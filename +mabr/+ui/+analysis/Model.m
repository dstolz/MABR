classdef Model < handle
% mabr.ui.analysis.Model  The analysis app's state, and every change to it -- no graphics.
%
%   mabr.ui.AnalysisApp is a window over this object, and so is every view
%   in it. The Model holds what is open -- a data folder (Catalog), its
%   labels and settings (Project), one session (Session) and what is
%   selected in it -- and EVERY change goes through one of its methods,
%   which is what lets one rule hold everywhere: a change is undoable, it is
%   saved a moment later without being asked, and it raises an event every
%   view listens to. Nothing here draws or blocks, so a test (or a script)
%   drives the whole app without a window:
%
%       m = mabr.ui.analysis.Model(Interactive=false,AutoRefresh=false);
%       m.openRoot(root);                    % scan, open the project
%       m.openSession(m.Catalog.Sessions.Key(1));
%       k = m.seriesKeys(Stimulus="Tone");
%       m.selectSeries(k(1));
%       m.acceptFit();                       % undoable, autosaved
%       m.undo();  m.flush();                % writes the results file now
%
%   EVENTS (each with a mabr.ui.analysis.ChangeData), in a fixed order per
%   method -- the table in 11_spec_gui sec. 2.3, e.g. openRoot raises
%   BusyChanged(busy) -> RootChanged -> ProjectChanged(all) ->
%   SettingsChanged -> StatusChanged -> BusyChanged(idle), and a curation
%   command ResultsChanged(curation, Keys=series) -> StatusChanged(save).
%   SessionChanged means "rebuild everything". Messages the Session appends
%   raise StatusChanged(message, Level).
%
%   JOBS. Anything slow (a scan, opening raw data, an analysis, a batch, an
%   export) runs through runJob: Busy is set and announced, a progress
%   window opens (ProgressFcn), the Session reports into a sink that turns
%   Cancel into the error mabr:analysis:cancelled -- every Session step is
%   atomic, so a cancelled step changes nothing -- and BusyChanged(idle)
%   follows whatever happened. A mutating call made while Busy errors
%   mabr:ui:analysis:busy.
%
%   AUTOSAVE. Every edit marks the session "pending" and restarts a
%   single-shot timer (MABR_OfflineAutosave, AutosaveDelay s); saveNow()
%   writes the results file (results v2, no sweeps, atomic) and the project.
%   A results file changed on disk since this Model read or wrote it is NOT
%   overwritten ("conflict": keepMine() / loadTheirs()); a folder that
%   cannot be written makes the Model ReadOnly (edits stay in memory). The
%   file a re-analysis replaces is first copied to <ResultsFolder>/.history
%   (newest 3 per session).
%
%   UNDO. One stack per session key, for the app's lifetime: an entry holds
%   Session.editSnapshot() before and after (and the project rows a label
%   edit touched). Re-analysing a session clears its stack.
%
%   The functions that would talk to the user -- ConfirmFcn, AlertFcn,
%   PromptFcn, PickFolderFcn, PickFileFcn, ProgressFcn -- are properties:
%   the app supplies uiconfirm and friends, a test supplies stubs.
%
%   PREFS are only READ here (the default analyst, results-folder overrides,
%   the settings of a new project). The single write is
%   setSettings(...,Persist=true), which only the settings dialog's OK/Apply
%   passes -- a script driving the Model never changes a user's prefs.
%
%   FOR THE VIEWS AND DIALOGS (beyond 11_spec_gui sec. 2.2): views read
%   Session/Selection/Status at refresh time and call these too --
%     V = projectView()            Project.view(Catalog,Settings), cached
%                                  (Status none|current|stale|failed and
%                                  StatusText, e.g. "Out of date (overrides
%                                  changed)")
%     info = sessionInfo(key)      Paths, Members, Name, IsPool, ResultsFile,
%                                  Subject, Start, Summary, TestMode
%     tf = hasResults(key) ; f = resultsFolder()
%     [o,d,t] = latencyOffset()    ms: total, conduction delay, system offset
%     txt = latencyText()          the delay in words ("" at 0); time axes go
%                                  through mabr.ui.analysis.View.timeAxis
%     setSessionOverrides(key,ov)  ov fields InputFullScale, AmplifierGain,
%                                  TimeOffset, ConductionDelay (NaN = none)
%     setHidden(keys,tf)           exclude and hide sessions (true) or show
%                                  them again (false); one undo step
%     keys = allKeys()             every session and pool but the hidden ones
%                                  (an "all sessions" scope)
%     file = exportScript(Keys=,File=,Open=)   the replication script (13 A7)
%     T = batch(keys,...,Settings=s)  a batch with another profile's
%                                  settings (BatchDialog); [] = the project's;
%                                  MergeInto=summary for a report's Retry
%     revertSeries(sk) ; clearAllEdits() ; keepMine() ; loadTheirs()
%     [u,r] = undoHistory()        labels of the undo/redo stacks
%     txt = blindText(txt)         TXT with session/subject names masked
%                                  while blind review is on (every event's
%                                  Text already is)
%     LastMessage, LastMessageLevel, LastOpenError, LastExport,
%     LastExportFolder, LastScript, JobTitle, ConflictTime (read-only)
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.ChangeData,
%   mabr.ui.analysis.View, mabr.analysis.Session, mabr.analysis.Catalog,
%   mabr.analysis.Project, mabr.analysis.Batch
%
% Daniel Stolzberg (c) 2026

    % =====================================================================
    properties (SetAccess = private)
        Catalog = []                        % mabr.analysis.Catalog, or []
        Project = []                        % mabr.analysis.Project, or []
        Settings = []                       % the project's mabr.analysis.Settings in force
        SessionKey (1,1) string = ""        % folder key, or "pool:<hex8>"
        SessionKeys (:,1) string = strings(0,1)   % the member folder keys
        Session = []                        % mabr.analysis.Session, or []
        SessionSource (1,1) string = "none" % "none" | "results" | "raw"
        Status                              % struct State, Text, Differences, FromStep, Seconds
        Selection                           % struct ConditionKey, SeriesKey, Level, Wave, Kind, Sweeps, Anchor
        Busy (1,1) logical = false
        CancelRequested (1,1) logical = false
        ReadOnly (1,1) logical = false
        ReadOnlyWhy (1,1) string = ""       % why, when it is not the folder ("" = cannot write there)
        BlindReview (1,1) logical = false
        SaveState (1,1) string = "saved"    % saved | pending | saving | failed | conflict | readonly
        LastSaved (1,1) datetime = NaT
        Queue = []                          % struct Keys, Position, Order, Seed, Blind, UnreviewedOnly
        PendingFileUse                      % struct FileIds (string col), Use (logical col)
        BrowserOrder (:,1) string = strings(0,1)
        LastBatch = []                      % struct Summary (table, retries merged), LogFile, Settings ([] = the project's)
        LevelMemory                         % containers.Map: levelMemoryKey(series) -> last level

        % ---- beyond the contract ----------------------------------------
        LastMessage (1,1) string = ""       % the last status sentence raised
        LastMessageLevel (1,1) double = 0
        LastOpenError = []                  % struct Key, Name, Message, Paths of a failed open
        ConflictTime (1,1) datetime = NaT   % when the results file was changed elsewhere
        LastExport = []                     % the options of the last export (exportAgain)
        LastExportFolder (1,1) string = ""
        LastScript (1,1) string = ""        % the last replication script written
        JobTitle (1,1) string = ""          % what the running job is
    end

    properties
        ResultsFolderOverride (1,1) string = ""   % results folder for this root ("" = the catalog's)
        CacheFolder (1,1) string = ""             % catalog cache folder ("" = Catalog's default)
        Interactive (1,1) logical = true          % false: never open an editor, keep theirs on conflict
        AutosaveDelay (1,1) double {mustBePositive} = 2
        UndoDepth (1,1) double {mustBePositive} = 100
        KeyTarget (1,1) string = "plot"           % "plot" | "ui" (the app writes it)
        FocusArea (1,1) string = "workspace"      % "workspace" | "browser" (the app writes it)
        KeysSuspended (1,1) logical = false       % the note editor is open
        Analyst (1,1) string = ""                 % stamped on every edit
        ConfirmFcn = []      % choice = ConfirmFcn(message,title,options,default)
        AlertFcn = []        % AlertFcn(message,title,icon)
        PromptFcn = []       % value = PromptFcn(prompt,title,default); [] = cancel
        PickFolderFcn = []   % path = PickFolderFcn(start,title); "" = cancel
        PickFileFcn = []     % path = PickFileFcn(filter,title,mode,default); "" = cancel
        ProgressFcn = []     % h = ProgressFcn("open",title): update(text,frac), cancelled(), close()
        AutoRefresh (1,1) logical = true          % false: no timers (call flush() to save)
        SettingsOverride = []                     % Settings that win over project and prefs (tests)
        CloseRequested (1,1) logical = false      % close the app when the running job ends
        CloseFcn = []                             % called (no arguments) when that happens
    end

    properties (Dependent)
        CanUndo
        CanRedo
        UndoLabel
        RedoLabel
    end

    properties (Access = private)
        UndoStacks                          % containers.Map: session key -> struct Undo, Redo
        AutosaveTimer = []
        Stamp                               % (bytes, datenum) of the results file as last read/written
        ResultsFile (1,1) string = ""       % the open session's results file
        SessionDirty (1,1) logical = false
        HistoryPending (1,1) logical = false
        SavedUnitOverride = []              % the unit override the open results were made with
        FailedText                          % containers.Map: session key -> failure text
        JobStep (1,1) string = ""
        JobK (1,1) double = 0
        JobN (1,1) double = 0
        JobOuter (1,1) string = ""
        JobBatch (1,1) logical = false
        SinkClock = []
        SinkLast (1,1) double = -Inf
        ProgressHandle = []
        ViewCache = []
        BatchRun = []                       % the latest Batch.run table (what batch() returns)
        BlindCache = []                     % blindPattern's struct Sig, Pat
    end

    events
        RootChanged
        ProjectChanged
        SessionChanged
        ResultsChanged
        SelectionChanged
        SettingsChanged
        StatusChanged
        BusyChanged
    end

    properties (Constant)
        HistoryKeep = 3                     % .history files kept per session
        PrefGroup = 'MABR'
    end

    % =====================================================================
    methods
        function obj = Model(varargin)
            % Model(Name=Value,...) -- any public property.
            obj.LevelMemory = containers.Map('KeyType','char','ValueType','double');
            obj.UndoStacks  = containers.Map('KeyType','char','ValueType','any');
            obj.FailedText  = containers.Map('KeyType','char','ValueType','any');
            obj.Status      = mabr.ui.analysis.Model.emptyStatus();
            obj.Selection   = mabr.ui.analysis.Model.emptySelection();
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            obj.Stamp       = mabr.ui.analysis.Model.fileStamp("");
            obj.Analyst     = mabr.ui.analysis.Model.defaultAnalyst();
            obj.ConfirmFcn    = @(msg,title,options,default) string(default);
            obj.AlertFcn      = @(msg,title,icon) mabr.log.vprintf(1,'%s: %s',char(title),char(msg));
            obj.PromptFcn     = @(prompt,title,default) [];
            obj.PickFolderFcn = @(start,title) "";
            obj.PickFileFcn   = @(filter,title,mode,default) "";
            obj.ProgressFcn   = @(op,title) obj.silentProgress();
            if mod(numel(varargin),2) ~= 0
                error('mabr:ui:analysis:Model:badArguments','Model takes Name,Value pairs.');
            end
            for i = 1:2:numel(varargin)
                obj.(char(varargin{i})) = varargin{i+1};
            end
            if ~isempty(obj.SettingsOverride)
                obj.Settings = obj.SettingsOverride;
            else
                obj.Settings = mabr.analysis.Settings.loadPrefs();
            end
        end

        function delete(obj)
            obj.stopAutosave();
            try
                if ~isempty(obj.AutosaveTimer) && isvalid(obj.AutosaveTimer)
                    delete(obj.AutosaveTimer);
                end
            catch
            end
        end

        % ---- dependent ---------------------------------------------------
        function tf = get.CanUndo(obj)
            st = obj.stack();
            tf = ~isempty(st.Undo);
        end

        function tf = get.CanRedo(obj)
            st = obj.stack();
            tf = ~isempty(st.Redo);
        end

        function s = get.UndoLabel(obj)
            st = obj.stack();
            if isempty(st.Undo), s = ""; else, s = string(st.Undo{end}.Label); end
        end

        function s = get.RedoLabel(obj)
            st = obj.stack();
            if isempty(st.Redo), s = ""; else, s = string(st.Redo{end}.Label); end
        end

        function set.KeyTarget(obj,v)
            v = string(v);
            if ~any(v == ["plot","ui"])
                error('mabr:ui:analysis:Model:badValue','KeyTarget is "plot" or "ui".');
            end
            obj.KeyTarget = v;
        end

        function set.Analyst(obj,v)
            % The name stamped on every edit -- the open session's too, so a
            % rename (Settings ▸ Analyst Name…) signs the next edit with it.
            v = string(v);
            obj.Analyst = v;
            try
                if ~isempty(obj.Session) %#ok<MCSUP> (the Session is the one being signed)
                    obj.Session.Analyst = v; %#ok<MCSUP>
                end
            catch
            end
        end

        function set.FocusArea(obj,v)
            v = string(v);
            if ~any(v == ["workspace","browser"])
                error('mabr:ui:analysis:Model:badValue','FocusArea is "workspace" or "browser".');
            end
            obj.FocusArea = v;
        end

        % =================================================================
        %  Root and catalog
        % =================================================================
        function openRoot(obj,path,opts)
            % Open a data folder: scan it, open its project, choose settings.
            %
            %   path                   the folder (a study, or one subject's)
            %   opts.SuggestStudyRoot  offer the study folder when PATH looks
            %                          like one animal's (default true)
            %
            % Writes nothing in the data tree: the catalog cache lives in
            % CacheFolder and the project is created on the first save.
            arguments
                obj
                path (1,1) string
                opts.SuggestStudyRoot (1,1) logical = true
            end
            obj.assertNotBusy();
            path = mabr.ui.analysis.Model.absolutePath(path);
            if ~isfolder(path)
                error('mabr:ui:analysis:noFolder','The folder "%s" does not exist.',path);
            end
            if opts.SuggestStudyRoot
                path = obj.offerStudyRoot(path);
            end
            obj.flush();
            [~,nm] = fileparts(char(path));
            obj.runJob("Scanning " + string(nm),@(sink) obj.openRootWork(path,sink));
        end

        function rescan(obj)
            % Scan the open folder again (new files, changed files).
            obj.assertNotBusy();
            obj.requireRoot();
            if ~obj.acquisitionOk(), return; end
            obj.flush();
            obj.runJob("Rescanning",@(sink) obj.rescanWork(sink));
        end

        function closeRoot(obj)
            % Close the folder (saving first).
            obj.assertNotBusy();
            obj.flush();
            obj.Session = [];
            obj.SessionKey = "";
            obj.SessionKeys = strings(0,1);
            obj.SessionSource = "none";
            obj.ResultsFile = "";
            obj.Selection = mabr.ui.analysis.Model.emptySelection();
            obj.Catalog = [];
            obj.Project = [];
            obj.Queue = [];
            obj.BlindReview = false;
            obj.ReadOnly = false;
            obj.ReadOnlyWhy = "";
            obj.SaveState = "saved";
            obj.LastOpenError = [];
            obj.ViewCache = [];
            obj.updateStatus();
            obj.ev("SessionChanged","all","closeRoot");
            obj.ev("RootChanged","all","closeRoot");
            obj.ev("StatusChanged","status","closeRoot",Text="Folder closed.");
        end

        function n = importNestedStore(obj,path)
            % Copy a nested results store (e.g. SUBJ-ID-1254/MABR_Analysis)
            % into this project's store; the nested store is left as it is.
            arguments
                obj
                path (1,1) string
            end
            obj.assertNotBusy();
            obj.requireRoot();
            if obj.ReadOnly
                error('mabr:ui:analysis:readOnly', ...
                    'The results folder cannot be written, so nothing can be imported into it.');
            end
            obj.flush();
            [n,msg] = obj.Project.importStore(path,obj.Catalog);
            obj.ViewCache = [];
            obj.markDirty("project");
            obj.ev("ProjectChanged","all","importNestedStore");
            obj.saveNow();
            txt = sprintf('Imported %d session(s) from %s.',n,path);
            msg = strjoin(reshape(string(msg),1,[])," ");
            if strlength(msg) > 0, txt = txt + " " + msg; end
            obj.ev("StatusChanged","save","importNestedStore",Text=txt);
        end

        function ignoreNestedStore(obj,path)
            % Stop offering to import a nested results store.
            arguments
                obj
                path (1,1) string
            end
            obj.assertNotBusy();
            obj.requireRoot();
            try
                obj.Project.ignoreStore(path);
            catch me
                mabr.log.vprintf(2,'Model: could not record an ignored store (%s).',me.message);
            end
            obj.markDirty("project");
            obj.ev("ProjectChanged","all","ignoreNestedStore");
            obj.ev("StatusChanged","save","ignoreNestedStore", ...
                Text="Results under " + path + " are ignored in this project.");
        end

        function setResultsFolder(obj,folder)
            % Use FOLDER as the results store of the open root (and reopen
            % it there). The app remembers the choice in its pref map; the
            % Model only applies it.
            %
            % From a writable store, whatever is pending is saved there
            % first. From a READ-ONLY one (the header bar's "Choose results
            % folder…") the edits held in memory are what this is for, so
            % they move with it: the open session's unsaved edits are
            % written into FOLDER (a results file already there for that
            % session is a save conflict -- Keep mine / Load theirs -- never
            % overwritten silently), and the project's unsaved labels become
            % FOLDER's project when FOLDER has none of its own (when it has
            % one, it is opened as it is and the status line says what was
            % not carried over).
            arguments
                obj
                folder (1,1) string
            end
            obj.assertNotBusy();
            folder = mabr.ui.analysis.Model.absolutePath(folder);
            if isempty(obj.Catalog)
                obj.ResultsFolderOverride = folder;
                obj.ReadOnly = false;
                obj.ReadOnlyWhy = "";
                return
            end
            if ~obj.ReadOnly
                obj.flush();          % pending edits go to the old store
            end
            key = obj.SessionKey;
            sel = obj.Selection;
            S   = obj.Session;
            src = obj.SessionSource;
            % (unsaved because the store is unwritable, or because its file
            % changed elsewhere and the conflict is still open)
            keepS = (obj.ReadOnly || obj.SaveState == "conflict") && ~isempty(S) && obj.SessionDirty;
            note = "";
            if obj.ReadOnly && obj.projectDirty()
                pf = fullfile(char(folder),char(mabr.analysis.Project.FileName));
                if isfile(pf)
                    note = "That folder has a project of its own: the label changes made " + ...
                        "while read-only were not carried over.";
                else
                    try
                        obj.ensureProjectSettings();
                        mabr.analysis.Project.atomicSave(string(pf), ...
                            mabr.analysis.Project.VarName,obj.Project.toStruct());
                    catch me
                        note = "The project's label changes could not be written there (" + ...
                            string(me.message) + ").";
                    end
                end
            end
            % Nothing is written to the old (unwritable) store on the way
            % out: openRoot's flush finds the Model still read-only.
            obj.SessionDirty = false;
            obj.ResultsFolderOverride = folder;
            obj.openRoot(string(obj.Catalog.Root),SuggestStudyRoot=false);
            if key == "" || isempty(obj.Catalog), return; end
            if keepS
                try
                    obj.adoptMovedSession(S,key,src,sel);
                catch me
                    obj.say("Could not move " + key + "'s edits: " + string(me.message),2,"setResultsFolder");
                end
            else
                try
                    obj.openSession(key,SeriesKey=sel.SeriesKey,Level=sel.Level);
                catch me
                    obj.say("Could not reopen " + key + ": " + string(me.message),1,"setResultsFolder");
                end
            end
            if note ~= "", obj.say(note,1,"setResultsFolder"); end
        end

        % =================================================================
        %  Sessions
        % =================================================================
        function openSession(obj,key,opts)
            % Open one session (or pool): from its results file when there
            % is one (instant, results only), else from the raw files
            % (parse, segment, reject: a job).
            %
            %   key             a Catalog.Sessions key or a "pool:..." key
            %   opts.Source     "auto" (results if any) | "results" | "raw"
            %   opts.SeriesKey  select this series (default: keep the place)
            %   opts.Level      at this level (default: remembered/7.1)
            arguments
                obj
                key (1,1) string
                opts.Source (1,1) string {mustBeMember(opts.Source,["auto","results","raw"])} = "auto"
                opts.SeriesKey (1,1) string = ""
                opts.Level (1,1) double = NaN
            end
            obj.assertNotBusy();
            obj.requireRoot();
            if key == obj.SessionKey && ~isempty(obj.Session) && opts.Source == "auto"
                % Already open (a second double-click): keep it -- reloading
                % would drop the raw sweeps it may have -- and only move to
                % the series asked for.
                if opts.SeriesKey ~= "" && any(obj.seriesKeys() == opts.SeriesKey)
                    obj.selectSeries(opts.SeriesKey,Level=opts.Level);
                end
                return
            end
            info = obj.sessionInfo(key);
            prev = obj.Selection;
            obj.flush();
            useResults = isfile(info.ResultsFile) && opts.Source ~= "raw";
            obj.LastOpenError = [];
            try
                if useResults
                    try
                        obj.openSessionWork(info,"results",opts,prev,[]);
                    catch meR
                        % A results file that cannot be read (a partial
                        % sync, a damaged disk) must not lock the session
                        % out: it opens from its raw files instead, and the
                        % unreadable file is kept aside before anything is
                        % saved over it (buildRawSession).
                        if strcmp(meR.identifier,'mabr:analysis:cancelled'), rethrow(meR); end
                        mabr.log.vprintf(1,'Model: the results of %s could not be read (%s); opening its raw files.', ...
                            info.Name,meR.message);
                        obj.say("The results of " + info.Name + " could not be read (" + ...
                            string(meR.message) + ") — opening it from its raw files.",1,"openSession");
                        obj.runJob("Opening " + info.Name, ...
                            @(sink) obj.openSessionWork(info,"raw",opts,prev,sink));
                        obj.say("Opened " + info.Name + " from its raw files: its results file could " + ...
                            "not be read (kept in .history); press Analyse.",1,"openSession");
                    end
                else
                    obj.runJob("Opening " + info.Name, ...
                        @(sink) obj.openSessionWork(info,"raw",opts,prev,sink));
                end
            catch me
                obj.LastOpenError = struct('Key',key,'Name',info.Name, ...
                    'Message',string(me.message),'Paths',info.Paths);
                obj.say("Could not open " + info.Name + ": " + string(me.message),2,"openSession");
                mabr.log.vprintf(2,me);
            end
        end

        function closeSession(obj)
            % Close the open session (saving first).
            obj.assertNotBusy();
            obj.flush();
            obj.Session = [];
            obj.SessionKey = "";
            obj.SessionKeys = strings(0,1);
            obj.SessionSource = "none";
            obj.ResultsFile = "";
            obj.Selection = mabr.ui.analysis.Model.emptySelection();
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            obj.updateStatus();
            obj.ev("SessionChanged","all","closeSession");
            obj.ev("SelectionChanged","series","closeSession");
            obj.ev("StatusChanged","status","closeSession");
        end

        function openAdjacent(obj,step)
            % The next (step +1) or previous (-1) session: through the review
            % queue when one is running, else in the browser's order,
            % skipping failed and empty sessions.
            arguments
                obj
                step (1,1) double = 1
            end
            obj.requireRoot();
            if ~isempty(obj.Queue)
                obj.nextInQueue(step);
                return
            end
            order = obj.browserKeys();
            if isempty(order)
                obj.say("No session to go to.",0,"openAdjacent");
                return
            end
            i = find(order == obj.SessionKey,1);
            if isempty(i)
                if step > 0, i = 0; else, i = numel(order) + 1; end
            end
            j = i + sign(step);
            while j >= 1 && j <= numel(order)
                if obj.isOpenable(order(j))
                    obj.openSession(order(j));
                    return
                end
                j = j + sign(step);
            end
            if step > 0
                obj.say("This is the last session.",0,"openAdjacent");
            else
                obj.say("This is the first session.",0,"openAdjacent");
            end
        end

        function setBrowserOrder(obj,keys)
            % The session keys in the order the browser shows them (it
            % calls this after every rebuild); openAdjacent walks it.
            obj.BrowserOrder = reshape(string(keys),[],1);
        end

        function ensureRaw(obj)
            % Give a results-only session its sweeps back (Session.loadRaw,
            % a job "Loading raw data"); a no-op when they are in memory.
            obj.assertSession();
            if obj.Session.HasSweeps, return; end
            obj.assertNotBusy();
            obj.runJob("Loading raw data",@(sink) obj.ensureRawWork(sink));
        end

        function analyze(obj,opts)
            % Run the analysis of the open session from the first step whose
            % settings (or data) changed, through to the end.
            %
            %   opts.From  "auto" (Settings.firstChangedStep, "segment" when
            %              never analysed) or a step name
            %   opts.Keys  condition subset (segment ... measure)
            arguments
                obj
                opts.From (1,1) string = "auto"
                opts.Keys (:,1) string = strings(0,1)
            end
            obj.assertNotBusy();
            obj.assertSession();
            if ~obj.acquisitionOk(), return; end
            from = opts.From;
            if from == "auto"
                from = obj.autoFrom();
                if from == ""
                    obj.say("Up to date — there is nothing to re-run.",0,"analyze");
                    return
                end
            end
            if ~ismember(from,mabr.analysis.Settings.Steps)
                error('mabr:ui:analysis:badStep','"%s" is not an analysis step.',from);
            end
            if ~ismember(from,["thresholds","peaks"]) && ~obj.Session.HasSweeps
                obj.ensureRaw();
                if ~obj.Session.HasSweeps, return; end   % cancelled
            end
            state0 = obj.stepStateOf(obj.Session);
            t0 = tic;
            try
                ok = obj.runJob("Analysing " + obj.displayName(), ...
                    @(sink) obj.analyzeWork(from,opts.Keys,sink,t0));
            catch me
                obj.analysisFailed(me,state0);
                rethrow(me);
            end
            if ~ok
                obj.afterCancelledAnalysis(state0);
                return
            end
            obj.saveNow();
        end

        function refit(obj)
            % Re-fit thresholds and peaks only (instant; works results-only).
            obj.assertNotBusy();
            obj.assertSession();
            state0 = obj.stepStateOf(obj.Session);
            try
                ok = obj.runJob("Re-fitting thresholds", ...
                    @(sink) obj.analyzeWork("thresholds",strings(0,1),sink,tic));
            catch me
                obj.analysisFailed(me,state0);
                rethrow(me);
            end
            if ok, obj.saveNow(); end
        end

        function txt = setSettings(obj,s,opts)
            % Make S the project's settings.
            %
            %   s             mabr.analysis.Settings
            %   opts.Persist  also remember S as the user's defaults (pref
            %                 OfflineAnalysisSettings) -- ONLY the settings
            %                 dialog's OK/Apply passes true
            %   opts.Refit    re-fit the open session at once when only its
            %                 thresholds/peaks settings changed (default
            %                 true); slower steps only become out of date
            %   txt           (returned) what is now out of date, in words
            arguments
                obj
                s (1,1) mabr.analysis.Settings
                opts.Persist (1,1) logical = false
                opts.Refit (1,1) logical = true
            end
            obj.assertNotBusy();
            obj.Settings = s;
            if ~isempty(obj.Project)
                try
                    obj.Project.setSettings(s);
                    obj.markDirty("project");
                catch me
                    mabr.log.vprintf(2,'Model: project settings not stored (%s).',me.message);
                end
            end
            if opts.Persist
                mabr.analysis.Settings.savePrefs(s);
            end
            obj.ViewCache = [];
            % The re-fit runs BEFORE the events, so SettingsChanged(all)
            % already finds the re-fitted session: a showing view draws it
            % once, and passes over the ResultsChanged(thresholds) that
            % follows from the same call (View.onModelEvent) -- the order
            % of the events is the contract's (11 sec. 2.3).
            refitted = false;
            failure = [];
            S = obj.Session;
            changed = struct('Step',"",'Fields',strings(0,1),'Old',[],'New',s);
            if opts.Refit && ~isempty(S) && obj.isAnalysed(S) && ~isempty(S.Settings)
                k = mabr.analysis.Settings.firstChangedStep(S.Settings,s);
                % (what changed, for the report: a delay or a time offset
                % alone re-reports the peaks and moves no threshold)
                changed.Step = k;
                changed.Old = S.Settings;
                try
                    changed.Fields = string(mabr.analysis.Settings.diff(S.Settings,s).Field);
                catch
                end
                % (a method reading a measure these results were made
                % without is a measure step, not a re-fit: Session.isStale
                % says so, and Analyse re-runs from there)
                if ismember(k,["thresholds","peaks"]) && S.missingMeasure(s) == ""
                    try
                        S.analyze(s,'From',k);
                        obj.HistoryPending = true;
                        obj.markDirty("session");
                        refitted = true;
                    catch me
                        % (a step is atomic: the session is as it was, now
                        % out of date; the settings are the project's all
                        % the same, so the views hear it before the error)
                        failure = me;
                    end
                end
            end
            obj.ev("SettingsChanged","all","setSettings");
            if refitted
                obj.ev("ResultsChanged","thresholds","setSettings");
            end
            obj.updateStatus();
            txt = obj.settingsReport(refitted,changed);
            obj.ev("StatusChanged","status","setSettings",Text=txt);
            if ~isempty(failure), rethrow(failure); end
        end

        function applyProfile(obj,name)
            % Use a built-in settings profile (Settings.profileNames).
            arguments
                obj
                name (1,1) string
            end
            obj.setSettings(mabr.analysis.Settings.profile(name));
        end

        function adoptSessionSettings(obj)
            % Make the open session's own settings the project's (the
            % out-of-date bar's "Use this session's settings").
            obj.assertSession();
            if isempty(obj.Session.Settings)
                obj.say("This session has not been analysed, so it has no settings of its own.",1, ...
                    "adoptSessionSettings");
                return
            end
            obj.setSettings(obj.Session.Settings);
        end

        % =================================================================
        %  Selection (never mutating; SelectionChanged)
        % =================================================================
        function selectCondition(obj,condKey)
            % Select one condition (its series and level follow).
            arguments
                obj
                condKey (1,1) string
            end
            obj.assertSession();
            obj.Session.rowOf(condKey);          % unknown -> mabr:analysis:Session:unknownKey
            sel = obj.Selection;
            sel.ConditionKey = condKey;
            sel.SeriesKey = obj.seriesOfCondition(condKey);
            sel.Level = obj.conditionLevel(condKey);
            sel.Sweeps = zeros(1,0);
            sel.Anchor = NaN;
            obj.rememberLevel(sel.SeriesKey,sel.Level);
            obj.Selection = sel;
            obj.ev("SelectionChanged","condition","selectCondition",Keys=condKey);
        end

        function selectSeries(obj,seriesKey,opts)
            % Select a series, at opts.Level, else the level last used in it,
            % else the threshold-adjacent level (11 sec. 7.1).
            arguments
                obj
                seriesKey (1,1) string
                opts.Level (1,1) double = NaN
            end
            obj.assertSession();
            [ck,lv] = obj.seriesLevels(seriesKey);
            if isempty(ck)
                error('mabr:ui:analysis:unknownSeries','No series "%s" in this session.',seriesKey);
            end
            level = opts.Level;
            if isnan(level)
                if isKey(obj.LevelMemory,obj.levelMemoryKey(seriesKey))
                    level = obj.LevelMemory(obj.levelMemoryKey(seriesKey));
                else
                    level = obj.defaultLevel(seriesKey);
                end
            end
            [~,i] = min(abs(lv - level));
            sel = obj.Selection;
            sameCond = sel.ConditionKey == ck(i);
            sel.SeriesKey = seriesKey;
            sel.Level = lv(i);
            sel.ConditionKey = ck(i);
            if ~sameCond
                sel.Sweeps = zeros(1,0);
                sel.Anchor = NaN;
            end
            obj.rememberLevel(seriesKey,lv(i));
            obj.Selection = sel;
            obj.ev("SelectionChanged","series","selectSeries",Keys=seriesKey);
        end

        function selectLevel(obj,level)
            % Select a level of the current series (the nearest one there).
            arguments
                obj
                level (1,1) double
            end
            obj.assertSession();
            sk = obj.Selection.SeriesKey;
            if sk == ""
                return
            end
            [ck,lv] = obj.seriesLevels(sk);
            if isempty(ck), return; end
            [~,i] = min(abs(lv - level));
            sel = obj.Selection;
            if sel.ConditionKey ~= ck(i)
                sel.Sweeps = zeros(1,0);
                sel.Anchor = NaN;
            end
            sel.Level = lv(i);
            sel.ConditionKey = ck(i);
            obj.rememberLevel(sk,lv(i));
            obj.Selection = sel;
            obj.ev("SelectionChanged","level","selectLevel",Keys=ck(i));
        end

        function stepLevel(obj,d)
            % One level louder (d = +1) or quieter (-1) in the current series.
            arguments
                obj
                d (1,1) double
            end
            obj.assertSession();
            sk = obj.Selection.SeriesKey;
            if sk == "", return; end
            [~,lv] = obj.seriesLevels(sk);
            if isempty(lv), return; end
            [~,i] = min(abs(lv - obj.Selection.Level));
            j = min(max(i + d,1),numel(lv));
            if j == i && ~isnan(obj.Selection.Level), return; end
            obj.selectLevel(lv(j));
        end

        function stepSeries(obj,d)
            % The next (+1) or previous (-1) series, keeping the level
            % nearest the current one.
            arguments
                obj
                d (1,1) double
            end
            obj.assertSession();
            keys = obj.seriesKeys();
            if isempty(keys), return; end
            i = find(keys == obj.Selection.SeriesKey,1);
            if isempty(i), i = 0; end
            j = min(max(i + d,1),numel(keys));
            if j == i, return; end
            lv = obj.Selection.Level;
            if isnan(lv)
                obj.selectSeries(keys(j));
            else
                obj.selectSeries(keys(j),Level=lv);
            end
        end

        function selectWave(obj,wave,kind)
            % Select a wave's peak (kind "P") or trough ("N") at the current
            % level -- the point the peak keys act on.
            arguments
                obj
                wave (1,1) string
                kind (1,1) string {mustBeMember(kind,["P","N"])} = "P"
            end
            sel = obj.Selection;
            sel.Wave = wave;
            sel.Kind = kind;
            obj.Selection = sel;
            obj.ev("SelectionChanged","wave","selectWave",Keys=sel.ConditionKey);
        end

        function clearWave(obj)
            % No wave point selected.
            sel = obj.Selection;
            if sel.Wave == "", return; end
            sel.Wave = "";
            obj.Selection = sel;
            obj.ev("SelectionChanged","wave","clearWave",Keys=sel.ConditionKey);
        end

        function selectSweeps(obj,cols,opts)
            % Select sweeps of the current condition (column indices into
            % its Sweeps).
            %   opts.Mode  "replace" | "extend" (from Selection.Anchor) | "toggle"
            arguments
                obj
                cols double = zeros(1,0)
                opts.Mode (1,1) string {mustBeMember(opts.Mode,["replace","extend","toggle"])} = "replace"
            end
            sel = obj.Selection;
            cols = unique(round(cols(:).'));
            cols = cols(isfinite(cols) & cols >= 1);
            switch opts.Mode
                case "replace"
                    sel.Sweeps = cols;
                    if ~isempty(cols), sel.Anchor = cols(end); end
                case "extend"
                    if isempty(cols)
                        % nothing to extend to
                    elseif isnan(sel.Anchor)
                        sel.Sweeps = cols;
                        sel.Anchor = cols(1);
                    else
                        k = cols(end);
                        sel.Sweeps = min(sel.Anchor,k):max(sel.Anchor,k);
                    end
                case "toggle"
                    sel.Sweeps = setxor(sel.Sweeps,cols);
                    if ~isempty(cols), sel.Anchor = cols(end); end
            end
            sel.Sweeps = reshape(sel.Sweeps,1,[]);
            obj.Selection = sel;
            obj.ev("SelectionChanged","sweeps","selectSweeps",Keys=sel.ConditionKey);
        end

        % =================================================================
        %  Threshold curation (current series unless a key is given)
        % =================================================================
        function rep = acceptFit(obj,seriesKey)
            % Accept the method's threshold for the series.
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            rep = obj.curate("Accept fit",sk,@(S) S.acceptFit(sk),"acceptFit","Accepted fit");
        end

        function rep = setThresholdAtLevel(obj,level,seriesKey)
            % The threshold is LEVEL: the lowest level with a response.
            arguments
                obj
                level (1,1) double = NaN
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            if isnan(level), level = obj.Selection.Level; end
            if isnan(level)
                error('mabr:ui:analysis:noLevel','Select a level first.');
            end
            rep = obj.curate("Threshold at " + mabr.ui.analysis.Model.num(level) + " dB",sk, ...
                @(S) S.setDecision(sk,"manual",'Value',level,'Kind',"level"), ...
                "setThresholdAtLevel","Threshold set at " + mabr.ui.analysis.Model.num(level) + " dB");
        end

        function rep = setThresholdValue(obj,v,seriesKey)
            % The threshold is the value V (dB), uncensored.
            arguments
                obj
                v (1,1) double
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            rep = obj.curate("Threshold " + mabr.ui.analysis.Model.num(v) + " dB",sk, ...
                @(S) S.setDecision(sk,"manual",'Value',v,'Kind',"value"), ...
                "setThresholdValue","Threshold set to " + mabr.ui.analysis.Model.num(v) + " dB");
        end

        function rep = setNoResponse(obj,seriesKey)
            % No response at any level (right-censored).
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            rep = obj.curate("No response",sk,@(S) S.setDecision(sk,"noresponse"), ...
                "setNoResponse","Marked no response");
        end

        function rep = setAllRespond(obj,seriesKey)
            % Every level responds (left-censored).
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            rep = obj.curate("All respond",sk,@(S) S.setDecision(sk,"allrespond"), ...
                "setAllRespond","Marked all levels responding");
        end

        function [rep,excluded] = toggleExcluded(obj,seriesKey)
            % Exclude the series, or bring an excluded one back.
            %   excluded  (returned) true when the series is now excluded
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            if obj.decisionOf(sk) == "excluded"
                rep = obj.curate("Include again",sk,@(S) S.clearDecision(sk), ...
                    "toggleExcluded","Included again");
                excluded = false;
            else
                rep = obj.curate("Exclude",sk,@(S) S.setDecision(sk,"excluded"), ...
                    "toggleExcluded","Excluded");
                excluded = true;
            end
        end

        function rep = clearDecision(obj,seriesKey)
            % Back to unreviewed.
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            rep = obj.curate("Clear decision",sk,@(S) S.clearDecision(sk), ...
                "clearDecision","Decision cleared");
        end

        function setNote(obj,target,text)
            % A note on a series threshold, or a comment on a session.
            %   target  struct Kind ("series"|"session"), Key
            arguments
                obj
                target (1,1) struct
                text (1,1) string
            end
            kind = string(target.Kind);
            key  = string(target.Key);
            if kind == "session"
                obj.label(key,"Comment",text);
                return
            end
            if key == "", key = obj.targetSeries(""); end
            obj.curate("Note",key,@(S) S.setThresholdNote(key,text),"setNote","Note saved");
        end

        function rep = cycleDetectionOverride(obj,condKey)
            % auto -> response -> no response -> auto, for one condition.
            arguments
                obj
                condKey (1,1) string = ""
            end
            if condKey == "", condKey = obj.Selection.ConditionKey; end
            v = obj.overrideOf(condKey);
            if isnan(v), nv = 1; elseif v == 1, nv = 0; else, nv = NaN; end
            rep = obj.setDetectionOverride(condKey,nv);
        end

        function rep = setDetectionOverride(obj,condKey,v)
            % Force a condition detected (1), not detected (0), or auto (NaN);
            % its series is re-fitted.
            arguments
                obj
                condKey (1,1) string
                v (1,1) double
            end
            obj.assertMutable();
            if condKey == ""
                error('mabr:ui:analysis:noCondition','Select a condition first.');
            end
            sk = obj.seriesOfCondition(condKey);
            switch true
                case isnan(v), w = "auto";
                case v == 1,   w = "response";
                otherwise,     w = "no response";
            end
            lab = "Detection " + w + " (" + obj.conditionLabel(condKey) + ")";
            rep = obj.applyEdit(lab,@(S) S.setDetectionOverride(condKey,v),"thresholds",sk, ...
                "setDetectionOverride","Detection set to " + w + " for " + obj.conditionLabel(condKey));
        end

        function T = compareMethods(obj,seriesKey)
            % Every built-in threshold method on the series' stored
            % per-condition columns: table Method, Label, Threshold, Status,
            % Text, Flags (the method's flags, "; "-joined -- why a level was
            % ignored, a dead channel's "zero variance" among them). Changes
            % nothing.
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            S = obj.Session;
            [ck,lv] = obj.seriesLevels(sk);
            Y = obj.seriesInputs(ck);
            M = mabr.analysis.SeriesThreshold.methods();
            n = numel(M);
            Method = strings(0,1); Label = Method; Stat = Method; Text = Method; Flags = Method;
            Threshold = zeros(0,1);
            st = obj.Settings;
            if ~isempty(S.Settings), st = S.Settings; end
            for i = 1:n
                id = string(M(i).Id);
                if id == "custom", continue; end
                Method(end+1,1) = id; %#ok<AGROW>
                Label(end+1,1) = string(M(i).Label); %#ok<AGROW>
                try
                    m = mabr.analysis.SeriesThreshold.resolve(id,st);
                    eo = obj.estimateOpts(st);
                    out = mabr.analysis.SeriesThreshold.estimate(lv,Y,m,eo{:});
                    Threshold(end+1,1) = out.Threshold; %#ok<AGROW>
                    Stat(end+1,1) = string(out.Status); %#ok<AGROW>
                    Text(end+1,1) = mabr.analysis.SeriesThreshold.formatValue(out.Threshold, ...
                        string(out.Censored),out.ThrLo,out.ThrHi); %#ok<AGROW>
                    fl = "";
                    if isfield(out,'Flags') && ~isempty(out.Flags)
                        f = string(out.Flags);
                        fl = strjoin(f(~ismissing(f) & f ~= ""),"; ");
                    end
                    Flags(end+1,1) = fl; %#ok<AGROW>
                catch me
                    Threshold(end+1,1) = NaN; %#ok<AGROW>
                    Stat(end+1,1) = "n/a"; %#ok<AGROW>
                    Text(end+1,1) = string(me.message); %#ok<AGROW>
                    Flags(end+1,1) = ""; %#ok<AGROW>
                end
            end
            T = table(Method,Label,Threshold,Stat,Text,Flags, ...
                'VariableNames',{'Method','Label','Threshold','Status','Text','Flags'});
        end

        function nextNeedingReview(obj,step)
            % The next (+1) or previous (-1) series with no decision yet --
            % in this session, then in the next session that has one.
            arguments
                obj
                step (1,1) double = 1
            end
            obj.requireRoot();
            if ~isempty(obj.Session)
                sk = obj.needingReview(obj.seriesKeys(),obj.Selection.SeriesKey,step);
                if sk ~= ""
                    obj.selectSeries(sk);
                    obj.say("Needs review: " + obj.seriesLabel(sk),0,"nextNeedingReview");
                    return
                end
            end
            if ~isempty(obj.Queue)
                order = obj.Queue.Keys;
            else
                order = obj.browserKeys();
            end
            i = find(order == obj.SessionKey,1);
            if isempty(i)
                if step > 0, i = 0; else, i = numel(order) + 1; end
            end
            j = i + sign(step);
            while j >= 1 && j <= numel(order)
                if obj.sessionNeedsReview(order(j))
                    obj.openSession(order(j));
                    if obj.SessionKey == order(j)
                        keys = obj.seriesKeys();
                        if step > 0, from = ""; else, from = "<end>"; end
                        sk = obj.needingReview(keys,from,step);
                        if sk ~= "", obj.selectSeries(sk); end
                    end
                    return
                end
                j = j + sign(step);
            end
            obj.say("Nothing else needs review.",0,"nextNeedingReview");
        end

        % =================================================================
        %  Peaks
        % =================================================================
        function rep = pickPeaks(obj,scope)
            % Re-pick the automatic peaks of the current series ("series")
            % or of every series ("all"); manual picks stay.
            arguments
                obj
                scope (1,1) string {mustBeMember(scope,["series","all"])} = "series"
            end
            obj.assertMutable();
            S = obj.Session;
            o = obj.peakOpts();
            if scope == "series"
                sk = obj.targetSeries("");
                args = [o {'SeriesKeys',sk}];
                keys = obj.seriesConditions(sk);
                lab = "Auto-pick (" + obj.seriesLabel(sk) + ")";
            else
                args = o;
                keys = strings(0,1);
                lab = "Auto-pick (all series)";
            end
            rep = obj.applyEdit(lab,@(S) S.pickPeaks(args{:}),"peaks",keys,"pickPeaks","Peaks re-picked");
            if isempty(S.Peaks)
                obj.say("No peaks: this session has no level series to track.",1,"pickPeaks");
            end
        end

        function rep = retrack(obj,opts)
            % Re-track the selected wave ("" all) from the selected level
            % down. opts.Overwrite drops manual picks below it first.
            arguments
                obj
                opts.Overwrite (1,1) logical = false
            end
            obj.assertMutable();
            sk = obj.targetSeries("");
            lvl = obj.Selection.Level;
            if isnan(lvl)
                [~,lv] = obj.seriesLevels(sk);
                lvl = max(lv);
            end
            wave = obj.Selection.Wave;
            keys = obj.seriesConditions(sk);
            what = "Re-track";
            if opts.Overwrite, what = "Re-track (overwrite)"; end
            rep = obj.applyEdit(what + " from " + mabr.ui.analysis.Model.num(lvl) + " dB", ...
                @(S) S.retrackSeries(sk,wave,lvl,'Overwrite',opts.Overwrite),"peaks",keys, ...
                "retrack",what + " from " + mabr.ui.analysis.Model.num(lvl) + " dB down");
        end

        function rep = setPeak(obj,condKey,wave,kind,tMs,opts)
            % Place a wave's peak (kind "P") or trough ("N") at tMs (ms,
            % raw latency re onset); opts.Snap to the nearest extremum.
            arguments
                obj
                condKey (1,1) string
                wave (1,1) string
                kind (1,1) string {mustBeMember(kind,["P","N"])}
                tMs (1,1) double
                opts.Snap (1,1) logical = true
            end
            obj.assertMutable();
            sk = obj.seriesOfCondition(condKey);
            keys = obj.seriesConditions(sk);
            if isempty(keys), keys = condKey; end
            nm = "peak"; if kind == "N", nm = "trough"; end
            % (the message names the time the user sees on the axes: the
            % reported latency, re sound arrival when a delay is set)
            rep = obj.applyEdit("Move " + wave + " " + nm + " (" + obj.conditionLabel(condKey) + ")", ...
                @(S) S.setPeak(condKey,wave,kind,tMs,'Snap',opts.Snap),"peaks",keys,"setPeak", ...
                sprintf('%s %s at %.2f ms',wave,nm,mabr.analysis.Peaks.reported(tMs,obj.latencyOffset())));
        end

        function rep = nudgePeak(obj,samples)
            % Move the selected wave point by whole samples.
            arguments
                obj
                samples (1,1) double
            end
            [ck,wave,kind] = obj.selectedPoint();
            lat = obj.pointLatency(ck,wave,kind);
            if isnan(lat)
                obj.say("No " + wave + " pick here to nudge.",1,"nudgePeak");
                rep = [];
                return
            end
            dt = 1000/obj.Session.SampleRate;
            rep = obj.setPeak(ck,wave,kind,lat + samples*dt,Snap=false);
        end

        function rep = moveToCandidate(obj,step)
            % Move the selected wave point to the next (+1) or previous (-1)
            % local extremum of its kind.
            arguments
                obj
                step (1,1) double = 1
            end
            [ck,wave,kind] = obj.selectedPoint();
            lat = obj.pointLatency(ck,wave,kind);
            S = obj.Session;
            y = obj.meanFor(ck);
            t = S.Time;
            c = mabr.analysis.Peaks.candidates(t,y,kind);
            rep = [];
            if isempty(c) || height(c) == 0
                obj.say("No other candidate.",0,"moveToCandidate");
                return
            end
            T = sort(c.T);
            if isnan(lat)
                if step > 0, k = 1; else, k = numel(T); end
            elseif step > 0
                k = find(T > lat + 1e-9,1,'first');
            else
                k = find(T < lat - 1e-9,1,'last');
            end
            if isempty(k)
                obj.say("No candidate further that way.",0,"moveToCandidate");
                return
            end
            i = c.Idx(find(c.T == T(k),1));
            tHat = mabr.analysis.Peaks.refine(t,y,i);
            rep = obj.setPeak(ck,wave,kind,tHat,Snap=false);
        end

        function rep = togglePeakAbsent(obj,opts)
            % Mark the selected wave absent at this level (opts.Below: and
            % every lower level), or bring it back.
            arguments
                obj
                opts.Below (1,1) logical = false
            end
            [ck,wave] = obj.selectedPoint();
            absent = obj.isAbsent(ck,wave);
            sk = obj.seriesOfCondition(ck);
            keys = obj.seriesConditions(sk);
            if absent
                lab = wave + " present again";
            elseif opts.Below
                lab = wave + " absent here and below";
            else
                lab = wave + " absent";
            end
            rep = obj.applyEdit(lab + " (" + obj.conditionLabel(ck) + ")", ...
                @(S) S.setPeakAbsent(ck,wave,~absent,'Below',opts.Below),"peaks",keys, ...
                "togglePeakAbsent",lab);
        end

        function rep = revertPeak(obj)
            % The selected wave point back to its automatic pick.
            [ck,wave,kind] = obj.selectedPoint();
            sk = obj.seriesOfCondition(ck);
            rep = obj.applyEdit("Revert " + wave + " (" + obj.conditionLabel(ck) + ")", ...
                @(S) S.clearPeak(ck,wave,kind),"peaks",obj.seriesConditions(sk),"revertPeak", ...
                wave + " back to the automatic pick");
        end

        function rep = clearSeriesPeakEdits(obj)
            % Every manual peak edit of the current series removed.
            obj.assertMutable();
            sk = obj.targetSeries("");
            rep = obj.applyEdit("Clear peak edits (" + obj.seriesLabel(sk) + ")", ...
                @(S) S.clearPeakOverrides(sk),"peaks",obj.seriesConditions(sk), ...
                "clearSeriesPeakEdits","Manual peak edits cleared");
        end

        function rep = bootstrapPeaks(obj,seriesKey)
            % Bootstrap confidence intervals of the series' peaks (raw data).
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            obj.ensureRaw();
            if ~obj.Session.HasSweeps, rep = []; return; end
            B = obj.Settings.PeakBootstrap;
            if B <= 0, B = 500; end
            args = [obj.peakOpts() {'SeriesKeys',sk,'Bootstrap',B}];
            keys = obj.seriesConditions(sk);
            rep = [];
            obj.runJob("Bootstrapping peaks",@(sink) obj.bootstrapWork(args,keys,sink));
        end

        function usePicksAsWindows(obj)
            % Make the current series' picks the wave windows of its
            % stimulus (project settings; the session is re-fitted). The
            % windows are stored as Session.picksAsWindows gives them: in the
            % recording's own time (re the timing pulse), where the picks are
            % and where the next analysis searches -- never less the latency
            % offset, which only changes reported latencies.
            obj.assertMutable();
            sk = obj.targetSeries("");
            W = obj.Session.picksAsWindows(sk);
            s = obj.Settings;
            old = s.Waves;
            stim = "";
            if ~isempty(W) && isfield(W,'Stimulus'), stim = string(W(1).Stimulus); end
            keep = old(string({old.Stimulus}) ~= stim);
            s.Waves = [reshape(keep,[],1); reshape(W,[],1)];
            obj.setSettings(s,Refit=true);
            obj.say("Wave windows now follow the picks of " + obj.seriesLabel(sk) + ...
                " (Settings ▸ Peaks to edit them).",0,"usePicksAsWindows");
        end

        % =================================================================
        %  Trials
        % =================================================================
        function rep = setSweepsRejected(obj,tf)
            % Reject (true) or restore (false) the selected sweeps of the
            % current condition; the condition is re-tested.
            arguments
                obj
                tf (1,1) logical = true
            end
            obj.assertMutable();
            ck = obj.Selection.ConditionKey;
            cols = obj.Selection.Sweeps;
            rep = [];
            if ck == "" || isempty(cols)
                obj.say("Select sweeps first.",1,"setSweepsRejected");
                return
            end
            obj.ensureRaw();
            if ~obj.Session.HasSweeps, return; end
            if tf, verb = "Reject"; else, verb = "Restore"; end
            lab = sprintf('%s %d sweep(s) (%s)',verb,numel(cols),obj.conditionLabel(ck));
            keys = obj.seriesConditions(obj.seriesOfCondition(ck));
            if isempty(keys), keys = ck; end
            obj.runJob(lab,@(sink) obj.rejectWork(lab,keys,sink, ...
                @(S) S.setSweepsRejected(ck,cols,tf)));
            rep = obj.LastMessage;
        end

        function rep = rejectAbove(obj,valueV,feature,opts)
            % Reject every sweep whose FEATURE exceeds valueV -- in the
            % current condition, or (opts.Series) every level of the series.
            %   valueV   volts; a plain ratio for TemplateAmp and TemplateR
            %   feature  "RMS" | "P2P" | "MaxAbs" | "TemplateAmp" | "TemplateR"
            %            (the values the Trials tab plots; featureValues)
            arguments
                obj
                valueV (1,1) double
                feature (1,1) string = "MaxAbs"
                opts.Series (1,1) logical = false
            end
            obj.assertMutable();
            ck = obj.Selection.ConditionKey;
            if ck == ""
                error('mabr:ui:analysis:noCondition','Select a condition first.');
            end
            obj.ensureRaw();
            if ~obj.Session.HasSweeps, rep = []; return; end
            feature = mabr.ui.analysis.Model.featureName(feature);
            if opts.Series
                cks = obj.seriesConditions(obj.seriesOfCondition(ck));
            else
                cks = ck;
            end
            lab = sprintf('Reject %s above %s',feature, ...
                mabr.ui.analysis.Model.featureValueText(valueV,feature));
            keys = obj.seriesConditions(obj.seriesOfCondition(ck));
            if isempty(keys), keys = cks; end
            obj.runJob(lab,@(sink) obj.rejectWork(lab,keys,sink, ...
                @(S) obj.rejectAboveIn(S,cks,valueV,feature)));
            rep = obj.LastMessage;
        end

        function clearManualRejections(obj,scope)
            % Remove manual rejections and restores: "condition" (current)
            % or "session".
            arguments
                obj
                scope (1,1) string {mustBeMember(scope,["condition","session"])} = "condition"
            end
            obj.assertMutable();
            obj.ensureRaw();
            if ~obj.Session.HasSweeps, return; end
            if scope == "condition"
                ck = obj.Selection.ConditionKey;
                if ck == "", error('mabr:ui:analysis:noCondition','Select a condition first.'); end
                keys = obj.seriesConditions(obj.seriesOfCondition(ck));
                lab = "Clear manual rejections (" + obj.conditionLabel(ck) + ")";
                fcn = @(S) S.clearManualRejections(ck);
            else
                keys = strings(0,1);
                lab = "Clear manual rejections (session)";
                fcn = @(S) S.clearManualRejections([]);
            end
            obj.runJob(lab,@(sink) obj.rejectWork(lab,keys,sink,fcn));
        end

        % =================================================================
        %  Files, labels, pools
        % =================================================================
        function stageFileUse(obj,fileIds,tf)
            % Stage files to use (true) or leave out (false); applyFileUse
            % re-segments, discardFileUse forgets.
            arguments
                obj
                fileIds string
                tf logical
            end
            obj.assertSession();
            fileIds = reshape(fileIds,[],1);
            tf = reshape(tf,[],1);
            if isscalar(tf), tf = repmat(tf,numel(fileIds),1); end
            P = obj.PendingFileUse;
            for i = 1:numel(fileIds)
                k = find(P.FileIds == fileIds(i),1);
                if isempty(k)
                    P.FileIds(end+1,1) = fileIds(i);
                    P.Use(end+1,1) = tf(i);
                else
                    P.Use(k) = tf(i);
                end
            end
            % a staged value equal to the file's current use is no change
            cur = obj.currentFileUse(P.FileIds);
            keep = P.Use ~= cur;
            P.FileIds = P.FileIds(keep);
            P.Use = P.Use(keep);
            obj.PendingFileUse = P;
            n = numel(P.FileIds);
            if n == 0
                txt = "";
            else
                txt = sprintf('%d change(s) — Apply re-segments the affected conditions (%s)', ...
                    n,mabr.ui.analysis.Style.formatSeconds(obj.estimateSeconds("segment")));
            end
            obj.ev("StatusChanged","files","stageFileUse",Text=txt);
        end

        function applyFileUse(obj)
            % Apply the staged file selection (re-segments what it touches).
            obj.assertMutable();
            P = obj.PendingFileUse;
            if isempty(P.FileIds)
                obj.say("No file changes to apply.",0,"applyFileUse");
                return
            end
            obj.ensureRaw();
            if ~obj.Session.HasSweeps, return; end
            lab = sprintf('Use files (%d change(s))',numel(P.FileIds));
            obj.runJob("Re-segmenting",@(sink) obj.fileUseWork(P,lab,sink));
        end

        function discardFileUse(obj)
            % Forget the staged file selection.
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            obj.ev("StatusChanged","files","discardFileUse",Text="");
        end

        function useOnly(obj,kind)
            % Stage a whole-session file selection: "all", "conventional",
            % "interleaved", "skipShort", or one RunGroup label.
            arguments
                obj
                kind (1,1) string
            end
            obj.assertSession();
            F = obj.Session.Files;
            if isempty(F) || height(F) == 0, return; end
            ids = string(F.FileId);
            switch kind
                case "all"
                    use = true(numel(ids),1);
                case {"conventional","interleaved"}
                    % (refused, with the cause, where it would leave nothing
                    % to analyse or change nothing)
                    use = string(F.AcqMode) == kind;
                    if ~any(use)
                        obj.say("This session has no " + kind + " runs: nothing was staged.",1,"useOnly");
                        return
                    end
                    if all(use)
                        obj.say("Every run of this session is " + kind + " already.",0,"useOnly");
                        return
                    end
                case "skipShort"
                    use = ~logical(F.Short);
                otherwise
                    use = string(F.RunGroup) == kind;
            end
            obj.stageFileUse(ids,use);
        end

        function setSessionOverrides(obj,key,ov)
            % Per-session overrides (NaN = none: the settings' own), stored
            % in the project: struct with any of InputFullScale (V),
            % AmplifierGain (V/V), TimeOffset (ms) and ConductionDelay (ms,
            % Project ConductionDelayOverride). Unit overrides make
            % segmentation out of date; a new TimeOffset or ConductionDelay
            % moves the latency offset (latencyOffset) and the open
            % session's peaks are re-picked at once.
            arguments
                obj
                key (1,1) string
                ov (1,1) struct
            end
            obj.assertNotBusy();
            obj.requireRoot();
            obj.runJob("Applying overrides",@(sink) obj.overridesWork(key,ov));
        end

        function note = label(obj,keys,name,value)
            % Set a label (Timepoint, Group, InStudy, Comment, a free
            % column, ...) of sessions or subjects -- Project.label, undoable.
            %   note  (returned) the coercion note ("" when none)
            arguments
                obj
                keys string
                name (1,1) string
                value
            end
            note = obj.setLabel(keys,name,value,"Set " + name,"","label");
        end

        function setHidden(obj,keys,tf)
            % Exclude sessions from the study and hide them from the
            % browser (TF true), or show them again (false): the project's
            % Hidden label (see HIDDEN in mabr.analysis.Project), one
            % undoable step. Their In study label is left alone, so showing
            % a session again puts it back exactly as it was; while hidden
            % it is out of the study, out of the "in study" and "all"
            % scopes of a batch, an export and a review, and listed in the
            % browser only under Show ▸ Hidden. A pool is a key like any
            % other; hiding a subject means hiding its sessions.
            arguments
                obj
                keys string
                tf (1,1) logical
            end
            obj.assertNotBusy();
            obj.requireRoot();
            keys = reshape(keys,[],1);
            keys = unique(keys(~ismissing(keys) & keys ~= ""),'stable');
            n = numel(keys);
            if n == 0
                if tf, t = "Select the sessions to hide first."; else, t = "Select the hidden sessions to unhide first."; end
                obj.say(t,0,"setHidden");
                return
            end
            if n == 1, what = "1 session"; else, what = n + " sessions"; end
            if tf
                undo = "Hide " + what;
                done = "Hid " + what + ": out of the study, and listed only under Show ▸ Hidden";
            else
                undo = "Unhide " + what;
                done = "Unhid " + what + ": listed again, and in the study as their In study tick says";
            end
            obj.setLabel(keys,"Hidden",tf,undo,done,"setHidden");
        end

        function addColumn(obj,name,level,type)
            % A free label column ("subject" or "session" level; "text" or
            % "number").
            arguments
                obj
                name (1,1) string
                level (1,1) string {mustBeMember(level,["subject","session"])} = "session"
                type (1,1) string {mustBeMember(type,["text","number"])} = "text"
            end
            obj.assertNotBusy();
            obj.requireRoot();
            obj.Project.addColumn(name,level,type);
            e = obj.newEntry("Add column " + name,"columns");
            e.Name = name; e.Level = level; e.Type = type;
            e.Op = "add";
            obj.pushUndo(e);
            obj.markDirty("project");
            obj.ev("ProjectChanged","columns","addColumn",Keys=name);
            obj.ev("StatusChanged","save","addColumn",Text="Column " + name + " added — Ctrl+Z to undo");
        end

        function removeColumn(obj,name)
            % Remove a free label column (its values come back with Ctrl+Z).
            arguments
                obj
                name (1,1) string
            end
            obj.assertNotBusy();
            obj.requireRoot();
            info = obj.columnInfo(name);
            keys = obj.columnKeys(info.Level);
            before = obj.labelValues(keys,name);
            obj.Project.removeColumn(name);
            e = obj.newEntry("Remove column " + name,"columns");
            e.Name = name; e.Level = info.Level; e.Type = info.Type; e.Levels = info.Levels;
            e.Keys = keys; e.Before = before;
            e.Op = "remove";
            obj.pushUndo(e);
            obj.ViewCache = [];
            obj.markDirty("project");
            obj.ev("ProjectChanged","columns","removeColumn",Keys=name);
            obj.ev("StatusChanged","save","removeColumn",Text="Column " + name + " removed — Ctrl+Z to undo");
        end

        function setLevels(obj,name,levels)
            % The order of a label column's values (e.g. the timepoints).
            arguments
                obj
                name (1,1) string
                levels string
            end
            obj.assertNotBusy();
            obj.requireRoot();
            info = obj.columnInfo(name);
            obj.Project.setLevels(name,reshape(levels,1,[]));
            e = obj.newEntry("Order of " + name,"columns");
            e.Name = name; e.Before = info.Levels; e.After = reshape(levels,1,[]);
            e.Op = "levels";
            obj.pushUndo(e);
            obj.ViewCache = [];
            obj.markDirty("project");
            obj.ev("ProjectChanged","columns","setLevels",Keys=name);
            obj.ev("StatusChanged","save","setLevels",Text="Order of " + name + " changed — Ctrl+Z to undo");
        end

        function setInStudy(obj,keys,tf)
            % Use the sessions in the study (or not).
            arguments
                obj
                keys string
                tf (1,1) logical
            end
            obj.label(keys,"InStudy",tf);
        end

        function setDuplicatePolicy(obj,p)
            % How duplicated study units are resolved: "most-sweeps",
            % "latest" or "mean".
            arguments
                obj
                p (1,1) string {mustBeMember(p,["most-sweeps","latest","mean"])}
            end
            obj.assertNotBusy();
            obj.requireRoot();
            old = string(obj.Project.DuplicatePolicy);
            obj.Project.setDuplicatePolicy(p);
            e = obj.newEntry("Duplicates: " + p,"property");
            e.Name = "DuplicatePolicy"; e.Before = old; e.After = p;
            obj.pushUndo(e);
            obj.ViewCache = [];
            obj.markDirty("project");
            obj.ev("ProjectChanged","labels","setDuplicatePolicy");
            obj.ev("StatusChanged","save","setDuplicatePolicy", ...
                Text="Duplicated sessions now use: " + p + " — Ctrl+Z to undo");
        end

        function key = pool(obj,keys,name)
            % Pool the sweeps of several sessions of one subject as one
            % session ("pool:<hex8>"); NAME "" asks for one.
            arguments
                obj
                keys string
                name (1,1) string = ""
            end
            obj.assertNotBusy();
            obj.requireRoot();
            keys = reshape(keys,[],1);
            key = "";
            if numel(keys) < 2
                obj.say("Select two or more sessions to pool.",1,"pool");
                return
            end
            if name == ""
                v = obj.PromptFcn("Name of the pooled session:","Pool sweeps", ...
                    "Pool " + string(datetime('now','Format','yyMMdd''T''HHmmss')));
                if isempty(v), return; end
                name = string(v);
            end
            key = string(obj.Project.addPool(keys,name));
            e = obj.newEntry("Pool " + name,"pools");
            e.Keys = keys; e.Name = name; e.PoolKey = key; e.Op = "add";
            obj.pushUndo(e);
            obj.ViewCache = [];
            obj.markDirty("project");
            obj.ev("ProjectChanged","pools","pool",Keys=key);
            obj.ev("StatusChanged","save","pool", ...
                Text=sprintf('Pooled %d sessions as "%s" — Ctrl+Z to undo',numel(keys),name));
        end

        function unpool(obj,key)
            % Dissolve a pool (its members return to the study).
            arguments
                obj
                key (1,1) string = ""
            end
            obj.assertNotBusy();
            obj.requireRoot();
            if key == "", key = obj.SessionKey; end
            if ~startsWith(key,"pool:")
                obj.say("That is not a pooled session.",1,"unpool");
                return
            end
            members = string(obj.Project.poolMembers(key));
            name = obj.poolName(key);
            if obj.SessionKey == key
                obj.closeSession();
            end
            obj.Project.removePool(key);
            e = obj.newEntry("Unpool " + name,"pools");
            e.Keys = members; e.Name = name; e.PoolKey = key; e.Op = "remove";
            obj.pushUndo(e);
            obj.ViewCache = [];
            obj.markDirty("project");
            obj.ev("ProjectChanged","pools","unpool",Keys=key);
            obj.ev("StatusChanged","save","unpool",Text="Pool " + name + " dissolved — Ctrl+Z to undo");
        end

        % =================================================================
        %  Batch, review, export
        % =================================================================
        function T = batch(obj,keys,opts)
            % Analyse several sessions headlessly (mabr.analysis.Batch).
            % Cancel means "stop after the current session".
            %
            %   keys                  sessions/pools ([] = every session
            %                         that is not hidden)
            %   opts.SkipCurrent      leave up-to-date sessions alone (true)
            %   opts.IncludeTestMode  analyse Test Mode sessions too (false)
            %   opts.SummaryFigure    a summary figure per session (false)
            %   opts.StopOnError      stop at the first failure (false)
            %   opts.Settings         a mabr.analysis.Settings to analyse
            %                         with -- the BatchDialog's profile
            %                         choice; [] = the project's settings.
            %                         It does not become the project's.
            %   opts.MergeInto        the summary this batch re-runs some of
            %                         (BatchReport's Retry failed): its rows
            %                         replace theirs in LastBatch.Summary, so
            %                         the report reopened from Batch ▸ Last
            %                         Batch Report still lists every session
            %   T  (returned) Batch.run's summary table of THIS run ([] when
            %      refused)
            %
            %   LastBatch afterwards: Summary (merged with MergeInto), LogFile
            %   (this run's), Settings (opts.Settings: what a Retry from the
            %   reopened report runs with; [] = the project's).
            arguments
                obj
                keys string = strings(0,1)
                opts.SkipCurrent (1,1) logical = true
                opts.IncludeTestMode (1,1) logical = false
                opts.SummaryFigure (1,1) logical = false
                opts.StopOnError (1,1) logical = false
                opts.Settings = []
                opts.MergeInto = table()
            end
            if ~istable(opts.MergeInto)
                error('mabr:ui:analysis:badSummary','batch MergeInto is a Batch.run summary table.');
            end
            if ~isempty(opts.Settings) && ~isa(opts.Settings,'mabr.analysis.Settings')
                error('mabr:ui:analysis:badSettings','batch Settings is [] or a mabr.analysis.Settings.');
            end
            T = [];
            obj.assertNotBusy();
            obj.requireRoot();
            if obj.isAcquisitionBusy()
                obj.say("Batch disabled while acquiring — run it after the session or in another MATLAB.", ...
                    1,"batch");
                return
            end
            if obj.ReadOnly
                error('mabr:ui:analysis:readOnly', ...
                    'The results folder cannot be written; choose another (Settings ▸ Results Folder…).');
            end
            keys = reshape(keys,[],1);
            if isempty(keys)
                keys = string(obj.Catalog.Sessions.Key);
                keys = keys(~obj.Project.isHidden(keys));
            end
            obj.flush();
            items = obj.batchItems(keys);
            logFile = string(fullfile(obj.resultsFolder(),'logs', ...
                "batch_" + string(datetime('now','Format','yyMMdd''T''HHmmss')) + ".csv"));
            obj.BatchRun = [];
            ok = obj.runJob("Batch analysis",@(sink) obj.batchWork(items,opts,logFile,sink), ...
                Throwing=false,Batch=true);
            if ok && istable(obj.BatchRun)
                T = obj.BatchRun;
            end
        end

        function startReviewQueue(obj,keys,opts)
            % Review the series of several sessions one after the other.
            %
            %   opts.Order           "browser" | "random"
            %   opts.Seed            of the random order (12)
            %   opts.UnreviewedOnly  only sessions with series left to review
            %   opts.Blind           hide subject, folder, date, timepoint
            %                        and group everywhere until endQueue
            arguments
                obj
                keys string = strings(0,1)
                opts.Order (1,1) string {mustBeMember(opts.Order,["browser","random"])} = "browser"
                opts.Seed (1,1) double = 12
                opts.UnreviewedOnly (1,1) logical = true
                opts.Blind (1,1) logical = false
            end
            obj.assertNotBusy();
            obj.requireRoot();
            keys = reshape(keys,[],1);
            if isempty(keys), keys = obj.browserKeys(); end
            if opts.UnreviewedOnly
                keep = arrayfun(@(k) obj.sessionNeedsReview(k),keys);
                keys = keys(keep);
            end
            if isempty(keys)
                obj.say("Nothing to review.",0,"startReviewQueue");
                return
            end
            if opts.Order == "browser"
                order = obj.browserKeys();
                [tf,pos] = ismember(keys,order);
                pos(~tf) = numel(order) + find(~tf);
                [~,ix] = sort(pos);
                keys = keys(ix);
            else
                rs = RandStream('threefry','Seed',opts.Seed);
                keys = keys(randperm(rs,numel(keys)));
            end
            q = struct('Keys',keys,'Position',1,'Order',opts.Order,'Seed',opts.Seed, ...
                'Blind',opts.Blind,'UnreviewedOnly',opts.UnreviewedOnly);
            obj.Queue = q;
            obj.BlindReview = opts.Blind;
            try
                obj.Project.setReviewQueue(q);
                obj.markDirty("project");
            catch me
                mabr.log.vprintf(2,'Model: review queue not stored (%s).',me.message);
            end
            if obj.SessionKey == keys(1) && ~isempty(obj.Session)
                % Already open: openSession would keep it without a word, but
                % the title (blind) and the queue position must still change.
                obj.ev("SessionChanged","all","startReviewQueue",Keys=keys(1));
                obj.ev("SelectionChanged","series","startReviewQueue",Keys=obj.Selection.SeriesKey);
                obj.ev("StatusChanged","queue","startReviewQueue", ...
                    Text=sprintf('Review queue: %d session(s).',numel(keys)));
            else
                obj.openSession(keys(1));
            end
        end

        function nextInQueue(obj,step)
            % The next (+1) / previous (-1) session of the review queue.
            arguments
                obj
                step (1,1) double = 1
            end
            if isempty(obj.Queue)
                obj.say("No review queue is running.",0,"nextInQueue");
                return
            end
            q = obj.Queue;
            j = q.Position + sign(step);
            if j < 1
                obj.say("This is the first item of the review queue.",0,"nextInQueue");
                return
            end
            if j > numel(q.Keys)
                obj.say(sprintf('End of the review queue (%d sessions).',numel(q.Keys)),0,"nextInQueue");
                return
            end
            q.Position = j;
            obj.Queue = q;
            obj.openSession(q.Keys(j));
        end

        function endQueue(obj)
            % Leave the review queue (and blind review).
            obj.Queue = [];
            obj.BlindReview = false;
            try
                if ~isempty(obj.Project)
                    obj.Project.setReviewQueue(struct('Keys',strings(0,1),'Position',0, ...
                        'Order',"",'Seed',1,'Blind',false,'UnreviewedOnly',false));
                    obj.markDirty("project");
                end
            catch me
                mabr.log.vprintf(2,'Model: review queue not cleared (%s).',me.message);
            end
            obj.ev("SessionChanged","all","endQueue",Keys=obj.SessionKey);
            obj.ev("SelectionChanged","series","endQueue");
            obj.ev("StatusChanged","queue","endQueue",Text="Review ended.");
        end

        function files = export(obj,opts)
            % Write the export tables (mabr.analysis.Export) for a scope.
            %
            %   opts  the ExportDialog.read() struct: Scope ("current" |
            %         "selected" | "instudy" | "all"), Keys, Tables, Formats,
            %         ThresholdsAll, OnlyReviewed, IncludeExcluded,
            %         IncludeTestMode, WaveformWindow, RScript, Script,
            %         Folder ("" = <ResultsFolder>/exports/<stamp>)
            %   files (returned) Export.write's table of files written
            arguments
                obj
                opts (1,1) struct = struct()
            end
            files = table();
            obj.assertNotBusy();
            obj.requireRoot();
            if ~obj.acquisitionOk(), return; end
            obj.flush();
            o = mabr.ui.analysis.Model.exportDefaults(opts);
            keys = obj.scopeKeys(o.Scope,o.Keys);
            if isempty(keys)
                obj.say("Nothing to export: no session in that scope has results.",1,"export");
                return
            end
            folder = o.Folder;
            if folder == ""
                % the default is a stamped folder in the results store; a
                % store that cannot be written (read-only) asks where else,
                % and refuses -- naming the store -- when told nowhere
                store = obj.resultsFolder();
                if obj.ReadOnly || ~mabr.ui.analysis.Model.canWrite(store)
                    pick = "";
                    try
                        pick = string(obj.PickFolderFcn(char(store), ...
                            "The results folder cannot be written — choose a folder for the export"));
                    catch
                    end
                    if isempty(pick) || pick == ""
                        obj.say("Nothing exported: the results folder " + store + " cannot be written. " + ...
                            "Choose a folder in Export… (Folder) and export again.",1,"export");
                        return
                    end
                    folder = string(fullfile(pick,string(datetime('now','Format','yyMMdd''T''HHmmss'))));
                else
                    folder = string(fullfile(store,'exports', ...
                        string(datetime('now','Format','yyMMdd''T''HHmmss'))));
                end
            end
            try
                ok = obj.runJob("Exporting",@(sink) obj.exportWork(keys,o,folder,sink));
            catch me
                obj.say("Export failed: " + string(me.message),2,"export");
                rethrow(me);
            end
            if ok
                files = obj.LastExport.Files;
                obj.LastExportFolder = folder;
            end
        end

        function files = exportAgain(obj)
            % The last export's options again, into a new stamped folder.
            files = table();
            if isempty(obj.LastExport)
                obj.say("Nothing has been exported yet — use Export… (Ctrl+E).",0,"exportAgain");
                return
            end
            o = obj.LastExport.Options;
            o.Folder = "";
            files = obj.export(o);
        end

        function file = exportScript(obj,opts)
            % Write a MATLAB script that reproduces this analysis without the
            % app (mabr.analysis.ScriptWriter): the open session, or the
            % browser's selection / the in-study sessions as a study script.
            %
            %   opts.Keys     the sessions ([] = the open session, else the
            %                 in-study sessions)
            %   opts.Study    true: the in-study sessions as a study script,
            %                 whatever is open
            %   opts.File     destination ("" = ask, starting at
            %                 <ResultsFolder>/scripts/<name>_replicate.m)
            %   opts.Open     open it in the editor (default: Interactive)
            %   file          (returned) the file written ("" = cancelled)
            arguments
                obj
                opts.Keys string = strings(0,1)
                opts.Study (1,1) logical = false
                opts.File (1,1) string = ""
                opts.Open = []
                opts.IncludeExport (1,1) logical = true
            end
            file = "";
            obj.requireRoot();
            obj.assertNotBusy();
            if ~mabr.ui.analysis.Model.hasClass("mabr.analysis.ScriptWriter")
                obj.say("Script export is not available in this MABR (mabr.analysis.ScriptWriter is missing).", ...
                    2,"exportScript");
                return
            end
            obj.flush();
            keys = reshape(opts.Keys,[],1);
            if opts.Study, keys = strings(0,1); end
            single = isempty(keys) && ~isempty(obj.Session) && ~opts.Study;
            fromStudy = false;
            if single
                name = obj.flatKey(obj.SessionKey);
            else
                if isempty(keys)
                    keys = obj.scopeKeys("instudy",strings(0,1));
                    fromStudy = true;
                end
                if isempty(keys)
                    obj.say("No analysed session to write a script for.",1,"exportScript");
                    return
                end
                name = "study";
            end
            file = opts.File;
            if file == ""
                % a script runs by its name, so the suggestion is a valid one
                nm = string(matlab.lang.makeValidName(char(name + "_replicate")));
                def = string(fullfile(obj.resultsFolder(),'scripts',nm + ".m"));
                file = string(obj.PickFileFcn("*.m","Export analysis script","save",def));
                if strlength(file) == 0, file = ""; return; end
            end
            if single
                % The session's labels (subject, timepoint, group, overrides)
                % from the project, so the script's export matches the app's.
                labels = []; notes = [];
                try
                    it = obj.Project.exportItems(obj.SessionKey,obj.Catalog);
                    if ~isempty(it), labels = it(1).Labels; notes = it(1).Notes; end
                catch
                end
                code = mabr.analysis.ScriptWriter.session(obj.Session, ...
                    'Title',"Replicate " + obj.Session.Name,'DataRoot',string(obj.Catalog.Root), ...
                    'IncludeExport',opts.IncludeExport,'Labels',labels,'Notes',notes);
            else
                items = obj.Project.exportItems(keys,obj.Catalog);
                code = mabr.analysis.ScriptWriter.study(items,'Title',"Replicate study", ...
                    'DataRoot',string(obj.Catalog.Root),'IncludeExport',opts.IncludeExport);
            end
            file = string(mabr.analysis.ScriptWriter.write(file,code));
            obj.LastScript = file;
            open = opts.Open;
            if isempty(open), open = obj.Interactive; end
            if logical(open)
                try
                    edit(char(file));
                catch
                end
            end
            % (the status line names what the script replicates)
            if single
                what = "of " + obj.Session.Name;
            elseif fromStudy
                what = "of the study (" + numel(keys) + " sessions)";
            elseif isscalar(keys)
                what = "of " + keys;
            else
                what = "of " + numel(keys) + " selected sessions";
            end
            obj.say("Wrote the replication script " + what + ": " + file,0,"exportScript");
        end

        % =================================================================
        %  Undo, save, misc
        % =================================================================
        function undo(obj)
            % Undo the last edit of this session (or of the project, with
            % no session open).
            obj.assertNotBusy();
            st = obj.stack();
            if isempty(st.Undo)
                obj.say("Nothing to undo.",0,"undo");
                return
            end
            e = st.Undo{end};
            obj.applyEntry(e,"Before");
            st = obj.stack();          % applyEntry may have run a job
            st.Undo(end) = [];
            st.Redo{end+1} = e;
            obj.setStack(st);
            obj.say("Undid " + e.Label + " — Ctrl+Y to redo",0,"undo");
        end

        function [u,r] = undoHistory(obj)
            % The labels of this session's undo and redo stacks, oldest
            % first (what Edit ▸ Undo would take back, in order).
            st = obj.stack();
            u = strings(0,1);
            r = strings(0,1);
            for k = 1:numel(st.Undo), u(end+1,1) = string(st.Undo{k}.Label); end %#ok<AGROW>
            for k = 1:numel(st.Redo), r(end+1,1) = string(st.Redo{k}.Label); end %#ok<AGROW>
        end

        function redo(obj)
            % Redo the last undone edit.
            obj.assertNotBusy();
            st = obj.stack();
            if isempty(st.Redo)
                obj.say("Nothing to redo.",0,"redo");
                return
            end
            e = st.Redo{end};
            obj.applyEntry(e,"After");
            st = obj.stack();
            st.Redo(end) = [];
            st.Undo{end+1} = e;
            obj.setStack(st);
            obj.say("Redid " + e.Label + " — Ctrl+Z to undo",0,"redo");
        end

        function ok = saveNow(obj,opts)
            % Write what is pending now: the session's results file (v2, no
            % sweeps, atomic) and the project. opts.Force overwrites a
            % results file changed elsewhere (keepMine). The two are saved
            % independently: a conflict on the results file does not hold
            % back the project's labels.
            arguments
                obj
                opts.Force (1,1) logical = false
            end
            ok = true;
            obj.stopAutosave();
            if obj.Busy
                obj.restartAutosave();
                return
            end
            needS = obj.SessionDirty && ~isempty(obj.Session) && obj.ResultsFile ~= "";
            if needS || obj.projectDirty()
                obj.ensureProjectSettings();
            end
            needP = obj.projectDirty();
            if ~needS && ~needP
                if obj.SaveState == "pending", obj.setSaveState("saved"); end
                return
            end
            if obj.ReadOnly
                obj.setSaveState("readonly");
                why = "results cannot be written to " + obj.resultsFolder();
                if obj.ReadOnlyWhy ~= "", why = obj.ReadOnlyWhy; end
                obj.ev("StatusChanged","save","saveNow",Level=1,Text="Read-only: " + why + ".");
                ok = false;
                return
            end
            obj.setSaveState("saving");
            if needP
                try
                    obj.Project.save();
                catch me
                    obj.saveFailed(me,string(obj.Project.ResultsFolder));
                    ok = false;
                    return
                end
            end
            if needS
                cur = mabr.ui.analysis.Model.fileStamp(obj.ResultsFile);
                if ~opts.Force && ~mabr.ui.analysis.Model.sameStamp(cur,obj.Stamp)
                    obj.ConflictTime = cur.Time;
                    obj.setSaveState("conflict");
                    obj.ev("StatusChanged","save","saveNow",Level=1, ...
                        Text="This session's results were changed elsewhere (" + ...
                        string(cur.Time,'HH:mm') + "); nothing was overwritten.");
                    ok = false;
                    return
                end
                try
                    obj.writeResults(cur);
                catch me
                    ok = false;
                    obj.saveFailed(me,obj.ResultsFile);
                    return
                end
            end
            obj.ViewCache = [];
            obj.LastSaved = datetime('now');
            obj.setSaveState("saved");
            obj.ev("StatusChanged","save","saveNow");
        end

        function flush(obj)
            % Write any pending save now (session switch, close, batch,
            % export, and tests). A results-file conflict waits for
            % keepMine/loadTheirs, but the project is still saved.
            obj.stopAutosave();
            if obj.Busy, return; end
            if obj.SaveState == "conflict"
                if obj.projectDirty()
                    try
                        obj.Project.save();
                    catch me
                        obj.saveFailed(me,string(obj.Project.ResultsFolder));
                    end
                    if obj.SaveState == "failed" || obj.SaveState == "readonly", return; end
                    obj.setSaveState("conflict");
                end
                return
            end
            if obj.SaveState == "pending" || obj.SaveState == "failed" || ...
                    obj.SessionDirty || obj.projectDirty()
                obj.saveNow();
            end
        end

        function keepMine(obj)
            % Resolve a save conflict by overwriting the file with this
            % session's results.
            obj.assertNotBusy();
            obj.saveNow(Force=true);
        end

        function loadTheirs(obj)
            % Resolve a save conflict by reloading the file (this session's
            % unsaved edits are dropped).
            obj.assertNotBusy();
            obj.assertSession();
            key = obj.SessionKey;
            sel = obj.Selection;
            obj.SessionDirty = false;
            obj.HistoryPending = false;
            obj.setSaveState("saved");
            obj.clearUndo(key);
            obj.openSession(key,Source="results",SeriesKey=sel.SeriesKey,Level=sel.Level);
        end

        function cancel(obj)
            % Ask the running job to stop (between steps; a batch after the
            % current session).
            if ~obj.Busy, return; end
            obj.CancelRequested = true;
            if obj.JobBatch
                obj.say("Stopping after this session…",1,"cancel");
            else
                obj.say("Cancelling…",1,"cancel");
            end
        end

        function s = sessionTitle(obj)
            % "SUBJ-ID-1254 · 14:08 · Tone 6×9 · 54 conditions"; in blind
            % review "Review item 14 / 236".
            if obj.BlindReview && ~isempty(obj.Queue)
                s = "Review item " + obj.Queue.Position + " / " + numel(obj.Queue.Keys);
                return
            end
            if isempty(obj.Session)
                if isempty(obj.Catalog), s = "";
                else, s = "No session open"; end
                return
            end
            S = obj.Session;
            parts = strings(1,0);
            try
                info = obj.sessionInfo(obj.SessionKey);
            catch
                info = struct('Subject',string(S.Subject),'Start',NaT,'Summary',"",'IsPool',false,'Name',S.Name);
            end
            if info.IsPool
                parts(end+1) = "Pool: " + info.Name;
            else
                sub = string(info.Subject);
                if sub == "", sub = string(S.Subject); end
                if sub ~= "", parts(end+1) = sub; end
                if ~isnat(info.Start), parts(end+1) = string(info.Start,'HH:mm'); end
            end
            if string(info.Summary) ~= "", parts(end+1) = string(info.Summary); end
            nc = 0;
            try
                nc = height(S.Conditions);
            catch
            end
            parts(end+1) = nc + " conditions";
            s = strjoin(parts," · ");
        end

        function txt = blindText(obj,txt)
            % TXT with every session's name, folder key and subject (and
            % every pool's) replaced by "…" while blind review is on: the
            % status line and the notification bar must not name what the
            % review hides ("Opened SUBJ-ID-959_Baseline", "Results found in
            % …\SUBJ-ID-1254\MABR_Analysis"). TXT itself otherwise. Every
            % event's Text goes through it (ev), and the app's own status
            % sentences too.
            txt = string(txt);
            if ~obj.BlindReview || isempty(obj.Catalog) || all(strlength(txt) == 0), return; end
            pat = obj.blindPattern();
            if pat == "", return; end
            txt = string(regexprep(cellstr(txt),char(pat),'…','ignorecase'));
        end

        function s = seriesLabel(obj,key)
            % "Tone 8 kHz" (" · interleaved" when the session has both modes).
            s = string(key);
            if isempty(obj.Session) || s == "", return; end
            try
                s = string(obj.Session.seriesLabel(key));
            catch
                s = mabr.ui.analysis.Model.keyLabel(key);
            end
        end

        function s = conditionLabel(obj,key)
            % "8 kHz, 60 dB".
            s = string(key);
            if isempty(obj.Session) || s == "", return; end
            try
                s = string(obj.Session.conditionLabel(key));
            catch
                s = mabr.ui.analysis.Model.keyLabel(key);
            end
        end

        function k = seriesKeys(obj,opts)
            % The open session's series keys in display order, optionally
            % only one stimulus / acquisition mode.
            arguments
                obj
                opts.Stimulus (1,1) string = ""
                opts.AcqMode (1,1) string = ""
            end
            k = strings(0,1);
            S = obj.Session;
            if isempty(S), return; end
            try
                k = reshape(string(S.seriesKeys()),[],1);
            catch
                k = obj.derivedSeriesKeys();
            end
            if opts.Stimulus ~= ""
                k = k(mabr.ui.analysis.Model.keyField(k,"Stimulus") == opts.Stimulus);
            end
            if opts.AcqMode ~= ""
                k = k(mabr.ui.analysis.Model.keyField(k,"AcqMode") == opts.AcqMode);
            end
        end

        function k = seriesConditions(obj,seriesKey)
            % The condition keys of a series, level ascending.
            k = obj.seriesLevels(seriesKey);
        end

        function lp = levelParam(obj)
            % The level parameter of the open session ("" when none).
            lp = "";
            S = obj.Session;
            if isempty(S), return; end
            try
                lp = string(S.LevelParam);
            catch
            end
            if lp == ""
                try
                    lp = string(S.levelParamOrEmpty());
                catch
                    try
                        lp = string(S.levelParam());
                    catch
                        lp = "";
                    end
                end
            end
        end

        function sec = estimateSeconds(obj,fromStep)
            % How long re-running from fromStep should take (a heuristic).
            arguments
                obj
                fromStep (1,1) string = "segment"
            end
            sec = NaN;
            S = obj.Session;
            if isempty(S), return; end
            try
                sec = mabr.analysis.Session.estimateSeconds(obj.Settings,fromStep, ...
                    height(S.Files),height(S.Conditions),numel(obj.seriesKeys()));
            catch
                sec = NaN;
            end
        end

        function tf = isAcquisitionBusy(~)
            % True while MABR acquires in this MATLAB (mabr.ui.App.isAcquiring;
            % false when that is unavailable or no App is open).
            try
                tf = logical(mabr.ui.App.isAcquiring());
            catch
                tf = false;
            end
        end

        function s = resultsPathText(obj)
            % "Results: …/OFC_NoiseExposure/MABR_Analysis" ("" with no root).
            s = "";
            if isempty(obj.Catalog), return; end
            f = obj.resultsFolder();
            parts = split(replace(f,"\","/"),"/");
            parts(parts == "") = [];
            if numel(parts) > 2
                s = "Results: …/" + strjoin(parts(end-1:end),"/");
            else
                s = "Results: " + f;
            end
        end

        % ---- conveniences views share (not in the contract) -------------
        function [o,d,t] = latencyOffset(obj)
            % The open session's latency offset, ms (0 with none open): how
            % much later than the timing pulse the sound reaches the ear --
            % the conduction delay d (the project's per-session override,
            % else the settings') plus the system time offset t (likewise).
            % It is Session.LatencyOffset: the offset the stored peaks were
            % picked with, under the settings of the session's last analysis
            % (the project's settings while it was never analysed). A view
            % converts a raw time x (ms re the timing pulse) to ear time as
            % x - o; mabr.ui.analysis.View.timeAxis/earTime do it for it.
            %   o  (returned) d + t, ms
            %   d  (returned) the conduction delay, ms
            %   t  (returned) the system time offset, ms
            o = 0; d = 0; t = 0;
            S = obj.Session;
            if isempty(S), return; end
            try
                st = S.Settings;
                if isempty(st), st = obj.Settings; end
                d = S.ConductionDelayOverride;
                if ~isfinite(d), d = st.conductionDelay(); end
                t = S.TimeOffset;
                if ~isfinite(t), t = st.TimeOffset; end
                if ~isempty(S.Settings)
                    o = double(S.LatencyOffset);   % the Session's own rule
                else
                    o = d + t;
                end
            catch me
                mabr.log.vprintf(2,'Model: latency offset unknown (%s).',me.message);
                o = 0; d = 0; t = 0;
            end
            if ~isfinite(o), o = 0; end
            if ~isfinite(d), d = 0; end
            if ~isfinite(t), t = 0; end
        end

        function txt = latencyText(obj)
            % The open session's latency reference in words, for a time
            % axis' tooltip or subtitle -- "Latencies re sound arrival: 0.29
            % ms conduction delay (10 cm at 343 m/s)." (the settings'
            % Settings.describe sentence when the session overrides
            % nothing), else naming this session's own override; "" when the
            % offset is 0.
            txt = "";
            [o,d,t] = obj.latencyOffset();
            if o == 0 && d == 0 && t == 0, return; end
            S = obj.Session;
            st = obj.Settings;
            dOv = NaN; tOv = NaN;
            try
                if ~isempty(S.Settings), st = S.Settings; end
                dOv = S.ConductionDelayOverride;
                tOv = S.TimeOffset;
            catch
            end
            if ~isfinite(dOv) && ~isfinite(tOv)
                try
                    L = splitlines(string(st.describe()));
                    L = L(startsWith(L,"Latencies re"));
                    if ~isempty(L), txt = L(1); return; end
                catch
                end
            end
            src = @(ov) mabr.ui.analysis.Model.pick(isfinite(ov),"this session's override","settings");
            f2 = @(v) string(sprintf('%.2f',v));
            if d ~= 0
                txt = "Latencies re sound arrival: " + f2(d) + " ms conduction delay (" + src(dOv) + ")";
                if t ~= 0
                    txt = txt + " plus a " + string(sprintf('%g',t)) + " ms system offset (" + ...
                        src(tOv) + "), " + f2(o) + " ms in all";
                end
            else
                txt = "Latencies re stimulus onset, less a " + string(sprintf('%g',t)) + ...
                    " ms system offset (" + src(tOv) + ")";
            end
            txt = txt + ".";
        end

        function f = resultsFolder(obj)
            % The results store in force ("" with no root).
            f = "";
            if ~isempty(obj.Catalog)
                f = string(obj.Catalog.ResultsFolder);
            end
        end

        function keys = allKeys(obj)
            % Every session and pool of the open folder but the hidden ones
            % -- what an "all sessions" scope means (a hidden session is
            % reached only by selecting it under Show ▸ Hidden).
            keys = strings(0,1);
            if isempty(obj.Catalog), return; end
            keys = reshape(string(obj.Catalog.Sessions.Key),[],1);
            if isempty(obj.Project), return; end
            try
                keys = [keys; reshape(string(obj.Project.Pools.Key),[],1)];
            catch
            end
            try
                keys = keys(~obj.Project.isHidden(keys));
            catch
            end
        end

        function V = projectView(obj)
            % Project.view(Catalog,Settings), cached until something it
            % depends on changes.
            V = table();
            if isempty(obj.Project) || isempty(obj.Catalog), return; end
            if isempty(obj.ViewCache)
                try
                    obj.ViewCache = obj.Project.view(obj.Catalog,obj.Settings);
                catch me
                    mabr.log.vprintf(2,'Model: Project.view failed (%s).',me.message);
                    obj.ViewCache = table();
                end
            end
            V = obj.ViewCache;
        end

        function info = sessionInfo(obj,key)
            % Where a session lives: struct Key, Paths, Members, Name,
            % IsPool, ResultsFile, Subject, Start, Summary, TestMode.
            arguments
                obj
                key (1,1) string
            end
            obj.requireRoot();
            c = obj.Catalog;
            info = struct('Key',key,'Paths',strings(0,1),'Members',strings(0,1),'Name',key, ...
                'IsPool',false,'ResultsFile',"",'Subject',"",'Start',NaT,'Summary',"", ...
                'TestMode',"none");
            T = c.Sessions;
            if startsWith(key,"pool:")
                m = reshape(string(obj.Project.poolMembers(key)),[],1);
                [tf,rows] = ismember(m,string(T.Key));
                if ~all(tf)
                    error('mabr:ui:analysis:unknownSession', ...
                        'Pool %s names sessions this folder does not hold.',key);
                end
                info.Paths   = reshape(string(T.Path(rows)),[],1);
                info.Members = m;
                info.IsPool  = true;
                info.Name    = obj.poolName(key);
                info.ResultsFile = string(c.resultsFile(m));
                info.Subject = string(T.Subject(rows(1)));
                info.Start   = min(T.Start(rows));
                info.Summary = "pool of " + numel(m) + " sessions";
                tm = string(T.TestMode(rows));
                if all(tm == "all"), info.TestMode = "all";
                elseif any(tm ~= "none"), info.TestMode = "some"; end
            else
                r = find(string(T.Key) == key,1);
                if isempty(r)
                    error('mabr:ui:analysis:unknownSession','No session "%s" in this folder.',key);
                end
                info.Paths   = string(T.Path(r));
                info.Members = key;
                info.Name    = string(T.Name(r));
                info.ResultsFile = string(c.resultsFile(key));
                info.Subject = string(T.Subject(r));
                info.Start   = T.Start(r);
                info.Summary = string(T.Summary(r));
                info.TestMode = string(T.TestMode(r));
            end
        end

        function tf = hasResults(obj,key)
            % True when the session (or pool) has a results file.
            tf = false;
            try
                tf = isfile(obj.sessionInfo(key).ResultsFile);
            catch
            end
        end

        function rep = revertSeries(obj,seriesKey)
            % Every edit of one series undone at once: its decision, note,
            % peak edits and detection overrides (one undo step).
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            sk = obj.targetSeries(seriesKey);
            ck = obj.seriesConditions(sk);
            rep = obj.applyEdit("Revert series (" + obj.seriesLabel(sk) + ")", ...
                @(S) mabr.ui.analysis.Model.revertIn(S,sk,ck),"all",sk,"revertSeries", ...
                obj.seriesLabel(sk) + " reverted to the automatic analysis");
        end

        function clearAllEdits(obj)
            % Every manual edit of the open session removed (after asking).
            obj.assertMutable();
            c = obj.confirm("Clear every manual edit of this session — decisions, notes, peak " + ...
                "edits, detection overrides and manual rejections? (Ctrl+Z brings them back.)", ...
                "Clear all manual edits",["Clear all","Cancel"],"Cancel");
            if c ~= "Clear all", return; end
            S = obj.Session;
            needsRaw = ~isempty(S.ManualRejections) && height(S.ManualRejections) > 0;
            if needsRaw
                obj.ensureRaw();
                if ~S.HasSweeps, return; end
            end
            keys = obj.seriesKeys();
            lab = "Clear all manual edits";
            obj.runJob(lab,@(sink) obj.rejectWork(lab,strings(0,1),sink, ...
                @(S) mabr.ui.analysis.Model.clearAllIn(S,keys,needsRaw)));
        end

        function k = levelMemoryKey(obj,sk)
            % The LevelMemory key of series SK in the open session. Memory is
            % per SESSION and series: sessions share series keys (every 4 kHz
            % conventional tone series is "Stimulus=Tone|AcqMode=conventional|
            % Frequency=4"), and a level remembered in one must not open the
            % next away from its own threshold.
            k = char(string(obj.SessionKey) + "||" + string(sk));
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- events and messages ----------------------------------------
        function ev(obj,name,what,source,opts)
            arguments
                obj
                name (1,1) string
                what (1,1) string
                source (1,1) string = ""
                opts.Keys = strings(0,1)
                opts.Text (1,1) string = ""
                opts.Level (1,1) double = 0
            end
            if opts.Text ~= "" && obj.BlindReview
                opts.Text = obj.blindText(opts.Text);
            end
            if opts.Text ~= ""
                obj.LastMessage = opts.Text;
                obj.LastMessageLevel = opts.Level;
            end
            notify(obj,char(name),mabr.ui.analysis.ChangeData(what,'Keys',opts.Keys, ...
                'Text',opts.Text,'Level',opts.Level,'Source',source));
        end

        function say(obj,text,level,source)
            % A status sentence: StatusChanged(message).
            if nargin < 3, level = 0; end
            if nargin < 4, source = ""; end
            obj.ev("StatusChanged","message",string(source),Text=string(text),Level=level);
        end

        function onSessionMessage(obj,level,text)
            % Session.MessageFcn: every message the session appends.
            switch string(level)
                case "warning", l = 1;
                case "error",   l = 2;
                otherwise,      l = 0;
            end
            try
                obj.ev("StatusChanged","message","Session",Text=string(text),Level=l);
            catch
            end
        end

        function setSaveState(obj,s)
            obj.SaveState = s;
        end

        % ---- guards ------------------------------------------------------
        function assertNotBusy(obj)
            if obj.Busy
                error('mabr:ui:analysis:busy', ...
                    'The analysis app is busy (%s); try again when it ends.',obj.JobTitle);
            end
        end

        function requireRoot(obj)
            if isempty(obj.Catalog)
                error('mabr:ui:analysis:noRoot','Open a data folder first.');
            end
        end

        function assertSession(obj)
            if isempty(obj.Session)
                error('mabr:ui:analysis:noSession','Open a session first.');
            end
        end

        function assertMutable(obj)
            obj.assertNotBusy();
            obj.assertSession();
        end

        function ok = acquisitionOk(obj)
            % Ask before heavy work while MABR acquires in this MATLAB.
            ok = true;
            if ~obj.isAcquisitionBusy(), return; end
            c = obj.confirm("MABR is acquiring in this MATLAB. Analysis here will freeze its live " + ...
                "view until it finishes.","Acquisition running",["Run anyway","Cancel"],"Cancel");
            ok = c == "Run anyway";
        end

        function c = confirm(obj,msg,title,options,default)
            try
                c = string(obj.ConfirmFcn(msg,title,options,default));
            catch me
                mabr.log.vprintf(2,'Model: ConfirmFcn failed (%s).',me.message);
                c = string(default);
            end
            if isempty(c) || ismissing(c), c = string(options(end)); end
        end

        % ---- jobs --------------------------------------------------------
        function ok = runJob(obj,title,fcn,opts)
            % Busy -> progress -> fcn(sink) -> idle. A cancel returns false;
            % any other error is rethrown once the Model is idle again.
            arguments
                obj
                title (1,1) string
                fcn
                opts.Throwing (1,1) logical = true
                opts.Batch (1,1) logical = false
                opts.Outer (1,1) string = ""
            end
            obj.assertNotBusy();
            obj.Busy = true;
            obj.CancelRequested = false;
            obj.JobTitle = title;
            obj.JobStep = "";
            obj.JobK = 0;
            obj.JobN = 0;
            obj.JobOuter = opts.Outer;
            obj.JobBatch = opts.Batch;
            obj.SinkClock = tic;
            obj.SinkLast = -Inf;
            obj.ev("BusyChanged","busy","runJob",Text=title);
            h = [];
            try
                h = obj.ProgressFcn("open",title);
            catch me
                mabr.log.vprintf(2,'Model: progress window failed (%s).',me.message);
            end
            if isempty(h), h = obj.silentProgress(); end
            obj.ProgressHandle = h;
            ok = false;
            cancelled = false;
            err = [];
            throwing = opts.Throwing;
            try
                fcn(@(msg,k,n) obj.sink(msg,k,n,throwing));
                ok = true;
            catch me
                if strcmp(me.identifier,'mabr:analysis:cancelled')
                    cancelled = true;
                else
                    err = me;
                end
            end
            try
                h.close();
            catch
            end
            obj.ProgressHandle = [];
            step = obj.JobStep; k = obj.JobK; n = obj.JobN;
            obj.Busy = false;
            obj.CancelRequested = false;
            obj.JobTitle = "";
            obj.JobBatch = false;
            if cancelled
                if step == ""
                    txt = "Cancelled — nothing changed";
                elseif n > 0
                    txt = sprintf('Cancelled during %s (%d/%d) — nothing changed',step,k,n);
                else
                    txt = "Cancelled during " + step + " — nothing changed";
                end
                obj.say(txt,1,"runJob");
            end
            obj.ev("BusyChanged","idle","runJob");
            if obj.CloseRequested && ~isempty(obj.CloseFcn)
                try
                    obj.CloseFcn();
                catch me2
                    mabr.log.vprintf(2,'Model: close after the job failed (%s).',me2.message);
                end
            end
            if ~isempty(err)
                rethrow(err);
            end
        end

        function sink(obj,msg,k,n,throwing)
            % The progress sink handed to Session/Catalog/Batch.
            obj.JobStep = string(msg);
            obj.JobK = double(k);
            obj.JobN = double(n);
            h = obj.ProgressHandle;
            t = toc(obj.SinkClock);
            if ~isempty(h) && ((t - obj.SinkLast >= 0.1) || (n > 0 && k >= n))
                obj.SinkLast = t;
                outer = obj.JobOuter;
                if outer == "", outer = obj.JobTitle; end
                if n > 0
                    inner = sprintf('%s %d/%d',msg,k,n);
                    frac = min(max(k/n,0),1);
                else
                    inner = string(msg);
                    frac = 0;
                end
                try
                    h.update(outer + newline + inner,frac);
                catch
                end
            end
            if ~obj.CancelRequested && ~isempty(h)
                c = false;
                try
                    c = logical(h.cancelled());
                catch
                end
                if c
                    obj.CancelRequested = true;
                    if ~throwing
                        obj.say("Stopping after this session…",1,"cancel");
                    end
                end
            end
            if obj.CancelRequested && throwing
                error('mabr:analysis:cancelled','Cancelled by user.');
            end
        end

        function h = silentProgress(obj)
            % A progress handle that shows nothing; cancelled() reads
            % CancelRequested (so model.cancel() works without a window).
            h = struct('update',@(text,frac) [], ...
                'cancelled',@() obj.CancelRequested, ...
                'close',@() []);
        end

        function adoptMovedSession(obj,S,key,src,sel)
            % setResultsFolder: the open session, with its unsaved edits, as
            % the open session of the reopened root -- saved into the new
            % store. Its results file there is never read: one already
            % present is a conflict on this first save (Keep mine / Load
            % theirs), not something overwritten silently.
            info = obj.sessionInfo(key);
            obj.Session = S;
            obj.SessionKey = info.Key;
            obj.SessionKeys = info.Members;
            obj.SessionSource = src;
            obj.ResultsFile = info.ResultsFile;
            obj.Stamp = mabr.ui.analysis.Model.fileStamp("");
            obj.SessionDirty = true;
            obj.HistoryPending = false;
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            obj.Selection = obj.initialSelection(sel.SeriesKey,sel.Level,sel);
            obj.updateStatus();
            obj.ev("SessionChanged","all","setResultsFolder",Keys=info.Key);
            obj.ev("SelectionChanged","series","setResultsFolder",Keys=obj.Selection.SeriesKey);
            obj.markDirty("session");
            obj.saveNow();
            if obj.SaveState == "saved"
                obj.say("This session's edits were saved in " + obj.resultsFolder() + ".",0, ...
                    "setResultsFolder");
            end
        end

        % ---- job bodies ----------------------------------------------------
        function openRootWork(obj,path,sink)
            rf = obj.resultsFolderFor(path);
            args = {};
            if obj.CacheFolder ~= "", args = [args {'CacheFolder',obj.CacheFolder}]; end
            if rf ~= "", args = [args {'ResultsFolder',rf}]; end
            c = mabr.analysis.Catalog(path,args{:});
            c.scan('ProgressFcn',sink);
            p = mabr.analysis.Project.open(string(c.ResultsFolder));
            s = obj.settingsFor(p);
            p.ensureSessions(c);
            % a project.mat that cannot be read (or one a newer MABR wrote)
            % is never written back (Project.ReadOnly): say so, and keep
            % this store read-only -- edits made now could not be kept
            projWhy = "";
            try
                if p.ReadOnly
                    projWhy = "project.mat could not be used (" + strjoin(string(p.Warnings),"; ") + ...
                        ") — labels, pools and exclusions are not shown and nothing is saved here";
                end
            catch
            end
            % commit
            obj.Catalog = c;
            obj.Project = p;
            obj.Settings = s;
            obj.Session = [];
            obj.SessionKey = "";
            obj.SessionKeys = strings(0,1);
            obj.SessionSource = "none";
            obj.ResultsFile = "";
            obj.Selection = mabr.ui.analysis.Model.emptySelection();
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            obj.Queue = [];
            obj.BlindReview = false;
            obj.ReadOnly = projWhy ~= "";
            obj.ReadOnlyWhy = projWhy;
            obj.SaveState = "saved";
            if obj.ReadOnly, obj.SaveState = "readonly"; end
            obj.SessionDirty = false;
            obj.LastOpenError = [];
            obj.ViewCache = [];
            obj.updateStatus();
            obj.ev("RootChanged","all","openRoot",Keys=string(c.Root));
            obj.ev("ProjectChanged","all","openRoot");
            obj.ev("SettingsChanged","all","openRoot");
            [txt,lvl] = obj.scanReport();
            if projWhy ~= ""
                txt = "Read-only: " + projWhy + ". " + txt;
                lvl = max(lvl,1);
            end
            obj.ev("StatusChanged","status","openRoot",Text=txt,Level=lvl);
        end

        function rescanWork(obj,sink)
            c = obj.Catalog;
            c.scan('ProgressFcn',sink);
            obj.Project.ensureSessions(c);
            obj.ViewCache = [];
            obj.updateStatus();
            obj.ev("RootChanged","all","rescan",Keys=string(c.Root));
            obj.ev("ProjectChanged","all","rescan");
            obj.ev("SettingsChanged","all","rescan");
            [txt,lvl] = obj.scanReport();
            obj.ev("StatusChanged","status","rescan",Text=txt,Level=lvl);
        end

        function [txt,lvl] = scanReport(obj)
            c = obj.Catalog;
            lvl = 0;
            nS = 0; nF = 0; bad = 0;
            try
                nS = height(c.Sessions);
                nF = height(c.Files);
                if nF > 0 && ismember('Ok',c.Files.Properties.VariableNames)
                    bad = sum(~c.Files.Ok);
                end
            catch
            end
            if nF == 0
                txt = sprintf(['No .abr files under %s (MABR_Analysis and hidden folders ' ...
                    'are skipped).'],string(c.Root));
                lvl = 1;
            else
                txt = sprintf('%d session(s), %d file(s) under %s.',nS,nF,string(c.Root));
                if bad > 0
                    txt = sprintf('%d files could not be read. %s',bad,txt);
                    lvl = 1;
                end
            end
        end

        function openSessionWork(obj,info,source,opts,prev,sink)
            if source == "results"
                S = mabr.analysis.Session.fromResults(info.ResultsFile,'Verbose',false);
            else
                S = obj.buildRawSession(info,sink);
            end
            stamp = mabr.ui.analysis.Model.fileStamp(info.ResultsFile);
            obj.SavedUnitOverride = obj.unitOverrideOf(S);
            obj.applyProjectOverrides(S,info.Key);
            try
                S.Analyst = obj.Analyst;
            catch
            end
            try
                S.MessageFcn = @(lvl,txt) obj.onSessionMessage(lvl,txt);
            catch
            end
            % commit
            obj.Session = S;
            if string(obj.SessionKey) ~= string(info.Key)
                % Another session keeps the series in view but not the level:
                % that comes from this session's own memory or its threshold.
                prev.Level = NaN;
            end
            obj.SessionKey = info.Key;
            obj.SessionKeys = info.Members;
            obj.SessionSource = source;
            obj.ResultsFile = info.ResultsFile;
            obj.Stamp = stamp;
            obj.SessionDirty = false;
            obj.HistoryPending = false;
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            if obj.ReadOnly, obj.SaveState = "readonly"; else, obj.SaveState = "saved"; end
            if ~isempty(obj.Queue)
                k = find(obj.Queue.Keys == info.Key,1);
                if ~isempty(k)
                    q = obj.Queue;
                    q.Position = k;
                    obj.Queue = q;
                end
            end
            if isKey(obj.FailedText,char(info.Key)) && source == "results"
                remove(obj.FailedText,char(info.Key));
            end
            obj.Selection = obj.initialSelection(opts.SeriesKey,opts.Level,prev);
            obj.updateStatus();
            obj.ev("SessionChanged","all","openSession",Keys=info.Key);
            obj.ev("SelectionChanged","series","openSession",Keys=obj.Selection.SeriesKey);
            if isempty(obj.Queue)
                w = "status";
            else
                w = "queue";
            end
            lvl = 0;
            nm = info.Name;
            if obj.BlindReview && ~isempty(obj.Queue)
                nm = "review item " + obj.Queue.Position + " / " + numel(obj.Queue.Keys);
            end
            txt = "Opened " + nm;
            if source == "results"
                txt = txt + " (results; raw data loads when needed).";
            else
                txt = txt + " from its raw files.";
            end
            if obj.Session.TestMode
                txt = "TEST MODE — " + txt;
                lvl = 1;
            end
            obj.ev("StatusChanged",w,"openSession",Text=txt,Level=lvl);
        end

        function S = buildRawSession(obj,info,sink)
            ov = obj.unitOverrideFor(info.Key);
            excl = strings(0,1);
            R = [];
            if isfile(info.ResultsFile)
                % Reopening an analysed session from its raw files keeps its
                % edits (and its file selection) -- when they can be read: an
                % unreadable results file is copied aside into .history
                % (<flat>_unreadable_<stamp>.mat, never pruned) before a
                % save can write over it, and the session opens without them.
                try
                    R = load(char(info.ResultsFile));
                    try
                        excl = reshape(string(R.Summary.Exclude),[],1);
                    catch
                    end
                catch me
                    R = [];
                    kept = obj.keepUnreadable(info);
                    mabr.log.vprintf(1,'Model: the earlier edits of %s could not be read (%s)%s.', ...
                        info.Name,me.message,kept);
                end
            end
            args = {'Name',info.Name,'Key',info.Key,'FolderKeys',info.Members,'Verbose',false, ...
                'KeepTraces',true,'Exclude',excl,'UnitOverride',ov,'Analyst',obj.Analyst, ...
                'Parse',false,'Force',info.IsPool};
            S = mabr.analysis.Session(info.Paths,args{:});
            S.ProgressFcn = sink;
            S.parse();
            if ~isempty(R)
                S.adoptEdits(R);
            end
            S.analyze(obj.Settings,'Steps',["segment","reject"]);
            S.ProgressFcn = [];
        end

        function ensureRawWork(obj,sink)
            S = obj.Session;
            S.ProgressFcn = sink;
            c = onCleanup(@() mabr.ui.analysis.Model.clearSink(S));
            S.loadRaw();
            clear c
            obj.SessionSource = "raw";
            obj.updateStatus();
            obj.ev("ResultsChanged","all","ensureRaw",Keys=obj.SessionKey);
            obj.ev("StatusChanged","status","ensureRaw",Text="Raw data loaded.");
        end

        function analyzeWork(obj,from,keys,sink,t0)
            S = obj.Session;
            S.ProgressFcn = sink;
            c = onCleanup(@() mabr.ui.analysis.Model.clearSink(S));
            args = {'From',from};
            if ~isempty(keys), args = [args {'Keys',keys}]; end
            rep = S.analyze(obj.Settings,args{:});
            clear c
            obj.clearUndo(obj.SessionKey);
            obj.HistoryPending = true;
            obj.SessionDirty = true;
            obj.SaveState = "pending";
            if isKey(obj.FailedText,char(obj.SessionKey))
                remove(obj.FailedText,char(obj.SessionKey));
            end
            obj.ViewCache = [];
            obj.updateStatus();
            obj.ev("ResultsChanged","all","analyze",Keys=obj.SessionKey);
            st = "ok";
            try
                st = string(rep.Status);
            catch
            end
            % in words: what was re-run (not the step's name), how long it
            % took, and the analysis' status only when it is not plain ok
            switch string(from)
                case "segment",    what = "Analysed in %s (all steps)";
                case "reject",     what = "Re-analysed from artifact rejection on in %s";
                case "detect",     what = "Re-ran detection, thresholds and peaks in %s";
                case "measure",    what = "Re-ran the single-trial measures, thresholds and peaks in %s";
                case "thresholds", what = "Re-fitted the thresholds and re-picked the peaks in %s";
                case "peaks",      what = "Re-picked the peaks in %s";
                otherwise,         what = "Analysed in %s";
            end
            secs = toc(t0);
            if secs < 1, dur = "under 1 s"; else, dur = sprintf('%.0f s',secs); end
            txt = sprintf(what,dur);
            if st ~= "ok"
                % ("ok (no thresholds)" -> "(no thresholds)")
                txt = txt + " (" + string(regexprep(char(st),'^ok\s*\((.*)\)$','$1')) + ")";
            end
            txt = txt + " — undo history cleared.";
            obj.ev("StatusChanged","status","analyze",Text=txt);
        end

        function analysisFailed(obj,me,state0)
            % An analysis that errored: the session says so ("Failed: ...")
            % until it is analysed again; steps that finished before the
            % error are kept, as after a cancel.
            if isempty(obj.Session), return; end
            obj.FailedText(char(obj.SessionKey)) = string(me.message);
            if ~isequaln(obj.stepStateOf(obj.Session),state0)
                obj.SessionDirty = true;
                obj.clearUndo(obj.SessionKey);
                obj.ev("ResultsChanged","all","analyze",Keys=obj.SessionKey);
            end
            obj.updateStatus();
            obj.ev("StatusChanged","status","analyze",Level=2, ...
                Text="Analysis failed: " + string(me.message));
        end

        function afterCancelledAnalysis(obj,state0)
            % A cancel between steps leaves the steps before it re-run.
            S = obj.Session;
            if isempty(S), return; end
            if ~isequaln(obj.stepStateOf(S),state0)
                obj.SessionDirty = true;
                obj.HistoryPending = true;
                obj.clearUndo(obj.SessionKey);
                obj.updateStatus();
                obj.ev("ResultsChanged","all","analyze",Keys=obj.SessionKey);
                obj.say("Cancelled — the steps that finished were kept; the rest is out of date.",1,"analyze");
                obj.markDirty("session");
            end
        end

        function bootstrapWork(obj,args,keys,sink)
            S = obj.Session;
            before = S.editSnapshot();
            S.ProgressFcn = sink;
            c = onCleanup(@() mabr.ui.analysis.Model.clearSink(S));
            S.pickPeaks(args{:});
            clear c
            after = S.editSnapshot();
            e = obj.newEntry("Bootstrap peaks","session");
            e.Before = before; e.After = after; e.What = "peaks"; e.Keys = keys;
            obj.pushUndo(e);
            obj.markDirty("session");
            obj.ev("ResultsChanged","peaks","bootstrapPeaks",Keys=keys);
            obj.ev("StatusChanged","save","bootstrapPeaks",Text="Peak confidence intervals computed.");
        end

        function rejectWork(obj,lab,keys,sink,fcn)
            % A data edit (rejection, file use) inside a job, undoable.
            S = obj.Session;
            before = S.editSnapshot();
            S.ProgressFcn = sink;
            c = onCleanup(@() mabr.ui.analysis.Model.clearSink(S));
            out = mabr.ui.analysis.Model.callReport(fcn,S);
            clear c
            after = S.editSnapshot();
            e = obj.newEntry(lab,"session");
            e.Before = before; e.After = after; e.What = "rejection"; e.Keys = keys;
            e.NeedsRaw = true;
            obj.pushUndo(e);
            obj.markDirty("session");
            obj.updateStatus();
            txt = mabr.ui.analysis.Model.reportText(out,lab);
            obj.ev("ResultsChanged","rejection","setSweepsRejected",Keys=keys);
            obj.ev("StatusChanged","save","setSweepsRejected",Text=txt + " — Ctrl+Z to undo");
        end

        function fileUseWork(obj,P,lab,sink)
            S = obj.Session;
            before = S.editSnapshot();
            S.ProgressFcn = sink;
            c = onCleanup(@() mabr.ui.analysis.Model.clearSink(S));
            drop = P.FileIds(~P.Use);
            add  = P.FileIds(P.Use);
            if ~isempty(drop), S.setExcluded(drop,true); end
            if ~isempty(add),  S.setExcluded(add,false); end
            clear c
            after = S.editSnapshot();
            e = obj.newEntry(lab,"session");
            e.Before = before; e.After = after; e.What = "all"; e.NeedsRaw = true;
            obj.pushUndo(e);
            obj.PendingFileUse = mabr.ui.analysis.Model.emptyFileUse();
            obj.markDirty("session");
            obj.updateStatus();
            obj.ev("ResultsChanged","all","applyFileUse",Keys=obj.SessionKey);
            obj.ev("StatusChanged","status","applyFileUse", ...
                Text=sprintf('%s applied — Ctrl+Z to undo',lab));
        end

        function overridesWork(obj,key,ov)
            names = ["InputFullScale","AmplifierGain","TimeOffset","ConductionDelay"];
            cols  = ["InputFullScaleOverride","AmplifierGainOverride","TimeOffsetOverride", ...
                "ConductionDelayOverride"];
            before = obj.latencyOffset();
            for i = 1:numel(names)
                if isfield(ov,names(i))
                    v = double(ov.(names(i)));
                    if isempty(v), v = NaN; end
                    obj.Project.label(key,cols(i),v);
                end
            end
            obj.markDirty("project");
            repicked = false;
            S = obj.Session;
            if key == obj.SessionKey && ~isempty(S)
                obj.applyProjectOverrides(S,key);
                % A new delay or time offset changes the REPORTED
                % latencies only (the waves are searched in the recording's
                % own time, so no pick moves), but the Peaks table records
                % the offset each pick is reported with (LatencyOffset):
                % the peaks step is re-run at once (instant, no raw data
                % needed), so the session stays up to date. Unit overrides
                % change the segmented volts, which only a re-analysis can
                % follow.
                if abs(obj.latencyOffset() - before) > 1e-12 && obj.isAnalysed(S) && ...
                        ~isempty(S.Settings) && height(S.Peaks) > 0
                    S.analyze(S.Settings,'From',"peaks");
                    obj.clearUndo(key);
                    obj.HistoryPending = true;
                    repicked = true;
                end
                obj.markDirty("session");
            end
            obj.ViewCache = [];
            obj.updateStatus();
            obj.ev("ResultsChanged","all","setSessionOverrides",Keys=key);
            txt = "Overrides saved.";
            if repicked
                txt = sprintf(['Overrides saved — latencies now reported less a %.3g ms latency ' ...
                    'offset (peaks re-picked, no pick moved; undo history cleared).'],obj.latencyOffset());
            elseif key == obj.SessionKey && obj.Status.State == "stale"
                txt = "Overrides saved — the session is out of date until it is analysed again.";
            end
            obj.ev("StatusChanged","status","setSessionOverrides",Text=txt);
        end

        function batchWork(obj,items,opts,logFile,sink)
            obj.JobOuter = "Batch";
            st = obj.Settings;
            if ~isempty(opts.Settings), st = opts.Settings; end
            T = mabr.analysis.Batch.run(items,st,'SkipCurrent',opts.SkipCurrent, ...
                'IncludeTestMode',opts.IncludeTestMode,'StopOnError',opts.StopOnError, ...
                'SummaryFigure',opts.SummaryFigure,'LogFile',logFile,'ProgressFcn',sink, ...
                'CancelFcn',@() obj.CancelRequested,'Project',obj.Project,'Analyst',obj.Analyst);
            obj.BatchRun = T;
            summary = T;
            if height(opts.MergeInto) > 0
                summary = mabr.ui.analysis.BatchReport.merge(opts.MergeInto,T);
            end
            % ({} keeps a [] Settings -- "the project's" -- a 1x1 struct)
            obj.LastBatch = struct('Summary',summary,'LogFile',logFile,'Settings',{opts.Settings});
            try
                obj.ensureProjectSettings();
                obj.Project.save();
            catch me
                mabr.log.vprintf(1,'Model: project not saved after the batch (%s).',me.message);
            end
            obj.ViewCache = [];
            obj.ev("ProjectChanged","status","batch",Keys=string(items.Key));
            % The open session re-analysed by the batch is read back.
            if obj.SessionKey ~= "" && ismember(obj.SessionKey,string(T.Key))
                r = find(string(T.Key) == obj.SessionKey,1);
                st = string(T.Status(r));
                if startsWith(st,"ok") && isfile(obj.ResultsFile)
                    sel = obj.Selection;
                    S = mabr.analysis.Session.fromResults(obj.ResultsFile,'Verbose',false);
                    obj.applyProjectOverrides(S,obj.SessionKey);
                    try
                        S.MessageFcn = @(lvl,txt) obj.onSessionMessage(lvl,txt);
                        S.Analyst = obj.Analyst;
                    catch
                    end
                    obj.Session = S;
                    obj.SessionSource = "results";
                    obj.Stamp = mabr.ui.analysis.Model.fileStamp(obj.ResultsFile);
                    obj.SavedUnitOverride = obj.unitOverrideOf(S);
                    obj.SessionDirty = false;
                    obj.clearUndo(obj.SessionKey);
                    obj.Selection = obj.initialSelection(sel.SeriesKey,sel.Level,sel);
                    obj.ev("SessionChanged","all","batch",Keys=obj.SessionKey);
                end
            end
            obj.updateStatus();
            obj.ev("StatusChanged","status","batch",Text=mabr.ui.analysis.Model.batchText(T));
        end

        function exportWork(obj,keys,o,folder,sink)
            % (an error says which folder it could not write)
            if ~isfolder(folder)
                [okM,msg] = mkdir(char(folder));
                if ~okM
                    error('mabr:ui:analysis:notWritable','Cannot create the export folder %s (%s).', ...
                        folder,msg);
                end
            end
            if ~mabr.ui.analysis.Model.canWrite(folder)
                error('mabr:ui:analysis:notWritable','Cannot write into the export folder %s.',folder);
            end
            sink("Collecting results",0,numel(keys));
            items = obj.Project.exportItems(keys,obj.Catalog);
            rawTables = intersect(o.Tables,mabr.analysis.Export.RawTables,'stable');
            resTables = setdiff(o.Tables,rawTables,'stable');
            subj = [];
            try
                subj = obj.Project.Subjects;
            catch
            end
            T = mabr.analysis.Export.tables(items,'Tables',resTables, ...
                'ThresholdsAll',o.ThresholdsAll,'OnlyReviewed',o.OnlyReviewed, ...
                'IncludeExcluded',o.IncludeExcluded,'IncludeTestMode',o.IncludeTestMode, ...
                'WaveformWindow',o.WaveformWindow,'Settings',obj.Settings, ...
                'Subjects',subj,'ProgressFcn',sink);
            files = mabr.analysis.Export.write(T,folder,'Formats',o.Formats,'ProgressFcn',sink);
            % The raw tables reopen each session's raw files, one at a time.
            if ~isempty(rawTables)
                for i = 1:numel(items)
                    key = string(items(i).Key);
                    obj.JobOuter = sprintf('Session %d/%d: %s',i,numel(items),key);
                    info = obj.sessionInfo(key);
                    S = mabr.analysis.Session.fromResults(info.ResultsFile,'Verbose',false);
                    obj.applyProjectOverrides(S,key);
                    S.ProgressFcn = sink;
                    S.loadRaw();
                    S.ProgressFcn = [];
                    f2 = mabr.analysis.Export.writeRaw(S,items(i),folder,'Tables',rawTables, ...
                        'Formats',o.RawFormats,'ProgressFcn',sink);
                    files = [files; f2]; %#ok<AGROW>
                    clear S
                end
                obj.JobOuter = "";
            end
            if o.RScript
                try
                    mabr.analysis.Export.writeRScript(folder,files,T);
                    mabr.analysis.Export.writeDictionary(folder,T);
                    mabr.analysis.Export.writeManifest(folder,T,'Files',files, ...
                        'Scope',o.Scope,'Options',rmfield(o,'Keys'),'Settings',obj.Settings);
                catch me
                    mabr.log.vprintf(1,'Model: R script/dictionary not written (%s).',me.message);
                end
            end
            if o.Script && mabr.ui.analysis.Model.hasClass("mabr.analysis.ScriptWriter")
                try
                    code = mabr.analysis.ScriptWriter.study(items,'Title',"Replicate this export", ...
                        'DataRoot',string(obj.Catalog.Root),'IncludeExport',true, ...
                        'ExportOptions',struct('Tables',o.Tables,'Formats',o.Formats, ...
                        'ThresholdsAll',o.ThresholdsAll,'OnlyReviewed',o.OnlyReviewed, ...
                        'IncludeExcluded',o.IncludeExcluded,'IncludeTestMode',o.IncludeTestMode, ...
                        'WaveformWindow',o.WaveformWindow,'RScript',o.RScript));
                    mabr.analysis.ScriptWriter.write(fullfile(folder,'replicate_analysis.m'),code);
                catch me
                    mabr.log.vprintf(1,'Model: replication script not written (%s).',me.message);
                end
            end
            sink("Done",numel(keys),numel(keys));
            o.Folder = folder;
            obj.LastExport = struct('Options',o,'Folder',folder,'Files',files);
            n = 0;
            try
                n = sum(string(files.File) ~= "");
            catch
            end
            obj.ev("StatusChanged","status","export",Text=sprintf('Exported %d file(s) to %s',n,folder));
        end

        % ---- edits -------------------------------------------------------
        function rep = curate(obj,label,sk,fcn,source,verb)
            % A threshold-curation edit: ResultsChanged(curation) ->
            % StatusChanged(save).
            rep = obj.applyEdit(label + " (" + obj.seriesLabel(sk) + ")",fcn,"curation",sk,source,verb, ...
                sk);
        end

        function rep = applyEdit(obj,label,fcn,what,keys,source,verb,seriesKey)
            % Snapshot, apply, snapshot, undo entry, autosave, events.
            obj.assertMutable();
            S = obj.Session;
            before = S.editSnapshot();
            oldFinal = "";
            if nargin >= 8, oldFinal = obj.finalWords(seriesKey); end
            out = mabr.ui.analysis.Model.callReport(fcn,S);
            after = S.editSnapshot();
            e = obj.newEntry(label,"session");
            e.Before = before; e.After = after; e.What = what;
            e.Keys = reshape(string(keys),[],1);
            obj.pushUndo(e);
            obj.markDirty("session");
            obj.updateStatus();
            txt = mabr.ui.analysis.Model.reportText(out,"");
            if txt == ""
                txt = verb;
                if nargin >= 8 && seriesKey ~= ""
                    nf = obj.finalWords(seriesKey);
                    txt = verb + " for " + obj.seriesLabel(seriesKey);
                    if nf ~= "", txt = txt + ": " + nf; end
                    if oldFinal ~= "" && oldFinal ~= nf, txt = txt + " (was " + oldFinal + ")"; end
                end
            end
            obj.ev("ResultsChanged",what,source,Keys=e.Keys);
            obj.ev("StatusChanged","save",source,Text=txt + " — Ctrl+Z to undo");
            rep = out;
            if isempty(rep), rep = struct('Text',txt); end
        end

        function e = newEntry(~,label,kind)
            e = struct('Label',string(label),'Kind',string(kind),'Before',[],'After',[], ...
                'What',"all",'Keys',strings(0,1),'NeedsRaw',false,'Name',"",'Level',"", ...
                'Type',"",'Levels',strings(1,0),'Op',"",'PoolKey',"",'Project',[]);
        end

        function applyEntry(obj,e,which)
            % Put the state of one undo entry back (which = "Before"/"After").
            switch e.Kind
                case "session"
                    obj.assertSession();
                    S = obj.Session;
                    if e.NeedsRaw && ~S.HasSweeps
                        obj.ensureRaw();
                        if ~S.HasSweeps, return; end
                    end
                    snap = e.(which);
                    if e.What == "rejection" || e.What == "all"
                        obj.runJob("Undoing",@(sink) obj.restoreWork(snap,e,sink));
                    else
                        S.restoreEdits(snap);
                        obj.markDirty("session");
                        obj.updateStatus();
                        obj.ev("ResultsChanged",e.What,"undo",Keys=e.Keys);
                        obj.ev("StatusChanged","save","undo");
                    end
                case "labels"
                    vals = e.(which);
                    for i = 1:numel(e.Keys)
                        try
                            obj.Project.label(e.Keys(i),e.Name,vals{i});
                        catch me
                            mabr.log.vprintf(2,'Model: label not restored (%s).',me.message);
                        end
                    end
                    obj.ViewCache = [];
                    obj.markDirty("project");
                    obj.ev("ProjectChanged","labels","undo",Keys=e.Keys);
                    obj.ev("StatusChanged","save","undo");
                case "columns"
                    obj.applyColumnEntry(e,which);
                    obj.ViewCache = [];
                    obj.markDirty("project");
                    obj.ev("ProjectChanged","columns","undo",Keys=e.Name);
                    obj.ev("StatusChanged","save","undo");
                case "property"
                    switch e.Name
                        case "DuplicatePolicy", obj.Project.setDuplicatePolicy(e.(which));
                        case "ReferenceTimepoint", obj.Project.setReferenceTimepoint(e.(which));
                    end
                    obj.ViewCache = [];
                    obj.markDirty("project");
                    obj.ev("ProjectChanged","labels","undo");
                    obj.ev("StatusChanged","save","undo");
                case "pools"
                    add = (e.Op == "add") == (which == "After");
                    if add
                        obj.Project.addPool(e.Keys,e.Name);
                    else
                        if obj.SessionKey == e.PoolKey, obj.closeSession(); end
                        obj.Project.removePool(e.PoolKey);
                    end
                    obj.ViewCache = [];
                    obj.markDirty("project");
                    obj.ev("ProjectChanged","pools","undo",Keys=e.PoolKey);
                    obj.ev("StatusChanged","save","undo");
            end
        end

        function restoreWork(obj,snap,e,sink)
            S = obj.Session;
            S.ProgressFcn = sink;
            c = onCleanup(@() mabr.ui.analysis.Model.clearSink(S));
            S.restoreEdits(snap);
            clear c
            obj.markDirty("session");
            obj.updateStatus();
            obj.ev("ResultsChanged",e.What,"undo",Keys=e.Keys);
            obj.ev("StatusChanged","save","undo");
        end

        function applyColumnEntry(obj,e,which)
            P = obj.Project;
            switch e.Op
                case "add"
                    if which == "Before", P.removeColumn(e.Name);
                    else, P.addColumn(e.Name,e.Level,e.Type); end
                case "remove"
                    if which == "Before"
                        P.addColumn(e.Name,e.Level,e.Type);
                        if ~isempty(e.Levels), P.setLevels(e.Name,e.Levels); end
                        for i = 1:numel(e.Keys)
                            v = e.Before{i};
                            if mabr.ui.analysis.Model.isBlank(v), continue; end
                            try
                                P.label(e.Keys(i),e.Name,v);
                            catch
                            end
                        end
                    else
                        P.removeColumn(e.Name);
                    end
                case "levels"
                    P.setLevels(e.Name,e.(which));
            end
        end

        function pushUndo(obj,e)
            st = obj.stack();
            st.Undo{end+1} = e;
            if numel(st.Undo) > obj.UndoDepth
                st.Undo = st.Undo(end-obj.UndoDepth+1:end);
            end
            st.Redo = {};
            obj.setStack(st);
        end

        function st = stack(obj,key)
            if nargin < 2, key = obj.SessionKey; end
            k = char(key);
            if isKey(obj.UndoStacks,k)
                st = obj.UndoStacks(k);
            else
                st = struct('Undo',{{}},'Redo',{{}});
            end
        end

        function setStack(obj,st,key)
            if nargin < 3, key = obj.SessionKey; end
            obj.UndoStacks(char(key)) = st;
        end

        function clearUndo(obj,key)
            k = char(key);
            if isKey(obj.UndoStacks,k), remove(obj.UndoStacks,k); end
        end

        % ---- saving ------------------------------------------------------
        function markDirty(obj,which)
            if nargin < 2, which = "session"; end
            if which == "session"
                obj.SessionDirty = true;
            end
            if obj.ReadOnly
                obj.SaveState = "readonly";
            elseif obj.SaveState ~= "conflict"
                obj.SaveState = "pending";
            end
            obj.restartAutosave();
        end

        function ensureProjectSettings(obj)
            % A project that has never had settings of its own (a new one:
            % Project.Settings []) records the ones in force at its first
            % save. Otherwise it would take the user's DEFAULTS (pref
            % OfflineAnalysisSettings) afresh at every open -- and the
            % settings dialog of another project writes that pref, which
            % would silently put every session here out of date (11 sec.
            % 11: the project's settings govern inside the project; the
            % pref is only the default for a new one).
            try
                if ~isempty(obj.Project) && isempty(obj.Project.Settings) && ...
                        ~isempty(obj.Settings) && ~obj.Project.ReadOnly
                    obj.Project.setSettings(obj.Settings);
                end
            catch me
                mabr.log.vprintf(2,'Model: the project''s settings were not recorded (%s).',me.message);
            end
        end

        function tf = projectDirty(obj)
            tf = false;
            if isempty(obj.Project), return; end
            try
                tf = logical(obj.Project.Dirty);
            catch
                tf = false;
            end
        end

        function writeResults(obj,cur)
            f = obj.ResultsFile;
            d = fileparts(char(f));
            if ~isfolder(d)
                [ok,msg] = mkdir(d);
                if ~ok
                    error('mabr:ui:analysis:notWritable','Cannot create %s (%s).',d,msg);
                end
            end
            if obj.HistoryPending && cur.Exists
                obj.copyToHistory(f);
            end
            % Session.saveResults notes "Saved <file>." through MessageFcn;
            % an autosave a moment after every edit would put that path on
            % the status line over the edit's own echo (and its Ctrl+Z
            % hint). The header's "Saved hh:mm:ss" already says it.
            S = obj.Session;
            fcn = [];
            try
                fcn = S.MessageFcn;
                S.MessageFcn = [];
            catch
            end
            restore = onCleanup(@() mabr.ui.analysis.Model.setMessageFcn(S,fcn));
            S.saveResults(f,'IncludeSweeps',false);
            clear restore
            obj.Stamp = mabr.ui.analysis.Model.fileStamp(f);
            obj.SessionDirty = false;
            obj.HistoryPending = false;
        end

        function saveFailed(obj,me,where)
            % WHERE is the results folder or a results FILE; probing a file
            % path as a folder would create a folder of the file's name
            % (and every later save onto that name would then fail)
            folder = string(where);
            if isfile(folder) || (folder ~= "" && folder == obj.ResultsFile)
                folder = string(fileparts(char(folder)));
            end
            if strcmp(me.identifier,'mabr:analysis:Project:readOnly')
                % project.mat cannot be used (unreadable, or a newer
                % format): retrying cannot help, so read-only -- the bar
                % offers another results folder -- not "retrying" forever
                obj.ReadOnly = true;
                if obj.ReadOnlyWhy == ""
                    obj.ReadOnlyWhy = "project.mat cannot be written back (" + string(me.message) + ")";
                end
                obj.setSaveState("readonly");
                obj.ev("StatusChanged","save","saveNow",Level=1, ...
                    Text="Read-only: " + obj.ReadOnlyWhy + ".");
                mabr.log.vprintf(1,'Model: save refused (%s).',me.message);
                return
            end
            if ~mabr.ui.analysis.Model.canWrite(folder)
                obj.ReadOnly = true;
                obj.setSaveState("readonly");
                obj.ev("StatusChanged","save","saveNow",Level=1, ...
                    Text="Read-only: results cannot be written to " + folder + ".");
            else
                obj.setSaveState("failed");
                obj.ev("StatusChanged","save","saveNow",Level=2, ...
                    Text="Save failed — retrying: " + string(me.message));
                obj.restartAutosave();
            end
            mabr.log.vprintf(2,'Model: save failed (%s).',me.message);
        end

        function copyToHistory(obj,file)
            % The results file a re-analysis replaces, kept (newest 3).
            try
                h = fullfile(char(obj.resultsFolder()),'.history');
                if ~isfolder(h), mkdir(h); end
                flat = obj.flatKey(obj.SessionKey);
                stamp = string(datetime('now','Format','yyMMdd''T''HHmmss'));
                dest = fullfile(h,char(flat + "_" + stamp + ".mat"));
                copyfile(char(file),dest,'f');
                L = dir(fullfile(h,char(flat + "_*.mat")));
                names = sort(reshape(string({L.name}),[],1));
                pat = "^" + regexptranslate('escape',flat) + "_\d{6}T\d{6}(_\d+)?\.mat$";
                names = names(~cellfun(@isempty,regexp(cellstr(names),char(pat),'once')));
                if numel(names) > obj.HistoryKeep
                    for k = 1:numel(names) - obj.HistoryKeep
                        delete(fullfile(h,char(names(k))));
                    end
                end
            catch me
                mabr.log.vprintf(1,'Model: the previous results were not kept in .history (%s).',me.message);
            end
        end

        function txt = keepUnreadable(obj,info)
            % Copy a results file that cannot be read into the store's
            % .history as <flat>_unreadable_<stamp>.mat (outside the pruned
            % pattern, so it is kept), before a save replaces it. Returns a
            % clause for the log saying where it went.
            txt = ""; %#ok<NASGU> (every path below sets it)
            try
                h = fullfile(char(obj.resultsFolder()),'.history');
                if ~isfolder(h), mkdir(h); end
                stamp = string(datetime('now','Format','yyMMdd''T''HHmmss'));
                dest = fullfile(h,char(obj.flatKey(info.Key) + "_unreadable_" + stamp + ".mat"));
                copyfile(char(info.ResultsFile),dest,'f');
                txt = "; the file was copied to " + string(dest);
            catch me
                txt = "; it could not be copied aside (" + string(me.message) + ")";
            end
        end

        function restartAutosave(obj)
            if ~obj.AutoRefresh, return; end
            try
                if isempty(obj.AutosaveTimer) || ~isvalid(obj.AutosaveTimer)
                    obj.AutosaveTimer = timer('Tag','MABR_OfflineAutosave', ...
                        'ExecutionMode','singleShot','BusyMode','drop', ...
                        'StartDelay',obj.AutosaveDelay,'TimerFcn',@(~,~) obj.onAutosave());
                end
                stop(obj.AutosaveTimer);
                obj.AutosaveTimer.StartDelay = obj.AutosaveDelay;
                start(obj.AutosaveTimer);
            catch me
                mabr.log.vprintf(2,'Model: autosave timer failed (%s).',me.message);
            end
        end

        function stopAutosave(obj)
            try
                if ~isempty(obj.AutosaveTimer) && isvalid(obj.AutosaveTimer)
                    stop(obj.AutosaveTimer);
                end
            catch
            end
        end

        function onAutosave(obj)
            if ~isvalid(obj), return; end
            if obj.Busy
                obj.restartAutosave();
                return
            end
            try
                obj.saveNow();
            catch me
                mabr.log.vprintf(1,'Model: autosave failed (%s).',me.message);
            end
        end

        % ---- status ------------------------------------------------------
        function updateStatus(obj)
            st = mabr.ui.analysis.Model.emptyStatus();
            S = obj.Session;
            if isempty(S)
                obj.Status = st;
                return
            end
            key = char(obj.SessionKey);
            if isKey(obj.FailedText,key)
                st.State = "failed";
                st.Text = "Failed: " + string(obj.FailedText(key));
                st.FromStep = "segment";
                st.Seconds = obj.estimateSeconds("segment");
                obj.Status = st;
                return
            end
            if ~obj.isAnalysed(S)
                st.State = "not-analysed";
                st.Text = "Not analysed";
                st.FromStep = "segment";
                st.Seconds = obj.estimateSeconds("segment");
                obj.Status = st;
                return
            end
            D = st.Differences;
            tf = false;
            try
                [tf,D] = S.isStale(obj.Settings);
            catch me
                mabr.log.vprintf(2,'Model: isStale failed (%s).',me.message);
            end
            D = mabr.ui.analysis.Model.normalizeDiff(D);
            ovChanged = ~isequaln(obj.unitOverrideOf(S),obj.SavedUnitOverride);
            if ovChanged
                D = [D; table("segment","UnitOverride","saved","changed", ...
                    'VariableNames',{'Step','Field','Old','New'})];
                tf = true;
            end
            % A delay or time offset set on this session in the project
            % while it was not open (Study table, another window): its peaks
            % are reported with another latency offset than the one now in
            % force (the picks themselves do not depend on it). Re-picking
            % them is the instant "peaks" step, which records the new one.
            [latChanged,oldOff] = mabr.ui.analysis.Model.peakOffsetChanged(S);
            if latChanged
                D = [D; table("peaks","LatencyOffset",string(sprintf('%g ms',oldOff)), ...
                    string(sprintf('%g ms',double(S.LatencyOffset))), ...
                    'VariableNames',{'Step','Field','Old','New'})];
                ovChanged = true;
                tf = true;
            end
            st.Differences = D;
            if ~tf
                st.State = "current";
                at = mabr.ui.analysis.Model.analysedAt(S);
                if isnat(at)
                    st.Text = "Up to date";
                else
                    st.Text = "Up to date (" + string(at,'yyyy-MM-dd HH:mm') + ")";
                end
                st.Seconds = 0;
            else
                st.State = "stale";
                steps = string(D.Step);
                if any(steps == "data")
                    st.Text = "Out of date (files changed)";
                elseif ovChanged && all(ismember(string(D.Field),["UnitOverride","LatencyOffset"]))
                    st.Text = "Out of date (overrides changed)";
                else
                    st.Text = "Out of date (settings changed)";
                end
                st.FromStep = mabr.ui.analysis.Model.earliestStep(steps);
                st.Seconds = obj.estimateSeconds(st.FromStep);
            end
            obj.Status = st;
        end

        function from = autoFrom(obj)
            S = obj.Session;
            if ~obj.isAnalysed(S)
                from = "segment";
                return
            end
            obj.updateStatus();
            if obj.Status.State == "current"
                from = "";
            elseif obj.Status.FromStep ~= ""
                from = obj.Status.FromStep;
            else
                from = "segment";
            end
        end

        function txt = settingsReport(obj,refitted,changed)
            % The status line after setSettings, in words: what was redone,
            % or what is now out of date. CHANGED (setSettings): the first
            % step whose settings changed, the fields, the old settings.
            if nargin < 3, changed = struct('Step',"",'Fields',strings(0,1),'Old',[],'New',[]); end
            latency = ["ConductionDelayMode","ConductionDelay","SpeakerDistance","SpeedOfSound","TimeOffset"];
            if refitted && changed.Step == "peaks" && ~isempty(changed.Fields) && ...
                    all(ismember(changed.Fields,latency))
                % a conduction delay or a time offset: the peaks are reported
                % at the new latency offset, and nothing else moves
                txt = "Settings applied — the reported peak latencies";
                try
                    o1 = changed.New.latencyOffset();
                    o0 = changed.Old.latencyOffset();
                    txt = txt + sprintf(' now have a %.2f ms latency offset (was %.2f ms)',o1,o0);
                catch
                    txt = txt + " follow the new conduction delay / time offset";
                end
                txt = txt + "; no threshold changed.";
            elseif refitted && changed.Step == "peaks"
                txt = "Settings applied — peaks picked again; no threshold changed.";
            elseif refitted
                txt = "Settings applied — thresholds re-fitted.";
            elseif ~isempty(obj.Session) && obj.Status.State == "stale"
                n = numel(mabr.analysis.Settings.Steps) - ...
                    find(mabr.analysis.Settings.Steps == obj.Status.FromStep,1) + 1;
                txt = sprintf('Settings applied — %d step(s) from %s are now out of date (%s): press Analyse.', ...
                    n,obj.Status.FromStep,mabr.ui.analysis.Style.formatSeconds(obj.Status.Seconds));
            else
                txt = "Settings applied.";
            end
        end

        % ---- selection helpers ------------------------------------------
        function sel = initialSelection(obj,seriesKey,level,prev)
            sel = mabr.ui.analysis.Model.emptySelection();
            keys = obj.seriesKeys();
            if seriesKey ~= "" && any(keys == seriesKey)
                sk = seriesKey; lv = level;
            elseif prev.SeriesKey ~= "" && any(keys == prev.SeriesKey)
                sk = prev.SeriesKey; lv = prev.Level;
                if ~isnan(level), lv = level; end
            elseif ~isempty(keys)
                sk = keys(1); lv = level;
            else
                % no series (no level parameter): select the first condition
                try
                    ck = string(obj.Session.Conditions.Key);
                    if ~isempty(ck), sel.ConditionKey = ck(1); end
                catch
                end
                return
            end
            [ck,lvs] = obj.seriesLevels(sk);
            if isempty(ck), return; end
            chosen = true;
            if isnan(lv)
                if isKey(obj.LevelMemory,obj.levelMemoryKey(sk))
                    lv = obj.LevelMemory(obj.levelMemoryKey(sk));
                else
                    % The threshold-adjacent default is not remembered: it is
                    % the app's guess, not a level anybody chose, and must
                    % follow the threshold when that is fitted or moved.
                    lv = obj.defaultLevel(sk);
                    chosen = false;
                end
            end
            [~,i] = min(abs(lvs - lv));
            sel.SeriesKey = sk;
            sel.Level = lvs(i);
            sel.ConditionKey = ck(i);
            if chosen, obj.rememberLevel(sk,lvs(i)); end
        end

        function rememberLevel(obj,sk,level)
            if sk ~= "" && isfinite(level)
                obj.LevelMemory(obj.levelMemoryKey(sk)) = level;
            end
        end

        function [ck,lv] = seriesLevels(obj,seriesKey)
            % Condition keys of a series and their levels, ascending.
            ck = strings(0,1); lv = zeros(0,1);
            S = obj.Session;
            if isempty(S) || seriesKey == "", return; end
            lp = obj.levelParam();
            try
                ck = reshape(string(S.seriesConditions(seriesKey)),[],1);
            catch
                ck = obj.derivedSeriesConditions(seriesKey);
            end
            if isempty(ck), return; end
            lv = nan(numel(ck),1);
            C = S.Conditions;
            keys = string(C.Key);
            for i = 1:numel(ck)
                r = find(keys == ck(i),1);
                if ~isempty(r) && lp ~= "" && ismember(char(lp),C.Properties.VariableNames)
                    lv(i) = double(C.(lp)(r));
                end
            end
            [lv,ix] = sort(lv);
            ck = ck(ix);
        end

        function lv = defaultLevel(obj,sk)
            % 11 sec. 7.1: the lowest usable level at or above the final
            % threshold; loudest when there is none to go by.
            [~,lvs] = obj.seriesLevels(sk);
            lv = NaN;
            if isempty(lvs), return; end
            lv = max(lvs);
            row = obj.thresholdRow(sk);
            if isempty(row), return; end
            c = string(mabr.ui.analysis.Model.rowValue(row,'FinalCensored',""));
            F = double(mabr.ui.analysis.Model.rowValue(row,'Final',NaN));
            hi = double(mabr.ui.analysis.Model.rowValue(row,'FinalHi',NaN));
            switch c
                case "interval"
                    k = find(lvs >= hi - 1e-9,1);
                    if ~isempty(k), lv = lvs(k); end
                case "none"
                    if isfinite(F)
                        k = find(lvs >= F - 1e-9,1);
                        if ~isempty(k), lv = lvs(k); end
                    end
                case "right"
                    lv = max(lvs);
                case "left"
                    lv = min(lvs);
            end
        end

        function row = thresholdRow(obj,sk)
            row = [];
            S = obj.Session;
            if isempty(S), return; end
            try
                row = S.seriesRow(sk);
            catch
                row = [];
            end
            if isnumeric(row) && ~isempty(row)
                try
                    row = S.Thresholds(row,:);
                catch
                    row = [];
                end
            end
        end

        function sk = targetSeries(obj,seriesKey)
            obj.assertSession();
            sk = seriesKey;
            if sk == "", sk = obj.Selection.SeriesKey; end
            if sk == ""
                error('mabr:ui:analysis:noSeries','Select a series first.');
            end
        end

        function d = decisionOf(obj,sk)
            d = "";
            row = obj.thresholdRow(sk);
            if isempty(row), return; end
            d = string(mabr.ui.analysis.Model.rowValue(row,'Decision',""));
            if ismissing(d), d = ""; end
        end

        function w = finalWords(obj,sk)
            w = "";
            row = obj.thresholdRow(sk);
            if isempty(row), return; end
            try
                t = mabr.ui.analysis.Style.formatThreshold(row);
                d = string(mabr.ui.analysis.Model.rowValue(row,'Decision',""));
                if ismissing(d) || d == "", d = "unreviewed"; end
                switch d
                    case "noresponse", w = "no response";
                    case "allrespond", w = "all respond " + t;
                    case "excluded",   w = "excluded";
                    otherwise,         w = d + " " + t;
                end
            catch
            end
        end

        function sk = seriesOfCondition(obj,ck)
            sk = "";
            S = obj.Session;
            if isempty(S) || ck == "", return; end
            try
                sk = string(S.seriesOf(ck));
            catch
                lp = obj.levelParam();
                if lp ~= ""
                    sk = regexprep(ck,"\|" + regexptranslate('escape',lp) + "=[^|]*","");
                end
            end
            if isempty(sk) || ismissing(sk), sk = ""; end
        end

        function lv = conditionLevel(obj,ck)
            lv = NaN;
            S = obj.Session;
            lp = obj.levelParam();
            if lp == "", return; end
            try
                r = S.rowOf(ck);
                lv = double(S.Conditions.(lp)(r));
            catch
            end
        end

        function k = derivedSeriesKeys(obj)
            k = strings(0,1);
            S = obj.Session;
            lp = obj.levelParam();
            if lp == "" || isempty(S.Conditions), return; end
            ck = string(S.Conditions.Key);
            k = unique(regexprep(ck,"\|" + regexptranslate('escape',lp) + "=[^|]*",""),'stable');
        end

        function ck = derivedSeriesConditions(obj,sk)
            S = obj.Session;
            lp = obj.levelParam();
            ck = strings(0,1);
            if lp == "" || isempty(S.Conditions), return; end
            ckAll = string(S.Conditions.Key);
            ser = regexprep(ckAll,"\|" + regexptranslate('escape',lp) + "=[^|]*","");
            ck = ckAll(ser == sk);
        end

        function [ck,wave,kind] = selectedPoint(obj)
            obj.assertSession();
            ck = obj.Selection.ConditionKey;
            wave = obj.Selection.Wave;
            kind = obj.Selection.Kind;
            if ck == ""
                error('mabr:ui:analysis:noCondition','Select a level first.');
            end
            if wave == ""
                error('mabr:ui:analysis:noWave','Select a wave first (1–5 for its peak, Shift+1–5 for its trough).');
            end
        end

        function lat = pointLatency(obj,ck,wave,kind)
            lat = NaN;
            P = obj.Session.Peaks;
            if isempty(P) || height(P) == 0, return; end
            r = find(string(P.Key) == ck & string(P.Wave) == wave,1);
            if isempty(r), return; end
            if kind == "N"
                lat = double(P.TroughLatency(r));
            else
                lat = double(P.PeakLatency(r));
            end
        end

        function tf = isAbsent(obj,ck,wave)
            tf = false;
            P = obj.Session.Peaks;
            if isempty(P) || height(P) == 0, return; end
            r = find(string(P.Key) == ck & string(P.Wave) == wave,1);
            if ~isempty(r), tf = string(P.State(r)) == "absent"; end
        end

        function y = meanFor(obj,ck)
            pol = "balanced";
            try
                pol = obj.Settings.PeakPolarity;
            catch
            end
            y = obj.Session.conditionMean(ck,pol);
            y = double(y(:));
        end

        function v = overrideOf(obj,ck)
            v = NaN;
            D = obj.Session.DetectionOverrides;
            if isempty(D) || height(D) == 0, return; end
            r = find(string(D.Key) == ck,1,'last');
            if ~isempty(r), v = double(D.Value(r)); end
        end

        function Y = seriesInputs(obj,ck)
            % SeriesThreshold.estimate's Y from the stored condition columns.
            C = obj.Session.Conditions;
            keys = string(C.Key);
            [~,rows] = ismember(ck,keys);
            col = @(name,def) mabr.ui.analysis.Model.column(C,rows,name,def);
            Y = struct('P',col('p',NaN),'IsSig',col('isSig',false),'Strength',col('strength',NaN), ...
                'PowerP',col('PowerP',NaN),'FspP',col('FspP',NaN),'SplitR',col('SplitR',NaN), ...
                'SplitRSD',col('SplitRSD',NaN),'XCorrUp',col('XCorrUp',NaN),'DTWUp',col('DTWUp',NaN), ...
                'SNR',col('SNR',NaN), ...
                'NClean',col('nClean',NaN),'NPos',col('nPos',NaN),'NNeg',col('nNeg',NaN), ...
                'Override',nan(numel(ck),1));
            for i = 1:numel(ck)
                Y.Override(i) = obj.overrideOf(ck(i));
            end
            Y.IsSig = logical(Y.IsSig);
            % A level whose clean sweeps do not vary (a dead channel,
            % noiseless data) has no metric and was not tested; its flag
            % gives the reason, so the comparison's "level ignored" says
            % "zero variance" rather than "the metric is undefined" -- as the
            % Session's own fit does (Session's estimate inputs).
            Y.ZeroVariance = false(numel(ck),1);
            if ismember('Flags',C.Properties.VariableNames)
                zv = mabr.analysis.SingleTrial.FlagZeroVariance;
                for i = 1:numel(ck)
                    if rows(i) < 1, continue; end
                    f = C.Flags(rows(i));
                    if iscell(f), f = f{1}; end
                    f = string(f);
                    Y.ZeroVariance(i) = any(contains(f(~ismissing(f)),zv));
                end
            end
        end

        function o = estimateOpts(obj,st)
            S = obj.Session;
            dir = st.LevelDirection;
            if dir == "auto"
                if contains(lower(obj.levelParam()),"attenuation"), dir = "descending";
                else, dir = "ascending"; end
            end
            alt = true;
            try
                alt = any(logical(S.Files.AlternatePolarity));
            catch
            end
            o = struct('Alpha',st.Alpha,'MinConsecutive',st.MinConsecutive, ...
                'Convention',st.ThresholdConvention,'Interpolate',st.Interpolate, ...
                'MinSweeps',st.MinSweeps,'MinPerPolarity',st.MinPerPolarity,'Alternating',alt, ...
                'Extrapolate',st.Extrapolate,'NearestLevel',st.NearestLevel,'CIAlpha',st.CIAlpha, ...
                'CINumSamples',st.CINumSamples,'Seed',st.Seed,'LevelDirection',dir, ...
                'FlagWideCI',st.FlagWideCI,'FlagNonMonotoneTol',st.FlagNonMonotoneTol);
            o = mabr.ui.analysis.Model.nameValues(o);
        end

        function o = peakOpts(obj)
            st = obj.Settings;
            S = obj.Session;
            if ~isempty(S) && ~isempty(S.Settings), st = S.Settings; end
            o = {'Waves',st.Waves,'OctaveShift',st.PeakOctaveShift,'RefFrequency',st.PeakRefFrequency, ...
                'Smooth',st.PeakSmooth,'MinSeparation',st.PeakMinSeparation, ...
                'TrackEarly',st.PeakTrackEarly,'TrackLate',st.PeakTrackLate, ...
                'CandidateRN',st.PeakCandidateRN,'DetectableRN',st.PeakDetectableRN, ...
                'Polarity',st.PeakPolarity,'AboveThresholdOnly',st.PeaksAboveThresholdOnly, ...
                'BaselineAmpWindow',st.BaselineAmpWindow,'EdgeMs',st.PeakEdgeMs, ...
                'Bootstrap',st.PeakBootstrap,'Seed',st.Seed};
        end

        function out = rejectAboveIn(obj,S,cks,valueV,feature)
            total = 0; nc = 0;
            for i = 1:numel(cks)
                f = obj.featureValues(S,cks(i),feature);
                if isempty(f), continue; end
                r = S.rowOf(cks(i));
                rej = false(size(f));
                try
                    rej = logical(S.Conditions.Rejected{r});
                    rej = reshape(rej,size(f));
                catch
                end
                cols = find(f(:).' > valueV & ~rej(:).');
                if isempty(cols), continue; end
                S.setSweepsRejected(cks(i),cols,true);
                total = total + numel(cols);
                nc = nc + 1;
            end
            out = struct('Text',sprintf('Rejected %d sweep(s) with %s above %s in %d condition(s)', ...
                total,feature,mabr.ui.analysis.Model.featureValueText(valueV,feature),nc));
        end

        function f = featureValues(~,S,ck,feature)
            % One value per sweep (columns of Sweeps), volts or a ratio --
            % the values the Trials tab plots: measure()'s Features, else
            % (a session read from raw and not yet measured)
            % SingleTrial.features over the response window measure() uses,
            % within the condition's Extent, as the tab computes them.
            f = [];
            r = S.rowOf(ck);
            try
                F = S.Conditions.Features{r};
                if istable(F) && ismember(char(feature),F.Properties.VariableNames)
                    f = double(F.(feature));
                    return
                end
            catch
            end
            X = S.Conditions.Sweeps{r};
            if isempty(X), return; end
            t = double(S.Time(:));
            w = S.ResponseWindow;
            try
                % (exactly what measure() was last given, as TrialView's
                % measureOpts reads it)
                if isfield(S.StepOptions,'measure') && isfield(S.StepOptions.measure,'ResponseWindow') && ...
                        ~isempty(S.StepOptions.measure.ResponseWindow)
                    w = S.StepOptions.measure.ResponseWindow;
                end
            catch
            end
            rows = mabr.analysis.Artifacts.windowMask(t,w);
            try
                e = double(S.Conditions.Extent(r,:));
                if all(isfinite(e)), rows = rows & t >= e(1) & t <= e(2); end
            catch
            end
            Ft = mabr.analysis.SingleTrial.features(X,rows,[]);
            f = double(Ft.(feature));
            f = f(:);
        end

        % ---- overrides and settings sources ------------------------------
        function s = settingsFor(obj,p)
            % Settings precedence: the app's override, the project's own,
            % the user's defaults (pref).
            if ~isempty(obj.SettingsOverride)
                s = obj.SettingsOverride;
                return
            end
            s = [];
            try
                ps = p.Settings;
                if isa(ps,'mabr.analysis.Settings')
                    s = ps;
                elseif isstruct(ps) && ~isempty(fieldnames(ps))
                    s = mabr.analysis.Settings.fromStruct(ps);
                end
            catch
            end
            if isempty(s), s = mabr.analysis.Settings.loadPrefs(); end
        end

        function rf = resultsFolderFor(obj,root)
            rf = obj.ResultsFolderOverride;
            if rf ~= "", return; end
            try
                if ispref(obj.PrefGroup,'OfflineResultsFolders')
                    M = getpref(obj.PrefGroup,'OfflineResultsFolders');
                    for i = 1:numel(M)
                        if strcmpi(string(M(i).Root),root)
                            rf = string(M(i).Folder);
                            return
                        end
                    end
                end
            catch
            end
        end

        function ov = unitOverrideFor(obj,key)
            ov = struct('InputFullScale',NaN,'AmplifierGain',NaN);
            if isempty(obj.Project), return; end
            try
                o = obj.Project.sessionOverrides(key);
                ov.InputFullScale = double(o.UnitOverride.InputFullScale);
                ov.AmplifierGain  = double(o.UnitOverride.AmplifierGain);
            catch
            end
        end

        function applyProjectOverrides(obj,S,key)
            % The project's per-session values onto S -- unit overrides,
            % TimeOffset and ConductionDelayOverride, NaN included -- through
            % Project.applyOverrides, the one place they reach a Session (so
            % the app and a batch build the same one). A key with no Sessions
            % row (a pool) gets NaN -- none -- as Project.batchItems gives a
            % batch, never what its results file happened to record.
            if isempty(obj.Project), return; end
            try
                obj.Project.applyOverrides(S,key);
            catch me
                mabr.log.vprintf(1,'Model: the project''s overrides for %s were not applied (%s).', ...
                    key,me.message);
            end
        end

        function pat = blindPattern(obj)
            % One regular expression matching every name blind review hides
            % (blindText): the catalog's session keys, names and subjects and
            % the project's pool keys and names, longest first, each a whole
            % word (so subject 12 does not eat "12 conditions" or
            % SUBJ-ID-1254's "SUBJ-ID-12"). Cached per catalog and pool set.
            pat = "";
            c = obj.Catalog;
            tok = strings(0,1);
            try
                T = c.Sessions;
                for v = ["Key","Name","Subject"]
                    if ismember(v,string(T.Properties.VariableNames))
                        tok = [tok; reshape(string(T.(v)),[],1)]; %#ok<AGROW>
                    end
                end
            catch
            end
            try
                P = obj.Project.Pools;
                tok = [tok; reshape(string(P.Key),[],1); reshape(string(P.Name),[],1)];
            catch
            end
            tok = tok(~ismissing(tok));
            tok = unique(strtrim(tok));
            tok = tok(strlength(tok) >= 2);
            if isempty(tok), return; end
            sig = string(numel(tok)) + "|" + strjoin(tok,"|");
            if isstruct(obj.BlindCache) && isfield(obj.BlindCache,'Sig') && obj.BlindCache.Sig == sig
                pat = obj.BlindCache.Pat;
                return
            end
            [~,ix] = sort(strlength(tok),'descend');
            tok = tok(ix);
            % (keys are folder paths: either slash matches either)
            esc = regexptranslate('escape',cellstr(tok));
            esc = regexprep(esc,'(\\\\|/)','[\\\\/]');
            pat = "(?<![A-Za-z0-9])(" + strjoin(string(esc),"|") + ")(?![A-Za-z0-9])";
            obj.BlindCache = struct('Sig',sig,'Pat',pat);
        end

        function ov = unitOverrideOf(~,S)
            ov = struct('InputFullScale',NaN,'AmplifierGain',NaN);
            try
                u = S.UnitOverride;
                ov.InputFullScale = double(u.InputFullScale);
                ov.AmplifierGain  = double(u.AmplifierGain);
            catch
            end
        end

        function r = projectRow(obj,key)
            r = [];
            if isempty(obj.Project), return; end
            try
                r = find(string(obj.Project.Sessions.Key) == key,1);
            catch
            end
        end

        function name = poolName(obj,key)
            name = key;
            try
                P = obj.Project.Pools;
                r = find(string(P.Key) == key,1);
                if ~isempty(r), name = string(P.Name(r)); end
            catch
            end
        end

        function n = displayName(obj)
            n = obj.SessionKey;
            try
                n = string(obj.Session.Name);
            catch
            end
        end

        % ---- label helpers -------------------------------------------------
        function note = setLabel(obj,keys,name,value,undoText,doneText,source)
            % label's and setHidden's work: Project.label as one undo entry
            % (UNDOTEXT), then ProjectChanged(labels) and the status line
            % (DONETEXT; "" = the coercion note, else "<name> set to
            % <value> for n item(s)"), each raised with SOURCE.
            obj.assertNotBusy();
            obj.requireRoot();
            keys = reshape(keys,[],1);
            before = obj.labelValues(keys,name);
            [~,note] = obj.Project.label(keys,name,value);
            note = string(note);
            if isempty(note) || ismissing(note), note = ""; end
            after = obj.labelValues(keys,name);
            e = obj.newEntry(undoText,"labels");
            e.Keys = keys;
            e.Name = name;
            e.Before = before;
            e.After = after;
            obj.pushUndo(e);
            obj.ViewCache = [];
            obj.markDirty("project");
            txt = string(doneText);
            if txt == "", txt = note; end
            if txt == ""
                txt = sprintf('%s set to %s for %d item(s)',name, ...
                    mabr.ui.analysis.Model.valueText(value),numel(keys));
            end
            obj.ev("ProjectChanged","labels",source,Keys=keys);
            obj.ev("StatusChanged","save",source,Text=txt + " — Ctrl+Z to undo");
        end

        function vals = labelValues(obj,keys,name)
            % The current value of label NAME for each key (cell).
            vals = cell(numel(keys),1);
            P = obj.Project;
            for i = 1:numel(keys)
                vals{i} = [];
                try
                    T = P.Sessions;
                    if ismember(char(name),T.Properties.VariableNames) && any(string(T.Key) == keys(i))
                        vals{i} = T.(name)(find(string(T.Key) == keys(i),1));
                        continue
                    end
                    U = P.Subjects;
                    if ismember(char(name),U.Properties.VariableNames)
                        sub = keys(i);
                        rs = find(string(T.Key) == keys(i),1);
                        if ~isempty(rs), sub = string(T.Subject(rs)); end
                        ru = find(string(U.Subject) == sub,1);
                        if ~isempty(ru), vals{i} = U.(name)(ru); end
                    end
                catch
                end
            end
        end

        function info = columnInfo(obj,name)
            info = struct('Level',"session",'Type',"text",'Levels',strings(1,0));
            try
                C = obj.Project.Columns;
                r = find(string(C.Name) == name,1);
                if isempty(r), return; end
                info.Level = string(C.Level(r));
                info.Type = string(C.Type(r));
                lv = C.Levels(r);
                if iscell(lv), lv = lv{1}; end
                info.Levels = reshape(string(lv),1,[]);
            catch
            end
        end

        function keys = columnKeys(obj,level)
            keys = strings(0,1);
            try
                if level == "subject"
                    keys = string(obj.Project.Subjects.Subject);
                else
                    keys = string(obj.Project.Sessions.Key);
                end
            catch
            end
        end

        % ---- sessions in order, review ------------------------------------
        function order = browserKeys(obj)
            order = obj.BrowserOrder;
            if isempty(order) && ~isempty(obj.Catalog)
                try
                    order = string(obj.Catalog.Sessions.Key);
                catch
                end
            end
        end

        function tf = isOpenable(obj,key)
            % Not failed, not empty.
            tf = true;
            try
                if ~startsWith(key,"pool:")
                    T = obj.Catalog.Sessions;
                    r = find(string(T.Key) == key,1);
                    if ~isempty(r) && ismember('NumIncluded',T.Properties.VariableNames) && T.NumIncluded(r) == 0
                        tf = false;
                        return
                    end
                end
                V = obj.projectView();
                if ~isempty(V) && ismember('Status',V.Properties.VariableNames)
                    r = find(string(V.Key) == key,1);
                    if ~isempty(r) && string(V.Status(r)) == "failed", tf = false; end
                end
            catch
            end
        end

        function tf = sessionNeedsReview(obj,key)
            % A session with analysed series not all reviewed.
            tf = false;
            try
                V = obj.projectView();
                r = find(string(V.Key) == key,1);
                if isempty(r), return; end
                if ismember(string(V.Status(r)),["none","failed"]), return; end
                rv = V.Reviewed(r);
                ns = V.NumSeries(r);
                if iscell(rv), rv = rv{1}; end
                if isstring(rv) || ischar(rv)
                    t = sscanf(char(rv),'%d/%d');
                    if numel(t) == 2, rv = t(1); ns = t(2); else, rv = NaN; end
                end
                tf = double(ns) > 0 && double(rv) < double(ns);
            catch
                tf = false;
            end
        end

        function sk = needingReview(obj,keys,from,step)
            sk = "";
            S = obj.Session;
            if isempty(S) || isempty(keys), return; end
            T = S.Thresholds;
            if isempty(T) || height(T) == 0, return; end
            need = false(numel(keys),1);
            tk = string(T.Key);
            for i = 1:numel(keys)
                r = find(tk == keys(i),1);
                if isempty(r), continue; end
                d = string(T.Decision(r));
                need(i) = ismissing(d) || d == "";
            end
            i0 = find(keys == from,1);
            if step > 0
                if isempty(i0), i0 = 0; end
                k = find(need((i0+1):end),1,'first');
                if ~isempty(k), sk = keys(i0 + k); end
            else
                if isempty(i0), i0 = numel(keys) + 1; end
                k = find(need(1:i0-1),1,'last');
                if ~isempty(k), sk = keys(k); end
            end
        end

        function keys = scopeKeys(obj,scope,keys)
            % Sessions with results, by export scope ("in study" and "all"
            % leave the hidden ones out; a selection is taken as given).
            keys = reshape(string(keys),[],1);
            switch string(scope)
                case "current"
                    keys = obj.SessionKey;
                    if keys == "", keys = strings(0,1); end
                case "selected"
                    % as given
                case "instudy"
                    try
                        keys = string(obj.Project.studyKeys());
                    catch
                        keys = strings(0,1);
                    end
                otherwise   % "all"
                    keys = obj.allKeys();
            end
            keep = false(numel(keys),1);
            for i = 1:numel(keys)
                keep(i) = obj.hasResults(keys(i));
            end
            keys = keys(keep);
        end

        function items = batchItems(obj,keys)
            % Batch.run's work list: Project.batchItems (paths, results
            % file, exclusions and every override of each key).
            items = obj.Project.batchItems(reshape(string(keys),[],1),obj.Catalog);
        end

        function use = currentFileUse(obj,ids)
            % Whether each file is in use now (i.e. not excluded by the user).
            use = true(numel(ids),1);
            S = obj.Session;
            excl = strings(0,1);
            try
                excl = reshape(string(S.Exclude),[],1);
            catch
                try
                    F = S.Files;
                    excl = string(F.FileId(string(F.Reason) == "excluded by user"));
                catch
                end
            end
            use(ismember(ids,excl)) = false;
        end

        function f = flatKey(obj,key)
            % A session key as a file name.
            if key == "." && ~isempty(obj.Catalog)
                [~,f] = fileparts(char(obj.ResultsFile));
                f = string(f);
                return
            end
            f = regexprep(string(key),'[^A-Za-z0-9_\-]','_');
        end

        function path = offerStudyRoot(obj,path)
            study = "";
            try
                study = string(mabr.analysis.Catalog.suggestStudyRoot(path));
            catch
            end
            if isempty(study) || ismissing(study) || study == "", return; end
            [~,sn] = fileparts(char(study));
            [~,fn] = fileparts(char(path));
            a = "Open " + string(sn);
            b = "Open " + string(fn) + " only";
            msg = sprintf(['“%s” looks like one animal''s folder. Open the study folder “%s” ' ...
                'instead? Results and labels for all animals are then kept together.'],fn,sn);
            c = obj.confirm(string(msg),"Open the study folder?",[a b],a);
            if c == a, path = study; end
        end
    end

    % =====================================================================
    methods (Static)
        function S = emptyStatus()
            % Status with nothing open.
            D = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
                'VariableNames',{'Step','Field','Old','New'});
            S = struct('State',"none",'Text',"",'Differences',D,'FromStep',"",'Seconds',NaN);
        end

        function S = emptySelection()
            % Selection with nothing selected.
            S = struct('ConditionKey',"",'SeriesKey',"",'Level',NaN,'Wave',"",'Kind',"P", ...
                'Sweeps',zeros(1,0),'Anchor',NaN);
        end
    end

    methods (Static, Access = private)
        function P = emptyFileUse()
            P = struct('FileIds',strings(0,1),'Use',false(0,1));
        end

        function a = defaultAnalyst()
            a = string(getenv('USERNAME'));
            try
                if ispref('MABR','OfflineAnalysisAnalyst')
                    v = string(getpref('MABR','OfflineAnalysisAnalyst'));
                    if isscalar(v) && strlength(v) > 0, a = v; end
                end
            catch
            end
        end

        function p = absolutePath(p)
            p = string(p);
            c = char(p);
            if ~(numel(c) >= 2 && (c(2) == ':' || startsWith(c,'\\') || startsWith(c,'/')))
                c = fullfile(pwd,c);
            end
            % strip a trailing separator (but keep "C:\")
            while numel(c) > 3 && any(c(end) == '\/')
                c(end) = [];
            end
            p = string(c);
        end

        function s = fileStamp(file)
            s = struct('Exists',false,'Bytes',NaN,'Datenum',NaN,'Time',NaT);
            file = string(file);
            if file == "" || ~isfile(file), return; end
            d = dir(char(file));
            if isempty(d), return; end
            s.Exists = true;
            s.Bytes = d.bytes;
            s.Datenum = d.datenum;
            s.Time = datetime(d.datenum,'ConvertFrom','datenum');
        end

        function tf = sameStamp(a,b)
            tf = a.Exists == b.Exists && (~a.Exists || ...
                (a.Bytes == b.Bytes && abs(a.Datenum - b.Datenum) < 1e-8));
        end

        function tf = canWrite(folder)
            % Can a file be created in FOLDER (creating FOLDER if need be)?
            tf = false;
            folder = char(folder);
            try
                if ~isfolder(folder)
                    [ok,~] = mkdir(folder);
                    if ~ok, return; end
                end
                f = [tempname(folder) '.probe'];
                fid = fopen(f,'w');
                if fid < 0, return; end
                fclose(fid);
                delete(f);
                tf = true;
            catch
                tf = false;
            end
        end

        function st = stepStateOf(S)
            st = [];
            try
                st = S.StepState;
            catch
            end
        end

        function [tf,old] = peakOffsetChanged(S)
            % True when the session's stored peaks were picked at another
            % latency offset (Peaks.LatencyOffset) than its LatencyOffset now.
            tf = false;
            old = NaN;
            try
                P = S.Peaks;
                if ~istable(P) || height(P) == 0 || ...
                        ~ismember('LatencyOffset',P.Properties.VariableNames)
                    return
                end
                po = double(P.LatencyOffset);
                po = po(isfinite(po));
                cur = double(S.LatencyOffset);
                if isempty(po) || ~isfinite(cur), return; end
                k = find(abs(po - cur) > 1e-9,1);
                if ~isempty(k)
                    tf = true;
                    old = po(k);
                end
            catch
            end
        end

        function tf = isAnalysed(S)
            tf = false;
            try
                st = S.StepState;
                tf = isstruct(st) && isfield(st,'detect') && ~isempty(st.detect);
            catch
            end
        end

        function at = analysedAt(S)
            at = NaT;
            try
                st = S.StepState;
                f = fieldnames(st);
                for i = 1:numel(f)
                    v = st.(f{i});
                    if isstruct(v) && isfield(v,'At') && ~isempty(v.At)
                        t = datetime(char(string(v.At)),'InputFormat','yyyy-MM-dd''T''HH:mm:ss');
                        if isnat(at) || t > at, at = t; end
                    end
                end
            catch
            end
        end

        function D = normalizeDiff(D)
            if ~istable(D) || isempty(D) || width(D) == 0
                D = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
                    'VariableNames',{'Step','Field','Old','New'});
                return
            end
            for v = ["Step","Field","Old","New"]
                if ~ismember(char(v),D.Properties.VariableNames)
                    D.(v) = repmat("",height(D),1);
                else
                    D.(v) = string(D.(v));
                end
            end
            D = D(:,{'Step','Field','Old','New'});
        end

        function k = earliestStep(steps)
            order = mabr.analysis.Settings.Steps;
            steps(steps == "data") = "segment";
            k = "";
            for s = order
                if any(steps == s), k = s; return; end
            end
            if any(steps == "report"), k = ""; end
        end

        function clearSink(S)
            try
                S.ProgressFcn = [];
            catch
            end
        end

        function setMessageFcn(S,fcn)
            try
                if isvalid(S), S.MessageFcn = fcn; end
            catch
            end
        end

        function out = callReport(fcn,S)
            % Call an edit; its report struct when it returns one.
            out = [];
            try
                out = fcn(S);
            catch me
                if any(strcmp(me.identifier,{'MATLAB:TooManyOutputs','MATLAB:maxlhs'}))
                    fcn(S);
                else
                    rethrow(me);
                end
            end
        end

        function t = reportText(out,default)
            t = string(default);
            try
                if isstruct(out) && isfield(out,'Text') && strlength(string(out.Text)) > 0
                    t = string(out.Text);
                elseif isstring(out) || ischar(out)
                    if strlength(string(out)) > 0, t = string(out); end
                end
            catch
            end
        end

        function t = batchText(T)
            t = "Batch finished.";
            try
                st = string(T.Status);
                nOk = sum(startsWith(st,"ok"));
                parts = sprintf('%d ok',nOk);
                for s = ["failed","skipped","cancelled"]
                    n = sum(st == s);
                    if n > 0, parts = parts + sprintf(', %d %s',n,s); end
                end
                t = "Batch: " + parts + ".";
            catch
            end
        end

        function v = rowValue(row,name,default)
            v = default;
            try
                if istable(row)
                    if ismember(name,row.Properties.VariableNames)
                        v = row.(name)(1);
                    end
                elseif isstruct(row) && isfield(row,name)
                    v = row.(name);
                end
                if iscell(v), v = v{1}; end
                if isempty(v), v = default; end
            catch
                v = default;
            end
        end

        function c = column(C,rows,name,def)
            n = numel(rows);
            if islogical(def), c = false(n,1); else, c = nan(n,1); end
            if ~ismember(name,C.Properties.VariableNames), return; end
            for i = 1:n
                if rows(i) < 1, continue; end
                v = C.(name)(rows(i));
                if iscell(v), v = v{1}; end
                if isempty(v), continue; end
                c(i) = double(v(1));
            end
        end

        function f = keyField(keys,name)
            % The value of NAME in each key ("" when absent).
            f = strings(size(keys));
            for i = 1:numel(keys)
                t = regexp(char(keys(i)),['(?:^|\|)' char(name) '=([^|]*)'],'tokens','once');
                if ~isempty(t), f(i) = string(t{1}); end
            end
        end

        function s = keyLabel(key)
            % A key as words when the Session cannot say better.
            parts = split(string(key),"|");
            vals = strings(0,1);
            for p = reshape(parts,1,[])
                kv = split(p,"=");
                if numel(kv) == 2 && kv(1) ~= "AcqMode"
                    vals(end+1) = kv(2); %#ok<AGROW>
                end
            end
            s = strjoin(vals," ");
        end

        function v = pick(tf,a,b)
            if tf, v = a; else, v = b; end
        end

        function s = num(v)
            if v == round(v), s = string(sprintf('%g',v)); else, s = string(sprintf('%.1f',v)); end
        end

        function s = valueText(v)
            if isstring(v) || ischar(v)
                s = """" + string(v) + """";
            elseif islogical(v)
                if v, s = "true"; else, s = "false"; end
            elseif isnumeric(v) && isscalar(v)
                s = string(sprintf('%g',v));
            else
                s = "the new value";
            end
        end

        function tf = isBlank(v)
            tf = isempty(v) || (isstring(v) && all(ismissing(v) | v == "")) || ...
                (isnumeric(v) && all(isnan(v(:))));
        end

        function s = featureValueText(v,feature)
            % A rejection threshold in words: microvolts for the voltage
            % features, a plain number for the ratios (TemplateAmp 1.5 is
            % "1.5", never "1500000 µV").
            if any(string(feature) == ["TemplateAmp","TemplateR"])
                s = string(sprintf('%.3g',v));
            else
                s = mabr.ui.analysis.Style.formatUV(v);
            end
        end

        function f = featureName(f)
            switch lower(regexprep(string(f),'[^A-Za-z]',''))
                case "rms",                 f = "RMS";
                case {"pp","ptop"},         f = "P2P";
                case {"maxx","maxabs","max"}, f = "MaxAbs";
                case "templateamp",         f = "TemplateAmp";
                case "templater",           f = "TemplateR";
                otherwise
                    f = string(f);
                    if ~ismember(f,["RMS","P2P","MaxAbs","TemplateAmp","TemplateR"])
                        f = "MaxAbs";
                    end
            end
        end

        function c = nameValues(s)
            f = fieldnames(s);
            c = cell(1,2*numel(f));
            for i = 1:numel(f)
                c{2*i-1} = f{i};
                c{2*i} = s.(f{i});
            end
        end

        function tf = hasClass(name)
            tf = ~isempty(meta.class.fromName(char(name)));
        end

        function o = exportDefaults(opts)
            o = struct('Scope',"all",'Keys',strings(0,1), ...
                'Tables',["sessions","subjects","conditions","thresholds","peaks", ...
                "peak_measures","io_slopes","waveforms","notes"], ...
                'Formats',"csv",'ThresholdsAll',false,'OnlyReviewed',false, ...
                'IncludeExcluded',false,'IncludeTestMode',false,'WaveformWindow',[-2 10], ...
                'RScript',true,'Script',false,'Folder',"",'RawFormats',"parquet");
            if ~isstruct(opts), return; end
            f = fieldnames(o);
            for i = 1:numel(f)
                if isfield(opts,f{i}) && ~isempty(opts.(f{i}))
                    o.(f{i}) = opts.(f{i});
                end
            end
            % ExportDialog may name AllMethods for ThresholdsAll
            if isfield(opts,'AllMethods') && ~isempty(opts.AllMethods)
                o.ThresholdsAll = logical(opts.AllMethods);
            end
            o.Scope = string(o.Scope);
            o.Tables = reshape(string(o.Tables),1,[]);
            o.Folder = string(o.Folder);
            o.Keys = reshape(string(o.Keys),[],1);
        end

        function rep = revertIn(S,sk,ck)
            S.clearDecision(sk);
            try
                S.setThresholdNote(sk,"");
            catch
            end
            S.clearPeakOverrides(sk);
            D = S.DetectionOverrides;
            if ~isempty(D) && height(D) > 0
                for k = reshape(ck,1,[])
                    if any(string(D.Key) == k)
                        S.setDetectionOverride(k,NaN);
                    end
                end
            end
            rep = [];
        end

        function rep = clearAllIn(S,keys,rejections)
            for k = reshape(keys,1,[])
                try
                    S.clearDecision(k);
                    S.setThresholdNote(k,"");
                catch
                end
            end
            S.clearPeakOverrides("");
            D = S.DetectionOverrides;
            if ~isempty(D) && height(D) > 0
                for k = reshape(unique(string(D.Key)),1,[])
                    S.setDetectionOverride(k,NaN);
                end
            end
            if rejections
                S.clearManualRejections([]);
            end
            rep = struct('Text',"Every manual edit of this session cleared");
        end
    end
end
