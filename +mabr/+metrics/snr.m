function r = snr(D)
% mabr.metrics.snr  Signal-to-noise ratio (dB) via plus/minus averaging.
%
%   r = snr(D) estimates SNR in decibels from the sweeps in D, a
%   [nSamples x nSweeps] matrix. The signal estimate is the RMS of the mean
%   sweep; the noise estimate is the RMS of the odd-minus-even average
%   difference (which cancels the time-locked response). Ported from the
%   abr.Buffer noisePower/signalPower/SNR helpers.
%
% Daniel Stolzberg (c) 2019-2026

if isempty(D) || size(D,2) < 2, r = NaN; return; end

D = double(D);

signalPower = rms(mean(D,2));

noise = mean(D(:,1:2:end),2) - mean(D(:,2:2:end),2);
noisePower = sqrt(mean(noise.^2));

r = 20*log10(signalPower./noisePower);
end
