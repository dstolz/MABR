function [pVal, result] = permtest(A, options)
% permtest  1-D permutation test across trials with selectable correction method.
%
%   [pVal, result] = permtest(A)
%   [pVal, result] = permtest(A, options)
%
% Methods (options.method):
%   "clusterMass"  (default) classic two-sided cluster mass (sum of t) with max-|mass| null
%   "tmax"         two-sided max-|t| (FWER-corrected per sample via max-statistic null)
%   "tfce"         two-sided TFCE (threshold-free cluster enhancement) with max-TFCE null 
%                       see Mensen & Khatami, 2013
%
% Inputs
%   A: [nTrials x nSamples]
%
% Options (defaults)
%   options.nPerm          = 1000
%   options.alpha          = 0.05
%   options.minClusterSize = 1
%   options.method         = "clusterMass"  ("clusterMass"|"tmax"|"tfce")
%   options.tfce.E         = 0.5           (Extent parameter)
%   options.tfce.H         = 2.0           (Height parameter)
%   options.tfce.dh        = 0.1           (threshold step in t-units)
%   options.showPlot       = false
%
% Outputs
%   pVal   scalar global p-value for the chosen max-statistic
%   result struct with method-specific fields; for "tmax" and "tfce", returns
%          result.pCorrSample (1 x nSamples) FWER-corrected per-sample p-values
%
% Notes
% - Uses sign-flip (Rademacher) permutations, appropriate for a one-sample test.
% - For "tmax"/"tfce", "where in time" is best read from result.pCorrSample.
%
% Mensen, A., & Khatami, R. (2013). Advanced EEG analysis using 
% threshold-free cluster-enhancement and non-parametric statistics. 
% NeuroImage, 67, 111–118. https://doi.org/10.1016/j.neuroimage.2012.10.027




arguments
    A double
    options.nPerm (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1000
    options.minClusterSize (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
    options.alpha (1,1) double {mustBeGreaterThan(options.alpha,0), mustBeLessThan(options.alpha,1)} = 0.05
    options.method (1,1) string {mustBeMember(options.method, ["clusterMass","tmax","tfce"])} = "clusterMass"
    options.tfce struct = struct("E",0.5,"H",2.0,"dh",0.1)
    options.showPlot (1,1) logical = false
end

pVal = NaN;
result = struct();
if isempty(A), return; end

[trials, nSamples] = size(A);
if trials < 2 || nSamples < 1, return; end

% --- Fast analytic one-sample t across trials ---
n = trials;
sumA   = sum(A, 1);
sumSqA = sum(A.^2, 1);

varA = (sumSqA - (sumA.^2)/n) ./ (n - 1);
seA  = sqrt(varA ./ n);

tValsReal = (sumA ./ n) ./ seA;
tValsReal(~isfinite(tValsReal)) = 0;

tThresh = tinv(1 - options.alpha/2, n - 1);

% --- Compute observed max-statistic (depends on method) ---
switch options.method
    case "clusterMass"
        [massPos, massNeg] = cluster_masses_1d(tValsReal, tThresh, options.minClusterSize);
        maxStatReal = max([0, massPos(:).', abs(massNeg(:).')]);  % max abs mass
        maxStatReal = maxStatReal(1);

    case "tmax"
        maxStatReal = max(abs(tValsReal));

    case "tfce"
        tfcePosReal = tfce_1d(max(tValsReal,0), options.tfce.E, options.tfce.H, options.tfce.dh, options.minClusterSize);
        tfceNegReal = tfce_1d(max(-tValsReal,0), options.tfce.E, options.tfce.H, options.tfce.dh, options.minClusterSize);
        tfceAbsReal = max(tfcePosReal, tfceNegReal);
        maxStatReal = max(tfceAbsReal);
end

% --- Permutations: sign flips; compute max-statistic null ---
maxStatPerm = zeros(options.nPerm, 1);

batchSize = min(options.nPerm, 512);
p0 = 0;

while p0 < options.nPerm
    nb = min(batchSize, options.nPerm - p0);

    s = 2*(rand(trials, nb) > 0.5) - 1;     % trials x nb
    sumPerm = (s.' * A);                    % nb x nSamples

    varPerm = (sumSqA - (sumPerm.^2)/n) ./ (n - 1);
    sePerm  = sqrt(varPerm ./ n);
    tBlock  = (sumPerm ./ n) ./ sePerm;
    tBlock(~isfinite(tBlock)) = 0;

    for j = 1:nb
        tPerm = tBlock(j, :);

        switch options.method
            case "clusterMass"
                [mPos, mNeg] = cluster_masses_1d(tPerm, tThresh, options.minClusterSize);
                if isempty(mPos) && isempty(mNeg)
                    maxStatPerm(p0+j) = 0;
                else
                    maxStatPerm(p0+j) = max([0, mPos(:).', abs(mNeg(:).')]);
                end

            case "tmax"
                maxStatPerm(p0+j) = max(abs(tPerm));

            case "tfce"
                tfcePos = tfce_1d(max(tPerm,0),  options.tfce.E, options.tfce.H, options.tfce.dh, options.minClusterSize);
                tfceNeg = tfce_1d(max(-tPerm,0), options.tfce.E, options.tfce.H, options.tfce.dh, options.minClusterSize);
                maxStatPerm(p0+j) = max(max(tfcePos, tfceNeg));
        end
    end

    p0 = p0 + nb;
end

% Global p-value (+1 correction) for the max-statistic
pVal = (1 + sum(maxStatPerm >= maxStatReal)) / (options.nPerm + 1);

% --- Fill result struct (method-specific) ---
result.method   = options.method;
result.tValsReal = tValsReal;
result.tThresh   = tThresh;
result.maxStatReal = maxStatReal;
result.maxStatPerm = maxStatPerm;

switch options.method
    case "clusterMass"
        % For clusterMass, keep cluster-level outputs (like your original)
        posMask = tValsReal >  tThresh;
        negMask = tValsReal < -tThresh;

        result.pos.mask = posMask;
        result.neg.mask = negMask;
        result.pos.mass = massPos;
        result.neg.mass = massNeg;

        % Cluster p-values from max-statistic null
        pPos = zeros(size(massPos));
        for k = 1:numel(massPos)
            pPos(k) = (1 + sum(maxStatPerm >= abs(massPos(k)))) / (options.nPerm + 1);
        end
        pNeg = zeros(size(massNeg));
        for k = 1:numel(massNeg)
            pNeg(k) = (1 + sum(maxStatPerm >= abs(massNeg(k)))) / (options.nPerm + 1);
        end
        result.pos.pCorr = pPos;
        result.neg.pCorr = pNeg;

    case "tmax"
        % Per-sample FWER-corrected p-values using max-|t| null
        result.pCorrSample = fwer_p_from_maxnull(abs(tValsReal), maxStatPerm);
        result.sigMask = result.pCorrSample < options.alpha;

    case "tfce"
        % Per-sample FWER-corrected p-values using max-TFCE null
        result.tfcePosReal = tfcePosReal;
        result.tfceNegReal = tfceNegReal;
        result.tfceAbsReal = tfceAbsReal;
        result.pCorrSample = fwer_p_from_maxnull(tfceAbsReal, maxStatPerm);
        result.sigMask = result.pCorrSample < options.alpha;
end

% --- Optional quick plot ---
if options.showPlot
    tl = tiledlayout(1,2);

    nexttile(tl);
    plot(tValsReal, '-'); hold on
    yline(0,'-k');
    yregion([-1 1]*tThresh); 
    title(sprintf('%s (global p = %.4g)', options.method, pVal));
    xlabel('sample'); ylabel('t');
    grid on

    nexttile(tl);
    histogram(maxStatPerm(maxStatPerm>0), 100, "Normalization","pdf", "LineStyle","none");
    xline(maxStatReal,'-r','actual','LineWidth',2);
    xlabel('max-statistic'); ylabel('pdf'); title('Permutation null');
    grid on
end

end

% ===================== helpers =====================

function [massPos, massNeg] = cluster_masses_1d(tVals, tThresh, minSz)
% Returns cluster masses for t > +tThresh and t < -tThresh, using 1D run-length parsing.
posMask = tVals >  tThresh;
negMask = tVals < -tThresh;

massPos = cluster_sum_from_mask(tVals,  posMask, minSz);
massNeg = cluster_sum_from_mask(tVals,  negMask, minSz); % will be negative values
end

function masses = cluster_sum_from_mask(x, mask, minSz)
masses = [];
if ~any(mask), return; end

d = diff([false, mask, false]);
starts = find(d==1);
ends   = find(d==-1) - 1;

lens = ends - starts + 1;
keep = lens >= minSz;
starts = starts(keep);
ends   = ends(keep);

masses = zeros(1, numel(starts));
for k = 1:numel(starts)
    masses(k) = sum(x(starts(k):ends(k)));
end
end

function tfce = tfce_1d(xNonneg, E, H, dh, minSz)
% Simple 1D TFCE for a nonnegative map.
% Integrates over thresholds h with step dh; at each h, finds clusters where x>h and
% adds (extent^E)*(h^H)*dh to all samples in those clusters.
%
% xNonneg: 1 x nSamples, must be >=0
tfce = zeros(size(xNonneg));
mx = max(xNonneg);
if mx <= 0 || dh <= 0, return; end

hs = dh:dh:mx;
for h = hs
    mask = xNonneg > h;
    if ~any(mask), continue; end

    d = diff([false, mask, false]);
    starts = find(d==1);
    ends   = find(d==-1) - 1;

    lens = ends - starts + 1;
    keep = lens >= minSz;
    starts = starts(keep);
    ends   = ends(keep);
    lens   = lens(keep);

    if isempty(starts), continue; end

    % TFCE increment for each cluster at this threshold
    incPerCluster = (lens.^E) .* (h.^H) .* dh;

    for k = 1:numel(starts)
        tfce(starts(k):ends(k)) = tfce(starts(k):ends(k)) + incPerCluster(k);
    end
end
end

function pCorr = fwer_p_from_maxnull(statPerSample, nullMax)
% FWER-corrected p per sample using max-statistic null:
% p = (1 + #{nullMax >= stat}) / (nPerm+1)
nPerm = numel(nullMax);
pCorr = zeros(size(statPerSample));

% Chunk to avoid large temporary matrices for big nSamples
chunk = 2000;
nS = numel(statPerSample);
for i0 = 1:chunk:nS
    i1 = min(nS, i0+chunk-1);
    v = statPerSample(i0:i1);
    % count perms with max >= v (vectorized via implicit expansion)
    c = sum(nullMax >= v, 1);
    pCorr(i0:i1) = (1 + c) / (nPerm + 1);
end
end
