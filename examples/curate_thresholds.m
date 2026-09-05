%CURATE_THRESHOLDS  Load a saved mabr.analysis.Session results file and hand-curate its thresholds.
%
% Prompts for a results .mat file (written by mabr.analysis.Session.saveResults,
% e.g. from examples/quick_analysis.m), then walks its Thresholds table one row
% at a time: draws the level series the fit was made from (mabr.analysis.Plot.
% detection) plus the sweep-stack context for that frequency (Session.plotStack),
% prints the fitted value, and asks for a curated one. The fit itself is never
% touched -- mabr.analysis.Session.setThreshold only ever writes the parallel
% Curated/IsCurated columns, so the model's own answer stays on the record next
% to whatever a human decided. See mabr.analysis.Threshold and
% docs/Analysis-Classes.md.
%
% At each row, typed at the "curated value" prompt:
%   Enter (blank)   leave this row uncurated (Curated stays at the fitted value)
%   a number        curate to that level, e.g. 35
%   i               curate to Inf (no response at any level tested)
%   q               stop curating and go straight to review + save
%
% Curated results are written to a NEW file (default "<name>_curated.mat"
% beside the original), so the fit-only results are never overwritten silently.

%% ------------------------------------------------------------------ SELECT

[fn,pth] = uigetfile({'*.mat','Session results (*.mat)'}, ...
    'Select an analyzed session (saveResults output)');
if isequal(fn,0)
    fprintf('Cancelled.\n');
    return
end
ffn = fullfile(pth,fn);

s = mabr.analysis.Session.fromResults(ffn);
fprintf('\nLoaded %s\n',ffn);
disp(s);

if height(s.Thresholds) == 0
    error('curate_thresholds:noThresholds', ...
        '%s has no Thresholds table -- run estimateThresholds() before curating.',fn);
end


%% ------------------------------------------------------------------ CURATE
idCols = setdiff(string(s.Thresholds.Properties.VariableNames), ...
    ["Threshold","CILower","CIUpper","Curated","IsCurated","Type","FitTarget", ...
     "NumLevels","NumSig","Fit","LevelParam"],'stable');

fp = "";
try, fp = s.frequencyParam(); catch, end %#ok<CTCH>

fig     = figure('Name',sprintf('Curate thresholds -- %s',s.Name),'NumberTitle','off');
axFit   = subplot(1,2,1,'Parent',fig);
axStack = subplot(1,2,2,'Parent',fig);

nR   = height(s.Thresholds);
quit = false;
for row = 1:nR
    Trow  = s.Thresholds(row,:);           % re-read: reflects any prior curation
    label = rowLabel(Trow,idCols);

    % --- the level series the fit was made from -------------------------
    cla(axFit);
    hasFit = ismember('Fit',Trow.Properties.VariableNames) && ~isempty(Trow.Fit{1}) ...
        && isstruct(Trow.Fit{1}) && isfield(Trow.Fit{1},'X') && ~isempty(Trow.Fit{1}.X);
    if hasFit
        mabr.analysis.Plot.detection(Trow.Fit{1},Parent=axFit);
        if Trow.IsCurated && isfinite(Trow.Curated) && Trow.Curated ~= Trow.Threshold
            xline(axFit,Trow.Curated,'g-','curated','LineWidth',2,'LabelHorizontalAlignment','left');
        end
    else
        text(axFit,0.5,0.5,'(no fit saved for this row)', ...
            'HorizontalAlignment','center','Units','normalized');
    end
    subtitle(axFit,label,'Interpreter','none');

    % --- sweep-stack context, when this row has a frequency-like value --
    cla(axStack);
    if fp ~= "" && ismember(fp,string(Trow.Properties.VariableNames))
        try
            s.plotStack(Trow.(fp),Parent=axStack);
        catch ME
            text(axStack,0.5,0.5,sprintf('(stack unavailable: %s)',ME.message), ...
                'HorizontalAlignment','center','Units','normalized','Interpreter','none');
        end
    end
    drawnow;

    % --- prompt -----------------------------------------------------------
    fprintf('\n[%d/%d] %s\n',row,nR,label);
    fprintf('    fitted   : %s\n',fmtTh(Trow.Threshold));
    fprintf('    CI       : [%s, %s]\n',fmtTh(Trow.CILower),fmtTh(Trow.CIUpper));
    curNote = ''; if Trow.IsCurated, curNote = '  (already curated)'; end
    fprintf('    curated  : %s%s\n',fmtTh(Trow.Curated),curNote);
    fprintf('    levels   : %d, %d significant\n',Trow.NumLevels,Trow.NumSig);

    resp = strtrim(lower(input( ...
        '    curated value, i=no response, q=quit+save > ','s')));

    switch resp
        case ''
            % leave uncurated
        case 'q'
            quit = true;
        case 'i'
            s.setThreshold(row,Inf);
        otherwise
            v = str2double(resp);
            if isnan(v)
                fprintf('    Not understood; leaving row %d uncurated.\n',row);
            else
                s.setThreshold(row,v);
            end
    end

    if quit, break; end
end

close(fig);

%% ------------------------------------------------------------------ REVIEW
fprintf('\n%d of %d thresholds curated by hand.\n', ...
    sum(s.Thresholds.IsCurated),height(s.Thresholds));
s.plotAudiogram(CI = false);

%% ------------------------------------------------------------------ SAVE
[~,nm] = fileparts(ffn);
defaultOut = fullfile(pth,nm + "_curated.mat");
[ofn,opth] = uiputfile('*.mat','Save curated results as',defaultOut);
if isequal(ofn,0)
    fprintf('Not saved.\n');
else
    s.saveResults(fullfile(opth,ofn));
end

%% ------------------------------------------------------------------ LOCAL FUNCTIONS
function lbl = rowLabel(Trow,idCols)
% One line identifying a Thresholds row from its grouping columns.
%   Trow    a 1-row table (e.g. s.Thresholds(row,:))
%   idCols  string array of grouping column names to read off Trow
%   lbl     (returned) 1x1 string, e.g. "Frequency = 16"
if isempty(idCols)
    lbl = "(single series)";
    return
end
parts = strings(1,numel(idCols));
for k = 1:numel(idCols)
    v = Trow.(idCols(k));
    if isnumeric(v), parts(k) = idCols(k) + " = " + num2str(v);
    else,             parts(k) = idCols(k) + " = " + string(v);
    end
end
lbl = strjoin(parts,', ');
end

function str = fmtTh(v)
% Format one threshold value for the console. v: scalar double. str: (returned) string.
if isinf(v),      str = "Inf (no response)";
elseif isnan(v),  str = "NaN";
else,             str = sprintf('%.1f',v);
end
end
