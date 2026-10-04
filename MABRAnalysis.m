function h = MABRAnalysis(varargin)
% MABRAnalysis  Open the MABR offline analysis app.
%
%   MABRAnalysis                 open the analysis window (or raise the one
%                                already open), reopening the last session
%   MABRAnalysis(root)           ... and open the data folder ROOT
%   MABRAnalysis(root,Name=Value)  ... with any option of mabr.ui.AnalysisApp
%   app = MABRAnalysis(...)      the mabr.ui.AnalysisApp
%
%   The analysis app works on saved .abr files: label timepoints, analyse,
%   review thresholds and peaks, compare a study, export for R. It needs no
%   audio device and no parallel pool, so it can run in a second MATLAB
%   beside one that is acquiring -- which is the recommended way on a rig,
%   since an analysis in the acquiring MATLAB holds up its live view. (In
%   MABR itself: File > Offline Analysis….)
%
%   Like MABR, it puts the toolbox (every subfolder except .git) on the path
%   and points the logger at this installation first, so its messages land
%   in <root>/.error_logs with MABR's own.
%
%   See also mabr.ui.AnalysisApp, MABR, mabr.analysis.Session
%
% Daniel Stolzberg (c) 2026

rootDir = fileparts(mfilename('fullpath'));

% add every subfolder except .git (the MABR.m rule)
p = split(string(genpath(rootDir)),pathsep);
p(p == "" | contains(p,'.git')) = [];
addpath(char(join(p,pathsep)));

[hasLog,why] = mabr.log.configure();
if ~hasLog
    warning('MABR:granaryMissing','%s',why);
end

% One analysis window: a second call raises the open one (and opens ROOT in
% it when one is given) rather than building another.
app = mabr.ui.AnalysisApp(varargin{:},'Instance',"reuse");

if nargout, h = app; end
end
