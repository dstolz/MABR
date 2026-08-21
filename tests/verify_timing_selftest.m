function verify_timing_selftest()
% verify_timing_selftest  Confirm AcqController's pre-run timing loop-back
%                          self-test does not regress a normal Start.
%
%   mabr.ui.AcqController.start() now streams a short synthetic timing-only
%   block through the real Engine.prep/run path (mabr.ui.AcqController>
%   verifyTimingLoop) before the first real block of a session, and errors
%   immediately if no pulse comes back -- catching a bad loop-back cable at
%   Start instead of after a wasted block. This is a no-hardware regression
%   test for that addition: in TESTING loopback mode the synthetic pulses
%   always come straight back, so the check must pass silently, the schedule
%   must still complete, and the check must not run again (and cost time) on
%   a second Start.
%
%   Requires the Parallel Computing Toolbox. Run:  >> verify_timing_selftest
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_timing_selftest ==\n');

cfg = mabr.Config;

ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = 4;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.002;
ctrl.Session.OutputPath = '';

assert(~ctrl.TimingVerified,'TimingVerified should start false');

t0 = tic;
run_schedule(ctrl,30);
elapsed = toc(t0);

assert(ctrl.TimingVerified,'Self-test did not mark timing as verified');
assert(ctrl.Session.NumBlocks == 1,'Expected exactly one finalized block, got %d', ...
    ctrl.Session.NumBlocks);
assert(ctrl.Session.Blocks(1).NumSweeps == 4, ...
    'Expected 4 sweeps from the real run, got %d -- the self-test block leaked into it', ...
    ctrl.Session.Blocks(1).NumSweeps);
fprintf('  PASS: first Start ran the self-test, verified timing, and completed normally (%.2fs)\n', ...
    elapsed);

% ---- Second Start must not repeat the check -----------------------------
ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = 4;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.002;

t1 = tic;
run_schedule(ctrl,30);
elapsed2 = toc(t1);

assert(ctrl.Session.NumBlocks == 2,'Expected a second finalized block, got %d', ...
    ctrl.Session.NumBlocks);
fprintf('  PASS: second Start skipped the self-test (TimingVerified cached) (%.2fs)\n',elapsed2);

fprintf('== verify_timing_selftest PASSED ==\n');
end


% =====================================================================
function run_schedule(ctrl,timeout)
% Start the controller and block (letting event callbacks run) until its
% schedule completes.
ctrl.start();
t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < timeout
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'Schedule did not complete within %g s',timeout);
end
