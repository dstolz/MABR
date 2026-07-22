function verify_stimgen_import()
% verify_stimgen_import  stimgen -> StimulusSet conversion, no hardware.
%
%   Checks the bridge in mabr.stim.fromStimgen:
%
%     1. one variant becomes one entry (a 2x2 grid is four presentations)
%     2. every entry is regenerated at Config.DACSampleRate, as a single column
%     3. the WAVEFORM matches its LABEL -- the trap that stimgen's
%        VariantReselectOnUpdate sets, where reading a parameter back after
%        selecting a variant silently advances to the next one, so an 8 kHz
%        tone gets saved as 16 kHz
%     4. informativeParams is the DECLARED list (Level, Frequency) and not
%        every numeric scalar on the entry -- Duration and WindowDuration must
%        not become grouping dimensions in the offline pipeline
%     4b. an UNCALIBRATED level series is rescaled relative to its loudest
%        entry -- with no calibration stimgen's SoundLevel never reaches the
%        amplitude, so 30 and 60 dB would otherwise be the same waveform
%     5. a Schedule builds and renders from the result
%     6. a .spl bank round-trips through the file path, and a live designer's
%        Reps is honoured only while the operator can see it (mabr.ui.App
%        hides that control, so a hidden one falls back to the GUI default)
%     7. Level/Frequency reach a filename in the shape the offline regex wants
%
%   Skips (and passes) when the stimgen submodule is not initialized, so the
%   suite still runs on a clone that never fetched it.
%
%   See also mabr.stim.fromStimgen, mabr.stim.stimgenAvailable, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('=== verify_stimgen_import ===\n');

[avail,why] = mabr.stim.stimgenAvailable();
if ~avail
    % An optional dependency nobody fetched is not a failure. Returning
    % normally is what the suite reads as a pass (see run_all_verifications).
    fprintf('  SKIP: %s\n',why);
    return
end

cfg = mabr.Config;

% --- 1-2. one variant, one entry, at the DAC rate --------------------
t = stimgen.Tone;
t.Frequency   = [8000 16000];
t.SoundLevel  = [30 60];
t.Duration    = 0.02;
t.DisplayName = "pip";

set = mabr.stim.fromStimgen(t,cfg);

assert(set.numStimuli == 4, ...
    'Expected 4 entries from a 2x2 variant grid, got %d.',set.numStimuli);
assert(set.SampleRate == cfg.DACSampleRate, ...
    'Expected %g Hz, got %g.',cfg.DACSampleRate,set.SampleRate);
fprintf('  4 entries at %g Hz\n',set.SampleRate);

for i = 1:set.numStimuli
    s = set.signal(i);
    assert(isa(s,'single'),'Entry %d signal is %s, expected single.',i,class(s));
    assert(iscolumn(s),'Entry %d signal is not a column vector.',i);
end
assert(numel(unique(set.IDs())) == 4,'Stimulus IDs are not unique: %s', ...
    strjoin(set.IDs(),', '));
fprintf('  signals are single columns, IDs unique\n');

% --- 3. the waveform matches its label -------------------------------
% The real test of the variant handling: measure the dominant frequency of
% each generated signal and compare it with the Frequency the entry claims.
for i = 1:set.numStimuli
    m = set.meta(i);
    x = double(set.signal(i));
    n = numel(x);
    X = abs(fft(x.*hann(n)));
    [~,k] = max(X(1:floor(n/2)));
    fMeas = (k-1)*set.SampleRate/n/1000;                 % kHz
    assert(abs(fMeas - m.Frequency) < 0.5, ...
        ['Entry %d ("%s") claims %g kHz but its waveform is %g kHz -- the ' ...
         'variant index and the metadata have come apart.'], ...
        i,m.ID,m.Frequency,fMeas);
end
fprintf('  every waveform matches its declared Frequency\n');

% Levels: the four entries must cover the 2x2 grid exactly once each.
got  = sortrows([arrayfun(@(i) set.meta(i).Frequency,1:4)', ...
                 arrayfun(@(i) set.meta(i).Level,    1:4)']);
want = sortrows([8 30; 8 60; 16 30; 16 60]);
assert(isequal(got,want),'Frequency/Level grid is %s, expected %s.', ...
    mat2str(got),mat2str(want));
fprintf('  Frequency/Level grid covered exactly once each\n');

% --- 4. declared informativeParams, not inferred ---------------------
m = set.meta(1);
assert(isequal(sort(m.informativeParams),{'Frequency','Level'}), ...
    'informativeParams is {%s}, expected {Frequency, Level}.', ...
    strjoin(m.informativeParams,', '));
% Duration is a numeric scalar on the entry and would have been inferred
% under the old rule; it must not be a grouping dimension.
assert(~ismember('Duration',m.informativeParams), ...
    'Duration leaked into informativeParams -- it would split offline groups.');
assert(strcmp(m.StimClass,'stimgen.Tone'),'StimClass is "%s".',m.StimClass);
assert(~m.Calibrated,'An uncalibrated Tone reported Calibrated = true.');
fprintf('  informativeParams = {%s}, provenance present\n', ...
    strjoin(m.informativeParams,', '));

% --- 4b. an uncalibrated level series is made relative ---------------
% Without a calibration stimgen's apply_calibration is a no-op, so SoundLevel
% never reaches the amplitude and all four entries would be IDENTICAL.
% fromStimgen rescales relative to the loudest instead: 30 dB must come back
% exactly 30 dB below 60 dB, at the same frequency.
for f = [8 16]
    at = @(L) find(arrayfun(@(i) set.meta(i).Frequency == f && ...
                                 set.meta(i).Level     == L, 1:set.numStimuli),1);
    lo = double(set.signal(at(30)));
    hi = double(set.signal(at(60)));
    dB = 20*log10(rms(hi)/rms(lo));
    assert(abs(dB - 30) < 0.01, ...
        ['At %g kHz the 30 and 60 dB entries differ by %.3f dB, expected 30 -- ' ...
         'an uncalibrated level series is not being scaled relative to its loudest.'], ...
        f,dB);
    assert(abs(set.meta(at(60)).LevelScale - 1) < eps('single'), ...
        'The loudest entry was not left at the bank''s own amplitude (LevelScale %g).', ...
        set.meta(at(60)).LevelScale);
end
% Relative, never louder: the reference is the top of the bank, so nothing may
% exceed the amplitude stimgen generated.
assert(all(arrayfun(@(i) set.meta(i).LevelScale,1:set.numStimuli) <= 1), ...
    'An entry was scaled UP -- the loudest level must be the reference.');
assert(~set.isCalibrated(),'Relative scaling must not claim the bank is calibrated.');
fprintf('  uncalibrated levels scaled relative to the loudest (30 dB apart)\n');

% --- 5. a schedule builds and renders --------------------------------
sch = mabr.stim.Schedule(set,cfg);
sch.Repetitions(:) = 4;
sch.ISI = 0.05;
sch.build();
spec = sch.renderSpec(sch.current());
assert(size(spec.PlayMatrix,2) == 2,'Play matrix is not 2-channel.');
assert(~isempty(spec.ExpectedOnsets),'Rendered run has no onsets.');
fprintf('  schedule renders: %s play matrix, %d onsets\n', ...
    mat2str(size(spec.PlayMatrix)),numel(spec.ExpectedOnsets));

% --- 6. .spl bank round-trip -----------------------------------------
% Written in the shape stimgen.StimPlayer.save_bank produces, so the file
% path is exercised without opening a GUI.
tmp = [tempname '.spl'];
c   = onCleanup(@() delete_if(tmp));

sp      = stimgen.StimPlay(t);
sp.Reps = 77;
sp.Name = "pips";
bank = struct('ISI',[1 1],'SelectionType',"Serial",'NItems',1, ...
              'Items',{{sp.toStruct}}); %#ok<NASGU>
save(tmp,'-struct','bank','-v7');

set2 = mabr.stim.StimulusSet.fromFile(tmp,cfg);
assert(set2.numStimuli == 4,'Bank round-trip gave %d entries.',set2.numStimuli);
assert(set2.SampleRate == cfg.DACSampleRate,'Bank round-trip rate is %g.',set2.SampleRate);
% Reps travels; ISI and SelectionType deliberately do not.
assert(all(mabr.stim.Schedule.startingRepetitions(set2) == 77), ...
    'StimPlay.Reps did not become the starting repetition count.');
% SoundLevel/Duration survive the serialization gap in StimType.fromStruct.
got2 = sortrows([arrayfun(@(i) set2.meta(i).Frequency,1:4)', ...
                 arrayfun(@(i) set2.meta(i).Level,    1:4)']);
assert(isequal(got2,want), ...
    ['A .spl round-trip lost the level/duration settings (grid %s) -- ' ...
     'StimType.fromStruct does not restore them on its own.'],mat2str(got2));
assert(strcmp(set2.Source.Kind,'stimgen'),'Source.Kind is "%s".',set2.Source.Kind);
fprintf('  .spl round-trip: 4 entries, Reps=77, grid intact\n');

% --- 6b. a hidden Reps field is no opinion ---------------------------
% The one case that needs the live designer, so this is the one place the
% file avoids the GUI for: mabr.ui.App hides the designer's session controls
% (set_control_visibility(All=false)), and a hidden Reps field is StimPlay's
% default of 20 rather than a choice. Importing it would silently seed a
% schedule with 20 sweeps -- not an ABR -- so it must fall back to 512, while
% a visible field is still taken at its word.
player = stimgen.StimPlayer();
cp     = onCleanup(@() delete(player));
item   = stimgen.StimPlay(t);
item.Name = "pips";
player.StimPlayObjs = item;     % Reps left at the class default, 20

player.set_control_visibility(All=false);
repsHidden = mabr.stim.Schedule.startingRepetitions(mabr.stim.fromStimgen(player,cfg));
assert(all(repsHidden == 512), ...
    ['A hidden Reps field leaked into the schedule (%s) -- the operator ' ...
     'never saw that number.'],mat2str(repsHidden));

player.set_control_visibility(Reps=true);
item.Reps = 77;
repsShown = mabr.stim.Schedule.startingRepetitions(mabr.stim.fromStimgen(player,cfg));
assert(all(repsShown == 77), ...
    'A visible Reps field was dropped (%s), expected 77.',mat2str(repsShown));
clear cp
fprintf('  designer Reps: hidden -> 512, visible -> 77\n');

% --- 7. offline-compatible filename ----------------------------------
blk = mabr.data.Block();
blk.Stim      = set.meta(1);
blk.StartTime = datetime(2026,7,21,10,30,0);
fn = mabr.data.io.buildFilename(blk,'SUBJ_ID_1');
assert(contains(fn,'Frequency_') && contains(fn,'kHz_Level_') && endsWith(fn,'.abr'), ...
    'Filename "%s" does not match the offline pipeline''s shape.',fn);
fprintf('  filename: %s\n',fn);

fprintf('== verify_stimgen_import PASSED ==\n');
end

% =========================================================================
function delete_if(f)
if isfile(f), delete(f); end
end
