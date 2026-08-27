classdef MetricPlot < handle
% mabr.ui.MetricPlot  Online analysis: ONE metric, plotted against the
% stimulus parameters, refreshed while the schedule runs.
%
%   The live plot answers "what does the response look like right now"; this
%   window answers the other question an experiment is actually asking --
%   "how does <some number> behave across the conditions I am running". It
%   computes one metric per stimulus condition (RMS, peak-to-peak, sweep
%   correlation, SNR, latency, a function you wrote) and draws it against the
%   condition's own parameters, updating as blocks land and as the run in
%   progress accumulates sweeps.
%
%       mp = mabr.ui.MetricPlot(controller);      % the App's chart toolbar button
%       mp.Metric = 'snr';  mp.PlotType = 'heatmap';
%
%   ONE PLOT PER WINDOW, AND THE WINDOW IS NOT A SINGLETON. Every press of
%   the toolbar button (or the live plot's Analysis button) opens ANOTHER
%   one, each with its own metric, window, plot type and aesthetics -- which
%   is the point: RMS against level and sweep correlation against frequency
%   are two plots, and folding them into one window behind a mode switch
%   means never seeing both. Open four and arrange them.
%
%   WHERE THE NUMBERS COME FROM
%   Two sources, merged by stimulus ID:
%     * finalized blocks -- mabr.ui.AcqController's BlockReady event, plus a
%       backfill of mabr.data.Session.Blocks when the window attaches, so a
%       window opened halfway through a schedule shows what is already done.
%       These are authoritative: artifact-rejected sweeps already excluded,
%       the display filter chain already applied.
%     * the run in progress -- pulled from AcqController.liveSnapshot on this
%       window's own clock, so a condition's point appears and firms up while
%       it is being acquired instead of springing into existence at the end
%       of the run. A live condition is drawn with a HOLLOW marker and
%       counted in the subtitle, because a number from 40 sweeps is not the
%       number the block will report and the plot must not imply otherwise.
%   A condition being acquired shows its live value; the finalized data takes
%   over the moment the run finalizes, and repeats/make-up runs of the same
%   stimulus ACCUMULATE (more sweeps for that condition, not a replacement).
%
%   THE PLOT ADAPTS TO HOW MANY PARAMETERS VARY
%   Parameters are the stimulus metadata's informativeParams -- whatever the
%   bank declares as identifying a condition (Frequency, Level, ...).
%       0 varying   one bar per stimulus ID
%       1 varying   metric vs that parameter, a line with symbols
%       2 varying   one line per level of the second, symbols and a legend --
%                   or, on request, a heat map, filled contour, or surface
%       3+          you pick which two are the axes; the rest collapse by
%                   averaging into each cell, and the subtitle says so
%   Auto never silently picks a surface: it picks lines, which are readable
%   at a glance during acquisition. The other forms are one right-click away.
%
%   AESTHETICS ARE THE OPERATOR'S, VIA RIGHT-CLICK
%   Everything visual -- plot type, palette, per-series colour, colormap,
%   marker, line style and width, grid, legend placement, axis scales and
%   limits, font size, light/dark, value labels -- is on the axes context
%   menu, and is remembered (MATLAB prefs, group MABR) so the NEXT window
%   opens looking like the last one you tuned. What is MEASURED (metric,
%   analysis window, which parameter is on which axis, refresh interval)
%   lives on the control strip instead: it changes the numbers, not the ink.
%
%   REFRESH RATE. Default 1 s, adjustable from 0.25 s to 60 s. There is no
%   reason to go faster -- an average moves slowly. The metric functions are
%   pure (mabr.metrics.online.context is the contract), so a slow custom
%   metric costs only its own window.
%
%   WHERE THE ARITHMETIC RUNS. With the compute workers on (Settings >
%   Background compute workers) each window takes a slot on the metrics
%   worker (mabr.compute.ComputeEngine) and its metric is evaluated in that
%   process -- the one place user-supplied metric functions run, so a hung
%   one costs its window and never this one or the live trace. Without a
%   worker, or a free slot, the window evaluates in-process exactly as it
%   always did; the two paths run the same code over the same table
%   (mabr.compute.evaluateJobs, mabr.compute.ConditionStore) and agree.
%
%   Nothing here writes anything: it is a view over data the acquisition owns.
%   The numbers can be taken away by hand -- right-click for the clipboard, a
%   CSV, an image, or a static copy in a plain figure.
%
%   See also mabr.metrics.online.catalog (the built-ins),
%   mabr.metrics.online.custom_template (writing your own),
%   mabr.ui.LivePlot, mabr.ui.AcqController.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant, Access = private)
        ControlHeight = 58;         % px, two rows of controls
        PrefGroup     = 'MABR';
        PrefKey       = 'MetricPlot';
        MinInterval   = 0.25;       % s
        MaxInterval   = 60;         % s
        FontSizes     = [8 9 10 11 12 14 16];
        Markers       = {'o','s','^','d','v','*','+','x','.','none'};
        LineStyles    = {'-','--',':','-.','none'};
        Grids         = {'none','x','y','both'};
    end

    properties
        Title (1,:) char = 'MABR Online Analysis';
    end

    properties (SetAccess = private)
        Figure
        Container       % figure, or the container this view was built into
        PlotPanel
        CtrlPanel
        Axes
        Controller      % mabr.ui.AcqController, or empty
    end

    % --- What is measured (the control strip writes exactly these) ---------
    properties
        Metric      (1,:) char   = 'rms'     % a catalog Key, or 'custom'
        Window      (1,2) double = [0 10]    % ms re onset, the analysis window
        XParam      (1,:) char   = ''        % '' = auto; 'Stimulus' = one per ID
        SeriesParam (1,:) char   = ''        % '' = auto; 'none' = one series
        PlotType    (1,:) char   = 'auto'    % auto|line|scatter|bar|heatmap|contour|surface
        UpdateInterval (1,1) double = 1      % s between refreshes
        Style       (1,1) struct             % aesthetics; see defaultStyle()
    end

    properties (SetAccess = private)
        CustomFcn  = []                      % user metric, or []
        CustomName (1,:) char = ''
        % The job slot this window holds on the metrics worker
        % (mabr.compute.ComputeEngine), or [] -- no worker, or none free.
        % With a slot the metric is evaluated off-process and read back;
        % without one it is evaluated here, exactly as it always was.
        Slot = []
        % Whether the values on screen came from the worker (or are
        % deliberately withheld because of it) rather than computed here.
        ServedByWorker (1,1) logical = false
    end

    properties (Dependent)
        Stalled                              % this window's metric hung the worker
    end

    properties (Access = private)
        Ctrl      = struct()
        Ticker
        Listeners
        Menu                                 % the axes context menu
        MenuItems = struct()
        Blocks                               % finalized conditions (store)
        LiveConds                            % the run in progress (store)
        LastValues                           % what the last render drew
        Built     (1,1) logical = false
        Suspend   (1,1) logical = false      % bulk load in progress
        Note      (1,:) char = ''            % one-line caveat for the subtitle
        WorkerNote (1,:) char = ''           % ... and one about the worker
        LastWorker = []                      % the last values the worker gave
        % render() is not re-entrant: legend() and drawnow process pending
        % events, and a timer tick landing inside one would cla() the axes
        % out from under the lines the outer call is still dressing. A tick
        % that finds a render in progress simply skips -- the next one
        % draws the same data.
        Rendering (1,1) logical = false
        Drawn     (1,1) logical = false      % something has been drawn at all
        DrawnNote (1,:) char = ''            % the WorkerNote it was drawn with
        WarnedMetric (1,:) char = ''         % last metric that threw, so it logs once
    end

    methods
        function obj = MetricPlot(controller,parent)
            % mp = mabr.ui.MetricPlot(controller) opens a window attached to a
            % running acquisition. Both arguments are optional: with no
            % controller it is a viewer for whatever addBlock() is handed, and
            % with a `parent` container it builds into that instead of its own
            % figure -- the same host seam mabr.ui.LivePlot offers.
            obj.Blocks    = mabr.ui.MetricPlot.emptyStore();
            obj.LiveConds = mabr.ui.MetricPlot.emptyStore();

            d = mabr.ui.MetricPlot.loadDefaults();
            obj.Style          = d.Style;
            obj.Metric         = d.Metric;
            obj.PlotType       = d.PlotType;
            obj.Window         = d.Window;
            obj.UpdateInterval = d.UpdateInterval;

            if nargin >= 2 && ~isempty(parent) && isgraphics(parent)
                obj.Container = parent;
            else
                obj.Figure = figure('Name',obj.Title,'NumberTitle','off', ...
                    'Color','w','Tag','MABR_METRICPLOT', ...
                    'Position',[120 120 760 540]);
                obj.Container = obj.Figure;
            end

            obj.build();
            obj.Built = true;

            if nargin >= 1 && ~isempty(controller) && isvalid(controller)
                obj.attach(controller);
            end

            obj.startTicker();
            obj.refresh();
        end

        function delete(obj)
            obj.stopTicker();
            try, obj.releaseSlot();     end %#ok<TRYNC>
            try, delete(obj.Ticker);    end %#ok<TRYNC>
            try, delete(obj.Listeners); end %#ok<TRYNC>
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function tf = get.Stalled(obj)
            tf = ~isempty(obj.Slot) && ~isempty(obj.Controller) && isvalid(obj.Controller) ...
                && ~isempty(obj.Controller.Compute) && isvalid(obj.Controller.Compute) ...
                && obj.Controller.Compute.isStalled(obj.Slot);
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Axes) && isgraphics(obj.Axes);
        end

        % --- Data sources ---------------------------------------------------
        function attach(obj,controller)
            % Track an acquisition. Re-pointing at a different controller (the
            % App rebuilds one when the Testing / stimulation-only mode
            % changes) replaces the listeners rather than adding a second set,
            % exactly as mabr.ui.TraceOrganizer.listenTo does.
            try, delete(obj.Listeners); end %#ok<TRYNC>
            obj.Listeners  = [];
            obj.releaseSlot();                  % on the OLD controller's engine
            obj.Controller = controller;
            if isempty(controller) || ~isvalid(controller), return; end

            obj.Listeners = [ ...
                addlistener(controller,'BlockReady',@(~,e) obj.onBlockReady(e)); ...
                addlistener(controller,'ScheduleComplete',@(~,~) obj.refresh())];

            % A slot on the metrics worker, where there is one: the metric
            % is then evaluated off-process. None free (or no worker) means
            % this window evaluates in-process, and nothing else changes.
            if ~isempty(controller.Compute) && isvalid(controller.Compute)
                obj.Slot = controller.Compute.acquireSlot();
                obj.pushJob();
            end

            % Backfill what the session already holds -- one redraw at the end
            % of it, not one per block.
            s = controller.Session;
            if ~isempty(s) && isvalid(s)
                obj.Suspend = true;
                try
                    for i = 1:s.NumBlocks
                        obj.addBlock(s.Blocks(i));
                    end
                catch me
                    obj.Suspend = false;
                    rethrow(me);
                end
                obj.Suspend = false;
            end
            obj.refresh();
        end

        function addBlock(obj,block)
            % Fold one finalized mabr.data.Block into the store. Public so a
            % host -- or a test -- can drive the window with no engine at all.
            % The conversion and the merge rule are
            % mabr.compute.ConditionStore's, shared with the metrics worker,
            % so the two build the same table from the same blocks.
            c = mabr.compute.ConditionStore.fromBlock(block);
            if isempty(c), return; end
            obj.Blocks = mabr.compute.ConditionStore.merge(obj.Blocks,c);
            obj.refresh();
        end

        function updateLive(obj,snap,stimuli)
            % Replace the in-progress conditions from an
            % AcqController.liveSnapshot payload ([] clears them) and redraw.
            % Public so a host -- or a test -- can drive the live half with no
            % engine; the window's own clock goes through setLive instead,
            % which is the same work without the redraw refresh is about to do
            % anyway.
            if nargin < 3, stimuli = []; end
            obj.setLive(snap,stimuli);
            obj.render();
        end

        function clearData(obj)
            % Forget everything -- a fresh subject on the same window.
            obj.Blocks    = mabr.ui.MetricPlot.emptyStore();
            obj.LiveConds = mabr.ui.MetricPlot.emptyStore();
            obj.refresh();
        end

        function setLive(obj,snap,stimuli)
            % The store half of updateLive: the snapshot always describes ONE
            % run, and only while it is streaming, so replacing wholesale is
            % what keeps this honest -- there is nothing to accumulate here;
            % the finalized block is where accumulation happens. The
            % parameters come from the bank handed in, or failing that the
            % controller's; a bank swapped under a running window costs the
            % point its parameters, not the window.
            if nargin < 3, stimuli = []; end
            if isempty(stimuli) && ~isempty(obj.Controller) && isvalid(obj.Controller)
                stimuli = obj.Controller.Stimuli;
            end
            obj.LiveConds = mabr.compute.ConditionStore.fromLive(snap,stimuli);
        end

        % --- Metric selection -----------------------------------------------
        function setCustomMetric(obj,fcn,name)
            % Adopt a user-written metric, refusing one that does not meet the
            % contract (mabr.metrics.online.validate) rather than letting it
            % throw on every refresh for the rest of the session.
            [ok,why] = mabr.metrics.online.validate(fcn);
            assert(ok,'mabr:ui:MetricPlot:badMetric', ...
                'That is not a valid online metric: %s',why);
            obj.CustomFcn = fcn;
            if nargin < 3 || isempty(name), name = func2str(fcn); end
            obj.CustomName = char(name);
            obj.Metric     = 'custom';
        end

        % --- Refresh ---------------------------------------------------------
        function refresh(obj)
            % Pull the run in progress (if any) and redraw. Safe at any time;
            % the timer calls it, and so does every setting change.
            if ~obj.Built || obj.Suspend, return; end
            if ~obj.isvalidView(), obj.stopTicker(); return; end
            obj.pullLive();
            obj.render();
        end

        function C = conditions(obj)
            % Every condition the window would plot, a live one overriding the
            % finalized data of the same stimulus. The merge rule lives in
            % mabr.compute.ConditionStore alone, so the plot, the export, the
            % metrics worker and the tests agree.
            C = mabr.compute.ConditionStore.conditions(obj.Blocks,obj.LiveConds);
        end

        function V = values(obj)
            % The plotted numbers as a struct array: Key, Label, Params,
            % Value, NumSweeps, Live. What the axes shows, what the clipboard
            % and the CSV carry, and what a test reads back.
            V = obj.computeValues();
        end

        function V = localValues(obj)
            % The same numbers evaluated in THIS process whatever the worker
            % is doing -- what a test holds the worker's answer against.
            V = obj.computeLocal();
        end

        function T = dataTable(obj)
            % values() as a table: one row per condition, each informative
            % parameter in its own column, the metric in the column named
            % after it.
            V = obj.computeValues();
            if isempty(V), T = table(); return; end
            e     = obj.metricEntry();
            names = mabr.ui.MetricPlot.paramNames(V);

            T = table({V.Label}','VariableNames',{'Condition'});
            for k = 1:numel(names)
                col = arrayfun(@(c) mabr.ui.MetricPlot.paramValue(c,names{k}),V);
                T.(matlab.lang.makeValidName(names{k})) = col(:);
            end
            T.(matlab.lang.makeValidName(e.Name)) = [V.Value]';
            T.Sweeps     = [V.NumSweeps]';
            T.InProgress = [V.Live]';
        end
    end

    % =====================================================================
    methods   % property setters -- every one lands in afterSettingChange
        function set.Metric(obj,v)
            obj.Metric = char(v);
            obj.afterSettingChange();
        end
        function set.Window(obj,v)
            assert(numel(v) == 2 && all(isfinite(v)) && v(2) > v(1), ...
                'mabr:ui:MetricPlot:window', ...
                'The analysis window must be [start end] ms and end after it starts.');
            obj.Window = double(v);
            obj.afterSettingChange();
        end
        function set.XParam(obj,v)
            obj.XParam = char(v);
            obj.afterSettingChange();
        end
        function set.SeriesParam(obj,v)
            obj.SeriesParam = char(v);
            obj.afterSettingChange();
        end
        function set.PlotType(obj,v)
            v = lower(char(v));
            assert(any(strcmp(v,mabr.ui.MetricPlot.plotTypes())), ...
                'mabr:ui:MetricPlot:plotType','Unknown plot type "%s".',v);
            obj.PlotType = v;
            obj.afterSettingChange();
        end
        function set.UpdateInterval(obj,v)
            obj.UpdateInterval = min(max(double(v), ...
                mabr.ui.MetricPlot.MinInterval),mabr.ui.MetricPlot.MaxInterval);
            obj.restartTicker();
            obj.afterSettingChange();
        end
        function set.Style(obj,v)
            obj.Style = mabr.ui.MetricPlot.fillStyle(v);
            obj.afterSettingChange();
        end
    end

    % =====================================================================
    methods (Access = private)
        % --- Construction ----------------------------------------------------
        function build(obj)
            c = obj.Container;
            obj.PlotPanel = uipanel('Parent',c,'BorderType','none', ...
                'BackgroundColor','w','Units','normalized');
            obj.CtrlPanel = uipanel('Parent',c,'BorderType','none', ...
                'BackgroundColor',get(0,'defaultUicontrolBackgroundColor'), ...
                'Units','normalized');

            obj.Axes = axes('Parent',obj.PlotPanel,'Units','normalized', ...
                'Position',[0.12 0.16 0.78 0.70],'Box','on','NextPlot','add');
            mabr.ui.hideAxesToolbar(obj.Axes);

            obj.buildControls();
            obj.buildMenus();
            obj.relayout();
            if isprop(c,'SizeChangedFcn'), c.SizeChangedFcn = @(~,~) obj.relayout(); end
        end

        function relayout(obj)
            if isempty(obj.CtrlPanel) || ~isgraphics(obj.CtrlPanel), return; end
            h = obj.ControlHeight / max(1,obj.containerHeight());
            h = min(max(h,0.02),0.6);
            obj.CtrlPanel.Position = [0 0 1 h];
            obj.PlotPanel.Position = [0 h 1 1-h];
        end

        function px = containerHeight(obj)
            c = obj.Container;
            oldU = c.Units; c.Units = 'pixels';
            px = c.Position(4);
            c.Units = oldU;
        end

        function buildControls(obj)
            % Two rows: WHAT is measured on top, WHERE it is plotted below.
            % Aesthetics are deliberately not here -- they are on the axes
            % context menu, which is where the pointer already is when the
            % operator decides a series is the wrong colour.
            p  = obj.CtrlPanel;
            y2 = 31; y1 = 5;                 % row baselines, px

            x = 8;
            [~,x] = obj.addText(p,'Metric:',x,y2,44);
            [obj.Ctrl.metric,x] = obj.addPopup(p,obj.metricItems(),x,y2,176, ...
                @() obj.onMetricControl(), ...
                'What to compute for each stimulus condition.');

            x = x + 8;
            [~,x] = obj.addText(p,'Window (ms):',x,y2,76);
            [obj.Ctrl.w0,x] = obj.addEdit(p,x,y2,42,@() obj.onWindowControl(), ...
                'Start of the analysis window, ms re stimulus onset.');
            [~,x] = obj.addText(p,'to',x,y2,16);
            [obj.Ctrl.w1,x] = obj.addEdit(p,x,y2,42,@() obj.onWindowControl(), ...
                'End of the analysis window, ms re stimulus onset.');

            x = x + 8;
            [~,x] = obj.addText(p,'Every (s):',x,y2,58);
            [obj.Ctrl.interval,x] = obj.addEdit(p,x,y2,42, ...
                @() obj.onIntervalControl(), ...
                sprintf('Refresh interval, %g to %g s.', ...
                    mabr.ui.MetricPlot.MinInterval,mabr.ui.MetricPlot.MaxInterval));

            x = 8;
            [~,x] = obj.addText(p,'X axis:',x,y1,44);
            [obj.Ctrl.xparam,x] = obj.addPopup(p,{'Auto'},x,y1,148, ...
                @() obj.onXControl(), ...
                'Which stimulus parameter runs along the X axis.');

            x = x + 8;
            [~,x] = obj.addText(p,'Series:',x,y1,44);
            [obj.Ctrl.series,x] = obj.addPopup(p,{'Auto'},x,y1,148, ...
                @() obj.onSeriesControl(), ...
                'Parameter separating the lines (or the second axis of a map).');

            x = x + 8;
            [obj.Ctrl.refresh,x] = obj.addButton(p,'Refresh',x,y1,66, ...
                @() obj.refresh(),'Recompute and redraw now.');

            x = x + 8;
            obj.Ctrl.status = obj.addText(p,'',x,y1,240);

            obj.syncControls();
        end

        function [h,x] = addText(~,p,txt,x,y,w)
            h = uicontrol(p,'Style','text','String',txt,'Units','pixels', ...
                'Position',[x y w 16],'HorizontalAlignment','left', ...
                'BackgroundColor',p.BackgroundColor);
            x = x + w + 3;
        end

        function [h,x] = addPopup(~,p,items,x,y,w,fcn,tip)
            h = uicontrol(p,'Style','popupmenu','String',items,'Units','pixels', ...
                'Position',[x y-1 w 20],'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        function [h,x] = addEdit(~,p,x,y,w,fcn,tip)
            h = uicontrol(p,'Style','edit','String','','Units','pixels', ...
                'Position',[x y w 20],'BackgroundColor','w', ...
                'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        function [h,x] = addButton(~,p,txt,x,y,w,fcn,tip)
            h = uicontrol(p,'Style','pushbutton','String',txt,'Units','pixels', ...
                'Position',[x y w 22],'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        % --- Control-strip callbacks -----------------------------------------
        function items = metricItems(obj)
            % The metric menu: the built-ins, then the custom one if a file has
            % been adopted, then the picker. Two entries rather than one so
            % re-selecting the metric you already loaded does not reopen a file
            % dialog -- the same shape mabr.ui.App's advance menu uses.
            C = mabr.metrics.online.catalog();
            items = cellfun(@(n,u) mabr.ui.MetricPlot.metricLabel(n,u), ...
                {C.Name},{C.Units},'UniformOutput',false);
            if ~isempty(obj.CustomFcn)
                items{end+1} = ['Custom: ' obj.CustomName];
            end
            items{end+1} = 'Custom function…';
        end

        function onMetricControl(obj)
            C = mabr.metrics.online.catalog();
            v = obj.Ctrl.metric.Value;
            nBuiltin = numel(C);
            if v <= nBuiltin
                obj.Metric = C(v).Key;
            elseif ~isempty(obj.CustomFcn) && v == nBuiltin+1
                obj.Metric = 'custom';
            else
                obj.chooseCustomMetric();
            end
        end

        function chooseCustomMetric(obj)
            % Pick a .m file, resolve it, and accept it only if it meets the
            % contract. On cancel or rejection the menu goes back to what was
            % selected before, so the picker item is never left standing as
            % the live value.
            [fn,pn] = uigetfile({'*.m','MATLAB function (*.m)'}, ...
                'Select a custom metric function');
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), figure(obj.Figure); end
            if isequal(fn,0), obj.syncControls(); return; end

            file = fullfile(pn,fn);
            [dn,name] = fileparts(file);
            if ~isempty(dn) && ~any(strcmp(dn,regexp(path,pathsep,'split')))
                addpath(dn);
            end
            try
                obj.setCustomMetric(str2func(name),name);
            catch me
                obj.alert(sprintf(['"%s" is not a valid online metric.\n\n%s\n\n' ...
                    'A metric takes one context struct and returns a single ' ...
                    'number. Copy +mabr/+metrics/+online/custom_template.m to ' ...
                    'get the contract right.'],name,me.message),'Invalid metric');
                obj.syncControls();
            end
        end

        function onWindowControl(obj)
            w0 = str2double(obj.Ctrl.w0.String);
            w1 = str2double(obj.Ctrl.w1.String);
            if ~isfinite(w0) || ~isfinite(w1) || w1 <= w0
                obj.syncControls();      % refuse it; put the old values back
                return
            end
            obj.Window = [w0 w1];
        end

        function onIntervalControl(obj)
            v = str2double(obj.Ctrl.interval.String);
            if ~isfinite(v) || v <= 0, obj.syncControls(); return; end
            obj.UpdateInterval = v;      % the setter clamps
        end

        function onXControl(obj)
            items = cellstr(obj.Ctrl.xparam.String);
            v = items{obj.Ctrl.xparam.Value};
            if strcmp(v,'Auto'), obj.XParam = ''; else, obj.XParam = v; end
        end

        function onSeriesControl(obj)
            items = cellstr(obj.Ctrl.series.String);
            v = items{obj.Ctrl.series.Value};
            switch v
                case 'Auto', obj.SeriesParam = '';
                case 'None', obj.SeriesParam = 'none';
                otherwise,   obj.SeriesParam = v;
            end
        end

        function syncControls(obj)
            % Push the settings back into the strip. Called after every change,
            % programmatic ones included, so the controls always state what the
            % window is actually doing.
            if ~isfield(obj.Ctrl,'metric') || ~isgraphics(obj.Ctrl.metric), return; end

            items = obj.metricItems();
            C     = mabr.metrics.online.catalog();
            if strcmp(obj.Metric,'custom') && ~isempty(obj.CustomFcn)
                v = numel(C)+1;
            else
                v = find(strcmp({C.Key},obj.Metric),1);
                if isempty(v), v = 1; end
            end
            obj.Ctrl.metric.String = items;
            obj.Ctrl.metric.Value  = min(v,numel(items));

            obj.Ctrl.w0.String       = num2str(obj.Window(1),'%g');
            obj.Ctrl.w1.String       = num2str(obj.Window(2),'%g');
            obj.Ctrl.interval.String = num2str(obj.UpdateInterval,'%g');

            names = mabr.ui.MetricPlot.paramNames(obj.conditions());
            obj.setPopup(obj.Ctrl.xparam,[{'Auto','Stimulus'} names], ...
                mabr.ui.MetricPlot.xLabelFor(obj.XParam));
            obj.setPopup(obj.Ctrl.series,[{'Auto','None'} names], ...
                mabr.ui.MetricPlot.seriesLabelFor(obj.SeriesParam));
        end

        function setPopup(~,h,items,value)
            if ~isgraphics(h), return; end
            h.String = items;
            i = find(strcmp(items,value),1);
            if isempty(i), i = 1; end
            h.Value = i;
        end

        function afterSettingChange(obj)
            if ~obj.Built, return; end
            obj.syncControls();
            obj.savePrefs();
            obj.syncMenus();
            obj.pushJob();
            obj.render(true);
        end

        % --- The metrics worker -------------------------------------------------
        function pushJob(obj)
            % Tell the worker what this window measures: the metric (a
            % catalog index, or the custom function itself over the queue),
            % the analysis window, and how often it is read. A change here
            % is answered a cycle later; until then the old answer is not
            % drawn under the new name (see workerValues).
            if isempty(obj.Slot) || isempty(obj.Controller) || ~isvalid(obj.Controller) ...
                    || isempty(obj.Controller.Compute) || ~isvalid(obj.Controller.Compute)
                return
            end
            ce = obj.Controller.Compute;
            if strcmp(obj.Metric,'custom') && ~isempty(obj.CustomFcn)
                ce.setCustomMetric(obj.Slot,obj.CustomFcn);
                idx = mabr.compute.RequestBuffer.Custom;
            else
                C   = mabr.metrics.online.catalog();
                idx = find(strcmp({C.Key},obj.Metric),1);
                if isempty(idx), idx = 1; end
            end
            obj.LastWorker = [];
            ce.setJob(obj.Slot,idx,obj.Window);
            ce.setSlotPeriod(obj.Slot,obj.UpdateInterval);
        end

        function releaseSlot(obj)
            if isempty(obj.Slot), return; end
            if ~isempty(obj.Controller) && isvalid(obj.Controller) ...
                    && ~isempty(obj.Controller.Compute) && isvalid(obj.Controller.Compute)
                obj.Controller.Compute.releaseSlot(obj.Slot);
            end
            obj.Slot       = [];
            obj.LastWorker = [];
        end

        function [V,decided] = workerValues(obj)
            % What the worker has for this window, and whether the worker
            % path DECIDED the answer (even when that answer is "nothing
            % yet"): false sends the caller to the in-process evaluation.
            %
            % Stale is not absent. No new publish means the last one stays
            % on screen with a note; only a worker that is gone (never
            % launched, or given up on) sends the metric back in-process.
            % Two things never come back in-process: a metric that hung the
            % worker (the slot is flagged, and evaluating it here would hang
            % the window -- the one outcome the worker exists to prevent),
            % and a custom metric while the worker is alive.
            V = []; decided = false;
            obj.WorkerNote = '';
            if isempty(obj.Slot) || isempty(obj.Controller) || ~isvalid(obj.Controller) ...
                    || isempty(obj.Controller.Compute) || ~isvalid(obj.Controller.Compute)
                return
            end
            ce = obj.Controller.Compute;
            if ce.isStalled(obj.Slot)
                obj.WorkerNote = 'this metric hung the analysis worker — choose another';
                V = obj.LastWorker;
                if isempty(V), V = mabr.ui.MetricPlot.emptyValues(); end
                decided = true;
                return
            end
            W = ce.values(obj.Slot);
            if isempty(W) || ~W.Current
                if ~ce.hasMetrics(), return; end          % gone: in-process
                if ~isempty(obj.LastWorker)
                    V = obj.LastWorker;
                    obj.WorkerNote = 'waiting for the analysis worker';
                    decided = true;
                elseif strcmp(obj.Metric,'custom')
                    V = mabr.ui.MetricPlot.emptyValues();
                    decided = true;
                end
                return
            end
            V = mabr.ui.MetricPlot.fromWorker(W);
            if W.Age > 3*obj.UpdateInterval + 2
                obj.WorkerNote = sprintf('analysis worker %.0f s behind',W.Age);
            end
            obj.LastWorker = V;
            decided = true;
        end

        % --- Timer -------------------------------------------------------------
        function startTicker(obj)
            obj.Ticker = timer('Tag','MABR_MetricPlot', ...
                'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                'Period',obj.UpdateInterval,'TasksToExecute',Inf, ...
                'TimerFcn',@(~,~) obj.onTick());
            start(obj.Ticker);
        end

        function restartTicker(obj)
            if isempty(obj.Ticker) || ~isvalid(obj.Ticker), return; end
            obj.stopTicker();
            obj.Ticker.Period = obj.UpdateInterval;
            start(obj.Ticker);
        end

        function stopTicker(obj)
            try
                if ~isempty(obj.Ticker) && isvalid(obj.Ticker) ...
                        && strcmp(obj.Ticker.Running,'on')
                    stop(obj.Ticker);
                end
            catch %#ok<CTCH>
            end
        end

        function onTick(obj)
            % Wrapped so a transient error never kills the window's clock --
            % the rule the live tick follows, for the same reason.
            try
                if ~obj.isvalidView(), obj.stopTicker(); return; end
                obj.refresh();
            catch me
                mabr.log.vprintf(2,1,'Metric plot tick error: %s',me.message);
            end
        end

        function pullLive(obj)
            if isempty(obj.Controller) || ~isvalid(obj.Controller)
                obj.LiveConds = mabr.ui.MetricPlot.emptyStore();
                return
            end
            obj.setLive(obj.Controller.liveSnapshot(),obj.Controller.Stimuli);
        end

        function onBlockReady(obj,e)
            try
                obj.addBlock(e.Info.block);
            catch me
                mabr.log.vprintf(2,1,'Metric plot could not take a block: %s',me.message);
            end
        end

        % --- Metric evaluation --------------------------------------------------
        function e = metricEntry(obj)
            % The metric in force: a catalog entry, or the custom function
            % dressed as one so everything downstream treats them alike.
            if strcmp(obj.Metric,'custom') && ~isempty(obj.CustomFcn)
                name = obj.CustomName;
                if isempty(name), name = 'Custom metric'; end
                e = struct('Key','custom','Name',name,'Units','', ...
                    'Summary','User-supplied metric.','Fcn',obj.CustomFcn);
                return
            end
            try
                e = mabr.metrics.online.catalog(obj.Metric);
            catch %#ok<CTCH>
                e = mabr.metrics.online.catalog('rms');
            end
        end

        function V = computeValues(obj)
            % One number per condition: from the metrics worker where this
            % window holds a slot on one, else computed here. The two agree
            % by construction -- both run mabr.compute.evaluateJobs over a
            % table built by mabr.compute.ConditionStore.
            [V,decided] = obj.workerValues();
            obj.ServedByWorker = decided;
            if ~decided, V = obj.computeLocal(); end
        end

        function V = computeLocal(obj)
            % The in-process evaluation (public as localValues, so a test can
            % hold it against the worker's answer).
            C = obj.conditions();
            e = obj.metricEntry();
            V = struct('Key',{},'Label',{},'Params',{},'Value',{}, ...
                       'NumSweeps',{},'Live',{});
            job = struct('Name',e.Name,'Fcn',e.Fcn,'Window',obj.Window);
            [vals,errs] = mabr.compute.evaluateJobs(C,job);
            % A metric that throws costs its own point, not the window, and
            % says so ONCE per metric rather than on every refresh -- this runs
            % every second, and a log line per tick is a log nobody reads.
            if ~isempty(errs{1}) && ~strcmp(obj.WarnedMetric,e.Name)
                obj.WarnedMetric = e.Name;
                mabr.log.vprintf(0,1,'Metric "%s" errored (%s); showing gaps.', ...
                    e.Name,errs{1});
            end
            for i = 1:numel(C)
                V(end+1) = struct('Key',C(i).Key,'Label',C(i).Label, ...
                    'Params',C(i).Params,'Value',vals(1,i), ...
                    'NumSweeps',size(C(i).Sweeps,2),'Live',C(i).Live); %#ok<AGROW>
            end
        end

        % --- Rendering ----------------------------------------------------------
        function render(obj,force)
            % Redraw from the current values. A refresh whose values are the
            % ones already on screen draws nothing (the status line still
            % ticks): between runs every open window would otherwise rebuild
            % its axes, legend and all, once a second for no change -- and
            % with several windows open that queue of pointless redraws can
            % outrun the thread that has to drain it. A setting change
            % forces the redraw, since the ink changed even if the numbers
            % did not.
            if nargin < 2, force = false; end
            if ~obj.isvalidView() || obj.Rendering, return; end
            obj.Rendering = true;
            guard = onCleanup(@() obj.endRender()); %#ok<NASGU>
            ax = obj.Axes;
            V  = obj.computeValues();
            if ~force && obj.Drawn && isequaln(V,obj.LastValues) ...
                    && strcmp(obj.WorkerNote,obj.DrawnNote)
                obj.setStatus(obj.statusText());
                return
            end
            obj.LastValues = V;
            obj.DrawnNote  = obj.WorkerNote;
            obj.Drawn      = true;
            obj.Note = '';

            cla(ax,'reset');
            set(ax,'NextPlot','add','Box','on');
            obj.applyTheme();

            e = obj.metricEntry();
            if isempty(V)
                obj.dropColorbar();
                obj.emptyMessage(e);
                obj.attachMenus();
                obj.setStatus('waiting for the first sweeps');
                return
            end

            names = mabr.ui.MetricPlot.paramNames(V);
            [xname,sname] = obj.axesChoice(names);
            ptype = obj.resolvePlotType(xname,sname);

            switch ptype
                case {'line','scatter'}
                    obj.drawLines(V,xname,sname,e,strcmp(ptype,'scatter'));
                case 'bar'
                    obj.drawBars(V,xname,sname);
                otherwise
                    ptype = obj.drawMap(V,xname,sname,e,ptype);
            end

            if ~any(strcmp(ptype,{'heatmap','contour','surface'}))
                % cla('reset') empties the axes but leaves a colorbar standing
                % -- it belongs to the figure, not the axes -- and a stale one
                % keeps the axes shrunk to make room for a scale that no longer
                % describes anything on it.
                obj.dropColorbar();
            end
            obj.noteHiddenParams(names,xname,sname,ptype);
            obj.decorate(V,xname,sname,e,ptype);
            obj.attachMenus();
            obj.setStatus(obj.statusText());
        end

        function [xname,sname] = axesChoice(obj,names)
            % Which parameter is the X axis, and which separates the series.
            % 'Auto' (the empty string) means the first parameter that varies,
            % then the second -- the arrangement that needs no explanation when
            % a frequency x level series is what is running. An explicit
            % choice, including "None" for the series, is always obeyed.
            xname = obj.XParam;
            if isempty(xname)
                if isempty(names), xname = 'Stimulus'; else, xname = names{1}; end
            elseif ~strcmp(xname,'Stimulus') && ~any(strcmp(xname,names))
                xname = 'Stimulus';        % the bank changed under the window
            end

            sname = obj.SeriesParam;
            if isempty(sname)
                rest = names(~strcmp(names,xname));
                if isempty(rest) || strcmp(xname,'Stimulus')
                    sname = 'none';
                else
                    sname = rest{1};
                end
            elseif ~strcmp(sname,'none') && ...
                    (~any(strcmp(sname,names)) || strcmp(sname,xname))
                sname = 'none';
            end
        end

        function dropColorbar(obj)
            if ~isprop(obj.Axes,'Colorbar'), return; end
            cb = obj.Axes.Colorbar;
            if ~isempty(cb) && isgraphics(cb), delete(cb); end
        end

        function noteHiddenParams(obj,names,xname,sname,ptype)
            % Say so when a parameter is varying but has no axis to vary along.
            % What happens to it differs by plot: a map AVERAGES the conditions
            % that share a cell, while a line simply draws them on top of one
            % another -- two different things, and neither is something to let
            % the reader discover from a point that looks lower than it should.
            % A more specific caveat (the map fallback) already standing wins:
            % it is the one that explains what is on screen.
            if ~isempty(obj.Note) || strcmp(xname,'Stimulus'), return; end
            extra = numel(names) - 1 - double(~strcmp(sname,'none'));
            if extra < 1, return; end
            if any(strcmp(ptype,{'heatmap','contour','surface'}))
                obj.Note = sprintf('%d further parameter(s) averaged into each cell',extra);
            else
                obj.Note = sprintf('%d further parameter(s) not distinguished',extra);
            end
        end

        function ptype = resolvePlotType(obj,xname,sname)
            ptype = obj.PlotType;
            if strcmp(ptype,'auto')
                if strcmp(xname,'Stimulus'), ptype = 'bar'; else, ptype = 'line'; end
                return
            end
            if any(strcmp(ptype,{'heatmap','contour','surface'})) && ...
                    (strcmp(xname,'Stimulus') || strcmp(sname,'none'))
                % A map needs two numeric axes. Say why, rather than drawing
                % something that looks like one and is not.
                obj.Note = ['a ' ptype ' needs two parameters — showing lines'];
                ptype = 'line';
            end
        end

        % --- Plot forms ---------------------------------------------------------
        function drawLines(obj,V,xname,sname,e,symbolsOnly)
            ax = obj.Axes;
            [x,xticks_,xlabels] = obj.xValues(V,xname);
            v    = [V.Value];
            live = logical([V.Live]);
            [~,sidx,slabels] = obj.seriesLevels(V,sname,e);
            col = obj.seriesColors(slabels);
            st  = obj.Style;

            h = gobjects(1,0);
            for k = 1:numel(slabels)
                m = sidx == k;
                if ~any(m), continue; end
                [xs,ord] = sort(x(m));
                vs = v(m);    vs = vs(ord);
                ls = live(m); ls = ls(ord);

                ls_style = st.LineStyle;
                if symbolsOnly, ls_style = 'none'; end
                h(end+1) = plot(ax,xs,vs,'LineStyle',ls_style, ...
                    'LineWidth',st.LineWidth,'Marker',st.Marker, ...
                    'MarkerSize',st.MarkerSize,'Color',col(k,:), ...
                    'MarkerFaceColor',col(k,:),'DisplayName',slabels{k}); %#ok<AGROW>

                % In-progress conditions get a hollow ring over the filled
                % marker. Drawn as a legend-less overlay so the series keeps
                % one handle, one colour, and one legend entry.
                if any(ls)
                    plot(ax,xs(ls),vs(ls),'LineStyle','none', ...
                        'Marker',mabr.ui.MetricPlot.ringMarker(st.Marker), ...
                        'MarkerSize',st.MarkerSize+3, ...
                        'MarkerEdgeColor',col(k,:),'MarkerFaceColor','none', ...
                        'LineWidth',st.LineWidth,'HandleVisibility','off');
                end
            end
            obj.applyValueLabels(x,v);
            obj.applyTicks(xname,xticks_,xlabels);
            obj.applyLegend(h,sname);
        end

        function drawBars(obj,V,xname,sname)
            ax = obj.Axes;
            [x,xticks_,xlabels] = obj.xValues(V,xname);
            v = [V.Value];
            [~,sidx,slabels] = obj.seriesLevels(V,sname,obj.metricEntry());
            col = obj.seriesColors(slabels);

            if numel(slabels) <= 1
                bar(ax,x,v,0.7,'FaceColor',col(1,:),'EdgeColor','none');
                obj.applyLegend(gobjects(1,0),'none');
            else
                xu = unique(x(isfinite(x)));
                M  = nan(numel(xu),numel(slabels));
                for i = 1:numel(V)
                    c = find(xu == x(i),1);
                    if ~isempty(c), M(c,sidx(i)) = v(i); end
                end
                hb = bar(ax,xu,M,'EdgeColor','none');
                for k = 1:numel(hb)
                    hb(k).FaceColor   = col(k,:);
                    hb(k).DisplayName = slabels{k};
                end
                obj.applyLegend(hb,sname);
            end
            obj.applyValueLabels(x,v);
            obj.applyTicks(xname,xticks_,xlabels);
        end

        function ptype = drawMap(obj,V,xname,sname,e,ptype)
            ax = obj.Axes;
            x  = arrayfun(@(c) mabr.ui.MetricPlot.paramValue(c,xname),V);
            y  = arrayfun(@(c) mabr.ui.MetricPlot.paramValue(c,sname),V);
            v  = [V.Value];

            [Z,xu,yu] = mabr.ui.MetricPlot.gridValues(x,y,v);
            if numel(xu) < 2 || numel(yu) < 2
                % Not a grid yet. Early in a schedule this is the normal state,
                % so fall back to the readable form and say why.
                obj.Note = 'not enough conditions for a map yet — showing lines';
                obj.drawLines(V,xname,sname,e,false);
                ptype = 'line';
                return
            end

            switch ptype
                case 'heatmap'
                    % Indexed axes with the real values as tick labels: drawing
                    % a heat map on a false linear spacing would restate an
                    % octave-spaced frequency series as an even one.
                    im = imagesc(ax,1:numel(xu),1:numel(yu),Z);
                    set(im,'AlphaData',~isnan(Z));
                    ax.YDir  = 'normal';
                    ax.XTick = 1:numel(xu);
                    ax.YTick = 1:numel(yu);
                    ax.XTickLabel = mabr.ui.MetricPlot.numLabels(xu);
                    ax.YTickLabel = mabr.ui.MetricPlot.numLabels(yu);
                case 'contour'
                    contourf(ax,xu,yu,Z,obj.Style.ContourLevels, ...
                        'LineColor',[0.25 0.25 0.25]);
                case 'surface'
                    s = surf(ax,xu,yu,Z);
                    shading(ax,obj.Style.Shading);
                    if strcmp(obj.Style.Shading,'faceted')
                        s.EdgeColor = [0.3 0.3 0.3];
                    end
                    view(ax,obj.Style.View);
                    zlabel(ax,mabr.ui.MetricPlot.metricLabel(e.Name,e.Units), ...
                        'Color',obj.foreground());
            end

            colormap(ax,obj.colormapValues());
            cb = colorbar(ax);
            cb.Label.String   = mabr.ui.MetricPlot.metricLabel(e.Name,e.Units);
            cb.Label.FontSize = obj.Style.FontSize;
            cb.Color          = obj.foreground();
        end

        % --- Shared drawing helpers ---------------------------------------------
        function [x,xticks_,xlabels] = xValues(~,V,xname)
            xticks_ = []; xlabels = {};
            if strcmp(xname,'Stimulus')
                x = 1:numel(V);
                xticks_ = x;
                xlabels = {V.Label};
            else
                x = arrayfun(@(c) mabr.ui.MetricPlot.paramValue(c,xname),V);
            end
        end

        function [levels,sidx,slabels] = seriesLevels(~,V,sname,e)
            if strcmp(sname,'none')
                levels  = 1;
                sidx    = ones(1,numel(V));
                slabels = {e.Name};
                return
            end
            s = arrayfun(@(c) mabr.ui.MetricPlot.paramValue(c,sname),V);
            levels = unique(s(isfinite(s)));
            if isempty(levels), levels = NaN; end
            sidx = ones(1,numel(V));
            for i = 1:numel(V)
                j = find(levels == s(i),1);
                if ~isempty(j), sidx(i) = j; end
            end
            slabels = arrayfun(@(u) sprintf('%s = %g',sname,u),levels, ...
                'UniformOutput',false);
        end

        function col = seriesColors(obj,slabels)
            n   = max(1,numel(slabels));
            col = mabr.ui.MetricPlot.paletteColors(obj.Style.Palette,n);
            % A colour the operator set by hand for a NAMED series wins, and
            % keeps winning as conditions appear around it.
            for k = 1:numel(slabels)
                f = matlab.lang.makeValidName(slabels{k});
                if isfield(obj.Style.SeriesColors,f)
                    col(k,:) = obj.Style.SeriesColors.(f);
                end
            end
        end

        function applyTicks(obj,xname,xticks_,xlabels)
            if isempty(xticks_), return; end
            ax = obj.Axes;
            ax.XTick = xticks_;
            ax.XTickLabel = xlabels;
            if numel(xlabels) > 4, ax.XTickLabelRotation = 30; end
            if strcmp(xname,'Stimulus'), ax.XLim = [0.4 numel(xticks_)+0.6]; end
        end

        function applyLegend(obj,h,sname)
            ax  = obj.Axes;
            old = get(ax,'Legend');
            if ~isempty(old) && isgraphics(old), delete(old); end
            if strcmp(obj.Style.Legend,'off') || isempty(h) || strcmp(sname,'none')
                return
            end
            lg = legend(ax,h(isgraphics(h)),'Location',obj.Style.Legend);
            lg.Box      = 'on';
            lg.FontSize = max(7,obj.Style.FontSize-1);
            title(lg,sname);
            if strcmp(obj.Style.Theme,'dark')
                lg.Color     = [0.15 0.15 0.17];
                lg.TextColor = [0.92 0.92 0.92];
                lg.EdgeColor = [0.40 0.40 0.45];
            end
        end

        function applyValueLabels(obj,x,v)
            if ~obj.Style.ShowValues, return; end
            ax = obj.Axes;
            for i = 1:numel(v)
                if ~isfinite(v(i)) || ~isfinite(x(i)), continue; end
                text(ax,x(i),v(i),sprintf('  %.3g',v(i)), ...
                    'FontSize',max(7,obj.Style.FontSize-2), ...
                    'VerticalAlignment','bottom','Clipping','on', ...
                    'Color',obj.foreground());
            end
        end

        function decorate(obj,V,xname,sname,e,ptype)
            ax = obj.Axes;
            fg = obj.foreground();
            set(ax,'FontSize',obj.Style.FontSize,'XColor',fg,'YColor',fg,'ZColor',fg);

            isMap = any(strcmp(ptype,{'heatmap','contour','surface'}));
            title(ax,e.Name,'Color',fg,'FontSize',obj.Style.FontSize+2);
            subtitle(ax,obj.subtitleText(V),'Color',mabr.ui.MetricPlot.dim(fg), ...
                'FontSize',max(7,obj.Style.FontSize-1));

            xlabel(ax,xname,'Color',fg);
            if isMap
                ylabel(ax,sname,'Color',fg);
            else
                ylabel(ax,mabr.ui.MetricPlot.metricLabel(e.Name,e.Units),'Color',fg);
            end

            switch obj.Style.Grid
                case 'none', grid(ax,'off');
                case 'x',    grid(ax,'off'); ax.XGrid = 'on';
                case 'y',    grid(ax,'off'); ax.YGrid = 'on';
                otherwise,   grid(ax,'on');
            end

            if isMap, return; end

            ax.XScale = obj.Style.XScale;
            ax.YScale = obj.Style.YScale;
            if strcmp(obj.Style.YLimMode,'manual') && obj.Style.YLim(2) > obj.Style.YLim(1)
                ax.YLim = obj.Style.YLim;
            end

            % One condition per parameter value makes for a cramped axis; a
            % little air keeps the end points off the box.
            if ~strcmp(xname,'Stimulus') && ~strcmp(ptype,'bar') ...
                    && strcmp(ax.XScale,'linear')
                x = arrayfun(@(c) mabr.ui.MetricPlot.paramValue(c,xname),V);
                x = x(isfinite(x));
                if numel(unique(x)) > 1
                    pad = 0.05*(max(x)-min(x));
                    ax.XLim = [min(x)-pad max(x)+pad];
                end
            end
        end

        function emptyMessage(obj,e)
            ax = obj.Axes;
            fg = obj.foreground();
            text(ax,0.5,0.5,'Waiting for the first completed sweeps…', ...
                'Units','normalized','HorizontalAlignment','center', ...
                'Color',mabr.ui.MetricPlot.dim(fg),'FontSize',obj.Style.FontSize+1);
            title(ax,e.Name,'Color',fg,'FontSize',obj.Style.FontSize+2);
            ylabel(ax,mabr.ui.MetricPlot.metricLabel(e.Name,e.Units),'Color',fg);
            set(ax,'XTick',[],'YTick',[],'FontSize',obj.Style.FontSize, ...
                'XColor',fg,'YColor',fg);
        end

        function txt = subtitleText(obj,V)
            nLive = nnz([V.Live]);
            parts = {sprintf('%g–%g ms',obj.Window(1),obj.Window(2)), ...
                     sprintf('%d condition%s',numel(V), ...
                        mabr.ui.MetricPlot.plural(numel(V))), ...
                     sprintf('%d sweeps',sum([V.NumSweeps]))};
            if nLive > 0
                parts{end+1} = sprintf('%d acquiring (hollow)',nLive);
            end
            if ~isempty(obj.Note),       parts{end+1} = obj.Note;       end
            if ~isempty(obj.WorkerNote), parts{end+1} = obj.WorkerNote; end
            txt = strjoin(parts,'  ·  ');
        end

        function txt = statusText(obj)
            txt = sprintf('updated %s · every %g s', ...
                char(datetime('now','Format','HH:mm:ss')),obj.UpdateInterval);
        end

        function endRender(obj)
            if isvalid(obj), obj.Rendering = false; end
        end

        function setStatus(obj,txt)
            if isfield(obj.Ctrl,'status') && isgraphics(obj.Ctrl.status)
                obj.Ctrl.status.String = txt;
            end
        end

        function applyTheme(obj)
            if strcmp(obj.Style.Theme,'dark')
                bg = [0.12 0.12 0.14];
            else
                bg = [1 1 1];
            end
            obj.Axes.Color = bg;
            if isgraphics(obj.PlotPanel), obj.PlotPanel.BackgroundColor = bg; end
            if ~isempty(obj.Figure) && isgraphics(obj.Figure)
                obj.Figure.Color = bg;
            end
        end

        function fg = foreground(obj)
            if strcmp(obj.Style.Theme,'dark')
                fg = [0.92 0.92 0.94];
            else
                fg = [0.15 0.15 0.15];
            end
        end

        function m = colormapValues(obj)
            m = mabr.ui.MetricPlot.colormapByName(obj.Style.Colormap);
            if obj.Style.ReverseMap, m = flipud(m); end
        end

        % --- Context menus (every aesthetic lives here) --------------------------
        function buildMenus(obj)
            f  = ancestor(obj.PlotPanel,'figure');
            cm = uicontextmenu(f);
            obj.Menu = cm;
            M = struct();

            M.plot  = uimenu(cm,'Text','Plot type');
            types   = mabr.ui.MetricPlot.plotTypes();
            names   = mabr.ui.MetricPlot.plotTypeNames();
            M.plotItems = gobjects(1,numel(types));
            for k = 1:numel(types)
                M.plotItems(k) = uimenu(M.plot,'Text',names{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setSetting('PlotType',types{k}));
            end

            M.palette = uimenu(cm,'Text','Series palette');
            pals = mabr.ui.MetricPlot.paletteNames();
            M.paletteItems = gobjects(1,numel(pals));
            for k = 1:numel(pals)
                M.paletteItems(k) = uimenu(M.palette,'Text',pals{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('Palette',pals{k}));
            end
            M.seriesColor = uimenu(M.palette,'Text','Set series colour…','Separator','on');
            uimenu(M.palette,'Text','Clear custom series colours', ...
                'MenuSelectedFcn',@(~,~) obj.setStyleField('SeriesColors',struct()));

            M.cmap = uimenu(cm,'Text','Colormap (maps)');
            maps = mabr.ui.MetricPlot.colormapNames();
            M.cmapItems = gobjects(1,numel(maps));
            for k = 1:numel(maps)
                M.cmapItems(k) = uimenu(M.cmap,'Text',maps{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('Colormap',maps{k}));
            end
            M.reverse = uimenu(M.cmap,'Text','Reverse','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.toggleStyleField('ReverseMap'));

            M.marker = uimenu(cm,'Text','Marker');
            mk = mabr.ui.MetricPlot.Markers;
            M.markerItems = gobjects(1,numel(mk));
            for k = 1:numel(mk)
                M.markerItems(k) = uimenu(M.marker,'Text',mk{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('Marker',mk{k}));
            end
            uimenu(M.marker,'Text','Size…','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.askNumber('MarkerSize','Marker size (points)'));

            M.line = uimenu(cm,'Text','Line');
            ls = mabr.ui.MetricPlot.LineStyles;
            M.lineItems = gobjects(1,numel(ls));
            for k = 1:numel(ls)
                M.lineItems(k) = uimenu(M.line,'Text',ls{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('LineStyle',ls{k}));
            end
            uimenu(M.line,'Text','Width…','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.askNumber('LineWidth','Line width (points)'));

            M.grid = uimenu(cm,'Text','Grid');
            gs = mabr.ui.MetricPlot.Grids;
            M.gridItems = gobjects(1,numel(gs));
            for k = 1:numel(gs)
                M.gridItems(k) = uimenu(M.grid,'Text',gs{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('Grid',gs{k}));
            end

            M.legend = uimenu(cm,'Text','Legend');
            lg = mabr.ui.MetricPlot.legendLocations();
            M.legendItems = gobjects(1,numel(lg));
            for k = 1:numel(lg)
                M.legendItems(k) = uimenu(M.legend,'Text',lg{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('Legend',lg{k}));
            end

            M.axes = uimenu(cm,'Text','Axes');
            M.xlog = uimenu(M.axes,'Text','Log X', ...
                'MenuSelectedFcn',@(~,~) obj.toggleScale('XScale'));
            M.ylog = uimenu(M.axes,'Text','Log Y', ...
                'MenuSelectedFcn',@(~,~) obj.toggleScale('YScale'));
            M.yauto = uimenu(M.axes,'Text','Y limits: auto','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.setStyleField('YLimMode','auto'));
            M.ymanual = uimenu(M.axes,'Text','Y limits…', ...
                'MenuSelectedFcn',@(~,~) obj.askYLim());
            M.values = uimenu(M.axes,'Text','Label each point','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.toggleStyleField('ShowValues'));

            M.font = uimenu(cm,'Text','Font size');
            sizes = mabr.ui.MetricPlot.FontSizes;
            M.fontItems = gobjects(1,numel(sizes));
            for k = 1:numel(sizes)
                M.fontItems(k) = uimenu(M.font,'Text',num2str(sizes(k)), ...
                    'MenuSelectedFcn',@(~,~) obj.setStyleField('FontSize',sizes(k)));
            end

            M.theme = uimenu(cm,'Text','Theme');
            M.themeLight = uimenu(M.theme,'Text','Light', ...
                'MenuSelectedFcn',@(~,~) obj.setStyleField('Theme','light'));
            M.themeDark = uimenu(M.theme,'Text','Dark', ...
                'MenuSelectedFcn',@(~,~) obj.setStyleField('Theme','dark'));

            uimenu(cm,'Text','Copy data to clipboard','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.copyData());
            uimenu(cm,'Text','Export data (CSV)…', ...
                'MenuSelectedFcn',@(~,~) obj.exportData());
            uimenu(cm,'Text','Save image…', ...
                'MenuSelectedFcn',@(~,~) obj.saveImage());
            uimenu(cm,'Text','Copy plot to a new figure', ...
                'MenuSelectedFcn',@(~,~) obj.popOut());
            uimenu(cm,'Text','Reset aesthetics','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.setSetting('Style', ...
                    mabr.ui.MetricPlot.defaultStyle()));

            obj.MenuItems = M;
            obj.syncMenus();
        end

        function attachMenus(obj)
            % cla('reset') drops the axes' menu, and every new child needs it
            % too, so that right-clicking a line, a bar, or the surface itself
            % opens the same menu the bare axes does.
            if isempty(obj.Menu) || ~isgraphics(obj.Menu), return; end
            obj.Axes.ContextMenu = obj.Menu;
            kids = obj.Axes.Children;
            for k = 1:numel(kids)
                try, kids(k).ContextMenu = obj.Menu; end %#ok<TRYNC>
            end
            obj.refreshSeriesColorMenu();
        end

        function refreshSeriesColorMenu(obj)
            % The per-series colour submenu is the one menu that depends on the
            % data, so it is rebuilt from whatever the last render drew.
            if ~isfield(obj.MenuItems,'seriesColor') || ...
                    ~isgraphics(obj.MenuItems.seriesColor), return; end
            m = obj.MenuItems.seriesColor;
            delete(m.Children);
            V = obj.LastValues;
            if isempty(V), m.Enable = 'off'; return; end
            names = mabr.ui.MetricPlot.paramNames(V);
            [~,sname] = obj.axesChoice(names);
            [~,~,slabels] = obj.seriesLevels(V,sname,obj.metricEntry());
            m.Enable = 'on';
            for k = 1:numel(slabels)
                uimenu(m,'Text',slabels{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.pickSeriesColor(slabels{k}));
            end
        end

        function syncMenus(obj)
            % Tick whatever is in force. Every submenu is a radio group except
            % the toggles, which are checkmarks in their own right.
            M = obj.MenuItems;
            if isempty(fieldnames(M)), return; end
            s = obj.Style;
            mabr.ui.MetricPlot.check(M.plotItems, ...
                mabr.ui.MetricPlot.plotTypes(),obj.PlotType);
            mabr.ui.MetricPlot.check(M.paletteItems, ...
                mabr.ui.MetricPlot.paletteNames(),s.Palette);
            mabr.ui.MetricPlot.check(M.cmapItems, ...
                mabr.ui.MetricPlot.colormapNames(),s.Colormap);
            mabr.ui.MetricPlot.check(M.markerItems, ...
                mabr.ui.MetricPlot.Markers,s.Marker);
            mabr.ui.MetricPlot.check(M.lineItems, ...
                mabr.ui.MetricPlot.LineStyles,s.LineStyle);
            mabr.ui.MetricPlot.check(M.gridItems, ...
                mabr.ui.MetricPlot.Grids,s.Grid);
            mabr.ui.MetricPlot.check(M.legendItems, ...
                mabr.ui.MetricPlot.legendLocations(),s.Legend);
            mabr.ui.MetricPlot.check(M.fontItems, ...
                arrayfun(@num2str,mabr.ui.MetricPlot.FontSizes, ...
                    'UniformOutput',false),num2str(s.FontSize));
            M.reverse.Checked    = onOffState(s.ReverseMap);
            M.xlog.Checked       = onOffState(strcmp(s.XScale,'log'));
            M.ylog.Checked       = onOffState(strcmp(s.YScale,'log'));
            M.values.Checked     = onOffState(s.ShowValues);
            M.yauto.Checked      = onOffState(strcmp(s.YLimMode,'auto'));
            M.ymanual.Checked    = onOffState(strcmp(s.YLimMode,'manual'));
            M.themeLight.Checked = onOffState(strcmp(s.Theme,'light'));
            M.themeDark.Checked  = onOffState(strcmp(s.Theme,'dark'));
        end

        function setSetting(obj,name,value)
            obj.(name) = value;      % the setter re-renders and saves
        end

        function setStyleField(obj,field,value)
            s = obj.Style;
            s.(field) = value;
            obj.Style = s;
        end

        function toggleStyleField(obj,field)
            s = obj.Style;
            s.(field) = ~s.(field);
            obj.Style = s;
        end

        function toggleScale(obj,field)
            s = obj.Style;
            if strcmp(s.(field),'log'), s.(field) = 'linear'; else, s.(field) = 'log'; end
            obj.Style = s;
        end

        function pickSeriesColor(obj,label)
            f = matlab.lang.makeValidName(label);
            s = obj.Style;
            if isfield(s.SeriesColors,f), c0 = s.SeriesColors.(f); else, c0 = [0 0.4 0.8]; end
            c = uisetcolor(c0,['Colour for ' label]);
            if isequal(c,0) || numel(c) ~= 3, return; end
            s.SeriesColors.(f) = c;
            obj.Style = s;
        end

        function askNumber(obj,field,prompt)
            a = inputdlg({prompt},'Online analysis',1,{num2str(obj.Style.(field),'%g')});
            if isempty(a), return; end
            v = str2double(a{1});
            if ~isfinite(v) || v <= 0, return; end
            obj.setStyleField(field,v);
        end

        function askYLim(obj)
            ax = obj.Axes;
            a = inputdlg({'Y minimum','Y maximum'},'Y limits',1, ...
                {num2str(ax.YLim(1),'%g'),num2str(ax.YLim(2),'%g')});
            if isempty(a), return; end
            lo = str2double(a{1}); hi = str2double(a{2});
            if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, return; end
            s = obj.Style;
            s.YLim     = [lo hi];
            s.YLimMode = 'manual';
            obj.Style  = s;
        end

        % --- Taking the numbers away ---------------------------------------------
        function copyData(obj)
            T = obj.dataTable();
            if isempty(T), return; end
            try
                clipboard('copy',mabr.ui.MetricPlot.tableText(T));
                obj.setStatus('copied to the clipboard');
            catch me
                obj.alert(['Could not copy: ' me.message],'Copy failed');
            end
        end

        function exportData(obj)
            T = obj.dataTable();
            if isempty(T), obj.alert('Nothing to export yet.','No data'); return; end
            [fn,pn] = uiputfile({'*.csv','Comma-separated values (*.csv)'}, ...
                'Export metric values',['metric_' obj.Metric '.csv']);
            if isequal(fn,0), return; end
            writetable(T,fullfile(pn,fn));
            obj.setStatus(['exported to ' fn]);
        end

        function saveImage(obj)
            [fn,pn] = uiputfile({'*.png','PNG image (*.png)'; ...
                                 '*.pdf','PDF (*.pdf)'; ...
                                 '*.tif','TIFF (*.tif)'},'Save plot', ...
                                 ['metric_' obj.Metric '.png']);
            if isequal(fn,0), return; end
            exportgraphics(obj.Axes,fullfile(pn,fn),'Resolution',200, ...
                'BackgroundColor',obj.Axes.Color);
            obj.setStatus(['saved ' fn]);
        end

        function popOut(obj)
            % A STATIC copy, deliberately: something to annotate and keep while
            % this window carries on updating underneath it.
            f  = figure('Name',[obj.Title ' (copy)'],'NumberTitle','off', ...
                'Color',obj.Axes.Color);
            ax = copyobj(obj.Axes,f);
            mabr.ui.hideAxesToolbar(ax);
            ax.Units       = 'normalized';
            ax.Position    = [0.13 0.13 0.775 0.75];
            ax.ContextMenu = [];
        end

        function alert(obj,msg,titleTxt)
            if ~isempty(obj.Figure) && isgraphics(obj.Figure)
                uiwait(msgbox(msg,titleTxt,'warn','modal'));
            else
                warning('mabr:ui:MetricPlot:alert','%s',msg);
            end
        end

        function savePrefs(obj)
            % The look AND the last analysis choice, so the next window opens
            % where this one left off. Guarded: a rig with no writable prefs
            % must not lose a window over it.
            try
                setpref(mabr.ui.MetricPlot.PrefGroup,mabr.ui.MetricPlot.PrefKey, ...
                    struct('Style',obj.Style,'Metric',obj.Metric, ...
                           'PlotType',obj.PlotType,'Window',obj.Window, ...
                           'UpdateInterval',obj.UpdateInterval));
            catch %#ok<CTCH>
            end
        end
    end

    % =====================================================================
    methods (Static)
        function t = plotTypes()
            t = {'auto','line','scatter','bar','heatmap','contour','surface'};
        end

        function n = plotTypeNames()
            n = {'Auto','Line + symbols','Symbols only','Bar', ...
                 'Heat map','Contour','Surface'};
        end

        function s = defaultStyle()
            % Every visual decision in one struct, so a window's look is one
            % value to save, restore, reset, or copy to another window.
            s = struct( ...
                'Palette','lines', 'Colormap','parula', 'ReverseMap',false, ...
                'SeriesColors',struct(), ...
                'LineStyle','-', 'LineWidth',1.5, 'Marker','o', 'MarkerSize',7, ...
                'Grid','both', 'Legend','northeast', 'FontSize',10, ...
                'Theme','light', 'ShowValues',false, ...
                'XScale','linear', 'YScale','linear', ...
                'YLimMode','auto', 'YLim',[0 1], ...
                'Shading','faceted', 'View',[-37.5 30], 'ContourLevels',12);
        end

        function d = loadDefaults()
            % What a NEW window opens with: the look and the analysis choice
            % last used. Defensive field by field, the rule every loadPrefs in
            % MABR follows -- a pref written by an older version is missing
            % whatever has been added since, and must not stop a window opening.
            d = struct('Style',mabr.ui.MetricPlot.defaultStyle(), ...
                'Metric','rms','PlotType','auto','Window',[0 10], ...
                'UpdateInterval',1);
            try
                if ~ispref(mabr.ui.MetricPlot.PrefGroup,mabr.ui.MetricPlot.PrefKey)
                    return
                end
                p = getpref(mabr.ui.MetricPlot.PrefGroup,mabr.ui.MetricPlot.PrefKey);
                if ~isstruct(p), return; end
                if isfield(p,'Style'), d.Style = mabr.ui.MetricPlot.fillStyle(p.Style); end
                if isfield(p,'Metric') && ischar(p.Metric) && ~strcmp(p.Metric,'custom')
                    % A custom metric cannot be restored -- the file it came
                    % from is not remembered, and silently falling back to a
                    % DIFFERENT number under the same name would be worse than
                    % opening on the default one.
                    d.Metric = p.Metric;
                end
                if isfield(p,'PlotType') && any(strcmp(p.PlotType, ...
                        mabr.ui.MetricPlot.plotTypes()))
                    d.PlotType = p.PlotType;
                end
                if isfield(p,'Window') && numel(p.Window) == 2 && ...
                        all(isfinite(p.Window)) && p.Window(2) > p.Window(1)
                    d.Window = p.Window(:)';
                end
                if isfield(p,'UpdateInterval') && isscalar(p.UpdateInterval) ...
                        && isfinite(p.UpdateInterval) && p.UpdateInterval > 0
                    d.UpdateInterval = p.UpdateInterval;
                end
            catch %#ok<CTCH>
            end
        end
    end

    methods (Static, Access = private)
        % The condition table -- its shape, its merge rule, and how a Block
        % or a live snapshot becomes a row of it -- is
        % mabr.compute.ConditionStore's, shared with the metrics worker. The
        % three helpers the drawing code leans on stay reachable under their
        % old names so nothing below has to know where they went.
        function s = emptyStore()
            s = mabr.compute.ConditionStore.empty();
        end

        function V = emptyValues()
            V = struct('Key',{},'Label',{},'Params',{},'Value',{}, ...
                       'NumSweeps',{},'Live',{});
        end

        function V = fromWorker(W)
            % A ComputeEngine.values() answer as the struct array the drawing
            % code takes -- the same shape localValues builds.
            V = mabr.ui.MetricPlot.emptyValues();
            for i = 1:numel(W.Keys)
                p = struct();
                if i <= numel(W.Params) && isstruct(W.Params{i}), p = W.Params{i}; end
                V(end+1) = struct('Key',char(W.Keys{i}),'Label',char(W.Keys{i}), ...
                    'Params',p,'Value',W.Values(i),'NumSweeps',W.NumSweeps(i), ...
                    'Live',logical(W.Live(i))); %#ok<AGROW>
            end
        end

        function names = paramNames(C)
            names = mabr.compute.ConditionStore.paramNames(C);
        end

        function v = paramValue(c,name)
            v = mabr.compute.ConditionStore.paramValue(c,name);
        end

        function [Z,xu,yu] = gridValues(x,y,v)
            % One cell per (x,y) pair; duplicates average (that is how a third
            % parameter collapses), and a pair with no condition stays NaN so a
            % half-finished grid is drawn as a hole rather than a zero somebody
            % could read as a measurement.
            xu = unique(x(isfinite(x)));
            yu = unique(y(isfinite(y)));
            Z  = nan(numel(yu),numel(xu));
            N  = zeros(size(Z));
            for i = 1:numel(v)
                c = find(xu == x(i),1);
                r = find(yu == y(i),1);
                if isempty(c) || isempty(r) || ~isfinite(v(i)), continue; end
                if isnan(Z(r,c)), Z(r,c) = 0; end
                Z(r,c) = Z(r,c) + v(i);
                N(r,c) = N(r,c) + 1;
            end
            Z(N > 0) = Z(N > 0)./N(N > 0);
        end

        function c = paletteColors(name,n)
            switch lower(name)
                case 'parula', c = mabr.ui.MetricPlot.spread(@parula,n);
                case 'turbo',  c = mabr.ui.MetricPlot.spread(@turbo,n);
                case 'cool',   c = mabr.ui.MetricPlot.spread(@cool,n);
                case 'copper', c = mabr.ui.MetricPlot.spread(@copper,n);
                case 'winter', c = mabr.ui.MetricPlot.spread(@winter,n);
                case 'gray',   c = mabr.ui.MetricPlot.spread(@(m) gray(m)*0.85,n);
                otherwise,     c = lines(max(n,7));
            end
            c = c(1:max(n,1),:);
        end

        function c = spread(fcn,n)
            % n colours spread across the WHOLE map, not the first n of 64 --
            % three conditions should look different, not like three shades of
            % dark blue.
            m   = fcn(max(n,2)+2);
            idx = round(linspace(1,size(m,1),max(n,1)));
            c   = m(idx,:);
        end

        function p = paletteNames()
            p = {'lines','parula','turbo','cool','copper','winter','gray'};
        end

        function m = colormapNames()
            m = {'parula','turbo','jet','hot','cool','bone','gray'};
        end

        function m = colormapByName(name)
            switch lower(name)
                case 'turbo', m = turbo(256);
                case 'jet',   m = jet(256);
                case 'hot',   m = hot(256);
                case 'cool',  m = cool(256);
                case 'bone',  m = bone(256);
                case 'gray',  m = gray(256);
                otherwise,    m = parula(256);
            end
        end

        function l = legendLocations()
            l = {'off','northeast','northwest','southeast','southwest', ...
                 'eastoutside','best'};
        end

        function check(items,values,current)
            % Tick exactly the one that matches; items are in `values` order.
            for k = 1:numel(items)
                if ~isgraphics(items(k)), continue; end
                items(k).Checked = onOffState(k <= numel(values) && ...
                    strcmp(values{k},current));
            end
        end

        function s = fillStyle(v)
            d = mabr.ui.MetricPlot.defaultStyle();
            s = d;
            if ~isstruct(v), return; end
            f = fieldnames(d);
            for k = 1:numel(f)
                if isfield(v,f{k}) && ~isempty(v.(f{k}))
                    s.(f{k}) = v.(f{k});
                end
            end
            if ~isstruct(s.SeriesColors), s.SeriesColors = struct(); end
        end

        function txt = metricLabel(name,units)
            if isempty(units)
                txt = name;
            else
                txt = sprintf('%s (%s)',name,units);
            end
        end

        function m = ringMarker(m)
            % A hollow overlay needs a marker that HAS an interior; '.' and
            % 'none' do not, so an in-progress point would be invisible.
            if any(strcmp(m,{'.','none','*','+','x'})), m = 'o'; end
        end

        function v = xLabelFor(v)
            if isempty(v), v = 'Auto'; end
        end

        function v = seriesLabelFor(v)
            if isempty(v)
                v = 'Auto';
            elseif strcmp(v,'none')
                v = 'None';
            end
        end

        function L = numLabels(u)
            L = arrayfun(@(x) num2str(x,'%g'),u(:),'UniformOutput',false);
        end

        function c = dim(fg)
            c = fg*0.6 + 0.25;
        end

        function s = plural(n)
            if n == 1, s = ''; else, s = 's'; end
        end

        function txt = tableText(T)
            % Tab-separated with a header: what a spreadsheet expects off the
            % clipboard.
            names = T.Properties.VariableNames;
            rows  = cell(height(T)+1,1);
            rows{1} = strjoin(names,sprintf('\t'));
            for i = 1:height(T)
                cells = cell(1,numel(names));
                for k = 1:numel(names)
                    v = T{i,k};
                    if iscell(v), v = v{1}; end
                    if ischar(v) || isstring(v)
                        cells{k} = char(v);
                    else
                        cells{k} = num2str(double(v),'%g');
                    end
                end
                rows{i+1} = strjoin(cells,sprintf('\t'));
            end
            txt = strjoin(rows,newline);
        end
    end
end

% ======================= local helpers ================================
function s = onOffState(tf)
if tf, s = 'on'; else, s = 'off'; end
end
