function MABR(rootDir)

if nargin == 0 || isempty(rootDir), rootDir = fileparts(which('ABRstartup')); end

addpath(rootDir);

abr.ControlPanel;

