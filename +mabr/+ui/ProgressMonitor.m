classdef ProgressMonitor < handle
% mabr.ui.ProgressMonitor  How far the schedule has got, at a glance.
%
%   The main window says what is happening NOW (state, sweeps, r) and the live
%   view says what the response looks like. Neither answers the question an
%   operator actually asks across a two-hour session: how much of the plan is
%   done, and which conditions are still short. This window answers only that,
%   in one of three views:
%
%     'simple'   NO plot at all -- the lamp, the header beside it, and the
%                control strip. That header already says how far along the
%                session is, what the rig is doing, and how much longer,
%                which is the whole of what the question needs; a bar
%                underneath it was a second drawing of the same number. The
%                window sizes itself DOWN to those two strips, so this is
%                what to leave in a corner or on a second monitor when the
%                answer wanted is "how long until I can go home". Asking for
%                either plot view grows the window back to make room for it.
%     'bars'     one bar per stimulus, or per value of any one stimulus
%                parameter (GroupBy). A 5-level x 4-frequency bank is 20 bars
%                by stimulus, 5 by Level, 4 by Frequency -- the same progress,
%                asked three ways. A bar being presented right now is amber, a
%                finished one green.
%     'heatmap'  the classic ABR grid: one parameter across (frequency), one
%                up (level), each cell shaded by how complete that condition
%                is, with its counts or percentage written in, and the cells
%                being presented right now outlined in the same amber. The
%                one view that shows a HOLE in the design -- a condition the
%                plan does not contain, hatched -- rather than a number that
%                happens to be small.
%
%   Labels ('counts' / 'percent' / 'none') decides what the numbers on the
%   bars, in the heat-map cells, and in the header read as: 1536/6144, or 25%.
%   'none' leaves the shading to speak for itself, which is the right setting
%   for a window glanced at from across the rig -- the header keeps a
%   percentage there, since one number is not what 'none' is about.
%
%   The header
%   ----------
%   Beside the big number, three lines, each answering one question:
%
%     what      the rig's state, which run of how many (and whether it is an
%               artifact make-up or a repeat the user asked for), and
%               'stimulation only' when nothing is being recorded. It reads
%               'Paused' while the operator has paused the rig: ProgState has
%               no such state -- a paused run is still Acquire -- so it is
%               read off the acquisition engine's own StateChanged instead.
%     this run  during a run, the condition being presented, named by the
%               parameters the bank varies ('8 kHz, 30 dB', never a constant
%               one), or how many are intermixed; how far through the run it
%               is; and how many sweeps the artifact preview has rejected.
%               Between runs, how many conditions are complete and the size of
%               the plan.
%     when      elapsed, the time left, and the clock time that comes to
%               ('done ≈ 14:32'); once the schedule rests, how long it took
%               and when it finished.
%
%   The time left starts from the plan -- every presentation left times the
%   ISI, plus each run left's silence bracket and longest stimulus -- and once
%   ten seconds of acquisition have been watched it is scaled by how long the
%   plan's work has ACTUALLY been taking, which is what picks up the per-run
%   preparation and finalization the plan cannot know about. Paused time is
%   left out of that ratio (a pause delays the finish by exactly its own
%   length; it does not mean the rest will go slower), and so is everything
%   before this window started watching: a window opened in the middle of a
%   session measures from the next thing it sees rather than pretending the
%   session began when it was opened, and shows no elapsed time, since it
%   does not know it.
%
%   The window's own title carries the percentage too, so a minimized monitor
%   still reports from the taskbar.
%
%   Counting
%   --------
%   The denominator is every presentation the plan currently holds -- summed
%   over mabr.stim.Schedule.Runs, so artifact make-up and user-requested
%   repeat runs enlarge it as they are appended. Progress therefore steps
%   BACK slightly when a make-up run lands, which is the truth: the work grew.
%
%   The numerator is Schedule.RunCounts (presentations actually recovered,
%   written by the controller at finalization) plus, while a run is under
%   way, that run's sweeps so far paired against Schedule.runSequence -- the
%   same pairing mabr.ui.AcqController.finalize_run de-interleaves by, so the
%   bar moving during a run and the count left behind after it agree. That
%   in-flight part is kept until the run is CREDITED -- until RunCounts
%   actually grows -- rather than dropped the moment the run stops streaming:
%   with the DSP worker, finalization is asynchronous, and dropping it at
%   BlockComplete made every bar fall back by a whole run until the worker's
%   reply landed.
%
%   In stimulation-only mode nothing is recorded, so there are no sweeps to
%   count. The run's presentations are ESTIMATED from the clock instead --
%   the worker streams at the device's pace, so onset k plays SilencePad +
%   (k-1)*ISI after the run starts, pauses excluded -- and marked '~'
%   wherever they are shown (Estimated says so to a script). The estimate
%   gives way to the presented counts the controller records at the end of
%   the run.
%
%   Cost
%   ----
%   Almost every refresh arrives from inside one of the controller's
%   callbacks, so the window is built to cost that callback as little as it
%   can:
%
%     * It rides the controller's AUXILIARY tick (MetricsUpdated, ~2 Hz --
%       deliberately not the ~20 Hz live tick, which belongs to the live
%       trace; see mabr.ui.AcqController.AuxPeriod) and repaints at most every
%       MinInterval seconds (default 0.2), and then only if the tallies moved
%       or a second has gone by for the clock. The aux tick is slower than
%       MinInterval, so that throttle does not bind there; it stays as this
%       window's own guarantee against a faster caller. State changes force a
%       repaint; a burst of BlockReady (one per stimulus of an intermixed
%       run) does not -- the state change that always follows finalization
%       repaints once.
%     * It never calls drawnow. From inside a timer callback a drawnow
%       flushes EVERY open figure, the live view included, and services the
%       event queue, so the live tick could run nested inside this window's
%       repaint. MATLAB flushes these changes itself as the callback returns.
%     * A property is written only when its value changes -- a uifigure
%       component sends every assignment to the browser that draws it, same
%       value or not -- judged against what this window last wrote rather
%       than by reading it back, since even a read goes through the
%       component. The per-bar and per-cell numbers are diffed the same way,
%       so a refresh mid-run rewrites the few that moved. The state is held
%       as plain flags and the finish time as seconds, not re-derived from an
%       enumeration and a datetime on every repaint.
%     * What follows from the run itself (which stimuli it presents, what to
%       call it) is worked out once per run, and its presentations are
%       tallied incrementally, so a refresh does not get dearer as an
%       intermixed run gets longer.
%     * Nothing is created per refresh: the bars are two patches whose
%       vertices are rewritten, the heat map one image whose CData is, the
%       outlines and hatching one line each, and the labels a fixed array of
%       text objects whose Strings are. Layout is rebuilt only when the view,
%       the grouping, or the plan itself changes.
%
%   One timer is the window's own: a 1 Hz clock that runs only while a
%   schedule is in flight and repaints only when nothing else has in the last
%   second. The aux tick fires only while sweeps are being counted, so
%   without it the elapsed time and the estimate froze between runs -- and for
%   the whole of a stimulation-only session, which is the one mode in which
%   mabr.ui.App opens this window by itself.
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
%   Closing its own window deletes the monitor, and with it the listeners on
%   the controller and the clock. AlwaysOnTop keeps the window above the
%   others (uifigure WindowStyle 'alwaysontop', the same mechanism
%   mabr.ui.App's pin uses) and is remembered per rig in the MABR pref group.
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
        PausedColor = [0.890 0.439 0.153];   % the lamp while the rig is paused
        InkColor    = [0.243 0.271 0.318];
        MutedColor  = [0.478 0.514 0.565];
        HatchColor  = [0.741 0.765 0.796];
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
        % The header clock's period (s), and how much acquisition has to have
        % been watched before the measured pace is trusted over the plan's.
        ClockPeriod    = 1;
        CalibrateAfter = 10;
        % The window with no plot in it: 8 padding + 62 header + 6 spacing +
        % 1 collapsed plot row + 6 spacing + 66 control strip + 8 padding.
        % Stated rather than measured because uigridlayout offers no way to
        % ask what a 'fit' would come to before it is laid out.
        CompactHeight     = 157;
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
        Paused    (1,1) logical = false  % the rig is paused (mabr.acq.State.Paused)
        Estimated (1,1) logical = false  % the run's count is estimated from the clock

        % The drawn objects. Public to READ for the same reason
        % mabr.ui.LivePlot's axes are: a script (and the verification suite)
        % has to be able to ask what the window is actually showing, which is
        % not the same question as what it was told.
        TrackPatch                  % full-width bar tracks (one patch, all bars)
        FillPatch                   % the filled part (one patch, all bars)
        ValueText  = gobjects(1,0)  % one per bar, empty when too many to label
        HeatImage                   % the heat map itself
        HeatText   = gobjects(1,0)  % one per cell, empty when too dense
        ActiveOutline               % heat-map cells being presented (one line)
        HoleHatch                   % heat-map cells the plan lacks (one line)
        MsgText                     % the "nothing to show yet" line
        ColorBar
    end

    properties (Access = private)
        Root
        Lamp
        PctLabel
        StateLabel
        DetailLabel
        TimeLabel
        Ctrl = struct()
        LayoutKey  (1,:) char = ''
        Map        = struct()       % group/cell mapping the current layout was built for
        Drawn      = struct()       % what the current layout's objects are showing
        Params     = struct('bank',[],'names',{{}},'values',[],'units',{{}},'ids',{{}},'labels',{{}})
        ParamsVersion (1,1) double = 0
        PlanKey    (1,2) double = [-1 -1]
        PlanTotals (1,:) double = []
        PlanOverhead (1,1) double = 0     % s a run costs beyond its presentations
        RunCache   = struct('key',[],'run',0,'seq',zeros(1,0),'active',false(1,0), ...
                            'label','','kind','','k',0,'cum',zeros(1,0))  % the current run
        LastDraw   (1,1) uint64 = uint64(0)
        LastClock  (1,1) uint64 = uint64(0)
        LastCounts  = []
        LastTargets = []
        LastActive  = []
        StateNow   (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        % StateNow as plain flags, with its lamp colour and label: derived
        % once per state change (setStateNow), because an enumeration
        % comparison costs tens of microseconds and a refresh asked the same
        % handful of questions of it several times over.
        Phase = struct('run',false,'acquire',false,'finalize',false,'advance',false, ...
                       'complete',false,'rest',true,'rgb',[0.6 0.6 0.6],'txt','Idle')
        Shown = struct()                  % what the header was last given (see put)
        LiveSweeps   (1,1) double = 0
        LiveRejected (1,1) double = 0
        LiveKnown    (1,1) logical = true   % is the current run's count known?
        InFlight     (1,1) double = 0       % the current run's count, as tallied
        RunBase      (1,1) double = 0       % sum(RunCounts) when this run began
        RunT0      (1,1) uint64 = uint64(0) % when the run started streaming
        RunT1      (1,1) double = NaN       % its active seconds, once it stopped
        RunPaused  (1,1) double = 0         % s paused within the run
        RunHeld    (1,1) double = NaN       % the run's clock, held while paused
        PauseT0    (1,1) uint64 = uint64(0)
        T0         (1,1) uint64 = uint64(0) % when this window saw the session start
        Frozen     (1,1) double = NaN       % elapsed, once the schedule rests
        FinishedText (1,:) char = ''        % clock time it came to rest, as shown
        % The wall clock as a tic, taken once: seconds since midnight 0000 at
        % WallTic. The finish time is then double arithmetic rather than a
        % datetime round trip on every repaint.
        WallRef    (1,1) double = 0
        WallTic    (1,1) uint64 = uint64(0)
        FinishKey  (1,1) double = NaN       % the minute FinishText was formatted for
        FinishText (1,:) char = ''
        JoinedLate (1,1) logical = false    % opened after the session began
        CalPending (1,1) logical = false    % take a pace baseline at the next refresh
        CalT0      (1,1) uint64 = uint64(0)
        CalPaused  (1,1) double = 0
        CalStop    (1,1) double = NaN       % active seconds, once the schedule rests
        CalBaseDone (1,1) double = 0
        CalBaseRuns (1,1) double = 0
        ClockTimer
        Listeners
        Building   (1,1) logical = false
        PlotShown  (1,1) logical = true    % is the plot row currently open
        PlotHeight (1,1) double = 500      % height the plot views were left at
    end

    methods
        function obj = ProgressMonitor(parent)
            obj.restorePlotHeight();
            obj.WallRef = 86400*datenum(datetime('now'));
            obj.WallTic = tic;
            if nargin >= 1 && ~isempty(parent) && isgraphics(parent)
                obj.Container = parent;
            else
                % Opens at whatever the DEFAULT view needs, which is the
                % compact one -- a window that opened tall and immediately
                % shrank would read as a glitch.
                obj.Figure = uifigure('Name',obj.Title,'Tag','MABR_PROGRESS', ...
                    'Position',[100 100 560 obj.CompactHeight],'Color',obj.PanelColor);
                % A monitor whose window has gone is nothing but listeners
                % on the controller and a clock, so closing the window takes
                % the monitor with it. A host that wants to do something first
                % (mabr.ui.App remembers the position) replaces this.
                obj.Figure.CloseRequestFcn = @(~,~) delete(obj);
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
            obj.stopClock(true);
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

        function tf = clockRunning(obj)
            % Whether the header clock is ticking -- it should be exactly while
            % a followed schedule is in flight.
            tf = ~isempty(obj.ClockTimer) && isvalid(obj.ClockTimer) ...
                 && strcmp(obj.ClockTimer.Running,'on');
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
            % metrics, every block it finalizes, and whether its engine is
            % paused. Only one controller is followed at a time -- calling this
            % again re-points the listeners rather than stacking a second set,
            % so re-opening the window (or rebuilding the controller) cannot
            % double-count anything.
            %
            % The controller's Schedule is read on every refresh rather than
            % held: setStimuli REPLACES it, so a stored handle would quietly
            % go stale the next time a bank is loaded.
            obj.stopListening();
            obj.Controller = [];
            obj.resetProgress();
            if nargin < 2 || isempty(controller) || ~isvalid(controller)
                obj.newPlan();
                return
            end
            obj.Controller = controller;
            obj.setStateNow(controller.State);
            L = [ ...
                addlistener(controller,'StateChanged',   @(~,e) obj.onState(e)); ...
                addlistener(controller,'MetricsUpdated', @(~,e) obj.onMetrics(e)); ...
                addlistener(controller,'BlockReady',     @(~,~) obj.onBlockReady()); ...
                addlistener(controller,'ScheduleComplete',@(~,~) obj.onComplete())];
            eng = engineOf(controller);
            if ~isempty(eng)
                L = [L; addlistener(eng,'StateChanged',@(~,e) obj.onEngineState(e))];
                if eng.State == mabr.acq.State.Paused
                    obj.Paused = true; obj.PauseT0 = tic;
                end
            end
            obj.Listeners = L;

            if ~obj.Phase.rest
                % Opened while a schedule is already running. Only a run
                % still being prepared with nothing yet recorded is the
                % START of one; anything later has been going for a while
                % this window cannot know, and the current run's count is
                % unknown until the next live update says it.
                [sch,~] = obj.plan();
                fresh = obj.StateNow == mabr.ui.ProgState.PrepBlock && runTotal(sch) == 0;
                obj.startSession(~fresh);
                obj.LiveKnown = fresh;
                obj.startClock();
            end
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

        function [pct,state,time,detail] = headerText(obj)
            % What the header is actually saying, read back -- the counterpart
            % of Counts/Targets for the top of the window, and how the
            % verification suite checks that Labels reaches it. Outputs in the
            % order they were added, not the order they are drawn: pct is the
            % big number, state the first line, detail the second (this run,
            % or the plan), time the third.
            pct = ''; state = ''; time = ''; detail = '';
            if ~obj.isvalidView(), return; end
            pct    = obj.PctLabel.Text;
            state  = obj.StateLabel.Text;
            time   = obj.TimeLabel.Text;
            detail = obj.DetailLabel.Text;
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
            % force skips the rate limit (a state change, a setting the user
            % just moved); everything else is throttled to MinInterval and
            % then dropped entirely if the numbers are the same as last time
            % and the clock has nothing new to say. Dropping a live tick costs
            % nothing: the state change that ends every run forces a repaint,
            % so the window cannot settle on a stale number.
            %
            % No drawnow, deliberately -- see Cost in the class help.
            if nargin < 2, force = false; end
            if ~obj.isvalidView(), return; end
            if ~force && obj.LastDraw ~= 0 && toc(obj.LastDraw) < obj.MinInterval
                return
            end

            [done,target,active,sch] = obj.tally();
            if obj.CalPending && obj.LiveKnown && ~isempty(sch)
                % The pace baseline: from here on, the time taken is compared
                % with the plan's work done SINCE here.
                obj.CalT0       = tic;
                obj.CalPaused   = 0;
                obj.CalBaseDone = sum(done);
                obj.CalBaseRuns = obj.runsDone(sch);
                obj.CalPending  = false;
            end
            moved   = ~isequal(done,obj.LastCounts) || ~isequal(target,obj.LastTargets) ...
                      || ~isequal(active,obj.LastActive);
            ticking = obj.LastClock == 0 || toc(obj.LastClock) >= 0.9*obj.ClockPeriod;
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
                obj.Shown.name  = obj.Title;                           %#ok<MCSUP>
                % ...and the progress it carries goes back on the end of it.
                if ~obj.Building, obj.refresh(true); end              %#ok<MCSUP>
            end
        end
    end

    % ======================= internals ====================================
    methods (Access = private)
        % --- Construction -----------------------------------------------------
        function build(obj)
            g = uigridlayout(obj.Container,[3 1]);
            g.RowHeight    = {62,'1x',66};
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
            % The part that has to be readable from across the room: the big
            % number, and beside it what the rig is doing, what this run is,
            % and how much longer -- in falling order of weight, so the eye
            % finds the state first and the arithmetic last.
            p  = uipanel(g,'BorderType','none','BackgroundColor',obj.PanelColor);
            hg = uigridlayout(p,[3 3]);
            hg.RowHeight       = {22,18,18};
            hg.ColumnWidth     = {24,'fit','1x'};
            hg.Padding         = [4 2 4 2];
            hg.RowSpacing      = 0;
            hg.ColumnSpacing   = 10;
            hg.BackgroundColor = obj.PanelColor;

            obj.Lamp = uilamp(hg,'Color',[0.6 0.6 0.6]);
            obj.Lamp.Layout.Row = 1; obj.Lamp.Layout.Column = 1;

            obj.PctLabel = uilabel(hg,'Text','—','FontSize',24,'FontWeight','bold', ...
                'FontColor',obj.InkColor,'VerticalAlignment','center');
            obj.PctLabel.Layout.Row = [1 3]; obj.PctLabel.Layout.Column = 2;

            obj.StateLabel = uilabel(hg,'Text','Idle','FontSize',12,'FontWeight','bold', ...
                'FontColor',obj.InkColor,'VerticalAlignment','center');
            obj.StateLabel.Layout.Row = 1; obj.StateLabel.Layout.Column = 3;

            obj.DetailLabel = uilabel(hg,'Text','','FontSize',11, ...
                'FontColor',obj.InkColor,'VerticalAlignment','center');
            obj.DetailLabel.Layout.Row = 2; obj.DetailLabel.Layout.Column = 3;

            obj.TimeLabel = uilabel(hg,'Text','','FontSize',11, ...
                'FontColor',obj.MutedColor,'VerticalAlignment','center');
            obj.TimeLabel.Layout.Row = 3; obj.TimeLabel.Layout.Column = 3;
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
            prev = obj.StateNow;
            s    = e.State;
            obj.setStateNow(s);
            if s == mabr.ui.ProgState.PrepBlock
                % The next run's sweeps have not started arriving; anything
                % left in the counter belongs to the run just finalized, which
                % is already in Schedule.RunCounts.
                obj.beginRun();
            elseif s == mabr.ui.ProgState.Acquire && prev ~= mabr.ui.ProgState.Acquire
                if prev ~= mabr.ui.ProgState.PrepBlock, obj.beginRun(); end
                obj.RunT0 = tic;
            end
            if prev == mabr.ui.ProgState.Acquire && s ~= mabr.ui.ProgState.Acquire ...
                    && obj.RunT0 ~= 0
                % Stopped streaming: freeze the run's clock, so a
                % stimulation-only estimate holds its last value until the
                % run is credited rather than falling to zero.
                obj.RunT1 = obj.runClock();
            end
            if obj.Phase.rest
                obj.restSession();
            else
                if obj.T0 == 0 || mabr.ui.ProgState.isTerminal(prev)
                    obj.startSession(false);   % a new schedule starts the clock
                end
                obj.startClock();
            end
            obj.refresh(true);
        end

        function onMetrics(obj,e)
            % The high-rate path into this window, and it does nothing but
            % store numbers: refresh() decides whether they are worth a
            % repaint yet.
            info = e.Info;
            if isstruct(info)
                if isfield(info,'numSweeps'),    obj.LiveSweeps   = info.numSweeps;    end
                if isfield(info,'numArtifacts'), obj.LiveRejected = info.numArtifacts; end
            end
            obj.LiveKnown = true;
            obj.refresh(false);
        end

        function onBlockReady(obj)
            % The run's presentations are in Schedule.RunCounts as of now
            % (assemble_blocks credits them before announcing), so the live
            % counter is given up. NOT forced: an intermixed run raises one of
            % these per stimulus in a single burst, and the state change that
            % always follows finalization repaints once for all of them.
            obj.LiveSweeps = 0;
            obj.refresh(false);
        end

        function onComplete(obj)
            obj.restSession();
            obj.refresh(true);
        end

        function onEngineState(obj,e)
            % Pause is a rig-level state ProgState does not have: a paused run
            % is still Acquire. The engine says so directly.
            paused = e.State == mabr.acq.State.Paused;
            if paused == obj.Paused, return; end
            if paused
                % Hold the run's clock where it stopped rather than keep
                % subtracting a growing pause from a growing total: two
                % readings of it must agree exactly while nothing plays.
                if obj.RunT0 ~= 0, obj.RunHeld = obj.runClock(); end
                obj.Paused  = true;
                obj.PauseT0 = tic;
            else
                obj.endPause();
            end
            obj.refresh(true);
        end

        function stopListening(obj)
            if ~isempty(obj.Listeners), delete(obj.Listeners); end
            obj.Listeners = [];
            obj.stopClock();
        end

        function resetProgress(obj)
            obj.LiveSweeps   = 0;
            obj.LiveRejected = 0;
            obj.LiveKnown    = true;
            obj.InFlight     = 0;
            obj.Estimated    = false;
            obj.RunT0        = uint64(0);
            obj.RunT1        = NaN;
            obj.RunPaused    = 0;
            obj.RunHeld      = NaN;
            obj.Paused       = false;
            obj.PauseT0      = uint64(0);
            obj.T0           = uint64(0);
            obj.Frozen       = NaN;
            obj.FinishedText = '';
            obj.JoinedLate   = false;
            obj.CalPending   = false;
            obj.CalT0        = uint64(0);
            obj.CalPaused    = 0;
            obj.CalStop      = NaN;
            obj.setStateNow(mabr.ui.ProgState.Idle);
            obj.stopClock();
        end

        function beginRun(obj)
            % A run is starting: nothing of it has been counted, and what the
            % plan has credited so far is the mark its own credit will move.
            obj.LiveSweeps   = 0;
            obj.LiveRejected = 0;
            obj.LiveKnown    = true;
            obj.RunT0        = uint64(0);
            obj.RunT1        = NaN;
            obj.RunPaused    = 0;
            [sch,~] = obj.plan();
            obj.RunBase = runTotal(sch);
        end

        function startSession(obj,late)
            obj.T0         = tic;
            obj.Frozen       = NaN;
            obj.FinishedText = '';
            obj.JoinedLate   = late;
            obj.CalPending = true;
            obj.CalT0      = uint64(0);
            obj.CalStop    = NaN;
        end

        function restSession(obj)
            % The schedule has come to rest (complete, halted, or failed).
            obj.endPause();
            if obj.T0 ~= 0 && isnan(obj.Frozen)
                obj.Frozen       = toc(obj.T0);
                obj.FinishedText = obj.clockTime(obj.wallNow());
                if obj.CalT0 ~= 0, obj.CalStop = toc(obj.CalT0) - obj.CalPaused; end
            end
            obj.stopClock();
        end

        function endPause(obj)
            if ~obj.Paused, return; end
            d = 0;
            if obj.PauseT0 ~= 0, d = toc(obj.PauseT0); end
            obj.RunPaused = obj.RunPaused + d;
            obj.CalPaused = obj.CalPaused + d;
            obj.Paused    = false;
            obj.PauseT0   = uint64(0);
            obj.RunHeld   = NaN;
        end

        function setStateNow(obj,s)
            % The one place StateNow changes, so Phase cannot disagree with it.
            obj.StateNow = s;
            [rgb,txt] = mabr.ui.ProgState.appearance(s);
            obj.Phase = struct( ...
                'run',      s == mabr.ui.ProgState.Acquire || s == mabr.ui.ProgState.PrepBlock, ...
                'acquire',  s == mabr.ui.ProgState.Acquire, ...
                'finalize', s == mabr.ui.ProgState.BlockComplete, ...
                'advance',  s == mabr.ui.ProgState.AdvanceBlock, ...
                'complete', s == mabr.ui.ProgState.SchedComplete, ...
                'rest',     mabr.ui.ProgState.isTerminal(s), ...
                'rgb',      rgb, ...
                'txt',      txt);
        end

        function t = wallNow(obj)
            % Local wall-clock time, in seconds since midnight of year 0.
            t = obj.WallRef + toc(obj.WallTic);
        end

        function s = finishText(obj,eta)
            % The clock time a finish ETA seconds away comes to. Formatted only
            % when the minute it names changes -- about once a minute, however
            % often the header repaints.
            t = obj.wallNow() + eta;
            key = floor(t/60);
            if key ~= obj.FinishKey
                obj.FinishKey  = key;
                obj.FinishText = obj.clockTime(t);
            end
            s = obj.FinishText;
        end

        function s = clockTime(obj,t)
            % 14:32 today, 'tomorrow 01:10' past midnight -- a finish read as a
            % bare clock time would be read as this afternoon.
            s = sprintf('%02d:%02d',mod(floor(t/3600),24),mod(floor(t/60),60));
            days = floor(t/86400) - floor(obj.wallNow()/86400);
            if days == 1
                s = ['tomorrow ' s];
            elseif days > 1
                s = sprintf('%s (+%d days)',s,days);
            end
        end

        function newPlan(obj)
            % A different plan invalidates the layout, the group mapping, the
            % parameter table and every cached tally alike.
            obj.LayoutKey     = '';
            obj.PlanKey       = [-1 -1];
            obj.Params        = emptyParams();
            obj.ParamsVersion = obj.ParamsVersion + 1;
            obj.RunCache      = emptyRun();
            obj.LastCounts    = [];
            obj.LastTargets   = [];
            obj.LastActive    = [];
            [sch,~] = obj.plan();
            obj.RunBase = runTotal(sch);
            if ~obj.isvalidView(), return; end
            obj.syncControls();
            obj.refresh(true);
        end

        % --- The header clock ---------------------------------------------------
        function startClock(obj)
            if isempty(obj.Controller) || ~obj.isvalidView(), return; end
            if isempty(obj.ClockTimer) || ~isvalid(obj.ClockTimer)
                obj.ClockTimer = timer('Name','MABR_ProgressClock', ...
                    'Period',obj.ClockPeriod,'StartDelay',obj.ClockPeriod, ...
                    'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                    'ObjectVisibility','off', ...
                    'TimerFcn',@(~,~) obj.onClock());
            end
            if strcmp(obj.ClockTimer.Running,'off'), start(obj.ClockTimer); end
        end

        function stopClock(obj,remove)
            if nargin < 2, remove = false; end
            t = obj.ClockTimer;
            if isempty(t) || ~isvalid(t), obj.ClockTimer = []; return; end
            if strcmp(t.Running,'on'), stop(t); end
            if remove
                delete(t);
                obj.ClockTimer = [];
            end
        end

        function onClock(obj)
            % Nothing to add when a controller event painted the header within
            % the last second -- the usual case while sweeps are arriving. What
            % is left is between runs, and all of a stimulation-only session.
            try
                if ~obj.isvalidView(), obj.stopClock(); return; end
                if obj.LastClock ~= 0 && toc(obj.LastClock) < 0.9*obj.ClockPeriod, return; end
                obj.refresh(false);
            catch me
                % A failing clock must not take the controller's callbacks
                % with it; the next state change repaints regardless.
                mabr.log.vprintf(2,'Progress clock tick failed: %s',me.message);
            end
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
            obj.InFlight  = 0;
            obj.Estimated = false;
            if isempty(sch) || isempty(bank), return; end

            n = bank.numStimuli;
            if n == 0, return; end

            target = obj.scheduledTotals(sch,n);
            done   = zeros(1,n);
            active = false(1,n);

            d = sch.RunCounts;
            if numel(d) > n, d = d(1:n); end
            done(1:numel(d)) = d;

            R = obj.currentRun(sch,n);
            if isempty(R.seq), return; end
            if obj.inRun(), active = R.active; end
            if obj.countsInFlight(sch)
                % The k-th recorded onset is the k-th presentation the
                % schedule ordered -- exactly the pairing finalize_run
                % de-interleaves by, so what this bar shows mid-run is what
                % the run leaves behind when it finalizes.
                if sch.StimulationOnly
                    k = obj.estimatePlayed(sch,numel(R.seq));
                    obj.Estimated = true;
                else
                    k = min(obj.LiveSweeps,numel(R.seq));
                end
                obj.InFlight = k;
                done = done + obj.prefixCounts(k,n);
            end
        end

        function tf = inRun(obj)
            tf = obj.Phase.run;
        end

        function tf = countsInFlight(obj,sch)
            % Whether the current run holds presentations Schedule.RunCounts
            % does not have yet: while it is being prepared or streamed, and
            % after it stops, up to the moment it is credited.
            if obj.inRun()
                tf = true;
            elseif obj.Phase.finalize
                tf = runTotal(sch) == obj.RunBase;
            else
                tf = false;
            end
        end

        function R = currentRun(obj,sch,n)
            % The run the schedule is on, and what follows from it -- worked
            % out once per run rather than per refresh, since for an
            % intermixed run it means sorting every presentation of the
            % session. Keyed on the plan's shape as well as the run index:
            % appending make-up runs does not change the current one, but a
            % replaced plan would.
            r = sch.current();
            if r < 1 || r > sch.NumRuns
                R = emptyRun();
                obj.RunCache = R;
                return
            end
            seq = sch.runSequence(r);
            key = [r, obj.PlanKey, numel(seq), n];
            R   = obj.RunCache;
            if isequal(R.key,key), return; end

            seq = reshape(double(seq),1,[]);
            u   = unique(seq);
            u   = u(u >= 1 & u <= n);    % a malformed plan must not throw here
            active = false(1,n);
            active(u) = true;
            P = obj.paramTable();
            if isscalar(u)
                if u <= numel(P.labels), label = P.labels{u}; else, label = sprintf('stimulus %d',u); end
            else
                label = sprintf('%d conditions intermixed',numel(u));
            end
            kind = '';
            if r <= numel(sch.IsMakeup) && sch.IsMakeup(r)
                kind = 'make-up';
            elseif r <= numel(sch.IsRepeat) && sch.IsRepeat(r)
                kind = 'repeat';
            end
            R = struct('key',key,'run',r,'seq',seq,'active',active, ...
                       'label',label,'kind',kind,'k',0,'cum',zeros(1,n));
            obj.RunCache = R;
        end

        function c = prefixCounts(obj,k,n)
            % Presentations per stimulus among the run's first k, kept
            % incrementally: each refresh adds only the sweeps that arrived
            % since the last one.
            R = obj.RunCache;
            if k ~= R.k
                if k > R.k
                    R.cum = R.cum + countOf(R.seq(R.k+1:k),n);
                else
                    R.cum = countOf(R.seq(1:k),n);
                end
                R.k = k;
                obj.RunCache = R;
            end
            c = R.cum;
        end

        function k = estimatePlayed(obj,sch,nSeq)
            % How many of a stimulation-only run's presentations have begun,
            % from the clock: the worker streams at the device's pace, onset k
            % at SilencePad + (k-1)*ISI, and pauses are not owed back (it
            % restarts its pacing clock on resume). A randomized ISI makes
            % this an expectation, which is what the '~' says anyway.
            k = 0;
            if obj.RunT0 == 0, return; end
            if isnan(obj.RunT1), t = obj.runClock(); else, t = obj.RunT1; end
            t   = t - sch.SilencePad;
            isi = sch.MeanISI;
            if t < 0 || ~(isi > 0), return; end
            k = min(nSeq,floor(t/isi) + 1);
        end

        function t = runClock(obj)
            % Seconds the current run has streamed, pauses excluded.
            if obj.Paused && ~isnan(obj.RunHeld), t = obj.RunHeld; return; end
            t = max(0,toc(obj.RunT0) - obj.RunPaused);
        end

        function n = runsDone(obj,sch)
            % Whole runs behind the schedule, the one just credited included.
            r = sch.current();
            if r == 0
                % Walked off the end -- or never built, with nothing done.
                n = sch.NumRuns*(runTotal(sch) > 0);
                return
            end
            n = r - 1;
            if obj.Phase.advance || (obj.Phase.finalize && ~obj.countsInFlight(sch))
                n = r;
            end
        end

        function t = scheduledTotals(obj,sch,n)
            % Every presentation the plan currently holds, per stimulus.
            % Recomputed only when the plan changes shape -- appending a
            % make-up or repeat run changes both the run count and the total
            % presentation count, so the pair is a sufficient fingerprint, and
            % a reshuffle (which changes neither, and neither should it change
            % this) correctly does not trigger a recount. The string form of
            % cellfun is the builtin one: this runs on every refresh.
            key = [sch.NumRuns, sum(cellfun('prodofsize',sch.Runs))];
            if isequal(key,obj.PlanKey) && numel(obj.PlanTotals) == n
                t = obj.PlanTotals; return
            end
            if sch.NumRuns == 0
                t = zeros(1,n);
            else
                seqAll = [sch.Runs{:}];
                t      = accumarray(seqAll(:),1,[n 1])';
            end
            % What a run costs beyond its presentations, for the time left:
            % the silence bracket, and the longest stimulus finishing after
            % the last onset (what mabr.stim.Schedule.summary adds per run).
            try
                over = sch.padSeconds() + sch.Set.maxDuration();
            catch
                over = 2*sch.SilencePad;
            end
            obj.PlanKey      = key;
            obj.PlanTotals   = t;
            obj.PlanOverhead = over;
        end

        % --- Parameters and grouping -------------------------------------------
        function P = paramTable(obj)
            % Which numeric parameters the loaded bank VARIES, their value per
            % stimulus, their units, and what to call each stimulus. From
            % mabr.stim.StimulusSet.paramTable, so a bank that declares
            % informativeParams gets exactly the list it declared and one that
            % does not gets the inferred numeric scalars -- the same dimensions
            % the offline pipeline groups by -- less any that are the same in
            % every entry: grouping by a constant is one bar, and a heat-map
            % axis along one is one column.
            [~,bank] = obj.plan();
            if isempty(bank)
                if ~isempty(obj.Params.bank)
                    obj.Params = emptyParams();
                    obj.ParamsVersion = obj.ParamsVersion + 1;
                end
                P = obj.Params;
                return
            end
            if ~isempty(obj.Params.bank) && isvalid(obj.Params.bank) ...
                    && obj.Params.bank == bank && numel(obj.Params.ids) == bank.numStimuli
                P = obj.Params; return
            end

            n = bank.numStimuli;
            names = {}; vals = zeros(n,0); units = {}; ids = cell(1,n);
            try
                T = bank.paramTable();
                keep  = T.Varying;
                names = T.Names(keep);
                vals  = T.Values(:,keep);
                units = T.Units(keep);
                ids   = T.IDs;
            catch
                % A bank entry we cannot describe still counts.
                for i = 1:n
                    try
                        ids{i} = char(string(bank.id(i)));
                    catch
                        ids{i} = sprintf('stimulus %d',i);
                    end
                end
            end
            labels = cell(1,n);
            for i = 1:n
                labels{i} = stimLabel(names,units,vals(i,:),ids{i});
            end
            P = struct('bank',bank,'names',{names},'values',vals, ...
                       'units',{units},'ids',{ids},'labels',{labels});
            obj.Params = P;
            obj.ParamsVersion = obj.ParamsVersion + 1;
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
                % Each stimulus by the parameters the bank varies ('8 kHz,
                % 30 dB'), which is what an operator calls a condition; its
                % ID where the bank varies none.
                labels = cellfun(@(s) shorten(s,26),P.labels,'UniformOutput',false);
                map = 1:n;
                return
            end

            v  = P.values(:,j).';
            u  = unique(v(~isnan(v)));
            map = zeros(1,n);
            for k = 1:numel(u), map(v == u(k)) = k; end
            % Bare values on the ticks, the unit once on the axis.
            labels = arrayfun(@(x) sprintf('%g',x),u,'UniformOutput',false);
            if any(isnan(v))
                map(isnan(v)) = numel(u) + 1;
                labels{end+1} = 'n/a';
            end
            axisName = axisLabel(P,j);
        end

        % --- Drawing -----------------------------------------------------------
        function drawHeader(obj,done,target,sch)
            D = sum(done); T = sum(target);
            complete = T > 0 && D >= T;
            paused   = obj.Paused && obj.Phase.acquire;
            mark = '';
            if obj.Estimated && obj.InFlight > 0, mark = '~'; end

            if T > 0
                switch obj.Labels
                    case 'counts', big = sprintf('%s%s / %s',mark,groupDigits(D),groupDigits(T));
                    otherwise,     big = [mark pctText(D/T)];
                end
            else
                big = '—';
            end
            obj.put('pct',obj.PctLabel,'Text',big);
            ink = obj.InkColor;
            if complete, ink = obj.DoneColor; end
            obj.put('pctInk',obj.PctLabel,'FontColor',ink);

            rgb = obj.Phase.rgb; txt = obj.Phase.txt;
            if paused, rgb = obj.PausedColor; txt = 'Paused'; end
            obj.put('lamp',obj.Lamp,'Color',rgb);

            if isempty(sch)
                state  = 'No schedule yet';
                detail = 'Start or preview a run, or load a plan.';
                when   = '';
            else
                state  = obj.stateLine(txt,sch,D);
                detail = obj.detailLine(done,target,sch);
                when   = obj.timeLine(D,T,sch,paused);
            end
            obj.put('state',obj.StateLabel,'Text',state);
            obj.put('detail',obj.DetailLabel,'Text',detail);
            obj.put('time',obj.TimeLabel,'Text',when);
            obj.applyName(D,T,complete,paused);
        end

        function txt = stateLine(obj,stateTxt,sch,D)
            bits = {stateTxt};
            if sch.NumRuns > 0
                r = sch.current();
                % Which run only once the schedule has actually got
                % somewhere; a plan waiting at run 1 is just a number of runs.
                started = D > 0 || ~obj.Phase.rest;
                if r >= 1 && started
                    s = sprintf('run %d of %d',r,sch.NumRuns);
                    R = obj.RunCache;
                    if ~isempty(R.key) && R.run == r && ~isempty(R.kind)
                        s = sprintf('%s (%s)',s,R.kind);
                    end
                    bits{end+1} = s;
                else
                    bits{end+1} = sprintf('%d run%s',sch.NumRuns,plural(sch.NumRuns));
                end
            end
            if sch.StimulationOnly
                % The counts here are presentations PLAYED, and the difference
                % matters enough to say every time.
                bits{end+1} = 'stimulation only';
            end
            txt = joinBits(bits);
        end

        function txt = detailLine(obj,done,target,sch)
            % During a run, the run: what it presents and how far through it
            % is. Otherwise the session: conditions finished, and its size.
            R = obj.RunCache;
            if obj.inRun() && ~isempty(R.seq)
                bits = {R.label};
                N = numel(R.seq);
                if ~obj.LiveKnown
                    % Opened mid-run: the count arrives with the next update.
                    bits{end+1} = sprintf('%s presentations this run',groupDigits(N));
                else
                    mark = '';
                    if obj.Estimated && obj.InFlight > 0, mark = '~'; end
                    if strcmp(obj.Labels,'counts')
                        bits{end+1} = sprintf('%s%s / %s this run',mark, ...
                            groupDigits(obj.InFlight),groupDigits(N));
                    else
                        bits{end+1} = sprintf('%s%s of this run',mark,pctText(obj.InFlight/N));
                    end
                end
                if obj.LiveRejected > 0 && ~sch.StimulationOnly
                    bits{end+1} = sprintf('%s rejected',groupDigits(obj.LiveRejected));
                end
            else
                has = target > 0;
                nC  = nnz(has);
                nD  = nnz(has & done >= target);
                bits = {sprintf('%d of %d condition%s complete',nD,nC,plural(nC)), ...
                        sprintf('%s presentations in %d run%s',groupDigits(sum(target)), ...
                            sch.NumRuns,plural(sch.NumRuns))};
            end
            txt = joinBits(bits);
        end

        function txt = timeLine(obj,D,T,sch,paused)
            when = {};
            if obj.T0 == 0
                % Not a session this window has watched: the plan's own
                % estimate is all there is.
                eta = obj.remaining(D,T,sch);
                if ~isnan(eta), when{end+1} = ['~' clockText(eta) ' to run']; end
            elseif ~isnan(obj.Frozen)
                finished = obj.Phase.complete || (T > 0 && D >= T);
                if finished
                    if ~obj.JoinedLate, when{end+1} = ['took ' clockText(obj.Frozen)]; end
                    if ~isempty(obj.FinishedText), when{end+1} = ['finished ' obj.FinishedText]; end
                else
                    if obj.JoinedLate, when{end+1} = 'stopped';
                    else,              when{end+1} = ['stopped after ' clockText(obj.Frozen)];
                    end
                    eta = obj.remaining(D,T,sch);
                    if ~isnan(eta), when{end+1} = ['~' clockText(eta) ' still to run']; end
                end
            else
                if ~obj.JoinedLate, when{end+1} = ['elapsed ' clockText(obj.elapsed())]; end
                if paused && obj.PauseT0 ~= 0
                    when{end+1} = ['paused ' clockText(toc(obj.PauseT0))];
                end
                eta = obj.remaining(D,T,sch);
                if ~isnan(eta)
                    when{end+1} = ['~' clockText(eta) ' left'];
                    % A clock time is worth reading once there is time to
                    % plan around; under a minute it is just noise.
                    if eta >= 60
                        when{end+1} = ['done ≈ ' obj.finishText(eta)];
                    end
                end
            end
            txt = joinBits(when);
        end

        function applyName(obj,D,T,complete,paused)
            % The percentage in the window's own title, so it reads from the
            % taskbar while the window is minimized or buried.
            if isempty(obj.Figure) || ~isgraphics(obj.Figure), return; end
            name = obj.Title;
            if T > 0 && (D > 0 || obj.T0 ~= 0)
                if complete
                    name = [name ' — done'];
                else
                    name = [name ' — ' pctText(D/T)];
                    if paused, name = [name ' (paused)']; end
                end
            end
            obj.put('name',obj.Figure,'Name',name);
        end

        function put(obj,key,h,prop,value)
            % Write one header property, and only when it changes. Judged
            % against what this window last wrote rather than by reading the
            % property back: on a uifigure component even a READ goes through
            % its component machinery, and a repaint asks seven of them.
            if isfield(obj.Shown,key) && isequal(obj.Shown.(key),value), return; end
            h.(prop) = value;
            obj.Shown.(key) = value;
        end

        function s = elapsed(obj)
            if obj.T0 == 0, s = 0; return; end
            if ~isnan(obj.Frozen), s = obj.Frozen; else, s = toc(obj.T0); end
        end

        function eta = remaining(obj,D,T,sch)
            % The plan's estimate of the work left, scaled by how long the
            % plan's work has actually been taking since the pace baseline.
            % Either way an estimate, and the label says so -- a randomized
            % ISI makes the duration an expectation, and an advance criterion
            % can end any run early.
            eta = NaN;
            if isempty(sch) || T <= 0 || D >= T, return; end
            isi   = sch.MeanISI;
            over  = obj.PlanOverhead;
            nDone = obj.runsDone(sch);
            planLeft = (T - D)*isi + max(0,sch.NumRuns - nDone)*over;
            pace = 1;
            if obj.CalT0 ~= 0
                if ~isnan(obj.CalStop)
                    act = obj.CalStop;
                else
                    act = toc(obj.CalT0) - obj.CalPaused;
                    if obj.Paused && obj.PauseT0 ~= 0, act = act - toc(obj.PauseT0); end
                end
                planDone = (D - obj.CalBaseDone)*isi + max(0,nDone - obj.CalBaseRuns)*over;
                if act >= obj.CalibrateAfter && planDone >= obj.CalibrateAfter/2
                    pace = act/planDone;
                end
            end
            eta = planLeft*pace;
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
                case 'heatmap', obj.drawHeat(done,target,active);
            end
        end

        function drawBars(obj,done,target,active)
            % The grouping is part of the layout: worked out when the layout
            % is built, and a refresh is then three accumarrays.
            obj.paramTable();    % settle the version the key is built from
            n   = numel(done);
            key = sprintf('bars|%s|%d|%d',obj.GroupBy,n,obj.ParamsVersion);
            if ~strcmp(obj.LayoutKey,key)
                [labels,map,axisName] = obj.groupsBy(obj.GroupBy,n);
                if isempty(labels), obj.showMessage('Nothing scheduled.'); return; end
                obj.buildBars(labels,axisName,key);
                obj.Map = struct('map',map,'G',numel(labels));
            end
            m = obj.Map;
            d = accumarray(m.map(:),done(:),  [m.G 1]).';
            t = accumarray(m.map(:),target(:),[m.G 1]).';
            a = accumarray(m.map(:),double(active(:)),[m.G 1]).' > 0;
            obj.paintBars(d,t,a);
        end

        function buildBars(obj,labels,axisName,key)
            n    = numel(labels);
            ax   = obj.Axes;
            show = n <= obj.MaxLabelled;
            % Bars share the axes height between them, so the type has to come
            % down as their number goes up -- floored, because a label too
            % small to read is no better than none.
            tickFont = max(7,min(11,round(360/max(n,1))));

            obj.clearAxes();
            F = reshape(1:4*n,4,n).';
            obj.TrackPatch = patch(ax,'Faces',F, ...
                'Vertices',barVertices(ones(1,n),n,obj.BarHeight,obj.BarSpan), ...
                'FaceColor',obj.TrackColor,'EdgeColor','none');
            obj.FillPatch = patch(ax,'Faces',F, ...
                'Vertices',barVertices(zeros(1,n),n,obj.BarHeight,obj.BarSpan), ...
                'FaceColor','flat','FaceVertexCData',repmat(obj.FillColor,n,1), ...
                'EdgeColor','none');
            obj.ValueText = gobjects(1,0);
            if show
                % One object per bar, built in bar order and never rebuilt --
                % only its String changes from here on. The value sits in the
                % gutter to the right of the track (see BarSpan), so no
                % number is ever drawn over a bar.
                obj.ValueText = gobjects(1,n);
                for k = 1:n
                    obj.ValueText(k) = text(ax,1,k,'', ...
                        'HorizontalAlignment','right','VerticalAlignment','middle', ...
                        'FontSize',tickFont,'Color',obj.InkColor,'Interpreter','none');
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
            % IDs like 8kHz_30dB are not TeX: an underscore would subscript.
            ax.TickLabelInterpreter = 'none';
            if show
                ax.YTick = 1:n;
                ax.YTickLabel = labels;
            else
                ax.YTick = [];
            end
            ylabel(ax,axisName,'Color',obj.MutedColor,'FontSize',11,'Interpreter','none');
            % What every object was created showing, for the diffs to start
            % from.
            obj.Drawn = struct('values',{repmat({''},1,numel(obj.ValueText))}, ...
                'valuesOn',true,'barColors',repmat(obj.FillColor,n,1));
            obj.LayoutKey = key;
        end

        function paintBars(obj,done,target,active)
            n    = numel(done);
            frac = zeros(1,n);
            pos  = target > 0;
            frac(pos) = min(1,done(pos)./target(pos));
            finished  = pos & frac >= 1;

            C = repmat(obj.FillColor,n,1);
            C(active,:)   = repmat(obj.ActiveColor,nnz(active),1);
            C(finished,:) = repmat(obj.DoneColor,nnz(finished),1);

            set(obj.FillPatch,'Vertices',barVertices(frac,n,obj.BarHeight,obj.BarSpan));
            if obj.markDrawn('barColors',C), set(obj.FillPatch,'FaceVertexCData',C); end

            if ~isempty(obj.ValueText)
                if strcmp(obj.Labels,'none')
                    if obj.markDrawn('valuesOn',false), set(obj.ValueText,'Visible','off'); end
                else
                    strs = cell(1,n);
                    for k = 1:n, strs{k} = obj.valueText(done(k),target(k),frac(k)); end
                    obj.setTexts(obj.ValueText,'values',strs);
                    if obj.markDrawn('valuesOn',true), set(obj.ValueText,'Visible','on'); end
                end
            end
            t = obj.bodyTitle(nnz(finished),nnz(pos));
            if isempty(obj.ValueText)
                % Rather than leave the bars anonymous with no explanation --
                % and the view that WOULD fit this many conditions is one
                % dropdown away.
                t = sprintf(['%s (%d — too many to label; group by a ' ...
                    'parameter, or use the heat map)'],t,n);
            end
            obj.setCaption(t);
        end

        function drawHeat(obj,done,target,active)
            P = obj.paramTable();
            if numel(P.names) < 2
                obj.showMessage(['The heat map needs two stimulus parameters that ' ...
                    'vary; this bank varies fewer. Try the bar views.']);
                return
            end
            jx = find(strcmp(P.names,obj.HeatX),1);
            jy = find(strcmp(P.names,obj.HeatY),1);
            if isempty(jx) || isempty(jy) || jx == jy
                obj.showMessage('Pick two different parameters for the heat map''s axes.');
                return
            end

            key = sprintf('heat|%s|%s|%d|%d',obj.HeatX,obj.HeatY,numel(done),obj.ParamsVersion);
            if ~strcmp(obj.LayoutKey,key), obj.buildHeat(P,jx,jy,key); end

            m  = obj.Map;
            nc = m.ny*m.nx;
            ok = ~isnan(m.cell);
            D  = reshape(accumarray(m.cell(ok).',done(ok).',  [nc 1]),m.ny,m.nx);
            T  = reshape(accumarray(m.cell(ok).',target(ok).',[nc 1]),m.ny,m.nx);
            A  = reshape(accumarray(m.cell(ok).',double(active(ok)).',[nc 1]),m.ny,m.nx) > 0;
            Fr = D./T;
            Fr(T == 0) = NaN;

            set(obj.HeatImage,'CData',min(1,Fr),'AlphaData',double(~isnan(Fr)));
            % A cell the plan has nothing in is a hole in the design, and has
            % to look like one: hatched, not a pale cell that could be 0%.
            if obj.markDrawn('holes',T == 0)
                [hx,hy] = hatchLines(T == 0);
                set(obj.HoleHatch,'XData',hx,'YData',hy);
            end
            % The cells being presented right now, in the bars' amber.
            if obj.markDrawn('active',A & T > 0)
                [ax_,ay_] = cellOutlines(A & T > 0);
                set(obj.ActiveOutline,'XData',ax_,'YData',ay_);
            end

            if isempty(obj.HeatText)
                % A grid too dense to write in; the shading carries it.
            elseif strcmp(obj.Labels,'none')
                if obj.markDrawn('heatOn',false), set(obj.HeatText,'Visible','off'); end
            else
                strs = repmat({''},m.ny,m.nx);
                ink  = obj.Drawn.heatInk;
                has  = reshape(find(T > 0),1,[]);
                ncm  = numel(m.white);
                for c_ = has
                    strs{c_} = obj.valueText(D(c_),T(c_),Fr(c_));
                    % Whichever of ink and white reads better on this cell's
                    % actual colour (see whiteInk); a hole keeps whatever it
                    % had, since it shows no text.
                    ink(c_) = m.white(min(ncm,floor(min(1,Fr(c_))*ncm) + 1));
                end
                obj.setTexts(obj.HeatText,'heatStr',strs);
                chg = ink ~= obj.Drawn.heatInk;
                if any(chg(:))
                    cols = repmat({obj.InkColor},sum(chg(:)),1);
                    cols(ink(chg)) = {[1 1 1]};
                    set(obj.HeatText(chg),{'Color'},cols);
                    obj.Drawn.heatInk = ink;
                end
                if obj.markDrawn('heatOn',true), set(obj.HeatText,'Visible','on'); end
            end
            has = T > 0;
            obj.setCaption(obj.bodyTitle(nnz(has & D >= T),nnz(has)));
        end

        function buildHeat(obj,P,jx,jy,key)
            obj.clearAxes();
            ax = obj.Axes;
            vx = P.values(:,jx).';  xu = unique(vx(~isnan(vx)));
            vy = P.values(:,jy).';  yu = unique(vy(~isnan(vy)));
            nx = numel(xu); ny = numel(yu);

            % Which cell each stimulus lands in, worked out ONCE: the refresh
            % path is then one accumarray, not a search per stimulus per
            % repaint.
            [~,ix] = ismember(vx,xu);
            [~,iy] = ismember(vy,yu);
            cell_  = nan(1,numel(vx));
            ok     = ix > 0 & iy > 0;
            cell_(ok) = sub2ind([ny nx],iy(ok),ix(ok));
            cm = heatColors();
            obj.Map = struct('cell',cell_,'nx',nx,'ny',ny,'white',whiteInk(cm,obj.InkColor));

            % image(), not imagesc(): the low-level form defaults to DIRECT
            % CData mapping, so 'scaled' is stated rather than assumed -- a
            % fraction indexing the colormap directly would paint every cell
            % the same colour. Everything here is a low-level primitive, so
            % nothing needs hold and nothing resets the axes. Stacking order
            % is creation order: the hatch goes UNDER the cell borders so they
            % trim its ends, the outline over them, the numbers on top.
            obj.HeatImage = image('Parent',ax,'XData',1:nx,'YData',1:ny, ...
                'CData',nan(ny,nx),'AlphaData',zeros(ny,nx), ...
                'CDataMapping','scaled');
            obj.HoleHatch = line(ax,NaN,NaN,'Color',obj.HatchColor,'LineWidth',0.75, ...
                'HitTest','off','PickableParts','none');
            [gx,gy] = gridLines(nx,ny);
            line(ax,gx,gy,'Color',obj.PaperColor,'LineWidth',1.5, ...
                'HitTest','off','PickableParts','none');
            obj.ActiveOutline = line(ax,NaN,NaN,'Color',obj.ActiveColor,'LineWidth',2, ...
                'HitTest','off','PickableParts','none');
            obj.HeatText = gobjects(0,0);
            if nx*ny <= obj.MaxCells
                % Smaller type as the grid gets denser, floored where it
                % stops being readable at all.
                fs = max(7,min(10,round(60/max(nx,ny))));
                obj.HeatText = gobjects(ny,nx);
                for c = 1:nx
                    for r = 1:ny
                        obj.HeatText(r,c) = text(ax,c,r,'', ...
                            'HorizontalAlignment','center','VerticalAlignment','middle', ...
                            'FontSize',fs,'Color',obj.InkColor,'Interpreter','none');
                    end
                end
            end

            ax.YDir  = 'normal';           % level increases upward
            ax.XLim  = [0.5 nx+0.5];
            ax.YLim  = [0.5 ny+0.5];
            ax.XTick = 1:nx; ax.XTickLabel = compose('%g',xu);
            ax.YTick = 1:ny; ax.YTickLabel = compose('%g',yu);
            ax.TickLabelInterpreter = 'none';
            % Paper behind the image, so a hole is white under its hatching
            % -- distinct from the ramp's palest step, which is 0%.
            ax.Color = obj.PaperColor;
            ax.Box   = 'on';
            ax.XColor = obj.MutedColor; ax.YColor = obj.MutedColor;
            ax.FontSize = 10;
            xlabel(ax,axisLabel(P,jx),'Color',obj.InkColor,'Interpreter','none');
            ylabel(ax,axisLabel(P,jy),'Color',obj.InkColor,'Interpreter','none');
            colormap(ax,cm);
            ax.CLim = [0 1];
            obj.addColorBar(ax);
            obj.Drawn = struct('heatStr',{repmat({''},size(obj.HeatText))}, ...
                'heatInk',false(size(obj.HeatText)),'heatOn',true);
            obj.LayoutKey = key;
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

        function tf = markDrawn(obj,field,value)
            % Whether VALUE differs from what the layout is showing for FIELD;
            % if so it is recorded as shown, and the caller writes it.
            tf = ~isfield(obj.Drawn,field) || ~isequal(obj.Drawn.(field),value);
            if tf, obj.Drawn.(field) = value; end
        end

        function setTexts(obj,h,field,strs)
            % Rewrite only the labels whose text changed. A refresh mid-run
            % moves one condition, or a handful -- not every cell of the grid.
            prev = obj.Drawn.(field);
            chg  = ~strcmp(strs(:),prev(:));
            if ~any(chg), return; end
            set(h(chg),{'String'},reshape(strs(chg),[],1));
            obj.Drawn.(field) = strs;
        end

        function setCaption(obj,txt)
            % The same reasoning as mabr.ui.LivePlot.setTitle: a caption is
            % rewritten on every refresh and hardly any refresh changes it,
            % and writing it back is not free.
            ax = obj.Axes;
            if isequal(ax.Title.String,txt), return; end
            title(ax,txt,'FontSize',10,'FontWeight','normal', ...
                'Color',obj.MutedColor,'Interpreter','none');
        end

        function s = valueText(obj,done,target,frac)
            if target <= 0, s = '—'; return; end
            switch obj.Labels
                case 'counts',  s = sprintf('%d/%d',round(done),round(target));
                case 'percent', s = pctText(frac);
                otherwise,      s = '';
            end
        end

        function t = bodyTitle(obj,nDone,nAll)
            [sch,~] = obj.plan();
            what = 'Presentations';
            if ~isempty(sch) && sch.StimulationOnly, what = 'Presentations played'; end
            switch obj.View
                case 'bars'
                    if strcmpi(obj.GroupBy,'Stimulus')
                        t = sprintf('%s complete, by stimulus',what);
                    else
                        t = sprintf('%s complete, by %s',what,obj.GroupBy);
                    end
                case 'heatmap'
                    t = sprintf('%s complete',what);
                otherwise
                    t = '';
            end
            if nAll > 0, t = sprintf('%s  ·  %d of %d done',t,nDone,nAll); end
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
            obj.TrackPatch    = [];
            obj.FillPatch     = [];
            obj.ValueText     = gobjects(1,0);
            obj.HeatImage     = [];
            obj.HeatText      = gobjects(1,0);
            obj.ActiveOutline = [];
            obj.HoleHatch     = [];
            obj.MsgText       = [];
            obj.Map           = struct();
            obj.Drawn         = struct();
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
function P = emptyParams()
P = struct('bank',[],'names',{{}},'values',[],'units',{{}},'ids',{{}},'labels',{{}});
end

function R = emptyRun()
R = struct('key',[],'run',0,'seq',zeros(1,0),'active',false(1,0), ...
           'label','','kind','','k',0,'cum',zeros(1,0));
end

function c = countOf(seq,n)
% Presentations per stimulus in a stretch of a run, as a [1 x n] row. Indices
% outside the bank are skipped rather than allowed to throw from a callback.
seq = seq(seq >= 1 & seq <= n);
c   = accumarray(reshape(seq,[],1),1,[n 1]).';
end

function t = runTotal(sch)
% Presentations the plan has credited so far -- the number a run's credit moves.
if isempty(sch), t = 0; else, t = sum(sch.RunCounts); end
end

function eng = engineOf(controller)
% The acquisition engine behind a controller, if it exposes one. Read only
% for its StateChanged (pause), so anything shaped like it will do -- which is
% what lets a test stand a fake in.
eng = [];
try
    if isprop(controller,'Engine') && ~isempty(controller.Engine) && isvalid(controller.Engine)
        eng = controller.Engine;
    end
catch
end
end

function s = stimLabel(names,units,vals,id)
% One stimulus by the parameters the bank varies -- '8 kHz, 30 dB' -- the
% convention mabr.ui.LivePlot names a condition by; its ID where there are none.
parts = cell(1,numel(names));
for j = 1:numel(names)
    parts{j} = paramValueText(names{j},units{j},vals(j));
end
parts = parts(~cellfun(@isempty,parts));
if isempty(parts), s = id; else, s = strjoin(parts,', '); end
end

function s = paramValueText(name,unit,v)
% A unit where the toolbox fixes one (kHz, dB); anything else is named rather
% than given a unit that would be a guess.
if isnan(v), s = ''; return; end
if isempty(unit), s = sprintf('%s %g',name,v);
else,             s = sprintf('%g %s',v,unit);
end
end

function s = axisLabel(P,j)
u = '';
if j <= numel(P.units), u = P.units{j}; end
if isempty(u), s = P.names{j}; else, s = sprintf('%s (%s)',P.names{j},u); end
end

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

function [x,y] = hatchLines(mask)
% Three parallel diagonal strokes across every masked cell, NaN-separated, for
% ONE line object; NaN alone (nothing drawn) when no cell is masked. Each
% stroke is 2 points and a separator, so a cell is 9 entries.
[r,c] = find(mask);
if isempty(r), x = NaN; y = NaN; return; end
sx = [-0.5 0.5; -0.5 0; 0 0.5];   % the main diagonal, and one either side
sy = [-0.5 0.5; 0 0.5; -0.5 0];
k  = numel(r);
X  = nan(9,k); Y = nan(9,k);
for s = 1:3
    X(3*s-2,:) = c.' + sx(s,1);  X(3*s-1,:) = c.' + sx(s,2);
    Y(3*s-2,:) = r.' + sy(s,1);  Y(3*s-1,:) = r.' + sy(s,2);
end
x = X(:).'; y = Y(:).';
end

function [x,y] = cellOutlines(mask)
% A rectangle just inside every masked cell (so the white borders do not cover
% it), closed and NaN-separated: 6 entries a cell, NaN alone for none.
[r,c] = find(mask);
if isempty(r), x = NaN; y = NaN; return; end
h = 0.42;
k = numel(r);
X = [c-h c+h c+h c-h c-h nan(k,1)].';
Y = [r-h r-h r+h r+h r-h nan(k,1)].';
x = X(:).'; y = Y(:).';
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

function white = whiteInk(cm,ink)
% For each colormap row, whether white text reads better on it than the ink
% colour does -- by WCAG contrast ratio, not by a guessed threshold. The ramp's
% middle is where a fixed cut-off goes wrong: white on a mid teal is barely
% 2:1, where the dark ink manages over 4:1.
L  = relLum(cm);
Li = relLum(ink);
white = 1.05./(L + 0.05) > (max(L,Li) + 0.05)./(min(L,Li) + 0.05);
end

function L = relLum(rgb)
c  = rgb;
lo = c <= 0.04045;
c(lo)  = c(lo)/12.92;
c(~lo) = ((c(~lo) + 0.055)/1.055).^2.4;
L = c*[0.2126; 0.7152; 0.0722];
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

function s = plural(n)
if n == 1, s = ''; else, s = 's'; end
end

function s = pctText(frac)
% Rounded, but never 100% while anything is left -- a header reading 100% over
% work still outstanding is the one rounding that says something false.
p = round(100*frac);
if frac < 1, p = min(p,99); end
s = sprintf('%d%%',p);
end

function s = groupDigits(n)
% 6144 -> 6,144: the big number is read from across the room.
s = sprintf('%d',round(abs(n)));
L = numel(s);
if L > 3
    k = mod(L-1,3) + 1;                  % digits before the first comma
    g = reshape(s(k+1:end),3,[]);
    s = [s(1:k) reshape([repmat(',',1,size(g,2)); g],1,[])];
end
if n < 0, s = ['-' s]; end
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

function s = joinBits(bits)
% strjoin(bits,'  ·  '), without strjoin's argument checking on every repaint.
s = bits{1};
for k = 2:numel(bits), s = [s '  ·  ' bits{k}]; end %#ok<AGROW>
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
