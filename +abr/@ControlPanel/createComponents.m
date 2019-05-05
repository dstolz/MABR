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




%% Create TabGroup --------------------------------------------------------
app.TabGroup = uitabgroup(app.ControlPanelUIFigure);
app.TabGroup.SelectionChangedFcn = createCallbackFcn(app, @TabGroupSelectionChanged, true);
app.TabGroup.Position = [1 1 550 273];
app.TabGroup.TabLocation = 'left';



%% CONFIG TAB -------------------------------------------------------------
% Create ConfigTab
app.ConfigTab = uitab(app.TabGroup);
app.ConfigTab.Title = 'Config';

y = 210; yspacing = 30;
x = 5; labelWidth = 80;
ddl = 210;
ddx = 107;
abx = 330;
bbx = 395;

% Create ConfigFileSave
app.ConfigFileSave = uibutton(app.ConfigTab, 'push');
app.ConfigFileSave.FontSize = 14;
app.ConfigFileSave.Position = [abx y 60 24];
app.ConfigFileSave.Text = 'save';
app.ConfigFileSave.ButtonPushedFcn = createCallbackFcn(app, @save_config_file, false);

% Create ConfigFileLoad
app.ConfigFileLoad = uibutton(app.ConfigTab, 'push');
app.ConfigFileLoad.FontSize = 14;
app.ConfigFileLoad.Position = [bbx y 60 24];
app.ConfigFileLoad.Text = 'load';
app.ConfigFileLoad.ButtonPushedFcn = createCallbackFcn(app, @load_config_file, false);

% Create ConfigFileLabel
app.ConfigFileLabel = uilabel(app.ConfigTab);
app.ConfigFileLabel.HorizontalAlignment = 'right';
app.ConfigFileLabel.FontSize = 14;
app.ConfigFileLabel.Position = [x y labelWidth 22];
app.ConfigFileLabel.Text = 'Config';

% Create ConfigFileDropDown
app.ConfigFileDropDown = uidropdown(app.ConfigTab);
app.ConfigFileDropDown.Items = {'ConfigFile.cfg'};
app.ConfigFileDropDown.Editable = 'off';
app.ConfigFileDropDown.FontSize = 14;
app.ConfigFileDropDown.BackgroundColor = [1 1 1];
app.ConfigFileDropDown.Position = [ddx y ddl 22];
app.ConfigFileDropDown.Value = 'ConfigFile.cfg';
app.ConfigFileDropDown.Tooltip = 'Select a configuration file';
app.ConfigFileDropDown.ValueChangedFcn = createCallbackFcn(app, @load_config_file,true);


y = y-yspacing;

% Create ScheduleDropDownLabel
app.ScheduleDropDownLabel = uilabel(app.ConfigTab);
app.ScheduleDropDownLabel.HorizontalAlignment = 'right';
app.ScheduleDropDownLabel.FontSize = 14;
app.ScheduleDropDownLabel.Position = [x y labelWidth 22];
app.ScheduleDropDownLabel.Text = 'Schedule';

% Create ConfigScheduleDropDown
app.ConfigScheduleDropDown = uidropdown(app.ConfigTab);
app.ConfigScheduleDropDown.Items = {''};
app.ConfigScheduleDropDown.Editable = 'off';
app.ConfigScheduleDropDown.FontSize = 14;
app.ConfigScheduleDropDown.BackgroundColor = [1 1 1];
app.ConfigScheduleDropDown.Position = [ddx y ddl 22];
app.ConfigScheduleDropDown.Value = '';
app.ConfigScheduleDropDown.ValueChangedFcn = createCallbackFcn(app, @load_schedule_file,true);

% Create ConfigLoadSchedButton
app.ConfigLoadSchedButton = uibutton(app.ConfigTab, 'push');
app.ConfigLoadSchedButton.FontSize = 14;
app.ConfigLoadSchedButton.Position = [bbx y 60 24];
app.ConfigLoadSchedButton.Text = 'load';
app.ConfigLoadSchedButton.ButtonPushedFcn = createCallbackFcn(app, @locate_schedule_file,false);

% Create ConfigNewSchedButton
app.ConfigNewSchedButton = uibutton(app.ConfigTab, 'push');
app.ConfigNewSchedButton.FontSize = 14;
app.ConfigNewSchedButton.Position = [abx y 60 24];
app.ConfigNewSchedButton.Text = 'new';
app.ConfigNewSchedButton.UserData = 'ScheduleDesign';
app.ConfigNewSchedButton.ButtonPushedFcn = createCallbackFcn(app, @locate_utility, true);


y = y - yspacing;

% Create CalibrationNew
app.CalibrationNew = uibutton(app.ConfigTab, 'push');
app.CalibrationNew.FontSize = 14;
app.CalibrationNew.Position = [abx y 60 24];
app.CalibrationNew.Text = 'new';
app.CalibrationNew.ButtonPushedFcn = createCallbackFcn(app, @abr.Calibration, false);

% Create CalibrationLoad
app.CalibrationLoad = uibutton(app.ConfigTab, 'push');
app.CalibrationLoad.FontSize = 14;
app.CalibrationLoad.Position = [bbx y 60 24];
app.CalibrationLoad.Text = 'load';
app.CalibrationLoad.ButtonPushedFcn = createCallbackFcn(app, @locate_calibration_file, false);

% Create CalibrationDropDownLabel
app.CalibrationDropDownLabel = uilabel(app.ConfigTab);
app.CalibrationDropDownLabel.HorizontalAlignment = 'right';
app.CalibrationDropDownLabel.FontSize = 14;
app.CalibrationDropDownLabel.Position = [x y labelWidth 22];
app.CalibrationDropDownLabel.Text = 'Calibration';

% Create CalibrationDropDown
app.CalibrationDropDown = uidropdown(app.ConfigTab);
app.CalibrationDropDown.Items = {''};
app.CalibrationDropDown.Editable = 'off';
app.CalibrationDropDown.FontSize = 14;
app.CalibrationDropDown.BackgroundColor = [1 1 1];
app.CalibrationDropDown.Position = [ddx y ddl 22];
app.CalibrationDropDown.Value = '';
app.CalibrationDropDown.Tooltip = 'Select a calibration file';
app.CalibrationDropDown.ValueChangedFcn = createCallbackFcn(app, @load_calibration_file,true);


app.OutputPanel = uipanel('Parent',app.ConfigTab,'Title','ABR Data Output', ...
    'Position',[5 10 450 100]);

x = 5;
y = 50;
ddx = 100;

% Create OutputFileDropDown
app.OutputFileDropDown = uidropdown(app.OutputPanel);
app.OutputFileDropDown.Editable = 'on';
app.OutputFileDropDown.FontSize = 14;
app.OutputFileDropDown.BackgroundColor = [1 1 1];
app.OutputFileDropDown.Position = [ddx y 300 22];
app.OutputFileDropDown.Items = {''};
app.OutputFileDropDown.Value = '';
app.OutputFileDropDown.Tooltip = 'Select an output file or create a new one by editing the name.';
app.OutputFileDropDown.ValueChangedFcn = createCallbackFcn(app, @output_file_changed,true);


% Create OutputFileLabel
app.OutputFileLabel = uilabel(app.OutputPanel);
app.OutputFileLabel.HorizontalAlignment = 'right';
app.OutputFileLabel.FontSize = 14;
app.OutputFileLabel.Position = [x y labelWidth 22];
app.OutputFileLabel.Text = 'Output File';

y = y - yspacing;


% Create OutputPathDropDown
recentPaths = getpref('ABRControlPanel','outputFolder',{app.root}); % set with recent directories
ind = isfolder(recentPaths);
recentPaths(~ind) = [];
app.OutputPathDropDown = uidropdown(app.OutputPanel);
app.OutputPathDropDown.Editable = 'off';
app.OutputPathDropDown.FontSize = 14;
app.OutputPathDropDown.BackgroundColor = [1 1 1];
app.OutputPathDropDown.Position = [ddx y 300 22];
app.OutputPathDropDown.Items = app.truncate_str(recentPaths,40);
app.OutputPathDropDown.ItemsData = recentPaths;
app.OutputPathDropDown.Value = recentPaths{1};
app.OutputPathDropDown.ValueChangedFcn = createCallbackFcn(app, @output_path_changed,true);

% Create OutputPathSelectButton
app.OutputPathSelectButton = uibutton(app.OutputPanel, 'push');
app.OutputPathSelectButton.FontSize = 14;
app.OutputPathSelectButton.Position = [ddx+300+5 y 40 24];
app.OutputPathSelectButton.Text = 'dir';
app.OutputPathSelectButton.Tooltip = 'Locate a data output directory';
app.OutputPathSelectButton.ButtonPushedFcn = createCallbackFcn(app, @output_select_directory, false);

% Create OutputPathLabel
app.OutputPathLabel = uilabel(app.OutputPanel);
app.OutputPathLabel.HorizontalAlignment = 'right';
app.OutputPathLabel.FontSize = 14;
app.OutputPathLabel.Position = [x y labelWidth 22];
app.OutputPathLabel.Text = 'Directory';

e.Value = app.OutputFileDropDown.Value;
e.Source = app.OutputFileDropDown;
app.output_path_changed(e);

%% SUBJECT TAB -------------------------------------------------------------
% Create SubjectInfoTab
app.SubjectInfoTab = uitab(app.TabGroup);
app.SubjectInfoTab.Title = 'Subject Info';

% Create DOBDatePickerLabel
app.DOBDatePickerLabel = uilabel(app.SubjectInfoTab);
app.DOBDatePickerLabel.HorizontalAlignment = 'right';
app.DOBDatePickerLabel.Position = [203 105 32 22];
app.DOBDatePickerLabel.Text = 'DOB';

% Create SubjectDOBDatePicker
app.SubjectDOBDatePicker = uidatepicker(app.SubjectInfoTab);
app.SubjectDOBDatePicker.Position = [249 105 148 22];

% Create SubjectTree
app.SubjectTree = uitree(app.SubjectInfoTab);
app.SubjectTree.Position = [20 29 150 203];

% Create NotesTextAreaLabel
app.NotesTextAreaLabel = uilabel(app.SubjectInfoTab);
app.NotesTextAreaLabel.HorizontalAlignment = 'right';
app.NotesTextAreaLabel.Position = [195 73 37 22];
app.NotesTextAreaLabel.Text = 'Notes';

% Create SubjectNotesTextArea
app.SubjectNotesTextArea = uitextarea(app.SubjectInfoTab);
app.SubjectNotesTextArea.Position = [247 16 193 81];

% Create AliasEditFieldLabel
app.AliasEditFieldLabel = uilabel(app.SubjectInfoTab);
app.AliasEditFieldLabel.HorizontalAlignment = 'right';
app.AliasEditFieldLabel.Position = [202 166 32 22];
app.AliasEditFieldLabel.Text = 'Alias';

% Create SubjectAliasEditField
app.SubjectAliasEditField = uieditfield(app.SubjectInfoTab, 'text');
app.SubjectAliasEditField.Position = [249 166 123 22];

% Create IDEditFieldLabel
app.IDEditFieldLabel = uilabel(app.SubjectInfoTab);
app.IDEditFieldLabel.HorizontalAlignment = 'right';
app.IDEditFieldLabel.Position = [209 135 25 22];
app.IDEditFieldLabel.Text = 'ID';

% Create SubjectIDEditField
app.SubjectIDEditField = uieditfield(app.SubjectInfoTab, 'text');
app.SubjectIDEditField.Position = [249 135 123 22];

% Create SubjectSexSwitch
app.SubjectSexSwitch = uiswitch(app.SubjectInfoTab, 'slider');
app.SubjectSexSwitch.Items = {'Female', 'Male'};
app.SubjectSexSwitch.Orientation = 'vertical';
app.SubjectSexSwitch.Tooltip = {'Select subject sex'};
app.SubjectSexSwitch.Position = [425 140 14 31];
app.SubjectSexSwitch.Value = 'Female';

% Create ScientistDropDownLabel
app.ScientistDropDownLabel = uilabel(app.SubjectInfoTab);
app.ScientistDropDownLabel.HorizontalAlignment = 'right';
app.ScientistDropDownLabel.Position = [183 203 51 22];
app.ScientistDropDownLabel.Text = 'Scientist';
app.ScientistDropDownLabel.Tooltip = 'Select or enter initials';

% Create SubjectScientistDropDown
app.SubjectScientistDropDown = uidropdown(app.SubjectInfoTab);
app.SubjectScientistDropDown.Editable = 'on';
app.SubjectScientistDropDown.Position = [249 203 123 22];

% Create SubjectAddaSubjectButton
app.SubjectAddaSubjectButton = uibutton(app.SubjectInfoTab, 'push');
app.SubjectAddaSubjectButton.FontSize = 10;
app.SubjectAddaSubjectButton.Position = [20 5 100 22];
app.SubjectAddaSubjectButton.Text = 'Add a Subject';
app.SubjectAddaSubjectButton.ButtonPushedFcn = createCallbackFcn(app, @add_subject,false);




%% CONTROL TAB ------------------------------------------------------------
% Create ControlTab
app.ControlTab = uitab(app.TabGroup);
app.ControlTab.Title = 'Control';

% Create ControlSweepCountGauge
app.ControlSweepCountGauge = uigauge(app.ControlTab, 'linear');
app.ControlSweepCountGauge.Position = [22 1 420 40];
app.ControlSweepCountGauge.Limits = [1 128];

% Create ControlStimInfoLabel
app.ControlStimInfoLabel = uilabel(app.ControlTab);
app.ControlStimInfoLabel.Position = [22 41 436 30];
app.ControlStimInfoLabel.HorizontalAlignment = 'center';
app.ControlStimInfoLabel.VerticalAlignment = 'bottom';
app.ControlStimInfoLabel.FontSize = 14;
app.ControlStimInfoLabel.Text = '';

% Create RepetitionsLabel
app.NumRepetitionsLabel = uilabel(app.ControlTab);
app.NumRepetitionsLabel.HorizontalAlignment = 'right';
app.NumRepetitionsLabel.Position = [61 132 76 22];
app.NumRepetitionsLabel.Text = '# Repetitions';

% Create NumRepetitionsSpinner
app.NumRepetitionsSpinner = uispinner(app.ControlTab);
app.NumRepetitionsSpinner.Limits = [1 Inf];
app.NumRepetitionsSpinner.RoundFractionalValues = 'on';
app.NumRepetitionsSpinner.ValueDisplayFormat = '%d';
app.NumRepetitionsSpinner.HorizontalAlignment = 'center';
app.NumRepetitionsSpinner.Position = [147 132 73 22];
app.NumRepetitionsSpinner.Value = 1;


% Create SweepsSpinnerLabel
app.SweepsSpinnerLabel = uilabel(app.ControlTab);
app.SweepsSpinnerLabel.HorizontalAlignment = 'right';
app.SweepsSpinnerLabel.Position = [79 199 58 22];
app.SweepsSpinnerLabel.Text = '# Sweeps';

% Create SweepCountSpinner
app.SweepCountSpinner = uispinner(app.ControlTab);
app.SweepCountSpinner.Limits = [1 inf];
app.SweepCountSpinner.RoundFractionalValues = 'on';
app.SweepCountSpinner.ValueDisplayFormat = '%d';
app.SweepCountSpinner.HorizontalAlignment = 'center';
app.SweepCountSpinner.Position = [147 199 73 22];
app.SweepCountSpinner.Value = 128;
app.SweepCountSpinner.ValueChangedFcn = createCallbackFcn(app, @update_sweep_count, true);
app.SweepCountSpinner.CreateFcn = createCallbackFcn(app, @update_sweep_count, true);

% Create SweepRateHzSpinnerLabel
app.SweepRateHzSpinnerLabel = uilabel(app.ControlTab);
app.SweepRateHzSpinnerLabel.HorizontalAlignment = 'right';
app.SweepRateHzSpinnerLabel.Position = [40 166 97 22];
app.SweepRateHzSpinnerLabel.Text = 'Sweep Rate (Hz)';

% Create SweepRateHzSpinner
app.SweepRateHzSpinner = uispinner(app.ControlTab);
app.SweepRateHzSpinner.Limits = [0.001 100];
app.SweepRateHzSpinner.HorizontalAlignment = 'center';
app.SweepRateHzSpinner.Position = [147 166 73 22];
app.SweepRateHzSpinner.Value = 21.1;

% Create SweepDurationLabel
app.SweepDurationLabel = uilabel(app.ControlTab);
app.SweepDurationLabel.HorizontalAlignment = 'right';
app.SweepDurationLabel.Position = [20 101 117 22];
app.SweepDurationLabel.Text = 'Sweep Duration (ms)';

% Create SweepDurationSpinner
app.SweepDurationSpinner = uispinner(app.ControlTab);
app.SweepDurationSpinner.Limits = [0.1 1000];
app.SweepDurationSpinner.HorizontalAlignment = 'center';
app.SweepDurationSpinner.Position = [147 101 73 22];
app.SweepDurationSpinner.Value = 10;

% Create ControlAdvCriteriaDropDownLabel
app.ControlAdvCriteriaDropDownLabel = uilabel(app.ControlTab);
app.ControlAdvCriteriaDropDownLabel.HorizontalAlignment = 'right';
app.ControlAdvCriteriaDropDownLabel.Position = [17 65 121 22];
app.ControlAdvCriteriaDropDownLabel.Text = 'Advance on';

% Create ControlAdvCriteriaDropDown
app.ControlAdvCriteriaDropDown = uidropdown(app.ControlTab);
app.ControlAdvCriteriaDropDown.Items = {'# Sweeps', 'Correlation Threshold', '< Define >'};
app.ControlAdvCriteriaDropDown.Position = [146 65 100 22];
app.ControlAdvCriteriaDropDown.Value = '# Sweeps';

% Create Panel_2
app.Panel_2 = uipanel(app.ControlTab);
app.Panel_2.Position = [250 80 200 150];

% Create ControlAdvanceButton
app.ControlAdvanceButton = uibutton(app.Panel_2, 'push');
app.ControlAdvanceButton.Position = [18 60 90 35];
app.ControlAdvanceButton.Text = 'Advance >';
app.ControlAdvanceButton.ButtonPushedFcn = createCallbackFcn(app, @advance_schedule,false);

% Create ControlRepeatButton
app.ControlRepeatButton = uibutton(app.Panel_2, 'state');
app.ControlRepeatButton.Text = 'Repeat';
app.ControlRepeatButton.Position = [18 105 90 35];
app.ControlRepeatButton.ValueChangedFcn = createCallbackFcn(app, @repeat_schedule_idx,true);


% Create ControlPauseButton
app.ControlPauseButton = uibutton(app.Panel_2, 'state');
app.ControlPauseButton.Text = 'Pause ||';
app.ControlPauseButton.Position = [18 16 90 35];
app.ControlPauseButton.ValueChangedFcn = createCallbackFcn(app, @pause_button,false);

% Create ControlAcquisitionSwitch
app.ControlAcquisitionSwitch = uiswitch(app.Panel_2, 'toggle');
app.ControlAcquisitionSwitch.Items = {'Idle', 'Acquire'};
app.ControlAcquisitionSwitch.FontSize = 16;
app.ControlAcquisitionSwitch.Position = [135 45 31 70];
app.ControlAcquisitionSwitch.Value = 'Idle';
app.ControlAcquisitionSwitch.ValueChangedFcn = createCallbackFcn(app, @control_acq_switch, true);



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

% Create UtilityScheduleDesignButton
app.UtilityScheduleDesignButton = uibutton(app.UtilitiesTab, 'push');
app.UtilityScheduleDesignButton.Position = [61 131 111 34];
app.UtilityScheduleDesignButton.Text = 'Schedule Design';
app.UtilityScheduleDesignButton.ButtonPushedFcn = createCallbackFcn(app,@abr.ScheduleDesign,false);

% Create UtilitySoundCalibrationButton
app.UtilitySoundCalibrationButton = uibutton(app.UtilitiesTab, 'push');
app.UtilitySoundCalibrationButton.Position = [61 182 111 34];
app.UtilitySoundCalibrationButton.Text = 'Sound Calibration';
app.UtilitySoundCalibrationButton.ButtonPushedFcn = createCallbackFcn(app,@abr.Calibration,false);


% Create UtilityABRDataViewerButton
app.UtilityABRDataViewerButton = uibutton(app.UtilitiesTab, 'push');
app.UtilityABRDataViewerButton.Position = [61 31 111 34];
app.UtilityABRDataViewerButton.Text = 'ABR Trace Organizer';
app.UtilityABRDataViewerButton.ButtonPushedFcn = createCallbackFcn(app,@abr.traces.Organizer,false);

% Create UtilityOnlineAnalysisButton
app.UtilityOnlineAnalysisButton = uibutton(app.UtilitiesTab, 'push');
app.UtilityOnlineAnalysisButton.Position = [61 81 111 34];
app.UtilityOnlineAnalysisButton.Text = 'Online Analysis';


%% NON-TAB COMPONENTS -----------------------------------------------------

% Create AcquisitionStateLamp
app.AcquisitionStateLamp = uilamp(app.ControlPanelUIFigure);
app.AcquisitionStateLamp.Position = [525 250 20 20];
app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];

p = app.AcquisitionStateLamp.Position;
% Create AcquisitionStateLabel
app.AcquisitionStateLabel = uilabel(app.ControlPanelUIFigure);
app.AcquisitionStateLabel.HorizontalAlignment = 'right';
app.AcquisitionStateLabel.Position = [p(1)-105 p(2) 100 22];
app.AcquisitionStateLabel.Text = 'Ready';
