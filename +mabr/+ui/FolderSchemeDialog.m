function scheme = FolderSchemeDialog(scheme0,root,ctx,meta,params)
% mabr.ui.FolderSchemeDialog  Modal editor for where a session's files go.
%
%   s = mabr.ui.FolderSchemeDialog(s0) opens a small modal window over a
%   mabr.FolderScheme and returns the edited scheme, or [] if the user
%   cancelled.
%
%   s = mabr.ui.FolderSchemeDialog(s0,root,ctx,meta,params) draws the preview
%   from the session as it stands: root is the Output folder ('' for none),
%   ctx a mabr.FolderScheme.context, meta one stimulus's metadata (the first
%   of the loaded bank; [] for none), and params the bank's parameter names,
%   which the Insert list offers and the pattern is checked against.
%
%   The pattern is typed, or built from the Preset and Insert lists. Insert
%   appends: an edit field does not say where its cursor is.
%
%   Nothing here moves a file already written. A change applies from the
%   next Start; a schedule already running keeps the folder it began in.
%
%   See also mabr.FolderScheme, mabr.ui.App.
%
% Daniel Stolzberg (c) 2026

if nargin < 1 || isempty(scheme0), scheme0 = mabr.FolderScheme; end
if nargin < 2, root = ''; end
if nargin < 3 || isempty(ctx), ctx = mabr.FolderScheme.context(); end
if nargin < 4, meta = []; end
if nargin < 5, params = {}; end
params = cellstr(params);

scheme = [];                         % [] unless OK is pressed
customKey = '<custom>';              % the Preset list's "whatever was typed"

presets  = mabr.FolderScheme.Presets;
tokHelp  = mabr.FolderScheme.tokenHelp();
% The bank's own parameters join the Insert list after the built-in tokens.
insTok   = tokHelp(:,1);
insLabel = strcat(tokHelp(:,1),{'  —  '},tokHelp(:,2));
for k = 1:numel(params)
    insTok{end+1,1}   = ['{' params{k} '}']; %#ok<AGROW>
    insLabel{end+1,1} = sprintf('{%s}  —  stimulus parameter (per condition)',params{k}); %#ok<AGROW>
end

% ---- layout -------------------------------------------------------------
fig = uifigure('Name','Session Folders','Position',[100 100 600 470], ...
    'WindowStyle','modal','Resize','off', ...
    'CloseRequestFcn',@(~,~) onCancel());
mabr.ui.WindowPos.restore(fig,'FolderSchemeDialog',fig.Position);

g = uigridlayout(fig,[9 4]);
g.RowHeight   = {24,28,28,28,'1x',18,52,40,32};
g.ColumnWidth = {80,'1x','fit','fit'};
g.Padding     = [12 10 12 10];
g.RowSpacing  = 6;

% Row 1: on/off
onCheck = uicheckbox(g,'Value',scheme0.Enabled, ...
    'Text','Save each Start in a folder of its own, under the Output folder', ...
    'Tooltip',['Off: every file goes straight into the Output folder, as before. ' ...
               'The pattern is kept either way.'], ...
    'ValueChangedFcn',@(~,~) onChange());
onCheck.Layout.Row = 1; onCheck.Layout.Column = [1 4];

% Row 2: the pattern
patLbl = uilabel(g,'Text','Pattern');
patLbl.Layout.Row = 2; patLbl.Layout.Column = 1;
patField = uieditfield(g,'text','Value',scheme0.Pattern, ...
    'Tooltip',['Folders separated by / or \. {Tokens} are filled in at Start; ' ...
               'everything else is kept as typed.'], ...
    'ValueChangedFcn',@(~,~) onChange(), ...
    'ValueChangingFcn',@(~,e) onChange(e.Value));
patField.Layout.Row = 2; patField.Layout.Column = [2 4];

% Row 3: presets
preLbl = uilabel(g,'Text','Preset');
preLbl.Layout.Row = 3; preLbl.Layout.Column = 1;
preDrop = uidropdown(g,'Items',[{'Custom'} presets(:,2)'], ...
    'ItemsData',[{customKey} presets(:,1)'], ...
    'Tooltip','Replace the pattern with one of these.', ...
    'ValueChangedFcn',@(~,~) onPreset());
preDrop.Layout.Row = 3; preDrop.Layout.Column = [2 4];

% Row 4: insert a token
insLbl = uilabel(g,'Text','Insert');
insLbl.Layout.Row = 4; insLbl.Layout.Column = 1;
insDrop = uidropdown(g,'Items',insLabel(:)','ItemsData',insTok(:)', ...
    'Tooltip','A token to add to the end of the pattern.');
insDrop.Layout.Row = 4; insDrop.Layout.Column = 2;
sepDrop = uidropdown(g,'Items',{'_ then','- then','\ new folder','nothing'}, ...
    'ItemsData',{'_','-','/',''},'Value','_', ...
    'Tooltip','What goes between the pattern and the inserted token.');
sepDrop.Layout.Row = 4; sepDrop.Layout.Column = 3;
insBtn = uibutton(g,'Text','Insert','ButtonPushedFcn',@(~,~) onInsert());
insBtn.Layout.Row = 4; insBtn.Layout.Column = 4;

% Row 5: what the tokens are
rows = strcat({'  '},pad(tokHelp(:,1)),{'  '},pad(tokHelp(:,2)),{'  e.g. '},tokHelp(:,3));
txt = [{'Session tokens (one folder per Start), then stimulus tokens (one folder per condition):'}; ...
       rows; ...
       {['  {<parameter>}       any stimulus parameter by name, e.g. {Frequency}, {Level:%03g}' ...
         '  — a number may carry a printf format']}];
helpArea = uitextarea(g,'Value',txt,'Editable','off','FontName','Consolas','FontSize',11);
helpArea.Layout.Row = 5; helpArea.Layout.Column = [1 4];

% Rows 6-7: the preview
prevLbl = uilabel(g,'Text','Files from the next Start will be saved in:','FontWeight','bold');
prevLbl.Layout.Row = 6; prevLbl.Layout.Column = [1 4];
prevArea = uitextarea(g,'Editable','off','FontName','Consolas','FontSize',11, ...
    'Tooltip','Worked out from the current subject, bank and Output folder, as of now.');
prevArea.Layout.Row = 7; prevArea.Layout.Column = [1 4];

% Row 8: validation
msgLbl = uilabel(g,'Text','','WordWrap','on','VerticalAlignment','top');
msgLbl.Layout.Row = 8; msgLbl.Layout.Column = [1 4];

% Row 9: transport
defBtn = uibutton(g,'Text','Default', ...
    'Tooltip',['Back to ' mabr.FolderScheme.DefaultPattern], ...
    'ButtonPushedFcn',@(~,~) onDefault());
defBtn.Layout.Row = 9; defBtn.Layout.Column = 1;
okBtn = uibutton(g,'Text','OK','BackgroundColor',[0.6 0.9 0.6], ...
    'FontWeight','bold','ButtonPushedFcn',@(~,~) onOK());
okBtn.Layout.Row = 9; okBtn.Layout.Column = 3;
cancelBtn = uibutton(g,'Text','Cancel','ButtonPushedFcn',@(~,~) onCancel());
cancelBtn.Layout.Row = 9; cancelBtn.Layout.Column = 4;

onChange();
uiwait(fig);

% ===================== nested callbacks ==================================
    function s = readControls(pattern)
        if nargin < 1, pattern = patField.Value; end
        s = mabr.FolderScheme([],onCheck.Value);
        s.Pattern = strtrim(char(pattern));
    end

    function onChange(pattern)
        % pattern: the text being typed (ValueChangingFcn), which Value does
        % not hold until the field loses focus.
        if ~isgraphics(fig), return; end
        if nargin < 1, s = readControls(); else, s = readControls(pattern); end

        on = s.Enabled;
        for h = {patField,preDrop,insDrop,sepDrop,insBtn,patLbl,preLbl,insLbl}
            h{1}.Enable = onOff(on);
        end

        kp = find(strcmp(presets(:,1),s.Pattern),1);
        if isempty(kp), preDrop.Value = customKey; else, preDrop.Value = presets{kp,1}; end

        [ok,err,warn] = s.validate(params);
        okBtn.Enable = onOff(ok);
        if ~ok
            msgLbl.Text = err;  msgLbl.FontColor = [0.8 0.2 0];
            prevArea.Value = {''};
            return
        end
        msgLbl.Text = warn;     msgLbl.FontColor = [0.55 0.4 0];

        prevArea.Value = previewLines(s);
    end

    function lines = previewLines(s)
        top = root;
        if isempty(top), top = '<Output folder>'; end
        sess = s.resolve(top,ctx);
        lines = {sess};
        if isstruct(meta)
            per = s.resolve(top,ctx,meta);
            % Only worth a second line when the stimulus moves the file.
            if ~strcmp(per,sess)
                id = '';
                if isfield(meta,'ID'), id = char(string(meta.ID)); end
                lines = {[sess '   (session: notes journal)']; ...
                         [per  '   (' id ')']};
            end
        end
    end

    function onPreset()
        if strcmp(preDrop.Value,customKey), return; end   % 'Custom' changes nothing
        patField.Value = preDrop.Value;
        onChange();
    end

    function onInsert()
        p = strtrim(patField.Value);
        sep = sepDrop.Value;
        if isempty(p) || any(p(end) == '/\'), sep = ''; end
        patField.Value = [p sep insDrop.Value];
        onChange();
    end

    function onDefault()
        onCheck.Value  = true;
        patField.Value = mabr.FolderScheme.DefaultPattern;
        onChange();
    end

    function onOK()
        s = readControls();
        if ~s.validate(params), return; end
        scheme = s;
        mabr.ui.WindowPos.remember(fig,'FolderSchemeDialog');
        delete(fig);
    end

    function onCancel()
        scheme = [];
        mabr.ui.WindowPos.remember(fig,'FolderSchemeDialog');
        delete(fig);
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end
