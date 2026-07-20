classdef LivePlot < handle
% mabr.ui.LivePlot  Live acquisition view: mean / most-recent / correlation.
%
%   A clean, object-oriented rebuild of the legacy abr_live_plot.m (which used
%   a persistent handle struct). It owns its own figure with two axes: a trace
%   axes showing the running mean sweep (black) and the most-recent sweep
%   (blue), and a narrow bar axes showing the online onset-contrast
%   correlation. Call update() from the AcqController's live-view timer.
%
%   lp = mabr.ui.LivePlot();               % own figure
%   lp.update(postSweep,tvec,R,target);    % postSweep = [nSweeps x nSamples]
%   lp.reset();                            % clear
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Figure
        axTrace
        axCorr
        meanLine
        recentLine
        zeroLine
        corrBar
    end

    properties
        Title (1,:) char = 'MABR Live Plot';
    end

    methods
        function obj = LivePlot(parent)
            if nargin >= 1 && ~isempty(parent) && isgraphics(parent)
                obj.build(parent);
            else
                f = figure('Name',obj.Title,'NumberTitle','off','Color','w', ...
                    'Tag','MABR_LIVEPLOT','Position',[100 100 640 280]);
                obj.Figure = f;
                obj.build(f);
            end
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function reset(obj)
            if isempty(obj.axTrace) || ~isgraphics(obj.axTrace), return; end
            set([obj.meanLine obj.recentLine],'XData',nan,'YData',nan);
            obj.corrBar.YData = 0;
            title(obj.axTrace,'');
        end

        function update(obj,postSweep,tvec,R,target,opts)
            % postSweep : [nSweeps x nSamples]   tvec : [1 x nSamples] seconds
            % R         : scalar correlation      target : target sweep count
            if nargin < 5 || isempty(target), target = NaN; end
            if nargin < 6, opts = struct('DetrendPoly',-1,'SmoothSpan',0); end
            if ~isfield(opts,'DetrendPoly'), opts.DetrendPoly = -1; end
            if ~isfield(opts,'SmoothSpan'),  opts.SmoothSpan  = 0;  end

            if isempty(obj.axTrace) || ~isgraphics(obj.axTrace), return; end
            if isempty(postSweep), obj.reset(); return; end

            tms  = double(tvec(:)')*1000;                 % s -> ms
            mean_ = mean(double(postSweep),1);            % running mean
            mean_ = obj.postprocess(mean_,tms,opts);
            recent = double(postSweep(end,:));

            scale = obj.pick_scale(max(abs([mean_ recent])));
            obj.meanLine.XData   = tms;   obj.meanLine.YData   = mean_ .* scale.mult;
            obj.recentLine.XData = tms;   obj.recentLine.YData = recent .* scale.mult;
            obj.zeroLine.XData   = tms([1 end]); obj.zeroLine.YData = [0 0];

            obj.axTrace.XLim = tms([1 end]);
            yl = max(abs([obj.meanLine.YData obj.recentLine.YData]));
            if ~isfinite(yl) || yl == 0, yl = 1; end
            obj.axTrace.YLim = [-1.1 1.1]*yl;
            ylabel(obj.axTrace,sprintf('Amplitude (%s)',scale.unit));

            if isnan(target)
                title(obj.axTrace,sprintf('%d sweeps',size(postSweep,1)));
            else
                title(obj.axTrace,sprintf('%d / %d sweeps',size(postSweep,1),target));
            end

            if nargin >= 4 && ~isempty(R) && ~isnan(R)
                obj.corrBar.YData = max(0,min(1,R));
            end
            drawnow limitrate
        end
    end

    methods (Access = private)
        function build(obj,parent)
            obj.axTrace = axes('Parent',parent,'Units','normalized', ...
                'Position',[0.10 0.16 0.62 0.72],'Box','on','NextPlot','add');
            grid(obj.axTrace,'on');
            xlabel(obj.axTrace,'Time (ms)');

            obj.zeroLine   = line(obj.axTrace,nan,nan,'Color',[.6 .6 .6],'LineWidth',1.5);
            obj.meanLine   = line(obj.axTrace,nan,nan,'Color',[0 0 0],'LineWidth',2);
            obj.recentLine = line(obj.axTrace,nan,nan,'Color',[0.2 0.6 1],'LineWidth',1);
            legend(obj.axTrace,[obj.meanLine obj.recentLine],{'Mean','Latest'}, ...
                'Location','southeast','Box','off','AutoUpdate','off');

            obj.axCorr = axes('Parent',parent,'Units','normalized', ...
                'Position',[0.80 0.16 0.14 0.72],'Box','on');
            obj.corrBar = bar(obj.axCorr,1,0,'FaceColor',[0.2 0.2 0.2]);
            obj.axCorr.YLim = [0 1];
            obj.axCorr.XTick = [];
            title(obj.axCorr,'\rho_{post}-\rho_{pre}');
            ylabel(obj.axCorr,'correlation');
        end
    end

    methods (Static, Access = private)
        function m = postprocess(m,tms,opts)
            if opts.SmoothSpan > 0, m = movmean(m,opts.SmoothSpan); end
            if opts.DetrendPoly == 0
                m = m - mean(m);
            elseif opts.DetrendPoly > 0
                [p,~,mu] = polyfit(tms,m,opts.DetrendPoly);
                m = m - polyval(p,tms,[],mu);
            end
        end

        function s = pick_scale(maxAbs)
            % Choose a sensible voltage unit for display.
            if ~isfinite(maxAbs) || maxAbs == 0, s = struct('mult',1e6,'unit','\muV'); return; end
            if     maxAbs >= 1e-1, s = struct('mult',1,   'unit','V');
            elseif maxAbs >= 1e-4, s = struct('mult',1e3, 'unit','mV');
            elseif maxAbs >= 1e-7, s = struct('mult',1e6, 'unit','\muV');
            else,                  s = struct('mult',1e9, 'unit','nV');
            end
        end
    end
end
