function reps = RepetitionsDialog(stimuli,reps0,isi)
% mabr.ui.RepetitionsDialog  Modal editor for per-stimulus repetition counts.
%
%   reps = mabr.ui.RepetitionsDialog(stimuli) opens a small modal window over
%   a mabr.stim.StimulusSet and returns a 1xN vector of repetition counts, or
%   [] if the user cancelled.
%
%   reps = mabr.ui.RepetitionsDialog(stimuli,reps0,isi) seeds the editor with
%   reps0 and uses isi (s) to estimate how long the resulting schedule runs.
%
%   Two modes:
%       Same for all   one spinner drives every entry; the table is read-only
%       Per stimulus   the table is editable, one row per stimulus ID
%
%   The running total (presentations and estimated acquisition time) updates
%   as values change, so an over-ambitious schedule is obvious before the run
%   rather than forty minutes into it.
%
%   See also mabr.stim.Schedule, mabr.stim.StimulusSet.
%
% Daniel Stolzberg (c) 2026

n   = stimuli.numStimuli;
ids = string(stimuli.IDs());

if nargin < 2 || isempty(reps0)
    reps0 = mabr.stim.Schedule.startingRepetitions(stimuli);
end
reps0 = double(reps0(:)');
if isscalar(reps0), reps0 = repmat(reps0,1,n); end
if numel(reps0) < n, reps0(end+1:n) = 0; end
reps0 = max(0,round(reps0(1:n)));

if nargin < 3 || isempty(isi), isi = 1/21.1; end

reps = [];                              % [] unless OK is pressed
assert(n > 0,'mabr:ui:RepetitionsDialog:empty','No stimuli to configure.');

uniform = all(reps0 == reps0(1));

% ---- layout -------------------------------------------------------------
fig = uifigure('Name','Repetitions','Position',[100 100 440 480], ...
    'WindowStyle','modal','Resize','off', ...
    'CloseRequestFcn',@(~,~) onCancel());

g = uigridlayout(fig,[5 3]);
g.RowHeight   = {30,30,'1x','fit',34};
g.ColumnWidth = {'fit','1x','fit'};

% Row 1: mode
lbl(g,'Mode',1,1);
modeDrop = uidropdown(g,'Items',{'Same for all stimuli','Per stimulus'}, ...
    'ValueChangedFcn',@(~,~) onMode());
modeDrop.Layout.Row = 1; modeDrop.Layout.Column = [2 3];
if uniform, modeDrop.Value = 'Same for all stimuli';
else,       modeDrop.Value = 'Per stimulus'; end

% Row 2: the "all" spinner
lbl(g,'Repetitions',2,1);
spin = uispinner(g,'Limits',[0 Inf],'RoundFractionalValues','on', ...
    'Step',16,'Value',reps0(1),'ValueChangedFcn',@(~,~) onSpin());
spin.Layout.Row = 2; spin.Layout.Column = 2;
applyBtn = uibutton(g,'Text','Apply to all','ButtonPushedFcn',@(~,~) onSpin());
applyBtn.Layout.Row = 2; applyBtn.Layout.Column = 3;

% Row 3: per-stimulus table
tbl = uitable(g,'Data',makeTable(reps0), ...
    'ColumnName',{'Stimulus ID','Repetitions'}, ...
    'ColumnEditable',[false true], ...
    'ColumnWidth',{'auto',110}, ...
    'CellEditCallback',@(~,e) onEdit(e));
tbl.Layout.Row = 3; tbl.Layout.Column = [1 3];

% Row 4: running total
totalLbl = uilabel(g,'Text','','FontColor',[0.3 0.3 0.3]);
totalLbl.Layout.Row = 4; totalLbl.Layout.Column = [1 3];

% Row 5: transport
okBtn = uibutton(g,'Text','OK','BackgroundColor',[0.6 0.9 0.6], ...
    'ButtonPushedFcn',@(~,~) onOK());
okBtn.Layout.Row = 5; okBtn.Layout.Column = 2;
cancelBtn = uibutton(g,'Text','Cancel','ButtonPushedFcn',@(~,~) onCancel());
cancelBtn.Layout.Row = 5; cancelBtn.Layout.Column = 3;

onMode();
uiwait(fig);

% ===================== nested callbacks ==================================
    function T = makeTable(r)
        % Plain variable names (the display names live in ColumnName) and
        % cellstr IDs, so this works back to the R2018b floor in Config.
        T = table(cellstr(ids(:)),r(:),'VariableNames',{'ID','Repetitions'});
    end

    function r = currentReps()
        r = double(tbl.Data.Repetitions)';
    end

    function onMode()
        perStim = strcmp(modeDrop.Value,'Per stimulus');
        tbl.ColumnEditable = [false perStim];
        spin.Enable     = onOff(~perStim);
        applyBtn.Enable = onOff(~perStim);
        if ~perStim, onSpin(); else, refreshTotal(); end
    end

    function onSpin()
        % "Same for all" is authoritative: push the spinner into every row.
        tbl.Data.Repetitions(:) = spin.Value;
        refreshTotal();
    end

    function onEdit(e)
        % uitable lets a bad edit through; clamp it and write the value back.
        v = e.NewData;
        if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v < 0
            tbl.Data.Repetitions(e.Indices(1)) = e.PreviousData;
        else
            tbl.Data.Repetitions(e.Indices(1)) = round(v);
        end
        refreshTotal();
    end

    function refreshTotal()
        r     = currentReps();
        total = sum(r);
        secs  = total*isi;
        totalLbl.Text = sprintf('%d stimuli  ·  %d presentations  ·  ~%s at %.2f ms ISI', ...
            n,total,durationText(secs),1e3*isi);
        if total == 0
            totalLbl.FontColor = [0.8 0.2 0];
            okBtn.Enable = 'off';
        else
            totalLbl.FontColor = [0.3 0.3 0.3];
            okBtn.Enable = 'on';
        end
    end

    function onOK()
        reps = currentReps();
        delete(fig);
    end

    function onCancel()
        reps = [];
        delete(fig);
    end
end

% ======================= local helpers ================================
function h = lbl(g,txt,r,c)
h = uilabel(g,'Text',txt);
h.Layout.Row = r; h.Layout.Column = c;
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function s = durationText(secs)
if secs < 90
    s = sprintf('%.0f s',secs);
elseif secs < 3600
    s = sprintf('%d min %02d s',floor(secs/60),round(mod(secs,60)));
else
    s = sprintf('%d h %02d min',floor(secs/3600),round(mod(secs,3600)/60));
end
end
