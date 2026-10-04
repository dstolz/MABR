classdef AnalysisApp < handle
% mabr.ui.AnalysisApp  The MABR offline analysis window.
%
%   One window for the whole offline workflow on saved .abr files: open a
%   data folder, label timepoints, analyse, review thresholds and peaks,
%   compare across a study, export. MABRAnalysis opens it (or File ▸
%   Offline Analysis… in MABR):
%
%       app = mabr.ui.AnalysisApp("C:\data\OFC_NoiseExposure");
%       app = mabr.ui.AnalysisApp("",Instance="reuse");   % raise the open one
%
%   THE WINDOW. A browser of sessions down the left (mabr.ui.analysis.
%   Browser); on the right a header (what is open, whether it is up to date,
%   saved, reviewed, and an Analyse button that names its cost), a
%   notification bar for the one thing most worth knowing (Test Mode, a
%   read-only results folder, a save conflict, out-of-date settings, ...),
%   and five tabs -- Session, Grid, Series, Trials, Study -- each a
%   mabr.ui.analysis.View built the first time it is shown (the class is
%   AnalysisApp.viewClass(tab): SessionView, GridView, SeriesView,
%   TrialView, StudyView). With no folder
%   open a Start panel covers the workspace. A status line runs along the
%   bottom.
%
%   STATE lives in mabr.ui.analysis.Model (the Model property), never in
%   this window: the window and every view draw what the Model holds and
%   send every change back through a Model method, which is what makes
%   every change undoable (Ctrl+Z), autosaved, and visible in every view at
%   once.
%
%   KEYS. One keymap (mabr.ui.analysis.Commands) drives the menus, the F1
%   sheet and the dispatcher. A letter only runs a command when the plots
%   have the keyboard (Model.KeyTarget "plot") -- after a click in a text
%   field, a table or a dropdown it is text again -- and while the note
%   editor is open every key but Esc and Ctrl+Enter is ignored. cb(fcn,area)
%   wraps every component callback so the dispatcher knows where the user
%   last was ("workspace" or "browser").
%
%   PREFS are written only from callbacks a user triggers: the recent
%   folders (OfflineRecentRoots), the results-folder choices
%   (OfflineResultsFolders), the analyst's name, "reopen last session", and
%   -- on close, when RememberState -- the window position, the last state
%   and the layout. prefKeys() lists every pref the app and its views may
%   write.
%
%   Options (name-value): Visible "on"|"off", Instance "new"|"reuse",
%   ResultsFolder, CacheFolder (tests: tempname), Restore (reopen the last
%   state), RememberState (write state prefs on close), ProgressMode
%   "dialog"|"none", ConfirmFcn/AlertFcn/PromptFcn/PickFolderFcn/PickFileFcn
%   (stubs for tests; [] = uiconfirm, uialert, PromptDialog, uigetdir,
%   uigetfile), Settings (a mabr.analysis.Settings that overrides the
%   project's), AutoRefresh (false: no timers; call flush()).
%
%   See also MABRAnalysis, mabr.ui.analysis.Model, mabr.ui.analysis.View,
%   mabr.ui.analysis.Commands, mabr.analysis.Session
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Figure = []
        Model = []
        Views = struct('Session',[],'Grid',[],'Series',[],'Trials',[],'Study',[])
        Browser = []
        NoteEditor = []
        ProgressMode (1,1) string = "dialog"
        Visible (1,1) string = "on"
        RememberState (1,1) logical = true
        AutoRefresh (1,1) logical = true
        ActiveTab (1,1) string = "Session"
        Dialogs = {}                 % dialogs and windows this app opened
        KeysWindow = []              % the F1 window
        ToolGlyphs (1,:) string = strings(1,0)   % the toolbar's glyphs, in order
    end

    properties (Constant)
        InstanceTag = 'MABR_OFFLINE_ANALYSIS'
        TabNames = ["Session","Grid","Series","Trials","Study"]
        BrowserWidth = 300
        MaxRecent = 10
        CloseSettle = 0.3        % s the window is given to finish its layout before it goes
    end

    properties (Access = private)
        H = struct()                 % handles of the shell's own controls
        Tabs = struct()
        TabGroup = []
        Written = struct()
        Listeners = event.listener.empty
        InUserCallback (1,1) logical = false
        BrowserVisible (1,1) logical = true
        CloseTimer = []
        Closing (1,1) logical = false
        ClosePending (1,1) logical = false   % closing once the running job unwinds
        BarActions = {[],[]}         % the two bar buttons' functions
        BarState (1,1) string = ""
        PointerNow (1,1) string = "arrow"   % the pointer onPointerMove last set
    end

    % =====================================================================
    methods
        function app = AnalysisApp(root,opts)
            arguments
                root (1,1) string = ""
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.Instance (1,1) string {mustBeMember(opts.Instance,["new","reuse"])} = "new"
                opts.ResultsFolder (1,1) string = ""
                opts.CacheFolder (1,1) string = ""
                opts.Restore (1,1) logical = true
                opts.RememberState (1,1) logical = true
                opts.ProgressMode (1,1) string {mustBeMember(opts.ProgressMode,["dialog","none"])} = "dialog"
                opts.ConfirmFcn = []
                opts.AlertFcn = []
                opts.PromptFcn = []
                opts.PickFolderFcn = []
                opts.PickFileFcn = []
                opts.Settings = []
                opts.AutoRefresh (1,1) logical = true
            end
            if opts.Instance == "reuse"
                existing = mabr.ui.AnalysisApp.findOpen();
                if ~isempty(existing)
                    app = existing;
                    app.raise();
                    if root ~= ""
                        try
                            app.openRoot(root);
                        catch me
                            app.setStatus("Could not open " + root + ": " + string(me.message),2);
                        end
                    end
                    if nargout == 0, clear app; end
                    return
                end
            end
            app.Visible       = opts.Visible;
            app.RememberState = opts.RememberState;
            app.ProgressMode  = opts.ProgressMode;
            app.AutoRefresh   = opts.AutoRefresh;

            m = mabr.ui.analysis.Model('ResultsFolderOverride',opts.ResultsFolder, ...
                'CacheFolder',opts.CacheFolder,'AutoRefresh',opts.AutoRefresh, ...
                'Interactive',opts.Visible == "on");
            if ~isempty(opts.Settings), m.SettingsOverride = opts.Settings; end
            app.Model = m;
            app.wireFunctions(opts);
            m.CloseFcn = @() app.deferClose();

            app.buildWindow();
            app.listen();
            app.applyLayoutPref();
            app.refreshAll();
            app.refreshStartPanel();
            % Shown before a folder is opened, so the study-folder question
            % and the scan's progress window have a window to sit on.
            app.Figure.Visible = char(opts.Visible);

            if root ~= ""
                try
                    m.openRoot(root);
                catch me
                    app.setStatus("Could not open " + root + ": " + string(me.message),2);
                end
            elseif opts.Restore
                app.restoreState();
            end
            app.refreshStartPanel();
            if nargout == 0, clear app; end
        end

        function delete(app)
            app.Closing = true;
            try
                if ~isempty(app.CloseTimer) && isvalid(app.CloseTimer)
                    stop(app.CloseTimer);
                    delete(app.CloseTimer);
                end
            catch
            end
            try
                delete(app.Listeners);
            catch
            end
            % The window goes FIRST, whole: deleting its tabs one at a time
            % (each view's delete) makes the client lay the rest out again
            % between deletions, and the resizes it then sends back reach
            % grid layouts already deleted -- "Invalid or deleted object"
            % from MATLAB's GridLayout controller, printed in the command
            % window as a red stack after closing a window mid-job.
            try
                if ~isempty(app.Figure) && isvalid(app.Figure), delete(app.Figure); end
            catch
            end
            for n = app.TabNames
                v = app.Views.(n);
                try
                    if ~isempty(v) && isvalid(v), delete(v); end
                catch
                end
            end
            for k = 1:numel(app.Dialogs)
                d = app.Dialogs{k};
                try
                    if ~isempty(d) && isvalid(d), delete(d); end
                catch
                end
            end
            try
                if ~isempty(app.KeysWindow) && isvalid(app.KeysWindow), delete(app.KeysWindow); end
            catch
            end
            try
                if ~isempty(app.Browser) && isvalid(app.Browser), delete(app.Browser); end
            catch
            end
            try
                if ~isempty(app.NoteEditor) && isvalid(app.NoteEditor), delete(app.NoteEditor); end
            catch
            end
            try
                if ~isempty(app.Model) && isvalid(app.Model), delete(app.Model); end
            catch
            end
            try
                if ~isempty(app.Figure) && isvalid(app.Figure), delete(app.Figure); end
            catch
            end
        end

        % ---- public API --------------------------------------------------
        function raise(app)
            % Bring the window forward (and out of the taskbar).
            f = app.Figure;
            if isempty(f) || ~isvalid(f), return; end
            try
                if isprop(f,'WindowState') && strcmp(f.WindowState,'minimized')
                    f.WindowState = 'normal';
                end
            catch
            end
            if strcmp(f.Visible,'on'), figure(f); end
        end

        function close(app)
            % Close the window -- after the current step when busy. Saves
            % pending edits; remembers position and state when RememberState.
            app.onCloseRequest();
        end

        function openRoot(app,path)
            % Model.openRoot; a root opened from a user's callback is also
            % remembered among the recent folders.
            arguments
                app
                path (1,1) string
            end
            app.Model.openRoot(path);
            if app.InUserCallback && ~isempty(app.Model.Catalog)
                app.rememberRoot(string(app.Model.Catalog.Root));
            end
        end

        function openSession(app,key)
            % Model.openSession.
            arguments
                app
                key (1,1) string
            end
            app.Model.openSession(key);
        end

        function activateTab(app,name)
            % Show a tab ("Session", "Grid", "Series", "Trials", "Study"),
            % building its view the first time.
            arguments
                app
                name (1,1) string
            end
            k = find(lower(app.TabNames) == lower(name),1);
            if isempty(k)
                error('mabr:ui:AnalysisApp:badTab','There is no "%s" tab.',name);
            end
            name = app.TabNames(k);
            if name == "Study" && app.Model.BlindReview
                app.setStatus("The Study tab is off during blind review.",1);
                return
            end
            app.TabGroup.SelectedTab = app.Tabs.(name);
            app.switchTo(name);
        end

        function runCommand(app,id)
            % Run a Commands id as if its key had been pressed.
            arguments
                app
                id (1,1) string
            end
            v = app.activeView();
            if ~isempty(v)
                try
                    if v.onCommand(id), return; end
                catch me
                    app.reportError(me);
                    return
                end
            end
            try
                app.execute(id);
            catch me
                app.reportError(me);
            end
        end

        function handled = dispatchKey(app,evt)
            % Route one key press (a KeyData event or a struct with Key,
            % Modifier, Character) to its command. See the class help.
            handled = false;
            m = app.Model;
            if isempty(m) || ~isvalid(m), return; end
            [key,mods,ch] = mabr.ui.AnalysisApp.keyParts(evt);
            if key == "" || any(key == ["control","shift","alt","command","windows"])
                return
            end
            % 2. the note editor has the keyboard
            if m.KeysSuspended
                if key == "escape"
                    app.NoteEditor.cancel();
                    handled = true;
                elseif key == "return" && mods == "control"
                    app.NoteEditor.commit();
                    handled = true;
                end
                return
            end
            % 3. busy: only Escape (cancel)
            if m.Busy
                if key == "escape"
                    m.cancel();
                    handled = true;
                end
                return
            end
            % 4. which part of the window
            if m.FocusArea == "browser"
                scopes = ["browser","global"];
            else
                scopes = [lower(app.ActiveTab),"global"];
            end
            id = mabr.ui.analysis.Commands.lookup(key,mods,ch,scopes);
            if id == "", return; end
            unmodified = ~contains(mods,"control") && ~contains(mods,"alt") && ...
                isempty(regexp(char(key),'^f\d{1,2}$','once')) && key ~= "escape";
            if unmodified
                if m.FocusArea == "browser"
                    % only the browser's own keys: an unmodified key of any
                    % other scope is the tree's (or nobody's) while the
                    % browser has the keyboard
                    T = mabr.ui.analysis.Commands.spec();
                    if ~any(T.Id == id & T.Scope == "browser"), return; end
                end
                % 5. a letter is text unless the plots have the keyboard
                if m.KeyTarget ~= "plot", return; end
                cur = [];
                try
                    cur = app.Figure.CurrentObject;
                catch
                end
                if mabr.ui.analysis.Compat.isTextComponent(cur), return; end
            end
            % 6. run it; the plots keep the keyboard
            app.runCommand(id);
            if isvalid(app) && isvalid(m)
                m.KeyTarget = "plot";
            end
            handled = true;
        end

        function f = cb(app,fcn,area)
            % Wrap a component callback: records where the user is (area
            % "workspace" or "browser"), reports errors on the status line,
            % and gives the keyboard back to the plots afterwards (unless
            % the component is one the user types into).
            if nargin < 3 || isempty(area), area = "workspace"; end
            area = string(area);
            f = @(src,evt) app.runCallback(fcn,area,src,evt);
        end

        function setStatus(app,text,level)
            % The status line: level 0 information, 1 warning, 2 error.
            if nargin < 3, level = 0; end
            h = app.ctrl('StatusText');
            if isempty(h), return; end
            text = string(text);
            if ismissing(text), text = ""; end
            % (blind review: no session or subject named on the status line)
            m = app.Model;
            if ~isempty(m) && isvalid(m) && m.BlindReview
                text = m.blindText(text);
            end
            app.put('status_text',h,'Text',char(text));
            app.put('status_color',h,'FontColor',mabr.ui.analysis.Style.levelColor(level));
            app.put('status_tip',h,'Tooltip',char(text));
            if level >= 2
                mabr.log.vprintf(2,'Analysis app: %s',char(text));
            end
        end

        function d = openDialog(app,name,varargin)
            % Open one of the app's dialogs: "settings", "export", "batch",
            % "batchReport", "review", "levels", "figureExport". A dialog
            % this MABR does not have yet says so on the status line.
            arguments
                app
                name (1,1) string
            end
            arguments (Repeating)
                varargin
            end
            d = [];
            m = app.Model;
            vis = {'Visible',app.Visible};
            switch name
                case "settings"
                    ttl = "Project settings";
                    if ~isempty(m.Catalog), ttl = ttl + " — " + string(m.Catalog.Root); end
                    cls = "SettingsDialog";
                    args = [{m.Settings,@(s) app.applySettingsFromDialog(s)},vis,{'Title',ttl},varargin];
                case "export"
                    % The "Selected sessions" scope needs the selection, as
                    % batch and review are given it: the browser's, else the
                    % open session (then the dialog opens on that session,
                    % "current", unless the caller chose a scope).
                    if ~mabr.ui.AnalysisApp.hasOption(varargin,'Keys')
                        [keys,fromBrowser] = app.selectedKeys();
                        extra = {'Keys',keys};
                        if ~fromBrowser && ~isempty(keys) && ...
                                ~mabr.ui.AnalysisApp.hasOption(varargin,'Scope')
                            extra = [extra {'Scope',"current"}];
                        end
                        varargin = [extra varargin];
                    end
                    cls = "ExportDialog";
                    args = [{m},vis,varargin];
                case "batch"
                    keys = app.selectedKeys();
                    if ~isempty(varargin) && (isstring(varargin{1}) || iscellstr(varargin{1}))
                        keys = string(varargin{1});
                        varargin(1) = [];
                    end
                    cls = "BatchDialog";
                    args = [{m,keys},vis,varargin];
                case "batchReport"
                    if isempty(m.LastBatch)
                        app.setStatus("No batch has run in this window yet.",0);
                        return
                    end
                    cls = "BatchReport";
                    % (a Retry from the reopened report runs with what the
                    % batch ran with -- its profile or .mabraset -- not
                    % with whatever the project's settings are now)
                    if ~mabr.ui.AnalysisApp.hasOption(varargin,'Settings') && ...
                            isfield(m.LastBatch,'Settings')
                        varargin = [{'Settings',m.LastBatch.Settings} varargin];
                    end
                    args = [{m,m.LastBatch.Summary,m.LastBatch.LogFile},vis,varargin];
                case "review"
                    keys = app.selectedKeys();
                    if ~isempty(varargin) && (isstring(varargin{1}) || iscellstr(varargin{1}))
                        keys = string(varargin{1});
                        varargin(1) = [];
                    end
                    cls = "ReviewDialog";
                    args = [{m,keys},vis,varargin];
                case "levels"
                    col = "Timepoint";
                    if ~isempty(varargin), col = string(varargin{1}); varargin(1) = []; end
                    cls = "LevelsDialog";
                    args = [{m,col},vis,varargin];
                case "figureExport"
                    if ~isempty(varargin)
                        target = varargin{1};
                    else
                        target = app.exportTarget();
                    end
                    if isempty(target)
                        app.setStatus("There is no plot on this tab to export.",1);
                        return
                    end
                    d = mabr.ui.analysis.FigureExport(target,app,'Visible',app.Visible);
                    app.keepDialog(d);
                    return
                otherwise
                    error('mabr:ui:AnalysisApp:badDialog','There is no "%s" dialog.',name);
            end
            full = "mabr.ui.analysis." + cls;
            if exist(char(full),'class') ~= 8
                app.setStatus(cls + " is not available yet in this MABR.",1);
                return
            end
            try
                d = feval(full,args{:});
            catch me
                % An older dialog may not take the Visible option.
                try
                    keep = ~cellfun(@(a) (ischar(a) || isstring(a)) && strcmpi(string(a),"Visible"),args);
                    k = find(~keep,1);
                    if ~isempty(k), args(k:k+1) = []; end
                    d = feval(full,args{:});
                catch
                    app.setStatus(cls + " could not open: " + string(me.message),2);
                    mabr.log.vprintf(2,me);
                    return
                end
            end
            app.keepDialog(d);
        end

        function showShortcuts(app)
            % The F1 window: every key of the global scope and the active tab.
            if ~isempty(app.KeysWindow) && isvalid(app.KeysWindow)
                app.fillKeysWindow();
                if strcmp(app.KeysWindow.Visible,'on'), figure(app.KeysWindow); end
                return
            end
            pos = [300 120 560 640];
            f = uifigure('Name','MABR Offline Analysis — keyboard shortcuts', ...
                'Tag','MABR_OFFLINE_KEYS','Position',pos,'Visible','off');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisKeys',pos,[420 360]);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn = @(~,~) app.closeKeysWindow();
            f.WindowKeyPressFcn = @(~,e) app.keysWindowKey(e);
            g = uigridlayout(f,[2 1],'RowHeight',{'1x',22},'Padding',[8 8 8 6]);
            t = uitable(g,'Tag','AnalysisKeysTable','RowName',{}, ...
                'ColumnName',{'Keys','Command','Where'},'ColumnWidth',{140,'auto',80});
            mabr.ui.analysis.Compat.setSortable(t,false);
            lab = uilabel(g,'Text','Keys run commands while a plot has the keyboard; click a plot to give it back.', ...
                'FontColor',mabr.ui.analysis.Style.Muted,'Tag','AnalysisKeysHint');
            lab.Layout.Row = 2;
            app.KeysWindow = f;
            app.fillKeysWindow();
            f.Visible = char(app.Visible);
        end

        function flush(app)
            % Run pending work now: the active view's debounced redraws and
            % the Model's pending save (tests call this instead of waiting).
            v = app.activeView();
            if ~isempty(v)
                try
                    v.flush();
                catch me
                    mabr.log.vprintf(2,'Analysis app: flush of %s failed (%s).',app.ActiveTab,me.message);
                end
            end
            try
                app.Browser.flush();
            catch
            end
            app.Model.flush();
        end
    end

    % =====================================================================
    methods (Static)
        function keys = prefKeys()
            % Every MABR pref the analysis app, its views and dialogs may write.
            keys = ["OfflineAnalysisSettings","OfflineRecentRoots","OfflineResultsFolders", ...
                "OfflineAnalysisLayout","OfflineAnalysisLastState","OfflineAnalysisRestore", ...
                "OfflineAnalysisAnalyst","OfflineAnalysisExport","OfflineAnalysisFigureExport", ...
                "OfflineAnalysisSession","OfflineAnalysisGrid","OfflineAnalysisSeries", ...
                "OfflineAnalysisTrials","OfflineAnalysisStudy"];
            keys = [keys,"WindowPos_" + mabr.ui.AnalysisApp.windowNames()];
        end

        function cls = viewClass(tab)
            % The class that draws a tab: "mabr.ui.analysis.<X>View". The
            % one place a tab's name becomes a class -- not simply name +
            % "View": the Trials tab is drawn by TrialView.
            arguments
                tab (1,1) string
            end
            switch tab
                case "Session", c = "SessionView";
                case "Grid",    c = "GridView";
                case "Series",  c = "SeriesView";
                case "Trials",  c = "TrialView";
                case "Study",   c = "StudyView";
                otherwise
                    error('mabr:ui:AnalysisApp:badTab','There is no "%s" tab.',tab);
            end
            cls = "mabr.ui.analysis." + c;
        end

        function names = windowNames()
            % The mabr.ui.WindowPos names of the app's windows and dialogs.
            names = ["OfflineAnalysis","OfflineAnalysisSettings","OfflineAnalysisExport", ...
                "OfflineAnalysisBatch","OfflineAnalysisBatchReport","OfflineAnalysisReview", ...
                "OfflineAnalysisLevels","OfflineAnalysisPrompt","OfflineAnalysisFigureExport", ...
                "OfflineAnalysisKeys"];
        end

        function app = findOpen()
            % The open analysis app, or [].
            app = [];
            f = findall(groot,'Type','figure','Tag',mabr.ui.AnalysisApp.InstanceTag);
            for k = 1:numel(f)
                a = getappdata(f(k),'AnalysisApp');
                if ~isempty(a) && isvalid(a)
                    app = a;
                    return
                end
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- construction ------------------------------------------------
        function wireFunctions(app,opts)
            m = app.Model;
            if isempty(opts.ConfirmFcn)
                m.ConfirmFcn = @(msg,title,options,default) app.defaultConfirm(msg,title,options,default);
            else
                m.ConfirmFcn = opts.ConfirmFcn;
            end
            if isempty(opts.AlertFcn)
                m.AlertFcn = @(msg,title,icon) app.defaultAlert(msg,title,icon);
            else
                m.AlertFcn = opts.AlertFcn;
            end
            if isempty(opts.PromptFcn)
                m.PromptFcn = @(prompt,title,default) mabr.ui.analysis.PromptDialog.run(title,prompt,default);
            else
                m.PromptFcn = opts.PromptFcn;
            end
            if isempty(opts.PickFolderFcn)
                m.PickFolderFcn = @(start,title) app.defaultPickFolder(start,title);
            else
                m.PickFolderFcn = opts.PickFolderFcn;
            end
            if isempty(opts.PickFileFcn)
                m.PickFileFcn = @(filter,title,mode,default) app.defaultPickFile(filter,title,mode,default);
            else
                m.PickFileFcn = opts.PickFileFcn;
            end
            m.ProgressFcn = @(op,title) app.openProgress(op,title);
        end

        function buildWindow(app)
            mon = get(groot,'MonitorPositions');
            sz = min([1500 900],0.9*mon(1,3:4));
            pos = [80 60 round(sz)];
            f = uifigure('Name','MABR Offline Analysis','Tag',app.InstanceTag, ...
                'Position',pos,'Visible','off');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysis',pos,[1100 700]);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn     = @(~,~) app.onCloseRequest();
            f.WindowKeyPressFcn   = @(~,e) app.onKeyPress(e);
            f.WindowButtonDownFcn = @(s,e) app.onButtonDown(s,e);
            % (the pointer over what a view lets the mouse drag -- a
            % threshold divider; a drag puts its own motion callback in
            % place for its duration and this one back afterwards)
            f.WindowButtonMotionFcn = @(~,~) app.onPointerMove();
            % a window deleted behind the app's back (close all force, a
            % script) takes the app -- its Model, timers and listeners --
            % with it
            f.DeleteFcn = @(~,~) app.onFigureDeleted();
            setappdata(f,'AnalysisApp',app);
            app.Figure = f;

            app.buildMenus();
            app.buildToolbar();

            root = uigridlayout(f,[2 1],'RowHeight',{'1x',24},'Padding',[6 4 6 2], ...
                'RowSpacing',2,'BackgroundColor',mabr.ui.analysis.Style.Panel);
            content = uigridlayout(root,[1 2],'ColumnWidth',{app.BrowserWidth,'1x'}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',6,'BackgroundColor',mabr.ui.analysis.Style.Panel);
            content.Layout.Row = 1;
            app.H.Root = root;
            app.H.Content = content;

            bh = uipanel(content,'BorderType','none','Tag','AnalysisBrowserHost', ...
                'BackgroundColor',mabr.ui.analysis.Style.Panel);
            bh.Layout.Row = 1; bh.Layout.Column = 1;
            app.H.BrowserHost = bh;

            ws = uigridlayout(content,[3 1],'RowHeight',{30,0,'1x'},'Padding',[0 0 0 0], ...
                'RowSpacing',4,'BackgroundColor',mabr.ui.analysis.Style.Panel);
            ws.Layout.Row = 1; ws.Layout.Column = 2;
            app.H.Workspace = ws;

            app.buildHeader(ws);
            app.buildBar(ws);

            ov = uigridlayout(ws,[3 3],'RowHeight',{'1x',230,'1x'},'ColumnWidth',{'1x',560,'1x'}, ...
                'Padding',[0 0 0 0],'RowSpacing',0,'ColumnSpacing',0, ...
                'BackgroundColor',mabr.ui.analysis.Style.Panel);
            ov.Layout.Row = 3;
            app.H.Overlay = ov;
            tg = uitabgroup(ov,'Tag','AnalysisTabs');
            tg.Layout.Row = [1 3]; tg.Layout.Column = [1 3];
            for n = app.TabNames
                app.Tabs.(n) = uitab(tg,'Title',char(n),'Tag',char("AnalysisTab" + n), ...
                    'BackgroundColor',mabr.ui.analysis.Style.Panel);
            end
            tg.SelectionChangedFcn = app.cb(@(~,e) app.onTabChanged(e));
            app.TabGroup = tg;
            app.NoteEditor = mabr.ui.analysis.NoteEditor(ov,app.Model,app,'Row',2,'Column',2);

            app.buildStartPanel(content);
            app.buildStatusBar(root);
            app.buildBrowser();
        end

        function buildHeader(app,ws)
            S = mabr.ui.analysis.Style;
            g = uigridlayout(ws,[1 6],'ColumnWidth',{'1x','fit','fit','fit','fit',200}, ...
                'Padding',[2 0 0 0],'ColumnSpacing',10,'BackgroundColor',S.Panel);
            g.Layout.Row = 1;
            app.H.HeaderTitle = uilabel(g,'Text','MABR Offline Analysis','FontWeight','bold', ...
                'FontSize',14,'FontColor',S.Ink,'Tag','AnalysisHeaderTitle', ...
                'Tooltip','The open session: subject, start time, stimuli and conditions.');
            app.H.HeaderStatus = uilabel(g,'Text','','HorizontalAlignment','center', ...
                'BackgroundColor',S.ChipGrey,'FontColor',S.Ink,'Tag','AnalysisHeaderStatus', ...
                'Tooltip','Whether the open session''s results match its files and the project''s settings.');
            app.H.HeaderProfile = uilabel(g,'Text','','FontColor',S.Muted,'Tag','AnalysisHeaderProfile', ...
                'Tooltip','The settings profile in force; "(modified)" when the settings match no built-in profile.');
            app.H.HeaderReviewed = uilabel(g,'Text','','FontColor',S.Muted,'Tag','AnalysisHeaderReviewed', ...
                'Tooltip','Series of this session with a curation decision, of all its series.');
            app.H.HeaderSaved = uilabel(g,'Text','','FontColor',S.Muted,'Tag','AnalysisHeaderSaved', ...
                'Tooltip','Edits are saved by themselves a moment after they are made (Ctrl+S saves now).');
            b = uibutton(g,'Text','Analyse','Tag','AnalysisHeaderAnalyze','Enable','off', ...
                'Tooltip','Analyse the open session from the first step that is out of date (Ctrl+Enter).');
            mabr.ui.analysis.Style.setButtonIcon(b,'play','left');
            b.ButtonPushedFcn = app.cb(@(~,~) app.Model.analyze());
            app.H.HeaderAnalyze = b;
        end

        function buildBar(app,ws)
            p = uipanel(ws,'Tag','AnalysisHeaderBar','BorderType','none','Visible','off', ...
                'BackgroundColor',mabr.ui.analysis.Style.BarBlue);
            p.Layout.Row = 2;
            g = uigridlayout(p,[1 3],'ColumnWidth',{'1x','fit','fit'},'Padding',[8 3 6 3], ...
                'ColumnSpacing',6,'BackgroundColor',mabr.ui.analysis.Style.BarBlue);
            t = uilabel(g,'Text','','Tag','AnalysisHeaderBarText','WordWrap','on', ...
                'FontColor',mabr.ui.analysis.Style.Ink);
            t.Layout.Column = 1;
            b1 = uibutton(g,'Text','','Tag','AnalysisHeaderBarAction1','Visible','off');
            b1.Layout.Column = 2;
            b1.ButtonPushedFcn = app.cb(@(~,~) app.runBarAction(1));
            b2 = uibutton(g,'Text','','Tag','AnalysisHeaderBarAction2','Visible','off');
            b2.Layout.Column = 3;
            b2.ButtonPushedFcn = app.cb(@(~,~) app.runBarAction(2));
            app.H.Bar = p;
            app.H.BarGrid = g;
            app.H.BarText = t;
            app.H.BarAction1 = b1;
            app.H.BarAction2 = b2;
        end

        function buildStartPanel(app,content)
            S = mabr.ui.analysis.Style;
            p = uipanel(content,'Tag','AnalysisStartPanel','BorderType','none', ...
                'BackgroundColor',S.Panel);
            p.Layout.Row = 1; p.Layout.Column = 2;
            g = uigridlayout(p,[8 3],'RowHeight',{'1x',36,46,22,170,24,40,'1x'}, ...
                'ColumnWidth',{'1x',460,'1x'},'Padding',[20 20 20 20],'RowSpacing',8, ...
                'BackgroundColor',S.Panel);
            t = uilabel(g,'Text','MABR Offline Analysis','FontSize',22,'FontWeight','bold', ...
                'FontColor',S.Ink,'HorizontalAlignment','center');
            t.Layout.Row = 2; t.Layout.Column = 2;
            b = uibutton(g,'Text','Open data folder… (Ctrl+O)','FontSize',15, ...
                'Tag','AnalysisStartOpen', ...
                'Tooltip','Choose a study folder (or one animal''s folder) holding .abr files (Ctrl+O).');
            b.Layout.Row = 3; b.Layout.Column = 2;
            b.ButtonPushedFcn = app.cb(@(~,~) app.browseRoot());
            mabr.ui.analysis.Style.setButtonIcon(b,'load','left');
            l = uilabel(g,'Text','Recent folders','FontColor',S.Muted);
            l.Layout.Row = 4; l.Layout.Column = 2;
            lb = uilistbox(g,'Items',{},'Multiselect','on','Value',{},'Tag','AnalysisStartRecent', ...
                'Tooltip','Folders opened recently; click one to open it again.');
            lb.Layout.Row = 5; lb.Layout.Column = 2;
            lb.ValueChangedFcn = app.cb(@(src,~) app.onRecentPicked(src));
            h = uilabel(g,'Text',['1 Open a data folder · 2 Label timepoints · 3 Analyse · ' ...
                '4 Review · 5 Compare in Study · 6 Export'],'HorizontalAlignment','center', ...
                'FontColor',S.Muted,'Tag','AnalysisStartHint');
            h.Layout.Row = 6; h.Layout.Column = [1 3];
            msg = uilabel(g,'Text','','HorizontalAlignment','center','WordWrap','on', ...
                'FontColor',S.Warn,'Tag','AnalysisStartMessage');
            msg.Layout.Row = 7; msg.Layout.Column = [1 3];
            app.H.Start = p;
            app.H.StartRecent = lb;
            app.H.StartMessage = msg;
            app.fillRecent();
        end

        function buildStatusBar(app,root)
            g = uigridlayout(root,[1 2],'ColumnWidth',{'1x',120},'Padding',[2 0 2 0], ...
                'ColumnSpacing',6,'BackgroundColor',mabr.ui.analysis.Style.Panel);
            g.Layout.Row = 2;
            s = uilabel(g,'Text','','Tag','AnalysisStatusText','FontColor',mabr.ui.analysis.Style.Ink);
            s.Layout.Column = 1;
            w = uibutton(g,'Text','','Tag','AnalysisStatusWarnings','Visible','off', ...
                'FontColor',mabr.ui.analysis.Style.Warn, ...
                'Tooltip','Warnings the open session''s analysis raised; click to see them on the Session tab.');
            w.Layout.Column = 2;
            w.ButtonPushedFcn = app.cb(@(~,~) app.activateTab("Session"));
            app.H.StatusText = s;
            app.H.StatusWarnings = w;
        end

        function buildBrowser(app)
            cls = "mabr.ui.analysis.Browser";
            if exist(char(cls),'class') == 8
                try
                    app.Browser = feval(cls,app.H.BrowserHost,app.Model,app); %#ok<FVAL> (built only when the class exists)
                    return
                catch me
                    mabr.log.vprintf(1,'Analysis app: the browser could not be built: %s',me.message);
                    mabr.log.vprintf(2,me);
                end
            end
            g = uigridlayout(app.H.BrowserHost,[1 1],'Padding',[6 6 6 6], ...
                'BackgroundColor',mabr.ui.analysis.Style.Panel);
            uilabel(g,'Text','Browser not available yet','HorizontalAlignment','center', ...
                'FontColor',mabr.ui.analysis.Style.Muted,'Tag','AnalysisBrowserUnavailable');
        end

        function buildMenus(app)
            f = app.Figure;
            K = @(id) mabr.ui.analysis.Commands.keyText(id);
            T = @(txt,id) mabr.ui.AnalysisApp.menuText(txt,K(id));

            m = uimenu(f,'Text','&File','Tag','AnalysisTopMenuFile');
            app.item(m,T("Open Folder…","file.open"),'AnalysisMenuOpen',@() app.browseRoot());
            app.H.MenuRecent = uimenu(m,'Text','Recent Folders','Tag','AnalysisMenuRecent');
            app.item(m,T("Rescan","file.rescan"),'AnalysisMenuRescan',@() app.Model.rescan());
            app.item(m,T("Save Now","file.save"),'AnalysisMenuSave',@() app.Model.saveNow(),true);
            app.item(m,T("Export…","file.export"),'AnalysisMenuExport',@() app.openDialog("export"),true);
            app.item(m,T("Export Again","file.exportAgain"),'AnalysisMenuExportAgain',@() app.Model.exportAgain());
            app.item(m,"Export Figure…",'AnalysisMenuExportFigure',@() app.openDialog("figureExport"));
            app.item(m,"Export Analysis Script…",'AnalysisMenuExportScript',@() app.exportScript());
            app.item(m,"Close",'AnalysisMenuClose',@() app.close(),true);

            m = uimenu(f,'Text','&Edit','Tag','AnalysisTopMenuEdit');
            app.H.MenuUndo = app.item(m,T("Undo","edit.undo"),'AnalysisMenuUndo',@() app.Model.undo());
            app.H.MenuRedo = app.item(m,T("Redo","edit.redo"),'AnalysisMenuRedo',@() app.Model.redo());
            app.item(m,T("Note…","edit.note"),'AnalysisMenuNote',@() app.openNote(),true);
            app.item(m,"Revert Series",'AnalysisMenuRevertSeries',@() app.Model.revertSeries());
            app.item(m,"Clear All Manual Edits in Session…",'AnalysisMenuClearEdits',@() app.Model.clearAllEdits());

            m = uimenu(f,'Text','&Session','Tag','AnalysisTopMenuSession');
            app.item(m,"Open Selected",'AnalysisMenuOpenSession',@() app.openSelected());
            app.item(m,T("Previous Session","session.prev"),'AnalysisMenuPrevSession',@() app.Model.openAdjacent(-1));
            app.item(m,T("Next Session","session.next"),'AnalysisMenuNextSession',@() app.Model.openAdjacent(1));
            app.item(m,T("Analyse","session.analyse"),'AnalysisMenuAnalyse',@() app.Model.analyze(),true);
            app.item(m,"Pool Sweeps of Selected Sessions…",'AnalysisMenuPool',@() app.poolSelected(),true);
            app.item(m,"Unpool",'AnalysisMenuUnpool',@() app.Model.unpool());
            app.item(m,"Review Queue…",'AnalysisMenuReview',@() app.openDialog("review"),true);
            app.item(m,"End Review",'AnalysisMenuEndReview',@() app.Model.endQueue());
            app.item(m,T("Next Needing Review","review.next"),'AnalysisMenuNextReview',@() app.Model.nextNeedingReview(1));
            app.item(m,T("Previous Needing Review","review.prev"),'AnalysisMenuPrevReview',@() app.Model.nextNeedingReview(-1));

            m = uimenu(f,'Text','&Batch','Tag','AnalysisTopMenuBatch');
            app.item(m,"Analyse Sessions…",'AnalysisMenuBatch',@() app.openDialog("batch"));
            app.item(m,"Last Batch Report",'AnalysisMenuBatchReport',@() app.openDialog("batchReport"));

            m = uimenu(f,'Text','&View','Tag','AnalysisTopMenuView');
            for k = 1:numel(app.TabNames)
                n = app.TabNames(k);
                app.item(m,T(n,"view.tab" + k),char("AnalysisMenuTab" + n),@() app.activateTab(n));
            end
            app.H.MenuBrowser = app.item(m,T("Show Browser","view.browser"),'AnalysisMenuBrowser', ...
                @() app.toggleBrowser(),true);
            app.H.MenuBrowser.Checked = 'on';
            app.item(m,T("Find…","view.find"),'AnalysisMenuFind',@() app.focusFind());

            m = uimenu(f,'Text','Se&ttings','Tag','AnalysisTopMenuSettings');
            app.item(m,"Analysis Settings…",'AnalysisMenuSettings',@() app.openDialog("settings"));
            pm = uimenu(m,'Text','Profile','Tag','AnalysisMenuProfile');
            for n = mabr.analysis.Settings.profileNames()
                nm = n;
                uimenu(pm,'Text',char(nm),'MenuSelectedFcn',app.cb(@(~,~) app.Model.applyProfile(nm)));
            end
            uimenu(pm,'Text','Load from File…','Separator','on','Tag','AnalysisMenuProfileLoad', ...
                'MenuSelectedFcn',app.cb(@(~,~) app.loadSettingsFile()));
            uimenu(pm,'Text','Save Current as File…','Tag','AnalysisMenuProfileSave', ...
                'MenuSelectedFcn',app.cb(@(~,~) app.saveSettingsFile()));
            app.item(m,"Results Folder…",'AnalysisMenuResultsFolder',@() app.chooseResultsFolder(),true);
            app.item(m,"Analyst Name…",'AnalysisMenuAnalyst',@() app.setAnalyst());
            app.H.MenuRestore = app.item(m,"Reopen Last Session at Start",'AnalysisMenuRestore', ...
                @() app.toggleRestore(),true);
            app.H.MenuRestore.Checked = matlab.lang.OnOffSwitchState(mabr.ui.AnalysisApp.restoreEnabled());

            m = uimenu(f,'Text','&Help','Tag','AnalysisTopMenuHelp');
            app.item(m,T("Keyboard Shortcuts","help.keys"),'AnalysisMenuKeys',@() app.showShortcuts());
            app.item(m,"Analysis App Guide",'AnalysisMenuGuide',@() app.openGuide(""));
            app.item(m,"Threshold Methods",'AnalysisMenuMethods',@() app.openGuide("threshold-methods"));
            app.item(m,"Open Log Folder",'AnalysisMenuLog',@() app.openLogFolder(),true);
            app.item(m,"Verification Tests…",'AnalysisMenuTests',@() app.openTests());
        end

        function h = item(app,parent,text,tag,fcn,sep)
            if nargin < 6, sep = false; end
            h = uimenu(parent,'Text',char(text),'Tag',char(tag), ...
                'Separator',matlab.lang.OnOffSwitchState(sep), ...
                'MenuSelectedFcn',app.cb(@(~,~) fcn()));
        end

        function buildToolbar(app)
            tb = uitoolbar(app.Figure,'Tag','AnalysisToolbar');
            app.H.Toolbar = tb;
            app.toolButton('load','Open data folder… (Ctrl+O)',@() app.browseRoot(),false);
            app.toolButton('repeat','Rescan the folder (F5)',@() app.Model.rescan(),false);
            app.toolButton('save','Save now (Ctrl+S)',@() app.Model.saveNow(),false);
            app.toolButton('play','Analyse the open session (Ctrl+Enter)',@() app.Model.analyze(),true);
            app.toolButton('batch','Analyse several sessions in a batch…',@() app.openDialog("batch"),false);
            app.toolButton('export','Export tables… (Ctrl+E)',@() app.openDialog("export"),true);
            app.toolButton('script','Export a MATLAB script that reproduces this analysis…', ...
                @() app.exportScript(),false);
            app.toolButton('figure','Export the plot on this tab as a figure…', ...
                @() app.openDialog("figureExport"),false);
            % (their tooltips name what they would undo / redo: refreshMenus)
            app.H.ToolUndo = app.toolButton('undo','Undo (Ctrl+Z)',@() app.Model.undo(),true);
            app.H.ToolRedo = app.toolButton('redo','Redo (Ctrl+Y)',@() app.Model.redo(),false);
            app.toolButton('traces','Grid tab (Ctrl+2)',@() app.activateTab("Grid"),true);
            app.toolButton('peaks','Series tab (Ctrl+3)',@() app.activateTab("Series"),false);
            app.toolButton('raster','Trials tab (Ctrl+4)',@() app.activateTab("Trials"),false);
            app.toolButton('study','Study tab (Ctrl+5)',@() app.activateTab("Study"),false);
            app.toolButton('notes','Note… (Ctrl+N)',@() app.openNote(),true);
            app.toolButton('gear','Analysis settings…',@() app.openDialog("settings"),false);
            app.toolButton('keys','Keyboard shortcuts (F1)',@() app.showShortcuts(),true);
            app.toolButton('help','Analysis app guide',@() app.openGuide(""),false);
        end

        function h = toolButton(app,glyph,tip,fcn,sep)
            % One toolbar button; the glyph is the literal first argument
            % at every call (tests/verify_icons.m reads them). A glyph
            % mabr.ui.Icon does not draw (yet) leaves a plain square.
            tb = app.H.Toolbar;
            h = uipushtool(tb,'Tooltip',char(tip),'Separator',matlab.lang.OnOffSwitchState(sep), ...
                'Tag',char("AnalysisTool_" + glyph),'ClickedCallback',app.cb(@(~,~) fcn()));
            try
                h.CData = mabr.ui.Icon.toolbar(glyph,tb);
            catch
                h.CData = mabr.ui.AnalysisApp.blankGlyph();
            end
            app.ToolGlyphs(end+1) = string(glyph);
        end

        function listen(app)
            m = app.Model;
            names = ["RootChanged","ProjectChanged","SessionChanged","ResultsChanged", ...
                "SelectionChanged","SettingsChanged","StatusChanged","BusyChanged"];
            L = event.listener.empty;
            for n = names
                L(end+1) = addlistener(m,char(n),@(~,e) app.onModelEvent(n,e)); %#ok<AGROW>
            end
            app.Listeners = L;
        end

        % ---- model events -------------------------------------------------
        function onModelEvent(app,name,e)
            if ~isvalid(app) || app.Closing || app.ClosePending, return; end
            try
                switch name
                    case "RootChanged"
                        app.refreshStartPanel();
                        app.refreshAll();
                    case "SessionChanged"
                        app.refreshAll();
                        if ~isempty(app.Model.Session)
                            app.ensureActiveView();
                        end
                    case "BusyChanged"
                        busy = e.What == "busy";
                        try
                            if busy, app.Figure.Pointer = 'watch'; else, app.Figure.Pointer = 'arrow'; end
                            if busy, app.PointerNow = "watch"; else, app.PointerNow = "arrow"; end
                        catch
                        end
                        if busy
                            app.setStatus(e.Text + "…",0);
                        end
                        app.refreshHeader();
                    case "StatusChanged"
                        if e.What ~= "message"
                            app.refreshHeader();
                            app.refreshBar();
                        end
                        % (a message is mostly a sentence for the status
                        % line -- they arrive by the dozen while a session
                        % is analysed -- but undo/redo announce themselves
                        % with one AFTER moving the stacks, so the Edit
                        % menu's labels are re-read on every one)
                        app.refreshMenus();
                        if strlength(e.Text) > 0
                            app.setStatus(e.Text,e.Level);
                        end
                    case "SelectionChanged"
                        % nothing in the shell depends on what is selected
                        % (every arrow key raises one)
                    otherwise
                        app.refreshHeader();
                        app.refreshBar();
                        app.refreshMenus();
                        if name == "ResultsChanged", app.refreshWarnings(); end
                end
            catch me
                mabr.log.vprintf(2,'Analysis app: %s handler failed (%s).',name,me.message);
            end
        end

        function refreshAll(app)
            app.refreshHeader();
            app.refreshBar();
            app.refreshMenus();
            app.refreshWarnings();
        end

        function refreshHeader(app)
            m = app.Model;
            S = mabr.ui.analysis.Style;
            if isempty(m) || ~isvalid(m), return; end
            t = m.sessionTitle();
            if t == "", t = "MABR Offline Analysis"; end
            app.put('hdr_title',app.H.HeaderTitle,'Text',char(t));
            % the title is cut off when the chips beside it are wide: the
            % whole of it is the tooltip
            app.put('hdr_title_tip',app.H.HeaderTitle,'Tooltip',char(t));
            st = m.Status;
            [bg,fg] = S.chipColors(st.State);
            app.put('hdr_status',app.H.HeaderStatus,'Text',char(" " + st.Text + " "));
            app.put('hdr_status_bg',app.H.HeaderStatus,'BackgroundColor',bg);
            app.put('hdr_status_fg',app.H.HeaderStatus,'FontColor',fg);
            app.put('hdr_status_vis',app.H.HeaderStatus,'Visible',matlab.lang.OnOffSwitchState(~isempty(m.Session)));
            prof = "";
            if ~isempty(m.Settings) && ~isempty(m.Catalog)
                n = "";
                try
                    n = m.Settings.matchingProfile();
                catch
                end
                if n == "", n = "(modified)"; end
                prof = "Profile: " + n;
            end
            app.put('hdr_profile',app.H.HeaderProfile,'Text',char(prof));
            app.put('hdr_reviewed',app.H.HeaderReviewed,'Text',char(app.reviewedText()));
            [txt,col] = app.savedText();
            app.put('hdr_saved',app.H.HeaderSaved,'Text',char(txt));
            app.put('hdr_saved_fg',app.H.HeaderSaved,'FontColor',col);
            [lab,on,tip] = app.analyseLabel();
            app.put('hdr_analyse',app.H.HeaderAnalyze,'Text',char(lab));
            app.put('hdr_analyse_on',app.H.HeaderAnalyze,'Enable',matlab.lang.OnOffSwitchState(on));
            app.put('hdr_analyse_tip',app.H.HeaderAnalyze,'Tooltip',char(tip));
        end

        function s = reviewedText(app)
            s = "";
            S = app.Model.Session;
            if isempty(S), return; end
            try
                T = S.Thresholds;
                if isempty(T) || height(T) == 0, return; end
                d = string(T.Decision);
                d(ismissing(d)) = "";
                s = sprintf('Reviewed %d/%d',sum(d ~= ""),numel(d));
            catch
            end
        end

        function [txt,col] = savedText(app)
            m = app.Model;
            S = mabr.ui.analysis.Style;
            col = S.Muted;
            txt = "";
            if isempty(m.Session) && isempty(m.Project), return; end
            switch m.SaveState
                case "saved"
                    if ~isnat(m.LastSaved)
                        txt = "Saved " + string(m.LastSaved,'HH:mm:ss');
                    elseif ~isempty(m.Session) && m.hasResults(m.SessionKey)
                        % opened from its results file, nothing edited yet
                        txt = "Saved";
                    end
                    % (nothing has been written yet: say nothing rather
                    % than "Saved" over a session that has no results file)
                case "pending", txt = "Save pending";
                case "saving",  txt = "Saving…";
                case "failed",  txt = "Save failed — retrying"; col = S.Error;
                case "conflict", txt = "Save conflict"; col = S.Error;
                case "readonly", txt = "Read-only"; col = S.Warn;
            end
        end

        function [lab,on,tip] = analyseLabel(app)
            m = app.Model;
            st = m.Status;
            on = ~m.Busy && ~isempty(m.Session);
            tip = 'Analyse the open session from the first step that is out of date (Ctrl+Enter).';
            switch st.State
                case "none"
                    lab = "Analyse"; on = false;
                case {"not-analysed","failed"}
                    lab = "Analyse";
                    t = mabr.ui.analysis.Style.formatSeconds(st.Seconds);
                    if t ~= "", lab = lab + " (" + t + ")"; end
                case "stale"
                    if ismember(st.FromStep,["thresholds","peaks"])
                        lab = "Re-fit thresholds";
                        tip = 'Only threshold and peak settings changed: re-fitting is instant (Ctrl+Enter).';
                    else
                        lab = "Re-run from " + st.FromStep;
                        t = mabr.ui.analysis.Style.formatSeconds(st.Seconds);
                        if t ~= "", lab = lab + " (" + t + ")"; end
                    end
                case "current"
                    lab = "Up to date"; on = false;
                    tip = 'The results match the files and the project''s settings.';
                otherwise
                    lab = "Analyse";
            end
        end

        function refreshBar(app)
            % The one notification that matters most (11 sec. 1.4).
            [state,text,color,acts] = app.barContent();
            if app.Model.BlindReview
                % (blind review: the bar names no session, subject or
                % folder; Model.blindText masks them)
                text = app.Model.blindText(text);
            end
            app.BarState = state;
            show = state ~= "";
            if show
                app.put('bar_text',app.H.BarText,'Text',char(text));
                app.put('bar_bg',app.H.Bar,'BackgroundColor',color);
                app.put('bar_grid_bg',app.H.BarGrid,'BackgroundColor',color);
                btns = {app.H.BarAction1,app.H.BarAction2};
                for k = 1:2
                    b = btns{k};
                    if k <= numel(acts)
                        app.put("bar_b" + k,b,'Text',char(acts(k).Text));
                        app.put("bar_b" + k + "_tip",b,'Tooltip',char(acts(k).Tooltip));
                        app.put("bar_b" + k + "_vis",b,'Visible','on');
                        app.BarActions{k} = acts(k).Fcn;
                    else
                        app.put("bar_b" + k + "_vis",b,'Visible','off');
                        app.BarActions{k} = [];
                    end
                end
            end
            app.put('bar_vis',app.H.Bar,'Visible',matlab.lang.OnOffSwitchState(show));
            h = 0;
            if show, h = 34; end
            if ~isfield(app.Written,'bar_height') || app.Written.bar_height ~= h
                rh = app.H.Workspace.RowHeight;
                rh{2} = h;
                app.H.Workspace.RowHeight = rh;
                app.Written.bar_height = h;
            end
        end

        function [state,text,color,acts] = barContent(app)
            m = app.Model;
            S = mabr.ui.analysis.Style;
            state = ""; text = ""; color = S.BarBlue;
            acts = struct('Text',{},'Tooltip',{},'Fcn',{});
            sess = m.Session;
            % 1. Test Mode
            if ~isempty(sess)
                tm = false;
                try
                    tm = logical(sess.TestMode);
                catch
                end
                if tm
                    state = "testmode"; color = S.BarRed;
                    text = "TEST MODE — these samples are the stimulus, not a subject.";
                    return
                end
            end
            % 2. read-only
            if m.ReadOnly
                state = "readonly"; color = S.BarYellow;
                text = "Read-only: results cannot be written to " + m.resultsFolder() + ".";
                try
                    % (the reason, when it is not the folder: project.mat)
                    if m.ReadOnlyWhy ~= "", text = "Read-only: " + m.ReadOnlyWhy + "."; end
                catch
                end
                acts(1) = struct('Text',"Choose results folder…", ...
                    'Tooltip',"Choose a folder the results can be written to.", ...
                    'Fcn',@() app.chooseResultsFolder());
                return
            end
            % 3. save conflict
            if m.SaveState == "conflict"
                state = "conflict"; color = S.BarRed;
                when = "";
                if ~isnat(m.ConflictTime), when = " (" + string(m.ConflictTime,'HH:mm') + ")"; end
                text = "This session's results were changed elsewhere" + when + ".";
                acts(1) = struct('Text',"Keep mine",'Tooltip',"Overwrite the file with this window's results.", ...
                    'Fcn',@() m.keepMine());
                acts(2) = struct('Text',"Load theirs",'Tooltip',"Reload the file; this window's unsaved edits are dropped.", ...
                    'Fcn',@() m.loadTheirs());
                return
            end
            % a session that would not open (after read-only and the save
            % conflict: those put edits at risk, this only says a click failed)
            if ~isempty(m.LastOpenError)
                e = m.LastOpenError;
                state = "openfailed"; color = S.BarRed;
                text = "Could not open " + e.Name + ": " + e.Message;
                key = e.Key; paths = e.Paths;
                acts(1) = struct('Text',"Retry",'Tooltip',"Try opening the session again.", ...
                    'Fcn',@() m.openSession(key));
                acts(2) = struct('Text',"Show files",'Tooltip',"Open the session's folder in Explorer.", ...
                    'Fcn',@() mabr.ui.AnalysisApp.showFolder(paths));
                return
            end
            % 4. out of date
            if ~isempty(sess) && m.Status.State == "stale"
                state = "stale"; color = S.BarAmber;
                D = m.Status.Differences;
                lines = strings(0,1);
                for i = 1:min(height(D),4)
                    if string(D.Step(i)) == "data"
                        lines(end+1) = "the session's files changed"; %#ok<AGROW>
                    elseif string(D.Field(i)) == "UnitOverride"
                        lines(end+1) = "unit overrides changed"; %#ok<AGROW>
                    elseif string(D.Field(i)) == "LatencyOffset"
                        lines(end+1) = "the latency offset changed (" + D.Old(i) + " → " + ...
                            D.New(i) + "; peaks were picked at the old one)"; %#ok<AGROW>
                    else
                        lines(end+1) = D.Field(i) + " " + D.Old(i) + " → " + D.New(i); %#ok<AGROW>
                    end
                end
                if height(D) > 4, lines(end+1) = "and " + (height(D) - 4) + " more"; end
                text = "Out of date: " + strjoin(lines,"; ");
                steps = mabr.analysis.Settings.Steps;
                k = find(steps == m.Status.FromStep,1);
                if isempty(k), k = 1; end
                n = numel(steps) - k + 1;
                t = mabr.ui.analysis.Style.formatSeconds(m.Status.Seconds);
                lab = "Re-run " + n + " steps";
                if n == 1, lab = "Re-run 1 step"; end
                if t ~= "", lab = lab + " (" + t + ")"; end
                acts(1) = struct('Text',lab,'Tooltip',"Re-run the analysis from " + m.Status.FromStep + ".", ...
                    'Fcn',@() m.analyze());
                settingsDiffer = any(string(D.Step) ~= "data" & ...
                    ~ismember(string(D.Field),["UnitOverride","LatencyOffset"]));
                if ~isempty(sess.Settings) && settingsDiffer
                    % (only settings can be adopted: changed files or
                    % overrides need the re-run)
                    acts(2) = struct('Text',"Use this session's settings", ...
                        'Tooltip',"Make the settings this session was analysed with the project's.", ...
                        'Fcn',@() m.adoptSessionSettings());
                end
                return
            end
            % 5. acquisition modes
            if ~isempty(sess)
                modes = strings(0,1);
                try
                    modes = string(sess.AcqModes);
                catch
                end
                pooled = false;
                try
                    pooled = m.Settings.PoolAcqModes;
                catch
                end
                if all(ismember(["conventional","interleaved"],modes)) && ~pooled
                    state = "acqmodes"; color = S.BarBlue;
                    text = ['This session holds a conventional and an interleaved run of the same ' ...
                        'conditions; they are analysed as separate series (Settings ▸ Pool acquisition modes).'];
                    return
                end
            end
            % 6. nested results stores (not during blind review: an offer
            % that can wait, and its folder names a subject)
            p = "";  n = 0;
            if ~m.BlindReview
                [p,n] = app.pendingNestedStore();
            end
            if p ~= ""
                state = "nested"; color = S.BarBlue;
                text = sprintf('Results found in %s (%d sessions).',p,n);
                acts(1) = struct('Text',"Import into this project", ...
                    'Tooltip',"Copy those results (and their labels) into this project's store; the original stays.", ...
                    'Fcn',@() m.importNestedStore(p));
                acts(2) = struct('Text',"Ignore",'Tooltip',"Stop offering to import them.", ...
                    'Fcn',@() m.ignoreNestedStore(p));
                return
            end
        end

        function [p,n] = pendingNestedStore(app)
            p = ""; n = 0;
            m = app.Model;
            if isempty(m.Catalog), return; end
            try
                N = m.Catalog.NestedStores;
                if isempty(N) || height(N) == 0, return; end
                done = strings(0,1);
                try
                    done = [reshape(string(m.Project.ImportedStores),[],1); ...
                        reshape(string(m.Project.IgnoredStores),[],1)];
                catch
                end
                for i = 1:height(N)
                    q = string(N.Path(i));
                    if ~any(strcmpi(q,done))
                        p = q;
                        try
                            n = double(N.NumResults(i));
                        catch
                        end
                        return
                    end
                end
            catch
            end
        end

        function runBarAction(app,k)
            fcn = app.BarActions{k};
            if isempty(fcn), return; end
            fcn();
        end

        function refreshMenus(app)
            m = app.Model;
            if isempty(m) || ~isvalid(m), return; end
            K = mabr.ui.analysis.Commands.keyText("edit.undo");
            if m.CanUndo
                u = "Undo """ + m.UndoLabel + """ (" + K + ")";
            else
                u = "Undo (" + K + ")";
            end
            app.put('menu_undo',app.H.MenuUndo,'Text',char(u));
            app.put('menu_undo_on',app.H.MenuUndo,'Enable',matlab.lang.OnOffSwitchState(m.CanUndo));
            K = mabr.ui.analysis.Commands.keyText("edit.redo");
            K = extractBefore(K + " or"," or");
            if m.CanRedo
                r = "Redo """ + m.RedoLabel + """ (" + K + ")";
            else
                r = "Redo (" + K + ")";
            end
            app.put('menu_redo',app.H.MenuRedo,'Text',char(r));
            app.put('menu_redo_on',app.H.MenuRedo,'Enable',matlab.lang.OnOffSwitchState(m.CanRedo));
            % the toolbar's buttons say the same as the menu
            if isfield(app.H,'ToolUndo') && isvalid(app.H.ToolUndo)
                app.put('tool_undo',app.H.ToolUndo,'Tooltip',char(u));
            end
            if isfield(app.H,'ToolRedo') && isvalid(app.H.ToolRedo)
                app.put('tool_redo',app.H.ToolRedo,'Tooltip',char(r));
            end
        end

        function refreshWarnings(app)
            h = app.ctrl('StatusWarnings');
            if isempty(h), return; end
            n = 0;
            S = app.Model.Session;
            if ~isempty(S)
                try
                    M = S.Messages;
                    if ~isempty(M) && height(M) > 0
                        n = sum(string(M.Level) == "warning");
                    end
                catch
                end
            end
            if n > 0
                app.put('warn_text',h,'Text',sprintf('%d warning(s)',n));
            end
            app.put('warn_vis',h,'Visible',matlab.lang.OnOffSwitchState(n > 0));
        end

        function refreshStartPanel(app)
            m = app.Model;
            noRoot = isempty(m.Catalog);
            empty = false;
            if ~noRoot
                try
                    empty = height(m.Catalog.Sessions) == 0;
                catch
                end
            end
            show = noRoot || empty;
            app.put('start_vis',app.H.Start,'Visible',matlab.lang.OnOffSwitchState(show));
            app.put('ws_vis',app.H.Workspace,'Visible',matlab.lang.OnOffSwitchState(~show));
            if empty
                app.put('start_msg',app.H.StartMessage,'Text',char(sprintf( ...
                    'No .abr files under %s (MABR_Analysis and hidden folders are skipped).', ...
                    string(m.Catalog.Root))));
            elseif ~noRoot
                app.put('start_msg',app.H.StartMessage,'Text','');
            end
            if ~show
                app.ensureActiveView();
            end
        end

        % ---- tabs and views ----------------------------------------------
        function switchTo(app,name)
            old = app.ActiveTab;
            if old ~= name
                ov = app.Views.(old);
                try
                    if ~isempty(ov) && isvalid(ov), ov.deactivate(); end
                catch
                end
            end
            app.ActiveTab = name;
            v = app.ensureView(name);
            if ~isempty(v)
                try
                    v.activate();
                catch me
                    mabr.log.vprintf(1,'Analysis app: %s view failed to activate: %s',name,me.message);
                end
            end
            m = app.Model;
            m.KeyTarget = "plot";
            m.FocusArea = "workspace";
            if ~isempty(app.KeysWindow) && isvalid(app.KeysWindow)
                app.fillKeysWindow();
            end
        end

        function ensureActiveView(app)
            v = app.ensureView(app.ActiveTab);
            if ~isempty(v) && ~v.IsActive
                try
                    v.activate();
                catch
                end
            end
        end

        function v = ensureView(app,name)
            v = app.Views.(name);
            if ~isempty(v) && isvalid(v), return; end
            v = [];
            tab = app.Tabs.(name);
            cls = mabr.ui.AnalysisApp.viewClass(name);
            ph = findall(tab,'Tag',char("Analysis" + name + "Unavailable"));
            if exist(char(cls),'class') ~= 8
                if isempty(ph), app.stubView(tab,name,"View not available yet"); end
                return
            end
            try
                if ~isempty(ph), delete(ph); end
                v = feval(cls,tab,app.Model,app);
                app.Views.(name) = v;
            catch me
                v = [];
                app.stubView(tab,name,"View not available yet: " + string(me.message));
                mabr.log.vprintf(1,'Analysis app: the %s view could not be built: %s',name,me.message);
                mabr.log.vprintf(2,me);
            end
        end

        function stubView(~,tab,name,text)
            % What a tab shows when its view cannot be built.
            g = uigridlayout(tab,[1 1],'Padding',[20 20 20 20], ...
                'BackgroundColor',mabr.ui.analysis.Style.Panel,'Tag',char("Analysis" + name + "Unavailable"));
            uilabel(g,'Text',char(text),'HorizontalAlignment','center','FontSize',14, ...
                'FontColor',mabr.ui.analysis.Style.Muted,'WordWrap','on', ...
                'Tag',char("Analysis" + name + "UnavailableText"));
        end

        function v = activeView(app)
            v = app.Views.(app.ActiveTab);
            if ~isempty(v) && ~isvalid(v), v = []; end
        end

        function onTabChanged(app,e)
            name = "";
            try
                name = erase(string(e.NewValue.Tag),"AnalysisTab");
            catch
            end
            if ~any(app.TabNames == name), return; end
            if name == "Study" && app.Model.BlindReview
                try
                    app.TabGroup.SelectedTab = e.OldValue;
                catch
                end
                app.setStatus("The Study tab is off during blind review.",1);
                return
            end
            app.switchTo(name);
        end

        function target = exportTarget(app)
            % The plot an Export Figure… of this tab copies: its first axes.
            target = [];
            tab = app.Tabs.(app.ActiveTab);
            ax = findall(tab,'Type','axes','Visible','on');
            if ~isempty(ax)
                target = ax(end);
            end
        end

        % ---- callbacks, keys, mouse -------------------------------------
        function runCallback(app,fcn,area,src,evt)
            if ~isvalid(app), return; end
            m = app.Model;
            prev = app.InUserCallback;
            app.InUserCallback = true;
            try
                m.KeyTarget = "ui";
                m.FocusArea = area;
            catch
            end
            try
                fcn(src,evt);
            catch me
                if isvalid(app), app.reportError(me); end
            end
            if ~isvalid(app), return; end
            app.InUserCallback = prev;
            try
                if isvalid(m) && ~mabr.ui.analysis.Compat.isTextComponent(src)
                    m.KeyTarget = "plot";
                    if strcmp(app.Figure.Visible,'on')
                        mabr.ui.analysis.Compat.tryFocus(app.Figure);
                    end
                end
            catch
            end
        end

        function reportError(app,me)
            if strcmp(me.identifier,'mabr:ui:analysis:busy')
                app.setStatus("Busy — try again when the current step ends",1);
            else
                app.setStatus(string(me.message),2);
            end
            mabr.log.vprintf(2,me);
        end

        function onKeyPress(app,evt)
            if ~isvalid(app), return; end
            prev = app.InUserCallback;
            app.InUserCallback = true;
            try
                app.dispatchKey(evt);
            catch me
                if isvalid(app), app.reportError(me); end
            end
            if isvalid(app), app.InUserCallback = prev; end
        end

        function onPointerMove(app)
            % The mouse moved over the window: the pointer the active view
            % wants there (View.hoverPointer -- the resize arrows over a
            % threshold divider), set only when it changes, and never while
            % the app is busy (the watch says so).
            try
                if ~isvalid(app) || app.Closing || app.ClosePending, return; end
                m = app.Model;
                if isempty(m) || ~isvalid(m) || m.Busy, return; end
                want = "";
                v = app.activeView();
                if ~isempty(v), want = string(v.hoverPointer()); end
                if want == "", want = "arrow"; end
                if want ~= app.PointerNow && mabr.ui.analysis.Compat.setPointer(app.Figure,want)
                    app.PointerNow = want;
                end
            catch
                % (a pointer is a hint: nothing here may interrupt the mouse)
            end
        end

        function onButtonDown(app,~,evt)
            m = app.Model;
            if isempty(m) || ~isvalid(m), return; end
            h = mabr.ui.analysis.Compat.hitObject(app.Figure,evt);
            ax = [];
            try
                if ~isempty(h), ax = ancestor(h,'axes'); end
            catch
            end
            if isempty(ax)
                m.KeyTarget = "ui";
            else
                m.KeyTarget = "plot";
                m.FocusArea = "workspace";
            end
        end

        function execute(app,id)
            % The app's half of runCommand: what an id does.
            m = app.Model;
            switch id
                case "file.open",        app.browseRoot();
                case "file.rescan",      m.rescan();
                case "file.save",        m.saveNow();
                case "file.export",      app.openDialog("export");
                case "file.exportAgain", m.exportAgain();
                case "file.exportScript", app.exportScript();
                case "edit.undo",        m.undo();
                case "edit.redo",        m.redo();
                case "edit.note",        app.openNote();
                case "session.analyse",  m.analyze();
                case "session.prev",     m.openAdjacent(-1);
                case "session.next",     m.openAdjacent(1);
                case "review.next",      m.nextNeedingReview(1);
                case "review.prev",      m.nextNeedingReview(-1);
                case "view.browser",     app.toggleBrowser();
                case "view.find",        app.focusFind();
                case "help.keys",        app.showShortcuts();
                case "browser.open",     app.openSelected();
                case "nav.escape"
                    if m.Selection.Wave ~= ""
                        m.clearWave();
                    end
                    m.KeyTarget = "plot";
                case "nav.levelUp",      m.stepLevel(1);
                case "nav.levelDown",    m.stepLevel(-1);
                case {"nav.seriesPrev","nav.seriesPrevPg"}, m.stepSeries(-1);
                case {"nav.seriesNext","nav.seriesNextPg"}, m.stepSeries(1);
                case "series.left"
                    if m.Selection.Wave ~= "", m.moveToCandidate(-1); else, m.stepSeries(-1); end
                case "series.right"
                    if m.Selection.Wave ~= "", m.moveToCandidate(1); else, m.stepSeries(1); end
                case "nav.openSeries",   app.activateTab("Series");
                case "nav.openTrials",   app.activateTab("Trials");
                case "thr.accept",       m.acceptFit();
                case "thr.atLevel",      m.setThresholdAtLevel(m.Selection.Level);
                case "thr.noResponse",   m.setNoResponse();
                case "thr.allRespond",   m.setAllRespond();
                case "thr.exclude"
                    [~,excluded] = m.toggleExcluded();
                    if excluded
                        sk = m.Selection.SeriesKey;
                        app.NoteEditor.open(struct('Kind',"series",'Key',sk),app.currentNote(sk));
                    end
                case "thr.clear",        m.clearDecision();
                case "thr.override",     m.cycleDetectionOverride(m.Selection.ConditionKey);
                case "peak.autoPick",    m.pickPeaks("series");
                case "peak.retrack",     m.retrack();
                case "peak.retrackOverwrite", m.retrack(Overwrite=true);
                case "peak.nudgeLeft",   m.nudgePeak(-1);
                case "peak.nudgeRight",  m.nudgePeak(1);
                case "peak.absent",      m.togglePeakAbsent();
                case "peak.absentBelow", m.togglePeakAbsent(Below=true);
                case "peak.revert",      m.revertPeak();
                case "trials.reject",    m.setSweepsRejected(true);
                case "trials.restore",   m.setSweepsRejected(false);
                otherwise
                    if startsWith(id,"view.tab")
                        k = str2double(extractAfter(id,"view.tab"));
                        app.activateTab(app.TabNames(k));
                    elseif startsWith(id,"peak.wave") || startsWith(id,"peak.trough")
                        k = str2double(regexp(char(id),'\d+$','match','once'));
                        names = app.waveNames();
                        if k <= numel(names)
                            kind = "P";
                            if startsWith(id,"peak.trough"), kind = "N"; end
                            m.selectWave(names(k),kind);
                        end
                    end
                    % other view.* commands belong to the views
            end
        end

        function names = waveNames(app)
            names = ["I","II","III","IV","V"];
            try
                W = app.Model.Settings.Waves;
                W = W([W.Enabled]);
                n = string({W.Name});
                if ~isempty(n), names = n; end
            catch
            end
        end

        % ---- actions -----------------------------------------------------
        function browseRoot(app)
            m = app.Model;
            start = "";
            if ~isempty(m.Catalog), start = string(m.Catalog.Root); end
            if start == ""
                r = mabr.ui.AnalysisApp.recentRoots();
                if ~isempty(r), start = r(1); end
            end
            p = string(m.PickFolderFcn(start,"Open a data folder"));
            if isempty(p) || ismissing(p) || p == "", return; end
            app.openRoot(p);
        end

        function onRecentPicked(app,src)
            v = src.Value;
            src.Value = {};
            if isempty(v), return; end
            if iscell(v), v = v{1}; end
            p = string(v);
            if p == "", return; end                 % (the "no recent folders" line)
            if ~isfolder(p)
                app.forgetRoot(p);
                app.setStatus("That folder is not there any more: " + p,1);
                return
            end
            app.openRoot(p);
        end

        function openSelected(app)
            if ~isempty(app.Browser) && isvalid(app.Browser)
                app.Browser.openSelected();
            else
                app.setStatus("Select a session in the browser first.",0);
            end
        end

        function [keys,fromBrowser] = selectedKeys(app)
            % The browser's selection, else the open session.
            %   fromBrowser  (returned) true when KEYS are the browser's
            keys = strings(0,1);
            try
                if ~isempty(app.Browser) && isvalid(app.Browser)
                    keys = reshape(string(app.Browser.selectedKeys()),[],1);
                end
            catch
            end
            fromBrowser = ~isempty(keys);
            if isempty(keys) && app.Model.SessionKey ~= ""
                keys = app.Model.SessionKey;
            end
        end

        function poolSelected(app)
            % Pool the browser's selection, after saying what that pools.
            m = app.Model;
            keys = app.selectedKeys();
            if numel(keys) < 2
                app.setStatus("Select two or more sessions of one subject in the browser to pool them.",1);
                return
            end
            names = strings(numel(keys),1);
            for k = 1:numel(keys)
                try
                    names(k) = m.sessionInfo(keys(k)).Name;
                catch
                    names(k) = keys(k);
                end
            end
            msg = "Pool the sweeps of " + numel(keys) + " sessions (" + strjoin(names,", ") + ...
                ") as one session? Every condition they share is averaged over all their " + ...
                "sweeps; the sessions themselves leave the study until the pool is dissolved.";
            c = string(m.ConfirmFcn(msg,"Pool sweeps",["Pool","Cancel"],"Pool"));
            if c ~= "Pool", return; end
            m.pool(keys,"");
        end

        function exportScript(app)
            % File ▸ Export Analysis Script… (and its toolbar button): with
            % no session open, a study script of the browser's selection
            % (else of the in-study sessions); with one open, its own script
            % -- unless the browser holds a selection of several sessions,
            % when the choice is asked for: this session, the selected
            % ones, or the study. Model.exportScript names on the status
            % line what was written.
            m = app.Model;
            [keys,fromBrowser] = app.selectedKeys();
            keys = unique(keys,'stable');
            if isempty(m.Session)
                if ~fromBrowser, keys = strings(0,1); end
                m.exportScript('Keys',keys);
                return
            end
            if ~(fromBrowser && numel(keys) > 1)
                m.exportScript();
                return
            end
            sel = "The " + numel(keys) + " selected sessions";
            c = string(m.ConfirmFcn("Write the replication script of which sessions? The open " + ...
                "session (" + m.SessionKey + "), the " + numel(keys) + " sessions selected in the " + ...
                "browser, or every session in the study.","Export analysis script", ...
                ["This session",sel,"The study","Cancel"],"This session"));
            switch c
                case "This session"
                    m.exportScript();
                case sel
                    m.exportScript('Keys',keys);
                case "The study"
                    m.exportScript('Study',true);
                otherwise
                    app.setStatus("No script written.",0);
            end
        end

        function openNote(app)
            m = app.Model;
            if isempty(m.Session)
                app.setStatus("Open a session first.",0);
                return
            end
            sk = m.Selection.SeriesKey;
            if sk ~= ""
                app.NoteEditor.open(struct('Kind',"series",'Key',sk),app.currentNote(sk));
            else
                txt = "";
                try
                    T = m.Project.Sessions;
                    r = find(string(T.Key) == m.SessionKey,1);
                    if ~isempty(r), txt = string(T.Comment(r)); end
                catch
                end
                app.NoteEditor.open(struct('Kind',"session",'Key',m.SessionKey),txt);
            end
        end

        function t = currentNote(app,sk)
            t = "";
            try
                T = app.Model.Session.Thresholds;
                r = find(string(T.Key) == sk,1);
                if ~isempty(r), t = string(T.Note(r)); end
                if ismissing(t), t = ""; end
            catch
            end
        end

        function toggleBrowser(app)
            app.BrowserVisible = ~app.BrowserVisible;
            app.applyBrowserVisible();
        end

        function applyBrowserVisible(app)
            w = 0;
            if app.BrowserVisible, w = app.BrowserWidth; end
            cw = app.H.Content.ColumnWidth;
            cw{1} = w;
            app.H.Content.ColumnWidth = cw;
            app.H.BrowserHost.Visible = matlab.lang.OnOffSwitchState(app.BrowserVisible);
            app.H.MenuBrowser.Checked = matlab.lang.OnOffSwitchState(app.BrowserVisible);
        end

        function focusFind(app)
            if ~app.BrowserVisible
                app.BrowserVisible = true;
                app.applyBrowserVisible();
            end
            h = findall(app.H.BrowserHost,'Tag','AnalysisBrowserSearch');
            m = app.Model;
            m.FocusArea = "browser";
            m.KeyTarget = "ui";
            if ~isempty(h)
                mabr.ui.analysis.Compat.tryFocus(h(1));
            end
        end

        function chooseResultsFolder(app)
            m = app.Model;
            if isempty(m.Catalog)
                app.setStatus("Open a data folder first.",0);
                return
            end
            f = string(m.PickFolderFcn(m.resultsFolder(),"Choose the results folder"));
            if isempty(f) || ismissing(f) || f == "", return; end
            root = string(m.Catalog.Root);
            m.setResultsFolder(f);
            app.rememberResultsFolder(root,f);
        end

        function setAnalyst(app)
            m = app.Model;
            v = m.PromptFcn("Your name or initials (stamped on every edit):","Analyst name",m.Analyst);
            if isempty(v), return; end
            v = strtrim(string(v));
            if v == "", return; end
            m.Analyst = v;
            try
                setpref('MABR','OfflineAnalysisAnalyst',char(v));
            catch
            end
            app.setStatus("Edits are now signed " + v + ".",0);
        end

        function toggleRestore(app)
            on = ~mabr.ui.AnalysisApp.restoreEnabled();
            try
                setpref('MABR','OfflineAnalysisRestore',on);
            catch
            end
            app.H.MenuRestore.Checked = matlab.lang.OnOffSwitchState(on);
        end

        function loadSettingsFile(app)
            m = app.Model;
            f = string(m.PickFileFcn("*.mabraset","Load analysis settings","open",""));
            if f == "", return; end
            [s,warn] = mabr.analysis.Settings.load(f);
            txt = m.setSettings(s);
            if ~isempty(warn), txt = txt + " " + strjoin(warn," "); end
            app.setStatus(txt,double(~isempty(warn)));
        end

        function saveSettingsFile(app)
            m = app.Model;
            f = string(m.PickFileFcn("*.mabraset","Save analysis settings","save","analysis.mabraset"));
            if f == "", return; end
            f = m.Settings.save(f);
            app.setStatus("Settings saved to " + f,0);
        end

        function txt = applySettingsFromDialog(app,s)
            % The settings dialog's OK/Apply: project settings + the user's
            % defaults (pref).
            txt = app.Model.setSettings(s,'Persist',true);
        end

        function openGuide(~,anchor)
            url = mabr.ui.wikiURL('Analysis-App');
            if anchor ~= "", url = [url '#' char(anchor)]; end
            web(url,'-browser');
        end

        function openLogFolder(app)
            [~,d] = mabr.log.logFile();
            if isempty(d)
                app.setStatus("No log folder: the logger (granary) is not on the path.",1);
                return
            end
            mabr.ui.AnalysisApp.showFolder(string(d));
        end

        function openTests(app)
            try
                t = mabr.ui.TestRunner();
                app.keepDialog(t);
            catch me
                app.setStatus("The verification tests could not open: " + string(me.message),2);
            end
        end

        % ---- F1 ----------------------------------------------------------
        function fillKeysWindow(app)
            f = app.KeysWindow;
            t = findall(f,'Tag','AnalysisKeysTable');
            if isempty(t), return; end
            sc = ["global",lower(app.ActiveTab),"browser"];
            S = mabr.ui.analysis.Commands.sheet(sc);
            % (and what the mouse does there that no key does: dragging a
            % threshold divider)
            S = [S; mabr.ui.analysis.Commands.gestures(sc)];
            where = S.Scope;
            where(where == "global") = "anywhere";
            t.Data = table(S.Keys,S.Command,where,'VariableNames',{'Keys','Command','Where'});
        end

        function keysWindowKey(app,e)
            if any(strcmp(e.Key,{'escape','f1'}))
                app.closeKeysWindow();
            end
        end

        function closeKeysWindow(app)
            f = app.KeysWindow;
            if isempty(f) || ~isvalid(f), return; end
            if app.RememberState
                mabr.ui.WindowPos.remember(f,'OfflineAnalysisKeys');
            end
            delete(f);
            app.KeysWindow = [];
        end

        % ---- closing -----------------------------------------------------
        function onCloseRequest(app)
            if ~isvalid(app) || app.Closing, return; end
            m = app.Model;
            if ~isempty(m) && isvalid(m) && m.Busy
                m.CloseRequested = true;
                m.cancel();
                app.setStatus("Closing after the current step…",1);
                % Nothing is redrawn for a window about to go: the job's
                % end would otherwise rebuild the tree and the tables, and
                % the client, still rendering them, sends events back to
                % components already deleted ("Invalid or deleted object").
                app.ClosePending = true;
                try
                    if ~isempty(app.Browser) && isvalid(app.Browser), app.Browser.deactivate(); end
                catch
                end
                for n = app.TabNames
                    try
                        v = app.Views.(n);
                        if ~isempty(v) && isvalid(v), v.deactivate(); end
                    catch
                    end
                end
                return
            end
            app.closeNow();
        end

        function closeNow(app)
            if ~isvalid(app) || app.Closing, return; end
            m = app.Model;
            try
                if ~isempty(m) && isvalid(m), m.flush(); end
            catch me
                mabr.log.vprintf(1,'Analysis app: pending edits were not saved on close (%s).',me.message);
            end
            if app.RememberState
                mabr.ui.WindowPos.remember(app.Figure,'OfflineAnalysis');
                app.saveState();
            end
            % (let the window take the events its client still has in
            % flight -- a job's last redraw -- while its components exist:
            % arriving after the delete, each prints "Invalid or deleted
            % object" from MATLAB's panel controller)
            % A drawnow alone returns before the client has finished: it
            % goes on laying the window out (and reporting positions,
            % scrolls and menu states back) for a moment after a job's last
            % redraw, so the window is given that moment.
            try
                if ~isempty(app.Figure) && isvalid(app.Figure)
                    t = tic;
                    while toc(t) < app.CloseSettle && isvalid(app)
                        drawnow;
                        pause(0.02);
                    end
                end
            catch
            end
            if ~isvalid(app), return; end
            delete(app);
        end

        function onFigureDeleted(app)
            if ~isvalid(app) || app.Closing, return; end
            app.Figure = [];
            delete(app);
        end

        function deferClose(app)
            % The Model's job has unwound with a close requested: close once
            % control returns to the event loop.
            if ~isvalid(app) || app.Closing, return; end
            try
                if ~isempty(app.CloseTimer) && isvalid(app.CloseTimer), return; end
                app.CloseTimer = timer('Tag','MABR_OfflineClose','StartDelay',0.05, ...
                    'ExecutionMode','singleShot','BusyMode','drop', ...
                    'TimerFcn',@(t,~) app.closeFromTimer(t));
                start(app.CloseTimer);
            catch
                app.closeNow();
            end
        end

        function closeFromTimer(app,t)
            try
                stop(t);
                delete(t);
            catch
            end
            if isvalid(app)
                app.CloseTimer = [];
                app.closeNow();
            end
        end

        % ---- state persistence -------------------------------------------
        function saveState(app)
            m = app.Model;
            st = struct('Root',"",'SessionKey',"",'Tab',app.ActiveTab,'SeriesKey',"", ...
                'ConditionKey',"",'BrowserFilter',"",'BrowserShow',"");
            try
                if ~isempty(m.Catalog), st.Root = string(m.Catalog.Root); end
                st.SessionKey = m.SessionKey;
                st.SeriesKey = m.Selection.SeriesKey;
                st.ConditionKey = m.Selection.ConditionKey;
                h = findall(app.H.BrowserHost,'Tag','AnalysisBrowserSearch');
                if ~isempty(h), st.BrowserFilter = string(h(1).Value); end
                h = findall(app.H.BrowserHost,'Tag','AnalysisBrowserShow');
                if ~isempty(h), st.BrowserShow = string(h(1).Value); end
            catch
            end
            try
                setpref('MABR','OfflineAnalysisLastState',st);
                setpref('MABR','OfflineAnalysisLayout',struct('BrowserVisible',app.BrowserVisible));
            catch me
                mabr.log.vprintf(2,'Analysis app: state not remembered (%s).',me.message);
            end
        end

        function restoreState(app)
            % Reopen the last folder, session, tab and browser filter --
            % guarded end to end: whatever has moved, the window opens.
            if ~mabr.ui.AnalysisApp.restoreEnabled(), return; end
            try
                if ~ispref('MABR','OfflineAnalysisLastState'), return; end
                st = getpref('MABR','OfflineAnalysisLastState');
                if ~isstruct(st) || ~isfield(st,'Root'), return; end
                root = string(st.Root);
                if isempty(root) || ismissing(root) || root == "", return; end
                if ~isfolder(root)
                    app.put('start_msg',app.H.StartMessage,'Text', ...
                        char("The last folder, " + root + ", is not there any more."));
                    app.setStatus("The last folder is not there any more: " + root,1);
                    return
                end
                m = app.Model;
                m.openRoot(root,SuggestStudyRoot=false);
                key = mabr.ui.AnalysisApp.field(st,'SessionKey');
                if key ~= ""
                    if any(string(m.Catalog.Sessions.Key) == key) || startsWith(key,"pool:")
                        m.openSession(key,SeriesKey=mabr.ui.AnalysisApp.field(st,'SeriesKey'));
                        ck = mabr.ui.AnalysisApp.field(st,'ConditionKey');
                        if ck ~= "" && ~isempty(m.Session)
                            try
                                m.selectCondition(ck);
                            catch
                            end
                        end
                    else
                        app.setStatus("The last session is no longer in this folder.",1);
                    end
                end
                tab = mabr.ui.AnalysisApp.field(st,'Tab');
                if any(app.TabNames == tab) && ~isempty(m.Session)
                    app.activateTab(tab);
                end
                if ~isempty(app.Browser) && isvalid(app.Browser)
                    try
                        app.Browser.applyFilter(mabr.ui.AnalysisApp.field(st,'BrowserFilter'), ...
                            mabr.ui.AnalysisApp.field(st,'BrowserShow'));
                    catch
                    end
                end
            catch me
                app.setStatus("Could not reopen the last session: " + string(me.message),1);
                mabr.log.vprintf(2,me);
            end
        end

        function applyLayoutPref(app)
            try
                if ispref('MABR','OfflineAnalysisLayout')
                    L = getpref('MABR','OfflineAnalysisLayout');
                    if isstruct(L) && isfield(L,'BrowserVisible')
                        app.BrowserVisible = logical(L.BrowserVisible);
                    end
                end
            catch
            end
            app.applyBrowserVisible();
        end

        function rememberRoot(app,path)
            % Most recent first, ten at most, one entry per folder (case aside).
            r = mabr.ui.AnalysisApp.recentRoots();
            r = r(~strcmpi(r,path));
            r = [string(path); r];
            r = r(1:min(end,app.MaxRecent));
            try
                setpref('MABR','OfflineRecentRoots',cellstr(r));
            catch
            end
            app.fillRecent();
        end

        function forgetRoot(app,path)
            r = mabr.ui.AnalysisApp.recentRoots();
            r = r(~strcmpi(r,path));
            try
                setpref('MABR','OfflineRecentRoots',cellstr(r));
            catch
            end
            app.fillRecent();
        end

        function rememberResultsFolder(~,root,folder)
            M = struct('Root',{},'Folder',{});
            try
                if ispref('MABR','OfflineResultsFolders')
                    v = getpref('MABR','OfflineResultsFolders');
                    if isstruct(v) && all(isfield(v,{'Root','Folder'})), M = v; end
                end
            catch
            end
            keep = true(1,numel(M));
            for i = 1:numel(M)
                keep(i) = ~strcmpi(string(M(i).Root),root);
            end
            M = M(keep);
            M(end+1) = struct('Root',char(root),'Folder',char(folder));
            try
                setpref('MABR','OfflineResultsFolders',M);
            catch
            end
        end

        function fillRecent(app)
            r = mabr.ui.AnalysisApp.recentRoots();
            lb = app.ctrl('StartRecent');
            if ~isempty(lb)
                if isempty(r)
                    % (first use: a muted line in the box, not an empty one)
                    lb.Items = {'No recent folders yet — use Open data folder… above.'};
                    lb.ItemsData = {''};
                    lb.Value = {};
                    lb.Enable = 'off';
                else
                    lb.Items = cellstr(reshape(r,1,[]));
                    lb.ItemsData = cellstr(reshape(r,1,[]));
                    lb.Value = {};
                    lb.Enable = 'on';
                end
            end
            mr = app.ctrl('MenuRecent');
            if ~isempty(mr)
                delete(mr.Children);
                if isempty(r)
                    uimenu(mr,'Text','(none)','Enable','off');
                end
                for k = 1:numel(r)
                    p = r(k);
                    uimenu(mr,'Text',char(p),'MenuSelectedFcn',app.cb(@(~,~) app.openRecent(p)));
                end
            end
        end

        function openRecent(app,p)
            if ~isfolder(p)
                app.forgetRoot(p);
                app.setStatus("That folder is not there any more: " + p,1);
                return
            end
            app.openRoot(p);
        end

        % ---- dialogs the injectable functions default to ------------------
        function c = defaultConfirm(app,msg,title,options,default)
            c = string(default);
            f = app.Figure;
            if isempty(f) || ~isvalid(f) || ~strcmp(f.Visible,'on'), return; end
            try
                c = string(uiconfirm(f,char(msg),char(title),'Options',cellstr(options), ...
                    'DefaultOption',char(default),'CancelOption',char(options(end))));
            catch
                c = string(default);
            end
        end

        function defaultAlert(app,msg,title,icon)
            f = app.Figure;
            if isempty(f) || ~isvalid(f) || ~strcmp(f.Visible,'on')
                mabr.log.vprintf(1,'%s: %s',char(title),char(msg));
                return
            end
            try
                uialert(f,char(msg),char(title),'Icon',char(icon));
            catch
                mabr.log.vprintf(1,'%s: %s',char(title),char(msg));
            end
        end

        function p = defaultPickFolder(app,start,title)
            p = "";
            s = char(start);
            if isempty(s) || ~isfolder(s), s = pwd; end
            d = uigetdir(s,char(title));
            if ~isequal(d,0), p = string(d); end
            app.raise();
        end

        function p = defaultPickFile(app,filter,title,mode,default)
            p = "";
            flt = cellstr(string(filter));
            if string(mode) == "save"
                [fn,pn] = uiputfile(flt,char(title),char(default));
            else
                [fn,pn] = uigetfile(flt,char(title),char(default));
            end
            if ~isequal(fn,0), p = string(fullfile(pn,fn)); end
            app.raise();
        end

        function h = openProgress(app,~,title)
            m = app.Model;
            h = struct('update',@(text,frac) [],'cancelled',@() m.CancelRequested,'close',@() []);
            if app.ProgressMode ~= "dialog", return; end
            f = app.Figure;
            if isempty(f) || ~isvalid(f) || ~strcmp(f.Visible,'on'), return; end
            try
                d = uiprogressdlg(f,'Title',char(title),'Cancelable','on', ...
                    'ShowPercentage','on','Message','');
                h = struct('update',@(text,frac) mabr.ui.AnalysisApp.progressUpdate(d,text,frac), ...
                    'cancelled',@() mabr.ui.AnalysisApp.progressCancelled(d,m), ...
                    'close',@() mabr.ui.AnalysisApp.progressClose(d));
            catch me
                mabr.log.vprintf(2,'Analysis app: no progress window (%s).',me.message);
            end
        end

        function keepDialog(app,d)
            % Remember a window this app opened (closed with it), forgetting
            % the ones already closed.
            keep = cellfun(@(x) ~isempty(x) && isvalid(x),app.Dialogs);
            app.Dialogs = [app.Dialogs(keep) {d}];
        end

        % ---- write-on-change ----------------------------------------------
        function put(app,key,h,prop,v)
            key = char(key);
            if isfield(app.Written,key) && isequal(app.Written.(key),v), return; end
            try
                h.(char(prop)) = v;
                app.Written.(key) = v;
            catch me
                mabr.log.vprintf(2,'Analysis app: could not set %s (%s).',char(prop),me.message);
            end
        end

        function h = ctrl(app,name)
            h = [];
            if isfield(app.H,name)
                h = app.H.(name);
                if ~isempty(h) && ~isvalid(h), h = []; end
            end
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function [key,mods,ch] = keyParts(evt)
            key = ""; mods = ""; ch = "";
            try
                key = lower(string(evt.Key));
            catch
            end
            try
                mods = mabr.ui.analysis.Commands.normalizeMods(evt.Modifier);
            catch
            end
            try
                ch = string(evt.Character);
            catch
            end
            if isempty(key) || ismissing(key), key = ""; end
            if isempty(ch) || ismissing(ch), ch = ""; end
        end

        function s = menuText(txt,keys)
            s = string(txt);
            keys = string(keys);
            if keys ~= ""
                k = extractBefore(keys + " or"," or");
                s = s + " (" + k + ")";
            end
        end

        function tf = hasOption(args,name)
            % Whether name-value ARGS (a cell row) name NAME (any case).
            tf = false;
            for k = 1:2:numel(args)
                a = args{k};
                if (ischar(a) || (isstring(a) && isscalar(a))) && strcmpi(string(a),name)
                    tf = true;
                    return
                end
            end
        end

        function c = blankGlyph()
            % A plain grey square: a toolbar button whose picture is missing.
            c = nan(16,16,3);
            c(3:14,3:14,:) = 0.75;
            c(4:13,4:13,:) = 0.93;
        end

        function r = recentRoots()
            r = strings(0,1);
            try
                if ispref('MABR','OfflineRecentRoots')
                    v = getpref('MABR','OfflineRecentRoots');
                    r = reshape(string(v),[],1);
                    r = r(~ismissing(r) & r ~= "");
                end
            catch
                r = strings(0,1);
            end
        end

        function tf = restoreEnabled()
            tf = true;
            try
                if ispref('MABR','OfflineAnalysisRestore')
                    tf = logical(getpref('MABR','OfflineAnalysisRestore'));
                end
            catch
                tf = true;
            end
        end

        function v = field(s,name)
            v = "";
            if isfield(s,name)
                v = string(s.(name));
                if isempty(v) || ismissing(v(1)), v = ""; else, v = v(1); end
            end
        end

        function showFolder(paths)
            paths = string(paths);
            if isempty(paths), return; end
            p = char(paths(1));
            if isfile(p), p = fileparts(p); end
            if ~isfolder(p), return; end
            try
                if ispc
                    winopen(p);
                else
                    system(['open "' p '"']);
                end
            catch
            end
        end

        function progressUpdate(d,text,frac)
            try
                if isvalid(d)
                    d.Message = char(text);
                    d.Value = min(max(frac,0),1);
                    drawnow limitrate
                end
            catch
            end
        end

        function tf = progressCancelled(d,m)
            tf = m.CancelRequested;
            try
                if isvalid(d), tf = tf || d.CancelRequested; end
            catch
            end
        end

        function progressClose(d)
            try
                if isvalid(d), close(d); end
            catch
            end
        end
    end
end
