function verify_offline_export()
% verify_offline_export  Export: tidy tables, censoring, CSV/XLSX/Parquet/MAT, R script, raw tables.
%
%   Checks mabr.analysis.Export against HAND-BUILT results structs in the
%   results-v2 shape (10 §16.1) -- a tone grid whose five series cover every
%   censoring case (interval from a manual level, right, left, none, an
%   excluded series) with manual and absent peaks, a click series recorded in
%   Test Mode, and the tone session again as a session out of the study -- so
%   that every expected number below is written down rather than computed by
%   the code under test:
%
%     A  schema() and columnName(): one row per column, the naming rules
%     B  tables(): every table built, its columns exactly the schema's in the
%        schema's order, dictionary(T) complete, no Inf anywhere
%     C  thresholds: the censoring columns of each case, imputation, final
%        value = SeriesThreshold.finalValue of the stored row
%     D  ThresholdsAll: a row per built-in method per series from the stored
%        per-condition columns, only the primary carrying curation; the
%        recomputed perm-descending intervals
%     E  peaks (offset latencies, NA amplitudes where they must be,
%        level_re_thr_db), peak_measures and io_slopes (uV, offset intercepts)
%     F  sessions, subjects, conditions, waveforms (from Means, no raw data),
%        trials (from SweepInfo), notes; the OnlyReviewed / IncludeExcluded /
%        IncludeTestMode filters
%     G  CSV: readtable round trip, no NaN/Inf text, TRUE/FALSE, ISO times,
%        UTF-8 with a non-ASCII note
%     H  XLSX: small tables only, a 1.1e6-row table refused, 31-char sheets
%     I  Parquet (SKIP without parquetwrite): small files, a per-session
%        dataset for a large table, read back
%     J  MAT: one struct MABRExport
%     K  mabr_import.R, mabr_columns.csv, mabr_export.json/mabr_settings.json
%     L  estimate(): rows, XLSXAllowed, NeedsRaw, a 1.1e6-row metadata check
%     M  writeRaw over a session-shaped struct: trial_waves, blocks,
%        block_waves, sweeps (Parquet, MAT; CSV refused), CSV appends that
%        reconcile columns; tables() building the same raw tables in memory
%     N  stack(), the progress sink and cancel, error ids, per-table formats,
%        a results FILE as input, a v1 results struct
%     O  writeRaw over a real Session built from SyntheticABR files, its
%        results-only twin refused, tables() over its real results v2 (SKIP
%        when the Session API it needs is not there yet)
%     P  sound conduction delay (A9): latencies re sound arrival from the
%        stored LatencyOffset, a label override, the settings, or none;
%        conduction_delay_ms/time_offset_ms/lat_peak_raw_ms in peaks,
%        peak_measures, trial_waves and block_waves; IPLs unchanged
%     Q  -Inf (no response on an attenuation axis) encoded like Inf: the
%        bound, fallback bounds, sensation level, ThresholdsAll, no Inf text
%     R  appends of sessions whose tables differ in columns (CSV, MAT,
%        Parquet)
%
%   No hardware, no pool, no prefs, no windows; everything is written under a
%   tempname folder removed on the way out.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_export ==\n');
t0 = tic;
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(root));
figs0 = findall(groot,'Type','figure');

[A,fxA] = toneResults();
B = clickResults();
labA = struct('Subject',"SUBJ-ID-9001",'SubjectRaw',"SUBJ_ID_9001",'Timepoint',"Baseline", ...
    'TimepointOrder',1,'Group',"Exposed",'InStudy',true,'TestMode',false,'DaysFromReference',0, ...
    'TimeOffset',0.1,'Comment',"first visit", ...
    'Free',struct('Weight_g',62.5,'Ear',"left",'Comment',"also a comment"), ...
    'UsedInStudy',struct('SeriesKey',fxA.SeriesKeys,'Used',[true;true;true;true;false]));
labB = struct('Subject',"SUBJ-ID-9002",'SubjectRaw',"SUBJ-ID-9002",'Timepoint',"2weeks", ...
    'TimepointOrder',2,'Group',"Sham",'InStudy',true,'TestMode',true,'DaysFromReference',14, ...
    'TimeOffset',NaN,'Comment',"",'Free',struct('Weight_g',70),'UsedInStudy',struct());
labC = labA; labC.InStudy = false; labC.Timepoint = "Repeat"; labC.TimepointOrder = 3;
notesA = table([datetime(2026,10,1,10,1,0); NaT],["[R01 S0012 10:01:00]";"[09:55:00]"], ...
    [fxA.NoteText;"impedance 3.2k"],[1;NaN],[12;NaN],["abr";"journal"],["session";"earlier"], ...
    'VariableNames',{'Time','Stamp','Text','Run','Sweep','Source','Scope'});
items = struct('Key',{fxA.Key,"SUBJ-ID-9002/SUBJ-ID-9002_261015T100000","SUBJ-ID-9001/visit-repeat"}, ...
    'Results',{A,B,A},'Labels',{labA,labB,labC},'Notes',{notesA,table(),table()}, ...
    'Session',{[],[],[]});
subjects = table(["SUBJ-ID-9001";"SUBJ-ID-9002"],["Exposed";"Sham"],[true;true],["";"spare"], ...
    [datetime(2026,9,1);datetime(2026,9,1)],["F";"M"], ...
    'VariableNames',{'Subject','Group','InStudy','Comment','Modified','Sex'});

%% ---- Part A: schema and column names -----------------------------------
S = mabr.analysis.Export.schema();
assert(istable(S) && isequal(string(S.Properties.VariableNames),["Table","Column","Type","Unit","Description"]), ...
    'schema() is a table Table, Column, Type, Unit, Description');
allT = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables];
assert(isempty(setxor(unique(S.Table),allT)),'schema() covers exactly the %d tables',numel(allT));
[~,iu] = unique(S.Table + "." + S.Column);
assert(numel(iu) == height(S),'schema() lists no column twice in one table');
assert(all(S.Description ~= ""),'every schema column has a description');
assert(all(ismember(S.Type,["string","double","integer","logical","date","datetime","any"])), ...
    'schema types are from the documented vocabulary');
for t = ["sessions","conditions","thresholds","peaks","waveforms","trials","notes","trial_waves","sweeps"]
    c = S.Column(S.Table == t);
    for need = ["session_id","subject","timepoint","timepoint_order","group","settings_hash","test_mode"]
        assert(ismember(need,c),'%s carries the per-session column %s',t,need);
    end
end
thrCols = S.Column(S.Table == "thresholds").';
for need = ["threshold_db","cens","thr_lo_db","thr_hi_db","thr_upper_db","convention", ...
        "threshold_fit_db","fit_status","threshold_imputed_db","imputation_rule","is_primary","used_in_study"]
    assert(ismember(need,thrCols),'thresholds has %s',need);
end
cn = mabr.analysis.Export.columnName(["Frequency","Level","Stim_Polarity","SoundLevel","ISIMode","3rd"]);
assert(isequal(cn,["frequency_khz","level_db","stim_polarity","sound_level","isi_mode","x3rd"]), ...
    'columnName: %s',strjoin(cn,", "));
assert(mabr.analysis.Export.columnName('Frequency') == "frequency_khz",'columnName takes char');
% No Statistics Toolbox (10 §0): no call to one of its functions, and no
% variable named after one.
forbidden = ['prctile|quantile|iqr|mad|range|zscore|nanmean|nanstd|nanmedian|corr|' ...
    'fcdf|finv|tcdf|tinv|normcdf|norminv|normpdf|randsample|datasample|bootstrp|' ...
    'fitglm|fitlm|boxplot|ksdensity|grpstats|skewness|kurtosis'];
src = fileread(which('mabr.analysis.Export'));
hit = regexp(src,['\<(' forbidden ')\s*\('],'match');
assert(isempty(hit),'Export.m calls %s.',strjoin(unique(hit),', '));
hit = regexp(src,'\<(range|corr|mad)\s*=','match');
assert(isempty(hit),'Export.m names a variable after a Statistics function: %s.',strjoin(unique(hit),', '));
fprintf('  PASS Part A: schema() has %d rows over %d tables; columnName snake_cases with kHz/dB suffixes\n', ...
    height(S),numel(allT));

%% ---- Part B: tables() --- shape, order, dictionary, no Inf --------------
T = mabr.analysis.Export.tables(items,Subjects=subjects,Tables=[mabr.analysis.Export.DefaultTables "trials"]);
names = string(fieldnames(T)).';
assert(isequal(names,[mabr.analysis.Export.DefaultTables "trials"]),'tables() returns the tables asked for, in order');
checkSchemaOrder(T,S);
D = mabr.analysis.Export.dictionary(T);
for t = names
    assert(isequal(D.Column(D.Table == t).',string(T.(t).Properties.VariableNames)), ...
        'dictionary(T) lists exactly the %s columns',t);
end
assert(~any(D.Description == "(not in the schema)"),'every exported column is in the schema');
assertNoInf(T,'tables()');
assert(height(T.sessions) == 1 && T.sessions.session_id == fxA.Key, ...
    'by default only the in-study, non-Test-Mode session is exported');
fprintf('  PASS Part B: %d tables, columns in schema order (placeholders expanded), dictionary complete, no Inf\n', ...
    numel(names));

%% ---- Part C: thresholds and censoring -----------------------------------
th = T.thresholds;
assert(height(th) == 5,'5 series, one primary row each (got %d)',height(th));
assert(all(th.is_primary),'without ThresholdsAll every row is primary');
ex = fxA.Expected;
for k = 1:numel(ex)
    r = th(th.series_key == ex(k).Key,:);
    assert(height(r) == 1,'one row for %s',ex(k).Key);
    lbl = ex(k).Label;
    assert(string(r.cens) == ex(k).cens,'%s: cens "%s" (expected "%s")',lbl,r.cens,ex(k).cens);
    for f = ["threshold_db","thr_lo_db","thr_hi_db","thr_upper_db","threshold_imputed_db","threshold_fit_db"]
        assert(isequaln(r.(f),ex(k).(f)),'%s: %s = %g (expected %g)',lbl,f,r.(f),ex(k).(f));
    end
    assert(string(r.imputation_rule) == ex(k).imputation_rule,'%s: imputation_rule "%s"',lbl,r.imputation_rule);
    assert(string(r.decision) == ex(k).decision && r.reviewed == (ex(k).decision ~= ""), ...
        '%s: decision/reviewed',lbl);
    assert(string(r.fit_status) == ex(k).fit_status,'%s: fit_status',lbl);
    assert(r.used_in_study == ex(k).used,'%s: used_in_study',lbl);
    assert(r.frequency_khz == ex(k).Frequency,'%s: frequency_khz',lbl);
    % The brms/survival encoding, stated as invariants too.
    switch ex(k).cens
        case "left",     assert(isnan(r.thr_lo_db) && r.thr_hi_db == r.threshold_db,'%s: left encoding',lbl);
        case "right",    assert(isnan(r.thr_hi_db) && r.thr_lo_db == r.threshold_db,'%s: right encoding',lbl);
        case "interval", assert(r.thr_lo_db < r.threshold_db && r.threshold_db <= r.thr_hi_db && ...
                r.thr_upper_db == r.thr_hi_db,'%s: interval encoding',lbl);
        case "none",     assert(r.thr_lo_db == r.threshold_db && r.thr_hi_db == r.threshold_db,'%s: none encoding',lbl);
        otherwise,       assert(all(isnan([r.threshold_db r.thr_lo_db r.thr_hi_db r.thr_upper_db])),'%s: excluded all NA',lbl);
    end
    if ex(k).cens ~= "", assert(isfinite(r.thr_upper_db),'%s: thr_upper_db never NA where cens is set',lbl); end
end
% The stored Final columns are SeriesThreshold.finalValue of the row.
for i = 1:height(A.Thresholds)
    Fv = mabr.analysis.SeriesThreshold.finalValue(table2struct(A.Thresholds(i,:)),"midpoint");
    assert(isequaln([Fv.Final Fv.FinalLo Fv.FinalHi],[A.Thresholds.Final(i) A.Thresholds.FinalLo(i) A.Thresholds.FinalHi(i)]) && ...
        Fv.FinalCensored == A.Thresholds.FinalCensored(i),'fixture row %d is finalValue-consistent',i);
end
r = th(th.series_key == fxA.SeriesKeys(1),:);
assert(r.n_used_min == 58 && abs(r.rn_uv_at_threshold - 1e6*fxA.RN(fxA.CondIndex(2,40))) < 1e-9, ...
    'n_used_min 58 and rn at the level nearest 30 dB (40 dB wins the tie)');
assert(r.level_ref == "dB SPL" && r.level_param == "Level" && r.method == "perm-glm" && r.criterion == 0.5, ...
    'level_ref, level_param, method, criterion carried');
assert(r.reviewed_by == "dan" && r.reviewed_at == datetime(2026,10,1,16,0,0),'reviewer and time carried');
fprintf('  PASS Part C: interval/right/left/none/excluded encoded exactly (Surv interval2 + brms y2), imputation rules, curated finals\n');

%% ---- Part D: ThresholdsAll ----------------------------------------------
TA = mabr.analysis.Export.tables(items,Tables="thresholds",ThresholdsAll=true);
ta = TA.thresholds;
others = setdiff(mabr.analysis.SeriesThreshold.Ids,["custom","perm-glm"],'stable');
assert(height(ta) == 5*(1 + numel(others)),'5 series x (primary + %d built-ins) rows (got %d)',numel(others),height(ta));
for k = 1:numel(ex)
    rk = ta(ta.series_key == ex(k).Key,:);
    assert(sum(rk.is_primary) == 1 && rk.method(rk.is_primary) == "perm-glm",'%s: one primary row',ex(k).Label);
    assert(isempty(setxor(rk.method(~rk.is_primary),others)),'%s: one row per other built-in method',ex(k).Label);
    assert(all(rk.decision(~rk.is_primary) == "") && all(~rk.reviewed(~rk.is_primary)) && ...
        all(isnat(rk.reviewed_at(~rk.is_primary))),'%s: only the primary row carries curation',ex(k).Label);
    pd = rk(rk.method == "perm-descending",:);
    assert(pd.cens == ex(k).PDcens && isequaln(pd.threshold_db,ex(k).PDthr), ...
        '%s: perm-descending from the stored p-values: %s %g (expected %s %g)',ex(k).Label, ...
        pd.cens,pd.threshold_db,ex(k).PDcens,ex(k).PDthr);
    assert(all(rk.used_in_study == ex(k).used),'%s: used_in_study on every method row',ex(k).Label);
end
xd = ta(ta.method == "xcorr-dtw",:);
assert(height(xd) == 5 && all(xd.metric == "dtw") && all(xd.criterion == 0.40) && all(xd.criterion_unit == "r"), ...
    'xcorr-dtw rows: from DTWUp at 0.40');
pd32 = ta(ta.series_key == fxA.SeriesKeys(5) & ta.method == "perm-descending",:);
assert(contains(pd32.flags,"top-level-only run"),'the 32 kHz run is flagged top-level-only');
assertNoInf(TA,'ThresholdsAll');
fprintf('  PASS Part D: ThresholdsAll adds %d methods per series from stored columns; perm-descending gives 30/80R/0L/50/70\n',numel(others));

%% ---- Part E: peaks, peak_measures, io_slopes ----------------------------
pk = T.peaks;
assert(height(pk) == height(A.Peaks),'every stored pick exported (%d)',height(pk));
m = pk(pk.condition_key == fxA.ManualKey & pk.wave == "III",:);
assert(m.state == "manual" && abs(m.lat_peak_ms - (fxA.ManualLat - 0.1)) < 1e-12 && ...
    abs(m.lat_peak_raw_ms - fxA.ManualLat) < 1e-12 && m.time_offset_ms == 0.1, ...
    'manual peak: lat_peak_ms = raw - time offset (0.1 ms)');
a = pk(pk.condition_key == fxA.AbsentKey & pk.wave == "V",:);
assert(a.state == "absent" && isnan(a.lat_peak_ms) && isnan(a.amp_pt_uv),'absent peak: NA latency and amplitude');
g = pk(pk.condition_key == fxA.CondKeys(fxA.CondIndex(2,80)) & pk.wave == "I",:);
assert(abs(g.amp_pt_uv - 1e6*fxA.AmpPT(2,80)) < 1e-9 && abs(g.level_re_thr_db - 50) < 1e-12, ...
    'amp_pt_uv in uV; level_re_thr_db = 80 - 30');
assert(all(isnan(pk.level_re_thr_db(startsWith(pk.series_key,fxA.SeriesKeys(2))))), ...
    'level_re_thr_db NA for the right-censored series');
assert(all(isnan(pk.level_re_thr_db(startsWith(pk.series_key,fxA.SeriesKeys(5))))), ...
    'level_re_thr_db NA for the excluded series');
assert(all(pk.level_re_thr_db(pk.series_key == fxA.SeriesKeys(3)) == pk.level_db(pk.series_key == fxA.SeriesKeys(3))), ...
    'left-censored at 0 dB: level_re_thr_db = level');
assert(all(pk.amp_unit == "uV") && all(pk.latency_method == "parabolic"),'amp_unit and latency_method');
pm = T.peak_measures;
assert(height(pm) > 0 && all(ismember(pm.unit,["ms","ln ratio"])),'peak_measures has IPLs and log ratios');
ipl = pm(pm.condition_key == fxA.CondKeys(fxA.CondIndex(2,80)) & pm.measure == "IPL_I_V",:);
assert(abs(ipl.value - (fxA.Lat(5,2,80) - fxA.Lat(1,2,80))) < 1e-12,'IPL_I_V = V - I latency');
assert(~any(startsWith(pm.condition_key,fxA.SeriesKeys(5))),'an excluded series contributes no derived measures');
io = T.io_slopes;
s1 = io(io.series_key == fxA.SeriesKeys(1) & io.wave == "I" & io.quantity == "amp_pt",:);
assert(s1.unit == "uV/dB" && abs(s1.slope - 1e6*fxA.AmpSlope) < 1e-9,'io amplitude slope in uV/dB');
s2 = io(io.series_key == fxA.SeriesKeys(1) & io.wave == "I" & io.quantity == "latency",:);
assert(s2.unit == "ms/dB" && abs(s2.slope - (-0.02)) < 1e-12 && abs(s2.intercept - (fxA.Lat0(1) - 0.1)) < 1e-9, ...
    'latency slope -0.02 ms/dB, intercept re onset minus the offset');
assert(s1.frequency_khz == 2 && ismember("frequency_khz",string(io.Properties.VariableNames)) && ...
    ~ismember("level_db",string(io.Properties.VariableNames)),'io_slopes carries the group parameter, not the level');
fprintf('  PASS Part E: peaks (offset latencies, NA where absent/censored), %d peak measures, %d io slopes\n', ...
    height(pm),height(io));

%% ---- Part F: sessions, subjects, conditions, waveforms, trials, notes, filters
ss = T.sessions;
assert(ss.subject == "SUBJ-ID-9001" && ss.subject_raw == "SUBJ_ID_9001" && ss.timepoint == "Baseline" && ...
    ss.timepoint_order == 1 && ss.group == "Exposed" && ss.in_study && ~ss.test_mode,'session labels');
assert(ss.date == datetime(2026,10,1) && ss.start_time == datetime(2026,10,1,10,0,0) && ...
    string(ss.start_time.Format) == "yyyy-MM-dd'T'HH:mm:ss",'date and start_time');
assert(ss.n_files == 25 && ss.n_conditions == 25 && ss.n_sweeps == 1600 && ss.stimuli == "Tone" && ...
    ss.units == "V" && ss.level_unit == "dB SPL" && ss.settings_hash == fxA.Hash,'session counts and units');
assert(ss.weight_g == 62.5 && ss.ear == "left" && ss.free_comment == "also a comment", ...
    'free session columns, a colliding name prefixed free_');
sj = T.subjects;
assert(height(sj) == 1 && sj.subject == "SUBJ-ID-9001" && sj.group == "Exposed" && sj.sex == "F", ...
    'subjects: the exported subject, free subject column from Project.Subjects');
cd = T.conditions;
assert(height(cd) == 25 && isequal(cd.condition_key,fxA.CondKeys),'conditions: one row per condition, by key');
c80 = cd(fxA.CondIndex(2,80),:);
assert(c80.n_total == 64 && c80.n_rejected == 6 && c80.n_rejected_rig == 3 && c80.n_rejected_auto == 2 && ...
    c80.n_rejected_manual == 1 && c80.n_used == 58 && c80.n_pos == 29 && c80.n_neg == 29, ...
    'rejection counts by reason from SweepInfo');
assert(c80.extent_ms == "-12-12" && c80.response_window_ms == "0.5-8" && c80.processing == "continuous" && ...
    c80.pad_mode == "",'extent, response window, processing, pad mode');
assert(c80.hp_6db_hz > 150 && c80.hp_6db_hz < 300 && c80.lp_6db_hz > 3000 && c80.lp_6db_hz < 4200, ...
    'realized -6 dB corners (%.0f-%.0f Hz)',c80.hp_6db_hz,c80.lp_6db_hz);
assert(abs(c80.rn_uv - 1e6*fxA.RN(fxA.CondIndex(2,80))) < 1e-9 && c80.split_avg_mode == "median" && ...
    c80.amp_unit == "uV" && c80.input_full_scale == 0.354 && c80.calibration_time == "2026-09-30T09:00:00", ...
    'measures in uV, split mode, amp unit, input full scale, calibration time');
assert(isequaln(cd.dtw_up,cd.xcorr_up + 0.1) && all(cd.dtw_lag_ms == 0.17) && all(cd.dtw_lag_range_ms == 0.08), ...
    'dtw_up / dtw_lag_ms / dtw_lag_range_ms are not DTWUp / DTWLag / DTWLagRange');
c0 = cd(fxA.CondIndex(2,0),:);
assert(c0.detected_override == 0 && all(isnan(cd.detected_override([1:fxA.CondIndex(2,0)-1 fxA.CondIndex(2,0)+1:end]))), ...
    'detected_override 0 where a human said no response, NA elsewhere');
wf = T.waveforms;
nWin = sum(fxA.Time - 0.1 >= -2 - 1e-9 & fxA.Time - 0.1 <= 10 + 1e-9);
assert(height(wf) == 25*3*nWin,'waveforms: 25 conditions x 3 polarities x %d samples (got %d)',nWin,height(wf));
w1 = wf(wf.condition_key == fxA.CondKeys(7) & wf.polarity == "balanced",:);
iw = find(fxA.Time - 0.1 >= -2 - 1e-9 & fxA.Time - 0.1 <= 10 + 1e-9);
assert(max(abs(w1.mean_uv - 1e6*double(A.Means.Balanced(iw,7)))) < 1e-9 && ...
    max(abs(w1.time_ms - (fxA.Time(iw) - 0.1))) < 1e-12 && all(w1.n == A.Means.N(7)), ...
    'balanced mean from the stored Means, time minus the offset, n');
assert(all(isnan(wf.sem_uv(wf.polarity ~= "balanced"))),'sem only on balanced rows');
assert(iscategorical(wf.session_id) && iscategorical(wf.polarity),'large tables hold text as categorical');
tr = T.trials;
assert(height(tr) == 1600 && all(ismember(string(tr.reject_reason),["none","rig","auto","manual"])), ...
    'trials: one row per stored sweep');
t1 = tr(tr.condition_key == fxA.CondKeys(fxA.CondIndex(2,80)) & tr.sweep_order == 5,:);
assert(t1.rejected && string(t1.reject_reason) == "rig" && string(t1.file_id) == fxA.FileIds(fxA.CondIndex(2,80)), ...
    'trial row: rejected by the rig, its file');
assert(abs(t1.t_session_s - (seconds(fxA.FileStart(fxA.CondIndex(2,80)) - fxA.FileStart(1)) + t1.time_s)) < 1e-6, ...
    't_session_s = file start re session start + time in file');
nt = T.notes;
assert(height(nt) == 2 && nt.text(1) == fxA.NoteText && nt.run(1) == 1 && isnat(nt.time(2)),'notes');
% Filters.
Tx = mabr.analysis.Export.tables(items,Tables=["sessions","thresholds","waveforms"],IncludeTestMode=true);
assert(height(Tx.sessions) == 2 && any(Tx.sessions.test_mode),'IncludeTestMode brings the Test Mode session');
assert(height(Tx.thresholds) == 6 && ismember("frequency_khz",string(Tx.thresholds.Properties.VariableNames)) && ...
    isnan(Tx.thresholds.frequency_khz(Tx.thresholds.stimulus == "ClickTrain")),'a click series stacks with NaN frequency');
nWinB = sum(B.Summary.Time >= -2 & B.Summary.Time <= 10);
assert(height(Tx.waveforms) == 25*3*nWin + 4*3*nWinB,'waveforms of both sessions');
Te = mabr.analysis.Export.tables(items,Tables=["sessions","conditions"],IncludeExcluded=true);
assert(height(Te.sessions) == 2 && ~all(Te.sessions.in_study) && height(Te.conditions) == 50, ...
    'IncludeExcluded brings the session out of the study');
To = mabr.analysis.Export.tables(items,Tables=["thresholds","peaks","peak_measures","io_slopes"],OnlyReviewed=true);
assert(height(To.thresholds) == 4 && all(To.thresholds.reviewed),'OnlyReviewed keeps the 4 reviewed series');
assert(~any(startsWith(To.peaks.condition_key,fxA.SeriesKeys(2))) && height(To.peaks) == height(pk) - 25, ...
    'OnlyReviewed drops the unreviewed series'' peaks');
Ts = mabr.analysis.Export.tables(items,Tables="sessions",Subjects=table("SUBJ-ID-9001",false,'VariableNames',{'Subject','InStudy'}));
assert(height(Ts.sessions) == 0,'a subject out of the study takes its sessions with it');
fprintf('  PASS Part F: sessions/subjects/conditions/waveforms (from Means)/trials (from SweepInfo)/notes; Test Mode, excluded and reviewed filters\n');

%% ---- Part G: CSV --------------------------------------------------------
fc = fullfile(root,"csv");
files = mabr.analysis.Export.write(T,fc,Formats="csv");
assert(height(files) == numel(names) && all(files.Format == "csv") && all(arrayfun(@isfile,files.File)), ...
    'one CSV per table');
for t = names
    f = files.File(files.Table == t);
    txt = readUtf8(f);
    assert(isempty(regexp(txt,'(^|,|\n)"?(NaN|-?Inf)"?(?=,|\r|\n|$)','once')),'%s: no NaN/Inf text',t);
    assert(~contains(txt,"<undefined>") && ~contains(txt,"<missing>"),'%s: no <undefined>/<missing>',t);
    R = readBack(f);
    assert(height(R) == height(T.(t)),'%s: %d rows read back',t,height(R));
    assert(isequal(string(R.Properties.VariableNames),string(T.(t).Properties.VariableNames)),'%s: header',t);
    for v = string(T.(t).Properties.VariableNames)
        [ok,why] = sameColumn(T.(t).(v),R.(v));
        assert(ok,'%s.%s round trip: %s',t,v,why);
    end
end
fth = files.File(files.Table == "thresholds");
o = detectImportOptions(fth,'Delimiter',',','Encoding','UTF-8','TextType','string','VariableNamingRule','preserve');
o = setvartype(o,{'reviewed','is_primary','test_mode'},'string');
Rt = readtable(fth,o);
assert(all(ismember([Rt.reviewed;Rt.is_primary;Rt.test_mode],["TRUE","FALSE"])),'logicals written TRUE/FALSE');
txt = readUtf8(files.File(files.Table == "sessions"));
assert(~isempty(regexp(txt,'2026-10-01T10:00:00','once')) && ~isempty(regexp(txt,'[,"]2026-10-01[",]','once')), ...
    'ISO 8601 datetime and date');
fid = fopen(files.File(files.Table == "notes"),'r');
bytes = fread(fid,'*uint8').';
fclose(fid);
want = unicode2native(char(fxA.NoteText),'UTF-8');
found = ~isempty(strfind(bytes,want)); %#ok<STREMP> a byte pattern, not text
assert(found && ~isequal(bytes(1:3),uint8([239 187 191])),'notes CSV holds the non-ASCII note as UTF-8 (no BOM)');
fprintf('  PASS Part G: %d CSVs read back column for column; no NaN/Inf text; TRUE/FALSE; ISO times; UTF-8\n',numel(names));

%% ---- Part H: XLSX --------------------------------------------------------
fx = fullfile(root,"xlsx");
fxl = mabr.analysis.Export.write(T,fx,Formats="xlsx");
wb = unique(fxl.File(fxl.File ~= ""));
assert(isscalar(wb) && isfile(wb),'one workbook');
sh = string(sheetnames(wb));
small = names(ismember(names,mabr.analysis.Export.XLSXTables));
assert(isempty(setxor(sh,"mabr_" + small)),'sheets for exactly the small tables (%s)',strjoin(sh,", "));
big = names(~ismember(names,mabr.analysis.Export.XLSXTables));
for t = big
    r = fxl(fxl.Table == t,:);
    assert(r.File == "" && contains(r.Note,"small tables"),'%s refused for XLSX with a note',t);
end
X = readtable(wb,'Sheet','mabr_thresholds','TextType','string','VariableNamingRule','preserve');
assert(height(X) == height(T.thresholds) && isequaln(X.threshold_db,T.thresholds.threshold_db), ...
    'thresholds sheet reads back (NaN as empty cells)');
fx2 = fullfile(root,"xlsx2");
pre = "a_rather_long_prefix_for_sheets_";
f2 = mabr.analysis.Export.write(struct('peak_measures',T.peak_measures),fx2,Formats="xlsx",Prefix=pre);
s2 = string(sheetnames(f2.File));
assert(isscalar(s2) && strlength(s2) == 31 && s2 == extractBefore(pre + "peak_measures",32), ...
    'sheet names are cut to 31 characters ("%s")',s2);
bigT = table(zeros(1.1e6,1),'VariableNames',{'x'});
fx3 = fullfile(root,"xlsx3");
f3 = mabr.analysis.Export.write(struct('peaks',bigT),fx3,Formats="xlsx");
assert(f3.File == "" && contains(f3.Note,"1100000") && isempty(dir(fullfile(fx3,'*.xlsx'))), ...
    'a 1.1e6-row table is refused, nothing written');
fprintf('  PASS Part H: XLSX holds the %d small tables, refuses the large ones and a 1.1e6-row table; 31-char sheets\n',numel(small));

%% ---- Part I: Parquet ------------------------------------------------------
if isempty(which('parquetwrite'))
    fprintf('  SKIP Part I: parquetwrite is not available in this MATLAB\n');
else
    fp = fullfile(root,"parquet");
    T2 = mabr.analysis.Export.tables(items,Subjects=subjects,IncludeTestMode=true, ...
        Tables=[mabr.analysis.Export.DefaultTables "trials"]);
    fpq = mabr.analysis.Export.write(T2,fp,Formats="parquet");
    rt = fpq(fpq.Table == "thresholds",:);
    Q = parquetread(rt.File);
    assert(height(Q) == height(T2.thresholds) && isequaln(Q.threshold_db,T2.thresholds.threshold_db) && ...
        isequal(string(Q.cens),string(T2.thresholds.cens)),'thresholds.parquet reads back');
    for t = ["waveforms","trials"]
        rw = fpq(fpq.Table == t,:);
        assert(isfolder(rw.File),'%s: a dataset folder',t);
        d = dir(fullfile(rw.File,'*.parquet'));
        assert(numel(d) == numel(unique(T2.(t).session_id)),'%s: one file per session (got %d)',t,numel(d));
        n = 0;
        for k = 1:numel(d)
            q = parquetread(fullfile(d(k).folder,d(k).name));
            n = n + height(q);
            nums = q(:,vartype('numeric'));
            assert(~any(isinf(nums{:,:}),'all'),'%s: no Inf in Parquet',t);
        end
        assert(n == height(T2.(t)),'%s: %d rows over the per-session files',t,n);
    end
    fprintf('  PASS Part I: small tables one Parquet file each; waveforms/trials one file per session; read back\n');
end

%% ---- Part J: MAT ------------------------------------------------------------
fm = fullfile(root,"mat");
fmat = mabr.analysis.Export.write(T,fm,Formats="mat");
mf = unique(fmat.File);
assert(isscalar(mf) && isfile(mf),'one MAT file');
M = load(mf);
assert(isequal(fieldnames(M),{'MABRExport'}) && isequal(string(fieldnames(M.MABRExport)).',names), ...
    'MAT holds one struct MABRExport of the tables');
for t = names
    for v = string(T.(t).Properties.VariableNames)
        assert(isequaln(M.MABRExport.(t).(v),T.(t).(v)),'MAT %s.%s equals the table',t,v);
    end
end
fprintf('  PASS Part J: MABRExport holds every table unchanged\n');

%% ---- Part K: R script, dictionary, manifest ----------------------------------
fr = mabr.analysis.Export.writeRScript(fc,files,T);
txt = string(readUtf8(fr));
rl = splitlines(txt);
live = rl(~startsWith(strtrim(rl),"#"));
cmt = rl(startsWith(strtrim(rl),"#"));
assert(any(contains(live,"timepoint = factor(timepoint, levels = unique(timepoint[order(timepoint_order)]))")), ...
    'R: timepoint factor ordered by timepoint_order');
assert(any(contains(live,"readr::read_csv(") & contains(live,'na = c("", "NA", "NaN")')),'R: read_csv with the NA strings');
assert(any(contains(live,"brms::brm(y | cens(cens, thr_upper_db) ~ group*timepoint*freq_f + (1 + timepoint | subject)")), ...
    'R: the brms censored model');
assert(any(contains(live,'ifelse(thr$cens == "interval", thr$thr_lo_db, thr$threshold_db)')),'R: y = lower bound on interval rows');
assert(any(contains(live,'survreg(Surv(thr_lo_db, thr_hi_db, type = "interval2") ~ group*timepoint*freq_f + cluster(subject)')), ...
    'R: the survreg interval2 model');
assert(any(contains(cmt,"lmer(threshold_imputed_db ~ group*timepoint*freq_f + (1|subject)")) && ...
    ~any(contains(live,"threshold_imputed_db ~")),'R: the imputed lmer only as a commented sensitivity analysis');
assert(any(contains(live,"lmer(log(amp_pt_uv) ~ group*timepoint*level_c + rn_uv + n_used + (1 + level_c | subject) + (1 | subject:session_id)")), ...
    'R: the log amplitude model with rn_uv and n_used');
assert(any(contains(live,"detectable, level_re_thr_db >= 10")),'R: amplitude rows detectable and >= 10 dB above threshold');
assert(any(contains(live,"lmer(lat_peak_ms ~")),'R: a latency model');
assert(any(contains(live,"glmmTMB::glmmTMB(")) && any(contains(live,'Gamma(link = "log")')),'R: glmmTMB Gamma alternative');
assert(any(contains(live,'emmeans::emmeans(m_surv, pairwise ~ group | freq_f, adjust = "holm")')),'R: Holm emmeans');
assert(any(contains(cmt,"singular")),'R: the singular-fit comment');
assert(~contains(txt,"m_drift"),'R: no block model without blocks');
assert(contains(txt,"mabr_sessions.csv") && contains(txt,"RUN_MODELS <- FALSE"),'R: file list and the model switch');
fd = mabr.analysis.Export.writeDictionary(fc,T);
Dd = readtable(fd,'TextType','string','Delimiter',',','VariableNamingRule','preserve');
assert(isequal(string(Dd.Properties.VariableNames),["table","column","type","unit","description"]), ...
    'mabr_columns.csv columns table, column, type, unit, description');
for t = names
    assert(isequal(Dd.column(Dd.table == t).',string(T.(t).Properties.VariableNames)), ...
        'mabr_columns.csv lists every written %s column',t);
end
fj = mabr.analysis.Export.writeManifest(fc,T,Files=files,Scope="In study", ...
    Options=struct('Tables',names,'ThresholdsAll',false,'WaveformWindow',[-2 10]));
J = jsondecode(readUtf8(fj));
assert(J.SchemaVersion == 1 && ischar(J.MABR.Commit) && ~isempty(J.MABR.Commit) && ischar(J.MATLAB) && ...
    strcmp(J.Scope,'In study'),'manifest: SchemaVersion 1, commit, MATLAB, scope');
assert(numel(J.Tables) == numel(names) && isequal(string({J.Tables.name}),names) && ...
    J.Tables(1).rows == 1,'manifest: one entry per table with rows');
assert(any(strcmp(J.SettingsHash,char(fxA.Hash))),'manifest names the settings hash');
Js = jsondecode(readUtf8(fullfile(fc,"mabr_settings.json")));
fn = fieldnames(Js);
assert(isscalar(fn) && Js.(fn{1}).MinSweeps == 20 && strcmp(Js.(fn{1}).MaxSweepsPerCondition,'Inf'), ...
    'mabr_settings.json holds the settings by hash (Inf as text)');
fprintf('  PASS Part K: mabr_import.R (factor order, brms cens, survreg interval2, commented lmer, log-amp lmer, glmmTMB, Holm), dictionary, manifest\n');

%% ---- Part L: estimate -----------------------------------------------------
Es = mabr.analysis.Export.estimate(items);
er = @(t) Es.Rows(Es.Table == t);
assert(er("sessions") == 1 && er("conditions") == 25 && er("thresholds") == 5 && er("peaks") == height(pk) && ...
    er("waveforms") == height(wf) && er("trials") == 1600 && er("notes") == 2 && er("subjects") == 1, ...
    'estimate: exact rows of the stored tables');
assert(er("peak_measures") >= height(pm) && er("io_slopes") >= height(io),'estimate: derived rows are upper bounds');
assert(all(Es.NeedsRaw == ismember(Es.Table,mabr.analysis.Export.RawTables)),'estimate: NeedsRaw for the raw tables');
assert(all(Es.XLSXAllowed == ismember(Es.Table,mabr.analysis.Export.XLSXTables)),'estimate: XLSXAllowed for the small tables');
assert(all(Es.CSVBytes > 0 & Es.ParquetBytes > 0),'estimate: sizes');
Ea = mabr.analysis.Export.estimate(items,Tables="thresholds",ThresholdsAll=true);
assert(Ea.Rows == 5*(1 + numel(others)),'estimate: ThresholdsAll rows');
bigItem = struct('Key',"BIG",'Results',struct('Version',2,'Summary',struct('Subject',"SUBJ-ID-1"), ...
    'Peaks',table(zeros(1.1e6,1),'VariableNames',{'Level'})),'Labels',struct(),'Notes',[],'Session',[]);
Eb = mabr.analysis.Export.estimate(bigItem,Tables=["sessions","peaks"]);
assert(Eb.Rows(Eb.Table == "peaks") == 1.1e6 && ~Eb.XLSXAllowed(Eb.Table == "peaks") && ...
    Eb.XLSXAllowed(Eb.Table == "sessions"),'estimate: a 1.1e6-row peaks table is not XLSX-allowed');
fprintf('  PASS Part L: estimate rows exact for stored tables, NeedsRaw, XLSXAllowed incl. the 1.1e6-row check\n');

%% ---- Part M: writeRaw over a session-shaped struct ---------------------------
[sess,fxR] = rawSession("SUBJ-ID-9001/raw-tone",["Stimulus","AcqMode","Frequency","Level"],"Tone",8);
fw = fullfile(root,"raw");
hasPq = ~isempty(which('parquetwrite'));
if hasPq
    rf = mabr.analysis.Export.writeRaw(sess,struct('Key',sess.Key,'Labels',labA),fw,Formats="parquet",BlockSize=16);
    q = readDataset(rf,"trial_waves");
    assert(height(q) == fxR.TrialWaveRows,'trial_waves: clean sweeps x picked waves (%d, expected %d)',height(q),fxR.TrialWaveRows);
    assert(all(q.session_id == sess.Key) && all(ismember(q.sweep_order,1:64)) && ...
        ~any(q.sweep_order(q.condition_key == fxR.Keys(1)) == fxR.RejectedOrder), ...
        'trial_waves: acquisition order of the clean sweeps');
    qb = readDataset(rf,"blocks");
    assert(height(qb) == fxR.BlockRows,'blocks: %d rows (expected %d)',height(qb),fxR.BlockRows);
    qw = readDataset(rf,"block_waves");
    assert(height(qw) == fxR.BlockWaveRows,'block_waves: %d rows (expected %d)',height(qw),fxR.BlockWaveRows);
    qs = readDataset(rf,"sweeps");
    assert(height(qs) == fxR.SweepRows,'sweeps: one row per sample (%d)',height(qs));
    k1 = qs(qs.condition_key == fxR.Keys(1) & qs.sweep_order == 3,:);
    assert(all(k1.rejected) && max(abs(k1.value_uv - 1e6*fxR.X1(:,3))) < 1e-9 && ...
        max(abs(k1.time_ms - (fxR.Time - 0.1))) < 1e-12,'sweeps: values in uV, rejected flagged, offset time');
else
    fprintf('  SKIP Part M (parquet): parquetwrite is not available\n');
end
[sess2,fxR2] = rawSession("SUBJ-ID-9002/raw-click",["Stimulus","AcqMode","Level"],"ClickTrain",NaN);
rc2 = mabr.analysis.Export.writeRaw(sess2,labB,fw,Formats="csv",BlockSize=16);   % no frequency_khz column
rc = mabr.analysis.Export.writeRaw(sess,labA,fw,Formats="csv",BlockSize=16);     % brings one: the CSV is rewritten
sw = rc(rc.Table == "sweeps",:);
assert(sw.File == "" && contains(sw.Note,"refused"),'CSV refused for sweeps');
assert(isempty(dir(fullfile(fw,'*sweeps*.csv'))),'no sweeps CSV written');
cb = readBack(rc.File(rc.Table == "blocks"));
assert(height(cb) == fxR.BlockRows + fxR2.BlockRows && ismember("frequency_khz",string(cb.Properties.VariableNames)) && ...
    all(ismissing(cb.frequency_khz(cb.stimulus == "ClickTrain")) | isnan(double(cb.frequency_khz(cb.stimulus == "ClickTrain")))), ...
    'blocks.csv appended across sessions, columns reconciled (a click has no frequency)');
ctw = readBack(rc.File(rc.Table == "trial_waves"));
assert(height(ctw) == fxR.TrialWaveRows + fxR2.TrialWaveRows,'trial_waves.csv appended');
rmat = mabr.analysis.Export.writeRaw(sess,labA,fw,Tables="sweeps",Formats="mat");
SW = load(rmat.File);
assert(isfield(SW,'MABRSweeps') && isa(SW.MABRSweeps.Conditions(1).Sweeps,'single') && ...
    isequal(size(SW.MABRSweeps.Conditions(1).Sweeps),[numel(fxR.Time) 64]) && SW.MABRSweeps.Unit == "uV" && ...
    height(SW.MABRSweeps.Conditions(1).Info) == 64,'sweeps MAT: one single [nT x n] matrix (uV) per condition');
% The same raw tables in memory, from tables() with a Session on the item.
it = struct('Key',sess.Key,'Results',struct('Version',2,'Summary',struct('Subject',"SUBJ-ID-9001")), ...
    'Labels',labA,'Notes',[],'Session',sess);
TR = mabr.analysis.Export.tables(it,Tables=["trial_waves","blocks","block_waves"],BlockSize=16);
assert(height(TR.trial_waves) == fxR.TrialWaveRows && height(TR.blocks) == fxR.BlockRows && ...
    height(TR.block_waves) == fxR.BlockWaveRows,'tables() builds the raw tables from an item''s Session');
checkSchemaOrder(TR,S);
f2r = mabr.analysis.Export.writeRScript(fw,[rc;rc2],TR);
assert(contains(string(readUtf8(f2r)),"m_drift <- lmerTest::lmer(response_rms_uv ~ block_c"),'R: block drift model when blocks were exported');
fprintf('  PASS Part M: writeRaw trial_waves/blocks/block_waves/sweeps (Parquet, MAT), CSV refused for sweeps, CSV appends reconcile columns\n');

%% ---- Part N: stack, progress and cancel, refusals, inputs ----------------------
% stack(): a click table and a tone table union to the schema order, the
% click's missing frequency filled with NaN; a table without UserData needs
% its name.
tc = Tx.thresholds(Tx.thresholds.stimulus == "ClickTrain",:);
tt = T.thresholds(1:2,:);
st = mabr.analysis.Export.stack({tc,tt});
assert(height(st) == 3 && isnan(st.frequency_khz(1)) && st.frequency_khz(2) == 2 && ...
    isequal(st.Properties.VariableNames,T.thresholds.Properties.VariableNames),'stack unions columns in schema order');
bare = tc; bare.Properties.UserData = [];
assert(height(mabr.analysis.Export.stack({bare,tt},"thresholds")) == 3,'stack takes the table name when the tables do not carry it');
assertError(@() mabr.analysis.Export.stack({bare}),'mabr:analysis:Export:badInput','stack without a name');
% Progress: the sink is called; a sink that throws cancels.
sink = @(m,c,n) recordCall(m,c,n);
recordCall('reset');
mabr.analysis.Export.tables(items,Tables="sessions",ProgressFcn=sink);
calls = recordCall('get');
assert(numel(calls) >= 2 && calls{end}{2} == calls{end}{3},'tables() reports progress, ending at count == total');
cancel = @(m,c,n) error('mabr:analysis:cancelled','Cancelled by user.');
assertError(@() mabr.analysis.Export.tables(items,Tables="sessions",ProgressFcn=cancel),'mabr:analysis:cancelled','cancel');
assertError(@() mabr.analysis.Export.tables(items,Tables="nope"),'mabr:analysis:Export:unknownTable','unknown table');
assertError(@() mabr.analysis.Export.write(T,fullfile(root,"bad"),Formats="feather"),'mabr:analysis:Export:badFormat','unknown format');
assertError(@() mabr.analysis.Export.writeRaw(sess,labA,fw,Tables="sessions"),'mabr:analysis:Export:unknownTable','writeRaw of a non-raw table');
% Per-table formats.
fpt = fullfile(root,"pertable");
fmts = struct('default',"csv",'waveforms',"mat");
fpo = mabr.analysis.Export.write(struct('sessions',T.sessions,'waveforms',T.waveforms),fpt,Formats=fmts);
assert(isequal(fpo.Format(fpo.Table == "sessions"),"csv") && isequal(fpo.Format(fpo.Table == "waveforms"),"mat"), ...
    'Formats as a struct: per table, "default" for the rest');
% A results FILE as Results (v2 = separate top-level variables).
rf2 = fullfile(root,"resultsA.mat");
save(rf2,'-struct','A');
itf = items(1); itf.Results = rf2;
Tf = mabr.analysis.Export.tables(itf,Tables=["conditions","thresholds"]);
assert(isequaln(Tf.thresholds.threshold_db,T.thresholds.threshold_db) && height(Tf.conditions) == 25, ...
    'a results file path exports what its struct does');
% A v1 results struct (the pre-rewrite Session.toStruct): thresholds from
% Threshold/Curated, conditions keyed, waveforms from the saved sweeps.
V1 = v1Results();
T1 = mabr.analysis.Export.tables(struct('Key',"OLD",'Results',V1,'Labels',struct(),'Notes',[],'Session',[]), ...
    Tables=["sessions","conditions","thresholds","waveforms"]);
t8 = T1.thresholds(T1.thresholds.frequency_khz == 8,:);
t16 = T1.thresholds(T1.thresholds.frequency_khz == 16,:);
assert(t8.cens == "none" && t8.threshold_db == 30.5 && t8.decision == "" && t16.cens == "right" && ...
    t16.threshold_db == 60 && t16.decision == "noresponse",'v1 thresholds: fit and legacy curation (Inf = no response)');
assert(height(T1.conditions) == 6 && all(startsWith(T1.conditions.condition_key,"AcqMode=conventional|Frequency=")) && ...
    T1.sessions.start_time == datetime(2025,5,1,9,0,0),'v1 conditions keyed, session start from Date');
assert(height(T1.waveforms) == 6*3*sum(V1.Time >= -2 & V1.Time <= 10),'v1 waveforms from the saved sweeps');
fprintf('  PASS Part N: stack, progress and cancel, error ids, per-table formats, a results file, v1 results\n');

%% ---- Part O: writeRaw over a real Session --------------------------------------
mc = ?mabr.analysis.Session;
propNames = string({mc.PropertyList.Name});
if ~all(ismember(["HasSweeps","KeyParams"],propNames))
    fprintf('  SKIP Part O: mabr.analysis.Session has no HasSweeps/KeyParams yet (Session part A not delivered)\n');
else
    folder = fullfile(root,"SUBJ-ID-9001","SUBJ-ID-9001_261001T100000");
    truth = mabrtest.SyntheticABR.defaults();
    truth.Freqs = 8; truth.Threshold = 30; truth.Levels = [40 80]; truth.nSweeps = 64;
    mabrtest.SyntheticABR.writeSession(folder,truth,Subject="SUBJ-ID-9001");
    s = mabr.analysis.Session(folder,Verbose=false);
    s.segment();
    tabs = ["blocks","sweeps"];
    note = "pickPeaks not available: trial_waves/block_waves not exercised";
    try
        s.pickPeaks();
        tabs = mabr.analysis.Export.RawTables;
        note = "picks from pickPeaks";
    catch ME
        if ~contains(ME.identifier,"notImplemented") && ~contains(ME.message,"not implemented")
            rethrow(ME);
        end
    end
    fn2 = fullfile(root,"rawsession");
    fmt = "csv"; if hasPq, fmt = "parquet"; end
    rs = mabr.analysis.Export.writeRaw(s,labA,fn2,Tables=tabs,Formats=[fmt "mat"],BlockSize=16);
    nT = numel(s.Time);
    assert(all(rs.Rows(rs.Table == "blocks") > 0),'writeRaw over a real Session writes blocks');
    sp = rs(rs.Table == "sweeps" & rs.Format == "mat",:);
    assert(sp.Rows == sum(s.Conditions.nSweeps) && isfile(sp.File),'the sweeps MAT holds every sweep');
    if hasPq
        q = readDataset(rs,"sweeps");
        assert(height(q) == sum(s.Conditions.nSweeps)*nT,'sweeps Parquet: one row per sample of every sweep');
    end
    % The same session's results v2 (part A's writer), exported without raw data.
    R = s.toStruct(false,true);
    sr = mabr.analysis.Session.fromResults(R);
    assert(~sr.HasSweeps,'fromResults without sweeps is results-only');
    assertError(@() mabr.analysis.Export.writeRaw(sr,labA,fn2),'mabr:analysis:Export:noRaw','writeRaw of a results-only Session');
    itR = struct('Key',string(s.Key),'Results',R,'Labels',labA,'Notes',[],'Session',[]);
    TN = mabr.analysis.Export.tables(itR,Tables=["sessions","conditions","thresholds","peaks","waveforms","trials"]);
    checkSchemaOrder(TN,S);
    assertNoInf(TN,'real results');
    nWinN = sum(s.Time - 0.1 >= -2 - 1e-9 & s.Time - 0.1 <= 10 + 1e-9);
    assert(height(TN.conditions) == height(s.Conditions) && height(TN.trials) == sum(s.Conditions.nSweeps) && ...
        height(TN.waveforms) == height(s.Conditions)*3*nWinN && height(TN.sessions) == 1, ...
        'tables() over a real results v2 struct: conditions, trials (SweepInfo), waveforms (Means)');
    assert(all(TN.conditions.n_rejected_rig == s.Conditions.nRejected) && all(TN.conditions.level_db == s.Conditions.Level), ...
        'the rig-flagged sweeps are counted by reason; parameters carried');
    assert(all(TN.conditions.hp_6db_hz > 150 & TN.conditions.hp_6db_hz < 300 & TN.conditions.lp_6db_hz > 3000 & ...
        TN.conditions.lp_6db_hz < 4200),'-6 dB corners of the filter segment applied (results with no Settings)');
    TO = mabr.analysis.Export.tables(struct('Key',string(s.Key),'Results',s,'Labels',labA,'Notes',[],'Session',[]), ...
        Tables="conditions");
    assert(isequaln(TO.conditions,TN.conditions),'a Session object as Results exports what its toStruct does');
    fprintf('  PASS Part O: writeRaw over a SyntheticABR Session (%s; %s); tables() over its real results v2\n', ...
        strjoin(tabs,", "),note);
end

%% ---- Part P: sound conduction delay (A9) -------------------------------------
% Latencies are reported re sound arrival: raw - conduction delay - time
% offset (Peaks.reported). The offset is the one the results stored with
% their peaks (Peaks.LatencyOffset) unless a label overrides it, and
% interpeak intervals, being differences, do not move.
labN = labA; labN.TimeOffset = NaN;                  % no label override
cdel = 10*10/343;                                    % 10 cm at 343 m/s
AP = A;
AP.Settings = mabr.analysis.Settings(MinSweeps=20,MinPerPolarity=10,NumPermutations=200, ...
    ConductionDelayMode="distance",SpeakerDistance=10,SpeedOfSound=343).toStruct();
AP.Peaks.LatencyOffset = repmat(0.35,height(AP.Peaks),1);
itP = items(1); itP.Results = AP; itP.Labels = labN;
TP = mabr.analysis.Export.tables(itP,Tables=["peaks","peak_measures","io_slopes","waveforms"]);
pp = TP.peaks;
okL = isfinite(pp.lat_peak_raw_ms);
assert(all(abs(pp.conduction_delay_ms - cdel) < 1e-12) && all(abs(pp.time_offset_ms - (0.35 - cdel)) < 1e-12), ...
    'peaks: conduction_delay_ms from the settings (10 cm at 343 m/s), time_offset_ms the rest of the stored 0.35 ms');
assert(isequal(pp.lat_peak_ms(okL),mabr.analysis.Peaks.reported(pp.lat_peak_raw_ms(okL),0.35)) && ...
    max(abs(pp.lat_peak_raw_ms(okL) - pp.conduction_delay_ms(okL) - pp.time_offset_ms(okL) - pp.lat_peak_ms(okL))) < 1e-12, ...
    'peaks: lat_peak_ms = Peaks.reported(raw, stored LatencyOffset) = raw - conduction delay - time offset');
mP = pp(pp.condition_key == fxA.ManualKey & pp.wave == "III",:);
assert(abs(mP.lat_peak_ms - (fxA.ManualLat - 0.35)) < 1e-12 && abs(mP.lat_peak_raw_ms - fxA.ManualLat) < 1e-12, ...
    'peaks: the manual pick reported re sound arrival, raw kept');
pmA = sortrows(T.peak_measures(:,{'condition_key','measure','value'}));
pmP = sortrows(TP.peak_measures(:,{'condition_key','measure','value'}));
assert(isequal(pmP.condition_key,pmA.condition_key) && isequal(pmP.measure,pmA.measure) && ...
    isequaln(pmP.value,pmA.value) && ...
    all(abs(TP.peak_measures.conduction_delay_ms - cdel) < 1e-12), ...
    'peak_measures: interpeak intervals and log ratios do not move with the offset; the delay is carried');
iP = TP.io_slopes(TP.io_slopes.series_key == fxA.SeriesKeys(1) & TP.io_slopes.wave == "I" & TP.io_slopes.quantity == "latency",:);
assert(abs(iP.intercept - (fxA.Lat0(1) - 0.35)) < 1e-9 && abs(iP.slope - (-0.02)) < 1e-12, ...
    'io_slopes: latency intercept on the ear-time base, slope unchanged');
wP = TP.waveforms(TP.waveforms.condition_key == fxA.CondKeys(7) & TP.waveforms.polarity == "balanced",:);
assert(abs(min(wP.time_ms) - (fxA.Time(find(fxA.Time - 0.35 >= -2 - 1e-9,1)) - 0.35)) < 1e-12, ...
    'waveforms: time_ms on the same base as lat_peak_ms');
% A label override (the Project's ConductionDelay/TimeOffset overrides)
% wins over the stored offset.
labO = labN; labO.ConductionDelay = 0.3; labO.TimeOffset = 0.05;
AP.Peaks.LatencyOffset(:) = 0.5;
itO = itP; itO.Results = AP; itO.Labels = labO;
po = mabr.analysis.Export.tables(itO,Tables="peaks").peaks;
assert(all(po.conduction_delay_ms == 0.3) && all(po.time_offset_ms == 0.05) && ...
    max(abs(po.lat_peak_ms(okL) - (po.lat_peak_raw_ms(okL) - 0.35))) < 1e-12, ...
    'a label override (0.3 + 0.05 ms) wins over the stored 0.5 ms');
% Nothing stored, nothing labelled: the settings' delay + TimeOffset.
AS = A;
AS.Settings = mabr.analysis.Settings(ConductionDelayMode="delay",ConductionDelay=0.25,TimeOffset=0.02).toStruct();
itS = itP; itS.Results = AS;
ps = mabr.analysis.Export.tables(itS,Tables="peaks").peaks;
assert(all(ps.conduction_delay_ms == 0.25) && all(abs(ps.time_offset_ms - 0.02) < 1e-15) && ...
    max(abs(ps.lat_peak_ms(okL) - (ps.lat_peak_raw_ms(okL) - 0.27))) < 1e-12, ...
    'without a stored offset the settings give conductionDelay() + TimeOffset');
% Default: no delay anywhere -- latencies are re the recorded onset.
AZ = A; AZ.Settings = mabr.analysis.Settings().toStruct();
itZ = itP; itZ.Results = AZ;
pz = mabr.analysis.Export.tables(itZ,Tables="peaks").peaks;
assert(all(pz.conduction_delay_ms == 0 & pz.time_offset_ms == 0) && isequaln(pz.lat_peak_ms,pz.lat_peak_raw_ms), ...
    'with no delay set lat_peak_ms is the raw latency');
% The raw tables: trial_waves and block_waves on the same base, from a
% session that stored its LatencyOffset.
sessP = sess; sessP.LatencyOffset = 0.3;
itRP = struct('Key',sessP.Key,'Results',struct('Version',2,'Summary',struct('Subject',"SUBJ-ID-9001")), ...
    'Labels',labN,'Notes',[],'Session',sessP);
TRP = mabr.analysis.Export.tables(itRP,Tables=["trial_waves","block_waves"],BlockSize=16);
checkSchemaOrder(TRP,S);
for t = ["trial_waves","block_waves"]
    x = TRP.(t);
    assert(height(x) > 0 && all(x.conduction_delay_ms == 0) && all(abs(x.time_offset_ms - 0.3) < 1e-15) && ...
        max(abs(x.lat_peak_ms - (x.lat_peak_raw_ms - 0.3)),[],'omitnan') < 1e-12, ...
        '%s: lat_peak_ms = lat_peak_raw_ms - the session''s 0.3 ms',t);
end
assert(max(abs(TRP.trial_waves.lat_peak_raw_ms - (TR.trial_waves.lat_peak_ms + 0.1)),[],'omitnan') < 1e-12, ...
    'trial_waves: the raw latency is the same pick whatever the offset');
DP = mabr.analysis.Export.dictionary(TP);
assert(contains(lower(DP.Description(DP.Table == "peaks" & DP.Column == "lat_peak_ms")),"sound arrival") && ...
    contains(DP.Description(DP.Table == "peak_measures" & DP.Column == "conduction_delay_ms"),"do not depend"), ...
    'the dictionary says latencies are re sound arrival and IPLs do not depend on the delay');
fprintf('  PASS Part P: latencies re sound arrival (stored 0.35 ms = %.4f ms delay + offset; label override; settings; none); IPLs unchanged; raw tables\n',cdel);

%% ---- Part Q: -Inf (no response on an attenuation axis) is encoded like Inf -------
[AQ,exQ] = attenuationResults();
itQ = struct('Key',"SUBJ-ID-9003/atten",'Results',AQ,'Labels',struct('Subject',"SUBJ-ID-9003"), ...
    'Notes',[],'Session',[]);
assert(AQ.Thresholds.Final(1) == -Inf && AQ.Thresholds.FinalCensored(1) == "left", ...
    'fixture: SeriesThreshold.finalValue of no response on an attenuation axis is -Inf, left-censored');
TQ = mabr.analysis.Export.tables(itQ,Tables=["thresholds","peaks"]);
assertNoInf(TQ,'attenuation axis');
for k = 1:numel(exQ)
    r = TQ.thresholds(TQ.thresholds.series_key == exQ(k).Key,:);
    assert(height(r) == 1 && r.cens == exQ(k).cens,'%s: cens "%s" (expected "%s")',exQ(k).Label,r.cens,exQ(k).cens);
    for f = ["threshold_db","thr_lo_db","thr_hi_db","thr_upper_db","threshold_imputed_db","threshold_fit_db","ci_lo_db","ci_hi_db"]
        assert(isequaln(r.(f),exQ(k).(f)),'%s: %s = %g (expected %g)',exQ(k).Label,f,r.(f),exQ(k).(f));
    end
    assert(r.imputation_rule == exQ(k).rule,'%s: imputation_rule',exQ(k).Label);
end
pq = TQ.peaks;
assert(all(isnan(pq.level_re_thr_db(pq.series_key == exQ(1).Key))) && ...
    all(isnan(pq.level_re_thr_db(pq.series_key == exQ(2).Key))), ...
    'no response on an attenuation axis: level_re_thr_db NA');
r32 = pq(pq.series_key == exQ(3).Key,:);
assert(all(abs(r32.level_re_thr_db - (45 - r32.attenuation)) < 1e-12) && any(r32.level_re_thr_db > 0), ...
    'attenuation axis: level_re_thr_db = threshold - attenuation (positive = louder than threshold)');
fq = mabr.analysis.Export.write(TQ,fullfile(root,"atten"),Formats="csv");
for t = ["thresholds","peaks"]
    txt = readUtf8(fq.File(fq.Table == t));
    assert(isempty(regexp(txt,'(^|,|\n)"?(NaN|-?Inf)"?(?=,|\r|\n|$)','once')),'%s CSV: no NaN/Inf/-Inf text',t);
end
% A v1 results struct with -Inf (legacy no response on an attenuation axis).
V1q = v1Results();
V1q.Thresholds.Threshold(2) = -Inf; V1q.Thresholds.Curated(2) = -Inf; V1q.Thresholds.IsCurated(2) = false;
T1q = mabr.analysis.Export.tables(struct('Key',"OLD",'Results',V1q,'Labels',struct(),'Notes',[],'Session',[]), ...
    Tables="thresholds");
t16q = T1q.thresholds(T1q.thresholds.frequency_khz == 16,:);
assert(t16q.cens == "left" && t16q.threshold_db == 20 && isnan(t16q.thr_lo_db) && t16q.thr_hi_db == 20, ...
    'v1 -Inf: left-censored at the lowest level');
assertNoInf(T1q,'v1 -Inf');
% The other built-in methods recomputed on the attenuation axis meet -Inf
% from SeriesThreshold itself (a no-response series fitted on -level).
% Stored p-values (none significant at 8 kHz) and enough sweeps per level
% for the default MinSweeps.
AQa = AQ;
AQa.Conditions.nClean(:) = 200;
AQa.Conditions.p = 0.5*ones(height(AQa.Conditions),1);
loud = AQa.Conditions.Frequency ~= 8 & AQa.Conditions.Attenuation <= 30;
AQa.Conditions.p(loud) = 0.001;
itQa = itQ; itQa.Results = AQa;
TQa = mabr.analysis.Export.tables(itQa,Tables="thresholds",ThresholdsAll=true);
assertNoInf(TQa,'ThresholdsAll on an attenuation axis');
qa = TQa.thresholds;
% The fixture's primary method is perm-descending; perm-glm is recomputed.
assert(all(qa.method(qa.is_primary) == "perm-descending"),'fixture: perm-descending is primary');
pdq = qa(qa.series_key == exQ(1).Key & qa.method == "perm-glm",:);
assert(height(pdq) == 1 && ~pdq.is_primary && pdq.cens == "left" && isnan(pdq.thr_lo_db) && pdq.thr_hi_db == 0 && ...
    pdq.threshold_db == 0 && pdq.thr_upper_db == 0 && isnan(pdq.threshold_fit_db) && pdq.threshold_imputed_db == -10, ...
    'ThresholdsAll: perm-glm no response on the attenuation axis (-Inf) is left-censored at the lowest attenuation (0 dB)');
pdr = qa(qa.series_key == exQ(2).Key & qa.method == "perm-glm",:);
assert(height(pdr) == 1 && ismember(pdr.cens,["none","interval"]) && pdr.threshold_db > 25 && pdr.threshold_db < 45, ...
    'ThresholdsAll: perm-glm with responses down to 30 dB attenuation puts the threshold near 35 dB attenuation (%g)',pdr.threshold_db);
if hasPq
    fqp = mabr.analysis.Export.write(TQa,fullfile(root,"attenpq"),Formats="parquet");
    qq = parquetread(fqp.File(fqp.Table == "thresholds"));
    nums = qq(:,vartype('numeric'));
    assert(~any(isinf(nums{:,:}),'all') && height(qq) == height(qa),'attenuation thresholds Parquet: no Inf');
end
fprintf('  PASS Part Q: -Inf (attenuation no response) left-censored at its bound like Inf; fallback bounds; sensation level on the attenuation axis; ThresholdsAll; no Inf text\n');

%% ---- Part R: appending sessions whose tables differ in columns -----------------
% A tone session has frequency_khz, a click session none: each format's
% Append must take the union, not fail or drop the column.
TA1 = mabr.analysis.Export.tables(items(1),Tables="thresholds");
TB1 = mabr.analysis.Export.tables(items(2),Tables="thresholds",IncludeTestMode=true);
assert(ismember("frequency_khz",string(TA1.thresholds.Properties.VariableNames)) && ...
    ~ismember("frequency_khz",string(TB1.thresholds.Properties.VariableNames)),'fixture: the click session has no frequency column');
fmts = ["csv" "mat"];
if hasPq, fmts(end+1) = "parquet"; end
fa = fullfile(root,"append");
mabr.analysis.Export.write(TA1,fa,Formats=fmts);
fb = mabr.analysis.Export.write(TB1,fa,Formats=fmts,Append=true);
nAB = height(TA1.thresholds) + height(TB1.thresholds);
for f = fmts
    file = fb.File(fb.Format == f);
    switch f
        case "csv",     q = readBack(file);
        case "mat",     m = load(file); q = m.MABRExport.thresholds;
        case "parquet", q = parquetread(file);
    end
    assert(height(q) == nAB,'%s append: %d rows (got %d)',f,nAB,height(q));
    fk = q.frequency_khz;
    if ~isnumeric(fk), fk = str2double(string(fk)); end
    isClick = string(q.stimulus) == "ClickTrain";
    assert(any(isClick) && all(isnan(fk(isClick))) && all(isfinite(fk(~isClick))), ...
        '%s append: frequency_khz kept for the tones, missing for the clicks',f);
    assert(all(ismissing(string(q.subject)) == false) && all(string(q.subject) ~= ""), ...
        '%s append: text columns stay text',f);
end
fprintf('  PASS Part R: CSV, MAT and Parquet appends take the union of two sessions'' columns\n');

%% ---- leaks -----------------------------------------------------------------
tm = timerfindall;
tags = string(get(tm,'Tag'));
assert(~any(startsWith(tags,"MABR_Offline")),'no MABR_Offline timer left behind');
assert(all(ismember(findall(groot,'Type','figure'),figs0)),'no figure left open');
clear cleanup
fprintf('== verify_offline_export PASSED (%.1f s) ==\n',toc(t0));
end

% =========================================================================
%  Fixtures
% =========================================================================
function [R,fx] = toneResults()
% A tone grid (2-32 kHz x 0-80 dB) as Session.saveResults would write it
% (results v2, no sweeps), built by hand so every exported number is known.
fs    = 12000;
time  = (-144:144).'/12;                       % ms, the [-12 12] window at 12 kHz
freqs = [2 4 8 16 32];
levels = 0:20:80;
first = [40 Inf 0 60 80];                      % first detected level per frequency
[Fg,Lg] = meshgrid(freqs,levels);
F = Fg(:); L = Lg(:);
nC = numel(F);
kv = @(v) mabr.analysis.Stats.keyValue(v);
sk = "Stimulus=Tone|AcqMode=conventional|Frequency=" + kv(F);
key = sk + "|Level=" + kv(L);
fi = arrayfun(@(f) find(freqs == f),F);
det = L >= first(fi).';
ci = @(f,l) find(F == f & L == l);

nS = 64*ones(nC,1); nRej = zeros(nC,1);
nRej(ci(2,80)) = 6;
nClean = nS - nRej; nPos = floor(nClean/2); nNeg = nClean - nPos;
p = 0.30 + 0.01*(1:nC).'; p(det) = 0.001;
st = (1:nC).'/10; st(det) = 50;
RN = (0.20 + 0.002*L)*1e-6;
splitR = 0.05*ones(nC,1); splitR(det) = 0.6;
xcu = 0.1*ones(nC,1); xcu(det) = 0.8; xcu(L == 80) = NaN;
dwu = xcu + 0.1;                                % (NaN at the top too)
snr = 0.2*ones(nC,1); snr(det) = 6;
C = table(key,repmat("Tone",nC,1),repmat("conventional",nC,1),F,L,nS,nRej,ones(nC,1),nClean,nPos,nNeg, ...
    repmat("continuous",nC,1),repmat([-12 12],nC,1),repmat("V",nC,1),repmat("dB SPL",nC,1),strings(nC,1), ...
    p,det,st,det,det,RN,RN*1.02,1e-6*det + 0.2e-6,0.18e-6*ones(nC,1),1 + 9*det,p,8*ones(nC,1), ...
    snr,snr - 0.5,1 + 4*det,20*ones(nC,1),62*ones(nC,1),p,splitR,0.05*ones(nC,1),splitR - 0.1, ...
    splitR + 0.1,16*ones(nC,1),xcu,0.083*ones(nC,1),xcu - 0.05,dwu,0.17*ones(nC,1),0.08*ones(nC,1), ...
    'VariableNames',{'Key','Stimulus','AcqMode','Frequency','Level','nSweeps','nRejected','nFiles', ...
    'nClean','nPos','nNeg','Processing','Extent','Units','LevelUnit','Flags','p','isSig','strength', ...
    'Detected','DetectedAuto','RN','RNPM','ResponseRMS','BaselineRMS','F','PowerP','PowerF95','SNR', ...
    'SNRCorr','Fsp','FspDF1','FspDF2','FspP','SplitR','SplitRSD','SplitRP025','SplitRP975','SplitN', ...
    'XCorrUp','XCorrLag','XCorrUp0','DTWUp','DTWLag','DTWLagRange'});

% ---- thresholds (primary method perm-glm), one row per series ----------
skeys = "Stimulus=Tone|AcqMode=conventional|Frequency=" + kv(freqs.');
rv = datetime(2026,10,1,16,0,0);
T = table();
T.Key = skeys;
T.Stimulus = repmat("Tone",5,1); T.AcqMode = repmat("conventional",5,1); T.Frequency = freqs.';
T.LevelParam = repmat("Level",5,1); T.Method = repmat("perm-glm",5,1); T.Metric = repmat("detection",5,1);
T.Type = repmat("glm",5,1); T.FitTarget = repmat("binary",5,1); T.Criterion = 0.5*ones(5,1);
T.CriterionUnit = repmat("probability",5,1); T.Convention = repmat("midpoint",5,1);
T.Threshold    = [31.2; Inf; 0; 51.5; 70.4];
T.ThresholdRaw = [31.2; 95;  -4; 51.5; 70.4];
T.Status   = ["ok";"no-response";"all-respond";"ok";"ok"];
T.Censored = ["none";"right";"left";"none";"none"];
T.ThrLo = [31.2; 80; NaN; 51.5; 70.4];
T.ThrHi = [31.2; NaN; 0; 51.5; 70.4];
T.CILower = [24; NaN; NaN; 44; 61]; T.CIUpper = [38; NaN; NaN; 59; Inf];
T.CIMethod = ["profile";"none";"none";"profile";"profile"];
T.NumLevels = 5*ones(5,1); T.NumUsable = 5*ones(5,1); T.NumSig = [3;0;5;2;1];
T.LevelStep = 20*ones(5,1); T.MinLevel = zeros(5,1); T.MaxLevel = 80*ones(5,1);
T.Converged = true(5,1); T.Message = repmat("psychometric (advisory)",5,1);
T.Flags = ["";"no detected level";"";"";"profile CI open"];
T.Decision = ["manual";"";"accepted";"accepted";"excluded"];
T.ManualValue = [40; NaN; NaN; NaN; NaN]; T.ManualKind = ["level";"";"";"";""];
T.Note = ["moved to the level by eye";"";"";"";"electrode came loose"];
T.ReviewedBy = ["dan";"";"dan";"dan";"dan"]; T.ReviewedAt = [rv;NaT;rv;rv;rv];
T.ReviewedValue = [31.2;NaN;0;51.5;70.4]; T.ReviewedMethod = ["perm-glm";"";"perm-glm";"perm-glm";"perm-glm"];
Fin = arrayfun(@(i) mabr.analysis.SeriesThreshold.finalValue(table2struct(T(i,:)),"midpoint"),(1:5).', ...
    'UniformOutput',false);
Fin = [Fin{:}];
T.Final = [Fin.Final].'; T.FinalCensored = [Fin.FinalCensored].'; T.FinalLo = [Fin.FinalLo].'; T.FinalHi = [Fin.FinalHi].';
T.Curated = T.Final; T.IsCurated = ismember(T.Decision,["manual","noresponse","allrespond","excluded"]);
T.Fit = arrayfun(@(i) struct('Type',"glm",'X',levels.','Y',double(det(fi == i)),'Threshold',T.Threshold(i)), ...
    (1:5).','UniformOutput',false);

% ---- peaks: five waves at every condition --------------------------------
waves = ["I","II","III","IV","V"];
lat0 = [1.5 2.3 3.1 4.0 4.9];
nP = nC*5;
pKey = strings(nP,1); pSk = pKey; pWave = pKey; pState = pKey;
pF = nan(nP,1); pL = pF; pLat = pF; pVal = pF; tLat = pF; tVal = pF;
lat = zeros(5,numel(freqs),numel(levels));
amp = zeros(numel(freqs),numel(levels));
rows = 0;
for i = 1:nC
    f = F(i); l = L(i); jf = find(freqs == f); jl = find(levels == l);
    a = 1e-6*(0.5 + 0.01*(l - min(first(jf),80)));
    amp(jf,jl) = 1.8*a;
    for w = 1:5
        rows = rows + 1;
        la = lat0(w) + 0.02*(80 - l);
        lat(w,jf,jl) = la;
        pKey(rows) = key(i); pSk(rows) = sk(i); pF(rows) = f; pL(rows) = l; pWave(rows) = waves(w);
        if det(i)
            pState(rows) = "auto";
            pLat(rows) = la; pVal(rows) = a; tLat(rows) = la + 0.45; tVal(rows) = -0.8*a;
        else
            pState(rows) = "none";
        end
    end
end
Pk = table(pKey,pSk,repmat("Tone",nP,1),repmat("conventional",nP,1),pF,pL,pWave,pState,pState, ...
    pLat,pVal,tLat,tVal,zeros(nP,1),'VariableNames',{'Key','SeriesKey','Stimulus','AcqMode', ...
    'Frequency','Level','Wave','State','TroughState','PeakLatency','PeakValue','TroughLatency', ...
    'TroughValue','Baseline'});
Pk.AmpPT = Pk.PeakValue - Pk.TroughValue;
Pk.AmpBP = Pk.PeakValue; Pk.AmpBT = Pk.TroughValue;
Pk.Prominence = 1.2*Pk.PeakValue;
rnOf = RN(arrayfun(@(k) find(key == k),Pk.Key));
Pk.ProminenceRN = Pk.Prominence./rnOf;
Pk.Detectable = Pk.ProminenceRN >= 2;
manKey = key(ci(2,60)); absKey = key(ci(2,40));
k = Pk.Key == manKey & Pk.Wave == "III";
Pk.State(k) = "manual"; Pk.PeakLatency(k) = 3.5;
k = Pk.Key == absKey & Pk.Wave == "V";
Pk.State(k) = "absent"; Pk.PeakLatency(k) = NaN; Pk.PeakValue(k) = NaN; Pk.TroughLatency(k) = NaN;
Pk.TroughValue(k) = NaN; Pk.AmpPT(k) = NaN; Pk.AmpBP(k) = NaN; Pk.AmpBT(k) = NaN; Pk.Detectable(k) = false;
below = false(height(Pk),1);
for s = 1:5
    r = Pk.SeriesKey == skeys(s);
    below(r) = mabr.analysis.SeriesThreshold.belowThreshold(Pk.Level(r),T.Final(s),T.FinalCensored(s),T.FinalLo(s));
end
Pk.BelowThreshold = below;
Pk.EdgeAffected = false(height(Pk),1);
Pk.LatencyMethod = repmat("parabolic",height(Pk),1);
Pk.LatencySE = nan(height(Pk),1); Pk.LatencyCILo = Pk.LatencySE; Pk.LatencyCIHi = Pk.LatencySE;
Pk.AmpPTSE = Pk.LatencySE; Pk.AmpPTCILo = Pk.LatencySE; Pk.AmpPTCIHi = Pk.LatencySE;
Pk.BootstrapUnstable = false(height(Pk),1);

% ---- means, per-sweep info, files -------------------------------------
nT = numel(time);
Bm = zeros(nT,nC,'single'); Pm = Bm; Nm = Bm;
for i = 1:nC
    y = 1e-6*det(i)*exp(-((time - 2)/0.3).^2);
    cm = 0.1e-6*cos(2*pi*time/1).*(time > 0);
    Bm(:,i) = y; Pm(:,i) = y + cm; Nm(:,i) = y - cm;
end
Means = struct('Keys',key,'Balanced',Bm,'Positive',Pm,'Negative',Nm, ...
    'SEM',0.05e-6*ones(nT,nC,'single'),'N',nClean);
cond = repelem((1:nC).',64,1); ord = repmat((1:64).',nC,1);
pol = int8(repmat([1;-1],32*nC,1));
rej = false(numel(cond),1); reason = zeros(numel(cond),1,'uint8');
base = (ci(2,80) - 1)*64;
rej(base + [5 10 20 30 31 50]) = true;
reason(base + [5 10 20]) = 1; reason(base + [30 31]) = 2; reason(base + 50) = 3;
SI = struct('Cond',uint16(cond),'File',uint16(cond),'Index',uint32(ord),'Order',uint32(ord), ...
    'Time',single((1500 + (ord - 1)*292)/fs),'Polarity',pol,'Rejected',rej,'Reason',reason, ...
    'Excess',false(numel(cond),1),'RMS',single(1e-6*ones(numel(cond),1)), ...
    'P2P',single(4e-6*ones(numel(cond),1)),'MaxAbs',single(2e-6*ones(numel(cond),1)), ...
    'BaselineRMS',single(0.9e-6*ones(numel(cond),1)),'TemplateAmp',single(ones(numel(cond),1)), ...
    'TemplateR',single(0.05*ones(numel(cond),1)));
start = datetime(2026,10,1,10,0,0);
fstart = start + seconds(15*(0:nC-1)).';
folder = "SUBJ-ID-9001_261001T100000";
fname = "SUBJ-ID-9001_Frequency-" + F + "kHz_Level-" + L + "dB_261001T1000" + compose("%02d",(0:nC-1).') + ".abr";
Files = table(F,L,fstart,fname,repmat(folder,nC,1),nS,repmat(fs,nC,1),false(nC,1),folder + "/" + fname, ...
    repmat("Tone",nC,1),"Tone_" + F,repmat("conventional",nC,1),repmat("continuous",nC,1),120*ones(nC,1), ...
    true(nC,1),repmat("V",nC,1),repmat("dB SPL",nC,1),true(nC,1),repmat(5e5,nC,1),fstart,25*ones(nC,1), ...
    24.33*ones(nC,1),repmat("E1+",nC,1),zeros(nC,1),true(nC,1),strings(nC,1),repmat("10:00 Tone conventional (25 files)",nC,1), ...
    false(nC,1),strings(nC,1),repmat("2026-09-30T09:00:00",nC,1),0.354*ones(nC,1), ...
    'VariableNames',{'Frequency','Level','timestamp','fileName','folder','nSweeps','SampleRate','TestMode', ...
    'FileId','Stimulus','StimID','AcqMode','Layout','SweepLength','AlternatePolarity','Units','LevelUnit', ...
    'Calibrated','Bytes','Modified','Duration','MinISI','Era','TruncatedSweeps','Include','Reason','RunGroup', ...
    'Short','DuplicateOf','CalibrationTime','InputFullScale'});

set_ = mabr.analysis.Settings(MinSweeps=20,MinPerPolarity=10,NumPermutations=200);
R = struct();
R.Version = 2;
R.Provenance = struct('AnalyzedAt','2026-10-01T15:40:00','MATLABVersion',version,'MABRVersion',"219549d", ...
    'Host',"RIG",'User',"dan",'SettingsHash',set_.hash());
R.Settings = set_.toStruct();
R.StepState = struct('segment',[],'reject',[],'detect',[],'measure',[],'thresholds',[],'peaks',[]);
R.Summary = struct('Key',"SUBJ-ID-9001/" + folder,'Keys',"SUBJ-ID-9001/" + folder,'Paths',"C:/data/" + folder, ...
    'Name',folder,'Subject',"SUBJ-ID-9001",'SubjectRaw',"SUBJ-ID-9001",'Date','2026-10-01T10:00:00', ...
    'SampleRate',fs,'Window',[-12 12],'ResponseWindow',[0.5 8],'BaselineWindow',[-10 0],'Time',time, ...
    'ParamNames',["Stimulus","Frequency","Level"],'KeyParams',["Stimulus","AcqMode","Frequency","Level"], ...
    'LevelParam',"Level",'GroupParams',["Stimulus","AcqMode","Frequency"],'TestMode',false,'Units',"V", ...
    'LevelUnit',"dB SPL",'AcqModes',"conventional",'DataFingerprint',"0a1b2c3d",'NumFiles',nC, ...
    'NumConditions',nC,'NumSweeps',sum(nS),'NumRejected',sum(nRej), ...
    'FilterDescription',"300-3000 Hz FIR (filtfilt)", ...
    'WindowedDescription',"Butterworth order 2, -6 dB at 237-3418 Hz (filtfilt), linear detrend, reflect pad 57", ...
    'HasCompact',false,'Exclude',strings(0,1),'UnitOverride',struct('InputFullScale',NaN,'AmplifierGain',NaN), ...
    'TimeOffset',NaN);
R.Files = Files;
R.Conditions = C;
R.Means = Means;
R.SweepInfo = SI;
R.Detection = struct('p',num2cell(p),'isSig',num2cell(det));
R.Thresholds = T;
R.CurationArchive = T([],:);
R.Peaks = Pk;
R.PeakOverrides = table(manKey,"III","P","manual",3.5,rv,"dan",'VariableNames',{'Key','Wave','Kind','State','Latency','Time','By'});
R.ManualRejections = table("x",50,true,rv,"dan",'VariableNames',{'FileId','SweepIndex','Reject','Time','By'});
R.DetectionOverrides = table(key(ci(2,0)),0,rv,"dan",'VariableNames',{'Key','Value','Time','By'});
R.Messages = table(rv,"info","segment","ok",'VariableNames',{'Time','Level','Step','Text'});
R.EditLog = table(rv,"dan","accept",skeys(3),"","accepted",'VariableNames',{'Time','User','Action','Key','Old','New'});

% ---- what the export must say ------------------------------------------
ex = struct('Key',num2cell(skeys),'Label',{"2 kHz (manual level)";"4 kHz (right)";"8 kHz (left)";"16 kHz (none)";"32 kHz (excluded)"});
vals = { ...  % cens, thr, lo, hi, upper, imputed, rule, fit, decision, status, used, PDcens, PDthr
    "interval", 30, 20, 40, 40, 30, "none", 31.2, "manual", "ok", true, "interval", 30
    "right",    80, 80, NaN, 80, 100, "max + step", NaN, "", "no-response", true, "right", 80
    "left",     0, NaN, 0, 0, -20, "min - step", 0, "accepted", "all-respond", true, "left", 0
    "none",     51.5, 51.5, 51.5, 51.5, 51.5, "none", 51.5, "accepted", "ok", true, "interval", 50
    "",         NaN, NaN, NaN, NaN, NaN, "", 70.4, "excluded", "ok", false, "interval", 70};
fn = ["cens","threshold_db","thr_lo_db","thr_hi_db","thr_upper_db","threshold_imputed_db","imputation_rule", ...
      "threshold_fit_db","decision","fit_status","used","PDcens","PDthr"];
for k = 1:5
    for j = 1:numel(fn), ex(k).(fn(j)) = vals{k,j}; end
    ex(k).Frequency = freqs(k);
end
fx = struct();
fx.Key = "SUBJ-ID-9001/" + folder;
fx.SeriesKeys = skeys;
fx.CondKeys = key;
fx.CondIndex = ci;
fx.Expected = ex;
fx.RN = RN;
fx.Time = time;
fx.Hash = set_.hash();
fx.NoteText = "Électrode déplacée — 3,2 kΩ";
fx.ManualKey = manKey; fx.ManualLat = 3.5;
fx.AbsentKey = absKey;
fx.Lat = @(w,f,l) lat(w,freqs == f,levels == l);
fx.AmpPT = @(f,l) amp(freqs == f,levels == l);
fx.AmpSlope = 1.8*0.01e-6;                      % V/dB of the generated amp_pt at 2 kHz
fx.Lat0 = lat0 + 0.02*80;                       % latency intercept at 0 dB (raw)
fx.FileIds = folder + "/" + fname;
fx.FileStart = fstart;
end

function R = clickResults()
% A click series recorded in Test Mode: Stimulus but no Frequency.
fs = 12000;
time = (-144:144).'/12;
L = (30:20:90).';
n = numel(L);
key = "Stimulus=ClickTrain|AcqMode=conventional|Level=" + mabr.analysis.Stats.keyValue(L);
C = table(key,repmat("ClickTrain",n,1),repmat("conventional",n,1),L,32*ones(n,1),zeros(n,1),ones(n,1), ...
    32*ones(n,1),16*ones(n,1),16*ones(n,1),repmat("continuous",n,1),repmat([-12 12],n,1),repmat("V",n,1), ...
    repmat("dB re max",n,1),strings(n,1),[0.4;0.001;0.001;0.001],[false;true;true;true],[1;9;9;9], ...
    [false;true;true;true],[false;true;true;true],0.3e-6*ones(n,1), ...
    'VariableNames',{'Key','Stimulus','AcqMode','Level','nSweeps','nRejected','nFiles','nClean','nPos', ...
    'nNeg','Processing','Extent','Units','LevelUnit','Flags','p','isSig','strength','Detected', ...
    'DetectedAuto','RN'});
T = table("Stimulus=ClickTrain|AcqMode=conventional","ClickTrain","conventional","Level","perm-descending", ...
    "detection","descending",0.05,"p","midpoint",40,40,"ok","interval",30,50,NaN,NaN,"none",4,4,3,20,30,90, ...
    "", "",NaN,"",40,"interval",30,50,"","",NaT, ...
    'VariableNames',{'Key','Stimulus','AcqMode','LevelParam','Method','Metric','Type','Criterion', ...
    'CriterionUnit','Convention','Threshold','ThresholdRaw','Status','Censored','ThrLo','ThrHi','CILower', ...
    'CIUpper','CIMethod','NumLevels','NumUsable','NumSig','LevelStep','MinLevel','MaxLevel','Flags', ...
    'Decision','ManualValue','ManualKind','Final','FinalCensored','FinalLo','FinalHi','Note','ReviewedBy', ...
    'ReviewedAt'});
nT = numel(time);
Means = struct('Keys',key,'Balanced',zeros(nT,n,'single'),'Positive',zeros(nT,n,'single'), ...
    'Negative',zeros(nT,n,'single'),'SEM',zeros(nT,n,'single'),'N',32*ones(n,1));
R = struct('Version',2, ...
    'Provenance',struct('AnalyzedAt','2026-10-15T11:00:00','SettingsHash',""), ...
    'Settings',[], ...
    'Summary',struct('Key',"SUBJ-ID-9002/SUBJ-ID-9002_261015T100000",'Subject',"SUBJ-ID-9002", ...
        'SubjectRaw',"SUBJ-ID-9002",'Date','2026-10-15T10:00:00','SampleRate',fs,'Window',[-12 12], ...
        'ResponseWindow',[0.5 8],'Time',time,'ParamNames',["Stimulus","Level"], ...
        'KeyParams',["Stimulus","AcqMode","Level"],'LevelParam',"Level",'GroupParams',["Stimulus","AcqMode"], ...
        'TestMode',true,'Units',"V",'LevelUnit',"dB re max",'AcqModes',"conventional",'NumFiles',n, ...
        'NumConditions',n,'NumSweeps',32*n), ...
    'Files',table(),'Conditions',C,'Means',Means,'SweepInfo',[],'Thresholds',T, ...
    'Peaks',table(),'DetectionOverrides',table());
end

function [R,ex] = attenuationResults()
% A session on an ATTENUATION axis (LevelDirection descending: more
% attenuation = softer), every threshold row an infinity or a bound the
% encoder must find for itself:
%   8 kHz   no response, by SeriesThreshold.finalValue: Final -Inf, left
%           at the lowest attenuation; the fit and its CI -Inf too
%   16 kHz  Final -Inf, left, bounds missing (the series' MinLevel stands)
%   32 kHz  an interval (40, 50] dB attenuation, point 45
%   4 kHz   an ascending-style +Inf right-censored row whose bound is
%           missing (the series' MaxLevel stands)
att = (0:10:60).';
fr = [8 16 32 4];
kv = @(v) mabr.analysis.Stats.keyValue(v);
[Fg,Ag] = meshgrid(fr,att);
F = Fg(:); Aa = Ag(:); n = numel(F);
sk = "Stimulus=Tone|AcqMode=conventional|Frequency=" + kv(F);
key = sk + "|Attenuation=" + kv(Aa);
C = table(key,repmat("Tone",n,1),repmat("conventional",n,1),F,Aa,64*ones(n,1),64*ones(n,1), ...
    'VariableNames',{'Key','Stimulus','AcqMode','Frequency','Attenuation','nSweeps','nClean'});
skeys = "Stimulus=Tone|AcqMode=conventional|Frequency=" + kv(fr.');
fitD = struct('Type',"descending",'X',att,'LevelDirection',"descending");
fitA = struct('Type',"descending",'X',att,'LevelDirection',"ascending");
nr = struct('Decision',"noresponse",'MinLevel',0,'MaxLevel',60,'Fit',{{fitD}});
F8 = mabr.analysis.SeriesThreshold.finalValue(nr,"midpoint");
T = table(skeys,repmat("Tone",4,1),repmat("conventional",4,1),fr.',repmat("Attenuation",4,1), ...
    repmat("perm-descending",4,1),[-Inf;-Inf;45;Inf],["no-response";"no-response";"ok";"no-response"], ...
    ["left";"left";"interval";"right"],[NaN;NaN;40;NaN],[0;NaN;50;NaN],[-Inf;NaN;38;NaN],[-Inf;NaN;52;Inf], ...
    10*ones(4,1),zeros(4,1),60*ones(4,1),["noresponse";"";"";""], ...
    [F8.Final;-Inf;45;Inf],[F8.FinalCensored;"left";"interval";"right"],[F8.FinalLo;NaN;40;NaN],[F8.FinalHi;NaN;50;NaN], ...
    {fitD;[];fitD;fitA}, ...
    'VariableNames',{'Key','Stimulus','AcqMode','Frequency','LevelParam','Method','Threshold','Status', ...
    'Censored','ThrLo','ThrHi','CILower','CIUpper','LevelStep','MinLevel','MaxLevel','Decision', ...
    'Final','FinalCensored','FinalLo','FinalHi','Fit'});
pk = key(Aa == 20 | Aa == 50);
np = numel(pk);
[~,pc] = ismember(pk,key);
Pk = table(pk,repmat("I",np,1),repmat("auto",np,1),2 + 0.01*Aa(pc),1e-6*ones(np,1),-1e-6*ones(np,1), ...
    'VariableNames',{'Key','Wave','State','PeakLatency','PeakValue','TroughValue'});
R = struct('Version',2,'Provenance',struct('SettingsHash',""),'Settings',[], ...
    'Summary',struct('Key',"SUBJ-ID-9003/atten",'Subject',"SUBJ-ID-9003",'Date','2026-10-02T09:00:00', ...
        'SampleRate',12000,'Window',[-12 12],'ResponseWindow',[0.5 8],'Time',(-144:144).'/12, ...
        'ParamNames',["Stimulus","Frequency","Attenuation"],'KeyParams',["Stimulus","AcqMode","Frequency","Attenuation"], ...
        'LevelParam',"Attenuation",'GroupParams',["Stimulus","AcqMode","Frequency"],'TestMode',false, ...
        'Units',"V",'LevelUnit',"dB"), ...
    'Files',table(),'Conditions',C,'Means',[],'SweepInfo',[],'Thresholds',T,'Peaks',Pk, ...
    'DetectionOverrides',table());
ex = struct('Key',num2cell(skeys),'Label',{"8 kHz (finalValue -Inf)";"16 kHz (-Inf, no bound)"; ...
    "32 kHz (interval)";"4 kHz (+Inf, no bound)"});
vals = { ... % cens, thr, lo, hi, upper, imputed, rule, fit, cilo, cihi
    "left",     0, NaN, 0,  0,  -10, "min - step", NaN, NaN, NaN
    "left",     0, NaN, 0,  0,  -10, "min - step", NaN, NaN, NaN
    "interval", 45, 40, 50, 50, 45,  "none",       45,  38,  52
    "right",    60, 60, NaN, 60, 70, "max + step", NaN, NaN, NaN};
fn = ["cens","threshold_db","thr_lo_db","thr_hi_db","thr_upper_db","threshold_imputed_db","rule", ...
      "threshold_fit_db","ci_lo_db","ci_hi_db"];
for k = 1:4
    for j = 1:numel(fn), ex(k).(fn(j)) = vals{k,j}; end
end
end

function [s,fx] = rawSession(key0,kp,stim,freq)
% A session-shaped struct holding sweeps: two conditions of 64 sweeps
% (template + seeded noise, alternating polarity, sweep 3 of the first
% rejected), and picks on each mean -- what writeRaw reads off a Session.
time = (-144:144).'/12;
truth = mabrtest.SyntheticABR.defaults();
rs = RandStream('threefry','Seed',7);
lev = [80;40];
n = 64;
keys = strings(2,1);
X = cell(2,1); rej = X; pol = X; ord = X; exc = X;
Pk = table();
for c = 1:2
    f = freq; if isnan(f), f = 16; end
    y = mabrtest.SyntheticABR.template(time,lev(c),f,truth);
    Xc = y + 2e-6*randn(rs,numel(time),n);
    X{c} = Xc;
    r = false(1,n); if c == 1, r(3) = true; end
    rej{c} = r; pol{c} = repmat([1 -1],1,n/2); ord{c} = 1:n; exc{c} = false(1,n);
    if isnan(freq)
        keys(c) = "Stimulus=" + stim + "|AcqMode=conventional|Level=" + mabr.analysis.Stats.keyValue(lev(c));
    else
        keys(c) = "Stimulus=" + stim + "|AcqMode=conventional|Frequency=" + mabr.analysis.Stats.keyValue(freq) + ...
            "|Level=" + mabr.analysis.Stats.keyValue(lev(c));
    end
    m = mean(Xc(:,~r),2);
    W = mabr.analysis.Peaks.wavesFor(mabr.analysis.Peaks.defaultWaves(),"",f);
    P = mabr.analysis.Peaks.pick(time,m,W);
    P.Key = repmat(keys(c),height(P),1);
    Pk = [Pk; P(:,{'Key','Wave','State','PeakLatency','TroughLatency'})]; %#ok<AGROW>
end
C = table(keys,repmat(stim,2,1),repmat("conventional",2,1),lev,X,rej,pol,ord,exc, ...
    'VariableNames',{'Key','Stimulus','AcqMode','Level','Sweeps','Rejected','Polarity','SweepOrder','Excess'});
if ~isnan(freq), C.Frequency = [freq;freq]; end
s = struct('Key',key0,'Name',key0,'Subject',"SUBJ-ID-9001",'Time',time,'Conditions',C,'Peaks',Pk, ...
    'KeyParams',kp,'ResponseWindow',[0.5 8],'Settings',mabr.analysis.Settings(),'TimeOffset',NaN);
% Expected rows.
picked = arrayfun(@(c) sum(Pk.Key == keys(c) & Pk.State == "auto" & isfinite(Pk.PeakLatency)),1:2);
clean = [n-1 n];
fx.TrialWaveRows = sum(picked.*clean);
nb = 0; nbw = 0;
for c = 1:2
    k = ~rej{c};
    fin = all(isfinite(X{c}(:,k)),2);
    rows = time(fin) >= 0.5 & time(fin) <= 8;
    pr = Pk(Pk.Key == keys(c) & Pk.State == "auto" & isfinite(Pk.PeakLatency),:);
    [Tb,Tw] = mabr.analysis.SingleTrial.blocks(X{c}(fin,k),pol{c}(k),ord{c}(k),rows,time(fin),16, ...
        pr(:,{'Wave','PeakLatency','TroughLatency'}));
    nb = nb + height(Tb); nbw = nbw + height(Tw);
end
fx.BlockRows = nb;
fx.BlockWaveRows = nbw;
fx.SweepRows = 2*n*numel(time);
fx.Keys = keys;
fx.X1 = X{1};
fx.Time = time;
fx.RejectedOrder = 3;
end

% =========================================================================
%  Helpers
% =========================================================================
function checkSchemaOrder(T,S)
% Every table's columns are exactly the schema's, in order, with each
% placeholder expanded to the dynamic columns the table records.
for t = string(fieldnames(T)).'
    rows = S(S.Table == t,:);
    dyn = T.(t).Properties.UserData.Dynamic;
    expect = strings(1,0);
    for k = 1:height(rows)
        c = rows.Column(k);
        if startsWith(c,"<")
            if ~isempty(dyn), expect = [expect dyn([dyn.Placeholder] == c).Column]; end %#ok<AGROW>
        else
            expect(end+1) = c; %#ok<AGROW>
        end
    end
    got = string(T.(t).Properties.VariableNames);
    assert(isequal(got,expect),'%s columns follow the schema: got [%s]',t,strjoin(got,","));
end
end

function assertNoInf(T,what)
for t = string(fieldnames(T)).'
    x = T.(t);
    for v = string(x.Properties.VariableNames)
        if isnumeric(x.(v))
            assert(~any(isinf(x.(v)),'all'),'%s: %s.%s holds Inf',what,t,v);
        end
    end
end
end

function txt = readUtf8(f)
fid = fopen(f,'r','n','UTF-8');
c = onCleanup(@() fclose(fid));
txt = fread(fid,'*char').';
end

function R = readBack(f)
% A CSV read as MATLAB reads one, column names as written.
o = detectImportOptions(f,'Delimiter',',','Encoding','UTF-8','TextType','string', ...
    'VariableNamingRule','preserve');
R = readtable(f,o);
end

function [ok,why] = sameColumn(a,b)
% An exported column against what readtable gives back, as text the way the
% file holds it: numbers to 10 significant digits, missing as "".
ok = true; why = "";
ta = asText(a,true);
tb = asText(b,false);
if numel(ta) ~= numel(tb)
    ok = false; why = sprintf('%d vs %d values',numel(ta),numel(tb)); return
end
d = find(ta ~= tb,1);
if ~isempty(d)
    ok = false; why = sprintf('row %d: "%s" vs "%s"',d,ta(d),tb(d));
end
end

function s = asText(x,original)
x = x(:);
if isnumeric(x)
    x = double(x);
    s = strings(size(x));
    fin = isfinite(x);
    s(fin) = compose("%.10g",round(x(fin),10,'significant'));
elseif islogical(x)
    s = repmat("FALSE",size(x)); s(x) = "TRUE";
elseif isdatetime(x)
    isDay = all(isnat(x) | x == dateshift(x,'start','day')) && ~contains(x.Format,'HH');
    if (original && strcmp(x.Format,'yyyy-MM-dd')) || (~original && isDay)
        fmt = 'yyyy-MM-dd';
    else
        fmt = 'yyyy-MM-dd''T''HH:mm:ss';
    end
    s = string(x,fmt);
    s(ismissing(s)) = "";
else
    s = string(x);
    s(ismissing(s)) = "";
    % readtable gives numbers back for a text column of numbers: text that
    % is a number compares as the number (double(string) is str2double,
    % natively and fast).
    v = double(s);
    isn = ~isnan(v) & s ~= "";
    s(isn) = compose("%.10g",round(v(isn),10,'significant'));
end
end

function out = recordCall(m,c,n)
% A progress sink that remembers its calls ('reset' / 'get' with one char argument).
persistent store
out = [];
if nargin == 1 && ischar(m)
    if strcmp(m,'reset'), store = {}; else, out = store; end
    return
end
store{end+1} = {m,c,n};
end

function assertError(f,id,what)
% f() must throw the error id.
try
    f();
catch ME
    assert(strcmp(ME.identifier,id),'%s: error %s (expected %s): %s',what,ME.identifier,id,ME.message);
    return
end
error('verify_offline_export:noError','%s: expected the error %s',what,id);
end

function V = v1Results()
% A results struct as the pre-rewrite Session.toStruct wrote it (Version 1):
% one struct, Conditions with sweep cells, Thresholds with Threshold/Curated.
time = (-144:144).'/12;
F = [8;8;8;16;16;16]; L = [20;40;60;20;40;60];
n = 6; N = 40;
rs = RandStream('threefry','Seed',11);
Sw = cell(n,1); Rj = Sw; Po = Sw;
for i = 1:n
    Sw{i} = 1e-6*randn(rs,numel(time),N);
    Rj{i} = false(1,N); Po{i} = repmat([1 -1],1,N/2);
end
Rj{1}(3) = true;
C = table(F,L,Sw,Rj,Po,N*ones(n,1),[1;0;0;0;0;0],ones(n,1),[0.5;0.01;0.001;0.4;0.3;0.2], ...
    [false;true;true;false;false;false],(1:n).','VariableNames',{'Frequency','Level','Sweeps', ...
    'Rejected','Polarity','nSweeps','nRejected','nFiles','p','isSig','strength'});
fit8 = struct('Threshold',30.5,'X',[20;40;60],'Type',"glm");
fit16 = struct('Threshold',Inf,'X',[20;40;60],'Type',"glm");
T = table([8;16],[30.5;Inf],[25;NaN],[36;NaN],[30.5;Inf],[false;true],["glm";"glm"],["binary";"binary"], ...
    [3;3],[2;0],{fit8;fit16},["Level";"Level"],'VariableNames',{'Frequency','Threshold','CILower', ...
    'CIUpper','Curated','IsCurated','Type','FitTarget','NumLevels','NumSig','Fit','LevelParam'});
V = struct('Version',1,'Path',"C:/data/old",'Name',"SUBJ-ID-7_old",'Subject',"SUBJ-ID-7", ...
    'Date',datetime(2025,5,1,9,0,0),'SampleRate',12000,'Window',[-12 12],'ResponseWindow',[0 10], ...
    'Time',time,'ParamNames',["Frequency","Level"],'TestMode',false,'Files',table(), ...
    'Conditions',C,'Thresholds',T,'FilterDescription',"300-3000 Hz FIR");
end

function q = readDataset(files,t)
% Every Parquet file a table was written to, stacked.
r = files(files.Table == t & files.Format == "parquet" & files.File ~= "",:);
assert(height(r) >= 1,'%s was written as Parquet',t);
q = table();
for k = 1:height(r)
    p = r.File(k);
    if isfolder(p)
        d = dir(fullfile(p,'*.parquet'));
        for j = 1:numel(d), q = [q; parquetread(fullfile(d(j).folder,d(j).name))]; end %#ok<AGROW>
    else
        q = [q; parquetread(p)]; %#ok<AGROW>
    end
end
end
