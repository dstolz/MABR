function [pool,ok] = pool(minWorkers,progressFcn)
% mabr.pool  The parallel pool MABR's workers run on, at least this large.
%
%   [pool,ok] = mabr.pool(minWorkers,progressFcn) returns the current pool if
%   it has at least minWorkers workers, and otherwise makes one that does:
%   ok is true when the pool returned is big enough.
%
%   A pool cannot be resized once it exists, and MABR's workers never return
%   (the acquisition loop runs for the whole session), so a parfeval onto a
%   full pool would sit queued forever. The size therefore has to be right
%   BEFORE the first worker launches -- which is why this is called by
%   mabr.ui.App.ensureController (from the compute-worker preference) and by
%   the verification scripts before they build a controller, and why
%   mabr.acq.Engine keeps reusing whatever pool exists rather than sizing one.
%
%   A pool that is too small is deleted and recreated ONLY while nothing is
%   running or queued on it; a busy one is returned as it is with ok = false,
%   and the caller decides (the App reports it and runs without compute
%   workers for the session). It is never shrunk: a bigger pool than asked
%   for costs nothing here.
%
%   If the cluster profile cannot supply minWorkers (a two-core machine
%   defaults to two), the error is reported and a single-worker pool is
%   made instead, again with ok = false -- acquisition must not depend on the
%   optional workers.
%
%   Lifted from mabr.acq.Engine.ensure_pool, which is unchanged and reuses
%   whatever this made.
%
% Daniel Stolzberg (c) 2026

if nargin < 1 || isempty(minWorkers), minWorkers = 1; end
if nargin < 2 || isempty(progressFcn), progressFcn = @(~) []; end
minWorkers = max(1,round(minWorkers));

progressFcn('Checking for a parallel pool…');
pool = gcp('nocreate');
ok   = false;

if ~isempty(pool)
    if pool.NumWorkers >= minWorkers
        progressFcn('Reusing the existing parallel pool.');
        ok = true;
        return
    end
    if pool_busy(pool)
        mabr.log.vprintf(1,1,['The parallel pool has %d worker(s), %d are needed, ' ...
            'and it is busy: keeping it as it is.'],pool.NumWorkers,minWorkers);
        return
    end
    progressFcn(sprintf('Restarting the parallel pool with %d workers…',minWorkers));
    delete(pool);
end

progressFcn(sprintf(['Starting parallel pool with %d worker(s) ' ...
    '(first launch can take ~30–60 s)…'],minWorkers));
try
    pool = make_pool(minWorkers);
    ok   = true;
catch me
    mabr.log.vprintf(0,1,'Could not start a %d-worker pool (%s); starting one worker.', ...
        minWorkers,me.message);
    progressFcn('Starting a single-worker parallel pool…');
    pool = make_pool(1);
    ok   = minWorkers <= 1;
end
end


% =====================================================================
function pool = make_pool(n)
try
    pool = parpool('Processes',n);
catch
    pool = parpool('local',n);      % older release fallback
end
end

function tf = pool_busy(pool)
% Anything running or waiting on the pool's feval queue. The properties
% exist from R2019b; a release without them is treated as busy, which is the
% safe answer (the pool is kept).
tf = true;
try
    q  = pool.FevalQueue;
    tf = ~isempty(q.RunningFutures) || ~isempty(q.QueuedFutures);
catch %#ok<CTCH>
end
end
