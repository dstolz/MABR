function [thresh_hat,logMdls] = batchABRAnalysis(rootPth, options)
% BATCHABRANALYSIS Processes ABR data across multiple sessions.
%
% Inputs:
%   rootPth - Root path containing ABR data folders.
%   win     - Time window in milliseconds, e.g., [-10 10].

arguments
    rootPth
    options.filePattern = "^SUBJ_ID_(\d+)_Frequency_([\d_]+kHz)_Level_(\d+dB)_(\d{6}T\d{6})\.abr";
    options.window (1,2) double {mustBeFinite,mustBeAscending} = [-10 10]; % ms
end


abrSessions = getABRSessions(rootPth);

thresh_hat = zeros(size(abrSessions));
logMdls = cell(size(abrSessions));
for k = 1:length(abrSessions)
    abrSessionName = extractSessionName(abrSessions{k});
    fprintf('%d/%d. Processing: %s\n', k, length(abrSessions), abrSessionName)

    T = parseABRFiles(abrSessions{k});%, filePattern = options.filePattern);
    if isempty(T)
        fprintf(2, '* No valid file names, skipping *\n')
        continue
    end

    [S, U, Fs, winIdx] = extractABRResponses(T, options.window);

    S = filterABRData(S, Fs);

    S = rejectArtifacts(S, respInd = winIdx);

    h = plotABRGrid(S, U, Fs, winIdx);
    tl = h.Children;
    title(tl, abrSessionName)
    abrSessionDate = T.timestamp(1);
    abrSessionDate.Format = "dd-MMM-uuuu";
    subtitle(tl, char(abrSessionDate))
    drawnow

    [thresh_hat{k}, logMdls{k}] = abrPermutationThreshold(S, U, winIdx, Fs, ...
        'responseWindow', [1 9], ...
        'minClusterSize', 5);
end


