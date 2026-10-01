classdef PresentationOrder < handle
% mabr.ui.PresentationOrder  The order the plan presents its conditions in.
%
%   mabr.ui.ProgressMonitor answers "how much of each condition is done";
%   this window answers "in what ORDER are they played, and which one is on
%   now". One axes: presentation number along x -- counted across the whole
%   plan, run after run, exactly as mabr.stim.Schedule.Runs holds them -- and
%   one row per condition up the y axis, so every presentation is a mark in
%   its condition's row. The rows are the conditions the plan presents, named
%   by the parameters the bank varies (from mabr.stim.StimulusSet.paramTable:
%   '8 kHz, 30 dB', the convention mabr.ui.LivePlot and the progress monitor
%   use), and they are in the SAME ORDER as the table beside the plot: the
%   y axis, top to bottom, is the table, top to bottom, whatever Sort by /
%   then by say. With no sort chosen both read in the bank's parameters,
%   ascending, so a Frequency x Level grid reads top to bottom as the grid it
%   is.
%
%   A conventional plan comes out as a staircase (one condition per run); an
%   interleaved one as a sawtooth repeated every cycle; a shuffled one as
%   scatter. Presentations already made are drawn in blue, the rest in grey,
%   and dotted verticals mark the run boundaries.
%
%   The ACTIVE condition -- the one being presented -- is highlighted three
%   ways at once: an amber band along its row, its row label in bold amber,
%   and an amber marker with a cursor line at the presentation itself. The
%   header names it and says where in the plan the rig is.
%
%   Switching conditions off
%   ------------------------
%   The table beside the plot lists every condition with an On box and how
%   many of its presentations lie in the runs still to come. Clearing a box
%   takes that condition out of every run not yet started
%   (mabr.stim.Schedule.setEnabled); ticking it again puts it back, as long
%   as its run has not been reached. The run in progress always plays as it
%   was rendered -- a run's plan is fixed before it streams, and the
%   controller pairs every recorded onset with that plan -- so a change
%   applies from the next run, and under a strategy that plays everything in
%   one run, only to runs appended after it (make-up, repeat). An upcoming
%   presentation of a condition that is off is drawn as a cross rather than a
%   dot, and its row label is greyed (the colour is the whole of the cue: no
%   word is added to the label).
%
%   Four buttons under the table do in one press what the On boxes do in
%   several, each with a pictogram from mabr.ui.Icon beside its caption:
%     Skip next       switches off the next condition in the queue -- the one
%                     the next run to start would present first. Pressed
%                     again it takes the one after. Its tooltip names it, and
%                     it is greyed when no run waits after the one in progress
%                     (an intermixed plan is one run).
%     Disable above   switches off every condition above the row picked in
%     Disable below   the table (or below it), counted in the order the table
%                     SHOWS them -- the sort chosen above it, not the plot's
%                     order. A click in the table picks a whole row; with
%                     several picked, the reach starts at the outer edge of the
%                     selection. Greyed until a row is picked and something on
%                     that side is still on.
%     Enable all      switches everything back on.
%   All four go through mabr.stim.Schedule.setEnabled, so all of the above
%   about the run in progress holds for them too.
%
%   When switching is not available
%   -------------------------------
%   A switch reaches only runs not yet started. A plan that mixes conditions
%   inside a run (interleaved, interleaved-random, shuffled, or a custom
%   strategy that does) plays as one run, so WHILE ITS LAST RUN IS BEING
%   PRESENTED there is no run waiting for a switch to reach: the On boxes
%   stop being editable, and Skip next, Disable above, Disable below and
%   Enable all are greyed, each tooltip (and the note under the table) saying
%   why (switchesLocked). The window's other controls -- the sort, the span,
%   the selection, Stay on top -- are views and stay live. Everything comes
%   back the moment the run is over, and it is never applied to a plan whose
%   runs each present one condition (conventional, conventional-shuffled):
%   every switch there stays live all through, Skip next greying itself by
%   its own rule once no run is left to skip into.
%
%   Stay on top (bottom right) keeps the window above every other one, the
%   mechanism the main window's pin and the progress monitor use (uifigure
%   WindowStyle 'alwaysontop'). It is remembered between sessions (pref
%   MABR/OrderOnTop), written only when the button is pressed.
%
%   The table's columns
%   -------------------
%   One column per stimulus parameter the bank varies (Frequency, Level, ...)
%   between On and Upcoming -- or a single Condition column, the stimulus ID,
%   for a bank that varies nothing. The rows are sorted by two keys chosen
%   above the table (Sort by / then by, each a column and a direction), so a
%   Frequency x Level bank can read 1 kHz 80 dB, 1 kHz 70 dB, ... 2 kHz 80 dB,
%   ...: Frequency ascending, then Level descending. Both keys and their
%   directions are remembered between sessions (prefs MABR/OrderSortKeys,
%   OrderSortDirs), written only when the user changes them; a key the bank
%   has no column for is ignored.
%
%   The sort is this window's own and the uitable has no sorting or dragging
%   of its own: the table is only ever updated in place, with its rows already
%   in order. Rows is that order -- the one list the table AND the y axis
%   are drawn from, so a table row is a plot row and an On box needs no
%   translating. The order is worked out when the keys, the plan, or -- for a
%   sort on Upcoming -- the counts change, and NOT when a box is ticked, so a
%   row does not jump away from the pointer that just clicked it (and the
%   plot does not shuffle under the eye either). When it does change, the
%   plot is re-laid to match: the labels, and the height of every mark.
%
%   What "being presented" means
%   ----------------------------
%   The position is the controller's live sweep count paired against the
%   run's own sequence -- the pairing mabr.ui.AcqController.finalize_run
%   de-interleaves by -- so the highlighted presentation is the LATEST ONE
%   THE RIG HAS RECORDED, not one inferred from a clock. At the very start of
%   a run, before its first sweep is in, it is the run's first presentation.
%   Between a run's end and the next run's start the last presentation stays
%   highlighted; at rest nothing is. In stimulation-only mode nothing is
%   recorded, so the position is ESTIMATED from the run's clock (onset k at
%   SilencePad + (k-1)*MeanISI, pauses excluded), the header says so ('~'),
%   and Estimated is true -- the same estimate the progress monitor makes.
%
%   Span
%   ----
%   Span decides how much of the plan the x axis shows:
%     'window'  WindowLength presentations around the active one, following
%               it -- the only legible view of a long intermixed run, where
%               the whole plan is tens of thousands of marks;
%     'run'     the whole of the run being presented;
%     'plan'    the whole plan;
%     'auto'    (default) 'plan' when every run presents one condition (a
%               conventional plan's order IS its runs), 'window' otherwise.
%   Consecutive presentations are joined by a line only while few enough are
%   shown to follow one.
%
%   Cost
%   ----
%   It rides the controller's auxiliary tick (MetricsUpdated, ~2 Hz) and
%   repaints at most every MinInterval seconds, writes a graphics property
%   only when its value changed, and never calls drawnow (see
%   mabr.ui.ProgressMonitor for why that matters inside a timer callback).
%   The plan's sequence and rows are rebuilt only when the plan changes
%   shape -- a new schedule, or a make-up or repeat run appended to it. A
%   timer of its own ticks only during a stimulation-only run, where there is
%   no aux tick to ride.
%
%   Use
%   ---
%       po = mabr.ui.PresentationOrder();
%       po.listenTo(controller);          % follow an AcqController
%       po.attach(schedule,stimulusSet);  % or show a plan with no controller
%       po.Span = 'plan';
%
%   Closing the window deletes the object, listeners and timer with it.
%
%   See also mabr.ui.ProgressMonitor, mabr.stim.Schedule, mabr.ui.App.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        Spans = {'auto','window','run','plan'};
    end

    properties (Constant, Access = private)
        SpanLabels  = {'Auto','Around current','Current run','Whole plan'};
        PendColor   = [0.620 0.651 0.690];   % not yet presented
        PendJoin    = [0.878 0.890 0.910];
        DoneColor   = [0.216 0.451 0.678];   % presented
        DoneJoin    = [0.694 0.784 0.867];
        ActiveColor = [0.898 0.616 0.180];   % being presented
        ActiveInk   = [0.702 0.420 0.000];   % the same amber, dark enough for text
        OffColor    = [0.788 0.439 0.439];   % an upcoming presentation switched off
        OffInk      = [0.600 0.620 0.650];   % a switched-off row's label
        ActiveRowBg = [0.992 0.906 0.757];
        MutedColor  = [0.478 0.514 0.565];
        PanelColor  = [0.969 0.973 0.980];
        % Joined by a line only while this few presentations are on screen;
        % beyond it the joins are a grey wash that says nothing.
        MaxJoined   = 400;
        % Open markers while this few are on screen, dots beyond.
        MaxOpen     = 150;
        % Run boundaries are drawn only while there are this few of them.
        MaxRunLines = 500;
        ClockPeriod = 0.5;
        % What the note under the table says, and the one reason every
        % greyed switch gives (see switchesLocked).
        NoteText = ['Changes apply from the next run: the run in progress ' ...
                    'plays as it was rendered.'];
        LockText = ['Not available while this run plays: it presents every condition ' ...
                    'at once and no later run is waiting for a switch to reach.'];
        TableTip = ['Clear On to leave a condition out of the runs not yet ' ...
                    'started; tick it to put it back. The order is set by ' ...
                    'Sort by / then by above, and is the order of the plot''s rows.'];
        AboveTip = ['Switch off every condition above the selected row, in the ' ...
                    'order the table shows them. Select a row first.'];
        BelowTip = ['Switch off every condition below the selected row, in the ' ...
                    'order the table shows them. Select a row first.'];
        AllTip   = 'Switch every condition back on.';
    end

    properties
        Span         (1,:) char = 'auto'
        WindowLength (1,1) double {mustBePositive,mustBeInteger} = 60
        MinInterval  (1,1) double {mustBeNonnegative} = 0.2
        Title        (1,:) char = 'MABR Presentation Order'
        AlwaysOnTop  (1,1) logical = false   % keep the window above the others
    end

    properties (SetAccess = private)
        Figure
        Axes
        Controller                 % mabr.ui.AcqController followed, if any
        Schedule                   % plan shown when no controller is attached
        Stimuli
        Sequence  (1,:) double = []   % stimulus index of every presentation, plan order
        RunStarts (1,:) double = 0    % presentations before each run; run r is RunStarts(r)+1:RunStarts(r+1)
        Rows      (1,:) double = []   % stimulus index of each y row, top to bottom -- and of each table row
        RowLabels (1,:) cell   = {}   % what each row is called (plain text)
        Done      (1,1) double = 0    % presentations made, counted across the plan
        Current   (1,1) double = 0    % the highlighted presentation (0 = none)
        ActiveStimulus (1,1) double = 0   % its stimulus index (0 = none)
        Estimated (1,1) logical = false   % the position is estimated from the clock
        Paused    (1,1) logical = false

        % The drawn objects, public to read so a script (and the verification
        % suite) can ask what the window is actually showing.
        PendingLine
        DoneLine
        OffLine                    % upcoming presentations of conditions switched off
        Table                      % the On / Condition / Upcoming table
        ActiveBand
        ActiveMarker
        CursorLine
        RunLines
        NowLabel
        InfoLabel
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners
        ClockTimer
        PlanSched                     % the schedule the current layout was built for
        PlanKey   (1,:) double = []
        RowOf     (1,:) double = []   % y row of each stimulus index (0 = not in plan)
        YSeq      (1,:) double = []   % y of every presentation
        BaseRows  (1,:) double = []   % the conditions the plan presents, in the bank's parameter order: what the sort starts from
        AllLabels (1,:) cell   = {}   % every stimulus's name, by stimulus index
        AllVals   (:,:) double = zeros(0,0)   % every stimulus's varying parameters, by stimulus index
        OffKey    (1,:) double = []   % what the switched-off drawing was made for
        TableKey  (1,:) double = []   % what the table was last filled for
        Side                          % the grid the table sits in (it is rebuilt in place)
        ColIds    (1,:) cell   = {}   % the table's columns, left to right
        SortKeys  (1,:) cell   = {}   % column ids the rows are sorted by, most significant first
        SortDirs  (1,:) cell   = {}   % 'ascend' or 'descend' for each
        ParamNames (1,:) cell  = {}   % the varying parameters, one table column each
        ParamUnits (1,:) cell  = {}
        RowVals   (:,:) double = zeros(0,0)   % their values, one row per y row
        SelStim   (1,:) double = []   % the conditions the user picked in the table
        OrderKey  = {}                % what Rows was last put in order for
        PlanVersion (1,1) double = 0  % bumped whenever the rows are rebuilt
        RowKey    (1,:) double = []   % what the row labels were last drawn for
        Blocked   (1,1) logical = false   % every run presents one condition
        StateNow  (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        Phase = struct('run',false,'acquire',false,'complete',false,'rest',true,'txt','Idle')
        LiveRun    (1,1) double = 0   % the run the live count belongs to
        LiveSweeps (1,1) double = 0
        RunT0     (1,1) uint64 = uint64(0)
        RunT1     (1,1) double = NaN
        RunPaused (1,1) double = 0
        PauseT0   (1,1) uint64 = uint64(0)
        LastDraw  (1,1) uint64 = uint64(0)
        Shown = struct()              % what each property was last set to (see put)
    end

    methods
        function obj = PresentationOrder()
            obj.loadDefaults();
            obj.Figure = uifigure('Name',obj.Title,'Tag','MABR_ORDER', ...
                'Position',[100 100 760 480],'Color',obj.PanelColor);
            obj.Figure.CloseRequestFcn = @(~,~) delete(obj);
            obj.build();
            obj.applyOnTop();
            obj.refresh(true);
        end

        function delete(obj)
            obj.stopListening();
            obj.stopClock(true);
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Axes) && isgraphics(obj.Axes);
        end

        function listenTo(obj,controller)
            % Follow an mabr.ui.AcqController. Re-points rather than stacking
            % a second set of listeners. Its Schedule is read on every
            % refresh rather than held, since a new Start replaces it.
            obj.stopListening();
            obj.Controller = [];
            obj.resetPosition();
            if nargin >= 2 && ~isempty(controller) && isvalid(controller)
                obj.Controller = controller;
                obj.setStateNow(controller.State);
                L = [ ...
                    addlistener(controller,'StateChanged',    @(~,e) obj.onState(e)); ...
                    addlistener(controller,'MetricsUpdated',  @(~,e) obj.onMetrics(e)); ...
                    addlistener(controller,'ScheduleComplete',@(~,~) obj.refresh(true))];
                eng = engineOf(controller);
                if ~isempty(eng)
                    L = [L; addlistener(eng,'StateChanged',@(~,e) obj.onEngineState(e))];
                    if eng.State == mabr.acq.State.Paused
                        obj.Paused = true; obj.PauseT0 = tic;
                    end
                end
                obj.Listeners = L;
                if obj.Phase.run
                    % Opened mid-run: the count arrives with the next
                    % update; until then the run's start is the best answer.
                    sch = obj.plan();
                    if ~isempty(sch), obj.LiveRun = sch.current(); end
                end
                obj.syncClock();
            end
            obj.PlanKey = [];
            obj.refresh(true);
        end

        function attach(obj,schedule,stimuli)
            % Show a plan with no controller behind it -- a script, a test,
            % or the App before the first Start. A controller attached
            % through listenTo still wins.
            if nargin < 3, stimuli = []; end
            obj.Schedule = schedule;
            if isempty(stimuli) && ~isempty(schedule) && isvalid(schedule)
                stimuli = schedule.Set;
            end
            obj.Stimuli = stimuli;
            obj.PlanKey = [];
            obj.refresh(true);
        end

        function reset(obj)
            obj.Schedule = [];
            obj.Stimuli  = [];
            obj.resetPosition();
            obj.PlanKey = [];
            obj.refresh(true);
        end

        function r = visibleRange(obj)
            % The presentations the x axis shows, [first last].
            r = [0 0];
            if ~obj.isvalidView(), return; end
            x = obj.Axes.XLim;
            r = [ceil(x(1)) floor(x(2))];
        end

        function s = resolvedSpan(obj)
            % Span with 'auto' decided for the plan on screen.
            s = obj.Span;
            if strcmp(s,'auto')
                if obj.Blocked, s = 'plan'; else, s = 'window'; end
            end
        end

        function refresh(obj,force)
            % Repaint from the plan and the live count. Throttled to
            % MinInterval unless forced.
            if nargin < 2, force = false; end
            if ~obj.isvalidView(), return; end
            if ~force && obj.LastDraw ~= 0 && toc(obj.LastDraw) < obj.MinInterval, return; end
            obj.LastDraw = tic;
            [sch,bank] = obj.plan();
            obj.syncPlan(sch,bank);
            if isempty(obj.Sequence)
                obj.paint(0,0,sch);
                return
            end
            [done,cur] = obj.position(sch);
            obj.paint(done,cur,sch);
        end

        function set.Span(obj,v)
            v = validatestring(v,mabr.ui.PresentationOrder.Spans);
            obj.Span = v;
            obj.settingChanged();
        end

        function set.WindowLength(obj,v)
            obj.WindowLength = v;
            obj.settingChanged();
        end

        function set.Title(obj,txt)
            obj.Title = txt;
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), obj.Figure.Name = txt; end %#ok<MCSUP>
        end

        function set.AlwaysOnTop(obj,tf)
            obj.AlwaysOnTop = logical(tf);
            obj.applyOnTop();
        end
    end

    methods (Access = private)
        % --- Construction -----------------------------------------------------
        function build(obj)
            g = uigridlayout(obj.Figure,[3 2]);
            g.RowHeight   = {44,'1x',30};
            g.ColumnWidth = {'1x',320};
            g.RowSpacing  = 6;
            g.ColumnSpacing = 8;
            g.Padding     = [8 8 8 8];
            g.BackgroundColor = obj.PanelColor;

            h = uigridlayout(g,[2 1]);
            h.Layout.Row = 1; h.Layout.Column = [1 2];
            h.RowHeight = {22,18}; h.RowSpacing = 2; h.Padding = [4 0 4 0];
            h.BackgroundColor = obj.PanelColor;
            obj.NowLabel = uilabel(h,'Text','','FontSize',15,'FontWeight','bold', ...
                'FontColor',obj.ActiveInk);
            obj.InfoLabel = uilabel(h,'Text','','FontColor',obj.MutedColor);

            ax = uiaxes(g);
            ax.Layout.Row = 2; ax.Layout.Column = 1;
            mabr.ui.hideAxesToolbar(ax);
            ax.YDir = 'reverse';
            ax.Box  = 'on';
            ax.TickLabelInterpreter = 'tex';
            ax.XGrid = 'off'; ax.YGrid = 'on';
            ax.GridAlpha = 0.08;
            ax.TickDir = 'out';
            ax.Color = [1 1 1];
            xlabel(ax,'Presentation (plan order)');
            hold(ax,'on');
            obj.Axes = ax;

            % Back to front: the band behind everything, then the run
            % boundaries, the plan, what has been played, and the cursor.
            obj.ActiveBand = patch(ax,'XData',nan(4,1),'YData',nan(4,1), ...
                'FaceColor',obj.ActiveColor,'FaceAlpha',0.22,'EdgeColor','none', ...
                'HitTest','off','Visible','off');
            obj.RunLines = line(ax,NaN,NaN,'LineStyle',':','Color',obj.MutedColor, ...
                'LineWidth',0.75,'HitTest','off');
            obj.PendingLine = line(ax,NaN,NaN,'Color',obj.PendJoin, ...
                'Marker','.','MarkerEdgeColor',obj.PendColor,'MarkerSize',8,'HitTest','off');
            obj.DoneLine = line(ax,NaN,NaN,'Color',obj.DoneJoin, ...
                'Marker','.','MarkerEdgeColor',obj.DoneColor, ...
                'MarkerFaceColor',obj.DoneColor,'MarkerSize',8,'HitTest','off');
            obj.OffLine = line(ax,NaN,NaN,'LineStyle','none','Marker','x', ...
                'MarkerEdgeColor',obj.OffColor,'MarkerSize',6,'HitTest','off');
            obj.CursorLine = line(ax,NaN,NaN,'Color',obj.ActiveColor,'LineWidth',1.25, ...
                'HitTest','off');
            obj.ActiveMarker = line(ax,NaN,NaN,'LineStyle','none','Marker','o', ...
                'MarkerSize',10,'LineWidth',2,'MarkerEdgeColor',obj.ActiveInk, ...
                'MarkerFaceColor',obj.ActiveColor,'HitTest','off');

            side = uigridlayout(g,[4 1]);
            side.Layout.Row = 2; side.Layout.Column = 2;
            side.RowHeight = {52,'1x',44,60};
            side.RowSpacing = 4; side.Padding = [0 0 0 0];
            side.BackgroundColor = obj.PanelColor;
            obj.Side = side;
            obj.buildSortControls();
            obj.buildTable();
            note = uilabel(side,'WordWrap','on','FontSize',11,'FontColor',obj.MutedColor, ...
                'Text',obj.NoteText);
            note.Layout.Row = 3;
            obj.Ctrl.note = note;
            obj.buildButtons();

            c = uigridlayout(g,[1 6]);
            c.Layout.Row = 3; c.Layout.Column = [1 2];
            c.ColumnWidth = {40,130,50,80,'1x',112};
            c.Padding = [4 0 4 0];
            c.BackgroundColor = obj.PanelColor;
            uilabel(c,'Text','Show','HorizontalAlignment','right');
            obj.Ctrl.span = uidropdown(c,'Tag','OrderSpan','Items',obj.SpanLabels,'ItemsData',obj.Spans, ...
                'Value',obj.Span,'ValueChangedFcn',@(s,~) obj.onControl('Span',s.Value), ...
                'Tooltip',['How much of the plan to show: the presentations around ' ...
                           'the current one, its run, or the whole plan. Auto shows ' ...
                           'the whole plan when every run presents one condition.']);
            uilabel(c,'Text','Width','HorizontalAlignment','right');
            obj.Ctrl.width = uispinner(c,'Limits',[1 Inf],'Step',10, ...
                'RoundFractionalValues','on','Value',obj.WindowLength, ...
                'ValueChangedFcn',@(s,~) obj.onControl('WindowLength',s.Value), ...
                'Tooltip','Presentations shown around the current one');
            obj.Ctrl.onTop = uibutton(c,'state','Text','Stay on top','Tag','OrderOnTop', ...
                'Value',obj.AlwaysOnTop, ...
                'ValueChangedFcn',@(s,~) obj.onTopPressed(s.Value), ...
                'Tooltip',['Keep this window above every other window, so it stays in ' ...
                           'view while the rig and the other viewers are being worked.']);
            obj.Ctrl.onTop.Layout.Column = 6;
            obj.setButtonIcon(obj.Ctrl.onTop,'pin');
        end

        function buildButtons(obj)
            % The four things the table's On boxes would otherwise take many
            % clicks to do. Each has a picture beside its caption (mabr.ui.Icon,
            % the same art as the toolbars); a disabled one says why in its
            % tooltip once there is something to say.
            bt = uigridlayout(obj.Side,[2 2]);
            bt.Layout.Row = 4;
            bt.RowHeight = {28,28}; bt.ColumnWidth = {'1x','1x'};
            bt.RowSpacing = 4; bt.ColumnSpacing = 4; bt.Padding = [0 0 0 0];
            bt.BackgroundColor = obj.PanelColor;
            %       field        Tag              caption          row col  action
            spec = { ...
                'skipNext',  'OrderSkipNext',  'Skip next',     1, 1, @() obj.skipNext(); ...
                'enableAll', 'OrderEnableAll', 'Enable all',    1, 2, @() obj.enableAll(); ...
                'disAbove',  'OrderDisAbove',  'Disable above', 2, 1, @() obj.disableSide('above'); ...
                'disBelow',  'OrderDisBelow',  'Disable below', 2, 2, @() obj.disableSide('below')};
            tips = struct('enableAll',obj.AllTip,'disAbove',obj.AboveTip, ...
                          'disBelow',obj.BelowTip);
            for k = 1:size(spec,1)
                fcn = spec{k,6};
                b = uibutton(bt,'Text',spec{k,3},'Tag',spec{k,2}, ...
                    'ButtonPushedFcn',@(~,~) fcn());
                b.Layout.Row = spec{k,4}; b.Layout.Column = spec{k,5};
                if isfield(tips,spec{k,1}), b.Tooltip = tips.(spec{k,1}); end
                obj.Ctrl.(spec{k,1}) = b;
            end
            obj.setButtonIcon(obj.Ctrl.skipNext,'skipnext');
            obj.setButtonIcon(obj.Ctrl.enableAll,'enableall');
            obj.setButtonIcon(obj.Ctrl.disAbove,'offabove');
            obj.setButtonIcon(obj.Ctrl.disBelow,'offbelow');
            obj.syncButtons([]);
        end

        function setButtonIcon(~,btn,glyph)
            % A picture beside the caption, from mabr.ui.Icon -- kept
            % transparent so it sits on whatever colour the button is (idle,
            % pressed, disabled). If the file cannot be made the button keeps
            % its caption and nothing else.
            f = mabr.ui.Icon.file(glyph);
            if isempty(f), return; end
            btn.Icon = f;
            btn.IconAlignment = 'left';
        end

        function onTopPressed(obj,tf)
            % Written to prefs only from the button -- a user choosing how
            % the window sits, never a script setting the property.
            obj.AlwaysOnTop = tf;
            try
                setpref('MABR','OrderOnTop',obj.AlwaysOnTop);
            catch
            end
        end

        function applyOnTop(obj)
            % 'alwaysontop' is a documented uifigure WindowStyle (R2021a, inside
            % MABR's R2021b floor) -- the mechanism the main window's pin and
            % the progress monitor use, nothing undocumented.
            if isempty(obj.Figure) || ~isgraphics(obj.Figure), return; end
            if obj.AlwaysOnTop, want = 'alwaysontop'; else, want = 'normal'; end
            if ~strcmp(obj.Figure.WindowStyle,want), obj.Figure.WindowStyle = want; end
            if isfield(obj.Ctrl,'onTop') && isvalid(obj.Ctrl.onTop) ...
                    && obj.Ctrl.onTop.Value ~= obj.AlwaysOnTop
                obj.Ctrl.onTop.Value = obj.AlwaysOnTop;
            end
        end

        function onControl(obj,what,value)
            obj.(what) = value;
            obj.savePrefs();
        end

        function settingChanged(obj)
            if ~obj.isvalidView(), return; end
            if isfield(obj.Ctrl,'span') && isvalid(obj.Ctrl.span)
                obj.Ctrl.span.Value  = obj.Span;
                obj.Ctrl.width.Value = obj.WindowLength;
            end
            obj.refresh(true);
        end

        function syncControls(obj)
            if ~isfield(obj.Ctrl,'width') || ~isvalid(obj.Ctrl.width), return; end
            want = matlab.lang.OnOffSwitchState(strcmp(obj.resolvedSpan(),'window'));
            obj.put('widthEnable',obj.Ctrl.width,'Enable',want);
        end

        function loadDefaults(obj)
            % Forgiving: a pref edited by hand must not stop the window opening.
            try
                s = getpref('MABR','OrderSpan','auto');
                if ischar(s) && any(strcmp(s,obj.Spans)), obj.Span = s; end
            catch
            end
            try
                w = getpref('MABR','OrderWindow',60);
                if isnumeric(w) && isscalar(w) && isfinite(w) && w >= 1
                    obj.WindowLength = round(w);
                end
            catch
            end
            try
                t = getpref('MABR','OrderOnTop',false);
                if (islogical(t) || isnumeric(t)) && isscalar(t), obj.AlwaysOnTop = logical(t); end
            catch
            end
            try
                k = getpref('MABR','OrderSortKeys',{});
                d = getpref('MABR','OrderSortDirs',{});
                if iscellstr(k) && iscellstr(d) && numel(k) == numel(d) ...
                        && numel(k) <= 2 && all(ismember(d,{'ascend','descend'})) %#ok<ISCLSTR>
                    obj.SortKeys = reshape(k,1,[]); obj.SortDirs = reshape(d,1,[]);
                end
            catch
            end
        end

        function saveTablePrefs(obj)
            % The sort keys, written only when the user changes them.
            try
                setpref('MABR','OrderSortKeys',obj.SortKeys);
                setpref('MABR','OrderSortDirs',obj.SortDirs);
            catch
            end
        end

        % --- The condition table ------------------------------------------------
        function ids = layoutIds(obj)
            % The table's columns, left to right.
            if isempty(obj.ParamNames)
                ids = {'On','Condition','Upcoming'};
            else
                ids = [{'On'} obj.ParamNames {'Upcoming'}];
            end
        end

        function h = baseHeader(obj,id)
            j = find(strcmp(obj.ParamNames,id),1);
            if isempty(j) || isempty(obj.ParamUnits{j})
                h = id;
            else
                h = sprintf('%s (%s)',id,obj.ParamUnits{j});
            end
        end

        function buildTable(obj)
            % The table is made once and only ever updated in place: deleting
            % a uitable while it is handling an event of its own is an error.
            obj.Table = uitable(obj.Side,'RowName',{}, ...
                'CellEditCallback',@(~,e) obj.onToggle(e), ...
                'Tooltip',obj.TableTip);
            obj.Table.Layout.Row = 2;
            % A click picks the whole row: the reference Disable above / below
            % measure from. Where a release cannot select by row, the table
            % still works and those two buttons simply stay greyed.
            try
                obj.Table.SelectionType = 'row';
                obj.Table.SelectionChangedFcn = @(~,~) obj.onSelect();
            catch
            end
            obj.syncColumns(obj.layoutIds());
        end

        function syncColumns(obj,ids)
            % Give the table the columns for this bank.
            t = obj.Table;
            w = cell(1,numel(ids));
            names = cell(1,numel(ids));
            for k = 1:numel(ids)
                names{k} = obj.baseHeader(ids{k});
                switch ids{k}
                    case 'On',       w{k} = 34;
                    case 'Upcoming', w{k} = 70;
                    otherwise,       w{k} = 'auto';
                end
            end
            t.Data = cell(0,numel(ids));
            t.ColumnName = names;
            t.ColumnEditable = strcmp(ids,'On');
            t.ColumnWidth = w;
            % The lock (syncSwitches) writes this through put(); what put
            % remembers is now this, not what it wrote for the old columns.
            obj.Shown.edit_ColumnEditable = t.ColumnEditable;
            obj.ColIds = ids;
            obj.TableKey = [];
            obj.OrderKey = {};
            obj.syncSortControls();
        end

        function buildSortControls(obj)
            % Sort by / then by: a column and a direction each.
            g = uigridlayout(obj.Side,[2 3]);
            g.Layout.Row = 1;
            g.ColumnWidth = {50,'1x',96}; g.RowHeight = {22,22};
            g.RowSpacing = 4; g.ColumnSpacing = 4; g.Padding = [0 0 0 0];
            g.BackgroundColor = obj.PanelColor;
            lbl = {'Sort by','then by'};
            tip = {'The column the rows are sorted by.', ...
                   'The column that orders rows the first one ties on.'};
            for k = 1:2
                l = uilabel(g,'Text',lbl{k},'HorizontalAlignment','right');
                l.Layout.Row = k; l.Layout.Column = 1;
                d = uidropdown(g,'Items',{'(plot order)'},'ItemsData',{''}, ...
                    'Tag',sprintf('OrderSortKey%d',k), ...
                    'ValueChangedFcn',@(~,~) obj.onSortChanged(),'Tooltip',tip{k});
                d.Layout.Row = k; d.Layout.Column = 2;
                e = uidropdown(g,'Items',{'Ascending','Descending'}, ...
                    'ItemsData',{'ascend','descend'},'Tag',sprintf('OrderSortDir%d',k), ...
                    'ValueChangedFcn',@(~,~) obj.onSortChanged());
                e.Layout.Row = k; e.Layout.Column = 3;
                obj.Ctrl.sortKey(k) = d;
                obj.Ctrl.sortDir(k) = e;
            end
        end

        function [keys,dirs] = effectiveSort(obj)
            % The saved sort, less any key this bank has no column for.
            keys = {}; dirs = {};
            for k = 1:numel(obj.SortKeys)
                if any(strcmp(obj.SortKeys{k},obj.ColIds)) && ~any(strcmp(obj.SortKeys{k},keys))
                    keys{end+1} = obj.SortKeys{k}; %#ok<AGROW>
                    dirs{end+1} = obj.SortDirs{k}; %#ok<AGROW>
                end
            end
        end

        function syncSortControls(obj)
            % Show the sort in force: the columns on offer, the keys, the
            % directions. The second key is off until the first is chosen.
            if ~isfield(obj.Ctrl,'sortKey'), return; end
            [keys,dirs] = obj.effectiveSort();
            ids = obj.ColIds;
            for k = 1:2
                offer = ids;
                if k == 2 && ~isempty(keys), offer = ids(~strcmp(ids,keys{1})); end
                names = cellfun(@(c) obj.baseHeader(c),offer,'UniformOutput',false);
                d = obj.Ctrl.sortKey(k);
                d.Items = [{'(plot order)'} names];
                d.ItemsData = [{''} offer];
                if numel(keys) >= k
                    d.Value = keys{k};
                    obj.Ctrl.sortDir(k).Value = dirs{k};
                else
                    d.Value = '';
                end
                obj.Ctrl.sortDir(k).Enable = matlab.lang.OnOffSwitchState(numel(keys) >= k);
            end
            obj.Ctrl.sortKey(2).Enable = matlab.lang.OnOffSwitchState(~isempty(keys));
        end

        function onSortChanged(obj)
            % A sort control was changed by the user.
            k1 = obj.Ctrl.sortKey(1).Value;
            k2 = obj.Ctrl.sortKey(2).Value;
            keys = {}; dirs = {};
            if ~isempty(k1)
                keys = {k1}; dirs = {obj.Ctrl.sortDir(1).Value};
                if ~isempty(k2) && ~strcmp(k2,k1)
                    keys{2} = k2; dirs{2} = obj.Ctrl.sortDir(2).Value;
                end
            end
            obj.SortKeys = keys; obj.SortDirs = dirs;
            obj.saveTablePrefs();
            obj.syncSortControls();
            obj.TableKey = [];
            obj.refresh(true);
        end

        function rows = sortedRows(obj,keys,dirs,on,up)
            % The conditions in the order the sort in force puts them: the
            % order of the table's rows AND of the y axis's. on and up are
            % per stimulus index (switched on; presentations still to come).
            % sortrows is stable, so ties stay in the bank's parameter order.
            rows = obj.BaseRows;
            n = numel(rows);
            if isempty(keys) || n < 2, return; end
            K = zeros(n,numel(keys));
            for j = 1:numel(keys)
                switch keys{j}
                    case 'On',       K(:,j) = double(on(rows(:)));
                    case 'Upcoming', K(:,j) = up(rows(:));
                    case 'Condition'
                        [~,~,r] = unique(obj.AllLabels(rows(:)));
                        K(:,j) = r;
                    otherwise
                        K(:,j) = obj.AllVals(rows(:),strcmp(obj.ParamNames,keys{j}));
                end
            end
            [~,ord] = sortrows(K,1:numel(keys),dirs);
            rows = rows(reshape(ord,1,[]));
        end

        function savePrefs(obj)
            % Written only from the control strip -- a user choosing a view,
            % never a script setting a property -- as mabr.ui.LivePlot does.
            try
                setpref('MABR','OrderSpan',obj.Span);
                setpref('MABR','OrderWindow',obj.WindowLength);
            catch
            end
        end

        % --- Controller events -------------------------------------------------
        function onState(obj,e)
            prev = obj.StateNow;
            s    = e.State;
            obj.setStateNow(s);
            if s == mabr.ui.ProgState.PrepBlock
                obj.beginRun();
            elseif s == mabr.ui.ProgState.Acquire && prev ~= mabr.ui.ProgState.Acquire
                if prev ~= mabr.ui.ProgState.PrepBlock, obj.beginRun(); end
                obj.RunT0 = tic;
                obj.RunT1 = NaN;
                obj.RunPaused = 0;
            end
            if prev == mabr.ui.ProgState.Acquire && s ~= mabr.ui.ProgState.Acquire ...
                    && obj.RunT0 ~= 0
                obj.RunT1 = obj.runClock();   % freeze a stimulation-only estimate
            end
            obj.syncClock();
            obj.refresh(true);
        end

        function onMetrics(obj,e)
            info = e.Info;
            if isstruct(info) && isfield(info,'numSweeps')
                obj.LiveSweeps = info.numSweeps;
            end
            if obj.LiveRun == 0
                sch = obj.plan();
                if ~isempty(sch), obj.LiveRun = sch.current(); end
            end
            obj.refresh(false);
        end

        function onEngineState(obj,e)
            paused = e.State == mabr.acq.State.Paused;
            if paused == obj.Paused, return; end
            if paused
                obj.Paused  = true;
                obj.PauseT0 = tic;
            else
                if obj.PauseT0 ~= 0, obj.RunPaused = obj.RunPaused + toc(obj.PauseT0); end
                obj.Paused  = false;
                obj.PauseT0 = uint64(0);
            end
            obj.refresh(true);
        end

        function beginRun(obj)
            obj.LiveSweeps = 0;
            obj.RunT0      = uint64(0);
            obj.RunT1      = NaN;
            obj.RunPaused  = 0;
            sch = obj.plan();
            if isempty(sch), obj.LiveRun = 0; else, obj.LiveRun = sch.current(); end
        end

        function resetPosition(obj)
            obj.LiveRun    = 0;
            obj.LiveSweeps = 0;
            obj.RunT0      = uint64(0);
            obj.RunT1      = NaN;
            obj.RunPaused  = 0;
            obj.Paused     = false;
            obj.PauseT0    = uint64(0);
            obj.setStateNow(mabr.ui.ProgState.Idle);
            obj.stopClock();
        end

        function setStateNow(obj,s)
            obj.StateNow = s;
            [~,txt] = mabr.ui.ProgState.appearance(s);
            obj.Phase = struct( ...
                'run',      s == mabr.ui.ProgState.Acquire || s == mabr.ui.ProgState.PrepBlock, ...
                'acquire',  s == mabr.ui.ProgState.Acquire, ...
                'complete', s == mabr.ui.ProgState.SchedComplete, ...
                'rest',     mabr.ui.ProgState.isTerminal(s), ...
                'txt',      txt);
        end

        function stopListening(obj)
            if ~isempty(obj.Listeners), delete(obj.Listeners); end
            obj.Listeners = [];
            obj.stopClock();
        end

        % --- The stimulation-only clock -------------------------------------------
        function syncClock(obj)
            % Ticks only while a stimulation-only run streams: every other
            % mode has the controller's aux tick to ride.
            sch = obj.plan();
            if obj.Phase.acquire && ~isempty(sch) && sch.StimulationOnly
                obj.startClock();
            else
                obj.stopClock();
            end
        end

        function startClock(obj)
            if ~obj.isvalidView(), return; end
            if isempty(obj.ClockTimer) || ~isvalid(obj.ClockTimer)
                obj.ClockTimer = timer('Name','MABR_OrderClock', ...
                    'Period',obj.ClockPeriod,'StartDelay',obj.ClockPeriod, ...
                    'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                    'ObjectVisibility','off','TimerFcn',@(~,~) obj.onClock());
            end
            if strcmp(obj.ClockTimer.Running,'off'), start(obj.ClockTimer); end
        end

        function stopClock(obj,remove)
            if nargin < 2, remove = false; end
            t = obj.ClockTimer;
            if isempty(t) || ~isvalid(t), obj.ClockTimer = []; return; end
            if strcmp(t.Running,'on'), stop(t); end
            if remove, delete(t); obj.ClockTimer = []; end
        end

        function onClock(obj)
            try
                if ~obj.isvalidView(), obj.stopClock(); return; end
                obj.refresh(false);
            catch me
                mabr.log.vprintf(2,'Presentation order clock tick failed: %s',me.message);
            end
        end

        function t = runClock(obj)
            % Seconds the current run has streamed, pauses excluded.
            t = toc(obj.RunT0) - obj.RunPaused;
            if obj.Paused && obj.PauseT0 ~= 0, t = t - toc(obj.PauseT0); end
            t = max(0,t);
        end

        % --- The plan -----------------------------------------------------------
        function [sch,bank] = plan(obj)
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

        function syncPlan(obj,sch,bank)
            % Rebuild the sequence, the rows, and the static lines -- only
            % when the plan is a different one or has changed shape.
            if isempty(sch) || isempty(bank)
                if ~isequal(obj.PlanKey,0)
                    obj.clearPlan();
                    obj.PlanKey = 0;
                end
                return
            end
            lens = cellfun('prodofsize',sch.Runs);
            key  = [sch.NumRuns, sum(lens), bank.numStimuli];
            if isequal(key,obj.PlanKey) && ~isempty(obj.PlanSched) ...
                    && isvalid(obj.PlanSched) && obj.PlanSched == sch
                return
            end
            obj.PlanKey   = key;
            obj.PlanSched = sch;

            n   = bank.numStimuli;
            seq = zeros(1,sum(lens));
            at  = 0;
            single = true;
            for r = 1:sch.NumRuns
                s = reshape(double(sch.Runs{r}),1,[]);
                seq(at+1:at+numel(s)) = s;
                at = at + numel(s);
                single = single && numel(unique(s)) <= 1;
            end
            obj.Sequence  = seq;
            obj.RunStarts = [0 cumsum(lens)];
            obj.Blocked   = single;

            valid   = seq >= 1 & seq <= n;
            present = unique(seq(valid));
            % A condition switched off whose runs have all been dropped keeps
            % its row, so it can still be seen -- and switched back on for a
            % make-up or repeat run.
            skipped = sch.Skipped;
            if ~isempty(skipped)
                present = union(present,find(skipped(1:min(n,end)) > 0));
            end
            present = reshape(present,1,[]);
            [labels,vals,pnames,punits] = stimulusLabels(bank);
            if ~isempty(vals) && ~isempty(present)
                [~,ix] = sortrows([vals(present,:) present(:)]);
                present = present(ix);
            end
            obj.BaseRows   = present;
            obj.AllLabels  = labels;
            obj.AllVals    = vals;
            obj.ParamNames = pnames;
            obj.ParamUnits = punits;
            obj.PlanVersion = obj.PlanVersion + 1;
            obj.OrderKey   = {};
            % The columns follow the parameters, and the sort keys follow
            % the columns, so this comes before the rows are put in order.
            ids = obj.layoutIds();
            if ~isequal(ids,obj.ColIds), obj.syncColumns(ids); end
            % The bank's own order for now; paint puts them in the order
            % the table is sorted into (syncOrder) as soon as it has the
            % counts that order may depend on.
            obj.setRows(present);
            obj.drawPlan();
        end

        function setRows(obj,rows)
            % Make rows the order of the y axis and of the table, top to
            % bottom, and work out where every presentation sits in it.
            n = numel(obj.AllLabels);
            obj.Rows      = rows;
            obj.RowLabels = obj.AllLabels(rows);
            obj.RowVals   = obj.AllVals(rows,:);
            obj.RowOf     = zeros(1,n);
            obj.RowOf(rows) = 1:numel(rows);
            seq = obj.Sequence;
            valid = seq >= 1 & seq <= n;
            y = nan(1,numel(seq));
            y(valid) = obj.RowOf(seq(valid));
            obj.YSeq = y;
        end

        function syncOrder(obj,on,up)
            % Put the rows in the order the table's sort gives, redrawing
            % the plot to match when that moved them. The order is held until
            % the keys, the plan or -- sorting on Upcoming -- the counts
            % change: ticking a box leaves every row where it is.
            [skeys,sdirs] = obj.effectiveSort();
            ups = [];
            if any(strcmp(skeys,'Upcoming')), ups = up(obj.BaseRows); end
            okey = {skeys,sdirs,obj.PlanVersion,ups,obj.ColIds};
            if isequal(okey,obj.OrderKey), return; end
            obj.OrderKey = okey;
            rows = obj.sortedRows(skeys,sdirs,on,up);
            if isequal(rows,obj.Rows), return; end
            obj.setRows(rows);
            obj.drawRows();
        end

        function clearPlan(obj)
            obj.Sequence  = [];
            obj.RunStarts = 0;
            obj.Rows      = [];
            obj.RowLabels = {};
            obj.BaseRows  = []; obj.AllLabels = {}; obj.AllVals = zeros(0,0);
            obj.ParamNames = {}; obj.ParamUnits = {}; obj.RowVals = zeros(0,0);
            obj.OrderKey = {}; obj.SelStim = [];
            obj.PlanVersion = obj.PlanVersion + 1;
            obj.RowOf     = [];
            obj.YSeq      = [];
            obj.Blocked   = false;
            obj.PlanSched = [];
            obj.Shown     = struct();
            if ~obj.isvalidView(), return; end
            set([obj.PendingLine obj.DoneLine obj.OffLine obj.CursorLine ...
                 obj.ActiveMarker obj.RunLines],'XData',NaN,'YData',NaN);
            obj.Table.Data = cell(0,numel(obj.ColIds));
            removeStyle(obj.Table);
            obj.OffKey = []; obj.TableKey = []; obj.RowKey = [];
            obj.ActiveBand.Visible = 'off';
            obj.Axes.YTick = [];
            obj.Axes.YTickLabel = {};
            obj.Axes.XLim = [0 1];
            obj.Axes.YLim = [0 1];
            obj.Done = 0; obj.Current = 0; obj.ActiveStimulus = 0;
        end

        function drawPlan(obj)
            % The parts of the drawing that follow from the plan alone.
            obj.Shown = struct();    % every cached write is now stale
            N  = numel(obj.Sequence);
            nR = numel(obj.Rows);
            ax = obj.Axes;
            obj.PendingLine.XData = 1:N;
            ax.YLim  = [0.5 max(nR,1)+0.5];
            obj.drawRows();

            S = obj.RunStarts;
            b = S(2:end-1) + 0.5;
            if isempty(b) || numel(b) > obj.MaxRunLines
                obj.RunLines.XData = NaN; obj.RunLines.YData = NaN;
            else
                y = [0.5; nR+0.5; NaN];
                obj.RunLines.XData = reshape([b; b; nan(1,numel(b))],1,[]);
                obj.RunLines.YData = reshape(repmat(y,1,numel(b)),1,[]);
            end
            obj.ActiveBand.XData = [0.5 N+0.5 N+0.5 0.5];
            obj.CursorLine.YData = [0.5 nR+0.5];
            obj.ActiveStimulus = -1;                  % force a repaint
        end

        function drawRows(obj)
            % The parts of the drawing that follow from the ORDER of the rows
            % -- the labels on the y axis and the height of every presentation
            % -- and so everything painted from them is stale.
            ax = obj.Axes;
            ax.YTick = 1:numel(obj.Rows);
            ax.YTickLabel = cellfun(@texEscape,obj.RowLabels,'UniformOutput',false);
            obj.PendingLine.YData = obj.YSeq;
            obj.Done = -1; obj.Current = -1;
            obj.OffKey = []; obj.TableKey = []; obj.RowKey = [];
        end

        function [done,cur] = position(obj,sch)
            % done: presentations made, across the plan. cur: the one to
            % highlight (0 = none).
            S  = obj.RunStarts;
            N  = numel(obj.Sequence);
            nr = numel(S) - 1;
            done = 0; cur = 0;
            obj.Estimated = false;
            r = sch.current();
            if obj.Phase.complete || r < 1 || r > nr
                % Complete, or walked off the end of the plan.
                if obj.Phase.complete || sum(sch.RunCounts) > 0, done = N; end
                return
            end
            done = S(r);                     % every run before this one
            L = obj.LiveRun;
            if L >= 1 && L <= nr && L <= r
                len = S(L+1) - S(L);
                if sch.StimulationOnly
                    k = obj.estimatePlayed(sch,len);
                    obj.Estimated = obj.Phase.run || k > 0;
                else
                    k = min(obj.LiveSweeps,len);
                end
                done = max(done,S(L) + k);
            end
            if obj.Phase.run
                cur = max(done,S(r) + 1);    % a run's first, before a sweep is in
                cur = min(cur,S(r+1));
            elseif ~obj.Phase.rest
                cur = done;                  % finalizing: the last one presented
            end
        end

        function k = estimatePlayed(obj,sch,len)
            % A stimulation-only run's presentations begun so far, from its
            % clock -- onset k at SilencePad + (k-1)*MeanISI.
            k = 0;
            if obj.RunT0 == 0, return; end
            if isnan(obj.RunT1), t = obj.runClock(); else, t = obj.RunT1; end
            t   = t - sch.SilencePad;
            isi = sch.MeanISI;
            if t < 0 || ~(isi > 0), return; end
            k = min(len,floor(t/isi) + 1);
        end

        % --- Painting --------------------------------------------------------
        function paint(obj,done,cur,sch)
            N = numel(obj.Sequence);
            if N == 0
                obj.put('now',obj.NowLabel,'Text','No plan to show');
                obj.put('info',obj.InfoLabel,'Text', ...
                    'The order appears once a schedule is built (Start or Preview).');
                obj.syncButtons(sch);
                return
            end

            % The order comes first: it decides the height of every mark.
            on = sch.isEnabled();
            up = sch.upcomingCounts();
            obj.syncOrder(on,up);

            if done ~= obj.Done
                if done > 0
                    obj.DoneLine.XData = 1:done;
                    obj.DoneLine.YData = obj.YSeq(1:done);
                else
                    obj.DoneLine.XData = NaN; obj.DoneLine.YData = NaN;
                end
                obj.Done = done;
            end

            obj.paintOff(sch,on);

            stim = 0;
            if cur >= 1 && cur <= N, stim = obj.Sequence(cur); else, cur = 0; end
            if cur ~= obj.Current
                if cur > 0
                    y = obj.YSeq(cur);
                    obj.ActiveMarker.XData = cur; obj.ActiveMarker.YData = y;
                    obj.CursorLine.XData   = [cur cur];
                else
                    obj.ActiveMarker.XData = NaN; obj.ActiveMarker.YData = NaN;
                    obj.CursorLine.XData   = [NaN NaN];
                end
                obj.Current = cur;
            end
            obj.ActiveStimulus = stim;
            rowOn = on(obj.Rows);
            obj.paintRows(stim,rowOn);
            obj.paintTable(stim,rowOn,up);
            obj.syncButtons(sch);

            obj.applySpan(done,cur);
            obj.syncControls();
            obj.paintHeader(done,cur,stim,rowOn);
        end

        function paintOff(obj,sch,on)
            % Upcoming presentations of conditions switched off: crosses
            % instead of dots. Redrawn only when the mask or the run moves.
            r   = sch.current();
            key = [r, double(on)];
            if isequal(key,obj.OffKey), return; end
            obj.OffKey = key;
            S   = obj.RunStarts;
            seq = obj.Sequence;
            off = false(1,numel(seq));
            if r >= 1 && r < numel(S) && ~all(on)
                later = S(r+1)+1:numel(seq);
                s = seq(later);
                ok = s >= 1 & s <= numel(on);
                off(later(ok)) = ~on(s(ok));
            end
            y = obj.YSeq;
            yo = nan(size(y)); yo(off) = y(off);
            y(off) = NaN;
            obj.PendingLine.YData = y;
            x = 1:numel(seq);
            if any(off)
                obj.OffLine.XData = x(off); obj.OffLine.YData = yo(off);
            else
                obj.OffLine.XData = NaN; obj.OffLine.YData = NaN;
            end
        end

        function paintRows(obj,stim,rowOn)
            % The row labels (active in bold amber, off greyed) and the band
            % along the active row.
            row = 0;
            if stim >= 1 && stim <= numel(obj.RowOf), row = obj.RowOf(stim); end
            key = [row, double(rowOn)];
            if isequal(key,obj.RowKey), return; end
            obj.RowKey = key;
            % A switched-off condition is greyed, with no word added to its
            % label -- the colour says it, as the table's greyed row does.
            lbl = cellfun(@texEscape,obj.RowLabels,'UniformOutput',false);
            c = obj.OffInk;
            for i = find(~rowOn)
                lbl{i} = sprintf('\\color[rgb]{%.3f,%.3f,%.3f}%s',c(1),c(2),c(3),lbl{i});
            end
            if row > 0
                obj.ActiveBand.YData   = [row-0.5 row-0.5 row+0.5 row+0.5];
                obj.ActiveBand.Visible = 'on';
                % Bold marks the condition now playing; amber is its colour
                % unless it has been switched off for the runs to come, when
                % the grey says that and the band and marker still say "now".
                c = obj.ActiveInk;
                if ~rowOn(row), c = obj.OffInk; end
                lbl{row} = sprintf('\\bf\\color[rgb]{%.3f,%.3f,%.3f}%s',c(1),c(2),c(3), ...
                    texEscape(obj.RowLabels{row}));
            else
                obj.ActiveBand.Visible = 'off';
            end
            obj.Axes.YTickLabel = lbl;
        end

        function paintTable(obj,stim,rowOn,up)
            % One row per condition, one column per parameter, in the order
            % of Rows -- the y axis's order. Rewritten only when a count, a
            % box, the active row, or the order changes -- a run boundary or
            % a toggle, not every tick.
            ids = obj.ColIds;
            upR = zeros(1,numel(obj.Rows));
            ok  = obj.Rows <= numel(up);
            upR(ok) = up(obj.Rows(ok));
            row = 0;
            if stim >= 1 && stim <= numel(obj.RowOf), row = obj.RowOf(stim); end

            key = [row, double(rowOn), upR, obj.Rows, obj.PlanVersion];
            if isequal(key,obj.TableKey), return; end
            obj.TableKey = key;
            t = obj.Table;
            D = cell(numel(obj.Rows),numel(ids));
            for c = 1:numel(ids)
                switch ids{c}
                    case 'On',        col = num2cell(rowOn);
                    case 'Upcoming',  col = num2cell(upR);
                    case 'Condition', col = obj.RowLabels;
                    otherwise
                        v = obj.RowVals(:,strcmp(obj.ParamNames,ids{c}));
                        col = num2cell(v);
                        col(isnan(v)) = {''};
                end
                D(:,c) = col(:);
            end
            t.Data = D;
            removeStyle(t);
            if any(~rowOn)
                addStyle(t,uistyle('FontColor',obj.OffInk),'row',find(~rowOn));
            end
            if row > 0
                addStyle(t,uistyle('BackgroundColor',obj.ActiveRowBg, ...
                    'FontWeight','bold'),'row',row);
            end
            obj.restoreSelection();
        end

        % --- The buttons ----------------------------------------------------------
        function [stim,name] = nextStimulus(obj,sch)
            % The condition the next run to start will present first -- the
            % one Skip next switches off -- and its name. 0 when there is none
            % a switch could still reach: nothing follows the run in progress,
            % or everything that does is already off.
            stim = 0; name = '';
            if isempty(sch) || sch.current() < 1, return; end
            n  = sch.Set.numStimuli;
            on = sch.isEnabled();
            for r = sch.current()+1:sch.NumRuns
                s = double(sch.Runs{r});
                s = s(s >= 1 & s <= n);
                s = s(on(s));
                if ~isempty(s), stim = s(1); break; end
            end
            if stim > 0
                k = find(obj.Rows == stim,1);
                if isempty(k), name = sprintf('stimulus %d',stim); else, name = obj.RowLabels{k}; end
            end
        end

        function tf = switchesLocked(obj,sch)
            % True while switching a condition off would have nothing to
            % reach. A switch applies to runs not yet started; a plan that
            % mixes conditions inside a run plays as one, so while its last
            % run is being presented no run waits. A plan whose runs each
            % present one condition is never locked. The controls that only
            % make sense with a run to reach -- the On boxes and the four
            % buttons -- go quiet; the sort, the span and the selection are
            % views and do not.
            tf = false;
            if nargin < 2, sch = obj.plan(); end
            if isempty(sch) || isempty(obj.Sequence) || obj.Blocked || ~obj.Phase.run
                return
            end
            tf = sch.current() >= sch.NumRuns;
        end

        function skipNext(obj)
            % Leave the next condition in the queue out of the runs not yet
            % started: the same switch as clearing its On box, without having
            % to find it in the table. Pressed again, it takes the one after.
            sch = obj.plan();
            if obj.switchesLocked(sch), return; end
            [stim,name] = obj.nextStimulus(sch);
            if stim == 0, return; end
            try
                sch.setEnabled(stim,false);
            catch me
                mabr.log.vprintf(0,1,'Could not skip %s: %s',name,me.message);
            end
            obj.TableKey = [];
            obj.refresh(true);
        end

        function disableSide(obj,side)
            % Switch off every condition above ('above') or below ('below')
            % the selected row, counted in the order the table SHOWS them --
            % its sort, not the plot's. With more than one row selected the
            % reach starts from the outer edge of the selection.
            sch = obj.plan();
            sel = obj.selectedTableRows();
            if isempty(sch) || isempty(sel) || obj.switchesLocked(sch), return; end
            if strcmp(side,'above')
                stim = obj.Rows(1:min(sel)-1);
            else
                stim = obj.Rows(max(sel)+1:end);
            end
            if isempty(stim), return; end
            try
                sch.setEnabled(stim,false);
            catch me
                mabr.log.vprintf(0,1,'Could not switch off the conditions %s the selected row: %s', ...
                    side,me.message);
            end
            obj.TableKey = [];
            obj.refresh(true);
        end

        function rows = selectedTableRows(obj)
            % The table rows picked, ascending, as the table shows them. The
            % table is asked rather than a copy kept: it is what the user sees.
            rows = [];
            t = obj.Table;
            if isempty(t) || ~isgraphics(t), return; end
            try
                sel = t.Selection;
                if strcmp(char(t.SelectionType),'cell'), sel = sel(:,1); end
                rows = unique(reshape(sel,1,[]));
            catch
            end
            rows = rows(rows >= 1 & rows <= numel(obj.Rows));
        end

        function onSelect(obj)
            % The user picked a row. Remember the CONDITION, not the row
            % number: new Data in the table drops its selection (see
            % restoreSelection) and a re-sort moves the row.
            rows = obj.selectedTableRows();
            obj.SelStim = reshape(obj.Rows(rows),1,[]);
            obj.syncButtons([]);
        end

        function restoreSelection(obj)
            % Put the picked conditions back after the table was rewritten,
            % wherever the sort now has them; one that has left the plan is
            % forgotten.
            if isempty(obj.SelStim), return; end
            rows = find(ismember(obj.Rows,obj.SelStim));
            obj.SelStim = reshape(obj.Rows(rows),1,[]);
            try
                obj.Table.Selection = reshape(rows,1,[]);   % 1-by-N, or the table refuses it
            catch
            end
        end

        function syncButtons(obj,sch)
            % Which of the buttons have anything to do. Skip next names the
            % condition it would take, so the tooltip is the preview.
            if ~isfield(obj.Ctrl,'skipNext') || ~isvalid(obj.Ctrl.skipNext), return; end
            if nargin < 2 || isempty(sch), sch = obj.plan(); end
            have = ~isempty(sch) && ~isempty(obj.Rows);
            lock = have && obj.switchesLocked(sch);
            tf = @(v) matlab.lang.OnOffSwitchState(v);

            stim = 0; name = '';
            if have && ~lock, [stim,name] = obj.nextStimulus(sch); end
            obj.put('skipEnable',obj.Ctrl.skipNext,'Enable',tf(stim > 0));
            if lock
                tip = obj.LockText;
            elseif stim > 0
                tip = sprintf(['Skip next: leave %s out of the runs not yet started. ' ...
                               'It is the next condition in the queue.'],name);
            else
                tip = 'Nothing to skip: no run is waiting after the one in progress.';
            end
            obj.put('skipTip',obj.Ctrl.skipNext,'Tooltip',tip);

            canAbove = false; canBelow = false; anyOff = false;
            if have && ~lock
                on    = sch.isEnabled();
                rowOn = on(obj.Rows);
                anyOff = ~all(on);
                sel = obj.selectedTableRows();
                if ~isempty(sel)
                    canAbove = any(rowOn(1:min(sel)-1));
                    canBelow = any(rowOn(max(sel)+1:end));
                end
            end
            obj.put('aboveEnable',obj.Ctrl.disAbove,'Enable',tf(canAbove));
            obj.put('belowEnable',obj.Ctrl.disBelow,'Enable',tf(canBelow));
            obj.put('enableAll',obj.Ctrl.enableAll,'Enable',tf(anyOff));
            obj.syncSwitches(lock);
        end

        function syncSwitches(obj,lock)
            % The rest of what the lock reaches: the table's On boxes, and
            % the words that say why nothing happens when they are pressed.
            % (Skip next's tooltip is syncButtons's: it also names the
            % condition it would take, so it changes with the queue.)
            if ~isfield(obj.Ctrl,'note') || ~isvalid(obj.Ctrl.note), return; end
            obj.put('edit',obj.Table,'ColumnEditable',strcmp(obj.ColIds,'On') & ~lock);
            if lock
                obj.put('note',obj.Ctrl.note,'Text',obj.LockText);
                obj.put('tableTip',obj.Table,'Tooltip',obj.LockText);
                obj.put('aboveTip',obj.Ctrl.disAbove,'Tooltip',obj.LockText);
                obj.put('belowTip',obj.Ctrl.disBelow,'Tooltip',obj.LockText);
                obj.put('allTip',obj.Ctrl.enableAll,'Tooltip',obj.LockText);
            else
                obj.put('note',obj.Ctrl.note,'Text',obj.NoteText);
                obj.put('tableTip',obj.Table,'Tooltip',obj.TableTip);
                obj.put('aboveTip',obj.Ctrl.disAbove,'Tooltip',obj.AboveTip);
                obj.put('belowTip',obj.Ctrl.disBelow,'Tooltip',obj.BelowTip);
                obj.put('allTip',obj.Ctrl.enableAll,'Tooltip',obj.AllTip);
            end
        end

        function onToggle(obj,e)
            % A box in the On column was clicked.
            sch = obj.plan();
            row = e.Indices(1);
            if isempty(sch) || e.Indices(2) ~= find(strcmp(obj.ColIds,'On'),1) ...
                    || row > numel(obj.Rows) || obj.switchesLocked(sch)
                % Not a box that can be ticked now: put the table back as the
                % plan holds it, whatever the edit left in the cell.
                obj.TableKey = [];
                obj.refresh(true);
                return
            end
            stimIdx = obj.Rows(row);
            try
                sch.setEnabled(stimIdx,logical(e.NewData));
            catch me
                mabr.log.vprintf(0,1,'Could not change condition %d: %s', ...
                    stimIdx,me.message);
            end
            obj.TableKey = [];     % the table must show what the plan now holds
            obj.refresh(true);
        end

        function enableAll(obj)
            sch = obj.plan();
            if isempty(sch) || obj.switchesLocked(sch), return; end
            off = find(~sch.isEnabled());
            if ~isempty(off), sch.setEnabled(off,true); end
            obj.refresh(true);
        end

        function applySpan(obj,done,cur)
            N = numel(obj.Sequence);
            S = obj.RunStarts;
            anchor = cur;
            if anchor == 0, anchor = max(1,min(N,done)); end
            switch obj.resolvedSpan()
                case 'plan'
                    lim = [0.5 N+0.5];
                case 'run'
                    r = find(S < anchor,1,'last');
                    if isempty(r) || r >= numel(S), r = 1; end
                    lim = [S(r)+0.5 S(r+1)+0.5];
                otherwise   % window
                    w  = min(obj.WindowLength,N);
                    lo = anchor - floor(w/4) - 0.5;
                    lo = max(0.5,min(lo,N+0.5-w));
                    lim = [lo lo+w];
            end
            obj.put('xlim',obj.Axes,'XLim',lim);
            shown = lim(2) - lim(1);
            if shown <= obj.MaxJoined, ls = '-'; else, ls = 'none'; end
            if shown <= obj.MaxOpen, mk = 'o'; ms = 5; else, mk = '.'; ms = 8; end
            obj.put('ls', [obj.PendingLine obj.DoneLine],'LineStyle',ls);
            if shown <= obj.MaxOpen, ms2 = 7; else, ms2 = 5; end
            obj.put('msOff',obj.OffLine,'MarkerSize',ms2);
            obj.put('mk', [obj.PendingLine obj.DoneLine],'Marker',mk);
            obj.put('ms', [obj.PendingLine obj.DoneLine],'MarkerSize',ms);
        end

        function paintHeader(obj,done,cur,stim,rowOn)
            N  = numel(obj.Sequence);
            S  = obj.RunStarts;
            nr = numel(S) - 1;
            est = ''; if obj.Estimated, est = '~'; end
            if cur > 0 && stim >= 1 && stim <= numel(obj.RowOf) && obj.RowOf(stim) > 0
                head = ['Now: ' obj.RowLabels{obj.RowOf(stim)}];
            elseif done >= N && N > 0
                head = 'Plan complete';
            else
                head = 'Nothing being presented';
            end
            if cur > 0
                r = find(S < cur,1,'last');
                where = sprintf('Run %d of %d  ·  presentation %s%s of %s', ...
                    r,nr,est,groupDigits(cur),groupDigits(N));
            else
                where = sprintf('%d run%s  ·  %s of %s presented', ...
                    nr,plural(nr),groupDigits(done),groupDigits(N));
            end
            state = obj.Phase.txt;
            if obj.Paused && obj.Phase.run, state = 'Paused'; end
            if isempty(obj.Controller), state = ''; end
            bits = {where};
            if ~isempty(state), bits{end+1} = state; end
            nOff = sum(~rowOn);
            if nOff > 0, bits{end+1} = sprintf('%d condition%s off',nOff,plural(nOff)); end
            if obj.Estimated, bits{end+1} = 'estimated from the clock (stimulation only)'; end
            obj.put('now', obj.NowLabel, 'Text',head);
            obj.put('info',obj.InfoLabel,'Text',strjoin(bits,'  ·  '));
        end

        function put(obj,key,h,prop,value)
            % Set a property only when it changes, judged against what this
            % window last wrote rather than by reading it back.
            k = [key '_' prop];
            if isfield(obj.Shown,k) && isequal(obj.Shown.(k),value), return; end
            set(h,prop,value);
            obj.Shown.(k) = value;
        end
    end
end

% ======================= local helpers ================================
function eng = engineOf(controller)
eng = [];
try
    if isprop(controller,'Engine') && ~isempty(controller.Engine) && isvalid(controller.Engine)
        eng = controller.Engine;
    end
catch
end
end

function [labels,vals,names,units] = stimulusLabels(bank)
% Each stimulus named by the parameters the bank varies ('8 kHz, 30 dB'),
% its ID where there are none; vals are those parameters, one row per
% stimulus, for sorting the rows, and names/units say which column is which.
n = bank.numStimuli;
labels = cell(1,n);
vals   = zeros(n,0);
names = {}; units = {}; ids = cell(1,n);
try
    T     = bank.paramTable();
    keep  = T.Varying;
    names = T.Names(keep);
    units = T.Units(keep);
    vals  = T.Values(:,keep);
    ids   = T.IDs;
    names = reshape(cellstr(names),1,[]);
    units = reshape(cellstr(units),1,[]);
catch
    names = {}; units = {}; vals = zeros(n,0);
    for i = 1:n, ids{i} = sprintf('stimulus %d',i); end
end
for i = 1:n
    parts = cell(1,numel(names));
    for j = 1:numel(names)
        v = vals(i,j);
        if isnan(v), parts{j} = '';
        elseif isempty(units{j}), parts{j} = sprintf('%s %g',names{j},v);
        else, parts{j} = sprintf('%g %s',v,units{j});
        end
    end
    parts = parts(~cellfun(@isempty,parts));
    if isempty(parts), labels{i} = ids{i}; else, labels{i} = strjoin(parts,', '); end
end
end

function s = texEscape(s)
% Tick labels use the TeX interpreter (for the bold active row), so the
% characters TeX would act on in an ID are escaped.
s = regexprep(s,'([\\_^{}])','\\$1');
end

function s = plural(n)
if n == 1, s = ''; else, s = 's'; end
end

function s = groupDigits(n)
s = sprintf('%d',round(abs(n)));
L = numel(s);
if L > 3
    k = mod(L-1,3) + 1;
    g = reshape(s(k+1:end),3,[]);
    s = [s(1:k) reshape([repmat(',',1,size(g,2)); g],1,[])];
end
if n < 0, s = ['-' s]; end
end
