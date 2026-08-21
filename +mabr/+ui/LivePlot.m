classdef LivePlot < handle
% mabr.ui.LivePlot  Live acquisition view: latest sweep + per-stimulus means.
%
%   A clean, object-oriented rebuild of the legacy abr_live_plot.m (which used
%   a persistent handle struct). It owns its own figure, split into three
%   regions:
%
%     * a LATEST axes across the top, always showing the single most recent
%       sweep on its own -- it is a different quantity from an average (one
%       sweep, tens of times larger) and sharing an axis with the means would
%       flatten them, so it keeps its own,
%     * a narrow correlation bar beside it (the online onset-contrast metric),
%     * and below, the RUNNING MEAN of every stimulus the current run is
%       presenting -- either overlaid on one axes or one small axes each.
%
%   That lower region is the point of the window during an intermixed run: the
%   run interleaves several conditions, so a single pooled average would mix
%   them and show nothing. Sweeps are sorted by the stimulus that evoked them
%   (mabr.stim.Schedule's per-onset stimulus index, handed over by
%   mabr.ui.AcqController) and averaged separately.
%
%       lp = mabr.ui.LivePlot();                    % own figure
%       lp.update(sweeps,tvec,R,target,bad,info);   % sweeps [nSweeps x nSamples]
%       lp.reset();                                 % clear
%
%   `info` carries the per-sweep stimulus identity; without it every sweep is
%   treated as one condition and the window degenerates to the old single-mean
%   view. See update() for the fields.
%
%   Display controls (also settable programmatically, which is what the strip
%   along the bottom of the window does):
%
%       Layout       'overlay' | 'separate'   means on one axes, or one each
%       TimeBase     [t0 t1] ms               default [-2 10]; the negative
%                                             half is the pre-onset baseline
%       AmpMode      'each' | 'common' | 'manual'
%       ManualLimit  volts                    the +/- limit AmpMode 'manual' uses
%
%   'each' lets every stimulus autoscale to its own response, which is what
%   you want when levels differ by 40 dB; 'common' holds them all to one scale,
%   which is the only way an amplitude difference between conditions is
%   visible; 'manual' pins the scale so it stops moving between refreshes.
%   Overlaid means share one axes and therefore one scale, so 'each' behaves as
%   'common' there.
%
%   Sweeps flagged in `bad` are EXCLUDED from the running means -- one electrode
%   pop otherwise smears across the whole average and the view stops reflecting
%   what the block will contain. They are reported instead: the count and rate
%   appear in red above the latest trace, and the latest sweep is drawn in red
%   when it was the one rejected, so a noisy electrode is visible as it happens
%   rather than at the end of the block.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant, Access = private)
        RecentColor   = [0.2 0.6 1];      % latest sweep, kept
        ArtifactColor = [0.85 0.15 0.1];  % latest sweep, rejected
        ZeroColor     = [0.6 0.6 0.6];
        ControlHeight = 30;   % px reserved for the control strip
        TilesPerCol   = 4;    % separate plots stack this deep before columning
        MaxLegend     = 12;   % overlaid means beyond this get no legend
        % Vertical split of the plot region: the latest sweep on top, the
        % means below it. Fractions of the plot panel.
        TopFrac       = 0.34;
    end

    properties
        Title (1,:) char = 'MABR Live Plot';
    end

    properties (SetAccess = private)
        Figure
        Container       % figure or the container this view was built into
        PlotPanel
        CtrlPanel
        axLatest
        axCorr
        axMean = gobjects(1,0);   % one (overlay) or one per stimulus
    end

    % --- Display settings ------------------------------------------------
    % Public so a script can drive the view; the control strip writes exactly
    % these, and each setter re-renders from the cached last update, so a
    % change is visible immediately whether or not sweeps are still arriving.
    properties
        Layout      (1,:) char   = 'overlay'
        TimeBase    (1,2) double = [-2 10]     % ms
        AmpMode     (1,:) char   = 'common'
        ManualLimit (1,1) double = 5e-6        % volts, +/-
    end

    properties (Access = private)
        meanLines  = gobjects(1,0);   % one per stimulus, in axMean order
        latestLine
        corrBar
        artifactText
        legendHandle
        Ctrl = struct();      % the control-strip uicontrols
        StimList   = [];      % stimulus indices the current axes were built for
        StimLabels = {};
        LayoutKey  (1,:) char = '';
        FilterText (1,:) char = '';
        Last = [];            % last update() payload, for re-render on a control change
    end

    methods
        function obj = LivePlot(parent)
            if nargin >= 1 && ~isempty(parent) && isgraphics(parent)
                obj.Container = parent;
            else
                obj.Figure = figure('Name',obj.Title,'NumberTitle','off','Color','w', ...
                    'Tag','MABR_LIVEPLOT','Position',[100 100 720 560]);
                obj.Container = obj.Figure;
            end
            obj.build();
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.PlotPanel) && isgraphics(obj.PlotPanel);
        end

        function reset(obj)
            % Forget the run just finished. The axes stay as they are: the
            % next run rebuilds them for its own stimulus list on the first
            % update, and rebuilding here would flash an empty grid in between.
            obj.Last = [];
            if ~obj.isvalidView(), return; end
            set(obj.meanLines(isgraphics(obj.meanLines)),'XData',nan,'YData',nan);
            if isgraphics(obj.latestLine)
                set(obj.latestLine,'XData',nan,'YData',nan,'Color',obj.RecentColor);
            end
            if isgraphics(obj.artifactText), obj.artifactText.String = ''; end
            if isgraphics(obj.corrBar), obj.corrBar.YData = 0; end
            title(obj.axLatest,'');
            for k = 1:numel(obj.axMean)
                if isgraphics(obj.axMean(k)), title(obj.axMean(k),''); end
            end
        end

        function update(obj,sweeps,tvec,R,target,bad,info)
            % sweeps : [nSweeps x nSamples]  tvec : [1 x nSamples] SECONDS,
            %          spanning the pre-onset baseline and the response, so a
            %          negative time base has something to show
            % R      : scalar correlation     target : target sweep count
            % bad    : [1 x nSweeps] logical, sweeps flagged as artifact
            % info   : optional struct
            %            .StimIndex [1 x nSweeps] stimulus behind each sweep
            %            .Stimuli   [1 x nStim]   stimuli this run presents,
            %                                     in the order to lay them out
            %            .Labels    {1 x nStim}   display label for each
            %            .DetrendPoly, .SmoothSpan  cosmetic post-processing
            %          Omit it and every sweep counts as one condition.
            if nargin < 4, R = []; end
            if nargin < 5, target = NaN; end
            if nargin < 6, bad = []; end
            if nargin < 7 || ~isstruct(info), info = struct(); end
            if ~obj.isvalidView(), return; end
            if isempty(sweeps), obj.reset(); return; end

            n = size(sweeps,1);
            if numel(bad) == n, bad = logical(bad(:)'); else, bad = false(1,n); end
            if isempty(target), target = NaN; end

            S        = struct();
            S.Y      = double(sweeps);
            S.t      = double(tvec(:)')*1000;          % s -> ms
            S.R      = R;
            S.target = target;
            S.bad    = bad;
            S.opts   = mabr.ui.LivePlot.resolveOpts(info);
            [S.stimIdx,S.stimList,S.labels] = mabr.ui.LivePlot.resolveStimuli(info,n);

            obj.Last = S;
            obj.render();
        end

        function setFilterText(obj,txt)
            % Caption the view with the display filter chain in force. The
            % whole point of the filter dialog is that these traces are NOT the
            % raw signal, so the window says which corners it is showing you
            % rather than leaving that to memory. It rides on the latest axes'
            % subtitle, which is the one caption nothing else claims.
            obj.FilterText = char(txt);
            obj.applyFilterText();
        end

        % --- Display settings ------------------------------------------------
        function set.Layout(obj,v)
            obj.Layout = validatestring(v,{'overlay','separate'}, ...
                'mabr.ui.LivePlot','Layout');
            obj.afterSettingChange();
        end

        function set.AmpMode(obj,v)
            obj.AmpMode = validatestring(v,{'each','common','manual'}, ...
                'mabr.ui.LivePlot','AmpMode');
            obj.afterSettingChange();
        end

        function set.TimeBase(obj,v)
            assert(v(2) > v(1),'mabr:ui:LivePlot:timeBase', ...
                'TimeBase must be increasing ([t0 t1] in ms).');
            obj.TimeBase = double(v);
            obj.afterSettingChange();
        end

        function set.ManualLimit(obj,v)
            assert(isfinite(v) && v > 0,'mabr:ui:LivePlot:manualLimit', ...
                'ManualLimit must be a positive number of volts.');
            obj.ManualLimit = double(v);
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
            obj.buildControls();
            obj.buildTop();
            obj.buildMeanAxes([],{});
            obj.relayout();
            if isprop(c,'SizeChangedFcn'), c.SizeChangedFcn = @(~,~) obj.relayout(); end
        end

        function relayout(obj)
            % The control strip keeps a fixed PIXEL height whatever the window
            % does, so its contents can be laid out in pixels once and never
            % move; only the plot region above it stretches.
            if ~obj.isvalidView(), return; end
            h = obj.ControlHeight / max(1,obj.containerHeight());
            h = min(max(h,0.02),0.5);
            obj.CtrlPanel.Position = [0 0 1 h];
            obj.PlotPanel.Position = [0 h 1 1-h];
        end

        function px = containerHeight(obj)
            c = obj.Container;
            oldU = c.Units; c.Units = 'pixels';
            px = c.Position(4);
            c.Units = oldU;
        end

        function buildTop(obj)
            p = obj.PlotPanel;
            y = 1 - obj.TopFrac;
            obj.axLatest = axes('Parent',p,'Units','normalized', ...
                'Position',[0.09 y+0.06 0.72 obj.TopFrac-0.13],'Box','on','NextPlot','add');
            grid(obj.axLatest,'on');
            yline(obj.axLatest,0,'Color',obj.ZeroColor,'LineWidth',1);
            xline(obj.axLatest,0,'Color',obj.ZeroColor,'LineStyle',':');
            obj.latestLine = line(obj.axLatest,nan,nan, ...
                'Color',obj.RecentColor,'LineWidth',1);

            % Sits in the axes' top-left corner in normalized units, so it
            % stays put as the trace rescales around it.
            obj.artifactText = text(obj.axLatest,0.02,0.96,'', ...
                'Units','normalized','Color',obj.ArtifactColor, ...
                'FontWeight','bold','VerticalAlignment','top', ...
                'HorizontalAlignment','left','Clipping','off');

            obj.axCorr = axes('Parent',p,'Units','normalized', ...
                'Position',[0.88 y+0.06 0.09 obj.TopFrac-0.13],'Box','on');
            obj.corrBar = bar(obj.axCorr,1,0,'FaceColor',[0.2 0.2 0.2]);
            obj.axCorr.YLim  = [0 1];
            obj.axCorr.XTick = [];
            title(obj.axCorr,'\rho_{post}-\rho_{pre}','FontSize',8);
        end

        function buildMeanAxes(obj,stimList,labels)
            % (Re)build the lower region for exactly the stimuli this run
            % presents. Called only when that list -- or the layout mode --
            % changes, never on a plain refresh.
            delete(obj.axMean(isgraphics(obj.axMean)));
            obj.axMean    = gobjects(1,0);
            obj.meanLines = gobjects(1,0);
            obj.legendHandle = [];

            obj.StimList   = stimList;
            obj.StimLabels = labels;
            n   = max(1,numel(stimList));
            col = mabr.ui.LivePlot.stimColors(n);
            p   = obj.PlotPanel;

            if strcmp(obj.Layout,'separate') && numel(stimList) > 1
                [pos,isBottom,isLeft] = obj.tilePositions(n);
                for k = 1:n
                    ax = axes('Parent',p,'Units','normalized','Position',pos(k,:), ...
                        'Box','on','NextPlot','add','FontSize',8);
                    grid(ax,'on');
                    yline(ax,0,'Color',obj.ZeroColor);
                    xline(ax,0,'Color',obj.ZeroColor,'LineStyle',':');
                    % Only the tile at the foot of each column is labelled:
                    % repeating "Time (ms)" under every one of a dozen tiles
                    % costs the height the traces need.
                    if isBottom(k), xlabel(ax,'Time (ms)','FontSize',8);
                    else,           ax.XTickLabel = [];
                    end
                    if ~isLeft(k),   ax.YTickLabel = []; end
                    obj.axMean(k)    = ax;
                    obj.meanLines(k) = line(ax,nan,nan,'Color',col(k,:),'LineWidth',1.5);
                end
            else
                ax = axes('Parent',p,'Units','normalized', ...
                    'Position',[0.09 0.11 0.72 1-obj.TopFrac-0.16], ...
                    'Box','on','NextPlot','add');
                grid(ax,'on');
                yline(ax,0,'Color',obj.ZeroColor);
                xline(ax,0,'Color',obj.ZeroColor,'LineStyle',':');
                obj.axMean = ax;
                for k = 1:n
                    obj.meanLines(k) = line(ax,nan,nan,'Color',col(k,:),'LineWidth',1.5);
                end
                obj.addOverlayLegend(labels);
                xlabel(obj.axMean(1),'Time (ms)');
            end
            obj.LayoutKey = obj.layoutKey(stimList,labels);
        end

        function addOverlayLegend(obj,labels)
            % Overlaid means need naming, but a legend that eats the axes is
            % worse than none: it is drawn INSIDE (so the manual axes layout
            % stays authoritative), small, and dropped entirely once there are
            % more conditions than it could label legibly -- at which point
            % Separate plots is the answer, and the tile titles name them.
            if numel(labels) < 2 || numel(labels) > obj.MaxLegend, return; end
            obj.legendHandle = legend(obj.axMean(1),obj.meanLines,labels, ...
                'Location','northeast','Box','off','AutoUpdate','off', ...
                'FontSize',7,'NumColumns',ceil(numel(labels)/6), ...
                'Interpreter','none');   % IDs like 8kHz_30dB are not TeX
        end

        function [pos,isBottom,isLeft] = tilePositions(obj,n)
            % Stack tiles down a column before adding another column: traces
            % are wide and short, so height is the scarce dimension.
            cols = max(1,ceil(n/obj.TilesPerCol));
            rows = ceil(n/cols);
            x0 = 0.075; x1 = 0.985; y0 = 0.10; y1 = 1-obj.TopFrac-0.05;
            wGap = 0.055; hGap = 0.030;
            w = (x1-x0)/cols - wGap;
            h = (y1-y0)/rows - hGap;
            pos      = zeros(n,4);
            isBottom = false(1,n);
            isLeft   = false(1,n);
            for k = 1:n
                c = floor((k-1)/rows);          % fill top-to-bottom, then across
                r = mod(k-1,rows);
                pos(k,:) = [x0 + c*(w+wGap), y1 - (r+1)*h - r*hGap, w, h];
                isBottom(k) = (r == rows-1) || (k == n);
                isLeft(k)   = (c == 0);
            end
        end

        % --- Control strip ---------------------------------------------------
        function buildControls(obj)
            p = obj.CtrlPanel;
            x = 8;
            [~,x] = obj.addText(p,'Means:',x,44);
            [obj.Ctrl.layout,x] = obj.addPopup(p,{'Overlaid','Separate'},x,88, ...
                @() obj.onLayoutControl(), ...
                'One axes for every stimulus mean, or one axes each.');

            x = x + 10;
            [~,x] = obj.addText(p,'Time (ms):',x,62);
            [obj.Ctrl.t0,x] = obj.addEdit(p,x,42,@() obj.onTimeControl(), ...
                'Start of the displayed window, relative to stimulus onset (may be negative).');
            [~,x] = obj.addText(p,'to',x,16);
            [obj.Ctrl.t1,x] = obj.addEdit(p,x,42,@() obj.onTimeControl(), ...
                'End of the displayed window, relative to stimulus onset.');

            x = x + 10;
            [~,x] = obj.addText(p,'Amplitude:',x,60);
            [obj.Ctrl.amp,x] = obj.addPopup(p, ...
                {'Auto (each)','Auto (shared)','Manual'},x,104,@() obj.onAmpControl(), ...
                ['How the mean axes are scaled: each stimulus to its own peak, ' ...
                 'all to one shared scale, or a fixed limit you set.']);
            [obj.Ctrl.manual,x] = obj.addEdit(p,x,54,@() obj.onManualControl(), ...
                'Fixed +/- limit for the mean axes.');
            obj.Ctrl.manualUnit = obj.addText(p,'uV',x,26);

            obj.syncControls();
        end

        function [h,x] = addText(~,p,txt,x,w)
            h = uicontrol(p,'Style','text','String',txt,'Units','pixels', ...
                'Position',[x 5 w 16],'HorizontalAlignment','left', ...
                'BackgroundColor',p.BackgroundColor);
            x = x + w + 3;
        end

        function [h,x] = addPopup(~,p,items,x,w,fcn,tip)
            h = uicontrol(p,'Style','popupmenu','String',items,'Units','pixels', ...
                'Position',[x 4 w 20],'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        function [h,x] = addEdit(~,p,x,w,fcn,tip)
            h = uicontrol(p,'Style','edit','String','','Units','pixels', ...
                'Position',[x 5 w 20],'BackgroundColor','w', ...
                'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        function onLayoutControl(obj)
            modes = {'overlay','separate'};
            obj.Layout = modes{obj.Ctrl.layout.Value};
        end

        function onAmpControl(obj)
            modes = {'each','common','manual'};
            newMode = modes{obj.Ctrl.amp.Value};
            % Switching INTO manual seeds the limit from whatever is on screen,
            % so "Manual" starts by holding the current view still rather than
            % jumping to some remembered number from an hour ago.
            if strcmp(newMode,'manual') && ~isempty(obj.Last)
                lim = obj.dataLimit();
                if isfinite(lim) && lim > 0, obj.ManualLimit = lim; end
            end
            obj.AmpMode = newMode;
        end

        function onTimeControl(obj)
            t = obj.TimeBase;
            v0 = str2double(obj.Ctrl.t0.String);
            v1 = str2double(obj.Ctrl.t1.String);
            if isfinite(v0) && isfinite(v1) && v1 > v0
                obj.TimeBase = [v0 v1];
            else
                obj.syncControls();   % reject: put the old values back
                obj.TimeBase = t;
            end
        end

        function onManualControl(obj)
            v = str2double(obj.Ctrl.manual.String);
            s = obj.currentScale();
            if isfinite(v) && v > 0
                obj.ManualLimit = v / s.mult;   % typed in the displayed unit
                obj.AmpMode     = 'manual';     % typing a limit means using it
            end
            obj.syncControls();
        end

        function syncControls(obj)
            % Push the settings into the strip. The manual field is shown in
            % whatever unit the axes are currently labelled in, so the number
            % beside "uV" always means what it says.
            if ~isfield(obj.Ctrl,'layout') || ~isgraphics(obj.Ctrl.layout), return; end
            obj.Ctrl.layout.Value = 1 + strcmp(obj.Layout,'separate');
            obj.Ctrl.amp.Value    = find(strcmp(obj.AmpMode,{'each','common','manual'}),1);
            obj.Ctrl.t0.String    = num2str(obj.TimeBase(1),'%g');
            obj.Ctrl.t1.String    = num2str(obj.TimeBase(2),'%g');
            s = obj.currentScale();
            obj.Ctrl.manual.String     = num2str(obj.ManualLimit*s.mult,'%.4g');
            obj.Ctrl.manualUnit.String = s.plain;
            obj.Ctrl.manual.Enable     = onOff(strcmp(obj.AmpMode,'manual'));
        end

        function afterSettingChange(obj)
            % Every setter lands here: keep the strip honest and redraw from
            % the cached sweeps, so a control does something even between runs.
            if ~obj.isvalidView(), return; end
            obj.syncControls();
            if ~isempty(obj.Last), obj.render(); end
        end

        % --- Rendering -------------------------------------------------------
        function render(obj)
            S = obj.Last;
            if isempty(S) || ~obj.isvalidView(), return; end

            key = obj.layoutKey(S.stimList,S.labels);
            if ~strcmp(key,obj.LayoutKey)
                obj.buildMeanAxes(S.stimList,S.labels);
                obj.applyFilterText();
            end

            [M,counts,rejected] = obj.stimulusMeans(S);
            latest = S.Y(end,:);
            scale  = obj.pickScale(max([abs(M(:)); abs(latest(:)); 0]));

            % --- latest sweep ------------------------------------------------
            set(obj.latestLine,'XData',S.t,'YData',latest*scale.mult);
            if S.bad(end), obj.latestLine.Color = obj.ArtifactColor;
            else,          obj.latestLine.Color = obj.RecentColor;
            end
            % The latest sweep autoscales even under AmpMode 'manual': it is a
            % single sweep, tens of times the size of a mean, and a limit
            % chosen to frame the averages would clip it off the axes entirely.
            obj.setLimits(obj.axLatest,S.t,max(abs(latest))*scale.mult);
            ylabel(obj.axLatest,sprintf('Amplitude (%s)',scale.unit));
            % Interpreter 'none' wherever a stimulus ID can appear: an ID like
            % 8kHz_30dB is not TeX, and the default interpreter renders the
            % underscore as a subscript.
            title(obj.axLatest,obj.latestTitle(S,counts),'Interpreter','none');
            obj.showArtifacts(nnz(S.bad),numel(S.bad));

            % --- per-stimulus means ------------------------------------------
            yl = obj.meanLimits(M,scale);
            for k = 1:numel(obj.meanLines)
                set(obj.meanLines(k),'XData',S.t,'YData',M(k,:)*scale.mult);
            end
            for a = 1:numel(obj.axMean)
                obj.setLimits(obj.axMean(a),S.t,yl(min(a,numel(yl))));
            end
            if numel(obj.axMean) > 1
                for k = 1:numel(obj.axMean)
                    title(obj.axMean(k),sprintf('%s  (n=%d)',S.labels{k},counts(k)-rejected(k)), ...
                        'FontSize',8,'FontWeight','normal','Interpreter','none');
                end
                ylabel(obj.axMean(1),sprintf('Mean (%s)',scale.unit));
            else
                ylabel(obj.axMean(1),sprintf('Mean (%s)',scale.unit));
                title(obj.axMean(1),obj.overlayTitle(S,counts,rejected),'Interpreter','none');
            end

            if ~isempty(S.R) && isscalar(S.R) && ~isnan(S.R)
                obj.corrBar.YData = max(0,min(1,S.R));
            end
            drawnow limitrate
        end

        function [M,counts,rejected] = stimulusMeans(obj,S)
            % One running mean per stimulus, over the sweeps that survived the
            % artifact preview -- the average the block will actually hold.
            n = numel(obj.meanLines);
            M = nan(n,numel(S.t));
            counts = zeros(1,n); rejected = zeros(1,n);
            for k = 1:n
                if k <= numel(S.stimList), sel = S.stimIdx == S.stimList(k);
                else,                      sel = true(size(S.stimIdx));
                end
                counts(k)   = nnz(sel);
                rejected(k) = nnz(sel & S.bad);
                good = sel & ~S.bad;
                % Every sweep of this condition rejected so far: there is no
                % mean to show, and a flat line at zero would be a lie.
                if any(good)
                    M(k,:) = mabr.ui.LivePlot.postprocess( ...
                        mean(S.Y(good,:),1),S.t,S.opts);
                end
            end
        end

        function yl = meanLimits(obj,M,scale)
            % One limit per mean axes, in display units. Overlaid means share
            % an axes and so cannot be scaled individually -- 'each' collapses
            % to 'common' there rather than silently picking one stimulus.
            n = size(M,1);
            switch obj.AmpMode
                case 'manual'
                    yl = repmat(obj.ManualLimit*scale.mult,1,n);
                case 'each'
                    if numel(obj.axMean) > 1
                        yl = max(abs(M),[],2).'*scale.mult;
                    else
                        yl = repmat(max(abs(M(:)))*scale.mult,1,n);
                    end
                otherwise
                    yl = repmat(max(abs(M(:)))*scale.mult,1,n);
            end
            yl(~isfinite(yl) | yl == 0) = 1;
        end

        function setLimits(obj,ax,t,ylim_)
            % Clamp the requested time base to what was actually recorded: the
            % window can be widened past the extracted sweep, and an axis
            % showing empty space either side reads as missing data.
            xl = obj.TimeBase;
            xl(1) = max(xl(1),t(1));
            xl(2) = min(xl(2),t(end));
            if ~(xl(2) > xl(1)), xl = [t(1) t(end)]; end
            ax.XLim = xl;
            if ~isfinite(ylim_) || ylim_ == 0, ylim_ = 1; end
            ax.YLim = [-1.1 1.1]*ylim_;
        end

        function lim = dataLimit(obj)
            % The +/- limit the mean axes are currently using, in VOLTS -- what
            % "Manual" seeds itself from.
            lim = 0;
            if isempty(obj.Last), return; end
            M   = obj.stimulusMeans(obj.Last);
            lim = max(abs(M(:)));
            if ~isfinite(lim) || lim == 0, lim = obj.ManualLimit; end
        end

        function s = currentScale(obj)
            % The unit the axes are labelled in right now, so the manual field
            % and its unit caption agree with them.
            if strcmp(obj.AmpMode,'manual')
                s = obj.pickScale(obj.ManualLimit);
            else
                s = obj.pickScale(obj.dataLimit());
            end
        end

        function txt = latestTitle(~,S,counts)
            done = sum(counts);
            if isnan(S.target), sweeps = sprintf('%d sweeps',done);
            else,               sweeps = sprintf('%d / %d sweeps',done,S.target);
            end
            % Name the condition the latest sweep belongs to only when the run
            % holds more than one -- otherwise it just repeats the axes below.
            if numel(S.stimList) > 1
                k = find(S.stimList == S.stimIdx(end),1);
                if ~isempty(k)
                    txt = sprintf('Latest — %s   (%s)',S.labels{k},sweeps);
                    return
                end
            end
            txt = sprintf('Latest sweep   (%s)',sweeps);
        end

        function txt = overlayTitle(~,S,counts,rejected)
            if numel(S.stimList) > 1
                txt = sprintf('Means — %d stimuli, %d sweeps averaged', ...
                    numel(S.stimList),sum(counts)-sum(rejected));
            else
                txt = sprintf('Mean of %d sweeps',sum(counts)-sum(rejected));
            end
        end

        function showArtifacts(obj,nBad,nTotal)
            % Silent when nothing has been rejected: an always-present "0
            % rejected" is noise the eye learns to skip, and the point of the
            % readout is that it appears the moment it matters.
            if ~isgraphics(obj.artifactText), return; end
            if nBad < 1
                obj.artifactText.String = '';
            else
                obj.artifactText.String = sprintf('%d rejected (%.0f%%)', ...
                    nBad,100*nBad/max(1,nTotal));
            end
        end

        function applyFilterText(obj)
            if isempty(obj.axLatest) || ~isgraphics(obj.axLatest), return; end
            subtitle(obj.axLatest,obj.FilterText,'FontWeight','normal', ...
                'FontAngle','italic','Color',[0.45 0.45 0.45]);
        end

        function k = layoutKey(obj,stimList,labels)
            k = sprintf('%s|%s|%s',obj.Layout,mat2str(stimList(:).'), ...
                strjoin(labels,'>'));
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function [idx,list,labels] = resolveStimuli(info,nSweeps)
            % Which stimulus evoked each sweep, which stimuli to lay out, and
            % what to call them. Absent info means one unnamed condition, which
            % is the old single-mean view.
            idx = ones(1,nSweeps);
            if isfield(info,'StimIndex') && ~isempty(info.StimIndex)
                v = double(info.StimIndex(:)');
                k = min(numel(v),nSweeps);
                idx(1:k) = v(1:k);
                % More onsets recorded than the schedule planned should not
                % happen; if it does, the extras belong with the last one
                % rather than inventing a condition for them.
                if k < nSweeps, idx(k+1:end) = v(k); end
            end

            if isfield(info,'Stimuli') && ~isempty(info.Stimuli)
                list = double(info.Stimuli(:)');
            else
                list = unique(idx,'stable');
            end

            labels = cell(1,numel(list));
            given  = {};
            if isfield(info,'Labels') && iscell(info.Labels), given = info.Labels; end
            for k = 1:numel(list)
                if k <= numel(given) && ~isempty(given{k})
                    labels{k} = char(string(given{k}));
                else
                    labels{k} = sprintf('Stimulus %d',list(k));
                end
            end
        end

        function opts = resolveOpts(info)
            opts = struct('DetrendPoly',-1,'SmoothSpan',0);
            if isfield(info,'DetrendPoly'), opts.DetrendPoly = info.DetrendPoly; end
            if isfield(info,'SmoothSpan'),  opts.SmoothSpan  = info.SmoothSpan;  end
        end

        function c = stimColors(n)
            % lines() only holds seven distinct colours before it repeats, and
            % two conditions sharing a colour on one overlaid axes is worse
            % than no colour at all. Past that, a continuous map: a bank is
            % almost always an ordered series (levels, frequencies), so the
            % gradient carries the ordering the repeat would have destroyed.
            if n <= 7
                c = lines(7);
                c = c(1:n,:);
            else
                c = turbo(n+2);
                c = c(2:end-1,:);   % drop the near-black ends
            end
        end

        function m = postprocess(m,tms,opts)
            if opts.SmoothSpan > 0, m = movmean(m,opts.SmoothSpan); end
            if opts.DetrendPoly == 0
                m = m - mean(m);
            elseif opts.DetrendPoly > 0
                [p,~,mu] = polyfit(tms,m,opts.DetrendPoly);
                m = m - polyval(p,tms,[],mu);
            end
        end

        function s = pickScale(maxAbs)
            % Choose a sensible voltage unit for display. `unit` is TeX for an
            % axis label, `plain` is what a uicontrol caption can render.
            if ~isfinite(maxAbs) || maxAbs == 0
                s = struct('mult',1e6,'unit','\muV','plain','uV'); return
            end
            if     maxAbs >= 1e-1, s = struct('mult',1,   'unit','V',    'plain','V');
            elseif maxAbs >= 1e-4, s = struct('mult',1e3, 'unit','mV',   'plain','mV');
            elseif maxAbs >= 1e-7, s = struct('mult',1e6, 'unit','\muV', 'plain','uV');
            else,                  s = struct('mult',1e9, 'unit','nV',   'plain','nV');
            end
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end
