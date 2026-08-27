function [vals,errs,done] = evaluateJobs(C,jobs,budget)
% mabr.compute.evaluateJobs  Evaluate online-analysis metrics over a
% condition table.
%
%   [vals,errs,done] = evaluateJobs(C,jobs) computes, for every job and every
%   condition, one number:
%
%       C      a condition table (mabr.compute.ConditionStore)
%       jobs   struct array, one metric each: .Fcn (v = Fcn(ctx), see
%              mabr.metrics.online.context), .Window ([t0 t1] ms, or [] for
%              all), and .Name (for the error report)
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
%   pass; without a budget every cell is evaluated.
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

nJ   = numel(jobs);
nC   = numel(C);
vals = nan(nJ,nC);
errs = repmat({''},nJ,1);
done = false(nJ,nC);
if nJ == 0 || nC == 0, return; end

t0 = tic;
for i = 1:nC
    c = C(i);
    n = size(c.Sweeps,2);
    for j = 1:nJ
        if toc(t0) > budget, return; end
        done(j,i) = true;
        if n < 1, continue; end             % NaN: nothing to measure yet

        info = struct('Window',getf(jobs(j),'Window',[]),'Label',c.Label, ...
            'ID',c.Key,'Params',c.Params,'NumTotal',c.NumTotal, ...
            'NumArtifacts',c.NumArtifacts,'Live',c.Live);
        ctx = mabr.metrics.online.context(c.Sweeps,c.Time,c.SampleRate,info);

        try
            out = jobs(j).Fcn(ctx);
            if (isnumeric(out) || islogical(out)) && isscalar(out)
                vals(j,i) = double(out);
            end
        catch me
            if isempty(errs{j}), errs{j} = me.message; end
        end
    end
end
end


% =====================================================================
function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
