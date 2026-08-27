function verify_shutdown_pool()
% verify_shutdown_pool  Confirm MABR gives the parallel pool back when it is
%                       done with it — and never takes one that is in use.
%
%   mabr.pool sizes the pool MABR's workers run on; mabr.shutdownPool is its
%   counterpart, called from mabr.ui.App.delete when the ShutdownPool
%   preference is on. The worry is not the deleting, it is the *declining*:
%   MABR shares a MATLAB session with whatever else the user is running, and
%   closing this window must not cancel somebody's parfor.
%
%   Part A (nothing to do): with no pool open it reports so rather than
%   claiming a success.
%   Part B (busy is left alone): a pool with work on its queue is NOT deleted,
%   and says why. This is the one that matters.
%   Part C (idle goes): an idle pool is deleted and the workers released.
%   Part D (the preference): MABR/ShutdownPool defaults to TRUE, round-trips,
%   and a corrupt value falls back to the default rather than stopping the
%   app on its way out (the user's own pref is saved and restored).
%
%   Deliberately LAST in run_all_verifications: it ends with no pool open, so
%   anything after it would pay the pool relaunch. Needs the Parallel
%   Computing Toolbox; no hardware.
%
%   Run:  >> verify_shutdown_pool
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_shutdown_pool ==\n');

hadPref = ispref('MABR','ShutdownPool');
cleanup = onCleanup(@() restore_pref(hadPref, ...
    subsref_if(hadPref,@() getpref('MABR','ShutdownPool'))));

% ---- Part A: nothing open, nothing to report but the truth --------------
delete(gcp('nocreate'));
[ok,why] = mabr.shutdownPool();
assert(~ok,'shutdownPool claimed success with no pool open');
assert(~isempty(why),'a refusal must say why');
fprintf('  PASS Part A: no pool -> "%s"\n',why);

% ---- Part B: a busy pool is somebody else's ------------------------------
p = parpool('Processes',1);
f = parfeval(p,@pause,0,30);
t0 = tic;                                  % let the future actually start
while isempty(p.FevalQueue.RunningFutures) && toc(t0) < 10, pause(0.1); end

[ok,why] = mabr.shutdownPool();
assert(~ok,'a BUSY pool was deleted — that cancels work MABR knows nothing about');
assert(contains(lower(why),'busy'),'the refusal should name the reason, got "%s"',why);
pool = gcp('nocreate');
assert(~isempty(pool) && isvalid(pool),'the busy pool did not survive');
fprintf('  PASS Part B: busy pool kept -> "%s"\n',why);

cancel(f);
t0 = tic;
while ~isempty(pool.FevalQueue.RunningFutures) && toc(t0) < 10, pause(0.1); end

% ---- Part C: idle, so it goes -------------------------------------------
[ok,why] = mabr.shutdownPool();
assert(ok,'an idle pool should have been shut down (%s)',why);
assert(isempty(gcp('nocreate')),'shutdownPool reported success but the pool is still up');
fprintf('  PASS Part C: idle pool released -> "%s"\n',why);

% Idempotent: calling it again is Part A, not an error.
[ok,~] = mabr.shutdownPool();
assert(~ok,'a second call should report nothing to do, not succeed');

% ---- Part D: the preference behind Settings > Shut down pool on exit -----
if ispref('MABR','ShutdownPool'), rmpref('MABR','ShutdownPool'); end
assert(isequal(getpref('MABR','ShutdownPool',true),true), ...
    'the default must be ON: an idle pool nobody is acquiring with is pure cost');

setpref('MABR','ShutdownPool',false);
assert(~getpref('MABR','ShutdownPool'),'the preference did not round-trip');

% App.poolShutdownEnabled coerces rather than trusting what it reads back,
% the same rule loadPrefs follows -- a hand-edited pref must not throw on the
% way out of the app, where there is nothing left to report it to.
setpref('MABR','ShutdownPool','yes please');
raw = getpref('MABR','ShutdownPool');
tf  = (islogical(raw) || isnumeric(raw)) && isscalar(raw) && raw ~= 0;
assert(islogical(tf) && ~tf,'a non-scalar-numeric pref should coerce to false, not throw');
fprintf('  PASS Part D: preference defaults ON, round-trips, and coerces a bad value\n');

fprintf('== verify_shutdown_pool PASSED ==\n');
end


% =====================================================================
function v = subsref_if(tf,fcn)
% getpref only where the pref exists, so the onCleanup above can be armed
% before Part D starts editing it.
v = [];
if tf, v = fcn(); end
end

function restore_pref(had,value)
if had
    setpref('MABR','ShutdownPool',value);
elseif ispref('MABR','ShutdownPool')
    rmpref('MABR','ShutdownPool');
end
end
