classdef ControlPanel < matlab.apps.AppBase & abr.ABRGlobal
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        ABR                 (1,1) abr.ABR
        
        TrcOrg              (1,1) abr.traces.Organizer
        
        Config              (1,1) struct

%         Subject             (1,1) abr.Subject
        Schedule            (1,1) abr.Schedule
        Calibration         (1,1) abr.AcousticCalibration
        
        configFile          (1,:) char
        scheduleFile        (1,:) char
        calibrationFile     (1,:) char
        outputFile          (1,:) char
        
    end
    
    properties (SetAccess = private)
        programState     (1,1) abr.PROGRAMSTATE = abr.PROGRAMSTATE.STARTUP;
        
        SIG              (1,1)
        
        scheduleRunCount (:,1)
        scheduleIdx      (1,1) = 1;
        
        DATA             (:,1) abr.ABR
        
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
        SweepCountSpinner              matlab.ui.control.Spinner
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
        UtilityOnlineAnalysisButton    matlab.ui.control.Button
        HelpButton                     matlab.ui.control.Button
        
        SubjectNode     matlab.ui.container.TreeNode
        
        TIMER (1,1) timer
    end
    
    properties
        ControlSweepCountGauge         matlab.ui.control.LinearGauge
        AcquisitionStateLamp           matlab.ui.control.Lamp
    end
    
    
    % Set/Get Properties
    methods
        createComponents(app);
        
        function ffn = get.outputFile(app)
            fn = app.OutputFileDD.Value;
            pn = app.OutputPathDD.Value;
            
            ffn = fullfile(pn,fn);
            
            if isequal(ffn,app.outputFile), return; end % no change

            if exist(ffn,'file') == 2
                fprintf('Appending to output file: %s (%s)\n',fn,pn)
                load(ffn,'-mat','meta');
                if ~isequal(meta.DataVersion,app.DataVersion)
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
        
    end
    
    
    
    
    
    
    
    methods (Access = private)
        abrAcquireBatch(app,ax,varargin);
        
        % Selection change function: TabGroup
        function TabGroupSelectionChanged(app, event)
            selectedTab = app.TabGroup.SelectedTab;
            
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
                    app.ConfigFileDD.Value     = app.configFile;
                    app.ConfigFileDD.Tooltip   = app.last_modified_str(app.configFile);
                    app.ConfigFileDD.FontColor = [0 0 0];
                    app.ConfigFileLabel.Tooltip = fileparts(app.configFile);
                    setpref('ABRControlPanel','recentConfigs',c);
                end
            end
            
            
            % Schedule File
            if isempty(app.scheduleFile)  
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
                app.ConfigScheduleDD.Value     = app.scheduleFile;
                app.ConfigScheduleDD.Tooltip   = app.last_modified_str(app.scheduleFile);
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
                    app.CalibrationDD.Value     = app.calibrationFile;
                    app.CalibrationDD.Tooltip   = app.last_modified_str(app.calibrationFile);
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
            TraceOrganizer  = app.TrcOrg;
            save(app.outputFile,'ABR_Data','TraceOrganizer','-mat','-v7.3');
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
            app.Config.scheduleFile    = app.scheduleFile;
            app.Config.configFile      = app.configFile;
            app.Config.calibrationFile = app.calibrationFile;
            app.Config.outputFile      = app.outputFile;
            
            app.Config.Control.advCriteria = app.ControlAdvCriteriaDD.Value;
            app.Config.Control.numSweeps   = app.SweepCountSpinner.Value;
            app.Config.Control.sweepRate   = app.SweepRateHzSpinner.Value;
            app.Config.Control.numReps     = app.NumRepetitionsSpinner.Value;
            app.Config.Control.sweepDuration = app.SweepDurationSpinner.Value;
            
            app.Config.Control.frameLength = abr.ABRGlobal.frameLength;
            
            app.Config.Filter.Enable       = app.FilterEnableSwitch.Value;
            app.Config.Filter.adcFilterHP  = app.FilterHPFcEditField.Value;
            app.Config.Filter.adcFilterLP  = app.FilterLPFcEditField.Value;
            app.Config.Filter.Notch.Freq   = app.FilterNotchFilterKnob.Value;
        end
        
        function apply_config_parameters(app)
            
            app.ControlAdvCriteriaDD.Value = app.Config.Control.advCriteria;
            app.SweepCountSpinner.Value          = app.Config.Control.numSweeps;
            app.SweepRateHzSpinner.Value         = app.Config.Control.sweepRate;
            app.NumRepetitionsSpinner.Value      = app.Config.Control.numReps;
            app.SweepDurationSpinner.Value       = app.Config.Control.sweepDuration;
            
            app.FilterEnableSwitch.Value         = app.Config.Filter.Enable;
            app.FilterHPFcEditField.Value        = app.Config.Filter.adcFilterHP;
            app.FilterLPFcEditField.Value        = app.Config.Filter.adcFilterLP;
            app.FilterNotchFilterKnob.Value      = app.Config.Filter.Notch.Freq;
            
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
            h.Items     = app.truncate_str(recentPaths,30);
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
            if ~app.validate_filename(nffn)
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
            

            if isvalid(app.Schedule)
                app.Schedule.load_schedule(app.scheduleFile);
            else
                h = findobj('type','figure','-and','name','CONTROL_PANEL_SCHEDULE');
                delete(h);
                app.Schedule = abr.Schedule(app.scheduleFile);
            end
            
            app.ConfigScheduleDD.Tooltip = app.last_modified_str(app.scheduleFile);
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
                load(app.calibrationFile,'CalibrationData','-mat');
                app.Calibration = CalibrationData;
                app.CalibrationDDLabel.Tooltip    = fileparts(app.calibrationFile);
                app.CalibrationDD.Tooltip = app.last_modified_str(app.calibrationFile);
            else
                app.Calibration = abr.AcousticCalibration; % blank calibration
                app.CalibrationDDLabel.Tooltip    = 'No Calibration File Loaded';
                app.CalibrationDD.Tooltip = 'No Calibration File Loaded';
            end
            
        end
        
        
        %% CONTROL --------------------------------------------------------
        function StateMachine(app)
            global ACQSTATE
            
            persistent active_state
            
            if active_state == app.programState, return; end
            
            active_state = app.programState;
            
            try
                switch active_state
                    case abr.PROGRAMSTATE.STARTUP
                        drawnow
                        
                    case abr.PROGRAMSTATE.PREFLIGHT
                        
                        app.gather_config_parameters;
                        
                        app.pause_button;

                        app.AcquisitionStateLabel.Text = 'Starting';
                        
                        app.AcquisitionStateLamp.Color = [1 1 0];
                        app.AcquisitionStateLamp.Tooltip = 'Starting ...';
                        
                        app.ControlSweepCountGauge.Value = 0;
                        app.ControlPauseButton.Value = 0;
                        
                        
                        app.load_schedule_file;
                        
                        app.TrcOrg.figure;
                        
                        app.Schedule.DO_NOT_DELETE = true;
                        app.scheduleIdx  = find(app.Schedule.selectedData,1,'first');
                        app.scheduleRunCount = zeros(size(app.Schedule.selectedData));
                        
                        drawnow
                        
                        app.programState = abr.PROGRAMSTATE.REPADVANCE; % to first trial
                        
                        
                        
                    case abr.PROGRAMSTATE.REPADVANCE
                        if ACQSTATE==abr.ACQSTATE.CANCELLED, return; end
                        
                        app.gather_config_parameters; % in case user updates guis
                        
                        if app.ControlRepeatButton.Value % 1 == depressed 
                            nReps = -1;
                        else
                            % find next trial
                            nReps = app.NumRepetitionsSpinner.Value;
                            if app.scheduleRunCount(app.scheduleIdx) >= nReps
                                ind = app.scheduleRunCount(app.scheduleIdx+1:end) < nReps ...
                                    & app.Schedule.selectedData(app.scheduleIdx+1:end);
                                if any(ind)
                                    app.scheduleIdx = app.scheduleIdx + find(ind,1,'first');
                                else
                                    % reached end of schedule
                                    app.programState = abr.PROGRAMSTATE.SCHEDCOMPLETE;
                                    return
                                end
                            end
                        end
                        
                        % update Schedule table selection                        
                        app.Schedule.sigArray(app.scheduleIdx).update;
                        app.Schedule.update_highlight(app.scheduleIdx);
                        
                        % update gui info
                        app.update_ControlStimInfoLabel(nReps);
                        
                        % convert to signal
                        app.ABR.DAC.SampleRate = app.SIG.Fs;
                        app.ABR.DAC.FrameSize = abr.ABRGlobal.frameLength;
                        
                        % reset the ADC buffer
                        app.ABR.ADC = abr.Buffer;
                        
                        app.ABR.ADC.FrameSize = abr.ABRGlobal.frameLength;
                        app.ABR.ADC.SampleRate = 12000; % TO DO: make app.ABR.ADC.SampleRate user settable?
                        app.ABR.adcDecimationFactor = max([1 floor(app.SIG.Fs ./ app.ABR.ADC.SampleRate)]);
                        app.ABR.ADC.SampleRate = app.ABR.DAC.SampleRate ./ app.ABR.adcDecimationFactor;

                        % generate signal based on its parameters
                        app.SIG = app.Schedule.sigArray(app.scheduleIdx);
                        app.SIG = app.SIG.update;
                        
                        
                        % copy stimulus to DAC buffer.
                        app.ABR.DAC.Data = app.SIG.data{1};
                        
                        % sweep duration
                        app.ABR.adcWindow = [0 app.Config.Control.sweepDuration]/1000; % ms -> s
                        
                        % calibrate stimulus data
                        if isvalid(app.Calibration)
                            f  = app.SIG.frequency.realValue;
                            sl = app.SIG.soundLevel.realValue;
                            A  = app.Calibration.estimateCalibratedV(f,sl);
                            app.ABR.DAC.Data = A .* app.ABR.DAC.Data;
                        else
                            h = warndlg('Invalid Calibration!','ABR','modal');
                            uiwait(h);                            
                        end
                        
                        % save original stimulus signal
                        app.ABR.SIG = app.SIG;
                        
                        % alternate polarity flag
                        app.ABR.altPolarity = app.SIG.polarity.Alternate;
                        
                        % update ABR info after setting buffer
                        app.ABR.numSweeps   = app.Config.Control.numSweeps;
                        app.ABR.sweepRate   = app.Config.Control.sweepRate;
                        
                        % setup optional digital filters
                        app.ABR.adcFilterLP = app.Config.Filter.adcFilterLP;
                        app.ABR.adcFilterHP = app.Config.Filter.adcFilterHP;
                        app.ABR.adcUseBPFilter = isequal(app.FilterEnableSwitch.Value,'Enabled');
                        
                        app.ABR.adcUseNotchFilter  = app.FilterNotchFilterKnob.Value ~= 0;
                        fv = app.FilterNotchFilterKnob.Value;
                        if fv > 0
                            app.ABR.adcNotchFilterFreq = fv;
                        end
                        
                        app.ABR = app.ABR.createADCfilt;
                        
                        
                        % reset pause button
                        app.ControlPauseButton.Value = 0;
                        app.ControlPauseButton.Text = 'Pause ';
                        app.ControlPauseButton.Tooltip = 'Click to Pause';
                        app.ControlPauseButton.BackgroundColor = [0.96 0.96 0.96];
                        app.AcquisitionStateLamp.Color = [0 1 0];
                        
                        drawnow
                        
                        app.programState = abr.PROGRAMSTATE.ACQUIRE;
                        
                        
                    case abr.PROGRAMSTATE.ACQUIRE
                        app.AcquisitionStateLabel.Text = 'Acquiring';
                        
                        app.AcquisitionStateLamp.Color = [0 1 0];
                        app.AcquisitionStateLamp.Tooltip = 'Acquiring';
                        
                        try
                            % do it
                            ax = app.live_plot;
                            figure(ancestor(ax,'figure'));
                            app.ABR = app.ABR.playrec(app,ax);

                            if app.programState == abr.PROGRAMSTATE.ACQUIRE
                                app.programState = abr.PROGRAMSTATE.REPCOMPLETE;
                            end
                                                        
                        catch me
                            app.programState = abr.PROGRAMSTATE.ACQUISITIONEERROR;
                            rethrow(me);
                        end
                        
                        
                        
                        
                    case abr.PROGRAMSTATE.REPCOMPLETE
                        app.scheduleRunCount(app.scheduleIdx) = app.scheduleRunCount(app.scheduleIdx) + 1;
                        
                        % Add buffer to traces.Organizer
                        app.TrcOrg.addTrace(app.ABR.ADC.SweepMean, ...
                            app.SIG.dataParams, ...
                            app.ABR.ADC.TimeVector(1), ...
                            app.ABR.ADC.SampleRate);
                        
                        %%%% TESTING
                        R = app.ABR.analysis('peaks');
                        
%                         % SAVE ABR DATA
%                         app.AcquisitionStateLabel.Text = 'Saving Data';
%                         app.auto_save_abr_data;
%                         drawnow
                        
                        
                                                
                        app.programState = abr.PROGRAMSTATE.REPADVANCE;
                        
                        
                    case abr.PROGRAMSTATE.SCHEDCOMPLETE
                        app.Schedule.update_highlight([]);
                        app.Schedule.DO_NOT_DELETE = false;
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.AcquisitionStateLamp.Color      = [0.6 0.6 0.6];
                        
                        % SAVE ABR DATA
                        app.AcquisitionStateLabel.Text      = 'Saving Data';
                        app.auto_save_abr_data;
                        drawnow                        
                        
                        app.AcquisitionStateLabel.Text      = 'Finished';
                        app.AcquisitionStateLamp.Tooltip    = 'Finished';
                        app.ControlStimInfoLabel.Text       = 'Completed';
                        drawnow
                        
                        
                    case abr.PROGRAMSTATE.USERIDLE
                        % SAVE ABR DATA
                        app.AcquisitionStateLabel.Text      = 'Saving Data';
                        app.AcquisitionStateLamp.Color      = [0.2 0.8 1];
                        drawnow
                        app.auto_save_abr_data;
                                                
                        
                        app.Schedule.DO_NOT_DELETE = false;
                        app.AcquisitionStateLabel.Text      = 'Ready';
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];
                        app.AcquisitionStateLamp.Tooltip    = 'Idle';
                        ACQSTATE = abr.ACQSTATE.CANCELLED;
                        
                        drawnow
                        
                        
                    case abr.PROGRAMSTATE.ACQUISITIONEERROR
                        app.Schedule.update_highlight(app.scheduleIdx,[1 0.2 0.2]);
                        app.Schedule.DO_NOT_DELETE = false;
                        app.AcquisitionStateLabel.Text      = 'ERROR';
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.AcquisitionStateLamp.Color      = [1 0 0];
                        app.AcquisitionStateLamp.Tooltip    = 'ERROR';
                        ACQSTATE = abr.ACQSTATE.CANCELLED;
                        
                        % SAVE ABR DATA
                        app.auto_save_abr_data;
                        
                        drawnow
                end
                
            catch stateME
%                 fprintf(2,'Current Program State: "%s"\n',app.programState)
                app.programState = abr.PROGRAMSTATE.ACQUISITIONEERROR;
                rethrow(stateME);
            end
            
                
        end
        
        function control_acq_switch(app,event)
            
            switch event.Value
                case 'Acquire'
                    app.programState = abr.PROGRAMSTATE.PREFLIGHT;
                    
                    while ~any(app.programState == [abr.PROGRAMSTATE.USERIDLE, abr.PROGRAMSTATE.ACQUISITIONEERROR, abr.PROGRAMSTATE.SCHEDCOMPLETE])
                        app.StateMachine;
                    end
                    
                case 'Idle'
                    % Send stop signal
                    app.programState = abr.PROGRAMSTATE.USERIDLE;
                    
                    % reset gui
                    app.AcquisitionStateLabel.Text = 'Cancelled';
                    
                    app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];
                    app.AcquisitionStateLamp.Tooltip = 'User cancelled acquisition';
                    
                    app.ControlPauseButton.Value = 0;
                    app.ControlPauseButton.Text = 'Pause';
                    app.ControlPauseButton.BackgroundColor = [0.96 0.96 0.96];
                    app.ControlPauseButton.Tooltip = 'Click to Pause';
                    
                    app.StateMachine;
            end
            
            
        end
        
        function pause_button(app)
            global ACQSTATE
            
            hObj = app.ControlPauseButton;
            
            if ACQSTATE == abr.ACQSTATE.IDLE
                hObj.Text = 'Pause';
                hObj.Value = 0;
                hObj.Tooltip = 'Click to Pause';
                hObj.BackgroundColor = [0.96 0.96 0.96];
                
            elseif hObj.Value == 0
                ACQSTATE = abr.ACQSTATE.ACQUIRE;
                hObj.Text = 'Pause';
                hObj.Tooltip = 'Click to Pause';
                hObj.BackgroundColor = [0.96 0.96 0.96];
                app.AcquisitionStateLamp.Color = [0 1 0];
                
            elseif ACQSTATE == abr.ACQSTATE.ACQUIRE
                ACQSTATE = abr.ACQSTATE.PAUSED;
                hObj.Text = '*PAUSED*';
                hObj.Tooltip = 'Click to Resume';
                hObj.UserData = hObj.BackgroundColor;
                hObj.BackgroundColor = [1 1 0];
            end
            
            drawnow
        end
        
        function advance_schedule(~,~)
            global ACQSTATE

            if ACQSTATE == abr.ACQSTATE.IDLE, return; end
            

            % TO DO: SHOULD BE ABLE TO ADVANCE TO THE NEXT STATE EVEN IF
            % NOT CURRENTLY ACQUIRING.  WHAT TrcOrg DO WITH 'PAUSED' STATE?
            
            % Updating ACQSTATE should be detected by ABR.playrec function
            % and stop the current acqusition, which returns control to the
            % StateMachine
%             ACQSTATE = 'REPCOMPLETE';
            ACQSTATE = abr.ACQSTATE.IDLE;
        end
        
        function repeat_schedule_idx(app,event)
            global ACQSTATE
            
            if ACQSTATE == abr.ACQSTATE.IDLE, return; end

            hObj = event.Source;
            if event.Value % depressed
                hObj.BackgroundColor = [0.8 0.8 1];
                app.update_ControlStimInfoLabel(-1);
                hObj.FontWeight = 'bold';
                
            else
                hObj.BackgroundColor = [.96 .96 .96];
                app.update_ControlStimInfoLabel(app.NumRepetitionsSpinner.Value);
                hObj.FontWeight = 'normal';
            end

            drawnow
        end
        
        
        function update_sweep_count(app,event)
            app.ControlSweepCountGauge.Limits = double([0 event.Source.Value]);
            drawnow limitrate
        end
        
        
        function update_ControlStimInfoLabel(app,nReps)
            
            selData = app.Schedule.selectedData;
            
            n = sum(selData);
            m = find(find(selData) == app.scheduleIdx);
            
            if nReps == -1
                app.ControlStimInfoLabel.Text = sprintf( ...
                    'Index %d (%d of %d)  |  Repetition %d < REPEATING >', ...
                    app.scheduleIdx,m,n, ...
                    app.scheduleRunCount(app.scheduleIdx)+1);
            else
                app.ControlStimInfoLabel.Text = sprintf( ...
                    'Index %d (%d of %d)  |  Repetition %d of %d', ...
                    app.scheduleIdx,m,n, ...
                    app.scheduleRunCount(app.scheduleIdx)+1,nReps);
            end
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
        
        function createSubjectTree(app)
            
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
        function ax = live_plot(app)    
            f = findobj('type','figure','-and','name','Live Plot');
            if ~isempty(f) && ishandle(f)
                ax = findobj('type','axes','-and','tag','live_plot');
                return
            end
            p = app.ControlPanelUIFigure.Position;
            f = figure('name','Live Plot','color','w','NumberTitle','off', ...
                'Position',[p(1)+p(3)+20 p(2)+p(4)-280 600 250]);
            ax = axes(f,'tag','live_plot','color','none');
            grid(ax,'on');
            box(ax,'on');
            ax.XAxis.Label.String = 'time (ms)';
            ax.YAxis.Label.String = 'amplitude (mV)';
            
            ax.Toolbar.Visible = 'off'; % disable zoom/pan options
            ax.HitTest = 'off';
            
            figure(f);
        end
        
        
    end
    
    
    methods (Access = public)
        
        % Constructor
        function app = ControlPanel(configFile)
            global ACQSTATE
            
            fprintf('Starting ABR Control Panel ...\n')
            
            ACQSTATE = abr.ACQSTATE.IDLE;

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
            
            if nargout == 0, clear app; end
            
        end
        
        % Code that executes before app deletion
        function delete(app)
            
            % Delete UIFigure when app is deleted
            delete(app.ControlPanelUIFigure)
        end
        
        
        
        function select_audiodevice(app)
            app.ABR = app.ABR.selectAudioDevice;
            app.SelectAudioDeviceMenu.Text = sprintf('Audio Device: "%s"',app.ABR.audioDevice);
            figure(app.ControlPanelUIFigure);
        end
        
        
        function setup_audiochannels(app)
            app.ABR = app.ABR.setupAudioChannels;
        end
    end
    
    
    methods (Access = private)
        function close_request(app,event)
            global ACQSTATE
            try
                app.Schedule.DO_NOT_DELETE = false;
            end
            
            if any(ACQSTATE == [abr.ACQSTATE.IDLE abr.ACQSTATE.CANCELLED])
                delete(app);
            else
                uialert(app.ControlPanelUIFigure, ...
                    sprintf('I''m sorry Dave, I''m afraid I can''t do that.\n\nPlease first set acquisition to "Idle".'), ...
                    'Control Panel','Icon','warning','modal',true);
            end
        end
    end
end





