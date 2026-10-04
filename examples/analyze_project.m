%ANALYZE_PROJECT  Analyse every session of a study folder with one set of settings, headless.
%
% Edit CONFIG and run it. It is the script form of the analysis app's
% "Analyse all": mabr.analysis.Batch.runFolder lists the study with a
% mabr.analysis.Catalog (its cache kept outside the data), opens the study's
% mabr.analysis.Project when there is one (its pools, exclusions and
% per-session overrides), and takes every session through
% mabr.analysis.Session.analyze with the settings below -- skipping the ones
% whose results are already current for those settings and files, carrying
% every curation, override and hand rejection of an existing results file
% over, and writing one results file per session into RESULTS, a log CSV
% line per session as it finishes (RESULTS/logs), and optionally a summary
% PNG per session (RESULTS/figures).
%
% The data folder is only READ: nothing is written under DATAROOT unless
% RESULTS is put there. Run it overnight; T at the end says what happened to
% each session, and a session that failed does not stop the others.
%
% Afterwards the results open in the analysis app (MABRAnalysis, pointed at
% the same results folder), or are read straight back:
%
%   s = mabr.analysis.Session.fromResults(T.ResultsFile(1));
%   s.Thresholds(:,["Key","Final","FinalCensored","Status"])
%
% See docs/Analysis-Classes.md (Batch, Settings, the named threshold methods).

%% ------------------------------------------------------------------ CONFIG
DATAROOT  = "D:/data/OFC_NoiseExposure";          % the study folder (read only)
RESULTS   = "D:/results/OFC_NoiseExposure";       % where results, logs and figures go
SETTINGS  = mabr.analysis.Settings();             % the recommended defaults (perm-glm thresholds)
% SETTINGS = mabr.analysis.Settings.profile("Legacy SCRATCH (2025)");   % the 2025 pipeline
% SETTINGS = mabr.analysis.Settings.load("myLab.mabraset");             % a saved set
FIGURES   = false;                                % a summary PNG per session
ONLYKEYS  = strings(0,1);                         % [] = every session, else catalog keys

%% ------------------------------------------------------------------ CHECK
assert(isfolder(DATAROOT),"No data folder %s.",DATAROOT);
p = SETTINGS.problems();
assert(all(p == ""),"The settings cannot be used: %s",strjoin(p,"; "));
fprintf('%s\n\n',SETTINGS.describe());
fprintf('Threshold: %s\n\n',SETTINGS.thresholdDefinition());

%% ------------------------------------------------------------------ RUN
t0 = tic;
T = mabr.analysis.Batch.runFolder(DATAROOT,SETTINGS, ...
    ResultsFolder=RESULTS, ...                    % never inside the data unless you say so
    Keys=ONLYKEYS, ...
    SummaryFigure=FIGURES, ...
    ProgressFcn=@showSession);

%% ------------------------------------------------------------------ REPORT
fprintf('\n%d session(s) in %.0f s:\n',height(T),toc(t0));
for s = unique(T.Status).'
    fprintf('  %-20s %d\n',s,sum(T.Status == s));
end
bad = T(T.Status == "failed",:);
for k = 1:height(bad)
    fprintf('  FAILED %s: %s\n',bad.Key(k),bad.Message(k));
end

%% ------------------------------------------------------------------ LOCAL FUNCTIONS
function showSession(msg,~,~)
% The batch's own progress lines ("Session 3 of 40: ..."); the sessions'
% step-by-step progress goes through the same sink and is not printed.
if startsWith(string(msg),"Session ")
    fprintf('  %s\n',msg);
end
end
