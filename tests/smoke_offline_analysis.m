function smoke_offline_analysis(root)
% smoke_offline_analysis  The offline analysis on a real study folder, which it never changes.
%
%   The verify_offline_* scripts hold every class to synthetic files whose
%   truth is known. This is the other half: the same classes and the same
%   window over a REAL study, the reference rig's SUBJ-ID-1254 sitting of
%   1 October 2026 -- tones and clicks, conventional and intermixed runs,
%   compact files, a noise series, a two-file sitting of single levels, and
%   runs stopped early -- so that what was built against the contract is
%   seen to hold on the data it was built for. It is not a verify_* script:
%   it needs that folder, which only some machines have, so the suite and
%   the Test Runner do not run it. Without the folder it says so and
%   returns.
%
%   THE DATA ARE READ-ONLY. Nothing is written under ROOT: the catalog's
%   cache, every results file, the project, the batch log, the exports and
%   the analysis window's saves all go to tempname folders removed on the
%   way out, and the whole tree is snapshot (relative path, bytes, modified
%   time, folders included) before and after and must come back identical --
%   in particular no MABR_Analysis folder anywhere under it. Every
%   preference the analysis window may write is put back
%   (mabrtest.prefGuard over mabr.ui.AnalysisApp.prefKeys()).
%
%   Steps (each prints PASS, a few print the numbers they found):
%     1  snapshot the tree; guard the prefs
%     2  Catalog.suggestStudyRoot(<root>/SUBJ-ID-1254) is ROOT
%     3  Catalog scan: 6 sessions under SUBJ-ID-1254, 202 files, stimuli
%        Tone, ClickTrain and Noise, the 54 compact files of 140000's
%        intermixed run, and 142240's 15-sweep click file a short run (in
%        the catalog's ShortRuns and in Session.Files.Short)
%     4  140000 (tones and clicks, both acquisition modes) segments: 12 tone
%        series (6 frequencies x 2 modes) and 1 click series, its
%        interleaved conditions windowed over [0 9.917] ms
%     5  Batch.run over all six sessions with Settings(NumPermutations=200,
%        SplitHalfResamples=100) into the tempdir results store: every
%        status "ok" or "ok (no thresholds)"; 140820's single-level series
%        flagged "insufficient levels" -- "insufficient", or "all-respond"
%        left-censored at 80 dB where that one level responds (both do),
%        never "no-response"; 140845's thresholds printed by the primary
%        method (perm-glm) and by perm-descending from the stored
%        per-condition columns, perm-glm's 1-16 kHz finite inside [0 80] dB
%        and 32 kHz right-censored or at least 60 dB
%     6  every results-only table exported as CSV and Parquet: each CSV
%        reads back with as many rows as were written, and none holds the
%        text NaN or Inf
%     7  the analysis window (invisible, every dialog stubbed): 140845
%        opened, every tab shown, the 8 kHz series opened in Series, its
%        fit accepted, the save flushed to the tempdir results file, closed
%     8  the tree snapshot again: identical, no MABR_Analysis under ROOT
%
%   Run:  >> smoke_offline_analysis
%         >> smoke_offline_analysis("D:\copy\of\OFC_NoiseExposure")
%
%   About two minutes on the reference machine. No hardware, no parallel
%   pool, no modal dialog.
%
%   See also mabr.analysis.Catalog, mabr.analysis.Batch, mabr.analysis.Export,
%   mabr.ui.AnalysisApp, verify_offline_app.
%
% Daniel Stolzberg (c) 2026

arguments
    root (1,1) string = "C:/Users/dstolz/My Drive/PROJECTS/OFC_NoiseExposure"
end

fprintf('== smoke_offline_analysis ==\n');
if ~isfolder(root)
    fprintf('  SKIP: the study folder "%s" is not on this machine.\n',root);
    return
end
T0 = tic;
subj = "SUBJ-ID-1254";
key  = @(stamp) subj + "/" + subj + "_261001T" + stamp;

% ---- 1. the tree as it is, and the prefs as they are ----------------------
before = treeSnapshot(root);
assert(height(before) > 0,'the snapshot of "%s" found nothing',root);
g = mabrtest.prefGuard(mabr.ui.AnalysisApp.prefKeys()); %#ok<NASGU>
tmp = string(tempname);
mkdir(tmp);
cleanTmp = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(tmp));
cacheF   = fullfile(tmp,"cache");
results  = fullfile(tmp,"results");
exportF  = fullfile(tmp,"export");
timersBefore = timerfindall();
figsBefore   = findall(groot,'Type','figure');
fprintf('  PASS 1: %d entries under the study snapshot; prefs guarded; scratch in %s\n', ...
    height(before),tmp);

% ---- 2. the study-folder suggestion ----------------------------------------
sug = mabr.analysis.Catalog.suggestStudyRoot(fullfile(root,subj));
assert(sameFolder(sug,root), ...
    'suggestStudyRoot of the subject folder gave "%s", expected the study folder "%s"',sug,root);
fprintf('  PASS 2: opening %s suggests the study folder instead\n',subj);

% ---- 3. the catalog --------------------------------------------------------
t = tic;
c = mabr.analysis.Catalog(root,'CacheFolder',cacheF,'ResultsFolder',results);
c.scan();
S = c.Sessions;
F = c.Files;
assert(sameFolder(c.AnalysisRoot,root),'AnalysisRoot is "%s", expected the study folder',c.AnalysisRoot);
assert(height(S) == 6 && all(S.Subject == subj), ...
    'expected 6 sessions of %s, found %d (%s)',subj,height(S),strjoin(unique(S.Subject),', '));
assert(all(startsWith(S.Key,subj + "/")),'a session key is not under %s/',subj);
assert(height(F) == 202 && all(F.Ok), ...
    'expected 202 readable .abr files, found %d (%d unreadable)',height(F),sum(~F.Ok));
stim = unique(F.Stimulus);
assert(isequal(sort(stim),sort(["ClickTrain";"Noise";"Tone"])), ...
    'stimuli found: %s; expected ClickTrain, Noise and Tone',strjoin(stim,', '));
in0 = F.SessionKey == key("140000");
nCompact = sum(in0 & F.Layout == "compact");
assert(nCompact == 54,'140000 holds %d compact files, expected 54',nCompact);
assert(all(F.AcqMode(in0 & F.Layout == "compact") == "interleaved"), ...
    'a compact file of 140000 is not AcqMode interleaved');
counts = arrayfun(@(k) sum(F.SessionKey == k),S.Key);
fprintf('       sessions (files): %s\n',strjoin(extractAfter(S.Key,"T") + " (" + counts + ")",', '));
r40 = S.Key == key("142240");
assert(S.ShortRuns(r40) == 1,'142240 should hold one short run, the catalog says %d',S.ShortRuns(r40));
assert(all(S.ShortRuns(~r40) == 0),'only 142240 should hold a short run: %s', ...
    strjoin(S.Key(S.ShortRuns > 0),', '));
f15 = F(F.SessionKey == key("142240") & F.NumSweeps == 15,:);
assert(height(f15) == 1 && f15.Stimulus == "ClickTrain", ...
    '142240 should hold exactly one 15-sweep click file');
s40 = mabr.analysis.Session(S.Path(r40),'Verbose',false,'KeepTraces',false);
short = s40.Files.fileName(s40.Files.Short);
assert(isscalar(short) && short == f15.FileName, ...
    'Session.Files.Short should mark the 15-sweep file alone, it marks: %s',strjoin(short,', '));
assert(c.LastScanReads == 202,'the first scan should open every file, it opened %d',c.LastScanReads);
fprintf('  PASS 3: 6 sessions, 202 files, %s; 54 compact in 140000; %s short (%.1f s)\n', ...
    strjoin(sort(stim),'/'),f15.FileName,toc(t));

% ---- 4. 140000: both acquisition modes, tones and clicks -------------------
t = tic;
s0 = mabr.analysis.Session(S.Path(S.Key == key("140000")),'Verbose',false,'KeepTraces',false);
s0.segment();
C = s0.Conditions;
assert(isequal(sort(s0.AcqModes),["conventional","interleaved"]), ...
    '140000''s acquisition modes are %s',strjoin(s0.AcqModes,', '));
sk = s0.seriesKeys();
isTone  = contains(sk,"Stimulus=Tone");
isClick = contains(sk,"Stimulus=ClickTrain");
assert(sum(isTone) == 12 && sum(isClick) == 1 && numel(sk) == 13, ...
    'expected 12 tone series and 1 click series, found %d tone, %d click of %d:\n  %s', ...
    sum(isTone),sum(isClick),numel(sk),strjoin(sk,newline + "  "));
assert(sum(isTone & contains(sk,"AcqMode=interleaved")) == 6, ...
    'expected one interleaved tone series per frequency');
il = C.AcqMode == "interleaved";
assert(sum(il) == 54,'expected 54 interleaved conditions, found %d',sum(il));
assert(all(C.Processing(il) == "windowed") && all(C.Processing(~il) == "continuous"), ...
    'interleaved conditions must be windowed and the rest continuous');
ext = C.Extent(il,:);
assert(all(abs(ext(:,1)) < 1e-9) && all(abs(ext(:,2) - 119/12) < 1e-3), ...
    'interleaved Extent should be [0 9.917] ms, found [%g %g]..[%g %g]', ...
    min(ext(:,1)),min(ext(:,2)),max(ext(:,1)),max(ext(:,2)));
fprintf('  PASS 4: 140000 segments into 12 tone + 1 click series; 54 windowed over [0 9.917] ms (%.1f s)\n',toc(t));
clear s0 s40

% ---- 5. the batch ----------------------------------------------------------
t = tic;
settings = mabr.analysis.Settings('NumPermutations',200,'SplitHalfResamples',100);
p = mabr.analysis.Project.open(string(c.ResultsFolder));
p.ensureSessions(c);
items = p.batchItems(S.Key,c);
B = mabr.analysis.Batch.run(items,settings,'SkipCurrent',false,'Project',p, ...
    'LogFile',string(fullfile(results,'logs','smoke_batch.csv')));
p.save();
disp(B(:,{'Key','Status','Seconds','Message'}));
assert(height(B) == 6,'the batch reported %d sessions, expected 6',height(B));
assert(all(ismember(B.Status,["ok","ok (no thresholds)"])), ...
    'every session should analyse: %s',strjoin(B.Key(~ismember(B.Status,["ok","ok (no thresholds)"])) + ...
    " " + B.Status(~ismember(B.Status,["ok","ok (no thresholds)"])),'; '));
assert(all(isfile(B.ResultsFile)) && all(startsWith(lower(B.ResultsFile),lower(results))), ...
    'every results file must exist, in the tempdir store');
% 140820 recorded one level (80 dB) per series. One level cannot say where
% a response starts: "insufficient" -- or, when that level responds,
% "all-respond", left-censored at it (SeriesThreshold step 3) -- each
% flagged "insufficient levels", and never "no-response".
R20 = mabr.analysis.Session.fromResults(B.ResultsFile(B.Key == key("140820")));
T20 = R20.Thresholds;
assert(height(T20) == 2 && all(T20.NumLevels == 1), ...
    '140820 should give two series of one level each (%d series)',height(T20));
assert(all(ismember(T20.Status,["insufficient","all-respond"])) && ...
    all(contains(T20.Flags,"insufficient levels")) && ...
    all(T20.Status == "insufficient" | (T20.FinalCensored == "left" & T20.Final == 80)), ...
    '140820''s single-level series should be insufficient (or all-respond at 80 dB), found %s', ...
    strjoin(T20.Status,', '));
fprintf('       140820 (one level each): %s\n',strjoin(T20.Status + " (" + ...
    arrayfun(@(r) mabr.ui.analysis.Style.formatThreshold(T20(r,:)),(1:height(T20)).') + ")",', '));
% 140845: the primary method's Finals, and perm-descending's beside them
k45 = key("140845");
ex = p.exportItems(k45,c);
X = mabr.analysis.Export.tables(ex,'Tables',"thresholds",'ThresholdsAll',true, ...
    'IncludeExcluded',true);
X = X.thresholds;
glm  = sortrows(X(X.is_primary & X.method == "perm-glm",:),'frequency_khz');
desc = sortrows(X(X.method == "perm-descending",:),'frequency_khz');
assert(height(glm) == 6 && height(desc) == 6, ...
    '140845 should give six series by each method (perm-glm %d, perm-descending %d)', ...
    height(glm),height(desc));
fprintf('       140845 thresholds (dB), by frequency:\n');
fprintf('         kHz   perm-glm (primary)        perm-descending\n');
for i = 1:6
    fprintf('       %5g   %-24s  %s\n',glm.frequency_khz(i),thrText(glm(i,:)),thrText(desc(i,:)));
end
lo = glm.frequency_khz <= 16;
assert(all(isfinite(glm.threshold_db(lo))) && all(glm.cens(lo) == "none" | glm.cens(lo) == "interval"), ...
    'perm-glm should give a finite threshold at 1-16 kHz');
assert(all(glm.threshold_db(lo) >= 0 & glm.threshold_db(lo) <= 80), ...
    'perm-glm''s 1-16 kHz thresholds should lie inside the levels tested, [0 80] dB');
g32 = glm(glm.frequency_khz == 32,:);
assert(g32.cens == "right" || g32.threshold_db >= 60, ...
    'perm-glm at 32 kHz should be right-censored or at least 60 dB, it is %s',thrText(g32));
fprintf(['  PASS 5: 6 sessions analysed (%s); 140820''s single-level series %s; 140845 as ' ...
    'printed (%.1f s)\n'],strjoin(unique(B.Status),', '),strjoin(unique(T20.Status),'/'),toc(t));

% ---- 6. export -------------------------------------------------------------
t = tic;
want = [mabr.analysis.Export.DefaultTables "trials"];
items = p.exportItems(S.Key,c);
assert(numel(items) == 6,'every session should have results to export, %d do',numel(items));
T = mabr.analysis.Export.tables(items,'Tables',want,'IncludeExcluded',true);
files = mabr.analysis.Export.write(T,exportF,'Formats',["csv","parquet"]);
csv = files(files.Format == "csv" & files.File ~= "",:);
assert(all(ismember(want,csv.Table)),'a table was not written as CSV: %s', ...
    strjoin(setdiff(want,csv.Table),', '));
bad = strings(0,1);
for i = 1:height(csv)
    rt = readtable(csv.File(i),'TextType','string','Delimiter',',');
    assert(height(rt) == csv.Rows(i),'%s: wrote %d rows, read %d back',csv.Table(i),csv.Rows(i),height(rt));
    txt = fileread(csv.File(i));
    if ~isempty(regexp(txt,'(^|,)"?-?(NaN|Inf)"?(,|\r?$)','once','lineanchors'))
        bad(end+1,1) = csv.Table(i); %#ok<AGROW>
    end
end
assert(isempty(bad),'NaN or Inf written as text in: %s',strjoin(bad,', '));
pq = files(files.Format == "parquet" & files.File ~= "",:);
nPq = 0;
for i = 1:height(pq)
    if isfile(pq.File(i))
        parquetread(pq.File(i));
        nPq = nPq + 1;
    elseif isfolder(pq.File(i))
        d = dir(fullfile(pq.File(i),'**','*.parquet'));
        for j = 1:numel(d), parquetread(fullfile(d(j).folder,d(j).name)); nPq = nPq + 1; end
    end
end
assert(height(pq) == numel(want),'a table was not written as Parquet: %s', ...
    strjoin(setdiff(want,pq.Table),', '));
fprintf('       rows: %s\n',strjoin(csv.Table + " " + csv.Rows,', '));
fprintf('  PASS 6: %d tables as CSV (read back, no NaN/Inf text) and Parquet (%d files read back) (%.1f s)\n', ...
    height(csv),nPq,toc(t));

% ---- 7. the analysis window ------------------------------------------------
t = tic;
app = mabr.ui.AnalysisApp(root,'Visible',"off",'Instance',"new", ...
    'ResultsFolder',results,'CacheFolder',cacheF,'Restore',false,'RememberState',false, ...
    'ProgressMode',"none",'AutoRefresh',false,'Settings',settings, ...
    'ConfirmFcn',@(~,~,options,default) string(default), ...
    'AlertFcn',@(varargin) [],'PromptFcn',@(varargin) [], ...
    'PickFolderFcn',@(varargin) "",'PickFileFcn',@(varargin) "");
cleanApp = onCleanup(@() deleteQuietly(app));
m = app.Model;
assert(~isempty(m.Catalog) && sameFolder(m.Catalog.Root,root),'the window did not open the study');
app.openSession(k45);
assert(m.SessionKey == k45 && m.SessionSource == "results", ...
    '140845 should open from its results (opened "%s" from "%s")',m.SessionKey,m.SessionSource);
for tab = mabr.ui.AnalysisApp.TabNames
    app.activateTab(tab);
    v = app.Views.(tab);
    assert(~isempty(v) && isa(v,char(mabr.ui.AnalysisApp.viewClass(tab))), ...
        'the %s tab did not build its view',tab);
    app.flush();
end
keys = m.seriesKeys();
s8 = keys(~cellfun(@isempty,regexp(keys,'(^|\|)Frequency=8(\||$)','once')) & ...
    contains(keys,"Stimulus=Tone"));
assert(isscalar(s8),'expected one 8 kHz tone series, found %d',numel(s8));
m.selectSeries(s8);
app.activateTab("Series");
resFile = B.ResultsFile(B.Key == k45);
d0 = dir(resFile);
m.acceptFit(s8);
row = m.Session.Thresholds.Key == s8;
assert(m.Session.Thresholds.Decision(row) == "accepted",'the 8 kHz fit was not accepted');
app.flush();
assert(m.SaveState == "saved",'the save did not complete (SaveState "%s")',m.SaveState);
d1 = dir(resFile);
assert(d1.datenum > d0.datenum || d1.bytes ~= d0.bytes,'the accepted fit was not written to %s',resFile);
R45 = mabr.analysis.Session.fromResults(resFile);
assert(R45.Thresholds.Decision(R45.Thresholds.Key == s8) == "accepted", ...
    'the results file does not hold the acceptance');
fprintf('       8 kHz: %s, accepted\n',mabr.ui.analysis.Style.formatThreshold(R45.Thresholds(R45.Thresholds.Key == s8,:)));
app.close();
drawnow
assert(~isvalid(app) || isempty(app.Figure) || ~isvalid(app.Figure),'the window did not close');
clear cleanApp
leftT = setdiff(timerfindall(),timersBefore);
leftT = leftT(arrayfun(@(x) startsWith(string(get(x,'Tag')),"MABR_Offline"),leftT));
assert(isempty(leftT),'%d MABR_Offline timer(s) left running',numel(leftT));
leftF = setdiff(findall(groot,'Type','figure'),figsBefore);
assert(isempty(leftF),'%d figure(s) left open',numel(leftF));
fprintf('  PASS 7: the window opened 140845, showed every tab, accepted 8 kHz and saved it (%.1f s)\n',toc(t));

% ---- 8. the data are as they were ------------------------------------------
after = treeSnapshot(root);
store = after.Path(contains(after.Path,"MABR_Analysis"));
assert(isempty(store),'a results store appeared under the data: %s',strjoin(store,', '));
[same,diffs] = sameSnapshot(before,after);
assert(same,'the data tree changed:\n  %s',strjoin(diffs,newline + "  "));
fprintf('  PASS 8: %d entries under the study, unchanged; no MABR_Analysis under it\n',height(after));

fprintf('== smoke_offline_analysis PASSED (%.0f s) ==\n',toc(T0));
end

% ===========================================================================
function T = treeSnapshot(root)
% Every file and folder under ROOT: relative path, bytes, modified time.
d = dir(fullfile(root,'**','*'));
d = d(~ismember({d.name},{'.','..'}));
full = string(fullfile({d.folder},{d.name})).';
base = string(fullfile(char(root)));
rel  = erase(full,base);
rel  = regexprep(rel,'^[\\/]+','');
T = table(rel,[d.isdir].',[d.bytes].',[d.datenum].', ...
    'VariableNames',{'Path','IsDir','Bytes','DateNum'});
T = sortrows(T,'Path');
end

function [same,diffs] = sameSnapshot(A,B)
% Do two snapshots agree? DIFFS names what does not.
diffs = strings(0,1);
gone  = setdiff(A.Path,B.Path);
added = setdiff(B.Path,A.Path);
diffs = [diffs; "removed: " + gone; "added: " + added];
[both,ia,ib] = intersect(A.Path,B.Path);
chg = A.Bytes(ia) ~= B.Bytes(ib) | A.DateNum(ia) ~= B.DateNum(ib);
diffs = [diffs; "changed: " + both(chg)];
same = isempty(diffs);
end

function tf = sameFolder(a,b)
% The same folder, however its separators and case are written.
n = @(p) lower(regexprep(strrep(char(p),'/','\'),'\\+$',''));
tf = strcmp(n(a),n(b));
end

function s = thrText(r)
% One exported threshold row as text: "35 (30-40]", ">80 (no response)".
switch r.cens
    case "interval", s = sprintf('%g (%g-%g]',r.threshold_db,r.thr_lo_db,r.thr_hi_db);
    case "right",    s = sprintf('>%g (no response)',r.threshold_db);
    case "left",     s = sprintf('<=%g (all respond)',r.threshold_db);
    case "none",     s = sprintf('%.1f',r.threshold_db);
    otherwise,       s = sprintf('- (%s)',r.fit_status);
end
end

function deleteQuietly(app)
try
    if ~isempty(app) && isvalid(app), delete(app); end
catch
end
end
