function verify_test_mode()
% verify_test_mode  Confirm TEST MODE copies the stimulus into the acquisition
%                   buffer, and that MABR checks and reports the alignment.
%
%   Test Mode (mabr.AudioSettings.Testing, named and documented as "Test Mode"
%   throughout the GUI) opens no audio device. Instead, mabr.acq.worker_loop
%   copies each frame of the continuous stimulus straight into the acquisition
%   ring buffer -- signal column and timing column alike -- so the samples
%   recorded at an onset ARE the samples the plan put there.
%
%   That makes it a check rather than merely a way to run without hardware.
%   Everything downstream pairs the k-th recovered sweep with the k-th planned
%   presentation, so a run in Test Mode exercises the whole chain -- plan,
%   render, timing channel, ring buffer, onset recovery, sweep attribution --
%   against a known answer, and mabr.ui.AcqController.alignmentCheck states
%   the verdict after every run.
%
%   Part A (the arithmetic): mabr.metrics.alignment_report on its own. A clean
%   run, a run stopped early, a run whose onsets drift, a spurious pulse, and
%   a run that recovered nothing at all.
%   Part B (the copy): drive a whole schedule through the real
%   mabr.ui.AcqController and confirm the ring buffer holds the run's rendered
%   play matrix -- the timing channel bit-for-bit, the signal channel to
%   within the ~1e-6 dither worker_loop adds.
%   Part C (the verdict): the controller's own report after that run says
%   aligned, at zero offset and zero jitter, with every presentation's
%   waveform compared and matching; and AlignmentChecked fired once per run.
%   Part D (it can fail): the same report, run again over deliberately
%   corrupted onsets, says MISALIGNED -- a check that cannot fail is not a
%   check. Drifting onsets, and a spurious extra pulse.
%   Part E (the marking): a Test Mode block and the .abr file it writes both
%   say so, because they are otherwise indistinguishable from real data.
%
%   Requires the Parallel Computing Toolbox (Parts B-E). No audio hardware --
%   which is the point.
%   Run:  >> verify_test_mode
%
%   See also verify_stimulus_alignment (the same correspondence taken apart
%   stage by stage, including through the compute workers), verify_timing_
%   loopback (the rig-side diagnostic).
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_test_mode ==\n');

cfg = mabr.Config;

%% ---- Part A: the arithmetic, on its own -------------------------------
expected = [1 1000 2000 3000 4000];

R = mabr.metrics.alignment_report(expected,expected);
assert(R.Aligned && R.Offset == 0 && R.Jitter == 0 && ~R.Truncated, ...
    'a recording that reproduces its own plan must report as aligned');
assert(R.NumCompared == 5 && R.Extra == 0, ...
    'all five presentations should have been compared, with nothing left over');

% A constant lag is a cable, not a fault: every onset is still the
% presentation it is paired with.
R = mabr.metrics.alignment_report(expected,expected + 37);
assert(R.Aligned && R.Offset == 37 && R.Jitter == 0, ...
    'a constant offset is latency, and must not read as a misalignment');

% A run stopped early played fewer presentations than it rendered. The ones it
% did play are still in the right places.
R = mabr.metrics.alignment_report(expected,expected(1:3));
assert(R.Aligned && R.Truncated && R.NumCompared == 3, ...
    'a truncated run whose onsets are all correctly placed is still aligned');
assert(contains(R.Summary,'ended early'), ...
    'the summary should say the run was cut short rather than implying a fault');

% Drift is the fault that matters: from the fourth presentation on, the k-th
% recorded sweep is no longer the k-th planned one.
drifting = expected + [0 0 0 12 24];
R = mabr.metrics.alignment_report(expected,drifting);
assert(~R.Aligned && R.Jitter == 24, ...
    'onsets drifting away from the plan must report as misaligned');
assert(contains(R.Summary,'MISALIGNED'),'a misaligned run must say so in as many words');

% A pulse with no presentation behind it shifts the pairing for everything
% after it, however well the ones before it line up.
R = mabr.metrics.alignment_report(expected,[expected 5000]);
assert(~R.Aligned && R.Extra == 1, ...
    'a spurious timing pulse is a fault even when every planned onset matched');

R = mabr.metrics.alignment_report(expected,[]);
assert(~R.Aligned && R.NumCompared == 0 && isnan(R.Offset), ...
    'recovering nothing at all is the loudest misalignment there is');

% The tolerance is a parameter, not a constant: a rig has jitter, loopback
% does not, and the caller is the one that knows which it is looking at.
R = mabr.metrics.alignment_report(expected,expected + [0 1 0 1 0],1);
assert(R.Aligned,'one sample of jitter should pass at a tolerance of one sample');
fprintf('  PASS Part A: clean, truncated, drifting, spurious and empty all judged correctly\n');

%% ---- Parts B-E: one schedule, in Test Mode -----------------------------
outDir = fullfile(tempdir, ...
    ['mabr_testmode_' char(datetime('now','Format','yyyyMMdd''T''HHmmssSSS'))]);
mkdir(outDir);
cleanDir = onCleanup(@() rmdir(outDir,'s')); %#ok<*NASGU>

bank = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 60]);

ctrl = mabr.ui.AcqController(cfg,true);      % true = Test Mode
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

assert(ctrl.Testing,'the controller should know it is in Test Mode');
assert(isempty(ctrl.LastAlignment), ...
    'nothing has been acquired yet, so there is no alignment to report');

ctrl.setStimuli(bank);
ctrl.Session.Subject.ID = 'SUBJ_ID_TM';
ctrl.Session.OutputPath = outDir;
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = 6;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.001;

nRuns = ctrl.Schedule.NumRuns;
assert(nRuns == 2,'expected one run per stimulus (2), got %d',nRuns);

% Counted through a LOCAL callback over a handle store, never a nested one: a
% nested function would make this workspace an object the controller's own
% listener list keeps alive, and the resulting cycle would stop the onCleanup
% above from ever deleting ctrl -- leaving its worker holding the pool for
% whatever runs next. (The same trap verify_stimulation_only documents.)
tally = containers.Map('KeyType','char','ValueType','double');
tally('checks')  = 0;
tally('aligned') = 0;
lh = addlistener(ctrl,'AlignmentChecked',@(~,e) collect_alignment(tally,e));

ctrl.start();

t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not run to completion (state %s)',string(ctrl.State));
delete(lh);

%% ---- Part B: the ring buffer holds the stimulus ------------------------
% The ring keeps only the newest run, so this is the LAST one. Re-rendering it
% is safe: the plan is fixed at build(), the ISI is a fixed grid, and nothing
% about renderSpec draws on chance for either.
spec = ctrl.Schedule.renderSpec(nRuns);
X    = spec.Plan.matrix();

[sig,tim] = ctrl.Engine.RingBuffer.readBlock();
assert(numel(sig) == size(X,1), ...
    ['the ring holds %d samples, the run rendered %d -- Test Mode should have ' ...
     'copied the whole play matrix'],numel(sig),size(X,1));

% The timing channel is copied untouched, so this can be asserted at its
% strongest: not "close to", but the same samples.
assert(isequal(tim,X(:,2)), ...
    'the recorded timing channel is not the timing channel that was rendered');

% The signal carries worker_loop's ~1e-6 dither (there so a loopback run is
% not perfectly degenerate -- see its comment), and nothing else.
err = max(abs(double(sig) - double(X(:,1))));
assert(err < 1e-4, ...
    ['the recorded signal is not the stimulus that was played (max error %.2e); ' ...
     'Test Mode did not copy the stimulus buffer into the acquisition buffer'],err);
fprintf(['  PASS Part B: %d samples copied stimulus -> acquisition buffer; timing ' ...
    'channel bit-exact, signal to %.1e\n'],numel(sig),err);

%% ---- Part C: MABR says so, by itself -----------------------------------
A = ctrl.LastAlignment;
assert(~isempty(A),'a finished run must leave an alignment report behind');
assert(A.TestMode,'the report should record which mode produced it');
assert(A.Aligned,'the run did not report as aligned: %s',A.Summary);
assert(A.Offset == 0 && A.Jitter == 0, ...
    ['with no device in the path an onset must come back exactly where it was ' ...
     'rendered (offset %g, jitter %g)'],A.Offset,A.Jitter);
assert(A.NumCompared == numel(spec.ExpectedOnsets), ...
    'every presentation of the run should have been accounted for (%d of %d)', ...
    A.NumCompared,numel(spec.ExpectedOnsets));

% The half only Test Mode makes answerable: not just that the onsets are in
% the right places, but that the samples AT them are the right stimulus.
assert(A.NumWaveforms == A.NumCompared, ...
    'Test Mode should compare every presentation waveform (%d of %d)', ...
    A.NumWaveforms,A.NumCompared);
assert(A.WaveformsMatch && A.MaxError < 1e-4, ...
    'the samples at the recovered onsets are not the stimuli scheduled there (max %.2e)', ...
    A.MaxError);

assert(tally('checks') == nRuns, ...
    'AlignmentChecked should fire once per run (%d of %d)',tally('checks'),nRuns);
assert(tally('aligned') == nRuns,'every run of this schedule should have reported aligned');
fprintf(['  PASS Part C: %d runs checked; %d presentations matched their own ' ...
    'waveforms (max error %.1e)\n'],nRuns,A.NumWaveforms,A.MaxError);

%% ---- Part D: the check can fail ----------------------------------------
% Run the controller's own check again over onsets that are deliberately
% wrong. The ring still holds the last run (nothing overwrites it until the
% next Run), so this exercises the real path -- report, waveform comparison
% and all -- rather than a stand-in for it.
good = double(spec.ExpectedOnsets(:)');

R = ctrl.alignmentCheck(struct('OnsetsAll',good));
assert(R.Aligned && R.WaveformsMatch, ...
    'the undoctored onsets must still pass, or Part D proves nothing');

half = ceil(numel(good)/2):numel(good);
bad  = good; bad(half) = bad(half) + 5;
R = ctrl.alignmentCheck(struct('OnsetsAll',bad));
assert(~R.Aligned && R.Jitter == 5, ...
    'onsets drifting five samples from the plan must be reported (jitter %g)',R.Jitter);
assert(R.MaxError > 1e-4, ...
    ['reading a sweep five samples off its onset must not still match the ' ...
     'stimulus (max error %.2e)'],R.MaxError);

R = ctrl.alignmentCheck(struct('OnsetsAll',[good good(end)+1000]));
assert(~R.Aligned && R.Extra == 1, ...
    'a pulse the plan never rendered must be reported as spurious');

% The controller keeps the latest verdict, whatever it was: a report that
% quietly reverted to the last good one would be worse than none.
assert(isequal(ctrl.LastAlignment.Extra,1), ...
    'LastAlignment should hold the most recent check, not the best one');
fprintf('  PASS Part D: drift and a spurious pulse both caught by the real check\n');

%% ---- Part E: the data say where they came from -------------------------
assert(ctrl.Session.NumBlocks == nRuns, ...
    'expected one block per run (%d), got %d',nRuns,ctrl.Session.NumBlocks);
assert(all([ctrl.Session.Blocks.TestMode]), ...
    'every block finalized in Test Mode must be marked as such');
fresh = mabr.data.Block;
assert(~fresh.TestMode, ...
    'a block should default to NOT being a Test Mode block');

files = dir(fullfile(outDir,'*.abr'));
assert(numel(files) == nRuns, ...
    'expected one .abr per run (%d), found %d',nRuns,numel(files));
D = load(fullfile(outDir,files(1).name),'-mat','ABR_Data');
assert(isfield(D.ABR_Data,'TestMode'), ...
    'a .abr must always carry TestMode -- offline code cannot be left to guess');
assert(islogical(D.ABR_Data.TestMode) && D.ABR_Data.TestMode, ...
    'a file written in Test Mode holds the stimulus, and has to say so');
assert(~isfield(D.ABR_Data.SIG,'TestMode'), ...
    'TestMode must stay out of SIG, where it would read as a stimulus parameter');
fprintf('  PASS Part E: %d blocks and %d .abr files marked as Test Mode\n', ...
    ctrl.Session.NumBlocks,numel(files));

fprintf('== verify_test_mode: ALL PASS ==\n');
end


% =====================================================================
function collect_alignment(tally,e)
% Local, not nested -- see the note at the listener above.
tally('checks') = tally('checks') + 1;
if e.Info.report.Aligned
    tally('aligned') = tally('aligned') + 1;
end
end
