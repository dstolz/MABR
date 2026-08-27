function ctx = context(sch,params,rs)
% mabr.stim.strategy.context  Build the canonical context struct handed to a
% custom presentation strategy. THIS IS THE CONTRACT every strategy function
% is called under: it receives exactly one struct describing the design, and
% returns the run(s) it wants presented (see mabr.stim.strategy.normalize for
% the accepted return shapes).
%
%   ctx = mabr.stim.strategy.context(sch,params,rs) describes the schedule
%   SCH's
%   design -- the bank, the repetition counts, the parameters that identify
%   each entry, and the timing the runs will be rendered at -- and merges the
%   user's tuning PARAMETERS (params, from mabr.stim.Schedule.StrategyParams)
%   underneath it. Defining it in one place is why every strategy sees the
%   same named fields, and why mabr.stim.strategy.validate can build a
%   representative design to test an unknown function against.
%
%   DESIGN fields (what there is to present):
%       numStimuli         entries in the bank
%       repetitions        [1 x n] presentations owed per entry, already
%                          normalized (scalar expanded, negatives clamped,
%                          rounded). This is the multiset a strategy is
%                          expected to permute -- see THE ONE INVARIANT below.
%       alternatePolarity  [1 x n] logical, which entries alternate polarity
%       IDs                {1 x n} each entry's ID
%       durations          [1 x n] seconds, one presentation of each entry
%       params             the bank tabulated by mabr.stim.StimulusSet.
%                          paramTable: .Names, .Values [n x nP], .Varying,
%                          .Units, .IDs. This is how a strategy orders by
%                          Level or groups by Frequency without parsing IDs.
%
%   TIMING fields (what the runs will be rendered at):
%       sampleRate         Hz, the DAC rate the plan is rendered at
%       isi / isiMode / isiRange / minISI / meanISI   see mabr.stim.Schedule
%       silencePad         s of silence bracketing each run
%       maxRunSamples      Config.maxInputBufferLength -- the ring buffer
%                          holds ONE run, so a run longer than this is refused
%                          by renderSpec. Leave headroom: the rendered run
%                          also carries 2*silencePad and rounds up to a whole
%                          number of frames.
%
%   REPRODUCIBILITY:
%       randStream         the schedule's OWN RandStream, RS -- the same one
%                          build() draws its own shuffles from. Shuffle with THIS
%                          (randperm(ctx.randStream,n)) and never with the
%                          bare randperm/rand: building a plan must not
%                          perturb global rng, and Schedule.Seed must make the
%                          whole plan reproducible.
%
%   ...plus any extra field the user puts in StrategyParams, passed through
%   untouched -- a custom strategy supplies its own knobs this way.
%
%   THE ONE INVARIANT. Every strategy MABR supplies is a permutation of a
%   fixed multiset: entry i is presented exactly repetitions(i) times, which
%   is what the artifact make-up budget, the progress tally and the balance of
%   an intermixed design all reason about. A custom strategy MAY depart from
%   it -- that is the point of being able to write one -- but it is warned
%   about (mabr.stim.strategy.normalize logs the difference), because the
%   overwhelmingly common cause is a bug in the sequence, not a design.
%
%   See also mabr.stim.strategy.custom_template, mabr.stim.strategy.validate,
%   mabr.stim.strategy.normalize, mabr.stim.Schedule.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 2 || isempty(params) || ~isstruct(params), params = struct(); end
% One stream per build, handed in rather than made here: obj.stream() returns
% a FRESH stream seeded the same way, so calling it twice under a fixed Seed
% would hand the strategy the identical draws build() and renderSpec use.
if nargin < 3 || isempty(rs), rs = sch.stream(); end
ctx = params;

set = sch.Set;
n   = set.numStimuli;

% Design.
ctx.numStimuli        = n;
ctx.repetitions       = sch.normalizedRepetitions();
ctx.alternatePolarity = set.alternatesPolarity();
ctx.IDs               = set.IDs();
if n == 0, ctx.durations = zeros(1,0); else, ctx.durations = set.duration(1:n); end
ctx.params            = set.paramTable();

% Timing.
ctx.sampleRate    = set.SampleRate;
ctx.isi           = sch.ISI;
ctx.isiMode       = sch.ISIMode;
ctx.isiRange      = sch.ISIRange;
ctx.minISI        = sch.MinISI;
ctx.meanISI       = sch.MeanISI;
ctx.silencePad    = sch.SilencePad;
ctx.maxRunSamples = sch.Config.maxInputBufferLength;

% Reproducibility.
ctx.randStream = rs;
end
