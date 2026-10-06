classdef Project < handle
% mabr.analysis.Project  What a study knows about its sessions beyond the recordings.
%
%   A Catalog lists what is on disk; a Project holds what a person decided
%   about it: which visit each session was (Timepoint), which animal belongs
%   to which group, which sessions are in the study and why the others are
%   not, free columns of their own (a weight, an ear, a cage), sessions
%   pooled into one, the analysis settings in force, and how the study picks
%   between two sessions that measured the same thing. It lives in ONE file
%   beside the results, <ResultsFolder>/project.mat, and the study tables are
%   built from the results files alone -- never from raw data:
%
%       c = mabr.analysis.Catalog(root);  c.scan();
%       p = mabr.analysis.Project.open(c.ResultsFolder);
%       p.ensureSessions(c);                         % rows for new sessions (in memory)
%       p.label(c.Sessions.Key(3),"Timepoint","2 weeks");
%       p.label("SUBJ-ID-1254","Group","Noise");
%       V = p.view(c,settings);                      % the browser's table
%       A = p.aggregate(V.Key(V.InStudy),c);         % the study's tables
%       p.save();
%
%   OPENING WRITES NOTHING. open() reads project.mat if there is one and
%   otherwise starts an empty project in memory; ensureSessions() adds rows
%   for sessions the project has not seen, in memory too. Browsing a study
%   must leave it exactly as it was -- a data drive is often shared or
%   synced -- so nothing reaches disk until a person edits something (or a
%   results save, which needs the project anyway) and save() is called.
%
%   SAVING IS SAFE AGAINST A SECOND WRITER. Two MATLABs (or the GUI and a
%   batch script) may hold the same project. save() therefore reads the file
%   back first, and merges ROW BY ROW: a row only one side has is kept, and
%   for a row both have the one with the later Modified wins -- so two people
%   labelling different sessions both keep their work, and the same label
%   edited twice ends as the later edit. Columns, pools and the scalar
%   settings merge as wholes, the side that changed them since it loaded
%   winning. The write itself is atomic (Project.atomicSave: a .tmp-<pid>
%   file moved over the old one), and every save bumps Revision.
%
%   LABELS ARE ROUTED BY LEVEL. A column belongs to the animal (Subjects:
%   Group, and any free subject column) or to the visit (Sessions:
%   Timepoint, InStudy, ExcludeReason, Comment, the overrides, any free
%   session column). label() takes either kind of key and finds the row the
%   column lives in, so Group set from one of an animal's sessions sets the
%   animal's group. Text is trimmed, and a value that differs from one
%   already in use only by case or spacing becomes that one ("baseline " ->
%   "Baseline") -- a study whose Timepoint column holds both cannot be
%   analysed -- with a note saying so.
%
%   TIMEPOINTS. A new session's Timepoint is the one its animal's other
%   sessions that day already have -- two sessions on one day are one visit
%   -- else the label its folder name suggests (Catalog.inferLabel); when the
%   folder says only the day, the animal's visits are numbered "Session 1",
%   "Session 2", ... in date order. Rows already in a project are never
%   relabelled. Their order (Columns.Levels of Timepoint) is by median visit date unless set
%   with setLevels; ReferenceTimepoint ("" = the first) is what
%   DaysFromReference counts from.
%
%   HIDDEN. A session (or pool) labelled Hidden is out of the study and out
%   of sight: view() reports it with InStudy false whatever its own InStudy
%   label says (the label is kept, so un-hiding puts the session back
%   exactly as it was), studyKeys() leaves it out, and the analysis app's
%   browser lists it only under Show ▸ Hidden. It is for what a folder holds
%   that is not the study's -- a pilot run, a recording abandoned, a
%   calibration -- and that should stop cluttering the list. Hidden is
%   false unless set, also for a project.mat written before the column.
%
%   POOLS. addPool makes several sessions of one animal one unit of
%   analysis ("pool:" + Stats.hex8 of the sorted member keys -- the hash
%   Catalog.resultsFile names the pooled results file by). Its members leave
%   the study while it exists (their previous InStudy is kept and put back by
%   removePool), so a session is never counted twice.
%
%   STUDY USE. The study unit is subject x Timepoint x series: when two
%   in-study sessions measured the same series at the same visit,
%   DuplicatePolicy decides -- "most-sweeps" (default; the larger median
%   clean sweep count over the series, ties to the later session), "latest",
%   or "mean" (both are used). aggregate() and exportItems() mark every
%   series row UsedInStudy accordingly and list the choices in Duplicates.
%
%   LATENCY OVERRIDES (A9). TimeOffsetOverride and ConductionDelayOverride
%   (ms, NaN = none) replace the settings' fixed offset and sound conduction
%   delay for one session; they reach a Session through applyOverrides
%   (or sessionOverrides / batchItems) and an export through exportItems'
%   Labels.
%
%   RUNS. recordRun(keys,errorText) notes an analysis attempt (LastRun,
%   LastError); view() reports a failure newer than the results file.
%
%   Nothing here prints, raises a dialog or touches a preference.
%
%   See also mabr.analysis.Catalog, mabr.analysis.Session,
%   mabr.analysis.Export, mabr.analysis.Settings.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        ResultsFolder (1,1) string = ""        % the results store this project lives in
        File          (1,1) string = ""        % <ResultsFolder>/project.mat
        FormatVersion (1,1) double = 1         % what save() writes
        Revision      (1,1) double = 0         % bumped by every save
        AnalysisRoot  (1,1) string = ""        % the catalog's, recorded at ensureSessions/save

        % One row per animal: Subject, Group, InStudy, Comment, Modified +
        % free subject columns. Natural subject order.
        Subjects table = table()

        % One row per session folder key (and per pool): Key, Subject,
        % SubjectOverride, Timepoint, InStudy, Hidden, ExcludeReason, Comment,
        % TimeOffsetOverride, ConductionDelayOverride, InputFullScaleOverride,
        % AmplifierGainOverride, LastRun, LastError, Day, Modified + free
        % session columns.
        Sessions table = table()

        % The label columns: Name, Level ("subject"|"session"), Type
        % ("text"|"number"), Levels (cell of string columns: the order of a
        % text column's values), Builtin.
        Columns table = table()

        % Key ("pool:<hex8>"), Name, Members ("k1|k2|..."), Created,
        % PreviousInStudy ("1|0|...", the members' InStudy before pooling).
        Pools table = table()

        Settings = []                          % [] or a mabr.analysis.Settings
        DuplicatePolicy (1,1) string = "most-sweeps"   % "most-sweeps" | "latest" | "mean"
        ReferenceTimepoint (1,1) string = ""   % "" = the first in Timepoint order
        ReviewQueue struct = struct('Keys',strings(0,1),'Position',0,'Order',"", ...
            'Seed',1,'Blind',false,'UnreviewedOnly',false)
        ImportedStores (:,1) string = strings(0,1)
        IgnoredStores  (:,1) string = strings(0,1)

        Dirty    (1,1) logical = false         % edited since the last save
        ReadOnly (1,1) logical = false         % a newer format, or an unreadable file
        LoadedStamp struct = struct('bytes',NaN,'datenum',NaN)   % project.mat as loaded
        FileFormatVersion (1,1) double = NaN   % the FormatVersion the file said (NaN: none)
        Warnings (:,1) string = strings(0,1)   % what open() noticed
    end

    properties (Access = private)
        Changed  (1,:) string = strings(1,0)   % whole-field parts edited since load/save
        RemovedColumns (1,:) string = strings(1,0)   % tombstones for the merge
        RemovedPools   (1,:) string = strings(1,0)
        LoadedRevision (1,1) double = NaN
        % The column names and pool keys the file held when this side last
        % loaded or saved it: a name in neither the file nor here was removed
        % by the other writer, and must stay removed in the merge.
        LoadedColumns (:,1) string = strings(0,1)
        LoadedPools   (:,1) string = strings(0,1)
        Cache = []                             % results() cache, containers.Map by file
    end

    properties (Constant)
        FileName = "project.mat"
        VarName  = "MABRAnalysisProject"
        Policies = ["most-sweeps" "latest" "mean"]
        SessionBuiltins = ["Key" "Subject" "SubjectOverride" "Timepoint" "InStudy" "Hidden" ...
            "ExcludeReason" "Comment" "TimeOffsetOverride" "ConductionDelayOverride" ...
            "InputFullScaleOverride" "AmplifierGainOverride" "LastRun" "LastError" "Day" "Modified"]
        SubjectBuiltins = ["Subject" "Group" "InStudy" "Comment" "Modified"]
        % The logical columns that are false until set (every other logical
        % column, InStudy above all, is true for a row that lacks it).
        OffByDefault = "Hidden"
        % The small results variables view() and results() read by default:
        % everything a status, a review count and a processing mode need, and
        % nothing per sweep.
        SmallVars = ["Version" "Provenance" "Summary" "StepState" "Thresholds" "Conditions"]
    end

    methods
        % =================================================================
        %  Construction and persistence
        % =================================================================
        function obj = Project(resultsFolder)
            % Project(resultsFolder) is a new, empty project for that store.
            % Nothing is read or written; Project.open reads an existing one.
            arguments
                resultsFolder (1,1) string = ""
            end
            obj.ResultsFolder = resultsFolder;
            if resultsFolder ~= ""
                obj.File = string(fullfile(char(resultsFolder),char(mabr.analysis.Project.FileName)));
            end
            obj.Subjects = emptySubjects();
            obj.Sessions = emptySessions();
            obj.Columns  = builtinColumns();
            obj.Pools    = emptyPools();
        end

        function save(obj)
            % Write project.mat: reload, merge, atomic write, Revision + 1.
            %
            %   save()
            %
            %   If the file on disk is not the one this project was loaded
            %   from (another MATLAB saved meanwhile), it is read back and
            %   merged first: rows by key, the later Modified winning;
            %   columns, pools and the scalar fields by whole field, the side
            %   that changed them winning. Creates the folder on the first
            %   save. A read-only project (a newer format, or a file that
            %   could not be read) refuses: mabr:analysis:Project:readOnly.
            if obj.ReadOnly
                error('mabr:analysis:Project:readOnly', ['The project %s is read-only (%s); ' ...
                    'it is not written back.'],obj.File,strjoin(obj.Warnings,' '));
            end
            if obj.File == ""
                error('mabr:analysis:Project:noFile','This project has no results folder to save into.');
            end
            if isfile(obj.File)
                [D,ok,why] = readProjectFile(obj.File);
                if ~ok
                    error('mabr:analysis:Project:badFile', ['%s cannot be read (%s); it is not ' ...
                        'overwritten.'],obj.File,why);
                end
                if getf(D,'FormatVersion',1) > obj.FormatVersion
                    error('mabr:analysis:Project:readOnly', ['%s was written by a newer MABR ' ...
                        '(format %g); it is not overwritten.'],obj.File,getf(D,'FormatVersion',1));
                end
                same = isequaln(fileStamp(obj.File),obj.LoadedStamp) && ...
                    isequaln(getf(D,'Revision',0),obj.LoadedRevision);
                if ~same
                    obj.mergeFrom(D);
                end
                obj.Revision = max(obj.Revision,double(getf(D,'Revision',0))) + 1;
            else
                obj.Revision = obj.Revision + 1;
            end
            S = obj.toStruct();
            mabr.analysis.Project.atomicSave(obj.File,mabr.analysis.Project.VarName,S);
            obj.LoadedStamp    = fileStamp(obj.File);
            obj.LoadedRevision = obj.Revision;
            obj.LoadedColumns  = obj.Columns.Name;
            obj.LoadedPools    = obj.Pools.Key;
            obj.Dirty          = false;
            obj.Changed        = strings(1,0);
            obj.RemovedColumns = strings(1,0);
            obj.RemovedPools   = strings(1,0);
        end

        function S = toStruct(obj)
            % The project as the plain struct project.mat holds (§16.2).
            S = struct();
            S.FormatVersion      = obj.FormatVersion;
            S.Revision           = obj.Revision;
            S.Saved              = mabr.analysis.Stats.isoTime(datetime('now'));
            S.AnalysisRoot       = obj.AnalysisRoot;
            S.Subjects           = obj.Subjects;
            S.Sessions           = obj.Sessions;
            S.Columns            = obj.Columns;
            S.Pools              = obj.Pools;
            if isempty(obj.Settings)
                S.Settings = [];
            elseif isstruct(obj.Settings)
                S.Settings = obj.Settings;
            else
                S.Settings = obj.Settings.toStruct();
            end
            S.DuplicatePolicy    = obj.DuplicatePolicy;
            S.ReferenceTimepoint = obj.ReferenceTimepoint;
            S.ReviewQueue        = obj.ReviewQueue;
            S.ImportedStores     = obj.ImportedStores;
            S.IgnoredStores      = obj.IgnoredStores;
        end

        % =================================================================
        %  Sessions from a catalog
        % =================================================================
        function ensureSessions(obj,catalog)
            % Rows for every catalog session the project lacks (in memory).
            %
            %   ensureSessions(catalog)
            %
            %   A new session gets the Timepoint its animal's other sessions
            %   that day already have, else its folder's InferredLabel;
            %   InStudy false with ExcludeReason "Test Mode" when every file
            %   of it is Test Mode; a Subjects row for an animal not seen
            %   before. New Timepoint values join the order after the
            %   existing ones, by median visit date. No existing row is
            %   changed (but a missing Day is filled in), and Dirty is not set
            %   -- browsing writes nothing.
            arguments
                obj
                catalog (1,1) mabr.analysis.Catalog
            end
            obj.AnalysisRoot = catalog.AnalysisRoot;
            % Days of rows that predate the Day column, or were imported.
            if height(obj.Sessions) > 0
                [tf,loc] = ismember(obj.Sessions.Key,catalog.Sessions.Key);
                fill = tf & isnat(obj.Sessions.Day);
                obj.Sessions.Day(fill) = catalog.Sessions.Day(loc(fill));
            end
            N = obj.proposedRows(catalog);
            if height(N) == 0, return; end
            obj.Sessions = [obj.Sessions; N];
            obj.addSubjectRows(unique(effectiveSubject(N),'stable'));
            obj.extendLevels("Timepoint",N.Timepoint,N.Day);
        end

        % =================================================================
        %  Labels
        % =================================================================
        function [v,note] = label(obj,keys,name,value)
            % Set one label on some sessions or subjects.
            %
            %   [v,note] = label(keys,name,value)
            %
            %   keys   session keys (Sessions.Key, pools included) and/or
            %          subject names (Subjects.Subject, any spelling)
            %   name   a Sessions column (Timepoint, InStudy, Hidden,
            %          ExcludeReason, Comment, SubjectOverride, TimeOffsetOverride,
            %          ConductionDelayOverride, InputFullScaleOverride,
            %          AmplifierGainOverride, free session columns) or a
            %          Subjects column (Group, free subject columns; Comment
            %          and InStudy through a subject key). The column's Level
            %          decides the table: a subject-level column given a
            %          session key edits that session's animal.
            %   value  the value; text is trimmed, and a text column's value
            %          differing from one in use only by case or spacing
            %          becomes that one. A number column takes numbers or
            %          numeric text ("" = NaN); anything else is refused
            %          (mabr:analysis:Project:badValue).
            %   v      (returned) the value as stored
            %   note   (returned) "" or what was done to the value
            %
            %   Every edited row gets Modified = now; the project is Dirty.
            arguments
                obj
                keys string
                name (1,1) string
                value
            end
            keys = reshape(keys,[],1);
            keys(ismissing(keys)) = [];
            if isempty(keys)
                error('mabr:analysis:Project:noKeys','label needs at least one key.');
            end
            [name,level,type] = obj.columnInfo(name);

            % Which rows: sessions and subjects, by key.
            isSess = ismember(keys,obj.Sessions.Key);
            subjOf = strings(numel(keys),1);
            for i = 1:numel(keys)
                if isSess(i)
                    r = find(obj.Sessions.Key == keys(i),1);
                    subjOf(i) = effectiveSubject(obj.Sessions(r,:));
                else
                    s = obj.subjectKey(keys(i));
                    if s == ""
                        error('mabr:analysis:Project:unknownKey', ['"%s" is neither a session nor a ' ...
                            'subject of this project (call ensureSessions first).'],keys(i));
                    end
                    subjOf(i) = s;
                end
            end
            toSubject = level == "subject" || (any(~isSess) && ismember(name,["Comment" "InStudy"]));
            if ~toSubject && any(~isSess)
                error('mabr:analysis:Project:badLevel', ['"%s" is a session column; "%s" is a ' ...
                    'subject. Label its sessions instead.'],name,keys(find(~isSess,1)));
            end

            % The value, coerced to the column.
            [v,note] = obj.coerce(name,level,type,value);
            now_ = datetime('now');
            if toSubject
                obj.addSubjectRows(unique(subjOf,'stable'));
                rows = find(ismember(obj.Subjects.Subject,subjOf));
                obj.Subjects.(name)(rows) = v;
                obj.Subjects.Modified(rows) = now_;
            else
                rows = find(ismember(obj.Sessions.Key,keys));
                if name == "SubjectOverride"
                    obj.Sessions.SubjectOverride(rows) = v;
                    obj.addSubjectRows(unique(effectiveSubject(obj.Sessions(rows,:)),'stable'));
                else
                    obj.Sessions.(name)(rows) = v;
                end
                obj.Sessions.Modified(rows) = now_;
                if name == "Timepoint"
                    obj.extendLevels("Timepoint",repmat(v,numel(rows),1),obj.Sessions.Day(rows));
                end
            end
            if type == "text" && ~ismember(name,["Timepoint" "Comment" "ExcludeReason" "SubjectOverride"])
                obj.extendLevels(name,v,NaT);
            end
            obj.Dirty = true;
        end

        function recordRun(obj,keys,errorText)
            % Note that keys were just analysed: LastRun = now, LastError.
            %
            %   recordRun(keys,errorText)
            %
            %   errorText  "" for a run that succeeded (the default), else the
            %              message view() reports as "Failed: <message>"
            %              until a results file newer than the failure exists
            arguments
                obj
                keys string
                errorText (1,1) string = ""
            end
            rows = find(ismember(obj.Sessions.Key,reshape(keys,[],1)));
            if isempty(rows), return; end
            now_ = datetime('now');
            obj.Sessions.LastRun(rows)   = now_;
            obj.Sessions.LastError(rows) = errorText;
            obj.Sessions.Modified(rows)  = now_;
            obj.Dirty = true;
        end

        function keys = studyKeys(obj)
            % The session and pool keys in the study: InStudy, not Hidden,
            % and their animal in the study -- view()'s InStudy &
            % SubjectInStudy, without a catalog (rows ensureSessions added).
            S = obj.Sessions;
            subj = effectiveSubject(S);
            [tf,loc] = ismember(subj,obj.Subjects.Subject);
            animal = true(height(S),1);
            animal(tf) = obj.Subjects.InStudy(loc(tf));
            keys = S.Key(S.InStudy & ~S.Hidden & animal);
        end

        function tf = isHidden(obj,keys)
            % Whether each of keys is a Hidden session or pool (a key the
            % project has no row for is not).
            arguments
                obj
                keys string
            end
            [in,loc] = ismember(keys,obj.Sessions.Key);
            tf = false(size(keys));
            tf(in) = obj.Sessions.Hidden(loc(in));
        end

        % =================================================================
        %  Columns
        % =================================================================
        function addColumn(obj,name,level,type)
            % A free label column: addColumn(name,"subject"|"session","text"|"number").
            arguments
                obj
                name (1,1) string
                level (1,1) string {mustBeMember(level,["subject","session"])}
                type (1,1) string {mustBeMember(type,["text","number"])} = "text"
            end
            name = strtrim(name);
            obj.checkNewName(name);
            if type == "text", def = ""; else, def = NaN; end
            if level == "subject"
                obj.Subjects.(name) = repmat(def,height(obj.Subjects),1);
            else
                obj.Sessions.(name) = repmat(def,height(obj.Sessions),1);
            end
            obj.Columns = [obj.Columns; columnRow(name,level,type,strings(0,1),false)];
            obj.RemovedColumns(obj.RemovedColumns == name) = [];
            obj.touch("Columns");
        end

        function removeColumn(obj,name)
            % Remove a free column (and its values). Built-ins are refused.
            arguments
                obj
                name (1,1) string
            end
            r = obj.freeColumnRow(name);
            name = obj.Columns.Name(r);
            if obj.Columns.Level(r) == "subject"
                obj.Subjects.(name) = [];
            else
                obj.Sessions.(name) = [];
            end
            obj.Columns(r,:) = [];
            obj.RemovedColumns = unique([obj.RemovedColumns name],'stable');
            obj.touch("Columns");
        end

        function renameColumn(obj,old,new)
            % Rename a free column, keeping its values and levels.
            arguments
                obj
                old (1,1) string
                new (1,1) string
            end
            r = obj.freeColumnRow(old);
            old = obj.Columns.Name(r);
            new = strtrim(new);
            if new == old, return; end
            if lower(new) ~= lower(old), obj.checkNewName(new); end
            if obj.Columns.Level(r) == "subject"
                obj.Subjects = renamevars(obj.Subjects,old,new);
            else
                obj.Sessions = renamevars(obj.Sessions,old,new);
            end
            obj.Columns.Name(r) = new;
            obj.RemovedColumns = unique([obj.RemovedColumns old],'stable');
            obj.RemovedColumns(obj.RemovedColumns == new) = [];
            obj.touch("Columns");
        end

        function setLevels(obj,name,levels)
            % The order of a text column's values (Timepoint: the visits).
            %
            %   setLevels(name,levels)
            %
            %   levels  the values in order (unique, any case); values in use
            %           but not listed keep their place after them, so a
            %           level cannot be lost by leaving it out
            arguments
                obj
                name (1,1) string
                levels string
            end
            [name,level,type] = obj.columnInfo(name);
            if type ~= "text"
                error('mabr:analysis:Project:badColumn','"%s" is a number column; it has no levels.',name);
            end
            levels = strtrim(reshape(levels,[],1));
            levels(ismissing(levels) | levels == "") = [];
            if numel(unique(lower(levels))) < numel(levels)
                error('mabr:analysis:Project:badLevels','The levels of "%s" repeat a value.',name);
            end
            if level == "subject", used = obj.Subjects.(name); else, used = obj.Sessions.(name); end
            used = unique(used(used ~= ""),'stable');
            r = find(obj.Columns.Name == name,1);
            rest = unionStable(obj.Columns.Levels{r},used);
            rest = rest(~ismember(lower(rest),lower(levels)));
            obj.Columns.Levels{r} = [levels; rest];
            obj.touch("Columns");
        end

        % =================================================================
        %  Pools
        % =================================================================
        function key = addPool(obj,keys,name,opts)
            % Several sessions of one animal analysed as one.
            %
            %   key = addPool(keys,name,Force=false)
            %
            %   keys        two or more session folder keys of this project
            %   name        display name ("" = "<first name> + <n-1>")
            %   opts.Force  allow sessions of different subjects (refused
            %               otherwise: mabr:analysis:Project:poolSubjects)
            %   key         (returned) "pool:" + Stats.hex8(join(sort(keys),"|"))
            %
            %   The members leave the study (their InStudy kept in
            %   PreviousInStudy for removePool) and the pool gets a Sessions
            %   row of its own, in the study, at the first member's
            %   Timepoint. Pooling the same sessions again returns the same key.
            arguments
                obj
                keys string
                name (1,1) string = ""
                opts.Force (1,1) logical = false
            end
            keys = unique(strtrim(reshape(keys,[],1)));
            keys(ismissing(keys) | keys == "") = [];
            if numel(keys) < 2
                error('mabr:analysis:Project:badPool','A pool needs at least two sessions.');
            end
            if any(startsWith(keys,"pool:"))
                error('mabr:analysis:Project:badPool','A pool cannot contain a pool.');
            end
            [tf,rows] = ismember(keys,obj.Sessions.Key);
            if ~all(tf)
                error('mabr:analysis:Project:unknownKey','"%s" is not a session of this project.', ...
                    keys(find(~tf,1)));
            end
            key = "pool:" + mabr.analysis.Stats.hex8(join(keys,"|"));
            if any(obj.Pools.Key == key), return; end
            for k = 1:height(obj.Pools)
                hit = intersect(split(obj.Pools.Members(k),"|"),keys);
                if ~isempty(hit)
                    error('mabr:analysis:Project:badPool','"%s" is already in the pool "%s".', ...
                        hit(1),obj.Pools.Name(k));
                end
            end
            subj = effectiveSubject(obj.Sessions(rows,:));
            if numel(unique(subj)) > 1 && ~opts.Force
                error('mabr:analysis:Project:poolSubjects', ['These sessions belong to different ' ...
                    'subjects (%s); pass Force=true to pool them anyway.'],strjoin(unique(subj),', '));
            end
            if name == ""
                parts = split(keys(1),"/");
                name = parts(end) + " + " + (numel(keys) - 1);
            end
            now_ = datetime('now');
            prev = join(string(double(obj.Sessions.InStudy(rows))),"|");
            obj.Pools = [obj.Pools; table(key,name,join(keys,"|"),now_,prev,'VariableNames', ...
                {'Key','Name','Members','Created','PreviousInStudy'})];
            obj.RemovedPools(obj.RemovedPools == key) = [];
            obj.Sessions.InStudy(rows) = false;
            obj.Sessions.Modified(rows) = now_;
            R = obj.Sessions(rows(1),:);
            R.Key = key;
            R.InStudy = true;
            R.Hidden = false;
            R.ExcludeReason = "";
            R.Comment = "";
            R.LastRun = NaT;  R.LastError = "";
            R.Day = min(obj.Sessions.Day(rows));
            R.Modified = now_;
            obj.Sessions(obj.Sessions.Key == key,:) = [];
            obj.Sessions = [obj.Sessions; R];
            obj.touch("Pools");
        end

        function removePool(obj,key)
            % Dissolve a pool: its members' InStudy back as they were.
            arguments
                obj
                key (1,1) string
            end
            r = find(obj.Pools.Key == key,1);
            if isempty(r)
                error('mabr:analysis:Project:unknownKey','"%s" is not a pool of this project.',key);
            end
            m = split(obj.Pools.Members(r),"|");
            prev = split(obj.Pools.PreviousInStudy(r),"|");
            now_ = datetime('now');
            for i = 1:numel(m)
                j = find(obj.Sessions.Key == m(i),1);
                if isempty(j), continue; end
                was = true;
                if i <= numel(prev), was = prev(i) ~= "0"; end
                obj.Sessions.InStudy(j) = was;
                obj.Sessions.Modified(j) = now_;
            end
            obj.Pools(r,:) = [];
            obj.Sessions(obj.Sessions.Key == key,:) = [];
            obj.RemovedPools = unique([obj.RemovedPools key],'stable');
            obj.touch("Pools");
        end

        function m = poolMembers(obj,key)
            % The member folder keys of a pool (a folder key: itself).
            arguments
                obj
                key (1,1) string
            end
            if ~startsWith(key,"pool:"), m = key; return; end
            r = find(obj.Pools.Key == key,1);
            if isempty(r)
                error('mabr:analysis:Project:unknownKey','"%s" is not a pool of this project.',key);
            end
            m = split(obj.Pools.Members(r),"|");
        end

        % =================================================================
        %  Scalar settings
        % =================================================================
        function setSettings(obj,s)
            % The analysis settings in force for this project ([] = none).
            arguments
                obj
                s
            end
            if ~(isempty(s) || isa(s,'mabr.analysis.Settings'))
                error('mabr:analysis:Project:badSettings','Settings is [] or a mabr.analysis.Settings.');
            end
            obj.Settings = s;
            obj.touch("Settings");
        end

        function setDuplicatePolicy(obj,policy)
            % "most-sweeps" | "latest" | "mean": which duplicated series the study uses.
            arguments
                obj
                policy (1,1) string
            end
            obj.DuplicatePolicy = checkPolicy(policy);
            obj.touch("DuplicatePolicy");
        end

        function setReferenceTimepoint(obj,tp)
            % The Timepoint DaysFromReference counts from ("" = the first).
            arguments
                obj
                tp (1,1) string
            end
            obj.ReferenceTimepoint = strtrim(tp);
            obj.touch("ReferenceTimepoint");
        end

        function setReviewQueue(obj,q)
            % The review queue (struct Keys, Position, Order, Seed, Blind, UnreviewedOnly).
            arguments
                obj
                q struct
            end
            d = obj.ReviewQueue;
            for f = string(fieldnames(d)).'
                if isfield(q,f), d.(f) = q.(f); end
            end
            d.Keys = reshape(string(d.Keys),[],1);
            obj.ReviewQueue = d;
            obj.touch("ReviewQueue");
        end

        function ignoreStore(obj,path)
            % Stop offering a nested results store for import.
            arguments
                obj
                path (1,1) string
            end
            obj.IgnoredStores = unique([obj.IgnoredStores; path],'stable');
            obj.Dirty = true;
        end

        % =================================================================
        %  Overrides for one session
        % =================================================================
        function o = sessionOverrides(obj,key)
            % What a Session built for key takes from the project.
            %
            %   o = sessionOverrides(key)
            %
            %   o  (returned) struct UnitOverride (InputFullScale,
            %      AmplifierGain; NaN = none), TimeOffset (ms, NaN = none:
            %      the settings' TimeOffset), ConductionDelay (ms, NaN = none:
            %      the settings' conductionDelay()), Members (folder keys)
            %
            %   The session's latency offset is the conduction delay (the
            %   override, else the settings') plus the time offset (the
            %   override, else the settings').
            arguments
                obj
                key (1,1) string
            end
            o = struct('UnitOverride',struct('InputFullScale',NaN,'AmplifierGain',NaN), ...
                'TimeOffset',NaN,'ConductionDelay',NaN,'Members',obj.poolMembers(key));
            r = find(obj.Sessions.Key == key,1);
            if isempty(r), return; end
            o.UnitOverride.InputFullScale = obj.Sessions.InputFullScaleOverride(r);
            o.UnitOverride.AmplifierGain  = obj.Sessions.AmplifierGainOverride(r);
            o.TimeOffset      = obj.Sessions.TimeOffsetOverride(r);
            o.ConductionDelay = obj.Sessions.ConductionDelayOverride(r);
        end

        function applyOverrides(obj,session,key)
            % Put key's project overrides on a mabr.analysis.Session.
            %
            %   applyOverrides(session,key)
            %
            %   Sets session.UnitOverride (InputFullScale, AmplifierGain),
            %   session.TimeOffset and session.ConductionDelayOverride (ms,
            %   NaN = the settings' own) from the Sessions row of key -- the
            %   one place a project's per-session values reach a Session, so
            %   the GUI and a batch build the same one. Its LatencyOffset is
            %   then (ConductionDelayOverride, else the settings' delay) +
            %   (TimeOffset, else the settings' TimeOffset).
            arguments
                obj
                session (1,1) mabr.analysis.Session
                key (1,1) string
            end
            o = obj.sessionOverrides(key);
            session.UnitOverride = o.UnitOverride;
            session.TimeOffset = o.TimeOffset;
            session.ConductionDelayOverride = o.ConductionDelay;
        end

        function T = batchItems(obj,keys,catalog)
            % The work list mabr.analysis.Batch.run takes, for these keys.
            %
            %   T = batchItems(keys,catalog)
            %
            %   T  (returned) table Key, Paths (cell of string columns),
            %      ResultsFile, Exclude (cell: the FileIds the existing results
            %      excluded), UnitOverride (cell of struct), TestMode (every
            %      file Test Mode), TimeOffset, ConductionDelay (ms, NaN none)
            arguments
                obj
                keys string
                catalog (1,1) mabr.analysis.Catalog
            end
            keys = reshape(keys,[],1);
            n = numel(keys);
            Paths = cell(n,1);  Ex = cell(n,1);  U = cell(n,1);
            RF = strings(n,1);  TM = false(n,1);  TO = NaN(n,1);  CD = NaN(n,1);
            for i = 1:n
                o = obj.sessionOverrides(keys(i));
                [~,loc] = ismember(o.Members,catalog.Sessions.Key);
                Paths{i} = catalog.Sessions.Path(loc(loc > 0));
                TM(i) = any(loc > 0) && all(catalog.Sessions.TestMode(loc(loc > 0)) == "all");
                RF(i) = obj.resultsFileOf(keys(i),catalog);
                Ex{i} = strings(0,1);
                R = obj.tryResults(keys(i),catalog,RF(i),"Summary");
                if ~isempty(R) && isfield(R,'Summary')
                    Ex{i} = reshape(string(getf(R.Summary,'Exclude',strings(0,1))),[],1);
                end
                U{i} = o.UnitOverride;
                TO(i) = o.TimeOffset;
                CD(i) = o.ConductionDelay;
            end
            T = table(keys,Paths,RF,Ex,U,TM,TO,CD,'VariableNames', ...
                {'Key','Paths','ResultsFile','Exclude','UnitOverride','TestMode','TimeOffset','ConductionDelay'});
        end

        % =================================================================
        %  The browser's table
        % =================================================================
        function V = view(obj,catalog,settings)
            % Catalog.Sessions joined with the labels and the results status.
            %
            %   V = view(catalog,settings)
            %
            %   catalog   a scanned mabr.analysis.Catalog
            %   settings  the mabr.analysis.Settings in force ([] = judge the
            %             data only, not the settings)
            %   V  (returned) one row per catalog session and per pool:
            %      Catalog.Sessions' columns (Subject the effective one), then
            %      IsPool, Members, PoolKey, the Sessions labels (InStudy
            %      false for a Hidden row, whatever its label: see HIDDEN in
            %      the class help), Group, SubjectInStudy, free subject
            %      columns, TimepointOrder, DaysFromReference, and
            %        Status      "none"|"current"|"stale"|"failed"
            %        StatusText  "Not analysed" | "Up to date (2026-09-30
            %                    15:40)" | "Out of date (settings changed)" |
            %                    "Out of date (files changed)" | "Out of date
            %                    (overrides changed)" | "Failed: <msg>"
            %        Reviewed    series with a decision; NumSeries all series
            %        SettingsHash, Processing (of the results)
            %        UsedInStudy at least one series used by the study
            %
            %   Results files are read for their small variables only
            %   (SmallVars), through the results() cache.
            arguments
                obj
                catalog (1,1) mabr.analysis.Catalog
                settings = []
            end
            V = obj.baseView(catalog);
            n = height(V);
            st = repmat("none",n,1);  txt = repmat("Not analysed",n,1);
            rev = zeros(n,1);  ns = zeros(n,1);  sh = strings(n,1);  pr = strings(n,1);
            Rs = cell(n,1);
            for i = 1:n
                f = V.ResultsFile(i);
                hasFile = isfile(f);
                R = [];
                bad = "";
                if hasFile
                    try
                        R = obj.results(V.Key(i),Catalog=catalog,File=f);
                    catch ME
                        bad = "the results file cannot be read (" + ME.message + ")";
                    end
                end
                Rs{i} = R;
                failed = V.LastError(i) ~= "" && ~ismissing(V.LastError(i)) && ...
                    (~hasFile || ~(fileTime(f) > V.LastRun(i)));
                if bad ~= ""
                    % One damaged file must not take the whole browser down.
                    st(i) = "failed";  txt(i) = "Failed: " + bad;
                elseif failed
                    st(i) = "failed";  txt(i) = "Failed: " + V.LastError(i);
                elseif ~isempty(R)
                    [st(i),txt(i)] = obj.statusOf(R,f,V(i,:),catalog,settings);
                end
                if ~isempty(R)
                    T = getf(R,'Thresholds',table());
                    if istable(T) && height(T) > 0
                        ns(i) = height(T);
                        if ismember('Decision',T.Properties.VariableNames)
                            rev(i) = nnz(string(T.Decision) ~= "");
                        end
                    end
                    sh(i) = string(getf(getf(R,'Provenance',struct()),'SettingsHash',""));
                    pr(i) = processingOf(getf(R,'Conditions',table()));
                end
            end
            V.Status = st;  V.StatusText = txt;  V.Reviewed = rev;  V.NumSeries = ns;
            V.SettingsHash = sh;  V.Processing = pr;
            U = obj.resolveUse(V,Rs,obj.DuplicatePolicy);
            V.UsedInStudy = cellfun(@(u) any(u.Used),U);
        end

        function R = results(obj,key,opts)
            % The variables of a results file, cached by file stamp.
            %
            %   R = results(key,Vars=...,Catalog=c,File=f)
            %
            %   key           a session or pool key
            %   opts.Vars     variables to read (default SmallVars); "all" =
            %                 every variable but Sweeps
            %   opts.Catalog  the catalog that names the results file (else
            %                 the project's ResultsFolder rule)
            %   opts.File     the file itself (overrides both)
            %   R  (returned) struct of the variables the file has, or [] when
            %      there is no file. A file that changed (bytes, time) is read
            %      again; a variable already read is not. What aggregate() and
            %      view() derive from a file is kept in the same cache entry
            %      (see memo), so it goes when the file changes.
            arguments
                obj
                key (1,1) string
                opts.Vars string = mabr.analysis.Project.SmallVars
                opts.Catalog = []
                opts.File (1,1) string = ""
            end
            f = opts.File;
            if f == "", f = obj.resultsFileOf(key,opts.Catalog); end
            R = [];
            if ~isfile(f), return; end
            if isempty(obj.Cache)
                obj.Cache = containers.Map('KeyType','char','ValueType','any');
            end
            ck = lower(char(f));
            stamp = fileStamp(f);
            E = struct('Stamp',stamp,'R',struct(),'Have',strings(1,0),'All',strings(1,0), ...
                'Derived',struct());
            if isKey(obj.Cache,ck)
                E0 = obj.Cache(ck);
                if isequaln(E0.Stamp,stamp), E = E0; end
            end
            if isempty(E.All)
                E.All = reshape(string(who('-file',char(f))),1,[]);
            end
            want = reshape(opts.Vars,1,[]);
            if any(want == "all"), want = E.All(E.All ~= "Sweeps"); end
            need = setdiff(intersect(want,E.All),E.Have,'stable');
            if ~isempty(need)
                L = load(char(f),'-mat',need{:});
                for v = need
                    E.R.(v) = L.(v);
                end
                E.Have = [E.Have need];
            end
            obj.Cache(ck) = E;
            R = struct();
            for v = intersect(want,E.Have,'stable')
                R.(v) = E.R.(v);
            end
        end

        % =================================================================
        %  The study
        % =================================================================
        function A = aggregate(obj,keys,catalog,opts)
            % The study's tables, from results files only.
            %
            %   A = aggregate(keys,catalog,Waveforms=false,DuplicatePolicy=...)
            %
            %   keys     session/pool keys ([] = every key in the study)
            %   catalog  the scanned catalog of the study
            %   opts.Waveforms        also A.Means (default false)
            %   opts.DuplicatePolicy  default the project's
            %   A  (returned) struct of tables, the Export tables' content
            %      under model names:
            %        Sessions      one row per key with results
            %        Subjects      the project's rows for their animals
            %        Conditions    every results Conditions row + labels
            %        Thresholds    every series row (no Fit) + labels,
            %                      TimepointOrder, UsedInStudy
            %        Peaks         every pick + labels, UsedInStudy
            %        PeakMeasures  Peaks.derived per condition + labels
            %        IOSlopes      Peaks.derived per series x wave + labels
            %        Means         (Waveforms) per condition: Time, Mean
            %                      (balanced), SEM, N, as cells
            %        Duplicates    Subject, Timepoint, SeriesKey, Keys, Used
            %                      ("|"-joined): the units the policy chose for
            %      Every label column is Session (the key), Subject,
            %      Timepoint, Group.
            %
            %   Each results file is read once (the results() cache), and
            %   what is made from it -- Peaks.derived, its tables with and
            %   without labels, its series' sweep counts -- is remembered with
            %   it until the file changes. A second call costs only what
            %   changed: after a label edit, the sessions it relabelled; after
            %   a re-analysis, the files rewritten.
            arguments
                obj
                keys string
                catalog (1,1) mabr.analysis.Catalog
                opts.Waveforms (1,1) logical = false
                opts.DuplicatePolicy (1,1) string = ""
            end
            policy = opts.DuplicatePolicy;
            if policy == "", policy = obj.DuplicatePolicy; end
            policy = checkPolicy(policy);
            B = obj.baseView(catalog);
            keys = reshape(keys,[],1);
            if isempty(keys), keys = B.Key(B.InStudy & B.SubjectInStudy); end
            [tf,loc] = ismember(keys,B.Key);
            if ~all(tf)
                error('mabr:analysis:Project:unknownKey','"%s" is not a session of this study.', ...
                    keys(find(~tf,1)));
            end
            B = B(loc,:);
            vars = ["Version" "Provenance" "Settings" "Summary" "Conditions" "Thresholds" "Peaks"];
            if opts.Waveforms, vars(end+1) = "Means"; end
            n = height(B);
            Rs = cell(n,1);
            for i = 1:n
                Rs{i} = obj.tryResults(B.Key(i),catalog,B.ResultsFile(i),vars);
            end
            [U,D] = obj.resolveUse(B,Rs,policy);
            has = ~cellfun(@isempty,Rs);

            % Per results file, the tables before labels (Peaks.derived the
            % costly part) and then the labelled ones are remembered with the
            % file in the results cache (memo) until it changes: the Study tab
            % calls this after every label edit, and an edit then relabels
            % only the sessions whose labels or study use it changed.
            need = ["Conditions" "Thresholds" "Peaks" "Settings" "Summary"];
            files = B.ResultsFile;  bk = B.Key;  bs = B.Subject;  bt = B.Timepoint;
            bg = B.Group;  bo = B.TimepointOrder;
            [C,T,P,M,G,W] = deal(cell(n,1));
            pr = strings(n,1);
            for i = find(has).'
                R = Rs{i};
                X = obj.memo(files(i),R,"parts",need,[],@studyParts,R);
                pr(i) = X.Processing;
                lab = struct('Session',bk(i),'Subject',bs(i),'Timepoint',bt(i),'Group',bg(i));
                L = obj.memo(files(i),R,"labelled",need,{lab,bo(i),U{i}}, ...
                    @labelledParts,X,lab,bo(i),U{i});
                C{i} = L.C;  T{i} = L.T;  P{i} = L.P;  M{i} = L.M;  G{i} = L.G;
                if opts.Waveforms
                    W{i} = obj.memo(files(i),R,"means",["Means" "Summary"],lab,@meansTable,lab,R);
                end
            end

            A = struct();
            A.Sessions = obj.studySessions(B(has,:),Rs(has),pr(has));
            subj = unique(B.Subject(has));
            A.Subjects = obj.Subjects(ismember(obj.Subjects.Subject,subj),:);
            A.Subjects.Modified = [];
            A.Conditions   = stackTables(C(has));
            A.Thresholds   = stackTables(T(has));
            A.Peaks        = stackTables(P(has));
            A.PeakMeasures = stackTables(M(has));
            A.IOSlopes     = stackTables(G(has));
            if opts.Waveforms, A.Means = stackTables(W(has)); end
            A.Duplicates   = D;
        end

        function items = exportItems(obj,keys,catalog,opts)
            % The input of mabr.analysis.Export.tables (§15.1) for these keys.
            %
            %   items = exportItems(keys,catalog,Notes=true,DuplicatePolicy=...)
            %
            %   items  (returned) struct array, one per key that has a results
            %          file (keys without one are left out): Key, Results (the
            %          file's variables but Sweeps), Labels (Subject,
            %          SubjectRaw, Timepoint, TimepointOrder, Group, InStudy,
            %          TestMode, DaysFromReference, TimeOffset and
            %          ConductionDelay -- the overrides, ms, NaN none --
            %          Comment, Free (free session columns), UsedInStudy
            %          (SeriesKey, Used)), Notes (Catalog.notes; a pool's
            %          members' together), Session ([])
            arguments
                obj
                keys string
                catalog (1,1) mabr.analysis.Catalog
                opts.Notes (1,1) logical = true
                opts.DuplicatePolicy (1,1) string = ""
            end
            policy = opts.DuplicatePolicy;
            if policy == "", policy = obj.DuplicatePolicy; end
            policy = checkPolicy(policy);
            B = obj.baseView(catalog);
            keys = reshape(keys,[],1);
            [tf,loc] = ismember(keys,B.Key);
            if ~all(tf)
                error('mabr:analysis:Project:unknownKey','"%s" is not a session of this study.', ...
                    keys(find(~tf,1)));
            end
            B = B(loc,:);
            n = height(B);
            Rs = cell(n,1);
            for i = 1:n
                Rs{i} = obj.tryResults(B.Key(i),catalog,B.ResultsFile(i),"all");
            end
            U = obj.resolveUse(B,Rs,policy);
            free = obj.Columns.Name(obj.Columns.Level == "session" & ~obj.Columns.Builtin);
            items = struct('Key',{},'Results',{},'Labels',{},'Notes',{},'Session',{});
            for i = 1:n
                if isempty(Rs{i}), continue; end
                L = struct();
                L.Subject = B.Subject(i);
                L.SubjectRaw = B.SubjectRaw(i);
                L.Timepoint = B.Timepoint(i);
                L.TimepointOrder = B.TimepointOrder(i);
                L.Group = B.Group(i);
                L.InStudy = B.InStudy(i) && B.SubjectInStudy(i);
                L.TestMode = B.TestMode(i) == "all";
                L.DaysFromReference = B.DaysFromReference(i);
                L.TimeOffset = B.TimeOffsetOverride(i);
                L.ConductionDelay = B.ConductionDelayOverride(i);
                L.Comment = B.Comment(i);
                Fr = struct();
                for c = reshape(free,1,[])
                    Fr.(matlab.lang.makeValidName(c)) = B.(c)(i);
                end
                L.Free = Fr;
                L.UsedInStudy = U{i};
                Nt = [];
                if opts.Notes
                    Nt = obj.notesOf(B(i,:),catalog);
                end
                items(end+1) = struct('Key',B.Key(i),'Results',Rs{i},'Labels',L, ...
                    'Notes',Nt,'Session',[]); %#ok<AGROW>
            end
        end

        % =================================================================
        %  A results store found below the study
        % =================================================================
        function [n,msg] = importStore(obj,nested,catalog)
            % Copy a nested store's results into this one and merge its labels.
            %
            %   [n,msg] = importStore(nested,catalog)
            %
            %   nested   the nested MABR_Analysis folder (or the folder above it)
            %   catalog  the scanned catalog of this study (keys and
            %            destinations come from it)
            %   n        (returned) results files imported (copied, or kept
            %            because the destination is newer)
            %   msg      (returned) what happened: files skipped, label
            %            conflicts (this project's edited rows win)
            %
            %   Each results file is re-keyed by prefixing the nested store's
            %   root relative to the analysis root, copied (never moved) to
            %   where this store keeps that key -- unless a newer file is
            %   already there -- with Summary.Key/Keys rewritten. Label rows
            %   are re-keyed the same way and merged: a row this project has
            %   never edited takes the imported values, an edited one keeps
            %   its own and the difference is listed. The nested store is
            %   never written to or deleted.
            arguments
                obj
                nested (1,1) string
                catalog (1,1) mabr.analysis.Catalog
            end
            store = char(nested);
            if ~isfile(fullfile(store,char(mabr.analysis.Project.FileName))) && ...
                    isfolder(fullfile(store,char(mabr.analysis.Catalog.StoreFolder)))
                store = fullfile(store,char(mabr.analysis.Catalog.StoreFolder));
            end
            if ~isfolder(store)
                error('mabr:analysis:Project:noStore','There is no results store at %s.',nested);
            end
            nroot = string(fileparts(store));
            prefix = relPath(catalog.AnalysisRoot,nroot);
            if prefix == "" || startsWith(prefix,"..") || isAbsolutePath(prefix)
                error('mabr:analysis:Project:noStore', ['The store %s is not below the analysis ' ...
                    'root %s.'],store,catalog.AnalysisRoot);
            end
            rekey = @(k) rekeyOne(k,prefix);
            notes = strings(0,1);
            n = 0;

            % ---- Results files.
            files = storeResults(store);
            for k = 1:numel(files)
                src = files(k);
                try
                    who_ = string(who('-file',char(src)));
                    if ~ismember("Summary",who_)
                        notes(end+1,1) = "skipped " + relPath(store,src) + " (not a results file)"; %#ok<AGROW>
                        continue
                    end
                    R = load(char(src),'-mat');
                catch ME
                    notes(end+1,1) = "skipped " + relPath(store,src) + " (" + ME.message + ")"; %#ok<AGROW>
                    continue
                end
                S = R.Summary;
                oldKey = string(getf(S,'Key',""));
                members = reshape(string(getf(S,'Keys',strings(0,1))),[],1);
                if startsWith(oldKey,"pool:") || numel(members) > 1
                    members = rekey(members);
                    newKey = "pool:" + mabr.analysis.Stats.hex8(join(sort(members),"|"));
                    dest = catalog.resultsFile(members);
                else
                    if oldKey == "" || ismissing(oldKey)
                        [~,b] = fileparts(char(src));
                        oldKey = string(b);
                    end
                    newKey = rekey(oldKey);
                    members = newKey;
                    dest = catalog.resultsFile(newKey);
                end
                if isfile(dest) && fileTime(dest) >= fileTime(src)
                    notes(end+1,1) = "kept the newer " + relPath(obj.ResultsFolder,dest); %#ok<AGROW>
                    n = n + 1;
                    continue
                end
                R.Summary.Key  = newKey;
                R.Summary.Keys = members;
                mabr.analysis.Project.atomicSave(dest,"",R);
                n = n + 1;
            end

            % ---- Labels.
            [D,ok] = readProjectFile(string(fullfile(store,char(mabr.analysis.Project.FileName))));
            if ok
                notes = [notes; obj.mergeImported(D,rekey)];
            end
            obj.ImportedStores = unique([obj.ImportedStores; string(store)],'stable');
            obj.IgnoredStores(strcmpi(obj.IgnoredStores,string(store))) = [];
            obj.Dirty = true;
            msg = sprintf('Imported %d results file(s) from %s.',n,store);
            if ~isempty(notes)
                msg = string(msg) + newline + join(notes,newline);
            end
            msg = string(msg);
            obj.Cache = [];
        end
    end

    methods (Static)
        function obj = open(resultsFolder)
            % The project of a results store; NEVER writes.
            %
            %   p = Project.open(resultsFolder)
            %
            %   Reads <resultsFolder>/project.mat when it exists, else returns
            %   a new empty project (nothing is created until save). A file of
            %   a newer FormatVersion is read for the fields this version
            %   knows and the project is ReadOnly; so is one that cannot be
            %   read at all (Warnings says why) -- it is never overwritten.
            arguments
                resultsFolder (1,1) string
            end
            obj = mabr.analysis.Project(resultsFolder);
            if ~isfile(obj.File), return; end
            [D,ok,why] = readProjectFile(obj.File);
            obj.LoadedStamp = fileStamp(obj.File);
            if ~ok
                obj.ReadOnly = true;
                obj.Warnings(end+1,1) = "project.mat could not be read (" + why + ")";
                return
            end
            fv = double(getf(D,'FormatVersion',1));
            obj.FileFormatVersion = fv;
            if fv > obj.FormatVersion
                obj.ReadOnly = true;
                obj.Warnings(end+1,1) = sprintf(['project.mat was written by a newer MABR (format %g; ' ...
                    'this one writes %d): opened read-only'],fv,obj.FormatVersion);
            end
            obj.loadStruct(D);
            obj.LoadedRevision = obj.Revision;
            obj.LoadedColumns  = obj.Columns.Name;
            obj.LoadedPools    = obj.Pools.Key;
        end

        function atomicSave(ffn,varName,S)
            % Write a MAT-file so that no reader ever sees half of it.
            %
            %   Project.atomicSave(ffn,varName,S)
            %
            %   ffn      destination (its folder is created)
            %   varName  the one variable to write, holding S; "" writes S's
            %            fields as variables (a results file)
            %   S        the struct
            %
            %   Saved to <ffn>.tmp-<pid>.mat and moved onto ffn, three tries
            %   0.25 s apart; on failure the .tmp is kept and
            %   mabr:analysis:Project:saveFailed names it.
            arguments
                ffn (1,1) string
                varName (1,1) string
                S struct
            end
            d = fileparts(char(ffn));
            if ~isempty(d) && ~isfolder(d), mkdir(d); end
            tmp = ffn + ".tmp-" + feature('getpid') + ".mat";
            if varName == ""
                save(char(tmp),'-struct','S','-v7');
            else
                W = struct();
                W.(char(varName)) = S;
                save(char(tmp),'-struct','W','-v7');
            end
            ok = false;  msg = '';
            for attempt = 1:3
                [ok,msg] = movefile(char(tmp),char(ffn),'f');
                if ok, break; end
                pause(0.25);
            end
            if ~ok
                error('mabr:analysis:Project:saveFailed', ...
                    'Could not move %s onto %s (%s). The file is kept as %s.',tmp,ffn,msg,tmp);
            end
        end

        function fp = fingerprintFor(catalog,keys,exclude)
            % The data fingerprint a Session over these folders would have.
            %
            %   fp = Project.fingerprintFor(catalog,keys,exclude)
            %
            %   Session.fingerprintOf over every Files row of the folder keys,
            %   with exclude the FileIds the results excluded.
            arguments
                catalog (1,1) mabr.analysis.Catalog
                keys string
                exclude string = strings(0,1)
            end
            F = catalog.Files(ismember(catalog.Files.SessionKey,reshape(keys,[],1)),:);
            fp = mabr.analysis.Session.fingerprintOf(F.FileId,F.Bytes,F.Modified,reshape(exclude,[],1));
        end
    end

    methods (Access = private)
        % =================================================================
        %  Loading and merging
        % =================================================================
        function loadStruct(obj,D)
            % Fill the project from a project.mat struct, forgivingly.
            obj.Revision = double(getf(D,'Revision',0));
            obj.AnalysisRoot = string(getf(D,'AnalysisRoot',""));
            C = getf(D,'Columns',[]);
            if istable(C), obj.Columns = conformColumns(C); end
            obj.Subjects = conformTable(getf(D,'Subjects',[]),emptySubjects(),obj.Columns,"subject");
            obj.Sessions = conformTable(getf(D,'Sessions',[]),emptySessions(),obj.Columns,"session");
            P = getf(D,'Pools',[]);
            if istable(P), obj.Pools = conformTable(P,emptyPools(),[],""); end
            s = getf(D,'Settings',[]);
            if isstruct(s) && ~isempty(s)
                try
                    obj.Settings = mabr.analysis.Settings.fromStruct(s);
                catch ME
                    obj.Warnings(end+1,1) = "the project's settings could not be read (" + ME.message + ")";
                end
            elseif isa(s,'mabr.analysis.Settings')
                obj.Settings = s;
            end
            try
                obj.DuplicatePolicy = checkPolicy(string(getf(D,'DuplicatePolicy',"most-sweeps")));
            catch
                obj.Warnings(end+1,1) = "unknown DuplicatePolicy; using most-sweeps";
            end
            obj.ReferenceTimepoint = string(getf(D,'ReferenceTimepoint',""));
            q = getf(D,'ReviewQueue',[]);
            if isstruct(q) && isscalar(q)
                d = obj.ReviewQueue;
                for f = string(fieldnames(d)).'
                    if isfield(q,f), d.(f) = q.(f); end
                end
                d.Keys = reshape(string(d.Keys),[],1);
                obj.ReviewQueue = d;
            end
            obj.ImportedStores = reshape(string(getf(D,'ImportedStores',strings(0,1))),[],1);
            obj.IgnoredStores  = reshape(string(getf(D,'IgnoredStores',strings(0,1))),[],1);
        end

        function mergeFrom(obj,D)
            % Merge the file's project D into this one (§13.6).
            Dp = mabr.analysis.Project(obj.ResultsFolder);
            Dp.loadStruct(D);

            % Columns as a whole field: the file's when this side did not
            % change them (so the other writer's removals and renames stand),
            % else a union by name -- this side's definitions -- less what
            % this side removed and what the other side removed since this
            % side loaded. Levels are united either way.
            C = obj.Columns;
            Cd = Dp.Columns;
            if ~ismember("Columns",obj.Changed)
                lvMine = C;
                C = Cd;
                for r = 1:height(C)
                    i = find(lvMine.Name == C.Name(r),1);
                    if ~isempty(i), C.Levels{r} = unionStable(C.Levels{r},lvMine.Levels{i}); end
                end
            else
                gone = ~C.Builtin & ismember(C.Name,obj.LoadedColumns) & ~ismember(C.Name,Cd.Name);
                C(gone,:) = [];
                for r = 1:height(Cd)
                    nm = Cd.Name(r);
                    if ismember(nm,obj.RemovedColumns), continue; end
                    i = find(C.Name == nm,1);
                    if isempty(i)
                        C = [C; Cd(r,:)]; %#ok<AGROW>
                    else
                        C.Levels{i} = unionStable(C.Levels{i},Cd.Levels{r});
                    end
                end
            end
            obj.Columns = C;

            % Rows: union by key, the later Modified winning.
            mine  = conformTable(obj.Subjects,emptySubjects(),C,"subject");
            other = conformTable(Dp.Subjects,emptySubjects(),C,"subject");
            obj.Subjects = sortSubjects(mergeRows(mine,other,"Subject"));
            mine  = conformTable(obj.Sessions,emptySessions(),C,"session");
            other = conformTable(Dp.Sessions,emptySessions(),C,"session");
            obj.Sessions = mergeRows(mine,other,"Key");

            % Pools as a whole field too: the file's when this side did not
            % change them, else a union in which either side's removals
            % stand. A pool the other writer dissolved must not come back
            % here, or it and its members (whose InStudy the dissolving
            % restored) would both be in the study.
            if ~ismember("Pools",obj.Changed)
                P = Dp.Pools;
            else
                P = obj.Pools;
                P(ismember(P.Key,obj.LoadedPools) & ~ismember(P.Key,Dp.Pools.Key),:) = [];
                for r = 1:height(Dp.Pools)
                    k = Dp.Pools.Key(r);
                    if ismember(k,obj.RemovedPools) || any(P.Key == k), continue; end
                    P = [P; Dp.Pools(r,:)]; %#ok<AGROW>
                end
            end
            obj.Pools = P;
            pk = obj.Sessions.Key(startsWith(obj.Sessions.Key,"pool:"));
            obj.Sessions(ismember(obj.Sessions.Key,pk(~ismember(pk,P.Key))),:) = [];

            % Whole fields: this side's when it changed them, else the file's.
            for f = ["Settings" "DuplicatePolicy" "ReferenceTimepoint" "ReviewQueue"]
                if ~ismember(f,obj.Changed), obj.(f) = Dp.(f); end
            end
            obj.ImportedStores = unique([obj.ImportedStores; Dp.ImportedStores],'stable');
            obj.IgnoredStores  = unique([obj.IgnoredStores; Dp.IgnoredStores],'stable');
            if obj.AnalysisRoot == "", obj.AnalysisRoot = Dp.AnalysisRoot; end
        end

        function notes = mergeImported(obj,D,rekey)
            % Labels from an imported store's project: rows this project
            % never edited take them; edited rows keep theirs (listed).
            notes = strings(0,1);
            Dp = mabr.analysis.Project("");
            Dp.loadStruct(D);
            % Its free columns join ours (same name: ours stands).
            for r = 1:height(Dp.Columns)
                c = Dp.Columns(r,:);
                if c.Builtin || any(lower(obj.Columns.Name) == lower(c.Name)), continue; end
                if ismember(c.Name,[obj.SessionBuiltins obj.SubjectBuiltins]), continue; end
                try
                    obj.addColumn(c.Name,c.Level,c.Type);
                catch ME
                    % A name this project reserves: its values stay behind.
                    notes(end+1,1) = "the column " + c.Name + " was not imported (" + ME.message + ")"; %#ok<AGROW>
                    continue
                end
                obj.Columns.Levels{end} = c.Levels{1};
            end
            Ses = conformTable(Dp.Sessions,emptySessions(),obj.Columns,"session");
            Sub = conformTable(Dp.Subjects,emptySubjects(),obj.Columns,"subject");
            % Pools are not carried over: their keys hash their members' keys,
            % which change here; pool the sessions again to re-create one.
            Ses = Ses(~startsWith(Ses.Key,"pool:"),:);
            Ses.Key = rekey(Ses.Key);
            [notes1,obj.Sessions] = importRows(obj.Sessions,Ses,"Key");
            [notes2,obj.Subjects] = importRows(obj.Subjects,Sub,"Subject");
            obj.Subjects = sortSubjects(obj.Subjects);
            obj.extendLevels("Timepoint",Ses.Timepoint,Ses.Day);
            notes = [notes; notes1; notes2];
        end

        % =================================================================
        %  Rows and columns
        % =================================================================
        function N = proposedRows(obj,catalog)
            % The Sessions rows ensureSessions would add.
            Cs = catalog.Sessions;
            new = find(~ismember(Cs.Key,obj.Sessions.Key));
            N = emptySessions();
            N = conformTable(N,emptySessions(),obj.Columns,"session");
            if isempty(new), return; end
            % Earliest first, so the first session of a day names the visit.
            st = posixtime(Cs.Start(new));  st(isnan(st)) = Inf;
            [~,o] = sort(st);
            new = new(o);
            known = obj.Sessions;
            for i = reshape(new,1,[])
                c = Cs(i,:);
                tp = "";
                if ~isnat(c.Day)
                    pool = [known; N];
                    same = effectiveSubject(pool) == c.Subject & pool.Day == c.Day & ...
                        pool.Timepoint ~= "" & ~startsWith(pool.Key,"pool:");
                    if any(same), tp = pool.Timepoint(find(same,1)); end
                end
                if tp == ""
                    tp = c.InferredLabel;
                    % A label that is only the day says nothing the Day column
                    % does not: the animal's visits are numbered instead.
                    if ~isnat(c.Day) && tp == string(c.Day,'yyyy-MM-dd')
                        tp = visitLabel(c,Cs,[known; N]);
                    end
                end
                R = blankSessionRow(N);
                R.Key = c.Key;
                R.Subject = c.Subject;
                R.Timepoint = tp;
                R.Day = c.Day;
                if c.TestMode == "all"
                    R.InStudy = false;
                    R.ExcludeReason = "Test Mode";
                end
                N = [N; R]; %#ok<AGROW>
            end
            % Back to catalog order.
            [~,o] = ismember(Cs.Key,N.Key);
            N = N(o(o > 0),:);
        end

        function addSubjectRows(obj,subj)
            % Subjects rows for animals not seen before (Modified NaT).
            subj = reshape(string(subj),[],1);
            subj = subj(subj ~= "" & ~ismissing(subj) & ~ismember(subj,obj.Subjects.Subject));
            if isempty(subj), return; end
            for s = reshape(subj,1,[])
                R = blankSubjectRow(obj.Subjects);
                R.Subject = s;
                obj.Subjects = [obj.Subjects; R];
            end
            obj.Subjects = sortSubjects(obj.Subjects);
        end

        function extendLevels(obj,name,values,days)
            % Values not yet in a column's Levels join it, by median date.
            r = find(obj.Columns.Name == name,1);
            if isempty(r), return; end
            values = reshape(string(values),[],1);
            if isscalar(days) && numel(values) > 1, days = repmat(days,numel(values),1); end
            days = reshape(days,[],1);
            lv = obj.Columns.Levels{r};
            ok = values ~= "" & ~ismissing(values) & ~ismember(lower(values),lower(lv));
            if ~any(ok), return; end
            u = unique(values(ok),'stable');
            med = Inf(numel(u),1);
            for k = 1:numel(u)
                d = days(values == u(k));
                d = d(~isnat(d));
                if ~isempty(d), med(k) = median(posixtime(d)); end
            end
            [~,o] = sortrows([med (1:numel(u))']);
            obj.Columns.Levels{r} = [lv; u(o)];
        end

        function [name,level,type] = columnInfo(obj,name)
            % A column's canonical name, level and type (case-insensitive).
            sess = ["Timepoint" "InStudy" "Hidden" "ExcludeReason" "Comment" "SubjectOverride" ...
                "TimeOffsetOverride" "ConductionDelayOverride" "InputFullScaleOverride" ...
                "AmplifierGainOverride"];
            stypes = ["text" "logical" "logical" "text" "text" "text" "number" "number" "number" "number"];
            i = find(strcmpi(sess,name),1);
            if ~isempty(i)
                name = sess(i);  level = "session";  type = stypes(i);
                return
            end
            i = find(strcmpi(obj.Columns.Name,name),1);
            if isempty(i)
                error('mabr:analysis:Project:unknownColumn','The project has no label column "%s".',name);
            end
            name = obj.Columns.Name(i);
            level = obj.Columns.Level(i);
            type = obj.Columns.Type(i);
        end

        function r = freeColumnRow(obj,name)
            r = find(strcmpi(obj.Columns.Name,name),1);
            if isempty(r)
                error('mabr:analysis:Project:unknownColumn','The project has no column "%s".',name);
            end
            if obj.Columns.Builtin(r)
                error('mabr:analysis:Project:builtinColumn','"%s" is a built-in column.',obj.Columns.Name(r));
            end
        end

        function checkNewName(obj,name)
            if name == "" || ismissing(name)
                error('mabr:analysis:Project:badColumn','A column needs a name.');
            end
            taken = [obj.SessionBuiltins obj.SubjectBuiltins reshape(obj.Columns.Name,1,[]) ...
                "Key" "Members" "IsPool" "PoolKey" "Status" "StatusText" "Reviewed" "NumSeries" ...
                "SettingsHash" "Processing" "UsedInStudy" "TimepointOrder" "DaysFromReference" ...
                "SubjectInStudy" "Session" string(mabr.analysis.Catalog.SessionColumns)];
            if any(strcmpi(taken,name))
                error('mabr:analysis:Project:columnExists','There is already a column "%s".',name);
            end
        end

        function [v,note] = coerce(obj,name,level,type,value)
            % A label value as the column stores it.
            note = "";
            switch type
                case "logical"
                    v = toLogical(value,name);
                case "number"
                    v = toNumber(value,name);
                    if name == "ConductionDelayOverride" && v < 0
                        error('mabr:analysis:Project:badValue','A conduction delay is not negative (%g ms).',v);
                    end
                    if ismember(name,["InputFullScaleOverride" "AmplifierGainOverride"]) && ~(v > 0) && ~isnan(v)
                        error('mabr:analysis:Project:badValue','%s must be positive (or NaN for none).',name);
                    end
                otherwise
                    if isstring(value) || ischar(value) || iscellstr(value)
                        v = string(value);
                    elseif isnumeric(value) && isscalar(value)
                        v = string(value);
                    else
                        error('mabr:analysis:Project:badValue','"%s" takes text.',name);
                    end
                    if ~isscalar(v), error('mabr:analysis:Project:badValue','"%s" takes one value.',name); end
                    if ismissing(v), v = ""; end
                    raw = v;
                    v = strtrim(v);
                    if name == "SubjectOverride"
                        if v ~= ""
                            v = mabr.analysis.AbrFile.canonicalSubject(v);
                            if v ~= raw, note = sprintf('"%s" was taken as "%s".',raw,v); end
                        end
                        return
                    end
                    if v == "" || ismember(name,["Comment" "ExcludeReason"]), return; end
                    % A level differing only by case or spacing is that level.
                    r = find(obj.Columns.Name == name,1);
                    lv = strings(0,1);
                    if ~isempty(r), lv = obj.Columns.Levels{r}; end
                    if level == "subject", used = obj.Subjects.(name); else, used = obj.Sessions.(name); end
                    cand = unique([lv; reshape(used(used ~= ""),[],1)],'stable');
                    hit = find(normText(cand) == normText(v),1);
                    if ~isempty(hit) && cand(hit) ~= v
                        note = sprintf('"%s" was taken as the existing "%s".',raw,cand(hit));
                        v = cand(hit);
                    elseif v ~= raw
                        note = sprintf('"%s" was trimmed to "%s".',raw,v);
                    end
            end
        end

        function s = subjectKey(obj,key)
            % The Subjects row a subject key names ("" if none), any spelling.
            s = "";
            if any(obj.Subjects.Subject == key), s = key; return; end
            c = mabr.analysis.AbrFile.canonicalSubject(key);
            if c ~= "" && any(obj.Subjects.Subject == c), s = c; end
        end

        function touch(obj,part)
            obj.Changed = unique([obj.Changed part],'stable');
            obj.Dirty = true;
        end

        % =================================================================
        %  Views
        % =================================================================
        function B = baseView(obj,catalog)
            % Catalog.Sessions (+ pools) joined with the labels: no results.
            Cs = catalog.Sessions;
            S = [obj.Sessions; obj.proposedRows(catalog)];
            P = obj.Pools;
            % Pool rows, from their members' catalog rows.
            for r = 1:height(P)
                m = split(P.Members(r),"|");
                [tf,loc] = ismember(m,Cs.Key);
                if ~any(tf), continue; end
                M = Cs(loc(tf),:);
                R = M(1,:);
                R.Key = P.Key(r);
                R.Name = P.Name(r);
                R.Day = min(M.Day);  R.Start = min(M.Start);  R.Stop = max(M.Stop);
                R.NumFiles = sum(M.NumFiles);  R.NumIncluded = sum(M.NumIncluded);
                R.NumSweeps = sum(M.NumSweeps);  R.NumConditions = max(M.NumConditions);
                R.Stimuli = joinUnique(M.Stimuli);
                R.Summary = string(sprintf('Pool of %d sessions',height(M)));
                R.AcqModes = joinUnique(M.AcqModes);
                R.HasCompact = any(M.HasCompact);
                R.ShortRuns = sum(M.ShortRuns);
                R.TestMode = "some";
                if all(M.TestMode == "none"), R.TestMode = "none"; end
                if all(M.TestMode == "all"), R.TestMode = "all"; end
                R.Units = oneOrMixed(M.Units);  R.LevelUnit = oneOrMixed(M.LevelUnit);
                R.NotesFile = "";
                R.ResultsFile = catalog.resultsFile(m(tf));
                R.HasResults = isfile(R.ResultsFile);
                Cs = [Cs; R]; %#ok<AGROW>
            end
            n = height(Cs);
            B = Cs;
            B.IsPool = startsWith(B.Key,"pool:");
            B.Members = B.Key;
            B.PoolKey = strings(n,1);
            for r = 1:height(P)
                m = split(P.Members(r),"|");
                B.Members(B.Key == P.Key(r)) = P.Members(r);
                B.PoolKey(ismember(B.Key,m)) = P.Key(r);
            end
            [tf,loc] = ismember(B.Key,S.Key);
            if ~all(tf)
                % A pool whose Sessions row is gone: in the study by default.
                extra = blankSessionRow(S);
                for i = find(~tf).'
                    R = extra;  R.Key = B.Key(i);  R.Subject = B.Subject(i);
                    S = [S; R]; %#ok<AGROW>
                end
                [~,loc] = ismember(B.Key,S.Key);
            end
            L = S(loc,:);
            B.SubjectCatalog = B.Subject;
            B.SubjectOverride = L.SubjectOverride;
            eff = effectiveSubject(L);
            eff(eff == "") = B.Subject(eff == "");
            B.Subject = eff;
            for c = ["Timepoint" "InStudy" "Hidden" "ExcludeReason" "Comment" "TimeOffsetOverride" ...
                    "ConductionDelayOverride" "InputFullScaleOverride" "AmplifierGainOverride" ...
                    "LastRun" "LastError" "Modified"]
                B.(c) = L.(c);
            end
            % A hidden session is out of the study whatever its own label
            % says: every reader of InStudy below (aggregate, resolveUse,
            % exportItems, the Study tab) then leaves it out.
            B.InStudy = B.InStudy & ~B.Hidden;
            free = obj.Columns.Name(obj.Columns.Level == "session" & ~obj.Columns.Builtin);
            for c = reshape(free,1,[]), B.(c) = L.(c); end
            % The animal's labels.
            [ts,ls] = ismember(B.Subject,obj.Subjects.Subject);
            B.Group = strings(n,1);  B.SubjectInStudy = true(n,1);
            B.Group(ts) = obj.Subjects.Group(ls(ts));
            B.SubjectInStudy(ts) = obj.Subjects.InStudy(ls(ts));
            sfree = obj.Columns.Name(obj.Columns.Level == "subject" & ~obj.Columns.Builtin);
            for c = reshape(sfree,1,[])
                col = obj.Subjects.(c);
                if isnumeric(col), v = NaN(n,1); else, v = strings(n,1); end
                v(ts) = col(ls(ts));
                B.(c) = v;
            end
            % Visit order and days from the reference visit.
            lv = obj.Columns.Levels{obj.Columns.Name == "Timepoint"};
            [~,ord] = ismember(lower(B.Timepoint),lower(lv));
            ord = double(ord);  ord(ord == 0) = NaN;
            B.TimepointOrder = ord;
            ref = obj.ReferenceTimepoint;
            if ref == "" && ~isempty(lv), ref = lv(1); end
            dfr = NaN(n,1);
            for s = reshape(unique(B.Subject),1,[])
                rows = B.Subject == s;
                d0 = B.Day(rows & B.Timepoint == ref & ~B.IsPool);
                d0 = d0(~isnat(d0));
                if isempty(d0), continue; end
                dfr(rows) = days(B.Day(rows) - min(d0));
            end
            B.DaysFromReference = dfr;
            % Results files for every row (pools already have theirs).
            for i = find(~B.IsPool).'
                B.ResultsFile(i) = catalog.resultsFile(B.Key(i));
            end
        end

        function R = tryResults(obj,key,catalog,file,vars)
            % results(), with a file that cannot be read treated as absent
            % (view() reports it as failed; a study table leaves it out).
            try
                R = obj.results(key,Catalog=catalog,File=file,Vars=vars);
            catch
                R = [];
            end
        end

        function v = memo(obj,file,R,name,need,key,fcn,varargin)
            % fcn(args...) remembered with file's entry in the results cache.
            %
            %   v = memo(file,R,name,need,key,fcn,args...)
            %
            %   file  the results file R was read from by results()
            %   R     what results() returned for it
            %   name  what is remembered (one value per name and file)
            %   need  the variables of R that fcn reads: whether R holds each
            %         is part of what the value is remembered under, so a
            %         call that read fewer variables never gets a value made
            %         from more (or the reverse)
            %   key   everything else the value depends on (labels, study
            %         use), [] = nothing; compared with isequaln
            %   fcn   a function of args (R, or what was derived from R, and
            %         key's values) -- a plain handle, not a closure, so that
            %         nothing is captured on the way in
            %   v  (returned) the remembered value when name was computed for
            %      the same file stamp, the same variables and an equal key;
            %      else fcn(args...), remembered
            %
            % The value lives in the cache entry results() replaces when the
            % file's stamp (bytes, modification time) changes, so a results
            % file that is rewritten is derived again and nothing else is.
            % Plain values only (tables, structs, strings): what is handed
            % back is a copy, so a caller cannot change what is remembered.
            ck = lower(char(file));
            have = isstruct(R) && ~isempty(obj.Cache) && isKey(obj.Cache,ck);
            if have
                E = obj.Cache(ck);
                sig = {isfield(R,cellstr(need)),key};
                if isfield(E,'Derived') && isfield(E.Derived,name) && ...
                        isequaln(E.Derived.(name).Sig,sig)
                    v = E.Derived.(name).Value;
                    return
                end
            end
            v = fcn(varargin{:});
            if have
                E = obj.Cache(ck);
                E.Derived.(name) = struct('Sig',{sig},'Value',{v});
                obj.Cache(ck) = E;
            end
        end

        function [st,txt] = statusOf(obj,R,f,row,catalog,settings) %#ok<INUSL>
            % One results file against the settings and the files.
            st = "current";
            stamp = "";
            SS = getf(R,'StepState',struct());
            steps = ["segment","reject","detect","measure","thresholds","peaks"];
            setChanged = false;
            if isstruct(SS) && isscalar(SS)
                for k = steps
                    if ~isfield(SS,k) || isempty(SS.(k))
                        % Not run (or invalidated): not current for that
                        % step (10 §10.3), as Session.staleness reads it.
                        if ~isempty(settings), setChanged = true; end
                        continue
                    end
                    s = SS.(k);
                    if isfield(s,'At') && string(s.At) > stamp, stamp = string(s.At); end
                    if ~isempty(settings)
                        if ~isfield(s,'Settings') || ~isequaln(s.Settings,settings.stepSettings(k))
                            setChanged = true;
                        end
                    end
                end
            end
            S = getf(R,'Summary',struct());
            fileChanged = false;
            fp = string(getf(S,'DataFingerprint',""));
            if fp ~= "" && ~ismissing(fp)
                ex = reshape(string(getf(S,'Exclude',strings(0,1))),[],1);
                mem = split(row.Members,"|");
                now_ = mabr.analysis.Project.fingerprintFor(catalog,mem,ex);
                fileChanged = now_ ~= fp;
            end
            if ~isstruct(SS) && ~isempty(settings), setChanged = true; end
            % The per-session overrides are neither step settings nor part of
            % the fingerprint; results made under others are out of date
            % (mabr.analysis.Batch re-runs them for the same reason).
            if ~setChanged && ~fileChanged && overridesChanged(row,S)
                st = "stale";  txt = "Out of date (overrides changed)";
                return
            end
            if setChanged && fileChanged
                st = "stale";  txt = "Out of date (settings and files changed)";
            elseif setChanged
                st = "stale";  txt = "Out of date (settings changed)";
            elseif fileChanged
                st = "stale";  txt = "Out of date (files changed)";
            else
                when = NaT;
                if stamp ~= ""
                    try
                        when = datetime(stamp,'InputFormat','yyyy-MM-dd''T''HH:mm:ss');
                    catch
                    end
                end
                if isnat(when), when = fileTime(f); end
                txt = "Up to date (" + string(when,'yyyy-MM-dd HH:mm') + ")";
            end
        end

        function [U,D] = resolveUse(obj,B,Rs,policy)
            % Which series of which session the study uses (§13.4).
            %
            %   U  cell, per row of B: struct SeriesKey (string column) and
            %      Used (logical column) over the results' Thresholds rows
            %   D  table Subject, Timepoint, SeriesKey, Keys, Used for every
            %      unit more than one in-study session provided
            n = height(B);
            U = cell(n,1);
            uk = strings(0,1);  ui = zeros(0,1);  us = strings(0,1);
            score = zeros(0,1);  start = zeros(0,1);
            files = B.ResultsFile;
            elig = B.InStudy & B.SubjectInStudy & B.TestMode ~= "all";
            for i = 1:n
                U{i} = struct('SeriesKey',strings(0,1),'Used',false(0,1));
                R = Rs{i};
                if isempty(R), continue; end
                T = tableOr(R,'Thresholds');
                if height(T) == 0 || ~ismember('Key',T.Properties.VariableNames), continue; end
                sk = string(T.Key);
                eligible = elig(i);
                U{i} = struct('SeriesKey',sk,'Used',repmat(eligible,numel(sk),1));
                if ~eligible, continue; end
                % The series' median clean sweeps, remembered with the file.
                sc = obj.memo(files(i),R,"sweeps",["Thresholds" "Conditions" "Summary"],[], ...
                    @seriesSweepsOf,R);
                t0 = posixtime(B.Start(i));  if isnan(t0), t0 = -Inf; end
                unit = B.Subject(i) + "|" + B.Timepoint(i) + "|" + sk;
                uk = [uk; unit]; ui = [ui; repmat(i,numel(sk),1)]; us = [us; sk]; %#ok<AGROW>
                score = [score; sc]; start = [start; repmat(t0,numel(sk),1)]; %#ok<AGROW>
            end
            D = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
                'VariableNames',{'Subject','Timepoint','SeriesKey','Keys','Used'});
            [g,~,j] = unique(uk);
            for k = 1:numel(g)
                m = find(j == k);
                if numel(m) < 2, continue; end
                switch policy
                    case "mean"
                        win = m;
                    case "latest"
                        [~,o] = sortrows([start(m) score(m)],[-1 -2]);
                        win = m(o(1));
                    otherwise
                        sm = score(m);  sm(isnan(sm)) = -Inf;
                        [~,o] = sortrows([sm start(m)],[-1 -2]);
                        win = m(o(1));
                end
                for q = reshape(m,1,[])
                    if ~ismember(q,win)
                        r = ui(q);
                        U{r}.Used(U{r}.SeriesKey == us(q)) = false;
                    end
                end
                D = [D; table(B.Subject(ui(m(1))),B.Timepoint(ui(m(1))),us(m(1)), ...
                    join(B.Key(ui(m)),"|"),join(B.Key(ui(win)),"|"),'VariableNames', ...
                    {'Subject','Timepoint','SeriesKey','Keys','Used'})]; %#ok<AGROW>
            end
        end

        function T = studySessions(obj,B,Rs,pr)
            % The study's Sessions table: one row per key with results (pr:
            % each one's Processing, as studyParts found it).
            n = height(B);
            sh = strings(n,1);  at = strings(n,1);  fp = strings(n,1);
            for i = 1:n
                Pv = getf(Rs{i},'Provenance',struct());
                sh(i) = string(getf(Pv,'SettingsHash',""));
                at(i) = string(getf(Pv,'AnalyzedAt',""));
                fp(i) = string(getf(getf(Rs{i},'Summary',struct()),'DataFingerprint',""));
            end
            T = table(B.Key,B.Subject,B.SubjectCatalog,B.Timepoint,B.TimepointOrder,B.Group, ...
                B.InStudy & B.SubjectInStudy,B.TestMode,B.Day,B.Start,B.DaysFromReference, ...
                B.NumFiles,B.NumConditions,B.NumSweeps,B.Stimuli,B.AcqModes,pr,B.Units, ...
                B.LevelUnit,sh,at,fp,B.Comment,B.TimeOffsetOverride,B.ConductionDelayOverride, ...
                'VariableNames',{'Session','Subject','SubjectRaw','Timepoint','TimepointOrder', ...
                'Group','InStudy','TestMode','Day','Start','DaysFromReference','NumFiles', ...
                'NumConditions','NumSweeps','Stimuli','AcqModes','Processing','Units', ...
                'LevelUnit','SettingsHash','AnalyzedAt','DataFingerprint','Comment', ...
                'TimeOffsetOverride','ConductionDelayOverride'});
            free = obj.Columns.Name(obj.Columns.Level == "session" & ~obj.Columns.Builtin);
            for c = reshape(free,1,[]), T.(c) = B.(c); end
        end

        function Nt = notesOf(obj,row,catalog) %#ok<INUSL>
            % Catalog.notes of a session, or of a pool's members together.
            Nt = [];
            m = split(row.Members,"|");
            parts = {};
            for k = reshape(m,1,[])
                if ~any(catalog.Sessions.Key == k), continue; end
                try
                    parts{end+1} = catalog.notes(k); %#ok<AGROW>
                catch
                end
            end
            if isempty(parts), return; end
            Nt = vertcat(parts{:});
        end

        function f = resultsFileOf(obj,key,catalog)
            % Where key's results are: the catalog's rule, else the project's.
            if ~isempty(catalog)
                f = catalog.resultsFile(obj.poolMembers(key));
                return
            end
            rf = char(obj.ResultsFolder);
            m = obj.poolMembers(key);
            if isscalar(m) && m ~= "."
                f = string(fullfile(rf,[char(strrep(m,"/",filesep)) '.mat']));
            elseif isscalar(m)
                [~,nm] = fileparts(char(obj.AnalysisRoot));
                f = string(fullfile(rf,[nm '.mat']));
            else
                m = sort(m);
                r = find(obj.Sessions.Key == m(1),1);
                subj = "(unknown subject)";
                if ~isempty(r), subj = effectiveSubject(obj.Sessions(r,:)); end
                parts = split(m(1),"/");
                f = string(fullfile(rf,char(subj),'pooled', ...
                    char(parts(end) + "+" + (numel(m) - 1) + "_" + mabr.analysis.Stats.hex8(join(m,"|")) + ".mat")));
            end
        end
    end
end

% =========================================================================
%  Tables
% =========================================================================
function T = emptySubjects()
s = strings(0,1);
T = table(s,s,false(0,1),s,NaT(0,1),'VariableNames',{'Subject','Group','InStudy','Comment','Modified'});
end

function T = emptySessions()
s = strings(0,1);  x = zeros(0,1);  t = NaT(0,1);  b = false(0,1);
T = table(s,s,s,s,b,b,s,s,x,x,x,x,t,s,t,t,'VariableNames', ...
    cellstr(mabr.analysis.Project.SessionBuiltins));
end

function T = emptyPools()
s = strings(0,1);
T = table(s,s,s,NaT(0,1),s,'VariableNames',{'Key','Name','Members','Created','PreviousInStudy'});
end

function T = builtinColumns()
T = [columnRow("Timepoint","session","text",strings(0,1),true)
     columnRow("Group","subject","text",strings(0,1),true)];
end

function T = columnRow(name,level,type,levels,builtin)
T = table(string(name),string(level),string(type),{reshape(string(levels),[],1)},logical(builtin), ...
    'VariableNames',{'Name','Level','Type','Levels','Builtin'});
end

function C = conformColumns(C)
% A Columns table from a file: every field, both built-ins present.
B = builtinColumns();
out = B([],:);
if ~all(ismember({'Name','Level','Type'},C.Properties.VariableNames)), C = B; end
for r = 1:height(C)
    nm = string(C.Name(r));  lv = string(C.Level(r));  ty = string(C.Type(r));
    if ~ismember(lv,["subject" "session"]) || ~ismember(ty,["text" "number"]), continue; end
    levels = strings(0,1);
    if ismember('Levels',C.Properties.VariableNames)
        x = C.Levels(r);
        if iscell(x), x = x{1}; end
        if ~isempty(x), levels = reshape(string(x),[],1); end
    end
    bi = ismember(nm,["Timepoint" "Group"]);
    % (a free column named like a built-in one added since -- "Hidden" --
    % gives way to it: two columns of one name cannot be a table)
    if ~bi && any(strcmpi(nm,[mabr.analysis.Project.SessionBuiltins mabr.analysis.Project.SubjectBuiltins]))
        continue
    end
    out = [out; columnRow(nm,lv,ty,levels,bi)]; %#ok<AGROW>
end
for b = ["Timepoint" "Group"]
    if ~any(out.Name == b), out = [out; B(B.Name == b,:)]; end %#ok<AGROW>
end
C = out;
end

function T = conformTable(T,base,cols,level)
% T with exactly base's columns (types as base's) plus the free columns of
% that level in cols; missing ones defaulted, extra ones dropped.
if ~istable(T), T = base; end
n = height(T);
names = string(base.Properties.VariableNames);
protos = cell(1,numel(names));
for j = 1:numel(names), protos{j} = base.(names(j)); end
if ~isempty(cols) && level ~= ""
    for r = find(cols.Level == level & ~cols.Builtin).'
        names(end+1) = cols.Name(r); %#ok<AGROW>
        if cols.Type(r) == "number", protos{end+1} = zeros(0,1); else, protos{end+1} = strings(0,1); end %#ok<AGROW>
    end
end
data = cell(1,numel(names));
for j = 1:numel(names)
    if ismember(names(j),T.Properties.VariableNames)
        data{j} = castLike(T.(names(j)),protos{j},n,names(j));
    else
        data{j} = defaultCol(protos{j},n,names(j));
    end
end
T = table(data{:},'VariableNames',cellstr(names));
end

function x = castLike(x,proto,n,name)
% Column x (named name) as proto's type, n rows.
try
    if isstring(proto)
        x = string(x);  x(ismissing(x)) = "";
    elseif islogical(proto)
        x = logical(x);
    elseif isdatetime(proto)
        if ~isdatetime(x), x = NaT(n,1); end
    elseif isnumeric(proto)
        x = double(x);
    end
    x = reshape(x,n,[]);
    if size(x,2) ~= 1, x = defaultCol(proto,n,name); end
catch
    x = defaultCol(proto,n,name);
end
end

function x = defaultCol(proto,n,name)
% A column's default: "", NaN, NaT, {} -- and true for a logical (InStudy),
% but false for one of OffByDefault (Hidden), so a row from before such a
% column, or a new one, is not hidden.
if nargin < 3, name = ""; end
if isstring(proto), x = strings(n,1);
elseif islogical(proto), x = true(n,1) & ~any(string(name) == mabr.analysis.Project.OffByDefault);
elseif isdatetime(proto), x = NaT(n,1);
elseif iscell(proto), x = cell(n,1);
else, x = NaN(n,1);
end
end

function R = blankSessionRow(T)
% One row of T at its defaults: "", NaN, NaT, InStudy true and Hidden false.
s = struct();
for v = string(T.Properties.VariableNames)
    s.(v) = defaultCol(T.(v)([]),1,v);
end
R = struct2table(s,'AsArray',true);
R = R(:,T.Properties.VariableNames);
end

function R = blankSubjectRow(T)
R = blankSessionRow(T);
end

function tp = visitLabel(c,Cs,pool)
% "Session k" for catalog row c, an unlabelled visit: k is the place of its day
% among the animal's days in the catalog (sessions of one day are one visit).
% A number the animal already uses for another day is skipped, so a visit
% added later that falls before the others cannot take a label in use.
own = Cs.Subject == c.Subject & ~startsWith(Cs.Key,"pool:") & ~isnat(Cs.Day);
k = max(1,nnz(unique(Cs.Day(own)) <= c.Day));
taken = pool.Timepoint(effectiveSubject(pool) == c.Subject & pool.Day ~= c.Day & ...
    ~startsWith(pool.Key,"pool:"));
while any(taken == "Session " + k), k = k + 1; end
tp = "Session " + k;
end

function s = effectiveSubject(T)
% A Sessions row's subject: its override when one is set.
s = T.Subject;
o = T.SubjectOverride;
use = o ~= "" & ~ismissing(o);
s(use) = o(use);
end

function T = sortSubjects(T)
if height(T) < 2, return; end
[~,i] = mabr.analysis.Stats.naturalSort(T.Subject);
T = T(i,:);
end

function M = mergeRows(mine,other,keyVar)
% Union by key; for a key in both the row with the later Modified wins
% (NaT is the oldest; a tie keeps mine).
M = mine;
[tf,loc] = ismember(other.(keyVar),mine.(keyVar));
for r = find(tf).'
    a = mine.Modified(loc(r));  b = other.Modified(r);
    if ~isnat(b) && (isnat(a) || b > a)
        M(loc(r),:) = other(r,:);
    end
end
M = [M; other(~tf,:)];
end

function [notes,M] = importRows(M,In,keyVar)
% Imported rows: new keys appended. For a key both have, a row the other
% project never edited (Modified NaT) carries no decision and is passed
% over; an edited one replaces a row never edited here, and meets an edited
% one here as a conflict, this project's row standing (listed if they differ).
notes = strings(0,1);
[tf,loc] = ismember(In.(keyVar),M.(keyVar));
for r = find(tf).'
    j = loc(r);
    if isnat(In.Modified(r)), continue; end
    if isnat(M.Modified(j))
        M(j,:) = In(r,:);
    else
        a = M(j,:);  b = In(r,:);
        a.Modified = NaT;  b.Modified = NaT;
        if keyVar == "Key", a.Day = NaT; b.Day = NaT; end
        if ~isequaln(a,b)
            notes(end+1,1) = "kept this project's labels of " + M.(keyVar)(j) + ...
                " (the imported store's differ)"; %#ok<AGROW>
        end
    end
end
M = [M; In(~tf,:)];
end

function u = unionStable(a,b)
a = reshape(string(a),[],1);  b = reshape(string(b),[],1);
u = [a; b(~ismember(lower(b),lower(a)))];
end

% =========================================================================
%  Values
% =========================================================================
function v = toLogical(value,name)
if islogical(value) && isscalar(value), v = value; return; end
if isnumeric(value) && isscalar(value) && ismember(value,[0 1]), v = value == 1; return; end
if (isstring(value) || ischar(value))
    t = lower(strtrim(string(value)));
    if ismember(t,["true" "yes" "1" "in" "on"]), v = true; return; end
    if ismember(t,["false" "no" "0" "out" "off"]), v = false; return; end
end
error('mabr:analysis:Project:badValue','"%s" takes true or false.',name);
end

function v = toNumber(value,name)
if (isnumeric(value) || islogical(value)) && isscalar(value)
    v = double(value);
elseif (isstring(value) || ischar(value)) && isscalar(string(value))
    t = strtrim(string(value));
    if t == "" || ismissing(t) || lower(t) == "nan"
        v = NaN;
    else
        v = str2double(t);
        if isnan(v)
            error('mabr:analysis:Project:badValue','"%s" is a number column; "%s" is not a number.',name,t);
        end
    end
else
    error('mabr:analysis:Project:badValue','"%s" takes one number.',name);
end
if isinf(v)
    error('mabr:analysis:Project:badValue','"%s" takes a finite number (or NaN for none).',name);
end
end

function t = normText(s)
% Text compared without case or spacing.
t = lower(regexprep(string(s),'\s+',''));
end

function p = checkPolicy(p)
p = lower(strtrim(string(p)));
if ~ismember(p,mabr.analysis.Project.Policies)
    error('mabr:analysis:Project:badPolicy','DuplicatePolicy is one of %s, not "%s".', ...
        strjoin(mabr.analysis.Project.Policies,', '),p);
end
end

function v = getf(s,f,d)
% s.f when s is a struct holding it, else d.
v = d;
if isstruct(s) && isscalar(s) && isfield(s,f)
    v = s.(f);
end
end

function s = joinUnique(v)
v = reshape(string(v),[],1);
parts = strings(0,1);
for k = 1:numel(v)
    parts = [parts; strtrim(split(v(k),","))]; %#ok<AGROW>
end
parts = unique(parts(parts ~= ""));
s = strjoin(parts,", ");
if isempty(parts), s = ""; end
s = string(s);
end

function s = oneOrMixed(v)
u = unique(string(v));
if isscalar(u), s = u; elseif isempty(u), s = ""; else, s = "mixed"; end
end

% =========================================================================
%  Results
% =========================================================================
function T = tableOr(R,name)
T = table();
if isstruct(R) && isfield(R,name) && istable(R.(name)), T = R.(name); end
end

function s = stringCol(T,name)
if ismember(name,T.Properties.VariableNames)
    s = string(T.(name));
else
    s = strings(height(T),1);
end
end

function p = processingOf(C)
p = "";
if ~istable(C) || ~ismember('Processing',C.Properties.VariableNames) || height(C) == 0, return; end
u = unique(string(C.Processing));
u = u(u ~= "" & ~ismissing(u));
p = strjoin(u,", ");
if isempty(u), p = ""; end
p = string(p);
end

function sc = seriesSweeps(T,C,gp)
% Median clean sweeps (nClean, else nSweeps) over each series' conditions.
% gp: the results' Summary.GroupParams -- the columns Session keys a series
% by; without them, the Thresholds columns between Key and LevelParam,
% which is where Session puts the same ones.
sc = NaN(height(T),1);
if height(C) == 0, return; end
v = string(T.Properties.VariableNames);
i0 = find(v == "Key",1);  i1 = find(v == "LevelParam",1);
gc = strings(1,0);
if ~isempty(gp) && (isstring(gp) || iscellstr(gp) || ischar(gp))
    gc = reshape(string(gp),1,[]);
elseif ~isempty(i0) && ~isempty(i1) && i1 > i0 + 1
    gc = v(i0+1:i1-1);
end
gc = gc(ismember(gc,C.Properties.VariableNames));
if ismember('nClean',C.Properties.VariableNames)
    nc = double(C.nClean);
elseif ismember('nSweeps',C.Properties.VariableNames)
    nc = double(C.nSweeps);
else
    return
end
ck = keyText(C,gc);
sk = string(T.Key);
for r = 1:height(T)
    % A series no condition keys to stays NaN (counted as the fewest
    % sweeps) rather than borrowing the whole session's count.
    x = nc(ck == sk(r));
    x = x(isfinite(x));
    if ~isempty(x), sc(r) = median(x); end
end
end

function k = keyText(T,cols)
% "Name=Value" over cols joined by "|", as mabr.analysis.Session keys a
% condition (a numeric NaN -- a parameter the stimulus lacks -- left out).
n = height(T);
cols = reshape(string(cols),1,[]);
if isempty(cols), k = repmat("(all)",n,1); return; end
parts = strings(n,numel(cols));
for j = 1:numel(cols)
    v = T.(cols(j));
    if isnumeric(v) || islogical(v)
        v = double(v(:));
        txt = cols(j) + "=" + mabr.analysis.Stats.keyValue(v);
        txt(isnan(v)) = "";
    else
        txt = cols(j) + "=" + mabr.analysis.Stats.keyValue(string(v(:)));
    end
    parts(:,j) = txt;
end
k = strings(n,1);
for i = 1:n
    p = parts(i,:);
    k(i) = strjoin(p(p ~= ""),"|");
end
end

function tf = overridesChanged(row,S)
% Whether the project's overrides for row differ from those the results
% Summary S was made with (UnitOverride, TimeOffset,
% ConductionDelayOverride; absent or non-finite = none on both sides).
tf = false;
pairs = {'TimeOffsetOverride','TimeOffset'; 'ConductionDelayOverride','ConductionDelayOverride'};
uo = getf(S,'UnitOverride',struct());
for k = 1:size(pairs,1)
    if ~ismember(pairs{k,1},row.Properties.VariableNames), continue; end
    a = double(row.(pairs{k,1})(1));
    b = double(getf(S,pairs{k,2},NaN));
    if isempty(b), b = NaN; end
    if ~isequaln(finiteOrNaN(a),finiteOrNaN(b(1))), tf = true; return; end
end
pairs = {'InputFullScaleOverride','InputFullScale'; 'AmplifierGainOverride','AmplifierGain'};
for k = 1:size(pairs,1)
    if ~ismember(pairs{k,1},row.Properties.VariableNames), continue; end
    a = double(row.(pairs{k,1})(1));
    b = NaN;
    if isstruct(uo) && isfield(uo,pairs{k,2}), b = double(uo.(pairs{k,2})); end
    if isempty(b), b = NaN; end
    if ~isequaln(finiteOrNaN(a),finiteOrNaN(b(1))), tf = true; return; end
end
end

function x = finiteOrNaN(x)
if ~isfinite(x), x = NaN; end
end

function u = usedFor(U,sk)
% UsedInStudy of rows with series keys sk.
u = false(numel(sk),1);
if isempty(U) || isempty(U.SeriesKey), return; end
[tf,loc] = ismember(sk,U.SeriesKey);
u(tf) = U.Used(loc(tf));
end

function T = withLabels(lab,T)
% The label columns in front of a results table (a results column of the
% same name gives way).
n = height(T);
L = table(repmat(lab.Session,n,1),repmat(lab.Subject,n,1),repmat(lab.Timepoint,n,1), ...
    repmat(lab.Group,n,1),'VariableNames',{'Session','Subject','Timepoint','Group'});
if width(T) > 0
    T(:,ismember(T.Properties.VariableNames,L.Properties.VariableNames)) = [];
    T = [L T];
else
    T = L;
end
end

function X = studyParts(R)
% One results file's study tables before labels: Conditions, Thresholds
% without Fit, Peaks, and Peaks.derived's PeakMeasures (M) and IOSlopes (G);
% and its Processing.
X = struct();
X.C = tableOr(R,'Conditions');
Ti = tableOr(R,'Thresholds');
if ismember('Fit',Ti.Properties.VariableNames), Ti.Fit = []; end
X.T = Ti;
X.P = tableOr(R,'Peaks');
[X.M,X.G] = derivedOf(R);
X.Processing = processingOf(X.C);
end

function sc = seriesSweepsOf(R)
% seriesSweeps over one results file's Thresholds and Conditions.
sc = seriesSweeps(tableOr(R,'Thresholds'),tableOr(R,'Conditions'), ...
    getf(getf(R,'Summary',struct()),'GroupParams',[]));
end

function L = labelledParts(X,lab,tpo,U)
% studyParts' tables with the session's labels in front, Thresholds with
% TimepointOrder and UsedInStudy, Peaks (when it has rows) with UsedInStudy.
L = struct();
L.C = withLabels(lab,X.C);
Ti = withLabels(lab,X.T);
Ti.TimepointOrder = repmat(tpo,height(Ti),1);
Ti.UsedInStudy = usedFor(U,stringCol(Ti,'Key'));
L.T = Ti;
Pi = withLabels(lab,X.P);
if height(X.P) > 0
    Pi.UsedInStudy = usedFor(U,stringCol(X.P,'SeriesKey'));
end
L.P = Pi;
L.M = withLabels(lab,X.M);
L.G = withLabels(lab,X.G);
end

function [M,G] = derivedOf(R)
% Peaks.derived over one session's picks, judged against its Finals.
M = table();  G = table();
P = tableOr(R,'Peaks');
if height(P) == 0, return; end
T = tableOr(R,'Thresholds');
fin = [];
if height(T) > 0 && all(ismember({'Key','Final'},T.Properties.VariableNames))
    fin = table(string(T.Key),double(T.Final),'VariableNames',{'SeriesKey','Final'});
    if ismember('FinalCensored',T.Properties.VariableNames), fin.FinalCensored = string(T.FinalCensored); end
    if ismember('FinalLo',T.Properties.VariableNames), fin.FinalLo = double(T.FinalLo); end
    if ismember('FinalHi',T.Properties.VariableNames), fin.FinalHi = double(T.FinalHi); end
    % The level axis, for a Peaks table without BelowThreshold (Peaks.
    % belowFromFinal judges "below" on -level on an attenuation axis): the
    % settings' LevelDirection, else "auto" = a level parameter named like
    % Attenuation -- Session's rule.
    dirn = string(getf(getf(R,'Settings',struct()),'LevelDirection',"auto"));
    if dirn == "auto"
        dirn = "ascending";
        if contains(lower(string(getf(getf(R,'Summary',struct()),'LevelParam',""))),"attenuation")
            dirn = "descending";
        end
    end
    fin.LevelDirection = repmat(dirn,height(fin),1);
end
above = true;
st = getf(R,'Settings',[]);
if isstruct(st) && isfield(st,'PeaksAboveThresholdOnly'), above = logical(st.PeaksAboveThresholdOnly); end
try
    [M,G] = mabr.analysis.Peaks.derived(P,Final=fin,AboveThresholdOnly=above);
catch
    % A peaks table of another shape: no derived measures from it.
end
end

function W = meansTable(lab,R)
% Per condition: the stored balanced mean, its SEM and N, with Time.
W = table();
Mn = getf(R,'Means',[]);
S = getf(R,'Summary',struct());
if ~isstruct(Mn) || ~isfield(Mn,'Balanced') || isempty(Mn.Balanced), return; end
k = reshape(string(Mn.Keys),[],1);
n = numel(k);
t = double(reshape(getf(S,'Time',(1:size(Mn.Balanced,1))'),[],1));
Tm = repmat({t},n,1);
Mc = cell(n,1);  Sc = cell(n,1);
for i = 1:n
    Mc{i} = double(Mn.Balanced(:,i));
    if isfield(Mn,'SEM') && size(Mn.SEM,2) >= i, Sc{i} = double(Mn.SEM(:,i)); else, Sc{i} = NaN(size(t)); end
end
N = NaN(n,1);
if isfield(Mn,'N') && numel(Mn.N) == n, N = double(Mn.N(:)); end
W = withLabels(lab,table(k,N,Tm,Mc,Sc,'VariableNames',{'Key','N','Time','Mean','SEM'}));
end

function T = stackTables(list)
% Vertical union of tables: every column of any, missing ones defaulted
% (NaN, "", false, NaT, {}), in order of first appearance.
list = list(~cellfun(@(t) isempty(t) || ~istable(t) || width(t) == 0,list));
if isempty(list), T = table(); return; end
% Each table's names are read once: a table property read is slow, and a
% study stacks one table per session (the usual case, every session with
% the same columns in the same order, then costs no rebuild at all).
vn = cell(size(list));
names = strings(1,0);  proto = struct();
for k = 1:numel(list)
    v = string(list{k}.Properties.VariableNames);
    vn{k} = v;
    for j = find(~ismember(v,names))
        names(end+1) = v(j); %#ok<AGROW>
        proto.(matlab.lang.makeValidName(v(j))) = list{k}.(v(j))([],:);
    end
end
for k = 1:numel(list)
    if isequal(vn{k},names), continue; end      % t(:,names) would be t itself
    t = list{k};
    n = height(t);
    for j = find(~ismember(names,vn{k}))
        p = proto.(matlab.lang.makeValidName(names(j)));
        if isstring(p), c = strings(n,1);
        elseif islogical(p), c = false(n,1);
        elseif isdatetime(p), c = NaT(n,1);
        elseif iscell(p), c = cell(n,1);
        elseif isnumeric(p), c = NaN(n,size(p,2));
        else, c = repmat(missing,n,1);
        end
        t.(names(j)) = c;
    end
    list{k} = t(:,cellstr(names));
end
try
    T = vertcat(list{:});
catch
    % Columns of one name but different types: as text.
    for k = 1:numel(list)
        for j = 1:numel(names)
            c = list{k}.(names(j));
            if ~iscell(c) && ~isstring(c) && ~(isnumeric(c) || islogical(c))
                list{k}.(names(j)) = string(c);
            end
        end
    end
    T = vertcat(list{:});
end
end

% =========================================================================
%  Files
% =========================================================================
function [D,ok,why] = readProjectFile(f)
D = struct();  ok = false;  why = "";
try
    L = load(char(f),'-mat',char(mabr.analysis.Project.VarName));
    if ~isfield(L,mabr.analysis.Project.VarName)
        why = "no " + mabr.analysis.Project.VarName + " in it";
        return
    end
    D = L.(mabr.analysis.Project.VarName);
    if ~isstruct(D) || ~isscalar(D)
        why = "it is not a project struct";  D = struct();
        return
    end
    ok = true;
catch ME
    why = string(ME.message);
end
end

function s = fileStamp(f)
s = struct('bytes',NaN,'datenum',NaN);
d = dir(char(f));
if isscalar(d) && ~d.isdir
    s.bytes = d.bytes;  s.datenum = d.datenum;
end
end

function t = fileTime(f)
t = NaT;
d = dir(char(f));
if isscalar(d) && ~d.isdir, t = datetime(d.datenum,'ConvertFrom','datenum'); end
end

function f = storeResults(store)
% The results files of a store (Catalog's countResults rule): every .mat
% but project.mat, temporary files, and .history/logs/figures/exports/scripts.
f = strings(0,1);
d = dir(fullfile(store,'**','*.mat'));
d = d(~[d.isdir]);
for k = 1:numel(d)
    rel = relPath(store,d(k).folder);
    if rel == "" && strcmpi(d(k).name,mabr.analysis.Project.FileName), continue; end
    if contains(lower(string(d(k).name)),".tmp"), continue; end
    if rel ~= ""
        parts = lower(split(rel,"/"));
        if any(startsWith(parts,".")) || any(ismember(parts,["logs" "figures" "exports" "scripts"]))
            continue
        end
    end
    f(end+1,1) = string(fullfile(d(k).folder,d(k).name)); %#ok<AGROW>
end
f = sort(f);
end

function r = relPath(base,f)
% f relative to base with "/" separators ("" for base itself); a path not
% under base comes back whole.
b = char(base);  f = char(f);
if strcmpi(regexprep(f,'[\\/]+$',''),regexprep(b,'[\\/]+$','')), r = ""; return; end
if ~(endsWith(b,'\') || endsWith(b,'/')), b = [b filesep]; end
if numel(f) > numel(b) && strcmpi(strrep(f(1:numel(b)),'/','\'),strrep(b,'/','\'))
    r = string(strrep(f(numel(b)+1:end),'\','/'));
else
    r = string(strrep(f,'\','/'));
end
end

function tf = isAbsolutePath(p)
tf = ~isempty(regexp(char(p),'^([A-Za-z]:|[\\/]{2}|/)','once'));
end

function k = rekeyOne(k,prefix)
% A nested store's keys as this store's: its root's path in front.
k = string(k);
top = k == "." | k == "";
k(~top) = prefix + "/" + k(~top);
k(top) = prefix;
end
