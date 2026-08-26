function worker_loop(rootPath,resultQueue,testing)
% mabr.acq.worker_loop  Acquisition loop that runs ON a parpool worker.
%
%   worker_loop(rootPath,resultQueue,testing) is launched once per
%   session via parfeval on a 1-process parallel pool. It owns the
%   audioPlayerRecorder (ASIO, full-duplex) and streams pre-rendered stimulus
%   blocks, writing recorded samples into the shared memory-mapped ring
%   buffer. It is the modern replacement for the legacy headless "Background"
%   MATLAB process (abr.Runtime + acquire_block.m), but communicates over
%   parallel queues instead of the mabr_com.dat command/state memmap and the
%   dac.wav handoff.
%
%   Communication:
%       * resultQueue (worker -> client, a parallel.pool.DataQueue) carries
%         a one-time handshake, then State transitions and error reports.
%       * cmdQueue (client -> worker, a parallel.pool.PollableDataQueue that
%         this function creates and hands back in the handshake) carries
%         mabr.acq.Cmd messages, polled every frame with a 0 timeout so
%         Pause/Stop/Kill take effect within one frame.
%
%   Message shapes:
%       client -> worker : struct('cmd',mabr.acq.Cmd,'data',payload)
%           Prep payload  : struct with fields
%                 Plan              mabr.stim.PlayPlan -- the run's waveforms,
%                                   onsets, stimulus indices and polarities.
%                                   stream_block renders each frame from it
%                                   (Plan.range) as the device is ready, so no
%                                   whole play matrix ever crosses the queue
%                                   or sits in either process's memory.
%                 PlayMatrix        [N x 2] single (col1 signal, col2 timing),
%                                   accepted in place of Plan for hand-built
%                                   blocks (the timing self-test, the tests)
%                 SampleRate        (Hz)
%                 PlayerChannels    [1x2] device output channels  (default [1 2])
%                 RecorderChannels  [1x2] device input channels   (default [1 2])
%                 StimulationOnly   (optional) true = open an output-only
%                                   audioDeviceWriter and record nothing
%                 Device            (optional) ASIO device name
%       worker -> client : struct('type',...) — see send_* helpers below.
%
%   testing (logical) selects a hardware-free loopback mode (the DAC frame is
%   fed back as the ADC frame with a trace of noise), mirroring the legacy
%   Universal.MODE == abr.Cmd.Test path so the whole engine is testable with
%   no audio device present.
%
% Daniel Stolzberg (c) 2019-2026

% Ensure the worker process can resolve the +mabr namespace. Adding the repo
% root is sufficient (packages resolve from the folder containing +mabr); the
% cfg argument was already deserialized using the path set on the client side
% (see mabr.acq.Engine), so this is belt-and-suspenders for the body.
if ~isempty(rootPath) && isfolder(rootPath)
    addpath(rootPath);
end

% Build the config on the worker from constants (avoids serializing the
% value object across parfeval); both processes derive identical paths.
cfg = mabr.Config;

% Command channel: created here, handed back to the client.
cmdQueue = parallel.pool.PollableDataQueue;

send(resultQueue,struct('type','handshake', ...
    'cmdQueue',cmdQueue,'pid',feature('getpid')));

apr = [];
prepared = [];   % last Prep payload

try
    rb = mabr.acq.RingBuffer(cfg,true);   % writable
    send_state(resultQueue,mabr.acq.State.Idle);
    mabr.log.vprintf(1,'Worker loop started (testing = %d)',testing);

    running = true;
    while running
        % Block (with a short timeout) waiting for the next command.
        [msg,ok] = poll(cmdQueue,0.1);
        if ~ok, continue; end

        switch msg.cmd
            case mabr.acq.Cmd.Prep
                prepared = msg.data;
                apr = prepare_device(apr,prepared,testing);
                send_state(resultQueue,mabr.acq.State.Ready);

            case mabr.acq.Cmd.Run
                if isempty(prepared)
                    send_error(resultQueue,'mabr:acq:worker:notPrepared', ...
                        'Received Run before Prep.');
                    continue
                end
                [reason,nStreamed] = stream_block(cmdQueue,resultQueue,rb,apr,prepared,cfg,testing);
                % How much of the play matrix actually went out, and why the
                % block ended. Sent BEFORE the Completed state, so the client's
                % BlockCompleted handler already has it: with nothing recorded
                % (stimulation only) this is the only evidence of how far
                % through the planned sequence a stopped run got.
                send(resultQueue,struct('type','streamed', ...
                    'samples',nStreamed,'reason',reason));
                if strcmp(reason,'killed')
                    running = false;
                else
                    send_state(resultQueue,mabr.acq.State.Completed);
                end

            case mabr.acq.Cmd.Pause
                % No effect while idle.

            case mabr.acq.Cmd.Resume
                % No effect while idle: a Resume can only unpause a running
                % block (handled inside stream_block), never re-run one.

            case mabr.acq.Cmd.Stop
                send_state(resultQueue,mabr.acq.State.Ready);

            case mabr.acq.Cmd.Release
                % Hand the ASIO device back without tearing down the worker.
                % Clearing `prepared` too, so a later Run cannot stream against
                % a device that is no longer open -- it must Prep again, which
                % is what reopens it.
                if ~isempty(apr)
                    try, release(apr); end %#ok<TRYNC>
                    apr = [];
                end
                prepared = [];
                mabr.log.vprintf(1,'Worker released the audio device.');
                send_state(resultQueue,mabr.acq.State.Idle);

            case mabr.acq.Cmd.Kill
                running = false;
        end
    end

catch me
    send_error(resultQueue,me.identifier,me.message);
    mabr.log.vprintf(0,1,me);
end

% Cleanup
if ~isempty(apr)
    try, release(apr); end %#ok<TRYNC>
end
send_state(resultQueue,mabr.acq.State.Idle);
mabr.log.vprintf(1,'Worker loop exiting');
end


% =====================================================================
function [reason,nStreamed] = stream_block(cmdQueue,resultQueue,rb,apr,spec,cfg,testing)
% Stream one prepared block frame-by-frame. Returns 'completed', 'stopped',
% or 'killed', plus the number of play-matrix samples actually emitted --
% which is the whole matrix unless a Stop/Kill cut it short. Analogue of the
% legacy acquire_block.m tight loop.

fl  = cfg.frameLength;
src = mabr.stim.PlayPlan.fromSpec(spec);   % frames on demand -- never a whole matrix
N   = src.N;
% Loopback pacing. With no device there is no sample clock to throttle the
% loop, so without this the whole run streams as fast as the CPU can copy
% frames and the requested ISI means nothing in wall-clock terms. The client
% sets this to one frame's duration to make TESTING run at real time.
testDelay = getdef(spec,'TestingFrameDelay',0);
% Playback only: the device is an output-only audioDeviceWriter, so there is
% a real sample clock pacing the loop but no returned frame to record. The
% ring buffer is still reset below (harmless, and it keeps the write head
% honest for whatever runs next).
stimOnly  = getdef(spec,'StimulationOnly',false) && ~testing;

rb.reset();                    % new block: clear write head, bump BlockSeq
send_state(resultQueue,mabr.acq.State.Acquire);
if stimOnly, kind = 'stimulation-only block'; else, kind = 'block'; end
mabr.log.vprintf(1,'Streaming %s: %d samples (%d frames)',kind,N,ceil(N/fl));

reason = 'completed';
i = 1;
% Pace against a running deadline rather than pause()-per-frame: pause has
% millisecond-scale granularity on Windows and the frame work itself takes
% time, so a naive pause(testDelay) accumulates drift and runs slow.
paceOrigin = tic;
paceFrames = 0;
while i <= N
    % --- honor any pending command (non-blocking) -------------------------
    [msg,ok] = poll(cmdQueue,0);
    if ok
        switch msg.cmd
            case mabr.acq.Cmd.Stop, reason = 'stopped'; break
            case mabr.acq.Cmd.Kill, reason = 'killed';  break
            case mabr.acq.Cmd.Pause
                send_state(resultQueue,mabr.acq.State.Paused);
                term = wait_while_paused(cmdQueue);      % blocks until resumed/terminated
                if ~isempty(term), reason = term; break; end
                send_state(resultQueue,mabr.acq.State.Acquire);
                % Paused time is not owed back: restart the pacing clock so
                % the loop does not sprint to "catch up" after a resume.
                paceOrigin = tic;
                paceFrames = 0;
        end
    end

    % --- one frame --------------------------------------------------------
    hi    = min(i+fl-1,N);
    frame = src.range(i,hi);   % [n x 2] single: signal, timing

    if testing
        % Hardware-free loopback: DAC -> ADC with a trace of noise.
        audioADC = [frame(:,1) + randn(size(frame,1),1,'single')/1e6, frame(:,2)];
        rb.writeFrame(audioADC(:,1),audioADC(:,2));
    elseif stimOnly
        % Output only: both columns (signal AND timing pulse) go out, the
        % device clock paces the loop, and nothing comes back to record.
        nUnder = apr(frame);
        if nUnder, mabr.log.vprintf(0,'# Underruns = %d',nUnder); end
    else
        [audioADC,nUnder,nOver] = apr(frame);
        if nUnder, mabr.log.vprintf(0,'# Underruns = %d',nUnder); end
        if nOver,  mabr.log.vprintf(0,'# Overruns = %d',nOver);   end
        rb.writeFrame(audioADC(:,1),audioADC(:,2));
    end

    i = hi + 1;

    if testing && testDelay > 0
        paceFrames = paceFrames + 1;
        lag = paceFrames*testDelay - toc(paceOrigin);
        if lag > 0, pause(lag); end
    end
end

% i advanced past the last frame written, so i-1 is what went out. A Stop
% breaks before the frame is played, which is exactly what should NOT be
% counted as presented.
nStreamed = min(i-1,N);

mabr.log.vprintf(1,'Block %s (%d of %d samples, head = %d)', ...
    reason,nStreamed,N,rb.WriteHead);
end


% =====================================================================
function term = wait_while_paused(cmdQueue)
% Block in place while paused. Returns '' on resume (Run), or a terminal
% reason ('stopped'/'killed') if the block should end.
term = '';
while true
    [msg,ok] = poll(cmdQueue,0.05);
    if ~ok, continue; end
    switch msg.cmd
        case mabr.acq.Cmd.Resume, return
        case mabr.acq.Cmd.Stop,   term = 'stopped'; return
        case mabr.acq.Cmd.Kill,   term = 'killed';  return
    end
end
end


% =====================================================================
function apr = prepare_device(apr,spec,testing)
% Build/refresh the audio device for a prepared block. Three modes, in
% precedence order:
%
%   testing          no device at all (stream_block loops the DAC frame back)
%   StimulationOnly  an OUTPUT-ONLY audioDeviceWriter -- playback and the
%                    timing pulse, nothing recorded. A separate class rather
%                    than an audioPlayerRecorder whose input is ignored, so
%                    the mode also runs on hardware with no input channels.
%   otherwise        the full-duplex audioPlayerRecorder
%
% release() works for both device classes, so switching modes between runs
% needs nothing special here.
if testing
    apr = [];
    return
end

if ~isempty(apr) && isvalid(apr), release(apr); end

player   = getdef(spec,'PlayerChannels',  [1 2]);
recorder = getdef(spec,'RecorderChannels',[1 2]);
stimOnly = getdef(spec,'StimulationOnly', false);

if stimOnly
    % Driver must be named explicitly: audioDeviceWriter defaults to
    % DirectSound on Windows, where audioPlayerRecorder is ASIO-only. The
    % Device name here came off the ASIO device list (see
    % mabr.AudioSettings.availableDevices), so anything else would fail to
    % resolve it -- and DirectSound would not honour 192 kHz besides.
    args = {'SampleRate',spec.SampleRate, ...
            'Driver','ASIO', ...
            'ChannelMappingSource','Property', ...
            'ChannelMapping',player, ...
            'BitDepth','32-bit float'};
else
    args = {'SampleRate',spec.SampleRate, ...
            'PlayerChannelMapping',player, ...
            'RecorderChannelMapping',recorder, ...
            'BitDepth','32-bit float'};
end

if isfield(spec,'Device') && ~isempty(spec.Device)
    args = [args, {'Device',spec.Device}];
end

if stimOnly
    apr = audioDeviceWriter(args{:});
    mabr.log.vprintf(1,['Opened an OUTPUT-ONLY device (stimulation only): ' ...
        'play channels [%d %d], nothing recorded.'],player);
else
    apr = audioPlayerRecorder(args{:});
    mabr.log.vprintf(1,'Opened a full-duplex device: play [%d %d], record [%d %d].', ...
        player,recorder);
end
end


% =====================================================================
function v = getdef(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function send_state(q,state)
send(q,struct('type','state','state',state));
end

function send_error(q,id,msg)
send(q,struct('type','error','identifier',id,'message',msg));
end
