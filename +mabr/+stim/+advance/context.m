function ctx = context(params,live)
% mabr.stim.advance.context  Build the canonical context struct handed to an
% advance criterion. THIS IS THE CONTRACT every advance function is called
% under: it receives exactly one struct with the fields below and returns a
% single logical `done` (true = stop the run early).
%
%   ctx = mabr.stim.advance.context(params,live) merges the user's tuning
%   PARAMETERS (params, from mabr.ui.AcqController.AdvanceParams) with the
%   live acquisition METRICS (live, recomputed each ~20 Hz tick) into one
%   struct. Defining it in one place is why every criterion — the two
%   supplied and any custom one the user selects in the GUI — sees the same
%   named fields, and why mabr.stim.advance.validate can build a
%   representative sample to test an unknown function against.
%
%   PARAMETER fields (set by the user / GUI, carried in AdvanceParams):
%       targetSweeps   sweeps the schedule will present for this run. This is
%                      the hard ceiling: a criterion that never fires runs to
%                      here and the block finalizes on the scheduled count.
%       corrThreshold  correlation an averaging criterion should reach
%       minSweeps      clean sweeps required before a criterion may fire
%       maxSweeps      optional hard cap below targetSweeps (Inf = none)
%     ...plus any extra field the user adds to AdvanceParams, passed through
%     untouched — a custom criterion supplies its own knobs this way.
%
%   LIVE METRIC fields (computed by AcqController.advance_met each tick):
%       numSweeps      CLEAN sweeps averaged so far (artifact-rejected ones
%                      excluded) — the count a criterion should reason about,
%                      since it is what the average is actually built from
%       numTotal       ALL sweeps acquired so far, including rejected ones
%       numArtifacts   sweeps rejected as artifact so far (numTotal-numSweeps)
%       corr           running onset-contrast correlation, 0..1
%                      (mabr.metrics.partition_corr over the clean sweeps)
%       elapsedSeconds wall-clock seconds since this run began streaming
%
%   A criterion is a PURE PREDICATE: keep it cheap and side-effect-free (it
%   runs 20 times a second on the GUI thread) and ALWAYS include a hard cap,
%   or one that never fires will simply run out the scheduled repetitions.
%
%   Advance criteria are evaluated for BLOCKED strategies only — an
%   intermixed run pools different conditions, so early-stopping it is
%   meaningless and unbalancing, and AcqController skips the criterion when
%   mabr.stim.Schedule.isIntermixed() is true.
%
%   See also mabr.stim.advance.num_sweeps, mabr.stim.advance.corr_threshold,
%   mabr.stim.advance.custom_template, mabr.stim.advance.validate.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 1 || isempty(params), params = struct(); end
ctx = params;

% Live metrics win over any same-named parameter: the metric is the current
% truth, the parameter only its threshold.
if nargin >= 2 && ~isempty(live) && isstruct(live)
    f = fieldnames(live);
    for i = 1:numel(f)
        ctx.(f{i}) = live.(f{i});
    end
end
end
