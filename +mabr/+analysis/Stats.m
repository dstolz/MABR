classdef Stats
% mabr.analysis.Stats  Statistics, hashing, keys and sorting, with no toolbox.
%
%   The offline analysis needs a handful of things the Statistics and
%   Machine Learning Toolbox would otherwise supply -- percentiles, the F and
%   t distributions, a normal quantile -- and mabr.Config.RequiredToolboxes
%   deliberately does not list that toolbox. Every one of them is here, built
%   on core MATLAB (betainc, erfcinv, sort), so a static scan of the analysis
%   code can insist that no Statistics function is ever called:
%
%       q   = mabr.analysis.Stats.percentile(x,[0.025 0.975]);
%       p   = mabr.analysis.Stats.fsf(F,df1,df2);        % upper tail of F
%       rs  = mabr.analysis.Stats.conditionStream(seed,key);
%       key = "Frequency=" + mabr.analysis.Stats.keyValue(8);
%
%   Four other families live here because more than one class needs exactly
%   the same answer, and two copies of a rule drift:
%
%     HASHING (fnv1a32, hex8). A stable 32-bit FNV-1a over the UTF-8 bytes of
%     a text: the same on every machine and every MATLAB, which is what makes
%     it usable in file names and fingerprints. Not cryptographic.
%
%     SEEDS (conditionSeed, conditionStream). A randomized statistic never
%     draws from the global stream: each condition gets a threefry stream
%     seeded from the analysis seed plus the hash of the condition's KEY. So
%     recomputing a subset of conditions is bit-identical to recomputing all
%     of them, and two conditions with the same number of sweeps still get
%     different permutations.
%
%     KEYS (keyValue). Conditions, series and files are identified by text
%     keys, "Name=Value" pairs joined by "|", never by row numbers. keyValue
%     is the one place a value becomes key text, so 8, 8.000000001 and a
%     value read back from a file all spell "8".
%
%     ORDER (naturalSort, isoTime). Subjects sort as a person reads them
%     (SUBJ-ID-959 before SUBJ-ID-1254), and a time becomes text one way.
%
%   balancedMean is the polarity-balanced average and its standard error,
%   kept here so that mabr.analysis.Session and mabr.analysis.SingleTrial
%   share ONE implementation of the number every threshold rests on.
%
%   Nothing here prints, plots, or touches a preference.
%
%   See also mabr.analysis.AbrFile, mabr.analysis.Threshold,
%   mabr.metrics.t_quantile, betainc, erfcinv.
%
% Daniel Stolzberg (c) 2026

    methods (Static)
        % =================================================================
        %  Percentiles and spread
        % =================================================================
        function q = percentile(x,p)
            % Linear-interpolation percentile of the finite values of x.
            %
            %   q = percentile(x,p)
            %
            %   x  numeric vector (any shape); NaN and +-Inf are dropped
            %   p  probabilities in [0 1], any shape; NaN gives NaN
            %   q  (returned) same shape as p; NaN where x has no finite value
            %
            %   The rule is mabr.analysis.Threshold.percentile's: sort the n
            %   finite values, take position p*n + 0.5 clamped to [1 n], and
            %   interpolate linearly between its neighbours -- with interp1's
            %   own arithmetic, so the two agree to the last bit wherever both
            %   are defined. Unlike that function it also answers for a single
            %   value (interp1 refuses one point) and for an empty x.
            arguments
                x {mustBeNumericOrLogical}
                p {mustBeNumeric}
            end
            Q = mabr.analysis.Stats.percentileCols(reshape(x,[],1),p);
            q = reshape(Q,size(p));
        end

        function Q = percentileCols(X,p)
            % percentile() of every column of a matrix at once.
            %
            %   Q = percentileCols(X,p)
            %
            %   X  [n x m] numeric; each column on its own, its NaN and +-Inf
            %      dropped
            %   p  probabilities in [0 1], any shape (used as p(:))
            %   Q  (returned) [numel(p) x m]; a column with no finite value is
            %      all NaN
            %
            %   Vectorized, because a bootstrap band asks for the percentiles
            %   of a few hundred columns at a time.
            arguments
                X {mustBeNumericOrLogical}
                p {mustBeNumeric}
            end
            if ~ismatrix(X)
                error('mabr:analysis:Stats:notMatrix', ...
                    'percentileCols takes an [n x m] matrix; got %d dimensions.',ndims(X));
            end
            X = double(X);
            p = double(p(:));
            [n,m] = size(X);
            Q = nan(numel(p),m);
            if n == 0 || m == 0 || isempty(p), return; end

            X(~isfinite(X)) = NaN;
            Xs  = sort(X,1);                     % NaN last in every column
            cnt = sum(~isnan(Xs),1);             % finite values per column
            c   = max(cnt,1);                    % keeps an empty column indexable

            pos = min(max(p.*cnt + 0.5,1),c);    % [numel(p) x m]
            lo  = floor(pos);
            hi  = min(lo + 1,c);
            f   = pos - lo;
            off = (0:m-1)*n;                     % column offsets, linear indexing
            % (1-f)*v0 + f*v1 is the form interp1 'linear' evaluates; the
            % algebraically equal v0 + f*(v1-v0) differs in the last bit.
            Q = (1 - f).*Xs(lo + off) + f.*Xs(hi + off);
            Q(:,cnt == 0) = NaN;
            Q(isnan(p),:) = NaN;
        end

        function v = iqr(x)
            % Interquartile range: percentile(x,0.75) - percentile(x,0.25).
            %
            %   x  numeric vector; NaN and +-Inf dropped (as percentile)
            %   v  (returned) scalar; NaN when x has no finite value
            arguments
                x {mustBeNumericOrLogical}
            end
            q = mabr.analysis.Stats.percentile(x,[0.25 0.75]);
            v = q(2) - q(1);
        end

        function v = mad(x)
            % Median absolute deviation from the median, unscaled.
            %
            %   x  numeric vector; NaN dropped
            %   v  (returned) median(abs(x - median(x))); NaN for no values
            %
            %   Unscaled on purpose: multiply by 1.4826 for a normal-consistent
            %   estimate of the SD, where a caller wants one.
            arguments
                x {mustBeNumericOrLogical}
            end
            x = double(x(:));
            x = x(~isnan(x));
            if isempty(x), v = NaN; return; end
            v = median(abs(x - median(x)));
        end

        % =================================================================
        %  Distributions
        % =================================================================
        function P = fcdf(F,d1,d2)
            % Lower tail of the F distribution, P(X <= F).
            %
            %   P = fcdf(F,d1,d2)
            %
            %   F       statistic(s); F <= 0 gives 0, F = Inf gives 1
            %   d1, d2  numerator and denominator degrees of freedom (> 0,
            %           finite); combined with F by implicit expansion
            %   P       (returned) the expanded size; NaN where an input is NaN
            %           or a df is not a positive finite number
            %
            %   betainc(d1*F/(d1*F + d2), d1/2, d2/2). For a small upper tail use
            %   fsf, which keeps the precision 1 - fcdf would lose.
            arguments
                F {mustBeNumeric}
                d1 {mustBeNumeric}
                d2 {mustBeNumeric}
            end
            [F,d1,d2,P] = expand3(F,d1,d2);
            ok = ~isnan(F) & isfinite(d1) & isfinite(d2) & d1 > 0 & d2 > 0;
            P(ok & F <= 0) = 0;
            P(ok & F == Inf) = 1;
            m = ok & F > 0 & F < Inf;
            x = d1(m).*F(m);
            r = x./(x + d2(m));
            % A finite F whose d1*F overflows would hand betainc Inf/Inf = NaN,
            % which it refuses with an error rather than a NaN; the ratio's
            % limit there is 1.
            r(x == Inf) = 1;
            P(m) = betainc(r,d1(m)/2,d2(m)/2);
        end

        function P = fsf(F,d1,d2)
            % Upper tail (survival function) of the F distribution, P(X > F).
            %
            %   P = fsf(F,d1,d2)
            %
            %   F       statistic(s); F <= 0 gives 1, F = Inf gives 0
            %   d1, d2  degrees of freedom (> 0, finite), implicit expansion
            %   P       (returned) the expanded size; NaN where an input is NaN
            %           or a df is not a positive finite number
            %
            %   betainc(d2/(d2 + d1*F), d2/2, d1/2): the upper tail computed as
            %   such, so a p-value of 1e-12 is 1e-12 and not 1 - (1 - 1e-12).
            arguments
                F {mustBeNumeric}
                d1 {mustBeNumeric}
                d2 {mustBeNumeric}
            end
            [F,d1,d2,P] = expand3(F,d1,d2);
            ok = ~isnan(F) & isfinite(d1) & isfinite(d2) & d1 > 0 & d2 > 0;
            P(ok & F <= 0) = 1;
            m = ok & F > 0;                     % F = Inf lands on betainc(0,...) = 0
            P(m) = betainc(d2(m)./(d2(m) + d1(m).*F(m)),d2(m)/2,d1(m)/2);
        end

        function P = tcdf(t,nu)
            % Student's t cumulative distribution, P(T <= t).
            %
            %   P = tcdf(t,nu)
            %
            %   t   statistic(s); +-Inf give 1 and 0
            %   nu  degrees of freedom (> 0); above 1e7, Inf included, the
            %       standard normal; combined with t by implicit expansion
            %   P   (returned) the expanded size; NaN where t is NaN or nu is
            %       not positive
            %
            %   With b = betainc(nu/(nu + t^2), nu/2, 1/2), the two-sided tail
            %   mass, P = 1 - b/2 for t >= 0 and b/2 below zero: the same exact
            %   identity mabr.metrics.t_quantile inverts.
            %
            %   betainc with a parameter in the tens of millions is not to be
            %   trusted: tcdf(2,3e7) came out 1.3e-3 too high and tcdf(2,1e17)
            %   exactly 0.5. So above nu = 1e7 -- where the t distribution is
            %   the normal to within 2e-8 -- the normal is used, the cut-off
            %   MATLAB's own tcdf makes.
            arguments
                t {mustBeNumeric}
                nu {mustBeNumeric}
            end
            t  = double(t);
            nu = double(nu);
            P  = nan(size(t + nu));             %#ok<ELARLOG> the implicit-expansion size
            t  = t + zeros(size(P));
            nu = nu + zeros(size(P));

            ok  = ~isnan(t) & ~isnan(nu) & nu > 0;
            nrm = ok & nu > 1e7;                % the limit is the normal
            fin = ok & ~nrm;
            b = betainc(nu(fin)./(nu(fin) + t(fin).^2),nu(fin)/2,0.5);
            tf = t(fin);
            Pf = b/2;
            Pf(tf >= 0) = 1 - b(tf >= 0)/2;
            P(fin) = Pf;
            P(nrm) = 0.5*erfc(-t(nrm)/sqrt(2));
        end

        function t = tquantile(p,nu)
            % Student's t inverse CDF -- mabr.metrics.t_quantile, by name here.
            %
            %   t = tquantile(p,nu)
            %
            %   p, nu  probabilities in (0,1) and degrees of freedom, implicit
            %          expansion; a degenerate input gives NaN; above nu = 1e7,
            %          Inf included, the normal quantile (zquantile)
            %   t      (returned) the quantile(s)
            %
            %   t_quantile inverts betainc and shares its large-nu failure
            %   (1.936 for p = 0.975 at nu = 3e7, against 1.960), and gives NaN
            %   at nu = Inf; above the cut-off tcdf makes, the normal is used
            %   here too, so tquantile and tcdf stay each other's inverse.
            arguments
                p {mustBeNumeric}
                nu {mustBeNumeric}
            end
            t   = mabr.metrics.t_quantile(p,nu);
            p   = double(p) + zeros(size(t));
            nu  = double(nu) + zeros(size(t));
            big = nu > 1e7 & p > 0 & p < 1;
            t(big) = mabr.analysis.Stats.zquantile(p(big));
        end

        function z = zquantile(p)
            % Standard normal quantile (inverse CDF).
            %
            %   z = zquantile(p)
            %
            %   p  probabilities, any shape; 0 and 1 give -Inf and Inf, outside
            %      [0 1] gives NaN
            %   z  (returned) same shape as p
            %
            %   sqrt(2)*erfinv(2p-1), evaluated as the equal -sqrt(2)*erfcinv(2p),
            %   which keeps its precision in the lower tail where 2p-1 rounds
            %   to -1. zquantile(0.975)^2 = 3.8415, the 95% chi-square(1) cut.
            arguments
                p {mustBeNumeric}
            end
            z = -sqrt(2)*erfcinv(2*double(p));
            z(z == 0) = 0;                      % +0 at p = 0.5: the negation leaves -0, which prints "-0"
        end

        % =================================================================
        %  Hashes, seeds, keys
        % =================================================================
        function h = fnv1a32(text)
            % 32-bit FNV-1a hash of a text's UTF-8 bytes.
            %
            %   h = fnv1a32(text)
            %
            %   text  char row or string scalar (a missing string hashes as "")
            %   h     (returned) uint32
            %
            %   Offset basis 2166136261, prime 16777619, reduced mod 2^32 after
            %   every byte. Worked in uint64 so the product (< 2^57) is exact and
            %   cannot saturate. Test vectors: "" 811c9dc5, "a" e40c292c,
            %   "foobar" bf9cf968.
            arguments
                text {mustBeTextScalar}
            end
            text = string(text);
            if ismissing(text), text = ""; end
            bytes = unicode2native(char(text),'UTF-8');
            h     = uint64(2166136261);
            prime = uint64(16777619);
            mod32 = uint64(4294967296);
            for k = 1:numel(bytes)
                h = mod(bitxor(h,uint64(bytes(k)))*prime,mod32);
            end
            h = uint32(h);
        end

        function s = hex8(text)
            % fnv1a32 as 8 lowercase hex digits.
            %
            %   s = hex8(text)
            %
            %   text  char row or string scalar
            %   s     (returned) 1x1 string, e.g. "811c9dc5" for ""
            arguments
                text {mustBeTextScalar}
            end
            s = string(sprintf('%08x',mabr.analysis.Stats.fnv1a32(text)));
        end

        function s = conditionSeed(seed,key)
            % The seed one condition's random draws start from.
            %
            %   s = conditionSeed(seed,key)
            %
            %   seed  the analysis seed, an integer (>= 0 in practice)
            %   key   the condition's key text (see keyValue)
            %   s     (returned) double integer in [0, 2^32):
            %         mod(seed + fnv1a32(key), 2^32)
            %
            %   Depends on the condition's KEY and nothing else, never on its
            %   row or on which other conditions are being computed -- which is
            %   what makes a subset recompute bit-identical to a full one.
            arguments
                seed (1,1) {mustBeNumeric,mustBeFinite,mustBeInteger}
                key {mustBeTextScalar}
            end
            s = mod(double(seed) + double(mabr.analysis.Stats.fnv1a32(key)),2^32);
        end

        function rs = conditionStream(seed,key)
            % A threefry RandStream seeded with conditionSeed(seed,key).
            %
            %   rs = conditionStream(seed,key)
            %
            %   seed, key  as conditionSeed
            %   rs         (returned) RandStream('threefry','Seed',s), private to
            %              the caller: never the global stream
            arguments
                seed (1,1) {mustBeNumeric,mustBeFinite,mustBeInteger}
                key {mustBeTextScalar}
            end
            rs = RandStream('threefry','Seed',mabr.analysis.Stats.conditionSeed(seed,key));
        end

        function s = keyValue(v)
            % The canonical key text of a value.
            %
            %   s = keyValue(v)
            %
            %   v  a number, logical, or text; an array gives an array
            %   s  (returned) string of v's size:
            %        text     itself, with "|" and "=" (the key's own
            %                 separators) replaced by "_"; missing -> ""
            %        numeric  sprintf('%.15g', round(v,6,'significant')), so
            %                 8.000000001 -> "8", 11.3 -> "11.3"; NaN -> "NaN";
            %                 -0 -> "0"
            %        logical  as the numbers 0 and 1
            %
            %   Six significant digits is far finer than any stimulus is set
            %   to and coarse enough that arithmetic noise -- a kHz value
            %   computed from Hz, a level read back from a file -- cannot give
            %   one condition two keys.
            if isstring(v) || ischar(v) || iscellstr(v)
                s = string(v);
                s(ismissing(s)) = "";
                s = replace(s,["|" "="],"_");
            elseif isnumeric(v) || islogical(v)
                r = round(double(real(v)),6,'significant');
                s = strings(size(r));
                for k = 1:numel(r)
                    s(k) = sprintf('%.15g',r(k));
                end
                s(s == "-0") = "0";
            else
                error('mabr:analysis:Stats:keyValue', ...
                    'A key value is a number, a logical or text, not a %s.',class(v));
            end
        end

        % =================================================================
        %  Order and time
        % =================================================================
        function [s,i] = naturalSort(strs)
            % Sort text the way a person reads numbers in it.
            %
            %   [s,i] = naturalSort(strs)
            %
            %   strs  string array, cellstr or char row (one text); a missing
            %         string sorts as ""
            %   s     (returned) strs reordered, same class and orientation
            %   i     (returned) the permutation: s = strs(i)
            %
            %   Each text is split into maximal runs of digits and of non-
            %   digits and compared run by run: two digit runs by their numeric
            %   value, anything else by its lower-case text; a text that runs
            %   out first comes first; ties keep their original order. So
            %   "SUBJ-ID-959" sorts before "SUBJ-ID-1254" and "a2" before "A10".
            %
            %   Done as one ordinary sort over a key per text: each run is
            %   followed by char(1), which sorts below every printable
            %   character so a shorter run comes first, and digit runs are
            %   zero-padded to a common width so text order is numeric order --
            %   for runs of any length, with no double rounding.
            if ischar(strs)
                if isempty(strs) || isrow(strs)
                    s = strs;  i = 1;
                    if isempty(strs), i = zeros(0,1); end
                    return
                end
                error('mabr:analysis:Stats:naturalSort', ...
                    'naturalSort takes one char row, a string array or a cellstr.');
            end
            if ~(isstring(strs) || iscellstr(strs))
                error('mabr:analysis:Stats:naturalSort', ...
                    'naturalSort takes text, not a %s.',class(strs));
            end
            t = string(strs(:));
            t(ismissing(t)) = "";
            n = numel(t);
            if n == 0
                s = strs;  i = zeros(size(strs));  return
            end
            runs  = regexp(cellstr(t),'\d+|\D+','match');   % n x 1, each a 1 x k cellstr
            isNum = cell(n,1);
            width = 1;
            for k = 1:n
                isNum{k} = cellfun(@(x) x(1) >= '0' && x(1) <= '9',runs{k});
                if any(isNum{k})
                    width = max(width,max(cellfun('length',runs{k}(isNum{k}))));
                end
            end
            key = strings(n,1);
            sep = char(1);
            for k = 1:n
                r = runs{k};
                for j = 1:numel(r)
                    if isNum{k}(j)
                        r{j} = [repmat('0',1,width - numel(r{j})) r{j}];
                    else
                        r{j} = lower(r{j});
                    end
                end
                key(k) = string([strjoin(r,sep) sep]);
                if isempty(r), key(k) = ""; end
            end
            [~,i] = sort(key);                  % MATLAB's sort is stable
            if isrow(strs), i = i.'; end
            s = strs(i);
        end

        function c = isoTime(dt)
            % A time as 'yyyy-MM-dd''T''HH:mm:ss' text.
            %
            %   c = isoTime(dt)
            %
            %   dt  datetime, or a datenum (so isoTime(now) works); an array
            %       gives an array
            %   c   (returned) char row for a scalar ('' for NaT), else a
            %       string array of dt's size ("" for NaT)
            %
            %   Local wall-clock time, no zone, whole seconds -- the form
            %   ABR_Data.StartTime and every results file use.
            fmt = 'yyyy-MM-dd''T''HH:mm:ss';
            if isnumeric(dt)
                d = NaT(size(dt));
                ok = isfinite(dt);
                if any(ok(:)), d(ok) = datetime(dt(ok),'ConvertFrom','datenum'); end
                dt = d;
            elseif ~isdatetime(dt)
                error('mabr:analysis:Stats:isoTime', ...
                    'isoTime takes a datetime or a datenum, not a %s.',class(dt));
            end
            if isscalar(dt)
                if isnat(dt), c = ''; else, c = char(dt,fmt); end
            else
                c = string(dt,fmt);
                c(ismissing(c)) = "";
            end
        end

        % =================================================================
        %  The polarity-balanced mean
        % =================================================================
        function [m,sem,info] = balancedMean(X,pol,strata)
            % Polarity-balanced mean of a condition's sweeps, and its SEM.
            %
            %   [m,sem,info] = balancedMean(X,pol,strata)
            %
            %   X       [nT x N] sweeps, one per column (rows outside a
            %           condition's extent may be NaN, and stay NaN)
            %   pol     1 x N stimulus polarity, +1/-1 ([] = all +1; 0 or NaN
            %           count as +1, as AbrFile reads them)
            %   strata  1 x N positive integers, the file each sweep came from
            %           ([] or a scalar = one file)
            %   m       (returned) [nT x 1] (mean(X(:,P)) + mean(X(:,Q)))/2 when
            %           both polarities are present, else mean(X)
            %   sem     (returned) [nT x 1] standard error of m
            %   info    (returned) struct: N, NPos, NNeg, G (non-empty groups),
            %           S2 ([nT x 1] pooled variance), Balanced
            %
            %   Equal weight per polarity cancels whatever follows the stimulus
            %   polarity -- the cochlear microphonic, stimulus artifact -- even
            %   when the counts differ. The variance is pooled WITHIN groups,
            %   a group being one file x one polarity (G of them):
            %       s2(t)  = sum_g sum_(k in g) (x_k(t) - m_g(t))^2 / (N - G)
            %       sem^2  = s2 * (1/n+ + 1/n-)/4      balanced
            %       sem^2  = s2 / N                    one polarity
            %   so neither the polarity-locked component nor a level shift
            %   between files is counted as noise. N == G (one sweep per
            %   group) leaves no degree of freedom: S2 and sem are NaN.
            arguments
                X {mustBeNumeric}
                pol {mustBeNumeric} = []
                strata {mustBeNumeric} = []
            end
            if ~ismatrix(X)
                error('mabr:analysis:Stats:notMatrix', ...
                    'balancedMean takes an [nT x N] matrix of sweeps.');
            end
            X = double(X);
            [nT,N] = size(X);
            pol = double(reshape(pol,1,[]));
            if isempty(pol), pol = ones(1,N); end
            strata = double(reshape(strata,1,[]));
            if isempty(strata), strata = ones(1,N); end
            if isscalar(strata), strata = repmat(strata,1,N); end
            if numel(pol) ~= N || numel(strata) ~= N
                error('mabr:analysis:Stats:size', ...
                    'X has %d sweeps but pol has %d and strata %d.',N,numel(pol),numel(strata));
            end
            if any(~isfinite(strata))
                error('mabr:analysis:Stats:strata','strata must be finite (one file index per sweep).');
            end
            pol(~(pol < 0)) = 1;                % 0 and NaN count as +1
            pol(pol < 0)    = -1;

            P  = pol > 0;   Q = pol < 0;
            nP = sum(P);    nQ = sum(Q);
            balanced = nP > 0 && nQ > 0;
            info = struct('N',N,'NPos',nP,'NNeg',nQ,'G',0,'S2',nan(nT,1),'Balanced',balanced);
            if N == 0
                m = nan(nT,1);  sem = nan(nT,1);
                return
            end

            if balanced
                m = (mean(X(:,P),2) + mean(X(:,Q),2))/2;
            else
                m = mean(X,2);
            end

            [~,~,g] = unique([strata(:) pol(:)],'rows');
            G  = max(g);
            ss = zeros(nT,1);
            for k = 1:G
                Xg = X(:,g == k);
                ss = ss + sum((Xg - mean(Xg,2)).^2,2);
            end
            S2 = ss/(N - G);                    % 0/0 = NaN when N == G
            if N == G, S2(:) = NaN; end
            if balanced
                sem = sqrt(S2*0.25*(1/nP + 1/nQ));
            else
                sem = sqrt(S2/N);
            end
            info.G  = G;
            info.S2 = S2;
        end
    end
end

% =========================================================================
function [a,b,c,out] = expand3(a,b,c)
% Three numeric inputs broadcast onto their implicit-expansion size, plus a
% NaN array of that size to fill.
a = double(a);  b = double(b);  c = double(c);
out = nan(size(a + b + c));             %#ok<ELARLOG> the implicit-expansion size
a = a + zeros(size(out));
b = b + zeros(size(out));
c = c + zeros(size(out));
end
