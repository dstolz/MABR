classdef ControlPanel < matlab.apps.AppBase
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        ABR         (1,1) abr.ABR
        
        TrcOrg      (1,1) traces.Organizer
        
        Subject     (1,1) abr.Subject
        Schedule    (1,1) Schedule
        
        Config
        
        configFile   (1,:) char
        scheduleFile (1,:) char
        
    end
    
    properties (SetAccess = private,GetAccess = public)
        programState     (1,:) char  = 'STARTUP';
        
        SIG              (1,1)
        
        scheduleRunCount (:,1)
        scheduleIdx      (1,1) = 1;
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
        SelectAudioDeviceMenu          matlab.ui.container.Menu
        TabGroup                       matlab.ui.container.TabGroup
        ConfigTab                      matlab.ui.container.Tab
        AcqFilterTab                   matlab.ui.container.Tab
        ConfigFileSave                 matlab.ui.control.Button
        ConfigFileLoad                 matlab.ui.control.Button
        ConfigFileLabel                matlab.ui.control.Label
        ConfigFileDropDown             matlab.ui.control.DropDown
        ScheduleDropDownLabel          matlab.ui.control.Label
        ConfigScheduleDropDown         matlab.ui.control.DropDown
        ConfigNewSchedButton           matlab.ui.control.Button
        ConfigLoadSchedButton          matlab.ui.control.Button
        OutputDropDownLabel            matlab.ui.control.Label
        ConfigOutputDropDown           matlab.ui.control.DropDown
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
        
        TIMER (1,1) timer
    end
    
    
    % Set/Get Properties
    methods
        
        
        function set.programState(app,state)
            app.programState = state;
            app.StateMachine;
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
                app.ConfigFileDropDown.Items     = {'Load a configuration file -->'};
                app.ConfigFileDropDown.ItemsData = {'NO CONFIG'};
                app.ConfigFileDropDown.Value     = 'NO CONFIG';
                app.configFile = '';
            else
                ffn = app.configFile;
                c = getpref('ABRControlPanel','recentConfigs',[]);
                ind = ismember(c,ffn) | cellfun(@(a) not(isequal(exist(a,'file'),2)),c);
                c(ind) = [];
                c = [{ffn}; c];
                d = cellfun(@dir,c);
                fn = cellfun(@(a,b) sprintf('%s\t[%s]', ...
                    a(find(a==filesep,1,'last')+1:find(a=='.',1,'last')-1), b),...
                    c,{d.date}','uni',0);
                app.ConfigFileDropDown.Items     = fn;
                app.ConfigFileDropDown.ItemsData = c;
                app.ConfigFileDropDown.Value     = app.configFile;  
                setpref('ABRControlPanel','recentConfigs',c);
%            
%                 f = dir(fullfile(fileparts(app.configFile),'*.cfg'));
%                 app.ConfigFileDropDown.Items     = {f.name};
%                 app.ConfigFileDropDown.ItemsData = cellfun(@fullfile,{f.folder},{f.name},'uni',0);
%                 app.ConfigFileDropDown.Value     = app.configFile;            
            end
            
            
            % Schedule File
            if isempty(app.scheduleFile)  
                app.ConfigScheduleDropDown.Items     = {'Load a schedule file -->'};
                app.ConfigScheduleDropDown.ItemsData = {'NO SCHED FILES'};
                app.ConfigScheduleDropDown.Value     = 'NO SCHED FILES';
                app.scheduleFile = '';
            else
                d = dir(fullfile(fileparts(app.scheduleFile),'*.sch'));
                fn = cellfun(@(a,b) sprintf('%s\t[%s]', ...
                    a(1:find(a=='.',1,'last')-1), b),...
                    {d.name},{d.date},'uni',0);
                app.ConfigScheduleDropDown.Items     = fn;
                app.ConfigScheduleDropDown.ItemsData = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
                app.ConfigScheduleDropDown.Value     = app.scheduleFile;
            end
            
            
            % other
            app.SelectAudioDeviceMenu.Text = sprintf('Audio Device: "%s"',app.ABR.audioDevice);
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
            app.Config.scheduleFile = app.scheduleFile;
            app.Config.configFile   = app.configFile;
            
            app.Config.Control.advCriteria = app.ControlAdvCriteriaDropDown.Value;
            app.Config.Control.numSweeps   = app.SweepCountSpinner.Value;
            app.Config.Control.sweepRate   = app.SweepRateHzSpinner.Value;
            app.Config.Control.numReps     = app.NumRepetitionsSpinner.Value;
            
            % TO DO: MAKE ADVANCED AUDIO SETTINGS MENU
            app.Config.Control.frameLength = 2048;
            
            app.Config.Filter.Enable       = app.FilterEnableSwitch.Value;
            app.Config.Filter.adcFilterHP  = app.FilterHPFcEditField.Value;
            app.Config.Filter.adcFilterLP  = app.FilterLPFcEditField.Value;
            app.Config.Filter.Notch.Freq   = app.FilterNotchFilterKnob.Value;
        end
        
        function apply_config_parameters(app)
            
            app.ControlAdvCriteriaDropDown.Value = app.Config.Control.advCriteria;
            app.SweepCountSpinner.Value          = app.Config.Control.numSweeps;
            app.SweepRateHzSpinner.Value         = app.Config.Control.sweepRate;
            app.NumRepetitionsSpinner.Value      = app.Config.Control.numReps;
            
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
            
            app.scheduleFile = app.Config.scheduleFile;
            
            setpref('ABRControlPanel','configPath',fileparts(app.configFile));
            setpref('ABRControlPanel','configFile',app.configFile);
            
            app.populate_gui;
            
            app.apply_config_parameters;
            
            app.load_schedule_file;
            
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

            abrConfig.Config       = app.Config;
            abrConfig.scheduleFile = app.scheduleFile;
            abrConfig.configFile   = ffn;
            abrConfig.ABR          = app.ABR;
            
            save(ffn,'abrConfig','-mat');
            
            fprintf('ABR Configuration file saved: %s\n',fn)
            
            setpref('ABRControlPanel','configPath',pn);
            
            app.configFile = ffn;

            app.populate_gui;
        end
        
        
        function config_file_changed(app,event)
            
            app.load_config_file(event.Source.Value);
            
        end
        
        
        function load_schedule_file(app,event)
            if isempty(app.scheduleFile), return; end
            if nargin == 2
                app.scheduleFile = event.Value;
            end
            
            if isvalid(app.Schedule)
                app.Schedule.load_schedule(app.scheduleFile);
            else
                app.Schedule = Schedule(app.scheduleFile); %#ok<ADPROPLC>
            end
            
            app.SIG = app.Schedule.SIG;
        end
        
        
        
        
        
        %% CONTROL --------------------------------------------------------
        function StateMachine(app)
            global ACQSTATE
            persistent active_state
            
            if isequal(active_state,app.programState)
                return
            end
            
            active_state = app.programState;
            fprintf('%s\t%s\n',datestr(now,'HH:MM:SS.FFF'),active_state)
            
            try
                switch active_state
                    case 'STARTUP'
                        drawnow
                        
                    case 'PREFLIGHT'
                        
                        app.gather_config_parameters;
                        
                        app.pause_button;

                        app.AcquisitionStateLabel.Text = 'Starting';
                        
                        app.AcquisitionStateLamp.Color = [1 1 0];
                        app.AcquisitionStateLamp.Tooltip = 'Starting ...';
                        
                        app.ControlSweepCountGauge.Value = 0;
                        app.ControlPauseButton.Value = 0;
                        
                        
                        app.load_schedule_file;
                        
                        app.Schedule.DO_NOT_DELETE = true;
                        app.scheduleIdx  = find(app.Schedule.selectedData,1,'first');
                        app.scheduleRunCount = zeros(size(app.Schedule.selectedData));
                        
                        drawnow
                        
                        app.programState = 'REPADVANCE'; % to first trial
                        
                        
                        
                    case 'REPADVANCE'
                        if isequal(ACQSTATE,'CANCELLED'), return; end
                        
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
                                    app.programState = 'SCHEDCOMPLETE';
                                    return
                                end
                            end
                        end
                        
                        % update Schedule table selection                        
                        app.Schedule.sigArray(app.scheduleIdx).update;
                        app.Schedule.update_highlight(app.scheduleIdx);
                        
                        % update gui info
                        app.update_ControlStimInfoLabel(nReps);
                        
                        %%%% MAKE USER OPTION OR READ FROM ASIOSETTINGS????
                        app.ABR.DAC.FrameSize = 1024;
                        app.ABR.ADC.FrameSize = 1024;
                        
                        % convert to signal
                        app.ABR.DAC.SampleRate = app.SIG.Fs; % ????
                        
                        % TO DO: make app.ABR.ADC.SampleRate user settable?
                        app.ABR.ADC.SampleRate = 12000;
                        app.ABR.adcDecimationFactor = max([1 floor(app.SIG.Fs ./ app.ABR.ADC.SampleRate)]);
                        app.ABR.ADC.SampleRate = app.ABR.DAC.SampleRate ./ app.ABR.adcDecimationFactor;

                        % generate signal based on its parameters
                        app.SIG = app.SIG.update;
                        
                        % copy stimulus to DAC buffer.
                        app.ABR.DAC.Data = app.SIG.data{app.scheduleIdx};
                        
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
                        app.ControlPauseButton.Text = 'Pause ||';
                        app.ControlPauseButton.Tooltip = 'Click to Pause';
                        app.ControlPauseButton.BackgroundColor = [0.96 0.96 0.96];
                        app.AcquisitionStateLamp.Color = [0 1 0];
                        
                        drawnow
                        
                        app.programState = 'ACQUIRE';
                        
                        
                    case 'ACQUIRE'
                        app.AcquisitionStateLabel.Text = 'Acquiring';
                        
                        app.AcquisitionStateLamp.Color = [0 1 0];
                        app.AcquisitionStateLamp.Tooltip = 'Acquiring';
                        
                        try
                            % do it
                            ax = app.live_plot;

                            app.ABR = app.ABR.playrec(app,ax,'showTimingStats',isequal(app.OptionShowTimingStats.Checked,'on'));

                            app.programState = 'REPCOMPLETE';
                                                        
                        catch me
                            app.programState = 'ACQUISITIONEERROR';
                            rethrow(me);
                        end
                        
                        
                        
                    case 'REPCOMPLETE'
                        app.scheduleRunCount(app.scheduleIdx) = app.scheduleRunCount(app.scheduleIdx) + 1;
                        
                        % Add buffer to traces.Organizer
                        params = structfun(@(a) a(app.scheduleIdx),app.SIG.dataParams,'uni',0);
                        app.TrcOrg.addTrace(app.ABR.ADC.SweepMean, ...
                            params, ...
                            app.ABR.ADC.TimeVector(1), ...
                            app.ABR.ADC.SampleRate);
                        
                        % update all trace colors
                        app.TrcOrg.TraceColors = [0.6 0.6 0.6];
                        
                        % update most recent trace color
                        app.TrcOrg.Traces(end).Color = [0 0 0];
                        
                        % Update TraceOrganizer plot
                        app.TrcOrg.plot;
                        
                        
                        % SAVE ABR DATA
                        
                        app.programState = 'REPADVANCE';
                        
                        
                    case 'SCHEDCOMPLETE'
                        app.Schedule.update_highlight([]);
                        app.Schedule.DO_NOT_DELETE = false;
                        app.AcquisitionStateLabel.Text      = 'Finished';
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.AcquisitionStateLamp.Color      = [0.6 0.6 0.6];
                        app.AcquisitionStateLamp.Tooltip    = 'Finished';
                        app.ControlStimInfoLabel.Text       = 'Completed';
                        drawnow
                        
                    case 'USERIDLE'
                        app.Schedule.DO_NOT_DELETE = false;
                        app.AcquisitionStateLabel.Text      = 'Ready';
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];
                        app.AcquisitionStateLamp.Tooltip    = 'Idle';
                        ACQSTATE = 'CANCELLED';
                        drawnow
                        
                        
                    case 'ACQUISITIONEERROR'
                        app.Schedule.update_highlight(app.scheduleIdx,[1 0.2 0.2]);
                        app.Schedule.DO_NOT_DELETE = false;
                        app.AcquisitionStateLabel.Text      = 'ERROR';
                        app.ControlAcquisitionSwitch.Value  = 'Idle';
                        app.AcquisitionStateLamp.Color      = [1 0 0];
                        app.AcquisitionStateLamp.Tooltip    = 'ERROR';
                        ACQSTATE = 'CANCELLED';
                        drawnow
                end
                
            catch stateME
%                 fprintf(2,'Current Program State: "%s"\n',app.programState)
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
                    
                    % reset gui
                    app.AcquisitionStateLabel.Text = 'Cancelled';
                    
                    app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];
                    app.AcquisitionStateLamp.Tooltip = 'User cancelled acquisition';
                    
                    app.ControlPauseButton.Value = 0;
                    app.ControlPauseButton.Text = 'Pause ||';
                    app.ControlPauseButton.BackgroundColor = [0.96 0.96 0.96];
                    app.ControlPauseButton.Tooltip = 'Click to Pause';
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
                hObj.BackgroundColor = [1 1 0];
            end
            
            drawnow
        end
        
        function advance_schedule(~,~)
            global ACQSTATE

            if isequal(ACQSTATE,'IDLE'), return; end
            

            % TO DO: SHOULD BE ABLE TO ADVANCE TO THE NEXT STATE EVEN IF
            % NOT CURRENTLY ACQUIRING.  WHAT TrcOrg DO WITH 'PAUSED' STATE?
            
            % Updating ACQSTATE should be detected by ABR.playrec function
            % and stop the current acqusition, which returns control to the
            % StateMachine
            ACQSTATE = 'REPCOMPLETE';
        end
        
        function repeat_schedule_idx(app,event)
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
            f = figure('name','Live Plot','color','w', ...
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
                lastConfigFile = getpref('ABRControlPanel','configFile',[]);
                if ~isempty(lastConfigFile)
                    app.load_config_file(lastConfigFile);
                end
            end
                        
            app.populate_gui;
            
            app.programState = 'STARTUP';

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
    end
    
    
    methods (Access = private)
        function close_request(app,event)
            global ACQSTATE
            try
                app.Schedule.DO_NOT_DELETE = false;
            end
            
            if ismember(ACQSTATE,{'IDLE','CANCELLED'})
                delete(app);
            else
                uialert(app.ControlPanelUIFigure, ...
                    sprintf('I''m sorry Dave, I''m afraid I can''t do that.\n\nPlease first set acquisition to "Idle".'), ...
                    'Control Panel','Icon','warning','modal',true);
            end
        end
    end
end





