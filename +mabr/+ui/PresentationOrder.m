classdef PresentationOrder < handle
% mabr.ui.PresentationOrder  The order the plan presents its conditions in.
%
%   mabr.ui.ProgressMonitor answers "how much of each condition is done";
%   this window answers "in what ORDER are they played, and which one is on
%   now". One axes: presentation number along x -- counted across the whole
%   plan, run after run, exactly as mabr.stim.Schedule.Runs holds them -- and
%   one row per condition up the y axis, so every presentation is a mark in
%   its condition's row. The rows are the conditions the plan presents,
%   sorted by the parameters the bank varies (from
%   mabr.stim.StimulusSet.paramTable) and named by them ('8 kHz, 30 dB',
%   the convention mabr.ui.LivePlot and the progress monitor use), so a
%   Frequency x Level grid reads top to bottom as the grid it is.
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
%   dot, and its row label is greyed. Enable all switches everything back on.
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
    end

    properties
        Span         (1,:) char = 'auto'
        WindowLength (1,1) double {mustBePositive,mustBeInteger} = 60
        MinInterval  (1,1) double {mustBeNonnegative} = 0.2
        Title        (1,:) char = 'MABR Presentation Order'
    end

    properties (SetAccess = private)
        Figure
        Axes
        Controller                 % mabr.ui.AcqController followed, if any
        Schedule                   % plan shown when no controller is attached
        Stimuli
        Sequence  (1,:) double = []   % stimulus index of every presentation, plan order
        RunStarts (1,:) double = 0    % presentations before each run; run r is RunStarts(r)+1:RunStarts(r+1)
        Rows      (1,:) double = []   % stimulus index of each y row, top to bottom
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
        OffKey    (1,:) double = []   % what the switched-off drawing was made for
        TableKey  (1,:) double = []   % what the table was last filled for
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
    end

    methods (Access = private)
        % --- Construction -----------------------------------------------------
        function build(obj)
            g = uigridlayout(obj.Figure,[3 2]);
            g.RowHeight   = {44,'1x',30};
            g.ColumnWidth = {'1x',250};
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

            side = uigridlayout(g,[3 1]);
            side.Layout.Row = 2; side.Layout.Column = 2;
            side.RowHeight = {'1x',44,26};
            side.RowSpacing = 4; side.Padding = [0 0 0 0];
            side.BackgroundColor = obj.PanelColor;
            obj.Table = uitable(side,'ColumnName',{'On','Condition','Upcoming'}, ...
                'ColumnEditable',[true false false], ...
                'ColumnWidth',{34,'auto',70},'RowName',{}, ...
                'Data',cell(0,3), ...
                'CellEditCallback',@(~,e) obj.onToggle(e), ...
                'Tooltip',['Clear On to leave a condition out of the runs not yet ' ...
                           'started; tick it to put it back.']);
            uilabel(side,'WordWrap','on','FontSize',11,'FontColor',obj.MutedColor, ...
                'Text',['Changes apply from the next run: the run in progress ' ...
                        'plays as it was rendered.']);
            obj.Ctrl.enableAll = uibutton(side,'Text','Enable all', ...
                'ButtonPushedFcn',@(~,~) obj.enableAll(), ...
                'Tooltip','Switch every condition back on');

            c = uigridlayout(g,[1 5]);
            c.Layout.Row = 3; c.Layout.Column = [1 2];
            c.ColumnWidth = {40,130,50,80,'1x'};
            c.Padding = [4 0 4 0];
            c.BackgroundColor = obj.PanelColor;
            uilabel(c,'Text','Show','HorizontalAlignment','right');
            obj.Ctrl.span = uidropdown(c,'Items',obj.SpanLabels,'ItemsData',obj.Spans, ...
                'Value',obj.Span,'ValueChangedFcn',@(s,~) obj.onControl('Span',s.Value), ...
                'Tooltip',['How much of the plan to show: the presentations around ' ...
                           'the current one, its run, or the whole plan. Auto shows ' ...
                           'the whole plan when every run presents one condition.']);
            uilabel(c,'Text','Width','HorizontalAlignment','right');
            obj.Ctrl.width = uispinner(c,'Limits',[1 Inf],'Step',10, ...
                'RoundFractionalValues','on','Value',obj.WindowLength, ...
                'ValueChangedFcn',@(s,~) obj.onControl('WindowLength',s.Value), ...
                'Tooltip','Presentations shown around the current one');
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
            [labels,vals] = stimulusLabels(bank);
            if ~isempty(vals) && ~isempty(present)
                [~,ix] = sortrows([vals(present,:) present(:)]);
                present = present(ix);
            end
            obj.Rows      = present;
            obj.RowLabels = labels(present);
            obj.RowOf     = zeros(1,n);
            obj.RowOf(present) = 1:numel(present);
            y = nan(1,numel(seq));
            y(valid) = obj.RowOf(seq(valid));
            obj.YSeq = y;

            obj.drawPlan();
        end

        function clearPlan(obj)
            obj.Sequence  = [];
            obj.RunStarts = 0;
            obj.Rows      = [];
            obj.RowLabels = {};
            obj.RowOf     = [];
            obj.YSeq      = [];
            obj.Blocked   = false;
            obj.PlanSched = [];
            obj.Shown     = struct();
            if ~obj.isvalidView(), return; end
            set([obj.PendingLine obj.DoneLine obj.OffLine obj.CursorLine ...
                 obj.ActiveMarker obj.RunLines],'XData',NaN,'YData',NaN);
            obj.Table.Data = cell(0,3);
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
            obj.PendingLine.YData = obj.YSeq;
            ax.YLim  = [0.5 max(nR,1)+0.5];
            ax.YTick = 1:nR;
            ax.YTickLabel = cellfun(@texEscape,obj.RowLabels,'UniformOutput',false);

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
            obj.Done = -1; obj.Current = -1; obj.ActiveStimulus = -1;   % force a repaint
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
                return
            end

            if done ~= obj.Done
                if done > 0
                    obj.DoneLine.XData = 1:done;
                    obj.DoneLine.YData = obj.YSeq(1:done);
                else
                    obj.DoneLine.XData = NaN; obj.DoneLine.YData = NaN;
                end
                obj.Done = done;
            end

            on = sch.isEnabled();
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
            obj.paintTable(sch,stim,rowOn);

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
            lbl = cellfun(@texEscape,obj.RowLabels,'UniformOutput',false);
            c = obj.OffInk;
            for i = find(~rowOn)
                lbl{i} = sprintf('\\color[rgb]{%.3f,%.3f,%.3f}%s (off)',c(1),c(2),c(3),lbl{i});
            end
            if row > 0
                obj.ActiveBand.YData   = [row-0.5 row-0.5 row+0.5 row+0.5];
                obj.ActiveBand.Visible = 'on';
                c = obj.ActiveInk;
                lbl{row} = sprintf('\\bf\\color[rgb]{%.3f,%.3f,%.3f}%s',c(1),c(2),c(3), ...
                    texEscape(obj.RowLabels{row}));
                if ~rowOn(row), lbl{row} = [lbl{row} ' (off)']; end
            else
                obj.ActiveBand.Visible = 'off';
            end
            obj.Axes.YTickLabel = lbl;
        end

        function paintTable(obj,sch,stim,rowOn)
            % One row per condition, in the plot's row order. Rewritten only
            % when a count, a box, or the active row changes -- a run
            % boundary or a toggle, not every tick.
            up  = sch.upcomingCounts();
            upR = zeros(1,numel(obj.Rows));
            ok  = obj.Rows <= numel(up);
            upR(ok) = up(obj.Rows(ok));
            row = 0;
            if stim >= 1 && stim <= numel(obj.RowOf), row = obj.RowOf(stim); end
            key = [row, double(rowOn), upR];
            if isequal(key,obj.TableKey), return; end
            obj.TableKey = key;
            t = obj.Table;
            t.Data = [num2cell(rowOn(:)), obj.RowLabels(:), num2cell(upR(:))];
            removeStyle(t);
            if any(~rowOn)
                addStyle(t,uistyle('FontColor',obj.OffInk),'row',find(~rowOn));
            end
            if row > 0
                addStyle(t,uistyle('BackgroundColor',obj.ActiveRowBg, ...
                    'FontWeight','bold'),'row',row);
            end
            obj.put('enableAll',obj.Ctrl.enableAll,'Enable', ...
                matlab.lang.OnOffSwitchState(~all(sch.isEnabled())));
        end

        function onToggle(obj,e)
            % A box in the On column was clicked.
            sch = obj.plan();
            row = e.Indices(1);
            if isempty(sch) || e.Indices(2) ~= 1 || row > numel(obj.Rows)
                obj.TableKey = [];
                obj.refresh(true);
                return
            end
            try
                sch.setEnabled(obj.Rows(row),logical(e.NewData));
            catch me
                mabr.log.vprintf(0,1,'Could not change condition %d: %s', ...
                    obj.Rows(row),me.message);
            end
            obj.TableKey = [];     % the table must show what the plan now holds
            obj.refresh(true);
        end

        function enableAll(obj)
            sch = obj.plan();
            if isempty(sch), return; end
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

function [labels,vals] = stimulusLabels(bank)
% Each stimulus named by the parameters the bank varies ('8 kHz, 30 dB'),
% its ID where there are none; vals are those parameters, one row per
% stimulus, for sorting the rows.
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
catch
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
