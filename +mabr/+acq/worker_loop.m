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
%                 PlayMatrix        [N x 2] single (col1 signal, col2 timing)
%                 SampleRate        (Hz)
%                 PlayerChannels    [1x2] device output channels  (default [1 2])
%                 RecorderChannels  [1x2] device input channels   (default [1 2])
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
                reason = stream_block(cmdQueue,resultQueue,rb,apr,prepared,cfg,testing);
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
function reason = stream_block(cmdQueue,resultQueue,rb,apr,spec,cfg,testing)
% Stream one prepared block frame-by-frame. Returns 'completed', 'stopped',
% or 'killed'. Analogue of the legacy acquire_block.m tight loop.

fl = cfg.frameLength;
X  = spec.PlayMatrix;          % [N x 2] single
N  = size(X,1);
% Loopback pacing. With no device there is no sample clock to throttle the
% loop, so without this the whole run streams as fast as the CPU can copy
% frames and the requested ISI means nothing in wall-clock terms. The client
% sets this to one frame's duration to make TESTING run at real time.
testDelay = getdef(spec,'TestingFrameDelay',0);

rb.reset();                    % new block: clear write head, bump BlockSeq
send_state(resultQueue,mabr.acq.State.Acquire);
mabr.log.vprintf(1,'Streaming block: %d samples (%d frames)',N,ceil(N/fl));

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
    frame = X(i:hi,:);

    if testing
        % Hardware-free loopback: DAC -> ADC with a trace of noise.
        audioADC = [frame(:,1) + randn(size(frame,1),1,'single')/1e6, frame(:,2)];
    else
        [audioADC,nUnder,nOver] = apr(frame);
        if nUnder, mabr.log.vprintf(0,'# Underruns = %d',nUnder); end
        if nOver,  mabr.log.vprintf(0,'# Overruns = %d',nOver);   end
    end

    rb.writeFrame(audioADC(:,1),audioADC(:,2));
    i = hi + 1;

    if testing && testDelay > 0
        paceFrames = paceFrames + 1;
        lag = paceFrames*testDelay - toc(paceOrigin);
        if lag > 0, pause(lag); end
    end
end

mabr.log.vprintf(1,'Block %s (head = %d)',reason,rb.WriteHead);
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
% Build/refresh the audioPlayerRecorder for a prepared block. In testing
% mode no device is created.
if testing
    apr = [];
    return
end

if ~isempty(apr) && isvalid(apr), release(apr); end

player   = getdef(spec,'PlayerChannels',  [1 2]);
recorder = getdef(spec,'RecorderChannels',[1 2]);

args = {'SampleRate',spec.SampleRate, ...
        'PlayerChannelMapping',player, ...
        'RecorderChannelMapping',recorder, ...
        'BitDepth','32-bit float'};

if isfield(spec,'Device') && ~isempty(spec.Device)
    args = [args, {'Device',spec.Device}];
end

apr = audioPlayerRecorder(args{:});
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
