classdef SeriesThreshold
% mabr.analysis.SeriesThreshold  The threshold of ONE level series, by a named method.
%
%   A series is one stimulus swept in level -- one frequency of a tone grid,
%   a click series -- and its threshold is a statement about the whole series
%   made from a per-level statistic. This class is that statement, as pure
%   functions of plain vectors: Session.estimateThresholds loops over series
%   and calls estimate(); the analysis GUI, the all-methods export and the
%   tests call it directly. Nothing here reads a file, holds state or prints.
%
%       m   = mabr.analysis.SeriesThreshold.resolve("perm-descending",settings);
%       out = mabr.analysis.SeriesThreshold.estimate(levels,Y,m,MinSweeps=100);
%       mabr.analysis.SeriesThreshold.formatValue(out.Threshold,out.Censored, ...
%           out.ThrLo,out.ThrHi)                         % "35 (30–40]"
%
%   NAMED METHODS pair a per-level METRIC with a MODEL and a CRITERION
%   (methods() lists them in dropdown order):
%
%     perm-glm          permutation-test detections -> Firth logistic fit, p = 0.5
%     perm-descending   permutation-test detections -> lowest of K consecutive
%     power-descending  response power vs the ± reference (sign-flip p) -> same
%     fsp-descending    Fsp with estimated df (F p) -> same
%     presto            split-half r -> ABRpresto-like fit, r = 0.30
%     xcorr             correlation with the next-louder level >= 0.35 -> same rule
%     custom            metric, model and criterion read from the settings
%
%   A named method's criterion is FIXED (a p-method's is Alpha: the
%   settings' in resolve, and in estimate the Alpha estimate is given);
%   Settings.Criterion is read only by "custom", NaN meaning the mode's
%   default. A criterion that silently followed whichever method was picked
%   would apply a correlation of 0.75 as a probability, or the reverse, from a
%   field the dropdown does not show.
%
%   P-BASED DETECTION DECIDES; GRADED METRICS INTERPOLATE. A p-value says
%   whether there is a response at a level, not how much, so a p-metric's
%   detections (p < Alpha) are a yes/no per level and the "descending" rule
%   -- walking down from the loudest level and stopping at K consecutive
%   misses, as it is done by eye (descendingRun) -- reports the INTERVAL
%   between the highest level without and the lowest level with K
%   consecutive detections -- interval-censored data, with the
%   point inside it chosen by Convention (midpoint, the default; lowest_level;
%   crossing = midpoint for p). A graded metric (r, SNR) crosses its criterion
%   somewhere between two levels, and with Interpolate the straight-line
%   crossing is a point estimate. For random equal halves the split-half r,
%   the power F and the SNR are one quantity (r ~ (F-1)/(F+1), SNR = 10 log10
%   F), which is why the power and Fsp methods decide by p rather than by a
%   criterion on any of them.
%
%   CENSORING IS AN ANSWER. Every level detected means the threshold is at or
%   below the lowest level presented ("all-respond", LEFT-censored at it); none
%   detected means above the highest ("no-response", RIGHT-censored, Threshold
%   Inf). A model estimate more than one level step outside the levels is
%   censored the same way, and the estimate before censoring is kept in
%   ThresholdRaw. Fewer than two usable levels is "insufficient", never "no
%   response": one level cannot say where a response starts.
%
%   USABLE LEVELS. A level counts only when it has MinSweeps clean sweeps,
%   MinPerPolarity of each polarity (alternating data) and a finite value of
%   the metric; anything else is dropped with a flag rather than entered as a
%   confident miss. A human override (Y.Override) replaces the detection at a
%   level -- and makes a level usable, since a person who has looked at it has
%   decided what the statistic could not.
%
%   LEVEL DIRECTION. An attenuation axis grows quieter as it grows, so with
%   LevelDirection "descending" the series is fitted on -level and every
%   threshold, bound and interval is mapped back; lo/hi swap, and so do
%   "left" and "right", so that ThrLo/ThrHi and Censored always describe the
%   NUMBERS reported (Status keeps its meaning).
%
%   See also mabr.analysis.Threshold, mabr.analysis.Settings,
%   mabr.analysis.Session

    properties (Constant)
        % Method Ids, in dropdown order.
        Ids = ["perm-glm","perm-descending","power-descending","fsp-descending", ...
               "presto","xcorr","custom"]

        % Per-level metrics, models and criterion modes a custom method takes.
        Metrics        = ["detection","power","fsp","splithalf","xcorr","snr","strength"]
        Models         = ["descending","glm","presto","isotonic","sigmoid","minimum"]
        CriterionModes = ["p","probability","absolute","fraction"]

        % The metrics that are p-values (detected = p < Alpha).
        PMetrics = ["detection","power","fsp"]

        % Every Status estimate() can report.
        Statuses = ["ok","no-response","all-respond","insufficient","failed"]
    end

    methods (Static)
        % =================================================================
        %  Named methods
        % =================================================================
        function M = methods()
            % The named methods, one row each, in dropdown order.
            %
            %   M  (returned) [7 x 1] struct array: Id, Label, Metric, Model,
            %      CriterionMode, Criterion, CriterionUnit, NeedsMeasures.
            %      Criterion is the method's default (p-methods: the default
            %      Alpha, 0.05); the custom row shows the default settings'
            %      custom fields. resolve() applies a real Settings.
            M = [ ...
                mrow("perm-glm","Permutation test → psychometric fit (GLM, p = 0.5)", ...
                     "detection","glm","probability",0.5)
                mrow("perm-descending","Permutation test → lowest of 2 consecutive detected levels", ...
                     "detection","descending","p",0.05)
                mrow("power-descending","Response power vs ± reference (sign-flip test) → lowest of 2 consecutive", ...
                     "power","descending","p",0.05)
                mrow("fsp-descending","Fsp (multi-point F, estimated df) → lowest of 2 consecutive", ...
                     "fsp","descending","p",0.05)
                mrow("presto","Split-half correlation r ≥ 0.30 (ABRpresto-like fit)", ...
                     "splithalf","presto","absolute",0.30)
                mrow("xcorr","Correlation with next-louder level ≥ 0.35 (Suthakar & Liberman 2019)", ...
                     "xcorr","descending","absolute",0.35)
                mrow("custom","Custom…","detection","glm","probability",0.5)];
        end

        function m = resolve(id,settings)
            % The method a settings object asks for, with its numbers filled in.
            %
            %   id        method Id (methods().Id)
            %   settings  a mabr.analysis.Settings, a plain struct with the same
            %             field names, or [] (defaults); only these fields are
            %             read: Alpha, MinConsecutive, ThresholdMetric,
            %             ThresholdModel, CriterionMode, Criterion
            %   m         (returned) one row as methods() returns, resolved:
            %             p-methods take Criterion = Alpha; the label carries
            %             MinConsecutive; custom takes metric/model/mode from
            %             the settings and Criterion (NaN = the mode's default)
            %
            % Errors mabr:analysis:SeriesThreshold:badMethod for an unknown Id
            % or a custom combination that cannot be estimated (glm on a
            % graded metric, presto on a p-value, a criterion out of range).
            arguments
                id {mustBeTextScalar}
                settings = []
            end
            id = string(id);
            M  = mabr.analysis.SeriesThreshold.methods();
            k  = find([M.Id] == id,1);
            if isempty(k)
                error('mabr:analysis:SeriesThreshold:badMethod', ...
                    'Unknown threshold method "%s". Known: %s.',id, ...
                    strjoin(mabr.analysis.SeriesThreshold.Ids,', '));
            end
            m = M(k);
            alpha = double(setting(settings,'Alpha',0.05));
            K     = max(1,double(setting(settings,'MinConsecutive',2)));

            if id == "custom"
                m.Metric        = string(setting(settings,'ThresholdMetric',"detection"));
                m.Model         = string(setting(settings,'ThresholdModel',"glm"));
                m.CriterionMode = string(setting(settings,'CriterionMode',"probability"));
                c = double(setting(settings,'Criterion',NaN));
                if isempty(c) || ~isscalar(c) || isnan(c)
                    c = defaultCriterion(m.CriterionMode,m.Metric,alpha);
                end
                m.Criterion = c;
                why = combinationProblem(m.Metric,m.Model,m.CriterionMode,m.Criterion);
                if why ~= ""
                    error('mabr:analysis:SeriesThreshold:badMethod', ...
                        'Custom threshold method: %s',why);
                end
            elseif m.CriterionMode == "p"
                m.Criterion = alpha;
            end
            m.CriterionUnit = criterionUnit(m.CriterionMode,m.Metric);
            m.NeedsMeasures = needsMeasures(m.Metric);

            % "2 consecutive" in a label is literally MinConsecutive.
            if m.Model == "descending" && id ~= "custom" && K ~= 2
                if K == 1
                    m.Label = replace(m.Label,"lowest of 2 consecutive detected levels","lowest detected level");
                    m.Label = replace(m.Label,"lowest of 2 consecutive","lowest detected level");
                else
                    m.Label = replace(m.Label,"lowest of 2 consecutive", ...
                        sprintf("lowest of %d consecutive",K));
                end
            end
        end

        function s = definition(m,settings)
            % One sentence saying what the threshold IS, with the numbers in force.
            %
            %   m         a resolved method (resolve) or an Id
            %   settings  Settings object, plain struct or [] (defaults); read:
            %             Alpha, NumPermutations, DetectMethod, MinConsecutive,
            %             ThresholdConvention, Interpolate, SplitHalfMode,
            %             SplitHalfResamples, SplitHalfWindow, ResponseWindow,
            %             MaxLag
            %   s         (returned) 1x1 string, e.g. "Threshold = the midpoint
            %             between the highest level without and the lowest
            %             level with 2 consecutive detected responses
            %             (permutation test TFCE, α 0.05, 1000 permutations)."
            arguments
                m
                settings = []
            end
            if ischar(m) || isstring(m)
                m = mabr.analysis.SeriesThreshold.resolve(m,settings);
            end
            K      = max(1,double(setting(settings,'MinConsecutive',2)));
            conv   = string(setting(settings,'ThresholdConvention',"midpoint"));
            interp = logical(setting(settings,'Interpolate',true));
            crit   = criterionText(m);

            % The descending rule walks down from the loudest level and stops
            % at K consecutive misses (descendingRun); the sentence says so.
            if K == 1, walk = "descending from the loudest level to the first miss";
            else, walk = sprintf("descending from the loudest level to the first %d consecutive misses",K); end
            switch m.Model
                case "descending"
                    if ismember(m.Metric,mabr.analysis.SeriesThreshold.PMetrics)
                        ev = pEvidence(m.Metric,settings,false);
                        if K == 1, run = "a detected response";
                        else, run = sprintf("%d consecutive detected responses",K); end
                        if conv == "lowest_level"
                            s = sprintf("Threshold = the lowest level with %s, %s (%s).",run,walk,ev);
                        else
                            s = sprintf(['Threshold = the midpoint between the highest level ' ...
                                'without and the lowest level with %s, %s (%s).'],run,walk,ev);
                        end
                    else
                        q = gradedQuantity(m.Metric,settings);
                        if K == 1, run = "level"; else, run = sprintf("run of %d consecutive levels",K); end
                        if interp
                            s = sprintf(['Threshold = level where %s reaches %s, interpolated ' ...
                                'between the bracketing levels of the lowest %s at or above it, %s.'], ...
                                q,crit,run,walk);
                        elseif conv == "lowest_level"
                            s = sprintf('Threshold = the lowest level of the lowest %s where %s is at least %s, %s.', ...
                                run,q,crit,walk);
                        else
                            s = sprintf(['Threshold = the midpoint between the highest level below ' ...
                                'and the lowest level of the lowest %s where %s is at least %s, %s.'], ...
                                run,q,crit,walk);
                        end
                    end
                case "glm"
                    s = sprintf(['Threshold = level where the probability of a detected response ' ...
                        '(%s) reaches %s (Firth logistic fit; profile CI; advisory).'], ...
                        pEvidence(m.Metric,settings,true),crit);
                case "presto"
                    s = sprintf('Threshold = level where %s reaches %s (sigmoid or power-law fit).', ...
                        gradedQuantity(m.Metric,settings),crit);
                otherwise
                    if ismember(m.Metric,mabr.analysis.SeriesThreshold.PMetrics)
                        if m.Model == "minimum", what = "the detections";
                        else, what = "the permutation statistic"; end
                    else
                        what = gradedQuantity(m.Metric,settings);
                    end
                    if K == 1, gate = "any level";
                    else, gate = sprintf("%d consecutive levels",K); end
                    s = sprintf(['Threshold = level where the %s fit of %s reaches %s of its ' ...
                        'observed range (legacy fraction criterion), fitted only when the ' ...
                        'permutation test detects a response at %s.'],m.Model,what,crit,gate);
            end
            s = string(s);
        end

        % =================================================================
        %  One series
        % =================================================================
        function out = estimate(levels,Y,m,opts)
            % Threshold of one level series by one method.
            %
            %   levels  [n x 1] level of each condition of the series, any order
            %   Y       struct of [n x 1] columns, one value per level (a
            %           missing field is NaN; a missing count is "unknown",
            %           which never makes a level unusable):
            %             P         permutation-test p (detect)
            %             IsSig     permutation verdict (legacy gate)
            %             Strength  permutation statistic
            %             PowerP    power-test p          FspP   Fsp p
            %             SplitR    split-half r          SplitRSD  its SD
            %             XCorrUp   r with the next-louder level
            %             SNR       dB                    NClean NPos NNeg
            %             Override  NaN none, 1 response, 0 no response
            %             ZeroVariance  true where the sweeps hold no
            %                       noise (a dead channel): the level's
            %                       metric is NaN, and its flag says why
            %   m       a method from resolve(), or an Id
            %   opts    Alpha (0.05), MinConsecutive (2), Convention
            %           ("midpoint"), Interpolate (true), MinSweeps (100),
            %           MinPerPolarity (40), Alternating (true), Extrapolate
            %           (true), NearestLevel (false), CIAlpha (0.05),
            %           CINumSamples (2000), Seed (1), LevelDirection
            %           ("ascending"; "descending" for an attenuation axis;
            %           "auto" is read as "ascending" here, since a series
            %           has no parameter name to judge by -- Session
            %           resolves it), FlagWideCI (0.35), FlagNonMonotoneTol
            %           (0), LegacyFitTarget ("auto"), LegacyWeights ([] =
            %           ones), YBoot ([n x B] replicate metric values for a
            %           bootstrap CI of a graded threshold; [] = none),
            %           NumPermutations (NaN; the permutations behind a
            %           permutation p: a level whose p is within twice its
            %           Monte-Carlo error of the cut is flagged "borderline
            %           detection at L dB (p ...)")
            %
            %   out  (returned) struct: Threshold, ThresholdRaw, Status,
            %        Censored, ThrLo, ThrHi, CILower, CIUpper, CIMethod, Type,
            %        FitTarget, Criterion, CriterionUnit, Convention,
            %        NumLevels, NumUsable, NumSig, LevelStep, MinLevel,
            %        MaxLevel, Converged, Message, Flags (string row),
            %        Detected, DetectedAuto, Usable (logical per INPUT level),
            %        Fit (plain struct; its Predict handle is in memory only)
            arguments
                levels (:,1) double
                Y (1,1) struct = struct()
                m = "perm-glm"
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1)} = 0.05
                opts.MinConsecutive (1,1) double {mustBeInteger,mustBeNonnegative} = 2
                opts.Convention (1,1) string {mustBeMember(opts.Convention,["midpoint","lowest_level","crossing"])} = "midpoint"
                opts.Interpolate (1,1) logical = true
                opts.MinSweeps (1,1) double {mustBeNonnegative} = 100
                opts.MinPerPolarity (1,1) double {mustBeNonnegative} = 40
                opts.Alternating (1,1) logical = true
                opts.Extrapolate (1,1) logical = true
                opts.NearestLevel (1,1) logical = false
                opts.CIAlpha (1,1) double {mustBeInRange(opts.CIAlpha,0,1,"exclusive")} = 0.05
                opts.CINumSamples (1,1) double {mustBeInteger,mustBePositive} = 2000
                opts.Seed = 1
                opts.LevelDirection (1,1) string {mustBeMember(opts.LevelDirection,["ascending","descending","auto"])} = "ascending"
                opts.FlagWideCI (1,1) double = 0.35
                opts.FlagNonMonotoneTol (1,1) double = 0
                opts.LegacyFitTarget (1,1) string {mustBeMember(opts.LegacyFitTarget,["auto","binary","p","strength"])} = "auto"
                opts.LegacyWeights (:,1) double = []
                opts.YBoot double = []
                opts.NumPermutations (1,1) double = NaN
            end
            if ischar(m) || isstring(m)
                m = mabr.analysis.SeriesThreshold.resolve(m, ...
                    struct('Alpha',opts.Alpha,'MinConsecutive',opts.MinConsecutive));
            end
            m   = checkMethod(m);
            % A named p-method's criterion IS Alpha (methods() table), and
            % the Alpha this call is given decides: a method resolved under
            % other settings -- or under none, for its custom fields -- must
            % not detect at a level the call did not ask for. A custom
            % method in mode "p" keeps the criterion it was resolved with.
            if m.CriterionMode == "p" && m.Id ~= "custom"
                m.Criterion = opts.Alpha;
            end
            n   = numel(levels);
            Y   = normalizeY(Y,n);
            K   = max(1,opts.MinConsecutive);
            sgn = 1;
            if opts.LevelDirection == "descending", sgn = -1; end
            isP = ismember(m.Metric,mabr.analysis.SeriesThreshold.PMetrics);
            val = metricColumn(Y,m.Metric);
            lw  = opts.LegacyWeights;
            if isempty(lw), lw = ones(n,1); end
            if numel(lw) ~= n
                error('mabr:analysis:SeriesThreshold:badInput', ...
                    'LegacyWeights has %d values for %d levels.',numel(lw),n);
            end
            flags = strings(1,0);

            % ---- 2. usable levels ---------------------------------------
            finLev = isfinite(levels);
            okN    = ~(Y.NClean < opts.MinSweeps);
            okPol  = ~opts.Alternating | ~(min(Y.NPos,Y.NNeg) < opts.MinPerPolarity);
            okVal  = isfinite(val);
            hasOv  = ~isnan(Y.Override);
            % The next-louder correlation has nothing to correlate the
            % loudest level with: NaN there is the method, not a defect.
            exempt = false(n,1);
            if m.Metric == "xcorr" && any(finLev)
                exempt = finLev & ~okVal & levels == max(levels(finLev));
            end
            usable = (finLev & okN & okPol & okVal) | (finLev & hasOv);
            % Said in the words the settings dialog uses ("Fewest clean
            % sweeps per level"), with the numbers: a flag is read by people.
            for i = find(finLev & ~usable).'
                if exempt(i), continue; end
                if ~okN(i)
                    why = sprintf("%s clean sweeps, fewer than the minimum of %s", ...
                        fmtNum(Y.NClean(i)),fmtNum(opts.MinSweeps));
                elseif ~okPol(i)
                    why = sprintf("%s clean sweeps of one polarity, fewer than the minimum of %s", ...
                        fmtNum(min(Y.NPos(i),Y.NNeg(i))),fmtNum(opts.MinPerPolarity));
                elseif Y.ZeroVariance(i) == 1
                    why = "zero variance (the clean sweeps do not vary)";
                else
                    why = "the metric is undefined";
                end
                flags(end+1) = sprintf("level ignored at %s dB: %s",fmtNum(levels(i)),why); %#ok<AGROW>
            end
            if any(~finLev), flags(end+1) = "level ignored: level value missing"; end

            u = find(usable);
            [L,o] = sort(sgn*levels(u));
            u  = u(o);
            nU = numel(u);
            yv = val(u);

            % ---- 4. detections ------------------------------------------
            [D,critUsed] = detections(yv,m,opts.Alpha);
            DAuto = D;
            ov = Y.Override(u);
            for i = find(~isnan(ov)).'
                D(i) = ov(i) ~= 0;
                flags(end+1) = sprintf("detection overridden at %s dB",fmtNum(sgn*L(i))); %#ok<AGROW>
            end
            % Borderline detections. A permutation p is a Monte-Carlo
            % estimate, with standard error sqrt(a(1-a)/B) at the cut a: with
            % 1000 permutations a level at p 0.043 is a detection that the
            % next seed may not make, and one such level can move a series'
            % threshold by a level step. Flagged (the levels and their p), so
            % the curator knows which detections to look at; nothing changes.
            if isP && m.Metric ~= "fsp" && isfinite(opts.NumPermutations) && opts.NumPermutations >= 1
                cut = opts.Alpha;
                if m.CriterionMode == "p" && isfinite(m.Criterion), cut = m.Criterion; end
                tolB = 2*sqrt(cut*(1 - cut)/opts.NumPermutations);
                bl = find(abs(yv - cut) < tolB & isnan(Y.Override(u)));
                if ~isempty(bl)
                    [lvB,ob] = sort(levels(u(bl)));
                    pB = yv(bl(ob));
                    flags(end+1) = sprintf("borderline detection at %s dB (p %s within Monte-Carlo error of %s)", ...
                        strjoin(compose("%g",lvB.'),", "),strjoin(compose("%.3f",pB.'),", "), ...
                        string(sprintf('%g',cut)));
                end
            end

            % The permutation verdicts the legacy models are gated on.
            ps = Y.IsSig(u);
            Dperm = ~isnan(ps) & ps ~= 0;
            Dperm(isnan(ps)) = Y.P(u(isnan(ps))) < opts.Alpha;
            Dperm(~isnan(ov)) = ov(~isnan(ov)) ~= 0;

            [step,minLev,maxLev] = levelRange(levels(u),levels(finLev));

            % ---- 3./5.-10. the model ------------------------------------
            ex = struct('P',Y.P(u),'Strength',Y.Strength(u),'SD',Y.SplitRSD(u),'LW',lw(u));
            if nU < 2
                R = newResult(m.Model);
                R.FitTarget = fitTargetOf(m,isP);
                flags(end+1) = "insufficient levels";
                if nU == 1
                    flags(end+1) = "only one usable level";
                end
                if nU == 1 && D(1)
                    R = setLeft(R,L(1));
                    R.Status  = "all-respond";
                    R.Message = "One usable level, and it was detected.";
                else
                    R.Status  = "insufficient";
                    R.Message = "Fewer than two usable levels.";
                end
                R.ThresholdRaw = R.Threshold;
            else
                R = fitSeries(L,yv,D,Dperm,ex,m,opts,K,step);
                R.ThresholdRaw = R.Threshold;
                R = censorResult(R,L,D,step);

                % ---- 9. bootstrap interval of a graded threshold -------
                if ~isempty(opts.YBoot) && ~isP && any(R.Censored == ["none","interval"])
                    R = bootstrapCI(R,opts.YBoot,u,L,ov,Dperm,ex,m,opts,K,step,n);
                end
            end
            flags = [flags R.Flags];

            % ---- 11. flags ----------------------------------------------
            if nU >= 1
                f1 = find(D,1);
                if ~isempty(f1) && sum(~D(f1+1:end)) > opts.FlagNonMonotoneTol
                    flags(end+1) = "non-monotone";
                end
                if ~any(D), flags(end+1) = "no detected level"; end
            end
            if nU >= 2 && all(isfinite(R.CI)) && L(end) > L(1) && ...
                    diff(R.CI)/(L(end)-L(1)) > opts.FlagWideCI
                flags(end+1) = "wide CI";
            end
            if nU >= 1 && isfinite(R.Threshold) && (R.Threshold < L(1) || R.Threshold > L(end))
                flags(end+1) = "extrapolated";
            end
            if any(finLev & Y.NClean < opts.MinSweeps), flags(end+1) = "low sweeps"; end
            if any(finLev & ~okVal & ~exempt), flags(end+1) = "metric undefined at some level"; end
            if R.Fitted && ~sameFamily(m.Model,R.Type), flags(end+1) = "fallback model used"; end
            if R.Fitted && ~R.Converged, flags(end+1) = "not converged"; end
            flags = unique(flags,'stable');

            % ---- back to the levels' own direction ----------------------
            predX = R.Predict;
            if sgn < 0
                R = mirrorResult(R);
            end
            sc = R.Scale;
            if isequal(sc,[0 1])
                predict = @(xx) predX(sgn*double(xx(:)));
            else
                predict = @(xx) sc(1) + (sc(2)-sc(1))*predX(sgn*double(xx(:)));
            end

            Detected = false(n,1);     Detected(u) = D;
            DetectedA = false(n,1);    DetectedA(u) = DAuto;

            % The saved series in the levels' own ascending order (u is in
            % fitting order, which an attenuation axis reverses).
            [Xo,io] = sort(levels(u));
            Yo = yv(io);
            Do = D(io);
            if isfinite(step) && isfinite(minLev)
                curveX = linspace(minLev-step,maxLev+step,101).';
                curveY = predict(curveX);
            else
                curveX = zeros(0,1); curveY = zeros(0,1);
            end
            critMode = m.CriterionMode;

            Fit = struct('Type',R.Type,'Criterion',critUsed,'CriterionMode',critMode, ...
                'X',Xo,'Y',Yo,'D',Do,'AllX',levels,'AllY',val,'Usable',usable, ...
                'Model',R.Model,'Scale',R.Scale,'CurveX',curveX,'CurveY',curveY, ...
                'Threshold',R.ThresholdRaw,'CI',R.CI,'Message',R.Message, ...
                'FitTarget',R.FitTarget,'Converged',R.Converged, ...
                'Metric',m.Metric,'Method',m.Id, ...
                'LevelDirection',string(ifelse(sgn < 0,"descending","ascending")), ...
                'Predict',predict);

            out = struct();
            out.Threshold     = R.Threshold;
            out.ThresholdRaw  = R.ThresholdRaw;
            out.Status        = R.Status;
            out.Censored      = R.Censored;
            out.ThrLo         = R.ThrLo;
            out.ThrHi         = R.ThrHi;
            out.CILower       = R.CI(1);
            out.CIUpper       = R.CI(2);
            out.CIMethod      = R.CIMethod;
            out.Type          = R.Type;
            out.FitTarget     = R.FitTarget;
            out.Criterion     = critUsed;
            out.CriterionUnit = m.CriterionUnit;
            out.Convention    = opts.Convention;
            out.NumLevels     = n;
            out.NumUsable     = nU;
            out.NumSig        = sum(D);
            out.LevelStep     = step;
            out.MinLevel      = minLev;
            out.MaxLevel      = maxLev;
            out.Converged     = R.Converged;
            out.Message       = R.Message;
            out.Flags         = flags;
            out.Detected      = Detected;
            out.DetectedAuto  = DetectedA;
            out.Usable        = usable;
            out.Fit           = Fit;
        end

        function [k,short,lo] = descendingRun(D,K)
            % The run of detections the descending rule reads, from the top down.
            %
            % As the rule is done by eye: start at the loudest level and walk
            % down while the response continues, and stop at the first K
            % consecutive levels without one (K = 1: the first miss). Of the
            % levels above that stop, the threshold run is the lowest run of K
            % consecutive detections (firstRun). Detections below the stop
            % are disconnected from the response at the top and only raise
            % the "isolated detection below threshold" flag: scanning up from
            % the softest level instead took the first run met there, which
            % for a series with no response at all can be a run of noise --
            % 18 dB for a 32 kHz series every other method calls no response.
            %
            %   D      logical vector over ascending levels
            %   K      run length (MinConsecutive), >= 1
            %   k      (returned) index where the threshold run starts, [] if
            %          none
            %   short  (returned) as firstRun: the run ends at the loudest level
            %          and is shorter than K
            %   lo     (returned) the lowest index above the stop (n+1 when the
            %          loudest K levels are all misses)
            D = logical(D(:));
            K = max(1,round(K));
            n = numel(D);
            lo = 1;
            c = 0;
            for i = n:-1:1
                if D(i)
                    c = 0;
                else
                    c = c + 1;
                    if c == K
                        lo = i + K;
                        break
                    end
                end
            end
            [k,short] = mabr.analysis.SeriesThreshold.firstRun(D(lo:n),K);
            if ~isempty(k), k = k + lo - 1; end
        end

        function [k,short] = firstRun(D,K)
            % The first run of K consecutive detections.
            %
            %   D      logical vector over ascending levels
            %   K      run length (MinConsecutive), >= 1
            %   k      (returned) index where the lowest run starts, [] if none
            %   short  (returned) true when that run is shorter than K because
            %          it ends at the loudest level (accepted: a level that is
            %          not there cannot be required to respond)
            D = logical(D(:));
            K = max(1,round(K));
            n = numel(D);
            k = []; short = false;
            for i = 1:n
                j = min(i+K-1,n);
                if all(D(i:j))
                    k = i;
                    short = i+K-1 > n;
                    return
                end
            end
        end

        % =================================================================
        %  The curated value
        % =================================================================
        function F = finalValue(row,convention)
            % The threshold a curated Thresholds row stands for.
            %
            %   row         one Thresholds row (table row or struct) with
            %               Decision, ManualKind, ManualValue, Threshold,
            %               Censored, ThrLo, ThrHi, MinLevel, MaxLevel and,
            %               when there, LevelStep and Fit (whose X are the
            %               usable levels and LevelDirection the axis; a
            %               cell holding it, as a table's Fit column does,
            %               is unwrapped). A table of several rows, or a
            %               struct array (table2struct of one), gives a
            %               struct array, one element per row.
            %   convention  "midpoint" (default), "lowest_level" or "crossing"
            %   F           (returned) struct Final, FinalCensored, FinalLo,
            %               FinalHi:
            %     ""/"accepted"   the method's Threshold/Censored/ThrLo/ThrHi
            %     "manual" level  L = lowest level WITH a response: the interval
            %                     (next lower usable level, L], point by
            %                     convention; L the lowest -> left-censored
            %     "manual" value  that value, uncensored
            %     "noresponse"    Inf, right-censored at MaxLevel
            %     "allrespond"    MinLevel, left-censored
            %     "excluded"      NaN, ""
            arguments
                row
                convention (1,1) string {mustBeMember(convention,["midpoint","lowest_level","crossing"])} = "midpoint"
            end
            % Several rows: one value each. (A struct array has to be taken
            % apart too -- a dot reference into one is a comma list, not a
            % value.)
            if istable(row) || (isstruct(row) && ~isscalar(row))
                if istable(row), nr = height(row); else, nr = numel(row); end
                F = repmat(struct('Final',NaN,'FinalCensored',"",'FinalLo',NaN,'FinalHi',NaN),nr,1);
                for i = 1:nr
                    if istable(row), ri = table2struct(row(i,:)); else, ri = row(i); end
                    F(i) = mabr.analysis.SeriesThreshold.finalValue(ri,convention);
                end
                return
            end
            r = row;
            F = struct('Final',NaN,'FinalCensored',"",'FinalLo',NaN,'FinalHi',NaN);
            decision = lower(strtrim(string(rowField(r,'Decision',""))));
            if ismissing(decision), decision = ""; end
            fit = rowFit(r);
            sgn = 1;
            if isstruct(fit) && isfield(fit,'LevelDirection') && string(fit.LevelDirection) == "descending"
                sgn = -1;
            end
            minL = double(rowField(r,'MinLevel',NaN));
            maxL = double(rowField(r,'MaxLevel',NaN));

            switch decision
                case "manual"
                    kind = lower(string(rowField(r,'ManualKind',"value")));
                    v    = double(rowField(r,'ManualValue',NaN));
                    if kind == "level"
                        lev = usableLevels(r,fit,minL,maxL);
                        F   = manualLevel(v,lev,sgn,convention);
                    else
                        F = struct('Final',v,'FinalCensored',"none",'FinalLo',v,'FinalHi',v);
                        if ~isfinite(v), F.FinalCensored = ""; end
                    end
                case "noresponse"
                    F = censoredX(+1,minL,maxL,sgn);
                case "allrespond"
                    F = censoredX(-1,minL,maxL,sgn);
                case "excluded"
                    % NaN, uncensored: nothing to report.
                otherwise
                    F.Final         = double(rowField(r,'Threshold',NaN));
                    F.FinalCensored = string(rowField(r,'Censored',""));
                    F.FinalLo       = double(rowField(r,'ThrLo',NaN));
                    F.FinalHi       = double(rowField(r,'ThrHi',NaN));
            end
        end

        function s = formatValue(value,censored,lo,hi)
            % Display text of a threshold with its censoring.
            %
            %   "34.9" (none) · "35 (30–40]" (interval) · ">80" (right) ·
            %   "≤0" (left) · "n/a" ("" or no value). Integers print with %g,
            %   anything else with one decimal.
            %
            %   value, censored, lo, hi  scalars, or arrays of one size (a
            %                            scalar is expanded)
            %   s                        (returned) string, same size as value
            arguments
                value double
                censored string = "none"
                lo double = NaN
                hi double = NaN
            end
            sz = size(value);
            if isscalar(censored), censored = repmat(censored,sz); end
            if isscalar(lo), lo = repmat(lo,sz); end
            if isscalar(hi), hi = repmat(hi,sz); end
            s = strings(sz);
            for i = 1:numel(value)
                s(i) = formatOne(value(i),censored(i),lo(i),hi(i));
            end
        end

        function tf = belowThreshold(level,final,finalCensored,finalLo,opts)
            % True for a level below the final threshold (peaks use it).
            %
            %   interval -> level <= FinalLo (the highest level without a
            %   response); none -> level < Final; right (no response) ->
            %   true; left / "" / excluded -> false.
            %
            %   level          level(s), any shape
            %   final, finalCensored, finalLo   the series' final value
            %   opts.Direction "ascending" (default) or "descending" (an
            %                  attenuation axis: the rule is applied to -level)
            %   opts.FinalHi   needed for a descending interval
            %   tf             (returned) logical, size of level
            arguments
                level double
                final (1,1) double
                finalCensored {mustBeTextScalar}
                finalLo (1,1) double = NaN
                opts.Direction (1,1) string {mustBeMember(opts.Direction,["ascending","descending"])} = "ascending"
                opts.FinalHi (1,1) double = NaN
            end
            c = string(finalCensored);
            if opts.Direction == "descending"
                level = -level;
                final = -final;
                lo    = -opts.FinalHi;
                if c == "left", c = "right"; elseif c == "right", c = "left"; end
            else
                lo = finalLo;
            end
            switch c
                case "interval", tf = level <= lo;
                case "none",     tf = level < final;
                case "right",    tf = true(size(level));
                otherwise,       tf = false(size(level));
            end
        end
    end
end

% =========================================================================
%  Local functions
% =========================================================================
function r = mrow(id,label,metric,model,mode,crit)
% One methods() row. All fields strings except Criterion/NeedsMeasures.
r = struct('Id',string(id),'Label',string(label),'Metric',string(metric), ...
    'Model',string(model),'CriterionMode',string(mode),'Criterion',crit, ...
    'CriterionUnit',criterionUnit(string(mode),string(metric)), ...
    'NeedsMeasures',needsMeasures(string(metric)));
end

function v = setting(s,name,default)
% A field of a Settings object or a plain struct; default when absent.
% (An EMPTY value is returned as it is: SplitHalfWindow = [] means "use the
% response window", which is a value, not an absence.)
v = default;
if isempty(s), return; end
if isstruct(s)
    if isfield(s,name), v = s.(name); end
elseif isobject(s) && isprop(s,name)
    v = s.(name);
end
end

function tf = needsMeasures(metric)
% Metrics that Session.measure computes (detect computes the others).
tf = ismember(metric,["power","fsp","splithalf","xcorr","snr"]);
end

function u = criterionUnit(mode,metric)
% The unit a criterion of this mode/metric is in.
switch mode
    case "p",           u = "p";
    case "probability", u = "probability";
    case "fraction",    u = "fraction of range";
    otherwise
        switch metric
            case {"splithalf","xcorr"}, u = "r";
            case "snr",                 u = "dB";
            case "strength",            u = "statistic";
            otherwise,                  u = "p";
        end
end
end

function c = defaultCriterion(mode,metric,alpha)
% The criterion of a custom method whose Settings.Criterion is NaN.
switch mode
    case "p",           c = alpha;
    case "probability", c = 0.5;
    case "fraction",    c = 0.5;
    otherwise
        switch metric
            case "splithalf", c = 0.30;
            case "xcorr",     c = 0.35;
            case "snr",       c = 3;      % dB: response power equal to the residual noise
            otherwise,        c = NaN;    % the permutation statistic has no natural scale
        end
end
end

function why = combinationProblem(metric,model,mode,crit)
% "" when a custom metric/model/mode/criterion can be estimated, else why not.
why = "";
if ~ismember(metric,mabr.analysis.SeriesThreshold.Metrics)
    why = string(sprintf('unknown metric "%s".',metric)); return
end
if ~ismember(model,mabr.analysis.SeriesThreshold.Models)
    why = string(sprintf('unknown model "%s".',model)); return
end
if ~ismember(mode,mabr.analysis.SeriesThreshold.CriterionModes)
    why = string(sprintf('unknown criterion mode "%s".',mode)); return
end
isP = ismember(metric,["detection","power","fsp"]);
switch model
    case "descending"
        if isP && mode ~= "p"
            why = sprintf('"descending" on the p-value metric "%s" needs criterion mode "p".',metric);
        elseif ~isP && mode ~= "absolute"
            why = sprintf('"descending" on the graded metric "%s" needs criterion mode "absolute".',metric);
        end
    case "glm"
        if ~isP
            why = sprintf(['"glm" is a model of yes/no detections; "%s" is graded and has no p-value ' ...
                '(use descending, presto or sigmoid).'],metric);
        elseif mode ~= "probability"
            why = '"glm" needs criterion mode "probability".';
        end
    case "presto"
        if ~ismember(metric,["splithalf","xcorr"])
            why = sprintf('"presto" fits a correlation (splithalf or xcorr), not "%s".',metric);
        elseif mode ~= "absolute"
            why = '"presto" needs criterion mode "absolute".';
        end
    otherwise
        if mode ~= "fraction"
            why = sprintf('"%s" is a legacy model and needs criterion mode "fraction".',model);
        end
end
if why ~= "", return; end
switch mode
    case "p"
        if ~(crit > 0 && crit <= 1), why = sprintf('criterion %g is not a p-value in (0,1].',crit); end
    case {"probability","fraction"}
        if ~(crit >= 0 && crit <= 1), why = sprintf('criterion %g is not in [0,1].',crit); end
    otherwise
        if ~isfinite(crit)
            why = sprintf('an absolute criterion on "%s" needs a value.',metric);
        elseif ismember(metric,["splithalf","xcorr"]) && ~(crit > -1 && crit < 1)
            why = sprintf('criterion %g is not a correlation in (-1,1).',crit);
        elseif metric == "strength" && crit < 0
            why = sprintf('criterion %g is below 0, where no permutation statistic lies.',crit);
        end
end
why = string(why);
end

function m = checkMethod(m)
% Validate a method struct handed to estimate (fills what can be derived).
if ~isstruct(m) || ~isscalar(m)
    error('mabr:analysis:SeriesThreshold:badMethod','A method is a struct from resolve() or an Id.');
end
need = ["Metric","Model","CriterionMode","Criterion"];
for f = need
    if ~isfield(m,f)
        error('mabr:analysis:SeriesThreshold:badMethod','The method struct has no %s field.',f);
    end
end
m.Metric = string(m.Metric); m.Model = string(m.Model); m.CriterionMode = string(m.CriterionMode);
if ~isfield(m,'Id'), m.Id = "custom"; end
if ~isfield(m,'Label'), m.Label = ""; end
m.Id = string(m.Id);
why = combinationProblem(m.Metric,m.Model,m.CriterionMode,double(m.Criterion));
if why ~= ""
    error('mabr:analysis:SeriesThreshold:badMethod','%s',why);
end
if ~isfield(m,'CriterionUnit'), m.CriterionUnit = criterionUnit(m.CriterionMode,m.Metric); end
if ~isfield(m,'NeedsMeasures'), m.NeedsMeasures = needsMeasures(m.Metric); end
end

function Y = normalizeY(Y,n)
% Every Y column as [n x 1] double: missing values NaN, missing counts Inf
% (an unknown count does not make a level unusable), IsSig as 0/1/NaN,
% ZeroVariance as 0/1/NaN (NaN: not said).
names  = ["P","IsSig","Strength","PowerP","FspP","SplitR","SplitRSD","XCorrUp", ...
          "SNR","NClean","NPos","NNeg","Override","ZeroVariance"];
counts = ["NClean","NPos","NNeg"];
for f = names
    if isfield(Y,f) && ~isempty(Y.(f))
        v = Y.(f);
        if ~(isnumeric(v) || islogical(v))
            error('mabr:analysis:SeriesThreshold:badInput','Y.%s is not numeric.',f);
        end
        v = double(v(:));
        if numel(v) ~= n
            error('mabr:analysis:SeriesThreshold:badInput', ...
                'Y.%s has %d values for %d levels.',f,numel(v),n);
        end
    elseif ismember(f,counts)
        v = inf(n,1);
    else
        v = nan(n,1);
    end
    Y.(f) = v;
end
end

function v = metricColumn(Y,metric)
% The per-level value a metric is judged on.
switch metric
    case "detection", v = Y.P;
    case "power",     v = Y.PowerP;
    case "fsp",       v = Y.FspP;
    case "splithalf", v = Y.SplitR;
    case "xcorr",     v = Y.XCorrUp;
    case "snr",       v = Y.SNR;
    otherwise,        v = Y.Strength;
end
end

function [D,crit] = detections(y,m,alpha)
% The detection at each (usable, ascending) level, before overrides, and the
% criterion it was judged against.
isP = ismember(m.Metric,["detection","power","fsp"]);
if isP
    crit = alpha;
    if m.CriterionMode == "p" && isfinite(m.Criterion), crit = m.Criterion; end
    D = y < crit;
    if m.CriterionMode ~= "p", crit = m.Criterion; end
elseif m.CriterionMode == "fraction"
    crit = m.Criterion;
    fin  = isfinite(y);
    D    = false(size(y));
    if any(fin)
        lo = min(y(fin)); hi = max(y(fin));
        if hi > lo, D = y >= lo + crit*(hi-lo); end
    end
else
    crit = m.Criterion;
    D = y >= crit;
end
D = D(:);
end

function [step,minL,maxL] = levelRange(lu,lall)
% Median spacing and range of the usable levels, falling back to every
% finite level when fewer than two are usable (so a human decision on an
% insufficient series still has a bound to stand on).
lu = lu(:); lall = lall(:);
src = lu;
if numel(unique(src)) < 2, src = lall; end
us = unique(src);
if numel(us) >= 2, step = median(diff(us)); else, step = NaN; end
if ~isempty(lu)
    minL = min(lu); maxL = max(lu);
elseif ~isempty(lall)
    minL = min(lall); maxL = max(lall);
else
    minL = NaN; maxL = NaN;
end
end

function R = newResult(model)
% An empty result (x-space), as fitSeries fills it.
R = struct('Threshold',NaN,'ThresholdRaw',NaN,'Status',"ok",'Censored',"", ...
    'ThrLo',NaN,'ThrHi',NaN,'CI',[NaN NaN],'CIMethod',"none",'CIOpen',[false false], ...
    'Type',string(model),'FitTarget',"binary",'Converged',false,'Fitted',false, ...
    'Message',"",'Flags',strings(1,0),'Model',struct(),'Scale',[0 1], ...
    'Predict',@(xx) nan(numel(xx),1));
end

function t = fitTargetOf(m,isP)
% "binary" for p-detections judged as yes/no, "graded" otherwise.
if isP && ismember(m.Model,["descending","glm","minimum"]), t = "binary"; else, t = "graded"; end
end

function R = fitSeries(L,y,D,Dperm,ex,m,opts,K,step)
% Steps 5-8 of estimate(): the model on the usable levels L (ascending, in
% the fitting direction). Returns the result in that direction.
isP = ismember(m.Metric,["detection","power","fsp"]);
n   = numel(L);
R   = newResult(m.Model);
R.FitTarget = fitTargetOf(m,isP);
R.Status    = "ok";

switch m.Model
    case "descending"
        [k,short] = mabr.analysis.SeriesThreshold.descendingRun(D,K);
        if short, R.Flags(end+1) = "top-level-only run"; end
        if isempty(k)
            R = setRight(R,L(n));
            R.Status = "no-response";
            if any(D), R.Flags(end+1) = "isolated detection below threshold"; end
            kk = NaN;
        elseif k == 1
            R = setLeft(R,L(1));
            R.Status = "all-respond";
            if any(~D), R.Flags(end+1) = "miss above threshold"; end
            kk = 1;
        else
            lo = L(k-1); hi = L(k);
            cross = NaN;
            if ~isP, cross = crossing(lo,hi,y(k-1),y(k),m.Criterion); end
            if ~isP && opts.Interpolate && isfinite(cross)
                R.Threshold = cross;
                R.Censored  = "none";
                R.ThrLo     = cross;
                R.ThrHi     = cross;
            else
                R.Censored = "interval";
                R.ThrLo    = lo;
                R.ThrHi    = hi;
                switch opts.Convention
                    case "lowest_level"
                        R.Threshold = hi;
                    case "crossing"
                        if isfinite(cross), R.Threshold = cross; else, R.Threshold = (lo+hi)/2; end
                    otherwise
                        R.Threshold = (lo+hi)/2;
                end
            end
            if any(D(1:k-1)), R.Flags(end+1) = "isolated detection below threshold"; end
            if any(~D(k:n)),  R.Flags(end+1) = "miss above threshold"; end
            kk = k;
        end
        R.Converged = true;
        R.Model = struct('KStar',kk,'K',K,'Convention',opts.Convention);
        if K == 1, R.Message = "lowest detected level, descending from the loudest";
        else, R.Message = sprintf("lowest of %d consecutive detected levels, descending from the loudest",K); end
        if isP
            thr = R.Threshold;
            R.Predict = @(xx) double(xx(:) >= thr);
        else
            [Lu,~,g] = unique(L);
            yu = accumarray(g,y,[],@mean);
            if numel(Lu) >= 2
                R.Predict = @(xx) interp1(Lu,yu,min(max(xx(:),Lu(1)),Lu(end)),'linear');
            end
        end

    case "glm"
        f = mabr.analysis.Threshold.fit(L,double(D),Type="glm",Penalty="firth", ...
            Weights=ones(n,1),Criterion=m.Criterion,Extrapolate=opts.Extrapolate, ...
            NearestLevel=opts.NearestLevel,CIAlpha=opts.CIAlpha, ...
            CINumSamples=opts.CINumSamples,Seed=opts.Seed);
        R = fromFit(R,f);
        R.FitTarget = "binary";
        R.Message = joinText(["psychometric (advisory)" f.Message]);
        if any(f.CIOpen), R.Flags(end+1) = "profile CI open"; end

    case "presto"
        f = mabr.analysis.Threshold.prestoFit(L,y,m.Criterion,SD=ex.SD,Step=step);
        R.FitTarget = "graded";
        R.Type      = f.Type;
        R.Model     = f.Model;
        R.Predict   = f.Predict;
        R.Converged = f.Converged;
        R.Fitted    = f.Type ~= "presto";
        R.Message   = f.Message;
        R.Flags     = [R.Flags f.Flags];
        switch f.Status
            case "ok"
                t = f.Threshold;
                if ~opts.Extrapolate && isfinite(t), t = min(max(t,L(1)),L(n)); end
                if opts.NearestLevel && isfinite(t)
                    kn = find(L >= t,1,'first');
                    if ~isempty(kn), t = L(kn); end
                end
                R.Threshold = t; R.Censored = "none"; R.ThrLo = t; R.ThrHi = t;
            case "all-respond"
                R = setLeft(R,L(1));  R.Status = "all-respond";
            case "no-response"
                R = setRight(R,L(n)); R.Status = "no-response";
            case "insufficient"
                % Fewer than two levels with a finite r (overridden levels
                % count as usable without one): nothing to fit, which is not
                % the same as a fit that failed to cross.
                R.Threshold = NaN; R.Censored = ""; R.Status = "insufficient";
            otherwise
                R.Threshold = NaN; R.Censored = ""; R.Status = "failed";
        end

    otherwise   % legacy fraction models: isotonic, sigmoid, minimum
        kp = mabr.analysis.SeriesThreshold.firstRun(Dperm,K);
        if isempty(kp)
            % The gate: a fraction of the observed range always exists, so a
            % series of pure noise would always "cross" it somewhere. Without
            % K consecutive permutation detections there is no response to
            % have a threshold, and the model is not fitted at all.
            R = setRight(R,L(n));
            R.Status  = "no-response";
            R.Message = sprintf("No run of %d consecutive permutation detections; %s fit not attempted.", ...
                K,m.Model);
            R.Predict = @(xx) zeros(numel(xx),1);
        else
            target = opts.LegacyFitTarget;
            if target == "auto"
                if ~isP
                    target = "graded";
                elseif m.Model == "minimum"
                    target = "binary";
                else
                    target = "strength";
                end
            end
            switch target
                case "binary",   yy = double(D);
                case "p",        yy = 1 - ex.P;
                case "strength", yy = ex.Strength;
                otherwise,       yy = y;
            end
            if target == "strength" && ~any(isfinite(yy))
                target = "binary"; yy = double(D);     % nothing graded to fit
            end
            f = mabr.analysis.Threshold.fit(L,yy,Type=m.Model,Criterion=m.Criterion, ...
                Weights=ex.LW,Extrapolate=opts.Extrapolate,NearestLevel=opts.NearestLevel, ...
                CIAlpha=opts.CIAlpha,CINumSamples=opts.CINumSamples,Seed=opts.Seed);
            R = fromFit(R,f);
            if target == "binary", R.FitTarget = "binary"; else, R.FitTarget = "graded"; end
        end
end
end

function R = fromFit(R,f)
% Copy a Threshold.fit result into a series result (a point estimate).
R.Threshold = f.Threshold;
R.CI        = f.CI;
R.CIMethod  = f.CIMethod;
R.CIOpen    = f.CIOpen;
R.Type      = f.Type;
R.Converged = f.Converged;
R.Model     = f.Model;
R.Scale     = f.Scale;
R.Message   = f.Message;
R.Fitted    = true;
if ~isempty(f.Predict), R.Predict = f.Predict; end
R.Censored  = "none";
R.ThrLo     = f.Threshold;
R.ThrHi     = f.Threshold;
if isfield(f,'Status') && f.Status == "insufficient", R.Status = "insufficient"; end
end

function R = censorResult(R,L,D,step)
% Step 10: the censoring rules every model's estimate is put through.
if R.Status == "insufficient", return; end
n = numel(L);
if all(D)
    R = setLeft(R,L(1));
    R.Status = "all-respond";
elseif ~any(D)
    R = setRight(R,L(n));
    R.Status = "no-response";
elseif any(R.Censored == ["none","interval"])
    t = R.Threshold;
    if isnan(t)
        R.Status = "failed";
    elseif t < L(1) - step
        R = setLeft(R,L(1));
        R.Status = "all-respond";
        R.Flags(end+1) = "estimate below range";
    elseif t > L(n) + step
        R = setRight(R,L(n));
        R.Status = "no-response";
        R.Flags(end+1) = "estimate above range";
    end
end
if R.Status == "failed"
    R.Threshold = NaN; R.Censored = ""; R.ThrLo = NaN; R.ThrHi = NaN;
end
end

function R = setLeft(R,L1)
% Left-censored at the lowest usable level: threshold at or below L1.
R.Threshold = L1; R.Censored = "left"; R.ThrLo = NaN; R.ThrHi = L1;
R = dropCI(R);
end

function R = setRight(R,Ln)
% Right-censored at the highest usable level: no response up to Ln.
R.Threshold = Inf; R.Censored = "right"; R.ThrLo = Ln; R.ThrHi = NaN;
R = dropCI(R);
end

function R = dropCI(R)
% A censored value has no interval of its own: the model's interval was
% around an estimate that is no longer the answer.
R.CI = [NaN NaN]; R.CIMethod = "none"; R.CIOpen = [false false];
R.Flags(R.Flags == "profile CI open") = [];
end

function R = mirrorResult(R)
% Map a result fitted on -level back to the levels' own direction.
R.Threshold    = -R.Threshold;
R.ThresholdRaw = -R.ThresholdRaw;
lo = -R.ThrHi; hi = -R.ThrLo;
R.ThrLo = lo; R.ThrHi = hi;
R.CI     = -fliplr(R.CI);
R.CIOpen = fliplr(R.CIOpen);
if R.Censored == "left", R.Censored = "right"; elseif R.Censored == "right", R.Censored = "left"; end
end

function R = bootstrapCI(R,YB,u,L,ov,Dperm,ex,m,opts,K,step,n)
% Step 9: refit every replicate column of YB with the same model; the
% percentile interval of the finite replicate thresholds (>= 10 of them).
if size(YB,1) ~= n
    error('mabr:analysis:SeriesThreshold:badInput', ...
        'YBoot has %d rows for %d levels.',size(YB,1),n);
end
B  = size(YB,2);
th = nan(B,1);
ob = opts;
ob.CINumSamples = 100;          % a replicate's own interval is never used
for b = 1:B
    yb = YB(u,b);
    ok = isfinite(yb) | ~isnan(ov);
    if sum(ok) < 2, continue; end
    Db = detections(yb(ok),m,opts.Alpha);
    ovb = ov(ok);
    Db(~isnan(ovb)) = ovb(~isnan(ovb)) ~= 0;
    exb = struct('P',ex.P(ok),'Strength',ex.Strength(ok),'SD',ex.SD(ok),'LW',ex.LW(ok));
    try
        Rb = fitSeries(L(ok),yb(ok),Db,Dperm(ok),exb,m,ob,K,step);
        Rb = censorResult(Rb,L(ok),Db,step);
        th(b) = Rb.Threshold;
    catch
        th(b) = NaN;
    end
end
fin = th(isfinite(th));
if numel(fin) >= 10
    R.CI       = reshape(mabr.analysis.Stats.percentile(fin,[opts.CIAlpha/2 1-opts.CIAlpha/2]),1,2);
    R.CIMethod = "bootstrap";
    R.CIOpen   = [false false];
end
end

function t = crossing(x0,x1,y0,y1,c)
% Straight-line crossing of criterion c between (x0,y0), below it, and
% (x1,y1), at or above it -- a point of (x0, x1]; NaN when the two values do
% not bracket c. Without overrides they always do (the level under the first
% run is undetected: y0 < c <= y1). An override can break that -- a level
% overridden to "no response" whose metric is over the criterion, or the
% reverse -- and the line extended past its ends would then put the
% threshold ON the open end of the interval (x0, x1], or outside it. The
% detections are then the person's, the metric has no crossing to offer, and
% the interval stands with its Convention point.
t = NaN;
if ~all(isfinite([x0 x1 y0 y1 c])) || ~(y0 < c && c <= y1), return; end
t = x0 + (c - y0)/(y1 - y0)*(x1 - x0);
t = min(max(t,min(x0,x1)),max(x0,x1));
end

function tf = sameFamily(requested,used)
% Is the model actually used the one asked for? (presto reports its curve.)
requested = string(requested); used = string(used);
if requested == "presto"
    tf = startsWith(used,"presto");
else
    tf = requested == used;
end
end

function s = joinText(parts)
% Non-empty parts joined by "; ".
parts = string(parts);
parts = parts(strlength(parts) > 0);
s = strjoin(parts,"; ");
if isempty(s), s = ""; end
end

function v = ifelse(c,a,b)
if c, v = a; else, v = b; end
end

function s = fmtNum(v)
% A level for text: %g for integers, one decimal otherwise.
if ~isfinite(v)
    s = string(sprintf('%g',v));
elseif abs(v - round(v)) <= 1e-9*max(1,abs(v))
    s = string(sprintf('%g',round(v) + 0));
else
    s = string(sprintf('%.1f',v));
end
end

function s = formatOne(v,c,lo,hi)
% formatValue for one element.
switch c
    case "none"
        if isfinite(v), s = fmtNum(v); else, s = "n/a"; end
    case "interval"
        if ~isfinite(v)
            s = "n/a";
        elseif isfinite(lo) && isfinite(hi)
            s = fmtNum(v) + " (" + fmtNum(lo) + "–" + fmtNum(hi) + "]";
        else
            s = fmtNum(v);
        end
    case "right"
        b = lo;
        if ~isfinite(b), b = v; end
        if isfinite(b), s = ">" + fmtNum(b); else, s = "n/a"; end
    case "left"
        b = hi;
        if ~isfinite(b), b = v; end
        if isfinite(b), s = "≤" + fmtNum(b); else, s = "n/a"; end
    otherwise
        s = "n/a";
end
end

function v = rowField(r,name,default)
% A field of a Thresholds row (struct), unwrapping a 1x1 cell.
v = default;
if isstruct(r) && isfield(r,name)
    v = r.(name);
    if iscell(v)
        if isempty(v), v = default; else, v = v{1}; end
    end
    if isempty(v), v = default; end
end
end

function fit = rowFit(r)
% The row's Fit struct, or [] when it has none.
fit = [];
if isstruct(r) && isfield(r,'Fit')
    f = r.Fit;
    if iscell(f) && ~isempty(f), f = f{1}; end
    if isstruct(f) && isscalar(f), fit = f; end
end
end

function lev = usableLevels(r,fit,minL,maxL)
% The series' usable levels: Fit.X when saved, else the regular grid the
% row's MinLevel/LevelStep/MaxLevel describe.
lev = [];
if isstruct(fit) && isfield(fit,'X') && ~isempty(fit.X)
    lev = double(fit.X(:));
else
    st = double(rowField(r,'LevelStep',NaN));
    if all(isfinite([minL maxL st])) && st > 0
        lev = (minL:st:maxL).';
    elseif all(isfinite([minL maxL]))
        lev = unique([minL; maxL]);
    end
end
lev = unique(lev(isfinite(lev)));
end

function F = manualLevel(v,lev,sgn,convention)
% A human's "lowest level with a response" as an interval over the usable
% levels (in the fitting direction, then mapped back).
F = struct('Final',NaN,'FinalCensored',"",'FinalLo',NaN,'FinalHi',NaN);
if ~isfinite(v), return; end
xv = sgn*v;
xs = sort(sgn*lev);
prev = xs(xs < xv);
if isempty(prev)
    fx = struct('Final',xv,'FinalCensored',"left",'FinalLo',NaN,'FinalHi',xv);
else
    lo = prev(end);
    if convention == "lowest_level", pt = xv; else, pt = (lo+xv)/2; end
    fx = struct('Final',pt,'FinalCensored',"interval",'FinalLo',lo,'FinalHi',xv);
end
F = fromX(fx,sgn);
end

function F = censoredX(side,minL,maxL,sgn)
% "noresponse" (side +1) / "allrespond" (side -1) in the fitting direction,
% mapped back.
if sgn > 0, xmin = minL; xmax = maxL; else, xmin = -maxL; xmax = -minL; end
if side > 0
    fx = struct('Final',Inf,'FinalCensored',"right",'FinalLo',xmax,'FinalHi',NaN);
else
    fx = struct('Final',xmin,'FinalCensored',"left",'FinalLo',NaN,'FinalHi',xmin);
end
F = fromX(fx,sgn);
end

function F = fromX(fx,sgn)
% Map a final value from the fitting direction back to the levels'.
F = fx;
if sgn > 0, return; end
F.Final   = -fx.Final;
F.FinalLo = -fx.FinalHi;
F.FinalHi = -fx.FinalLo;
if fx.FinalCensored == "left", F.FinalCensored = "right";
elseif fx.FinalCensored == "right", F.FinalCensored = "left"; end
end

% --- definition text ------------------------------------------------------
function s = critText(c)
% A criterion in a sentence.
if abs(c) < 1, s = string(sprintf('%.2f',c)); else, s = string(sprintf('%g',c)); end
end

function s = criterionText(m)
% The criterion of a resolved method, with its unit where it has one.
switch m.CriterionMode
    case "fraction", s = critText(m.Criterion);
    otherwise
        if m.CriterionUnit == "dB", s = string(sprintf('%g dB',m.Criterion));
        else, s = critText(m.Criterion); end
end
end

function n = detectName(dm)
% The permutation statistic as named in a sentence.
switch string(dm)
    case "tfce",        n = "TFCE";
    case "clusterMass", n = "cluster-mass";
    case "tmax",        n = "t-max";
    otherwise,          n = string(dm);
end
end

function s = pEvidence(metric,settings,glm)
% The p-value a p-metric's detections come from, in parentheses-ready text.
a  = double(setting(settings,'Alpha',0.05));
B  = double(setting(settings,'NumPermutations',1000));
dn = detectName(setting(settings,'DetectMethod',"tfce"));
switch metric
    case "detection"
        if glm
            s = sprintf('%s permutation test, α %g, %d permutations',dn,a,B);
        else
            s = sprintf('permutation test %s, α %g, %d permutations',dn,a,B);
        end
    case "power"
        s = sprintf('response power vs ± reference, sign-flip test, α %g, %d permutations',a,B);
    otherwise
        s = sprintf('Fsp with estimated degrees of freedom, α %g',a);
end
s = string(s);
end

function q = gradedQuantity(metric,settings)
% The graded quantity a criterion is applied to, as a noun phrase.
switch metric
    case "splithalf"
        md  = string(setting(settings,'SplitHalfMode',"median"));
        R   = double(setting(settings,'SplitHalfResamples',500));
        win = double(setting(settings,'SplitHalfWindow',[]));
        if numel(win) ~= 2, win = double(setting(settings,'ResponseWindow',[0.5 8])); end
        q = sprintf('the split-half correlation (%s sub-averages, %d resamples, %g–%g ms)', ...
            md,R,win(1),win(2));
    case "xcorr"
        q = sprintf("the correlation with the next-louder level's average (lag ≤ %g ms)", ...
            double(setting(settings,'MaxLag',0.3)));
    case "snr"
        q = 'the response SNR re the ± reference noise';
    case "strength"
        q = sprintf('the %s permutation statistic',detectName(setting(settings,'DetectMethod',"tfce")));
    otherwise
        q = sprintf('the %s p-value',metric);
end
q = string(q);
end
