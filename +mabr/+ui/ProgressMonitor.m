classdef ProgressMonitor < handle
% mabr.ui.ProgressMonitor  How far the schedule has got, at a glance.
%
%   The main window says what is happening NOW (state, sweeps, r) and the live
%   view says what the response looks like. Neither answers the question an
%   operator actually asks across a two-hour session: how much of the plan is
%   done, and which conditions are still short. This window answers only that,
%   in one of three views:
%
%     'simple'   NO plot at all -- the lamp, the three header labels beside
%                it, and the control strip. That header already says how far
%                along the session is, what the rig is doing, and how much
%                longer, which is the whole of what the question needs; a
%                bar underneath it was a second drawing of the same number.
%                The window sizes itself DOWN to those two strips, so this is
%                what to leave in a corner or on a second monitor when the
%                answer wanted is "how long until I can go home". Asking for
%                either plot view grows the window back to make room for it.
%     'bars'     one bar per stimulus, or per value of any one stimulus
%                parameter (GroupBy). A 5-level x 4-frequency bank is 20 bars
%                by stimulus, 5 by Level, 4 by Frequency -- the same progress,
%                asked three ways.
%     'heatmap'  the classic ABR grid: one parameter across (frequency), one
%                up (level), each cell shaded by how complete that condition
%                is, with its counts or percentage written in. The one view
%                that shows a HOLE in the design -- a condition nobody has
%                run yet -- rather than a number that happens to be small.
%
%   Labels ('counts' / 'percent' / 'none') decides what the numbers on the
%   bars, in the heat-map cells, and in the header read as: 1536/6144, or 25%.
%   'none' leaves the shading to speak for itself, which is the right setting
%   for a window glanced at from across the rig -- the header keeps a
%   percentage there, since one number is not what 'none' is about.
%
%   Counting
%   --------
%   The denominator is every presentation the plan currently holds -- summed
%   over mabr.stim.Schedule.Runs, so artifact make-up and user-requested
%   repeat runs enlarge it as they are appended. Progress therefore steps
%   BACK slightly when a make-up run lands, which is the truth: the work grew.
%
%   The numerator is Schedule.RunCounts (presentations actually recovered,
%   written by the controller at finalization) plus, while a run is streaming,
%   that run's sweeps so far paired against Schedule.runSequence -- the same
%   pairing mabr.ui.AcqController.finalize_run de-interleaves by, so the bar
%   moving during a run and the count left behind after it agree. In
%   stimulation-only mode nothing is recorded and no live metrics arrive, so
%   the bars step once per run instead of continuously.
%
%   Cost
%   ----
%   This window runs NO timer of its own. It rides the controller's existing
%   AUXILIARY tick (MetricsUpdated, ~2 Hz -- deliberately not the ~20 Hz live
%   tick, which belongs to the live trace; see mabr.ui.AcqController.AuxPeriod)
%   and repaints at most every MinInterval seconds (default 0.2), and then
%   only if the tallies actually changed -- a schedule of 512-sweep runs
%   changes its counts a few times a second at most. State changes and
%   finished blocks force a repaint regardless.
%
%   Note the aux tick is now SLOWER than MinInterval, so that throttle no
%   longer binds: the rate limiting has moved upstream to AuxPeriod and this
%   window repaints once per event. MinInterval stays because it is this
%   window's own guarantee -- it is what keeps a faster caller (a hand-driven
%   refresh, a future tick rate, mabrtest.FakeController) from repainting it
%   arbitrarily often.
%   Nothing is created per refresh: the bars are two patches whose vertices
%   are rewritten, the heat map one image whose CData is, and the labels a
%   fixed array of text objects whose Strings are. Layout is rebuilt only
%   when the view, the grouping, or the plan itself changes.
%
%   Use
%   ---
%       pm = mabr.ui.ProgressMonitor();       % its own window
%       pm.listenTo(controller);              % follow an AcqController
%       pm.View = 'heatmap';                  % or from the control strip
%
%       pm = mabr.ui.ProgressMonitor(panel);  % embedded (parent must be in a
%                                             % uifigure -- this is uigridlayout)
%       pm.attach(schedule,stimulusSet);      % follow a plan with no controller
%
%   AlwaysOnTop keeps the window above the others (uifigure WindowStyle
%   'alwaysontop', the same mechanism mabr.ui.App's pin uses) and is
%   remembered per rig in the MABR pref group.
%
%   See also mabr.ui.App, mabr.ui.AcqController, mabr.stim.Schedule.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        Views      = {'simple','bars','heatmap'};
        LabelModes = {'counts','percent','none'};
    end

    properties (Constant, Access = private)
        % One palette, stated once. The three bar colours are the whole legend
        % this window needs: grey is not started, blue is under way, amber is
        % being presented right now, green is finished.
        TrackColor  = [0.898 0.910 0.925];
        FillColor   = [0.216 0.451 0.678];
        DoneColor   = [0.157 0.596 0.439];
        ActiveColor = [0.898 0.616 0.180];
        InkColor    = [0.243 0.271 0.318];
        MutedColor  = [0.478 0.514 0.565];
        PaperColor  = [1 1 1];
        PanelColor  = [0.969 0.973 0.980];
        % Fraction of the axes width the bars occupy; the remainder is the
        % value gutter, so a number never sits on top of a bar and no
        % contrast-flipping is needed to keep it readable.
        BarSpan     = 0.80;
        BarHeight   = 0.62;
        % Beyond this many bars the labels and values stop being legible, so
        % they are dropped and the bars alone carry the shape.
        MaxLabelled = 40;
        % Beyond this many heat-map cells the overlay stops fitting inside one.
        MaxCells    = 400;
        % The window with no plot in it: 8 padding + 56 header + 6 spacing +
        % 1 collapsed plot row + 6 spacing + 66 control strip + 8 padding.
        % Stated rather than measured because uigridlayout offers no way to
        % ask what a 'fit' would come to before it is laid out.
        CompactHeight     = 152;
        DefaultPlotHeight = 500;
    end

    properties
        View        (1,:) char = 'simple'
        GroupBy     (1,:) char = 'Stimulus'
        HeatX       (1,:) char = ''
        HeatY       (1,:) char = ''
        Labels      (1,:) char = 'counts'
        MinInterval (1,1) double {mustBeNonnegative} = 0.2
        AlwaysOnTop (1,1) logical = false
        Title       (1,:) char = 'MABR Acquisition Progress'
    end

    properties (SetAccess = private)
        Figure
        Container            % figure or the container this view was built into
        PlotPanel
        CtrlPanel
        Axes
        Controller           % mabr.ui.AcqController being followed, if any
        Schedule             % plan shown when no controller is attached
        Stimuli
        Counts  (1,:) double = []   % last tally: presentations done, per stimulus
        Targets (1,:) double = []   % last tally: presentations planned, per stimulus

        % The drawn objects. Public to READ for the same reason
        % mabr.ui.LivePlot's axes are: a script (and the verification suite)
        % has to be able to ask what the window is actually showing, which is
        % not the same question as what it was told.
        TrackPatch                  % full-width bar tracks (one patch, all bars)
        FillPatch                   % the filled part (one patch, all bars)
        ValueText  = gobjects(1,0)  % one per bar, empty when too many to label
        HeatImage                   % the heat map itself
        HeatText   = gobjects(1,0)  % one per cell, empty when too dense
        MsgText                     % the "nothing to show yet" line
        ColorBar
    end

    properties (Access = private)
        Root
        Lamp
        PctLabel
        StateLabel
        TimeLabel
        Ctrl = struct()
        LayoutKey  (1,:) char = ''
        Map        = struct()       % group/cell mapping the current layout was built for
        Params     = struct('bank',[],'names',{{}},'values',[])
        PlanKey    (1,2) double = [-1 -1]
        PlanTotals (1,:) double = []
        LastDraw   (1,1) uint64 = uint64(0)
        LastClock  (1,1) uint64 = uint64(0)
        LastCounts  = []
        LastTargets = []
        LastActive  = []
        StateNow   (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        LiveSweeps (1,1) double = 0
        T0         (1,1) uint64 = uint64(0)
        Frozen     (1,1) double = NaN
        Listeners
        Building   (1,1) logical = false
        PlotShown  (1,1) logical = true    % is the plot row currently open
        PlotHeight (1,1) double = 500      % height the plot views were left at
    end

    methods
        function obj = ProgressMonitor(parent)
            obj.restorePlotHeight();
            if nargin >= 1 && ~isempty(parent) && isgraphics(parent)
                obj.Container = parent;
            else
                % Opens at whatever the DEFAULT view needs, which is the
                % compact one -- a window that opened tall and immediately
                % shrank would read as a glitch.
                obj.Figure = uifigure('Name',obj.Title,'Tag','MABR_PROGRESS', ...
                    'Position',[100 100 560 obj.CompactHeight],'Color',obj.PanelColor);
                obj.Container = obj.Figure;
            end
            obj.Building = true;
            obj.build();
            obj.Building = false;
            obj.restoreOnTop();
            obj.syncControls();
            obj.refresh(true);
        end

        function delete(obj)
            obj.stopListening();
            obj.rememberPlotHeight();
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Axes) && isgraphics(obj.Axes);
        end

        function tf = hasPlot(obj)
            % Whether this window currently draws anything at all -- false in
            % the 'simple' view, where the header IS the report.
            tf = ~strcmp(obj.View,'simple');
        end

        function fitToView(obj)
            % Size the window to the view it is showing: down to the two
            % strips with no plot, back up to whatever height the plot views
            % were last left at.
            %
            % Only the HEIGHT moves. The width means the same thing in both
            % forms and is the user's to choose, and the TOP edge is held so
            % the window grows and shrinks downwards rather than jumping out
            % from under the pointer that just changed the view. Public
            % because a host that places this window itself (mabr.ui.App
            % restores a remembered position) has to be able to hand the size
            % back afterwards -- the spot is the user's, the height is the
            % view's.
            if isempty(obj.Figure) || ~isgraphics(obj.Figure), return; end
            if obj.hasPlot(), h = obj.PlotHeight; else, h = obj.CompactHeight; end
            p = obj.Figure.Position;
            if abs(p(4) - h) < 1, return; end
            top = p(2) + p(4);
            obj.Figure.Position = mabr.ui.WindowPos.clampToScreen([p(1) top-h p(3) h]);
        end

        % --- What to watch ---------------------------------------------------
        function listenTo(obj,controller)
            % Follow an mabr.ui.AcqController: its state transitions, its live
            % metrics, and every block it finalizes. Only one controller is
            % followed at a time -- calling this again re-points the listeners
            % rather than stacking a second set, so re-opening the window (or
            % rebuilding the controller) cannot double-count anything.
            %
            % The controller's Schedule is read on every refresh rather than
            % held: setStimuli REPLACES it, so a stored handle would quietly
            % go stale the next time a bank is loaded.
            obj.stopListening();
            obj.Controller = [];
            obj.resetProgress();
            if nargin < 2 || isempty(controller) || ~isvalid(controller), return; end
            obj.Controller = controller;
            obj.StateNow   = controller.State;
            obj.Listeners  = [ ...
                addlistener(controller,'StateChanged',   @(~,e) obj.onState(e)); ...
                addlistener(controller,'MetricsUpdated', @(~,e) obj.onMetrics(e)); ...
                addlistener(controller,'BlockReady',     @(~,~) obj.onBlockReady()); ...
                addlistener(controller,'ScheduleComplete',@(~,~) obj.onComplete())];
            obj.newPlan();
        end

        function attach(obj,schedule,stimuli)
            % Follow a plan directly, with no controller behind it -- what a
            % script or a test uses, and what the App calls to re-point an open
            % window at the schedule a new run just built. A controller
            % attached through listenTo still wins: it owns the live half of
            % the tally, and its Schedule is the one actually being played.
            if nargin < 3, stimuli = []; end
            obj.Schedule = schedule;
            if isempty(stimuli) && ~isempty(schedule) && isvalid(schedule)
                stimuli = schedule.Set;
            end
            obj.Stimuli = stimuli;
            obj.newPlan();
        end

        function [pct,state,time] = headerText(obj)
            % What the header is actually saying, read back -- the counterpart
            % of Counts/Targets for the top of the window, and how the
            % verification suite checks that Labels reaches it.
            pct = ''; state = ''; time = '';
            if ~obj.isvalidView(), return; end
            pct   = obj.PctLabel.Text;
            state = obj.StateLabel.Text;
            time  = obj.TimeLabel.Text;
        end

        function reset(obj)
            % Forget the plan and the clock; keep the window and its settings.
            obj.Schedule = [];
            obj.Stimuli  = [];
            obj.resetProgress();
            obj.newPlan();
        end

        % --- Painting ---------------------------------------------------------
        function refresh(obj,force)
            % Recompute the tally and repaint what changed.
            %
            % force skips the rate limit (a state change, a finished block, a
            % setting the user just moved); everything else is throttled to
            % MinInterval and then dropped entirely if the numbers are the same
            % as last time. Dropping a live tick costs nothing: the block that
            % ends the run forces a repaint, so the window cannot settle on a
            % stale number.
            if nargin < 2, force = false; end
            if ~obj.isvalidView(), return; end
            if ~force && obj.LastDraw ~= 0 && toc(obj.LastDraw) < obj.MinInterval
                return
            end

            [done,target,active,sch] = obj.tally();
            moved   = ~isequal(done,obj.LastCounts) || ~isequal(target,obj.LastTargets) ...
                      || ~isequal(active,obj.LastActive);
            ticking = obj.LastClock == 0 || toc(obj.LastClock) >= 1;
            if ~force && ~moved && ~ticking, return; end

            obj.LastDraw = tic;
            obj.Counts   = done;
            obj.Targets  = target;

            if force || moved
                obj.drawBody(done,target,active,sch);
                obj.LastCounts  = done;
                obj.LastTargets = target;
                obj.LastActive  = active;
            end
            obj.drawHeader(done,target,sch);
            obj.LastClock = tic;
            drawnow limitrate
        end

        % --- Settings ---------------------------------------------------------
        % Every one of these is what the control strip writes, so a script and
        % the strip drive the window through exactly the same path. Each clears
        % the layout key where the change is structural, then repaints.
        % (MCSUP: a set method assigning another property. Deliberate, and the
        % same pattern mabr.ui.AcqController.set.Filters uses -- a monitor is
        % never deserialized, so load order cannot be disturbed.)
        function set.View(obj,v)
            obj.View = validatestring(v,mabr.ui.ProgressMonitor.Views);
            obj.LayoutKey = '';                                       %#ok<MCSUP>
            obj.settingChanged();
        end

        function set.GroupBy(obj,v)
            obj.GroupBy = char(v);
            obj.LayoutKey = '';                                       %#ok<MCSUP>
            obj.settingChanged();
        end

        function set.HeatX(obj,v)
            obj.HeatX = char(v);
            obj.LayoutKey = '';                                       %#ok<MCSUP>
            obj.settingChanged();
        end

        function set.HeatY(obj,v)
            obj.HeatY = char(v);
            obj.LayoutKey = '';                                       %#ok<MCSUP>
            obj.settingChanged();
        end

        function set.Labels(obj,v)
            obj.Labels = validatestring(v,mabr.ui.ProgressMonitor.LabelModes);
            obj.settingChanged();
        end

        function set.AlwaysOnTop(obj,tf)
            obj.AlwaysOnTop = logical(tf);
            obj.applyOnTop();
        end

        function set.Title(obj,txt)
            obj.Title = char(txt);
            if ~isempty(obj.Figure) && isgraphics(obj.Figure)          %#ok<MCSUP>
                obj.Figure.Name = obj.Title;                           %#ok<MCSUP>
            end
        end
    end

    % ======================= internals ====================================
    methods (Access = private)
        % --- Construction -----------------------------------------------------
        function build(obj)
            g = uigridlayout(obj.Container,[3 1]);
            g.RowHeight    = {56,'1x',66};
            g.ColumnWidth  = {'1x'};
            g.RowSpacing   = 6;
            g.Padding      = [8 8 8 8];
            g.BackgroundColor = obj.PanelColor;
            obj.Root = g;

            obj.buildHeader(g);
            obj.buildPlot(g);
            obj.buildControls(g);
            obj.applyViewLayout(true);
        end

        function applyViewLayout(obj,force)
            % Open or collapse the plot row to match the view, and resize the
            % window to suit. The axes and its panel are COLLAPSED rather than
            % destroyed -- asking for a plot view is then a row height and a
            % Visible, not a rebuild, and the embedded form (which has no
            % window to resize) gets the same behaviour from the same code.
            if nargin < 2, force = false; end
            if isempty(obj.Root) || ~isgraphics(obj.Root), return; end
            want = obj.hasPlot();
            if ~force && want == obj.PlotShown, return; end
            % Leaving a plot view is the moment to note how tall the user had
            % made it; coming back is the moment to give that height back.
            if obj.PlotShown && ~want, obj.rememberPlotHeight(); end

            obj.PlotPanel.Visible = matlab.lang.OnOffSwitchState(want);
            rh = obj.Root.RowHeight;
            % 1 pixel rather than 0: a collapsed row still has to be a valid
            % height, and one pixel of paper is invisible between two panels
            % of the same colour.
            if want, rh{2} = '1x'; else, rh{2} = 1; end
            obj.Root.RowHeight = rh;
            obj.PlotShown = want;
            obj.fitToView();
        end

        function rememberPlotHeight(obj)
            % Per rig, like the always-on-top pref: an operator who made the
            % heat map big wants it that big tomorrow too.
            if isempty(obj.Figure) || ~isgraphics(obj.Figure), return; end
            if ~obj.PlotShown, return; end
            h = obj.Figure.Position(4);
            % A window still at (or below) compact height has no plot height
            % worth keeping -- storing one would fix the plot views at a size
            % that cannot show a plot.
            if h < obj.CompactHeight + 60, return; end
            obj.PlotHeight = h;
            try, setpref('MABR','ProgressPlotHeight',h); end %#ok<TRYNC>
        end

        function restorePlotHeight(obj)
            obj.PlotHeight = obj.DefaultPlotHeight;
            try
                h = getpref('MABR','ProgressPlotHeight',obj.DefaultPlotHeight);
                if isnumeric(h) && isscalar(h) && isfinite(h) && h >= obj.CompactHeight + 60
                    obj.PlotHeight = double(h);
                end
            catch
            end
        end

        function buildHeader(obj,g)
            % The one line that has to be readable from across the room: how
            % far along, what the rig is doing, and how much longer.
            p  = uipanel(g,'BorderType','none','BackgroundColor',obj.PanelColor);
            hg = uigridlayout(p,[2 3]);
            hg.RowHeight       = {28,20};
            hg.ColumnWidth     = {24,'fit','1x'};
            hg.Padding         = [4 2 4 2];
            hg.RowSpacing      = 0;
            hg.ColumnSpacing   = 10;
            hg.BackgroundColor = obj.PanelColor;

            obj.Lamp = uilamp(hg,'Color',[0.6 0.6 0.6]);
            obj.Lamp.Layout.Row = 1; obj.Lamp.Layout.Column = 1;

            obj.PctLabel = uilabel(hg,'Text','—','FontSize',22,'FontWeight','bold', ...
                'FontColor',obj.InkColor,'VerticalAlignment','center');
            obj.PctLabel.Layout.Row = [1 2]; obj.PctLabel.Layout.Column = 2;

            obj.StateLabel = uilabel(hg,'Text','Idle','FontSize',12, ...
                'FontColor',obj.InkColor,'VerticalAlignment','bottom');
            obj.StateLabel.Layout.Row = 1; obj.StateLabel.Layout.Column = 3;

            obj.TimeLabel = uilabel(hg,'Text','','FontSize',11, ...
                'FontColor',obj.MutedColor,'VerticalAlignment','top');
            obj.TimeLabel.Layout.Row = 2; obj.TimeLabel.Layout.Column = 3;
        end

        function buildPlot(obj,g)
            % The axes fills its panel by normalized OUTER position rather than
            % sitting in a nested grid layout: the heat map hangs a colorbar
            % off it, and a colorbar is positioned relative to its axes inside
            % a plain container -- it is not a grid-managed child.
            obj.PlotPanel = uipanel(g,'BorderType','none','BackgroundColor',obj.PaperColor);
            obj.Axes = uiaxes(obj.PlotPanel,'Units','normalized', ...
                'OuterPosition',[0 0 1 1],'PositionConstraint','outerposition', ...
                'Color',obj.PaperColor);
            mabr.ui.hideAxesToolbar(obj.Axes);   % nothing here is pannable
            disableDefaultInteractivity(obj.Axes);
        end

        function buildControls(obj,g)
            % Two rows of paired label+control. The second row is contextual --
            % grouping belongs to the bars, the axes to the heat map -- and its
            % controls are GREYED rather than hidden, so the strip never
            % reflows under the pointer and the setting stays visible while it
            % is not in force.
            obj.CtrlPanel = uipanel(g,'BorderType','none','BackgroundColor',obj.PanelColor);
            cg = uigridlayout(obj.CtrlPanel,[2 6]);
            cg.RowHeight       = {22,22};
            cg.ColumnWidth     = {40,'1x',34,'1x',14,'1x'};
            cg.Padding         = [4 4 4 4];
            cg.RowSpacing      = 5;
            cg.ColumnSpacing   = 6;
            cg.BackgroundColor = obj.PanelColor;

            obj.stripLabel(cg,1,1,'View');
            obj.Ctrl.view = uidropdown(cg, ...
                'Items',{'Simple','Bars','Heat map'},'ItemsData',obj.Views, ...
                'Value',obj.View,'Tooltip','How to draw the schedule''s progress', ...
                'ValueChangedFcn',@(s,~) obj.onControl('View',s.Value));
            obj.Ctrl.view.Layout.Row = 1; obj.Ctrl.view.Layout.Column = 2;

            obj.stripLabel(cg,1,3,'Show');
            obj.Ctrl.labels = uidropdown(cg, ...
                'Items',{'Counts','Percent','None'},'ItemsData',obj.LabelModes, ...
                'Value',obj.Labels,'Tooltip','What the numbers on the bars and cells read as', ...
                'ValueChangedFcn',@(s,~) obj.onControl('Labels',s.Value));
            obj.Ctrl.labels.Layout.Row = 1; obj.Ctrl.labels.Layout.Column = 4;

            obj.Ctrl.onTop = uicheckbox(cg,'Text','Always on top','FontSize',11, ...
                'FontColor',obj.InkColor,'Value',obj.AlwaysOnTop, ...
                'Tooltip','Keep this window above the others', ...
                'ValueChangedFcn',@(s,~) obj.onControl('AlwaysOnTop',s.Value));
            obj.Ctrl.onTop.Layout.Row = 1; obj.Ctrl.onTop.Layout.Column = [5 6];
            if isempty(obj.Figure)
                % Embedded: this window is the host's, and its stacking is the
                % host's decision, not this component's.
                obj.Ctrl.onTop.Enable  = 'off';
                obj.Ctrl.onTop.Tooltip = 'Set on the window that hosts this view';
            end

            obj.Ctrl.groupLabel = obj.stripLabel(cg,2,1,'Group');
            obj.Ctrl.group = uidropdown(cg,'Items',{'Stimulus'},'ItemsData',{'Stimulus'}, ...
                'Tooltip','One bar per stimulus, or per value of one parameter', ...
                'ValueChangedFcn',@(s,~) obj.onControl('GroupBy',s.Value));
            obj.Ctrl.group.Layout.Row = 2; obj.Ctrl.group.Layout.Column = 2;

            obj.Ctrl.xLabel = obj.stripLabel(cg,2,3,'X');
            obj.Ctrl.x = uidropdown(cg,'Items',{'—'},'ItemsData',{''}, ...
                'Tooltip','Parameter across the heat map', ...
                'ValueChangedFcn',@(s,~) obj.onControl('HeatX',s.Value));
            obj.Ctrl.x.Layout.Row = 2; obj.Ctrl.x.Layout.Column = 4;

            obj.Ctrl.yLabel = obj.stripLabel(cg,2,5,'Y');
            obj.Ctrl.y = uidropdown(cg,'Items',{'—'},'ItemsData',{''}, ...
                'Tooltip','Parameter up the heat map', ...
                'ValueChangedFcn',@(s,~) obj.onControl('HeatY',s.Value));
            obj.Ctrl.y.Layout.Row = 2; obj.Ctrl.y.Layout.Column = 6;
        end

        function h = stripLabel(obj,g,row,col,txt)
            h = uilabel(g,'Text',txt,'FontSize',11,'FontColor',obj.MutedColor, ...
                'HorizontalAlignment','right');
            h.Layout.Row = row; h.Layout.Column = col;
        end

        % --- Control strip ----------------------------------------------------
        function onControl(obj,what,value)
            obj.(what) = value;      % the property setters do the rest
        end

        function settingChanged(obj)
            if obj.Building || ~obj.isvalidView(), return; end
            obj.applyViewLayout();
            obj.syncControls();
            obj.refresh(true);
        end

        function syncControls(obj)
            % Push the current settings and the current bank's parameter list
            % into the strip. Called after any programmatic change too, so the
            % controls always say what the window is actually doing.
            if obj.Building || isempty(fieldnames(obj.Ctrl)), return; end
            obj.Building = true;
            c = onCleanup(@() obj.endSync());

            P     = obj.paramTable();
            names = P.names;

            obj.Ctrl.view.Value   = obj.View;
            obj.Ctrl.labels.Value = obj.Labels;
            obj.Ctrl.onTop.Value  = obj.AlwaysOnTop;

            grpItems = [{'Stimulus'} names];
            if ~ismember(obj.GroupBy,grpItems), obj.GroupBy = 'Stimulus'; end
            setDropdown(obj.Ctrl.group,grpItems,grpItems,obj.GroupBy);

            if isempty(names)
                axItems = {'(no parameters)'};
                axData  = {''};
            else
                axItems = names;
                axData  = names;
            end
            [dx,dy] = defaultAxes(names);
            if ~ismember(obj.HeatX,axData) || isempty(obj.HeatX), obj.HeatX = dx; end
            if ~ismember(obj.HeatY,axData) || isempty(obj.HeatY) || strcmp(obj.HeatY,obj.HeatX)
                % Picking X = the parameter Y is already on has to MOVE Y, not
                % leave the two on one axis and the map blank.
                alt = axData(~strcmp(axData,obj.HeatX));
                if isempty(alt),            obj.HeatY = dy;
                elseif ismember(dy,alt),    obj.HeatY = dy;
                else,                       obj.HeatY = alt{1};
                end
            end
            setDropdown(obj.Ctrl.x,axItems,axData,obj.HeatX);
            setDropdown(obj.Ctrl.y,axItems,axData,obj.HeatY);

            isBars = strcmp(obj.View,'bars');
            isHeat = strcmp(obj.View,'heatmap');
            setEnabled({obj.Ctrl.group,obj.Ctrl.groupLabel},isBars);
            setEnabled({obj.Ctrl.x,obj.Ctrl.xLabel,obj.Ctrl.y,obj.Ctrl.yLabel}, ...
                isHeat && ~isempty(names));
        end

        function endSync(obj)
            obj.Building = false;
        end

        function restoreOnTop(obj)
            % Per rig, like the other MABR prefs -- an operator who wants this
            % window pinned wants it pinned tomorrow too.
            if isempty(obj.Figure)
                obj.AlwaysOnTop = false;   % embedded: the host owns its stacking
                return
            end
            try
                obj.AlwaysOnTop = getpref('MABR','ProgressOnTop',false);
            catch
                obj.AlwaysOnTop = false;
            end
        end

        function applyOnTop(obj)
            if isempty(obj.Figure) || ~isgraphics(obj.Figure), return; end
            % 'alwaysontop' is a documented uifigure WindowStyle from R2021a,
            % inside MABR's R2021b floor -- the same mechanism the main
            % window's pin uses, no undocumented handle games.
            if obj.AlwaysOnTop
                obj.Figure.WindowStyle = 'alwaysontop';
            else
                obj.Figure.WindowStyle = 'normal';
            end
            if ~obj.Building && isfield(obj.Ctrl,'onTop') && isvalid(obj.Ctrl.onTop)
                obj.Ctrl.onTop.Value = obj.AlwaysOnTop;
            end
            try, setpref('MABR','ProgressOnTop',obj.AlwaysOnTop); end %#ok<TRYNC>
        end

        % --- Controller events -------------------------------------------------
        function onState(obj,e)
            wasTerminal = mabr.ui.ProgState.isTerminal(obj.StateNow);
            obj.StateNow = e.State;
            if e.State == mabr.ui.ProgState.PrepBlock
                % The next run's sweeps have not started arriving; anything
                % left in the counter belongs to the run just finalized, which
                % is already in Schedule.RunCounts.
                obj.LiveSweeps = 0;
            end
            if mabr.ui.ProgState.isTerminal(e.State)
                if obj.T0 ~= 0 && isnan(obj.Frozen), obj.Frozen = toc(obj.T0); end
            elseif obj.T0 == 0 || wasTerminal
                obj.T0 = tic; obj.Frozen = NaN;   % a new schedule starts the clock
            end
            obj.refresh(true);
        end

        function onMetrics(obj,e)
            % The ONLY high-rate path into this window, and it does nothing but
            % store a number: refresh() decides whether that number is worth a
            % repaint yet.
            obj.LiveSweeps = e.Info.numSweeps;
            obj.refresh(false);
        end

        function onBlockReady(obj)
            % The run's presentations are in Schedule.RunCounts as of now, so
            % the live counter has to be given up or it would be counted twice.
            obj.LiveSweeps = 0;
            obj.refresh(true);
        end

        function onComplete(obj)
            if obj.T0 ~= 0 && isnan(obj.Frozen), obj.Frozen = toc(obj.T0); end
            obj.refresh(true);
        end

        function stopListening(obj)
            if ~isempty(obj.Listeners), delete(obj.Listeners); end
            obj.Listeners = [];
        end

        function resetProgress(obj)
            obj.LiveSweeps = 0;
            obj.T0         = uint64(0);
            obj.Frozen     = NaN;
            obj.StateNow   = mabr.ui.ProgState.Idle;
        end

        function newPlan(obj)
            % A different plan invalidates the layout, the group mapping, the
            % parameter table and every cached tally alike.
            obj.LayoutKey   = '';
            obj.PlanKey     = [-1 -1];
            obj.Params      = struct('bank',[],'names',{{}},'values',[]);
            obj.LastCounts  = [];
            obj.LastTargets = [];
            obj.LastActive  = [];
            if ~obj.isvalidView(), return; end
            obj.syncControls();
            obj.refresh(true);
        end

        % --- The tally --------------------------------------------------------
        function [sch,bank] = plan(obj)
            % The plan to report on: the controller's when one is attached
            % (it owns the live half of the tally, and its Schedule is the one
            % actually being played), otherwise whatever attach() was handed.
            % Named bank, not set, so nothing in here can shadow set().
            sch = []; bank = [];
            if ~isempty(obj.Controller) && isvalid(obj.Controller)
                sch  = obj.Controller.Schedule;
                bank = obj.Controller.Stimuli;
            elseif ~isempty(obj.Schedule) && isvalid(obj.Schedule)
                sch  = obj.Schedule;
                bank = obj.Stimuli;
            end
            if ~isempty(sch) && ~isvalid(sch), sch = []; end
            if isempty(sch), bank = []; return; end
            if isempty(bank) || ~isvalid(bank), bank = sch.Set; end
        end

        function [done,target,active,sch] = tally(obj)
            % Presentations done and planned, per stimulus, plus which stimuli
            % the run streaming right now is presenting.
            [sch,bank] = obj.plan();
            % Row empties, not [], so the size-validated Counts/Targets never
            % see a 0x0.
            done = zeros(1,0); target = zeros(1,0); active = false(1,0);
            if isempty(sch) || isempty(bank), return; end

            n = bank.numStimuli;
            if n == 0, return; end

            target = obj.scheduledTotals(sch,n);
            done   = zeros(1,n);
            active = false(1,n);

            d = sch.RunCounts;
            if numel(d) > n, d = d(1:n); end
            done(1:numel(d)) = d;

            r = sch.current();
            if r >= 1 && r <= sch.NumRuns && obj.inRun()
                seq = sch.runSequence(r);
                active(unique(seq)) = true;
                % The k-th recorded onset is the k-th presentation the schedule
                % ordered -- exactly the pairing finalize_run de-interleaves
                % by, so what this bar shows mid-run is what the run leaves
                % behind when it finalizes.
                k = min(obj.LiveSweeps,numel(seq));
                if k >= 1
                    done = done + accumarray(seq(1:k)',1,[n 1])';
                end
            end
        end

        function tf = inRun(obj)
            tf = obj.StateNow == mabr.ui.ProgState.Acquire ...
                 || obj.StateNow == mabr.ui.ProgState.PrepBlock;
        end

        function t = scheduledTotals(obj,sch,n)
            % Every presentation the plan currently holds, per stimulus.
            % Recomputed only when the plan changes shape -- appending a
            % make-up or repeat run changes both the run count and the total
            % presentation count, so the pair is a sufficient fingerprint, and
            % a reshuffle (which changes neither, and neither should it change
            % this) correctly does not trigger a recount.
            key = [sch.NumRuns, sum(cellfun(@numel,sch.Runs))];
            if isequal(key,obj.PlanKey) && numel(obj.PlanTotals) == n
                t = obj.PlanTotals; return
            end
            if sch.NumRuns == 0
                t = zeros(1,n);
            else
                seqAll = [sch.Runs{:}];
                t      = accumarray(seqAll(:),1,[n 1])';
            end
            obj.PlanKey    = key;
            obj.PlanTotals = t;
        end

        % --- Parameters and grouping -------------------------------------------
        function P = paramTable(obj)
            % Which numeric parameters the loaded bank varies, and their value
            % per stimulus. Built from StimulusSet.meta, so a bank that DECLARES
            % informativeParams gets exactly the list it declared and one that
            % does not gets the inferred numeric scalars -- the same dimensions
            % the offline pipeline groups by.
            [~,bank] = obj.plan();
            if isempty(bank)
                P = struct('bank',[],'names',{{}},'values',[]);
                obj.Params = P;
                return
            end
            if ~isempty(obj.Params.bank) && isvalid(obj.Params.bank) ...
                    && obj.Params.bank == bank && size(obj.Params.values,1) == bank.numStimuli
                P = obj.Params; return
            end

            n     = bank.numStimuli;
            names = {};
            vals  = [];
            for i = 1:n
                try
                    m = bank.meta(i);
                catch
                    continue    % a bank entry we cannot describe still counts
                end
                ip = m.informativeParams;
                for k = 1:numel(ip)
                    f = ip{k};
                    if ~isfield(m,f), continue; end
                    v = m.(f);
                    if ~(isnumeric(v) && isscalar(v)), continue; end
                    j = find(strcmp(names,f),1);
                    if isempty(j)
                        names{end+1} = f;              %#ok<AGROW>
                        j = numel(names);
                        vals(:,j) = nan(n,1);          %#ok<AGROW>
                    end
                    vals(i,j) = double(v);             %#ok<AGROW>
                end
            end
            P = struct('bank',bank,'names',{names},'values',vals);
            obj.Params = P;
        end

        function [labels,map,axisName] = groupsBy(obj,name,n)
            % map(i) = which bar stimulus i belongs to; labels, one per bar.
            axisName = '';
            P = obj.paramTable();
            j = [];
            if ~isempty(name) && ~strcmpi(name,'Stimulus')
                j = find(strcmp(P.names,name),1);
            end
            if isempty(j)
                [~,bank] = obj.plan();
                labels = cell(1,n);
                for i = 1:n
                    labels{i} = shorten(char(string(bank.id(i))),26);
                end
                map = 1:n;
                return
            end

            v  = P.values(:,j).';
            u  = unique(v(~isnan(v)));
            map = zeros(1,n);
            for k = 1:numel(u), map(v == u(k)) = k; end
            labels = arrayfun(@(x) sprintf('%g',x),u,'UniformOutput',false);
            if any(isnan(v))
                map(isnan(v)) = numel(u) + 1;
                labels{end+1} = 'n/a';
            end
            axisName = name;
        end

        % --- Drawing -----------------------------------------------------------
        function drawHeader(obj,done,target,sch)
            D = sum(done); T = sum(target);
            if T > 0
                frac = min(1,D/T);
                switch obj.Labels
                    case 'counts',  obj.PctLabel.Text = sprintf('%d / %d',D,T);
                    otherwise,      obj.PctLabel.Text = sprintf('%.0f%%',100*frac);
                end
            else
                obj.PctLabel.Text = '—';
            end

            [rgb,txt] = mabr.ui.ProgState.appearance(obj.StateNow);
            obj.Lamp.Color = rgb;
            if isempty(sch)
                obj.StateLabel.Text = 'No schedule yet';
                obj.TimeLabel.Text  = 'Start or preview a run, or load a plan.';
                return
            end

            bits = {txt};
            if sch.NumRuns > 0
                r = sch.current();
                if r >= 1
                    bits{end+1} = sprintf('run %d of %d',r,sch.NumRuns);
                else
                    bits{end+1} = sprintf('%d runs',sch.NumRuns);
                end
            end
            if sch.StimulationOnly
                % The counts here are presentations PLAYED, and the difference
                % matters enough to say every time.
                bits{end+1} = 'stimulation only';
            end
            obj.StateLabel.Text = strjoin(bits,'  ·  ');

            el = obj.elapsed();
            when = {};
            if el > 0, when{end+1} = ['elapsed ' clockText(el)]; end
            eta = obj.remaining(D,T,el,sch);
            if ~isnan(eta), when{end+1} = ['~' clockText(eta) ' left']; end
            obj.TimeLabel.Text = strjoin(when,'  ·  ');
        end

        function s = elapsed(obj)
            if obj.T0 == 0, s = 0; return; end
            if ~isnan(obj.Frozen), s = obj.Frozen; else, s = toc(obj.T0); end
        end

        function eta = remaining(~,D,T,el,sch)
            % Measured rate once there is one to measure; the plan's own
            % estimate before that. Either way it is an estimate and the label
            % says so -- a randomized ISI makes the duration an expectation,
            % and an advance criterion can end any run early.
            eta = NaN;
            if isempty(sch) || T <= 0 || D >= T, return; end
            if D > 0 && el > 5
                eta = el*(T-D)/D;
            else
                eta = (T-D)*sch.MeanISI;
            end
        end

        function drawBody(obj,done,target,active,sch)
            if ~obj.hasPlot()
                % The header carries the whole report in this view and the
                % axes is collapsed to a pixel, so anything drawn here would
                % be work nobody can see. Clear it once so a view switched
                % away from cannot leave stale patches behind, then leave it.
                if ~strcmp(obj.LayoutKey,'none')
                    obj.clearAxes();
                    obj.LayoutKey = 'none';
                end
                return
            end
            if isempty(done) || isempty(sch)
                obj.showMessage('No schedule to report on yet.');
                return
            end
            switch obj.View
                case 'bars',    obj.drawBars(done,target,active);
                case 'heatmap', obj.drawHeat(done,target);
            end
        end

        function drawBars(obj,done,target,active)
            [labels,map,axisName] = obj.groupsBy(obj.GroupBy,numel(done));
            G = numel(labels);
            if G == 0, obj.showMessage('Nothing scheduled.'); return; end
            d = accumarray(map(:),done(:),  [G 1]).';
            t = accumarray(map(:),target(:),[G 1]).';
            a = accumarray(map(:),double(active(:)),[G 1]).' > 0;
            obj.paintBars(labels,d,t,a,axisName,11,sprintf('%d',numel(done)));
        end

        function paintBars(obj,labels,done,target,active,axisName,fontSize,tag)
            n    = numel(labels);
            key  = sprintf('bars|%d|%s|%d|%s',n,axisName,fontSize,tag);
            ax   = obj.Axes;
            show = n <= obj.MaxLabelled;
            % Bars share the axes height between them, so the type has to come
            % down as their number goes up -- floored, because a label too
            % small to read is no better than none.
            tickFont = max(7,min(fontSize,round(360/max(n,1))));

            if ~strcmp(obj.LayoutKey,key)
                obj.clearAxes();
                V = barVertices(zeros(1,n),n,obj.BarHeight,obj.BarSpan);
                F = reshape(1:4*n,4,n).';
                obj.TrackPatch = patch(ax,'Faces',F, ...
                    'Vertices',barVertices(ones(1,n),n,obj.BarHeight,obj.BarSpan), ...
                    'FaceColor',obj.TrackColor,'EdgeColor','none');
                obj.FillPatch = patch(ax,'Faces',F,'Vertices',V, ...
                    'FaceColor','flat','FaceVertexCData',repmat(obj.FillColor,n,1), ...
                    'EdgeColor','none');
                obj.ValueText = gobjects(1,0);
                if show
                    % One object per bar, built in bar order and never
                    % rebuilt -- only its String changes from here on. The
                    % value sits in the gutter to the right of the track (see
                    % BarSpan), so no number is ever drawn over a bar.
                    obj.ValueText = gobjects(1,n);
                    for k = 1:n
                        obj.ValueText(k) = text(ax,1,k,'', ...
                            'HorizontalAlignment','right','VerticalAlignment','middle', ...
                            'FontSize',tickFont,'Color',obj.InkColor);
                    end
                end
                ax.YDir  = 'reverse';
                ax.XLim  = [0 1];
                ax.YLim  = [0.5 n+0.5];
                ax.XTick = [];
                ax.Color = obj.PaperColor;
                ax.Box   = 'off';
                ax.XColor = 'none';
                ax.YColor = obj.MutedColor;
                ax.FontSize = tickFont;
                if show
                    ax.YTick = 1:n;
                    ax.YTickLabel = labels;
                else
                    ax.YTick = [];
                end
                ylabel(ax,axisName,'Color',obj.MutedColor,'FontSize',fontSize);
                obj.LayoutKey = key;
            end

            frac = zeros(1,n);
            pos  = target > 0;
            frac(pos) = min(1,done(pos)./target(pos));

            C = repmat(obj.FillColor,n,1);
            C(active,:)      = repmat(obj.ActiveColor,nnz(active),1);
            C(frac >= 1,:)   = repmat(obj.DoneColor,nnz(frac >= 1),1);

            set(obj.FillPatch,'Vertices',barVertices(frac,n,obj.BarHeight,obj.BarSpan), ...
                'FaceVertexCData',C);

            if ~isempty(obj.ValueText)
                if strcmp(obj.Labels,'none')
                    set(obj.ValueText,'Visible','off');
                else
                    strs = cell(1,n);
                    for k = 1:n, strs{k} = obj.valueText(done(k),target(k),frac(k)); end
                    % The {'Prop'},values form of set() takes no trailing
                    % name/value pairs, so Visible is its own call.
                    set(obj.ValueText(:),{'String'},strs(:));
                    set(obj.ValueText,'Visible','on');
                end
            end
            t = obj.bodyTitle();
            if ~show
                % Rather than leave the bars anonymous with no explanation --
                % and the view that WOULD fit this many conditions is one
                % dropdown away.
                t = sprintf(['%s (%d — too many to label; group by a ' ...
                    'parameter, or use the heat map)'],t,n);
            end
            title(ax,t,'FontSize',10,'FontWeight','normal','Color',obj.MutedColor);
        end

        function drawHeat(obj,done,target)
            P = obj.paramTable();
            if numel(P.names) < 2
                obj.showMessage(['The heat map needs two stimulus parameters; ' ...
                    'this bank varies fewer. Try the bar views.']);
                return
            end
            jx = find(strcmp(P.names,obj.HeatX),1);
            jy = find(strcmp(P.names,obj.HeatY),1);
            if isempty(jx) || isempty(jy) || jx == jy
                obj.showMessage('Pick two different parameters for the heat map''s axes.');
                return
            end

            vx = P.values(:,jx).';  xu = unique(vx(~isnan(vx)));
            vy = P.values(:,jy).';  yu = unique(vy(~isnan(vy)));
            nx = numel(xu); ny = numel(yu);
            key = sprintf('heat|%s|%s|%d|%d|%d',obj.HeatX,obj.HeatY,nx,ny,numel(done));
            ax  = obj.Axes;

            if ~strcmp(obj.LayoutKey,key)
                obj.clearAxes();
                % Which cell each stimulus lands in, worked out ONCE: the
                % refresh path is then one accumarray, not a search per
                % stimulus per repaint.
                cell_ = nan(1,numel(vx));
                for i = 1:numel(vx)
                    if isnan(vx(i)) || isnan(vy(i)), continue; end
                    cell_(i) = sub2ind([ny nx],find(yu == vy(i),1),find(xu == vx(i),1));
                end
                obj.Map = struct('cell',cell_,'nx',nx,'ny',ny);

                % image(), not imagesc(): the low-level form defaults to
                % DIRECT CData mapping, so 'scaled' is stated rather than
                % assumed -- a fraction indexing the colormap directly would
                % paint every cell the same colour.
                obj.HeatImage = image('Parent',ax,'XData',1:nx,'YData',1:ny, ...
                    'CData',nan(ny,nx),'AlphaData',zeros(ny,nx), ...
                    'CDataMapping','scaled');
                hold(ax,'on');
                [gx,gy] = gridLines(nx,ny);
                plot(ax,gx,gy,'-','Color',obj.PaperColor,'LineWidth',1.5);
                obj.HeatText = gobjects(0,0);
                if nx*ny <= obj.MaxCells
                    obj.HeatText = gobjects(ny,nx);
                    for c = 1:nx
                        for r = 1:ny
                            obj.HeatText(r,c) = text(ax,c,r,'', ...
                                'HorizontalAlignment','center','VerticalAlignment','middle', ...
                                'FontSize',9,'Color',obj.InkColor);
                        end
                    end
                end
                hold(ax,'off');

                ax.YDir  = 'normal';           % level increases upward
                ax.XLim  = [0.5 nx+0.5];
                ax.YLim  = [0.5 ny+0.5];
                ax.XTick = 1:nx; ax.XTickLabel = compose('%g',xu);
                ax.YTick = 1:ny; ax.YTickLabel = compose('%g',yu);
                ax.Color = [0.965 0.969 0.976];
                ax.Box   = 'on';
                ax.XColor = obj.MutedColor; ax.YColor = obj.MutedColor;
                ax.FontSize = 10;
                xlabel(ax,obj.HeatX,'Color',obj.InkColor);
                ylabel(ax,obj.HeatY,'Color',obj.InkColor);
                colormap(ax,heatColors());
                ax.CLim = [0 1];
                obj.addColorBar(ax);
                obj.LayoutKey = key;
            end

            m  = obj.Map;
            ok = ~isnan(m.cell);
            D  = accumarray(m.cell(ok).',done(ok).',  [m.ny*m.nx 1]);
            T  = accumarray(m.cell(ok).',target(ok).',[m.ny*m.nx 1]);
            D  = reshape(D,m.ny,m.nx); T = reshape(T,m.ny,m.nx);
            Fr = D./T;
            Fr(T == 0) = NaN;

            set(obj.HeatImage,'CData',min(1,Fr),'AlphaData',double(~isnan(Fr)));

            if isempty(obj.HeatText)
                % A grid too dense to write in; the shading carries it.
            elseif strcmp(obj.Labels,'none')
                set(obj.HeatText,'Visible','off');
            else
                strs = cell(m.ny,m.nx); cols = cell(m.ny,m.nx);
                for c = 1:m.nx
                    for r = 1:m.ny
                        if T(r,c) == 0
                            strs{r,c} = ''; cols{r,c} = obj.MutedColor;
                        else
                            strs{r,c} = obj.valueText(D(r,c),T(r,c),Fr(r,c));
                            % Dark ink on a pale cell, white once the cell is
                            % dark enough to swallow it.
                            if Fr(r,c) > 0.55, cols{r,c} = [1 1 1];
                            else,              cols{r,c} = obj.InkColor;
                            end
                        end
                    end
                end
                set(obj.HeatText(:),{'String','Color'},[strs(:) cols(:)]);
                set(obj.HeatText,'Visible','on');
            end
            title(ax,obj.bodyTitle(),'FontSize',10,'FontWeight','normal', ...
                'Color',obj.MutedColor);
        end

        function addColorBar(obj,ax)
            try
                obj.ColorBar = colorbar(ax);
                obj.ColorBar.Ticks      = [0 0.5 1];
                obj.ColorBar.TickLabels = {'0','50','100%'};
                obj.ColorBar.Color      = obj.MutedColor;
                obj.ColorBar.FontSize   = 9;
            catch
                obj.ColorBar = [];   % a colorbar is a nicety, not a requirement
            end
        end

        function s = valueText(obj,done,target,frac)
            if target <= 0, s = '—'; return; end
            switch obj.Labels
                case 'counts',  s = sprintf('%d/%d',round(done),round(target));
                case 'percent', s = sprintf('%.0f%%',100*frac);
                otherwise,      s = '';
            end
        end

        function t = bodyTitle(obj)
            [sch,~] = obj.plan();
            what = 'presentations';
            if ~isempty(sch) && sch.StimulationOnly, what = 'presentations played'; end
            switch obj.View
                case 'bars'
                    if strcmpi(obj.GroupBy,'Stimulus')
                        t = sprintf('%s complete, by stimulus',capitalize_(what));
                    else
                        t = sprintf('%s complete, by %s',capitalize_(what),obj.GroupBy);
                    end
                case 'heatmap'
                    t = sprintf('%s complete',capitalize_(what));
                otherwise
                    t = '';
            end
        end

        function showMessage(obj,txt)
            % Idempotent: an idle window would otherwise tear down and rebuild
            % this one text object on every refresh.
            if strcmp(obj.LayoutKey,['msg|' txt]), return; end
            obj.clearAxes();
            ax = obj.Axes;
            ax.XLim = [0 1]; ax.YLim = [0 1];
            ax.XTick = []; ax.YTick = [];
            ax.XColor = 'none'; ax.YColor = 'none';
            ax.Color = obj.PaperColor;
            title(ax,'');
            obj.MsgText = text(ax,0.5,0.5,txt,'HorizontalAlignment','center', ...
                'VerticalAlignment','middle','FontSize',11,'Color',obj.MutedColor);
            obj.LayoutKey = ['msg|' txt];
        end

        function clearAxes(obj)
            % Layout changes are rare and user-driven, so this is the one place
            % graphics objects are created and destroyed at all.
            if ~isempty(obj.ColorBar) && isgraphics(obj.ColorBar)
                delete(obj.ColorBar);
            end
            obj.ColorBar = [];
            cla(obj.Axes,'reset');
            obj.TrackPatch = [];
            obj.FillPatch  = [];
            obj.ValueText  = gobjects(1,0);
            obj.HeatImage  = [];
            obj.HeatText   = gobjects(1,0);
            obj.MsgText    = [];
            obj.Map        = struct();
            % cla(...,'reset') puts every axes property back to its default,
            % so the geometry buildPlot chose has to be restated here.
            obj.Axes.Units              = 'normalized';
            obj.Axes.PositionConstraint = 'outerposition';
            obj.Axes.OuterPosition      = [0 0 1 1];
            mabr.ui.hideAxesToolbar(obj.Axes);
            disableDefaultInteractivity(obj.Axes);
        end
    end
end

% ======================= local helpers ================================
function V = barVertices(frac,n,h,span)
% 4 vertices per bar, [4n x 2], in the order the Faces matrix expects.
x1 = zeros(1,n);
x2 = span.*max(0,min(1,frac));
y  = 1:n;
V  = zeros(4*n,2);
V(1:4:end,:) = [x1(:) y(:)-h/2];
V(2:4:end,:) = [x2(:) y(:)-h/2];
V(3:4:end,:) = [x2(:) y(:)+h/2];
V(4:4:end,:) = [x1(:) y(:)+h/2];
end

function [gx,gy] = gridLines(nx,ny)
% Cell borders as ONE line object: NaN-separated segments.
xv = 0.5:1:(nx+0.5);
yv = 0.5:1:(ny+0.5);
gx = [reshape([xv;xv;nan(1,numel(xv))],1,[]) ...
      reshape([repmat(0.5,1,numel(yv)); repmat(nx+0.5,1,numel(yv)); nan(1,numel(yv))],1,[])];
gy = [reshape([repmat(0.5,1,numel(xv)); repmat(ny+0.5,1,numel(xv)); nan(1,numel(xv))],1,[]) ...
      reshape([yv;yv;nan(1,numel(yv))],1,[])];
end

function cm = heatColors()
% A single-hue sequential ramp: pale where nothing has been run, deep where a
% condition is finished. One hue so the eye reads it as an amount rather than
% as a category, which is what a diverging or rainbow map would imply.
anchors = [0.957 0.965 0.976
           0.796 0.878 0.902
           0.518 0.741 0.780
           0.243 0.565 0.639
           0.055 0.318 0.400];
cm = interp1(linspace(0,1,size(anchors,1)).',anchors,linspace(0,1,64).');
end

function [x,y] = defaultAxes(names)
% Frequency across, level up -- the orientation every published ABR grid uses,
% so the window opens on the arrangement an audiologist already reads. Falls
% back to the first two parameters the bank declares when neither name is
% recognisable.
x = ''; y = '';
if isempty(names), return; end
low = lower(names);
ix  = find(contains(low,{'freq','khz','carrier'}),1);
iy  = find(contains(low,{'level','db','spl','atten','inten'}),1);
if isequal(ix,iy), iy = []; end
if isempty(ix), ix = find(~ismember(1:numel(names),iy),1); end
if isempty(iy), iy = find(~ismember(1:numel(names),ix),1); end
if isempty(ix), ix = 1; end
if isempty(iy), iy = min(2,numel(names)); end
x = names{ix};
y = names{iy};
end

function s = shorten(s,n)
if numel(s) > n, s = [s(1:n-1) '…']; end
end

function s = capitalize_(s)
if ~isempty(s), s(1) = upper(s(1)); end
end

function s = clockText(secs)
% m:ss under an hour, h:mm:ss over it -- a wall clock, not a sentence: this
% one is read at a glance and re-read every second.
secs = max(0,round(secs));
h = floor(secs/3600); m = floor(mod(secs,3600)/60); s_ = mod(secs,60);
if h > 0
    s = sprintf('%d:%02d:%02d',h,m,s_);
else
    s = sprintf('%d:%02d',m,s_);
end
end

function setDropdown(d,items,data,value)
% Items and ItemsData must always be the same length, and they are set one at a
% time -- so the old data is cleared first rather than left briefly longer than
% the new list.
d.ItemsData = {};
d.Items     = items;
d.ItemsData = data;
if ismember(value,data), d.Value = value; end
end

function setEnabled(controls,tf)
% A cell array, not a handle array: these are different classes and cannot be
% concatenated into one (the same reason mabr.ui.App.setEnable takes a cell).
state = 'off'; if tf, state = 'on'; end
for k = 1:numel(controls)
    c = controls{k};
    if ~isempty(c) && isvalid(c), c.Enable = state; end
end
end
