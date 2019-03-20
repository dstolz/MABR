classdef ControlPanel < matlab.apps.AppBase
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        ABR         (1,1) abr.ABR
        Subject     (1,1) abr.Subject
        Schedule    (1,1) abr.sigdef.Schedule
        
        Config
        
        configFile   (1,:) char
        scheduleFile (1,:) char
        
    end
    
    properties (SetAccess = private,GetAccess = public)
        programState    (1,:) char  = 'STARTUP';
        
        SIG         (1,1)
        
        scheduleRunCount (:,1)
        scheduleIdx      (1,1) = 1;
        alternateIdx     (1,1) = 1;
    end
    
    % Properties that correspond to app components
    properties (Access = public) %(Access = private)
        ControlPanelUIFigure           matlab.ui.Figure
        FileMenu                       matlab.ui.container.Menu
        LoadConfigurationMenu          matlab.ui.container.Menu
        SaveConfigurationMenu          matlab.ui.container.Menu
        OptionsMenu                    matlab.ui.container.Menu
        OptionShowTimingStats          matlab.ui.container.Menu
        StayonTopMenu                  matlab.ui.container.Menu
        ASIOSettingsMenu               matlab.ui.container.Menu
        TabGroup                       matlab.ui.container.TabGroup
        ConfigTab                      matlab.ui.container.Tab
        AcqFilterTab                   matlab.ui.container.Tab
        ScheduleDropDownLabel          matlab.ui.control.Label
        ConfigScheduleDropDown         matlab.ui.control.DropDown
        ConfigLocateSchedButton             matlab.ui.control.Button
        ConfigNewButton                matlab.ui.control.Button
        OutputDropDownLabel            matlab.ui.control.Label
        ConfigOutputDropDown           matlab.ui.control.DropDown
        ConfigSaveButton               matlab.ui.control.Button
        ConfigLoadButton               matlab.ui.control.Button
        SubjectInfoTab                 matlab.ui.container.Tab
        DOBDatePickerLabel             matlab.ui.control.Label
        SubjectDOBDatePicker           matlab.ui.control.DatePicker
        SubjectTree                    matlab.ui.container.Tree
        NotesTextAreaLabel             matlab.ui.control.Label
        SubjectNotesTextArea           matlab.ui.control.TextArea
        AliasEditFieldLabel            matlab.ui.control.Label
        SubjectAliasEditField          matlab.ui.control.EditField
        IDEditFieldLabel               matlab.ui.control.Label
        SubjectIDEditField             matlab.ui.control.EditField
        SubjectSexSwitch               matlab.ui.control.Switch
        ScientistDropDownLabel         matlab.ui.control.Label
        SubjectScientistDropDown       matlab.ui.control.DropDown
        SubjectAddaSubjectButton       matlab.ui.control.Button
        ControlTab                     matlab.ui.container.Tab
        ControlSweepCountGauge         matlab.ui.control.LinearGauge
        ControlStimInfoLabel           matlab.ui.control.Label
        NumRepetitionsLabel            matlab.ui.control.Label
        NumRepetitionsSpinner          matlab.ui.control.Spinner
        ControlAdvCriteriaDropDownLabel  matlab.ui.control.Label
        ControlAdvCriteriaDropDown     matlab.ui.control.DropDown
        SweepsSpinnerLabel             matlab.ui.control.Label
        SweepCountSpinner              matlab.ui.control.Spinner
        SweepRateHzSpinnerLabel        matlab.ui.control.Label
        SweepRateHzSpinner             matlab.ui.control.Spinner
        Panel_2                        matlab.ui.container.Panel
        ControlAdvanceButton           matlab.ui.control.Button
        ControlRepeatButton            matlab.ui.control.StateButton
        ControlPauseButton             matlab.ui.control.StateButton
        ControlAcquisitionSwitch       matlab.ui.control.ToggleSwitch
        AcquisitionStateLamp           matlab.ui.control.Lamp
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
        
        
        SubjectNode     matlab.ui.container.TreeNode
    end
    
    
    % Set/Get Properties
    methods
        function ffn = get.scheduleFile(app)
            ffn = app.ConfigScheduleDropDown.Value;
            if isempty(ffn) || isequal(ffn,'NO SCHED FILES'), return; end
            if ~exist(ffn,'file')
                errordlg(sprintf('Missing schedule file! "%s"', ...
                    ffn),'Schedule File','modal');
            end
            
        end
        
        function set.programState(app,state)
            app.programState = state;
            app.Dispatch;
        end
        
        
        function a = get.alternateIdx(app)
            % alternate
            if app.alternateIdx == 1
                a = 2;
            else
                a = 1;
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
            
            % Schedule File
            if isempty(app.scheduleFile)
                c = getpref('ABRControlPanel','schedPath',cd);
                f = dir(fullfile(c,'*.sched'));
            else
                f = dir(fullfile(fileparts(app.scheduleFile),'*.sched'));
            end
            
            if isempty(f)
                app.ConfigScheduleDropDown.Items     = {'Load a schedule file -->'};
                app.ConfigScheduleDropDown.ItemsData = {'NO SCHED FILES'};
                app.ConfigScheduleDropDown.Value     = 'NO SCHED FILES';
            else
                app.ConfigScheduleDropDown.Items     = {f.name};
                app.ConfigScheduleDropDown.ItemsData = cellfun(@fullfile,{f.folder},{f.name},'uni',0);
                app.ConfigScheduleDropDown.Value     = fullfile(f(1).folder,f(1).name);
            end
            
            
            
        end
        
        
        
        
        
        
        %% MENU -----------------------------------------------------------
        function launch_asiosettings(app)
            % launches external ASIO settings gui
            asiosettings;
        end
        
        function menu_option_processor(app,event)
            hObj = event.Source;
            
            if isequal(hObj.Checked,'on')
                hObj.Checked = 'off';
            else
                hObj.Checked = 'on';
            end
        end
        
        
        
        
        
        
        
        
        
        
        %% CONFIG ---------------------------------------------------------
        function gather_config_parameters(app)
            
            app.Config.scheduleFile = app.scheduleFile;
            app.Config.configFile   = app.configFile;
            
            app.Config.Control.advCriteria = app.ControlAdvCriteriaDropDown.Value;
            app.Config.Control.numSweeps   = app.SweepCountSpinner.Value;
            app.Config.Control.sweepRate   = app.SweepRateHzSpinner.Value;
            
            app.Config.Control.frameLength = 512;
            
            
            app.Config.Filter.adcFilterHP  = app.FilterHPFcEditField.Value;
            app.Config.Filter.adcFilterLP  = app.FilterLPFcEditField.Value;
            
        end
        
        function apply_config_parameters(app)
            
        end
        
        function locate_schedule_file(app)
            dfltPth = getpref('ABRControlPanel','schedulePath',cd);
            
            [fn,pn] = uigetfile({'*.sched','Stimulus Schedule File (*.sched)'}, ...
                'Load Stimulus Schedule File',dfltPth);
            
            if isequal(fn,0), return; end
            
            app.scheduleFile = fullfile(pn,fn);
            
            if isempty(app.scheduleFile), return; end
            
            d = dir(fullfile(pn,'*.sched'));
            
            app.ConfigScheduleDropDown.Items     = cellfun(@(a) a(1:find(a=='.',1,'last')-1),{d.name},'uni',0);
            app.ConfigScheduleDropDown.ItemsData = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
            app.ConfigScheduleDropDown.Value     = fullfile(pn,fn);
            
            setpref('ABRControlPanel','schedulePath',pn);
            
            app.load_schedule_file;
            
        end
        
        function load_config_file(app)
            dfltPth = getpref('ABRControlPanel','configPath',cd);
            
            [fn,pn] = uigetfile({'*.cfg','ABR Config File (*.cfg)'}, ...
                'Load ABR Configuration File',dfltPth);
            
            if isequal(fn,0), return; end
            
            app.configFile = fullfile(pn,fn);
            
            if isempty(app.configFile), return; end
            
            % Load configuration file
            load(app.configFile,'abrConfig','-mat');
            
            app.ABR     = abrConfig.ABR;
            app.Subject = abrConfig.Subject;
            
            setpref('ABRControlPanel','configPath',fileparts(app.configFile));
            
            app.populate_gui;
        end
        
        
        function save_config_file(app)
            % Save configuration file
            
            dfltPth = getpref('ABRControlPanel','configPath',cd);
            
            [fn,pn] = uiputfile({'*.cfg', 'ABR Configuration (.cfg)'}, ...
                'Save ABR Configuration File',dfltPth);
            
            if isequal(fn,0), return; end

            abrConfig.ABR     = app.ABR;
            abrConfig.Subject = app.Subject;
            
            save(fullfile(pn,fn),'abrConfig','-mat');
            
            fprintf('ABR Configuration file saved: %s\n',fn)
            
            setpref('ABRControlPanel','configPath',pn);
        end
        
        function load_schedule_file(app,event)
            if isempty(app.scheduleFile), return; end
            if nargin == 2
                app.scheduleFile = event.Value;
            end
            app.Schedule.createGUI;
            app.Schedule.filename = app.scheduleFile;
            app.Schedule.load_schedule;
        end
        
        
        
        
        
        %% CONTROL --------------------------------------------------------
        function Dispatch(app)
            global ACQSTATE
            
            try
                switch app.programState
                    case 'STARTUP'
                        drawnow
                        
                    case 'PREFLIGHT'
                        app.gather_config_parameters;
                        
                        app.AcquisitionStateLabel.Text = 'Starting';
                        
                        app.AcquisitionStateLamp.Color = [1 1 0];
                        app.AcquisitionStateLamp.Tooltip = 'Starting ...';
                        
                        app.ControlSweepCountGauge.Value = 0;
                        
                        app.ControlPauseButton.Value = 0;
                        app.pause_button;
                        
                        % TO DO: make user settable option
                        app.ABR.audioDevice = 'ASIO4ALL v2'; 
                        
                        app.Schedule.filename = app.scheduleFile;
                        app.Schedule.createGUI;
                        
                        app.scheduleIdx  = find(app.Schedule.selectedData,1,'first');
                        app.scheduleRunCount = zeros(size(app.Schedule.selectedData));
                        app.alternateIdx = 1;
                        
                        drawnow
                        
                        app.programState = 'REPADVANCE'; % to first trial
                        
                        
                    case 'REPADVANCE'
                        if isequal(ACQSTATE,'CANCELLED'), return; end
                        
                        app.gather_config_parameters; % in case user updates guis
                        
                        % find next trial                        
                        nReps = app.NumRepetitionsSpinner.Value;
                        if app.scheduleRunCount(app.scheduleIdx) >= nReps
                            ind = app.scheduleRunCount(app.scheduleIdx+1:end) < nReps ...
                                & app.Schedule.selectedData(app.scheduleIdx+1:end)';
                            app.scheduleIdx = app.scheduleIdx + find(ind,1,'first');
                        end
                        
                        if isempty(app.scheduleIdx)
                            % reached end of schedule
                            app.programState = 'SCHEDCOMPLETED';
                            return
                        end
                        
                        app.SIG = app.Schedule.sigArray(app.scheduleIdx).update;
                        
                        
                        app.ControlStimInfoLabel.Text = sprintf( ...
                            'Schedule Index %d of %d  |  Repetition %d of %d', ...
                            app.scheduleIdx,sum(app.Schedule.selectedData), ...
                            app.scheduleRunCount(app.scheduleIdx)+1,nReps);
                        
                        
                        
                        % convert to signal
                        app.ABR.dacFs = app.SIG.Fs;
                        if iscell(app.SIG.data)
                            % TO DO: THIS WON'T WORK AS INTENDED!
                            %        This needs to be done on a sweep-by-sweep
                            %        basis.
                            app.ABR.dacBuffer = app.SIG.data{app.alternateIdx};
                        else
                            app.ABR.dacBuffer = app.SIG.data;
                        end
                        
                        % update ABR info after setting buffer
                        app.ABR.frameLength = app.Config.Control.frameLength;
                        app.ABR.numSweeps   = app.Config.Control.numSweeps;
                        app.ABR.sweepRate   = app.Config.Control.sweepRate;
                        
                        app.ABR.adcFilterLP = app.Config.Filter.adcFilterLP;
                        app.ABR.adcFilterHP = app.Config.Filter.adcFilterHP;
                        app.ABR.adcUseBPFilter = isequal(app.FilterEnableSwitch.Value,'Enabled');
                        
                        app.ABR.adcUseNotchFilter  = app.FilterNotchFilterKnob.Value ~= 0;
                        app.ABR.adcNotchFilterFreq = app.FilterNotchFilterKnob.Value;
                        
                        app.ABR.createADCfilt;
                        
                        drawnow
                        
                        app.programState = 'ACQUIRE';
                        
                    case 'ACQUIRE'
                        app.AcquisitionStateLabel.Text = 'Acquiring';
                        
                        app.AcquisitionStateLamp.Color = [0 1 0];
                        app.AcquisitionStateLamp.Tooltip = 'Acquiring';
                        
                        try
                            % do it
                            ax = app.live_plot;
                            app.acquireBatch(ax,'showTimingStats',isequal(app.OptionShowTimingStats.Checked,'on'));
                            
                            app.programState = 'REPCOMPLETE';
                            
                            ACQSTATE = 'IDLE';
                            
                        catch me
                            app.programState = 'ACQUISITIONEERROR';
                            rethrow(me);
                        end
                        
                    case 'REPCOMPLETE'
                        app.scheduleRunCount(app.scheduleIdx) = app.scheduleRunCount(app.scheduleIdx) + 1;
                        
                        % SAVE ABR DATA
                        
                        app.programState = 'REPADVANCE';
                        
                        
                    case 'SCHEDCOMPLETED'
                        ACQSTATE = 'IDLE';
                        
                        
                    case 'USERIDLE'
                        app.AcquisitionStateLabel.Text = 'Ready';
                        app.ControlAcquisitionSwitch.Value = 'Idle';
                        app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];
                        app.AcquisitionStateLamp.Tooltip = 'Idle';
                        
                        ACQSTATE = 'CANCELLED';
                        drawnow
                        
                        
                    case 'ACQUISITIONEERROR'
                        app.AcquisitionStateLabel.Text = 'ERROR';
                        
                        app.ControlAcquisitionSwitch.Value = 'Idle';
                        app.AcquisitionStateLamp.Color = [1 0 0];
                        app.AcquisitionStateLamp.Tooltip = 'ERROR';
                        
                        ACQSTATE = 'CANCELLED';
                        drawnow
                end
                
            catch stateME
                fprintf(2,'Current Program State: "%s"\n',app.programState)
                app.programState = 'ACQUISITIONEERROR';
                rethrow(stateME);
            end
                
        end
        
        
        function control_acq_switch(app,event)
            switch event.Value
                case 'Acquire'
                    app.programState = 'PREFLIGHT';
                    

                case 'Idle'
                    % Send stop signal
                    app.programState = 'USERIDLE';
            end
        end
        
        function pause_button(app)
            global ACQSTATE
            
            hObj = app.ControlPauseButton;
            
            if isequal(ACQSTATE,'IDLE')
                hObj.Text = 'Pause ||';
                hObj.Value = 0;
                hObj.Tooltip = 'Click to Pause';
                hObj.BackgroundColor = [0.96 0.96 0.96];
                
            elseif hObj.Value == 0
                ACQSTATE = 'ACQUIRE';
                hObj.Text = 'Pause ||';
                hObj.Tooltip = 'Click to Pause';
                hObj.BackgroundColor = [0.96 0.96 0.96];
                app.AcquisitionStateLamp.Color = [0 1 0];
                
            elseif isequal(ACQSTATE,'ACQUIRE')
                ACQSTATE = 'PAUSED';
                hObj.Text = '*PAUSED*';
                hObj.Tooltip = 'Click to Resume';
                hObj.UserData = hObj.BackgroundColor;
                hObj.BackgroundColor = [1 0.2 0.2];
            end
        end
        
        
        function update_sweep_count(app,event)
            app.ControlSweepCountGauge.Limits = double([0 event.Source.Value]);
            drawnow limitrate
        end
        
        
        
        
        
        
        
        
        
        %% UTILITIES ------------------------------------------------------
        
        function locate_utility(app, event)
            % Launch Schedule Design utility or locate if already exists
            
            try
                switch event.Source.Text
                    case 'Schedule Design'
                        ScheduleDesign; %(app.schedDesignFile);
                        
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
            app.Config.Filter.Enable = event.Value;
            
            switch event.Value
                case 'Disabled'
                    app.FilterEnabledLamp.Color = [0.6 0.6 0.6];
                    
                case 'Enabled'
                    app.FilterEnabledLamp.Color = [0 1 0];
                    
            end
        end
        
        function notch_filter_select(app,event)
            app.Config.Filter.Notch.Enable = event.Value;
            
            switch event.Value
                case '0'
                    app.FilterNotchEnabledLamp.Color = [0.6 0.6 0.6];
                    
                otherwise
                    app.FilterNotchEnabledLamp.Color = [0 1 0];
                    
            end
        end
        
        
        
        %% OTHER ----------------------------------------------------------
        function ax = live_plot(app)    
            % TO DO: Make into it's own class
            f = findobj('type','figure','-and','name','Live Plot');
            if ~isempty(f) && ishandle(f)
                ax = findobj('type','axes','-and','tag','live_plot');
                return
            end
            f = figure('name','Live Plot','color','w');
            ax = axes(f,'tag','live_plot');
            grid(ax,'on');
            box(ax,'on');
            ax.XAxis.Label.String = 'time (ms)';
            ax.YAxis.Label.String = 'amplitude (mV)';
        end
    end
    
    
    
    
    
    
    methods (Access = public)
        
        % Construct app
        function app = ControlPanel(configFile)
            global ACQSTATE
            
            ACQSTATE = 'IDLE';

            app.createComponents
            
            % Register the app with App Designer
            %             registerApp(app, app.ControlPanelUIFigure)
            
            
            if nargin == 1 && exist(configFile,'file') == 2
                app.configFile = configFile;
                app.load_config_file;
                
            elseif nargin == 0
                lastConfigFile = getpref('ABRControlPanel','lastConfigFile',[]);
                if ~isempty(lastConfigFile)
                    app.configFile = lastConfigFile;
                    app.load_config_file;
                end
            end
            
            app.populate_gui;
            
            if nargout == 0, clear app; end
        end
        
        % Code that executes before app deletion
        function delete(app)
            
            % Delete UIFigure when app is deleted
            delete(app.ControlPanelUIFigure)
        end
    end
    
    
    methods (Static)
        
    end
end





