function [pVal, result] = permtest(A, respWin, options)
% PERMTEST  Perform a cluster-based permutation t-test on time-series data.
%
%   pVal = PERMTEST(A, preWin, respWin) performs a cluster-based permutation
%   t-test on the input data matrix A, comparing the post-stimulus window
%   defined by respWin to zero.
%
%   [pVal, result] = PERMTEST(A, preWin, respWin, nPerm, minClusterSize, alpha)
%   specifies additional parameters. See input arguments for details.
%
%   Inputs:
%     A             - [timepoints x trials] data matrix
%     respWin       - logical vector
% 
%   Aditional Input Options: Name = Value
%     nPerm         - Number of permutations (default = 1000)
%     minClusterSize- Minimum cluster size (default = 1)
%     alpha         - Significance level (default = 0.05)
%     showPlot      - Boolean to show diagnostic plots (default = false)
%     approach      - Permute with pre-event "noise" or "flip" (default) the response
%     preWin        - logical vector must be specified if using "noise" approach
%
%   Outputs:
%     pVal          - P-value from permutation test
%     result        - Struct with fields: t-values, significance, and permutation stats

arguments
    A double
    respWin logical
    options.preWin = [];
    options.nPerm (1,1) double {mustBePositive} = 1000
    options.minClusterSize (1,1) double {mustBeNonnegative} = 1
    options.alpha (1,1) double {mustBeGreaterThanOrEqual(options.alpha,0), mustBeLessThanOrEqual(options.alpha,1)} = 0.05
    options.showPlot (1,1) logical = false
    options.approach (1,1) string {mustBeMember(options.approach,["noise","flip"])} = "noise";
end

structToCallerVars(options);
alpha = options.alpha; % also a function name

pVal = NaN;
result = struct();

if isempty(A), return; end

respWin = respWin(:)';


switch approach 
    case "noise"
        assert(~isempty(preWin), '`preWin` must be specified if using the "noise" approach')

    case "flip"
        assert(isempty(preWin), '`preWin` is not used with the "flip" approach')
end


A = A';  % A must be [trials x timepoints]
nTrials = size(A, 1);

% One-sample t-test on post-stimulus window
[~, ~, ~, stats] = ttest(A(:, respWin), 0, 'Alpha', alpha);
tValsReal = stats.tstat;
tThresh = tinv(1 - alpha/2, nTrials - 1);

% Identify significant timepoints
isSig = abs(tValsReal) > tThresh;
clusters = bwconncomp(isSig, 4);
n = cellfun(@numel, clusters.PixelIdxList);
ind = n < minClusterSize;
clusters.PixelIdxList(ind) = [];
clusters.NumObjects = sum(~ind);
if clusters.NumObjects > 0
    clusterStatsReal = cellfun(@(x) sum(abs(tValsReal(x))), clusters.PixelIdxList);
    maxClusterStatReal = max(clusterStatsReal);
    % maxClusterStatReal = sum(abs(tValsReal(isSig)));
else
    clusterStatsReal = [];
    maxClusterStatReal = 0;
end

% Permutation testing
maxClusterStatsPerm = zeros(nPerm, 1);
for p = 1:nPerm
    ind = rand(nTrials, 1) > 0.5;
    Aperm = A;
    switch approach
        case "noise"
            Aperm(ind, preWin) = A(ind, respWin);
            Aperm(ind, respWin) = A(ind, preWin);
        case "flip"
            Aperm(ind, :) = -Aperm(ind, :);
    end

    [~, ~, ~, statsPerm] = ttest(Aperm(:, respWin), 0, 'Alpha', alpha);
    tValsPerm = statsPerm.tstat;

    isSigPerm = abs(tValsPerm) > tThresh;
    clustersPerm = bwconncomp(isSigPerm, 4);
    n = cellfun(@numel, clustersPerm.PixelIdxList);
    ind = n < minClusterSize;
    clustersPerm.PixelIdxList(ind) = [];
    clustersPerm.NumObjects = sum(~ind);
    if clustersPerm.NumObjects > 0
        clusterStatsPerm = cellfun(@(x) sum(abs(tValsPerm(x))), clustersPerm.PixelIdxList);
        maxClusterStatsPerm(p) = max(clusterStatsPerm);
        % maxClusterStatsPerm(p) = sum(abs(tValsPerm(isSigPerm)));
    end
end

% Compute p-value
pVal = mean(maxClusterStatsPerm >= maxClusterStatReal);

% Return results
if nargout == 2
    result.clusters = clusters;
    result.clusterStatsReal = clusterStatsReal;
    result.maxClusterStatReal = maxClusterStatReal;
    result.tValsReal = tValsReal;
    result.tThresh = tThresh;
    result.isSig = isSig;
    result.maxClusterStatsPerm = maxClusterStatsPerm;
end


if showPlot
    use_fig("perm");
    tl = tiledlayout('flow');

    nexttile(tl);
    plot(tValsReal, 'k-');
    hold on
    x = find(isSig);
    plot(x,sign(tValsReal(x)).*max(abs(ylim)),'sr',MarkerFaceColor='r');
    hold off
    yline(tThresh, '--r');
    yline(-tThresh, '--r');
    titlef('t-values across time (p = %.4f)', pVal);
    subtitle('respWin only');
    xlabel('sample'); ylabel('t-statistic');

    nexttile(tl);
    histogram(maxClusterStatsPerm(maxClusterStatsPerm>0),100,Normalization="pdf");
    xline(maxClusterStatReal,'-r',LineWidth = 3)
    axis tight
    grid on
    ylabel('pdf')
    xlabel('cluster magnitude')
    title('permuted distribution')
end

