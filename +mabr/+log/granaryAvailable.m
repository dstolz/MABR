function [tf,msg] = granaryAvailable()
% mabr.log.granaryAvailable  Is the granary logging package on the path?
%
%   tf = mabr.log.granaryAvailable() returns true when granary
%   (external/granary, a git submodule) has been initialized and is visible to
%   MATLAB. granary is the logger behind mabr.log.vprintf: every message MABR
%   prints to the command window and every line in .error_logs/ goes through
%   it.
%
%   [tf,msg] = ... also returns an actionable message for the false case,
%   suitable for a status line, a warning, or a disabled control's tooltip.
%
%   Unlike stimgen (mabr.stim.stimgenAvailable), granary is NOT optional: it
%   is the toolbox's only logger, and a clone missing it loses the daily
%   .error_logs/ file that explains a failure after the fact. It is deliberately
%   not fatal either -- mabr.log.vprintf falls back to printing to the command
%   window and says so once, because a logger that throws would take down the
%   app at startup and, worse, make the error about the missing logger itself
%   unloggable. Fetch the submodule and restart to get the record back.
%
%   The class tested for is granary.Logger rather than the granary.printf
%   function, so a stale MABR-shaped shadow of the name on someone's path
%   cannot read as the package being present.
%
%   See also mabr.log.configure, mabr.log.vprintf, mabr.log.logFile.
%
% Daniel Stolzberg (c) 2026

tf = exist('granary.Logger','class') == 8;

if tf
    msg = '';
else
    msg = ['The granary logging package is not on the MATLAB path. It ships ' ...
           'as a git submodule: run "git submodule update --init" in the MABR ' ...
           'folder, then restart MABR. Until then MABR prints to the command ' ...
           'window but writes no log file.'];
end
end
