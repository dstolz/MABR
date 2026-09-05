classdef PermTest
% mabr.analysis.PermTest  Sign-flip permutation test for one ABR condition.
%
%   Asks one question about one condition: are these sweeps time-locked to
%   anything, or are they noise? The null is built by randomly flipping the
%   sign of whole sweeps (Rademacher permutation), which is the right null for
%   a one-sample test of a signal averaged across sweeps, and the family-wise
%   error over samples is controlled by a MAX-statistic null -- so the p-value
%   needs no further correction for the number of samples in the window.
%
%       [p,res] = mabr.analysis.PermTest.run(X)          % X: [nSamples x nSweeps]
%       [p,res] = mabr.analysis.PermTest.run(X, Method="tfce", NumPermutations=2000)
%
%   Three max-statistics, all two-sided:
%
%     "clusterMass" (default) -- the largest summed-t run above the t
%       threshold. Sensitive to sustained deflections; needs a threshold.
%     "tmax" -- the largest |t| anywhere. Sensitive to sharp peaks; the
%       strictest, and the only one with no free parameter.
%     "tfce" -- threshold-free cluster enhancement (Mensen & Khatami 2013),
%       which integrates extent against height and so needs no cluster
%       threshold at all. Usually the most sensitive on ABR data.
%
%   The permutations are VECTORIZED, which is the practical difference from a
%   loop: the sum of squares is invariant under a sign flip, so every permuted
%   t-map for a block of permutations is one matrix product plus arithmetic,
%   and the cluster and TFCE statistics are then computed for the whole block
%   at once by run-length arithmetic rather than sample by sample.
%
%   Seed makes a run reproducible. That matters more here than it looks: a
%   threshold is fitted to these p-values, so an unseeded test makes the
%   threshold itself jitter between re-analyses of the same data.
%
%   Requires no Statistics toolbox -- the t threshold comes from
%   mabr.metrics.t_quantile.
%
%   Mensen, A., & Khatami, R. (2013). Advanced EEG analysis using
%   threshold-free cluster-enhancement and non-parametric statistics.
%   NeuroImage, 67, 111-118.
%
%   See also mabr.analysis.Threshold, mabr.analysis.Session

    methods (Static)
        function [pVal,result] = run(X,opts)
            % Permutation test on one [nSamples x nSweeps] matrix.
            %
            %   X    [nSamples x nSweeps] double
            %   opts.Method            "clusterMass" (default), "tmax", or "tfce"
            %   opts.NumPermutations   number of sign-flip permutations (default 1000)
            %   opts.Alpha             two-sided per-sample alpha (default 0.05)
            %   opts.MinClusterSize    minimum run length counted as a cluster (default 1)
            %   opts.TFCE              struct('E',.,'H',.,'dh',.) TFCE parameters
            %   opts.Seed              [] (default, uses global rng) or an integer seed
            %   opts.BlockSize         permutations generated per batch (default 512)
            %   pVal    (returned) global p-value for the chosen max-statistic
            %   result  (returned) struct: .method .t .tThresh .statistic (observed max),
            %           .null (nPerm x 1), .pSample (FWER-corrected per sample,
            %           for every method), .sigMask, .nSweeps, .clusters
            arguments
                X double
                opts.Method (1,1) string {mustBeMember(opts.Method,["clusterMass","tmax","tfce"])} = "clusterMass"
                opts.NumPermutations (1,1) double {mustBeInteger,mustBePositive} = 1000
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1)} = 0.05
                opts.MinClusterSize (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.TFCE struct = struct('E',0.5,'H',2.0,'dh',0.1)
                opts.Seed = []
                opts.BlockSize (1,1) double {mustBeInteger,mustBePositive} = 512
            end

            nPerm = opts.NumPermutations;
            result = struct('method',opts.Method,'t',[],'tThresh',NaN, ...
                'statistic',NaN,'null',[],'pSample',[],'sigMask',[], ...
                'nSweeps',0,'nSamples',0,'alpha',opts.Alpha,'clusters',struct([]));
            pVal = NaN;

            if isempty(X), return; end
            [nSamples,nSweeps] = size(X);
            result.nSweeps  = nSweeps;
            result.nSamples = nSamples;
            if nSweeps < 2 || nSamples < 1, return; end

            X = double(X);

            % --- observed t map (analytic one-sample t across sweeps) -------
            n      = nSweeps;
            sumX   = sum(X,2);
            sumSq  = sum(X.^2,2);
            tReal  = mabr.analysis.PermTest.tFromSums(sumX,sumSq,n).';   % 1 x nSamples

            tThresh = mabr.metrics.t_quantile(1-opts.Alpha/2, n-1);
            result.t = tReal;
            result.tThresh = tThresh;

            % --- observed max-statistic -------------------------------------
            switch opts.Method
                case "clusterMass"
                    statReal = mabr.analysis.PermTest.maxClusterMass(tReal,tThresh,opts.MinClusterSize);
                    perSample = abs(tReal);   % only used for the reported map
                case "tmax"
                    perSample = abs(tReal);
                    statReal  = max(perSample);
                case "tfce"
                    perSample = mabr.analysis.PermTest.tfce(tReal,opts.TFCE,opts.MinClusterSize);
                    statReal  = max(perSample);
            end
            result.statistic = statReal;

            % --- permutation null -------------------------------------------
            if isempty(opts.Seed)
                stream = [];
            else
                stream = RandStream('threefry','Seed',opts.Seed);
            end

            null = zeros(nPerm,1);
            done = 0;
            while done < nPerm
                nb = min(opts.BlockSize, nPerm - done);

                if isempty(stream)
                    flips = 2*(rand(nSweeps,nb) > 0.5) - 1;
                else
                    flips = 2*(rand(stream,nSweeps,nb) > 0.5) - 1;
                end

                % Sign flips leave sum(X.^2) untouched, so only the sum moves.
                sumP = (X*flips);                                  % nSamples x nb
                Tb   = mabr.analysis.PermTest.tFromSums(sumP,sumSq,n).';   % nb x nSamples

                switch opts.Method
                    case "clusterMass"
                        null(done+(1:nb)) = mabr.analysis.PermTest.maxClusterMass(Tb,tThresh,opts.MinClusterSize);
                    case "tmax"
                        null(done+(1:nb)) = max(abs(Tb),[],2);
                    case "tfce"
                        null(done+(1:nb)) = max(mabr.analysis.PermTest.tfce(Tb,opts.TFCE,opts.MinClusterSize),[],2);
                end
                done = done + nb;
            end
            result.null = null;

            % Global p with the +1 correction, so a p of exactly zero -- which
            % no finite number of permutations can justify -- cannot occur.
            pVal = (1 + sum(null >= statReal)) / (nPerm + 1);

            % --- per-sample FWER-corrected p, for every method ---------------
            result.pSample = mabr.analysis.PermTest.fwerP(perSample,null);
            result.sigMask = result.pSample < opts.Alpha;

            % --- cluster inventory (clusterMass only) ------------------------
            if opts.Method == "clusterMass"
                result.clusters = mabr.analysis.PermTest.clusterTable(tReal,tThresh, ...
                    opts.MinClusterSize,null);
            end
        end

        function t = tFromSums(sumX,sumSq,n)
            % One-sample t from sufficient statistics, columnwise.
            %
            % Written this way because a sign flip changes sumX and leaves
            % sumSq alone -- which is what makes a whole block of permuted
            % t-maps one matrix product rather than a loop.
            %
            %   sumX, sumSq  same-shape arrays, sum(X,dim) and sum(X.^2,dim)
            %                (columns are the permutations/rows are samples,
            %                whichever orientation the caller used)
            %   n            number of sweeps summed over (scalar)
            %   t            (returned) t-statistic, same shape as sumX
            v  = (sumSq - (sumX.^2)/n) ./ (n-1);
            se = sqrt(v./n);
            t  = (sumX./n) ./ se;
            t(~isfinite(t)) = 0;
        end

        function m = maxClusterMass(T,thr,minSz)
            % Largest absolute cluster mass per row of T [nRows x nSamples].
            %
            % Vectorized over rows: run boundaries come from one DIFF, and each
            % run's mass from the difference of a running sum at its ends.
            %
            %   T      [nRows x nSamples] double (t-maps, one row per permutation)
            %   thr    t threshold, scalar
            %   minSz  minimum run length counted as a cluster (default 1)
            %   m      (returned) [nRows x 1] double, largest |cluster mass| per row
            arguments
                T double
                thr (1,1) double
                minSz (1,1) double = 1
            end
            m = max(mabr.analysis.PermTest.maxPositiveMass(T,thr,minSz), ...
                    mabr.analysis.PermTest.maxPositiveMass(-T,thr,minSz));
        end

        function A = tfce(T,par,minSz)
            % Threshold-free cluster enhancement of |T|, two-sided, per row.
            %
            % Returns a map the same size as T: for each threshold step h, every
            % sample inside a supra-h run gains extent^E * h^H * dh. The
            % accumulation is done with a difference array so a run is two
            % writes rather than a loop over its samples.
            %
            %   T      [nRows x nSamples] double (t-maps)
            %   par    struct('E',.,'H',.,'dh',.) TFCE parameters (defaults 0.5,2.0,0.1)
            %   minSz  minimum run length counted (default 1)
            %   A      (returned) [nRows x nSamples] double, TFCE-enhanced map
            arguments
                T double
                par struct = struct('E',0.5,'H',2.0,'dh',0.1)
                minSz (1,1) double = 1
            end
            E  = mabr.analysis.PermTest.getdef(par,'E',0.5);
            H  = mabr.analysis.PermTest.getdef(par,'H',2.0);
            dh = mabr.analysis.PermTest.getdef(par,'dh',0.1);

            A = mabr.analysis.PermTest.tfceOneSided(max(T,0),E,H,dh,minSz);
            B = mabr.analysis.PermTest.tfceOneSided(max(-T,0),E,H,dh,minSz);
            A = max(A,B);
        end

        function p = fwerP(stat,null)
            % FWER-corrected p per sample against a max-statistic null.
            %
            %   stat  observed per-sample statistic, any shape
            %   null  [nPerm x 1] max-statistic null distribution
            %   p     (returned) FWER-corrected p-value, same shape as stat
            nPerm = numel(null);
            p = zeros(size(stat));
            chunk = 2000;
            for i0 = 1:chunk:numel(stat)
                i1 = min(numel(stat), i0+chunk-1);
                p(i0:i1) = (1 + sum(null(:) >= reshape(stat(i0:i1),1,[]),1)) / (nPerm+1);
            end
        end

        function ax = plot(result,ax)
            % The two pictures worth seeing: the t map against its threshold,
            % and where the observed statistic falls in the permutation null.
            %
            %   result  struct returned by run()
            %   ax      1x2 array of axes to draw into (default: a new figure)
            %   ax      (returned) the same 1x2 array of axes
            arguments
                result struct
                ax = []
            end
            if isempty(ax)
                fig = figure('Name','Permutation test','Color','w');
                tl  = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
                % gobjects first: the default [] is a double array, and
                % assigning an axes into it silently converts the handle to a
                % number, after which line() reads it as a coordinate.
                ax  = gobjects(1,2);
                ax(1) = nexttile(tl); ax(2) = nexttile(tl);
            end

            line(ax(1),1:numel(result.t),result.t,'Color',[0 0.35 0.7]);
            yline(ax(1),0,'-k');
            yline(ax(1), result.tThresh,'--','Color',[0.6 0.6 0.6]);
            yline(ax(1),-result.tThresh,'--','Color',[0.6 0.6 0.6]);
            if any(result.sigMask)
                hold(ax(1),'on');
                idx = find(result.sigMask);
                plot(ax(1),idx,result.t(idx),'.','Color',[0.8 0.2 0.2],'MarkerSize',8);
                hold(ax(1),'off');
            end
            grid(ax(1),'on'); box(ax(1),'on');
            xlabel(ax(1),'Sample'); ylabel(ax(1),'t');
            title(ax(1),sprintf('%s',result.method));

            nz = result.null(result.null > 0);
            if ~isempty(nz)
                histogram(ax(2),nz,min(100,max(10,round(numel(nz)/20))), ...
                    'Normalization','pdf','EdgeColor','none','FaceColor',[0.5 0.55 0.6]);
            end
            xline(ax(2),result.statistic,'-r','observed','LineWidth',2);
            grid(ax(2),'on'); box(ax(2),'on');
            xlabel(ax(2),'Max statistic'); ylabel(ax(2),'pdf');
            title(ax(2),'Permutation null');

            mabr.analysis.Plot.plainAxes(ax);
        end
    end

    methods (Static, Access = private)
        function m = maxPositiveMass(T,thr,minSz)
            % Largest positive supra-threshold run mass per row.
            %
            %   T      [nRows x nSamples] double
            %   thr    threshold, scalar
            %   minSz  minimum run length counted
            %   m      (returned) [nRows x 1] double
            [nr,ns] = size(T);
            m = zeros(nr,1);

            mask = T > thr;
            if ~any(mask(:)), return; end

            % Running sum of the supra-threshold values, with a leading zero so
            % a run's mass is one subtraction.
            C = [zeros(nr,1) cumsum(T.*mask,2)];        % nr x (ns+1)

            d = diff([false(nr,1) mask false(nr,1)],1,2);   % nr x (ns+1)
            [rs,cs] = find(d ==  1);
            [re,ce] = find(d == -1);

            % find() walks column-major; sort both by (row,column) so the k-th
            % start and the k-th end belong to the same run.
            [~,i] = sortrows([rs cs]); rs = rs(i); cs = cs(i);
            [~,i] = sortrows([re ce]); ce = ce(i);

            len  = ce - cs;                                  % samples in the run
            mass = C(sub2ind([nr ns+1],rs,ce)) - C(sub2ind([nr ns+1],rs,cs));

            keep = len >= minSz;
            if ~any(keep), return; end
            m = accumarray(rs(keep),mass(keep),[nr 1],@max,0);
        end

        function A = tfceOneSided(X,E,H,dh,minSz)
            % TFCE of a non-negative map, per row.
            %
            %   X      [nRows x nSamples] double, non-negative
            %   E,H    TFCE extent/height exponents
            %   dh     threshold step size
            %   minSz  minimum run length counted
            %   A      (returned) [nRows x nSamples] double
            [nr,ns] = size(X);
            A = zeros(nr,ns);
            mx = max(X(:));
            if mx <= 0 || dh <= 0, return; end

            for h = dh:dh:mx
                mask = X > h;
                if ~any(mask(:)), continue; end

                d = diff([false(nr,1) mask false(nr,1)],1,2);
                [rs,cs] = find(d ==  1);
                [re,ce] = find(d == -1);
                [~,i] = sortrows([rs cs]); rs = rs(i); cs = cs(i);
                [~,i] = sortrows([re ce]); ce = ce(i);

                len  = ce - cs;
                keep = len >= minSz;
                if ~any(keep), continue; end
                rs = rs(keep); cs = cs(keep); ce = ce(keep); len = len(keep);

                inc = (len.^E) .* (h.^H) .* dh;

                % Difference array: add at the run's first sample, subtract one
                % past its last, then integrate along the row.
                D = zeros(nr,ns+1);
                D(sub2ind([nr ns+1],rs,cs)) = D(sub2ind([nr ns+1],rs,cs)) + inc;
                D(sub2ind([nr ns+1],rs,ce)) = D(sub2ind([nr ns+1],rs,ce)) - inc;
                Dc = cumsum(D,2);
                A = A + Dc(:,1:ns);
            end
        end

        function C = clusterTable(t,thr,minSz,null)
            % Inventory of the observed supra-threshold clusters, each with a
            % p-value read off the same max-statistic null.
            %
            %   t      1 x nSamples observed t-map
            %   thr    t threshold, scalar
            %   minSz  minimum run length counted
            %   null   [nPerm x 1] max-statistic null distribution
            %   C      (returned) struct array, one per cluster: .sign,
            %          .first, .last (sample indices), .mass, .p
            C = struct('sign',{},'first',{},'last',{},'mass',{},'p',{});
            for s = [1 -1]
                x = s*t;
                mask = x > thr;
                d = diff([false mask false]);
                a = find(d == 1); b = find(d == -1) - 1;
                for k = 1:numel(a)
                    if (b(k)-a(k)+1) < minSz, continue; end
                    mass = sum(x(a(k):b(k)));
                    C(end+1) = struct('sign',s,'first',a(k),'last',b(k), ...
                        'mass',s*mass, ...
                        'p',(1+sum(null >= mass))/(numel(null)+1)); %#ok<AGROW>
                end
            end
        end

        function v = getdef(s,f,d)
            % s: struct or []; f: field name; d: default. v: (returned)
            % s.(f) when present and non-empty, else d.
            if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end
    end
end
