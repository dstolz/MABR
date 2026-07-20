function idx = find_timing_onsets(timing,shadowSamples,threshold)
% mabr.metrics.find_timing_onsets  Locate sweep onsets in a timing channel.
%
%   idx = find_timing_onsets(timing) returns the 1-based sample indices (into
%   the timing vector) of sweep onsets: the first sample of each rising
%   threshold crossing. Onsets closer together than shadowSamples are merged
%   (the earliest kept).
%
%   idx = find_timing_onsets(timing,shadowSamples,threshold)
%       shadowSamples  minimum spacing between onsets (default 1)
%       threshold      detection threshold (default 0.1)
%
%   Rewrite of the legacy abr.Runtime.find_timing_onsets as a pure, testable
%   function. Unlike the legacy edge test it detects the first sample to reach
%   threshold on a rising edge, so it works for both the clean synthesized
%   impulses (TESTING loopback) and the smeared pulses returned by hardware.
%   As in the recent legacy fix, only the positive part of the signal is used.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 2 || isempty(shadowSamples), shadowSamples = 1;   end
if nargin < 3 || isempty(threshold),     threshold     = 0.1; end

d = double(timing(:));
d(d < 0) = 0;                       % look only at the positive signal

above = d >= threshold;
if numel(above) < 2, idx = []; return; end

% first sample entering the 'above threshold' region = rising crossing
idx = find(above(2:end) & ~above(1:end-1)) + 1;

% merge onsets closer than shadowSamples (keep the earliest of each cluster)
if ~isempty(idx)
    keep = [true; diff(idx) >= shadowSamples];
    idx  = idx(keep);
end
end
