function [thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals, options, ptoptions)
% abrPermutationThreshold  Permutation-based ABR detection across rows with improved threshold estimation.
%
%   [thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals)
%   [thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals, options, ptoptions)
%
% Overview
%   For each condition S{r,c} (row r, column c), this runs PERMTEST across trials
%   to detect a time-locked response (two-sided; method controlled by ptoptions.method).
%   Then, for each column c, it estimates a *row-domain threshold* (e.g., dB SPL)
%   from the row-wise detection results using a more stable, information-preserving
%   fitting strategy than "fit a sigmoid to 0/1 significance".
%
% Inputs
%   S        cell [nRows x nCols]. Each S{r,c} is [nSamples x nTrials].
%            This function transposes to [nTrials x nSamples] for PERMTEST.
%
%   rowVals  double [nRows x 1]. Row-domain values (commonly dB SPL, but may be
%            any ordered stimulus dimension used to define threshold).
%
% Options (struct; fields shown with defaults)
%   options.useParallel      (1,1) logical = false
%       If true, uses PARFOR for permutation tests (disabled in debug mode).
%
%   options.debug            (1,1) logical = false
%       If true, enables diagnostic plotting and forwards ptoptions.showPlot=true.
%
%   options.thresholdType    (1,1) string = "glm"
%       Threshold model per column:
%         "glm"        : binomial GLM (logit) on binary detection y = isSig, with
%                        Jeffreys-prior (Firth) penalty and unit weights (see below)
%         "sigmoid"    : 4-parameter sigmoid on continuous strength (maxStatReal)
%         "isotonic"   : isotonic regression (monotone) on y (binary by default)
%         "minimum"    : first row meeting isSig (p < ptoptions.alpha)
%
%       Compatibility aliases:
%         "logistic"   -> "glm"
%         "logistic4"  -> "sigmoid"
%
%   options.criterion        (1,1) double {mustBeInRange(options.criterion,0,1)} = 0.5
%       Threshold criterion.
%         - For "glm": threshold is x where P(detect)=criterion (psychometric).
%         - For "sigmoid": threshold is x where fitted y reaches
%           y = A + criterion*(B-A), where A=baseline, B=ceiling.
%         - For "isotonic": threshold is first x where fitted y >= criterion, so y
%           must lie in [0,1]: use fitTarget "binary" (the default) or "p", not
%           the unbounded "strength".
%
%   options.fitTarget        (1,1) string = "auto"
%       Which y to use when a model supports both:
%         "auto"    : "glm" and "isotonic" use binary; "sigmoid" uses strength.
%         "binary"  : use y = isSig
%         "p"       : use y = 1 - pVal (in [0,1])  (sometimes helpful if you prefer)
%         "strength": use y = maxStatReal (preferred if you care about graded evidence)
%
%   options.nearestLevel     (1,1) logical = false
%       If true, pins each threshold up to the nearest value in rowVals.
%
%   options.extrapolate      (1,1) logical = true
%       If false, thresholds are clamped to [min(rowVals), max(rowVals)] after estimation.
%
%   options.ciNSamples       (1,1) double {mustBeInteger,mustBePositive} = 2000
%       Monte-Carlo samples for threshold confidence intervals (when available).
%
%   options.ciAlpha          (1,1) double {mustBeInRange(options.ciAlpha,0,1)} = 0.05
%       Confidence level alpha for CI: returns 100*(1-ciAlpha)% CI.
%
%   options.window           (1,2) double [t0 t1] in ms re sweep onset = []
%   options.Fs               (1,1) double, sampling rate in Hz (required with window)
%   options.winIdx           vector, sample offsets re onset (required with window)
%       Response window to test. PERMTEST is a one-sample sign-flip test against zero at
%       every sample it is given and never compares with a baseline, so any pre-stimulus
%       samples left in S can produce a "detection" out of baseline noise. With window
%       given, each S{r,c} is cut to the samples whose time (winIdx/Fs) lies within
%       [t0 t1] BEFORE testing; Fs and winIdx are the 3rd and 4th outputs of
%       EXTRACTABRRESPONSES, which S still matches row for row. permResult then holds the
%       per-sample results (tValsReal, ...) for those samples only, i.e. winIdx(keep).
%       The default [] tests every sample of S, as this function always did, and warns
%       once per session (abrPermutationThreshold:noWindow) that [0 10] is recommended;
%       cut S to the response window yourself and switch that warning off if you prefer.
%       Example: abrPermutationThreshold(S, U.Level, window=[0 10], Fs=Fs, winIdx=winIdx)
%
% Permutation Test Options (struct; forwarded to PERMTEST)
%   ptoptions.method         (1,1) string {"clusterMass","tmax","tfce"} = "clusterMass"
%   ptoptions.alpha          (1,1) double in (0,1) = 0.05
%   ptoptions.nPerm          (1,1) double >0 = 1000
%   ptoptions.minClusterSize (1,1) double >0 = 1
%   ptoptions.showPlot       (1,1) logical = false
%   ptoptions.Seed           (1,1) nonnegative integer = []
%       Makes the whole run reproducible. Condition number i (linear index into S after
%       its rows are sorted by rowVals) is tested with PERMTEST Seed = Seed+i-1, so no two
%       conditions share one set of sign flips, and the Monte-Carlo threshold intervals
%       draw from a private stream seeded past those. The global random stream is not
%       used or advanced. Empty (default): the global stream, as before.
%
% Outputs
%   thresh_hat   1 x nCols double
%       Threshold estimate per column.
%
%   permResult   nRows x nCols struct
%       PERMTEST result structs. In addition, this function adds fields:
%         .pVal        scalar p-value from PERMTEST
%         .isSig       logical scalar (pVal < ptoptions.alpha)
%         .nTrials     number of trials used at that condition
%         .strength    scalar detection strength used for thresholding when available
%       A condition with fewer than 2 trials (for instance one sweep left after
%       artifact rejection) cannot be tested: its pVal and strength are NaN, isSig
%       is false, and it is left out of the threshold fit.
%
%   mdls         1 x nCols cell
%       Per-column model info. Each mdls{k} is a struct with fields like:
%         .type, .criterion, .fitTarget
%         (.type is "minimum (fallback)" when the requested fit errored and the
%         first significant row was used instead; .fitError holds the message.)
%         .model (fitglm model or cfit model or isotonic struct)
%         .threshCI (1x2) CI when available, else [NaN NaN]
%
% The "glm" threshold
%   A monotone series of detections (every level below some point missed, every level
%   above it detected) is perfectly separated: the maximum-likelihood slope is infinite,
%   so an unpenalised fit returns an arbitrary slope and the threshold is just the midpoint
%   of the gap, with a meaningless interval. The fit is therefore Firth-penalised
%   (fitglm 'LikelihoodPenalty','jeffreys-prior'), which keeps slope, threshold and
%   interval finite and lets the data set them. If this MATLAB's fitglm has no such option
%   the unpenalised fit is used instead, with a warning
%   (abrPermutationThreshold:noPenalisedFit). The fit uses unit weights: each level
%   contributes ONE yes/no verdict, however many sweeps stand behind it. Weighting by the
%   trial count (as earlier versions did) treated every verdict as nTrials identical
%   observations and made the interval about sqrt(nTrials) too narrow, so the "wide CI"
%   curation flag could hardly fire. This now matches the class-based
%   mabr.analysis.Threshold (Firth penalty, unit weights: the same threshold to the
%   digit). The interval is still a Monte Carlo draw from the fit's covariance, not that
%   class's profile-likelihood interval, and is wider (draws with a nearly flat slope
%   reach far); it can run past the tested levels, which is honest about how little a
%   handful of yes/no verdicts says. THRESHOLDS AND INTERVALS FROM RUNS MADE WITH EARLIER
%   VERSIONS DIFFER from those of this one, and an all-missed (or all-detected) column is
%   Inf (or the lowest level) instead of an extrapolated number.
%
% Requirements
%   - PERMTEST
%   - Curve Fitting Toolbox for "sigmoid" (fit/cfit) only
%   - Statistics & ML Toolbox (PERMTEST uses TINV; "glm" uses FITGLM)
%   - the helper_fnc repository is optional here (PARFOR_PROGRESS is used if present)
%   - Parallel Computing Toolbox for PARFOR (optional)
%
% DJS 2025 (revised)

arguments
    S cell
    rowVals (:,1) double

    options.useParallel (1,1) logical = false
    options.debug (1,1) logical = false

    options.thresholdType (1,1) string = "glm"
    options.criterion (1,1) double {mustBeInRange(options.criterion,0,1)} = 0.5
    options.fitTarget (1,1) string {mustBeMember(options.fitTarget, ["auto","binary","p","strength"])} = "auto"

    options.nearestLevel (1,1) logical = false
    options.extrapolate (1,1) logical = true

    options.ciNSamples (1,1) double {mustBeInteger,mustBePositive} = 2000
    options.ciAlpha (1,1) double {mustBeInRange(options.ciAlpha,0,1)} = 0.05

    options.window double {mustBeFinite} = []
    options.Fs double {mustBeScalarOrEmpty,mustBePositive,mustBeFinite} = []
    options.winIdx double {mustBeFinite} = []

    ptoptions.method (1,1) string {mustBeMember(ptoptions.method, ["clusterMass","tmax","tfce"])} = "clusterMass"
    ptoptions.alpha (1,1) double {mustBeInRange(ptoptions.alpha, 0, 1)} = 0.05
    ptoptions.nPerm (1,1) double {mustBePositive,mustBeFinite} = 1000
    ptoptions.minClusterSize (1,1) double {mustBePositive,mustBeFinite} = 1
    ptoptions.showPlot (1,1) logical = false
    ptoptions.Seed double {mustBeScalarOrEmpty,mustBeNonnegative,mustBeInteger} = []
end

% Fail now, with one message, if the helper repository or a toolbox is missing, rather
% than part-way through a long permutation run. The sigmoid fit is the only part that
% needs the Curve Fitting Toolbox, and parfor_progress is optional here (see below).
needs = "statistics";
if options.thresholdType == "sigmoid" || options.thresholdType == "logistic4"
    needs(end+1) = "curvefit";
end
checkABRDependencies("abrPermutationThreshold", string.empty(1,0), needs);

% Warned about once per MATLAB session, not once per call: the default is legitimate for
% data the caller has already cut, and a batch would otherwise repeat it for every session.
persistent warnedNoWindow

% ---- Normalize/alias thresholdType for backward compatibility ----
thresholdType = options.thresholdType;
if thresholdType == "logistic"
    thresholdType = "glm";
elseif thresholdType == "logistic4"
    thresholdType = "sigmoid";
end
thresholdType = validatestring(thresholdType, ["glm","sigmoid","isotonic","minimum"]);

% ---- Sort rowVals and reorder S to match ----
[rowVals, order] = sort(rowVals(:), "ascend");
S = S(order, :);

nCols = size(S,2);
nRows = size(S,1);
assert(nRows == numel(rowVals), "Length of rowVals must match size(S,1).");

% ---- Cut S to the response window ----
% PERMTEST tests every sample it is given against zero, baseline included, so the window
% has to be applied here, before any testing, or a significant stretch of pre-stimulus
% noise counts as a detection (the cause of the "p = 0.08/0.05/0.11 on identical data"
% finding). The cut is in samples, with a hair of tolerance, so that 10 ms at a rate where
% 10 ms is not a whole number of samples neither gains nor loses an end sample to rounding.
if isempty(options.window)
    if isempty(warnedNoWindow)
        warnedNoWindow = true;
        warning("abrPermutationThreshold:noWindow", ...
            ['No response window given: every sample of S is tested, any pre-stimulus baseline ' ...
             'included, so noise before the stimulus can count as a detection. Pass ' ...
             'window=[0 10] (ms) together with Fs= and winIdx= from extractABRResponses, or cut S ' ...
             'to the response window yourself and switch this warning off with ' ...
             'warning(''off'',''abrPermutationThreshold:noWindow'').']);
    end
else
    win = options.window(:).';
    if numel(win) ~= 2 || win(1) >= win(2)
        error("abrPermutationThreshold:badWindow", "window must be [t0 t1] in ms with t0 < t1.");
    end
    if isempty(options.Fs) || isempty(options.winIdx)
        error("abrPermutationThreshold:windowNeedsTime", ...
            "window needs Fs and winIdx (the 3rd and 4th outputs of extractABRResponses) to know the time of each sample.");
    end
    winIdx = options.winIdx(:);
    keep = winIdx >= ceil(win(1) * options.Fs / 1000 - 1e-9) & winIdx <= floor(win(2) * options.Fs / 1000 + 1e-9);
    if ~any(keep)
        error("abrPermutationThreshold:emptyWindow", ...
            "No sample of winIdx (%g to %g ms at %g Hz) lies within window [%g %g] ms.", ...
            1000 * min(winIdx) / options.Fs, 1000 * max(winIdx) / options.Fs, options.Fs, win(1), win(2));
    end
    for idx = 1:numel(S)
        if isempty(S{idx}), continue; end
        if size(S{idx}, 1) ~= numel(winIdx)
            error("abrPermutationThreshold:windowMismatch", ...
                "S{%d} has %d samples but winIdx has %d; winIdx must be the one extractABRResponses returned for this S.", ...
                idx, size(S{idx}, 1), numel(winIdx));
        end
        S{idx} = S{idx}(keep, :);
    end
end

% ---- Force debug -> showPlot for PERMTEST ----
ptoptions.showPlot = options.debug;

% ---- Allocate ----
permResultCell = cell(nRows, nCols);   % store structs safely
pVal = nan(nRows, nCols);
nTrialsMat = nan(nRows, nCols);

% ---- Forward permtest options ----
% The Seed is not forwarded as given: every condition would then draw the SAME sign flips.
% Each gets its own (Seed + its linear index - 1), so one Seed still fixes the whole run.
% The threshold intervals sample coefficients at random too, so they get a stream of their
% own, seeded past those of the conditions, so a seeded run is reproducible down to
% mdls{k}.threshCI.
seed = ptoptions.Seed;
ptoptions = rmfield(ptoptions, "Seed");
cargs = namedargs2cell(ptoptions);
ciStream = [];
if ~isempty(seed)
    ciStream = RandStream("threefry", "Seed", seed + numel(S));
end

% ---- Progress helper (optional) ----
useProg = exist("parfor_progress","file") == 2;
if useProg
    parfor_progress(numel(S), "Permutation tests");
end

% ---- Run PERMTEST over all cells ----
if options.useParallel && ~options.debug
    parfor idx = 1:numel(S)
        if isempty(S{idx}), continue; end
        A = S{idx};                       % [nSamples x nTrials]
        nTrialsMat(idx) = size(A,2);
        ca = permArgs(cargs, seed, idx);
        [pVal(idx), permResultCell{idx}] = permtest(A', ca{:}); % trials x samples
        if useProg, parfor_progress; end
    end
else
    for idx = 1:numel(S)
        if isempty(S{idx}), continue; end
        A = S{idx};
        nTrialsMat(idx) = size(A,2);
        ca = permArgs(cargs, seed, idx);
        [pVal(idx), permResultCell{idx}] = permtest(A', ca{:});
        if options.debug, pause; end
        if useProg, parfor_progress; end
    end
end
if useProg, parfor_progress(0); end


% ---- Convert permResultCell to a uniform struct array ----
% Find the first result that has fields to use as a template. PERMTEST returns a
% field-less struct() for a level with fewer than 2 trials, which is not empty but
% would leave the template with no fields to build the uniform array from.
hasFields = cellfun(@(s) isstruct(s) && ~isempty(fieldnames(s)), permResultCell);
firstIdx = find(hasFields, 1, 'first');

if isempty(firstIdx)
    permResult = repmat(struct(), nRows, nCols);
else
    template = permResultCell{firstIdx};
    baseFields = fieldnames(template);

    % Add fields you always want present downstream
    extraFields = {'pVal','isSig','nTrials','strength'};
    allFields = unique([baseFields; extraFields(:)]);

    % Build defaults for missing fields
    defaults = struct();
    for f = 1:numel(allFields)
        defaults.(allFields{f}) = [];
    end

    permResult = repmat(orderfields(defaults, allFields), nRows, nCols);

    for ii = 1:numel(permResultCell)
        s = permResultCell{ii};
        if isempty(s)
            s = struct();
        end

        % Add any missing fields
        for f = 1:numel(allFields)
            fn = allFields{f};
            if ~isfield(s, fn)
                s.(fn) = [];
            end
        end

        % Assign with consistent field order
        permResult(ii) = orderfields(s, allFields);
    end
end



% ---- Sanitize p-values ----
% Clip to [0,1], but leave NaN (no test was possible) as NaN: max(NaN,0) is 0, which
% would turn every untestable level into a p of 0, i.e. a "significant" detection.
ok = ~isnan(pVal);
pVal(ok) = min(max(pVal(ok), 0), 1);
isSig = pVal < ptoptions.alpha;     % false where pVal is NaN

% ---- Add convenience fields into permResult ----
for r = 1:nRows
    for c = 1:nCols
        % A level with no data, or with fewer than 2 trials, has no PERMTEST result: it
        % returned struct() (or nothing), so the field exists after the uniform rebuild
        % above but is empty. Test for emptiness, not for the field, or strength would
        % be left [] and the arrayfun below would fail for the whole call.
        if isempty(S{r,c}) || ~isfield(permResult, "tValsReal") || isempty(permResult(r,c).tValsReal)
            permResult(r,c).pVal = nan;
            permResult(r,c).isSig = false;
            permResult(r,c).nTrials = nTrialsMat(r,c);   % NaN when there is no data at all
            permResult(r,c).strength = nan;
            continue
        end
        permResult(r,c).pVal = pVal(r,c);
        permResult(r,c).isSig = isSig(r,c);
        permResult(r,c).nTrials = nTrialsMat(r,c);

        % Preferred: use a scalar "strength" that matches PERMTEST method.
        % Newer permtest (recommended): result.maxStatReal exists.
        if isfield(permResult(r,c), "maxStatReal")
            permResult(r,c).strength = permResult(r,c).maxStatReal;
        elseif isfield(permResult(r,c), "maxClusterMassReal")
            permResult(r,c).strength = permResult(r,c).maxClusterMassReal;
        else
            permResult(r,c).strength = nan;
        end
    end
end

% ---- Threshold estimation per column ----
thresh_hat = nan(1, nCols);
mdls = cell(1, nCols);

if useProg
    parfor_progress(nCols, "Estimating thresholds");
end

for k = 1:nCols

    % Collect per-row measures for this column
    p = pVal(:,k);
    yBin = double(isSig(:,k));
    yBin(isnan(p)) = nan;                   % untestable levels are missing, not "not detected"
    yP   = 1 - p;                           % in [0,1]
    yStr = arrayfun(@(s) s.strength, permResult(:,k));
    yStr = yStr(:);

    w = nTrialsMat(:,k);                    % weights by trial count
    if all(isnan(w)) || all(w==0), w = ones(nRows,1); end
    w(~isfinite(w)) = 1;

    % Determine fit target y
    fitTarget = options.fitTarget;
    if fitTarget == "auto"
        switch thresholdType
            case "glm"
                fitTarget = "binary";
            case "sigmoid"
                fitTarget = "strength";
            case "isotonic"
                % threshold_from_isotonic compares the fitted y with options.criterion,
                % which lies in [0,1]. A strength (e.g. a cluster mass) is unbounded, so
                % any noise cluster would exceed the criterion at the lowest level.
                fitTarget = "binary";
            otherwise
                fitTarget = "binary";
        end
    end

    switch fitTarget
        case "binary",   y = yBin;
        case "p",        y = yP;
        case "strength", y = yStr;
    end
    xAll = rowVals(:);
    y    = y(:);
    w    = w(:);


    % Drop NaNs
    good = isfinite(xAll) & isfinite(y) & isfinite(w);
    x = xAll(good);
    y = y(good);
    wUse = w(good);

    mdlInfo = struct();
    mdlInfo.type = thresholdType;
    mdlInfo.criterion = options.criterion;
    mdlInfo.fitTarget = fitTarget;
    mdlInfo.threshCI = [nan nan];

    if numel(x) < 2
        thresh_hat(k) = inf;
        mdlInfo.model = [];
        mdls{k} = mdlInfo;
        if useProg, parfor_progress; end
        continue
    end

    try
        switch thresholdType

            case "minimum"
                idx = find(isSig(:,k), 1, "first");
                if isempty(idx)
                    thresh_hat(k) = inf;
                else
                    thresh_hat(k) = rowVals(idx);
                end
                mdlInfo.model = [];
                mdlInfo.threshCI = [nan nan];

            case "glm"
                % Binomial GLM is only strictly correct for binary y.
                % If user chose non-binary fitTarget, we treat y in [0,1] as
                % "fractional response" with binomial variance (quasi-like).
                % For typical ABR thresholding, use fitTarget="binary".
                if exist("fitglm","file") ~= 2
                    error("fitglm not available (Statistics & ML Toolbox required for 'glm').");
                end

                % Penalised, unit-weight fit; see "The glm threshold" in the help. y that
                % never changes (nothing detected, or everything detected) has no slope to
                % fit: the penalised fit would return a slope of ~1e-17 and a threshold
                % ~1e17 dB out, a made-up number, so those columns go to the isotonic
                % branch, which answers Inf (never detected) or the lowest level.
                useIso = numel(unique(y)) < 2;
                if ~useIso
                    glm = fit_penalised_logistic(table(x(:), y(:), 'VariableNames', {'x','y'}));
                    b = glm.Coefficients.Estimate;   % [b0; b1]
                    b0 = b(1); b1 = b(2);
                    useIso = ~isfinite(b1) || b1 <= 0;
                end

                % If slope is non-positive, fall back to isotonic (monotone)
                if useIso
                    iso = isotonic_pav(x, y, wUse);
                    thresh_hat(k) = threshold_from_isotonic(iso, options.criterion);
                    mdlInfo.model = iso;
                    mdlInfo.type = "isotonic";
                    mdlInfo.threshCI = [nan nan];
                else
                    % threshold at criterion probability
                    thr = invlogit_x_at_prob(b0, b1, options.criterion);
                    thresh_hat(k) = thr;

                    % CI via MVN sampling of coefficients using covariance
                    if isprop(glm, "CoefficientCovariance") && all(isfinite(glm.CoefficientCovariance(:)))
                        covB = glm.CoefficientCovariance;
                        thrCI = threshold_ci_from_glm(b0, b1, covB, options.criterion, options.ciNSamples, options.ciAlpha, ciStream);
                        mdlInfo.threshCI = thrCI;
                    end

                    mdlInfo.model = glm;
                end

            case "sigmoid"
                % Fit a 4-parameter sigmoid to continuous detection strength by default:
                %   y(x) = A + (B-A) / (1 + exp(-(x-c)/d))
                % Threshold is x where y reaches A + criterion*(B-A).
                if exist("fit","file") ~= 2
                    error("fit not available (Curve Fitting Toolbox required for 'sigmoid').");
                end

                % If y is binary or in [0,1], this still works; if y is strength,
                % it becomes a graded detectability curve.
                ft = fittype(@(A,B,c,d,x) A + (B-A) ./ (1 + exp(-(x-c)./d)), ...
                    "independent","x", "coefficients",["A","B","c","d"]);

                ftopts = fitoptions('Method','NonlinearLeastSquares', ...
                    'Algorithm','Levenberg-Marquardt', ...
                    'Display','Off');

                % Stable starts:
                yMin = min(y);
                yMax = max(y);
                c0 = median(x);
                d0 = max(eps, (max(x)-min(x))/8);

                ftopts.StartPoint = [yMin, yMax, c0, d0];
                ftopts.Weights = wUse(:);

                mdl = fit(x(:), y(:), ft, ftopts);

                % Compute threshold by criterion on dynamic range
                A = mdl.A; B = mdl.B; c = mdl.c; d = mdl.d;
                yCrit = A + options.criterion*(B-A);
                thr = invsigmoid_x(A,B,c,d,yCrit);
                thresh_hat(k) = thr;

                % CI (approx) from confint -> derive SD -> Monte Carlo sample
                try
                    ci = confint(mdl, 1 - options.ciAlpha); % [low; high] for params
                    thrCI = threshold_ci_from_cfit(mdl, options.criterion, options.ciNSamples, options.ciAlpha, ciStream);
                    mdlInfo.threshCI = thrCI;
                    mdlInfo.paramCI = ci;
                catch
                    % CI not available; leave NaN
                end
                mdlInfo.model = mdl;

            case "isotonic"
                % Monotone fit using pooled adjacent violators. Works for binary,
                % p-based, or strength y.
                iso = isotonic_pav(x, y, wUse);
                thresh_hat(k) = threshold_from_isotonic(iso, options.criterion);
                mdlInfo.model = iso;

        end

    catch ME
        % If fitting fails, fall back to "minimum" on significance
        mdlInfo.type = "minimum (fallback)";   % so the curation title does not claim the requested model
        idx = find(isSig(:,k), 1, "first");
        if isempty(idx)
            thresh_hat(k) = inf;
        else
            thresh_hat(k) = rowVals(idx);
        end
        mdlInfo.model = [];
        mdlInfo.fitError = ME.message;
        mdlInfo.threshCI = [nan nan];
    end

    % Clamp if requested
    if ~options.extrapolate && isfinite(thresh_hat(k))
        thresh_hat(k) = min(max(thresh_hat(k), min(rowVals)), max(rowVals));
    end

    % Pin to nearest available level if requested
    if options.nearestLevel && isfinite(thresh_hat(k))
        idx = find(rowVals >= thresh_hat(k), 1, "first");
        if ~isempty(idx)
            thresh_hat(k) = rowVals(idx);
        end
    end

    mdls{k} = mdlInfo;

    % Debug plots (per column)
    if options.debug
        figure(101); clf
        tiledlayout(2,1)

        nexttile
        plot(rowVals, double(isSig(:,k)), 'ok'); hold on
        ylim([-0.1 1.1]); grid on
        xlabel('rowVals'); ylabel(sprintf('isSig (alpha=%.3g)', ptoptions.alpha))
        title(sprintf('Column %d: binary detections', k))

        nexttile
        yy = arrayfun(@(s) s.strength, permResult(:,k)).';
        plot(rowVals, yy, 'ok'); hold on
        grid on
        xlabel('rowVals'); ylabel('strength (max-statistic)')
        title(sprintf('Column %d: strength + threshold', k))
        xline(thresh_hat(k), '-r', sprintf('th=%.3g', thresh_hat(k)), 'LineWidth', 2);

        % If model can be plotted, overlay
        mdlObj = mdls{k}.model;
        try
            if isa(mdlObj, "GeneralizedLinearModel")
                xs = linspace(min(x), max(x), 200).';
                ps = predict(mdlObj, table(xs,'VariableNames',{'x'}));
                figure(102); clf
                plot(rowVals, double(isSig(:,k)), 'ok'); hold on
                plot(xs, ps, '-'); grid on
                ylim([-0.1 1.1])
                xlabel('rowVals'); ylabel('P(detect)')
                xline(thresh_hat(k), '-r');
                title(sprintf('Column %d GLM psychometric (criterion=%.2f)', k, options.criterion))
            elseif isa(mdlObj, "cfit")
                xs = linspace(min(x), max(x), 200);
                figure(103); clf
                plot(x, y, 'ok'); hold on
                plot(xs, feval(mdlObj, xs), '-'); grid on
                xline(thresh_hat(k), '-r');
                title(sprintf('Column %d sigmoid (criterion=%.2f)', k, options.criterion))
            elseif isstruct(mdlObj) && isfield(mdlObj,"x") && isfield(mdlObj,"yhat")
                figure(104); clf
                plot(mdlObj.x, mdlObj.y, 'ok'); hold on
                stairs(mdlObj.xUnique, mdlObj.yhatUnique, '-'); grid on
                xline(thresh_hat(k), '-r');
                title(sprintf('Column %d isotonic (criterion=%.2f)', k, options.criterion))
            end
        catch
        end
    end

    if useProg, parfor_progress; end
end

if useProg, parfor_progress(0); end

end

% ========================== Helper functions ==========================

function ca = permArgs(cargs, seed, idx)
% PERMTEST arguments for condition idx: the common ones plus its own Seed when the run has one.
ca = cargs;
if ~isempty(seed)
    ca = [cargs, {"Seed", seed + idx - 1}];
end
end

function glm = fit_penalised_logistic(T)
% Logistic fit of detection y on level x with Jeffreys-prior (Firth) penalty and no
% weights, so that one verdict per level counts as one observation (see the help).
% Where this MATLAB's fitglm does not know the LikelihoodPenalty option (it is recent),
% the unpenalised fit is used and the warning says what that costs. Any other failure is
% rethrown so that the caller's fallback to the first significant level reports it.
try
    glm = fitglm(T, 'y ~ x', ...
        'Distribution','binomial', ...
        'Link','logit', ...
        'LikelihoodPenalty','jeffreys-prior');
catch ME
    if ~contains(ME.message, "LikelihoodPenalty") && ~strcmp(ME.identifier, "stats:internal:parseArgs:BadParamName")
        rethrow(ME)
    end
    warning("abrPermutationThreshold:noPenalisedFit", ...
        ['This MATLAB''s fitglm has no ''LikelihoodPenalty'' option (%s), so the GLM threshold is ' ...
         'fitted WITHOUT the Firth penalty. A monotone series of detections is perfectly separated ' ...
         'and the slope, the threshold and its interval are then set by the optimiser, not by the data.'], ME.message);
    glm = fitglm(T, 'y ~ x', 'Distribution','binomial', 'Link','logit');
end
end

function xCrit = invlogit_x_at_prob(b0, b1, pCrit)
% Solve for x where logit(p)=b0+b1*x
pCrit = min(max(pCrit, eps), 1-eps);
xCrit = (log(pCrit/(1-pCrit)) - b0) / b1;
end

function xCrit = invsigmoid_x(A,B,c,d,yCrit)
% Solve y = A + (B-A)/(1+exp(-(x-c)/d)) for x
% Guard against degenerate ranges
if ~isfinite(A) || ~isfinite(B) || ~isfinite(c) || ~isfinite(d) || d == 0 || A == B
    xCrit = nan; return
end
% Normalize
t = (B-A) / (yCrit - A) - 1;   % exp(-(x-c)/d)
if ~isfinite(t) || t <= 0
    xCrit = nan; return
end
xCrit = c - d * log(t);
end

function thrCI = threshold_ci_from_glm(b0, b1, covB, criterion, nSamp, ciAlpha, rs)
% Parametric Monte Carlo CI using MVN(b, covB). rs is a RandStream, or [] for the global one.
if nSamp < 100, nSamp = 100; end
if ~all(isfinite(covB(:))) || any(eig((covB+covB')/2) < -1e-12)
    thrCI = [nan nan]; return
end
R = chol((covB+covB')/2 + 1e-12*eye(2), "lower");
if isempty(rs), z = randn(2, nSamp); else, z = randn(rs, 2, nSamp); end
B = [b0; b1] + R*z;

thr = nan(1,nSamp);
for i = 1:nSamp
    if B(2,i) > 0
        thr(i) = invlogit_x_at_prob(B(1,i), B(2,i), criterion);
    end
end
thr = thr(isfinite(thr));
if isempty(thr)
    thrCI = [nan nan];
else
    thrCI = quantile(thr, [ciAlpha/2, 1-ciAlpha/2]);
end
end

function thrCI = threshold_ci_from_cfit(mdl, criterion, nSamp, ciAlpha, rs)
% Approximate parametric CI for threshold from cfit using confint-derived SD.
% This is a pragmatic approximation when full covariance is not exposed.
% rs is a RandStream, or [] for the global one.
ci = confint(mdl, 1 - ciAlpha);     % [low; high] for A,B,c,d
mu = [mdl.A, mdl.B, mdl.c, mdl.d];
sd = (ci(2,:) - ci(1,:)) ./ (2*1.96);  % approx SD under normality

if isempty(rs), z = randn(nSamp, 4); else, z = randn(rs, nSamp, 4); end
P = mu + sd .* z;

thr = nan(1,nSamp);
for i = 1:nSamp
    A = P(i,1); B = P(i,2); c = P(i,3); d = P(i,4);
    yCrit = A + criterion*(B-A);
    thr(i) = invsigmoid_x(A,B,c,d,yCrit);
end
thr = thr(isfinite(thr));
if isempty(thr)
    thrCI = [nan nan];
else
    thrCI = quantile(thr, [ciAlpha/2, 1-ciAlpha/2]);
end
end

function iso = isotonic_pav(x, y, w)
% Isotonic regression (non-decreasing) using pooled adjacent violators (PAV).
% Returns fitted yhat at unique x, and interpolation-ready structures.
%
% Inputs assumed finite and x may have repeats.
[xs, order] = sort(x(:), "ascend");
ys = y(order);
ws = w(order);

% Collapse repeats of x by weighted average
[xu, ~, g] = unique(xs);
yu = accumarray(g, ys.*ws, [], @sum) ./ accumarray(g, ws, [], @sum);
wu = accumarray(g, ws, [], @sum);

% PAV on (xu, yu) with weights wu
m = numel(xu);
yhat = yu;
what = wu;

i = 1;
while i < m
    if yhat(i) <= yhat(i+1)
        i = i + 1;
    else
        % pool blocks i and i+1
        wsum = what(i) + what(i+1);
        yavg = (what(i)*yhat(i) + what(i+1)*yhat(i+1)) / wsum;

        yhat(i) = yavg;
        what(i) = wsum;

        % remove i+1
        yhat(i+1) = [];
        what(i+1) = [];
        xu(i+1) = [];
        m = m - 1;

        if i > 1, i = i - 1; end
    end
end

% Expand to original sorted xs via step function interpolation:
% We keep (xu, yhat) and users can interpret as stairs.
iso = struct();
iso.x = xs;
iso.y = ys;
iso.w = ws;
iso.xUnique = xu;
iso.yhatUnique = yhat;
end

function thr = threshold_from_isotonic(iso, criterion)
% Threshold is smallest x where yhat(x) >= criterion (using unique x grid).
xu = iso.xUnique(:);
yh = iso.yhatUnique(:);
idx = find(yh >= criterion, 1, "first");
if isempty(idx)
    thr = inf;
else
    thr = xu(idx);
end
end
