classdef SessionView < mabr.ui.analysis.View
% mabr.ui.analysis.SessionView  The Session tab: one session at a glance, and what went into it.
%
%   The first thing to look at when a session opens, and the place its
%   inputs are decided:
%
%     top left      the CONDITION MATRIX: one row per level (loudest at the
%                   top), one column per series (the Grid's order), each
%                   cell coloured by a measure picked above it -- clean
%                   sweeps, % rejected, -log10 p, split-half r or SNR -- with
%                   its value written in and ● (detected) / ○ (not) in the
%                   corner (■ □ when an override decided it). The final
%                   threshold is a green step line between the rows. A click
%                   selects that condition (every tab follows); a double-
%                   click opens it on the Series tab.
%     bottom left   the FILES: every .abr of the session, grouped by run --
%                   whether it is used, when it ran, what it presented, its
%                   sweeps and the rig's own rejections, its layout,
%                   interval, units, Test Mode, and why it is left out when
%                   it is. Ticking Use on or off is STAGED: nothing is re-
%                   segmented until Apply ("3 changes — Apply re-segments the
%                   affected conditions (≈5 s)"), and Discard forgets it. The
%                   buttons below stage whole selections (all files, only
%                   the conventional or the interleaved runs, no short
%                   runs); the table's context menu does the same for one run
%                   group.
%     top right     the rig NOTES taken while the session was recorded (or
%                   the whole notebook), each once.
%     bottom right  the MESSAGES the analysis left (warnings first), a
%                   SUMMARY of how the session was processed -- per condition
%                   group, the FIR and windowed operators with their -6 dB
%                   corners, acquisition modes and pooling, units, the
%                   settings profile and hash, the data fingerprint, where
%                   its results are -- and the per-session OVERRIDES: the
%                   recorder's full scale, an amplifier gain, a system time
%                   offset and a sound conduction delay (empty = none: the
%                   settings' own). A unit override makes the session out of
%                   date from segmentation; a time offset or delay changes
%                   only the REPORTED latencies (the waves are searched in
%                   the recording's own time, so no pick moves) and the
%                   peaks step is re-run at once to record the new offset.
%
%   Everything goes through mabr.ui.analysis.Model (selectCondition,
%   stageFileUse/applyFileUse/discardFileUse/useOnly, setSessionOverrides),
%   so every change is undoable and every other tab follows.
%
%   The look (MatrixMetric, NotesScope) persists in pref
%   OfflineAnalysisSession, written ONLY from this tab's own controls.
%
%   Public methods (tests call these):
%     selectCell(seriesKey,level,Open=false)   what a click (Open: a double-
%                                              click) on the matrix does
%     setMetric(name), setNotesScope(name)     the dropdowns
%     applyOverrides()                         the overrides row's Apply
%     filesContextAction(action,row)           "useGroup" | "excludeGroup" |
%                                              "copy" on a Files row
%     M = matrixData()                         what the matrix shows
%   and the static v = SessionView.metricValues(C,metric): one measure per
%   row of a Conditions table (NaN where there is none yet).
%
%   See also mabr.ui.analysis.View, mabr.ui.analysis.Browser,
%   mabr.ui.analysis.Model, mabr.analysis.Session
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        MetricNames = ["Clean sweeps","% rejected","−log10 p","Split-half r","SNR (dB)"]
        ScopeNames  = ["During this session","All notes"]
        FileColumns = ["Use","Run group","File","Start","Stimulus","Params","Sweeps", ...
            "Rig rej.","Layout","ISI (ms)","Units","Level unit","Test","Note"]
        EmptyText   = "Open a session from the browser (double-click, Enter, or Open)."
    end

    properties (SetAccess = private)
        FileIds  (:,1) string = strings(0,1)   % the Files table's rows, as FileIds
        RunGroups (:,1) string = strings(0,1)  % ... and their run groups
        ShownUse (:,1) logical = false(0,1)    % the Use column as on screen
        Matrix = struct('SeriesKeys',strings(1,0),'Levels',zeros(0,1), ...
            'CondKeys',strings(0,0),'Values',zeros(0,0),'Text',strings(0,0), ...
            'Marks',strings(0,0),'FinalY',zeros(1,0))
        MenuRow (1,1) double = NaN             % the Files row a context menu opened on
    end

    properties (Access = private)
        MatrixShape (1,1) string = ""          % what the cell texts were built for
        ColumnLabels (1,:) string = strings(1,0)   % the matrix's x tick labels
        SessionShown (1,1) string = ""         % the session the Files table was built for
    end

    % =====================================================================
    methods
        function obj = SessionView(parent,model,host)
            % SessionView(parent,model,host): the Session tab, built into
            % PARENT (its uitab) over MODEL.
            if nargin < 3, host = []; end
            obj@mabr.ui.analysis.View(parent,model,host);
        end

        function build(obj)
            % View's contract: the controls, built once (see the class help).
            S = mabr.ui.analysis.Style;
            look = obj.look();
            g = uigridlayout(obj.Parent,[2 2],'RowHeight',{'1x','1x'},'ColumnWidth',{'1.3x','1x'}, ...
                'Padding',[6 6 6 6],'RowSpacing',6,'ColumnSpacing',8,'BackgroundColor',S.Panel);
            obj.Handles.Grid = g;

            % ---- top left: the condition matrix
            tl = uigridlayout(g,[2 1],'RowHeight',{24,'1x'},'Padding',[0 0 0 0],'RowSpacing',2, ...
                'BackgroundColor',S.Panel);
            tl.Layout.Row = 1; tl.Layout.Column = 1;
            st = uigridlayout(tl,[1 3],'ColumnWidth',{'fit',140,'1x'},'Padding',[0 0 0 0], ...
                'ColumnSpacing',6,'BackgroundColor',S.Panel);
            uilabel(st,'Text','Colour by','FontColor',S.Muted);
            md = uidropdown(st,'Items',cellstr(obj.MetricNames),'Value',char(look.MatrixMetric), ...
                'Tag','AnalysisSessionMatrixMetric', ...
                'Tooltip','What colours the cells (and the number written in each).');
            md.ValueChangedFcn = obj.viewWrap(@(src,~) obj.onMetricPicked(src));
            % (short enough for the strip at the window's smallest size; the
            % tooltip says it in full)
            hint = 'Click: select · double-click: Series · arrows move · F1 keys';
            full = ['Click a cell to select it · double-click it (or press Return) to open ' ...
                'it in Series · ↑↓ another level · ←→ another series · F1 every key'];
            hl = uilabel(st,'Text',hint,'FontColor',S.Muted, ...
                'Tag','AnalysisSessionMatrixHint','Tooltip',full);
            hl.Layout.Column = 3;
            p = uipanel(tl,'BorderType','none','BackgroundColor',[1 1 1], ...
                'Tag','AnalysisSessionMatrixPanel','AutoResizeChildren','off');
            p.Layout.Row = 2;
            % (margins in pixels -- the level labels and the series names
            % need the same room however big the panel is -- re-applied
            % whenever the panel changes size)
            p.SizeChangedFcn = @(~,~) obj.relayoutMatrix();
            ax = axes(p,'Units','normalized','Position',[0.10 0.20 0.87 0.72], ...
                'YDir','reverse','Box','on','Layer','top','TickLength',[0 0], ...
                'Color',[0.97 0.97 0.97],'FontSize',9,'XColor',S.Ink,'YColor',S.Ink, ...
                'Tag','AnalysisSessionMatrixAxes','Visible','off');
            % (invisible until a session is drawn: with none open there is
            % no plot here to export, and Export Figure… must say so)
            mabr.ui.hideAxesToolbar(ax);
            try
                disableDefaultInteractivity(ax);
            catch
            end
            hold(ax,'on');
            im = image(ax,'XData',1,'YData',1,'CData',NaN,'CDataMapping','scaled', ...
                'AlphaData',0,'Tag','AnalysisSessionMatrixImage');
            colormap(ax,mabr.ui.analysis.SessionView.ramp());
            fin = line(ax,NaN,NaN,'Color',S.FinalGreen,'LineWidth',2.5, ...
                'Tag','AnalysisSessionMatrixFinal','HitTest','off','PickableParts','none', ...
                'DisplayName','Final threshold');
            sel = line(ax,NaN,NaN,'Color',S.Accent,'LineWidth',2.2, ...
                'Tag','AnalysisSessionMatrixSelection','HitTest','off','PickableParts','none', ...
                'DisplayName','Selected condition');
            click = obj.viewWrap(@(~,e) obj.onMatrixClick(e));
            im.ButtonDownFcn = click;
            ax.ButtonDownFcn = click;
            cm = uicontextmenu(ancestor(p,'figure'),'Tag','AnalysisSessionMatrixMenu');
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            ax.ContextMenu = cm;
            im.ContextMenu = cm;
            obj.Handles.Metric = md;
            obj.Handles.MatrixPanel = p;
            obj.Handles.Axes = ax;
            obj.Handles.Image = im;
            obj.Handles.Final = fin;
            obj.Handles.Outline = sel;
            obj.Handles.CellText = gobjects(0,0);
            obj.Handles.CellMark = gobjects(0,0);

            % ---- bottom left: the files
            bl = uigridlayout(g,[3 1],'RowHeight',{'1x',26,26},'Padding',[0 0 0 0],'RowSpacing',4, ...
                'BackgroundColor',S.Panel);
            bl.Layout.Row = 2; bl.Layout.Column = 1;
            tb = uitable(bl,'Tag','AnalysisSessionFiles','RowName',{}, ...
                'ColumnName',cellstr(obj.FileColumns), ...
                'ColumnEditable',[true false(1,numel(obj.FileColumns) - 1)], ...
                'ColumnWidth',{36,150,190,64,72,150,52,54,70,56,64,64,40,'auto'}, ...
                'Tooltip',['The session''s files, grouped by run. Tick Use off to leave a file out ' ...
                '(staged until Apply).']);
            mabr.ui.analysis.Compat.setSortable(tb,false);
            tb.CellEditCallback = obj.viewWrap(@(src,e) obj.onFileEdited(src,e));
            fm = uicontextmenu(ancestor(p,'figure'),'Tag','AnalysisSessionFilesMenu');
            fm.ContextMenuOpeningFcn = obj.viewWrap(@(~,e) obj.onFilesMenuOpening(e));
            uimenu(fm,'Text','Use only this run group','Tag','AnalysisSessionFilesUseGroup', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.filesContextAction("useGroup",obj.MenuRow)));
            uimenu(fm,'Text','Exclude this run group','Tag','AnalysisSessionFilesExcludeGroup', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.filesContextAction("excludeGroup",obj.MenuRow)));
            uimenu(fm,'Text','Copy table','Separator','on','Tag','AnalysisSessionFilesCopy', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.filesContextAction("copy",obj.MenuRow)));
            tb.ContextMenu = fm;
            pr = uigridlayout(bl,[1 3],'ColumnWidth',{'1x',90,90},'Padding',[0 0 0 0], ...
                'ColumnSpacing',4,'BackgroundColor',S.Panel);
            pr.Layout.Row = 2;
            pl = uilabel(pr,'Text','','FontColor',S.AccentText,'Tag','AnalysisSessionPending', ...
                'Tooltip','File changes waiting to be applied.');
            pl.Layout.Column = 1;
            ap = uibutton(pr,'Text','Apply','Tag','AnalysisSessionApplyFiles','Enable','off', ...
                'Tooltip','Re-segment the conditions the staged file changes touch (Ctrl+Z undoes it).');
            mabr.ui.analysis.Style.setButtonIcon(ap,'accept','left');
            ap.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.applyFileUse());
            dc = uibutton(pr,'Text','Discard','Tag','AnalysisSessionDiscardFiles','Enable','off', ...
                'Tooltip','Forget the staged file changes.');
            mabr.ui.analysis.Style.setButtonIcon(dc,'undo','left');
            dc.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.discardFileUse());
            br = uigridlayout(bl,[1 4],'ColumnWidth',{'1x','1x','1x','1x'},'Padding',[0 0 0 0], ...
                'ColumnSpacing',4,'BackgroundColor',S.Panel);
            br.Layout.Row = 3;
            b1 = uibutton(br,'Text','Use all','Tag','AnalysisSessionUseAll', ...
                'Tooltip','Stage every file of the session for use.');
            b1.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.useOnly("all"));
            b2 = uibutton(br,'Text','Only conventional','Tag','AnalysisSessionOnlyConventional', ...
                'Tooltip','Stage only the conventional (one condition per file) runs for use.');
            b2.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.useOnly("conventional"));
            b3 = uibutton(br,'Text','Only interleaved','Tag','AnalysisSessionOnlyInterleaved', ...
                'Tooltip','Stage only the interleaved (intermixed) runs for use.');
            b3.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.useOnly("interleaved"));
            b4 = uibutton(br,'Text','Skip short runs','Tag','AnalysisSessionSkipShort', ...
                'Tooltip','Skip files with < 50% of the median sweep count (runs stopped early).');
            b4.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.Model.useOnly("skipShort"));
            obj.Handles.Files = tb;
            obj.Handles.FilesMenu = fm;
            obj.Handles.Pending = pl;
            obj.Handles.ApplyFiles = ap;
            obj.Handles.DiscardFiles = dc;
            obj.Handles.Bulk = [b1 b2 b3 b4];

            % ---- top right: the notes
            tr = uigridlayout(g,[2 1],'RowHeight',{24,'1x'},'Padding',[0 0 0 0],'RowSpacing',2, ...
                'BackgroundColor',S.Panel);
            tr.Layout.Row = 1; tr.Layout.Column = 2;
            ns = uigridlayout(tr,[1 2],'ColumnWidth',{'1x',150},'Padding',[0 0 0 0], ...
                'ColumnSpacing',6,'BackgroundColor',S.Panel);
            uilabel(ns,'Text','Rig notes','FontWeight','bold','FontColor',S.Ink);
            sd = uidropdown(ns,'Items',cellstr(obj.ScopeNames),'Value',char(look.NotesScope), ...
                'Tag','AnalysisSessionNotesScope', ...
                'Tooltip','Only the notes written while this session was recorded, or the whole notebook.');
            sd.ValueChangedFcn = obj.viewWrap(@(src,~) obj.onScopePicked(src));
            nt = uitextarea(tr,'Value',{''},'Editable','off','Tag','AnalysisSessionNotes', ...
                'Tooltip','The rig notebook (each note once), as the files and .notes journals hold it.');
            nt.Layout.Row = 2;
            obj.Handles.NotesScope = sd;
            obj.Handles.Notes = nt;

            % ---- bottom right: messages, summary, overrides
            rr = uigridlayout(g,[3 1],'RowHeight',{'1x','1x',54},'Padding',[0 0 0 0],'RowSpacing',4, ...
                'BackgroundColor',S.Panel);
            rr.Layout.Row = 2; rr.Layout.Column = 2;
            mt = uitable(rr,'Tag','AnalysisSessionMessages','RowName',{}, ...
                'ColumnName',{'Time','Level','Step','Text'},'ColumnWidth',{62,60,70,'auto'}, ...
                'Tooltip','What the analysis noted and warned about, warnings first.');
            mabr.ui.analysis.Compat.setSortable(mt,false);
            mm = uicontextmenu(ancestor(p,'figure'),'Tag','AnalysisSessionMessagesMenu');
            uimenu(mm,'Text','Copy table','Tag','AnalysisSessionMessagesCopy', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) mabr.ui.analysis.FigureExport.copyTable(mt)));
            mt.ContextMenu = mm;
            sm = uitextarea(rr,'Value',{''},'Editable','off','Tag','AnalysisSessionSummary', ...
                'FontSize',11,'Tooltip','How this session was processed, and where its results are.');
            sm.Layout.Row = 2;
            og = uigridlayout(rr,[2 5],'RowHeight',{24,24},'ColumnWidth',{'fit','1x','fit','1x',70}, ...
                'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',4,'BackgroundColor',S.Panel);
            og.Layout.Row = 3;
            f = struct();
            f.FullScale = obj.overrideField(og,1,1,'Full scale (V)','AnalysisSessionFullScale', ...
                ['Volts at the recorder input the converter reads as 1.0, for this session only; ' ...
                'empty = what its files recorded.']);
            f.Gain = obj.overrideField(og,1,3,'Gain (V/V)','AnalysisSessionGain', ...
                'The amplifier gain ahead of the recorder, for this session only; empty = the files''.');
            f.TimeOffset = obj.overrideField(og,2,1,'Time offset (ms)','AnalysisSessionTimeOffset', ...
                ['A fixed system offset taken off every latency of this session; empty = the ' ...
                'settings'' TimeOffset.']);
            f.ConductionDelay = obj.overrideField(og,2,3,'Delay (ms)','AnalysisSessionConductionDelay', ...
                ['The sound conduction delay of this session (speaker to ear), ms; latencies are ' ...
                'then re sound arrival. Empty = the settings'' delay.']);
            ab = uibutton(og,'Text','Apply','Tag','AnalysisSessionApplyOverrides', ...
                'Tooltip',['Store these overrides for this session in the project: a unit override ' ...
                'makes it out of date from segmentation; a time offset or delay changes only the ' ...
                'reported latencies (no pick moves; the peaks are re-picked at once to record it).']);
            ab.Layout.Row = [1 2]; ab.Layout.Column = 5;
            ab.ButtonPushedFcn = obj.viewWrap(@(~,~) obj.applyOverrides());
            obj.Handles.Messages = mt;
            obj.Handles.Summary = sm;
            obj.Handles.Overrides = f;
            obj.Handles.ApplyOverrides = ab;
        end

        function relayoutNow(obj)
            % (View.layoutSoon: on showing the tab, and a moment after the
            % matrix is drawn) the matrix laid out for its panel's size now
            % -- a session drawn while the tab was being shown measured a
            % size the panel no longer has.
            obj.relayoutMatrix();
        end

        function refresh(obj,what,keys) %#ok<INUSD>
            % Redraw what WHAT says moved (ChangeData's word); words this
            % tab does not draw return at once.
            what = string(what);
            if isempty(obj.Model.Session)
                if any(what == ["all","status"])
                    obj.showEmpty(obj.EmptyText,[]);
                    obj.put('ax_vis',obj.Handles.Axes,'Visible','off');
                    obj.SessionShown = "";
                end
                return
            end
            switch what
                case "all"
                    obj.hideEmpty();
                    obj.renderAll();
                case {"rejection","detection","thresholds","curation","measures","peaks"}
                    obj.renderGuarded(@() obj.renderMatrix());
                    obj.renderMessages();
                    if what == "rejection", obj.renderFiles(); end
                case "files"
                    obj.refreshFileUse();
                case {"condition","series","level"}
                    obj.renderSelection();
                case "status"
                    obj.renderSummary();
                    obj.renderOverrides();
                    obj.refreshFileUse();
                case {"busy","idle"}
                    obj.refreshEnables();
                otherwise
                    % ("message", "save", "queue", "wave", "sweeps", "labels",
                    % ...: nothing this tab draws)
            end
        end

        % ---- public API ------------------------------------------------------
        function selectCell(obj,seriesKey,level,opts)
            % A click on the matrix cell of SERIESKEY at LEVEL (NaN: the
            % series' only row): select that condition; Open (a double-
            % click) also shows it on the Series tab.
            arguments
                obj
                seriesKey (1,1) string
                level (1,1) double = NaN
                opts.Open (1,1) logical = false
            end
            M = obj.Matrix;
            c = find(M.SeriesKeys == seriesKey,1);
            if isempty(c)
                error('mabr:ui:SessionView:noCell','No column "%s" in the matrix.',seriesKey);
            end
            if isnan(level)
                r = find(M.CondKeys(:,c) ~= "",1);
            else
                r = find(abs(M.Levels - level) < 1e-9,1);
            end
            if isempty(r) || M.CondKeys(r,c) == ""
                error('mabr:ui:SessionView:noCell','%s was not recorded at %g.',seriesKey,level);
            end
            obj.cellClicked(r,c,opts.Open);
        end

        function setMetric(obj,name)
            % Colour the matrix by NAME (one of MetricNames).
            arguments
                obj
                name (1,1) string
            end
            k = find(obj.MetricNames == name,1);
            if isempty(k)
                error('mabr:ui:SessionView:badMetric','"%s" is not a matrix measure (%s).', ...
                    name,strjoin(obj.MetricNames,", "));
            end
            obj.ViewLook.MatrixMetric = obj.MetricNames(k);
            obj.put('metric_value',obj.Handles.Metric,'Value',char(obj.MetricNames(k)));
            if ~isempty(obj.Model.Session)
                obj.renderGuarded(@() obj.renderMatrix());
            end
        end

        function setNotesScope(obj,name)
            % Show the notes written during this session, or "All notes".
            arguments
                obj
                name (1,1) string
            end
            k = find(obj.ScopeNames == name,1);
            if isempty(k)
                error('mabr:ui:SessionView:badScope','"%s" is not a notes scope.',name);
            end
            obj.ViewLook.NotesScope = obj.ScopeNames(k);
            obj.put('scope_value',obj.Handles.NotesScope,'Value',char(obj.ScopeNames(k)));
            if ~isempty(obj.Model.Session), obj.renderNotes(); end
        end

        function applyOverrides(obj)
            % The overrides row's Apply: the four fields (empty = none) to
            % Model.setSessionOverrides.
            m = obj.Model;
            if m.SessionKey == ""
                obj.status("Open a session first.",0);
                return
            end
            f = obj.Handles.Overrides;
            names = ["InputFullScale","AmplifierGain","TimeOffset","ConductionDelay"];
            fields = ["FullScale","Gain","TimeOffset","ConductionDelay"];
            ov = struct();
            for i = 1:numel(names)
                txt = strtrim(string(f.(fields(i)).Value));
                if txt == ""
                    v = NaN;
                else
                    v = str2double(txt);
                    if ~isfinite(v)
                        obj.status(sprintf('"%s" is not a number (%s).',txt,names(i)),2);
                        return
                    end
                    if any(names(i) == ["InputFullScale","AmplifierGain"]) && v <= 0
                        obj.status(names(i) + " must be above zero (or empty for none).",2);
                        return
                    end
                    if names(i) == "ConductionDelay" && v < 0
                        obj.status("A conduction delay cannot be negative (empty for none).",2);
                        return
                    end
                end
                ov.(names(i)) = v;
            end
            m.setSessionOverrides(m.SessionKey,ov);
        end

        function filesContextAction(obj,action,row)
            % What the Files table's context menu does on ROW: "useGroup"
            % (use only that row's run group), "excludeGroup" (leave it
            % out), "copy" (the table as tab-separated text).
            arguments
                obj
                action (1,1) string {mustBeMember(action,["useGroup","excludeGroup","copy"])}
                row (1,1) double = NaN
            end
            if action == "copy"
                mabr.ui.analysis.FigureExport.copyTable(obj.Handles.Files);
                obj.status("Files table copied.",0);
                return
            end
            if ~isfinite(row) || row < 1 || row > numel(obj.FileIds)
                obj.status("Right-click a file of the run group first.",0);
                return
            end
            grp = obj.RunGroups(row);
            if grp == ""
                obj.status("That file belongs to no run group (it could not be read).",1);
                return
            end
            if action == "useGroup"
                obj.Model.useOnly(grp);
            else
                ids = obj.FileIds(obj.RunGroups == grp);
                obj.Model.stageFileUse(ids,false);
            end
        end

        function M = matrixData(obj)
            % What the matrix shows: SeriesKeys (columns), Levels (rows,
            % loudest first), CondKeys ("" where not recorded), Values, Text,
            % Marks (the detection glyphs) and FinalY (the step line's row
            % boundary per column, NaN without one).
            M = obj.Matrix;
        end
    end

    % =====================================================================
    methods (Static)
        function d = factoryDefaults()
            % The tab's look as shipped (pref OfflineAnalysisSession).
            d = struct('MatrixMetric',"Clean sweeps",'NotesScope',"During this session");
        end

        function d = loadDefaults()
            % The look the user left (forgiving: anything odd -> shipped).
            f = mabr.ui.analysis.SessionView.factoryDefaults();
            d = mabr.ui.analysis.View.loadLook("OfflineAnalysisSession",f);
            if ~any(mabr.ui.analysis.SessionView.MetricNames == string(d.MatrixMetric))
                d.MatrixMetric = f.MatrixMetric;
            end
            if ~any(mabr.ui.analysis.SessionView.ScopeNames == string(d.NotesScope))
                d.NotesScope = f.NotesScope;
            end
        end

        function saveDefaults(d)
            % Store a look (ONLY from the tab's own controls).
            mabr.ui.analysis.View.saveLook("OfflineAnalysisSession",d);
        end

        function v = metricValues(C,metric)
            % What the matrix colours by: one value per row of a Conditions
            % table C for METRIC (one of MetricNames), NaN where the session
            % has not got that far (no such column yet, or a condition the
            % step left without a value).
            arguments
                C table
                metric (1,1) string
            end
            n = height(C);
            v = NaN(n,1);
            has = @(c) ismember(c,C.Properties.VariableNames);
            switch metric
                case "Clean sweeps"
                    if has('nClean'), v = double(C.nClean); end
                case "% rejected"
                    if has('nRejected') && has('nSweeps')
                        ns = double(C.nSweeps);
                        v = 100*double(C.nRejected)./ns;
                        v(ns == 0) = NaN;
                    end
                case "−log10 p"
                    if has('p')
                        p = double(C.p);
                        % (max ignores NaN: without the mask a condition with
                        % no p -- too few sweeps to test -- read 307.7 and
                        % washed every other cell out to white)
                        v = -log10(max(p,realmin));
                        v(isnan(p)) = NaN;
                    end
                case "Split-half r"
                    if has('SplitR'), v = double(C.SplitR); end
                case "SNR (dB)"
                    if has('SNR'), v = double(C.SNR); end
            end
            v = reshape(v,[],1);
        end
    end

    % =====================================================================
    methods (Access = private)
        function d = look(obj)
            d = mabr.ui.analysis.SessionView.factoryDefaults();
            L = obj.ViewLook;
            if isstruct(L)
                if isfield(L,'MatrixMetric') && any(obj.MetricNames == string(L.MatrixMetric))
                    d.MatrixMetric = string(L.MatrixMetric);
                end
                if isfield(L,'NotesScope') && any(obj.ScopeNames == string(L.NotesScope))
                    d.NotesScope = string(L.NotesScope);
                end
            end
        end

        function sg = loudnessSign(obj,S,lp)
            % +1 when a higher level is louder, -1 on an attenuation axis:
            % the settings' LevelDirection (the session's own when analysed),
            % "auto" meaning a level parameter named like "Attenuation" --
            % the rule mabr.analysis.Session applies.
            sg = 1;
            st = [];
            try
                st = S.Settings;
            catch
            end
            if isempty(st), st = obj.Model.Settings; end
            d = "auto";
            try
                d = string(st.LevelDirection);
            catch
            end
            if d == "descending" || (d == "auto" && contains(lower(string(lp)),"attenuation"))
                sg = -1;
            end
        end

        function h = overrideField(~,g,r,c,label,tag,tip)
            l = uilabel(g,'Text',label,'FontColor',mabr.ui.analysis.Style.Muted);
            l.Layout.Row = r; l.Layout.Column = c;
            % (a grey "none" inside the empty box where the release has the
            % hint -- Compat; the tooltip says what empty means everywhere)
            h = uieditfield(g,'text','Value','','Tag',tag,'Tooltip',[tip ' Empty = none.']);
            mabr.ui.analysis.Compat.setPlaceholder(h,'none');
            h.Layout.Row = r; h.Layout.Column = c + 1;
        end

        function status(obj,text,level)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus(text,level);
            else
                mabr.log.vprintf(2,'Session tab: %s',char(text));
            end
        end

        function t = mask(obj,t)
            % TEXT with the session's names taken out -- its folders, their
            % paths, its key and its subject (however spelled) -- for blind
            % review.
            t = string(t);
            S = obj.Model.Session;
            if isempty(S), return; end
            tok = strings(0,1);
            try
                tok = [string(S.Name); string(S.Subject); string(S.SubjectRaw); string(S.Key); ...
                    reshape(string(S.Paths),[],1); reshape(string(S.FolderKeys),[],1)];
                for p = reshape(string(S.Paths),1,[])
                    [~,nm] = fileparts(char(p));
                    tok(end+1,1) = string(nm); %#ok<AGROW>
                end
            catch
            end
            tok = unique(tok(~ismissing(tok) & strlength(tok) >= 3));
            [~,o] = sort(strlength(tok),'descend');
            for k = reshape(o,1,[])
                t = replace(t,tok(k),"…");
            end
        end

        % ---- the whole tab -------------------------------------------------
        function renderAll(obj)
            L = obj.look();
            obj.put('metric_value',obj.Handles.Metric,'Value',char(L.MatrixMetric));
            obj.put('scope_value',obj.Handles.NotesScope,'Value',char(L.NotesScope));
            obj.renderGuarded(@() obj.renderMatrix());
            obj.renderFiles();
            obj.renderNotes();
            obj.renderMessages();
            obj.renderSummary();
            % (the override boxes are typed into, so what put last wrote is
            % not what they show: another session -- or the re-analysis an
            % Apply ends in -- writes the stored values whatever they hold,
            % or a number typed and never applied would stay on screen for
            % the next session and be applied to it)
            obj.forgetWritten('ov_');
            obj.renderOverrides();
            obj.refreshEnables();
        end

        % ---- the matrix -------------------------------------------------------
        function renderMatrix(obj)
            m = obj.Model;
            S = m.Session;
            if isempty(S), return; end
            ax = obj.Handles.Axes;
            obj.put('ax_vis',ax,'Visible','on');
            metric = obj.look().MatrixMetric;
            C = S.Conditions;
            ck = strings(0,1);
            if istable(C) && height(C) > 0, ck = string(C.Key); end
            lp = m.levelParam();
            % columns (series, the Grid's order) and the rows' levels
            sks = reshape(m.seriesKeys(),1,[]);
            colConds = cell(1,numel(sks));
            colLevels = cell(1,numel(sks));
            for j = 1:numel(sks)
                cks = reshape(string(m.seriesConditions(sks(j))),[],1);
                lv = NaN(numel(cks),1);
                for i = 1:numel(cks)
                    r = find(ck == cks(i),1);
                    if ~isempty(r) && lp ~= "" && ismember(char(lp),C.Properties.VariableNames)
                        lv(i) = double(C.(lp)(r));
                    end
                end
                colConds{j} = cks;
                colLevels{j} = lv;
            end
            sg = obj.loudnessSign(S,lp);
            if isempty(sks)
                % no level parameter: one row, a column per condition
                sks = reshape(ck,1,[]);
                colConds = num2cell(sks);
                colLevels = repmat({NaN},1,numel(sks));
                levels = NaN;
            else
                % loudest at the top (the smallest attenuation, on an
                % attenuation axis)
                lvAll = vertcat(colLevels{:});
                levels = unique(lvAll(isfinite(lvAll)));
                [~,o] = sort(sg*levels,'descend');
                levels = levels(o);
                if any(~isfinite(lvAll)), levels(end+1,1) = NaN; end
            end
            nL = numel(levels);  nS = numel(sks);
            CK = strings(nL,nS);
            for j = 1:nS
                for i = 1:numel(colConds{j})
                    lv = colLevels{j}(i);
                    if isnan(lv)
                        r = find(isnan(levels),1);
                    else
                        r = find(abs(levels - lv) < 1e-9,1);
                    end
                    if ~isempty(r), CK(r,j) = colConds{j}(i); end
                end
            end
            [vals,txt,marks] = mabr.ui.analysis.SessionView.cellValues(S,CK,metric);
            M = struct('SeriesKeys',sks,'Levels',levels,'CondKeys',CK,'Values',vals, ...
                'Text',txt,'Marks',marks,'FinalY',NaN(1,nS));
            M.FinalY = obj.finalRows(S,M,sg);
            obj.Matrix = M;

            % the image
            im = obj.Handles.Image;
            have = CK ~= "";
            cmap = mabr.ui.analysis.SessionView.ramp();
            lim = mabr.ui.analysis.SessionView.limitsFor(vals(have),metric);
            if nL == 0 || nS == 0
                set(im,'XData',1,'YData',1,'CData',NaN,'AlphaData',0);
            else
                cd = vals;
                cd(~have) = NaN;
                % a recorded cell without a value is light grey, not blank
                a = double(have);
                set(im,'XData',[1 nS],'YData',[1 nL],'CData',cd,'AlphaData',a);
            end
            mabr.ui.analysis.Compat.setColorLimits(ax,lim);
            obj.put('ax_xlim',ax,'XLim',[0.5 max(nS,1) + 0.5]);
            obj.put('ax_ylim',ax,'YLim',[0.5 max(nL,1) + 0.5]);
            obj.put('ax_xtick',ax,'XTick',1:nS);
            % (the acquisition mode as the browser's badge: "Tone 8 kHz ⧉" for
            % the interleaved run -- the full words do not fit under a cell)
            % (without a level parameter every column is one condition --
            % a series of one -- named by what varies, "8 kHz", through its
            % CONDITION key: conditionLabel does not know series keys)
            xl = strings(1,nS);
            bySeries = lp ~= "";
            for j = 1:nS
                ck1 = CK(find(CK(:,j) ~= "",1),j);
                if ~bySeries && ~isempty(ck1)
                    xl(j) = m.conditionLabel(ck1);
                else
                    xl(j) = m.seriesLabel(sks(j));
                end
            end
            xl = replace(xl," · conventional","");
            xl = replace(xl," · interleaved"," " + mabr.ui.analysis.Style.BadgeInterleaved);
            obj.ColumnLabels = xl;
            obj.put('ax_xticklabel',ax,'XTickLabel',cellstr(xl));
            obj.put('ax_ytick',ax,'YTick',1:nL);
            yl = strings(1,nL);
            for i = 1:nL
                if isnan(levels(i)), yl(i) = "–"; else, yl(i) = string(sprintf('%g',levels(i))); end
            end
            obj.put('ax_yticklabel',ax,'YTickLabel',cellstr(yl));
            ylab = "Level";
            if lp ~= "", ylab = lp; end
            try
                if lp ~= "" && ~mabr.ui.analysis.SeriesView.isSoundLevel(lp,S)
                    % a Level parameter that is not a sound level (Frequency,
                    % say) in its own unit, never the session's dB
                    u = mabr.ui.analysis.SeriesView.levelUnitOf(lp,S);
                    if u ~= "", ylab = ylab + " (" + u + ")"; end
                elseif S.LevelUnit ~= "" && lp ~= ""
                    ylab = ylab + " (" + S.LevelUnit + ")";
                end
            catch
            end
            obj.put('ax_ylabel',ax.YLabel,'String',char(ylab));
            obj.put('ax_title',ax.Title,'String',char(metric));

            % texts: rebuilt only when the shape changes, rewritten in place
            shape = string(nL) + "x" + string(nS) + "|" + strjoin(reshape(CK,1,[]),",");
            if shape ~= obj.MatrixShape
                delete(obj.Handles.CellText(isgraphics(obj.Handles.CellText)));
                delete(obj.Handles.CellMark(isgraphics(obj.Handles.CellMark)));
                T = gobjects(nL,nS);  K = gobjects(nL,nS);
                fs = 9;
                if nS > 10 || nL > 12, fs = 8; end
                for i = 1:nL
                    for j = 1:nS
                        if ~have(i,j), continue; end
                        T(i,j) = text(ax,j,i,'','HorizontalAlignment','center', ...
                            'VerticalAlignment','middle','FontSize',fs,'HitTest','off', ...
                            'PickableParts','none','Tag','AnalysisSessionMatrixText');
                        % (larger than the value: ● and ○ are drawn at about
                        % half the size of a digit, and at the value's size
                        % they were specks no one could tell apart)
                        K(i,j) = text(ax,j + 0.44,i - 0.42,'','HorizontalAlignment','right', ...
                            'VerticalAlignment','top','FontSize',fs + 4,'HitTest','off', ...
                            'PickableParts','none','Tag','AnalysisSessionMatrixMark');
                    end
                end
                obj.Handles.CellText = T;
                obj.Handles.CellMark = K;
                obj.MatrixShape = shape;
                obj.forgetWritten('cell_');
                % (the texts were drawn after the lines: lift the lines back
                % above them)
                try
                    uistack(obj.Handles.Final,'top');
                    uistack(obj.Handles.Outline,'top');
                catch
                end
            end
            T = obj.Handles.CellText;  K = obj.Handles.CellMark;
            for i = 1:nL
                for j = 1:nS
                    if ~have(i,j) || ~isgraphics(T(i,j)), continue; end
                    col = mabr.ui.analysis.SessionView.cellColor(vals(i,j),lim,cmap);
                    ink = mabr.ui.analysis.SessionView.inkOn(col);
                    id = sprintf('cell_%d_%d',i,j);
                    obj.put([id '_t'],T(i,j),'String',char(txt(i,j)));
                    obj.put([id '_c'],T(i,j),'Color',ink);
                    obj.put([id '_m'],K(i,j),'String',char(marks(i,j)));
                    obj.put([id '_mc'],K(i,j),'Color',ink);
                end
            end

            % the final threshold, a staircase between the rows (kept just
            % inside the axes when it runs along the top or bottom edge, where
            % the box would hide it)
            X = zeros(1,0);  Y = zeros(1,0);
            for j = 1:nS
                y = M.FinalY(j);
                if isfinite(y), y = min(max(y,0.56),nL + 0.44); end
                if isfinite(y)
                    X = [X j-0.5 j+0.5]; %#ok<AGROW>
                    Y = [Y y y]; %#ok<AGROW>
                else
                    X = [X NaN]; %#ok<AGROW>
                    Y = [Y NaN]; %#ok<AGROW>
                end
            end
            if isempty(X), X = NaN; Y = NaN; end
            set(obj.Handles.Final,'XData',X,'YData',Y);
            obj.renderSelection();
            % (now, and once more when the window has drawn it: a session
            % opened as the tab is shown is drawn before its layout settles)
            obj.layoutSoon();
        end

        function y = finalRows(obj,S,M,sg)
            % Where the step line crosses each column: the boundary below
            % the quietest row at least as loud as the curated threshold
            % (above the top row when nothing responded, below the bottom
            % when everything did). SG is the loudness sign (+1, or -1 on an
            % attenuation axis): rows run loudest first either way.
            if nargin < 4, sg = 1; end
            nS = numel(M.SeriesKeys);
            y = NaN(1,nS);
            T = [];
            try
                T = S.Thresholds;
            catch
            end
            if ~istable(T) || height(T) == 0 || ~ismember('Key',T.Properties.VariableNames), return; end
            tk = string(T.Key);
            for j = 1:nS
                r = find(tk == M.SeriesKeys(j),1);
                if isempty(r), continue; end
                rows = find(M.CondKeys(:,j) ~= "" & isfinite(M.Levels));
                if isempty(rows), continue; end
                c = obj.rowText(T,r,'FinalCensored');
                F = obj.rowNum(T,r,'Final');
                % censored: what it MEANS on this axis (the censoring
                % describes the numbers -- "right" is no response on a dB
                % SPL axis, all respond on an attenuation one), placed at
                % the row of its BOUND (a level the method left out may lie
                % beyond it), else at the loudest / quietest row
                if any(c == ["right","left"])
                    noResp = (c == "right" && sg > 0) || (c == "left" && sg < 0);
                    if c == "right", b = obj.rowNum(T,r,'FinalLo'); else, b = obj.rowNum(T,r,'FinalHi'); end
                    kb = [];
                    if isfinite(b), kb = rows(find(abs(M.Levels(rows) - b) < 1e-9,1)); end
                    if noResp
                        if isempty(kb), y(j) = min(rows) - 0.5; else, y(j) = kb - 0.5; end
                    else
                        if isempty(kb), y(j) = max(rows) + 0.5; else, y(j) = kb + 0.5; end
                    end
                    continue
                end
                switch c
                    case "interval"
                        % (the louder bound: the quietest level that
                        % responded)
                        b = [obj.rowNum(T,r,'FinalLo') obj.rowNum(T,r,'FinalHi')];
                        b = b(isfinite(b));
                        if isempty(b)
                            t = F;
                        else
                            t = sg*max(sg*b);
                        end
                    otherwise
                        t = F;
                end
                if ~isfinite(t), continue; end
                k = find(sg*M.Levels(rows) >= sg*t - 1e-9,1,'last');
                if isempty(k)
                    y(j) = min(rows) - 0.5;
                else
                    y(j) = rows(k) + 0.5;
                end
            end
        end

        function relayoutMatrix(obj)
            % Place the matrix axes with margins in pixels: room for the
            % level labels on the left, the title above, the series names
            % below (turned 25 degrees once they no longer fit flat).
            try
                ax = obj.Handles.Axes;
                pos = getpixelposition(obj.Handles.MatrixPanel);
                W = pos(3);  H = pos(4);
                if W < 80 || H < 80, return; end
                xl = obj.ColumnLabels;
                nS = max(numel(xl),1);
                n = 0;
                if ~isempty(xl), n = double(max(strlength(xl))); end
                ml = 62;  mr = 14;  mt = 26;  mb = 28;
                colW = (W - ml - mr)/nS;
                rot = 6*n + 8 > colW;
                if rot
                    mb = 22 + ceil(6*n*sind(25));
                    if ~isempty(xl)
                        ml = max(ml,ceil(6*double(strlength(xl(1)))*cosd(25)) - 12);
                    end
                end
                mb = min(mb,0.45*H);
                obj.put('ax_xrot',ax,'XTickLabelRotation',25*rot);
                ax.Position = [ml/W mb/H max(0.05,(W - ml - mr)/W) max(0.05,(H - mb - mt)/H)];
            catch me
                mabr.log.vprintf(2,'Session tab: matrix not laid out (%s).',me.message);
            end
        end



        function renderSelection(obj)
            % The selected condition's cell, outlined in the accent colour.
            M = obj.Matrix;
            ck = obj.Model.Selection.ConditionKey;
            [r,c] = find(M.CondKeys == ck & ck ~= "",1);
            h = obj.Handles.Outline;
            if isempty(r)
                set(h,'XData',NaN,'YData',NaN);
                return
            end
            e = 0.46;
            set(h,'XData',c + [-e e e -e -e],'YData',r + [-e -e e e -e]);
        end

        function onMatrixClick(obj,evt)
            % A click on the matrix: the cell under the pointer.
            p = [];
            try
                p = evt.IntersectionPoint;
            catch
            end
            if isempty(p)
                try
                    cp = obj.Handles.Axes.CurrentPoint;
                    p = cp(1,1:2);
                catch
                    return
                end
            end
            c = round(p(1));  r = round(p(2));
            M = obj.Matrix;
            if r < 1 || c < 1 || r > size(M.CondKeys,1) || c > size(M.CondKeys,2), return; end
            if M.CondKeys(r,c) == "", return; end
            open = false;
            try
                fig = ancestor(obj.Handles.Axes,'figure');
                open = strcmp(fig.SelectionType,'open');
            catch
            end
            obj.cellClicked(r,c,open);
        end

        function cellClicked(obj,r,c,open)
            ck = obj.Matrix.CondKeys(r,c);
            obj.Model.selectCondition(ck);
            if open && ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.activateTab("Series");
            end
        end

        % ---- the files ----------------------------------------------------------
        function renderFiles(obj)
            S = obj.Model.Session;
            tb = obj.Handles.Files;
            F = S.Files;
            if ~istable(F) || height(F) == 0
                tb.Data = obj.blankFiles(0);
                obj.FileIds = strings(0,1);
                obj.RunGroups = strings(0,1);
                obj.ShownUse = false(0,1);
                obj.refreshFileUse();
                return
            end
            n = height(F);
            blind = obj.Model.BlindReview;
            ids = obj.colOf(F,'FileId',strings(n,1));
            rg  = obj.colOf(F,'RunGroup',strings(n,1));
            rg(ismissing(rg)) = "";
            ts  = obj.colOf(F,'timestamp',NaT(n,1));
            % grouped by run (sorted), in start order within; unreadable last
            key = rg;  key(key == "") = char(65535);
            tnum = inf(n,1);
            ok = ~isnat(ts);
            tnum(ok) = posixtime(ts(ok));
            [~,~,gi] = unique(key);
            [~,o] = sortrows([gi tnum (1:n).']);
            rig = obj.rigRejections(S,n);
            pn = S.ParamNames;
            pn = pn(pn ~= "Stimulus");
            T = obj.blankFiles(n);
            stim = obj.colOf(F,'Stimulus',strings(n,1));
            for k = 1:n
                i = o(k);
                if isnat(ts(i)), st = ""; else, st = string(ts(i),'HH:mm:ss'); end
                params = strings(1,0);
                for p = pn
                    if ismember(char(p),F.Properties.VariableNames)
                        v = F.(p)(i);
                        if isnumeric(v) && isfinite(v)
                            params(end+1) = p + "=" + sprintf('%g',v); %#ok<AGROW>
                        end
                    end
                end
                if blind
                    % (blind review: no file names, no clock times)
                    T.("Run group"){k} = char(regexprep(rg(i),'^[\d:-]+\s+',''));
                    T.File{k} = sprintf('file %d',k);
                    T.Start{k} = '';
                else
                    T.("Run group"){k} = char(rg(i));
                    T.File{k} = char(obj.cellText(F,'fileName',i));
                    T.Start{k} = char(st);
                end
                T.Stimulus{k} = char(stim(i));
                T.Params{k} = char(strjoin(params,"; "));
                T.Sweeps(k) = obj.numOf(F,'nSweeps',i);
                T.("Rig rej.")(k) = rig(i);
                T.Layout{k} = char(obj.cellText(F,'Layout',i));
                isi = obj.numOf(F,'MinISI',i);
                T.("ISI (ms)")(k) = round(isi*10)/10;
                T.Units{k} = char(obj.cellText(F,'Units',i));
                T.("Level unit"){k} = char(obj.cellText(F,'LevelUnit',i));
                tm = false;
                try
                    tm = logical(F.TestMode(i));
                catch
                end
                if tm, T.Test{k} = 'TEST'; end
                note = obj.fileNote(F,i);
                if blind, note = regexprep(obj.mask(note),'duplicate of \S+','duplicate'); end
                T.Note{k} = char(note);
            end
            obj.FileIds = ids(o);
            obj.RunGroups = rg(o);
            use = obj.currentUse();
            T.Use = use;
            tb.Data = T;
            obj.ShownUse = use;
            obj.SessionShown = obj.Model.SessionKey;
            obj.refreshFileUse();
        end

        function T = blankFiles(obj,n)
            c = @() repmat({''},n,1);
            T = table(false(n,1),c(),c(),c(),c(),c(),NaN(n,1),NaN(n,1),c(),NaN(n,1),c(),c(),c(),c(), ...
                'VariableNames',cellstr(obj.FileColumns));
        end

        function use = currentUse(obj)
            % Use as staged: the files not left out by the user, with the
            % pending changes on top.
            ids = obj.FileIds;
            use = true(numel(ids),1);
            S = obj.Model.Session;
            try
                use(ismember(ids,reshape(string(S.Exclude),[],1))) = false;
            catch
            end
            P = obj.Model.PendingFileUse;
            for k = 1:numel(P.FileIds)
                i = find(ids == P.FileIds(k),1);
                if ~isempty(i), use(i) = P.Use(k); end
            end
        end

        function refreshFileUse(obj)
            % The Use column and the pending line, after a staging change.
            if isempty(obj.Model.Session), return; end
            if obj.SessionShown ~= obj.Model.SessionKey
                obj.renderFiles();
                return
            end
            use = obj.currentUse();
            if ~isequal(use,obj.ShownUse)
                tb = obj.Handles.Files;
                T = tb.Data;
                if istable(T) && height(T) == numel(use)
                    T.Use = use;
                    tb.Data = T;
                end
                obj.ShownUse = use;
            end
            n = numel(obj.Model.PendingFileUse.FileIds);
            if n == 0
                txt = "";
            else
                if n == 1, w = "1 change"; else, w = n + " changes"; end
                est = mabr.ui.analysis.Style.formatSeconds(obj.Model.estimateSeconds("segment"));
                txt = w + " — Apply re-segments the affected conditions";
                if est ~= "", txt = txt + " (" + est + ")"; end
            end
            obj.put('pending_text',obj.Handles.Pending,'Text',char(txt));
            obj.refreshEnables();
        end

        function onFileEdited(obj,~,e)
            % A Use tick changed: stage it (the table already shows it, so
            % the refresh that follows writes nothing into the table from
            % inside its own callback).
            try
                r = e.Indices(1);  c = e.Indices(2);
            catch
                return
            end
            if c ~= 1 || r > numel(obj.FileIds), return; end
            tf = logical(e.NewData);
            obj.ShownUse(r) = tf;
            obj.Model.stageFileUse(obj.FileIds(r),tf);
        end

        function onFilesMenuOpening(obj,e)
            % Which row the menu was opened on (the right-clicked one where
            % the release says so, else the selected one).
            obj.MenuRow = NaN;
            try
                r = e.InteractionInformation.Row;
                if ~isempty(r) && isfinite(r(1)), obj.MenuRow = r(1); return; end
            catch
            end
            rows = mabr.ui.analysis.Compat.selectedRows(obj.Handles.Files);
            if ~isempty(rows), obj.MenuRow = rows(1); end
        end

        function rig = rigRejections(~,S,n)
            % Per Files row, the sweeps the rig itself flagged (RejectReason
            % 1) -- counted from the conditions, which know each sweep's file.
            rig = zeros(n,1);
            C = S.Conditions;
            try
                if ~all(ismember({'SweepFile','RejectReason'},C.Properties.VariableNames)), return; end
                for r = 1:height(C)
                    f = double(C.SweepFile{r});
                    why = double(C.RejectReason{r});
                    if numel(f) ~= numel(why), continue; end
                    f = f(why == 1 & f >= 1 & f <= n);
                    rig = rig + accumarray(f(:),1,[n 1]);
                end
            catch
                rig = NaN(n,1);
            end
        end

        function t = fileNote(obj,F,i)
            % Why a file is not used, or what to know about it.
            t = "";
            inc = true;
            try
                inc = logical(F.Include(i));
            catch
            end
            why = obj.cellText(F,'Reason',i);
            if ~inc && why ~= ""
                t = why;
            end
            dup = obj.cellText(F,'DuplicateOf',i);
            if dup ~= "" && ~contains(t,"duplicate")
                t = strjoin([t "duplicate of " + dup],"; ");
                t = regexprep(t,'^; ','');
            end
            try
                if logical(F.Short(i))
                    t = strjoin([t "short run"],"; ");
                    t = regexprep(t,'^; ','');
                end
            catch
            end
        end

        % ---- notes, messages, summary, overrides -----------------------------
        function renderNotes(obj)
            m = obj.Model;
            if m.BlindReview
                % (a notebook names animals, treatments and times: exactly
                % what blind review hides)
                obj.put('notes_value',obj.Handles.Notes,'Value',{'(notes are hidden during blind review)'});
                return
            end
            scope = "session";
            if obj.look().NotesScope == "All notes", scope = "all"; end
            keys = m.SessionKeys;
            if isempty(keys), keys = m.SessionKey; end
            N = table();
            for k = reshape(string(keys),1,[])
                try
                    Tk = m.Catalog.notes(k,'Scope',scope);
                    N = [N; Tk(:,{'Time','Stamp','Text'})]; %#ok<AGROW>
                catch
                end
            end
            lines = strings(0,1);
            if height(N) > 0
                % each note once, by (time, text) -- a notebook repeats in
                % every file, and a pool's members share it
                tk = strings(height(N),1);
                for i = 1:height(N)
                    if isnat(N.Time(i))
                        tk(i) = "stamp:" + string(N.Stamp(i));
                    else
                        tk(i) = string(N.Time(i),'yyyy-MM-dd''T''HH:mm:ss');
                    end
                end
                [~,first] = unique(tk + "|" + string(N.Text),'stable');
                N = N(sort(first),:);
                tn = inf(height(N),1);
                ok = ~isnat(N.Time);
                tn(ok) = posixtime(N.Time(ok));
                [~,o] = sortrows([tn (1:height(N)).']);
                N = N(o,:);
                for i = 1:height(N)
                    if isnat(N.Time(i))
                        st = string(N.Stamp(i));
                    elseif scope == "all"
                        st = string(N.Time(i),'yyyy-MM-dd HH:mm');
                    else
                        st = string(N.Time(i),'HH:mm:ss');
                    end
                    lines(end+1,1) = "[" + st + "] " + string(N.Text(i)); %#ok<AGROW>
                end
            end
            if isempty(lines)
                if scope == "all"
                    lines = "(no notes in this session's files or journal)";
                else
                    lines = "(no notes were written while this session was recorded)";
                end
            end
            obj.put('notes_value',obj.Handles.Notes,'Value',cellstr(lines));
        end

        function renderMessages(obj)
            S = obj.Model.Session;
            M = table();
            try
                M = S.Messages;
            catch
            end
            n = 0;
            if istable(M), n = height(M); end
            if n == 0
                D = table(cell(0,1),cell(0,1),cell(0,1),cell(0,1), ...
                    'VariableNames',{'Time','Level','Step','Text'});
            else
                lev = lower(string(M.Level));
                rank = 3*ones(n,1);
                rank(lev == "error") = 1;
                rank(lev == "warning") = 2;
                tn = inf(n,1);
                try
                    ok = ~isnat(M.Time);
                    tn(ok) = posixtime(M.Time(ok));
                catch
                end
                [~,o] = sortrows([rank tn (1:n).']);
                M = M(o,:);
                tt = repmat({''},n,1);
                for i = 1:n
                    try
                        if ~isnat(M.Time(i)), tt{i} = char(string(M.Time(i),'HH:mm:ss')); end
                    catch
                    end
                end
                txt = string(M.Text);
                if obj.Model.BlindReview
                    for i = 1:n, txt(i) = obj.mask(txt(i)); end
                end
                D = table(tt,cellstr(string(M.Level)),cellstr(string(M.Step)),cellstr(txt), ...
                    'VariableNames',{'Time','Level','Step','Text'});
            end
            obj.Handles.Messages.Data = D;
        end

        function renderSummary(obj)
            % How this session was processed (11 sec. 5), as text.
            m = obj.Model;
            S = m.Session;
            if isempty(S), return; end
            L = strings(0,1);
            blind = m.BlindReview;
            try
                if blind
                    % (describe names the folder and the subject)
                    nInc = sum(logical(S.Files.Include));
                    L(end+1) = sprintf('%d files (%d included), %d conditions, %g Hz', ...
                        height(S.Files),nInc,height(S.Conditions),S.SampleRate);
                else
                    L(end+1) = S.describe();
                end
            catch
            end
            if m.SessionSource == "results"
                L(end+1) = "Opened from its results file (no sweeps in memory until they are needed).";
            end
            % processing per condition group
            C = S.Conditions;
            if istable(C) && height(C) > 0
                stim = obj.colOf(C,'Stimulus',repmat("",height(C),1));
                mode = obj.colOf(C,'AcqMode',repmat("",height(C),1));
                proc = obj.colOf(C,'Processing',repmat("",height(C),1));
                grp = strtrim(stim + " " + mode);
                [u,~,j] = unique(grp,'stable');
                for k = 1:numel(u)
                    pk = proc(j == k);
                    pu = unique(pk(pk ~= ""),'stable');
                    w = sum(j == k) + " condition(s)";
                    if ~isempty(pu), w = w + ", " + strjoin(pu," and "); end
                    nm = u(k);
                    if nm == "", nm = "Conditions"; end
                    L(end+1) = "  " + nm + ": " + w; %#ok<AGROW>
                end
            end
            % the filters
            try
                L(end+1) = "Filter: " + S.Filter.describe();
                [hp,lpf] = S.Filter.corners6dB();
                cc = strings(1,0);
                if isfinite(hp), cc(end+1) = sprintf('%.0f Hz',hp); end
                if isfinite(lpf), cc(end+1) = sprintf('%.0f Hz',lpf); end
                if ~isempty(cc), L(end+1) = "  −6 dB corners: " + strjoin(cc," and "); end
            catch
            end
            st = S.Settings;
            if isempty(st), st = m.Settings; end
            try
                if istable(C) && ismember('Processing',C.Properties.VariableNames) && ...
                        any(string(C.Processing) == "windowed")
                    L(end+1) = "Windowed operator: " + S.Filter.describeWindowed( ...
                        Order=st.WindowedOrder,PadMode=st.PadMode);
                end
            catch
            end
            % acquisition modes and pooling
            try
                modes = strjoin(S.AcqModes,", ");
                if modes ~= ""
                    pooled = "kept apart";
                    if ~isempty(st) && st.PoolAcqModes, pooled = "pooled"; end
                    L(end+1) = "Acquisition: " + modes + " (" + pooled + ")";
                end
            catch
            end
            try
                if S.Units ~= "" || S.LevelUnit ~= ""
                    L(end+1) = "Units: " + S.Units + "; levels in " + S.LevelUnit;
                end
            catch
            end
            try
                lt = m.latencyText();
                if lt ~= "", L(end+1) = lt; end
            catch
            end
            % settings, fingerprint, results file
            try
                if ~isempty(S.Settings)
                    pn = S.Settings.matchingProfile();
                    if pn == "", pn = "(modified)"; end
                    L(end+1) = "Settings: profile " + pn + " · hash " + S.Settings.hash();
                else
                    L(end+1) = "Settings: not analysed yet (the project's are in force)";
                end
            catch
            end
            try
                if S.DataFingerprint ~= "", L(end+1) = "Data fingerprint: " + S.DataFingerprint; end
            catch
            end
            if ~blind
                try
                    L(end+1) = "Results: " + m.sessionInfo(m.SessionKey).ResultsFile;
                catch
                end
            end
            obj.put('summary_value',obj.Handles.Summary,'Value',cellstr(L));
        end

        function renderOverrides(obj)
            % The project's per-session overrides (empty = none).
            m = obj.Model;
            vals = NaN(1,4);
            cols = ["InputFullScaleOverride","AmplifierGainOverride","TimeOffsetOverride", ...
                "ConductionDelayOverride"];
            try
                T = m.Project.Sessions;
                r = find(string(T.Key) == m.SessionKey,1);
                if ~isempty(r)
                    for i = 1:numel(cols)
                        if ismember(char(cols(i)),T.Properties.VariableNames)
                            vals(i) = double(T.(cols(i))(r));
                        end
                    end
                end
            catch
            end
            f = obj.Handles.Overrides;
            names = ["FullScale","Gain","TimeOffset","ConductionDelay"];
            for i = 1:numel(names)
                if isfinite(vals(i)), t = sprintf('%g',vals(i)); else, t = ''; end
                obj.put("ov_" + names(i),f.(names(i)),'Value',t);
            end
        end

        function refreshEnables(obj)
            m = obj.Model;
            busy = m.Busy;
            has = ~isempty(m.Session);
            pend = has && ~isempty(m.PendingFileUse.FileIds);
            on = @(tf) matlab.lang.OnOffSwitchState(tf);
            obj.put('apply_on',obj.Handles.ApplyFiles,'Enable',on(pend && ~busy));
            obj.put('discard_on',obj.Handles.DiscardFiles,'Enable',on(pend && ~busy));
            % "Only conventional" / "Only interleaved" choose between two
            % kinds of run: offered only when the session holds that kind
            % AND another (on a session of one kind they would either change
            % nothing or leave nothing to analyse), the tooltip saying why
            modes = strings(0,1);
            if has
                try
                    modes = unique(string(m.Session.Files.AcqMode));
                    modes = modes(~ismissing(modes) & modes ~= "");
                catch
                end
            end
            mixed = numel(modes) > 1;
            tips = ["Stage every file of the session for use.", ...
                "Stage only the conventional (one condition per file) runs for use.", ...
                "Stage only the interleaved (intermixed) runs for use.", ...
                "Skip files with < 50% of the median sweep count (runs stopped early)."];
            ok = [true, mixed && any(modes == "conventional"), mixed && any(modes == "interleaved"), true];
            for k = 2:3
                if ~ok(k) && has
                    kind = ["","conventional","interleaved"];
                    if any(modes == kind(k))
                        tips(k) = "Every run of this session is " + kind(k) + ": there is nothing to choose between.";
                    else
                        tips(k) = "This session has no " + kind(k) + " runs.";
                    end
                end
            end
            for k = 1:numel(obj.Handles.Bulk)
                obj.put("bulk_on_" + k,obj.Handles.Bulk(k),'Enable',on(has && ~busy && ok(k)));
                obj.put("bulk_tip_" + k,obj.Handles.Bulk(k),'Tooltip',char(tips(k)));
            end
            obj.put('ovapply_on',obj.Handles.ApplyOverrides,'Enable',on(has && ~busy));
        end

        % ---- dropdown callbacks (the only places the look is saved) ---------
        function onMetricPicked(obj,src)
            obj.setMetric(string(src.Value));
            obj.savePrefs();
        end

        function onScopePicked(obj,src)
            obj.setNotesScope(string(src.Value));
            obj.savePrefs();
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function [vals,txt,marks] = cellValues(S,CK,metric)
            % Each cell's measure, its text, and its detection glyph.
            [nL,nS] = size(CK);
            vals = NaN(nL,nS);  txt = strings(nL,nS);  marks = strings(nL,nS);
            C = S.Conditions;
            if ~istable(C) || height(C) == 0, return; end
            keys = string(C.Key);
            v = mabr.ui.analysis.SessionView.metricValues(C,metric);
            det = [];  ovKeys = strings(0,1);
            if ismember('Detected',C.Properties.VariableNames), det = logical(C.Detected); end
            try
                D = S.DetectionOverrides;
                if istable(D) && height(D) > 0, ovKeys = string(D.Key); end
            catch
            end
            for i = 1:nL
                for j = 1:nS
                    if CK(i,j) == "", continue; end
                    r = find(keys == CK(i,j),1);
                    if isempty(r), continue; end
                    vals(i,j) = v(r);
                    txt(i,j) = mabr.ui.analysis.SessionView.formatValue(v(r),metric);
                    if ~isempty(det)
                        marks(i,j) = mabr.ui.analysis.Style.detectionGlyph(det(r),any(ovKeys == CK(i,j)));
                    end
                end
            end
        end

        function s = formatValue(v,metric)
            if ~isfinite(v)
                s = "–";
                return
            end
            switch string(metric)
                case "Clean sweeps", s = string(sprintf('%d',round(v)));
                case "% rejected",   s = string(sprintf('%.0f',v));
                case "−log10 p",     s = string(sprintf('%.1f',v));
                case "Split-half r", s = string(sprintf('%.2f',v));
                otherwise,           s = string(sprintf('%.1f',v));
            end
            % (p = 1 is -log10 p = -0, and a value that rounds to zero is
            % zero: never "-0.0" in a cell)
            s = regexprep(s,'^-(0(\.0*)?)$','$1');
        end

        function lim = limitsFor(v,metric)
            v = v(isfinite(v));
            switch string(metric)
                case "Clean sweeps"
                    % (from zero: 61 against 62 sweeps is no difference worth
                    % a colour, a condition left with 20 is)
                    lim = [0 max([v(:); 1])];
                case "% rejected", lim = [0 max([v(:); 10])];
                case "−log10 p",   lim = [0 max([v(:); 3])];
                case "Split-half r", lim = [min([v(:); 0]) 1];
                otherwise
                    if isempty(v)
                        lim = [0 1];
                    else
                        lim = [min(v) max(v)];
                    end
            end
            if ~(lim(2) > lim(1)), lim = lim(1) + [-0.5 0.5]; end
        end

        function cm = ramp()
            % Paper white to the data blue (the higher, the darker).
            a = [0.96 0.97 0.99];
            b = [0.13 0.33 0.56];
            t = linspace(0,1,64).';
            cm = a + t.*(b - a);
        end

        function c = cellColor(v,lim,cmap)
            if ~isfinite(v)
                c = [0.97 0.97 0.97];
                return
            end
            n = size(cmap,1);
            k = round(1 + (v - lim(1))/(lim(2) - lim(1))*(n - 1));
            c = cmap(min(max(k,1),n),:);
        end

        function ink = inkOn(c)
            % Ink or white, whichever reads on the cell.
            L = 0.2126*c(1) + 0.7152*c(2) + 0.0722*c(3);
            if L < 0.5
                ink = [1 1 1];
            else
                ink = mabr.ui.analysis.Style.Ink;
            end
        end

        function v = colOf(T,name,default)
            if ismember(char(name),T.Properties.VariableNames)
                v = T.(char(name));
                if iscellstr(v), v = string(v); end %#ok<ISCLSTR>
                if isstring(v), v(ismissing(v)) = ""; end
            else
                v = default;
            end
        end

        function t = cellText(T,name,i)
            t = "";
            if ~ismember(char(name),T.Properties.VariableNames), return; end
            v = T.(char(name))(i);
            if iscell(v), v = v{1}; end
            t = string(v);
            if isempty(t) || ismissing(t), t = ""; end
        end

        function x = numOf(T,name,i)
            x = NaN;
            if ~ismember(char(name),T.Properties.VariableNames), return; end
            try
                x = double(T.(char(name))(i));
            catch
            end
        end

        function t = rowText(T,r,name)
            t = "";
            if ~ismember(char(name),T.Properties.VariableNames), return; end
            t = string(T.(char(name))(r));
            if isempty(t) || ismissing(t), t = ""; end
        end

        function x = rowNum(T,r,name)
            x = NaN;
            if ~ismember(char(name),T.Properties.VariableNames), return; end
            x = double(T.(char(name))(r));
        end
    end
end
