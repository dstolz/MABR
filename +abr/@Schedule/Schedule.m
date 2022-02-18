classdef Schedule < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public,Hidden)
        ScheduleFigure              matlab.ui.Figure
        FileMenu                    matlab.ui.container.Menu
        LoadScheduleMenu            matlab.ui.container.Menu
        SaveScheduleMenu            matlab.ui.container.Menu
        ScheduleMenu                matlab.ui.container.Menu
        SortbySelectedColumnMenu    matlab.ui.container.Menu
        RemoveRowsMenu              matlab.ui.container.Menu
        ResetScheduleMenu           matlab.ui.container.Menu
        DeselectAllRowsMenu         matlab.ui.container.Menu
        SelectEveryOtherRowMenu     matlab.ui.container.Menu
        CustomSelectionMenu         matlab.ui.container.Menu
        ToggleCurrentSelectionMenu  matlab.ui.container.Menu
        ScheduleTable               matlab.ui.control.Table
        ButtonPanel                 matlab.ui.container.Panel
        SortonColumnButton          matlab.ui.control.Button
        ResetButton                 matlab.ui.control.Button
        DeselectAllButton           matlab.ui.control.Button
        EveryOtherButton            matlab.ui.control.Button
        CustomButton                matlab.ui.control.Button
        ToggleButton                matlab.ui.control.Button
        LoadButton                  matlab.ui.control.Button
        SaveButton                  matlab.ui.control.Button
        LaunchSchDesGUIButton       matlab.ui.control.Button
        ScheduleInfoButton          matlab.ui.control.Button
        RemoveRowsButton            matlab.ui.control.Button
    end

    
    properties (Access = public)
        filename (1,:) char
        
        DO_NOT_DELETE (1,1) logical = false;
    end
    
    
    properties (SetAccess = private)
        SIG
        data
        compiled
        props
        
        scheduleDesignFilename (1,:) char
        
    end
    
    properties (Dependent)
        selectedData % rows currently selected (checked) in table
        sigArray
    end
    
    
    
    
    
    
    
    
    
    methods
        
        function a = get.sigArray(app)
            d = app.ScheduleTable.Data;
            a = repmat(app.SIG,size(d,1),1);
            for i = 1:length(app.props)
                for j = 1:size(d,1)
                    a(j).(app.props{i}).Value = d{j,i+1};
                end
            end
        end
        
        function s = get.selectedData(app)
            s = [];
            d = app.ScheduleTable.Data;
            if isempty(d), return; end
            s = [d{:,1}];
        end
        
        function p = get.props(app)
            if isempty(app.props)
                p = fieldnames(app.data);
%                 p = app.ScheduleTable.Data.Properties.VariableNames;
%                 p(ismember(p,'Selected')) = [];
            else
                p = app.props;
            end
        end
        
        function preprocess(app,SIG,props,data)
            
            app.SIG = SIG;
            
            for i = 1:length(props)
                ind = ismember(data(:,1),SIG.(props{i}).DescriptionWithUnit);
                if ~any(ind), continue; end
                
                P = app.SIG.(props{i});
                
                D.(props{i}).SIG = P; % store sigProp for later
                
                D.(props{i}).Alternate   = data{ind,2};
                D.(props{i}).Description = P.Description;
                
                switch P.Type
                    case 'String'
                        D.(props{i}).values = data{ind,3};
                        D.(props{i}).N = 1;
                        D.(props{i}).type = 'string';
                        
                    case 'File'
                        % THIS IS NOT RIGHT
                        f = cellfun(@(a) a(find(a==filesep,1,'last')+1:find(a=='.',1,'last')-1),P.Value,'uni',0);
                        D.(props{i}).values = f;
                        D.(props{i}).N = numel(P.Value);
                        D.(props{i}).filenames = P.Value;
                        D.(props{i}).type = 'files';
                        
                    case 'Numeric'
                        Selected = data{ind,3};
                        if Selected(1) ~= '[', Selected = ['[' Selected ']']; end %#ok<AGROW>
                        
                        if data{ind,2}
                            D.(props{i}).values = Selected;
                            D.(props{i}).N = 1;
                            D.(props{i}).type = 'Numeric';
                            D.(props{i}).Alternate = 1;
                        else
                            D.(props{i}).values = eval(Selected);
                            D.(props{i}).N = numel(D.(props{i}).values);
                            D.(props{i}).type = 'Numeric';
                            D.(props{i}).Alternate = 0;
                        end
                end
            end
            
            
            app.data = D;
        end
        
        function compile(app)
            D  = app.data;
            Ps = app.props;
            D = orderfields(D,Ps);
            
            C = {};
            
            N = structfun(@(a) a.N,D);
            
            k = 1;
            
            for i = 1:length(Ps)
                
                vj = D.(Ps{i}).values;
                
                if D.(Ps{i}).Alternate
                    if ~iscell(vj), vj = {vj}; end
                else
                    if ischar(vj)
                        vj = {vj};
                    else
                        if ~iscell(vj), vj = num2cell(vj); end
                    end
                end
                
                if isempty(C)
                    C(:,k) = vj(:);
                else
                    if N(i) > 1
                        C = [C; repmat(C,N(i)-1,1)];
                        vje = repmat(vj,size(C,1)/N(i),1);
                    else
                        vje = repmat(vj,size(C,1),1);
                    end
                    if isempty(vje)
                        C(:,k) = {'~'};
                    else
                        C(:,k) = vje(:);
                    end
                end
                k = k + 1;
            end
            
            % sort columns of C by number of unique values in descending order
            [~,i] = sort(N,'descend');
            app.compiled = C(:,i);
            app.props    = Ps(i);
            app.data     = orderfields(D,i); % fields may have been rearranged
        end
        
        function update(app)
            
            t = table;
            P = app.props;
            
            n = length(P);
            t.Selected = true(size(app.compiled,1),1);
            alias = cell(1,n);
            for i = 1:n
                if isnumeric(app.compiled{1,i}) || islogical(app.compiled{1,i})
                    t.(P{i}) = [app.compiled{:,i}]';
                else
                    t.(P{i}) = app.compiled(:,i);
                end
                alias{i} = app.SIG.(P{i}).AliasWithUnit;
                if isempty(alias{i}), alias{i} = P{i}; end
            end
            t.Properties.VariableDescriptions = [{'Selected'} alias];
            
            
            app.ScheduleTable.ColumnName     = t.Properties.VariableDescriptions;
            app.ScheduleTable.ColumnWidth    = [{20} repmat({'auto'},1,n)];
            app.ScheduleTable.ColumnEditable = [true, false(1,n)];
            app.ScheduleTable.RowStriping    = 'on';
            app.ScheduleTable.Data = t;
            
            app.ScheduleTable.UserData.Table = t;
            app.ScheduleTable.UserData.Obj = app;
            
            
            [pn,fn,~] = fileparts(app.filename);
            if isempty(pn)
                app.ScheduleFigure.Name = 'Schedule: *NEW SCHEDULE*';
                app.update_save_state('on');
            else
                app.ScheduleFigure.Name = sprintf('Schedule: %s [%s]',fn,pn);
                app.update_save_state('off');
            end
            
            figure(app.ScheduleFigure);
        end
        
        function update_highlight(app,row,highlightColor)
            if nargin < 2, row = []; end
            if nargin < 3 || isempty(highlightColor), highlightColor = [0.2 0.6 1]; end
            n = size(app.ScheduleTable.Data,1);
            c = repmat([1 1 1; 0.9 0.9 0.9],ceil(n/2),1);
            c(n+1:end,:) = [];
            if ~isempty(row)
                c(row,:) = highlightColor;
            end
            app.ScheduleTable.BackgroundColor = c;
        end
        
        function load_schedule(app,ffn)
            if nargin == 2 && ~isempty(ffn) && ischar(ffn)
                assert(exist(ffn,'file') == 2,'File does not exist! "%s"',ffn)
            else
                dfltpth = getpref('Schedule','path',cd);
                
                [fn,pn] = uigetfile({'*.sch','Schedule (*.sch)'},'Load a file',dfltpth);
                
                if isequal(fn,0), return; end
                
                ffn = fullfile(pn,fn);
                
                setpref('Schedule','path',pn);
            end
            
            vprintf(1,'Loading schedule "%s" ...',ffn)
            
            D = load(ffn,'-mat','compiled','data','SIG','tblData');
            
            if ~all(isfield(D,{'compiled','data','SIG','tblData'}))
                errordlg(sprintf('Essential component(s) missing from schedule file!\n\n%s',ffn),'Schedule','modal');
                return
            end
            
            
            app.SIG      = D.SIG;
            app.compiled = D.compiled;
            app.data     = D.data;
            
            app.filename = ffn;
            
            app.update;
            app.ScheduleTable.Data = D.tblData;
            
            
            app.update_save_state('off');
            
                        
        end
    end
    
    methods (Access = private)
        function selection_processor(app,event)
            
            hObj = event.Source;
            
            [M,N] = size(app.ScheduleTable.Data);
            
            if M == 0, return; end % no data yet
            
            switch hObj.Text
                case {'Deselect All','Deselect All Rows'}
                    app.ScheduleTable.Data(:,1) = num2cell(false(M,1));
                    app.DeselectAllButton.Text = 'Select All';
                    app.DeselectAllRowsMenu.Text = 'Select All Rows';
                    
                case {'Select All','Select All Rows'}
                    app.ScheduleTable.Data(:,1) = num2cell(true(M,1));
                    app.DeselectAllButton.Text = 'Deselect All';
                    app.DeselectAllRowsMenu.Text = 'Deselect All Rows';
                    
                case {'Every Other','Select Every Other Row'}
                    Selected = [true(1,M); false(1,M)];
                    app.ScheduleTable.Data(:,1) = num2cell(Selected(1:M))';
                    
                case {'Custom','Custom Selection'}
                    dflt = getpref('Schedule','SelectCustom','1:2:end');
                    
                    opts.Resize='on';
                    opts.WindowStyle='modal';
                    opts.Interpreter='tex';
                    opts.InputFontSize = 14;
                    
                    r = inputdlg('\fontsize{14} Enter expression. M = length of schedule.', ...
                        'Select',1,{dflt},opts);
                    
                    if isempty(r), return; end
                    
                    D = app.ScheduleTable.Data;
                    
                    t = false(M,1);
                    try
                        eval(sprintf('t(%s) = true;',char(r)));
                        app.ScheduleTable.Data(:,1) = num2cell(t);
                        setpref('Schedule','SelectCustom',char(r));
                    catch me
                        errordlg(sprintf('Invalid expression: %s.\n\n%s\n%s', ...
                            char(r),me.identifier,me.message),'Select');
                    end
                    
                case {'Toggle','Toggle Current Selection'}
                    app.ScheduleTable.Data(:,1) = num2cell(~[app.ScheduleTable.Data{:,1}]')';
                    
                case {'Sort on Column','Sort by Selected Column'}
                    col = app.ScheduleTable.UserData.ColumnSelected;
                    if isempty(col), return; end
                    
                    tbl = app.ScheduleTable.UserData.Table;
                    p = tbl.Properties.VariableNames;
                    sortDir = repmat({'ascend'},1,length(col));
                    for i = 1:length(col)
                        if iscellstr(tbl.(p{col(i)})) %#ok<ISCLSTR>
                            if issorted(string(tbl.(p{col(i)})),sortDir{i}), sortDir{i} = 'descend'; end
                        else
                            if issortedrows(tbl,p(col(i)),sortDir{i}), sortDir{i} = 'descend'; end
                        end
                    end
                    tbl = sortrows(tbl,p(col),sortDir);
                    app.ScheduleTable.UserData.Table = tbl;
                    app.ScheduleTable.Data = tbl;
                    
                    
                case 'Remove Row(s)'
                    selection = uiconfirm(app.ScheduleFigure, ...
                        'What would you like to remove?','Schedule', ...
                        'Options',{'Selected Rows','Unselected Rows','Nevermind'}, ...
                        'DefaultOption',2,'CancelOption',3,...
                        'Icon','question');
                    
                    if isequal(selection,'Nevermind'), return; end
                    
                    ind = app.ScheduleTable.Data.Selected;
                    if isequal(selection,'Unselected Rows'), ind = ~ind; end
                    if ~any(ind)
                        uialert(app.ScheduleFigure,'Nothing to remove.', ...
                            'Schedule','Icon','info');
                        return
                    end
                    
                    app.ScheduleTable.Data(ind,:) = [];
                    
                case {'Reset','Reset Schedule'}
                    app.ScheduleTable.UserData.Obj.update;
            end
            
            if any(app.ScheduleTable.Data.Selected) % table format
                app.update_save_state('on');
            else
                app.update_save_state('off');
            end
            
        end
        
        function save_schedule(app)
            dfltpth = getpref('Schedule','path',cd);
            
            [fn,pn] = uiputfile({'*.sch','Schedule (*.sch)'},'Save schedule',dfltpth);
            
            figure(app.ScheduleFigure); % not sure why, but GUI disappears
            
            if isequal(fn,0), return; end
            
            tblData  = app.ScheduleTable.Data;
            data     = app.data;
            compiled = app.compiled;
            SIG      = app.SIG;
            
            save(fullfile(pn,fn),'-mat','compiled','data','SIG','tblData');
            
            fprintf('Schedule saved as ... %s\n',fullfile(pn,fn))
            
            app.filename = fullfile(pn,fn);
            [~,fn,~] = fileparts(app.filename);
            app.ScheduleFigure.Name = sprintf('Schedule: %s (%s)',fn,pn);
            
            setpref('Scehdule','path',pn);
            
            app.update_save_state('off');
            
        end
        
        function update_save_state(app,s)
            
            app.SaveButton.Enable = s;
            app.SaveScheduleMenu.Enable = s;
            
            if isequal(s,'on')
                app.SaveButton.Tooltip = 'Schedule has been altered';
                app.SaveScheduleMenu.Tooltip = 'Schedule has been altered';
            else
                app.SaveButton.Tooltip = 'Schedule has been saved';
                app.SaveScheduleMenu.Tooltip = 'Schedule has been saved';
                
            end
            
        end
    end
    

    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app, filename)
            app.ScheduleTable.RowName = 'numbered';
            
            if nargin == 2 && ~isempty(filename) && ischar(filename)
                app.filename = filename;
                app.load_schedule(filename);
            end
        end

        % Cell selection callback: ScheduleTable
        function ScheduleTableCellSelection(app, event)
            hObj = event.Source;
            if isempty(event.Indices)
                hObj.UserData.ColumnSelected = [];
                hObj.UserData.RowSelected = [];
                return
            end
            row = event.Indices(:,1);
            col = event.Indices(:,2);
            hObj.UserData.ColumnSelected = col;
            hObj.UserData.RowSelected = row;
        end

        % Cell edit callback: ScheduleTable
        function ScheduleTableCellEdit(app, event)
            if any(app.ScheduleTable.Data.Selected)
                app.update_save_state('on');
            else
                app.update_save_state('off');
            end
        end

        % Callback function: LoadButton, LoadScheduleMenu
        function LoadButtonPushed(app, event)
            app.load_schedule;
        end

        % Callback function: SaveButton, SaveScheduleMenu
        function SaveButtonPushed(app, event)
            app.save_schedule;
        end

        % Button pushed function: LaunchSchDesGUIButton
        function LaunchSchDesGUIButtonPushed(app, event)
            abr.ScheduleDesign;
        end

        % Callback function: SortbySelectedColumnMenu, 
        % SortonColumnButton
        function SortonColumnButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end

        % Callback function: DeselectAllButton, DeselectAllRowsMenu
        function DeselectAllButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end

        % Callback function: EveryOtherButton, SelectEveryOtherRowMenu
        function EveryOtherButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end

        % Callback function: CustomButton, CustomSelectionMenu
        function CustomButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end

        % Callback function: ToggleButton, ToggleCurrentSelectionMenu
        function ToggleButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end

        % Callback function: ResetButton, ResetScheduleMenu
        function ResetButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end

        % Close request function: ScheduleFigure
        function ScheduleFigureCloseRequest(app, event)
            if app.DO_NOT_DELETE
                uialert(app.ScheduleFigure, ...
                    sprintf('I''m sorry Dave, I''m afraid I can''t do that.\n\nYou must first set the Control Panel to "Idle".'), ...
                    'Sorry Dave','Icon','warning','Modal',true);
                return
            end
            
            if isequal(app.SaveButton.Enable,'on')
                r = uiconfirm(app.ScheduleFigure, ...
                    'Would you like to save changes to the current Schedule before exiting?', ...
                    'Schedule','Options',{'Save','Don''t Save','Cancel'}, ...
                    'DefaultOption',1, ...
                    'CancelOption',3);
                switch r
                    case 'Save'
                        app.save_schedule;
                    case 'Cancel'
                        return;
                end
            end
            
            setpref('abr_Schedule','figpos',app.ScheduleFigure.Position);
            
            delete(app)
            
        end

        % Button pushed function: ScheduleInfoButton
        function ScheduleInfoButtonPushed(app, event)
             abr.Universal.docbox('schedule');
        end

        % Callback function: RemoveRowsButton, RemoveRowsMenu
        function RemoveRowsButtonPushed(app, event)
            % AppDesigner f's up custom function name when selecting as callback for multiple objects
            app.selection_processor(event);
        end
    end

    % App initialization and construction
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)
            pos = getpref('abr_Schedule','figpos',[400 150 1000 800]);
            
            % Create ScheduleFigure
            app.ScheduleFigure = uifigure;
            app.ScheduleFigure.Position = pos;
            app.ScheduleFigure.Name = 'Schedule';
            app.ScheduleFigure.Tag  = 'MABR_FIG';
            app.ScheduleFigure.CloseRequestFcn = createCallbackFcn(app, @ScheduleFigureCloseRequest, true);

            % Create FileMenu
            app.FileMenu = uimenu(app.ScheduleFigure);
            app.FileMenu.Text = 'File';

            % Create LoadScheduleMenu
            app.LoadScheduleMenu = uimenu(app.FileMenu);
            app.LoadScheduleMenu.MenuSelectedFcn = createCallbackFcn(app, @LoadButtonPushed, true);
            app.LoadScheduleMenu.Accelerator = 'L';
            app.LoadScheduleMenu.Text = 'Load Schedule';

            % Create SaveScheduleMenu
            app.SaveScheduleMenu = uimenu(app.FileMenu);
            app.SaveScheduleMenu.MenuSelectedFcn = createCallbackFcn(app, @SaveButtonPushed, true);
            app.SaveScheduleMenu.Accelerator = 'S';
            app.SaveScheduleMenu.Text = 'Save Schedule';

            % Create ScheduleMenu
            app.ScheduleMenu = uimenu(app.ScheduleFigure);
            app.ScheduleMenu.Text = 'Schedule';

            % Create SortbySelectedColumnMenu
            app.SortbySelectedColumnMenu = uimenu(app.ScheduleMenu);
            app.SortbySelectedColumnMenu.MenuSelectedFcn = createCallbackFcn(app, @SortonColumnButtonPushed, true);
            app.SortbySelectedColumnMenu.Accelerator = 'C';
            app.SortbySelectedColumnMenu.Text = 'Sort by Selected Column';

            % Create RemoveRowsMenu
            app.RemoveRowsMenu = uimenu(app.ScheduleMenu);
            app.RemoveRowsMenu.MenuSelectedFcn = createCallbackFcn(app, @RemoveRowsButtonPushed, true);
            app.RemoveRowsMenu.Separator = 'on';
            app.RemoveRowsMenu.Accelerator = 'K';
            app.RemoveRowsMenu.Text = 'Remove Row(s)';

            % Create ResetScheduleMenu
            app.ResetScheduleMenu = uimenu(app.ScheduleMenu);
            app.ResetScheduleMenu.MenuSelectedFcn = createCallbackFcn(app, @ResetButtonPushed, true);
            app.ResetScheduleMenu.Accelerator = 'R';
            app.ResetScheduleMenu.Text = 'Reset Schedule';

            % Create DeselectAllRowsMenu
            app.DeselectAllRowsMenu = uimenu(app.ScheduleMenu);
            app.DeselectAllRowsMenu.MenuSelectedFcn = createCallbackFcn(app, @DeselectAllButtonPushed, true);
            app.DeselectAllRowsMenu.Separator = 'on';
            app.DeselectAllRowsMenu.Accelerator = 'D';
            app.DeselectAllRowsMenu.Text = 'Deselect All Rows';

            % Create SelectEveryOtherRowMenu
            app.SelectEveryOtherRowMenu = uimenu(app.ScheduleMenu);
            app.SelectEveryOtherRowMenu.MenuSelectedFcn = createCallbackFcn(app, @EveryOtherButtonPushed, true);
            app.SelectEveryOtherRowMenu.Accelerator = 'O';
            app.SelectEveryOtherRowMenu.Text = 'Select Every Other Row';

            % Create CustomSelectionMenu
            app.CustomSelectionMenu = uimenu(app.ScheduleMenu);
            app.CustomSelectionMenu.MenuSelectedFcn = createCallbackFcn(app, @CustomButtonPushed, true);
            app.CustomSelectionMenu.Accelerator = 'M';
            app.CustomSelectionMenu.Text = 'Custom Selection';

            % Create ToggleCurrentSelectionMenu
            app.ToggleCurrentSelectionMenu = uimenu(app.ScheduleMenu);
            app.ToggleCurrentSelectionMenu.MenuSelectedFcn = createCallbackFcn(app, @ToggleButtonPushed, true);
            app.ToggleCurrentSelectionMenu.Accelerator = 'T';
            app.ToggleCurrentSelectionMenu.Text = 'Toggle Current Selection';

            % Create ScheduleTable
            app.ScheduleTable = uitable(app.ScheduleFigure);
            app.ScheduleTable.ColumnName = {''};
            app.ScheduleTable.RowName = {};
            app.ScheduleTable.ColumnEditable = false;
            app.ScheduleTable.CellEditCallback = createCallbackFcn(app, @ScheduleTableCellEdit, true);
            app.ScheduleTable.CellSelectionCallback = createCallbackFcn(app, @ScheduleTableCellSelection, true);
            app.ScheduleTable.Position = [1 1 pos(3) pos(4)-30];

            % Create ButtonPanel
            app.ButtonPanel = uipanel(app.ScheduleFigure);
            app.ButtonPanel.BorderType = 'none';
            app.ButtonPanel.Position = [1 pos(4)-30 pos(3) 30];

            % Create SortonColumnButton
            app.SortonColumnButton = uibutton(app.ButtonPanel, 'push');
            app.SortonColumnButton.ButtonPushedFcn = createCallbackFcn(app, @SortonColumnButtonPushed, true);
            app.SortonColumnButton.Position = [299 5 100 22];
            app.SortonColumnButton.Text = 'Sort on Column';

            % Create ResetButton
            app.ResetButton = uibutton(app.ButtonPanel, 'push');
            app.ResetButton.ButtonPushedFcn = createCallbackFcn(app, @ResetButtonPushed, true);
            app.ResetButton.Position = [511 5 54 22];
            app.ResetButton.Text = 'Reset';

            % Create DeselectAllButton
            app.DeselectAllButton = uibutton(app.ButtonPanel, 'push');
            app.DeselectAllButton.ButtonPushedFcn = createCallbackFcn(app, @DeselectAllButtonPushed, true);
            app.DeselectAllButton.Position = [630 5 73 22];
            app.DeselectAllButton.Text = 'Deselect All';

            % Create EveryOtherButton
            app.EveryOtherButton = uibutton(app.ButtonPanel, 'push');
            app.EveryOtherButton.ButtonPushedFcn = createCallbackFcn(app, @EveryOtherButtonPushed, true);
            app.EveryOtherButton.Position = [708 5 72 22];
            app.EveryOtherButton.Text = 'Every Other';

            % Create CustomButton
            app.CustomButton = uibutton(app.ButtonPanel, 'push');
            app.CustomButton.ButtonPushedFcn = createCallbackFcn(app, @CustomButtonPushed, true);
            app.CustomButton.Position = [785 5 58 22];
            app.CustomButton.Text = 'Custom';

            % Create ToggleButton
            app.ToggleButton = uibutton(app.ButtonPanel, 'push');
            app.ToggleButton.ButtonPushedFcn = createCallbackFcn(app, @ToggleButtonPushed, true);
            app.ToggleButton.Position = [848 5 51 22];
            app.ToggleButton.Text = 'Toggle';

            % Create LoadButton
            app.LoadButton = uibutton(app.ButtonPanel, 'push');
            app.LoadButton.ButtonPushedFcn = createCallbackFcn(app, @LoadButtonPushed, true);
            app.LoadButton.Icon = 'file_open.png';
            app.LoadButton.Position = [6 5 62 22];
            app.LoadButton.Text = 'Load';

            % Create SaveButton
            app.SaveButton = uibutton(app.ButtonPanel, 'push');
            app.SaveButton.ButtonPushedFcn = createCallbackFcn(app, @SaveButtonPushed, true);
            app.SaveButton.Icon = 'file_save.png';
            app.SaveButton.Enable = 'off';
            app.SaveButton.Position = [73 5 63 22];
            app.SaveButton.Text = 'Save';

            % Create LaunchSchDesGUIButton
            app.LaunchSchDesGUIButton = uibutton(app.ButtonPanel, 'push');
            app.LaunchSchDesGUIButton.ButtonPushedFcn = createCallbackFcn(app, @LaunchSchDesGUIButtonPushed, true);
            app.LaunchSchDesGUIButton.Icon = 'guideicon.gif';
            app.LaunchSchDesGUIButton.Position = [185 5 68 22];
            app.LaunchSchDesGUIButton.Text = 'Design';

            % Create ScheduleInfoButton
            app.ScheduleInfoButton = uibutton(app.ButtonPanel, 'push');
            app.ScheduleInfoButton.ButtonPushedFcn = createCallbackFcn(app, @sch_docbox, true);
            app.ScheduleInfoButton.Icon = 'helpicon.gif';
            app.ScheduleInfoButton.IconAlignment = 'center';
            app.ScheduleInfoButton.Position = [150 5 20 23];
            app.ScheduleInfoButton.Text = '';

            % Create RemoveRowsButton
            app.RemoveRowsButton = uibutton(app.ButtonPanel, 'push');
            app.RemoveRowsButton.ButtonPushedFcn = createCallbackFcn(app, @RemoveRowsButtonPushed, true);
            app.RemoveRowsButton.Position = [404 5 102 22];
            app.RemoveRowsButton.Text = 'Remove Row(s)';
        end
        
        
        function sch_docbox(app,event)
            abr.Universal.docbox('schedule');
        end
    end

    methods (Access = public)

        % Constructor
        function app = Schedule(varargin)

            % Create and configure components
            createComponents(app)

%             % Register the app with App Designer
%             registerApp(app, app.ScheduleFigure)

            % Execute the startup function
            runStartupFcn(app, @(app)startupFcn(app, varargin{:}))

            if nargout == 0
                clear app
            end
        end

        % Destructor
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.ScheduleFigure)
        end
    end
end