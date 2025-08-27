function [pVal, result] = permtest(A, respWin, options)
% PERMTEST  Cluster-based permutation t-test with baseline correction & sign-flips.
%
%   pVal = PERMTEST(A, respWin, options) tests whether the response window
%   contains timepoints with nonzero mean across trials using a cluster-based
%   permutation on the signed t-map.
%
%   Inputs
%     A         - [trials x timepoints] data matrix
%     respWin   - logical vector (length = # timepoints) marking response window
%
%   Name-Value Options
%     preWin          - logical vector for baseline window (REQUIRED)
%     nPerm           - number of permutations (default = 1000)
%     minClusterSize  - minimum contiguous samples per cluster (default = 1)
%     alpha           - cluster-defining two-sided alpha for t-threshold (default = 0.05)
%     showPlot        - show quick diagnostic plots (default = false)
%
%   Method (brief)
%     1) Baseline-correct each trial by subtracting its mean over preWin.
%     2) Compute one-sample t-statistic vs 0 at each timepoint in respWin.
%     3) Form clusters separately for positive (t>tThr) and negative (t<-tThr)
%        runs; cluster mass = sum of t-values in the run.
%     4) Build a max-cluster-mass null by trial-wise random sign-flips of the
%        baseline-corrected data; recompute steps (2)-(3) each permutation.
%     5) pVal = (1 + #{perm max ≥ real max}) / (nPerm + 1).
%
%   Outputs
%     pVal    - permutation p-value for the maximum cluster mass
%     result  - struct with fields:
%                 .tValsReal              (1 x sum(respWin))
%                 .tThresh
%                 .pos.mask, .neg.mask    (logical masks over respWin)
%                 .pos.mass, .neg.mass    (cluster masses per run)
%                 .maxClusterMassReal
%                 .maxClusterMassPerm     (nPerm x 1)
%                 .respWin, .preWin
%
% dstolz@umd.edu 2025

arguments
    A double
    respWin logical
    options.preWin logical = []
    options.nPerm (1,1) double {mustBeInteger,mustBePositive} = 1000
    options.minClusterSize (1,1) double {mustBeInteger,mustBeNonnegative} = 1
    options.alpha (1,1) double {mustBeGreaterThanOrEqual(options.alpha,0), mustBeLessThanOrEqual(options.alpha,1)} = 0.05
    options.showPlot (1,1) logical = false
end

pVal = NaN;
result = struct();

if isempty(A)
    return
end

% Dimensions & window checks
[trials, timepoints] = size(A);
respWin = respWin(:).';
assert(numel(respWin)==timepoints, 'respWin length must match size(A,2)');
assert(any(respWin), 'respWin must contain at least one true sample');

preWin = options.preWin;
if isempty(preWin), preWin = ~respWin; end
% assert(~isempty(preWin) && islogical(preWin) && numel(preWin)==timepoints && any(preWin), ...
%     '`preWin` is required and must match size(A,2)');

% Baseline-correct each trial by its mean over preWin
b = mean(A(:, preWin), 2, 'omitnan');
A_bc = A - b;
A_bc = A_bc(:, respWin);

% Real t-map on response window
[~, ~, ~, stats] = ttest(A_bc, 0);      % across trials
tValsReal = stats.tstat;                            % 1 x sum(respWin)
tThresh = tinv(1 - options.alpha/2, trials - 1);

% Build signed clusters (positive and negative), apply minClusterSize
posMask = tValsReal >  tThresh;
negMask = tValsReal < -tThresh;

% Positive clusters
if any(posMask)
    [Lpos, npos] = bwlabel(posMask);                       % Image Processing Toolbox
    lenPos = accumarray(Lpos(Lpos>0).', 1, [npos,1]);
    keepPos = find(lenPos >= options.minClusterSize);
    massPos = zeros(1, numel(keepPos));
    for k = 1:numel(keepPos)
        massPos(k) = sum(tValsReal(Lpos == keepPos(k)));
    end
else
    massPos = [];
end

% Negative clusters
if any(negMask)
    [Lneg, nneg] = bwlabel(negMask);
    lenNeg = accumarray(Lneg(Lneg>0).', 1, [nneg,1]);
    keepNeg = find(lenNeg >= options.minClusterSize);
    massNeg = zeros(1, numel(keepNeg));
    for k = 1:numel(keepNeg)
        massNeg(k) = sum(tValsReal(Lneg == keepNeg(k)));   % negative masses
    end
else
    massNeg = [];
end

maxClusterMassReal = 0;
if ~isempty(massPos)
    maxClusterMassReal = max(maxClusterMassReal, max(massPos));
end
if ~isempty(massNeg)
    maxClusterMassReal = max(maxClusterMassReal, max(abs(massNeg)));
end

% Permutations: trial-wise sign flips of baseline-corrected data
maxClusterMassPerm = zeros(options.nPerm,1);
for p = 1:options.nPerm
    s = 2*(rand(trials,1)>0.5) - 1;           % +/-1
    Aperm = A_bc .* s;

    [~, ~, ~, statsPerm] = ttest(Aperm, 0);
    tPerm = statsPerm.tstat(:).';

    posP = tPerm >  tThresh;
    negP = tPerm < -tThresh;

    maxMass = 0;

    if any(posP)
        [Lp, np] = bwlabel(posP);
        lenP = accumarray(Lp(Lp>0).', 1, [np,1]);
        keepP = find(lenP >= options.minClusterSize);
        for k = 1:numel(keepP)
            maxMass = max(maxMass, sum(tPerm(Lp == keepP(k))));
        end
    end

    if any(negP)
        [Ln, nn] = bwlabel(negP);
        lenN = accumarray(Ln(Ln>0).', 1, [nn,1]);
        keepN = find(lenN >= options.minClusterSize);
        for k = 1:numel(keepN)
            maxMass = max(maxMass, abs(sum(tPerm(Ln == keepN(k)))));
        end
    end

    maxClusterMassPerm(p) = maxMass;
end

% p-value with +1 correction
pVal = (1 + sum(maxClusterMassPerm >= maxClusterMassReal)) / (options.nPerm + 1);

% Outputs
if nargout > 1
    result.tValsReal = tValsReal;
    result.tThresh = tThresh;
    result.pos.mask = posMask;
    result.neg.mask = negMask;
    result.pos.mass = massPos;
    result.neg.mass = massNeg;
    result.maxClusterMassReal = maxClusterMassReal;
    result.maxClusterMassPerm = maxClusterMassPerm;
    result.respWin = respWin;
    result.preWin = preWin;
end

if options.showPlot
    
    tl = use_fig_tiledlayout('permtest');

    nexttile(tl);
    plot(tValsReal, '-'); hold on
    yline(0,'-k');
    yline(tThresh, '--'); yline(-tThresh, '--');
    xlim([1 numel(tValsReal)]);
    posIdx = find(posMask);
    negIdx = find(negMask);
    if ~isempty(posIdx), plot(posIdx, tValsReal(posIdx), 'sk',MarkerFaceColor = 'r'); end
    if ~isempty(negIdx), plot(negIdx, tValsReal(negIdx), 'sk',MarkerFaceCOlor = 'r'); end
    titlef('t-map (p = %.4f)', pVal);
    subtitlef('alpha = %.4f', options.alpha);
    xlabel('sample in respWin'); 
    ylabel('t-statistic');
    ylim([-1 1]*max(abs(ylim)));
    
    hold off
    grid on

    nexttile(tl);
    histogram(maxClusterMassPerm(maxClusterMassPerm>0), 100, Normalization="pdf");
    xline(maxClusterMassReal,'-','LineWidth',2);
    xlabel('max cluster mass'); ylabel('pdf'); title('Permutation null')
    grid on
end
