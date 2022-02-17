function h = MABR(rootDir)

if ~ispc
    vprintf(0,1,'No support yet for non-Windows operating systems! :(')
    return
end

if nargin == 0 || isempty(rootDir)
    s = dbstack('-completenames');
    rootDir = fileparts(s(1).file); 
end

addpath(rootDir);

h = abr.ControlPanel;

if nargout == 0, clear h; end
