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
%   plan advances through every run to SchedComplete, and nothing is recorded,
%   finalized, or written.
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
assert(contains(b.describe(),'TESTING') && ~contains(b.describe(),'stimulation only'), ...
    'Testing opens no device at all, so it must win over stimulation only');
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
assert(size(spec.PlayMatrix,2) == 2, ...
    'the play matrix must keep both columns: the timing pulse is still an output');
assert(any(spec.PlayMatrix(:,2) ~= 0), ...
    'the timing channel must still be synthesized in stimulation-only mode');
assert(any(spec.PlayMatrix(:,1) ~= 0), ...
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

ctrl.setStimuli(set);
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

% No LivePlot is attached -- the live timer never starts in this mode, so
% nothing should be reaching for one.
ctrl.start();          % must NOT throw mabr:ui:AcqController:timingNotDetected

t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not run to completion (state %s)',string(ctrl.State));

assert(ctrl.Session.NumBlocks == 0, ...
    'nothing is recorded, so no block should have been finalized (got %d)', ...
    ctrl.Session.NumBlocks);

written = dir(fullfile(outDir,'*.abr'));
assert(isempty(written),'stimulation only must write no .abr files (found %d)',numel(written));
fprintf(['  PASS Part C: %d runs played to completion; 0 blocks, 0 files, ' ...
    'no loop-back required\n'],nRuns);

fprintf('== verify_stimulation_only PASSED ==\n');
end
