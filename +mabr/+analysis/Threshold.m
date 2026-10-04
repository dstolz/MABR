classdef Threshold
% mabr.analysis.Threshold  Response detection and threshold estimation.
%
%   Two single-purpose halves, deliberately kept apart:
%
%     detect(X,...)   judges ONE condition -- is there a time-locked response
%                     in this [nSamples x nSweeps] matrix? -- and returns a
%                     p-value, a detection strength, and a verdict. Sweeps
%                     with no noise are not tested (p NaN, ZeroVariance), and
%                     TFCE is bounded to MaxTFCESteps steps.
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
%   FIRTH-PENALISED GLM. fit(...,Type="glm",Penalty="firth") replaces the
%   ridge-stabilised IRLS with Firth's bias-reduced logistic regression
%   (logisticFirth) and a profile penalised-likelihood interval
%   (firthProfileCI). A monotone ABR detection series is COMPLETELY
%   SEPARATED -- every level below some point missed, every level above it
%   detected -- and the ordinary maximum-likelihood fit then does not exist:
%   IRLS runs the slope off to infinity until a ridge or a variance floor
%   stops it, and both the threshold and its interval are set by that floor
%   rather than by the data. Firth's penalty keeps the estimates finite and
%   the profile interval honest about how little nine yes/no verdicts say.
%   Penalty "none" (the default) is today's fit, bit for bit, so every
%   existing script keeps its numbers; mabr.analysis.SeriesThreshold always
%   asks for Firth, with unit weights (one verdict per level is ONE
%   observation, whatever its sweep count).
%
%   prestoFit is the ABRpresto-like fit of a split-half correlation series
%   (Shaheen et al. 2025, Hear Res 462:109258), implemented from the paper's
%   description: a bounded sigmoid and a power law, the better one that
%   crosses the criterion, censoring when neither can.
%
%   Every fit-shaped struct this class returns carries Threshold, CI,
%   CIMethod ("montecarlo"|"profile"|"none"), CIOpen, Type, Criterion,
%   Predict, Model, X, Y, Scale, Converged, Message and Status ("ok" unless a
%   fit says otherwise). A saved fit carries no function handle, so
%   predictor(fit) rebuilds Predict after loading.
%
%   See also mabr.analysis.PermTest, mabr.analysis.Session,
%   mabr.analysis.SeriesThreshold

    properties (Constant)
        % Most threshold steps a TFCE map is integrated over (see detect).
        % At the default step of 0.1 that is a |t| of 100, which no
        % recording with noise in it reaches -- an ABR at 4000 sweeps is a t
        % of 10 to 30 -- so the step is raised only for near-noiseless data.
        % mabr.analysis.PermTest.MaxTFCESteps, ten times this, is PermTest's
        % own backstop for direct calls; a step raised here keeps every map
        % well under it, so that one never applies to a detect() test.
        MaxTFCESteps = 1000
    end

    methods (Static)
        % =================================================================
        %  Detection: one condition
        % =================================================================
        function d = detect(X,opts)
            % Detect a time-locked response in one [nSamples x nSweeps] matrix.
            %
            % NO NOISE, NO TEST. Sweeps that do not vary within their file x
            % polarity groups (mabr.analysis.SingleTrial.zeroVariance over the
            % tested rows: an all-zero channel, a digital loop-back, data
            % written without noise) are not tested: p is NaN, isSig false,
            % ZeroVariance true, and Flags says so. A sign-flip test of such
            % sweeps has nothing to compare the response with, and its t is
            % unbounded. Pass Polarity (and Strata) so that a polarity-
            % following CM is not mistaken for noise; without them the
            % sweeps are one group and only identical sweeps count.
            %
            % BOUNDED TFCE. TFCE integrates each t map in steps of TFCE.dh up
            % to its maximum, so a near-noiseless condition whose |t| runs to
            % 1e4 or 1e8 took that over dh steps per permutation block -- a
            % hang. When the largest |t| this test can meet (the observed
            % map and every permuted one, found by a t-max run on the same
            % sign flips, which depend on the seed and not on the method)
            % would need more than MaxTFCESteps steps, dh is raised to that
            % |t| over MaxTFCESteps for the observed map and the null alike
            % -- a valid test, integrated more coarsely -- and Flags says
            % so. Below that nothing changes, bit for bit.
            %
            %   d.p             global p-value (NaN: not tested)
            %   d.isSig         p < Alpha
            %   d.strength      max-statistic (graded evidence, method-specific)
            %   d.nSweeps       sweeps the test was run on
            %   d.result        the full mabr.analysis.PermTest result
            %                   (struct() when not tested)
            %   d.ZeroVariance  true when the sweeps hold no noise (not tested)
            %   d.TFCEStep      the TFCE step used (NaN for other methods)
            %   d.Flags         string row: why a test was not run, or ran
            %                   with a raised TFCE step
            arguments
                X double
                opts.Rows = []                 % response window, rows of X
                opts.Method (1,1) string {mustBeMember(opts.Method,["clusterMass","tmax","tfce"])} = "clusterMass"
                opts.NumPermutations (1,1) double {mustBeInteger,mustBePositive} = 1000
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1)} = 0.05
                opts.MinClusterSize (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.TFCE struct = struct('E',0.5,'H',2.0,'dh',0.1)
                opts.Seed = []
                opts.Polarity double = []      % 1 x nSweeps +1/-1 ([] = one polarity)
                opts.Strata double = []        % 1 x nSweeps file index ([] = one file)
            end

            d = struct('p',NaN,'isSig',false,'strength',NaN,'nSweeps',0,'result',struct(), ...
                'ZeroVariance',false,'TFCEStep',NaN,'Flags',strings(1,0));

            if isempty(X), return; end
            Y = mabr.analysis.Artifacts.windowRows(X,opts.Rows);
            n = size(Y,2);

            if mabr.analysis.SingleTrial.zeroVariance(Y,opts.Polarity,opts.Strata)
                d.nSweeps      = n;
                d.ZeroVariance = true;
                d.Flags        = mabr.analysis.SingleTrial.FlagZeroVariance;
                return
            end

            tfce = opts.TFCE;
            if opts.Method == "tfce"
                [tfce,d.TFCEStep,why] = mabr.analysis.Threshold.boundedTFCE(Y,tfce,opts);
                if why ~= "", d.Flags = why; end
            end

            [p,res] = mabr.analysis.PermTest.run(Y, ...
                Method=opts.Method, NumPermutations=opts.NumPermutations, ...
                Alpha=opts.Alpha, MinClusterSize=opts.MinClusterSize, ...
                TFCE=tfce, Seed=opts.Seed);

            % A test that could not be run (fewer than two sweeps) has no
            % p-value, and NaN has to stay NaN: clamped into [0 1] it became
            % 0, which read as the strongest detection a test can report.
            if isnan(p)
                d.p     = NaN;
                d.isSig = false;
            else
                d.p     = min(max(p,0),1);
                d.isSig = d.p < opts.Alpha;
            end
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
            %   out.CIMethod   "montecarlo" (glm/sigmoid draws), "profile"
            %                  (Firth), or "none" (no interval available)
            %   out.CIOpen     [lower upper] logical: a profile bound that ran
            %                  into the edge of its grid (that bound is NaN)
            %   out.Type       model actually used (may differ from the request
            %                  when a fit failed and the fallback ran)
            %   out.Predict    @(x) fitted curve, for drawing
            %   out.Model      the fitted parameters
            %   out.Status     "ok", or "insufficient" with fewer than two levels
            %
            %   opts.Penalty   "none" (default: ridge-stabilised IRLS, exactly
            %                  as before) or "firth" (glm only: Firth-penalised
            %                  fit, no ridge, profile-likelihood CI)
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
                opts.Penalty (1,1) string {mustBeMember(opts.Penalty,["none","firth"])} = "none"
                opts.Seed = []
            end

            out = struct('Threshold',Inf,'CI',[NaN NaN],'Type',opts.Type, ...
                'Criterion',opts.Criterion,'Predict',[],'Model',[], ...
                'X',x,'Y',y,'Scale',[0 1],'Converged',false,'Message',"", ...
                'CIMethod',"none",'CIOpen',[false false],'Status',"ok");

            w = opts.Weights;
            if isempty(w), w = ones(size(x)); end
            w(~isfinite(w) | w <= 0) = 1;

            good = isfinite(x) & isfinite(y) & isfinite(w);
            x = x(good); y = y(good); w = w(good);
            [x,i] = sort(x); y = y(i); w = w(i);

            if numel(x) < 2
                out.Message = "Fewer than two usable levels.";
                out.Status  = "insufficient";
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
                        if opts.Penalty == "firth"
                            out = mabr.analysis.Threshold.fitFirth(out,x,yFit,w,opts);
                        else
                            out = mabr.analysis.Threshold.fitLogistic(out,x,yFit,w,opts,stream);
                        end
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
            % Only FINITE interval ends are clamped: an unavailable bound is
            % NaN, and clamping turned it into a level (an isotonic fit's
            % [NaN NaN] read [min min], an interval nobody had computed).
            if ~opts.Extrapolate && isfinite(out.Threshold)
                out.Threshold = min(max(out.Threshold,min(x)),max(x));
                fin = isfinite(out.CI);
                out.CI(fin) = min(max(out.CI(fin),min(x)),max(x));
            end
            if opts.NearestLevel && isfinite(out.Threshold)
                k = find(x >= out.Threshold,1,'first');
                if ~isempty(k), out.Threshold = x(k); end
            end

            % A Monte Carlo interval that came back empty (too few finite
            % draws) is no interval; a profile interval keeps its name even
            % when both ends are open, because "open" is what it found.
            if out.CIMethod == "montecarlo" && all(isnan(out.CI))
                out.CIMethod = "none";
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

        % =================================================================
        %  Firth-penalised logistic regression
        % =================================================================
        function [b,covB,converged,ll] = logisticFirth(x,y,w)
            % Firth's bias-reduced logistic regression (Firth 1993,
            % Biometrika 80:27; Heinze & Schemper 2002, Stat Med 21:2409).
            %
            % Maximises the PENALISED log-likelihood
            %
            %     l*(b) = sum w.*(y.*log(mu) + (1-y).*log(1-mu)) + 1/2*log det(X'WX)
            %
            % -- the binomial log-likelihood plus half the log-determinant of
            % the Fisher information (Jeffreys' prior), X = [1 x], W =
            % w.*mu.*(1-mu) floored at 1e-12 -- by Fisher scoring on the
            % modified score X'(w.*(y-mu) + h.*(1/2-mu)), h the diagonal of
            % W^1/2 X (X'WX)^-1 X' W^1/2, halving a step (up to 10 times)
            % that would lower l*. As |b| grows the information and with it
            % det(X'WX) go to zero, so the penalty goes to -Inf: the maximum is
            % finite even under COMPLETE SEPARATION, which is the ordinary
            % state of a monotone ABR detection series, where the unpenalised
            % fit has no maximum at all.
            %
            % (With unit weights this is exactly the working-response form
            % z = eta + (y - mu + h.*(1/2-mu))./(mu.*(1-mu)); the h term is not
            % scaled by w, because the penalty is not a function of the weights'
            % count of observations but of the information they carry.)
            %
            %   x          predictor (level), [n x 1]
            %   y          response in [0 1] (binary or a proportion), [n x 1]
            %   w          case weight (default ones), [n x 1]
            %   b          (returned) [intercept; slope]
            %   covB       (returned) [2 x 2] (X'WX)^-1 at the solution, NaN(2)
            %              if that is singular
            %   converged  (returned) 1x1 logical: the step fell below
            %              1e-10*(1+norm(b))
            %   ll         (returned) l*(b) at the solution
            arguments
                x (:,1) double
                y (:,1) double
                w (:,1) double = ones(size(x))
            end
            n = numel(x);
            X = [ones(n,1) x];
            y = min(max(y,0),1);
            w(~isfinite(w) | w < 0) = 0;

            % Start flat at the overall rate: the penalised surface is smooth
            % and single-peaked, so this converges in a handful of steps.
            ybar = sum(w.*y)/max(sum(w),eps);
            ybar = min(max(ybar,0.02),0.98);
            b  = [log(ybar/(1-ybar)); 0];
            ll = mabr.analysis.Threshold.firthPLL(x,y,w,b(1),b(2));
            converged = false;

            for it = 1:100
                eta = X*b;
                mu  = 1./(1+exp(-eta));
                W   = max(w.*mu.*(1-mu),1e-12);
                A   = X.'*(W.*X);
                if ~(rcond(A) > eps), break; end
                h     = W.*sum((X/A).*X,2);
                U     = X.'*(w.*(y-mu) + h.*(0.5-mu));
                delta = A\U;

                t = 1;
                bNew  = b + delta;
                llNew = mabr.analysis.Threshold.firthPLL(x,y,w,bNew(1),bNew(2));
                for s = 1:10
                    if isfinite(llNew) && llNew >= ll, break; end
                    t     = t/2;
                    bNew  = b + t*delta;
                    llNew = mabr.analysis.Threshold.firthPLL(x,y,w,bNew(1),bNew(2));
                end
                if ~(isfinite(llNew) && llNew >= ll)
                    % No step along this direction raises l*: b is as good as
                    % the iteration can make it.
                    converged = norm(t*delta) < 1e-10*(1+norm(b));
                    break
                end
                moved = norm(bNew-b);
                b  = bNew;
                ll = llNew;
                if moved < 1e-10*(1+norm(b)), converged = true; break; end
            end

            eta = X*b;
            mu  = 1./(1+exp(-eta));
            W   = max(w.*mu.*(1-mu),1e-12);
            A   = X.'*(W.*X);
            if rcond(A) > eps
                covB = inv(A);
            else
                covB = nan(2);
            end
        end

        function [ci,open] = firthProfileCI(x,y,w,crit,alpha)
            % Profile penalised-likelihood interval for a Firth threshold.
            %
            % The threshold theta = (logit(crit) - b0)/b1 is made a parameter
            % of its own (b0 = logit(crit) - b1*theta) and l* is maximised over
            % the slope b1 in [1e-6, 50/step] at each of 201 theta values
            % spanning [min(x) - 2*step, max(x) + 2*step]. The interval is
            % every theta whose deviance 2*(l*max - l*(theta)) is within the
            % chi-square(1) cut q = zquantile(1-alpha/2)^2 (3.8415 at alpha
            % 0.05). Unlike the Monte Carlo interval of the unpenalised fit it
            % does not assume the threshold is normally distributed -- which it
            % is not, when nine yes/no verdicts are all that pin it down.
            %
            % An end that reaches the edge of the theta grid is reported as
            % NaN with open = true: the data cannot say where that end is,
            % only that it is at least two steps outside the levels tested.
            %
            % The slope is maximised by a vectorised search (all 201 theta at
            % once: a 48-point grid on log b1, then golden section between the
            % grid points either side of the best) rather than 201 separate
            % FMINBND calls; the bounds, scale and tolerance are the same.
            %
            %   x      predictor (level), [n x 1]
            %   y      response in [0 1], [n x 1]
            %   w      case weight (default ones), [n x 1]
            %   crit   criterion probability (default 0.5)
            %   alpha  two-sided level (default 0.05); the [0 1] fit() accepts:
            %          0 keeps every theta (both ends open), 1 only the maximum
            %   ci     (returned) [lower upper], NaN where unavailable or open
            %   open   (returned) [lower upper] logical
            arguments
                x (:,1) double
                y (:,1) double
                w (:,1) double = ones(size(x))
                crit (1,1) double {mustBeInRange(crit,0,1)} = 0.5
                alpha (1,1) double {mustBeInRange(alpha,0,1)} = 0.05
            end
            ci = [NaN NaN];
            open = [false false];
            good = isfinite(x) & isfinite(y) & isfinite(w);
            x = x(good); y = min(max(y(good),0),1); w = w(good);
            if numel(x) < 2, return; end

            ux = unique(x);
            if numel(ux) > 1, step = median(diff(ux)); else, step = 1; end
            [~,~,~,llHat] = mabr.analysis.Threshold.logisticFirth(x,y,w);

            pc    = min(max(crit,eps),1-eps);
            lc    = log(pc/(1-pc));
            theta = linspace(min(x)-2*step, max(x)+2*step, 201).';
            prof  = mabr.analysis.Threshold.firthProfile(x,y,w,lc,theta,step);

            % The profile maximum IS l*max; taking the larger of the two only
            % guards against the slope search beating the fit by a rounding
            % error and producing a negative deviance.
            llMax = max([llHat; prof]);
            q     = mabr.analysis.Stats.zquantile(1-alpha/2)^2;
            keep  = 2*(llMax - prof) <= q;
            if ~any(keep), return; end

            i0 = find(keep,1,'first');
            i1 = find(keep,1,'last');
            ci = [theta(i0) theta(i1)];
            if i0 == 1,             ci(1) = NaN; open(1) = true; end
            if i1 == numel(theta),  ci(2) = NaN; open(2) = true; end
        end

        % =================================================================
        %  ABRpresto-like fit of a split-half correlation series
        % =================================================================
        function out = prestoFit(x,y,crit,opts)
            % Threshold of a correlation-vs-level series, after ABRpresto.
            %
            % Implemented from the description in Shaheen et al. 2025 (Hear
            % Res 462:109258), not from the reference code (whose licence is
            % academic-only). y is a per-level statistic that grows from ~0 to
            % ~1 with the response -- the mean split-half correlation -- and
            % the threshold is where it crosses crit (0.30 in the paper).
            %
            % Two curves are fitted by weighted least squares, weights
            % 1./SD (SD = each level's spread of the resampled r, so that a
            % level whose correlation is unstable counts for less):
            %
            %   sigmoid    y = A./(1+exp(-k(x-x0))) + B, A in [0.1 1],
            %              B in [-0.5 0.8], x0 within a step of the levels,
            %              k >= 0 (bounded through logistic/exp transforms
            %              for FMINSEARCH);
            %   power law  y = a*x'.^p + c, x' = x - min(x) + 1, p > 0, the
            %              threshold mapped back by + min(x) - 1. (The reference
            %              code reported this one in x' units, 1 dB too high
            %              whenever the lowest level was 0 dB.)
            %
            % The sigmoid is used when it crosses crit inside the levels AND
            % fits better; otherwise the power law, when IT crosses. When
            % neither does: at most two levels above crit is "no-response",
            % at most two below is "all-respond", anything else "failed"
            % (Threshold NaN). Before fitting, every level above 1.1*crit is
            % "all-respond" and none reaching crit is "no-response".
            %
            %   x          levels, [n x 1]
            %   y          statistic per level (e.g. mean split-half r), [n x 1]
            %   crit       criterion (default 0.30)
            %   opts.SD    per-level SD of the resampled statistic (default
            %              ones; a non-finite or non-positive SD takes the
            %              median of the others)
            %   opts.Step  level spacing (default: median spacing of x)
            %   out        (returned) fit-shaped struct (Threshold, CI,
            %              CIMethod, CIOpen, Type "presto-sigmoid" |
            %              "presto-power" | "presto", Criterion, Predict, Model,
            %              X, Y, Scale, Converged, Message, Status, Flags)
            arguments
                x (:,1) double
                y (:,1) double
                crit (1,1) double {mustBeFinite} = 0.30
                opts.SD (:,1) double = []
                opts.Step (1,1) double = NaN
            end
            sd = opts.SD;
            if isempty(sd), sd = ones(size(x)); end
            if numel(sd) ~= numel(x)
                error('mabr:analysis:Threshold:badSD', ...
                    'SD has %d values for %d levels.',numel(sd),numel(x));
            end

            out = struct('Threshold',NaN,'CI',[NaN NaN],'Type',"presto", ...
                'Criterion',crit,'Predict',@(xx) nan(numel(xx),1),'Model',struct(), ...
                'X',x,'Y',y,'Scale',[0 1],'Converged',false,'Message',"", ...
                'CIMethod',"none",'CIOpen',[false false],'Status',"ok", ...
                'Flags',strings(1,0));

            good = isfinite(x) & isfinite(y);
            x = x(good); y = y(good); sd = sd(good);
            [x,o] = sort(x); y = y(o); sd = sd(o);
            out.X = x; out.Y = y;
            if numel(x) < 2
                out.Status  = "insufficient";
                out.Message = "Fewer than two usable levels.";
                return
            end

            step = opts.Step;
            if ~(isfinite(step) && step > 0)
                ux = unique(x);
                if numel(ux) > 1, step = median(diff(ux)); else, step = 1; end
            end
            okSD = isfinite(sd) & sd > 0;
            if any(okSD), fill = median(sd(okSD)); else, fill = 1; end
            sd(~okSD) = fill;
            w = 1./max(sd,1e-6);

            % Decided before fitting, as the paper does: every level clearly
            % above the criterion (the 1.1 allows a little extrapolation), or
            % none reaching it.
            if min(y) > 1.1*crit
                out.Status    = "all-respond";
                out.Threshold = x(1);
                out.Converged = true;
                out.Message   = sprintf("Every level is above %.2f (1.1 x the criterion).",1.1*crit);
                return
            end
            if max(y) < crit
                out.Status    = "no-response";
                out.Threshold = Inf;
                out.Converged = true;
                out.Message   = sprintf("No level reaches the criterion %.2f.",crit);
                return
            end

            sig = mabr.analysis.Threshold.prestoSigmoid(x,y,w,crit,step);
            pow = mabr.analysis.Threshold.prestoPower(x,y,w,crit);

            if sig.Spans && isfinite(sig.Threshold) && sig.SSE < pow.SSE
                use = sig;
                out.Threshold = sig.Threshold;
                if sig.AtBound, out.Flags(end+1) = "parameter at bound"; end
            elseif ~pow.Spans || ~isfinite(pow.Threshold)
                % Neither curve crosses the criterion inside the levels. Keep
                % the better of the two for drawing and decide by counting.
                if sig.SSE <= pow.SSE, use = sig; else, use = pow; end
                if sum(y > crit) <= 2
                    out.Status    = "no-response";
                    out.Threshold = Inf;
                    out.Message   = "Neither fit crossed the criterion; at most two levels above it.";
                elseif sum(y < crit) <= 2
                    out.Status    = "all-respond";
                    out.Threshold = x(1);
                    out.Message   = "Neither fit crossed the criterion; at most two levels below it.";
                else
                    out.Status    = "failed";
                    out.Threshold = NaN;
                    out.Message   = "Neither fit crossed the criterion.";
                    out.Flags(end+1) = "presto: no fit crossed the criterion";
                end
            else
                use = pow;
                out.Threshold = pow.Threshold;
                if ~(pow.AdjR2 > 0.7), out.Flags(end+1) = "power law (noisy)"; end
            end

            out.Type      = use.Type;
            out.Model     = use.Model;
            out.Predict   = use.Predict;
            out.Converged = use.Converged;
        end

        % =================================================================
        %  Saved fits
        % =================================================================
        function fit = predictor(fit)
            % Rebuild fit.Predict after loading: a saved fit carries no
            % function handle.
            %
            % A fit with CurveX/CurveY (the curve SeriesThreshold samples)
            % gets a piecewise-linear interpolant of that curve, extrapolated
            % and clamped to the curve's own range. Otherwise the curve is
            % rebuilt from Type and Model exactly as fit/prestoFit build it:
            % glm (b), sigmoid (A,B,c,d), isotonic (x,yhat), minimum (x,y),
            % presto-sigmoid (A,B,k,x0), presto-power (a,p,c,xmin). Anything
            % else -- or a Model missing a parameter -- predicts NaN.
            %
            %   fit  a fit-shaped struct (from fit, estimate, prestoFit or a
            %        SeriesThreshold Fit), with or without Predict
            %   fit  (returned) the same struct with Predict set
            arguments
                fit (1,1) struct
            end
            fit.Predict = @(xx) nan(numel(xx),1);

            if isfield(fit,'CurveX') && isfield(fit,'CurveY') && ...
                    numel(fit.CurveX) == numel(fit.CurveY) && ~isempty(fit.CurveX)
                cx = double(fit.CurveX(:));
                cy = double(fit.CurveY(:));
                g  = isfinite(cx) & isfinite(cy);
                [cx,iu] = unique(cx(g));
                cy = cy(g);
                cy = cy(iu);
                if numel(cx) >= 2
                    lo = min(cy); hi = max(cy);
                    fit.Predict = @(xx) min(max(interp1(cx,cy,double(xx(:)), ...
                        'linear','extrap'),lo),hi);
                    return
                elseif isscalar(cx)
                    c0 = cy;
                    fit.Predict = @(xx) repmat(c0,numel(xx),1);
                    return
                end
            end

            if ~isfield(fit,'Type') || ~isfield(fit,'Model') || ~isstruct(fit.Model)
                return
            end
            M = fit.Model;
            try
                switch string(fit.Type)
                    case "glm"
                        b = M.b;
                        fit.Predict = @(xx) 1./(1+exp(-(b(1)+b(2)*xx(:))));
                    case "sigmoid"
                        A = M.A; B = M.B; c = M.c; d = M.d;
                        fit.Predict = @(xx) A + (B-A)./(1+exp(-(xx(:)-c)./d));
                    case "isotonic"
                        fit.Predict = mabr.analysis.Threshold.stepPredict(M.x,M.yhat);
                    case "minimum"
                        fit.Predict = mabr.analysis.Threshold.stepPredict(M.x,M.y);
                    case "presto-sigmoid"
                        A = M.A; B = M.B; k = M.k; x0 = M.x0;
                        fit.Predict = @(xx) A./(1+exp(-k*(xx(:)-x0))) + B;
                    case "presto-power"
                        a = M.a; p = M.p; c = M.c; xmin = M.xmin;
                        fit.Predict = @(xx) a*max(xx(:)-xmin+1,0).^p + c;
                end
            catch
                % A Model missing a field: keep the NaN predictor rather than
                % fail a load over a curve that is only ever drawn.
                fit.Predict = @(xx) nan(numel(xx),1);
            end
        end
    end

    methods (Static, Access = private)
        function [par,dh,why] = boundedTFCE(Y,par,opts)
            % The TFCE parameters detect() runs with: par itself, unless the
            % largest |t| of the test would need more than MaxTFCESteps steps
            % of par.dh, when dh is raised to that |t| over MaxTFCESteps.
            %
            %   Y     [nSamples x nSweeps] the tested rows
            %   par   TFCE struct (E, H, dh)
            %   opts  detect()'s options (NumPermutations, Alpha, Seed)
            %   par   (returned) TFCE struct to use
            %   dh    (returned) its step
            %   why   (returned) "" or the flag a raised step carries
            why = "";
            dh  = 0.1;
            if isstruct(par) && isfield(par,'dh') && ~isempty(par.dh), dh = double(par.dh); end
            n = size(Y,2);
            if n < 2 || ~(dh > 0), return; end
            cap = mabr.analysis.Threshold.MaxTFCESteps;

            % First a bound no permutation can exceed, from the data alone:
            % a sign flip moves only the sum, and t grows with |sum|, which is
            % at most sum|x| -- t^2 <= (n-1) A^2/(n Q - A^2), A = sum|x|,
            % Q = sum x^2, and n Q - A^2 = n sum (|x| - mean|x|)^2. With noise
            % in the sweeps it is about 1.3 sqrt(n) (or the observed t, when
            % larger) -- under the cap below some 5000 sweeps, and then
            % nothing more is done; above, the t-max run below costs a
            % matrix product and finds the |t| the test really meets.
            a  = abs(Y);
            m  = mean(a,2);
            D  = n*sum((a - m).^2,2);
            tb = sqrt(n - 1)*n*m./sqrt(D);
            tb(m == 0) = 0;
            if ~(max(tb) > cap*dh), return; end

            % Then the |t| the test will meet: a t-max run on the same sign
            % flips. When they come from the global stream it is put back
            % on the way out, so the TFCE run draws the same ones again.
            if isempty(opts.Seed)
                s0 = rng;
                restore = onCleanup(@() rng(s0));
            end
            [~,r] = mabr.analysis.PermTest.run(Y,Method="tmax", ...
                NumPermutations=opts.NumPermutations,Alpha=opts.Alpha,Seed=opts.Seed);
            reach = max([abs(r.statistic); abs(r.null(:))]);
            if ~(reach > cap*dh), return; end
            dh = reach/cap;
            par.dh = dh;
            why = sprintf("TFCE step raised to %.3g (|t| reaches %.3g: near-noiseless sweeps)",dh,reach);
        end

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
                out.CIMethod = "montecarlo";
            end
        end

        function out = fitFirth(out,x,y,w,opts)
            % Firth GLM branch of fit(). Same in/out shape as fitLogistic: a
            % falling or flat fitted slope falls back to the isotonic fit as
            % the unpenalised branch does. No ridge, and the interval is the
            % profile likelihood rather than Monte Carlo draws, so no stream.
            [b,covB,conv] = mabr.analysis.Threshold.logisticFirth(x,y,w);
            slope = b(2);

            if ~isfinite(slope) || slope <= 0
                out = mabr.analysis.Threshold.fitIsotonic(out,x,y,w,opts);
                out.Type = "isotonic";
                out.Message = "GLM slope was not positive; used isotonic fit.";
                return
            end

            out.Type      = "glm";
            out.Converged = conv;
            out.Model     = struct('b',b,'cov',covB,'penalty',"firth");
            out.Predict   = @(xx) 1./(1+exp(-(b(1)+b(2)*xx(:))));
            out.Threshold = mabr.analysis.Threshold.logitInverse(b(1),b(2),opts.Criterion);
            [out.CI,out.CIOpen] = mabr.analysis.Threshold.firthProfileCI( ...
                x,y,w,opts.Criterion,opts.CIAlpha);
            out.CIMethod  = "profile";
        end

        function L = firthPLL(x,y,w,b0,b1)
            % Penalised log-likelihood l*(b0,b1) of logisticFirth, at every
            % element of b0/b1 (arrays of one size) at once. x,y,w: [n x 1].
            %
            % det(X'WX) is formed from sums over x CENTRED on its mean: the
            % determinant is unchanged by the shift (it is a unimodular change
            % of the columns of X), its cancellation error is not, and levels
            % of 80 dB square to numbers that swamp a near-zero information.
            xm  = mean(x);
            xc  = x - xm;
            b0c = b0 + b1*xm;                  % b0 + b1*x == b0c + b1*xc
            ll  = zeros(size(b0));
            S0  = ll; S1 = ll; S2 = ll;
            for k = 1:numel(x)
                eta = b0c + b1*xc(k);
                if y(k) > 0
                    ll = ll - w(k)*y(k)*mabr.analysis.Threshold.softplus(-eta);
                end
                if y(k) < 1
                    ll = ll - w(k)*(1-y(k))*mabr.analysis.Threshold.softplus(eta);
                end
                mu = 1./(1+exp(-eta));
                Wk = max(w(k)*mu.*(1-mu),1e-12);
                S0 = S0 + Wk;
                S1 = S1 + Wk*xc(k);
                S2 = S2 + Wk*xc(k)^2;
            end
            L = ll + 0.5*log(max(S0.*S2 - S1.^2,realmin));
        end

        function prof = firthProfile(x,y,w,lc,theta,step)
            % max over b1 in [1e-6, 50/step] of l*(lc - b1*theta, b1), for each
            % theta (column), searched on log(b1): a 48-point grid for all
            % theta at once, then a vectorised golden section between the
            % grid points either side of each theta's best. prof: (returned)
            % [numel(theta) x 1].
            lo = log(1e-6);
            hi = log(50/step);
            if ~(hi > lo), hi = lo + 1; end
            nT = numel(theta);
            G  = 48;
            u  = linspace(lo,hi,G);

            [U,T] = meshgrid(u,theta);
            B1 = exp(U);
            Lg = mabr.analysis.Threshold.firthPLL(x,y,w,lc - B1.*T,B1);
            [best,j] = max(Lg,[],2);

            f  = @(uu) mabr.analysis.Threshold.firthPLL(x,y,w,lc - exp(uu).*theta,exp(uu));
            gr = (sqrt(5)-1)/2;
            a  = u(max(j-1,1)).';
            c  = u(min(j+1,G)).';
            p1 = c - gr*(c-a);
            p2 = a + gr*(c-a);
            f1 = f(p1);
            f2 = f(p2);
            for it = 1:80
                left = f1 >= f2;                 % the maximum is in [a, p2]
                c(left)   = p2(left);
                a(~left)  = p1(~left);
                p2(left)  = p1(left);   f2(left)  = f1(left);
                p1(~left) = p2(~left);  f1(~left) = f2(~left);
                p1(left)  = c(left)  - gr*(c(left)  - a(left));
                p2(~left) = a(~left) + gr*(c(~left) - a(~left));
                pn = p2;
                pn(left) = p1(left);
                fn = f(pn);
                f1(left)  = fn(left);
                f2(~left) = fn(~left);
                if max(c-a) < 1e-10, break; end
            end
            prof = max([best f1 f2],[],2);
            prof = reshape(prof,nT,1);
        end

        function s = softplus(t)
            % log(1+exp(t)) without overflow. t: any array; s: same size.
            s = max(t,0) + log1p(exp(-abs(t)));
        end

        function s = prestoSigmoid(x,y,w,crit,step)
            % The bounded sigmoid of prestoFit, fitted by FMINSEARCH on
            % unconstrained transforms: A = 0.1 + 0.9*sg(a), B = -0.5 +
            % 1.3*sg(b), x0 = lo + (hi-lo)*sg(c), k = exp(d), sg the logistic.
            % Started from A,B clamped from max/min y, k0 = (8/A0)(A0-B0)/span
            % and the best of five x0 from min+span/8 to max-span/8. s:
            % (returned) struct Type, Threshold, Spans, SSE, AtBound, Model,
            % Predict, Converged.
            lo   = min(x) - step;
            hi   = max(x) + step;
            span = max(x) - min(x);
            if ~(span > 0), span = step; end
            sg     = @(t) 1./(1+exp(-t));
            lgt    = @(v) log(v./(1-v));
            inside = @(v) min(max(v,1e-6),1-1e-6);

            A0 = min(max(max(y),0.1),1);
            B0 = min(max(min(y),-0.5),0.8);
            k0 = (8/A0)*(A0-B0)/span;
            if ~(isfinite(k0) && k0 > 0), k0 = 8/span; end
            curve = @(A,B,k,x0,xx) A./(1+exp(-k*(xx-x0))) + B;
            cand  = linspace(min(x)+span/8, max(x)-span/8, 5);
            sse0  = arrayfun(@(c) sum(w.*(y - curve(A0,B0,k0,c,x)).^2), cand);
            [~,i] = min(sse0);

            par = @(q) [0.1+0.9*sg(q(1)); -0.5+1.3*sg(q(2)); lo+(hi-lo)*sg(q(3)); exp(q(4))];
            sse = @(q) mabr.analysis.Threshold.prestoSSE(par(q),x,y,w,curve);
            q0  = [lgt(inside((A0-0.1)/0.9)); lgt(inside((B0+0.5)/1.3)); ...
                   lgt(inside((cand(i)-lo)/(hi-lo))); log(k0)];
            o = optimset('Display','off','MaxFunEvals',8000,'MaxIter',8000, ...
                'TolX',1e-10,'TolFun',1e-12);
            [q,fv,flag] = fminsearch(sse,q0,o);
            % One restart from the answer: cheap, and the simplex of a first
            % run on a four-parameter surface stalls often enough to matter.
            [q2,fv2,flag2] = fminsearch(sse,q,o);
            if fv2 <= fv, q = q2; fv = fv2; flag = flag2; end

            P = par(q);
            A = P(1); B = P(2); x0 = P(3); k = P(4);
            yfit = curve(A,B,k,x0,x);
            r    = A/(crit-B);
            if crit > B && r > 1
                thr = x0 - log(r-1)/k;
            else
                thr = NaN;
            end
            % "Within 1% of a bound": of the parameter's range for A, B and
            % x0; for k, whose only bound is 0, a slope so shallow the curve
            % moves less than ~2% of A across the whole series.
            atB = abs(A-0.1) <= 0.009 || abs(A-1) <= 0.009 || ...
                  abs(B+0.5) <= 0.013 || abs(B-0.8) <= 0.013 || ...
                  abs(x0-lo) <= 0.01*(hi-lo) || abs(x0-hi) <= 0.01*(hi-lo) || ...
                  k*span < 0.08;

            s = struct('Type',"presto-sigmoid",'Threshold',thr, ...
                'Spans',yfit(1) < crit && crit < yfit(end),'SSE',fv,'AtBound',atB, ...
                'Model',struct('A',A,'B',B,'k',k,'x0',x0,'SSE',fv), ...
                'Predict',@(xx) A./(1+exp(-k*(xx(:)-x0))) + B, ...
                'Converged',flag == 1);
        end

        function s = prestoPower(x,y,w,crit)
            % The power law of prestoFit: y = a*x'.^p + c with x' = x - min(x)
            % + 1 >= 1 and p = exp(q) > 0, weighted least squares by
            % FMINSEARCH from several starts. The threshold is solved in x'
            % and mapped back by + min(x) - 1, so it is in the units of x
            % whatever the lowest level is. s: (returned) struct as
            % prestoSigmoid plus AdjR2.
            xmin = min(x);
            xp   = x - xmin + 1;
            f    = @(q,xx) q(1)*xx.^exp(q(3)) + q(2);
            sse  = @(q) sum(w.*(y - f(q,xp)).^2);
            o = optimset('Display','off','MaxFunEvals',6000,'MaxIter',6000, ...
                'TolX',1e-10,'TolFun',1e-12);
            best = []; bestV = Inf; bestFlag = 0;
            for p0 = [0.5 1 2 4]
                for c0 = unique([0 min(y)])
                    a0 = (max(y)-c0)/max(xp)^p0;
                    if ~(abs(a0) > 1e-9), a0 = 1e-3; end
                    try %#ok<TRYNC>
                        [q,v,flag] = fminsearch(sse,[a0; c0; log(p0)],o);
                        if v < bestV, best = q; bestV = v; bestFlag = flag; end
                    end
                end
            end
            if isempty(best)
                s = struct('Type',"presto-power",'Threshold',NaN,'Spans',false, ...
                    'SSE',Inf,'AtBound',false,'AdjR2',NaN, ...
                    'Model',struct('a',NaN,'p',NaN,'c',NaN,'xmin',xmin,'SSE',Inf,'R2',NaN,'AdjR2',NaN), ...
                    'Predict',@(xx) nan(numel(xx),1),'Converged',false);
                return
            end
            a = best(1); c = best(2); p = exp(best(3));
            yfit = f(best,xp);
            n    = numel(y);
            sst  = sum((y-mean(y)).^2);
            if sst > 0, R2 = 1 - sum((y-yfit).^2)/sst; else, R2 = NaN; end
            if n > 4, adj = 1 - (1-R2)*(n-1)/(n-4); else, adj = NaN; end
            t = (crit-c)/a;
            if a ~= 0 && t > 0
                thr = t^(1/p) + (xmin - 1);
            else
                thr = NaN;
            end
            s = struct('Type',"presto-power",'Threshold',thr, ...
                'Spans',yfit(1) < crit && crit < yfit(end),'SSE',bestV, ...
                'AtBound',false,'AdjR2',adj, ...
                'Model',struct('a',a,'p',p,'c',c,'xmin',xmin,'SSE',bestV,'R2',R2,'AdjR2',adj), ...
                'Predict',@(xx) a*max(xx(:)-xmin+1,0).^p + c, ...
                'Converged',bestFlag == 1);
        end

        function v = prestoSSE(P,x,y,w,curve)
            % Weighted SSE of the presto sigmoid at P = [A;B;x0;k]. v: scalar.
            v = sum(w.*(y - curve(P(1),P(2),P(4),P(3),x)).^2);
        end

        function fcn = stepPredict(x,y)
            % 'previous'-interpolating step curve through (x,y), as the
            % isotonic and minimum fits draw; a single point is a constant.
            x = x(:); y = y(:);
            if numel(x) >= 2
                fcn = @(xx) interp1(x,y,xx(:),'previous','extrap');
            elseif isscalar(x)
                c0 = y;
                fcn = @(xx) repmat(c0,numel(xx),1);
            else
                fcn = @(xx) nan(numel(xx),1);
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
                out.CIMethod = "montecarlo";
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
