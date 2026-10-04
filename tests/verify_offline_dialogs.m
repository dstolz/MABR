function verify_offline_dialogs()
% verify_offline_dialogs  The analysis app's dialogs, driven by their Tags with no person at the keyboard.
%
%   Every dialog of the offline analysis app -- SettingsDialog,
%   ExportDialog, BatchDialog, BatchReport, ReviewDialog, LevelsDialog -- is
%   built invisible over a small analysed study (mabrtest.OfflineFixture)
%   and driven the way a user drives it: a control found by its Tag, its
%   Value set, its callback run. Checked:
%
%     A  SettingsDialog: read() is the settings it opened with; an edit is
%        read back and says how much it makes out of date; a value
%        problems() objects to, and one the class refuses, list themselves
%        and disable OK and Apply; Apply hands the edited Settings to the
%        applyFcn and reports; the waves table adds and removes rows; Save
%        As... and Load... round-trip a .mabraset file; a built-in profile
%        and Defaults fill every field; the sound conduction delay row
%        (13 A9): the fields each mode reads are the ones enabled, the
%        readout says "= 0.29 ms", an impossible number disables OK, and one
%        left in a greyed field does not; without an open session the onset
%        bias says so; OK and Apply are disabled while the Model is busy.
%     B  ExportDialog: the estimate per table, the per-table formats (large
%        tables to Parquet, XLSX only where a sheet holds the table, sweeps
%        never CSV), the warnings line and "Export anyway", Export disabled
%        with its reason, an export into tempdir with replicate_analysis.m
%        beside it (13 A7) built with the export's own options (formats,
%        waveform window) -- and without it when unticked -- the options
%        remembered in the pref by the Export button, [Open folder], Write
%        script… (refused under "Current session" with none open),
%        read/write; opened with no root, no folder is suggested.
%     C  BatchDialog: the estimate line, up-to-date sessions skipped, a
%        .mabraset profile, Start -> Model.batch (NumPermutations 50) ->
%        a BatchReport.
%     D  BatchReport: Retry failed re-runs the failed session and replaces
%        its row; Open opens the selected session; Copy; Log.
%     E  ReviewDialog: Start begins a queue with the random order, seed and
%        blind review chosen, holding as many sessions as the dialog said.
%     F  LevelsDialog: Up/Down reorder, OK stores the order (undoable); a
%        number column has none to set.
%     G  Through mabr.ui.AnalysisApp.openDialog: each dialog opens with the
%        arguments the app passes, the settings dialog finds the app's Model
%        (the open session's onset bias, its parameters, the app's
%        setSettings report), follows the project's settings changed
%        elsewhere without overwriting an edit pending, and follows the
%        session opened; deleting the app closes them all.
%     H  Every dialog's Start/OK/Export/Retry is disabled while the Model is
%        busy (a job running) and comes back after it (A3, B, D), and an
%        apply() called anyway refuses rather than throwing; the window
%        position is remembered on every way out (OK, Cancel, the close box,
%        delete). Run right after A3, whose job it shares.
%
%   No hardware, no parallel pool, no modal dialog; tempdir only; every
%   pref a dialog or the app can write is snapshotted and put back
%   (mabrtest.prefGuard); no figure or MABR_Offline* timer is left behind.
%
%   See also mabr.ui.analysis.SettingsDialog, mabr.ui.analysis.ExportDialog,
%   mabr.ui.analysis.BatchDialog, mabr.ui.analysis.BatchReport,
%   mabr.ui.analysis.ReviewDialog, mabr.ui.analysis.LevelsDialog

fprintf('== verify_offline_dialogs ==\n');
t0 = tic;
names = ["Settings","Export","Batch","BatchReport","Review","Levels"];
guardKeys = unique([mabr.ui.AnalysisApp.prefKeys(), "WindowPos_OfflineAnalysis" + names, ...
    "OfflineAnalysisExport","OfflineAnalysisSettings"]);
guard = mabrtest.prefGuard(guardKeys,Clear=true); %#ok<NASGU>

F = mabrtest.OfflineFixture.make();
work = string(tempname);
mkdir(work);
cleanWork = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(work));
m = mabr.ui.analysis.Model('Interactive',false,'AutoRefresh',false, ...
    'ResultsFolderOverride',F.ResultsFolder,'CacheFolder',F.CacheFolder,'SettingsOverride',F.Settings);
cleanModel = onCleanup(@() delete(m));
m.openRoot(F.Root,'SuggestStudyRoot',false);
fprintf('  (fixture and model ready in %.1f s)\n',toc(t0));

% =========================================================================
% A  SettingsDialog
% =========================================================================
rec = containers.Map('KeyType','double','ValueType','any');
picks = containers.Map('KeyType','char','ValueType','any');
picks('file') = "";
pick = @(filter,title,mode,default) picks('file');
d = mabr.ui.analysis.SettingsDialog(F.Settings,@(s) recordApply(rec,s),'Visible',"off", ...
    'Model',m,'PickFileFcn',pick,'Title',"Project settings — test");
fig = d.Figure;
assert(d.isopen() && ~isOn(fig,'Visible') && strcmp(fig.Name,'Project settings — test'), ...
    'The settings dialog did not open invisible with its title.');
assert(isequaln(d.read().toStruct(),F.Settings.toStruct()),'read() is not the settings the dialog opened with.');
for t = ["AnalysisSettingsApply","AnalysisSettingsOK","AnalysisSettingsCancel","AnalysisSettingsDefaults", ...
        "AnalysisSettingsProblems","AnalysisSettingsWindowStart","AnalysisSettingsWindowEnd", ...
        "AnalysisSettingsConductionDelayMode","AnalysisSettingsTimeOffset","AnalysisSettingsOnsetBias"]
    tag(fig,t);
end
okb = tag(fig,'AnalysisSettingsOK');  apb = tag(fig,'AnalysisSettingsApply');
assert(isOn(okb) && ~isOn(apb), 'Unchanged settings: OK on, Apply off expected.');
% the filter response keeps its axis labels however the panel is resized
% (the problems row growing shrinks it): pixel margins, no auto-resize
fa = tag(fig,'AnalysisSettingsFilterAxes');
assert(strcmp(fa.Parent.AutoResizeChildren,'off') && ~isempty(getappdata(fa,'MABRAxesMargins')), ...
    'The filter plot is not held at pixel margins in its panel.');
assert(string(tag(fig,'AnalysisSettingsProblems').Text) == "",'Valid settings listed a problem.');
assert(contains(string(tag(fig,'AnalysisSettingsChanges').Text),"Nothing changed"),'The changes line.');

% an edit is read back, and says what it makes out of date
setv(tag(fig,'AnalysisSettingsWindowStart'),-10);
assert(isequal(d.read().Window,[-10 12]),'The sweep window edit was not read back.');
chg = string(tag(fig,'AnalysisSettingsChanges').Text);
assert(contains(chg,"1 change") && contains(chg,"(Sweep window)") && contains(chg,"re-segmented"), ...
    'The changes line did not say -- in the dialog''s own words -- what the edit makes out of date: %s',chg);
assert(mabr.ui.analysis.SettingsDialog.fieldLabel("ConductionDelayMode") == "Sound conduction delay" && ...
    mabr.ui.analysis.SettingsDialog.fieldLabel("MaxSweepsPerCondition") == "Max sweeps per condition", ...
    'A setting without a label of its own is not named in words.');
assert(isOn(apb),'Apply stayed disabled after an edit.');

% a problem disables OK and Apply; fixing it enables them
d.showTab("Detection & measures");
np = tag(fig,'AnalysisSettingsNumPermutations');
setv(np,10);
pr = string(tag(fig,'AnalysisSettingsProblems').Text);
assert(contains(pr,"permutations is too few"),'problems() was not listed: %s',pr);
assert(~isOn(okb) && ~isOn(apb),'A problem left OK/Apply enabled.');
assert(~d.ok() && d.isopen(),'OK closed the dialog over a problem.');
assert(rec.Count == 0,'The applyFcn ran over a problem.');
setv(np,100);
assert(isOn(okb) && string(tag(fig,'AnalysisSettingsProblems').Text) == "", ...
    'Fixing the problem did not enable OK.');
% a value the class refuses is a problem of its own
d.showTab("Artifacts");
rf = tag(fig,'AnalysisSettingsRejectFactor');
setv(rf,0);
assert(contains(string(tag(fig,'AnalysisSettingsProblems').Text),"RejectFactor") && ~isOn(okb), ...
    'A refused value was not listed as a problem.');
assert(d.read().RejectFactor == F.Settings.RejectFactor,'A refused value reached the settings.');
setv(rf,3);
assert(isOn(okb),'Clearing a refused value did not enable OK.');

% Apply hands the edited settings over and reports
assert(d.apply(),'apply() refused valid settings.');
assert(rec.Count == 1 && isequal(rec(1).Window,[-10 12]),'Apply did not hand the edited settings to the applyFcn.');
rpt = string(tag(fig,'AnalysisSettingsChanges').Text);
assert(startsWith(rpt,"Applied — ") && contains(rpt,"re-segmented"), ...
    'Apply did not report which steps are now out of date: %s',rpt);
assert(~isOn(apb),'Apply stayed enabled with nothing new to apply.');

% the waves table
d.showTab("Peaks");
wt = tag(fig,'AnalysisSettingsWaves');
assert(height(wt.Data) == 5,'The waves table does not hold the five default waves.');
press(tag(fig,'AnalysisSettingsWaveAdd'));
W = d.read().Waves;
assert(numel(W) == 6 && W(6).Name == "A" && height(wt.Data) == 6,'Add wave did not add wave A.');
wt.CellSelectionCallback(wt,struct('Indices',[6 1]));
press(tag(fig,'AnalysisSettingsWaveRemove'));
assert(numel(d.read().Waves) == 5 && height(wt.Data) == 5,'Remove did not remove the selected wave.');
D = wt.Data;  D.Name{1} = '';  wt.Data = D;
wt.CellEditCallback(wt,[]);
assert(contains(string(tag(fig,'AnalysisSettingsProblems').Text),"Wave 1") && ~isOn(okb), ...
    'A wave without a name was not a problem.');
D.Name{1} = 'I';  wt.Data = D;
wt.CellEditCallback(wt,[]);
assert(isOn(okb) && isequal(d.read().Waves,F.Settings.Waves),'The waves did not come back.');

% Save As… and Load… round-trip a .mabraset file
d.showTab("Profiles");
f1 = fullfile(work,"mine.mabraset");
picks('file') = f1;
press(tag(fig,'AnalysisSettingsSaveAs'));
assert(isfile(f1),'Save As… wrote no file.');
saved = mabr.analysis.Settings.load(f1);
assert(isequaln(saved.resultsStruct(),d.read().resultsStruct()),'Save As… did not write the settings shown.');
d.showTab("Detection");
setv(np,200);
assert(d.read().NumPermutations == 200,'NumPermutations edit.');
press(tag(fig,'AnalysisSettingsLoad'));
assert(d.read().NumPermutations == 100 && np.Value == 100,'Load… did not put the file''s settings back.');
mt = tag(fig,'AnalysisSettingsMatches');
assert(contains(string(mt.Text),"no built-in"),'The profile match line: %s',string(mt.Text));
pl = tag(fig,'AnalysisSettingsProfileList');
pl.Value = 'Legacy SCRATCH (2025)';
press(tag(fig,'AnalysisSettingsProfileUse'));
assert(isequaln(d.read().toStruct(),mabr.analysis.Settings.profile("Legacy SCRATCH (2025)").toStruct()), ...
    'Use this profile did not fill every field.');
assert(contains(string(mt.Text),"Legacy SCRATCH"),'The profile match line after a profile.');
assert(np.Value == 2000,'A built tab did not show the profile''s value.');
press(tag(fig,'AnalysisSettingsDefaults'));
assert(isequaln(d.read().toStruct(),mabr.analysis.Settings().toStruct()),'Defaults did not restore the defaults.');
fprintf('  PASS Part A1: SettingsDialog read/write, problems and refused values disable OK/Apply, Apply reports, waves add/remove, Save As/Load round trip, profiles, Defaults\n');

% the sound conduction delay row (13 A9)
d.showTab("Signal");
md = tag(fig,'AnalysisSettingsConductionDelayMode');
cd_ = tag(fig,'AnalysisSettingsConductionDelay');
sd = tag(fig,'AnalysisSettingsSpeakerDistance');
sp = tag(fig,'AnalysisSettingsSpeedOfSound');
ro = tag(fig,'AnalysisSettingsConductionReadout');
assert(md.Value == "none" && ~isOn(cd_) && ~isOn(sd) && ~isOn(sp), ...
    'Mode None should grey every delay field.');
setv(md,'distance');
assert(d.read().ConductionDelayMode == "distance" && isOn(sd) && isOn(sp) && ~isOn(cd_), ...
    'Mode distance: the distance and speed fields should be the enabled ones.');
assert(string(ro.Text) == "= 0.29 ms",'The readout for 10 cm at 343 m/s: "%s".',string(ro.Text));
setv(sd,600);
assert(contains(string(tag(fig,'AnalysisSettingsProblems').Text),"SpeakerDistance") && ~isOn(okb), ...
    'A 600 cm speaker distance did not disable OK.');
setv(sd,20);
assert(string(ro.Text) == "= 0.58 ms" && isOn(okb),'The readout did not follow the distance.');
setv(sp,250);
assert(contains(string(tag(fig,'AnalysisSettingsProblems').Text),"SpeedOfSound") && ~isOn(okb), ...
    'A 250 m/s speed of sound did not disable OK.');
setv(sp,343);
setv(md,'delay');
assert(isOn(cd_) && ~isOn(sd),'Mode delay: only the delay field should be enabled.');
setv(cd_,-0.1);
assert(contains(string(tag(fig,'AnalysisSettingsProblems').Text),"ConductionDelay") && ~isOn(okb), ...
    'A negative delay did not disable OK.');
setv(md,'none');
assert(isOn(okb) && string(ro.Text) == "re onset", ...
    'A bad number in a greyed field blocked OK (mode None reads none of them).');
setv(md,'delay');  setv(cd_,0.3);
assert(string(ro.Text) == "= 0.30 ms" && abs(d.read().latencyOffset() - 0.3) < 1e-12,'The delay readout.');
bias = tag(fig,'AnalysisSettingsOnsetBias');
assert(contains(string(bias.Text),"open a session") && ~isOn(tag(fig,'AnalysisSettingsUseOnsetBias')), ...
    'With no session open the onset bias should say so: "%s".',string(bias.Text));
fprintf('  PASS Part A2: the conduction delay row: fields per mode, live readout (= 0.29 ms), problems disable OK only under the mode that reads them\n');

% OK and Apply are disabled while the Model is busy -- and so are the
% Start/OK of the review, levels and batch dialogs (one job for all four)
for n = ["Review","Levels","Batch"]
    if ispref('MABR',char("WindowPos_OfflineAnalysis" + n)), rmpref('MABR',char("WindowPos_OfflineAnalysis" + n)); end
end
rv = mabr.ui.analysis.ReviewDialog(m,F.Keys(1),'Visible',"off");
l = mabr.ui.analysis.LevelsDialog(m,"Timepoint",'Visible',"off");
b = mabr.ui.analysis.BatchDialog(m,F.Keys(1),'Visible',"off");
setv(tag(b.Figure,'AnalysisBatchSkipCurrent'),false);
setv(tag(fig,'AnalysisSettingsTimeOffset'),0.05);
ctrls = {'ok',okb; 'apply',apb; 'review',tag(rv.Figure,'AnalysisReviewStart'); ...
    'levels',tag(l.Figure,'AnalysisLevelsOK'); 'batch',tag(b.Figure,'AnalysisBatchStart')};
before = cellfun(@(h) string(h.Enable),ctrls(:,2));
assert(all(before == "on"),'Before the job: Settings OK/Apply, Review/Batch Start and Levels OK enabled.');
busy = containers.Map('KeyType','char','ValueType','any');
m.ProgressFcn = @(op,title) probeBusy(busy,ctrls,{'settings',d;'review',rv;'levels',l});
m.rescan();
m.ProgressFcn = @(op,title) silentProgress();
assert(allOff(busy,ctrls(:,1)),'OK/Apply/Start were not disabled while the Model was busy.');
assert(isequal(cellfun(@(h) string(h.Enable),ctrls(:,2)),before),'OK/Apply/Start did not come back after the job.');
% apply() called anyway while the job runs refuses (false) rather than
% throwing the Model's busy error out of a callback
for n = ["settings","review","levels"]
    k = char("apply_" + n);
    got = "(never called)";
    if isKey(busy,k), got = string(busy(k)); end
    assert(isKey(busy,k) && isequal(busy(k),false),'%s apply() while the Model was busy gave %s.',n,got);
end
assert(isempty(m.Queue) && rec.Count == 1,'An apply() refused while busy still did something.');
% OK applies what changed and closes
n0 = rec.Count;
assert(d.ok() && ~d.isopen() && ~isvalid(fig),'OK did not close the dialog.');
assert(rec.Count == n0 + 1 && rec(rec.Count).TimeOffset == 0.05 && isequaln(d.Value,rec(rec.Count)), ...
    'OK did not apply the changes.');
assert(ispref('MABR','WindowPos_OfflineAnalysisSettings'),'OK did not remember the window position.');
delete(d);
% Cancel applies nothing
d = mabr.ui.analysis.SettingsDialog(F.Settings,@(s) recordApply(rec,s),'Visible',"off",'Tab',"Thresholds");
tg = tag(d.Figure,'AnalysisSettingsTabs');
assert(tg.SelectedTab.Title == "Thresholds",'Tab= did not open on the Thresholds tab.');
mth = tag(d.Figure,'AnalysisSettingsThresholdMethod');
assert(mth.Value == "perm-glm" && startsWith(string(tag(d.Figure,'AnalysisSettingsThresholdDefinition').Text),"Threshold"), ...
    'The threshold method dropdown and its definition.');
assert(~isOn(tag(d.Figure,'AnalysisSettingsThresholdModel')),'Custom fields enabled for a named method.');
setv(mth,'custom');
assert(isOn(tag(d.Figure,'AnalysisSettingsThresholdModel')),'Custom fields disabled for Custom.');
n0 = rec.Count;
rmpref('MABR','WindowPos_OfflineAnalysisSettings');
d.cancel();
assert(~d.isopen() && isempty(d.Value) && rec.Count == n0,'Cancel applied something.');
assert(ispref('MABR','WindowPos_OfflineAnalysisSettings'),'Cancel did not remember the window position.');
delete(d);
fprintf('  PASS Part A3: OK/Apply disabled while the Model is busy; OK applies and closes; Cancel applies nothing; Tab=; the method''s custom fields\n');

% =========================================================================
% H  Busy, and the window position on the close box, delete and Cancel
% =========================================================================
f = rv.Figure;
f.CloseRequestFcn(f,[]);
assert(~rv.isopen() && ~isvalid(f) && ispref('MABR','WindowPos_OfflineAnalysisReview'), ...
    'The close box did not close and remember the position.');
delete(rv);
f = l.Figure;
delete(l);
assert(~isvalid(f) && ispref('MABR','WindowPos_OfflineAnalysisLevels'),'delete did not remember the position.');
b.cancel();
assert(~b.isopen() && ispref('MABR','WindowPos_OfflineAnalysisBatch'),'Batch dialog Cancel did not remember the position.');
delete(b);
fprintf('  PASS Part H: Start/OK of every dialog disabled while the Model is busy (A3, B, D), apply() then refuses without throwing; the window position is remembered on OK, Cancel, the close box and delete\n');

% =========================================================================
% B  ExportDialog
% =========================================================================
opened = containers.Map('KeyType','char','ValueType','any');
e = mabr.ui.analysis.ExportDialog(m,'Visible',"off",'Keys',F.Keys(1:2), ...
    'OpenFolderFcn',@(p) recordOpen(opened,p));
fig = e.Figure;
v = e.read();
assert(v.Scope == "selected" && isequal(v.Keys,F.Keys(1:2)),'The scope did not follow the selection.');
assert(isequal(v.Tables,mabr.analysis.Export.DefaultTables) && v.Script && v.RScript, ...
    'The defaults: the default tables, R script and replication script ticked.');
assert(v.Formats.thresholds == "csv" && isequal(v.Formats.waveforms,"parquet"), ...
    'Formats: small tables CSV, large ones Parquet.');
tb = tag(fig,'AnalysisExportTables');
r = find(string(tb.Data.Table) == "thresholds",1);
assert(tb.Data.Rows(r) > 0 && strlength(string(tb.Data.CSV{r})) > 0,'No estimate for the thresholds table.');
r = find(string(tb.Data.Table) == "trial_waves",1);
assert(string(tb.Data.Raw{r}) == "yes",'trial_waves should need raw data.');
assert(contains(string(tag(fig,'AnalysisExportCount').Text),"2 session"),'The scope''s count.');
V = m.projectView();
[~,loc] = ismember(F.Keys(1:2),string(V.Key));
nUn = sum(V.NumSeries(loc) - V.Reviewed(loc));
w = e.warnings();
assert(nUn > 0 && contains(w,sprintf('%d series not reviewed',nUn)),'The warnings line: "%s".',w);
go = tag(fig,'AnalysisExportGo');
assert(go.Text == "Export anyway" && isOn(go),'With warnings Export should read "Export anyway".');
% per-table formats (static)
E = table(["thresholds";"waveforms";"sweeps"],[10;2e6;5e6],[1;1;1],[1;1;1],[true;false;false], ...
    [false;false;true],'VariableNames',{'Table','Rows','CSVBytes','ParquetBytes','XLSXAllowed','NeedsRaw'});
fm = mabr.ui.analysis.ExportDialog.formatsFor(["thresholds","waveforms","sweeps"], ...
    struct('CSV',true,'XLSX',true,'Parquet',false,'MAT',false),E);
assert(isequal(fm.thresholds,["csv","xlsx"]) && isequal(fm.waveforms,"csv") && isempty(fm.sweeps), ...
    'formatsFor: XLSX only where a sheet holds the table, sweeps never CSV.');
fm = mabr.ui.analysis.ExportDialog.formatsFor(["thresholds","waveforms","sweeps"], ...
    struct('CSV',false,'XLSX',false,'Parquet',true,'MAT',true),E);
assert(isequal(fm.thresholds,["parquet","mat"]) && isequal(fm.sweeps,["parquet","mat"]),'formatsFor: Parquet only.');
E2 = table("peaks",2e6,1,1,false,false,'VariableNames',E.Properties.VariableNames);
fm = mabr.ui.analysis.ExportDialog.formatsFor("peaks",struct('CSV',true,'XLSX',true,'Parquet',false,'MAT',false),E2);
assert(isequal(fm.peaks,"csv"),'formatsFor: a sheet table over the row limit still went to XLSX.');
% XLSX and a table too big for a sheet; nothing ticked
setv(tag(fig,'AnalysisExportXLSX'),true);
assert(contains(e.warnings(),"XLSX leaves out waveforms") && ~any(e.read().Formats.waveforms == "xlsx"), ...
    'XLSX was not left out of the waveforms table.');
setv(tag(fig,'AnalysisExportXLSX'),false);
D = tb.Data;  keep = D.Use;  D.Use(:) = false;  tb.Data = D;
tb.CellEditCallback(tb,[]);
assert(~isOn(go) && contains(string(go.Tooltip),"No table"),'Export with nothing ticked was not disabled.');
D.Use = keep;  tb.Data = D;
tb.CellEditCallback(tb,[]);
setv(tag(fig,'AnalysisExportScope'),'current');
assert(~isOn(go) && contains(string(go.Tooltip),"No session is open"),'Scope current with no session.');
setv(tag(fig,'AnalysisExportScope'),'selected');
% read/write round trip
v = e.read();  v.OnlyReviewed = true;  v.WaveformWindow = [-1 8];
e.write(v);
assert(e.read().OnlyReviewed && isequal(e.read().WaveformWindow,[-1 8]) && contains(e.warnings(),"(left out)"), ...
    'write() did not put the options back.');
v.OnlyReviewed = false;  v.WaveformWindow = [-1.5 9];  % (not the default: the script must carry it)
e.write(v);
% the export, through the button
x1 = fullfile(work,"exp1");
setv(tag(fig,'AnalysisExportFolder'),char(x1));
assert(contains(string(tag(fig,'AnalysisExportFolder').Tooltip),x1),'The folder field''s tooltip does not hold the whole path.');
assert(~ispref('MABR','OfflineAnalysisExport'),'The export pref existed before an Export.');
busy = containers.Map('KeyType','char','ValueType','any');
m.ProgressFcn = @(op,title) probeBusy(busy,{'go',go;'script',tag(fig,'AnalysisExportWriteScript')});
press(go);
m.ProgressFcn = @(op,title) silentProgress();
assert(allOff(busy,["go","script"]) && isOn(go),'Export/Write script were not disabled while the export ran.');
assert(isfile(fullfile(x1,"mabr_thresholds.csv")) && isfile(fullfile(x1,"mabr_sessions.csv")), ...
    'The export wrote no CSV tables into %s.',x1);
assert(~isempty(dir(fullfile(x1,"*waveforms*"))),'The waveforms table was not written.');
assert(isempty(dir(fullfile(x1,"mabr_waveforms.csv"))),'The waveforms table went to CSV with Parquet ticked.');
assert(isfile(fullfile(x1,"replicate_analysis.m")),'The replication script was not written beside the export.');
code = string(fileread(fullfile(x1,"replicate_analysis.m")));
assert(contains(code,"mabr.analysis.Export.write") && contains(code,"Session("), ...
    'replicate_analysis.m does not re-analyse and export.');
% built with the same export options: the per-table formats (Parquet for
% the large tables; ScriptWriter's own default is CSV) and the window
assert(contains(code,"""parquet""") && contains(code,mabr.analysis.ScriptWriter.literal([-1.5 9])), ...
    'replicate_analysis.m was not built with the export''s options (formats, waveform window).');
assert(isfile(fullfile(x1,"mabr_import.R")),'The R script was not written.');
assert(ispref('MABR','OfflineAnalysisExport'),'Export did not remember its options.');
dd = mabr.ui.analysis.ExportDialog.loadDefaults();
assert(dd.Script && dd.Parquet && isequal(dd.Tables,mabr.analysis.Export.DefaultTables) && ...
    isequal(dd.WaveformWindow,[-1.5 9]),'The remembered options are not the ones exported with.');
res = string(tag(fig,'AnalysisExportResult').Text);
ob = tag(fig,'AnalysisExportOpenFolder');
assert(contains(res,"Exported") && isOn(ob,'Visible'),'A finished export left no note with Open folder.');
press(ob);
assert(isKey(opened,'last') && opened('last') == string(x1),'Open folder did not open the export folder.');
% without the script (one small table, to keep it quick)
x2 = fullfile(work,"exp2");
v = e.read();  v.Tables = "sessions";  v.Script = false;  v.RScript = false;  v.Folder = x2;
e.write(v);
files = e.apply();
assert(height(files) > 0 && isfile(fullfile(x2,"mabr_sessions.csv")) && ...
    ~isfile(fullfile(x2,"replicate_analysis.m")),'Unticked, the replication script was still written.');
% Write script… under "Current session" with none open: refused, never a
% study script of the in-study sessions in its place
asked = containers.Map('KeyType','char','ValueType','any');
m.PickFileFcn = @(f,t,mo,dflt) recordPick(asked,dflt);
setv(tag(fig,'AnalysisExportScope'),'current');
assert(e.writeScript() == "" && ~isKey(asked,'last') && e.LastScript == "" && ...
    contains(string(tag(fig,'AnalysisExportResult').Text),"No session is open"), ...
    'Write script… under Current session with no session open did not refuse.');
setv(tag(fig,'AnalysisExportScope'),'selected');
% Write script…
sf = fullfile(work,"scripts","two_replicate.m");
m.PickFileFcn = @(f,t,mo,dflt) sf;
press(tag(fig,'AnalysisExportWriteScript'));
assert(isfile(sf) && e.LastScript == string(sf),'Write script… wrote no script.');
m.PickFileFcn = @(f,t,mo,dflt) "";
e.cancel();
assert(~e.isopen() && ispref('MABR','WindowPos_OfflineAnalysisExport'),'Export dialog: Cancel and its position.');
delete(e);
% over a Model with no root: no folder to suggest (never a relative
% exports\<stamp>), Export disabled with a reason, nothing thrown
m0 = mabr.ui.analysis.Model('Interactive',false,'AutoRefresh',false);
e0 = mabr.ui.analysis.ExportDialog(m0,'Visible',"off");
go0 = tag(e0.Figure,'AnalysisExportGo');
assert(string(tag(e0.Figure,'AnalysisExportFolder').Value) == "" && ~isOn(go0) && ...
    strlength(string(go0.Tooltip)) > 0 && isempty(e0.apply()),'The export dialog with no root open.');
delete(e0);  delete(m0);
fprintf('  PASS Part B: ExportDialog estimates, per-table formats, warnings and "Export anyway", disabled with a reason and while busy, export into tempdir with replicate_analysis.m built with its options (and without), options remembered by the button, Open folder, Write script… (refused with no session open), no root\n');

% =========================================================================
% C  BatchDialog
% =========================================================================
s50 = F.Settings;  s50.NumPermutations = 50;  s50.Profile = "fast";
f50 = s50.save(fullfile(work,"batch50.mabraset"));
picks('file') = f50; %#ok<NASGU> (a handle: the pick stub reads it)
rmpref('MABR','WindowPos_OfflineAnalysisBatch');         % (Part H made it)
b = mabr.ui.analysis.BatchDialog(m,F.Keys(1),'Visible',"off",'PickFileFcn',pick);
fig = b.Figure;
st = tag(fig,'AnalysisBatchStart');
assert(contains(b.estimateText(),"1 up to date") && ~isOn(st), ...
    'An up-to-date selection should leave nothing to analyse: "%s".',b.estimateText());
setv(tag(fig,'AnalysisBatchSkipCurrent'),false);
assert(startsWith(b.estimateText(),"1 session · ") && isOn(st),'The estimate: "%s".',b.estimateText());
setv(tag(fig,'AnalysisBatchScope'),'all');
assert(startsWith(b.estimateText(),sprintf('%d sessions · ',numel(F.Keys))),'Scope all: "%s".',b.estimateText());
setv(tag(fig,'AnalysisBatchScope'),'selected');
pf = tag(fig,'AnalysisBatchProfile');
pf.Value = numel(pf.Items);                 % "Settings file…"
pf.ValueChangedFcn(pf,[]);
v = b.read();
assert(v.Profile == "File: batch50.mabraset" && v.Settings.NumPermutations == 50 && isequal(v.Keys,F.Keys(1)), ...
    'The .mabraset profile was not chosen.');
assert(~v.SkipCurrent && ~v.IncludeTestMode && ~v.SummaryFigure && ~v.StopOnError,'read(): the switches.');
press(st);
assert(~b.isopen() && ispref('MABR','WindowPos_OfflineAnalysisBatch'),'Start did not close the dialog.');
assert(~isempty(b.Report) && isvalid(b.Report) && b.Report.isopen(),'Start did not open the batch report.');
T = b.Report.read();
assert(height(T) == 1 && T.Key(1) == F.Keys(1) && startsWith(string(T.Status(1)),"ok"), ...
    'The batch did not analyse the selected session.');
assert(~isempty(m.LastBatch) && isfile(m.LastBatch.LogFile),'The batch wrote no log.');
logFile = string(m.LastBatch.LogFile);
delete(b);                                  % takes its report with it
fprintf('  PASS Part C: BatchDialog estimate, up-to-date sessions skipped, a .mabraset profile, Start -> Model.batch (NumPermutations 50) -> BatchReport\n');

% =========================================================================
% D  BatchReport
% =========================================================================
S0 = table([F.Keys(2);F.Keys(3)],["failed";"ok"],[1.5;2],["boom";""],["";""],["";""], ...
    'VariableNames',cellstr(mabr.analysis.Batch.LogColumns));
r = mabr.ui.analysis.BatchReport(m,S0,logFile,'Visible',"off",'Settings',s50,'OpenFcn',@(f) recordOpen(opened,f));
fig = r.Figure;
sm = string(tag(fig,'AnalysisBatchReportSummary').Text);
assert(contains(sm,"1 failed") && contains(sm,"1 ok"),'The report''s summary line: "%s".',sm);
rb = tag(fig,'AnalysisBatchReportRetry');  obb = tag(fig,'AnalysisBatchReportOpen');
assert(isOn(rb) && ~isOn(obb),'Retry should be on (a failure) and Open off (no selection).');
busy = containers.Map('KeyType','char','ValueType','any');
m.ProgressFcn = @(op,title) probeBusy(busy,{'retry',rb});
press(rb);
m.ProgressFcn = @(op,title) silentProgress();
assert(allOff(busy,"retry"),'Retry failed was not disabled while its batch ran.');
T = r.read();
assert(startsWith(string(T.Status(1)),"ok") && T.Key(1) == F.Keys(2) && height(T) == 2, ...
    'Retry failed did not re-run the failed session and replace its row.');
assert(~contains(string(tag(fig,'AnalysisBatchReportSummary').Text),"failed") && ~isOn(rb), ...
    'After a good retry the report still showed a failure.');
% ... and the Model keeps the MERGED summary and the settings the batch ran
% with, so Batch ▸ Last Batch Report reopens every row and retries alike
LB = m.LastBatch;
assert(~isempty(LB) && height(LB.Summary) == 2 && all(ismember([F.Keys(2);F.Keys(3)],string(LB.Summary.Key))) && ...
    startsWith(string(LB.Summary.Status(string(LB.Summary.Key) == F.Keys(2))),"ok"), ...
    'After a Retry the Model''s LastBatch.Summary is not the merged summary (%d rows).',height(LB.Summary));
assert(isfield(LB,'Settings') && isequaln(LB.Settings,s50),'LastBatch.Settings is not what the retry ran with.');
tbl = tag(fig,'AnalysisBatchReportTable');
if isprop(tbl,'SelectionChangedFcn') && ~isempty(tbl.SelectionChangedFcn)
    mabr.ui.analysis.Compat.setSelectedRows(tbl,2);
    tbl.SelectionChangedFcn(tbl,[]);
else
    tbl.CellSelectionCallback(tbl,struct('Indices',[2 1]));
end
assert(isequal(r.Selected,2) && isOn(obb),'Selecting a row did not enable Open.');
press(obb);
assert(m.SessionKey == F.Keys(3),'Open did not open the selected session.');
txt = r.copy();
assert(startsWith(txt,"Session" + char(9) + "Status" + char(9) + "Seconds") && contains(txt,F.Keys(2)), ...
    'Copy did not copy the table.');
press(tag(fig,'AnalysisBatchReportLog'));
assert(opened('last') == r.LogFile && isfile(r.LogFile),'Log did not open the batch log.');
M = mabr.ui.analysis.BatchReport.merge(S0,table(F.Keys(2),"ok",3,"",'VariableNames',{'Key','Status','Seconds','Message'}));
assert(M.Status(1) == "ok" && M.Seconds(1) == 3 && M.Status(2) == "ok" && height(M) == 2,'BatchReport.merge.');
r.ok();
assert(~r.isopen() && ispref('MABR','WindowPos_OfflineAnalysisBatchReport'),'Batch report: OK and its position.');
delete(r);
fprintf('  PASS Part D: BatchReport Retry failed (disabled while it runs, row replaced -- in the Model''s LastBatch too, with the settings it ran with), Open the selected session, Copy, Log, merge\n');

% =========================================================================
% E  ReviewDialog
% =========================================================================
m.closeSession();
rmpref('MABR','WindowPos_OfflineAnalysisReview');        % (Part H made it)
rv = mabr.ui.analysis.ReviewDialog(m,F.Keys(1:2),'Visible',"off");
fig = rv.Figure;
v = rv.read();
assert(v.Scope == "selected" && isequal(v.Keys,F.Keys(1:2)) && v.UnreviewedOnly && v.Order == "browser" && ...
    v.Seed == 12 && ~v.Blind,'ReviewDialog defaults.');
assert(contains(string(tag(fig,'AnalysisReviewCount').Text),"2 sessions"),'The queue count.');
sdf = tag(fig,'AnalysisReviewSeed');
assert(~isOn(sdf),'The seed is only for a random order.');
setv(tag(fig,'AnalysisReviewScope'),'analysed');
setv(tag(fig,'AnalysisReviewOrder'),'random');
assert(isOn(sdf),'Random order: the seed field should be enabled.');
setv(sdf,7);
setv(tag(fig,'AnalysisReviewBlind'),true);
v = rv.read();
assert(v.Scope == "analysed" && numel(v.Keys) == numel(F.Keys) && v.Order == "random" && v.Seed == 7 && v.Blind, ...
    'ReviewDialog read().');
cnt = string(tag(fig,'AnalysisReviewCount').Text);
press(tag(fig,'AnalysisReviewStart'));
assert(~rv.isopen() && rv.Started,'Start did not start and close.');
q = m.Queue;
assert(~isempty(q) && q.Order == "random" && q.Seed == 7 && q.Blind && m.BlindReview && ...
    m.SessionKey == q.Keys(1),'The review queue was not started as chosen.');
assert(startsWith(cnt,sprintf('%d session',numel(q.Keys))), ...
    'The dialog said "%s" but the queue holds %d session(s).',cnt,numel(q.Keys));
assert(ispref('MABR','WindowPos_OfflineAnalysisReview'),'Review dialog: its position.');
m.endQueue();
delete(rv);
fprintf('  PASS Part E: ReviewDialog Start -> a queue with the random order, seed and blind review chosen, as many sessions as the dialog said\n');

% =========================================================================
% F  LevelsDialog
% =========================================================================
lv0 = mabr.ui.analysis.LevelsDialog.levelsOf(m,"Timepoint");
rmpref('MABR','WindowPos_OfflineAnalysisLevels');        % (Part H made it)
l = mabr.ui.analysis.LevelsDialog(m,"Timepoint",'Visible',"off");
fig = l.Figure;
assert(isequal(l.read(),lv0) && numel(lv0) >= 2,'The levels shown are not the project''s.');
txt = strjoin(string(get(findall(fig,'Type','uilabel'),'Text')),' ');
assert(contains(txt,"Order the timepoints (first at the top)"),'The levels dialog''s sentence: %s',txt);
lb = tag(fig,'AnalysisLevelsList');  up = tag(fig,'AnalysisLevelsUp');  dn = tag(fig,'AnalysisLevelsDown');
assert(~isOn(up) && isOn(dn),'With the first selected only Down should be enabled.');
setv(lb,char(lv0(2)));
press(up);
assert(isequal(l.read(),lv0([2 1 3:end])),'Up did not move the value up.');
press(dn); press(up);
assert(isequal(l.read(),lv0([2 1 3:end])),'Down/Up.');
press(tag(fig,'AnalysisLevelsOK'));
C = m.Project.Columns;
k = find(string(C.Name) == "Timepoint",1);
got = reshape(string(C.Levels{k}),1,[]);
assert(isequal(got(1:2),lv0([2 1])) && ~l.isopen(),'OK did not store the order.');
assert(m.CanUndo && contains(m.UndoLabel,"Timepoint"),'The new order is not undoable.');
m.undo();
C = m.Project.Columns;
got = reshape(string(C.Levels{k}),1,[]);
assert(isequal(got(1:2),lv0(1:2)),'Undo did not restore the order.');
assert(ispref('MABR','WindowPos_OfflineAnalysisLevels'),'Levels dialog: its position.');
delete(l);
m.addColumn("Weight","subject","number");
l = mabr.ui.analysis.LevelsDialog(m,"Weight",'Visible',"off");
assert(~l.IsText && ~isOn(tag(l.Figure,'AnalysisLevelsUp')),'A number column has no order to set.');
assert(~l.ok() && ~l.isopen(),'OK on a number column should just close.');
delete(l);
fprintf('  PASS Part F: LevelsDialog Up/Down, OK stores the order (undoable), a number column has none\n');

% =========================================================================
% G  Through the app
% =========================================================================
clear cleanModel
delete(m);
app = mabr.ui.AnalysisApp(F.Root,'Visible',"off",'Instance',"new",'ResultsFolder',F.ResultsFolder, ...
    'CacheFolder',F.CacheFolder,'Settings',F.Settings,'Restore',false,'RememberState',false, ...
    'ProgressMode',"none",'AutoRefresh',false, ...
    'ConfirmFcn',@(msg,t,o,dflt) string(dflt),'AlertFcn',@(msg,t,i) [], ...
    'PromptFcn',@(p,t,dflt) [],'PickFolderFcn',@(s,t) "",'PickFileFcn',@(f,t,mo,dflt) "");
am = app.Model;
am.openSession(F.Keys(1));
d = app.openDialog("settings");
assert(isa(d,'mabr.ui.analysis.SettingsDialog') && d.Model == am,'The app''s settings dialog did not find its Model.');
fig = d.Figure;
assert(startsWith(string(fig.Name),"Project settings — "),'The settings dialog title.');
bias = string(tag(fig,'AnalysisSettingsOnsetBias').Text);
assert(contains(bias,"+0.078 ms"),'The onset bias of the session''s files: "%s".',bias);
press(tag(fig,'AnalysisSettingsUseOnsetBias'));
assert(abs(d.read().TimeOffset - 0.078125) < 1e-12,'Use it did not fill the time offset.');
d.showTab("Thresholds");
lp = tag(fig,'AnalysisSettingsLevelParam');
assert(any(strcmp(lp.Items,'Level')) && any(strcmp(lp.Items,'Frequency')),'Level parameter: the session''s parameters.');
d.showTab("Detection");
setv(tag(fig,'AnalysisSettingsNumPermutations'),120);
assert(d.apply(),'Apply through the app refused.');
rpt = string(tag(fig,'AnalysisSettingsChanges').Text);
assert(startsWith(rpt,"Settings applied") && contains(rpt,"out of date"),'The app''s setSettings report: "%s".',rpt);
assert(am.Settings.NumPermutations == 120 && abs(am.Settings.TimeOffset - 0.078125) < 1e-12, ...
    'Apply did not make the edited settings the project''s.');
assert(ispref('MABR','OfflineAnalysisSettings'),'The app''s Apply did not remember the settings (Persist).');
% settings changed elsewhere: shown when nothing is pending, never over an edit
npf = tag(fig,'AnalysisSettingsNumPermutations');
s2 = am.Settings;  s2.NumPermutations = 130;
am.setSettings(s2);
assert(npf.Value == 130 && d.read().NumPermutations == 130 && ~isOn(tag(fig,'AnalysisSettingsApply')), ...
    'The dialog did not follow the project''s settings changed elsewhere.');
setv(npf,140);
s2.NumPermutations = 150;  s2.Alpha = 0.04;
am.setSettings(s2);
assert(npf.Value == 140 && d.read().NumPermutations == 140 && d.read().Alpha == 0.05 && ...
    contains(string(tag(fig,'AnalysisSettingsChanges').Text),"Permutations") && ...
    ~contains(string(tag(fig,'AnalysisSettingsChanges').Text),"NumPermutations"), ...
    'A change made elsewhere overwrote the edit pending in the dialog.');
% another session: its onset bias
am.closeSession();
assert(contains(string(tag(fig,'AnalysisSettingsOnsetBias').Text),"open a session"), ...
    'The onset bias did not follow the session closing.');
am.openSession(F.Keys(1));
assert(contains(string(tag(fig,'AnalysisSettingsOnsetBias').Text),"+0.078 ms"), ...
    'The onset bias did not follow the session opening.');
dlg = {d, app.openDialog("export"), app.openDialog("batch"), app.openDialog("review"), app.openDialog("levels")};
cls = ["SettingsDialog","ExportDialog","BatchDialog","ReviewDialog","LevelsDialog"];
for k = 1:numel(dlg)
    assert(isa(dlg{k},"mabr.ui.analysis." + cls(k)) && dlg{k}.isopen() && ~isOn(dlg{k}.Figure,'Visible'), ...
        'openDialog did not open an invisible %s.',cls(k));
end
assert(isempty(app.openDialog("batchReport")),'No batch has run in this app: no report.');
% Export… from the menu, the toolbar or Ctrl+E carries the selection, as
% Batch and Review do: the "Selected sessions" scope is never empty
ek = dlg{2}.Keys;
assert(~isempty(ek) && all(ismember(ek,string(am.Catalog.Sessions.Key))) && ...
    (any(ek == am.SessionKey) || dlg{2}.read().Scope == "selected"), ...
    'The export dialog opened from the app has no selection to export.');
% Batch ▸ Last Batch Report: with the settings the batch ran with
sOther = F.Settings;  sOther.NumPermutations = 50;  sOther.Profile = "fast";
am.batch(F.Keys(2),SkipCurrent=true,Settings=sOther);
rr = app.openDialog("batchReport");
assert(isa(rr,'mabr.ui.analysis.BatchReport') && isequaln(rr.Settings,sOther) && height(rr.read()) == 1, ...
    'The reopened batch report does not retry with the settings the batch ran with.');
dlg{end+1} = rr;
figs = cellfun(@(x) x.Figure,dlg,'UniformOutput',false);
delete(app);
assert(all(cellfun(@(f) ~isvalid(f),figs)),'Deleting the app left a dialog open.');
fprintf('  PASS Part G: AnalysisApp.openDialog opens every dialog; the settings dialog uses the app''s Model (onset bias +0.078 ms, Use it, parameters, setSettings report, settings changed elsewhere, the session opened); Export… carries the selection; Last Batch Report retries with the batch''s settings; deleting the app closes them\n');

% ---- nothing left behind ------------------------------------------------
left = findall(groot,'Type','figure');
left = left(startsWith(string(get(left,{'Tag'})),"MABR_OFFLINE"));
assert(isempty(left),'%d analysis window(s) left open.',numel(left));
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,{'Tag'})),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
fprintf('== verify_offline_dialogs PASSED (%.1f s) ==\n',toc(t0));
end

% =========================================================================
function h = tag(fig,name)
h = findall(fig,'Tag',char(name));
assert(isscalar(h),'Expected one control tagged %s, found %d.',name,numel(h));
end

function setv(h,v)
% A control's Value, as a user sets it, then its callback.
h.Value = v;
if ~isempty(h.ValueChangedFcn), h.ValueChangedFcn(h,[]); end
end

function press(h)
h.ButtonPushedFcn(h,[]);
end

function tf = isOn(h,prop)
% An on/off property (Enable unless named) as a logical.
if nargin < 2, prop = 'Enable'; end
tf = logical(h.(prop));
end

function recordApply(rec,s)
% The applyFcn stub: returns nothing, so the dialog reports for itself.
rec(rec.Count + 1) = s; %#ok<NASGU> (a containers.Map: a handle)
end

function recordOpen(rec,p)
rec('last') = string(p); %#ok<NASGU>
end

function h = probeBusy(rec,ctrls,dlgs)
% A ProgressFcn that notes, as the job starts (the Model already busy), the
% Enable of each named control: ctrls = {name, handle; ...}; and, for each
% dialog of dlgs = {name, dialog; ...}, what its apply() returned then
% (rec("apply_<name>"); the error identifier when it threw).
if nargin < 3, dlgs = cell(0,2); end
for k = 1:size(ctrls,1)
    rec(ctrls{k,1}) = string(ctrls{k,2}.Enable);
end
for k = 1:size(dlgs,1)
    key = ['apply_' dlgs{k,1}];
    try
        rec(key) = dlgs{k,2}.apply();
    catch me
        rec(key) = "threw " + string(me.identifier);
    end
end
h = silentProgress();
end

function p = recordPick(rec,dflt)
% A PickFileFcn that notes it was asked (and cancels).
rec('last') = string(dflt); %#ok<NASGU>
p = "";
end

function tf = allOff(rec,names)
% Every named control was seen disabled by probeBusy.
tf = all(cellfun(@(n) isKey(rec,n) && rec(n) == "off",cellstr(names)));
end

function h = silentProgress()
h = struct('update',@(text,frac) [],'cancelled',@() false,'close',@() []);
end
