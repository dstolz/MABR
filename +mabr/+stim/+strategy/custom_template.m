function runs = custom_template(ctx)
% mabr.stim.strategy.custom_template  Copy this to write your own presentation
% strategy, then select it from the GUI's Strategy dropdown (Custom…).
%
%   THE CONTRACT (see mabr.stim.strategy.context for the authoritative field
%   list). A strategy is a PURE FUNCTION FROM A DESIGN TO AN ORDER:
%
%       runs = my_strategy(ctx)
%
%   INPUT  ctx  a struct describing what there is to present and what it will
%               be presented at. The fields you will actually use:
%                 ctx.numStimuli        entries in the bank
%                 ctx.repetitions       [1 x n] presentations owed per entry
%                 ctx.alternatePolarity [1 x n] logical
%                 ctx.IDs               {1 x n} each entry's ID
%                 ctx.params            .Names / .Values [n x nP] / .Varying /
%                                       .Units -- the bank as a table, which
%                                       is how you order by Level or group by
%                                       Frequency without parsing IDs
%                 ctx.randStream        shuffle with THIS, never bare randperm
%                 ctx.maxRunSamples     one run is one ring-buffer pass
%               Read only the fields you need; ignore the rest. Any extra
%               field you put in Schedule.StrategyParams arrives here too.
%
%   OUTPUT runs  the order to present them in, as either:
%                  a vector          -> ONE run of those stimulus indices
%                  {vec1,vec2,...}   -> that many runs, in that order
%                  struct('Runs',...,'Polarities',...) -> only when you want
%                                       to place +1/-1 yourself
%                Indices are 1-based into the bank ctx describes. Polarity is
%                assigned for you unless you supply it, and is balanced across
%                the WHOLE plan, so a custom order gets the same signs the
%                built-in strategies would have given it.
%
%   THREE RULES.
%     1. SHUFFLE FROM ctx.randStream. randperm(ctx.randStream,n), not
%        randperm(n). Building a plan must not perturb global rng, and it is
%        what makes Schedule.Seed reproduce a whole session -- order and,
%        under ISIMode 'random', timing with it.
%     2. WATCH THE RUN LENGTH. One run is recorded in one pass of the ring
%        buffer, so roughly numel(run)*ctx.meanISI*ctx.sampleRate must stay
%        under ctx.maxRunSamples (~5.8 min at 192 kHz). renderSpec refuses a
%        longer one with mabr:stim:Schedule:tooLong rather than discarding the
%        earliest sweeps. Putting every presentation in one run is what makes
%        this bite: split into several and the ceiling is per-run.
%     3. PRESENT EACH ENTRY ITS ctx.repetitions COUNT, unless you mean not to.
%        Departing is allowed and is logged, not refused -- but the usual
%        cause is a cycle that assumed equal counts, not a design.
%
%   Strategies are built ONCE, when the plan is built, and never called again
%   during acquisition -- so unlike an advance criterion this may be as
%   expensive as it likes. It cannot adapt to incoming data for the same
%   reason; that is what an advance criterion is for.
%
%   ------------------------------------------------------------------------
%   THIS TEMPLATE'S OWN BEHAVIOUR, as a worked example: one run per condition
%   (so each still saves to its own .abr and early stop stays available), the
%   conditions grouped by Frequency and ordered LOUDEST FIRST within each.
%
%   None of the five built-in strategies can express it -- 'blocked' presents
%   in bank order and the shuffled ones scramble it -- and it is what an ABR
%   threshold series usually wants: the loud conditions respond visibly, so a
%   dead electrode or a slipped ear plug shows up in the first minute rather
%   than after twenty spent collecting noise near threshold.
%
%   A bank with no Level parameter simply comes back in bank order: a strategy
%   that errors on a bank missing the field it hoped for is worse than one
%   that degrades to the obvious thing.
%
%   See also mabr.stim.strategy.context, mabr.stim.strategy.validate,
%   mabr.stim.strategy.normalize, mabr.stim.Schedule.
%
% Daniel Stolzberg (c) 2019-2026

n = ctx.numStimuli;

level = paramColumn(ctx,'Level');       % [] when the bank does not carry one
freq  = paramColumn(ctx,'Frequency');

% Order the CONDITIONS: by frequency ascending (so the session walks the
% bank predictably), and within a frequency by level descending.
if isempty(level) && isempty(freq)
    order = 1:n;
else
    if isempty(freq),  freq  = zeros(n,1); end
    if isempty(level), level = zeros(n,1); end
    % sortrows over [frequency, -level]: ascending on the first, which
    % negating turns into descending on the second.
    [~,order] = sortrows([freq(:) -level(:)]);
    order = order(:)';
end

% One run per condition, each the full repetition train. Entries owed nothing
% are left out rather than emitted as an empty run.
runs = {};
for i = order
    if ctx.repetitions(i) <= 0, continue, end
    runs{end+1} = repmat(i,1,ctx.repetitions(i)); %#ok<AGROW>
end
end

function v = paramColumn(ctx,name)
% One named column of ctx.params.Values, or [] when the bank has no such
% parameter. Every strategy that reads a parameter by name needs this, and
% needs it to return empty rather than throw -- see the header.
v = [];
if ~isfield(ctx,'params') || ~isstruct(ctx.params) || isempty(ctx.params.Names)
    return
end
j = find(strcmpi(ctx.params.Names,name),1);
if isempty(j), return, end
v = ctx.params.Values(:,j);
end
