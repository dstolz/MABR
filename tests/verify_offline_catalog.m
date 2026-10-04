function verify_offline_catalog()
% verify_offline_catalog  Study discovery offline: mabr.analysis.Catalog (and, from W2, Project), no hardware.
%
%   A Catalog is the offline analysis's index of a data folder: every .abr
%   under it read for its metadata, one row per session folder, and where
%   each session's results go. Everything here is held against a study tree
%   mabrtest.SyntheticABR wrote, so every count, day and label is known:
%
%     study/SUBJ-ID-1254/  _Baseline, _2weeks, _261001T140000 (tones and
%                          clicks, conventional and intermixed, notes and a
%                          journal -- plus a 16-sweep click run added later,
%                          a short run)
%     study/SUBJ-ID-959/   _Baseline, _2weeks, _stimgen (stimgen-named files
%                          spelling the subject SUBJ_ID_959, with a Test Mode
%                          file), _TestOnly (a copy of that Test Mode file
%                          alone), MABR_Analysis/ (a planted results store
%                          with one results file and a stray .abr)
%     study/Pilot/run_old  "old"-named clicks under no subject folder, a
%                          corrupt .abr and one that is not a recording
%     study/.trash         a hidden folder holding a copy of a recording, and
%     study/$RECYCLE.BIN   Windows' own, holding another
%     study2/MABR_Analysis/project.mat with SUBJ-ID-77/SUBJ-ID-77_Baseline
%                          below it, whose notes exist only in a journal
%     rates/SUBJ-ID-31     (Part G) one real file and two Test Mode files
%                          at twice its sample rate
%
%   Part A  sessions: keys, natural subject order, days, start and stop,
%           counts, the summary text, acquisition modes, short runs, Test
%           Mode none/some/all, units, notes files, inferred labels; files:
%           columns, canonical subjects (defect 16), unreadable and skipped
%           files, the cross-folder duplicate, hidden folders and stores
%           never listed -- and nothing written under the study
%   Part B  notes: a file's notebook de-duplicated and scoped to the session;
%           the journal fallback with times rebuilt from its header (run and
%           sweep from the stamp, an elapsed stamp, midnight); no notes
%   Part C  where results go: resultsFile for a key, ".", and a pool; bad
%           keys; AnalysisRoot at an ancestor's store and at the folder's
%           own; a ResultsFolder override; a cache folder inside the
%           AnalysisRoot refused; a drive root's "." results file; nested
%           stores; suggestStudyRoot; inferLabel
%   Part D  the cache: a rescan opens only the file that could not be
%           loaded (never cached: that failure may be the moment's); one
%           touched file is read again; a cached load failure is retried and
%           healed; another ReaderVersion or CacheVersion, a corrupt cache, a
%           cache of another folder and changed record fields are each
%           rebuilt silently; ReadMetadata false; a cache folder inside the
%           data is refused -- every scan leaving the study byte-for-byte
%           as it was
%   Part E  progress and cancel: the sink's calls, a cancelled scan changes
%           nothing on the object but keeps what it read; argument errors
%   Part F  static scan: no Statistics Toolbox function in Catalog.m
%   Part G  every session's included files, sweeps, conditions, units,
%           modes and short runs against mabr.analysis.Session over the same
%           folder -- including one real file beside two Test Mode files at
%           another rate, where the order of Session's rules decides
%   Project P1-P10  mabr.analysis.Project over the same study, with hand-made
%           results files in a store redirected into the temporary folder:
%           open/ensureSessions/view write nothing, Timepoints by the same-day
%           rule, Test Mode out of the study (defect 17); labels routed by
%           level with case/space coercion; free columns and Levels; pools;
%           atomic reload-merge-write save and read-only newer formats; view
%           statuses none/current/stale/failed; aggregate under each
%           DuplicatePolicy with UsedInStudy; aggregate's per-file cache
%           (P7b) equal to a freshly opened project's tables after label
%           edits and a rewritten results file; exportItems and batchItems
%           (incl. the A9 conduction-delay override); importStore
%
%   Everything is written under one tempname folder, removed on the way out.
%   No preference is read or written, no figure opened, and the global random
%   stream is never drawn from (asserted).
%
%   Run:  >> verify_offline_catalog
%
%   See also mabr.analysis.Catalog, mabr.analysis.AbrFile,
%   mabrtest.SyntheticABR.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_catalog ==\n');
tAll  = tic;
rng0  = rng;
figs0 = findall(groot,'Type','figure');
work  = string(tempname);
mkdir(work);
cleanup = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(work));

TIMES = string(char(215));               % the summary's multiplication sign
MID   = string(char(183));               % and its separator
Cat   = 'mabr.analysis.Catalog';

% =========================================================================
%  The trees
% =========================================================================
tBuild = tic;
truth = mabrtest.SyntheticABR.defaults();
study = fullfile(work,"study");
info  = mabrtest.SyntheticABR.writeStudy(study,truth,Subjects=["SUBJ-ID-1254" "SUBJ-ID-959"],Mixed=true);
SP    = @(folder) info.Sessions.Path(info.Sessions.Folder == folder);
SI    = @(folder) info.SessionInfo(info.Sessions.Folder == folder);
mixedName = "SUBJ-ID-1254_261001T140000";
mixed = SP(mixedName);
mi    = SI(mixedName);

% A run stopped early: 16-sweep clicks, a second Start in the mixed folder.
tShort = truth;  tShort.nSweeps = 16;  tShort.Seed = truth.Seed + 777;
mabrtest.SyntheticABR.writeSession(mixed,tShort,Subject="SUBJ-ID-1254", ...
    Start=datetime(2026,10,1,15,0,0),Stimuli="ClickTrain");

% stimgen names spell the subject SUBJ_ID_959; one Test Mode file.
small = truth;  small.Freqs = [8 16];  small.Threshold = [20 40];  small.Levels = [40 60 80];
small.Seed = truth.Seed + 555;
sg = fullfile(study,"SUBJ-ID-959","SUBJ-ID-959_stimgen");
iSG = mabrtest.SyntheticABR.writeSession(sg,small,Subject="SUBJ_ID_959", ...
    Start=datetime(2026,10,1,16,0,0),NamingStyle="stimgen",TestModeFile=true);
tmName = iSG.Files.FileName(iSG.Files.TestMode);
assert(isscalar(tmName),'Setup: the stimgen session should hold one Test Mode file.');
only = fullfile(study,"SUBJ-ID-959","SUBJ-ID-959_TestOnly");
mkdir(only);
copyfile(fullfile(sg,tmName),fullfile(only,tmName));

% "old" names under a folder that names no subject, and two bad files.
old = fullfile(study,"Pilot","run_old");
mabrtest.SyntheticABR.writeSession(old,truth,Subject="SUBJ_ID_1254", ...
    Start=datetime(2026,10,1,17,0,0),Stimuli="ClickTrain",NamingStyle="old");
fid = fopen(fullfile(old,"broken.abr"),'w');
fwrite(fid,'this is not a MAT-file');
fclose(fid);
ABR_Data = struct('Note','not a recording');
save(fullfile(old,"notarecording.abr"),'ABR_Data','-v6');

% Places a scan must never list: a hidden folder, and a results store
% (which is also a nested store: project.mat, one results file, history).
anyAbr = fullfile(SP("SUBJ-ID-1254_Baseline"),info.SessionInfo(1).Files.FileName(1));
mkdir(fullfile(study,".trash"));
copyfile(anyAbr,fullfile(study,".trash","copy.abr"));
mkdir(fullfile(study,"$RECYCLE.BIN","S-1-5-21"));         % a drive root's deleted files
copyfile(anyAbr,fullfile(study,"$RECYCLE.BIN","S-1-5-21","$R0001.abr"));
store959 = fullfile(study,"SUBJ-ID-959","MABR_Analysis");
mkdir(fullfile(store959,".history"));
MABRAnalysisProject = struct('FormatVersion',1);
save(fullfile(store959,"project.mat"),'MABRAnalysisProject');
dummy = 1;
save(fullfile(store959,"SUBJ-ID-959_Baseline.mat"),'dummy');
save(fullfile(store959,".history","SUBJ-ID-959_Baseline_261001T120000.mat"),'dummy');
copyfile(anyAbr,fullfile(store959,"stray.abr"));
% A backup copy whose extension only STARTS with .abr: Windows' own
% wildcard matching finds it through its 8.3 short name (RUN~1.ABR). It
% is not a recording and its folder is no session.
bak = fullfile(study,"SUBJ-ID-1254","Backup");
mkdir(bak);
copyfile(anyAbr,fullfile(bak,"run.abr_old"));

% The mixed session's newest file holding notes gets a note from the
% morning (another animal's) and a repeat of its last note.
[~,j] = max(mi.Files.StartTime);
noteFile = fullfile(mixed,mi.Files.FileName(j));
S0 = load(noteFile,'-mat');
ABR_Data = S0.ABR_Data;
assert(numel(ABR_Data.Notes) == 3,'Setup: the last mixed-session file should hold all 3 notes.');
early = ABR_Data.Notes(1);
early.Text  = 'Morning: SUBJ-ID-1253 weighed 62 g';
early.Time  = '2026-10-01T11:00:00';
early.Stamp = '11:00:00';
early.Run   = NaN;  early.Sweep = NaN;  early.NumRuns = NaN;
ABR_Data.Notes = [early reshape(ABR_Data.Notes,1,[]) ABR_Data.Notes(end)];
save(noteFile,'ABR_Data','-v6');

% study2: a store at the study, a subject folder below it, and a session
% whose notes live only in a journal written by hand.
study2 = fullfile(work,"study2");
s77 = fullfile(study2,"SUBJ-ID-77","SUBJ-ID-77_Baseline");
i77 = mabrtest.SyntheticABR.writeSession(s77,truth,Subject="SUBJ-ID-77", ...
    Start=datetime(2026,10,1,10,0,0),Stimuli="ClickTrain");
mkdir(fullfile(study2,"MABR_Analysis"));
save(fullfile(study2,"MABR_Analysis","project.mat"),'MABRAnalysisProject');
journal77 = fullfile(s77,"SUBJ-ID-77_Notes_261001T095000.notes");
writeText(journal77,[ ...
    "% MABR session notes " + string(char(8212)) + " SUBJ-ID-77 " + string(char(8212)) + ...
        " session started 2026-10-01T09:50:00"
    "% Rewritten in full on every change; last written 2026-10-02T00:10:00"
    "[09:52:10] Electrodes in"
    "[R01 S0010 10:00:30] Twitch during the first run"
    "[R01 S0010 10:00:30] Twitch during the first run"
    "An untimed line"
    "[+00:12:00] Elapsed-stamped note"
    "[00:10:00] After midnight"]);

nAbr = 0;                                % .abr files a scan should list
expect = struct('Key',{},'Subject',{},'SubjectRaw',{},'Day',{},'Start',{},'NumFiles',{}, ...
    'NumIncluded',{},'NumSweeps',{},'NumConditions',{},'Stimuli',{},'Summary',{}, ...
    'AcqModes',{},'HasCompact',{},'ShortRuns',{},'TestMode',{},'Label',{});
rows = {
    "SUBJ-ID-959/SUBJ-ID-959_Baseline","SUBJ-ID-959","SUBJ-ID-959",datetime(2026,10,1,11,0,0),27,27,27*128,27,"Tone","Tone 3"+TIMES+"9","conventional",false,0,"none","Baseline"
    "SUBJ-ID-959/SUBJ-ID-959_stimgen","SUBJ-ID-959","SUBJ-ID-959",datetime(2026,10,1,16,0,0),7,6,6*128,6,"Tone","Tone 2"+TIMES+"3","conventional",false,0,"some","stimgen"
    "SUBJ-ID-959/SUBJ-ID-959_TestOnly","SUBJ-ID-959","SUBJ-ID-959",datetime(2026,10,1,16,1,30),1,1,128,1,"Tone","Tone 1"+TIMES+"1","conventional",false,0,"all","TestOnly"
    "SUBJ-ID-959/SUBJ-ID-959_2weeks","SUBJ-ID-959","SUBJ-ID-959",datetime(2026,10,15,11,0,0),27,27,27*128,27,"Tone","Tone 3"+TIMES+"9","conventional",false,0,"none","2weeks"
    "SUBJ-ID-1254/SUBJ-ID-1254_Baseline","SUBJ-ID-1254","SUBJ-ID-1254",datetime(2026,10,1,10,0,0),27,27,27*128,27,"Tone","Tone 3"+TIMES+"9","conventional",false,0,"none","Baseline"
    "SUBJ-ID-1254/"+mixedName,"SUBJ-ID-1254","SUBJ-ID-1254",datetime(2026,10,1,14,0,0),72,72,63*128+9*16,63,"ClickTrain, Tone", ...
        "Tone 3"+TIMES+"9 "+TIMES+"2 "+MID+" ClickTrain "+TIMES+"9 "+TIMES+"2","conventional, interleaved",true,9,"none","2026-10-01"
    "Pilot/run_old","SUBJ-ID-1254","SUBJ_ID_1254",datetime(2026,10,1,17,0,0),11,9,9*128,9,"ClickTrain","ClickTrain "+TIMES+"9","conventional",false,0,"none","run_old"
    "SUBJ-ID-1254/SUBJ-ID-1254_2weeks","SUBJ-ID-1254","SUBJ-ID-1254",datetime(2026,10,15,10,0,0),27,27,27*128,27,"Tone","Tone 3"+TIMES+"9","conventional",false,0,"none","2weeks"};
for r = 1:size(rows,1)
    [k,s,sr,t0,nf,ni,ns,nc,st,su,am,hc,sh,tm,lb] = rows{r,:};
    expect(r) = struct('Key',k,'Subject',s,'SubjectRaw',sr,'Day',dateshift(t0,'start','day'), ...
        'Start',t0,'NumFiles',nf,'NumIncluded',ni,'NumSweeps',ns,'NumConditions',nc, ...
        'Stimuli',st,'Summary',su,'AcqModes',am,'HasCompact',hc,'ShortRuns',sh, ...
        'TestMode',tm,'Label',lb);
    nAbr = nAbr + nf;
end
fprintf('  (built %d .abr files in two trees in %.1f s)\n',nAbr + height(i77.Files),toc(tBuild));

cacheA = fullfile(work,"cacheA");

% =========================================================================
%  Part A -- sessions and files
% =========================================================================
calls = containers.Map('KeyType','double','ValueType','any');
sink  = @(m,k,n) recordCall(calls,m,k,n);
c1 = mabr.analysis.Catalog(study,CacheFolder=cacheA);
assert(isnat(c1.ScannedAt) && c1.LastScanReads == 0,'A new Catalog should not have been scanned.');
assert(height(c1.Files) == 0 && isequal(string(c1.Files.Properties.VariableNames),c1.FileColumns) && ...
    height(c1.Sessions) == 0 && isequal(string(c1.Sessions.Properties.VariableNames),c1.SessionColumns), ...
    'Before a scan Files and Sessions should be empty tables with every column.');
tScan = tic;
scanUnchanged(c1,study,{'ProgressFcn',sink});
tScan = toc(tScan);
assert(strcmpi(c1.Root,study) && strcmpi(c1.AnalysisRoot,study) && ...
    strcmpi(c1.ResultsFolder,fullfile(study,"MABR_Analysis")), ...
    'Root/AnalysisRoot/ResultsFolder: %s | %s | %s',c1.Root,c1.AnalysisRoot,c1.ResultsFolder);
assert(c1.LastScanReads == nAbr,'The first scan read %d files; %d are there.',c1.LastScanReads,nAbr);
assert(c1.CacheState == "new",'First scan CacheState "%s".',c1.CacheState);

S = c1.Sessions;
F = c1.Files;
assert(isequal(string(S.Properties.VariableNames),c1.SessionColumns),'Sessions columns: %s', ...
    strjoin(S.Properties.VariableNames,', '));
assert(isequal(string(F.Properties.VariableNames),c1.FileColumns),'Files columns: %s', ...
    strjoin(F.Properties.VariableNames,', '));
assert(isequal(S.Key,[expect.Key]'),'Session order (natural subjects, then days, then starts):\n%s', ...
    strjoin(S.Key,newline));
for r = 1:numel(expect)
    e = expect(r);  w = e.Key;
    assert(S.Subject(r) == e.Subject && S.SubjectRaw(r) == e.SubjectRaw, ...
        '%s: Subject "%s"/"%s".',w,S.Subject(r),S.SubjectRaw(r));
    assert(S.Day(r) == e.Day && S.Start(r) == e.Start,'%s: Day %s, Start %s.',w, ...
        string(S.Day(r)),string(S.Start(r)));
    assert(S.NumFiles(r) == e.NumFiles && S.NumIncluded(r) == e.NumIncluded, ...
        '%s: NumFiles %d, NumIncluded %d.',w,S.NumFiles(r),S.NumIncluded(r));
    assert(S.NumSweeps(r) == e.NumSweeps && S.NumConditions(r) == e.NumConditions, ...
        '%s: NumSweeps %d, NumConditions %d.',w,S.NumSweeps(r),S.NumConditions(r));
    assert(S.Stimuli(r) == e.Stimuli,'%s: Stimuli "%s".',w,S.Stimuli(r));
    assert(S.Summary(r) == e.Summary,'%s: Summary "%s" (code points %s), expected "%s".',w, ...
        S.Summary(r),mat2str(double(char(S.Summary(r)))),e.Summary);
    assert(S.AcqModes(r) == e.AcqModes && S.HasCompact(r) == e.HasCompact, ...
        '%s: AcqModes "%s", HasCompact %d.',w,S.AcqModes(r),S.HasCompact(r));
    assert(S.ShortRuns(r) == e.ShortRuns,'%s: ShortRuns %d.',w,S.ShortRuns(r));
    assert(S.TestMode(r) == e.TestMode,'%s: TestMode "%s".',w,S.TestMode(r));
    assert(S.Units(r) == "V" && S.LevelUnit(r) == "dB SPL",'%s: Units "%s", LevelUnit "%s".', ...
        w,S.Units(r),S.LevelUnit(r));
    assert(S.InferredLabel(r) == e.Label,'%s: InferredLabel "%s".',w,S.InferredLabel(r));
    assert(S.Name(r) == folderOf(S.Path(r)) && endsWith(e.Key,S.Name(r)) && ...
        strcmpi(S.Path(r),fullfile(study,strrep(e.Key,"/",filesep))),'%s: Path/Name.',w);
    % Stop: the end of the last file recorded (every session here ends on
    % a continuous file).
    Fr = F(F.SessionKey == e.Key & F.Ok,:);
    [tLast,iLast] = max(Fr.StartTime);
    assert(abs(seconds(S.Stop(r) - (tLast + seconds(Fr.Duration(iLast))))) < 1e-6, ...
        '%s: Stop %s.',w,string(S.Stop(r)));
    assert(nnz(F.SessionKey == e.Key) == e.NumFiles,'%s: %d Files rows.',w,nnz(F.SessionKey == e.Key));
    st = F.StartTime(F.SessionKey == e.Key);
    st = st(~isnat(st));
    assert(issorted(st),'%s: files are not in start order.',w);
end
assert(numel(unique(S.Subject)) == 2,'Two subjects expected, got: %s.',strjoin(unique(S.Subject),', '));
km = find(S.Key == "SUBJ-ID-1254/" + mixedName);
assert(strcmpi(S.NotesFile(km),string(mi.NotesFile)) && all(S.NotesFile([1:km-1 km+1:end]) == ""), ...
    'NotesFile: only the mixed session has a journal (%s).',S.NotesFile(km));
assert(~any(S.HasResults),'No session of the study has a results file in its store yet.');
fprintf('  PASS Part A sessions: %d sessions in natural subject order (959 first), days, start/stop, counts, summaries ("%s"), modes, short runs, Test Mode none/some/all, labels\n', ...
    height(S),replace(S.Summary(km),[TIMES MID],["x" "."]));   % ASCII for any console

% ---- Files
assert(height(F) == nAbr,'Files has %d rows; %d .abr files are outside skipped folders.',height(F),nAbr);
assert(~any(contains(F.Path,".trash") | contains(F.Path,"$RECYCLE.BIN") | contains(F.Path,"MABR_Analysis")), ...
    'A file in a hidden folder or a results store was listed.');
assert(~any(endsWith(F.FileName,".abr_old")) && ~any(contains(S.Key,"Backup")), ...
    'A *.abr_old backup was listed as a recording.');
assert(all(ismember(F.SessionKey,S.Key)),'A Files row names a session that is not in Sessions.');
assert(all(F.FileId == folderOf(F.Folder) + "/" + F.FileName),'FileId is not "<folder name>/<file name>".');
iSGf = F.SessionKey == "SUBJ-ID-959/SUBJ-ID-959_stimgen";
assert(all(startsWith(F.FileName(iSGf),"SUBJ_ID_959_")) && all(F.Subject(iSGf) == "SUBJ-ID-959"), ...
    'Defect 16: files named SUBJ_ID_959 in folder SUBJ-ID-959 should be one subject.');
iOldf = F.SessionKey == "Pilot/run_old";
assert(all(F.Subject(iOldf) == "SUBJ-ID-1254"),'"old"-named files: Subject %s.',strjoin(unique(F.Subject(iOldf)),', '));
bk = F.FileName == "broken.abr";  nr = F.FileName == "notarecording.abr";
assert(nnz(bk) == 1 && ~F.Ok(bk) && startsWith(F.Error(bk),"could not load"), ...
    'broken.abr: Ok %d, Error "%s".',F.Ok(bk),F.Error(bk));
assert(nnz(nr) == 1 && ~F.Ok(nr) && contains(F.Error(nr),"not an ABR recording"), ...
    'notarecording.abr: Ok %d, Error "%s".',F.Ok(nr),F.Error(nr));
assert(all(F.Ok(~bk & ~nr)),'Every other file should read Ok.');
dup = F.DuplicateOf ~= "";
assert(nnz(dup) == 1 && F.SessionKey(dup) == "SUBJ-ID-959/SUBJ-ID-959_TestOnly" && ...
    F.DuplicateOf(dup) == "SUBJ-ID-959/SUBJ-ID-959_stimgen/" + tmName, ...
    'DuplicateOf: the Test Mode copy should name its original (%s).',strjoin(F.DuplicateOf(dup),', '));
assert(all(F.TestMode == (F.FileName == tmName)),'TestMode flags.');
cmp = F.Layout == "compact";
assert(nnz(cmp) == 27 && all(F.AcqMode(cmp) == "interleaved") && all(F.SessionKey(cmp) == S.Key(km)), ...
    'Compact files: %d, modes %s.',nnz(cmp),strjoin(unique(F.AcqMode(cmp)),', '));
assert(any(contains(c1.Warnings,"broken.abr")) && any(contains(c1.Warnings,"not recordings")) && ...
    any(contains(c1.Warnings,"copies")),'Warnings:\n%s',strjoin(c1.Warnings,newline));
assert(numel(c1.Records) == height(F) && all([c1.Records.Path]' == F.Path), ...
    'Records should be one AbrFile record per Files row, same order.');
% Every column named for a reader field IS that field, row for row (a
% swapped Units/LevelUnit or a column taken from the wrong record would
% pass every count above). Subject is the catalog's own rule.
pass = setdiff(intersect(c1.FileColumns,string(fieldnames(c1.Records))),"Subject");
assert(numel(pass) >= 15,'Expected most Files columns to come from the reader (%d do).',numel(pass));
for v = reshape(pass,1,[])
    assert(isequaln(F.(v),reshape([c1.Records.(v)],[],1)),'Files.%s is not the reader''s %s.',v,v);
end
fprintf('  PASS Part A files: %d rows with every column, canonical subjects (defect 16), unreadable/skipped files kept as rows, the copy marked DuplicateOf, hidden folders and stores never listed (%.2f s scan)\n', ...
    height(F),tScan);

% =========================================================================
%  Part B -- notes
% =========================================================================
before = snapshot(study);
kMix = S.Key(km);
Tn = c1.notes(kMix);
Ta = c1.notes(kMix,Scope="all");
assert(isequal(string(Tn.Properties.VariableNames),c1.NoteColumns),'notes() columns: %s', ...
    strjoin(Tn.Properties.VariableNames,', '));
assert(height(Tn) == 3 && isequal(Tn.Text,string(mi.Notes(:))) && all(Tn.Scope == "session"), ...
    'Session-scope notes:\n%s',strjoin(Tn.Text,newline));
assert(height(Ta) == 4 && Ta.Text(1) == "Morning: SUBJ-ID-1253 weighed 62 g" && Ta.Scope(1) == "earlier" && ...
    isequal(Ta.Text(2:4),Tn.Text) && Ta.Time(1) == datetime(2026,10,1,11,0,0), ...
    'All notes (the morning note earlier, the repeat gone):\n%s',strjoin(Ta.Text + " [" + Ta.Scope + "]",newline));
assert(Ta.Properties.UserData.From == "file" && strcmpi(Ta.Properties.UserData.File,noteFile), ...
    'Notes should come from the newest file holding them (%s), not the newer short run.', ...
    Ta.Properties.UserData.File);
assert(Tn.Run(2) == 1 && Tn.Sweep(2) == 64,'A structured note keeps its run and sweep.');
Tb = c1.notes(S.Key(1),Scope="all");
assert(height(Tb) == 0 && isequal(string(Tb.Properties.VariableNames),c1.NoteColumns) && ...
    Tb.Properties.UserData.From == "none",'A session without notes should give an empty table.');
assertError(@() c1.notes("no/such/session"),'mabr:analysis:Catalog:unknownKey');
assertError(@() c1.fileRows("no/such/session"),'mabr:analysis:Catalog:unknownKey');
fr = c1.fileRows(kMix);
assert(isequal(fr,F(F.SessionKey == kMix,:)),'fileRows should be the session''s Files rows.');

% The journal fallback (study2): times from the header, run and sweep from
% the stamp, an elapsed stamp, a line past midnight, a line with no stamp.
cacheX = fullfile(work,"cacheX");
c77 = mabr.analysis.Catalog(fullfile(study2,"SUBJ-ID-77"),CacheFolder=cacheX);
scanUnchanged(c77,study2,{});
k77 = "SUBJ-ID-77/SUBJ-ID-77_Baseline";
assert(isequal(c77.Sessions.Key,k77) && strcmpi(c77.Sessions.NotesFile,journal77), ...
    'study2: key %s, NotesFile %s.',strjoin(c77.Sessions.Key,', '),strjoin(c77.Sessions.NotesFile,', '));
J  = c77.notes(k77,Scope="all");
Js = c77.notes(k77);
wantText = ["Electrodes in";"Twitch during the first run";"An untimed line";"Elapsed-stamped note";"After midnight"];
wantTime = [datetime(2026,10,1,9,52,10);datetime(2026,10,1,10,0,30);NaT;datetime(2026,10,1,10,2,0); ...
    datetime(2026,10,2,0,10,0)];
assert(isequal(J.Text,wantText) && isequaln(J.Time,wantTime), ...
    'Journal notes:\n%s',strjoin(string(J.Time) + " " + J.Text,newline));
assert(isequal(J.Scope,["earlier";"session";"unknown";"session";"later"]),'Journal scopes: %s', ...
    strjoin(J.Scope,', '));
assert(J.Run(2) == 1 && J.Sweep(2) == 10 && isnan(J.Run(1)) && J.Properties.UserData.From == "journal", ...
    'Journal run/sweep/source.');
assert(isequal(Js.Text,wantText([2 4])),'Session-scope journal notes: %s',strjoin(Js.Text,' | '));
assert(isequal(before,snapshot(study)),'Reading notes changed something under the study.');
fprintf('  PASS Part B notes: a file''s notebook de-duplicated and scoped (session vs all); the journal fallback dates its stamps from the header (run/sweep, elapsed, midnight, untimed)\n');

% =========================================================================
%  Part C -- where results go
% =========================================================================
rf  = c1.ResultsFolder;
kB  = "SUBJ-ID-1254/SUBJ-ID-1254_Baseline";
k2w = "SUBJ-ID-1254/SUBJ-ID-1254_2weeks";
assert(strcmpi(c1.resultsFile(kB),fullfile(rf,"SUBJ-ID-1254","SUBJ-ID-1254_Baseline.mat")), ...
    'resultsFile(key): %s',c1.resultsFile(kB));
for r = 1:height(S)
    assert(S.ResultsFile(r) == c1.resultsFile(S.Key(r)),'Sessions.ResultsFile(%d) is not resultsFile(Key).',r);
end
hx = mabr.analysis.Stats.hex8(k2w + "|" + kB);       % sorted: "2" before "B"
wantPool = fullfile(rf,"SUBJ-ID-1254","pooled","SUBJ-ID-1254_2weeks+1_" + hx + ".mat");
assert(strcmpi(c1.resultsFile([kB k2w]),wantPool) && c1.resultsFile([k2w kB]) == c1.resultsFile([kB k2w]) && ...
    c1.resultsFile([kB k2w kB]) == c1.resultsFile([kB k2w]),'Pool resultsFile: %s, expected %s.', ...
    c1.resultsFile([kB k2w]),wantPool);
three = c1.resultsFile([kB k2w kMix]);
assert(contains(three,"+2_") && contains(three,filesep + "pooled" + filesep),'Three-member pool: %s',three);
assertError(@() c1.resultsFile("pool:12ab34cd"),'mabr:analysis:Catalog:badKey');
assertError(@() c1.resultsFile("../outside"),'mabr:analysis:Catalog:badKey');
assertError(@() c1.resultsFile("SUBJ-ID-1254/"),'mabr:analysis:Catalog:badKey');
assertError(@() c1.resultsFile("SUBJ-ID-1254\SUBJ-ID-1254_Baseline"),'mabr:analysis:Catalog:badKey');
assertError(@() c1.resultsFile(strings(0,1)),'mabr:analysis:Catalog:noKeys');

% "." -- a session folder opened on its own is its own analysis root.
base1254 = SP("SUBJ-ID-1254_Baseline");
cDot = mabr.analysis.Catalog(base1254,CacheFolder=fullfile(work,"cacheDot"));
scanUnchanged(cDot,base1254,{});
assert(isequal(cDot.Sessions.Key,".") && cDot.Sessions.Name == "SUBJ-ID-1254_Baseline" && ...
    cDot.Sessions.Subject == "SUBJ-ID-1254" && cDot.Sessions.InferredLabel == "Baseline", ...
    'A session folder as root: key "%s", name "%s".',strjoin(cDot.Sessions.Key,','),strjoin(cDot.Sessions.Name,','));
wantDot = fullfile(base1254,"MABR_Analysis","SUBJ-ID-1254_Baseline.mat");
assert(strcmpi(cDot.resultsFile("."),wantDot) && strcmpi(cDot.Sessions.ResultsFile,wantDot) && ...
    all(cDot.Files.SessionKey == ".") && all(cDot.Files.FileId == "SUBJ-ID-1254_Baseline/" + cDot.Files.FileName), ...
    'resultsFile("."): %s',cDot.resultsFile("."));

% An ancestor's store makes it the analysis root; keys are relative to it.
assert(strcmpi(c77.Root,fullfile(study2,"SUBJ-ID-77")) && strcmpi(c77.AnalysisRoot,study2) && ...
    strcmpi(c77.ResultsFolder,fullfile(study2,"MABR_Analysis")) && ...
    strcmpi(c77.Sessions.ResultsFile,fullfile(study2,"MABR_Analysis","SUBJ-ID-77","SUBJ-ID-77_Baseline.mat")) && ...
    height(c77.NestedStores) == 0,'AnalysisRoot at the ancestor holding MABR_Analysis/project.mat: %s', ...
    c77.AnalysisRoot);

% A ResultsFolder override, and a results file found there.
rf77 = fullfile(work,"results77");
cR = mabr.analysis.Catalog(fullfile(study2,"SUBJ-ID-77"),CacheFolder=cacheX,ResultsFolder=rf77);
assert(strcmpi(cR.ResultsFolder,rf77),'ResultsFolder override: %s',cR.ResultsFolder);
want77 = fullfile(rf77,"SUBJ-ID-77","SUBJ-ID-77_Baseline.mat");
assert(strcmpi(cR.resultsFile(k77),want77),'resultsFile under the override: %s',cR.resultsFile(k77));
mkdir(fullfile(rf77,"SUBJ-ID-77"));
save(want77,'dummy');
scanUnchanged(cR,study2,{});
assert(cR.Sessions.HasResults && strcmpi(cR.Sessions.ResultsFile,want77) && cR.LastScanReads == 0, ...
    'HasResults under the override (reads %d).',cR.LastScanReads);

% A cache folder in the study but beside Root (inside its AnalysisRoot) is
% inside the data too: never written. Constructing writes nothing.
cG = mabr.analysis.Catalog(fullfile(study2,"SUBJ-ID-77"),CacheFolder=fullfile(study2,"cache_here"));
assert(startsWith(cG.CacheState,"disabled") && cG.CacheFile == "" && ~isfolder(fullfile(study2,"cache_here")), ...
    'A cache folder inside the AnalysisRoot should disable the cache (state "%s").',cG.CacheState);

% A drive root as the analysis root (a stick from the rig with its files at
% the top): its "." results file is named for the drive letter, never
% ".mat". Constructing a Catalog reads nothing below its root.
drv = string(regexp(char(tempdir),'^[A-Za-z]:','match','once'));
if drv ~= "" && ~isfile(fullfile(drv + filesep,"MABR_Analysis","project.mat"))
    cDrv = mabr.analysis.Catalog(drv + filesep,CacheFolder="",ResultsFolder=fullfile(work,"rfDrive"));
    wantDrv = fullfile(work,"rfDrive",extractBefore(drv,2) + ".mat");
    assert(strcmpi(cDrv.AnalysisRoot,drv + filesep) && strcmpi(cDrv.resultsFile("."),wantDrv) && ...
        startsWith(cDrv.CacheState,"disabled"),'A drive root''s "." results file: %s (expected %s).', ...
        cDrv.resultsFile("."),wantDrv);
end

% A folder that holds its own store is its own analysis root; from the
% study, that store is a nested one.
c959 = mabr.analysis.Catalog(fullfile(study,"SUBJ-ID-959"),CacheFolder=cacheA);
scanUnchanged(c959,study,{});
assert(strcmpi(c959.AnalysisRoot,fullfile(study,"SUBJ-ID-959")) && height(c959.NestedStores) == 0 && ...
    isequal(c959.Sessions.Key,["SUBJ-ID-959_Baseline";"SUBJ-ID-959_stimgen";"SUBJ-ID-959_TestOnly";"SUBJ-ID-959_2weeks"]), ...
    'A folder with its own store: AnalysisRoot %s, keys %s.',c959.AnalysisRoot,strjoin(c959.Sessions.Key,', '));
assert(isequal(c959.Sessions.HasResults,[true;false;false;false]), ...
    'The planted results file should be found for SUBJ-ID-959_Baseline only.');
NS = c1.NestedStores;
assert(isequal(string(NS.Properties.VariableNames),c1.StoreColumns) && height(NS) == 1 && ...
    strcmpi(NS.Path,store959) && strcmpi(NS.Root,fullfile(study,"SUBJ-ID-959")) && NS.NumResults == 1, ...
    'NestedStores: %d row(s)%s.',height(NS),sprintf(' %s (%d)',NS.Path,NS.NumResults));

% suggestStudyRoot and inferLabel.
sug = @(p) mabr.analysis.Catalog.suggestStudyRoot(p);
assert(strcmpi(sug(fullfile(study,"SUBJ-ID-1254")),study),'suggestStudyRoot(subject folder) should be the study.');
assert(sug(fullfile(study,"SUBJ-ID-959")) == "",'A subject folder holding its own store needs no suggestion.');
assert(sug(fullfile(study2,"SUBJ-ID-77")) == "",'A subject folder below a study store needs no suggestion.');
assert(sug(base1254) == "",'A folder holding .abr files itself is a session, not a subject.');
assert(sug(fullfile(study,"Pilot")) == "",'A folder naming no subject gets no suggestion.');
assert(sug(fullfile(work,"no_such_folder")) == "",'A missing folder gets no suggestion.');
lbl = @(f,s) mabr.analysis.Catalog.inferLabel(f,s);
assert(lbl("SUBJ-ID-959_Baseline","SUBJ-ID-959") == "Baseline" && ...
    lbl("SUBJ-ID-1254_261001T140000","SUBJ-ID-1254") == "2026-10-01" && ...
    lbl("SUBJ_ID_1254_2weeks","SUBJ-ID-1254") == "2weeks" && ...
    lbl("subj-id-1254-pre","SUBJ-ID-1254") == "pre" && ...
    lbl("SUBJ-ID-1254","SUBJ-ID-1254") == "" && ...
    lbl("261001","") == "2026-10-01" && ...
    lbl("SUBJ-ID-12_Baseline","") == "Baseline" && ...
    lbl("Baseline_SUBJ-ID-12_x","SUBJ-ID-12") == "Baseline_x" && ...
    lbl("261341","") == "261341" && lbl("260231","") == "260231", ...
    'inferLabel rules.');
fprintf('  PASS Part C results location: resultsFile for a key, "." and a pool (order-free, %s), bad keys refused; AnalysisRoot at an ancestor''s and at the folder''s own store; ResultsFolder override; a cache folder inside the AnalysisRoot refused; a drive root''s "." file; a nested store found; suggestStudyRoot; inferLabel\n', ...
    folderOf(wantPool));

% =========================================================================
%  Part D -- the cache
% =========================================================================
assert(c1.CacheFile == string(fullfile(c1.CacheFolder,"catalog_" + ...
    mabr.analysis.Stats.hex8(lower(c1.Root)) + ".mat")) && isfile(c1.CacheFile) && ...
    strcmpi(c1.CacheFolder,cacheA),'CacheFile: %s',c1.CacheFile);
% A file that could not be LOADED (broken.abr) is never a cache hit -- that
% failure may be the moment's (locked, unsynced, no permission), and size
% and time would not change when it passed -- so every rescan reads it, and
% nothing else.
retryRow = startsWith(F.Error,"could not load") | F.Error == "file not found";
nRetry = nnz(retryRow);
assert(nRetry == 1 && F.FileName(retryRow) == "broken.abr", ...
    'Only broken.abr should be a load failure (%d are).',nRetry);
c2 = mabr.analysis.Catalog(study,CacheFolder=cacheA);
tRe = tic;
scanUnchanged(c2,study,{});
tRe = toc(tRe);
assert(c2.LastScanReads == nRetry && c2.CacheState == "loaded",'Rescan: %d reads, CacheState "%s".', ...
    c2.LastScanReads,c2.CacheState);
assert(isequaln(c2.Files,c1.Files) && isequaln(c2.Sessions,c1.Sessions) && ...
    isequaln(c2.NestedStores,c1.NestedStores) && isequaln(c2.Records,c1.Records), ...
    'A rescan from the cache should give exactly the first scan''s tables.');

% Touch one file: only it is read again.
iT = find(F.SessionKey == kB,1);
touch(F.Path(iT),datetime('now') - hours(1));
scanUnchanged(c2,study,{});
assert(c2.LastScanReads == nRetry + 1,'After touching one file the scan read %d.',c2.LastScanReads);
assert(c2.Files.Modified(iT) ~= c1.Files.Modified(iT) && ...
    isequaln(removevars(c2.Files,'Modified'),removevars(c1.Files,'Modified')), ...
    'Only the touched file''s Modified should differ.');
ref = c2;

% Another reader version, another cache version, a corrupt cache, a cache
% of another folder, records of another shape: each rebuilt, silently.
cases = { ...
    @(M) setfield(M,'ReaderVersion',mabr.analysis.AbrFile.ReaderVersion + 1), "rebuilt (reader version changed)"
    @(M) setfield(M,'CacheVersion',99),                                       "rebuilt (cache version changed)"
    @(M) setfield(M,'Root',"C:\elsewhere"),                                    "rebuilt (cache of another folder)"
    @(M) dropRecordField(M),                                                  "rebuilt (record fields changed)"
    'corrupt',                                                                "rebuilt (cache unreadable)"};
for q = 1:size(cases,1)
    edit = cases{q,1};
    if ischar(edit)
        fid = fopen(ref.CacheFile,'w');  fwrite(fid,uint8(1:200));  fclose(fid);
    else
        L = load(ref.CacheFile,'MABRCatalogCache');
        MABRCatalogCache = edit(L.MABRCatalogCache);
        save(ref.CacheFile,'MABRCatalogCache');
    end
    cq = mabr.analysis.Catalog(study,CacheFolder=cacheA);
    out = evalc('scanUnchanged(cq,study,{});');
    assert(isempty(strtrim(out)),'A rebuilt cache printed:\n%s',out);
    assert(cq.LastScanReads == nAbr && cq.CacheState == cases{q,2}, ...
        'Case %d: %d reads, CacheState "%s" (expected "%s").',q,cq.LastScanReads,cq.CacheState,cases{q,2});
    assert(~any(contains(cq.Warnings,"cache",'IgnoreCase',true)), ...
        'A rebuilt cache should be silent; Warnings:\n%s',strjoin(cq.Warnings,newline));
    assert(isequaln(cq.Files,ref.Files) && isequaln(cq.Sessions,ref.Sessions), ...
        'Case %d: a rebuilt cache gave different tables.',q);
    cr = mabr.analysis.Catalog(study,CacheFolder=cacheA);
    scanUnchanged(cr,study,{});
    assert(cr.LastScanReads == nRetry && cr.CacheState == "loaded", ...
        'Case %d: the rebuilt cache was not written back (%d reads).',q,cr.LastScanReads);
end

% ReadMetadata false: nothing is opened; the cache still serves.
cacheE = fullfile(work,"cacheEmpty");
cm = mabr.analysis.Catalog(study,CacheFolder=cacheE,ReadMetadata=false);
scanUnchanged(cm,study,{});
assert(cm.LastScanReads == 0 && height(cm.Files) == nAbr && ~any(cm.Files.Ok) && ...
    all(contains(cm.Files.Error,"not read")) && isequal(sort(cm.Sessions.Key),sort(ref.Sessions.Key)) && ...
    ~isfile(cm.CacheFile) && any(contains(cm.Warnings,"ReadMetadata")), ...
    'ReadMetadata false over an empty cache: %d reads, %d Ok, cache written %d.', ...
    cm.LastScanReads,nnz(cm.Files.Ok),isfile(cm.CacheFile));
[~,ia] = ismember(ref.Sessions.Key,cm.Sessions.Key);
assert(all(cm.Sessions.Subject(ia) == ref.Sessions.Subject) && all(cm.Sessions.NumFiles(ia) == ref.Sessions.NumFiles), ...
    'Unread files still give each session its subject and its file count.');
% Over a warm cache it gives the full tables, but for the one file the
% cache cannot vouch for (it could not be loaded), which is listed unread.
cw = mabr.analysis.Catalog(study,CacheFolder=cacheA,ReadMetadata=false);
scanUnchanged(cw,study,{});
assert(cw.LastScanReads == 0 && isequaln(removevars(cw.Files,'Error'),removevars(ref.Files,'Error')) && ...
    isequal(cw.Files.Error(~retryRow),ref.Files.Error(~retryRow)) && ...
    all(contains(cw.Files.Error(retryRow),"not read")) && isequaln(cw.Sessions,ref.Sessions), ...
    'ReadMetadata false over a warm cache should give the full tables.');

% The same folder spelled with "/" and in capitals is the same root: the
% same cache file, every record a hit, the same keys.
cu = mabr.analysis.Catalog(upper(strrep(study,"\","/")),CacheFolder=cacheA);
scanUnchanged(cu,study,{});
assert(cu.CacheFile == ref.CacheFile && cu.LastScanReads == nRetry && cu.CacheState == "loaded" && ...
    isequal(cu.Sessions.Key,ref.Sessions.Key) && isequal(cu.Files.SessionKey,ref.Files.SessionKey), ...
    'Root spelled another way: cache %s, %d reads.',cu.CacheFile,cu.LastScanReads);

% A good file the cache remembers as a load failure (it was locked, say,
% when it was first listed) is read again, comes back whole, and the cache
% is healed: the next scan reads only broken.abr again.
L = load(ref.CacheFile,'MABRCatalogCache');
MABRCatalogCache = L.MABRCatalogCache;
iE = find(strcmpi(MABRCatalogCache.Entries.Path,F.Path(iT)),1);
assert(~isempty(iE),'Setup: %s should be in the cache.',F.Path(iT));
rl = MABRCatalogCache.Entries.Rec{iE};
rl.Ok = false;  rl.Error = "could not load: simulated (the file was locked)";
MABRCatalogCache.Entries.Rec{iE} = rl;
save(ref.CacheFile,'MABRCatalogCache');
cl = mabr.analysis.Catalog(study,CacheFolder=cacheA);
scanUnchanged(cl,study,{});
assert(cl.LastScanReads == nRetry + 1 && cl.CacheState == "loaded" && isequaln(cl.Files,ref.Files) && ...
    cl.Files.Ok(iT),'A cached load failure should be read again (%d reads, Ok %d).',cl.LastScanReads, ...
    cl.Files.Ok(iT));
cl2 = mabr.analysis.Catalog(study,CacheFolder=cacheA);
scanUnchanged(cl2,study,{});
assert(cl2.LastScanReads == nRetry,'The healed record was not cached (%d reads).',cl2.LastScanReads);

% A cache folder inside the data is never written.
inside = fullfile(study,"cache_here");
ci = mabr.analysis.Catalog(study,CacheFolder=inside);
assert(startsWith(ci.CacheState,"disabled") && ci.CacheFile == "" && ci.CacheFolder == "", ...
    'A cache folder inside the data should disable the cache (state "%s").',ci.CacheState);
scanUnchanged(ci,study,{});
assert(ci.LastScanReads == nAbr && ~isfolder(inside) && any(contains(ci.Warnings,"disabled")) && ...
    isequaln(ci.Files,ref.Files),'The disabled cache: %d reads, folder created %d.', ...
    ci.LastScanReads,isfolder(inside));
fprintf('  PASS Part D cache: a rescan opens only the unloadable file (%.2f s) and equals the first; one touched file is read again; a cached load failure is retried and healed; reader/cache version, corrupt, other-folder and changed-record caches rebuilt silently; ReadMetadata false; a cache inside the data refused; the study unchanged by every scan\n', ...
    tRe);

% =========================================================================
%  Part E -- progress, cancel, arguments
% =========================================================================
K = cell2mat(keys(calls));
V = values(calls);
cnt = cellfun(@(v) v{2},V);  tot = cellfun(@(v) v{3},V);
msg = string(cellfun(@(v) v{1},V,'UniformOutput',false));
assert(K(1) == 1 && cnt(1) == 0 && cnt(end) == nAbr && all(tot == nAbr) && all(diff(cnt) >= 0) && ...
    all(contains(msg,string(nAbr))),'Progress calls: counts %s of %s.',mat2str(cnt),mat2str(unique(tot)));
box = containers.Map();
cc  = mabr.analysis.Catalog(study,CacheFolder=fullfile(work,"cacheCancel"));
stateBefore = {cc.Files,cc.Sessions,cc.Records,cc.Warnings,cc.ScannedAt,cc.LastScanReads,cc.CacheState};
assertError(@() cc.scan(ProgressFcn=@(m,k,n) cancelAfterStart(box,k)),'mabr:analysis:cancelled');
assert(isequaln(stateBefore,{cc.Files,cc.Sessions,cc.Records,cc.Warnings,cc.ScannedAt,cc.LastScanReads,cc.CacheState}), ...
    'A cancelled scan changed the object.');
kc = box('k');
% Files are read in path order; those read before the cancel are cached --
% all but a load failure among them, which is never cached.
[~,ord] = sort(lower(ref.Files.Path));
keptBefore = nnz(~retryRow(ord(1:kc)));
scanUnchanged(cc,study,{});
assert(cc.LastScanReads == nAbr - keptBefore && isequaln(cc.Files,ref.Files), ...
    'After a cancel at %d the next scan read %d (the %d cacheable ones read before it should be cached).', ...
    kc,cc.LastScanReads,keptBefore);
assertError(@() cc.scan(ProgressFcn=42),'mabr:analysis:Catalog:badProgressFcn');
assertError(@() mabr.analysis.Catalog(fullfile(work,"no_such_folder")),'mabr:analysis:Catalog:noRoot');
% A root that disappears after construction is an error, not an empty study.
gone = fullfile(work,"gone");
mkdir(fullfile(gone,"SUBJ-ID-5"));
copyfile(anyAbr,fullfile(gone,"SUBJ-ID-5","x.abr"));
cg = mabr.analysis.Catalog(gone,CacheFolder=fullfile(work,"cacheGone"));
mabrtest.SyntheticABR.rmdirQuiet(gone);
assertError(@() cg.scan(),'mabr:analysis:Catalog:noRoot');
assert(height(cg.Sessions) == 0 && isnat(cg.ScannedAt),'A failed scan changed the object.');
fprintf('  PASS Part E progress and cancel: %d sink calls (0..%d of %d); a cancel at %d changes nothing but keeps what it read; bad arguments refused\n', ...
    numel(cnt),cnt(end),nAbr,kc);

% =========================================================================
%  Part F -- no Statistics Toolbox function
% =========================================================================
file = which(Cat);
assert(~isempty(file),'%s is not on the path.',Cat);
hits = forbiddenUses(file);
assert(isempty(hits),'Statistics Toolbox identifiers in Catalog.m:\n%s',strjoin(hits,newline));
fprintf('  PASS Part F: Catalog.m calls no Statistics Toolbox function\n');

% =========================================================================
%  Part G -- the same verdict a Session over each folder reaches
% =========================================================================
% A folder of one real file beside two Test Mode files at another rate.
% Session drops the Test Mode files (real data is there) and only THEN takes
% the majority rate of what is left, keeping the real file; the rules the
% other way round would take the Test Mode rate and include nothing. The
% folder is named for its subject alone, so its label is its day.
ratesRoot = fullfile(work,"rates");
rates = fullfile(ratesRoot,"SUBJ-ID-31");
mkdir(rates);
fb = info.SessionInfo(1).Files.FileName(1);
copyfile(fullfile(SP("SUBJ-ID-1254_Baseline"),fb),fullfile(rates,"SUBJ-ID-31_real.abr"));
L = load(fullfile(sg,tmName),'-mat');
ABR_Data = L.ABR_Data;
ABR_Data.ADC.SampleRate = 2*ABR_Data.ADC.SampleRate;
for q = 1:2
    ABR_Data.StartTime = char(datetime(2026,10,1,12,q,0),'yyyy-MM-dd''T''HH:mm:ss');
    save(fullfile(rates,sprintf('SUBJ-ID-31_test%d.abr',q)),'ABR_Data','-v6');
end
cRates = mabr.analysis.Catalog(ratesRoot,CacheFolder=fullfile(work,"cacheRates"));
scanUnchanged(cRates,ratesRoot,{});
Sr = cRates.Sessions;
assert(height(Sr) == 1 && Sr.Key == "SUBJ-ID-31" && Sr.NumFiles == 3 && Sr.NumIncluded == 1 && ...
    Sr.NumSweeps == truth.nSweeps && Sr.TestMode == "some" && Sr.Subject == "SUBJ-ID-31", ...
    'One real file beside two Test Mode files at another rate: %d of %d included, %d sweeps.', ...
    Sr.NumIncluded,Sr.NumFiles,Sr.NumSweeps);
assert(Sr.InferredLabel == string(Sr.Day,'yyyy-MM-dd') && Sr.InferredLabel == "2026-10-01", ...
    'A folder named for its subject alone is labelled by its day ("%s").',Sr.InferredLabel);

% Every session against mabr.analysis.Session over its folder: the files it
% would include, their sweeps and conditions, units, acquisition modes, and
% whether any run is short.
nCmp = 0;
for cat = {c1,c77,cRates}
    T = cat{1}.Sessions;
    for r = 1:height(T)
        s  = mabr.analysis.Session(T.Path(r),Verbose=false,KeepTraces=false);
        Fs = s.Files;
        inc = Fs.Include;
        w = T.Key(r);
        assert(T.NumFiles(r) == height(Fs) && T.NumIncluded(r) == nnz(inc) && ...
            T.NumSweeps(r) == sum(Fs.nSweeps(inc)),'%s: files %d/%d, included %d/%d, sweeps %d/%d (catalog/Session).', ...
            w,T.NumFiles(r),height(Fs),T.NumIncluded(r),nnz(inc),T.NumSweeps(r),sum(Fs.nSweeps(inc)));
        ck = strings(nnz(inc),1);
        for p = reshape(s.KeyParams,1,[])
            ck = ck + p + "=" + mabr.analysis.Stats.keyValue(Fs.(p)(inc)) + "|";
        end
        assert(T.NumConditions(r) == numel(unique(ck)),'%s: %d conditions, Session keys %d.', ...
            w,T.NumConditions(r),numel(unique(ck)));
        modes = "";
        if ~isempty(s.AcqModes), modes = join(s.AcqModes,", "); end
        assert(T.Units(r) == s.Units && T.LevelUnit(r) == s.LevelUnit && T.AcqModes(r) == modes, ...
            '%s: units "%s"/"%s", level unit "%s"/"%s", modes "%s"/"%s".',w,T.Units(r),s.Units, ...
            T.LevelUnit(r),s.LevelUnit,T.AcqModes(r),modes);
        assert((T.ShortRuns(r) > 0) == any(Fs.Short),'%s: ShortRuns %d, Session short files %d.', ...
            w,T.ShortRuns(r),nnz(Fs.Short));
        nCmp = nCmp + 1;
    end
end
fprintf('  PASS Part G: %d sessions agree with mabr.analysis.Session over the same folder (included files, sweeps, conditions, units, modes, short runs), Test Mode dropped before the rate rule; a subject-named folder labelled by its day\n', ...
    nCmp);

% =========================================================================
%  Project
% =========================================================================
% The Project checks of 12_impl_plan U5: open writes nothing, ensureSessions,
% labels and coercion, columns, pools, atomic reload-merge-write save, view
% statuses, aggregate and DuplicatePolicy, exportItems, importStore. They
% use the study tree, the warm cache in cacheA and the planted store under
% SUBJ-ID-959.
ctx = struct('Work',work,'Study',study,'Study2',study2,'Info',info,'CacheFolder',cacheA, ...
    'Catalog',ref,'Catalog77',c77,'Store959',store959);
if exist('mabr.analysis.Project','class') ~= 8
    fprintf('  SKIP Project (W2): mabr.analysis.Project does not exist yet\n');
else
    projectChecks(ctx);
end

% =========================================================================
%  Leaks
% =========================================================================
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_catalog left a figure open.');
tm = timerfindall;
if ~isempty(tm)
    assert(~any(startsWith(string(get(tm,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
assert(isequal(rng,rng0),'The global random stream was drawn from.');
clear cleanup
assert(~isfolder(work),'The temporary folder was not removed.');
fprintf('== verify_offline_catalog PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Project (W2) checks
% =========================================================================
function projectChecks(ctx)
% mabr.analysis.Project over the study tree, with hand-made results files
% (the results-v2 variables a status, a review count and a study table
% read) in a results store redirected into the temporary folder.
P     = 'mabr.analysis.Project';
work  = ctx.Work;
study = ctx.Study;
store = fullfile(work,"projstore");
tPr   = tic;
c = mabr.analysis.Catalog(study,CacheFolder=ctx.CacheFolder,ResultsFolder=store);
c.scan();
assert(c.ResultsFolder == string(store),'Setup: the results folder override did not take.');
k959B = "SUBJ-ID-959/SUBJ-ID-959_Baseline";   k959S = "SUBJ-ID-959/SUBJ-ID-959_stimgen";
k959T = "SUBJ-ID-959/SUBJ-ID-959_TestOnly";   k959W = "SUBJ-ID-959/SUBJ-ID-959_2weeks";
k54B  = "SUBJ-ID-1254/SUBJ-ID-1254_Baseline"; k54M  = "SUBJ-ID-1254/SUBJ-ID-1254_261001T140000";
k54W  = "SUBJ-ID-1254/SUBJ-ID-1254_2weeks";   kOld  = "Pilot/run_old";
assert(all(ismember([k959B k959S k959T k959W k54B k54M k54W kOld],c.Sessions.Key)) && height(c.Sessions) == 8, ...
    'Setup: the study should hold the eight sessions of Part A.');

% =========================================================================
%  P1 -- open and ensureSessions write nothing; Timepoints; Test Mode
% =========================================================================
s0 = snapshot(work);
p = mabr.analysis.Project.open(store);
assert(isa(p,P) && height(p.Sessions) == 0 && p.Revision == 0 && ~p.Dirty && ~p.ReadOnly && ...
    p.File == string(fullfile(store,"project.mat")),'open() of an empty store: a new empty project.');
assert(isequal(p.Columns.Name,["Timepoint";"Group"]) && all(p.Columns.Builtin), ...
    'A new project has the two built-in columns.');
p.ensureSessions(c);
assert(~p.Dirty && height(p.Sessions) == 8 && isequal(p.Subjects.Subject,["SUBJ-ID-959";"SUBJ-ID-1254"]), ...
    'ensureSessions: 8 sessions, 2 subjects in natural order, and not Dirty.');
tpOf = @(k) p.Sessions.Timepoint(p.Sessions.Key == k);
got = arrayfun(@(k) tpOf(k),[k959B k959S k959T k959W k54B k54M kOld k54W]);
assert(isequal(got,["Baseline" "Baseline" "Baseline" "2weeks" "Baseline" "Baseline" "Baseline" "2weeks"]), ...
    'Timepoints (same-day rule; inferred labels otherwise): %s.',strjoin(got,', '));
row = @(k) p.Sessions(p.Sessions.Key == k,:);
assert(~row(k959T).InStudy && row(k959T).ExcludeReason == "Test Mode" && row(k959S).InStudy && ...
    row(k959S).ExcludeReason == "",'An all-Test-Mode session is not in the study (defect 17); a mixed one is.');
assert(isequal(p.Columns.Levels{p.Columns.Name == "Timepoint"},["Baseline";"2weeks"]), ...
    'Timepoint levels by median visit date.');
assert(all(isnat(p.Sessions.Modified)) && all(~isnat(p.Sessions.Day)),'New rows: Modified NaT, Day set.');
p.ensureSessions(c);
assert(height(p.Sessions) == 8,'A second ensureSessions adds nothing.');
V = p.view(c,[]);
assert(height(V) == 8 && all(V.Status == "none") && all(V.StatusText == "Not analysed") && ...
    all(ismember(["Timepoint" "InStudy" "Group" "TimepointOrder" "DaysFromReference" "UsedInStudy" ...
    "IsPool" "PoolKey"],string(V.Properties.VariableNames))),'view() before any analysis.');
assert(isequal(snapshot(work),s0) && ~isfolder(store),'open/ensureSessions/view wrote something.');
fprintf('  PASS Project P1: open and ensureSessions write nothing; Timepoints by the same-day rule; Test Mode not in study (defect 17)\n');

% =========================================================================
%  P2 -- labels: routing by level, coercion, numbers, overrides
% =========================================================================
[v,note] = p.label(k959S,"Timepoint","baseline ");
assert(v == "Baseline" && contains(note,"Baseline") && p.Dirty && ~isnat(row(k959S).Modified), ...
    '"baseline " should become "Baseline" with a note (got "%s", "%s").',v,note);
[v,note] = p.label(k959W,"timepoint"," 2 weeks");
assert(v == "2weeks" && note ~= "",'"2 weeks" differs from "2weeks" only by spacing (got "%s").',v);
p.label(k54W,"Timepoint","Week 6");
lv = p.Columns.Levels{p.Columns.Name == "Timepoint"};
assert(isequal(lv,["Baseline";"2weeks";"Week 6"]),'A new Timepoint joins the levels at the end.');
p.label(k54W,"Timepoint","2weeks");
p.label(k959B,"Group","Noise");
assert(p.Subjects.Group(p.Subjects.Subject == "SUBJ-ID-959") == "Noise" && ...
    ~ismember("Group",p.Sessions.Properties.VariableNames),'Group from a session key edits the animal.');
[v,note] = p.label("subj_id_1254","group","noise ");
assert(v == "Noise" && note ~= "" && p.Subjects.Group(p.Subjects.Subject == "SUBJ-ID-1254") == "Noise" && ...
    ~isnat(p.Subjects.Modified(p.Subjects.Subject == "SUBJ-ID-1254")), ...
    'A subject key in any spelling; "noise " coerced to "Noise".');
p.label("SUBJ-ID-1254","Group","Sham");
p.addColumn("Weight","subject","number");
v = p.label(k54B,"Weight","62.5");
assert(v == 62.5 && p.Subjects.Weight(p.Subjects.Subject == "SUBJ-ID-1254") == 62.5,'Numeric text into a number column.');
assertError(@() p.label(k54B,"Weight","heavy"),'mabr:analysis:Project:badValue');
assertError(@() p.label(k54B,"Nope",1),'mabr:analysis:Project:unknownColumn');
assertError(@() p.label("SUBJ-ID-1254","Timepoint","x"),'mabr:analysis:Project:badLevel');
assertError(@() p.label("nowhere","Comment","x"),'mabr:analysis:Project:unknownKey');
p.label(k54B,"ConductionDelayOverride",0.29);
p.label(k54B,"TimeOffsetOverride","0.05");
assertError(@() p.label(k54B,"ConductionDelayOverride",-1),'mabr:analysis:Project:badValue');
o = p.sessionOverrides(k54B);
assert(o.ConductionDelay == 0.29 && o.TimeOffset == 0.05 && isnan(o.UnitOverride.InputFullScale) && ...
    isequal(o.Members,k54B),'sessionOverrides carries the conduction delay and time offset (A9).');
sx = mabr.analysis.Session("",Parse=false,Verbose=false);
p.applyOverrides(sx,k54B);
assert(sx.ConductionDelayOverride == 0.29 && sx.TimeOffset == 0.05 && isnan(sx.UnitOverride.AmplifierGain), ...
    'applyOverrides puts the overrides on a Session.');
if isprop(sx,'LatencyOffset')
    assert(abs(sx.LatencyOffset - 0.34) < 1e-12,'The Session''s LatencyOffset is the override delay + offset (%g).', ...
        sx.LatencyOffset);
end
p.label("SUBJ-ID-959","InStudy",false);
assert(~p.Subjects.InStudy(p.Subjects.Subject == "SUBJ-ID-959") && row(k959B).InStudy, ...
    'InStudy through a subject key is the animal''s.');
p.label("SUBJ-ID-959","InStudy","yes");
[v,note] = p.label(kOld,"SubjectOverride","subj_id_1254");
assert(v == "SUBJ-ID-1254" && note ~= "",'A subject override is canonical.');
p.label(kOld,"SubjectOverride","");
fprintf('  PASS Project P2: labels routed by level (Group from a session edits the animal), case/space coercion with a note, numbers refused as text, overrides incl. ConductionDelayOverride (A9)\n');

% =========================================================================
%  P3 -- columns and levels
% =========================================================================
p.addColumn("Ear","session","text");
p.label(k54B,"Ear","Left");
[v,note] = p.label(k54M,"ear","left");
assert(v == "Left" && note ~= "",'A free text column coerces to its levels too.');
p.renameColumn("Ear","Side");
assert(ismember("Side",p.Sessions.Properties.VariableNames) && ~ismember("Ear",p.Sessions.Properties.VariableNames) && ...
    any(p.Columns.Name == "Side") && row(k54B).Side == "Left",'renameColumn keeps the values.');
p.removeColumn("side");
assert(~ismember("Side",p.Sessions.Properties.VariableNames) && ~any(p.Columns.Name == "Side"),'removeColumn.');
assertError(@() p.removeColumn("Timepoint"),'mabr:analysis:Project:builtinColumn');
assertError(@() p.addColumn("timepoint","session"),'mabr:analysis:Project:columnExists');
assertError(@() p.renameColumn("Group","Cohort"),'mabr:analysis:Project:builtinColumn');
p.setLevels("Timepoint",["2weeks" "Baseline"]);
lv = p.Columns.Levels{p.Columns.Name == "Timepoint"};
assert(isequal(lv,["2weeks";"Baseline";"Week 6"]),'setLevels orders; unlisted levels follow.');
V = p.view(c,[]);
assert(V.TimepointOrder(V.Key == k959B) == 2 && V.TimepointOrder(V.Key == k959W) == 1,'TimepointOrder follows the levels.');
assert(V.DaysFromReference(V.Key == k959B) == -14 && V.DaysFromReference(V.Key == k959W) == 0, ...
    'DaysFromReference counts from the first timepoint.');
p.setLevels("Timepoint",["Baseline" "2weeks"]);
V = p.view(c,[]);
assert(V.DaysFromReference(V.Key == k959W) == 14 && V.DaysFromReference(V.Key == k54M) == 0,'DaysFromReference from Baseline.');
assertError(@() p.setLevels("Weight",["a" "b"]),'mabr:analysis:Project:badColumn');
fprintf('  PASS Project P3: free columns added, renamed and removed (built-ins refused); Levels order TimepointOrder and DaysFromReference\n');

% =========================================================================
%  P4 -- pools
% =========================================================================
p.label(k54M,"InStudy",false);
key = p.addPool([k54M k54B]);
assert(key == "pool:" + mabr.analysis.Stats.hex8(join(sort([k54B;k54M]),"|")),'The pool key hashes the sorted members.');
assert(~row(k54B).InStudy && ~row(k54M).InStudy && row(key).InStudy && row(key).Timepoint == "Baseline", ...
    'Pool members leave the study; the pool is in it.');
assert(isequal(p.poolMembers(key),sort([k54B;k54M])) && p.addPool([k54B k54M]) == key && height(p.Pools) == 1, ...
    'poolMembers; pooling again returns the same pool.');
V = p.view(c,[]);
pv = V(V.Key == key,:);
assert(pv.IsPool && pv.NumFiles == sum(V.NumFiles(ismember(V.Key,[k54B k54M]))) && ...
    pv.ResultsFile == c.resultsFile([k54B k54M]) && all(V.PoolKey(ismember(V.Key,[k54B k54M])) == key), ...
    'view lists the pool with its members'' files and its pooled results file.');
assertError(@() p.addPool([k959B k54W]),'mabr:analysis:Project:poolSubjects');
assertError(@() p.addPool(k959B),'mabr:analysis:Project:badPool');
kf = p.addPool([k959B k54W],"cross",Force=true);
p.removePool(kf);
assert(row(k959B).InStudy && row(k54W).InStudy && ~any(p.Sessions.Key == kf),'removePool restores and drops its row.');
p.removePool(key);
assert(row(k54B).InStudy && ~row(k54M).InStudy && height(p.Pools) == 0,'removePool restores the previous InStudy (1 and 0).');
p.label(k54M,"InStudy",true);
fprintf('  PASS Project P4: pools (members out of study and restored, cross-subject refused unless Force, the hashed key and its pooled results file)\n');

% =========================================================================
%  P5 -- save: atomic, format, reload-merge-write, read-only newer format
% =========================================================================
p.save();
pf = fullfile(store,"project.mat");
L = load(pf);
F = L.MABRAnalysisProject;
need = ["FormatVersion" "Revision" "Saved" "AnalysisRoot" "Subjects" "Sessions" "Columns" "Pools" ...
    "Settings" "DuplicatePolicy" "ReferenceTimepoint" "ReviewQueue" "ImportedStores" "IgnoredStores"];
assert(isfile(pf) && p.Revision == 1 && ~p.Dirty && F.FormatVersion == 1 && F.Revision == 1 && ...
    all(isfield(F,need)) && isempty(dir(fullfile(store,"*.tmp-*"))),'The first save: project.mat §16.2, Revision 1, no temporary file.');
assert(isequal(fieldnames(L),{'MABRAnalysisProject'}),'project.mat holds one variable.');
q = mabr.analysis.Project.open(store);
assert(isequaln(q.Sessions,p.Sessions) && isequaln(q.Subjects,p.Subjects) && isequaln(q.Columns,p.Columns) && ...
    q.Revision == 1 && ~q.Dirty,'A project reloads as it was saved.');
p.label(k959B,"Comment","from p");
q.label(k959W,"Comment","from q");
q.addColumn("Cage","subject","text");
p.save();
q.save();
r = mabr.analysis.Project.open(store);
cm = @(pp,k) pp.Sessions.Comment(pp.Sessions.Key == k);
assert(cm(r,k959B) == "from p" && cm(r,k959W) == "from q" && r.Revision == 3 && ...
    ismember("Cage",r.Subjects.Properties.VariableNames) && ismember("Weight",r.Subjects.Properties.VariableNames), ...
    'Two projects editing different rows (and columns) both survive the merge.');
p.label(kOld,"Comment","p first");
pause(0.05);
q.label(kOld,"Comment","q later");
q.save();
p.save();
r = mabr.analysis.Project.open(store);
assert(cm(r,kOld) == "q later" && cm(p,kOld) == "q later" && r.Revision == 5, ...
    'The same row edited twice: the later Modified wins, whoever saves last.');
% Whole fields the other writer changed while this side did not: a pool it
% dissolved and a column it removed stay gone (a resurrected pool would put
% it AND its restored members in the study).
p = r;
kp = p.addPool([k54M k54B]);
p.save();
q = mabr.analysis.Project.open(store);
q.removePool(kp);
q.removeColumn("Cage");
q.save();
p.label(kOld,"Comment","after the pool");
p.save();
r = mabr.analysis.Project.open(store);
assert(height(r.Pools) == 0 && ~any(r.Sessions.Key == kp) && ~ismember("Cage",r.Subjects.Properties.VariableNames) && ...
    ~any(r.Columns.Name == "Cage") && all(r.Sessions.InStudy(ismember(r.Sessions.Key,[k54B k54M]))) && ...
    cm(r,kOld) == "after the pool" && height(p.Pools) == 0,['A pool dissolved and a column removed by the other ' ...
    'writer stay gone when this side saves after them.']);
p = r;                                   % carry on from what is on disk
ro = fullfile(work,"rostore");
mkdir(ro);
MABRAnalysisProject = p.toStruct();
MABRAnalysisProject.FormatVersion = 2;
MABRAnalysisProject.NewThing = 1;
save(fullfile(ro,"project.mat"),'MABRAnalysisProject');
mkdir(fullfile(ro,"bad"));
fid = fopen(fullfile(ro,"bad","project.mat"),'w');
fwrite(fid,'not a MAT-file');
fclose(fid);
sRO = snapshot(ro);
pr = mabr.analysis.Project.open(ro);
assert(pr.ReadOnly && pr.FileFormatVersion == 2 && height(pr.Sessions) == 8 && ~isempty(pr.Warnings), ...
    'A newer format: known fields read, read-only.');
assertError(@() pr.save(),'mabr:analysis:Project:readOnly');
pb = mabr.analysis.Project.open(fullfile(ro,"bad"));
assert(pb.ReadOnly && contains(pb.Warnings(1),"could not be read"),'An unreadable project.mat opens read-only.');
assertError(@() pb.save(),'mabr:analysis:Project:readOnly');
assert(isequal(snapshot(ro),sRO),'A read-only project.mat is never written.');
fprintf('  PASS Project P5: atomic save (format §16.2, Revision), reload-merge-write: different rows both kept, same row later Modified wins; newer format and unreadable files read-only\n');

% =========================================================================
%  P6 -- view statuses from hand-made results files
% =========================================================================
S0 = mabr.analysis.Settings();
S1 = mabr.analysis.Settings(NumPermutations=200);
fpOf = @(k) mabr.analysis.Project.fingerprintFor(c,k);
sReal = mabr.analysis.Session(c.Sessions.Path(c.Sessions.Key == k959B),Verbose=false,KeepTraces=false);
assert(sReal.DataFingerprint == fpOf(k959B),'Project.fingerprintFor equals a Session''s DataFingerprint over the same folder.');
fakeResults(c.resultsFile(k959B),k959B,S0,fpOf(k959B),[8 16],[500 500],["accepted" ""]);
fakeResults(c.resultsFile(k959W),k959W,S1,fpOf(k959W),[8 16],[500 500],["" ""]);
fakeResults(c.resultsFile(k54W),k54W,S0,"deadbeef",[8 16],[500 500],["" ""]);
fakeResults(c.resultsFile(kOld),kOld,S0,fpOf(kOld),[8 16],[500 500],["" ""]);
fakeResults(c.resultsFile(k54B),k54B,S0,fpOf(k54B),[8 16],[500 500],["manual" "accepted"]);
fakeResults(c.resultsFile(k54M),k54M,S0,fpOf(k54M),[8 NaN],[300 100],["" ""]);
touch(c.resultsFile(kOld),datetime('now') - hours(1));
p.recordRun(kOld,"Out of memory");
p.recordRun(k959S,"Cannot read file");
V = p.view(c,S0);
sv = @(k) V(V.Key == k,:);
assert(sv(k959B).Status == "current" && startsWith(sv(k959B).StatusText,"Up to date (") && ...
    sv(k959B).Reviewed == 1 && sv(k959B).NumSeries == 2 && sv(k959B).Processing == "continuous" && ...
    sv(k959B).SettingsHash == S0.hash(),'A current results file: status, review count, processing, settings hash.');
assert(sv(k959W).Status == "stale" && sv(k959W).StatusText == "Out of date (settings changed)", ...
    'Results from other settings are stale (%s).',sv(k959W).StatusText);
assert(sv(k54W).Status == "stale" && sv(k54W).StatusText == "Out of date (files changed)", ...
    'Results over other files are stale (%s).',sv(k54W).StatusText);
assert(sv(kOld).Status == "failed" && sv(kOld).StatusText == "Failed: Out of memory" && ...
    sv(k959S).Status == "failed" && sv(k959T).Status == "none" && sv(k959T).StatusText == "Not analysed", ...
    'Failed (newer than the results file, or no results) and none.');
V0 = p.view(c,[]);
assert(V0.Status(V0.Key == k959W) == "current",'Without settings only the data is judged.');
% A per-session override the results were not made with: out of date until a
% re-run (Batch re-runs it for the same reason); taken back, current again.
p.label(k959B,"ConductionDelayOverride",0.2);
V = p.view(c,S0);
assert(V.Status(V.Key == k959B) == "stale" && V.StatusText(V.Key == k959B) == "Out of date (overrides changed)", ...
    'A changed override: %s.',V.StatusText(V.Key == k959B));
p.label(k959B,"ConductionDelayOverride",NaN);
V = p.view(c,S0);
assert(V.Status(V.Key == k959B) == "current",'An override taken back: %s.',V.StatusText(V.Key == k959B));
p.recordRun(kOld,"");
R1 = p.results(k959B,Catalog=c);
assert(isstruct(R1) && all(isfield(R1,["Version" "Summary" "StepState" "Thresholds"])) && ~isfield(R1,'Means'), ...
    'results() reads the small variables.');
R2 = p.results(k959B,Catalog=c,Vars=["Means" "Summary"]);
assert(isfield(R2,'Means') && isfield(R2,'Summary') && ~isfield(R2,'Thresholds') && isempty(p.results(k959T,Catalog=c)), ...
    'results(Vars) and a key without results.');
% A step not run is not current (10 §10.3); a damaged results file is a
% failure in view() and left out of the study tables, never an error.
fT = c.resultsFile(k959T);
fakeResults(fT,k959T,S0,fpOf(k959T),[8 16],[500 500],["" ""]);
Lt = load(fT);
Lt.StepState.peaks = [];
save(fT,'-struct','Lt');
V = p.view(c,S0);
assert(V.Status(V.Key == k959T) == "stale" && V.StatusText(V.Key == k959T) == "Out of date (settings changed)", ...
    'A results file whose peaks step was never run is stale against settings (%s).',V.StatusText(V.Key == k959T));
V = p.view(c,[]);
assert(V.Status(V.Key == k959T) == "current",'Without settings the step states are not judged.');
fid = fopen(fT,'w');  fwrite(fid,'not a MAT-file');  fclose(fid);
V = p.view(c,S0);
assert(V.Status(V.Key == k959T) == "failed" && contains(V.StatusText(V.Key == k959T),"cannot be read"), ...
    'An unreadable results file: Failed in view (%s).',V.StatusText(V.Key == k959T));
A = p.aggregate([k959T k959B],c);
assert(height(A.Sessions) == 1 && A.Sessions.Session == k959B,'An unreadable results file is left out of aggregate.');
delete(fT);
fprintf('  PASS Project P6: view statuses none/current/stale (settings; files via Session.fingerprintOf)/failed, StatusText, Reviewed, NumSeries, Processing, SettingsHash, overrides changed; the results cache\n');

% =========================================================================
%  P7 -- aggregate: duplicates under each policy, UsedInStudy
% =========================================================================
keys = [k54B k54M k959B k959W];
A = p.aggregate(keys,c,Waveforms=true);
f8 = "Stimulus=Tone|AcqMode=conventional|Frequency=8";
use = @(A,k,sk) A.Thresholds.UsedInStudy(A.Thresholds.Session == k & A.Thresholds.Key == sk);
assert(all(isfield(A,["Sessions" "Subjects" "Conditions" "Thresholds" "Peaks" "PeakMeasures" "IOSlopes" "Means" "Duplicates"])), ...
    'aggregate returns every study table.');
assert(height(A.Sessions) == 4 && height(A.Subjects) == 2 && height(A.Thresholds) == 8 && ...
    height(A.Conditions) == 4*6 && height(A.Means) == 24 && ~ismember("Fit",A.Thresholds.Properties.VariableNames), ...
    'Study tables: 4 sessions, 2 subjects, 8 series, 24 conditions (got %d/%d/%d/%d).', ...
    height(A.Sessions),height(A.Subjects),height(A.Thresholds),height(A.Conditions));
assert(use(A,k54B,f8) && ~use(A,k54M,f8) && use(A,k54M,"Stimulus=ClickTrain|AcqMode=conventional") && ...
    height(A.Duplicates) == 1 && A.Duplicates.SeriesKey == f8 && A.Duplicates.Used == k54B && ...
    A.Duplicates.Timepoint == "Baseline",'most-sweeps keeps the 500-sweep session''s 8 kHz series.');
pk = A.Peaks(A.Peaks.Session == k54M,:);
assert(all(pk.UsedInStudy == (pk.SeriesKey ~= f8)) && height(A.PeakMeasures) > 0 && height(A.IOSlopes) > 0, ...
    'Peaks carry UsedInStudy; measures and slopes are derived.');
assert(A.Sessions.DaysFromReference(A.Sessions.Session == k959W) == 14 && ...
    isequal(A.Thresholds.Properties.VariableNames(1:4),{'Session','Subject','Timepoint','Group'}), ...
    'Label columns and DaysFromReference.');
A = p.aggregate(keys,c,DuplicatePolicy="latest");
assert(~use(A,k54B,f8) && use(A,k54M,f8) && A.Duplicates.Used == k54M,'latest keeps the later session''s series.');
A = p.aggregate(keys,c,DuplicatePolicy="mean");
assert(use(A,k54B,f8) && use(A,k54M,f8) && A.Duplicates.Used == k54B + "|" + k54M,'mean keeps both.');
p.label(k959W,"InStudy",false);
A = p.aggregate(keys,c);
assert(~any(A.Thresholds.UsedInStudy(A.Thresholds.Session == k959W)) && ~A.Sessions.InStudy(A.Sessions.Session == k959W), ...
    'A session out of the study contributes nothing.');
p.label(k959W,"InStudy",true);
p.setDuplicatePolicy("latest");
assert(p.DuplicatePolicy == "latest",'setDuplicatePolicy.');
A = p.aggregate(keys,c);
assert(use(A,k54M,f8),'The project policy is the default.');
p.setDuplicatePolicy("most-sweeps");
assertError(@() p.setDuplicatePolicy("best"),'mabr:analysis:Project:badPolicy');
V = p.view(c,S0);
sv = @(k) V(V.Key == k,:);
% Over the whole study Pilot/run_old is SUBJ-ID-1254 at Baseline too, with
% as many sweeps as the Baseline session: the tie goes to the later one.
assert(~sv(k54B).UsedInStudy && sv(kOld).UsedInStudy && sv(k54M).UsedInStudy && ~sv(k959T).UsedInStudy, ...
    'view UsedInStudy: a most-sweeps tie goes to the later session.');
fprintf('  PASS Project P7: aggregate from results only (sessions, subjects, conditions, thresholds, peaks, measures, slopes, means); duplicates under most-sweeps (a tie to the later session)/latest/mean with UsedInStudy and Duplicates\n');

% =========================================================================
%  P7b -- aggregate's per-file cache answers what a fresh project computes
% =========================================================================
% What aggregate makes from each results file (Peaks.derived, the tables
% with and without labels, the series' sweep counts) is remembered with the
% file until it changes, so the Study tab's call after every label edit
% stays cheap. The project that has been answering all along must agree,
% table for table, with one opened fresh from the same project.mat: warm,
% after label edits that change labels, study use and duplicates, and
% after a results file is rewritten.
tc = tic;
keys = [k54B k54M k959B k959W kOld];
A0 = cacheMatchesFresh(p,store,c,keys,S0,"warm");
assert(isequaln(p.aggregate(keys,c,Waveforms=true),A0),'A second aggregate differs from the first.');
tp0 = p.Sessions.Timepoint(p.Sessions.Key == k54M);
g0  = p.Subjects.Group(p.Subjects.Subject == "SUBJ-ID-959");
p.label(k54M,"Timepoint","2weeks");          % no longer a Baseline duplicate of k54B
p.label("SUBJ-ID-959","Group","Sham");       % the animal: every one of its sessions relabelled
p.label(k959W,"InStudy",false);              % its series no longer used
A1 = cacheMatchesFresh(p,store,c,keys,S0,"after label edits");
assert(all(A1.Thresholds.Group(A1.Thresholds.Subject == "SUBJ-ID-959") == "Sham") && ...
    ~any(A1.Thresholds.UsedInStudy(A1.Thresholds.Session == k959W)) && ...
    all(A1.Thresholds.Timepoint(A1.Thresholds.Session == k54M) == "2weeks"), ...
    'The label edits did not reach the study tables.');
% A rewritten results file is derived again (its stamp moved); the others
% are not touched.
f959 = c.resultsFile(k959B);
fakeResults(f959,k959B,S0,fpOf(k959B),[8 16],[500 500],["noresponse" ""]);
touch(f959,datetime('now') + minutes(2));
A2 = cacheMatchesFresh(p,store,c,keys,S0,"after a results file was rewritten");
assert(A2.Thresholds.Decision(A2.Thresholds.Session == k959B & A2.Thresholds.Frequency == 8) == "noresponse", ...
    'The rewritten results file was not read again.');
% Put everything back as P8 and P9 expect it.
p.label(k54M,"Timepoint",tp0);
p.label("SUBJ-ID-959","Group",g0);
p.label(k959W,"InStudy",true);
fakeResults(f959,k959B,S0,fpOf(k959B),[8 16],[500 500],["accepted" ""]);
touch(f959,datetime('now') + minutes(4));
cacheMatchesFresh(p,store,c,keys,S0,"labels and file put back");
fprintf(['  PASS Project P7b: aggregate''s per-file cache equals a freshly opened project''s ' ...
    'tables (and view) warm, after Timepoint/Group/InStudy edits and after a results file is ' ...
    'rewritten (%.1f s)\n'],toc(tc));

% =========================================================================
%  P8 -- exportItems and batchItems
% =========================================================================
items = p.exportItems([k54B k959S kOld],c);
assert(numel(items) == 2 && isequal(fieldnames(items)',{'Key','Results','Labels','Notes','Session'}) && ...
    isequal([items.Key],[k54B kOld]),'exportItems: one item per key with results (§15.1).');
Lb = items(1).Labels;
needL = ["Subject" "SubjectRaw" "Timepoint" "TimepointOrder" "Group" "InStudy" "TestMode" ...
    "DaysFromReference" "TimeOffset" "ConductionDelay" "Comment" "Free" "UsedInStudy"];
assert(all(isfield(Lb,needL)) && Lb.ConductionDelay == 0.29 && Lb.TimeOffset == 0.05 && ...
    Lb.Group == "Sham" && Lb.Timepoint == "Baseline" && isstruct(Lb.Free) && ...
    isequal(sort(Lb.UsedInStudy.SeriesKey),sort(string(items(1).Results.Thresholds.Key))) && ...
    ~isfield(items(1).Results,'Sweeps') && isfield(items(1).Results,'Means') && isempty(items(1).Session) && ...
    istable(items(1).Notes) && isnan(items(2).Labels.ConductionDelay),'exportItems Labels, Results and Notes.');
% The items are what Export.tables takes: the overrides reach the latencies.
Tx = mabr.analysis.Export.tables(items);
px = Tx.peaks(Tx.peaks.session_id == k54B,:);
assert(height(Tx.thresholds) == 4 && height(px) > 0 && all(px.conduction_delay_ms == 0.29) && ...
    all(px.time_offset_ms == 0.05) && all(abs(px.lat_peak_ms - (px.lat_peak_raw_ms - 0.34)) < 1e-9), ...
    'Export.tables over exportItems: the conduction delay and time offset overrides reach the latencies.');
B = p.batchItems([k54B kOld],c);
assert(isequal(string(B.Properties.VariableNames),["Key" "Paths" "ResultsFile" "Exclude" "UnitOverride" ...
    "TestMode" "TimeOffset" "ConductionDelay"]) && B.ConductionDelay(1) == 0.29 && ...
    B.Paths{1} == c.Sessions.Path(c.Sessions.Key == k54B) && B.ResultsFile(2) == c.resultsFile(kOld), ...
    'batchItems carries the paths, results file and overrides.');
fprintf('  PASS Project P8: exportItems shape (§15.1: Labels with TimeOffset/ConductionDelay overrides, UsedInStudy, Free; Results without sweeps; Notes) accepted by Export.tables with the overrides in the latencies; batchItems and applyOverrides\n');

% =========================================================================
%  P9 -- importStore copies and re-keys, never touching the nested store
% =========================================================================
nested = string(ctx.Store959);            % SUBJ-ID-959/MABR_Analysis
assert(any(strcmpi(c.NestedStores.Path,nested)),'Setup: the planted store is a nested store.');
np = mabr.analysis.Project(nested);
c959 = mabr.analysis.Catalog(fullfile(study,"SUBJ-ID-959"),CacheFolder=ctx.CacheFolder, ...
    ResultsFolder=fullfile(work,"unused"));
c959.scan();
np.ensureSessions(c959);
np.label("SUBJ-ID-959_TestOnly","Comment","nested T");
np.label("SUBJ-ID-959_Baseline","Comment","nested B");
np.addColumn("Litter","subject","text");
MABRAnalysisProject = np.toStruct();
save(fullfile(nested,"project.mat"),'MABRAnalysisProject');
fakeResults(fullfile(nested,"SUBJ-ID-959_TestOnly.mat"),"SUBJ-ID-959_TestOnly",S0,"",[8 16],[100 100],["" ""]);
sN = snapshot(nested);
[n,msg] = p.importStore(nested,c);
assert(isequal(snapshot(nested),sN),'importStore wrote into the nested store.');
dest = c.resultsFile(k959T);
Ld = load(dest,'Summary');
assert(n == 1 && isfile(dest) && Ld.Summary.Key == k959T && isequal(Ld.Summary.Keys,k959T), ...
    'importStore: one results file copied and re-keyed (n = %d).',n);
assert(contains(msg,"skipped SUBJ-ID-959_Baseline.mat") && contains(msg,"kept this project's labels of " + k959B), ...
    'importStore lists the skipped file and the conflict:\n%s',msg);
assert(cm(p,k959T) == "nested T" && cm(p,k959B) == "from p" && any(p.ImportedStores == nested) && ...
    ismember("Litter",p.Subjects.Properties.VariableNames) && p.Dirty, ...
    'Labels merged: an unedited row takes the import; an edited one keeps its own.');
[n2,~] = p.importStore(nested,c);
assert(n2 == 1 && isequal(snapshot(nested),sN),'A second import keeps the newer copy.');
V = p.view(c,S0);
assert(V.Status(V.Key == k959T) ~= "none",'The imported results are found where the key says.');
p.save();
fprintf('  PASS Project P9: importStore copies and re-keys results, merges labels (edited rows win, conflicts listed), never touches the nested store\n');

% =========================================================================
%  P10 -- no Statistics Toolbox
% =========================================================================
hits = forbiddenUses(which(P));
assert(isempty(hits),'Statistics Toolbox identifiers in Project.m:\n%s',strjoin(hits,newline));
fprintf('  PASS Project P10: Project.m calls no Statistics Toolbox function (%.1f s for the Project checks)\n',toc(tPr));
end

function fakeResults(file,key,settings,fp,freqs,nClean,decisions)
% A results-v2 file of the shape §16.1 gives, by hand: per frequency a
% series of three levels (NaN = a click series), conditions with nClean
% sweeps, two picked waves per condition, and stored means.
levels = [40 60 80];
tMs = (-2:0.5:10)';
C = table();  T = table();  Pk = table();
for i = 1:numel(freqs)
    if isnan(freqs(i))
        stim = "ClickTrain";  sk = "Stimulus=ClickTrain|AcqMode=conventional";
    else
        stim = "Tone";  sk = "Stimulus=Tone|AcqMode=conventional|Frequency=" + freqs(i);
    end
    for L = levels
        ck = sk + "|Level=" + L;
        C = [C; table(ck,stim,"conventional",freqs(i),L,nClean(i) + 12,nClean(i),"continuous", ...
            'VariableNames',{'Key','Stimulus','AcqMode','Frequency','Level','nSweeps','nClean','Processing'})]; %#ok<AGROW>
        for w = ["I" "II"]
            lat = 1.2 + (w == "II")*1.1 + (80 - L)*0.01;
            Pk = [Pk; table(ck,sk,stim,"conventional",freqs(i),L,w,"auto",lat,1e-6*L/80,-0.5e-6*L/80, ...
                1.5e-6*L/80,true,false,'VariableNames',{'Key','SeriesKey','Stimulus','AcqMode', ...
                'Frequency','Level','Wave','State','PeakLatency','PeakValue','TroughValue','AmpPT', ...
                'Detectable','BelowThreshold'})]; %#ok<AGROW>
        end
    end
    T = [T; table(sk,stim,"conventional",freqs(i),"Level","perm-glm",50,"ok","interval",40,60, ...
        decisions(i),50,"interval",40,60,40,80,20,{struct()},'VariableNames',{'Key','Stimulus', ...
        'AcqMode','Frequency','LevelParam','Method','Threshold','Status','Censored','ThrLo','ThrHi', ...
        'Decision','Final','FinalCensored','FinalLo','FinalHi','MinLevel','MaxLevel','LevelStep','Fit'})]; %#ok<AGROW>
end
R = struct();
R.Version = 2;
R.Provenance = struct('AnalyzedAt','2026-09-30T15:40:00','MATLABVersion',version, ...
    'MABRVersion',"unknown",'Host',"test",'User',"test",'SettingsHash',settings.hash());
R.Settings = settings.toStruct();
SS = struct();
for st = mabr.analysis.Settings.Steps
    SS.(st) = struct('At','2026-09-30T15:40:00','Settings',settings.stepSettings(st),'Fingerprint',fp);
end
R.StepState = SS;
R.Summary = struct('Key',key,'Keys',key,'Name',key,'Subject',"",'Date','2026-10-01T10:00:00', ...
    'Time',tMs,'KeyParams',["Stimulus" "AcqMode" "Frequency" "Level"],'LevelParam',"Level", ...
    'GroupParams',["Stimulus" "AcqMode" "Frequency"],'TestMode',false,'Units',"V",'LevelUnit',"dB SPL", ...
    'DataFingerprint',fp,'NumFiles',height(C),'NumConditions',height(C),'Exclude',strings(0,1), ...
    'UnitOverride',struct('InputFullScale',NaN,'AmplifierGain',NaN),'TimeOffset',NaN, ...
    'ConductionDelayOverride',NaN);
R.Conditions = C;
nC = height(C);
rs = RandStream('threefry','Seed',1);
R.Means = struct('Keys',C.Key,'Balanced',single(randn(rs,numel(tMs),nC)*1e-6), ...
    'Positive',single(NaN(numel(tMs),nC)),'Negative',single(NaN(numel(tMs),nC)), ...
    'SEM',single(ones(numel(tMs),nC)*1e-7),'N',C.nClean);
R.Thresholds = T;
R.Peaks = Pk;
d = fileparts(char(file));
if ~isfolder(d), mkdir(d); end
save(char(file),'-struct','R');
end

% =========================================================================
%  Helpers
% =========================================================================
function A = cacheMatchesFresh(p,store,c,keys,settings,what)
% p.aggregate (with whatever p's caches hold) equal, table for table, to the
% aggregate of a project opened fresh from what p saves -- and the same for
% view (the two share the duplicate resolution and its cached sweep counts).
A = p.aggregate(keys,c,Waveforms=true);
V = p.view(c,settings);
p.save();
q = mabr.analysis.Project.open(store);
q.ensureSessions(c);
Aq = q.aggregate(keys,c,Waveforms=true);
fn = fieldnames(Aq);
assert(isequal(sort(fieldnames(A)),sort(fn)),'aggregate''s tables differ (%s).',what);
for k = 1:numel(fn)
    assert(isequaln(A.(fn{k}),Aq.(fn{k})), ...
        'aggregate''s %s from the cache differs from a fresh project''s (%s).',fn{k},what);
end
Vq = q.view(c,settings);
assert(isequaln(V,Vq),'view from the cache differs from a fresh project''s (%s).',what);
end

function scanUnchanged(c,root,args)
% c.scan(args{:}) with the tree under root byte-for-byte the same after it,
% and no MABR_Analysis folder created at root.
hadStore = isfolder(fullfile(root,"MABR_Analysis"));
s0 = snapshot(root);
c.scan(args{:});
s1 = snapshot(root);
assert(isequal(s0,s1),'A scan of %s wrote under it:\n%s',root, ...
    strjoin([setdiff(s1,s0); setdiff(s0,s1)],newline));
assert(isfolder(fullfile(root,"MABR_Analysis")) == hadStore,'A scan created %s.',fullfile(root,"MABR_Analysis"));
end

function s = snapshot(root)
% Every file and folder under root with its size and modified time.
d = dir(fullfile(char(root),'**'));
d = d(~ismember({d.name},{'.','..'}));
s = sort(reshape(string(fullfile({d.folder},{d.name})) + "|" + string([d.bytes]) + "|" + ...
    compose('%.10f',[d.datenum]) + "|" + string([d.isdir]),[],1));
end

function touch(file,when)
% Give a file another modified time without changing a byte.
ok = false;
if usejava('jvm')
    when.TimeZone = 'local';
    ok = java.io.File(char(file)).setLastModified(round(posixtime(when)*1000));
end
if ~ok
    pause(1.1);
    fid = fopen(file,'r+');
    b = fread(fid,1,'*uint8');
    fseek(fid,0,'bof');
    fwrite(fid,b);
    fclose(fid);
end
end

function M = dropRecordField(M)
% A cache whose first record lacks a field the reader now writes.
E = M.Entries;
E.Rec{1} = rmfield(E.Rec{1},'LevelScale');
M.Entries = E;
end

function writeText(file,lines)
fid = fopen(file,'w','n','UTF-8');
assert(fid > 0,'Cannot write %s.',file);
fprintf(fid,'%s\n',lines);
fclose(fid);
end

function s = folderOf(p)
% The last component of each path.
s = regexprep(reshape(string(p),[],1),'^.*[\\/]','');
end

function recordCall(calls,m,k,n)
% A progress sink that records every call (calls is a containers.Map, a handle).
calls(double(calls.Count + 1)) = {m,k,n}; %#ok<NASGU>
end

function cancelAfterStart(box,k)
% A progress sink that cancels at its first call after the start, leaving
% the count it cancelled at in box (a containers.Map, a handle).
if k >= 1
    box('k') = k; %#ok<NASGU>
    error('mabr:analysis:cancelled','Cancelled by user.');
end
end

function assertError(fcn,id)
% fcn throws an error with this identifier.
try
    fcn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected error %s, got %s: %s',id,ME.identifier,ME.message);
    return
end
error('verify:offline:noError','Expected error %s; nothing was thrown.',id);
end

function [hits,where] = forbiddenUses(file)
% Lines of a file that call a Statistics Toolbox function (10 sec. 0) or use
% range/corr/mad as a name: the text of each (hits) and its line number
% (where). Comments and strings are ignored, as is the name a function line
% defines; a name reached through a dot (obj.range) is not the toolbox
% function. (verify_offline_files' scan, which proves it can fail.)
names = ["prctile","quantile","iqr","mad","range","zscore","nanmean","nanstd","nanmedian", ...
    "corr","fcdf","finv","tcdf","tinv","normcdf","norminv","normpdf","randsample","datasample", ...
    "bootstrp","fitglm","fitlm","boxplot","ksdensity","grpstats","skewness","kurtosis"];
asName  = ["range","corr","mad"];
callPat = "(?<![\w.])(" + join(names,"|") + ")\s*\(";
namePat = "(?<![\w.])(" + join(asName,"|") + ")(?!\w)";
lines = splitlines(string(fileread(file)));
code  = codeOnly(lines);
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

function out = codeOnly(lines)
% Each line with its comment and the contents of its strings blanked.
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
                    o(i) = ch;              % a transpose
                else
                    q = '''';
                end
            else
                o(i) = ch;
            end
        elseif ch == q
            if i < numel(s) && s(i+1) == q
                i = i + 1;                  % an escaped quote inside the string
            else
                q = '';
            end
        end
        i = i + 1;
    end
    out(k) = string(o);
end
end
