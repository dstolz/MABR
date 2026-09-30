function [vals,errs,done] = evaluateJobs(C,jobs,budget,memo)
% mabr.compute.evaluateJobs  Evaluate online-analysis metrics over a
% condition table.
%
%   [vals,errs,done] = evaluateJobs(C,jobs) computes, for every job and every
%   condition, one number:
%
%       C      a condition table (mabr.compute.ConditionStore)
%       jobs   struct array, one metric each: .Fcn (v = Fcn(ctx), see
%              mabr.metrics.online.context), .Window ([t0 t1] ms, or [] for
%              all), .Name (for the error report), and optionally .Sig -- a
%              string naming the metric itself (see memo) -- and
%              .WhileAcquiring (default true): false leaves every LIVE
%              condition NaN without calling the metric, or even building
%              its context (see mabr.metrics.online.catalog)
%       vals   [nJobs x nConds] double, NaN wherever there is nothing to
%              report -- no sweeps yet, a metric that threw, or one that was
%              not reached (see budget)
%       errs   {nJobs x 1} '' or the message of the first error the job
%              raised this pass. A metric that throws costs its own point,
%              not the pass; the caller decides how often to say so.
%       done   [nJobs x nConds] logical, false for the cells a budget left
%              unevaluated -- so the caller can tell "not reached" from "NaN
%              is the honest answer"
%
%   evaluateJobs(C,jobs,budget) stops starting new cells once `budget`
%   seconds have elapsed and returns what it has. The metrics worker runs
%   under one so that a slow-but-finite metric over eighty conditions
%   publishes the conditions it finished rather than holding the whole
%   pass; without a budget every cell is evaluated. LIVE conditions are
%   evaluated first: they are the ones changing, and a budget spent on a
%   backlog of finished ones left them unreached, pass after pass.
%
%   evaluateJobs(C,jobs,budget,memo) remembers answers across passes in memo
%   (a containers.Map the caller keeps -- a handle, so it is updated in
%   place). Only a FINISHED condition's value is kept: its sweeps change only
%   when a block is merged into it, which changes its sweep count and so the
%   key -- (condition key, sweep and artifact counts, the job's Sig, its
%   window) -- while a live one changes every pass. A job with no Sig is never
%   remembered. Metrics are pure functions of their context by contract
%   (mabr.metrics.online.context), which is what makes a remembered value
%   the value. Re-evaluating every metric over every finished condition on
%   every pass made each pass cost the whole session so far.
%
%   The context (sweep selection, window, baseline) is built once per
%   condition and window, and shared by every job asking for that window.
%
%   This is the loop mabr.ui.MetricPlot.computeValues used to run for its one
%   metric, lifted out so the window and the metrics worker evaluate a metric
%   by the same steps: the context is built by mabr.metrics.online.context
%   from the condition's clean sweeps, the function is called once, and the
%   result is accepted only if it is one numeric or logical scalar.
%
%   See also mabr.metrics.online.context, mabr.metrics.online.catalog,
%   mabr.compute.ConditionStore, mabr.ui.MetricPlot.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 3 || isempty(budget), budget = Inf; end
if nargin < 4, memo = []; end
useMemo = isa(memo,'containers.Map');
MaxMemo = 20000;                    % entries; a long session's worth, then start over

nJ   = numel(jobs);
nC   = numel(C);
vals = nan(nJ,nC);
errs = repmat({''},nJ,1);
done = false(nJ,nC);
if nJ == 0 || nC == 0, return; end

if useMemo && memo.Count > MaxMemo, remove(memo,keys(memo)); end
sig    = cell(1,nJ);
onLive = true(1,nJ);                % evaluated over live conditions too
for j = 1:nJ
    sig{j} = '';
    if useMemo && isfield(jobs(j),'Sig') && ~isempty(jobs(j).Sig)
        sig{j} = [char(jobs(j).Sig) '|' windowKey(getf(jobs(j),'Window',[]))];
    end
    onLive(j) = logical(getf(jobs(j),'WhileAcquiring',true));
end

live  = logical([C.Live]);
order = [find(live) find(~live)];   % the changing conditions first

t0 = tic;
for i = order
    c = C(i);
    n = size(c.Sweeps,2);
    base = '';
    if useMemo && ~c.Live
        base = sprintf('%s|%d|%d|%d|',c.Key,n,c.NumTotal,c.NumArtifacts);
    end
    ctxs = {};                      % contexts built for this condition, by window
    wins = {};
    for j = 1:nJ
        if toc(t0) > budget, return; end
        done(j,i) = true;
        if n < 1, continue; end             % NaN: nothing to measure yet
        if c.Live && ~onLive(j), continue; end  % NaN: measured once it finishes

        key = '';
        if ~isempty(base) && ~isempty(sig{j})
            key = [base sig{j}];
            if isKey(memo,key), vals(j,i) = memo(key); continue; end
        end

        w = getf(jobs(j),'Window',[]);
        k = find(cellfun(@(x) isequal(x,w),wins),1);
        if isempty(k)
            info = struct('Window',w,'Label',c.Label, ...
                'ID',c.Key,'Params',c.Params,'NumTotal',c.NumTotal, ...
                'NumArtifacts',c.NumArtifacts,'Live',c.Live);
            ctxs{end+1} = mabr.metrics.online.context(c.Sweeps,c.Time,c.SampleRate,info); %#ok<AGROW>
            wins{end+1} = w; %#ok<AGROW>
            k = numel(ctxs);
        end

        try
            out = jobs(j).Fcn(ctxs{k});
            if (isnumeric(out) || islogical(out)) && isscalar(out)
                vals(j,i) = double(out);
            end
        catch me
            if isempty(errs{j}), errs{j} = me.message; end
            key = '';                       % a failure may not be the answer next time
        end
        if ~isempty(key), memo(key) = vals(j,i); end
    end
end
end


% =====================================================================
function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function k = windowKey(w)
if isempty(w), k = 'all'; else, k = sprintf('%bx,',double(w)); end
end
