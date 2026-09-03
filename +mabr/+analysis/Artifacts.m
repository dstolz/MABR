classdef Artifacts
% mabr.analysis.Artifacts  Per-sweep artifact detection for one condition.
%
%   Every method here judges ONE condition -- a single [nSamples x nSweeps]
%   matrix -- and returns a flag per sweep. Nothing loops over conditions and
%   nothing removes a sweep: the verdict is a logical vector, and what to do
%   with it belongs to the caller (mabr.analysis.Session keeps the samples and
%   excludes flagged sweeps from every average, the same rule the acquisition
%   side follows in mabr.data.Recording).
%
%       isArt = mabr.analysis.Artifacts.detect(X, Rows=respIdx);
%       isArt = mabr.analysis.Artifacts.detect(X, Method="threshold", Threshold=50e-6);
%
%   Two families of criterion, and the difference matters:
%
%     RELATIVE ("median","mean","quartiles","grubbs","gesd","movmedian",
%     "movmean") flags sweeps that stand out from the OTHERS in the same
%     condition, via ISOUTLIER. This is what the offline pipeline has always
%     done and it adapts to each electrode and each animal -- but it always
%     finds something, even in clean data, and it cannot flag a condition that
%     is uniformly bad.
%
%     ABSOLUTE ("threshold") flags sweeps whose feature exceeds a fixed number,
%     which is what mabr.metrics.detect_artifacts does live during acquisition.
%     It is decidable for one sweep on its own, comparable across a session,
%     and it CAN condemn a whole condition -- which is sometimes the truth.
%
%   The feature is computed inside a response window (Rows), because a sweep is
%   judged on the part of it being measured: baseline drift before the onset is
%   not the same defect as a movement transient on top of wave IV.
%
%   See also mabr.analysis.Session, mabr.metrics.detect_artifacts, isoutlier

    properties (Constant)
        % Feature names accepted by feature() and detect().
        Features = ["rms","std","meanabs","peak2peak","posPeak","negPeak","absPeak"]

        % isoutlier methods accepted, plus the absolute "threshold" criterion.
        Methods = ["median","mean","quartiles","grubbs","gesd","movmedian","movmean","threshold","none"]
    end

    methods (Static)
        function [isArt,info] = detect(X,opts)
            % Flag artifact sweeps in one [nSamples x nSweeps] matrix.
            %
            %   isArt   1 x nSweeps logical
            %   info    struct with .feature (the per-sweep value), .lower,
            %           .upper (the bounds applied), .method, .name, .count
            arguments
                X double
                opts.Rows = []            % logical mask or indices into rows of X
                opts.Feature (1,1) string {mustBeMember(opts.Feature, ...
                    ["rms","std","meanabs","peak2peak","posPeak","negPeak","absPeak"])} = "absPeak"
                opts.Method (1,1) string {mustBeMember(opts.Method, ...
                    ["median","mean","quartiles","grubbs","gesd","movmedian","movmean","threshold","none"])} = "median"
                opts.Threshold (1,1) double {mustBePositive} = Inf
                opts.MethodArgs struct = struct()
            end

            info = struct('feature',[],'lower',[],'upper',[], ...
                'method',opts.Method,'name',opts.Feature,'count',0);

            if isempty(X)
                isArt = false(1,0);
                return
            end

            f = mabr.analysis.Artifacts.feature(X,opts.Feature,opts.Rows);
            info.feature = f(:).';

            switch opts.Method
                case "none"
                    isArt = false(1,numel(f));

                case "threshold"
                    if ~isfinite(opts.Threshold)
                        error('mabr:analysis:Artifacts:noThreshold', ...
                            'Method "threshold" requires a finite Threshold.');
                    end
                    % A signed feature (negPeak) is judged on its magnitude;
                    % every other feature here is already non-negative.
                    isArt = abs(f(:).') > opts.Threshold;
                    info.lower = -opts.Threshold;
                    info.upper =  opts.Threshold;

                otherwise
                    nv = namedargs2cell(opts.MethodArgs);
                    if isempty(nv)
                        [isArt,lo,up] = isoutlier(f(:),opts.Method);
                    else
                        [isArt,lo,up] = isoutlier(f(:),opts.Method,nv{:});
                    end
                    isArt = reshape(logical(isArt),1,[]);
                    info.lower = lo(:).';
                    info.upper = up(:).';
            end

            info.count = sum(isArt);
        end

        function f = feature(X,name,rows)
            % Per-sweep feature within a response window. Pure: no state, no
            % thresholds, no decisions -- just a number per column of X.
            arguments
                X double
                name (1,1) string {mustBeMember(name, ...
                    ["rms","std","meanabs","peak2peak","posPeak","negPeak","absPeak"])} = "absPeak"
                rows = []
            end
            if isempty(X), f = zeros(1,0); return; end

            Y = mabr.analysis.Artifacts.windowRows(X,rows);

            switch name
                case "rms",       f = sqrt(mean(Y.^2,1));
                case "std",       f = std(Y,0,1);
                case "meanabs",   f = mean(abs(Y),1);
                case "peak2peak", f = max(Y,[],1) - min(Y,[],1);
                case "posPeak",   f = max(Y,[],1);
                case "negPeak",   f = min(Y,[],1);
                case "absPeak",   f = max(abs(Y),[],1);
            end
            f = reshape(f,1,[]);
        end

        function Y = windowRows(X,rows)
            % Restrict X to the rows a caller nominated. Empty means all rows,
            % which is the only reading that cannot silently drop data.
            if isempty(rows)
                Y = X;
                return
            end
            if islogical(rows)
                if numel(rows) ~= size(X,1)
                    error('mabr:analysis:Artifacts:rowMismatch', ...
                        'Rows mask has %d elements for %d samples.', numel(rows), size(X,1));
                end
                Y = X(rows,:);
            else
                Y = X(round(rows),:);
            end
            if isempty(Y)
                error('mabr:analysis:Artifacts:emptyWindow', ...
                    'Rows selected no samples.');
            end
        end

        function rows = windowMask(t,win)
            % Logical row mask for a [t0 t1] window over a time vector, both
            % in the same units. The one place a window becomes a mask, so a
            % rejection window and a plot window cannot round differently.
            arguments
                t (:,1) double
                win (1,2) double
            end
            rows = t >= min(win) & t <= max(win);
        end

        function ax = plotDiagnostic(X,isArt,info,opts)
            % Show what was rejected and why: the feature distribution with
            % the bounds that were applied, and the surviving mean with the
            % rejected sweeps drawn over it.
            arguments
                X double
                isArt (1,:) logical
                info struct = struct()
                opts.Time (:,1) double = []
                opts.Parent = []
            end
            if isempty(opts.Parent)
                fig = figure('Name','Artifact rejection','Color','w');
                tl = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
            else
                tl = opts.Parent;
            end

            t = opts.Time;
            if isempty(t), t = (1:size(X,1)).'; end

            ax = gobjects(1,2);
            ax(1) = nexttile(tl);
            if isfield(info,'feature') && ~isempty(info.feature)
                histogram(ax(1),info.feature,max(8,min(64,numel(info.feature))), ...
                    'FaceColor',[0.4 0.5 0.6],'EdgeColor','none');
                for b = [info.lower info.upper]
                    if isfinite(b), xline(ax(1),b,'--r','LineWidth',1.5); end
                end
            end
            grid(ax(1),'on'); box(ax(1),'on');
            xlabel(ax(1),sprintf('%s',info.name)); ylabel(ax(1),'sweeps');
            title(ax(1),sprintf('%s / %s',info.name,info.method));

            ax(2) = nexttile(tl);
            hold(ax(2),'on');
            if any(isArt), plot(ax(2),t,X(:,isArt),'Color',[0.85 0.5 0.5]); end
            if any(~isArt), plot(ax(2),t,mean(X(:,~isArt),2),'k','LineWidth',2); end
            hold(ax(2),'off');
            axis(ax(2),'tight'); grid(ax(2),'on'); box(ax(2),'on');
            xlabel(ax(2),'Time (ms)'); ylabel(ax(2),'Amplitude');
            title(ax(2),sprintf('%d of %d rejected',sum(isArt),numel(isArt)));

            mabr.analysis.Plot.plainAxes(ax);
        end
    end
end
