classdef Browser < mabr.ui.analysis.View
% mabr.ui.analysis.Browser  The left column of the analysis app: every session of the open folder.
%
%   The browser is how a study is walked: a tree of subjects, their visits
%   (one per day) and the sessions recorded on each, with what matters about
%   each session on its own line -- whether it is analysed and up to date,
%   what was presented, how many files, whether it holds an interleaved run,
%   a run stopped early or Test Mode data, and how many of its series have
%   been reviewed:
%
%       SUBJ-ID-1254 (6)
%         2026-10-01 · Baseline (2)
%           ● 10:00  Tone 2×5 · 10 files  ✓5/7
%           ◐ 14:00  Tone 2×5 ×2 · ClickTrain ×5 · 24 files ⧉  ✓0/4
%           ⊕ Pool: 10:00 + 14:00  ○
%
%   Status glyphs are mabr.ui.analysis.Style's (○ not analysed, ● up to
%   date, ◐ out of date, ✓ up to date and every series reviewed, ✕ failed);
%   badges only when true (⧉ interleaved run, ⚠ short run, TEST Test Mode).
%   Above the tree: the folder (a dropdown of recent ones; picking one opens
%   it), Browse and Rescan, where the results go (a link to the folder), a
%   search box and a Show filter. Below it: what the selection is, its
%   Timepoint (a visit's sets every session of that day), its animal's Group
%   (subject level, whichever of its sessions is selected), In study, a
%   comment, and Open / Analyse n sessions… / Pool.
%
%   The tree's nodes are REBUILT only when what it lists changed -- another
%   folder, a session that came or went, a pool, the filter -- since
%   deleting and creating uitree nodes is what redrawing the window spends
%   its time on. Otherwise (a rescan that found nothing new, a label, an
%   analysis, an autosave, new settings) the texts that moved are rewritten
%   in place, which also keeps whatever the user expanded.
%
%   Every control is wrapped with the app's cb(...,"browser"), so after a
%   click here the arrow keys move the tree and Return opens the selection,
%   while the plots' letter keys stay off until a plot is clicked. In blind
%   review the tree, search and details are covered ("Blind review — item
%   14 of 236" and End review): who and when is exactly what blind review
%   hides.
%
%   Public methods (tests call these instead of synthesising clicks):
%     applyFilter(text,show)   search text and Show ("All", "Needs review",
%                              "Not analysed", "Out of date", "Failed",
%                              "Not in study", "Test Mode"); text "" = no
%                              search, show "" = "All" (both replace what
%                              was in force)
%     selectKeys(keys)         select session (or pool) nodes by key
%     openSelected()           open the first selected session
%     keys = selectedKeys()    the session keys the selection stands for (a
%                              subject or visit node: its visible sessions)
%     info = selectedNodeInfo()  struct Type, Key, Subject, Day, Keys, Count
%     importNested(path)       import a nested results store ("" = the one
%                              the banner offers)
%     setTimepoint(v), setGroup(v), setInStudy(tf), comment(text)
%                              what the details controls do, for the
%                              selection
%     poolSelected()           confirm (listing what is pooled per
%                              condition) and pool the selection
%     refresh(what,keys)       redraw (View's contract)
%     flush()                  apply a search still waiting for its pause
%   and statics nodeText(row) / visitText(day,timepoints,n) /
%   showNames() -- the text of a node, from a Model.projectView row.
%
%   No pref of its own: the filter is remembered by the app with the rest
%   of its last state (OfflineAnalysisLastState).
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.Model.projectView,
%   mabr.ui.analysis.SessionView, mabr.analysis.Project.view
%
% Daniel Stolzberg (c) 2026

    properties
        % How a folder is shown in Explorer (results link, Show in
        % Explorer): [] = winopen. Tests put a stub here.
        OpenFolderFcn = []
    end

    properties (SetAccess = private)
        FilterText (1,1) string = ""        % the search in force
        FilterShow (1,1) string = "All"     % the Show choice in force
        VisibleKeys (:,1) string = strings(0,1)   % session/pool keys in tree order
        RebuildCount (1,1) double = 0       % times the tree was rebuilt (tests)
        PendingSearch = []                  % search text waiting for its pause ([] = none)
    end

    properties (Access = private)
        NodeMap = []                        % containers.Map key -> uitreenode (sessions, pools)
        NodeText = []                       % containers.Map key -> the text last written
        % The tree as built: one entry per node, parents before children --
        % its id ("<Type>|<Key>"), its parent's index (0 = the tree), the
        % node and the text last written. What a pass would list is compared
        % with these, so an unchanged tree is rewritten in place, not rebuilt.
        TreeIds (:,1) string = strings(0,1)
        TreeParents (:,1) double = zeros(0,1)
        TreeNodes = gobjects(0,1)
        TreeTexts (:,1) string = strings(0,1)
        % The subjects the user opened (and the open sessions'), so a tree
        % built again -- a pool, a session that came or went -- opens them
        % again rather than collapsing everything but the current subject.
        ExpandedSubjects (:,1) string = strings(0,1)
        SearchTimer = []
        MenuTarget = []                     % the node a context menu was opened on
        LastSessionKey (1,1) string = ""
        Banner = struct('Path',"",'Count',0)
        View_ = []                          % projectView as last read (one refresh)
    end

    properties (Constant)
        ShowOptions = ["All","Needs review","Not analysed","Out of date","Failed", ...
            "Not in study","Test Mode"]
        SearchDelay = 0.3                   % s after the last keystroke
        UnknownDate = "(unknown date)"
    end

    % =====================================================================
    methods
        function obj = Browser(parent,model,host)
            % Browser(parent,model,host): build into PARENT (the app's
            % AnalysisBrowserHost panel) and listen to MODEL.
            %   host  mabr.ui.AnalysisApp, or [] (a test drives it alone)
            if nargin < 3, host = []; end
            obj@mabr.ui.analysis.View(parent,model,host);
            obj.activate();               % the browser is always showing
        end

        function delete(obj)
            % (View's delete then drops the listeners and the graphics)
            obj.stopSearchTimer();
        end

        % ---- View contract -------------------------------------------------
        function refresh(obj,what,keys)
            % Redraw what WHAT says moved (ChangeData's word): "all" and the
            % words that change what is listed rebuild the tree; status words
            % rewrite node texts in place; anything else is not the
            % browser's (selection, messages, busy...).
            if nargin < 3, keys = strings(0,1); end
            what = string(what);
            switch what
                case "all"
                    obj.refreshAll();
                case {"labels","pools","columns"}
                    obj.rebuildTree();
                    obj.refreshDetails();
                case {"status","save","thresholds","curation","rejection","detection", ...
                        "measures","peaks","files"}
                    obj.refreshStatus(keys);
                case "queue"
                    obj.refreshBlind();
                otherwise
                    % ("message", "busy", "idle", "condition", "series", ...:
                    % nothing the browser draws)
            end
        end

        function flush(obj)
            % Apply a search that is still waiting for the typing to pause.
            if ~isempty(obj.PendingSearch)
                t = string(obj.PendingSearch);
                obj.PendingSearch = [];
                obj.stopSearchTimer();
                obj.setFilter(t,obj.FilterShow);
            end
        end

        % ---- public API ------------------------------------------------------
        function applyFilter(obj,text,show)
            % Search for TEXT (subject, folder, stimuli, summary, timepoint,
            % group; any case; "" = every session) and show only SHOW ("" =
            % "All").
            arguments
                obj
                text (1,1) string = ""
                show (1,1) string = ""
            end
            if ismissing(text), text = ""; end
            if ismissing(show) || show == "", show = "All"; end
            k = find(strcmpi(obj.ShowOptions,show),1);
            if isempty(k)
                error('mabr:ui:Browser:badShow','"%s" is not a Show choice (%s).',show, ...
                    strjoin(obj.ShowOptions,", "));
            end
            obj.PendingSearch = [];
            obj.stopSearchTimer();
            obj.setFilter(text,obj.ShowOptions(k));
        end

        function selectKeys(obj,keys)
            % Select the session (or pool) nodes of KEYS that are listed.
            arguments
                obj
                keys string
            end
            nodes = obj.nodesFor(keys);
            obj.selectNodes(nodes);
            obj.refreshDetails();
        end

        function openSelected(obj,source)
            % Open the first selected session (a subject's or visit's first
            % visible session when one of those is selected); SOURCE
            % "auto" (default: its results when it has any) or "raw".
            if nargin < 2, source = "auto"; end
            keys = obj.selectedKeys();
            if isempty(keys)
                obj.status("Select a session in the browser first.",0);
                return
            end
            obj.Model.openSession(keys(1),Source=string(source));
        end

        function keys = selectedKeys(obj)
            % The session (and pool) keys the selection stands for: a
            % session or pool node its own key, a subject or visit node every
            % session listed under it -- in tree order, each once.
            keys = strings(0,1);
            nodes = obj.selectedNodes();
            for k = 1:numel(nodes)
                keys = [keys; obj.keysUnder(nodes(k))]; %#ok<AGROW>
            end
            [~,i] = unique(keys,'stable');
            keys = keys(sort(i));
        end

        function info = selectedNodeInfo(obj)
            % What is selected: struct Type ("none"|"subject"|"visit"|
            % "session"|"pool"|"multiple"), Key, Subject, Day, Keys (the
            % sessions it stands for), Count (nodes selected).
            info = struct('Type',"none",'Key',"",'Subject',"",'Day',NaT,'Keys',strings(0,1),'Count',0);
            nodes = obj.selectedNodes();
            info.Count = numel(nodes);
            info.Keys = obj.selectedKeys();
            if isempty(nodes), return; end
            if numel(nodes) > 1
                info.Type = "multiple";
                return
            end
            d = nodes(1).NodeData;
            info.Type = string(d.Type);
            info.Key = string(d.Key);
            info.Subject = string(d.Subject);
            info.Day = d.Day;
        end

        function n = importNested(obj,path)
            % Import a nested results store into this project ("" = the one
            % the banner offers).
            arguments
                obj
                path (1,1) string = ""
            end
            if path == "", path = obj.Banner.Path; end
            n = 0;
            if path == "", return; end
            n = obj.Model.importNestedStore(path);
        end

        function ignoreNested(obj,path)
            % Stop offering a nested results store ("" = the banner's).
            arguments
                obj
                path (1,1) string = ""
            end
            if path == "", path = obj.Banner.Path; end
            if path == "", return; end
            obj.Model.ignoreNestedStore(path);
        end

        function note = setTimepoint(obj,value)
            % The Timepoint of the selection's sessions (a visit node: every
            % session of that day).
            arguments
                obj
                value (1,1) string
            end
            note = "";
            keys = obj.selectedKeys();
            if isempty(keys)
                obj.status("Select a session or a visit first.",0);
                return
            end
            note = obj.Model.label(keys,"Timepoint",strtrim(value));
        end

        function note = setGroup(obj,value)
            % The Group of the selection's animals (a subject label: every
            % session of the animal shares it).
            arguments
                obj
                value (1,1) string
            end
            note = "";
            subj = obj.selectedSubjects();
            if isempty(subj)
                obj.status("Select a subject or one of its sessions first.",0);
                return
            end
            note = obj.Model.label(subj,"Group",strtrim(value));
        end

        function setInStudy(obj,tf)
            % Use the selection in the study (or not): a subject node the
            % whole animal, anything else its sessions.
            arguments
                obj
                tf (1,1) logical
            end
            info = obj.selectedNodeInfo();
            if info.Type == "subject"
                obj.Model.setInStudy(info.Subject,tf);
            else
                keys = obj.selectedKeys();
                if isempty(keys), return; end
                obj.Model.setInStudy(keys,tf);
            end
        end

        function comment(obj,text)
            % A comment on the selection: a session's (Model.setNote), a
            % subject's, or the same comment on several sessions. Without
            % TEXT the Model's PromptFcn asks for it.
            info = obj.selectedNodeInfo();
            if info.Type == "none"
                obj.status("Select a session first.",0);
                return
            end
            if nargin < 2
                v = obj.Model.PromptFcn("Comment:","Comment",obj.currentComment(info));
                if isempty(v), return; end
                text = string(v);
            end
            text = string(text);
            switch info.Type
                case {"session","pool"}
                    obj.Model.setNote(struct('Kind',"session",'Key',info.Key),text);
                case "subject"
                    obj.Model.label(info.Subject,"Comment",text);
                otherwise
                    if isempty(info.Keys), return; end
                    obj.Model.label(info.Keys,"Comment",text);
            end
        end

        function key = poolSelected(obj)
            % Pool the selected sessions -- after the ConfirmFcn has listed,
            % condition by condition, the sweeps that are pooled.
            key = "";
            keys = obj.poolableKeys();
            if numel(keys) < 2
                obj.status("Select two or more sessions of one subject to pool them.",1);
                return
            end
            msg = obj.poolMessage(keys);
            c = string(obj.Model.ConfirmFcn(msg,"Pool sweeps",["Pool","Cancel"],"Pool"));
            if c ~= "Pool", return; end
            key = obj.Model.pool(keys,"");
        end

        function analyseSelected(obj)
            % "Analyse n sessions…": the batch dialog for the selection.
            keys = obj.selectedKeys();
            if isempty(keys)
                obj.status("Select the sessions to analyse first.",0);
                return
            end
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.openDialog("batch",keys);
            else
                obj.status("The batch dialog needs the analysis window.",1);
            end
        end

        function openResultsFolder(obj)
            % The results link: the folder in Explorer, or why not yet.
            f = obj.Model.resultsFolder();
            if f == ""
                obj.status("Open a data folder first.",0);
            elseif ~isfolder(f)
                obj.status("The results folder is created on the first save",0);
            else
                obj.showFolder(f);
            end
        end
    end

    % =====================================================================
    methods (Static)
        function s = nodeText(row)
            % The text of a session (or pool) node from one Model.projectView
            % row: "<status> 14:08  Tone 6×9 ×2 · 126 files ⧉ ⚠ TEST ✓5/7"
            % (a pool "⊕ Pool: 14:00 + 14:08  <status> ✓1/2"). Badges only
            % when true; the review count once there are series.
            %   row  one row (table or struct) with Status, Start, Summary,
            %        NumFiles, AcqModes, ShortRuns, TestMode, Reviewed,
            %        NumSeries and, for a pool, IsPool and PoolStarts (the
            %        members' start times, "HH:mm" strings)
            if istable(row), row = table2struct(row(1,:)); end
            st  = mabr.ui.analysis.Browser.field(row,'Status',"none");
            rev = double(mabr.ui.analysis.Browser.field(row,'Reviewed',0));
            ns  = double(mabr.ui.analysis.Browser.field(row,'NumSeries',0));
            if ~isfinite(rev), rev = 0; end
            if ~isfinite(ns), ns = 0; end
            glyph = mabr.ui.analysis.Style.statusGlyph(st,ns > 0 && rev >= ns);
            badges = strings(1,0);
            modes = lower(string(mabr.ui.analysis.Browser.field(row,'AcqModes',"")));
            if contains(modes,"interleaved"), badges(end+1) = mabr.ui.analysis.Style.BadgeInterleaved; end
            sr = double(mabr.ui.analysis.Browser.field(row,'ShortRuns',0));
            if isfinite(sr) && sr > 0, badges(end+1) = mabr.ui.analysis.Style.BadgeShort; end
            tm = string(mabr.ui.analysis.Browser.field(row,'TestMode',"none"));
            if tm ~= "none" && tm ~= "" && tm ~= "false" && tm ~= "0"
                badges(end+1) = mabr.ui.analysis.Style.BadgeTest;
            end
            if ns > 0
                badges(end+1) = mabr.ui.analysis.Style.GlyphReviewed + rev + "/" + ns;
            end
            tail = "";
            if ~isempty(badges), tail = " " + strjoin(badges," "); end
            if logical(mabr.ui.analysis.Browser.field(row,'IsPool',false))
                t = string(mabr.ui.analysis.Browser.field(row,'PoolStarts',strings(0,1)));
                t = t(t ~= "");
                if isempty(t), t = string(mabr.ui.analysis.Browser.field(row,'Name',"")); end
                % (the status after the name: the ⊕ is what says "pool")
                s = "⊕ Pool: " + strjoin(reshape(t,1,[])," + ") + "  " + glyph + tail;
                return
            end
            when = "--:--";
            t0 = mabr.ui.analysis.Browser.field(row,'Start',NaT);
            if isdatetime(t0) && ~isnat(t0), when = string(t0,'HH:mm'); end
            parts = strings(1,0);
            summ = string(mabr.ui.analysis.Browser.field(row,'Summary',""));
            if summ ~= "" && ~ismissing(summ), parts(end+1) = summ; end
            nf = double(mabr.ui.analysis.Browser.field(row,'NumFiles',NaN));
            if isfinite(nf)
                if nf == 1, parts(end+1) = "1 file"; else, parts(end+1) = nf + " files"; end
            end
            s = glyph + " " + when + "  " + strjoin(parts," · ") + tail;
        end

        function s = visitText(day,timepoints,n)
            % "2026-10-01 · Baseline (6)"; "(unknown date) (2)" without a day;
            % several timepoints joined by " / ". A timepoint that only
            % repeats the day ("2026-10-01", the default label of an
            % unlabelled visit) is left out: it says nothing the day does not.
            if isdatetime(day) && ~isnat(day)
                s = string(day,'yyyy-MM-dd');
            else
                s = mabr.ui.analysis.Browser.UnknownDate;
            end
            tp = reshape(string(timepoints),1,[]);
            tp = tp(~ismissing(tp) & strtrim(tp) ~= "");
            tp = unique(tp,'stable');
            tp = tp(strtrim(tp) ~= s);
            if ~isempty(tp), s = s + " · " + strjoin(tp," / "); end
            s = s + " (" + n + ")";
        end

        function names = showNames()
            % The Show filter's choices.
            names = mabr.ui.analysis.Browser.ShowOptions;
        end
    end

    % =====================================================================
    methods
        function build(obj)
            % View's contract: the controls, built once (see the class help).
            S = mabr.ui.analysis.Style;
            g = uigridlayout(obj.Parent,[6 1],'Padding',[6 6 4 6],'RowSpacing',4, ...
                'BackgroundColor',S.Panel);
            g.RowHeight = {26,20,26,0,'1x',220};
            obj.Handles.Grid = g;

            % ---- row 1: the folder, browse, rescan
            r1 = uigridlayout(g,[1 3],'ColumnWidth',{'1x',30,30},'Padding',[0 0 0 0], ...
                'ColumnSpacing',4,'BackgroundColor',S.Panel);
            r1.Layout.Row = 1;
            dd = uidropdown(r1,'Items',{'(no folder open)'},'ItemsData',{''},'Value','', ...
                'Tag','AnalysisBrowserRoot', ...
                'Tooltip','The data folder that is open; pick a recent one to open it.');
            dd.ValueChangedFcn = obj.viewWrap(@(src,~) obj.onRootPicked(src),"browser");
            b = uibutton(r1,'Text','…','Tag','AnalysisBrowserBrowse', ...
                'Tooltip','Open a data folder… (Ctrl+O)');
            if mabr.ui.analysis.Style.setButtonIcon(b,'load','center'), b.Text = ''; end
            b.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.onBrowse(),"browser");
            r = uibutton(r1,'Text','↻','Tag','AnalysisBrowserRescan', ...
                'Tooltip','Rescan the folder for new and changed files (F5).');
            if mabr.ui.analysis.Style.setButtonIcon(r,'repeat','center'), r.Text = ''; end
            r.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.rescan(),"browser");
            obj.Handles.Root = dd;
            obj.Handles.Browse = b;
            obj.Handles.Rescan = r;

            % ---- row 2: where the results go
            link = mabr.ui.analysis.Compat.makeLink(g,'Results: (no folder open)', ...
                @() obj.runWrapped(@() obj.openResultsFolder()));
            link.Layout.Row = 2;
            link.Tag = 'AnalysisBrowserResultsPath';
            try
                link.Tooltip = 'Where this study''s results and labels are kept; click to show the folder.';
            catch
            end
            obj.Handles.ResultsPath = link;

            % ---- row 3: search and show
            % (a label as well as the grey hint inside the box: the hint is
            % newer than R2021b, so Compat.setPlaceholder leaves it to the
            % tooltip there)
            r3 = uigridlayout(g,[1 3],'ColumnWidth',{'fit','1x',112},'Padding',[0 0 0 0], ...
                'ColumnSpacing',4,'BackgroundColor',S.Panel);
            r3.Layout.Row = 3;
            uilabel(r3,'Text','Find','FontColor',S.Muted, ...
                'Tooltip','Find sessions (Ctrl+F)');
            ef = uieditfield(r3,'text','Tag','AnalysisBrowserSearch', ...
                'Tooltip',['Find sessions by subject, folder, stimulus, timepoint or group ' ...
                '(Ctrl+F); the list follows as you type.']);
            mabr.ui.analysis.Compat.setPlaceholder(ef,'Search (Ctrl+F)');
            ef.ValueChangedFcn  = obj.viewWrap(@(src,~) obj.onSearchCommitted(src),"browser");
            ef.ValueChangingFcn = obj.viewWrap(@(~,e) obj.onSearchTyping(e),"browser");
            sh = uidropdown(r3,'Items',cellstr(obj.ShowOptions),'Value','All', ...
                'Tag','AnalysisBrowserShow', ...
                'Tooltip','Show only the sessions that need something (review, analysis, a re-run, ...).');
            sh.ValueChangedFcn = obj.viewWrap(@(src,~) obj.onShowPicked(src),"browser");
            obj.Handles.SearchRow = r3;
            obj.Handles.Search = ef;
            obj.Handles.Show = sh;

            % ---- row 4: a nested results store to import
            bp = uipanel(g,'BorderType','none','BackgroundColor',S.BarBlue, ...
                'Tag','AnalysisBrowserBanner','Visible','off');
            bp.Layout.Row = 4;
            bg = uigridlayout(bp,[2 2],'RowHeight',{'1x',20},'ColumnWidth',{'1x','1x'}, ...
                'Padding',[4 2 4 2],'RowSpacing',2,'ColumnSpacing',4,'BackgroundColor',S.BarBlue);
            bt = uilabel(bg,'Text','','WordWrap','on','FontColor',S.Ink, ...
                'Tag','AnalysisBrowserBannerText');
            bt.Layout.Row = 1; bt.Layout.Column = [1 2];
            bi = uibutton(bg,'Text','Import into this project','Tag','AnalysisBrowserBannerImport', ...
                'Tooltip',['Copy those results (and their labels) into this project''s store; ' ...
                'the original store is left as it is.']);
            bi.Layout.Row = 2; bi.Layout.Column = 1;
            bi.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.importNested(""),"browser");
            bn = uibutton(bg,'Text','Ignore','Tag','AnalysisBrowserBannerIgnore', ...
                'Tooltip','Stop offering to import that store into this project.');
            bn.Layout.Row = 2; bn.Layout.Column = 2;
            bn.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.ignoreNested(""),"browser");
            obj.Handles.Banner = bp;
            obj.Handles.BannerText = bt;

            % ---- row 5: the tree
            t = uitree(g,'Multiselect','on','Tag','AnalysisBrowserTree');
            t.Layout.Row = 5;
            t.SelectionChangedFcn = obj.viewWrap(@(~,~) obj.onTreeSelection(),"browser");
            t.NodeExpandedFcn  = obj.viewWrap(@(~,e) obj.onNodeExpanded(e,true),"browser");
            t.NodeCollapsedFcn = obj.viewWrap(@(~,e) obj.onNodeExpanded(e,false),"browser");
            mabr.ui.analysis.Compat.setDoubleClick(t,obj.viewWrap(@(~,~) obj.openSelected(),"browser"));
            obj.Handles.Tree = t;
            obj.buildContextMenu(t);

            % ---- row 6: details of the selection
            d = uigridlayout(g,[5 2],'RowHeight',{'1x',24,24,24,26},'ColumnWidth',{66,'1x'}, ...
                'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',4,'BackgroundColor',S.Panel);
            d.Layout.Row = 6;
            ta = uitextarea(d,'Value',{''},'Editable','off','Tag','AnalysisBrowserDetails', ...
                'FontSize',11,'Tooltip','What is selected in the tree.');
            ta.Layout.Row = 1; ta.Layout.Column = [1 2];
            l = uilabel(d,'Text','Timepoint','FontColor',S.Muted);
            l.Layout.Row = 2; l.Layout.Column = 1;
            tp = uidropdown(d,'Editable','on','Items',{},'Value','','Tag','AnalysisBrowserTimepoint', ...
                'Tooltip',['The visit the selected sessions belong to (on a day''s node: every ' ...
                'session of that day). Pick one or type a new one.']);
            tp.Layout.Row = 2; tp.Layout.Column = 2;
            tp.ValueChangedFcn = obj.viewWrap(@(src,~) obj.onTimepointEdited(src),"browser");
            l = uilabel(d,'Text','Group','FontColor',S.Muted);
            l.Layout.Row = 3; l.Layout.Column = 1;
            gp = uidropdown(d,'Editable','on','Items',{},'Value','','Tag','AnalysisBrowserGroup', ...
                'Tooltip',['The group of the selected animal -- a subject label, so every one ' ...
                'of its sessions shares it. Pick one or type a new one.']);
            gp.Layout.Row = 3; gp.Layout.Column = 2;
            gp.ValueChangedFcn = obj.viewWrap(@(src,~) obj.onGroupEdited(src),"browser");
            cb = uicheckbox(d,'Text','In study','Value',true,'Tag','AnalysisBrowserInStudy', ...
                'Tooltip','Use the selected sessions (or animal) in the study tables and the export.');
            cb.Layout.Row = 4; cb.Layout.Column = 1;
            cb.ValueChangedFcn = obj.viewWrap(@(src,~) obj.setInStudy(logical(src.Value)),"browser");
            cm = uibutton(d,'Text','Comment…','Tag','AnalysisBrowserComment', ...
                'Tooltip','Write a comment on the selected session (or animal).');
            mabr.ui.analysis.Style.setButtonIcon(cm,'notes','left');
            cm.Layout.Row = 4; cm.Layout.Column = 2;
            cm.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.comment(),"browser");
            br = uigridlayout(d,[1 3],'ColumnWidth',{'1x','1.6x','1x'},'Padding',[0 0 0 0], ...
                'ColumnSpacing',4,'BackgroundColor',S.Panel);
            br.Layout.Row = 5; br.Layout.Column = [1 2];
            op = uibutton(br,'Text','Open','Tag','AnalysisBrowserOpen', ...
                'Tooltip','Open the selected session (Enter or double-click).');
            mabr.ui.analysis.Style.setButtonIcon(op,'inspect','left');
            op.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.openSelected(),"browser");
            an = uibutton(br,'Text','Analyse…','Tag','AnalysisBrowserAnalyse', ...
                'Tooltip','Analyse the selected sessions in a batch…');
            mabr.ui.analysis.Style.setButtonIcon(an,'batch','left');
            an.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.analyseSelected(),"browser");
            pl = uibutton(br,'Text','Pool','Tag','AnalysisBrowserPool', ...
                'Tooltip',['Pool the sweeps of the selected sessions of one animal as one ' ...
                'session (asks first, listing what is pooled).']);
            mabr.ui.analysis.Style.setButtonIcon(pl,'pool','left');
            pl.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.poolSelected(),"browser");
            obj.Handles.Details = d;
            obj.Handles.DetailsText = ta;
            obj.Handles.Timepoint = tp;
            obj.Handles.Group = gp;
            obj.Handles.InStudy = cb;
            obj.Handles.Comment = cm;
            obj.Handles.Open = op;
            obj.Handles.Analyse = an;
            obj.Handles.Pool = pl;

            % ---- blind review: covers search, tree and details
            bl = uipanel(g,'BorderType','none','BackgroundColor',S.Panel,'Visible','off', ...
                'Tag','AnalysisBrowserBlind');
            bl.Layout.Row = [3 6];
            blg = uigridlayout(bl,[4 1],'RowHeight',{'1x','fit',30,'1x'},'Padding',[12 12 12 12], ...
                'RowSpacing',10,'BackgroundColor',S.Panel);
            blt = uilabel(blg,'Text','Blind review','HorizontalAlignment','center','WordWrap','on', ...
                'FontSize',14,'FontColor',S.Muted,'Tag','AnalysisBrowserBlindText');
            blt.Layout.Row = 2;
            ble = uibutton(blg,'Text','End review','Tag','AnalysisBrowserBlindEnd', ...
                'Tooltip','Leave the review queue; subjects, dates and labels are shown again.');
            ble.Layout.Row = 3;
            ble.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.endQueue(),"browser");
            obj.Handles.Blind = bl;
            obj.Handles.BlindText = blt;

            obj.NodeMap = containers.Map('KeyType','char','ValueType','any');
            obj.NodeText = containers.Map('KeyType','char','ValueType','any');
        end

        function onModelEvent(obj,name,data)
            % The browser is always showing, and routes by EVENT as well as
            % by word: opening another session must not rebuild the tree (it
            % only moves a status glyph and, maybe, the expanded subject).
            if ~obj.Built, return; end
            obj.ViewEvent = string(name);
            what = "all"; keys = strings(0,1);
            try
                what = data.What;
                keys = data.Keys;
            catch
            end
            try
                switch string(name)
                    case "RootChanged"
                        obj.refreshAll();
                    case "ProjectChanged"
                        if what == "status"
                            obj.refreshStatus(keys);
                        else
                            obj.refresh(what,keys);
                            if what ~= "all", obj.refreshBanner(); end
                        end
                    case "SessionChanged"
                        obj.onSessionChanged();
                    case "SettingsChanged"
                        % every status may have moved (new settings make
                        % sessions out of date)
                        obj.refreshStatus(strings(0,1));
                    case "ResultsChanged"
                        % (the open session; Keys may name another one, e.g.
                        % setSessionOverrides on a session that is not open)
                        obj.refreshStatus(unique([obj.Model.SessionKey; reshape(keys,[],1)]));
                    case "StatusChanged"
                        if what == "status"
                            obj.refreshStatus(strings(0,1));
                        elseif what == "save"
                            % (an autosave, after every edit: only what was
                            % saved can have moved -- the open session)
                            obj.refreshStatus(unique([obj.Model.SessionKey; reshape(keys,[],1)]));
                        elseif what == "queue"
                            obj.refreshBlind();
                        end
                    case "BusyChanged"
                        if what == "idle" && ~isempty(obj.PendingSearch) && isempty(obj.SearchTimer)
                            % a search typed while a job ran
                            obj.flush();
                        end
                        obj.refreshButtons();
                    otherwise
                        % SelectionChanged: nothing in the browser follows it
                end
            catch me
                mabr.log.vprintf(1,'Browser: %s handler failed: %s',string(name),me.message);
                mabr.log.vprintf(2,me);
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- whole refreshes -------------------------------------------------
        function refreshAll(obj)
            obj.refreshRoot();
            obj.rebuildTree();
            obj.refreshBlind();
            obj.refreshDetails();
        end

        function refreshRoot(obj)
            % The folder dropdown (recent folders, the open one first if it is
            % not among them) and the results link.
            m = obj.Model;
            cur = "";
            if ~isempty(m.Catalog), cur = string(m.Catalog.Root); end
            r = mabr.ui.analysis.Browser.recentRoots();
            if cur ~= ""
                r = [cur; r(~strcmpi(r,cur))];
            end
            if isempty(r)
                items = "(no folder open)";  data = "";
            else
                items = mabr.ui.analysis.Browser.tails(r);  data = r;
            end
            dd = obj.Handles.Root;
            v = '';
            if cur ~= "", v = char(cur); elseif ~isempty(data), v = char(data(1)); end
            try
                % (Items and ItemsData together: one alone would leave the
                % two different lengths for a moment)
                set(dd,'Items',cellstr(reshape(items,1,[])),'ItemsData',cellstr(reshape(data,1,[])), ...
                    'Value',v);
            catch me
                mabr.log.vprintf(2,'Browser: folder list not updated (%s).',me.message);
            end
            tip = 'The data folder that is open; pick a recent one to open it.';
            if cur ~= "", tip = char(cur + newline + "Pick a recent folder to open it."); end
            obj.put('root_tip',dd,'Tooltip',tip);
            txt = m.resultsPathText();
            if txt == "", txt = "Results: (no folder open)"; end
            obj.put('results_text',obj.Handles.ResultsPath,'Text',char(txt));
        end

        function refreshBanner(obj)
            % Row 4: the first nested results store neither imported nor
            % ignored ("Results found in SUBJ-ID-1254/MABR_Analysis (6 sessions).").
            [p,n] = obj.pendingStore();
            obj.Banner = struct('Path',p,'Count',n);
            show = p ~= "" && ~obj.Model.BlindReview;
            if show
                rel = p;
                try
                    root = string(obj.Model.Catalog.Root);
                    if startsWith(lower(replace(p,"\","/")),lower(replace(root,"\","/")))
                        rel = extractAfter(replace(p,"\","/"),strlength(root));
                        rel = regexprep(rel,'^/+','');
                    end
                catch
                end
                if n == 1, what = "1 session"; else, what = n + " sessions"; end
                obj.put('banner_text',obj.Handles.BannerText,'Text', ...
                    char("Results found in " + rel + " (" + what + ")."));
                obj.put('banner_tip',obj.Handles.BannerText,'Tooltip',char(p));
            end
            obj.put('banner_vis',obj.Handles.Banner,'Visible',matlab.lang.OnOffSwitchState(show));
            h = 0;
            if show, h = 60; end    % (two lines of text: a store's path is long)
            if ~isfield(obj.Written,'banner_h') || obj.Written.banner_h ~= h
                rh = obj.Handles.Grid.RowHeight;
                rh{4} = h;
                obj.Handles.Grid.RowHeight = rh;
                obj.Written.banner_h = h;
            end
        end

        function refreshBlind(obj)
            % Blind review covers who and when: the search, the tree, the
            % details.
            m = obj.Model;
            blind = logical(m.BlindReview);
            if blind
                txt = "Blind review";
                try
                    txt = "Blind review — item " + m.Queue.Position + " of " + numel(m.Queue.Keys);
                catch
                end
                obj.put('blind_text',obj.Handles.BlindText,'Text',char(txt));
            end
            on = matlab.lang.OnOffSwitchState(blind);
            off = matlab.lang.OnOffSwitchState(~blind);
            obj.put('blind_vis',obj.Handles.Blind,'Visible',on);
            obj.put('tree_vis',obj.Handles.Tree,'Visible',off);
            obj.put('search_vis',obj.Handles.SearchRow,'Visible',off);
            obj.put('details_vis',obj.Handles.Details,'Visible',off);
            obj.refreshBanner();          % (hidden while blind, back after)
        end

        % ---- the tree --------------------------------------------------------
        function rebuildTree(obj,force)
            % Bring the tree in line with the project view, through the
            % filter. The nodes are built again only when what is listed
            % changed (the ids or their nesting: another folder, a session
            % that came or went, a pool, a session moved to another day);
            % otherwise the texts that moved are rewritten in place, and the
            % selection and whatever the user expanded stay as they are. Then
            % the Model is told the order the sessions are listed in
            % (Ctrl+PgDn walks it).
            %   force  build the nodes even when nothing listed changed (a new
            %          filter: the subjects it leaves are expanded)
            if nargin < 2, force = false; end
            V = obj.Model.projectView();
            obj.View_ = V;
            P = obj.treePlan(V);
            same = ~force && numel(P.Ids) == numel(obj.TreeIds) && all(P.Ids == obj.TreeIds) && ...
                isequal(P.Parents,obj.TreeParents) && all(isvalid(obj.TreeNodes));
            if same
                obj.rewriteTexts(P.Texts,1:numel(P.Ids));
            else
                obj.buildNodes(P);
            end
            obj.VisibleKeys = P.Order;
            obj.Model.setBrowserOrder(P.Order);
            obj.LastSessionKey = obj.Model.SessionKey;
            obj.refreshButtons();
        end

        function P = treePlan(obj,V)
            % What the tree lists, parents before children: Ids
            % ("<Type>|<Key>", the form selectionIds uses), Parents (index
            % into Ids, 0 = the tree), Texts, Data (each node's NodeData),
            % Expand (the subjects to open when the nodes are built) and
            % Order (the session and pool keys, top to bottom).
            P = struct('Ids',strings(0,1),'Parents',zeros(0,1),'Texts',strings(0,1), ...
                'Data',{cell(0,1)},'Expand',false(0,1),'Order',strings(0,1));
            if isempty(V) || ~istable(V) || height(V) == 0, return; end
            n = height(V);
            keep = obj.filterMask(V);
            isPool = logical(obj.col(V,'IsPool',false(n,1)));
            subj = obj.col(V,'Subject',strings(n,1));
            subj(ismissing(subj) | subj == "") = mabr.analysis.Catalog.UnknownSubject;
            day = obj.dayCol(V);
            % (the columns a node's text needs, read once: indexing a wide
            % table row by row costs milliseconds a row, and a study lists
            % hundreds of sessions)
            C = obj.textColumns(V);
            tpAll = obj.col(V,'Timepoint',strings(n,1));
            open = obj.openSessionRow();
            % pools: under their visit when every member was that day, else
            % under the subject
            poolDay = NaT(n,1);
            for i = find(isPool & keep).'
                poolDay(i) = obj.poolVisit(V,i);
            end
            subjects = unique(subj(keep));
            known = subjects(subjects ~= mabr.analysis.Catalog.UnknownSubject);
            known = mabr.analysis.Stats.naturalSort(known);
            subjects = [reshape(known,[],1); subjects(subjects == mabr.analysis.Catalog.UnknownSubject)];
            current = obj.currentSubject(V,subj);
            opened = [obj.ExpandedSubjects; obj.selectedSubjects()];
            filtered = obj.FilterText ~= "" || obj.FilterShow ~= "All";
            starts = obj.col(V,'Start',NaT(n,1));
            for s = reshape(subjects,1,[])
                rowsS = find(keep & subj == s);
                nSess = sum(~isPool(rowsS));
                [P,si] = mabr.ui.analysis.Browser.planNode(P,"subject|" + s,0, ...
                    s + " (" + nSess + ")",struct('Type',"subject",'Key',s,'Subject',s,'Day',NaT), ...
                    filtered || s == current || any(opened == s));
                % visits: days ascending, unknown last
                sess = rowsS(~isPool(rowsS));
                dKeys = day(sess);
                ud = obj.uniqueDays(dKeys);
                for d = 1:numel(ud)
                    if isnat(ud(d))
                        rows = sess(isnat(dKeys));
                    else
                        rows = sess(dKeys == ud(d));
                    end
                    [~,o] = sort(obj.startNum(starts(rows)));
                    rows = rows(o);
                    tps = tpAll(rows);
                    vk = s + "|" + obj.dayKey(ud(d));
                    [P,vi] = mabr.ui.analysis.Browser.planNode(P,"visit|" + vk,si, ...
                        mabr.ui.analysis.Browser.visitText(ud(d),tps,numel(rows)), ...
                        struct('Type',"visit",'Key',vk,'Subject',s,'Day',ud(d)),false);
                    % its sessions, then the pools of that day
                    pr = rowsS(isPool(rowsS) & obj.sameDay(poolDay(rowsS),ud(d)));
                    for r = [reshape(rows,1,[]) reshape(pr,1,[])]
                        P = obj.planSession(P,vi,V,C,r,day(r),subj(r),open);
                    end
                end
                % pools spanning days
                pr = rowsS(isPool(rowsS) & isnat(poolDay(rowsS)));
                for r = reshape(pr,1,[])
                    P = obj.planSession(P,si,V,C,r,day(r),subj(r),open);
                end
            end
        end

        function P = planSession(obj,P,parent,V,C,r,day,subject,open)
            % One session (or pool) node of the plan (C: textColumns(V)).
            row = obj.nodeRow(V,r,mabr.ui.analysis.Browser.textRow(C,r),day,open);
            typ = "session";
            if row.IsPool, typ = "pool"; end
            key = string(row.Key);
            P = mabr.ui.analysis.Browser.planNode(P,typ + "|" + key,parent, ...
                mabr.ui.analysis.Browser.nodeText(row), ...
                struct('Type',typ,'Key',key,'Subject',subject,'Day',day),false);
            P.Order(end+1,1) = key;
        end

        function buildNodes(obj,P)
            % Delete every node and create the plan's, keeping the selection.
            t = obj.Handles.Tree;
            prevSel = obj.selectionIds();
            try
                delete(t.Children);
            catch
            end
            n = numel(P.Ids);
            nodes = gobjects(n,1);
            obj.NodeMap = containers.Map('KeyType','char','ValueType','any');
            obj.NodeText = containers.Map('KeyType','char','ValueType','any');
            for k = 1:n
                if P.Parents(k) == 0, parent = t; else, parent = nodes(P.Parents(k)); end
                nodes(k) = uitreenode(parent,'Text',char(P.Texts(k)),'NodeData',P.Data{k});
                obj.attachMenu(nodes(k));
                d = P.Data{k};
                if any(d.Type == ["session","pool"])
                    obj.NodeMap(char(d.Key)) = nodes(k);
                    obj.NodeText(char(d.Key)) = P.Texts(k);
                end
            end
            % (once their children exist: expand opens what is below)
            for k = reshape(find(P.Expand),1,[])
                try
                    expand(nodes(k),'all');
                catch
                end
            end
            obj.TreeIds = P.Ids;
            obj.TreeParents = P.Parents;
            obj.TreeNodes = nodes;
            obj.TreeTexts = P.Texts;
            obj.RebuildCount = obj.RebuildCount + 1;
            obj.restoreSelection(prevSel);
        end

        function rewriteTexts(obj,texts,idx)
            % Write TEXTS onto the built nodes IDX, only where they moved.
            for j = 1:numel(idx)
                k = idx(j);
                if obj.TreeTexts(k) == texts(j), continue; end
                h = obj.TreeNodes(k);
                if isvalid(h), h.Text = char(texts(j)); end
                obj.TreeTexts(k) = texts(j);
                if any(extractBefore(obj.TreeIds(k),"|") == ["session","pool"])
                    obj.NodeText(char(extractAfter(obj.TreeIds(k),"|"))) = texts(j);
                end
            end
        end

        function row = nodeRow(obj,V,r,row,day,open)
            % One project-view row as nodeText wants it -- with the open
            % session's status and review count taken from the Model, which
            % knows about edits the results file has not seen yet.
            %   row, day, open  (optional) the row as a struct, its day and
            %                   openSessionRow(), when the caller has them
            if nargin < 4 || isempty(row), row = table2struct(V(r,:)); end
            if nargin < 5, day = obj.dayCol(V(r,:)); end
            if nargin < 6, open = obj.openSessionRow(); end
            row.Day = day;
            if ~isfield(row,'IsPool'), row.IsPool = false; end
            row.IsPool = logical(row.IsPool);
            if row.IsPool
                row.PoolStarts = obj.poolStarts(V,r);
            end
            if ~isempty(open) && string(row.Key) == open.Key
                row.Status = open.Status;
                if isfinite(open.NumSeries)
                    row.Reviewed = open.Reviewed;
                    row.NumSeries = open.NumSeries;
                end
            end
        end

        function C = textColumns(obj,V)
            % The project-view columns nodeText reads, whole (textRow takes
            % one row of them).
            n = height(V);
            C = struct();
            C.Key       = string(V.Key);
            C.Name      = obj.col(V,'Name',strings(n,1));
            C.Status    = obj.col(V,'Status',repmat("none",n,1));
            C.Start     = obj.col(V,'Start',NaT(n,1));
            C.Summary   = obj.col(V,'Summary',strings(n,1));
            C.NumFiles  = obj.col(V,'NumFiles',NaN(n,1));
            C.AcqModes  = obj.col(V,'AcqModes',strings(n,1));
            C.ShortRuns = obj.col(V,'ShortRuns',zeros(n,1));
            C.TestMode  = obj.col(V,'TestMode',repmat("none",n,1));
            C.Reviewed  = obj.col(V,'Reviewed',zeros(n,1));
            C.NumSeries = obj.col(V,'NumSeries',zeros(n,1));
            C.IsPool    = obj.col(V,'IsPool',false(n,1));
        end

        function o = openSessionRow(obj)
            % The open session as the Model knows it ([] when none): Key,
            % Status, and Reviewed of NumSeries (NaN before an analysis).
            o = [];
            m = obj.Model;
            if m.SessionKey == "" || isempty(m.Session), return; end
            o = struct('Key',m.SessionKey,'Status',"none",'Reviewed',0,'NumSeries',NaN);
            switch m.Status.State
                case "current", o.Status = "current";
                case "stale",   o.Status = "stale";
                case "failed",  o.Status = "failed";
            end
            try
                T = m.Session.Thresholds;
                if istable(T) && height(T) > 0
                    d = string(T.Decision);
                    d(ismissing(d)) = "";
                    o.Reviewed = sum(d ~= "");
                    o.NumSeries = height(T);
                end
            catch
            end
        end

        function refreshStatus(obj,keys)
            % A status moved: rewrite the texts of KEYS' nodes in place (all
            % of them when empty) -- through the whole plan when the Show
            % filter depends on status, since a session may now belong or
            % not.
            if isempty(keys) || any(obj.FilterShow == ["Needs review","Not analysed","Out of date","Failed"])
                obj.rebuildTree();
                obj.refreshDetails();
                return
            end
            V = obj.Model.projectView();
            obj.View_ = V;
            if isempty(V) || ~istable(V) || height(V) == 0, return; end
            vk = string(V.Key);
            open = obj.openSessionRow();
            C = obj.textColumns(V);
            for k = unique(reshape(string(keys),1,[]))
                r = find(vk == k,1);
                i = find(obj.TreeIds == "session|" + k | obj.TreeIds == "pool|" + k,1);
                if isempty(r) || isempty(i), continue; end
                row = mabr.ui.analysis.Browser.textRow(C,r);
                txt = mabr.ui.analysis.Browser.nodeText(obj.nodeRow(V,r,row,obj.dayCol(V(r,:)),open));
                obj.rewriteTexts(txt,i);
            end
            obj.refreshDetails();
        end

        function onSessionChanged(obj)
            % Another session is open: its node and the last one's move
            % glyphs, its subject opens, and it is selected unless already.
            prev = obj.LastSessionKey;
            cur  = obj.Model.SessionKey;
            obj.LastSessionKey = cur;
            ks = [prev cur];
            ks = ks(ks ~= "");
            obj.refreshStatus(ks);
            obj.refreshBlind();
            if cur == "" || ~isKey(obj.NodeMap,char(cur)), return; end
            n = obj.NodeMap(char(cur));
            if ~isvalid(n), return; end
            sn = n.Parent;
            while ~isempty(sn) && isprop(sn,'NodeData') && isstruct(sn.NodeData) && ...
                    string(sn.NodeData.Type) ~= "subject"
                sn = sn.Parent;
            end
            try
                if ~isempty(sn) && isa(sn,'matlab.ui.container.TreeNode')
                    expand(sn,'all');
                    obj.rememberExpanded(string(sn.NodeData.Key),true);
                end
            catch
            end
            sel = obj.selectedNodes();
            if ~any(arrayfun(@(x) isequal(x,n),sel))
                obj.selectNodes(n);
                obj.refreshDetails();
            end
        end

        % ---- filter ----------------------------------------------------------
        function setFilter(obj,text,show)
            obj.FilterText = strtrim(text);
            obj.FilterShow = show;
            % (written every time: the user may have typed over the box)
            obj.Handles.Search.Value = char(text);
            obj.Handles.Show.Value = char(show);
            % (built afresh even when the same sessions pass: a filter opens
            % every subject it leaves, clearing it only the current one)
            obj.rebuildTree(true);
            obj.refreshDetails();
        end

        function keep = filterMask(obj,V)
            n = height(V);
            keep = true(n,1);
            q = lower(obj.FilterText);
            if q ~= ""
                txt = strings(n,1);
                for c = ["Subject","Name","Stimuli","Summary","Timepoint","Group","Key"]
                    v = obj.col(V,c,strings(n,1));
                    v(ismissing(v)) = "";
                    txt = txt + " " + lower(v);
                end
                keep = keep & contains(txt,q);
            end
            st = obj.col(V,'Status',repmat("none",n,1));
            switch obj.FilterShow
                case "Needs review"
                    rev = double(obj.col(V,'Reviewed',zeros(n,1)));
                    ns = double(obj.col(V,'NumSeries',zeros(n,1)));
                    keep = keep & ismember(st,["current","stale"]) & ns > 0 & rev < ns;
                case "Not analysed"
                    keep = keep & st == "none";
                case "Out of date"
                    keep = keep & st == "stale";
                case "Failed"
                    keep = keep & st == "failed";
                case "Not in study"
                    ins = logical(obj.col(V,'InStudy',true(n,1)));
                    sin = logical(obj.col(V,'SubjectInStudy',true(n,1)));
                    keep = keep & ~(ins & sin);
                case "Test Mode"
                    tm = obj.col(V,'TestMode',repmat("none",n,1));
                    keep = keep & tm ~= "none";
            end
        end

        function onSearchCommitted(obj,src)
            % Enter (or leaving the box): filter now.
            obj.PendingSearch = [];
            obj.stopSearchTimer();
            obj.setFilter(string(src.Value),obj.FilterShow);
        end

        function onSearchTyping(obj,e)
            % Every keystroke: wait for a pause (SearchDelay) before
            % rebuilding the tree. Without timers (tests), flush() applies it.
            v = "";
            try
                v = string(e.Value);
            catch
            end
            obj.PendingSearch = v;
            if ~obj.Model.AutoRefresh, return; end
            obj.stopSearchTimer();
            try
                obj.SearchTimer = timer('Tag','MABR_OfflineSearch','StartDelay',obj.SearchDelay, ...
                    'ExecutionMode','singleShot','BusyMode','drop', ...
                    'TimerFcn',@(~,~) obj.onSearchTimer());
                start(obj.SearchTimer);
            catch
                obj.flush();
            end
        end

        function onSearchTimer(obj)
            if ~isvalid(obj), return; end
            if obj.Model.Busy
                % a job is running: the search waits for BusyChanged(idle)
                obj.stopSearchTimer();
                return
            end
            try
                obj.flush();
            catch me
                mabr.log.vprintf(2,'Browser: search failed (%s).',me.message);
            end
        end

        function stopSearchTimer(obj)
            t = obj.SearchTimer;
            obj.SearchTimer = [];
            try
                if ~isempty(t) && isvalid(t)
                    stop(t);
                    delete(t);
                end
            catch
            end
        end

        function onShowPicked(obj,src)
            obj.setFilter(obj.FilterText,string(src.Value));
        end

        % ---- selection and details ------------------------------------------
        function onNodeExpanded(obj,e,tf)
            % A subject the user opened (or closed) stays so when the tree
            % is built again.
            try
                d = e.Node.NodeData;
                if string(d.Type) == "subject"
                    obj.rememberExpanded(string(d.Key),tf);
                end
            catch
            end
        end

        function rememberExpanded(obj,subject,tf)
            s = obj.ExpandedSubjects(obj.ExpandedSubjects ~= subject);
            if tf, s(end+1,1) = subject; end
            obj.ExpandedSubjects = s;
        end

        function onTreeSelection(obj)
            obj.refreshDetails();
        end

        function refreshDetails(obj)
            % The details text and the label controls for the selection.
            info = obj.selectedNodeInfo();
            ta = obj.Handles.DetailsText;
            lines = obj.detailLines(info);
            obj.put('details_text',ta,'Value',cellstr(lines));
            % timepoint: the levels in use, the selection's own value
            P = obj.Model.Project;
            levels = strings(1,0);
            groups = strings(1,0);
            if ~isempty(P)
                try
                    C = P.Columns;
                    lv = C.Levels(string(C.Name) == "Timepoint");
                    if iscell(lv) && ~isempty(lv), lv = lv{1}; end
                    levels = reshape(string(lv),1,[]);
                catch
                end
                try
                    gv = string(P.Subjects.Group);
                    gv = gv(~ismissing(gv) & gv ~= "");
                    groups = reshape(unique(gv,'stable'),1,[]);
                catch
                end
            end
            keys = info.Keys;
            tpVal = "";  grVal = "";  inStudy = true;
            V = obj.viewTable();
            if ~isempty(V) && ~isempty(keys)
                vk = string(V.Key);
                rows = find(ismember(vk,keys));
                if ~isempty(rows)
                    % (columns indexed, not V(rows,:): a wide table's rows
                    % are slow to take)
                    n = height(V);
                    tps = obj.col(V,'Timepoint',strings(n,1));
                    tps = tps(rows);
                    tps(ismissing(tps)) = "";
                    if all(tps == tps(1)), tpVal = tps(1); end
                    grs = obj.col(V,'Group',strings(n,1));
                    grs = grs(rows);
                    grs(ismissing(grs)) = "";
                    if all(grs == grs(1)), grVal = grs(1); end
                    if info.Type == "subject"
                        ins = obj.col(V,'SubjectInStudy',true(n,1));
                    else
                        ins = obj.col(V,'InStudy',true(n,1));
                    end
                    inStudy = all(logical(ins(rows)));
                end
            elseif info.Type == "subject" && ~isempty(P)
                try
                    U = P.Subjects;
                    r = find(string(U.Subject) == info.Subject,1);
                    if ~isempty(r)
                        grVal = string(U.Group(r));
                        inStudy = logical(U.InStudy(r));
                    end
                catch
                end
            end
            if ismissing(tpVal), tpVal = ""; end
            if ismissing(grVal), grVal = ""; end
            obj.put('tp_items',obj.Handles.Timepoint,'Items',cellstr(levels));
            obj.Handles.Timepoint.Value = char(tpVal);
            obj.put('gr_items',obj.Handles.Group,'Items',cellstr(groups));
            obj.Handles.Group.Value = char(grVal);
            obj.Handles.InStudy.Value = inStudy;
            obj.refreshButtons();
        end

        function lines = detailLines(obj,info)
            % What the details box says about the selection.
            V = obj.viewTable();
            switch info.Type
                case "none"
                    if isempty(obj.Model.Catalog)
                        lines = "Open a data folder to list its sessions.";
                    elseif isempty(V)
                        lines = "This folder holds no sessions.";
                    else
                        lines = ["Select a session to see its details.";
                            "Double-click (or Enter, or Open) opens it."];
                    end
                case "multiple"
                    n = numel(info.Keys);
                    if n == 1, w = "1 session"; else, w = n + " sessions"; end
                    lines = [info.Count + " items selected — " + w + "."; ...
                        "Analyse or label them together, or pool them (one subject)."];
                case "subject"
                    rows = obj.rowsOf(V,info.Keys);
                    d = obj.dayCol(V);
                    nd = numel(unique(obj.dayKey(d(rows))));
                    lines = info.Subject;
                    lines(end+1) = numel(info.Keys) + " session(s) on " + nd + " day(s)";
                    g = obj.subjectLabel(info.Subject,"Group");
                    if g ~= "", lines(end+1) = "Group: " + g; end
                    c = obj.subjectLabel(info.Subject,"Comment");
                    if c ~= "", lines(end+1) = "Comment: " + c; end
                case "visit"
                    rows = obj.rowsOf(V,info.Keys);
                    tps = obj.col(V,'Timepoint',strings(height(V),1));
                    tps = tps(rows);
                    lines = info.Subject + " · " + mabr.ui.analysis.Browser.visitText(info.Day,tps,numel(rows));
                    lines(end+1) = "Setting the timepoint here labels every session of this day.";
                otherwise
                    r = obj.rowsOf(V,info.Key);
                    if isempty(r)
                        lines = info.Key;
                        return
                    end
                    R = table2struct(V(r(1),:));
                    row = obj.nodeRow(V,r(1),R);
                    lines = string(R.Name);
                    % what a node's badges warn about comes first, where
                    % the box shows it without scrolling
                    if string(obj.fieldOr(R,'TestMode',"none")) ~= "none"
                        lines(end+1) = "TEST MODE: these samples are the stimulus, not a subject.";
                    end
                    if double(obj.fieldOr(R,'ShortRuns',0)) > 0
                        lines(end+1) = "⚠ " + obj.fieldOr(R,'ShortRuns',0) + " run(s) stopped early.";
                    end
                    if info.Type == "pool"
                        lines(end+1) = "Pool of " + numel(split(string(R.Members),"|")) + " sessions";
                    end
                    when = "";
                    try
                        if ~isnat(R.Start)
                            when = string(R.Start,'yyyy-MM-dd HH:mm');
                            if ~isnat(R.Stop), when = when + "–" + string(R.Stop,'HH:mm'); end
                        end
                    catch
                    end
                    lines(end+1) = strjoin([string(R.Subject) when(when ~= "")]," · ");
                    lines(end+1) = sprintf('%d files (%d included) · %d conditions · %d sweeps', ...
                        obj.num(R,'NumFiles'),obj.num(R,'NumIncluded'),obj.num(R,'NumConditions'), ...
                        obj.num(R,'NumSweeps'));
                    if string(R.Summary) ~= "", lines(end+1) = string(R.Summary); end
                    if isfield(R,'AcqModes') && string(R.AcqModes) ~= ""
                        lines(end+1) = "Acquisition: " + string(R.AcqModes);
                    end
                    u = string(obj.fieldOr(R,'Units',""));
                    lu = string(obj.fieldOr(R,'LevelUnit',""));
                    if u ~= "" || lu ~= "", lines(end+1) = "Units: " + strjoin([u lu]," · "); end
                    st = string(obj.fieldOr(R,'StatusText',""));
                    if string(R.Key) == obj.Model.SessionKey && ~isempty(obj.Model.Session)
                        st = obj.Model.Status.Text;
                    end
                    ns = obj.num(row,'NumSeries');
                    if ns > 0
                        st = st + " · reviewed " + obj.num(row,'Reviewed') + "/" + ns;
                    end
                    lines(end+1) = "Status: " + st;
                    lab = strings(1,0);
                    tp = string(obj.fieldOr(R,'Timepoint',""));
                    if tp ~= "" && ~ismissing(tp), lab(end+1) = "Timepoint " + tp; end
                    g = string(obj.fieldOr(R,'Group',""));
                    if g ~= "" && ~ismissing(g), lab(end+1) = "group " + g; end
                    if logical(obj.fieldOr(R,'InStudy',true)) && logical(obj.fieldOr(R,'SubjectInStudy',true))
                        lab(end+1) = "in study";
                    else
                        lab(end+1) = "not in study";
                    end
                    lines(end+1) = strjoin(lab," · ");
                    c = string(obj.fieldOr(R,'Comment',""));
                    if c ~= "" && ~ismissing(c), lines(end+1) = "Comment: " + c; end
                    if info.Type ~= "pool"
                        lines = [reshape(lines,1,[]), reshape(obj.noteLines(string(R.Key)),1,[])];
                    end
                    f = string(obj.fieldOr(R,'ResultsFile',""));
                    if f ~= "", lines(end+1) = "Results: " + f; end
            end
            lines = reshape(string(lines),[],1);
        end

        function lines = noteLines(obj,key)
            % The rig notes written during session KEY, for the details box:
            % how many, and the first two. Read through the catalog (from
            % the newest file that holds them, else the session's .notes
            % journal; read once and remembered by the catalog, never
            % written). "" lines when there are none.
            lines = strings(0,1);
            c = obj.Model.Catalog;
            if isempty(c), return; end
            try
                T = c.notes(key,'Scope',"session");
            catch
                return
            end
            n = height(T);
            if n == 0, return; end
            if n == 1, w = "1 note"; else, w = n + " notes"; end
            lines(end+1,1) = "Rig notes: " + w + " during this session";
            for k = 1:min(n,2)
                t = string(T.Text(k));
                if strlength(t) > 80, t = extractBefore(t,80) + "…"; end
                lines(end+1,1) = "  • " + t; %#ok<AGROW>
            end
            if n > 2, lines(end+1,1) = "  … (the Session tab lists them all)"; end
        end

        function refreshButtons(obj)
            % Enables of the details row from the selection (and Busy).
            info = obj.selectedNodeInfo();
            n = numel(info.Keys);
            busy = obj.Model.Busy;
            on = @(tf) matlab.lang.OnOffSwitchState(tf);
            obj.put('open_on',obj.Handles.Open,'Enable',on(n >= 1 && ~busy));
            if n == 1, lab = "Analyse 1 session…"; else, lab = "Analyse " + n + " sessions…"; end
            if n == 0, lab = "Analyse…"; end
            obj.put('analyse_text',obj.Handles.Analyse,'Text',char(lab));
            obj.put('analyse_on',obj.Handles.Analyse,'Enable',on(n >= 1 && ~busy));
            obj.put('pool_on',obj.Handles.Pool,'Enable',on(numel(obj.poolableKeys()) >= 2 && ~busy));
            hasSel = info.Type ~= "none";
            obj.put('tp_on',obj.Handles.Timepoint,'Enable',on(hasSel && info.Type ~= "subject"));
            obj.put('gr_on',obj.Handles.Group,'Enable',on(hasSel));
            obj.put('in_on',obj.Handles.InStudy,'Enable',on(hasSel));
            obj.put('cm_on',obj.Handles.Comment,'Enable',on(hasSel));
        end

        % ---- label controls ---------------------------------------------------
        function onTimepointEdited(obj,src)
            obj.setTimepoint(string(src.Value));
        end

        function onGroupEdited(obj,src)
            obj.setGroup(string(src.Value));
        end

        function t = currentComment(obj,info)
            t = "";
            V = obj.viewTable();
            switch info.Type
                case {"session","pool"}
                    r = obj.rowsOf(V,info.Key);
                    if ~isempty(r), t = string(obj.fieldOr(table2struct(V(r(1),:)),'Comment',"")); end
                case "subject"
                    t = obj.subjectLabel(info.Subject,"Comment");
            end
            if ismissing(t), t = ""; end
        end

        % ---- pooling ------------------------------------------------------------
        function keys = poolableKeys(obj)
            % The selected sessions (no pools) -- poolable when they are of
            % one subject.
            keys = obj.selectedKeys();
            keys = keys(~startsWith(keys,"pool:"));
            V = obj.viewTable();
            if numel(keys) < 2 || isempty(V), return; end
            rows = obj.rowsOf(V,keys);
            s = obj.col(V,'Subject',strings(height(V),1));
            s = unique(s(rows));
            if numel(s) > 1, keys = strings(0,1); end
        end

        function msg = poolMessage(obj,keys)
            % The question before pooling: which sessions, and per condition
            % how many sweeps each brings (from the catalog's files).
            names = keys;
            V = obj.viewTable();
            for i = 1:numel(keys)
                r = obj.rowsOf(V,keys(i));
                if ~isempty(r), names(i) = string(V.Name(r(1))); end
            end
            lines = "Pool the sweeps of " + numel(keys) + " sessions (" + strjoin(names,", ") + ...
                ") as one session? Every condition they share is averaged over all their sweeps; " + ...
                "the sessions themselves leave the study until the pool is dissolved.";
            try
                F = obj.Model.Catalog.Files;
                F = F(ismember(string(F.SessionKey),keys) & logical(F.Ok),:);
                cond = string(F.Stimulus) + " " + string(F.ParamText);
                mode = string(F.AcqMode);
                cond(mode ~= "" & ~ismissing(mode)) = cond(mode ~= "" & ~ismissing(mode)) + ...
                    " (" + mode(mode ~= "" & ~ismissing(mode)) + ")";
                [u,~,j] = unique(strtrim(cond),'stable');
                rowsTxt = strings(0,1);
                for c = 1:numel(u)
                    parts = strings(1,0);
                    for i = 1:numel(keys)
                        k = j == c & string(F.SessionKey) == keys(i);
                        if any(k), parts(end+1) = string(sum(double(F.NumSweeps(k)))); end %#ok<AGROW>
                    end
                    rowsTxt(end+1,1) = "  " + u(c) + ": " + strjoin(parts," + ") + " sweeps"; %#ok<AGROW>
                end
                if ~isempty(rowsTxt)
                    nShow = min(numel(rowsTxt),12);
                    rowsTxt = rowsTxt(1:nShow);
                    if numel(u) > nShow, rowsTxt(end+1) = "  and " + (numel(u) - nShow) + " more"; end
                    lines = lines + newline + newline + "Pooled per condition:" + newline + ...
                        strjoin(rowsTxt,newline);
                end
            catch me
                mabr.log.vprintf(2,'Browser: pool listing not available (%s).',me.message);
            end
            msg = lines;
        end

        % ---- context menu --------------------------------------------------------
        function buildContextMenu(obj,t)
            fig = ancestor(t,'figure');
            cm = uicontextmenu(fig,'Tag','AnalysisBrowserMenu');
            cm.ContextMenuOpeningFcn = obj.viewWrap(@(~,e) obj.onMenuOpening(e),"browser");
            it = struct();
            it.Open = uimenu(cm,'Text','Open','Tag','AnalysisBrowserMenuOpen', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.openSelected(),"browser"));
            % (the raw files rather than the results: the way back to a
            % session whose results file cannot be read, or to start over)
            it.OpenRaw = uimenu(cm,'Text','Open from raw files','Tag','AnalysisBrowserMenuOpenRaw', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.openSelected("raw"),"browser"));
            it.Analyse = uimenu(cm,'Text','Analyse…','Tag','AnalysisBrowserMenuAnalyse', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.analyseSelected(),"browser"));
            it.Pool = uimenu(cm,'Text','Pool sweeps of selected sessions…','Tag','AnalysisBrowserMenuPool', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.poolSelected(),"browser"));
            it.Timepoint = uimenu(cm,'Text','Set timepoint','Separator','on', ...
                'Tag','AnalysisBrowserMenuTimepoint');
            it.Group = uimenu(cm,'Text','Set group','Tag','AnalysisBrowserMenuGroup');
            it.InStudy = uimenu(cm,'Text','In study','Tag','AnalysisBrowserMenuInStudy', ...
                'MenuSelectedFcn',obj.viewWrap(@(src,~) obj.setInStudy(~strcmp(src.Checked,'on')),"browser"));
            it.Explorer = uimenu(cm,'Text','Show in Explorer','Separator','on', ...
                'Tag','AnalysisBrowserMenuExplorer', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.showSelectedFolder(),"browser"));
            it.CopyPath = uimenu(cm,'Text','Copy path','Tag','AnalysisBrowserMenuCopyPath', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.copySelectedPath(),"browser"));
            obj.Handles.Menu = cm;
            obj.Handles.MenuItems = it;
            try
                t.ContextMenu = cm;
            catch
            end
        end

        function attachMenu(obj,node)
            % Every node shares the tree's menu (right-clicking a node then
            % says which one it was).
            try
                node.ContextMenu = obj.Handles.Menu;
            catch
            end
        end

        function onMenuOpening(obj,e)
            % A right-click on a node that is not selected selects it first,
            % so the menu always acts on what is highlighted.
            node = [];
            try
                c = e.ContextObject;
                if isa(c,'matlab.ui.container.TreeNode'), node = c; end
            catch
            end
            if isempty(node)
                try
                    c = e.InteractionInformation.Node;
                    if isa(c,'matlab.ui.container.TreeNode'), node = c; end
                catch
                end
            end
            if ~isempty(node) && isvalid(node)
                sel = obj.selectedNodes();
                if ~any(arrayfun(@(x) isequal(x,node),sel))
                    obj.selectNodes(node);
                    obj.refreshDetails();
                end
            end
            obj.fillMenu();
        end

        function fillMenu(obj)
            % The submenus and labels for the selection at hand.
            it = obj.Handles.MenuItems;
            info = obj.selectedNodeInfo();
            n = numel(info.Keys);
            if n == 1, lab = "Analyse 1 session…"; else, lab = "Analyse " + n + " sessions…"; end
            it.Analyse.Text = char(lab);
            on = @(tf) matlab.lang.OnOffSwitchState(tf);
            it.Open.Enable = on(n >= 1);
            it.OpenRaw.Enable = on(n >= 1);
            it.Analyse.Enable = on(n >= 1);
            it.Pool.Enable = on(numel(obj.poolableKeys()) >= 2);
            it.InStudy.Checked = on(logical(obj.Handles.InStudy.Value));
            it.InStudy.Enable = on(info.Type ~= "none");
            it.Explorer.Enable = on(info.Type ~= "none");
            it.CopyPath.Enable = on(info.Type ~= "none");
            % Set timepoint / Set group: the values in use, then New…
            delete(it.Timepoint.Children);
            delete(it.Group.Children);
            for v = reshape(string(obj.Handles.Timepoint.Items),1,[])
                vv = v;
                uimenu(it.Timepoint,'Text',char(vv), ...
                    'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.setTimepoint(vv),"browser"));
            end
            uimenu(it.Timepoint,'Text','New…','Separator',on(~isempty(obj.Handles.Timepoint.Items)), ...
                'Tag','AnalysisBrowserMenuTimepointNew', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.newLabel("Timepoint"),"browser"));
            for v = reshape(string(obj.Handles.Group.Items),1,[])
                vv = v;
                uimenu(it.Group,'Text',char(vv), ...
                    'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.setGroup(vv),"browser"));
            end
            uimenu(it.Group,'Text','New…','Separator',on(~isempty(obj.Handles.Group.Items)), ...
                'Tag','AnalysisBrowserMenuGroupNew', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.newLabel("Group"),"browser"));
            it.Timepoint.Enable = on(info.Type ~= "none" && info.Type ~= "subject");
            it.Group.Enable = on(info.Type ~= "none");
        end

        function newLabel(obj,name)
            v = obj.Model.PromptFcn("New " + lower(name) + ":",name,"");
            if isempty(v), return; end
            v = strtrim(string(v));
            if v == "", return; end
            if name == "Timepoint"
                obj.setTimepoint(v);
            else
                obj.setGroup(v);
            end
        end

        function paths = selectedPaths(obj)
            paths = strings(0,1);
            V = obj.viewTable();
            keys = obj.selectedKeys();
            if isempty(V) || isempty(keys), return; end
            info = obj.selectedNodeInfo();
            rows = obj.rowsOf(V,keys);
            paths = obj.col(V(rows,:),'Path',strings(numel(rows),1));
            if info.Type == "subject" && ~isempty(paths)
                % the animal's folder: the one above its sessions
                p = fileparts(char(paths(1)));
                paths = string(p);
            end
        end

        function showSelectedFolder(obj)
            p = obj.selectedPaths();
            if isempty(p), return; end
            obj.showFolder(p(1));
        end

        function copySelectedPath(obj)
            p = obj.selectedPaths();
            if isempty(p), return; end
            txt = strjoin(p,newline);
            try
                clipboard('copy',char(txt));
            catch
            end
            obj.status("Copied " + numel(p) + " path(s).",0);
        end

        function showFolder(obj,p)
            if ~isempty(obj.OpenFolderFcn)
                obj.OpenFolderFcn(p);
                return
            end
            try
                if ispc
                    winopen(char(p));
                else
                    system(['open "' char(p) '"']);
                end
            catch me
                obj.status("Could not show " + p + ": " + string(me.message),1);
            end
        end

        % ---- root ---------------------------------------------------------------
        function onRootPicked(obj,src)
            p = string(src.Value);
            m = obj.Model;
            cur = "";
            if ~isempty(m.Catalog), cur = string(m.Catalog.Root); end
            if p == "" || strcmpi(p,cur), return; end
            if ~isfolder(p)
                obj.status("That folder is not there any more: " + p,1);
                obj.refreshRoot();
                return
            end
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.openRoot(p);            % (remembers it among the recent ones)
            else
                m.openRoot(p);
            end
        end

        function onBrowse(obj)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.runCommand("file.open");
                return
            end
            m = obj.Model;
            start = "";
            if ~isempty(m.Catalog), start = string(m.Catalog.Root); end
            p = string(m.PickFolderFcn(start,"Open a data folder"));
            if isempty(p) || ismissing(p) || p == "", return; end
            m.openRoot(p);
        end

        % ---- helpers ------------------------------------------------------------
        function runWrapped(obj,fcn)
            f = obj.viewWrap(@(~,~) fcn(),"browser");
            f([],[]);
        end

        function status(obj,text,level)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus(text,level);
            else
                mabr.log.vprintf(2,'Browser: %s',char(text));
            end
        end

        function V = viewTable(obj)
            V = obj.View_;
            if isempty(V)
                V = obj.Model.projectView();
                obj.View_ = V;
            end
            if ~istable(V) || height(V) == 0, V = table(); end
        end

        function nodes = selectedNodes(obj)
            nodes = [];
            try
                nodes = obj.Handles.Tree.SelectedNodes;
            catch
            end
            if isempty(nodes), nodes = []; return; end
            nodes = nodes(arrayfun(@isvalid,nodes));
        end

        function selectNodes(obj,nodes)
            t = obj.Handles.Tree;
            try
                if isempty(nodes)
                    t.SelectedNodes = [];
                else
                    t.SelectedNodes = nodes;
                end
            catch me
                mabr.log.vprintf(2,'Browser: selection not set (%s).',me.message);
            end
        end

        function nodes = nodesFor(obj,keys)
            nodes = [];
            for k = reshape(string(keys),1,[])
                if isKey(obj.NodeMap,char(k))
                    n = obj.NodeMap(char(k));
                    if isvalid(n), nodes = [nodes; n]; end %#ok<AGROW>
                end
            end
        end

        function ids = selectionIds(obj)
            % The selection as (Type|Key) strings, to put back after a rebuild.
            ids = strings(0,1);
            nodes = obj.selectedNodes();
            for k = 1:numel(nodes)
                d = nodes(k).NodeData;
                ids(end+1,1) = string(d.Type) + "|" + string(d.Key); %#ok<AGROW>
            end
        end

        function restoreSelection(obj,ids)
            % Select the built nodes whose ids (selectionIds' form) are IDS.
            if isempty(ids), return; end
            nodes = obj.TreeNodes(ismember(obj.TreeIds,ids));
            if isempty(nodes), nodes = []; end
            obj.selectNodes(nodes);
        end

        function keys = keysUnder(obj,node)
            % The session and pool keys at or below a node, in tree order.
            keys = strings(0,1);
            d = node.NodeData;
            if any(string(d.Type) == ["session","pool"])
                keys = string(d.Key);
                return
            end
            ch = node.Children;
            for k = 1:numel(ch)
                keys = [keys; obj.keysUnder(ch(k))]; %#ok<AGROW>
            end
        end

        function s = selectedSubjects(obj)
            s = strings(0,1);
            nodes = obj.selectedNodes();
            for k = 1:numel(nodes)
                d = nodes(k).NodeData;
                v = string(d.Subject);
                if v ~= "" && v ~= mabr.analysis.Catalog.UnknownSubject
                    s(end+1,1) = v; %#ok<AGROW>
                end
            end
            s = unique(s,'stable');
        end

        function v = subjectLabel(obj,subject,name)
            v = "";
            try
                U = obj.Model.Project.Subjects;
                r = find(string(U.Subject) == subject,1);
                if ~isempty(r), v = string(U.(name)(r)); end
            catch
            end
            if ismissing(v), v = ""; end
        end

        function s = currentSubject(obj,V,subj)
            % The subject to keep open: the open session's, else the
            % selection's, else the first.
            s = "";
            k = obj.Model.SessionKey;
            if k ~= ""
                r = find(string(V.Key) == k,1);
                if ~isempty(r), s = subj(r); return; end
            end
            nodes = obj.selectedNodes();
            if ~isempty(nodes)
                s = string(nodes(1).NodeData.Subject);
                return
            end
            u = mabr.analysis.Stats.naturalSort(unique(subj));
            if ~isempty(u), s = u(1); end
        end

        function [p,n] = pendingStore(obj)
            % The first nested store neither imported nor ignored.
            p = ""; n = 0;
            m = obj.Model;
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
                        n = double(N.NumResults(i));
                        return
                    end
                end
            catch
            end
        end

        function t = poolStarts(obj,V,r)
            % "HH:mm" of each member of the pool in row r, earliest first.
            m = split(string(V.Members(r)),"|");
            vk = string(V.Key);
            st = obj.col(V,'Start',NaT(height(V),1));
            when = NaT(0,1);
            for i = 1:numel(m)
                j = find(vk == m(i),1);
                if ~isempty(j) && ~isnat(st(j)), when(end+1,1) = st(j); end %#ok<AGROW>
            end
            when = sort(when);
            t = strings(numel(when),1);
            for i = 1:numel(when), t(i) = string(when(i),'HH:mm'); end
        end

        function d = poolVisit(obj,V,r)
            % The day of a pool when all its members share it, else NaT.
            d = NaT;
            m = split(string(V.Members(r)),"|");
            [tf,loc] = ismember(m,string(V.Key));
            if ~all(tf), return; end
            days = obj.dayCol(V(loc,:));
            days = days(~isnat(days));
            if isempty(days), return; end
            if all(days == days(1)), d = days(1); end
        end

        function d = dayCol(obj,V)
            % Day as a datetime column (start of day), NaT where unknown.
            n = height(V);
            d = NaT(n,1);
            try
                v = V.Day;
                if isdatetime(v)
                    d = dateshift(v,'start','day');
                else
                    st = obj.col(V,'Start',NaT(n,1));
                    d = dateshift(st,'start','day');
                end
            catch
            end
            d.Format = 'yyyy-MM-dd';
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function [P,i] = planNode(P,id,parent,text,data,expand)
            % Append one node to a tree plan (treePlan); I is its index.
            i = numel(P.Ids) + 1;
            P.Ids(i,1) = id;
            P.Parents(i,1) = parent;
            P.Texts(i,1) = text;
            P.Data{i,1} = data;
            P.Expand(i,1) = expand;
        end

        function v = field(s,name,default)
            if isstruct(s) && isfield(s,name)
                v = s.(name);
                if isempty(v), v = default; end
                if iscell(v) && isscalar(v), v = v{1}; end
            else
                v = default;
            end
        end

        function row = textRow(C,r)
            % Row R of textColumns, as the struct nodeText takes.
            row = struct();
            for f = reshape(string(fieldnames(C)),1,[])
                v = C.(f);
                if iscell(v), row.(f) = v{r}; else, row.(f) = v(r); end
            end
        end

        function v = fieldOr(s,name,default)
            v = mabr.ui.analysis.Browser.field(s,name,default);
            if (isstring(v) || ischar(v)) && any(ismissing(string(v))), v = default; end
        end

        function n = num(s,name)
            n = double(mabr.ui.analysis.Browser.field(s,name,NaN));
            if ~isscalar(n), n = NaN; end
        end

        function v = col(V,name,default)
            % A column of V, or DEFAULT when it has none.
            if ismember(char(name),V.Properties.VariableNames)
                v = V.(char(name));
                if iscellstr(v), v = string(v); end %#ok<ISCLSTR>
            else
                v = default;
            end
        end

        function rows = rowsOf(V,keys)
            rows = zeros(0,1);
            if isempty(V) || height(V) == 0, return; end
            rows = find(ismember(string(V.Key),string(keys)));
        end

        function [ud,j] = uniqueDays(d)
            % Days ascending, the unknown (NaT) last, as one entry.
            known = unique(d(~isnat(d)));
            ud = sort(known);
            if any(isnat(d)), ud(end+1,1) = NaT; end
            j = [];
        end

        function tf = sameDay(d,day)
            if isnat(day)
                tf = false(size(d));
            else
                tf = ~isnat(d) & d == day;
            end
        end

        function k = dayKey(d)
            k = strings(numel(d),1);
            for i = 1:numel(d)
                if isnat(d(i)), k(i) = "unknown"; else, k(i) = string(d(i),'yyyy-MM-dd'); end
            end
        end

        function x = startNum(t)
            x = inf(numel(t),1);
            ok = ~isnat(t);
            x(ok) = posixtime(t(ok));
        end

        function r = recentRoots()
            % pref OfflineRecentRoots (READ only; the app writes it).
            r = strings(0,1);
            try
                if ispref('MABR','OfflineRecentRoots')
                    r = reshape(string(getpref('MABR','OfflineRecentRoots')),[],1);
                    r = r(~ismissing(r) & r ~= "");
                end
            catch
                r = strings(0,1);
            end
        end

        function t = tails(paths)
            % Folder names for the dropdown, widened by the parent folder
            % where two would read alike (items must be distinct).
            n = numel(paths);
            t = strings(n,1);
            for i = 1:n
                [~,nm] = fileparts(char(paths(i)));
                t(i) = string(nm);
            end
            [~,~,j] = unique(lower(t));
            dup = accumarray(j,1) > 1;
            for i = find(dup(j)).'
                [pp,nm] = fileparts(char(paths(i)));
                [~,par] = fileparts(pp);
                t(i) = string(par) + "/" + string(nm);
            end
            % still alike: the whole path
            [~,~,j] = unique(lower(t));
            cnt = accumarray(j,1);
            t(cnt(j) > 1) = paths(cnt(j) > 1);
        end
    end
end
