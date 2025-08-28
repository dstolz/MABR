function [pVal, result] = permtest(A, options)
% permtest  Cluster-based permutation test on a 1-D series across trials.
%
%   [pVal, result] = permtest(A)
%   [pVal, result] = permtest(A, options)
%
% Description
%   Performs a two-sided, cluster-based permutation test on a time/position
%   series measured across repeated trials. For each sample (column) of A,
%   a one-sample t-test against 0 is computed across trials (rows). The t-map
%   is thresholded at a two-sided level (alpha/2 each tail), contiguous
%   supra-threshold samples form clusters, and each cluster’s mass is the sum
%   of its t-values. A null distribution of the maximum absolute cluster mass
%   is built by random trial-wise sign flips (Rademacher permutations). The
%   p-value is the +1-corrected proportion of null maxima ≥ the observed max.
%
% Input
%   A        double, size [nTrials x nSamples]. Rows are trials, columns are
%            time/position samples. Values should be baseline-corrected so
%            that 0 represents “no effect”.
%
% Name-Value Options (struct; fields shown with defaults)
%   options.nPerm          (1,1) double = 1000
%       Number of sign-flip permutations.
%   options.minClusterSize (1,1) double = 1
%       Minimum contiguous length (in samples) for clusters to be counted.
%   options.alpha          (1,1) double = 0.05
%       Family-wise alpha for the initial t-threshold (two-sided).
%   options.showPlot       (1,1) logical = false
%       If true, plots the t-map with thresholds and the permutation null.
%
% Output
%   pVal    Scalar p-value from the max-cluster-mass test with +1 correction.
%
%   result  Struct with fields (returned only if requested):
%       .tValsReal              1 x nSamples real t-statistics
%       .tThresh                Scalar t-threshold (two-sided)
%       .pos.mask               1 x nSamples logical, positive clusters
%       .neg.mask               1 x nSamples logical, negative clusters
%       .pos.mass               1 x nPosClusters cluster masses (positive)
%       .neg.mass               1 x nNegClusters cluster masses (negative)
%       .maxClusterMassReal     Scalar observed max absolute cluster mass
%       .maxClusterMassPerm     nPerm x 1 null distribution of max masses
%
% Assumptions
%   Exchangeability under sign-flips (symmetric noise across trials) and
%   temporal adjacency defining clusters along columns of A.
%
% Requirements
%   Statistics and Machine Learning Toolbox (ttest, tinv)
%   Image Processing Toolbox (bwlabel)
%
% Example
%   rng default
%   A = randn(100, 500);
%   A(:, 200:215) = A(:, 200:215) + 0.6;               % inject effect
%   opts = struct('nPerm', 2000, 'minClusterSize', 3, 'alpha', 0.05);
%   [pVal, R] = permtest(A, opts);
%
% Notes
%   Cluster mass is the sum of t-values; the test controls FWER over the
%   family of samples. This implementation uses two-sided thresholding and
%   the maximum absolute cluster mass across both positive and negative
%   clusters on each permutation.
%
% dstolz@umd.edu 2025

arguments
    A double
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
[trials, ~] = size(A);



% Real t-map on response window
[~, ~, ~, stats] = ttest(A, 0);      % across trials
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
    Aperm = A .* s;

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
end

if options.showPlot
    
    tl = use_fig_tiledlayout('permtest');

    nexttile(tl);
    plot(tValsReal, '-'); hold on
    yline(0,'-k');
    yregion(tThresh,-tThresh)

    xlim([1 numel(tValsReal)]);
    posIdx = find(posMask);
    negIdx = find(negMask);
    if ~isempty(posIdx), plot(posIdx, tValsReal(posIdx), 'sk',MarkerFaceColor = 'r'); end
    if ~isempty(negIdx), plot(negIdx, tValsReal(negIdx), 'sk',MarkerFaceCOlor = 'r'); end
    titlef('t-map (p = %.4f)', pVal);
    subtitlef('alpha = %.4f', options.alpha);
    xlabel('sample'); 
    ylabel('t-statistic');
    ylim([-1 1]*max(abs(ylim)));
    
    hold off
    grid on

    nexttile(tl);
    histogram(maxClusterMassPerm(maxClusterMassPerm>0), 100, Normalization="pdf", LineStyle="none");
    xline(maxClusterMassReal,'-r','actual','LineWidth',2);
    xlabel('max cluster mass'); ylabel('pdf'); title('Permutation null')
    grid on
end
