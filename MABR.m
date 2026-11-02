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

% Add every CODE subfolder: not .git or .github, not the daily logs or the
% runtime buffers, not docs/ or plans/, and not the submodules' own tests/,
% documentation/ and templates/ folders. contains(p,'.git') was a substring
% test -- a root such as ...\.gitrepos\MABR dropped every folder -- and
% genpath put twenty folders of non-code on the path (and savepath, which
% Installation.md recommends, froze them all). MABR's own tests/ stays:
% run_all_verifications and Help > Verification Tests... are found there.
% (MABRAnalysis.m applies the same rule.)
p  = cellstr(split(string(genpath(rootDir)),pathsep));
nonCode = ~cellfun(@isempty,regexp(p, ...
    '[\\/](\.git\w*|\.error_logs|\.runtime_data|docs|plans|documentation|templates)([\\/]|$)','once'));
subTests = contains(p,[filesep 'external' filesep]) & ...
    ~cellfun(@isempty,regexp(p,'[\\/]tests([\\/]|$)','once'));
p = p(~cellfun(@isempty,p) & ~nonCode & ~subTests);
addpath(strjoin(p,pathsep));

% Wire the logger to this installation before anything logs, so the first
% message of the session already lands in <root>/.error_logs rather than in
% whatever granary's defaults would have chosen. Said here rather than left to
% the first mabr.log.vprintf only so a missing submodule is reported at the
% one moment the user is looking at the command window.
[hasLog,why] = mabr.log.configure();
if ~hasLog
    warning('MABR:granaryMissing','%s',why);
end

% Only one MABR window may be open (mabr.ui.App enforces it by throwing).
% Typing MABR again is a reasonable thing to do, though, and not an error, so
% answer it here by raising the window that is already up.
existing = findall(groot,'Type','figure','Tag',mabr.ui.App.InstanceTag);
if ~isempty(existing)
    f = existing(1);
    try
        if isprop(f,'WindowState') && strcmp(f.WindowState,'minimized')
            f.WindowState = 'normal';
        end
    catch
    end
    figure(f);
    fprintf('MABR is already open -- brought the existing window to the front.\n');
    if nargout, h = []; end
    return
end

h = mabr.ui.App;

if nargout == 0, clear h; end
end
