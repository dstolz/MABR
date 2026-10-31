function [thresh_hat, logMdls] = batchABRAnalysis(rootPth, options)
% BATCHABRANALYSIS Run the abr_analysis chain over every session folder below a root.
%
%   [thresh_hat, logMdls] = batchABRAnalysis(rootPth)
%   [thresh_hat, logMdls] = batchABRAnalysis(rootPth, window=[-10 10], responseWindow=[0 10])
%
%   For each folder GETABRSESSIONS finds below rootPth this runs PARSEABRFILES,
%   EXTRACTABRRESPONSES (which already filters the whole trace, so FILTERABRDATA is not
%   called again), REJECTARTIFACTS and PLOTABRGRID, then ABRPERMUTATIONTHRESHOLD on the
%   response window only. It is the recipe of docs/Offline-Analysis.md in a loop.
%
% Inputs
%   rootPth          Root folder searched, at any depth, for folders holding .abr files.
%   filePattern      Regular expression a file name must match. Default: the current
%                    naming scheme, SUBJ-ID-<n>_Frequency-<f>kHz_Level-<L>dB_<time>.abr.
%   window           [t0 t1] ms re sweep onset cut from each file and drawn in the grid.
%                    Default [-10 10].
%   responseWindow   [t0 t1] ms tested for a response, and over which artifacts are judged.
%                    Default [0 10]; it must lie inside window.
%   thresholdType    thresholdType of ABRPERMUTATIONTHRESHOLD. Default "glm".
%   minClusterSize   minClusterSize of PERMTEST, in samples. Default 5.
%   Seed             Nonnegative integer making the permutation tests reproducible. Default [].
%   plot             Draw the response grid of every session. Default true.
%
% Outputs
%   thresh_hat   Cell, one per session: a [1 x nFrequencies] vector of thresholds in the
%                order of U.Frequency (empty for a session that was skipped).
%   logMdls      Cell, one struct per session with fields U (the unique stimulus values),
%                permResult and mdls (outputs 2 and 3 of ABRPERMUTATIONTHRESHOLD).
%
%   A session is skipped, with a message, when no file matches filePattern, when its files
%   vary anything but Level and Frequency, or when it holds compact files (intermixed
%   runs, which EXTRACTABRRESPONSES refuses): analyse those with mabr.analysis.Batch.

arguments
    rootPth (1,1) string
    options.filePattern = "^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr"
    options.window (1,2) double {mustBeFinite} = [-10 10]   % ms
    options.responseWindow (1,2) double {mustBeFinite} = [0 10]   % ms
    options.thresholdType (1,1) string = "glm"
    options.minClusterSize (1,1) double {mustBePositive} = 5
    options.Seed double {mustBeScalarOrEmpty,mustBeNonnegative,mustBeInteger} = []
    options.plot (1,1) logical = true
end

% Check everything the chain needs now, not in the middle of the first session.
checkABRDependencies("batchABRAnalysis", ["parfor_progress" "structToCallerVars" "errEmpty" "colorcet"], ["statistics" "signal"]);

rw = options.responseWindow;
if diff(options.window) <= 0 || diff(rw) <= 0 || rw(1) < options.window(1) || rw(2) > options.window(2)
    error('batchABRAnalysis:window', 'window and responseWindow must each be ascending, with responseWindow inside window.');
end

abrSessions = getABRSessions(rootPth);
thresh_hat = cell(size(abrSessions));
logMdls = cell(size(abrSessions));
for k = 1:length(abrSessions)
    abrSessionName = extractSessionName(abrSessions{k});
    fprintf('%d/%d. Processing: %s\n', k, length(abrSessions), abrSessionName)

    T = parseABRFiles(abrSessions{k}, filePattern = options.filePattern);
    if isempty(T)
        fprintf(2, '* No valid file names, skipping *\n')
        continue
    end

    try
        [S, U, Fs, winIdx] = extractABRResponses(T, options.window);
    catch ME
        if ~strcmp(ME.identifier, 'abr_analysis:extractABRResponses:compactFile'), rethrow(ME), end
        fprintf(2, '* %s *\n', ME.message)
        continue
    end

    % S has one dimension per parameter in file order, frequency first in the usual
    % files; the steps below want [level x frequency].
    names = string(fieldnames(U));
    lvlName = names(ismember(names, ["Level" "soundLevel"]));
    frqName = names(ismember(names, ["Frequency" "frequency"]));
    if numel(names) ~= 2 || isempty(lvlName) || isempty(frqName)
        fprintf(2, '* Files vary %s, not just Level and Frequency; skipping *\n', strjoin(names, ', '))
        continue
    end
    if names(2) == lvlName, S = S'; end

    tms = 1000 * winIdx / Fs;    % ms re onset; the 1e-9 keeps an end sample that rounds a hair outside
    S = rejectArtifacts(S, respInd = tms >= rw(1) - 1e-9 & tms <= rw(2) + 1e-9);

    if options.plot
        h = plotABRGrid(S, U, Fs, winIdx);
        tl = h(1).Parent;
        title(tl, abrSessionName, Interpreter = 'none')
        subtitle(tl, char(T.timestamp(1), 'dd-MMM-uuuu'))
        drawnow
    end

    [thresh_hat{k}, permResult, mdls] = abrPermutationThreshold(S, U.(lvlName), ...
        'window', rw, 'Fs', Fs, 'winIdx', winIdx, ...
        'thresholdType', options.thresholdType, 'minClusterSize', options.minClusterSize, 'Seed', options.Seed);
    logMdls{k} = struct('U', U, 'permResult', permResult, 'mdls', {mdls});
end
end
