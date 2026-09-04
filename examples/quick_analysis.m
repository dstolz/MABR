%QUICK_ANALYSIS  Kick off the mabr.analysis pipeline over one folder of .abr files.
%
% Edit the four settings under CONFIG and run it. It walks every session
% folder under DATAROOT, takes each one from filenames to thresholds
% (parse -> segment -> reject -> detect -> estimateThresholds), saves a
% plain-struct results file per session, and leaves a combined threshold
% table in the workspace variable ALL.
%
% Nothing here needs hardware, a parallel pool, or the GUI -- the analysis
% classes read saved .abr files and nothing else. See docs/Analysis-Classes.md.
%
% Re-analysing is cheap: the Session objects are kept in SESSIONS with their
% traces cached, so a second band or a stricter rejection is
%
%   s = SESSIONS(1);
%   s.Filter = mabr.analysis.Filter(HighPass=[100 200],LowPass=[2000 3000]);
%   s.segment(); s.reject(); s.detect(); s.estimateThresholds();
%
% with no disk reads.

%% ------------------------------------------------------------------ CONFIG
DATAROOT = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_data/";                  % folder to search (recursively)
RESULTS  = fullfile(DATAROOT,"analysis");       % where the .mat results go
PLOT     = true;                                % draw grid + audiogram per session
NPERM    = 1000;                                % permutation count (2000 for final)

%% ------------------------------------------------------------------ SESSIONS
paths = mabr.analysis.Session.find(DATAROOT);
assert(~isempty(paths),"No .abr files found under %s",DATAROOT);
fprintf('%d session folder(s) under %s\n\n',numel(paths),DATAROOT);

if ~isfolder(RESULTS), mkdir(RESULTS); end

SESSIONS = mabr.analysis.Session.empty(0,1);
ALL      = table();

for k = 1:numel(paths)
    fprintf('--- [%d/%d] %s\n',k,numel(paths),paths(k));
    try
        s = mabr.analysis.Session(paths(k), ...
                Window=[-12 12], ...            % sweep window, ms re onset
                ResponseWindow=[0 10]);         % what detection looks at

        s.segment();                            % FIR 300-3000 Hz, then cut sweeps
        s.reject(Method="median",Feature="absPeak");
        s.detect(Method="tfce",NumPermutations=NPERM,Seed=1);
        s.estimateThresholds(Type="glm",FitTarget="binary",Criterion=0.5);

        s.saveResults(fullfile(RESULTS,s.Name + ".mat"));

        if PLOT
            s.plotGrid();
            s.plotAudiogram();
        end

        T = s.Thresholds;
        T = removevars(T,intersect(["Fit","Detection"],string(T.Properties.VariableNames)));
        T.Session = repmat(s.Name,height(T),1);
        T.Subject = repmat(s.Subject,height(T),1);
        ALL = [ALL; T];                                            %#ok<AGROW>

        SESSIONS(end+1,1) = s;                                     %#ok<SAGROW>
    catch ME
        warning('%s failed: %s',paths(k),ME.message);
    end
end

%% ------------------------------------------------------------------ SUMMARY
if ~isempty(ALL)
    ALL = movevars(ALL,["Subject","Session"],'Before',1);
    disp(ALL);
    writetable(ALL,fullfile(RESULTS,"thresholds.csv"));
    fprintf('\nWrote %s\n',fullfile(RESULTS,"thresholds.csv"));
end
