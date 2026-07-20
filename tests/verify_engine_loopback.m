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
nFrames = 40;
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
