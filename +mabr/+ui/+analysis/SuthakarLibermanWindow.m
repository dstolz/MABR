classdef SuthakarLibermanWindow < handle
% mabr.ui.analysis.SuthakarLibermanWindow  A series as Suthakar & Liberman 2019 analysed it (their Figs. 2 and 3).
%
%   The method "suthakar-liberman" takes the paper's statistic and criterion
%   but decides by MABR's descending rule; this window shows what the paper
%   itself would have said, beside it (mabr.analysis.SuthakarLiberman):
%
%     top     the cross-covariance of each level's average with the
%             next-louder level's, against lag (xcov 'coeff'; Fig. 2B), lag 0
%             dotted and the method's lag allowance [0 MaxLag] shaded
%     bottom  r at lag 0 against level with the paper's two fits -- the
%             sigmoid (sigm_fit, its curve's 95% confidence band) and the
%             power law (power2, its 95% prediction band) -- the criterion
%             0.35, and the threshold with its interval in the panel of the
%             fit the decision tree chose (Figs. 2C-D, 3E-H); the method's
%             own r (the best lag) as grey rings, its threshold as a grey line
%     below   the path through the tree (A-D) and why, and the method's answer
%
%   It follows the Series tab: it draws the selected series, again whenever
%   the selection, the results or the session change. It changes nothing
%   and writes no preference but its position (mabr.ui.WindowPos,
%   "OfflineAnalysisSuthakar"). Every plot has Export figure… / Copy data /
%   Copy image.
%
%       w = mabr.ui.analysis.SuthakarLibermanWindow(model);              % the selected series
%       w = mabr.ui.analysis.SuthakarLibermanWindow(model,sk,Visible="off");   % a test
%       w.Result.Path, w.Result.Threshold, w.Data.Pairs
%
%   Tags: MABR_OFFLINE_SUTHAKAR (the figure), AnalysisSuthakarHeader,
%   AnalysisSuthakarCorrelogramAxes, AnalysisSuthakarSigmoidAxes,
%   AnalysisSuthakarPowerAxes, AnalysisSuthakarDecision, AnalysisSuthakarPaper,
%   AnalysisSuthakarClose; in the plots AnalysisSuthakarPair, ...LagZero,
%   ...LagAllowance, ...R0, ...RBest, ...Band, ...Curve, ...Criterion,
%   ...Threshold, ...MethodThreshold.
%
%   See also mabr.analysis.SuthakarLiberman, mabr.analysis.SeriesThreshold
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPosition = [180 110 1060 720]
        WindowName = "OfflineAnalysisSuthakar"
        FigureTag  = "MABR_OFFLINE_SUTHAKAR"
        SigmoidColor = [0.000 0.620 0.820]
        PowerColor   = [0.910 0.200 0.480]
        CriterionColor = [0.200 0.650 0.200]
        Margins = [56 44 16 26]
    end

    properties (SetAccess = private)
        Figure = []
        Model = []
        Host = []
        SeriesKey (1,1) string = ""
        Data = []                  % SuthakarLiberman.fromSession of the series drawn
        Result = []                % SuthakarLiberman.decide of it ([] with a Problem)
        Method = []                % the method's own answer (a compareMethods row), or []
        Done (1,1) logical = false
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners = event.listener.empty
        Rendering (1,1) logical = false
        RenderPending (1,1) logical = false
        Inputs = []                % what Result was decided from (Levels, R0)
        Cached = []                % the decision made from Inputs
    end

    methods
        function obj = SuthakarLibermanWindow(model,seriesKey,opts)
            % SuthakarLibermanWindow(model[,seriesKey],Visible=,Host=)
            arguments
                model
                seriesKey (1,1) string = ""
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.Host = []
            end
            if ~isa(model,'mabr.ui.analysis.Model')
                error('mabr:ui:SuthakarLibermanWindow:badModel', ...
                    'SuthakarLibermanWindow needs a mabr.ui.analysis.Model.');
            end
            obj.Model = model;
            obj.Host = opts.Host;
            if seriesKey == ""
                try
                    seriesKey = string(model.Selection.SeriesKey);
                catch
                end
            end
            obj.SeriesKey = seriesKey;
            f = uifigure('Name','Suthakar & Liberman 2019','Tag',char(obj.FigureTag), ...
                'Position',obj.DefaultPosition,'Visible','off');
            mabr.ui.WindowPos.restore(f,char(obj.WindowName),obj.DefaultPosition);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn = @(~,~) obj.close();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            setappdata(f,'SuthakarLibermanWindow',obj);   % (as AnalysisApp's: a test finds it)
            obj.Figure = f;
            obj.build();
            obj.Listeners = [ ...
                event.listener(model,'SelectionChanged',@(~,~) obj.onSelection())
                event.listener(model,'ResultsChanged',@(~,~) obj.refresh())
                event.listener(model,'SessionChanged',@(~,~) obj.refresh())];
            obj.refresh();
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        function refresh(obj)
            % Draw the series again from the session as it is now.
            if ~obj.isopen(), return; end
            if obj.Rendering
                obj.RenderPending = true;
                return
            end
            obj.Rendering = true;
            cleaner = onCleanup(@() obj.endRender());
            obj.render();
            clear cleaner
        end

        function showSeries(obj,seriesKey)
            % Draw another series of the open session.
            obj.SeriesKey = string(seriesKey);
            obj.refresh();
        end

        function close(obj)
            if obj.Done, return; end
            obj.Done = true;
            obj.closeFigure();
        end

        function cancel(obj)
            obj.close();
        end

        function tf = isopen(obj)
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            f = obj.Figure;
            muted = mabr.ui.analysis.Style.Muted;
            g = uigridlayout(f,[4 1],'Padding',[10 10 10 8],'RowSpacing',6);
            g.RowHeight = {'fit','1x','fit',30};
            obj.Ctrl.Header = uilabel(g,'Text','','WordWrap','on','FontColor',muted, ...
                'Tag','AnalysisSuthakarHeader');
            p = uigridlayout(g,[2 2],'Padding',[0 0 0 0],'RowSpacing',6,'ColumnSpacing',8);
            p.RowHeight = {'1x','1x'};
            p.ColumnWidth = {'1x','1x'};
            [obj.Ctrl.Corr,pc] = obj.plotAxes(p,'AnalysisSuthakarCorrelogramAxes');
            pc.Layout.Row = 1;  pc.Layout.Column = [1 2];
            [obj.Ctrl.Sig,ps] = obj.plotAxes(p,'AnalysisSuthakarSigmoidAxes');
            ps.Layout.Row = 2;  ps.Layout.Column = 1;
            [obj.Ctrl.Pow,pp] = obj.plotAxes(p,'AnalysisSuthakarPowerAxes');
            pp.Layout.Row = 2;  pp.Layout.Column = 2;
            obj.Ctrl.Decision = uilabel(g,'Text','','WordWrap','on','Tag','AnalysisSuthakarDecision', ...
                'FontSize',12,'VerticalAlignment','top');
            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.ColumnWidth = {'1x',150,80};
            uilabel(r,'Text',char(mabr.analysis.SuthakarLiberman.Citation),'FontColor',muted, ...
                'FontSize',10,'WordWrap','on');
            obj.Ctrl.Paper = uibutton(r,'Text','The paper (doi)','Tag','AnalysisSuthakarPaper', ...
                'Tooltip',char("https://doi.org/" + mabr.analysis.SuthakarLiberman.DOI), ...
                'ButtonPushedFcn',@(~,~) web(char("https://doi.org/" + mabr.analysis.SuthakarLiberman.DOI),'-browser'));
            uibutton(r,'Text','Close','Tag','AnalysisSuthakarClose', ...
                'Tooltip','Close this window (Esc)','ButtonPushedFcn',@(~,~) obj.close());
        end

        function [ax,panel] = plotAxes(obj,parent,tag)
            panel = uipanel(parent,'BorderType','none','BackgroundColor',[1 1 1]);
            ax = axes('Parent',panel,'Units','normalized','Position',[0.1 0.15 0.85 0.75], ...
                'Tag',tag,'FontSize',9,'Box','off','TickDir','out','Color',[1 1 1]);
            hold(ax,'on');
            mabr.ui.hideAxesToolbar(ax);
            disableDefaultInteractivity(ax);
            mabr.ui.analysis.Style.pinAxes(panel,ax,obj.Margins);
            cm = uicontextmenu(obj.Figure,'Tag',[tag 'Menu']);
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            ax.ContextMenu = cm;
        end

        function render(obj)
            S = [];
            try
                S = obj.Model.Session;
            catch
            end
            for ax = [obj.Ctrl.Corr obj.Ctrl.Sig obj.Ctrl.Pow]
                cla(ax);
                title(ax,'');
            end
            obj.Data = [];  obj.Result = [];  obj.Method = [];
            if isempty(S) || obj.SeriesKey == ""
                obj.say("Select a series on the Series tab.","");
                return
            end
            try
                D = mabr.analysis.SuthakarLiberman.fromSession(S,obj.SeriesKey);
            catch me
                obj.say("This series cannot be read: " + string(me.message),"");
                return
            end
            obj.Data = D;
            obj.Figure.Name = char("Suthakar & Liberman 2019 — " + obj.blind(D.SeriesLabel));
            win = sprintf('%g–%g ms',D.Window);
            head = obj.blind(D.SeriesLabel) + " · r of each level's average with the next-louder level's, " + ...
                "over the response window " + win + ".";
            obj.Method = obj.methodAnswer();
            obj.drawCorrelograms(D);
            if D.Problem ~= ""
                obj.say(head,D.Problem);
                return
            end
            % decided again only when what it is decided from changed (a
            % curation edit leaves the correlations as they were)
            in = struct('Key',obj.SeriesKey,'Levels',D.Levels,'R0',D.R0);
            if isempty(obj.Inputs) || ~isequaln(in,obj.Inputs) || isempty(obj.Cached)
                res = mabr.analysis.SuthakarLiberman.decide(D.Levels,D.R0);
                obj.Inputs = in;
                obj.Cached = res;
            end
            obj.Result = obj.Cached;
            obj.drawFit(obj.Ctrl.Sig,"sigmoid",D,obj.Result);
            obj.drawFit(obj.Ctrl.Pow,"power",D,obj.Result);
            msg = obj.Result.Message;
            if ~isempty(obj.Method)
                msg = msg + newline + "This method (suthakar-liberman, the descending rule on r at the best " + ...
                    sprintf('lag ≤ %g ms): ',D.MaxLag) + obj.Method.Text + ".";
            end
            obj.say(head,msg);
        end

        function drawCorrelograms(obj,D)
            ax = obj.Ctrl.Corr;
            P = D.Pairs;
            title(ax,'Cross-covariance with the next-louder level (xcov ''coeff'')','FontWeight','normal');
            xlabel(ax,'Signal lag (ms; positive: the quieter response later)');
            ylabel(ax,'Correlation');
            if isempty(P)
                text(ax,0.5,0.5,'No correlograms: the condition averages are not available.', ...
                    'Units','normalized','HorizontalAlignment','center', ...
                    'Color',mabr.ui.analysis.Style.Muted,'Tag','AnalysisSuthakarNoPairs');
                return
            end
            L = max(abs(vertcat(P.LagMs)));
            if ~(L > 0), L = 1; end
            yl = [-1 1];
            ml = D.MaxLag;
            if isfinite(ml) && ml > 0
                patch(ax,[0 ml ml 0],[yl(1) yl(1) yl(2) yl(2)],[1 0.88 0.70],'EdgeColor','none', ...
                    'FaceAlpha',0.6,'Tag','AnalysisSuthakarLagAllowance', ...
                    'DisplayName',sprintf('this method''s lag allowance (0–%g ms)',ml));
            end
            line(ax,[0 0],yl,'LineStyle',':','Color',[0 0 0],'Tag','AnalysisSuthakarLagZero', ...
                'DisplayName','lag 0 (the paper''s)');
            c = mabr.ui.analysis.Style.colorFor(1:numel(P),numel(P));
            [~,o] = sort([P.Level],'descend');          % loudest pair first, as the stack reads
            for k = 1:numel(o)
                q = P(o(k));
                line(ax,q.LagMs,q.R,'Color',c(k,:),'LineWidth',1,'Tag','AnalysisSuthakarPair', ...
                    'DisplayName',sprintf('%g with %g',q.Level,q.Louder));
                % the lower level at the pair's peak near lag 0, as the paper labels them
                near = abs(q.LagMs) <= max(1,2*max(ml,0));
                [rp,i] = max(q.R.*near - 10*~near);
                lg = q.LagMs(i);
                text(ax,lg,rp,sprintf(' %g',q.Level),'Color',c(k,:),'FontSize',8, ...
                    'VerticalAlignment','bottom','Tag','AnalysisSuthakarPairLabel','HitTest','off');
            end
            xlim(ax,[-L L]);
            ylim(ax,yl);
        end

        function drawFit(obj,ax,kind,D,res)
            SL = mabr.analysis.SuthakarLiberman;
            if kind == "sigmoid"
                f = res.Sigmoid;  col = obj.SigmoidColor;
                name = "Sigmoid (sigm_fit)";
                bandName = "95% confidence band of the curve";
            else
                f = res.Power;  col = obj.PowerColor;
                name = "Power law (power2)";
                bandName = "95% prediction band";
            end
            chosen = res.Fit == kind;
            if chosen
                name = name + " — chosen, path " + res.Path;
                if res.Noisy, name = name + " (noisy)"; end
            end
            title(ax,char(name),'FontWeight','normal','Interpreter','none');
            xlabel(ax,char(D.LevelLabel + " (the quieter level of each pair)"));
            ylabel(ax,'Correlation coefficient');
            x = res.X;
            step = 10;
            if numel(unique(x)) > 1, step = median(diff(unique(x))); end
            xl = [min(D.Levels) - step/2, max(D.Levels) + step/2];
            if ~all(isfinite(xl)), xl = [0 1]; end
            xx = linspace(xl(1),xl(2),241).';
            if f.Ok
                B = f.Band(xx);
                good = all(isfinite(B),2);
                if any(good)
                    xb = xx(good);  B = B(good,:);
                    patch(ax,[xb; flipud(xb)],[B(:,1); flipud(B(:,2))],col,'FaceAlpha',0.15, ...
                        'EdgeColor','none','Tag','AnalysisSuthakarBand','DisplayName',char(bandName));
                end
                yh = f.Predict(xx);
                line(ax,xx,yh,'Color',col,'LineWidth',1.5,'Tag','AnalysisSuthakarCurve', ...
                    'DisplayName',char(kind + " fit"));
            else
                text(ax,0.5,0.92,char("Not fitted: " + f.Message),'Units','normalized', ...
                    'HorizontalAlignment','center','Color',mabr.ui.analysis.Style.Muted, ...
                    'FontSize',9,'Tag','AnalysisSuthakarNotFitted');
            end
            crit = res.Criterion;
            line(ax,xl,[crit crit],'LineStyle','--','Color',obj.CriterionColor,'Tag','AnalysisSuthakarCriterion', ...
                'DisplayName',sprintf('criterion %.2f',crit));
            text(ax,xl(2),crit,sprintf('Criterion = %.2f ',crit),'Color',obj.CriterionColor, ...
                'HorizontalAlignment','right','VerticalAlignment','bottom','FontSize',8, ...
                'Tag','AnalysisSuthakarCriterionLabel','HitTest','off');
            % the method's r (best lag) where it differs from lag 0
            if isfinite(D.MaxLag) && D.MaxLag > 0
                rb = D.R;
                use = isfinite(rb) & isfinite(D.R0) & abs(rb - D.R0) > 1e-9;
                if any(use)
                    line(ax,D.Levels(use),rb(use),'LineStyle','none','Marker','o','MarkerSize',6, ...
                        'MarkerEdgeColor',[0.6 0.6 0.6],'Tag','AnalysisSuthakarRBest', ...
                        'DisplayName',sprintf('r at the best lag ≤ %g ms (this method)',D.MaxLag));
                end
            end
            line(ax,x,res.Y,'LineStyle','none','Marker','o','MarkerSize',6,'MarkerFaceColor',[0 0 0], ...
                'MarkerEdgeColor',[0 0 0],'Tag','AnalysisSuthakarR0','DisplayName','r at lag 0 (the paper''s)');
            % the method's threshold, for comparison
            mt = NaN;
            if ~isempty(obj.Method), mt = obj.Method.Threshold; end
            if isfinite(mt) && mt >= xl(1) && mt <= xl(2)
                line(ax,[mt mt],[-0.5 1],'Color',[0.55 0.55 0.55],'LineWidth',1,'Tag','AnalysisSuthakarMethodThreshold', ...
                    'DisplayName','this method''s threshold');
            end
            % the threshold, in the chosen fit's panel (the paper's arrow)
            if chosen && isfinite(res.Threshold)
                t = res.Threshold;
                line(ax,t,crit - 0.09,'LineStyle','none','Marker','^','MarkerSize',9, ...
                    'MarkerFaceColor',obj.CriterionColor,'MarkerEdgeColor',obj.CriterionColor, ...
                    'Tag','AnalysisSuthakarThreshold','DisplayName','threshold');
                txt = SL.valueText(t,res.Interval);
                if t < xl(1) || t > xl(2), txt = txt + " (outside the levels)"; end
                text(ax,min(max(t,xl(1)),xl(2)),crit - 0.17,char(txt),'Color',obj.CriterionColor, ...
                    'HorizontalAlignment','center','VerticalAlignment','top','FontSize',9, ...
                    'FontWeight','bold','Tag','AnalysisSuthakarThresholdLabel','HitTest','off');
            end
            if f.Ok
                if kind == "sigmoid"
                    st = sprintf('RMS error %.3f',f.RMSE);
                else
                    st = sprintf('RMS error %.3f · adjusted R² %.2f',f.RMSE,f.AdjR2);
                end
                text(ax,0.02,0.97,st,'Units','normalized','VerticalAlignment','top','FontSize',8, ...
                    'Color',mabr.ui.analysis.Style.Muted,'Tag','AnalysisSuthakarFitStats','HitTest','off');
            end
            vals = [res.Y; -0.5; 1];
            yl = [min(vals) max(vals)];
            yl = yl + [-0.05 0.05]*diff(yl);
            xlim(ax,xl);
            ylim(ax,yl);
        end

        function m = methodAnswer(obj)
            % The method's own answer for the series (Compare methods' row).
            m = [];
            try
                T = obj.Model.compareMethods(obj.SeriesKey);
                k = find(T.Method == "suthakar-liberman",1);
                if ~isempty(k)
                    m = struct('Threshold',T.Threshold(k),'Text',string(T.Text(k)),'Status',string(T.Status(k)));
                end
            catch
            end
        end

        function say(obj,head,msg)
            obj.Ctrl.Header.Text = char(head);
            obj.Ctrl.Decision.Text = char(msg);
        end

        function s = blind(obj,s)
            % Blind review masks names in every title (Model.blindText).
            s = string(s);
            try
                s = string(obj.Model.blindText(s));
            catch
            end
        end

        function onSelection(obj)
            try
                sk = string(obj.Model.Selection.SeriesKey);
            catch
                return
            end
            if sk ~= "" && sk ~= obj.SeriesKey
                obj.SeriesKey = sk;
                obj.refresh();
            end
        end

        function endRender(obj)
            obj.Rendering = false;
            if obj.RenderPending
                obj.RenderPending = false;
                obj.refresh();
            end
        end

        function onKey(obj,e)
            if strcmpi(e.Key,'escape'), obj.close(); end
        end

        function closeFigure(obj)
            try
                delete(obj.Listeners);
            catch
            end
            obj.Listeners = event.listener.empty;
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,char(obj.WindowName));
            delete(f);
            obj.Figure = [];
        end
    end
end
