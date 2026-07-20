function verify_online_advance()
% verify_online_advance  Confirm an online criterion stops a block early.
%
%   Part A (pure logic): the advance criteria return correct decisions,
%   including the correlation-threshold criterion that was an empty stub in the
%   legacy (advanceFcns/abr_adv_corr_thr.m).
%
%   Part B (end-to-end): drive the real mabr.ui.AcqController in TESTING
%   loopback with the built-in demo stimulus and the correlation-threshold
%   criterion, and confirm the block completes with far fewer sweeps than the
%   stimulus provides — the regression win the legacy design could not offer
%   ("NOT CURRENTLY POSSIBLE TO UPDATE THE NUMBER OF SWEEPS DURING PLAYBACK").
%
%   Requires the Parallel Computing Toolbox. Run:  >> verify_online_advance
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_online_advance ==\n');

% ---- Part A: criterion logic (deterministic) ---------------------------
assert(~mabr.stim.advance.num_sweeps(struct('numSweeps',10,'targetSweeps',100)));
assert( mabr.stim.advance.num_sweeps(struct('numSweeps',100,'targetSweeps',100)));

c = struct('corr',0.9,'corrThreshold',0.5,'minSweeps',16,'numSweeps',10,'maxSweeps',Inf);
assert(~mabr.stim.advance.corr_threshold(c),'should not fire below minSweeps');
c.numSweeps = 20;
assert( mabr.stim.advance.corr_threshold(c),'should fire when corr and count met');
c.corr = 0.1;
assert(~mabr.stim.advance.corr_threshold(c),'should not fire below threshold');
c.numSweeps = 5000; c.maxSweeps = 4096;
assert( mabr.stim.advance.corr_threshold(c),'should fire at maxSweeps cap');
fprintf('  PASS Part A: advance criterion logic\n');

% ---- Part B: end-to-end early stop -------------------------------------
cfg = mabr.Config;
stimSweeps = 200;

ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

source = mabr.stim.demoSource(cfg,'Frequencies',8,'Levels',60,'NumSweeps',stimSweeps);
ctrl.setSource(source);
ctrl.Queue.TestingFrameDelay = 0.004;      % pace loopback so the 20 Hz timer keeps up
ctrl.Window = [0 0.01];
ctrl.AdvanceFcn    = @mabr.stim.advance.corr_threshold;
ctrl.AdvanceParams = struct('corrThreshold',0.3,'minSweeps',16,'maxSweeps',Inf,'targetSweeps',stimSweeps);
ctrl.Session.OutputPath = '';               % don't write files for this test

ctrl.start();

t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete,'Schedule did not complete within 90 s');
assert(ctrl.Session.NumBlocks == 1,'Expected exactly one finalized block');

n = ctrl.Session.Blocks(1).NumSweeps;
assert(n >= 10,'Block stopped implausibly early (%d sweeps)',n);
assert(n < 0.75*stimSweeps,'Block did NOT stop early: %d of %d sweeps',n,stimSweeps);
fprintf('  PASS Part B: block stopped early at %d of %d sweeps\n',n,stimSweeps);

fprintf('== verify_online_advance PASSED ==\n');
end
