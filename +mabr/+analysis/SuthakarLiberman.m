classdef SuthakarLiberman
% mabr.analysis.SuthakarLiberman  The threshold algorithm of Suthakar & Liberman 2019, as published.
%
%   Suthakar K, Liberman MC (2019) A simple algorithm for objective threshold
%   determination of auditory brainstem responses. Hear Res 381:107782.
%   doi:10.1016/j.heares.2019.107782
%
%   The paper correlates each level's average with the next-louder level's
%   (xcov 'coeff' at lag 0, the value belonging to the quieter level of the
%   pair), fits a sigmoid and a power law to r against level, and reads the
%   threshold off one of them where it reaches 0.35, by a decision tree (its
%   Fig. 4):
%
%     C1  the sigmoid's limits span the criterion (a < 0.35 < b) and its
%         slope is neither flat nor a step (0.005 < d < 0.999)
%     C2  the sigmoid's RMS error is below the power law's     -> A: sigmoid
%     C3  the power law's adjusted R^2 is over 0.7              -> B: power law
%     C4  r ever exceeds the criterion -> C: power law, flagged for visual
%         inspection; else D: no threshold (visual thresholding)
%
%   C1 failing goes straight to C3, as C2 failing does. This class is that
%   tree, to compare with what MABR's own "suthakar-liberman" method says
%   (mabr.analysis.SeriesThreshold): the same statistic and criterion, but
%   the descending rule instead of the fits, and the best lag up to MaxLag
%   instead of lag 0. It decides nothing in an analysis -- the analysis
%   app's Suthakar & Liberman window draws it beside the method's answer.
%
%       out = mabr.analysis.SuthakarLiberman.decide(levels,r);      % r at lag 0
%       out.Path, out.Threshold, out.Interval, out.Message
%       D   = mabr.analysis.SuthakarLiberman.fromSession(S,seriesKey);
%       out = mabr.analysis.SuthakarLiberman.decide(D.Levels,D.R0);
%
%   The fits, by least squares (unweighted, as the paper's tools fit):
%
%     sigmoid  y = a + (b-a)/(1 + 10^(d(c-x)))  -- the sigm_fit form: a and b
%              the lower and upper limits, c the midpoint, d the slope
%     power    y = a x^b + c  -- MATLAB's power2, on the levels themselves
%              (so only levels above 0: a level at or below 0 is left out of
%              this fit and counted in Excluded)
%
%   Their intervals are the ones the paper drew: the sigmoid's is nlpredci's
%   default, a 95% confidence band of the fitted curve; the power law's is
%   predint's default, a 95% prediction band for a new observation; the
%   threshold interval is where each band crosses the criterion (NaN on a
%   side where it does not -- the paper's "?"). "RMS error" is the residual
%   standard error sqrt(SSE/(n-p)) both tools report (fit's gof.rmse,
%   nlinfit's MSE), and the adjusted R^2 is fit's: 1 - (SSE/(n-p))/(SST/(n-1)).
%   No Statistics or Curve Fitting toolbox: fminsearch, a QR factorisation
%   for the covariance, and mabr.metrics.t_quantile.
%
%   See also mabr.analysis.SeriesThreshold, mabr.analysis.SingleTrial.xcorrUp,
%   mabr.ui.analysis.SuthakarLibermanWindow
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        Criterion  = 0.35            % r: the paper's criterion
        SlopeRange = [0.005 0.999]   % C1: the sigmoid's d, exclusive
        MinAdjR2   = 0.7             % C3: the power law's adjusted R^2
        Confidence = 0.95            % the bands' level
        Citation   = "Suthakar K, Liberman MC (2019). A simple algorithm for objective threshold determination of auditory brainstem responses. Hear Res 381:107782."
        DOI        = "10.1016/j.heares.2019.107782"
        Paths      = ["A","B","C","D","insufficient"]
    end

    methods (Static)
        % =================================================================
        %  The decision tree
        % =================================================================
        function out = decide(x,y,crit)
            % The paper's threshold of one level series.
            %
            %   x     levels, the quieter level of each correlated pair
            %   y     the correlation at each (lag 0 for the paper's)
            %   crit  criterion (default Criterion, 0.35)
            %   out   (returned) struct:
            %     Path       "A" | "B" | "C" | "D" | "insufficient"
            %     Fit        "sigmoid" | "power" | "" (the fit the threshold is from)
            %     Threshold  dB (NaN for D, or a chosen fit that never reaches crit)
            %     Interval   [lo hi], where the chosen fit's band crosses crit
            %     Noisy      true on path C (flagged for visual inspection)
            %     C1..C4     logical, NaN where the tree did not ask
            %     Sigmoid, Power   fitSigmoid / fitPower results
            %     X, Y, Criterion, Message (one sentence: the path and why)
            arguments
                x (:,1) double
                y (:,1) double
                crit (1,1) double = mabr.analysis.SuthakarLiberman.Criterion
            end
            if numel(x) ~= numel(y)
                error('mabr:analysis:SuthakarLiberman:size','%d levels and %d values.',numel(x),numel(y));
            end
            ok = isfinite(x) & isfinite(y);
            x = x(ok);  y = y(ok);
            [x,o] = sort(x);  y = y(o);
            SL = mabr.analysis.SuthakarLiberman;
            sig = SL.fitSigmoid(x,y,crit);
            pow = SL.fitPower(x,y,crit);
            out = struct('Path',"",'Fit',"",'Threshold',NaN,'Interval',[NaN NaN],'Noisy',false, ...
                'C1',NaN,'C2',NaN,'C3',NaN,'C4',NaN,'Sigmoid',sig,'Power',pow, ...
                'X',x,'Y',y,'Criterion',crit,'Message',"");
            if numel(x) < 4
                out.Path = "insufficient";
                out.Message = string(sprintf(['%d level pair(s) with a correlation: the power law needs 4 and ' ...
                    'the sigmoid 5, so the paper''s tree cannot run.'],numel(x)));
                return
            end

            % C1: the sigmoid spans the criterion, with a slope in range
            p = sig.Params;
            if sig.Ok
                spans = p(1) < crit && crit < p(2);
                slope = p(4) > SL.SlopeRange(1) && p(4) < SL.SlopeRange(2);
                out.C1 = spans && slope;
                if ~spans
                    why1 = sprintf('its limits [%.2f %.2f] do not span %.2f',p(1),p(2),crit);
                elseif ~slope
                    why1 = sprintf('its slope d = %.4g is outside %g–%g',p(4),SL.SlopeRange);
                else
                    why1 = sprintf('its limits [%.2f %.2f] span %.2f and its slope d = %.3g is in range', ...
                        p(1),p(2),crit,p(4));
                end
            else
                out.C1 = false;
                why1 = char(sig.Message);
            end

            if out.C1
                % C2: the better of the two fits
                out.C2 = ~pow.Ok || sig.RMSE < pow.RMSE;
                if out.C2
                    out.Path = "A";
                    out = SL.choose(out,sig,"sigmoid");
                    if pow.Ok
                        rms = sprintf(', and it fits better (RMS error %.3f against %.3f)',sig.RMSE,pow.RMSE);
                    else
                        rms = ' (the power law could not be fitted)';
                    end
                    out.Message = "Path A: the sigmoid passes C1 — " + why1 + rms + ...
                        SL.thresholdPhrase(out,crit) + ".";
                    return
                end
                head = sprintf('the sigmoid passes C1 but fits worse (RMS error %.3f against %.3f)', ...
                    sig.RMSE,pow.RMSE);
            else
                head = "the sigmoid fails C1 — " + why1;
            end

            % C3, C4: the power arm
            if ~pow.Ok
                out.Path = "D";
                out.Message = "Path D: " + head + ", and the power law could not be fitted (" + ...
                    pow.Message + "): no threshold — the paper leaves it to visual thresholding.";
                return
            end
            out.C3 = pow.AdjR2 > SL.MinAdjR2;
            if out.C3
                out.Path = "B";
                out = SL.choose(out,pow,"power");
                out.Message = "Path B: " + head + sprintf('; the power law fits with adjusted R² %.2f > %.1f', ...
                    pow.AdjR2,SL.MinAdjR2) + SL.thresholdPhrase(out,crit) + ".";
                return
            end
            out.C4 = max(y) > crit;
            if out.C4
                out.Path = "C";
                out.Noisy = true;
                out = SL.choose(out,pow,"power");
                out.Message = "Path C: " + head + sprintf(['; the power law fits poorly (adjusted R² %.2f ' ...
                    '≤ %.1f) but r exceeds %.2f (max %.2f)'],pow.AdjR2,SL.MinAdjR2,crit,max(y)) + ...
                    SL.thresholdPhrase(out,crit) + ", flagged for visual inspection.";
            else
                out.Path = "D";
                out.Message = "Path D: " + head + sprintf(['; the power law fits poorly (adjusted R² %.2f) ' ...
                    'and r never exceeds %.2f (max %.2f): no threshold — likely no response.'], ...
                    pow.AdjR2,crit,max(y));
            end
        end

        % =================================================================
        %  The two fits
        % =================================================================
        function f = fitSigmoid(x,y,crit)
            % The sigm_fit sigmoid y = a + (b-a)/(1+10^(d(c-x))), least squares.
            %
            %   x, y  levels and values (NaN pairs dropped)
            %   crit  criterion the threshold and its interval are read at
            %   f     (returned) struct Ok, Params [a b c d], N, SSE, RMSE,
            %         Threshold, Interval, Predict, Band (xx -> [lo hi]: the
            %         95% confidence band of the curve), Converged, Message
            arguments
                x (:,1) double
                y (:,1) double
                crit (1,1) double = mabr.analysis.SuthakarLiberman.Criterion
            end
            ok = isfinite(x) & isfinite(y);
            x = x(ok);  y = y(ok);
            n = numel(x);
            f = mabr.analysis.SuthakarLiberman.emptyFit("sigmoid",n,4);
            if n < 5
                f.Message = string(sprintf('the sigmoid needs at least 5 levels (%d)',n));
                return
            end
            if max(y) == min(y)
                f.Message = "every value is the same";
                return
            end
            model = @(q,xx) q(1) + (q(2)-q(1))./(1 + 10.^(q(4)*(q(3)-xx)));
            sse = @(q) sum((y - model(q,x)).^2);
            % starts: the observed range, the midpoint at five places across
            % the levels, four slopes; the best simplex, then one restart
            span = max(x) - min(x);
            mids = linspace(min(x) + span/8,max(x) - span/8,5);
            o = optimset('Display','off','MaxFunEvals',20000,'MaxIter',20000,'TolX',1e-10,'TolFun',1e-12);
            best = []; bv = Inf; flag = 0;
            for c0 = mids
                for d0 = [0.02 0.05 0.1 0.3]
                    [q,v,fl] = fminsearch(sse,[min(y); max(y); c0; d0],o);
                    if v < bv, best = q; bv = v; flag = fl; end
                end
            end
            [q,v,fl] = fminsearch(sse,best,o);
            if v <= bv, best = q; bv = v; flag = fl; end
            f.Ok = all(isfinite(best));
            if ~f.Ok
                f.Message = "the fit did not converge to finite values";
                return
            end
            f.Params = best(:).';
            f.SSE = bv;
            f.RMSE = sqrt(bv/(n - 4));
            f.Converged = flag == 1;
            f.Predict = @(xx) model(best,xx(:));
            J = mabr.analysis.SuthakarLiberman.sigmoidJacobian(best,x);
            jac = @(xx) mabr.analysis.SuthakarLiberman.sigmoidJacobian(best,xx(:));
            f.Band = mabr.analysis.SuthakarLiberman.bandFcn(f.Predict,J,jac,bv,n,4,false);
            a = best(1); b = best(2); c = best(3); d = best(4);
            r = (b - a)/(crit - a) - 1;
            if d ~= 0 && isfinite(r) && r > 0
                f.Threshold = c - log10(r)/d;
            end
            f.Interval = mabr.analysis.SuthakarLiberman.bandInterval(f,x,crit);
            f.Message = string(sprintf('a %.3f, b %.3f, c %.1f, d %.4g; RMS error %.3f',a,b,c,d,f.RMSE));
        end

        function f = fitPower(x,y,crit)
            % MATLAB's power2, y = a x^b + c, on the levels above 0, least squares.
            %
            %   x, y  levels and values (NaN pairs dropped; levels <= 0 are
            %         left out, as x^b needs x > 0, and counted in Excluded)
            %   crit  criterion the threshold and its interval are read at
            %   f     (returned) struct as fitSigmoid, Params [a b c], plus
            %         AdjR2 and Excluded; Band is the 95% prediction band
            arguments
                x (:,1) double
                y (:,1) double
                crit (1,1) double = mabr.analysis.SuthakarLiberman.Criterion
            end
            ok = isfinite(x) & isfinite(y);
            x = x(ok);  y = y(ok);
            pos = x > 0;
            nx = sum(~pos);
            x = x(pos);  y = y(pos);
            n = numel(x);
            f = mabr.analysis.SuthakarLiberman.emptyFit("power",n,3);
            f.Excluded = nx;
            if n < 4
                f.Message = string(sprintf('the power law needs at least 4 levels above 0 (%d)',n));
                return
            end
            sst = sum((y - mean(y)).^2);
            if sst == 0
                f.Message = "every value is the same";
                return
            end
            % for a given exponent the model is linear in a and c: profile
            % the exponent on a grid, then refine it (and a, c with it)
            prof = @(b) mabr.analysis.SuthakarLiberman.powerProfile(x,y,b);
            grid = -6:0.05:6;
            grid(abs(grid) < 1e-9) = [];
            v = arrayfun(prof,grid);
            [~,k] = min(v);
            o = optimset('Display','off','MaxFunEvals',4000,'MaxIter',4000,'TolX',1e-12,'TolFun',1e-14);
            [b,~,flag] = fminsearch(prof,grid(k),o);
            [bv,ac] = prof(b);
            if ~(isfinite(bv) && all(isfinite(ac)))
                f.Message = "the fit did not converge to finite values";
                return
            end
            q = [ac(1); b; ac(2)];
            f.Ok = true;
            f.Params = q(:).';
            f.SSE = bv;
            f.RMSE = sqrt(bv/(n - 3));
            f.AdjR2 = 1 - (bv/(n - 3))/(sst/(n - 1));
            f.Converged = flag == 1;
            f.Predict = @(xx) mabr.analysis.SuthakarLiberman.powerAt(q,xx(:));
            J = mabr.analysis.SuthakarLiberman.powerJacobian(q,x);
            jac = @(xx) mabr.analysis.SuthakarLiberman.powerJacobian(q,max(xx(:),realmin));
            f.Band = mabr.analysis.SuthakarLiberman.bandFcn(f.Predict,J,jac,bv,n,3,true);
            t0 = (crit - q(3))/q(1);
            if q(1) ~= 0 && t0 > 0
                f.Threshold = t0^(1/q(2));
            end
            f.Interval = mabr.analysis.SuthakarLiberman.bandInterval(f,x,crit);
            f.Message = string(sprintf('a %.4g, b %.3f, c %.3f; RMS error %.3f, adjusted R² %.2f',q,f.RMSE,f.AdjR2));
            if nx > 0
                f.Message = f.Message + sprintf(' (%d level(s) at or below 0 left out)',nx);
            end
        end

        % =================================================================
        %  The correlation, as the paper computed it
        % =================================================================
        function [lagMs,r] = correlogram(mLow,mHigh,rows,dtMs)
            % xcov(quieter, louder, 'coeff') over the windowed samples.
            %
            % Each mean has its own mean over the window removed and the
            % product is scaled by both norms, so r at lag 0 is the Pearson
            % correlation (SingleTrial.xcorrUp's r0). A positive lag pairs
            % a quieter sample with an EARLIER louder one: the quieter
            % response is later, as SingleTrial.xcorrUp's lags read.
            %
            %   mLow, mHigh  [nT x 1] means of the quieter and louder level
            %   rows         [nT x 1] logical: the window (one run of rows)
            %   dtMs         sample interval, ms
            %   lagMs, r     (returned) [2m-1 x 1], m = the window's samples
            %                with both means finite; empty with fewer than 3
            arguments
                mLow (:,1) double
                mHigh (:,1) double
                rows (:,1) logical
                dtMs (1,1) double {mustBePositive}
            end
            lagMs = zeros(0,1);  r = zeros(0,1);
            idx = find(rows & isfinite(mLow) & isfinite(mHigh));
            if numel(idx) < 3, return; end
            a = mLow(idx) - mean(mLow(idx));
            b = mHigh(idx) - mean(mHigh(idx));
            den = sqrt(sum(a.^2)*sum(b.^2));
            if ~(den > 0), return; end
            m = numel(idx);
            r = conv(a,flipud(b))/den;
            lagMs = (-(m-1):(m-1)).'*dtMs;
        end

        function D = fromSession(S,seriesKey)
            % One series of a session, as the paper's algorithm reads it.
            %
            %   S          mabr.analysis.Session (sweeps or results only)
            %   seriesKey  a series key (Session.seriesKeys)
            %   D          (returned) struct:
            %     Keys, Levels     the series' conditions, level ascending
            %     R0               r with the next-louder level at lag 0
            %                      (XCorrUp0: the paper's), NaN at the loudest
            %     R, LagMs         this method's r, the best lag <= MaxLag
            %                      (XCorrUp, XCorrLag)
            %     Pairs            struct array, one per adjacent pair: Level,
            %                      Louder (levels), LagMs, R (the correlogram)
            %     Window           [t0 t1] ms the correlation is computed over
            %     MaxLag           ms, the method's lag allowance
            %     LevelLabel, SeriesLabel, Direction (+1, or -1 on an
            %     attenuation axis)
            %     Problem          "" or why the paper's tree cannot be run
            arguments
                S (1,1) mabr.analysis.Session
                seriesKey (1,1) string
            end
            D = struct('Keys',strings(0,1),'Levels',zeros(0,1),'R0',zeros(0,1),'R',zeros(0,1), ...
                'LagMs',zeros(0,1),'Pairs',struct('Level',{},'Louder',{},'LagMs',{},'R',{}), ...
                'Window',[NaN NaN],'MaxLag',NaN,'LevelLabel',"Level",'SeriesLabel',"", ...
                'Direction',1,'Problem',"");
            C = S.Conditions;
            if ~istable(C) || height(C) == 0
                D.Problem = "The session has no conditions yet.";
                return
            end
            try
                D.SeriesLabel = S.seriesLabel(seriesKey);
            catch
                D.SeriesLabel = seriesKey;
            end
            keys = S.seriesConditions(seriesKey);
            lp = S.levelParamOrEmpty();
            if isempty(keys) || lp == "" || ~ismember(lp,string(C.Properties.VariableNames))
                D.Problem = "The series has no level parameter to correlate along.";
                return
            end
            D.LevelLabel = lp;
            r = S.rowOf(keys);
            lv = double(C.(lp)(r));
            [lv,o] = sort(lv);
            r = r(o);  keys = keys(o);
            D.Keys = keys;  D.Levels = lv;
            col = @(nm) mabr.analysis.SuthakarLiberman.column(C,nm,r);
            D.R0 = col('XCorrUp0');  D.R = col('XCorrUp');  D.LagMs = col('XCorrLag');
            % the options the measures were made with
            mo = struct();
            if isfield(S.StepOptions,'measure') && isstruct(S.StepOptions.measure), mo = S.StepOptions.measure; end
            D.Window = S.ResponseWindow;
            if isfield(mo,'ResponseWindow') && numel(mo.ResponseWindow) == 2, D.Window = double(mo.ResponseWindow); end
            if isfield(mo,'MaxLag'), D.MaxLag = double(mo.MaxLag); end
            % louder is higher, on an attenuation axis lower (the rule
            % Session.loudnessSign applies to XCorrUp's next-louder level)
            dirn = "auto";
            if isfield(S.StepOptions,'thresholds') && isfield(S.StepOptions.thresholds,'LevelDirection')
                dirn = string(S.StepOptions.thresholds.LevelDirection);
            end
            if dirn == "descending" || (dirn == "auto" && contains(lower(lp),"attenuation"))
                D.Direction = -1;
            end
            if ~ismember('XCorrUp0',string(C.Properties.VariableNames))
                D.Problem = "The session's measures have not been run (no next-louder correlation).";
                return
            end
            if D.Direction < 0
                D.Problem = ['The level axis is an attenuation: the paper''s power law is fitted ' ...
                    'to sound levels above 0 and has no reading on it.'];
            end
            % the correlograms: each condition against the next louder one,
            % over the window and both conditions' extents (XCorrUp's rows)
            t = S.Time;
            if numel(t) < 2, return; end
            dt = median(diff(t));
            rw = mabr.analysis.Artifacts.windowMask(t,D.Window);
            loud = D.Direction*lv;
            for i = 1:numel(r)
                if ~isfinite(loud(i)), continue; end
                j = find(isfinite(loud) & loud > loud(i));
                if isempty(j), continue; end
                [~,k] = min(loud(j));
                j = j(k);
                rows = rw & mabr.analysis.SuthakarLiberman.extentMask(t,C.Extent(r(i),:)) ...
                    & mabr.analysis.SuthakarLiberman.extentMask(t,C.Extent(r(j),:));
                try
                    mLow = S.conditionMean(keys(i));
                    mHigh = S.conditionMean(keys(j));
                catch
                    continue
                end
                [lagMs,rr] = mabr.analysis.SuthakarLiberman.correlogram(mLow,mHigh,rows,dt);
                if isempty(rr), continue; end
                D.Pairs(end+1) = struct('Level',lv(i),'Louder',lv(j),'LagMs',lagMs,'R',rr);
            end
        end

        function s = valueText(thr,iv)
            % "38.0 (36.2–40.7)", "35.1 (?–48.0)", "n/a".
            if ~isfinite(thr), s = "n/a"; return; end
            s = sprintf('%.1f',thr);
            if any(isfinite(iv))
                side = @(v) string(ifelse(isfinite(v),sprintf('%.1f',v),'?'));
                s = s + " (" + side(iv(1)) + "–" + side(iv(2)) + ")";
            end
            s = string(s);
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function f = emptyFit(kind,n,p)
            f = struct('Kind',kind,'Ok',false,'Params',NaN(1,p),'N',n,'SSE',NaN,'RMSE',NaN, ...
                'AdjR2',NaN,'Excluded',0,'Threshold',NaN,'Interval',[NaN NaN], ...
                'Predict',@(xx) nan(numel(xx),1),'Band',@(xx) nan(numel(xx),2), ...
                'Converged',false,'Message',"");
        end

        function s = thresholdPhrase(out,crit)
            % ": threshold 38.0 (36.2–40.7)", or why the chosen fit gives none.
            if isfinite(out.Threshold)
                s = ": threshold " + mabr.analysis.SuthakarLiberman.valueText(out.Threshold,out.Interval);
            else
                s = string(sprintf(': but that fit never reaches %.2f at a level above 0, so it gives no threshold',crit));
            end
        end

        function out = choose(out,f,kind)
            out.Fit = kind;
            out.Threshold = f.Threshold;
            out.Interval = f.Interval;
        end

        function J = sigmoidJacobian(q,x)
            % d/d[a b c d] of a + (b-a)/(1+10^(d(c-x))), overflow-safe.
            s = 1./(1 + 10.^(q(4)*(q(3) - x)));
            w = s.*(1 - s)*log(10)*(q(2) - q(1));
            J = [1 - s, s, -w*q(4), -w.*(q(3) - x)];
        end

        function [v,ac] = powerProfile(x,y,b)
            % SSE of a x^b + c with a, c solved for this b.
            % The x^b column is scaled to a largest value of 1 before it is
            % factorised (unscaled, a large exponent makes it ~1e200 against
            % the column of ones), and an exponent near 0 -- x^b a second
            % constant column -- is judged on the factorisation rather than
            % left to warn. Exponents past +-20 are no fit: on levels in dB
            % they are steps, which is what the sigmoid is for.
            ac = [NaN; NaN];  v = Inf;
            if ~(abs(b) <= 20), return; end
            xb = x.^b;
            sc = max(abs(xb));
            if ~(isfinite(sc) && sc > 0), return; end
            X = [xb/sc, ones(size(x))];
            [Q,R] = qr(X,0);
            if ~(abs(R(2,2)) > 1e-10*abs(R(1,1))), return; end
            ac = R\(Q.'*y);
            v = sum((y - X*ac).^2);
            ac(1) = ac(1)/sc;
        end

        function y = powerAt(q,x)
            y = NaN(size(x));
            p = x > 0;
            y(p) = q(1)*x(p).^q(2) + q(3);
        end

        function J = powerJacobian(q,x)
            xb = x.^q(2);
            J = [xb, q(1)*xb.*log(x), ones(size(x))];
        end

        function band = bandFcn(predict,J,jac,sse,n,p,observation)
            % xx -> [lo hi]: the fitted curve's confidence band (nlpredci's
            % default), or with OBSERVATION a new value's prediction band
            % (predint's default); non-simultaneous, Confidence level.
            band = @(xx) nan(numel(xx),2);
            if n <= p, return; end
            [~,R] = qr(J,0);
            if size(R,1) < p || rank(R) < p, return; end
            Ri = R\eye(p);
            mse = sse/(n - p);
            tq = mabr.metrics.t_quantile(0.5 + mabr.analysis.SuthakarLiberman.Confidence/2,n - p);
            band = @(xx) mabr.analysis.SuthakarLiberman.bandAt(predict,jac,Ri,mse,tq,observation,xx);
        end

        function B = bandAt(predict,jac,Ri,mse,tq,observation,xx)
            xx = xx(:);
            yh = predict(xx);
            v = mse*sum((jac(xx)*Ri).^2,2);
            if observation, v = v + mse; end
            h = tq*sqrt(v);
            B = [yh - h, yh + h];
        end

        function iv = bandInterval(f,x,crit)
            % Where each edge of the band crosses crit, nearest the threshold.
            iv = [NaN NaN];
            if ~isfinite(f.Threshold), return; end
            span = max(x) - min(x);
            if ~(span > 0), span = 10; end
            xx = linspace(min(x) - span,max(x) + span,4001).';
            if f.Kind == "power", xx = xx(xx > 0); end
            if numel(xx) < 2, return; end
            B = f.Band(xx);
            cr = NaN(1,2);
            for e = 1:2
                g = B(:,e) - crit;
                k = find(isfinite(g(1:end-1)) & isfinite(g(2:end)) & sign(g(1:end-1)) ~= sign(g(2:end)));
                if isempty(k), continue; end
                xc = xx(k) - g(k).*(xx(k+1) - xx(k))./(g(k+1) - g(k));
                [~,i] = min(abs(xc - f.Threshold));
                cr(e) = xc(i);
            end
            if all(isfinite(cr))
                iv = sort(cr);
            elseif isfinite(cr(1)) || isfinite(cr(2))
                % one edge only: which side of the threshold it is on
                c = cr(isfinite(cr));
                if c <= f.Threshold, iv = [c NaN]; else, iv = [NaN c]; end
            end
        end

        function m = extentMask(t,extent)
            % Rows of t inside a condition's Extent ([NaN NaN] = none): the
            % rule of Session.extentMask (private there), so the rows here
            % are the rows XCorrUp was computed over.
            if any(isnan(extent))
                m = false(size(t));
            else
                m = t >= extent(1) & t <= extent(2);
            end
        end

        function v = column(C,nm,r)
            if ismember(nm,string(C.Properties.VariableNames))
                v = double(C.(nm)(r));
                v = v(:);
            else
                v = NaN(numel(r),1);
            end
        end
    end
end

function v = ifelse(c,a,b)
if c, v = a; else, v = b; end
end
