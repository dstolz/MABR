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
%                 IdleClockSeconds  (optional, default 10) how long a device
%                                   kept open after a run is kept clocked
%                                   before its stream is stopped (idle_frame)
%                 DeviceFactory     (optional, TESTS ONLY) constructor to use
%                                   in place of the device class
%       worker -> client : struct('type',...) — see send_* helpers below.
%           'streamed' (once per block, before its Completed state):
%                 samples      play-matrix samples actually emitted
%                 reason       'completed' | 'stopped' | 'killed'
%                 underruns    samples of output the device ran dry for
%                 overruns     samples of input the device dropped
%                 underrunAt   [1 x k] play-matrix sample each was reported at
%                 overrunAt    [1 x k]
%                 timing       where the frame loop's time went -- percentiles
%                              per stage and the slowest frames with their
%                              ring positions (see summarize_frames)
%                 deviceOpens  devices this worker has constructed so far
%                              (the same number from run to run = reused)
%                 idleFrames   silent frames the device this block streamed
%                              on was kept clocked with before it (0 for a
%                              device opened for this block)
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
aprSig = '';     % what apr was built for (see prepare_device): reused while unchanged
nOpened = 0;     % devices constructed this session -- reported with every block
prepared = [];   % last Prep payload
% A device kept open between runs is kept CLOCKED: see idle_frame.
idle = struct('clocking',false,'since',tic,'limit',10,'duplex',true, ...
              'frames',0,'under',0,'over',0);

try
    rb = mabr.acq.RingBuffer(cfg,true);   % writable
    % Bring the whole ring into memory now, while nothing is streaming. The
    % ring is a file-backed map written one 4 KiB page per channel per frame,
    % and a page not yet resident has to be faulted in -- from disk, when it
    % is cold -- by the streaming loop itself, synchronously. Long runs on
    % the rig showed one-frame underruns spaced at whole MiB of ring written
    % (a run that fits in the first few MiB, which every run rewrites, never
    % did). Prep repeats this over the run's own range.
    t0 = tic;
    rb.prefault();
    mabr.log.vprintf(2,'Ring buffer prefaulted (%.0f MiB) in %.2f s', ...
        2*rb.MaxLength*4/2^20,toc(t0));
    send_state(resultQueue,mabr.acq.State.Idle);
    if testing
        mabr.log.vprintf(1,['Worker loop started in TEST MODE -- no device will be ' ...
            'opened, and the stimulus is copied into the acquisition buffer.']);
    else
        mabr.log.vprintf(1,'Worker loop started.');
    end

    running = true;
    while running
        if idle.clocking
            % An open device between runs: one frame of silence (which is
            % also what paces this loop), then a look at the queue without
            % waiting. After idle.limit seconds with nothing to do, stop the
            % stream -- the next run then starts it again, which is what
            % every run used to pay.
            [idle,apr] = idle_frame(apr,idle,cfg.frameLength);
            [msg,ok] = poll(cmdQueue,0);
            if ~ok && idle.clocking && toc(idle.since) > idle.limit
                try, release(apr); end %#ok<TRYNC>
                idle.clocking = false;
                mabr.log.vprintf(2,'Audio device idle for %g s: stream stopped (%d idle frames).', ...
                    idle.limit,idle.frames);
            end
        else
            % Block (with a short timeout) waiting for the next command.
            [msg,ok] = poll(cmdQueue,0.1);
        end
        if ~ok, continue; end

        switch msg.cmd
            case mabr.acq.Cmd.Prep
                prepared = msg.data;
                [apr,aprSig,opened] = prepare_device(apr,aprSig,prepared,testing);
                if opened
                    % A new device starts its stream at the first frame, and
                    % what the old one's idle stream went through is not
                    % this device's history.
                    nOpened = nOpened + 1;
                    idle.clocking = false;
                    idle.frames = 0; idle.under = 0; idle.over = 0;
                end
                idle.limit  = getdef(prepared,'IdleClockSeconds',10);
                idle.duplex = ~getdef(prepared,'StimulationOnly',false);
                % Every run writes the ring from its start, so these are
                % the pages it is about to write: touch them here, between
                % runs, rather than one at a time inside the frame loop
                % (resident pages cost microseconds; see the start-up call).
                rb.prefault(1,mabr.stim.PlayPlan.fromSpec(prepared).N);
                % The Prep work above was time the idle stream went unfed;
                % one more frame now takes whatever the device has to say
                % about it, so it is not reported as the run's first frame.
                if idle.clocking, [idle,apr] = idle_frame(apr,idle,cfg.frameLength); end
                send_state(resultQueue,mabr.acq.State.Ready);

            case mabr.acq.Cmd.Run
                if isempty(prepared)
                    send_error(resultQueue,'mabr:acq:worker:notPrepared', ...
                        'Received Run before Prep.');
                    continue
                end
                % What the idle stream went through since the last run is
                % the stream's business, not this run's.
                idleFrames = idle.frames;
                if idle.under > 0 || idle.over > 0
                    mabr.log.vprintf(2,'Between runs (%d idle frames): %d samples of underrun, %d of overrun.', ...
                        idle.frames,idle.under,idle.over);
                end
                idle.frames = 0; idle.under = 0; idle.over = 0;
                [reason,nStreamed,xr,timing] = stream_block(cmdQueue,resultQueue,rb,apr,prepared,cfg,testing);
                % Keep the device clocked until the next run, so that run
                % starts on the next frame of a stream already running
                % rather than paying the device's start-up (a quarter to
                % half a second a run on the reference rig) -- and with the
                % same round-trip latency as this one.
                if ~isempty(apr) && ~strcmp(reason,'killed')
                    idle.clocking = true;
                    idle.since    = tic;
                end
                % How much of the play matrix actually went out, why the
                % block ended, and what the device said about it (underruns
                % and overruns, with where in the block each was reported).
                % Sent BEFORE the Completed state, so the client's
                % BlockCompleted handler already has it: with nothing recorded
                % (stimulation only) this is the only evidence of how far
                % through the planned sequence a stopped run got, and for a
                % recorded run it is what lets a misaligned verdict name its
                % likeliest cause (mabr.ui.AcqController.alignmentCheck).
                % `timing` is where the frame loop's own time went (see
                % summarize_frames).
                send(resultQueue,struct('type','streamed', ...
                    'samples',nStreamed,'reason',reason, ...
                    'underruns',xr.underruns,'overruns',xr.overruns, ...
                    'underrunAt',xr.underrunAt,'overrunAt',xr.overrunAt, ...
                    'timing',timing,'deviceOpens',nOpened,'idleFrames',idleFrames));
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
                aprSig = '';
                idle.clocking = false;
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
function [reason,nStreamed,xr,timing] = stream_block(cmdQueue,resultQueue,rb,apr,spec,cfg,testing)
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
% where there is no device to say anything. Nothing is LOGGED from inside
% the loop: a logged line costs a stack walk and a file write, and an
% underrun is exactly the moment the loop has no time to spare. One summary
% goes out after the block (log_block_report).
%
% timing is where each frame's time went, measured with a few tic/tocs a
% frame (microseconds against a 5.3 ms frame): see summarize_frames.

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
% Per frame, in ms: command poll, frame render, device call, ring write, and
% the whole iteration. Preallocated -- nothing in the loop may grow.
ft = zeros(ceil(N/fl),5,'single');
nf = 0;
% Pace against a running deadline rather than pause()-per-frame: pause has
% millisecond-scale granularity on Windows and the frame work itself takes
% time, so a naive pause(testDelay) accumulates drift and runs slow.
paceOrigin = tic;
paceFrames = 0;
while i <= N
    tIter = tic;
    % --- honor any pending command (non-blocking) -------------------------
    [msg,ok] = poll(cmdQueue,0);
    dPoll = toc(tIter);
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
                % ...nor is it this frame's work.
                tIter = tic;
                dPoll = 0;
        end
    end

    % --- one frame --------------------------------------------------------
    hi    = min(i+fl-1,N);
    t     = tic;
    frame = src.range(i,hi);   % [n x 2] single: signal, timing
    dRender = toc(t);
    dDev    = 0;

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
        t = tic;
        rb.writeFrame(audioADC(:,1),audioADC(:,2));
        dRing = toc(t);
    elseif stimOnly
        % Output only: both columns (signal AND timing pulse) go out, the
        % device clock paces the loop, and nothing comes back to record.
        t = tic;
        nUnder = apr(frame);
        dDev = toc(t);
        xr = note_xruns(xr,nUnder,0,i);
        dRing = 0;
    else
        t = tic;
        [audioADC,nUnder,nOver] = apr(frame);
        dDev = toc(t);
        xr = note_xruns(xr,nUnder,nOver,i);
        t = tic;
        rb.writeFrame(audioADC(:,1),audioADC(:,2));
        dRing = toc(t);
    end

    i  = hi + 1;
    nf = nf + 1;
    ft(nf,:) = 1e3*[dPoll dRender dDev dRing toc(tIter)];

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

timing = summarize_frames(ft(1:nf,:),fl,spec.SampleRate);
log_block_report(xr,timing,spec.SampleRate);
end


% =====================================================================
function xr = note_xruns(xr,nUnder,nOver,at)
% Keep what the device reported for the frame starting at play-matrix sample
% `at`. Both counts are in samples, and an event is kept with WHERE it was
% reported so a misaligned verdict can say whether the jump it found is the
% one the device owned up to (mabr.metrics.alignment_report). Called inside
% the frame loop, so it only accumulates: log_block_report says it all once
% the block is over.
if nUnder
    xr.underruns = xr.underruns + double(nUnder);
    xr.underrunAt(end+1) = at;
end
if nOver
    xr.overruns = xr.overruns + double(nOver);
    xr.overrunAt(end+1) = at;
end
end


% =====================================================================
function T = summarize_frames(ft,fl,fs)
% Where the frame loop's time went. ft is [nFrames x 5] ms per frame: command
% poll, frame render, device call, ring write, whole iteration. The device
% call is where the loop WAITS -- the device paces it -- so what can make an
% underrun is everything else, `work` below: if one frame's work outlasts the
% device's buffered slack, the output runs dry.
%
%   T.frames     frames streamed           T.frameMs  one frame's duration
%   T.columns    {'poll','render','device','ring','work'}
%   T.p50 T.p99 T.max   [1 x 5] ms, in the order of columns
%   T.slowest    [k x 7], the (up to) 8 frames with the most work, worst
%                first: frame, ring sample it started at (0-based, which is
%                also its play-matrix offset -- every block writes the ring
%                from its start), then the five columns in ms
T = struct('frames',0,'frameMs',1e3*fl/fs, ...
    'columns',{{'poll','render','device','ring','work'}}, ...
    'p50',zeros(1,5),'p99',zeros(1,5),'max',zeros(1,5),'slowest',zeros(0,7));
n = size(ft,1);
T.frames = n;
if n == 0, return; end
X = double([ft(:,1:4), ft(:,5) - ft(:,3)]);
S = sort(X,1);
T.p50 = S(max(1,ceil(0.50*n)),:);
T.p99 = S(max(1,ceil(0.99*n)),:);
T.max = S(n,:);
[~,ord] = sort(X(:,5),'descend');
k = ord(1:min(8,n));
T.slowest = [k(:), (k(:)-1)*fl, X(k,:)];
end


% =====================================================================
function log_block_report(xr,T,fs)
% What the device reported and where the loop's time went, once per block.
%
% Every block writes the ring from its start, so a play-matrix sample is also
% a ring position, and each event is reported with its offset into the MiB of
% ring (2^18 single-precision samples) it fell in. Underruns on long rig runs
% came at whole-MiB spacings; an offset that is always a frame or two says the
% ring's pages are the cause, one scattered at random says something else is.
perMiB = 2^18;
where  = @(at) strjoin(arrayfun(@(a) sprintf('%.2f s (+%d)',(a-1)/fs, ...
    mod(a-1,perMiB)),at(1:min(end,10)),'UniformOutput',false),', ');
if xr.underruns > 0
    mabr.log.vprintf(0,'# Underruns: %d samples in %d event(s), at %s -- s into the block (samples into its MiB of ring)', ...
        xr.underruns,numel(xr.underrunAt),where(xr.underrunAt));
end
if xr.overruns > 0
    mabr.log.vprintf(0,'# Overruns: %d samples in %d event(s), at %s -- s into the block (samples into its MiB of ring)', ...
        xr.overruns,numel(xr.overrunAt),where(xr.overrunAt));
end
if T.frames == 0, return; end
% Loud when a frame's work came within half a frame of the budget, or the
% device complained; otherwise a detail line.
worst = T.max(5);
level = 2;
if worst > 0.5*T.frameMs || xr.underruns > 0 || xr.overruns > 0, level = 1; end
mabr.log.vprintf(level, ['Frame timing, %d frames of %.2f ms: work (all but the device call) ' ...
    'p50 %.2f / p99 %.2f / max %.2f ms; device call p50 %.2f / max %.2f; ring write max %.2f ' ...
    '(render %.2f, poll %.2f)'],T.frames,T.frameMs,T.p50(5),T.p99(5),worst, ...
    T.p50(3),T.max(3),T.max(4),T.max(2),T.max(1));
if level == 1
    s = T.slowest(1:min(3,end),:);
    mabr.log.vprintf(1,'  slowest frames: %s', strjoin(arrayfun(@(r) sprintf( ...
        '%.2f s (+%d into its MiB): ring %.2f, render %.2f, poll %.2f ms', ...
        s(r,2)/fs,mod(s(r,2),perMiB),s(r,6),s(r,4),s(r,3)),1:size(s,1), ...
        'UniformOutput',false),'; '));
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
function [apr,sig,opened] = prepare_device(apr,sig,spec,testing)
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
% The device is REUSED while nothing it was built from has changed -- `sig`
% is the constructor and every argument it was given -- and a device kept
% between runs is kept clocked (idle_frame), so the next run starts on the
% next frame of a stream already running. Every Prep used to release the
% device and build a new one, and the new one paid the driver's start-up on
% the run's first frame. Change the mode, the device, the rate or a channel
% and it is rebuilt as before. `opened` says which happened.
%
% release() works for both device classes, so switching modes between runs
% needs nothing special here.
opened = false;
if testing
    apr = []; sig = '';
    return
end

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

% The class to build: the real device, or -- for tests only; nothing on a
% rig sets it -- a stand-in with the same calling convention
% (mabrtest.FakeAudioDevice), which is how the suite, run in Test Mode where
% no device is opened at all, can still see a device being kept.
ctor = getdef(spec,'DeviceFactory',[]);
if isempty(ctor)
    if stimOnly, ctor = @audioDeviceWriter; else, ctor = @audioPlayerRecorder; end
end

newSig = [func2str(ctor) '|' jsonencode(args)];
if ~isempty(apr) && isvalid(apr) && strcmp(newSig,sig)
    return                            % the device this run needs is the one open
end
if ~isempty(apr) && isvalid(apr), release(apr); end

apr    = ctor(args{:});
sig    = newSig;
opened = true;
if stimOnly
    mabr.log.vprintf(1,['Opened an OUTPUT-ONLY device (stimulation only): ' ...
        'play channels [%d %d], nothing recorded.'],player);
else
    mabr.log.vprintf(1,'Opened a full-duplex device: play [%d %d], record [%d %d].', ...
        player,recorder);
end
end


% =====================================================================
function [idle,apr] = idle_frame(apr,idle,fl)
% One frame of silence into a device kept open between runs (see the main
% loop). Keeping the stream running is what lets the next run start on the
% next frame, without the device's start-up and at the same round-trip
% latency as the last. The recorded input is discarded, and what the device
% reports goes into idle's own tallies, never into a run's. A device that
% fails here is released and dropped, so the next Prep builds a fresh one
% rather than the error ending the worker.
silence = zeros(fl,2,'single');
try
    if idle.duplex
        [~,nU,nO] = apr(silence);
    else
        nU = apr(silence);
        nO = 0;
    end
    idle.frames = idle.frames + 1;
    idle.under  = idle.under + double(nU);
    idle.over   = idle.over + double(nO);
catch me
    mabr.log.vprintf(0,1,['The audio device failed while idle between runs (%s); ' ...
        'it will be opened again for the next run.'],me.message);
    try, release(apr); end %#ok<TRYNC>
    apr = [];
    idle.clocking = false;
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
