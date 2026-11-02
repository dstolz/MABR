function [ok,why] = configure(cmd)
% mabr.log.configure  Wire granary to this MABR installation.
%
%   ok = mabr.log.configure() tells the granary logging package the four
%   things a library cannot discover about its host, and returns true when
%   granary is present and configured. It is idempotent and cheap after the
%   first call -- mabr.log.vprintf calls it once per MATLAB process, before
%   the first message, so nothing else has to remember to.
%
%   [ok,why] = ... also returns the reason for a false ok
%   (mabr.log.granaryAvailable's message).
%
%   mabr.log.configure('-reset') forgets the cached answer and wires granary
%   again, rebuilding the logger. Two cases need it, and restarting MABR is
%   the ordinary route for both: the submodule fetched and added to the path
%   mid-session, and anything that has reset granary's own settings out from
%   under MABR -- notably granary's smoke test (external/granary/tests, which
%   MABR.m's genpath puts on the path), which finishes with
%   granary.config('-reset') and so leaves the session logging to <tempdir>
%   with the caller column unattributed. The cached answer is deliberately not
%   re-verified per message: this is called on every one, suppressed messages
%   included, and granary's whole gate costs less than the check would.
%
%   What is configured, and why each matters here:
%
%     LogRoot     mabr.Config.root. granary's default is tempdir; MABR has
%                 always kept its daily log with the toolbox, in
%                 <repo>/.error_logs/error_log_<ddmmmyyyy>.txt, and the
%                 offline half of a bug report goes looking for it there.
%                 With LogDirName below this reproduces that path exactly, so
%                 the change of logger does not move anybody's logs.
%
%     PrefGroup   'MABR'. The operator's log-directory override then lands in
%                 the same preference group as every other MABR setting
%                 (ArtifactPolicy, FilterPolicy, AudioSettings, ViewPolicy,
%                 WindowPos), rather than in a second group named after a
%                 dependency. A rig whose toolbox sits on a read-only or
%                 synced share sets it with granary.setLogDir.
%
%     FacadeFiles {'vprintf.m','StimgenLogSink.m'} -- the one that bites.
%                 granary attributes each log line to the frame that raised
%                 it, found by skipping its own package and any front door the
%                 host registers. MABR has two: mabr.log.vprintf, which every
%                 call site goes through, and mabr.log.StimgenLogSink, which
%                 forwards stimgen's messages in. Unnamed, both would appear
%                 as the origin of every message they carry, at one fixed line,
%                 and the caller column of the log would say nothing.
%                 'vprintf.m' is matched by filename, so it also covers
%                 stimgen's own front door (+stimgen/+util/vprintf.m) and
%                 attribution passes through to the stimgen code that logged --
%                 which is the point of the sink.
%
%   Nothing here throws. Logging runs inside catch blocks, and a logger that
%   raised while being set up would replace the failure the operator needed to
%   see. A missing submodule is reported through ok/why, not an error; see
%   mabr.log.granaryAvailable for what MABR does without it.
%
%   Called from every process that logs, not just the GUI: granary's settings
%   are per-MATLAB-session, and the acquisition and compute workers are
%   separate processes with their own copy. Without this a worker's messages
%   would go to <tempdir>/.error_logs instead of the session's own file.
%
%   See also mabr.log.vprintf, mabr.log.granaryAvailable, mabr.log.logFile,
%            granary.config, granary.setLogDir.
%
% Daniel Stolzberg (c) 2026

persistent done reason

if nargin > 0 && (ischar(cmd) || isstring(cmd)) && strcmp(char(cmd),'-reset')
    done   = [];
    reason = '';
end

if ~isempty(done)
    ok  = done;
    why = reason;
    return
end

[ok,why] = mabr.log.granaryAvailable();

if ok
    try
        % A log root the process cannot write to -- a read-only clone, a
        % share without write access -- used to make granary try once, latch
        % a failure, print one stderr line and drop every message after it,
        % while logFile still returned the path nothing was written to. So
        % the folder is tried first, and tempdir stands in when it fails.
        logRoot = mabr.Config.root;
        logDir  = fullfile(logRoot,'.error_logs');
        if ~writable(logDir)
            fprintf(2,['MABR: cannot write to %s; this session logs to %s instead. ' ...
                'Set the log folder with granary.setLogDir.\n'],logDir,fullfile(tempdir,'.error_logs'));
            logRoot = tempdir;
        end
        granary.config( ...
            'LogRoot',     logRoot, ...
            'LogDirName',  '.error_logs', ...
            'PrefGroup',   'MABR', ...
            'FacadeFiles', {'vprintf.m','StimgenLogSink.m'});
        % Rebuild the session logger against those settings. A sink resolves
        % its directory when it is constructed, so a logger built by an
        % earlier granary.printf -- before MABR configured anything -- is
        % already pointed at tempdir and would stay there.
        granary.Logger.instance('-reset');
        pruneOldLogs(fullfile(logRoot,'.error_logs'));
    catch me
        ok  = false;
        why = sprintf('granary could not be configured: %s',me.message);
    end
end

done   = ok;
reason = why;
end


% =====================================================================
function tf = writable(folder)
% Whether this process can create files in `folder` (made if absent).
tf = false;
try
    if ~isfolder(folder)
        [made,~] = mkdir(folder);
        if ~made, return; end
    end
    probe = fullfile(folder,sprintf('.write_probe_%d',feature('getpid')));
    fid = fopen(probe,'w');
    if fid < 0, return; end
    fclose(fid);
    delete(probe);
    tf = true;
catch
end
end

function pruneOldLogs(folder)
% Daily logs older than the preference MABR/LogRetentionDays (default 365;
% 0 or less keeps everything) are deleted, and the deletion is said in the
% log that remains. Nothing pruned them before: the folder only ever grew (46
% daily files, back to the first rig session), and the ddmmmyyyy names sort
% by day of month rather than by date, so the oldest were also the hardest to
% find.
try
    days = getpref('MABR','LogRetentionDays',365);
    if ~(isnumeric(days) && isscalar(days) && isfinite(days) && days > 0), return; end
    d = dir(fullfile(folder,'error_log_*.txt'));
    old = d([d.datenum] < now - days); %#ok<TNOW1>
    for k = 1:numel(old)
        delete(fullfile(old(k).folder,old(k).name));
    end
    if ~isempty(old)
        granary.printf(1,'Pruned %d daily log(s) older than %g days from %s (preference MABR/LogRetentionDays).', ...
            numel(old),days,folder);
    end
catch
    % A log that cannot be pruned is still a log.
end
end
