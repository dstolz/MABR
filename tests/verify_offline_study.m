function verify_offline_study()
% verify_offline_study  The analysis app's Study tab: labels, duplicates, thresholds, growth, waveforms.
%
%   Drives mabr.ui.analysis.StudyView inside an invisible
%   mabr.ui.AnalysisApp over mabrtest.OfflineFixture (two subjects at
%   Baseline and 2 weeks, plus a mixed tone/click session of SUBJ-ID-9001
%   on the Baseline day -- which is what makes a duplicated study unit), the
%   way a person does: controls by Tag, h.Value = v; h.ValueChangedFcn(h,[]),
%   table edits through their CellEditCallback, points through clickPoint.
%
%     Part A  thresholdUnits (pure): no-response and all-respond rules,
%             excluded series, the "mean" policy, the shift and its hollow
%             points, "First session" by start time; settingsOdd (whom the
%             settings banner names)
%     Part B  prefs: a script-driven view writes none; a control writes
%             OfflineAnalysisStudy
%     Part C  the Sessions and Subjects tables: columns, status, edits
%             through Model.label (the coercion note on the status line, a
%             refused number put back), the subject Comment through Edit
%             comment…, add/remove a column, selection, Export…, Copy table
%     Part D  duplicates: the banner, each DuplicatePolicy (the rule it
%             names), Choose…, undo
%     Part E  the threshold plot: one point per subject x timepoint x
%             series, log frequency axis, n in every legend entry, the
%             no-response triangles on the ceiling and each rule in the
%             subtitle, Show modes, the shift re a timepoint (hollow
%             censored points), one panel per subject (one legend for all),
%             timepoint axis (automatic for a family without a parameter;
%             a session with no timepoint plotted), colour groups,
%             manual and all-respond curation reaching the plot, timepoint
%             order, click readout, double-click opening the series
%     Part F  growth & latency: µV, % of the subject's reference timepoint,
%             dB re threshold, latency, interpeak
%     Part G  waveforms: the grand average is the mean of per-subject means,
%             with a band, n in the legend
%     Part L  the waveform grid: All levels stacks every level (loudest at
%             the top) in a column per series -- All series too: a
%             frequency x level grid; a click family is one column -- each
%             row's summary the mean of its subjects' curves, offset by the
%             row and scaled by the column's row spacing (per column,
%             global, fixed µV), one legend outside the last column, Copy
%             data in µV; colour by subject; one column per subject and
%             series; All series at one level is a panel per series
%     Part H  a session re-analysed with other settings: the settings
%             banner, its latencies re sound arrival (13 A9), [Re-analyse
%             them] clears it
%     Part I  blind review switches the tab off
%     Part K  the clean-sweeps banner (results edited in tempdir, Rescan)
%     Part J  no results: "0 of n sessions analysed — select them and press
%             Analyse."
%
%   No hardware, no parallel pool, no modal dialog; tempdir only; every
%   pref restored (mabrtest.prefGuard); no figure or MABR_Offline* timer
%   left behind.
%
%   See also mabr.ui.analysis.StudyView, mabr.analysis.Project.aggregate,
%   mabrtest.OfflineFixture, verify_offline_app
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_study ==\n');
tAll  = tic;
lap();
figs0 = findall(groot,'Type','figure');
guard = mabrtest.prefGuard(mabr.ui.AnalysisApp.prefKeys(),Clear=true); %#ok<NASGU>

partA_units();

F = mabrtest.OfflineFixture.make();
fprintf('  (fixture: %d sessions analysed in %.1f s)\n',numel(F.Keys),lap());
[app,stub] = newApp(F);
closer = mabrtest.OfflineFixture.closer(app,F); %#ok<NASGU> (the app, THEN the fixture's folders)
app.activateTab("Study");
v = app.Views.Study;
assert(isa(v,'mabr.ui.analysis.StudyView') && v.IsActive,'The Study tab did not build a StudyView.');
v.UseDialogs = false;
fprintf('  (window opened on the fixture and the Study tab built in %.1f s)\n',lap());

partB_prefs(app,v);
partC_tables(app,v,stub,F);
partM_sessionView(app,v,F);
partD_duplicates(app,v,stub);
partE_thresholds(app,v);
partF_growth(app,v);
partG_waveforms(app,v);
partL_waveGrid(app,v);
partH_settings(app,v,F);
partI_blind(app,v,F);
partK_sweeps(app,v);
partJ_empty(app,v);

clear closer
closeQuietly(app);
drawnow;
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_study left a figure open (%s).', ...
    strjoin(string(get(setdiff(figs1,figs0),'Name')),', '));
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_study PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Part A -- the threshold units, pure
% =========================================================================
function partA_units()
U = @mabr.ui.analysis.StudyView.thresholdUnits;
sk4 = "Stimulus=Tone|AcqMode=conventional|Frequency=4";
sk8 = "Stimulus=Tone|AcqMode=conventional|Frequency=8";
s = ["A","A","A","A","B","B","B","A"]';
tp = ["Base","Base","Late","Late","Base","Late","Late","Base"]';
ses = ["a1","a1","a2","a2","b1","b2","b2","a3"]';
key = [sk4,sk8,sk4,sk8,sk4,sk4,sk8,sk4]';
fin = [30 Inf 50 20 40 Inf 35 34]';
cen = ["none","right","none","left","none","right","none","none"]';
dec = ["","","manual","allrespond","","noresponse","excluded",""]';
T = table(ses,s,tp,[1 1 2 2 1 2 2 1]',repmat("",8,1),key,fin,cen,fin,fin,dec, ...
    zeros(8,1),repmat(80,8,1),repmat(10,8,1),'VariableNames',{'Session','Subject', ...
    'Timepoint','TimepointOrder','Group','Key','Final','FinalCensored','FinalLo','FinalHi', ...
    'Decision','MinLevel','MaxLevel','LevelStep'});
T.FinalLo(cen == "right") = 80;  T.FinalHi(cen == "right") = NaN;
T.FinalHi(cen == "left") = 20;
[P,info] = U(T,NoResponse="step",Params="Frequency");
% the excluded series is gone; A Base 4 kHz comes from two sessions (a1, a3): averaged
assert(height(P) == 6 && info.Excluded == 1,'thresholdUnits kept %d units (want 6), %d excluded.',height(P),info.Excluded);
r = P.Subject == "A" & P.Timepoint == "Base" & P.X == 4;
assert(nnz(r) == 1 && P.Value(r) == 32 && P.Sessions(r) == "a1|a3", ...
    'Two sessions of one unit are not averaged (%g, %s).',P.Value(r),P.Sessions(r));
nr = P.Kind == "noresponse";
assert(nnz(nr) == 2 && all(P.Value(nr) == 90) && isequal(info.Ceilings,90) && info.NoResponse == 2, ...
    'No response is not counted as max level + step (90).');
lf = P.Kind == "allrespond";
assert(nnz(lf) == 1 && P.Value(lf) == 20,'All respond is not plotted at its upper bound.');
assert(all(P.Series(P.X == 4) == "4 kHz") && all(P.Series(P.X == 8) == "8 kHz"),'Series names.');
[P5,i5] = U(T,NoResponse="5db",Params="Frequency");
assert(all(P5.Value(P5.Kind == "noresponse") == 85) && isequal(i5.Ceilings,85),'Max level + 5 dB.');
[Px,ix] = U(T,NoResponse="exclude",Params="Frequency");
assert(~any(Px.Kind == "noresponse") && height(Px) == 4 && ix.Dropped == 2,'Exclude keeps no-response units.');
% an attenuation axis: censoring describes the NUMBERS, so "left" (-Inf) is
% no response there -- a step below the smallest attenuation -- and "right"
% all respond, at the largest (SeriesView.censorMeaning's rule)
Ta = table(["c1";"c2"],["C";"C"],["Base";"Base"],[1;1],["";""],[sk4;sk8],[-Inf;80],["left";"right"], ...
    [NaN;80],[0;NaN],["";""],[0;0],[80;80],[10;10],["Attenuation";"Attenuation"],'VariableNames', ...
    {'Session','Subject','Timepoint','TimepointOrder','Group','Key','Final','FinalCensored','FinalLo', ...
    'FinalHi','Decision','MinLevel','MaxLevel','LevelStep','LevelParam'});
[Pa,ia] = U(Ta,Params="Frequency");
assert(Pa.Kind(Pa.X == 4) == "noresponse" && Pa.Value(Pa.X == 4) == -10 && ia.NoResponse == 1 && ...
    Pa.Kind(Pa.X == 8) == "allrespond" && Pa.Value(Pa.X == 8) == 80 && ia.AllRespond == 1, ...
    'An attenuation series: no response is not "left" a step below 0, or all respond not "right" at 80.');
[P5a,~] = U(Ta,NoResponse="5db",Params="Frequency");
assert(P5a.Value(P5a.X == 4) == -5,'An attenuation series: no response at the smallest attenuation − 5 dB.');
Tb = Ta;  Tb.LevelParam(:) = "Level";
[Pb,~] = U(Tb,Params="Frequency",Direction="descending");
assert(isequal(Pb.Kind,Pa.Kind) && isequal(Pb.Value,Pa.Value),'Direction "descending" is not read as an attenuation axis.');
[Pc,~] = U(Tb,Params="Frequency");
assert(Pc.Kind(Pc.X == 4) == "allrespond" && Pc.Value(Pc.X == 4) == 0 && ...
    Pc.Kind(Pc.X == 8) == "noresponse" && Pc.Value(Pc.X == 8) == 90,'The same rows on a dB SPL axis.');
Tb.LevelDirection = ["descending";"descending"];
[Pd,~] = U(Tb,Params="Frequency",Direction="ascending");
assert(isequal(Pd.Kind,Pa.Kind),'A LevelDirection column does not win over the settings''.');
% the shift re Base: A Late 4 kHz = 50 - 32; B Late 4 kHz = 90 - 40, hollow (censored)
[Ps,is] = U(T,NoResponse="step",Reference="tp:Base",Params="Frequency");
a = Ps.Subject == "A" & Ps.Timepoint == "Late" & Ps.X == 4;
b = Ps.Subject == "B" & Ps.Timepoint == "Late" & Ps.X == 4;
assert(is.Shift && Ps.Plotted(a) == 18 && ~Ps.Hollow(a),'The shift of an uncensored pair.');
assert(Ps.Plotted(b) == 50 && Ps.Hollow(b),'A shift involving a censored value is not hollow.');
assert(all(Ps.Plotted(Ps.Timepoint == "Base") == 0),'The reference units are not at 0.');
% B 8 kHz has no Base unit (its only one was excluded): left out and counted
assert(is.NoReference == 0 || ~any(Ps.Subject == "B" & Ps.X == 8),'A unit without a reference was kept.');
[Pf,~] = U(T,Reference="first",Params="Frequency");
assert(isequal(sortrows(Pf(:,{'Subject','X','Plotted'})),sortrows(Ps(:,{'Subject','X','Plotted'}))), ...
    'Reference "first" differs from the first timepoint named.');
% with no timepoint order, "First session" is the earliest session (a unit
% of several sessions starts with its earliest): here the Late ones
T2 = T;
T2.TimepointOrder(:) = NaN;
T2.StartTime = [100 100 50 50 100 50 50 200]';
[P2,~] = U(T2,Reference="first",Params="Frequency");
a = P2.Subject == "A" & P2.X == 4;
assert(P2.Plotted(a & P2.Timepoint == "Late") == 0 && P2.Plotted(a & P2.Timepoint == "Base") == 32 - 50, ...
    'Without a timepoint order, "First session" is not the earliest session.');
% the settings banner's reference: the project's settings whenever a used
% session has them (else [Re-analyse them] could never clear it), else
% the commonest
O = @mabr.ui.analysis.StudyView.settingsOdd;
assert(isequal(O(["h1";"h1";"h2";""],"h2"),[true;true;false;false]),'settingsOdd: the project''s hash in a minority.');
assert(isequal(O(["h1";"h1";"h2"],"h9"),[false;false;true]),'settingsOdd: the commonest hash without the project''s.');
assert(~any(O(["h1";"h1"],"h1")) && isempty(O(strings(0,1),"h1")),'settingsOdd: one hash names nobody.');
fprintf('  PASS Part A: thresholdUnits -- no response (step / +5 dB / exclude), all respond, an attenuation axis (left = no response), excluded, the mean of duplicates, the shift and its hollow points, "First session" by start time without a timepoint order; settingsOdd (%.1f s)\n',lap());
end

% =========================================================================
%  Part B -- prefs only from controls
% =========================================================================
function partB_prefs(app,v)
v.refresh("all",strings(0,1));
for s = ["Thresholds","Growth","Waveforms","Sessions"]
    v.showSub(s);
end
v.applySettings(struct('Show',"median"));
dd = control(app,'AnalysisStudyShow');
assert(string(v.ViewLook.Show) == "median" && string(dd.Value) == "median", ...
    'applySettings did not reach the look and its control.');
assert(~ispref('MABR','OfflineAnalysisStudy'),'A script-driven Study view wrote its look pref.');
drive(app,dd,'both');
assert(ispref('MABR','OfflineAnalysisStudy'),'The Show control did not remember the look.');
p = getpref('MABR','OfflineAnalysisStudy');
assert(string(p.Show) == "both" && all(isfield(p,{'Family','X','ColorBy','Show','Layout', ...
    'Reference','NoResponse','Measure','YMode','XMode','WaveAllSeries','WaveAllLevels', ...
    'WaveScale','WaveFixed'})),'The look pref lacks fields or the new Show.');
d = mabr.ui.analysis.StudyView.loadDefaults();
assert(string(d.Show) == "both",'loadDefaults does not read the pref back.');
fprintf('  PASS Part B: a script-driven Study view (refresh, sub-tabs, applySettings) writes no pref; a control writes OfflineAnalysisStudy with every look field (%.1f s)\n',lap());
end

% =========================================================================
%  Part C -- the Sessions and Subjects tables
% =========================================================================
function partC_tables(app,v,stub,F)
m = app.Model;
v.showSub("Sessions");
t = control(app,'AnalysisStudySessions');
u = control(app,'AnalysisStudySubjects');
cn = string(t.ColumnName);
need = ["In study","Subject","Session","Day","Timepoint","Group","Stimuli","Status","Reviewed", ...
    "Processing","Noise (µV)","% rejected","Min N","Units","Settings"];
assert(all(ismember(need,cn)),'The Sessions table lacks columns: %s',strjoin(need(~ismember(need,cn)),', '));
assert(size(t.Data,1) == numel(F.Keys),'The Sessions table has %d rows for %d sessions.',size(t.Data,1),numel(F.Keys));
col = @(name) find(string(t.ColumnName) == name,1);
st = string(t.Data(:,col("Status")));
assert(all(contains(st,"Up to date")),'A fixture session is not shown up to date: %s',strjoin(st,' | '));
assert(all(endsWith(string(t.Data(:,col("Reviewed"))),"/2") | endsWith(string(t.Data(:,col("Reviewed"))),"/5")), ...
    'The Reviewed column is not k/n.');
noise = str2double(string(t.Data(:,col("Noise (µV)"))));
assert(all(noise > 0 & noise < 100),'Noise (median RN, µV) is not plausible.');
assert(all(str2double(string(t.Data(:,col("Min N")))) >= 20),'Min N is not the fewest clean sweeps.');
ed = t.ColumnEditable;
assert(ed(col("In study")) && ed(col("Timepoint")) && ed(col("Group")) && ~ed(col("Status")) && ...
    ~ed(col("Subject")),'The wrong Sessions columns are editable.');
assert(all(ismember(["Subject","Group","In study","Comment"],string(u.ColumnName))),'Subjects table columns.');

% a timepoint differing only by case and spacing is the existing one; the note says so
k2 = "SUBJ-ID-9002/SUBJ-ID-9002_2weeks";
r = rowOf(t,v,k2);
editCell(t,r,col("Timepoint"),'  2WEEKS ');
assert(projectValue(m,k2,"Timepoint") == "2weeks",'The coerced timepoint is %s.',projectValue(m,k2,"Timepoint"));
assert(contains(statusText(app),'was taken as the existing "2weeks"'),'The coercion note is not on the status line: %s',statusText(app));
assert(string(t.Data{r,col("Timepoint")}) == "2weeks",'The table does not show the coerced value.');
% Group from a session row is the animal's
r1 = rowOf(t,v,"SUBJ-ID-9001/SUBJ-ID-9001_Baseline");
editCell(t,r1,col("Group"),'Noise');
gs = m.Project.Subjects;
assert(gs.Group(gs.Subject == "SUBJ-ID-9001") == "Noise",'Group set from a session did not reach the subject.');
rows01 = startsWith(v.tableKeys(),"SUBJ-ID-9001/");
assert(all(string(t.Data(rows01,col("Group"))) == "Noise"),'Every session of the subject does not show its group.');
% the Subjects table edits the animal; a group differing only in case becomes the existing one
ru = find(string(u.Data(:,1)) == "SUBJ-ID-9002",1);
ucol = @(name) find(string(u.ColumnName) == name,1);
editCell(u,ru,ucol("Group"),'noise ');
gs = m.Project.Subjects;
assert(gs.Group(gs.Subject == "SUBJ-ID-9002") == "Noise",'A Subjects-table group edit was not coerced.');
editCell(u,ru,ucol("Group"),'Control');
gs = m.Project.Subjects;
assert(gs.Group(gs.Subject == "SUBJ-ID-9002") == "Control",'A Subjects-table group edit was lost.');
% the Comment is not typed into a cell (no note is): the table's Edit
% comment… asks for it, and Ctrl+Z takes it back
ue = u.ColumnEditable;
assert(~ue(ucol("Comment")) && ue(ucol("Group")) && ue(ucol("In study")),'The Subjects table''s editable columns.');
c0 = gs.Comment(gs.Subject == "SUBJ-ID-9002");
u.CellSelectionCallback(u,struct('Indices',[ru ucol("Comment")]));
stub.Answers('prompt') = "ear bar slipped";
ec = findall(app.Figure,'Tag','AnalysisStudyEditComment');
assert(isscalar(ec),'The Subjects table has no Edit comment… item.');
app.setStatus("",0);
ec.MenuSelectedFcn(ec,[]);
assertNoError(app,'Edit comment…');
gs = m.Project.Subjects;
assert(gs.Comment(gs.Subject == "SUBJ-ID-9002") == "ear bar slipped" && ...
    string(u.Data{ru,ucol("Comment")}) == "ear bar slipped",'Edit comment… did not set the subject''s comment.');
m.undo();
gs = m.Project.Subjects;
assert(gs.Comment(gs.Subject == "SUBJ-ID-9002") == c0,'Undo did not take the comment back.');
% In study off and on again
km = "SUBJ-ID-9001/SUBJ-ID-9001_261001T140000";
rm = rowOf(t,v,km);
editCell(t,rm,col("In study"),false);
assert(~projectLogical(m,km,"InStudy"),'Unticking In study did not reach the project.');
T = v.Data.A.Thresholds;
assert(~any(T.UsedInStudy(T.Session == km)),'A session out of the study is still used by the study.');
editCell(t,rowOf(t,v,km),col("In study"),true);
assert(projectLogical(m,km,"InStudy"),'Ticking In study did not reach the project.');

% Add column…: name, then subject, then number
stub.Answers('prompt') = "Weight";
stub.Answers('queue') = ["Subject","Number"];
press(app,'AnalysisStudyAddColumn');
C = m.Project.Columns;
w = find(C.Name == "Weight",1);
assert(~isempty(w) && C.Level(w) == "subject" && C.Type(w) == "number",'Add column… did not make a subject number column.');
assert(any(string(t.ColumnName) == "Weight") && any(string(u.ColumnName) == "Weight"), ...
    'The new column is not in both tables.');
editCell(u,ru,ucol("Weight"),'31.5');
assert(m.Project.Subjects.Weight(m.Project.Subjects.Subject == "SUBJ-ID-9002") == 31.5,'A number edit was lost.');
app.setStatus("",0);
editCell(u,ru,ucol("Weight"),'heavy');
assert(contains(statusText(app),"Not changed"),'Text in a number column was not refused on the status line.');
assert(string(u.Data{ru,ucol("Weight")}) == "31.5",'A refused edit was not put back in the table.');
assert(m.Project.Subjects.Weight(m.Project.Subjects.Subject == "SUBJ-ID-9002") == 31.5,'A refused edit changed the project.');
% Remove column…: the selected column, and Ctrl+Z brings it back with its values
u.CellSelectionCallback(u,struct('Indices',[ru ucol("Weight")]));
press(app,'AnalysisStudyRemoveColumn');
assert(~any(m.Project.Columns.Name == "Weight") && ~any(string(t.ColumnName) == "Weight"), ...
    'Remove column… did not remove the selected column.');
m.undo();
assert(any(m.Project.Columns.Name == "Weight") && ...
    m.Project.Subjects.Weight(m.Project.Subjects.Subject == "SUBJ-ID-9002") == 31.5, ...
    'Undo did not bring the column back with its value.');
% ... and with no free column selected it asks which
t.CellSelectionCallback(t,struct('Indices',[1 col("Subject")]));
stub.Answers('queue') = "Weight";
press(app,'AnalysisStudyRemoveColumn');
asked = stub.Calls('confirm');
assert(~any(m.Project.Columns.Name == "Weight") && contains(asked(end),"Remove which column"), ...
    'Remove column… did not ask which column.');

% selection: the Analyse button names its count
t.CellSelectionCallback(t,struct('Indices',[1 1; 2 3]));
b = control(app,'AnalysisStudyAnalyseSelected');
assert(string(b.Text) == "Analyse 2 selected…" && string(b.Enable) == "on",'Analyse n selected: %s',b.Text);
tk = v.tableKeys();
assert(isequal(sort(v.SelectedKeys),sort(tk(1:2))),'The selected keys are not the rows.');
bs = control(app,'AnalysisStudyAnalyseStale');
assert(string(bs.Text) == "Analyse 0 out-of-date…" && string(bs.Enable) == "off",'Analyse n out-of-date: %s',bs.Text);
% Export… opens the export dialog on the sessions selected (else the study)
press(app,'AnalysisStudyExport');
ed = findall(groot,'Type','figure','Tag','MABR_OFFLINE_EXPORT');
assert(isscalar(ed),'Export… did not open the export dialog (%d).',numel(ed));
sc = findall(ed,'Tag','AnalysisExportScope');
assert(string(sc.Value) == "selected",'Export… with two rows selected opened on "%s".',string(sc.Value));
cx = findall(ed,'Tag','AnalysisExportCancel');
cx.ButtonPushedFcn(cx,[]);
assert(~any(isvalid(ed)) || string(ed.Visible) == "off",'The export dialog did not close on Cancel.');
% icons (13 A6) and Copy table
for tg = ["AnalysisStudyAnalyseSelected","AnalysisStudyAnalyseStale","AnalysisStudyReview","AnalysisStudyExport"]
    h = control(app,tg);
    assert(~isempty(h.Icon),'%s has no icon.',tg);
end
txt = v.copyTable("sessions");
L = splitlines(txt);
assert(startsWith(L(1),"In study" + char(9) + "Subject") && numel(L) == numel(F.Keys) + 1,'Copy table text.');
assert(numel(findall(app.Figure,'Tag','AnalysisStudyCopyTable')) == 2,'Not every table has Copy table.');
fprintf('  PASS Part C: Sessions/Subjects tables -- columns, status, review counts, noise, Min N; edits through Model.label (coercion note on the status line, Group set for the animal, In study), the subject Comment through Edit comment… (not typed into a cell; undo), Add/Remove column (selected or asked; undo), a refused number put back, selection counts, Export… on the selection, icons, Copy table (%.1f s)\n',lap());
end

% =========================================================================
%  Part M -- the Sessions table's Duration / N presented columns, filters, sort
% =========================================================================
function partM_sessionView(app,v,F)
m = app.Model;
v.showSub("Sessions");
t = control(app,'AnalysisStudySessions');
col = @(name) find(string(t.ColumnName) == name,1);
n = numel(F.Keys);
pick = @(tag,val) setDropdown(control(app,tag),val);
cells = @(name) string(t.Data(:,col(name)));

% the two columns: duration as h:mm:ss, the stimuli presented as the catalog's sweep count
assert(~isempty(col("Duration")) && ~isempty(col("N presented")),'The Sessions table lacks Duration / N presented.');
d = cells("Duration");
assert(all(d == "" | ~cellfun(@isempty,regexp(cellstr(d),'^\d+:\d\d:\d\d$','once'))),'Duration is not h:mm:ss: %s',strjoin(d,' | '));
tk = v.tableKeys();
S = m.Catalog.Sessions;
np = str2double(cells("N presented"));
for i = 1:numel(tk)
    r = find(S.Key == tk(i),1);
    if ~isempty(r), assert(np(i) == S.NumSweeps(r),'N presented of %s is %g, the catalog has %g.',tk(i),np(i),S.NumSweeps(r)); end
end
assert(all(np > 0),'A session shows no stimuli presented.');

% every filter offers All and exactly the values the sessions hold
subj = control(app,'AnalysisStudyFilterSubject');
us = unique(string(m.projectView().Subject));
assert(isequal(sort(string(subj.ItemsData(:))),sort(["";us(:)])),'The Subject filter does not offer the study''s subjects.');
dayItems = string(control(app,'AnalysisStudyFilterDay').ItemsData);
assert(numel(dayItems) == 1 + numel(unique(string(S.Day,'yyyy-MM-dd'))),'The Day filter offers %d choices.',numel(dayItems));
assert(~any(string(control(app,'AnalysisStudyFilterStatus').ItemsData) == "stale"),'Status offers a value no session has.');
assert(string(control(app,'AnalysisStudyFilterClear').Enable) == "off",'Clear filters is live with no filter set.');

% a filter shows the matching sessions only, and a row still edits ITS session
order0 = v.tableKeys();
target = us(end);
pick('AnalysisStudyFilterSubject',target);
tk = v.tableKeys();
assert(~isempty(tk) && all(startsWith(tk,target + "/")) && size(t.Data,1) == numel(tk) && numel(tk) < n, ...
    'The Subject filter did not narrow the table (%d of %d rows).',numel(tk),n);
assert(contains(string(control(app,'AnalysisStudyFilterCount').Text),"Showing " + numel(tk) + " of " + n),'The count label: %s',control(app,'AnalysisStudyFilterCount').Text);
assert(string(control(app,'AnalysisStudyFilterClear').Enable) == "on",'Clear filters is not live.');
k1 = tk(1);
was = projectLogical(m,k1,"InStudy");
editCell(t,rowOf(t,v,k1),col("In study"),~was);
assert(projectLogical(m,k1,"InStudy") == ~was,'An edit in a filtered table reached another session.');
editCell(t,rowOf(t,v,k1),col("In study"),was);
assert(projectLogical(m,k1,"InStudy") == was,'Restoring In study failed.');

% two filters narrow together (when some session is out of the study, In study = No offers itself)
if any(string(control(app,'AnalysisStudyFilterInStudy').ItemsData) == "no")
    pick('AnalysisStudyFilterInStudy','no');
    PV = m.projectView();
    assert(numel(v.tableKeys()) == nnz(PV.Subject == target & ~PV.InStudy),'Subject and In study filters did not narrow together.');
    pick('AnalysisStudyFilterInStudy','');
end
assert(numel(v.tableKeys()) == numel(tk),'Clearing one filter did not bring its rows back.');

% a selection survives a filter for the rows still showing, and only those
v.selectSessions(tk(1));
other = us(1);
pick('AnalysisStudyFilterSubject',other);
assert(isempty(v.SelectedKeys),'A selected session that is filtered out is still selected.');
pick('AnalysisStudyFilterSubject',target);
v.selectSessions(tk(1));
pick('AnalysisStudyFilterGroup','');
assert(isequal(v.SelectedKeys,tk(1)),'A selection did not survive a redraw of the same rows.');
c = control(app,'AnalysisStudyFilterClear');
c.ButtonPushedFcn(c,[]);
assert(isequal(v.tableKeys(),order0) && string(c.Enable) == "off",'Clear filters did not restore the table.');
assert(string(control(app,'AnalysisStudyFilterSubject').Value) == "",'Clear filters left a dropdown on a value.');

% sort: by a text column (natural order), then a numeric one; direction; ties keep table order
by1 = 'AnalysisStudySortBy1';  dir1 = 'AnalysisStudySortDir1';
pick(by1,'Subject');
sj = cells("Subject");
assert(isequal(sj,mabr.analysis.Stats.naturalSort(sj)),'Sort by Subject is not in natural order.');
pick(dir1,'descending');
sj2 = cells("Subject");
assert(isequal(sj2,flipud(mabr.analysis.Stats.naturalSort(sj2))),'Descending Subject is not descending.');
assert(isequal(sort(v.tableKeys()),sort(order0)),'Sorting changed which sessions show.');
pick(by1,'N presented');
np = str2double(cells("N presented"));
assert(issorted(-np),'Descending N presented is not descending: %s',strjoin(string(np),', '));
% a second key breaks ties of the first
pick('AnalysisStudySortBy2','Session');
assert(string(control(app,'AnalysisStudySortBy2').Enable) == "on",'Then by is not live under a first sort.');
% a sorted table still edits the right session
r = 2;  kk = v.tableKeys();  kk = kk(r);
was = projectLogical(m,kk,"InStudy");
editCell(t,r,col("In study"),~was);
assert(projectLogical(m,kk,"InStudy") == ~was,'An edit in a sorted table reached another session.');
editCell(t,rowOf(t,v,kk),col("In study"),was);
% the sort is the user's look: remembered in the study look (the pref guard puts the pref back)
L = v.displaySettings();
assert(string(L.SessSort1) == "N presented" && string(L.SessDir1) == "descending" && string(L.SessSort2) == "Session", ...
    'The sort choice is not in the look.');
% back to the table order for the parts that follow
pick('AnalysisStudySortBy2','');
pick(by1,'');
pick(dir1,'ascending');
assert(isequal(v.tableKeys(),order0),'The table order did not come back with the sort cleared.');
fprintf('  PASS Part M: Sessions table -- Duration and N presented, six filters (values from the data, narrowing together, Clear, an empty result), sort by one and two columns in both directions (natural text, numbers), edits and selection following the rows shown, the sort remembered in the look (%.1f s)\n',lap());
end

function setDropdown(h,val)
% A person choosing VAL (an ItemsData code) in a dropdown.
h.Value = char(val);
h.ValueChangedFcn(h,[]);
end

% =========================================================================
%  Part D -- duplicates
% =========================================================================
function partD_duplicates(app,v,stub)
m = app.Model;
v.showSub("Thresholds");
ban = control(app,'AnalysisStudyDuplicates');
txt = string(control(app,'AnalysisStudyDuplicatesText').Text);
assert(string(ban.Visible) == "on" && v.BannerKind == "duplicates",'The duplicates banner is not up (%s).',v.BannerKind);
assert(~isempty(regexp(txt,'^2 duplicated series \(SUBJ-ID-9001 · Baseline · Tone\): using (140000|Baseline) \([\d.]+ sweeps/condition\)\.$','once')), ...
    'Duplicates banner: %s',txt);
km = "SUBJ-ID-9001/SUBJ-ID-9001_261001T140000";
kb = "SUBJ-ID-9001/SUBJ-ID-9001_Baseline";
A = v.Data.A;
% what each rule must choose, worked out here from the results
sw = @(k) median(double(A.Conditions.nClean(A.Conditions.Session == k & ...
    startsWith(A.Conditions.Key,"Stimulus=Tone|AcqMode=conventional|Frequency="))));
st = @(k) A.Sessions.Start(A.Sessions.Session == k);
if sw(km) > sw(kb) || (sw(km) == sw(kb) && st(km) > st(kb)), most = km; else, most = kb; end
if st(km) > st(kb), latest = km; else, latest = kb; end
if most == km, nm = "140000"; else, nm = "Baseline"; end
assert(contains(txt,"using " + nm + " ("),'The banner names %s, not the session most sweeps chose.',txt);
dd = control(app,'AnalysisStudyDuplicatePolicy');
for pol = ["most-sweeps","latest","mean"]
    drive(app,dd,char(pol));
    assert(string(m.Project.DuplicatePolicy) == pol,'The Duplicates control did not set the project policy %s.',pol);
    P = v.thresholdTable();
    r = P.Subject == "SUBJ-ID-9001" & P.Timepoint == "Baseline";
    assert(nnz(r) == 2,'SUBJ-ID-9001 · Baseline has %d points (want one per series).',nnz(r));
    switch pol
        case "most-sweeps", assert(all(P.Sessions(r) == most),'Most sweeps used %s.',strjoin(P.Sessions(r),', '));
        case "latest",      assert(all(P.Sessions(r) == latest),'Latest used %s.',strjoin(P.Sessions(r),', '));
        otherwise
            assert(all(contains(P.Sessions(r),km) & contains(P.Sessions(r),kb)),'Mean did not use both sessions.');
            T = A.Thresholds;
            for q = find(r).'
                rr = T.Key == P.SeriesKey(q) & ismember(T.Session,[km kb]);
                f = T.Final(rr);
                c = ~isfinite(f);
                ceil_ = T.MaxLevel(rr) + T.LevelStep(rr);   % no response: max level + step
                f(c) = ceil_(c);
                assert(nnz(rr) == 2 && abs(P.Value(q) - mean(f)) < 1e-9,'Mean of sessions: %g, not %g.',P.Value(q),mean(f));
            end
            assert(contains(string(control(app,'AnalysisStudyDuplicatesText').Text),"the mean of 2 sessions"), ...
                'The banner does not say the mean is used.');
    end
end
m.undo();
assert(string(m.Project.DuplicatePolicy) == "latest" && string(dd.Value) == "latest", ...
    'Undo did not restore the previous policy (and the control).');
stub.Answers('queue') = "Most sweeps";
press(app,'AnalysisStudyDuplicatesAction');
assert(string(m.Project.DuplicatePolicy) == "most-sweeps",'Choose… did not set the policy.');
asked = stub.Calls('confirm');
assert(contains(asked(end),"SUBJ-ID-9001 · Baseline") && contains(asked(end),"Most sweeps"), ...
    'Choose… did not list the duplicates and explain the policies.');
fprintf('  PASS Part D: duplicates banner ("2 duplicated series … using 140000 (n sweeps/condition)"); most sweeps, latest and mean each use what their rule says; undo; Choose… (%.1f s)\n',lap());
end

% =========================================================================
%  Part E -- the threshold plot
% =========================================================================
function partE_thresholds(app,v)
m = app.Model;
v.showSub("Thresholds");
panel = v.Handles.ThrPanel;
fam = control(app,'AnalysisStudyFamily');
items = string(fam.Items);
assert(all(ismember(["Tone · conventional","Tone · interleaved","ClickTrain"],items)),'Family items: %s',strjoin(items,', '));
assert(string(fam.Value) == "Tone|conventional",'The family does not open on the commonest.');
P = v.thresholdTable();
u = unique(P.Subject + "|" + P.Timepoint + "|" + P.SeriesKey);
assert(height(P) == 8 && numel(u) == 8,'%d points / %d units (want 8: 2 subjects x 2 timepoints x 2 frequencies).',height(P),numel(u));
assert(all(ismember(P.Series,["4 kHz","16 kHz"])),'Series names: %s',strjoin(unique(P.Series),', '));
ax = axesOf(panel);
assert(isscalar(ax) && strcmp(ax.XScale,'log') && isequal(ax.XTick,[4 16]),'The frequency axis is not log with ticks at the frequencies.');
% the plot panels leave their axes where they are put: with the panel's
% auto-resize on, axes drawn before a sub-tab's first layout are squeezed
% into a corner once it is laid out (an invisible window never is, so the
% setting is what this test can see)
for tg = ["AnalysisStudyThresholdPanel","AnalysisStudyGrowthPanel","AnalysisStudyWavesPanel"]
    assert(strcmp(control(app,tg).AutoResizeChildren,'off'),'%s resizes its axes itself.',tg);
end
lg = legendStrings(panel);
assert(all(ismember(["Baseline (n = 2)","2weeks (n = 2)"],lg)),'Legend: %s',strjoin(lg,' | '));
% no response: triangles on the dashed ceiling, the rule in the subtitle
nr = P.Kind == "noresponse";
assert(nnz(nr) >= 1,'The fixture has no no-response series to draw.');
tri = findall(panel,'-regexp','Tag','^AnalysisStudyNoResponsePoints');
y = cell2mat(get(tri,{'YData'}).');
assert(~isempty(tri) && all(y == 100) && strcmp(tri(1).Marker,'^'),'No-response triangles are not at 100 (80 + 20).');
% drawn above the summary (Show "both" by default), whose filled circle
% would otherwise hide them; the legend is in a corner, not "best"
ch = allchild(ax);
iT = find(ismember(ch,tri),1);  iS = find(strcmp(get(ch,'Tag'),'AnalysisStudySummary'),1);
assert(~isempty(iS) && iT < iS,'The no-response triangles are drawn under the summary.');
assert(~isempty(ax.Legend) && ~strcmp(ax.Legend.Location,'best') && ...
    ismember(ax.Legend.Location,{'northeast','northwest','southeast','southwest'}), ...
    'The threshold legend is not placed in a corner.');
ce = findall(panel,'Tag','AnalysisStudyCeiling');
assert(isscalar(ce) && all(ce.YData == 100) && strcmp(ce.LineStyle,'--'),'No dashed ceiling at 100.');
assert(v.PlotNotes.Thresholds == "no response counted as 100 dB SPL (n = " + nnz(nr) + ")" && ...
    string(ax.Subtitle.String) == v.PlotNotes.Thresholds,'Subtitle: %s',v.PlotNotes.Thresholds);
nrd = control(app,'AnalysisStudyNoResponse');
drive(app,nrd,'5db');
tri = findall(panel,'-regexp','Tag','^AnalysisStudyNoResponsePoints');
assert(all(cell2mat(get(tri,{'YData'}).') == 85) && contains(v.PlotNotes.Thresholds,"counted as 85 dB SPL"), ...
    'Max level + 5 dB: %s',v.PlotNotes.Thresholds);
drive(app,nrd,'exclude');
P2 = v.thresholdTable();
assert(isempty(findall(panel,'-regexp','Tag','^AnalysisStudyNoResponsePoints')) && ~any(P2.Kind == "noresponse") && ...
    height(P2) == 8 - nnz(nr) && v.PlotNotes.Thresholds == "no response left out (n = " + nnz(nr) + ")", ...
    'Exclude: %s',v.PlotNotes.Thresholds);
drive(app,nrd,'step');
% Show: summaries across SUBJECTS
show = control(app,'AnalysisStudyShow');
drive(app,show,'mean');
P = v.thresholdTable();
eb = findall(panel,'Tag','AnalysisStudySummary');
assert(numel(eb) == 2 && isempty(findall(panel,'Tag','AnalysisStudyPoints')),'Mean ± SEM shows %d summaries / individuals.',numel(eb));
cs = findall(panel,'Tag','AnalysisStudySummaryCensored');
for e = reshape(eb,1,[])
    g = groupOf(e);
    for i = 1:numel(e.XData)
        rr = P.Color == g & P.XPlot == e.XData(i);
        vals = subjectMeans(P(rr,:));
        assert(abs(e.YData(i) - mean(vals)) < 1e-9,'Mean ± SEM of %s at %g is %g, not %g.',g,e.XData(i),e.YData(i),mean(vals));
        % a summary of censored values alone is marked as such (hollow,
        % its censoring symbol), one with a measured value is not
        allCen = all(P.Kind(rr & isfinite(P.Plotted)) ~= "value");
        hit = false;
        for h = reshape(cs,1,[])
            hit = hit || any(abs(h.XData - e.XData(i)) < 1e-9 & abs(h.YData - e.YData(i)) < 1e-9);
        end
        assert(hit == allCen,'The summary at %g (%s) is %smarked censored.',e.XData(i),g,string(repmat('not ',1,allCen)));
        if numel(vals) > 1
            assert(abs(e.YNegativeDelta(i) - std(vals)/sqrt(numel(vals))) < 1e-9,'The SEM is not across subjects.');
        end
    end
end
drive(app,show,'median');
eb = findall(panel,'Tag','AnalysisStudySummary');
e = eb(1);
vals = subjectMeans(P(P.Color == groupOf(e) & P.XPlot == e.XData(1),:));
assert(abs(e.YData(1) - median(vals)) < 1e-9,'Median (IQR) is not the median.');
drive(app,show,'individuals');
assert(isempty(findall(panel,'Tag','AnalysisStudySummary')) && ~isempty(findall(panel,'Tag','AnalysisStudyIndividuals')), ...
    'Individuals still draws a summary.');
drive(app,show,'both');
% Reference: the per-subject shift, censored pairs hollow
ref = control(app,'AnalysisStudyReference');
assert(isequal(string(ref.Items),["None","Baseline","2weeks","First session"]),'Reference items: %s',strjoin(string(ref.Items),', '));
drive(app,ref,'tp:Baseline');
Ps = v.thresholdTable();
P0 = P;
for i = 1:height(Ps)
    b = P0.Subject == Ps.Subject(i) & P0.SeriesKey == Ps.SeriesKey(i) & P0.Timepoint == "Baseline";
    s = P0.Subject == Ps.Subject(i) & P0.SeriesKey == Ps.SeriesKey(i) & P0.Timepoint == Ps.Timepoint(i);
    assert(abs(Ps.Plotted(i) - (P0.Value(s) - P0.Value(b))) < 1e-9,'A shift is not value - baseline.');
    assert(Ps.Hollow(i) == (P0.Censored(s) || P0.Censored(b)),'Hollow is not "involves a censored value".');
end
assert(any(Ps.Hollow) && ~isempty(findall(panel,'-regexp','Tag','Hollow$')),'No hollow (censored) shift points are drawn.');
hol = findall(panel,'-regexp','Tag','Hollow$');
assert(all(strcmp(get(hol,'MarkerFaceColor'),'none')),'Hollow points are filled.');
ax = axesOf(panel);
assert(contains(string(ax.YLabel.String),"shift re Baseline"),'Shift y label: %s',string(ax.YLabel.String));
assert(isempty(findall(panel,'Tag','AnalysisStudyCeiling')),'A shift plot draws the ceiling.');
drive(app,ref,'none');
% one panel per subject
lay = control(app,'AnalysisStudyLayout');
drive(app,lay,'subject');
ax = axesOf(panel);
tt = sort(titlesOf(ax));
assert(numel(ax) == 2 && isequal(tt,["SUBJ-ID-9001";"SUBJ-ID-9002"]),'Per subject: %d panels.',numel(ax));
% the rule is said once, and the other panel's title stays level with it
% (as many blank subtitle lines)
a1 = ax(titlesOf(ax) == "SUBJ-ID-9001");  a2 = ax(titlesOf(ax) == "SUBJ-ID-9002");
s1 = string(a1.Subtitle.String);  s2 = string(a2.Subtitle.String);
assert(strjoin(s1,"; ") == v.PlotNotes.Thresholds && numel(s2) == numel(s1) && all(strtrim(s2) == ""), ...
    'Per-subject subtitles: "%s" / "%s".',strjoin(s1,' | '),strjoin(s2,' | '));
% ONE legend, naming every colour drawn in any panel -- also one only the
% second subject has (SUBJ-ID-9001's 2 weeks out of the study)
m.label("SUBJ-ID-9001/SUBJ-ID-9001_2weeks","InStudy",false);
ax = axesOf(panel);
nl = arrayfun(@(a) ~isempty(a.Legend) && isvalid(a.Legend),ax);
P1 = v.thresholdTable();
assert(~any(P1.Subject == "SUBJ-ID-9001" & P1.Timepoint == "2weeks"),'An out-of-study session is still plotted.');
assert(nnz(nl) == 1 && nl(titlesOf(ax) == "SUBJ-ID-9001") && ...
    isequal(sort(legendStrings(panel)),["2weeks","Baseline"]), ...
    'Per-subject legend: %s (%d legends).',strjoin(legendStrings(panel),' | '),nnz(nl));
m.undo();
drive(app,lay,'overlay');
% thresholds across timepoints: a panel per frequency, the visits in order
xd = control(app,'AnalysisStudyX');
drive(app,xd,'Timepoint');
ax = axesOf(panel);
assert(numel(ax) == 2 && isequal(sort(titlesOf(ax)),["16 kHz";"4 kHz"]), ...
    'X = Timepoint does not tile the frequencies.');
assert(isequal(string(ax(1).XTickLabel(:)).',["Baseline","2weeks"]),'Timepoint ticks: %s',strjoin(string(ax(1).XTickLabel),', '));
% a session with no timepoint yet is still plotted -- after the ordered
% ones, as "(no timepoint)", on the axis and in the legend
m.label("SUBJ-ID-9002/SUBJ-ID-9002_2weeks","Timepoint","");
P9 = v.thresholdTable();
ax = axesOf(panel);
assert(height(P9) == 8 && all(isfinite(P9.XPlot)) && ...
    isequal(string(ax(1).XTickLabel(:)).',["Baseline","2weeks","(no timepoint)"]) && ...
    any(legendStrings(panel) == "(no timepoint) (n = 1)"), ...
    'A session without a timepoint is not plotted as "(no timepoint)": %s / %s', ...
    strjoin(string(ax(1).XTickLabel),', '),strjoin(legendStrings(panel),' | '));
m.undo();
% the timepoint order decides that axis (and the Reference list): set in
% the Timepoint order… dialog, as a person does, and undone
press(app,'AnalysisStudyTimepoints');
dl = findall(groot,'Type','figure','Tag','MABR_OFFLINE_LEVELS');
assert(isscalar(dl),'Timepoint order… did not open the order dialog (%d).',numel(dl));
lb = findall(dl,'Tag','AnalysisLevelsList');
items = string(lb.Items);
assert(all(ismember(["Baseline","2weeks"],items)),'The order dialog lists %s.',strjoin(items,', '));
lb.Value = '2weeks';
lb.ValueChangedFcn(lb,[]);
up = findall(dl,'Tag','AnalysisLevelsUp');
for q = 1:find(items == "2weeks") - 1
    up.ButtonPushedFcn(up,[]);
end
okb = findall(dl,'Tag','AnalysisLevelsOK');
okb.ButtonPushedFcn(okb,[]);
assert(~isvalid(dl) || string(dl.Visible) == "off",'The order dialog did not close on OK.');
ax = axesOf(panel);
assert(isequal(string(ax(1).XTickLabel(:)).',["2weeks","Baseline"]) && ...
    isequal(string(control(app,'AnalysisStudyReference').Items),["None","2weeks","Baseline","First session"]), ...
    'The timepoint order does not reach the plot.');
m.undo();
ax = axesOf(panel);
assert(isequal(string(ax(1).XTickLabel(:)).',["Baseline","2weeks"]),'Undo did not put the timepoint order back.');
drive(app,xd,'Frequency');
% colour by group (Part C made SUBJ-ID-9001 Noise and SUBJ-ID-9002 Control)
cb = control(app,'AnalysisStudyColorBy');
drive(app,cb,'group');
lg = legendStrings(panel);
assert(all(ismember(["Control (n = 1)","Noise (n = 1)"],lg)),'Colour by group: %s',strjoin(lg,' | '));
drive(app,cb,'group-timepoint');
assert(numel(legendStrings(panel)) == 4,'Group × Timepoint does not make four groups.');
drive(app,cb,'timepoint');
% a family without a group parameter: across timepoints, automatically
drive(app,fam,'ClickTrain');
xd = control(app,'AnalysisStudyX');
Pc = v.thresholdTable();
assert(string(xd.Value) == "Timepoint" && string(xd.Enable) == "off" && height(Pc) == 1 && isnan(Pc.X), ...
    'ClickTrain (no parameter) is not plotted against Timepoint.');
ax = axesOf(panel);
assert(isequal(string(ax.XTickLabel(:)).',"Baseline"),'ClickTrain timepoint tick.');
drive(app,fam,'Tone|conventional');
% curation reaches the plot: a manual threshold and "all respond"
kw = "SUBJ-ID-9001/SUBJ-ID-9001_2weeks";
k4 = "Stimulus=Tone|AcqMode=conventional|Frequency=4";
k16 = "Stimulus=Tone|AcqMode=conventional|Frequency=16";
m.openSession(kw);
m.setThresholdValue(40,k4);
m.openSession("SUBJ-ID-9002/SUBJ-ID-9002_Baseline");
m.setAllRespond(k16);
m.flush();
v.flush();
P = v.thresholdTable();
r = find(P.Session == kw & P.SeriesKey == k4,1);
assert(~isempty(r) && P.Value(r) == 40 && P.Decision(r) == "manual",'A manual threshold did not reach the study.');
txt = v.clickPoint(r);
assert(txt == "SUBJ-ID-9001 · 2weeks · 4 kHz · 40 dB, manual, reviewed",'Readout: %s',txt);
assert(string(control(app,'AnalysisStudyReadout').Text) == txt && ...
    isscalar(findall(panel,'Tag','AnalysisStudySelected')),'The readout or the highlight is not shown.');
ar = P.Kind == "allrespond";
assert(nnz(ar) == 1 && ~isempty(findall(panel,'Tag','AnalysisStudyAllRespondPoints')) && ...
    contains(v.PlotNotes.Thresholds,"all levels responding plotted at the quietest level (n = 1)"), ...
    'All respond is not a ▼ with its rule: %s',v.PlotNotes.Thresholds);
assert(contains(v.clickPoint(find(ar)),"all respond, reviewed"),'All-respond readout.');
% a click on the axes finds the nearest point (what ButtonDownFcn does with
% CurrentPoint, which a script cannot set); a click far from every point
% reads nothing
ax = axesOf(panel);
k = find(P.Subject == "SUBJ-ID-9002" & P.Kind == "value",1);
j = find(P.XPlot == P.XPlot(k) & P.Plotted == P.Plotted(k),1);
want = v.clickPoint(j);
v.clickPoint(r);
txt = v.clickAt(P.XPlot(k)*1.01,P.Plotted(k) + 0.2);
assert(txt == want && v.Readout == want && startsWith(txt,P.Subject(j) + " · " + P.Timepoint(j) + " · " + P.Series(j)), ...
    'A click on the axes did not read out the nearest point: %s',txt);
assert(v.clickAt(P.XPlot(k),max(P.Plotted) + 500) == "" && v.Readout == want,'A click far from every point read one out.');
assert(contains(func2str(ax.ButtonDownFcn),'runCallback'),'The axes'' click is not wrapped by the window''s cb.');
% double-click: the session, on that series, in the Series tab
v.clickPoint(k,Open=true);
assert(m.SessionKey == P.Session(k) && m.Selection.SeriesKey == P.SeriesKey(k) && app.ActiveTab == "Series", ...
    'A double-click did not open %s on %s in the Series tab.',P.Session(k),P.SeriesKey(k));
app.activateTab("Study");
assert(numel(findall(app.Figure,'Tag','AnalysisStudyPlotMenu')) <= 3 && ...
    ~isempty(findall(ax.ContextMenu,'Tag','AnalysisMenuCopyDataItem')),'Plot menus leak or lack Copy data.');
fprintf('  PASS Part E: thresholds -- one point per subject x timepoint x series, log frequency axis, n in the legend, ▲ on the dashed ceiling with the rule in the subtitle (step, +5 dB, exclude), Show (mean ± SEM across subjects, median, individuals), the shift re Baseline (hollow censored pairs), per-subject panels (one legend naming every colour, level titles), timepoint axis ("(no timepoint)" plotted) and its order (Timepoint order… dialog, undo), colour by group, ClickTrain across timepoints, a manual and an all-respond curation, readout, a click on the axes, double-click opens the series (%.1f s)\n',lap());
end

% =========================================================================
%  Part F -- growth and latency
% =========================================================================
function partF_growth(app,v)
v.showSub("Growth");
panel = v.Handles.GrowthPanel;
at = control(app,'AnalysisStudyAt');
assert(isequal(string(at.Items),["4 kHz","16 kHz"]),'At items: %s',strjoin(string(at.Items),', '));
drive(app,at,'4 kHz');
G = v.growthTable();
A = v.Data.A;
Pk = A.Peaks;
assert(height(G) > 0,'No growth points at 4 kHz.');
for i = 1:height(G)
    r = Pk.Session == G.Session(i) & Pk.SeriesKey == G.SeriesKey(i) & Pk.Level == G.Level(i) & Pk.Wave == "I";
    assert(nnz(r) == 1 && abs(G.Y(i) - 1e6*Pk.AmpPT(r)) < 1e-9 && ~Pk.BelowThreshold(r), ...
        'Growth point %d is not the wave I P–N amplitude in µV above threshold.',i);
end
ax = axesOf(panel);
% the level axis in the sessions' own unit, as the thresholds plot names it
lu = string(v.Data.A.Sessions.LevelUnit);
lu = lu(lu ~= "" & ~ismissing(lu) & lu ~= "mixed");
wantX = "Level (dB)";
if ~isempty(lu)
    [uu,~,jj] = unique(lu);
    [~,kk] = max(accumarray(jj,1));
    wantX = "Level (" + uu(kk) + ")";
end
assert(contains(string(ax.YLabel.String),"(µV)") && string(ax.XLabel.String) == wantX, ...
    'Growth labels: %s / %s (want %s).',string(ax.YLabel.String),string(ax.XLabel.String),wantX);
assert(all(contains(legendStrings(panel),"(n = ")),'The growth legend lacks n.');
% % of the subject's reference timepoint (the first, with no Reference chosen)
ym = control(app,'AnalysisStudyYMode');
drive(app,ym,'percent');
Gp = v.growthTable();
assert(height(Gp) > 0 && all(abs(Gp.Y(Gp.Timepoint == "Baseline") - 100) < 1e-9),'Reference rows are not 100%.');
for i = find(Gp.Timepoint ~= "Baseline").'
    b = G.Subject == Gp.Subject(i) & G.SeriesKey == Gp.SeriesKey(i) & G.Level == Gp.Level(i) & G.Timepoint == "Baseline";
    s = G.Subject == Gp.Subject(i) & G.SeriesKey == Gp.SeriesKey(i) & G.Level == Gp.Level(i) & G.Timepoint == Gp.Timepoint(i);
    assert(abs(Gp.Y(i) - 100*G.Y(s)/G.Y(b)) < 1e-9,'% of reference is not value/reference.');
end
assert(any(Gp.Timepoint ~= "Baseline"),'No subject has a growth point at two timepoints (the manual threshold of Part E should).');
assert(contains(string(axesOf(panel).YLabel.String),"% of reference"),'Percent y label.');
drive(app,ym,'uv');
% dB re threshold
xm = control(app,'AnalysisStudyXMode');
drive(app,xm,'re-threshold');
Gx = v.growthTable();
T = A.Thresholds;
for i = 1:height(Gx)
    f = T.Final(T.Session == Gx.Session(i) & T.Key == Gx.SeriesKey(i));
    assert(abs(Gx.X(i) - (Gx.Level(i) - f)) < 1e-9,'dB re threshold is not level - Final.');
end
assert(string(axesOf(panel).XLabel.String) == "Level re threshold (dB)",'re-threshold x label.');
% the summary groups levels re threshold into bins (each subject's fall
% elsewhere) but is drawn where its subjects are: at the mean, across
% subjects, of each subject's mean position in the bin
sm = findall(panel,'Tag','AnalysisStudyGrowthSummary');
assert(~isempty(sm),'No growth summary is drawn re threshold.');
for e = reshape(sm,1,[])
    rr = Gx.Color == groupOf(e);
    ub = unique(Gx.XBin(rr));
    want = zeros(numel(ub),1);
    for q = 1:numel(ub)
        rb = rr & Gx.XBin == ub(q);
        s = unique(Gx.Subject(rb));
        want(q) = mean(arrayfun(@(k) mean(Gx.X(rb & Gx.Subject == s(k))),1:numel(s)));
    end
    assert(numel(e.XData) == numel(want) && max(abs(sort(e.XData(:)) - sort(want))) < 1e-9, ...
        'The %s summary re threshold is not drawn where its subjects are.',groupOf(e));
end
drive(app,xm,'db');
% latency (raw - offset; no offset here) and the interpeak interval
me = control(app,'AnalysisStudyMeasure');
drive(app,me,'latency');
Gl = v.growthTable();
for i = 1:height(Gl)
    r = Pk.Session == Gl.Session(i) & Pk.SeriesKey == Gl.SeriesKey(i) & Pk.Level == Gl.Level(i) & Pk.Wave == "I";
    assert(abs(Gl.Y(i) - (Pk.PeakLatency(r) - Pk.LatencyOffset(r))) < 1e-9,'Latency is not the reported one.');
end
assert(string(axesOf(panel).YLabel.String) == "Wave I latency (ms)",'Latency label: %s',string(axesOf(panel).YLabel.String));
drive(app,me,'ipl-I-V');
assert(string(control(app,'AnalysisStudyWave').Enable) == "off",'The Wave control is live for an interpeak interval.');
Gi = v.growthTable();
for i = 1:height(Gi)
    r = Pk.Session == Gi.Session(i) & Pk.SeriesKey == Gi.SeriesKey(i) & Pk.Level == Gi.Level(i);
    d = Pk.PeakLatency(r & Pk.Wave == "V") - Pk.PeakLatency(r & Pk.Wave == "I");
    assert(abs(Gi.Y(i) - d) < 1e-9,'Interpeak I–V is not lat V - lat I.');
end
drive(app,me,'amp-pt');
fprintf('  PASS Part F: growth & latency -- wave I P–N amplitude in µV (above threshold), %% of the subject''s reference timepoint, dB re threshold (the summary drawn where its subjects are), latency (reported), interpeak I–V; n in the legend (%.1f s)\n',lap());
end

% =========================================================================
%  Part G -- waveforms
% =========================================================================
function partG_waveforms(app,v)
v.showSub("Waveforms");
panel = v.Handles.WavesPanel;
lev = control(app,'AnalysisStudyWaveLevel');
assert(string(lev.Value) == "80",'The waveform level does not open on the loudest.');
W = v.waveTable();
assert(height(W) == 4 && numel(unique(W.Subject + W.Color)) == 4,'One curve per subject and colour group (got %d).',height(W));
gm = findall(panel,'Tag','AnalysisStudyGrandMean');
assert(numel(gm) == 2,'%d grand means (want one per timepoint).',numel(gm));
for g = reshape(gm,1,[])
    rows = W.Color == groupOf(g);
    Y = 1e6*cell2mat(reshape(W.Y(rows),1,[]));
    assert(max(abs(g.YData(:) - mean(Y,2))) < 1e-9,'The grand mean is not the mean of the subjects'' curves.');
end
bands = findall(panel,'Tag','AnalysisStudyBand');
assert(numel(bands) == 2,'%d SEM bands (want one per group).',numel(bands));
for b = reshape(bands,1,[])
    rows = W.Color == groupOf(b);
    Y = 1e6*cell2mat(reshape(W.Y(rows),1,[]));
    mu = mean(Y,2);
    se = std(Y,0,2)/sqrt(size(Y,2));
    want = [mu - se; flipud(mu + se)];
    assert(numel(b.YData) == numel(want) && max(abs(b.YData(:) - want)) < 1e-9, ...
        'The %s band is not the mean ± SEM across subjects.',groupOf(b));
end
assert(all(contains(legendStrings(panel),"(n = 2)")),'Waveform legend: %s',strjoin(legendStrings(panel),' | '));
ax = axesOf(panel);
assert(string(ax.XLabel.String) == "Time re onset (ms)" && string(ax.YLabel.String) == "Amplitude (µV)",'Waveform labels.');
drive(app,lev,'60');
assert(string(lev.Value) == "60" && height(v.waveTable()) > 0,'The level control does not choose the level.');
fprintf('  PASS Part G: waveforms -- the grand average is the mean of per-subject means, an SEM band per group, n in the legend, the level control (%.1f s)\n',lap());
end

% =========================================================================
%  Part L -- the waveform grid
% =========================================================================
function partL_waveGrid(app,v)
v.showSub("Waveforms");
panel = v.Handles.WavesPanel;
ser = control(app,'AnalysisStudyWaveSeries');
lev = control(app,'AnalysisStudyWaveLevel');
sc  = control(app,'AnalysisStudyWaveScale');
fx  = control(app,'AnalysisStudyWaveFixed');
ALL = char(mabr.ui.analysis.StudyView.WaveAllCode);
assert(isequal(string(ser.Items),["All series","4 kHz","16 kHz"]) && string(lev.Items{1}) == "All levels", ...
    'Series / Level do not offer All: %s / %s',strjoin(string(ser.Items),', '),strjoin(string(lev.Items),', '));
assert(string(sc.Enable) == "off" && string(fx.Enable) == "off" && isempty(fieldnames(v.WaveGrid)), ...
    'The row scale is live for a single condition.');

% All levels: one column, the five levels stacked, loudest at the top
drive(app,ser,'4 kHz');
drive(app,lev,ALL);
G = v.WaveGrid;
ax = axesOf(panel);
assert(isscalar(ax) && isequal(G.Columns,"4 kHz") && isequal(G.Levels(:).',0:20:80) && ...
    isequal(ax.YTick,0:4) && isequal(string(ax.YTickLabel(:)).',["0","20","40","60","80"]), ...
    'All levels: %d column(s), levels %s.',numel(ax),mat2str(G.Levels(:).'));
assert(string(ax.Title.String) == "4 kHz" && string(ax.YLabel.String) == "Level (dB SPL)", ...
    'Grid labels: "%s" / "%s".',string(ax.Title.String),string(ax.YLabel.String));
assert(string(sc.Enable) == "on" && string(fx.Enable) == "off",'The row scale is not live for the grid.');
p = getpref('MABR','OfflineAnalysisStudy');
assert(p.WaveAllLevels && ~p.WaveAllSeries,'All levels was not remembered.');
checkGridMeans(v,panel);
W = v.waveTable();
Y = 1e6*cell2mat(reshape(W.Y,1,[]));
assert(abs(G.RowScale - max(abs(Y(:)))) < 1e-9,'Per column, rows are not the largest curve apart.');
assert(~isempty(ax.Legend) && strcmp(ax.Legend.Location,'northeastoutside') && ...
    isequal(sort(string(ax.Legend.String)),sort(["Baseline (n = 2)","2weeks (n = 2)"])), ...
    'Grid legend: %s',strjoin(string(ax.Legend.String),' | '));
% Copy data copies the curves in µV, not their places in the stack
txt = mabr.ui.analysis.FigureExport.copyData(panel);
hdr = split(extractBefore(string(txt) + newline,newline),char(9));
assert(all(contains(hdr,"(µV)")) && any(hdr == "4 kHz · 80 dB · Baseline · mean (µV) y"), ...
    'Copy data of the grid: %s',strjoin(hdr(1:min(4,end)),' | '));

% All series too: a frequency x level grid, one legend outside the last column
drive(app,ser,ALL);
G = v.WaveGrid;
ax = byPosition(axesOf(panel));
assert(numel(ax) == 2 && isequal(G.Columns(:).',["4 kHz","16 kHz"]) && ...
    isequal(titlesOf(ax).',["4 kHz","16 kHz"]),'All series: columns %s.',strjoin(G.Columns,', '));
assert(~isempty(ax(1).YTickLabel) && isempty(ax(2).YTickLabel) && isequal(ax(1).YLim,ax(2).YLim), ...
    'Only the first column names the levels, and every column shares the rows.');
nl = arrayfun(@(a) ~isempty(a.Legend) && isvalid(a.Legend),ax);
assert(isequal(nl(:).',[false true]) && abs(ax(1).Position(3) - ax(2).Position(3)) < 1e-9, ...
    'The legend is not outside the last column alone, or it narrowed that column.');
p = getpref('MABR','OfflineAnalysisStudy');
assert(p.WaveAllSeries && p.WaveAllLevels,'All series was not remembered.');
checkGridMeans(v,panel);
W = v.waveTable();
for c = 1:2
    Y = 1e6*cell2mat(reshape(W.Y(W.Tile == G.Columns(c)),1,[]));
    assert(abs(G.RowScale(c) - max(abs(Y(:)))) < 1e-9,'Column %s is not scaled to its largest curve.',G.Columns(c));
end
assert(numel(findall(panel,'Tag','AnalysisStudyWaveGridScale')) == 2,'Per column, each column does not say its row spacing.');
% Global, then a fixed number of microvolts
drive(app,sc,'global');
G2 = v.WaveGrid;
assert(all(G2.RowScale == max(G.RowScale)) && isscalar(findall(panel,'Tag','AnalysisStudyWaveGridScale')), ...
    'Global: rows %s µV apart.',mat2str(G2.RowScale(:).'));
drive(app,sc,'fixed');
assert(string(fx.Enable) == "on",'Fixed µV does not open the µV field.');
drive(app,fx,2);
st = findall(panel,'Tag','AnalysisStudyWaveGridScale');
assert(all(v.WaveGrid.RowScale == 2) && isscalar(st) && contains(string(st.String),"2 µV"), ...
    'Fixed 2 µV: rows %s apart (%s).',mat2str(v.WaveGrid.RowScale(:).'),strjoin(string(get(st,'String')),' | '));
checkGridMeans(v,panel);
drive(app,sc,'column');
% colour by subject: one curve per subject in every row, named in the legend
cb = control(app,'AnalysisStudyColorBy');
drive(app,cb,'subject');
W = v.waveTable();
assert(numel(unique(W.Subject + "|" + W.Series + "|" + string(W.Level))) == height(W) && all(W.Color == W.Subject), ...
    'Colour by subject does not make one curve per subject in each slot.');
assert(isequal(sort(legendStrings(panel)),["SUBJ-ID-9001 (n = 1)","SUBJ-ID-9002 (n = 1)"]), ...
    'Colour by subject: %s',strjoin(legendStrings(panel),' | '));
checkGridMeans(v,panel);
drive(app,cb,'timepoint');
% one panel per subject: a column per subject and series, no summaries
lay = control(app,'AnalysisStudyLayout');
drive(app,lay,'subject');
G = v.WaveGrid;
ax = byPosition(axesOf(panel));
assert(isequal(G.Columns(:).',["SUBJ-ID-9001 · 4 kHz","SUBJ-ID-9001 · 16 kHz","SUBJ-ID-9002 · 4 kHz", ...
    "SUBJ-ID-9002 · 16 kHz"]) && numel(ax) == 4 && isequal(string(ax(1).Title.String(:)).',["SUBJ-ID-9001","4 kHz"]), ...
    'Per subject: columns %s.',strjoin(G.Columns,', '));
assert(isempty(findall(panel,'Tag','AnalysisStudyWaveGridMean')) && ...
    ~isempty(findall(panel,'Tag','AnalysisStudyWaveGridIndividuals')) && ...
    isequal(sort(legendStrings(panel)),sort(["Baseline","2weeks"])), ...
    'Per subject: summaries drawn, or the legend is %s.',strjoin(legendStrings(panel),' | '));
drive(app,lay,'overlay');

% All series at one level: a panel per series, in µV, one legend
drive(app,lev,'80');
ax = byPosition(axesOf(panel));
assert(isempty(fieldnames(v.WaveGrid)) && numel(ax) == 2 && isequal(titlesOf(ax).',["4 kHz","16 kHz"]) && ...
    string(ax(1).YLabel.String) == "Amplitude (µV)" && string(sc.Enable) == "off", ...
    'All series at 80 dB is not a panel per series.');
assert(numel(findall(panel,'Tag','AnalysisStudyGrandMean')) == 4,'A panel per series does not draw each timepoint''s grand mean.');
lg = legendStrings(panel);
assert(numel(lg) == 2 && all(contains(lg,"(n = 2)")),'A panel per series: legend %s.',strjoin(lg,' | '));

% a family of one series (clicks) has no All series: every level is one column
fam = control(app,'AnalysisStudyFamily');
drive(app,fam,'ClickTrain');
assert(isequal(string(ser.Items),"ClickTrain"),'Click series: %s',strjoin(string(ser.Items),', '));
drive(app,lev,ALL);
G = v.WaveGrid;
assert(isequal(G.Columns,"ClickTrain") && numel(G.Levels) > 1 && isscalar(axesOf(panel)), ...
    'Every click level is not one column (%d levels).',numel(G.Levels));
checkGridMeans(v,panel);
drive(app,fam,'Tone|conventional');

% back to one condition, as Part G left it
drive(app,ser,'4 kHz');
drive(app,lev,'80');
p = getpref('MABR','OfflineAnalysisStudy');
assert(isempty(fieldnames(v.WaveGrid)) && numel(findall(panel,'Tag','AnalysisStudyGrandMean')) == 2 && ...
    ~p.WaveAllSeries && ~p.WaveAllLevels,'One series at one level is not the single plot again.');
fprintf('  PASS Part L: the waveform grid -- All levels stacks every level in a column per series (All series: frequency x level), each row''s mean that of its subjects'' curves, offset by its row at the column''s spacing (per column, global, fixed µV), one legend outside the last column, Copy data in µV; colour by subject; a column per subject and series; All series at one level is a panel per series; clicks are one column (%.1f s)\n',lap());
end

function checkGridMeans(v,panel)
% Every row's summary in the waveform grid is the mean of that row's
% subjects' curves -- in µV on its Copy-data line, and drawn offset by its
% row at its column's row spacing.
G = v.WaveGrid;
W = v.waveTable();
data = findall(panel,'Tag','AnalysisStudyWaveGridData');
dn = string(get(data,{'DisplayName'}));
mn = findall(panel,'Tag','AnalysisStudyWaveGridMean');
assert(~isempty(mn),'The grid draws no summaries.');
for h = reshape(mn,1,[])
    a = ancestor(h,'axes');
    c = find(G.Columns == string(a.UserData.Tile),1);
    g = string(h.DisplayName);
    yd = h.YData(:);
    br = [0; find(isnan(yd))];      % the row segments, in row order
    s = 0;
    for k = 1:numel(G.Levels)
        rows = W.Tile == G.Columns(c) & W.Color == g & W.Level == G.Levels(k);
        if ~any(rows), continue; end
        s = s + 1;
        want = mean(1e6*cell2mat(reshape(W.Y(rows),1,[])),2);
        nm = G.Columns(c) + " · " + compose("%g",G.Levels(k)) + " dB · " + g + " · mean (µV)";
        hc = data(dn == nm);
        assert(isscalar(hc) && max(abs(hc.YData(:) - want)) < 1e-9, ...
            'The Copy-data mean of %s is not the mean of its subjects'' curves.',nm);
        seg = yd(br(s)+1:br(s+1)-1);
        assert(numel(seg) == numel(want) && max(abs(seg - (G.RowY(k) + want/G.RowScale(c)))) < 1e-9, ...
            'The drawn mean of %s is not offset by its row at its column''s spacing.',nm);
    end
end
end

function ax = byPosition(ax)
% Axes left to right, then top to bottom.
p = cell2mat(arrayfun(@(a) a.Position,ax(:),'UniformOutput',false));
[~,o] = sortrows([-round(p(:,2),6) p(:,1)]);
ax = ax(o);
end

% =========================================================================
%  Part H -- a session analysed with other settings (13 A9 latency)
% =========================================================================
function partH_settings(app,v,F)
m = app.Model;
k = "SUBJ-ID-9002/SUBJ-ID-9002_2weeks";
s2 = F.Settings;                  % (a value object: F.Settings is untouched)
s2.ConductionDelayMode = "delay";
s2.ConductionDelay = 0.3;
s2.NumPermutations = 40;          % other settings anyway, and a quicker batch
s2.SplitHalfResamples = 20;
m.batch(k,SkipCurrent=false,Settings=s2);
v.showSub("Growth");
drive(app,control(app,'AnalysisStudyMeasure'),'latency');
assert(v.BannerKind == "settings",'No settings banner after a session was re-analysed with other settings (%s).',v.BannerKind);
bt = string(control(app,'AnalysisStudyBannerText').Text);
assert(~isempty(regexp(bt,'^Analysed with different settings: 1 of \d+ sessions\.$','once')),'Settings banner: %s',bt);
assert(string(control(app,'AnalysisStudyBanner').Visible) == "on" && string(control(app,'AnalysisStudyDuplicates').Visible) == "off", ...
    'Two banners at once.');
G = v.growthTable();
Pk = v.Data.A.Peaks;
r = find(G.Session == k,1);
assert(~isempty(r),'The re-analysed session has no latency points.');
q = Pk.Session == k & Pk.SeriesKey == G.SeriesKey(r) & Pk.Level == G.Level(r) & Pk.Wave == "I";
assert(abs(Pk.LatencyOffset(q) - 0.3) < 1e-12 && abs(G.Y(r) - (Pk.PeakLatency(q) - 0.3)) < 1e-9, ...
    'The latency is not re sound arrival (raw - 0.3 ms).');
yl = string(axesOf(v.Handles.GrowthPanel).YLabel.String);
assert(yl == "Wave I latency re sound arrival (ms)",'Latency label with a delay: %s',yl);
% the grand averages are drawn in ear time too
v.showSub("Waveforms");
W = v.waveTable();
assert(any(contains(W.Sessions,k)),'The re-analysed session has no curve at %s dB.',string(control(app,'AnalysisStudyWaveLevel').Value));
wl = string(axesOf(v.Handles.WavesPanel).XLabel.String);
assert(wl == "Time re sound arrival (ms)" && contains(v.PlotNotes.Waveforms,"time re sound arrival"), ...
    'Waveforms with a delay: %s (%s)',wl,v.PlotNotes.Waveforms);
% the Sessions table highlights the odd hash and counts it out of date
v.showSub("Sessions");
assert(contains(string(control(app,'AnalysisStudyAnalyseStale').Text),"Analyse 1 out-of-date"), ...
    'The out-of-date count: %s',control(app,'AnalysisStudyAnalyseStale').Text);
% [Re-analyse them] puts it back on the project's settings
press(app,'AnalysisStudyBannerAction');
assert(v.BannerKind ~= "settings",'The settings banner is still up after Re-analyse them.');
v.showSub("Growth");
assert(string(axesOf(v.Handles.GrowthPanel).YLabel.String) == "Wave I latency (ms)",'The delay outlived the re-analysis.');
v.showSub("Waveforms");
assert(string(axesOf(v.Handles.WavesPanel).XLabel.String) == "Time re onset (ms)",'The waveforms kept the delay after the re-analysis.');
v.showSub("Growth");
drive(app,control(app,'AnalysisStudyMeasure'),'amp-pt');
fprintf('  PASS Part H: a session re-analysed with other settings raises "Analysed with different settings: 1 of n sessions"; its latencies are re sound arrival (raw - 0.3 ms, labelled so); [Re-analyse them] clears it (%.1f s)\n',lap());
end

% =========================================================================
%  Part I -- blind review
% =========================================================================
function partI_blind(app,v,F)
m = app.Model;
v.showSub("Thresholds");
m.startReviewQueue(F.Keys(1:2),UnreviewedOnly=false,Blind=true);
emp = findall(app.Figure,'Tag','AnalysisStudyEmpty');
v.refresh("all",strings(0,1));
assert(~isempty(emp) && string(emp.Text) == "The Study tab is off during blind review.", ...
    'The Study view does not switch off in blind review.');
tab0 = app.ActiveTab;
app.activateTab("Study");
assert(app.ActiveTab == tab0 || app.ActiveTab == "Study",'activateTab during blind review.');
m.endQueue();
app.activateTab("Study");
v.refresh("all",strings(0,1));
ep = findall(app.Figure,'Tag','AnalysisStudyEmptyPanel');
assert(string(ep.Visible) == "off" && ~isempty(v.thresholdTable()),'The Study view did not come back after the review.');
fprintf('  PASS Part I: the Study view is off during blind review and back after it (%.1f s)\n',lap());
end

% =========================================================================
%  Part K -- the clean-sweeps banner
% =========================================================================
function partK_sweeps(app,v)
% Half the clean sweeps in the 2-week sessions' results (as a re-analysis
% with harsher rejection would leave them), then Rescan, as a person does
% after files changed outside the window: the groups' medians now differ
% by far more than 20%. The files are put back and the banner goes.
m = app.Model;
v.showSub("Thresholds");
keys = ["SUBJ-ID-9001/SUBJ-ID-9001_2weeks","SUBJ-ID-9002/SUBJ-ID-9002_2weeks"];
files = strings(1,numel(keys));
orig = cell(1,numel(keys));
for i = 1:numel(keys)
    files(i) = m.Catalog.resultsFile(keys(i));
    orig{i} = load(files(i),'-mat');
end
restore = onCleanup(@() putBack(files,orig));
for i = 1:numel(keys)
    S = orig{i};
    S.Conditions.nClean = round(S.Conditions.nClean/2);
    save(files(i),'-struct','S');
end
m.rescan();
v.flush();
bt = string(control(app,'AnalysisStudyBannerText').Text);
assert(v.BannerKind == "sweeps" && string(control(app,'AnalysisStudyBanner').Visible) == "on" && ...
    startsWith(bt,"Median clean sweeps differ by more than 20% between the plotted groups (") && ...
    contains(bt,"Baseline ") && contains(bt,"2weeks ") && ...
    string(control(app,'AnalysisStudyBannerAction').Visible) == "off", ...
    'Clean-sweeps banner: %s (%s)',bt,v.BannerKind);
clear restore
m.rescan();
v.flush();
assert(v.BannerKind ~= "sweeps",'The clean-sweeps banner outlived the files that raised it.');
fprintf('  PASS Part K: clean sweeps halved at one timepoint raise "Median clean sweeps differ by more than 20%% between the plotted groups (…)" (no action button); it goes with the files (%.1f s)\n',lap());
end

function putBack(files,orig)
for i = 1:numel(files)
    S = orig{i};       % (saved by name)
    try
        save(files(i),'-struct','S');
    catch
    end
end
end

% =========================================================================
%  Part J -- no results yet
% =========================================================================
function partJ_empty(app,v)
m = app.Model;
empty = string(tempname);
mkdir(empty);
cl = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(empty));
m.setResultsFolder(empty);
app.activateTab("Study");
v.refresh("all",strings(0,1));
emp = findall(app.Figure,'Tag','AnalysisStudyEmpty');
n = height(v.Data.V);
assert(string(emp.Text) == "0 of " + n + " sessions analysed — select them and press Analyse.", ...
    'Empty study: %s',emp.Text);
b = findall(app.Figure,'Tag','AnalysisStudyEmptyAction1');
assert(string(b.Visible) == "on" && startsWith(string(b.Text),"Analyse " + n + " sessions"),'The empty state''s Analyse button.');
press(app,'AnalysisStudyEmptyAction2');
ep = findall(app.Figure,'Tag','AnalysisStudyEmptyPanel');
assert(string(ep.Visible) == "off" && v.ActiveSub == "Sessions",'"Label sessions first" did not show the Sessions table.');
fprintf('  PASS Part J: a study with no results says "0 of %d sessions analysed — select them and press Analyse." and offers Analyse / Label sessions first (%.1f s)\n',n,lap());
end

% =========================================================================
%  Helpers
% =========================================================================
function [app,stub] = newApp(F)
stub = newStub(F.ResultsFolder);
app = mabr.ui.AnalysisApp(F.Root,Visible="off",ResultsFolder=F.ResultsFolder, ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false,RememberState=false, ...
    ProgressMode="none",AutoRefresh=false,ConfirmFcn=stub.Confirm,PromptFcn=stub.Prompt, ...
    PickFolderFcn=stub.PickFolder,PickFileFcn=stub.PickFile,AlertFcn=stub.Alert);
end

function stub = newStub(work)
% Dialog stand-ins: record what was asked; answer from a queue, else the first option.
calls   = containers.Map('KeyType','char','ValueType','any');
answers = containers.Map('KeyType','char','ValueType','any');
calls('confirm') = strings(0,1);
calls('alert') = strings(0,1);
answers('prompt') = "";
answers('queue') = strings(1,0);
answers('folder') = "";
stub.Calls   = calls;
stub.Answers = answers;
stub.Confirm    = @(msg,title,options,default) stubConfirm(calls,answers,msg,title,options);
stub.Alert      = @(msg,title,icon) stubRecord(calls,'alert',string(title) + ": " + string(msg));
stub.Prompt     = @(prompt,title,default) answers('prompt');
stub.PickFolder = @(start,title) answers('folder');
stub.PickFile   = @(filter,title,mode,default) string(fullfile(work,"picked.dat"));
end

function c = stubConfirm(calls,answers,msg,title,options)
stubRecord(calls,'confirm',string(msg) + " | " + string(title));
q = answers('queue');
if ~isempty(q)
    c = q(1);
    answers('queue') = q(2:end); %#ok<NASGU> (a containers.Map)
else
    c = string(options(1));
end
end

function stubRecord(calls,key,text)
calls(key) = [calls(key); string(text)]; %#ok<NASGU> (a containers.Map)
end

function h = control(app,tag)
% The one control tagged TAG in the window (found once, then remembered:
% a findall over the whole uifigure costs tens of milliseconds).
persistent cache fig
if isempty(cache) || ~isequal(fig,app.Figure)
    cache = containers.Map('KeyType','char','ValueType','any');
    fig = app.Figure;
end
k = char(tag);
if isKey(cache,k)
    h = cache(k);
    if isvalid(h), return; end
end
h = findall(app.Figure,'Tag',k);
assert(isscalar(h),'%d controls tagged %s.',numel(h),tag);
cache(k) = h;
end

function drive(app,h,value)
% A person picking VALUE in a dropdown; the callback's errors would only
% reach the status line, so a red status line fails the test here.
app.setStatus("",0);
h.Value = value;
h.ValueChangedFcn(h,[]);
assertNoError(app,string(h.Tag) + " = " + string(value));
end

function press(app,tag)
app.setStatus("",0);
h = control(app,tag);
h.ButtonPushedFcn(h,[]);
assertNoError(app,tag);
end

function assertNoError(app,what)
lab = control(app,'AnalysisStatusText');
assert(~isequal(lab.FontColor,mabr.ui.analysis.Style.Error),'%s failed: %s',what,string(lab.Text));
end

function editCell(t,r,c,value)
% A person typing VALUE into cell (r,c) of a table.
evt = struct('Indices',[r c],'NewData',value,'PreviousData',[],'EditData',value,'Error',[]);
t.CellEditCallback(t,evt);
end

function r = rowOf(t,v,key)
r = find(v.tableKeys() == key,1);
assert(~isempty(r) && r <= size(t.Data,1),'No row for %s.',key);
end

function s = statusText(app)
s = string(control(app,'AnalysisStatusText').Text);
end

function v = projectValue(m,key,name)
T = m.Project.Sessions;
v = string(T.(name)(T.Key == key));
end

function v = projectLogical(m,key,name)
T = m.Project.Sessions;
v = logical(T.(name)(T.Key == key));
end

function ax = axesOf(panel)
ax = findall(panel,'Type','axes','Tag','AnalysisStudyAxes');
ax = flipud(ax(:));
end

function s = legendStrings(panel)
% Every legend entry of the panel's axes.
s = strings(1,0);
ax = axesOf(panel);
for k = 1:numel(ax)
    L = ax(k).Legend;
    if ~isempty(L) && isvalid(L)
        s = [s, reshape(string(L.String),1,[])]; %#ok<AGROW>
    end
end
end

function t = titlesOf(ax)
t = strings(numel(ax),1);
for k = 1:numel(ax)
    t(k) = string(ax(k).Title.String);
end
end

function s = lap()
% Seconds since the last call (the first call starts the clock).
persistent t
if isempty(t), t = tic; end
s = toc(t);
t = tic;
end

function g = groupOf(h)
% The colour group a summary line was drawn for (its legend entry less " (n = k)").
g = string(regexprep(char(h.DisplayName),'\s*\(n = \d+\)$',''));
end

function v = subjectMeans(P)
% Each subject's mean of its plotted values (what a summary is taken over).
s = unique(P.Subject);
v = zeros(numel(s),1);
for k = 1:numel(s)
    v(k) = mean(P.Plotted(P.Subject == s(k)));
end
end

function closeQuietly(app)
try
    if ~isempty(app) && isvalid(app), delete(app); end
catch
end
end
