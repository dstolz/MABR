function h = MABR(rootDir)

if nargin == 0 || isempty(rootDir)
    s = dbstack('-completenames');
    rootDir = fileparts(s(1).file); 
end

addpath(rootDir);

h = abr.ControlPanel;

if nargout == 0, clear h; end
