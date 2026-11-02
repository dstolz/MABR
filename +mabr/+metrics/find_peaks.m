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
%   The npeaks returned are the MOST PROMINENT in the trace, in order of
%   occurrence. findpeaks(...,'NPeaks',n) alone stops at the first n local
%   maxima in time order, which on a filtered trace are its first n wiggles:
%   the organizer's "mark peaks" then marked noise ahead of wave I, and the
%   callers that rank by prominence (the inspector's auto-detect, the online
%   latency metric) only ever saw the first few candidates of their window.
%
%   Ported from abr.ABR.analysis('peaks'). Named find_peaks (not findpeaks)
%   to avoid shadowing the Signal Processing Toolbox findpeaks it calls.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 2 || isempty(npeaks),       npeaks = 5;           end
if nargin < 3 || isempty(findNegative), findNegative = false; end

M = double(meanTrace(:));
if findNegative, M = -M; end

[pks,locs,w,p] = findpeaks(M);
if numel(locs) > npeaks
    [~,o] = sort(p,'descend');
    keep  = sort(o(1:npeaks));          % the n most prominent, back in time order
    pks = pks(keep); locs = locs(keep); w = w(keep); p = p(keep);
end
if findNegative, pks = -pks; end

r = struct('pks',pks,'locs',locs,'w',w,'p',p);
end
