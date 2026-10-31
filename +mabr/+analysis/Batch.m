classdef Batch
% mabr.analysis.Batch  Analyse many sessions with one set of settings, headless.
%
%   The overnight run: every session of a study taken through
%   mabr.analysis.Session.analyze with one mabr.analysis.Settings, its
%   results written where the analysis app looks for them, and a line of log
%   per session written the moment it finishes -- so a run stopped by a power
%   cut says exactly how far it got.
%
%       T = mabr.analysis.Batch.runFolder("D:\data\OFC_NoiseExposure", ...
%               mabr.analysis.Settings(), ResultsFolder="D:\results\OFC");
%       T(T.Status == "failed",:)
%
%   run(items,settings) is the loop; runFolder(root,settings) builds the
%   items from a mabr.analysis.Catalog of a data folder (and the pools of its
%   mabr.analysis.Project, when there is one) and calls it. Per session:
%     - a Test Mode session is skipped ("skipped: Test Mode") unless
%       IncludeTestMode -- its samples are the stimulus, not a subject;
%     - a session whose results are CURRENT for these settings and its files
%       (isCurrent: every step's recorded settings equal the settings' and
%       the files fingerprint as they did) and that were made with the same
%       per-session overrides (UnitOverride, TimeOffset, ConductionDelay) is
%       skipped when SkipCurrent;
%     - otherwise it is read (Session(paths,KeepTraces=false,...)), the edits
%       of any existing results file are adopted (Session.adoptEdits: curation,
%       overrides and manual rejections survive a re-run), it is analysed,
%       the previous results file is copied to <ResultsFolder>/.history
%       (the newest three per session are kept), and the new results are
%       written WITHOUT sweeps (the GUI reads the raw files again when it
%       needs them). A results file that could not be read is copied to
%       .history as <session>_unreadable_<stamp>.mat instead, which is never
%       pruned;
%     - the analysis takes minutes, and a second MATLAB (the analysis app, a
%       second batch) may save curation to the same results file meanwhile,
%       so the file's size and time are noted when it is read and compared
%       again before it is replaced. If it changed, the file is read again
%       and its edits adopted again before the save; if it cannot be read, or
%       holds manual rejections or file exclusions this run did not analyse
%       (the numbers would not follow from the edits), the results file is
%       left alone, this run's results are written beside it as
%       <name>.conflict.mat and the session's Status is "conflict".
%   A failure is caught per session ("failed", with the error text, also
%   logged through mabr.log.vprintf) and the run goes on, unless
%   StopOnError. CancelFcn() returning true stops the run after the session
%   in progress (the rest are "cancelled"); a progress sink throwing
%   mabr:analysis:cancelled stops the session in progress -- nothing is
%   written for it -- and the run.
%
%   Batch never writes a preference and never opens a window; the summary
%   figures (SummaryFigure) are drawn in invisible figures and closed.
%
%   See also mabr.analysis.Session, mabr.analysis.Settings,
%   mabr.analysis.Catalog, mabr.analysis.Project
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        % Results files kept per session in .history.
        HistoryKeep = 3

        % Columns of the log CSV, in order.
        LogColumns = ["Key","Status","Seconds","Message","SettingsHash","ResultsFile"]
    end

    methods (Static)
        function T = run(items,settings,opts)
            % Analyse every session of items.
            %
            %   items   table, one row per session: Key (string), Paths (cell
            %           of string columns: its folder(s)), ResultsFile (string),
            %           and optionally Exclude (cell of FileId columns),
            %           UnitOverride (cell of structs InputFullScale /
            %           AmplifierGain), TestMode (logical: every file is Test
            %           Mode), Name (string), TimeOffset and ConductionDelay
            %           (ms, NaN = none: the session's overrides, see
            %           Session.LatencyOffset)
            %   settings  mabr.analysis.Settings (default Settings())
            %   opts.SkipCurrent      skip sessions whose results are current (true)
            %   opts.Steps            analyze's Steps ("all")
            %   opts.IncludeTestMode  analyse Test Mode sessions too (false)
            %   opts.StopOnError      stop at the first failure (false)
            %   opts.KeepCurated      carry curation (true)
            %   opts.LogFile          log CSV ("" = <ResultsFolder>/logs/
            %                         batch_<yyMMdd'T'HHmmss>.csv)
            %   opts.ResultsFolder    the results store ("" = the folder of the
            %                         first item's ResultsFile); .history, logs
            %                         and figures go under it
            %   opts.SummaryFigure    write <ResultsFolder>/figures/<key>.png (false)
            %   opts.FiguresFolder    where those go ("" = <ResultsFolder>/figures)
            %   opts.ProgressFcn      progress sink fcn(message,count,total),
            %                         handed to every Session too
            %   opts.CancelFcn        [] or @() tf: true stops after the current session
            %   opts.Project          [] or a mabr.analysis.Project whose
            %                         LastRun/LastError are updated (in memory);
            %                         items without UnitOverride, TimeOffset or
            %                         ConductionDelay columns take its
            %                         per-session overrides (sessionOverrides)
            %   opts.Analyst          stamped on the sessions' edits
            %   T  (returned) table Key, Status ("ok", "ok (no thresholds)",
            %      "skipped", "failed", "cancelled", "conflict" -- the results
            %      file changed while the session was analysed and could not
            %      be reconciled, see above), Seconds, Message, ResultsFile,
            %      SettingsHash -- one row per item, in order
            arguments
                items table
                settings = []
                opts.SkipCurrent (1,1) logical = true
                opts.Steps (1,:) string = "all"
                opts.IncludeTestMode (1,1) logical = false
                opts.StopOnError (1,1) logical = false
                opts.KeepCurated (1,1) logical = true
                opts.LogFile (1,1) string = ""
                opts.ResultsFolder (1,1) string = ""
                opts.SummaryFigure (1,1) logical = false
                opts.FiguresFolder (1,1) string = ""
                opts.ProgressFcn = []
                opts.CancelFcn = []
                opts.Project = []
                opts.Analyst (1,1) string = string(getenv('USERNAME'))
            end
            s = mabr.analysis.Batch.asSettings(settings);
            pr = s.problems();
            pr = pr(pr ~= "");
            if ~isempty(pr)
                error('mabr:analysis:Batch:badSettings','These settings cannot be used: %s', ...
                    strjoin(reshape(pr,1,[]),'; '));
            end
            items = mabr.analysis.Batch.normalizeItems(items,opts.Project);
            n = height(items);
            hash = string(s.hash());
            rf = opts.ResultsFolder;
            if rf == "" && n > 0
                rf = string(fileparts(char(items.ResultsFile(1))));
            end
            logFile = opts.LogFile;
            if logFile == "" && rf ~= ""
                logFile = string(fullfile(char(rf),'logs', ...
                    ['batch_' char(datetime('now'),'yyMMdd''T''HHmmss') '.csv']));
            end
            figFolder = opts.FiguresFolder;
            if figFolder == "" && rf ~= "", figFolder = string(fullfile(char(rf),'figures')); end

            Status = repmat("cancelled",n,1);
            Seconds = zeros(n,1);
            Message = strings(n,1);
            for i = 1:n
                if i > 1 && mabr.analysis.Batch.cancelled(opts.CancelFcn), break; end
                key = items.Key(i);
                try
                    mabr.analysis.Batch.progress(opts.ProgressFcn, ...
                        sprintf('Session %d of %d: %s',i,n,key),i-1,n);
                catch ME
                    if strcmp(ME.identifier,'mabr:analysis:cancelled'), break; end
                    rethrow(ME);
                end
                t0 = tic;
                [Status(i),Message(i)] = mabr.analysis.Batch.one(items(i,:),s,opts,rf,figFolder);
                Seconds(i) = toc(t0);
                mabr.analysis.Batch.appendLog(logFile,key,Status(i),Seconds(i),Message(i),hash, ...
                    items.ResultsFile(i));
                mabr.analysis.Batch.noteProject(opts.Project,key,Status(i),Message(i));
                if Status(i) == "failed"
                    mabr.log.vprintf(1,'Batch: %s failed: %s',key,Message(i));
                elseif Status(i) == "conflict"
                    mabr.log.vprintf(1,'Batch: %s: %s',key,Message(i));
                end
                if Status(i) == "cancelled" || (Status(i) == "failed" && opts.StopOnError), break; end
            end
            for j = find(Status == "cancelled" & Seconds == 0).'
                if Message(j) == "", Message(j) = "cancelled before it started"; end
            end
            try
                mabr.analysis.Batch.progress(opts.ProgressFcn,'Batch finished',n,n);
            catch
                % a sink that cancels now has nothing left to cancel
            end
            T = table(items.Key,Status,Seconds,Message,items.ResultsFile,repmat(hash,n,1), ...
                'VariableNames',{'Key','Status','Seconds','Message','ResultsFile','SettingsHash'});
        end

        function T = runFolder(root,settings,opts)
            % Analyse every session under a data folder (the script entry).
            %
            % A mabr.analysis.Catalog of root is scanned (its cache in
            % CacheFolder, never under root), its sessions -- and the pools of
            % the study's mabr.analysis.Project, when one exists -- become the
            % items of run(), each with the exclusions and overrides the
            % project holds for it, and the results go to the catalog's
            % results store (or ResultsFolder). The project is updated
            % (LastRun, LastError) and saved when it was found or
            % SaveProject is true.
            %
            %   root                data folder
            %   settings            mabr.analysis.Settings (default: the
            %                       project's settings, else Settings())
            %   opts.ResultsFolder  results store ("" = <AnalysisRoot>/MABR_Analysis)
            %   opts.CacheFolder    the catalog's cache folder ("" = its default)
            %   opts.Keys           only these session keys (default all)
            %   opts.SaveProject    save the project afterwards (default: when
            %                       it existed)
            %   every other option of run() (SkipCurrent, Steps,
            %   IncludeTestMode, StopOnError, KeepCurated, LogFile,
            %   SummaryFigure, FiguresFolder, ProgressFcn, CancelFcn, Analyst)
            %   T  (returned) as run()
            arguments
                root (1,1) string
                settings = []
                opts.ResultsFolder (1,1) string = ""
                opts.CacheFolder (1,1) string = ""
                opts.Keys (:,1) string = strings(0,1)
                opts.SaveProject = []
                opts.SkipCurrent (1,1) logical = true
                opts.Steps (1,:) string = "all"
                opts.IncludeTestMode (1,1) logical = false
                opts.StopOnError (1,1) logical = false
                opts.KeepCurated (1,1) logical = true
                opts.LogFile (1,1) string = ""
                opts.SummaryFigure (1,1) logical = false
                opts.FiguresFolder (1,1) string = ""
                opts.ProgressFcn = []
                opts.CancelFcn = []
                opts.Analyst (1,1) string = string(getenv('USERNAME'))
            end
            cargs = {'ResultsFolder',opts.ResultsFolder};
            if opts.CacheFolder ~= "", cargs = [cargs {'CacheFolder',opts.CacheFolder}]; end
            c = mabr.analysis.Catalog(root,cargs{:});
            c.scan(ProgressFcn=opts.ProgressFcn);
            p = [];
            existed = false;
            if exist('mabr.analysis.Project','class') == 8
                try
                    existed = isfile(fullfile(char(c.ResultsFolder),'project.mat'));
                    p = mabr.analysis.Project.open(c.ResultsFolder);
                    p.ensureSessions(c);
                catch ME
                    mabr.log.vprintf(1,'Batch: the project could not be opened (%s); running without it.', ...
                        ME.message);
                    p = [];
                end
            end
            if isempty(settings) && ~isempty(p)
                try
                    if ~isempty(p.Settings), settings = p.Settings; end
                catch
                end
            end
            items = mabr.analysis.Batch.itemsFromCatalog(c,p,opts.Keys);
            T = mabr.analysis.Batch.run(items,settings,SkipCurrent=opts.SkipCurrent, ...
                Steps=opts.Steps,IncludeTestMode=opts.IncludeTestMode, ...
                StopOnError=opts.StopOnError,KeepCurated=opts.KeepCurated, ...
                LogFile=opts.LogFile,ResultsFolder=c.ResultsFolder, ...
                SummaryFigure=opts.SummaryFigure,FiguresFolder=opts.FiguresFolder, ...
                ProgressFcn=opts.ProgressFcn,CancelFcn=opts.CancelFcn,Project=p, ...
                Analyst=opts.Analyst);
            save = opts.SaveProject;
            if isempty(save), save = existed; end
            if ~isempty(p) && logical(save)
                try
                    p.save();
                catch ME
                    mabr.log.vprintf(1,'Batch: the project could not be saved (%s).',ME.message);
                end
            end
        end

        function tf = isCurrent(resultsFile,settings,fingerprint)
            % Whether a results file is current for these settings and files.
            %
            % Current: every analysis step recorded settings (StepState)
            % equal to settings.stepSettings(step) -- isequaln, field by field
            % -- and the fingerprint the segment step recorded equals
            % fingerprint (Session.folderFingerprint of the session's folders
            % and exclusions). Only the small variables are read.
            %
            %   resultsFile  a results v2 file
            %   settings     mabr.analysis.Settings (or its struct)
            %   fingerprint  the data fingerprint now ("" = not compared)
            %   tf           (returned) logical
            arguments
                resultsFile (1,1) string
                settings = []
                fingerprint (1,1) string = ""
            end
            tf = false;
            if ~isfile(resultsFile), return; end
            try
                R = load(char(resultsFile),'Version','StepState','Summary');
            catch
                return
            end
            if ~isfield(R,'StepState') || ~isstruct(R.StepState), return; end
            s = mabr.analysis.Batch.asSettings(settings);
            for st = s.Steps
                if ~isfield(R.StepState,st), return; end
                x = R.StepState.(st);
                if isempty(x) || ~isstruct(x) || ~isfield(x,'Settings'), return; end
                if ~isequaln(mabr.analysis.Settings.canonicalStruct(x.Settings),s.stepSettings(st)), return; end
            end
            if fingerprint ~= ""
                seg = R.StepState.segment;
                fp = "";
                if isfield(seg,'Fingerprint'), fp = string(seg.Fingerprint); end
                if fp ~= fingerprint, return; end
            end
            tf = true;
        end
    end

    methods (Static, Access = private)
        function [status,msg] = one(item,s,opts,rf,figFolder)
            % One session: skip, analyse and save, or fail -- never throws.
            key = item.Key;
            paths = item.Paths{1};
            excl = item.Exclude{1};
            if item.TestMode && ~opts.IncludeTestMode
                status = "skipped";  msg = "skipped: Test Mode";
                return
            end
            out = item.ResultsFile;
            if opts.SkipCurrent && isfile(out)
                fp = mabr.analysis.Session.folderFingerprint(paths,excl);
                if mabr.analysis.Batch.isCurrent(out,s,fp) && ...
                        mabr.analysis.Batch.sameOverrides(out,item)
                    status = "skipped";  msg = "skipped: up to date";
                    return
                end
            end
            try
                sargs = {'Verbose',false,'KeepTraces',false,'Exclude',excl, ...
                    'UnitOverride',item.UnitOverride{1},'Analyst',opts.Analyst,'Key',key, ...
                    'Parse',false};
                if item.Name ~= "", sargs = [sargs {'Name',item.Name}]; end
                S = mabr.analysis.Batch.newSession(paths,sargs,item,opts);
                % The edits of an earlier results file are carried over. One
                % that cannot be read (a crash mid-write, a disk error) must
                % not fail the session at every batch from now on: it is
                % analysed afresh, the message says so, and the unreadable
                % file is kept in .history by keepHistory below (under the
                % _unreadable_ name, so that three further batches do not
                % prune it).
                lost = "";
                % The file's stamp is taken BEFORE it is read: a save landing
                % between the two then shows as a change at the end (a
                % harmless re-adoption), whereas the other order could miss it.
                stamp = mabr.analysis.Batch.fileStamp(out);
                if isfile(out)
                    try
                        R = load(char(out));
                        S.adoptEdits(R);
                    catch MEr
                        lost = "; the previous results could not be read (" + string(MEr.message) + ...
                            "), so their edits were not carried over: analysed afresh, the old file kept in .history as _unreadable_";
                        S = mabr.analysis.Batch.newSession(paths,sargs,item,opts);   % no half-adopted edits
                    end
                end
                rep = S.analyze(s,Steps=opts.Steps,KeepCurated=opts.KeepCurated);
                status = rep.Status;
                nf = sum(S.Files.Include);
                msg = sprintf('%d files, %d conditions, %d series',nf,S.NumConditions,height(S.Thresholds)) + lost;
                S.ProgressFcn = [];
                % The file was read minutes ago. Whatever a second MATLAB
                % saved to it since (curation, above all) would be replaced
                % by this run's stale copy of it, so the file is looked at
                % again; "conflict" leaves it alone and writes this run's
                % results beside it instead.
                [late,note] = mabr.analysis.Batch.adoptLate(S,out,stamp);
                msg = msg + note;
                if late == "conflict"
                    cf = mabr.analysis.Batch.conflictFile(out);
                    S.saveResults(cf,IncludeSweeps=false);
                    status = "conflict";
                    msg = msg + "; this run's results were written to " + cf + ", the results file was left as it is";
                    return
                end
                % An unreadable file is the one kept under the _unreadable_
                % name -- unless it was replaced meanwhile by a readable one,
                % which is an ordinary previous results file.
                mabr.analysis.Batch.keepHistory(out,key,rf,lost ~= "" && late == "unchanged");
                S.saveResults(out,IncludeSweeps=false);
                if opts.SummaryFigure
                    try
                        mabr.analysis.Batch.summaryFigure(S,key,figFolder);
                    catch ME
                        msg = msg + "; summary figure failed: " + string(ME.message);
                    end
                end
            catch ME
                if strcmp(ME.identifier,'mabr:analysis:cancelled')
                    status = "cancelled";  msg = "cancelled by user";
                else
                    status = "failed";  msg = string(ME.message);
                    if msg == "", msg = string(ME.identifier); end
                end
            end
        end

        function S = newSession(paths,sargs,item,opts)
            % The Session of one work item, parsed, with its overrides.
            S = mabr.analysis.Session(paths,sargs{:});
            S.TimeOffset = item.TimeOffset;
            S.ConductionDelayOverride = item.ConductionDelay;
            S.ProgressFcn = opts.ProgressFcn;
            S.parse();
        end

        function tf = sameOverrides(out,item)
            % Whether a results file was made with this item's per-session
            % overrides (UnitOverride, TimeOffset, ConductionDelay). They are
            % the session's, not the settings', so neither the step settings
            % nor the file fingerprint sees a change to them -- a project
            % override edited since the last run would otherwise be skipped
            % as "up to date". A file that does not record them (older) is
            % taken as made without any.
            tf = false;
            try
                R = load(char(out),'Summary');
                S = R.Summary;
            catch
                return
            end
            none = struct('InputFullScale',NaN,'AmplifierGain',NaN);
            uo = none;
            if isfield(S,'UnitOverride') && isstruct(S.UnitOverride), uo = S.UnitOverride; end
            u = item.UnitOverride{1};
            for f = ["InputFullScale","AmplifierGain"]
                a = NaN;  b = NaN;
                if isfield(uo,f), a = double(uo.(f)); end
                if isfield(u,f), b = double(u.(f)); end
                if ~isequaln(a,b), return; end
            end
            pairs = {'TimeOffset','TimeOffset';'ConductionDelayOverride','ConductionDelay'};
            for k = 1:size(pairs,1)
                a = NaN;
                if isfield(S,pairs{k,1}), a = double(S.(pairs{k,1})); end
                if ~isfinite(a), a = NaN; end
                b = double(item.(pairs{k,2}));
                if ~isfinite(b), b = NaN; end
                if ~isequaln(a,b), return; end
            end
            tf = true;
        end

        function items = normalizeItems(items,p)
            % The optional columns of run()'s items, filled in -- the
            % overrides from the project p, when there is one, so a work list
            % built by hand runs each session exactly as the app would.
            if nargin < 2, p = []; end
            n = height(items);
            v = string(items.Properties.VariableNames);
            if ~all(ismember(["Key","Paths","ResultsFile"],v))
                error('mabr:analysis:Batch:badItems','items needs the columns Key, Paths and ResultsFile.');
            end
            items.Key = string(items.Key);
            items.ResultsFile = string(items.ResultsFile);
            if ~iscell(items.Paths), items.Paths = num2cell(string(items.Paths)); end
            items.Paths = cellfun(@(p) reshape(string(p),[],1),items.Paths,'UniformOutput',false);
            if ~ismember("Exclude",v), items.Exclude = repmat({strings(0,1)},n,1); end
            items.Exclude = cellfun(@(p) reshape(string(p),[],1),items.Exclude,'UniformOutput',false);
            none = struct('InputFullScale',NaN,'AmplifierGain',NaN);
            if ~ismember("UnitOverride",v), items.UnitOverride = repmat({none},n,1); end
            for i = 1:n
                if ~isstruct(items.UnitOverride{i}), items.UnitOverride{i} = none; end
            end
            if ~ismember("TestMode",v), items.TestMode = false(n,1); end
            items.TestMode = logical(items.TestMode);
            if ~ismember("Name",v), items.Name = strings(n,1); end
            items.Name = string(items.Name);
            if ~ismember("TimeOffset",v), items.TimeOffset = NaN(n,1); end
            if ~ismember("ConductionDelay",v), items.ConductionDelay = NaN(n,1); end
            items.TimeOffset = double(items.TimeOffset);
            items.ConductionDelay = double(items.ConductionDelay);
            if isempty(p) || ~ismethod(p,'sessionOverrides'), return; end
            for i = 1:n
                try
                    o = p.sessionOverrides(items.Key(i));
                catch
                    continue
                end
                if ~ismember("UnitOverride",v), items.UnitOverride{i} = o.UnitOverride; end
                if ~ismember("TimeOffset",v), items.TimeOffset(i) = o.TimeOffset; end
                if ~ismember("ConductionDelay",v), items.ConductionDelay(i) = o.ConductionDelay; end
            end
        end

        function items = itemsFromCatalog(c,p,keys)
            % run()'s items: the catalog's sessions, then the project's pools.
            S = c.Sessions;
            if ~isempty(keys), S = S(ismember(S.Key,keys),:); end
            n = height(S);
            Key = S.Key;
            Paths = num2cell(S.Path);
            ResultsFile = strings(n,1);
            for i = 1:n, ResultsFile(i) = c.resultsFile(S.Key(i)); end
            Exclude = repmat({strings(0,1)},n,1);
            UnitOverride = repmat({struct('InputFullScale',NaN,'AmplifierGain',NaN)},n,1);
            TestMode = S.TestMode == "all";
            Name = S.Name;
            TimeOffset = NaN(n,1);
            ConductionDelay = NaN(n,1);
            % Exclusions the results already hold (the app writes them there).
            for i = 1:n
                if isfile(ResultsFile(i))
                    try
                        R = load(char(ResultsFile(i)),'Summary');
                        Exclude{i} = reshape(string(R.Summary.Exclude),[],1);
                    catch
                    end
                end
            end
            if ~isempty(p)
                [Exclude,UnitOverride,TimeOffset,ConductionDelay] = mabr.analysis.Batch.projectOverrides( ...
                    p,Key,Exclude,UnitOverride,TimeOffset,ConductionDelay);
            end
            items = table(Key,Paths,ResultsFile,Exclude,UnitOverride,TestMode,Name,TimeOffset,ConductionDelay);
            if isempty(p), return; end
            % Pools: one item each, its members' folders together, with the
            % pool's own exclusions and overrides (Project.batchItems -- the
            % same rows the app's batch dialog runs).
            try
                P = p.Pools;
            catch
                return
            end
            for k = 1:height(P)
                pk = string(P.Key(k));
                members = split(string(P.Members(k)),"|");
                if ~all(ismember(members,c.Sessions.Key)), continue; end
                if ~isempty(keys) && ~any(ismember([members; pk],keys)), continue; end
                try
                    row = p.batchItems(pk,c);
                catch
                    continue
                end
                row.Name = string(P.Name(k));
                row = row(:,items.Properties.VariableNames);
                items = [items; row]; %#ok<AGROW>
            end
        end

        function [Ex,UO,TO,CD] = projectOverrides(p,keys,Ex,UO,TO,CD)
            % The project's per-session overrides, where it has a row.
            try
                T = p.Sessions;
            catch
                return
            end
            v = string(T.Properties.VariableNames);
            [tf,loc] = ismember(keys,string(T.Key));
            for i = find(tf).'
                r = loc(i);
                if ismember("TimeOffsetOverride",v), TO(i) = double(T.TimeOffsetOverride(r)); end
                if ismember("ConductionDelayOverride",v), CD(i) = double(T.ConductionDelayOverride(r)); end
                o = UO{i};
                if ismember("InputFullScaleOverride",v), o.InputFullScale = double(T.InputFullScaleOverride(r)); end
                if ismember("AmplifierGainOverride",v), o.AmplifierGain = double(T.AmplifierGainOverride(r)); end
                UO{i} = o;
                if ismember("Exclude",v)
                    try
                        e = T.Exclude(r);
                        if iscell(e), e = e{1}; end
                        e = reshape(string(e),[],1);
                        if ~isempty(e) && any(e ~= ""), Ex{i} = e(e ~= ""); end
                    catch
                    end
                end
            end
        end

        function keepHistory(out,key,rf,unreadable)
            % The previous results file into .history, newest HistoryKeep kept.
            %
            % A file that could not be read is copied as
            % <flat>_unreadable_<stamp>.mat (the naming Model.keepUnreadable
            % uses), which the pruning pattern below does not match: it is
            % the only copy of what a person had curated, and three further
            % batches must not delete it.
            if nargin < 4, unreadable = false; end
            if ~isfile(out), return; end
            if rf == "", rf = string(fileparts(char(out))); end
            hd = fullfile(char(rf),'.history');
            if ~isfolder(hd), mkdir(hd); end
            flat = mabr.analysis.Batch.flatKey(key);
            stamp = char(datetime('now'),'yyMMdd''T''HHmmss');
            tag = '';
            if unreadable, tag = '_unreadable'; end
            dst = fullfile(hd,[char(flat) tag '_' stamp '.mat']);
            k = 1;
            while isfile(dst)
                k = k + 1;
                dst = fullfile(hd,sprintf('%s%s_%s_%d.mat',flat,tag,stamp,k));
            end
            copyfile(char(out),dst,'f');
            if unreadable, return; end        % never pruned
            d = dir(fullfile(hd,[char(flat) '_*.mat']));
            d = d(~cellfun(@isempty,regexp({d.name},['^' regexptranslate('escape',char(flat)) ...
                '_\d{6}T\d{6}(_\d+)?\.mat$'],'once')));
            if numel(d) <= mabr.analysis.Batch.HistoryKeep, return; end
            [~,o] = sort([d.datenum],'descend');
            d = d(o);
            % Same-second copies: the name decides among equal times.
            for j = mabr.analysis.Batch.HistoryKeep+1:numel(d)
                delete(fullfile(hd,d(j).name));
            end
        end

        function s = fileStamp(f)
            % Size and modification time of a file, [] when it is not there.
            d = dir(char(f));
            d = d(~[d.isdir]);
            if isscalar(d), s = [d.bytes d.datenum]; else, s = []; end
        end

        function cf = conflictFile(out)
            % <name>.conflict.mat beside the results file <name>.mat. Catalog
            % and Project do not count it as a session's results.
            [d,n] = fileparts(char(out));
            cf = string(fullfile(d,[n '.conflict.mat']));
        end

        function [late,note] = adoptLate(S,out,stamp)
            % Reconcile a finished analysis with a results file that may have
            % changed since it was read.
            %
            %   S      the analysed session (edits adopted when it was read)
            %   out    the results file it is about to replace
            %   stamp  fileStamp(out) from before it was read
            %   late   "unchanged" (the file is as it was read), "merged" (it
            %          changed and its edits were adopted again) or
            %          "conflict" (it changed and cannot be reconciled: the
            %          caller must not replace it)
            %   note   (returned) a clause for the session's message ("" when
            %          unchanged)
            %
            % adoptEdits merges, newer winning, so an edit the other writer
            % REMOVED comes back from this run's copy; that is the price of
            % not losing the ones it added. Manual rejections and file
            % exclusions are different: they change which sweeps the numbers
            % are made of, and adoptEdits recomputes nothing, so a saved file
            % would claim results that do not follow from its own edits. Those
            % are a conflict, and the session is analysed again by the next
            % batch.
            late = "unchanged";  note = "";
            if isequaln(mabr.analysis.Batch.fileStamp(out),stamp), return; end
            pre = "; the results file was changed by another process while this ran";
            if ~isfile(out)
                late = "merged";
                note = pre + " (it was removed), so there was nothing to adopt";
                return
            end
            % Stamped again before the reload, and compared once more after
            % the edits are adopted: a third writer in between is a conflict
            % too. What remains is the few milliseconds of the move itself.
            stamp2 = mabr.analysis.Batch.fileStamp(out);
            try
                R = load(char(out));
            catch ME
                late = "conflict";
                note = pre + " and cannot be read now (" + string(ME.message) + ")";
                return
            end
            if mabr.analysis.Batch.countsChanged(S,R)
                late = "conflict";
                note = pre + ", with manual rejections or file exclusions that this run did not analyse";
                return
            end
            try
                S.adoptEdits(R);
            catch ME
                late = "conflict";
                note = pre + " and its edits could not be adopted (" + string(ME.message) + ")";
                return
            end
            if ~isequaln(mabr.analysis.Batch.fileStamp(out),stamp2)
                late = "conflict";
                note = pre + " again while its edits were adopted";
                return
            end
            late = "merged";
            note = pre + ": its edits were read again and adopted before saving";
        end

        function tf = countsChanged(S,R)
            % Whether the results struct R holds manual rejections or file
            % exclusions other than the session S analysed with (the same
            % reading adoptEdits makes of R: exclusions only when R lists some).
            tf = false;
            M = S.ManualRejections;
            if isfield(R,'ManualRejections') && istable(R.ManualRejections) && ...
                    all(ismember({'FileId','SweepIndex'},R.ManualRejections.Properties.VariableNames)) && ...
                    all(ismember({'FileId','SweepIndex'},M.Properties.VariableNames))
                k = @(T) sort(string(T.FileId) + "|" + string(T.SweepIndex));
                if ~isequal(k(R.ManualRejections),k(M)), tf = true; return; end
            end
            ex = [];
            if isfield(R,'Exclude')
                ex = R.Exclude;
            elseif isfield(R,'Summary') && isstruct(R.Summary) && isfield(R.Summary,'Exclude')
                ex = R.Summary.Exclude;
            end
            if ~isempty(ex)
                ex = reshape(string(ex),[],1);
                ex = unique(ex(~ismissing(ex) & ex ~= ""),'stable');
                if ~isempty(ex) && ~isequal(sort(ex),sort(S.Exclude)), tf = true; end
            end
        end

        function f = flatKey(key)
            % A session key as one file name ("/" and anything a Windows
            % name cannot hold become "__" / "_").
            f = regexprep(char(key),'[\\/]','__');
            f = regexprep(f,'[<>:"|?*]','_');
            f = string(f);
        end

        function appendLog(logFile,key,status,secs,msg,hash,rfile)
            % One line of the log CSV, written and closed at once.
            if logFile == "", return; end
            d = fileparts(char(logFile));
            if ~isempty(d) && ~isfolder(d), mkdir(d); end
            fresh = ~isfile(logFile);
            fid = fopen(char(logFile),'a','n','UTF-8');
            if fid < 0
                mabr.log.vprintf(1,'Batch: cannot write the log %s.',logFile);
                return
            end
            c = onCleanup(@() fclose(fid));
            q = @(x) ['"' strrep(char(string(x)),'"','""') '"'];
            if fresh
                fprintf(fid,'%s\n',strjoin(mabr.analysis.Batch.LogColumns,','));
            end
            fprintf(fid,'%s,%s,%.3f,%s,%s,%s\n',q(key),q(status),secs,q(msg),q(hash),q(rfile));
        end

        function noteProject(p,key,status,msg)
            % LastRun/LastError of the session's project row (in memory).
            if isempty(p) || ~ismember(status,["ok","ok (no thresholds)","failed"]), return; end
            err = "";
            if status == "failed", err = msg; end
            try
                p.recordRun(key,err);          % Project's own entry point
                return
            catch
            end
            try
                p.label(key,"LastRun",datetime('now'));
                p.label(key,"LastError",err);
            catch
                try
                    r = find(string(p.Sessions.Key) == key,1);
                    if ~isempty(r)
                        p.Sessions.LastRun(r) = datetime('now');
                        p.Sessions.LastError(r) = err;
                    end
                catch
                    % A project that does not take them: the log has them.
                end
            end
        end

        function summaryFigure(S,key,folder)
            % <folder>/<flat key>.png: the grid and the audiogram, side by side.
            %
            % Each is drawn in an invisible classic figure of its own and
            % rendered at 150 dpi, and the two images are put side by side --
            % one figure holding both would need a panel, which neither
            % exportgraphics nor print captures.
            if ~isfolder(folder), mkdir(folder); end
            imgs = {};
            f1 = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 900 700], ...
                'Tag','MABR_OfflineBatchFigure');
            c1 = onCleanup(@() delete(f1));
            try
                S.plotGrid(Parent=tiledlayout(f1,1,1));
                imgs{end+1} = print(f1,'-RGBImage','-r150');
            catch
            end
            if height(S.Thresholds) > 0
                f2 = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 600 700], ...
                    'Tag','MABR_OfflineBatchFigure');
                c2 = onCleanup(@() delete(f2));
                try
                    S.plotAudiogram(Parent=axes(f2));
                    imgs{end+1} = print(f2,'-RGBImage','-r150');
                catch
                end
                clear c2
            end
            clear c1
            if isempty(imgs)
                error('mabr:analysis:Batch:noFigure','Neither the grid nor the audiogram could be drawn.');
            end
            h = max(cellfun(@(x) size(x,1),imgs));
            imgs = cellfun(@(x) cat(1,x,255*ones(h - size(x,1),size(x,2),3,'like',x)), ...
                imgs,'UniformOutput',false);
            imwrite([imgs{:}],fullfile(char(folder),[char(mabr.analysis.Batch.flatKey(key)) '.png']));
        end

        function tf = cancelled(fcn)
            % CancelFcn's answer (a CancelFcn that errors does not cancel).
            tf = false;
            if isempty(fcn), return; end
            try
                tf = logical(fcn());
            catch
            end
        end

        function progress(fcn,msg,k,n)
            % The batch's own progress line (a sink that throws cancels).
            if isempty(fcn), return; end
            fcn(msg,k,n);
        end

        function s = asSettings(x)
            if isempty(x)
                s = mabr.analysis.Settings();
            elseif isa(x,'mabr.analysis.Settings')
                s = x;
            elseif isstruct(x)
                s = mabr.analysis.Settings.fromStruct(x);
            else
                error('mabr:analysis:Batch:badSettings', ...
                    'Settings must be a mabr.analysis.Settings or its struct, not a %s.',class(x));
            end
        end
    end
end
