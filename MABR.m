function h = MABR(rootDir)
% MABR  Launch the MABR acquisition GUI.
%
%   MABR adds the toolbox (all subfolders except .git) to the MATLAB path and
%   opens the acquisition app, mabr.ui.App. Windows-only.
%
%   As of the ground-up rewrite this points at the +mabr namespace; the legacy
%   +abr package was retired at cutover (recoverable from git history / the
%   master branch).
%
%   Two git submodules live under external/ and are picked up by the same
%   genpath: granary, the logger behind every message MABR prints and every
%   line in .error_logs/, and stimgen, the suggested source of calibrated
%   stimuli. Fetch both with "git submodule update --init". stimgen is
%   optional at runtime; granary is not, and a clone missing it launches with
%   a warning and no log file (see mabr.log.granaryAvailable).
%
% Daniel Stolzberg (c) 2019-2026

if ~ispc
    warning('MABR:windowsOnly','MABR is Windows-only.');
    if nargout, h = []; end
    return
end

if nargin == 0 || isempty(rootDir)
    rootDir = fileparts(mfilename('fullpath'));
end

% add every subfolder except .git
p = split(string(genpath(rootDir)),pathsep);
p(p == "" | contains(p,'.git')) = [];
addpath(char(join(p,pathsep)));

% Wire the logger to this installation before anything logs, so the first
% message of the session already lands in <root>/.error_logs rather than in
% whatever granary's defaults would have chosen. Said here rather than left to
% the first mabr.log.vprintf only so a missing submodule is reported at the
% one moment the user is looking at the command window.
[hasLog,why] = mabr.log.configure();
if ~hasLog
    warning('MABR:granaryMissing','%s',why);
end

h = mabr.ui.App;

if nargout == 0, clear h; end
end
