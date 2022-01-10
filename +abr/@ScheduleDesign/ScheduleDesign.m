classdef ScheduleDesign < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        ScheduleDesignFigure      matlab.ui.Figure
        FileMenu                  matlab.ui.container.Menu
        SaveScheduleDesignMenu    matlab.ui.container.Menu
        LoadScheduleDesignMenu    matlab.ui.container.Menu
        OptionsMenu               matlab.ui.container.Menu
        AudioSamplingRateMenu     matlab.ui.container.Menu
        SigDefTable               matlab.ui.control.Table
        SignalTypeDropDownLabel   matlab.ui.control.Label
        SignalTypeDropDown        matlab.ui.control.DropDown
        CompileButton             matlab.ui.control.Button
        PlotButton                matlab.ui.control.Button
        ScheduleDesignInfoButton  matlab.ui.control.Button
    end

    
    properties (Access = private)
        axSigPlot
        ScheduleDesignFigureSigPlot
        MODE = 0; % 0 = normal; 1 = calibration mode
    end
    
    properties (SetAccess = private, GetAccess = public)
        SCH % abr.sigdef.Schedule
        SIG % abr.sigdef.sigs....
        SigFiles
    end
    
    methods (Access = public)
        
        function updateSIG(app)
            
            props = app.SigDefTable.UserData;
            data  = app.SigDefTable.Data;
            
            for i = 1:length(props)
                ind = ismember(data(:,1),app.SIG.(props{i}).DescriptionWithUnit);
                if ~any(ind), continue; end
                app.SIG.(props{i}).Alternate = data{ind,2};
                app.SIG.(props{i}).Value     = data{ind,3};
            end
        end
        
        function loadSIG(app)
            props = properties(app.SIG);
            
            ind = cellfun(@(a) isa(app.SIG.(a),'abr.sigdef.sigProp'),props);
            props(~ind) = [];
            
            ind = cellfun(@(a) app.SIG.(a).Active,props);
            props(~ind) = [];
            
            app.SigFiles = [];
            app.SigDefTable.Data = {[]};
            for i = 1:length(props)
                
                if ~isa(app.SIG.(props{i}),'abr.sigdef.sigProp') || ~app.SIG.(props{i}).Active, continue; end
                
                descr = app.SIG.(props{i}).DescriptionWithUnit;
                if isempty(descr), continue; end % only include properties with descriptions
                
                app.SigDefTable.Data{end+1,1} = descr;
                v = app.SIG.(props{i}).Value;
                
                if isnumeric(v), v = mat2str(v); end
                
                app.SigDefTable.Data{end,3} = v;
                
                % Alternating parameter?
                app.SigDefTable.Data{end,2} = app.SIG.(props{i}).Alternate;
            end
            app.SigDefTable.Data(1,:) = [];
            
            app.SigDefTable.UserData = props;
        end
    end
    
    methods (Access = private)
        
        function load_sig_file(app,ffn)
            if nargin < 2 || isempty(ffn)
                dfltpn = getpref('ScheduleDesign','dfltpn',cd);
                [fn,pn] = uigetfile({'*.schd','Schedule Design File (*.schd)'},'Save Schedule Design File',dfltpn);
                
                figure(app.ScheduleDesignFigure);
                
                if isequal(fn,0), return; end
                
                ffn = fullfile(pn,fn);
            end
            
            load(ffn,'-mat','SIG');
            
            app.SignalTypeDropDown.Value = SIG.Type;
            app.SIG = SIG;
            
            app.loadSIG;
            
            setpref('ScheduleDesign','dfltpn',pn);            
        end
        
        function update_sampling_rate(app,Fs)
            AllFs = [44100,48000,64000,88200,96000,128000,176400,192000];
            Fs = getpref('ScheduleDesign','Fs',44100);
            if nargin == 2 && ~isempty(AllFs)
                mustBeMember(Fs,AllFs);
                app.SIG.Fs = Fs;
            else
                SRs = cellfun(@(a) sprintf('%d Hz',a),num2cell(AllFs),'uni',0);
                i = find(AllFs == Fs,1);
                if isempty(i), i = length(AllFs); end
                [sel,ok] = listdlg('ListString',SRs,'InitialValue',i, ...
                    'Name','Sampling Rate','PromptString','Select Stimulus Sampling Rate:', ...
                    'SelectionMode','single');
                figure(app.ScheduleDesignFigure); % figure disappears for some reason
                if ~ok, return; end
                app.SIG.Fs = AllFs(sel);
            end
            app.AudioSamplingRateMenu.Text = sprintf('Stimulus Sampling Rate = %d Hz',app.SIG.Fs);
            setpref('ScheduleDesign','Fs',app.SIG.Fs);
        end
        
        % Code that executes after component creation
        function startupFcn(app, SIG_IN, MODE)
            app.ScheduleDesignFigure.Tag = 'ScheduleDesignGUI';
            if nargin >= 2 && ~isempty(SIG_IN) && startsWith(class(SIG_IN),'abr.sigdef.')
                if ischar(SIG_IN) % filename
                    app.load_sig_file(SIG_IN);
                else
                    app.SignalTypeDropDown.Value = SIG_IN.Type;
                    app.SIG = SIG_IN;
                    app.loadSIG;
                end
            else
                app.signal_type_changed;
            end
            
            if nargin == 3 && ~isempty(MODE)
                app.MODE = MODE;
            end
            
        end

        % Value changed function: SignalTypeDropDown
        function signal_type_changed(app, event)
            sigType = app.SignalTypeDropDown.Value;
            app.SIG = abr.sigdef.sigs.(sigType);
            app.loadSIG;
        end

        % Cell selection callback: SigDefTable
        function SigDefTableCellSelection(app, event)
            if isempty(event.Indices), return; end
            
            row = event.Indices(1);
            col = event.Indices(2);
            
            prop = app.SigDefTable.UserData{row};
            
            switch col
                case 1 % NAME
                case 2 % ALTERNATE
                case 3 % VALUE
                    
                    if ~isempty(app.SIG.(prop).Function)
                        % call a function
                        result = feval(app.SIG.(prop).Function,app.SIG);
                        
                        figure(app.ScheduleDesignFigure); % otherwise the gui will hide after closing dialog box
                        
                        if isequal(result,'NOVALUE'), return; end
                        
                        app.SIG.(prop).Value = result;
                        
                        switch app.SIG.(prop).Type
                            case 'File'
                                f = cellfun(@(a) a(find(a==filesep,1,'last')+1:find(a=='.',1,'last')-1),result,'uni',0);
                                app.SigDefTable.Data{row,col} = sprintf('"%s" ',f{:});
                                
                            case 'String'
                                app.SigDefTable.Data{row,col} = result;
                        end
                    end
            end
        end

        % Cell edit callback: SigDefTable
        function SigDefTableCellEdit(app, event)
            
            if isempty(event.Indices), return; end
            
            row = event.Indices(1);
            col = event.Indices(2);
            
            v = app.SigDefTable.Data{row,3};
            
            if v(1) ~= '[', v = ['[' v ']']; end
            
            try
                nd = eval(v);
                
            catch me
                app.SigDefTable.Data{row,col} = event.PreviousData;
                uiconfirm(app.ScheduleDesignFigure, ...
                    sprintf('Unable to evaluate: "%s"\n\nIdentifier: %s\n\n%s', ...
                    event.NewData,me.identifier,me.message), ...
                    'Schedule Design','Options',{'OK'},'Icon','error');
                return
                
            end
            
            switch col
                case 1 % NAME
                case 2 % ALTERNATE
                    
                    if ~contains(app.SigDefTable.Data{row,1},'Polarity')
                        uialert(app.ScheduleDesignFigure,'Alternating parameters is currently only supported for the "Polarity" parameter.','Alternate', ...
                            'Icon','warning','Modal',true);
                        app.SigDefTable.Data{row,col} = false;
                        return
                    end
                    
                    if app.SigDefTable.Data{row,col} == true && numel(nd) ~= 2
                        uialert(app.ScheduleDesignFigure,'Must have two values to use Alternate option.','Alternate', ...
                            'Icon','warning','Modal',true);
                        app.SigDefTable.Data{row,col} = false;
                    end
                    
                case 3 % VALUE
                    if numel(nd) ~= 2
                        app.SigDefTable.Data{row,2} = false;
                    end
                    
                    try
                        app.updateSIG;
                        app.SIG = app.SIG.update;
                        
                    catch me
                        uialert(app.ScheduleDesignFigure,sprintf('Invalid expression:\n\n%s\n\n%s', ...
                            me.identifier,me.message),'Schedule Design','modal',true,'Icon','error');
                        app.SigDefTable.Data{row,3} = event.PreviousData;
                    end
                    
            end
            
            app.updateSIG;
            app.SIG = app.SIG.update;
            
        end

        % Button pushed function: PlotButton
        function PlotButtonPushed(app, event)
            if isempty(app.ScheduleDesignFigureSigPlot) || ~isvalid(app.ScheduleDesignFigureSigPlot)
                app.ScheduleDesignFigureSigPlot = figure('name','SigPlot','color','w');
                app.axSigPlot  = axes(app.ScheduleDesignFigureSigPlot,'Tag','SigPlot');
            end
            
            app.SIG = app.SIG.update;
            
            figure(app.ScheduleDesignFigureSigPlot);
            
            %         btnSigSched_Callback([],[],true);
            cla(app.axSigPlot);
            grid(app.axSigPlot,'on');
            
            app.axSigPlot.XAxis.Label.String = 'time (ms)';
            app.axSigPlot.YAxis.Label.String = 'amplitude';
            for k = 1:numel(app.SIG.data)
                if length(app.SIG.timeVector) == 1
                    t = app.SIG.timeVector{1};
                else
                    t = app.SIG.timeVector{k};
                end
                hl(k) = line(app.axSigPlot,t*1000,app.SIG.data{k},'linestyle','-', ...
                    'marker','o','markersize',4,'linewidth',2);
                if numel(hl) > 1
                    set(hl(1:end-1),'marker','none','color',[0.8 0.8 0.8],'linewidth',1);
                end
                
                %             y = max(abs(app.SIG.data{k}(:))) * 1.1;
                %             app.axSigPlot.YAxis.Limits = [-y y];
                app.axSigPlot.YAxis.Limits = [-1.1 1.1];
                
                if isa(app.SIG,'abr.sigdef.sigs.File')
                    fn = app.SIG.fullFilename.Value{k};
                    fn = fn(find(fn==filesep,1,'last')+1:find(fn=='.',1,'last')-1);
                    pstr = sprintf('Filename: "%s"',fn);
                else
                    x = app.SIG.dataParams;
                    N = structfun(@(a) numel(unique(a)),x);
                    p = fieldnames(x);
                    if ~all(N==1)
                        x = rmfield(x,p(N==1));
                    end
                    
                    pstr = '';
                    for i = fieldnames(x)'
                        v = x.(char(i));
                        pstr = sprintf('%s| %s: %.2f ',pstr,app.SIG.(char(i)).Alias,v(k));
                    end
                    pstr([1:2 end]) = [];
                end
                app.axSigPlot.Title.String = pstr;
                
                pause(0.2)
            end
            
            
        end

        % Button pushed function: CompileButton
        function compile_parameters(app, event)
            
            props = app.SigDefTable.UserData;
            data  = app.SigDefTable.Data;
            
            if ~isprop(app,'SCH') || ~isa(app.SCH,'Schedule') || ~isvalid(app.SCH)
                app.SCH = abr.Schedule;
            end
            
            app.SCH.preprocess(app.SIG,props,data);
            app.SCH.compile;
            
            if app.MODE == 0
                app.SCH.update;
            else
                close(app.SCH.ScheduleFigure);
            end
            
            % Update serves as trigger for uiwait functions elsewhere
            app.CompileButton.UserData = rand(1);
            
        end

        % Menu selected function: SaveScheduleDesignMenu
        function SaveScheduleDesignMenuSelected(app, event)
            dfltpn = getpref('ScheduleDesign','dfltpn',cd);
            
            [fn,pn] = uiputfile({'*.schd','Schedule Design File (*.schd)'},'Save Schedule Design File',dfltpn);
            
            figure(app.ScheduleDesignFigure);
            
            if isequal(fn,0), return; end
            
            ffn = fullfile(pn,fn);
            
            SIG = app.SIG;
            save(ffn,'SIG','-mat');
            
            fprintf('Schedule Design File Saved: %s\n',ffn)
            
            setpref('ScheduleDesign','dfltpn',pn);
            
            
        end

        % Menu selected function: LoadScheduleDesignMenu
        function LoadScheduleDesignMenuSelected(app, event)
            app.load_sig_file;
        end

        function sd_docbox(app)
            abr.Universal.docbox('schedule_design');
        end

        % Create UIFigure and components
        function createComponents(app)

            % Create ScheduleDesignFigure
            app.ScheduleDesignFigure = uifigure;
            app.ScheduleDesignFigure.Position = [100 100 608 435];
            app.ScheduleDesignFigure.Tag  = 'MABR_FIG';
            app.ScheduleDesignFigure.Name = 'Schedule Design';

            % Create FileMenu
            app.FileMenu = uimenu(app.ScheduleDesignFigure);
            app.FileMenu.Text = 'File';

            % Create SaveScheduleDesignMenu
            app.SaveScheduleDesignMenu = uimenu(app.FileMenu);
            app.SaveScheduleDesignMenu.MenuSelectedFcn = createCallbackFcn(app, @SaveScheduleDesignMenuSelected, true);
            app.SaveScheduleDesignMenu.Accelerator = 'S';
            app.SaveScheduleDesignMenu.Text = 'Save Schedule Design';

            % Create LoadScheduleDesignMenu
            app.LoadScheduleDesignMenu = uimenu(app.FileMenu);
            app.LoadScheduleDesignMenu.MenuSelectedFcn = createCallbackFcn(app, @LoadScheduleDesignMenuSelected, true);
            app.LoadScheduleDesignMenu.Accelerator = 'L';
            app.LoadScheduleDesignMenu.Text = 'Load Schedule Design';

            % Create OptionsMenu
            app.OptionsMenu = uimenu(app.ScheduleDesignFigure);
            app.OptionsMenu.Text = 'Options';
            
            % Create AudioSamplingRateMenu
            Fs = getpref('ScheduleDesign','Fs',44100);
            app.AudioSamplingRateMenu = uimenu(app.OptionsMenu);
            app.AudioSamplingRateMenu.Text = sprintf('Stimulus Sampling Rate = %d Hz',Fs);
            app.AudioSamplingRateMenu.Tooltip = 'Set the DAC sampling rate';
            app.AudioSamplingRateMenu.MenuSelectedFcn = createCallbackFcn(app, @update_sampling_rate, false);

            % Create SigDefTable
            app.SigDefTable = uitable(app.ScheduleDesignFigure);
            app.SigDefTable.ColumnName = {'Parameter'; 'Alternate'; 'Value/Expression'};
            app.SigDefTable.ColumnWidth = {200, 50, 320};
            app.SigDefTable.RowName = {};
            app.SigDefTable.ColumnEditable = [false true true];
            app.SigDefTable.CellEditCallback = createCallbackFcn(app, @SigDefTableCellEdit, true);
            app.SigDefTable.CellSelectionCallback = createCallbackFcn(app, @SigDefTableCellSelection, true);
            app.SigDefTable.FontSize = 14;
            app.SigDefTable.Position = [17 20 578 368];

            % Create SignalTypeDropDownLabel
            app.SignalTypeDropDownLabel = uilabel(app.ScheduleDesignFigure);
            app.SignalTypeDropDownLabel.HorizontalAlignment = 'right';
            app.SignalTypeDropDownLabel.FontSize = 18;
            app.SignalTypeDropDownLabel.Position = [40 401 105 22];
            app.SignalTypeDropDownLabel.Text = 'Signal Type:';

            % Create SignalTypeDropDown
            app.SignalTypeDropDown = uidropdown(app.ScheduleDesignFigure);
            app.SignalTypeDropDown.Items = {'Tone', 'Noise', 'Click', 'File'};
            app.SignalTypeDropDown.ValueChangedFcn = createCallbackFcn(app, @signal_type_changed, true);
            app.SignalTypeDropDown.FontSize = 18;
            app.SignalTypeDropDown.Position = [152 396 100 32];
            app.SignalTypeDropDown.Value = 'Tone';

            % Create CompileButton
            app.CompileButton = uibutton(app.ScheduleDesignFigure, 'push');
            app.CompileButton.ButtonPushedFcn = createCallbackFcn(app, @compile_parameters, true);
            app.CompileButton.FontSize = 16;
            app.CompileButton.FontWeight = 'bold';
            app.CompileButton.Position = [353 397 100 30];
            app.CompileButton.Text = 'Compile';

            % Create PlotButton
            app.PlotButton = uibutton(app.ScheduleDesignFigure, 'push');
            app.PlotButton.ButtonPushedFcn = createCallbackFcn(app, @PlotButtonPushed, true);
            app.PlotButton.FontSize = 16;
            app.PlotButton.FontWeight = 'bold';
            app.PlotButton.Position = [470 397 100 30];
            app.PlotButton.Text = 'Plot';

            % Create ScheduleDesignInfoButton
            app.ScheduleDesignInfoButton = uibutton(app.ScheduleDesignFigure, 'push');
            app.ScheduleDesignInfoButton.Icon = 'helpicon.gif';
            app.ScheduleDesignInfoButton.IconAlignment = 'center';
            app.ScheduleDesignInfoButton.Position = [10 405 20 23];
            app.ScheduleDesignInfoButton.Text = '';
            app.ScheduleDesignInfoButton.ButtonPushedFcn = createCallbackFcn(app, @sd_docbox, false);
        end
    end

    methods (Access = public)

        % Construct app
        function app = ScheduleDesign(varargin)

            % Create and configure components
            createComponents(app)

%             % Register the app with App Designer
%             registerApp(app, app.ScheduleDesignFigure)

            % Execute the startup function
            runStartupFcn(app, @(app)startupFcn(app, varargin{:}))

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.ScheduleDesignFigure)
        end
    end
end