function h = MABR(rootDir)

if ~ispc
    vprintf(0,1,'No support yet for non-Windows operating systems! :(')
    return
end

if nargin == 0 || isempty(rootDir)
    rootDir = fileparts(mfilename('fullpath')); 
end

% addpath(rootDir);
pth = genpath(rootDir);


sep = ";";
if ~ispc(), sep = ":"; end

pth = split(pth,sep);

i = cellfun(@(a) isempty(a) || contains(a,'.git'),pth);

pth(i) = [];

pth = join(pth,sep);

addpath(char(pth));

h = abr.ControlPanel;

if nargout == 0, clear h; end
