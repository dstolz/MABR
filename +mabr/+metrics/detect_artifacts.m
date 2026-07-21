function [tf,feature] = detect_artifacts(D,mode,threshold)
% mabr.metrics.detect_artifacts  Flag sweeps contaminated by artifact.
%
%   tf = detect_artifacts(D,mode,threshold) returns a [1 x nSweeps] logical
%   marking each sweep (column) of the [nSamples x nSweeps] matrix D that
%   exceeds `threshold` under the chosen criterion:
%
%       'none'     nothing is rejected (tf is all false)
%       'voltage'  reject when ANY sample leaves +/-threshold. Catches the
%                  large transients -- movement, electrode pops, stimulator
%                  breakthrough -- that a mean would otherwise smear across
%                  the whole average.
%       'rms'      reject when the sweep's RMS exceeds threshold. Catches
%                  sustained high-amplitude contamination (muscle activity)
%                  that never trips a peak limit but still dominates the mean.
%
%   [tf,feature] = ... also returns the per-sweep feature actually compared
%   against the threshold (max |sample| or RMS), so a caller can report or
%   plot the distribution behind a decision.
%
%   Both criteria are absolute thresholds on the sweep as supplied. Pass the
%   FILTERED sweeps (mabr.data.Recording.SweepData after designFilters) --
%   baseline drift in an unfiltered trace trips a voltage threshold on its own.
%
%   This is the online/acquisition-time counterpart to the offline pipeline's
%   abr_analysis/rejectArtifacts, which instead rejects by isoutlier() over
%   the distribution of a whole session. A fixed threshold is what the live
%   path needs: it is decidable for one sweep as it arrives, and it does not
%   move as more data accumulates.
%
% Daniel Stolzberg (c) 2019-2026

if isempty(D), tf = false(1,0); feature = zeros(1,0); return; end

D = double(D);

switch lower(mode)
    case 'none'
        feature = zeros(1,size(D,2));
        tf      = false(1,size(D,2));
        return

    case 'voltage'
        feature = max(abs(D),[],1);

    case 'rms'
        feature = sqrt(mean(D.^2,1));

    otherwise
        error('mabr:metrics:detect_artifacts:mode', ...
            'Unknown artifact mode "%s". Expected none, voltage, or rms.',mode);
end

% NaN samples (a sweep window running off the end of the trace) cannot be
% judged, so they are not artifacts by omission -- max/mean above already
% propagate NaN, and NaN > threshold is false.
tf = feature > threshold;
end
