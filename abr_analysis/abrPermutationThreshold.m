function [thresh_hat,permResult,mdls] = abrPermutationThreshold(S, rowVals, options, ptoptions)
% abrPermutationThreshold  Permutation-based detection across rows and per-column thresholding.
%
%   [thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals)
%   [thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals, options, ptoptions)
%
% Description
%   For each cell S{r,c} (row r, column c), runs a two-sided cluster-based
%   permutation test (PERMTEST) across trials to detect a response over time.
%   Within each column c, detections across rows are summarized versus rowVals
%   and a threshold is estimated using the selected model. Thresholds are
%   reported per column (1 × nCols).
%
% Inputs
%   S         cell [nRows × nCols]. Each S{r,c} is a numeric matrix of size
%             [nSamples × nTrials] (this function transposes to trials × samples
%             before calling PERMTEST).
%
%   rowVals   double [nRows × 1]. X-values for the row dimension (e.g., frequency).
%
% Name-Value Options (struct; fields shown with defaults)
%   options.useParallel      (1,1) logical = false
%       Use PARFOR for permutation tests when true.
%
%   options.debug            (1,1) logical = false
%       Show diagnostic plots for fits; also forwards to ptoptions.showPlot.
%
%   options.thresholdType    (1,1) string = "logistic"
%       Per-column threshold model:
%         "logistic"  – fit fittype('logistic') to binary detection vs rowVals.
%         "logistic4" – fit fittype('logistic4') to cluster mass vs rowVals.
%         "minimum"   – first row with significant detection (by p < alpha).
%
%   options.nearestLevel     (1,1) logical = false
%       If true, pin each threshold up to the nearest value in rowVals.
%
% Permutation Test Options (struct; fields shown with defaults)
%   ptoptions.alpha          (1,1) double = 0.05
%       Family-wise alpha for the cluster-forming t-threshold (two-sided).
%
%   ptoptions.nPerm          (1,1) double = 1000
%       Number of sign-flip permutations per condition.
%
%   ptoptions.minClusterSize (1,1) double = 1
%       Minimum contiguous sample length to count as a cluster.
%
%   ptoptions.showPlot       (1,1) logical = false
%       Plot PERMTEST diagnostics (overridden by options.debug).
%
% Outputs
%   thresh_hat   1 × nCols double
%       Threshold per column. For "logistic"/"logistic4" this is the fitted
%       center/inflection parameter (field ‘c’). For "minimum" it is rowVals at
%       the first significant row; Inf if none. Optionally quantized to rowVals
%       when options.nearestLevel = true.
%
%   permResult   nRows × nCols struct
%       PERMTEST results for each condition with fields:
%         .tValsReal, .tThresh, .pos, .neg, .maxClusterMassReal, .maxClusterMassPerm
%       (See PERMTEST for details.)
%
%   mdls         1 × nCols cell
%       Curve-fitting model objects (one per column) for "logistic"/"logistic4";
%       empty for "minimum".
%
% Theory (brief)
%   Each condition uses a two-sided cluster-based permutation on the time axis,
%   controlling FWER over samples. Column-wise thresholds are then obtained by
%   fitting detection summaries across rows versus rowVals, or by first-hit.
%
% Requirements
%   Statistics and Machine Learning Toolbox (ttest, tinv)
%   Image Processing Toolbox (bwlabel)
%   Curve Fitting Toolbox (fit, fittype, fitoptions; models 'logistic','logistic4')
%   Parallel Computing Toolbox (optional; for PARFOR)
%
% Example
%   % S: nRows × nCols cell; each S{r,c} is [nSamples × nTrials]
%   fHz     = [4e3; 8e3; 16e3; 32e3];           % rowVals
%   opts    = struct('thresholdType',"logistic", 'useParallel',true, 'nearestLevel',true);
%   ptopts  = struct('alpha',0.05, 'nPerm',2000, 'minClusterSize',3);
%   [th, PR, M] = abrPermutationThreshold(S, fHz, opts, ptopts);
%
% Notes
%   • ptoptions.showPlot is set to options.debug inside.
%   • The fittype names 'logistic' and 'logistic4' must exist in your environment
%     (e.g., user-defined FITTYPEs).
%
% See also: PERMTEST
%
% DJS 2025

arguments
    S cell
    rowVals (:,1) double
    options.useParallel (1,1) logical = false;
    options.debug (1,1) logical = false;
    options.thresholdType (1,1) string {mustBeMember(options.thresholdType,["logistic","logistic4","minimum"])} = "logistic";
    options.nearestLevel (1,1) logical = false;
    ptoptions.alpha (1,1) double {mustBeInRange(ptoptions.alpha, 0, 1)} = 0.05
    ptoptions.nPerm (1,1) double {mustBePositive,mustBeFinite} = 1000
    ptoptions.minClusterSize (1,1) double {mustBePositive,mustBeFinite} = 1;
    ptoptions.showPlot (1,1) logical = false;
end

ptoptions.showPlot = options.debug;
structToCallerVars(options);

nCols = size(S,2);
nRows = length(rowVals);

assert(size(S,1) == nRows,'Length of `rowVals` must match `size(S,1)`')




cargs = namedargs2cell(ptoptions);


permResult(size(S,1),size(S,2)) = struct('tValsReal',[],'tThresh',[],'pos',[],'neg',[],'maxClusterMassReal',[],'maxClusterMassPerm',[]);

pVal = nan(size(S));

% Run permutation tests
parfor_progress(numel(S),'Permutation tests');
if options.useParallel && ~options.debug
    parfor i = 1:numel(S)
        if isempty(S{i}), continue; end
        [pVal(i), permResult(i)] = permtest(S{i}',cargs{:});
        parfor_progress;
    end
else
    for i = 1:numel(S)
        if isempty(S{i}), continue; end
        [pVal(i), permResult(i)] = permtest(S{i}',cargs{:});
        if options.debug, pause; end
        parfor_progress;
    end
end
parfor_progress(0);


i = isnan(pVal);
pVal = max(pVal, 0);
pVal(i) = nan;
isSig = pVal < ptoptions.alpha;
thresh_hat = nan(1, nCols);
mdls = cell(1,nCols);

parfor_progress(nCols,'Estimating thresholds');
switch (thresholdType)
    case "logistic"
        ft = fittype('logistic');
        ftopts = fitoptions('Method','NonlinearLeastSquares');
        ftopts.Algorithm = 'Levenberg-Marquardt';
        ftopts.Display = 'Off';
        ftopts.StartPoint = [0 1 mean(rowVals)];

        % Estimate thresholds for each (fieldOfInterst)
        for k = 1:nCols

            % s = cellfun(@sum,{permResult(:,f).clusterStatsReal});
            y = double(isSig(:, k));

            i = ~isnan(y);
            x = rowVals(i);
            y = y(i);

            try
                mdl = fit(x(:),y(:),ft,ftopts);
                thresh_hat(k) = mdl.c;
                mdls{k} = mdl;
            catch
                thresh_hat(k) = max(rowVals) + 5;
            end



            if options.debug
                use_fig('abrPermutationThreshold');
                plot(x,y,'ob');
                hold on
                if isequal(class(mdl),'cfit')
                    plot(mdl,x(:),y(:));
                end
                stem(thresh_hat(k),0.5,'-kd')
                hold off
                grid on
                ylim([0 1])
                titlef('%d Hz -- C = %.3f',rowVals(k),thresh_hat(k))
                legend off
            end


            parfor_progress;
        end

    case "logistic4"
        ft = fittype('logistic4');
        ftopts = fitoptions('Method','NonlinearLeastSquares');
        ftopts.Algorithm = 'Levenberg-Marquardt';
        ftopts.Display = 'Off';
        ftopts.StartPoint = [0 1 mean(rowVals) 1];

        % Estimate thresholds for each column
        for k = 1:nCols
            y = [permResult(:,k).maxClusterMassReal];
            i = ~isnan(y);
            x = rowVals(i);
            y = y(i);

            mdl = fit(x(:),y(:),ft,ftopts);

            thresh_hat(k) = mdl.c;


            if options.debug
                use_fig('abrPermutationThreshold');
                plot(x,y,'ob');
                hold on
                plot(mdl,x(:),y(:));
                stem(thresh_hat(k),0.5,'-kd')
                hold off
                grid on
                ylim([0 1])
                titlef('%d Hz -- C = %.3f',rowVals(k),thresh_hat(k))
                legend off
            end

            mdls{k} = mdl;

            parfor_progress;
        end



    case "minimum"
        for k = 1:nCols
            idx = find(isSig(:,k),1,'first');
            if isempty(idx)
                thresh_hat(k) = inf;
            else
                thresh_hat(k) = rowVals(idx);
            end
            parfor_progress;
        end
end
parfor_progress(0);

if options.nearestLevel
    % pin to nearest level greater than threshold
    for i = 1:length(thresh_hat)
        idx = find(rowVals >= thresh_hat(i),1);
        if isempty(idx), continue; end
        thresh_hat(i) = rowVals(idx);
    end
end