function r = find_peaks(meanTrace,npeaks,findNegative)
% mabr.metrics.find_peaks  Wrapper over findpeaks for ABR wave marking.
%
%   r = find_peaks(meanTrace) returns a struct with fields pks/locs/w/p for
%   up to 5 positive peaks in meanTrace (a column vector, e.g. a SweepMean).
%
%   r = find_peaks(meanTrace,npeaks,findNegative)
%       npeaks        max number of peaks (default 5)
%       findNegative  logical; find troughs instead of peaks (default false)
%
%   Ported from abr.ABR.analysis('peaks'). Named find_peaks (not findpeaks)
%   to avoid shadowing the Signal Processing Toolbox findpeaks it calls.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 2 || isempty(npeaks),       npeaks = 5;           end
if nargin < 3 || isempty(findNegative), findNegative = false; end

M = double(meanTrace(:));
if findNegative, M = -M; end

[pks,locs,w,p] = findpeaks(M,'NPeaks',npeaks);
if findNegative, pks = -pks; end

r = struct('pks',pks,'locs',locs,'w',w,'p',p);
end
