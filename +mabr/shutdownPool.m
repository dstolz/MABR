function [ok,why] = shutdownPool()
% mabr.shutdownPool  Delete the parallel pool MABR's workers ran on.
%
%   [ok,why] = mabr.shutdownPool() deletes the current parallel pool and
%   returns whether it did, with a one-line reason either way. It is the
%   counterpart of mabr.pool: that makes the pool the workers need, this
%   takes it away again once nothing needs it.
%
%   It exists because MABR's workers never return on their own -- the
%   acquisition loop runs for the whole session -- so killing them (which is
%   what deleting an Engine/ComputeEngine does) frees the pool's slots but
%   leaves the pool itself, and with it one to three idle worker processes
%   holding a MATLAB's worth of memory each for as long as the session lasts.
%   Closing the GUI is the moment that stops being wanted, which is why
%   mabr.ui.App.delete calls this (see the ShutdownPool preference).
%
%   A BUSY pool is never deleted. By the time the App gets here its own
%   workers have been killed and waited for, so anything still running or
%   queued belongs to somebody else -- another parfor in the same MATLAB
%   session -- and cancelling that would cost work MABR knows nothing about.
%   This is the same rule mabr.pool applies before resizing one, for the same
%   reason, and it is why ok is a report rather than a promise.
%
%   Safe to call with no pool open (ok = false, and why says so).
%
% See also mabr.pool
%
% Daniel Stolzberg (c) 2026

ok = false;

pool = gcp('nocreate');
if isempty(pool)
    why = 'No parallel pool was open.';
    return
end

if pool_busy(pool)
    why = ['The parallel pool is still busy, so it was left running ' ...
           '(something other than MABR is using it).'];
    mabr.log.vprintf(1,'%s',why);
    return
end

n = pool.NumWorkers;
try
    delete(pool);
    ok  = true;
    why = sprintf('Parallel pool shut down (%d worker(s) released).',n);
    mabr.log.vprintf(1,'%s',why);
catch me
    why = sprintf('Could not shut down the parallel pool: %s',me.message);
    mabr.log.vprintf(0,1,'%s',why);
end
end


% =====================================================================
function tf = pool_busy(pool)
% Anything running or waiting on the pool's feval queue. The properties exist
% from R2019b; a release without them is treated as busy, which is the safe
% answer (the pool is kept). Same test as mabr.pool's.
tf = true;
try
    q  = pool.FevalQueue;
    tf = ~isempty(q.RunningFutures) || ~isempty(q.QueuedFutures);
catch %#ok<CTCH>
end
end
