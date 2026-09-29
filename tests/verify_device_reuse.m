function verify_device_reuse()
% verify_device_reuse  The acquisition worker keeps its audio device open --
%                      and clocked -- between runs, and builds a new one only
%                      when it has to.
%
%   Every Prep used to release the device and construct another, and the new
%   one paid the driver's start-up on the first frame of every run: a quarter
%   to half a second a run on the reference rig, plus a read of the shared
%   preferences file each time. mabr.acq.worker_loop now reuses the device
%   while nothing it was built from has changed, and feeds it silence between
%   runs so the next run starts on the next frame of a stream already running.
%
%   The suite runs in Test Mode, where no device is opened at all, so this
%   runs a real (not Test Mode) worker over mabrtest.FakeAudioDevice -- the
%   same arguments and the same calls as audioPlayerRecorder, a loop-back
%   paced at the device's rate -- chosen through the spec's DeviceFactory:
%
%   Part A: three runs with unchanged settings build ONE device, the stream
%           is clocked between them, and every run's recording is intact.
%   Part B: a changed setting (the player channels) builds a new device.
%   Part C: Release drops the device; the next Prep builds another.
%   Part D: after IdleClockSeconds with nothing to do the stream stops (the
%           device is kept), and the next run starts it again.
%
%   Requires the Parallel Computing Toolbox. No audio hardware.
%   Run:  >> verify_device_reuse
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_device_reuse ==\n');

cfg = mabr.Config;
fl  = cfg.frameLength;
Fs  = cfg.DACSampleRate;

N      = 40*fl;
t      = (0:N-1)'/Fs;
signal = single(0.2*sin(2*pi*1000*t));
timing = zeros(N,1,'single');
timing(1:4*fl:N) = 1;
spec = struct('PlayMatrix',[signal timing],'SampleRate',Fs, ...
    'DeviceFactory',@mabrtest.FakeAudioDevice,'IdleClockSeconds',30);

eng = mabr.acq.Engine(cfg,false);          % NOT Test Mode: a device is opened
cleaner = onCleanup(@() delete(eng)); %#ok<NASGU>
eng.waitUntilReady();

% ---- Part A: one device across unchanged runs, clocked in between ------
opens = zeros(1,3); idleF = zeros(1,3);
for k = 1:3
    run_block(eng,spec);
    s = eng.LastStream;
    opens(k) = s.deviceOpens;
    idleF(k) = s.idleFrames;
    rec = eng.RingBuffer.readSignal(1,N);
    assert(isequal(rec,signal),'run %d: the recording does not match what was played',k);
    pause(0.3);                            % the gap a finalize takes, roughly
end
assert(all(opens == 1),'unchanged settings should reuse one device (opens %s)',mat2str(opens));
assert(idleF(1) == 0 && all(idleF(2:3) > 10), ...
    'the device should be clocked between runs, not before the first (idle frames %s)',mat2str(idleF));
fprintf('  PASS Part A: 3 runs, 1 device; clocked between them (%s idle frames)\n',mat2str(idleF(2:3)));

% ---- Part B: a changed setting rebuilds ----------------------------------
spec2 = spec; spec2.PlayerChannels = [2 1];
run_block(eng,spec2);
assert(eng.LastStream.deviceOpens == 2,'a changed channel map should build a new device');
assert(eng.LastStream.idleFrames == 0,'a new device has no idle stream behind it');
run_block(eng,spec2);
assert(eng.LastStream.deviceOpens == 2,'...and then keep that one');
fprintf('  PASS Part B: a changed setting builds a new device, then keeps it\n');

% ---- Part C: Release drops it ---------------------------------------------
eng.releaseDevice();
wait_until(@() eng.State == mabr.acq.State.Idle,10);
run_block(eng,spec2);
assert(eng.LastStream.deviceOpens == 3,'after Release the next Prep should build again');
fprintf('  PASS Part C: Release drops the device; the next run opens another\n');

% ---- Part D: an idle stream stops after IdleClockSeconds -----------------
spec3 = spec2; spec3.IdleClockSeconds = 0.2;
run_block(eng,spec3);                      % arms the short limit
pause(1.0);                                % ~5x the limit
run_block(eng,spec3);
s = eng.LastStream;
maxIdle = ceil(0.6*Fs/fl);                 % 0.2 s of frames, with room to spare
assert(s.deviceOpens == 3,'a stopped stream keeps its device (opens %d)',s.deviceOpens);
assert(s.idleFrames > 0 && s.idleFrames < maxIdle, ...
    'the idle stream should have stopped after 0.2 s (%d idle frames in 1 s)',s.idleFrames);
assert(isequal(eng.RingBuffer.readSignal(1,N),signal),'the restarted stream recorded wrongly');
fprintf('  PASS Part D: idle stream stopped after its limit (%d frames), device kept and restarted\n', ...
    s.idleFrames);

fprintf('== verify_device_reuse PASSED ==\n');
end


% =====================================================================
function run_block(eng,spec)
eng.prep(spec);
wait_until(@() eng.State == mabr.acq.State.Ready,10);
assert(eng.State == mabr.acq.State.Ready,'the worker did not become Ready (state %s)',string(eng.State));
eng.run();
wait_until(@() eng.State == mabr.acq.State.Completed,30);
assert(eng.State == mabr.acq.State.Completed,'the block did not complete (state %s)',string(eng.State));
end

function wait_until(pred,timeout)
t0 = tic;
while ~pred() && toc(t0) < timeout
    pause(0.02);
end
end
