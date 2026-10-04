function verify_offline_app()
% verify_offline_app  The analysis app shell: Model, events, keys, autosave, undo, prefs, scans.
%
%   Checks mabr.ui.AnalysisApp and the shared parts of +mabr/+ui/+analysis
%   (Model, ChangeData, View, Commands, Compat, Style, FigureExport,
%   PromptDialog, NoteEditor) without a person at the keyboard: every window
%   is built invisible, every dialog a test would see is a stub
%   (ConfirmFcn/PromptFcn/PickFolderFcn/PickFileFcn), progress windows are
%   off (ProgressMode "none") and so are timers (AutoRefresh false), so a
%   test calls flush() where a person would wait.
%
%     Part A  Commands: one row per (scope, key, modifiers, char), lookup
%             priority, sheets and hints; every toolbar glyph is one
%             mabr.ui.Icon draws
%     Part B  ChangeData, Style, Compat
%     Part C  the View base (a probe subclass written to tempdir): build,
%             events into refresh only while active, put writes once,
%             renderGuarded runs a nested render after the outer one,
%             showEmpty/hideEmpty, the look persistence helpers
%     Part D  the window with no folder: Start panel, tabs built lazily,
%             each into its own view class (AnalysisApp.viewClass: the
%             Trials tab is TrialView) with no "View not available yet", F1,
%             key routing (letters ignored while a text control has the
%             keyboard, Ctrl chords always), reuse of the open window
%     Part E  a folder (mabrtest.OfflineFixture): opening a subject folder
%             offers the study folder; browsing writes nothing under the
%             data; the events of openRoot, openSession, ensureRaw, analyze,
%             a curation command, a label edit and undo, in 11 sec. 2.3 order
%     Part F  every Mutating command is undoable (run it, undo it, the
%             session's editSnapshot is back where it was)
%     Part G  keys with a session: the note editor swallows typing, Esc
%             closes it, x opens it; the browser area keeps letters
%     Part H  autosave writes the results file; a file changed elsewhere is
%             a conflict and is not overwritten; an unwritable results
%             folder makes the Model read-only; an unreadable results file
%             opens its session from the raw files (kept in .history); an
%             unreadable project.mat is read-only with its reason and is
%             not retried; a read-only store's export refuses naming it
%     Part I  the busy guard, cancelling a job (nothing changed); last of
%             all (I2), closing the test's window while busy: it goes once
%             the job unwinds, printing nothing
%     Part J  blind review titles; the acquisition guard
%     Part K  prefs: a script-driven run writes none; the user's own
%             callbacks write theirs; the last state is restored
%     Part L  exports: a figure, a prompt, an analysis script (when
%             mabr.analysis.ScriptWriter exists), tables
%     Part M  static scans: no post-R2021b UI identifier outside Compat.m
%             (Compat.setPlaceholder is the helper, not a use),
%             no Statistics Toolbox function, and requiredFilesAndProducts
%             lists neither Statistics nor Curve Fitting
%     Part N  the sound conduction delay (13 A9): a per-session override
%             through setSessionOverrides reaches the project and the
%             Session, re-picks its peaks recording the new offset (no pick
%             moves: the waves are searched in the recording's time), keeps
%             the session up to date, and the views' time axis reads "re
%             sound arrival" with the delay named; clearing it goes back to
%             onset
%
%   No hardware, no parallel pool, no modal dialog; tempdir only; every
%   pref restored (mabrtest.prefGuard).
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.Model, mabrtest.OfflineFixture
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_app ==\n');
tAll  = tic;
figs0 = findall(groot,'Type','figure');
keys  = [mabr.ui.AnalysisApp.prefKeys(),"OfflineAnalysisProbe"];
guard = mabrtest.prefGuard(keys); %#ok<NASGU>
work  = string(tempname);
mkdir(work);
cleanWork = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(work));
setpref('MABR','OfflineAnalysisRestore',true);   % (guarded) Part K restores the last state

took = strings(1,0);
lap = tic;
partA_commands();
partB_shared();
partC_view(work);                 % writes the probe's own look pref, by design
prefs0 = allPrefs();
took(end+1) = sprintf("A-C %.1f",toc(lap));

modelReady = exist('mabr.analysis.Batch','class') == 8 && exist('mabr.analysis.Project','class') == 8;
if modelReady
    lap = tic;
    F = mabrtest.OfflineFixture.make();
    fprintf('  (fixture: %d sessions analysed in %.1f s so far)\n',numel(F.Keys),toc(tAll));
    [app,stub] = newApp(F,"");
    closer = mabrtest.OfflineFixture.closer(app,F); %#ok<NASGU> (the app, THEN the fixture's folders)
    took(end+1) = sprintf("fixture %.1f",toc(lap));
    % (Part D on the same window, before it opens a folder: one window and
    % one set of views fewer to build than a window of its own)
    parts = {@() partD_shell(work,app), @() partE_events(app,stub,F), @() partF_undoable(app), ...
        @() partG_keys(app), @() partH_autosave(app,F,work), @() partI_jobs(app,F), ...
        @() partJ_review(app,F), @() partN_latency(app,F)};
    names = ["D","E","F","G","H","I","J","N"];
    for p = 1:numel(parts)
        lap = tic;
        parts{p}();
        took(end+1) = sprintf("%s %.1f",names(p),toc(lap)); %#ok<AGROW>
    end
    assert(isempty(changedPrefs(prefs0,allPrefs())), ...
        'A script-driven run of the analysis app wrote a MABR pref: %s', ...
        strjoin(changedPrefs(prefs0,allPrefs()),', '));
    fprintf('  PASS Part K1: a script-driven run (open, analyse, curate, undo, save) writes no pref\n');
    lap = tic;
    partK_prefs(F);
    took(end+1) = sprintf("K %.1f",toc(lap));
    lap = tic;
    partL_exports(app,F,work);
    took(end+1) = sprintf("L %.1f",toc(lap));
    lap = tic;
    partI2_closeWhileBusy(app);
    took(end+1) = sprintf("I2 %.1f",toc(lap));
    clear closer
else
    fprintf('  SKIP Parts E-L: mabr.analysis.Batch/Project are not in this MABR yet\n');
    partD_shell(work,[]);
    partL_figure(work);
end

lap = tic;
partM_scans();
took(end+1) = sprintf("M %.1f",toc(lap));
fprintf('  (seconds per part: %s)\n',strjoin(took,', '));

% ---- leaks ------------------------------------------------------------
drawnow;
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_app left a figure open (%s).', ...
    strjoin(string(get(setdiff(figs1,figs0),'Name')),', '));
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_app PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Part A -- the keymap
% =========================================================================
function partA_commands()
T = mabr.ui.analysis.Commands.spec();
need = ["Id","Key","Modifiers","Char","Scope","Target","Mutating","Label","Short","MenuTag"];
assert(all(ismember(need,string(T.Properties.VariableNames))),'Commands.spec lacks columns.');
sig = T.Scope + "|" + T.Key + "|" + T.Modifiers + "|" + T.Char;
sig = sig(T.Key + T.Char ~= "");
[u,~,j] = unique(sig);
dup = u(accumarray(j,1) > 1);
assert(isempty(dup),'Two Commands rows share scope/key/modifiers/char: %s',strjoin(dup,', '));
assert(all(ismember(T.Scope,["global","browser","session","grid","series","trials","study"])), ...
    'A Commands row has an unknown scope.');
assert(all(ismember(T.Target,["app","model","view"])),'A Commands row has an unknown target.');
% no unmodified letter means one command on one tab and another elsewhere
L = T(T.Modifiers == "" & strlength(T.Key) == 1 & T.Key >= "a" & T.Key <= "z",:);
for k = unique(L.Key).'
    ids = unique(L.Id(L.Key == k));
    assert(isscalar(ids),'The key "%s" runs different commands on different tabs (%s).',k,strjoin(ids,', '));
end
% the commands the spec names, with their keys
look = @(k,m,c,s) mabr.ui.analysis.Commands.lookup(k,m,c,s);
assert(look("o","control",'o',["series","global"]) == "file.open",'Ctrl+O is not file.open.');
assert(look("z","control",'',["grid","global"]) == "edit.undo",'Ctrl+Z is not undo.');
assert(look("y","control",'',["grid","global"]) == "edit.redo" && ...
    look("z",{'shift','control'},'',["grid","global"]) == "edit.redo",'Ctrl+Y / Ctrl+Shift+Z are not redo.');
assert(look("i","",'i',["series","global"]) == "thr.noResponse" && ...
    look("i","",'i',["grid","global"]) == "thr.noResponse",'"i" is not no response on Grid and Series.');
assert(look("n","",'n',["series","global"]) == "view.normalize" && ...
    look("n","control",'',["series","global"]) == "edit.note",'n / Ctrl+N are not normalise / note.');
assert(look("leftarrow","",'',["series","global"]) == "series.left" && ...
    look("leftarrow","",'',["grid","global"]) == "nav.seriesPrev",'Left is not scoped per tab.');
assert(look("leftarrow","alt",'',["series","global"]) == "peak.nudgeLeft" && ...
    look("leftarrow","shift",'',["series","global"]) == "peak.nudgeLeft",'Alt/Shift+Left do not nudge.');
assert(look("1","shift",'!',["series","global"]) == "peak.trough1",'Shift+1 is not the wave I trough.');
assert(look("equal","shift",'+',["grid","global"]) == "view.scaleUp" && ...
    look("","",'+',["trials","global"]) == "view.scaleUp",'+ does not scale up.');
assert(look("return","",'',["browser","global"]) == "browser.open" && ...
    look("return","",'',["grid","global"]) == "nav.openSeries" && ...
    look("return","control",'',["grid","global"]) == "session.analyse",'Return is not scoped.');
assert(look("q","",'q',["series","global"]) == "",'An unbound key found a command.');
assert(look("a","",'a',["trials","global"]) == "",'"a" leaked into the Trials tab.');
% every Mutating command is one the Model undoes (Part F runs each)
mut = unique(T.Id(T.Mutating));
want = ["thr.accept","thr.atLevel","thr.noResponse","thr.allRespond","thr.exclude","thr.clear", ...
    "thr.override","peak.autoPick","peak.retrack","peak.retrackOverwrite","peak.nudgeLeft", ...
    "peak.nudgeRight","peak.absent","peak.absentBelow","peak.revert","trials.reject","trials.restore"];
assert(isempty(setxor(mut,want)),'The Mutating commands changed: %s',strjoin(setxor(mut,want),', '));
S = mabr.ui.analysis.Commands.sheet(["global","series"]);
assert(height(S) > 20 && all(S.Keys ~= ""),'Commands.sheet is short or has keyless rows.');
h = mabr.ui.analysis.Commands.hint("series");
assert(contains(h,"a accept") && endsWith(h,"F1 all keys"),'Commands.hint("series") is not the strip.');
assert(mabr.ui.analysis.Commands.keyText("edit.redo") == "Ctrl+Y or Ctrl+Shift+Z",'keyText of redo.');
assert(mabr.ui.analysis.Commands.keyText("file.exportScript") == "",'file.exportScript has a key.');
fprintf('  PASS Part A1: Commands -- %d rows, unique per scope/key, lookup and scopes as specified\n',height(T));

% every toolbar glyph (and every button glyph) the GUI files ask for exists
glyphs = requestedGlyphs();
have = string(mabr.ui.Icon.names());
missing = setdiff(glyphs,have);
newA6 = ["gear","export","script","batch","accept","noresponse","exclude","threshold","retrack", ...
    "reject","restore","undo","redo","study","raster","pool","copy","figure"];
assert(all(ismember(missing,newA6)),'Glyphs asked for that are not in mabr.ui.Icon: %s',strjoin(missing,', '));
if isempty(missing)
    fprintf('  PASS Part A2: all %d glyphs the analysis app asks for are drawn by mabr.ui.Icon\n',numel(glyphs));
else
    fprintf('  SKIP Part A2: glyphs not drawn yet (unit U15): %s\n',strjoin(missing,', '));
end
end

function g = requestedGlyphs()
% The glyphs AnalysisApp.m and +mabr/+ui/+analysis/*.m name (verify_icons' regexes).
files = [string(which('mabr.ui.AnalysisApp')); analysisGuiFiles()];
g = strings(0,1);
for f = reshape(files,1,[])
    s = fileread(f);
    t = regexp(s,'(?:toolButton|Icon\.toolbar)\(\s*''([A-Za-z]+)''','tokens');
    t = [t regexp(s,'setButtonIcon\(\s*[A-Za-z_.]+\s*,\s*''([A-Za-z]+)''','tokens')]; %#ok<AGROW>
    for k = 1:numel(t), g(end+1,1) = string(t{k}{1}); end %#ok<AGROW>
end
g = unique(g);
end

% =========================================================================
%  Part B -- ChangeData, Style, Compat
% =========================================================================
function partB_shared()
d = mabr.ui.analysis.ChangeData("curation",Keys=["a";"b"],Text="hi",Level=1,Source="acceptFit");
assert(d.What == "curation" && isequal(d.Keys,["a";"b"]) && d.Level == 1 && d.Origin == "acceptFit", ...
    'ChangeData fields.');
assert(isempty(mabr.ui.analysis.ChangeData().Keys),'ChangeData() Keys are not empty.');
threw = false;
try
    mabr.ui.analysis.ChangeData("everything");
catch me
    threw = strcmp(me.identifier,'mabr:ui:analysis:ChangeData:badWhat');
end
assert(threw,'ChangeData accepted a word outside its vocabulary.');

St = mabr.ui.analysis.Style;
row = struct('Final',35,'FinalCensored',"interval",'FinalLo',30,'FinalHi',40);
assert(St.formatThreshold(row) == "35 (30–40]",'formatThreshold of an interval: %s',St.formatThreshold(row));
row = struct('Final',Inf,'FinalCensored',"right",'FinalLo',80,'FinalHi',NaN);
assert(St.formatThreshold(row) == ">80",'formatThreshold of a right-censored row.');
assert(St.formatThreshold([]) == "n/a",'formatThreshold of nothing.');
assert(St.formatUV(3.41e-6) == "3.41 µV" && St.formatMs(2.584) == "2.58 ms" && St.formatUV(NaN) == "–" && ...
    St.formatUV(1e-3) == "1000 µV",'formatUV/formatMs.');
c = St.colorFor(1:12,12);
assert(isequal(size(c),[12 3]) && isequal(c(1,:),St.OkabeIto(1,:)) && size(unique(c,'rows'),1) == 12, ...
    'colorFor does not give 12 distinct colours starting with Okabe-Ito.');
assert(St.decisionGlyph("accepted") == "✓" && St.decisionGlyph("","fit changed") == "⚑" && ...
    St.decisionGlyph("") == "" && St.statusGlyph("stale") == "◐",'Style glyphs.');
f = uifigure('Visible','off');
cl = onCleanup(@() delete(f));
b = uibutton(f,'Text','Keep me');
assert(~St.setButtonIcon(b,'nosuchglyphatall','left') && b.Text == "Keep me", ...
    'setButtonIcon with an unknown glyph did more than keep the text.');
assert(St.setButtonIcon(b,'save','left') && ~isempty(b.Icon),'setButtonIcon did not set a known glyph.');

Cp = mabr.ui.analysis.Compat;
e1 = uieditfield(f);  e2 = uieditfield(f,'numeric');  ta = uitextarea(f);
dd = uidropdown(f,'Items',{'a','b'});  de = uidropdown(f,'Items',{'a','b'},'Editable','on');
assert(Cp.isTextComponent(e1) && Cp.isTextComponent(e2) && Cp.isTextComponent(ta) && ...
    Cp.isTextComponent(de) && ~Cp.isTextComponent(dd) && ~Cp.isTextComponent(b) && ...
    ~Cp.isTextComponent([]),'Compat.isTextComponent.');
assert(isequal(Cp.selectedRows([],struct('Indices',[3 1; 2 2; 3 2])),[2 3]),'Compat.selectedRows from Indices.');
% whole-row selection round trip: a row table's Selection is a 1-by-N row
% (a column errors), and every selected row comes back, not just the first
tr = uitable(f,'Data',table((1:5)',(11:15)'));
Cp.enableRowSelection(tr,@(s,e) []);
Cp.setSelectedRows(tr,[4;2]);
assert(isequal(Cp.selectedRows(tr,[]),[2 4]),'Compat row selection round trip: %s', ...
    mat2str(Cp.selectedRows(tr,[])));
tcell = uitable(f,'Data',table((1:5)',(11:15)'));
Cp.setSelectedRows(tcell,[5 3]);
assert(isequal(Cp.selectedRows(tcell,[]),[3 5]),'Compat cell selection round trip.');
Cp.setSelectedRows(tr,[]);
assert(isempty(Cp.selectedRows(tr,[])),'Compat setSelectedRows([]) did not clear the selection.');
assert(isempty(Cp.hitObject(f,struct('HitObject',[]))),'Compat.hitObject from a struct.');
Cp.setPlaceholder(e1,'type here');
t = uitable(f,'Data',table((1:3)'));
Cp.setSortable(t,false);
Cp.setColorLimits(axes(uipanel(f)),[-1 1]);
assert(Cp.tryFocus([]) == false,'tryFocus of nothing.');
fprintf('  PASS Part B: ChangeData, Style (formats, glyphs, colours, button icons), Compat helpers\n');
end

% =========================================================================
%  Part C -- the View base
% =========================================================================
function partC_view(work)
pkg = fullfile(work,'probe');
mkdir(fullfile(pkg,'+u6probe'));
writeProbeClasses(fullfile(pkg,'+u6probe'));
addpath(char(pkg));
cp = onCleanup(@() rmpath(char(pkg)));

m = mabr.ui.analysis.Model('AutoRefresh',false,'Interactive',false);
f = uifigure('Visible','off');
cf = onCleanup(@() delete(f));
tg = uitabgroup(f);
tab = uitab(tg,'Title','Probe');
v = u6probe.ProbeView(tab,m,[]);
assert(v.Built && v.Builds == 1 && ~v.IsActive && v.Dirty,'A new view is built once, inactive and dirty.');
assert(v.ViewName == "Probe" && v.ViewPrefKey == "OfflineAnalysisProbe",'ViewName/ViewPrefKey from the class name.');
% events while inactive only mark it dirty; activate catches up once
m.selectWave("II","P");
assert(isempty(v.Calls),'An inactive view refreshed on an event.');
v.activate();
assert(isequal(v.Calls,"all") && ~v.Dirty,'activate() did not refresh a dirty view once with "all".');
m.selectWave("III","N");
assert(isequal(v.Calls(end),"wave") && v.ViewEvent == "SelectionChanged",'An active view did not get What="wave".');
v.deactivate();
n0 = numel(v.Calls);
m.clearWave();
assert(numel(v.Calls) == n0 && v.Dirty,'A deactivated view refreshed.');
v.flush();
assert(numel(v.Calls) == n0,'flush() refreshed an inactive view.');
% status chatter (a message, an autosave) is not missed work for a hidden
% view, and a showing view still hears it
v.activate();
v.deactivate();
m.undo();                                        % "Nothing to undo." -- StatusChanged(message)
assert(~v.Dirty,'A status message made a hidden view dirty.');
v.activate();
m.undo();
assert(v.Calls(end) == "message",'A showing view did not hear a status message.');
% a settings change that re-fits is drawn once: the ResultsChanged its own
% call raises right after SettingsChanged(all) is passed over (the Model
% re-fits first); one from another call, or after another event, is not
chg = @(w,src) mabr.ui.analysis.ChangeData(w,Source=src);
n0 = numel(v.Calls);
v.onModelEvent("SettingsChanged",chg("all","setSettings"));
v.onModelEvent("ResultsChanged",chg("thresholds","setSettings"));
assert(isequal(v.Calls(n0+1:end),"all"),'A re-fitting settings change drew %d times (%s).', ...
    numel(v.Calls) - n0,strjoin(v.Calls(n0+1:end),', '));
v.onModelEvent("ResultsChanged",chg("thresholds","setSettings"));
v.onModelEvent("SettingsChanged",chg("all","openRoot"));
v.onModelEvent("ResultsChanged",chg("thresholds","acceptFit"));
v.onModelEvent("SettingsChanged",chg("all","setSettings"));
v.onModelEvent("StatusChanged",chg("status","setSettings"));
v.onModelEvent("ResultsChanged",chg("thresholds","setSettings"));
assert(isequal(v.Calls(n0+2:end),["thresholds";"all";"thresholds";"all";"status";"thresholds"]), ...
    'Events that are not one re-fitting call were coalesced: %s',strjoin(v.Calls(n0+2:end),', '));
v.deactivate();
% put writes only on change
c = u6probe.Counter();
v.callPut('k',c,'Value',3);
v.callPut('k',c,'Value',3);
v.callPut('k',c,'Value',4);
assert(c.Count == 2 && c.Value == 4,'put() wrote %d times for two different values.',c.Count);
v.callForget('k');
v.callPut('k',c,'Value',4);
assert(c.Count == 3,'put() after forgetWritten did not write.');
% renderGuarded: a render asked for during a render runs after it, once
v.Inner = 0;
v.callRender(@() v.nested());
assert(v.Inner == 2 && ~v.Rendering && ~v.RenderPending,'renderGuarded did not run the nested render once after.');
% showEmpty / hideEmpty
hit = containers.Map('KeyType','char','ValueType','double');
hit('n') = 0;
v.callShowEmpty("Open a session from the browser (double-click, Enter, or Open).", ...
    struct('Text',{"Open…","Help"},'Fcn',{@() bump(hit),@() []},'Glyph',{"load",""}));
lab = findall(f,'Tag','AnalysisProbeEmpty');
b1 = findall(f,'Tag','AnalysisProbeEmptyAction1');
b2 = findall(f,'Tag','AnalysisProbeEmptyAction2');
assert(isscalar(lab) && startsWith(string(lab.Text),"Open a session") && v.callIsEmptyShown(), ...
    'showEmpty did not show its text.');
assert(strcmp(b1.Visible,'on') && strcmp(b2.Visible,'on') && b1.Text == "Open…",'showEmpty buttons.');
b1.ButtonPushedFcn(b1,[]);
assert(hit('n') == 1,'An empty-state button did not run its action.');
assert(~isempty(b1.Icon) && isempty(b2.Icon),'The empty-state buttons do not carry their glyphs.');
v.callShowEmpty("Something else.",struct('Text',"Retry",'Fcn',@() []));
assert(isempty(b1.Icon) && b1.Text == "Retry",'An empty-state button kept the last action''s picture.');
v.callShowEmpty("Only one level was recorded — no threshold can be estimated.",[]);
assert(strcmp(b1.Visible,'off') && strcmp(b2.Visible,'off'),'showEmpty without actions left buttons up.');
v.callHideEmpty();
assert(~v.callIsEmptyShown(),'hideEmpty did not lift the overlay.');
% look persistence: forgiving read, write from savePrefs only
setpref('MABR','OfflineAnalysisProbe',struct('Scale',2.5,'Mode',7,'Junk',1));
d = u6probe.ProbeView.loadDefaults();
assert(d.Scale == 2.5 && d.Mode == "auto" && ~isfield(d,'Junk'),'loadLook was not forgiving.');
setpref('MABR','OfflineAnalysisProbe',42);
d = u6probe.ProbeView.loadDefaults();
assert(isequal(d,u6probe.ProbeView.factoryDefaults()),'loadLook of a junk pref is not the factory look.');
v.applySettings(struct('Scale',3,'Nope',1));
assert(v.displaySettings().Scale == 3 && ~isfield(v.displaySettings(),'Nope'),'applySettings.');
v.savePrefs();
assert(getpref('MABR','OfflineAnalysisProbe').Scale == 3,'savePrefs did not write the look.');
% the time-axis helper every view draws its time axis through (no session: onset)
ax = axes(uipanel(f));
T = v.labelTimeAxis(ax,Subtitle=true);
assert(T.Label == "Time re onset (ms)" && string(ax.XLabel.String) == "Time re onset (ms)" && ...
    v.earTime(2.5) == 2.5 && v.rawTime(2.5) == 2.5,'The View time-axis helpers with no session.');
% delete takes the listeners with it
delete(v);
m.selectWave("I","P");
delete(m);
fprintf(['  PASS Part C: View base -- lazy build, events into refresh only while active, ' ...
    'put on change, nested render, empty states, look persistence\n']);
end

function bump(h)
h('n') = h('n') + 1; %#ok<NASGU> (a containers.Map: a handle)
end

function writeProbeClasses(folder)
probe = {
'classdef ProbeView < mabr.ui.analysis.View'
'    % A View for verify_offline_app (written to tempdir by the test).'
'    properties'
'        Calls = strings(0,1)'
'        Builds = 0'
'        Inner = 0'
'    end'
'    methods'
'        function build(obj)'
'            obj.Builds = obj.Builds + 1;'
'            g = uigridlayout(obj.Parent,[1 1]);'
'            obj.Handles.Label = uilabel(g,''Text'',''probe'',''Tag'',''AnalysisProbeLabel'');'
'        end'
'        function refresh(obj,what,~)'
'            obj.Calls(end+1,1) = string(what);'
'        end'
'        function callPut(obj,key,h,prop,v), obj.put(key,h,prop,v); end'
'        function callForget(obj,p), obj.forgetWritten(p); end'
'        function callShowEmpty(obj,t,a), obj.showEmpty(t,a); end'
'        function callHideEmpty(obj), obj.hideEmpty(); end'
'        function tf = callIsEmptyShown(obj), tf = obj.isEmptyShown(); end'
'        function callRender(obj,f), obj.renderGuarded(f); end'
'        function nested(obj)'
'            obj.Inner = obj.Inner + 1;'
'            if obj.Inner == 1, obj.renderGuarded(@() obj.nested()); end'
'        end'
'    end'
'    methods (Static)'
'        function d = factoryDefaults(), d = struct(''Scale'',1,''Mode'',"auto"); end'
'        function d = loadDefaults()'
'            d = mabr.ui.analysis.View.loadLook("OfflineAnalysisProbe",u6probe.ProbeView.factoryDefaults());'
'        end'
'        function saveDefaults(d), mabr.ui.analysis.View.saveLook("OfflineAnalysisProbe",d); end'
'    end'
'end'};
counter = {
'classdef Counter < handle'
'    % Counts the writes to Value (verify_offline_app).'
'    properties'
'        Count = 0'
'    end'
'    properties (Dependent)'
'        Value'
'    end'
'    properties (Access = private)'
'        V = []'
'    end'
'    methods'
'        function set.Value(obj,v), obj.Count = obj.Count + 1; obj.V = v; end'
'        function v = get.Value(obj), v = obj.V; end'
'    end'
'end'};
writeText(fullfile(folder,'ProbeView.m'),string(probe)); %#ok<STRCLQT>
writeText(fullfile(folder,'Counter.m'),string(counter)); %#ok<STRCLQT>
end

% =========================================================================
%  Part D -- the window with no folder
% =========================================================================
function partD_shell(work,app)
% APP: the test's main window before it opens a folder (it is left open,
% on the Session tab); [] builds one of its own and closes it.
own = isempty(app);
if own
    stub = newStub(work);
    app = mabr.ui.AnalysisApp("",Visible="off",Restore=false,RememberState=false, ...
        ProgressMode="none",AutoRefresh=false,ConfirmFcn=stub.Confirm,PromptFcn=stub.Prompt, ...
        PickFolderFcn=stub.PickFolder,PickFileFcn=stub.PickFile,AlertFcn=stub.Alert);
    closer = onCleanup(@() closeQuietly(app));
end
f = app.Figure;
assert(isvalid(f) && f.Tag == "MABR_OFFLINE_ANALYSIS" && getappdata(f,'AnalysisApp') == app, ...
    'The window is not tagged / registered.');
assert(isequal(mabr.ui.AnalysisApp.findOpen(),app),'findOpen does not find the app.');
same = mabr.ui.AnalysisApp("",Instance="reuse");
assert(isequal(same,app),'Instance "reuse" built a second window.');
sp = findall(f,'Tag','AnalysisStartPanel');
assert(strcmp(sp.Visible,'on'),'The Start panel is not up with no folder open.');
for tag = ["AnalysisStartOpen","AnalysisStartRecent","AnalysisStartHint","AnalysisTabs", ...
        "AnalysisTabSession","AnalysisTabGrid","AnalysisTabSeries","AnalysisTabTrials", ...
        "AnalysisTabStudy","AnalysisHeaderTitle","AnalysisHeaderStatus","AnalysisHeaderProfile", ...
        "AnalysisHeaderReviewed","AnalysisHeaderSaved","AnalysisHeaderAnalyze","AnalysisHeaderBar", ...
        "AnalysisNoteEditor","AnalysisStatusText","AnalysisMenuOpen","AnalysisMenuRecent", ...
        "AnalysisMenuRescan","AnalysisMenuSave","AnalysisMenuExport","AnalysisMenuExportAgain", ...
        "AnalysisMenuExportFigure","AnalysisMenuExportScript","AnalysisMenuClose","AnalysisMenuUndo", ...
        "AnalysisMenuRedo","AnalysisMenuNote","AnalysisMenuRevertSeries","AnalysisMenuClearEdits", ...
        "AnalysisMenuOpenSession","AnalysisMenuPrevSession","AnalysisMenuNextSession", ...
        "AnalysisMenuAnalyse","AnalysisMenuPool","AnalysisMenuUnpool","AnalysisMenuReview", ...
        "AnalysisMenuEndReview","AnalysisMenuNextReview","AnalysisMenuPrevReview","AnalysisMenuBatch", ...
        "AnalysisMenuBatchReport","AnalysisMenuTabSession","AnalysisMenuTabStudy","AnalysisMenuBrowser", ...
        "AnalysisMenuFind","AnalysisMenuSettings","AnalysisMenuProfile","AnalysisMenuResultsFolder", ...
        "AnalysisMenuAnalyst","AnalysisMenuRestore","AnalysisMenuKeys","AnalysisMenuGuide", ...
        "AnalysisMenuMethods","AnalysisMenuLog","AnalysisMenuTests"]
    assert(~isempty(findall(f,'Tag',char(tag))),'No control tagged %s.',tag);
end
assert(numel(app.ToolGlyphs) == 18 && all(ismember(["load","play","export","script","figure", ...
    "undo","redo","traces","peaks","raster","study","gear","keys","help"],app.ToolGlyphs)), ...
    'The toolbar does not carry the A6 icon map.');
m = app.Model;
% tabs build lazily, each its own view class (the Trials tab is TrialView,
% not "Trials" + "View"); every view exists now, so no tab may say "View
% not available yet"
assert(isempty(app.Views.Trials) && isempty(app.Views.Study),'A tab built its view before it was shown.');
app.activateTab("Trials");
assert(app.ActiveTab == "Trials" && m.KeyTarget == "plot" && m.FocusArea == "workspace", ...
    'activateTab did not switch and hand the keyboard to the plots.');
want = ["mabr.ui.analysis.SessionView","mabr.ui.analysis.GridView","mabr.ui.analysis.SeriesView", ...
    "mabr.ui.analysis.TrialView","mabr.ui.analysis.StudyView"];
for k = 1:numel(app.TabNames)
    n = app.TabNames(k);
    assert(mabr.ui.AnalysisApp.viewClass(n) == want(k),'The %s tab maps to %s.',n,mabr.ui.AnalysisApp.viewClass(n));
    assert(exist(want(k),'class') == 8,'%s does not exist.',want(k));
    app.activateTab(n);
    v = app.Views.(n);
    assert(~isempty(v) && isvalid(v) && isa(v,want(k)) && v.IsActive, ...
        'The %s tab did not build its %s (%s).',n,want(k),class(v));
end
un = findall(f,'-regexp','Tag','^Analysis\w+Unavailable(Text)?$');
if ~isempty(un)
    error('verify:offline:app','A tab says its view is not available: %s',strjoin(string({un.Tag}),', '));
end
lab = findall(f,'Type','uilabel');
for h = reshape(lab,1,[])
    assert(~startsWith(strjoin(string(h.Text)," "),"View not available"), ...
        'A label (%s) still says "View not available yet".',h.Tag);
end
app.activateTab("Trials");
% keys: letters do nothing while a text control has the keyboard; chords do
m.KeyTarget = "ui";
assert(~app.dispatchKey(keyEvt('a')) && ~app.dispatchKey(keyEvt('f')),'A letter ran with KeyTarget "ui".');
assert(app.dispatchKey(keyEvt('3','control')) && app.ActiveTab == "Series",'Ctrl+3 did not switch tabs.');
m.KeyTarget = "ui";
assert(app.dispatchKey(keyEvt('1','control')) && app.ActiveTab == "Session",'Ctrl+1 with KeyTarget "ui".');
assert(~app.dispatchKey(keyEvt('shift','shift')),'A bare modifier ran something.');
% F1
assert(app.dispatchKey(keyEvt('f1')),'F1 was not handled.');
kw = findall(groot,'Tag','MABR_OFFLINE_KEYS');
assert(isscalar(kw),'F1 did not open the shortcuts window.');
kt = findall(kw,'Tag','AnalysisKeysTable');
assert(height(kt.Data) > 20 && any(kt.Data.Keys == "Ctrl+O"),'The shortcuts window does not list the keys.');
app.showShortcuts();
assert(isscalar(findall(groot,'Tag','MABR_OFFLINE_KEYS')),'F1 twice opened two windows.');
% the cb wrapper: errors reach the status line, the keyboard returns to the plots
cbf = app.cb(@(~,~) error('mabr:ui:analysis:busy','x'));
cbf(f,[]);
st = findall(f,'Tag','AnalysisStatusText');
assert(startsWith(string(st.Text),"Busy"),'The busy error did not say "Busy — try again ...".');
cbf = app.cb(@(~,~) error('verify:boom','Something broke'));
cbf(f,[]);
assert(string(st.Text) == "Something broke" && m.KeyTarget == "plot",'cb() error / keyboard handling.');
app.setStatus("hello",1);
assert(string(st.Text) == "hello" && isequal(st.FontColor,mabr.ui.analysis.Style.Warn),'setStatus.');
% dialogs that do not exist yet say so; FigureExport needs a plot
if exist('mabr.ui.analysis.LevelsDialog','class') ~= 8
    d = app.openDialog("levels");
    assert(isempty(d) && contains(string(st.Text),"not available yet"),'A missing dialog did not say so.');
end
app.openDialog("figureExport");
assert(contains(string(st.Text),"no plot"),'Export figure with nothing plotted.');
assert(isempty(m.Catalog) && m.sessionTitle() == "" && m.Status.State == "none",'A fresh Model is not empty.');
% with no folder ever opened, the Recent folders list says so (muted) rather
% than standing as an empty white box (the prefs are cleared by the guard)
lb = findall(f,'Tag','AnalysisStartRecent');
rr = strings(0,1);                      % (getpref with a default would CREATE the pref)
if ispref('MABR','OfflineRecentRoots'), rr = string(getpref('MABR','OfflineRecentRoots')); end
rr = rr(rr ~= "" & ~ismissing(rr));
if isempty(rr)
    assert(strcmp(lb.Enable,'off') && contains(strjoin(string(lb.Items)),"No recent folders yet"), ...
        'The empty Recent folders list is a blank box.');
end
if own
    clear closer
    closeQuietly(app);
    assert(~isvalid(app) && isempty(findall(groot,'Tag','MABR_OFFLINE_KEYS')),'close() left windows.');
else
    kw = findall(groot,'Tag','MABR_OFFLINE_KEYS');
    if ~isempty(kw), delete(kw); end
    app.activateTab("Session");
end
% a window deleted behind the app's back takes the app (Model, timers) with it
a3 = mabr.ui.AnalysisApp("",Visible="off",Restore=false,RememberState=false, ...
    ProgressMode="none",AutoRefresh=false);
m3 = a3.Model;
delete(a3.Figure);
assert(~isvalid(a3) && ~isvalid(m3),'Deleting the window left the app or its Model behind.');
fprintf(['  PASS Part D: the window with no folder -- Start panel, tags, A6 toolbar, lazy tabs (each its own view class: Trials is TrialView), ' ...
    'F1, key routing, cb(), reuse\n']);
end

% =========================================================================
%  Part E -- a folder: study root, nothing written, events in order
% =========================================================================
function partE_events(app,stub,F)
m = app.Model;
snap0 = treeSnapshot(F.Root);
subjectFolder = fullfile(F.Root,"SUBJ-ID-9001");
rec = recordEvents(m);
app.openRoot(subjectFolder);
calls = stub.Calls('confirm');
assert(~isempty(calls) && contains(calls(end),"looks like one animal") && ...
    contains(calls(end),"Open the study folder?"),'Opening a subject folder did not offer the study folder.');
assert(samePath(m.Catalog.Root,F.Root),'The study folder was not opened (%s).',string(m.Catalog.Root));
assertEvents(rec,["BusyChanged(busy)","RootChanged(all)","ProjectChanged(all)", ...
    "SettingsChanged(all)","StatusChanged(status)","BusyChanged(idle)"],"openRoot");
sp = findall(app.Figure,'Tag','AnalysisStartPanel');
assert(strcmp(sp.Visible,'off'),'The Start panel stayed up with a folder open.');
assert(isequaln(m.Settings,F.Settings),'The Settings override did not win over the project.');
sv = findall(app.Figure,'Tag','AnalysisHeaderSaved');
assert(string(sv.Text) == "",'The header says "%s" before anything was saved.',string(sv.Text));

key = F.Keys(1);
m.flush();
rec = recordEvents(m);
m.openSession(key);
assert(m.SessionKey == key && m.SessionSource == "results" && ~m.Session.HasSweeps, ...
    'An analysed session did not open from its results.');
assertEvents(rec,["SessionChanged(all)","SelectionChanged(series)","StatusChanged(status)"],"openSession");
assert(m.Selection.SeriesKey ~= "" && isfinite(m.Selection.Level) && m.Selection.ConditionKey ~= "", ...
    'Opening a session did not select a series and level.');
assert(m.Status.State == "current",'A freshly analysed session is not up to date (%s).',m.Status.Text);
assert(startsWith(m.sessionTitle(),"SUBJ-ID-9001"),'sessionTitle: %s',m.sessionTitle());
ht = findall(app.Figure,'Tag','AnalysisHeaderTitle');
assert(string(ht.Text) == m.sessionTitle() && string(ht.Tooltip) == m.sessionTitle(), ...
    'The header does not show the session title (and the whole of it as its tooltip).');
assert(string(sv.Text) == "Saved",'A session opened from its results does not read "Saved".');
assert(isequal(treeSnapshot(F.Root),snap0),'Browsing wrote under the data folder.');
fprintf('  PASS Part E1: a subject folder offers the study folder; browsing writes nothing in the data\n');

rec = recordEvents(m);
m.ensureRaw();
assert(m.SessionSource == "raw" && m.Session.HasSweeps,'ensureRaw did not load the sweeps.');
assertEvents(rec,["BusyChanged(busy)","ResultsChanged(all)","StatusChanged(status)","BusyChanged(idle)"],"ensureRaw");

rec = recordEvents(m);
m.analyze(From="thresholds");
assertEvents(rec,["BusyChanged(busy)","ResultsChanged(all)","StatusChanged(status)","BusyChanged(idle)"], ...
    "analyze",IgnoreSave=true);
assert(~m.CanUndo,'analyze did not clear the undo history.');

sk = m.Selection.SeriesKey;
m.Analyst = "verify-analyst";                    % (Settings > Analyst Name...: the open session too)
rec = recordEvents(m);
m.acceptFit();
assertEvents(rec,["ResultsChanged(curation)","StatusChanged(save)"],"acceptFit");
assert(contains(m.LastMessage,"Ctrl+Z to undo"),'A curation command did not echo its undo hint.');
r = m.Session.Thresholds(string(m.Session.Thresholds.Key) == sk,:);
assert(string(r.Decision) == "accepted",'acceptFit did not accept.');
assert(string(r.ReviewedBy) == "verify-analyst",'A renamed analyst did not sign the open session''s edit.');
assert(m.CanUndo && startsWith(m.UndoLabel,"Accept fit"),'acceptFit left no undo entry.');
mu = findall(app.Figure,'Tag','AnalysisMenuUndo');
assert(contains(string(mu.Text),"Accept fit") && strcmp(mu.Enable,'on'),'Edit ▸ Undo does not name the edit.');
tu = findall(app.Figure,'Tag','AnalysisTool_undo');
assert(contains(string(tu.Tooltip),"Accept fit"),'The toolbar''s Undo does not name the edit (%s).',string(tu.Tooltip));

rec = recordEvents(m);
m.label(key,"Timepoint","Day 0");
assertEvents(rec,["ProjectChanged(labels)","StatusChanged(save)"],"label");
assert(projectValue(m,key,"Timepoint") == "Day 0",'The label was not set.');
rec = recordEvents(m);
m.undo();
assertEvents(rec,["ProjectChanged(labels)","StatusChanged(save)"],"undo (label)");
assert(projectValue(m,key,"Timepoint") ~= "Day 0",'Undo did not put the label back.');
m.redo();
assert(projectValue(m,key,"Timepoint") == "Day 0",'Redo did not set the label again.');
m.undo();
rec = recordEvents(m);
m.undo();
assertEvents(rec,["ResultsChanged(curation)","StatusChanged(save)"],"undo (curation)");
r = m.Session.Thresholds(string(m.Session.Thresholds.Key) == sk,:);
assert(string(r.Decision) ~= "accepted",'Undo did not take the acceptance back.');
% a thresholds-only settings change re-fits at once, BEFORE its events (so a
% view draws the re-fitted session once); the events keep the contract's order
s0 = m.Settings;
s2 = s0;
if s0.ThresholdMethod == "perm-descending", s2.ThresholdMethod = "perm-glm";
else, s2.ThresholdMethod = "perm-descending"; end
rec = recordEvents(m);
rec('refit') = "";
L = addlistener(m,'SettingsChanged',@(~,~) noteRefit(rec,m));
m.setSettings(s2);
delete(L);
assertEvents(rec,["SettingsChanged(all)","ResultsChanged(thresholds)","StatusChanged(status)"], ...
    "setSettings (a re-fit)",IgnoreSave=true);
assert(rec('refit') == s2.ThresholdMethod,'SettingsChanged was raised before the re-fit (the session had "%s").', ...
    rec('refit'));
m.setSettings(s0);
assert(m.Session.Settings.ThresholdMethod == s0.ThresholdMethod,'Setting the settings back did not re-fit.');
fprintf(['  PASS Part E2: events of openRoot, openSession, ensureRaw, analyze, a curation, a label, ' ...
    'undo and a re-fitting settings change, in 11 sec. 2.3 order\n']);
end

% =========================================================================
%  Part F -- every Mutating command is undoable
% =========================================================================
function partF_undoable(app)
m = app.Model;
S = m.Session;
sk = m.Selection.SeriesKey;
[ck,lv] = seriesLevels(m,sk);
m.selectSeries(sk,Level=max(lv));               % a level with a response
wave = firstPickedWave(m,ck(end));
T = mabr.ui.analysis.Commands.spec();
ids = unique(T.Id(T.Mutating),'stable');
done = strings(0,1);
for id = reshape(ids,1,[])
    % a state the command can act on
    switch id
        case "thr.clear"
            m.acceptFit();
        case "peak.revert"
            m.selectWave(wave,"P");
            m.nudgePeak(1);
        case "trials.restore"
            m.selectSweeps([1 2]);
            m.setSweepsRejected(true);
        case "trials.reject"
            m.selectSweeps([3 4 5]);
    end
    if startsWith(id,"peak.") && id ~= "peak.autoPick"
        m.selectWave(wave,"P");
    end
    before = S.editSnapshot();
    nUndo = undoCount(m);
    app.runCommand(id);
    if m.KeysSuspended, app.NoteEditor.cancel(); end
    assert(undoCount(m) == nUndo + 1,'"%s" left no undo entry (%s).',id,m.LastMessage);
    after = S.editSnapshot();
    if ~ismember(id,["peak.autoPick","peak.retrack","peak.retrackOverwrite"])
        assert(~isequaln(after,before),'"%s" changed nothing to undo.',id);
    end
    m.undo();
    assert(isequaln(S.editSnapshot(),before),'Undoing "%s" did not restore the edits.',id);
    done(end+1) = id; %#ok<AGROW>
end
% clean the setup edits away again
while m.CanUndo, m.undo(); end
fprintf('  PASS Part F: all %d Mutating commands are undoable (%s)\n',numel(done),strjoin(done,', '));
end

% =========================================================================
%  Part G -- keys with a session
% =========================================================================
function partG_keys(app)
m = app.Model;
S = m.Session;
app.activateTab("Series");
sel0 = m.Selection;
snap0 = S.editSnapshot();
% the note editor swallows typing
app.NoteEditor.open(struct('Kind',"series",'Key',sel0.SeriesKey),"");
assert(m.KeysSuspended && app.NoteEditor.IsOpen,'The note editor did not suspend the keys.');
for ch = 'tinnitus'
    app.dispatchKey(keyEvt(ch));
end
app.dispatchKey(keyEvt('uparrow'));
app.dispatchKey(keyEvt('2','control'));
assert(isequaln(S.editSnapshot(),snap0) && isequaln(m.Selection,sel0) && app.ActiveTab == "Series", ...
    'Typing into the note editor ran commands.');
assert(app.dispatchKey(keyEvt('escape')) && ~app.NoteEditor.IsOpen && ~m.KeysSuspended, ...
    'Esc did not close the note editor.');
% Ctrl+Enter saves the note
app.NoteEditor.open(struct('Kind',"series",'Key',sel0.SeriesKey),"");
app.NoteEditor.write("electrode loose");
assert(app.dispatchKey(keyEvt('return','control')) && ~app.NoteEditor.IsOpen,'Ctrl+Enter did not save.');
r = S.Thresholds(string(S.Thresholds.Key) == sel0.SeriesKey,:);
assert(string(r.Note) == "electrode loose",'The note was not saved on the series.');
m.undo();
% Ctrl chords and plot keys work again
m.KeyTarget = "plot";
assert(app.dispatchKey(keyEvt('2','control')) && app.ActiveTab == "Grid",'Ctrl+2 after the editor.');
[~,lv] = seriesLevels(m,m.Selection.SeriesKey);
m.selectLevel(min(lv));
l0 = m.Selection.Level;
assert(app.dispatchKey(keyEvt('uparrow')) && m.Selection.Level > l0,'Up did not step to a louder level.');
% x excludes and opens the note editor
assert(app.dispatchKey(keyEvt('x')) && app.NoteEditor.IsOpen,'x did not open the note editor.');
app.dispatchKey(keyEvt('escape'));
r = S.Thresholds(string(S.Thresholds.Key) == m.Selection.SeriesKey,:);
assert(string(r.Decision) == "excluded",'x did not exclude.');
m.undo();
% the browser has the keyboard: Return opens, letters and arrows are not the plots'
m.FocusArea = "browser";
m.KeyTarget = "plot";
l1 = m.Selection.Level;
assert(~app.dispatchKey(keyEvt('uparrow')) && m.Selection.Level == l1,'Up moved the level from the browser.');
assert(~app.dispatchKey(keyEvt('a')),'"a" ran from the browser.');
orig = m.SessionKey;
other = setdiff(string(m.Catalog.Sessions.Key),orig,'stable');
if ~isempty(app.Browser) && isvalid(app.Browser) && ismethod(app.Browser,'selectKeys')
    app.Browser.selectKeys(other(1));
    m.FocusArea = "browser";
    m.KeyTarget = "plot";
    assert(app.dispatchKey(keyEvt('return')) && m.SessionKey == other(1),'Return did not open the selection.');
    m.openSession(orig);
    if ~m.Session.HasSweeps, m.ensureRaw(); end
else
    assert(app.dispatchKey(keyEvt('return')),'Return was not dispatched from the browser.');
end
m.FocusArea = "workspace";
fprintf(['  PASS Part G: the note editor swallows typing (Esc closes, Ctrl+Enter saves), x opens it, ' ...
    'plot keys and chords, browser focus\n']);
end

% =========================================================================
%  Part H -- autosave, conflict, read-only
% =========================================================================
function partH_autosave(app,F,work)
m = app.Model;
m.flush();
file = m.sessionInfo(m.SessionKey).ResultsFile;
% Part E's analyze replaced the results file: the old one went to .history
flat = regexprep(m.SessionKey,'[^A-Za-z0-9_\-]','_');
H = dir(fullfile(F.ResultsFolder,'.history',char(flat + "_*.mat")));
assert(~isempty(H) && numel(H) <= 3,'A re-analysis did not keep the previous results in .history (%d files).',numel(H));
d0 = dir(file);
m.acceptFit();
assert(m.SaveState == "pending",'An edit did not make the save pending (%s).',m.SaveState);
sv = findall(app.Figure,'Tag','AnalysisHeaderSaved');
assert(string(sv.Text) == "Save pending",'The header does not say "Save pending".');
st = findall(app.Figure,'Tag','AnalysisStatusText');
echo = string(st.Text);
assert(contains(echo,"Ctrl+Z to undo"),'The accept did not echo itself (%s).',echo);
m.flush();
d1 = dir(file);
assert(m.SaveState == "saved" && ~isequal([d0.bytes d0.datenum],[d1.bytes d1.datenum]), ...
    'flush() did not write the results file.');
R = load(file,'Thresholds');
assert(any(string(R.Thresholds.Decision) == "accepted"),'The saved file lacks the edit.');
% the save is the header's to report: the edit's echo (and its undo hint)
% stays on the status line
assert(string(st.Text) == echo,'The save replaced the edit''s echo with "%s".',string(st.Text));
% a project with no settings of its own records the ones in force at its
% first save (the fixture's was written by a batch, with none)
P = load(fullfile(F.ResultsFolder,'project.mat'));
ps = P.(char(mabr.analysis.Project.VarName)).Settings;
assert(isstruct(ps) && ~isempty(ps) && mabr.analysis.Settings.fromStruct(ps).hash() == m.Settings.hash(), ...
    'The project did not record its settings at its first save.');
% a file changed behind the Model's back is a conflict, never overwritten
x = 1;
save(file,'x','-append');
d2 = dir(file);
m.clearDecision();
m.flush();
d3 = dir(file);
assert(m.SaveState == "conflict" && isequal([d2.bytes d2.datenum],[d3.bytes d3.datenum]), ...
    'A results file changed elsewhere was overwritten (state %s).',m.SaveState);
bt = findall(app.Figure,'Tag','AnalysisHeaderBarText');
assert(contains(string(bt.Text),"changed elsewhere"),'The bar does not offer the conflict.');
m.keepMine();
assert(m.SaveState == "saved",'keepMine did not save.');
fprintf('  PASS Part H1: autosave writes the results file; a file changed elsewhere is a conflict, not overwritten\n');

% an unwritable results folder makes the Model read-only
blocker = fullfile(work,"blocker.txt");
writeText(blocker,"not a folder");
stub = newStub(work);
ro = mabr.ui.AnalysisApp(F.Root,Visible="off",ResultsFolder=fullfile(blocker,"MABR_Analysis"), ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false,RememberState=false, ...
    ProgressMode="none",AutoRefresh=false,ConfirmFcn=stub.Confirm,PromptFcn=stub.Prompt, ...
    PickFolderFcn=stub.PickFolder,PickFileFcn=stub.PickFile,AlertFcn=stub.Alert);
cr = onCleanup(@() closeQuietly(ro));
mr = ro.Model;
mr.label(F.Keys(1),"Timepoint","Day 9");
mr.flush();
assert(mr.ReadOnly && mr.SaveState == "readonly",'An unwritable results folder did not make it read-only.');
assert(projectValue(mr,F.Keys(1),"Timepoint") == "Day 9",'A read-only edit was lost from memory.');
bt = findall(ro.Figure,'Tag','AnalysisHeaderBarText');
assert(startsWith(string(bt.Text),"Read-only"),'The bar does not say read-only.');
% ... and a curation made there, in memory only
k1 = F.Keys(1);
mr.openSession(k1);
mr.analyze();
mr.acceptFit();
sk = mr.Selection.SeriesKey;
mr.flush();
assert(mr.ReadOnly && mr.SaveState == "readonly",'The read-only session was saved somewhere.');
% "Choose results folder…": the edits held in memory move to the new store
moved = fullfile(work,"moved_results");
mr.setResultsFolder(moved);
assert(~mr.ReadOnly && mr.SaveState == "saved" && samePath(mr.resultsFolder(),moved), ...
    'Choosing a writable results folder did not end read-only (%s).',mr.SaveState);
assert(mr.SessionKey == k1 && projectValue(mr,k1,"Timepoint") == "Day 9", ...
    'The read-only label edit did not move with the results folder.');
Pm = load(fullfile(moved,'project.mat'));
Ts = Pm.(char(mabr.analysis.Project.VarName)).Sessions;
assert(string(Ts.Timepoint(string(Ts.Key) == k1)) == "Day 9",'The moved project.mat lacks the label.');
Rm = load(mr.sessionInfo(k1).ResultsFile,'Thresholds');
assert(string(Rm.Thresholds.Decision(string(Rm.Thresholds.Key) == sk)) == "accepted", ...
    'The read-only curation was not written into the new results folder.');
fprintf(['  PASS Part H2: an unwritable results folder makes the Model read-only (edits kept in memory); ' ...
    'choosing another moves the edits there\n']);

% a results file that cannot be read (a partial sync) does not lock its
% session out: it opens from the raw files, the bad file kept in .history
mr.closeSession();
rf = mr.sessionInfo(k1).ResultsFile;
garbage(rf);
mr.openSession(k1);
assert(mr.SessionKey == k1 && ~isempty(mr.Session) && mr.SessionSource == "raw", ...
    'An unreadable results file kept its session from opening (%s).',mr.LastMessage);
assert(contains(mr.LastMessage,"raw files") && contains(mr.LastMessage,"could not be read"), ...
    'Opening past an unreadable results file did not say so: %s',mr.LastMessage);
kept = dir(fullfile(moved,'.history',"*_unreadable_*.mat"));
assert(isscalar(kept),'The unreadable results file was not kept aside in .history.');
mr.closeSession();
% a project.mat that cannot be read: read-only, saying why, and an edit is
% not "retrying" a save that cannot succeed
garbage(fullfile(moved,'project.mat'));
mr.openRoot(F.Root);
assert(mr.ReadOnly && contains(mr.ReadOnlyWhy,"project.mat") && startsWith(mr.LastMessage,"Read-only") && ...
    mr.LastMessageLevel >= 1,'An unreadable project.mat was ignored silently (%s).',mr.LastMessage);
bt = findall(ro.Figure,'Tag','AnalysisHeaderBarText');
assert(contains(string(bt.Text),"project.mat"),'The bar does not say project.mat cannot be used.');
mr.label(F.Keys(2),"Timepoint","Day 3");
mr.flush();
assert(mr.SaveState == "readonly" && ~contains(mr.LastMessage,"retrying"), ...
    'A label edit over an unreadable project.mat is %s (%s).',mr.SaveState,mr.LastMessage);
% ... and an export there asks for a folder, and refuses -- naming the
% store -- when given none
files = mr.export(struct('Scope',"all",'Tables',"sessions",'Formats',"csv",'RScript',false));
assert(isempty(files) && contains(mr.LastMessage,"cannot be written") && ...
    contains(mr.LastMessage,mr.resultsFolder()),'A read-only export: %s',mr.LastMessage);
clear cr
closeQuietly(ro);
fprintf(['  PASS Part H3: an unreadable results file opens its session from the raw files (kept in ' ...
    '.history); an unreadable project.mat is read-only with its reason, an edit is not retried; an ' ...
    'export from a read-only store refuses naming it\n']);
end

function garbage(file)
% Overwrite FILE with bytes no MAT reader takes (what a partial sync leaves).
fid = fopen(file,'w');
fwrite(fid,uint8(mod((1:4096)*37,251)));
fclose(fid);
end

% =========================================================================
%  Part I -- busy, cancel, close while busy
% =========================================================================
function partI_jobs(app,F)
m = app.Model;
box = containers.Map('KeyType','char','ValueType','any');
box('err') = "";
prog0 = m.ProgressFcn;
m.ProgressFcn = @(op,title) struct('update',@(t,f) tryWhileBusy(m,box), ...
    'cancelled',@() false,'close',@() []);
m.rescan();
m.ProgressFcn = prog0;
assert(box('err') == "mabr:ui:analysis:busy",'A mutating call inside a job did not error busy (%s).',box('err'));

% cancel: nothing changed
S = m.Session;
if ~S.HasSweeps, m.ensureRaw(); end
before = stateOf(S);
m.ProgressFcn = @(op,title) struct('update',@(t,f) m.cancel(),'cancelled',@() false,'close',@() []);
m.analyze(From="detect");
m.ProgressFcn = prog0;
assert(~m.Busy && contains(m.LastMessage,"Cancelled") && contains(m.LastMessage,"nothing changed"), ...
    'Cancelling did not say "Cancelled ... nothing changed" (%s).',m.LastMessage);
assert(isequaln(stateOf(S),before),'A cancelled analysis changed the session.');
fprintf('  PASS Part I1: busy guard inside a job; a cancelled job says so and changes nothing\n');

end

function partI2_closeWhileBusy(app)
% Closing while busy closes after the job unwinds -- the test's own window,
% last of all: one a user has had open a while (a window closed while the
% client is still drawing it for the first time is another matter: its
% components' first "ready" reports arrive after they are gone, whatever
% the app does). The command window's output is captured: an event the
% client sends to a component already deleted prints a red "Invalid or
% deleted object" stack there, which closing must not leave behind -- the
% app redraws nothing once a close is pending and gives the client a moment
% before the window goes.
app.Model.ProgressFcn = @(op,title) struct('update',@(t,f) app.Figure.CloseRequestFcn(app.Figure,[]), ...
    'cancelled',@() false,'close',@() []);
out = evalc('t0 = closeWhileBusy(app);');
assert(~isvalid(app),'A window closed while busy was still open %.0f s after the job ended.',toc(t0));
assert(~contains(out,"Invalid or deleted object"),'Closing while busy printed: %s',out);
fprintf('  PASS Part I2: closing while busy cancels, and the window goes once the job unwinds, printing nothing (%.1f s)\n',toc(t0));
end

function t0 = closeWhileBusy(app)
app.Model.rescan();
t0 = tic;
while isvalid(app) && toc(t0) < 30
    pause(0.05);
end
drawnow;
pause(0.3);
end

function tryWhileBusy(m,box)
if box('err') ~= "", return; end
try
    m.label(string(m.Catalog.Sessions.Key(1)),"Comment","x");
    box('err') = "no error"; %#ok<NASGU> (a containers.Map)
catch me
    box('err') = string(me.identifier); %#ok<NASGU>
end
end

function s = stateOf(S)
s = struct('StepState',S.StepState,'Edits',S.editSnapshot(), ...
    'p',S.Conditions.p,'Thresholds',S.Thresholds(:,{'Key','Threshold','Decision'}));
end

% =========================================================================
%  Part J -- blind review, the acquisition guard
% =========================================================================
function partJ_review(app,F)
m = app.Model;
keys = F.Keys(1:2);
m.startReviewQueue(keys,UnreviewedOnly=false,Blind=true);
assert(m.BlindReview && m.sessionTitle() == "Review item 1 / 2",'Blind review title: %s',m.sessionTitle());
ht = findall(app.Figure,'Tag','AnalysisHeaderTitle');
assert(string(ht.Text) == "Review item 1 / 2",'The header shows more than the review item.');
tab0 = app.ActiveTab;
app.activateTab("Study");
assert(app.ActiveTab == tab0,'The Study tab opened during blind review.');
m.nextInQueue(1);
assert(m.SessionKey == keys(2) && m.sessionTitle() == "Review item 2 / 2",'nextInQueue.');
% nothing names a subject or session: the status line (the Model's
% "Opened ..." and anything the app says), the bar, the last message
st = findall(app.Figure,'Tag','AnalysisStatusText');
bt = findall(app.Figure,'Tag','AnalysisHeaderBarText');
named = @(t) contains(string(t),"SUBJ-ID") || any(contains(string(t),F.Keys));
assert(~named(st.Text) && ~named(st.Tooltip) && contains(string(st.Text),"review item 2 / 2"), ...
    'The status line names the session in blind review: %s',string(st.Text));
assert(~named(m.LastMessage) && ~named(bt.Text),'The bar or the last message names a session in blind review.');
info = m.sessionInfo(keys(1));
app.setStatus("Opened " + info.Name + " from " + fullfile(info.Paths(1),"MABR_Analysis") + ...
    " (" + info.Subject + ", 12 conditions)",0);
assert(~named(st.Text) && contains(string(st.Text),"12 conditions"), ...
    'A status sentence the app wrote names the session in blind review: %s',string(st.Text));
assert(m.blindText("SUBJ-ID-90017 has 9001 sweeps") == "SUBJ-ID-90017 has 9001 sweeps", ...
    'blindText masked part of a longer word: %s',m.blindText("SUBJ-ID-90017 has 9001 sweeps"));
m.endQueue();
assert(~m.BlindReview && isempty(m.Queue) && ~startsWith(m.sessionTitle(),"Review"),'endQueue.');
app.setStatus("Opened " + info.Name,0);
assert(contains(string(st.Text),info.Name),'After the review the status line still masks names.');
assert(~m.isAcquisitionBusy(),'The acquisition guard reports acquisition with no App open.');
fprintf(['  PASS Part J: blind review titles and the Study tab; the status line, the bar and the last ' ...
    'message name no session or subject; the acquisition guard\n']);
end

% =========================================================================
%  Part N -- the sound conduction delay (13 A9)
% =========================================================================
function partN_latency(app,F)
m = app.Model;
key = F.Keys(1);
if m.SessionKey ~= key, m.openSession(key); end
S = m.Session;
assert(m.latencyOffset() == 0,'A session with no delay has a latency offset (%g).',m.latencyOffset());
T0 = mabr.ui.analysis.View.timeAxisFor(m);
assert(T0.Label == "Time re onset (ms)" && T0.Tip == "" && T0.Offset == 0,'The onset time axis.');
P0 = S.Peaks;
picked = isfinite(P0.PeakLatency);
assert(any(picked),'No picked peak to move.');
rec = recordEvents(m);
m.setSessionOverrides(key,struct('ConductionDelay',0.25));
assertEvents(rec,["BusyChanged(busy)","ResultsChanged(all)","StatusChanged(status)","BusyChanged(idle)"], ...
    "setSessionOverrides",IgnoreSave=true);
assert(projectValueNum(m,key,"ConductionDelayOverride") == 0.25,'The delay did not reach the project.');
assert(S.ConductionDelayOverride == 0.25 && abs(m.latencyOffset() - 0.25) < 1e-12, ...
    'The delay did not reach the Session (offset %g).',m.latencyOffset());
P1 = m.Session.Peaks;
assert(all(abs(P1.LatencyOffset - 0.25) < 1e-12),'The peaks were not re-picked at the new offset.');
% the waves are searched in the recording's time: a delay changes what is
% reported, never a pick (to the fraction of a sample a results-only
% session's re-pick may differ by)
d1 = abs(P1.PeakLatency - P0.PeakLatency);
assert(height(P1) == height(P0) && isequal(isnan(P1.PeakLatency),isnan(P0.PeakLatency)) && ...
    all(d1(~isnan(d1)) <= 1000/S.SampleRate),'The delay moved a pick (largest change %.3g ms).',max([0; d1(~isnan(d1))]));
assert(contains(m.LastMessage,"re-picked"),'The status line does not say the peaks were re-picked (%s).',m.LastMessage);
T1 = mabr.ui.analysis.View.timeAxisFor(m);
assert(T1.Label == "Time re sound arrival (ms)" && abs(T1.Offset - 0.25) < 1e-12 && ...
    contains(T1.Tip,"0.25") && contains(T1.Tip,"override"), ...
    'The time axis does not read re sound arrival with the delay named (%s | %s).',T1.Label,T1.Tip);
assert(abs((10 - T1.Offset) - 9.75) < 1e-12,'Raw 10 ms is not 9.75 ms re sound arrival.');
m.flush();
assert(m.Status.State == "current",'The re-picked session is not up to date (%s).',m.Status.Text);
V = m.projectView();
assert(string(V.Status(string(V.Key) == key)) == "current", ...
    'The project reads the session as out of date after the delay was applied and saved (%s).', ...
    string(V.StatusText(string(V.Key) == key)));
% back to none
m.setSessionOverrides(key,struct('ConductionDelay',NaN));
assert(isnan(projectValueNum(m,key,"ConductionDelayOverride")) && m.latencyOffset() == 0 && ...
    mabr.ui.analysis.View.timeAxisFor(m).Label == "Time re onset (ms)",'Clearing the delay.');
P2 = m.Session.Peaks;
% (a results-only session re-picks from its stored single-precision means,
% so a pick may move by a fraction of a sample, never more)
dt = 1000/m.Session.SampleRate;
d = abs(P2.PeakLatency - P0.PeakLatency);
assert(isequal(isnan(P2.PeakLatency),isnan(P0.PeakLatency)) && all(d(~isnan(d)) <= dt), ...
    'Clearing the delay did not give the original picks back (largest change %.3g ms).',max([0; d(~isnan(d))]));
% a system time offset alone keeps "re onset" and names the offset (11 sec. 7.3)
m.setSessionOverrides(key,struct('TimeOffset',0.1));
T2 = mabr.ui.analysis.View.timeAxisFor(m);
assert(startsWith(T2.Label,"Time re onset (ms)") && contains(T2.Label,"0.1 ms offset") && ...
    abs(T2.Offset - 0.1) < 1e-12 && contains(T2.Tip,"system offset"), ...
    'A time offset alone: %s | %s',T2.Label,T2.Tip);
m.setSessionOverrides(key,struct('TimeOffset',NaN));
assert(m.latencyOffset() == 0,'Clearing the time offset.');
m.flush();
% a delay set on a session that is NOT open (the Study table): opening it,
% its peaks were picked at another offset -- out of date from "peaks" (an
% instant re-fit), never shown as up to date with the old picks
k2 = F.Keys(2);
m.setSessionOverrides(k2,struct('ConductionDelay',0.2));
m.openSession(k2);
assert(m.Status.State == "stale" && m.Status.FromStep == "peaks" && ...
    m.Status.Text == "Out of date (overrides changed)", ...
    'A session whose delay changed while closed opened as %s (from %s).',m.Status.Text,m.Status.FromStep);
bt = findall(app.Figure,'Tag','AnalysisHeaderBarText');
assert(contains(string(bt.Text),"latency offset"),'The bar does not say the latency offset changed.');
m.analyze();
assert(m.Status.State == "current" && all(abs(m.Session.Peaks.LatencyOffset - 0.2) < 1e-12), ...
    'Analyse did not re-pick the peaks at the new delay (%s).',m.Status.Text);
m.setSessionOverrides(k2,struct('ConductionDelay',NaN));
assert(m.Status.State == "current" && m.latencyOffset() == 0,'Clearing the delay of the open session.');
m.openSession(key);
m.flush();
fprintf(['  PASS Part N: a 0.25 ms conduction-delay override reaches project and session, re-picks ' ...
    'the peaks, stays up to date, and the time axis reads "re sound arrival"; clearing it restores onset; ' ...
    'a delay set while a session was closed opens it out of date from "peaks"\n']);
end

function v = projectValueNum(m,key,name)
T = m.Project.Sessions;
v = double(T.(name)(string(T.Key) == key));
end

% =========================================================================
%  Part K -- prefs written only from the user's callbacks; state restored
% =========================================================================
function partK_prefs(F)
[app,stub] = newApp(F,"",RememberState=true);
stub.Answers('folder') = F.Root;
b = findall(app.Figure,'Tag','AnalysisStartOpen');
b.ButtonPushedFcn(b,[]);                     % the user presses Open data folder...
r = string(getpref('MABR','OfflineRecentRoots'));
assert(samePath(r(1),F.Root),'The Open button did not remember the folder.');
lb = findall(app.Figure,'Tag','AnalysisStartRecent');
assert(any(arrayfun(@(x) samePath(x,F.Root),string(lb.Items))),'The Start panel does not list the recent folder.');
m = app.Model;
m.openSession(F.Keys(2));
app.activateTab("Series");
sk = m.Selection.SeriesKey;
app.close();                                 % RememberState: position and state
assert(~isvalid(app),'close() did not close.');
st = getpref('MABR','OfflineAnalysisLastState');
assert(samePath(st.Root,F.Root) && string(st.SessionKey) == F.Keys(2) && string(st.Tab) == "Series", ...
    'The last state was not remembered.');
assert(ispref('MABR','WindowPos_OfflineAnalysis') && ispref('MABR','OfflineAnalysisLayout'), ...
    'Closing did not remember the window position and layout.');
% ... and comes back
a2 = mabr.ui.AnalysisApp("",Visible="off",ResultsFolder=F.ResultsFolder,CacheFolder=F.CacheFolder, ...
    Settings=F.Settings,Restore=true,RememberState=false,ProgressMode="none",AutoRefresh=false, ...
    ConfirmFcn=stub.Confirm,PromptFcn=stub.Prompt,PickFolderFcn=stub.PickFolder, ...
    PickFileFcn=stub.PickFile,AlertFcn=stub.Alert);
c2 = onCleanup(@() closeQuietly(a2));
assert(a2.Model.SessionKey == F.Keys(2) && a2.ActiveTab == "Series" && a2.Model.Selection.SeriesKey == sk, ...
    'The last session, tab and series were not reopened.');
clear c2
closeQuietly(a2);
fprintf(['  PASS Part K2: the Open button remembers the folder; close remembers position and state; ' ...
    'Restore reopens them\n']);
end

% =========================================================================
%  Part L -- exports
% =========================================================================
function partL_exports(app,F,work)
partL_figure(work);
m = app.Model;
if exist('mabr.analysis.ScriptWriter','class') == 8
    file = m.exportScript(File=fullfile(work,"replicate_test.m"),Open=false);
    assert(isfile(file),'exportScript wrote no file.');
    code = fileread(file);
    assert(contains(code,"mabr.analysis.Session(") && contains(code,"analyze("), ...
        'The analysis script does not rebuild and analyse the session.');
    % the menu/toolbar route: asks where (PickFileFcn), never opens an editor here
    app.runCommand("file.exportScript");
    assert(m.LastScript ~= file && isfile(m.LastScript) && endsWith(m.LastScript,".m"), ...
        'file.exportScript did not write a script where PickFileFcn said (%s).',m.LastScript);
    assert(contains(m.LastMessage,"replication script of " + m.Session.Name),'The status line does not name the script''s scope: %s',m.LastMessage);
    % several sessions: one study script
    f2 = m.exportScript(Keys=F.Keys(1:2),File=fullfile(work,"study_replicate.m"),Open=false);
    code = fileread(f2);
    assert(numel(strfind(code,"mabr.analysis.Session(")) >= 2,'The study script does not rebuild both sessions.');
    assert(contains(m.LastMessage,"of 2 selected sessions"),'The study script''s status: %s',m.LastMessage);
    % a session open and several selected in the browser: the menu asks which
    % (here, the selection), never silently the open session alone
    app.Browser.selectKeys(F.Keys(1:2));
    c0 = m.ConfirmFcn;
    m.ConfirmFcn = @(msg,title,options,default) pickSecond(msg,options);
    try
        app.runCommand("file.exportScript");
    catch me
        m.ConfirmFcn = c0;
        rethrow(me);
    end
    m.ConfirmFcn = c0;
    code = fileread(m.LastScript);
    assert(numel(strfind(code,"mabr.analysis.Session(")) >= 2 && contains(m.LastMessage,"of 2 selected sessions"), ...
        'With two sessions selected the menu did not write their study script (%s).',m.LastMessage);
    fprintf(['  PASS Part L2: Export Analysis Script writes a script that rebuilds the session (menu route, ' ...
        'study of two; with several selected it asks which, and the status line names the scope)\n']);
else
    fprintf('  SKIP Part L2: mabr.analysis.ScriptWriter is not in this MABR yet\n');
end
out = fullfile(work,"export1");
files = m.export(struct('Scope',"current",'Tables',["sessions","thresholds"],'Formats',"csv", ...
    'RScript',false,'Folder',out));
assert(istable(files) && height(files) >= 2 && all(isfile(files.File(files.File ~= ""))), ...
    'export() did not write the tables.');
assert(m.LastExportFolder == out,'LastExportFolder.');
again = m.exportAgain();
assert(istable(again) && height(again) >= 2 && m.LastExportFolder ~= out,'exportAgain did not use a new folder.');
fprintf('  PASS Part L3: export writes the tables; Export Again repeats into a new folder\n');
T = m.batch(F.Keys(1),SkipCurrent=true,Settings=F.Settings);   % (the BatchDialog's profile)
assert(istable(T) && height(T) == 1 && ~isempty(m.LastBatch),'batch() through the Model.');
fprintf('  PASS Part L4: a batch through the Model (%s)\n',string(T.Status(1)));
end

function partL_figure(work)
f = figure('Visible','off');
cf = onCleanup(@() delete(f));
ax = axes(f);
plot(ax,1:5,(1:5).^2,'DisplayName','squares');
hold(ax,'on');
plot(ax,1:3,[2 4 6],'DisplayName','evens');
legend(ax);
png = fullfile(work,"fig1.png");
file = mabr.ui.analysis.FigureExport.run(ax,Format="png",WidthCm=8,HeightCm=6,DPI=100,File=png);
assert(isfile(file) && file == png,'FigureExport.run wrote no png.');
info = imfinfo(char(file));
assert(info.Width > 150 && info.Width <= round(8/2.54*100) + 2, ...
    'The png is not (at most) 8 cm wide at 100 dpi (%d px).',info.Width);
pdf = mabr.ui.analysis.FigureExport.run(ax,Format="pdf",File=fullfile(work,"fig1"));
assert(isfile(pdf) && endsWith(pdf,".pdf"),'FigureExport.run wrote no pdf.');
% a layer switched off is not copied (Copy data copies what is shown), nor
% a line inside a hidden group
plot(ax,1:9,1:9,'DisplayName','hidden','Visible','off');
hg = hggroup(ax,'Visible','off');
line(hg,1:8,1:8,'DisplayName','grouped');
txt = mabr.ui.analysis.FigureExport.copyData(ax);
lines = splitlines(txt);
assert(startsWith(lines(1),"squares x" + char(9) + "squares y") && numel(lines) == 6, ...
    'copyData is not tab-separated columns with a header.');
assert(~contains(lines(1),"hidden") && ~contains(lines(1),"grouped") && numel(split(lines(1),char(9))) == 4, ...
    'copyData copied a line that is not shown: %s',lines(1));
% ... but a hidden carrier of a plot's true values (markForCopy) is
cl = mabr.ui.analysis.FigureExport.markForCopy(line(ax,1:5,2*(1:5),'Visible','off','DisplayName','carried'));
hdr = split(extractBefore(mabr.ui.analysis.FigureExport.copyData(ax) + newline,newline),char(9));
assert(any(hdr == "carried y") && numel(hdr) == 6,'copyData did not copy a marked carrier line.');
delete(cl);
% a line with hidden handles (a drawn ruler, a key) is drawing, not data --
% whatever the root's ShowHiddenHandles says
hh = line(ax,1:4,1:4,'DisplayName','ruler','HandleVisibility','off');
sh0 = get(groot,'ShowHiddenHandles');
set(groot,'ShowHiddenHandles','on');
try
    hdr = split(extractBefore(mabr.ui.analysis.FigureExport.copyData(ax) + newline,newline),char(9));
catch me
    set(groot,'ShowHiddenHandles',sh0);
    rethrow(me);
end
set(groot,'ShowHiddenHandles',sh0);
assert(~any(contains(hdr,"ruler")),'copyData copied a hidden-handle line with ShowHiddenHandles on.');
delete(hh);
cm = uicontextmenu(f);
it = mabr.ui.analysis.FigureExport.addContextItems(cm,ax,[]);
assert(numel(it) == 3 && string(it(1).Text) == "Export figure…" && strcmp(it(1).Separator,'on') && ...
    string(it(2).Text) == "Copy data" && string(it(3).Text) == "Copy image",'addContextItems.');
uf = uifigure('Visible','off');
cu = onCleanup(@() delete(uf));
tb = uitable(uigridlayout(uf,[1 1]),'Data',table(["a";"b"],[1;NaN],[true;false]), ...
    'ColumnName',{'Name','Value','On'});
lines = splitlines(mabr.ui.analysis.FigureExport.copyTable(tb));
assert(isequal(lines,["Name" + char(9) + "Value" + char(9) + "On"; "a" + char(9) + "1" + char(9) + "TRUE"; ...
    "b" + char(9) + char(9) + "FALSE"]),'copyTable is not tab-separated with a header row.');
d = mabr.ui.analysis.FigureExport(ax,[],Visible="off");
d.write(struct('Format',"png",'WidthCm',10));
v = d.read();
assert(v.Format == "png" && v.WidthCm == 10,'FigureExport dialog read/write.');
assert(~isempty(findall(d.Figure,'Tag','AnalysisFigureOK')),'FigureExport dialog tags.');
d.cancel();
assert(~d.isopen(),'FigureExport cancel did not close.');
p = mabr.ui.analysis.PromptDialog("Pool name","Name of the pool:","Pool 1",Visible="off");
assert(p.read() == "Pool 1",'PromptDialog default.');
p.write("Day 3");
p.ok();
assert(p.Value == "Day 3" && ~p.isopen(),'PromptDialog ok().');
p = mabr.ui.analysis.PromptDialog("Level","Level (dB):",40,Visible="off",Numeric=true);
p.write(55);
assert(p.read() == 55,'A numeric PromptDialog.');
p.cancel();
assert(isempty(p.Value),'PromptDialog cancel() gave an answer.');
fprintf('  PASS Part L1: FigureExport (png at size, pdf, copyData of what is shown, dialog), PromptDialog (ok, cancel, numeric)\n');
end

% =========================================================================
%  Part M -- static scans
% =========================================================================
function partM_scans()
gui = [string(which('mabr.ui.AnalysisApp')); analysisGuiFiles()];
compat = string(which('mabr.ui.analysis.Compat'));
hits = strings(0,1);
for f = reshape(gui,1,[])
    if strcmpi(f,compat), continue; end
    hits = [hits; postR2021b(f)]; %#ok<AGROW>
end
% the scan can fail: a planted file
plant = string(tempname) + ".m";
writeText(plant,["h.DoubleClickedFcn = @(s,e) 1;","focus(h);","x = obj.Selection;", ...
    "t.SelectionType = 'row';","set(t,'SelectionType','cell')","% focus(h) in a comment", ...
    "y = model.Selection.Level;","app.Figure.Theme = 'light';","ef.Placeholder = 'Search';", ...
    "set(ef,'Placeholder','none')","mabr.ui.analysis.Compat.setPlaceholder(ef,'Search (Ctrl+F)');", ...
    "s = 'a Placeholder in a sentence';"]);
cp = onCleanup(@() delete(plant));
pl = postR2021b(plant);
assert(numel(pl) == 8,'The post-R2021b scan found %d of the 8 planted uses:\n%s',numel(pl),strjoin(pl,newline));
assert(~any(contains(pl,"setPlaceholder")) && ~any(contains(pl,"in a sentence")), ...
    'The post-R2021b scan read Compat.setPlaceholder (or a sentence) as a use:\n%s',strjoin(pl,newline));
assert(isempty(hits),'Post-R2021b UI identifiers outside Compat.m:\n%s',strjoin(hits,newline));
fprintf('  PASS Part M1: no post-R2021b UI identifier outside Compat.m (%d files; a planted file is caught)\n',numel(gui));

% (identifiers in the window's and the model's files; the products of the
% window's own -- the model's are verify_offline_session Part L's, and the
% dependency analysis is most of this part's time)
model = analysisModelFiles();
files = [gui; model];
hits = strings(0,1);
for f = reshape(files,1,[])
    hits = [hits; forbiddenUses(f)]; %#ok<AGROW>
end
assert(isempty(hits),'Statistics Toolbox identifiers:\n%s',strjoin(hits,newline));
[~,pl] = matlab.codetools.requiredFilesAndProducts(cellstr(gui),'toponly');
names = string({pl.Name});
bad = names(contains(names,["Statistics","Curve Fitting"]));
assert(isempty(bad),'requiredFilesAndProducts lists %s.',strjoin(bad,', '));
fprintf('  PASS Part M2: no Statistics Toolbox identifier in %d files; the window''s %d files need: %s\n', ...
    numel(files),numel(gui),strjoin(names,', '));
end

function files = analysisGuiFiles()
d = fileparts(which('mabr.ui.analysis.Model'));
L = dir(fullfile(d,'*.m'));
files = reshape(string(fullfile({L.folder},{L.name})),[],1);
end

function files = analysisModelFiles()
% The new and modified +mabr/+analysis files (10 sec. 0).
d = fileparts(which('mabr.analysis.Session'));
names = ["AbrFile","Stats","Settings","SingleTrial","Peaks","SeriesThreshold","Threshold", ...
    "Session","Catalog","Project","Batch","Export","ScriptWriter","Filter","Plot","Progress"];
files = strings(0,1);
for n = names
    f = fullfile(d,n + ".m");
    if isfile(f), files(end+1,1) = f; end %#ok<AGROW>
end
end

function hits = postR2021b(file)
% Lines using a UI identifier newer than R2021b (11 sec. 13). Comments are
% ignored, strings are not (a property set by name counts). The Model's own
% Selection struct is not uitable.Selection: field access (".Selection.Level")
% and a model receiver (model/Model/m/obj in Model.m) are left alone.
% Placeholder counts as a property access (.Placeholder) or its name as a
% string literal ('Placeholder', set/get by name) -- never as part of
% another name, so Compat.setPlaceholder (the R2021b-safe way, 11 sec. 3.3)
% is not a use.
% Patterns: DoubleClickedFcn, ClickedFcn, focus(, .Placeholder,
% 'Placeholder', .Theme, clim(, fontsize(, xregion(/yregion(, dictionary(,
% scroll(, SelectionType 'row'|'cell'|'column' (by name or assignment),
% .Selection on a uitable-like receiver, tiledlayout(...,'horizontal'|
% 'vertical').
lines = splitlines(string(fileread(file)));
% (only lines that could hit are taken apart character by character)
cand = ~cellfun(@isempty,regexp(cellstr(lines), ...
    'DoubleClickedFcn|ClickedFcn|focus|Placeholder|Theme|clim|fontsize|region|dictionary|scroll|SelectionType|\.Selection|tiledlayout','once'));
code  = withoutComments(lines,cand);
[~,base] = fileparts(file);
pats = ["DoubleClickedFcn","ClickedFcn","\<focus\s*\(","\.Placeholder\>","'Placeholder'","\.Theme\>", ...
    "\<clim\s*\(","\<fontsize\s*\(","\<xregion\s*\(","\<yregion\s*\(","\<dictionary\s*\(", ...
    "\<scroll\s*\(","SelectionType'\s*,\s*'(row|cell|column)'", ...
    "SelectionType\s*=\s*'(row|cell|column)'"];
hits = strings(0,1);
for k = 1:numel(code)
    c = code(k);
    bad = false;
    for p = pats
        if ~isempty(regexp(c,p,'once')), bad = true; end
    end
    [tok,ix] = regexp(c,'(\w+)\.Selection\>(?!Type|ChangedFcn)','tokens','end');
    for i = 1:numel(tok)
        recv = string(tok{i}{1});
        nxt = extractBetween(c + " ",ix(i)+1,ix(i)+1);
        fieldAccess = nxt == ".";
        modelRecv = any(recv == ["model","Model","m","mdl"]) || (base == "Model" && recv == "obj");
        if ~fieldAccess && ~modelRecv, bad = true; end
    end
    if contains(c,"tiledlayout(") && ~isempty(regexp(c,'''(horizontal|vertical)''\s*\)','once'))
        bad = true;
    end
    if bad
        hits(end+1,1) = sprintf('%s:%d: %s',file,k,strtrim(lines(k))); %#ok<AGROW>
    end
end
end

function out = withoutComments(lines,cand)
% Each line with its comment removed (strings kept); %{ %} blocks dropped.
% Lines not in CAND (none of the patterns occurs in them) are left empty.
if nargin < 2, cand = true(size(lines)); end
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
    if ~cand(k), continue; end
    q = '';
    cut = numel(s);
    i = 1;
    while i <= numel(s)
        ch = s(i);
        if isempty(q)
            if ch == '%' || (i + 2 <= numel(s) && strcmp(s(i:i+2),'...'))
                cut = i - 1;
                break
            end
            if ch == '"'
                q = '"';
            elseif ch == ''''
                prev = ' ';
                if i > 1, prev = s(i-1); end
                if ~(isstrprop(prev,'alphanum') || any(prev == '_)]}.'''))
                    q = '''';
                end
            end
        elseif ch == q
            if i < numel(s) && s(i+1) == q
                i = i + 1;
            else
                q = '';
            end
        end
        i = i + 1;
    end
    out(k) = string(s(1:cut));
end
end

function [hits,where] = forbiddenUses(file)
% Lines calling a Statistics Toolbox function (10 sec. 0) or naming
% range/corr/mad (verify_offline_files' rule: comments, strings, dotted names
% and a function's own name are not uses).
names = ["prctile","quantile","iqr","mad","range","zscore","nanmean","nanstd","nanmedian", ...
    "corr","fcdf","finv","tcdf","tinv","normcdf","norminv","normpdf","randsample","datasample", ...
    "bootstrp","fitglm","fitlm","boxplot","ksdensity","grpstats","skewness","kurtosis"];
asName  = ["range","corr","mad"];
callPat = "(?<![\w.])(" + join(names,"|") + ")\s*\(";
namePat = "(?<![\w.])(" + join(asName,"|") + ")(?!\w)";
lines = splitlines(string(fileread(file)));
cand = ~cellfun(@isempty,regexp(cellstr(lines),char(join(names,"|")),'once'));
code  = codeOnly(lines,cand);
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

function out = codeOnly(lines,cand)
% Each line with its comment and the contents of its strings blanked.
% Lines not in CAND (no forbidden name occurs in them) are left empty.
if nargin < 2, cand = true(size(lines)); end
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
    if ~cand(k), continue; end
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
                    o(i) = ch;
                else
                    q = '''';
                end
            else
                o(i) = ch;
            end
        elseif ch == q
            if i < numel(s) && s(i+1) == q
                i = i + 1;
            else
                q = '';
            end
        end
        i = i + 1;
    end
    out(k) = string(o);
end
end

% =========================================================================
%  Helpers
% =========================================================================
function [app,stub] = newApp(F,root,opts)
arguments
    F
    root (1,1) string = ""
    opts.RememberState (1,1) logical = false
end
stub = newStub(F.ResultsFolder);
app = mabr.ui.AnalysisApp(root,Visible="off",ResultsFolder=F.ResultsFolder, ...
    CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false, ...
    RememberState=opts.RememberState,ProgressMode="none",AutoRefresh=false, ...
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
stub.PickFile   = @(filter,title,mode,default) string(fullfile(work,"picked_" + ...
    string(datetime('now','Format','HHmmssSSS')) + extFor(filter)));
end

function c = stubConfirm(calls,msg,title,options)
stubRecord(calls,'confirm',string(msg) + " | " + string(title));
c = string(options(1));
end

function stubRecord(calls,key,text)
calls(key) = [calls(key); string(text)]; %#ok<NASGU> (a containers.Map)
end

function e = extFor(filter)
e = ".dat";
t = regexp(char(string(filter)),'\*(\.\w+)','tokens','once');
if ~isempty(t), e = string(t{1}); end
end

function e = keyEvt(key,varargin)
e = struct('Key',key,'Modifier',{varargin},'Character','');
if isscalar(key) && isempty(varargin), e.Character = key; end
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

function noteRefit(rec,m)
% (the open session's threshold method when SettingsChanged arrives)
rec('refit') = string(m.Session.Settings.ThresholdMethod); %#ok<NASGU> (a containers.Map)
end

function logEvent(rec,n,e)
rec('log') = [rec('log'); n + "(" + e.What + ")"]; %#ok<NASGU>
end

function assertEvents(rec,want,what,opts)
arguments
    rec
    want string
    what string
    opts.IgnoreSave (1,1) logical = false
end
got = rec('log');
delete(rec('listeners'));
got = got(got ~= "StatusChanged(message)");
if opts.IgnoreSave, got = got(got ~= "StatusChanged(save)"); end
assert(isequal(reshape(got,1,[]),reshape(want,1,[])),'%s raised [%s], not [%s].',what, ...
    strjoin(got,' -> '),strjoin(want,' -> '));
end

function v = projectValue(m,key,name)
T = m.Project.Sessions;
v = string(T.(name)(string(T.Key) == key));
if isempty(v) || ismissing(v), v = ""; end
end

function [ck,lv] = seriesLevels(m,sk)
S = m.Session;
ck = string(S.seriesConditions(sk));
lp = m.levelParam();
[~,rows] = ismember(ck,string(S.Conditions.Key));
lv = double(S.Conditions.(lp)(rows));
[lv,ix] = sort(lv);
ck = ck(ix);
end

function w = firstPickedWave(m,ck)
P = m.Session.Peaks;
r = find(string(P.Key) == ck & isfinite(P.PeakLatency),1);
assert(~isempty(r),'No picked peak at %s to test the peak commands on.',ck);
w = string(P.Wave(r));
end

function n = undoCount(m)
n = numel(m.undoHistory());
end

function snap = treeSnapshot(root)
% Every file under ROOT: relative path, bytes, modification time.
L = dir(fullfile(root,'**','*'));
L = L(~[L.isdir]);
p = string(fullfile({L.folder},{L.name}));
snap = sortrows(table(p(:),[L.bytes]',[L.datenum]','VariableNames',{'Path','Bytes','Datenum'}),'Path');
end

function P = allPrefs()
% Every MABR pref, as one struct ([] when there are none).
P = [];
try
    if ispref('MABR'), P = getpref('MABR'); end
catch
end
end

function names = changedPrefs(a,b)
names = strings(0,1);
if ~isstruct(a), a = struct(); end
if ~isstruct(b), b = struct(); end
f = union(fieldnames(a),fieldnames(b));
% getpref(group,name,default) ADDS a missing pref holding the default:
% mabr.ui.WindowPos.restore's getpref('MABR','WindowPos_<name>',[]) leaves
% an empty WindowPos_ pref behind on a first open. That is a read, not a
% remembered position, so a new pref holding [] is not counted as written.
for i = numel(f):-1:1
    if ~isfield(a,f{i}) && isfield(b,f{i}) && isempty(b.(f{i})) && startsWith(f{i},'WindowPos_')
        f(i) = [];
    end
end
for i = 1:numel(f)
    if ~isfield(a,f{i}) || ~isfield(b,f{i}) || ~isequaln(a.(f{i}),b.(f{i}))
        names(end+1,1) = string(f{i}); %#ok<AGROW>
    end
end
end

function tf = samePath(a,b)
% Two folder paths name the same folder (separators, case, a trailing slash).
n = @(p) lower(regexprep(replace(string(p),"/","\"),'\\+$',''));
tf = n(a) == n(b);
end

function writeText(file,lines)
% Lines of text to a file (writelines is R2022a+).
fid = fopen(file,'w','n','UTF-8');
assert(fid > 0,'Cannot write %s.',file);
c = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',lines);
end

function closeQuietly(app)
try
    if ~isempty(app) && isvalid(app), delete(app); end
catch
end
end

function c = pickSecond(msg,options)
% A ConfirmFcn that answers the second option (and insists it was asked
% which sessions to write).
assert(contains(string(msg),"which sessions"),'The script menu asked: %s',string(msg));
c = string(options(2));
end
