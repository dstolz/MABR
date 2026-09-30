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
%           'streamed' (once per block, before its Completed state):
%                 samples      play-matrix samples actually emitted
%                 reason       'completed' | 'stopped' | 'killed'
%                 underruns    samples of output the device ran dry for
%                 overruns     samples of input the device dropped
%                 underrunAt   [1 x k] play-matrix sample each was reported at
%                 overrunAt    [1 x k]
%                 (mabr.acq.Engine.LastStream holds it client-side)
%
%   testing (logical) selects TEST MODE, which the GUI names and documents as
%   such (mabr.ui.AudioSettingsDialog, and the wiki page it links to): no audio
%   device is opened, and each frame of the continuous stimulus is copied
%   straight into the acquisition ring buffer instead -- the DAC frame IS the
%   ADC frame, signal column and timing column alike.
%
%   That copy is the whole substance of the mode. Because the samples recorded
%   at an onset are by construction the samples the plan put there, a run in
%   Test Mode is a test of the correspondence everything else rests on: the
%   plan, the render, the timing channel, the ring buffer, sweep extraction and
%   the pairing of the k-th sweep with the k-th presentation all have to agree
%   or the recorded sweeps do not match their own stimuli.
%   mabr.ui.AcqController.alignmentCheck is what states the verdict.
%
%   It also mirrors the legacy Universal.MODE == abr.Cmd.Test path, so the
%   whole engine remains testable with no audio device present.
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
    if testing
        mabr.log.vprintf(1,['Worker loop started in TEST MODE -- no device will be ' ...
            'opened, and the stimulus is copied into the acquisition buffer.']);
    else
        mabr.log.vprintf(1,'Worker loop started.');
    end

    running = true;
    while running
        % Block (with a short timeout) waiting for the next command.
        [msg,ok] = poll(cmdQueue,0.1);
        if ~ok, continue; end

        % A command that fails fails THAT command, not the worker. Before this
        % catch existed, any error here (a device that would not open, most
        % often) ended the loop through the outer catch below, and the client
        % had no way to tell: its command queue still existed, so the next
        % Start was sent to a queue nothing read and sat in PrepBlock until
        % MABR was restarted. Here the error is reported, the block is
        % un-prepared (so a Run cannot stream against a half-built device),
        % and the loop goes back to waiting for the next Prep.
        try
            switch msg.cmd
                case mabr.acq.Cmd.Prep
                    apr = prepare_device(apr,msg.data,testing);
                    prepared = msg.data;
                    send_state(resultQueue,mabr.acq.State.Ready);

                case mabr.acq.Cmd.Run
                    if isempty(prepared)
                        send_error(resultQueue,'mabr:acq:worker:notPrepared', ...
                            'Received Run before Prep.');
                        continue
                    end
                    [reason,nStreamed,xr] = stream_block(cmdQueue,resultQueue,rb,apr,prepared,cfg,testing);
                    % How much of the play matrix actually went out, why the
                    % block ended, and what the device said about it (underruns
                    % and overruns, with where in the block each was reported).
                    % Sent BEFORE the Completed state, so the client's
                    % BlockCompleted handler already has it: with nothing recorded
                    % (stimulation only) this is the only evidence of how far
                    % through the planned sequence a stopped run got, and for a
                    % recorded run it is what lets a misaligned verdict name its
                    % likeliest cause (mabr.ui.AcqController.alignmentCheck).
                    send(resultQueue,struct('type','streamed', ...
                        'samples',nStreamed,'reason',reason, ...
                        'underruns',xr.underruns,'overruns',xr.overruns, ...
                        'underrunAt',xr.underrunAt,'overrunAt',xr.overrunAt));
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
        catch me
            prepared = [];
            send_error(resultQueue,me.identifier,me.message);
            mabr.log.vprintf(0,1,me);
            send_state(resultQueue,mabr.acq.State.Idle);
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
function [reason,nStreamed,xr] = stream_block(cmdQueue,resultQueue,rb,apr,spec,cfg,testing)
% Stream one prepared block frame-by-frame. Returns 'completed', 'stopped',
% or 'killed', plus the number of play-matrix samples actually emitted --
% which is the whole matrix unless a Stop/Kill cut it short. Analogue of the
% legacy acquire_block.m tight loop.
%
% xr is what the device reported while it ran, in the units it reports them
% in (samples): underruns (output it ran dry for -- silence is played, then
% the next frame, so everything after comes out late) and overruns (input it
% had nowhere to put -- recorded samples dropped), each with the play-matrix
% sample at which every event was reported (the start of the frame being
% handed over, so approximate to about a device buffer). Empty in Test Mode,
% where there is no device to say anything.

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
if testing,       kind = 'Test Mode block (stimulus -> acquisition buffer)';
elseif stimOnly,  kind = 'stimulation-only block';
else,             kind = 'block';
end
mabr.log.vprintf(1,'Streaming %s: %d samples (%d frames)',kind,N,ceil(N/fl));

reason = 'completed';
xr = struct('underruns',0,'overruns',0,'underrunAt',zeros(1,0),'overrunAt',zeros(1,0));
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
        % TEST MODE: the stimulus frame IS the acquired frame. Both columns
        % are copied -- the timing column too, so onset recovery runs over
        % exactly the pulses the plan rendered rather than a synthesized
        % substitute for them.
        %
        % The dither is ~1e-6 of full scale (below any converter's noise
        % floor, and four orders under the tolerance alignmentCheck compares
        % at) and is there so a loopback run is not perfectly degenerate: with
        % a bit-exact copy every sweep of a condition is identical, its
        % standard deviation is exactly zero and its correlation exactly one,
        % which makes the live view's error bands and the correlation advance
        % criterion untestable in the one mode built for testing them.
        audioADC = [frame(:,1) + randn(size(frame,1),1,'single')/1e6, frame(:,2)];
        rb.writeFrame(audioADC(:,1),audioADC(:,2));
    elseif stimOnly
        % Output only: both columns (signal AND timing pulse) go out, the
        % device clock paces the loop, and nothing comes back to record.
        nUnder = apr(frame);
        xr = note_xruns(xr,nUnder,0,i,spec.SampleRate);
    else
        [audioADC,nUnder,nOver] = apr(frame);
        xr = note_xruns(xr,nUnder,nOver,i,spec.SampleRate);
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
function xr = note_xruns(xr,nUnder,nOver,at,fs)
% Log and keep what the device reported for the frame starting at play-matrix
% sample `at`. Both counts are in samples, and an event is kept with WHERE it
% was reported so a misaligned verdict can say whether the jump it found is
% the one the device owned up to (mabr.metrics.alignment_report).
if nUnder
    xr.underruns = xr.underruns + double(nUnder);
    xr.underrunAt(end+1) = at;
    mabr.log.vprintf(0,'# Underruns = %d (at %.2f s into the block)', ...
        nUnder,(at-1)/fs);
end
if nOver
    xr.overruns = xr.overruns + double(nOver);
    xr.overrunAt(end+1) = at;
    mabr.log.vprintf(0,'# Overruns = %d (at %.2f s into the block)', ...
        nOver,(at-1)/fs);
end
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
%   testing          TEST MODE -- no device at all; stream_block copies the
%                    stimulus frame into the acquisition ring buffer
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
    apr = open_device(@audioDeviceWriter,args);
    mabr.log.vprintf(1,['Opened an OUTPUT-ONLY device (stimulation only): ' ...
        'play channels [%d %d], nothing recorded.'],player);
else
    apr = open_device(@audioPlayerRecorder,args);
    mabr.log.vprintf(1,'Opened a full-duplex device: play [%d %d], record [%d %d].', ...
        player,recorder);
end
end


% =====================================================================
function apr = open_device(ctor,args)
% Construct the device, retrying a read of the preferences file that landed
% in the middle of somebody else's write.
%
% Opening an audio device reads matlabprefs.mat -- the DSP System Toolbox's
% device lookup (dspAudioDeviceInfo) asks for dsp/portaudioHostApi -- and
% every worker in a local pool shares that one file with the GUI process.
% MATLAB's preference functions take no lock: a setpref in the GUI (a window
% closed, an analysis setting changed) rewrites the whole file, and a read
% that lands inside the rewrite sees a truncated MAT-file and throws
% MATLAB:load:notBinaryFile out of the constructor. Every Prep opens the
% device afresh, so this is one chance per run. The write takes
% milliseconds; waiting it out is the whole fix. Anything else, or a file
% still unreadable after the last try, is the caller's error as before.
tries = 5;
for k = 1:tries
    try
        apr = ctor(args{:});
        return
    catch me
        if k == tries || ~startsWith(me.identifier,'MATLAB:load:')
            rethrow(me);
        end
        mabr.log.vprintf(1,1,['Opening the audio device could not read the ' ...
            'preferences file (%s); another MATLAB process was probably ' ...
            'writing it. Retrying (%d of %d).'],me.message,k,tries-1);
        pause(0.1*k);
    end
end
end

function v = getdef(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function send_state(q,state)
send(q,struct('type','state','state',state));
end

function send_error(q,id,msg)
send(q,struct('type','error','identifier',id,'message',msg));
end
