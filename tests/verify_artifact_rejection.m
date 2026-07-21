function verify_artifact_rejection()
% verify_artifact_rejection  Confirm artifact detection, persistence, make-up
%                            scheduling, and that make-up always terminates.
%
%   Part A (pure logic): mabr.metrics.detect_artifacts flags the right sweeps
%   under each criterion.
%   Part B (policy): mabr.ArtifactPolicy keeps the two thresholds independent
%   and round-trips through MATLAB prefs (the user's own prefs are saved and
%   restored, so running this does not disturb them).
%   Part C (data model): flags stay aligned with SweepOnsets even when a
%   truncated run leaves the last sweep window short, survive the .abr writer,
%   and are excluded from a Block's metrics.
%   Part D (scheduling): mabr.stim.Schedule.appendMakeup appends runs, honours
%   MakeupLimit, and reset() drops them.
%   Part E (end-to-end): drive the real controller in TESTING loopback with a
%   threshold that rejects EVERY sweep, and confirm the make-up loop still
%   terminates inside the cap — the property that keeps a noisy electrode from
%   making a session run forever.
%
%   Parts A-D need no hardware and no parallel pool; Part E needs the Parallel
%   Computing Toolbox. Run:  >> verify_artifact_rejection
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_artifact_rejection ==\n');

cfg = mabr.Config;

% ---- Part A: detection logic (deterministic) ---------------------------
% sweep 1: silent.  sweep 2: constant 0.5.  sweep 3: quiet but for one spike.
D = [zeros(10,1), 0.5*ones(10,1), [0.01*ones(9,1); 5]];

assert(~any(mabr.metrics.detect_artifacts(D,'none',0.1)), ...
    '''none'' must reject nothing');

assert(isequal(mabr.metrics.detect_artifacts(D,'voltage',1),[false false true]), ...
    'voltage criterion should catch only the spike');

% RMS: 0, 0.5, ~1.58 -> the constant sweep and the spike both clear 0.2, and
% this is the case a peak threshold of 1 misses entirely.
assert(isequal(mabr.metrics.detect_artifacts(D,'rms',0.2),[false true true]), ...
    'rms criterion should catch sustained amplitude a peak limit misses');

[tf,feature] = mabr.metrics.detect_artifacts(D,'voltage',1);
assert(isequal(size(tf),[1 3]) && isequal(feature,[0 0.5 5]), ...
    'feature output should be the per-sweep max |x|');

assert(isempty(mabr.metrics.detect_artifacts([],'voltage',1)),'empty in, empty out');

try
    mabr.metrics.detect_artifacts(D,'bogus',1);
    error('expected an error for an unknown mode');
catch me
    assert(strcmp(me.identifier,'mabr:metrics:detect_artifacts:mode'), ...
        'wrong identifier: %s',me.identifier);
end
fprintf('  PASS Part A: detection logic\n');

% ---- Part B: policy + pref persistence ---------------------------------
p = mabr.ArtifactPolicy;
assert(strcmp(p.Mode,'none') && ~p.Enabled,'default policy rejects nothing');
assert(isinf(p.Threshold),'a disabled policy must have an unreachable threshold');
assert(p.VoltageThreshold == 0.100,'default voltage threshold should be +/-100 mV');

p.Mode = 'voltage';
assert(p.Enabled && p.Threshold == 0.100);
p = p.setThreshold(0.050);
assert(p.VoltageThreshold == 0.050 && p.RMSThreshold == 0.030, ...
    'setting the voltage threshold must not disturb the RMS one');
p.Mode = 'rms';
assert(p.Threshold == 0.030);
p = p.setThreshold(0.020);
assert(p.VoltageThreshold == 0.050 && p.RMSThreshold == 0.020, ...
    'the two thresholds must stay independent across a mode switch');

% Prefs round-trip, leaving whatever the user had in place afterwards.
saved   = mabr.ArtifactPolicy.loadPrefs();
restore = onCleanup(@() mabr.ArtifactPolicy.savePrefs(saved));

p.Repeat = true;
mabr.ArtifactPolicy.savePrefs(p);
q = mabr.ArtifactPolicy.loadPrefs();
assert(strcmp(q.Mode,p.Mode) && q.VoltageThreshold == p.VoltageThreshold ...
    && q.RMSThreshold == p.RMSThreshold && q.Repeat == p.Repeat, ...
    'policy did not survive a setpref/getpref round-trip');

% A corrupt pref must fall back to the default rather than stop the app.
setpref('MABR','ArtifactVoltage',-1);
assert(mabr.ArtifactPolicy.loadPrefs().VoltageThreshold == 0.100, ...
    'an invalid saved threshold should fall back to the default');
fprintf('  PASS Part B: policy thresholds and pref persistence\n');

% ---- Part C: flags in the data model and on disk ------------------------
% The last onset's window runs off the end, so it is absent from SweepData;
% IsArtifact must still line up with SweepOnsets.
rec = mabr.data.Recording(12000,randn(1000,1),[1;101;201;951],100,1);
assert(isequal(rec.ValidSweeps,[true;true;true;false]),'ValidSweeps mismatch');
assert(size(rec.SweepData,2) == 3,'the short sweep should not reach SweepData');

flags = false(4,1);
flags(rec.ValidSweeps) = mabr.metrics.detect_artifacts(rec.SweepData,'voltage',0.5);
rec.IsArtifact = flags;
assert(numel(rec.IsArtifact) == numel(rec.SweepOnsets), ...
    'flags must align with SweepOnsets, not with SweepData');

% Force a known rejection and check it reaches the .abr struct.
rec.IsArtifact = [false;true;false;false];
assert(rec.NumArtifacts == 1);

meta = struct('ID','test');
meta.informativeParams = {};
meta.Label = {};
blk = mabr.data.Block(struct('Meta',meta,'SampleRate',192000),rec,'');
blk.SweepPolarity = ones(1,4);

S = mabr.data.io.buildStruct(blk);
assert(isfield(S.ADC,'IsArtifact') && isequal(S.ADC.IsArtifact,[false;true;false;false]), ...
    'IsArtifact did not reach the .abr struct');
assert(numel(S.ADC.Data) == 1000, ...
    'a rejected sweep must NOT be removed from the saved trace');

blk = blk.computeMetrics();
assert(isfinite(blk.Metrics.rms),'metrics should still compute with a sweep excluded');
fprintf('  PASS Part C: flags align, persist, and exclude from metrics\n');

% ---- Part D: make-up scheduling and its cap -----------------------------
stim = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 60]);
sch  = mabr.stim.Schedule(stim,cfg);
sch.Strategy    = 'blocked';
sch.Repetitions = 10;
sch.build();
assert(sch.NumRuns == 2 && ~any(sch.IsMakeup),'expected two plain blocked runs');

added = sch.appendMakeup([3 0]);
assert(added(1) == 3 && sch.NumRuns == 3,'make-up run was not appended');
assert(isequal(sch.IsMakeup,[false false true]),'make-up run not marked');
assert(isequal(sch.runSequence(3),[1 1 1]),'make-up run should hold one stimulus');

% MakeupLimit = 1 -> a budget of 10 per stimulus, 3 of it already spent.
added = sch.appendMakeup([20 0]);
assert(added(1) == 7,'expected the cap to clamp the request to the remaining 7');
added = sch.appendMakeup([5 0]);
assert(added(1) == 0,'budget was exhausted; nothing more may be appended');

sch.reset();
assert(sch.NumRuns == 2 && ~any(sch.IsMakeup) && ~any(sch.MakeupUsed), ...
    'reset() must return the schedule to its built state');
fprintf('  PASS Part D: make-up appends, caps at MakeupLimit, and resets\n');

% ---- Part E: end-to-end, worst case ------------------------------------
reps = 6;
ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl)); %#ok<NASGU>
ctrl.waitUntilReady();

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = reps;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.002;
ctrl.Session.OutputPath = '';

% A threshold nothing can satisfy: every sweep is an artifact, so every run
% asks for a full make-up. This is the runaway case the cap exists for.
ctrl.Artifacts = mabr.ArtifactPolicy('voltage',1e-9,true);

run_schedule(ctrl,120);

assert(ctrl.Session.NumBlocks >= 2, ...
    'expected the original run plus at least one make-up, got %d blocks', ...
    ctrl.Session.NumBlocks);
used = sum(ctrl.Schedule.MakeupUsed);
assert(used > 0,'nothing was made up despite every sweep being rejected');
assert(used <= reps,'make-up (%d) exceeded the MakeupLimit cap (%d)',used,reps);
for i = 1:ctrl.Session.NumBlocks
    b = ctrl.Session.Blocks(i);
    assert(b.ADC.NumArtifacts == b.NumSweeps, ...
        'block %d: %d of %d sweeps flagged; expected all', ...
        i,b.ADC.NumArtifacts,b.NumSweeps);
end
fprintf('  PASS Part E: %d make-up presentations, capped at %d, loop terminated\n', ...
    used,reps);

% Counting-only must schedule no make-up at all.
n0 = ctrl.Session.NumBlocks;
ctrl.Artifacts = mabr.ArtifactPolicy('voltage',1e-9,false);
run_schedule(ctrl,120);

assert(~any(ctrl.Schedule.IsMakeup),'counting-only must not append make-up runs');
assert(ctrl.Session.NumBlocks - n0 == 1, ...
    'counting-only should have produced exactly one more block, got %d', ...
    ctrl.Session.NumBlocks - n0);
b = ctrl.Session.Blocks(end);
assert(b.ADC.NumArtifacts == b.NumSweeps,'artifacts should still be counted');
fprintf('  PASS Part E: counting-only counts %d artifacts and schedules no make-up\n', ...
    b.ADC.NumArtifacts);

fprintf('== verify_artifact_rejection PASSED ==\n');
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
