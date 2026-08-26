classdef TraceInspector < handle
% mabr.ui.TraceInspector  Detailed peak picker for a single trace.
%
%   Opened by double-clicking a trace in mabr.ui.TraceOrganizer (or from its
%   Peaks menu, or with "i"). The organizer stacks many traces at one shared
%   normalization, which is what makes a level series legible -- and what
%   makes any single waveform too small to measure. The inspector shows ONE
%   trace at full size in its own units, with the tools to put wave markers
%   where they actually belong.
%
%       insp = mabr.ui.TraceInspector(trace);            % a mabr.ui.Trace
%       insp = mabr.ui.TraceInspector(trace,@onApply);   % ...and notify a caller
%
%   Waves are rows in a table: a name, a search window in ms relative to the
%   stimulus onset (the trace's own time base starts at onset), and whether
%   the feature wanted there is a peak or a trough. Auto-detect fills every
%   enabled row with the most prominent extremum inside its window; whatever
%   it gets wrong is then dragged, clicked, or nudged into place. A marker is
%   free to leave its window once placed -- the window is a search hint, not
%   a cage, and a latency that fell outside the window you guessed is a
%   measurement, not an error.
%
%   Opening the inspector runs Auto-detect on whatever is not ALREADY placed,
%   so a trace with no picks yet shows peaks immediately rather than a blank
%   waveform waiting for a button press. A pick already there -- seeded from
%   the trace's own markers, or left from an earlier pass -- is never
%   overwritten by this; only a wave still unplaced is touched.
%
%   NOTHING is written back to the trace until Apply & Close, which transfers
%   the marked waves to Trace.setMarkers (sample indices plus wave names, so
%   they survive rescaling and a .torg round-trip) and calls the apply
%   callback so the organizer can redraw. Cancel leaves the trace untouched.
%   Reopening the inspector on a trace that already carries markers seeds the
%   table from them, so a second pass edits the first rather than starting
%   over.
%
%   The search windows persist in MATLAB prefs (group 'MABR') on Apply, so a
%   lab that works at one species and one rate sets its windows once.
%
%     Auto-detect (a)      fill every enabled wave from its window
%     click on the trace   place the selected wave (snaps to the nearest
%                          local extremum within SnapWindow ms)
%     drag a marker        move it freely, sample by sample
%     Left / Right         nudge the selected wave 1 sample (Shift: 10)
%     Delete               clear the selected wave
%     c / f                clear all / fit the view
%     Enter / Escape       apply & close / cancel
%     F1                   this list
%
%   Smoothing is display-and-detection only: markers are stored as indices
%   into the trace's own samples, so what transfers is a position on the real
%   waveform however heavily the view was smoothed to find it.
%
%   See also mabr.ui.TraceOrganizer, mabr.ui.Trace, mabr.metrics.find_peaks.
%
% Daniel Stolzberg (c) 2026

    properties
        SmoothSpan   (1,1) double {mustBeNonnegative,mustBeFinite} = 0;    % samples, 0 = off
        SnapWindow   (1,1) double {mustBeNonnegative,mustBeFinite} = 0.25; % ms
        DisplayScale (1,1) double {mustBePositive,mustBeFinite}    = 1e6;  % V -> uV
        DisplayUnit  (1,:) char = 'µV';
    end

    properties (SetAccess = private)
        Trace                      % the mabr.ui.Trace being inspected (shared handle)
        % Spelled out rather than calling emptyWaves(): a property default
        % that calls a static method of its own class is evaluated during
        % that class's initialization.
        Waves (1,:) struct = struct('Name',{},'Enabled',{},'TMin',{}, ...
                                    'TMax',{},'Type',{},'Loc',{});
        Applied (1,1) logical = false;   % did the user transfer the peaks?
    end

    properties (SetAccess = private, Transient)
        Figure                     % readable so callers can export the view
        Axes
    end

    properties (Constant, Access = private)
        PrefKey  = 'TraceInspectorWaves';
        WinColor = [0.30 0.45 0.70];
        SelColor = [0.85 0.10 0.10];
        PanelW   = 368;            % what the wave table needs, in pixels
    end

    properties (Access = private, Transient)
        H = struct();              % all the widget handles, in one place
        Markers (1,:) mabr.ui.Marker = mabr.ui.Marker.empty;
        WinShapes = gobjects(1,0); % window patches + their name labels
        ApplyFcn
        SelRow  = [];              % selected wave row, or []
        dragIdx = [];
        Fitted (1,1) logical = false;
    end

    methods
        function obj = TraceInspector(tr,applyFcn)
            if nargin < 1 || isempty(tr) || ~isa(tr,'mabr.ui.Trace') || ~isvalid(tr)
                error('mabr:ui:TraceInspector:badTrace', ...
                    'A valid mabr.ui.Trace is required.');
            end
            if numel(tr.Data) < 3
                error('mabr:ui:TraceInspector:noData', ...
                    'Trace "%s" has no waveform to inspect.',tr.DisplayName);
            end
            obj.Trace = tr;
            if nargin >= 2, obj.ApplyFcn = applyFcn; end
            obj.Waves = obj.loadWaves();
            obj.seedFromTrace();
            obj.build();
            % Anything still unplaced after seeding from the trace's own
            % markers has never been picked at all -- detect just those, so
            % opening on a fresh trace shows peaks immediately rather than a
            % blank waveform waiting for a button press, without disturbing a
            % mark this trace (or an earlier pass) already carried.
            toDetect = find([obj.Waves.Enabled] & isnan([obj.Waves.Loc]));
            if isempty(toDetect)
                obj.redraw();
            else
                obj.autoDetect(toDetect);
            end
        end

        function delete(obj)
            delete(obj.Markers);
            delete(obj.WinShapes(isgraphics(obj.WinShapes)));
            try, delete(obj.Figure); end %#ok<TRYNC>
        end

        function tf = isopen(obj)
            tf = ~isempty(obj.Figure) && isgraphics(obj.Figure);
        end

        function show(obj)
            % Raise the window, rebuilding it if it was closed -- the wave
            % table outlives its figure, so reopening resumes where the last
            % pass left off.
            if ~obj.isopen()
                obj.build();
                obj.redraw();
            end
            figure(obj.Figure);
        end

        % --- Peak picking ----------------------------------------------------
        function autoDetect(obj,idx)
            % Fill each enabled wave with the most prominent extremum inside
            % its own search window.
            if nargin < 2 || isempty(idx), idx = find([obj.Waves.Enabled]); end
            n = 0;
            for i = idx(:)'
                if ~obj.Waves(i).Enabled, continue; end
                if obj.detectOne(i), n = n + 1; end
            end
            obj.redraw();
            obj.status(sprintf('Auto-detect: %d of %d wave(s) found.',n,numel(idx)));
        end

        function setWaveTime(obj,i,tms,snap)
            % Place wave i at time tms (ms). With snap true the position is
            % pulled to the nearest local extremum of the right sign within
            % SnapWindow ms -- clicking "near enough" is how a peak is
            % actually picked by hand.
            if nargin < 4, snap = false; end
            if ~obj.validWave(i), return; end
            k = obj.nearestSample(tms);
            if snap, k = obj.snapToExtremum(k,obj.Waves(i).Type); end
            obj.Waves(i).Loc     = k;
            obj.Waves(i).Enabled = true;
            obj.redraw();
        end

        function nudgeWave(obj,i,delta)
            if ~obj.validWave(i), return; end
            if isnan(obj.Waves(i).Loc)
                obj.status(sprintf('Wave %s is not placed yet.',obj.Waves(i).Name));
                return
            end
            obj.Waves(i).Loc = min(max(obj.Waves(i).Loc+delta,1),numel(obj.Trace.Data));
            obj.redraw();
        end

        function tf = setWindow(obj,i,t0,t1,type)
            % Redefine wave i's search window (ms re onset), and optionally
            % what it is looking for. Returns false for a window that runs
            % backwards, which is the one way to get this wrong.
            tf = false;
            if ~obj.validWave(i), return; end
            if ~isfinite(t0) || ~isfinite(t1) || t1 <= t0
                obj.status('Window start must be below its end.');
                return
            end
            obj.Waves(i).TMin = double(t0);
            obj.Waves(i).TMax = double(t1);
            if nargin >= 5 && ~isempty(type)
                obj.Waves(i).Type = obj.mkWave('x',true,0,1,type).Type;
            end
            obj.redraw();
            tf = true;
        end

        function enableWave(obj,i,tf)
            % A disabled row keeps its window and its pick but takes no part
            % in auto-detect, the plot, or the transfer.
            if ~obj.validWave(i), return; end
            obj.Waves(i).Enabled = logical(tf);
            obj.redraw();
        end

        function clearWave(obj,i)
            if ~obj.validWave(i), return; end
            obj.Waves(i).Loc = NaN;
            obj.redraw();
        end

        function clearAll(obj)
            for i = 1:numel(obj.Waves), obj.Waves(i).Loc = NaN; end
            obj.redraw();
            obj.status('All waves cleared.');
        end

        function addWave(obj,name,t0,t1,type)
            % Add a row beyond the default I-V (a trough between two waves, a
            % late component, whatever this preparation actually shows).
            if nargin < 2 || isempty(name), name = sprintf('P%d',numel(obj.Waves)+1); end
            if nargin < 3 || isempty(t0),   t0 = obj.Axes.XLim(1); end
            if nargin < 4 || isempty(t1),   t1 = t0 + 1;           end
            if nargin < 5 || isempty(type), type = 'Peak';         end
            obj.Waves(end+1) = obj.mkWave(name,true,t0,t1,type);
            obj.redraw();
        end

        % --- Transfer ---------------------------------------------------------
        function n = transfer(obj)
            % Write the placed waves onto the organizer's Trace, in temporal
            % order, as sample indices + names. This is the only thing in here
            % that touches the trace at all.
            n = 0;
            if isempty(obj.Trace) || ~isvalid(obj.Trace), return; end
            [locs,names] = obj.markedWaves();
            obj.Trace.setMarkers(locs,names);
            n = numel(locs);
            if ~isempty(obj.ApplyFcn)
                % The callback redraws someone else's window; a failure there
                % must not lose the peaks the user just spent time placing.
                try
                    obj.ApplyFcn();
                catch me
                    mabr.log.vprintf(2,1,'TraceInspector apply callback failed: %s',me.message);
                end
            end
        end

        function apply(obj)
            % The trace can have been removed from the organizer while this
            % window sat open; transfer() says so by writing nothing.
            name = '(removed trace)';
            if ~isempty(obj.Trace) && isvalid(obj.Trace), name = obj.Trace.DisplayName; end
            n = obj.transfer();
            obj.saveWaves();
            obj.Applied = true;
            mabr.log.vprintf(2,'Trace inspector: %d marker(s) transferred to "%s"',n,name);
            obj.close();
        end

        function cancel(obj)
            obj.Applied = false;
            obj.close();
        end

        function close(obj)
            if obj.isopen()
                mabr.ui.WindowPos.remember(obj.Figure,'TraceInspector');
            end
            delete(obj.Markers);
            obj.Markers = mabr.ui.Marker.empty;
            delete(obj.WinShapes(isgraphics(obj.WinShapes)));
            obj.WinShapes = gobjects(1,0);
            try, delete(obj.Figure); end %#ok<TRYNC>
            obj.Figure = [];
            obj.Axes   = [];
            obj.H      = struct();
            obj.Fitted = false;   % a rebuilt axes has to be fitted again
        end

        % --- Results ----------------------------------------------------------
        function t = results(obj)
            % One row per placed wave: Name, Latency (ms), Amplitude (in
            % DisplayUnit), Type. A table, so it can go straight to a file.
            [locs,names] = obj.markedWaves();
            y = obj.workingY()*obj.DisplayScale;
            types = cell(numel(locs),1);
            for i = 1:numel(locs)
                j = find(strcmp({obj.Waves.Name},names{i}),1);
                types{i} = obj.Waves(j).Type;
            end
            t = table(names(:),obj.timeMs(locs(:)),y(locs(:)),types, ...
                'VariableNames',{'Wave','Latency_ms','Amplitude','Type'});
            t.Properties.VariableUnits = {'','ms',obj.DisplayUnit,''};
        end
    end

    % =====================================================================
    methods (Access = private)
        % --- Construction -----------------------------------------------------
        function build(obj)
            obj.Figure = figure('Name',sprintf('MABR Trace Inspector — %s', ...
                    obj.Trace.DisplayName), ...
                'NumberTitle','off','Color','w','MenuBar','none','ToolBar','none', ...
                'Position',[140 140 960 580], ...
                'CloseRequestFcn',@(~,~) obj.cancel(), ...
                'WindowButtonMotionFcn',@(~,~) obj.onMotion(), ...
                'WindowButtonUpFcn',@(~,~) obj.endDrag(), ...
                'WindowKeyPressFcn',@(~,e) obj.onKey(e), ...
                'WindowScrollWheelFcn',@(~,e) obj.onScroll(e), ...
                'SizeChangedFcn',@(~,~) obj.layout());
            mabr.ui.WindowPos.restore(obj.Figure,'TraceInspector', ...
                obj.Figure.Position,[860 500]);

            obj.Axes = axes('Parent',obj.Figure,'Units','pixels','Box','on', ...
                'NextPlot','add','XGrid','on','YGrid','on','GridLineStyle',':');
            mabr.ui.hideAxesToolbar(obj.Axes);
            xlabel(obj.Axes,'Time re stimulus onset (ms)');
            obj.Axes.ButtonDownFcn = @(~,~) obj.onAxesClick();

            % Drawn objects are PickableParts 'none' so a click anywhere in
            % the axes reaches the axes callback -- only the markers, which
            % have to be grabbable, stay pickable.
            obj.H.zero = line(obj.Axes,nan,nan,'Color',[0.85 0.85 0.85], ...
                'PickableParts','none');
            obj.H.raw  = line(obj.Axes,nan,nan,'Color',[0.72 0.76 0.80], ...
                'LineWidth',1,'PickableParts','none');
            obj.H.work = line(obj.Axes,nan,nan,'Color',obj.Trace.Color, ...
                'LineWidth',1.5,'PickableParts','none');

            obj.buildPanel();
            obj.layout();
        end

        function buildPanel(obj)
            p = uipanel('Parent',obj.Figure,'Units','pixels','BorderType','none', ...
                'BackgroundColor','w');
            obj.H.panel = p;

            obj.H.header = uicontrol(p,'Style','text','Units','pixels', ...
                'String',sprintf(['Waves — windows and latencies in ms re ' ...
                    'onset, amplitude in %s'],obj.DisplayUnit), ...
                'HorizontalAlignment','left','BackgroundColor','w', ...
                'FontWeight','bold');

            % Short headers and generous widths: a column whose title reads
            % "Late..." is worse than one called "Lat", and the units are
            % stated once, above.
            obj.H.table = uitable(p,'Units','pixels', ...
                'ColumnName',{'Wave','On','Start','End','Type','Lat','Amp'}, ...
                'ColumnFormat',{'char','logical','bank','bank', ...
                                {'Peak','Trough'},'char','char'}, ...
                'ColumnEditable',[true true true true true false false], ...
                'ColumnWidth',{48,34,52,52,62,48,50}, ...
                'RowName',[], ...
                'CellEditCallback',@(~,e) obj.onCellEdit(e), ...
                'CellSelectionCallback',@(~,e) obj.onCellSelect(e));

            obj.H.smoothLbl = obj.label(p,'Smooth (samples)');
            obj.H.smooth    = uicontrol(p,'Style','edit','Units','pixels', ...
                'String',num2str(obj.SmoothSpan),'BackgroundColor','w', ...
                'TooltipString',['Moving average over the trace for viewing and ' ...
                    'detection only. Markers are stored as sample indices, so ' ...
                    'nothing smoothed is ever transferred.'], ...
                'Callback',@(s,~) obj.onSmooth(s));
            obj.H.snapLbl   = obj.label(p,'Snap (ms)');
            obj.H.snap      = uicontrol(p,'Style','edit','Units','pixels', ...
                'String',num2str(obj.SnapWindow),'BackgroundColor','w', ...
                'TooltipString',['How far a click is pulled to the nearest local ' ...
                    'extremum. 0 places the marker exactly where you clicked.'], ...
                'Callback',@(s,~) obj.onSnap(s));

            obj.H.auto  = obj.button(p,'Auto-detect (a)', ...
                'Find the most prominent peak/trough inside each enabled window.', ...
                @() obj.autoDetect());
            obj.H.clear = obj.button(p,'Clear all (c)', ...
                'Unplace every wave. The search windows are kept.', ...
                @() obj.clearAll());
            obj.H.fit   = obj.button(p,'Fit view (f)', ...
                'Show the whole trace.',@() obj.fitView());
            obj.H.copy  = obj.button(p,'Copy table', ...
                'Copy the placed waves to the clipboard, tab-delimited.', ...
                @() obj.copyTable());

            obj.H.cursor = uicontrol(p,'Style','text','Units','pixels', ...
                'String','','HorizontalAlignment','left','BackgroundColor','w', ...
                'ForegroundColor',[0.35 0.35 0.35]);
            obj.H.summary = uicontrol(p,'Style','text','Units','pixels', ...
                'String','','HorizontalAlignment','left','BackgroundColor','w');

            obj.H.apply = obj.button(p,'Apply & Close', ...
                'Transfer the placed waves to the trace in the organizer.', ...
                @() obj.apply());
            obj.H.apply.FontWeight = 'bold';
            obj.H.apply.BackgroundColor = [0.72 0.90 0.72];
            obj.H.cancelBtn = obj.button(p,'Cancel', ...
                'Close without changing the trace.',@() obj.cancel());
            obj.H.help  = obj.button(p,'?','Keyboard shortcuts (F1)',@() obj.showHelp());
        end

        function h = label(~,parent,txt)
            h = uicontrol(parent,'Style','text','Units','pixels','String',txt, ...
                'HorizontalAlignment','left','BackgroundColor','w');
        end

        function h = button(~,parent,txt,tip,fcn)
            h = uicontrol(parent,'Style','pushbutton','Units','pixels', ...
                'String',txt,'TooltipString',tip,'Callback',@(~,~) fcn());
        end

        % --- Layout -----------------------------------------------------------
        function layout(obj)
            % Fires as a resize callback, which the figure issues while it is
            % still being built.
            if ~obj.isopen() || ~isfield(obj.H,'panel') || ~isgraphics(obj.H.panel)
                return
            end
            fp = getpixelposition(obj.Figure);
            fw = fp(3); fh = fp(4);
            m  = 10;
            pw = obj.PanelW;
            obj.H.panel.Position = [max(m,fw-pw-m), m, pw, max(120,fh-2*m)];
            obj.Axes.Position = [64, 58, max(120,fw-pw-3*m-64), max(100,fh-104)];
            obj.layoutPanel();
        end

        function layoutPanel(obj)
            pp = getpixelposition(obj.H.panel);
            w  = pp(3)-4;  x = 2;
            y  = 4;
            hb = 28;

            obj.H.apply.Position     = [x                     y round(w*0.50) hb];
            obj.H.cancelBtn.Position = [x+round(w*0.52)       y round(w*0.30) hb];
            obj.H.help.Position      = [x+round(w*0.855)      y round(w*0.14) hb];
            y = y + hb + 8;

            obj.H.summary.Position = [x y w 52];   y = y + 52 + 4;
            obj.H.cursor.Position  = [x y w 17];   y = y + 17 + 6;

            hw = round((w-6)/2);
            obj.H.fit.Position   = [x y hw 26];
            obj.H.copy.Position  = [x+hw+6 y hw 26];   y = y + 26 + 4;
            obj.H.auto.Position  = [x y hw 26];
            obj.H.clear.Position = [x+hw+6 y hw 26];   y = y + 26 + 8;

            obj.H.smoothLbl.Position = [x     y+3 100 16];
            obj.H.smooth.Position    = [x+104 y    44 22];
            obj.H.snapLbl.Position   = [x+158 y+3  62 16];
            obj.H.snap.Position      = [x+222 y    44 22];
            y = y + 22 + 10;

            top = pp(4) - 22;
            obj.H.header.Position = [x pp(4)-19 w 17];
            obj.H.table.Position  = [x y w max(60,top-y)];
        end

        % --- Drawing -----------------------------------------------------------
        function redraw(obj)
            if ~obj.isopen(), return; end
            t  = obj.timeMs();
            yr = double(obj.Trace.Data(:))*obj.DisplayScale;
            yw = obj.workingY()*obj.DisplayScale;

            % The raw trace stays visible under a smoothed view: smoothing is
            % a way to see a peak, not a claim about where it is.
            set(obj.H.raw,'XData',t,'YData',yr, ...
                'Visible',mabr.ui.Trace.onoff(obj.SmoothSpan > 1));
            set(obj.H.work,'XData',t,'YData',yw,'Color',obj.Trace.Color);
            set(obj.H.zero,'XData',[t(1) t(end)],'YData',[0 0]);

            if ~obj.Fitted
                obj.Axes.XLim = [t(1) t(end)];
                obj.Fitted = true;
            end
            f = isfinite(yw);
            if any(f), lo = min(yw(f)); hi = max(yw(f)); else, lo = -1; hi = 1; end
            if hi <= lo, lo = lo - 1; hi = hi + 1; end
            pad = 0.08*(hi-lo);
            obj.Axes.YLim = [lo-pad hi+pad];
            ylabel(obj.Axes,sprintf('Amplitude (%s)',obj.DisplayUnit));

            obj.drawWindows();
            obj.drawMarkers(yw);
            obj.refreshTable();
            obj.refreshSummary();
        end

        function drawWindows(obj)
            delete(obj.WinShapes(isgraphics(obj.WinShapes)));
            obj.WinShapes = gobjects(1,0);
            yl  = obj.Axes.YLim;
            big = [-1 -1 1 1]*max(abs(yl))*100;     % taller than any later YLim
            sh  = gobjects(1,0);
            for i = 1:numel(obj.Waves)
                w = obj.Waves(i);
                if ~w.Enabled, continue; end
                if i == obj.SelRow, a = 0.20; else, a = 0.07; end
                p = patch(obj.Axes,'XData',[w.TMin w.TMax w.TMax w.TMin], ...
                    'YData',big,'FaceColor',obj.WinColor,'FaceAlpha',a, ...
                    'EdgeColor','none','PickableParts','none');
                txt = text(obj.Axes,mean([w.TMin w.TMax]),yl(2),w.Name, ...
                    'HorizontalAlignment','center','VerticalAlignment','top', ...
                    'FontSize',8,'Color',obj.WinColor*0.8, ...
                    'Interpreter','none','PickableParts','none');
                sh = [sh p txt]; %#ok<AGROW>
            end
            obj.WinShapes = sh;
            % Behind the waveform: the windows are context, not content.
            if ~isempty(sh), uistack(sh,'bottom'); end
        end

        function drawMarkers(obj,yw)
            delete(obj.Markers);
            obj.Markers = mabr.ui.Marker.empty;
            t = obj.timeMs();
            for i = 1:numel(obj.Waves)
                w = obj.Waves(i);
                if ~w.Enabled || isnan(w.Loc), continue; end
                % Built undrawn so the style can be set first -- Marker.draw
                % reads the properties once, at draw time.
                m = mabr.ui.Marker([],t(w.Loc),yw(w.Loc),w.Name);
                if strcmpi(w.Type,'Trough'), m.Style = '^'; else, m.Style = 'v'; end
                if i == obj.SelRow
                    m.Color = obj.SelColor;  m.Size = 64;
                else
                    m.Color = obj.WinColor;  m.Size = 40;
                end
                m.draw(obj.Axes);
                m.MarkerHandle.ButtonDownFcn = @(~,~) obj.startDrag(i);
                m.LabelHandle.ButtonDownFcn  = @(~,~) obj.startDrag(i);
                obj.Markers(end+1) = m;
            end
        end

        function refreshTable(obj)
            if ~isfield(obj.H,'table') || ~isgraphics(obj.H.table), return; end
            n = numel(obj.Waves);
            d = cell(n,7);
            y = obj.workingY()*obj.DisplayScale;
            for i = 1:n
                w = obj.Waves(i);
                d(i,1:5) = {w.Name,w.Enabled,w.TMin,w.TMax,w.Type};
                if isnan(w.Loc)
                    d(i,6:7) = {'—','—'};
                else
                    d{i,6} = sprintf('%.2f',obj.timeMs(w.Loc));
                    d{i,7} = sprintf('%.3f',y(w.Loc));
                end
            end
            obj.H.table.Data = d;
        end

        function refreshSummary(obj)
            if ~isfield(obj.H,'summary') || ~isgraphics(obj.H.summary), return; end
            [locs,names] = obj.markedWaves();
            nEn = nnz([obj.Waves.Enabled]);
            s = {sprintf('%d of %d enabled wave(s) placed.',numel(locs),nEn),'',''};
            if numel(locs) >= 2
                lat = obj.timeMs(locs);
                d = arrayfun(@(k) sprintf('%s–%s %.2f',names{k},names{k+1}, ...
                    lat(k+1)-lat(k)),1:numel(locs)-1,'UniformOutput',false);
                s{2} = ['Interpeak: ' strjoin(d,'  ')];
                s{3} = sprintf('%s–%s %.2f ms overall',names{1},names{end}, ...
                    lat(end)-lat(1));
            end
            obj.H.summary.String = s;
        end

        function status(obj,txt)
            if obj.isopen()
                title(obj.Axes,txt,'FontWeight','normal','FontSize',9, ...
                    'Interpreter','none');
            end
        end

        % --- Detection ---------------------------------------------------------
        function tf = detectOne(obj,i)
            % Most prominent extremum of the right sign inside wave i's window.
            tf = false;
            w  = obj.Waves(i);
            t  = obj.timeMs();
            y  = obj.workingY();
            m  = find(t >= min(w.TMin,w.TMax) & t <= max(w.TMin,w.TMax));
            if isempty(m)
                obj.Waves(i).Loc = NaN;
                return
            end
            seg      = y(m);
            isTrough = strcmpi(w.Type,'Trough');
            k = [];
            if all(isfinite(seg))
                try
                    % find_peaks returns them in order of occurrence, but the
                    % one wanted inside a hand-drawn window is the most
                    % prominent, not merely the first -- hence the sort on p.
                    r = mabr.metrics.find_peaks(seg,5,isTrough);
                    if ~isempty(r.locs)
                        [~,b] = max(r.p);
                        k = r.locs(b);
                    end
                catch
                    k = [];   % too short a window for findpeaks
                end
            end
            if isempty(k)
                % A window can hold no local extremum at all: a monotonic
                % stretch, or a peak sitting exactly on the window edge. The
                % extremum of the segment is then the honest answer, and the
                % latency it reports is what tells the user to widen it.
                % min/max skip NaN of their own accord, which is the whole
                % reason this branch can take a window findpeaks refused.
                if isTrough, [~,k] = min(seg); else, [~,k] = max(seg); end
            end
            obj.Waves(i).Loc = m(k);
            tf = true;
        end

        function k = snapToExtremum(obj,k0,type)
            % Pull a click to the nearest local extremum within SnapWindow ms.
            k = k0;
            if obj.SnapWindow <= 0, return; end
            t  = obj.timeMs();
            y  = obj.workingY();
            m  = find(abs(t - t(k0)) <= obj.SnapWindow);
            if numel(m) < 2, return; end
            seg = y(m);
            if strcmpi(type,'Trough'), [~,b] = min(seg); else, [~,b] = max(seg); end
            k = m(b);
        end

        function k = nearestSample(obj,tms)
            [~,k] = min(abs(obj.timeMs() - tms));
        end

        function y = workingY(obj)
            % What the user is looking at, and therefore what detection runs
            % on -- picking a peak off one signal while showing another is the
            % kind of disagreement nobody catches until the numbers are wrong.
            y = double(obj.Trace.Data(:));
            if obj.SmoothSpan > 1, y = movmean(y,round(obj.SmoothSpan)); end
        end

        function t = timeMs(obj,idx)
            t = double(obj.Trace.Time(:))*1000;
            if nargin >= 2, t = t(idx); end
        end

        function [locs,names] = markedWaves(obj)
            % Placed waves in temporal order, so the markers a trace carries
            % read left to right whatever order the table is in.
            en = [obj.Waves.Enabled] & ~isnan([obj.Waves.Loc]);
            locs  = [obj.Waves(en).Loc];
            names = {obj.Waves(en).Name};
            [locs,ord] = sort(locs);
            names = names(ord);
        end

        function tf = validWave(obj,i)
            tf = ~isempty(i) && isscalar(i) && i >= 1 && i <= numel(obj.Waves);
        end

        % --- Interaction --------------------------------------------------------
        function startDrag(obj,i)
            obj.SelRow  = i;
            obj.dragIdx = i;
            obj.redraw();
        end

        function onMotion(obj)
            % Mouse motion is live from the moment the figure exists, which is
            % before the axes and the panel are on it.
            if ~obj.isopen() || isempty(obj.Axes) || ~isgraphics(obj.Axes), return; end
            cp = obj.Axes.CurrentPoint;
            if isempty(obj.dragIdx)
                % Only while the pointer is actually over the plot: the data
                % coordinates extrapolate happily across the whole figure, so
                % they cannot tell a reading from a mouse parked on the table.
                if obj.overAxes(), obj.showCursor(cp(1,1)); else, obj.showCursor([]); end
                return
            end
            k = obj.nearestSample(cp(1,1));
            obj.Waves(obj.dragIdx).Loc = k;
            % Move only the marker while dragging: a full redraw 60 times a
            % second would rebuild the table and every patch for nothing.
            m = obj.markerFor(obj.dragIdx);
            if ~isempty(m)
                y = obj.workingY()*obj.DisplayScale;
                m.move(obj.timeMs(k),y(k));
            end
            obj.showCursor(obj.timeMs(k));
        end

        function endDrag(obj)
            if isempty(obj.dragIdx), return; end
            i = obj.dragIdx;
            obj.dragIdx = [];
            obj.redraw();
            obj.status(sprintf('Wave %s at %.2f ms.',obj.Waves(i).Name, ...
                obj.timeMs(obj.Waves(i).Loc)));
        end

        function m = markerFor(obj,i)
            % Markers are drawn only for placed, enabled waves, so the i-th
            % wave is not the i-th marker.
            m = mabr.ui.Marker.empty;
            en = find([obj.Waves.Enabled] & ~isnan([obj.Waves.Loc]));
            j  = find(en == i,1);
            if ~isempty(j) && j <= numel(obj.Markers), m = obj.Markers(j); end
        end

        function onAxesClick(obj)
            if strcmp(get(obj.Figure,'SelectionType'),'alt'), return; end
            if isempty(obj.SelRow)
                obj.status('Select a wave row in the table, then click the trace.');
                return
            end
            cp = obj.Axes.CurrentPoint;
            obj.setWaveTime(obj.SelRow,cp(1,1),true);
            obj.status(sprintf('Wave %s placed at %.2f ms.',obj.Waves(obj.SelRow).Name, ...
                obj.timeMs(obj.Waves(obj.SelRow).Loc)));
        end

        function tf = overAxes(obj)
            p  = obj.Figure.CurrentPoint;       % figure pixels
            ax = obj.Axes.Position;             % pixels: set at construction
            tf = p(1) >= ax(1) && p(1) <= ax(1)+ax(3) && ...
                 p(2) >= ax(2) && p(2) <= ax(2)+ax(4);
        end

        function showCursor(obj,tms)
            if ~isfield(obj.H,'cursor') || ~isgraphics(obj.H.cursor), return; end
            xl = obj.Axes.XLim;
            if isempty(tms) || ~isfinite(tms) || tms < xl(1) || tms > xl(2)
                obj.H.cursor.String = '';
                return
            end
            k = obj.nearestSample(tms);
            y = obj.workingY()*obj.DisplayScale;
            obj.H.cursor.String = sprintf('t = %.2f ms      y = %.3f %s', ...
                obj.timeMs(k),y(k),obj.DisplayUnit);
        end

        function onCellSelect(obj,e)
            if isempty(e.Indices), return; end
            obj.SelRow = e.Indices(1);
            obj.redraw();
        end

        function onCellEdit(obj,e)
            i = e.Indices(1);
            c = e.Indices(2);
            if ~obj.validWave(i), return; end
            switch c
                case 1
                    v = strtrim(e.NewData);
                    if isempty(v), obj.refreshTable(); return; end
                    obj.Waves(i).Name = v;
                case 2
                    obj.Waves(i).Enabled = logical(e.NewData);
                case {3,4}
                    lim = [obj.Waves(i).TMin obj.Waves(i).TMax];
                    lim(c-2) = double(e.NewData);
                    if ~obj.setWindow(i,lim(1),lim(2))
                        obj.refreshTable();     % put the rejected value back
                        return
                    end
                    % An edited window does not move a marker already placed:
                    % re-detecting under the user's hand would undo the very
                    % adjustment they may have opened this window to protect.
                    obj.status(sprintf('Window changed — Auto-detect to re-find %s.', ...
                        obj.Waves(i).Name));
                case 5
                    obj.Waves(i).Type = e.NewData;
            end
            obj.SelRow = i;
            obj.redraw();
        end

        function onSmooth(obj,src)
            v = str2double(src.String);
            if ~isfinite(v) || v < 0
                src.String = num2str(obj.SmoothSpan);
                obj.status('Smoothing span must be 0 or more samples.');
                return
            end
            obj.SmoothSpan = v;
            obj.redraw();
        end

        function onSnap(obj,src)
            v = str2double(src.String);
            if ~isfinite(v) || v < 0
                src.String = num2str(obj.SnapWindow);
                obj.status('Snap window must be 0 ms or more.');
                return
            end
            obj.SnapWindow = v;
        end

        function onKey(obj,e)
            shift = any(strcmpi(e.Modifier,'shift'));
            step  = 1; if shift, step = 10; end
            switch lower(e.Key)
                case 'leftarrow',  obj.nudgeWave(obj.SelRow,-step);
                case 'rightarrow', obj.nudgeWave(obj.SelRow,+step);
                case {'delete','backspace'}
                    if ~isempty(obj.SelRow), obj.clearWave(obj.SelRow); end
                case 'a', obj.autoDetect();
                case 'c', obj.clearAll();
                case 'f', obj.fitView();
                case 'return', obj.apply();
                case 'escape', obj.cancel();
                case {'f1','help'}, obj.showHelp();
            end
        end

        function onScroll(obj,e)
            % Wheel zooms time about the cursor: the whole job here is reading
            % latencies off a few milliseconds of a ten-millisecond sweep.
            if ~obj.isopen(), return; end
            cp = obj.Axes.CurrentPoint;
            x  = cp(1,1);
            xl = obj.Axes.XLim;
            if x < xl(1) || x > xl(2), x = mean(xl); end
            f  = 1.15^double(e.VerticalScrollCount);
            nl = x + (xl - x)*f;
            if diff(nl) > 1e-4, obj.Axes.XLim = nl; end
        end

        function fitView(obj)
            t = obj.timeMs();
            obj.Axes.XLim = [t(1) t(end)];
            obj.Fitted = true;
            obj.redraw();
        end

        function copyTable(obj)
            r = obj.results();
            if isempty(r), obj.status('Nothing placed to copy.'); return; end
            lines = {sprintf('Wave\tLatency (ms)\tAmplitude (%s)\tType',obj.DisplayUnit)};
            for i = 1:height(r)
                lines{end+1} = sprintf('%s\t%.3f\t%.4f\t%s', ...
                    r{i,1}{1},r{i,2},r{i,3},r{i,4}{1}); %#ok<AGROW>
            end
            try
                clipboard('copy',strjoin(lines,newline));
                obj.status(sprintf('%d wave(s) copied to the clipboard.',height(r)));
            catch me
                obj.status(['Clipboard unavailable: ' me.message]);
            end
        end

        function showHelp(~)
            msg = { ...
                'Select a wave row in the table, then click the trace to place it.'
                'Drag a marker to move it. The search window is only a hint for'
                'Auto-detect -- a marker may sit anywhere on the trace.'
                ''
                'a                    auto-detect every enabled wave'
                'click on the trace   place the selected wave (snaps to a peak)'
                'Left / Right         nudge the selected wave 1 sample'
                'Shift+Left / Right   nudge 10 samples'
                'Delete               clear the selected wave'
                'c                    clear all waves'
                'f                    fit the view to the whole trace'
                'scroll wheel         zoom time about the cursor'
                'Enter                apply and close'
                'Escape               cancel'
                'F1                   this help' };
            helpdlg(msg,'Trace Inspector');
        end

        % --- Wave definitions ---------------------------------------------------
        function seedFromTrace(obj)
            % Markers already on the trace ARE waves: reopening the inspector
            % on a trace marked earlier must show what is there rather than a
            % blank sheet, so a second pass edits the first pass.
            locs = obj.Trace.MarkerLocs;
            if isempty(locs), return; end
            txt = obj.Trace.MarkerText;
            if numel(txt) < numel(locs), txt(end+1:numel(locs)) = {''}; end
            for i = 1:numel(locs)
                name = strtrim(txt{i});
                j = find(strcmpi({obj.Waves.Name},name),1);
                if isempty(j)
                    t0 = obj.timeMs(locs(i));
                    if isempty(name), name = sprintf('P%d',numel(obj.Waves)+1); end
                    obj.Waves(end+1) = obj.mkWave(name,true,t0-0.5,t0+0.5,'Peak');
                    j = numel(obj.Waves);
                end
                obj.Waves(j).Loc     = locs(i);
                obj.Waves(j).Enabled = true;
            end
        end

        function w = loadWaves(obj)
            % A lab works at one species and one rate; its windows should not
            % have to be retyped every session.
            w = mabr.ui.TraceInspector.defaultWaves();
            try
                s = getpref('MABR',obj.PrefKey,[]);
            catch
                return
            end
            if ~isstruct(s) || isempty(s) || ...
                    ~all(isfield(s,{'Name','Enabled','TMin','TMax','Type'}))
                return
            end
            v = mabr.ui.TraceInspector.emptyWaves();
            for i = 1:numel(s)
                try
                    v(end+1) = obj.mkWave(s(i).Name,s(i).Enabled, ...
                        s(i).TMin,s(i).TMax,s(i).Type); %#ok<AGROW>
                catch
                    % One malformed row is not a reason to discard a whole
                    % set of windows -- or to fail to open.
                end
            end
            if ~isempty(v), w = v; end
        end

        function saveWaves(obj)
            s = obj.Waves;
            for i = 1:numel(s), s(i).Loc = NaN; end   % windows persist, picks do not
            try
                setpref('MABR',obj.PrefKey,s);
            catch me
                mabr.log.vprintf(2,1,'Could not save inspector waves: %s',me.message);
            end
        end
    end

    methods (Static)
        function w = defaultWaves()
            % ABR waves I-V with starting search windows (ms re onset). These
            % are a rodent-rig starting point, not a claim about anyone's
            % preparation -- edit them once and Apply persists them.
            mk = @mabr.ui.TraceInspector.mkWave;
            w = [mk('I',   true, 1.0, 2.0, 'Peak'), ...
                 mk('II',  true, 1.8, 2.8, 'Peak'), ...
                 mk('III', true, 2.6, 3.6, 'Peak'), ...
                 mk('IV',  true, 3.4, 4.6, 'Peak'), ...
                 mk('V',   true, 4.2, 5.6, 'Peak')];
        end

        function w = mkWave(name,enabled,t0,t1,type)
            % The one place a wave row is built, so every path produces the
            % same fields in the same order and struct arrays concatenate.
            if ~ismember(lower(char(type)),{'peak','trough'})
                error('mabr:ui:TraceInspector:badType', ...
                    'Wave type must be Peak or Trough, not "%s".',char(type));
            end
            w = struct('Name',char(name),'Enabled',logical(enabled), ...
                'TMin',double(t0),'TMax',double(t1), ...
                'Type',[upper(char(type(1))) lower(char(type(2:end)))],'Loc',NaN);
        end

        function w = emptyWaves()
            w = struct('Name',{},'Enabled',{},'TMin',{},'TMax',{},'Type',{},'Loc',{});
        end
    end
end
