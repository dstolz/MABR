function verify_online_advance()
% verify_online_advance  Confirm an online criterion stops a run early, and
%                        that intermixed runs de-interleave correctly.
%
%   Part A (pure logic): the advance criteria return correct decisions,
%   including the correlation-threshold criterion that was an empty stub in the
%   legacy (advanceFcns/abr_adv_corr_thr.m).
%
%   Part B (end-to-end): drive the real mabr.ui.AcqController in TESTING
%   loopback with the built-in demo stimuli, a BLOCKED strategy, and the
%   correlation-threshold criterion, and confirm the run completes with far
%   fewer sweeps than the schedule asked for — the regression win the legacy
%   design could not offer ("NOT CURRENTLY POSSIBLE TO UPDATE THE NUMBER OF
%   SWEEPS DURING PLAYBACK").
%
%   Part C (intermixing): schedule two stimuli with a shuffled-cycle strategy,
%   and confirm one continuous run is de-interleaved back into one
%   mabr.data.Block per stimulus ID with the scheduled repetition counts.
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

cfg = mabr.Config;

% ---- Part B: end-to-end early stop -------------------------------------
reps = 200;

% One controller serves both parts: a second Engine would map the same
% ring-buffer files and contend for the single-process parallel pool.
ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = reps;
ctrl.Schedule.ISI         = 1/21.1;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.004;   % pace loopback so the 20 Hz timer keeps up

ctrl.Window = [0 0.01];
ctrl.AdvanceFcn    = @mabr.stim.advance.corr_threshold;
ctrl.AdvanceParams = struct('corrThreshold',0.3,'minSweeps',16,'maxSweeps',Inf,'targetSweeps',reps);
ctrl.Session.OutputPath = '';               % don't write files for this test

run_schedule(ctrl,90);

assert(ctrl.Session.NumBlocks == 1,'Expected exactly one finalized block');
n = ctrl.Session.Blocks(1).NumSweeps;
assert(n >= 10,'Run stopped implausibly early (%d sweeps)',n);
assert(n < 0.75*reps,'Run did NOT stop early: %d of %d sweeps',n,reps);
fprintf('  PASS Part B: run stopped early at %d of %d sweeps\n',n,reps);

% ---- Part C: intermixed run de-interleaves -----------------------------
repsC = 20;
n0    = ctrl.Session.NumBlocks;    % Part B's block stays in the session

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 60]));
ctrl.Schedule.Strategy    = 'shuffled-cycles';
ctrl.Schedule.Repetitions = repsC;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.Seed        = 42;             % reproducible order
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.002;

assert(ctrl.Schedule.isIntermixed(),'shuffled-cycles should intermix');
assert(ctrl.Schedule.NumRuns == 1,'Intermixed strategies produce a single run');

seq = ctrl.Schedule.runSequence(1);
assert(numel(seq) == 2*repsC,'Expected %d presentations, got %d',2*repsC,numel(seq));
assert(numel(unique(seq)) == 2,'Run should contain both stimuli');
assert(any(diff(seq) ~= 0),'Sequence is not actually intermixed');

% The criterion must NOT fire here even though it is armed: an intermixed run
% plays to completion.
ctrl.AdvanceFcn    = @mabr.stim.advance.corr_threshold;
ctrl.AdvanceParams = struct('corrThreshold',0.01,'minSweeps',4,'maxSweeps',Inf,'targetSweeps',2*repsC);

run_schedule(ctrl,90);

newBlocks = ctrl.Session.Blocks(n0+1:end);
assert(numel(newBlocks) == 2, ...
    'Expected one block per stimulus, got %d',numel(newBlocks));

ids = arrayfun(@(b) string(b.Stim.Meta.ID),newBlocks);
assert(numel(unique(ids)) == 2,'Blocks did not separate by stimulus ID (%s)',strjoin(ids,', '));

for i = 1:2
    ns = newBlocks(i).NumSweeps;
    assert(ns == repsC,'Block "%s": expected %d sweeps, got %d',ids(i),repsC,ns);
end
fprintf('  PASS Part C: intermixed run split into %s, %d sweeps each\n', ...
    strjoin(ids,' + '),repsC);

fprintf('== verify_online_advance PASSED ==\n');
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
