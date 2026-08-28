function R = alignment_report(expected,recovered,tolerance)
% mabr.metrics.alignment_report  Compare recovered sweep onsets with the plan.
%
%   R = alignment_report(expected,recovered) holds the onsets a run RENDERED
%   (mabr.stim.Schedule.renderSpec's ExpectedOnsets) against the onsets the
%   timing channel actually gave back (mabr.metrics.find_timing_onsets, as
%   absolute ring-buffer sample indices) and reports whether the two describe
%   the same experiment. Pure arithmetic on two index vectors -- no ring
%   buffer, no waveforms, no toolboxes -- so it is testable on its own and can
%   be run over a saved plan after the fact.
%
%   R = alignment_report(expected,recovered,tolerance) allows onsets to sit up
%   to `tolerance` samples off a constant offset before the run is called
%   misaligned (default 0: in TEST MODE the DAC frame IS the ADC frame, so an
%   onset off by even one sample is a defect in the plan, the render, the ring
%   buffer or the extraction rather than anything about a rig).
%
%   Fields:
%       NumExpected   presentations the plan rendered
%       NumRecovered  timing pulses recovered
%       NumCompared   min of the two -- what the offsets below describe
%       Truncated     true when fewer came back than were planned. NOT a
%                     fault on its own: a run stopped early (Abort, or an
%                     advance criterion met) plays fewer presentations than
%                     it rendered, and the ones it did play can still be
%                     perfectly placed.
%       Offset        the constant lag, in samples, between plan and
%                     recording (the MODE of the per-onset differences, so a
%                     single spurious pulse cannot move it). 0 in a loopback
%                     with no device in the path; the loop-back latency on a
%                     real rig. NaN when nothing was recovered.
%       Jitter        the largest departure from that constant offset. This is
%                     the number that matters: a constant offset is a cable,
%                     a varying one means the k-th recorded sweep is not the
%                     k-th planned presentation, and every sweep after the
%                     drift is attributed to the wrong condition.
%       Extra         onsets recovered beyond the plan (spurious pulses), a
%                     fault however small -- they shift the pairing.
%       Aligned       Jitter <= tolerance, Extra == 0, and at least one
%                     presentation recovered.
%       Summary       one line, for a status bar or a log.
%
%   The pairing this checks is the one everything else rests on: the k-th
%   recovered onset is paired with the k-th planned presentation
%   (mabr.compute.Pipeline.finalize, mabr.metrics.extract_sweeps), so if the
%   two lists do not line up sample-for-sample then the stimulus metadata
%   saved beside a sweep is not the stimulus that produced it.
%
%   See also mabr.ui.AcqController.alignmentCheck (which adds the waveform
%   comparison Test Mode makes possible), mabr.metrics.find_timing_onsets.
%
% Daniel Stolzberg (c) 2026

if nargin < 3 || isempty(tolerance), tolerance = 0; end

expected  = double(expected(:)');
recovered = double(recovered(:)');

R = struct('NumExpected',numel(expected),'NumRecovered',numel(recovered), ...
           'NumCompared',0,'Truncated',false,'Offset',NaN,'Jitter',NaN, ...
           'Extra',0,'Aligned',false,'Summary','');

% A pulse with no presentation behind it is counted, never paired off: it
% is exactly the failure that shifts every later sweep onto the wrong
% condition, so it must not be quietly trimmed away by the min() below.
R.Extra     = max(0,R.NumRecovered - R.NumExpected);
n           = min(R.NumExpected,R.NumRecovered);
R.NumCompared = n;
R.Truncated   = R.NumRecovered < R.NumExpected;

if n < 1
    R.Summary = sprintf('no onsets recovered (the plan rendered %d)',R.NumExpected);
    return
end

d = recovered(1:n) - expected(1:n);
% The mode rather than the median: the offset is a single physical constant
% (zero, or a converter's latency) that the great majority of onsets share
% exactly, and taking the value most of them agree on leaves any onset that
% does NOT agree showing up in Jitter, where it belongs. A median would let
% a large minority drag the reference and understate the drift.
R.Offset = mode(d);
R.Jitter = max(abs(d - R.Offset));
R.Aligned = R.Jitter <= tolerance && R.Extra == 0;

if R.Aligned
    R.Summary = sprintf('%d/%d presentations aligned (offset %d samples)', ...
        n,R.NumExpected,R.Offset);
    if R.Truncated
        R.Summary = sprintf('%s — run ended early, %d of %d played', ...
            R.Summary,n,R.NumExpected);
    end
elseif R.Extra > 0 && R.Jitter <= tolerance
    % Every planned onset landed where it should have, and then some. Said
    % separately because "6 of 5 presentations recovered" reads as nonsense,
    % and because the remedy is a different one: a pulse nobody rendered
    % points at the timing channel, not at the plan.
    R.Summary = sprintf(['MISALIGNED: %d timing pulse(s) more than the plan ' ...
        'rendered (%d recovered, %d planned) -- every sweep after the first ' ...
        'spurious one is paired with the wrong presentation'], ...
        R.Extra,R.NumRecovered,R.NumExpected);
else
    R.Summary = sprintf(['MISALIGNED: %d of %d presentations recovered at an ' ...
        'offset of %d samples, drifting by up to %d'], ...
        n,R.NumExpected,R.Offset,R.Jitter);
    if R.Extra > 0
        R.Summary = sprintf('%s; %d spurious pulse(s)',R.Summary,R.Extra);
    end
end
end
