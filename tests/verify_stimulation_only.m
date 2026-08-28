function verify_stimulation_only()
% verify_stimulation_only  Confirm the stimulation-only mode plays a whole
%                          schedule without recording, saving, or requiring a
%                          loop-back.
%
%   Stimulation only (mabr.AudioSettings.StimulationOnly) keeps the signal and
%   the timing pulse on the outputs but performs no acquisition: the worker
%   opens an output-only audioDeviceWriter, mabr.ui.AcqController skips the
%   pre-run loop-back self-test and the live timer, and a completed run is
%   never finalized -- no mabr.data.Block, no .abr file.
%
%   Part A (the setting): the flag defaults off, survives prefs and the
%   configuration-file struct round-trip, is reported by describe(), and falls
%   back to the default when the saved pref is corrupt (the user's own prefs
%   are saved and restored, so running this does not disturb them).
%   Part B (the spec): the flag reaches the rendered spec, which is how it
%   gets to mabr.acq.worker_loop.prepare_device -- per block, since the device
%   is rebuilt on every Prep -- while the play matrix keeps BOTH columns: the
%   timing pulse is as much an output as the signal.
%   Part C (end-to-end): drive the real mabr.ui.AcqController with
%   Schedule.StimulationOnly set and confirm start() needs no loop-back, the
%   plan advances through every run to SchedComplete, and nothing is recorded
%   or finalized -- no mabr.data.Block, no .abr.
%   Part D (the record): what such a session DOES write. One .stimlog per run
%   holding the sequence that was played -- every presentation in play order
%   with its stimulus, polarity, and onset time -- because nothing being
%   recorded here does not make what was presented any less the experimental
%   record, and a rig where another system does the recording has nothing else
%   to align against.
%
%   The engine runs in TESTING loopback (Engine(cfg,true)), so no audio device
%   is needed. Testing wins inside the worker -- prepare_device builds nothing
%   and stream_block takes the loopback branch -- which is exactly the point:
%   what Part C exercises is the CLIENT-side stimulation-only path, every line
%   of it driven by Schedule.StimulationOnly. The output-only device swap
%   itself is hardware and is verified on the rig (see the plan's manual
%   checklist, alongside verify_timing_loopback's 'Testing',false form).
%
%   Requires the Parallel Computing Toolbox (Part C only).
%   Run:  >> verify_stimulation_only
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_stimulation_only ==\n');

cfg = mabr.Config;

% ---- Part A: the setting -------------------------------------------------
a = mabr.AudioSettings;
assert(islogical(a.StimulationOnly) && ~a.StimulationOnly, ...
    'StimulationOnly should default to false');

b = a; b.Testing = false; b.Device = 'Fireface UCX'; b.StimulationOnly = true;
assert(contains(b.describe(),'stimulation only'), ...
    'describe() should say so while StimulationOnly is set');
assert(contains(b.describe(),'Fireface UCX'), ...
    'describe() should still name the device -- a real one IS opened');
assert(b.isStimulationOnly(),'isStimulationOnly should agree with the flag');
b.Testing = true;
assert(contains(b.describe(),'TEST MODE') && ~contains(b.describe(),'stimulation only'), ...
    'Test Mode opens no device at all, so it must win over stimulation only');
assert(~b.isStimulationOnly(), ...
    'both flags set is a half state: isStimulationOnly must let Testing win');

% Configuration-file round-trip (plain structs, per mabr.ui.App.captureConfiguration)
c = mabr.AudioSettings.fromStruct(b.toStruct());
assert(c.StimulationOnly == b.StimulationOnly, ...
    'StimulationOnly did not survive toStruct/fromStruct');
assert(isequal(mabr.AudioSettings.fromStruct(struct('Device','x')).StimulationOnly,false), ...
    'a struct saved before the field existed should fall back to the default');

saved   = mabr.AudioSettings.loadPrefs();
restore = onCleanup(@() mabr.AudioSettings.savePrefs(saved));

q = mabr.AudioSettings; q.Testing = false; q.StimulationOnly = true;
mabr.AudioSettings.savePrefs(q);
r = mabr.AudioSettings.loadPrefs();
assert(islogical(r.StimulationOnly) && r.StimulationOnly, ...
    'StimulationOnly did not survive a setpref/getpref round-trip');

setpref('MABR','AudioStimulationOnly','not a logical');
assert(mabr.AudioSettings.loadPrefs().StimulationOnly == false, ...
    'an invalid saved StimulationOnly value should fall back to the default');
fprintf('  PASS Part A: default, describe(), prefs and struct round-trip\n');

% ---- Part B: the flag reaches the rendered spec --------------------------
% Two stimuli, so a blocked plan has more than one run to advance through:
% "the schedule drives itself to completion" is the claim, and one run cannot
% demonstrate advancing.
set = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 60]);

sch = mabr.stim.Schedule(set,cfg);
sch.Repetitions(:)  = 4;
sch.StimulationOnly = true;
sch.build();
spec = sch.renderSpec(sch.current());
assert(isfield(spec,'StimulationOnly') && spec.StimulationOnly, ...
    'StimulationOnly must reach the rendered spec -- that is how it gets to the worker');
play = spec.Plan.matrix();
assert(size(play,2) == 2, ...
    'the play matrix must keep both columns: the timing pulse is still an output');
assert(any(play(:,2) ~= 0), ...
    'the timing channel must still be synthesized in stimulation-only mode');
assert(any(play(:,1) ~= 0), ...
    'the signal channel must still be synthesized in stimulation-only mode');

sch2 = mabr.stim.Schedule(set,cfg);
sch2.Repetitions(:) = 4;
sch2.build();
assert(~sch2.renderSpec(sch2.current()).StimulationOnly, ...
    'a schedule that was never told otherwise must render as full-duplex');
fprintf('  PASS Part B: flag on the spec, both output columns intact\n');

% ---- Part C: a whole schedule plays with nothing recorded ---------------
outDir = fullfile(tempdir, ...
    ['mabr_stimonly_' char(datetime('now','Format','yyyyMMdd''T''HHmmssSSS'))]);
mkdir(outDir);
cleanDir = onCleanup(@() rmdir(outDir,'s'));

ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

assert(strcmp(mabr.ui.AcqController.workerRole(true),'stimulus') && ...
       strcmp(mabr.ui.AcqController.workerRole(false),'acquisition'), ...
    'a worker that records nothing must not be called an acquisition worker');
assert(strcmp(ctrl.Engine.WorkerName,'acquisition worker'), ...
    'a controller built without the flag should launch an acquisition worker');

ctrl.setStimuli(set);
ctrl.Session.Subject.ID = 'SUBJ_ID_777';
ctrl.Schedule.Strategy       = 'blocked';
ctrl.Schedule.Repetitions    = 8;
ctrl.Schedule.ISI            = 0.02;
ctrl.Schedule.StimulationOnly = true;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.001;

nRuns = ctrl.Schedule.NumRuns;
assert(nRuns > 1,'the test needs a plan with several runs to advance through');

% An OutputPath IS set: "nothing is written" has to be verified against a
% session that would otherwise write, not one that had nowhere to.
ctrl.Session.OutputPath = outDir;

% Files written are announced through BlockSaved, exactly as .abr files are:
% the event means "a file was written", and this mode has one kind to write.
%
% The callback is a LOCAL function over a handle store, deliberately not a
% NESTED one. A nested function would make this file's workspace a shared
% object that the controller's own listener list keeps alive, and the cycle
% (ctrl -> listener -> callback -> workspace -> ctrl) would stop the onCleanup
% above from ever deleting ctrl: its worker would then hold the pool's only
% process forever and the NEXT test in the suite would hang in pctRunOnAll,
% far from the cause. See verify_artifact_rejection, where exactly that had to
% be broken by hand.
savedMap = containers.Map('KeyType','double','ValueType','char');
lh = addlistener(ctrl,'BlockSaved',@(~,e) collect_saved(savedMap,e));

% No LivePlot is attached -- the live timer never starts in this mode, so
% nothing should be reaching for one.
ctrl.start();          % must NOT throw mabr:ui:AcqController:timingNotDetected

assert(strcmp(ctrl.Engine.WorkerName,'stimulus worker'), ...
    'start() must re-label the worker for the mode it is about to run in');

t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not run to completion (state %s)',string(ctrl.State));

assert(ctrl.Session.NumBlocks == 0, ...
    'nothing is recorded, so no block should have been finalized (got %d)', ...
    ctrl.Session.NumBlocks);

delete(lh);        % done listening; nothing below should still be collecting
saved = values(savedMap);   % numeric keys, so this comes back in write order

written = dir(fullfile(outDir,'*.abr'));
assert(isempty(written),'stimulation only must write no .abr files (found %d)',numel(written));
fprintf(['  PASS Part C: %d runs played to completion; 0 blocks, 0 .abr files, ' ...
    'no loop-back required\n'],nRuns);

% ---- Part D: the stimulation sequence IS saved ---------------------------
logs = dir(fullfile(outDir,'*.stimlog'));
assert(numel(logs) == nRuns, ...
    'expected one .stimlog per run (%d), found %d',nRuns,numel(logs));
assert(numel(saved) == nRuns, ...
    'every written log should be announced through BlockSaved (%d of %d)', ...
    numel(saved),nRuns);
assert(all(endsWith(saved,'.stimlog')), ...
    'BlockSaved reported something other than the stimulation logs');
assert(all(startsWith({logs.name},'SUBJ_ID_777_StimLog_Run')), ...
    'stimulation logs should be named for the subject and the run');

L = load(fullfile(outDir,logs(1).name),'-mat','MABR_StimLog');
assert(isfield(L,'MABR_StimLog'),'a .stimlog must hold one MABR_StimLog struct');
S = L.MABR_StimLog;

assert(strcmp(S.Mode,'stimulation-only') && ~S.Recorded, ...
    'the log must say plainly that nothing was recorded');
assert(S.Complete && strcmp(S.StopReason,'completed'), ...
    'a run that played out in full should be logged as complete');

% One entry per presentation, in play order, each naming its stimulus.
seq = S.Sequence;
assert(numel(seq.StimulusIndex) == 8 && numel(seq.Polarity) == 8 && ...
       numel(seq.OnsetTime) == 8 && numel(seq.ID) == 8, ...
    'the sequence must hold one entry per presentation (8)');
assert(S.NumPlanned == 8 && S.NumPresented == 8, ...
    'every presentation of a completed run was presented');
assert(all(seq.Presented),'a completed run presented all of its stimuli');
assert(all(ismember(seq.Polarity,[-1 1])),'polarity must be +1/-1 per presentation');
assert(issorted(seq.OnsetTime) && seq.OnsetTime(1) >= 0, ...
    'onset times must ascend from the start of the run');
% Blocked, so one stimulus for the whole run -- and it must be a real ID from
% the bank, not an index the reader has to resolve somewhere else.
assert(isscalar(unique(seq.StimulusIndex)),'a blocked run holds one stimulus');
assert(ismember(seq.ID{1},set.IDs()),'the logged ID must name a stimulus in the bank');

% The ISI is recoverable from the onsets alone: this is the number a system
% recording elsewhere lines its own data up with.
assert(all(abs(diff(seq.OnsetTime) - 0.02) < 1e-6), ...
    'onset spacing must match the scheduled ISI');

% Parameters, so the log describes the stimulus rather than just naming it.
assert(isscalar(S.Stimuli) && S.Stimuli.NumPresented == 8, ...
    'the per-stimulus tally should cover the one stimulus this run played');
assert(isfield(S.Stimuli.SIG,'informativeParams'), ...
    'each stimulus should carry its parameters, flattened as a .abr SIG is');

% The plan's own bookkeeping is kept as truthfully as a recorded run keeps it.
assert(sum(ctrl.Schedule.RunCounts) == nRuns*8, ...
    'presented counts should be recorded against the schedule (got %d)', ...
    sum(ctrl.Schedule.RunCounts));

fprintf(['  PASS Part D: %d stimulation logs written; sequence, polarity, ' ...
    'onsets and parameters all recorded\n'],numel(logs));

fprintf('== verify_stimulation_only PASSED ==\n');
end


% =====================================================================
function collect_saved(store,e)
% Record one BlockSaved file. A local function over a handle store (see the
% comment at the listener), so nothing here captures the controller.
store(store.Count+1) = e.Info.file; %#ok<NASGU>
end
