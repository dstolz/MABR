function [S, U, Fs, winIdx] = extractABRResponses(T, sessionPath, win)
% EXTRACTABRRESPONSES Extracts ABR responses from data files.
%
% Inputs:
%   T           - Table containing metadata and filenames.
%   sessionPath - Path to the session folder.
%   win         - Time window in milliseconds.
%
% Outputs:
%   S      - Cell array of ABR responses.
%   U      - Struct containing unique frequencies and levels.
%   Fs     - Sampling frequency.
%   winIdx - Sample indices corresponding to the time window.

minNumSweeps = 1;
U.frequency = unique(T.frequency);
U.level = unique(T.level);
N = structfun(@numel, U, 'UniformOutput', false);
S = cell(N.level, N.frequency);

warning('off', 'audio:audioPlayerRecorder:invalidDevice')

for f = 1:N.frequency
    for lvl = 1:N.level
        ind = T.frequency == U.frequency(f) & T.level == U.level(lvl);
        
        if ~any(ind), continue; end

        load(fullfile(sessionPath, T.filename(ind)), '-mat');
        Fs = ABR_Data.ADC.SampleRate;
        swin = round(Fs * win / 1000);
        winIdx = swin(1):swin(2);

        nSweeps = length(ABR_Data.ADC.SweepOnsets);
        nSamples = length(ABR_Data.ADC.Data);
        if nSweeps < minNumSweeps, continue; end

        S{lvl, f} = nan(length(winIdx), nSweeps);
        for i = 1:nSweeps
            idx = ABR_Data.ADC.SweepOnsets(i) + winIdx;
            if any(idx > nSamples | idx < 1), continue; end
            S{lvl, f}(:, i) = ABR_Data.ADC.Data(idx);
        end
        S{lvl, f} = S{lvl, f}(:, ~any(isnan(S{lvl, f}), 1));
    end
end

warning('on', 'audio:audioPlayerRecorder:invalidDevice')
