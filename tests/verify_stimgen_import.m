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
%     5. a Schedule builds and renders from the result
%     6. a .spl bank round-trips through the file path
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
