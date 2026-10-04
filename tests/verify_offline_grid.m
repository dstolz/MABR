function verify_offline_grid()
% verify_offline_grid  The analysis app's Grid tab: columns, controls, dividers, significance, overlays, gestures, keys.
%
%   Drives mabr.ui.analysis.GridView inside an invisible mabr.ui.AnalysisApp
%   over mabrtest.OfflineFixture (plus one session written here with a
%   condition missing), the way a user would: through the strip's controls
%   (Value + ValueChangedFcn), the key dispatcher, and the view's public
%   gestures (selectAt, clickAt, menuAction).
%
%     Part A  the pure pieces: GridView.sigSamples shades clusters with
%             p < alpha for a cluster-mass Detection built by hand (NOT its
%             sigMask -- defect 11) and sigMask for tmax/TFCE; dividerY puts
%             an interval, a right- and a left-censored threshold and a value
%             at the right height; a junk look pref is read forgivingly
%     Part B  one axes per series; the Stimulus and AcqMode filters change
%             the set (AcqMode shown only for a session holding both)
%     Part C  significance drawn from the session's own TFCE detections, and
%             from a cluster-mass re-analysis (clusters, not sigMask)
%     Part D  peak markers: one line per wave x kind per axes, at the picked
%             latencies on the drawn traces (none below threshold)
%     Part E  Compare with: another session's means from its results file,
%             grey dash-dots on this grid's scale; hidden, overlay and all,
%             in blind review
%     Part F  keys through dispatchKey: t / i / Alt+Down / c / a / x / d put
%             the Final (and the fit) dividers at the right rows, a decision
%             on another series redraws that column alone, n / + / - /
%             Shift+Up / Ctrl+0 redraw in place, arrows move the selection;
%             none of it writes a pref
%     Part G  gestures: selectAt, the row-band hit test of clickAt, a
%             double-click opening the Series tab, the axes' own
%             ButtonDownFcn (SelectionType "normal" and "open"), every
%             menuAction, the context menu's items
%     Part L  the threshold by hand, through the mouse's own callbacks (the
%             figure's CurrentPoint, the column's ButtonDownFcn, the
%             window's motion / up / key callbacks): each column's grip and
%             the hover pointer; a drag snaps half way between two of the
%             column's levels (manual at the louder, an undo step, an EditLog
%             row), Alt the exact value, above / below the levels no response
%             / all respond (NR), Esc (the app's and the window's) cancels,
%             Ctrl+Z undoes; a press on the divider let go selects the row
%             under it and a double-click there still opens Series; with the
%             Threshold layer off there is nothing to drag
%     Part H  a ragged grid: a level a series lacks is "not recorded" (no
%             trace), and an unanalysed session says so in a banner
%     Part I  the sound conduction delay (13 A9): with a 0.25 ms delay the
%             traces, the response window and the peak markers move to ear
%             time, the axis reads "Time re sound arrival (ms)" and the note
%             under the grid names the delay; a system offset alone keeps
%             "re onset" and names the offset; at 0 nothing differs
%     Part K  LevelDirection "descending" (a thresholds-only refit through
%             Settings) turns the stack over and the dashed rows follow the
%             descending rule; a divider dragged above / below the rows
%             previews no response / all respond where the release leaves
%             it; back to "auto" it turns back
%     Part J  the strip's look controls (window, scale, polarity, band,
%             annotation, the three switches) drive the drawing with the
%             graphics updated in place, a window ending before it starts is
%             refused (the field put back), Copy data copies no layer that
%             is switched off, and the controls -- only they -- write the
%             pref OfflineAnalysisGrid
%
%   No hardware, no parallel pool, no modal dialog, no timer; tempdir only;
%   every MABR pref the app may write is restored (mabrtest.prefGuard).
%
%   See also mabr.ui.analysis.GridView, verify_offline_app, mabrtest.OfflineFixture

% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_grid ==\n');
tAll  = tic;
figs0 = findall(groot,'Type','figure');
keys  = mabr.ui.AnalysisApp.prefKeys();
guard = mabrtest.prefGuard(keys,Clear=true); %#ok<NASGU>

partA_static();

F = mabrtest.OfflineFixture.make();
rag = writeRagged(F);
fprintf('  (fixture and the ragged session written in %.1f s)\n',toc(tAll));
[app,stub] = newApp(F); %#ok<ASGLU>
closer = mabrtest.OfflineFixture.closer(app,F); %#ok<NASGU> (the app, THEN the fixture's folders)
app.openRoot(F.Root);
m = app.Model;
k = struct('Base',keyOf(F,"_Baseline","SUBJ-ID-9001"),'Two',keyOf(F,"_2weeks","SUBJ-ID-9001"), ...
    'Mixed',keyOf(F,"T140000","SUBJ-ID-9001"),'Rag',rag.Key);
m.openSession(k.Base);
app.activateTab("Grid");
v = app.Views.Grid;
assert(isa(v,'mabr.ui.analysis.GridView'),'The Grid tab is not a GridView.');
prefs0 = allPrefs();

fprintf('  (app open on the study in %.1f s)\n',toc(tAll));
took = strings(1,0);
parts = {@() partB_columns(app,v,k), @() partC_significance(app,v,k), @() partD_peaks(app,v), ...
    @() partE_compare(app,v,k), @() partF_keys(app,v), @() partG_gestures(app,v), ...
    @() partL_drag(app,v), @() partH_ragged(app,v,k), @() partI_latency(app,v,k), ...
    @() partK_direction(app,v)};
names = ["B","C","D","E","F","G","L","H","I","K"];
for i = 1:numel(parts)
    t0 = tic;
    parts{i}();
    took(end+1) = names(i) + sprintf(' %.1f',toc(t0)); %#ok<AGROW>
end
d = changedPrefs(prefs0,allPrefs());
assert(isempty(d),'Script-driven grid use (gestures, keys, filters) wrote a pref: %s',strjoin(d,', '));
fprintf('  PASS prefs: filters, gestures and keys wrote no pref\n');
t0 = tic;
partJ_controls(app,v,prefs0);
took(end+1) = "J" + sprintf(' %.1f',toc(t0));
fprintf('  (seconds per part: %s)\n',strjoin(took,', '));

clear closer
closeQuietly(app);

% ---- leaks ------------------------------------------------------------
drawnow;
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_grid left a figure open.');
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_grid PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Part A -- the pure pieces
% =========================================================================
function partA_static()
G = 'mabr.ui.analysis.GridView';
t = (-2:1/12:10).';                       % 12 kHz
rowsMs = [0.5 8];
r0 = find(abs(t - 0.5) < 1e-9,1);
nTest = nnz(t >= 0.5 - 1e-9 & t <= 8 + 1e-9);
% a cluster-mass detection whose sigMask (|t| against a null of cluster
% MASSES) marks samples 1:5, while its clusters say 10:14 (p .01) and 30:33
% (p .4): the shading is the significant cluster, nothing else
det = struct('method',"clusterMass",'RowsMs',rowsMs,'sigMask',[true(1,5) false(1,nTest-5)], ...
    'clusters',struct('sign',{1,-1},'first',{10,30},'last',{14,33},'mass',{50,8},'p',{0.01,0.4}));
mask = feval([G '.sigSamples'],det,t,0.05);
want = false(numel(t),1);  want(r0 + (10:14) - 1) = true;
assert(isequal(mask,want),'clusterMass: the shading is not the significant cluster (defect 11).');
mask = feval([G '.sigSamples'],{det},t,0.005);
assert(~any(mask),'clusterMass at alpha .005 shaded a cluster with p .01.');
det.method = "tfce";
want = false(numel(t),1);  want(r0 + (0:4)) = true;
assert(isequal(feval([G '.sigSamples'],det,t,0.05),want),'tfce: the shading is not sigMask.');
det.method = "tmax";
assert(isequal(feval([G '.sigSamples'],det,t,0.05),want),'tmax: the shading is not sigMask.');
assert(~any(feval([G '.sigSamples'],[],t,0.05)) && ~any(feval([G '.sigSamples'],{},t,0.05)), ...
    'No detection shaded something.');
% dividers on a 0:20:80 stack, rows at 0..4
lv = (0:20:80).';  y = (0:4).';
dy = @(v,c,lo,hi) feval([G '.dividerY'],v,c,lo,hi,lv,y,1);
assert(abs(dy(30,"interval",20,40) - 1.5) < 1e-12,'An interval (20,40] is not halfway between its rows.');
assert(abs(dy(Inf,"right",80,NaN) - 4.5) < 1e-12,'No response is not above the top row.');
assert(abs(dy(0,"left",0,0) + 0.5) < 1e-12,'All respond is not under the bottom row.');
assert(abs(dy(34.9,"none",34.9,34.9) - 1.745) < 1e-12,'A value is not placed between its rows.');
% a censored threshold stands at its BOUND's row, not the extreme one: "≤20"
% with the 0 dB row left out by the method is under the 20 dB row, "> 60"
% (80 dB left out) above the 60 dB row
assert(abs(dy(20,"left",NaN,20) - 0.5) < 1e-12,'"≤20" is not under the 20 dB row.');
assert(abs(dy(Inf,"right",60,NaN) - 3.5) < 1e-12,'"> 60" is not above the 60 dB row.');
assert(isnan(dy(NaN,"",NaN,NaN)) && isnan(dy(Inf,"none",Inf,Inf)),'An excluded/undefined threshold has a divider.');
assert(abs(dy(95,"none",95,95) - 4.5) < 1e-12,'A value beyond the top is not held half a row above it.');
% an attenuation stack (80 at the bottom, 0 at the top): the censoring
% describes the numbers, so "left" (below 0 -- louder than the loudest, no
% response) is above the top row and "right" (all respond) under the bottom
ya = (0:4).';  la = (80:-20:0).';
da = @(v,c,lo,hi) feval([G '.dividerY'],v,c,lo,hi,la,ya,1);
assert(abs(da(0,"left",0,0) - 4.5) < 1e-12,'Attenuation: no response ("left") is not above the top row.');
assert(abs(da(80,"right",80,80) + 0.5) < 1e-12,'Attenuation: all respond ("right") is not under the bottom row.');
assert(abs(da(30,"interval",20,40) - 2.5) < 1e-12,'Attenuation: an interval is not halfway between its rows.');
% a junk pref is read forgivingly
setpref('MABR','OfflineAnalysisGrid',struct('Scale',"bogus",'WindowStart',5,'WindowEnd',1, ...
    'Peaks',"yes",'Fixed',-3,'Polarity',"negative"));
d = feval([G '.loadDefaults']);
f = feval([G '.factoryDefaults']);
assert(d.Scale == f.Scale && d.WindowStart == f.WindowStart && d.WindowEnd == f.WindowEnd && ...
    d.Peaks == f.Peaks && d.Fixed == f.Fixed && d.Polarity == "negative", ...
    'A junk OfflineAnalysisGrid pref was not read forgivingly.');
rmpref('MABR','OfflineAnalysisGrid');
fprintf(['  PASS Part A: sigSamples shades significant clusters for clusterMass (not its sigMask) and ' ...
    'sigMask for tmax/tfce; dividers for interval/right/left/value; a junk look pref is forgiven\n']);
end

% =========================================================================
%  Part B -- columns and filters
% =========================================================================
function partB_columns(app,v,k)
m = app.Model;
fig = app.Figure;
sk = m.seriesKeys();
assert(numel(v.Handles.Columns) == numel(sk) && isequal([v.Handles.Columns.SeriesKey].',sk), ...
    'The grid does not have one column per series.');
ax = findall(v.Handles.Panel,'Type','axes','Tag','AnalysisGridAxes','Visible','on');
assert(numel(ax) == numel(sk),'%d axes for %d series.',numel(ax),numel(sk));
L = v.Handles.Columns(1).Lines;
assert(numel(L) == 5 && all(arrayfun(@(r) any(isfinite(r.Line.YData)),L)), ...
    'The first column does not stack its five levels.');
acq = findall(fig,'Tag','AnalysisGridAcqMode');
assert(strcmp(acq.Visible,'off'),'The AcqMode filter shows for a one-mode session.');
t = v.Handles.Columns(1).Axes.Title.String;
short = mabr.ui.analysis.Style.compactSeriesLabels(arrayfun(@(s) m.seriesLabel(s),sk));
assert(contains(string(t{1}),short(1)),'A column title does not name its series (%s).',string(t{1}));
sc = v.Handles.Columns(1).Scale;
assert(startsWith(string(sc.String),"rows ") && endsWith(string(sc.String)," apart") && ...
    sc.Position(2) == 1,'The row-spacing label reads "%s".',string(sc.String));

m.openSession(k.Mixed);
skAll = m.seriesKeys();
assert(numel(v.Handles.Columns) == numel(skAll) && numel(skAll) == 5,'The mixed session has %d columns.', ...
    numel(v.Handles.Columns));
assert(strcmp(acq.Visible,'on'),'The AcqMode filter is hidden for a session holding both modes.');
st = findall(fig,'Tag','AnalysisGridStimulus');
assert(all(ismember(["All","Tone","ClickTrain"],string(st.ItemsData))),'The Stimulus filter lacks a stimulus.');
ax1 = v.Handles.Columns(1).Axes;
drive(st,'Tone');
assert(numel(v.Handles.Columns) == 4 && all(contains([v.Handles.Columns.SeriesKey],"Stimulus=Tone")), ...
    'Stimulus=Tone did not leave the four tone series.');
drive(acq,'interleaved');
c = [v.Handles.Columns.SeriesKey];
assert(numel(c) == 2 && all(contains(c,"AcqMode=interleaved")),'AcqMode=interleaved did not leave two series.');
vis = findall(v.Handles.Panel,'Type','axes','Visible','on');
assert(numel(vis) == 2 && all(ismember(vis,[v.Handles.Columns.Axes])),'Filtered out columns still show.');
% the axes put away are hidden whole and hold no data a copy would find
hid = findall(v.Handles.Panel,'Type','axes','Visible','off');
assert(numel(hid) == 3,'%d axes put away (3 expected).',numel(hid));
L = findobj(hid,'Type','line');
assert(all(arrayfun(@(h) all(isnan(h.YData)),L)),'A put-away axes still holds data a copy would find.');
T = findall(hid,'Type','text');
words = arrayfun(@(h) strjoin(string(h.String)," / "),T);
shown = strcmp(get(T,'Visible'),'on') & strlength(words) > 0;
assert(~any(shown),'A put-away axes still shows text ("%s").',strjoin(words(shown),'", "'));
drive(st,'All');
drive(acq,'All');
assert(numel(v.Handles.Columns) == 5,'Clearing the filters did not bring every series back.');
assert(numel(findall(v.Handles.Panel,'Type','axes')) == 5 && ...
    numel(findall(v.Handles.Panel,'Type','axes','Visible','on')) == 5,'Stale axes left behind after the filters.');
assert(v.Handles.Columns(1).Axes == ax1,'The filters rebuilt the axes rather than re-using them.');
m.openSession(k.Base);
assert(numel(findall(v.Handles.Panel,'Type','axes','Visible','on')) == 2 && ...
    all(arrayfun(@(r) any(isfinite(r.Line.YData)),v.Handles.Columns(1).Lines)), ...
    'Back on the two-series session, the grid is not its two columns.');
fprintf(['  PASS Part B: one axes per series (2; the mixed session 5); Stimulus/AcqMode filters change ' ...
    'the set, re-using the axes (the ones not needed hidden and empty); AcqMode shown only for a ' ...
    'two-mode session\n']);
end

% =========================================================================
%  Part C -- significance (defect 11)
% =========================================================================
function partC_significance(app,v,k)
m = app.Model;
v.applySettings(struct('Significance',true));
S = m.Session;
[nSig,nDrawn] = sigCounts(v,S);
assert(nSig > 0,'No significant sample in the analysed session: nothing to check.');
assert(nDrawn == nSig,'TFCE: %d samples shaded, %d significant.',nDrawn,nSig);
assert(strcmp(v.Handles.Columns(1).Sig.Visible,'on'),'The significance band is hidden while on.');

% a cluster-mass re-analysis of another session: shaded = its clusters
m.openSession(k.Two);
s = m.Settings;
s0 = s;
s.DetectMethod = "clusterMass";
s.NumPermutations = 50;            % (p down to 1/51: enough to find the responses' clusters)
m.setSettings(s,Refit=false);
m.analyze();
S = m.Session;
dets = S.Conditions.Detection;
assert(all(cellfun(@(d) string(d.method),dets) == "clusterMass"),'The re-analysis did not use cluster mass.');
[nSig,nDrawn,nMask] = sigCounts(v,S);
assert(nSig > 0,'The cluster-mass re-analysis found no significant cluster to shade.');
assert(nDrawn == nSig,'clusterMass: %d samples shaded, %d in significant clusters.',nDrawn,nSig);
assert(nMask ~= nSig,'This check cannot tell clusters from sigMask (both %d samples).',nSig);
m.setSettings(s0,Refit=false);
m.openSession(k.Base);
v.applySettings(struct('Significance',false));
assert(strcmp(v.Handles.Columns(1).Sig.Visible,'off'),'The significance band shows while off.');
fprintf(['  PASS Part C: significance drawn from TFCE sigMask (%d samples) and, after a cluster-mass ' ...
    're-analysis, from its significant clusters (not its sigMask)\n'],nDrawn);
end

function [nSig,nDrawn,nMask] = sigCounts(v,S)
% The significant samples within the window, as GridView.sigSamples says,
% as the GridSignificance lines draw them, and as the raw sigMask would.
D = v.Grid;
alpha = S.Settings.Alpha;
nSig = 0;  nDrawn = 0;  nMask = 0;
keysC = string(S.Conditions.Key);
for j = 1:numel(D.Keys)
    for r = 1:numel(D.Levels)
        ck = D.Cond(j,r);
        if ck == "", continue; end
        det = S.Conditions.Detection{keysC == ck};
        mk = mabr.ui.analysis.GridView.sigSamples(det,S.Time,alpha);
        nSig = nSig + nnz(mk(D.Win));
        raw = false(numel(S.Time),1);
        [~,r0] = min(abs(S.Time - det.RowsMs(1)));
        raw(r0 + find(det.sigMask) - 1) = true;
        nMask = nMask + nnz(raw(D.Win));
    end
    h = findobj(v.Handles.Columns(j).Axes,'Tag','GridSignificance');
    assert(isscalar(h),'Column %d has %d significance lines (one expected).',j,numel(h));
    nDrawn = nDrawn + nnz(isfinite(h.YData));
end
end

% =========================================================================
%  Part D -- peaks
% =========================================================================
function partD_peaks(app,v)
m = app.Model;
S = m.Session;
W = S.Settings.Waves;
nW = nnz([W.Enabled]);
D = v.Grid;
P = S.Peaks;
for j = 1:numel(D.Keys)
    ax = v.Handles.Columns(j).Axes;
    h = findobj(ax,'Tag','GridPeaks');
    assert(numel(h) == 2*nW,'Column %d has %d peak lines for %d waves (one per wave x kind).',j,numel(h),nW);
    for i = 1:numel(h)
        u = h(i).UserData;
        x = [];  y = [];
        for r = 1:numel(D.Levels)
            ck = D.Cond(j,r);
            row = find(string(P.Key) == ck & string(P.Wave) == u.Wave,1);
            if isempty(row), continue; end
            if u.Kind == "P"
                lat = P.PeakLatency(row);  st = string(P.State(row));
            else
                lat = P.TroughLatency(row);  st = string(P.TroughState(row));
            end
            if ~isfinite(lat) || ~any(st == ["auto","manual"]) || lat < D.X(1) || lat > D.X(end), continue; end
            if P.BelowThreshold(row), continue; end       % (not marked below threshold)
            x(end+1,1) = lat; %#ok<AGROW>
            y(end+1,1) = interp1(D.X,D.Y{j,r},lat); %#ok<AGROW>
        end
        hx = h(i).XData(:);  hy = h(i).YData(:);
        if isempty(x)
            assert(all(isnan(hx)),'Wave %s %s: markers with no pick.',u.Wave,u.Kind);
        else
            assert(numel(hx) == numel(x) && max(abs(hx - x)) < 1e-12 && max(abs(hy - y)) < 1e-12, ...
                'Wave %s %s markers are not at the picked latencies on the trace.',u.Wave,u.Kind);
        end
    end
end
v.applySettings(struct('Peaks',false));
assert(all(strcmp(get(findobj(v.Handles.Panel,'Tag','GridPeaks'),'Visible'),'off')),'Peaks off still shows markers.');
v.applySettings(struct('Peaks',true));
fprintf('  PASS Part D: %d peak lines per axes (wave x kind), each at its picked latencies on the trace\n',2*nW);
end

% =========================================================================
%  Part E -- compare with another session
% =========================================================================
function partE_compare(app,v,k)
m = app.Model;
fig = app.Figure;
dd = findall(fig,'Tag','AnalysisGridCompare');
data = string(dd.ItemsData);
assert(any(data == k.Two) && any(data == k.Mixed) && ~any(data == k.Base) && ...
    ~any(contains(data,"SUBJ-ID-9002")),'Compare with does not offer this subject''s other sessions only.');
drive(dd,char(k.Two));
assert(v.CompareKey == k.Two,'Picking a session did not compare with it.');
O = mabr.analysis.Session.fromResults(m.sessionInfo(k.Two).ResultsFile,Verbose=false);
D = v.Grid;
h = findobj(v.Handles.Columns(1).Axes,'Tag','GridCompare');
assert(isscalar(h) && strcmp(h.Visible,'on') && any(isfinite(h.YData)),'No compare overlay drawn.');
assert(strcmp(h.LineStyle,'-.'),'The compare overlay is not dash-dotted (dashed grey is below threshold).');
% the first row's segment is the other session's mean on THIS grid's scale
ck = D.Cond(1,1);
mu = O.conditionMean(ck,"balanced");
xo = O.Time(:);
in = xo >= D.XLim(1) - 1e-9 & xo <= D.XLim(2) + 1e-9;
want = D.RowY(1) + mu(in)/D.Den(1,1);
seg = h.YData(1:nnz(in));
assert(max(abs(seg(:) - want(:))) < 1e-12,'The compare overlay is not the other session''s mean on this scale.');
drive(dd,'(none)');
assert(v.CompareKey == "" && strcmp(h.Visible,'off'),'None did not remove the overlay.');
% blind review hides Compare with, and takes an overlay with it
drive(dd,char(k.Two));
m.startReviewQueue(k.Base,Blind=true,UnreviewedOnly=false);
app.activateTab("Grid");
assert(m.BlindReview && strcmp(dd.Visible,'off') && strcmp(v.Handles.CompareLabel.Visible,'off') && ...
    v.CompareKey == "" && ~any(isfinite(h.YData)),'Blind review does not hide Compare with (and its overlay).');
m.endQueue();
assert(~m.BlindReview && strcmp(dd.Visible,'on') && m.SessionKey == k.Base, ...
    'Compare with did not come back after the blind review.');
fprintf(['  PASS Part E: Compare with offers this subject''s analysed sessions; its means drawn as grey ' ...
    'dash-dots on this scale; hidden (overlay and all) in blind review\n']);
end

% =========================================================================
%  Part F -- keys (and the dividers they move)
% =========================================================================
function partF_keys(app,v)
m = app.Model;
D = v.Grid;
sk = D.Keys(1);
v.selectAt(sk,40);
press(app,'t');
row = thrRow(m,sk);
assert(row.Decision == "manual" && row.FinalCensored == "interval" && row.FinalHi == 40, ...
    't did not set the threshold at 40 dB.');
[yF,yT,vis] = dividers(v,1);
assert(vis(1) && abs(yF - 1.5) < 1e-12,'An interval (20,40] divider is at %g, not between the 20 and 40 dB rows.',yF);
fitY = mabr.ui.analysis.GridView.dividerY(row.Threshold,row.Censored,row.ThrLo,row.ThrHi,D.Levels,D.RowY,D.Pitch);
if isfinite(fitY) && abs(fitY - 1.5) > 1e-9
    assert(vis(2) && abs(yT - fitY) < 1e-12,'The fit is not drawn dashed red where the decision differs.');
end
L = v.Handles.Columns(1).Lines;
assert(strcmp(L(1).Line.LineStyle,'--') && strcmp(L(2).Line.LineStyle,'--') && strcmp(L(4).Line.LineStyle,'-'), ...
    'Below-threshold traces are not dashed (or above-threshold ones are).');
assert(L(3).Line.LineWidth == 2.5 && isequal(L(3).Line.Color,mabr.ui.analysis.Style.Accent), ...
    'The selected condition is not thick amber.');
tt = string(v.Handles.Columns(1).Axes.Title.String);
assert(contains(tt(2),"(20–40]") && contains(tt(2),"fit"),'The title does not show the decision and the fit: %s',tt(2));

press(app,'i');
assert(thrRow(m,sk).Decision == "noresponse",'i did not mark no response.');
[yF,~,vis] = dividers(v,1);
lab = v.Handles.Columns(1).FinalLabel;
assert(vis(1) && abs(yF - 4.5) < 1e-12 && string(lab.String) == "NR" && strcmp(lab.Visible,'on'), ...
    'No response is not "NR" above the top row.');
press(app,'downarrow',{'alt'});
assert(thrRow(m,sk).Decision == "allrespond",'Alt+Down did not mark all respond.');
[yF,~,vis] = dividers(v,1);
assert(vis(1) && abs(yF + 0.5) < 1e-12,'All respond is not under the bottom row.');
press(app,'c');
assert(thrRow(m,sk).Decision == "",'c did not clear the decision.');
[~,~,vis] = dividers(v,1);
assert(~vis(2),'The fit is drawn although no decision differs from it.');
press(app,'a');
assert(thrRow(m,sk).Decision == "accepted",'a did not accept the fit.');
press(app,'x');
assert(thrRow(m,sk).Decision == "excluded" && m.KeysSuspended,'x did not exclude and open the note editor.');
press(app,'escape');
assert(~m.KeysSuspended,'Esc did not close the note editor.');
[~,~,vis] = dividers(v,1);
tt = string(v.Handles.Columns(1).Axes.Title.String);
assert(~vis(1) && startsWith(tt(2),"excluded"),'An excluded series still shows a final threshold.');
press(app,'x');
assert(thrRow(m,sk).Decision == "",'x did not include the series again.');

% a decision on another column (as the Series tab makes it) is drawn in
% that column, in place, and leaves this one alone
C2 = v.Handles.Columns(2);
f1 = v.Handles.Columns(1).Final;
y1 = f1.YData;  vis1 = char(f1.Visible);
m.setAllRespond(D.Keys(2));
[yF,~,vis] = dividers(v,2);
assert(vis(1) && abs(yF + 0.5) < 1e-12 && isvalid(C2.Axes) && C2.Axes == v.Handles.Columns(2).Axes, ...
    'All respond on the second column is not drawn under its bottom row, in place.');
assert(all(strcmp(get([C2.Lines.Line],'LineStyle'),'-')),'All respond left a trace of the second column dashed.');
assert(isequal(f1.YData,y1) && strcmp(f1.Visible,vis1),'A decision on the second column moved the first one''s.');
m.clearDecision(D.Keys(2));

ck = m.Selection.ConditionKey;
press(app,'d');
assert(overrideOf(m,ck) == 1,'d did not force a response.');
r = find(arrayfun(@(x) x.ConditionKey == ck,v.Handles.Columns(1).Lines));
assert(string(v.Handles.Columns(1).Lines(r).Note.String) == "■",'The overridden condition is not marked ■.');
press(app,'d');  press(app,'d');
assert(isnan(overrideOf(m,ck)),'d three times is not back to automatic.');

h = v.Handles.Columns(1).Lines(2).Line;   % 20 dB: smaller than the column's scale
y0 = h.YData;
press(app,'n');
assert(v.Normalize && ~isequal(h.YData,y0) && isvalid(h),'n did not normalise in place.');
press(app,'n');
assert(~v.Normalize && isequal(h.YData,y0),'n again did not restore the common scale.');
press(app,'add',{},'+');
assert(v.Gain == 1.25 && ~isequal(h.YData,y0),'+ did not scale up.');
press(app,'subtract',{},'-');
assert(v.Gain == 1 && max(abs(h.YData - y0)) < 1e-12,'- did not scale back.');
yl = v.Handles.Columns(1).Axes.YLim;
press(app,'uparrow',{'shift'});
assert(v.Spacing == 1.25 && ~isequal(v.Handles.Columns(1).Axes.YLim,yl),'Shift+Up did not widen the rows.');
press(app,'0',{'control'});
assert(v.Spacing == 1 && v.Gain == 1 && ~v.Normalize && isequal(v.Handles.Columns(1).Axes.YLim,yl), ...
    'Ctrl+0 did not reset the stack.');

v.selectAt(sk,40);
press(app,'uparrow');
assert(m.Selection.Level == 60 && v.Handles.Columns(1).Lines(4).Line.LineWidth == 2.5 && ...
    v.Handles.Columns(1).Lines(3).Line.LineWidth < 2.5,'Up did not move the selection one level louder.');
press(app,'downarrow');
assert(m.Selection.Level == 40,'Down did not move the selection back.');
press(app,'rightarrow');
assert(m.Selection.SeriesKey == D.Keys(2) && m.Selection.Level == 40,'Right did not step to the next column.');
press(app,'leftarrow');
assert(m.Selection.SeriesKey == D.Keys(1),'Left did not step back.');
fprintf(['  PASS Part F: t/i/Alt+Down/c/a/x/d through dispatchKey (Final divider halfway in the interval, NR ' ...
    'above the top, under the bottom for all respond, the fit dashed red where it differs); a decision on ' ...
    'another series redraws only its column; n/+/-/Shift+Up/Ctrl+0 redraw in place; arrows move the selection\n']);
end

% =========================================================================
%  Part G -- gestures and the context menu
% =========================================================================
function partG_gestures(app,v)
m = app.Model;
D = v.Grid;
sk1 = D.Keys(1);  sk2 = D.Keys(2);
v.selectAt(sk2,60);
assert(m.Selection.ConditionKey == D.Cond(2,4),'selectAt did not select that condition.');
% the row bands: halfway to each neighbour
assert(v.clickAt(sk1,2.4) == D.Cond(1,3) && v.clickAt(sk1,2.6) == D.Cond(1,4) && ...
    v.clickAt(sk1,-7) == D.Cond(1,1) && v.clickAt(sk1,99) == D.Cond(1,5), ...
    'The row-band hit test does not reach halfway to each neighbour.');
assert(m.Selection.ConditionKey == D.Cond(1,5),'A click did not select its row.');
v.clickAt(sk1,1,"open");
assert(app.ActiveTab == "Series" && m.Selection.ConditionKey == D.Cond(1,2), ...
    'A double-click did not open the Series tab on that condition.');
app.activateTab("Grid");
% the axes' own ButtonDownFcn (what a click calls): the figure's
% SelectionType says what kind of click, the axes' CurrentPoint (read-only:
% wherever the pointer last was) which row
fig = app.Figure;
ax = v.Handles.Columns(1).Axes;
cp = ax.CurrentPoint;
want = v.rowAt(1,cp(1,2));
assert(want ~= "" && want ~= D.Cond(2,4),'(the click check needs a recorded row other than the selection)');
v.selectAt(sk2,60);
fig.SelectionType = 'normal';
ax.ButtonDownFcn(ax,[]);
assert(app.ActiveTab == "Grid" && m.Selection.ConditionKey == want, ...
    'A click on a column (its ButtonDownFcn) did not select the row under the pointer.');
v.selectAt(sk2,60);
fig.SelectionType = 'open';
ax.ButtonDownFcn(ax,[]);
fig.SelectionType = 'normal';
assert(app.ActiveTab == "Series" && m.Selection.ConditionKey == want, ...
    'A double-click on a column (SelectionType ''open'') did not open the Series tab on that row.');
app.activateTab("Grid");
% the context menu
ax = v.Handles.Columns(1).Axes;
cm = ax.ContextMenu;
need = ["AnalysisGridMenuAtLevel","AnalysisGridMenuNoResponse","AnalysisGridMenuAccept", ...
    "AnalysisGridMenuOverride","AnalysisGridMenuOverrideAuto","AnalysisGridMenuOverrideResponse", ...
    "AnalysisGridMenuOverrideNone","AnalysisGridMenuOpenSeries","AnalysisGridMenuOpenTrials", ...
    "AnalysisMenuFigureExportItem","AnalysisMenuCopyDataItem","AnalysisMenuCopyImageItem"];
tags = string(get(findall(cm,'Type','uimenu'),'Tag'));
assert(all(ismember(need,tags)),'The context menu lacks %s.',strjoin(need(~ismember(need,tags)),', '));
v.clickAt(sk1,4,"alt");
assert(v.MenuKey == D.Cond(1,5),'A right-click did not make its row the menu''s condition.');
cm.ContextMenuOpeningFcn(cm,[]);
at = findall(cm,'Tag','AnalysisGridMenuAtLevel');
assert(v.MenuKey ~= "" && contains(string(at.Text),"Set threshold at") && contains(string(at.Text),"dB (t)"), ...
    'Opening the menu did not name the level it acts on.');
ck = D.Cond(1,5);
v.menuAction("atLevel",ck);
row = thrRow(m,sk1);
assert(row.Decision == "manual" && row.FinalHi == 80,'menuAction atLevel did not set the threshold at 80 dB.');
v.menuAction("noResponse",ck);
assert(thrRow(m,sk1).Decision == "noresponse",'menuAction noResponse.');
v.menuAction("accept",ck);
assert(thrRow(m,sk1).Decision == "accepted",'menuAction accept.');
v.menuAction("overrideNone",ck);
assert(overrideOf(m,ck) == 0,'menuAction overrideNone.');
v.menuAction("overrideResponse",ck);
assert(overrideOf(m,ck) == 1,'menuAction overrideResponse.');
v.menuAction("overrideAuto",ck);
assert(isnan(overrideOf(m,ck)),'menuAction overrideAuto.');
v.menuAction("openTrials",D.Cond(2,3));
assert(app.ActiveTab == "Trials" && m.Selection.ConditionKey == D.Cond(2,3),'menuAction openTrials.');
app.activateTab("Grid");
v.menuAction("openSeries",D.Cond(2,2));
assert(app.ActiveTab == "Series",'menuAction openSeries.');
app.activateTab("Grid");
try
    v.menuAction("bogus",ck);
    error('verify:noThrow','A bad action did not throw.');
catch me
    assert(strcmp(me.identifier,'mabr:ui:analysis:GridView:badAction'),'A bad action threw %s.',me.identifier);
end
m.clearDecision(sk1);
fprintf(['  PASS Part G: selectAt; clickAt''s row bands reach halfway; a double-click opens Series; ' ...
    'the axes'' ButtonDownFcn selects (normal) and opens Series (open); the context menu''s items ' ...
    'and every menuAction\n']);
end

% =========================================================================
%  Part L -- the threshold by hand (a column's divider dragged)
% =========================================================================
function partL_drag(app,v)
% Through the mouse's own callbacks: the figure's CurrentPoint is set
% (setPoint) and the column's ButtonDownFcn, then the window's motion / up /
% key callbacks are called as MATLAB would call them.
m = app.Model;
fig = app.Figure;
app.activateTab("Grid");
D = v.Grid;
sk = D.Keys(1);
if thrRow(m,sk).Decision ~= "", m.clearDecision(sk); end
D = v.Grid;
C = v.Handles.Columns(1);
ax = C.Axes;
assert(isequal(D.Levels(:).',0:20:80),'(Part L needs the 0:20:80 dB rows)');
Y = D.RowY(:).';
mid = @(a,b) (Y(a) + Y(b))/2;
u = " " + mabr.ui.analysis.SeriesView.levelUnitOf(D.LevelParam,m.Session);
green = mabr.ui.analysis.Style.FinalGreen;
x8 = 8;
up0 = fig.WindowButtonUpFcn;  key0 = fig.WindowKeyPressFcn;  mot0 = fig.WindowButtonMotionFcn;
fig.SelectionType = 'normal';

% each column's grip; the pointer over the divider
[y0,onLine] = v.thresholdHandleY(sk);
assert(onLine && abs(y0 - C.Final.YData(1)) < 1e-12 && strcmp(C.Grip.Visible,'on') && C.Grip.YData == y0 && ...
    isequal(C.Grip.MarkerFaceColor,green),'The column''s final threshold has no grip at its divider''s end.');
assert(all(arrayfun(@(c) strcmp(c.Grip.Visible,'on'),v.Handles.Columns)),'A column has no grip.');
setPoint(fig,ax,x8,y0);
fig.WindowButtonMotionFcn(fig,[]);
assert(v.hoverPointer() == "top" && strcmp(fig.Pointer,'top'),'Over a column''s divider the pointer is not the resize arrows.');
setPoint(fig,ax,x8,Y(1));
fig.WindowButtonMotionFcn(fig,[]);
assert(v.hoverPointer() == "" && strcmp(fig.Pointer,'arrow'),'Away from the divider the pointer did not go back.');

% a drag snaps half way between two rows: manual at the louder
nU = numel(m.undoHistory());  nE = height(m.Session.EditLog);
setPoint(fig,ax,x8,y0);
ax.ButtonDownFcn(ax,[]);
assert(v.ThresholdDragging,'A press on a column''s divider did not take it.');
setPoint(fig,ax,x8,Y(2) + 0.3*(Y(3) - Y(2)));               % between 20 and 40 dB
fig.WindowButtonMotionFcn(fig,[]);
assert(v.ThresholdReadout == "Threshold 30" + u && abs(C.Final.YData(1) - mid(2,3)) < 1e-12 && ...
    isscalar(findall(ax,'Tag','GridThresholdReadout')),'Mid-drag the column''s divider is not snapped half way ("%s").', ...
    v.ThresholdReadout);
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,sk);
L = m.Session.EditLog;
assert(~v.ThresholdDragging && r.Decision == "manual" && string(r.ManualKind) == "level" && r.ManualValue == 40 && ...
    r.FinalCensored == "interval" && r.Final == 30 && numel(m.undoHistory()) == nU + 1 && height(L) == nE + 1 && ...
    string(L.Action(end)) == "setDecision" && contains(string(L.New(end)),"manual"), ...
    'The drop between 20 and 40 dB did not set the threshold at 40 dB as one undo step and one EditLog row.');
assert(abs(C.Final.YData(1) - mid(2,3)) < 1e-12 && isempty(findall(ax,'Tag','GridThresholdReadout')) && ...
    isequal(fig.WindowButtonUpFcn,up0) && isequal(fig.WindowKeyPressFcn,key0) && ...
    isequal(fig.WindowButtonMotionFcn,mot0),'After the drop the divider is not snapped, or the window kept the drag''s callbacks.');
L1 = v.Handles.Columns(1).Lines;
assert(strcmp(L1(1).Line.LineStyle,'--') && strcmp(L1(2).Line.LineStyle,'--') && strcmp(L1(4).Line.LineStyle,'-'), ...
    'The traces below the dropped threshold are not dashed.');

% Alt: the exact value
setPoint(fig,ax,x8,C.Final.YData(1));
ax.ButtonDownFcn(ax,[]);
fig.WindowKeyPressFcn(fig,keyEvt('alt',{'alt'}));
setPoint(fig,ax,x8,Y(3) + 0.37*(Y(4) - Y(3)));
fig.WindowButtonMotionFcn(fig,[]);
cp = ax.CurrentPoint;
vx = round(interp1(Y,D.Levels,cp(1,2))*10)/10;
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,sk);
assert(r.Decision == "manual" && string(r.ManualKind) == "value" && abs(r.ManualValue - vx) < 1e-9 && ...
    r.FinalCensored == "none",'Alt did not set the exact value %g (%s %g).',vx,r.Decision,r.ManualValue);

% above the loudest level: no response (NR); below the quietest: all respond
v.dragThreshold(sk,Y(end) + 0.3*D.Pitch);
r = thrRow(m,sk);
lab = v.Handles.Columns(1).FinalLabel;
assert(r.Decision == "noresponse" && string(lab.String) == "NR" && strcmp(lab.Visible,'on') && ...
    abs(C.Final.YData(1) - (Y(end) + D.Pitch/2)) < 1e-12,'A drop above the loudest row is not no response (NR).');
v.dragThreshold(sk,Y(1) - 0.3*D.Pitch);
r = thrRow(m,sk);
assert(r.Decision == "allrespond" && abs(C.Final.YData(1) - (Y(1) - D.Pitch/2)) < 1e-12, ...
    'A drop below the quietest row is not all respond.');

% Esc cancels: the app's key, and the window's own
nU = numel(m.undoHistory());
yb = C.Final.YData(1);
for way = 1:2
    setPoint(fig,ax,x8,yb);
    ax.ButtonDownFcn(ax,[]);
    setPoint(fig,ax,x8,mid(3,4));
    fig.WindowButtonMotionFcn(fig,[]);
    assert(abs(C.Final.YData(1) - mid(3,4)) < 1e-12,'(the preview did not follow the pointer)');
    if way == 1
        press(app,'escape');
    else
        fig.WindowKeyPressFcn(fig,keyEvt('escape'));
    end
    assert(~v.ThresholdDragging && thrRow(m,sk).Decision == "allrespond" && numel(m.undoHistory()) == nU && ...
        abs(C.Final.YData(1) - yb) < 1e-12 && isequal(fig.WindowButtonUpFcn,up0), ...
        'Esc (way %d) did not cancel the column''s drag.',way);
end

% Ctrl+Z undoes a drop
press(app,'z',{'control'});
assert(thrRow(m,sk).Decision == "noresponse",'Ctrl+Z did not undo the all-respond drop.');
m.undo();  m.undo();  m.undo();
assert(thrRow(m,sk).Decision == "",'The drops were not all undone.');

% a press on the divider let go where it was selects the row under it (2 px
% below the divider); a double-click there opens the Series tab
yF = C.Final.YData(1);
pp = getpixelposition(ax);
yc = yF - 2*diff(ax.YLim)/pp(4);
want = v.rowAt(1,yc);
v.selectAt(D.Keys(2),40);
nU = numel(m.undoHistory());
setPoint(fig,ax,x8,yc);
ax.ButtonDownFcn(ax,[]);
assert(v.ThresholdDragging,'A press 2 px from the column''s divider did not take it.');
fig.WindowButtonUpFcn(fig,[]);
assert(~v.ThresholdDragging && m.Selection.ConditionKey == want && numel(m.undoHistory()) == nU, ...
    'A press on the divider let go where it was did not select the row under it.');
v.selectAt(D.Keys(2),40);
setPoint(fig,ax,x8,yF);
fig.SelectionType = 'open';
ax.ButtonDownFcn(ax,[]);
fig.SelectionType = 'normal';
assert(~v.ThresholdDragging && app.ActiveTab == "Series" && numel(m.undoHistory()) == nU, ...
    'A double-click on the divider did not open the Series tab.');
app.activateTab("Grid");

% the Threshold layer off: no grip, nothing to drag
v.applySettings(struct('Threshold',false));
C = v.Handles.Columns(1);
assert(strcmp(C.Grip.Visible,'off') && isnan(v.thresholdHandleY(sk)), ...
    'With the Threshold layer off a column still offers its divider.');
threw = "";
try
    v.dragThreshold(sk,1);
catch me
    threw = string(me.identifier);
end
assert(threw == "mabr:ui:analysis:GridView:noThreshold",'dragThreshold with the layer off gave "%s".',threw);
v.applySettings(struct('Threshold',true));
assert(strcmp(v.Handles.Columns(1).Grip.Visible,'on'),'The grip did not come back with the layer.');
% the hint strip starts with the gesture, and its tooltip says it in full
assert(startsWith(mabr.ui.analysis.Commands.hint("grid"),"drag green line") && ...
    contains(string(v.Handles.Hints.Tooltip),mabr.ui.analysis.ThresholdDrag.Hint), ...
    'The Grid''s hint strip does not name the threshold drag.');
fprintf(['  PASS Part L: each column''s grip and pointer; dragged (the callbacks, CurrentPoint) a divider ' ...
    'snaps half way -- manual at the louder level, one undo step, an EditLog row; Alt exact; above/below ' ...
    'no response (NR) / all respond; Esc (app and window) cancels; Ctrl+Z undoes; a press on it let go ' ...
    'selects, a double-click opens Series; nothing to drag with the layer off; the hint strip names it\n']);
end

% =========================================================================
%  Part H -- a ragged grid; an unanalysed session
% =========================================================================
function partH_ragged(app,v,k)
m = app.Model;
m.openSession(k.Rag);
assert(m.Status.State == "not-analysed",'The ragged session is not unanalysed (%s).',m.Status.State);
ban = v.Handles.Banner;
assert(strcmp(ban.Visible,'on') && string(ban.Text) == "Not analysed — press Analyse (Ctrl+Enter)", ...
    'An unanalysed session has no banner.');
D = v.Grid;
j = find(contains(D.Keys,"Frequency=16"),1);
r = find(D.Levels == 40,1);
assert(~isempty(j) && ~isempty(r) && D.Cond(j,r) == "",'The 16 kHz 40 dB condition is not missing.');
R = v.Handles.Columns(j).Lines(r);
assert(strcmp(R.Missing.Visible,'on') && string(R.Missing.String) == "not recorded" && ...
    all(isnan(R.Line.YData)),'A missing condition is not "not recorded" (or has a trace).');
o = find(~contains(D.Keys,"Frequency=16"),1);
assert(strcmp(v.Handles.Columns(o).Lines(r).Missing.Visible,'off') && ...
    any(isfinite(v.Handles.Columns(o).Lines(r).Line.YData)),'The recorded 4 kHz 40 dB row is not drawn.');
sel = m.Selection.ConditionKey;
v.selectAt(D.Keys(j),40);
assert(m.Selection.ConditionKey == sel,'Selecting a missing row changed the selection.');
st = findall(app.Figure,'Tag','AnalysisStatusText');
assert(contains(string(st.Text),"not recorded"),'The status line does not say the row was not recorded.');
assert(isempty(v.Handles.Columns(1).Final.XData) || strcmp(v.Handles.Columns(1).Final.Visible,'off'), ...
    'An unanalysed session shows a threshold.');
m.openSession(k.Base);
assert(strcmp(ban.Visible,'off'),'The banner stays for an analysed session.');
fprintf('  PASS Part H: a missing level is "not recorded" with no trace; an unanalysed session shows its banner\n');
end

% =========================================================================
%  Part I -- the sound conduction delay (13 A9)
% =========================================================================
function partI_latency(app,v,k)
m = app.Model;
fig = app.Figure;
h = v.Handles.Columns(1).Lines(5).Line;
ax = v.Handles.Columns(1).Axes;
note = findall(fig,'Tag','AnalysisGridTimeNote');
x0 = h.XData;  y0 = h.YData;  lab0 = string(ax.XLabel.String);
sh0 = v.Handles.Columns(1).Shade.Vertices;
assert(lab0 == "Time re onset (ms)" && strcmp(note.Visible,'off'),'With no delay the axis is not "re onset".');
S = m.Session;
assert(isequal(x0(:),S.Time(v.Grid.Win)),'With no delay the traces are not drawn at the recorded times.');

m.setSessionOverrides(k.Base,struct('ConductionDelay',0.25));
S = m.Session;
D = v.Grid;
assert(isvalid(h) && h == v.Handles.Columns(1).Lines(5).Line,'The delay rebuilt the axes.');
want = S.Time(:) - 0.25;
want = want(want >= D.XLim(1) - 1e-9 & want <= D.XLim(2) + 1e-9);
assert(max(abs(h.XData(:) - want)) < 1e-12,'The traces are not in ear time (raw - 0.25 ms).');
assert(string(ax.XLabel.String) == "Time re sound arrival (ms)" && contains(string(ax.XLabel.UserData),"0.25"), ...
    'The time axis does not read "Time re sound arrival (ms)" with the delay named.');
assert(strcmp(note.Visible,'on') && contains(string(note.Text),"sound arrival") && ...
    contains(string(note.Tooltip),"0.25"),'The note under the grid does not name the delay.');
rw = S.ResponseWindow - 0.25;
V = v.Handles.Columns(1).Shade.Vertices;
assert(abs(min(V(:,1)) - max(rw(1),D.XLim(1))) < 1e-12 && abs(max(V(:,1)) - min(rw(2),D.XLim(2))) < 1e-12, ...
    'The response window is not shaded in ear time.');
P = S.Peaks;
pk = findobj(ax,'Tag','GridPeaks');
pk = pk(arrayfun(@(p) p.UserData.Wave == "I" && p.UserData.Kind == "P",pk));
ck = D.Cond(1,5);
lat = P.PeakLatency(string(P.Key) == ck & string(P.Wave) == "I");
if isfinite(lat)
    assert(any(abs(pk.XData - (lat - 0.25)) < 1e-12),'Wave I is not marked at its latency re sound arrival.');
end

% a system time offset alone is not sound arrival: "re onset", less it
m.setSessionOverrides(k.Base,struct('ConductionDelay',NaN,'TimeOffset',0.1));
want = S.Time(:) - 0.1;
want = want(want >= v.Grid.XLim(1) - 1e-9 & want <= v.Grid.XLim(2) + 1e-9);
assert(max(abs(h.XData(:) - want)) < 1e-12,'The traces are not drawn less a 0.1 ms system offset.');
assert(startsWith(string(ax.XLabel.String),"Time re onset (ms) − 0.1") && strcmp(note.Visible,'on') && ...
    contains(string(note.Text),"0.1 ms system offset"),'A system offset alone is not named on the axis.');

m.setSessionOverrides(k.Base,struct('TimeOffset',NaN));
assert(isequal(h.XData,x0) && max(abs(h.YData - y0)) < 1e-9 && string(ax.XLabel.String) == lab0 && ...
    strcmp(note.Visible,'off') && isequal(v.Handles.Columns(1).Shade.Vertices,sh0), ...
    'With the delay cleared the grid is not as before.');
m.flush();
fprintf(['  PASS Part I: a 0.25 ms delay moves traces, response window and peaks to ear time, the axis ' ...
    'reads "Time re sound arrival (ms)" and the note names the delay; a 0.1 ms system offset alone ' ...
    'reads "re onset" less it; cleared, nothing differs\n']);
end

% =========================================================================
%  Part K -- the level direction (a thresholds-only refit)
% =========================================================================
function partK_direction(app,v)
% LevelDirection is a thresholds setting, so Settings ▸ "descending" re-fits
% the thresholds alone and arrives as ResultsChanged(thresholds) -- the event
% that redraws only the dividers. The stack must still turn over (the
% largest value, the quietest on an attenuation axis, at the bottom) and the
% dashed rows follow the descending rule the session now uses.
m = app.Model;
s0 = m.Settings;
s = s0;
s.LevelDirection = "descending";
m.setSettings(s,Refit=true);
S = m.Session;
assert(S.Settings.LevelDirection == "descending",'(the refit did not adopt the descending direction)');
D = v.Grid;
assert(D.Descending && isequal(D.Levels(:),sort(D.Levels(:),'descend')), ...
    'LevelDirection descending did not turn the stack over (rows bottom to top: %s).',mat2str(D.Levels.'));
lab = string(v.Handles.Columns(1).Axes.YTickLabel).';
assert(isequal(lab,string(D.Levels.')),'The level labels do not follow the turned stack.');
sel = m.Selection.ConditionKey;
for j = 1:numel(D.Keys)
    T = S.Thresholds(string(S.Thresholds.Key) == D.Keys(j),:);
    fc = string(T.FinalCensored);  if ismissing(fc), fc = ""; end
    want = mabr.analysis.SeriesThreshold.belowThreshold(D.Levels.',T.Final,fc,T.FinalLo, ...
        Direction="descending",FinalHi=T.FinalHi);
    want(D.Cond(j,:) == "") = false;
    assert(isequal(D.Below(j,:),want),'Column %d: the dashed rows do not follow the descending rule.',j);
    L = v.Handles.Columns(j).Lines;
    for r = 1:numel(L)
        if L(r).ConditionKey == "" || L(r).ConditionKey == sel, continue; end
        assert(strcmp(L(r).Line.LineStyle,'--') == want(r), ...
            'Column %d row %d is drawn %s against the descending rule.',j,r,L(r).Line.LineStyle);
    end
end
% the decisions on the turned stack: no response is "NR" above the top row
% (the loudest) with every trace dashed, all respond under the bottom row
sk = D.Keys(1);
m.setNoResponse(sk);
[yF,~,vis] = dividers(v,1);
lab = v.Handles.Columns(1).FinalLabel;
assert(vis(1) && abs(yF - (D.RowY(end) + D.Pitch/2)) < 1e-12 && string(lab.String) == "NR" && ...
    strcmp(lab.Visible,'on') && all(v.Grid.Below(1,:)), ...
    'Attenuation stack: no response is not "NR" above the top row with every row below threshold.');
m.setAllRespond(sk);
[yF,~,vis] = dividers(v,1);
assert(vis(1) && abs(yF - (D.RowY(1) - D.Pitch/2)) < 1e-12 && strcmp(lab.Visible,'off') && ...
    ~any(v.Grid.Below(1,:)),'Attenuation stack: all respond is not under the bottom row with no row below.');
m.clearDecision(sk);
% dragged on the turned stack (the mouse's callbacks): each preview stands
% where its release leaves the divider -- NR above the top row, all respond
% under the bottom -- and reads in the numbers' own terms (≤ 0 / > 80: the
% censoring of the numbers, as the column title writes it)
fig = app.Figure;
fig.SelectionType = 'normal';
D = v.Grid;
C = v.Handles.Columns(1);
ax = C.Axes;
u = " " + mabr.ui.analysis.SeriesView.levelUnitOf(D.LevelParam,m.Session);
[y0,onLine] = v.thresholdHandleY(sk);
xp = 8;  if ~onLine, xp = D.XLim(2); end
setPoint(fig,ax,xp,y0);
ax.ButtonDownFcn(ax,[]);
setPoint(fig,ax,8,D.RowY(end) + 0.3*D.Pitch);
fig.WindowButtonMotionFcn(fig,[]);
assert(v.ThresholdDragging && abs(C.Final.YData(1) - (D.RowY(end) + D.Pitch/2)) < 1e-12 && ...
    strcmp(C.FinalLabel.Visible,'on') && v.ThresholdReadout == "No response (≤ 0" + u + ")", ...
    'Dragged above the top row of the turned stack, the preview is not NR above it ("%s").',v.ThresholdReadout);
setPoint(fig,ax,8,D.RowY(1) - 0.3*D.Pitch);
fig.WindowButtonMotionFcn(fig,[]);
assert(abs(C.Final.YData(1) - (D.RowY(1) - D.Pitch/2)) < 1e-12 && strcmp(C.FinalLabel.Visible,'off') && ...
    v.ThresholdReadout == "All respond (> 80" + u + ")", ...
    'Dragged under the bottom row of the turned stack, the preview is not all respond under it ("%s").', ...
    v.ThresholdReadout);
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,sk);
assert(~v.ThresholdDragging && r.Decision == "allrespond" && abs(C.Final.YData(1) - (D.RowY(1) - D.Pitch/2)) < 1e-12, ...
    'The release under the bottom row of the turned stack is not all respond where its preview stood.');
m.undo();
m.setSettings(s0,Refit=true);
D = v.Grid;
assert(~D.Descending && issorted(D.Levels),'Back to "auto", the stack did not turn back.');
fprintf(['  PASS Part K: LevelDirection descending (a thresholds-only refit) turns the stack over, the ' ...
    'dashed rows follow the descending rule, NR sits above the loudest row and all-respond under ' ...
    'the quietest -- dragged there too, each preview where its release leaves it ("≤ 0", "> 80"); ' ...
    'back to auto it turns back\n']);
end

% =========================================================================
%  Part J -- the look controls (and the only pref writes)
% =========================================================================
function partJ_controls(app,v,prefs0)
m = app.Model;
fig = app.Figure;
assert(~ispref('MABR','OfflineAnalysisGrid'),'The look pref exists before any control was used.');
v.applySettings(mabr.ui.analysis.GridView.factoryDefaults());
S = m.Session;
C1 = v.Handles.Columns(1);
h = C1.Lines(5).Line;          % 80 dB
y0 = h.YData;
ck = v.Grid.Cond(1,5);

ws = findall(fig,'Tag','AnalysisGridWindowStart');  we = findall(fig,'Tag','AnalysisGridWindowEnd');
drive(ws,0);  drive(we,8);
assert(isvalid(h) && h == v.Handles.Columns(1).Lines(5).Line,'The window rebuilt the axes.');
assert(min(h.XData) >= -1e-9 && max(h.XData) <= 8 + 1e-9 && isequal(C1.Axes.XLim,[0 8]), ...
    'The window controls do not crop the time axis to [0 8].');
win = S.Time >= -1e-9 & S.Time <= 8 + 1e-9;
% a window ending before it starts is refused, and the field shows the
% window in force again (not the number typed, nor both ends reset)
st = findall(fig,'Tag','AnalysisStatusText');
drive(ws,9);
assert(ws.Value == 0 && we.Value == 8 && v.ViewLook.WindowStart == 0 && v.ViewLook.WindowEnd == 8 && ...
    isequal(C1.Axes.XLim,[0 8]) && contains(string(st.Text),"must end after it starts"), ...
    'A window ending before it starts was not refused with the field put back (start field %g).',ws.Value);

sc = findall(fig,'Tag','AnalysisGridScale');  fx = findall(fig,'Tag','AnalysisGridFixed');
drive(fx,5);
drive(sc,'fixed');
mu = S.conditionMean(ck,"balanced");
want = 4 + mu(win)/(5*1e-6);
assert(max(abs(h.YData(:) - want(:))) < 1e-9,'Fixed 5 µV: the trace is not row + mean/5 µV.');
drive(sc,'global');
cs = v.Grid.ColScale;
assert(all(cs == max(cs)),'Global: the columns do not share one scale.');
drive(sc,'column');
cs = v.Grid.ColScale;
amp = max(v.Grid.Amp,[],2);
assert(all(abs(cs - amp) < 1e-15),'Per column: a column''s scale is not its largest mean.');

pol = findall(fig,'Tag','AnalysisGridPolarity');
yb = h.YData;
drive(pol,'positive');
mp = S.conditionMean(ck,"positive");
want = 4 + mp(win)/v.Grid.Den(1,5);
assert(~isequal(h.YData,yb) && max(abs(h.YData(:) - want(:))) < 1e-9,'Polarity + does not draw the positive mean.');
drive(pol,'balanced');

bd = findall(fig,'Tag','AnalysisGridBand');
drive(bd,'sem');
B = C1.Band;
assert(strcmp(B.Visible,'on') && size(B.Faces,1) == 5,'SEM: the band does not have one face per trace.');
drive(bd,'none');
assert(strcmp(B.Visible,'off'),'Band None still shows.');

an = findall(fig,'Tag','AnalysisGridAnnotate');
drive(an,'n');
nc = S.Conditions.nClean(S.rowOf(ck));
assert(string(C1.Lines(5).Note.String) == string(nc),'Annotate n does not show the clean sweeps.');
drive(an,'p');
p = S.Conditions.p(S.rowOf(ck));
txt = string(C1.Lines(5).Note.String);
if p < 0.001
    assert(txt == "<.001",'Annotate p.');
else
    assert(abs(str2double(txt) - round(p,3)) < 1e-9,'Annotate p shows %s for p %g.',txt,p);
end
drive(an,'detected');

% Copy data copies what is drawn: the peaks and the threshold while shown...
hd = copyHeader(v);
assert(contains(hd,"peak x") && contains(hd,"final threshold") && ~contains(hd,"significant"), ...
    'Copy data (peaks and threshold on, significance off) has the wrong columns: %s',hd);
for name = ["Significance","Peaks","Threshold"]
    cb = findall(fig,'Tag',"AnalysisGrid" + name);
    drive(cb,~cb.Value);
end
assert(strcmp(C1.Sig.Visible,'on') && all(strcmp(get(C1.Peaks,'Visible'),'off')) && ...
    strcmp(C1.Final.Visible,'off'),'The switches do not show/hide significance, peaks and threshold.');
% ... and not once they are switched off (they were copied while hidden)
hd = copyHeader(v);
hasSig = any(arrayfun(@(c) any(isfinite(c.Sig.YData)),v.Handles.Columns));
assert(~contains(hd,"peak x") && ~contains(hd,"trough x") && ~contains(hd,"final threshold") && ...
    ~contains(hd,"fitted threshold") && contains(hd,"significant") == hasSig, ...
    'Copy data copies a layer that is switched off: %s',hd);
assert(isvalid(h) && h == v.Handles.Columns(1).Lines(5).Line && isvalid(C1.Axes) && ...
    C1.Axes == v.Handles.Columns(1).Axes,'The controls rebuilt the graphics instead of updating them.');
assert(~isequal(h.YData,y0),'The controls did not change what the trace draws.');

% only the look pref was written, with what was chosen
assert(ispref('MABR','OfflineAnalysisGrid'),'The look controls did not remember the look.');
g = getpref('MABR','OfflineAnalysisGrid');
assert(g.WindowStart == 0 && g.WindowEnd == 8 && g.Scale == "column" && g.Fixed == 5 && ...
    g.Polarity == "balanced" && g.Band == "none" && g.Annotate == "detected" && g.Significance && ...
    ~g.Peaks && ~g.Threshold,'The pref does not hold the look chosen.');
d = changedPrefs(prefs0,allPrefs());
assert(isequal(d,"OfflineAnalysisGrid"),'The look controls wrote other prefs: %s',strjoin(d,', '));
% the next view opens on it
d2 = mabr.ui.analysis.GridView.loadDefaults();
assert(d2.WindowStart == 0 && ~d2.Peaks,'loadDefaults does not read the remembered look.');
fprintf(['  PASS Part J: window/scale/polarity/band/annotate/switches drive the drawing with the same ' ...
    'graphics; a reversed window is refused; Copy data copies only the layers shown; only these ' ...
    'controls wrote a pref (OfflineAnalysisGrid)\n']);
end

function hd = copyHeader(v)
% The header row of the grid's Copy data (the clipboard copy is incidental).
txt = splitlines(v.copyData());
hd = txt(1);
end

% =========================================================================
%  helpers
% =========================================================================
function rag = writeRagged(F)
% A third subject's session with the 16 kHz 40 dB file removed, written into
% the fixture's study before the app scans it.
sub = "SUBJ-ID-9003";
folder = fullfile(F.Root,sub,sub + "_Baseline");
mabrtest.SyntheticABR.writeSession(folder,F.Truth,'Subject',sub,'Start',datetime(2026,10,1,12,0,0));
L = dir(fullfile(folder,'*.abr'));
names = string({L.name});
hit = contains(names,"16kHz") & contains(names,"Level-40dB");
assert(nnz(hit) == 1,'Could not find the one 16 kHz 40 dB file to remove (%d).',nnz(hit));
delete(fullfile(folder,names(hit)));
rag = struct('Key',sub + "/" + sub + "_Baseline",'Folder',folder);
end

function key = keyOf(F,part,subject)
key = F.Keys(contains(F.Keys,part) & startsWith(F.Keys,subject));
assert(isscalar(key),'No single fixture session matching %s.',part);
end

function [app,stub] = newApp(F)
stub.Confirm    = @(msg,title,options,default) string(options(1));
stub.Alert      = @(msg,title,icon) [];
stub.Prompt     = @(prompt,title,default) [];
stub.PickFolder = @(start,title) "";
stub.PickFile   = @(filter,title,mode,default) "";
app = mabr.ui.AnalysisApp("",Visible="off",ResultsFolder=F.ResultsFolder, ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false,RememberState=false, ...
    ProgressMode="none",AutoRefresh=false,ConfirmFcn=stub.Confirm,PromptFcn=stub.Prompt, ...
    PickFolderFcn=stub.PickFolder,PickFileFcn=stub.PickFile,AlertFcn=stub.Alert);
end

function closeQuietly(app)
try
    if ~isempty(app) && isvalid(app)
        app.Model.flush();
        delete(app);
    end
catch
end
end

function drive(h,value)
% What a user does to a control: set its value, run its callback.
h.Value = value;
h.ValueChangedFcn(h,[]);
end

function press(app,key,mods,ch)
% A key press, as the figure's WindowKeyPressFcn would deliver it, with the
% plots holding the keyboard (a click on a plot does that).
if nargin < 3, mods = {}; end
if nargin < 4
    ch = key;
    if strlength(string(key)) > 1, ch = ''; end
end
m = app.Model;
m.KeyTarget = "plot";
m.FocusArea = "workspace";
ok = app.dispatchKey(struct('Key',key,'Modifier',{mods},'Character',ch));
assert(ok,'The key %s (%s) was not handled.',key,strjoin(string(mods),'+'));
end

function row = thrRow(m,sk)
T = m.Session.Thresholds;
row = table2struct(T(string(T.Key) == sk,:));
row.Decision = string(row.Decision);
row.FinalCensored = string(row.FinalCensored);
row.Censored = string(row.Censored);
end

function setPoint(fig,ax,x,y)
% Put the mouse at (x,y) in AX's data units, as MATLAB would before a click
% or a move: the figure's CurrentPoint (settable; the axes' follows it) is
% placed and corrected against what the axes then reports (an invisible
% window's layout may still be settling: then a drawnow, and again).
for pass = 1:3
    pos = getpixelposition(ax,true);
    xl = ax.XLim;  yl = ax.YLim;
    sx = pos(3)/diff(xl);  sy = pos(4)/diff(yl);
    p = [pos(1) + (x - xl(1))*sx, pos(2) + (y - yl(1))*sy];
    e = [Inf Inf];
    for k = 1:8
        fig.CurrentPoint = p;
        cp = ax.CurrentPoint;
        e = [x - cp(1,1), y - cp(1,2)];
        if abs(e(1))*sx < 0.25 && abs(e(2))*sy < 0.25, break; end
        p = p + e.*[sx sy];
    end
    if abs(e(1))*sx < 0.5 && abs(e(2))*sy < 0.5, break; end
    drawnow;
end
assert(abs(e(1))*sx < 1 && abs(e(2))*sy < 1,'(the pointer could not be put at %g, %g)',x,y);
end

function e = keyEvt(key,mods)
% A key event as the window's WindowKeyPressFcn receives it.
if nargin < 2, mods = {}; end
e = struct('Key',key,'Modifier',{mods},'Character','');
end

function v = overrideOf(m,ck)
v = NaN;
D = m.Session.DetectionOverrides;
r = find(string(D.Key) == ck,1,'last');
if ~isempty(r), v = double(D.Value(r)); end
end

function [yF,yT,vis] = dividers(v,j)
C = v.Handles.Columns(j);
yF = C.Final.YData(1);  yT = C.Fit.YData(1);
vis = [strcmp(C.Final.Visible,'on') strcmp(C.Fit.Visible,'on')];
end

function s = allPrefs()
s = struct();
if ispref('MABR'), s = getpref('MABR'); end
end

function d = changedPrefs(a,b)
na = string(fieldnames(a));  nb = string(fieldnames(b));
d = setxor(na,nb);
for n = reshape(intersect(na,nb),1,[])
    if ~isequaln(a.(n),b.(n)), d(end+1) = n; end %#ok<AGROW>
end
d = reshape(unique(d),1,[]);
d(startsWith(d,"WindowPos_")) = [];       % (WindowPos.restore's first read; not the grid's)
end
