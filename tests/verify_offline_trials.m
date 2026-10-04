function verify_offline_trials()
% verify_offline_trials  The Trials tab: single sweeps, hand rejection, and the single-trial panels.
%
%   Drives mabr.ui.analysis.TrialView inside an invisible mabr.ui.AnalysisApp
%   over mabrtest.OfflineFixture the way a person would -- controls by Tag,
%   the view's gestures (clickSweep, selectRange), keys through
%   dispatchKey -- with every dialog stubbed, progress windows off and
%   timers off (AutoRefresh false) except where the debounce timer itself
%   is the subject. The condition is the mixed session's 4 kHz tone,
%   conventional run (it holds a rig note, written at sweep 32 of 80 dB).
%
%     Part A  a session opened from its results offers "Load raw data (…)"
%             (AnalysisTrialsLoadRaw, with its glyph); pressing it loads the
%             sweeps and the panels take the offer's place
%     Part B  the header: condition, N / clean / rejected (manual), RN, SNR,
%             F, Fsp, perm p and the wave readout, each the Session's number
%     Part C  the image: one row per shown sweep, the sweeps themselves in
%             µV in acquisition order, red ticks at the rejected rows, the
%             colour limits at the 99th percentile of |x|, the rig note at
%             the sweep it was written at (and on the feature plot)
%     Part D  the controls: feature, x axis (sweep / time / block), order by
%             feature, include rejected, the bootstrap band (after the
%             debounce, the arithmetic of SingleTrial.bootstrapBand), the
%             polarity means (the Session's conditionMean); the look pref is
%             written by the controls and by nothing a script does
%     Part E  selection: click, Shift+click (in the order shown, sorted by
%             the feature too), Ctrl+click, selectRange; the label, the image
%             ticks, the feature rings, the highlighted sweep
%     Part F  r and Shift+R through dispatchKey: the flags, the recompute
%             report on the status line, the condition re-tested (statistic
%             and p move), Ctrl+Z puts every flag back
%     Part G  Reject above in the condition and in the series (counted
%             against the features), Clear manual rejections
%     Part H  the +/- reference (the one measure() drew: its RMS is the
%             stored RNPM) and panel (d): convergence (RN against N, the
%             1/sqrt(N) guide, the SNR); the permutation test without its
%             null (from a results file) and with it (after a re-test); the
%             split-half too-few note, then -- the settings asking for K >= 8
%             and the session re-measured -- the histogram whose mean IS the
%             stored r, bounded "partition 2.5–97.5%", and no "CI" anywhere
%     Part I  the 150 ms debounce: a change starts MABR_OfflineTrials,
%             flush() does the work now, the timer does it by itself
%     Part J  the sound conduction delay (13 A9): every time axis in ear
%             time ("Time re sound arrival (ms)", the delay in the subtitle
%             and the header's tooltip); the wave windows -- written and
%             searched in the recording's time -- the response window and
%             the peaks all shifted to it, each window still holding its
%             pick; the header's latency the reported one; cleared, onset
%             time again
%     Part L  the controls at 1500 px (two rows) and at the window's
%             minimum width (one strip a row), nothing cut off
%     Part K  keys (arrows change the condition; +, − and Ctrl+0 the image
%             colour), fewer than two clean sweeps, no session, context
%             menus, glyphs and Tags
%     Part M  Reject above on a session read from raw and never measured
%             (no Features table): the Model compares the feature the tab
%             plots -- SingleTrial.features over the response window within
%             the condition's Extent -- and a ratio reads as a ratio
%
%   No hardware, no parallel pool, no modal dialog; tempdir only; every pref
%   restored (mabrtest.prefGuard).
%
%   See also mabr.ui.analysis.TrialView, verify_offline_app, mabrtest.OfflineFixture
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_trials ==\n');
tAll  = tic;
figs0 = findall(groot,'Type','figure');
keys  = [mabr.ui.AnalysisApp.prefKeys(),"OfflineAnalysisTrials","OfflineAnalysisTrial"];
guard = mabrtest.prefGuard(keys); %#ok<NASGU>
look  = mabrtest.prefGuard(["OfflineAnalysisTrials","OfflineAnalysisTrial"],Clear=true); %#ok<NASGU>

F = mabrtest.OfflineFixture.make(Subjects="SUBJ-ID-9001");   % one subject is all it takes
fprintf('  (fixture in %.1f s)\n',toc(tAll));
app = newApp(F);
closer = mabrtest.OfflineFixture.closer(app,F); %#ok<NASGU> (the app, THEN the fixture's folders)
m = app.Model;
app.openRoot(F.Root);
key = F.Keys(contains(F.Keys,"T14"));
assert(isscalar(key),'The fixture has no mixed session.');

t0 = tic;
v = partA_loadRaw(app,key);
viewCleanup = onCleanup(@() deleteView(app,v));
times = struct('A',toc(t0));
times = timed(times,'B',@() partB_header(app,v));
times = timed(times,'C',@() partC_image(app,v));
times = timed(times,'D',@() partD_controls(app,v));
times = timed(times,'E',@() partE_selection(app,v));
times = timed(times,'H1',@() partH1_panels(app,v));
times = timed(times,'F',@() partF_keys(app,v));
times = timed(times,'H2',@() partH2_null(app,v));
times = timed(times,'G',@() partG_rejectAbove(app,v));
times = timed(times,'H3',@() partH3_splitHalf(app,v,F));
times = timed(times,'J',@() partJ_latency(app,v));
times = timed(times,'I',@() partI_debounce(app,v));
times = timed(times,'L',@() partL_layout(app,v));
times = timed(times,'K',@() partK_rest(app,v));
times = timed(times,'M',@() partM_unmeasured(app,v,F));
parts = strings(1,0);
for k = string(fieldnames(times)).'
    parts(end+1) = sprintf('%s %.1f',k,times.(k)); %#ok<AGROW>
end
fprintf('  (seconds per part: %s)\n',strjoin(parts,', '));

clear viewCleanup closer
deleteView(app,v);
closeQuietly(app);
assert(~isvalid(m),'Closing the app left its Model.');

% ---- leaks ------------------------------------------------------------
drawnow;
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_trials left a figure open.');
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_trials PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Part A -- results only: the offer to load the sweeps
% =========================================================================
function v = partA_loadRaw(app,key)
m = app.Model;
m.openSession(key);
assert(m.SessionSource == "results" && ~m.Session.HasSweeps,'The session did not open from its results.');
m.selectSeries("Stimulus=Tone|AcqMode=conventional|Frequency=4",Level=80);
v = trialView(app);
rp = tagged(app,'AnalysisTrialsRawPanel');
lr = tagged(app,'AnalysisTrialsLoadRaw');
assert(strcmp(rp.Visible,'on') && startsWith(string(lr.Text),"Load raw data (") && ...
    endsWith(string(lr.Text),")"),'A results-only session does not offer "Load raw data (…)" (%s).',string(lr.Text));
assert(~isempty(lr.Icon),'The Load raw data button has no glyph.');
hdr = tagged(app,'AnalysisTrialsHeader');
assert(contains(string(hdr.Text),"N 64") && contains(string(hdr.Text),"perm p"), ...
    'The header does not show the stored measures while results only (%s).',string(hdr.Text));
assert(isempty(v.Trial) && strcmp(tagged(app,'AnalysisTrialsReject').Enable,'off'), ...
    'Sweep actions are offered with no sweeps in memory.');
lr.ButtonPushedFcn(lr,[]);
assert(m.SessionSource == "raw" && m.Session.HasSweeps,'Load raw data did not load the sweeps.');
assert(strcmp(rp.Visible,'off') && ~isempty(v.Trial) && v.Trial.Key == m.Selection.ConditionKey, ...
    'The panels did not replace the offer.');
fprintf('  PASS Part A: results only -> "%s" (load glyph) -> the sweeps are drawn\n',string(lr.Text));
end

% =========================================================================
%  Part B -- the header
% =========================================================================
function partB_header(app,v)
m = app.Model;
S = m.Session;
ck = m.Selection.ConditionKey;
r = S.rowOf(ck);
C = S.Conditions;
St = mabr.ui.analysis.Style;
h = string(tagged(app,'AnalysisTrialsHeader').Text);
man = sum(C.Rejected{r} & C.RejectReason{r} == 3);
want = ["Tone 4 kHz","80 dB", ...
    sprintf("N %d / clean %d / rejected %d (manual %d)",numel(C.Rejected{r}),C.nClean(r),C.nRejected(r),man), ...
    "RN " + St.formatUV(C.RN(r),2), sprintf("SNR %.1f dB",C.SNR(r)), ...
    "F " + sprintf('%.2g',C.F(r)) + " (p " + sprintf('%.3g',C.PowerP(r)) + ")", ...
    "Fsp " + sprintf('%.2g',C.Fsp(r)) + " (p " + sprintf('%.3g',C.FspP(r)) + ")", ...
    "perm p " + sprintf('%.3g',C.p(r))];
for w = want
    assert(contains(h,w),'The header lacks "%s": %s',w,h);
end
P = S.Peaks;
i = find(string(P.Key) == ck & string(P.Wave) == "I",1);
assert(~isempty(i) && isfinite(P.PeakLatency(i)),'No wave I pick at 80 dB to read out.');
w = "I " + St.formatMs(P.PeakLatency(i),2) + " " + St.formatUV(P.AmpPT(i),2);
assert(contains(h,w),'The header does not read out wave I as "%s": %s',w,h);
assert(~isempty(v.Trial),'No trial data.');
fprintf('  PASS Part B: header "%s"\n',h);
end

% =========================================================================
%  Part C -- the image
% =========================================================================
function partC_image(app,v)
m = app.Model;
S = m.Session;
ck = m.Selection.ConditionKey;
r = S.rowOf(ck);
C = S.Conditions;
D = v.Trial;
H = v.Handles;
[~,acq] = sort(C.SweepOrder{r});
assert(isequal(D.Display,reshape(acq,1,[])),'The image rows are not in acquisition order.');
im = H.Image;
assert(isequal(size(im.CData),[numel(D.Display) numel(S.Time)]), ...
    'The image is %s, not sweeps x time (%d x %d).',mat2str(size(im.CData)),numel(D.Display),numel(S.Time));
X = C.Sweeps{r};
assert(max(abs(im.CData - 1e6*X(:,D.Display).'),[],'all') < 1e-9,'The image is not the sweeps in µV.');
assert(isequal(im.XData,[S.Time(1) S.Time(end)]),'The image''s time axis is not the session''s.');
rej = find(C.Rejected{r}(D.Display));
assert(~isempty(rej),'The fixture condition has no rejected sweep to mark.');
assert(isequal(tickRows(H.ImageRejected),rej(:)),'The red ticks are not at the rejected rows.');
Z = X(:,~C.Rejected{r} & ~C.Excess{r});
p99 = 1e6*mabr.analysis.Stats.percentile(abs(Z(isfinite(Z))),0.99);
lim = H.ImageAxes.CLim;
assert(abs(lim(2) - p99) < 1e-9*p99 && lim(1) == -lim(2),'The colour limits are not ±p99(|x|) (%s vs %g).', ...
    mat2str(lim),p99);
% the rig note "Electrode impedance 3.2 kOhm" was written at sweep 32 of this run
assert(isscalar(D.Notes) && D.Notes(1).Text == "Electrode impedance 3.2 kOhm", ...
    'The rig note of this run was not placed (%d notes).',numel(D.Notes));
c = D.Notes(1).Col;
assert(D.Index(c) == 32,'The note sits at sweep %d, not 32.',D.Index(c));
assert(isequal(H.ImageNotes.YData,find(D.Display == c)),'The note mark is not at its sweep''s row.');
assert(any(abs(H.FeatureNotes.XData - D.PX(c)) < 1e-12),'The feature plot has no note tick at the sweep.');
assert(string(H.ImageAxes.XLabel.String) == "Time re onset (ms)",'The image''s time axis label.');
fprintf(['  PASS Part C: image %d x %d sweeps x time in acquisition order, red ticks at the %d rejected rows, ' ...
    'colour ±%.3g µV (p99), the rig note at sweep 32\n'],size(im.CData),numel(rej),p99);
end

% =========================================================================
%  Part D -- the controls (and the look pref)
% =========================================================================
function partD_controls(app,v)
m = app.Model;
S = m.Session;
ck = m.Selection.ConditionKey;
r = S.rowOf(ck);
C = S.Conditions;
H = v.Handles;
pk = 'OfflineAnalysisTrials';
assert(~ispref('MABR',pk),'The look pref exists before any control was used.');
% a script's look is not a preference
v.applySettings(struct('Feature',"RMS"));
assert(v.ViewLook.Feature == "RMS" && ~ispref('MABR',pk),'applySettings wrote the look pref.');
Ft = C.Features{r};
clean = ~C.Rejected{r} & ~C.Excess{r};
assert(maxDiff(H.FeatureClean.YData,1e6*Ft.RMS(clean).') < 1e-9,'The RMS feature is not plotted.');
% the controls
setCtl(tagged(app,'AnalysisTrialsFeature'),'P2P');
assert(ispref('MABR',pk) && isequal(getpref('MABR',pk),v.displaySettings()), ...
    'A control did not remember the look.');
assert(maxDiff(H.FeatureClean.YData,1e6*Ft.P2P(clean).') < 1e-9 && ...
    maxDiff(H.FeatureClean.XData,C.SweepOrder{r}(clean)) < 1e-12,'P–P against sweep order.');
assert(contains(string(H.FeatureAxes.YLabel.String),"P–P (µV)"),'The feature axis label.');
setCtl(tagged(app,'AnalysisTrialsXAxis'),'time');
assert(maxDiff(H.FeatureClean.XData,C.SweepTime{r}(clean)) < 1e-9,'Time (s) is not the sweeps'' time in the run.');
setCtl(tagged(app,'AnalysisTrialsXAxis'),'block');
x = H.FeatureClean.XData;
assert(all(x >= 0.6 & x <= 1.4) && isequal(H.FeatureAxes.XTick,1),'One file is one block.');
setCtl(tagged(app,'AnalysisTrialsXAxis'),'sweep');
setCtl(tagged(app,'AnalysisTrialsOrder'),'feature');
D = v.Trial;
f = D.FV(D.Display);
assert(issorted(f(isfinite(f))) && maxDiff(H.Image.CData(1,:),1e6*C.Sweeps{r}(:,D.Display(1)).') < 1e-9, ...
    'Ordered by the feature, the image rows are not sorted by it.');
assert(contains(string(H.ImageAxes.YLabel.String),"by P–P"),'The image does not say it is sorted.');
setCtl(tagged(app,'AnalysisTrialsOrder'),'acquisition');
setCtl(tagged(app,'AnalysisTrialsIncludeRejected'),false);
D = v.Trial;
assert(numel(D.Display) == sum(~C.Rejected{r}) && size(H.Image.CData,1) == numel(D.Display) && ...
    all(isnan(H.FeatureRejected.XData)),'Leaving rejected sweeps out.');
setCtl(tagged(app,'AnalysisTrialsIncludeRejected'),true);
% polarity: the Session's own means
for pol = ["positive","negative","difference","balanced"]
    setCtl(tagged(app,'AnalysisTrialsPolarity'),char(pol));
    mm = S.conditionMean(ck,pol);
    assert(maxDiff(H.MeanLine.YData,1e6*mm.') < 1e-9,'The %s mean is not the Session''s.',pol);
end
setCtl(tagged(app,'AnalysisTrialsPolarity'),'overlay');
assert(maxDiff(H.MeanPos.YData,1e6*S.conditionMean(ck,"positive").') < 1e-9 && ...
    maxDiff(H.MeanNeg.YData,1e6*S.conditionMean(ck,"negative").') < 1e-9 && all(isnan(H.MeanLine.YData)), ...
    'The +/− overlay.');
ttl = string(H.MeanAxes.Title.String);
assert(contains(ttl,"\color") && contains(ttl,"+ mean") && contains(ttl,"− mean"), ...
    'The overlay''s title does not name each mean in its line''s colour: %s',ttl);
setCtl(tagged(app,'AnalysisTrialsPolarity'),'balanced');
[mm,se] = S.conditionMean(ck,"balanced");
by = H.MeanBand.YData;
assert(maxDiff(by(:,1).',1e6*[(mm - se).' fliplr((mm + se).')]) < 1e-9,'The SEM band.');
% the bootstrap band waits for the debounce
setCtl(tagged(app,'AnalysisTrialsBand'),'bootstrap');
assert(v.HeavyPending && all(isnan(H.MeanBand.YData(:))),'The bootstrap band did not wait for the debounce.');
v.flush();
D = v.Trial;
c = find(D.Clean);
[lo,hi] = mabr.analysis.SingleTrial.bootstrapBand(D.X(:,c),D.Pol(c),D.File(c),500,0.05, ...
    mabr.analysis.Stats.conditionStream(D.Opts.Seed,D.Key + "|band"));
by = H.MeanBand.YData;
assert(~v.HeavyPending && maxDiff(by(:,1).',1e6*[lo.' fliplr(hi.')]) < 1e-9,'The bootstrap band.');
assert(contains(string(H.MeanAxes.Title.String),"95% bootstrap"),'The mean title does not name the band.');
setCtl(tagged(app,'AnalysisTrialsBand'),'sem');
setCtl(tagged(app,'AnalysisTrialsFeature'),'MaxAbs');
assert(isequal(getpref('MABR',pk),v.displaySettings()),'The look pref does not follow the controls.');
fprintf(['  PASS Part D: feature, x axis (sweep / time / block), order, include rejected, polarity ' ...
    '(= conditionMean), SEM and bootstrap bands; the look pref is the controls'' only\n']);
end

% =========================================================================
%  Part E -- selection
% =========================================================================
function partE_selection(app,v)
m = app.Model;
H = v.Handles;
D = v.Trial;
cols = D.Display;
v.clickSweep(cols(10));
assert(isequal(m.Selection.Sweeps,cols(10)) && m.Selection.Anchor == cols(10),'A click did not select the sweep.');
v.clickSweep(cols(15),"shift");
assert(isequal(sort(m.Selection.Sweeps),sort(cols(10:15))),'Shift+click did not extend from the anchor.');
assert(string(tagged(app,'AnalysisTrialsSelection').Text) == "6 sweeps selected",'The selection label.');
assert(isequal(tickRows(H.ImageSelection),(10:15).'),'The image does not mark the selected rows.');
assert(numel(H.FeatureSelection.XData) == 6,'The feature plot does not ring the selection.');
assert(maxDiff(H.MeanSweep.YData,1e6*D.X(:,cols(10)).') < 1e-9,'The anchor sweep is not highlighted.');
assert(any(contains(string(H.MeanAxes.Subtitle.String),"light grey: sweep " + D.Order(cols(10)))), ...
    'The mean''s subtitle does not say which sweep the light grey line is.');
assert(strcmp(tagged(app,'AnalysisTrialsReject').Enable,'on'),'Reject selected is off with sweeps selected.');
v.clickSweep(cols(12),"control");
assert(numel(m.Selection.Sweeps) == 5 && ~ismember(cols(12),m.Selection.Sweeps),'Ctrl+click did not toggle.');
sel = v.selectRange(20.5,30.5);
assert(isequal(sort(m.Selection.Sweeps),sort(sel)) && all(D.Order(sel) >= 21 & D.Order(sel) <= 30) && ...
    numel(sel) == 10,'selectRange did not select the x range.');
% in the order shown: sorted by the feature, a Shift+click range is a range of rows
setCtl(tagged(app,'AnalysisTrialsOrder'),'feature');
D = v.Trial;
v.clickSweep(D.Display(3));
v.clickSweep(D.Display(8),"shift");
assert(isequal(sort(m.Selection.Sweeps),sort(D.Display(3:8))),'Shift+click in feature order.');
setCtl(tagged(app,'AnalysisTrialsOrder'),'acquisition');
m.selectSweeps(zeros(1,0));
assert(string(tagged(app,'AnalysisTrialsSelection').Text) == "No sweeps selected" && ...
    strcmp(tagged(app,'AnalysisTrialsReject').Enable,'off'),'Clearing the selection.');
fprintf('  PASS Part E: click, Shift+click (acquisition and feature order), Ctrl+click, selectRange\n');
end

% =========================================================================
%  Part H1 -- panel (d) before any re-test
% =========================================================================
function partH1_panels(app,v)
H = v.Handles;
D = v.Trial;
S = app.Model.Session;
assert(strcmp(H.ConvPanel.Visible,'on') && strcmp(H.SplitPanel.Visible,'off'),'Convergence is not panel (d)''s default.');
v.flush();
c = find(D.Clean);
[~,o] = sort(D.Order(c));
cc = c(o);
want = mabr.analysis.SingleTrial.convergence(D.X(:,cc),D.Pol(cc),D.File(cc),D.MeasureRows,[], ...
    mabr.analysis.Stats.conditionStream(D.Opts.Seed,D.Key + "|convergence"));
assert(isequaln(v.Heavy.Conv,want),'The convergence is not SingleTrial.convergence of the clean sweeps.');
assert(isequal(H.ConvRN.XData,want.N.') && maxDiff(H.ConvRN.YData,1e6*want.RN.') < 1e-9 && ...
    maxDiff(H.ConvSNR.YData,want.SNR.') < 1e-9,'The convergence lines.');
p = polyfit(log(H.ConvGuide.XData),log(H.ConvGuide.YData),1);
assert(abs(p(1) + 0.5) < 1e-9 && abs(H.ConvGuide.YData(end) - H.ConvRN.YData(end)) < 1e-9, ...
    'The guide is not 1/sqrt(N) through the last point.');
% the +/- reference drawn is the analysis' own (replayed from the condition's
% stream): its RMS over the response window is the stored RNPM
ref = v.Heavy.Ref;
rows = D.MeasureRows(:) & all(isfinite(D.X(:,c)),2);
rnpm = S.Conditions.RNPM(D.Row);
assert(abs(sqrt(mean(ref(rows).^2)) - rnpm) < 1e-9*rnpm && maxDiff(H.MeanRef.YData,1e6*ref.') < 1e-9, ...
    'The ± reference is not the one measure() drew (RMS %.6g vs RNPM %.6g).',sqrt(mean(ref(rows).^2)),rnpm);
assert(any(contains(string(H.MeanAxes.Subtitle.String),"grey: ± reference")), ...
    'The mean''s subtitle does not name the ± reference.');
% the split-half: K = 16 per polarity per half, under the settings' 25
setCtl(tagged(app,'AnalysisTrialsPanelD'),'splithalf');
v.flush();
assert(strcmp(H.SplitPanel.Visible,'on') && isempty(v.Heavy.Split.R) && ...
    startsWith(strjoin(string(H.SplitNote.String)," "),"Too few sweeps for a split-half r"), ...
    'The split-half too-few note.');
% the permutation test, its null not in a results file
setCtl(tagged(app,'AnalysisTrialsPanelD'),'permutation');
d = S.Conditions.Detection{D.Row};
assert(isempty(d.null),'The null came back from the results file.');
assert(maxDiff(H.PermT.YData,double(d.t)) < 1e-12 && any(abs(H.PermThreshold.YData - d.tThresh) < 1e-12) && ...
    any(abs(H.PermThreshold.YData + d.tThresh) < 1e-12),'The t map and its threshold.');
assert(string(H.PermNullText.String) == mabr.ui.analysis.TrialView.NoNullText,'The no-null text.');
mask = logical(d.sigMask);
runs = sum(diff([false mask false]) == 1);
nSpans = 0;
if ~all(isnan(H.PermSpans.XData(:))), nSpans = size(H.PermSpans.XData,2); end
assert(nSpans == runs,'%d significant spans drawn for %d runs of the tfce mask.',nSpans,runs);
fprintf(['  PASS Part H1: ± reference = measure()''s (RMS = RNPM %.3g µV); convergence (= SingleTrial.convergence, ' ...
    '1/sqrt(N) guide), split-half too few (K < 25), permutation t map with %d span(s) and "%s"\n'], ...
    1e6*rnpm,runs,mabr.ui.analysis.TrialView.NoNullText);
end

% =========================================================================
%  Part F -- r and Shift+R through the keys
% =========================================================================
function partF_keys(app,v)
m = app.Model;
S = m.Session;
[ck,lv] = seriesLevels(m,m.Selection.SeriesKey);
% the level whose permutation p is furthest from both ends of its range (a p
% of 1 -- no response at all -- or of 1/(B+1) can stay put however many sweeps
% go; the fixture's 40 dB holds p 0.31)
C = S.Conditions;
p = C.p(S.rowOf(ck));
p(~(p > 0.02 & p < 0.98)) = NaN;
[~,j] = min(abs(log(p) - log(0.3)));
assert(isfinite(p(j)),'No level of the series has a mid-range p to move.');
m.selectLevel(lv(j));
assert(v.Trial.Key == ck(j),'The view did not follow the level.');
r = S.rowOf(ck(j));
rej0 = C.Rejected{r};
snap0 = S.editSnapshot();
d0 = C.Detection{r};
p0 = C.p(r);
D = v.Trial;
v.clickSweep(D.Display(5));
v.clickSweep(D.Display(24),"shift");
sel = m.Selection.Sweeps;
nNew = sum(~rej0(sel));
m.KeyTarget = "plot";
assert(app.dispatchKey(keyEvt('r')),'r was not handled on the Trials tab.');
C = S.Conditions;
assert(all(C.Rejected{r}(sel)) && all(C.RejectReason{r}(sel) == 3),'r did not reject the selection by hand.');
st = statusText(app);
assert(contains(st,sprintf('%d sweep(s) rejected',numel(sel))) && contains(st,"Ctrl+Z to undo"), ...
    'The status line does not echo the recompute report: %s',st);
d1 = C.Detection{r};
assert(d1.nSweeps == d0.nSweeps - nNew && d1.strength ~= d0.strength,'The condition was not re-tested.');
assert(C.p(r) ~= p0,'p did not change (%.4g) after %d sweeps were rejected.',p0,nNew);
h = string(tagged(app,'AnalysisTrialsHeader').Text);
assert(contains(h,sprintf('(manual %d)',numel(sel))),'The header does not count the manual rejections: %s',h);
assert(strcmp(tagged(app,'AnalysisTrialsClearManual').Enable,'on'),'Clear manual is off after a hand rejection.');
m.KeyTarget = "plot";
assert(app.dispatchKey(keyEvt('r','shift')),'Shift+R was not handled.');
C = S.Conditions;
assert(~any(C.Rejected{r}(sel)),'Shift+R did not restore the selection.');
assert(app.dispatchKey(keyEvt('z','control')),'The first Ctrl+Z was not handled.');
assert(app.dispatchKey(keyEvt('z','control')),'The second Ctrl+Z was not handled.');
assert(isequaln(S.editSnapshot(),snap0) && isequal(S.Conditions.Rejected{r},rej0),'Undo did not put the flags back.');
fprintf('  PASS Part F: r rejected %d sweeps (p %.4g -> %.4g; "%s"), Shift+R restored them, Ctrl+Z undid both\n', ...
    numel(sel),p0,d1.p,extractBefore(st + " —"," —"));
end

% =========================================================================
%  Part H2 -- the permutation null, once it is in memory
% =========================================================================
function partH2_null(app,v)
H = v.Handles;
S = app.Model.Session;
d = S.Conditions.Detection{v.Trial.Row};
assert(~isempty(d.null),'A re-tested condition has no null in memory.');
assert(string(H.PermNullText.String) == "" && maxDiff(H.PermObserved.XData,[d.strength d.strength]) < 1e-12, ...
    'The observed statistic is not drawn on the null.');
assert(max(H.PermNull.YData) > 0,'The null histogram is empty.');
t = string(H.PermNullAxes.Title.String);
assert(contains(t,"tfce") && contains(t,"B = " + numel(d.null)) && contains(t,"p " + sprintf('%.3g',d.p)), ...
    'The null''s title does not give the method, B and p: %s',t);
fprintf('  PASS Part H2: with the null in memory -- %s\n',t);
end

% =========================================================================
%  Part G -- Reject above, Clear manual rejections
% =========================================================================
function partG_rejectAbove(app,v)
m = app.Model;
S = m.Session;
setCtl(tagged(app,'AnalysisTrialsFeature'),'MaxAbs');
ck = v.Trial.Key;
r = S.rowOf(ck);
C = S.Conditions;
fV = C.Features{r}.MaxAbs.';                    % volts, as the Model compares them
f = 1e6*fV;
rej = C.Rejected{r};
fs = sort(f(~rej));
k = floor(numel(fs)/2);
val = (fs(k) + fs(k+1))/2;                       % between two sweeps, never on one
want = sum(fV > val*1e-6 & ~rej);
fld = tagged(app,'AnalysisTrialsRejectAboveValue');
setCtl(fld,val);
assert(maxDiff(v.Handles.FeatureAbove.YData,[val val]) < 1e-12,'The reject-above line is not at the value.');
b = tagged(app,'AnalysisTrialsRejectAbove');
b.ButtonPushedFcn(b,[]);
st = statusText(app);
assert(contains(st,sprintf('Rejected %d sweep(s)',want)) && contains(st,"in 1 condition(s)"), ...
    'Reject above in the condition: %s (expected %d)',st,want);
assert(isequal(S.Conditions.Rejected{r},rej | fV > val*1e-6),'Reject above flagged other sweeps.');
m.undo();
% every level of the series
total = 0;  nc = 0;
for c2 = reshape(seriesLevels(m,m.Selection.SeriesKey),1,[])
    r2 = S.rowOf(c2);
    f2 = S.Conditions.Features{r2}.MaxAbs.';
    n2 = sum(f2 > val*1e-6 & ~S.Conditions.Rejected{r2});
    total = total + n2;
    nc = nc + (n2 > 0);
end
b = tagged(app,'AnalysisTrialsRejectAboveSeries');
b.ButtonPushedFcn(b,[]);
st = statusText(app);
assert(contains(st,sprintf('Rejected %d sweep(s)',total)) && contains(st,sprintf('in %d condition(s)',nc)), ...
    'Reject above in the series: %s (expected %d in %d)',st,total,nc);
m.undo();
assert(isequal(S.Conditions.Rejected{r},rej),'Undo of Reject above.');
% a ratio feature's threshold is a plain number ("TemplateAmp above 1.5",
% never "1500000 µV"), compared with the ratios the plot shows
setCtl(tagged(app,'AnalysisTrialsFeature'),'TemplateAmp');
setCtl(fld,1.5);
fr = C.Features{r}.TemplateAmp.';
wantR = sum(fr > 1.5 & ~rej);
n0 = numel(m.undoHistory());
b = tagged(app,'AnalysisTrialsRejectAbove');
b.ButtonPushedFcn(b,[]);
st = statusText(app);
assert(contains(st,"TemplateAmp above 1.5 in") && ~contains(st,"µV") && ...
    contains(st,sprintf('Rejected %d sweep(s)',wantR)),'Reject above a ratio: %s (expected %d)',st,wantR);
if numel(m.undoHistory()) > n0, m.undo(); end
assert(isequal(S.Conditions.Rejected{r},rej),'Undo of Reject above a ratio.');
setCtl(tagged(app,'AnalysisTrialsFeature'),'MaxAbs');
% Clear manual rejections
D = v.Trial;
v.clickSweep(D.Display(2));
v.clickSweep(D.Display(4),"shift");
tagged(app,'AnalysisTrialsReject').ButtonPushedFcn(tagged(app,'AnalysisTrialsReject'),[]);
assert(strcmp(tagged(app,'AnalysisTrialsClearManual').Enable,'on') && height(S.ManualRejections) == 3, ...
    'The Reject selected button.');
cm = tagged(app,'AnalysisTrialsClearManual');
cm.ButtonPushedFcn(cm,[]);
assert(height(S.ManualRejections) == 0 && isequal(S.Conditions.Rejected{r},rej) && strcmp(cm.Enable,'off'), ...
    'Clear manual rejections did not drop the hand decisions.');
fprintf('  PASS Part G: Reject above %.3g µV -- %d sweep(s) in the condition, %d in %d level(s); a ratio feature reads as a plain number; Clear manual\n', ...
    val,want,total,nc);
end

% =========================================================================
%  Part H3 -- the split-half histogram, replayed
% =========================================================================
function partH3_splitHalf(app,v,F)
m = app.Model;
S = m.Session;
% first the split-half of the analysis as it stands (too few at K >= 25), so
% the panel holds a result the re-analysis below must replace -- the same
% sweeps, counts and flags, other options: a cache keyed on the sweeps
% alone would go on drawing the old one
setCtl(tagged(app,'AnalysisTrialsPanelD'),'splithalf');
v.flush();
assert(isempty(v.Heavy.Split.R),'The split-half was not too few under the fixture''s settings.');
s2 = F.Settings;
s2.SplitHalfMinPerPolarity = 8;
s2.SplitHalfResamples = 60;
m.setSettings(s2,Refit=false);
assert(m.Status.FromStep == "measure",'A split-half setting did not make "measure" out of date (%s).',m.Status.FromStep);
m.analyze();
setCtl(tagged(app,'AnalysisTrialsPanelD'),'splithalf');
v.flush();
H = v.Handles;
r = v.Trial.Row;
C = S.Conditions;
R = v.Heavy.Split;
assert(~isempty(R.R) && numel(R.R) == s2.SplitHalfResamples,'No split-half partitions.');
assert(R.Mean == C.SplitR(r) && R.SD == C.SplitRSD(r) && R.P025 == C.SplitRP025(r) && ...
    R.P975 == C.SplitRP975(r) && R.K == C.SplitN(r), ...
    'The partitions drawn are not the ones measure() made (mean %.17g vs %.17g).',R.Mean,C.SplitR(r));
assert(isequal(H.SplitMean.XData,[R.Mean R.Mean]) && ...
    isequaln(H.SplitBounds.XData,[R.P025 R.P025 NaN R.P975 R.P975]),'The mean and the bounds.');
y = H.SplitOutline.YData;
cnt = y(2:2:end-1);                              % the outline holds each bin's count twice
assert(sum(cnt) == numel(R.R) && all(cnt >= 0),'The histogram is not of the partitions.');
assert(string(H.SplitBoundsLabel.String) == "partition 2.5–97.5%" && strcmp(H.SplitBoundsLabel.Visible,'on'), ...
    'The bounds are not labelled "partition 2.5–97.5%".');
txt = [string(get(findall(H.SplitPanel,'Type','text'),'String')); string(H.SplitAxes.Title.String); ...
    string(H.SplitAxes.XLabel.String); string(tagged(app,'AnalysisTrialsHeader').Text)];
assert(~any(contains(txt,"CI")) && ~any(contains(txt,"confidence",'IgnoreCase',true)), ...
    'The split-half is called a confidence interval somewhere.');
h = string(tagged(app,'AnalysisTrialsHeader').Text);
assert(contains(h,sprintf('split-half r %.2f (SD %.2f; partition 2.5–97.5%%',C.SplitR(r),C.SplitRSD(r))), ...
    'The header does not give the split-half r: %s',h);
% the +/- reference was redrawn with the new analysis too: still measure()'s
D = v.Trial;
c = find(D.Clean);
rows = D.MeasureRows(:) & all(isfinite(D.X(:,c)),2);
assert(abs(sqrt(mean(v.Heavy.Ref(rows).^2)) - C.RNPM(r)) < 1e-9*C.RNPM(r), ...
    'After the re-analysis the ± reference is not measure()''s.');
fprintf('  PASS Part H3: split-half r %.3f from %d replayed partitions (K = %d) = measure()''s, "partition 2.5–97.5%%"\n', ...
    R.Mean,numel(R.R),R.K);
end

% =========================================================================
%  Part J -- the sound conduction delay (13 A9)
% =========================================================================
function partJ_latency(app,v)
m = app.Model;
S = m.Session;
key = m.SessionKey;
m.selectLevel(80);
setCtl(tagged(app,'AnalysisTrialsPanelD'),'permutation');
v.flush();
H = v.Handles;
ck = v.Trial.Key;
P = S.Peaks;
i = find(string(P.Key) == ck & string(P.Wave) == "I",1);
ear0 = P.PeakLatency(i);                         % offset 0: ear time is raw time
g = findobj(H.MeanAxes,'Tag','TrialsPeak_I');
assert(abs(g.XData - ear0) < 1e-12,'Wave I is not drawn at its latency.');
st = S.Settings;
W = mabr.analysis.Peaks.wavesFor(st.Waves,"Tone",4,OctaveShift=st.PeakOctaveShift, ...
    RefFrequency=st.PeakRefFrequency,Offset=0);
w1 = W(string({W.Name}) == "I");
wp = findobj(H.MeanAxes,'Tag','TrialsWaveWindow_I');
assert(maxDiff(wp.XData(:).',[w1.TMin w1.TMax w1.TMax w1.TMin]) < 1e-12,'The wave I window.');

m.setSessionOverrides(key,struct('ConductionDelay',0.25));
v.flush();
assert(abs(m.latencyOffset() - 0.25) < 1e-12,'The delay did not reach the session.');
for ax = [H.MeanAxes H.ImageAxes H.PermTAxes]
    assert(string(ax.XLabel.String) == "Time re sound arrival (ms)", ...
        'An axes (%s) does not read "Time re sound arrival (ms)" (%s).',ax.Tag,string(ax.XLabel.String));
end
sub = string(H.MeanAxes.Subtitle.String);
assert(any(contains(sub,"re sound arrival (0.25 ms")),'The subtitle does not name the delay: %s',strjoin(sub," | "));
assert(contains(string(tagged(app,'AnalysisTrialsHeader').Tooltip),"0.25"),'The header tooltip does not name the delay.');
assert(maxDiff(H.MeanLine.XData,S.Time.' - 0.25) < 1e-12 && ...
    maxDiff(H.Image.XData,[S.Time(1) S.Time(end)] - 0.25) < 1e-12,'The traces are not in ear time.');
% the windows are in the recording's time (where the picker searched), so
% on the ear-time axis they move 0.25 ms earlier with the traces and picks
assert(maxDiff(wp.XData(:).',[w1.TMin w1.TMax w1.TMax w1.TMin] - 0.25) < 1e-12, ...
    'The wave I window is not drawn 0.25 ms earlier (its recording-time window re sound arrival).');
lp = findobj(H.MeanAxes,'Tag','TrialsWaveLabel_I');
assert(abs(lp.Position(1) - (mean([w1.TMin w1.TMax]) - 0.25)) < 1e-12,'The wave I label did not move with its window.');
% each drawn window still holds its pick (to a sample: the parabolic
% refinement), as each recording-time window holds its raw pick
P = S.Peaks;
dt = 1000/S.SampleRate;
nHeld = 0;
for j = 1:numel(W)
    nm = string(W(j).Name);
    r = find(string(P.Key) == ck & string(P.Wave) == nm,1);
    if isempty(r) || string(P.State(r)) ~= "auto" || ~isfinite(P.PeakLatency(r)), continue; end
    fn = matlab.lang.makeValidName(nm);
    gw = findobj(H.MeanAxes,'Tag',char("TrialsWaveWindow_" + fn));
    gp = findobj(H.MeanAxes,'Tag',char("TrialsPeak_" + fn));
    assert(isscalar(gw) && isscalar(gp) && strcmp(gw.Visible,'on'),'Wave %s has no drawn window or pick.',nm);
    assert(gp.XData >= min(gw.XData) - dt && gp.XData <= max(gw.XData) + dt, ...
        'Wave %s''s pick (%.3f ms drawn) is outside its drawn window [%.3f %.3f] with a 0.25 ms delay.', ...
        nm,gp.XData,min(gw.XData),max(gw.XData));
    assert(abs(gp.XData - (P.PeakLatency(r) - 0.25)) < 1e-12,'Wave %s is not at its reported latency.',nm);
    nHeld = nHeld + 1;
end
assert(nHeld >= 1,'No automatic pick of the condition to hold against its window.');
rw = v.Trial.Opts.ResponseWindow;               % raw, like the sweeps
assert(maxDiff(H.MeanWindow.XData,[rw(1) rw(2) rw(2) rw(1)] - 0.25) < 1e-12, ...
    'The response window is not drawn in ear time.');
P = S.Peaks;
i = find(string(P.Key) == ck & string(P.Wave) == "I",1);
assert(abs(g.XData - (P.PeakLatency(i) - 0.25)) < 1e-12,'Wave I is not at its reported latency.');
h = string(tagged(app,'AnalysisTrialsHeader').Text);
assert(contains(h,"I " + mabr.ui.analysis.Style.formatMs(P.PeakLatency(i) - 0.25,2)), ...
    'The header''s wave I is not re sound arrival: %s',h);
d = S.Conditions.Detection{v.Trial.Row};
k = S.Time >= d.RowsMs(1) - 1e-9 & S.Time <= d.RowsMs(2) + 1e-9;
assert(maxDiff(H.PermT.XData,S.Time(k).' - 0.25) < 1e-12,'The t map is not in ear time.');
m.setSessionOverrides(key,struct('ConductionDelay',NaN));
v.flush();
assert(string(H.MeanAxes.XLabel.String) == "Time re onset (ms)" && ...
    ~any(contains(string(H.MeanAxes.Subtitle.String),"sound arrival")) && ...
    maxDiff(H.MeanLine.XData,S.Time.') < 1e-12,'Clearing the delay did not give onset time back.');
fprintf(['  PASS Part J: a 0.25 ms delay -- mean, image and t axes "Time re sound arrival (ms)", ' ...
    'delay in subtitle and tooltip, traces, wave windows and picks 0.25 ms ' ...
    'earlier (each window holding its pick), wave I at its ' ...
    'reported latency; cleared, onset again\n']);
end

% =========================================================================
%  Part I -- the debounce
% =========================================================================
function partI_debounce(app,v)
m = app.Model;
restore = onCleanup(@() setAuto(m,false));
m.AutoRefresh = true;
n0 = v.HeavyRuns;
m.stepLevel(-1);
assert(v.HeavyPending,'A new condition did not leave the single-trial panels for the debounce.');
tm = timerfindall('Tag','MABR_OfflineTrials');
assert(isscalar(tm) && strcmp(tm.Running,'on') && tm.StartDelay == 0.15 && strcmp(tm.BusyMode,'drop'), ...
    'The debounce timer is not running (150 ms, BusyMode drop).');
v.flush();
assert(~v.HeavyPending && v.HeavyRuns == n0 + 1 && strcmp(tm.Running,'off'),'flush() did not run the debounced work.');
m.stepLevel(1);
assert(v.HeavyPending,'The second change did not wait.');
t0 = tic;
while v.HeavyPending && toc(t0) < 5
    pause(0.05);
end
assert(~v.HeavyPending && v.HeavyRuns == n0 + 2,'The timer did not run the work by itself (%.2f s).',toc(t0));
fprintf('  PASS Part I: a change waits 150 ms (MABR_OfflineTrials); flush() runs it now; the timer ran it in %.2f s\n', ...
    toc(t0));
end

% =========================================================================
%  Part L -- the controls fit the window, wide and at its minimum size
% =========================================================================
function partL_layout(app,v)
f = app.Figure;
pos0 = f.Position;
back = onCleanup(@() set(f,'Position',pos0));
H = v.Handles;
seen = strings(1,0);
strips = [H.StripA H.StripB H.StripC H.StripD];
for w = [1100 1500]
    % an invisible window is laid out a moment after it is resized (and
    % gets no SizeChangedFcn): wait for the controls' width to move, render
    % (renderAll measures them), and wait for the strips to settle
    cw0 = H.ControlsPanel.Position(3);
    f.Position = [pos0(1:2) w 760];
    waitFor(@() H.ControlsPanel.Position(3) ~= cw0);
    v.applySettings(struct());
    settle(strips);
    cw = H.ControlsPanel.Position(3);
    want = "narrow";
    if cw >= mabr.ui.analysis.TrialView.WideControls, want = "wide"; end
    assert(v.ControlLayout == want,'At %d px (controls %g px) the layout is %s, not %s.', ...
        w,cw,v.ControlLayout,want);
    nRows = numel(H.Controls.RowHeight);
    assert(nRows == 2 + 2*(want == "narrow"),'The %s layout has %d rows.',want,nRows);
    % nothing is cut off: every control lies inside its strip, every strip
    % inside the panel
    for s = [H.StripA H.StripB H.StripC H.StripD]
        sp = s.Position;
        assert(sp(1) + sp(3) <= cw + 1,'A strip runs past the controls'' right edge at %d px.',w);
        for c = reshape(s.Children,1,[])
            p = c.Position;
            if isa(c,'matlab.ui.control.Label') && strlength(string(c.Text)) == 0, continue; end
            assert(p(1) >= 0 && p(1) + p(3) <= sp(3) + 1, ...
                '%s is cut off at %d px (x %g + %g > strip %g).',string(c.Tag),w,p(1),p(3),sp(3));
        end
    end
    seen(end+1) = sprintf('%d px: %s',w,want); %#ok<AGROW>
end
cw0 = H.ControlsPanel.Position(3);
clear back
waitFor(@() H.ControlsPanel.Position(3) ~= cw0);
v.applySettings(struct());
fprintf('  PASS Part L: the controls fit (%s) with nothing cut off\n',strjoin(seen,', '));
end

function waitFor(cond)
% Poll (drawnow) until COND holds, at most 5 s.
t = tic;
drawnow;
while ~cond() && toc(t) < 5
    pause(0.05);
    drawnow;
end
end

function settle(h)
% Poll until the positions of the graphics H have stopped moving (at most 5 s).
t = tic;
last = [];
while toc(t) < 5
    pause(0.1);
    drawnow;
    pos = vertcat(h.Position);
    if isequal(pos,last), break; end
    last = pos;
end
end

% =========================================================================
%  Part K -- keys, empty states, menus, glyphs, Tags
% =========================================================================
function partK_rest(app,v)
m = app.Model;
H = v.Handles;
owned = isequal(app.Views.Trials,v);
assert(owned,'The app does not hold the Trials view: its keys would not reach it through dispatchKey.');
ck0 = m.Selection.ConditionKey;
m.KeyTarget = "plot";
assert(app.dispatchKey(keyEvt('downarrow')) && v.Trial.Key == m.Selection.ConditionKey && ...
    v.Trial.Key ~= ck0,'↓ did not move the Trials tab to the quieter level.');
m.KeyTarget = "plot";
app.dispatchKey(keyEvt('uparrow'));
assert(v.Trial.Key == ck0,'↑ did not come back.');
lim0 = H.ImageAxes.CLim(2);
scale = @(id,k) runKey(app,v,owned,id,k);
scale("view.scaleUp",keyEvt('equal'));
assert(abs(H.ImageAxes.CLim(2) - lim0/1.5) < 1e-9*lim0,'+ did not raise the image contrast.');
scale("view.resetZoom",keyEvt('0','control'));
assert(abs(H.ImageAxes.CLim(2) - lim0) < 1e-9*lim0,'Ctrl+0 did not reset it.');
scale("view.scaleDown",keyEvt('hyphen'));
assert(abs(H.ImageAxes.CLim(2) - lim0*1.5) < 1e-9*lim0,'− did not lower it.');
scale("view.resetZoom",keyEvt('0','control'));
% Esc is the tab's only while a drag is in progress
assert(~v.onCommand("nav.escape"),'Esc with no drag in progress was kept from the app.');
% fewer than two clean sweeps
v.selectRange(-Inf,Inf);
m.KeyTarget = "plot";
app.dispatchKey(keyEvt('r'));
D = v.Trial;
assert(D.NClean == 0 && string(H.MeanFew.String) == mabr.ui.analysis.TrialView.FewText && ...
    size(H.Image.CData,1) == D.N,'Every sweep rejected: "%s" with the image kept.',mabr.ui.analysis.TrialView.FewText);
assert(contains(string(tagged(app,'AnalysisTrialsHeader').Text),"clean 0"),'The header with no clean sweep.');
m.KeyTarget = "plot";
app.dispatchKey(keyEvt('z','control'));
assert(v.Trial.NClean >= 2 && string(H.MeanFew.String) == "",'Undo did not bring the sweeps back.');
% context menus end with the export items; the sweep plots act on the selection
for ax = [H.ImageAxes H.MeanAxes H.FeatureAxes H.ConvAxes H.SplitAxes H.PermTAxes H.PermNullAxes]
    tags = string(get(ax.ContextMenu.Children,'Tag'));
    assert(all(ismember(["AnalysisMenuFigureExportItem","AnalysisMenuCopyDataItem","AnalysisMenuCopyImageItem"],tags)), ...
        'The %s menu does not end with Export figure / Copy data / Copy image.',ax.Tag);
end
for ax = [H.ImageAxes H.FeatureAxes]
    tags = string(get(ax.ContextMenu.Children,'Tag'));
    assert(all(ismember(["AnalysisTrialsMenuReject","AnalysisTrialsMenuRestore"],tags)),'The %s menu.',ax.Tag);
end
% glyphs (13 A6) and Tags (11 sec. 8)
for t = ["AnalysisTrialsLoadRaw","AnalysisTrialsReject","AnalysisTrialsRestore","AnalysisTrialsClearManual", ...
        "AnalysisTrialsRejectAbove"]
    assert(~isempty(tagged(app,t).Icon),'%s has no glyph.',t);
end
for t = ["AnalysisTrialsHeader","AnalysisTrialsSelection","AnalysisTrialsImage","AnalysisTrialsMean", ...
        "AnalysisTrialsFeaturePlot","AnalysisTrialsPanel"]
    tagged(app,t);
end
for t = ["AnalysisTrialsFeature","AnalysisTrialsXAxis","AnalysisTrialsPanelD","AnalysisTrialsBand", ...
        "AnalysisTrialsPolarity","AnalysisTrialsOrder","AnalysisTrialsIncludeRejected", ...
        "AnalysisTrialsRejectAboveValue","AnalysisTrialsRejectAbove","AnalysisTrialsRejectAboveSeries", ...
        "AnalysisTrialsReject","AnalysisTrialsRestore","AnalysisTrialsClearManual","AnalysisTrialsLoadRaw"]
    assert(strlength(string(tagged(app,t).Tooltip)) > 30,'%s has no full-sentence tooltip.',t);
end
% no session
m.closeSession();
lab = findall(app.Figure,'-regexp','Tag','^AnalysisTrials?Empty$');
assert(any(arrayfun(@(x) string(x.Text) == mabr.ui.analysis.TrialView.NoSessionText,lab)) && ...
    isempty(v.Trial),'No session: the empty state.');
fprintf(['  PASS Part K: ↓/↑ follow the level; + − Ctrl+0 scale the image (%s); every sweep rejected ' ...
    'keeps the image and says "%s"; menus, glyphs, Tags; no session\n'], ...
    pick(owned,"through dispatchKey","through onCommand: the app does not hold the view"), ...
    mabr.ui.analysis.TrialView.FewText);
end

% =========================================================================
%  Part M -- Reject above before measure(): the tab's features
% =========================================================================
function partM_unmeasured(app,v,F)
m = app.Model;
others = F.Keys(~contains(F.Keys,"T14"));
k2 = others(1);
rf = m.sessionInfo(k2).ResultsFile;
if isfile(rf), delete(rf); end                   % (the fixture's, in tempdir)
m.openSession(k2);
assert(m.SessionSource == "raw" && m.Session.HasSweeps && m.Status.State == "not-analysed", ...
    'A session without results did not open from its raw files, unanalysed (%s).',m.Status.State);
sk = m.seriesKeys(Stimulus="Tone");
sk = sk(contains(sk,"Frequency=4"));
assert(~isempty(sk),'The session has no 4 kHz tone series.');
m.selectSeries(sk(1),Level=80);
assert(isequal(app.Views.Trials,v),'The Trials tab was rebuilt.');
app.activateTab("Trials");
v.flush();
S = m.Session;
D = v.Trial;
r = S.rowOf(D.Key);
C = S.Conditions;
noF = ~ismember('Features',C.Properties.VariableNames) || ~istable(C.Features{r}) || height(C.Features{r}) == 0;
assert(noF,'The unmeasured session already has a Features table: nothing here tests the fallback.');
% (a ratio feature, a plain number: TemplateAmp where the average holds a
% response to scale by -- SingleTrial.features leaves it NaN otherwise --
% else TemplateR, the other one)
feat = "TemplateAmp";
fr = double(D.Features.TemplateAmp(:)).';
if ~any(isfinite(fr))
    feat = "TemplateR";
    fr = double(D.Features.TemplateR(:)).';
end
rej = logical(C.Rejected{r});  rej = rej(:).';
fs = sort(fr(~rej & isfinite(fr)));
assert(numel(fs) >= 2,'The tab computed no %s for the unmeasured condition.',feat);
k = floor(numel(fs)/2);
val = (fs(k) + fs(k+1))/2;                       % between two sweeps, never on one
want = sum(fr > val & ~rej);
assert(want > 0,'Nothing above the median %s.',feat);
setCtl(tagged(app,'AnalysisTrialsFeature'),char(feat));
setCtl(tagged(app,'AnalysisTrialsRejectAboveValue'),val);
n0 = numel(m.undoHistory());
b = tagged(app,'AnalysisTrialsRejectAbove');
b.ButtonPushedFcn(b,[]);
st = statusText(app);
assert(contains(st,sprintf('Rejected %d sweep(s) with %s above %s',want,feat,sprintf('%.3g',val))) && ...
    ~contains(st,"µV"),'Reject above on an unmeasured session: "%s" (expected %d above %.3g, the tab''s feature).', ...
    st,want,val);
got = logical(S.Conditions.Rejected{r});
assert(isequal(got(:).',rej | fr > val),'Reject above flagged other sweeps than the tab''s %s says.',feat);
if numel(m.undoHistory()) > n0, m.undo(); end
setCtl(tagged(app,'AnalysisTrialsFeature'),'MaxAbs');
fprintf(['  PASS Part M: before measure(), Reject above compares the tab''s own feature ' ...
    '(%s > %.3g: %d sweep(s)), a ratio in plain numbers\n'],feat,val,want);
end

% =========================================================================
%  Helpers
% =========================================================================
function times = timed(times,name,fcn)
t = tic;
fcn();
times.(name) = toc(t);
end

function app = newApp(F)
work = string(tempname);
app = mabr.ui.AnalysisApp("",Visible="off",ResultsFolder=F.ResultsFolder, ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false,RememberState=false, ...
    ProgressMode="none",AutoRefresh=false, ...
    ConfirmFcn=@(msg,title,options,default) string(options(1)), ...
    PromptFcn=@(prompt,title,default) [], PickFolderFcn=@(start,title) "", ...
    PickFileFcn=@(filter,title,mode,default) string(fullfile(work,"picked.dat")), ...
    AlertFcn=@(msg,title,icon) []);
end

function v = trialView(app)
% The app's Trials view: the app builds the Trials tab as a TrialView
% (AnalysisApp.viewClass), and the keys go through its dispatcher.
app.activateTab("Trials");
v = app.Views.Trials;
assert(~isempty(v) && isa(v,'mabr.ui.analysis.TrialView') && v.IsActive, ...
    'The app did not build its Trials tab as a mabr.ui.analysis.TrialView (%s).',class(v));
assert(isempty(findall(app.Figure,'Tag','AnalysisTrialsUnavailable')), ...
    'The Trials tab says its view is not available.');
end

function deleteView(app,v)
% A view the app does not hold is the test's to delete (its timer with it).
try
    if ~isempty(v) && isvalid(v) && ~(isvalid(app) && isequal(app.Views.Trials,v))
        delete(v);
    end
catch
end
end

function runKey(app,v,owned,id,evt)
if owned
    app.Model.KeyTarget = "plot";
    assert(app.dispatchKey(evt),'%s was not handled.',id);
else
    assert(v.onCommand(id),'%s was not handled by the view.',id);
end
end

function h = tagged(app,tag)
h = findall(app.Figure,'Tag',char(tag));
assert(isscalar(h),'%d controls tagged %s.',numel(h),tag);
end

function setCtl(h,value)
h.Value = value;
h.ValueChangedFcn(h,[]);
end

function s = statusText(app)
s = string(tagged(app,'AnalysisStatusText').Text);
end

function e = keyEvt(key,varargin)
e = struct('Key',key,'Modifier',{varargin},'Character','');
if isscalar(key) && isempty(varargin), e.Character = key; end
end

function rows = tickRows(h)
% The rows a NaN-separated tick line marks (each tick spans row±0.45).
y = h.YData(:);
y = y(isfinite(y));
rows = unique(round(y));
rows = rows(:);
end

function d = maxDiff(a,b)
a = double(a(:));  b = double(b(:));
if numel(a) ~= numel(b) || ~isequal(isnan(a),isnan(b))
    d = Inf;
    return
end
k = ~isnan(a);
d = max([0; abs(a(k) - b(k))]);
end

function [ck,lv] = seriesLevels(m,sk)
ck = m.seriesConditions(sk);
S = m.Session;
lp = m.levelParam();
lv = S.Conditions.(lp)(S.rowOf(ck));
end

function setAuto(m,tf)
try
    if isvalid(m), m.AutoRefresh = tf; end
catch
end
end

function v = pick(tf,a,b)
if tf, v = a; else, v = b; end
end

function closeQuietly(app)
try
    if ~isempty(app) && isvalid(app), delete(app); end
catch
end
end
