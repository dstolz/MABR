classdef Catalog < handle
% mabr.analysis.Catalog  Every recording under a data folder, listed without opening one.
%
%   A Catalog is what the offline analysis knows about a data folder before
%   it analyses anything: every .abr file under it, read for its metadata
%   alone, and every folder holding them as a SESSION -- whose subject it is,
%   which day, what was presented and how, whether any of it was Test Mode,
%   and where its results file lives or would live. It is the browser's
%   index, the batch's work list and the study's roll call:
%
%       c = mabr.analysis.Catalog("D:\data\OFC_NoiseExposure");
%       c.scan();
%       c.Sessions(:,["Subject" "Day" "InferredLabel" "Summary"])
%       f = c.resultsFile(c.Sessions.Key(1));         % where its results go
%       T = c.notes(c.Sessions.Key(1));                % notes taken during it
%
%   NOTHING IS WRITTEN UNDER ROOT. A data folder is somebody's raw data, often
%   a synced or shared drive, and listing it must not change it: no index
%   file, no results folder, no lock beside the recordings. The one file a
%   scan writes is its cache, in CacheFolder (the user's local application
%   data by default) -- and a CacheFolder inside Root, or inside the
%   AnalysisRoot above it, disables the cache rather than break that rule.
%   Results are found where they already are
%   (HasResults) and named where they would go (resultsFile); creating them is
%   mabr.analysis.Project's and mabr.analysis.Batch's business.
%
%   ONE READER. Every file is read through mabr.analysis.AbrFile.read, the
%   reader mabr.analysis.Session uses, so a file listed here as a 30 dB tone
%   in an interleaved run is the file a session will analyse as one. The
%   subject, stimulus, parameters, layout and units all come from inside the
%   file; only the subject is ever taken from a name.
%
%   THE CACHE makes a rescan cost the files that changed. Each file's record
%   is kept against its (path, bytes, modified time); a file whose three
%   still match is not opened again (LastScanReads counts the ones that
%   were) -- unless it could not be loaded at all last time, which may have
%   been the moment rather than the file (locked, not yet synced, no
%   permission), so it is tried again at every scan. The cache is one
%   MAT-file per Root,
%   <CacheFolder>/catalog_<hex8(lower(Root))>.mat, and is thrown away and
%   rebuilt -- silently, since nothing is lost but time -- when it is
%   unreadable, belongs to another folder, or was written by another
%   CacheVersion or AbrFile.ReaderVersion. CacheState says which.
%
%   SESSIONS ARE FOLDERS, KEYED BY PATH. A session is one folder holding .abr
%   files (any depth), keyed by its path relative to AnalysisRoot with "/"
%   between folders -- "SUBJ-ID-1254/SUBJ-ID-1254_261001T140000" -- so a key
%   means the same folder on every machine the study is copied to. A folder
%   that IS the analysis root is keyed ".". Folders under a MABR_Analysis
%   results store or a hidden folder (".", or Windows' "$..." and System
%   Volume Information) are never listed.
%
%   ANALYSIS ROOT AND RESULTS. Results and labels for a study live in one
%   store, <AnalysisRoot>/MABR_Analysis. AnalysisRoot is the nearest folder
%   at or above Root that already holds MABR_Analysis/project.mat -- so
%   opening one animal's folder inside a study that has a store keys its
%   sessions into that store -- and Root itself otherwise. ResultsFolder
%   overrides the store's location (a read-only data drive, a test).
%   suggestStudyRoot spots the commonest mistake, opening one animal's folder
%   when its study has no store yet, and names the folder to open instead.
%   NestedStores lists any other store found below Root, for a project to
%   import.
%
%   SUBJECTS ARE CANONICAL. Writers have spelled one animal SUBJ-ID-1254 and
%   SUBJ_ID_1254 side by side; every spelling becomes "SUBJ-ID-" + upper(id)
%   (mabr.analysis.AbrFile.canonicalSubject). A session's subject is the
%   first one named along its folder path (the shallowest wins), else the
%   first one its files' names give, else "(unknown subject)". Subjects sort
%   naturally (SUBJ-ID-959 before SUBJ-ID-1254), then days, then start
%   times.
%
%   NOTES. Every file's ABR_Data.Notes, and every .notes journal, holds the
%   whole rig notebook as it stood -- including what was written about the
%   animal before this one. notes() therefore reads the newest file's
%   notebook (or the folder's newest journal, with times rebuilt from its
%   header), removes repeats, and by default keeps only what was written
%   while this session was being recorded.
%
%   SESSIONS, one row per folder holding .abr files:
%     Key, Path, Name           key, absolute folder, folder name
%     Subject, SubjectRaw       canonical subject, and its spelling as found
%     Day, Start, Stop          the date of Start; the first start and the
%                               last end among its readable files (an
%                               intermixed run's end is estimated: its
%                               presentations times the folder's interval)
%     NumFiles, NumIncluded     .abr files in it; those a Session over it
%                               would include by default (readable, at the
%                               majority rate, no Test Mode beside real data)
%     NumSweeps, NumConditions  over the included files, conditions keyed as
%                               a Session keys them (acquisition modes apart)
%     Stimuli, Summary          "ClickTrain, Tone"; "Tone 6×9 ×2 · ClickTrain
%                               ×9 ×2" -- values per parameter (×n for one),
%                               then files per condition when more than one
%     AcqModes, HasCompact      "conventional, interleaved"; any compact file
%     ShortRuns                 runs stopped early: under half the median
%                               sweeps of their stimulus and acquisition mode
%     TestMode                  "none" | "some" | "all" of its readable files
%     Units, LevelUnit          the included files' ("mixed" if they differ)
%     NotesFile                 its newest .notes journal ("" for none)
%     InferredLabel             inferLabel of its name, else its Day
%     ResultsFile, HasResults   resultsFile(Key), and whether it exists
%   FILES carry mabr.analysis.AbrFile's fields of the same names, plus FileId
%   (Session's "<folder name>/<file name>"), SessionKey, Subject (the file
%   name's, else its session's) and DuplicateOf: for a recording copied into
%   a second session folder, the original's "<key>/<file name>".
%
%   Nothing here prints, raises a dialog, or touches a preference. A scan is
%   atomic: one that fails or is cancelled through its progress sink (which
%   throws mabr:analysis:cancelled) leaves every property as it was.
%
%   See also mabr.analysis.AbrFile, mabr.analysis.Session,
%   mabr.analysis.Stats, mabr.data.SessionNotes.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Root          (1,1) string = ""       % the folder scanned, absolute
        AnalysisRoot  (1,1) string = ""       % keys are relative to this
        ResultsFolder (1,1) string = ""       % the results store (may not exist yet)

        % One row per .abr file under Root (FileColumns), in session order and
        % by start time within a session.
        Files table = table()

        % One row per folder holding .abr files (SessionColumns): subjects in
        % natural order, then days, then start times.
        Sessions table = table()

        % Results stores found below Root other than AnalysisRoot's own: Path
        % (the MABR_Analysis folder), Root (its parent), NumResults.
        NestedStores table = table()

        ScannedAt     (1,1) datetime = NaT    % when the last scan finished
        Warnings      (:,1) string = strings(0,1)   % what the last scan noticed
        CacheFolder   (1,1) string = ""       % "" when caching is disabled
        CacheFile     (1,1) string = ""       % "" when caching is disabled
        LastScanReads (1,1) double = 0        % files the last scan opened (the rest were cached)

        % What the last scan made of the cache: "new", "loaded", "rebuilt
        % (<why>)" or "disabled (<why>)".
        CacheState    (1,1) string = "none"

        % false: a scan opens no file, listing what the cache holds and the
        % rest by name only (Ok false, Error saying so).
        ReadMetadata  (1,1) logical = true

        % The mabr.analysis.AbrFile record of each Files row, same order.
        Records struct = struct([])
    end

    properties (Access = private)
        % notes() sources found since the last scan, by session key: finding
        % the newest file holding a notebook can mean opening every file of a
        % folder that has none, and a browser asks again on every click.
        % Created on first use (a handle default would be shared by every
        % Catalog) and dropped by each scan.
        NotesMemo = []
    end

    properties (Constant)
        CacheVersion    = 1                    % bump when the cache's layout changes
        StoreFolder     = "MABR_Analysis"      % a results store's folder name
        ProjectFile     = "project.mat"        % what makes a folder a store
        UnknownSubject  = "(unknown subject)"
        UnknownStimulus = "(unknown)"
        NotesMargin     = minutes(5)           % a session's notes window, each side

        FileColumns = ["Path" "Folder" "FileName" "FileId" "Bytes" "Modified" "SessionKey" ...
            "Subject" "StartTime" "Stimulus" "ParamText" "NumSweeps" "SampleRate" "Layout" ...
            "AcqMode" "TestMode" "Units" "LevelUnit" "Duration" "Ok" "Error" "DuplicateOf"]
        SessionColumns = ["Key" "Path" "Name" "Subject" "SubjectRaw" "Day" "Start" "Stop" ...
            "NumFiles" "NumIncluded" "NumSweeps" "NumConditions" "Stimuli" "Summary" ...
            "AcqModes" "HasCompact" "ShortRuns" "TestMode" "Units" "LevelUnit" "NotesFile" ...
            "InferredLabel" "ResultsFile" "HasResults"]
        StoreColumns = ["Path" "Root" "NumResults"]
        NoteColumns  = ["Time" "Stamp" "Text" "Run" "Sweep" "Source" "Scope"]
    end

    methods
        % =================================================================
        %  Construction
        % =================================================================
        function obj = Catalog(root,opts)
            % Catalog(root,Name=Value) names a data folder; scan() reads it.
            %
            %   root                folder to catalog (must exist)
            %   opts.CacheFolder    where the scan cache goes (default
            %                       <LOCALAPPDATA or tempdir>/MABR/
            %                       AnalysisCache). One inside root or its
            %                       AnalysisRoot disables the cache: nothing
            %                       is ever written into the data
            %   opts.ResultsFolder  results store override ("" = the default
            %                       <AnalysisRoot>/MABR_Analysis)
            %   opts.ReadMetadata   open the files a scan finds (default true)
            %   obj  (returned) a Catalog with empty Files and Sessions; nothing
            %        is read until scan()
            arguments
                root (1,1) string
                opts.CacheFolder (1,1) string = mabr.analysis.Catalog.defaultCacheFolder()
                opts.ResultsFolder (1,1) string = ""
                opts.ReadMetadata (1,1) logical = true
            end
            if ismissing(root) || strtrim(root) == "" || ~isfolder(root)
                error('mabr:analysis:Catalog:noRoot','The data folder "%s" does not exist.',root);
            end
            obj.Root = absFolder(root);
            obj.AnalysisRoot = storeRoot(obj.Root);
            if obj.AnalysisRoot == "", obj.AnalysisRoot = obj.Root; end
            if ~ismissing(opts.ResultsFolder) && strtrim(opts.ResultsFolder) ~= ""
                obj.ResultsFolder = absPath(opts.ResultsFolder);
            else
                obj.ResultsFolder = string(fullfile(char(obj.AnalysisRoot), ...
                    char(mabr.analysis.Catalog.StoreFolder)));
            end

            % The cache is the one thing a scan writes, so it must never land
            % in the data: a CacheFolder inside the study -- Root, or the
            % AnalysisRoot above it, which is the same study opened lower
            % down; passed, or the default when either is as high as the
            % user's own profile -- turns caching off instead.
            cf = "";
            if ~ismissing(opts.CacheFolder) && strtrim(opts.CacheFolder) ~= ""
                cf = absPath(opts.CacheFolder);
            end
            if cf == ""
                obj.CacheState = "disabled (no cache folder)";
            elseif isUnder(cf,obj.Root) || isUnder(cf,obj.AnalysisRoot)
                obj.CacheState = "disabled (the cache folder is inside the data folder)";
            else
                obj.CacheFolder = cf;
                obj.CacheFile = string(fullfile(char(cf), ...
                    char("catalog_" + mabr.analysis.Stats.hex8(lower(obj.Root)) + ".mat")));
            end
            obj.ReadMetadata = opts.ReadMetadata;
            obj.Files        = emptyFiles();
            obj.Sessions     = emptySessions();
            obj.NestedStores = emptyStores();
        end

        % =================================================================
        %  Scanning
        % =================================================================
        function scan(obj,opts)
            % List every .abr under Root, read what changed, index sessions.
            %
            %   scan(ProgressFcn=fcn)
            %
            %   opts.ProgressFcn  [] or @(message,count,total), called with
            %                     count 0 once the files are listed, then at
            %                     most every 0.1 s while they are read, and with
            %                     count == total at the end. A sink that throws
            %                     (mabr:analysis:cancelled) stops the scan:
            %                     nothing on the object changes, but the records
            %                     read so far are cached for the next scan.
            %
            %   Fills Files, Sessions, Records, NestedStores, Warnings,
            %   ScannedAt, LastScanReads and CacheState, all at once at the
            %   end. Writes only CacheFile.
            arguments
                obj
                opts.ProgressFcn = []
            end
            sink = opts.ProgressFcn;
            if ~isempty(sink) && ~isa(sink,'function_handle')
                error('mabr:analysis:Catalog:badProgressFcn', ...
                    'ProgressFcn is [] or a function handle @(message,count,total).');
            end
            % A folder that has gone (a drive unplugged) is not an empty one:
            % listing nothing would read as "no sessions" to everything above.
            if ~isfolder(obj.Root)
                error('mabr:analysis:Catalog:noRoot','The data folder "%s" is no longer there.',obj.Root);
            end
            warns = strings(0,1);
            if startsWith(obj.CacheState,"disabled")
                warns(end+1,1) = "The scan cache is " + obj.CacheState + ...
                    "; every scan reads every file.";
            end

            % ---- What is there. Results stores and hidden folders are not
            % data, and a ResultsFolder override inside Root is a store too.
            d = listFiles(obj.Root,'*.abr',true);
            if ~isempty(d)
                inStore = isUnder(string({d.folder})',obj.ResultsFolder);
                d = d(~inStore);
            end
            n     = numel(d);
            paths = strings(n,1);
            if n > 0, paths = reshape(string(fullfile({d.folder},{d.name})),[],1); end
            bytes = reshape(double([d.bytes]),[],1);
            dnum  = reshape(double([d.datenum]),[],1);

            % ---- What is already known. The template is the record AbrFile
            % gives a file it cannot find: every field, at its blank value,
            % straight from the reader -- so a cache written by a reader
            % with other fields can be recognized and dropped.
            tmpl = mabr.analysis.AbrFile.read(string(tempname) + ".abr",ReadTrace=false);
            [C,state] = obj.loadCache(tmpl);

            % ---- Read what changed. A cached record of a file that could
            % not be LOADED is no hit: that failure may have been the moment
            % (a file locked, a permission since fixed, a synced file not yet
            % downloaded), none of which changes the file's size or time, so
            % a cached verdict would outlive its cause and no rescan could
            % clear it. Such files are tried again at every scan.
            recs  = repmat(tmpl,n,1);
            fresh = false(n,1);
            blank = false(n,1);
            [~,loc] = ismember(lower(paths),C.Lower);
            msg = sprintf('Reading %d .abr file(s) under %s',n,obj.Root);
            try
                if ~isempty(sink), sink(msg,0,n); end
                tLast = tic;
                for k = 1:n
                    j = loc(k);
                    readNow = false;
                    if j > 0 && C.Bytes(j) == bytes(k) && C.Modified(j) == dnum(k) && ~C.Retry(j)
                        r = C.Rec{j};
                        % The same file, perhaps spelled in another case.
                        r.Path = paths(k);
                        r.Folder = string(d(k).folder);
                        r.FileName = string(d(k).name);
                    elseif obj.ReadMetadata
                        r = mabr.analysis.AbrFile.read(paths(k),ReadTrace=false,ReadNotes=false);
                        readNow = true;
                    else
                        r = blankRecord(tmpl,d(k),paths(k));
                        blank(k) = true;
                    end
                    recs(k)  = r;
                    fresh(k) = readNow;
                    if ~isempty(sink) && (k == n || toc(tLast) >= 0.1)
                        sink(msg,k,n);
                        tLast = tic;
                    end
                end
            catch ME
                % Whatever was read is still worth keeping for the next
                % scan (fresh is set only once a record is in recs); the
                % object itself is left exactly as it was.
                keep = fresh & ~retryRead(recs);
                if any(keep) && obj.CacheFile ~= ""
                    P = mergeEntries(C,paths(keep),bytes(keep),dnum(keep),recs(keep));
                    obj.writeCache(P);
                end
                rethrow(ME);
            end

            % ---- Cache what was really read or found -- never a file listed
            % unread, nor one that could not be loaded -- and only when that
            % differs from what is on disk.
            keep = ~blank & ~retryRead(recs);
            if obj.CacheFile ~= ""
                changed = any(fresh & keep) || state ~= "loaded" || numel(C.Lower) ~= nnz(keep);
                if changed && (nnz(keep) > 0 || isfile(obj.CacheFile))
                    P = struct('Path',paths(keep),'Bytes',bytes(keep), ...
                        'Modified',dnum(keep),'Rec',{num2cell(recs(keep))});
                    w = obj.writeCache(P);
                    warns = [warns; w];
                end
            end

            % ---- Index, then commit everything at once.
            notesFiles = listFiles(obj.Root,'*.notes',true);
            [F,S,R,w] = obj.buildIndex(recs,blank,notesFiles);
            warns = [warns; w];
            stores = nestedStores(obj.Root,obj.AnalysisRoot,obj.ResultsFolder);

            obj.Files         = F;
            obj.Sessions      = S;
            obj.Records       = R;
            obj.NestedStores  = stores;
            obj.Warnings      = warns;
            obj.LastScanReads = nnz(fresh);
            obj.CacheState    = state;
            obj.ScannedAt     = datetime('now');
            obj.NotesMemo     = [];
        end

        % =================================================================
        %  Per session
        % =================================================================
        function T = notes(obj,key,opts)
            % The rig notes of one session.
            %
            %   T = notes(key,Scope="session")
            %
            %   key         a Sessions.Key
            %   opts.Scope  "session" (default): only notes written while this
            %               session was recorded, its first start less
            %               NotesMargin to its last stop plus NotesMargin;
            %               "all": the whole notebook
            %   T  (returned) table Time, Stamp, Text, Run, Sweep, Source, Scope
            %      in the notebook's order. Scope is "session", "earlier" or
            %      "later" against that window, or "unknown" for a note with
            %      no time (kept only by Scope "all"). UserData.From says
            %      where they came from ("file", "journal" or "none") and
            %      UserData.File which one.
            %
            %   A file's ABR_Data.Notes is the whole notebook as it stood when
            %   that file was written, so the newest file holding notes has
            %   them all; a folder whose files hold none falls back to its
            %   newest .notes journal, whose clock stamps are given a date from
            %   its "session started" header (rolling over midnight in commit
            %   order) and whose run and sweep are read back out of the stamp.
            %   A notebook repeats itself across files and journals, so
            %   repeats go: by (Time, Text) for a file's notes, by (Stamp,
            %   Text) for a journal's. If the session has no start or stop
            %   time, every timed note counts as "session".
            arguments
                obj
                key (1,1) string
                opts.Scope (1,1) string {mustBeMember(opts.Scope,["session","all"])} = "session"
            end
            r  = obj.sessionIndex(key);
            Sr = obj.Sessions(r,:);
            if isempty(obj.NotesMemo)
                obj.NotesMemo = containers.Map('KeyType','char','ValueType','any');
            end
            if isKey(obj.NotesMemo,char(key))
                M = obj.NotesMemo(char(key));
            else
                M = obj.notesSource(key,Sr.NotesFile);
                obj.NotesMemo(char(key)) = M;
            end
            raw  = M.Raw;
            from = M.From;
            src  = M.File;

            T = notesTable(raw);
            if height(T) > 0
                if from == "journal"
                    dk = T.Stamp + "|" + T.Text;
                else
                    tk = reshape(string(mabr.analysis.Stats.isoTime(T.Time)),[],1);
                    tk(isnat(T.Time)) = "stamp:" + T.Stamp(isnat(T.Time));
                    dk = tk + "|" + T.Text;
                end
                [~,first] = unique(dk,'stable');
                T = T(sort(first),:);
                lo = Sr.Start - mabr.analysis.Catalog.NotesMargin;
                hi = Sr.Stop + mabr.analysis.Catalog.NotesMargin;
                timed = ~isnat(T.Time);
                sc = repmat("unknown",height(T),1);
                sc(timed) = "session";
                if ~isnat(lo) && ~isnat(hi)
                    sc(timed & T.Time < lo) = "earlier";
                    sc(timed & T.Time > hi) = "later";
                end
                T.Scope = sc;
                if opts.Scope == "session"
                    T = T(T.Scope == "session",:);
                end
            end
            T.Properties.UserData = struct('From',from,'File',src);
        end

        function f = resultsFile(obj,keys)
            % Where the results of a session -- or of a pool of sessions -- go.
            %
            %   f = resultsFile(key)        one folder key, or "."
            %   f = resultsFile(keys)       several: a pool
            %
            %   keys  session keys (Sessions.Key or any key under AnalysisRoot;
            %         need not be in this catalog); repeats are ignored and the
            %         order does not matter
            %   f     (returned) string path, under ResultsFolder:
            %           one key  <ResultsFolder>/<key, / as filesep>.mat
            %           "."      <ResultsFolder>/<AnalysisRoot's name>.mat
            %           a pool   <ResultsFolder>/<subject>/pooled/
            %                    <first name>+<n-1>_<hex8(join(sort(keys),"|"))>.mat
            %
            %   A pool's file is named by the hash of its sorted member keys --
            %   the hash its mabr.analysis.Project pool key carries -- so the
            %   same sessions pooled again find the same file. Its subject and
            %   first name are those of the first key in sorted order.
            %   Nothing is created; the file need not exist.
            arguments
                obj
                keys string
            end
            keys = reshape(keys,[],1);
            keys(ismissing(keys)) = [];
            keys = strtrim(keys);
            keys(keys == "") = [];
            keys = unique(keys);                % sorted, as the hash wants
            if isempty(keys)
                error('mabr:analysis:Catalog:noKeys','resultsFile needs at least one session key.');
            end
            bad = ~cellfun(@isempty,regexp(cellstr(keys),'[<>:"|?*\\]|^/|/$|//|(^|/)\.\.?(/|$)','once')) ...
                & keys ~= ".";
            if any(bad)
                error('mabr:analysis:Catalog:badKey', ['"%s" is not a session key: a key is a ' ...
                    'folder path relative to the analysis root, "/" between folders (a pool ' ...
                    'is named by its member keys).'],keys(find(bad,1)));
            end
            rf = char(obj.ResultsFolder);
            if isscalar(keys)
                if keys == "."
                    f = string(fullfile(rf,[char(folderName(obj.AnalysisRoot)) '.mat']));
                else
                    f = string(fullfile(rf,[char(strrep(keys,"/",filesep)) '.mat']));
                end
                return
            end
            subj = obj.keySubject(keys(1));
            name = obj.keyName(keys(1));
            f = string(fullfile(rf,char(subj),'pooled', ...
                char(name + "+" + (numel(keys) - 1) + "_" + ...
                mabr.analysis.Stats.hex8(join(keys,"|")) + ".mat")));
        end

        function r = fileRows(obj,key)
            % The Files rows of one session, in their catalog order.
            %
            %   r = fileRows(key)
            %
            %   key  a Sessions.Key (an unknown one is an error:
            %        mabr:analysis:Catalog:unknownKey)
            %   r    (returned) table, Files' columns
            arguments
                obj
                key (1,1) string
            end
            obj.sessionIndex(key);
            r = obj.Files(obj.Files.SessionKey == key,:);
        end
    end

    methods (Static)
        function p = suggestStudyRoot(folder)
            % The study folder to open instead of one animal's, or "".
            %
            %   p = suggestStudyRoot(folder)
            %
            %   folder  the folder a user is about to open
            %   p       (returned) its parent, when the folder's own name names
            %           a subject, it holds no .abr file itself but folders below
            %           it do, and no MABR_Analysis/project.mat exists at or
            %           above it; "" otherwise (including a folder that does not
            %           exist)
            %
            %   Opening one animal's folder as the root would put that
            %   animal's results in a store of its own and leave every other
            %   animal of the study outside it -- the mistake this exists to
            %   catch. Once a study has a store, opening anything inside it
            %   files into that store anyway (AnalysisRoot), so there is
            %   nothing to suggest.
            arguments
                folder (1,1) string
            end
            p = "";
            if ismissing(folder) || strtrim(folder) == "" || ~isfolder(folder), return; end
            f = absFolder(folder);
            if mabr.analysis.AbrFile.subjectOf(folderName(f)) == "", return; end
            here = dir(fullfile(char(f),'*.abr'));
            here = here(~[here.isdir]);
            if ~isempty(here) && any(matchesPattern({here.name},'*.abr')), return; end
            if isempty(listFiles(f,'*.abr',true)), return; end
            if storeRoot(f) ~= "", return; end
            parent = string(fileparts(char(f)));
            if parent == "" || strcmpi(parent,f), return; end
            p = parent;
        end

        function L = inferLabel(name,subject)
            % A visit label guessed from a session folder's name.
            %
            %   L = inferLabel(name,subject)
            %
            %   name     the session folder's name (not a path)
            %   subject  its canonical subject ("SUBJ-ID-959"); "" or any other
            %            text removes whichever subject the name has
            %   L        (returned) the name without its subject token and the
            %            separators around it; a remainder that is a
            %            yyMMdd'T'HHmmss or yyMMdd stamp becomes "yyyy-MM-dd";
            %            "" when nothing is left
            %
            %       inferLabel("SUBJ-ID-959_Baseline","SUBJ-ID-959")        "Baseline"
            %       inferLabel("SUBJ-ID-1254_261001T140000","SUBJ-ID-1254") "2026-10-01"
            %
            %   The default folder scheme names a folder <subject>_<stamp>,
            %   and a timepoint is a day, not a second: two sessions of one
            %   animal on one day are one visit.
            arguments
                name (1,1) string
                subject (1,1) string = ""
            end
            L = "";
            if ismissing(name), return; end
            s  = char(strtrim(name));
            id = "";
            if ~ismissing(subject)
                tok = regexp(char(subject),'^SUBJ-ID-(\S+)$','tokens','once','ignorecase');
                if ~isempty(tok), id = string(tok{1}); end
            end
            if id ~= ""
                pat = ['SUBJ[-_ ]?ID[-_ ]?' regexptranslate('escape',char(id)) '(?![A-Za-z0-9])'];
            else
                pat = 'SUBJ[-_ ]?ID[-_ ]?[A-Za-z0-9]+';
            end
            s = regexprep(s,['[\s_\-.]*' pat '[\s_\-.]*'],'_','once','ignorecase');
            s = regexprep(s,'^[\s_\-.]+|[\s_\-.]+$','');
            if isempty(s), return; end
            L = string(s);
            d = stampDate(s);
            if ~isnat(d), L = string(d,'yyyy-MM-dd'); end
        end

        function f = defaultCacheFolder()
            % <LOCALAPPDATA or tempdir>/MABR/AnalysisCache -- local to this
            % machine and this user, and outside any data folder.
            base = getenv('LOCALAPPDATA');
            if isempty(base) || ~isfolder(base), base = tempdir; end
            f = string(fullfile(base,'MABR','AnalysisCache'));
        end
    end

    methods (Access = private)
        function [C,state] = loadCache(obj,tmpl)
            % The cache's entries ready for lookup, and what was made of it.
            % Any problem means an empty cache and a reason, never an error
            % and never a printed warning: a lost cache costs only time.
            C = struct('Path',strings(0,1),'Lower',strings(0,1),'Bytes',zeros(0,1), ...
                'Modified',zeros(0,1),'Rec',{cell(0,1)},'Retry',false(0,1));
            if obj.CacheFile == ""
                state = obj.CacheState;
                return
            end
            file = char(obj.CacheFile);
            if ~isfile(file)
                state = "new";
                return
            end
            w0 = warning;
            [lm,li] = lastwarn;
            restore = onCleanup(@() restoreWarnings(w0,lm,li));
            warning('off','all');
            state = "rebuilt (cache unreadable)";
            try
                S = load(file,'MABRCatalogCache');
                M = S.MABRCatalogCache;
                if ~(isstruct(M) && isscalar(M) && ...
                        all(isfield(M,{'CacheVersion','ReaderVersion','Root','Entries'})))
                    return
                end
                if ~isequal(M.CacheVersion,mabr.analysis.Catalog.CacheVersion)
                    state = "rebuilt (cache version changed)";
                    return
                end
                if ~isequal(M.ReaderVersion,mabr.analysis.AbrFile.ReaderVersion)
                    state = "rebuilt (reader version changed)";
                    return
                end
                if ~strcmpi(string(M.Root),obj.Root)
                    state = "rebuilt (cache of another folder)";
                    return
                end
                E = M.Entries;
                if ~(istable(E) && all(ismember({'Path','Bytes','Modified','Rec'}, ...
                        E.Properties.VariableNames)) && iscell(E.Rec))
                    return
                end
                f0 = fieldnames(tmpl);
                same = cellfun(@(r) isstruct(r) && isscalar(r) && isequal(fieldnames(r),f0),E.Rec);
                if ~all(same)
                    state = "rebuilt (record fields changed)";
                    return
                end
                C.Path     = reshape(string(E.Path),[],1);
                C.Lower    = lower(C.Path);
                C.Bytes    = reshape(double(E.Bytes),[],1);
                C.Modified = reshape(double(E.Modified),[],1);
                C.Rec      = reshape(E.Rec,[],1);
                C.Retry    = retryRead(vertcat(C.Rec{:}));
                state = "loaded";
            catch
                % unreadable: rebuilt
            end
            clear restore
        end

        function w = writeCache(obj,P)
            % Write the cache atomically (a temporary file, then a move), so
            % a scan cut off mid-write leaves the previous cache whole. A
            % failure is a warning: the next scan just reads more.
            w = strings(0,1);
            if obj.CacheFile == "", return; end
            folder = char(obj.CacheFolder);
            tmp = '';
            try
                if ~isfolder(folder), mkdir(folder); end
                n = numel(P.Path);
                Entries = table(reshape(P.Path,n,1),reshape(P.Bytes,n,1), ...
                    reshape(P.Modified,n,1),reshape(P.Rec,n,1), ...
                    'VariableNames',{'Path','Bytes','Modified','Rec'});
                MABRCatalogCache = struct('CacheVersion',mabr.analysis.Catalog.CacheVersion, ...
                    'ReaderVersion',mabr.analysis.AbrFile.ReaderVersion,'Root',obj.Root, ...
                    'Saved',string(mabr.analysis.Stats.isoTime(datetime('now'))), ...
                    'Entries',Entries);
                [~,stem] = fileparts(char(obj.CacheFile));
                [~,u] = fileparts(tempname);
                tmp = fullfile(folder,[stem '_' u '.tmp.mat']);
                save(tmp,'MABRCatalogCache');
                [ok,msg] = movefile(tmp,char(obj.CacheFile),'f');
                if ~ok, error('mabr:analysis:Catalog:cacheMove','%s',msg); end
            catch ME
                if ~isempty(tmp) && isfile(tmp)
                    try
                        delete(tmp);
                    catch
                        % a stray temporary file in the cache folder is harmless
                    end
                end
                w = "The scan cache " + obj.CacheFile + " could not be written (" + ...
                    string(ME.message) + "); the next scan reads every file again.";
            end
        end

        function [F,S,R,warns] = buildIndex(obj,R,blank,notesFiles)
            % Files, Sessions and the matching records, from one record per
            % file, plus whatever is worth a warning.
            warns = strings(0,1);
            n = numel(R);
            if n == 0
                F = emptyFiles();  S = emptySessions();  R = R(:);
                return
            end
            R = R(:);
            folders = reshape([R.Folder],[],1);
            [~,~,g] = unique(lower(folders),'stable');
            nS = max(g);

            nf  = numel(notesFiles);
            nfF = strings(nf,1);  nfP = strings(nf,1);  nfD = zeros(nf,1);
            if nf > 0
                nfF = lower(reshape(string({notesFiles.folder}),[],1));
                nfP = reshape(string(fullfile({notesFiles.folder},{notesFiles.name})),[],1);
                nfD = reshape([notesFiles.datenum],[],1);
            end

            arName = folderName(obj.AnalysisRoot);
            info  = cell(nS,1);
            for s = 1:nS
                idx  = find(g == s);
                path = folders(idx(1));
                rel  = relPath(obj.AnalysisRoot,path);
                key  = rel;
                if key == "", key = "."; end
                % The newest journal in the folder, by its modified time.
                nfile = "";
                m = find(nfF == lower(path));
                if ~isempty(m)
                    [~,j] = max(nfD(m));
                    nfile = nfP(m(j));
                end
                I = sessionInfo(R(idx),key,path,arName,nfile);
                I.Index = idx(I.Order);
                info{s} = I;
            end
            I = vertcat(info{:});

            % ---- Session order: subjects naturally, unknown last; days; starts.
            subj = reshape([I.Subject],[],1);
            us   = unique(subj);
            uRank = naturalRank(us);
            uRank(us == mabr.analysis.Catalog.UnknownSubject) = numel(us) + 1;
            [~,si] = ismember(subj,us);
            dayN  = timeNum(vertcat(I.Day));     dayN(isnan(dayN)) = Inf;
            start = timeNum(vertcat(I.Start));   start(isnan(start)) = Inf;
            keys  = reshape([I.Key],[],1);
            [~,o] = sortrows([uRank(si) dayN start naturalRank(keys)]);
            I = I(o);
            nS = numel(I);

            % ---- Sessions.
            Key = reshape([I.Key],[],1);
            ResultsFile = strings(nS,1);
            HasResults  = false(nS,1);
            for s = 1:nS
                ResultsFile(s) = obj.resultsFile(Key(s));
                HasResults(s)  = isfile(ResultsFile(s));
            end
            col = @(f) reshape([I.(f)],[],1);
            S = table(Key,col('Path'),col('Name'),col('Subject'),col('SubjectRaw'), ...
                vertcat(I.Day),vertcat(I.Start),vertcat(I.Stop),col('NumFiles'), ...
                col('NumIncluded'),col('NumSweeps'),col('NumConditions'),col('Stimuli'), ...
                col('Summary'),col('AcqModes'),col('HasCompact'),col('ShortRuns'), ...
                col('TestMode'),col('Units'),col('LevelUnit'),col('NotesFile'), ...
                col('InferredLabel'),ResultsFile,HasResults, ...
                'VariableNames',cellstr(mabr.analysis.Catalog.SessionColumns));
            S.Day.Format   = 'yyyy-MM-dd';
            S.Start.Format = 'yyyy-MM-dd HH:mm:ss';
            S.Stop.Format  = 'yyyy-MM-dd HH:mm:ss';

            % ---- Files, in session order.
            order = vertcat(I.Index);
            R     = R(order);
            blank = blank(order);
            nIn   = arrayfun(@(x) numel(x.Index),I);
            % (reshape: repelem of a single session's scalar is a row)
            SessionKey = reshape(repelem(Key,nIn),[],1);
            fsubj      = reshape(repelem(reshape([I.Subject],[],1),nIn),[],1);
            own        = reshape([R.Subject],[],1);
            fsubj(own ~= "") = own(own ~= "");
            % FileId is mabr.analysis.Session's: "<folder name>/<file name>",
            % the same on every machine (two folders of one name in two
            % subjects share it; the catalog's own references use the path
            % relative to AnalysisRoot instead).
            FileId = regexprep(reshape([R.Folder],[],1),'^.*[\\/]','') + "/" + ...
                reshape([R.FileName],[],1);
            relF   = SessionKey + "/" + reshape([R.FileName],[],1);
            atRoot = SessionKey == ".";
            if any(atRoot), relF(atRoot) = reshape([R(atRoot).FileName],[],1); end

            % A file copied into a second session folder is the same
            % recording twice (same name, sweeps, samples and start); a
            % pool of the two must count it once. The first in catalog
            % order is the original.
            ok = reshape([R.Ok],[],1);
            DuplicateOf = strings(numel(R),1);
            t  = reshape([R.StartTime],[],1);
            ns = round(reshape([R.Duration],[],1).*reshape([R.SampleRate],[],1));
            cand = find(ok & ~isnat(t));
            if ~isempty(cand)
                dk = lower(reshape([R(cand).FileName],[],1)) + "|" + ...
                    string(reshape([R(cand).NumSweeps],[],1)) + "|" + string(ns(cand)) + "|" + ...
                    reshape(string(mabr.analysis.Stats.isoTime(t(cand))),[],1);
                [~,firstOf,gg] = unique(dk,'stable');
                isDup = (1:numel(cand))' ~= firstOf(gg);
                DuplicateOf(cand(isDup)) = relF(cand(firstOf(gg(isDup))));
            end

            c = @(f) reshape([R.(f)],[],1);
            F = table(c('Path'),c('Folder'),c('FileName'),FileId,c('Bytes'),c('Modified'), ...
                SessionKey,fsubj,c('StartTime'),c('Stimulus'),c('ParamText'),c('NumSweeps'), ...
                c('SampleRate'),c('Layout'),c('AcqMode'),c('TestMode'),c('Units'), ...
                c('LevelUnit'),c('Duration'),c('Ok'),c('Error'),DuplicateOf, ...
                'VariableNames',cellstr(mabr.analysis.Catalog.FileColumns));
            F.Modified.Format  = 'yyyy-MM-dd HH:mm:ss';
            F.StartTime.Format = 'yyyy-MM-dd HH:mm:ss';

            % ---- Warnings: files that are there but cannot be used.
            skp = reshape([R.Skipped],[],1);
            bad = find(~ok & ~skp & ~blank);
            for k = reshape(bad(1:min(end,20)),1,[])
                warns(end+1,1) = relF(k) + ": " + R(k).Error; %#ok<AGROW>
            end
            if numel(bad) > 20
                warns(end+1,1) = sprintf('... and %d more unreadable file(s).',numel(bad) - 20);
            end
            if any(skp)
                warns(end+1,1) = sprintf(['%d .abr file(s) are not recordings and are left out ' ...
                    '(first: %s).'],nnz(skp),relF(find(skp,1)));
            end
            if any(DuplicateOf ~= "")
                warns(end+1,1) = sprintf(['%d file(s) are copies of a recording in another ' ...
                    'session folder (Files.DuplicateOf).'],nnz(DuplicateOf ~= ""));
            end
            if any(blank)
                warns(end+1,1) = sprintf(['%d file(s) not in the cache were listed without ' ...
                    'being read (ReadMetadata is false).'],nnz(blank));
            end
        end

        function M = notesSource(obj,key,journal)
            % Where a session's notebook is: the newest readable file whose
            % ABR_Data.Notes holds anything (newest by start, then modified
            % time), else the newest journal in its folder, else nowhere.
            % Never throws -- an unreadable journal is no notes.
            M = struct('Raw',noteStruct(0),'From',"none",'File',"");
            % A legacy (E0) file predates the notebook, so it is never opened
            % for one: a folder of them would otherwise be read whole for
            % nothing on the first click.
            rows = obj.Files.SessionKey == key & obj.Files.Ok;
            if ~isempty(obj.Records) && numel(obj.Records) == numel(rows)
                rows = rows & reshape([obj.Records.Era],[],1) ~= "E0";
            end
            F = obj.Files(rows,:);
            if height(F) > 0
                t = timeNum(F.StartTime);  t(isnan(t)) = -Inf;
                m = timeNum(F.Modified);   m(isnan(m)) = -Inf;
                [~,o] = sortrows([t m],[-1 -2]);
                for i = reshape(o,1,[])
                    [~,~,~,nt] = mabr.analysis.AbrFile.read(F.Path(i),ReadTrace=false,ReadNotes=true);
                    if ~isempty(nt)
                        M = struct('Raw',nt,'From',"file",'File',F.Path(i));
                        return
                    end
                end
            end
            if journal ~= "" && isfile(journal)
                try
                    M = struct('Raw',journalNotes(journal),'From',"journal",'File',journal);
                catch
                    % an unreadable journal leaves the notes empty
                end
            end
        end

        function i = sessionIndex(obj,key)
            % The Sessions row of a key; an unknown key is an error.
            i = find(obj.Sessions.Key == key,1);
            if isempty(i)
                error('mabr:analysis:Catalog:unknownKey', ...
                    'No session "%s" in the catalog of %s.',key,obj.Root);
            end
        end

        function s = keySubject(obj,key)
            % A key's subject: the catalog's, else the one its path names.
            s = "";
            i = find(obj.Sessions.Key == key,1);
            if ~isempty(i), s = obj.Sessions.Subject(i); end
            if s == ""
                s = pathSubject(keyPathText(folderName(obj.AnalysisRoot),key));
            end
            if s == "", s = mabr.analysis.Catalog.UnknownSubject; end
        end

        function s = keyName(obj,key)
            % A key's session folder name.
            if key == "."
                s = folderName(obj.AnalysisRoot);
            else
                parts = split(key,"/");
                s = parts(end);
            end
        end
    end
end

% =========================================================================
%  One session
% =========================================================================
function I = sessionInfo(R,key,path,arName,notesFile)
% Everything the Sessions table says about one folder, from its records,
% plus Order: the records in the order the folder's files are listed (by
% start time, then by name).
t = timeNum(reshape([R.StartTime],[],1));
t(isnan(t)) = Inf;
[~,order] = sortrows([t naturalRank(reshape([R.FileName],[],1))]);
R  = R(order);
ok = reshape([R.Ok],[],1);
inc = includedFiles(R);
Rk = R(ok);
Ri = R(inc);

I = struct();
I.Order = order;
I.Key   = key;
I.Path  = path;
I.Name  = folderName(path);

% The subject: the first one the folder path names (from the analysis
% root down, so nothing above the study counts), else the first a file
% name gives.
[subj,raw] = pathSubject(keyPathText(arName,key));
if subj == ""
    own = reshape([R.Subject],[],1);
    j = find(own ~= "",1);
    if ~isempty(j), subj = R(j).Subject;  raw = R(j).SubjectRaw; end
end
if subj == "", subj = mabr.analysis.Catalog.UnknownSubject;  raw = ""; end
I.Subject    = subj;
I.SubjectRaw = raw;

% When: the earliest start to the latest end of anything readable.
I.Start = NaT;
I.Stop  = NaT;
if ~isempty(Rk)
    st = reshape([Rk.StartTime],[],1);
    st = st(~isnat(st));
    if ~isempty(st), I.Start = min(st); end
    I.Stop = stopOf(Rk);
end
I.Day = NaT;
if ~isnat(I.Start), I.Day = dateshift(I.Start,'start','day'); end

% What the included files hold. A folder may include none (every file
% unreadable, or listed unread), so every column comes through textCol,
% which knows an empty record array still means "no text".
I.NumFiles      = numel(R);
I.NumIncluded   = numel(Ri);
I.NumSweeps     = sum([Ri.NumSweeps]);
I.NumConditions = numel(unique(conditionKeys(Ri,true)));
stim = unique(textCol(Ri,'Stimulus'));
stim(stim == "") = [];
I.Stimuli = "";
if ~isempty(stim)
    [~,so] = sort(lower(stim));
    I.Stimuli = join(reshape(stim(so),1,[]),", ");
end
I.Summary    = summaryText(Ri);
I.AcqModes   = acqModesText(Ri);
I.HasCompact = any(textCol(Ri,'Layout') == "compact");
I.ShortRuns  = shortRuns(Ri);

tm = reshape(logical([Rk.TestMode]),[],1);
if isempty(tm) || ~any(tm)
    I.TestMode = "none";
elseif all(tm)
    I.TestMode = "all";
else
    I.TestMode = "some";
end
I.Units     = oneOf(textCol(Ri,'Units'));
I.LevelUnit = oneOf(textCol(Ri,'LevelUnit'));
I.NotesFile = notesFile;

% A folder named for its subject alone says nothing about the visit; its
% day is the next best label (the same-day rule groups by day anyway).
lbl = mabr.analysis.Catalog.inferLabel(I.Name,subj);
if lbl == "" && ~isnat(I.Day), lbl = string(I.Day,'yyyy-MM-dd'); end
I.InferredLabel = lbl;
end

function v = textCol(R,f)
% A text field of every record as a string column -- strings(0,1), not the
% double [] that [R.(f)] makes of an empty record array.
if isempty(R)
    v = strings(0,1);
else
    v = reshape([R.(f)],[],1);
end
end

function inc = includedFiles(R)
% The files a Session over this folder alone would include by default:
% readable recordings, no Test Mode file beside real data, and then only
% those at the majority sample rate of what is left -- mabr.analysis.
% Session's Include rules in Session's order (less the cross-folder
% duplicate rule, which one folder cannot meet). The order matters: rate
% first, a folder of one real file and two Test Mode files at another rate
% would take the Test Mode rate as its own and then include nothing.
inc = reshape([R.Ok],[],1);
if ~any(inc), return; end
tm = reshape([R.TestMode],[],1);
if any(inc & ~tm), inc = inc & ~tm; end
fs   = reshape([R.SampleRate],[],1);
rate = mode(fs(inc));                   % ties go to the lower rate, as Session's
inc  = inc & fs == rate;
end

function stop = stopOf(R)
% The end of the last thing recorded. A continuous file ends at its start
% plus its duration. A compact file holds only its own windows, so an
% intermixed run -- all its files share one start -- is taken to last its
% presentations times the folder's onset interval (the median of its
% continuous files' MinISI; else one window each, a lower bound).
stop = NaT;
t    = reshape([R.StartTime],[],1);
dur  = reshape([R.Duration],[],1);
lay  = reshape([R.Layout],[],1);
cont = lay ~= "compact" & ~isnat(t) & isfinite(dur);
ends = t(cont) + seconds(dur(cont));
comp = lay == "compact" & ~isnat(t);
if any(comp)
    isi = reshape([R.MinISI],[],1);
    isi = isi(lay ~= "compact" & isfinite(isi));
    Rc  = R(comp);
    tc  = t(comp);
    [u,~,g] = unique(timeNum(tc));
    for k = 1:numel(u)
        m  = find(g == k);
        nP = sum([Rc(m).NumSweeps]);
        if isempty(isi)
            w = Rc(m(1)).SweepLength/Rc(m(1)).SampleRate*1000;
        else
            w = median(isi);
        end
        ends(end+1,1) = tc(m(1)) + seconds(nP*w/1000); %#ok<AGROW>
    end
end
ends = ends(~isnat(ends));
if ~isempty(ends), stop = max(ends); end
end

function keys = conditionKeys(R,withAcq)
% One condition key per record, spelled as mabr.analysis.Session keys its
% conditions (Stats.keyValue values): Stimulus when any record names one,
% AcqMode (withAcq), then the union of the records' parameters ordered
% ignoring case, a parameter a record lacks as NaN. Built a column at a
% time: keyValue is vectorized, and a rescan of a large tree is mostly this.
n = numel(R);
keys = strings(n,1);
if n == 0, return; end
names = paramNames(R);
cols  = strings(n,0);
stim  = textCol(R,'Stimulus');
if any(stim ~= "")
    cols(:,end+1) = "Stimulus=" + mabr.analysis.Stats.keyValue(stim);
end
if withAcq
    cols(:,end+1) = "AcqMode=" + mabr.analysis.Stats.keyValue(textCol(R,'AcqMode'));
end
for j = 1:numel(names)
    cols(:,end+1) = names(j) + "=" + mabr.analysis.Stats.keyValue(paramColumn(R,names(j))); %#ok<AGROW>
end
if isempty(cols), return; end
keys = join(cols,"|",2);
end

function names = paramNames(R)
% The union of the records' parameter names, ordered ignoring case.
names = strings(1,0);
for k = 1:numel(R)
    names = [names reshape(R(k).ParamNames,1,[])]; %#ok<AGROW>
end
names = unique(names);
[~,o] = sort(lower(names));
names = reshape(names(o),1,[]);
end

function v = paramColumn(R,name)
% One parameter of every record as a column, NaN where a record has none.
v = nan(numel(R),1);
for k = 1:numel(R)
    P = R(k).Params;
    if isstruct(P) && isfield(P,name), v(k) = double(P.(name)); end
end
end

function s = summaryText(R)
% "Tone 6×9 ×2 · ClickTrain ×9 ×2": per stimulus (in the order each was
% first presented), how many values each of its parameters takes -- ×n for
% a single parameter -- and how many files hold each condition when that is
% more than one: two runs of one grid, or a conventional and an intermixed
% run of it.
s = "";
if isempty(R), return; end
% Strings, not chars: char(215) + 9 is the number 224.
X = string(char(215));  mid = string(char(183));  dash = string(char(8211));
stim = reshape([R.Stimulus],[],1);
t = timeNum(reshape([R.StartTime],[],1));
t(isnan(t)) = Inf;
u = unique(stim);
first = zeros(numel(u),1);
for k = 1:numel(u), first(k) = min(t(stim == u(k))); end
[~,~,nameRank] = unique(lower(u));
[~,o] = sortrows([first nameRank]);
u = u(o);
parts = strings(1,numel(u));
for k = 1:numel(u)
    Rs = R(stim == u(k));
    names = paramNames(Rs);
    counts = zeros(1,0);
    for j = 1:numel(names)
        v = paramColumn(Rs,names(j));
        v = v(isfinite(v));
        if isempty(v), continue; end
        counts(end+1) = numel(unique(mabr.analysis.Stats.keyValue(v))); %#ok<AGROW>
    end
    if isempty(counts)
        dims = "";
    elseif isscalar(counts)
        dims = X + counts;
    else
        dims = join(string(counts),X);
    end
    [~,~,gc] = unique(conditionKeys(Rs,false));
    per = accumarray(gc,1);
    if max(per) <= 1
        rep = "";
    elseif min(per) == max(per)
        rep = " " + X + max(per);
    else
        rep = " " + X + min(per) + dash + max(per);
    end
    label = u(k);
    if label == "", label = mabr.analysis.Catalog.UnknownStimulus; end
    parts(k) = strtrim(label + " " + dims) + rep;
end
s = join(parts," " + mid + " ");
end

function s = acqModesText(R)
% "conventional, interleaved": the acquisition modes present, in that order.
s = "";
if isempty(R), return; end
m = unique(reshape([R.AcqMode],[],1));
m(m == "") = [];
known = ["conventional" "interleaved" "pooled"];
m = [known(ismember(known,m)) reshape(sort(setdiff(m,known)),1,[])];
if isempty(m), return; end
s = join(m,", ");
end

function n = shortRuns(R)
% Runs stopped early: files with fewer than half the median sweeps of their
% stimulus and acquisition mode (mabr.analysis.Session's Short rule),
% counted as runs -- each continuous file is one, and the compact files of
% one intermixed run (one start time) are one between them.
n = 0;
if isempty(R), return; end
grp  = reshape([R.Stimulus],[],1) + "|" + reshape([R.AcqMode],[],1);
nsw  = reshape([R.NumSweeps],[],1);
short = false(numel(R),1);
[~,~,g] = unique(grp);
for k = 1:max(g)
    m = g == k;
    short(m) = nsw(m) < 0.5*median(nsw(m));
end
if ~any(short), return; end
Rs  = R(short);
lay = reshape([Rs.Layout],[],1);
id  = reshape([Rs.Path],[],1);
cmp = lay == "compact";
id(cmp) = "compact|" + reshape([Rs(cmp).Stimulus],[],1) + "|" + ...
    mabr.analysis.Stats.isoTime(reshape([Rs(cmp).StartTime],[],1));
n = numel(unique(id));
end

function u = oneOf(v)
% The one value v holds, "" for none, "mixed" for several.
v = unique(v(v ~= ""));
if isempty(v)
    u = "";
elseif isscalar(v)
    u = v;
else
    u = "mixed";
end
end

% =========================================================================
%  Notes
% =========================================================================
function N = noteStruct(n)
% n blank note records, the fields AbrFile.read's notes carry.
N = repmat(struct('Stamp',"",'Text',"",'Time',NaT,'Run',NaN,'Sweep',NaN,'Source',""),n,1);
end

function T = notesTable(N)
% A note struct array as the notes() table (Scope filled in by the caller).
n = numel(N);
if n == 0
    T = table(NaT(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),strings(0,1), ...
        strings(0,1),'VariableNames',cellstr(mabr.analysis.Catalog.NoteColumns));
    T.Time.Format = 'yyyy-MM-dd HH:mm:ss';
    return
end
N = N(:);
Time = NaT(n,1);
for k = 1:n
    if isdatetime(N(k).Time) && ~isempty(N(k).Time), Time(k) = N(k).Time(1); end
end
Time.Format = 'yyyy-MM-dd HH:mm:ss';
Stamp  = reshape(string({N.Stamp}),[],1);
Text   = reshape(string({N.Text}),[],1);
Run    = reshape(double([N.Run]),[],1);
Sweep  = reshape(double([N.Sweep]),[],1);
Source = reshape(string({N.Source}),[],1);
Scope  = strings(n,1);
T = table(Time,Stamp,Text,Run,Sweep,Source,Scope);
end

function N = journalNotes(file)
% A .notes journal as note records, with what its text still says: the
% stamp and text (mabr.data.SessionNotes.fromFile), the run and sweep read
% back out of an "R02 S0128 09:17:05" stamp, and a time -- a clock stamp
% dated from the journal's "session started" header (else the stamp in its
% file name) and moved past midnight when it falls more than half an hour
% before the note committed ahead of it, an elapsed "+hh:mm:ss" stamp added
% to that start.
store = mabr.data.SessionNotes.fromFile(char(file));
recs  = store.Notes;
N = noteStruct(numel(recs));
t0 = NaT;
try
    txt = fileread(char(file));
    tok = regexp(txt,'session started\s+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})','tokens','once');
    if ~isempty(tok), t0 = datetime(tok{1},'InputFormat','yyyy-MM-dd''T''HH:mm:ss'); end
catch
end
if isnat(t0)
    [~,nm] = fileparts(char(file));
    tok = regexp(nm,'(\d{6}T\d{6})','tokens');
    if ~isempty(tok)
        try
            t0 = datetime(tok{end}{1},'InputFormat','yyMMdd''T''HHmmss');
        catch
        end
    end
end
prev = t0;
for k = 1:numel(recs)
    stamp = string(recs(k).Stamp);
    N(k).Stamp = stamp;
    N(k).Text  = string(recs(k).Text);
    tk = regexp(char(stamp),'(?<![A-Za-z0-9])R(\d+)(?![A-Za-z0-9])','tokens','once');
    if ~isempty(tk), N(k).Run = str2double(tk{1}); end
    tk = regexp(char(stamp),'(?<![A-Za-z0-9])S(\d+)(?![A-Za-z0-9])','tokens','once');
    if ~isempty(tk), N(k).Sweep = str2double(tk{1}); end
    if isnat(t0), continue; end
    t = NaT;
    e = regexp(char(stamp),'^\+(\d+):(\d{2}):(\d{2})$','tokens','once');
    c = regexp(char(stamp),'(?<![\d:+])(\d{1,2}):(\d{2}):(\d{2})\s*$','tokens','once');
    if ~isempty(e)
        t = t0 + duration(str2double(e{1}),str2double(e{2}),str2double(e{3}));
    elseif ~isempty(c)
        t = dateshift(prev,'start','day') + ...
            duration(str2double(c{1}),str2double(c{2}),str2double(c{3}));
        for guard = 1:3
            if t >= prev - minutes(30), break; end
            t = t + days(1);
        end
    end
    if ~isnat(t)
        N(k).Time = t;
        prev = t;
    end
end
end

% =========================================================================
%  Results stores
% =========================================================================
function T = nestedStores(root,analysisRoot,resultsFolder)
% Every MABR_Analysis/project.mat below root that is not the store this
% catalog files into: a store a project can import.
T = emptyStores();
d = listFiles(root,char(mabr.analysis.Catalog.ProjectFile),false);
if isempty(d), return; end
own = string(fullfile(char(analysisRoot),char(mabr.analysis.Catalog.StoreFolder)));
P = strings(0,1);  Rt = strings(0,1);  N = zeros(0,1);
for k = 1:numel(d)
    folder = string(d(k).folder);
    rel = relPath(root,folder);
    if rel == "", continue; end
    parts = split(rel,"/");
    if ~strcmpi(parts(end),mabr.analysis.Catalog.StoreFolder), continue; end
    if any(strcmpi(parts(1:end-1),mabr.analysis.Catalog.StoreFolder)), continue; end
    if strcmpi(folder,own) || strcmpi(folder,resultsFolder), continue; end
    P(end+1,1)  = folder; %#ok<AGROW>
    Rt(end+1,1) = string(fileparts(char(folder))); %#ok<AGROW>
    N(end+1,1)  = countResults(folder); %#ok<AGROW>
end
if isempty(P), return; end
T = table(P,Rt,N,'VariableNames',cellstr(mabr.analysis.Catalog.StoreColumns));
end

function n = countResults(store)
% The results files in a store: every .mat but its project.mat, temporary
% files, and what lives in .history, logs, figures, exports and scripts.
n = 0;
d = dir(fullfile(char(store),'**','*.mat'));
d = d(~[d.isdir]);
for k = 1:numel(d)
    rel = relPath(store,d(k).folder);
    if rel == "" && strcmpi(d(k).name,mabr.analysis.Catalog.ProjectFile), continue; end
    if contains(lower(string(d(k).name)),".tmp"), continue; end
    if rel ~= ""
        parts = lower(split(rel,"/"));
        if any(startsWith(parts,".")) || any(ismember(parts,["logs" "figures" "exports" "scripts"]))
            continue
        end
    end
    n = n + 1;
end
end

function r = storeRoot(p)
% The nearest folder at or above p holding MABR_Analysis/project.mat, "" if
% none.
r = "";
p = char(p);
for guard = 1:256
    if isfile(fullfile(p,char(mabr.analysis.Catalog.StoreFolder), ...
            char(mabr.analysis.Catalog.ProjectFile)))
        r = string(p);
        return
    end
    q = fileparts(p);
    if isempty(q) || strcmp(q,p), return; end
    p = q;
end
end

% =========================================================================
%  Files and folders
% =========================================================================
function d = listFiles(base,pattern,skipStores)
% Every file matching pattern anywhere under base, sorted by path, outside
% hidden (".") folders -- and outside results stores when skipStores.
d = dir(fullfile(char(base),'**',pattern));
d = d(~[d.isdir]);
d = d(:);
if isempty(d), return; end
d = d(matchesPattern({d.name},pattern));
if isempty(d), return; end
[uf,~,g] = unique({d.folder});
keepF = cellfun(@(f) ~isSkipped(relPath(base,f),skipStores),uf);
d = d(keepF(g));
if isempty(d), return; end
[~,o] = sort(lower(string(fullfile({d.folder},{d.name}))));
d = d(o);
d = d(:);
end

function tf = matchesPattern(names,pattern)
% Whether each name really matches pattern ('*.ext' or an exact name). A
% guard rather than a fix: Windows' own wildcard matching also tries 8.3
% short names, so to the shell '*.abr' finds "run.abr_old" (RUN~1.ABR), a
% backup that is not a recording. MATLAB's dir does not do that today; this
% keeps a listing correct whatever dir does.
names = reshape(string(names),[],1);
pattern = string(pattern);
if startsWith(pattern,"*.")
    tf = endsWith(lower(names),lower(extractAfter(pattern,1)));
else
    tf = strcmpi(names,pattern);
end
end

function tf = isSkipped(rel,skipStores)
% Whether a folder (relative to the scanned root) is hidden or in a store.
% Hidden is a "." folder, or one of Windows' own at a drive root -- a stick
% from the rig opened at its top has a $RECYCLE.BIN of deleted recordings,
% which are not a session.
tf = false;
if rel == "", return; end
parts = split(rel,"/");
tf = any(startsWith(parts,[".","$"]) | strcmpi(parts,"System Volume Information"));
if ~tf && skipStores
    tf = any(strcmpi(parts,mabr.analysis.Catalog.StoreFolder));
end
end

function r = blankRecord(tmpl,d,path)
% The record of a file listed but not read.
r = tmpl;
r.Path     = path;
r.Folder   = string(d.folder);
r.FileName = string(d.name);
r.Bytes    = double(d.bytes);
r.Modified = datetime(d.datenum,'ConvertFrom','datenum');
[r.Subject,r.SubjectRaw] = pathSubject(r.FileName);
r.Ok       = false;
r.Error    = "metadata not read (ReadMetadata is false)";
r.Warnings = strings(0,1);
end

function P = mergeEntries(C,paths,bytes,dnum,recs)
% The loaded cache entries with these fresh ones replacing or joining them
% (less any old entry that is a failure to load, which is never kept).
keepOld = ~ismember(C.Lower,lower(paths)) & ~C.Retry;
P = struct('Path',[C.Path(keepOld); paths], ...
    'Bytes',[C.Bytes(keepOld); bytes], ...
    'Modified',[C.Modified(keepOld); dnum], ...
    'Rec',{[C.Rec(keepOld); num2cell(recs(:))]});
end

function tf = retryRead(R)
% Whether each record says its file could not be LOADED (or had gone by the
% time it was opened) -- a verdict about that moment rather than about the
% file, so it is never served from the cache. A file that loaded but is not
% a usable recording (Skipped, a missing field, an unparseable one) stays
% that way until it changes, and is cached like any other.
tf = false(numel(R),1);
if isempty(R), return; end
ok  = reshape([R.Ok],[],1);
skp = reshape([R.Skipped],[],1);
err = reshape([R.Error],[],1);
tf  = ~ok & ~skp & (startsWith(err,"could not load") | err == "file not found");
end

function [s,raw] = pathSubject(text)
% The first subject named in text (a path or a name), canonical and as
% spelled; "" when there is none.
s = "";  raw = "";
m = regexp(char(text),'SUBJ[-_ ]?ID[-_ ]?[A-Za-z0-9]+','match','once','ignorecase');
if isempty(m), return; end
[s,raw] = mabr.analysis.AbrFile.canonicalSubject(string(m));
end

function t = keyPathText(arName,key)
% "<analysis root name>/<key>": a session's path from the analysis root
% down, the text its subject is read from.
if key == "."
    t = arName;
else
    t = arName + "/" + key;
end
end

function s = folderName(p)
% The last component of a path. A drive root has none, and its name is
% what a session there is called and what its results file is named after
% -- "" would make that file ".mat" -- so it is named for its drive letter.
[~,nm,ext] = fileparts(char(p));
s = string([nm ext]);
if s == ""
    tok = regexp(char(p),'^([A-Za-z]):','tokens','once');
    if ~isempty(tok), s = string(tok{1}); else, s = "root"; end
end
end

function r = relPath(base,f)
% f relative to base with "/" separators: "" when f is base. A path not
% under base comes back whole (it should not happen).
b = char(base);  f = char(f);
if strcmpi(f,b), r = ""; return; end
if ~(endsWith(b,'\') || endsWith(b,'/')), b = [b filesep]; end
if numel(f) > numel(b) && strcmpi(f(1:numel(b)),b)
    r = string(strrep(f(numel(b)+1:end),'\','/'));
else
    r = string(strrep(f,'\','/'));
end
end

function tf = isUnder(child,parent)
% Whether each child path is parent or inside it (case-insensitive).
child = reshape(string(child),[],1);
p = lower(strrep(char(parent),'/','\'));
p = regexprep(p,'\\+$','');
c = lower(strrep(child,'/','\'));
c = regexprep(c,'\\+$','');
tf = c == string(p) | startsWith(c,string(p) + "\");
end

function p = absFolder(p)
% An existing folder's absolute path as dir() spells it, without a trailing
% separator (but a drive root keeps its own).
p = char(p);
d = dir(p);
if ~isempty(d)
    p = d(1).folder;
elseif ~isAbsolute(p)
    p = fullfile(pwd,p);
end
p = string(trimSeparators(p));
end

function p = absPath(p)
% A path made absolute (against pwd) whether or not it exists yet.
p = char(strtrim(string(p)));
if isfolder(p)
    p = char(absFolder(p));
elseif ~isAbsolute(p)
    p = fullfile(pwd,p);
end
p = string(trimSeparators(p));
end

function p = trimSeparators(p)
p = char(p);
if ispc, p = strrep(p,'/','\'); end
if ~isempty(regexp(p,'^[A-Za-z]:[\\/]*$','once'))
    p = [p(1:2) filesep];
else
    q = regexprep(p,'[\\/]+$','');
    if ~isempty(q), p = q; end
end
end

function tf = isAbsolute(p)
p = char(p);
tf = ~isempty(regexp(p,'^([A-Za-z]:[\\/]|[\\/]{2})','once')) || (~ispc && startsWith(p,'/'));
end

function d = stampDate(s)
% The date of a yyMMdd or yyMMdd'T'HHmmss stamp, NaT for anything else
% (including an impossible month, day or time).
d = NaT;
tok = regexp(char(s),'^(\d{2})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?$','tokens','once');
if isempty(tok), return; end
yy = str2double(tok{1});  mo = str2double(tok{2});  dd = str2double(tok{3});
if mo < 1 || mo > 12 || dd < 1 || dd > 31, return; end
if numel(tok) >= 6 && ~isempty(tok{4})
    if str2double(tok{4}) > 23 || str2double(tok{5}) > 59 || str2double(tok{6}) > 59, return; end
end
d = datetime(2000 + yy,mo,dd);
if day(d) ~= dd, d = NaT; end          % 31 Feb rolls over: not a date
end

function x = timeNum(t)
% Datetimes as numbers that sort the same way (seconds; NaN for NaT).
x = reshape(posixtime(t),[],1);
end

function r = naturalRank(s)
% Each text's position in natural order (mabr.analysis.Stats.naturalSort).
s = reshape(string(s),[],1);
r = zeros(numel(s),1);
if isempty(s), return; end
[~,i] = mabr.analysis.Stats.naturalSort(s);
r(i) = (1:numel(s))';
end

function restoreWarnings(w0,msg,id)
warning(w0);
lastwarn(msg,id);
end

% =========================================================================
%  Empty tables (the columns exist before anything is scanned)
% =========================================================================
function T = emptyFiles()
s = strings(0,1);  x = zeros(0,1);  t = NaT(0,1);  b = false(0,1);
T = table(s,s,s,s,x,t,s,s,t,s,s,x,x,s,s,b,s,s,x,b,s,s, ...
    'VariableNames',cellstr(mabr.analysis.Catalog.FileColumns));
end

function T = emptySessions()
s = strings(0,1);  x = zeros(0,1);  t = NaT(0,1);  b = false(0,1);
T = table(s,s,s,s,s,t,t,t,x,x,x,x,s,s,s,b,x,s,s,s,s,s,s,b, ...
    'VariableNames',cellstr(mabr.analysis.Catalog.SessionColumns));
end

function T = emptyStores()
T = table(strings(0,1),strings(0,1),zeros(0,1), ...
    'VariableNames',cellstr(mabr.analysis.Catalog.StoreColumns));
end
