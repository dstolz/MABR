function [thresh_hat,permResult,logMdls] = abrPermutationThreshold(S, U, winIdx, Fs, options, ptoptions)
% abrPermutationThreshold - Perform cluster-based permutation testing and estimate ABR thresholds.
%
% Syntax:
%   [thresh_hat, permResult, logMdls] = abrPermutationThreshold(S, U, winIdx, Fs, options, ptoptions)
%
% Description:
%   Performs cluster-based permutation testing on auditory brainstem response (ABR) data
%   to detect significant responses within a specified time window, and estimates thresholds
%   using logistic model fitting or minimum significant level selection.
%
% Inputs:
%   S               - cell array (nLevels × nFreqs) of ABR data matrices (trials × timepoints).
%   U               - struct with fields:
%                       .frequency - vector of stimulus frequencies (Hz).
%                       .level     - vector of stimulus levels (dB SPL).
%   winIdx          - vector of sample indices defining the full recording window.
%   Fs              - sampling frequency in Hz.
%   options         - struct of function-level options:
%                       .useParallel    - logical; run permutation tests in parallel (default: true).
%                       .debug          - logical; enable debug mode with pausing and plots (default: false).
%                       .responseWindow - [tMin tMax] in ms for post-stimulus analysis window (default: [1 9]).
%                       .thresholdType  - 'logistic' or 'minimum' threshold estimation (default: 'logistic').
%   ptoptions       - struct of permutation-test options:
%                       .alpha           - significance level (0 < alpha < 1, default: 0.05).
%                       .nPerm           - number of permutations (positive integer, default: 1000).
%                       .minClusterSize  - minimum cluster size for inclusion (>=1, default: 1).
%                       .approach        - 'flip' (sign-flipping) or 'noise' (pre-vs-post noise resampling) (default: 'flip').
%                       .showPlot        - logical; visualize real and permuted cluster statistics (default: inherits options.debug).
%
% Outputs:
%   thresh_hat      - 1 × nFreqs vector of estimated ABR thresholds (dB SPL).
%   permResult      - struct array (nLevels*nFreqs) with fields:
%                       .clusters, .clusterStatsReal, .maxClusterStatReal, .tValsReal,
%                       .tThresh, .isSig, .maxClusterStatsPerm.
%   logMdls         - 1 × nFreqs cell array of fitted logistic model objects (if thresholdType=='logistic'; else empty).
%
% Theory of Operation:
%   The function conducts a cluster-based permutation test as follows:
%     1. For each sound level and frequency, compute real t-values comparing activity within
%        the post-stimulus response window to baseline.
%     2. Identify temporal clusters of contiguous samples exceeding a critical t-threshold
%        determined from the t-distribution at the specified alpha level.
%     3. Measure cluster statistics (sum of t-values) for each cluster.
%     4. Generate a null distribution by permuting labels (sign-flipping or resampling noise)
%        nPerm times, recomputing max cluster statistics for each permutation.
%     5. Determine significance by comparing real cluster statistics to the null distribution.
%   Detected significant responses (p < alpha) across levels yield a binary detection matrix,
%   which is either fit with a logistic psychometric function (estimating the 50% threshold),
%   or thresholded by the first level showing significance (minimum criterion).
%
% DJS 2025

arguments
    S cell
    U
    winIdx double
    Fs (1,1) double {mustBePositive}
    options.useParallel (1,1) logical = true;
    options.debug (1,1) logical = false;
    options.responseWindow (1,2) double {mustBeFinite} = [1 9]; % response window in ms
    options.thresholdType (1,1) string {mustBeMember(options.thresholdType,["logistic","minimum"])} = "logistic";
    ptoptions.alpha (1,1) double {mustBeInRange(ptoptions.alpha, 0, 1)} = 0.05
    ptoptions.nPerm (1,1) double {mustBePositive,mustBeFinite} = 1000
    ptoptions.minClusterSize (1,1) double {mustBePositive,mustBeFinite} = 1;
    ptoptions.approach (1,1) string {mustBeMember(ptoptions.approach,["noise","flip"])} = "flip";
    ptoptions.showPlot (1,1) logical = false;
end

ptoptions.showPlot = options.debug;
structToCallerVars(options);


nFreq = length(U.frequency);

tvec = winIdx ./ Fs;

% Define pre- and post-stimulus windows
if ptoptions.approach == "noise"
    ptoptions.preWin  = tvec >= -responseWindow(2)/1000 & tvec <= -responseWindow(1)/1000;
end
postWin = tvec >=  responseWindow(1)/1000 & tvec <=  responseWindow(2)/1000;


cargs = namedargs2cell(ptoptions);


permResult(size(S,1),size(S,2)) = struct('clusters',[],'clusterStatsReal',[],'maxClusterStatReal',[],'tValsReal',[],'tThresh',[],'isSig',[],'maxClusterStatsPerm',[]);
pVal = nan(size(S));

% Run permutation tests
fprintf('Permutation tests\n')
parfor_progress(numel(S));
if options.useParallel && ~options.debug
    parfor i = 1:numel(S)
        if isempty(S{i}), continue; end
        [pVal(i), permResult(i)] = permtest(S{i}, postWin,cargs{:});
        parfor_progress;
    end
else
    for i = 1:numel(S)
        if isempty(S{i}), continue; end
        [pVal(i), permResult(i)] = permtest(S{i}, postWin,cargs{:});
        if options.debug, pause; end
        parfor_progress;
    end
end
parfor_progress(0);


fprintf('Estimating thresholds\n')
pVal = max(pVal, 0);
isSig = pVal < ptoptions.alpha;
thresh_hat = nan(1, nFreq);

switch (thresholdType)
    case "logistic"
        logisticModel = fittype('A / (1 + exp(-B*(x - C)))', ...
            'independent', 'x', ...
            'coefficients', {'A', 'B', 'C'});
        % invLogFnc = @(A,B,C,y) C - (1/B) * log((A/y) - 1);
        lowerBounds = [0, 0, -Inf];
        upperBounds = [Inf, Inf, Inf];

        % Estimate thresholds for each frequency
        logMdls = cell(1,nFreq);
        for f = 1:nFreq
            y = double(isSig(:, f));
            i = ~isnan(y);
            x = U.level(i);
            y = y(i);

            [x, y] = prepareCurveData(x, y);
            startPoints = [max(y), 1, mean(x)];

            logMdls{f} = fit(x, y, logisticModel, ...
                'StartPoint', startPoints, ...
                'Lower', lowerBounds, ...
                'Upper', upperBounds);

            thresh_hat(f) = logMdls{f}.C;
        end
    case "minimum"
        for f = 1:nFreq
            idx = find(isSig(:,f),1,'first');
            if isempty(idx)
                thresh_hat(f) = inf;
            else
                thresh_hat(f) = U.level(idx);
            end
        end
end

% no response at presented sound levels
i = thresh_hat > max(U.level);
thresh_hat(i) =  max(U.level)+5;

% i = thresh_hat < min(U.level);
% thresh_hat(i) = min(U.level);


% pin to nearest level greater than threshold
% for i = 1:length(thresh_hat)
%     idx = find(U.level >= thresh_hat(i),1);
%     if isempty(idx), continue; end
%     thresh_hat(i) = U.level(idx);
% end