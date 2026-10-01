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
%     6c. a bank saved WITH its calibration imports calibrated: the volts are
%        the lookup table's and identical to the live stimulus's, the set says
%        so, and stimgen's "No calibration data" warning is NOT raised on the
%        way in -- while it still is for a bank that has none
%     7. Level/Frequency reach a filename in the shape the offline regex wants
%     8. a Tone's Polarity: -1 inverts the waveform, 0 (alternate) imports as
%        alternatePolarity with ONE variant per condition -- repetitions split
%        between the signs, not doubled as OnsetPhase = [0 180] would; a
%        ClickTrain alternates presentations the same way under Polarity = 2,
%        and its in-train alternation (0) is not flipped a second time
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
assert(isa(spec.Plan,'mabr.stim.PlayPlan'),'Rendered run carries no PlayPlan.');
assert(size(spec.Plan.range(1,cfg.frameLength),2) == 2,'Play matrix is not 2-channel.');
assert(~isempty(spec.ExpectedOnsets),'Rendered run has no onsets.');
fprintf('  schedule renders: %s play matrix, %d onsets\n', ...
    mat2str([spec.Plan.N 2]),numel(spec.ExpectedOnsets));

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

% --- 6c. a CALIBRATED bank: the LUT's volts, said so, and no false alarm
% A bank the designer saves carries its calibration as a struct, and readBank
% restores the stimulus first and puts the calibration back after. In between,
% every property stimgen's fromStruct assigns regenerates the signal against
% an EMPTY calibration -- and stimgen answers that with a red, level-0
% "No calibration data available for stim", word for word what a genuinely
% uncalibrated bank earns. That line appeared on a correctly calibrated rig
% bank, where nothing on screen could be weighed against it. So three things:
% the volts are the table's, the set SAYS it is calibrated, and the warning
% is not raised -- while it still IS for the bank above that has none, since
% a check that cannot fail is not a check.
calS = struct('version',2, ...
    'CalibrationData',struct('tone',struct( ...
        'frequency',[1000 2000 4000 8000 16000 32000], ...
        'voltage',  [0.10 0.08 0.20 0.12 0.05 0.25])), ...
    'MicSensitivity',0.03,'NormativeValue',80, ...
    'CalibrationTimestamp',datetime(2026,9,29,10,59,22));
cal = stimgen.StimCalibration.loadobj(calS);

tc = stimgen.Tone;
tc.Frequency   = [8000 16000];
tc.SoundLevel  = [30 60];
tc.Duration    = 0.02;
tc.DisplayName = "calpip";
tc.Calibration = cal;

spc      = stimgen.StimPlay(tc);
spc.Name = "calpips";
tmpC  = [tempname '.spl'];
cc    = onCleanup(@() delete_if(tmpC));
bankC = struct('ISI',[1 1],'SelectionType',"Serial",'NItems',1, ...
               'Items',{{spc.toStruct}});
save(tmpC,'-struct','bankC','-v7');

% Heard at stimgen's own logging seam rather than scraped off the console, so
% it does not depend on the verbosity in force or on which stream red text
% goes to. The sink in place (mabr.ui.App's, when the suite runs from the GUI)
% goes back however this ends.
heard = containers.Map('KeyType','double','ValueType','any');
prev  = stimgen.util.logSink();
cs    = onCleanup(@() stimgen.util.logSink(prev));
stimgen.util.logSink(stimgen.FcnLogSink( ...
    @(lvl,~,msg,~) hear(heard,lvl,msg),@(~) true));

set3       = mabr.stim.StimulusSet.fromFile(tmpC,cfg);
falseAlarm = heardSince(heard,0,'No calibration data');

n0 = heard.Count;
mabr.stim.StimulusSet.fromFile(tmp,cfg);      % part 6's bank: no calibration
realAlarm = heardSince(heard,n0,'No calibration data');

% stimgen's own restore, which the designer and SpotCheck load through and
% which had the same ordering. REPORTED, not asserted: it is the submodule's
% behaviour, and a suite must not fail over which commit of an optional
% dependency happens to be checked out. MABR's route above is quiet either way.
n0 = heard.Count;
viaStimgen   = stimgen.StimType.fromStruct(tc.toStruct);
stimgenQuiet = ~heardSince(heard,n0,'No calibration data');
clear cs

assert(set3.numStimuli == 4,'Calibrated bank gave %d entries.',set3.numStimuli);
assert(set3.isCalibrated(), ...
    'A bank saved WITH its calibration imported as uncalibrated.');

% The file route against the live object, which never passes through
% readBank: same calibration, same parameters, so the same samples.
setLive = mabr.stim.fromStimgen(tc,cfg);
assert(isequal(set3.IDs(),setLive.IDs()), ...
    'The bank file and the live stimulus disagree about the conditions.');
for i = 1:set3.numStimuli
    m = set3.meta(i);
    assert(isequal(set3.signal(i),setLive.signal(i)), ...
        ['Entry %d ("%s"): the waveform read back from the bank is not the ' ...
         'one the calibrated stimulus generates.'],i,m.ID);
    assert(~isfield(m,'LevelScale'), ...
        ['Entry %d ("%s") was rescaled relative to the bank -- that is for ' ...
         'an UNCALIBRATED bank; these volts came from a measurement.'],i,m.ID);

    % And against the table itself: a Tone is normalized to a unit peak and
    % gated with a plateau, so its peak IS the drive voltage.
    vWant = cal.compute_adjusted_voltage("tone",m.Frequency*1000,m.Level);
    vGot  = max(abs(double(set3.signal(i))));
    assert(abs(vGot - vWant) <= 1e-4*vWant, ...
        ['Entry %d ("%s") peaks at %.6g V; the calibration asks for %.6g V ' ...
         'at %g kHz, %g dB.'],i,m.ID,vGot,vWant,m.Frequency,m.Level);
end

[lbl,detail] = set3.describeSource();
assert(contains(lbl,'(calibrated)') && ~contains(lbl,'uncalibrated'), ...
    'A calibrated bank describes itself as "%s".',lbl);
assert(contains(detail,'2026-09-29 10:59:22'), ...
    'The bank''s description does not say which calibration ("%s").',detail);

assert(~falseAlarm, ...
    ['Importing a CALIBRATED bank raised stimgen''s "No calibration data" ' ...
     'warning. The waveforms are right; the log says they are not.']);
assert(realAlarm, ...
    ['Importing an UNCALIBRATED bank raised no "No calibration data" warning ' ...
     '-- so its absence above proves nothing, and a bank with no calibration ' ...
     'behind it loads without a word from stimgen.']);
fprintf(['  calibrated .spl: LUT volts, identical to the live stimulus, says ' ...
         '"%s", no false alarm\n'],lbl);

assert(viaStimgen.ApplyCalibration && ~isempty(viaStimgen.Calibration.CalibrationData), ...
    'stimgen.StimType.fromStruct dropped the calibration it was given.');
if stimgenQuiet
    fprintf('  stimgen''s own fromStruct restores a calibrated stimulus quietly\n');
else
    fprintf(['  NOTE: stimgen''s own fromStruct still raises "No calibration data" on a\n' ...
             '        calibrated stimulus -- an older submodule; the designer will log it\n' ...
             '        when it loads a calibrated bank. MABR''s import is unaffected.\n']);
end

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
assert(contains(fn,'_Frequency-') && contains(fn,'kHz_Level-') && endsWith(fn,'.abr'), ...
    'Filename "%s" does not match the offline pipeline''s shape.',fn);
fprintf('  filename: %s\n',fn);

% --- 8. Tone polarity ------------------------------------------------
pos = stimgen.Tone(Frequency=[8000 16000],Duration=0.02);
neg = stimgen.Tone(Frequency=[8000 16000],Duration=0.02,Polarity=-1);
alt = stimgen.Tone(Frequency=[8000 16000],Duration=0.02,Polarity=0);
setPos = mabr.stim.fromStimgen(pos,cfg);
setNeg = mabr.stim.fromStimgen(neg,cfg);
setAlt = mabr.stim.fromStimgen(alt,cfg);

assert(setAlt.numStimuli == 2, ...
    ['Alternating polarity made %d entries from 2 frequencies -- it must not ' ...
     'add a variant (that is what OnsetPhase = [0 180] is for).'],setAlt.numStimuli);
assert(all(setAlt.alternatesPolarity()) && ~any(setPos.alternatesPolarity()) ...
    && ~any(setNeg.alternatesPolarity()), ...
    'Only Polarity = 0 should import as alternatePolarity.');
for i = 1:2
    assert(isequal(setNeg.signal(i),-setPos.signal(i)), ...
        'Polarity = -1 entry %d is not the inverted Polarity = 1 waveform.',i);
    assert(isequal(setAlt.signal(i),setPos.signal(i)), ...
        'Polarity = 0 entry %d is not generated positive (the schedule flips it).',i);
end

% Repetitions are split between the signs, per stimulus.
schA = mabr.stim.Schedule(setAlt,cfg);
schA.Repetitions(:) = 6;
schA.ISI = 0.05;
schA.build();
for r = 1:schA.NumRuns
    seq = schA.runSequence(r);
    pol = schA.runPolarity(r);
    for k = unique(seq(:))'
        pk = pol(seq == k);
        assert(numel(pk) == 6 && sum(pk == 1) == 3 && sum(pk == -1) == 3, ...
            'Stimulus %d: polarities %s, expected 3 x +1 and 3 x -1.',k,mat2str(pk(:)'));
    end
end

% Polarity survives a bank save (it is a UserProperty).
back = stimgen.StimType.fromStruct(alt.toStruct);
assert(isequal(back.Polarity,0),'Tone.Polarity did not survive toStruct/fromStruct.');

% A ClickTrain's Polarity = 0 alternates inside its own waveform; flipping
% whole presentations as well is not what it means.
ck = stimgen.ClickTrain(Polarity=0,Duration=0.02,Rate=200);
assert(~any(mabr.stim.fromStimgen(ck,cfg).alternatesPolarity()), ...
    'A ClickTrain was imported as alternatePolarity; its alternation is in-waveform.');

% Polarity = 2 alternates PRESENTATIONS -- the one a single click needs, since
% with one click there is nothing to alternate within. Generated positive.
one    = stimgen.ClickTrain(Duration=0.005,Rate=100,ClickDuration=1e-4);
onePos = mabr.stim.fromStimgen(one,cfg);
one.Polarity = 2;
oneAlt = mabr.stim.fromStimgen(one,cfg);
assert(all(oneAlt.alternatesPolarity()) && ~any(onePos.alternatesPolarity()), ...
    'ClickTrain Polarity = 2 did not import as alternatePolarity.');
assert(isequal(oneAlt.signal(1),onePos.signal(1)), ...
    'ClickTrain Polarity = 2 is not generated positive (the schedule flips it).');
assert(max(oneAlt.signal(1)) > 0 && min(oneAlt.signal(1)) >= 0, ...
    'A single-click ClickTrain under Polarity = 2 is not a positive click.');
fprintf(['  polarity: Tone -1 inverts, 0 alternates presentations (3 + 3 of 6); ' ...
         'ClickTrain 2 alternates presentations, 0 stays in-train\n']);

fprintf('== verify_stimgen_import PASSED ==\n');
end

% =========================================================================
function delete_if(f)
if isfile(f), delete(f); end
end

% =========================================================================
function hear(heard,level,msg)
% A stimgen.LogSink must never throw (stimgen logs from inside catch blocks).
try
    if isa(msg,'MException') || isstruct(msg), msg = msg.message; end
    k = heard.Count + 1;
    % A containers.Map is a handle: this writes into the caller's map.
    heard(k) = struct('Level',level,'Text',char(string(msg))); %#ok<NASGU>

catch
end
end

% =========================================================================
function tf = heardSince(heard,after,pattern)
% Whether any message numbered above `after` contains `pattern`.
tf = false;
for k = after+1:heard.Count
    m = heard(k);       % a containers.Map takes one level of indexing
    if contains(m.Text,pattern), tf = true; return; end
end
end
