function [thresh_hat,permResult,mdls] = abrPermutationThreshold(S, U, winIdx, Fs, options, ptoptions)
% abrPermutationThreshold - Perform cluster-based permutation testing and estimate ABR thresholds.
%
% Syntax:
%   [thresh_hat, permResult, mdls] = abrPermutationThreshold(S, U, winIdx, Fs, options, ptoptions)
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
%                       .nearestLevel   - logical; pin estimated threshold to the nearest presented level (default: true)
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
%   mdls         - 1 × nFreqs cell array of fitted logistic model objects (if thresholdType=='logistic'; else empty).
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
    options.useParallel (1,1) logical = false;
    options.debug (1,1) logical = false;
    options.responseWindow (1,2) double {mustBeFinite} = [1 9]; % response window in ms
    options.thresholdType (1,1) string {mustBeMember(options.thresholdType,["logistic","minimum"])} = "logistic";
    options.nearestLevel (1,1) logical = true;
    ptoptions.alpha (1,1) double {mustBeInRange(ptoptions.alpha, 0, 1)} = 0.05
    ptoptions.nPerm (1,1) double {mustBePositive,mustBeFinite} = 1000
    ptoptions.minClusterSize (1,1) double {mustBePositive,mustBeFinite} = 1;
    ptoptions.showPlot (1,1) logical = false;
end

ptoptions.showPlot = options.debug;
structToCallerVars(options);


nFreq = length(U.frequency);

tvec = winIdx ./ Fs;

% % Define pre- and post-stimulus windows
% if ptoptions.approach == "noise"
%     ptoptions.preWin  = tvec >= -responseWindow(2)/1000 & tvec <= -responseWindow(1)/1000;
% end
postWin = tvec >=  responseWindow(1)/1000 & tvec <=  responseWindow(2)/1000;


cargs = namedargs2cell(ptoptions);


permResult(size(S,1),size(S,2)) = struct('tValsReal',[],'tThresh',[],'pos',[],'neg',[],'maxClusterMassReal',[],'maxClusterMassPerm',[],'respWin',[],'preWin',[]);
% permResult(size(S,1),size(S,2)) = struct('clusters',[],'clusterStatsReal',[],'maxClusterStatReal',[],'tValsReal',[],'tThresh',[],'isSig',[],'maxClusterStatsPerm',[]);
pVal = nan(size(S));

% Run permutation tests
parfor_progress(numel(S),'Permutation tests');
if options.useParallel && ~options.debug
    parfor i = 1:numel(S)
        if isempty(S{i}), continue; end
        [pVal(i), permResult(i)] = permtest(S{i}', postWin,cargs{:});
        parfor_progress;
    end
else
    for i = 1:numel(S)
        if isempty(S{i}), continue; end
        [pVal(i), permResult(i)] = permtest(S{i}', postWin,cargs{:});
        if options.debug, pause; end
        parfor_progress;
    end
end
parfor_progress(0);


i = isnan(pVal);
pVal = max(pVal, 0);
pVal(i) = nan;
isSig = pVal < ptoptions.alpha;
thresh_hat = nan(1, nFreq);
mdls = cell(1,nFreq);

parfor_progress(nFreq,'Estimating thresholds');
switch (thresholdType)
    case "logistic"


        % Estimate thresholds for each frequency
        for f = 1:nFreq

            % s = cellfun(@sum,{permResult(:,f).clusterStatsReal});
            y = double(isSig(:, f));

            i = ~isnan(y);
            x = U.soundLevel(i);
            y = y(i);


            % x: n×1 numeric, y: n×1 (0/1)
            mdl = fitglm(x(:), y(:), 'Distribution','binomial', 'Link','logit', ...
                'LikelihoodPenalty','jeffreys-prior');   % Firth logistic

            xg = linspace(min(x), max(x), 200)';
            pg = predict(mdl, xg);

            coef = mdl.Coefficients.Estimate;
            if all(coef<0)
                thresh_hat(f) = max(x)+5;
            else
                thresh_hat(f) = -coef(1)/coef(2);   % x where P≈0.5
            end


            if options.debug
                use_fig('abrPermutationThreshold');
                plot(x,y,'ob');
                hold on
                plot(xg,pg,'-k')
                stem(thresh_hat(f),0.5,'-r')
                hold off
                grid on
                ylim([0 1])
                titlef('%d Hz -- C = %.3f',U.frequency(f),thresh_hat(f))
            end

            parfor_progress;
        end
   


    case "minimum"
        for f = 1:nFreq
            idx = find(isSig(:,f),1,'first');
            if isempty(idx)
                thresh_hat(f) = inf;
            else
                thresh_hat(f) = U.soundLevel(idx);
            end
            parfor_progress;
        end
end
parfor_progress(0);

% no response at presented sound levels
i = thresh_hat > max(U.soundLevel);
thresh_hat(i) =  max(U.soundLevel)+5;

% i = thresh_hat < min(U.soundLevel);
% thresh_hat(i) = min(U.soundLevel);

if options.nearestLevel
    % pin to nearest level greater than threshold
    for i = 1:length(thresh_hat)
        idx = find(U.soundLevel >= thresh_hat(i),1);
        if isempty(idx), continue; end
        thresh_hat(i) = U.soundLevel(idx);
    end
end