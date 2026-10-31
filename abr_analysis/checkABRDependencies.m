function checkABRDependencies(caller, helpers, toolboxes)
% CHECKABRDEPENDENCIES  Stop with one clear message when the legacy pipeline's outside parts are missing.
%
%   checkABRDependencies(caller, helpers, toolboxes) is called first thing by each
%   abr_analysis entry point. The pipeline is not self-contained: it calls helper
%   functions from the author's separate helper_fnc repository and needs MATLAB
%   toolboxes that nothing else in MABR needs. Without this check the first call
%   dies deep inside the chain with "Undefined function 'parfor_progress'" and no
%   hint of where that function comes from.
%
%   Inputs
%     caller      Name of the calling function, for the message.
%     helpers     String array of helper_fnc function names the caller needs, e.g.
%                 ["parfor_progress" "colorcet"]. Default: none.
%     toolboxes   String array drawn from "statistics", "curvefit" and "signal"
%                 (Statistics and Machine Learning, Curve Fitting and Signal
%                 Processing Toolbox). Default: none.
%
%   Error id: abr_analysis:missingDependency (one error naming everything missing).
%
%   MABR deliberately does not ship copies of the helper_fnc functions: a copy in
%   this folder would shadow, or be shadowed by, the user's own checkout depending on
%   path order, and the two could silently disagree. The mabr.analysis classes and
%   the Analysis App (MABRAnalysis) need none of this.
%
% See also parseABRFiles, abrPermutationThreshold

arguments
    caller (1,1) string
    helpers (1,:) string = string.empty(1,0)
    toolboxes (1,:) string {mustBeMember(toolboxes, ["statistics","curvefit","signal"])} = string.empty(1,0)
end

% Look the helpers up by name instead of calling them, so nothing runs (and nothing
% is shadowed) just to find out whether it exists. exist returns 2, 3 or 6 for an M-,
% MEX or P-file; 7 would be a FOLDER of that name, which cannot be called.
isHere = arrayfun(@(h) any(exist(h, 'file') == [2 3 6]), helpers);
missingHelpers = helpers(~isHere);

% A toolbox counts as present only if a representative function resolves AND its
% license can be had: the function can be on the path of an unlicensed machine, and
% a license can be held for a toolbox whose files were never installed.
tbName    = struct('statistics', "Statistics and Machine Learning Toolbox", ...
                   'curvefit',   "Curve Fitting Toolbox", ...
                   'signal',     "Signal Processing Toolbox");
tbLicense = struct('statistics', "Statistics_Toolbox", ...
                   'curvefit',   "Curve_Fitting_Toolbox", ...
                   'signal',     "Signal_Toolbox");
tbProbe   = struct('statistics', "tinv", 'curvefit', "fit", 'signal', "firpm");

missingToolboxes = strings(1, 0);
for t = toolboxes
    if ~any(exist(tbProbe.(t), 'file') == [2 3 6]) || ~license('test', tbLicense.(t))
        missingToolboxes(end+1) = tbName.(t); %#ok<AGROW>
    end
end

if isempty(missingHelpers) && isempty(missingToolboxes)
    return
end

msg = sprintf('%s cannot run.', caller);
if ~isempty(missingHelpers)
    msg = sprintf(['%s\n\nMissing from the MATLAB path: %s.\nThese belong to the author''s separate helper_fnc ' ...
        'repository, which MABR does not ship (a copy here could shadow, or be shadowed by, your own):\n' ...
        '    https://github.com/dstolz/helper_fnc\nClone it and add it to the path, e.g. ' ...
        'addpath(genpath(''C:/src/helper_fnc'')).'], msg, strjoin(missingHelpers, ', '));
end
if ~isempty(missingToolboxes)
    msg = sprintf(['%s\n\nNot installed, or not licensed: %s.\nInstall it from Home > Add-Ons > Get Add-Ons ' ...
        '(your institution''s MATLAB license must include it).'], msg, strjoin(missingToolboxes, ', '));
end
msg = sprintf(['%s\n\nThe mabr.analysis classes and the Analysis App (>> MABRAnalysis) need none of this ' ...
    'and read the same .abr files.'], msg);

error('abr_analysis:missingDependency', '%s', msg);
end
