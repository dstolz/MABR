function [p,dir] = logFile()
% mabr.log.logFile  Path of the log file MABR is writing.
%
%   p = mabr.log.logFile() returns the full path of the daily log the next
%   message will land in -- <logdir>/error_log_<ddmmmyyyy>.txt -- which is
%   what "open the current log" means: today's file, whether or not anything
%   has been written to it yet. p is '' when granary is not on the path, since
%   nothing is being written (see mabr.log.granaryAvailable).
%
%   [p,dir] = ... also returns the directory holding it. By default that is
%   <repo>/.error_logs (mabr.log.configure points granary at it); an operator
%   whose toolbox sits on a read-only or synced share can move it with
%   granary.setLogDir, which is persisted in the MABR preference group.
%
%   The file is flushed before the path is returned, so a caller that is
%   about to read it -- a bug report, a diagnostic checking the log is live --
%   sees the tail rather than whatever had reached disk before the last
%   buffered write.
%
%   Never throws.
%
%   See also mabr.log.vprintf, mabr.log.configure, granary.setLogDir.
%
% Daniel Stolzberg (c) 2026

p   = '';
dir = '';

try
    if ~mabr.log.configure(), return; end
    L = granary.Logger.instance();
    L.flush();
    p = L.LogFile;
    if ~isempty(p), dir = fileparts(p); end
catch
    % A path lookup must not raise on a caller that is already reporting a
    % failure.
end
end
