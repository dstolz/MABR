classdef GridView < mabr.ui.analysis.View
% mabr.ui.analysis.GridView  The Grid tab: every series of a session side by side, levels stacked.
%
%   One column per series -- mabr.ui.analysis.Model.seriesKeys under the
%   strip's filters -- each a classic axes holding the series' condition
%   means stacked by level, loudest at the top. It is the whole session at a
%   glance and the place a threshold is most often judged, so what the
%   analysis decided is drawn ON the traces:
%
%     - the FINAL threshold is a green divider between the rows (an interval
%       halfway between its two levels; "NR" above the top row when nothing
%       responded; under the bottom row when everything did), and the
%       method's own threshold a dashed red divider wherever a decision
%       overrides it;
%     - traces below the final threshold are dashed grey, the selected
%       condition thick and amber;
%     - a right-margin note per trace (detected ● ○, ■ □ when overridden; p;
%       split-half r; SNR; n), amber when the condition has fewer clean
%       sweeps than Settings.MinSweeps;
%     - optionally the significant samples of each condition's permutation
%       test as a wide translucent band on the trace, the wave peaks (▲) and
%       troughs (▼) in the wave colours (not below threshold, where a pick
%       is noise by the analysis' own verdict), an SEM band, and another
%       analysed session's means as grey dash-dots (Compare with; dash-dot,
%       because dashed grey already means "below threshold").
%
%   SIGNIFICANCE (defect 11). A cluster-mass test's sigMask compares |t| per
%   sample with a null of cluster MASSES, which is not a per-sample test; the
%   samples a cluster-mass test found significant are its clusters with
%   p < alpha. So the shading is Detection.clusters(k).first:last for
%   clusterMass and Detection.sigMask for tmax/tfce -- both indices into the
%   tested rows, which run from Detection.RowsMs(1) to RowsMs(2) of Time
%   (GridView.sigSamples, a pure static so a test can hand it a Detection).
%
%   TIME. Traces are drawn in the session's displayed time (View.earTime):
%   re sound arrival when the session has a conduction delay (13 A9), less
%   the system time offset when it has one, re the timing pulse otherwise
%   -- the stored times are raw, so this is the one place they are shifted.
%   The window fields, the response window shading, the peak markers and a
%   compared session (in its own ear time) all use that time; the x label
%   says which ("Time re sound arrival (ms)") and the note under the grid
%   names the delay, its tooltip where the delay came from.
%
%   REDRAWING. Every graphics object is made once and afterwards only
%   rewritten (View.put, on change). The column axes are kept for the life
%   of the view: a filter or another session re-uses them -- adding rows or
%   peak lines where a layout needs more, hiding the axes and rows it does
%   not use -- because an axes costs ~0.15 s to make and a rebuild of a
%   seven-column grid used to take two seconds. A threshold decision, a
%   detection override or a peak edit redraws just the columns of the
%   series it names; a look, a filter or a settings change redraws the grid
%   over cached means; new data (an analysis, a rejection, a new session)
%   empties the caches. A layer switched off (band, significance, peaks,
%   thresholds) is hidden AND emptied, so that Copy data -- every line of
%   the grid, or of one column from its context menu -- copies what is
%   drawn.
%
%   A RAGGED grid -- a series that lacks a level another one has -- shows
%   "not recorded" in that row, never a flat trace: a zero line would read
%   as a measured absence of response.
%
%   STRIP. The look (window, scale, polarity, band, annotation and the
%   three switches) persists in the MABR pref OfflineAnalysisGrid, written
%   only from these controls' callbacks; the filters (stimulus, acquisition
%   mode, slices of further group parameters, Compare with) belong to the
%   session and are not remembered. Keys (Commands scope "grid"): n
%   normalises each trace to its own peak, + / − scale, Shift+↑/↓ the row
%   spacing, Ctrl+0 resets the three, ← / → step through the visible columns;
%   the threshold keys (a t i x c d, Alt+↓) and ↑/↓ are the Model's.
%
%   THE THRESHOLD BY HAND. In every column the green divider -- or, where
%   the series has no final threshold yet, its grip (the hollow green ◁ at
%   the column's right edge) -- can be dragged up and down, exactly as on
%   the Series stack (mabr.ui.analysis.ThresholdDrag): the pointer turns to
%   the resize arrows over it; while dragging, the divider follows the
%   pointer with a readout ("Threshold 37.5 dB SPL") and the status line
%   says the rest; the release is the Model's curation call the buttons
%   make -- between two of the column's levels it SNAPS half way (the
%   louder is the lowest level with a response), with Alt held it is the
%   value at the pointer (0.1 dB), above the loudest level no response,
%   below the quietest all respond. Esc cancels; Ctrl+Z undoes. A press on
%   the divider let go where it was is the ordinary click (it selects that
%   row), and a double-click still opens the Series tab. Only with the
%   Threshold layer shown (there is nothing to drag otherwise).
%
%   PUBLIC GESTURES (what a click does, for tests and scripts):
%     selectAt(seriesKey,level)       select that condition
%     clickAt(seriesKey,y,selType)    a click at data y in a column: the
%                                     row-band hit test (a trace's band reaches
%                                     halfway to each neighbour), selType
%                                     "normal" | "open" (double-click: the
%                                     Series tab) | "alt" (right-click: the
%                                     context menu's condition)
%     menuAction(name,condKey)        a context-menu item: "atLevel",
%                                     "noResponse", "accept", "overrideAuto",
%                                     "overrideResponse", "overrideNone",
%                                     "openSeries", "openTrials"
%     y = thresholdHandleY(seriesKey) where a column's divider (or grip) is
%     dragThreshold(seriesKey,y,Alt=,Cancel=)   press on it, move to y, let go
%   Handles.Columns is a struct array, one element per column shown (an
%   axes put away is hidden with its lines emptied): SeriesKey,
%   Axes, Menu, Lines (struct array per row: ConditionKey, Level, Line, Note,
%   Missing), Final (Tag GridFinal), FinalLabel, Fit (GridFit), Grip
%   (GridThresholdGrip), Sig (GridSignificance), Band (GridBand), Compare
%   (GridCompare), Peaks (Tag GridPeaks, UserData Wave/Kind), Shade
%   (GridResponseWindow), Scale (GridScale). ThresholdDragging is true from a
%   press on a divider to the release, ThresholdReadout the readout as last
%   drawn. The mouse's own callbacks are each axes' ButtonDownFcn and,
%   during a drag, the figure's WindowButtonMotionFcn/UpFcn/KeyPressFcn --
%   a test sets the figure's CurrentPoint and calls them.
%
%   See also mabr.ui.analysis.View, mabr.ui.analysis.Model,
%   mabr.ui.AnalysisApp, mabr.analysis.Session.conditionMean

% Daniel Stolzberg (c) 2026

    properties (Constant)
        ScaleIds       = ["column","global","fixed"]
        ScaleLabels    = ["Per column","Global","Fixed µV"]
        PolarityIds    = ["balanced","positive","negative","difference"]
        PolarityLabels = ["Balanced","+","−","Difference"]
        BandIds        = ["none","sem"]
        BandLabels     = ["None","SEM"]
        AnnotateIds    = ["detected","p","splitr","snr","n"]
        AnnotateLabels = ["Detected","p","Split-half r","SNR (dB)","n"]
        StepFactor     = 1.25        % one press of + / − / Shift+↑ / Shift+↓
        NotRecorded    = "not recorded"
        NotAnalysedText = "Not analysed — press Analyse (Ctrl+Enter)"
        NoSessionText  = "Open a session from the browser (double-click, Enter, or Open)."
        NoCompare      = "(none)"                % the Compare with dropdown's "no overlay"
        % margins of the axes inside the plot panel, pixels
        MarginLeft   = 62
        MarginRight  = 38            % per column: the right-margin notes
        MarginTop    = 40            % two-line column titles
        MarginBottom = 48
        ColumnGap    = 8
        TitleGap     = 12            % px left free between two columns' titles
        MinColumnPx  = 60            % narrower than this, the margins between columns shrink
        MarginRightTight = 16        % ... to this (and the gap to 2)
        % The smallest plot panel the window can have (its minimum size,
        % 1100 x 700, less the browser and the strip): anything smaller is a
        % panel not laid out yet, which is given NominalPanel instead.
        MinPanel     = [500 350]
        NominalPanel = [1170 680]
        % strip row 1: Stimulus | Mode (0 unless the session has both) |
        % slices (0 unless any) | gap | Compare with
        Strip1Widths = {'fit',120,'fit',120,0,'1x','fit',220}
    end

    properties (SetAccess = private)
        Gain (1,1) double = 1               % + / −
        Spacing (1,1) double = 1            % Shift+↑ / Shift+↓ (row pitch)
        Normalize (1,1) logical = false     % n: each trace to its own peak
        Stimulus (1,1) string = "All"       % filter: a stimulus, or "All"
        AcqMode (1,1) string = "All"        % filter: an acquisition mode, or "All"
        Slice = struct()                    % filter: further group parameter -> value text ("All")
        CompareKey (1,1) string = ""        % the session overlaid ("" none)
        MenuKey (1,1) string = ""           % the condition the context menu acts on
        Grid = []                           % what was last drawn (layout and the derived numbers)
        ThresholdReadout (1,1) string = ""  % the threshold drag's readout as last drawn
    end

    properties (Dependent)
        ThresholdDragging                   % a threshold divider is held (press to release)
    end

    properties (Access = private)
        StructSig (1,1) string = ""         % columns, rows and waves of the axes built
        SliceSig (1,1) string = ""          % the slice parameters of the dropdowns built
        MeanCache                           % containers.Map "polarity|key" -> {mean, sem}
        CompareCache                        % containers.Map session key -> struct(Session, Stamp)
        SeriesCache = []                    % seriesMembers' answers for one set of keys
        Pool = []                           % every column axes built (buildColumns re-uses them)
        LookOnly (1,1) logical = false      % refresh("all") from applySettings: keep the means
        EveryCache = []                     % allSeriesKeys' answer until the data change
        TitlePx (1,1) double = 238          % a column title's room, pixels: plot + right margin (relayout)
        PlotPx (1,1) double = 560           % a column's plot height, pixels (relayout)
        ColumnPx (1,1) double = 200         % a column's plot width, pixels (relayout)
        ThrDrag = []                        % the threshold drag in progress (ThresholdDrag)
        DividerAt = struct('SeriesKey',{},'Line',{},'HasLine',{},'Grip',{},'On',{})  % per column (drawThreshold)
        DragReadout = gobjects(0,1)         % the drag's readout
    end

    % =====================================================================
    methods
        function obj = GridView(parent,model,host)
            % GridView(parent,model,host) -- the app builds it lazily (View).
            if nargin < 3, host = []; end
            obj@mabr.ui.analysis.View(parent,model,host);
        end

        function delete(obj)
            % The context menus belong to the figure, not to the panel the
            % base class deletes: they go here (and a drag in progress puts
            % the window's callbacks back first).
            try
                if ~isempty(obj.ThrDrag) && isvalid(obj.ThrDrag)
                    obj.ThrDrag.cancel();
                    delete(obj.ThrDrag);
                end
            catch
            end
            try
                obj.deletePool();
            catch
            end
        end

        % ---- View contract -----------------------------------------------
        function build(obj)
            obj.MeanCache    = containers.Map('KeyType','char','ValueType','any');
            obj.CompareCache = containers.Map('KeyType','char','ValueType','any');
            obj.ViewLook = mabr.ui.analysis.GridView.sanitize(obj.ViewLook);
            Sty = mabr.ui.analysis.Style;

            g = uigridlayout(obj.Parent,[6 1],'Padding',[6 4 6 2],'RowSpacing',3, ...
                'BackgroundColor',Sty.Panel,'Tag','AnalysisGridLayout');
            g.RowHeight = {24,24,24,0,'1x',18};
            g.Layout.Row = 1; g.Layout.Column = 1;
            H = struct();
            H.Layout = g;
            % Three short rows rather than two long ones: every control fits
            % the window at its minimum size (1100 px with the browser open).

            % ---- strip, row 1: which series --------------------------------
            s1 = uigridlayout(g,[1 7],'Padding',[0 0 0 0],'ColumnSpacing',5, ...
                'BackgroundColor',Sty.Panel,'Tag','AnalysisGridStrip1');
            s1.Layout.Row = 1;
            s1.ColumnWidth = obj.Strip1Widths;
            H.Strip1 = s1;
            obj.label(s1,1,"Stimulus");
            H.Stimulus = uidropdown(s1,'Items',{'All'},'ItemsData',{'All'},'Value','All', ...
                'Tag','AnalysisGridStimulus', ...
                'Tooltip','Show the series of one stimulus, or of all of them.', ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onFilter("Stimulus",src)));
            H.Stimulus.Layout.Column = 2;
            H.AcqModeLabel = obj.label(s1,3,"Mode");
            H.AcqMode = uidropdown(s1,'Items',{'All','conventional','interleaved'}, ...
                'ItemsData',{'All','conventional','interleaved'},'Value','All', ...
                'Tag','AnalysisGridAcqMode', ...
                'Tooltip',['Show the conventional (blocked) or the interleaved runs only; ' ...
                'the session holds both, analysed as separate series.'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onFilter("AcqMode",src)));
            H.AcqMode.Layout.Column = 4;
            H.SliceGrid = uigridlayout(s1,[1 1],'Padding',[0 0 0 0],'ColumnSpacing',4, ...
                'BackgroundColor',Sty.Panel,'Tag','AnalysisGridSlicePanel');
            H.SliceGrid.Layout.Column = 5;
            H.SliceGrid.ColumnWidth = {0};
            H.Slices = gobjects(0);
            H.CompareLabel = obj.label(s1,7,"Compare with");
            H.Compare = uidropdown(s1,'Items',{'None'},'ItemsData',{char(obj.NoCompare)}, ...
                'Value',char(obj.NoCompare), ...
                'Tag','AnalysisGridCompare', ...
                'Tooltip',['Overlay another analysed session of this subject (its means from its ' ...
                'results file) as grey dash-dots.'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onCompare(src)));
            H.Compare.Layout.Column = 8;

            % ---- strip, row 2: the axes ------------------------------------
            s2 = uigridlayout(g,[1 14],'Padding',[0 0 0 0],'ColumnSpacing',5, ...
                'BackgroundColor',Sty.Panel,'Tag','AnalysisGridStrip2');
            s2.Layout.Row = 2;
            s2.ColumnWidth = {'fit',52,'fit',52,'fit','fit',96,52,'fit','fit',96,'fit',72,'1x'};
            H.Strip2 = s2;
            obj.label(s2,1,"Window");
            H.WindowStart = uieditfield(s2,'numeric','Value',obj.ViewLook.WindowStart, ...
                'Tag','AnalysisGridWindowStart','Limits',[-1000 1000], ...
                'Tooltip','Start of the time axis, ms (re sound arrival when the session has a conduction delay).', ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("WindowStart",src.Value)));
            H.WindowStart.Layout.Column = 2;
            obj.label(s2,3,"to");
            H.WindowEnd = uieditfield(s2,'numeric','Value',obj.ViewLook.WindowEnd, ...
                'Tag','AnalysisGridWindowEnd','Limits',[-1000 1000], ...
                'Tooltip','End of the time axis, ms.', ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("WindowEnd",src.Value)));
            H.WindowEnd.Layout.Column = 4;
            obj.label(s2,5,"ms");
            obj.label(s2,6,"Scale");
            H.Scale = uidropdown(s2,'Items',cellstr(obj.ScaleLabels),'ItemsData',cellstr(obj.ScaleIds), ...
                'Value',char(obj.ViewLook.Scale),'Tag','AnalysisGridScale', ...
                'Tooltip',['Row height: the largest mean of each column, of the whole grid, or a fixed ' ...
                'number of microvolts (+ / − scale, n normalises each trace).'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Scale",string(src.Value))));
            H.Scale.Layout.Column = 7;
            H.Fixed = uieditfield(s2,'numeric','Value',obj.ViewLook.Fixed, ...
                'Tag','AnalysisGridFixed','Limits',[1e-3 1e6],'LowerLimitInclusive','on', ...
                'Tooltip','Microvolts per row when Scale is Fixed µV.', ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Fixed",src.Value)));
            H.Fixed.Layout.Column = 8;
            obj.label(s2,9,"µV");
            obj.label(s2,10,"Polarity");
            H.Polarity = uidropdown(s2,'Items',cellstr(obj.PolarityLabels), ...
                'ItemsData',cellstr(obj.PolarityIds),'Value',char(obj.ViewLook.Polarity), ...
                'Tag','AnalysisGridPolarity', ...
                'Tooltip',['Balanced: each polarity weighted equally, so the cochlear microphonic ' ...
                'cancels; + or −: one polarity; Difference: (+ − −)/2, what follows polarity.'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Polarity",string(src.Value))));
            H.Polarity.Layout.Column = 11;
            obj.label(s2,12,"Band");
            H.Band = uidropdown(s2,'Items',cellstr(obj.BandLabels),'ItemsData',cellstr(obj.BandIds), ...
                'Value',char(obj.ViewLook.Band),'Tag','AnalysisGridBand', ...
                'Tooltip','Shade ± one standard error of each mean.', ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Band",string(src.Value))));
            H.Band.Layout.Column = 13;

            % ---- strip, row 3: what is marked ------------------------------
            s3 = uigridlayout(g,[1 7],'Padding',[0 0 0 0],'ColumnSpacing',8, ...
                'BackgroundColor',Sty.Panel,'Tag','AnalysisGridStrip3');
            s3.Layout.Row = 3;
            s3.ColumnWidth = {'fit',110,'fit','fit','fit','1x',100};
            H.Strip3 = s3;
            obj.label(s3,1,"Annotate");
            H.Annotate = uidropdown(s3,'Items',cellstr(obj.AnnotateLabels), ...
                'ItemsData',cellstr(obj.AnnotateIds),'Value',char(obj.ViewLook.Annotate), ...
                'Tag','AnalysisGridAnnotate', ...
                'Tooltip',['The note right of each trace: detected (● ○; ■ □ overridden), p, ' ...
                'split-half r, SNR or clean sweeps; amber below the minimum sweep count.'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Annotate",string(src.Value))));
            H.Annotate.Layout.Column = 2;
            H.Significance = uicheckbox(s3,'Text','Significance','Value',obj.ViewLook.Significance, ...
                'Tag','AnalysisGridSignificance', ...
                'Tooltip',['Shade the samples the permutation test found significant (clusters with ' ...
                'p < alpha for cluster mass; the corrected per-sample mask for tmax and TFCE).'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Significance",logical(src.Value))));
            H.Significance.Layout.Column = 3;
            H.Peaks = uicheckbox(s3,'Text','Peaks','Value',obj.ViewLook.Peaks, ...
                'Tag','AnalysisGridPeaks', ...
                'Tooltip',['Mark the picked wave peaks (▲) and troughs (▼) in the wave colours ' ...
                '(not below threshold).'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Peaks",logical(src.Value))));
            H.Peaks.Layout.Column = 4;
            H.Threshold = uicheckbox(s3,'Text','Threshold','Value',obj.ViewLook.Threshold, ...
                'Tag','AnalysisGridThreshold', ...
                'Tooltip',['Draw the final threshold (green) and the fit where a decision differs ' ...
                '(dashed red); traces below threshold dashed grey.'], ...
                'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onLook("Threshold",logical(src.Value))));
            H.Threshold.Layout.Column = 5;
            b = uibutton(s3,'Text','Copy data','Tag','AnalysisGridCopy', ...
                'Tooltip','Copy every trace of the grid as tab-separated columns (time, value per trace).', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.copyData()));
            b.Layout.Column = 7;
            mabr.ui.analysis.Style.setButtonIcon(b,'copy','left');
            H.Copy = b;

            % ---- the not-analysed banner ----------------------------------
            H.Banner = uilabel(g,'Text',char(obj.NotAnalysedText),'Tag','AnalysisGridBanner', ...
                'BackgroundColor',Sty.BarYellow,'FontColor',Sty.Ink,'Visible','off', ...
                'HorizontalAlignment','center');
            H.Banner.Layout.Row = 4;

            % ---- the plots ------------------------------------------------
            p = uipanel(g,'BorderType','none','BackgroundColor',[1 1 1], ...
                'Tag','AnalysisGridPanel','AutoResizeChildren','off');
            p.Layout.Row = 5;
            p.SizeChangedFcn = @(~,~) obj.relayoutSafe();
            H.Panel = p;

            % ---- the time-axis note and the hint strip --------------------
            f = uigridlayout(g,[1 2],'Padding',[0 0 0 0],'ColumnSpacing',8, ...
                'BackgroundColor',Sty.Panel);
            f.Layout.Row = 6;
            f.ColumnWidth = {'fit','1x'};
            H.TimeNote = uilabel(f,'Text','','Tag','AnalysisGridTimeNote','FontSize',10, ...
                'FontColor',Sty.AccentText,'Visible','off');
            % (as many of the keys as the strip holds, then "F1 all keys" --
            % fitted again in relayout; the tooltip has them all)
            H.Hints = uilabel(f,'Text',char(mabr.ui.analysis.Commands.hint("grid")), ...
                'Tag','AnalysisGridHints','FontSize',10,'FontColor',Sty.Muted, ...
                'HorizontalAlignment','right', ...
                'Tooltip',char("In each column, " + mabr.ui.analysis.ThresholdDrag.Hint + ...
                " (above the loudest level: no response; below the quietest: all respond; Esc " + ...
                "cancels; with the Threshold layer shown). The keys of this tab: " + ...
                mabr.ui.analysis.Commands.hint("grid")));
            H.Hints.Layout.Column = 2;

            H.Columns = mabr.ui.analysis.GridView.emptyColumns();
            obj.Handles = H;
        end

        function refresh(obj,what,keys)
            % Route a Model event: rebuild, redraw, or restyle the selection.
            if nargin < 3, keys = strings(0,1); end
            what = string(what);
            ev = obj.ViewEvent;
            switch what
                case "all"
                    % A look or a settings change keeps the means (a refit
                    % that regroups the series is caught by renderColumns);
                    % a new session, root or analysis does not.
                    if ~obj.LookOnly && ev ~= "SettingsChanged"
                        obj.clearMeans();
                        obj.dropMissingCompare();
                    end
                    obj.render();
                case {"files","rejection","detection","measures"}
                    obj.clearMeans();
                    obj.render();
                case {"thresholds","curation","peaks"}
                    % A decision, an override or a peak edit changes what
                    % is drawn over the traces of the series it names, never
                    % the traces, the columns or the scales: only those
                    % columns are redrawn (every curation key lands here).
                    obj.renderColumns(keys);
                case {"labels","columns","pools"}
                    % (the candidates may change; a compared session that is
                    % no longer one takes its overlay with it)
                    if ev == "ProjectChanged" && obj.syncCompare(), obj.render(); end
                case "status"
                    if ev == "ProjectChanged"
                        dropped = obj.syncCompare();
                        % a batch that re-analysed the compared session: its
                        % overlay is read again (compareSession sees the
                        % results file change)
                        if dropped || obj.CompareKey ~= "" && ...
                                (isempty(keys) || any(string(keys) == obj.CompareKey))
                            obj.render();
                        end
                    else
                        obj.syncBanner();
                    end
                case "queue"
                    if obj.syncCompare(), obj.render(); end
                    obj.syncBanner();
                case {"condition","series","level"}
                    obj.renderGuarded(@() obj.applySelection());
                otherwise
                    % message, save, busy, idle, wave, sweeps: nothing drawn here
            end
        end

        function handled = onCommand(obj,id)
            % The grid's own keys (Commands Target "view", and ← / → which
            % step through the VISIBLE columns rather than every series).
            handled = true;
            f = obj.StepFactor;
            switch string(id)
                case "view.normalize"
                    obj.Normalize = ~obj.Normalize;
                    obj.render();
                    if obj.Normalize
                        obj.say("Each trace normalised to its own peak (n).");
                    else
                        obj.say("Traces back at the common scale (n).");
                    end
                case "view.scaleUp"
                    obj.Gain = min(obj.Gain*f,64);
                    obj.render();
                case "view.scaleDown"
                    obj.Gain = max(obj.Gain/f,1/64);
                    obj.render();
                case "view.spacingUp"
                    obj.Spacing = min(obj.Spacing*f,8);
                    obj.render();
                case "view.spacingDown"
                    obj.Spacing = max(obj.Spacing/f,0.125);
                    obj.render();
                case "view.resetZoom"
                    obj.Gain = 1;
                    obj.Spacing = 1;
                    obj.Normalize = false;
                    obj.render();
                case {"nav.seriesPrev","nav.seriesPrevPg"}
                    obj.stepColumn(-1);
                case {"nav.seriesNext","nav.seriesNextPg"}
                    obj.stepColumn(1);
                case "nav.escape"
                    % (a threshold divider held: put it back; else the app's)
                    handled = obj.ThresholdDragging;
                    if handled, obj.ThrDrag.cancel(); end
                otherwise
                    handled = false;
            end
        end

        function tf = get.ThresholdDragging(obj)
            tf = ~isempty(obj.ThrDrag) && isvalid(obj.ThrDrag) && obj.ThrDrag.Active;
        end

        function p = hoverPointer(obj)
            % The resize arrows over a column's threshold divider (or its
            % grip): one CurrentPoint read per column until the one under
            % the pointer, and the sizes the last layout cached.
            p = "";
            try
                if ~obj.Built || ~obj.IsActive || obj.ThresholdDragging || isempty(obj.Grid), return; end
                if ~logical(obj.ViewLook.Threshold) || obj.Model.Busy, return; end
                D = obj.Grid;
                C = obj.Handles.Columns;
                for j = 1:min(numel(C),numel(D.Keys))
                    ax = C(j).Axes;
                    cp = ax.CurrentPoint;
                    x = cp(1,1);  y = cp(1,2);
                    if x < D.XLim(1) || x > D.XLim(2) || y < D.YLim(1) || y > D.YLim(2), continue; end
                    if obj.onDivider(j,x,y,false), p = "top"; end
                    return
                end
            catch
                p = "";
            end
        end

        function s = displaySettings(obj)
            % The look as the pref and a configuration hold it (cleaned: a
            % value the strip cannot show is its default).
            s = mabr.ui.analysis.GridView.sanitize(obj.ViewLook);
        end

        function activate(obj)
            % Shown again: whatever was missed while hidden may have been a
            % new session or new data, so the caches go before the redraw.
            if obj.Dirty
                obj.clearMeans();
                obj.dropMissingCompare();
            end
            activate@mabr.ui.analysis.View(obj);
        end

        function relayoutNow(obj)
            % (View.layoutSoon, on showing the tab) the columns placed for
            % the panel's size now: the window may have been resized while
            % the tab was hidden.
            obj.relayoutSafe();
        end

        function applySettings(obj,s)
            % Adopt a look (View.applySettings) and redraw over the means
            % already computed: a look changes how they are drawn, never
            % what they are (the cache is keyed by polarity).
            obj.LookOnly = true;
            try
                applySettings@mabr.ui.analysis.View(obj,s);
            catch me
                obj.LookOnly = false;
                rethrow(me);
            end
            obj.LookOnly = false;
        end

        % ---- gestures ----------------------------------------------------
        function selectAt(obj,seriesKey,level)
            % Select the condition of SERIESKEY at LEVEL (as a click on its
            % trace does). A level the series did not record says so.
            arguments
                obj
                seriesKey (1,1) string
                level (1,1) double
            end
            [j,k] = obj.slotOf(seriesKey,level);
            ck = obj.Grid.Cond(j,k);
            if ck == ""
                obj.say(obj.Grid.Labels(j) + " was not recorded at " + ...
                    mabr.ui.analysis.GridView.levelText(level) + ".",1);
                return
            end
            obj.Model.selectCondition(ck);
        end

        function ck = clickAt(obj,seriesKey,y,selType)
            % A click at data height Y in a column: the row-band hit test,
            % then what the click means (selType "normal", "open" for a
            % double-click -- the Series tab -- or "alt", a right-click,
            % which also makes it the context menu's condition).
            %   ck  (returned) the condition hit ("" for a row not recorded)
            arguments
                obj
                seriesKey (1,1) string
                y (1,1) double
                selType (1,1) string = "normal"
            end
            j = obj.columnOf(seriesKey);
            ck = obj.rowAt(j,y);
            if selType == "alt", obj.MenuKey = ck; end
            if ck == ""
                obj.say(obj.Grid.Labels(j) + ": " + obj.NotRecorded + " at this level.",1);
                return
            end
            obj.Model.selectCondition(ck);
            if selType == "open" && ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.activateTab("Series");
            end
        end

        function menuAction(obj,name,condKey)
            % One item of a column's context menu, on condKey (default: the
            % condition the menu was opened over).
            arguments
                obj
                name (1,1) string
                condKey (1,1) string = ""
            end
            if condKey == "", condKey = obj.MenuKey; end
            if condKey == ""
                error('mabr:ui:analysis:GridView:noCondition', ...
                    'Right-click a trace first: that row was not recorded.');
            end
            m = obj.Model;
            S = m.Session;
            if isempty(S)
                error('mabr:ui:analysis:noSession','Open a session first.');
            end
            sk = string(S.seriesOf(condKey));
            switch name
                case "atLevel"
                    m.selectCondition(condKey);
                    m.setThresholdAtLevel(obj.levelOf(S,condKey),sk);
                case "noResponse"
                    m.selectCondition(condKey);
                    m.setNoResponse(sk);
                case "accept"
                    m.selectCondition(condKey);
                    m.acceptFit(sk);
                case "overrideAuto"
                    m.setDetectionOverride(condKey,NaN);
                case "overrideResponse"
                    m.setDetectionOverride(condKey,1);
                case "overrideNone"
                    m.setDetectionOverride(condKey,0);
                case "openSeries"
                    m.selectCondition(condKey);
                    if ~isempty(obj.Host) && isvalid(obj.Host), obj.Host.activateTab("Series"); end
                case "openTrials"
                    m.selectCondition(condKey);
                    if ~isempty(obj.Host) && isvalid(obj.Host), obj.Host.activateTab("Trials"); end
                otherwise
                    error('mabr:ui:analysis:GridView:badAction','No grid menu action "%s".',name);
            end
        end

        function [y,onLine] = thresholdHandleY(obj,seriesKey)
            % Where SERIESKEY's threshold divider is in its column (data
            % units), or -- with no final threshold yet -- its grip; NaN
            % when there is nothing to drag (one level, not analysed, the
            % Threshold layer off).
            %   onLine  (returned) true for the divider, false for the grip
            arguments
                obj
                seriesKey (1,1) string
            end
            j = obj.columnOf(seriesKey);
            y = NaN;  onLine = false;
            if j > numel(obj.DividerAt), return; end
            d = obj.DividerAt(j);
            if isempty(d.SeriesKey) || d.SeriesKey ~= seriesKey || ~d.On, return; end
            onLine = d.HasLine;
            if onLine, y = d.Line; else, y = d.Grip; end
        end

        function dragThreshold(obj,seriesKey,y,opts)
            % Press on SERIESKEY's threshold divider (or its grip), move to
            % Y (the column's data units) and let go -- the mouse's own code
            % path, without a mouse (the rules: ThresholdDrag).
            %   opts.Alt     Alt held during the drag (the exact value)
            %   opts.Cancel  Esc instead of the release (nothing changes)
            arguments
                obj
                seriesKey (1,1) string
                y (1,1) double {mustBeFinite}
                opts.Alt (1,1) logical = false
                opts.Cancel (1,1) logical = false
            end
            [y0,~] = obj.thresholdHandleY(seriesKey);
            if ~isfinite(y0)
                error('mabr:ui:analysis:GridView:noThreshold', ...
                    'Series "%s" has no threshold divider to drag.',seriesKey);
            end
            j = obj.columnOf(seriesKey);
            ax = obj.Handles.Columns(j).Axes;
            if ~obj.thresholdPress(ax,obj.Grid.XLim(2),y0)
                error('mabr:ui:analysis:GridView:noThreshold','The threshold divider could not be taken.');
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

        function ck = rowAt(obj,j,y)
            % The condition whose row band holds data height Y in column J
            % ("" for a row this column did not record). A trace's band
            % reaches halfway to each neighbour; the outer rows' reach on.
            ck = "";
            G = obj.Grid;
            if isempty(G) || j < 1 || j > numel(G.Keys) || ~isfinite(y), return; end
            k = round(y/G.Pitch) + 1;
            k = min(max(k,1),numel(G.Levels));
            ck = G.Cond(j,k);
        end

        function txt = copyData(obj)
            % Every line of the grid as tab-separated columns (FigureExport).
            txt = "";
            if ~isfield(obj.Handles,'Panel') || ~isvalid(obj.Handles.Panel), return; end
            txt = mabr.ui.analysis.FigureExport.copyData(obj.Handles.Panel);
            if txt ~= "", obj.say("Grid data copied to the clipboard."); end
        end

        function setCompare(obj,key)
            % Overlay another session's means ("" none) -- what picking it
            % in Compare with does.
            arguments
                obj
                key (1,1) string
            end
            obj.CompareKey = key;
            obj.render();
        end

        function setFilter(obj,name,value)
            % Show one stimulus / acquisition mode / slice value ("All" =
            % every one) -- what the strip's dropdowns do.
            arguments
                obj
                name (1,1) string
                value (1,1) string
            end
            switch name
                case "Stimulus", obj.Stimulus = value;
                case "AcqMode",  obj.AcqMode = value;
                otherwise
                    obj.Slice.(char(matlab.lang.makeValidName(name))) = value;
            end
            obj.render();
        end
    end

    % =====================================================================
    methods (Static)
        function d = factoryDefaults()
            % The grid's look as it comes (pref OfflineAnalysisGrid's fields).
            d = struct('WindowStart',-2,'WindowEnd',10,'Scale',"column",'Fixed',5, ...
                'Polarity',"balanced",'Band',"none",'Annotate',"detected", ...
                'Significance',false,'Peaks',true,'Threshold',true);
        end

        function d = loadDefaults()
            % The look the user last chose, forgiving of a pref from another
            % version (a value it cannot show falls back to the default).
            d = mabr.ui.analysis.View.loadLook("OfflineAnalysisGrid", ...
                mabr.ui.analysis.GridView.factoryDefaults());
            d = mabr.ui.analysis.GridView.sanitize(d);
        end

        function saveDefaults(d)
            % Remember a look (the strip's callbacks; a configuration).
            mabr.ui.analysis.View.saveLook("OfflineAnalysisGrid",mabr.ui.analysis.GridView.sanitize(d));
        end

        function mask = sigSamples(det,time,alpha)
            % The samples of TIME a condition's permutation test found
            % significant (defect 11): clusters with p < ALPHA for a
            % cluster-mass test, the corrected per-sample mask for tmax and
            % TFCE. Both index the TESTED rows, which start at the Time
            % sample nearest Detection.RowsMs(1).
            %   det    a Session Detection record (struct) or [] / {}
            %   time   the session's Time (ms), any shape
            %   alpha  the detection's alpha
            %   mask   (returned) logical, numel(time) x 1
            n = numel(time);
            mask = false(n,1);
            if iscell(det)
                if isempty(det), return; end
                det = det{1};
            end
            if ~isstruct(det) || isempty(det) || ~isfield(det,'RowsMs') || n == 0, return; end
            rowsMs = double(det.RowsMs);
            if numel(rowsMs) < 1 || ~isfinite(rowsMs(1)), return; end
            time = double(time(:));
            [~,r0] = min(abs(time - rowsMs(1)));
            method = "";
            if isfield(det,'method'), method = string(det.method); end
            idx = zeros(0,1);
            if method == "clusterMass"
                cl = struct([]);
                if isfield(det,'clusters'), cl = det.clusters; end
                if isstruct(cl) && ~isempty(cl) && all(isfield(cl,["first","last","p"]))
                    for c = reshape(cl,1,[])
                        if isfinite(c.p) && c.p < alpha && isfinite(c.first) && isfinite(c.last)
                            idx = [idx; (c.first:c.last).']; %#ok<AGROW>
                        end
                    end
                end
            elseif isfield(det,'sigMask')
                idx = find(logical(det.sigMask(:)));
            end
            idx = r0 + idx - 1;
            idx = idx(idx >= 1 & idx <= n);
            mask(idx) = true;
        end

        function y = dividerY(value,censored,lo,hi,levels,rowY,pitch)
            % Where a threshold divider sits in a stack (NaN: none).
            %   value, censored, lo, hi   a threshold (Final or the fit) and
            %                             its censoring ("none", "interval",
            %                             "right", "left", "")
            %   levels, rowY              the rows' levels and heights
            %   pitch                     the row pitch
            % An interval sits halfway between its two levels; a value is
            % placed proportionally between the rows that bracket it. The
            % censoring describes the NUMBERS (SeriesThreshold: "right" is
            % beyond the largest value, "left" below the smallest), so it
            % sits half a row beyond the row of its BOUND -- lo of "> 80",
            % hi of "≤ 70" -- not beyond the extreme row: a level the method
            % left out (too few sweeps) may lie past the bound, and a
            % divider under it would read as "that level responds". On a
            % level stack (values growing up) "right" -- no response -- is
            % above that row and "left" -- every level responds -- under
            % it; on an attenuation stack (the largest value, the quietest,
            % at the bottom) the other way round. Without a bound, the
            % extreme row.
            y = NaN;
            levels = double(levels(:));  rowY = double(rowY(:));
            ok = isfinite(levels) & isfinite(rowY);
            if ~any(ok), return; end
            L = levels(ok);  Y = rowY(ok);
            top = max(Y);  bot = min(Y);
            [~,iHi] = max(L);  [~,iLo] = min(L);
            s = 1;                                   % +1: the values grow up the stack
            if Y(iHi) < Y(iLo), s = -1; end
            at = @(v) mabr.ui.analysis.GridView.levelY(v,levels,rowY);
            switch string(censored)
                case "right"
                    y = Y(iHi) + s*pitch/2;
                    if isfinite(lo), y = at(lo) + s*pitch/2; end
                case "left"
                    y = Y(iLo) - s*pitch/2;
                    if isfinite(hi), y = at(hi) - s*pitch/2; end
                case "interval"
                    yl = mabr.ui.analysis.GridView.levelY(lo,levels,rowY);
                    yh = mabr.ui.analysis.GridView.levelY(hi,levels,rowY);
                    if isfinite(yl) && isfinite(yh)
                        y = (yl + yh)/2;
                    elseif isfinite(yh)
                        y = yh - s*pitch/2;
                    elseif isfinite(yl)
                        y = yl + s*pitch/2;
                    end
                case "none"
                    y = mabr.ui.analysis.GridView.levelY(value,levels,rowY);
            end
            if isfinite(y)
                y = min(max(y,bot - pitch/2),top + pitch/2);
            end
        end

        function y = levelY(v,levels,rowY)
            % The height of level V on a stack whose rows are LEVELS at
            % ROWY: linear between the rows, extrapolated by the nearest
            % step beyond them (NaN for a non-finite V).
            y = NaN;
            if ~isfinite(v), return; end
            ok = isfinite(levels(:)) & isfinite(rowY(:));
            L = double(levels(ok));  Y = double(rowY(ok));
            if isempty(L), return; end
            [L,o] = sort(L);  Y = Y(o);
            if isscalar(L)
                y = Y;
                return
            end
            if v <= L(1)
                y = Y(1) + (v - L(1))*(Y(2) - Y(1))/(L(2) - L(1));
            elseif v >= L(end)
                y = Y(end) + (v - L(end))*(Y(end) - Y(end-1))/(L(end) - L(end-1));
            else
                y = interp1(L,Y,v);
            end
            if ~isfinite(y), y = NaN; end
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- drawing ------------------------------------------------------
        function render(obj)
            obj.renderGuarded(@() obj.renderNow());
        end

        function renderNow(obj)
            if ~obj.Built, return; end
            m = obj.Model;
            S = [];
            try
                S = m.Session;
            catch
            end
            obj.ViewLook = mabr.ui.analysis.GridView.sanitize(obj.ViewLook);
            obj.syncLookControls();
            if isempty(S)
                obj.deleteColumns();
                obj.Grid = [];
                obj.put('s_banner_vis',obj.Handles.Banner,'Visible','off');
                obj.syncBannerRow(false);
                obj.showEmpty(obj.NoSessionText);
                return
            end
            every = obj.allSeriesKeys();
            obj.syncFilters(S,every);
            obj.syncCompare();
            L = obj.layoutOf(S,every);
            if isempty(L.Keys)
                obj.deleteColumns();
                obj.Grid = [];
                if height(S.Conditions) == 0
                    obj.showEmpty("This session has no conditions to draw — see its files on the Session tab.");
                else
                    obj.showEmpty("No series match these filters.");
                end
                obj.syncBanner();
                return
            end
            obj.hideEmpty();
            if L.Sig ~= obj.StructSig || isempty(obj.Handles.Columns) || ...
                    ~all(arrayfun(@(c) isvalid(c.Axes),obj.Handles.Columns))
                obj.buildColumns(L);
            end
            D = obj.dataOf(S,L);
            obj.Grid = D;
            obj.relayout();
            for j = 1:numel(L.Keys)
                obj.drawColumn(S,D,j);
            end
            obj.drawTimeAxis();
            obj.applySelection();
            obj.syncBanner();
        end

        function L = layoutOf(obj,S,every)
            % The columns (series keys, filtered), the rows (every level any
            % column has, loudest last), and which condition fills each slot.
            %   every  Model.seriesKeys(): every series, in the Model's order
            m = obj.Model;
            keys = every;
            if obj.Stimulus ~= "All"
                keys = keys(mabr.ui.analysis.GridView.keyField(keys,"Stimulus") == obj.Stimulus);
            end
            if obj.AcqMode ~= "All"
                keys = keys(mabr.ui.analysis.GridView.keyField(keys,"AcqMode") == obj.AcqMode);
            end
            f = fieldnames(obj.Slice);
            for i = 1:numel(f)
                v = string(obj.Slice.(f{i}));
                if v == "All" || v == "", continue; end
                keys = keys(mabr.ui.analysis.GridView.keyField(keys,f{i}) == v);
            end
            keys = reshape(keys,[],1);
            lp = m.levelParam();
            C = S.Conditions;
            hasLp = lp ~= "" && ismember(char(lp),C.Properties.VariableNames);
            nC = numel(keys);
            [cks,labels] = obj.seriesMembers(S,keys,every);
            lvs = cell(nC,1);
            allLv = zeros(0,1);
            for j = 1:nC
                ck = cks{j};
                lv = nan(numel(ck),1);
                if hasLp && ~isempty(ck)
                    [tf,r] = ismember(ck,string(C.Key));
                    lv(tf) = double(C.(char(lp))(r(tf)));
                end
                lvs{j} = lv;
                allLv = [allLv; lv(isfinite(lv))]; %#ok<AGROW>
            end
            desc = obj.isDescending(S,lp);
            levels = unique(round(allLv,9));
            if isempty(levels)
                levels = NaN;
            elseif desc
                levels = flipud(levels);      % attenuation: the largest is the quietest
            end
            nR = numel(levels);
            Cond = strings(nC,nR);
            for j = 1:nC
                for k = 1:nR
                    if isnan(levels(k))
                        hit = find(isnan(lvs{j}),1);
                    else
                        hit = find(abs(lvs{j} - levels(k)) < 1e-6,1);
                    end
                    if ~isempty(hit), Cond(j,k) = cks{j}(hit); end
                end
            end
            waves = obj.waveNames(S);
            % (titles use the short names: the mode as ⧉, a stimulus word
            % every column shares left out -- Style.compactSeriesLabels)
            L = struct('Keys',keys,'Labels',labels,'Levels',reshape(levels,[],1),'Cond',Cond, ...
                'LevelParam',lp,'Descending',desc,'Waves',waves, ...
                'Short',reshape(mabr.ui.analysis.Style.compactSeriesLabels(labels),[],1));
            % (the condition in every slot is part of the structure: each
            % trace's DisplayName is written when the axes are built)
            L.Sig = strjoin(keys,";") + "#" + strjoin(string(levels),",") + "#" + ...
                strjoin(Cond(:),";") + "#" + strjoin(waves,",");
        end

        function [cks,labels] = seriesMembers(obj,S,keys,every)
            % The condition keys and the label of each series in KEYS -- the
            % Model's answers (seriesConditions, seriesLabel), worked out once
            % per set of condition and series keys. Both make the Session
            % group every condition again, which asked per column on every
            % redraw cost more than drawing the columns. A key names its
            % series' parameter values, so the answers depend on the keys
            % alone (the session object is deliberately not held: an old
            % session's sweeps must not outlive its switch).
            m = obj.Model;
            ck = reshape(string(S.Conditions.Key),[],1);
            stamp = string(m.SessionKey) + "#" + strjoin(ck,";") + "#" + strjoin(every,";");
            c = obj.SeriesCache;
            if isempty(c) || c.Stamp ~= stamp
                of = strings(0,1);
                try
                    of = reshape(string(S.seriesOf(ck)),[],1);
                catch
                end
                c = struct('Stamp',stamp,'Conds',ck,'Of',of, ...
                    'Labels',containers.Map('KeyType','char','ValueType','any'));
                obj.SeriesCache = c;
            end
            n = numel(keys);
            cks = cell(n,1);  labels = strings(n,1);
            for j = 1:n
                hit = strings(0,1);
                if numel(c.Of) == numel(c.Conds), hit = c.Conds(c.Of == keys(j)); end
                if isempty(hit), hit = reshape(string(m.seriesConditions(keys(j))),[],1); end
                cks{j} = hit;
                kj = char(keys(j));
                if ~isKey(c.Labels,kj), c.Labels(kj) = string(m.seriesLabel(keys(j))); end
                labels(j) = c.Labels(kj);
            end
        end

        function D = dataOf(obj,S,L)
            % Everything the drawing needs, computed once per render: the
            % displayed time, each slot's mean and SEM over the window, the
            % scales, the row heights, the threshold rows.
            m = obj.Model;
            look = obj.ViewLook;
            D = L;
            nC = numel(L.Keys);  nR = numel(L.Levels);
            t = double(S.Time(:));
            xe = obj.earTime(t);
            xl = obj.windowLimits(S);
            win = xe >= xl(1) - 1e-9 & xe <= xl(2) + 1e-9;
            D.XLim = xl;
            D.X = xe(win);
            D.Win = win;
            D.Offset = obj.timeAxis().Offset;
            D.Pitch = obj.Spacing;
            D.RowY = ((0:nR-1).')*D.Pitch;
            D.YLim = [-D.Pitch/2 - 0.6, D.RowY(end) + D.Pitch/2 + 0.6];
            % headroom for the row-spacing label in the top-left corner
            % (GridScale), so the loudest trace and its peak markers do not
            % run through it (in data units, not pixels: the same layout
            % gives the same limits whatever the window's size)
            D.YLim(2) = D.YLim(2) + 0.45;
            D.M = cell(nC,nR);  D.E = cell(nC,nR);
            D.Amp = nan(nC,nR);  D.N = nan(nC,nR);
            C = S.Conditions;
            keysC = string(C.Key);
            pol = string(look.Polarity);
            for j = 1:nC
                for k = 1:nR
                    ck = L.Cond(j,k);
                    if ck == "", continue; end
                    [mu,se] = obj.meanOf(S,ck,pol);
                    mu = mu(win);  se = se(win);
                    D.M{j,k} = mu;  D.E{j,k} = se;
                    a = max(abs(mu(isfinite(mu))));
                    if ~isempty(a), D.Amp(j,k) = a; end
                    r = find(keysC == ck,1);
                    if ~isempty(r) && ismember('nClean',C.Properties.VariableNames)
                        D.N(j,k) = double(C.nClean(r));
                    end
                end
            end
            minSw = mabr.ui.analysis.GridView.settingOf(m.Settings,'MinSweeps',0);
            D.MinSweeps = minSw;
            % row scale (volts per row pitch)
            colS = nan(nC,1);
            for j = 1:nC
                a = D.Amp(j,:);  n = D.N(j,:);
                good = isfinite(a) & (n >= minSw | ~isfinite(n));
                if any(good), colS(j) = max(a(good));
                elseif any(isfinite(a)), colS(j) = max(a(isfinite(a))); end
            end
            switch string(look.Scale)
                case "global"
                    g = max(colS(isfinite(colS)));
                    if isempty(g), g = NaN; end
                    colS(:) = g;
                case "fixed"
                    colS(:) = double(look.Fixed)*1e-6;
            end
            colS(~isfinite(colS) | colS <= 0) = 1e-6;
            D.ColScale = colS;
            D.Y = cell(nC,nR);
            D.Den = nan(nC,nR);
            for j = 1:nC
                for k = 1:nR
                    if isempty(D.M{j,k}), continue; end
                    den = colS(j);
                    if obj.Normalize && isfinite(D.Amp(j,k)) && D.Amp(j,k) > 0, den = D.Amp(j,k); end
                    D.Den(j,k) = den;
                    D.Y{j,k} = D.RowY(k) + obj.Gain*D.M{j,k}/den;
                end
            end
            % thresholds
            D.Thr = cell(nC,1);
            D.Below = false(nC,nR);
            D = obj.thresholdsOf(S,D,1:nC);
        end

        function D = thresholdsOf(obj,S,D,cols)
            % The threshold rows of columns COLS and which of their rows lie
            % below the Final threshold (dashed grey).
            dirn = "ascending";  if D.Descending, dirn = "descending"; end
            lv = D.Levels(:).';
            for j = reshape(cols,1,[])
                row = obj.thresholdRow(S,D.Keys(j));
                D.Thr{j} = row;
                D.Below(j,:) = false;
                if isempty(row), continue; end
                fc = string(row.FinalCensored);
                if ismissing(fc), fc = ""; end
                try
                    D.Below(j,:) = mabr.analysis.SeriesThreshold.belowThreshold(lv,row.Final,fc, ...
                        row.FinalLo,Direction=dirn,FinalHi=row.FinalHi);
                catch
                end
                D.Below(j,D.Cond(j,:) == "") = false;
            end
        end

        function renderColumns(obj,keys)
            obj.renderGuarded(@() obj.renderColumnsNow(keys));
        end

        function renderColumnsNow(obj,keys)
            % Redraw the columns of the series (or conditions) KEYS name --
            % all of them for none -- over the layout, means and scales
            % already computed; anything else in doubt is a full render.
            if ~obj.Built, return; end
            D = obj.Grid;
            H = obj.Handles.Columns;
            S = [];
            try
                S = obj.Model.Session;
            catch
            end
            % A refit can change more than the dividers: the waves, or the
            % level direction (LevelDirection is a thresholds setting, so
            % Settings ▸ "descending" arrives as ResultsChanged(thresholds)
            % with the session's settings already changed) -- which turns
            % the stack upside down. Either is a full render.
            if isempty(S) || isempty(D) || isempty(H) || numel(H) ~= numel(D.Keys) || ...
                    ~all(arrayfun(@(c) isvalid(c.Axes),H)) || ...
                    ~isequal(obj.waveNames(S),D.Waves) || ...
                    obj.isDescending(S,D.LevelParam) ~= D.Descending
                obj.renderNow();
                return
            end
            keys = reshape(string(keys),[],1);
            if isempty(keys)
                cols = 1:numel(D.Keys);
            else
                cols = find(ismember(D.Keys,keys) | any(ismember(D.Cond,keys),2)).';
            end
            if ~isempty(cols)
                D = obj.thresholdsOf(S,D,cols);
                if any(cellfun(@isempty,D.Thr(cols))) && height(S.Thresholds) > 0
                    % a column whose series the refit no longer has (its
                    % grouping changed): lay the grid out again
                    obj.clearMeans();
                    obj.renderNow();
                    return
                end
                obj.Grid = D;
                for j = cols
                    obj.drawColumn(S,D,j);
                end
                obj.applySelection();
            end
            obj.syncBanner();
        end

        function drawColumn(obj,S,D,j)
            % Write one column's graphics -- only what changed (put).
            H = obj.Handles.Columns(j);
            ax = H.Axes;
            look = obj.ViewLook;
            p = "g_" + j + "_";
            nR = numel(D.Levels);
            obj.put(p + "xlim",ax,'XLim',D.XLim);
            obj.put(p + "ylim",ax,'YLim',D.YLim);
            obj.put(p + "ytick",ax,'YTick',D.RowY.');
            if j == 1
                lab = strings(1,nR);
                for k = 1:nR, lab(k) = mabr.ui.analysis.GridView.levelText(D.Levels(k),false); end
                obj.put(p + "yticklab",ax,'YTickLabel',cellstr(lab));
                obj.put(p + "ylabel",ax.YLabel,'String',char(obj.levelAxisLabel(S,D.LevelParam)));
            else
                obj.put(p + "yticklab",ax,'YTickLabel',{});
            end

            % response window
            rw = obj.earTime(double(S.ResponseWindow(:).'));
            rw = [max(rw(1),D.XLim(1)) min(rw(2),D.XLim(2))];
            if rw(2) > rw(1)
                V = [rw(1) D.YLim(1); rw(2) D.YLim(1); rw(2) D.YLim(2); rw(1) D.YLim(2)];
            else
                V = nan(4,2);
            end
            obj.putPatch(p + "shade",H.Shade,V,[1 2 3 4]);
            obj.put(p + "shadevis",H.Shade,'Visible','on');

            % traces, notes, missing rows
            noteX = D.XLim(2) + 0.03*diff(D.XLim);
            mid = mean(D.XLim);
            ctx = obj.noteContext(S);
            for k = 1:nR
                R = H.Lines(k);
                q = p + k + "_";
                ck = D.Cond(j,k);
                obj.put(q + "lvis",R.Line,'Visible','on');      % (a re-used row may have been hidden)
                obj.put(q + "nvis",R.Note,'Visible','on');
                if ck == ""
                    obj.putXY(q + "xy",R.Line,NaN,NaN);
                    obj.put(q + "note",R.Note,'String','');
                    obj.put(q + "mpos",R.Missing,'Position',[mid D.RowY(k) 0]);
                    obj.put(q + "mvis",R.Missing,'Visible','on');
                    continue
                end
                obj.put(q + "mvis",R.Missing,'Visible','off');
                y = D.Y{j,k};
                if isempty(y), y = nan(size(D.X)); end
                obj.putXY(q + "xy",R.Line,D.X,y);
                [txt,col] = obj.noteFor(ctx,ck,D.N(j,k),D.MinSweeps);
                obj.put(q + "note",R.Note,'String',char(txt));
                obj.put(q + "notecol",R.Note,'Color',col);
                obj.put(q + "notepos",R.Note,'Position',[noteX D.RowY(k) 0]);
            end

            % SEM band. A layer switched off holds no data (here and below),
            % so that Copy data -- which copies every line of the axes,
            % shown or not -- copies what is drawn, and nothing is computed
            % for a layer nobody sees.
            bandOn = string(look.Band) == "sem";
            if bandOn
                [Vb,Fb] = obj.bandOf(D,j);
            else
                Vb = nan(3,2);  Fb = [1 2 3];
            end
            obj.putPatch(p + "band",H.Band,Vb,Fb);
            obj.put(p + "bandvis",H.Band,'Visible',mabr.ui.analysis.GridView.onoff(bandOn));

            % significance
            sigOn = logical(look.Significance);
            xs = NaN;  ys = NaN;
            if sigOn, [xs,ys] = obj.sigOf(S,D,j); end
            obj.putXY(p + "sig",H.Sig,xs,ys);
            obj.put(p + "sigvis",H.Sig,'Visible',mabr.ui.analysis.GridView.onoff(sigOn));

            % compare
            [xc,yc] = obj.compareOf(D,j);
            obj.putXY(p + "cmp",H.Compare,xc,yc);
            obj.put(p + "cmpvis",H.Compare,'Visible',mabr.ui.analysis.GridView.onoff(obj.CompareKey ~= ""));

            % peaks
            obj.drawPeaks(S,D,j);

            % thresholds and the title
            obj.drawThreshold(D,j);
            obj.drawTitle(D,j);
            obj.put(p + "scaletxt",H.Scale,'String',char(obj.scaleText(D,j)));
            obj.put(p + "scalevis",H.Scale,'Visible', ...
                mabr.ui.analysis.GridView.onoff(j == 1 || string(look.Scale) == "column" && ~obj.Normalize));
        end

        function drawThreshold(obj,D,j)
            H = obj.Handles.Columns(j);
            p = "g_" + j + "_";
            Sty = mabr.ui.analysis.Style;
            row = D.Thr{j};
            yF = NaN;  yT = NaN;  fc = "";
            if ~isempty(row)
                fc = string(row.FinalCensored);  if ismissing(fc), fc = ""; end
                tc = string(row.Censored);       if ismissing(tc), tc = ""; end
                yF = mabr.ui.analysis.GridView.dividerY(row.Final,fc,row.FinalLo,row.FinalHi, ...
                    D.Levels,D.RowY,D.Pitch);
                yT = mabr.ui.analysis.GridView.dividerY(row.Threshold,tc,row.ThrLo,row.ThrHi, ...
                    D.Levels,D.RowY,D.Pitch);
                if isfinite(yF) && isfinite(yT) && abs(yF - yT) < 1e-9, yT = NaN; end
                if ~isfinite(yF) && ~isfinite(yT), yT = NaN; end
            end
            show = logical(obj.ViewLook.Threshold);
            xl = D.XLim;
            if ~show, yF = NaN;  yT = NaN; end          % (switched off: no data to copy)
            obj.putXY(p + "final",H.Final,xl,[yF yF]);
            obj.put(p + "finalvis",H.Final,'Visible',mabr.ui.analysis.GridView.onoff(show && isfinite(yF)));
            obj.putXY(p + "fit",H.Fit,xl,[yT yT]);
            obj.put(p + "fitvis",H.Fit,'Visible',mabr.ui.analysis.GridView.onoff(show && isfinite(yT)));
            % "NR" for no response: censored beyond the loudest level --
            % "right" on a level axis, "left" on an attenuation axis (the
            % censoring describes the numbers; see dividerY)
            lab = "";
            if (fc == "right" && ~D.Descending) || (fc == "left" && D.Descending), lab = "NR"; end
            obj.put(p + "flab",H.FinalLabel,'String',char(lab));
            if isfinite(yF)
                obj.put(p + "flabpos",H.FinalLabel,'Position',[xl(2) - 0.02*diff(xl) yF 0]);
            end
            obj.put(p + "flabvis",H.FinalLabel,'Visible', ...
                mabr.ui.analysis.GridView.onoff(show && lab ~= "" && isfinite(yF)));
            obj.put(p + "flabcol",H.FinalLabel,'Color',Sty.FinalGreen);
            % the grip the mouse drags (ThresholdDrag): at the divider's
            % right end, filled; with no final threshold yet hollow, on the
            % fit or half way up the column's rows; none where nothing can
            % be decided (fewer than two levels, not analysed) or the layer
            % is off
            rec = find(D.Cond(j,:) ~= "");
            can = show && ~isempty(row) && numel(rec) >= 2;
            gy = yF;
            if ~isfinite(gy) && can
                if isfinite(yT)
                    gy = yT;
                else
                    k = max(1,floor(numel(rec)/2));
                    gy = mean(D.RowY(rec(k:min(k+1,end))));
                end
            end
            on = can && isfinite(gy);
            face = Sty.FinalGreen;
            if ~isfinite(yF), face = [1 1 1]; end
            if isfield(H,'Grip') && ~isempty(H.Grip) && isgraphics(H.Grip)
                obj.putXY(p + "grip",H.Grip,xl(2),gy);
                obj.put(p + "gripface",H.Grip,'MarkerFaceColor',face);
                obj.put(p + "gripvis",H.Grip,'Visible',mabr.ui.analysis.GridView.onoff(on));
            end
            obj.DividerAt(j) = struct('SeriesKey',D.Keys(j),'Line',yF,'HasLine',isfinite(yF), ...
                'Grip',gy,'On',on);
        end

        function drawTitle(obj,D,j)
            H = obj.Handles.Columns(j);
            row = D.Thr{j};
            l1 = D.Labels(j);
            if isfield(D,'Short') && numel(D.Short) >= j, l1 = D.Short(j); end
            l2 = "";
            if ~isempty(row)
                dec = string(row.Decision);  if ismissing(dec), dec = ""; end
                flags = "";
                try
                    flags = string(row.Flags);
                catch
                end
                gl = mabr.ui.analysis.Style.decisionGlyph(dec,flags);
                if gl ~= "", l1 = gl + " " + l1; end
                if dec == "excluded"
                    l2 = "excluded";
                else
                    l2 = mabr.ui.analysis.Style.formatThreshold(row);
                end
                if ~any(dec == ["","accepted"])
                    tc = string(row.Censored);  if ismissing(tc), tc = ""; end
                    fitTxt = mabr.analysis.SeriesThreshold.formatValue(double(row.Threshold),tc, ...
                        double(row.ThrLo),double(row.ThrHi));
                    if fitTxt ~= l2, l2 = l2 + " (fit " + fitTxt + ")"; end
                end
            end
            % (less a gap, so that neighbouring titles never touch)
            [l1,l2,fs] = mabr.ui.analysis.GridView.fitTitle(l1,l2,obj.TitlePx - obj.TitleGap);
            obj.put("g_" + j + "_title",H.Axes.Title,'String',{char(l1),char(l2)});
            obj.put("g_" + j + "_titlefs",H.Axes.Title,'FontSize',fs);
        end

        function drawPeaks(obj,S,D,j)
            % One line per wave x kind: the picks of this column's traces
            % (automatic or manual, not below threshold) on the drawn traces,
            % at their latencies in the displayed time.
            H = obj.Handles.Columns(j);
            p = "g_" + j + "_pk";
            show = logical(obj.ViewLook.Peaks);
            if ~show
                % switched off: hidden, and holding no data to copy
                for i = 1:numel(H.Peaks)
                    obj.putXY(p + i + "_xy",H.Peaks(i),NaN,NaN);
                    obj.put(p + i + "_vis",H.Peaks(i),'Visible','off');
                end
                return
            end
            P = table();
            try
                P = S.Peaks;
            catch
            end
            nR = numel(D.Levels);
            rows = cell(nR,1);             % each trace's Peaks rows
            pWave = strings(0,1);  lat = {[],[]};  st = {strings(0,1),strings(0,1)};
            if istable(P) && height(P) > 0 && all(ismember(["Key","Wave","PeakLatency"], ...
                    string(P.Properties.VariableNames)))
                pKey  = reshape(string(P.Key),[],1);
                pWave = reshape(string(P.Wave),[],1);
                G = @mabr.ui.analysis.GridView.numCol;
                lat   = {G(P,'PeakLatency'), G(P,'TroughLatency')};
                st    = {mabr.ui.analysis.GridView.strCol(P,'State',"auto"), ...
                         mabr.ui.analysis.GridView.strCol(P,'TroughState',"auto")};
                below = G(P,'BelowThreshold') == 1;
                for k = 1:nR
                    ck = D.Cond(j,k);
                    if ck == "" || isempty(D.Y{j,k}), continue; end
                    rows{k} = find(pKey == ck & ~below);
                end
            end
            for i = 1:numel(H.Peaks)
                h = H.Peaks(i);
                u = h.UserData;
                kind = 1 + (u.Kind == "N");
                x = zeros(0,1);  y = zeros(0,1);
                for k = 1:nR
                    r = rows{k};
                    if isempty(r), continue; end
                    r = r(find(pWave(r) == u.Wave,1));
                    if isempty(r), continue; end
                    t = lat{kind}(r);
                    if ~isfinite(t) || ~any(st{kind}(r) == ["auto","manual"]), continue; end
                    xe = t - D.Offset;
                    if xe < D.X(1) || xe > D.X(end), continue; end
                    yy = interp1(D.X,D.Y{j,k},xe);
                    if ~isfinite(yy), continue; end
                    x(end+1,1) = xe; %#ok<AGROW>
                    y(end+1,1) = yy; %#ok<AGROW>
                end
                if isempty(x), x = NaN; y = NaN; end
                obj.putXY(p + i + "_xy",h,x,y);
                obj.put(p + i + "_vis",h,'Visible',mabr.ui.analysis.GridView.onoff(show));
            end
        end

        function [V,F] = bandOf(obj,D,j)
            % One patch per column: one face per trace (mean ± SEM), NaN-padded.
            V = zeros(0,2);  faces = {};
            for k = 1:numel(D.Levels)
                e = D.E{j,k};  y = D.Y{j,k};
                if isempty(e) || isempty(y), continue; end
                e = obj.Gain*e/D.Den(j,k);
                ok = isfinite(e) & isfinite(y);
                if nnz(ok) < 2, continue; end
                x = D.X(ok);  yu = y(ok) + e(ok);  yd = y(ok) - e(ok);
                n0 = size(V,1);
                V = [V; [x yu]; [flipud(x) flipud(yd)]]; %#ok<AGROW>
                faces{end+1} = n0 + (1:2*numel(x)); %#ok<AGROW>
            end
            if isempty(faces)
                V = nan(3,2);  F = [1 2 3];
                return
            end
            w = max(cellfun(@numel,faces));
            F = nan(numel(faces),w);
            for i = 1:numel(faces)
                F(i,1:numel(faces{i})) = faces{i};
            end
        end

        function [x,y] = sigOf(obj,S,D,j)
            % The significant samples of each trace, NaN-separated.
            x = NaN;  y = NaN;
            C = S.Conditions;
            if ~ismember('Detection',C.Properties.VariableNames), return; end
            alpha = obj.detectionAlpha(S);
            keysC = string(C.Key);
            xs = {};  ys = {};
            for k = 1:numel(D.Levels)
                ck = D.Cond(j,k);
                if ck == "" || isempty(D.Y{j,k}), continue; end
                r = find(keysC == ck,1);
                if isempty(r), continue; end
                det = C.Detection(r);
                mask = mabr.ui.analysis.GridView.sigSamples(det,S.Time,alpha);
                mask = mask(D.Win);
                if ~any(mask), continue; end
                yy = D.Y{j,k};
                yy(~mask) = NaN;
                xs{end+1} = [D.X; NaN]; %#ok<AGROW>
                ys{end+1} = [yy; NaN]; %#ok<AGROW>
            end
            if ~isempty(xs)
                x = vertcat(xs{:});  y = vertcat(ys{:});
            end
        end

        function [x,y] = compareOf(obj,D,j)
            % The compared session's means at this column's conditions, on
            % this grid's scale (NaN-separated).
            x = NaN;  y = NaN;
            if obj.CompareKey == "", return; end
            O = obj.compareSession();
            if isempty(O), return; end
            xs = {};  ys = {};
            okeys = string(O.Conditions.Key);
            tO = double(O.Time(:));
            offO = 0;
            try
                offO = double(O.LatencyOffset);
                if ~isfinite(offO), offO = 0; end
            catch
            end
            xo = tO - offO;
            inWin = xo >= D.XLim(1) - 1e-9 & xo <= D.XLim(2) + 1e-9;
            for k = 1:numel(D.Levels)
                ck = D.Cond(j,k);
                if ck == "" || ~any(okeys == ck), continue; end
                try
                    mu = O.conditionMean(ck,string(obj.ViewLook.Polarity));
                catch
                    continue
                end
                den = D.Den(j,k);
                if ~isfinite(den), den = D.ColScale(j); end
                yy = D.RowY(k) + obj.Gain*double(mu(inWin))/den;
                xs{end+1} = [xo(inWin); NaN]; %#ok<AGROW>
                ys{end+1} = [yy(:); NaN]; %#ok<AGROW>
            end
            if ~isempty(xs)
                x = vertcat(xs{:});  y = vertcat(ys{:});
            end
        end

        function drawTimeAxis(obj)
            % The x label on the first column (View.labelTimeAxis), and the
            % delay named under the grid with its source in the tooltip.
            H = obj.Handles;
            if isempty(H.Columns), return; end
            T = obj.labelTimeAxis(H.Columns(1).Axes,Key="g_time");
            on = T.Offset ~= 0;
            txt = "";
            if on, txt = "Times " + T.Subtitle; end
            obj.put('s_timenote',H.TimeNote,'Text',char(txt));
            obj.put('s_timenote_tip',H.TimeNote,'Tooltip',char(T.Tip));
            obj.put('s_timenote_vis',H.TimeNote,'Visible',mabr.ui.analysis.GridView.onoff(on));
        end

        function applySelection(obj)
            % Restyle every trace for the selection and the threshold: the
            % selected condition thick amber, below-threshold dashed grey.
            D = obj.Grid;
            if isempty(D) || isempty(obj.Handles.Columns), return; end
            Sty = mabr.ui.analysis.Style;
            sel = "";
            try
                s = obj.Model.Selection;
                sel = string(s.ConditionKey);
            catch
            end
            thr = logical(obj.ViewLook.Threshold);
            for j = 1:numel(D.Keys)
                H = obj.Handles.Columns(j);
                inCol = false;
                for k = 1:numel(D.Levels)
                    q = "g_" + j + "_" + k + "_";
                    h = H.Lines(k).Line;
                    ck = D.Cond(j,k);
                    if ck ~= "" && ck == sel
                        col = Sty.Accent;  w = 2.5;  ls = '-';
                        inCol = true;
                    elseif thr && D.Below(j,k)
                        col = Sty.SubThreshold;  w = 0.9;  ls = '--';
                    else
                        col = Sty.Ink;  w = 1;  ls = '-';
                    end
                    obj.put(q + "col",h,'Color',col);
                    obj.put(q + "lw",h,'LineWidth',w);
                    obj.put(q + "ls",h,'LineStyle',ls);
                end
                tcol = Sty.Ink;
                if inCol, tcol = Sty.AccentText; end
                obj.put("g_" + j + "_tcol",H.Axes.Title,'Color',tcol);
            end
        end

        % ---- building -----------------------------------------------------
        function buildColumns(obj,L)
            % Make columns 1..n show L's series. Axes are kept for the life
            % of the view and re-used (an axes costs ~0.15 s to make -- its
            % toolbar, its interactions, its menu -- and a filter or a
            % session switch re-lays the grid out; moving one to another
            % container costs as much again): a column gains rows and peak
            % lines where L needs more and hides the rows it does not use,
            % and the axes no column needs are hidden where they are, their
            % lines emptied so that a copy of the data finds nothing there.
            Sty = mabr.ui.analysis.Style;
            nC = numel(L.Keys);  nR = numel(L.Levels);
            pool = obj.Pool;
            if isempty(pool), pool = mabr.ui.analysis.GridView.emptyPool(); end
            keep = arrayfun(@(c) ~isempty(c.Axes) && isvalid(c.Axes),pool);
            pool = pool(keep);
            for j = 1:nC
                if j > numel(pool)
                    pool(j) = obj.newColumn();
                end
                c = pool(j);
                obj.forgetWritten("g_" + j + "_");
                obj.forgetWritten("g_time");             % (column 1's x label)
                c.SeriesKey = L.Keys(j);
                c.Axes.UserData = L.Keys(j);
                if strcmp(c.Axes.Visible,'off')          % a parked axes back in use
                    c.Axes.Visible = 'on';
                    set([c.Axes.Title c.Axes.XLabel c.Axes.YLabel],'Visible','on');
                end
                added = false;
                % rows: one trace, note and "not recorded" per level
                for k = numel(c.Lines)+1:nR
                    c.Lines(k,1).Line = line(c.Axes,NaN,NaN,'Color',Sty.Ink,'LineWidth',1, ...
                        'PickableParts','none','HitTest','off','Tag','GridTrace');
                    c.Lines(k,1).Note = text(c.Axes,NaN,NaN,'','FontSize',8,'Clipping','off', ...
                        'HorizontalAlignment','left','VerticalAlignment','middle', ...
                        'PickableParts','none','HitTest','off','Tag','GridNote','Interpreter','none');
                    c.Lines(k,1).Missing = text(c.Axes,NaN,NaN,char(obj.NotRecorded),'FontSize',8, ...
                        'FontAngle','italic','Color',Sty.Muted,'HorizontalAlignment','center', ...
                        'VerticalAlignment','middle','PickableParts','none','HitTest','off', ...
                        'Tag','GridNotRecorded','Visible','off','Interpreter','none');
                    added = true;
                end
                for k = 1:numel(c.Lines)
                    if k <= nR
                        ck = L.Cond(j,k);
                        nm = "";
                        if ck ~= "", nm = obj.conditionName(ck); end
                        c.Lines(k).ConditionKey = ck;
                        c.Lines(k).Level = L.Levels(k);
                        set(c.Lines(k).Line,'UserData',ck,'DisplayName',char(nm));
                    else
                        % a row this layout does not have: empty and hidden
                        c.Lines(k).ConditionKey = "";
                        c.Lines(k).Level = NaN;
                        set(c.Lines(k).Line,'XData',NaN,'YData',NaN,'Visible','off', ...
                            'UserData',"",'DisplayName','');
                        set(c.Lines(k).Note,'String','','Visible','off');
                        set(c.Lines(k).Missing,'Visible','off');
                    end
                end
                % peaks: one line per wave x kind
                if ~isequal(c.Waves,L.Waves) || numel(c.Peaks) ~= 2*numel(L.Waves)
                    delete(c.Peaks(isgraphics(c.Peaks)));
                    pk = gobjects(0);
                    for w = reshape(L.Waves,1,[])
                        wc = mabr.ui.analysis.Style.waveColor(w);
                        pk(end+1) = line(c.Axes,NaN,NaN,'LineStyle','none','Marker','^','MarkerSize',4.5, ...
                            'MarkerFaceColor',wc,'MarkerEdgeColor',0.6*wc,'PickableParts','none', ...
                            'HitTest','off','Tag','GridPeaks','DisplayName',char(w + " peak"), ...
                            'UserData',struct('Wave',w,'Kind',"P")); %#ok<AGROW>
                        pk(end+1) = line(c.Axes,NaN,NaN,'LineStyle','none','Marker','v','MarkerSize',4.5, ...
                            'MarkerFaceColor','none','MarkerEdgeColor',wc,'PickableParts','none', ...
                            'HitTest','off','Tag','GridPeaks','DisplayName',char(w + " trough"), ...
                            'UserData',struct('Wave',w,'Kind',"N")); %#ok<AGROW>
                    end
                    c.Peaks = pk;
                    c.Waves = L.Waves;
                    added = true;
                end
                if added, obj.stackColumn(c); end
                pool(j) = c;
            end
            for j = nC+1:numel(pool)
                obj.parkColumn(pool(j),j);
            end
            obj.Pool = pool;
            cols = mabr.ui.analysis.GridView.emptyColumns();
            for j = 1:nC
                c = rmfield(pool(j),'Waves');
                c.Lines = c.Lines(1:nR);
                cols(j) = orderfields(c,fieldnames(cols));
            end
            obj.Handles.Columns = cols;
            obj.StructSig = L.Sig;
        end

        function c = newColumn(obj)
            % One column's axes with the objects every layout needs (rows
            % and peak lines are added by buildColumns as a layout asks).
            Sty = mabr.ui.analysis.Style;
            panel = obj.Handles.Panel;
            fig = ancestor(panel,'figure');
            ax = axes('Parent',panel,'Units','normalized','Position',[0.1 0.1 0.8 0.8], ...
                'Tag','AnalysisGridAxes','Box','off','TickDir','out','FontSize',9, ...
                'Color','none','XColor',Sty.Ink,'YColor',Sty.Muted,'NextPlot','add', ...
                'Layer','top','TickLength',[0.015 0.015],'Clipping','on','UserData',"");
            mabr.ui.hideAxesToolbar(ax);
            try
                disableDefaultInteractivity(ax);
            catch
            end
            ax.Title.FontWeight = 'normal';
            ax.Title.FontSize = 9;
            ax.Title.Interpreter = 'none';
            ax.ButtonDownFcn = obj.viewWrap(@(src,evt) obj.onAxesDown(src,evt));
            c = struct('SeriesKey',"",'Axes',ax,'Menu',[],'Lines',[],'Final',[], ...
                'FinalLabel',[],'Fit',[],'Grip',[],'Sig',[],'Band',[],'Compare',[],'Peaks',gobjects(0), ...
                'Shade',[],'Scale',[],'Waves',strings(1,0));
            c.Shade = patch(ax,'XData',nan(4,1),'YData',nan(4,1),'FaceColor',Sty.DataBlue, ...
                'FaceAlpha',0.07,'EdgeColor','none','PickableParts','none','HitTest','off', ...
                'Tag','GridResponseWindow');
            c.Band = patch(ax,'Vertices',nan(3,2),'Faces',[1 2 3],'FaceColor',Sty.Muted, ...
                'FaceAlpha',0.22,'EdgeColor','none','PickableParts','none','HitTest','off', ...
                'Tag','GridBand','Visible','off');
            c.Sig = line(ax,NaN,NaN,'Color',[Sty.DataBlue 0.35],'LineWidth',6, ...
                'PickableParts','none','HitTest','off','Tag','GridSignificance', ...
                'DisplayName','significant','Visible','off');
            c.Compare = line(ax,NaN,NaN,'Color',[0.40 0.40 0.40],'LineStyle','-.', ...
                'LineWidth',1,'PickableParts','none','HitTest','off','Tag','GridCompare', ...
                'DisplayName','compared session','Visible','off');
            c.Lines = struct('ConditionKey',cell(0,1),'Level',cell(0,1),'Line',cell(0,1), ...
                'Note',cell(0,1),'Missing',cell(0,1));
            c.Final = line(ax,NaN,NaN,'Color',Sty.FinalGreen,'LineWidth',1.6, ...
                'PickableParts','none','HitTest','off','Tag','GridFinal', ...
                'DisplayName','final threshold','Visible','off');
            c.Fit = line(ax,NaN,NaN,'Color',Sty.FitRed,'LineWidth',1.2,'LineStyle','--', ...
                'PickableParts','none','HitTest','off','Tag','GridFit', ...
                'DisplayName','fitted threshold','Visible','off');
            c.FinalLabel = text(ax,NaN,NaN,'','FontSize',8,'FontWeight','bold', ...
                'Color',Sty.FinalGreen,'HorizontalAlignment','right','VerticalAlignment','bottom', ...
                'PickableParts','none','HitTest','off','Tag','GridFinalLabel','Visible','off');
            % the divider's grip (drawing, not data: hidden handles, so Copy
            % data passes it by, and an exported figure drops it)
            c.Grip = line(ax,NaN,NaN,'LineStyle','none','Marker','<','MarkerSize',6, ...
                'MarkerEdgeColor',Sty.FinalGreen,'MarkerFaceColor',Sty.FinalGreen,'LineWidth',1, ...
                'Clipping','off','PickableParts','none','HitTest','off','HandleVisibility','off', ...
                'Tag','GridThresholdGrip','Visible','off');
            % (in the headroom dataOf keeps above the loudest trace; a white
            % ground keeps it legible where a large response still reaches)
            c.Scale = text(ax,0.01,1,'','Units','normalized','FontSize',7.5,'Color',Sty.Muted, ...
                'HorizontalAlignment','left','VerticalAlignment','top','PickableParts','none', ...
                'HitTest','off','Tag','GridScale','Interpreter','none','BackgroundColor',[1 1 1], ...
                'Margin',1);
            c.Menu = obj.buildMenu(fig,ax);
        end

        function stackColumn(~,c)
            % Drawing order, bottom to top: response window, SEM band,
            % significance, compared session, traces (with their notes),
            % peak markers, the threshold dividers and their labels -- kept
            % when rows or peak lines are added to an axes built earlier.
            R = c.Lines;
            rows = gobjects(0,1);
            for k = numel(R):-1:1
                rows = [rows; R(k).Missing; R(k).Note; R(k).Line]; %#ok<AGROW>
            end
            % (the grip has hidden handles, so it is not among Children: it
            % stays where it was made, above everything built before it)
            top = [c.Scale; c.FinalLabel; c.Fit; c.Final; flipud(c.Peaks(:)); rows; ...
                c.Compare; c.Sig; c.Band; c.Shade];
            try
                ch = c.Axes.Children;
                rest = ch(~ismember(ch,top));
                c.Axes.Children = [top; rest];
            catch me
                mabr.log.vprintf(2,'Grid view: drawing order not kept (%s).',me.message);
            end
        end

        function parkColumn(obj,c,j)
            % An axes no column needs now: hidden with everything in it
            % (title and labels too) and its lines emptied, so that neither
            % the drawing nor a copy of the data finds it, until a layout
            % needs it again.
            obj.forgetWritten("g_" + j + "_");
            if strcmp(c.Axes.Visible,'off') && c.Axes.UserData == "", return; end
            try
                set(findobj(c.Axes,'Type','line'),'XData',NaN,'YData',NaN);
                set(allchild(c.Axes),'Visible','off');
                set([c.Axes.Title c.Axes.XLabel c.Axes.YLabel],'Visible','off');   % (an axes off shows its title)
                c.Axes.Visible = 'off';
                c.Axes.UserData = "";
            catch me
                mabr.log.vprintf(2,'Grid view: an unused column was not put away (%s).',me.message);
            end
        end

        function s = conditionName(obj,ck)
            % Model.conditionLabel, remembered with the series answers (it
            % names each trace for a copy of the data).
            c = obj.SeriesCache;
            k = char("c:" + ck);
            if ~isempty(c) && isKey(c.Labels,k)
                s = c.Labels(k);
                return
            end
            s = string(obj.Model.conditionLabel(ck));
            if ~isempty(c), c.Labels(k) = s; end
        end

        function cm = buildMenu(obj,fig,ax)
            % A column's context menu; the condition under the click is
            % resolved when it opens (MenuKey).
            cm = uicontextmenu(fig,'Tag','AnalysisGridMenu');
            act = @(name) obj.viewWrap(@(~,~) obj.menuAction(name));
            uimenu(cm,'Text','Set threshold at this level (t)','Tag','AnalysisGridMenuAtLevel', ...
                'MenuSelectedFcn',act("atLevel"));
            uimenu(cm,'Text','No response (i)','Tag','AnalysisGridMenuNoResponse', ...
                'MenuSelectedFcn',act("noResponse"));
            uimenu(cm,'Text','Accept fit (a)','Tag','AnalysisGridMenuAccept', ...
                'MenuSelectedFcn',act("accept"));
            dm = uimenu(cm,'Text','Detection override (d)','Tag','AnalysisGridMenuOverride');
            uimenu(dm,'Text','Automatic','Tag','AnalysisGridMenuOverrideAuto', ...
                'MenuSelectedFcn',act("overrideAuto"));
            uimenu(dm,'Text','Response','Tag','AnalysisGridMenuOverrideResponse', ...
                'MenuSelectedFcn',act("overrideResponse"));
            uimenu(dm,'Text','No response','Tag','AnalysisGridMenuOverrideNone', ...
                'MenuSelectedFcn',act("overrideNone"));
            uimenu(cm,'Text','Open in Series (Enter)','Separator','on','Tag','AnalysisGridMenuOpenSeries', ...
                'MenuSelectedFcn',act("openSeries"));
            uimenu(cm,'Text','Open in Trials (Shift+Enter)','Tag','AnalysisGridMenuOpenTrials', ...
                'MenuSelectedFcn',act("openTrials"));
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            try
                cm.ContextMenuOpeningFcn = @(src,~) obj.onMenuOpening(src,ax);
            catch
            end
            ax.ContextMenu = cm;
        end

        function deleteColumns(obj)
            % No columns to show: every axes is put away (parkColumn).
            if ~isfield(obj.Handles,'Columns'), return; end
            for j = 1:numel(obj.Pool)
                if ~isempty(obj.Pool(j).Axes) && isvalid(obj.Pool(j).Axes)
                    obj.parkColumn(obj.Pool(j),j);
                end
            end
            obj.Handles.Columns = mabr.ui.analysis.GridView.emptyColumns();
            obj.StructSig = "";
            obj.forgetWritten('g_');
        end

        function deletePool(obj)
            % The view goes: its axes go with its panels, its context menus
            % (children of the figure) here.
            for c = reshape(obj.Pool,1,[])
                try
                    if ~isempty(c.Menu) && isvalid(c.Menu), delete(c.Menu); end
                catch
                end
                try
                    if ~isempty(c.Axes) && isvalid(c.Axes), delete(c.Axes); end
                catch
                end
            end
            obj.Pool = [];
            if isfield(obj.Handles,'Columns')
                obj.Handles.Columns = mabr.ui.analysis.GridView.emptyColumns();
            end
            obj.StructSig = "";
        end

        function relayoutSafe(obj)
            try
                obj.relayout();
            catch
            end
        end

        function relayout(obj)
            % Place the axes: pixel margins (level labels, right-margin
            % notes, titles, ticks) turned into normalized positions for the
            % panel's current size.
            if ~isfield(obj.Handles,'Columns') || isempty(obj.Handles.Columns), return; end
            panel = obj.Handles.Panel;
            pos = [0 0 0 0];
            try
                pos = getpixelposition(panel);
            catch
            end
            W = pos(3);  Hh = pos(4);
            if W < obj.MinPanel(1) || Hh < obj.MinPanel(2)
                % Not laid out yet (a uitab's contents get their size when
                % the client next draws; SizeChangedFcn then places them
                % again): the panel's size in the window's default layout,
                % rather than the placeholder size a new component reports.
                W = obj.NominalPanel(1);  Hh = obj.NominalPanel(2);
            end
            n = numel(obj.Handles.Columns);
            ml = obj.MarginLeft;  mr = obj.MarginRight;  gap = obj.ColumnGap;
            w = (W - ml - n*mr - (n-1)*gap - 4)/n;
            if w < obj.MinColumnPx
                % Many series in a narrow panel (13 at the window's minimum
                % size): the room between the columns gives way before the
                % plots do -- a note may then reach into the next column --
                % rather than the last columns falling off the panel.
                mr = obj.MarginRightTight;  gap = 2;
                w = (W - ml - n*mr - (n-1)*gap - 4)/n;
            end
            w = max(w,24);
            h = max(Hh - obj.MarginTop - obj.MarginBottom,40);
            obj.PlotPx = h;
            obj.ColumnPx = w;
            try
                obj.put('s_hints',obj.Handles.Hints,'Text', ...
                    char(mabr.ui.analysis.Commands.hint("grid",MaxChars=max(30,floor(W/5.6)))));
            catch
            end
            for j = 1:n
                x = ml + (j-1)*(w + mr + gap);
                p = [x/W obj.MarginBottom/Hh w/W h/Hh];
                obj.put("g_" + j + "_pos",obj.Handles.Columns(j).Axes,'Position',p);
            end
            if w + mr ~= obj.TitlePx
                % narrower or wider columns: the titles are fitted again
                obj.TitlePx = w + mr;
                D = obj.Grid;
                if ~isempty(D) && numel(D.Keys) == n
                    for j = 1:n
                        obj.drawTitle(D,j);
                        obj.put("g_" + j + "_scaletxt",obj.Handles.Columns(j).Scale,'String', ...
                            char(obj.scaleText(D,j)));
                    end
                end
            end
        end

        % ---- callbacks ----------------------------------------------------
        function onLook(obj,field,value)
            % A look control: adopt, remember (the user chose it), redraw.
            field = string(field);
            if any(field == ["WindowStart","WindowEnd"])
                w = [double(obj.ViewLook.WindowStart) double(obj.ViewLook.WindowEnd)];
                w(1 + (field == "WindowEnd")) = double(value);
                if ~(w(2) > w(1))
                    % Refused, and the field put back. (sanitize would reset
                    % BOTH ends to the defaults, and the field -- whose
                    % Written record still holds the value before the edit
                    % -- would go on showing the number typed.)
                    obj.forgetWritten('s_wstart');
                    obj.forgetWritten('s_wend');
                    obj.syncLookControls();
                    obj.say(sprintf('The time window must end after it starts (%g to %g ms kept).', ...
                        obj.ViewLook.WindowStart,obj.ViewLook.WindowEnd),1);
                    return
                end
            end
            obj.ViewLook.(char(field)) = value;
            obj.ViewLook = mabr.ui.analysis.GridView.sanitize(obj.ViewLook);
            obj.savePrefs();
            obj.render();
        end

        function onFilter(obj,name,src)
            obj.setFilter(name,string(src.Value));
        end

        function onSlice(obj,src)
            obj.setFilter(string(src.UserData),string(src.Value));
        end

        function onCompare(obj,src)
            k = string(src.Value);
            if k == obj.NoCompare, k = ""; end
            obj.setCompare(k);
            if obj.CompareKey ~= ""
                obj.say("Comparing with " + obj.compareLabel(obj.CompareKey) + " (grey dash-dots).");
            end
        end

        function onAxesDown(obj,ax,~)
            % A click on a column: which row, and what kind of click -- or,
            % a plain press on the threshold divider (or its grip), the
            % divider taken (thresholdPress; let go where it was, it is
            % this click after all).
            fig = ancestor(ax,'figure');
            st = "normal";
            try
                st = string(fig.SelectionType);
            catch
            end
            x = NaN;  y = NaN;
            try
                cp = ax.CurrentPoint;
                x = cp(1,1);  y = cp(1,2);
            catch
            end
            if st == "normal" && obj.thresholdPress(ax,x,y), return; end
            obj.clickAt(string(ax.UserData),y,st);
        end

        % ---- the threshold by hand (ThresholdDrag) ------------------------
        function tf = thresholdPress(obj,ax,x,y)
            % A press at (x,y) in column AX takes its threshold divider
            % when within ThresholdDrag.HitPixels of it (or GripPixels of
            % its grip): the drag runs over the column's own recorded rows.
            tf = false;
            D = obj.Grid;
            if isempty(D) || ~isfinite(y) || obj.ThresholdDragging, return; end
            try
                if obj.Model.Busy, return; end
            catch
                return
            end
            sk = string(ax.UserData);
            j = find(D.Keys == sk,1);
            if isempty(j) || ~obj.onDivider(j,x,y,true,ax), return; end
            rec = D.Cond(j,:) ~= "";
            [~,sy] = obj.columnScale(ax,true);
            S = obj.Model.Session;
            obj.ThrDrag = mabr.ui.analysis.ThresholdDrag(ax,obj.Model,sk,D.RowY(rec),D.Levels(rec), ...
                Unit=mabr.ui.analysis.SeriesView.levelUnitOf(D.LevelParam,S),Axis="y", ...
                PxPerUnit=sy,Pointer="top", ...
                Preview=@(o) obj.gridPreview(j,o),End=@(c) obj.gridDragEnd(j,c), ...
                Click=@() obj.clickAt(sk,y,"normal"),Status=@(t,l) obj.say(t,l), ...
                Wrap=@(f) obj.viewWrap(f));
            obj.ThrDrag.begin(y);
            tf = true;
        end

        function gridPreview(obj,j,o)
            % Column J's divider (and grip) where a release would put it,
            % and the readout above it.
            D = obj.Grid;
            if isempty(D) || j > numel(obj.Handles.Columns), return; end
            H = obj.Handles.Columns(j);
            xl = D.XLim;
            F = o.F;
            y = mabr.ui.analysis.GridView.dividerY(F.Final,string(F.FinalCensored),F.FinalLo, ...
                F.FinalHi,D.Levels,D.RowY,D.Pitch);
            if ~isfinite(y), y = o.Pos; end
            green = mabr.ui.analysis.Style.FinalGreen;
            set(H.Final,'XData',xl,'YData',[y y],'Visible','on');
            nr = o.Kind == "noresponse";
            lab = '';  if nr, lab = 'NR'; end
            set(H.FinalLabel,'String',lab,'Position',[xl(2) - 0.02*diff(xl) y 0], ...
                'Visible',mabr.ui.analysis.GridView.onoff(nr));
            if ~isempty(H.Grip) && isgraphics(H.Grip)
                set(H.Grip,'XData',xl(2),'YData',y,'MarkerFaceColor',green,'Visible','on');
            end
            % the method's own threshold stays in view, dashed red, as the
            % reference the divider is being moved from
            yT = NaN;
            row = D.Thr{j};
            if ~isempty(row)
                tc = string(row.Censored);  if ismissing(tc), tc = ""; end
                yT = mabr.ui.analysis.GridView.dividerY(row.Threshold,tc,row.ThrLo,row.ThrHi, ...
                    D.Levels,D.RowY,D.Pitch);
            end
            set(H.Fit,'XData',xl,'YData',[yT yT],'Visible',mabr.ui.analysis.GridView.onoff(isfinite(yT)));
            % (written behind put's back: drawThreshold writes them again)
            p = "g_" + j + "_";
            for k = ["final","finalvis","flab","flabpos","flabvis","grip","gripface","gripvis","fit","fitvis"]
                obj.forgetWritten(p + k);
            end
            r = obj.DragReadout;
            if isempty(r) || ~isgraphics(r) || r.Parent ~= H.Axes
                delete(r(isgraphics(r)));
                r = text(H.Axes,NaN,NaN,'','Color',green,'FontWeight','bold','FontSize',8, ...
                    'HorizontalAlignment','right','VerticalAlignment','bottom','Interpreter','none', ...
                    'BackgroundColor',[1 1 1],'Margin',1,'Clipping','off','HitTest','off', ...
                    'PickableParts','none','HandleVisibility','off','Tag','GridThresholdReadout');
                obj.DragReadout = r;
            end
            set(r,'Position',[xl(2) - 0.06*diff(xl) y 0],'String',char(o.Short));
            obj.ThresholdReadout = o.Short;
        end

        function gridDragEnd(obj,j,committed)
            % The readout goes; cancelled (or a decision the series already
            % had), column J's divider back where the Model has it -- a
            % decision made redraws the column through the Model's event.
            r = obj.DragReadout;
            obj.DragReadout = gobjects(0,1);
            delete(r(isgraphics(r)));
            obj.ThresholdReadout = "";
            D = obj.Grid;
            if ~committed && ~isempty(D) && j <= numel(obj.Handles.Columns)
                p = "g_" + j + "_";
                for k = ["final","finalvis","flab","flabpos","flabvis","grip","gripface","gripvis","fit","fitvis"]
                    obj.forgetWritten(p + k);
                end
                try
                    obj.drawThreshold(D,j);
                catch me
                    mabr.log.vprintf(2,'Grid view: divider not put back (%s).',me.message);
                end
            end
        end

        function tf = onDivider(obj,j,x,y,precise,ax)
            % (x,y) within HitPixels of column J's divider (anywhere along
            % it) or GripPixels of its grip. PRECISE measures the axes now
            % (a press); otherwise the sizes the last layout cached (a hover).
            tf = false;
            D = obj.Grid;
            if j > numel(obj.DividerAt) || isempty(D), return; end
            d = obj.DividerAt(j);
            if isempty(d.SeriesKey) || d.SeriesKey ~= D.Keys(j) || ~d.On, return; end
            if nargin < 6, ax = obj.Handles.Columns(j).Axes; end
            [sx,sy] = obj.columnScale(ax,precise);
            xl = D.XLim;
            if d.HasLine && x >= xl(1) && x <= xl(2) && ...
                    abs(y - d.Line)*sy <= mabr.ui.analysis.ThresholdDrag.HitPixels
                tf = true;
            elseif hypot((x - xl(2))*sx,(y - d.Grip)*sy) <= mabr.ui.analysis.ThresholdDrag.GripPixels
                tf = true;
            end
        end

        function [sx,sy] = columnScale(obj,ax,precise)
            % Pixels per ms and per data unit of a column's axes.
            D = obj.Grid;
            w = NaN;  h = NaN;
            if precise
                try
                    pos = getpixelposition(ax);
                    w = pos(3);  h = pos(4);
                catch
                end
            end
            if ~(w > 10 && h > 10), w = obj.ColumnPx;  h = obj.PlotPx; end
            sx = w/diff(D.XLim);
            sy = h/diff(D.YLim);
        end

        function onMenuOpening(obj,cm,ax)
            % (not wrapped by Host.cb: that hands the keyboard back to the
            % window afterwards, which would close the menu being opened)
            try
                obj.menuOpening(cm,ax);
            catch me
                mabr.log.vprintf(2,'Grid view: context menu not prepared (%s).',me.message);
            end
        end

        function menuOpening(obj,cm,ax)
            % Resolve the condition under the right-click, and say what the
            % items will act on.
            y = NaN;
            try
                cp = ax.CurrentPoint;
                y = cp(1,2);
            catch
            end
            j = obj.columnOf(string(ax.UserData));
            ck = obj.rowAt(j,y);
            if ck == "" && obj.MenuKey ~= "" && any(obj.Grid.Cond(j,:) == obj.MenuKey)
                ck = obj.MenuKey;
            end
            obj.MenuKey = ck;
            items = findall(cm,'Type','uimenu');
            tags = string(get(items,'Tag'));
            needs = startsWith(tags,"AnalysisGridMenu");     % not the export items
            set(items(needs),'Enable',mabr.ui.analysis.GridView.onoff(ck ~= ""));
            if ck == "", return; end
            S = obj.Model.Session;
            lv = obj.levelOf(S,ck);
            at = findall(cm,'Tag','AnalysisGridMenuAtLevel');
            if ~isempty(at)
                at.Text = char("Set threshold at " + mabr.ui.analysis.GridView.levelText(lv) + " (t)");
            end
            v = NaN;
            try
                D = S.DetectionOverrides;
                r = find(string(D.Key) == ck,1,'last');
                if ~isempty(r), v = double(D.Value(r)); end
            catch
            end
            set(findall(cm,'Tag','AnalysisGridMenuOverrideAuto'),'Checked',mabr.ui.analysis.GridView.onoff(isnan(v)));
            set(findall(cm,'Tag','AnalysisGridMenuOverrideResponse'),'Checked',mabr.ui.analysis.GridView.onoff(v == 1));
            set(findall(cm,'Tag','AnalysisGridMenuOverrideNone'),'Checked',mabr.ui.analysis.GridView.onoff(v == 0));
        end

        function stepColumn(obj,d)
            % ← / →: the neighbouring VISIBLE column, at the nearest level.
            D = obj.Grid;
            if isempty(D) || isempty(D.Keys), return; end
            m = obj.Model;
            sel = m.Selection;
            j = find(D.Keys == string(sel.SeriesKey),1);
            if isempty(j)
                j = 1;
            else
                j = min(max(j + d,1),numel(D.Keys));
                if D.Keys(j) == string(sel.SeriesKey), return; end
            end
            lv = sel.Level;
            if isnan(lv)
                m.selectSeries(D.Keys(j));
            else
                m.selectSeries(D.Keys(j),Level=lv);
            end
        end

        % ---- controls in step with the state ------------------------------
        function syncLookControls(obj)
            H = obj.Handles;
            L = obj.ViewLook;
            obj.put('s_wstart',H.WindowStart,'Value',double(L.WindowStart));
            obj.put('s_wend',H.WindowEnd,'Value',double(L.WindowEnd));
            obj.put('s_scale',H.Scale,'Value',char(L.Scale));
            obj.put('s_fixed',H.Fixed,'Value',double(L.Fixed));
            obj.put('s_fixed_en',H.Fixed,'Enable',mabr.ui.analysis.GridView.onoff(string(L.Scale) == "fixed"));
            obj.put('s_pol',H.Polarity,'Value',char(L.Polarity));
            obj.put('s_band',H.Band,'Value',char(L.Band));
            obj.put('s_ann',H.Annotate,'Value',char(L.Annotate));
            obj.put('s_sig',H.Significance,'Value',logical(L.Significance));
            obj.put('s_pk',H.Peaks,'Value',logical(L.Peaks));
            obj.put('s_thr',H.Threshold,'Value',logical(L.Threshold));
        end

        function syncFilters(obj,S,every)
            % Stimulus / mode / slice dropdowns for this session (EVERY: all
            % its series keys); a filter value the session does not hold
            % falls back to All.
            H = obj.Handles;
            stims = unique(mabr.ui.analysis.GridView.keyField(every,"Stimulus"));
            stims = stims(stims ~= "");
            if ~any(stims == obj.Stimulus), obj.Stimulus = "All"; end
            obj.putDropdown('s_stim',H.Stimulus,["All"; stims],["All"; stims],obj.Stimulus);
            modes = unique(mabr.ui.analysis.GridView.keyField(every,"AcqMode"));
            modes = modes(modes ~= "");
            both = numel(modes) > 1;
            if ~both || ~any(modes == obj.AcqMode), obj.AcqMode = "All"; end
            obj.putDropdown('s_acq',H.AcqMode,["All"; modes],["All"; modes],obj.AcqMode);
            cw = obj.Strip1Widths;       % (never read back off the layout)
            if ~both, cw([3 4]) = {0,0}; end
            obj.put('s_acq_vis',H.AcqMode,'Visible',mabr.ui.analysis.GridView.onoff(both));
            obj.put('s_acqlab_vis',H.AcqModeLabel,'Visible',mabr.ui.analysis.GridView.onoff(both));
            % slices: further group parameters
            extra = obj.sliceParams(S,every);
            sig = strjoin(extra,",");
            if sig ~= obj.SliceSig
                obj.buildSlices(extra);
            end
            if isempty(extra)
                cw{5} = 0;
                obj.Slice = struct();
            else
                cw{5} = 'fit';
                for i = 1:numel(extra)
                    nm = char(matlab.lang.makeValidName(extra(i)));
                    vals = unique(mabr.ui.analysis.GridView.keyField(every,extra(i)));
                    vals = mabr.ui.analysis.GridView.sortValues(vals(vals ~= ""));
                    cur = "All";
                    if isfield(obj.Slice,nm), cur = string(obj.Slice.(nm)); end
                    if ~any(vals == cur), cur = "All"; end
                    obj.Slice.(nm) = cur;
                    dd = obj.Handles.Slices(i);
                    obj.putDropdown("s_slice" + i,dd,["All"; vals],["All"; vals],cur);
                end
            end
            obj.put('s_strip1_cw',H.Strip1,'ColumnWidth',cw);
        end

        function extra = sliceParams(~,S,keys)
            % Group parameters beyond the stimulus, the mode and the column
            % parameter that take more than one value among the series.
            extra = strings(1,0);
            try
                cols = string(S.groupColumns());
            catch
                return
            end
            cols = setdiff(cols,["Stimulus","AcqMode"],'stable');
            if isempty(cols), return; end
            fp = "";
            try
                fp = string(S.frequencyParam());
            catch
            end
            if ~any(cols == fp), fp = cols(1); end
            for c = setdiff(cols,fp,'stable')
                v = unique(mabr.ui.analysis.GridView.keyField(keys,c));
                if numel(v(v ~= "")) > 1, extra(end+1) = c; end %#ok<AGROW>
            end
        end

        function buildSlices(obj,extra)
            H = obj.Handles;
            delete(H.SliceGrid.Children);
            n = numel(extra);
            obj.forgetWritten('s_slice');
            dds = gobjects(0);
            if n == 0
                H.SliceGrid.ColumnWidth = {0};
            else
                H.SliceGrid.ColumnWidth = repmat({'fit',90},1,n);
                for i = 1:n
                    lab = uilabel(H.SliceGrid,'Text',char(extra(i)),'FontColor',mabr.ui.analysis.Style.Ink);
                    lab.Layout.Row = 1;  lab.Layout.Column = 2*i - 1;
                    dd = uidropdown(H.SliceGrid,'Items',{'All'},'ItemsData',{'All'},'Value','All', ...
                        'Tag','AnalysisGridSlice','UserData',extra(i), ...
                        'Tooltip',char("Show the series at one " + extra(i) + ", or at every one."), ...
                        'ValueChangedFcn',obj.viewWrap(@(src,~) obj.onSlice(src)));
                    dd.Layout.Row = 1;  dd.Layout.Column = 2*i;
                    dds(end+1) = dd; %#ok<AGROW>
                end
            end
            obj.Handles.Slices = dds;
            obj.SliceSig = strjoin(extra,",");
        end

        function dropped = syncCompare(obj)
            % The sessions worth comparing with: this subject's other
            % analysed sessions sharing a stimulus (none in blind review).
            %   dropped  (returned) true when the session compared with is
            %            no longer one of them (its overlay must go: a
            %            caller outside a render redraws)
            key0 = obj.CompareKey;
            H = obj.Handles;
            m = obj.Model;
            blind = false;
            try
                blind = m.BlindReview;
            catch
            end
            [keys,labels] = obj.compareCandidates();
            if blind
                keys = strings(0,1);  labels = strings(0,1);
                obj.CompareKey = "";
            end
            if ~any(keys == obj.CompareKey), obj.CompareKey = ""; end
            cur = obj.CompareKey;
            if cur == "", cur = obj.NoCompare; end
            obj.putDropdown('s_cmp',H.Compare,["None"; labels],[obj.NoCompare; keys],cur);
            vis = mabr.ui.analysis.GridView.onoff(~blind);
            obj.put('s_cmp_vis',H.Compare,'Visible',vis);
            obj.put('s_cmplab_vis',H.CompareLabel,'Visible',vis);
            obj.put('s_cmp_en',H.Compare,'Enable',mabr.ui.analysis.GridView.onoff(~isempty(keys)));
            dropped = key0 ~= "" && obj.CompareKey == "";
        end

        function [keys,labels] = compareCandidates(obj)
            keys = strings(0,1);  labels = strings(0,1);
            m = obj.Model;
            if isempty(m.Session) || isempty(m.Catalog) || m.SessionKey == "", return; end
            try
                info = m.sessionInfo(m.SessionKey);
                T = m.Catalog.Sessions;
                S = m.Session;
                stims = unique(mabr.ui.analysis.GridView.keyField(string(S.Conditions.Key),"Stimulus"));
                if obj.Stimulus ~= "All", stims = obj.Stimulus; end
                for r = 1:height(T)
                    k = string(T.Key(r));
                    if k == m.SessionKey || any(k == info.Members), continue; end
                    if string(T.Subject(r)) ~= string(info.Subject), continue; end
                    st = strtrim(split(string(T.Stimuli(r)),","));
                    if ~isempty(stims) && all(stims ~= "") && ~any(ismember(st,stims)), continue; end
                    if ~m.hasResults(k), continue; end
                    keys(end+1,1) = k; %#ok<AGROW>
                    labels(end+1,1) = obj.compareLabel(k,T(r,:)); %#ok<AGROW>
                end
            catch me
                mabr.log.vprintf(2,'Grid view: compare candidates unavailable (%s).',me.message);
            end
        end

        function s = compareLabel(obj,key,row)
            s = key;
            try
                if nargin < 3
                    T = obj.Model.Catalog.Sessions;
                    row = T(string(T.Key) == key,:);
                end
                lab = string(row.InferredLabel(1));
                st = row.Start(1);
                if ~isnat(st), lab = lab + " · " + string(st,'yyyy-MM-dd HH:mm'); end
                s = lab;
            catch
            end
        end

        function dropMissingCompare(obj)
            % A new session: the compared one is kept only while it is still
            % a candidate (syncCompare decides).
            obj.CompareCache = containers.Map('KeyType','char','ValueType','any');
        end

        function O = compareSession(obj)
            % The compared session, read from its results file once (and
            % again only when the file changes).
            O = [];
            key = obj.CompareKey;
            if key == "", return; end
            try
                f = obj.Model.sessionInfo(key).ResultsFile;
                d = dir(f);
                if isempty(d), obj.CompareKey = ""; return; end
                stamp = [d(1).datenum d(1).bytes];
                if isKey(obj.CompareCache,char(key))
                    c = obj.CompareCache(char(key));
                    if isequal(c.Stamp,stamp), O = c.Session; return; end
                end
                O = mabr.analysis.Session.fromResults(f,Verbose=false);
                obj.CompareCache(char(key)) = struct('Session',O,'Stamp',stamp);
            catch me
                O = [];
                obj.say("Could not read the compared session's results: " + string(me.message),1);
                obj.CompareKey = "";
            end
        end

        function syncBanner(obj)
            on = false;
            try
                m = obj.Model;
                on = ~isempty(m.Session) && string(m.Status.State) == "not-analysed";
            catch
            end
            obj.put('s_banner_vis',obj.Handles.Banner,'Visible',mabr.ui.analysis.GridView.onoff(on));
            obj.syncBannerRow(on);
        end

        function syncBannerRow(obj,on)
            rh = obj.Handles.Layout.RowHeight;
            if on, rh{4} = 22; else, rh{4} = 0; end
            obj.put('s_rows',obj.Handles.Layout,'RowHeight',rh);
        end

        % ---- small pieces -------------------------------------------------
        function xl = windowLimits(obj,S)
            % The displayed time range: the look's window, within the time
            % the session's conditions hold (compact files hold 0-9.9 ms).
            ws = double(obj.ViewLook.WindowStart);
            we = double(obj.ViewLook.WindowEnd);
            if ~(isfinite(ws) && isfinite(we) && we > ws), ws = -2; we = 10; end
            t = double(S.Time(:));
            ext = [t(1) t(end)];
            try
                E = double(S.Conditions.Extent);
                E = E(all(isfinite(E),2),:);
                if ~isempty(E), ext = [max(min(E(:,1)),t(1)) min(max(E(:,2)),t(end))]; end
            catch
            end
            ext = obj.earTime(ext);
            xl = [max(ws,ext(1)) min(we,ext(2))];
            if ~(xl(2) > xl(1)), xl = ext; end
            if ~(xl(2) > xl(1)), xl = [ws we]; end
        end

        function [mu,se] = meanOf(obj,S,ck,pol)
            % conditionMean, remembered until the data change (clearMeans);
            % keyed by session too, since two sessions of one design share
            % their condition keys.
            k = char(obj.Model.SessionKey + "|" + pol + "|" + ck);
            if isKey(obj.MeanCache,k)
                v = obj.MeanCache(k);
                mu = v{1};  se = v{2};
                return
            end
            [mu,se] = S.conditionMean(ck,pol);
            mu = double(mu(:));  se = double(se(:));
            obj.MeanCache(k) = {mu,se};
        end

        function clearMeans(obj)
            % The data changed (or a new session): means and series again.
            obj.MeanCache = containers.Map('KeyType','char','ValueType','any');
            obj.EveryCache = [];
        end

        function every = allSeriesKeys(obj)
            % Model.seriesKeys() -- every series, in the Model's order --
            % remembered until the data change (clearMeans): it groups every
            % condition, as much work as drawing two columns, and a look or
            % a filter does not change it.
            if isempty(obj.EveryCache)
                obj.EveryCache = reshape(string(obj.Model.seriesKeys()),[],1);
            end
            every = obj.EveryCache;
        end

        function ctx = noteContext(~,S)
            % What the right-margin notes are read from, taken out of the
            % tables once per column rather than once per trace.
            C = S.Conditions;
            ctx = struct('Keys',reshape(string(C.Key),[],1));
            ctx.Detected = mabr.ui.analysis.GridView.numCol(C,'Detected');
            ctx.HasDetected = ismember('Detected',C.Properties.VariableNames);
            ctx.p      = mabr.ui.analysis.GridView.numCol(C,'p');
            ctx.SplitR = mabr.ui.analysis.GridView.numCol(C,'SplitR');
            ctx.SNR    = mabr.ui.analysis.GridView.numCol(C,'SNR');
            ctx.OvKeys = strings(0,1);  ctx.OvVals = zeros(0,1);
            try
                Dv = S.DetectionOverrides;
                if height(Dv) > 0
                    ctx.OvKeys = reshape(string(Dv.Key),[],1);
                    ctx.OvVals = reshape(double(Dv.Value),[],1);
                end
            catch
            end
        end

        function [txt,col] = noteFor(obj,ctx,ck,n,minSw)
            % The right-margin note of one trace, and its colour.
            Sty = mabr.ui.analysis.Style;
            col = Sty.Ink;
            r = find(ctx.Keys == ck,1);
            txt = "";
            if ~isempty(r)
                switch string(obj.ViewLook.Annotate)
                    case "detected"
                        if ctx.HasDetected && isfinite(ctx.Detected(r))   % (NaN: not measured)
                            det = ctx.Detected(r) == 1;
                            rr = find(ctx.OvKeys == ck,1,'last');
                            ov = ~isempty(rr) && isfinite(ctx.OvVals(rr));
                            txt = mabr.ui.analysis.Style.detectionGlyph(det,ov);
                            if ~det, col = Sty.Muted; end
                        end
                    case "p"
                        txt = mabr.ui.analysis.GridView.pText(ctx.p(r));
                    case "splitr"
                        if isfinite(ctx.SplitR(r)), txt = string(sprintf('%.2f',ctx.SplitR(r))); end
                    case "snr"
                        if isfinite(ctx.SNR(r)), txt = string(sprintf('%.1f',ctx.SNR(r))); end
                end
            end
            if string(obj.ViewLook.Annotate) == "n" && isfinite(n)
                txt = string(sprintf('%d',round(n)));
            end
            if isfinite(n) && n < minSw
                col = Sty.AccentText;
                if txt == "", txt = string(sprintf('n %d',round(n))); end
            end
        end

        function s = scaleText(obj,D,j)
            % The vertical scale of column j in words: how many microvolts
            % apart two adjacent rows are (a trace one row tall is that
            % big) -- "rows 3.2 µV apart", or "↕ 3.2 µV" where a column is
            % too narrow for the words (13 columns in a small window).
            if obj.Normalize
                s = "each trace to its peak";
                return
            end
            v = D.Pitch*D.ColScale(j)/obj.Gain;
            u = mabr.ui.analysis.Style.formatUV(v,2);
            s = "rows " + u + " apart";
            if strlength(s)*0.66*7.5 > obj.TitlePx - obj.TitleGap
                s = "↕ " + u;
            end
        end

        function s = levelAxisLabel(~,S,lp)
            % The level axis' label in its own unit: the session's level
            % reference for a sound level, kHz for a frequency the user made
            % the Level parameter, none for any other parameter
            % (SeriesView.levelUnitOf -- "Frequency (dB)" would misstate it).
            if lp == "", s = ""; return; end
            u = mabr.ui.analysis.SeriesView.levelUnitOf(lp,S);
            if u == "", s = lp; else, s = lp + " (" + u + ")"; end
        end

        function row = thresholdRow(~,S,sk)
            % The series' Thresholds row as a struct of the fields drawn
            % ([] when there is none). Read field by field: Thresholds is
            % wide, and turning a whole row into a struct cost more than
            % drawing the column.
            row = [];
            try
                r = S.seriesRow(sk);
                if isempty(r), return; end
                T = S.Thresholds;
                vn = string(T.Properties.VariableNames);
                need = ["Final","FinalCensored","FinalLo","FinalHi","Threshold","Censored", ...
                    "ThrLo","ThrHi","Decision"];
                if ~all(ismember(need,vn)), return; end
                row = struct();
                for f = [need "Flags"]
                    v = "";
                    if any(vn == f)
                        v = T.(f)(r,:);
                        if iscell(v), v = v{1}; end
                    end
                    row.(f) = v;
                end
            catch
                row = [];
            end
        end

        function desc = isDescending(obj,S,lp)
            st = [];
            try
                st = S.Settings;
            catch
            end
            if isempty(st), st = obj.Model.Settings; end
            d = mabr.ui.analysis.GridView.settingOf(st,'LevelDirection',"auto");
            d = string(d);
            if d == "auto"
                desc = contains(lower(lp),"attenuation");
            else
                desc = d == "descending";
            end
        end

        function w = waveNames(obj,S)
            st = [];
            try
                st = S.Settings;
            catch
            end
            if isempty(st), st = obj.Model.Settings; end
            try
                W = st.Waves;
                W = W(logical([W.Enabled]));
                w = reshape(string({W.Name}),1,[]);
            catch
                w = ["I","II","III","IV","V"];
            end
        end

        function a = detectionAlpha(obj,S)
            % The alpha the detection was run at (the session's settings),
            % else the project's.
            st = [];
            try
                st = S.Settings;
            catch
            end
            if isempty(st), st = obj.Model.Settings; end
            a = double(mabr.ui.analysis.GridView.settingOf(st,'Alpha',0.05));
        end

        function lv = levelOf(obj,S,ck)
            lv = NaN;
            lp = obj.Model.levelParam();
            if lp == "", return; end
            try
                lv = double(S.Conditions.(char(lp))(S.rowOf(ck)));
            catch
            end
        end

        function j = columnOf(obj,seriesKey)
            D = obj.Grid;
            j = [];
            if ~isempty(D), j = find(D.Keys == seriesKey,1); end
            if isempty(j)
                error('mabr:ui:analysis:GridView:unknownSeries', ...
                    'Series "%s" is not a column of the grid.',seriesKey);
            end
        end

        function [j,k] = slotOf(obj,seriesKey,level)
            j = obj.columnOf(seriesKey);
            L = obj.Grid.Levels;
            if isnan(level)
                k = find(isnan(L),1);
            else
                k = find(abs(L - level) < 1e-6,1);
            end
            if isempty(k)
                error('mabr:ui:analysis:GridView:unknownLevel', ...
                    'No row at %s in the grid.',mabr.ui.analysis.GridView.levelText(level));
            end
        end

        function putXY(obj,key,h,x,y)
            % XData and YData together, only when either changed (a line
            % whose two vectors briefly disagree in length warns).
            key = char(key);
            v = {x,y};
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                set(h,'XData',x,'YData',y);
                obj.Written.(key) = v;
            catch me
                mabr.log.vprintf(2,'Grid view: could not set line data (%s).',me.message);
            end
        end

        function putPatch(obj,key,h,V,F)
            key = char(key);
            v = {V,F};
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                set(h,'Faces',[]);
                set(h,'Vertices',V,'Faces',F);
                obj.Written.(key) = v;
            catch me
                mabr.log.vprintf(2,'Grid view: could not set a patch (%s).',me.message);
            end
        end

        function putDropdown(obj,key,dd,labels,data,value)
            % Items, ItemsData and Value of a dropdown, on change only.
            labels = cellstr(reshape(string(labels),1,[]));
            data   = cellstr(reshape(string(data),1,[]));
            value  = char(value);
            if ~any(strcmp(data,value)), value = data{1}; end
            key = char(key);
            v = {labels,data,value};
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                set(dd,'Items',labels,'ItemsData',data,'Value',value);
                obj.Written.(key) = v;
            catch me
                mabr.log.vprintf(2,'Grid view: could not fill a dropdown (%s).',me.message);
            end
        end

        function h = label(~,parent,col,text)
            h = uilabel(parent,'Text',char(text),'FontColor',mabr.ui.analysis.Style.Ink);
            h.Layout.Row = 1;
            h.Layout.Column = col;
        end

        function say(obj,text,level)
            if nargin < 3, level = 0; end
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus(text,level);
            end
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function C = emptyColumns()
            C = struct('SeriesKey',{},'Axes',{},'Menu',{},'Lines',{},'Final',{}, ...
                'FinalLabel',{},'Fit',{},'Grip',{},'Sig',{},'Band',{},'Compare',{},'Peaks',{}, ...
                'Shade',{},'Scale',{});
        end

        function C = emptyPool()
            % A column as the pool keeps it: Handles.Columns' fields and the
            % waves its peak lines were made for.
            C = struct('SeriesKey',{},'Axes',{},'Menu',{},'Lines',{},'Final',{}, ...
                'FinalLabel',{},'Fit',{},'Grip',{},'Sig',{},'Band',{},'Compare',{},'Peaks',{}, ...
                'Shade',{},'Scale',{},'Waves',{});
        end

        function d = sanitize(d)
            % A look the controls can show: unknown values back to defaults.
            f = mabr.ui.analysis.GridView.factoryDefaults();
            if ~isstruct(d), d = f; return; end
            for n = fieldnames(f).'
                if ~isfield(d,n{1}), d.(n{1}) = f.(n{1}); end
            end
            d.Scale    = mabr.ui.analysis.GridView.member(d.Scale, ...
                mabr.ui.analysis.GridView.ScaleIds,f.Scale);
            d.Polarity = mabr.ui.analysis.GridView.member(d.Polarity, ...
                mabr.ui.analysis.GridView.PolarityIds,f.Polarity);
            d.Band     = mabr.ui.analysis.GridView.member(d.Band, ...
                mabr.ui.analysis.GridView.BandIds,f.Band);
            d.Annotate = mabr.ui.analysis.GridView.member(d.Annotate, ...
                mabr.ui.analysis.GridView.AnnotateIds,f.Annotate);
            for n = ["WindowStart","WindowEnd","Fixed"]
                v = d.(n);
                if ~(isnumeric(v) && isscalar(v) && isfinite(v)), d.(n) = f.(n); else, d.(n) = double(v); end
            end
            if ~(d.Fixed > 0), d.Fixed = f.Fixed; end
            if ~(d.WindowEnd > d.WindowStart)
                d.WindowStart = f.WindowStart;  d.WindowEnd = f.WindowEnd;
            end
            for n = ["Significance","Peaks","Threshold"]
                v = d.(n);
                if (islogical(v) || isnumeric(v)) && isscalar(v), d.(n) = logical(v);
                else, d.(n) = f.(n); end
            end
        end

        function [l1,l2,fs] = fitTitle(l1,l2,avail)
            % A column's two-line title fitted to AVAIL pixels: the font
            % shrinks from 9 to 7 points first, and only then is the longer
            % line cut short ("…"). Titles of neighbouring columns must not
            % run into each other however many series a session has. (An
            % estimate, ~0.66 of the font size per character, rather than a
            % measurement: reading a text's extent makes MATLAB lay the axes
            % out on the spot.)
            perChar = @(fs) 0.66*fs;          % pixels per character at fs points
            n = max(strlength(l1),strlength(l2));
            fs = 9;
            if n == 0 || ~(avail > 0), return; end
            fs = min(9,max(7,floor(avail/(n*perChar(1)))));
            k = floor(avail/perChar(fs));     % characters that fit at fs
            if strlength(l1) > k, l1 = mabr.ui.analysis.GridView.shortTitle(l1,k); end
            if strlength(l2) > k, l2 = extractBefore(l2,max(k,2)) + "…"; end
        end

        function s = shortTitle(s,k)
            % A column name cut to K characters without losing what tells
            % two columns apart: a leading decision glyph ("⚑ ") and the
            % interleaved badge at the end (" ⧉") stay; the stimulus word
            % goes first ("Tone 16 kHz" -> "16 kHz"), then the middle is
            % cut ("ClickTra…").
            s = string(s);
            pre = "";  post = "";
            B = " " + mabr.ui.analysis.Style.BadgeInterleaved;
            if endsWith(s,B), post = B;  s = extractBefore(s,strlength(s) - strlength(B) + 1); end
            tok = regexp(char(s),'^(\S)\s(.*)$','tokens','once');   % a one-character glyph
            if ~isempty(tok), pre = string(tok{1}) + " ";  s = string(tok{2}); end
            room = k - strlength(pre) - strlength(post);
            w = split(s," ");
            if strlength(s) > room && numel(w) > 1
                s = strjoin(w(2:end)," ");
            end
            if strlength(s) > room
                s = extractBefore(s,max(room,2)) + "…";
            end
            s = pre + s + post;
        end

        function v = member(v,allowed,default)
            try
                v = string(v);
                if ~isscalar(v) || ~any(allowed == v), v = default; end
            catch
                v = default;
            end
        end

        function f = keyField(keys,name)
            % The value text of NAME in each key ("" when absent).
            keys = string(keys);
            f = strings(size(keys));
            pat = ['(?:^|\|)' regexptranslate('escape',char(name)) '=([^|]*)'];
            for i = 1:numel(keys)
                t = regexp(char(keys(i)),pat,'tokens','once');
                if ~isempty(t), f(i) = string(t{1}); end
            end
        end

        function v = sortValues(v)
            % Value texts in numeric order when they are numbers.
            v = reshape(string(v),[],1);
            x = str2double(v);
            if all(isfinite(x) | v == "NaN")
                [~,o] = sort(x);
                v = v(o);
            else
                v = sort(v);
            end
        end

        function s = levelText(v,withUnit)
            if nargin < 2, withUnit = true; end
            if ~isfinite(v)
                s = "";
                return
            end
            s = string(sprintf('%g',v));
            if withUnit, s = s + " dB"; end
        end

        function s = pText(p)
            if ~isfinite(p)
                s = "";
            elseif p < 0.001
                s = "<.001";
            else
                s = string(sprintf('%.3f',p));
                if startsWith(s,"0."), s = extractAfter(s,1); end
            end
        end

        function v = numCol(T,name)
            % Table column NAME as doubles (NaN where it is absent or not a
            % number), one per row.
            v = nan(height(T),1);
            if ~ismember(char(name),T.Properties.VariableNames), return; end
            x = T.(char(name));
            try
                if iscell(x)
                    for i = 1:numel(x)
                        xi = x{i};
                        if (isnumeric(xi) || islogical(xi)) && ~isempty(xi), v(i) = double(xi(1)); end
                    end
                elseif (isnumeric(x) || islogical(x)) && size(x,1) == height(T)
                    v = double(x(:,1));
                end
            catch
            end
        end

        function v = strCol(T,name,default)
            % Table column NAME as strings (DEFAULT where it is absent or
            % missing), one per row.
            v = repmat(string(default),height(T),1);
            if ~ismember(char(name),T.Properties.VariableNames), return; end
            try
                x = reshape(string(T.(char(name))),[],1);
                if numel(x) == height(T)
                    x(ismissing(x)) = string(default);
                    v = x;
                end
            catch
            end
        end

        function v = settingOf(s,name,default)
            v = default;
            if isempty(s), return; end
            try
                if isstruct(s)
                    if isfield(s,name), v = s.(name); end
                elseif isprop(s,name)
                    v = s.(name);
                end
            catch
                v = default;
            end
        end

        function s = onoff(tf)
            if tf, s = 'on'; else, s = 'off'; end
        end
    end
end
