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
%         "glm"        : binomial GLM (logit) on binary detection y = isSig
%         "sigmoid"    : 4-parameter sigmoid on continuous strength (maxStatReal)
%         "isotonic"   : isotonic regression (monotone) on y (binary or strength)
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
%         - For "isotonic": threshold is first x where fitted y >= criterion.
%
%   options.fitTarget        (1,1) string = "auto"
%       Which y to use when a model supports both:
%         "auto"    : "glm" uses binary; "sigmoid" uses strength; "isotonic" uses
%                     strength if available else binary.
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
% Permutation Test Options (struct; forwarded to PERMTEST)
%   ptoptions.method         (1,1) string {"clusterMass","tmax","tfce"} = "clusterMass"
%   ptoptions.alpha          (1,1) double in (0,1) = 0.05
%   ptoptions.nPerm          (1,1) double >0 = 1000
%   ptoptions.minClusterSize (1,1) double >0 = 1
%   ptoptions.showPlot       (1,1) logical = false
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
%
%   mdls         1 x nCols cell
%       Per-column model info. Each mdls{k} is a struct with fields like:
%         .type, .criterion, .fitTarget
%         .model (fitglm model or cfit model or isotonic struct)
%         .threshCI (1x2) CI when available, else [NaN NaN]
%
% Requirements
%   - PERMTEST
%   - Curve Fitting Toolbox for "sigmoid" (fit/cfit) (optional)
%   - Statistics & ML Toolbox for "glm" (fitglm) (optional)
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

    ptoptions.method (1,1) string {mustBeMember(ptoptions.method, ["clusterMass","tmax","tfce"])} = "clusterMass"
    ptoptions.alpha (1,1) double {mustBeInRange(ptoptions.alpha, 0, 1)} = 0.05
    ptoptions.nPerm (1,1) double {mustBePositive,mustBeFinite} = 1000
    ptoptions.minClusterSize (1,1) double {mustBePositive,mustBeFinite} = 1
    ptoptions.showPlot (1,1) logical = false
end

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

% ---- Force debug -> showPlot for PERMTEST ----
ptoptions.showPlot = options.debug;

% ---- Allocate ----
permResultCell = cell(nRows, nCols);   % store structs safely
pVal = nan(nRows, nCols);
nTrialsMat = nan(nRows, nCols);

% ---- Forward permtest options ----
cargs = namedargs2cell(ptoptions);

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
        [pVal(idx), permResultCell{idx}] = permtest(A', cargs{:}); % trials x samples
        if useProg, parfor_progress; end
    end
else
    for idx = 1:numel(S)
        if isempty(S{idx}), continue; end
        A = S{idx};
        nTrialsMat(idx) = size(A,2);
        [pVal(idx), permResultCell{idx}] = permtest(A', cargs{:});
        if options.debug, pause; end
        if useProg, parfor_progress; end
    end
end
if useProg, parfor_progress(0); end


% ---- Convert permResultCell to a uniform struct array ----
% Find first non-empty result as a template
firstIdx = find(~cellfun(@isempty, permResultCell), 1, 'first');

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
pVal = min(max(pVal, 0), 1);  % clip to [0,1]
isSig = pVal < ptoptions.alpha;

% ---- Add convenience fields into permResult ----
for r = 1:nRows
    for c = 1:nCols
        if isempty(S{r,c}) || ~isfield(permResult(r,c), "tValsReal")
            permResult(r,c).pVal = nan;
            permResult(r,c).isSig = false;
            permResult(r,c).nTrials = nan;
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
                if any(isfinite(yStr))
                    fitTarget = "strength";
                else
                    fitTarget = "binary";
                end
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

                T = table(x(:), y(:), wUse(:), 'VariableNames', {'x','y','w'});
                % Use weights; for true binary, this is standard. For fractional y,
                % it's a reasonable pragmatic approximation.
                glm = fitglm(T, 'y ~ x', ...
                    'Distribution','binomial', ...
                    'Link','logit', ...
                    'Weights', T.w);

                b = glm.Coefficients.Estimate;   % [b0; b1]
                b0 = b(1); b1 = b(2);

                % If slope is non-positive, fall back to isotonic (monotone)
                if ~isfinite(b1) || b1 <= 0
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
                        thrCI = threshold_ci_from_glm(b0, b1, covB, options.criterion, options.ciNSamples, options.ciAlpha);
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
                    thrCI = threshold_ci_from_cfit(mdl, options.criterion, options.ciNSamples, options.ciAlpha);
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

function thrCI = threshold_ci_from_glm(b0, b1, covB, criterion, nSamp, ciAlpha)
% Parametric Monte Carlo CI using MVN(b, covB)
if nSamp < 100, nSamp = 100; end
if ~all(isfinite(covB(:))) || any(eig((covB+covB')/2) < -1e-12)
    thrCI = [nan nan]; return
end
R = chol((covB+covB')/2 + 1e-12*eye(2), "lower");
z = randn(2, nSamp);
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

function thrCI = threshold_ci_from_cfit(mdl, criterion, nSamp, ciAlpha)
% Approximate parametric CI for threshold from cfit using confint-derived SD.
% This is a pragmatic approximation when full covariance is not exposed.
ci = confint(mdl, 1 - ciAlpha);     % [low; high] for A,B,c,d
mu = [mdl.A, mdl.B, mdl.c, mdl.d];
sd = (ci(2,:) - ci(1,:)) ./ (2*1.96);  % approx SD under normality

P = mu + sd .* randn(nSamp, 4);

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
