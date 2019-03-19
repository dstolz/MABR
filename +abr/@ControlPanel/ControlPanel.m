classdef ControlPanel < matlab.apps.AppBase
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        ABR         (1,1) abr.ABR
        Subject     (1,1) abr.Subject

        
        configFile   (1,:) char
        scheduleFile (1,:) char
        
        subjectDirectory (1,:) char
    end
    
    
    
    % Properties that correspond to app components
    properties (Access = private)
        ControlPanelUIFigure        matlab.ui.Figure
        FileMenu                       matlab.ui.container.Menu
        LoadConfigurationMenu          matlab.ui.container.Menu
        SaveConfigurationMenu          matlab.ui.container.Menu
        OptionsMenu                    matlab.ui.container.Menu
        StayonTopMenu                  matlab.ui.container.Menu
        AcquisitionFilterDesignMenu    matlab.ui.container.Menu
        TabGroup                       matlab.ui.container.TabGroup
        ConfigTab                      matlab.ui.container.Tab
        ScheduleDropDownLabel          matlab.ui.control.Label
        ConfigScheduleDropDown         matlab.ui.control.DropDown
        ConfigLocateButton             matlab.ui.control.Button
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
        Panel                          matlab.ui.container.Panel
        AdvancementCriteriaDropDownLabel  matlab.ui.control.Label
        SweepAdvancementCriteriaDropDown  matlab.ui.control.DropDown
        SweepsSpinnerLabel             matlab.ui.control.Label
        SweepCountSpinner              matlab.ui.control.Spinner
        SweepRateHzSpinnerLabel        matlab.ui.control.Label
        SweepRateHzSpinner             matlab.ui.control.Spinner
        Panel_2                        matlab.ui.container.Panel
        ControlAdvanceButton           matlab.ui.control.Button
        ControlRepeatButton            matlab.ui.control.StateButton
        ControlPauseButton             matlab.ui.control.StateButton
        ControlAcquireIdleSwitch       matlab.ui.control.ToggleSwitch
        ControlAcquireLamp             matlab.ui.control.Lamp
        UtilitiesTab                   matlab.ui.container.Tab
        UtilityScheduleDesignButton    matlab.ui.control.Button
        UtilitySoundCalibrationButton  matlab.ui.control.Button
        UtilityABRDataViewerButton     matlab.ui.control.Button
        UtilityOnlineAnalysisButton    matlab.ui.control.Button
        
        
        SubjectNode     matlab.ui.container.TreeNode
    end
    
    methods (Access = private)
        
        
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
        
        
        % CONFIG ----------------------------------------------------------
        function load_config_file(app)
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
                'ABR Configuration File',dfltPth);
            
            if isequal(fn,0), return; end

            abrConfig.ABR     = app.ABR;
            abrConfig.Subject = app.Subject;
            
            save(fullfile(pn,fn),'abrConfig','-mat');
            
            fprintf('ABR Configuration file saved: %s\n',fn)
            
            setpref('ABRControlPanel','configPath',pn);
        end
        
        function load_schedule_file(app)
        
            if isempty(app.scheduleFile), return; end
            
            % Load schedule file
            S = load(app.scheduleFile,'-mat','compiled','data','SIG','tblData');
            
            setpref('ABRControlPanel','schedulePath',fileparts(app.scheduleFile));
            
            app.populate_gui;
        end
        
        
        
        
        
        
        % UTILITIES -------------------------------------------------------
        
        function launch_utility(app, utility)
            % Launch Schedule Design utility or locate if already exists
            
            try
                switch utility
                    case 'ScheduleDesign'
                        ScheduleDesign(app.schedDesignFile);
                        
                    otherwise
                        run(utility);
                end
            catch me
                errordlg(sprintf('Unable to launch: %s\n\n%s\n%s',utility,me.identifier,me.message), ...
                    'launch_utility','modal');
            end
        end
        
        
        
        % SUBJECT ---------------------------------------------------------
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
        
    end
    
    methods
        function d = get.subjectDirectory(obj)
            if isfolder(obj.subjectDirectory)
                d = obj.subjectDirectory;
            else
                d = cd;
            end
            
        end
    end
    
    
    
    
    
    methods (Access = public)
        
        % Construct app
        function app = ControlPanel(configFile)
            
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
end





