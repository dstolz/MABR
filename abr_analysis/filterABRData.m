function S = filterABRData(S, Fs, fc)
% FILTERABRDATA Applies bandpass filtering to ABR data.
%
% Inputs:
%   S  - Cell array of ABR responses.
%   Fs - Sampling frequency (Hz).
%   fc - Two-element vector specifying the bandpass filter cutoff frequencies [low high] in Hz.
%
% Output:
%   S - Filtered ABR responses.

arguments
    S cell
    Fs (1,1) {mustBeNumeric, mustBePositive}
    fc (1,2) {mustBeNumeric, mustBePositive} = [300 1500]
end

fprintf('Bandpass filtering with cutoff frequencies: [%d %d] Hz\n', fc(1), fc(2));

parfor_progress(numel(S));
parfor i = 1:numel(S)
    if isempty(S{i}), continue; end
    S{i} = bandpass(S{i}, fc, Fs);
    parfor_progress;
end
parfor_progress(0);
