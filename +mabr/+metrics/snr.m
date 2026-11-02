function r = snr(D,pol)
% mabr.metrics.snr  Signal-to-noise ratio (dB) via plus/minus averaging.
%
%   r = snr(D) estimates SNR in decibels from the sweeps in D, a
%   [nSamples x nSweeps] matrix. The signal estimate is the RMS of the mean
%   sweep; the noise estimate is the RMS of the plus/minus reference (half
%   the odd-minus-even average difference, which cancels the time-locked
%   response). Ported from the abr.Buffer noisePower/signalPower/SNR helpers.
%
%   r = snr(D,pol) also takes the per-sweep polarity (+1/-1 per column), so
%   the two halves are balanced in sign and a polarity-locked component is
%   not counted as noise (mabr.metrics.plus_minus).
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 2, pol = []; end
if isempty(D) || size(D,2) < 2, r = NaN; return; end

D = double(D);

signalPower = rms(mean(D,2));

% The plus/minus reference (Schimmel 1967): HALF the difference of two
% half-averages, balanced in polarity when the polarity is known -- see
% mabr.metrics.plus_minus for both halves of that sentence. Without the
% halving (the legacy port) every SNR read 6 dB low, and pure noise read
% about -6 dB where it should read 0 dB. mabr.data.Recording.noisePower and
% the online 'Residual noise' metric use the same function.
noise = mabr.metrics.plus_minus(D,pol);
noisePower = sqrt(mean(noise.^2));

r = 20*log10(signalPower./noisePower);
end
