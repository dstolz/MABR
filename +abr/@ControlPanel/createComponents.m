% App initialization and construction

% Create UIFigure and components
function createComponents(app)

% Create ControlPanelUIFigure
app.ControlPanelUIFigure = uifigure;
app.ControlPanelUIFigure.Position = [50 400 550 275];
app.ControlPanelUIFigure.Name = 'ABR Control Panel';
app.ControlPanelUIFigure.CloseRequestFcn = createCallbackFcn(app, @close_request, true);


%% MENU -------------------------------------------------------------------
% Create FileMenu
app.FileMenu = uimenu(app.ControlPanelUIFigure);
app.FileMenu.Text = 'File';

% Create LoadConfigurationMenu
app.LoadConfigurationMenu = uimenu(app.FileMenu);
app.LoadConfigurationMenu.Text = 'Load Configuration ...';
app.LoadConfigurationMenu.Accelerator = 'l';
app.LoadConfigurationMenu.Callback = createCallbackFcn(app, @load_config_file, false);

% Create SaveConfigurationMenu
app.SaveConfigurationMenu = uimenu(app.FileMenu);
app.SaveConfigurationMenu.Text = 'Save Configuration ...';
app.SaveConfigurationMenu.Accelerator = 's';
app.SaveConfigurationMenu.Callback = createCallbackFcn(app, @save_config_file, false);

% Create OptionsMenu
app.OptionsMenu = uimenu(app.ControlPanelUIFigure);
app.OptionsMenu.Text = 'Options';

% Create StayonTopMenu
app.StayonTopMenu = uimenu(app.OptionsMenu);
app.StayonTopMenu.Text = 'Stay on Top';
app.StayonTopMenu.Separator = 'on';
app.StayonTopMenu.Checked = 'off';
app.StayonTopMenu.MenuSelectedFcn = createCallbackFcn(app, @always_on_top,false);

% % Create OptionShowTimingStats
% app.OptionShowTimingStats = uimenu(app.OptionsMenu);
% app.OptionShowTimingStats.Text = 'Show Timing Stats';
% app.OptionShowTimingStats.Separator = 'on';
% app.OptionShowTimingStats.Checked = 'off';
% app.OptionShowTimingStats.MenuSelectedFcn = createCallbackFcn(app, @menu_option_processor,true);

% Create ASIOSettingsMenu
app.ASIOSettingsMenu = uimenu(app.OptionsMenu);
app.ASIOSettingsMenu.Text = 'ASIO Settings';
app.ASIOSettingsMenu.Tooltip = 'Launches Sound Card ASIO Settings';
app.ASIOSettingsMenu.Separator = 'on';
app.ASIOSettingsMenu.MenuSelectedFcn = createCallbackFcn(app, @launch_asiosettings, false);

% Create SelectAudioDeviceMenu 
app.SelectAudioDeviceMenu = uimenu(app.OptionsMenu);
app.SelectAudioDeviceMenu.Text = 'Select Audio Device';
app.SelectAudioDeviceMenu.Tooltip = 'Select Audio Device';
app.SelectAudioDeviceMenu.MenuSelectedFcn = createCallbackFcn(app, @select_audiodevice, false);

% Create SetupAudioChannelsMenu
app.SetupAudioChannelsMenu = uimenu(app.OptionsMenu);
app.SetupAudioChannelsMenu.Text = 'Setup Audio Channels';
app.SetupAudioChannelsMenu.Tooltip = 'Setup Stimulus, Acquisition, and Loop-Back channels';
app.SetupAudioChannelsMenu.MenuSelectedFcn = createCallbackFcn(app, @setup_audiochannels, false);

%% Create TabGroup --------------------------------------------------------
app.TabGroup = uitabgroup(app.ControlPanelUIFigure);
app.TabGroup.SelectionChangedFcn = createCallbackFcn(app, @TabGroupSelectionChanged, true);
app.TabGroup.Position = [1 1 550 273];
app.TabGroup.TabLocation = 'left';


%% NON-TAB COMPONENTS -----------------------------------------------------

% Create AcquisitionStateLamp
app.AcquisitionStateLamp = uilamp(app.ControlPanelUIFigure);
app.AcquisitionStateLamp.Position = [530 250 20 20];
app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];

p = app.AcquisitionStateLamp.Position;

% Create AcquisitionStateLabel
app.AcquisitionStateLabel = uilabel(app.ControlPanelUIFigure);
app.AcquisitionStateLabel.HorizontalAlignment = 'right';
app.AcquisitionStateLabel.Position = [p(1)-102 p(2) 100 22];
app.AcquisitionStateLabel.FontSize = 14;
app.AcquisitionStateLabel.FontWeight = 'bold';
app.AcquisitionStateLabel.Text = 'Ready';

app.HelpButton = uibutton(app.ControlPanelUIFigure, 'push');
app.HelpButton.Icon = 'helpicon.gif';
app.HelpButton.IconAlignment = 'center';
app.HelpButton.Position = [100 250 20 20];
app.HelpButton.Text = '';

%% CONFIG TAB -------------------------------------------------------------
% Create ConfigTab
app.ConfigTab = uitab(app.TabGroup);
app.ConfigTab.Title = 'Configure';

nRows = 9; nCols = 6;
G = uigridlayout(app.ConfigTab,[nRows nCols]);
G.RowHeight = [{22} repmat({'1x'},1,nRows-1)];
G.ColumnWidth = {80 '1x' '1x' '1x' 60 60}; 
    
% Skip first row to provide some space
R = 2;

% Create ConfigFileLabel
app.ConfigFileLabel = uilabel(G);
app.ConfigFileLabel.HorizontalAlignment = 'right';
app.ConfigFileLabel.FontSize = 14;
app.ConfigFileLabel.Layout.Row = R;
app.ConfigFileLabel.Layout.Column = 1;
app.ConfigFileLabel.Text = 'Config';

% Create ConfigFileDD
app.ConfigFileDD = uidropdown(G);
app.ConfigFileDD.Items = {'ConfigFile.cfg'};
app.ConfigFileDD.Editable = 'off';
app.ConfigFileDD.FontSize = 14;
app.ConfigFileDD.BackgroundColor = [1 1 1];
app.ConfigFileDD.Layout.Row = R;
app.ConfigFileDD.Layout.Column = [2 4];
app.ConfigFileDD.Value = 'ConfigFile.cfg';
app.ConfigFileDD.Tooltip = 'Select a configuration file';
app.ConfigFileDD.ValueChangedFcn = createCallbackFcn(app, @load_config_file,true);


% Create ConfigFileSave
app.ConfigFileSave = uibutton(G, 'push');
app.ConfigFileSave.FontSize = 14;
app.ConfigFileSave.Layout.Row = R;
app.ConfigFileSave.Layout.Column = 5;
app.ConfigFileSave.Icon = fullfile(app.iconPath,'file_save.png');
app.ConfigFileSave.Text = 'save';
app.ConfigFileSave.VerticalAlignment = 'top';
app.ConfigFileSave.ButtonPushedFcn = createCallbackFcn(app, @save_config_file, false);

% Create ConfigFileLoad
app.ConfigFileLoad = uibutton(G, 'push');
app.ConfigFileLoad.FontSize = 14;
app.ConfigFileLoad.Layout.Row = R;
app.ConfigFileLoad.Layout.Column = 6;
app.ConfigFileLoad.Icon = fullfile(app.iconPath,'file_open.png');
app.ConfigFileLoad.Text = 'load';
app.ConfigFileLoad.VerticalAlignment = 'top';
app.ConfigFileLoad.ButtonPushedFcn = createCallbackFcn(app, @load_config_file, false);


R = R + 1;
% Create ScheduleDDLabel
app.ScheduleDDLabel = uilabel(G);
app.ScheduleDDLabel.HorizontalAlignment = 'right';
app.ScheduleDDLabel.FontSize = 14;
app.ScheduleDDLabel.Layout.Row = R;
app.ScheduleDDLabel.Layout.Column = 1;
app.ScheduleDDLabel.Text = 'Schedule';

% Create ConfigScheduleDD
app.ConfigScheduleDD = uidropdown(G);
app.ConfigScheduleDD.Items = {''};
app.ConfigScheduleDD.Editable = 'off';
app.ConfigScheduleDD.FontSize = 14;
app.ConfigScheduleDD.BackgroundColor = [1 1 1];
app.ConfigScheduleDD.Layout.Row = R;
app.ConfigScheduleDD.Layout.Column = [2 4];
app.ConfigScheduleDD.Value = '';
app.ConfigScheduleDD.ValueChangedFcn = createCallbackFcn(app, @load_schedule_file,true);

% Create ConfigLoadSchedButton
app.ConfigLoadSchedButton = uibutton(G, 'push');
app.ConfigLoadSchedButton.FontSize = 14;
app.ConfigLoadSchedButton.Layout.Row = R;
app.ConfigLoadSchedButton.Layout.Column = 6;
app.ConfigLoadSchedButton.Text = 'load';
app.ConfigLoadSchedButton.Icon = fullfile(app.iconPath,'file_open.png');
app.ConfigLoadSchedButton.VerticalAlignment = 'top';
app.ConfigLoadSchedButton.ButtonPushedFcn = createCallbackFcn(app, @locate_schedule_file,false);

% Create ConfigNewSchedButton
app.ConfigNewSchedButton = uibutton(G, 'push');
app.ConfigNewSchedButton.FontSize = 14;
app.ConfigNewSchedButton.Layout.Row = R;
app.ConfigNewSchedButton.Layout.Column = 5;
app.ConfigNewSchedButton.Text = 'new';
app.ConfigNewSchedButton.Icon = fullfile(app.iconPath,'file_new.png');
app.ConfigNewSchedButton.VerticalAlignment = 'top';
app.ConfigNewSchedButton.UserData = 'ScheduleDesign';
app.ConfigNewSchedButton.ButtonPushedFcn = createCallbackFcn(app, @locate_utility, true);

R = R + 1;

% Create CalibrationDDLabel
app.CalibrationDDLabel = uilabel(G);
app.CalibrationDDLabel.HorizontalAlignment = 'right';
app.CalibrationDDLabel.FontSize = 14;
app.CalibrationDDLabel.Layout.Row = R;
app.CalibrationDDLabel.Layout.Column = 1;
app.CalibrationDDLabel.Text = 'Calibration';

% Create CalibrationDD
app.CalibrationDD = uidropdown(G);
app.CalibrationDD.Items = {''};
app.CalibrationDD.Editable = 'off';
app.CalibrationDD.FontSize = 14;
app.CalibrationDD.BackgroundColor = [1 1 1];
app.CalibrationDD.Layout.Row = R;
app.CalibrationDD.Layout.Column = [2 4];
app.CalibrationDD.Value = '';
app.CalibrationDD.Tooltip = 'Select a calibration file';
app.CalibrationDD.ValueChangedFcn = createCallbackFcn(app, @load_calibration_file,true);

% Create CalibrationLoad
app.CalibrationLoad = uibutton(G, 'push');
app.CalibrationLoad.FontSize = 14;
app.CalibrationLoad.Layout.Row = R;
app.CalibrationLoad.Layout.Column = 6;
app.CalibrationLoad.Text = 'load';
app.CalibrationLoad.Icon = fullfile(app.iconPath,'file_open.png');
app.CalibrationLoad.VerticalAlignment = 'top';
app.CalibrationLoad.ButtonPushedFcn = createCallbackFcn(app, @locate_calibration_file, false);

% Create CalibrationNew
app.CalibrationNew = uibutton(G, 'push');
app.CalibrationNew.FontSize = 14;
app.CalibrationNew.Layout.Row = R;
app.CalibrationNew.Layout.Column = 5;
app.CalibrationNew.Text = 'new';
app.CalibrationNew.Icon = fullfile(app.iconPath,'file_new.png');
app.CalibrationNew.VerticalAlignment = 'top';
app.CalibrationNew.ButtonPushedFcn = createCallbackFcn(app, @abr.Calibration, false);

R = R + 2; % allow some extra space

app.OutputPanel = uipanel('Parent',G,'Title','ABR Data Output');
app.OutputPanel.Layout.Row = [R R+3];
app.OutputPanel.Layout.Column = [1 nCols];

nRows = 2; nCols = 3;
G = uigridlayout(app.OutputPanel,[nRows nCols]);
G.RowHeight = repmat({24},1,nRows);
G.ColumnWidth = {80 '1x' 60};
    
R = 1;

% Create OutputFileLabel
app.OutputFileLabel = uilabel(G);
app.OutputFileLabel.HorizontalAlignment = 'right';
app.OutputFileLabel.FontSize = 14;
app.OutputFileLabel.Text = 'Filename';
app.OutputFileLabel.Layout.Row = R;
app.OutputFileLabel.Layout.Column = 1;

% Create OutputFileDD
app.OutputFileDD = uidropdown(G);
app.OutputFileDD.Editable = 'on';
app.OutputFileDD.FontSize = 14;
app.OutputFileDD.BackgroundColor = [1 1 1];
app.OutputFileDD.Items = {''};
app.OutputFileDD.Value = '';
app.OutputFileDD.Tooltip = 'Select an output file or create a new one by editing the name.';
app.OutputFileDD.ValueChangedFcn = createCallbackFcn(app, @output_file_changed,true);
app.OutputFileDD.Layout.Row = R;
app.OutputFileDD.Layout.Column = 2;

R = R + 1;

% Create OutputPathLabel
app.OutputPathLabel = uilabel(G);
app.OutputPathLabel.HorizontalAlignment = 'right';
app.OutputPathLabel.FontSize = 14;
app.OutputPathLabel.Text = 'Directory';
app.OutputPathLabel.Layout.Row = R;
app.OutputPathLabel.Layout.Column = 1;


% Create OutputPathDD
recentPaths = getpref('ABRControlPanel','outputFolder',{app.root}); % set with recent directories
ind = isfolder(recentPaths);
recentPaths(~ind) = [];
app.OutputPathDD = uidropdown(G);
app.OutputPathDD.Editable = 'off';
app.OutputPathDD.FontSize = 14;
app.OutputPathDD.BackgroundColor = [1 1 1];
app.OutputPathDD.Items = app.truncate_str(recentPaths,40);
app.OutputPathDD.ItemsData = recentPaths;
app.OutputPathDD.Value = recentPaths{1};
app.OutputPathDD.ValueChangedFcn = createCallbackFcn(app, @output_path_changed,true);
app.OutputPathDD.Layout.Row = R;
app.OutputPathDD.Layout.Column = 2;

% Create OutputPathSelectButton
app.OutputPathSelectButton = uibutton(G, 'push');
app.OutputPathSelectButton.FontSize = 14;
app.OutputPathSelectButton.Text = 'dir';
app.OutputPathSelectButton.Tooltip = 'Locate a data output directory';
app.OutputPathSelectButton.ButtonPushedFcn = createCallbackFcn(app, @output_select_directory, false);
app.OutputPathSelectButton.Layout.Row = R;
app.OutputPathSelectButton.Layout.Column = nCols;

e.Value = app.OutputFileDD.Value;
e.Source = app.OutputFileDD;
app.output_path_changed(e);







%% SUBJECT TAB -------------------------------------------------------------
% % Create SubjectInfoTab
% app.SubjectInfoTab = uitab(app.TabGroup);
% app.SubjectInfoTab.Title = 'Subject Info';
% 
% 
% nRows = 8; nCols = 4;
% G = uigridlayout(app.SubjectInfoTab,[nRows nCols]);
% G.RowHeight = repmat({'1x'},1,nRows);
% G.ColumnWidth = {'1x' 35 '1x' 60}; 
%     % Create SubjectTree
% app.SubjectTree = uitree(G);
% app.SubjectTree.Layout.Row = [2 nRows-1];
% app.SubjectTree.Layout.Column  = 1;
% 
% % Create SubjectAddaSubjectButton
% app.SubjectAddaSubjectButton = uibutton(G, 'push');
% app.SubjectAddaSubjectButton.FontSize = 10;
% app.SubjectAddaSubjectButton.Layout.Row = nRows;
% app.SubjectAddaSubjectButton.Layout.Column = 1;
% app.SubjectAddaSubjectButton.Text = 'Add a Subject';
% app.SubjectAddaSubjectButton.ButtonPushedFcn = createCallbackFcn(app, @add_subject,false);
% 
% 
% R = 2;
% % Create UserDDLabel
% app.UserDDLabel = uilabel(G);
% app.UserDDLabel.HorizontalAlignment = 'right';
% app.UserDDLabel.Layout.Row = R;
% app.UserDDLabel.Layout.Column = 2;
% app.UserDDLabel.Text = 'User';
% app.UserDDLabel.Tooltip = 'Select or enter initials';
% 
% % Create SubjectUserDD
% app.SubjectUserDD = uidropdown(G);
% app.SubjectUserDD.Editable = 'on';
% app.SubjectUserDD.Layout.Row = R;
% app.SubjectUserDD.Layout.Column = 3;
% 
% R = R + 1;
% % Create AliasEditFieldLabel
% app.AliasEditFieldLabel = uilabel(G);
% app.AliasEditFieldLabel.HorizontalAlignment = 'right';
% app.AliasEditFieldLabel.Layout.Row = R;
% app.AliasEditFieldLabel.Layout.Column = 2;
% app.AliasEditFieldLabel.Text = 'Alias';
% 
% % Create AliasEditField
% app.AliasEditField = uieditfield(G, 'text');
% app.AliasEditField.Layout.Row = R;
% app.AliasEditField.Layout.Column = 3;
% 
% R = R + 1;
% % Create IDEditFieldLabel
% app.IDEditFieldLabel = uilabel(G);
% app.IDEditFieldLabel.HorizontalAlignment = 'right';
% app.IDEditFieldLabel.Layout.Row = R;
% app.IDEditFieldLabel.Layout.Column = 2;
% app.IDEditFieldLabel.Text = 'ID';
% 
% % Create SubjectIDEditField
% app.SubjectIDEditField = uieditfield(G, 'text');
% app.SubjectIDEditField.Layout.Row = R;
% app.SubjectIDEditField.Layout.Column = 3;
% 
% R = R + 1;
% % Create DOBDatePickerLabel
% app.DOBDatePickerLabel = uilabel(G);
% app.DOBDatePickerLabel.HorizontalAlignment = 'right';
% app.DOBDatePickerLabel.Layout.Row = R;
% app.DOBDatePickerLabel.Layout.Column = 2;
% app.DOBDatePickerLabel.Text = 'DOB';
% 
% % Create SubjectDOBDatePicker
% app.SubjectDOBDatePicker = uidatepicker(G);
% app.SubjectDOBDatePicker.Layout.Row = R;
% app.SubjectDOBDatePicker.Layout.Column = 3;
% 
% 
% % Create SubjectSexSwitch
% app.SubjectSexSwitch = uiswitch(G, 'slider');
% app.SubjectSexSwitch.Items = {'Female', 'Male'};
% app.SubjectSexSwitch.Orientation = 'vertical';
% app.SubjectSexSwitch.Tooltip = {'Select subject sex'};
% app.SubjectSexSwitch.Layout.Row = [2 4];
% app.SubjectSexSwitch.Layout.Column = 4;
% app.SubjectSexSwitch.Value = 'Female';
% 
% 
% R = R + 1;
% % Create NotesTextAreaLabel
% app.NotesTextAreaLabel = uilabel(G);
% app.NotesTextAreaLabel.HorizontalAlignment = 'right';
% app.NotesTextAreaLabel.Layout.Row = R;
% app.NotesTextAreaLabel.Layout.Column = 2;
% app.NotesTextAreaLabel.Text = 'Notes';
% 
% % Create SubjectNotesTextArea
% app.SubjectNotesTextArea = uitextarea(G);
% app.SubjectNotesTextArea.Layout.Row = [R nRows];
% app.SubjectNotesTextArea.Layout.Column = [3 nCols];
% 





%% CONTROL TAB ------------------------------------------------------------
% Create ControlTab
app.ControlTab = uitab(app.TabGroup);
app.ControlTab.Title = 'Control';

nRows = 8; nCols = 4;
G = uigridlayout(app.ControlTab,[nRows nCols]);
G.RowHeight = [repmat({'1x'},1,nRows-1) 40];
G.ColumnWidth = {120 100 '1x' 180}; 
    
R = 2;

% Create SweepsSpinnerLabel
app.SweepsSpinnerLabel = uilabel(G);
app.SweepsSpinnerLabel.HorizontalAlignment = 'right';
app.SweepsSpinnerLabel.Layout.Row = R;
app.SweepsSpinnerLabel.Layout.Column = 1;
app.SweepsSpinnerLabel.Text = '# Sweeps';
app.SweepsSpinnerLabel.Tooltip = 'Number of sweeps, i.e. stimulus presentations, per schedule row.';

% Create SweepCountSpinner
app.SweepCountSpinner = uispinner(G);
app.SweepCountSpinner.Limits = [1 inf];
app.SweepCountSpinner.RoundFractionalValues = 'on';
app.SweepCountSpinner.ValueDisplayFormat = '%d';
app.SweepCountSpinner.HorizontalAlignment = 'center';
app.SweepCountSpinner.Layout.Row = R;
app.SweepCountSpinner.Layout.Column = 2;
app.SweepCountSpinner.Value = 128;
app.SweepCountSpinner.ValueChangedFcn = createCallbackFcn(app, @update_sweep_count, true);
app.SweepCountSpinner.CreateFcn = createCallbackFcn(app, @update_sweep_count, true);

R = R + 1;
% Create SweepRateHzSpinnerLabel
app.SweepRateHzSpinnerLabel = uilabel(G);
app.SweepRateHzSpinnerLabel.HorizontalAlignment = 'right';
app.SweepRateHzSpinnerLabel.Layout.Row = R;
app.SweepRateHzSpinnerLabel.Layout.Column = 1;
app.SweepRateHzSpinnerLabel.Text = 'Sweep Rate (Hz)';
app.SweepRateHzSpinnerLabel.Tooltip = 'Stimulus presentation rate in Hz';

% Create SweepRateHzSpinner
app.SweepRateHzSpinner = uispinner(G);
app.SweepRateHzSpinner.Limits = [0.001 100];
app.SweepRateHzSpinner.HorizontalAlignment = 'center';
app.SweepRateHzSpinner.Layout.Row = R;
app.SweepRateHzSpinner.Layout.Column = 2;
app.SweepRateHzSpinner.Value = 21.1;

R = R + 1;
% Create RepetitionsLabel
app.NumRepetitionsLabel = uilabel(G);
app.NumRepetitionsLabel.HorizontalAlignment = 'right';
app.NumRepetitionsLabel.Layout.Row = R;
app.NumRepetitionsLabel.Layout.Column = 1;
app.NumRepetitionsLabel.Text = '# Repetitions';
app.NumRepetitionsLabel.Tooltip = 'Number of repetitions per schedule row';

% Create NumRepetitionsSpinner
app.NumRepetitionsSpinner = uispinner(G);
app.NumRepetitionsSpinner.Limits = [1 Inf];
app.NumRepetitionsSpinner.RoundFractionalValues = 'on';
app.NumRepetitionsSpinner.ValueDisplayFormat = '%d';
app.NumRepetitionsSpinner.HorizontalAlignment = 'center';
app.NumRepetitionsSpinner.Layout.Row = R;
app.NumRepetitionsSpinner.Layout.Column = 2;
app.NumRepetitionsSpinner.Value = 1;

R = R + 1;
% Create SweepDurationLabel
app.SweepDurationLabel = uilabel(G);
app.SweepDurationLabel.HorizontalAlignment = 'right';
app.SweepDurationLabel.Layout.Row = R;
app.SweepDurationLabel.Layout.Column = 1;
app.SweepDurationLabel.Text = 'Sweep Duration (ms)';
app.SweepDurationLabel.Tooltip = 'ABR acquisition duration in milliseconds';

% Create SweepDurationSpinner
app.SweepDurationSpinner = uispinner(G);
app.SweepDurationSpinner.Limits = [0.1 1000];
app.SweepDurationSpinner.HorizontalAlignment = 'center';
app.SweepDurationSpinner.Layout.Row = R;
app.SweepDurationSpinner.Layout.Column = 2;
app.SweepDurationSpinner.Value = 10;

R = R + 1;
% Create ControlAdvCriteriaDDLabel
app.ControlAdvCriteriaDDLabel = uilabel(G);
app.ControlAdvCriteriaDDLabel.HorizontalAlignment = 'right';
app.ControlAdvCriteriaDDLabel.Layout.Row = R;
app.ControlAdvCriteriaDDLabel.Layout.Column = 1;
app.ControlAdvCriteriaDDLabel.Text = 'Advance on...';
app.ControlAdvCriteriaDDLabel.Tooltip = 'Criterion function used to advance to the next schedule row';

% Create ControlAdvCriteriaDD
app.ControlAdvCriteriaDD = uidropdown(G);
app.ControlAdvCriteriaDD.Items = {'# Sweeps', 'Correlation Threshold', '< Define >'};
app.ControlAdvCriteriaDD.Layout.Row = R;
app.ControlAdvCriteriaDD.Layout.Column = 2;
app.ControlAdvCriteriaDD.Value = '# Sweeps';

% Create Panel_2
app.Panel_2 = uipanel(G);
app.Panel_2.Layout.Row = [2 6];
app.Panel_2.Layout.Column = 4;



nRows = 3; nCols = 2;
Gpanel = uigridlayout(app.Panel_2,[nRows nCols]);
Gpanel.RowHeight = repmat({'1x'},1,nRows);
Gpanel.ColumnWidth = {'1x' '1x'}; 
    
R = 1;
% Create ControlAdvanceButton
app.ControlAdvanceButton = uibutton(Gpanel, 'push');
app.ControlAdvanceButton.Layout.Row = R;
app.ControlAdvanceButton.Layout.Column = 1;
app.ControlAdvanceButton.Text = 'Advance';
app.ControlAdvanceButton.Icon = fullfile(app.iconPath,'advance.gif');
app.ControlAdvanceButton.IconAlignment = 'right';
app.ControlAdvanceButton.ButtonPushedFcn = createCallbackFcn(app, @advance_schedule,false);

R = R + 1;
% Create ControlRepeatButton
app.ControlRepeatButton = uibutton(Gpanel, 'state');
app.ControlRepeatButton.Text = 'Repeat';
app.ControlRepeatButton.Layout.Row = R;
app.ControlRepeatButton.Layout.Column = 1;
app.ControlRepeatButton.Icon = fullfile(app.iconPath,'repeat.gif');
app.ControlRepeatButton.IconAlignment = 'right';
app.ControlRepeatButton.ValueChangedFcn = createCallbackFcn(app, @repeat_schedule_idx,true);


R = R + 1;
% Create ControlPauseButton
app.ControlPauseButton = uibutton(Gpanel, 'state');
app.ControlPauseButton.Text = 'Pause';
app.ControlPauseButton.Layout.Row = R;
app.ControlPauseButton.Layout.Column = 1;
app.ControlPauseButton.Icon = fullfile(app.iconPath,'pause.gif');
app.ControlPauseButton.IconAlignment = 'right';
app.ControlPauseButton.ValueChangedFcn = createCallbackFcn(app, @pause_button,false);


% Create ControlAcquisitionSwitch
app.ControlAcquisitionSwitch = uiswitch(Gpanel, 'toggle');
app.ControlAcquisitionSwitch.Items = {'Idle', 'Acquire'};
app.ControlAcquisitionSwitch.FontSize = 16;
app.ControlAcquisitionSwitch.Layout.Row = [1 3];
app.ControlAcquisitionSwitch.Layout.Column = 2;
app.ControlAcquisitionSwitch.Value = 'Idle';
app.ControlAcquisitionSwitch.ValueChangedFcn = createCallbackFcn(app, @control_acq_switch, true);


%%%%%
% Create ControlStimInfoLabel
app.ControlStimInfoLabel = uilabel(G);
app.ControlStimInfoLabel.Layout.Row = length(G.RowHeight)-1;
app.ControlStimInfoLabel.Layout.Column = [1 length(G.ColumnWidth)];
app.ControlStimInfoLabel.HorizontalAlignment = 'center';
app.ControlStimInfoLabel.VerticalAlignment = 'bottom';
app.ControlStimInfoLabel.FontSize = 14;
app.ControlStimInfoLabel.Text = '';

% Create ControlSweepCountGauge
app.ControlSweepCountGauge = uigauge(G, 'linear');
app.ControlSweepCountGauge.Layout.Row = length(G.RowHeight);
app.ControlSweepCountGauge.Layout.Column = [1 length(G.ColumnWidth)];
app.ControlSweepCountGauge.Limits = [1 128];

%% FILTER TAB -------------------------------------------------------------
app.AcqFilterTab = uitab(app.TabGroup);
app.AcqFilterTab.Title = 'Acq Filter';

% Create Panel_3
app.Panel_3 = uipanel(app.AcqFilterTab);
app.Panel_3.Position = [10 22 430 213];

% Create FilterHPFcEditFieldLabel
app.FilterHPFcEditFieldLabel = uilabel(app.Panel_3);
app.FilterHPFcEditFieldLabel.HorizontalAlignment = 'right';
app.FilterHPFcEditFieldLabel.FontSize = 14;
app.FilterHPFcEditFieldLabel.Position = [11 163 218 22];
app.FilterHPFcEditFieldLabel.Text = 'High-Pass Frequency Corner (Hz)';

% Create FilterHPFcEditField
app.FilterHPFcEditField = uieditfield(app.Panel_3, 'numeric');
app.FilterHPFcEditField.Limits = [0.5 100];
app.FilterHPFcEditField.FontSize = 16;
app.FilterHPFcEditField.Position = [248 163 65 22];
app.FilterHPFcEditField.Value = 10;

% Create FilterLPFcEditFieldLabel
app.FilterLPFcEditFieldLabel = uilabel(app.Panel_3);
app.FilterLPFcEditFieldLabel.HorizontalAlignment = 'right';
app.FilterLPFcEditFieldLabel.FontSize = 14;
app.FilterLPFcEditFieldLabel.Position = [14 128 215 22];
app.FilterLPFcEditFieldLabel.Text = 'Low-Pass Frequency Corner (Hz)';

% Create FilterLPFcEditField
app.FilterLPFcEditField = uieditfield(app.Panel_3, 'numeric');
app.FilterLPFcEditField.Limits = [100 20000];
app.FilterLPFcEditField.FontSize = 16;
app.FilterLPFcEditField.Position = [248 128 65 22];
app.FilterLPFcEditField.Value = 3000;

% Create FilterEnableSwitch
app.FilterEnableSwitch = uiswitch(app.Panel_3, 'rocker');
app.FilterEnableSwitch.Items = {'Disabled', 'Enabled'};
app.FilterEnableSwitch.Position = [348 145 16 36];
app.FilterEnableSwitch.Value = 'Enabled';
app.FilterEnableSwitch.ValueChangedFcn = createCallbackFcn(app, @filter_enable_switch, true);

% Create FilterEnabledLamp
app.FilterEnabledLamp = uilamp(app.Panel_3);
app.FilterEnabledLamp.Position = [171 194 10 10];

% Create FilterNotchFilterKnob
app.FilterNotchFilterKnob = uiknob(app.Panel_3, 'discrete');
app.FilterNotchFilterKnob.Items = {'Disabled', '50 Hz', '60 Hz'};
app.FilterNotchFilterKnob.ItemsData = {0,50,60};
app.FilterNotchFilterKnob.FontSize = 14;
app.FilterNotchFilterKnob.Position = [186 21 54 54];
app.FilterNotchFilterKnob.Value = 60;
app.FilterNotchFilterKnob.ValueChangedFcn = createCallbackFcn(app, @notch_filter_select, true);

% Create FilterNotchEnabledLamp
app.FilterNotchEnabledLamp = uilamp(app.Panel_3);
app.FilterNotchEnabledLamp.Position = [144 80 10 10];

% Create FilterBandpassFilterLabel
app.FilterBandpassFilterLabel = uilabel(app.Panel_3);
app.FilterBandpassFilterLabel.FontSize = 14;
app.FilterBandpassFilterLabel.FontWeight = 'bold';
app.FilterBandpassFilterLabel.Position = [14 189 157 22];
app.FilterBandpassFilterLabel.Text = 'Digital Bandpass Filter';

% Create FilterNotchFilterLabel
app.FilterNotchFilterLabel = uilabel(app.Panel_3);
app.FilterNotchFilterLabel.FontSize = 14;
app.FilterNotchFilterLabel.FontWeight = 'bold';
app.FilterNotchFilterLabel.Position = [14 74 130 22];
app.FilterNotchFilterLabel.Text = 'Digital Notch Filter';



%% UTILITIES TAB ----------------------------------------------------------
% Create UtilitiesTab
app.UtilitiesTab = uitab(app.TabGroup);
app.UtilitiesTab.Title = 'Utilities';


nRows = 5; nCols = 3;
G = uigridlayout(app.UtilitiesTab,[nRows nCols]);
G.RowHeight = repmat({'1x'},1,nRows);
G.ColumnWidth = repmat({'1x'},1,nCols);
    
R = 2;

% Create UtilityScheduleDesignButton
app.UtilityScheduleDesignButton = uibutton(G, 'push');
app.UtilityScheduleDesignButton.Layout.Row = R;
app.UtilityScheduleDesignButton.Layout.Column = 1;
app.UtilityScheduleDesignButton.Text = 'Schedule Design';
app.UtilityScheduleDesignButton.ButtonPushedFcn = createCallbackFcn(app,@abr.ScheduleDesign,false);

R = R + 1;
% Create UtilitySoundCalibrationButton
app.UtilitySoundCalibrationButton = uibutton(G, 'push');
app.UtilitySoundCalibrationButton.Layout.Row = R;
app.UtilitySoundCalibrationButton.Layout.Column = 1;
app.UtilitySoundCalibrationButton.Text = 'Sound Calibration';
app.UtilitySoundCalibrationButton.ButtonPushedFcn = createCallbackFcn(app,@abr.Calibration,false);

R = R + 1;
% Create UtilityABRDataViewerButton
app.UtilityABRDataViewerButton = uibutton(G, 'push');
app.UtilityABRDataViewerButton.Layout.Row = R;
app.UtilityABRDataViewerButton.Layout.Column = 1;
app.UtilityABRDataViewerButton.Text = 'ABR Trace Organizer';
app.UtilityABRDataViewerButton.ButtonPushedFcn = createCallbackFcn(app,@abr.traces.Organizer,false);

R = R + 1;
% Create UtilityOnlineAnalysisButton
app.UtilityOnlineAnalysisButton = uibutton(G, 'push');
app.UtilityOnlineAnalysisButton.Layout.Row = R;
app.UtilityOnlineAnalysisButton.Layout.Column = 1;
app.UtilityOnlineAnalysisButton.Text = 'Online Analysis';


