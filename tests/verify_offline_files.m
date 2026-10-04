function verify_offline_files()
% verify_offline_files  The offline file layer: AbrFile, Stats and prefGuard, no hardware.
%
%   mabr.analysis.AbrFile is the one reader every offline consumer goes
%   through, so a wrong answer here is a wrong answer everywhere. Every claim
%   below is held against files whose every field is known, because
%   mabrtest.SyntheticABR wrote them, or against an edited copy of one.
%
%   Part A  a session as the rig writes one: current names, tones and clicks,
%           continuous and compact layouts, the E0 legacy file, a Test Mode
%           file, an 11025 Hz file, a truncated compact window, notes -- every
%           field of every file against what was written
%   Part B  the "old" and "stimgen" naming styles: one subject however spelled
%   Part C  edited files: reserved, lower-case and duplicate parameters, an E0
%           parameter with no dataParams, the three units eras, level units,
%           dropped onsets (0, negative, Inf, NaN) with their numbers kept,
%           mismatched flags, the truncation boundary, files that are not
%           recordings (a legacy -v7.3 output file of a missing class among
%           them), a corrupt file, a missing file and a <missing> path,
%           unusable fields, non-finite samples (a warning, still Ok)
%   Part D  warnings: captured in rec.Warnings, nothing printed, the caller's
%           warning state (even a warning set to 'error') and lastwarn untouched
%   Part E  subjects: subjectOf and canonicalSubject
%   Part F  drift: SyntheticABR's field set is mabr.data.io.buildStruct's, and
%           a file the real writer builds reads back
%   Part G  Stats: percentiles (bit for bit Threshold.percentile's rule), F and
%           t tails, quantiles, FNV-1a, seeds, keys, natural sort, isoTime,
%           balancedMean
%   Part H  mabrtest.prefGuard on a throwaway pref
%   Part I  static scan: no Statistics Toolbox function in AbrFile or Stats --
%           and a planted one is caught, so the scan can fail
%
%   Everything is written under one tempname folder removed on the way out.
%   The only preferences touched are the throwaway MABR/OfflineTestProbe and
%   OfflineTestProbe2, put back as they were. The global random stream is
%   never drawn from, and that is asserted.
%
%   Run:  >> verify_offline_files
%
%   See also mabr.analysis.AbrFile, mabr.analysis.Stats, mabrtest.prefGuard,
%   mabrtest.SyntheticABR.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_files ==\n');
tAll  = tic;
rng0  = rng;
figs0 = findall(groot,'Type','figure');
root  = string(tempname);
mkdir(root);
cleanup = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(root));

truth = mabrtest.SyntheticABR.defaults();
n  = truth.nSweeps;
Fs = truth.Fs;

% =========================================================================
%  Part A -- a session as the rig writes one
% =========================================================================
txt = {'Gerbil anesthetized','Impedance 3.2 kOhm','Ear plug slipped'};
I = mabrtest.SyntheticABR.writeSession(fullfile(root,'current'),truth, ...
    Stimuli=["Tone" "ClickTrain"],Layout="both",Legacy=true,TestModeFile=true, ...
    OtherRateFile=true,Truncated=true,Notes=txt);
F = I.Files;
nFiles = height(F);
tRead = 0;
seen = struct('compact',0,'truncated',0,'legacy',0,'testmode',0,'otherrate',0,'click',0);
for i = 1:nFiles
    ffn  = fullfile(I.Folder,F.FileName(i));
    what = F.FileName(i);
    A    = loadABR(ffn);
    t0   = tic;
    [rec,trace,sw,notes] = mabr.analysis.AbrFile.read(ffn,ReadNotes=true);
    tRead = tRead + toc(t0);

    % ---- every file
    assert(rec.Ok && ~rec.Skipped && rec.Error == "",'%s: not Ok (%s).',what,rec.Error);
    assert(isempty(rec.Warnings),'%s: unexpected warnings: %s',what,strjoin(rec.Warnings,' | '));
    d = dir(ffn);
    assert(strcmpi(rec.Path,string(fullfile(d.folder,d.name))) && rec.FileName == what && ...
        strcmpi(rec.Folder,string(d.folder)),'%s: Path/Folder/FileName wrong (%s).',what,rec.Path);
    assert(rec.Bytes == d.bytes && ~isnat(rec.Modified),'%s: Bytes/Modified wrong.',what);
    assert(rec.Subject == "SUBJ-ID-9001",'%s: Subject "%s".',what,rec.Subject);
    assert(rec.SampleRate == A.ADC.SampleRate && rec.SampleRate == F.SampleRate(i), ...
        '%s: SampleRate %g.',what,rec.SampleRate);
    assert(rec.NumSweeps == n && rec.NumSweeps == F.nSweeps(i),'%s: NumSweeps %d.',what,rec.NumSweeps);
    assert(rec.SweepLength == A.ADC.SweepLength,'%s: SweepLength %g.',what,rec.SweepLength);
    assert(abs(rec.Duration - numel(A.ADC.Data)/A.ADC.SampleRate) < 1e-12,'%s: Duration.',what);
    assert(rec.StartTime == F.StartTime(i),'%s: StartTime %s, written %s.',what, ...
        string(rec.StartTime),string(F.StartTime(i)));
    assert(rec.TestMode == F.TestMode(i),'%s: TestMode.',what);
    assert(rec.Layout == F.Layout(i),'%s: Layout %s, written %s.',what,rec.Layout,F.Layout(i));
    isComp = F.Layout(i) == "compact";
    assert(mabr.analysis.AbrFile.isCompact(A.ADC.SweepOnsets,A.ADC.SweepLength,numel(A.ADC.Data)) == isComp, ...
        '%s: isCompact disagrees with the layout written.',what);
    on = double(A.ADC.SweepOnsets(:));
    if isComp
        assert(rec.AcqMode == "interleaved" && isnan(rec.MinISI),'%s: compact AcqMode/MinISI.',what);
        assert(isequal(on,(0:n-1)'*rec.SweepLength + 1),'%s: compact onsets.',what);
        seen.compact = seen.compact + 1;
    else
        assert(rec.AcqMode == "conventional",'%s: AcqMode %s.',what,rec.AcqMode);
        assert(abs(rec.MinISI - min(diff(on))/rec.SampleRate*1000) < 1e-9,'%s: MinISI.',what);
    end

    % ---- the sweeps
    assert(isequal(sw.Onset,on) && iscolumn(sw.Onset),'%s: sw.Onset.',what);
    assert(isequal(sw.Index,1:n),'%s: sw.Index.',what);
    assert(isequal(sw.IsArtifact,ismember(1:n,F.FlaggedSweeps{i})),'%s: sw.IsArtifact.',what);
    if F.Legacy(i)
        assert(isequal(sw.Polarity,ones(1,n)),'%s: legacy polarity is not all +1.',what);
    else
        assert(isequal(sw.Polarity,double(A.ADC.SweepPolarity(:))'),'%s: sw.Polarity.',what);
    end
    wantValid = true(1,n);
    if F.Truncated(i), wantValid(end) = false; seen.truncated = seen.truncated + 1; end
    assert(isequal(sw.Valid,wantValid) && rec.TruncatedSweeps == double(F.Truncated(i)), ...
        '%s: Valid/TruncatedSweeps (%d).',what,rec.TruncatedSweeps);
    assert(isa(trace,'single') && isequal(trace,A.ADC.Data(:)),'%s: trace.',what);

    % ---- notes
    if isfield(A,'Notes')
        assert(numel(notes) == numel(A.Notes) && iscolumn(notes),'%s: %d notes, file has %d.', ...
            what,numel(notes),numel(A.Notes));
        for q = 1:numel(notes)
            r = A.Notes(q);
            assert(notes(q).Stamp == string(r.Stamp) && notes(q).Text == string(r.Text) && ...
                notes(q).Time == datetime(r.Time,'InputFormat','yyyy-MM-dd''T''HH:mm:ss') && ...
                isequaln(notes(q).Run,r.Run) && isequaln(notes(q).Sweep,r.Sweep), ...
                '%s: note %d read wrong.',what,q);
        end
    else
        assert(isempty(notes) && isequal(size(notes),[0 1]) && ...
            isequal(fieldnames(notes),{'Stamp';'Text';'Time';'Run';'Sweep';'Source'}), ...
            '%s: a file without Notes gave notes.',what);
    end

    % ---- era, stimulus, parameters, units
    if F.Legacy(i)
        seen.legacy = seen.legacy + 1;
        assert(rec.Era == "E0" && rec.SubjectRaw == "SUBJ_ID_9001",'%s: Era/SubjectRaw.',what);
        assert(rec.Stimulus == "" && rec.StimClass == "" && rec.StimID == "",'%s: legacy stimulus.',what);
        assert(isequal(rec.ParamNames,["Frequency" "Level"]),'%s: legacy ParamNames %s.',what, ...
            strjoin(rec.ParamNames,','));
        assert(rec.Params.Frequency == F.Frequency(i) && rec.Params.Level == F.Level(i), ...
            '%s: legacy parameters %g kHz %g dB (uint32 placeholders, dataParams in Hz).', ...
            what,rec.Params.Frequency,rec.Params.Level);
        assert(rec.ParamText == sprintf("Frequency=%g; Level=%g",F.Frequency(i),F.Level(i)), ...
            '%s: ParamText %s.',what,rec.ParamText);
        assert(rec.Units == "converter" && isnan(rec.AmplifierGain) && isnan(rec.InputFullScale), ...
            '%s: legacy units.',what);
        assert(~rec.Calibrated && rec.LevelUnit == "dB" && ~rec.AlternatePolarity && ...
            rec.CalibrationTime == "" && isnan(rec.LevelScale),'%s: legacy level/polarity.',what);
        assert(rec.SweepLength == round(Fs*0.010) + 1 && rec.DACSampleRate == truth.DACSampleRate, ...
            '%s: legacy geometry.',what);
        assert(isscalar(A.ADC.IsArtifact) && ~any(sw.IsArtifact),'%s: scalar IsArtifact.',what);
    else
        assert(rec.Era == "E1+" && rec.SubjectRaw == "SUBJ-ID-9001",'%s: Era/SubjectRaw.',what);
        st = F.Stimulus(i);
        assert(rec.Stimulus == st && rec.StimClass == "stimgen." + st,'%s: Stimulus %s / %s.', ...
            what,rec.Stimulus,rec.StimClass);
        if st == "Tone"
            id = matlab.lang.makeValidName(sprintf('Tone_Frequency%g_SoundLevel%g',F.Frequency(i)*1000,F.Level(i)));
            assert(rec.StimID == id,'%s: StimID %s.',what,rec.StimID);
            assert(isequal(rec.ParamNames,["Level" "Frequency"]) && ...
                rec.Params.Level == F.Level(i) && rec.Params.Frequency == F.Frequency(i), ...
                '%s: tone parameters.',what);
            assert(rec.ParamText == sprintf("Frequency=%g; Level=%g",F.Frequency(i),F.Level(i)), ...
                '%s: ParamText %s.',what,rec.ParamText);
        else
            seen.click = seen.click + 1;
            assert(rec.StimID == sprintf("ClickTrain_SoundLevel%g",F.Level(i)),'%s: StimID %s.',what,rec.StimID);
            assert(isequal(rec.ParamNames,"Level") && rec.Params.Level == F.Level(i) && ...
                ~isfield(rec.Params,'Frequency') && rec.ParamText == sprintf("Level=%g",F.Level(i)), ...
                '%s: click parameters.',what);
        end
        assert(rec.Units == "V" && rec.AmplifierGain == truth.AmplifierGain && ...
            rec.InputFullScale == truth.InputFullScale,'%s: units.',what);
        assert(rec.Calibrated && rec.LevelUnit == "dB SPL" && isnan(rec.LevelScale) && ...
            rec.CalibrationTime == string(A.SIG.CalibrationTime) && rec.CalibrationTime ~= "", ...
            '%s: calibration fields.',what);
        assert(rec.AlternatePolarity && rec.DACSampleRate == A.DAC.SampleRate,'%s: alternation/DAC rate.',what);
    end
    if F.TestMode(i)
        seen.testmode = seen.testmode + 1;
        assert(rec.TestMode && rec.Stimulus == "Tone",'%s: Test Mode file.',what);
    end
    if F.SampleRate(i) == 11025
        seen.otherrate = seen.otherrate + 1;
        assert(rec.SampleRate == 11025 && rec.SweepLength == 110 && rec.DACSampleRate == 176400, ...
            '%s: the 11025 Hz file reads %g Hz, L %g, DAC %g.',what,rec.SampleRate,rec.SweepLength,rec.DACSampleRate);
    end
end
nF = numel(truth.Freqs);  nL = numel(truth.Levels);
assert(seen.compact == nF*nL && seen.truncated == 1 && seen.legacy == 1 && seen.testmode == 1 && ...
    seen.otherrate == 1 && seen.click == nL,'Part A did not meet every kind of file it should have.');

% literal spot values, so the comparisons above are not merely self-consistent
kc = find(F.Layout == "continuous" & ~F.Legacy & F.SampleRate == Fs & ~F.TestMode,1);
kk = find(F.Layout == "compact",1);
rc = mabr.analysis.AbrFile.read(fullfile(I.Folder,F.FileName(kc)),ReadTrace=false);
rk = mabr.analysis.AbrFile.read(fullfile(I.Folder,F.FileName(kk)),ReadTrace=false);
assert(abs(rc.MinISI - 292/12) < 1e-9 && abs(rc.Duration - 39476/12000) < 1e-12 && ...
    abs(rk.Duration - 1.28) < 1e-12 && rk.SweepLength == 120,'Spot values wrong.');
% metadata-only reads give the same record and no trace
for k = [kc kk]
    ffn = fullfile(I.Folder,F.FileName(k));
    [r1,t1] = mabr.analysis.AbrFile.read(ffn);
    [r2,t2,sw2,n2] = mabr.analysis.AbrFile.read(ffn,ReadTrace=false);
    assert(isequaln(r1,r2) && ~isempty(t1) && isempty(t2) && sw2.Onset(1) >= 1 && isempty(n2), ...
        'ReadTrace=false changed the record of %s.',F.FileName(k));
end
fprintf(['  PASS Part A: %d files (%d compact, 1 truncated, 1 E0 legacy, 1 Test Mode, ' ...
    '1 at 11025 Hz, %d clicks), every field as written; %.1f ms per read\n'], ...
    nFiles,seen.compact,seen.click,1000*tRead/nFiles);

% =========================================================================
%  Part B -- naming styles
% =========================================================================
Tq = truth;
Tq.Freqs = [4 16];  Tq.Threshold = [30 40];  Tq.Levels = [40 80];  Tq.nSweeps = 8;
for style = ["old" "stimgen"]
    Ik = mabrtest.SyntheticABR.writeSession(fullfile(root,style),Tq, ...
        Stimuli=["Tone" "ClickTrain"],NamingStyle=style);
    for i = 1:height(Ik.Files)
        what = Ik.Files.FileName(i);
        rec  = mabr.analysis.AbrFile.read(fullfile(Ik.Folder,what),ReadTrace=false);
        st   = Ik.Files.Stimulus(i);
        raw  = "SUBJ_ID_9001";
        if style == "old" && st == "Tone", raw = "SUBJ-ID-9001"; end
        assert(rec.Ok && rec.Subject == "SUBJ-ID-9001" && rec.SubjectRaw == raw, ...
            '%s (%s names): Subject %s / raw %s.',what,style,rec.Subject,rec.SubjectRaw);
        assert(rec.Stimulus == st && rec.NumSweeps == Tq.nSweeps,'%s: Stimulus/NumSweeps.',what);
        if st == "Tone"
            assert(isequal(rec.ParamNames,["Level" "Frequency"]) && startsWith(rec.StimID,"Tone_Frequency"), ...
                '%s: tone metadata.',what);
        else
            assert(isequal(rec.ParamNames,"Level") && startsWith(rec.StimID,"ClickTrain_SoundLevel"), ...
                '%s: click metadata.',what);
        end
    end
end
fprintf('  PASS Part B: "old" and "stimgen" names -- SUBJ_ID_9001 and SUBJ-ID-9001 are one subject\n');

% =========================================================================
%  Part C -- edited files
% =========================================================================
E = fullfile(root,'edited');
mkdir(E);
iTone = find(F.Stimulus == "Tone" & F.Layout == "continuous" & ~F.Legacy & ~F.TestMode & ...
    F.SampleRate == Fs & F.Frequency == 8 & F.Level == 80,1);
iComp = find(F.Layout == "compact" & ~F.Truncated & F.Frequency == 16 & F.Level == 80,1);
iLeg  = find(F.Legacy,1);
A0 = loadABR(fullfile(I.Folder,F.FileName(iTone)));
AC = loadABR(fullfile(I.Folder,F.FileName(iComp)));
AL = loadABR(fullfile(I.Folder,F.FileName(iLeg)));
on0  = double(A0.ADC.SweepOnsets(:));
pol0 = double(A0.ADC.SweepPolarity(:))';

% C1 reserved names, the mapping, and the first of two names kept
A = A0;
A.SIG.informativeParams = {'Level','Frequency','Polarity','units','soundLevel','Key'};
A.SIG.Polarity = 1;  A.SIG.units = 3;  A.SIG.soundLevel = 99;  A.SIG.Key = 7;
rec = readEdited(E,'C1_reserved.abr',A);
assert(rec.Ok && isequal(rec.ParamNames,["Level" "Frequency" "Stim_Polarity" "Stim_units" "Stim_Key"]), ...
    'C1: ParamNames %s.',strjoin(rec.ParamNames,','));
assert(rec.Params.Stim_Polarity == 1 && rec.Params.Stim_units == 3 && rec.Params.Stim_Key == 7 && ...
    rec.Params.Level == 80,'C1: values (soundLevel must not replace Level).');
assert(numel(rec.Warnings) == 4 && sum(contains(rec.Warnings,"Stim_")) == 3 && ...
    any(contains(rec.Warnings,"twice")),'C1: warnings %s.',strjoin(rec.Warnings,' | '));
assert(rec.ParamText == "Frequency=8; Level=80; Stim_Key=7; Stim_Polarity=1; Stim_units=3", ...
    'C1: ParamText %s.',rec.ParamText);

% C2 lower-case names in an E1+ file (kHz already: no division), and a
%    parameter that is not a number
A = A0;
A.SIG = rmfield(A.SIG,{'Level','Frequency'});
A.SIG.informativeParams = {'frequency','soundLevel','Rate'};
A.SIG.frequency = 8;  A.SIG.soundLevel = 30;  A.SIG.Rate = 'fast';
rec = readEdited(E,'C2_lowercase.abr',A);
assert(rec.Ok && isequal(rec.ParamNames,["Frequency" "Level" "Rate"]) && ...
    rec.Params.Frequency == 8 && rec.Params.Level == 30 && isnan(rec.Params.Rate), ...
    'C2: lower-case names read %s.',rec.ParamText);
assert(isscalar(rec.Warnings) && contains(rec.Warnings,"Rate") && contains(rec.Warnings,"NaN"), ...
    'C2: warnings %s.',strjoin(rec.Warnings,' | '));

% C3 an E0 file: uint32 placeholders rejected, Hz from dataParams, and a
%    parameter dataParams does not hold
A = AL;
A.SIG.dataParams = struct('frequency',16000);
rec = readEdited(E,'C3_legacy.abr',A);
assert(rec.Ok && rec.Era == "E0" && rec.Params.Frequency == 16 && isnan(rec.Params.Level), ...
    'C3: E0 parameters %s.',rec.ParamText);
assert(isscalar(rec.Warnings) && contains(rec.Warnings,"soundLevel") && contains(rec.Warnings,"uint32"), ...
    'C3: warnings %s.',strjoin(rec.Warnings,' | '));

% C4 the three units eras
A = A0;
A.ADC = rmfield(A.ADC,'InputFullScale');
rec = readEdited(E,'C4_unscaled.abr',A);
assert(rec.Units == "V-unscaled" && rec.AmplifierGain == truth.AmplifierGain && isnan(rec.InputFullScale), ...
    'C4: no InputFullScale reads %s.',rec.Units);
A.ADC = rmfield(A.ADC,'AmplifierGain');
rec = readEdited(E,'C4_converter.abr',A);
assert(rec.Units == "converter" && isnan(rec.AmplifierGain),'C4: neither reads %s.',rec.Units);

% C5 level units: uncalibrated with and without LevelScale
A = A0;
A.SIG.Calibrated = false;  A.SIG.LevelScale = 0.5;
rec = readEdited(E,'C5_relative.abr',A);
assert(~rec.Calibrated && rec.LevelUnit == "dB re max" && rec.LevelScale == 0.5, ...
    'C5: uncalibrated + LevelScale reads %s.',rec.LevelUnit);
A.SIG = rmfield(A.SIG,'LevelScale');
rec = readEdited(E,'C5_uncalibrated.abr',A);
assert(rec.LevelUnit == "dB" && isnan(rec.LevelScale),'C5: uncalibrated reads %s.',rec.LevelUnit);

% C6 onsets before sample 1 dropped, every other sweep keeping its number
A = A0;
A.ADC.SweepOnsets(1) = 0;  A.ADC.SweepOnsets(2) = -3;
[rec,~,sw] = readEdited(E,'C6_onset0.abr',A);
assert(rec.Ok && rec.NumSweeps == n-2 && isequal(sw.Index,3:n) && isequal(sw.Onset,on0(3:n)), ...
    'C6: dropped onsets (NumSweeps %d, Index starts %d).',rec.NumSweeps,sw.Index(1));
assert(isequal(find(sw.IsArtifact),find(sw.Index == 40)) && isequal(sw.Polarity,pol0(3:n)), ...
    'C6: flags and polarity are not carried with their sweeps.');
assert(isscalar(rec.Warnings) && contains(rec.Warnings,"2 sweep onset"),'C6: warning %s.', ...
    strjoin(rec.Warnings,' | '));
% ... and onsets that are no sample at all (Inf, NaN) go the same way: an Inf
% kept would be counted as a sweep and then fail every index made from it
A = A0;
A.ADC.SweepOnsets(3) = Inf;  A.ADC.SweepOnsets(4) = NaN;
[rec,~,sw] = readEdited(E,'C6_nonfinite.abr',A);
assert(rec.Ok && rec.NumSweeps == n-2 && isequal(sw.Index,[1 2 5:n]) && ...
    isequal(sw.Onset,on0([1 2 5:n])) && isscalar(rec.Warnings) && contains(rec.Warnings,"2 sweep onset"), ...
    'C6: Inf/NaN onsets must be dropped like an onset of 0 (NumSweeps %d; %s).',rec.NumSweeps, ...
    strjoin(rec.Warnings,' | '));
% ... and flags whose count does not match, a zero polarity
A = A0;
A.ADC.IsArtifact = true(5,1);  A.ADC.SweepPolarity(2) = 0;
[rec,~,sw] = readEdited(E,'C6_flags.abr',A);
assert(~any(sw.IsArtifact) && sw.Polarity(2) == 1 && isscalar(rec.Warnings) && ...
    contains(rec.Warnings,"IsArtifact"),'C6: mismatched IsArtifact / zero polarity.');
A.ADC.SweepPolarity = [1;-1];
[rec,~,sw] = readEdited(E,'C6_polarity.abr',A);
assert(isequal(sw.Polarity,ones(1,n)) && any(contains(rec.Warnings,"SweepPolarity")), ...
    'C6: mismatched SweepPolarity must read as all +1.');

% C7 the truncation boundary: 11 trailing zeros are a recording, 12 (1 ms) a
%    zero-filled window
A = AC;
A.ADC.Data(end-10:end) = 0;
[rec,~,sw] = readEdited(E,'C7_eleven.abr',A);
assert(rec.TruncatedSweeps == 0 && all(sw.Valid),'C7: 11 zeros read as truncated.');
A.ADC.Data(end-11:end) = 0;
[rec,~,sw] = readEdited(E,'C7_twelve.abr',A);
assert(rec.TruncatedSweeps == 1 && ~sw.Valid(end) && all(sw.Valid(1:end-1)) && rec.NumSweeps == n, ...
    'C7: 12 zeros not read as one truncated window.');

% C8 files that are not recordings
ABR_Data = 5;
f5 = fullfile(E,'C8_five.abr');
save(f5,'ABR_Data','-v6');
rec = mabr.analysis.AbrFile.read(f5);
notRec = "not an ABR recording (no ADC.Data/SweepOnsets)";
assert(rec.Skipped && ~rec.Ok && rec.Error == notRec && rec.Era == "",'C8: ABR_Data = 5 not skipped.');
ABR_Data = struct('SIG',struct('Label',{{'ID = x'}}));
fNoADC = fullfile(E,'C8_noadc.abr');
save(fNoADC,'ABR_Data','-v6');
rec = mabr.analysis.AbrFile.read(fNoADC);
assert(rec.Skipped && ~rec.Ok && rec.Error == notRec && rec.Era == "E0",'C8: no ADC not skipped.');
X = 1;
fOther = fullfile(E,'C8_other.abr');
save(fOther,'X','-v6');
[rec,tr,sw,nt] = mabr.analysis.AbrFile.read(fOther,ReadNotes=true);
assert(rec.Skipped && ~rec.Ok && isempty(tr) && isempty(sw.Onset) && isempty(nt) && ...
    any(contains(rec.Warnings,"Variable 'ABR_Data' not found")),'C8: another variable.');
% ... and the legacy -v7.3 "output file" (10 sec. 2.2): ABR_Data an OBJECT of
% a class that no longer exists, which LOAD hands back as a uint32 placeholder
fOut = legacyOutputFile(E);
[rec,tr] = mabr.analysis.AbrFile.read(fOut);
assert(rec.Skipped && ~rec.Ok && rec.Error == notRec && isempty(tr) && rec.Subject == "SUBJ-ID-42" && ...
    any(contains(rec.Warnings,"cannot be instantiated")), ...
    'C8: a -v7.3 output file holding a missing class must be skipped (%s; %s).',rec.Error, ...
    strjoin(rec.Warnings,' | '));

% C9 a corrupt file, a missing file
fBad = fullfile(E,'SUBJ-ID-77_corrupt.abr');
fid = fopen(fBad,'w');
fwrite(fid,uint8(mod((1:600)*37,256)));
fclose(fid);
[rec,tr] = mabr.analysis.AbrFile.read(fBad);
assert(~rec.Ok && ~rec.Skipped && startsWith(rec.Error,"could not load") && isempty(tr) && ...
    rec.Subject == "SUBJ-ID-77" && rec.Bytes == 600,'C9: corrupt file (%s).',rec.Error);
rec = mabr.analysis.AbrFile.read(fullfile(E,'SUBJ_ID_78_absent.abr'));
assert(~rec.Ok && rec.Error == "file not found" && rec.Subject == "SUBJ-ID-78" && ...
    rec.SubjectRaw == "SUBJ_ID_78" && isnan(rec.Bytes),'C9: missing file (%s).',rec.Error);
rec = mabr.analysis.AbrFile.read(string(missing));      % an empty cell of a path column
assert(~rec.Ok && rec.Error == "file not found" && rec.Path == "" && rec.Subject == "", ...
    'C9: a <missing> path must read as no file, not throw.');

% C10 unusable fields: no sample rate, no samples, non-numeric data, a time
%     nobody can parse
A = A0;  A.ADC.SampleRate = 0;
rec = readEdited(E,'C10_rate.abr',A);
assert(~rec.Ok && ~rec.Skipped && contains(rec.Error,"SampleRate"),'C10: rate 0 (%s).',rec.Error);
A = A0;  A.ADC.Data = single([]);
rec = readEdited(E,'C10_empty.abr',A);
assert(~rec.Ok && contains(rec.Error,"no samples"),'C10: empty Data (%s).',rec.Error);
A = A0;  A.ADC.Data = {1};
rec = readEdited(E,'C10_cell.abr',A);
assert(~rec.Ok && contains(rec.Error,"not numeric"),'C10: cell Data (%s).',rec.Error);
A = A0;  A.StartTime = 'not a time';
rec = readEdited(E,'C10_time.abr',A);
assert(rec.Ok && isnat(rec.StartTime),'C10: an unparseable StartTime must be NaT, the file still Ok.');
A = A0;  A = rmfield(A,'TestMode');  A.SIG = rmfield(A.SIG,{'alternatePolarity','Calibrated'});
rec = readEdited(E,'C10_absent.abr',A);
assert(rec.Ok && ~rec.TestMode && ~rec.AlternatePolarity && ~rec.Calibrated && rec.LevelUnit == "dB", ...
    'C10: absent optional fields.');
% C11 non-finite samples (NaN, Inf): still a recording, said in a warning
%     with the count -- the segmenter leaves out the sweeps they reach
A = A0;  A.ADC.Data(500:502) = NaN;  A.ADC.Data(900) = Inf;
[rec,tr,sw] = readEdited(E,'C11_nonfinite.abr',A);
assert(rec.Ok && rec.NumSweeps == numel(sw.Onset) && nnz(~isfinite(tr)) == 4 && ...
    any(contains(rec.Warnings,"4 non-finite sample(s)")), ...
    'C11: non-finite samples (%s; %s).',rec.Error,strjoin(rec.Warnings,' | '));
fprintf(['  PASS Part C: reserved/lower-case/duplicate/E0 parameters, units eras, level units, ' ...
    'dropped onsets (0, <0, Inf, NaN) keep their numbers, truncation at 1 ms of zeros, ' ...
    'non-recordings (a -v7.3 missing-class output file too) skipped, corrupt/missing/unusable ' ...
    'files never throw; non-finite samples warned, the file still a recording\n']);

% =========================================================================
%  Part D -- warnings: captured, silent, the caller's state untouched
% =========================================================================
wCaller = warning;
putBack = onCleanup(@() warning(wCaller));
warning('error','MATLAB:load:variableNotFound');    % a caller who made it fatal
warning('off','verify:offline:quiet');
wBefore = warning;
lastwarn('sentinel message','verify:offline:sentinel');
[o1,r1] = quietRead(fOther);
[o2,r2] = quietRead(fBad);
[o3,r3] = quietRead(fullfile(I.Folder,F.FileName(iTone)));
[o4,r4] = quietRead(fullfile(I.Folder,F.FileName(iLeg)));
out = strtrim([o1 o2 o3 o4]);
assert(isempty(out),'AbrFile.read printed: %s',out);
assert(r1.Skipped && isscalar(r1.Warnings) && r1.Warnings == "load: Variable 'ABR_Data' not found.", ...
    'The load warning was not captured: %s',strjoin(r1.Warnings,' | '));
assert(~r2.Ok && r3.Ok && r4.Ok && isempty(r3.Warnings),'Reads under a strict caller state failed.');
assert(isequal(warning,wBefore),'AbrFile.read changed the global warning state.');
[m,id] = lastwarn;
assert(strcmp(m,'sentinel message') && strcmp(id,'verify:offline:sentinel'), ...
    'AbrFile.read changed lastwarn to "%s" (%s).',m,id);
clear putBack
assert(isequal(warning,wCaller),'The test did not put the warning state back.');
fprintf(['  PASS Part D: load warnings captured in rec.Warnings, nothing printed, a warning set to ' ...
    '''error'' does not fail the read, warning state and lastwarn unchanged\n']);

% =========================================================================
%  Part E -- subjects
% =========================================================================
cases = [ ...
    "C:/data/SUBJ-ID-1254/SUBJ-ID-1254_261001T140000/x.abr",   "SUBJ-ID-1254"
    "SUBJ_ID_1254_ClickTrain_SoundLevel80_261001T142038.abr",   "SUBJ-ID-1254"
    "SUBJ-ID-959_Baseline",                                     "SUBJ-ID-959"
    "C:/data/session_7/file.abr",                               ""
    "C:/study/SUBJ-ID-1/SUBJ-ID-2_x/y.abr",                     "SUBJ-ID-1"
    "subj id abc12 notes.txt",                                  "SUBJ-ID-ABC12"
    "SUBJID42.abr",                                             "SUBJ-ID-42"
    "SUBJECT_7.abr",                                            ""];
got = mabr.analysis.AbrFile.subjectOf(cases(:,1));
for k = 1:size(cases,1)
    assert(got(k) == cases(k,2),'subjectOf("%s") = "%s", expected "%s".',cases(k,1),got(k),cases(k,2));
    assert(mabr.analysis.AbrFile.subjectOf(cases(k,1)) == cases(k,2),'subjectOf scalar call differs.');
end
assert(isequal(size(got),[size(cases,1) 1]),'subjectOf must keep its input''s shape.');
canon = [ ...
    "959",            "SUBJ-ID-959",  "959"
    "subj_id_959",    "SUBJ-ID-959",  "subj_id_959"
    "  SUBJ-ID-1254 ","SUBJ-ID-1254", "SUBJ-ID-1254"
    "rat7",           "SUBJ-ID-RAT7", "rat7"
    "",               "",             ""
    "SUBJ-ID-",       "",             "SUBJ-ID-"];
for k = 1:size(canon,1)
    [s,raw] = mabr.analysis.AbrFile.canonicalSubject(canon(k,1));
    assert(s == canon(k,2) && raw == canon(k,3),'canonicalSubject("%s") = "%s" / "%s".',canon(k,1),s,raw);
end
fprintf('  PASS Part E: subjectOf (first match from the left, any spelling) and canonicalSubject\n');

% =========================================================================
%  Part F -- the writer: field-set drift, and a real writer's file
% =========================================================================
[block,meta] = writerBlock();
ref = mabr.data.io.buildStruct(block);
Aw  = loadABR(fullfile(I.Folder,F.FileName(iTone)));
sameFields(fieldnames(Aw),fieldnames(ref),'top level');
sameFields(fieldnames(Aw.ADC),fieldnames(ref.ADC),'ADC');
sameFields(fieldnames(Aw.DAC),fieldnames(ref.DAC),'DAC');
sameFields(fieldnames(Aw.Notes),fieldnames(ref.Notes),'Notes');
sameFields(setdiff(fieldnames(Aw.SIG),cellstr(Aw.SIG.informativeParams)), ...
    setdiff(fieldnames(ref.SIG),cellstr(ref.SIG.informativeParams)),'SIG (less its parameters)');
% the writer's own file, named and saved as mabr.data.io.writeABR does (without
% its log line, which would land outside tempdir)
W = fullfile(root,'writer');
mkdir(W);
fw = fullfile(W,mabr.data.io.buildFilename(block,'SUBJ_ID_999'));
ABR_Data = ref;
save(fw,'ABR_Data','-mat','-nocompression');
[rec,tr,sw,nt] = mabr.analysis.AbrFile.read(fw,ReadNotes=true);
assert(rec.Ok && isempty(rec.Warnings) && rec.Era == "E1+" && rec.Units == "V" && ...
    rec.Subject == "SUBJ-ID-999" && rec.SubjectRaw == "SUBJ-ID-999",'Writer file: identity/units.');
assert(rec.SampleRate == ref.ADC.SampleRate && rec.Layout == "continuous" && ...
    rec.NumSweeps == numel(ref.ADC.SweepOnsets) && isequal(sw.Onset,double(ref.ADC.SweepOnsets(:))) && ...
    isequal(tr,ref.ADC.Data(:)),'Writer file: samples/sweeps.');
assert(rec.Stimulus == "Tone" && rec.StimID == string(meta.ID) && ...
    isequal(rec.ParamNames,string(meta.informativeParams)) && rec.Params.Frequency == meta.Frequency && ...
    rec.Params.Level == meta.Level && ~isfield(rec.Params,'Polarity'),'Writer file: stimulus/parameters.');
assert(rec.Calibrated && rec.LevelUnit == "dB SPL" && rec.AlternatePolarity && ...
    isequal(sw.Polarity,repmat([1 -1],1,numel(sw.Onset)/2)),'Writer file: calibration/polarity.');
assert(isscalar(nt) && nt.Text == "impedance 3.2 kOhm" && nt.Time == datetime(2026,10,1,9,58,0), ...
    'Writer file: notes.');
fprintf(['  PASS Part F: SyntheticABR carries exactly io.buildStruct''s fields (top, ADC, DAC, ' ...
    'Notes, SIG); the writer''s own file reads back whole\n']);

% =========================================================================
%  Part G -- Stats
% =========================================================================
rs = RandStream('threefry','Seed',20261001);

% percentile: hand values, finite only, shapes, degenerate inputs
q = mabr.analysis.Stats.percentile([1 2 3 4],[0 0.25 0.5 0.9 1]);
assert(isequal(q,[1 1.5 2.5 4 4]),'percentile([1 2 3 4]) = %s.',mat2str(q));
assert(mabr.analysis.Stats.percentile([4 NaN 1 Inf 3 2 -Inf],0.5) == 2.5,'percentile must drop NaN/Inf.');
q = mabr.analysis.Stats.percentile((1:10)',[0.1 0.5; 0.9 NaN]);
assert(isequaln(q,[1.5 5.5; 9.5 NaN]),'percentile must keep p''s shape (and NaN p -> NaN).');
assert(isequal(mabr.analysis.Stats.percentile(7,[0 0.5 1]),[7 7 7]),'percentile of one value.');
assert(isnan(mabr.analysis.Stats.percentile([],0.5)) && isnan(mabr.analysis.Stats.percentile([NaN Inf],0.5)), ...
    'percentile with no finite value must be NaN.');
% ...bit for bit the rule Threshold.percentile applies (a copy of it, below)
for trial = 1:300
    m  = randi(rs,[2 60]);
    x  = randn(rs,m,1).*10.^randi(rs,[-6 3]);
    p  = rand(rs,1,7);
    a  = mabr.analysis.Stats.percentile(x,p);
    b  = thresholdPercentile(x,p);
    assert(isequal(a,b),'percentile differs from Threshold.percentile''s rule (trial %d).',trial);
end
% percentileCols: hand values, NaN per column, agreement with percentile
X = [1 10 NaN; 2 NaN NaN; 3 30 NaN; 4 40 NaN];
Q = mabr.analysis.Stats.percentileCols(X,[0.5 1]);
assert(isequaln(Q,[2.5 30 NaN; 4 40 NaN]),'percentileCols hand values: %s.',mat2str(Q));
X = randn(rs,40,25);  X(rand(rs,40,25) < 0.2) = NaN;  p = [0.025 0.5 0.975];
Q = mabr.analysis.Stats.percentileCols(X,p);
for c = 1:size(X,2)
    assert(isequal(Q(:,c),mabr.analysis.Stats.percentile(X(:,c),p(:))),'percentileCols column %d.',c);
end
% spread
assert(mabr.analysis.Stats.iqr([1 2 3 4]) == 2 && isnan(mabr.analysis.Stats.iqr([])),'iqr.');
assert(mabr.analysis.Stats.mad([1 2 3 4 100 NaN]) == 1 && isnan(mabr.analysis.Stats.mad(NaN)),'mad.');
% the F and t tails
v = mabr.analysis.Stats.fsf(2.250,5,250);
assert(abs(v - 0.05) < 0.002,'fsf(2.25,5,250) = %.5f, expected ~0.05.',v);
Fq = [0.1 0.5 1 2.25 7];
assert(max(abs(mabr.analysis.Stats.fcdf(Fq,5,250) + mabr.analysis.Stats.fsf(Fq,5,250) - 1)) < 1e-12, ...
    'fcdf + fsf ~= 1.');
assert(isequaln(mabr.analysis.Stats.fsf([0 -1 Inf NaN],3,20),[1 1 0 NaN]) && ...
    isequaln(mabr.analysis.Stats.fcdf([0 -1 Inf NaN],3,20),[0 0 1 NaN]),'F tails at the edges.');
assert(all(isnan(mabr.analysis.Stats.fsf(2,[0 -1 NaN Inf],10))),'F tails with an invalid df.');
assert(isequal(size(mabr.analysis.Stats.fsf([1;2;3],[2 4],10)),[3 2]),'F tails must broadcast.');
assert(mabr.analysis.Stats.fcdf(1e308,5,250) == 1 && mabr.analysis.Stats.fsf(1e308,5,250) == 0, ...
    'F tails where d1*F overflows (fcdf used to throw there: betainc refuses Inf/Inf).');
assert(max(abs(mabr.analysis.Stats.fcdf(Fq,2,2) - Fq./(1 + Fq))) < 1e-14, ...
    'fcdf(F,2,2) must be F/(1+F), its closed form.');
v = mabr.analysis.Stats.tcdf(2,10);
assert(abs(v - 0.96331) < 1e-4,'tcdf(2,10) = %.6f, expected 0.96331.',v);
assert(abs(mabr.analysis.Stats.tcdf(-2,10) - (1 - v)) < 1e-14 && mabr.analysis.Stats.tcdf(0,5) == 0.5 && ...
    isequal(mabr.analysis.Stats.tcdf([Inf -Inf],3),[1 0]) && isnan(mabr.analysis.Stats.tcdf(1,0)), ...
    'tcdf symmetry / edges.');
assert(abs(mabr.analysis.Stats.tcdf(1.959963984540054,Inf) - 0.975) < 1e-12,'tcdf with nu = Inf is the normal.');
% closed forms at nu = 1 (Cauchy) and 2, and the large-nu end: betainc with a
% parameter in the tens of millions is 1.3e-3 off (0.5 flat by 1e17), so above
% 1e7 tcdf is the normal; at 1e6 it is still the exact formula, which sits the
% expansion's phi(t)(t^3+t)/(4 nu) below the normal
tt = [-50 -3 -1 -0.2 0 0.2 1 3 50];
assert(max(abs(mabr.analysis.Stats.tcdf(tt,1) - (0.5 + atan(tt)/pi))) < 1e-14 && ...
    max(abs(mabr.analysis.Stats.tcdf(tt,2) - (0.5 + tt./(2*sqrt(2 + tt.^2))))) < 1e-14, ...
    'tcdf closed forms at nu = 1 and 2.');
Phi2 = 0.5*erfc(-2/sqrt(2));
assert(abs(mabr.analysis.Stats.tcdf(2,1e9) - Phi2) < 1e-9 && mabr.analysis.Stats.tcdf(2,1e17) == Phi2 && ...
    abs(mabr.analysis.Stats.tcdf(2,1e6) - (Phi2 - exp(-2)/sqrt(2*pi)*10/4e6)) < 1e-9, ...
    'tcdf at large nu: %.12f at 1e9, %.12f at 1e17 (normal %.12f).', ...
    mabr.analysis.Stats.tcdf(2,1e9),mabr.analysis.Stats.tcdf(2,1e17),Phi2);
tq = mabr.analysis.Stats.tquantile([0.9 0.975 0.995],[3 10 30]);
assert(abs(tq(2) - 2.2281) < 1e-4 && ...
    max(abs(mabr.analysis.Stats.tcdf(tq,[3 10 30]) - [0.9 0.975 0.995])) < 1e-10,'tquantile/tcdf round trip.');
% ...and past the large-nu cut-off, where t_quantile alone gives 1.936
tq = mabr.analysis.Stats.tquantile(0.975,[1e6 3e7 1e9 Inf]);
assert(abs(tq(1) - 1.9599663568) < 1e-8 && all(tq(2:4) == mabr.analysis.Stats.zquantile(0.975)) && ...
    max(abs(mabr.analysis.Stats.tcdf(tq,[1e6 3e7 1e9 Inf]) - 0.975)) < 1e-10 && ...
    isnan(mabr.analysis.Stats.tquantile(1,1e9)),'tquantile at large nu: %s.',mat2str(tq,10));
z = mabr.analysis.Stats.zquantile([0.975 0.5 0 1 1.5]);
assert(abs(z(1)^2 - 3.8415) < 1e-4 && z(2) == 0 && 1/z(2) == Inf && isequal(z(3:4),[-Inf Inf]) && ...
    isnan(z(5)),'zquantile: %s (and +0, not -0, at p = 0.5).',mat2str(z));
assert(abs(mabr.analysis.Stats.zquantile(1e-10) + 6.361340902404056) < 1e-9,'zquantile deep lower tail.');
% FNV-1a
assert(mabr.analysis.Stats.hex8("") == "811c9dc5" && mabr.analysis.Stats.hex8("a") == "e40c292c" && ...
    mabr.analysis.Stats.hex8("foobar") == "bf9cf968",'FNV-1a test vectors.');
h = mabr.analysis.Stats.fnv1a32('a');
assert(isa(h,'uint32') && h == uint32(hex2dec('e40c292c')) && mabr.analysis.Stats.hex8('') == "811c9dc5", ...
    'fnv1a32 class/value, char input.');
mu = string(char([181 115 32 8212 32])) + "SUBJ-ID-959";     % "µs — SUBJ-ID-959"
assert(mabr.analysis.Stats.fnv1a32(mu) == referenceFNV(unicode2native(char(mu),'UTF-8')), ...
    'fnv1a32 must hash the UTF-8 bytes of non-ASCII text.');
assert(strlength(mabr.analysis.Stats.hex8("x")) == 8 && isstring(mabr.analysis.Stats.hex8("x")),'hex8 shape.');
% seeds and streams
k1 = "Stimulus=Tone|AcqMode=conventional|Frequency=8|Level=80";
k2 = "Stimulus=Tone|AcqMode=conventional|Frequency=8|Level=70";
s1 = mabr.analysis.Stats.conditionSeed(1,k1);
assert(s1 == mabr.analysis.Stats.conditionSeed(1,k1) && s1 ~= mabr.analysis.Stats.conditionSeed(1,k2) && ...
    s1 ~= mabr.analysis.Stats.conditionSeed(2,k1) && s1 >= 0 && s1 < 2^32 && s1 == round(s1), ...
    'conditionSeed must be deterministic, key- and seed-sensitive, an integer in [0,2^32).');
assert(mabr.analysis.Stats.conditionSeed(0,"") == 2166136261 && ...
    mabr.analysis.Stats.conditionSeed(2^32 - 1,"a") == mod(2^32 - 1 + hex2dec('e40c292c'),2^32), ...
    'conditionSeed arithmetic.');
r1 = mabr.analysis.Stats.conditionStream(1,k1);
r2 = mabr.analysis.Stats.conditionStream(1,k1);
r3 = mabr.analysis.Stats.conditionStream(1,k2);
d1 = rand(r1,1,5);
assert(isa(r1,'RandStream') && r1.Seed == s1 && contains(lower(r1.Type),'threefry') && ...
    isequal(d1,rand(r2,1,5)) && ~isequal(d1,rand(r3,1,5)),'conditionStream.');
% keys
assert(mabr.analysis.Stats.keyValue(8.000000001) == "8" && mabr.analysis.Stats.keyValue(-0) == "0" && ...
    mabr.analysis.Stats.keyValue(NaN) == "NaN" && mabr.analysis.Stats.keyValue(11.3) == "11.3" && ...
    mabr.analysis.Stats.keyValue(1/3) == "0.333333" && mabr.analysis.Stats.keyValue(true) == "1" && ...
    mabr.analysis.Stats.keyValue(-10) == "-10",'keyValue numbers.');
assert(mabr.analysis.Stats.keyValue("a|b=c") == "a_b_c" && mabr.analysis.Stats.keyValue('Tone') == "Tone" && ...
    isequal(mabr.analysis.Stats.keyValue([8 16]),["8" "16"]),'keyValue text / arrays.');
% natural sort
[s,i] = mabr.analysis.Stats.naturalSort(["SUBJ-ID-1254","SUBJ-ID-959"]);
assert(isequal(s,["SUBJ-ID-959","SUBJ-ID-1254"]) && isequal(i,[2 1]),'naturalSort subjects.');
in = ["a10";"A2";"a2";"b1";"a1b";""];
[s,i] = mabr.analysis.Stats.naturalSort(in);
assert(isequal(s,["";"a1b";"A2";"a2";"a10";"b1"]) && isequal(i,[6;5;2;3;1;4]), ...
    'naturalSort runs/case/ties: %s.',strjoin(s,','));
[s,i] = mabr.analysis.Stats.naturalSort({'x-2','x-10','x-1'});
assert(iscellstr(s) && isequal(s,{'x-1','x-2','x-10'}) && isequal(i,[3 1 2]),'naturalSort cellstr.'); %#ok<ISCLSTR>
[s,i] = mabr.analysis.Stats.naturalSort(["a-1","a1"]);
assert(isequal(s,["a1","a-1"]) && isequal(i,[2 1]),'naturalSort: a shorter run sorts first.');
assert(isempty(mabr.analysis.Stats.naturalSort(strings(0,1))),'naturalSort of nothing.');
% isoTime
t = datetime(2026,10,1,14,30,12);
assert(strcmp(mabr.analysis.Stats.isoTime(t),'2026-10-01T14:30:12') && ...
    strcmp(mabr.analysis.Stats.isoTime(NaT),'') && ...
    strcmp(mabr.analysis.Stats.isoTime(datenum(t)),'2026-10-01T14:30:12') && ...
    isequal(mabr.analysis.Stats.isoTime([t; NaT]),["2026-10-01T14:30:12"; ""]),'isoTime.'); %#ok<DATNM>
% balancedMean against a naive computation
nT = 30;  N = 47;
X  = randn(rs,nT,N);
X(:,1:20) = X(:,1:20) + 3;                      % a level shift between the two files
pol = ones(1,N);  pol(randperm(rs,N,19)) = -1;  % unbalanced counts
strata = [ones(1,20) 2*ones(1,N-20)];
[m,sem,info] = mabr.analysis.Stats.balancedMean(X,pol,strata);
P = pol > 0;  Qn = pol < 0;
mN = (mean(X(:,P),2) + mean(X(:,Qn),2))/2;
ss = zeros(nT,1);  G = 0;
for f = 1:2
    for sg = [-1 1]
        k = strata == f & pol == sg;
        if ~any(k), continue; end
        G  = G + 1;
        ss = ss + sum((X(:,k) - mean(X(:,k),2)).^2,2);
    end
end
s2 = ss/(N - G);
semN = sqrt(s2*(1/sum(P) + 1/sum(Qn))/4);
assert(max(abs(m - mN)) < 1e-12 && max(abs(sem - semN)) < 1e-12 && info.G == G && ...
    info.N == N && info.NPos == sum(P) && info.NNeg == sum(Qn) && info.Balanced && ...
    max(abs(info.S2 - s2)) < 1e-12,'balancedMean differs from the naive per-class computation.');
[m1,sem1,i1] = mabr.analysis.Stats.balancedMean(X,ones(1,N),strata);
assert(max(abs(m1 - mean(X,2))) < 1e-12 && ~i1.Balanced && i1.G == 2 && ...
    max(abs(sem1 - sqrt(i1.S2/N))) < 1e-12,'balancedMean, one polarity.');
[m0,~,i0] = mabr.analysis.Stats.balancedMean(X,[0 pol(2:end)],strata);
assert(i0.NPos == sum(P) + (pol(1) < 0) && isequal(size(m0),[nT 1]),'balancedMean: polarity 0 counts as +1.');
[~,semG,iG] = mabr.analysis.Stats.balancedMean(X(:,1:4),[1 -1 1 -1],1:4);
assert(all(isnan(semG)) && iG.G == 4,'balancedMean with one sweep per group has no SEM.');
[mE,semE,iE] = mabr.analysis.Stats.balancedMean(zeros(5,0),[],[]);
assert(all(isnan(mE)) && all(isnan(semE)) && iE.N == 0,'balancedMean of no sweeps.');
fprintf(['  PASS Part G: Stats -- percentiles (= Threshold.percentile''s rule, bit for bit), ' ...
    'fsf(2.25,5,250) = %.4f, tcdf(2,10) = %.5f, FNV vectors, seeds, keys, natural sort, ' ...
    'isoTime, balancedMean\n'],mabr.analysis.Stats.fsf(2.25,5,250),mabr.analysis.Stats.tcdf(2,10));

% =========================================================================
%  Part H -- prefGuard
% =========================================================================
probe  = 'OfflineTestProbe';
probe2 = 'OfflineTestProbe2';
had0 = [ispref('MABR',probe) ispref('MABR',probe2)];
val0 = {[],[]};
if had0(1), val0{1} = getpref('MABR',probe); end
if had0(2), val0{2} = getpref('MABR',probe2); end
outer = mabrtest.prefGuard([string(probe) string(probe2)]); %#ok<NASGU>
if ispref('MABR',probe),  rmpref('MABR',probe);  end
if ispref('MABR',probe2), rmpref('MABR',probe2); end
% absent before -> absent after
g = mabrtest.prefGuard(probe); %#ok<NASGU>
setpref('MABR',probe,42);
clear g
assert(~ispref('MABR',probe),'prefGuard left a pref that did not exist before.');
% present before -> its value back
setpref('MABR',probe,'before');
g = mabrtest.prefGuard(probe); %#ok<NASGU>
setpref('MABR',probe,'after');
clear g
assert(isequal(getpref('MABR',probe),'before'),'prefGuard did not restore the old value.');
% Clear = true: gone now, back afterwards
g = mabrtest.prefGuard(probe,Clear=true); %#ok<NASGU>
assert(~ispref('MABR',probe),'prefGuard(Clear=true) did not remove the pref.');
setpref('MABR',probe,'during');
clear g
assert(isequal(getpref('MABR',probe),'before'),'prefGuard(Clear=true) did not restore it.');
% "group/name" spelling, several keys, one absent
g = mabrtest.prefGuard(["MABR/" + probe, string(probe2)]); %#ok<NASGU>
rmpref('MABR',probe);
setpref('MABR',probe2,5);
clear g
assert(isequal(getpref('MABR',probe),'before') && ~ispref('MABR',probe2), ...
    'prefGuard with two keys, one in group/name form.');
% restored when the function holding it throws
try
    guardedThrow(probe);
catch ME
    assert(strcmp(ME.identifier,'verify:offline:boom'),'Unexpected error: %s',ME.message);
end
assert(isequal(getpref('MABR',probe),'before'),'prefGuard did not restore after an error.');
clear outer
assert(isequal([ispref('MABR',probe) ispref('MABR',probe2)],had0),'The probe prefs were not put back.');
if had0(1), assert(isequal(getpref('MABR',probe),val0{1}),'The probe pref value was not put back.'); end
fprintf('  PASS Part H: prefGuard restores values, removes what was absent, Clear, group/name, after an error\n');

% =========================================================================
%  Part I -- no Statistics Toolbox function, and a scan that can fail
% =========================================================================
plant = fullfile(root,'planted_scan.m');
fid = fopen(plant,'w');
fprintf(fid,'%s\n', ...
    'function v = mad(x)', ...                  % a definition: allowed
    'y = prctile(x,50);', ...                   % FLAG: a call
    'z = mabr.analysis.Stats.iqr(x);', ...      % qualified: allowed
    '% iqr(x) and corr(a,b) in a comment', ...  % comment: allowed
    's = ''range(1)'';', ...                    % in a string: allowed
    'r = range;', ...                           % FLAG: a variable named range
    'w = x'';', ...                             % a transpose
    'q = x'' + corr(a,b);', ...                 % FLAG: a call after a transpose
    't = "nanmean(x)";', ...                    % in a string: allowed
    'u = obj.range(2); %{', ...                 % qualified: allowed
    'end');
fclose(fid);
[hits,where] = forbiddenUses(plant);
assert(isequal(where,[2;6;8]),'The scan missed or invented: %s',strjoin(hits,' | '));
for cls = ["mabr.analysis.AbrFile" "mabr.analysis.Stats"]
    file = which(cls);
    assert(~isempty(file),'%s not found on the path.',cls);
    hits = forbiddenUses(file);
    assert(isempty(hits),'Statistics Toolbox identifiers in %s:\n%s',cls,strjoin(hits,newline));
end
fprintf('  PASS Part I: AbrFile.m and Stats.m call no Statistics Toolbox function (a planted call is caught)\n');

% =========================================================================
%  Leaks
% =========================================================================
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_files left a figure open.');
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
assert(isequal(rng,rng0),'The global random stream was drawn from.');
clear cleanup
assert(~isfolder(root),'The temporary folder was not removed.');
fprintf('== verify_offline_files PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Helpers
% =========================================================================
function A = loadABR(ffn)
s = load(ffn,'-mat','ABR_Data');
A = s.ABR_Data;
end

function [rec,trace,sw,notes] = readEdited(folder,name,ABR_Data)
% Save an edited ABR_Data as -v6 under folder and read it back.
ffn = fullfile(folder,name);
save(ffn,'ABR_Data','-v6');
[rec,trace,sw,notes] = mabr.analysis.AbrFile.read(ffn,ReadNotes=true);
end

function ffn = legacyOutputFile(folder)
% A -v7.3 file shaped like the legacy +abr "output file" (meta, and ABR_Data
% an abr.ABR OBJECT): here an object of a throwaway class that is removed --
% folder, path entry and loaded definition -- once saved, so LOAD finds the
% class missing exactly as it finds abr.ABR missing on every machine today.
[~,tag] = fileparts(tempname);
pkg  = "mabrOfflineProbe_" + string(regexprep(tag,'\W',''));
cdir = fullfile(folder,'probe_class');
mkdir(fullfile(cdir,"+" + pkg));
fid = fopen(fullfile(cdir,"+" + pkg,'ABR.m'),'w');
fprintf(fid,'%s\n','classdef ABR',' properties', ...
    '  ADC = struct(''Data'',1:10,''SweepOnsets'',1);',' end','end');
fclose(fid);
addpath(cdir);
offPath = onCleanup(@() rmpath(cdir));          % the path comes back, error or not
ABR_Data = feval(pkg + ".ABR");
meta = struct('Subject','SUBJ_ID_42');
ffn = fullfile(folder,'SUBJ_ID_42.abr');
save(ffn,'meta','ABR_Data','-mat','-v7.3');
clear ABR_Data offPath
rmdir(cdir,'s');
clear(char(pkg + ".ABR"));                      % no instance left, so the definition goes
end

function [out,rec] = quietRead(ffn) %#ok<INUSD> used inside the evalc text
% AbrFile.read under evalc: everything it printed, and its record.
rec = [];
out = evalc('rec = mabr.analysis.AbrFile.read(ffn);');
end

function sameFields(a,b,where)
% Two field-name lists hold the same names (order aside).
a = sort(cellstr(a(:)));  b = sort(cellstr(b(:)));
if ~isequal(a,b)
    error('verify:offline:drift',['The writer''s %s fields differ from SyntheticABR''s: ' ...
        'writer only [%s], SyntheticABR only [%s]. Update AbrFile (and bump ReaderVersion) ' ...
        'and SyntheticABR together.'],where,strjoin(setdiff(b,a),' '),strjoin(setdiff(a,b),' '));
end
end

function [block,meta] = writerBlock()
% A Block built as verify_data_roundtrip builds one -- at the DAC rate, the
% writer decimating -- carrying a stimgen tone's metadata and one note, so
% that buildStruct writes every optional field SyntheticABR's files hold.
cfg = mabr.Config;
FsD = cfg.DACSampleRate;
df  = cfg.decimationFactor;
rs  = RandStream('threefry','Seed',5);
nS  = 64;
period = round(FsD/21.1);
data   = single(1e-7*randn(rs,nS*period + period,1));
onsets = (round(0.05*FsD) + (0:nS-1)*period)';
rec  = mabr.data.Recording(FsD,data,onsets,round(0.01*FsD),df);
meta = struct('ID','Tone_Frequency8000_SoundLevel30','Frequency',8,'Level',30,'Polarity',1, ...
    'alternatePolarity',true,'informativeParams',{{'Level','Frequency'}}, ...
    'StimClass','stimgen.Tone','VariantIndex',3,'Calibrated',true, ...
    'CalibrationTime','2026-09-30 16:00:00', ...
    'Label',{{'ID = Tone_Frequency8000_SoundLevel30','Level = 30','Frequency = 8'}});
block = mabr.data.Block(struct('Meta',meta,'SampleRate',FsD),rec,'2026-10-01T10:00:00');
block.SweepPolarity  = repmat([1 -1],1,nS/2);
block.AmplifierGain  = 1000;
block.InputFullScale = 0.354;
r = mabr.data.SessionNotes.blankRecord();
r.Text = 'impedance 3.2 kOhm';  r.Time = '2026-10-01T09:58:00';  r.Stamp = '09:58:00';
block.Notes = r;
end

function q = thresholdPercentile(x,p)
% mabr.analysis.Threshold.percentile as it stands at 219549d, verbatim, so
% Stats.percentile is held to that rule without depending on Threshold.m.
x = sort(x(:));
n = numel(x);
if n == 0, q = nan(size(p)); return; end
pos = p(:).'*n + 0.5;
q = interp1((1:n).',x,min(max(pos,1),n),'linear');
end

function h = referenceFNV(bytes)
% FNV-1a written the textbook way, for the non-ASCII check.
h = uint64(2166136261);
for k = 1:numel(bytes)
    h = bitxor(h,uint64(bytes(k)));
    h = mod(h*uint64(16777619),uint64(2^32));
end
h = uint32(h);
end

function guardedThrow(probe)
% Hold a prefGuard, write the pref, and fail.
g = mabrtest.prefGuard(string(probe)); %#ok<NASGU>
setpref('MABR',probe,'oops');
error('verify:offline:boom','boom');
end

function [hits,where] = forbiddenUses(file)
% Lines of a file that call a Statistics Toolbox function (10 sec. 0) or use
% range/corr/mad as a name: the text of each (hits) and its line number
% (where). Comments and strings are ignored, as is the name a function line
% defines (Stats defines iqr and mad); a name reached through a dot
% (mabr.analysis.Stats.iqr, obj.range) is not the toolbox function.
names = ["prctile","quantile","iqr","mad","range","zscore","nanmean","nanstd","nanmedian", ...
    "corr","fcdf","finv","tcdf","tinv","normcdf","norminv","normpdf","randsample","datasample", ...
    "bootstrp","fitglm","fitlm","boxplot","ksdensity","grpstats","skewness","kurtosis"];
asName  = ["range","corr","mad"];
callPat = "(?<![\w.])(" + join(names,"|") + ")\s*\(";
namePat = "(?<![\w.])(" + join(asName,"|") + ")(?!\w)";
lines = splitlines(string(fileread(file)));
code  = codeOnly(lines);
hits  = strings(0,1);
where = zeros(0,1);
for k = 1:numel(code)
    c = regexprep(code(k),'^(\s*function\s+(?:\[[^\]]*\]\s*=\s*|[\w.]+\s*=\s*)?)[\w.]+','$1');
    if ~isempty(regexp(c,callPat,'once')) || ~isempty(regexp(c,namePat,'once'))
        hits(end+1,1)  = sprintf('%s:%d: %s',file,k,strtrim(lines(k))); %#ok<AGROW>
        where(end+1,1) = k; %#ok<AGROW>
    end
end
end

function out = codeOnly(lines)
% Each line with its comment and the contents of its strings blanked.
% Handles %{ ... %} blocks, '...' continuations, '' and "" escapes, and tells
% a transpose from a char literal by what precedes the quote.
out = strings(size(lines));
inBlock = false;
for k = 1:numel(lines)
    s = char(lines(k));
    t = strtrim(s);
    if inBlock
        if strcmp(t,'%}'), inBlock = false; end
        continue
    end
    if strcmp(t,'%{'), inBlock = true; continue; end
    o = blanks(numel(s));
    q = '';
    i = 1;
    while i <= numel(s)
        ch = s(i);
        if isempty(q)
            if ch == '%' || (i + 2 <= numel(s) && strcmp(s(i:i+2),'...')), break; end
            if ch == '"'
                q = '"';
            elseif ch == ''''
                prev = ' ';
                if i > 1, prev = s(i-1); end
                if isstrprop(prev,'alphanum') || any(prev == '_)]}.''')
                    o(i) = ch;              % a transpose
                else
                    q = '''';
                end
            else
                o(i) = ch;
            end
        elseif ch == q
            if i < numel(s) && s(i+1) == q
                i = i + 1;                  % a doubled quote stays in the string
            else
                q = '';
            end
        end
        i = i + 1;
    end
    out(k) = string(o);
end
end
