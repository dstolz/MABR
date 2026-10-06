function verify_offline_browser()
% verify_offline_browser  The analysis app's browser and Session tab: tree, filter, labels, files, overrides.
%
%   Drives mabr.ui.analysis.Browser and mabr.ui.analysis.SessionView inside
%   an invisible mabr.ui.AnalysisApp over mabrtest.OfflineFixture (two
%   subjects -- SUBJ-ID-1254 and SUBJ-ID-959, so natural order is tested --
%   at Baseline and 2 weeks, plus SUBJ-ID-1254's mixed tone/click session
%   with both acquisition modes), the way a person would: by the controls'
%   own callbacks, found by Tag, and by the public methods the views offer.
%
%     Part A  the tree: subjects in natural order with their counts, one
%             visit per day labelled "yyyy-MM-dd · <timepoint> (n)", session
%             texts as Browser.nodeText makes them (status glyphs, badges,
%             review counts -- every glyph and badge checked on hand-made
%             rows too), the Model told the order; a status change rewrites
%             a node in place without a rebuild, and so does a rescan that
%             found nothing new (the nodes, and what is expanded, stay)
%     Part B  the filter: search text over subject/folder/stimuli, every
%             Show choice, the typing debounce (flush applies it; with
%             timers on, a MABR_OfflineSearch timer that flush stops)
%     Part C  selection: selectKeys/selectedKeys/selectedNodeInfo, the
%             details text, Open (button and openSelected), the multi-
%             selection's Analyse/Pool enables, Analyse n sessions… opening
%             the batch dialog on them, pooling (the confirmation
%             lists what is pooled per condition; a pool node appears under
%             its visit) and undo
%     Part D  labels: Timepoint on a visit node labels every session of
%             that day (ProjectChanged(labels)); Group is a subject label;
%             In study; Comment (method and button); the context menu's
%             Set timepoint ▸ New… and In study
%     Part E  the results link's text and what clicking it does; the
%             folder dropdown
%     Part F  the Session tab's matrix: rows of levels loudest first,
%             columns of series, −log10 p never negative ("-0.0") and
%             blank (not 307.7) without a p, the metric switch, the final
%             threshold's
%             step line between the right rows, a click selecting the
%             condition (and the cell outlined), a double-click opening the
%             Series tab; notes in both scopes, each once; the messages
%             (warnings first); the processing summary
%     Part G  the Files table: grouped by run, a staged Use edit and the
%             pending line, Discard, Apply re-segmenting (ResultsChanged
%             all) and undo, the bulk buttons, the run-group context
%             actions, Copy table
%     Part H  the overrides row: a sound conduction delay (13 A9) re-picks
%             the peaks and keeps the session up to date; a full-scale
%             override makes it out of date (and the browser says so in
%             place); clearing it brings it back; a bad number is refused;
%             a number typed and never applied does not follow the user to
%             another session
%     Part I  a nested results store: the banner, Import, Ignore
%     Part J  blind review covers the tree; End review uncovers it
%     Part L  exclude and hide: the context menu's item hides a session
%             (out of the tree, the study and the all / in-study scopes, its
%             own In study label kept; the details count it), Show ▸ Hidden
%             lists only it with In study greyed and the item reading
%             Unhide, Delete on a subject node hides its sessions and the
%             subject with them, Ctrl+Z, the Session menu's two items
%     Part K  prefs: only the Session tab's own controls wrote one
%             (OfflineAnalysisSession); scripts driving both views wrote none
%
%   No hardware, no parallel pool, no modal dialog; tempdir only; every pref
%   put back (mabrtest.prefGuard).
%
%   See also mabr.ui.analysis.Browser, mabr.ui.analysis.SessionView,
%   mabrtest.OfflineFixture, verify_offline_app
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_browser ==\n');
tAll  = tic;
figs0 = findall(groot,'Type','figure');
guard = mabrtest.prefGuard(mabr.ui.AnalysisApp.prefKeys()); %#ok<NASGU>

F = mabrtest.OfflineFixture.make(Subjects=["SUBJ-ID-1254","SUBJ-ID-959"]);
fprintf('  (fixture: %d sessions analysed in %.1f s)\n',numel(F.Keys),toc(tAll));
[app,stub] = newApp(F);
closer = mabrtest.OfflineFixture.closer(app,F); %#ok<NASGU> (the app, THEN the fixture's folders)
assert(isa(app.Browser,'mabr.ui.analysis.Browser'),'The app did not build the browser.');
% no session open: the Session tab says how to open one and shows no plot
% (so Export Figure… has nothing to export)
em = findall(app.Figure,'Tag','AnalysisSessionEmpty');
assert(~isempty(em) && string(em.Text) == mabr.ui.analysis.SessionView.EmptyText && ...
    isempty(findall(app.Figure,'Tag','AnalysisSessionMatrixAxes','Visible','on')), ...
    'The Session tab with no session open.');
prefs0 = allPrefs();

t0 = tic; partA_tree(app,F);          tA = toc(t0);
t0 = tic; partB_filter(app,F);        tB = toc(t0);
t0 = tic; partC_select(app,F,stub);   tC = toc(t0);
t0 = tic; partD_labels(app,F,stub);   tD = toc(t0);
t0 = tic; partE_links(app,F);         tE = toc(t0);
prefsMid = allPrefs();
assert(isempty(changedPrefs(prefs0,prefsMid)),'Driving the browser wrote a pref: %s', ...
    strjoin(changedPrefs(prefs0,prefsMid),', '));
t0 = tic; partF_matrix(app,F,prefs0); tF = toc(t0);
t0 = tic; partG_files(app,F);         tG = toc(t0);
t0 = tic; partH_overrides(app,F);     tH = toc(t0);
t0 = tic; partI_nested(app,F);        tI = toc(t0);
t0 = tic; partJ_blind(app,F);         tJ = toc(t0);
t0 = tic; partL_hide(app,F);          tL = toc(t0);
fprintf('  (parts A-J, L: %s s)\n',strjoin(compose('%.1f',[tA tB tC tD tE tF tG tH tI tJ tL]),' '));
changed = changedPrefs(prefs0,allPrefs());
assert(isequal(changed,"OfflineAnalysisSession"), ...
    'Only the Session tab''s controls may write a pref; changed: [%s].',strjoin(changed,', '));
fprintf('  PASS Part K: only the Session tab''s own controls wrote a pref (OfflineAnalysisSession)\n');

clear closer
closeQuietly(app);
drawnow;
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_browser left a figure open.');
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_browser PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Part A -- the tree
% =========================================================================
function partA_tree(app,F)
m  = app.Model;
br = app.Browser;
t  = ctrl(app,'AnalysisBrowserTree');
V  = m.projectView();
subj = string(arrayfun(@(n) string(n.Text),t.Children,'UniformOutput',false));
assert(isequal(reshape(subj,1,[]),["SUBJ-ID-959 (2)","SUBJ-ID-1254 (3)"]), ...
    'Subjects are not in natural order with their counts: %s',strjoin(subj,' | '));
s1254 = t.Children(2);
visits = s1254.Children;
assert(numel(visits) == 2,'SUBJ-ID-1254 should have two visits (2026-10-01, 2026-10-15).');
for k = 1:numel(visits)
    d = visits(k).NodeData;
    assert(d.Type == "visit" && d.Subject == "SUBJ-ID-1254",'A visit node has the wrong NodeData.');
    rows = string(V.Subject) == "SUBJ-ID-1254" & ~V.IsPool & dateshift(V.Day,'start','day') == d.Day;
    want = mabr.ui.analysis.Browser.visitText(d.Day,V.Timepoint(rows),sum(rows));
    assert(string(visits(k).Text) == want,'Visit text "%s", not "%s".',visits(k).Text,want);
end
assert(startsWith(string(visits(1).Text),"2026-10-01 · ") && endsWith(string(visits(1).Text),"(2)") && ...
    startsWith(string(visits(2).Text),"2026-10-15"),'Visits are not one per day, ascending (%s, %s).', ...
    visits(1).Text,visits(2).Text);
% every session node: Browser.nodeText of its row; the mixed one carries ⧉
for k = reshape(F.Keys,1,[])
    n = nodeOf(t,k);
    assert(~isempty(n),'No node for %s.',k);
    r = find(string(V.Key) == k,1);
    row = table2struct(V(r,:));
    assert(string(n.Text) == mabr.ui.analysis.Browser.nodeText(row),'Node text of %s: %s',k,n.Text);
    assert(startsWith(string(n.Text),mabr.ui.analysis.Style.GlyphCurrent + " "), ...
        'An analysed session does not lead with ● (%s).',n.Text);
    assert(contains(string(n.Text),"✓0/"),'The review count is missing (%s).',n.Text);
end
kMixed = F.Keys(contains(F.Keys,"T140000"));
nm = nodeOf(t,kMixed);
assert(contains(string(nm.Text),"14:00") && contains(string(nm.Text),mabr.ui.analysis.Style.BadgeInterleaved), ...
    'The mixed session does not show 14:00 and ⧉: %s',nm.Text);
assert(isequal(sort(m.BrowserOrder),sort(F.Keys)) && isequal(m.BrowserOrder,br.VisibleKeys), ...
    'The Model was not told the browser''s order.');
assert(contains(m.BrowserOrder(1),"SUBJ-ID-959"),'The browser order does not follow the tree.');
% the glyphs and badges, on rows made by hand
row = struct('Status',"none",'Start',datetime(2026,10,1,14,8,0),'Summary',"Tone 6×9 ×2", ...
    'NumFiles',126,'AcqModes',"conventional",'ShortRuns',0,'TestMode',"none",'Reviewed',0,'NumSeries',0);
assert(mabr.ui.analysis.Browser.nodeText(row) == "○ 14:08  Tone 6×9 ×2 · 126 files", ...
    'nodeText (not analysed): %s',mabr.ui.analysis.Browser.nodeText(row));
row.Status = "stale"; row.AcqModes = "conventional, interleaved"; row.ShortRuns = 2;
row.TestMode = "some"; row.Reviewed = 5; row.NumSeries = 7;
assert(mabr.ui.analysis.Browser.nodeText(row) == "◐ 14:08  Tone 6×9 ×2 · 126 files ⧉ ⚠ TEST ✓5/7", ...
    'nodeText (badges): %s',mabr.ui.analysis.Browser.nodeText(row));
row.Status = "current"; row.Reviewed = 7;
assert(startsWith(mabr.ui.analysis.Browser.nodeText(row),"✓ 14:08"),'Fully reviewed is not ✓.');
row.Status = "failed";
assert(startsWith(mabr.ui.analysis.Browser.nodeText(row),"✕ "),'Failed is not ✕.');
row.IsPool = true; row.PoolStarts = ["14:00";"14:08"]; row.Status = "none"; row.NumSeries = 0;
row.TestMode = "none"; row.ShortRuns = 0; row.AcqModes = "";
assert(startsWith(mabr.ui.analysis.Browser.nodeText(row),"⊕ Pool: 14:00 + 14:08"), ...
    'A pool node: %s',mabr.ui.analysis.Browser.nodeText(row));
% a timepoint that only repeats the day is not said twice
assert(mabr.ui.analysis.Browser.visitText(datetime(2026,10,1),["2026-10-01";"2026-10-01"],2) == ...
    "2026-10-01 (2)",'visitText repeats the day as a timepoint.');
assert(mabr.ui.analysis.Browser.visitText(NaT,"",2) == "(unknown date) (2)" && ...
    mabr.ui.analysis.Browser.visitText(datetime(2026,10,1),["Baseline";"Baseline";""],3) == ...
    "2026-10-01 · Baseline (3)",'visitText.');
% a status that moves rewrites its node in place (no rebuild)
k2 = F.Keys(contains(F.Keys,"SUBJ-ID-959_2weeks"));
n0 = br.RebuildCount;
m.setSessionOverrides(k2,struct('InputFullScale',2));
assert(startsWith(string(nodeOf(t,k2).Text),mabr.ui.analysis.Style.GlyphStale + " "), ...
    'An override did not turn the node out of date: %s',nodeOf(t,k2).Text);
m.setSessionOverrides(k2,struct('InputFullScale',NaN));
assert(startsWith(string(nodeOf(t,k2).Text),mabr.ui.analysis.Style.GlyphCurrent + " "), ...
    'Clearing the override did not bring the node back: %s',nodeOf(t,k2).Text);
assert(br.RebuildCount == n0,'A status change rebuilt the tree (%d rebuilds).',br.RebuildCount - n0);
% a rescan that finds nothing new keeps the nodes (and so what is expanded)
n1 = nodeOf(t,k2);
m.rescan();
assert(br.RebuildCount == n0 && isequal(nodeOf(t,k2),n1) && isvalid(n1), ...
    'A rescan that found nothing new rebuilt the tree.');
assert(isequal(m.BrowserOrder,br.VisibleKeys),'The Model lost the browser''s order on a rescan.');
fprintf(['  PASS Part A: subjects in natural order, one visit per day, node texts (glyphs, ⧉, ✓n/m; ' ...
    'every badge on hand-made rows), the Model told the order; a status change rewrites a node ' ...
    'in place, a rescan keeps the nodes\n']);
end

% =========================================================================
%  Part B -- the filter
% =========================================================================
function partB_filter(app,F)
br = app.Browser;
m  = app.Model;
t  = ctrl(app,'AnalysisBrowserTree');
br.applyFilter("959");
assert(isscalar(t.Children) && isequal(sort(br.VisibleKeys),sort(F.Keys(contains(F.Keys,"959")))), ...
    'Searching "959" did not leave SUBJ-ID-959''s sessions.');
assert(isequal(m.BrowserOrder,br.VisibleKeys),'The filtered order did not reach the Model.');
br.applyFilter("2WEEKS");
assert(numel(br.VisibleKeys) == 2 && all(contains(br.VisibleKeys,"2weeks")),'Search is not by folder, any case.');
br.applyFilter("clicktrain");
assert(isscalar(br.VisibleKeys) && contains(br.VisibleKeys,"T140000"),'Search is not by stimulus.');
br.applyFilter("","Test Mode");
assert(isempty(br.VisibleKeys) && isempty(t.Children),'Show Test Mode listed sessions that are not.');
br.applyFilter("","Not analysed");
assert(isempty(br.VisibleKeys),'Show Not analysed listed analysed sessions.');
br.applyFilter("","Needs review");
assert(numel(br.VisibleKeys) == numel(F.Keys),'Show Needs review: every session has series to review.');
for s = mabr.ui.analysis.Browser.showNames()
    br.applyFilter("",s);           % every choice is accepted
end
% the controls themselves
sh = ctrl(app,'AnalysisBrowserShow');
sh.Value = 'Out of date';
sh.ValueChangedFcn(sh,[]);
assert(br.FilterShow == "Out of date" && isempty(br.VisibleKeys),'The Show dropdown.');
sh.Value = 'All';
sh.ValueChangedFcn(sh,[]);
ef = ctrl(app,'AnalysisBrowserSearch');
ef.ValueChangingFcn(ef,struct('Value','1254'));
assert(numel(br.VisibleKeys) == numel(F.Keys) && br.PendingSearch == "1254", ...
    'Typing filtered before the pause.');
app.flush();
assert(numel(br.VisibleKeys) == 3 && isempty(br.PendingSearch),'flush() did not apply the typed search.');
% with timers on, the pause is a MABR_OfflineSearch timer that flush stops
m.AutoRefresh = true;
ef.ValueChangingFcn(ef,struct('Value','959'));
assert(~isempty(timerfindall('Tag','MABR_OfflineSearch')),'No debounce timer while typing.');
br.flush();
m.AutoRefresh = false;
assert(isempty(timerfindall('Tag','MABR_OfflineSearch')) && numel(br.VisibleKeys) == 2, ...
    'flush() did not stop the debounce timer and apply the search.');
ef.Value = '';
ef.ValueChangedFcn(ef,[]);
assert(numel(br.VisibleKeys) == numel(F.Keys) && br.FilterText == "",'Clearing the search (Enter).');
fprintf('  PASS Part B: search (subject, folder, stimulus; any case), every Show choice, the typing debounce\n');
end

% =========================================================================
%  Part C -- selection, details, open, pool
% =========================================================================
function partC_select(app,F,stub)
br = app.Browser;
m  = app.Model;
kB = F.Keys(contains(F.Keys,"SUBJ-ID-1254_Baseline"));
kM = F.Keys(contains(F.Keys,"T140000"));
k9 = F.Keys(contains(F.Keys,"SUBJ-ID-959_Baseline"));
br.selectKeys(kB);
info = br.selectedNodeInfo();
assert(info.Type == "session" && info.Key == kB && isequal(br.selectedKeys(),kB),'selectKeys / selectedNodeInfo.');
dt = string(ctrl(app,'AnalysisBrowserDetails').Value);
assert(dt(1) == "SUBJ-ID-1254_Baseline" && any(startsWith(dt,"Status: Up to date")) && ...
    any(contains(dt,"files (")) && any(startsWith(dt,"Results: ")),'The details text: %s',strjoin(dt,' | '));
br.openSelected();
assert(m.SessionKey == kB,'openSelected did not open the selection.');
br.selectKeys(kM);
b = ctrl(app,'AnalysisBrowserOpen');
b.ButtonPushedFcn(b,[]);
assert(m.SessionKey == kM,'The Open button did not open the selection.');
assert(m.FocusArea == "browser",'A browser control did not record the browser as the focus area.');
m.FocusArea = "workspace";
% a subject node stands for its sessions
t = ctrl(app,'AnalysisBrowserTree');
t.SelectedNodes = t.Children(2);
t.SelectionChangedFcn(t,[]);
assert(isequal(sort(br.selectedKeys()),sort(F.Keys(contains(F.Keys,"1254")))),'A subject node''s keys.');
% several: Analyse names the count; Pool only within one subject
br.selectKeys([kB;kM]);
an = ctrl(app,'AnalysisBrowserAnalyse');
pl = ctrl(app,'AnalysisBrowserPool');
assert(string(an.Text) == "Analyse 2 sessions…" && strcmp(an.Enable,'on') && strcmp(pl.Enable,'on'), ...
    'Two sessions of one subject: "%s", Pool %s.',an.Text,pl.Enable);
% Analyse n sessions… opens the batch dialog on exactly those sessions
% (a dialog's window position is a pref -- WindowPos creates it on opening
% and stores it on closing; not a look the browser chose, so it is put back
% here for Part K's count)
wp = 'WindowPos_OfflineAnalysisBatch';
had = ispref('MABR',wp);
if had, old = getpref('MABR',wp); end
nd = numel(app.Dialogs);
an.ButtonPushedFcn(an,[]);
assert(numel(app.Dialogs) == nd + 1 && isa(app.Dialogs{end},'mabr.ui.analysis.BatchDialog') && ...
    isequal(sort(app.Dialogs{end}.Keys),sort([kB;kM])), ...
    'Analyse 2 sessions… did not open the batch dialog on the selection.');
delete(app.Dialogs{end});
if had, setpref('MABR',wp,old); elseif ispref('MABR',wp), rmpref('MABR',wp); end
br.selectKeys([kB;k9]);
assert(strcmp(pl.Enable,'off'),'Pool is offered for sessions of two subjects.');
% pooling: the confirmation lists the conditions; the pool sits under its visit
br.selectKeys([kB;kM]);
n0 = numel(stub.Calls('confirm'));
pk = br.poolSelected();
c = stub.Calls('confirm');
assert(numel(c) == n0 + 1 && contains(c(end),"Pooled per condition") && contains(c(end),"sweeps") && ...
    contains(c(end),"Pool sweeps"),'The pool confirmation does not list the conditions:\n%s',c(end));
assert(startsWith(pk,"pool:"),'No pool was made.');
pn = nodeOf(t,pk);
assert(~isempty(pn) && startsWith(string(pn.Text),"⊕ Pool: 10:00 + 14:00") && ...
    pn.Parent.NodeData.Type == "visit",'The pool node: %s',string(pn.Text));
m.undo();
assert(isempty(nodeOf(t,pk)),'Undo did not remove the pool node.');
fprintf(['  PASS Part C: selectKeys/selectedKeys/info, details, Open (button, openSelected), subject ' ...
    'nodes, Analyse n / Pool enables, Analyse n opens the batch dialog on them, pooling lists the ' ...
    'conditions and its node sits under the visit\n']);
end

% =========================================================================
%  Part D -- labels
% =========================================================================
function partD_labels(app,F,stub)
br = app.Browser;
m  = app.Model;
t  = ctrl(app,'AnalysisBrowserTree');
% Timepoint on a visit node: every session of that day
vn = t.Children(2).Children(1);              % SUBJ-ID-1254, 2026-10-01
t.SelectedNodes = vn;
t.SelectionChangedFcn(t,[]);
day = br.selectedKeys();
assert(numel(day) == 2,'The first visit of SUBJ-ID-1254 should hold two sessions.');
rec = recordEvents(m);
tp = ctrl(app,'AnalysisBrowserTimepoint');
tp.Value = 'Day 0';
tp.ValueChangedFcn(tp,[]);
log = rec('log'); delete(rec('listeners'));
assert(any(log == "ProjectChanged(labels)"),'A Timepoint edit raised no ProjectChanged(labels).');
for k = reshape(day,1,[])
    assert(labelOf(m,k,"Timepoint") == "Day 0",'%s did not get the visit''s timepoint.',k);
end
other = setdiff(F.Keys(contains(F.Keys,"1254")),day);
assert(labelOf(m,other,"Timepoint") ~= "Day 0",'The timepoint reached another day.');
assert(isequal(t.Children(2).Children(1),vn),'A label edit rebuilt the tree (its texts move in place).');
assert(contains(string(vn.Text),"Day 0"),'The visit node does not show the new timepoint: %s',vn.Text);
m.undo();
assert(labelOf(m,day(1),"Timepoint") ~= "Day 0",'Undo did not put the timepoint back.');
% Group: a subject label, set from one of its sessions
k9 = F.Keys(contains(F.Keys,"SUBJ-ID-959_Baseline"));
br.selectKeys(k9);
gp = ctrl(app,'AnalysisBrowserGroup');
gp.Value = 'Noise';
gp.ValueChangedFcn(gp,[]);
U = m.Project.Subjects;
assert(string(U.Group(string(U.Subject) == "SUBJ-ID-959")) == "Noise",'Group did not reach the subject.');
V = m.projectView();
assert(all(string(V.Group(contains(string(V.Key),"959"))) == "Noise") && ...
    all(string(V.Group(contains(string(V.Key),"1254"))) ~= "Noise"),'Group is not subject level.');
assert(string(gp.Value) == "Noise" && any(string(gp.Items) == "Noise"),'The Group box does not show it.');
m.undo();
% In study
cb = ctrl(app,'AnalysisBrowserInStudy');
cb.Value = false;
cb.ValueChangedFcn(cb,[]);
assert(~labelOf(m,k9,"InStudy"),'In study (off) was not stored.');
br.applyFilter("","Not in study");
assert(isequal(br.VisibleKeys,k9),'Show Not in study does not list it.');
br.applyFilter("","All");
m.undo();
assert(labelOf(m,k9,"InStudy"),'Undo did not put In study back.');
% Comment: the method, then the button (PromptFcn)
br.selectKeys(k9);
br.comment("loose electrode");
assert(labelOf(m,k9,"Comment") == "loose electrode",'comment() did not store the comment.');
dt = string(ctrl(app,'AnalysisBrowserDetails').Value);
assert(any(dt == "Comment: loose electrode"),'The details do not show the comment.');
stub.Answers('prompt') = "impedance checked";
b = ctrl(app,'AnalysisBrowserComment');
b.ButtonPushedFcn(b,[]);
assert(labelOf(m,k9,"Comment") == "impedance checked",'The Comment button did not store the comment.');
m.undo(); m.undo();
% the context menu: Set timepoint > New..., In study
cm = findall(app.Figure,'Tag','AnalysisBrowserMenu');
cm.ContextMenuOpeningFcn(cm,struct());
it = findall(cm,'Tag','AnalysisBrowserMenuTimepointNew');
stub.Answers('prompt') = "Pre";
it.MenuSelectedFcn(it,[]);
assert(labelOf(m,k9,"Timepoint") == "Pre",'Set timepoint ▸ New… did not label the selection.');
m.undo();
cm.ContextMenuOpeningFcn(cm,struct());
it = findall(cm,'Tag','AnalysisBrowserMenuInStudy');
assert(strcmp(it.Checked,'on'),'The In study item is not checked for a session in the study.');
it.MenuSelectedFcn(it,[]);
assert(~labelOf(m,k9,"InStudy"),'The In study item did not toggle.');
m.undo();
stub.Answers('prompt') = "Pool A";
fprintf(['  PASS Part D: Timepoint on a visit labels the day (ProjectChanged), Group is subject level, ' ...
    'In study, Comment (method, button), context menu New… and In study; all undone\n']);
end

% =========================================================================
%  Part E -- the results link and the folder list
% =========================================================================
function partE_links(app,F)
br = app.Browser;
m  = app.Model;
link = ctrl(app,'AnalysisBrowserResultsPath');
assert(string(link.Text) == m.resultsPathText() && startsWith(string(link.Text),"Results: "), ...
    'The results link reads "%s", not "%s".',link.Text,m.resultsPathText());
box = containers.Map('KeyType','char','ValueType','any');
box('p') = "";
br.OpenFolderFcn = @(p) setBox(box,p);
br.openResultsFolder();
assert(samePath(box('p'),m.resultsFolder()),'The link did not show the results folder.');
br.OpenFolderFcn = [];
dd = ctrl(app,'AnalysisBrowserRoot');
assert(samePath(string(dd.Value),F.Root) && any(arrayfun(@(x) samePath(x,F.Root),string(dd.ItemsData))), ...
    'The folder dropdown does not show the open folder.');
[~,tail] = fileparts(char(F.Root));
assert(any(string(dd.Items) == string(tail)),'The folder dropdown is not labelled by the folder''s name.');
fprintf('  PASS Part E: the results link text and click; the folder dropdown shows the open folder\n');
end

function setBox(box,p)
box('p') = string(p); %#ok<NASGU> (a containers.Map)
end

% =========================================================================
%  Part F -- the Session tab: matrix, notes, messages, summary
% =========================================================================
function partF_matrix(app,F,prefs0)
m = app.Model;
kM = F.Keys(contains(F.Keys,"T140000"));
if m.SessionKey ~= kM, m.openSession(kM); end
app.activateTab("Session");
v = app.Views.Session;
assert(isa(v,'mabr.ui.analysis.SessionView'),'The Session tab is not a SessionView.');
S = m.Session;
M = v.matrixData();
assert(isequal(reshape(M.SeriesKeys,[],1),m.seriesKeys()),'Matrix columns are not the series in order.');
assert(issorted(M.Levels(isfinite(M.Levels)),'descend'),'Matrix rows are not loudest first.');
assert(nnz(M.CondKeys ~= "") == height(S.Conditions),'Not every condition has a cell.');
assert(all(M.Text(M.CondKeys ~= "") ~= "") && any(M.Marks(:) == "●"),'Cells lack values or detection marks.');
% clean sweeps written in each cell
[r,c] = find(M.CondKeys ~= "",1);
row = S.Conditions(string(S.Conditions.Key) == M.CondKeys(r,c),:);
assert(M.Text(r,c) == string(row.nClean),'Cell text %s is not the clean sweeps %d.',M.Text(r,c),row.nClean);
% the final threshold: between the right rows
T = S.Thresholds;
fin = findall(app.Figure,'Tag','AnalysisSessionMatrixFinal');
assert(any(isfinite(fin.YData)),'No final-threshold line is drawn.');
for j = 1:numel(M.SeriesKeys)
    y = M.FinalY(j);
    tr = T(string(T.Key) == M.SeriesKeys(j),:);
    if isempty(tr) || ~isfinite(y), continue; end
    t0 = tr.Final;
    if string(tr.FinalCensored) == "interval", t0 = tr.FinalHi; end
    rows = find(M.CondKeys(:,j) ~= "");
    above = rows(rows < y);  below = rows(rows > y);
    if ismember(string(tr.FinalCensored),["none","interval"])
        assert(all(M.Levels(above) >= t0 - 1e-9) && all(M.Levels(below) < t0 - 1e-9), ...
            'The step line of %s is not between the rows around %g.',M.SeriesKeys(j),t0);
    end
end
% −log10 p of a condition with p = 1 is zero, never "-0.0"
v.setMetric("−log10 p");
Mp = v.matrixData();
assert(~any(startsWith(Mp.Text(:),"-")) && all(Mp.Values(isfinite(Mp.Values)) >= 0), ...
    'A −log10 p cell reads negative: %s',strjoin(Mp.Text(startsWith(Mp.Text(:),"-")),', '));
% ... and a condition with no p (too few sweeps to test) has no value, not
% -log10(realmin) = 307.7 washing every other cell out
Ct = table([0.01;1;NaN],[50;60;NaN],[3;2;1],[64;64;0],'VariableNames',{'p','nClean','nRejected','nSweeps'});
vp = mabr.ui.analysis.SessionView.metricValues(Ct,"−log10 p");
vr = mabr.ui.analysis.SessionView.metricValues(Ct,"% rejected");
vs = mabr.ui.analysis.SessionView.metricValues(Ct,"SNR (dB)");
assert(abs(vp(1) - 2) < 1e-12 && vp(2) == 0 && isnan(vp(3)) && isnan(vr(3)) && all(isnan(vs)), ...
    'metricValues: −log10 p %s, %% rejected %s, SNR %s.',mat2str(vp.'),mat2str(vr.'),mat2str(vs.'));
% script-driven: no pref
v.setMetric("Split-half r");
v.setNotesScope("All notes");
assert(isempty(changedPrefs(prefs0,allPrefs())),'setMetric/setNotesScope from a script wrote a pref.');
v.setNotesScope("During this session");
% the metric dropdown (a user's control: the look is remembered)
md = ctrl(app,'AnalysisSessionMatrixMetric');
md.Value = '% rejected';
md.ValueChangedFcn(md,[]);
ax = findall(app.Figure,'Tag','AnalysisSessionMatrixAxes');
M2 = v.matrixData();
assert(string(ax.Title.String) == "% rejected" && ~isequal(M2.Text,M.Text),'The metric switch did not redraw.');
p = getpref('MABR','OfflineAnalysisSession');
assert(string(p.MatrixMetric) == "% rejected",'The metric dropdown did not remember its choice.');
md.Value = 'Clean sweeps';
md.ValueChangedFcn(md,[]);
% a click selects the condition and outlines its cell
[r,c] = find(M.CondKeys ~= "" & M.CondKeys ~= m.Selection.ConditionKey,1);
im = findall(app.Figure,'Tag','AnalysisSessionMatrixImage');
im.ButtonDownFcn(im,struct('IntersectionPoint',[c r 0]));
assert(m.Selection.ConditionKey == M.CondKeys(r,c),'A click did not select the condition.');
sel = findall(app.Figure,'Tag','AnalysisSessionMatrixSelection');
assert(abs(mean(sel.XData(1:4)) - c) < 1e-9 && abs(mean(sel.YData(1:4)) - r) < 1e-9, ...
    'The selected cell is not outlined.');
m.stepLevel(1);
sel = findall(app.Figure,'Tag','AnalysisSessionMatrixSelection');
[r2,c2] = find(M.CondKeys == m.Selection.ConditionKey,1);
assert(abs(mean(sel.YData(1:4)) - r2) < 1e-9 && abs(mean(sel.XData(1:4)) - c2) < 1e-9, ...
    'The outline did not follow a level step.');
% a double-click opens the Series tab
v.selectCell(M.SeriesKeys(1),max(M.Levels),Open=true);
assert(app.ActiveTab == "Series" && m.Selection.SeriesKey == M.SeriesKeys(1),'A double-click did not open Series.');
app.activateTab("Session");
% notes, each once, in both scopes
nt = ctrl(app,'AnalysisSessionNotes');
L = string(nt.Value);
assert(any(contains(L,"Electrode impedance 3.2 kOhm")) && numel(unique(L)) == numel(L), ...
    'The session''s notes: %s',strjoin(L,' | '));
sd = ctrl(app,'AnalysisSessionNotesScope');
sd.Value = 'All notes';
sd.ValueChangedFcn(sd,[]);
L2 = string(nt.Value);
assert(numel(L2) >= numel(L) && numel(unique(L2)) == numel(L2) && ...
    any(contains(L2,"Ear plug slipped")),'All notes: %s',strjoin(L2,' | '));
p = getpref('MABR','OfflineAnalysisSession');
assert(string(p.NotesScope) == "All notes",'The notes scope was not remembered.');
sd.Value = 'During this session';
sd.ValueChangedFcn(sd,[]);
% messages, warnings first; the summary
mt = ctrl(app,'AnalysisSessionMessages');
D = mt.Data;
assert(height(D) == height(S.Messages),'The messages table has %d rows for %d messages.',height(D),height(S.Messages));
lev = string(D.Level);
w = find(lev == "warning" | lev == "error");
if ~isempty(w)
    assert(isequal(w(:).',1:numel(w)),'Warnings are not first in the messages table.');
end
sm = string(ctrl(app,'AnalysisSessionSummary').Value);
assert(any(startsWith(sm,"Filter: ")) && any(startsWith(sm,"Settings: profile")) && ...
    any(startsWith(sm,"Results: ")) && any(startsWith(sm,"Acquisition: ")) && ...
    any(startsWith(sm,"Data fingerprint: ")),'The summary: %s',strjoin(sm,' | '));
fprintf(['  PASS Part F: matrix (levels loudest first, series columns, values and ●/○, −log10 p ' ...
    'never negative nor 307.7 without a p, the final ' ...
    'line between the right rows), metric switch, click and double-click, notes in both scopes, ' ...
    'messages warnings first, summary\n']);
end

% =========================================================================
%  Part G -- the Files table
% =========================================================================
function partG_files(app,F)
m = app.Model;
v = app.Views.Session;
kM = F.Keys(contains(F.Keys,"T140000"));
if m.SessionKey ~= kM, m.openSession(kM); end
S = m.Session;
tb = ctrl(app,'AnalysisSessionFiles');
pend = ctrl(app,'AnalysisSessionPending');
ap = ctrl(app,'AnalysisSessionApplyFiles');
dc = ctrl(app,'AnalysisSessionDiscardFiles');
D = tb.Data;
assert(height(D) == height(S.Files) && isequal(sort(v.FileIds),sort(string(S.Files.FileId))), ...
    'The Files table does not list the session''s files.');
assert(isequal(string(tb.ColumnName(:)).',v.FileColumns),'The Files table''s columns.');
g = string(D.("Run group"));
[~,first] = unique(g,'stable');
for k = 1:numel(first)
    rows = find(g == g(first(k)));
    assert(isequal(rows(:).',rows(1):rows(end)),'Run group "%s" is not contiguous.',g(first(k)));
end
assert(all(D.Use) && strcmp(ap.Enable,'off') && string(pend.Text) == "",'Nothing is staged at first.');
% a staged edit, then Discard
D.Use(1) = false;
tb.Data = D;
tb.CellEditCallback(tb,struct('Indices',[1 1],'NewData',false,'PreviousData',true,'EditData',false));
assert(startsWith(string(pend.Text),"1 change — Apply re-segments the affected conditions") && ...
    strcmp(ap.Enable,'on') && isequal(m.PendingFileUse.FileIds,v.FileIds(1)), ...
    'A staged edit: "%s".',pend.Text);
dc.ButtonPushedFcn(dc,[]);
assert(isempty(m.PendingFileUse.FileIds) && string(pend.Text) == "" && all(tb.Data.Use), ...
    'Discard did not forget the staged edit.');
% bulk: only conventional (the mixed session has interleaved runs too)
b = ctrl(app,'AnalysisSessionOnlyConventional');
b.ButtonPushedFcn(b,[]);
[~,loc] = ismember(v.FileIds,string(S.Files.FileId));
conv = string(S.Files.AcqMode(loc)) == "conventional";
assert(any(~conv) && isequal(tb.Data.Use,conv),'Only conventional did not stage the interleaved files off.');
b = ctrl(app,'AnalysisSessionUseAll');
b.ButtonPushedFcn(b,[]);
assert(isempty(m.PendingFileUse.FileIds) && all(tb.Data.Use),'Use all did not undo the staging.');
b = ctrl(app,'AnalysisSessionOnlyInterleaved');
assert(strcmp(b.Enable,'on') && strcmp(ctrl(app,'AnalysisSessionOnlyConventional').Enable,'on'), ...
    'Only conventional / Only interleaved are off on a session holding both.');
b.ButtonPushedFcn(b,[]);
assert(isequal(tb.Data.Use,~conv),'Only interleaved.');
b = ctrl(app,'AnalysisSessionSkipShort');
b.ButtonPushedFcn(b,[]);
short = logical(S.Files.Short(loc));
assert(isequal(tb.Data.Use,~short),'Skip short runs.');
dc.ButtonPushedFcn(dc,[]);
% the run-group context actions
cm = findall(app.Figure,'Tag','AnalysisSessionFilesMenu');
r = find(string(tb.Data.("Run group")) ~= "",1,'last');
grp = string(tb.Data.("Run group")(r));
mabr.ui.analysis.Compat.setSelectedRows(tb,r);
cm.ContextMenuOpeningFcn(cm,[]);
if ~isfinite(v.MenuRow)
    % (a release whose table has no Selection: the action itself)
    v.filesContextAction("excludeGroup",r);
else
    assert(v.MenuRow == r,'The context menu did not find its row.');
    it = findall(cm,'Tag','AnalysisSessionFilesExcludeGroup');
    it.MenuSelectedFcn(it,[]);
end
inGrp = string(tb.Data.("Run group")) == grp;
assert(isequal(tb.Data.Use,~inGrp),'Exclude this run group.');
dc.ButtonPushedFcn(dc,[]);
v.filesContextAction("useGroup",r);
assert(isequal(tb.Data.Use,inGrp),'Use only this run group.');
dc.ButtonPushedFcn(dc,[]);
txt = mabr.ui.analysis.FigureExport.copyTable(tb);
assert(startsWith(txt,"Use" + char(9) + "Run group"),'Copy table.');
% Apply re-segments (on the smaller Baseline session), then undo
kB = F.Keys(contains(F.Keys,"SUBJ-ID-1254_Baseline"));
m.openSession(kB);
S = m.Session;
% a session of conventional runs only: nothing to choose between, so the
% two "Only" buttons are off, saying why, and the Model refuses by name
bi = ctrl(app,'AnalysisSessionOnlyInterleaved');  bc = ctrl(app,'AnalysisSessionOnlyConventional');
assert(all(string(S.Files.AcqMode) == "conventional") && strcmp(bi.Enable,'off') && strcmp(bc.Enable,'off') && ...
    contains(string(bi.Tooltip),"no interleaved runs") && contains(string(bc.Tooltip),"is conventional"), ...
    'On a conventional-only session the Only buttons are %s/%s ("%s").',bc.Enable,bi.Enable,string(bi.Tooltip));
m.useOnly("interleaved");
assert(isempty(m.PendingFileUse.FileIds) && contains(m.LastMessage,"no interleaved runs"), ...
    'Only interleaved on a conventional-only session staged something (%s).',m.LastMessage);
id = v.FileIds(end);
D = tb.Data;
D.Use(end) = false;
tb.Data = D;
tb.CellEditCallback(tb,struct('Indices',[height(D) 1],'NewData',false,'PreviousData',true,'EditData',false));
rec = recordEvents(m);
ap.ButtonPushedFcn(ap,[]);
log = rec('log'); delete(rec('listeners'));
assert(any(log == "ResultsChanged(all)") && any(string(S.Exclude) == id),'Apply did not re-segment: %s', ...
    strjoin(log,' '));
assert(~tb.Data.Use(end) && isempty(m.PendingFileUse.FileIds) && string(pend.Text) == "", ...
    'After Apply the file is not shown as left out.');
assert(contains(string(ctrl(app,'AnalysisSessionFiles').Data.Note{end}),"excluded"), ...
    'The Note column does not say the file is excluded.');
m.undo();
assert(~any(string(S.Exclude) == id) && tb.Data.Use(end),'Undo did not bring the file back.');
fprintf(['  PASS Part G: files grouped by run, staged edit + pending line, Discard, Only conventional/' ...
    'interleaved, Use all, Skip short, run-group context actions, Copy table, Apply re-segments ' ...
    '(ResultsChanged all) and undo\n']);
end

% =========================================================================
%  Part H -- the overrides row (and the A9 conduction delay)
% =========================================================================
function partH_overrides(app,F)
m = app.Model;
kB = F.Keys(contains(F.Keys,"SUBJ-ID-1254_Baseline"));
if m.SessionKey ~= kB, m.openSession(kB); end
app.activateTab("Session");
fs = ctrl(app,'AnalysisSessionFullScale');
gn = ctrl(app,'AnalysisSessionGain');
to = ctrl(app,'AnalysisSessionTimeOffset');
cd = ctrl(app,'AnalysisSessionConductionDelay');
ab = ctrl(app,'AnalysisSessionApplyOverrides');
assert(all(arrayfun(@(h) string(h.Value) == "",[fs gn to cd])),'Overrides are not empty at first.');
% a sound conduction delay: peaks re-picked, still up to date
cd.Value = '0.3';
ab.ButtonPushedFcn(ab,[]);
assert(projectNum(m,kB,"ConductionDelayOverride") == 0.3 && abs(m.latencyOffset() - 0.3) < 1e-12, ...
    'The delay did not reach the project and the session (offset %g).',m.latencyOffset());
assert(all(abs(m.Session.Peaks.LatencyOffset - 0.3) < 1e-12) && m.Status.State == "current", ...
    'The delay did not re-pick the peaks (%s).',m.Status.Text);
assert(string(cd.Value) == "0.3",'The delay field does not show the stored delay.');
assert(any(contains(string(ctrl(app,'AnalysisSessionSummary').Value),"0.30 ms conduction delay")), ...
    'The summary does not name the delay.');
% a unit override: out of date (and the browser says so in place)
cd.Value = '';
fs.Value = '2';
ab.ButtonPushedFcn(ab,[]);
assert(projectNum(m,kB,"InputFullScaleOverride") == 2 && isnan(projectNum(m,kB,"ConductionDelayOverride")), ...
    'The full-scale override (and the cleared delay) did not reach the project.');
assert(m.Status.State == "stale" && m.Status.Text == "Out of date (overrides changed)", ...
    'A unit override did not make the session out of date (%s).',m.Status.Text);
n = nodeOf(ctrl(app,'AnalysisBrowserTree'),kB);
assert(startsWith(string(n.Text),mabr.ui.analysis.Style.GlyphStale + " "),'The browser node: %s',n.Text);
fs.Value = '';
ab.ButtonPushedFcn(ab,[]);
assert(m.Status.State == "current" && isnan(projectNum(m,kB,"InputFullScaleOverride")) && ...
    m.latencyOffset() == 0,'Clearing the overrides (%s).',m.Status.Text);
% a bad number is refused
gn.Value = 'abc';
ab.ButtonPushedFcn(ab,[]);
st = ctrl(app,'AnalysisStatusText');
assert(contains(string(st.Text),"not a number") && isnan(projectNum(m,kB,"AmplifierGainOverride")), ...
    'A bad number was not refused (%s).',st.Text);
% a value typed and never applied does not follow the user to another
% session (where Apply would store it), and coming back shows the stored one
gn.Value = '5';
k9 = F.Keys(contains(F.Keys,"SUBJ-ID-959_Baseline"));
m.openSession(k9);
assert(string(gn.Value) == "" && isnan(projectNum(m,k9,"AmplifierGainOverride")), ...
    'An unapplied gain stayed in the box for another session ("%s").',gn.Value);
m.openSession(kB);
assert(all(arrayfun(@(h) string(h.Value) == "",[fs gn to cd])), ...
    'Coming back did not show the session''s stored (empty) overrides.');
m.flush();
fprintf(['  PASS Part H: overrides row -- a 0.3 ms conduction delay (AnalysisSessionConductionDelay) ' ...
    're-picks the peaks and stays up to date; a full-scale override makes the session out of date ' ...
    '(browser node ◐); clearing restores; a bad number is refused; an unapplied number does not ' ...
    'follow to another session\n']);
end

% =========================================================================
%  Part I -- a nested results store
% =========================================================================
function partI_nested(app,F)
m = app.Model;
stores = [fullfile(F.Root,"SUBJ-ID-1254","MABR_Analysis"); fullfile(F.Root,"SUBJ-ID-959","MABR_Analysis")];
for s = reshape(stores,1,[])
    p = mabr.analysis.Project(s);
    p.save();
end
m.rescan();
bn = ctrl(app,'AnalysisBrowserBanner');
bt = ctrl(app,'AnalysisBrowserBannerText');
assert(strcmp(bn.Visible,'on') && startsWith(string(bt.Text),"Results found in SUBJ-ID-1254/MABR_Analysis (") && ...
    endsWith(string(bt.Text),"sessions)."),'The nested-store banner: "%s" (%s).',bt.Text,bn.Visible);
b = ctrl(app,'AnalysisBrowserBannerImport');
b.ButtonPushedFcn(b,[]);
assert(any(strcmpi(string(m.Project.ImportedStores),stores(1))),'Import did not import the store.');
assert(strcmp(bn.Visible,'on') && contains(string(bt.Text),"SUBJ-ID-959/MABR_Analysis"), ...
    'After Import the banner does not offer the next store ("%s").',bt.Text);
b = ctrl(app,'AnalysisBrowserBannerIgnore');
b.ButtonPushedFcn(b,[]);
assert(any(strcmpi(string(m.Project.IgnoredStores),stores(2))) && strcmp(bn.Visible,'off'), ...
    'Ignore did not dismiss the banner.');
m.flush();
fprintf('  PASS Part I: the nested-store banner names the store; Import imports it; Ignore dismisses the next\n');
end

% =========================================================================
%  Part J -- blind review
% =========================================================================
function partJ_blind(app,F)
m = app.Model;
m.startReviewQueue(F.Keys,UnreviewedOnly=false,Blind=true);
bl = ctrl(app,'AnalysisBrowserBlind');
t  = ctrl(app,'AnalysisBrowserTree');
txt = ctrl(app,'AnalysisBrowserBlindText');
assert(m.BlindReview && strcmp(bl.Visible,'on') && strcmp(t.Visible,'off') && ...
    strcmp(ctrl(app,'AnalysisBrowserDetails').Parent.Visible,'off'),'Blind review does not cover the tree.');
assert(string(txt.Text) == "Blind review — item 1 of " + numel(F.Keys),'Blind text: %s',txt.Text);
% the Session tab names nobody either: no file names or clock times, no
% notes, no folder or subject in the messages and the summary
app.activateTab("Session");
S = m.Session;
who = [S.Subject string(S.Name)];
D = ctrl(app,'AnalysisSessionFiles').Data;
sm = string(ctrl(app,'AnalysisSessionSummary').Value);
mt = string(ctrl(app,'AnalysisSessionMessages').Data.Text);
nt = string(ctrl(app,'AnalysisSessionNotes').Value);
assert(all(startsWith(string(D.File),"file ")) && all(string(D.Start) == "") && ...
    ~any(contains(string(D.("Run group")),":")),'Blind review shows file names or times in the Files table.');
assert(~any(contains([sm; mt; nt],who)),'Blind review shows the subject or the folder on the Session tab.');
assert(contains(nt(1),"hidden during blind review"),'Blind review shows the notes.');
m.nextInQueue(1);
assert(string(txt.Text) == "Blind review — item 2 of " + numel(F.Keys),'The blind text did not follow the queue.');
b = ctrl(app,'AnalysisBrowserBlindEnd');
b.ButtonPushedFcn(b,[]);
assert(~m.BlindReview && strcmp(bl.Visible,'off') && strcmp(t.Visible,'on'),'End review did not uncover the tree.');
m.flush();
D = ctrl(app,'AnalysisSessionFiles').Data;
assert(~all(startsWith(string(D.File),"file ")),'After the review the Files table still hides the names.');
fprintf(['  PASS Part J: blind review covers search, tree and details ("item k of n") and hides names, ' ...
    'times and notes on the Session tab; End review uncovers them\n']);
end

% =========================================================================
%  Part L -- exclude and hide
% =========================================================================
function partL_hide(app,F)
br = app.Browser;
m  = app.Model;
t  = ctrl(app,'AnalysisBrowserTree');
br.applyFilter("","All");
kB = F.Keys(contains(F.Keys,"SUBJ-ID-1254_Baseline"));
n0 = numel(br.VisibleKeys);
rawInStudy = @(k) logical(m.Project.Sessions.InStudy(m.Project.Sessions.Key == k));
% the context menu's item on a session that is shown
br.selectKeys(kB);
cm = findall(app.Figure,'Tag','AnalysisBrowserMenu');
cm.ContextMenuOpeningFcn(cm,struct());
it = findall(cm,'Tag','AnalysisBrowserMenuHide');
assert(strcmp(it.Text,'Exclude and hide') && strcmp(it.Enable,'on'),'The hide item on a shown session reads "%s".',it.Text);
it.MenuSelectedFcn(it,[]);
assert(m.Project.isHidden(kB) && ~labelOf(m,kB,"InStudy") && rawInStudy(kB), ...
    'Exclude and hide: Hidden, out of the study, its own In study label kept.');
assert(isempty(nodeOf(t,kB)) && numel(br.VisibleKeys) == n0 - 1 && ~any(m.BrowserOrder == kB), ...
    'A hidden session is still listed.');
assert(~any(m.allKeys() == kB) && ~any(m.Project.studyKeys() == kB), ...
    'A hidden session is in the "all" or the "in study" scope.');
assert(contains(m.LastMessage,"Hid 1 session") && contains(m.LastMessage,"Ctrl+Z"),'The status line: %s',m.LastMessage);
dt = string(ctrl(app,'AnalysisBrowserDetails').Value);
assert(any(dt == "1 session is hidden (Show ▸ Hidden lists them)."), ...
    'The details do not count the hidden session: %s',strjoin(dt,' | '));
% Show ▸ Hidden lists only it: In study greyed, the item reads Unhide
br.applyFilter("","Hidden");
assert(isequal(br.VisibleKeys,kB),'Show Hidden lists [%s], not only the hidden session.',strjoin(br.VisibleKeys,', '));
br.selectKeys(kB);
cb = ctrl(app,'AnalysisBrowserInStudy');
assert(strcmp(cb.Enable,'off') && ~cb.Value,'In study is not greyed (and clear) for a hidden session.');
dt = string(ctrl(app,'AnalysisBrowserDetails').Value);
assert(any(contains(dt,"hidden (not in study)")),'The details do not say the session is hidden: %s',strjoin(dt,' | '));
cm.ContextMenuOpeningFcn(cm,struct());
assert(strcmp(it.Text,'Unhide') && strcmp(findall(cm,'Tag','AnalysisBrowserMenuInStudy').Enable,'off'), ...
    'On a hidden session the item reads "%s" (and In study is not greyed).',it.Text);
it.MenuSelectedFcn(it,[]);
assert(~m.Project.isHidden(kB) && labelOf(m,kB,"InStudy") && isempty(br.VisibleKeys),'Unhide.');
br.applyFilter("","All");
assert(~isempty(nodeOf(t,kB)) && numel(br.VisibleKeys) == n0,'Unhidden, the session is not listed again.');
% Delete on a subject node hides its sessions, and the subject goes with them
t.SelectedNodes = t.Children(1);
t.SelectionChangedFcn(t,[]);
subj = string(t.Children(1).NodeData.Subject);
ks = br.selectedKeys();
assert(subj == "SUBJ-ID-959" && numel(ks) == 2,'Setup: the first subject is SUBJ-ID-959 with two sessions.');
m.FocusArea = "browser";
m.KeyTarget = "plot";
assert(app.dispatchKey(keyEvt('delete')),'Delete was not dispatched from the browser.');
m.FocusArea = "workspace";
names = string(arrayfun(@(n) string(n.NodeData.Subject),t.Children,'UniformOutput',false));
assert(all(m.Project.isHidden(ks)) && ~any(names == subj) && numel(br.VisibleKeys) == n0 - 2, ...
    'Delete on a subject did not hide its sessions (and the subject with them).');
assert(contains(m.LastMessage,"Hid 2 sessions"),'The status line: %s',m.LastMessage);
m.undo();
assert(~any(m.Project.isHidden(ks)) && numel(br.VisibleKeys) == n0,'Ctrl+Z did not bring the subject back.');
% the Session menu's two items
br.selectKeys(kB);
mi = ctrl(app,'AnalysisMenuHide');
mi.MenuSelectedFcn(mi,[]);
assert(m.Project.isHidden(kB),'Session ▸ Exclude and Hide Selected did not hide the selection.');
br.applyFilter("","Hidden");
br.selectKeys(kB);
mi = ctrl(app,'AnalysisMenuUnhide');
mi.MenuSelectedFcn(mi,[]);
assert(~m.Project.isHidden(kB),'Session ▸ Unhide Selected did not unhide the selection.');
br.applyFilter("","All");
m.undo(); m.undo();
assert(~m.Project.isHidden(kB) && numel(br.VisibleKeys) == n0,'Undoing the menu''s hide and unhide.');
fprintf(['  PASS Part L: exclude and hide (context menu, Delete on a subject, Session menu) takes sessions ' ...
    'out of the tree, the study and the all/in-study scopes with their In study kept; Show Hidden ' ...
    'lists only them, In study greyed, Unhide; Ctrl+Z\n']);
end

% =========================================================================
%  Helpers
% =========================================================================
function [app,stub] = newApp(F)
stub = newStub(F.ResultsFolder);
app = mabr.ui.AnalysisApp(F.Root,Visible="off",ResultsFolder=F.ResultsFolder, ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false, ...
    RememberState=false,ProgressMode="none",AutoRefresh=false, ...
    ConfirmFcn=stub.Confirm,PromptFcn=stub.Prompt,PickFolderFcn=stub.PickFolder, ...
    PickFileFcn=stub.PickFile,AlertFcn=stub.Alert);
end

function stub = newStub(work)
% Dialog stand-ins: they record what was asked and answer at once.
calls   = containers.Map('KeyType','char','ValueType','any');
answers = containers.Map('KeyType','char','ValueType','any');
calls('confirm') = strings(0,1);
calls('alert') = strings(0,1);
answers('folder') = "";
answers('prompt') = "Pool A";
stub.Calls   = calls;
stub.Answers = answers;
stub.Confirm    = @(msg,title,options,default) stubConfirm(calls,msg,title,options);
stub.Alert      = @(msg,title,icon) stubRecord(calls,'alert',string(title) + ": " + string(msg));
stub.Prompt     = @(prompt,title,default) answers('prompt');
stub.PickFolder = @(start,title) answers('folder');
stub.PickFile   = @(filter,title,mode,default) string(fullfile(work,"picked.dat"));
end

function c = stubConfirm(calls,msg,title,options)
stubRecord(calls,'confirm',string(msg) + " | " + string(title));
c = string(options(1));
end

function stubRecord(calls,key,text)
calls(key) = [calls(key); string(text)]; %#ok<NASGU> (a containers.Map)
end

function h = ctrl(app,tag)
h = findall(app.Figure,'Tag',tag);
assert(~isempty(h),'No control tagged %s.',tag);
h = h(1);
end

function n = nodeOf(t,key)
% The tree node of a session/pool key ([] when not listed).
n = [];
stack = t.Children(:);
while ~isempty(stack)
    x = stack(1);
    stack(1) = [];
    d = x.NodeData;
    if isstruct(d) && any(string(d.Type) == ["session","pool"]) && string(d.Key) == key
        n = x;
        return
    end
    stack = [stack; x.Children(:)]; %#ok<AGROW>
end
end

function e = keyEvt(key,varargin)
e = struct('Key',key,'Modifier',{varargin},'Character','');
if isscalar(key) && isempty(varargin), e.Character = key; end
end

function v = labelOf(m,key,name)
V = m.projectView();
v = V.(name)(string(V.Key) == key);
if isstring(v) || ischar(v) || iscellstr(v), v = string(v); end
end

function v = projectNum(m,key,name)
T = m.Project.Sessions;
v = double(T.(name)(string(T.Key) == key));
end

function rec = recordEvents(m)
% A recorder of the Model's events: rec('log') is "Name(What)" per event.
rec = containers.Map('KeyType','char','ValueType','any');
rec('log') = strings(0,1);
names = ["RootChanged","ProjectChanged","SessionChanged","ResultsChanged", ...
    "SelectionChanged","SettingsChanged","StatusChanged","BusyChanged"];
L = event.listener.empty;
for n = names
    L(end+1) = addlistener(m,char(n),@(~,e) logEvent(rec,n,e)); %#ok<AGROW>
end
rec('listeners') = L;
end

function logEvent(rec,n,e)
rec('log') = [rec('log'); n + "(" + e.What + ")"]; %#ok<NASGU>
end

function P = allPrefs()
P = struct();
try
    if ispref('MABR'), P = getpref('MABR'); end
catch
end
end

function names = changedPrefs(a,b)
fa = string(fieldnames(a));
fb = string(fieldnames(b));
names = strings(1,0);
for f = reshape(union(fa,fb),1,[])
    if ~startsWith(f,"Offline") && ~startsWith(f,"WindowPos_Offline"), continue; end
    inA = any(fa == f);  inB = any(fb == f);
    if inA ~= inB || (inA && ~isequaln(a.(f),b.(f)))
        names(end+1) = f; %#ok<AGROW>
    end
end
end

function tf = samePath(a,b)
na = lower(regexprep(char(string(a)),'[\\/]+$',''));
nb = lower(regexprep(char(string(b)),'[\\/]+$',''));
tf = strcmp(strrep(na,'/','\'),strrep(nb,'/','\'));
end

function closeQuietly(app)
try
    if ~isempty(app) && isvalid(app), delete(app); end
catch
end
end
