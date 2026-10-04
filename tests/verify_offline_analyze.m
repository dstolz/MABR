function verify_offline_analyze()
% verify_offline_analyze  mabr.analysis.Session part B and Batch on synthetic files: measures, named thresholds, curation, peaks, edits, replication, batch, end to end.
%
%   Part B of mabr.analysis.Session is everything after detection -- the
%   single-trial measures, the named threshold methods, the curation that
%   must survive every re-analysis, wave picking, the edits, the Settings-
%   driven analyze() -- and mabr.analysis.Batch, the loop around it. Every
%   claim is held against files mabrtest.SyntheticABR wrote, so the truth
%   (where the response starts, where each wave is) is known.
%
%   Part A  measure: every column; on conditions without a response the RN
%           and its ± reference agree and the SNR is about 0 dB; XCorrUp is
%           NaN at each series' loudest level; the split-half K is one per
%           series
%   Part B  analyze(Settings) on the default synthetic grid (+ clicks):
%           every series "ok"; perm-descending's interval within one level
%           step of the truth and the default perm-glm within one step of it;
%           StepState filled, isStale false, a Criterion change stale for
%           thresholds only, a touched file stale for the data
%   Part C  curation survives re-analysis: accepted / manual level /
%           noresponse / excluded kept by analyze(From="detect"); an accepted
%           fit that moves loses its acceptance with "fit changed since
%           review"; a GroupBy change archives the curation and getting the
%           grouping back restores it; a TYPED GroupBy keeps stimuli apart
%           ("Frequency" is the default grouping again, and the reviewers'
%           "Level" on a Frequency axis no longer fits clicks with tones)
%   Part D  a single-level session: every series "insufficient", never
%           "no-response"
%   Part E  peaks: at 80 dB all five waves within 2 samples of the truth;
%           noiseless tracking down to threshold with no label switch; a
%           manual pick moves the picks below only after retrackSeries; an
%           absent wave survives re-analysis; BelowThreshold follows Final;
%           EdgeAffected only for windowed conditions; picksAsWindows
%   Part F  edits: setSweepsRejected re-tests and reports, editSnapshot /
%           restoreEdits round trip, setExcluded re-segments and cascades
%           (and taking the file back is bit-identical), atomicity of a
%           cancelled cascade
%   Part G  the sweep cap (64: 32 per polarity, Excess flagged, Rejected
%           untouched) and UnitOverride (a "V-unscaled" file x 0.354, "V")
%   Part H  REPLICATION (13 A7): a new Session given only the edit tables
%           (adoptEdits of a plain struct) and analyze(settings) reproduces
%           the original results bit for bit
%   Part I  SOUND CONDUCTION DELAY (13 A9): a reporting correction -- a
%           0.3 ms delay (per session, or the settings' 10 cm through
%           analyze) changes no pick, threshold or picksAsWindows window,
%           and moves every reported latency by exactly itself;
%           LatencyOffset's rule
%   Part J  Batch: statuses, a broken session "failed" while the rest
%           finish, the log written as it goes, current sessions skipped, a
%           changed setting re-run, curation carried over, CancelFcn,
%           .history pruned to 3, the summary PNG, a changed per-session
%           override re-run, an unreadable results file analysed afresh
%           (said, and kept in .history), no MABR pref written
%   Part K  review regressions: a graded threshold method on measures alone
%           (no detect()); a nearly emptied level does not set its series'
%           split-half K; a taken-back acceptance stays flagged
%   Part L  END TO END: a SyntheticABR study through Catalog, Project
%           (labels), Batch.run, Project.view (all current), aggregate,
%           Export.tables/write (every results-only table as CSV, read back,
%           no NaN/Inf text); a per-session ConductionDelayOverride moves the
%           exported latencies by exactly that amount, changes no threshold,
%           and reads "out of date" until a batch re-runs the session
%   Part M  NO NOISE: a noiseless session (polarity-following CM kept) and an
%           all-zero (dead) channel analyse with the recommended settings in
%           seconds -- every condition untested (p NaN) and flagged "zero
%           variance", its noise-referenced measures NaN, every series
%           "insufficient" for that reason, warnings naming the conditions;
%           without polarities the noiseless sweeps are tested with a raised
%           TFCE step (once a hang), and a noisy condition's test is
%           PermTest's own, bit for bit
%
%   Everything is written under one tempname folder removed on the way out;
%   figures are invisible and closed. No preference is read or written
%   (prefGuard checks), no pool is started, and the global random stream is
%   never drawn from.
%
%   Run:  >> verify_offline_analyze
%
%   See also mabr.analysis.Session, mabr.analysis.Batch,
%   mabr.analysis.SeriesThreshold, mabr.analysis.Peaks, mabrtest.SyntheticABR,
%   verify_offline_session, verify_analysis.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_analyze ==\n');
tAll  = tic;
rng0  = rng;
figs0 = findall(groot,'Type','figure');
prefs0 = offlinePrefs();
root  = string(tempname);
mkdir(root);
cleanup = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(root));

truth = mabrtest.SyntheticABR.defaults();
dt    = 1000/truth.Fs;
st    = mabr.analysis.Settings(NumPermutations=200,SplitHalfResamples=100);

% The main session: the default tone grid and a click series.
tp = tic;
fa = fullfile(root,"SUBJ-ID-9001_A");
infoA = mabrtest.SyntheticABR.writeSession(fa,truth,Stimuli=["Tone" "ClickTrain"]);
s = mabr.analysis.Session(fa,Verbose=false);
rep = s.analyze(st);
tAnalyze = toc(tp);

% =========================================================================
%  Part A -- measure
% =========================================================================
C = s.Conditions;
names = [mabr.analysis.Session.MeasureColumns "Features"];
missingCols = names(~ismember(names,string(C.Properties.VariableNames)));
assert(isempty(missingCols),'measure() did not write: %s.',strjoin(missingCols,', '));
assert(all(cellfun(@(f,r) istable(f) && height(f) == numel(r),C.Features,C.Rejected)), ...
    'Features is not one row per sweep.');
lp = s.levelParam();
quiet = false(height(C),1);
for i = 1:height(infoA.Thresholds)
    m = C.Stimulus == infoA.Thresholds.Stimulus(i) & ...
        (isnan(infoA.Thresholds.Frequency(i)) & isnan(C.Frequency) | C.Frequency == infoA.Thresholds.Frequency(i));
    quiet = quiet | (m & C.(lp) < infoA.Thresholds.FirstLevel(i));
end
ratio = C.RN(quiet)./C.RNPM(quiet);
assert(abs(median(ratio) - 1) < 0.15,'Median RN/RNPM on no-response conditions is %.3f.',median(ratio));
assert(abs(median(C.SNR(quiet))) < 1.5,'Median SNR on no-response conditions is %.2f dB.',median(C.SNR(quiet)));
sk = arrayfun(@(k) s.seriesOf(k),C.Key);
for k = unique(sk).'
    r = find(sk == k);
    [~,top] = max(C.(lp)(r));
    assert(isnan(C.XCorrUp(r(top))),'XCorrUp is not NaN at the loudest level of %s.',k);
    assert(all(isfinite(C.XCorrUp(r([1:top-1 top+1:end])))),'XCorrUp missing below the top of %s.',k);
    assert(isscalar(unique(C.SplitN(r))),'The split-half K differs within %s.',k);
end
fprintf(['  PASS Part A: measure writes every column (Features one row per sweep); no-response ' ...
    'conditions: median RN/RNPM %.3f, median SNR %+.2f dB; XCorrUp NaN at each top level; ' ...
    'one split-half K per series (%s) (analyze %.1f s)\n'], ...
    median(ratio),median(C.SNR(quiet)),mat2str(unique(C.SplitN).'),tAnalyze);

% =========================================================================
%  Part B -- analyze, named methods, staleness
% =========================================================================
tp = tic;
T = s.Thresholds;
need = ["Key","Stimulus","AcqMode","Frequency","LevelParam","Method","Metric","Type","FitTarget", ...
    "Criterion","CriterionUnit","Convention","Threshold","ThresholdRaw","Status","Censored","ThrLo", ...
    "ThrHi","CILower","CIUpper","CIMethod","NumLevels","NumUsable","NumSig","LevelStep","MinLevel", ...
    "MaxLevel","Converged","Message","Flags","Decision","ManualValue","ManualKind","Final", ...
    "FinalCensored","FinalLo","FinalHi","Note","ReviewedBy","ReviewedAt","ReviewedValue", ...
    "ReviewedMethod","Curated","IsCurated","Fit"];
assert(isequal(string(T.Properties.VariableNames),need),'Thresholds columns: %s.', ...
    strjoin(T.Properties.VariableNames,' '));
assert(height(T) == 4 && all(T.Status == "ok") && all(T.Method == "perm-glm"), ...
    'Expected 4 perm-glm series all "ok": %s.',strjoin(T.Status + "/" + T.Method,', '));
assert(rep.Status == "ok" && isequal(rep.Steps,mabr.analysis.Session.StepNames), ...
    'analyze() reported %s over [%s].',rep.Status,strjoin(rep.Steps));
% The descending rule on the same data: on the power test (the more sensitive
% statistic on these files) the interval is within one level step of the
% level the response was built to start at; on the permutation test it is
% never below the truth and perm-glm is within one step of it.
sd = st;  sd.ThresholdMethod = "power-descending";
s.analyze(sd,From="thresholds");
Tp = s.Thresholds;
sd.ThresholdMethod = "perm-descending";
s.analyze(sd,From="thresholds");
Td = s.Thresholds;
step = 10;
truthOf = @(r) infoA.Thresholds.FirstLevel(matchSeries(infoA.Thresholds,Td(r,:)));
for r = find(Td.Stimulus == "Tone").'      % per frequency (the click series is weaker)
    tr = truthOf(r);
    assert(Tp.Censored(r) == "interval" && Tp.ThrHi(r) - tr <= step && tr - Tp.ThrLo(r) <= step, ...
        '%s: power-descending (%g, %g] is not within one step of the truth %g.',Tp.Key(r), ...
        Tp.ThrLo(r),Tp.ThrHi(r),tr);
    assert(Td.Censored(r) == "interval" && Td.ThrHi(r) >= tr, ...
        '%s: perm-descending (%g, %g] detects below the truth %g.',Td.Key(r),Td.ThrLo(r),Td.ThrHi(r),tr);
    assert(abs(T.Threshold(r) - Td.Final(r)) <= step, ...
        '%s: perm-glm %.1f is more than one step from perm-descending %.1f.',T.Key(r),T.Threshold(r),Td.Final(r));
end
tone = Td.Stimulus == "Tone";
descTxt = strjoin(mabr.analysis.SeriesThreshold.formatValue(Tp.Final(tone),Tp.FinalCensored(tone),Tp.FinalLo(tone),Tp.FinalHi(tone)),", ");
permTxt = strjoin(mabr.analysis.SeriesThreshold.formatValue(Td.Final(tone),Td.FinalCensored(tone),Td.FinalLo(tone),Td.FinalHi(tone)),", ");
s.analyze(st,From="thresholds");
assert(isequaln(s.Thresholds.Threshold,T.Threshold),'Going back to perm-glm did not give the same thresholds.');
for stp = mabr.analysis.Session.StepNames
    x = s.StepState.(stp);
    assert(isstruct(x) && all(isfield(x,["At","Settings","Fingerprint"])) && x.Fingerprint == s.DataFingerprint, ...
        'StepState.%s is not filled.',stp);
end
[tf,D] = s.isStale(st);
assert(~tf && height(D) == 0,'A just-analysed session is stale: %s.',strjoin(D.Step + "." + D.Field,', '));
s2 = st;  s2.Criterion = 0.7;  s2.ThresholdMethod = "custom";
[tf,D] = s.isStale(s2);
assert(tf && all(D.Step == "thresholds") && all(ismember(["Criterion","ThresholdMethod"],D.Field)), ...
    'A Criterion change is not stale for thresholds only: %s.',strjoin(D.Step + "." + D.Field,', '));
% A touched file changes the data fingerprint (its own small session).
fz = fullfile(root,"SUBJ-ID-9001_touch");
tz = truth;  tz.Freqs = 8;  tz.Threshold = 20;  tz.Levels = [40 80];  tz.nSweeps = 16;
iz = mabrtest.SyntheticABR.writeSession(fz,tz);
sz = mabr.analysis.Session(fz,Verbose=false);
sz.analyze(st,Steps="segment");
pause(1.1);
ffn = fullfile(fz,iz.Files.FileName(1));
fidT = fopen(ffn,'r');  bytes = fread(fidT,Inf,'*uint8');  fclose(fidT);
fidT = fopen(ffn,'w');  fwrite(fidT,bytes);  fclose(fidT);     % same bytes, a new modified time
[tf,D] = sz.isStale(st);
assert(tf && any(D.Step == "data" & D.Field == "files"),'A touched file did not make the data stale.');
fprintf(['  PASS Part B: analyze: 4 perm-glm series "ok" (%s); per frequency power-descending %s within ' ...
    'one step of the truth, perm-descending %s never below it and within one step of perm-glm; ' ...
    'StepState filled, not stale, a Criterion change stale for thresholds only, a touched file ' ...
    'stale for the data (%.1f s)\n'],strjoin(compose('%.1f',T.Threshold),", "),descTxt,permTxt,toc(tp));

% =========================================================================
%  Part C -- curation survives re-analysis
% =========================================================================
tp = tic;
T = s.Thresholds;
k4 = T.Key(T.Frequency == 4);  k8 = T.Key(T.Frequency == 8);  k16 = T.Key(T.Frequency == 16);
kc = T.Key(T.Stimulus == "ClickTrain");
s.acceptFit(k4);
r8 = s.setDecision(k8,"manual",Value=30,Kind="level",Note="clear wave V at 30");
s.setDecision(k16,"noresponse");
s.setDecision(kc,"excluded");
assert(contains(r8.Text,"manual") && r8.Action == "setDecision",'setDecision report: %s.',r8.Text);
T = s.Thresholds;
assert(T.Final(T.Key == k8) == 25 && T.FinalCensored(T.Key == k8) == "interval" && ...
    isinf(T.Final(T.Key == k16)) && isnan(T.Final(T.Key == kc)) && ...
    T.Final(T.Key == k4) == T.Threshold(T.Key == k4),'Final does not follow the decisions.');
assert(~T.IsCurated(T.Key == k4) && all(T.IsCurated(T.Key ~= k4)),'IsCurated is wrong.');
s.analyze(st,From="detect");
T2 = s.Thresholds;
cc = mabr.analysis.Session.CurationColumns;
assert(isequaln(T2(:,["Key" cc "Final"]),T(:,["Key" cc "Final"])), ...
    'Curation was not carried through analyze(From="detect").');
% An accepted fit that moves: force the 4 kHz levels at and above 20 dB detected.
C = s.Conditions;
lowKeys = C.Key(C.Frequency == 4 & C.Level >= 10 & C.Level < 30);
for k = lowKeys.', s.setDetectionOverride(k,1); end
T3 = s.Thresholds;
r = T3.Key == k4;
assert(T3.Decision(r) == "" && contains(T3.Flags(r),"fit changed since review"), ...
    'A moved accepted fit kept its acceptance (Threshold %.1f, reviewed %.1f, flags "%s").', ...
    T3.Threshold(r),T3.ReviewedValue(r),T3.Flags(r));
for k = lowKeys.', s.setDetectionOverride(k,NaN); end
assert(abs(s.Thresholds.Threshold(r) - T.Threshold(r)) < 1e-9,'Clearing the overrides did not restore the fit.');
s.acceptFit(k4);
Tc = s.Thresholds;
% A different grouping archives the curation; the old one restores it.
sg = st;  sg.GroupBy = ["Stimulus","AcqMode"];
s.analyze(sg,From="thresholds");
% (The click series has no frequency, so its key is the same under both
% groupings and its curation simply stays.)
assert(height(s.Thresholds) == 2 && height(s.CurationArchive) == 3 && ...
    all(contains(s.CurationArchive.Key,"Frequency=")) && ...
    s.Thresholds.Decision(s.Thresholds.Key == kc) == "excluded" && ...
    any(contains(s.Messages.Text,"no longer match a series")), ...
    'A regrouping did not archive the 3 curated tone series (%d archived).',height(s.CurationArchive));
s.analyze(st,From="thresholds");
T4 = s.Thresholds;
assert(height(s.CurationArchive) == 0 && isequaln(T4(:,["Key" cc "Final"]),Tc(:,["Key" cc "Final"])), ...
    'The curation did not come back with the grouping.');
% A typed GroupBy keeps stimuli apart whatever it names (seriesGrouping):
% "Frequency" is then the default grouping -- the same keys, nothing
% archived -- and "Level" on a Frequency axis, which once fitted clicks and
% tones into one series per level without a word, fits none together.
sf = st;  sf.GroupBy = "Frequency";
s.analyze(sf,Steps="thresholds");
assert(isequal(s.GroupParams,["Stimulus" "AcqMode" "Frequency"]) && isequal(s.Thresholds.Key,T4.Key) && ...
    height(s.CurationArchive) == 0 && any(contains(s.Messages.Text,"Stimulus added to the GroupBy given")), ...
    'GroupBy "Frequency" did not keep clicks and tones apart (GroupParams %s).',strjoin(s.GroupParams,", "));
sl = st;  sl.GroupBy = "Level";  sl.LevelParam = "Frequency";
s.analyze(sl,Steps="thresholds");
skl = arrayfun(@(k) s.seriesOf(k),s.Conditions.Key);
mixed = arrayfun(@(k) numel(unique(s.Conditions.Stimulus(skl == k))) > 1,unique(skl));
assert(isequal(s.GroupParams,["Stimulus" "AcqMode" "Level"]) && ~any(mixed) && ...
    height(s.Thresholds) == 2*numel(truth.Levels), ...
    'GroupBy "Level" on a Frequency axis: %d series mix stimuli (GroupParams %s, %d series).', ...
    sum(mixed),strjoin(s.GroupParams,", "),height(s.Thresholds));
s.analyze(st,From="thresholds");
assert(height(s.CurationArchive) == 0 && isequaln(s.Thresholds(:,["Key" cc "Final"]),Tc(:,["Key" cc "Final"])), ...
    'The curation did not come back after the GroupBy probes.');
fprintf(['  PASS Part C: accepted / manual level (Final 25 (20-30]) / noresponse / excluded carried ' ...
    'through analyze(From="detect"); an accepted fit moved by overrides lost its acceptance ' ...
    '("fit changed since review"); a regrouping archived the 3 tone series'' curation and restored it; ' ...
    'a typed GroupBy keeps Stimulus ("Frequency" = the default keys; "Level" on a Frequency axis ' ...
    'mixes no stimuli) (%.1f s)\n'],toc(tp));

% =========================================================================
%  Part D -- a single-level session
% =========================================================================
tp = tic;
t1 = truth;  t1.Levels = 80;
f1 = fullfile(root,"SUBJ-ID-9001_single");
mabrtest.SyntheticABR.writeSession(f1,t1);
s1 = mabr.analysis.Session(f1,Verbose=false);
r1 = s1.analyze(st);
% One level cannot say where a response starts: "insufficient" -- or, when
% that one level responds, "all-respond" (left-censored at it, SeriesThreshold
% 7.2 step 3) -- and never "no-response".
T1s = s1.Thresholds;
assert(height(T1s) == 3 && all(ismember(T1s.Status,["insufficient","all-respond"])) && ...
    ~any(T1s.Status == "no-response") && all(contains(T1s.Flags,"insufficient levels")) && ...
    all(T1s.Status == "insufficient" | (T1s.FinalCensored == "left" & T1s.Final == 80)) && r1.Status == "ok", ...
    'A single-level session gave statuses %s.',strjoin(T1s.Status,', '));
fprintf(['  PASS Part D: a single-level session: 3 series, each "%s" (flag "insufficient levels"), ' ...
    'never "no-response" (%.1f s)\n'],strjoin(unique(T1s.Status),'"/"'),toc(tp));

% =========================================================================
%  Part E -- peaks
% =========================================================================
tp = tic;
P = s.Peaks;
assert(all(ismember(["Key","SeriesKey","Level","Wave","State","TroughState","PeakLatency","PeakValue", ...
    "TroughLatency","TroughValue","Baseline","AmpPT","AmpBP","AmpBT","Prominence","ProminenceRN", ...
    "Detectable","BelowThreshold","EdgeAffected","LatencyMethod","LatencySE","LatencyCILo", ...
    "LatencyCIHi","AmpPTSE","AmpPTCILo","AmpPTCIHi","BootstrapUnstable","LatencyOffset"], ...
    string(P.Properties.VariableNames))),'Peaks lacks columns.');
worst = 0;
for f = truth.Freqs
    W = mabrtest.SyntheticABR.waveTruth(80,f,infoA.Truth);
    for w = 1:height(W)
        r = P.Frequency == f & P.Level == 80 & P.Wave == W.Wave(w) & P.Stimulus == "Tone";
        assert(nnz(r) == 1 && P.State(r) == "auto",'%g kHz 80 dB wave %s not picked.',f,W.Wave(w));
        e = abs(P.PeakLatency(r) - W.PeakLatency(w))/dt;
        worst = max(worst,e);
        assert(e <= 2,'%g kHz 80 dB wave %s is %.2f samples from the truth.',f,W.Wave(w),e);
    end
end
% BelowThreshold follows Final (the 16 kHz series is "noresponse": all below).
T = s.Thresholds;
for k = T.Key.'
    q = P.SeriesKey == k;
    r = find(T.Key == k);
    want = mabr.analysis.SeriesThreshold.belowThreshold(P.Level(q),T.Final(r),T.FinalCensored(r),T.FinalLo(r));
    assert(isequal(P.BelowThreshold(q),want(:)),'BelowThreshold does not follow Final for %s.',k);
end
assert(all(P.BelowThreshold(P.SeriesKey == k16)),'A "noresponse" series has picks above threshold.');

% Noiseless: tracking from 80 dB down to threshold without a label switch.
tn = truth;  tn.NoiseSD = 0;  tn.Hum = 0;  tn.AmplitudeJitter = 0;  tn.LatencyJitter = 0;
tn.Drift = 0;  tn.ArtifactSweeps = [];  tn.FlaggedSweeps = [];  tn.nSweeps = 8;  tn.CMAmp80 = 0;
fn = fullfile(root,"SUBJ-ID-9001_quiet");
infoN = mabrtest.SyntheticABR.writeSession(fn,tn);
sn = mabr.analysis.Session(fn,Verbose=false);
sn.segment();
sn.pickPeaks();
Pn = sn.Peaks;
nChecked = 0;
for f = tn.Freqs
    thr = infoN.Thresholds.FirstLevel(infoN.Thresholds.Frequency == f);
    for L = tn.Levels(tn.Levels >= thr)
        W = mabrtest.SyntheticABR.waveTruth(L,f,infoN.Truth);
        for w = 1:height(W)
            r = Pn.Frequency == f & Pn.Level == L & Pn.Wave == W.Wave(w);
            assert(Pn.State(r) == "auto",'%g kHz %g dB wave %s lost in tracking.',f,L,W.Wave(w));
            [~,nearest] = min(abs(W.PeakLatency - Pn.PeakLatency(r)));
            assert(nearest == w && abs(Pn.PeakLatency(r) - W.PeakLatency(w)) <= dt, ...
                '%g kHz %g dB: wave %s picked at %.3f ms, truth %.3f ms (label switch).', ...
                f,L,W.Wave(w),Pn.PeakLatency(r),W.PeakLatency(w));
            nChecked = nChecked + 1;
        end
    end
end
assert(~any(Pn.EdgeAffected),'A continuous condition was flagged edge-affected.');
% A manual pick moves the levels below only once they are re-tracked.
sk8 = sn.seriesKeys();  sk8 = sk8(contains(sk8,"Frequency=8"));
k60 = sn.Conditions.Key(sn.Conditions.Frequency == 8 & sn.Conditions.Level == 60);
k50 = sn.Conditions.Key(sn.Conditions.Frequency == 8 & sn.Conditions.Level == 50);
v60 = Pn.PeakLatency(Pn.Key == k60 & Pn.Wave == "V");
v50 = Pn.PeakLatency(Pn.Key == k50 & Pn.Wave == "V");
rp = sn.setPeak(k60,"V","P",v60 - 0.3,Snap=false);
Pm = sn.Peaks;
assert(Pm.State(Pm.Key == k60 & Pm.Wave == "V") == "manual" && ...
    abs(Pm.PeakLatency(Pm.Key == k60 & Pm.Wave == "V") - (v60 - 0.3)) < 1e-12 && ...
    Pm.PeakLatency(Pm.Key == k50 & Pm.Wave == "V") == v50 && contains(rp.Text,"V peak"), ...
    'setPeak did not place the manual pick, or moved the level below.');
sn.retrackSeries(sk8,"V",60);
Pm = sn.Peaks;
assert(~isequaln(Pm.PeakLatency(Pm.Key == k50 & Pm.Wave == "V"),v50) && ...
    Pm.State(Pm.Key == k60 & Pm.Wave == "V") == "manual", ...
    'retrackSeries did not re-track wave V below the manual pick.');
sn.clearPeak(k60,"V","P");
sn.retrackSeries(sk8,"V",60);
Pm = sn.Peaks;
assert(abs(Pm.PeakLatency(Pm.Key == k50 & Pm.Wave == "V") - v50) < 1e-12,'Clearing the pick and re-tracking did not restore wave V.');
% An absent wave survives a re-pick.
k70 = sn.Conditions.Key(sn.Conditions.Frequency == 8 & sn.Conditions.Level == 70);
sn.setPeakAbsent(k70,"II",true);
assert(sn.Peaks.State(sn.Peaks.Key == k70 & sn.Peaks.Wave == "II") == "absent",'setPeakAbsent did not mark wave II.');
sn.pickPeaks();
assert(sn.Peaks.State(sn.Peaks.Key == k70 & sn.Peaks.Wave == "II") == "absent", ...
    'An absent wave did not survive pickPeaks().');
sn.setPeakAbsent(k70,"II",false);
% picksAsWindows: the loudest picks at the reference frequency (in the
% recording's time, like the windows).
Wp = sn.picksAsWindows(sk8);
W80 = mabrtest.SyntheticABR.waveTruth(80,8,infoN.Truth);
shift = 0.15*log2(16/8);
assert(all(abs([Wp.Expected] - (W80.PeakLatency.' - shift)) <= dt) && all([Wp.Stimulus] == "Tone") && ...
    all(abs([Wp.TMax] - [Wp.TMin] - 1) < 1e-12),'picksAsWindows is not the loudest picks less the octave shift.');
% EdgeAffected only for windowed conditions.
tb = truth;  tb.Freqs = 8;  tb.Threshold = 20;  tb.Levels = [60 80];  tb.nSweeps = 32;
fb = fullfile(root,"SUBJ-ID-9001_both");
mabrtest.SyntheticABR.writeSession(fb,tb,Layout="both");
sb = mabr.analysis.Session(fb,Verbose=false);
sb.segment();
sb.pickPeaks(EdgeMs=2);
Pb = sb.Peaks;
win = ismember(Pb.Key,sb.Conditions.Key(sb.Conditions.Processing == "windowed"));
assert(any(Pb.EdgeAffected(win)) && ~any(Pb.EdgeAffected(~win)), ...
    'EdgeAffected is not confined to windowed conditions.');
fprintf(['  PASS Part E: 80 dB waves I-V within %.2f samples of the truth; noiseless tracking of %d ' ...
    'picks down to threshold within a sample, no label switch; a manual pick moves the level ' ...
    'below only after retrackSeries; an absent wave survives pickPeaks; BelowThreshold follows ' ...
    'Final; picksAsWindows; EdgeAffected only windowed (%.1f s)\n'],worst,nChecked,toc(tp));

% =========================================================================
%  Part F -- edits, undo, files
% =========================================================================
tp = tic;
snap0 = s.editSnapshot();
C0 = s.Conditions;  T0 = s.Thresholds;  P0 = s.Peaks;
k = C0.Key(C0.Frequency == 8 & C0.Level == 30);
r = s.rowOf(k);
cols = find(~C0.Rejected{r},70);
rr = s.setSweepsRejected(k,cols,true);
C1 = s.Conditions;
assert(C1.nClean(r) == C0.nClean(r) - 70 && C1.p(r) ~= C0.p(r) && contains(rr.Text,"Re-tested") && ...
    all(C1.RejectReason{r}(cols) == 3),'setSweepsRejected did not re-test (%s).',rr.Text);
assert(isequaln(C1.p(C1.Key ~= k),C0.p(C0.Key ~= k)),'setSweepsRejected re-tested other conditions.');
rs = s.restoreEdits(snap0);
assert(isequaln(s.Conditions.p,C0.p) && isequaln(s.Conditions.Rejected,C0.Rejected) && ...
    isequaln(s.Thresholds(:,["Key" cc "Final" "Threshold"]),T0(:,["Key" cc "Final" "Threshold"])) && ...
    isequaln(s.Peaks,P0) && height(s.ManualRejections) == 0 && rs.Action == "restoreEdits", ...
    'restoreEdits did not put the session back.');
% A cancelled cascade leaves everything as it was.
before = snapshotOf(s);
s.ProgressFcn = @(m,c,t) cancelAt(c,1);
id = "";
try
    s.setSweepsRejected(k,cols,true);
catch ME
    id = string(ME.identifier);
end
s.ProgressFcn = [];
assert(id == "mabr:analysis:cancelled" && isequaln(snapshotOf(s),before), ...
    'A cancelled setSweepsRejected changed the session (%s).',id);
% Excluding the only file of a condition removes it and re-fits its series;
% taking it back is bit-identical.
fid = s.Files.FileId(s.Conditions.SweepFile{r}(1));
nC = s.NumConditions;
re = s.setExcluded(fid,true);
assert(s.NumConditions == nC - 1 && ~ismember(k,s.Conditions.Key) && ismember(fid,s.Exclude) && ...
    ~s.Files.Include(s.Files.FileId == fid) && contains(re.Text,"re-segmented"), ...
    'setExcluded did not remove the condition.');
assert(s.Thresholds.NumLevels(s.Thresholds.Key == k8) == 8,'The series was not re-estimated without the level.');
[stale,D] = s.isStale(st);
assert(~stale,'setExcluded left the session stale: %s.',strjoin(D.Step + "." + D.Field,', '));
s.setExcluded(fid,false);
assert(isequaln(s.Conditions.p,C0.p) && isequaln(s.Conditions.Key,C0.Key) && ...
    isequaln(s.Thresholds.Threshold,T0.Threshold),'Taking the file back is not bit-identical.');
% ... and undoing an exclusion is the same thing.
snapX = s.editSnapshot();
s.setExcluded(fid,true);
s.restoreEdits(snapX);
assert(isempty(s.Exclude) && isequaln(s.Conditions.p,C0.p) && isequaln(s.Conditions.Key,C0.Key) && ...
    isequaln(s.Thresholds.Threshold,T0.Threshold) && isequaln(s.Peaks,P0), ...
    'restoreEdits did not undo a file exclusion.');
fprintf(['  PASS Part F: setSweepsRejected re-tests one condition ("%s"); restoreEdits puts it back; ' ...
    'a cancelled cascade changes nothing; setExcluded removes the condition and re-fits its ' ...
    'series, taking it back is bit-identical (%.1f s)\n'],extractBefore(rr.Text + ";",";"),toc(tp));

% =========================================================================
%  Part G -- the sweep cap, UnitOverride
% =========================================================================
tp = tic;
sc = mabr.analysis.Session(fa,Verbose=false);
sc.analyze(st,Steps=["segment","reject"]);
R0 = sc.Conditions.Rejected;
sm = st;  sm.MaxSweepsPerCondition = 64;
sc.analyze(sm,Steps=["segment","reject"]);
Cc = sc.Conditions;
assert(all(Cc.nClean == 64 & Cc.nPos == 32 & Cc.nNeg == 32),'The cap did not keep 32 clean sweeps per polarity.');
assert(isequal(Cc.Rejected,R0) && all(cellfun(@(e,j) ~any(e & j),Cc.Excess,Cc.Rejected)) && ...
    all(cellfun(@sum,Cc.Excess) > 0),'The cap touched Rejected, or marked a rejected sweep Excess.');
% A "V-unscaled" file (gain, no InputFullScale) times 0.354 with the override.
fu = fullfile(root,"SUBJ-ID-9001_units");
tu = truth;  tu.Freqs = 8;  tu.Threshold = 20;  tu.Levels = 80;  tu.nSweeps = 16;
iu = mabrtest.SyntheticABR.writeSession(fu,tu);
ffn = fullfile(fu,iu.Files.FileName(1));
L = load(ffn,'-mat');  ABR_Data = L.ABR_Data;
ABR_Data.ADC = rmfield(ABR_Data.ADC,'InputFullScale');
save(ffn,'ABR_Data','-v6');
u0 = mabr.analysis.Session(fu,Verbose=false);  u0.segment();
u1 = mabr.analysis.Session(fu,Verbose=false,UnitOverride=struct('InputFullScale',0.354,'AmplifierGain',NaN));
u1.segment();
X0 = u0.sweeps(1);  X1 = u1.sweeps(1);
assert(u0.Units == "V-unscaled" && u1.Units == "V" && u1.Conditions.Units == "V", ...
    'Units: %s without and %s with the override.',u0.Units,u1.Units);
assert(max(abs(X1(:) - 0.354*X0(:))) <= 1e-12*max(abs(X0(:))),'The override did not scale by 0.354.');
fprintf('  PASS Part G: MaxSweepsPerCondition 64 keeps 32 + 32, Excess flagged, Rejected untouched; "V-unscaled" x 0.354 -> "V" (%.1f s)\n',toc(tp));

% =========================================================================
%  Part H -- replication from the edit tables alone (13 A7)
% =========================================================================
tp = tic;
% Edits of every kind on the main session.
C = s.Conditions;
kr = C.Key(C.Frequency == 4 & C.Level == 80);
s.setSweepsRejected(kr,find(~C.Rejected{s.rowOf(kr)},12),true);
s.setSweepsRejected(kr,find(C.RejectReason{s.rowOf(kr)} == 1,1),false);   % restore a rig flag
ko = C.Key(C.Frequency == 16 & C.Level == 30);
s.setDetectionOverride(ko,1);
P = s.Peaks;
lowest = @(fk) C.Key(C.Frequency == fk & C.Stimulus == "Tone" & C.Level == min(C.Level(C.Frequency == fk & C.Stimulus == "Tone")));
kl = lowest(4);
lat = P.PeakLatency(P.Key == C.Key(C.Frequency == 4 & C.Level == 80) & P.Wave == "III");
s.setPeak(kl,"III","P",lat + 0.4,Snap=false);
s.setPeakAbsent(lowest(8),"IV",true);
s.setThresholdNote(k4,"looked fine");
s.setDecision(k8,"manual",Value=32.5,Kind="value");
orig = struct('T',s.Thresholds,'C',s.Conditions,'P',s.Peaks);
E = struct('ManualRejections',s.ManualRejections,'DetectionOverrides',s.DetectionOverrides, ...
    'PeakOverrides',s.PeakOverrides,'Exclude',s.Exclude, ...
    'Thresholds',s.Thresholds(:,["Key" cc]),'CurationArchive',s.CurationArchive, ...
    'EditLog',s.EditLog);
rpl = mabr.analysis.Session(fa,Verbose=false);
ra = rpl.adoptEdits(E);
rpl.analyze(st);
Tr = rpl.Thresholds;  Cr = rpl.Conditions;  Pr = rpl.Peaks;
assert(contains(ra.Text,"manual rejection"),'adoptEdits report: %s.',ra.Text);
for v = ["Key","Threshold","ThrLo","ThrHi","Status","Censored","Final","FinalCensored","FinalLo", ...
        "FinalHi","Decision","ManualValue","Note","Flags","CILower","CIUpper"]
    assert(isequaln(Tr.(v),orig.T.(v)),'Replicated Thresholds.%s differs.',v);
end
for v = ["Key","p","isSig","Detected","nClean","Rejected","RejectReason","Excess","RN","SNR","SplitR","XCorrUp"]
    assert(isequaln(Cr.(v),orig.C.(v)),'Replicated Conditions.%s differs.',v);
end
for v = ["Key","Wave","State","PeakLatency","PeakValue","TroughLatency","TroughValue","AmpPT", ...
        "Detectable","BelowThreshold","LatencyOffset"]
    assert(isequaln(Pr.(v),orig.P.(v)),'Replicated Peaks.%s differs.',v);
end
fprintf(['  PASS Part H: a new Session given only the edit tables (adoptEdits of a plain struct: ' ...
    '%d manual rejections, %d detection override, %d peak overrides, curation) and analyze() ' ...
    'reproduces Thresholds, Conditions and Peaks bit for bit (%.1f s)\n'], ...
    height(E.ManualRejections),height(E.DetectionOverrides),height(E.PeakOverrides),toc(tp));

% =========================================================================
%  Part I -- sound conduction delay (13 A9): reported, never searched
% =========================================================================
% The delay is a reporting correction. The wave windows are in the
% recording's own time (they were drawn up on recordings), so a delay must
% change no pick -- with windows moved by it, a peak near the edge of two
% overlapping windows changed its label when the delay was switched on --
% and every reported latency moves by exactly the delay.
tp = tic;
td = tn;  td.Freqs = 16;  td.Threshold = 40;  td.Levels = 40:10:80;
fu0 = fullfile(root,"SUBJ-ID-9001_nodelay");
mabrtest.SyntheticABR.writeSession(fu0,td);
a0 = mabr.analysis.Session(fu0,Verbose=false);  a0.segment();  a0.pickPeaks();
a1 = mabr.analysis.Session(fu0,Verbose=false);  a1.ConductionDelayOverride = 0.3;
a1.segment();  a1.pickPeaks();
assert(a1.LatencyOffset == 0.3 && all(a1.Peaks.LatencyOffset == 0.3) && all(a0.Peaks.LatencyOffset == 0), ...
    'LatencyOffset / Peaks.LatencyOffset are not the conduction delay.');
pc = ["Key","Wave","State","PeakLatency","PeakValue","TroughState","TroughLatency","TroughValue", ...
    "AmpPT","Prominence","Detectable","BelowThreshold"];
assert(isequaln(a0.Peaks(:,pc),a1.Peaks(:,pc)),'A 0.3 ms conduction delay changed a pick.');
ok = ismember(a0.Peaks.State,["auto","manual"]);
dl = mabr.analysis.Peaks.reported(a1.Peaks.PeakLatency(ok),a1.Peaks.LatencyOffset(ok)) - a0.Peaks.PeakLatency(ok);
assert(any(ok) && max(abs(dl + 0.3)) < 1e-12, ...
    'Reported latencies did not move by exactly the delay (by %.4f to %.4f ms).',min(dl),max(dl));
w0 = a0.picksAsWindows(a0.seriesKeys());  w1 = a1.picksAsWindows(a1.seriesKeys());
assert(isequal(w0,w1),'picksAsWindows moved with the conduction delay.');
% The same through analyze(), on noisy data: the settings' 10 cm against
% none -- every threshold and pick the same, every latency reported 10/343
% ms earlier.
tq = truth;  tq.Freqs = 16;  tq.Threshold = 40;  tq.Levels = [40 60 80];  tq.nSweeps = 48;
fq = fullfile(root,"SUBJ-ID-9001_delaynoisy");
mabrtest.SyntheticABR.writeSession(fq,tq);
sd0 = mabr.analysis.Settings(NumPermutations=50,SplitHalfResamples=20,MinSweeps=20,MinPerPolarity=10);
sd1 = sd0;  sd1.ConductionDelayMode = "distance";  sd1.SpeakerDistance = 10;
b0 = mabr.analysis.Session(fq,Verbose=false);  b0.analyze(sd0);
b1 = mabr.analysis.Session(fq,Verbose=false);  b1.analyze(sd1);
tc = ["Key","Threshold","Status","Censored","ThrLo","ThrHi","Final","NumSig"];
assert(isequaln(b0.Thresholds(:,tc),b1.Thresholds(:,tc)) && isequaln(b0.Peaks(:,pc),b1.Peaks(:,pc)), ...
    'Settings with a 10 cm conduction delay changed a threshold or a pick.');
okb = ismember(b0.Peaks.State,["auto","manual"]);
db = mabr.analysis.Peaks.reported(b1.Peaks.PeakLatency(okb),b1.Peaks.LatencyOffset(okb)) - ...
    mabr.analysis.Peaks.reported(b0.Peaks.PeakLatency(okb),b0.Peaks.LatencyOffset(okb));
assert(any(okb) && max(abs(db + 10*10/343)) < 1e-12,'A 10 cm delay did not move every latency by 0.29 ms.');
% The rule: a session's own value, else the settings'; the two parts add.
a2 = mabr.analysis.Session("",Parse=false,Verbose=false);
assert(a2.LatencyOffset == 0 && isnan(a2.TimeOffset) && isnan(a2.ConductionDelayOverride), ...
    'A fresh session''s latency offset is not 0 with no overrides.');
sx = mabr.analysis.Settings(ConductionDelayMode="distance",SpeakerDistance=10,TimeOffset=0.05);
a3 = mabr.analysis.Session(fu0,Verbose=false);
a3.analyze(sx,Steps="segment");
assert(abs(a3.LatencyOffset - (10*10/343 + 0.05)) < 1e-12,'Settings latencyOffset() not used.');
a3.TimeOffset = 0.1;
assert(abs(a3.LatencyOffset - (10*10/343 + 0.1)) < 1e-12,'TimeOffset did not replace the settings'' TimeOffset.');
a3.ConductionDelayOverride = 0.2;
assert(abs(a3.LatencyOffset - 0.3) < 1e-12,'ConductionDelayOverride did not replace the settings'' delay.');
fprintf(['  PASS Part I: a 0.3 ms ConductionDelayOverride (and the settings'' 10 cm through analyze) ' ...
    'changes no pick, threshold or picksAsWindows window and moves %d reported latencies by exactly ' ...
    'the delay (Peaks.LatencyOffset 0.3); LatencyOffset = (override or settings delay) + ' ...
    '(TimeOffset or settings) (%.1f s)\n'],sum(ok),toc(tp));

% =========================================================================
%  Part J -- Batch
% =========================================================================
tp = tic;
tsy = truth;  tsy.Freqs = 8;  tsy.Threshold = 20;  tsy.Levels = 20:20:80;  tsy.nSweeps = 48;
study = fullfile(root,"study");
infoS = mabrtest.SyntheticABR.writeStudy(study,tsy,Mixed=false);
broken = fullfile(study,"SUBJ-ID-9002","SUBJ-ID-9002_broken");
mkdir(broken);
fidB = fopen(fullfile(broken,"SUBJ-ID-9002_Frequency-8kHz_Level-20dB_261001T150000.abr"),'w');
fprintf(fidB,'not a MAT-file');  fclose(fidB);
rfold = fullfile(root,"results");  cache = fullfile(root,"cache");
sb1 = mabr.analysis.Settings(NumPermutations=50,SplitHalfResamples=20,MinSweeps=20,MinPerPolarity=10, ...
    SplitHalfMinPerPolarity=5);
logFile = fullfile(root,"batch.csv");
seen = containers.Map('KeyType','char','ValueType','any');
seen('lines') = zeros(0,2);
sink = @(m,c,t) logLines(seen,m,c,logFile);
T1 = mabr.analysis.Batch.runFolder(study,sb1,ResultsFolder=rfold,CacheFolder=cache,LogFile=logFile, ...
    ProgressFcn=sink);
nS = height(infoS.Sessions);
assert(height(T1) == nS + 1 && sum(T1.Status == "ok") == nS && sum(T1.Status == "failed") == 1 && ...
    T1.Status(contains(T1.Key,"broken")) == "failed", ...
    'Batch statuses: %s.',strjoin(T1.Key + "=" + T1.Status,', '));
assert(all(isfile(T1.ResultsFile(T1.Status == "ok"))) && ~isfile(T1.ResultsFile(T1.Status == "failed")), ...
    'Results files were not written for exactly the sessions that finished.');
L = seen('lines');
assert(~isempty(L) && all(L(:,2) == L(:,1)),'The log did not hold one line per finished session as the batch went.');
lg = readtable(logFile,'TextType','string','Delimiter',',');
assert(height(lg) == nS + 1 && isequal(string(lg.Properties.VariableNames),mabr.analysis.Batch.LogColumns), ...
    'The log CSV has %d rows.',height(lg));
T2 = mabr.analysis.Batch.runFolder(study,sb1,ResultsFolder=rfold,CacheFolder=cache,LogFile=logFile);
assert(all(T2.Status(T2.Key ~= T1.Key(T1.Status == "failed")) == "skipped") && ...
    all(contains(T2.Message(T2.Status == "skipped"),"up to date")),'Current sessions were not skipped.');
% Curation in a results file is carried over; a changed setting re-runs.
f0 = T1.ResultsFile(find(T1.Status == "ok",1));
r0 = mabr.analysis.Session.fromResults(f0,Verbose=false);
kk = r0.Thresholds.Key(1);
r0.setDecision(kk,"noresponse",Note="batch carry");
r0.saveResults(f0,IncludeSweeps=false);
sb2 = sb1;  sb2.ThresholdConvention = "lowest_level";
k3 = T1.Key(T1.Status == "ok");  k3 = k3(1:2);   % f0's session and one more (time)
T3 = mabr.analysis.Batch.runFolder(study,sb2,ResultsFolder=rfold,CacheFolder=cache,LogFile=logFile,Keys=k3);
assert(height(T3) == 2 && all(T3.Status == "ok"),'A changed setting did not re-run the sessions asked for.');
Lr = load(f0,'Thresholds');
assert(Lr.Thresholds.Decision(Lr.Thresholds.Key == kk) == "noresponse" && ...
    Lr.Thresholds.Note(Lr.Thresholds.Key == kk) == "batch carry",'The curation was not carried over.');
% CancelFcn stops after the first session.
T4 = mabr.analysis.Batch.runFolder(study,sb2,ResultsFolder=rfold,CacheFolder=cache,LogFile=logFile, ...
    SkipCurrent=false,CancelFcn=@() true);
assert(T4.Status(1) ~= "cancelled" && all(T4.Status(2:end) == "cancelled"),'CancelFcn did not stop after one session.');
k1 = T1.Key(find(T1.Status == "ok",1));
% A per-session override (a project's TimeOffset/ConductionDelay/UnitOverride)
% is not in the step settings or the fingerprint: changing it must still re-run.
cz = mabr.analysis.Catalog(study,ResultsFolder=rfold,CacheFolder=cache);
cz.scan();
it = table(k1,{cz.Sessions.Path(cz.Sessions.Key == k1)},cz.resultsFile(k1), ...
    'VariableNames',{'Key','Paths','ResultsFile'});
Ta = mabr.analysis.Batch.run(it,sb2,ResultsFolder=rfold,LogFile=logFile);
it.TimeOffset = 0.2;
Tb = mabr.analysis.Batch.run(it,sb2,ResultsFolder=rfold,LogFile=logFile);
Tc = mabr.analysis.Batch.run(it,sb2,ResultsFolder=rfold,LogFile=logFile);
Lo = load(it.ResultsFile,'Summary');
assert(Ta.Status == "skipped" && Tb.Status == "ok" && Tc.Status == "skipped" && ...
    Lo.Summary.TimeOffset == 0.2,'A changed per-session override was not re-run (%s, %s, %s).', ...
    Ta.Status,Tb.Status,Tc.Status);
% .history keeps the newest 3 (T3, T4 and Tb made 3 copies of k1's
% results; this run makes the 4th); the summary figure.
mabr.analysis.Batch.runFolder(study,sb2,ResultsFolder=rfold,CacheFolder=cache,LogFile=logFile, ...
    SkipCurrent=false,Keys=k1,SummaryFigure=true);
hist = dir(fullfile(rfold,".history","*.mat"));
flat = regexprep(char(k1),'[\\/]','__');
nh = sum(startsWith({hist.name},[flat '_']));
assert(nh == 3,'.history holds %d copies of %s.',nh,k1);
assert(isfile(fullfile(rfold,"figures",[flat '.png'])),'SummaryFigure wrote no PNG.');
% An existing results file that cannot be read does not fail its session at
% every batch from then on: the session is analysed afresh, its message says
% the edits were not carried over, and the unreadable file is kept in
% .history (the newest copy there).
rk1 = it.ResultsFile;
fidC = fopen(rk1,'w');  fprintf(fidC,'not a MAT-file');  fclose(fidC);
Tz = mabr.analysis.Batch.run(it,sb2,ResultsFolder=rfold,LogFile=logFile);
Lz = load(rk1,'Version');
hz = dir(fullfile(rfold,".history",[flat '_*.mat']));
[~,oz] = sort([hz.datenum],'descend');
assert(Tz.Status == "ok" && contains(Tz.Message,"could not be read") && Lz.Version == 2 && ...
    ~isempty(hz) && hz(oz(1)).bytes == numel('not a MAT-file'), ...
    'An unreadable results file: %s "%s".',Tz.Status,Tz.Message);
assert(isequaln(offlinePrefs(),prefs0),'A batch wrote a MABR preference.');
fprintf(['  PASS Part J: Batch over %d sessions + 1 broken: %d ok, the broken one "failed"; the log ' ...
    'gained each line as its session ended; current sessions skipped; a changed setting re-ran ' ...
    'its sessions with curation carried over; CancelFcn stopped after one; .history keeps 3; summary ' ...
    'PNG; a changed per-session override re-runs; an unreadable results file is analysed afresh, said, ' ...
    'and kept in .history; no pref written (%.1f s)\n'],nS,nS,toc(tp));

% =========================================================================
%  Part K -- review regressions
% =========================================================================
tp = tic;
fk = fullfile(root,"SUBJ-ID-9001_K");
tk = truth;  tk.Freqs = 8;  tk.Threshold = 40;  tk.Levels = [20 40 60 80];  tk.nSweeps = 120;
mabrtest.SyntheticABR.writeSession(fk,tk);
sk2 = mabr.analysis.Session(fk,Verbose=false);
sk2.segment();
sk2.measure(NumPermutations=50,SplitHalfResamples=20);
% A graded method on the measures alone (no detect()): no error, and the
% method's verdict lands in Detected.
Tk = sk2.estimateThresholds(Method="power-descending");
assert(height(Tk) == 1 && all(ismember(["Detected","DetectedAuto"],string(sk2.Conditions.Properties.VariableNames))), ...
    'A graded method without detect() did not run, or wrote no Detected column.');
% One level reduced to a handful of sweeps does not take the split-half r
% away from the rest of its series.
Ck = sk2.Conditions;
lo = find(Ck.Level == 20);  hi = find(Ck.Level ~= 20);
K0 = Ck.SplitN(hi);
assert(all(isfinite(Ck.SplitR(hi))) && all(K0 >= 25),'No split-half r to begin with.');
n20 = numel(Ck.Rejected{lo});
sk2.setSweepsRejected(Ck.Key(lo),1:n20-6,true);
Ck = sk2.Conditions;
assert(isnan(Ck.SplitR(lo)) && all(isfinite(Ck.SplitR(hi))) && isequal(Ck.SplitN(hi),K0), ...
    'A level with 6 clean sweeps changed its series'' split-half K (%s -> %s).',mat2str(K0.'),mat2str(Ck.SplitN(hi).'));
% A review record without a decision (an acceptance a re-fit took back) keeps
% its "fit changed since review" flag even when the value did not move.
E = struct('Thresholds',table(Tk.Key,"","rev",Tk.Threshold,"power-descending", ...
    'VariableNames',{'Key','Decision','ReviewedBy','ReviewedValue','ReviewedMethod'}));
sk2.adoptEdits(E);
assert(contains(sk2.Thresholds.Flags,"fit changed since review"), ...
    'A taken-back acceptance lost its flag: "%s".',sk2.Thresholds.Flags);
fprintf(['  PASS Part K: a graded method runs on measures alone and writes Detected; a level with 6 ' ...
    'clean sweeps leaves its series'' split-half K (%s); a taken-back acceptance stays flagged ' ...
    '(%.1f s)\n'],mat2str(unique(K0).'),toc(tp));

% =========================================================================
%  Part L -- END TO END: study -> catalog -> project -> batch -> view ->
%            aggregate -> export -> CSV; a per-session conduction delay
% =========================================================================
tp = tic;
te = truth;  te.Freqs = 8;  te.Threshold = 20;  te.Levels = [20 40 60 80];  te.nSweeps = 48;
studyE = fullfile(root,"studyE");
infoE = mabrtest.SyntheticABR.writeStudy(studyE,te,Mixed=false);
cE = mabr.analysis.Catalog(studyE,ResultsFolder=fullfile(root,"resultsE"),CacheFolder=fullfile(root,"cacheE"));
cE.scan();
keysE = cE.Sessions.Key;
assert(numel(keysE) == height(infoE.Sessions) && numel(keysE) == 4, ...
    'The catalog found %d sessions in a 4-session study.',numel(keysE));
pE = mabr.analysis.Project.open(cE.ResultsFolder);
pE.ensureSessions(cE);
subjE = cE.Sessions.Subject;
pE.label(keysE(subjE == "SUBJ-ID-9001"),"Group","Exposed");
pE.label(keysE(subjE == "SUBJ-ID-9002"),"Group","Sham");
pE.addColumn("Weight_g","session","number");
pE.label(keysE(1),"Weight_g",62.5);
sbE = mabr.analysis.Settings(NumPermutations=50,SplitHalfResamples=20,MinSweeps=20,MinPerPolarity=10, ...
    SplitHalfMinPerPolarity=5);
TE = mabr.analysis.Batch.run(pE.batchItems(keysE,cE),sbE,Project=pE,ResultsFolder=cE.ResultsFolder, ...
    LogFile=fullfile(root,"batchE.csv"));
assert(all(TE.Status == "ok"),'End-to-end batch statuses: %s.',strjoin(TE.Key + "=" + TE.Status,', '));
VE = pE.view(cE,sbE);
VE = VE(ismember(VE.Key,keysE),:);
assert(height(VE) == 4 && all(VE.Status == "current") && all(VE.NumSeries == 1) && ...
    all(~isnat(pE.Sessions.LastRun(ismember(pE.Sessions.Key,keysE)))), ...
    'Project.view after the batch: %s.',strjoin(VE.Key + "=" + VE.StatusText,', '));
AE = pE.aggregate(keysE,cE);
assert(height(AE.Thresholds) == 4 && all(AE.Thresholds.UsedInStudy) && height(AE.Peaks) > 0 && ...
    isequal(sort(unique(string(AE.Thresholds.Group))),["Exposed";"Sham"]) && height(AE.Duplicates) == 0, ...
    'Project.aggregate: %d threshold rows, groups %s.',height(AE.Thresholds), ...
    strjoin(unique(string(AE.Thresholds.Group)),'/'));
% Every results-only table through Export.tables and write(), as CSV, read back.
tabsE = [mabr.analysis.Export.DefaultTables "trials"];
TT = mabr.analysis.Export.tables(pE.exportItems(keysE,cE),Tables=tabsE);
outE = fullfile(root,"exportE");
FE = mabr.analysis.Export.write(TT,outE,Formats="csv");
FE = FE(FE.File ~= "",:);
need = ["sessions","subjects","conditions","thresholds","peaks","peak_measures","io_slopes", ...
    "waveforms","trials"];
assert(all(ismember(need,FE.Table)),'Export.write left out: %s.',strjoin(setdiff(need,FE.Table),', '));
for i = 1:height(FE)
    txt = fileread(FE.File(i));
    bad = regexp(txt,'(^|,)"?(NaN|-?Inf)"?(?=,|\r?$)','match','once','lineanchors');
    assert(isempty(bad),'%s holds "%s" text.',FE.File(i),bad);
    rt = readtable(FE.File(i),'TextType','string','Delimiter',',','VariableNamingRule','preserve');
    want = TT.(FE.Table(i));
    assert(height(rt) == height(want) && isequal(string(rt.Properties.VariableNames), ...
        string(want.Properties.VariableNames)),'%s does not read back as written (%d of %d rows).', ...
        FE.Table(i),height(rt),height(want));
end
% A per-session conduction delay set in the project: the exported latencies
% move by exactly that amount at once (Labels.ConductionDelay), nothing else
% does, and the session reads "out of date" until a batch re-runs it -- which
% leaves every threshold as it was.
kD = keysE(1);  dly = 0.25;
pE.label(kD,"ConductionDelayOverride",dly);
TT2 = mabr.analysis.Export.tables(pE.exportItems(keysE,cE),Tables=["thresholds","peaks"]);
P1 = TT.peaks;  P2 = TT2.peaks;
inD = P1.session_id == kD;
assert(any(inD) && isequal(P1.session_id,P2.session_id) && isequaln(P1.lat_peak_raw_ms,P2.lat_peak_raw_ms), ...
    'The peaks rows changed with the override.');
okD = inD & isfinite(P1.lat_peak_ms);
assert(any(okD) && max(abs(P1.lat_peak_ms(okD) - P2.lat_peak_ms(okD) - dly)) < 1e-12 && ...
    all(P2.conduction_delay_ms(inD) == dly) && all(P1.conduction_delay_ms(inD) == 0) && ...
    isequaln(P1(~inD,:),P2(~inD,:)), ...
    'A %.2f ms conduction delay did not move %s''s latencies by exactly that.',dly,kD);
assert(isequaln(TT.thresholds,TT2.thresholds),'A conduction delay changed the exported thresholds.');
VD = pE.view(cE,sbE);
assert(VD.Status(VD.Key == kD) == "stale" && contains(VD.StatusText(VD.Key == kD),"overrides") && ...
    all(VD.Status(ismember(VD.Key,keysE) & VD.Key ~= kD) == "current"), ...
    'A changed override did not make only its session out of date (%s).',VD.StatusText(VD.Key == kD));
rfD = cE.resultsFile(kD);
Th0 = load(rfD,'Thresholds');
TD = mabr.analysis.Batch.run(pE.batchItems(keysE,cE),sbE,Project=pE,ResultsFolder=cE.ResultsFolder, ...
    LogFile=fullfile(root,"batchE.csv"));
assert(TD.Status(TD.Key == kD) == "ok" && all(TD.Status(TD.Key ~= kD) == "skipped"), ...
    'After the override the batch ran: %s.',strjoin(TD.Key + "=" + TD.Status,', '));
Th1 = load(rfD,'Thresholds','Peaks');
fc = ["Threshold","Final","FinalCensored","FinalLo","FinalHi","Status"];
fc = fc(ismember(fc,string(Th0.Thresholds.Properties.VariableNames)));
assert(isequaln(Th0.Thresholds(:,fc),Th1.Thresholds(:,fc)),'Re-analysing with a conduction delay changed a threshold.');
assert(height(Th1.Peaks) > 0 && all(Th1.Peaks.LatencyOffset == dly), ...
    'The re-analysed peaks did not record the %.2f ms offset.',dly);
VA = pE.view(cE,sbE);
assert(all(VA.Status(ismember(VA.Key,keysE)) == "current"),'Sessions not current after the re-run.');
fprintf(['  PASS Part L: end to end -- writeStudy -> Catalog (%d sessions) -> Project labels -> ' ...
    'Batch.run (all ok) -> view all current -> aggregate (%d series, 2 groups) -> Export %d CSVs ' ...
    'read back, no NaN/Inf text; a %.2f ms ConductionDelayOverride moves %s''s latencies by exactly ' ...
    'that, changes no threshold, reads "out of date" until a batch re-runs it (%.1f s)\n'], ...
    numel(keysE),height(AE.Thresholds),height(FE),dly,kD,toc(tp));

% =========================================================================
%  Part M -- no noise: a noiseless session and a dead channel
% =========================================================================
% Sweeps that do not vary have nothing to test a response against, and a
% sign flip lining them up has an unbounded t: a noiseless 8-sweep session
% once kept TFCE integrating for over 13 minutes. Both kinds now finish in
% seconds with the recommended settings (TFCE, 1000 permutations), untested
% and flagged, and every series says why it has no threshold.
tp = tic;
assert(~any(contains(s.Conditions.Flags,"zero variance")),'A noisy condition was flagged zero variance.');
tq = truth;  tq.Freqs = 8;  tq.Threshold = 20;  tq.Levels = 0:20:80;  tq.nSweeps = 8;
tq.NoiseSD = 0;  tq.Hum = 0;  tq.AmplitudeJitter = 0;  tq.LatencyJitter = 0;  tq.Drift = 0;
tq.ArtifactSweeps = [];  tq.FlaggedSweeps = [];         % the CM stays: it follows polarity
fq = fullfile(root,"SUBJ-ID-9001_noiseless");
mabrtest.SyntheticABR.writeSession(fq,tq,Stimuli=["Tone" "ClickTrain"]);
fd = fullfile(root,"SUBJ-ID-9001_dead");
infoD = mabrtest.SyntheticABR.writeSession(fd,tq,Stimuli=["Tone" "ClickTrain"]);
for k = 1:height(infoD.Files)
    zeroData(fullfile(fd,infoD.Files.FileName(k)));
end
sm = mabr.analysis.Settings(MinSweeps=0,MinPerPolarity=0);
zvFlag = mabr.analysis.SingleTrial.FlagZeroVariance;
secs = [0 0];
folders = [fq fd];
for i = 1:2
    sq = mabr.analysis.Session(folders(i),Verbose=false);
    t0 = tic;
    sq.analyze(sm);
    secs(i) = toc(t0);
    Cq = sq.Conditions;  Tq = sq.Thresholds;
    assert(secs(i) < 60,'%s: analyze took %.0f s.',folders(i),secs(i));
    assert(height(Cq) == 2*numel(tq.Levels) && all(isnan(Cq.p)) && ~any(Cq.isSig) && ...
        ~any(Cq.Detected) && all(contains(Cq.Flags,zvFlag)), ...
        '%s: a zero-variance condition was tested or not flagged.',folders(i));
    assert(all(isnan(Cq.F)) && all(isnan(Cq.SNR)) && all(isnan(Cq.PowerP)) && all(isnan(Cq.FspP)) && ...
        all(isnan(Cq.SplitR)), ...
        '%s: a zero-variance condition has a noise-referenced measure.',folders(i));
    assert(height(Tq) == 2 && all(Tq.Status == "insufficient") && ...
        all(contains(Tq.Flags,"zero variance (the clean sweeps do not vary)")), ...
        '%s: the series do not say they are insufficient for zero variance: %s.', ...
        folders(i),strjoin(Tq.Status + " / " + Tq.Flags," | "));
    W = sq.Messages.Text(sq.Messages.Level == "warning");
    lab = sq.conditionLabel(Cq.Key(1));
    assert(any(contains(W,"zero variance") & contains(W,"not tested") & contains(W,lab)) && ...
        any(contains(W,"zero variance") & contains(W,"are NaN") & contains(W,lab)), ...
        '%s: no warning names the zero-variance conditions.',folders(i));
end
% Without polarities the noiseless CM reads as noise: the test runs, and the
% TFCE step is raised to keep its |t| of ~1e8 finite. With them it is not run.
sq = mabr.analysis.Session(fq,Verbose=false);
sq.analyze(sm,Steps=["segment","reject"]);
r = find(sq.Conditions.Stimulus == "Tone" & sq.Conditions.Level == 0);
[Xq,polq,strq] = deal(sq.Conditions.Sweeps{r},sq.Conditions.Polarity{r},sq.Conditions.SweepFile{r});
use = ~sq.Conditions.Rejected{r} & ~sq.Conditions.Excess{r};
t0 = tic;
d1 = mabr.analysis.Threshold.detect(Xq(:,use),Rows=sq.ResponseRows,Method="tfce",NumPermutations=1000,Seed=1);
tRaised = toc(t0);
assert(~d1.ZeroVariance && isfinite(d1.p) && d1.TFCEStep > 0.1 && any(startsWith(d1.Flags,"TFCE step raised")) && ...
    tRaised < 20,'Unpolarized noiseless sweeps: p %g, step %g, %.1f s, flags "%s".',d1.p,d1.TFCEStep, ...
    tRaised,strjoin(d1.Flags,"; "));
d2 = mabr.analysis.Threshold.detect(Xq(:,use),Rows=sq.ResponseRows,Method="tfce",Seed=1, ...
    Polarity=polq(use),Strata=strq(use));
assert(d2.ZeroVariance && isnan(d2.p) && ~d2.isSig && isequal(d2.Flags,zvFlag), ...
    'Polarized noiseless sweeps were tested.');
% A noisy condition: no flag, the default step, and PermTest's own answer.
r = find(s.Conditions.Frequency == 8 & s.Conditions.Level == 40,1);
use = ~s.Conditions.Rejected{r} & ~s.Conditions.Excess{r};
Xs = s.Conditions.Sweeps{r}(:,use);
d3 = mabr.analysis.Threshold.detect(Xs,Rows=s.ResponseRows,Method="tfce",NumPermutations=200,Seed=7);
[p3,res3] = mabr.analysis.PermTest.run(Xs(s.ResponseRows,:),Method="tfce",NumPermutations=200,Seed=7);
assert(~d3.ZeroVariance && isempty(d3.Flags) && d3.TFCEStep == 0.1 && d3.p == p3 && ...
    d3.strength == res3.statistic && isequal(d3.result.null,res3.null), ...
    'A noisy condition''s TFCE test is not PermTest''s own.');
fprintf(['  PASS Part M: a noiseless session and an all-zero channel analyse in %.1f and %.1f s with ' ...
    'the recommended settings: every condition untested (p NaN) and flagged zero variance, F/SNR/' ...
    'PowerP/Fsp/SplitR NaN, both series "insufficient" for zero variance, warnings naming them; ' ...
    'unpolarized noiseless sweeps tested with a raised TFCE step (%.2f s); a noisy test is PermTest''s ' ...
    'own (%.1f s)\n'],secs,tRaised,toc(tp));

% =========================================================================
%  Leaks
% =========================================================================
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_analyze left a figure open.');
tmr = timerfindall;
if ~isempty(tmr)
    assert(~any(startsWith(string(get(tmr,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
assert(isequal(rng,rng0),'The global random stream was drawn from.');
assert(isequaln(offlinePrefs(),prefs0),'A MABR offline preference changed.');
clear cleanup
assert(~isfolder(root),'The temporary folder was not removed.');
fprintf('== verify_offline_analyze PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Helpers
% =========================================================================
function k = matchSeries(Th,row)
% The truth row of a Thresholds row (by stimulus and frequency).
if row.Stimulus == "ClickTrain"
    k = find(Th.Stimulus == "ClickTrain",1);
else
    k = find(Th.Stimulus == row.Stimulus & Th.Frequency == row.Frequency,1);
end
end

function cancelAt(c,k)
% A progress sink that cancels once the count reaches k.
if c >= k
    error('mabr:analysis:cancelled','Cancelled by user.');
end
end

function S = snapshotOf(s)
% What a cancelled edit must leave untouched.
S = struct('Conditions',s.Conditions,'Thresholds',s.Thresholds,'Peaks',s.Peaks, ...
    'ManualRejections',s.ManualRejections,'StepState',s.StepState,'EditLog',s.EditLog);
end

function logLines(seen,m,c,logFile)
% At the start of session c+1 the log holds c lines (and its header).
if ~startsWith(string(m),"Session "), return; end
n = 0;
if isfile(logFile)
    n = numel(splitlines(strtrim(string(fileread(logFile))))) - 1;
end
x = seen('lines');
x(end+1,:) = [c n];
seen('lines') = x; %#ok<NASGU> (a containers.Map: a handle)
end

function zeroData(file)
% One .abr file with every sample zero: a dead channel, as the rig writes it.
S = load(file,'-mat');
ABR_Data = S.ABR_Data;
ABR_Data.ADC.Data(:) = 0;
save(file,'ABR_Data','-mat');
end

function P = offlinePrefs()
% Every MABR pref whose name starts OfflineAnalysis, as a struct.
P = struct();
if ~ispref('MABR'), return; end
g = getpref('MABR');
for f = string(fieldnames(g)).'
    if startsWith(f,"OfflineAnalysis"), P.(f) = g.(f); end
end
end
