function verify_offline_series()
% verify_offline_series  The analysis app's Series tab: the list, the level stack, threshold and peak curation, the side plots.
%
%   Drives mabr.ui.analysis.SeriesView inside an invisible mabr.ui.AnalysisApp
%   over mabrtest.OfflineFixture (plus three sessions written here: one with
%   a single level, one whose level parameter cannot be told, one on an
%   attenuation axis), the way a user
%   would: the controls (Value + ValueChangedFcn, ButtonPushedFcn), the key
%   dispatcher, and the view's public gestures (clickAt, dragPeak,
%   menuAction).
%
%     Part A  the pure pieces: flag codes, the fit text with its interval, the
%             decision sentence, the custom criterion modes, a junk look pref
%             read forgivingly
%     Part B  empty states: no session, a session of single-level series, a
%             session with no level parameter (and its Settings… button)
%     Part C  entering a series selects the level next to its threshold (11
%             sec. 7.1, worked out here independently); LevelMemory brings a
%             series back at the level last used; the list click selects
%     Part D  the stack (a line per level, the current one black, undetected
%             levels dashed, the detection glyphs and counts, the Final and
%             fit dividers at the right heights); every threshold button and
%             its key give the same Decision, list glyph and Final text, each
%             an undo step; the note button and Ctrl+N open the note editor;
%             the value field sets a manual value; the context menu
%     Part E  the method dropdown opens on perm-glm (13 A1) and changes the
%             PROJECT's method: the open session is re-fitted, its detection
%             is not re-run, the other sessions become out of date and none
%             is re-run; the custom row shows only for "custom" with the
%             criterion's unit; the evidence plot per method family (p-methods:
%             detections and -log10 p beside alpha; graded: the metric and its
%             criterion); the value field follows a re-fit, never a typed
%             value; Compare methods
%     Part F  the audiogram: frequency on a log axis, the series without a
%             frequency listed beneath in words (no NaN on the log axis);
%             Compare with, and blind review hiding it
%     Part G  peaks: 1-5 / Shift+1-5 select, a click snaps to the nearest
%             extremum, a press on the marker without moving changes nothing,
%             dragPeak places exactly, Alt/Shift+arrow nudges a sample, the
%             arrows move to candidates only while a point is selected (else
%             change series), Delete / Shift+Delete absent, Backspace revert,
%             p / u / Shift+U; the wave matrix (bold manual cells, "—" absent,
%             loudest first), its cell selection, PeaksShow and the I/O and
%             latency plots; Bootstrap loads the raw data and fills the SE
%             columns; "Use current picks as wave windows" updates the
%             project's waves
%     Part H  the sound conduction delay (13 A9): with 0.25 ms the stack reads
%             "Time re sound arrival (ms)" and names the delay, traces,
%             response window, picks and wave windows are in ear time (the
%             windows are written and searched in the recording's time, so
%             they are drawn 0.25 ms earlier and each still holds its pick),
%             the matrix and the latency plot show reported (ear-time)
%             latencies, a drag stores raw time, "Use current picks as wave
%             windows" stores windows in the recording's time; cleared,
%             nothing differs
%     Part J  an attenuation axis (a larger number is quieter): the loudest
%             level on top, no response -- "left" of the numbers there --
%             the NR divider above it and the evidence's arrow at the top,
%             all respond the divider below the quietest; the divider
%             dragged there previews exactly where its release leaves it
%     Part K  a Level parameter that is not a sound level (Frequency): no
%             series on the audiogram, each listed beneath after the reason,
%             the level axis in kHz; back on Level, the audiogram as before
%     Part L  the threshold by hand, through the mouse's own callbacks (the
%             figure's CurrentPoint set, the axes' ButtonDownFcn, the
%             window's motion / up / key callbacks): the divider's grip and
%             the hover pointer; a drag SNAPS half way between two levels
%             (Decision manual, ManualKind level, an undo step, an EditLog
%             row) with a live readout; Alt gives the exact value; above the
%             loudest level no response, below the quietest all respond; Esc
%             (the app's and the window's) cancels; Ctrl+Z undoes; a press on
%             the divider let go where it was still selects the level under
%             it, a click elsewhere selects, the selected wave point's drag
%             still moves the point; the evidence plot's band and green
%             line (the hand over the band, never through the Peaks
%             sub-tab); a series with no final threshold offers a hollow grip;
%             F1 and the hint strip name the gesture
%     Part M  a time offset changed alone: the status line says the peak
%             latencies are reported at the new offset and no threshold
%             changed (none did); Compare methods gives each method's flags
%     Part I  the look controls (polarity, normalise, peaks show, plot kind,
%             side tab) -- and only they -- write the pref
%             OfflineAnalysisSeries; the keys n / + / Ctrl+0 redraw in place;
%             the A6 button pictures; the hint strip; the stack's margins
%             are pixels (a narrow window clips no label)
%
%   No hardware, no parallel pool, no modal dialog, no timer; tempdir only;
%   every MABR pref the app may write is restored (mabrtest.prefGuard).
%
%   See also mabr.ui.analysis.SeriesView, verify_offline_app, mabrtest.OfflineFixture

% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_series ==\n');
tAll  = tic;
figs0 = findall(groot,'Type','figure');
guard = mabrtest.prefGuard(mabr.ui.AnalysisApp.prefKeys(),Clear=true); %#ok<NASGU>

partA_static();

F = mabrtest.OfflineFixture.make(Subjects="SUBJ-ID-9001");
x = writeExtra(F);
fprintf('  (fixture and three extra sessions written in %.1f s)\n',toc(tAll));
app = newApp(F);
closer = mabrtest.OfflineFixture.closer(app,F); %#ok<NASGU> (the app, THEN the fixture's folders)
app.Figure.Position = [40 40 1500 900];
app.openRoot(F.Root);
k = struct('Base',keyOf(F,"_Baseline","SUBJ-ID-9001"),'Two',keyOf(F,"_2weeks","SUBJ-ID-9001"), ...
    'Mixed',keyOf(F,"T140000","SUBJ-ID-9001"),'Single',x.Single,'NoLevel',x.NoLevel, ...
    'Atten',x.Atten);
prefs0 = allPrefs();
fprintf('  (app open on the study in %.1f s)\n',toc(tAll));

took = strings(1,0);
t0 = tic;  v = partB_empty(app,k);           took(end+1) = sprintf("B %.1f",toc(t0));
t0 = tic;  partC_enter(app,v);             took(end+1) = sprintf("C %.1f",toc(t0));
t0 = tic;  partD_curation(app,v);            took(end+1) = sprintf("D %.1f",toc(t0));
t0 = tic;  partE_method(app,v,k);            took(end+1) = sprintf("E %.1f",toc(t0));
t0 = tic;  partF_audiogram(app,v,k);         took(end+1) = sprintf("F %.1f",toc(t0));
t0 = tic;  partG_peaks(app,v);             took(end+1) = sprintf("G %.1f",toc(t0));
t0 = tic;  partH_delay(app,v,k);             took(end+1) = sprintf("H %.1f",toc(t0));
t0 = tic;  partJ_attenuation(app,v,k);       took(end+1) = sprintf("J %.1f",toc(t0));
t0 = tic;  partK_levelAxis(app,v,k);         took(end+1) = sprintf("K %.1f",toc(t0));
t0 = tic;  partL_drag(app,v,k);              took(end+1) = sprintf("L %.1f",toc(t0));
t0 = tic;  partM_report(app,k);              took(end+1) = sprintf("M %.1f",toc(t0));
d = changedPrefs(prefs0,allPrefs());
assert(isempty(d),'Script-driven Series use (gestures, keys, buttons) wrote a pref: %s',strjoin(d,', '));
fprintf('  PASS prefs: gestures, keys and curation buttons wrote no pref\n');
t0 = tic;  partI_look(app,v,prefs0);         took(end+1) = sprintf("I %.1f",toc(t0));
fprintf('  (seconds per part: %s)\n',strjoin(took,', '));

clear closer
closeQuietly(app);

% ---- leaks ------------------------------------------------------------
drawnow;
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_series left a figure open.');
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_series PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Part A -- the pure pieces
% =========================================================================
function partA_static()
V = 'mabr.ui.analysis.SeriesView';
c = feval([V '.flagCodes'],"non-monotone; wide CI; miss above threshold");
assert(c == "NM W MA",'Flag codes: "%s".',c);
assert(feval([V '.flagCodes'],"") == "" && feval([V '.flagCodes'],string(missing)) == "", ...
    'An empty flag text has codes.');
row = struct('Threshold',34.9,'Censored',"none",'ThrLo',34.9,'ThrHi',34.9,'CILower',31.2,'CIUpper',38);
s = feval([V '.fitText'],row);
assert(startsWith(s,"34.9") && contains(s,"[31.2–38]"),'The fit text "%s" lacks its interval.',s);
row = struct('Threshold',Inf,'Censored',"right",'ThrLo',80,'ThrHi',NaN);
assert(feval([V '.fitText'],row) == ">80",'A right-censored fit is not ">80".');
row = struct('Decision',"manual",'ManualValue',40,'ManualKind',"level",'ReviewedBy',"dstolz", ...
    'ReviewedAt',datetime(2026,10,1,15,42,0),'Final',40,'FinalCensored',"interval",'FinalLo',20, ...
    'FinalHi',40,'Flags',"miss above threshold",'Note',"ear plug");
s = feval([V '.stateText'],row);
assert(startsWith(s,"Decision: manual 40 dB (lowest level with a response) by dstolz 15:42") && ...
    contains(s,"Final " + mabr.ui.analysis.Style.formatThreshold(row)) && ...
    contains(s,"Flags: miss above threshold") && contains(s,"Note: ear plug"), ...
    'The decision sentence is wrong: "%s".',s);
md = @(a,b) feval([V '.modeFor'],a,b);
assert(md("detection","descending") == "p" && md("xcorr","descending") == "absolute" && ...
    md("detection","glm") == "probability" && md("splithalf","presto") == "absolute" && ...
    md("snr","sigmoid") == "fraction",'The custom criterion modes are wrong.');
setpref('MABR','OfflineAnalysisSeries',struct('Polarity',"bogus",'Normalize',"yes",'PeaksShow',"pn", ...
    'PlotKind',7,'SideTab',"Peaks"));
d = feval([V '.loadDefaults']);
f = feval([V '.factoryDefaults']);
assert(d.Polarity == f.Polarity && d.Normalize == f.Normalize && d.PeaksShow == "pn" && ...
    d.PlotKind == f.PlotKind && d.SideTab == "Peaks",'A junk OfflineAnalysisSeries pref was not read forgivingly.');
rmpref('MABR','OfflineAnalysisSeries');
% the audiogram's place for a series: one frequency on a sound-level axis;
% several (a key that fixes none), none, or a level axis that is not a
% sound level (Level parameter = Frequency) list it beneath instead
ag = @(a,b) feval([V '.audiogramX'],a,b);
[xa,wa] = ag(true,[4;4;4]);   [xb,wb] = ag(true,[4;8;16]);
[xc,wc] = ag(true,[NaN;NaN]);  [xd,wd] = ag(false,[4;4]);
assert(xa == 4 && wa == "" && isnan(xb) && wb == "several" && isnan(xc) && wc == "none" && ...
    isnan(xd) && wd == "level",'The audiogram places a series wrongly (%s/%s/%s/%s).',wa,wb,wc,wd);
S0 = struct('LevelUnit',"dB SPL");
lu = @(p) feval([V '.levelUnitOf'],p,S0);
sl = @(p) feval([V '.isSoundLevel'],p,S0);
assert(lu("Level") == "dB SPL" && lu("Attenuation") == "dB SPL" && lu("Frequency") == "kHz" && ...
    lu("Duration") == "" && sl("") && sl("Level") && ~sl("Frequency") && ~sl("Duration"), ...
    'The level axis'' unit is wrong for a Level parameter that is not a sound level.');
% the threshold drag's drop rule, a pure function (ThresholdDrag): rows at
% positions 0..4, louder higher; an attenuation axis is the same rows with
% the numbers falling as they get louder. A row with no bounds (struct())
% still previews a censored drop on the numbers' own side, as
% SeriesThreshold.finalValue censors it, and says so in its terms.
TD = 'mabr.ui.analysis.ThresholdDrag';
oc = @(pos,p,L,alt) feval([TD '.outcome'],pos,p,L,alt);
pr = @(o) feval([TD '.predict'],struct(),o);
ds = @(o,F) feval([TD '.describe'],o,F,"dB");
o = oc(1.3,0:4,0:20:80,false);
assert(o.Kind == "level" && o.Level == 40 && o.Lo == 20 && o.Hi == 40 && o.Dir == 1, ...
    'A drop between 20 and 40 dB is not the decision at 40 dB.');
o = oc(1.37,0:4,0:20:80,true);
assert(o.Kind == "value" && abs(o.Value - 27.4) < 1e-9,'Alt between 20 and 40 dB is not 27.4 (%g).',o.Value);
assert(oc(4.2,0:4,0:20:80,true).Kind == "noresponse" && oc(-0.2,0:4,0:20:80,false).Kind == "allrespond" && ...
    oc(1,0,80,false).Kind == "",'Beyond the rows (Alt or not) is not no response / all respond, or one row decides.');
F = pr(oc(4.3,0:4,0:20:80,false));
assert(F.FinalCensored == "right" && F.FinalLo == 80 && ds(oc(4.3,0:4,0:20:80,false),F) == "No response (> 80 dB)", ...
    'No response on a level axis does not preview as "> 80".');
oN = oc(2.3,0:2,[80 40 0],false);  FN = pr(oN);
oA = oc(-0.3,0:2,[80 40 0],false); FA = pr(oA);
assert(oN.Dir == -1 && FN.FinalCensored == "left" && FN.FinalHi == 0 && ds(oN,FN) == "No response (≤ 0 dB)" && ...
    FA.FinalCensored == "right" && FA.FinalLo == 80 && ds(oA,FA) == "All respond (> 80 dB)", ...
    'On an attenuation axis no response / all respond do not preview on the numbers'' own side (%s / %s).', ...
    ds(oN,FN),ds(oA,FA));
fprintf(['  PASS Part A: flag codes, the fit text with its interval, the decision sentence, the custom ' ...
    'criterion modes; a junk look pref is forgiven; the audiogram''s place for a series; the level ' ...
    'axis'' unit; the threshold drag''s drop rule on level and attenuation axes\n']);
end

% =========================================================================
%  Part B -- empty states
% =========================================================================
function v = partB_empty(app,k)
m = app.Model;
fig = app.Figure;
app.activateTab("Series");
v = app.Views.Series;
assert(isa(v,'mabr.ui.analysis.SeriesView'),'The Series tab is not a SeriesView.');
[txt,on] = emptyState(fig);
assert(on && txt == v.TextNoSession,'With no session the tab does not say "%s" (it says "%s").',v.TextNoSession,txt);

% a session of single-level series: shown like any other -- the list, the
% one trace, the peaks side -- with the banner saying why there is no
% threshold, the evidence plot replaced by the same sentence, and only
% Exclude and the note left of the threshold buttons
m.openSession(k.Single);
m.analyze();
[~,on] = emptyState(fig);
H = v.Handles;
assert(~on && ~isempty(v.Geometry) && isscalar(v.Geometry.Keys), ...
    'A session of single-level series is not shown (empty state %d).',on);
assert(size(H.List.Data,1) == numel(m.seriesKeys()) && strcmp(H.Banner.Visible,'on') && ...
    contains(string(H.Banner.Text),v.TextSingleLevel),'The single-level series lacks its list or banner.');
sl = findall(H.Evidence,'Tag','EvidenceSingleLevel');
assert(isscalar(sl) && string(sl.String) == v.TextSingleLevel && strcmp(H.Evidence.Visible,'off'), ...
    'The single-level evidence plot does not say "%s".',v.TextSingleLevel);
assert(strcmp(H.Accept.Enable,'off') && strcmp(H.AtLevel.Enable,'off') && strcmp(H.Exclude.Enable,'on') && ...
    strcmp(H.Note.Enable,'on'),'A single-level series offers the threshold buttons (or not Exclude/Note).');
assert(size(H.Matrix.Data,1) == 1,'The single-level series'' peaks are not on the Peaks side.');
% (nor a divider to drag: one level decides nothing)
assert(isnan(v.thresholdHandleY()) && strcmp(H.Stack.Grip.Visible,'off'), ...
    'A single-level series offers a threshold divider to drag.');
threw = "";
try
    v.dragThreshold(0);
catch me
    threw = string(me.identifier);
end
assert(threw == "mabr:ui:SeriesView:noThreshold",'dragThreshold on a single level gave "%s".',threw);

m.openSession(k.NoLevel);
assert(m.levelParam() == "",'The no-level session has a level parameter (%s): nothing to check.',m.levelParam());
[txt,on] = emptyState(fig);
assert(on && txt == v.TextNoLevel,'A session with no level parameter does not say "%s" (it says "%s").', ...
    v.TextNoLevel,txt);
b = findall(fig,'Tag','AnalysisSeriesEmptyAction1');
assert(strcmp(b.Visible,'on') && contains(string(b.Text),"Settings") && ~isempty(b.Icon), ...
    'The no-level state does not offer the Settings… button with its picture.');

% a session not analysed yet: its traces, a banner, no threshold
m.openSession(k.Two,Source="raw");
[~,on] = emptyState(fig);
H = v.Handles;
assert(~on && m.Status.State == "not-analysed",'Opening from raw did not give an unanalysed session.');
assert(strcmp(H.Banner.Visible,'on') && contains(string(H.Banner.Text),v.TextNotAnalysed), ...
    'An unanalysed session does not say "%s".',v.TextNotAnalysed);
G = v.Geometry;
assert(numel(G.Keys) == 5 && all(any(isfinite(G.Mean),1)),'An unanalysed session draws no traces.');
assert(string(H.State.Text) == "Not analysed: no threshold yet." && ...
    strcmp(findall(fig,'Tag','AnalysisThresholdAccept').Enable,'off'),'An unanalysed series offers threshold buttons.');
assert(isnan(v.thresholdHandleY()) && strcmp(H.Stack.Grip.Visible,'off'), ...
    'An unanalysed series offers a threshold divider to drag.');

m.openSession(k.Base);
[~,on] = emptyState(fig);
assert(~on && ~isempty(v.Geometry),'Opening an analysed session did not lift the empty state.');
assert(strcmp(v.Handles.Banner.Visible,'off'),'An analysed session shows the banner "%s".',v.Handles.Banner.Text);
fprintf(['  PASS Part B: no session and no level parameter each show their sentence (the last with ' ...
    'Settings…); a single-level session is shown -- list, trace, peaks -- with the banner and the ' ...
    'evidence saying no threshold can be estimated; an unanalysed session draws its traces under ' ...
    '"Not analysed"; an analysed session lifts it all\n']);
end

% =========================================================================
%  Part C -- entering a series, LevelMemory, the list
% =========================================================================
function partC_enter(app,v)
m = app.Model;
H = v.Handles;
sk = m.seriesKeys();
assert(numel(sk) == 2,'The baseline session has %d series.',numel(sk));
% (Part B viewed another session's series of the SAME key at its loudest
% level: level memory is per session, so it must not carry over here.)
assert(m.Selection.SeriesKey == sk(1) && m.Selection.Level == expectLevel(m,sk(1)), ...
    'The session did not open on its first series at the threshold-adjacent level (%g, want %g).', ...
    m.Selection.Level,expectLevel(m,sk(1)));
D = H.List.Data;
want = mabr.ui.analysis.Style.compactSeriesLabels([m.seriesLabel(sk(1)); m.seriesLabel(sk(2))]);
assert(size(D,1) == 2 && isequal(string(D(:,2)),want) && all(~startsWith(want,"Tone")), ...
    'The list rows are not the session''s series (by their short names: %s).',strjoin(string(D(:,2)),' | '));
assert(string(D{1,3}) == mabr.ui.analysis.Style.formatThreshold(thrRow(m,sk(1))), ...
    'The list row 1 does not show its Final.');
assert(string(H.Reviewed.Text) == "Reviewed 0/2",'The reviewed count reads "%s".',H.Reviewed.Text);

% a series never visited opens next to its threshold: a value of 35 dB
% on 0:20:80 -> 40 dB
m.setThresholdValue(35,sk(2));
assert(~isKey(m.LevelMemory,m.levelMemoryKey(sk(2))),'The second series was visited already: nothing to check.');
listClick(v,2);
assert(m.Selection.SeriesKey == sk(2) && m.Selection.Level == 40, ...
    'A series with a threshold of 35 dB opened at %g dB, not 40.',m.Selection.Level);
assert(isequal(rowStyleRows(H.List),2),'The list does not highlight the current row.');
assert(v.Geometry.SeriesKey == sk(2),'The stack does not show the clicked series.');
m.selectLevel(60);
listClick(v,1);
assert(m.Selection.SeriesKey == sk(1) && m.Selection.Level == expectLevel(m,sk(1)), ...
    'Back on the first series the level is not the one left there.');
listClick(v,2);
assert(m.Selection.Level == 60 && m.LevelMemory(m.levelMemoryKey(sk(2))) == 60, ...
    'LevelMemory did not bring the second series back at 60 dB (%g).',m.Selection.Level);
press(app,'downarrow');
assert(m.Selection.Level == 40,'Down did not select the quieter level.');
press(app,'uparrow');  press(app,'uparrow');
assert(m.Selection.Level == 80,'Up twice did not reach 80 dB.');
m.undo();                                  % the 35 dB value
assert(thrRow(m,sk(2)).Decision == "",'Undo did not take the 35 dB value back.');
listClick(v,1);
fprintf(['  PASS Part C: a series opens next to its threshold (35 dB -> 40), LevelMemory restores 60 dB, ' ...
    'list clicks select and highlight, arrows step levels\n']);
end

% =========================================================================
%  Part D -- the stack, curation buttons and keys
% =========================================================================
function partD_curation(app,v)
m = app.Model;
H = v.Handles;
fig = app.Figure;
sk = m.seriesKeys();
s1 = sk(1);
m.selectSeries(s1,Level=40);
G = v.Geometry;
St = H.Stack;
n = numel(G.Keys);
assert(n == 5 && isequal(G.Levels(:).',0:20:80),'The stack does not hold 0:20:80 dB quietest first.');
assert(St.Lines.Count == 5,'The stack does not have one trace per level.');
i40 = find(G.Levels == 40);
for i = 1:n
    ln = St.Lines(char(G.Keys(i)));
    assert(max(abs(ln.YData(:) - (G.Disp(:,i) + G.Offsets(i)))) < 1e-12,'Level %g is not drawn at its offset.',G.Levels(i));
    if i == i40
        assert(isequal(ln.Color,[0 0 0]) && ln.LineWidth == 2,'The selected level is not black, 2 px.');
    elseif G.Detected(i) == 0
        assert(strcmp(ln.LineStyle,'--'),'An undetected level is not dashed.');
    else
        assert(strcmp(ln.LineStyle,'-'),'A detected level is not solid.');
    end
    gl = mabr.ui.analysis.Style.detectionGlyph(G.Detected(i) == 1,G.Overridden(i));
    assert(string(St.Glyphs(i).String) == gl,'Level %g carries "%s", not "%s".',G.Levels(i),St.Glyphs(i).String,gl);
    assert(string(St.Counts(i).String) == string(G.Count(i)),'Level %g does not show its sweep count.',G.Levels(i));
end
assert(string(St.Axes.YTickLabel{end}) == "80",'The loudest level is not on top.');
% the amplitude scale: a 1-2-5 microvolt bar no taller than the row spacing
% (0.8 of it), labelled; normalised, the corner says the traces share none
sb = St.ScaleBar;  stx = St.ScaleText;
len = diff(sb.YData);
uv = str2double(extractBefore(string(stx.String)," µV"));
assert(isgraphics(sb) && endsWith(string(stx.String),"µV") && len > 0 && len <= 0.8*G.Step + 1e-12 && ...
    abs(len - uv*1e-6*v.AmpScale) < 1e-9*max(1,len) && ismember(round(uv/10^floor(log10(uv)),6),[1 2 5]), ...
    'The stack has no µV scale bar of a 1-2-5 size (%s, %g).',string(stx.String),len);
v.onCommand("view.normalize");
assert(string(v.Handles.Stack.ScaleText.String) == "each trace to its own peak" && ...
    all(isnan(v.Handles.Stack.ScaleBar.YData)),'Normalised, the scale bar does not give way to its note.');
v.onCommand("view.normalize");
G = v.Geometry;

% Final and fit dividers
press(app,'t');                                % manual at 40 dB
r = thrRow(m,s1);
[yF,yT] = deal(St.Final.YData(1),St.Fit.YData(1));
assert(r.Decision == "manual" && abs(yF - wantY(G,r.Final,r.FinalCensored,r.FinalLo,r.FinalHi)) < 1e-9 && ...
    strcmp(St.Final.Visible,'on'),'The Final divider is not at the manual threshold.');
assert(strcmp(St.Fit.Visible,'on') && abs(yT - wantY(G,r.Threshold,r.Censored,r.ThrLo,r.ThrHi)) < 1e-9, ...
    'The fit divider is not at the fitted threshold where it differs.');
m.undo();
press(app,'i');                                % no response
assert(abs(St.Final.YData(1) - (G.Offsets(end) + G.Step/2)) < 1e-9 && strcmp(St.FinalText.Visible,'on'), ...
    'No response is not a divider above the loudest level marked NR.');
m.undo();

% every button and its key: the same Decision, glyph, Final text; an undo step each
fl = thrRow(m,s1).Flags;
pairs = { ...
    "AnalysisThresholdAccept",     {'a'},              "accepted",   mabr.ui.analysis.Style.GlyphAccepted
    "AnalysisThresholdAtLevel",    {'t'},              "manual",     mabr.ui.analysis.Style.GlyphManual
    "AnalysisThresholdNoResponse", {'i'},              "noresponse", mabr.ui.analysis.Style.GlyphNoResponse
    "AnalysisThresholdAllRespond", {'downarrow','alt'},"allrespond", mabr.ui.analysis.Style.GlyphAllRespond
    "AnalysisThresholdExclude",    {'x'},              "excluded",   mabr.ui.analysis.Style.GlyphExcluded};
for p = 1:size(pairs,1)
    b = findall(fig,'Tag',pairs{p,1});
    kk = pairs{p,2};
    nU = numel(m.undoHistory());
    push(b);
    closeNote(app);
    r1 = thrRow(m,s1);
    assert(r1.Decision == pairs{p,3},'%s gave the decision "%s" (status: %s).',pairs{p,1},r1.Decision,statusText(app));
    assert(numel(m.undoHistory()) == nU + 1 && m.CanUndo,'%s did not add one undo step.',pairs{p,1});
    li = H.List.Data;
    assert(string(li{1,1}) == pairs{p,4} && string(li{1,3}) == mabr.ui.analysis.Style.formatThreshold(r1), ...
        'After %s the list shows "%s %s".',pairs{p,1},li{1,1},li{1,3});
    assert(startsWith(string(H.State.Text),"Decision: "),'The decision sentence is missing.');
    m.undo();
    assert(thrRow(m,s1).Decision == "",'Undo after %s left "%s".',pairs{p,1},thrRow(m,s1).Decision);
    if numel(kk) > 1, press(app,kk{1},kk(2)); else, press(app,kk{1}); end
    closeNote(app);
    r2 = thrRow(m,s1);
    assert(r2.Decision == r1.Decision && isequaln(r2.Final,r1.Final) && r2.FinalCensored == r1.FinalCensored, ...
        'The key %s and the button %s disagree (%s %g / %s %g).',kk{1},pairs{p,1},r2.Decision,r2.Final, ...
        r1.Decision,r1.Final);
    m.undo();
end
% clear: after an accept, the button and c both clear (an undo step each)
for way = 1:2
    m.acceptFit();
    nU = numel(m.undoHistory());
    if way == 1, push(findall(fig,'Tag','AnalysisThresholdClear')); else, press(app,'c'); end
    assert(thrRow(m,s1).Decision == "" && numel(m.undoHistory()) == nU + 1,'Clear did not clear the decision.');
    g = string(H.List.Data{1,1});
    assert(g == mabr.ui.analysis.Style.decisionGlyph("",fl),'A cleared series shows "%s".',g);
    m.undo(); m.undo();
end
assert(thrRow(m,s1).Decision == "",'The decisions were not all undone.');

% the note: the button and Ctrl+N open the editor on this series
push(findall(fig,'Tag','AnalysisThresholdNote'));
assert(m.KeysSuspended && app.NoteEditor.IsOpen && app.NoteEditor.Target.Key == s1, ...
    'The Note button did not open the note editor on the series.');
app.NoteEditor.write("ear plug slipped");
app.NoteEditor.commit();
assert(~m.KeysSuspended && contains(thrRow(m,s1).Note,"ear plug") && contains(string(H.State.Text),"ear plug"), ...
    'The note was not saved on the series.');
press(app,'n',{'control'});
assert(app.NoteEditor.IsOpen,'Ctrl+N did not open the note editor.');
press(app,'escape');
assert(~app.NoteEditor.IsOpen,'Escape did not close the note editor.');
m.undo();

% the value field: a manual value, uncensored
vf = findall(fig,'Tag','AnalysisThresholdValueField');
vf.Value = 42.5;
push(findall(fig,'Tag','AnalysisThresholdSetValue'));
r = thrRow(m,s1);
assert(r.Decision == "manual" && r.ManualValue == 42.5 && r.Final == 42.5 && r.FinalCensored == "none", ...
    'The value field did not set a manual 42.5 dB (status: %s).',statusText(app));
assert(contains(string(H.State.Text),"manual 42.5 dB"),'The decision sentence does not say "manual 42.5 dB".');
m.undo();

% the context menu
v.menuAction("noResponse",80);
assert(thrRow(m,s1).Decision == "noresponse" && m.Selection.Level == 80,'menuAction("noResponse",80) did not.');
m.undo();
ck = m.Selection.ConditionKey;
v.menuAction("override");
assert(overrideOf(m,ck) == 1,'menuAction("override") did not force a response.');
i80 = find(v.Geometry.Keys == ck);
assert(string(v.Handles.Stack.Glyphs(i80).String) == mabr.ui.analysis.Style.GlyphOverrideOn, ...
    'An overridden level does not show ■.');
m.undo();
assert(isnan(overrideOf(m,ck)),'Undo did not drop the override.');
try
    v.menuAction("bogus");
    error('verify:noError','menuAction("bogus") did not error.');
catch me
    assert(strcmp(me.identifier,'mabr:ui:SeriesView:badMenu'),'menuAction("bogus") errored with %s.',me.identifier);
end
assert(isscalar(findall(fig,'Tag','AnalysisSeriesMenu_accept')) && ...
    numel(findall(fig,'Tag','AnalysisMenuCopyDataItem')) >= 1,'The stack''s context menu lacks its items.');
fprintf(['  PASS Part D: the stack (traces at their offsets, the selected level black, undetected dashed, ' ...
    '● ○ ■ and counts, Final/fit/NR dividers); buttons = keys for a t i Alt+↓ x c (list glyph, Final, one ' ...
    'undo step each); Note and Ctrl+N; the value field; the context menu\n']);
end

% =========================================================================
%  Part E -- the method dropdown, custom row, evidence, compare
% =========================================================================
function partE_method(app,v,k)
m = app.Model;
H = v.Handles;
fig = app.Figure;
sk = m.seriesKeys();
s1 = sk(1);
m.selectSeries(sk(2));
m.selectSeries(s1);                        % a fresh visit seeds the value field
vf = H.ValueField;
assert(vf.Value == seedOf(m,s1),'The value field does not open on the series'' Final (%g).',vf.Value);
M = mabr.analysis.SeriesThreshold.methods();
assert(isequal(string(H.Method.ItemsData),string({M.Id})) && string({M(1).Id}) == "perm-glm", ...
    'The method dropdown does not list SeriesThreshold.methods() in order.');
assert(string(H.Method.Value) == "perm-glm" && m.Settings.ThresholdMethod == "perm-glm", ...
    'The method dropdown does not open on perm-glm (13 A1).');
assert(string(H.Definition.Text) == m.Settings.thresholdDefinition(),'The definition sentence is not the settings''.');
assert(strcmp(H.CustomRow.Visible,'off') && H.ThresholdGrid.RowHeight{2} == 0,'The custom row shows for perm-glm.');

% the evidence of a p-method (perm-glm): detections, -log10 p and alpha
S = m.Session;
[ck,lv] = seriesLevels(m,s1);
rows = rowsOf(S,ck);
p = double(S.Conditions.p(rows));
ax = H.Evidence;
lab = findall(ax,'Tag','EvidenceRulerLabel');
assert(isscalar(lab) && contains(string(lab.String),"log10 p"),'The p-method evidence has no -log10 p ruler.');
pl = findobj(ax,'Tag','EvidenceP');
assert(isscalar(pl) && isequal(pl.XData(:),lv) && max(abs(pl.UserData(:) + log10(max(p,eps)))) < 1e-12, ...
    'The -log10 p line is not the conditions'' p.');
pv = findobj(ax,'Tag','EvidencePValues');
assert(isscalar(pv) && max(abs(pv.YData(:) + log10(max(p,eps)))) < 1e-12,'The -log10 p values are not kept for Copy data.');
al = findobj(ax,'Tag','EvidenceAlpha');
a = -log10(m.Settings.Alpha);
assert(isscalar(al) && abs(al.UserData(1) - a) < 1e-12,'The alpha line is not at -log10 alpha.');
% drawn where the right ruler reads -log10 p: its ticks fix the mapping
tk = findall(ax,'Tag','EvidenceRulerTick');
tv = str2double(string({tk.String}));  ty = arrayfun(@(t) t.Position(2),tk(:).');
c = polyfit(tv,ty,1);
assert(numel(tk) >= 2 && max(abs(polyval(c,tv) - ty)) < 1e-9 && abs(polyval(c,a) - al.YData(1)) < 1e-9 && ...
    max(abs(polyval(c,pl.UserData(:)) - pl.YData(:))) < 1e-9,'The -log10 p line is not where its ruler says.');
txt = mabr.ui.analysis.FigureExport.copyData(ax);
hdr = split(extractBefore(txt + newline,newline),char(9));
assert(any(hdr == "-log10 p y") && ~any(contains(hdr,"Ruler")),'Copy data does not give the -log10 p values (only).');
% ... whatever the root's ShowHiddenHandles says (findobj alone would then
% hand the ruler over too)
sh0 = get(groot,'ShowHiddenHandles');
set(groot,'ShowHiddenHandles','on');
try
    txt2 = mabr.ui.analysis.FigureExport.copyData(ax);
catch me
    set(groot,'ShowHiddenHandles',sh0);
    rethrow(me);
end
set(groot,'ShowHiddenHandles',sh0);
assert(txt2 == txt,'With ShowHiddenHandles on, Copy data copies the hidden ruler lines.');
% the sweep counts sit in their own band, under every marker
yN = arrayfun(@(t) t.Position(2),findobj(ax,'Tag','EvidenceN'));
mk = [findobj(ax,'Tag','EvidenceDetected'); findobj(ax,'Tag','EvidenceUndetected'); findobj(ax,'Tag','EvidenceP')];
yM = cell2mat(arrayfun(@(h) h.YData(:),mk,'UniformOutput',false));
assert(~isempty(yN) && max(yN) < min(yM),'The sweep counts are drawn on the markers.');
det = double(S.Conditions.Detected(rows)) == 1;
dl = findobj(ax,'Tag','EvidenceDetected'); ul = findobj(ax,'Tag','EvidenceUndetected');
got = [];
if ~isempty(dl), got = [got; dl.XData(:) ones(numel(dl.XData),1)]; end
if ~isempty(ul), got = [got; ul.XData(:) zeros(numel(ul.XData),1)]; end
assert(isequal(sortrows(got),sortrows([lv double(det)])),'The detections are not drawn at 1 / 0 per level.');
assert(~isempty(findobj(ax,'Tag','EvidenceCurve')) && ...
    isequal(findobj(ax,'Tag','EvidenceCriterion').YData,[0.5 0.5]),'perm-glm shows no fitted curve or p = 0.5 line.');
assert(numel(findobj(ax,'Tag','EvidenceN')) == numel(lv),'The evidence does not count sweeps per level.');
r = thrRow(m,s1);
fl = findobj(ax,'Tag','EvidenceFinal');
assert(isscalar(fl) && all(abs(fl.XData - r.Final) < 1e-12),'The Final is not drawn at %g.',r.Final);

% the PROJECT's method: refit here, out of date elsewhere, nothing re-run
V0 = m.projectView();
assert(all(V0.Status(ismember(V0.Key,[k.Two;k.Mixed])) == "current"),'The other sessions are not current to begin with.');
f2 = m.sessionInfo(k.Two).ResultsFile;
d0 = dir(f2);
p0 = S.Conditions.p;
drive(H.Method,'perm-descending');
S = m.Session;
assert(m.Settings.ThresholdMethod == "perm-descending" && m.Project.Settings.ThresholdMethod == "perm-descending", ...
    'The dropdown did not change the project''s method.');
assert(all(string(S.Thresholds.Method) == "perm-descending") && m.Status.State == "current", ...
    'The open session was not re-fitted with the new method (%s).',m.Status.Text);
assert(isequaln(S.Conditions.p,p0),'Changing the method re-ran detection.');
V1 = m.projectView();
assert(all(V1.Status(ismember(V1.Key,[k.Two;k.Mixed])) == "stale"),'The other sessions are not out of date.');
d1 = dir(f2);
assert(d1.bytes == d0.bytes && d1.datenum == d0.datenum,'Another session was re-run.');
assert(isempty(findobj(H.Evidence,'Tag','EvidenceCriterion')) && ...
    isscalar(findall(H.Evidence,'Tag','EvidenceRulerLabel')),'perm-descending (p) draws a criterion line or no p ruler.');
assert(vf.Value == seedOf(m,s1),'The value field did not follow the re-fitted Final (%g, want %g).', ...
    vf.Value,seedOf(m,s1));

% a graded method: the metric beside its criterion, no p axis
drive(H.Method,'xcorr');
S = m.Session;
assert(vf.Value == seedOf(m,s1),'The value field did not follow the xcorr Final (%g, want %g).', ...
    vf.Value,seedOf(m,s1));
vf.Value = 55.5;                           % typed, not yet Set: no re-fit may overwrite it
y = double(S.Conditions.XCorrUp(rows));
assert(isempty(findall(H.Evidence,'Tag','EvidenceRulerLabel')),'A graded method shows the p ruler.');
cl = findobj(H.Evidence,'Tag','EvidenceCriterion');
assert(isscalar(cl) && isequal(cl.YData,[0.35 0.35]),'xcorr''s criterion line is not at 0.35.');
ml = findobj(H.Evidence,'Tag','EvidenceMetric');
got = zeros(0,2);
for h = reshape(ml,1,[]), got = [got; h.XData(:) h.YData(:)]; end %#ok<AGROW>
got = got(isfinite(got(:,2)),:);
want = [lv y]; want = want(isfinite(y),:);
assert(isequal(sortrows(got),sortrows(want)),'The xcorr evidence is not XCorrUp per level.');
assert(string(H.Evidence.YLabel.String) == "r with next louder",'The graded axis is not labelled.');
if ismember('PowerF95',S.Conditions.Properties.VariableNames)
    drive(H.Method,'power-descending');
    assert(~isempty(findobj(H.Evidence,'Tag','EvidencePowerF')) && ...
        ~isempty(findobj(H.Evidence,'Tag','EvidencePowerF95')),'The power method shows no F / null 95% ticks.');
end

% the custom row: only for "custom", with the criterion's unit
drive(H.Method,'custom');
assert(strcmp(H.CustomRow.Visible,'on') && H.ThresholdGrid.RowHeight{2} == 24, ...
    'The custom row does not show for "custom".');
assert(string(H.CriterionUnit.Text) == "probability",'detection + glm is not a probability.');
drive(findall(fig,'Tag','AnalysisThresholdModel'),'descending');
assert(m.Settings.ThresholdModel == "descending" && string(H.CriterionUnit.Text) == "p", ...
    'detection + descending is not a p criterion.');
drive(findall(fig,'Tag','AnalysisThresholdMetric'),'xcorr');
assert(m.Settings.ThresholdMetric == "xcorr" && string(H.CriterionUnit.Text) == "r", ...
    'xcorr + descending is not an r criterion.');
drive(findall(fig,'Tag','AnalysisThresholdCriterion'),'0.5');
assert(m.Settings.Criterion == 0.5 && all(string(m.Session.Thresholds.Method) == "custom"), ...
    'The custom criterion was not applied.');
drive(findall(fig,'Tag','AnalysisThresholdModel'),'glm');     % glm on a graded metric
assert(m.Settings.ThresholdModel == "descending" && contains(statusText(app),"Not applied") && ...
    string(H.ModelDrop.Value) == "descending",'An impossible custom combination was applied.');

% back to perm-glm: every session current again, still none re-run
drive(H.Method,'perm-glm');
assert(strcmp(H.CustomRow.Visible,'off') && H.ThresholdGrid.RowHeight{2} == 0,'The custom row stays for perm-glm.');
assert(vf.Value == 55.5,'A re-fit overwrote the value typed in the value field (%g).',vf.Value);
m.setSettings(withCustomDefaults(m.Settings));
V2 = m.projectView();
assert(all(V2.Status(ismember(V2.Key,[k.Two;k.Mixed])) == "current"),'Back on perm-glm the others are not current.');
d2 = dir(f2);
assert(d2.datenum == d0.datenum,'Another session was re-run.');

% Compare methods: every built-in method on the stored statistics
T = m.compareMethods(s1);
push(findall(fig,'Tag','AnalysisThresholdCompare'));
D = H.Other.Data;
assert(size(D,1) == height(T) && height(T) == numel(M) - 1 && isequal(string(D(:,2)),T.Text), ...
    'The compare table is not Model.compareMethods.');
% the methods by name (not their ids), the status in words, every row shown
assert(~any(ismember(string(D(:,1)),T.Method)) && all(contains(string(H.Other.Tooltip),T.Label)) && ...
    ~any(contains(string(D(:,3)),"-")),'The compare table shows ids or status tokens: %s / %s.', ...
    strjoin(string(D(:,1)),', '),strjoin(string(D(:,3)),', '));
assert(H.ThresholdGrid.RowHeight{9} >= 26 + 21*height(T),'The compare table is not tall enough for its rows.');
assert(contains(string(H.OtherNote.Text),m.seriesLabel(s1)),'The compare note does not name the series.');
m.selectSeries(sk(2));
assert(isempty(H.Other.Data) && H.ThresholdGrid.RowHeight{9} == 0,'The compare table outlived its series.');
m.selectSeries(s1);
fprintf(['  PASS Part E: the dropdown opens on perm-glm and changes the project''s method (refit here, ' ...
    'detection kept, others out of date and not re-run); custom row and units; evidence per family ' ...
    '(-log10 p + alpha, curve and 0.5; xcorr metric + 0.35); the value field follows a re-fit but ' ...
    'never a typed value; Compare methods\n']);
end

% =========================================================================
%  Part F -- the audiogram
% =========================================================================
function partF_audiogram(app,v,k)
m = app.Model;
H = v.Handles;
ax = H.Audiogram;
assert(strcmp(ax.XScale,'log'),'The audiogram''s frequency axis is not logarithmic.');
assert(string(H.AudiogramNote.Text) == "",'The baseline session lists series without a frequency.');
L = findobj(ax,'Tag','AudiogramLine');
assert(isscalar(L) && isequal(L.XData(:),[4;16]),'The audiogram does not plot 4 and 16 kHz.');
cur = findobj(ax,'Tag','AudiogramCurrent');
assert(isscalar(cur) && cur.XData == 4,'The current series is not highlighted at 4 kHz.');

m.openSession(k.Mixed);
note = string(H.AudiogramNote.Text);
ck = m.seriesKeys(Stimulus="ClickTrain");
assert(isscalar(ck) && contains(note,m.seriesLabel(ck)) && ...
    contains(note,mabr.ui.analysis.Style.formatThreshold(thrRow(m,ck))),'The click series is not listed: "%s".',note);
L = findobj(ax,'Type','line');
for h = reshape(L,1,[])
    assert(all(isfinite(h.XData) & h.XData > 0),'A NaN or non-positive x on the log audiogram (%s).',h.Tag);
end
assert(numel(findobj(ax,'Tag','AudiogramLine')) == 2,'The tone series are not one line per acquisition mode.');
m.openSession(k.Base);

% Compare with: the subject's other analysed sessions, grey dashes
cmp = v.Handles.Compare;
items = string(cmp.ItemsData);
assert(strcmp(cmp.Visible,'on') && any(items == k.Two) && ~any(items == k.Base), ...
    'Compare with does not offer the subject''s other analysed session.');
drive(cmp,char(k.Two));
ln = v.Handles.Stack.Compare;
assert(strcmp(ln.Visible,'on') && any(isfinite(ln.YData)),'Compare with draws no overlay.');
drive(cmp,'');
assert(strcmp(ln.Visible,'off'),'The overlay stays after Compare with: none.');
% blind review hides it (another session's data would name it), overlay
% included; it comes back empty, the dropdown and the stack agreeing
drive(cmp,char(k.Two));
m.startReviewQueue(k.Base,Blind=true,UnreviewedOnly=false);
cmp = v.Handles.Compare;  ln = v.Handles.Stack.Compare;
assert(m.BlindReview && strcmp(cmp.Visible,'off') && strcmp(ln.Visible,'off') && v.CompareKey == "", ...
    'Blind review does not hide Compare with and its overlay.');
m.endQueue();
assert(~m.BlindReview && strcmp(cmp.Visible,'on') && string(cmp.Value) == "" && strcmp(ln.Visible,'off'), ...
    'After blind review Compare with is not back, empty.');
fprintf(['  PASS Part F: the audiogram plots frequency on a log axis with the current series ringed; the ' ...
    'click series is listed beneath in words, no NaN on the log axis; Compare with overlays another ' ...
    'session and blind review hides it\n']);
end

% =========================================================================
%  Part G -- peaks
% =========================================================================
function partG_peaks(app,v)
m = app.Model;
H = v.Handles;
fig = app.Figure;
sk = m.seriesKeys();
s1 = sk(1);
m.selectSeries(s1,Level=80);
S = m.Session;
G = v.Geometry;
i = find(G.Levels == 80);
ck = G.Keys(i);
dt = 1000/S.SampleRate;
assert(isequal(G.Waves,["I","II","III","IV","V"]),'The series'' waves are %s.',strjoin(G.Waves,","));

% 1-5 and Shift+1-5
press(app,'3');
assert(m.Selection.Wave == "III" && m.Selection.Kind == "P",'3 did not select wave III''s peak.');
press(app,'3',{'shift'},'#');
assert(m.Selection.Wave == "III" && m.Selection.Kind == "N",'Shift+3 did not select wave III''s trough.');
press(app,'1');
assert(m.Selection.Wave == "I" && m.Selection.Kind == "P",'1 did not select wave I''s peak.');
sel = H.Stack.Selected;
lat0 = pk(m,ck,"I");
assert(strcmp(sel.Visible,'on') && abs(sel.XData - lat0) < 1e-12,'The selected point is not drawn at wave I.');

% a click snaps; a press on the marker without moving changes nothing
nU = numel(m.undoHistory());
v.clickAt(lat0,80);
assert(numel(m.undoHistory()) == nU && pk(m,ck,"I") == lat0,'A press on the marker without moving moved it.');
pxPerMs = pixelsPerMs(H.Stack.Axes);
tc = lat0 + max(15/pxPerMs,0.12);              % clear of the 8 px drag zone
v.clickAt(tc,80);
L1 = pk(m,ck,"I");
assert(numel(m.undoHistory()) == nU + 1 && peakState(m,ck,"I") == "manual",'A click did not place wave I.');
assert(abs(L1 - snapExpected(S,ck,tc,0.25)) < 1e-9,'The click at %.3f ms did not snap (%.4f, want %.4f).', ...
    tc,L1,snapExpected(S,ck,tc,0.25));
assert(contains(string(H.Cursor.Text),"80 dB"),'The cursor readout is not written on a click.');
bc = boldCells(H.Matrix);
assert(any(ismember(bc,[1 2],'rows')),'The manual pick is not bold in the matrix (row 1, column I).');
v.clickAt(lat0,40);
assert(m.Selection.Level == 40 && pk(m,ck,"I") == L1,'A click on another level did more than select it.');
m.selectLevel(80);

% dragPeak: exactly there, one undo step
nU = numel(m.undoHistory());
v.dragPeak("I","P",2.0);
assert(pk(m,ck,"I") == 2.0 && numel(m.undoHistory()) == nU + 1,'dragPeak did not place wave I at 2.000 ms.');
MT = v.matrixTable();
assert(string(MT{1,2}) == "2.00",'The matrix does not show the dragged latency.');

% nudges: Alt and Shift arrows, one sample
press(app,'leftarrow',{'alt'});   assert(abs(pk(m,ck,"I") - (2 - dt)) < 1e-9,'Alt+Left did not nudge one sample.');
press(app,'leftarrow',{'shift'}); assert(abs(pk(m,ck,"I") - (2 - 2*dt)) < 1e-9,'Shift+Left did not nudge.');
press(app,'rightarrow',{'alt'});  assert(abs(pk(m,ck,"I") - (2 - dt)) < 1e-9,'Alt+Right did not nudge.');
press(app,'rightarrow',{'shift'});assert(abs(pk(m,ck,"I") - 2) < 1e-9,'Shift+Right did not nudge.');

% arrows: candidates while a point is selected, else series
press(app,'rightarrow');
L2 = pk(m,ck,"I");
assert(m.Selection.SeriesKey == s1 && L2 > 2,'Right with a point selected did not move to the next candidate.');
press(app,'leftarrow');
assert(m.Selection.SeriesKey == s1 && pk(m,ck,"I") < L2,'Left did not move back to a candidate.');
press(app,'escape');
assert(m.Selection.Wave == "",'Escape did not clear the selected point.');
press(app,'rightarrow');
assert(m.Selection.SeriesKey == sk(2),'Right with no point selected did not change series.');
press(app,'leftarrow');
assert(m.Selection.SeriesKey == s1,'Left with no point selected did not change series back.');
m.selectLevel(80);
H = v.Handles;            % (another series rebuilt the stack's objects)

% absent here, revert, absent here and below
press(app,'2');
press(app,'delete');
G = v.Geometry;
j2 = find(G.Waves == "II");
assert(G.State(i,j2) == "absent",'Delete did not mark wave II absent.');
D = H.Matrix.Data;
assert(string(D{1,1+j2}) == "—",'An absent wave is not "—" in the matrix (it is "%s").',D{1,1+j2});
ab = H.Stack.Absent("II");
assert(isfinite(ab.XData(i)) && ab.YData(i) == G.Offsets(i),'No grey cross where wave II is absent.');
press(app,'backspace');
assert(peakState(m,ck,"II") == "auto",'Backspace did not bring the automatic pick back.');
press(app,'delete',{'shift'});
G = v.Geometry;
assert(all(G.State(:,j2) == "absent"),'Shift+Delete did not mark wave II absent at and below 80 dB.');
m.undo();
assert(peakState(m,ck,"II") == "auto",'Undo did not take the absences back.');

% p, u, Shift+U
press(app,'p');            [u,~] = m.undoHistory();  assert(startsWith(u(end),"Auto-pick"),'p is not "Auto-pick".');
press(app,'u');            [u,~] = m.undoHistory();  assert(startsWith(u(end),"Re-track from 80"),'u is not a re-track.');
press(app,'u',{'shift'});  [u,~] = m.undoHistory();  assert(startsWith(u(end),"Re-track (overwrite)"),'Shift+U is not.');
for q = 1:3, m.undo(); end

% the matrix: loudest first; a cell selects its level and wave
D = H.Matrix.Data;
assert(isequal(string(D(:,1)).',string(80:-20:0)) && isequal(string(H.Matrix.ColumnName(2:6)).',G.Waves), ...
    'The matrix is not levels loudest first by waves.');
G = v.Geometry;
for r = 1:5
    ii = find(G.Levels == 80 - 20*(r-1));
    lt = G.PeakLat(ii,1);
    if isfinite(lt), assert(string(D{r,2}) == sprintf('%.2f',lt),'Matrix row %d: wave I latency.',r); end
end
cb = H.Matrix.CellSelectionCallback;
cb(H.Matrix,struct('Indices',[3 4]));
assert(m.Selection.Level == 40 && m.Selection.Wave == "III" && m.Selection.Kind == "P", ...
    'A matrix cell did not select its level and wave.');
m.selectLevel(80);
G = v.Geometry;
look(v,'PeaksShow',"pn");
D = H.Matrix.Data;
assert(string(D{1,2}) == sprintf('%.2f',1e6*G.AmpPT(i,1)) && string(H.PeaksShow.Value) == "pn", ...
    'P–N amplitudes are not shown in µV.');
look(v,'PeaksShow',"bp");
D = H.Matrix.Data;
assert(string(D{1,2}) == sprintf('%.2f',1e6*G.AmpBP(i,1)),'Baseline–peak amplitudes are not shown in µV.');
look(v,'PeaksShow',"latency");

% the I/O and latency plots
look(v,'PlotKind',"io");
w1 = findobj(H.PeakPlot,'Tag','PeakPlotWave','DisplayName','I');
[lvA,o] = sort(G.Levels);
ya = 1e6*G.AmpPT(o,1);  ya(G.Below(o,1) | ~ismember(G.State(o,1),["auto","manual"])) = NaN;
assert(isscalar(w1) && isequal(w1.XData(:),lvA) && isequaln(w1.YData(:),ya),'The I/O plot is not wave I''s P–N amplitude.');
look(v,'PlotKind',"latency");
w1 = findobj(H.PeakPlot,'Tag','PeakPlotWave','DisplayName','I');
yl = G.PeakLat(o,1);  yl(G.Below(o,1) | ~ismember(G.State(o,1),["auto","manual"])) = NaN;
assert(isequaln(w1.YData(:),yl) && string(H.PeakPlot.YLabel.String) == "Latency (ms)" && ...
    string(H.PeakPlot.Title.String) == "",'The latency plot is not wave I''s latency.');
look(v,'PlotKind',"io");

% Bootstrap: raw data, SE columns (40 replicates; the project's setting)
st = m.Settings;  st.PeakBootstrap = 40;
m.setSettings(st);
assert(m.SessionSource == "results",'The session is not results-only before the bootstrap.');
push(findall(fig,'Tag','AnalysisPeaksBootstrap'));
assert(m.SessionSource == "raw",'Bootstrap did not load the raw data (status: %s).',statusText(app));
G = v.Geometry;
assert(any(isfinite(G.LatSE(:))),'Bootstrap filled no latency SE.');
cn = string(H.Matrix.ColumnName);
assert(numel(cn) == 11 && cn(7) == "I SE",'The matrix has no SE columns: %s.',strjoin(cn,", "));

% Use current picks as wave windows: the project's waves follow this series
P = m.Session.picksAsWindows(s1);
push(findall(fig,'Tag','AnalysisPeaksFitWindows'));
W = m.Settings.Waves;
tone = W(string({W.Stimulus}) == "Tone");
assert(~isempty(tone) && isequal(m.Project.Settings.Waves,W),'The project''s waves did not take this series'' picks.');
assert(isequaln([tone.Expected],[P.Expected]),'The new windows are not the picks of the series.');
assert(contains(statusText(app),"Wave windows now follow"),'No status line for the new windows.');
fprintf(['  PASS Part G: 1-5 / Shift+1-5; click snaps, press without moving keeps, drag exact; Alt/Shift ' ...
    'nudges; arrows = candidates only with a point; Delete / Shift+Delete / Backspace; p u Shift+U; the ' ...
    'matrix (loudest first, bold manual, "—", cell select, P–N / B–P); I/O and latency plots; Bootstrap ' ...
    '(raw, SE columns); picks as wave windows\n']);
end

% =========================================================================
%  Part H -- the sound conduction delay (13 A9)
% =========================================================================
function partH_delay(app,v,k)
m = app.Model;
s1 = m.seriesKeys(); s1 = s1(1);
m.selectSeries(s1,Level=80);
H = v.Handles;
ax = H.Stack.Axes;
G0 = v.Geometry;
i = find(G0.Levels == 80);
ln = H.Stack.Lines(char(G0.Keys(i)));
x0 = ln.XData;
assert(string(ax.XLabel.String) == "Time re onset (ms)" && string(ax.Subtitle.String) == "", ...
    'With no delay the stack is not "re onset".');
m.selectWave("I","P");

m.setSessionOverrides(k.Base,struct('ConductionDelay',0.25));
S = m.Session;
G = v.Geometry;
assert(abs(G.Offset - 0.25) < 1e-12,'The view did not take the 0.25 ms offset.');
assert(string(ax.XLabel.String) == "Time re sound arrival (ms)" && contains(string(ax.Subtitle.String),"0.25") && ...
    contains(string(ax.XLabel.UserData),"0.25"),'The stack does not read "Time re sound arrival (ms)" naming the delay.');
ln = H.Stack.Lines(char(G.Keys(i)));
assert(max(abs(ln.XData(:) - (S.Time(:) - 0.25))) < 1e-12,'The traces are not in ear time.');
rw = S.ResponseWindow - 0.25;
assert(max(abs(H.Stack.Response.XData(:) - [rw(1);rw(2);rw(2);rw(1)])) < 1e-12,'The response window is not in ear time.');
ck = G.Keys(i);
raw = pk(m,ck,"I");
mk = H.Stack.Markers("I|P");
assert(abs(mk.XData(i) - (raw - 0.25)) < 1e-12,'Wave I is not marked at its latency re sound arrival.');
% the windows: written (and searched) in the recording's time, so on the
% ear-time axis they are drawn 0.25 ms earlier, like the traces and picks;
% moved by the latency shift per dB below the loudest level
st = S.Settings;
W = mabr.analysis.Peaks.wavesFor(st.Waves,"Tone",4,OctaveShift=st.PeakOctaveShift,RefFrequency=st.PeakRefFrequency);
w1 = W(string({W.Name}) == "I");
pw = H.Stack.Windows("I");
assert(strcmp(pw.Visible,'on') && max(abs(pw.XData(:) - ([w1.TMin;w1.TMax;w1.TMax;w1.TMin] - 0.25))) < 1e-12, ...
    'Wave I''s window is not drawn at its recording-time window less the 0.25 ms offset at the loudest level.');
m.selectLevel(40);
sh = w1.LatencyShift*40;
assert(max(abs(pw.XData(:) - ([w1.TMin;w1.TMax;w1.TMax;w1.TMin] + sh - 0.25))) < 1e-12, ...
    'At 40 dB wave I''s window is not moved by its latency shift (less the offset).');
m.selectLevel(80);
% each drawn window still holds its pick: at the loudest level the window
% is the one the picker searched, and an automatic pick lies inside it (to
% a sample, for the parabolic refinement) on the drawn axis as in raw time
G = v.Geometry;
dt = 1000/S.SampleRate;
nHeld = 0;
for j = 1:numel(G.Waves)
    wv = G.Waves(j);
    if G.State(i,j) ~= "auto" || ~isfinite(G.PeakLat(i,j)), continue; end
    wr = W(string({W.Name}) == wv);
    if isempty(wr), continue; end
    pwj = H.Stack.Windows(char(wv));
    mkj = H.Stack.Markers(char(wv + "|P"));
    x = mkj.XData(i);
    assert(strcmp(pwj.Visible,'on') && x >= min(pwj.XData) - dt && x <= max(pwj.XData) + dt, ...
        'Wave %s''s pick (%.3f ms drawn) is outside its drawn window [%.3f %.3f] with a 0.25 ms delay.', ...
        wv,x,min(pwj.XData),max(pwj.XData));
    assert(G.PeakLat(i,j) >= wr.TMin - dt && G.PeakLat(i,j) <= wr.TMax + dt, ...
        'Wave %s''s raw pick %.3f ms is outside its search window [%.3f %.3f].',wv,G.PeakLat(i,j),wr.TMin,wr.TMax);
    nHeld = nHeld + 1;
end
assert(nHeld >= 1,'No automatic pick at the loudest level to hold against its window.');
% reported latencies: the matrix and the latency plot
D = H.Matrix.Data;
assert(string(D{1,2}) == sprintf('%.2f',mabr.analysis.Peaks.reported(raw,0.25)),'The matrix does not show ear-time latency.');
assert(contains(string(H.Matrix.Tooltip),"sound arrival"),'The matrix tooltip does not name the delay.');
look(v,'PlotKind',"latency");
w = findobj(H.PeakPlot,'Tag','PeakPlotWave','DisplayName','I');
[~,o] = sort(G.Levels);
yl = G.PeakLat(o,1) - 0.25;  yl(G.Below(o,1) | ~ismember(G.State(o,1),["auto","manual"])) = NaN;
ys = string(H.PeakPlot.YLabel.String);
assert(isequaln(w.YData(:),yl) && ys(1) == "Latency (ms)" && numel(ys) == 2 && ys(2) == "re sound arrival" && ...
    contains(string(H.PeakPlot.YLabel.UserData),"0.25"), ...
    'The latency plot does not show reported (ear-time) latencies re sound arrival.');
look(v,'PlotKind',"io");
% a drag on the ear-time axis stores raw time
v.dragPeak("I","P",2.0);
assert(abs(pk(m,ck,"I") - 2.25) < 1e-12,'A drag to 2.00 ms re sound arrival stored %g ms raw, not 2.25.',pk(m,ck,"I"));
assert(abs(H.Stack.Selected.XData - 2.0) < 1e-12,'The dragged point is not drawn at 2.00 ms.');
m.undo();
% "Use current picks as wave windows" with the delay set: the windows are
% stored in the recording's time (the raw pick less the octave shift, not
% less the delay), so each is drawn centred on the pick it came from
G = v.Geometry;
P = m.Session.picksAsWindows(s1);
xs = containers.Map();
for j = 1:numel(G.Waves)
    if ismember(G.State(i,j),["auto","manual"]) && isfinite(G.PeakLat(i,j))
        xs(char(G.Waves(j))) = G.PeakLat(i,j);
    end
end
assert(xs.Count >= 1,'No pick at the loudest level to make a window of.');
shift = st.PeakOctaveShift*log2(st.PeakRefFrequency/4);
for nm = string(xs.keys)
    pj = P(string({P.Name}) == nm);
    assert(abs(pj.Expected - (xs(char(nm)) - shift)) < 1e-9, ...
        'Wave %s''s window from its pick is at %.4f ms, not the raw pick less the octave shift (%.4f ms).', ...
        nm,pj.Expected,xs(char(nm)) - shift);
end
push(findall(app.Figure,'Tag','AnalysisPeaksFitWindows'));
Ws = m.Settings.Waves;
Ws = Ws(string({Ws.Stimulus}) == "Tone");
assert(isequaln([Ws.Expected],[P.Expected]),'The stored windows are not picksAsWindows'' (recording time).');
m.selectLevel(80);
assert(v.Geometry.SeriesKey == s1 && abs(v.Geometry.Offset - 0.25) < 1e-12, ...
    'After the new windows the stack is not on the series with the delay.');
for nm = string(xs.keys)
    pwj = v.Handles.Stack.Windows(char(nm));          % (a re-fit may rebuild the stack)
    assert(strcmp(pwj.Visible,'on') && abs(mean([min(pwj.XData) max(pwj.XData)]) - (xs(char(nm)) - 0.25)) < 1e-9, ...
        'Wave %s''s window from its pick is not drawn centred on the pick (%.4f ms re sound arrival).', ...
        nm,xs(char(nm)) - 0.25);
end

m.setSessionOverrides(k.Base,struct('ConductionDelay',NaN));
ax = v.Handles.Stack.Axes;
ln = v.Handles.Stack.Lines(char(v.Geometry.Keys(i)));
assert(isequal(ln.XData,x0) && string(ax.XLabel.String) == "Time re onset (ms)" && ...
    string(ax.Subtitle.String) == "",'With the delay cleared the stack is not as before.');
m.flush();
fprintf(['  PASS Part H: a 0.25 ms delay: "Time re sound arrival (ms)" naming it; traces, response window, ' ...
    'picks and wave windows in ear time (windows drawn 0.25 ms earlier, moved per dB at 40 dB, each holding ' ...
    'its pick); matrix and latency plot reported; a drag stores raw; picks as windows stored in recording ' ...
    'time, drawn on their picks; cleared, as before\n']);
end

% =========================================================================
%  Part J -- an attenuation axis (larger number = quieter)
% =========================================================================
function partJ_attenuation(app,v,k)
m = app.Model;
m.openSession(k.Atten);
assert(m.levelParam() == "Attenuation",'The attenuation session''s level parameter is "%s".',m.levelParam());
m.analyze();
assert(m.Status.State == "current",'The attenuation session was not analysed (%s).',m.Status.Text);
sk = m.seriesKeys();
s1 = sk(1);
m.selectSeries(s1);
G = v.Geometry;
St = v.Handles.Stack;
ev = v.Handles.Evidence;
assert(G.Sign == -1 && isequal(G.Levels(:).',[80 40 0]) && string(St.Axes.YTickLabel{end}) == "0", ...
    'The loudest level (attenuation 0 dB) is not on top of the stack.');
% no response: SeriesThreshold reports it "left" of the numbers (below the
% smallest attenuation) -- still above the LOUDEST level, still NR, still
% the evidence's arrow at the top
press(app,'i');
r = thrRow(m,s1);
assert(r.Decision == "noresponse" && r.FinalCensored == "left", ...
    'No response on an attenuation axis is not left-censored (%s %s).',r.Decision,r.FinalCensored);
assert(abs(St.Final.YData(1) - (G.Offsets(end) + G.Step/2)) < 1e-9 && strcmp(St.FinalText.Visible,'on'), ...
    'No response on an attenuation axis is not a divider above the loudest level marked NR.');
c = findobj(ev,'Tag','EvidenceCensor');
assert(isscalar(c) && string(c.String) == "▲" && c.UserData == "noresponse" && c.Position(1) == 0, ...
    'No response on an attenuation axis is not ▲ at the top over 0 dB.');
m.undo();
% all respond: "right" of the numbers -- below the quietest level, no NR,
% ▼ at the bottom
press(app,'downarrow',{'alt'});
r = thrRow(m,s1);
assert(r.Decision == "allrespond" && r.FinalCensored == "right", ...
    'All respond on an attenuation axis is not right-censored (%s %s).',r.Decision,r.FinalCensored);
assert(abs(St.Final.YData(1) - (G.Offsets(1) - G.Step/2)) < 1e-9 && strcmp(St.FinalText.Visible,'off'), ...
    'All respond on an attenuation axis is not a divider below the quietest level (or it says NR).');
c = findobj(ev,'Tag','EvidenceCensor');
assert(isscalar(c) && string(c.String) == "▼" && c.UserData == "allrespond" && c.Position(1) == 80, ...
    'All respond on an attenuation axis is not ▼ at the bottom under 80 dB.');
m.undo();
% dragged (the mouse's callbacks): the preview stands where the release will
% leave the divider -- NR above the loudest row, all respond under the
% quietest -- and reads in the numbers' own terms (≤ 0 / > 80, as the list)
fig = app.Figure;
ax = St.Axes;
fig.SelectionType = 'normal';
u = "";  if G.Unit ~= "", u = " " + G.Unit; end
[y0,onLine] = v.thresholdHandleY();
xp = 8;  if ~onLine, xp = v.TimeWindow(2); end
setPoint(fig,ax,xp,y0);
ax.ButtonDownFcn(ax,[]);
setPoint(fig,ax,8,G.Offsets(end) + 0.3*G.Step);
fig.WindowButtonMotionFcn(fig,[]);
assert(v.ThresholdDragging && abs(St.Final.YData(1) - (G.Offsets(end) + G.Step/2)) < 1e-9 && ...
    strcmp(St.FinalText.Visible,'on') && v.ThresholdReadout == "No response (≤ 0" + u + ")", ...
    'Dragged above the loudest level of an attenuation axis, the preview is not NR above it ("%s").', ...
    v.ThresholdReadout);
setPoint(fig,ax,8,G.Offsets(1) - 0.3*G.Step);
fig.WindowButtonMotionFcn(fig,[]);
assert(abs(St.Final.YData(1) - (G.Offsets(1) - G.Step/2)) < 1e-9 && strcmp(St.FinalText.Visible,'off') && ...
    v.ThresholdReadout == "All respond (> 80" + u + ")", ...
    'Dragged below the quietest level of an attenuation axis, the preview is not under it ("%s").', ...
    v.ThresholdReadout);
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,s1);
assert(r.Decision == "allrespond" && abs(St.Final.YData(1) - (G.Offsets(1) - G.Step/2)) < 1e-9, ...
    'The release below the quietest level is not all respond where its preview stood.');
m.undo();
m.openSession(k.Base);
fprintf(['  PASS Part J: an attenuation axis -- the loudest (0 dB) on top; no response (left of the ' ...
    'numbers) is the NR divider above it and ▲ at the top, all respond the divider below the ' ...
    'quietest and ▼ at the bottom; dragged there, each preview stands where its release leaves the ' ...
    'divider ("≤ 0", "> 80")\n']);
end

% =========================================================================
%  Part K -- a Level parameter that is not a sound level (Frequency)
% =========================================================================
function partK_levelAxis(app,v,k)
m = app.Model;
if m.SessionKey ~= k.Base, m.openSession(k.Base); end
ax = v.Handles.Audiogram;
assert(isscalar(findobj(ax,'Tag','AudiogramLine')),'The baseline audiogram is not drawn.');
s0 = m.Settings;
s = s0;
s.LevelParam = "Frequency";
m.setSettings(s);
assert(m.levelParam() == "Frequency",'The session was not re-fitted along Frequency (level parameter "%s").', ...
    m.levelParam());
sks = m.seriesKeys();
assert(~isempty(sks),'No series along Frequency.');
m.selectSeries(sks(1));
G = v.Geometry;
% each series is a frequency sweep at one level: no place on an audiogram
% (its first condition's frequency would mislabel it) -- listed beneath,
% the reason first, each threshold in kHz
note = string(v.Handles.AudiogramNote.Text);
assert(isempty(findobj(ax,'Tag','AudiogramLine')) && isempty(findobj(ax,'Tag','AudiogramPoint')) && ...
    isempty(findobj(ax,'Tag','AudiogramCurrent')) && strcmp(ax.Visible,'off'), ...
    'The audiogram plots series whose level axis is Frequency.');
assert(startsWith(note,"No audiogram: these thresholds are along Frequency, not a sound level."), ...
    'The audiogram does not say why the series along Frequency are not on it: "%s".',note);
T = m.Session.Thresholds;
listed = sks(ismember(sks,string(T.Key)));
assert(~isempty(listed) && all(arrayfun(@(x) contains(note,m.seriesLabel(x)),listed)) && ...
    contains(note,"kHz"),'The series along Frequency are not listed beneath (in kHz): "%s".',note);
assert(G.Unit == "kHz" && string(v.Handles.Stack.Axes.YLabel.String) == "Frequency (kHz)", ...
    'The level axis along Frequency is not labelled in kHz (stack "%s").',string(v.Handles.Stack.Axes.YLabel.String));
% back to the automatic level: the audiogram as it was
m.setSettings(s0);
sk2 = m.seriesKeys();
m.selectSeries(sk2(1));
L = findobj(ax,'Tag','AudiogramLine');
assert(m.levelParam() == "Level" && isscalar(L) && isequal(L.XData(:),[4;16]) && ...
    strcmp(ax.Visible,'on') && string(v.Handles.AudiogramNote.Text) == "", ...
    'Back on the sound level the audiogram is not as it was.');
assert(startsWith(string(v.Handles.Stack.Axes.YLabel.String),"Level (dB"), ...
    'Back on the sound level the stack does not read "Level (dB…)".');
m.flush();
fprintf(['  PASS Part K: Level parameter = Frequency -- no series on the audiogram, each listed beneath ' ...
    'after the reason, the level axis in kHz; back on Level, the audiogram as before\n']);
end

% =========================================================================
%  Part L -- the threshold by hand (the divider dragged)
% =========================================================================
function partL_drag(app,v,k)
% Everything through the mouse's own callbacks: the figure's CurrentPoint
% is set (setPoint) and the axes' ButtonDownFcn, then the window's
% WindowButtonMotionFcn / WindowButtonUpFcn / WindowKeyPressFcn are called
% as MATLAB would call them.
m = app.Model;
fig = app.Figure;
if m.SessionKey ~= k.Base, m.openSession(k.Base); end
app.activateTab("Series");
sk = m.seriesKeys();
s1 = sk(1);
m.selectSeries(s1,Level=40);
if m.Selection.Wave ~= "", press(app,'escape'); end          % no wave point selected
if thrRow(m,s1).Decision ~= "", m.clearDecision(s1); end
G = v.Geometry;
St = v.Handles.Stack;
ax = St.Axes;
assert(isequal(G.Levels(:).',0:20:80),'(Part L needs the 0:20:80 dB series)');
u = "";  if G.Unit ~= "", u = " " + G.Unit; end
mid = @(a,b) (G.Offsets(a) + G.Offsets(b))/2;
green = mabr.ui.analysis.Style.FinalGreen;
x8 = 8;                                       % late in the window: no wave point there
up0 = fig.WindowButtonUpFcn;  key0 = fig.WindowKeyPressFcn;  mot0 = fig.WindowButtonMotionFcn;

% the divider's grip, and the pointer over the divider (the app's own
% motion callback asks the view)
[y0,onLine] = v.thresholdHandleY();
gp = St.Grip;
assert(onLine && abs(y0 - St.Final.YData(1)) < 1e-12 && strcmp(gp.Visible,'on') && gp.YData == y0 && ...
    gp.XData == v.TimeWindow(2) && isequal(gp.MarkerFaceColor,green), ...
    'The final threshold has no filled grip at the right end of its divider.');
setPoint(fig,ax,x8,y0);
fig.WindowButtonMotionFcn(fig,[]);
assert(v.hoverPointer() == "top" && strcmp(fig.Pointer,'top'),'Over the divider the pointer is not the resize arrows.');
setPoint(fig,ax,x8,G.Offsets(1));
fig.WindowButtonMotionFcn(fig,[]);
assert(v.hoverPointer() == "" && strcmp(fig.Pointer,'arrow'),'Away from the divider the pointer stays the resize arrows.');

% (start from a known 70 dB, well away from the 20-40 dB gap the drag goes to:
% where the fit itself lands depends on the fixture's detections, and a
% move under ThresholdDrag's few pixels is a click, not a drag)
m.setThresholdValue(70,s1);
[y0,onLine] = v.thresholdHandleY();
assert(onLine,'(the 70 dB start has no divider)');

% 1. a drag SNAPS half way between two levels: the louder is the lowest
%    level with a response, what "t" there decides -- with a live readout
nU = numel(m.undoHistory());  nE = height(m.Session.EditLog);
setPoint(fig,ax,x8,y0);
fig.SelectionType = 'normal';
ax.ButtonDownFcn(ax,[]);
assert(v.ThresholdDragging,'A press on the divider did not take it.');
setPoint(fig,ax,x8,G.Offsets(2) + 0.3*G.Step);              % between 20 and 40 dB
fig.WindowButtonMotionFcn(fig,[]);
assert(v.ThresholdReadout == "Threshold 30" + u && abs(St.Final.YData(1) - mid(2,3)) < 1e-12 && ...
    strcmp(fig.Pointer,'top'),'Mid-drag the divider is not snapped half way with its readout ("%s").', ...
    v.ThresholdReadout);
rd = findall(ax,'Tag','SeriesThresholdReadout');
assert(isscalar(rd) && string(rd.String) == v.ThresholdReadout && contains(statusText(app),"release to set") && ...
    string(v.Handles.Cursor.Text) == v.ThresholdReadout,'The readout is not beside the divider, in the strip and on the status line.');
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,s1);
assert(~v.ThresholdDragging && r.Decision == "manual" && r.ManualKind == "level" && r.ManualValue == 40 && ...
    r.FinalCensored == "interval" && r.FinalLo == 20 && r.FinalHi == 40 && r.Final == 30, ...
    'The drop between 20 and 40 dB did not set the threshold at 40 dB (30 (20–40]): %s %s %g.', ...
    r.Decision,r.ManualKind,r.ManualValue);
L = m.Session.EditLog;
assert(numel(m.undoHistory()) == nU + 1 && height(L) == nE + 1 && string(L.Action(end)) == "setDecision" && ...
    string(L.Key(end)) == s1 && contains(string(L.New(end)),"manual") && contains(string(L.New(end)),"30"), ...
    'The drop is not one undo step and one EditLog row (Decision manual, 30).');
assert(abs(St.Final.YData(1) - mid(2,3)) < 1e-12 && isempty(findall(ax,'Tag','SeriesThresholdReadout')) && ...
    v.ThresholdReadout == "" && contains(statusText(app),"Ctrl+Z to undo"), ...
    'After the drop the divider is not at the snapped place, or the readout stayed.');
assert(isequal(fig.WindowButtonUpFcn,up0) && isequal(fig.WindowKeyPressFcn,key0) && ...
    isequal(fig.WindowButtonMotionFcn,mot0),'The drag did not give the window its callbacks back.');

% 2. Alt (the window's key during the drag): the exact value, to 0.1 dB
setPoint(fig,ax,x8,St.Final.YData(1));
ax.ButtonDownFcn(ax,[]);
fig.WindowKeyPressFcn(fig,keyEvt('alt',{'alt'}));
setPoint(fig,ax,x8,G.Offsets(3) + 0.37*G.Step);
fig.WindowButtonMotionFcn(fig,[]);
cp = ax.CurrentPoint;
vx = round(interp1(G.Offsets,G.Levels,cp(1,2))*10)/10;
assert(v.ThresholdReadout == "Threshold " + string(sprintf('%g',vx)) + u, ...
    'With Alt the readout is "%s", not the value at the pointer (%g).',v.ThresholdReadout,vx);
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,s1);
assert(r.Decision == "manual" && r.ManualKind == "value" && abs(r.ManualValue - vx) < 1e-9 && ...
    r.FinalCensored == "none" && abs(r.Final - vx) < 1e-9 && contains(string(m.Session.EditLog.New(end)),sprintf('%g',vx)), ...
    'Alt did not set the exact value %g (%s %s %g).',vx,r.Decision,r.ManualKind,r.ManualValue);

% 3./4. above the loudest level: no response; below the quietest: all respond
v.dragThreshold(G.Offsets(end) + 0.3*G.Step);
r = thrRow(m,s1);
assert(r.Decision == "noresponse" && r.FinalCensored == "right" && strcmp(St.FinalText.Visible,'on') && ...
    abs(St.Final.YData(1) - (G.Offsets(end) + G.Step/2)) < 1e-12 && contains(statusText(app),"no response"), ...
    'A drop above the loudest level is not no response, NR above the top row (%s).',r.Decision);
v.dragThreshold(G.Offsets(1) - 0.3*G.Step);
r = thrRow(m,s1);
assert(r.Decision == "allrespond" && r.FinalCensored == "left" && ...
    abs(St.Final.YData(1) - (G.Offsets(1) - G.Step/2)) < 1e-12 && contains(statusText(app),"all levels respond"), ...
    'A drop below the quietest level is not all respond (%s).',r.Decision);

% 5. Esc cancels -- the app's key, and the window's own during the drag
nU = numel(m.undoHistory());
yb = St.Final.YData(1);
for way = 1:2
    setPoint(fig,ax,x8,yb);
    ax.ButtonDownFcn(ax,[]);
    setPoint(fig,ax,x8,mid(3,4));
    fig.WindowButtonMotionFcn(fig,[]);
    assert(abs(St.Final.YData(1) - mid(3,4)) < 1e-12,'(the preview did not follow the pointer)');
    if way == 1
        press(app,'escape');
    else
        fig.WindowKeyPressFcn(fig,keyEvt('escape'));
    end
    assert(~v.ThresholdDragging && thrRow(m,s1).Decision == "allrespond" && numel(m.undoHistory()) == nU && ...
        abs(St.Final.YData(1) - yb) < 1e-12 && v.ThresholdReadout == "" && isequal(fig.WindowButtonUpFcn,up0) && ...
        isequal(fig.WindowKeyPressFcn,key0) && contains(statusText(app),"cancelled"), ...
        'Esc (way %d) did not cancel the drag and put the divider back.',way);
end

% 6. Ctrl+Z undoes a drop
press(app,'z',{'control'});
assert(thrRow(m,s1).Decision == "noresponse",'Ctrl+Z did not undo the all-respond drop.');
m.undo();  m.undo();  m.undo();
assert(thrRow(m,s1).Decision == "manual" && thrRow(m,s1).ManualValue == 70, ...
    'The drops were not all undone (back to the 70 dB start).');
m.undo();                                    % and the 70 dB start itself
assert(thrRow(m,s1).Decision == "",'The 70 dB start was not undone.');

% 7. a press on the divider let go where it was: the ordinary click -- it
%    selects the level whose band it is in (2 px under the divider)
G = v.Geometry;
yF = St.Final.YData(1);
pp = getpixelposition(ax);
sy = pp(4)/diff(ax.YLim);
yc = yF - 2/sy;
iBand = min(max(round((yc - G.Offsets(1))/G.Step) + 1,1),numel(G.Offsets));
m.selectLevel(G.Levels(mod(iBand,numel(G.Levels)) + 1));   % another level first
lv0 = m.Selection.Level;
nU = numel(m.undoHistory());
setPoint(fig,ax,x8,yc);
ax.ButtonDownFcn(ax,[]);
assert(v.ThresholdDragging,'A press 2 px from the divider did not take it.');
fig.WindowButtonUpFcn(fig,[]);
assert(~v.ThresholdDragging && m.Selection.Level == G.Levels(iBand) && lv0 ~= G.Levels(iBand) && ...
    numel(m.undoHistory()) == nU && thrRow(m,s1).Decision == "", ...
    'A press on the divider let go where it was did not select the level under it (%g).',m.Selection.Level);
% 8. a click away from the divider selects as ever
setPoint(fig,ax,1.5,G.Offsets(2));
ax.ButtonDownFcn(ax,[]);
assert(~v.ThresholdDragging && m.Selection.Level == 20,'A click on the 20 dB trace did not select it.');

% 9. the selected wave point keeps its drag
m.selectLevel(80);
press(app,'1');
G = v.Geometry;
ck = G.Keys(G.Levels == 80);
sel = St.Selected;
px = sel.XData;  py = sel.YData;
setPoint(fig,ax,px,py);
ax.ButtonDownFcn(ax,[]);
assert(v.Dragging && ~v.ThresholdDragging,'A press on the selected wave point did not take the point.');
setPoint(fig,ax,px + 0.3,py);
fig.WindowButtonMotionFcn(fig,[]);
cp = ax.CurrentPoint;
fig.WindowButtonUpFcn(fig,[]);
assert(~v.Dragging && abs(pk(m,ck,"I") - cp(1,1)) < 1e-6 && thrRow(m,s1).Decision == "", ...
    'The wave point drag did not place wave I where it was let go (%.3f, want %.3f).',pk(m,ck,"I"),cp(1,1));
m.undo();
press(app,'escape');

% 10. the evidence plot: a click in its band of counts sets the threshold
%     where it lands; its green line drags along the level axis; a press
%     elsewhere in it does nothing
ev = v.Handles.Evidence;
yl = ev.YLim;
nU = numel(m.undoHistory());
setPoint(fig,ev,50,yl(1) + 0.03*diff(yl));
ev.ButtonDownFcn(ev,[]);
dl = findall(ev,'Tag','EvidenceThresholdDrag');
assert(v.ThresholdDragging && v.ThresholdReadout == "Threshold 50" + u && isscalar(dl) && ...
    all(abs(dl.XData - 50) < 1e-9),'A click in the evidence band does not preview 50 dB there ("%s").', ...
    v.ThresholdReadout);
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,s1);
assert(r.Decision == "manual" && r.ManualValue == 60 && r.Final == 50 && numel(m.undoHistory()) == nU + 1 && ...
    isempty(findall(ev,'Tag','EvidenceThresholdDrag')),'The evidence band click did not set 50 (40–60].');
fl = findobj(ev,'Tag','EvidenceFinal');
assert(isscalar(fl) && all(abs(fl.XData - 50) < 1e-9),'The evidence plot''s green line is not at 50.');
setPoint(fig,ev,50,mean(yl));
ev.ButtonDownFcn(ev,[]);
assert(v.ThresholdDragging,'A press on the evidence plot''s green line did not take it.');
setPoint(fig,ev,73,mean(yl));
fig.WindowButtonMotionFcn(fig,[]);
fig.WindowButtonUpFcn(fig,[]);
r = thrRow(m,s1);
assert(r.Decision == "manual" && r.ManualValue == 80 && r.Final == 70,'The evidence line dragged to 73 dB did not set 70 (60–80].');
nU = numel(m.undoHistory());
setPoint(fig,ev,10,mean(yl));
ev.ButtonDownFcn(ev,[]);
assert(~v.ThresholdDragging && numel(m.undoHistory()) == nU,'A press in the evidence plot away from its line did something.');
% the band of counts offers its click (the hand) -- but not through the
% Peaks sub-tab, which sits in the evidence plot's place
setPoint(fig,ev,50,yl(1) + 0.03*diff(yl));
fig.WindowButtonMotionFcn(fig,[]);
assert(v.hoverPointer() == "hand" && strcmp(fig.Pointer,'hand'),'Over the evidence plot''s band of counts the pointer is not the hand.');
H = v.Handles;
H.Side.SelectedTab = H.SidePeaks;
setPoint(fig,ev,50,yl(1) + 0.03*diff(yl));
fig.WindowButtonMotionFcn(fig,[]);
assert(v.hoverPointer() == "" && strcmp(fig.Pointer,'arrow'), ...
    'Over the Peaks sub-tab, in the evidence plot''s place, the pointer still offers the threshold.');
H.Side.SelectedTab = H.SideThreshold;
m.undo();  m.undo();

% 11. no final threshold yet (excluded): a hollow grip, dragged as the line
m.toggleExcluded();
[yg,onLine] = v.thresholdHandleY();
assert(~onLine && isfinite(yg) && strcmp(St.Grip.Visible,'on') && isequal(St.Grip.MarkerFaceColor,[1 1 1]) && ...
    strcmp(St.Final.Visible,'off'),'An excluded series offers no hollow grip to drag.');
v.dragThreshold(mid(4,5));                   % (far from the fit, where the hollow grip sits)
r = thrRow(m,s1);
assert(r.Decision == "manual" && r.ManualValue == 80 && isequal(St.Grip.MarkerFaceColor,green), ...
    'Dragging the hollow grip did not set the threshold (%s).',r.Decision);
m.undo();  m.undo();
assert(thrRow(m,s1).Decision == "",'The grip drag was not undone.');

% 12. F1 lists the drag, and the hint strip's tooltip says it
assert(startsWith(mabr.ui.analysis.Commands.hint("series"),"drag green line") && ...
    contains(string(v.Handles.Hints.Tooltip),mabr.ui.analysis.ThresholdDrag.Hint), ...
    'The hint strip does not name the threshold drag.');
press(app,'f1');
kw = findall(groot,'Tag','MABR_OFFLINE_KEYS');
kt = findall(kw,'Tag','AnalysisKeysTable');
D = kt.Data;
assert(any(string(D.Keys) == "Drag the green line" & contains(string(D.Command),"Alt")), ...
    'F1 does not list dragging the green line.');
kw.CloseRequestFcn(kw,[]);
assert(isempty(findall(groot,'Tag','MABR_OFFLINE_KEYS')),'(the F1 window did not close)');
fprintf(['  PASS Part L: the divider''s grip and pointer; dragged (the callbacks, CurrentPoint) it snaps ' ...
    'half way -- manual at the louder level, one undo step, an EditLog row, a live readout; Alt the ' ...
    'exact value; above/below the levels no response / all respond; Esc (app and window) cancels; ' ...
    'Ctrl+Z undoes; a press on it let go selects, clicks select, the wave point drags; the evidence ' ...
    'band and line; a hollow grip with no threshold; F1 and the hints\n']);
end

% =========================================================================
%  Part M -- the report of a latency-only settings change
% =========================================================================
function partM_report(app,k)
m = app.Model;
if m.SessionKey ~= k.Base, m.openSession(k.Base); end
s0 = m.Settings;
T0 = m.Session.Thresholds;
s = s0;
s.TimeOffset = s0.TimeOffset + 0.1;
txt = m.setSettings(s);
T1 = m.Session.Thresholds;
assert(startsWith(txt,"Settings applied") && contains(txt,"peak latencies") && ...
    contains(txt,sprintf('%.2f ms latency offset',s.latencyOffset())) && contains(txt,"no threshold changed") && ...
    ~contains(txt,"re-fitted") && contains(statusText(app),"no threshold changed"), ...
    'A time offset changed alone is reported as "%s".',txt);
assert(isequaln(T1.Final,T0.Final) && isequaln(T1.Threshold,T0.Threshold), ...
    'A time offset changed a threshold.');
txt = m.setSettings(s0);
assert(contains(txt,"no threshold changed"),'Putting the offset back is reported as "%s".',txt);
sk = m.seriesKeys();
C = m.compareMethods(sk(1));
assert(ismember('Flags',C.Properties.VariableNames) && isstring(C.Flags), ...
    'Compare methods does not give each method''s flags.');
fprintf(['  PASS Part M: a time offset alone -- "peak latencies ... latency offset ...; no threshold ' ...
    'changed" (none did), and back; Compare methods carries the flags\n']);
end

% =========================================================================
%  Part I -- the look (the only pref writes), icons, hints
% =========================================================================
function partI_look(app,v,prefs0)
m = app.Model;
H = v.Handles;
G = v.Geometry;
i = numel(G.Keys);
ln = H.Stack.Lines(char(G.Keys(i)));
y0 = ln.YData;
press(app,'equal');
assert(isvalid(ln) && ln == H.Stack.Lines(char(G.Keys(i))),'+ rebuilt the stack.');
G1 = v.Geometry;
assert(max(abs((ln.YData - G1.Offsets(i)) - 1.25*(y0 - G.Offsets(i)))) < 1e-9,'+ did not scale the traces by 1.25.');
press(app,'0',{'control'});
assert(max(abs(ln.YData - y0)) < 1e-12,'Ctrl+0 did not reset the scale.');
press(app,'n');
in = ln.XData >= v.TimeWindow(1) & ln.XData <= v.TimeWindow(2);
Gn = v.Geometry;
assert(Gn.Normalized && Gn.Step == 1 && max(abs(ln.YData(in) - Gn.Offsets(i)),[],'omitnan') <= 0.5 + 1e-9, ...
    'n did not normalise the traces.');
press(app,'n');
d = changedPrefs(prefs0,allPrefs());
assert(isempty(d),'A key wrote a pref: %s',strjoin(d,', '));

drive(H.Polarity,'overlay');
ln2 = H.Stack.Lines2(char(G.Keys(i)));
assert(strcmp(ln2.Visible,'on') && any(isfinite(ln2.YData)),'+/− overlay does not draw the negative average.');
drive(H.Normalize,true);
drive(H.PeaksShow,'pn');
drive(H.PlotKind,'latency');
H.Side.SelectedTab = H.SidePeaks;
H.Side.SelectionChangedFcn(H.Side,struct('NewValue',H.SidePeaks));
p = getpref('MABR','OfflineAnalysisSeries');
assert(p.Polarity == "overlay" && p.Normalize && p.PeaksShow == "pn" && p.PlotKind == "latency" && ...
    p.SideTab == "Peaks",'The look controls did not remember the look.');
d = mabr.ui.analysis.SeriesView.loadDefaults();
assert(isequal(d,p),'loadDefaults does not read back what the controls wrote.');
drive(H.Polarity,'balanced');
assert(strcmp(ln2.Visible,'off'),'Balanced still draws the negative average.');

% the A6 pictures and the hint strip
glyphs = ["AnalysisThresholdAccept","AnalysisThresholdAtLevel","AnalysisThresholdNoResponse", ...
    "AnalysisThresholdExclude","AnalysisThresholdNote","AnalysisPeaksAutoPick","AnalysisPeaksRetrack", ...
    "AnalysisPeaksClear","AnalysisPeaksWaves","AnalysisPeaksCopy"];
for t = glyphs
    b = findall(app.Figure,'Tag',t);
    assert(isscalar(b) && ~isempty(b.Icon),'%s has no picture.',t);
end
% the hint strip: the keys that fit, then "F1 all keys"; all of them in its tooltip
full = mabr.ui.analysis.Commands.hint("series");
ht = string(H.Hints.Text);
assert(endsWith(ht,"F1 all keys") && startsWith(full,extractBefore(ht,strlength(ht) - strlength("F1 all keys") + 1)) && ...
    contains(string(H.Hints.Tooltip),full),'The hint strip is not a prefix of Commands.hint("series") (%s).',ht);
short = mabr.ui.analysis.Commands.hint("series",MaxChars=40);
assert(strlength(short) <= 40 && endsWith(short,"F1 all keys"),'Commands.hint MaxChars does not fit the strip.');
assert(m.KeyTarget == "plot",'The look controls left the keyboard off the plots.');

% the stack's margins are PIXELS, laid out on a resize: the tick labels and
% the level label, the detection glyph and the sweep count keep their room
% however narrow the window (11 sec. 1.3's minimum leaves the stack ~250 px)
sp = H.StackPanel;
sp.SizeChangedFcn(sp,[]);
pos = getpixelposition(sp);
ax = v.Handles.Stack.Axes;
mg = v.StackMargins;
P = ax.Position.*[pos(3) pos(4) pos(3) pos(4)];
assert(max(abs(P - [mg(1) mg(2) pos(3)-mg(1)-mg(3) pos(4)-mg(2)-mg(4)])) < 1e-6, ...
    'The stack axes'' margins are not %s px.',mat2str(mg));
xl = ax.XLim;
pxPerMs = (pos(3) - mg(1) - mg(3))/diff(xl);
g = v.Handles.Stack.Glyphs(1);  c = v.Handles.Stack.Counts(1);
assert(abs((g.Position(1) - xl(2))*pxPerMs - v.MarginGlyphPx) < 1e-6 && ...
    abs((c.Position(1) - xl(2))*pxPerMs - v.MarginCountPx) < 1e-6, ...
    'The detection glyph and sweep count are not %d and %d px past the axes.',v.MarginGlyphPx,v.MarginCountPx);
narrow = isequal(H.Grid.ColumnWidth{1},v.ListWidth(2));
cw = H.Strip.ColumnWidth;
assert(isequal(cw{5},0) == narrow,'The strip and the columns disagree about the window''s width.');
% the side plots sit at their pixel margins inside their panels (AutoResizeChildren
% off: the uifigure does not rescale them), however the panel was laid out
for f = ["Evidence","Audiogram","PeakPlot"]
    ax = H.(f);
    p = ax.Parent;
    assert(strcmp(p.AutoResizeChildren,'off'),'The %s panel resizes its axes itself.',f);
    pos = ax.Position;
    assert(all(pos >= 0) && pos(1) + pos(3) <= 1 + 1e-9 && pos(2) + pos(4) <= 1 + 1e-9, ...
        'The %s axes reach outside their panel (%s).',f,mat2str(pos,3));
    p.SizeChangedFcn(p,[]);
    pp = getpixelposition(p);
    mg = getappdata(ax,'MABRAxesMargins');
    P = ax.Position.*[pp(3) pp(4) pp(3) pp(4)];
    assert(max(abs(P - [mg(1) mg(2) pp(3)-mg(1)-mg(3) pp(4)-mg(2)-mg(4)])) < 1e-6, ...
        'The %s axes are not at their %s px margins.',f,mat2str(mg));
end
fprintf(['  PASS Part I: + / Ctrl+0 / n redraw in place without a pref; the look controls write ' ...
    'OfflineAnalysisSeries (read back by loadDefaults); the A6 pictures; the hint strip; the stack''s ' ...
    'margins in pixels\n']);
end

% =========================================================================
%  helpers
% =========================================================================
function x = writeExtra(F)
% Two sessions written into the fixture's study before the app scans it:
% SUBJ-ID-9004, every series a single level (80 dB); SUBJ-ID-9005, whose
% level parameter is renamed "Gain" (not a level alias) beside Frequency,
% so the level axis cannot be told.
t = F.Truth;
t.Freqs = [4 16];  t.Threshold = [30 40];  t.nSweeps = 16;
t.ArtifactSweeps = [];  t.FlaggedSweeps = [];
t1 = t;  t1.Levels = 80;  t1.Freqs = 4;  t1.Threshold = 30;
sub = "SUBJ-ID-9004";
mabrtest.SyntheticABR.writeSession(fullfile(F.Root,sub,sub + "_Baseline"),t1,'Subject',sub, ...
    'Start',datetime(2026,10,1,9,0,0));
x.Single = sub + "/" + sub + "_Baseline";
t2 = t;  t2.Levels = [40 80];
sub = "SUBJ-ID-9005";
folder = fullfile(F.Root,sub,sub + "_Baseline");
mabrtest.SyntheticABR.writeSession(folder,t2,'Subject',sub,'Start',datetime(2026,10,1,9,0,0));
L = dir(fullfile(folder,'*.abr'));
for f = 1:numel(L)
    file = fullfile(folder,L(f).name);
    A = load(file,'-mat');
    ABR_Data = A.ABR_Data;
    SIG = ABR_Data.SIG;
    SIG.Gain = SIG.Level;
    SIG = rmfield(SIG,'Level');
    ip = string(SIG.informativeParams);
    ip(ip == "Level") = "Gain";
    SIG.informativeParams = cellstr(ip);
    SIG.Label = cellstr(replace(string(SIG.Label),"Level = ","Gain = "));
    ABR_Data.SIG = SIG;
    save(file,'ABR_Data','-v6');
end
x.NoLevel = sub + "/" + sub + "_Baseline";
% SUBJ-ID-9006: one frequency at 0/40/80 dB SPL written as an ATTENUATION
% axis (80 - level: 80, 40, 0 dB), where a larger number is quieter
t3 = t;  t3.Levels = [0 40 80];  t3.Freqs = 4;  t3.Threshold = 30;  t3.nSweeps = 32;
sub = "SUBJ-ID-9006";
folder = fullfile(F.Root,sub,sub + "_Baseline");
mabrtest.SyntheticABR.writeSession(folder,t3,'Subject',sub,'Start',datetime(2026,10,1,9,0,0));
L = dir(fullfile(folder,'*.abr'));
for f = 1:numel(L)
    file = fullfile(folder,L(f).name);
    A = load(file,'-mat');
    ABR_Data = A.ABR_Data;
    SIG = ABR_Data.SIG;
    SIG.Attenuation = 80 - SIG.Level;
    SIG = rmfield(SIG,'Level');
    ip = string(SIG.informativeParams);
    ip(ip == "Level") = "Attenuation";
    SIG.informativeParams = cellstr(ip);
    lab = string(SIG.Label);
    lab(startsWith(lab,"Level = ")) = sprintf('Attenuation = %g',SIG.Attenuation);
    SIG.Label = cellstr(lab);
    ABR_Data.SIG = SIG;
    save(file,'ABR_Data','-v6');
end
x.Atten = sub + "/" + sub + "_Baseline";
end

function key = keyOf(F,part,subject)
key = F.Keys(contains(F.Keys,part) & startsWith(F.Keys,subject));
assert(isscalar(key),'No single fixture session matching %s.',part);
end

function app = newApp(F)
app = mabr.ui.AnalysisApp("",Visible="off",ResultsFolder=F.ResultsFolder, ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false,RememberState=false, ...
    ProgressMode="none",AutoRefresh=false, ...
    ConfirmFcn=@(msg,title,options,default) string(options(1)), ...
    AlertFcn=@(msg,title,icon) [],PromptFcn=@(prompt,title,default) [], ...
    PickFolderFcn=@(start,title) "",PickFileFcn=@(filter,title,mode,default) "");
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

function look(v,name,value)
% A look setting as a configuration applies it (no pref is written).
v.applySettings(struct(name,value));
end

function push(b)
assert(isscalar(b) && isvalid(b),'No such button.');
b.ButtonPushedFcn(b,[]);
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
if ~m.KeysSuspended
    m.KeyTarget = "plot";
    m.FocusArea = "workspace";
end
ok = app.dispatchKey(struct('Key',key,'Modifier',{mods},'Character',ch));
assert(ok,'The key %s (%s) was not handled.',key,strjoin(string(mods),'+'));
end

function closeNote(app)
% x opens the note editor after an exclusion; close it as Escape would.
if app.NoteEditor.IsOpen, app.NoteEditor.cancel(); end
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

function listClick(v,k)
% A click on row k of the series list.
t = v.Handles.List;
cb = [];
try
    cb = t.SelectionChangedFcn;
catch
end
if isempty(cb), cb = t.CellSelectionCallback; end
mabr.ui.analysis.Compat.setSelectedRows(t,k);
cb(t,struct('Indices',[k 1]));
end

function [txt,on] = emptyState(fig)
lab = findall(fig,'Tag','AnalysisSeriesEmpty');
pan = findall(fig,'Tag','AnalysisSeriesEmptyPanel');
txt = ""; on = false;
if ~isempty(lab), txt = string(lab.Text); end
if ~isempty(pan), on = strcmp(pan.Visible,'on'); end
end

function s = statusText(app)
s = string(findall(app.Figure,'Tag','AnalysisStatusText').Text);
end

function row = thrRow(m,sk)
T = m.Session.Thresholds;
row = table2struct(T(string(T.Key) == sk,:));
for f = ["Decision","FinalCensored","Censored","Flags","Note","ManualKind"]
    if isfield(row,f)
        s = string(row.(f));
        if isempty(s) || ismissing(s(1)), s = ""; end
        row.(f) = s(1);
    end
end
end

function v = seedOf(m,sk)
% What the value field holds when nobody has typed in it: the series'
% Final to one decimal, else the selected level.
r = thrRow(m,sk);
v = double(r.Final);
if ~isfinite(v), v = m.Selection.Level; end
if ~isfinite(v), v = 0; end
v = round(v*10)/10;
end

function lv = expectLevel(m,sk)
% 11 sec. 7.1, independently: the lowest level at or above the Final
% threshold (an interval: at or above its upper bound), the loudest for no
% response, the quietest for all respond, the loudest otherwise.
[~,lvs] = seriesLevels(m,sk);
r = thrRow(m,sk);
lv = max(lvs);
switch r.FinalCensored
    case "interval", k = find(lvs >= r.FinalHi - 1e-9,1); if ~isempty(k), lv = lvs(k); end
    case "none",     k = find(lvs >= r.Final - 1e-9,1);   if ~isempty(k), lv = lvs(k); end
    case "left",     lv = min(lvs);
end
end

function [ck,lv] = seriesLevels(m,sk)
ck = reshape(string(m.seriesConditions(sk)),[],1);
C = m.Session.Conditions;
lv = double(C.Level(rowsOf(m.Session,ck)));
end

function r = rowsOf(S,ck)
[~,r] = ismember(ck,string(S.Conditions.Key));
end

function y = wantY(G,v,c,lo,hi)
at = @(L) interp1(G.Levels,G.Offsets,L,'linear','extrap');
switch c
    case "interval", y = (at(lo) + at(hi))/2;
    case "none",     y = at(v);
    case "right",    y = G.Offsets(end) + G.Step/2;
    case "left",     y = G.Offsets(1) - G.Step/2;
    otherwise,       y = NaN;
end
end

function v = overrideOf(m,ck)
v = NaN;
D = m.Session.DetectionOverrides;
r = find(string(D.Key) == ck,1,'last');
if ~isempty(r), v = double(D.Value(r)); end
end

function s = withCustomDefaults(s)
% The settings as the fixture had them: perm-glm with the custom fields at
% their class defaults (the custom row changed them while it was on).
d = mabr.analysis.Settings();
s.ThresholdMetric = d.ThresholdMetric;
s.ThresholdModel  = d.ThresholdModel;
s.CriterionMode   = d.CriterionMode;
s.Criterion       = d.Criterion;
end

function lat = pk(m,ck,wave)
P = m.Session.Peaks;
lat = double(P.PeakLatency(string(P.Key) == ck & string(P.Wave) == wave));
end

function st = peakState(m,ck,wave)
P = m.Session.Peaks;
st = string(P.State(string(P.Key) == ck & string(P.Wave) == wave));
end

function s = pixelsPerMs(ax)
pos = getpixelposition(ax);
s = pos(3)/diff(ax.XLim);
end

function lat = snapExpected(S,ck,t0,win)
% Session.setPeak's snap, worked out here: the nearest local maximum of the
% condition's balanced mean within win ms, refined; t0 itself when none.
y = S.conditionMean(ck,"balanced");
t = S.Time(:);
c = find(islocalmax(y(:)) & isfinite(y(:)) & abs(t - t0) <= win + 1e-9);
lat = t0;
if isempty(c), return; end
[~,j] = min(abs(t(c) - t0));
lat = mabr.analysis.Peaks.refine(t,y(:),c(j));
end

function rc = boldCells(tbl)
% The [row column] cells styled bold.
rc = zeros(0,2);
try
    SC = tbl.StyleConfigurations;
    for r = 1:height(SC)
        st = SC.Style(r);
        if string(SC.Target(r)) == "cell" && string(st.FontWeight) == "bold"
            ix = SC.TargetIndex{r};
            rc = [rc; ix]; %#ok<AGROW>
        end
    end
catch me
    error('verify:style','Cannot read the matrix styles (%s).',me.message);
end
end

function rows = rowStyleRows(tbl)
rows = zeros(1,0);
SC = tbl.StyleConfigurations;
for r = 1:height(SC)
    if string(SC.Target(r)) == "row", rows = [rows reshape(SC.TargetIndex{r},1,[])]; end %#ok<AGROW>
end
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
d(startsWith(d,"WindowPos_")) = [];       % (WindowPos.restore's first read; not the view's)
end
