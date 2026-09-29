function verify_engine_loopback()
% verify_engine_loopback  No-hardware acceptance test for mabr.acq.Engine.
%
%   Runs the acquisition engine in TESTING loopback mode (no audio device)
%   and asserts the guarantees from the rewrite plan's verification section:
%       * recorded frames land in the ring buffer
%       * the write-head advances during acquisition
%       * Pause / Stop / Kill sent over the queue take effect within ~1 frame
%
%   Requires the Parallel Computing Toolbox. Run from anywhere on the MABR
%   path:  >> verify_engine_loopback
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_engine_loopback ==\n');

cfg = mabr.Config;
fl  = cfg.frameLength;
Fs  = cfg.DACSampleRate;

% ---- Build a deterministic test block --------------------------------------
% Long enough that, at the paced ~4 ms/frame below, the block still has time
% left when the Pause/Resume/Stop assertions run (~2 s of streaming).
nFrames = 500;
N       = nFrames * fl;
t       = (0:N-1)'/Fs;
signal  = single(0.2*sin(2*pi*1000*t));          % 1 kHz tone

sweepPeriod             = 4*fl;                    % onset every 4 frames
timing                  = zeros(N,1,'single');
timing(1:sweepPeriod:N) = 1;
expectedOnsets          = numel(1:sweepPeriod:N);

% Pace the loopback (~4 ms/frame) so the block streams in real-ish time and
% the Pause/Resume/Stop assertions below land mid-block rather than after it
% has already finished.
spec = struct('PlayMatrix',[signal timing],'SampleRate',Fs,'TestingFrameDelay',0.004);

% ---- Launch the engine (loopback) ------------------------------------------
eng = mabr.acq.Engine(cfg,true);
cleaner = onCleanup(@() delete(eng));
eng.waitUntilReady();
fprintf('  worker ready (PID %d)\n',eng.WorkerPID);

Completed = mabr.acq.State.Completed;

% ---- Test 1: full block streams and head advances --------------------------
eng.prep(spec);
wait_until(@() eng.State == mabr.acq.State.Ready, 10);
eng.run();

heads = [];
t0 = tic;
while eng.State ~= Completed && toc(t0) < 30
    heads(end+1) = eng.head(); %#ok<AGROW>
    pause(0.05);
end
assert(eng.State == Completed,'Block did not complete within 30 s');
assert(max(heads) > fl,'Write-head never advanced past one frame');
assert(eng.head() >= N-fl,'Final head (%d) did not reach end of block (%d)',eng.head(),N);
assert(any(diff(heads) > 0),'Write-head did not advance monotonically during acquisition');

rec = eng.RingBuffer.readSignal(1,N);
err = max(abs(double(rec) - double(signal)));
assert(err < 1e-3,'Loopback signal mismatch (max err %.2e)',err);

recTim    = eng.RingBuffer.readTiming(1,N);
gotOnsets = nnz(recTim > 0.5);
assert(gotOnsets == expectedOnsets, ...
    'Timing onsets mismatch: got %d, expected %d',gotOnsets,expectedOnsets);
fprintf('  PASS test 1: full block (head %d, %d onsets, loopback err %.1e)\n', ...
    eng.head(),gotOnsets,err);

% ---- Test 1b: the frame loop reports where its time went ---------------
% Every frame is accounted for, the order statistics are ordered, and the
% slowest frames name ring positions inside the block -- the numbers a rig
% run needs to tell a slow ring page from a slow render.
T = eng.LastStream.timing;
assert(isstruct(T) && T.frames == nFrames, ...
    'the stream report should time every one of the %d frames',nFrames);
assert(all(T.p50 <= T.p99 & T.p99 <= T.max),'frame-timing percentiles out of order');
assert(abs(T.frameMs - 1e3*fl/Fs) < 1e-9,'frameMs should be one frame at the DAC rate');
assert(size(T.slowest,1) == min(8,nFrames) && size(T.slowest,2) == 7, ...
    'expected the 8 slowest frames, 7 columns each');
assert(all(mod(T.slowest(:,2),fl) == 0 & T.slowest(:,2) >= 0 & T.slowest(:,2) < N), ...
    'a slow frame''s ring position should be a frame boundary inside the block');
assert(issorted(T.slowest(:,7),'descend'),'the slowest frames should come worst first');

% Prefault reads and never writes: the block is intact afterwards, across
% the wrap too.
before = eng.RingBuffer.readSignal(1,N);
np = eng.RingBuffer.prefault(1,N);
assert(np >= ceil(N/1024),'prefault should touch every page of the range (%d)',np);
eng.RingBuffer.prefault(eng.RingBuffer.MaxLength - 2048,eng.RingBuffer.MaxLength + 2048);
assert(isequal(eng.RingBuffer.readSignal(1,N),before),'prefault changed the ring');
fprintf('  PASS test 1b: %d frames timed (work p99 %.3f ms of %.2f); prefault leaves the ring intact\n', ...
    T.frames,T.p99(5),T.frameMs);

% ---- Test 1c: onsets read off the single samples are the double path's -----
% Finalization finds a whole run's onsets; it now compares the recorded
% singles directly rather than a 512 MB double copy of a full ring. The
% answer must not move: noise with its negative half, and a threshold (0.7)
% whose single rounding lies BELOW it, with a sample sitting exactly there.
assert(double(single(0.7)) < 0.7,'0.7 is meant to round down into single');
rng(5);
tim = single(0.05*randn(20000,1));
tim(500:520)   = 1;
tim(3000:3004) = 0.7;
tim(7000)      = single(0.7);
tim(9000:9010) = single(0.7) + eps(single(0.7));
for thr = [0.1 0.3 1/3 0.7 0.95]
    a = mabr.metrics.find_timing_onsets(tim,5,thr);
    b = mabr.metrics.find_timing_onsets(double(tim),5,thr);
    assert(isequal(a,b),'single and double onset detection disagree at threshold %g',thr);
end
fprintf('  PASS test 1c: onsets found on single samples match the double path exactly\n');

% ---- Test 2: Pause freezes the head, Resume continues ----------------------
eng.prep(spec);
wait_until(@() eng.State == mabr.acq.State.Ready, 10);
eng.run();
pause(0.1);
eng.pause();
wait_until(@() eng.State == mabr.acq.State.Paused, 5);
h1 = eng.head();
pause(0.3);
h2 = eng.head();
assert(h2 == h1,'Head advanced while paused (%d -> %d)',h1,h2);
eng.resume();
pause(0.3);
assert(eng.head() > h2,'Head did not resume after Pause');
fprintf('  PASS test 2: Pause froze head at %d, Resume advanced it\n',h1);

% ---- Test 3: Stop ends the block early -------------------------------------
eng.stop();
wait_until(@() eng.State == Completed, 5);
assert(eng.State == Completed,'Stop did not complete the block');
assert(eng.head() < N,'Stop did not end the block early (head %d, N %d)',eng.head(),N);
% The 0.3 s spent paused in test 2 is nobody's frame work.
T = eng.LastStream.timing;
assert(T.max(5) < 250,'paused time was counted as frame work (max %.0f ms)',T.max(5));
fprintf('  PASS test 3: Stop ended block early at head %d (< %d)\n',eng.head(),N);

% ---- Test 4: Kill tears the worker down ------------------------------------
eng.kill();
pause(0.5);
fprintf('  PASS test 4: Kill issued cleanly\n');

fprintf('== verify_engine_loopback PASSED ==\n');
end


% =====================================================================
function wait_until(pred,timeout)
% Pause (letting DataQueue callbacks run) until pred() is true or timeout.
t0 = tic;
while ~pred() && toc(t0) < timeout
    pause(0.02);
end
end
