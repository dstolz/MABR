classdef Threshold
% mabr.analysis.Threshold  Response detection and threshold estimation.
%
%   Two single-purpose halves, deliberately kept apart:
%
%     detect(X,...)   judges ONE condition -- is there a time-locked response
%                     in this [nSamples x nSweeps] matrix? -- and returns a
%                     p-value, a detection strength, and a verdict.
%
%     fit(x,y,...)    fits ONE series -- level against detection -- and returns
%                     the level at which the criterion is met, with a
%                     confidence interval and a curve to draw.
%
%   Neither loops over conditions, frequencies, or sessions. Assembling the
%   series is the caller's job (mabr.analysis.Session.estimateThresholds does
%   it for one session's conditions; a study is your own loop over sessions).
%
%       d = mabr.analysis.Threshold.detect(X, Method="tfce", Seed=1);
%       f = mabr.analysis.Threshold.fit(levels, [d.isSig], Type="glm");
%       f.Threshold
%
%   Four models, and the choice is about what you are willing to assume:
%
%     "glm"      binomial logistic regression on the binary detections. The
%                psychometric reading: threshold is the level at which the
%                probability of detecting a response reaches Criterion.
%     "sigmoid"  logistic growth curve on the graded detection STRENGTH,
%                thresholded at Criterion of the response range. Uses more of
%                the evidence than a 0/1 collapse, at the cost of assuming the
%                strength grows sigmoidally. By default the asymptotes are
%                pinned to the observed range and only the midpoint and slope
%                are fitted -- see sigmoidFit, where the reason is spelled out.
%     "isotonic" monotone (pooled-adjacent-violators) fit. Assumes only that
%                detection does not get worse with level -- the safe choice
%                for a noisy or short series.
%     "minimum"  the lowest level that was detected. No model at all; entirely
%                determined by the level spacing, which is why it is a
%                fallback rather than a default.
%
%   Nothing here needs the Statistics or Curve Fitting toolboxes, which
%   mabr.Config deliberately does not require: the logistic regression is
%   iteratively reweighted least squares, the sigmoid is FMINSEARCH, and the
%   confidence intervals are Monte Carlo draws from a parameter covariance
%   estimated from the fit's own Jacobian.
%
%   CRITERION MEANS TWO DIFFERENT THINGS, and which one it means is decided by
%   FitTarget, not by the model. On BINARY detections it is a probability: the
%   threshold is the level at which a response becomes detectable half the time
%   (at Criterion = 0.5), which is what "ABR threshold" normally means. On
%   graded STRENGTH it is a fraction of the response range: Criterion = 0.5 is
%   the HALF-MAXIMUM of the growth function, which on real data sits well above
%   the level at which the response first became detectable, because the
%   response goes on growing after it appears. Both are useful and neither is
%   wrong; reading one as the other is. estimate()'s "auto" gives each model
%   the target it is a model of, so ask for FitTarget="binary" explicitly when
%   you want a detection threshold out of a sigmoid or an isotonic fit.
%
%   A threshold that could not be reached is Inf, never a made-up number. It
%   means "no response at any level presented", which is a finding; deciding
%   what to plot for it (usually max(level)+step) belongs to the caller, which
%   is why estimateThresholds keeps it separate from the curated value.
%
%   See also mabr.analysis.PermTest, mabr.analysis.Session

    methods (Static)
        % =================================================================
        %  Detection: one condition
        % =================================================================
        function d = detect(X,opts)
            % Detect a time-locked response in one [nSamples x nSweeps] matrix.
            %
            %   d.p         global p-value
            %   d.isSig     p < Alpha
            %   d.strength  max-statistic (graded evidence, method-specific)
            %   d.nSweeps   sweeps the test was run on
            %   d.result    the full mabr.analysis.PermTest result
            arguments
                X double
                opts.Rows = []                 % response window, rows of X
                opts.Method (1,1) string {mustBeMember(opts.Method,["clusterMass","tmax","tfce"])} = "clusterMass"
                opts.NumPermutations (1,1) double {mustBeInteger,mustBePositive} = 1000
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1)} = 0.05
                opts.MinClusterSize (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.TFCE struct = struct('E',0.5,'H',2.0,'dh',0.1)
                opts.Seed = []
            end

            d = struct('p',NaN,'isSig',false,'strength',NaN,'nSweeps',0,'result',struct());

            if isempty(X), return; end
            Y = mabr.analysis.Artifacts.windowRows(X,opts.Rows);

            [p,res] = mabr.analysis.PermTest.run(Y, ...
                Method=opts.Method, NumPermutations=opts.NumPermutations, ...
                Alpha=opts.Alpha, MinClusterSize=opts.MinClusterSize, ...
                TFCE=opts.TFCE, Seed=opts.Seed);

            d.p        = min(max(p,0),1);
            d.isSig    = d.p < opts.Alpha;
            d.strength = res.statistic;
            d.nSweeps  = res.nSweeps;
            d.result   = res;
        end

        % =================================================================
        %  Threshold: one series
        % =================================================================
        function out = fit(x,y,opts)
            % Estimate the threshold from one level series.
            %
            %   x   levels (any ordered stimulus dimension), [nLevels x 1]
            %   y   detection per level: binary, a probability, or a strength
            %
            %   out.Threshold  the estimate (Inf when the criterion is never met)
            %   out.CI         [lower upper], NaN when unavailable
            %   out.Type       model actually used (may differ from the request
            %                  when a fit failed and the fallback ran)
            %   out.Predict    @(x) fitted curve, for drawing
            %   out.Model      the fitted parameters
            arguments
                x (:,1) double
                y (:,1) double
                opts.Type (1,1) string {mustBeMember(opts.Type,["glm","sigmoid","isotonic","minimum"])} = "glm"
                opts.Criterion (1,1) double {mustBeInRange(opts.Criterion,0,1)} = 0.5
                opts.Weights (:,1) double = []
                opts.Normalize (1,1) logical = true   % scale a non-[0,1] y before applying Criterion
                opts.Asymptotes (1,1) string {mustBeMember(opts.Asymptotes,["fixed","fit"])} = "fixed"
                opts.Extrapolate (1,1) logical = true
                opts.NearestLevel (1,1) logical = false
                opts.Interpolate (1,1) logical = false % isotonic/minimum: interpolate between levels
                opts.CINumSamples (1,1) double {mustBeInteger,mustBePositive} = 2000
                opts.CIAlpha (1,1) double {mustBeInRange(opts.CIAlpha,0,1)} = 0.05
                opts.Ridge (1,1) double {mustBeNonnegative} = 1e-6
                opts.Seed = []
            end

            out = struct('Threshold',Inf,'CI',[NaN NaN],'Type',opts.Type, ...
                'Criterion',opts.Criterion,'Predict',[],'Model',[], ...
                'X',x,'Y',y,'Scale',[0 1],'Converged',false,'Message',"");

            w = opts.Weights;
            if isempty(w), w = ones(size(x)); end
            w(~isfinite(w) | w <= 0) = 1;

            good = isfinite(x) & isfinite(y) & isfinite(w);
            x = x(good); y = y(good); w = w(good);
            [x,i] = sort(x); y = y(i); w = w(i);

            if numel(x) < 2
                out.Message = "Fewer than two usable levels.";
                return
            end

            % Criterion is a fraction of the response range, so a strength in
            % arbitrary units has to be put on [0,1] before it can be applied.
            % Binary and probability data are already there and are left alone.
            lo = min(y); hi = max(y);
            inUnit = lo >= 0 && hi <= 1;
            if opts.Normalize && ~inUnit && hi > lo
                out.Scale = [lo hi];
                yFit = (y - lo) ./ (hi - lo);
            else
                yFit = y;
            end

            if isempty(opts.Seed), stream = []; else, stream = RandStream('threefry','Seed',opts.Seed); end

            try
                switch opts.Type
                    case "glm"
                        out = mabr.analysis.Threshold.fitLogistic(out,x,yFit,w,opts,stream);
                    case "sigmoid"
                        out = mabr.analysis.Threshold.fitSigmoid(out,x,yFit,w,opts,stream);
                    case "isotonic"
                        out = mabr.analysis.Threshold.fitIsotonic(out,x,yFit,w,opts);
                    case "minimum"
                        out = mabr.analysis.Threshold.fitMinimum(out,x,yFit,opts);
                end
            catch ME
                % A failed fit falls back to the assumption-free answer rather
                % than to no answer, and says so.
                out.Message = string(ME.message);
                out = mabr.analysis.Threshold.fitMinimum(out,x,yFit,opts);
                out.Type = "minimum";
            end

            % Clamp / pin, in that order: clamping decides whether an
            % extrapolated estimate is allowed at all, pinning then puts an
            % allowed estimate on a level that was actually presented.
            if ~opts.Extrapolate && isfinite(out.Threshold)
                out.Threshold = min(max(out.Threshold,min(x)),max(x));
                out.CI = min(max(out.CI,min(x)),max(x));
            end
            if opts.NearestLevel && isfinite(out.Threshold)
                k = find(x >= out.Threshold,1,'first');
                if ~isempty(k), out.Threshold = x(k); end
            end
        end

        function out = estimate(levels,det,opts)
            % Fit a threshold to one series of DETECT results.
            %
            % The one place the choice of fit target lives: "binary" is the
            % detection verdict, "strength" the graded max-statistic, "p" the
            % complement of the p-value. Left on "auto", each model gets the
            % target it is actually about -- a GLM is a model of a yes/no
            % outcome, a sigmoid a model of a graded one.
            arguments
                levels (:,1) double
                det struct                      % struct array from detect(), one per level
                opts.Type (1,1) string {mustBeMember(opts.Type,["glm","sigmoid","isotonic","minimum"])} = "glm"
                opts.FitTarget (1,1) string {mustBeMember(opts.FitTarget,["auto","binary","p","strength"])} = "auto"
                opts.Criterion (1,1) double {mustBeInRange(opts.Criterion,0,1)} = 0.5
                opts.Asymptotes (1,1) string {mustBeMember(opts.Asymptotes,["fixed","fit"])} = "fixed"
                opts.Extrapolate (1,1) logical = true
                opts.NearestLevel (1,1) logical = false
                opts.CIAlpha (1,1) double {mustBeInRange(opts.CIAlpha,0,1)} = 0.05
                opts.CINumSamples (1,1) double {mustBeInteger,mustBePositive} = 2000
                opts.Seed = []
            end

            target = opts.FitTarget;
            if target == "auto"
                switch opts.Type
                    case "glm",      target = "binary";
                    case "sigmoid",  target = "strength";
                    case "isotonic", target = "strength";
                    otherwise,       target = "binary";
                end
            end

            strength = [det.strength].';
            if target == "strength" && ~any(isfinite(strength))
                target = "binary";      % nothing graded to fit
            end

            switch target
                case "binary",   y = double([det.isSig].');
                case "p",        y = 1 - [det.p].';
                case "strength", y = strength;
            end

            w = [det.nSweeps].';

            out = mabr.analysis.Threshold.fit(levels,y, ...
                Type=opts.Type, Criterion=opts.Criterion, Weights=w, ...
                Asymptotes=opts.Asymptotes, ...
                Extrapolate=opts.Extrapolate, NearestLevel=opts.NearestLevel, ...
                CIAlpha=opts.CIAlpha, CINumSamples=opts.CINumSamples, Seed=opts.Seed);
            out.FitTarget = target;
        end

        % =================================================================
        %  Model fitting (public so they can be used and tested on their own)
        % =================================================================
        function [b,covB,converged] = logisticIRLS(x,y,w,ridge)
            % Weighted binomial logistic regression by iteratively reweighted
            % least squares. Replaces fitglm so that no Statistics toolbox is
            % needed; y may be fractional, which IRLS handles as a binomial
            % proportion the same way a GLM with weights does.
            %
            %   x          predictor (level), [n x 1]
            %   y          response in [0 1] (binary or fractional), [n x 1]
            %   w          per-observation weight, [n x 1]
            %   ridge      ridge penalty added to the normal equations (default 1e-6)
            %   b          (returned) [intercept; slope], [2 x 1]
            %   covB       (returned) [2 x 2] covariance of b (NaN(2) if ill-conditioned)
            %   converged  (returned) 1x1 logical
            arguments
                x (:,1) double
                y (:,1) double
                w (:,1) double
                ridge (1,1) double = 1e-6
            end
            n = numel(x);
            X = [ones(n,1) x];
            y = min(max(y,0),1);

            % Start from a least-squares fit to the clipped logit, which is a
            % good enough guess that IRLS converges in a handful of steps.
            yc  = min(max(y,0.02),0.98);
            b   = X \ log(yc./(1-yc));
            R   = ridge*eye(2);
            converged = false;

            for it = 1:100
                eta = X*b;
                mu  = 1./(1+exp(-eta));
                v   = max(mu.*(1-mu),1e-9);
                W   = w.*v;
                z   = eta + (y-mu)./v;
                A   = X.'*(W.*X) + R;
                bNew = A \ (X.'*(W.*z));
                if ~all(isfinite(bNew)), break; end
                if norm(bNew-b) < 1e-10*(1+norm(b)), b = bNew; converged = true; break; end
                b = bNew;
            end

            eta = X*b;
            mu  = 1./(1+exp(-eta));
            W   = w.*max(mu.*(1-mu),1e-9);
            A   = X.'*(W.*X) + R;
            if rcond(A) > eps
                covB = inv(A);
            else
                covB = nan(2);
            end
        end

        function [p,resid,J,converged] = sigmoidFit(x,y,w,asymptotes)
            % Logistic growth curve  y = A + (B-A)/(1+exp(-(x-c)/d))  by
            % FMINSEARCH on the weighted sum of squares, with d kept positive
            % through its logarithm so the curve cannot fit backwards.
            %
            % ASYMPTOTES is the decision that matters on a real level series.
            % "fixed" (the default) takes A and B from the observed range and
            % fits only the midpoint c and the slope d; "fit" estimates all
            % four. Four free parameters on the six or eight levels an ABR
            % series actually holds is over-parametrized whenever the response
            % is still growing at the loudest level -- which is the usual case
            % -- and the fit then answers by inventing a ceiling far above
            % anything measured and moving the midpoint out with it. With the
            % asymptotes pinned to the data, Criterion means a fraction of the
            % response range that was actually observed, which is both stable
            % and what a half-maximum threshold has always meant.
            %
            % Several starts, because a single start on a short series lands in
            % a flat region often enough to matter.
            %
            %   x          predictor (level), [n x 1]
            %   y          response, [n x 1]
            %   w          per-observation weight (default all ones), [n x 1]
            %   asymptotes "fixed" (default, A/B pinned to data range) or "fit"
            %   p          (returned) [4 x 1]: [A;B;c;log(d)] regardless of
            %              which branch ran (fixed A0/B0 are reported too)
            %   resid      (returned) [n x 1] residuals y - model(p,x) (equal
            %              to y itself if the fit did not converge)
            %   J          (returned) [n x 4] finite-difference Jacobian at the
            %              solution (columns of a pinned asymptote are zero);
            %              [] if the fit did not converge
            %   converged  (returned) 1x1 logical
            arguments
                x (:,1) double
                y (:,1) double
                w (:,1) double = ones(size(x))
                asymptotes (1,1) string {mustBeMember(asymptotes,["fixed","fit"])} = "fixed"
            end
            w = w./mean(w);
            A0 = min(y); B0 = max(y);
            xrange = max(x)-min(x);
            widths = log(max(eps,xrange./[8 4 12])).';
            mids   = [median(x); mean(x); x(max(1,ceil(numel(x)/3)))];

            if asymptotes == "fixed"
                model  = @(q,xx) A0 + (B0-A0)./(1+exp(-(xx-q(1))./exp(q(2))));
                starts = [mids widths];
            else
                model  = @(q,xx) q(1) + (q(2)-q(1))./(1+exp(-(xx-q(3))./exp(q(4))));
                starts = [repmat([A0 B0],3,1) mids widths];
            end
            sse = @(q) sum(w.*(y - model(q,x)).^2);

            best = []; bestVal = Inf;
            o = optimset('Display','off','MaxFunEvals',4000,'MaxIter',4000, ...
                'TolX',1e-8,'TolFun',1e-10);
            for k = 1:size(starts,1)
                try %#ok<TRYNC>
                    [qk,vk] = fminsearch(sse,starts(k,:).',o);
                    if vk < bestVal, bestVal = vk; best = qk; end
                end
            end
            converged = ~isempty(best) && all(isfinite(best));
            if ~converged
                p = nan(4,1); resid = y; J = [];
                return
            end

            resid = y - model(best,x);

            % Finite-difference Jacobian at the solution, for the covariance
            % the confidence interval is drawn from. A pinned asymptote carries
            % no uncertainty of its own, so its column stays zero.
            J = zeros(numel(x),4);
            if asymptotes == "fixed", cols = [3 4]; else, cols = 1:4; end
            for k = 1:numel(best)
                h  = max(1e-6, abs(best(k))*1e-6);
                qk = best; qk(k) = qk(k)+h;
                J(:,cols(k)) = (model(qk,x) - model(best,x))/h;
            end

            % Reported in one shape whichever branch ran, so every caller reads
            % [A B c log(d)] and nothing has to ask which it was.
            if asymptotes == "fixed"
                p = [A0; B0; best(1); best(2)];
            else
                p = best;
            end
        end

        function iso = isotonicPAV(x,y,w)
            % Isotonic (non-decreasing) regression by pooled adjacent
            % violators, weighted, with repeated x collapsed first.
            %
            %   x    predictor (level), [n x 1]
            %   y    response, [n x 1]
            %   w    per-observation weight (default all ones), [n x 1]
            %   iso  (returned) struct: .x (unique levels), .y (weighted mean
            %        per level), .w (summed weight per level), .yhat
            %        (monotone-fitted value per level)
            arguments
                x (:,1) double
                y (:,1) double
                w (:,1) double = ones(size(x))
            end
            [xs,i] = sort(x); ys = y(i); ws = w(i);
            [xu,~,g] = unique(xs);
            yu = accumarray(g,ys.*ws,[],@sum) ./ accumarray(g,ws,[],@sum);
            wu = accumarray(g,ws,[],@sum);

            % Block form of PAV: push each point on a stack, merging backwards
            % while the last block violates monotonicity.
            n = numel(xu);
            val = zeros(n,1); wgt = zeros(n,1); last = zeros(n,1);
            top = 0;
            for k = 1:n
                top = top + 1;
                val(top) = yu(k); wgt(top) = wu(k); last(top) = k;
                while top > 1 && val(top-1) > val(top)
                    wsum = wgt(top-1) + wgt(top);
                    val(top-1) = (wgt(top-1)*val(top-1) + wgt(top)*val(top))/wsum;
                    wgt(top-1) = wsum;
                    last(top-1) = last(top);
                    top = top - 1;
                end
            end

            yhat = zeros(n,1);
            first = 1;
            for b = 1:top
                yhat(first:last(b)) = val(b);
                first = last(b) + 1;
            end

            iso = struct('x',xu,'y',yu,'w',wu,'yhat',yhat);
        end
    end

    methods (Static, Access = private)
        function out = fitLogistic(out,x,y,w,opts,stream)
            % GLM branch of fit(). out: the partially-filled result struct
            % from fit() (in/out); x,y,w: as in fit()/logisticIRLS; opts: the
            % fit() options struct; stream: RandStream for the CI draw, or [].
            % Returns out with Type/Converged/Model/Predict/Threshold/CI set
            % (falls back to fitIsotonic when the fitted slope is not positive).
            [b,covB,conv] = mabr.analysis.Threshold.logisticIRLS(x,y,w,opts.Ridge);
            slope = b(2);

            if ~isfinite(slope) || slope <= 0
                % A flat or falling psychometric function is not a threshold.
                % Fall back on the monotone fit, which cannot invert.
                out = mabr.analysis.Threshold.fitIsotonic(out,x,y,w,opts);
                out.Type = "isotonic";
                out.Message = "GLM slope was not positive; used isotonic fit.";
                return
            end

            out.Type      = "glm";
            out.Converged = conv;
            out.Model     = struct('b',b,'cov',covB);
            out.Predict   = @(xx) 1./(1+exp(-(b(1)+b(2)*xx(:))));
            out.Threshold = mabr.analysis.Threshold.logitInverse(b(1),b(2),opts.Criterion);

            if all(isfinite(covB(:)))
                out.CI = mabr.analysis.Threshold.ciLogistic(b,covB,opts,stream);
            end
        end

        function out = fitSigmoid(out,x,y,w,opts,stream)
            % Sigmoid branch of fit(). Same in/out shape as fitLogistic;
            % throws mabr:analysis:Threshold:sigmoidFailed on non-convergence
            % (caught by fit(), which falls back to fitMinimum).
            [p,resid,J,conv] = mabr.analysis.Threshold.sigmoidFit(x,y,w,opts.Asymptotes);
            if ~conv || ~all(isfinite(p))
                error('mabr:analysis:Threshold:sigmoidFailed','Sigmoid fit did not converge.');
            end

            A = p(1); B = p(2); c = p(3); d = exp(p(4));
            out.Type      = "sigmoid";
            out.Converged = true;
            out.Model     = struct('A',A,'B',B,'c',c,'d',d,'p',p, ...
                'asymptotes',opts.Asymptotes);
            out.Predict   = @(xx) A + (B-A)./(1+exp(-(xx(:)-c)./d));

            yCrit = A + opts.Criterion*(B-A);
            out.Threshold = mabr.analysis.Threshold.sigmoidInverse(A,B,c,d,yCrit);

            % Parameter covariance from the fit's own Jacobian, then Monte
            % Carlo through the (nonlinear) threshold expression.
            free = any(J ~= 0,1);
            dof  = max(1,numel(x)-sum(free));
            s2   = sum(resid.^2)/dof;
            covP = zeros(4);
            Jf   = J(:,free);
            if ~isempty(Jf) && rcond(Jf.'*Jf) > eps
                covP(free,free) = s2 * inv(Jf.'*Jf);   %#ok<MINV>
                out.CI = mabr.analysis.Threshold.ciSigmoid(p,covP,opts,stream);
            end
        end

        function out = fitIsotonic(out,x,y,w,opts)
            % Isotonic branch of fit(). Same in/out shape as fitLogistic;
            % no CI is computed (out.CI stays [NaN NaN] from fit()'s default).
            iso = mabr.analysis.Threshold.isotonicPAV(x,y,w);
            out.Type      = "isotonic";
            out.Converged = true;
            out.Model     = iso;
            out.Predict   = @(xx) interp1(iso.x,iso.yhat,xx(:),'previous','extrap');

            % Criterion applies to the fitted dynamic range, so a monotone fit
            % that never rises above its own floor has no threshold rather
            % than one at its first level.
            lo = min(iso.yhat); hi = max(iso.yhat);
            if hi <= lo
                out.Threshold = Inf;
                return
            end
            yc = lo + opts.Criterion*(hi-lo);
            k  = find(iso.yhat >= yc,1,'first');
            if isempty(k)
                out.Threshold = Inf;
            elseif opts.Interpolate && k > 1
                % Straight line between the bracketing levels, so the estimate
                % is not forced onto the level grid.
                y0 = iso.yhat(k-1); y1 = iso.yhat(k);
                f  = (yc - y0)/max(y1-y0,eps);
                out.Threshold = iso.x(k-1) + f*(iso.x(k)-iso.x(k-1));
            else
                out.Threshold = iso.x(k);
            end
        end

        function out = fitMinimum(out,x,y,opts)
            % Assumption-free fallback branch of fit(): the first level whose
            % y reaches Criterion of the observed range. Same in/out shape as
            % fitLogistic (no w, no CI).
            out.Type      = "minimum";
            out.Converged = true;
            out.Model     = struct('x',x,'y',y);
            out.Predict   = @(xx) interp1(x,y,xx(:),'previous','extrap');

            lo = min(y); hi = max(y);
            if hi <= lo
                out.Threshold = Inf;
                return
            end
            yc = lo + opts.Criterion*(hi-lo);
            k  = find(y >= yc,1,'first');
            if isempty(k)
                out.Threshold = Inf;
            else
                out.Threshold = x(k);
            end
        end

        % --- inverses -------------------------------------------------------
        function xc = logitInverse(b0,b1,pCrit)
            % Level at which the logistic curve with intercept b0, slope b1
            % reaches probability pCrit. xc: (returned) scalar level.
            pCrit = min(max(pCrit,eps),1-eps);
            xc = (log(pCrit/(1-pCrit)) - b0)/b1;
        end

        function xc = sigmoidInverse(A,B,c,d,yCrit)
            % Level at which the sigmoid A + (B-A)/(1+exp(-(x-c)/d)) reaches
            % yCrit. xc: (returned) scalar level, or NaN when yCrit is outside
            % (A,B) or the curve is degenerate.
            if ~all(isfinite([A B c d])) || d == 0 || A == B, xc = NaN; return; end
            t = (B-A)/(yCrit-A) - 1;              % exp(-(x-c)/d)
            if ~isfinite(t) || t <= 0, xc = NaN; return; end
            xc = c - d*log(t);
        end

        % --- confidence intervals -------------------------------------------
        function ci = ciLogistic(b,covB,opts,stream)
            % Monte Carlo CI on the GLM threshold: draws parameters from
            % N(b,covB), inverts each draw, takes the percentile interval.
            % b: [2x1], covB: [2x2], opts: fit() options (Criterion,
            % CINumSamples, CIAlpha used), stream: RandStream or [].
            % ci: (returned) [lower upper], [NaN NaN] if covB is singular.
            n = max(100,opts.CINumSamples);
            S = (covB+covB.')/2 + 1e-12*eye(2);
            [R,fail] = chol(S,'lower');
            if fail, ci = [NaN NaN]; return; end

            z = mabr.analysis.Threshold.randn2(2,n,stream);
            P = b + R*z;
            th = nan(1,n);
            ok = P(2,:) > 0;
            th(ok) = arrayfun(@(i) mabr.analysis.Threshold.logitInverse(P(1,i),P(2,i),opts.Criterion), find(ok));
            ci = mabr.analysis.Threshold.percentileCI(th,opts.CIAlpha);
        end

        function ci = ciSigmoid(p,covP,opts,stream)
            % Monte Carlo CI on the sigmoid threshold, same idea as
            % ciLogistic. p: [4x1] = [A;B;c;log(d)], covP: [4x4] (singular in
            % the pinned rows/columns of a fixed-asymptote fit), opts/stream
            % as ciLogistic. ci: (returned) [lower upper], [NaN NaN] if no
            % parameter is free or the free covariance block is singular.
            n = max(100,opts.CINumSamples);
            S = (covP+covP.')/2;
            % A pinned asymptote has zero variance, so this covariance is
            % singular by construction: draw the free parameters through their
            % own block and leave the pinned ones exactly where they are.
            free = any(S ~= 0,1);
            if ~any(free), ci = [NaN NaN]; return; end
            [R,fail] = chol(S(free,free) + 1e-12*eye(sum(free)),'lower');
            if fail, ci = [NaN NaN]; return; end

            P = repmat(p(:),1,n);
            P(free,:) = P(free,:) + R*mabr.analysis.Threshold.randn2(sum(free),n,stream);
            th = nan(1,n);
            for i = 1:n
                A = P(1,i); B = P(2,i); c = P(3,i); d = exp(P(4,i));
                th(i) = mabr.analysis.Threshold.sigmoidInverse(A,B,c,d,A+opts.Criterion*(B-A));
            end
            ci = mabr.analysis.Threshold.percentileCI(th,opts.CIAlpha);
        end

        function ci = percentileCI(th,alpha)
            % th: 1 x n Monte Carlo threshold draws (may contain NaN/Inf,
            % dropped before use); alpha: two-sided CI level. ci: (returned)
            % [lower upper] percentile interval, [NaN NaN] if fewer than 10
            % finite draws remain.
            th = th(isfinite(th));
            if numel(th) < 10, ci = [NaN NaN]; return; end
            ci = mabr.analysis.Threshold.percentile(th,[alpha/2 1-alpha/2]);
        end

        function q = percentile(x,p)
            % Linear-interpolation percentile, so no Statistics toolbox is
            % needed for a confidence interval.
            %
            %   x  data vector, any shape
            %   p  probabilities in [0 1], any shape
            %   q  (returned) percentile values, same shape as p (NaN(size(p))
            %      when x is empty)
            x = sort(x(:));
            n = numel(x);
            if n == 0, q = nan(size(p)); return; end
            pos = p(:).'*n + 0.5;
            q = interp1((1:n).',x,min(max(pos,1),n),'linear');
        end

        function z = randn2(m,n,stream)
            % m,n: output size; stream: RandStream or [] (uses the global
            % stream). z: (returned) [m x n] standard normal draws.
            if isempty(stream), z = randn(m,n); else, z = randn(stream,m,n); end
        end
    end
end
