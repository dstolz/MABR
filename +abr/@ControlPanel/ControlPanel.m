classdef ControlPanel < matlab.apps.AppBase & abr.Universal & handle
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        ABR                 (1,1) abr.ABR
        
        TrcOrg              (1,1) abr.traces.Organizer
        
        Config              (1,1) struct

%         Subject             (1,1) abr.Subject
        Schedule            (1,1) %abr.Schedule
        Calibration         (1,1) abr.SoundCalibration
        
        configFile          (1,:) char
        scheduleFile        (1,:) char
        calibrationFile     (1,:) char
        outputFile          (1,:) char
        
    end
    
    properties (SetAccess = private)
        stateProgram     (1,1) abr.stateProgram = abr.stateProgram.STARTUP;
        
        SIG              (1,1)
        
        scheduleRunCount (:,1)
        scheduleIdx      (1,1) = 1;
        
        DATA             (:,1) abr.ABR
    end

    properties (Access = private)
        Runtime     %abr.Runtime
        
        timer_StartFcn   = @abr.ControlPanel.timer_Start;
        timer_RuntimeFcn = @abr.ControlPanel.timer_Runtime;
        timer_StopFcn    = @abr.ControlPanel.timer_Stop;
        timer_ErrorFcn   = @abr.ControlPanel.timer_Error;
    end
    
    % Properties that correspond to app components
    properties % (Access = private)
        ControlPanelUIFigure           matlab.ui.Figure
        FileMenu                       matlab.ui.container.Menu
        LoadConfigurationMenu          matlab.ui.container.Menu
        SaveConfigurationMenu          matlab.ui.container.Menu
        OptionsMenu                    matlab.ui.container.Menu
        OptionShowTimingStats          matlab.ui.container.Menu
        StayonTopMenu                  matlab.ui.container.Menu
        ASIOSettingsMenu               matlab.ui.container.Menu
        SelectAudioDeviceMenu          matlab.ui.container.Menu
        SetupAudioChannelsMenu         matlab.ui.container.Menu
        VerbosityMenu                  matlab.ui.container.Menu
        ResetBackgroundProcessMenu     matlab.ui.container.Menu
        ParametersMenu                 matlab.ui.container.Menu
        UpdateInputGainMenu            matlab.ui.container.Menu
        TabGroup                       matlab.ui.container.TabGroup
        ConfigTab                      matlab.ui.container.Tab
        AcqFilterTab                   matlab.ui.container.Tab
        ConfigFileSave                 matlab.ui.control.Button
        ConfigFileLoad                 matlab.ui.control.Button
        ConfigFileLabel                matlab.ui.control.Label
        ConfigFileDD                   matlab.ui.control.DropDown
        CalibrationNew                 matlab.ui.control.Button
        CalibrationLoad                matlab.ui.control.Button
        CalibrationDDLabel             matlab.ui.control.Label
        CalibrationDD                  matlab.ui.control.DropDown
        ScheduleDDLabel                matlab.ui.control.Label
        ConfigScheduleDD               matlab.ui.control.DropDown
        ConfigNewSchedButton           matlab.ui.control.Button
        ConfigLoadSchedButton          matlab.ui.control.Button
        OutputPanel                    matlab.ui.container.Panel
        OutputPathLabel                matlab.ui.control.Label
        OutputFileLabel                matlab.ui.control.Label
        OutputPathDD                   matlab.ui.control.DropDown
        OutputFileDD                   matlab.ui.control.DropDown
        OutputPathSelectButton         matlab.ui.control.Button
        ConfigOutputDD                 matlab.ui.control.DropDown
        SubjectInfoTab                 matlab.ui.container.Tab
        DOBDatePickerLabel             matlab.ui.control.Label
        SubjectDOBDatePicker           matlab.ui.control.DatePicker
        SubjectTree                    matlab.ui.container.Tree
        NotesTextAreaLabel             matlab.ui.control.Label
        SubjectNotesTextArea           matlab.ui.control.TextArea
        AliasEditFieldLabel            matlab.ui.control.Label
        AliasEditField                 matlab.ui.control.EditField
        IDEditFieldLabel               matlab.ui.control.Label
        SubjectIDEditField             matlab.ui.control.EditField
        SubjectSexSwitch               matlab.ui.control.Switch
        UserDDLabel                    matlab.ui.control.Label
        SubjectUserDD                  matlab.ui.control.DropDown
        SubjectAddaSubjectButton       matlab.ui.control.Button
        ControlTab                     matlab.ui.container.Tab
        ControlStimInfoLabel           matlab.ui.control.Label
        NumRepetitionsLabel            matlab.ui.control.Label
        NumRepetitionsSpinner          matlab.ui.control.Spinner
        ControlAdvCriteriaDDLabel      matlab.ui.control.Label
        ControlAdvCriteriaDD           matlab.ui.control.DropDown
        SweepsSpinnerLabel             matlab.ui.control.Label
        SweepCountDD                   matlab.ui.control.DropDown
        SweepRateHzSpinnerLabel        matlab.ui.control.Label
        SweepRateHzSpinner             matlab.ui.control.Spinner
        SweepDurationSpinner           matlab.ui.control.Spinner
        SweepDurationLabel             matlab.ui.control.Label
        Panel_2                        matlab.ui.container.Panel
        ControlAdvanceButton           matlab.ui.control.Button
        ControlRepeatButton            matlab.ui.control.StateButton
        ControlPauseButton             matlab.ui.control.StateButton
        ControlAcquisitionSwitch       matlab.ui.control.ToggleSwitch
        AcquisitionStateLabel          matlab.ui.control.Label
        Panel_3                        matlab.ui.container.Panel
        FilterHPFcEditFieldLabel       matlab.ui.control.Label
        FilterHPFcEditField            matlab.ui.control.NumericEditField
        FilterLPFcEditFieldLabel       matlab.ui.control.Label
        FilterLPFcEditField            matlab.ui.control.NumericEditField
        FilterEnableSwitch             matlab.ui.control.RockerSwitch
        FilterEnabledLamp              matlab.ui.control.Lamp
        FilterNotchFilterKnob          matlab.ui.control.DiscreteKnob
        FilterBandpassFilterLabel      matlab.ui.control.Label
        FilterNotchFilterLabel         matlab.ui.control.Label
        FilterNotchEnabledLamp         matlab.ui.control.Lamp
        UtilitiesTab                   matlab.ui.container.Tab
        UtilityScheduleDesignButton    matlab.ui.control.Button
        UtilitySoundCalibrationButton  matlab.ui.control.Button
        UtilityABRDataViewerButton     matlab.ui.control.Button
        UtilityScheduleButton    matlab.ui.control.Button
        HelpButton                     matlab.ui.control.Button
        LocateFiguresButton            matlab.ui.control.Button
        
        SubjectNode     matlab.ui.container.TreeNode
        
        Timer (1,1) timer
    end
    
    properties (Access=private)
        selectedTab
    end
    
    properties
        ControlSweepCountGauge         matlab.ui.control.LinearGauge
        AcquisitionStateLamp           matlab.ui.control.Lamp
    end
    
    
    % Set/Get Properties
    methods
        createComponents(app);
        R = live_analysis(app,preSweep,postSweep);
        abr_live_plot(app,sweeps,tvec,R);
        
        function ffn = get.outputFile(app)
            fn = app.OutputFileDD.Value;
            pn = app.OutputPathDD.Value;
            
            ffn = fullfile(pn,fn);
            
            if isequal(ffn,app.outputFile), return; end % no change

            if exist(ffn,'file') == 2
                fprintf('Appending to output file: %s (%s)\n',fn,pn)
                load(ffn,'-mat','meta');
                % should probably be ||
                if exist('meta','var') && ~isequal(meta.DataVersion,app.DataVersion)
                    warndlg(sprintf([ ...
                        'Data file: %s\n\n', ...
                        'Existing datafile version, %s, ', ...
                        'does not match the current program data version, %s.'], ...
                        ffn,meta.DataVersion,app.DataVersion), ...
                        'Append existing file','modal');
                end
                
            else
                fprintf('Creating new output file: %s (%s)\n',fn,pn)
                meta = app.meta;
                ABR_Data = abr.ABR; % init
                TraceOrganizer = abr.traces.Organizer; % init
                
                save(ffn,'meta','ABR_Data','TraceOrganizer','-mat','-v7.3');
            end
        end
       
        function t = get.selectedTab(app)
            if isempty(app.selectedTab)
                app.selectedTab = app.ConfigTab;
            end
            t = app.selectedTab;
        end 
    end
    
    
    
    
    
    
    
    methods (Access = private)
        abrAcquireBatch(app,ax,varargin);
        
        % Selection change function: TabGroup
        function TabGroup_selection_changed(app, event)
            app.selectedTab = app.TabGroup.SelectedTab;
        end
        
        
        
        
        function populate_gui(app)
            % Config file
            if isempty(app.configFile)
                app.ConfigFileDD.Items     = {'Load a configuration file -->'};
                app.ConfigFileDD.ItemsData = {'NO CONFIG'};
                app.ConfigFileDD.Value     = 'NO CONFIG';
                app.ConfigFileDD.Tooltip   = 'No Configuration File Selected';
                app.ConfigFileDD.FontColor = [1 0 0];
                app.ConfigFileLabel.Tooltip      = '';
                app.configFile = '';
            else
                ffn = app.configFile;
                c = getpref('ABRControlPanel','recentConfigs',[]);
                if ~isempty(c)
                    ind = ismember(c,ffn) | cellfun(@(a) not(eq(exist(a,'file'),2)),c);
                    c(ind) = [];
                end
                c = [{ffn}; c];
                vind = cellfun(@(a) exist(a,'file')==0,c);
                c(vind) = [];
                if isempty(c)
                    app.ConfigFileDD.Items     = {'< NO CONFIG FILES >'};
                    app.ConfigFileDD.ItemsData = {'< NO CONFIG FILES >'};
                    app.ConfigFileDD.Value     = '< NO CONFIG FILES >';
                    app.ConfigFileDD.Tooltip   = '< NO CONFIG FILES >';
                    app.ConfigFileDD.FontColor = [1 0 0];
                    app.ConfigFileLabel.Tooltip = '< NO CONFIG FILES >';
                else
                    d = cellfun(@dir,c);
                    app.ConfigFileDD.Items     = {d.name};
                    app.ConfigFileDD.ItemsData = c;
                    if ismember(app.configFile,c)
                        app.ConfigFileDD.Value = app.configFile;
                    else
                        app.ConfigFileDD.Value = c{1};
                    end
                    app.ConfigFileDD.Tooltip   = abr.Tools.last_modified_str(app.configFile);
                    app.ConfigFileDD.FontColor = [0 0 0];
                    app.ConfigFileLabel.Tooltip = fileparts(app.configFile);
                    setpref('ABRControlPanel','recentConfigs',c);
                end
            end
            
            
            % Schedule File
            if isempty(app.scheduleFile) || exist(app.scheduleFile,'file') ~= 2
                app.ConfigScheduleDD.Items     = {'Load a schedule file -->'};
                app.ConfigScheduleDD.ItemsData = {'NO SCHED FILES'};
                app.ConfigScheduleDD.Value     = 'NO SCHED FILES';
                app.ConfigScheduleDD.Tooltip   = 'Must load a schedule file.';
                app.ConfigScheduleDD.FontColor = [1 0 0];
                app.ScheduleDDLabel.Tooltip    = '';
                app.scheduleFile = '';
            else
                d = dir(fullfile(fileparts(app.scheduleFile),'*.sch'));
                ffns = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
                app.ConfigScheduleDD.Items     = {d.name};
                app.ConfigScheduleDD.ItemsData = ffns;
                if ismember(app.scheduleFile,ffns)
                    app.ConfigScheduleDD.Value = app.scheduleFile;
                else
                    app.ConfigScheduleDD.Value = ffns{1};
                end
                app.ConfigScheduleDD.Tooltip   = abr.Tools.last_modified_str(app.scheduleFile);
                app.ConfigScheduleDD.FontColor = [0 0 0];
                app.ScheduleDDLabel.Tooltip    = fileparts(app.scheduleFile);
            end
            
            
            % Calibration Files
            if isempty(app.calibrationFile)
                    app.CalibrationDD.Items     = {'< NO CALIBRATION FILES! >'};
                    app.CalibrationDD.ItemsData = {'< NO CALIBRATION FILES! >'};
                    app.CalibrationDD.Value     = '< NO CALIBRATION FILES! >';
                    app.CalibrationDD.Tooltip   = 'No Calibration File!';
                    app.CalibrationDD.FontColor = [1 0 0];
                    app.CalibrationDDLabel.Tooltip = '';
                    app.calibrationFile = [];
            else
                    d = dir(fullfile(fileparts(app.calibrationFile),'*.cal'));
                    fns = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
                    app.CalibrationDD.Items     = {d.name};
                    app.CalibrationDD.ItemsData = fns;
                    if ismember(app.calibrationFile,fns)
                        app.CalibrationDD.Value = app.calibrationFile;
                    else
                        app.CalibrationDD.Value = fns{1};
                    end
                    app.CalibrationDD.Tooltip   = abr.Tools.last_modified_str(app.calibrationFile);
                    app.CalibrationDD.FontColor = [0 0 0];
                    app.CalibrationDDLabel.Tooltip = fileparts(app.calibrationFile);
                    setpref('ABRControlPanel','calpth',fileparts(app.calibrationFile));
            end
            
            
            
            
            % other
            app.SelectAudioDeviceMenu.Text = sprintf('Audio Device: "%s"',app.ABR.audioDevice);
        end
        
        
        
        
        function auto_save_abr_data(app)
            app.DATA(end+1) = app.ABR;
            ABR_Data        = app.DATA;
            save(app.outputFile,'ABR_Data','-mat','-v7.3');
            % TraceOrganizer  = app.TrcOrg;
            % save(app.outputFile,'ABR_Data','TraceOrganizer','-mat','-v7.3');
        end
        
        
        %% MENU -----------------------------------------------------------
        
        function launch_asiosettings(app)
            % launches external ASIO settings gui
            asiosettings;
        end
        
        function menu_option_processor(~,event)
            hObj = event.Source;
            if isequal(hObj.Checked,'on')
                hObj.Checked = 'off';
            else
                hObj.Checked = 'on';
            end
        end
        
        function always_on_top(app)
            % solution????
            drawnow expose
            
            jFrame = getjframe(app.ControlPanelUIFigure);
%             warnStruct=warning('off','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
%             jFrame = get(handle(app.ControlPanelUIFigure),'JavaFrame');
%             warning(warnStruct.state,'MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
            jFrame_fHGxClient = jFrame.fHG2Client;
            wasOnTop = jFrame_fHGxClient.getWindow.isAlwaysOnTop;
            jFrame_fHGxClient.getWindow.setAlwaysOnTop(isOnTop);

        end
        
        
        
        
        
        
        
        
        
        %% CONFIG ---------------------------------------------------------
        function gather_config_parameters(app)
            vprintf(3,'Gathering configuration parameters')
            
            app.Config.scheduleFile    = app.scheduleFile;
            app.Config.configFile      = app.configFile;
            app.Config.calibrationFile = app.calibrationFile;
            app.Config.outputFile      = app.outputFile;
            
            app.Config.Control.advCriteria = app.ControlAdvCriteriaDD.Value;
            n = app.SweepCountDD.Value;
            if ischar(n)
                app.Config.Control.numSweeps = str2double(n);
            else
                app.Config.Control.numSweeps = n;
            end
            app.Config.Control.sweepRate   = app.SweepRateHzSpinner.Value;
            app.Config.Control.numReps     = app.NumRepetitionsSpinner.Value;
            app.Config.Control.sweepDuration = app.SweepDurationSpinner.Value;
            
            app.Config.Control.frameLength = abr.Universal.frameLength;
            
            app.Config.Filter.Enable       = app.FilterEnableSwitch.Value;
            app.Config.Filter.adcFilterHP  = app.FilterHPFcEditField.Value;
            app.Config.Filter.adcFilterLP  = app.FilterLPFcEditField.Value;
            app.Config.Filter.Notch.Freq   = app.FilterNotchFilterKnob.Value;
            
            app.Config.Parameters = app.Runtime.infoData;
        end
        
        function apply_config_parameters(app)
            
            app.ControlAdvCriteriaDD.Value = app.Config.Control.advCriteria;
            app.SweepCountDD.Value               = num2str(app.Config.Control.numSweeps,'%d');
            app.SweepRateHzSpinner.Value         = app.Config.Control.sweepRate;
            app.NumRepetitionsSpinner.Value      = app.Config.Control.numReps;
            app.SweepDurationSpinner.Value       = app.Config.Control.sweepDuration;
            
            app.FilterEnableSwitch.Value         = app.Config.Filter.Enable;
            app.FilterHPFcEditField.Value        = app.Config.Filter.adcFilterHP;
            app.FilterLPFcEditField.Value        = app.Config.Filter.adcFilterLP;
            app.FilterNotchFilterKnob.Value      = app.Config.Filter.Notch.Freq;
            
            P = app.Config.Parameters;
            app.UpdateInputGainMenu.Text = sprintf('Amplifier Gain = %gx',P.InputAmpGain);
            fn = fieldnames(P);
            for i = 1:length(fn)
                app.Runtime.update_infoData(fn{i},P.(fn{i}));
            end
            
            if isequal(app.FilterEnableSwitch.Value,'Enabled')
                app.FilterEnabledLamp.Color = [0 1 0];
            else
                app.FilterEnabledLamp.Color = [0.6 0.6 0.6];
            end
            
            if app.FilterNotchFilterKnob.Value == 0
                app.FilterNotchEnabledLamp.Color = [0.6 0.6 0.6];
            else
                app.FilterNotchEnabledLamp.Color = [0 1 0];
            end
            
            while isempty(app.ABR.audioDevice)
                h = msgbox('Select Audio Device','ABR','help','modal');
                uiwait(h);
                app.select_audiodevice;
            end
            
        end
        
        function locate_schedule_file(app)
            dfltPth = getpref('ABRControlPanel','schedulePath',cd);
            
            [fn,pn] = uigetfile({'*.sch','Stimulus Schedule File (*.sch)'}, ...
                'Load Stimulus Schedule File',dfltPth);
            
            if isequal(fn,0), return; end
            
            app.scheduleFile = fullfile(pn,fn);
            
            if isempty(app.scheduleFile), return; end
                        
            setpref('ABRControlPanel','schedulePath',pn);
            
            app.populate_gui;
            
            app.load_schedule_file;
            
            figure(app.ControlPanelUIFigure);
        end
        
        function locate_calibration_file(app)
            dfltPth = getpref('ABRControlPanel','calibrationPath',cd);
            
            [fn,pn] = uigetfile({'*.cal','Acoustic Calibration File (*.cal)'}, ...
                'Load Acoustic Calibration File',dfltPth);
            
            if isequal(fn,0), return; end
            
            app.calibrationFile = fullfile(pn,fn);
            
            if isempty(app.calibrationFile), return; end
                        
            setpref('ABRControlPanel','calibrationPath',pn);
            
            app.populate_gui;
            
            app.load_calibration_file;
            
            figure(app.ControlPanelUIFigure);
        end
        
        function load_config_file(app,ffn)
            if nargin < 2 || isempty(ffn)
                dfltPth = getpref('ABRControlPanel','configPath',cd);
                
                [fn,pn] = uigetfile({'*.cfg','ABR Config File (*.cfg)'}, ...
                    'Load ABR Configuration File',dfltPth);
                
                if isequal(fn,0), return; end
                
                app.configFile = fullfile(pn,fn);
                
                if isempty(app.configFile), return; end
            else
                app.configFile = ffn;
            end
            
            % Load configuration file
            try
                load(app.configFile,'abrConfig','-mat');
            catch me
                errordlg(sprintf('Error loading configuration file: %s\n\n%s\n\n%s', ...
                    ffn,me.identifier,me.message),'ABR Configuration','modal');
                return
            end
            
            app.Config = abrConfig.Config;
            app.ABR    = abrConfig.ABR;
            
            app.scheduleFile    = app.Config.scheduleFile;
            app.calibrationFile = app.Config.calibrationFile;
            
            setpref('ABRControlPanel','configPath',fileparts(app.configFile));
            setpref('ABRControlPanel','configFile',app.configFile);
            
            app.populate_gui;
            
            app.apply_config_parameters;
            
            app.load_schedule_file;
            app.load_calibration_file;
            
            figure(app.ControlPanelUIFigure);
        end
        
        function save_config_file(app,ffn)
            % Save configuration file
            
            if nargin < 2 || isempty(ffn)
                dfltPth = getpref('ABRControlPanel','configPath',cd);
                
                [fn,pn] = uiputfile({'*.cfg', 'ABR Configuration (*.cfg)'}, ...
                    'Save ABR Configuration File',dfltPth);
                
                figure(app.ControlPanelUIFigure);
                
                if isequal(fn,0), return; end
                
                ffn = fullfile(pn,fn);
            else
                [pn,fn] = fileparts(ffn);
            end
            
            app.gather_config_parameters;

            abrConfig.Config            = app.Config;
            abrConfig.scheduleFile      = app.scheduleFile;
            abrConfig.calibratonFile    = app.calibrationFile;
            abrConfig.configFile        = ffn;
            abrConfig.ABR               = app.ABR;
            abrConfig.meta              = app.meta;
            
            save(ffn,'abrConfig','-mat','-v7.3');
            
            fprintf('ABR Configuration file saved: %s\n',fn)
            
            setpref('ABRControlPanel','configPath',pn);
            
            app.configFile = ffn;

            app.populate_gui;
        end
        
        function output_select_directory(app)
            recentPaths = getpref('ABRControlPanel','outputFolder',{app.root}); % set with recent directories

            pn = uigetdir(recentPaths{1},'Pick a Directory');
            figure(app.ControlPanelUIFigure); % because it hides for some reason
            
            
            ind = ismember(recentPaths,pn);
            recentPaths(ind) = [];
            
            ind = isfolder(recentPaths);
            recentPaths(~ind) = [];

            recentPaths = [pn; recentPaths];
            
            app.OutputPathDD.Items = recentPaths;
            app.OutputPathDD.ItemsData = recentPaths;
            app.OutputPathDD.Value = pn;
            
            setpref('ABRControlPanel','outputFolder',recentPaths(1:min([10 length(recentPaths)])));
        end
        
        function output_path_changed(app,event)
            recentPaths = getpref('ABRControlPanel','outputFolder',{app.root}); % set with recent directories
            
            pn = event.Value;
            h  = event.Source;
            
            
            h.ItemsData = recentPaths;
            h.Items     = abr.Tools.truncate_str(recentPaths,30);
            h.Value     = pn;
            h.Tooltip   = pn;
            
            setpref('ABRControlPanel','outputFolder',recentPaths(1:min([10 length(recentPaths)])));

            % update output file dropdown items
            fn = app.OutputFileDD.Value;
            if isempty(fn), fn = 'abr_data_file.abr'; end
            d  = dir(fullfile(pn,'*.abr'));
            fns = {d.name};
            if ~ismember(fn,fns), fns = [{fn} fns]; end
            app.OutputFileDD.Items     = fns;
            app.OutputFileDD.ItemsData = fns;
            app.OutputFileDD.Value     = fn;
            
            e.Value = app.OutputFileDD.Value;
            e.Source = app.OutputFileDD;
            app.output_file_changed(e);
        end
        
        function output_file_changed(app,event)
            
            pn = app.OutputPathDD.Value;
            
            nfn = event.Value;
            if ~endsWith(nfn,'.abr'), nfn = [nfn,'.abr']; end
            nffn = fullfile(pn,nfn);
            if ~abr.Tools.validate_filename(nffn)
                uialert(app.ControlPanelUIFigure, ...
                    sprintf('Invalid Filename: %s',nffn), ...
                    'Invalid Filename','Icon','error','Modal',true);
                app.OutputFileDD.FontColor = [1 0 0];
                % * TO DO: DISABLE RUNNING EXPERIMENT WITH INVALID FILENAME
                return
            end
            
            fns = app.OutputFileDD.Items;            
            
            if ~ismember(nfn,fns), fns = [{nfn} fns]; end
            
            app.outputFile = fullfile(pn,nfn);
            
            if exist(app.outputFile,'file') == 0
                % initialize output file
                discard = [];
                save(app.outputFile,'discard','-mat');
            end
            
            app.OutputFileDD.Items     = fns;
            app.OutputFileDD.ItemsData = fns; %cellfun(@(a) fullfile(pn,a),fns,'uni',0);
            app.OutputFileDD.Value     = nfn;
            app.OutputFileDD.FontColor = [0 0 0];
        end
        
        function load_schedule_file(app,event)
            if isempty(app.scheduleFile), return; end
            if nargin == 2
                app.scheduleFile = event.Value;
            end
            

            if isequal(app.Schedule,0)
                if exist(app.scheduleFile,'file') == 2
                    app.Schedule = abr.Schedule(app.scheduleFile);
                else
                    return % ????
                end
            elseif isvalid(app.Schedule)
                app.Schedule.load_schedule(app.scheduleFile);
            else
                h = findobj('type','figure','-and','name','CONTROL_PANEL_SCHEDULE');
                delete(h);
                app.Schedule = abr.Schedule(app.scheduleFile);
            end
            
            app.ConfigScheduleDD.Tooltip = abr.Tools.last_modified_str(app.scheduleFile);
            app.ScheduleDDLabel.Tooltip    = fileparts(app.scheduleFile);
            app.Schedule.ScheduleFigure.Tag = 'CONTROL_PANEL_SCHEDULE';
            
            app.SIG = app.Schedule.SIG;
        end
        
        function load_calibration_file(app,event)
            if isempty(app.calibrationFile), return; end
            if nargin == 2
                app.calibrationFile = event.Value;
            end
            
            if exist(app.calibrationFile,'file') == 2
                vprintf(2,'Loading Calibration file: %s',app.calibrationFile)
                load(app.calibrationFile,'Calibration','-mat');
                if ~exist('Calibration','var')
                    msg = sprintf('Invalid calibration file: %s',app.calibrationFile);
                    errordlg(msg,'Calibration File','modal');
                    vprintf(0,1,msg);
                    return
                end
                app.Calibration = Calibration; %#ok<ADPROPLC>
                app.CalibrationDDLabel.Tooltip    = fileparts(app.calibrationFile);
                app.CalibrationDD.Tooltip = abr.Tools.last_modified_str(app.calibrationFile);
            else
                app.Calibration = abr.SoundCalibration; % blank calibration
                app.CalibrationDDLabel.Tooltip    = 'No Calibration File Loaded';
                app.CalibrationDD.Tooltip = 'No Calibration File Loaded';
            end
            
        end
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        %% CONTROL --------------------------------------------------------
        function StateMachine(app)
            global stateAcq
            
            persistent activeState
            
            if activeState == app.stateProgram, return; end
            
            activeState = app.stateProgram;
            
            vprintf(2,'StateMachine: activeState = %s',activeState)
            
            try
                switch activeState
                    case abr.stateProgram.STARTUP
                        drawnow
                        
                    case abr.stateProgram.PREP_BLOCK
                        
                        app.gather_config_parameters;
                        
                        % reset pause button state
                        app.pause_button;

                        app.update_lamp('Prep');
                        
                        
                        app.ControlSweepCountGauge.Value = 0;
                        app.ControlPauseButton.Value = 0;
                        
                        vprintf(3,'Reloading schedule file')
                        app.load_schedule_file;
                        
                        % launch trace organizer
                        app.TrcOrg.figure;
                        
                        app.Schedule.DO_NOT_DELETE = true;
                        app.scheduleIdx  = find(app.Schedule.selectedData,1,'first');
                        app.scheduleRunCount = zeros(size(app.Schedule.selectedData));
                        
                        drawnow
                        

                        % setup as foreground process and launch background process
                        if isempty(app.Runtime) || isstruct(app.Runtime) || ~isvalid(app.Runtime) || ~app.Runtime.FgIsRunning
                            app.Runtime = abr.Runtime;
                        end
                        
                        % idle background process
                        app.Runtime.CommandToBg = abr.Cmd.Idle;
                        
                        if ~app.Runtime.BgIsRunning
                            D = uiprogressdlg(app.ControlPanelUIFigure, ...
                                'Title','Starting Background Process',...
                                'Indeterminate','on','icon','info',...
                                'Message','Please wait ...');
                            abr.Runtime.launch_bg_process;
                        end
                        
                        
                        % wait for the background process to load
                        while ~app.Runtime.BgIsRunning, pause(0.01); end
                        if exist('D','var'), close(D); end
                        
                        
                        % TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!
                        app.Runtime.CommandToBg = abr.Cmd.Test;
                        % TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!
                        
                        
                        app.stateProgram = abr.stateProgram.ADVANCE_BLOCK; % to first trial
                        
                        app.StateMachine;
                        
                        
                    case abr.stateProgram.ADVANCE_BLOCK
                        if stateAcq==abr.stateAcq.CANCELLED, return; end
                        
                        app.gather_config_parameters; % in case user updates guis
                        
                        if app.ControlRepeatButton.Value % 1 == depressed 
                            nReps = inf; 

                            % update gui info
                            app.update_ControlStimInfoLabel(nReps);
                        else
                            % find next trial
                            switch app.ControlAdvCriteriaDD.Value
                                case '# Sweeps'
                                    nReps = app.NumRepetitionsSpinner.Value;
                                    
                                    if app.scheduleRunCount(app.scheduleIdx) >= nReps
                                        ind = app.scheduleRunCount(app.scheduleIdx+1:end) < nReps ...
                                            & app.Schedule.selectedData(app.scheduleIdx+1:end);
                                        if any(ind)
                                            app.scheduleIdx = app.scheduleIdx + find(ind,1,'first');
                                        else
                                            % reached end of schedule
                                            app.stateProgram = abr.stateProgram.SCHED_COMPLETE;
                                            app.StateMachine;
                                            return
                                        end
                                    end
                                    
                                    % update gui info
                                    app.update_ControlStimInfoLabel(nReps);
                                case '< Define >'
                                    % TO DO: ADD CUSTOM FUNCTION SUPPORT
                                otherwise
                                    app.scheduleIdx = feval(app.ControlAdvCriteriaDD.ItemsData,app);
                            end
                        end
                        
                        % make sure the sweep gauge reflects current value
                        app.ControlSweepCountGauge.Limits = [0 app.Config.Control.numSweeps];
                        
                        
                        % update status
                        if app.scheduleIdx == 1
                            app.update_lamp('starting');
                        else
                            app.update_lamp('advancing');
                        end
                        
                        
                        
                        % update Schedule table selection                        
                        app.Schedule.update_highlight(app.scheduleIdx,[.6 1 .2]);
                        
                        % convert to signal
                        app.ABR.DAC.SampleRate = app.SIG.Fs;
                        app.ABR.DAC.FrameSize  = abr.Universal.frameLength;
                        
                        % reset the ADC buffer
                        app.ABR.ADC = abr.Buffer;
                        
                        app.ABR.ADC.FrameSize       = abr.Universal.frameLength;
                        app.ABR.ADC.SampleRate      = abr.Universal.ADCSampleRate;
                        app.ABR.adcDecimationFactor = round(max([1 floor(app.SIG.Fs ./ app.ABR.ADC.SampleRate)]));
                        app.ABR.ADC.SampleRate      = app.ABR.DAC.SampleRate ./ app.ABR.adcDecimationFactor;

                        
                        % generate signal based on its parameters
                        app.SIG = app.Schedule.sigArray(app.scheduleIdx);
                        
                        % calibrate stimulus data
                        if app.Calibration.calibration_is_valid
                            app.SIG.Calibration = app.Calibration;
                        else
                            r = questdlg('Invalid Calibration!','ABR','Continue','Cancel','Cancel');
                            if isequal(r,'Cancel')
                                app.stateProgram = abr.stateProgram.USER_IDLE;
                                stateAcq = abr.stateAcq.CANCELLED;
                                return
                            end
                            vprintf(0,1,'Continuing with invalid calibration!')
                        end
                        
                        % compute signal
                        app.SIG = app.SIG.update;
                        
                        % copy unmodified stimulus signal
                        app.ABR.SIG = app.SIG;
                        
                        % copy stimulus to DAC buffer.
                        app.ABR.DAC.PadToFrameSize = 'off';
                        app.ABR.DAC.Data = app.SIG.data{1};
                        
                        % sweep duration
                        app.ABR.adcWindow = [0 app.Config.Control.sweepDuration]/1000; % ms -> s
                        
                        % alternate polarity flag
                        app.ABR.altPolarity = app.SIG.polarity.Alternate;
                        
                        % update ABR info after setting buffer
                        app.ABR.numSweeps = app.Config.Control.numSweeps;
                        app.ABR.sweepRate = app.Config.Control.sweepRate;
                        
                        % setup optional digital filters
                        app.ABR.adcFilterLP = app.Config.Filter.adcFilterLP;
                        app.ABR.adcFilterHP = app.Config.Filter.adcFilterHP;
                        app.ABR.adcUseBPFilter = isequal(app.FilterEnableSwitch.Value,'Enabled');
                        
                        app.ABR.adcUseNotchFilter = app.FilterNotchFilterKnob.Value ~= 0;
                        fv = app.FilterNotchFilterKnob.Value;
                        if fv > 0
                            app.ABR.adcNotchFilterFreq = fv;
                        end
                        
                        app.ABR.createADCfilt;
                                                
                        % update status
                        app.update_lamp('acquiring');
                        
                        
                        % update infoData with channel ids
                        app.Runtime.update_infoData('DACsignalCh',app.ABR.DACsignalCh);
                        app.Runtime.update_infoData('DACtimingCh',app.ABR.DACtimingCh);
                        app.Runtime.update_infoData('ADCsignalCh',app.ABR.ADCsignalCh);
                        app.Runtime.update_infoData('ADCtimingCh',app.ABR.ADCtimingCh);
                        
                        % write audio file to .runtime
                        app.Runtime.prepare_block_fg(app.ABR.DAC.Data, ...
                            app.ABR.DAC.SampleRate,app.ABR.numSweeps, ...
                            app.ABR.sweepRate,app.ABR.altPolarity);
                        

                        
                        % tell background process to prep for acquisition
                        app.Runtime.CommandToBg = abr.Cmd.Prep;
                        
                        % wait for state of background process to update
                        while app.Runtime.BackgroundState ~= abr.stateAcq.READY
                            pause(0.01);
                            if app.Runtime.BackgroundState == abr.stateAcq.ERROR
                                app.stateProgram = abr.stateProgram.ERROR;
                                app.StateMachine;
                                return
                            end
                        end
                        
                        
                        stateAcq = abr.stateAcq.READY;

                        app.stateProgram = abr.stateProgram.ACQUIRE;
                        
                        app.StateMachine;
                        
                        
                        
                    case abr.stateProgram.ACQUIRE
                                                
                        % send command to background process to acquire block
                        app.Runtime.CommandToBg = abr.Cmd.Run;
                        
                        stateAcq = abr.stateAcq.ACQUIRE;
                        
                        app.update_lamp('Acquiring');
                        
                        % start monitoring timer
                        app.run_acq_timer;
                        
                            
                        
                    case abr.stateProgram.BLOCK_COMPLETE
                        app.scheduleRunCount(app.scheduleIdx) = app.scheduleRunCount(app.scheduleIdx) + 1;
                        
                        % extract sweep-based data and plot one last time
                        [preSweep,postSweep] = app.Runtime.extract_sweeps(app.ABR.adcWindowTVec,true);
                        
                        if ~isnan(postSweep(1))
                                                        
                            % update signal amplitude by InputAmpGain
                            A = app.Config.Parameters.InputAmpGain;
                            preSweep  = preSweep ./ A;
                            postSweep = postSweep ./ A;

                            R = app.partition_corr(preSweep,postSweep);
                            app.abr_live_plot(postSweep,app.ABR.adcWindowTVec,R);
                            
                            % Add buffer to traces.Organizer
                            app.TrcOrg.add_trace( ...
                                mean(postSweep), ...
                                app.SIG, ...
                                app.ABR.adcWindow(1), ...
                                app.ABR.ADC.SampleRate);
                        end
                        %%%% TESTING
%                         R = app.ABR.analysis('peaks');
                        
                        % SAVE ABR DATA
                        app.update_lamp('saving');

                        % store continue data buffer for offline analysis
                        bufferHead = app.Runtime.mapCom.Data.BufferIndex(2);
                        app.ABR.ADC.Data = app.Runtime.mapSignalBuffer.Data(1:bufferHead);
                        app.ABR.ADC.SweepOnsets = app.Runtime.find_timing_onsets;
                        
                        app.auto_save_abr_data;
                        drawnow

                        app.stateProgram = abr.stateProgram.ADVANCE_BLOCK;
                        app.StateMachine;
                        
                    case abr.stateProgram.SCHED_COMPLETE
                        app.Schedule.update_highlight([]);
                        app.Schedule.DO_NOT_DELETE = false;
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.ControlStimInfoLabel.Text = 'Completed';
                        app.update_lamp('Finished');
                        
                        
                    case abr.stateProgram.USER_IDLE
                        app.Schedule.DO_NOT_DELETE = false;
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.update_lamp('Ready');
                        stateAcq = abr.stateAcq.CANCELLED;
                        
                        [preSweep,postSweep] = app.Runtime.extract_sweeps(app.ABR.adcWindowTVec,true);
                        if ~isnan(postSweep(1))
                            % update signal amplitude by InputAmpGain
                            A = app.Config.Parameters.InputAmpGain;
                            preSweep  = preSweep ./ A;
                            postSweep = postSweep ./ A;

                            R = app.partition_corr(preSweep,postSweep);
                            app.abr_live_plot(postSweep,app.ABR.adcWindowTVec,R)
                            

                            % Add buffer to traces.Organizer
                            app.TrcOrg.add_trace( ...
                                mean(postSweep), ...
                                app.SIG, ...
                                app.ABR.adcWindow(1), ...
                                app.ABR.ADC.SampleRate);
                        end
                    
                        
                        
                        
                    case abr.stateProgram.ACQ_ERROR
                        app.Schedule.update_highlight(app.scheduleIdx,[1 0.2 0.2]);
                        app.Schedule.DO_NOT_DELETE = false;
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.update_lamp('error');
                        stateAcq = abr.stateAcq.CANCELLED;
                        
                end
                
            catch stateME
%                 fprintf(2,'Current Program State: "%s"\n',app.stateProgram)
                app.stateProgram = abr.stateProgram.ACQ_ERROR;
                app.StateMachine;
                rethrow(stateME);
            end
            
                
        end
        
        function control_acq_switch(app,event)
            vprintf(3,'User set control switch to %s',event.Value)

            switch event.Value
                case 'Acquire'
                    app.stateProgram = abr.stateProgram.PREP_BLOCK;
                    app.StateMachine;

%                     while ~any(app.stateProgram == [abr.stateProgram.USER_IDLE, abr.stateProgram.ACQ_ERROR, abr.stateProgram.SCHED_COMPLETE])
%                         app.StateMachine;
%                     end
                    
                case 'Idle'
                    stop(app.Timer);
                    
                    app.stateProgram = abr.stateProgram.USER_IDLE;
                    
                    % Send stop signal to background process
                    app.Runtime.CommandToBg = abr.Cmd.Stop;
                    
                    % reset gui
                    app.update_lamp('Cancelled');
                    
                    app.ControlPauseButton.Value = 0;
                    app.pause_button;
                    
                    app.Schedule.update_highlight(app.scheduleIdx);
                    
                    app.stateProgram = abr.stateProgram.USER_IDLE;
                    app.StateMachine;
            end
        end
        

        function run_acq_timer(app)            
            if isempty(app.Timer) || ~isvalid(app.Timer) || isempty(app.Timer.TimerFcn)
                T = timer('Tag','ABR_ControlPanel');
                
                T.BusyMode = 'drop';
                T.ExecutionMode = 'fixedRate';
                T.TasksToExecute = inf;
                T.Period = 0.05;
                T.StartDelay = 1;
                
                T.StartFcn = {app.timer_StartFcn,app};
                T.TimerFcn = {app.timer_RuntimeFcn,app};
                T.StopFcn  = {app.timer_StopFcn,app};
                T.ErrorFcn = {app.timer_ErrorFcn,app};

                app.Timer = T;
            end
            
            start(app.Timer);
        end           
        
        
        function check_rec_status(app)
            persistent prevState

            bgState = app.Runtime.BackgroundState;

            if bgState == prevState, return; end

            prevState = bgState;

            vprintf(3,'BackgroundState = %s',char(bgState))
            
            % check status of recording
            switch bgState
                case abr.stateAcq.COMPLETED
                    stop(app.Timer);
                    app.stateProgram = abr.stateProgram.BLOCK_COMPLETE;
                    app.StateMachine;
                    
                case abr.stateAcq.ERROR
                    stop(app.Timer);
                    app.stateProgram = abr.stateProgram.ACQ_ERROR;
                    app.StateMachine;
            end
        end

        function pause_button(app)
            global stateAcq
            
            hObj = app.ControlPauseButton;
            
            if stateAcq == abr.stateAcq.IDLE
                hObj.Text = 'Pause';
                hObj.Value = 0;
                hObj.Tooltip = 'Click to Pause';
                hObj.BackgroundColor = [0.96 0.96 0.96];
                
            elseif hObj.Value == 0
                % send command to background process
                if app.Runtime.CommandToBg == abr.Cmd.Pause
                    app.Runtime.CommandToBg = abr.Cmd.Run;
                end
                stateAcq = abr.stateAcq.ACQUIRE;
                hObj.Text = 'Pause';
                hObj.Tooltip = 'Click to Pause';
                hObj.BackgroundColor = [0.96 0.96 0.96];
                app.AcquisitionStateLamp.Color = [0 1 0];
                
            elseif stateAcq == abr.stateAcq.ACQUIRE
                % send command to background process
                app.Runtime.CommandToBg = abr.Cmd.Pause;
                stateAcq = abr.stateAcq.PAUSED;
                hObj.Text = '*PAUSED*';
                hObj.Tooltip = 'Click to Resume';
                hObj.UserData = hObj.BackgroundColor;
                hObj.BackgroundColor = [1 1 0];
            end
            
            drawnow
        end
        
        function advance_schedule(app,~)
            global stateAcq

            if stateAcq == abr.stateAcq.IDLE, return; end
            
            vprintf(2,'User advanced to next block')
            stateAcq = abr.stateAcq.ADVANCED;
            app.Runtime.CommandToBg = abr.Cmd.Stop;

        end
        
        function repeat_schedule_idx(app,event)
            global stateAcq
            
            if stateAcq == abr.stateAcq.IDLE, return; end

            hObj = event.Source;
            if event.Value % depressed
                hObj.BackgroundColor = [0.8 0.8 1];
                app.update_ControlStimInfoLabel(inf);
                hObj.FontWeight = 'bold';
                
            else
                hObj.BackgroundColor = [.96 .96 .96];
                app.update_ControlStimInfoLabel(app.NumRepetitionsSpinner.Value);
                hObj.FontWeight = 'normal';
            end

            drawnow
        end
        
        
        function update_num_reps(app,event)
            vprintf(3,'Updated Number of Reps: %d',event.Value)
            app.update_ControlStimInfoLabel(event.Value);
        end

        function update_sweep_rate(app,event)
            vprintf(3,'Updated Sweep Rate: %.3f Hz',event.Value)
            if app.SweepDurationSpinner.Value/1000 > .5/event.Value
                app.SweepDurationSpinner.Value = 1000*.5/event.Value;
                abr.Tools.edit_field_alert(app.SweepDurationSpinner);
            end
        end
        
        function update_sweep_duration(app,event)
            sweepRate = app.SweepRateHzSpinner.Value;
            if event.Value/1000 > .5/sweepRate
                abr.Tools.edit_field_alert(app.SweepDurationSpinner);
                app.SweepDurationSpinner.Value = event.PreviousValue;
                return
            end
            vprintf(3,'Updated Sweep Duration: %.3f ms',event.Value/1000)
            app.ABR.adcWindow = [0 event.Value/1000];
        end
        
        
        function update_sweep_count(app,event)
            global stateAcq
            
            v = event.Value;
            if ischar(v), v = str2double(v); end
            if isnan(v) || ~isreal(v)
                event.Source.FontColor       = [1 1 1];
                event.Source.BackgroundColor = [1 0 0];
                pause(0.5)
                event.Source.Value = event.PreviousValue;
                event.Source.FontColor       = [0 0 0];
                event.Source.BackgroundColor = [1 1 1];
                return 
            else
                event.Source.FontColor       = [0 0 0];
                event.Source.BackgroundColor = [1 1 1];
            end
            
            % don't update gauge during a block
            if stateAcq == abr.stateAcq.ACQUIRE, return; end
                
            app.ControlSweepCountGauge.Limits = double([0 v]);
            drawnow
        end
        
        
        function update_ControlStimInfoLabel(app,nReps)
            
            selData = app.Schedule.selectedData;
            
            n = sum(selData);
            m = find(find(selData) == app.scheduleIdx);
            
            app.ControlStimInfoLabel.Text = sprintf( ...
                'Block %d of %d  | Schedule Row %d | Repetition %d of %d', ...
                m,n,app.scheduleIdx, ...
                app.scheduleRunCount(app.scheduleIdx)+1,nReps);
        end
        
        
        function update_lamp(app,state)
            txt = '';
            color = [.6 .6 .6];
            ttip = '';
            switch lower(state)
                case 'ready'
                    txt = 'Ready';
                    ttip = 'Ready to begin acquisition';

                case 'acquiring'
                    txt = 'Acquiring';
                    color = [0 1 0];
                    ttip = 'Acquiring ABR Block';
                    
                case 'prep'
                    txt = 'Prepping';
                    color = [1 1 0];
                    ttip = 'Preping Block';
            
                case 'starting'
                    txt = 'Starting';
                    color = [0 .4 .8];
                    ttip = 'Starting block';

                case 'advancing'
                    txt = 'Advancing';
                    color = [0 .4 .8];
                    ttip = 'Advancing to next block';
                    
                case 'saving'
                    txt = 'Saving Data';
                    color = [.2 .8 1];
                    ttip = 'Saving ABR Data';

                case 'finished'
                    txt = 'Finished';
                    ttip = 'Completed Schedule';

                case 'cancelled'
                    txt = 'Cancelled';
                    ttip = 'User cancelled acquisition';

                case 'error'
                    txt = 'ERROR';
                    color = [1 0 0];
                    ttip = 'Error!';
            end

            
            app.AcquisitionStateLabel.Text = txt;
            app.AcquisitionStateLamp.Color = color;
            app.AcquisitionStateLamp.Tooltip = ttip;

            drawnow
        end










        
        
        %% UTILITIES ------------------------------------------------------
        
        function locate_utility(app, event)
            % Launch Schedule Design utility or locate if already exists
            
            try
                switch event.Source.UserData
                    case 'ScheduleDesign'
                        ScheduleDesign;
                        
                    case ''
                        return
                        
                    otherwise
                        run(event);
                end
            catch me
                errordlg(sprintf('Unable to launch: %s""\n\n%s\n%s',event.Source.Text,me.identifier,me.message), ...
                    'launch_utility','modal');
            end
        end
        
        
        
        %% SUBJECT --------------------------------------------------------
        function add_subject(app)
            
        end
        
        function create_subject_tree(app)
            
            subjs = dir(fullfile(app.subjectDirectory,'*.ABRsubj'));
            
            if isfield(app,'SubjectNode'), delete(app.SubjectNode); end
            
            for i = 1:length(subjs)
                
                load(fullfile(subjs.folder,subjs.name),'Subject');
                
                % Create Node
                app.SubjectNode(i) = uitreenode(app.SubjectTree);
                app.SubjectNode(i).Text = sprintf('%s: %s',Subject.ID,Subject.Alias); %#ok<ADPROP>
                
            end
            
        end
        
        %% FILTER ---------------------------------------------------------
        function filter_enable_switch(app,event)
            
            switch event.Value
                case 'Disabled'
                    app.FilterEnabledLamp.Color = [0.6 0.6 0.6];
                    
                case 'Enabled'
                    app.FilterEnabledLamp.Color = [0 1 0];
                    
            end
        end
        
        function notch_filter_select(app,event)
            
            switch event.Value
                case 0
                    app.FilterNotchEnabledLamp.Color = [0.6 0.6 0.6];
                    
                otherwise
                    app.FilterNotchEnabledLamp.Color = [0 1 0];
                    
            end
        end
        
        
        
        %% OTHER ----------------------------------------------------------
       
        
        function ax = live_analysis_plot(app)    
            f = findobj('type','figure','-and','name','Live Analysis');
            if ~isempty(f) && ishandle(f)
                ax = findobj('type','axes','-and','tag','live_analysis_plot');
                return
            end
            p = app.ControlPanelUIFigure.Position;
            f = figure('name','Live Analysis','color','w','NumberTitle','off', ...
                'Position',[p(1)+p(3)-60020 p(2)+p(4)-280 600 250]);
            ax = axes(f,'tag','live_analysis_plot','color','none');
            grid(ax,'on');
            box(ax,'on');
            % Correct???
            ax.XAxis.Label.String = app.ABR.SIG.SortProperty;
            ax.YAxis.Label.String = 'amplitude (mV)';
            
            ax.Toolbar.Visible = 'off'; % disable zoom/pan options
            ax.HitTest = 'off';
            
            figure(f);
        end
        
        function update_verbosity(app)
            global GVerbosity
            
            vstr = {'0 - Stealth mode'; ...
                 '1 - Basic info'; ...
                 '2 - Lots of info'; ...
                 '3 - Looking under the hood'; ...
                 '4 - Ludicrus!'};
            
            [s,v] = listdlg('PromptString','Set Verbosity Level', ...
                'SelectionMode','single', ...
                'InitialValue',GVerbosity+1, ...
                'ListString',vstr);
            
            if isequal(v,0), return; end
            
            GVerbosity = s-1;
            
            app.VerbosityMenu.Text = sprintf('Program Verbosity = %d',GVerbosity);
            
            vprintf(1,'Verbosity set to %s',vstr{GVerbosity+1})
            
            figure(app.ControlPanelUIFigure);
        end
    end
    
    
    methods (Access = public)
        
        % Constructor
        function app = ControlPanel(configFile)
            global stateAcq
            
            abr.Universal.startup;
            
            vprintf(0,'Starting MABR Control Panel ...')

            stateAcq = abr.stateAcq.IDLE;
            
            % setup as foreground process and launch background process
            if isempty(app.Runtime) || isstruct(app.Runtime) || ~isvalid(app.Runtime) || ~app.Runtime.FgIsRunning
                app.Runtime = abr.Runtime;
            end
            
            % idle background process
            app.Runtime.CommandToBg = abr.Cmd.Idle;
            
            app.createComponents;
            
            if nargin == 1 && ischar(configFile) && exist(configFile,'file') == 2
                app.configFile = configFile;
                app.load_config_file;
                
            elseif nargin == 0
                lastConfigFile = getpref('ABRControlPanel','configFile',[]);
                if ~isempty(lastConfigFile) && exist(lastConfigFile,'file') == 2
                    app.load_config_file(lastConfigFile);
                end
            end
                        
            app.populate_gui;

            
            figure(app.ControlPanelUIFigure);
            
            
            % Setup Background process AFTER creating GUI
            if ~app.Runtime.BgIsRunning
                abr.Runtime.launch_bg_process;
            end
            
            if nargout == 0, clear app; end
            
        end
        
        % Code that executes before app deletion
        function delete(app)
            
            % Delete UIFigure when app is deleted
            delete(app.ControlPanelUIFigure)
        end
        
        
        
        function select_audiodevice(app)
            app.ABR.selectAudioDevice;
            app.SelectAudioDeviceMenu.Text = sprintf('Audio Device: "%s"',app.ABR.audioDevice);
            figure(app.ControlPanelUIFigure);
        end
        
        
        function setup_audiochannels(app)
            app.ABR.setupAudioChannels;
        end
    end
    
    
    methods (Access = private)
        function update_amplifier_gain(app)
            g = getpref('ABRControlPanel','AmpGain',1);
            i = inputdlg('Enter input amplifier gain:','Amp Gain', ...
                1,{num2str(g)});
            if isempty(i), return; end
            g = str2double(i{1});
            if isnan(g) || ~isreal(g) || isinf(g) || ~isscalar(g) || g <= 0
                vprintf(0,1,'Invalid value for input gain: %s',i{1})
                return
            end
            vprintf(1,'Amplifier gain set to: %g',g);
            app.UpdateInputGainMenu.Text = sprintf('Amplifier Gain = %gx',g);
            setpref('ABRControlPanel','AmpGain',g);
        end
        
        function cp_docbox(app)
            c = strrep(lower(app.selectedTab.Title),' ','_');
            abr.Universal.docbox('control_panel','components',c);
        end
        
        function locate_figures(app)
            f = findall(0,'tag','MABR_FIG');
            if ~isempty(f), arrayfun(@figure,f); end
            
            f = findobj('-regexp','Tag','TRACEORGANIZER*');
            if ~isempty(f), arrayfun(@figure,f); end
        end
        
        function reset_bg_process(app)
            r = uiconfirm(app.ControlPanelUIFigure, ...
                'Are you certain you want to reset the background process?', ...
                'Reset Background Process','Icon','warning', ...
                'Options',{'Reset','Nevermind'},'DefaultOption','Nevermind', ...
                'CancelOption','Nevermind');
            if isequal(r,'Nevermind'), return; end
            vprintf(1,1,'User reset background process')
            app.Runtime.CommandToBg = abr.Cmd.Kill;
            pause(0.5);
            app.Runtime.CommandToBg = abr.Cmd.Idle;
            vprintf(0,1,'Attempting to relaunch background process')
            abr.Runtime.launch_bg_process;
        end
        
        function close_request(app,event)
            global stateAcq
            try
                app.Schedule.DO_NOT_DELETE = false;
            end
            
            if stateAcq == abr.stateAcq.ACQUIRE
                uialert(app.ControlPanelUIFigure, ...
                    sprintf('I''m sorry Dave, I''m afraid I can''t do that.\n\nPlease first set acquisition to "Idle".'), ...
                    'Control Panel','Icon','warning','modal',true);
            else
                try
                    app.Runtime.CommandToBg = abr.Cmd.Kill;
                end
                delete(app);
            end
        end
    end
    
    methods (Static)
        R = partition_corr(preSweep,postSweep);
        r = summary_analysis(data,type,options);
        timer_Start(T,event,obj);
        timer_Runtime(T,event,obj);
        timer_Stop(T,event,obj);
        timer_Error(T,event,obj);
    end
end





