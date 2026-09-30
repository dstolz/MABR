function R = alignment_report(expected,recovered,tolerance,device,stepTolerance)
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
%   R = alignment_report(expected,recovered,tolerance,device) also takes what
%   the audio device said about the run, a struct whose fields are all
%   optional:
%       SampleRate   Hz, so an offset can be quoted in milliseconds too
%       Underruns    samples of OUTPUT the device ran dry for. It plays silence
%                    for that long and then carries on with the next frame, so
%                    every presentation after it comes out late by about that
%                    much -- nothing is lost, but the plan's grid has a gap in
%                    it, and that shows up here as a step in the offset
%       Overruns     samples of INPUT the device had nowhere to put -- recorded
%                    samples that are simply gone, which moves everything after
%                    them EARLY and can take a pulse with it
%       UnderrunAt   [1 x k] play-matrix sample at which each underrun was
%       OverrunAt    [1 x k] reported (the start of the frame being handed to
%                    the device, so "near", not "at": the device buffers a
%                    little ahead of the frame the program is on)
%   These are only NAMED in a misaligned verdict, never used to make one: the
%   onsets alone decide whether a run is aligned, and a device that reports
%   trouble whose effect the timing channel does not show is not a fault here.
%
%   R = alignment_report(expected,recovered,tolerance,device,stepTolerance)
%   also lets the offset STEP by up to stepTolerance samples (default 0: no
%   step is allowed) as long as it holds, within `tolerance`, on either side
%   of each step and no pulse was spurious. That is a latency step: a USB
%   audio device can slip its output by one microframe (125 us, 24 samples at
%   192 kHz) mid-stream, which moves every later onset and its response
%   together. Sweeps are cut at the recovered onsets, so each is still paired
%   with its own presentation. The run is then Aligned, and its summary says
%   where the latency stepped. A step bigger than stepTolerance -- an
%   underrun's whole audio frame, or the whole interval a spurious or
%   missing pulse shifts the pairing by -- is still a fault.
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
%       NumJumps      how many times the offset changed by more than the
%                     tolerance between one presentation and the next. Jitter
%                     says HOW FAR the offset strayed; this says HOW: a single
%                     jump is a gap or a dropout at one moment (a device
%                     underrun, a lost frame), no jumps with a large Jitter is
%                     a slow creep (a clock), many is scatter.
%       JumpAt        [1 x NumJumps] the first presentation on the far side of
%                     each jump (1 = the first presentation of the run)
%       JumpSize      [1 x NumJumps] signed samples each one moved the offset
%                     by. A jump of +1024 is a late audio frame; a jump of
%                     minus one inter-stimulus interval is a dropped pulse
%       Extra         onsets recovered beyond the plan (spurious pulses), a
%                     fault however small -- they shift the pairing.
%       NumSteps      how many of the jumps were tolerated latency steps (0
%                     unless the run is Aligned only because of them)
%       StepTolerance the stepTolerance the report was made with
%       Underruns, Overruns, UnderrunAt, OverrunAt
%                     the `device` fields above, always present (0 / empty
%                     when none were given) so a consumer reads one shape
%       Aligned       at least one presentation recovered, Extra == 0, and
%                     either Jitter <= tolerance or every jump a latency step
%                     (see stepTolerance).
%       Summary       one line, for a status bar or a log. A misaligned one
%                     leads with what happened to the offset and where, then
%                     says whether the run ended early (so "3602 of 9216" is
%                     not read as lost pulses) and what the device reported.
%
%   The pairing this checks is the one everything else rests on: the k-th
%   recovered onset is paired with the k-th planned presentation
%   (mabr.compute.Pipeline.finalize, mabr.metrics.extract_sweeps), so if the
%   two lists do not line up sample-for-sample then the stimulus metadata
%   saved beside a sweep is not the stimulus that produced it.
%
%   See also mabr.ui.AcqController.alignmentCheck (which adds the waveform
%   comparison Test Mode makes possible and supplies `device` from
%   mabr.acq.Engine.LastStream), mabr.metrics.find_timing_onsets.
%
% Daniel Stolzberg (c) 2026

if nargin < 3 || isempty(tolerance), tolerance = 0; end
if nargin < 4 || ~isstruct(device),  device    = struct(); end
if nargin < 5 || isempty(stepTolerance), stepTolerance = 0; end

expected  = double(expected(:)');
recovered = double(recovered(:)');

R = struct('NumExpected',numel(expected),'NumRecovered',numel(recovered), ...
           'NumCompared',0,'Truncated',false,'Offset',NaN,'Jitter',NaN, ...
           'NumJumps',0,'JumpAt',zeros(1,0),'JumpSize',zeros(1,0), ...
           'Extra',0,'NumSteps',0,'StepTolerance',stepTolerance, ...
           'Underruns',  double(getf(device,'Underruns',0)), ...
           'Overruns',   double(getf(device,'Overruns',0)), ...
           'UnderrunAt', double(getf(device,'UnderrunAt',zeros(1,0))), ...
           'OverrunAt',  double(getf(device,'OverrunAt',zeros(1,0))), ...
           'Aligned',false,'Summary','');
R.UnderrunAt = R.UnderrunAt(:)';
R.OverrunAt  = R.OverrunAt(:)';

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

% Where the offset MOVED, independent of which level the mode settled on: a
% device that stalls late in a run leaves most onsets at the old offset and a
% few at the new, one that stalls early leaves it the other way round, and
% both are one jump between the same two presentations.
step       = diff(d);
j          = find(abs(step) > tolerance);
R.NumJumps = numel(j);
R.JumpAt   = reshape(j + 1,1,[]);
R.JumpSize = reshape(step(j),1,[]);

% Latency steps (see stepTolerance): every jump small, AND the offset holding
% within tolerance on either side of each -- so a creep inside a stretch
% counts against the run exactly as it would with no step at all.
edges = [1 R.JumpAt n+1];
held  = true;
for q = 1:numel(edges)-1
    seg = d(edges(q):edges(q+1)-1);
    if max(abs(seg - mode(seg))) > tolerance, held = false; break; end
end
stepped = R.NumJumps > 0 && stepTolerance > tolerance && held ...
    && all(abs(R.JumpSize) <= stepTolerance);
if ~R.Aligned && R.Extra == 0 && stepped
    R.Aligned  = true;
    R.NumSteps = R.NumJumps;
end

fs = getf(device,'SampleRate',[]);

if R.Aligned
    R.Summary = sprintf('%d/%d presentations aligned (offset %d samples)', ...
        n,R.NumExpected,R.Offset);
    if R.NumSteps > 0
        % Said, not alarmed about: every sweep is still paired with its own
        % presentation, but a latency that moves is a fact about the device
        % worth its line in the log.
        R.Summary = sprintf('%s; the latency stepped %+d samples%s at presentation %d', ...
            R.Summary,R.JumpSize(1),inMs(R.JumpSize(1),fs),R.JumpAt(1));
        if R.NumSteps > 1
            R.Summary = sprintf('%s and %d more time(s)',R.Summary,R.NumSteps-1);
        end
    end
    if R.Truncated
        R.Summary = sprintf('%s — run ended early, %d of %d played', ...
            R.Summary,n,R.NumExpected);
    end
    return
end

% The jumps a latency step cannot explain -- with no stepTolerance, all of
% them. The verdict leads with the first of these, not with a harmless step
% that happened to come before it.
big = find(abs(R.JumpSize) > max(stepTolerance,tolerance));

if R.Extra > 0 && (R.Jitter <= tolerance || stepped)
    % Every planned onset landed where it should have, and then some. Said
    % separately because "6 of 5 presentations recovered" reads as nonsense,
    % and because the remedy is a different one: a pulse nobody rendered
    % points at the timing channel, not at the plan.
    s = sprintf(['MISALIGNED: %d timing pulse(s) more than the plan ' ...
        'rendered (%d recovered, %d planned) -- every sweep after the first ' ...
        'spurious one is paired with the wrong presentation'], ...
        R.Extra,R.NumRecovered,R.NumExpected);
else
    % What happened to the offset comes first, because it is the answer to
    % "what went wrong"; the counts come after, as context. Leading with
    % "3602 of 9216 presentations recovered" read as 5614 lost pulses when it
    % was a run somebody stopped, and "drifting by up to 1023" hid that
    % nothing had drifted -- the offset had stepped once, by an audio frame.
    if ~isempty(big)
        k = big(1);
        s = sprintf('MISALIGNED: offset jumped %+d samples%s at presentation %d', ...
            R.JumpSize(k),inMs(R.JumpSize(k),fs),R.JumpAt(k));
        if R.NumJumps > 1
            s = sprintf('%s, and moved %d more time(s)',s,R.NumJumps-1);
        end
    else
        s = sprintf('MISALIGNED: offset crept by up to %d samples over the run', ...
            R.Jitter);
    end
    s = sprintf('%s (usual offset %d)',s,R.Offset);
    if R.Extra > 0
        s = sprintf('%s; %d spurious pulse(s)',s,R.Extra);
    end
end

if R.Truncated
    % Not a fault, but it is what the "N of M" in every count above means.
    s = sprintf('%s; run ended early, %d of %d played',s,n,R.NumExpected);
end

% What the device saw, when it saw anything. The onsets have already decided
% this run is misaligned; this is the likeliest reason, offered next to the
% evidence rather than left for the operator to go and find in the log.
if R.Underruns > 0
    s = sprintf('%s; device underran %s (%d samples)%s',s, ...
        times_(max(1,numel(R.UnderrunAt))),R.Underruns,near(R.UnderrunAt,expected));
end
if R.Overruns > 0
    s = sprintf('%s; device overran %s (%d samples of input dropped)%s',s, ...
        times_(max(1,numel(R.OverrunAt))),R.Overruns,near(R.OverrunAt,expected));
end
R.Summary = s;
end


% =====================================================================
function v = getf(s,name,default)
% A field of an optional struct, or its default when absent or empty.
if isfield(s,name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end

function s = inMs(samples,fs)
% " (+5.33 ms)" when the rate is known, nothing when it is not.
if isempty(fs) || ~isscalar(fs) || ~(fs > 0)
    s = '';
else
    s = sprintf(' (%+.2f ms)',1e3*samples/fs);
end
end

function s = times_(k)
if k == 1, s = '1 time'; else, s = sprintf('%d times',k); end
end

function s = near(at,expected)
% ", near presentation 3258" -- the first presentation planned at or after
% where the device reported trouble, which is the first one it could have
% moved. Empty when the report carried no position.
s = '';
if isempty(at), return; end
k = find(expected >= at(1),1);
if isempty(k)
    s = ', after the last presentation';
elseif numel(at) > 1
    s = sprintf(', first near presentation %d',k);
else
    s = sprintf(', near presentation %d',k);
end
end
