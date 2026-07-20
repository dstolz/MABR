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

h = mabr.ui.App;

if nargout == 0, clear h; end
end
