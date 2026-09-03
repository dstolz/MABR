classdef Plot
% mabr.analysis.Plot  Figures for offline ABR analysis.
%
%   Static, self-contained drawing. Every method takes plain data -- means, a
%   time vector, level and frequency values -- rather than a Session, so a
%   figure can be drawn from anything, including results loaded from a saved
%   .mat that no longer has the object that made them.
%
%     grid       the level x frequency matrix of averaged waveforms, which is
%                the picture a threshold is actually read off
%     stack      one frequency's level series as an offset waterfall
%     audiogram  thresholds against frequency, with confidence intervals and
%                an honest marker for "no response at any level presented"
%     detection  one level series with its fitted curve and threshold
%     waveform   one condition: the mean, its error band, and the sweeps
%
%   No colorcet, no use_fig, no File Exchange anything: palette() carries
%   perceptually uniform colormaps of its own, so a figure looks the same on a
%   rig as it does on the analysis machine.
%
%   See also mabr.analysis.Session, mabr.analysis.Threshold

    properties (Constant)
        PaletteNames = ["linear","fire","rainbow","blue","gray"]
    end

    methods (Static)
        % =================================================================
        %  The grid
        % =================================================================
        function [ax,tl] = grid(S,t,rowVals,colVals,opts)
            % Tiled grid of averaged responses: one tile per condition.
            %
            %   S        [nRows x nCols] cell; each cell is a mean vector or a
            %            [nSamples x nSweeps] matrix (averaged here). Empty
            %            cells are drawn as empty tiles, which is the honest
            %            picture of a condition that was never collected.
            %   t        time vector (ms), one entry per sample
            %   rowVals  row values, ascending (levels). Drawn top-down, loudest
            %            at the top, the way an ABR series is read.
            %   colVals  column values, ascending (frequencies)
            arguments
                S cell
                t (:,1) double
                rowVals (:,1) double
                colVals (:,1) double
                opts.Window (1,2) double = [-Inf Inf]   % ms, what to draw
                opts.Normalize (1,1) string {mustBeMember(opts.Normalize,["column","global","tile","none"])} = "column"
                opts.Colors double = []
                opts.Palette (1,1) string = "linear"
                opts.LineWidth (1,1) double = 1.5
                opts.RowLabel (1,1) string = "Level (dB SPL)"
                opts.ColLabel (1,1) string = "Frequency (kHz)"
                opts.RowFormat (1,1) string = "%g"
                opts.ColFormat (1,1) string = "%g"
                opts.Threshold (1,:) double = []        % one per column; marks the row
                opts.Scale (1,1) double = 1e6           % volts -> microvolts
                opts.Unit (1,1) string = "\muV"
                opts.Parent = []
            end

            nRow = numel(rowVals); nCol = numel(colVals);
            if ~isequal(size(S),[nRow nCol])
                error('mabr:analysis:Plot:sizeMismatch', ...
                    'S is %dx%d but %d rows and %d columns were given.', ...
                    size(S,1),size(S,2),nRow,nCol);
            end

            keep = t >= opts.Window(1) & t <= opts.Window(2);
            tv   = t(keep);

            % Mean per condition, in display units.
            M = cell(nRow,nCol);
            for i = 1:numel(S)
                x = S{i};
                if isempty(x), continue; end
                if size(x,2) > 1, x = mean(x,2); end
                M{i} = opts.Scale * x(keep);
            end

            cm = opts.Colors;
            if isempty(cm), cm = mabr.analysis.Plot.palette(nCol,opts.Palette); end

            if isempty(opts.Parent)
                fig = figure('Name','ABR grid','Color','w');
                tl  = tiledlayout(fig,nRow,nCol,'Padding','tight','TileSpacing','none');
            else
                tl = opts.Parent;
                tl.GridSize = [nRow nCol];
            end

            % Normalization decides what a tile's height means, so it is
            % settled once, before anything is drawn.
            [lims,unitLabel] = mabr.analysis.Plot.gridLimits(M,opts);

            ax = gobjects(nRow,nCol);
            for c = 1:nCol
                for r = 1:nRow
                    % Row 1 of the layout is the LOUDEST level, so the series
                    % descends the way it is read.
                    src = nRow - r + 1;
                    a = nexttile(tl,(r-1)*nCol + c);
                    ax(r,c) = a;
                    hold(a,'on');

                    if tv(1) < 0
                        xline(a,0,'-','Color',[0.75 0.75 0.75],'LineWidth',0.5);
                    end
                    yline(a,0,'-','Color',[0.75 0.75 0.75],'LineWidth',0.5);

                    if ~isempty(M{src,c})
                        y = M{src,c};
                        if opts.Normalize ~= "none", y = y / lims(src,c); end
                        line(a,tv,y,'Color',cm(min(c,size(cm,1)),:),'LineWidth',opts.LineWidth);
                    end

                    hold(a,'off');
                    a.XAxis.Color = 'none';
                    a.YAxis.Color = 'none';
                    set(a,'XLim',[tv(1) tv(end)],'Box','off');
                    if opts.Normalize == "none"
                        set(a,'YLim',[-lims(src,c) lims(src,c)]);
                    else
                        set(a,'YLim',[-1 1]);
                    end

                    if c == 1
                        ylabel(a,sprintf(opts.RowFormat,rowVals(src)), ...
                            'Color','k','Rotation',0, ...
                            'HorizontalAlignment','right','VerticalAlignment','middle');
                    end
                    if r == nRow
                        xlabel(a,sprintf(opts.ColFormat,colVals(c)),'Color','k');
                    end
                end

                % Threshold marker: a rule across the tile of the level the
                % threshold was estimated at, in that column only.
                if numel(opts.Threshold) >= c && isfinite(opts.Threshold(c))
                    k = find(rowVals >= opts.Threshold(c),1,'first');
                    if ~isempty(k)
                        a = ax(nRow-k+1,c);
                        set(a,'Color',[1 0.96 0.94]);
                        line(a,[tv(1) tv(end)],[1 1]*min(ylim(a)), ...
                            'Color',[0.85 0.2 0.2],'LineWidth',4);
                    end
                end
            end

            % Time axis on the bottom-left tile only: every tile shares it, and
            % nCol x nRow copies of the same ruler is noise.
            a = ax(nRow,1);
            a.XAxis.Color = 'k';
            xt = mabr.analysis.Plot.niceTicks(tv);
            set(a,'XTick',xt);
            xlabel(a,'ms','Color','k');

            % One scale bar, in the same tile, saying what the traces are worth.
            mabr.analysis.Plot.scaleBar(a,lims(1,1),unitLabel,opts.Normalize);

            ylabel(tl,char(opts.RowLabel));
            xlabel(tl,char(opts.ColLabel));
            mabr.analysis.Plot.plainAxes(ax);
        end

        % =================================================================
        %  One column as a waterfall
        % =================================================================
        function ax = stack(S,t,rowVals,opts)
            % Level series for ONE frequency, offset into a single axes.
            %
            % The grid answers "where does the response disappear" across
            % frequencies; this answers it for one, with the amplitudes still
            % comparable because every trace shares a scale.
            arguments
                S cell
                t (:,1) double
                rowVals (:,1) double
                opts.Window (1,2) double = [-Inf Inf]
                opts.Spacing (1,1) double = NaN     % display units; NaN = auto
                opts.Colors double = []
                opts.Palette (1,1) string = "linear"
                opts.Scale (1,1) double = 1e6
                opts.Unit (1,1) string = "\muV"
                opts.RowFormat (1,1) string = "%g dB"
                opts.Threshold (1,1) double = NaN
                opts.Parent = []
            end
            keep = t >= opts.Window(1) & t <= opts.Window(2);
            tv = t(keep);

            n = numel(rowVals);
            M = cell(n,1);
            for i = 1:n
                x = S{i};
                if isempty(x), continue; end
                if size(x,2) > 1, x = mean(x,2); end
                M{i} = opts.Scale * x(keep);
            end

            amp = max(cellfun(@(v) max(abs(v),[],'includenan'),M(~cellfun(@isempty,M))));
            if isempty(amp) || ~isfinite(amp), amp = 1; end
            dy = opts.Spacing;
            if ~isfinite(dy), dy = 2.2*amp; end

            cm = opts.Colors;
            if isempty(cm), cm = mabr.analysis.Plot.palette(n,opts.Palette); end

            if isempty(opts.Parent)
                ax = axes(figure('Name','ABR stack','Color','w'));
            else
                ax = opts.Parent;
            end
            hold(ax,'on');
            if tv(1) < 0, xline(ax,0,'-','Color',[0.8 0.8 0.8]); end
            for i = 1:n
                if isempty(M{i}), continue; end
                line(ax,tv,M{i} + (i-1)*dy,'Color',cm(i,:),'LineWidth',1.5);
            end
            if isfinite(opts.Threshold)
                k = find(rowVals >= opts.Threshold,1,'first');
                if ~isempty(k)
                    yline(ax,(k-1)*dy,'--','Color',[0.85 0.2 0.2],'LineWidth',1.5, ...
                        'Label','threshold','LabelHorizontalAlignment','left');
                end
            end
            hold(ax,'off');

            set(ax,'YTick',(0:n-1)*dy,'YTickLabel',compose(opts.RowFormat,rowVals));
            xlim(ax,[tv(1) tv(end)]);
            ylim(ax,[-dy (n)*dy]);
            grid(ax,'on'); box(ax,'on');
            xlabel(ax,'Time (ms)');
            ylabel(ax,'');
            mabr.analysis.Plot.scaleBar(ax,amp,opts.Unit,"none");
            mabr.analysis.Plot.plainAxes(ax);
        end

        % =================================================================
        %  Audiogram
        % =================================================================
        function ax = audiogram(freqs,thresh,opts)
            % Thresholds against frequency.
            %
            % A threshold that was never reached is Inf, and it is drawn as an
            % open marker at the ceiling with an upward arrow rather than as a
            % number: "greater than the loudest level presented" is what was
            % measured, and plotting it as a value invites it into an average.
            arguments
                freqs (1,:) double
                thresh (1,:) double
                opts.CI double = []             % [2 x nFreq] lower/upper
                opts.Ceiling (1,1) double = NaN % level to draw non-responses at
                opts.Colors double = []
                opts.Palette (1,1) string = "linear"
                opts.Color (1,3) double = [0.1 0.1 0.1]
                opts.Label (1,1) logical = true
                opts.DisplayName (1,1) string = ""
                opts.MarkerSize (1,1) double = 60
                opts.Parent = []
                opts.Hold (1,1) logical = false
            end
            if isempty(opts.Parent)
                ax = axes(figure('Name','ABR audiogram','Color','w'));
            else
                ax = opts.Parent;
            end
            if ~opts.Hold, cla(ax); end
            hold(ax,'on');

            ceiling = opts.Ceiling;
            if ~isfinite(ceiling)
                finiteTh = thresh(isfinite(thresh));
                if isempty(finiteTh), ceiling = 90; else, ceiling = max(finiteTh) + 5; end
            end

            noResp = ~isfinite(thresh);
            shown  = thresh;
            shown(noResp) = ceiling;

            cm = opts.Colors;
            if isempty(cm), cm = repmat(opts.Color,numel(freqs),1); end

            if ~isempty(opts.CI)
                for i = 1:numel(freqs)
                    if all(isfinite(opts.CI(:,i)))
                        line(ax,[freqs(i) freqs(i)],opts.CI(:,i).', ...
                            'Color',[0.6 0.6 0.6],'LineWidth',1.5,'HandleVisibility','off');
                    end
                end
            end

            hLine = line(ax,freqs,shown,'Color','k','LineStyle','--','LineWidth',1);
            if opts.DisplayName ~= ""
                hLine.DisplayName = char(opts.DisplayName);
            else
                hLine.HandleVisibility = 'off';
            end

            scatter(ax,freqs(~noResp),shown(~noResp),opts.MarkerSize, ...
                cm(~noResp,:),'filled','HandleVisibility','off');
            if any(noResp)
                scatter(ax,freqs(noResp),shown(noResp),opts.MarkerSize, ...
                    cm(noResp,:),'^','LineWidth',1.5,'HandleVisibility','off');
            end

            if opts.Label
                txt = compose('%.0f',shown);
                txt(noResp) = compose('>%.0f',shown(noResp));
                text(ax,freqs,shown+1.5,txt,'HorizontalAlignment','center', ...
                    'VerticalAlignment','bottom','FontSize',9,'Color','k');
            end
            hold(ax,'off');

            set(ax,'XScale','log','XTick',freqs);
            xlim(ax,[min(freqs)*2^-0.25 max(freqs)*2^0.25]);
            grid(ax,'on'); box(ax,'on');
            xlabel(ax,'Frequency (kHz)');
            ylabel(ax,'Threshold (dB SPL)');
            mabr.analysis.Plot.plainAxes(ax);
        end

        % =================================================================
        %  One fitted level series
        % =================================================================
        function ax = detection(fitOut,opts)
            % The evidence behind one threshold: the points that were fitted,
            % the fitted curve, and where the criterion was met.
            arguments
                fitOut struct
                opts.Parent = []
                opts.XLabel (1,1) string = "Level (dB SPL)"
                opts.YLabel (1,1) string = ""
            end
            if isempty(opts.Parent)
                ax = axes(figure('Name','Detection','Color','w'));
            else
                ax = opts.Parent;
            end
            hold(ax,'on');

            x = fitOut.X; y = fitOut.Y;
            yl = opts.YLabel;
            if yl == "", yl = "Detection"; end

            % Points are shown on the scale they were fitted on, which is the
            % scale the criterion was applied on.
            sc = fitOut.Scale;
            if numel(sc) == 2 && sc(2) > sc(1) && ~(min(y) >= 0 && max(y) <= 1)
                y = (y - sc(1))./(sc(2)-sc(1));
                yl = yl + " (scaled)";
            end

            scatter(ax,x,y,50,[0.15 0.15 0.15],'filled','HandleVisibility','off');

            if ~isempty(fitOut.Predict)
                xs = linspace(min(x),max(x),200).';
                ys = fitOut.Predict(xs);
                line(ax,xs,ys,'Color',[0 0.4 0.75],'LineWidth',2, ...
                    'DisplayName',char(fitOut.Type));
            end

            if isfinite(fitOut.Threshold)
                xline(ax,fitOut.Threshold,'-r','LineWidth',2, ...
                    'Label',sprintf('%.1f',fitOut.Threshold), ...
                    'HandleVisibility','off');
                if all(isfinite(fitOut.CI))
                    yl2 = ylim(ax);
                    patch(ax,'XData',fitOut.CI([1 2 2 1]),'YData',yl2([1 1 2 2]), ...
                        'FaceColor',[0.85 0.2 0.2],'FaceAlpha',0.10,'EdgeColor','none', ...
                        'HandleVisibility','off');
                end
            end
            hold(ax,'off');
            grid(ax,'on'); box(ax,'on');
            xlabel(ax,char(opts.XLabel)); ylabel(ax,char(yl));
            title(ax,sprintf('%s fit, criterion %.2f',fitOut.Type,fitOut.Criterion));
            mabr.analysis.Plot.plainAxes(ax);
        end

        % =================================================================
        %  One condition
        % =================================================================
        function ax = waveform(X,t,opts)
            % One condition: the mean with an error band, optionally over the
            % individual sweeps.
            arguments
                X double
                t (:,1) double
                opts.Parent = []
                opts.Sweeps (1,1) logical = false
                opts.Band (1,1) string {mustBeMember(opts.Band,["none","std","sem","ci"])} = "sem"
                opts.Confidence (1,1) double = 0.95
                opts.Color (1,3) double = [0 0.35 0.7]
                opts.Scale (1,1) double = 1e6
                opts.Unit (1,1) string = "\muV"
            end
            if isempty(opts.Parent)
                ax = axes(figure('Name','ABR waveform','Color','w'));
            else
                ax = opts.Parent;
            end
            Y = opts.Scale*X;
            m = mean(Y,2);

            hold(ax,'on');
            if opts.Sweeps && size(Y,2) > 1
                line(ax,t,Y,'Color',[0.8 0.8 0.85]);
            end
            if opts.Band ~= "none" && size(Y,2) > 1
                hw = mabr.analysis.Plot.bandHalfWidth(Y,opts.Band,opts.Confidence);
                patch(ax,'XData',[t; flipud(t)],'YData',[m-hw; flipud(m+hw)], ...
                    'FaceColor',opts.Color,'FaceAlpha',0.20,'EdgeColor','none');
            end
            line(ax,t,m,'Color',opts.Color,'LineWidth',2);
            if t(1) < 0, xline(ax,0,'-','Color',[0.8 0.8 0.8]); end
            hold(ax,'off');
            axis(ax,'tight'); grid(ax,'on'); box(ax,'on');
            xlabel(ax,'Time (ms)'); ylabel(ax,sprintf('Amplitude (%s)',opts.Unit));
            title(ax,sprintf('%d sweeps',size(X,2)));
            mabr.analysis.Plot.plainAxes(ax);
        end

        % =================================================================
        %  Utilities
        % =================================================================
        function cm = palette(n,name)
            % n perceptually-ordered colors, without colorcet.
            %
            % The ends are trimmed: the extremes of a perceptual map are very
            % dark and very light, and neither reads as a line on white.
            arguments
                n (1,1) double {mustBePositive,mustBeInteger}
                name (1,1) string = "linear"
            end
            A = mabr.analysis.Plot.anchors(name);
            ta = linspace(0,1,size(A,1)).';
            if n == 1
                t = 0.5;
            else
                t = linspace(0.05,0.92,n).';
            end
            cm = min(max(interp1(ta,A,t,'pchip'),0),1);
        end

        function hw = bandHalfWidth(Y,kind,conf)
            % Half-width of an error band over columns of Y.
            n = size(Y,2);
            s = std(Y,0,2);
            switch kind
                case "std", hw = s;
                case "sem", hw = s./sqrt(n);
                case "ci"
                    if n < 2, hw = nan(size(s)); return; end
                    tq = mabr.metrics.t_quantile(1-(1-conf)/2,n-1);
                    hw = tq*s./sqrt(n);
                otherwise, hw = zeros(size(s));
            end
        end

        function plainAxes(ax)
            % Switch off the interactive axes toolbar, which fights with
            % programmatic limits and adds nothing to a static figure.
            for a = ax(:).'
                try %#ok<TRYNC>
                    if isprop(a,'Toolbar'), a.Toolbar.Visible = 'off'; end
                end
            end
        end
    end

    methods (Static, Access = private)
        function [lims,unitLabel] = gridLimits(M,opts)
            % One number per tile saying what its full scale is, whichever
            % normalization was asked for -- so the traces, the y limits and
            % the scale bar cannot disagree.
            [nRow,nCol] = size(M);
            lims = ones(nRow,nCol);

            switch opts.Normalize
                case "global"
                    m = max(cellfun(@(v) mabr.analysis.Plot.peakOr0(v),M),[],'all');
                    lims(:) = max(m,eps);
                case "column"
                    for c = 1:nCol
                        m = max(cellfun(@(v) mabr.analysis.Plot.peakOr0(v),M(:,c)));
                        lims(:,c) = max(m,eps);
                    end
                case "tile"
                    for i = 1:numel(M)
                        lims(i) = max(mabr.analysis.Plot.peakOr0(M{i}),eps);
                    end
                case "none"
                    m = max(cellfun(@(v) mabr.analysis.Plot.peakOr0(v),M),[],'all');
                    lims(:) = max(m,eps);
            end
            unitLabel = opts.Unit;
        end

        function p = peakOr0(v)
            if isempty(v), p = 0; else, p = max(abs(v(:))); end
        end

        function scaleBar(ax,fullScale,unit,normalize)
            % A bar of known size, drawn inside the axes, so a normalized grid
            % still says what its traces are worth.
            if ~isfinite(fullScale) || fullScale <= 0, return; end
            xl = xlim(ax); yl = ylim(ax);

            v = mabr.analysis.Plot.niceNumber(fullScale/2);
            if normalize == "none"
                h = v;                       % data units
            else
                h = v/fullScale;             % normalized units
            end
            if h <= 0 || h > 0.9*diff(yl), return; end

            x0 = xl(1) + 0.02*diff(xl);
            y0 = yl(1) + 0.05*diff(yl);
            line(ax,[x0 x0],[y0 y0+h],'Color','k','LineWidth',2,'Clipping','off');
            text(ax,x0 + 0.01*diff(xl), y0 + h/2, sprintf('%g %s',v,unit), ...
                'FontSize',8,'VerticalAlignment','middle','Clipping','off');
        end

        function v = niceNumber(x)
            % Nearest 1-2-5 rung at or below x.
            if ~isfinite(x) || x <= 0, v = 1; return; end
            e = floor(log10(x));
            m = x/10^e;
            if     m >= 5, m = 5;
            elseif m >= 2, m = 2;
            else,          m = 1;
            end
            v = m*10^e;
        end

        function xt = niceTicks(tv)
            span = tv(end)-tv(1);
            step = mabr.analysis.Plot.niceNumber(span/4);
            xt = ceil(tv(1)/step)*step : step : tv(end);
        end

        function A = anchors(name)
            switch lower(string(name))
                case "linear"   % viridis
                    A = [0.2670 0.0049 0.3294
                         0.2826 0.1409 0.4575
                         0.2539 0.2653 0.5300
                         0.2068 0.3718 0.5531
                         0.1636 0.4711 0.5581
                         0.1276 0.5669 0.5506
                         0.1347 0.6586 0.5176
                         0.4775 0.8214 0.3182
                         0.9932 0.9062 0.1439];
                case "fire"     % inferno
                    A = [0.0015 0.0005 0.0139
                         0.0874 0.0446 0.2248
                         0.2582 0.0386 0.4065
                         0.4163 0.0902 0.4329
                         0.5783 0.1480 0.4044
                         0.7357 0.2159 0.3302
                         0.8650 0.3168 0.2261
                         0.9545 0.4687 0.0999
                         0.9884 0.9984 0.6449];
                case "rainbow"
                    A = [0.1900 0.0718 0.2322
                         0.2748 0.4382 0.8577
                         0.1080 0.7178 0.8154
                         0.2296 0.9080 0.4661
                         0.7076 0.9755 0.2199
                         0.9782 0.7684 0.1936
                         0.9426 0.4127 0.0755
                         0.7226 0.1274 0.0221
                         0.4796 0.0158 0.0106];
                case "blue"
                    A = [0.9686 0.9843 1.0000
                         0.7725 0.8588 0.9373
                         0.4196 0.6824 0.8392
                         0.1294 0.4431 0.7098
                         0.0314 0.1882 0.4196];
                case "gray"
                    A = [0.95 0.95 0.95; 0.05 0.05 0.05];
                otherwise
                    error('mabr:analysis:Plot:palette', ...
                        'Unknown palette "%s". Choose from: %s.', ...
                        name, strjoin(mabr.analysis.Plot.PaletteNames,', '));
            end
        end
    end
end
