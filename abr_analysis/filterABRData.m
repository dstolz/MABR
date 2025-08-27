function S = filterABRData(S, Fs)
% FILTERABRDATA Applies bandpass filtering to ABR data.
%
% Inputs:
%   S  - Cell array of ABR responses.
%   Fs - Sampling frequency (Hz).
%
% Output:
%   S - Filtered ABR responses.

arguments
    S cell
    Fs (1,1) {mustBeNumeric, mustBePositive}
end



% fprintf('Bandpass filtering with cutoff frequencies: [%d %d] Hz\n', Fpass1,Fpass2);

Fpass = 3000;            % Passband Frequency
Fstop = 4200;            % Stopband Frequency
Dpass = 0.014390163418;  % Passband Ripple
Dstop = 0.031622776602;  % Stopband Attenuation
dens  = 20;              % Density Factor

% Calculate the order from the parameters using FIRPMORD.
[N, Fo, Ao, W] = firpmord([Fpass, Fstop]/(Fs/2), [1 0], [Dpass, Dstop]);

% Calculate the coefficients using the FIRPM function.
b  = firpm(N, Fo, Ao, W, {dens});
Hlp = dfilt.dffir(b);



Fstop = 150;             % Stopband Frequency
Fpass = 300;             % Passband Frequency
Dstop = 0.031622776602;  % Stopband Attenuation
Dpass = 0.014390163418;  % Passband Ripple
dens  = 20;              % Density Factor

% Calculate the order from the parameters using FIRPMORD.
[N, Fo, Ao, W] = firpmord([Fstop, Fpass]/(Fs/2), [0 1], [Dstop, Dpass]);

% Calculate the coefficients using the FIRPM function.
b  = firpm(N, Fo, Ao, W, {dens});
Hhp = dfilt.dffir(b);


parfor_progress(numel(S));
for i = 1:numel(S)
    if isempty(S{i}), continue; end
    S{i} = filtfilt(Hhp,S{i});
    S{i} = filtfilt(Hlp,S{i});
    parfor_progress;
end
parfor_progress(0);
