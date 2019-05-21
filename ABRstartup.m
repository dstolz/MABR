function ABRstartup(rootDir)

if nargin == 0 || isempty(rootDir), rootDir = cd; end

addpath(rootDir);

addpath(genpath(fullfile(rootDir,'external')));
addpath(genpath(fullfile(rootDir,'helpers')));

a = abr.Universal;
a.banner;
delete(a); clear a


