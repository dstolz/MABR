% App initialization and construction

% Create UIFigure and components
function createComponents(app)

% Create ControlPanelUIFigure
app.ControlPanelUIFigure = uifigure;
app.ControlPanelUIFigure.Position = [100 100 480 273];
app.ControlPanelUIFigure.Name = 'ABR Control Panel';

% Create FileMenu
app.FileMenu = uimenu(app.ControlPanelUIFigure);
app.FileMenu.Text = 'File';

% Create LoadConfigurationMenu
app.LoadConfigurationMenu = uimenu(app.FileMenu);
app.LoadConfigurationMenu.Text = 'Load Configuration ...';

% Create SaveConfigurationMenu
app.SaveConfigurationMenu = uimenu(app.FileMenu);
app.SaveConfigurationMenu.Text = 'Save Configuration ...';

% Create OptionsMenu
app.OptionsMenu = uimenu(app.ControlPanelUIFigure);
app.OptionsMenu.Text = 'Options';

% Create StayonTopMenu
app.StayonTopMenu = uimenu(app.OptionsMenu);
app.StayonTopMenu.Text = 'Stay on Top';

% Create AcquisitionFilterDesignMenu
app.AcquisitionFilterDesignMenu = uimenu(app.OptionsMenu);
app.AcquisitionFilterDesignMenu.Text = 'Acquisition Filter Design';

% Create TabGroup
app.TabGroup = uitabgroup(app.ControlPanelUIFigure);
app.TabGroup.SelectionChangedFcn = createCallbackFcn(app, @TabGroupSelectionChanged, true);
app.TabGroup.Position = [1 1 480 273];

% Create ConfigTab
app.ConfigTab = uitab(app.TabGroup);
app.ConfigTab.Title = 'Config';

% Create ScheduleDropDownLabel
app.ScheduleDropDownLabel = uilabel(app.ConfigTab);
app.ScheduleDropDownLabel.HorizontalAlignment = 'right';
app.ScheduleDropDownLabel.FontSize = 14;
app.ScheduleDropDownLabel.Position = [29 182 64 22];
app.ScheduleDropDownLabel.Text = 'Schedule';

% Create ConfigScheduleDropDown
app.ConfigScheduleDropDown = uidropdown(app.ConfigTab);
app.ConfigScheduleDropDown.Items = {''};
app.ConfigScheduleDropDown.Editable = 'off';
app.ConfigScheduleDropDown.FontSize = 14;
app.ConfigScheduleDropDown.BackgroundColor = [1 1 1];
app.ConfigScheduleDropDown.Position = [108 182 287 22];
app.ConfigScheduleDropDown.Value = '';

% Create ConfigLocateButton
app.ConfigLocateButton = uibutton(app.ConfigTab, 'push');
app.ConfigLocateButton.FontSize = 14;
app.ConfigLocateButton.Position = [399.5 180 53 24];
app.ConfigLocateButton.Text = 'locate';

% Create ConfigNewButton
app.ConfigNewButton = uibutton(app.ConfigTab, 'push');
app.ConfigNewButton.FontSize = 14;
app.ConfigNewButton.Position = [401 124 49 24];
app.ConfigNewButton.Text = 'new';

% Create OutputDropDownLabel
app.OutputDropDownLabel = uilabel(app.ConfigTab);
app.OutputDropDownLabel.HorizontalAlignment = 'right';
app.OutputDropDownLabel.FontSize = 14;
app.OutputDropDownLabel.Position = [44 126 48 22];
app.OutputDropDownLabel.Text = 'Output';

% Create ConfigOutputDropDown
app.ConfigOutputDropDown = uidropdown(app.ConfigTab);
app.ConfigOutputDropDown.Items = {'data_output_file.abr'};
app.ConfigOutputDropDown.Editable = 'on';
app.ConfigOutputDropDown.FontSize = 14;
app.ConfigOutputDropDown.BackgroundColor = [1 1 1];
app.ConfigOutputDropDown.Position = [107 126 287 22];
app.ConfigOutputDropDown.Value = 'data_output_file.abr';

% Create ConfigSaveButton
app.ConfigSaveButton = uibutton(app.ConfigTab, 'push');
app.ConfigSaveButton.Position = [267 67 100 30];
app.ConfigSaveButton.Text = 'Save';

% Create ConfigLoadButton
app.ConfigLoadButton = uibutton(app.ConfigTab, 'push');
app.ConfigLoadButton.Position = [120 67 100 30];
app.ConfigLoadButton.Text = 'Load';

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
app.SubjectSexSwitch.Position = [426 180 14 31];
app.SubjectSexSwitch.Value = 'Female';

% Create ScientistDropDownLabel
app.ScientistDropDownLabel = uilabel(app.SubjectInfoTab);
app.ScientistDropDownLabel.HorizontalAlignment = 'right';
app.ScientistDropDownLabel.Position = [183 203 51 22];
app.ScientistDropDownLabel.Text = 'Scientist';

% Create SubjectScientistDropDown
app.SubjectScientistDropDown = uidropdown(app.SubjectInfoTab);
app.SubjectScientistDropDown.Position = [249 203 123 22];

% Create SubjectAddaSubjectButton
app.SubjectAddaSubjectButton = uibutton(app.SubjectInfoTab, 'push');
app.SubjectAddaSubjectButton.FontSize = 10;
app.SubjectAddaSubjectButton.Tooltip = {'Select subject directory'};
app.SubjectAddaSubjectButton.Position = [20 5 100 22];
app.SubjectAddaSubjectButton.Text = 'Add a Subject';
app.SubjectAddaSubjectButton.ButtonPushedFcn = {@add_subject,app};

% Create ControlTab
app.ControlTab = uitab(app.TabGroup);
app.ControlTab.Title = 'Control';

% Create ControlSweepCountGauge
app.ControlSweepCountGauge = uigauge(app.ControlTab, 'linear');
app.ControlSweepCountGauge.Position = [22 1 436 40];

% Create Panel
app.Panel = uipanel(app.ControlTab);
app.Panel.Position = [14 124 248 111];

% Create AdvancementCriteriaDropDownLabel
app.AdvancementCriteriaDropDownLabel = uilabel(app.Panel);
app.AdvancementCriteriaDropDownLabel.HorizontalAlignment = 'right';
app.AdvancementCriteriaDropDownLabel.Position = [13 12 121 22];
app.AdvancementCriteriaDropDownLabel.Text = 'Advancement Criteria';

% Create SweepAdvancementCriteriaDropDown
app.SweepAdvancementCriteriaDropDown = uidropdown(app.Panel);
app.SweepAdvancementCriteriaDropDown.Items = {'# Sweeps', 'Correlation Threshold', ''};
app.SweepAdvancementCriteriaDropDown.Position = [142 12 85 22];
app.SweepAdvancementCriteriaDropDown.Value = '# Sweeps';

% Create SweepsSpinnerLabel
app.SweepsSpinnerLabel = uilabel(app.Panel);
app.SweepsSpinnerLabel.HorizontalAlignment = 'right';
app.SweepsSpinnerLabel.Position = [74 80 58 22];
app.SweepsSpinnerLabel.Text = '# Sweeps';

% Create SweepCountSpinner
app.SweepCountSpinner = uispinner(app.Panel);
app.SweepCountSpinner.Limits = [1 Inf];
app.SweepCountSpinner.RoundFractionalValues = 'on';
app.SweepCountSpinner.ValueDisplayFormat = '%d';
app.SweepCountSpinner.HorizontalAlignment = 'center';
app.SweepCountSpinner.Position = [142 80 73 22];
app.SweepCountSpinner.Value = 1024;

% Create SweepRateHzSpinnerLabel
app.SweepRateHzSpinnerLabel = uilabel(app.Panel);
app.SweepRateHzSpinnerLabel.HorizontalAlignment = 'right';
app.SweepRateHzSpinnerLabel.Position = [35 47 97 22];
app.SweepRateHzSpinnerLabel.Text = 'Sweep Rate (Hz)';

% Create SweepRateHzSpinner
app.SweepRateHzSpinner = uispinner(app.Panel);
app.SweepRateHzSpinner.Limits = [0.001 100];
app.SweepRateHzSpinner.HorizontalAlignment = 'center';
app.SweepRateHzSpinner.Position = [142 47 73 22];
app.SweepRateHzSpinner.Value = 21.1;

% Create Panel_2
app.Panel_2 = uipanel(app.ControlTab);
app.Panel_2.Position = [270 78 196 157];

% Create ControlAdvanceButton
app.ControlAdvanceButton = uibutton(app.Panel_2, 'push');
app.ControlAdvanceButton.Position = [18 60 77 35];
app.ControlAdvanceButton.Text = 'Advance >';

% Create ControlRepeatButton
app.ControlRepeatButton = uibutton(app.Panel_2, 'state');
app.ControlRepeatButton.Text = 'Repeat';
app.ControlRepeatButton.Position = [18 105 77 35];

% Create ControlPauseButton
app.ControlPauseButton = uibutton(app.Panel_2, 'state');
app.ControlPauseButton.Text = 'Pause ||';
app.ControlPauseButton.Position = [18 16 77 35];

% Create ControlAcquireIdleSwitch
app.ControlAcquireIdleSwitch = uiswitch(app.Panel_2, 'toggle');
app.ControlAcquireIdleSwitch.Items = {'Idle', 'Acquire'};
app.ControlAcquireIdleSwitch.FontSize = 16;
app.ControlAcquireIdleSwitch.Position = [118 47 31 70];
app.ControlAcquireIdleSwitch.Value = 'Idle';

% Create ControlAcquireLamp
app.ControlAcquireLamp = uilamp(app.Panel_2);
app.ControlAcquireLamp.Position = [168 120 20 20];
app.ControlAcquireLamp.Color = [0.6 0.6 0.6];

% Create UtilitiesTab
app.UtilitiesTab = uitab(app.TabGroup);
app.UtilitiesTab.Title = 'Utilities';

% Create UtilityScheduleDesignButton
app.UtilityScheduleDesignButton = uibutton(app.UtilitiesTab, 'push');
app.UtilityScheduleDesignButton.ButtonPushedFcn = {@launch_utility,app,'ScheduleDesign'};
app.UtilityScheduleDesignButton.Position = [61 131 111 34];
app.UtilityScheduleDesignButton.Text = 'Schedule Design';

% Create UtilitySoundCalibrationButton
app.UtilitySoundCalibrationButton = uibutton(app.UtilitiesTab, 'push');
app.UtilitySoundCalibrationButton.Position = [61 182 111 34];
app.UtilitySoundCalibrationButton.Text = 'Sound Calibration';

% Create UtilityABRDataViewerButton
app.UtilityABRDataViewerButton = uibutton(app.UtilitiesTab, 'push');
app.UtilityABRDataViewerButton.Position = [61 31 111 34];
app.UtilityABRDataViewerButton.Text = 'ABR Data Viewer';

% Create UtilityOnlineAnalysisButton
app.UtilityOnlineAnalysisButton = uibutton(app.UtilitiesTab, 'push');
app.UtilityOnlineAnalysisButton.Position = [61 81 111 34];
app.UtilityOnlineAnalysisButton.Text = 'Online Analysis';
