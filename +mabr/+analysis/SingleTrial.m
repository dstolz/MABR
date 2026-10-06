classdef SingleTrial
% mabr.analysis.SingleTrial  Statistics of one condition's single sweeps.
%
%   Everything here answers a question about ONE condition -- one
%   [nSamples x nSweeps] matrix of sweeps -- and nothing loops over
%   conditions, series or sessions (mabr.analysis.Session.measure does that).
%   Every function is pure: it reads its arguments, draws only from the
%   RandStream it is handed, and writes nothing.
%
%       [m,sem,info] = mabr.analysis.SingleTrial.balancedMean(X,pol,strata)
%       S = mabr.analysis.SingleTrial.summary(X,tMs,pol,strata, ...
%               Rows=tMs >= 0.5 & tMs <= 8, Stream=RandStream('threefry','Seed',1));
%
%   Common inputs:
%     X       [nT x N] sweeps, one per column, volts. Rows outside a
%             condition's extent may be NaN; callers pass rows inside it.
%     pol     1 x N stimulus polarity, +1/-1 (0 is read as +1, as
%             mabr.analysis.AbrFile reads it)
%     strata  1 x N positive integers, the file each sweep came from ([] =
%             one file). The GROUPS of every pooled statistic here are
%             file x polarity.
%     rows    nT x 1 logical (or indices): the samples a statistic is taken
%             over. Rows holding any NaN are dropped from it.
%     stream  a RandStream. Never the global stream: a statistic recomputed
%             for a subset of conditions must come out bit-identical.
%
%   POLARITY IS NOT NOISE. With alternating polarity the cochlear microphonic
%   (CM) and any stimulus artifact follow the stimulus sign, and the CM of a
%   1-2 kHz tone lies inside the 300-3000 Hz band. Pooling both polarities as
%   one population therefore counts the CM as noise (overestimating it at
%   exactly the loud low-frequency conditions) and lets it leak into a mean
%   whenever rejections unbalance the classes. So, everywhere here:
%     - the mean is polarity-BALANCED, m = (m+ + m-)/2;
%     - the variance is pooled WITHIN file x polarity groups, s^2 =
%       sum_g sum_k (x_k - m_g)^2 / (N - G), and sem^2 = s^2 (1/n+ + 1/n-)/4
%       (s^2/N for one-polarity data, which is flagged "polarity-locked
%       components not cancelled");
%     - every random sign vector (the +/- reference, the power test's null)
%       is balanced WITHIN each group, and is applied to the group's
%       residuals x_k - m_g, so the CM and the response cancel out of it
%       exactly whatever the group sizes.
%
%   THE ONE STATISTIC. The response power of the balanced mean over the
%   response window, P_m = mean_t (m_t - mean m)^2, against the residual
%   noise RN^2 = mean_t sem^2(t), gives F = P_m/RN^2 (fsp's statistic but
%   for the window mean's share of the noise, which fsp also takes out),
%   SNR = 10 log10 F (whose null is about 0 dB, not -Inf, because P_m still
%   holds the residual noise) and, for random equal halves averaged by the
%   mean, a partition-averaged split-half correlation r = (F-1)/(F+1). A
%   criterion on any one of them is a criterion on all three -- r 0.30 is
%   F 1.86 is SNR 2.7 dB -- which is why the methods built on them decide
%   by a p-value (powerTest, fsp) rather than by a fixed number. The
%   split-half's own percentiles describe PARTITION variability of one
%   dataset; they are not a confidence interval and are never called one.
%
%     balancedMean   polarity-balanced mean, SEM and the pooled variance
%     plusMinus      Schimmel's +/- reference with polarity-balanced signs
%     powerTest      sign-flip permutation p for F
%     fsp            Fsp with an estimated numerator df (Satterthwaite, with
%                    Srivastava's bias-corrected trace)
%     splitHalf      ABRpresto-like resampled split-half correlation
%     convergence    RN, F, SNR against the number of sweeps
%     features       per-sweep RMS, peak-to-peak, template amplitude ...
%     blocks         consecutive polarity-balanced sub-averages
%     bootstrapBand  pointwise bootstrap band of the balanced mean
%     xcorrUp        correlation with the next-louder level's mean
%     dtwUp          the same after dynamic time warping, the lag changing
%                    smoothly along the response (Signal Processing's dtw)
%     zeroVariance   whether the sweeps hold any noise at all
%     summary        all of the above that one condition needs, at once
%
%   NO NOISE, NO STATISTIC. Every statistic here is a signal measured
%   against the sweeps' own noise. A condition whose sweeps do not vary
%   within their file x polarity groups -- an all-zero (dead) channel, a
%   digital loop-back, synthetic data written without noise -- has none, so
%   summary leaves F, SNR, the power test, Fsp and the split-half r NaN and
%   flags it (FlagZeroVariance) rather than dividing by zero: RN is 0, which
%   is true, and a ratio over it is not a measurement.
%
%   Requires no Statistics toolbox: percentiles and F tails come from
%   mabr.analysis.Stats.
%
%   Schimmel H (1967) Science 157:92-94. Elberling C, Don M (1984) Scand
%   Audiol 13:187-197. Srivastava MS (2005) J Japan Statist Soc 35:251-272.
%   Shaheen LA et al. (2025) Hear Res 462:109258 (ABRpresto).
%
%   See also mabr.analysis.Stats, mabr.analysis.Peaks, mabr.analysis.Session

    properties (Constant)
        % Sign-flip permutations generated per batch: big enough that the
        % null is a handful of matrix products, small enough that the sign
        % matrix of a 1000-sweep condition stays a few MB.
        BlockSize = 512

        % Fewest distinct balanced sign patterns powerTest gives a p-value
        % for (see powerTest). About 14 sweeps of alternating polarity.
        MinSignPatterns = 1000

        % The flag a one-polarity condition carries.
        FlagUnbalanced = "polarity-locked components not cancelled"

        % The flag a condition without noise carries (see zeroVariance).
        FlagZeroVariance = "zero variance: the clean sweeps do not vary (a dead channel, or noiseless data)"

        % Residual noise, relative to the RMS of the sweeps themselves, at or
        % under which a condition counts as having none (zeroVariance). Real
        % electrodes put it at 1e-2 or more -- amplifier noise alone is a
        % thousandth of an ABR -- so this only ever catches what is not a
        % recording: an all-zero channel, a digital loop-back, synthetic data
        % written without noise (where the previous presentation's tail
        % leaves it near 1e-9).
        ZeroVarianceTol = 1e-6

        % Standard errors above zero the sweeps' mean projection on their
        % leave-one-out average must stand for TemplateAmp to be defined
        % (features): below it there is no response to scale by.
        TemplateMinT = 3

        % Span, ms, of the moving mean dtwUp smooths the warp's lag with. A
        % latency shift changes slowly along a response (wave I's per dB is
        % half wave V's, 3.4 ms later), noise changes every few samples, and
        % a lag free to change at every sample lines noise up: on pairs of
        % independent noise means (default band and window, 0.3 ms
        % allowance) the unsmoothed warp gave a median r of 0.60, against
        % 0.14 for xcorrUp. Over 2 ms the median is 0.14 again, while a
        % noiseless synthetic series whose waves shift by 0.15-0.30 ms per
        % 10 dB still comes to r 0.995 (xcorrUp: 0.90). 1 ms let noise
        % back in (median 0.28); 3 ms gave some of the alignment up (0.987).
        DTWLagSmoothMs = 2
    end

    methods (Static)
        % =================================================================
        %  The mean
        % =================================================================
        function [m,sem,info] = balancedMean(X,pol,strata)
            % Polarity-balanced mean and its SEM, columns over every row of X.
            %
            %   X       [nT x N] sweeps
            %   pol     1 x N +1/-1
            %   strata  1 x N file index ([] = one file)
            %   m       (returned) nT x 1 balanced mean
            %   sem     (returned) nT x 1 standard error of m
            %   info    (returned) struct N, NPos, NNeg, G, S2 (nT x 1 pooled
            %           within-group variance), Balanced
            %
            % One implementation, mabr.analysis.Stats.balancedMean, shared with
            % mabr.analysis.Session, so a mean drawn and a mean measured
            % cannot differ.
            arguments
                X double
                pol double = []
                strata double = []
            end
            [m,sem,info] = mabr.analysis.Stats.balancedMean(X,pol,strata);
        end

        % =================================================================
        %  The +/- reference
        % =================================================================
        function q = plusMinus(X,pol,strata,stream)
            % Schimmel +/- reference: an estimate of the noise left in the mean.
            %
            % Within each file x polarity group, half the sweeps get +1 and
            % half -1 (an odd group's remaining sweep a random sign), in a
            % random order; q = (q+ + q-)/2 with q_c = (1/n_c) sum s_k r_k over
            % the class, r_k = x_k - m_g the sweep's residual from its group
            % mean (an odd group's scaled by n/sqrt(n^2-1), the variance its
            % unpaired sign takes away). E[q^2] = sem^2 of the balanced mean,
            % for every group of two or more sweeps.
            %
            % Signs that simply followed presentation order would coincide
            % with stimulus polarity, and q would then hold the CM instead of
            % noise. Balancing them within the group cancels the CM; taking
            % them over residuals cancels it (and the response) exactly even
            % when a group is odd.
            %
            %   X       [nT x N] sweeps
            %   pol     1 x N +1/-1
            %   strata  1 x N file index ([] = one file)
            %   stream  RandStream ([] = threefry seeded 1)
            %   q       (returned) nT x 1 +/- reference (NaN where X is)
            arguments
                X double
                pol double
                strata double = []
                stream = []
            end
            [nT,N] = size(X);
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,N);
            stream = mabr.analysis.SingleTrial.streamOrDefault(stream);
            q = nan(nT,1);
            if N < 2, return; end
            G = mabr.analysis.SingleTrial.groupInfo(pol,strata);
            R = mabr.analysis.SingleTrial.residuals(X,G);
            s = mabr.analysis.SingleTrial.balancedSigns(G,1,stream);
            q = R*(s.*G.w.*G.oddScale);
        end

        % =================================================================
        %  Detection by response power
        % =================================================================
        function [F,p,Fnull] = powerTest(X,pol,strata,rows,B,stream)
            % Sign-flip permutation test of the response power F = P_m/RN^2.
            %
            % P_m = mean_t (m_t - mean m)^2 and RN^2 = mean_t sem^2(t), both
            % from balancedMean over rows. The null is B permutations of signs
            % balanced within each file x polarity group (as plusMinus), in
            % blocks of BlockSize, each one matrix product: per permutation
            % m* = balanced combination of the signed group RESIDUALS (an odd
            % group's scaled as plusMinus scales them, so m* has the variance
            % m has) and F* = P_m*/RN^2. p = (1 + #(F* >= F))/(B + 1).
            %
            % The noise estimate is held at its observed value rather than
            % recomputed from sum(x^2) of the flipped sweeps: flipped raw
            % sweeps carry the polarity-locked CM (and the response) into the
            % permuted noise, which deflates F* and made the test reject a
            % pure-noise condition with a CM as large as its noise half the
            % time. Over residuals, with the denominator fixed, the null is
            % the response power of pure noise and the test holds its level.
            %
            % That null is an approximation that needs many distinct sign
            % patterns. The observed mean is made of the group means and the
            % null of the residuals about them -- independent pieces of the
            % data -- so the observed F is not one of the permutations, and
            % with small groups the few distinct F* cannot place it: at alpha
            % 0.05, pure noise was "detected" a third of the time at 4
            % alternating sweeps (two patterns) and one time in ten at 9. Below
            % MinSignPatterns distinct patterns (prod over groups of
            % nchoosek(n,floor(n/2)), doubled for an odd group, halved for
            % the global sign; about 14 alternating sweeps) p is NaN and
            % Fnull empty; F is still returned. Above it the test is close to
            % its level and exact in the limit: with 12-31 residual degrees of
            % freedom (N - G) it rejected pure noise at 0.05-0.065 for a
            % nominal 0.045 (B = 199), and at its level from about 36 on.
            %
            %   X       [nT x N] sweeps
            %   pol     1 x N +1/-1
            %   strata  1 x N file index ([] = one file)
            %   rows    nT x 1 logical, the response window ([] = all)
            %   B       number of permutations (default 1000; 0 = F only)
            %   stream  RandStream ([] = threefry seeded 1)
            %   F       (returned) observed F (NaN when undefined)
            %   p       (returned) permutation p (NaN when F or B is, or when
            %           the groups are too small for a sign-flip null)
            %   Fnull   (returned) B x 1 permutation null of F
            arguments
                X double
                pol double
                strata double = []
                rows = []
                B (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
                stream = []
            end
            N = size(X,2);
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,N);
            rows = mabr.analysis.SingleTrial.useRows(X,rows);
            F = NaN; p = NaN; Fnull = zeros(0,1);

            Xr = X(rows,:);
            G  = mabr.analysis.SingleTrial.groupInfo(pol,strata);
            if size(Xr,1) < 2 || N - G.nG < 1, return; end

            [m,sem] = mabr.analysis.Stats.balancedMean(Xr,pol,strata);
            RN2 = mean(sem.^2);
            F   = mean((m - mean(m)).^2)/RN2;
            if ~isfinite(F) || B < 1, return; end
            if mabr.analysis.SingleTrial.logSignPatterns(G) < ...
                    log(mabr.analysis.SingleTrial.MinSignPatterns)
                return
            end

            stream = mabr.analysis.SingleTrial.streamOrDefault(stream);
            Rw = mabr.analysis.SingleTrial.residuals(Xr,G).*((G.w.*G.oddScale).');   % nR x N
            Fnull = zeros(B,1);
            done = 0;
            while done < B
                nb = min(mabr.analysis.SingleTrial.BlockSize, B - done);
                S  = mabr.analysis.SingleTrial.balancedSigns(G,nb,stream);   % N x nb
                Ms = Rw*S;                                                  % nR x nb
                Fnull(done+(1:nb)) = (mean((Ms - mean(Ms,1)).^2,1)/RN2).';
                done = done + nb;
            end
            p = (1 + sum(Fnull >= F))/(B + 1);
        end

        function S = fsp(X,pol,strata,rows)
            % Fsp over the response window with an ESTIMATED numerator df.
            %
            % Q = sum_t (m_t - mean m)^2 over rows; E = residuals of X(rows,:)
            % from their file x polarity group means; S^ = E E'/(N - G); c =
            % (1/n+ + 1/n-)/4 (or 1/N); C = I - 11'/nR; A^ = c C S^ C, the
            % covariance of the demeaned balanced mean. Under H0, Q ~ tr(A)
            % chi2(nu1)/nu1 with nu1 = (tr A)^2/tr(A^2) (Satterthwaite);
            % tr(A^2) is estimated with Srivastava's bias correction,
            % n^2/((n-1)(n+2)) (tr(A^2) - (tr A)^2/n), n = N - G, and nu1 is
            % clamped to [1, nR-1]. Fsp = Q/tr(A^), nu2 = N - G, and p is
            % the upper F tail.
            %
            % The classic Fsp borrowed nu1 = 5 and nu2 = 250 from human EEG
            % tables; filtered 300-3000 Hz over a few ms the averaged noise
            % has tens of independent samples, and nu1 = 5 made the test
            % several dB too conservative. Estimating it from the data's own
            % residual covariance is what makes p comparable across rigs.
            %
            %   X, pol, strata, rows  as powerTest
            %   S  (returned) struct F, DF1, DF2, P (all NaN when undefined)
            arguments
                X double
                pol double
                strata double = []
                rows = []
            end
            S = struct('F',NaN,'DF1',NaN,'DF2',NaN,'P',NaN);
            N = size(X,2);
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,N);
            rows = mabr.analysis.SingleTrial.useRows(X,rows);
            Xr = X(rows,:);
            nR = size(Xr,1);
            G  = mabr.analysis.SingleTrial.groupInfo(pol,strata);
            n  = N - G.nG;
            if nR < 2 || n < 2, return; end

            m  = mabr.analysis.Stats.balancedMean(Xr,pol,strata);
            Q  = sum((m - mean(m)).^2);
            E  = mabr.analysis.SingleTrial.residuals(Xr,G);
            Sh = (E*E.')/n;
            % C*Sh*C without forming C: double-centre the covariance.
            Sc = Sh - mean(Sh,1) - mean(Sh,2) + mean(Sh(:));
            A  = G.c*Sc;
            trA  = trace(A);
            trA2 = sum(A.^2,'all');
            t2c  = n^2/((n-1)*(n+2))*(trA2 - trA^2/n);
            if t2c > 0 && isfinite(t2c)
                nu1 = trA^2/t2c;
            else
                nu1 = nR - 1;      % no measurable correlation left to correct for
            end
            nu1 = min(max(nu1,1),nR - 1);

            S.F   = Q/trA;
            S.DF1 = nu1;
            S.DF2 = n;
            S.P   = mabr.analysis.Stats.fsf(S.F,nu1,n);
        end

        % =================================================================
        %  Split-half reliability
        % =================================================================
        function R = splitHalf(X,pol,rows,opts)
            % Resampled split-half correlation (ABRpresto-like).
            %
            % Each resample draws, from each polarity class, 2K sweeps without
            % replacement: the first K go to half A, the next K to half B (so
            % both halves are polarity-balanced and disjoint). Each half is
            % averaged -- "median" across its sweeps, as ABRpresto does, or
            % "mean" -- and r is the Pearson correlation of the two halves over
            % rows. A median sub-average carries about pi/2 the noise variance
            % of a mean, so median-mode r is lower than mean-mode r on the
            % same data; ABRpresto's 0.30 criterion was set with medians.
            %
            % P025/P975 describe how r varies over PARTITIONS of this one
            % dataset. That is not sampling uncertainty, and nothing here or
            % downstream calls it a confidence interval.
            %
            %   X     [nT x N] sweeps
            %   pol   1 x N +1/-1
            %   rows  nT x 1 logical ([] = all finite rows)
            %   opts.K               sweeps per polarity per half ([] = floor(
            %                        min(n+,n-)/2), or floor(N/2) from all
            %                        sweeps when there is one polarity). A
            %                        larger K is reduced to what fits.
            %   opts.Resamples       number of random partitions (default 500)
            %   opts.Mode            "median" (default) | "mean"
            %   opts.Stream          RandStream ([] = threefry seeded 1)
            %   opts.MinPerPolarity  smallest K worth reporting (default 25)
            %   R  (returned) struct R (Resamples x 1), Mean, SD, P025, P975,
            %      K, N, Mode. K < MinPerPolarity: R empty, the rest NaN.
            arguments
                X double
                pol double
                rows = []
                opts.K double = []
                opts.Resamples (1,1) double {mustBeInteger,mustBePositive} = 500
                opts.Mode (1,1) string {mustBeMember(opts.Mode,["median","mean"])} = "median"
                opts.Stream = []
                opts.MinPerPolarity (1,1) double {mustBeNonnegative} = 25
            end
            N   = size(X,2);
            pol = mabr.analysis.SingleTrial.labels(pol,[],N);
            rows = mabr.analysis.SingleTrial.useRows(X,rows);
            Xr = X(rows,:);
            nR = size(Xr,1);

            iP = find(pol > 0);  iQ = find(pol < 0);
            bal = ~isempty(iP) && ~isempty(iQ);
            if bal
                Kmax = floor(min(numel(iP),numel(iQ))/2);
            else
                Kmax = floor(N/2);
            end
            if isempty(opts.K), K = Kmax; else, K = min(floor(opts.K(1)),Kmax); end

            R = struct('R',zeros(0,1),'Mean',NaN,'SD',NaN,'P025',NaN,'P975',NaN, ...
                'K',K,'N',N,'Mode',opts.Mode);
            if K < max(1,opts.MinPerPolarity) || nR < 2, return; end

            stream = mabr.analysis.SingleTrial.streamOrDefault(opts.Stream);
            nB = opts.Resamples;
            if bal, h = 2*K; else, h = K; end            % sweeps per half
            IA = zeros(h,nB);  IB = zeros(h,nB);
            for b = 1:nB
                if bal
                    a = iP(randperm(stream,numel(iP),2*K));
                    c = iQ(randperm(stream,numel(iQ),2*K));
                    IA(:,b) = [a(1:K) c(1:K)].';
                    IB(:,b) = [a(K+1:end) c(K+1:end)].';
                else
                    a = randperm(stream,N,2*K);
                    IA(:,b) = a(1:K).';
                    IB(:,b) = a(K+1:end).';
                end
            end

            % Averaged a chunk of partitions at a time as one 3-D array:
            % the same numbers as a loop, without 2*Resamples calls' overhead.
            chunk = max(1,floor(2e6/(nR*h)));
            r = zeros(nB,1);
            for b0 = 1:chunk:nB
                bb = b0:min(nB,b0+chunk-1);
                A3 = reshape(Xr(:,IA(:,bb)),nR,h,numel(bb));
                B3 = reshape(Xr(:,IB(:,bb)),nR,h,numel(bb));
                if opts.Mode == "median"
                    Am = reshape(median(A3,2),nR,[]);
                    Bm = reshape(median(B3,2),nR,[]);
                else
                    Am = reshape(mean(A3,2),nR,[]);
                    Bm = reshape(mean(B3,2),nR,[]);
                end
                r(bb) = mabr.analysis.SingleTrial.pearsonCols(Am,Bm).';
            end

            R.R    = r;
            R.Mean = mean(r);
            R.SD   = std(r);
            R.P025 = mabr.analysis.Stats.percentile(r,0.025);
            R.P975 = mabr.analysis.Stats.percentile(r,0.975);
        end

        % =================================================================
        %  Convergence with N
        % =================================================================
        function C = convergence(X,pol,strata,rows,ns,stream)
            % RN, response RMS, F, SNR and one split-half r against N.
            %
            % For each n in ns: the first ceil(n/2) sweeps of each polarity in
            % acquisition order (the column order of X; pass clean sweeps), or
            % the first n of one-polarity data. Averaging that works makes RN
            % fall as 1/sqrt(N), a slope of -0.5 on log-log axes; a flatter
            % slope is drift, a non-stationary electrode, or a response that
            % is not time-locked.
            %
            %   X, pol, strata, rows  as powerTest
            %   ns      sweep counts ([] = 8, 16, 32, ... up to N, and N)
            %   stream  RandStream for the split-half draws ([] = threefry 1)
            %   C  (returned) table N, RN, ResponseRMS, F, SNR, SplitR -- one
            %      row per ns entry; N is the count actually used. SplitR is
            %      ONE random mean-mode partition, a noisy value by design.
            arguments
                X double
                pol double
                strata double = []
                rows = []
                ns double = []
                stream = []
            end
            Ntot = size(X,2);
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,Ntot);
            rows   = mabr.analysis.SingleTrial.useRows(X,rows);
            stream = mabr.analysis.SingleTrial.streamOrDefault(stream);
            if isempty(ns)
                ns = 2.^(3:floor(log2(max(Ntot,1))));
                ns = unique([ns(ns < Ntot) Ntot]);
            end
            ns = reshape(ns,1,[]);
            iP = find(pol > 0);  iQ = find(pol < 0);
            bal = ~isempty(iP) && ~isempty(iQ);

            k = numel(ns);
            N = nan(k,1); RN = N; ResponseRMS = N; F = N; SNR = N; SplitR = N;
            for i = 1:k
                if bal
                    h = ceil(ns(i)/2);
                    sel = sort([iP(1:min(h,end)) iQ(1:min(h,end))]);
                else
                    sel = 1:min(ns(i),Ntot);
                end
                N(i) = numel(sel);
                if N(i) < 2 || ~any(rows), continue; end
                [m,sem] = mabr.analysis.Stats.balancedMean(X(rows,sel),pol(sel),strata(sel));
                Pm = mean((m - mean(m)).^2);
                RN(i) = sqrt(mean(sem.^2));
                ResponseRMS(i) = sqrt(Pm);
                F(i)   = Pm/RN(i)^2;
                SNR(i) = 10*log10(F(i));
                sh = mabr.analysis.SingleTrial.splitHalf(X(:,sel),pol(sel),rows, ...
                    Resamples=1,Mode="mean",Stream=stream,MinPerPolarity=1);
                SplitR(i) = sh.Mean;
            end
            C = table(N,RN,ResponseRMS,F,SNR,SplitR);
        end

        % =================================================================
        %  Per-sweep features
        % =================================================================
        function T = features(X,rows,baselineRows)
            % One row of quality-control features per sweep.
            %
            % RMS, P2P and MaxAbs over rows; BaselineRMS over baselineRows
            % (NaN when there is none). TemplateAmp is each sweep's projection
            % onto the leave-one-out mean m~_k = (sum x - x_k)/(N-1) over rows,
            % beta_k = <x_k,m~_k>/<m~_k,m~_k>, divided by mean(beta) so the
            % features average exactly 1 -- a sweep at 2 carries twice the
            % typical response. That needs a response to be typical of: when
            % mean(beta) is less than 3 standard errors above zero (std(beta)
            % /sqrt(N)) the average holds none, the division is by noise --
            % values in the hundreds of either sign, in a condition below
            % threshold -- and TemplateAmp is NaN for every sweep instead.
            % TemplateR is corrcoef(x_k, m~_k) over rows; at
            % ABR single-sweep SNRs (around -18 dB) it is mostly noise and is
            % a QC feature only, never a detection statistic.
            %
            %   X             [nT x N] sweeps
            %   rows          nT x 1 logical ([] = all finite rows)
            %   baselineRows  nT x 1 logical or indices ([] = none)
            %   T  (returned) N-row table RMS, P2P, MaxAbs, BaselineRMS,
            %      TemplateAmp, TemplateR (volts, except the last two)
            arguments
                X double
                rows = []
                baselineRows = []
            end
            N  = size(X,2);
            rows = mabr.analysis.SingleTrial.useRows(X,rows);
            Xr = X(rows,:);
            if isempty(Xr)
                RMS = nan(N,1); P2P = RMS; MaxAbs = RMS;
            else
                RMS    = sqrt(mean(Xr.^2,1)).';
                P2P    = (max(Xr,[],1) - min(Xr,[],1)).';
                MaxAbs = max(abs(Xr),[],1).';
            end

            BaselineRMS = nan(N,1);
            if ~isempty(baselineRows)
                br = mabr.analysis.SingleTrial.useRows(X,baselineRows);
                if any(br)
                    BaselineRMS = sqrt(mean(X(br,:).^2,1)).';
                end
            end

            TemplateAmp = nan(N,1);  TemplateR = nan(N,1);
            if N >= 2 && ~isempty(Xr)
                M = (sum(Xr,2) - Xr)/(N - 1);            % leave-one-out means
                beta = (sum(Xr.*M,1)./sum(M.^2,1)).';
                mb = mean(beta);
                if mb > mabr.analysis.SingleTrial.TemplateMinT*std(beta)/sqrt(N)
                    TemplateAmp = beta/mb;
                end
                TemplateR   = mabr.analysis.SingleTrial.pearsonCols(Xr,M).';
            end
            T = table(RMS,P2P,MaxAbs,BaselineRMS,TemplateAmp,TemplateR);
        end

        % =================================================================
        %  Block sub-averages
        % =================================================================
        function [Tb,Tw] = blocks(X,pol,order,rows,tMs,blockSize,picks)
            % Consecutive polarity-balanced sub-averages, for drift and adaptation.
            %
            % A single sweep is far below the noise, so trial-to-trial change
            % is seen in BLOCKS. Sweeps are walked in acquisition order; a
            % block fills until it holds blockSize/2 sweeps of EACH polarity
            % (blockSize of one-polarity data). A sweep whose polarity is
            % already full waits for the next block, so every block is
            % balanced; what is left when the sweeps run out is dropped and
            % counted.
            %
            %   X          [nT x N] sweeps
            %   pol        1 x N +1/-1
            %   order      1 x N acquisition rank ([] = column order)
            %   rows       nT x 1 logical, the window RN and ResponseRMS are
            %              taken over ([] = all finite rows)
            %   tMs        nT x 1 time (ms); needed only with picks
            %   blockSize  sweeps per block (default 64)
            %   picks      [] or struct array / table with Wave, PeakLatency,
            %              TroughLatency (ms): each block's average is re-picked
            %              within +-0.3 ms of each (parabolic refinement)
            %   Tb  (returned) table Block, N, FirstOrder, LastOrder, RN (RMS of
            %       the block's +/- reference over rows), ResponseRMS.
            %       Tb.Properties.UserData: Dropped (sweeps in no block) and
            %       Members (cell, the column indices of each block).
            %       The block's +/- reference alternates signs WITHIN each
            %       polarity in acquisition order, over residuals from the
            %       class means: deterministic, and blind to the CM.
            %   Tw  (returned) table Block, Wave, PeakLatency, AmpPT (V)
            arguments
                X double
                pol double
                order double = []
                rows = []
                tMs double = []
                blockSize (1,1) double {mustBeInteger,mustBePositive} = 64
                picks = []
            end
            N   = size(X,2);
            pol = mabr.analysis.SingleTrial.labels(pol,[],N);
            if isempty(order), order = 1:N; end
            order = reshape(double(order),1,[]);
            rows  = mabr.analysis.SingleTrial.useRows(X,rows);

            isP = pol > 0;
            bal = any(isP) && any(~isP);
            if bal, per = floor(blockSize/2); else, per = blockSize; end
            per = max(per,1);

            [~,walk] = sort(order,'ascend');      % stable: ties keep column order
            members = {};
            cur = zeros(1,0);  pend = zeros(1,0);
            for k = walk
                [cur,pend] = mabr.analysis.SingleTrial.offer(cur,pend,k,isP,per,bal);
                while mabr.analysis.SingleTrial.isFull(cur,isP,per,bal)
                    members{end+1} = cur; %#ok<AGROW>
                    cur = zeros(1,0);
                    queue = pend;  pend = zeros(1,0);
                    for j = queue
                        [cur,pend] = mabr.analysis.SingleTrial.offer(cur,pend,j,isP,per,bal);
                    end
                end
            end
            dropped = numel(cur) + numel(pend);

            nBk = numel(members);
            Block = (1:nBk).';
            Nb = zeros(nBk,1); FirstOrder = nan(nBk,1); LastOrder = FirstOrder;
            RN = nan(nBk,1); ResponseRMS = RN;
            means = cell(nBk,1);
            for b = 1:nBk
                k = members{b};
                Nb(b) = numel(k);
                FirstOrder(b) = min(order(k));
                LastOrder(b)  = max(order(k));
                [~,o] = sort(order(k));
                k = k(o);                                 % acquisition order inside
                means{b} = mabr.analysis.Stats.balancedMean(X(:,k),pol(k),ones(1,numel(k)));
                if any(rows)
                    m = means{b}(rows);
                    q = mabr.analysis.SingleTrial.alternatingReference(X(rows,k),pol(k));
                    RN(b) = sqrt(mean(q.^2));
                    ResponseRMS(b) = sqrt(mean((m - mean(m)).^2));
                end
            end
            Tb = table(Block,Nb,FirstOrder,LastOrder,RN,ResponseRMS, ...
                'VariableNames',{'Block','N','FirstOrder','LastOrder','RN','ResponseRMS'});
            Tb.Properties.UserData = struct('Dropped',dropped,'Members',{members});

            Tw = table(zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
                'VariableNames',{'Block','Wave','PeakLatency','AmpPT'});
            pk = mabr.analysis.SingleTrial.pickList(picks);
            if isempty(pk.Wave) || nBk == 0, return; end
            t = reshape(tMs,[],1);
            if numel(t) ~= size(X,1)
                error('mabr:analysis:SingleTrial:time', ...
                    'tMs has %d samples and X %d rows.',numel(t),size(X,1));
            end
            nW = numel(pk.Wave);
            Bl = reshape(repelem(Block,nW),[],1);  Wv = repmat(pk.Wave,nBk,1);   % repelem of a scalar is a row
            Lat = nan(nBk*nW,1);  Amp = Lat;
            for b = 1:nBk
                for w = 1:nW
                    i = (b-1)*nW + w;
                    [lp,vp] = mabr.analysis.Peaks.repick(t,means{b},pk.PeakLatency(w),0.3,"P");
                    [~,vt]  = mabr.analysis.Peaks.repick(t,means{b},pk.TroughLatency(w),0.3,"N");
                    Lat(i) = lp;
                    Amp(i) = vp - vt;
                end
            end
            Tw = table(Bl,Wv,Lat,Amp,'VariableNames',{'Block','Wave','PeakLatency','AmpPT'});
        end

        % =================================================================
        %  Bootstrap
        % =================================================================
        function [lo,hi] = bootstrapBand(X,pol,strata,B,alpha,stream)
            % Pointwise percentile bootstrap band of the balanced mean.
            %
            % Sweeps are resampled with replacement WITHIN each file x polarity
            % group (fixed counts, so every replicate is as balanced as the
            % data), the balanced mean is formed per replicate, and lo/hi are
            % the alpha/2 and 1-alpha/2 percentiles per sample.
            %
            %   X, pol, strata  as balancedMean
            %   B       replicates (default 500)
            %   alpha   two-sided level (default 0.05)
            %   stream  RandStream ([] = threefry seeded 1)
            %   lo, hi  (returned) nT x 1 (NaN on rows holding any NaN)
            arguments
                X double
                pol double
                strata double = []
                B (1,1) double {mustBeInteger,mustBePositive} = 500
                alpha (1,1) double {mustBeInRange(alpha,0,1,"exclusive")} = 0.05
                stream = []
            end
            nT = size(X,1);
            lo = nan(nT,1);  hi = lo;
            if size(X,2) < 2, return; end
            M = mabr.analysis.SingleTrial.bootstrapMeans(X,pol,strata,B,stream);
            fin = all(isfinite(M),2);
            if ~any(fin), return; end
            Q = mabr.analysis.Stats.percentileCols(M(fin,:).',[alpha/2 1-alpha/2]);
            lo(fin) = Q(1,:).';
            hi(fin) = Q(2,:).';
        end

        function M = bootstrapMeans(X,pol,strata,B,stream)
            % Balanced means of B within-group bootstrap resamples.
            %
            % The resampling engine behind bootstrapBand and
            % mabr.analysis.Peaks.bootstrap: each replicate draws n_g sweeps
            % with replacement inside every file x polarity group, and its
            % balanced mean is one column of X*W, W holding each sweep's draw
            % count times its class weight.
            %
            %   X, pol, strata  as balancedMean
            %   B       replicates
            %   stream  RandStream ([] = threefry seeded 1)
            %   M       (returned) [nT x B] replicate means (rows of X holding
            %           a NaN are NaN)
            arguments
                X double
                pol double
                strata double = []
                B (1,1) double {mustBeInteger,mustBePositive} = 500
                stream = []
            end
            [nT,N] = size(X);
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,N);
            stream = mabr.analysis.SingleTrial.streamOrDefault(stream);
            G   = mabr.analysis.SingleTrial.groupInfo(pol,strata);
            fin = all(isfinite(X),2);
            M   = nan(nT,B);
            Xf  = X(fin,:);
            members = arrayfun(@(g) find(G.gid == g),1:G.nG,'UniformOutput',false);
            done = 0;
            while done < B
                nb = min(mabr.analysis.SingleTrial.BlockSize, B - done);
                subs = cell(G.nG,1);
                for g = 1:G.nG
                    k  = members{g};
                    ng = numel(k);
                    d  = randi(stream,ng,ng,nb);                       % ng x nb draws
                    subs{g} = [reshape(k(d),[],1) reshape(repelem((1:nb).',ng),[],1)];
                end
                subs = vertcat(subs{:});
                Cnt  = accumarray(subs,1,[N nb]);                       % draw counts
                M(fin,done+(1:nb)) = Xf*(Cnt.*G.w);
                done = done + nb;
            end
        end

        % =================================================================
        %  Correlation with the next-louder level
        % =================================================================
        function [r,lagMs,r0] = xcorrUp(mLow,mHigh,rows,maxLagSamples,dtMs)
            % Morphology agreement of a mean with the next-louder level's mean.
            %
            % For tau = 0..maxLagSamples, r(tau) = corrcoef(mLow(t+tau),
            % mHigh(t)) over t in rows with both finite; r = max r(tau), lagMs
            % its lag. One direction only: a quieter response is LATER, so the
            % quieter mean is advanced to meet the louder one (Suthakar &
            % Liberman 2019, who use lag 0; a small lag allowance stops the
            % latency shift itself from reading as a loss of morphology).
            %
            %   mLow, mHigh    nT x 1 means of the quieter and louder level
            %   rows           nT x 1 logical ([] = all)
            %   maxLagSamples  largest advance tried (default 0)
            %   dtMs           sample interval (ms)
            %   r      (returned) the best correlation (NaN when < 3 pairs)
            %   lagMs  (returned) its lag, ms (NaN with r)
            %   r0     (returned) the lag-0 correlation
            arguments
                mLow (:,1) double
                mHigh (:,1) double
                rows = []
                maxLagSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                dtMs (1,1) double {mustBePositive} = 1
            end
            n = numel(mLow);
            if numel(mHigh) ~= n
                error('mabr:analysis:SingleTrial:xcorrSize', ...
                    'mLow has %d samples and mHigh %d.',n,numel(mHigh));
            end
            if isempty(rows), rows = true(n,1); end
            if ~islogical(rows), r_ = false(n,1); r_(rows) = true; rows = r_; end
            idx = find(rows(:));
            rr = nan(maxLagSamples+1,1);
            for tau = 0:maxLagSamples
                t = idx(idx + tau <= n);
                a = mLow(t + tau);  b = mHigh(t);
                ok = isfinite(a) & isfinite(b);
                if nnz(ok) >= 3
                    rr(tau+1) = mabr.analysis.SingleTrial.pearsonCols(a(ok),b(ok));
                end
            end
            r0 = rr(1);
            if all(isnan(rr))
                r = NaN; lagMs = NaN;
            else
                [r,i] = max(rr);
                lagMs = (i-1)*dtMs;
            end
        end

        function [r,lagMs,rangeMs] = dtwUp(mLow,mHigh,rows,maxLagSamples,dtMs,smoothMs)
            % xcorrUp with a lag that changes along the response: the
            % correlation after dynamic time warping (Signal Processing's
            % dtw), with the warp smoothed.
            %
            % xcorrUp advances the quieter mean by ONE lag for the whole
            % window. A quieter response is not the louder one shifted,
            % though: its later waves are delayed more than its early ones
            % (wave V by about twice wave I's latency shift per dB), so one
            % lag can line up wave I or wave V but not both, and the part
            % left out of line reads as a loss of morphology. Here the lag
            % follows the response:
            %
            %   1. The louder mean over the rows, Y = mHigh(J), and the
            %      quieter one advanced by half the allowance, X = mLow(J+s),
            %      s = floor(maxLagSamples/2), each z-scored (r ignores scale
            %      and offset, so the warp should too).
            %   2. [~,ix,iy] = dtw(X,Y,s): a path within s samples of the
            %      diagonal, so with the advance a lag of 0 to 2s samples at
            %      each louder sample (the mean of the quieter samples the
            %      path pairs it with). One direction only, as in xcorrUp: a
            %      quieter response is later, never earlier. dtw pairs the
            %      two ends, so the path starts and ends at lag s and reaches
            %      any lag in s samples (0.17 ms at 12 kHz and the default
            %      0.3 ms allowance).
            %   3. That lag smoothed by a moving mean over smoothMs (default
            %      DTWLagSmoothMs, 2 ms) and held to [0, 2s]. A warp free to
            %      move at every sample lines noise up -- see DTWLagSmoothMs
            %      for the numbers -- while a latency shift changes slowly
            %      from wave to wave.
            %   4. The quieter mean read at each louder sample plus its lag
            %      (linear interpolation), and r = its Pearson correlation
            %      with Y: one pair per louder sample, as many as the lag-0
            %      correlation has.
            %
            % With an allowance under 2 samples there is nothing to warp
            % (s = 0) and r is the lag-0 correlation.
            %
            %   mLow, mHigh    nT x 1 means of the quieter and louder level
            %   rows           nT x 1 logical ([] = all), read as one
            %                  sequence; a row is dropped where either mean
            %                  is not finite or the lag runs past the end
            %   maxLagSamples  largest delay of the quieter mean (default 0),
            %                  rounded down to an even number of samples
            %   dtMs           sample interval (ms)
            %   smoothMs       moving-mean span of the lag, ms (default
            %                  DTWLagSmoothMs; 0 = the path's own lag)
            %   r        (returned) correlation after warping (NaN with fewer
            %            than 3 rows or a flat mean)
            %   lagMs    (returned) mean lag over the rows, ms (NaN with r)
            %   rangeMs  (returned) largest minus smallest lag, ms: 0 when
            %            the warp is one rigid shift (NaN with r)
            arguments
                mLow (:,1) double
                mHigh (:,1) double
                rows = []
                maxLagSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                dtMs (1,1) double {mustBePositive} = 1
                smoothMs (1,1) double {mustBeNonnegative,mustBeFinite} = mabr.analysis.SingleTrial.DTWLagSmoothMs
            end
            n = numel(mLow);
            if numel(mHigh) ~= n
                error('mabr:analysis:SingleTrial:xcorrSize', ...
                    'mLow has %d samples and mHigh %d.',n,numel(mHigh));
            end
            if isempty(rows), rows = true(n,1); end
            if ~islogical(rows), r_ = false(n,1); r_(rows) = true; rows = r_; end
            r = NaN; lagMs = NaN; rangeMs = NaN;
            s = floor(maxLagSamples/2);
            J = find(rows(:));
            J = J(J + 2*s <= n);
            J = J(isfinite(mHigh(J)) & isfinite(mLow(J + s)));
            m = numel(J);
            if m < 3, return; end
            X = mLow(J + s);
            Y = mHigh(J);
            sx = std(X);  sy = std(Y);
            if ~(sx > 0 && sy > 0), return; end
            if s > 0
                [~,ix,iy] = dtw(((X - mean(X))/sx).',((Y - mean(Y))/sy).',s);
                ix = ix(:);  iy = iy(:);
                lag = accumarray(iy,J(ix) + s,[m 1])./accumarray(iy,1,[m 1]) - J;
                span = round(smoothMs/dtMs);
                if span > 1
                    lag = movmean(lag,span,'Endpoints','shrink');
                end
                lag = min(max(lag,0),2*s);
                Xw  = interp1((1:n).',mLow,J + lag,'linear');
            else
                Xw  = X;
                lag = zeros(m,1);
            end
            ok = isfinite(Xw);
            if nnz(ok) < 3, return; end
            r = mabr.analysis.SingleTrial.pearsonCols(Xw(ok),Y(ok));
            lagMs   = mean(lag(ok))*dtMs;
            rangeMs = (max(lag(ok)) - min(lag(ok)))*dtMs;
        end

        % =================================================================
        %  No noise
        % =================================================================
        function [tf,rel] = zeroVariance(X,pol,strata,rows)
            % Whether the sweeps hold no noise: they do not vary within their
            % file x polarity groups.
            %
            % The noise is the residual of each sweep from its group's mean
            % -- the residual every statistic here pools -- so a polarity-
            % following CM, which makes the sweeps differ, is not noise, and
            % sweeps that differ only by the stimulus sign count as identical.
            % Its RMS, pooled over the groups (N - G degrees of freedom), is
            % compared with the RMS of the sweeps themselves: at or under
            % ZeroVarianceTol of it (or with every sample zero) there is
            % nothing to test a response against. Every sign-flip permutation
            % of such sweeps is then either the observed mean itself or a
            % degenerate one, and the t statistic of a sweep set whose
            % magnitudes agree is unbounded -- which is what once kept a TFCE
            % test of a noiseless condition integrating for a quarter of an
            % hour.
            %
            %   X       [nT x N] sweeps
            %   pol     1 x N +1/-1 ([] = all +1: one polarity)
            %   strata  1 x N file index ([] = one file)
            %   rows    nT x 1 logical, the samples judged ([] = all finite rows)
            %   tf      (returned) true when the sweeps hold no noise; false
            %           too when that cannot be said (fewer sweeps than groups
            %           plus one, or no finite row)
            %   rel     (returned) noise RMS / sweep RMS (NaN when undefined,
            %           0 for an all-zero condition)
            arguments
                X double
                pol double = []
                strata double = []
                rows = []
            end
            tf = false;  rel = NaN;
            N = size(X,2);
            if N < 2, return; end
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,N);
            rows = mabr.analysis.SingleTrial.useRows(X,rows);
            Xr = X(rows,:);
            if isempty(Xr), return; end
            G = mabr.analysis.SingleTrial.groupInfo(pol,strata);
            if N - G.nG < 1, return; end             % no sweep to estimate noise from
            scale = sqrt(mean(Xr.^2,'all'));
            if scale == 0
                tf = true;  rel = 0;
                return
            end
            R = mabr.analysis.SingleTrial.residuals(Xr,G);
            noise = sqrt(sum(R.^2,'all')/((N - G.nG)*size(Xr,1)));
            rel = noise/scale;
            tf = rel <= mabr.analysis.SingleTrial.ZeroVarianceTol;
        end

        % =================================================================
        %  Everything one condition needs
        % =================================================================
        function S = summary(X,tMs,pol,strata,opts)
            % The single-trial measures of one condition, in one call.
            %
            %   X       [nT x N] sweeps (clean ones)
            %   tMs     nT x 1 time, ms (checked against X)
            %   pol     1 x N +1/-1 ([] = all +1)
            %   strata  1 x N file index ([] = one file)
            %   opts.Rows                response window ([] = all finite rows)
            %   opts.BaselineRows        baseline window ([] = none: BaselineRMS NaN)
            %   opts.SplitRows           split-half window ([] = Rows)
            %   opts.Stream              RandStream ([] = threefry seeded 1);
            %                            drawn from by the +/- reference, then
            %                            the power test, then the split-half
            %   opts.NumPermutations     power-test permutations (default 1000)
            %   opts.SplitHalfMode       "median" (default) | "mean"
            %   opts.SplitHalfResamples  default 500
            %   opts.SplitHalfK          [] = from the data (see splitHalf)
            %   opts.MinPerPolarity      split-half minimum K (default 25)
            %   opts.Measures            "all" (default), "none", or any of
            %                            "power", "fsp", "splithalf": the costly
            %                            ones to compute (the rest always are)
            %   S  (returned) struct: N, NPos, NNeg, Balanced; Mean, MeanPos,
            %      MeanNeg, SEM, PlusMinus (nT x 1, every row); RN =
            %      sqrt(mean sem^2) and RNPM (RMS of the +/- reference) over
            %      Rows; ResponseRMS = sqrt(P_m); BaselineRMS (RMS of the
            %      demeaned mean over BaselineRows); F, PowerP, PowerF95 (95th
            %      percentile of the power-test null; both NaN for a condition
            %      too small for a sign-flip null, see powerTest), SNR = 10 log10 F,
            %      SNRCorr = 10 log10(F-1) (NaN when F <= 1); Fsp, FspDF1,
            %      FspDF2, FspP; SplitR, SplitRSD, SplitRP025, SplitRP975,
            %      SplitN (K); Flags (string row). Sweeps with no noise
            %      (zeroVariance over Rows) leave F, SNR, SNRCorr, PowerP,
            %      PowerF95, Fsp*, and SplitR* NaN and add FlagZeroVariance.
            arguments
                X double
                tMs double = []
                pol double = []
                strata double = []
                opts.Rows = []
                opts.BaselineRows = []
                opts.SplitRows = []
                opts.Stream = []
                opts.NumPermutations (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
                opts.SplitHalfMode (1,1) string {mustBeMember(opts.SplitHalfMode,["median","mean"])} = "median"
                opts.SplitHalfResamples (1,1) double {mustBeInteger,mustBePositive} = 500
                opts.SplitHalfK double = []
                opts.MinPerPolarity (1,1) double {mustBeNonnegative} = 25
                opts.Measures (1,:) string {mustBeMember(opts.Measures,["all","none","power","fsp","splithalf"])} = "all"
            end
            [nT,N] = size(X);
            if ~isempty(tMs) && numel(tMs) ~= nT
                error('mabr:analysis:SingleTrial:time', ...
                    'tMs has %d samples and X %d rows.',numel(tMs),nT);
            end
            if isempty(pol), pol = ones(1,N); end
            [pol,strata] = mabr.analysis.SingleTrial.labels(pol,strata,N);
            stream = mabr.analysis.SingleTrial.streamOrDefault(opts.Stream);
            want = @(m) any(opts.Measures == "all") || any(opts.Measures == m);

            rows = mabr.analysis.SingleTrial.useRows(X,opts.Rows);
            if isempty(opts.SplitRows)
                splitRows = rows;
            else
                splitRows = mabr.analysis.SingleTrial.useRows(X,opts.SplitRows);
            end

            S = mabr.analysis.SingleTrial.emptySummary(nT);
            isP = pol > 0;
            S.N = N;  S.NPos = sum(isP);  S.NNeg = sum(~isP);
            S.Balanced = S.NPos > 0 && S.NNeg > 0;
            if ~S.Balanced
                S.Flags = mabr.analysis.SingleTrial.FlagUnbalanced;
            end
            if N == 0, return; end

            [m,sem] = mabr.analysis.Stats.balancedMean(X,pol,strata);
            S.Mean = m;
            S.SEM  = sem;
            if S.NPos > 0, S.MeanPos = mean(X(:,isP),2); end
            if S.NNeg > 0, S.MeanNeg = mean(X(:,~isP),2); end
            if N < 2, return; end

            q = mabr.analysis.SingleTrial.plusMinus(X,pol,strata,stream);
            S.PlusMinus = q;
            if any(rows)
                mr = m(rows);
                Pm = mean((mr - mean(mr)).^2);
                S.RN          = sqrt(mean(sem(rows).^2));
                S.RNPM        = sqrt(mean(q(rows).^2));
                S.ResponseRMS = sqrt(Pm);
                S.F           = Pm/S.RN^2;
                S.SNR         = 10*log10(S.F);
                if S.F > 1, S.SNRCorr = 10*log10(S.F - 1); end
            end
            if ~isempty(opts.BaselineRows)
                br = mabr.analysis.SingleTrial.useRows(X,opts.BaselineRows);
                if any(br)
                    mb = m(br);
                    S.BaselineRMS = sqrt(mean((mb - mean(mb)).^2));
                end
            end

            % No noise, no ratio over it: RN stays (it is 0, which is true),
            % everything measured against it is NaN, and the tests that would
            % divide by it are not run.
            noNoise = any(rows) && mabr.analysis.SingleTrial.zeroVariance(X,pol,strata,rows);
            if noNoise
                S.F = NaN;  S.SNR = NaN;  S.SNRCorr = NaN;
                S.Flags = [reshape(string(S.Flags),1,[]) mabr.analysis.SingleTrial.FlagZeroVariance];
            end

            if want("power") && any(rows) && opts.NumPermutations > 0 && ~noNoise
                [~,S.PowerP,Fnull] = mabr.analysis.SingleTrial.powerTest(X,pol,strata, ...
                    rows,opts.NumPermutations,stream);
                if ~isempty(Fnull)
                    S.PowerF95 = mabr.analysis.Stats.percentile(Fnull,0.95);
                end
            end
            if want("fsp") && any(rows) && ~noNoise
                f = mabr.analysis.SingleTrial.fsp(X,pol,strata,rows);
                S.Fsp = f.F;  S.FspDF1 = f.DF1;  S.FspDF2 = f.DF2;  S.FspP = f.P;
            end
            if want("splithalf") && any(splitRows) && ~noNoise
                sh = mabr.analysis.SingleTrial.splitHalf(X,pol,splitRows, ...
                    K=opts.SplitHalfK,Resamples=opts.SplitHalfResamples, ...
                    Mode=opts.SplitHalfMode,Stream=stream, ...
                    MinPerPolarity=opts.MinPerPolarity);
                S.SplitR = sh.Mean;  S.SplitRSD = sh.SD;
                S.SplitRP025 = sh.P025;  S.SplitRP975 = sh.P975;
                S.SplitN = sh.K;
            end
        end
    end

    methods (Static, Access = private)
        % =================================================================
        %  Group structure
        % =================================================================
        function [pol,strata] = labels(pol,strata,N)
            % The labels Stats.balancedMean accepts, normalized once.
            %
            %   pol     [] (all +1) or one per sweep; 0 and NaN read as +1
            %   strata  [] or a scalar (one file) or one finite index per sweep
            %   N       sweeps
            %   pol, strata  (returned) 1 x N each, pol +1/-1
            pol = reshape(double(pol),1,[]);
            if isempty(pol), pol = ones(1,N); end
            if numel(pol) ~= N
                error('mabr:analysis:SingleTrial:polarity', ...
                    'pol has %d entries for %d sweeps.',numel(pol),N);
            end
            pol = sign(pol);  pol(pol == 0 | isnan(pol)) = 1;
            strata = reshape(double(strata),1,[]);
            if isempty(strata), strata = ones(1,N); end
            if isscalar(strata), strata = repmat(strata,1,N); end
            if numel(strata) ~= N
                error('mabr:analysis:SingleTrial:strata', ...
                    'strata has %d entries for %d sweeps.',numel(strata),N);
            end
            if any(~isfinite(strata))
                error('mabr:analysis:SingleTrial:strata', ...
                    'strata must be finite: one file index per sweep.');
            end
        end

        function G = groupInfo(pol,strata)
            % The file x polarity groups and the weights of the balanced mean.
            %
            %   pol, strata  1 x N, already through labels()
            %   G  (returned) struct: N, gid (1 x N group of each sweep), n
            %      (1 x nG sizes), nG, A (N x nG sparse indicator), w (N x 1:
            %      m = X*w is the balanced mean), c (sem^2 = c*s^2), nPos,
            %      nNeg, Balanced, and oddScale (N x 1, see below)
            %
            % oddScale: balanced signs leave an odd group of n one unpaired
            % sign, so sum s_k r_k over its residuals has variance (n - 1/n)
            % sigma^2 where the group's share of the mean has n sigma^2.
            % Scaling that group's residuals by n/sqrt(n^2 - 1) restores the
            % second moment exactly (1 for even groups and for a group of one,
            % whose residual is zero).
            N = numel(pol);
            [~,~,gid] = unique([strata(:) pol(:)],'rows');
            G.N   = N;
            G.gid = reshape(gid,1,[]);
            G.nG  = max([gid; 0]);
            G.n   = reshape(accumarray(gid(:),1,[G.nG 1]),1,[]);
            G.A   = sparse((1:N).',gid(:),1,N,G.nG);
            f = ones(1,G.nG);
            odd = mod(G.n,2) == 1 & G.n >= 3;
            f(odd) = G.n(odd)./sqrt(G.n(odd).^2 - 1);
            G.oddScale = reshape(f(G.gid),[],1);
            isP = pol > 0;
            G.nPos = sum(isP);  G.nNeg = N - G.nPos;
            G.Balanced = G.nPos > 0 && G.nNeg > 0;
            G.w = zeros(N,1);
            if G.Balanced
                G.w(isP)  = 1/(2*G.nPos);
                G.w(~isP) = 1/(2*G.nNeg);
                G.c = 0.25*(1/G.nPos + 1/G.nNeg);
            else
                G.w(:) = 1/max(N,1);
                G.c = 1/max(N,1);
            end
        end

        function R = residuals(X,G)
            % X: [nR x N]; G: from groupInfo. R (returned): each sweep minus
            % its file x polarity group mean.
            Mg = (X*G.A)./G.n;
            R  = X - Mg(:,G.gid);
        end

        function S = balancedSigns(G,nb,stream)
            % nb random sign vectors, balanced within every group.
            %
            % A group of n gets floor(n/2) of +1 and of -1 in a random order,
            % and an odd group's remaining sweep a random sign: the signs of
            % one column are the uniform draws compared with their own median
            % (exactly half above it), the median element itself a coin flip.
            %
            %   G       from groupInfo
            %   nb      number of sign vectors
            %   stream  RandStream
            %   S       (returned) [N x nb] of +1/-1
            S = zeros(G.N,nb);
            for g = 1:G.nG
                k = find(G.gid == g);
                U = rand(stream,numel(k),nb);
                s = sign(U - median(U,1));
                z = s == 0;
                if any(z(:))
                    flip = 2*(rand(stream,1,nb) > 0.5) - 1;
                    F = repmat(flip,numel(k),1);
                    s(z) = F(z);
                end
                S(k,:) = s;
            end
        end

        function v = logSignPatterns(G)
            % log of the number of distinct balanced sign patterns of the
            % group residuals, up to the global sign (which leaves F*
            % unchanged): nchoosek(n,floor(n/2)) per group of n >= 2, twice
            % that for an odd group (its leftover sweep's sign); a group of
            % one has a zero residual and adds nothing. G: from groupInfo.
            n = G.n(G.n >= 2);
            h = floor(n/2);
            v = sum(gammaln(n + 1) - gammaln(h + 1) - gammaln(n - h + 1) + ...
                log(2)*mod(n,2)) - log(2);
        end

        function q = alternatingReference(X,pol)
            % Deterministic +/- reference of one block: signs alternate +,-,+
            % WITHIN each polarity in column (acquisition) order, over the
            % residuals from the class mean (an odd class's scaled by
            % n/sqrt(n^2-1), as groupInfo explains). X: [nR x n]; pol: 1 x n.
            % q (returned): nR x 1.
            isP = pol > 0;
            q = zeros(size(X,1),1);
            bal = any(isP) && any(~isP);
            for cls = [true false]
                k = find(isP == cls);
                n = numel(k);
                if n == 0, continue; end
                r = X(:,k) - mean(X(:,k),2);
                s = (-1).^(0:n-1);
                if bal, w = 1/(2*n); else, w = 1/n; end
                if mod(n,2) == 1 && n >= 3, w = w*n/sqrt(n^2 - 1); end
                q = q + r*(s.'*w);
            end
        end

        function [cur,pend] = offer(cur,pend,k,isP,per,bal)
            % Put sweep k into the open block if its polarity still has room,
            % else into the queue for the next block.
            if bal
                full = sum(isP(cur) == isP(k)) >= per;
            else
                full = numel(cur) >= per;
            end
            if full, pend(end+1) = k; else, cur(end+1) = k; end
        end

        function tf = isFull(cur,isP,per,bal)
            if bal
                tf = sum(isP(cur)) >= per && sum(~isP(cur)) >= per;
            else
                tf = numel(cur) >= per;
            end
        end

        % =================================================================
        %  Small helpers
        % =================================================================
        function rows = useRows(X,rows)
            % rows: [] (all), logical, or indices; X: [nT x N]. rows
            % (returned): nT x 1 logical, without any row holding a NaN.
            nT = size(X,1);
            if isempty(rows)
                rows = true(nT,1);
            elseif ~islogical(rows)
                r = false(nT,1);
                r(rows(rows >= 1 & rows <= nT)) = true;
                rows = r;
            else
                rows = reshape(rows,[],1);
                if numel(rows) ~= nT
                    error('mabr:analysis:SingleTrial:rows', ...
                        'rows has %d entries and X %d rows.',numel(rows),nT);
                end
            end
            rows = rows & all(isfinite(X),2);
        end

        function r = pearsonCols(A,B)
            % Pearson correlation of each column of A with the same column of
            % B -- corrcoef's arithmetic, one column at a time, vectorized,
            % and bounded to [-1 1] as corrcoef bounds it.
            %
            % Each centred column is scaled to unit peak first. r does not
            % depend on scale, and volts squared twice underflow: on the
            % tail of a noiseless template (1e-100 V and below) the product
            % of the two sums of squares became 0 under a nonzero numerator,
            % and xcorrUp returned r = Inf. A constant column is still NaN.
            a = A - mean(A,1);
            b = B - mean(B,1);
            a = a./max(abs(a),[],1);
            b = b./max(abs(b),[],1);
            r = sum(a.*b,1)./sqrt(sum(a.^2,1).*sum(b.^2,1));
            r = min(max(r,-1),1);
        end

        function s = streamOrDefault(s)
            % [] -> a fresh threefry stream seeded 1, so a call that was given
            % no stream is still reproducible and never touches the global rng.
            if isempty(s), s = RandStream('threefry','Seed',1); end
        end

        function pk = pickList(picks)
            % picks: [] / struct array / table with Wave, PeakLatency,
            % TroughLatency. pk (returned): struct of columns (Wave string).
            pk = struct('Wave',strings(0,1),'PeakLatency',zeros(0,1),'TroughLatency',zeros(0,1));
            if isempty(picks), return; end
            if istable(picks), picks = table2struct(picks); end
            pk.Wave = reshape(string({picks.Wave}),[],1);
            pk.PeakLatency = reshape(double([picks.PeakLatency]),[],1);
            if isfield(picks,'TroughLatency')
                pk.TroughLatency = reshape(double([picks.TroughLatency]),[],1);
            else
                pk.TroughLatency = nan(numel(pk.Wave),1);
            end
        end

        function S = emptySummary(nT)
            nanCol = nan(nT,1);
            S = struct('N',0,'NPos',0,'NNeg',0,'Balanced',false, ...
                'Mean',nanCol,'MeanPos',nanCol,'MeanNeg',nanCol,'SEM',nanCol, ...
                'PlusMinus',nanCol,'RN',NaN,'RNPM',NaN,'ResponseRMS',NaN, ...
                'BaselineRMS',NaN,'F',NaN,'PowerP',NaN,'PowerF95',NaN, ...
                'SNR',NaN,'SNRCorr',NaN,'Fsp',NaN,'FspDF1',NaN,'FspDF2',NaN, ...
                'FspP',NaN,'SplitR',NaN,'SplitRSD',NaN,'SplitRP025',NaN, ...
                'SplitRP975',NaN,'SplitN',NaN,'Flags',strings(1,0));
        end
    end
end
