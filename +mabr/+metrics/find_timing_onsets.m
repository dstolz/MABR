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

if threshold > 0 && isa(timing,'single')
    % The comparison straight on the single samples -- finalization runs this
    % over a whole run, and a double copy of a full ring is 512 MB (plus the
    % clipped temporaries) for an answer the singles already hold. Exact:
    % with a positive threshold the negative part can never reach it, so the
    % clipping below changes nothing, and comparing against the smallest
    % single at or above the threshold is the double comparison, value for
    % value (MATLAB compares a single with a double in single, and a
    % threshold that rounds DOWN into single -- 0.7 does -- would otherwise
    % count the one sample equal to that rounding as above it).
    t = single(threshold);
    if double(t) < threshold, t = t + eps(t); end
    above = timing(:) >= t;
else
    d = double(timing(:));
    d(d < 0) = 0;                   % look only at the positive signal
    above = d >= threshold;
end
if numel(above) < 2, idx = []; return; end

% first sample entering the 'above threshold' region = rising crossing
idx = find(above(2:end) & ~above(1:end-1)) + 1;

% A vector that already starts above threshold has its onset at sample 1;
% without this the onset is dropped entirely, which is the right answer for a
% vector read on its own.
%
% It is NOT the right answer at the incremental slice boundaries in
% mabr.metrics.extract_sweeps, where a pulse can straddle two slices and this
% reports the middle of a pulse already counted. Deciding that needs the
% sample before the slice, which only the caller has -- so extract_sweeps
% checks it and drops the duplicate. Do not assume the shadow interval covers
% it: a timing pulse spans its whole presentation, which is routinely longer
% than the shadow.
if above(1), idx = [1; idx]; end

% merge onsets closer than shadowSamples (keep the earliest of each cluster)
if ~isempty(idx)
    keep = [true; diff(idx) >= shadowSamples];
    idx  = idx(keep);
end
end
