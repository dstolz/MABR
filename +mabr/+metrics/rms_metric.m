function r = rms_metric(D)
% mabr.metrics.rms_metric  Mean per-sweep RMS amplitude.
%
%   r = rms_metric(D) returns the mean of the root-mean-square amplitude of
%   each sweep (column) of D, a [nSamples x nSweeps] matrix. Ported from the
%   legacy abr.ABR.analysis('rms'). Named rms_metric (not rms) to avoid
%   shadowing the Signal Processing Toolbox rms() it calls.
%
% Daniel Stolzberg (c) 2019-2026

if isempty(D), r = NaN; return; end
r = mean(rms(double(D)));
end
