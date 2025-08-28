function [S, artInd] = rejectArtifacts(S, option)
% REJECTARTIFACTS  Remove artifact trials using isoutlier on a per-trial feature.
%
% Syntax
%   S = rejectArtifacts(S)
%   [S, artInd] = rejectArtifacts(S, Name, Value)
%
% Description
%   For each element of S (each a [samples x trials] matrix), this function
%   computes a per-trial feature within a response window, detects outlier
%   trials using isoutlier with a user-selectable METHOD and parameters, and
%   removes those trials. Logical indices of removed trials are returned.
%
% Inputs
%   S            Cell array of ABR response matrices sized [samples x trials].
%                A single numeric matrix is also accepted and handled as 1x1 cell.
%                If S is a cell array, then each cell is processed independently.
%                Each element of S must be a matrix, with trials in columns.
%
% Name-Value Options
%   'respInd'    Logical vector. Samples that define the response window.
%                Default: [] (use all samples).
%
%   'feature'    "rms" | "std" | "meanabs" | "peak2peak" | "posPeak" | "negPeak" | "absPeak"
%                Trial-level feature computed within the response window.
%                Default: "absPeak".
%
%   'rmMethod'   "median" | "mean" | "quartiles" | "gesd" | "movmedian" | "movmean"
%                Method passed to isoutlier. Default: "quartiles".
%
%   'rmArgs'     struct. Additional name-value arguments forwarded to isoutlier.
%                Common fields include:
%                  - ThresholdFactor  : scalar (median/mean/quartiles)
%                  - MaxNumOutliers   : integer (gesd)
%                  - Alpha            : scalar in (0,1) (gesd)
%                Example: rmArgs = struct('ThresholdFactor',2,'MaxNumOutliers',10)
%                Default: struct().
%
%   'useParallel' Logical. If true, uses PARFOR across cells. Default: false.
%
%   'plot'       Logical. If true, shows a diagnostic figure with the feature
%                histogram and any reported thresholds. Default: false.
%
%   'verbose'    Logical. Print per-cell artifact counts in serial mode.
%                Default: false.
%
% Outputs
%   S            Cleaned ABR responses with artifact trials removed per cell.
%                Shape matches input: cell-in returns cell-out; matrix-in returns matrix.
%
%   artInd       Cell array of logical index vectors flagging rejected trials
%                for each cell. For a matrix input, artInd is a 1x1 cell.
%
% Example
%   % Use GESD with custom limits
%   rmArgs = struct('MaxNumOutliers',8,'Alpha',0.005);
%   [S, artInd] = rejectArtifacts(S,'respInd',respInd,'feature','rms', ...
%                                 'rmMethod','gesd','rmArgs',rmArgs,'plot',true);
%
% See also isoutlier

arguments
    S
    option.respInd (1,:) logical = []
    option.feature (1,1) string {mustBeMember(option.feature, ["rms","std","meanabs","peak2peak","posPeak","negPeak","absPeak"])} = "absPeak"
    option.rmMethod (1,1) string {mustBeMember(option.rmMethod, ["median","mean","quartiles","gesd","grubbs"])} = "median"
    option.rmArgs struct = struct()
    option.useParallel (1,1) logical = false
    option.plot (1,1) logical = false
    option.verbose (1,1) logical = false
end

if ~iscell(S)
    [S, artInd] = rejectArtifacts({S}, option);
    S = S{1};
    artInd = artInd{1};
    return
end

nS = numel(S);
useParfor = option.useParallel && nS > 1;

artInd = cell(size(S));

parfor_progress(nS, 'Rejecting artifacts');
if useParfor
    parfor i = 1:nS
        artInd{i} = localReject(S{i}, option);
        parfor_progress;
    end
else
    for i = 1:nS
        artInd{i} = localReject(S{i}, option);
        parfor_progress;
    end
end
parfor_progress(0);


S = cellfun(@(a,b) a(:,~b), S, artInd, 'UniformOutput', false);

end % main function

% -------------------------------------------------------------------------
function artInd = localReject(y, option)
    if isempty(y)
        artInd = [];
        return
    end

    if isempty(option.respInd)
        respInd = true(size(y,1),1);
    else
        respInd = option.respInd;
    end

    y = y(respInd,:);
    f = computeFeature(y, option.feature);

    nv = namedargs2cell(option.rmArgs);

    if isempty(nv)
        [artInd, lb, ub] = isoutlier(f, option.rmMethod);
    else
        [artInd, lb, ub] = isoutlier(f, option.rmMethod, nv{:});
    end


    if option.plot
        tl = use_fig_tiledlayout;

        nexttile;
        histogram(f, 64, Normalization="pdf");
        if ~isempty(lb), xline(lb, '--r'); end
        if ~isempty(ub), xline(ub, '--r'); end
        grid on;

        nexttile;
        plot(mean(y(:,~artInd),2), '-k', LineWidth=2);
        hold on;
        plot(y(:,artInd));
        hold off;
        axis tight;
        grid on;

        titlef(tl, "%d artifacts from %d waveforms", sum(artInd), length(artInd));
        drawnow;
    end
end

% -------------------------------------------------------------------------
function f = computeFeature(ywin, feature)
% Compute a per-trial feature within the response window
    switch feature
        case "rms"
            f = rms(ywin, 1);
        case "std"
            f = std(ywin, 0, 1);
        case "meanabs"
            f = mean(abs(ywin), 1);
        case "peak2peak"
            f = range(ywin, 1);
        case "posPeak"
            f = max(ywin,[],1);
        case "negPeak"
            f = min(ywin,[],1);
        case "absPeak"
            f = max(abs(ywin),[],1);
    end
    f = f(:);
end
