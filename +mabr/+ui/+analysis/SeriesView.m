classdef SeriesView < mabr.ui.analysis.View
% mabr.ui.analysis.SeriesView  The Series tab: one level series -- its traces, its threshold, its peaks.
%
%   The tab where a threshold is decided and the waves are picked, one series
%   at a time (one stimulus swept in level: "Tone 8 kHz"). Three columns:
%
%     LEFT    every series of the open session (AnalysisSeriesList): its
%             decision glyph (✓ accepted, ✎ manual, ∅ no response, ≤ all
%             respond, ✕ excluded, ⚑ flagged and unreviewed), its final
%             threshold, the method's fit [interval], and short flag codes --
%             NM non-monotone, W wide CI, X extrapolated, LS low sweeps, IS
%             isolated detection, MA miss above, FC fit changed -- with
%             "Reviewed 5/7" above it. Clicking a row opens that series at the
%             level last used in it, else the level next to its threshold
%             (11 sec. 7.1, Model.selectSeries).
%     CENTRE  the level stack (AnalysisSeriesStack): one average per level,
%             loudest at the top. The selected level is black; a level with a
%             detected response dark grey, one without light grey and dashed;
%             the right margin carries ● / ○ (■ / □ where a person overrode
%             the detection) and the clean sweep count (amber below
%             MinSweeps). The final threshold is a green divider between the
%             levels ("NR" above the loudest for no response), the method's own
%             fit a dashed red one wherever it differs. Wave picks are one
%             marker line per wave and kind (▲ peaks, ▼ troughs, in the wave's
%             colour; × in light grey where a wave is marked absent), the
%             selected point larger with a black edge. The wave search windows
%             are shaded on the selected level only -- where the tracker
%             expects each wave at that level, the loudest level's window
%             moved later by the wave's latency shift per dB -- the response
%             window faintly behind everything.
%     RIGHT   two sub-tabs. THRESHOLD: the method -- the PROJECT's, so a change
%             re-fits the open session at once and leaves every other session
%             out of date, never re-run behind the user's back -- with its
%             definition in one sentence; the evidence the method decided from
%             (a p-method's detections, and -log10 p beside its alpha line on
%             a ruler of its own at the right; a graded method's metric beside
%             its criterion; the fitted curve and interval; the fit dashed
%             red, the final value green, censoring as arrows, n per level
%             along the bottom); the curation buttons, a
%             value field, the decision in words; every other method's answer
%             on request; and this session's audiogram, with the series that
%             have no frequency listed under it in words. PEAKS: the wave
%             matrix (latency, P–N or baseline–peak amplitude per level and
%             wave; manual picks bold, absent "—", below threshold grey
%             italic; bootstrap SE columns once there are any), the peak
%             buttons, and an I/O or latency–intensity plot.
%
%   THE MOUSE. A click on the stack selects the level under it -- a level's
%   band reaches halfway to each neighbour. With a wave point selected (1–5
%   its peak, Shift+1–5 its trough, a click on its marker, or a cell of the
%   wave matrix), a click inside the selected level's band moves that point
%   to the nearest extremum (snap); pressing ON the marker (within 8 px) and
%   dragging puts it exactly where it is let go. Either is one undo step.
%   Right-click opens the context menu and does nothing else.
%
%   THE THRESHOLD BY HAND. The green divider -- or, where there is no final
%   threshold yet, its grip (the hollow green ◁ at the stack's right edge)
%   -- can be dragged up and down (mabr.ui.analysis.ThresholdDrag): a press
%   within a few pixels of it (the pointer turns to the resize arrows
%   there) takes it, the divider follows the pointer with a readout beside
%   it ("Threshold 37.5 dB SPL") and the whole sentence on the status line,
%   and the release decides through the Model's curation call the buttons
%   make: between two levels it SNAPS half way, the louder being the lowest
%   level with a response (what "t" on that level decides); with Alt held
%   it is the value at the pointer, to 0.1 dB; above the loudest level, no
%   response; below the quietest, all respond. Esc during the drag cancels;
%   Ctrl+Z undoes the release. A press on the divider released where it was
%   is an ordinary click (it selects the level), and the selected wave
%   point's own drag keeps its priority within its 8 px. The evidence plot
%   on the Threshold side does the same along its level axis: drag its
%   green line sideways, or click (or drag) in the band of sweep counts
%   along its bottom.
%
%   TIME. Every time axis comes from mabr.ui.analysis.View.timeAxis: with a
%   conduction delay the stack reads "Time re sound arrival (ms)" and names
%   the delay in its subtitle, and traces, picks AND the wave windows are
%   drawn at raw time minus the offset. The windows are written, and
%   searched, in the recording's own time (re the timing pulse; the delay
%   changes no pick, mabr.analysis.Peaks), so a window drawn as written on
%   an ear-time axis would sit the offset later than the samples the picker
%   searched, and a pick could appear outside its own window. The matrix and
%   the latency plot show the same ear-time latencies
%   (mabr.analysis.Peaks.reported, the one place the offset comes off). With
%   no offset nothing moves. A click is converted back to raw time (rawTime)
%   before it reaches Model.setPeak.
%
%   Gestures a test or a script uses instead of the mouse:
%       v.clickAt(tMs,level)        % a click at tMs (drawn time) on LEVEL's band
%       v.dragPeak(wave,kind,tMs)   % kind "P" | "N"; placed exactly, no snap
%       v.menuAction(name)          % the stack's context menu: "accept",
%                                   % "atLevel", "noResponse", "exclude",
%                                   % "override", "autoPick", "retrack",
%                                   % "absent", "revert", "exportFigure",
%                                   % "copyData", "copyImage"
%       y = v.thresholdHandleY()    % where the divider (or its grip) is
%       v.dragThreshold(y,Alt=,Cancel=)  % press on it, move to y, let go
%   and Handles.Stack: Axes; Lines and Lines2 (containers.Map, condition key
%   -> the trace and, for "+/− overlay", the negative one); Markers
%   (containers.Map "wave|P"/"wave|N" -> one line per wave and kind); Absent
%   and Windows (by wave); Final, Fit, Grip (Tag SeriesThresholdGrip),
%   Selected, Compare, Response. ThresholdDragging is true from the press
%   on the divider to the release; ThresholdReadout is the readout as last
%   drawn ("" when none). The mouse's own callbacks are the axes'
%   ButtonDownFcn and, during a drag, the figure's WindowButtonMotionFcn,
%   WindowButtonUpFcn and WindowKeyPressFcn -- a test sets the figure's
%   CurrentPoint and calls them.
%
%   THE LOOK (Polarity, Normalize, PeaksShow, PlotKind, SideTab) is kept in
%   the MABR pref OfflineAnalysisSeries -- written only from this tab's own
%   controls, never from a key, a setter or a script.
%
%   See also mabr.ui.analysis.View, mabr.ui.analysis.Model,
%   mabr.analysis.SeriesThreshold, mabr.analysis.Peaks, mabr.ui.AnalysisApp
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        PolarityItems = ["Balanced","+","−","+/− overlay","Difference"]
        PolarityData  = ["balanced","positive","negative","overlay","difference"]
        ShowItems     = ["Latency (ms)","P–N amplitude (µV)","Baseline–peak amplitude (µV)"]
        ShowData      = ["latency","pn","bp"]
        PlotItems     = ["I/O","Latency–intensity"]
        PlotData      = ["io","latency"]
        SideTabs      = ["Threshold","Peaks"]
        DefaultWindow = [-2 10]      % ms, the drawn (ear) time
        DragPixels    = 8            % a press this close to the selected marker drags it
        % the stack axes' margins inside its panel, px [left bottom right
        % top]: tick labels and the level label; the time label; the
        % detection glyph and sweep count; the subtitle and wave names
        StackMargins  = [54 42 52 34]
        MarginGlyphPx = 5            % the glyph this far right of the axes, px
        MarginCountPx = 20           % ... and the sweep count
        % the side plots' axes inside their panels, px [left bottom right
        % top] (Style.pinAxes): tick labels and the axis label on the left,
        % the ticks and the level label below; the evidence plot's own
        % ruler (−log10 p, power F) on its right
        % the series list's column, px (a wide window, a narrow one): room
        % for "16 kHz ⧉" beside the decision, Final, Fit and Flags columns
        ListWidth = [252 212]
        EvidenceMargins  = [52 42 50 8]
        AudiogramMargins = [52 42 14 8]
        PeakPlotMargins  = [60 38 18 12]
        ScaleBarTag      = 'SeriesScaleBar'
        % the Threshold sub-tab's rows: method, custom row (0 unless
        % "custom"), definition, evidence, two button rows, value, decision,
        % other methods, compare, audiogram, the series it cannot place
        ThresholdRows = {24,0,46,172,36,36,26,40,88,26,150,'fit'}
        TextNoSession   = "Open a session from the browser (double-click, Enter, or Open)."
        TextNoLevel     = "No level parameter found — choose one in Settings ▸ Thresholds."
        TextSingleLevel = "Only one level was recorded — no threshold can be estimated."
        TextNoSeries    = "This session has no conditions to show."
        TextNotAnalysed = "Not analysed — press Analyse (Ctrl+Enter)"
        % (substring of a Thresholds flag, its code in the list)
        FlagCodes = ["non-monotone","NM"; "wide CI","W"; "extrapolated","X"; ...
                     "low sweeps","LS"; "isolated detection","IS"; "miss above","MA"; ...
                     "fit changed","FC"]
        MenuNames = ["accept","atLevel","noResponse","exclude","override","autoPick", ...
                     "retrack","absent","revert","exportFigure","copyData","copyImage"]
        ColorDetected   = [0.25 0.25 0.25]
        ColorUndetected = [0.62 0.62 0.62]
        ColorNegative   = [0.80 0.40 0.20]
        ColorCompare    = [0.55 0.55 0.55]
        ColorAbsent     = [0.70 0.70 0.70]
        ColorCurrentRow = [1.00 0.93 0.80]
    end

    properties (SetAccess = private)
        AmpScale (1,1) double = 1            % amplitude multiplier (+ / −)
        SpacingScale (1,1) double = 1        % stack spacing multiplier (Shift+↑ / Shift+↓)
        TimeWindow (1,2) double = [-2 10]    % ms of drawn (ear) time
        Dragging (1,1) logical = false       % a marker is being dragged
        MenuLevel (1,1) double = NaN         % the level the context menu opened on
        CompareKey (1,1) string = ""         % the session overlaid ("" none)
        Geometry = []                        % the series as last drawn (computeGeometry)
        ThresholdReadout (1,1) string = ""   % the threshold drag's readout as last drawn
    end

    properties (Dependent)
        ThresholdDragging                    % a threshold divider is held (press to release)
    end

    properties (Access = private)
        ThrDrag = []                         % the threshold drag in progress (ThresholdDrag)
        DividerAt = []                       % where drawDividers put the divider and its grip
        EvidenceInfo = []                    % what the evidence plot drew, for its mouse
        EvidenceDrag = gobjects(0,1)         % the evidence drag's line and readout
        StackReadout = gobjects(0,1)         % the stack drag's readout
        DragInfo = []
        CompareCache = []                    % containers.Map: session key -> Session
        CompareFor (1,1) string = ""         % the session the compare list was built for
        EvObjs = gobjects(0,1)               % what the evidence plot drew last
        AgObjs = gobjects(0,1)               % ... the audiogram
        PkObjs = gobjects(0,1)               % ... the peak plot
        StackKey (1,1) string = ""           % what the stack's objects were built for
        ListKeys (:,1) string = strings(0,1) % series key of each list row
        ListStyle (1,1) string = ""          % the list's highlight as last applied
        MatrixInfo = []                      % row -> level/key, column -> wave of the matrix
        MatrixStyle (1,1) string = ""        % the matrix's styles as last applied
        OtherFor (1,1) string = ""           % the series the compare table describes
        ValueFor (1,1) string = ""           % the series the value field was seeded for
        Menus = gobjects(0,1)                % context menus (children of the figure)
        Pass = []                            % what one render pass looked up once (beginPass)
        MethodKey (1,1) string = ""          % the settings the method labels were resolved for
        MethodLabels = strings(1,0)          % ... those labels
        MethodCustom = []                    % ... and the custom row's criterion and unit
        StackPx = []                         % the stack axes' size in px, once laid out
        ValueSeed = NaN                      % what the value field was last seeded with
        CustomRowOn (1,1) logical = false    % the Threshold sub-tab shows the custom row
        AudiogramOn (1,1) logical = true     % ... and the audiogram (off: no frequency)
    end

    % =====================================================================
    methods
        function delete(obj)
            % (View's delete then removes the listeners and the graphics.)
            try
                obj.endDrag(false,NaN);
            catch
            end
            try
                if ~isempty(obj.ThrDrag) && isvalid(obj.ThrDrag)
                    obj.ThrDrag.cancel();
                    delete(obj.ThrDrag);
                end
            catch
            end
            try
                delete(obj.Menus(isvalid(obj.Menus)));
            catch
            end
        end

        function refresh(obj,what,keys) %#ok<INUSD> (keys: one series is drawn, whichever changed)
            % Redraw what a Model event changed. Words this tab does not draw
            % ("message", "save", "busy", "idle", "queue", "labels",
            % "columns", "pools", "sweeps") return at once.
            switch string(what)
                case {"all","rejection","detection","measures","thresholds","files"}
                    obj.renderGuarded(@() obj.renderAll());
                case "curation"
                    % a decision or a note: the traces and picks are as drawn
                    obj.renderGuarded(@() obj.renderCuration());
                case {"series","condition"}
                    % another series is a new stack; the one already drawn
                    % (a session just opened on it, a condition of it picked
                    % elsewhere) only moves the selected level
                    if obj.geometryValid()
                        obj.renderGuarded(@() obj.renderLevel());
                    else
                        obj.renderGuarded(@() obj.renderAll());
                    end
                case "peaks"
                    obj.renderGuarded(@() obj.renderPeaksOnly());
                case "level"
                    obj.renderGuarded(@() obj.renderLevel());
                case "wave"
                    obj.renderGuarded(@() obj.renderWave());
                case "status"
                    obj.renderBanner();
                otherwise
                    % nothing this tab draws
            end
        end

        function relayoutNow(obj)
            % (View.layoutSoon, on showing the tab) the column widths, the
            % stack's pixel margins and its right margin, the hint strip,
            % and the side plots at their margins: the window may have been
            % resized while the tab was hidden.
            obj.onResize();
            obj.placeSidePlots();
        end

        function handled = onCommand(obj,id)
            % The keys this tab owns: the display (n, +/−, Shift+↑/↓,
            % Ctrl+0), the wave keys (1–5, Shift+1–5: this series' own
            % waves), and Escape while a marker is being dragged.
            handled = false;
            m = obj.Model;
            id = string(id);
            switch id
                case "view.normalize"
                    % (a key, not a control: the look is not remembered)
                    obj.ViewLook.Normalize = ~obj.lookNormalize();
                    obj.renderGuarded(@() obj.renderTraces());
                    handled = true;
                case "view.scaleUp"
                    obj.AmpScale = min(obj.AmpScale*1.25,64);
                    obj.renderGuarded(@() obj.renderTraces());
                    handled = true;
                case "view.scaleDown"
                    obj.AmpScale = max(obj.AmpScale/1.25,1/64);
                    obj.renderGuarded(@() obj.renderTraces());
                    handled = true;
                case "view.spacingUp"
                    obj.SpacingScale = min(obj.SpacingScale*1.25,16);
                    obj.renderGuarded(@() obj.renderTraces());
                    handled = true;
                case "view.spacingDown"
                    obj.SpacingScale = max(obj.SpacingScale/1.25,1/16);
                    obj.renderGuarded(@() obj.renderTraces());
                    handled = true;
                case "view.resetZoom"
                    obj.AmpScale = 1;
                    obj.SpacingScale = 1;
                    obj.TimeWindow = obj.DefaultWindow;
                    obj.renderGuarded(@() obj.renderTraces());
                    handled = true;
                case "nav.escape"
                    if obj.ThresholdDragging
                        obj.ThrDrag.cancel();
                        handled = true;
                    elseif obj.Dragging
                        obj.endDrag(false,NaN);
                        handled = true;
                    end
                otherwise
                    if startsWith(id,"peak.wave") || startsWith(id,"peak.trough")
                        if isempty(m.Session), return; end
                        k = str2double(regexp(char(id),'\d+$','match','once'));
                        names = obj.waveNames();
                        if k >= 1 && k <= numel(names)
                            kind = "P";
                            if startsWith(id,"peak.trough"), kind = "N"; end
                            m.selectWave(names(k),kind);
                        end
                        handled = true;
                    end
            end
        end

        % ---- gestures (what the mouse does, for tests and scripts) -------
        function clickAt(obj,tMs,level)
            % A click on the stack at tMs (ms, the DRAWN time axis) in the
            % band of LEVEL: selects that level, or -- on the selected level
            % with a wave point selected -- moves the point to the nearest
            % extremum (a press on the marker itself starts a drag, which a
            % click without moving leaves where it was).
            arguments
                obj
                tMs (1,1) double {mustBeFinite}
                level (1,1) double {mustBeFinite}
            end
            G = obj.requireGeometry();
            [~,i] = min(abs(G.Levels - level));
            % on the trace, but never outside its own band
            v = obj.traceValue(G,i,tMs);
            if ~isfinite(v), v = 0; end
            y = G.Offsets(i) + max(min(v,0.49*G.Step),-0.49*G.Step);
            obj.pointerDown(tMs,y);
            if obj.ThresholdDragging
                % (a press on the divider let go where it was: a click)
                obj.ThrDrag.releaseAt(y);
            end
            if obj.Dragging
                obj.endDrag(true,tMs);
            end
        end

        function [y,onLine] = thresholdHandleY(obj)
            % Where the threshold divider is on the stack (its data units),
            % or -- with no final threshold yet -- its grip; NaN when the
            % series has no threshold to set (one level, not analysed).
            %   onLine  (returned) true for the divider, false for the grip
            G = obj.requireGeometry();
            y = NaN;  onLine = false;
            d = obj.DividerAt;
            if ~obj.canDragThreshold(G) || isempty(d) || d.SeriesKey ~= G.SeriesKey, return; end
            onLine = d.HasLine;
            if onLine, y = d.Line; else, y = d.Grip; end
        end

        function dragThreshold(obj,y,opts)
            % Press on the threshold divider (or its grip), move to Y (the
            % stack's data units) and let go -- the mouse's own code path,
            % without a mouse: the divider snaps half way between two
            % levels, or, with Alt, stays at Y (0.1 dB); above the loudest
            % level it is no response, below the quietest all respond.
            %   opts.Alt     Alt held during the drag
            %   opts.Cancel  Esc instead of the release (nothing changes)
            arguments
                obj
                y (1,1) double {mustBeFinite}
                opts.Alt (1,1) logical = false
                opts.Cancel (1,1) logical = false
            end
            [y0,~] = obj.thresholdHandleY();
            if ~isfinite(y0)
                error('mabr:ui:SeriesView:noThreshold','This series has no threshold to drag.');
            end
            xl = obj.TimeWindow;
            if ~obj.thresholdPress(xl(2),y0)
                error('mabr:ui:SeriesView:noThreshold','The threshold divider could not be taken.');
            end
            d = obj.ThrDrag;
            d.setAlt(opts.Alt);
            d.moveTo(y);
            if opts.Cancel
                d.cancel();
            else
                d.releaseAt(y);
            end
        end

        function tf = get.ThresholdDragging(obj)
            tf = ~isempty(obj.ThrDrag) && isvalid(obj.ThrDrag) && obj.ThrDrag.Active;
        end

        function p = hoverPointer(obj)
            % The resize arrows over the stack's divider (or its grip) and
            % over the evidence plot's green line; a hand over the evidence
            % plot's band of counts, where a click sets the threshold.
            p = "";
            try
                if ~obj.Built || ~obj.IsActive || obj.Dragging || obj.ThresholdDragging || ...
                        ~obj.geometryValid(), return; end
                G = obj.Geometry;
                if ~obj.canDragThreshold(G), return; end
                ax = obj.Handles.Stack.Axes;
                cp = ax.CurrentPoint;
                x = cp(1,1);  y = cp(1,2);
                xl = ax.XLim;  yl = ax.YLim;
                if x >= xl(1) && x <= xl(2) && y >= yl(1) && y <= yl(2)
                    if obj.onDivider(G,x,y,false), p = "top"; end
                    return
                end
                E = obj.EvidenceInfo;
                if isempty(E) || E.SeriesKey ~= G.SeriesKey || ~E.Draggable, return; end
                % (the evidence plot only while its sub-tab is showing: the
                % Peaks sub-tab occupies the same place, and its plot takes
                % no threshold)
                if obj.Handles.Side.SelectedTab ~= obj.Handles.SideThreshold, return; end
                ax = obj.Handles.Evidence;
                cp = ax.CurrentPoint;
                x = cp(1,1);  y = cp(1,2);
                if x < E.XLim(1) || x > E.XLim(2) || y < E.YLim(1) || y > E.YLim(2), return; end
                if isfinite(E.Final) && abs(x - E.Final)*E.PxPerX <= mabr.ui.analysis.ThresholdDrag.HitPixels ...
                        && y >= E.Bottom
                    p = "left";
                elseif y < E.Bottom
                    p = "hand";
                end
            catch
                p = "";
            end
        end

        function dragPeak(obj,wave,kind,tMs)
            % Drag WAVE's peak ("P") or trough ("N") at the selected level to
            % tMs (ms, the drawn time axis) and let go: placed exactly there,
            % no snap, one undo step.
            arguments
                obj
                wave (1,1) string
                kind (1,1) string {mustBeMember(kind,["P","N"])}
                tMs (1,1) double {mustBeFinite}
            end
            m = obj.Model;
            G = obj.requireGeometry();
            i = obj.currentIndex(G);
            if isnan(i)
                error('mabr:ui:SeriesView:noLevel','Select a level first.');
            end
            if m.Selection.Wave ~= wave || m.Selection.Kind ~= kind
                m.selectWave(wave,kind);
                G = obj.Geometry;
            end
            j = find(G.Waves == wave,1);
            if isempty(j)
                error('mabr:ui:SeriesView:noWave','This series has no wave "%s".',wave);
            end
            [px,~] = obj.pointXY(G,i,j,kind);
            if isfinite(px)
                obj.beginDrag(G,i,j,kind,px);
                obj.moveDrag(tMs);
                obj.endDrag(true,tMs);
            else
                obj.writeCursor(tMs,i);
                m.setPeak(G.Keys(i),wave,kind,obj.rawTime(tMs),Snap=false);
            end
        end

        function menuAction(obj,name,level)
            % Run an item of the stack's context menu (at LEVEL, default the
            % level the menu was opened on, else the selected one).
            arguments
                obj
                name (1,1) string
                level (1,1) double = NaN
            end
            if ~ismember(name,obj.MenuNames)
                error('mabr:ui:SeriesView:badMenu','The series menu has no "%s" (it has %s).', ...
                    name,strjoin(obj.MenuNames,', '));
            end
            m = obj.Model;
            if isnan(level), level = obj.MenuLevel; end
            if isfinite(level) && ~isempty(m.Session) && ~(m.Selection.Level == level)
                m.selectLevel(level);
            end
            ax = obj.Handles.Stack.Axes;
            switch name
                case "accept",       obj.runId("thr.accept");
                case "atLevel",      obj.runId("thr.atLevel");
                case "noResponse",   obj.runId("thr.noResponse");
                case "exclude",      obj.runId("thr.exclude");
                case "override",     obj.runId("thr.override");
                case "autoPick",     obj.runId("peak.autoPick");
                case "retrack",      obj.runId("peak.retrack");
                case "absent",       obj.runId("peak.absent");
                case "revert",       obj.runId("peak.revert");
                case "exportFigure"
                    if ~isempty(obj.Host) && isvalid(obj.Host)
                        obj.Host.openDialog("figureExport",ax);
                    else
                        mabr.ui.analysis.FigureExport(ax,[]);
                    end
                case "copyData",     mabr.ui.analysis.FigureExport.copyData(ax);
                case "copyImage",    mabr.ui.analysis.FigureExport.copyImage(ax);
            end
        end

        function T = matrixTable(obj)
            % The wave matrix as it is shown (a table; text cells).
            h = obj.Handles.Matrix;
            T = cell2table(h.Data,'VariableNames',matlab.lang.makeUniqueStrings( ...
                matlab.lang.makeValidName(cellstr(h.ColumnName(:).'))));
        end

        function build(obj)
            % The tab's controls (View calls this once, into Parent).
            obj.CompareCache = containers.Map('KeyType','char','ValueType','any');
            obj.TimeWindow = obj.DefaultWindow;
            look = obj.cleanLook(obj.ViewLook);
            obj.ViewLook = look;
            fig = ancestor(obj.Parent,'figure');
            panel = mabr.ui.analysis.Style.Panel;
            H = struct();
            g = uigridlayout(obj.Parent,[1 3],'ColumnWidth',{obj.ListWidth(1),'1x',400},'RowHeight',{'1x'}, ...
                'Padding',[6 6 6 6],'ColumnSpacing',6,'RowSpacing',4,'BackgroundColor',panel, ...
                'Tag','AnalysisSeriesGrid');
            g.Layout.Row = 1; g.Layout.Column = 1;
            H.Grid = g;

            % ---- left: the series list ------------------------------------
            gl = uigridlayout(g,[2 1],'RowHeight',{22,'1x'},'Padding',[0 0 0 0], ...
                'RowSpacing',4,'BackgroundColor',panel);
            gl.Layout.Row = 1; gl.Layout.Column = 1;
            H.Reviewed = uilabel(gl,'Text','','FontWeight','bold','Tag','AnalysisSeriesReviewed', ...
                'Tooltip',['Series of this session with a decision (accepted, manual, no response, ' ...
                'all respond or excluded), of all its series']);
            % (the columns fit the list's own width: the series' name gets
            % what the four narrow columns leave -- '1x' where the release
            % has weighted widths -- and the fit's interval is on the
            % Threshold side, not in a column the list has no room for)
            t = uitable(gl,'Tag','AnalysisSeriesList','RowName',{},'ColumnEditable',false, ...
                'ColumnName',{'','Series','Final','Fit','Flags'},'Data',cell(0,5), ...
                'ColumnWidth',{18,'auto',42,42,46},'FontSize',11);
            mabr.ui.analysis.SeriesView.trySet(t,'ColumnWidth',{18,'1x',42,42,46});
            t.Layout.Row = 2;
            mabr.ui.analysis.SeriesView.tip(t,['Every series of this session ("⧉" its interleaved ' ...
                'run): decision, final threshold, the method''s fit (its interval is on the ' ...
                'Threshold side) and flags (NM non-monotone, W wide CI, X extrapolated, LS low ' ...
                'sweeps, IS isolated detection, MA miss above, FC fit changed). Click a row to ' ...
                'open that series.']);
            mabr.ui.analysis.Compat.setSortable(t,false);
            mabr.ui.analysis.Compat.enableRowSelection(t,obj.viewWrap(@(s,e) obj.onListSelect(s,e)));
            H.List = t;
            obj.tableMenu(fig,t,'AnalysisSeriesListCopy');

            % ---- centre: strip, banner, stack, hints ----------------------
            gc = uigridlayout(g,[4 1],'RowHeight',{26,0,'1x',18},'Padding',[0 0 0 0], ...
                'RowSpacing',4,'BackgroundColor',panel);
            gc.Layout.Row = 1; gc.Layout.Column = 2;
            H.Centre = gc;
            strip = uigridlayout(gc,[1 5],'ColumnWidth',obj.StripColumns(false),'RowHeight',{'1x'}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',6,'BackgroundColor',panel);
            strip.Layout.Row = 1;
            H.Strip = strip;
            H.Polarity = uidropdown(strip,'Items',cellstr(obj.PolarityItems), ...
                'ItemsData',cellstr(obj.PolarityData),'Value',char(look.Polarity), ...
                'Tag','AnalysisSeriesPolarity', ...
                'Tooltip',['Which average is drawn: balanced (equal weight per stimulus polarity), ' ...
                'the + or − sweeps alone, both overlaid, or their difference (what follows polarity)'], ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onPolarity(s)));
            H.Normalize = uibutton(strip,'state','Text','Normalise (n)','Value',look.Normalize, ...
                'Tag','AnalysisSeriesNormalize', ...
                'Tooltip','Scale every trace to its own largest deflection (n)', ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onNormalize(s)));
            H.Compare = uidropdown(strip,'Items',{'Compare with: none'},'ItemsData',{''},'Value','', ...
                'Tag','AnalysisSeriesCompare', ...
                'Tooltip',['Overlay this series from another analysed session of the same subject ' ...
                '(grey dashes)'], ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onCompare(s)));
            % (a series is fully specified by its key, so there is nothing to
            % slice; the control exists for the contract and stays hidden)
            H.Slice = uidropdown(strip,'Items',{'—'},'Visible','off','Tag','AnalysisSeriesSlice', ...
                'Tooltip','Not needed: a series is one stimulus swept in level');
            H.Cursor = uilabel(strip,'Text','','Tag','AnalysisSeriesCursor','FontSize',11, ...
                'HorizontalAlignment','right','FontColor',mabr.ui.analysis.Style.Muted, ...
                'Tooltip',['Time, amplitude and level under the last click or drag on the stack ' ...
                '(while the green threshold line is dragged: the threshold a release would set)']);
            H.Banner = uilabel(gc,'Text','','Tag','AnalysisSeriesBanner','Visible','off', ...
                'HorizontalAlignment','center','FontColor',mabr.ui.analysis.Style.AccentText, ...
                'BackgroundColor',mabr.ui.analysis.Style.BarAmber,'WordWrap','on');
            H.Banner.Layout.Row = 2;
            sp = uipanel(gc,'BorderType','none','BackgroundColor',[1 1 1],'Tag','AnalysisSeriesStack');
            sp.Layout.Row = 3;
            % (a resized window may cross the 1000 px the column widths
            % change at; not a user's callback, so not wrapped)
            mabr.ui.analysis.SeriesView.trySet(sp,'AutoResizeChildren','off');   % (its axes are normalized)
            sp.SizeChangedFcn = @(~,~) obj.onResize();
            H.StackPanel = sp;
            ax = axes('Parent',sp,'Units','normalized','Position',[0.09 0.11 0.80 0.81], ...
                'Tag','AnalysisSeriesStackAxes','Box','off','TickDir','out','FontSize',10, ...
                'Color',[1 1 1],'XLim',obj.TimeWindow,'YLim',[0 1],'Layer','top');
            mabr.ui.hideAxesToolbar(ax);
            disableDefaultInteractivity(ax);
            ax.ButtonDownFcn = obj.viewWrap(@(s,e) obj.onStackDown(s,e));
            ax.XLabel.String = 'Time re onset (ms)';
            resp = patch(ax,NaN(4,1),NaN(4,1),[0.93 0.95 0.99],'EdgeColor','none', ...
                'FaceAlpha',0.6,'HitTest','off','PickableParts','none','Tag','SeriesResponseWindow', ...
                'DisplayName','response window');
            H.Stack = struct('Axes',ax,'Response',resp, ...
                'Lines',containers.Map('KeyType','char','ValueType','any'), ...
                'Lines2',containers.Map('KeyType','char','ValueType','any'), ...
                'Markers',containers.Map('KeyType','char','ValueType','any'), ...
                'Absent',containers.Map('KeyType','char','ValueType','any'), ...
                'Windows',containers.Map('KeyType','char','ValueType','any'), ...
                'Final',gobjects(1),'FinalText',gobjects(1),'Fit',gobjects(1),'Grip',gobjects(1), ...
                'Selected',gobjects(1),'Compare',gobjects(1),'Labels',gobjects(0,1), ...
                'Glyphs',gobjects(0,1),'Counts',gobjects(0,1),'LineList',gobjects(0,1), ...
                'LineList2',gobjects(0,1),'WaveSet',strings(1,0),'ScaleBar',gobjects(1), ...
                'ScaleText',gobjects(1));
            cm = uicontextmenu(fig,'Tag','AnalysisSeriesStackMenu');
            items = ["Accept fit (a)","accept"; "Threshold at this level (t)","atLevel"; ...
                "No response (i)","noResponse"; "Exclude (x)","exclude"; ...
                "Cycle detection override (d)","override"; "Auto-pick series (p)","autoPick"; ...
                "Re-track down (u)","retrack"; "Wave absent here (Delete)","absent"; ...
                "Back to automatic pick (Backspace)","revert"];
            for k = 1:size(items,1)
                nm = items(k,2);
                uimenu(cm,'Text',char(items(k,1)),'Tag',char("AnalysisSeriesMenu_" + nm), ...
                    'Separator',matlab.lang.OnOffSwitchState(k == 6), ...
                    'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.menuAction(nm)));
            end
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            cm.ContextMenuOpeningFcn = @(~,~) obj.onMenuOpening();
            ax.ContextMenu = cm;
            obj.Menus(end+1,1) = cm;
            % (as many of the tab's keys as the strip has room for, then "F1
            % all keys" -- fitted again on every resize, fitHints; the
            % tooltip has them all)
            H.Hints = uilabel(gc,'Text',char(mabr.ui.analysis.Commands.hint("series",MaxChars=90)), ...
                'Tag','AnalysisSeriesHints','FontColor',mabr.ui.analysis.Style.Muted,'FontSize',10, ...
                'Tooltip',char("On the stack, " + mabr.ui.analysis.ThresholdDrag.Hint + ...
                " (above the loudest level: no response; below the quietest: all respond; Esc " + ...
                "cancels). The keys of this tab (click the stack to give it the keyboard): " + ...
                mabr.ui.analysis.Commands.hint("series")));
            H.Hints.Layout.Row = 4;

            % ---- right: threshold and peaks -------------------------------
            tg = uitabgroup(g,'Tag','AnalysisSeriesSide');
            tg.Layout.Row = 1; tg.Layout.Column = 3;
            H.Side = tg;
            H.SideThreshold = uitab(tg,'Title','Threshold','Tag','AnalysisSeriesSideThreshold', ...
                'BackgroundColor',panel);
            H.SidePeaks = uitab(tg,'Title','Peaks','Tag','AnalysisSeriesSidePeaks', ...
                'BackgroundColor',panel);
            if look.SideTab == "Peaks", tg.SelectedTab = H.SidePeaks; end
            tg.SelectionChangedFcn = obj.viewWrap(@(s,e) obj.onSideTab(s,e));
            obj.Handles = H;
            obj.buildThreshold(fig);
            obj.buildPeaks(fig);
            obj.forgetWritten();
        end
    end

    % =====================================================================
    methods (Access = private)
        function buildThreshold(obj,fig)
            H = obj.Handles;
            panel = mabr.ui.analysis.Style.Panel;
            muted = mabr.ui.analysis.Style.Muted;
            g = uigridlayout(H.SideThreshold,[12 1],'Padding',[6 6 6 6],'RowSpacing',4, ...
                'RowHeight',obj.ThresholdRows,'BackgroundColor',panel, ...
                'Tag','AnalysisThresholdGrid');
            mabr.ui.analysis.SeriesView.trySet(g,'Scrollable','on');
            H.ThresholdGrid = g;
            r1 = obj.rowGrid(g,1,{52,'1x'});
            uilabel(r1,'Text','Method','FontWeight','bold');
            H.Method = uidropdown(r1,'Items',{'—'},'ItemsData',{''},'Value','', ...
                'Tag','AnalysisThresholdMethod', ...
                'Tooltip',['The threshold method of this PROJECT: the open session is re-fitted at ' ...
                'once, every other session becomes out of date (nothing is re-run until you press ' ...
                'Analyse there)'], ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onMethod(s)));
            r2 = obj.rowGrid(g,2,{'1x','1x',56,'fit'});
            r2.Tag = 'AnalysisThresholdCustomRow';
            H.CustomRow = r2;
            H.Metric = uidropdown(r2,'Items',cellstr(mabr.analysis.SeriesThreshold.Metrics), ...
                'Value','detection','Tag','AnalysisThresholdMetric', ...
                'Tooltip','Custom method: the per-level statistic the threshold is decided from', ...
                'ValueChangedFcn',obj.viewWrap(@(~,~) obj.onCustom("metric")));
            H.ModelDrop = uidropdown(r2,'Items',cellstr(mabr.analysis.SeriesThreshold.Models), ...
                'Value','glm','Tag','AnalysisThresholdModel', ...
                'Tooltip','Custom method: how the threshold is read off the levels', ...
                'ValueChangedFcn',obj.viewWrap(@(~,~) obj.onCustom("model")));
            H.Criterion = uieditfield(r2,'text','Value','','Tag','AnalysisThresholdCriterion', ...
                'Tooltip','Custom method: the criterion (blank = the default for this metric and model)', ...
                'ValueChangedFcn',obj.viewWrap(@(~,~) obj.onCustom("criterion")));
            H.CriterionUnit = uilabel(r2,'Text','','FontColor',muted,'Tag','AnalysisThresholdCriterionUnit');
            H.Definition = uilabel(g,'Text','','WordWrap','on','FontColor',muted,'FontSize',11, ...
                'VerticalAlignment','top','Tag','AnalysisThresholdDefinition');
            H.Definition.Layout.Row = 3;
            ep = uipanel(g,'BorderType','none','BackgroundColor',[1 1 1],'Tag','AnalysisThresholdEvidence');
            ep.Layout.Row = 4;
            % ONE axes. A p-method's second scale (-log10 p, or the power
            % F) is drawn into it and given a ruler of its own on the right
            % (drawRuler): not yyaxis, which copyobj cannot copy -- and every
            % plot here leaves through FigureExport, which copies axes into
            % a figure of their own -- and not a second axes laid over the
            % first, which FigureExport paints white and a uifigure can lay
            % out a few pixels off the first.
            ax = axes('Parent',ep,'Units','normalized','Position',[0.14 0.20 0.70 0.72], ...
                'Tag','AnalysisThresholdEvidenceAxes','FontSize',9,'Box','off','TickDir','out', ...
                'Color',[1 1 1]);
            mabr.ui.hideAxesToolbar(ax);
            disableDefaultInteractivity(ax);
            % room on the right for the drawn ruler when the axes is
            % exported on its own (FigureExport fits a copy to its figure,
            % keeping at least this inset; here Position decides)
            mabr.ui.analysis.SeriesView.trySet(ax,'LooseInset',[0.12 0.17 0.17 0.06]);
            % (here, margins in pixels: normalized fractions of a 172 px
            % panel left the tick labels and the ruler no fixed room, and a
            % panel resized by the uifigure put the axes half outside it)
            mabr.ui.analysis.Style.pinAxes(ep,ax,obj.EvidenceMargins);
            % (its green line drags along the level axis, and a click in the
            % band of counts along the bottom sets the threshold there --
            % the stack's rules, ThresholdDrag; what it draws passes clicks
            % through to the axes, renderEvidence)
            ax.ButtonDownFcn = obj.viewWrap(@(s,e) obj.onEvidenceDown(s,e));
            H.Evidence = ax;
            obj.plotMenu(fig,ax,'AnalysisThresholdEvidenceMenu');
            r5 = obj.rowGrid(g,5,{'1x','1x','1x'});
            H.Accept = obj.button(r5,'Accept fit (a)','AnalysisThresholdAccept', ...
                'Accept the fitted threshold (a)',@(~,~) obj.runId("thr.accept"));
            mabr.ui.analysis.Style.setButtonIcon(H.Accept,'accept','left');
            H.AtLevel = obj.button(r5,'At selected level (t)','AnalysisThresholdAtLevel', ...
                ['The threshold is the selected level: the lowest level with a response (t). ' ...
                'Or drag the green line on the stack: it snaps half way between two levels ' ...
                '(Alt for an exact value)'], ...
                @(~,~) obj.runId("thr.atLevel"));
            mabr.ui.analysis.Style.setButtonIcon(H.AtLevel,'threshold','left');
            H.NoResponse = obj.button(r5,'No response (i)','AnalysisThresholdNoResponse', ...
                ['No response at any level: the threshold is above the loudest level (i; or drag ' ...
                'the green line above the loudest trace)'], ...
                @(~,~) obj.runId("thr.noResponse"));
            mabr.ui.analysis.Style.setButtonIcon(H.NoResponse,'noresponse','left');
            r6 = obj.rowGrid(g,6,{'1x','1x','1x'});
            H.AllRespond = obj.button(r6,'All respond (Alt+↓)','AnalysisThresholdAllRespond', ...
                ['Every level responds: the threshold is at or below the quietest level (Alt+↓; ' ...
                'or drag the green line below the quietest trace)'], ...
                @(~,~) obj.runId("thr.allRespond"));
            mabr.ui.analysis.Style.setButtonIcon(H.AllRespond,'enableall','left');
            H.Exclude = obj.button(r6,'Exclude (x)','AnalysisThresholdExclude', ...
                'Exclude this series from the study (or bring it back), then say why in a note (x)', ...
                @(~,~) obj.runId("thr.exclude"));
            mabr.ui.analysis.Style.setButtonIcon(H.Exclude,'exclude','left');
            H.Clear = obj.button(r6,'Clear (c)','AnalysisThresholdClear', ...
                'Back to unreviewed: the decision is cleared (c)',@(~,~) obj.runId("thr.clear"));
            mabr.ui.analysis.Style.setButtonIcon(H.Clear,'trash','left');
            r7 = obj.rowGrid(g,7,{'fit',64,46,'1x'});
            uilabel(r7,'Text','Value (dB)');
            H.ValueField = uieditfield(r7,'numeric','Value',0,'Tag','AnalysisThresholdValueField', ...
                'Tooltip',['A threshold value of your own, in dB (then press Set) -- or hold Alt ' ...
                'while dragging the green line on the stack']);
            H.SetValue = obj.button(r7,'Set','AnalysisThresholdSetValue', ...
                'Make the value typed beside it this series'' threshold (uncensored)', ...
                @(~,~) obj.onSetValue());
            H.Note = obj.button(r7,'Note… (Ctrl+N)','AnalysisThresholdNote', ...
                'A note on this series'' threshold (Ctrl+N)',@(~,~) obj.runId("edit.note"));
            mabr.ui.analysis.Style.setButtonIcon(H.Note,'notes','left');
            H.State = uilabel(g,'Text','','WordWrap','on','VerticalAlignment','top', ...
                'Tag','AnalysisThresholdState','FontSize',11, ...
                'Tooltip','The decision on this series, its final threshold and the method''s flags');
            H.State.Layout.Row = 8;
            ot = uitable(g,'Tag','AnalysisThresholdOther','RowName',{},'ColumnEditable',false, ...
                'ColumnName',{'Method','Threshold','Status'},'Data',cell(0,3),'FontSize',10, ...
                'ColumnWidth',{'auto','auto','auto'});
            ot.Layout.Row = 9;
            mabr.ui.analysis.SeriesView.tip(ot,['Every built-in method''s threshold for this series, ' ...
                'from its stored per-level statistics (press Compare methods)']);
            mabr.ui.analysis.Compat.setSortable(ot,false);
            obj.tableMenu(fig,ot,'AnalysisThresholdOtherCopy');
            H.Other = ot;
            r10 = obj.rowGrid(g,10,{'1x',150});
            H.OtherNote = uilabel(r10,'Text','','FontColor',muted,'FontSize',10, ...
                'Tag','AnalysisThresholdOtherNote');
            H.CompareMethods = obj.button(r10,'Compare methods','AnalysisThresholdCompare', ...
                'Every built-in method on this series'' stored statistics (changes nothing)', ...
                @(~,~) obj.onCompareMethods());
            mabr.ui.analysis.Style.setButtonIcon(H.CompareMethods,'threshold','left');
            ap = uipanel(g,'BorderType','none','BackgroundColor',[1 1 1],'Tag','AnalysisThresholdAudiogram');
            ap.Layout.Row = 11;
            ax2 = axes('Parent',ap,'Units','normalized','Position',[0.14 0.27 0.80 0.66], ...
                'Tag','AnalysisThresholdAudiogramAxes','FontSize',9,'Box','off','TickDir','out');
            hold(ax2,'on');
            mabr.ui.hideAxesToolbar(ax2);
            disableDefaultInteractivity(ax2);
            mabr.ui.analysis.Style.pinAxes(ap,ax2,obj.AudiogramMargins);
            H.AudiogramPanel = ap;
            H.Audiogram = ax2;
            obj.plotMenu(fig,ax2,'AnalysisThresholdAudiogramMenu');
            H.AudiogramNote = uilabel(g,'Text','','WordWrap','on','FontColor',muted,'FontSize',10, ...
                'Tag','AnalysisThresholdAudiogramNote', ...
                'Tooltip','Series of this session with no frequency, and their thresholds');
            H.AudiogramNote.Layout.Row = 12;
            obj.Handles = H;
        end

        function buildPeaks(obj,fig)
            H = obj.Handles;
            panel = mabr.ui.analysis.Style.Panel;
            g = uigridlayout(H.SidePeaks,[7 1],'Padding',[6 6 6 6],'RowSpacing',4, ...
                'RowHeight',{24,'1x',34,34,34,24,190},'BackgroundColor',panel,'Tag','AnalysisPeaksGrid');
            r1 = obj.rowGrid(g,1,{'1x',72});
            H.PeaksShow = uidropdown(r1,'Items',cellstr(obj.ShowItems),'ItemsData',cellstr(obj.ShowData), ...
                'Value',char(obj.ViewLook.PeaksShow),'Tag','AnalysisPeaksShow', ...
                'Tooltip',['What the wave matrix shows: latency (ms re sound arrival when a delay ' ...
                'is set), peak-to-trough or baseline-to-peak amplitude (µV)'], ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onPeaksShow(s)));
            H.CopyMatrix = obj.button(r1,'Copy','AnalysisPeaksCopy', ...
                'Copy the wave matrix as tab-separated text',@(~,~) obj.copyMatrix());
            mabr.ui.analysis.Style.setButtonIcon(H.CopyMatrix,'copy','left');
            mt = uitable(g,'Tag','AnalysisPeaksMatrix','RowName',{},'ColumnEditable',false, ...
                'Data',cell(0,1),'ColumnName',{'Level'},'FontSize',11);
            mt.Layout.Row = 2;
            mabr.ui.analysis.Compat.setSortable(mt,false);
            mt.CellSelectionCallback = obj.viewWrap(@(s,e) obj.onMatrixSelect(s,e));
            mabr.ui.analysis.SeriesView.tip(mt,['One row per level (loudest first), one column per ' ...
                'wave: manual picks bold, absent "—", below threshold grey italic. Click a cell to ' ...
                'select that level and wave peak.']);
            obj.tableMenu(fig,mt,'AnalysisPeaksMatrixCopy');
            H.Matrix = mt;
            r3 = obj.rowGrid(g,3,{'1x','1x'});
            H.AutoPick = obj.button(r3,'Auto-pick series (p)','AnalysisPeaksAutoPick', ...
                'Pick the waves of this series again (manual picks stay) (p)', ...
                @(~,~) obj.runId("peak.autoPick"));
            mabr.ui.analysis.Style.setButtonIcon(H.AutoPick,'peaks','left');
            H.Retrack = obj.button(r3,'Re-track down (u)','AnalysisPeaksRetrack', ...
                ['Track the selected wave (all waves when none is selected) again from the ' ...
                'selected level down (u; Shift+U also drops the manual picks below)'], ...
                @(~,~) obj.runId("peak.retrack"));
            mabr.ui.analysis.Style.setButtonIcon(H.Retrack,'retrack','left');
            r4 = obj.rowGrid(g,4,{'1x',116});
            H.ClearPeaks = obj.button(r4,'Clear manual edits of this series','AnalysisPeaksClear', ...
                'Remove every manual pick and absence of this series and track it again', ...
                @(~,~) obj.Model.clearSeriesPeakEdits());
            mabr.ui.analysis.Style.setButtonIcon(H.ClearPeaks,'trash','left');
            H.Bootstrap = obj.button(r4,'Bootstrap CIs','AnalysisPeaksBootstrap', ...
                ['Bootstrap standard errors and intervals of the picks of this series (loads the ' ...
                'raw data)'],@(~,~) obj.Model.bootstrapPeaks());
            mabr.ui.analysis.Style.setButtonIcon(H.Bootstrap,'raster','left');
            r5 = obj.rowGrid(g,5,{'1x',116});
            H.FitWindows = obj.button(r5,'Use current picks as wave windows','AnalysisPeaksFitWindows', ...
                ['Make this series'' loudest-level picks the wave windows of its stimulus (project ' ...
                'settings; other sessions become out of date)'],@(~,~) obj.Model.usePicksAsWindows());
            H.Waves = obj.button(r5,'Waves…','AnalysisPeaksWaves', ...
                'Edit the wave windows (Settings, Peaks tab)',@(~,~) obj.openSettings("Peaks"));
            mabr.ui.analysis.Style.setButtonIcon(H.Waves,'gear','left');
            H.PlotKind = uidropdown(g,'Items',cellstr(obj.PlotItems),'ItemsData',cellstr(obj.PlotData), ...
                'Value',char(obj.ViewLook.PlotKind),'Tag','AnalysisPeaksPlotKind', ...
                'Tooltip',['The plot below: peak-to-trough amplitude against level (I/O), or ' ...
                'latency against level'], ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onPlotKind(s)));
            H.PlotKind.Layout.Row = 6;
            pp = uipanel(g,'BorderType','none','BackgroundColor',[1 1 1],'Tag','AnalysisPeaksPlot');
            pp.Layout.Row = 7;
            ax = axes('Parent',pp,'Units','normalized','Position',[0.15 0.20 0.78 0.66], ...
                'Tag','AnalysisPeaksPlotAxes','FontSize',9,'Box','off','TickDir','out');
            hold(ax,'on');
            mabr.ui.hideAxesToolbar(ax);
            disableDefaultInteractivity(ax);
            mabr.ui.analysis.Style.pinAxes(pp,ax,obj.PeakPlotMargins);
            H.PeakPlot = ax;
            obj.plotMenu(fig,ax,'AnalysisPeaksPlotMenu');
            obj.Handles = H;
        end

        % ---- rendering ---------------------------------------------------
        function renderAll(obj)
            m = obj.Model;
            obj.syncLook();
            S = m.Session;
            % one pass: each series' threshold row, conditions and label are
            % looked up once however many parts of the tab draw them
            obj.beginPass();
            done = onCleanup(@() obj.endPass());
            if isempty(S)
                obj.Geometry = [];
                obj.showEmpty(obj.TextNoSession);
                return
            end
            lp = m.levelParam();
            if lp == ""
                obj.Geometry = [];
                obj.showEmpty(obj.TextNoLevel,obj.settingsAction());
                return
            end
            sks = m.seriesKeys();
            nLev = zeros(numel(sks),1);
            for k = 1:numel(sks)
                nLev(k) = numel(obj.condsOf(sks(k)));
            end
            % (a series of ONE level -- an 80 dB suprathreshold run -- is
            % still shown: its trace and its peaks are curated here as any
            % other's; only the threshold has nothing to be decided from,
            % which the banner and the evidence plot say)
            if isempty(sks) || all(nLev < 1)
                obj.Geometry = [];
                obj.showEmpty(obj.TextNoSeries);
                return
            end
            sk = m.Selection.SeriesKey;
            if sk == "" || ~any(sks == sk)
                % (the SelectionChanged this raises draws the tab; a series
                % of several levels first, where there is one)
                k = find(nLev > 1,1);
                if isempty(k), k = find(nLev >= 1,1); end
                m.selectSeries(sks(k));
                return
            end
            obj.hideEmpty();
            obj.layoutColumns();
            G = obj.computeGeometry(sk);
            obj.Geometry = G;
            obj.renderList(sks);
            obj.syncCompare();
            obj.renderStack(G);
            obj.renderThreshold(G);
            obj.renderPeaksSide(G);
            obj.renderBanner();
        end

        function renderTraces(obj)
            % The stack again after a display change (polarity, normalise,
            % scale, spacing, window): nothing on the side changes.
            if ~obj.geometryValid()
                obj.renderAll();
                return
            end
            obj.syncLook();
            G = obj.computeGeometry(obj.Geometry.SeriesKey);
            obj.Geometry = G;
            obj.renderStack(G);
        end

        function renderCuration(obj)
            % A curation (accept, a manual value, no response, exclude, a
            % note) changes the series' threshold row -- and with it the
            % list, the dividers, the threshold side and which picks are
            % below threshold -- but no trace and no pick.
            if ~obj.geometryValid()
                obj.renderAll();
                return
            end
            m = obj.Model;
            obj.beginPass();
            done = onCleanup(@() obj.endPass());
            G = obj.Geometry;
            G.Row = obj.rowOf(m.Session,G.SeriesKey);
            G = obj.peakGeometry(G);
            obj.Geometry = G;
            obj.renderList(m.seriesKeys());
            obj.drawDividers(G);
            obj.renderThreshold(G);
            obj.renderPeaksSide(G);
            obj.renderBanner();
        end

        function renderPeaksOnly(obj)
            % A peak edit: the markers, the matrix and the peak plot.
            if ~obj.geometryValid()
                obj.renderAll();
                return
            end
            G = obj.peakGeometry(obj.Geometry);
            if ~isequal(G.Waves,obj.Geometry.Waves)
                obj.renderAll();       % the wave set changed: rebuild
                return
            end
            obj.Geometry = G;
            obj.drawMarkers(G);
            obj.drawCurrent(G);
            obj.renderPeaksSide(G);
        end

        function renderLevel(obj)
            if ~obj.geometryValid()
                obj.renderAll();
                return
            end
            G = obj.Geometry;
            obj.drawCurrent(G);
            obj.renderBanner();
        end

        function renderWave(obj)
            if ~obj.geometryValid()
                obj.renderAll();
                return
            end
            obj.drawCurrent(obj.Geometry);
        end

        function renderBanner(obj)
            % "Not analysed" and/or "only one level", above the stack.
            m = obj.Model;
            parts = strings(1,0);
            if ~isempty(m.Session) && ~obj.isEmptyShown()
                if m.Status.State == "not-analysed"
                    parts(end+1) = obj.TextNotAnalysed;
                end
                G = obj.Geometry;
                if ~isempty(G) && isscalar(G.Keys)
                    parts(end+1) = obj.TextSingleLevel;
                end
            end
            H = obj.Handles;
            txt = strjoin(parts,"   ·   ");
            on = txt ~= "";
            obj.put('banner_text',H.Banner,'Text',char(txt));
            obj.put('banner_vis',H.Banner,'Visible',matlab.lang.OnOffSwitchState(on));
            rh = {26,0,'1x',18};
            if on, rh{2} = 22; end
            obj.put('centre_rows',H.Centre,'RowHeight',rh);
        end

        function layoutColumns(obj)
            % {ListWidth(1),'1x',400}, or {ListWidth(2),'1x',340} when the
            % workspace is narrow.
            w = NaN;
            try
                p = obj.Parent.Parent;
                pos = p.Position;
                w = pos(3);
            catch
            end
            if ~isfinite(w)
                try
                    f = ancestor(obj.Parent,'figure');
                    w = f.Position(3);
                catch
                    w = 1200;
                end
            end
            narrow = w < 1000;
            cw = {obj.ListWidth(1),'1x',400};
            if narrow, cw = {obj.ListWidth(2),'1x',340}; end
            obj.put('grid_cols',obj.Handles.Grid,'ColumnWidth',cw);
            obj.put('strip_cols',obj.Handles.Strip,'ColumnWidth',obj.StripColumns(narrow));
        end

        function syncLook(obj)
            % The controls as the look says (after a pref or a configuration).
            look = obj.cleanLook(obj.ViewLook);
            obj.ViewLook = look;
            H = obj.Handles;
            obj.put('look_pol',H.Polarity,'Value',char(look.Polarity));
            obj.put('look_norm',H.Normalize,'Value',logical(look.Normalize));
            obj.put('look_show',H.PeaksShow,'Value',char(look.PeaksShow));
            obj.put('look_plot',H.PlotKind,'Value',char(look.PlotKind));
            tab = H.SideThreshold;
            if look.SideTab == "Peaks", tab = H.SidePeaks; end
            obj.put('look_side',H.Side,'SelectedTab',tab);
        end

        % ---- the series list ---------------------------------------------
        function renderList(obj,sks)
            m = obj.Model;
            S = m.Session;
            n = numel(sks);
            C = cell(n,5);
            nRev = 0;
            % (names shortened for the column: the mode as ⧉, a stimulus
            % word every series shares left out -- Style.compactSeriesLabels)
            labs = strings(n,1);
            for i = 1:n, labs(i) = obj.labelOf(sks(i)); end
            labs = mabr.ui.analysis.Style.compactSeriesLabels(labs);
            for i = 1:n
                row = obj.rowOf(S,sks(i));
                lab = char(labs(i));
                if isempty(row)
                    C(i,:) = {'',lab,'n/a','',''};
                    continue
                end
                d = mabr.ui.analysis.SeriesView.asText(mabr.ui.analysis.SeriesView.field(row,'Decision',""));
                flags = mabr.ui.analysis.SeriesView.asText(mabr.ui.analysis.SeriesView.field(row,'Flags',""));
                if d ~= "", nRev = nRev + 1; end
                C(i,:) = {char(mabr.ui.analysis.Style.decisionGlyph(d,flags)),lab, ...
                    char(mabr.ui.analysis.Style.formatThreshold(row)), ...
                    char(mabr.ui.analysis.SeriesView.fitText(row,false)), ...
                    char(mabr.ui.analysis.SeriesView.flagCodes(flags))};
            end
            H = obj.Handles;
            obj.ListKeys = reshape(sks,[],1);
            obj.put('list_data',H.List,'Data',C);
            obj.put('list_rev',H.Reviewed,'Text',sprintf('Reviewed %d/%d',nRev,n));
            k = find(sks == m.Selection.SeriesKey,1);
            if isempty(k), k = 0; end
            key = string(k) + "|" + n + "|" + strjoin(sks,",");
            if key ~= obj.ListStyle
                try
                    removeStyle(H.List);
                    if k > 0
                        addStyle(H.List,uistyle('BackgroundColor',obj.ColorCurrentRow, ...
                            'FontWeight','bold'),'row',k);
                    end
                catch me
                    mabr.log.vprintf(2,'Series view: list highlight (%s).',me.message);
                end
                obj.ListStyle = key;
            end
        end

        % ---- the stack -----------------------------------------------------
        function G = computeGeometry(obj,sk)
            % Everything the stack, the gestures and the side panels draw
            % from: the series' conditions (quietest first, so the loudest is
            % on top), their means as drawn, offsets, detection, counts, the
            % threshold row and the peaks.
            m = obj.Model;
            S = m.Session;
            look = obj.cleanLook(obj.ViewLook);
            G = struct();
            G.Session = S;
            G.SessionKey = m.SessionKey;
            G.SeriesKey = sk;
            lp = m.levelParam();
            G.LevelParam = lp;
            ck = reshape(string(obj.condsOf(sk)),[],1);
            C = S.Conditions;
            [~,rows] = ismember(ck,string(C.Key));
            lv = double(C.(char(lp))(rows));
            sg = mabr.ui.analysis.SeriesView.loudness(lp,S,m.Settings);
            [~,o] = sort(sg*lv);
            G.Keys = ck(o);
            G.Levels = lv(o);
            G.Rows = rows(o);
            G.Sign = sg;
            n = numel(G.Keys);
            st = S.Settings;
            if isempty(st), st = m.Settings; end
            G.Settings = st;
            T = obj.timeAxis();
            G.Offset = T.Offset;
            G.TimeRaw = double(S.Time(:));
            G.T = G.TimeRaw - G.Offset;
            pol = look.Polarity;
            p1 = pol; p2 = "";
            if pol == "overlay", p1 = "positive"; p2 = "negative"; end
            nT = numel(G.T);
            Y = NaN(nT,n); Y2 = NaN(nT,n);
            for i = 1:n
                try
                    y = S.conditionMean(G.Keys(i),p1);
                    Y(:,i) = double(y(:));
                    if p2 ~= ""
                        y2 = S.conditionMean(G.Keys(i),p2);
                        Y2(:,i) = double(y2(:));
                    end
                catch me
                    mabr.log.vprintf(2,'Series view: no mean for %s (%s).',G.Keys(i),me.message);
                end
            end
            G.Mean = Y;
            G.Mean2 = Y2;
            G.Count = NaN(n,1);
            if ismember('nClean',C.Properties.VariableNames)
                G.Count = double(C.nClean(G.Rows));
            end
            G.MinSweeps = double(st.MinSweeps);
            win = G.T >= obj.TimeWindow(1) & G.T <= obj.TimeWindow(2);
            if ~any(win), win = true(nT,1); end
            D = Y; D2 = Y2;
            if look.Normalize
                for i = 1:n
                    a = max(abs([Y(win,i); Y2(win,i)]),[],'omitnan');
                    if isfinite(a) && a > 0
                        D(:,i) = Y(:,i)/(2*a);
                        D2(:,i) = Y2(:,i)/(2*a);
                    end
                end
                base = 1;
            else
                use = G.Count >= G.MinSweeps;
                if ~any(use), use = true(n,1); end
                base = max(abs([Y(win,use); Y2(win,use)]),[],'all','omitnan');
                if ~(isfinite(base) && base > 0), base = 1e-6; end
            end
            G.Normalized = look.Normalize;
            G.Step = base*obj.SpacingScale;
            G.Disp = D*obj.AmpScale;
            G.Disp2 = D2*obj.AmpScale;
            G.Overlay = p2 ~= "";
            G.Offsets = (0:n-1).'*G.Step;
            G.Detected = NaN(n,1);
            if ismember('Detected',C.Properties.VariableNames)
                G.Detected = double(C.Detected(G.Rows));
            end
            G.Overridden = false(n,1);
            DO = S.DetectionOverrides;
            if istable(DO) && height(DO) > 0 && ismember('Key',DO.Properties.VariableNames)
                for i = 1:n
                    r = find(string(DO.Key) == G.Keys(i),1,'last');
                    G.Overridden(i) = ~isempty(r) && isfinite(double(DO.Value(r)));
                end
            end
            G.Row = obj.rowOf(S,sk);
            % the unit of the series' level axis -- which is the user's
            % Level parameter, and need not be a sound level (Frequency,
            % say): "Frequency (dB)" would misstate every threshold
            G.Unit = mabr.ui.analysis.SeriesView.levelUnitOf(lp,S);
            G.LevelLabel = G.LevelParam;
            if G.Unit ~= "", G.LevelLabel = G.LevelParam + " (" + G.Unit + ")"; end
            G = obj.peakGeometry(G);
        end

        function G = peakGeometry(obj,G)
            % The picks of the series, level by wave (raw latencies), and the
            % wave windows (shifted for the series' frequency) in DRAWN time:
            % the windows are in the recording's time like the picks, so they
            % take the same "- G.Offset" the traces and markers do.
            S = G.Session;
            n = numel(G.Keys);
            W = obj.seriesWindows(G);
            P = S.Peaks;
            Ps = table();
            if istable(P) && height(P) > 0 && all(ismember({'SeriesKey','Wave','Key'},P.Properties.VariableNames))
                Ps = P(string(P.SeriesKey) == G.SeriesKey,:);
            end
            if height(Ps) > 0
                waves = unique(string(Ps.Wave),'stable').';
                % in the windows' order where they name them
                wn = string({W.Name});
                [tf,loc] = ismember(waves,wn);
                ord = [loc(tf), numel(wn) + find(~tf)];
                [~,o] = sort(ord);
                waves = waves(o);
            else
                waves = string({W.Name});
            end
            nW = numel(waves);
            G.Waves = reshape(waves,1,[]);
            G.PeakLat = NaN(n,nW); G.TroughLat = NaN(n,nW);
            G.State = repmat("none",n,nW); G.TState = repmat("none",n,nW);
            G.AmpPT = NaN(n,nW); G.AmpBP = NaN(n,nW);
            G.LatSE = NaN(n,nW); G.AmpSE = NaN(n,nW);
            G.Below = false(n,nW);
            if height(Ps) > 0
                % one row per (level, wave): place each column at once (a
                % repeated pair keeps its last row, as a loop would)
                [~,i] = ismember(string(Ps.Key),G.Keys);
                [~,j] = ismember(string(Ps.Wave),G.Waves);
                use = i > 0 & j > 0;
                at = sub2ind([n nW],i(use),j(use));
                vn = string(Ps.Properties.VariableNames);
                G.PeakLat(at) = double(Ps.PeakLatency(use));
                if any(vn == "TroughLatency"),  G.TroughLat(at) = double(Ps.TroughLatency(use)); end
                if any(vn == "State"),          G.State(at) = string(Ps.State(use)); end
                if any(vn == "TroughState"),    G.TState(at) = string(Ps.TroughState(use)); end
                if any(vn == "AmpPT"),          G.AmpPT(at) = double(Ps.AmpPT(use)); end
                if any(vn == "AmpBP"),          G.AmpBP(at) = double(Ps.AmpBP(use)); end
                if any(vn == "LatencySE"),      G.LatSE(at) = double(Ps.LatencySE(use)); end
                if any(vn == "AmpPTSE"),        G.AmpSE(at) = double(Ps.AmpPTSE(use)); end
                if any(vn == "BelowThreshold"), G.Below(at) = logical(Ps.BelowThreshold(use)); end
            end
            % windows aligned with the waves (NaN where a wave has none), in
            % drawn time (raw - Offset), where the samples they searched are
            off = 0;
            if isfield(G,'Offset') && isfinite(G.Offset), off = G.Offset; end
            G.WinLo = NaN(1,nW); G.WinHi = NaN(1,nW); G.WinExp = NaN(1,nW); G.WinShift = zeros(1,nW);
            wn = string({W.Name});
            for j = 1:nW
                k = find(wn == G.Waves(j),1);
                if isempty(k), continue; end
                G.WinLo(j) = W(k).TMin - off;  G.WinHi(j) = W(k).TMax - off;
                G.WinExp(j) = W(k).Expected - off;
                try
                    G.WinShift(j) = double(W(k).LatencyShift);
                catch
                end
            end
        end

        function W = seriesWindows(~,G)
            % The enabled wave windows of the series' stimulus and frequency,
            % in the RECORDING's time (re the timing pulse), as Settings holds
            % them and Session.pickPeaks searches them (Peaks.wavesFor with
            % no offset). peakGeometry takes the latency offset off to draw
            % them.
            S = G.Session;
            st = G.Settings;
            C = S.Conditions;
            r = G.Rows(end);
            stim = "";
            if ismember('Stimulus',C.Properties.VariableNames), stim = string(C.Stimulus(r)); end
            freq = NaN;
            try
                fp = string(S.frequencyParam());
                if fp ~= "" && ismember(fp,string(C.Properties.VariableNames)) && isnumeric(C.(char(fp)))
                    freq = double(C.(char(fp))(r));
                end
            catch
            end
            try
                W = mabr.analysis.Peaks.wavesFor(st.Waves,stim,freq,OctaveShift=st.PeakOctaveShift, ...
                    RefFrequency=st.PeakRefFrequency);
                W = W([W.Enabled]);
            catch me
                mabr.log.vprintf(2,'Series view: wave windows unknown (%s).',me.message);
                W = mabr.analysis.Peaks.defaultWaves();
            end
        end

        function renderStack(obj,G)
            H = obj.Handles.Stack;
            ax = H.Axes;
            key = G.SessionKey + "|" + G.SeriesKey + "|" + strjoin(G.Keys,",") + "|" + ...
                strjoin(G.Waves,",");
            if key ~= obj.StackKey || ~isvalid(H.Final)
                if obj.canReuseStack(G)
                    obj.rekeyStack(G);      % same shape: the objects stay
                else
                    obj.rebuildStack(G);
                end
                obj.StackKey = key;
                H = obj.Handles.Stack;
            end
            n = numel(G.Keys);
            xl = obj.TimeWindow;
            % (headroom over the loudest trace for the wave names above its
            % peaks, which would otherwise run into the axes' subtitle)
            yl = [G.Offsets(1) - G.Step, G.Offsets(end) + 1.3*G.Step];
            obj.put('st_xlim',ax,'XLim',xl);
            obj.put('st_ylim',ax,'YLim',yl);
            obj.put('st_ytick',ax,'YTick',G.Offsets.');
            obj.put('st_yticklab',ax,'YTickLabel',cellstr(compose('%g',G.Levels)));
            obj.put('st_ylab',ax.YLabel,'String',char(G.LevelLabel));
            obj.labelTimeAxis(ax,Key="stack",Subtitle=true);
            % the response window (raw, re the onset) in drawn time
            rw = [NaN NaN];
            try
                rw = double(G.Session.ResponseWindow) - G.Offset;
            catch
            end
            obj.put('st_resp_x',H.Response,'XData',[rw(1) rw(2) rw(2) rw(1)].');
            obj.put('st_resp_y',H.Response,'YData',[yl(1) yl(1) yl(2) yl(2)].');
            % traces
            x = G.T.';
            for i = 1:n
                ln = H.Lines(char(G.Keys(i)));
                obj.put("st_l" + i + "_x",ln,'XData',x);
                obj.put("st_l" + i + "_y",ln,'YData',(G.Disp(:,i) + G.Offsets(i)).');
                ln2 = H.Lines2(char(G.Keys(i)));
                if G.Overlay
                    obj.put("st_n" + i + "_x",ln2,'XData',x);
                    obj.put("st_n" + i + "_y",ln2,'YData',(G.Disp2(:,i) + G.Offsets(i)).');
                end
                obj.put("st_n" + i + "_v",ln2,'Visible',matlab.lang.OnOffSwitchState(G.Overlay));
            end
            obj.drawMargin(G);
            obj.drawScaleBar(G);
            obj.drawDividers(G);
            obj.drawMarkers(G);
            obj.drawCurrent(G);
            obj.drawCompare(G);
        end

        function drawMargin(obj,G)
            % The right margin, level by level: the detection glyph (● ○,
            % ■ □ overridden) and the clean sweep count (amber, bold, below
            % MinSweeps), a fixed number of PIXELS past the axes, so a
            % narrow window does not run them into each other.
            H = obj.Handles.Stack;
            xl = obj.TimeWindow;
            dx = 0.0025*diff(xl);                 % per px before the axes is laid out
            if numel(obj.StackPx) == 2 && obj.StackPx(1) > 20
                dx = diff(xl)/obj.StackPx(1);
            end
            gx = xl(2) + obj.MarginGlyphPx*dx;
            nx = xl(2) + obj.MarginCountPx*dx;
            for i = 1:numel(G.Keys)
                det = G.Detected(i);
                if isnan(det)
                    gtxt = "–";
                else
                    gtxt = mabr.ui.analysis.Style.detectionGlyph(det == 1,G.Overridden(i));
                end
                obj.put("st_g" + i + "_p",H.Glyphs(i),'Position',[gx G.Offsets(i) 0]);
                obj.put("st_g" + i + "_s",H.Glyphs(i),'String',char(gtxt));
                ctxt = "";
                if isfinite(G.Count(i)), ctxt = string(G.Count(i)); end
                low = isfinite(G.Count(i)) && G.Count(i) < G.MinSweeps;
                cc = mabr.ui.analysis.Style.Muted;
                if low, cc = mabr.ui.analysis.Style.AccentText; end
                obj.put("st_c" + i + "_p",H.Counts(i),'Position',[nx G.Offsets(i) 0]);
                obj.put("st_c" + i + "_s",H.Counts(i),'String',char(ctxt));
                obj.put("st_c" + i + "_c",H.Counts(i),'Color',cc);
                obj.put("st_c" + i + "_w",H.Counts(i),'FontWeight', ...
                    char(mabr.ui.analysis.SeriesView.pick(low,"bold","normal")));
            end
        end

        function drawScaleBar(obj,G)
            % The stack's amplitude scale: a bar of a 1-2-5 number of
            % microvolts no taller than 0.8 of the row spacing, labelled
            % ("2 µV"), in the top-left corner -- over the loudest trace's
            % baseline, before the onset, where nothing else is drawn -- so
            % a response can be judged against the noise without a click.
            % Normalised, the traces share no scale, and the corner says so.
            H = obj.Handles.Stack;
            if ~isfield(H,'ScaleBar') || ~isgraphics(H.ScaleBar) || isempty(G) || isempty(G.Keys)
                return
            end
            xl = obj.TimeWindow;
            dx = 0.0025*diff(xl);                 % per px before the axes is laid out
            if numel(obj.StackPx) == 2 && obj.StackPx(1) > 20
                dx = diff(xl)/obj.StackPx(1);
            end
            x0 = xl(1) + 10*dx;
            yTop = G.Offsets(end) + 1.2*G.Step;   % under the axes' top (+1.3 steps)
            X = [NaN NaN];  Y = [NaN NaN];
            txt = "";  tx = x0;  ty = yTop - 0.15*G.Step;
            if G.Normalized
                txt = "each trace to its own peak";
            else
                perV = obj.AmpScale;              % data units per volt
                room = 0.8*G.Step/perV;           % volts the bar may span
                if isfinite(room) && room > 0
                    e = floor(log10(room));
                    mant = room/10^e;
                    f = [1 2 5];
                    v = max(f(f <= mant + 1e-12))*10^e;
                    len = v*perV;
                    X = [x0 x0];  Y = [yTop - len, yTop];
                    txt = string(sprintf('%g µV',round(v*1e6,12,'significant')));
                    tx = x0 + 5*dx;  ty = yTop - len/2;
                end
            end
            obj.put('st_sb_x',H.ScaleBar,'XData',X);
            obj.put('st_sb_y',H.ScaleBar,'YData',Y);
            obj.put('st_sb_p',H.ScaleText,'Position',[tx ty 0]);
            obj.put('st_sb_s',H.ScaleText,'String',char(txt));
        end

        function layoutStack(obj)
            % The stack axes inside its panel with margins in PIXELS
            % (StackMargins), so the tick labels, the level label and the
            % right margin's glyphs and counts keep their room however
            % narrow the window. Called from the panel's SizeChangedFcn --
            % which runs once the panel has a real size -- never from a
            % render, which may see a size not laid out yet.
            H = obj.Handles;
            try
                pos = getpixelposition(H.StackPanel);
            catch
                return
            end
            W = pos(3); Ht = pos(4);
            mg = obj.StackMargins;
            if ~(W > mg(1) + mg(3) + 40 && Ht > mg(2) + mg(4) + 40), return; end
            P = [mg(1)/W, mg(2)/Ht, 1 - (mg(1) + mg(3))/W, 1 - (mg(2) + mg(4))/Ht];
            obj.put('axpos_stack',H.Stack.Axes,'Position',P);
            obj.StackPx = [W - mg(1) - mg(3), Ht - mg(2) - mg(4)];
        end

        function drawDividers(obj,G)
            % The final threshold (green, "NR" above the loudest level for
            % no response) and the method's fit (dashed red) where it differs.
            H = obj.Handles.Stack;
            xl = obj.TimeWindow;
            row = G.Row;
            yF = NaN; yT = NaN; nr = false; showFit = false;
            if ~isempty(row)
                f  = @(nm,d) mabr.ui.analysis.SeriesView.field(row,nm,d);
                [yF,nr] = obj.dividerY(G,double(f('Final',NaN)),mabr.ui.analysis.SeriesView.asText(f('FinalCensored',"")), ...
                    double(f('FinalLo',NaN)),double(f('FinalHi',NaN)));
                [yT,~] = obj.dividerY(G,double(f('Threshold',NaN)),mabr.ui.analysis.SeriesView.asText(f('Censored',"")), ...
                    double(f('ThrLo',NaN)),double(f('ThrHi',NaN)));
                showFit = isfinite(yT) && ~(isfinite(yF) && abs(yT - yF) < 1e-9*max(1,abs(G.Step)));
            end
            obj.put('st_final_x',H.Final,'XData',xl);
            obj.put('st_final_y',H.Final,'YData',[yF yF]);
            obj.put('st_final_v',H.Final,'Visible',matlab.lang.OnOffSwitchState(isfinite(yF)));
            obj.put('st_nr_p',H.FinalText,'Position',[xl(1) + 0.01*diff(xl), yF, 0]);
            obj.put('st_nr_v',H.FinalText,'Visible',matlab.lang.OnOffSwitchState(nr && isfinite(yF)));
            obj.put('st_fit_x',H.Fit,'XData',xl);
            obj.put('st_fit_y',H.Fit,'YData',[yT yT]);
            obj.put('st_fit_v',H.Fit,'Visible',matlab.lang.OnOffSwitchState(showFit));
            % the grip: a green ◁ at the right end of the divider, which the
            % mouse drags (ThresholdDrag) -- hollow, and half way up the
            % stack (or on the fit), where there is no final threshold to
            % drag yet; none where nothing can be decided (one level, not
            % analysed)
            can = obj.canDragThreshold(G,false);
            gy = yF;
            if ~isfinite(gy) && can
                if isfinite(yT)
                    gy = yT;
                else
                    k = max(1,floor(numel(G.Offsets)/2));
                    gy = mean(G.Offsets(k:min(k+1,end)));
                end
            end
            on = can && isfinite(gy);
            face = mabr.ui.analysis.Style.FinalGreen;
            if ~isfinite(yF), face = [1 1 1]; end
            if isfield(H,'Grip') && isgraphics(H.Grip)
                obj.put('st_grip_x',H.Grip,'XData',xl(2));
                obj.put('st_grip_y',H.Grip,'YData',gy);
                obj.put('st_grip_f',H.Grip,'MarkerFaceColor',face);
                obj.put('st_grip_v',H.Grip,'Visible',matlab.lang.OnOffSwitchState(on));
            end
            obj.DividerAt = struct('SeriesKey',G.SeriesKey,'Line',yF,'HasLine',isfinite(yF), ...
                'Grip',gy,'On',on);
        end

        function rebuildStack(obj,G)
            % New objects for a new series (or wave set), in drawing order:
            % windows, traces, compare, dividers, absences, markers, the
            % selected point, labels, margins.
            H = obj.Handles.Stack;
            ax = H.Axes;
            obj.deleteStackObjects();
            obj.forgetWritten('st_');
            n = numel(G.Keys);
            nW = numel(G.Waves);
            off = {'HitTest','off','PickableParts','none'};
            H.Windows = containers.Map('KeyType','char','ValueType','any');
            for j = 1:nW
                c = mabr.ui.analysis.Style.waveColor(G.Waves(j));
                H.Windows(char(G.Waves(j))) = patch(ax,NaN(4,1),NaN(4,1),c,'EdgeColor','none', ...
                    'FaceAlpha',0.13,'Visible','off','Tag','SeriesWaveWindow', ...
                    'DisplayName',char("window " + G.Waves(j)),off{:});
            end
            H.Lines = containers.Map('KeyType','char','ValueType','any');
            H.Lines2 = containers.Map('KeyType','char','ValueType','any');
            H.LineList = gobjects(n,1);
            H.LineList2 = gobjects(n,1);
            for i = 1:n
                nm = char(strtrim(compose('%g',G.Levels(i)) + " " + G.Unit));
                ln = line(ax,NaN,NaN,'Color',obj.ColorDetected,'LineWidth',1,'LineStyle','-', ...
                    'Marker','none','Tag','SeriesTrace','DisplayName',nm,'UserData',G.Keys(i),off{:});
                H.Lines(char(G.Keys(i))) = ln;
                ln2 = line(ax,NaN,NaN,'Color',obj.ColorNegative,'LineWidth',1,'Visible','off', ...
                    'LineStyle','-','Marker','none','Tag','SeriesTraceNegative', ...
                    'DisplayName',[nm ' (−)'],'UserData',G.Keys(i),off{:});
                H.Lines2(char(G.Keys(i))) = ln2;
                H.LineList(i) = ln;
                H.LineList2(i) = ln2;
            end
            H.WaveSet = reshape(G.Waves,1,[]);
            H.Compare = line(ax,NaN,NaN,'Color',obj.ColorCompare,'LineStyle','--','LineWidth',1, ...
                'Marker','none','Visible','off','Tag','SeriesCompare','DisplayName','compare',off{:});
            H.Final = line(ax,NaN,NaN,'Color',mabr.ui.analysis.Style.FinalGreen,'LineWidth',2, ...
                'LineStyle','-','Marker','none','Visible','off','Tag','SeriesFinal', ...
                'DisplayName','final threshold',off{:});
            H.FinalText = text(ax,NaN,NaN,'NR','Color',mabr.ui.analysis.Style.FinalGreen, ...
                'FontWeight','bold','FontSize',9,'VerticalAlignment','bottom','Visible','off', ...
                'Tag','SeriesFinalText',off{:});
            H.Fit = line(ax,NaN,NaN,'Color',mabr.ui.analysis.Style.FitRed,'LineStyle','--', ...
                'Marker','none','LineWidth',1.5,'Visible','off','Tag','SeriesFit','DisplayName','fit',off{:});
            % (the divider's grip: drawing, not data -- hidden handles, so
            % Copy data passes it by, and an exported figure drops it)
            H.Grip = line(ax,NaN,NaN,'LineStyle','none','Marker','<','MarkerSize',8, ...
                'MarkerEdgeColor',mabr.ui.analysis.Style.FinalGreen,'LineWidth',1.2, ...
                'MarkerFaceColor',mabr.ui.analysis.Style.FinalGreen,'Visible','off','Clipping','off', ...
                'Tag','SeriesThresholdGrip','HandleVisibility','off',off{:});
            H.Absent = containers.Map('KeyType','char','ValueType','any');
            H.Markers = containers.Map('KeyType','char','ValueType','any');
            for j = 1:nW
                w = G.Waves(j);
                c = mabr.ui.analysis.Style.waveColor(w);
                H.Absent(char(w)) = line(ax,NaN,NaN,'LineStyle','none','Marker','x', ...
                    'Color',obj.ColorAbsent,'MarkerSize',8,'LineWidth',1.5,'Tag','SeriesAbsent', ...
                    'DisplayName',char(w + " absent"),off{:});
                H.Markers(char(w + "|P")) = line(ax,NaN,NaN,'LineStyle','none','Marker','^', ...
                    'MarkerSize',6,'MarkerFaceColor',c,'MarkerEdgeColor',0.6*c,'Color',c, ...
                    'Tag','SeriesMarker','DisplayName',char(w + " peak"),off{:});
                H.Markers(char(w + "|N")) = line(ax,NaN,NaN,'LineStyle','none','Marker','v', ...
                    'MarkerSize',6,'MarkerFaceColor','none','MarkerEdgeColor',c,'Color',c, ...
                    'LineWidth',1,'Tag','SeriesMarker','DisplayName',char(w + " trough"),off{:});
            end
            H.Selected = line(ax,NaN,NaN,'LineStyle','none','Marker','^','MarkerSize',11, ...
                'MarkerEdgeColor',[0 0 0],'LineWidth',1.5,'Visible','off','Tag','SeriesSelectedPoint', ...
                'DisplayName','selected point',off{:});
            lab = gobjects(nW,1);
            for j = 1:nW
                lab(j) = text(ax,NaN,NaN,char(G.Waves(j)),'Color',0.8*mabr.ui.analysis.Style.waveColor(G.Waves(j)), ...
                    'FontSize',9,'FontWeight','bold','HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom','Visible','off','Tag','SeriesWaveLabel',off{:});
            end
            H.Labels = lab;
            gl = gobjects(n,1); cn = gobjects(n,1);
            for i = 1:n
                gl(i) = text(ax,NaN,NaN,'','FontSize',10,'Clipping','off','Color',mabr.ui.analysis.Style.Ink, ...
                    'VerticalAlignment','middle','Tag','SeriesGlyph',off{:});
                cn(i) = text(ax,NaN,NaN,'','FontSize',9,'Clipping','off','VerticalAlignment','middle', ...
                    'Tag','SeriesCount',off{:});
            end
            H.Glyphs = gl;
            H.Counts = cn;
            % the amplitude scale: a vertical bar in the top-left corner,
            % over the loudest trace's baseline (no wave is there), hidden
            % handles so Copy data passes it by
            H.ScaleBar = line(ax,NaN,NaN,'Color',mabr.ui.analysis.Style.Ink,'LineWidth',1.5, ...
                'Marker','none','Tag',obj.ScaleBarTag,'HandleVisibility','off',off{:});
            H.ScaleText = text(ax,NaN,NaN,'','FontSize',9,'Color',mabr.ui.analysis.Style.Ink, ...
                'HorizontalAlignment','left','VerticalAlignment','middle','Interpreter','none', ...
                'Tag','SeriesScaleText','HandleVisibility','off',off{:});
            obj.Handles.Stack = H;
        end

        function tf = canReuseStack(obj,G)
            % Another series of the same shape -- as many levels, the same
            % waves -- reuses the stack's objects (rebuilding them is most
            % of what switching series would cost).
            H = obj.Handles.Stack;
            tf = isgraphics(H.Final) && isgraphics(H.ScaleBar) && isgraphics(H.Grip) && ...
                numel(H.LineList) == numel(G.Keys) && ...
                all(isgraphics(H.LineList)) && all(isgraphics(H.LineList2)) && ...
                isequal(H.WaveSet,reshape(G.Waves,1,[]));
        end

        function rekeyStack(obj,G)
            % The traces of the stack under this series' condition keys.
            H = obj.Handles.Stack;
            H.Lines = containers.Map('KeyType','char','ValueType','any');
            H.Lines2 = containers.Map('KeyType','char','ValueType','any');
            for i = 1:numel(G.Keys)
                k = char(G.Keys(i));
                H.Lines(k) = H.LineList(i);
                H.Lines2(k) = H.LineList2(i);
                nm = char(strtrim(compose('%g',G.Levels(i)) + " " + G.Unit));
                obj.put("st_l" + i + "_dn",H.LineList(i),'DisplayName',nm);
                obj.put("st_l" + i + "_ud",H.LineList(i),'UserData',G.Keys(i));
                obj.put("st_n" + i + "_dn",H.LineList2(i),'DisplayName',[nm ' (−)']);
                obj.put("st_n" + i + "_ud",H.LineList2(i),'UserData',G.Keys(i));
            end
            obj.Handles.Stack = H;
        end

        function deleteStackObjects(obj)
            H = obj.Handles.Stack;
            objs = gobjects(0,1);
            for f = ["Windows","Lines","Lines2","Absent","Markers"]
                M = H.(f);
                v = values(M);
                for k = 1:numel(v), objs(end+1,1) = v{k}; end %#ok<AGROW>
            end
            objs = [objs; H.Compare(:); H.Final(:); H.FinalText(:); H.Fit(:); H.Grip(:); H.Selected(:); ...
                H.Labels(:); H.Glyphs(:); H.Counts(:); H.ScaleBar(:); H.ScaleText(:)];
            objs = objs(isgraphics(objs));
            delete(objs);
        end

        function [y,nr] = dividerY(~,G,v,c,lo,hi)
            % Where a threshold divides the stack: an interval half way
            % between its rows, a point at its interpolated height, "no
            % response" above the loudest row (marked NR), "all respond"
            % below the quietest. NaN when there is nothing to draw
            % (excluded, n/a). On an attenuation axis the censoring sides
            % describe the NUMBERS (SeriesThreshold swaps them), so "left"
            % is no response there (censorMeaning).
            % A censored threshold stands half a row beyond the row of its
            % BOUND (FinalLo of "> 80", FinalHi of "≤ 70"), not beyond the
            % extreme row: a level the method left out (too few sweeps) may
            % lie past the bound, and a divider under it would read as "that
            % level responds". Without a bound, the extreme row.
            y = NaN; nr = false;
            n = numel(G.Levels);
            if n == 0, return; end
            at = @(L) mabr.ui.analysis.SeriesView.levelY(G,L);
            [noResp,allResp] = mabr.ui.analysis.SeriesView.censorMeaning(c,G.Sign);
            b = lo;                                     % "right": above lo
            if c == "left", b = hi; end                 % "left": at or below hi
            if ~isfinite(b), b = v; end
            switch c
                case "interval"
                    if isfinite(lo) && isfinite(hi), y = (at(lo) + at(hi))/2; end
                case "none"
                    if isfinite(v)
                        y = at(v);
                    end
                otherwise
                    if noResp
                        y = G.Offsets(end) + G.Step/2;      % the loudest is on top
                        if isfinite(b), y = at(b) + G.Step/2; end
                        nr = true;
                    elseif allResp
                        y = G.Offsets(1) - G.Step/2;
                        if isfinite(b), y = at(b) - G.Step/2; end
                    end
            end
            if isfinite(y)
                y = min(max(y,G.Offsets(1) - G.Step/2),G.Offsets(end) + G.Step/2);
            end
        end

        function drawMarkers(obj,G)
            % One line per wave and kind, one point per level; × for absent.
            H = obj.Handles.Stack;
            n = numel(G.Keys);
            for j = 1:numel(G.Waves)
                w = G.Waves(j);
                for kind = ["P","N"]
                    key = char(w + "|" + kind);
                    if ~isKey(H.Markers,key), continue; end
                    if kind == "P", lat = G.PeakLat(:,j); else, lat = G.TroughLat(:,j); end
                    x = lat - G.Offset;
                    y = NaN(n,1);
                    for i = 1:n
                        if isfinite(x(i)), y(i) = obj.traceValue(G,i,x(i)) + G.Offsets(i); end
                    end
                    x(~isfinite(y)) = NaN;
                    obj.put("st_m" + j + kind + "_x",H.Markers(key),'XData',x.');
                    obj.put("st_m" + j + kind + "_y",H.Markers(key),'YData',y.');
                end
                % absent: a grey cross at the expected time of that level
                ab = G.State(:,j) == "absent";
                xa = NaN(n,1); ya = NaN(n,1);
                if any(ab) && isfinite(G.WinExp(j))
                    top = max(G.Sign*G.Levels);
                    dL = top - G.Sign*G.Levels;
                    xa(ab) = G.WinExp(j) + G.WinShift(j)*dL(ab);
                    ya(ab) = G.Offsets(ab);
                end
                if isKey(H.Absent,char(w))
                    obj.put("st_a" + j + "_x",H.Absent(char(w)),'XData',xa.');
                    obj.put("st_a" + j + "_y",H.Absent(char(w)),'YData',ya.');
                end
            end
        end

        function drawCurrent(obj,G)
            % What follows the selected level and point: line styles, the
            % wave windows on that level, the selected marker, wave labels.
            m = obj.Model;
            H = obj.Handles.Stack;
            i = obj.currentIndex(G);
            n = numel(G.Keys);
            for k = 1:n
                ln = H.Lines(char(G.Keys(k)));
                det = G.Detected(k);
                if k == i
                    c = [0 0 0]; w = 2; ls = '-';
                elseif isnan(det) || det == 1
                    c = obj.ColorDetected; w = 1; ls = '-';
                else
                    c = obj.ColorUndetected; w = 0.9; ls = '--';
                end
                obj.put("st_l" + k + "_c",ln,'Color',c);
                obj.put("st_l" + k + "_w",ln,'LineWidth',w);
                obj.put("st_l" + k + "_s",ln,'LineStyle',ls);
                ln2 = H.Lines2(char(G.Keys(k)));
                obj.put("st_n" + k + "_w",ln2,'LineWidth',w);
                obj.put("st_n" + k + "_s",ln2,'LineStyle',ls);
            end
            % the search windows, on the selected level only, in drawn time
            % (peakGeometry: written and searched in the recording's time,
            % less the latency offset like the traces) and moved later by each wave's
            % latency shift per dB below the loudest level -- where the
            % tracker expects the wave at this level (the same rule places
            % an absent wave's cross)
            for j = 1:numel(G.Waves)
                p = H.Windows(char(G.Waves(j)));
                ok = isfinite(i) && isfinite(G.WinLo(j)) && isfinite(G.WinHi(j));
                if ok
                    yc = G.Offsets(i);
                    sh = G.WinShift(j)*(max(G.Sign*G.Levels) - G.Sign*G.Levels(i));
                    if ~isfinite(sh), sh = 0; end
                    lo = G.WinLo(j) + sh;  hi = G.WinHi(j) + sh;
                    obj.put("st_w" + j + "_x",p,'XData',[lo hi hi lo].');
                    obj.put("st_w" + j + "_y",p,'YData',(yc + G.Step*[-0.5 -0.5 0.5 0.5]).');
                end
                obj.put("st_w" + j + "_v",p,'Visible',matlab.lang.OnOffSwitchState(ok));
            end
            % the selected point
            wave = m.Selection.Wave;
            kind = m.Selection.Kind;
            j = find(G.Waves == wave,1);
            px = NaN; py = NaN;
            if isfinite(i) && ~isempty(j), [px,py] = obj.pointXY(G,i,j,kind); end
            on = isfinite(px) && isfinite(py);
            if on
                c = mabr.ui.analysis.Style.waveColor(wave);
                mk = '^'; if kind == "N", mk = 'v'; end
                obj.put('st_sel_x',H.Selected,'XData',px);
                obj.put('st_sel_y',H.Selected,'YData',py);
                obj.put('st_sel_m',H.Selected,'Marker',mk);
                obj.put('st_sel_c',H.Selected,'MarkerFaceColor',c);
            end
            obj.put('st_sel_v',H.Selected,'Visible',matlab.lang.OnOffSwitchState(on));
            % wave names over the selected level's peaks
            for j = 1:numel(G.Waves)
                lx = NaN; ly = NaN;
                if isfinite(i), [lx,ly] = obj.pointXY(G,i,j,"P"); end
                ok = isfinite(lx) && isfinite(ly);
                if ok
                    obj.put("st_t" + j + "_p",H.Labels(j),'Position',[lx, ly + 0.12*G.Step, 0]);
                end
                obj.put("st_t" + j + "_v",H.Labels(j),'Visible',matlab.lang.OnOffSwitchState(ok));
            end
        end

        function drawCompare(obj,G)
            % Another session's means of the same series, grey dashes.
            H = obj.Handles.Stack;
            ln = H.Compare;
            X = NaN; Y = NaN;
            on = false;
            if obj.CompareKey ~= "" && ~obj.Model.BlindReview
                Sc = obj.compareSession(obj.CompareKey);
                if ~isempty(Sc)
                    try
                        [X,Y] = obj.compareData(G,Sc);
                        on = any(isfinite(Y));
                    catch me
                        mabr.log.vprintf(2,'Series view: compare overlay (%s).',me.message);
                    end
                end
            end
            obj.put('st_cmp_x',ln,'XData',reshape(X,1,[]));
            obj.put('st_cmp_y',ln,'YData',reshape(Y,1,[]));
            obj.put('st_cmp_v',ln,'Visible',matlab.lang.OnOffSwitchState(on));
        end

        function [X,Y] = compareData(obj,G,Sc)
            X = zeros(0,1); Y = zeros(0,1);
            lp = G.LevelParam;
            ck = reshape(string(Sc.seriesConditions(G.SeriesKey)),[],1);
            if isempty(ck) || ~ismember(char(lp),Sc.Conditions.Properties.VariableNames), return; end
            [~,rows] = ismember(ck,string(Sc.Conditions.Key));
            lv = double(Sc.Conditions.(char(lp))(rows));
            off = 0;
            try
                off = double(Sc.LatencyOffset);
            catch
            end
            t = double(Sc.Time(:)) - off;
            win = t >= obj.TimeWindow(1) & t <= obj.TimeWindow(2);
            pol = obj.cleanLook(obj.ViewLook).Polarity;
            if pol == "overlay", pol = "balanced"; end
            for i = 1:numel(G.Keys)
                k = find(lv == G.Levels(i),1);
                if isempty(k), continue; end
                y = double(Sc.conditionMean(ck(k),pol));
                y = y(:);
                if G.Normalized
                    a = max(abs(y(win)),[],'omitnan');
                    if isfinite(a) && a > 0, y = y/(2*a); end
                end
                X = [X; t; NaN]; %#ok<AGROW>
                Y = [Y; y*obj.AmpScale + G.Offsets(i); NaN]; %#ok<AGROW>
            end
        end

        function S = compareSession(obj,key)
            k = char(key);
            if isKey(obj.CompareCache,k)
                S = obj.CompareCache(k);
                return
            end
            try
                info = obj.Model.sessionInfo(key);
                S = mabr.analysis.Session.fromResults(info.ResultsFile,Verbose=false);
                obj.CompareCache(k) = S;
            catch me
                mabr.log.vprintf(1,'Series view: cannot compare with %s (%s).',key,me.message);
                S = [];
            end
        end

        function syncCompare(obj)
            % The compare list: the same subject's other analysed sessions.
            m = obj.Model;
            H = obj.Handles;
            if m.BlindReview
                obj.put('cmp_vis',H.Compare,'Visible','off');
                if obj.CompareKey ~= ""
                    % (or the dropdown would name a session the overlay no
                    % longer shows once the review ends)
                    H.Compare.Value = '';
                    obj.CompareKey = "";
                end
                return
            end
            obj.put('cmp_vis',H.Compare,'Visible','on');
            if obj.CompareFor == m.SessionKey, return; end
            items = {'Compare with: none'}; data = {''};
            try
                info = m.sessionInfo(m.SessionKey);
                T = m.Catalog.Sessions;
                keys = string(T.Key);
                same = string(T.Subject) == string(info.Subject) & ~ismember(keys,info.Members) & ...
                    keys ~= m.SessionKey;
                for r = reshape(find(same),1,[])
                    if m.hasResults(keys(r))
                        items{end+1} = char("Compare with: " + string(T.Name(r))); %#ok<AGROW>
                        data{end+1} = char(keys(r)); %#ok<AGROW>
                    end
                end
            catch me
                mabr.log.vprintf(2,'Series view: no compare list (%s).',me.message);
            end
            obj.forgetWritten('cmp_list');
            % (sessions read for another session's list: may be out of date
            % by now, and each is a results file's worth of memory)
            obj.CompareCache = containers.Map('KeyType','char','ValueType','any');
            H.Compare.Items = items;
            H.Compare.ItemsData = data;
            H.Compare.Value = '';
            obj.CompareKey = "";
            obj.CompareFor = m.SessionKey;
        end

        % ---- threshold side ----------------------------------------------
        function renderThreshold(obj,G)
            m = obj.Model;
            H = obj.Handles;
            obj.syncMethod();
            try
                def = string(m.Settings.thresholdDefinition());
            catch me
                def = "The method cannot be resolved: " + string(me.message);
            end
            obj.put('thr_def',H.Definition,'Text',char(def));
            row = G.Row;
            has = ~isempty(row);
            % one level is no level series: nothing to decide a threshold
            % from, so only Exclude and the note stay (and the evidence plot
            % says why, renderEvidence); the peaks are curated as ever
            single = isscalar(G.Keys);
            for f = ["Accept","AtLevel","NoResponse","AllRespond","Clear","SetValue","CompareMethods"]
                obj.put("thr_en_" + f,H.(f),'Enable',matlab.lang.OnOffSwitchState(has && ~single));
            end
            for f = ["Exclude","Note"]
                obj.put("thr_en_" + f,H.(f),'Enable',matlab.lang.OnOffSwitchState(has));
            end
            if has
                obj.put('thr_state',H.State,'Text',char(mabr.ui.analysis.SeriesView.stateText(row)));
            else
                obj.put('thr_state',H.State,'Text','Not analysed: no threshold yet.');
            end
            % the value field follows the series' Final -- on a new series,
            % and after a re-fit or a decision while it still holds what
            % was put there -- but never over a value the user typed
            v = NaN;
            if has, v = double(mabr.ui.analysis.SeriesView.field(row,'Final',NaN)); end
            if ~isfinite(v), v = m.Selection.Level; end
            if ~isfinite(v), v = 0; end
            v = round(v*10)/10;
            fresh = obj.ValueFor ~= G.SessionKey + "|" + G.SeriesKey;
            untouched = isequal(H.ValueField.Value,obj.ValueSeed);
            if fresh || (untouched && v ~= obj.ValueSeed)
                H.ValueField.Value = v;
                obj.ValueSeed = v;
                obj.ValueFor = G.SessionKey + "|" + G.SeriesKey;
            end
            if obj.OtherFor ~= G.SessionKey + "|" + G.SeriesKey
                obj.put('thr_other',H.Other,'Data',cell(0,3));
                obj.put('thr_other_note',H.OtherNote,'Text','');
                obj.OtherFor = "";
            end
            obj.renderEvidence(G);
            obj.renderAudiogram(G);
            obj.applyThresholdRows();
            obj.placeSidePlots();
        end

        function syncMethod(obj)
            % The project's method, its custom row and the criterion unit.
            m = obj.Model;
            H = obj.Handles;
            s = m.Settings;
            M = mabr.analysis.SeriesThreshold.methods();
            ids = string({M.Id});
            % the labels carry the settings' numbers (alpha, consecutive
            % levels): resolved again only when those numbers change
            mk = strjoin(string({sprintf('%.17g',s.Alpha),sprintf('%.17g',s.MinConsecutive), ...
                char(s.ThresholdMetric),char(s.ThresholdModel),char(s.CriterionMode), ...
                sprintf('%.17g',s.Criterion)}),"|");
            if mk ~= obj.MethodKey || numel(obj.MethodLabels) ~= numel(M)
                labels = string({M.Label});
                for k = 1:numel(M)
                    try
                        r = mabr.analysis.SeriesThreshold.resolve(ids(k),s);
                        labels(k) = string(r.Label);
                    catch
                    end
                end
                crit = s.Criterion;
                try
                    r = mabr.analysis.SeriesThreshold.resolve("custom",s);
                    crit = r.Criterion;
                    unit = string(r.CriterionUnit);
                catch
                    unit = mabr.ui.analysis.SeriesView.unitOf(s.CriterionMode,s.ThresholdMetric);
                end
                obj.MethodKey = mk;
                obj.MethodLabels = labels;
                obj.MethodCustom = struct('Criterion',crit,'Unit',unit);
            end
            labels = obj.MethodLabels;
            % (ItemsData first: a dropdown refuses fewer data than items)
            obj.put('mth_data',H.Method,'ItemsData',cellstr(ids));
            obj.put('mth_items',H.Method,'Items',cellstr(labels));
            cur = string(s.ThresholdMethod);
            if ~any(ids == cur), cur = ids(1); end
            obj.put('mth_value',H.Method,'Value',char(cur));
            obj.put('mth_tip',H.Method,'Tooltip',char("The threshold method of this PROJECT: " + ...
                labels(ids == cur) + ". Changing it re-fits this session at once; every other " + ...
                "session becomes out of date and is re-run only when you press Analyse there."));
            custom = cur == "custom";
            obj.CustomRowOn = custom;
            obj.applyThresholdRows();
            obj.put('mth_custom_vis',H.CustomRow,'Visible',matlab.lang.OnOffSwitchState(custom));
            obj.put('mth_metric',H.Metric,'Value',char(s.ThresholdMetric));
            obj.put('mth_model',H.ModelDrop,'Value',char(s.ThresholdModel));
            crit = obj.MethodCustom.Criterion;
            unit = obj.MethodCustom.Unit;
            ct = "";
            if isfinite(crit), ct = string(sprintf('%g',crit)); end
            obj.put('mth_crit',H.Criterion,'Value',char(ct));
            obj.put('mth_unit',H.CriterionUnit,'Text',char(unit));
        end

        function renderEvidence(obj,G)
            % What the method decided from, level by level. Along the bottom
            % a band of its own holds the sweep count of each level, so the
            % counts never sit on a marker (a p of 1 is drawn at the bottom
            % of the data area, just above the band).
            ax = obj.Handles.Evidence;
            obj.dropObjs("EvObjs");
            obj.EvidenceInfo = [];
            if isscalar(G.Keys)
                % one level: there is no threshold to estimate, so no
                % evidence either -- the plot says so in its place
                obj.put('ev_vis',ax,'Visible','off');
                obj.addEv(text(ax,0.5,0.5,char(obj.TextSingleLevel),'Units','normalized', ...
                    'HorizontalAlignment','center','VerticalAlignment','middle','FontSize',10, ...
                    'Color',mabr.ui.analysis.Style.Muted,'Tag','EvidenceSingleLevel'));
                return
            end
            obj.put('ev_vis',ax,'Visible','on');
            S = G.Session;
            C = S.Conditions;
            [lv,o] = sort(G.Levels);
            rows = G.Rows(o);
            det = G.Detected(o);
            ov = G.Overridden(o);
            nn = G.Count(o);
            step = 10;
            if numel(lv) > 1, step = median(diff(lv)); end
            if ~(isfinite(step) && step > 0), step = 10; end
            xl = [lv(1) - step/2, lv(end) + step/2];
            obj.put('ev_xlim',ax,'XLim',xl);
            obj.put('ev_xtick',ax,'XTick',reshape(unique(lv),1,[]));
            obj.put('ev_xlab',ax.XLabel,'String',char(G.LevelLabel));
            row = G.Row;
            if isempty(row)
                obj.put('ev_ylim',ax,'YLim',[0 1]);
                obj.put('ev_ylab',ax.YLabel,'String','');
                obj.addEv(text(ax,mean(xl),0.5,'Not analysed','HorizontalAlignment','center', ...
                    'Color',mabr.ui.analysis.Style.Muted,'Tag','EvidenceEmpty'));
                return
            end
            f = @(nm,d) mabr.ui.analysis.SeriesView.field(row,nm,d);
            fit = f('Fit',[]);
            if iscell(fit), if isempty(fit), fit = []; else, fit = fit{1}; end, end
            metric = mabr.ui.analysis.SeriesView.asText(f('Metric',"detection"));
            mode = "";
            if isstruct(fit) && isfield(fit,'CriterionMode'), mode = string(fit.CriterionMode); end
            if mode == ""
                try
                    r = mabr.analysis.SeriesThreshold.resolve(mabr.ui.analysis.SeriesView.asText(f('Method',"")),G.Settings);
                    mode = string(r.CriterionMode);
                catch
                    mode = "p";
                end
            end
            isP = ismember(metric,mabr.analysis.SeriesThreshold.PMetrics) && ismember(mode,["p","probability"]);
            crit = double(f('Criterion',NaN));
            blue = mabr.ui.analysis.Style.DataBlue;
            if isP
                % left: detected or not (squares where a person decided);
                % the second scale is drawn over pr, above the counts' band
                pr = [-0.45 1.3];
                ylL = [-0.80 1.3];
                obj.put('ev_ylim',ax,'YLim',ylL);
                obj.put('ev_ytick',ax,'YTick',[0 1]);
                obj.put('ev_yticklab',ax,'YTickLabel',{'no','yes'});
                obj.put('ev_ylab',ax.YLabel,'String','Detected');
                d1 = det == 1;
                sets = {d1 & ~ov, 'o', blue; ~d1 & ~ov, 'o', 'none'; d1 & ov, 's', blue; ~d1 & ov, 's', 'none'};
                tags = ["EvidenceDetected","EvidenceUndetected","EvidenceOverrideOn","EvidenceOverrideOff"];
                for k = 1:4
                    sel = sets{k,1} & isfinite(det);
                    if ~any(sel), continue; end
                    obj.addEv(line(ax,lv(sel),double(d1(sel)),'LineStyle','none','Marker',sets{k,2}, ...
                        'MarkerSize',7,'MarkerEdgeColor',blue,'MarkerFaceColor',sets{k,3},'Tag',char(tags(k)), ...
                        'DisplayName',char(tags(k))));
                end
                if isstruct(fit) && isfield(fit,'CurveX') && ~isempty(fit.CurveX) && mode == "probability"
                    obj.addEv(line(ax,double(fit.CurveX(:)),double(fit.CurveY(:)),'Color',blue, ...
                        'LineWidth',1.2,'LineStyle','-','Marker','none','Tag','EvidenceCurve', ...
                        'DisplayName','fitted probability'));
                end
                if mode == "probability" && isfinite(crit)
                    obj.addEv(line(ax,xl,[crit crit],'Color',mabr.ui.analysis.Style.Muted,'LineStyle',':', ...
                        'Marker','none','Tag','EvidenceCriterion','DisplayName','criterion'));
                end
                % right: -log10 p and alpha (power: F against its null's 95th
                % percentile), on a scale of their own mapped onto the
                % axes' height; each line keeps its values in UserData
                alpha = 0.05;
                try
                    alpha = double(G.Settings.Alpha);
                catch
                end
                orange = mabr.ui.analysis.Style.AccentText;
                if metric == "power" && ismember('F',C.Properties.VariableNames) && ...
                        ismember('PowerF95',C.Properties.VariableNames)
                    F = double(C.F(rows)); F95 = double(C.PowerF95(rows));
                    top = 1.15*max([F; F95; 1],[],'omitnan');
                    on = @(v) pr(1) + v/top*diff(pr);
                    obj.addEv(line(ax,lv,on(F),'Color',orange,'Marker','d','LineStyle','-', ...
                        'MarkerSize',5,'Tag','EvidencePowerF','DisplayName','power F (as drawn)', ...
                        'UserData',F));
                    obj.addEv(line(ax,lv,on(F95),'LineStyle','none','Marker','_','MarkerSize',14, ...
                        'LineWidth',1.5,'Color',mabr.ui.analysis.Style.Muted,'Tag','EvidencePowerF95', ...
                        'DisplayName','null 95% (as drawn)','UserData',F95));
                    obj.drawRuler(ax,xl,pr,top,"Power F (– null 95%)");
                else
                    pc = mabr.ui.analysis.SeriesView.pColumn(metric);
                    p = NaN(numel(rows),1);
                    if ismember(char(pc),C.Properties.VariableNames), p = double(C.(char(pc))(rows)); end
                    y = -log10(max(p,eps));
                    a = -log10(alpha);
                    top = max([y; a*1.5],[],'omitnan');
                    if ~(isfinite(top) && top > 0), top = 2; end
                    top = 1.15*top;
                    on = @(v) pr(1) + v/top*diff(pr);
                    obj.addEv(line(ax,lv,on(y),'Color',orange,'Marker','.','LineStyle','-', ...
                        'MarkerSize',12,'Tag','EvidenceP','DisplayName','-log10 p (as drawn)','UserData',y));
                    obj.addEv(line(ax,xl,on([a a]),'Color',orange,'LineStyle','--','Marker','none', ...
                        'Tag','EvidenceAlpha','DisplayName',sprintf('alpha %g (as drawn)',alpha), ...
                        'UserData',[a a]));
                    % the values themselves, for Copy data (not drawn)
                    obj.addEv(mabr.ui.analysis.FigureExport.markForCopy( ...
                        line(ax,lv,y,'Visible','off','LineStyle','none','Marker','none', ...
                        'Tag','EvidencePValues','DisplayName','-log10 p','HitTest','off')));
                    obj.drawRuler(ax,xl,pr,top,"−log10 p");
                end
                yl = ylL;
                yd = pr;
            else
                % graded: the metric against its criterion
                vc = mabr.ui.analysis.SeriesView.metricColumn(metric);
                y = NaN(numel(rows),1);
                if ismember(char(vc),C.Properties.VariableNames), y = double(C.(char(vc))(rows)); end
                d1 = det == 1;
                if any(d1 & isfinite(y))
                    obj.addEv(line(ax,lv(d1),y(d1),'LineStyle','none','Marker','o','MarkerSize',7, ...
                        'MarkerEdgeColor',blue,'MarkerFaceColor',blue,'Tag','EvidenceMetric', ...
                        'DisplayName','detected'));
                end
                if any(~d1 & isfinite(y))
                    obj.addEv(line(ax,lv(~d1),y(~d1),'LineStyle','none','Marker','o','MarkerSize',7, ...
                        'MarkerEdgeColor',blue,'MarkerFaceColor','none','Tag','EvidenceMetric', ...
                        'DisplayName','not detected'));
                end
                cy = [];
                if isstruct(fit) && isfield(fit,'CurveX') && ~isempty(fit.CurveX)
                    cy = double(fit.CurveY(:));
                    obj.addEv(line(ax,double(fit.CurveX(:)),cy,'Color',blue,'LineWidth',1.2, ...
                        'LineStyle','-','Marker','none','Tag','EvidenceCurve','DisplayName','fit'));
                end
                % the criterion on the metric's own scale: a fraction of
                % the range is that far between the lowest and the highest
                % value (SeriesThreshold's rule), anything else is a value
                cline = crit;
                cname = "criterion";
                if mode == "fraction" && isfinite(crit)
                    fy = y(isfinite(y));
                    cline = NaN;
                    if ~isempty(fy) && max(fy) > min(fy)
                        cline = min(fy) + crit*(max(fy) - min(fy));
                    end
                    cname = sprintf('criterion (%g of the range)',crit);
                end
                vals = [y; cline; cy];
                vals = vals(isfinite(vals));
                if isempty(vals), vals = [0 1]; end
                yd = [min(vals) max(vals)];
                if diff(yd) <= 0, yd = yd + [-0.5 0.5]; end
                yd = yd + [-0.15 0.2]*diff(yd);         % the data area
                yl = [yd(1) - 0.22*diff(yd), yd(2)];    % ... above the counts' band
                obj.put('ev_ylim',ax,'YLim',yl);
                obj.put('ev_ytick',ax,'YTickMode','auto');
                obj.put('ev_yticklab',ax,'YTickLabelMode','auto');
                obj.put('ev_ylab',ax.YLabel,'String',char(mabr.ui.analysis.SeriesView.metricLabel(metric)));
                if isfinite(cline)
                    obj.addEv(line(ax,xl,[cline cline],'Color',mabr.ui.analysis.Style.AccentText, ...
                        'LineStyle','--','Marker','none','Tag','EvidenceCriterion','DisplayName',char(cname)));
                end
            end
            % the fit's confidence interval as a band across the levels (a
            % graded fit's, or the psychometric fit's profile interval); an
            % open side runs to the edge of the plot
            lo = double(f('CILower',NaN)); hi = double(f('CIUpper',NaN));
            if (isfinite(lo) || isfinite(hi)) && ~any(isnan([lo hi]))
                lo = max(lo,xl(1)); hi = min(hi,xl(2));
                if hi > lo
                    obj.addEv(patch(ax,[lo hi hi lo],[yd(1) yd(1) yd(2) yd(2)], ...
                        mabr.ui.analysis.Style.FitRed,'FaceAlpha',0.10,'EdgeColor','none', ...
                        'Tag','EvidenceCI','DisplayName','confidence interval'));
                end
            end
            % the final value and the fit, censoring, n per level
            fin = double(f('Final',NaN)); fc = mabr.ui.analysis.SeriesView.asText(f('FinalCensored',""));
            thr = double(f('Threshold',NaN));
            green = mabr.ui.analysis.Style.FinalGreen;
            finLine = gobjects(0);
            if isfinite(fin)
                finLine = line(ax,[fin fin],yd,'Color',green,'LineWidth',2,'LineStyle','-', ...
                    'Marker','none','Tag','EvidenceFinal','DisplayName','final');
                obj.addEv(finLine);
            end
            if isfinite(thr) && ~(isfinite(fin) && abs(thr - fin) < 1e-9)
                obj.addEv(line(ax,[thr thr],yd,'Color',mabr.ui.analysis.Style.FitRed,'LineStyle','--', ...
                    'Marker','none','LineWidth',1.5,'Tag','EvidenceFit','DisplayName','fit'));
            end
            flo = double(f('FinalLo',NaN)); fhi = double(f('FinalHi',NaN));
            % ▲ at the top for no response, ▼ at the bottom for all
            % respond -- by what the censoring MEANS, which on an
            % attenuation axis is the other side of the numbers
            [noResp,allResp] = mabr.ui.analysis.SeriesView.censorMeaning(fc,G.Sign);
            xb = flo;                                  % the bound the arrow stands on
            if fc == "left", xb = fhi; end
            if (noResp || allResp) && isfinite(xb)
                if noResp
                    obj.addEv(text(ax,xb,yd(2),'▲','Color',green,'HorizontalAlignment','center', ...
                        'VerticalAlignment','top','FontSize',12,'Tag','EvidenceCensor', ...
                        'UserData',"noresponse"));
                else
                    obj.addEv(text(ax,xb,yd(1),'▼','Color',green,'HorizontalAlignment','center', ...
                        'VerticalAlignment','bottom','FontSize',12,'Tag','EvidenceCensor', ...
                        'UserData',"allrespond"));
                end
            elseif fc == "interval" && isfinite(flo) && isfinite(fhi)
                yb = yd(2) - 0.06*diff(yd);
                obj.addEv(line(ax,[flo fhi],[yb yb],'Color',green,'LineWidth',3, ...
                    'LineStyle','-','Marker','none','Tag','EvidenceInterval','DisplayName','interval'));
            end
            % (the counts in their band under the data area)
            yn = yl(1) + 0.03*diff(yl);
            for k = 1:numel(lv)
                if ~isfinite(nn(k)), continue; end
                obj.addEv(text(ax,lv(k),yn,sprintf('%d',round(nn(k))),'FontSize',7, ...
                    'Color',mabr.ui.analysis.Style.Muted,'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom','Tag','EvidenceN'));
            end
            % The mouse: everything drawn lets a click through to the axes
            % (onEvidenceDown), where the green line drags along the level
            % axis and a click in the band of counts sets the threshold.
            h = obj.EvObjs(isgraphics(obj.EvObjs));
            set(h,'HitTest','off');
            px = NaN;
            try
                pp = getpixelposition(ax);
                if pp(3) > 10, px = pp(3)/diff(xl); end
            catch
            end
            if ~isfinite(px), px = 240/diff(xl); end
            obj.EvidenceInfo = struct('SeriesKey',G.SeriesKey,'XLim',xl,'YLim',yl,'Bottom',yd(1), ...
                'Final',fin,'FinalLine',finLine,'Step',step,'PxPerX',px, ...
                'Draggable',obj.canDragThreshold(G,false));
        end

        function drawRuler(obj,ax,xl,yl,top,label)
            % A y ruler on the right edge of AX for a second scale running
            % 0..TOP over the axes' YLim YL: spine, ticks, tick labels and
            % LABEL, outside the plot box (Clipping off) and in the axes'
            % own colour and font, so it is copied, exported and laid out
            % with the axes it describes.
            px = diff(xl)/240;                     % ~1 px of a 240 px plot
            try
                pp = getpixelposition(ax);
                if pp(3) > 10, px = diff(xl)/pp(3); end
            catch
            end
            ink = ax.YColor;
            fs = ax.FontSize;
            st = 10^floor(log10(top/3));
            for f = [1 2 5 10]
                if top/(f*st) <= 5, st = f*st; break; end
            end
            tv = 0:st:top;
            ty = yl(1) + tv/top*diff(yl);
            x0 = xl(2);
            % (hidden handles: drawn, copied and exported with the axes, but
            % not data -- Copy data lists lines found by findobj)
            off = {'Clipping','off','HitTest','off','PickableParts','none','HandleVisibility','off'};
            obj.addEv(line(ax,[x0 x0],yl,'Color',ink,'LineWidth',0.5,'Marker','none', ...
                'Tag','EvidenceRuler',off{:}));
            X = reshape([repmat(x0,1,numel(ty)); repmat(x0 + 4*px,1,numel(ty)); NaN(1,numel(ty))],1,[]);
            Y = reshape([ty; ty; NaN(1,numel(ty))],1,[]);
            obj.addEv(line(ax,X,Y,'Color',ink,'LineWidth',0.5,'Marker','none', ...
                'Tag','EvidenceRuler',off{:}));
            w = 0;
            for k = 1:numel(tv)
                s = sprintf('%g',tv(k));
                w = max(w,strlength(s));
                obj.addEv(text(ax,x0 + 6*px,ty(k),s,'Color',ink,'FontSize',fs, ...
                    'VerticalAlignment','middle','HorizontalAlignment','left', ...
                    'Tag','EvidenceRulerTick',off{:}));
            end
            obj.addEv(text(ax,x0 + (10 + 0.62*fs*w)*px,mean(yl),char(label),'Color',ink, ...
                'FontSize',fs,'Rotation',90,'HorizontalAlignment','center', ...
                'VerticalAlignment','top','Tag','EvidenceRulerLabel',off{:}));
        end

        function renderAudiogram(obj,G)
            % This session's series against frequency (log); the series that
            % have no place on it are listed beneath in words: those without
            % a frequency, those whose conditions are at several (a series
            % key that fixes none), and every series when the level axis is
            % not a sound level (the user's Level parameter set to
            % Frequency, say) -- audiogramX.
            m = obj.Model;
            ax = obj.Handles.Audiogram;
            obj.dropObjs("AgObjs");
            S = G.Session;
            sks = m.seriesKeys();
            xp = "";
            try
                xp = string(S.frequencyParam());
            catch
            end
            C = S.Conditions;
            if xp ~= "" && ~(ismember(char(xp),C.Properties.VariableNames) && isnumeric(C.(char(xp))))
                xp = "";
            end
            lp = string(G.LevelParam);
            levelIsSound = mabr.ui.analysis.SeriesView.isSoundLevel(lp,S) && ~strcmpi(lp,xp);
            ckeys = string(C.Key);
            gcols = strings(1,0);
            for nm = ["Stimulus","AcqMode"]
                if ismember(char(nm),C.Properties.VariableNames) && numel(unique(C.(char(nm)))) > 1
                    gcols(end+1) = nm; %#ok<AGROW>
                end
            end
            x = NaN(numel(sks),1); y = NaN(numel(sks),1); mk = strings(numel(sks),1);
            grp = strings(numel(sks),1);
            missing = strings(0,1);
            for k = 1:numel(sks)
                ck = obj.condsOf(sks(k));
                if isempty(ck), continue; end
                [~,rr] = ismember(string(ck),ckeys);
                rr = rr(rr > 0);
                if isempty(rr), continue; end
                r = rr(1);
                fq = NaN;
                if xp ~= "", fq = double(C.(char(xp))(rr)); end
                [x(k),why] = mabr.ui.analysis.SeriesView.audiogramX(levelIsSound,fq);
                parts = strings(1,0);
                for nm = gcols, parts(end+1) = string(C.(char(nm))(r)); end %#ok<AGROW>
                grp(k) = strjoin(parts," · ");
                row = obj.rowOf(S,sks(k));
                if isempty(row), continue; end
                f  = @(nm,d) mabr.ui.analysis.SeriesView.field(row,nm,d);
                c = mabr.ui.analysis.SeriesView.asText(f('FinalCensored',""));
                switch c
                    case "right", y(k) = double(f('FinalLo',NaN)); mk(k) = "^";
                    case "left",  y(k) = double(f('FinalHi',NaN)); mk(k) = "v";
                    otherwise
                        y(k) = double(f('Final',NaN)); mk(k) = "o";
                end
                if ~(isfinite(x(k)) && x(k) > 0)
                    lab = obj.labelOf(sks(k));
                    if why == "several"
                        lab = lab + " (" + numel(unique(fq(isfinite(fq)))) + " frequencies)";
                    end
                    missing(end+1,1) = lab + ": " + strtrim( ...
                        mabr.ui.analysis.Style.formatThreshold(row) + " " + G.Unit); %#ok<AGROW>
                    x(k) = NaN;
                end
            end
            ok = isfinite(x) & x > 0 & isfinite(y);
            note = "";
            if ~isempty(missing), note = strjoin(missing,"; "); end
            if ~levelIsSound
                % every series is listed: say why before the list
                why0 = "No audiogram: these thresholds are along " + lp + ", not a sound level.";
                if note == "", note = why0; else, note = why0 + " " + note; end
            elseif xp == "" && isempty(missing)
                note = "No frequency axis in this session.";
            end
            % no series of the session has a frequency (clicks, noise): no
            % empty log axis, the note in its place, larger
            hasX = any(isfinite(x) & x > 0);
            obj.AudiogramOn = hasX;
            if ~hasX && note == "", note = "No thresholds to plot against frequency yet."; end
            fs = 10;
            if ~hasX, fs = 12; end
            obj.put('ag_note',obj.Handles.AudiogramNote,'Text',char(note));
            obj.put('ag_note_fs',obj.Handles.AudiogramNote,'FontSize',fs);
            obj.put('ag_vis',ax,'Visible',matlab.lang.OnOffSwitchState(hasX));
            obj.put('ag_xscale',ax,'XScale','log');
            ylab = "Threshold";
            if G.Unit ~= "", ylab = ylab + " (" + G.Unit + ")"; end
            obj.put('ag_ylab',ax.YLabel,'String',char(ylab));
            xlab = "";
            if xp ~= "", xlab = xp + " (kHz)"; end
            obj.put('ag_xlab',ax.XLabel,'String',char(xlab));
            if ~any(ok)
                obj.put('ag_xlim',ax,'XLim',[1 100]);
                % (frequency ticks as numbers, as the populated plot has them)
                obj.put('ag_xtick',ax,'XTick',[1 2 4 8 16 32 64]);
                obj.put('ag_xticklab',ax,'XTickLabel',{'1','2','4','8','16','32','64'});
                return
            end
            ux = unique(x(ok));
            lo = min(ux)/1.5; hi = max(ux)*1.5;
            obj.put('ag_xlim',ax,'XLim',[lo hi]);
            obj.put('ag_xtick',ax,'XTick',reshape(ux,1,[]));
            obj.put('ag_xticklab',ax,'XTickLabel',cellstr(compose('%g',ux)));
            ys = y(ok);
            yr = [min(ys) max(ys)];
            if diff(yr) <= 0, yr = yr + [-10 10]; end
            obj.put('ag_ylim',ax,'YLim',yr + [-0.15 0.15]*diff(yr));
            groups = unique(grp(ok),'stable');
            for g = 1:numel(groups)
                sel = ok & grp == groups(g);
                [xs,o] = sort(x(sel));
                yy = y(sel); yy = yy(o);
                mm = mk(sel); mm = mm(o);
                c = mabr.ui.analysis.Style.colorFor(g,numel(groups));
                nm = groups(g); if nm == "", nm = "series"; end
                obj.addAg(line(ax,xs,yy,'Color',c,'LineWidth',1.2,'Marker','none','LineStyle','-', ...
                    'Tag','AudiogramLine','DisplayName',char(nm)));
                for kind = ["o","^","v"]
                    s2 = mm == kind;
                    if ~any(s2), continue; end
                    obj.addAg(line(ax,xs(s2),yy(s2),'LineStyle','none','Marker',char(kind), ...
                        'MarkerSize',6,'MarkerFaceColor',c,'MarkerEdgeColor',c,'Tag','AudiogramPoint', ...
                        'DisplayName',char(nm)));
                end
                if numel(groups) > 1
                    % several lines (tone conventional / interleaved): each
                    % named at its last point
                    obj.addAg(text(ax,xs(end),yy(end),char(nm + "  "),'Color',0.8*c,'FontSize',8, ...
                        'HorizontalAlignment','right','VerticalAlignment','bottom', ...
                        'Tag','AudiogramLabel'));
                end
            end
            k = find(sks == G.SeriesKey,1);
            if ~isempty(k) && ok(k)
                obj.addAg(line(ax,x(k),y(k),'LineStyle','none','Marker',char(mk(k)),'MarkerSize',11, ...
                    'MarkerEdgeColor',[0 0 0],'LineWidth',1.5,'MarkerFaceColor','none', ...
                    'Tag','AudiogramCurrent','DisplayName','this series'));
            end
        end

        % ---- peaks side ----------------------------------------------------
        function renderPeaksSide(obj,G)
            H = obj.Handles;
            has = any(G.State(:) ~= "none") || any(isfinite(G.PeakLat(:)));
            analysed = istable(G.Session.Peaks) && height(G.Session.Peaks) > 0;
            for f = ["AutoPick","Retrack","ClearPeaks","Bootstrap"]
                obj.put("pk_en_" + f,H.(f),'Enable',matlab.lang.OnOffSwitchState(analysed));
            end
            obj.put('pk_en_FitWindows',H.FitWindows,'Enable',matlab.lang.OnOffSwitchState(analysed && has));
            obj.renderMatrix(G);
            obj.renderPeakPlot(G);
        end

        function renderMatrix(obj,G)
            % Levels loudest first, waves across: what PeaksShow asks for.
            H = obj.Handles;
            show = obj.cleanLook(obj.ViewLook).PeaksShow;
            n = numel(G.Keys);
            o = n:-1:1;                     % loudest first
            nW = numel(G.Waves);
            switch show
                case "latency"
                    V = mabr.analysis.Peaks.reported(G.PeakLat,G.Offset);
                    SE = G.LatSE; fmt = '%.2f'; sefmt = '%.3f';
                case "pn"
                    V = 1e6*G.AmpPT; SE = 1e6*G.AmpSE; fmt = '%.2f'; sefmt = '%.2f';
                otherwise
                    V = 1e6*G.AmpBP; SE = NaN(size(V)); fmt = '%.2f'; sefmt = '%.2f';
            end
            hasSE = any(isfinite(SE(:)));
            nc = 1 + nW + hasSE*nW;
            D = repmat({''},n,nc);
            for r = 1:n
                i = o(r);
                D{r,1} = sprintf('%g',G.Levels(i));
                for j = 1:nW
                    if G.State(i,j) == "absent"
                        D{r,1+j} = '—';
                    elseif isfinite(V(i,j))
                        D{r,1+j} = sprintf(fmt,V(i,j));
                    end
                    if hasSE && isfinite(SE(i,j))
                        D{r,1+nW+j} = sprintf(sefmt,SE(i,j));
                    end
                end
            end
            names = [G.LevelLabel, G.Waves];
            if hasSE, names = [names, G.Waves + " SE"]; end
            obj.put('mx_names',H.Matrix,'ColumnName',cellstr(names));
            obj.put('mx_widths',H.Matrix,'ColumnWidth',[{100}, repmat({50},1,nc - 1)]);
            obj.put('mx_data',H.Matrix,'Data',D);
            T = obj.timeAxis();
            tip = "One row per level (loudest first), one column per wave: manual picks bold, " + ...
                "absent ""—"", below threshold grey italic. Click a cell to select that level and wave peak.";
            if show == "latency" && T.Tip ~= "", tip = tip + " " + T.Tip; end
            obj.put('mx_tip',H.Matrix,'Tooltip',char(tip));
            obj.MatrixInfo = struct('Keys',G.Keys(o),'Levels',G.Levels(o),'Waves',G.Waves,'NumWaves',nW);
            % styles: manual cells bold, below-threshold rows grey italic
            man = G.State == "manual";
            if show == "pn", man = man | G.TState == "manual"; end
            man = man(o,:);
            below = any(G.Below(o,:),2);
            [mr,mc] = find(man);
            key = string(n) + "|" + nc + "|" + strjoin(string(mr.' ) + ":" + string(mc.'),",") + ...
                "|" + strjoin(string(find(below).'),",");
            if key ~= obj.MatrixStyle
                try
                    removeStyle(H.Matrix);
                    if any(below)
                        addStyle(H.Matrix,uistyle('FontColor',[0.5 0.5 0.5],'FontAngle','italic'), ...
                            'row',reshape(find(below),1,[]));
                    end
                    if ~isempty(mr)
                        addStyle(H.Matrix,uistyle('FontWeight','bold'),'cell',[mr(:) mc(:) + 1]);
                    end
                catch me
                    mabr.log.vprintf(2,'Series view: matrix styles (%s).',me.message);
                end
                obj.MatrixStyle = key;
            end
        end

        function renderPeakPlot(obj,G)
            % One line per wave against level: I/O (P–N amplitude) or
            % latency (ear time, Peaks.reported); bootstrap SE as error
            % bars; levels below threshold hollow. The wave names sit at
            % each line's last point, spread apart where they would overlap.
            ax = obj.Handles.PeakPlot;
            obj.dropObjs("PkObjs");
            kind = obj.cleanLook(obj.ViewLook).PlotKind;
            T = obj.timeAxis();
            [x,o] = sort(G.Levels);
            if kind == "io"
                Y = 1e6*G.AmpPT(o,:); E = 1e6*G.AmpSE(o,:);
                ylab = {'P–N amplitude (µV)'};
            else
                Y = mabr.analysis.Peaks.reported(G.PeakLat(o,:),G.Offset); E = G.LatSE(o,:);
                % the reference on a second line of the label (a title
                % above a plot this short is cut off by its panel): "re
                % sound arrival" with a conduction delay, the system
                % offset's own words without one
                ylab = {'Latency (ms)'};
                if T.Offset ~= 0
                    ref = "re sound arrival";
                    if ~startsWith(T.Label,"Time re sound arrival"), ref = T.Subtitle; end
                    ylab{2} = char(ref);
                end
            end
            St = G.State(o,:);
            B = G.Below(o,:);
            obj.put('pk_xlab',ax.XLabel,'String',char(G.LevelLabel));
            obj.put('pk_ylab',ax.YLabel,'String',ylab);
            % (the delay in full, for whoever reads the label's data)
            obj.put('pk_ylab_tip',ax.YLabel,'UserData',char(T.Tip));
            vals = Y(isfinite(Y));
            if isempty(vals)
                yr = [0 1];
                obj.put('pk_ylim',ax,'YLimMode','auto');
            else
                yr = [min(vals) max(vals)];
                if diff(yr) <= 0, yr = yr + [-1 1]*max(abs(yr(1))*0.1,0.1); end
                yr = yr + [-0.12 0.12]*diff(yr);
                obj.put('pk_ylim',ax,'YLim',yr);
            end
            nW = numel(G.Waves);
            lx = NaN(1,nW); ly = NaN(1,nW);
            for j = 1:nW
                w = G.Waves(j);
                c = mabr.ui.analysis.Style.waveColor(w);
                y = Y(:,j);
                y(~ismember(St(:,j),["auto","manual"])) = NaN;
                above = y; above(B(:,j)) = NaN;
                below = y; below(~B(:,j)) = NaN;
                obj.addPk(line(ax,x,above,'Color',c,'LineWidth',1.2,'LineStyle','-','Marker','o', ...
                    'MarkerSize',5,'MarkerFaceColor',c,'Tag','PeakPlotWave','DisplayName',char(w)));
                if any(isfinite(below))
                    obj.addPk(line(ax,x,below,'Color',c,'LineStyle',':','Marker','o','MarkerSize',5, ...
                        'MarkerFaceColor',[1 1 1],'Tag','PeakPlotBelow','DisplayName',char(w + " (below threshold)")));
                end
                e = E(:,j);
                okE = isfinite(e) & isfinite(y);
                if any(okE)
                    obj.addPk(errorbar(ax,x(okE),y(okE),e(okE),'LineStyle','none','Color',c, ...
                        'CapSize',3,'Tag','PeakPlotSE','DisplayName',char(w + " SE")));
                end
                k = find(isfinite(y),1,'last');
                if ~isempty(k), lx(j) = x(k); ly(j) = y(k); end
            end
            % names at the last points, at least a label's height apart
            ly = mabr.ui.analysis.SeriesView.spread(lx,ly,0.12*diff(yr));
            for j = find(isfinite(lx) & isfinite(ly))
                c = mabr.ui.analysis.Style.waveColor(G.Waves(j));
                obj.addPk(text(ax,lx(j),ly(j),['  ' char(G.Waves(j))],'Color',0.8*c,'FontSize',8, ...
                    'FontWeight','bold','VerticalAlignment','middle','Tag','PeakPlotLabel'));
            end
            step = 10;
            if numel(x) > 1, step = median(diff(x)); end
            if ~(isfinite(step) && step > 0), step = 10; end
            obj.put('pk_xlim',ax,'XLim',[x(1) - step/2, x(end) + step]);
            ux = unique(x(isfinite(x))).';
            if numel(ux) > 8, ux = ux(1:ceil(numel(ux)/8):end); end
            obj.put('pk_xtick',ax,'XTick',ux);
        end

        % ---- mouse ---------------------------------------------------------
        function onStackDown(obj,src,~)
            fig = ancestor(src,'figure');
            try
                if strcmp(fig.SelectionType,'alt'), return; end   % the context menu's
            catch
            end
            if ~obj.geometryValid(), return; end
            cp = src.CurrentPoint;
            obj.pointerDown(cp(1,1),cp(1,2));
        end

        function pointerDown(obj,x,y)
            % A press at (x,y) in the stack's data units: on the threshold
            % divider (or its grip) it takes the divider -- a release where
            % it was is still the click below (thresholdPress) -- anywhere
            % else, the click.
            if obj.thresholdPress(x,y), return; end
            obj.plainPointerDown(x,y);
        end

        function plainPointerDown(obj,x,y)
            % The click: select the level under it, or on the selected level
            % pick, drag or place the selected wave point.
            m = obj.Model;
            G = obj.Geometry;
            i = mabr.ui.analysis.SeriesView.bandAt(G,y);
            obj.writeCursor(x,i);
            if G.Keys(i) ~= m.Selection.ConditionKey
                m.selectLevel(G.Levels(i));
                return
            end
            wave = m.Selection.Wave;
            kind = m.Selection.Kind;
            j = find(G.Waves == wave,1);
            if wave == "" || isempty(j)
                % no point selected: a press on a marker of this level selects it
                [w,k,d] = obj.nearestMarker(G,i,x,y);
                if d <= obj.DragPixels, m.selectWave(w,k); end
                return
            end
            [px,py] = obj.pointXY(G,i,j,kind);
            if isfinite(px) && obj.pixelDistance(x,y,px,py) <= obj.DragPixels
                obj.beginDrag(G,i,j,kind,px);
                return
            end
            m.setPeak(G.Keys(i),wave,kind,obj.rawTime(x),Snap=true);
        end

        function beginDrag(obj,G,i,j,kind,x0)
            ax = obj.Handles.Stack.Axes;
            fig = ancestor(ax,'figure');
            obj.DragInfo = struct('Figure',fig,'Index',i,'Wave',G.Waves(j),'Kind',kind, ...
                'Key',G.Keys(i),'X0',x0,'X',x0,'Moved',false, ...
                'Motion',{fig.WindowButtonMotionFcn},'Up',{fig.WindowButtonUpFcn});
            obj.Dragging = true;
            fig.WindowButtonMotionFcn = @(~,~) obj.onDragMove();
            fig.WindowButtonUpFcn = obj.viewWrap(@(~,~) obj.onDragUp());
        end

        function onDragMove(obj)
            if ~obj.Dragging, return; end
            cp = obj.Handles.Stack.Axes.CurrentPoint;
            obj.moveDrag(cp(1,1));
        end

        function moveDrag(obj,x)
            % The dragged marker follows the pointer (nothing is stored yet).
            if ~obj.Dragging, return; end
            d = obj.DragInfo;
            G = obj.Geometry;
            xl = obj.TimeWindow;
            x = min(max(x,xl(1)),xl(2));
            d.X = x;
            d.Moved = d.Moved || abs(x - d.X0) > 0;
            obj.DragInfo = d;
            y = obj.traceValue(G,d.Index,x) + G.Offsets(d.Index);
            sel = obj.Handles.Stack.Selected;
            sel.XData = x;
            sel.YData = y;
            obj.forgetWritten('st_sel_');
            obj.writeCursor(x,d.Index);
        end

        function onDragUp(obj)
            if ~obj.Dragging, return; end
            cp = obj.Handles.Stack.Axes.CurrentPoint;
            obj.endDrag(true,cp(1,1));
        end

        function endDrag(obj,commit,x)
            % Let go: the point is stored where it was dropped (one undo
            % step) -- unless it never moved, or the drag was cancelled.
            if ~obj.Dragging, return; end
            d = obj.DragInfo;
            obj.Dragging = false;
            obj.DragInfo = [];
            try
                if isvalid(d.Figure)
                    d.Figure.WindowButtonMotionFcn = d.Motion;
                    d.Figure.WindowButtonUpFcn = d.Up;
                end
            catch
            end
            if commit && isfinite(x)
                xl = obj.TimeWindow;
                x = min(max(x,xl(1)),xl(2));
                moved = d.Moved || abs(x - d.X0) > 0;
                if moved
                    obj.Model.setPeak(d.Key,d.Wave,d.Kind,obj.rawTime(x),Snap=false);
                    return
                end
            end
            if obj.geometryValid(), obj.drawCurrent(obj.Geometry); end
        end

        % ---- the threshold by hand (ThresholdDrag) ------------------------
        function tf = thresholdPress(obj,x,y)
            % A press at (x,y) on the stack takes the threshold divider when
            % it is within ThresholdDrag.HitPixels of it (anywhere along it)
            % or of its grip -- unless the selected wave point is under the
            % press, whose drag comes first. The click a press would have
            % been is kept for a release that never moved.
            tf = false;
            G = obj.Geometry;
            if ~obj.canDragThreshold(G) || ~obj.onDivider(G,x,y,true), return; end
            if obj.onSelectedMarker(G,x,y), return; end
            [~,sy] = obj.stackScale(true);
            ax = obj.Handles.Stack.Axes;
            obj.ThrDrag = mabr.ui.analysis.ThresholdDrag(ax,obj.Model,G.SeriesKey,G.Offsets,G.Levels, ...
                Row=G.Row,Unit=G.Unit,Axis="y",PxPerUnit=sy,Pointer="top", ...
                Preview=@(o) obj.stackPreview(o),End=@(c) obj.stackDragEnd(c), ...
                Click=@() obj.plainPointerDown(x,y),Status=@(t,l) obj.status(t,l), ...
                Wrap=@(f) obj.viewWrap(f));
            obj.ThrDrag.begin(y);
            tf = true;
        end

        function stackPreview(obj,o)
            % The divider (and its grip) where a release would put it, the
            % readout beside it, the readout in the strip's cursor label.
            if ~obj.geometryValid(), return; end
            G = obj.Geometry;
            H = obj.Handles.Stack;
            xl = obj.TimeWindow;
            F = o.F;
            y = obj.dividerY(G,F.Final,string(F.FinalCensored),F.FinalLo,F.FinalHi);
            if ~isfinite(y), y = o.Pos; end
            nr = o.Kind == "noresponse";
            green = mabr.ui.analysis.Style.FinalGreen;
            set(H.Final,'XData',xl,'YData',[y y],'Visible','on');
            set(H.FinalText,'Position',[xl(1) + 0.01*diff(xl), y, 0], ...
                'Visible',matlab.lang.OnOffSwitchState(nr));
            if isgraphics(H.Grip)
                set(H.Grip,'XData',xl(2),'YData',y,'MarkerFaceColor',green,'Visible','on');
            end
            % the method's own threshold stays in view, dashed red, as the
            % reference the divider is being moved from
            yT = NaN;
            row = G.Row;
            if ~isempty(row)
                f = @(nm,d) mabr.ui.analysis.SeriesView.field(row,nm,d);
                yT = obj.dividerY(G,double(f('Threshold',NaN)), ...
                    mabr.ui.analysis.SeriesView.asText(f('Censored',"")),double(f('ThrLo',NaN)),double(f('ThrHi',NaN)));
            end
            set(H.Fit,'XData',xl,'YData',[yT yT],'Visible',matlab.lang.OnOffSwitchState(isfinite(yT)));
            % (written behind put's back: the next drawDividers writes again)
            obj.forgetWritten('st_final_');
            obj.forgetWritten('st_nr_');
            obj.forgetWritten('st_grip_');
            obj.forgetWritten('st_fit_');
            [sx,~] = obj.stackScale(false);
            tx = xl(2) - 12/sx;
            r = obj.StackReadout;
            if isempty(r) || ~isgraphics(r)
                r = text(H.Axes,tx,y,'','Color',green,'FontWeight','bold','FontSize',10, ...
                    'HorizontalAlignment','right','VerticalAlignment','bottom','Interpreter','none', ...
                    'BackgroundColor',[1 1 1],'Margin',1,'Clipping','off','HitTest','off', ...
                    'PickableParts','none','HandleVisibility','off','Tag','SeriesThresholdReadout');
                obj.StackReadout = r;
            end
            set(r,'Position',[tx y 0],'String',char(o.Short));
            obj.ThresholdReadout = o.Short;
            obj.put('cursor',obj.Handles.Cursor,'Text',char(o.Short));
        end

        function stackDragEnd(obj,committed)
            % The drag is over: the readout goes; cancelled (or a decision
            % the series already had), the divider back where the Model has
            % it -- a decision made redraws it through the Model's event.
            r = obj.StackReadout;
            obj.StackReadout = gobjects(0,1);
            delete(r(isgraphics(r)));
            obj.ThresholdReadout = "";
            if ~committed
                % (the strip's readout described a threshold not set)
                obj.put('cursor',obj.Handles.Cursor,'Text','');
            end
            if ~committed && obj.geometryValid()
                obj.forgetWritten('st_final_');
                obj.forgetWritten('st_nr_');
                obj.forgetWritten('st_grip_');
                obj.forgetWritten('st_fit_');
                obj.drawDividers(obj.Geometry);
            end
        end

        function onEvidenceDown(obj,src,~)
            % A press on the evidence plot: its green line (dragged along
            % the level axis), or the band of counts under the data, where
            % the threshold goes where the click lands (the stack's rules).
            fig = ancestor(src,'figure');
            try
                if ~strcmp(fig.SelectionType,'normal'), return; end   % (the menu's, a double-click)
            catch
            end
            if ~obj.geometryValid() || obj.ThresholdDragging, return; end
            cp = src.CurrentPoint;
            obj.evidencePress(cp(1,1),cp(1,2));
        end

        function tf = evidencePress(obj,x,y)
            % (x,y) in the evidence plot's data units: a press on the green
            % line takes it (a release where it was changes nothing); one in
            % the band of counts is a drag from where it lands.
            tf = false;
            G = obj.Geometry;
            E = obj.EvidenceInfo;
            if isempty(E) || ~obj.canDragThreshold(G) || E.SeriesKey ~= G.SeriesKey || ~E.Draggable
                return
            end
            if x < E.XLim(1) || x > E.XLim(2) || y > E.YLim(2), return; end
            ax = obj.Handles.Evidence;
            px = E.PxPerX;
            try
                pp = getpixelposition(ax);
                if pp(3) > 10, px = pp(3)/diff(E.XLim); end
            catch
            end
            onLine = isfinite(E.Final) && abs(x - E.Final)*px <= mabr.ui.analysis.ThresholdDrag.HitPixels && ...
                y >= E.Bottom;
            inBand = y < E.Bottom;
            if ~(onLine || inBand), return; end
            obj.ThrDrag = mabr.ui.analysis.ThresholdDrag(ax,obj.Model,G.SeriesKey,G.Sign*G.Levels,G.Levels, ...
                Row=G.Row,Unit=G.Unit,Axis="x",Scale=G.Sign,PxPerUnit=px,Pointer="left", ...
                Preview=@(o) obj.evidencePreview(o),End=@(c) obj.evidenceDragEnd(c), ...
                Status=@(t,l) obj.status(t,l),Wrap=@(f) obj.viewWrap(f));
            obj.ThrDrag.begin(G.Sign*x,Moved=inBand);
            tf = true;
        end

        function evidencePreview(obj,o)
            % A green line where a release would put the threshold on the
            % level axis (the edge beyond the loudest or the quietest level
            % for no response / all respond), the readout at its top.
            E = obj.EvidenceInfo;
            if isempty(E), return; end
            G = obj.Geometry;
            ax = obj.Handles.Evidence;
            F = o.F;
            half = G.Sign*E.Step/2;
            switch o.Kind
                case "noresponse", xp = o.Lo + half;
                case "allrespond", xp = o.Hi - half;
                otherwise
                    xp = F.Final;
                    if ~isfinite(xp), xp = o.Value; end
                    if ~isfinite(xp), xp = (o.Lo + o.Hi)/2; end
            end
            xp = min(max(xp,E.XLim(1)),E.XLim(2));
            green = mabr.ui.analysis.Style.FinalGreen;
            h = obj.EvidenceDrag;
            if numel(h) ~= 2 || ~all(isgraphics(h))
                delete(h(isgraphics(h)));
                h = gobjects(2,1);
                h(1) = line(ax,[NaN NaN],[NaN NaN],'Color',green,'LineWidth',2,'LineStyle','-', ...
                    'Marker','none','HitTest','off','PickableParts','none','HandleVisibility','off', ...
                    'Tag','EvidenceThresholdDrag');
                h(2) = text(ax,NaN,NaN,'','Color',green,'FontWeight','bold','FontSize',9, ...
                    'VerticalAlignment','top','Interpreter','none','BackgroundColor',[1 1 1], ...
                    'Margin',1,'Clipping','off','HitTest','off','PickableParts','none', ...
                    'HandleVisibility','off','Tag','EvidenceThresholdReadout');
                obj.EvidenceDrag = h;
            end
            if ~isempty(E.FinalLine) && isgraphics(E.FinalLine), E.FinalLine.Visible = 'off'; end
            set(h(1),'XData',[xp xp],'YData',[E.Bottom E.YLim(2)]);
            ha = 'left';
            if xp > mean(E.XLim), ha = 'right'; end
            set(h(2),'Position',[xp E.YLim(2) 0],'String',char(o.Short),'HorizontalAlignment',ha);
            obj.ThresholdReadout = o.Short;
            obj.put('cursor',obj.Handles.Cursor,'Text',char(o.Short));
        end

        function evidenceDragEnd(obj,committed)
            % The drag line and readout go, the plot's own line comes back
            % (a decision made redraws the plot through the Model's event).
            h = obj.EvidenceDrag;
            obj.EvidenceDrag = gobjects(0,1);
            delete(h(isgraphics(h)));
            obj.ThresholdReadout = "";
            if ~committed, obj.put('cursor',obj.Handles.Cursor,'Text',''); end
            E = obj.EvidenceInfo;
            if ~isempty(E) && ~isempty(E.FinalLine) && isgraphics(E.FinalLine)
                E.FinalLine.Visible = 'on';
            end
        end

        function tf = canDragThreshold(obj,G,checkBusy)
            % A threshold the mouse may set: an analysed series of two or
            % more levels (and, for a press, a Model free to take it).
            if nargin < 3, checkBusy = true; end
            try
                tf = ~isempty(G) && ~isempty(G.Row) && numel(G.Keys) >= 2;
                if tf && checkBusy
                    tf = ~obj.Model.Busy && ~obj.ThresholdDragging && ~obj.Dragging;
                end
            catch
                tf = false;
            end
        end

        function tf = onDivider(obj,G,x,y,precise)
            % (x,y) within HitPixels of the divider (anywhere along it), or
            % within GripPixels of its grip. PRECISE measures the axes now
            % (a press); otherwise the size cached at the last layout (a
            % hover, on every move of the mouse).
            tf = false;
            d = obj.DividerAt;
            if isempty(d) || ~d.On || d.SeriesKey ~= G.SeriesKey, return; end
            [sx,sy] = obj.stackScale(precise);
            xl = obj.TimeWindow;
            if d.HasLine && x >= xl(1) && x <= xl(2) && ...
                    abs(y - d.Line)*sy <= mabr.ui.analysis.ThresholdDrag.HitPixels
                tf = true;
            elseif hypot((x - xl(2))*sx,(y - d.Grip)*sy) <= mabr.ui.analysis.ThresholdDrag.GripPixels
                tf = true;
            end
        end

        function tf = onSelectedMarker(obj,G,x,y)
            % The selected wave point of the selected level within DragPixels
            % of (x,y): its drag comes before the divider's.
            tf = false;
            m = obj.Model;
            i = mabr.ui.analysis.SeriesView.bandAt(G,y);
            if G.Keys(i) ~= m.Selection.ConditionKey || m.Selection.Wave == "", return; end
            j = find(G.Waves == m.Selection.Wave,1);
            if isempty(j), return; end
            [px,py] = obj.pointXY(G,i,j,m.Selection.Kind);
            tf = isfinite(px) && obj.pixelDistance(x,y,px,py) <= obj.DragPixels;
        end

        function [sx,sy] = stackScale(obj,precise)
            % Pixels per ms and per data unit of the stack axes.
            ax = obj.Handles.Stack.Axes;
            xl = obj.TimeWindow;
            yl = [0 1];
            G = obj.Geometry;
            if ~isempty(G) && ~isempty(G.Offsets)
                yl = [G.Offsets(1) - G.Step, G.Offsets(end) + 1.3*G.Step];   % renderStack's YLim
            end
            w = NaN;  h = NaN;
            if precise
                try
                    pos = getpixelposition(ax);
                    w = pos(3);  h = pos(4);
                catch
                end
            end
            if ~(w > 20 && h > 20) && numel(obj.StackPx) == 2
                w = obj.StackPx(1);  h = obj.StackPx(2);
            end
            if ~(w > 20 && h > 20), w = 600;  h = 400; end
            sx = w/diff(xl);
            sy = h/diff(yl);
        end

        function onMenuOpening(obj)
            % Which level the right-click was on.
            obj.MenuLevel = NaN;
            if ~obj.geometryValid(), return; end
            try
                cp = obj.Handles.Stack.Axes.CurrentPoint;
                i = mabr.ui.analysis.SeriesView.bandAt(obj.Geometry,cp(1,2));
                obj.MenuLevel = obj.Geometry.Levels(i);
            catch
            end
        end

        function [w,k,d] = nearestMarker(obj,G,i,x,y)
            w = ""; k = "P"; d = Inf;
            for j = 1:numel(G.Waves)
                for kind = ["P","N"]
                    [px,py] = obj.pointXY(G,i,j,kind);
                    if ~isfinite(px), continue; end
                    dd = obj.pixelDistance(x,y,px,py);
                    if dd < d, d = dd; w = G.Waves(j); k = kind; end
                end
            end
        end

        function d = pixelDistance(obj,x,y,px,py)
            ax = obj.Handles.Stack.Axes;
            try
                pos = getpixelposition(ax);
                sx = pos(3)/diff(ax.XLim);
                sy = pos(4)/diff(ax.YLim);
            catch
                sx = 50; sy = 50;
            end
            d = hypot((x - px)*sx,(y - py)*sy);
        end

        function [px,py] = pointXY(obj,G,i,j,kind)
            % Where a pick is drawn: (ear time, on the drawn trace).
            if kind == "N", lat = G.TroughLat(i,j); else, lat = G.PeakLat(i,j); end
            px = lat - G.Offset;
            py = NaN;
            if isfinite(px), py = obj.traceValue(G,i,px) + G.Offsets(i); end
        end

        function v = traceValue(~,G,i,x)
            % The drawn trace of level i at drawn time x (no offset).
            v = NaN;
            t = G.T;
            y = G.Disp(:,i);
            ok = isfinite(t) & isfinite(y);
            if nnz(ok) < 2 || x < min(t(ok)) || x > max(t(ok)), return; end
            v = interp1(t(ok),y(ok),x,'linear');
        end

        function writeCursor(obj,x,i)
            % "2.58 ms · 3.41 µV · 60 dB" -- only during a click or a drag.
            G = obj.Geometry;
            if isempty(G) || ~isfinite(i), return; end
            t = G.T; y = G.Mean(:,i);
            ok = isfinite(t) & isfinite(y);
            v = NaN;
            if nnz(ok) >= 2 && x >= min(t(ok)) && x <= max(t(ok))
                v = interp1(t(ok),y(ok),x,'linear');
            end
            txt = mabr.ui.analysis.Style.formatMs(x) + " · " + mabr.ui.analysis.Style.formatUV(v) + ...
                " · " + strtrim(sprintf('%g',G.Levels(i)) + " " + G.Unit);
            obj.put('cursor',obj.Handles.Cursor,'Text',char(txt));
        end

        % ---- controls ------------------------------------------------------
        function onListSelect(obj,src,evt)
            rows = mabr.ui.analysis.Compat.selectedRows(src,evt);
            if isempty(rows), return; end
            k = rows(1);
            if k < 1 || k > numel(obj.ListKeys), return; end
            sk = obj.ListKeys(k);
            m = obj.Model;
            if sk ~= m.Selection.SeriesKey
                m.selectSeries(sk);
            end
        end

        function onMatrixSelect(obj,~,evt)
            % A cell: that level, and that wave's peak.
            idx = [];
            try
                idx = evt.Indices;
            catch
            end
            info = obj.MatrixInfo;
            if isempty(idx) || isempty(info), return; end
            r = idx(1,1); c = idx(1,2);
            if r < 1 || r > numel(info.Levels), return; end
            m = obj.Model;
            if info.Keys(r) ~= m.Selection.ConditionKey
                m.selectLevel(info.Levels(r));
            end
            j = c - 1;
            if j > info.NumWaves, j = j - info.NumWaves; end
            if j >= 1 && j <= info.NumWaves
                m.selectWave(info.Waves(j),"P");
            end
        end

        function onPolarity(obj,src)
            obj.ViewLook.Polarity = string(src.Value);
            obj.Written.look_pol = src.Value;
            obj.savePrefs();
            obj.renderGuarded(@() obj.renderTraces());
        end

        function onNormalize(obj,src)
            obj.ViewLook.Normalize = logical(src.Value);
            obj.Written.look_norm = logical(src.Value);
            obj.savePrefs();
            obj.renderGuarded(@() obj.renderTraces());
        end

        function onResize(obj)
            % The stack panel has a new size: the column widths (the
            % workspace may have crossed 1000 px), the axes' pixel margins,
            % and the right margin's glyphs and counts, which sit a number
            % of pixels -- not milliseconds -- past the axes.
            if ~isvalid(obj) || ~obj.Built, return; end
            try
                obj.layoutColumns();
                obj.layoutStack();
                obj.fitHints();
                if ~obj.Rendering && obj.geometryValid()
                    obj.drawMargin(obj.Geometry);
                    obj.drawScaleBar(obj.Geometry);
                end
            catch me
                mabr.log.vprintf(2,'Series view: layout after a resize (%s).',me.message);
            end
        end

        function fitHints(obj)
            % The hint strip: as many of the tab's keys as fit the stack's
            % width (~5.6 px a character at 10 points -- an estimate, since
            % measuring a label would lay it out on the spot), then "F1 all
            % keys"; the tooltip lists them all.
            try
                pos = getpixelposition(obj.Handles.StackPanel);
            catch
                return
            end
            if ~(pos(3) > 60), return; end
            n = max(20,floor(pos(3)/5.6));
            obj.put('hints_text',obj.Handles.Hints,'Text', ...
                char(mabr.ui.analysis.Commands.hint("series",MaxChars=n)));
        end

        function placeSidePlots(obj)
            % The side plots' axes back at their pixel margins (Style.pinAxes
            % keeps them there on a resize; a redraw re-asserts it, since a
            % sub-tab drawn while hidden is laid out only when shown).
            H = obj.Handles;
            for f = ["Evidence","Audiogram","PeakPlot"]
                if isfield(H,f) && ~isempty(H.(f)) && isvalid(H.(f))
                    mabr.ui.analysis.Style.placeAxes(H.(f).Parent,H.(f));
                end
            end
        end

        function onCompare(obj,src)
            obj.CompareKey = string(src.Value);
            if obj.geometryValid(), obj.drawCompare(obj.Geometry); end
        end

        function onSideTab(obj,src,~)
            name = "Threshold";
            try
                if src.SelectedTab == obj.Handles.SidePeaks, name = "Peaks"; end
            catch
            end
            obj.ViewLook.SideTab = name;
            obj.Written.look_side = src.SelectedTab;
            obj.savePrefs();
        end

        function onPeaksShow(obj,src)
            obj.ViewLook.PeaksShow = string(src.Value);
            obj.Written.look_show = src.Value;
            obj.savePrefs();
            if obj.geometryValid(), obj.renderGuarded(@() obj.renderMatrix(obj.Geometry)); end
        end

        function onPlotKind(obj,src)
            obj.ViewLook.PlotKind = string(src.Value);
            obj.Written.look_plot = src.Value;
            obj.savePrefs();
            if obj.geometryValid(), obj.renderGuarded(@() obj.renderPeakPlot(obj.Geometry)); end
        end

        function onMethod(obj,src)
            % The PROJECT's method: the open session is re-fitted at once
            % (thresholds and peaks only), every other one becomes out of date.
            m = obj.Model;
            id = string(src.Value);
            s = m.Settings;
            if string(s.ThresholdMethod) == id, return; end
            s.ThresholdMethod = id;
            if id == "custom"
                s.CriterionMode = mabr.ui.analysis.SeriesView.modeFor(s.ThresholdMetric,s.ThresholdModel);
                try
                    mabr.analysis.SeriesThreshold.resolve("custom",s);
                catch me
                    % the custom fields as they stand cannot be estimated
                    % (say so; the dropdown goes back to the method in force)
                    obj.status("Not applied — " + string(me.message),1);
                    obj.forgetWritten('mth_');
                    obj.syncMethod();
                    return
                end
            end
            obj.forgetWritten('mth_value');
            m.setSettings(s,Persist=false,Refit=true);
        end

        function onCustom(obj,which)
            % A custom method's metric, model or criterion. The criterion
            % mode is the one the metric and model allow; a combination the
            % method cannot estimate is refused here, with the reason.
            m = obj.Model;
            H = obj.Handles;
            s = m.Settings;
            s.ThresholdMetric = string(H.Metric.Value);
            s.ThresholdModel = string(H.ModelDrop.Value);
            s.CriterionMode = mabr.ui.analysis.SeriesView.modeFor(s.ThresholdMetric,s.ThresholdModel);
            if which == "criterion"
                v = str2double(string(H.Criterion.Value));
                if strtrim(string(H.Criterion.Value)) == "", v = NaN; end
                s.Criterion = v;
            else
                s.Criterion = NaN;          % the new combination's default
            end
            try
                mabr.analysis.SeriesThreshold.resolve("custom",s);
            catch me
                obj.status("Not applied — " + string(me.message),1);
                obj.forgetWritten('mth_');
                obj.syncMethod();
                return
            end
            s.ThresholdMethod = "custom";
            obj.forgetWritten('mth_');
            m.setSettings(s,Persist=false,Refit=true);
        end

        function onSetValue(obj)
            v = obj.Handles.ValueField.Value;
            obj.Model.setThresholdValue(v);
        end

        function onCompareMethods(obj)
            % (a short name per method -- the full one is in the table's
            % tooltip -- and the status in words)
            m = obj.Model;
            T = m.compareMethods();
            n = height(T);
            names = strings(n,1);  words = strings(n,1);
            for i = 1:n
                names(i) = mabr.ui.analysis.SeriesView.methodShort(T.Method(i),T.Label(i));
                words(i) = mabr.ui.analysis.SeriesView.statusWord(T.Status(i));
            end
            D = [cellstr(names), cellstr(T.Text), cellstr(words)];
            H = obj.Handles;
            obj.put('thr_other',H.Other,'Data',D);
            obj.put('thr_other_tip',H.Other,'Tooltip',char("Every built-in method's threshold " + ...
                "for this series, from its stored per-level statistics: " + ...
                strjoin(names + " = " + string(T.Label),"; ") + "."));
            obj.put('thr_other_note',H.OtherNote,'Text',char("All methods for " + ...
                m.seriesLabel(m.Selection.SeriesKey)));
            obj.OtherFor = m.SessionKey + "|" + m.Selection.SeriesKey;
            obj.applyThresholdRows();
        end

        function applyThresholdRows(obj)
            % The Threshold sub-tab's row heights from what it shows: the
            % custom row only for "custom", the other methods' table as tall
            % as its rows once filled (nothing while empty), the audiogram
            % only when a series of the session has a frequency.
            H = obj.Handles;
            rh = obj.ThresholdRows;
            if obj.CustomRowOn, rh{2} = 24; end
            n = 0;
            try
                n = size(H.Other.Data,1);
            catch
            end
            if n == 0, rh{9} = 0; else, rh{9} = 26 + 21*n; end
            if ~obj.AudiogramOn, rh{11} = 0; end
            obj.put('mth_rows',H.ThresholdGrid,'RowHeight',rh);
            obj.put('thr_other_vis',H.Other,'Visible',matlab.lang.OnOffSwitchState(n > 0));
        end

        function copyMatrix(obj)
            mabr.ui.analysis.FigureExport.copyTable(obj.Handles.Matrix);
            obj.status("Wave matrix copied.",0);
        end

        function openSettings(obj,tab)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.openDialog("settings",'Tab',tab);
            end
        end

        function a = settingsAction(obj)
            a = struct('Text',"Settings…",'Fcn',@() obj.openSettings("Thresholds"),'Glyph',"gear", ...
                'Tooltip',"Open the analysis settings on their Thresholds tab");
        end

        function runId(obj,id)
            % A command, as if its key were pressed: through the app (so a
            % button and its key are one code path), or -- with no app, as a
            % test may build this view -- straight to the Model.
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.runCommand(id);
                return
            end
            m = obj.Model;
            switch id
                case "thr.accept",       m.acceptFit();
                case "thr.atLevel",      m.setThresholdAtLevel(m.Selection.Level);
                case "thr.noResponse",   m.setNoResponse();
                case "thr.allRespond",   m.setAllRespond();
                case "thr.exclude",      m.toggleExcluded();
                case "thr.clear",        m.clearDecision();
                case "thr.override",     m.cycleDetectionOverride(m.Selection.ConditionKey);
                case "peak.autoPick",    m.pickPeaks("series");
                case "peak.retrack",     m.retrack();
                case "peak.absent",      m.togglePeakAbsent();
                case "peak.revert",      m.revertPeak();
                otherwise
                    % (edit.note needs the app's note editor)
            end
        end

        function status(obj,text,level)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus(text,level);
            else
                mabr.log.vprintf(max(level,1),'%s',char(text));
            end
        end

        % ---- one render pass's lookups -----------------------------------
        function beginPass(obj)
            % Start remembering lookups for one render: a series' threshold
            % row, its conditions and its label are asked for by the list,
            % the stack, the threshold side and the audiogram alike, and
            % each costs a table search.
            obj.Pass = struct('Session',obj.Model.Session,'RowKeys',[],'Rows',[], ...
                'Conds',containers.Map('KeyType','char','ValueType','any'), ...
                'Labels',containers.Map('KeyType','char','ValueType','any'));
        end

        function endPass(obj)
            % Forget them: the next edit may change any of them.
            if isvalid(obj), obj.Pass = []; end
        end

        function tf = inPass(obj,S)
            % (the same Session OBJECT: == on a handle, never isequal, which
            % may compare two sessions property by property)
            tf = ~isempty(obj.Pass) && ~isempty(S) && ~isempty(obj.Pass.Session) && ...
                obj.Pass.Session == S;
        end

        function row = rowOf(obj,S,sk)
            % The series' Thresholds row as a struct (Fit unwrapped), [] for
            % none -- SeriesView.thresholdRow, all rows converted at once
            % within a pass.
            if ~obj.inPass(S)
                row = mabr.ui.analysis.SeriesView.thresholdRow(S,sk);
                return
            end
            if isempty(obj.Pass.RowKeys)
                keys = strings(0,1);
                R = struct([]);
                try
                    T = S.Thresholds;
                    if height(T) > 0 && ismember('Key',T.Properties.VariableNames)
                        keys = string(T.Key);
                        R = table2struct(T);
                        if isfield(R,'Fit')
                            for k = 1:numel(R)
                                f = R(k).Fit;
                                if iscell(f)
                                    if isempty(f), R(k).Fit = []; else, R(k).Fit = f{1}; end
                                end
                            end
                        end
                    end
                catch
                    keys = strings(0,1);
                    R = struct([]);
                end
                obj.Pass.RowKeys = {keys};
                obj.Pass.Rows = R;
            end
            keys = obj.Pass.RowKeys{1};
            r = find(keys == sk,1);
            row = [];
            if ~isempty(r), row = obj.Pass.Rows(r); end
        end

        function ck = condsOf(obj,sk)
            % Model.seriesConditions, once per series within a pass.
            m = obj.Model;
            if ~obj.inPass(m.Session)
                ck = m.seriesConditions(sk);
                return
            end
            k = char(sk);
            if ~isKey(obj.Pass.Conds,k)
                obj.Pass.Conds(k) = m.seriesConditions(sk);
            end
            ck = obj.Pass.Conds(k);
        end

        function s = labelOf(obj,sk)
            % Model.seriesLabel, once per series within a pass.
            m = obj.Model;
            if ~obj.inPass(m.Session)
                s = m.seriesLabel(sk);
                return
            end
            k = char(sk);
            if ~isKey(obj.Pass.Labels,k)
                obj.Pass.Labels(k) = m.seriesLabel(sk);
            end
            s = obj.Pass.Labels(k);
        end

        % ---- small things --------------------------------------------------
        function names = waveNames(obj)
            % The waves the 1–5 keys select: this series' own.
            names = strings(1,0);
            if obj.geometryValid(), names = obj.Geometry.Waves; end
            if isempty(names)
                try
                    W = obj.Model.Settings.Waves;
                    W = W([W.Enabled]);
                    names = string({W.Name});
                catch
                    names = ["I","II","III","IV","V"];
                end
            end
        end

        function i = currentIndex(obj,G)
            i = NaN;
            if isempty(G) || isempty(G.Keys), return; end
            k = find(G.Keys == obj.Model.Selection.ConditionKey,1);
            if isempty(k)
                lv = obj.Model.Selection.Level;
                if isfinite(lv)
                    [~,k] = min(abs(G.Levels - lv));
                end
            end
            if ~isempty(k), i = k; end
        end

        function tf = geometryValid(obj)
            G = obj.Geometry;
            m = obj.Model;
            tf = false;
            if isempty(G) || isempty(m.Session), return; end
            try
                tf = G.Session == m.Session && G.SessionKey == m.SessionKey && ...
                    G.SeriesKey == m.Selection.SeriesKey && isvalid(obj.Handles.Stack.Axes);
            catch
                tf = false;
            end
        end

        function G = requireGeometry(obj)
            if ~obj.geometryValid()
                obj.renderAll();
            end
            G = obj.Geometry;
            if isempty(G)
                error('mabr:ui:SeriesView:noSeries','There is no series on the Series tab.');
            end
        end

        function look = cleanLook(obj,look)
            % The look, with anything a pref or a configuration got wrong
            % replaced by the factory value.
            d = obj.factoryDefaults();
            if ~isstruct(look), look = d; end
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(look,f{k}), look.(f{k}) = d.(f{k}); end
            end
            look.Polarity = mabr.ui.analysis.SeriesView.member(look.Polarity,obj.PolarityData,d.Polarity);
            look.PeaksShow = mabr.ui.analysis.SeriesView.member(look.PeaksShow,obj.ShowData,d.PeaksShow);
            look.PlotKind = mabr.ui.analysis.SeriesView.member(look.PlotKind,obj.PlotData,d.PlotKind);
            look.SideTab = mabr.ui.analysis.SeriesView.member(look.SideTab,obj.SideTabs,d.SideTab);
            try
                look.Normalize = logical(look.Normalize(1));
            catch
                look.Normalize = d.Normalize;
            end
        end

        function tf = lookNormalize(obj)
            tf = obj.cleanLook(obj.ViewLook).Normalize;
        end

        function dropObjs(obj,name)
            h = obj.(name);
            h = h(isgraphics(h));
            delete(h);
            obj.(name) = gobjects(0,1);
        end

        function addEv(obj,h), obj.EvObjs(end+1,1) = h; end
        function addAg(obj,h), obj.AgObjs(end+1,1) = h; end
        function addPk(obj,h), obj.PkObjs(end+1,1) = h; end

        function g = rowGrid(~,parent,row,cw)
            g = uigridlayout(parent,[1 numel(cw)],'ColumnWidth',cw,'RowHeight',{'1x'}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',4,'BackgroundColor',mabr.ui.analysis.Style.Panel);
            g.Layout.Row = row;
        end

        function b = button(obj,parent,text,tag,tip,fcn)
            b = uibutton(parent,'Text',text,'Tag',tag,'Tooltip',tip, ...
                'ButtonPushedFcn',obj.viewWrap(fcn));
            mabr.ui.analysis.SeriesView.trySet(b,'WordWrap','on');
        end

        function tableMenu(obj,fig,tbl,tag)
            cm = uicontextmenu(fig);
            uimenu(cm,'Text','Copy table','Tag',tag, ...
                'MenuSelectedFcn',@(~,~) mabr.ui.analysis.FigureExport.copyTable(tbl));
            tbl.ContextMenu = cm;
            obj.Menus(end+1,1) = cm;
        end

        function plotMenu(obj,fig,ax,tag,target)
            % A plot's context menu: Export figure… / Copy data / Copy image
            % of TARGET (default the axes; a panel exports every axes in it).
            if nargin < 5, target = ax; end
            cm = uicontextmenu(fig,'Tag',tag);
            mabr.ui.analysis.FigureExport.addContextItems(cm,target,obj.Host);
            ax.ContextMenu = cm;
            obj.Menus(end+1,1) = cm;
        end
    end

    % =====================================================================
    methods (Static)
        function u = levelUnitOf(lp,S)
            % The unit of a series' level axis LP in session S: the session's
            % level reference for a sound level (Session.LevelAliases, or the
            % session's automatic level parameter; "dB" when the files do not
            % say), kHz for a frequency (Session.FrequencyAliases), and none
            % for any other parameter a user made the level axis -- a unit
            % guessed for a parameter MABR does not know the unit of is worse
            % than none (mabr.stim.StimulusSet.paramUnit).
            lp = string(lp);
            if isempty(lp) || ismissing(lp(1)), lp = ""; else, lp = lp(1); end
            if any(strcmpi(lp,mabr.analysis.Session.FrequencyAliases))
                u = "kHz";
                return
            end
            if ~mabr.ui.analysis.SeriesView.isSoundLevel(lp,S)
                u = "";
                return
            end
            u = "dB";
            try
                v = string(S.LevelUnit);
                if v ~= "" && v ~= "mixed" && ~ismissing(v), u = v; end
            catch
            end
        end

        function tf = isSoundLevel(lp,S)
            % Whether the level axis LP is a sound level: a Session.LevelAliases
            % name, the session's automatic level parameter, or "" (none
            % named: the automatic one). A Level parameter the user set to
            % something else (Frequency, say) is not.
            lp = string(lp);
            if isempty(lp) || ismissing(lp(1)) || lp(1) == "", tf = true; return; end
            lp = lp(1);
            tf = any(strcmpi(lp,mabr.analysis.Session.LevelAliases));
            if tf || any(strcmpi(lp,mabr.analysis.Session.FrequencyAliases)), return; end
            try
                tf = strcmpi(lp,string(S.levelParamOrEmpty()));
            catch
                tf = false;
            end
        end

        function [x,why] = audiogramX(levelIsSound,freqs)
            % Where one series stands on the audiogram's frequency axis.
            %
            % The audiogram plots LEVEL thresholds against frequency, so a
            % series has a place on it only when its level axis is a sound
            % level other than the frequency itself and every one of its
            % conditions is at ONE frequency. A series along Frequency (the
            % user's Level parameter) or one whose key fixes no frequency (a
            % GroupBy that leaves Frequency out) is listed beneath the plot
            % instead: its first condition's frequency would put it where
            % nothing about it is.
            %
            %   levelIsSound  the series' level axis is a sound level and not
            %                 the frequency parameter
            %   freqs         the frequency (kHz) of each of the series'
            %                 conditions ([] or NaN = none)
            %   x    (returned) kHz, or NaN when the series has no place
            %   why  (returned) "" (placed), "level" (not a sound-level
            %        axis), "none" (no frequency), "several" (more than one)
            x = NaN;
            if ~levelIsSound, why = "level"; return; end
            f = unique(double(freqs(isfinite(freqs) & freqs > 0)));
            if isempty(f)
                why = "none";
            elseif ~isscalar(f)
                why = "several";
            else
                x = f;  why = "";
            end
        end

        function d = factoryDefaults()
            % The look of a new Series tab.
            d = struct('Polarity',"balanced",'Normalize',false,'PeaksShow',"latency", ...
                'PlotKind',"io",'SideTab',"Threshold");
        end

        function d = loadDefaults()
            % The look the last Series tab was left with (pref
            % OfflineAnalysisSeries), forgiving of anything wrong in it.
            d0 = mabr.ui.analysis.SeriesView.factoryDefaults();
            d = mabr.ui.analysis.View.loadLook("OfflineAnalysisSeries",d0);
            d.Polarity = mabr.ui.analysis.SeriesView.member(d.Polarity, ...
                mabr.ui.analysis.SeriesView.PolarityData,d0.Polarity);
            d.PeaksShow = mabr.ui.analysis.SeriesView.member(d.PeaksShow, ...
                mabr.ui.analysis.SeriesView.ShowData,d0.PeaksShow);
            d.PlotKind = mabr.ui.analysis.SeriesView.member(d.PlotKind, ...
                mabr.ui.analysis.SeriesView.PlotData,d0.PlotKind);
            d.SideTab = mabr.ui.analysis.SeriesView.member(d.SideTab, ...
                mabr.ui.analysis.SeriesView.SideTabs,d0.SideTab);
        end

        function saveDefaults(d)
            % Remember a look (from this tab's controls, or a configuration).
            mabr.ui.analysis.View.saveLook("OfflineAnalysisSeries",d);
        end

        function mode = modeFor(metric,model)
            % The one criterion mode a custom metric and model can take
            % (SeriesThreshold's combination rule): descending decides by p
            % on a p-value and by an absolute value on a graded metric; glm
            % is a probability, presto an absolute correlation, the legacy
            % models a fraction of the range.
            metric = string(metric); model = string(model);
            isP = ismember(metric,mabr.analysis.SeriesThreshold.PMetrics);
            switch model
                case "descending"
                    if isP, mode = "p"; else, mode = "absolute"; end
                case "glm",    mode = "probability";
                case "presto", mode = "absolute";
                otherwise,     mode = "fraction";
            end
        end

        function s = flagCodes(flags)
            % "NM W X ..." for a Thresholds row's Flags text.
            s = "";
            flags = string(flags);
            if isempty(flags) || all(ismissing(flags)), return; end
            flags = strjoin(flags(~ismissing(flags)),"; ");
            T = mabr.ui.analysis.SeriesView.FlagCodes;
            c = strings(1,0);
            for k = 1:size(T,1)
                if contains(flags,T(k,1),'IgnoreCase',true), c(end+1) = T(k,2); end %#ok<AGROW>
            end
            s = strjoin(c," ");
        end

        function s = fitText(row,withCI)
            % The method's own threshold and, when it has one (and withCI,
            % default true), its interval: "34.9 [31.2–38.0]", "35 (30–40]",
            % ">80".
            if nargin < 2, withCI = true; end
            f = @(nm,d) mabr.ui.analysis.SeriesView.field(row,nm,d);
            s = mabr.analysis.SeriesThreshold.formatValue(double(f('Threshold',NaN)), ...
                mabr.ui.analysis.SeriesView.asText(f('Censored',"")),double(f('ThrLo',NaN)),double(f('ThrHi',NaN)));
            lo = double(f('CILower',NaN)); hi = double(f('CIUpper',NaN));
            if withCI && isfinite(lo) && isfinite(hi)
                s = s + " [" + mabr.ui.analysis.SeriesView.num(lo) + "–" + ...
                    mabr.ui.analysis.SeriesView.num(hi) + "]";
            end
        end

        function s = stateText(row)
            % "Decision: accepted by dstolz 15:42 · Final 35 (30–40] · Flags: ..."
            f = @(nm,d) mabr.ui.analysis.SeriesView.field(row,nm,d);
            d = mabr.ui.analysis.SeriesView.asText(f('Decision',""));
            switch d
                case "",           what = "none (unreviewed)";
                case "noresponse", what = "no response";
                case "allrespond", what = "all respond";
                case "manual"
                    v = double(f('ManualValue',NaN));
                    k = mabr.ui.analysis.SeriesView.asText(f('ManualKind',""));
                    what = "manual " + mabr.ui.analysis.SeriesView.num(v) + " dB";
                    if k == "level", what = what + " (lowest level with a response)"; end
                otherwise,         what = d;
            end
            if d ~= ""
                by = mabr.ui.analysis.SeriesView.asText(f('ReviewedBy',""));
                at = f('ReviewedAt',NaT);
                if by ~= "", what = what + " by " + by; end
                try
                    if isdatetime(at) && ~isnat(at), what = what + " " + string(at,'HH:mm'); end
                catch
                end
            end
            s = "Decision: " + what + " · Final " + mabr.ui.analysis.Style.formatThreshold(row);
            % (the method's own value with its interval: the series list
            % has no room for the interval)
            ft = mabr.ui.analysis.SeriesView.fitText(row);
            if ft ~= "" && ft ~= "n/a", s = s + " · Fit " + ft; end
            fl = mabr.ui.analysis.SeriesView.asText(f('Flags',""));
            if fl ~= "", s = s + " · Flags: " + fl; end
            note = mabr.ui.analysis.SeriesView.asText(f('Note',""));
            if note ~= "", s = s + " · Note: " + note; end
        end
    end

    methods (Static, Access = private)
        function cw = StripColumns(narrow)
            % The strip above the stack: polarity, normalise, compare,
            % (slice), cursor. Narrow (a workspace under 1000 px leaves
            % the stack ~250 px) the three controls share it and the cursor
            % readout gives its room up.
            if narrow
                cw = {100,92,'1x',0,0};
            else
                cw = {112,96,160,0,'1x'};
            end
        end

        function s = methodShort(id,label)
            % A threshold method's name for a narrow table (the full label
            % is in the table's tooltip).
            switch string(id)
                case "perm-glm",         s = "Permutation + GLM fit";
                case "perm-descending",  s = "Permutation, descending";
                case "power-descending", s = "Response power";
                case "fsp-descending",   s = "Fsp";
                case "presto",           s = "Split-half r (presto)";
                case "xcorr",            s = "Next-level correlation";
                case "xcorr-dtw",        s = "Next-level correlation (DTW)";
                otherwise,               s = string(label);
            end
        end

        function w = statusWord(status)
            % A SeriesThreshold status in words ("no-response" -> "no
            % response").
            w = string(status);
            if isempty(w) || ismissing(w), w = ""; return; end
            switch w
                case "insufficient", w = "too few levels";
                otherwise,           w = replace(w,"-"," ");
            end
        end

        function row = thresholdRow(S,sk)
            % One Thresholds row as a struct (Fit unwrapped), [] for none.
            row = [];
            try
                r = S.seriesRow(sk);
                if isempty(r), return; end
                row = table2struct(S.Thresholds(r,:));
                if isfield(row,'Fit') && iscell(row.Fit)
                    if isempty(row.Fit), row.Fit = []; else, row.Fit = row.Fit{1}; end
                end
            catch
                row = [];
            end
        end

        function v = field(s,name,default)
            v = default;
            if isstruct(s) && isfield(s,name)
                v = s.(name);
                if isempty(v), v = default; end
            end
        end

        function t = asText(v)
            % A scalar string, "" for missing/empty.
            try
                t = string(v);
                if isempty(t), t = ""; return; end
                t = t(1);
                if ismissing(t), t = ""; end
            catch
                t = "";
            end
        end

        function s = num(v)
            if ~isfinite(v)
                s = string(v);
            elseif abs(v - round(v)) < 1e-9
                s = string(sprintf('%g',v));
            else
                s = string(sprintf('%.1f',v));
            end
        end

        function v = member(v,allowed,default)
            try
                v = string(v);
                v = v(1);
                if ~any(allowed == v), v = string(default); end
            catch
                v = string(default);
            end
        end

        function y = levelY(G,L)
            % The stack height of a level value (between rows by interpolation).
            [x,o] = sort(G.Sign*G.Levels);
            off = G.Offsets(o);
            if numel(x) < 2
                y = off(1);
                return
            end
            y = interp1(x,off,G.Sign*L,'linear','extrap');
        end

        function [noResp,allResp] = censorMeaning(c,s)
            % What a censored threshold MEANS on a level axis of sign s (+1
            % louder is larger, -1 attenuation): SeriesThreshold reports
            % the side of the NUMBERS, so "right" (above the largest value)
            % is no response on a dB SPL axis and all respond on an
            % attenuation axis, and "left" the other way about.
            c = string(c);
            noResp  = (c == "right" && s > 0) || (c == "left" && s < 0);
            allResp = (c == "left" && s > 0) || (c == "right" && s < 0);
        end

        function i = bandAt(G,y)
            % The level whose band holds y (halfway to each neighbour).
            n = numel(G.Offsets);
            i = round((y - G.Offsets(1))/G.Step) + 1;
            if ~isfinite(i), i = n; end
            i = min(max(i,1),n);
        end

        function sg = loudness(lp,S,settings)
            % +1 when louder is a larger number, -1 on an attenuation axis.
            sg = 1;
            dirn = "auto";
            try
                st = S.Settings;
                if isempty(st), st = settings; end
                dirn = string(st.LevelDirection);
            catch
            end
            if dirn == "descending" || (dirn == "auto" && contains(lower(string(lp)),"attenuation"))
                sg = -1;
            end
        end

        function c = pColumn(metric)
            switch string(metric)
                case "power", c = "PowerP";
                case "fsp",   c = "FspP";
                otherwise,    c = "p";
            end
        end

        function c = metricColumn(metric)
            switch string(metric)
                case "splithalf", c = "SplitR";
                case "xcorr",     c = "XCorrUp";
                case "dtw",       c = "DTWUp";
                case "snr",       c = "SNR";
                case "strength",  c = "strength";
                case "power",     c = "PowerP";
                case "fsp",       c = "FspP";
                otherwise,        c = "p";
            end
        end

        function s = metricLabel(metric)
            switch string(metric)
                case "splithalf", s = "Split-half r";
                case "xcorr",     s = "r with next louder";
                case "dtw",       s = "r with next louder (DTW)";
                case "snr",       s = "SNR (dB)";
                case "strength",  s = "Permutation statistic";
                otherwise,        s = string(metric);
            end
        end

        function u = unitOf(mode,metric)
            switch string(mode)
                case "p",           u = "p";
                case "probability", u = "probability";
                case "fraction",    u = "fraction of range";
                otherwise
                    switch string(metric)
                        case {"splithalf","xcorr","dtw"}, u = "r";
                        case "snr",                       u = "dB";
                        case "strength",                  u = "statistic";
                        otherwise,                        u = "p";
                    end
            end
        end

        function v = pick(tf,a,b)
            if tf, v = a; else, v = b; end
        end

        function y = spread(x,y,d)
            % Label heights y at positions x, moved apart so that labels at
            % the same x are at least d apart (in their order, centred on
            % where they were).
            y = reshape(y,1,[]);
            x = reshape(x,1,[]);
            ok = isfinite(x) & isfinite(y);
            for ux = unique(x(ok))
                k = find(ok & x == ux);
                if numel(k) < 2, continue; end
                [v,o] = sort(y(k));
                for i = 2:numel(v)
                    v(i) = max(v(i),v(i-1) + d);
                end
                v = v - (mean(v) - mean(y(k)));
                y(k(o)) = v;
            end
        end

        function tip(h,text)
            try
                h.Tooltip = text;
            catch
            end
        end

        function trySet(h,prop,v)
            try
                h.(prop) = v;
            catch
            end
        end
    end
end
