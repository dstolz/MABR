function h = MABR(rootDir)

if nargin == 0 || isempty(rootDir), rootDir = fileparts(which('ABRstartup')); end

addpath(rootDir);

h = abr.ControlPanel;

if nargout == 0, clear h; end
