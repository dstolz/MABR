function done = custom_template(ctx)
% mabr.stim.advance.custom_template  Copy this to write your own advance
% criterion, then select it from the GUI's Advance dropdown (Custom…).
%
%   THE CONTRACT (see mabr.stim.advance.context for the authoritative field
%   list). An advance function is a PURE PREDICATE with exactly this shape:
%
%       done = my_criterion(ctx)
%
%   INPUT  ctx  a struct carrying the run's tuning parameters and its live
%               metrics. The fields you will actually use:
%                 ctx.numSweeps      clean sweeps averaged so far
%                 ctx.numTotal       all sweeps so far, incl. rejected
%                 ctx.numArtifacts   sweeps rejected as artifact so far
%                 ctx.corr           running correlation 0..1
%                 ctx.elapsedSeconds seconds since the run began
%                 ctx.corrThreshold  the GUI's threshold field
%                 ctx.minSweeps      sweeps before the criterion may fire
%                 ctx.maxSweeps      optional hard cap (Inf = none)
%                 ctx.targetSweeps   the scheduled repetition count
%               Read only the fields you need; ignore the rest. Any extra
%               field you add to AcqController.AdvanceParams arrives here too.
%
%   OUTPUT done  a single logical. Return true to END the run early; the
%                worker halts within one frame. Return false to keep going.
%
%   TWO RULES.
%     1. ALWAYS include a hard cap. A criterion that never returns true will
%        simply run until the scheduled repetitions (ctx.targetSweeps) are
%        exhausted — no error, but no early stop either.
%     2. KEEP IT CHEAP AND SIDE-EFFECT-FREE. It is called ~20 times a second
%        on the GUI thread. If you need a metric the controller does not
%        compute, add it in AcqController.live_tick_body from a
%        mabr.metrics function rather than recomputing it in here.
%
%   Criteria run for BLOCKED strategies only (an intermixed run pools
%   different conditions), so you never have to reason about mixed sweeps.
%
%   This template's own behaviour, as a worked example: stop once the
%   correlation clears the threshold, but not before a floor of clean sweeps,
%   and never past a hard cap.
%
%   See also mabr.stim.advance.num_sweeps, mabr.stim.advance.corr_threshold,
%   mabr.stim.advance.context, mabr.stim.advance.validate.
%
% Daniel Stolzberg (c) 2019-2026

% Read parameters defensively so the criterion still works if a field was
% left unset (the supplied criteria use the same getfield_default helper).
minN = getfield_default(ctx,'minSweeps',32);
maxN = getfield_default(ctx,'maxSweeps',Inf);
thr  = getfield_default(ctx,'corrThreshold',0.5);
n    = getfield_default(ctx,'numSweeps',0);
r    = getfield_default(ctx,'corr',0);

done = (n >= minN && r >= thr) || (n >= maxN);
end

function v = getfield_default(s,f,d)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
