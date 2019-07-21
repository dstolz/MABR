% App initialization and construction

% Create UIFigure and components
function createComponents(app)

global GVerbosity

% Create ControlPanelUIFigure
app.ControlPanelUIFigure = uifigure;
app.ControlPanelUIFigure.Position = [50 400 600 325];
app.ControlPanelUIFigure.Name = 'MABR Control Panel';
app.ControlPanelUIFigure.Tag  = 'MABR_FIG';
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




% Create ParametersMenu
app.ParametersMenu = uimenu(app.ControlPanelUIFigure);
app.ParametersMenu.Text = 'Parameters';

% Create UpdateInputGainMenu
g = getpref('ABRControlPanel','AmpGain',1);
app.UpdateInputGainMenu = uimenu(app.ParametersMenu);
app.UpdateInputGainMenu.Text = sprintf('Amplifier Gain = %gx',g);
app.UpdateInputGainMenu.Callback = createCallbackFcn(app, @update_amplifier_gain, false);



% Create OptionsMenu
app.OptionsMenu = uimenu(app.ControlPanelUIFigure);
app.OptionsMenu.Text = 'Options';

% Create StayonTopMenu
app.StayonTopMenu = uimenu(app.OptionsMenu);
app.StayonTopMenu.Text = 'Stay on Top';
app.StayonTopMenu.Separator = 'on';
app.StayonTopMenu.Checked = 'off';
app.StayonTopMenu.MenuSelectedFcn = createCallbackFcn(app, @always_on_top,false);

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
app.SetupAudioChannelsMenu.Text = 'Define Audio Channels';
app.SetupAudioChannelsMenu.Tooltip = 'Setup Stimulus, Acquisition, and Loop-Back channels';
app.SetupAudioChannelsMenu.MenuSelectedFcn = createCallbackFcn(app, @setup_audiochannels, false);

% Create VerbosityMenu
app.VerbosityMenu = uimenu(app.OptionsMenu);
app.VerbosityMenu.Text = sprintf('Program Verbosity = %d',GVerbosity);
app.VerbosityMenu.Tooltip = 'Specify the verbosity of command line output.';
app.VerbosityMenu.Separator = 'on';
app.VerbosityMenu.MenuSelectedFcn = createCallbackFcn(app, @update_verbosity, false);


% Create ResetBackgroundProcessMenu
app.ResetBackgroundProcessMenu = uimenu(app.OptionsMenu);
app.ResetBackgroundProcessMenu.Text = 'Reset Background Process';
app.ResetBackgroundProcessMenu.Tooltip = 'Click to reset the background process if you are having techinical issues';
app.ResetBackgroundProcessMenu.Separator = 'on';
app.ResetBackgroundProcessMenu.MenuSelectedFcn = createCallbackFcn(app, @reset_bg_process, false);




CPpos = app.ControlPanelUIFigure.Position;

%% Create TabGroup --------------------------------------------------------
app.TabGroup = uitabgroup(app.ControlPanelUIFigure);
app.TabGroup.SelectionChangedFcn = createCallbackFcn(app, @TabGroup_selection_changed, true);
app.TabGroup.Position = [1 1 CPpos(3) CPpos(4)-1];
app.TabGroup.TabLocation = 'left';


%% NON-TAB COMPONENTS -----------------------------------------------------

% Create AcquisitionStateLamp
app.AcquisitionStateLamp = uilamp(app.ControlPanelUIFigure);
app.AcquisitionStateLamp.Position = [CPpos(3)-25 CPpos(4)-25 20 20];
app.AcquisitionStateLamp.Color = [0.6 0.6 0.6];

p = app.AcquisitionStateLamp.Position;

% Create AcquisitionStateLabel
app.AcquisitionStateLabel = uilabel(app.ControlPanelUIFigure);
app.AcquisitionStateLabel.HorizontalAlignment = 'right';
app.AcquisitionStateLabel.Position = [p(1)-105 p(2) 100 22];
app.AcquisitionStateLabel.FontSize = 14;
app.AcquisitionStateLabel.FontWeight = 'bold';
app.AcquisitionStateLabel.Text = 'Ready';

% Create HelpButton
app.HelpButton = uibutton(app.ControlPanelUIFigure, 'push');
app.HelpButton.Icon = fullfile(app.iconPath,'helpicon.gif');
app.HelpButton.IconAlignment = 'center';
app.HelpButton.Position = [150 CPpos(4)-25 20 20];
app.HelpButton.Text = '';
app.HelpButton.Tooltip = 'Control Panel Help';
app.HelpButton.ButtonPushedFcn = createCallbackFcn(app, @cp_docbox, false);

% Create LocateFigures
app.LocateFiguresButton = uibutton(app.ControlPanelUIFigure, 'push');
app.LocateFiguresButton.Icon = fullfile(app.iconPath,'figureicon.gif');
app.LocateFiguresButton.IconAlignment = 'center';
app.LocateFiguresButton.Position = [180 CPpos(4)-25 20 20];
app.LocateFiguresButton.Text = '';
app.LocateFiguresButton.Tooltip = 'Locate open figures';
app.LocateFiguresButton.ButtonPushedFcn = createCallbackFcn(app, @locate_figures, false);







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
app.CalibrationNew.ButtonPushedFcn = createCallbackFcn(app, @abr.CalibrationUtility, false);

R = R + 2; % allow some extra space


app.OutputPanel = uipanel('Parent',G,'Title','ABR Data Output');
app.OutputPanel.Layout.Row = [R R+3];
app.OutputPanel.Layout.Column = [1 nCols];


nRows = 3; nCols = 3;
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
app.OutputPathDD.Items = abr.Tools.truncate_str(recentPaths,40);
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
G.ColumnWidth = {140 80 10 195}; 
    
R = 2;

% Create SweepsSpinnerLabel
app.SweepsSpinnerLabel = uilabel(G);
app.SweepsSpinnerLabel.HorizontalAlignment = 'right';
app.SweepsSpinnerLabel.Layout.Row = R;
app.SweepsSpinnerLabel.Layout.Column = 1;
app.SweepsSpinnerLabel.FontSize = 14;
app.SweepsSpinnerLabel.FontWeight = 'normal';
app.SweepsSpinnerLabel.Text = '# Sweeps';
app.SweepsSpinnerLabel.Tooltip = 'Number of sweeps, i.e. stimulus presentations, per schedule row.';

% Creqte SweepCountDD
app.SweepCountDD = uidropdown(G);
app.SweepCountDD.Layout.Row = R;
app.SweepCountDD.Layout.Column = 2;
app.SweepCountDD.Editable = 'on';
app.SweepCountDD.Items = cellstr(num2str(2.^(6:13)'));
app.SweepCountDD.ItemsData = num2cell(2.^(6:13)');
app.SweepCountDD.Value = 1024;
app.SweepCountDD.FontSize = 16;
app.SweepCountDD.FontWeight = 'normal';
app.SweepCountDD.ValueChangedFcn = createCallbackFcn(app, @update_sweep_count, true);

R = R + 1;
% Create SweepRateHzSpinnerLabel
app.SweepRateHzSpinnerLabel = uilabel(G);
app.SweepRateHzSpinnerLabel.HorizontalAlignment = 'right';
app.SweepRateHzSpinnerLabel.Layout.Row = R;
app.SweepRateHzSpinnerLabel.Layout.Column = 1;
app.SweepRateHzSpinnerLabel.FontSize = 14;
app.SweepRateHzSpinnerLabel.FontWeight = 'normal';
app.SweepRateHzSpinnerLabel.Text = 'Sweep Rate (Hz)';
app.SweepRateHzSpinnerLabel.Tooltip = 'Stimulus presentation rate in Hz';

% Create SweepRateHzSpinner
app.SweepRateHzSpinner = uispinner(G);
app.SweepRateHzSpinner.Limits = [0.001 100];
app.SweepRateHzSpinner.HorizontalAlignment = 'center';
app.SweepRateHzSpinner.Layout.Row = R;
app.SweepRateHzSpinner.Layout.Column = 2;
app.SweepRateHzSpinner.FontSize = 16;
app.SweepRateHzSpinner.FontWeight = 'normal';
app.SweepRateHzSpinner.Value = 21.1;
app.SweepRateHzSpinner.ValueChangedFcn = createCallbackFcn(app, @update_sweep_rate, true);

R = R + 1;
% Create SweepDurationLabel
app.SweepDurationLabel = uilabel(G);
app.SweepDurationLabel.HorizontalAlignment = 'right';
app.SweepDurationLabel.Layout.Row = R;
app.SweepDurationLabel.Layout.Column = 1;
app.SweepDurationLabel.FontSize = 14;
app.SweepDurationLabel.FontWeight = 'normal';
app.SweepDurationLabel.Text = 'Sweep Duration (ms)';
app.SweepDurationLabel.Tooltip = 'ABR acquisition duration in milliseconds';

% Create SweepDurationSpinner
app.SweepDurationSpinner = uispinner(G);
app.SweepDurationSpinner.Limits = [0.1 1000];
app.SweepDurationSpinner.HorizontalAlignment = 'center';
app.SweepDurationSpinner.Layout.Row = R;
app.SweepDurationSpinner.Layout.Column = 2;
app.SweepDurationSpinner.FontSize = 16;
app.SweepDurationSpinner.FontWeight = 'normal';
app.SweepDurationSpinner.Value = 10;
app.SweepDurationSpinner.ValueChangedFcn = createCallbackFcn(app, @update_sweep_duration, true);


R = R + 1;
% Create RepetitionsLabel
app.NumRepetitionsLabel = uilabel(G);
app.NumRepetitionsLabel.HorizontalAlignment = 'right';
app.NumRepetitionsLabel.Layout.Row = R;
app.NumRepetitionsLabel.Layout.Column = 1;
app.NumRepetitionsLabel.FontSize = 14;
app.NumRepetitionsLabel.FontWeight = 'normal';
app.NumRepetitionsLabel.Text = '# Repetitions';
app.NumRepetitionsLabel.Tooltip = 'Number of repetitions per schedule row';

% Create NumRepetitionsSpinner
app.NumRepetitionsSpinner = uispinner(G);
app.NumRepetitionsSpinner.Limits = [1 Inf];
app.NumRepetitionsSpinner.RoundFractionalValues = 'on';
app.NumRepetitionsSpinner.ValueDisplayFormat = '%d';
app.NumRepetitionsSpinner.HorizontalAlignment = 'center';
app.NumRepetitionsSpinner.FontSize = 16;
app.NumRepetitionsSpinner.FontWeight = 'normal';
app.NumRepetitionsSpinner.Layout.Row = R;
app.NumRepetitionsSpinner.Layout.Column = 2;
app.NumRepetitionsSpinner.Value = 1;
app.NumRepetitionsSpinner.ValueChangedFcn = createCallbackFcn(app, @update_num_reps, true);

R = R + 1;
% Create ControlAdvCriteriaDDLabel
app.ControlAdvCriteriaDDLabel = uilabel(G);
app.ControlAdvCriteriaDDLabel.HorizontalAlignment = 'right';
app.ControlAdvCriteriaDDLabel.Layout.Row = R;
app.ControlAdvCriteriaDDLabel.Layout.Column = 1;
app.ControlAdvCriteriaDDLabel.FontSize = 14;
app.ControlAdvCriteriaDDLabel.FontWeight = 'normal';
app.ControlAdvCriteriaDDLabel.Text = 'Advancement Criteria:';
app.ControlAdvCriteriaDDLabel.Tooltip = 'Function used to advance to the next schedule row';

% Create ControlAdvCriteriaDD
g = getpref('ABRControlPanel','AdvanceFcns',{'# Sweeps', 'Correlation Threshold'; 'abr_adv_num_sweeps', 'abr_adv_corr_thr'});
app.ControlAdvCriteriaDD = uidropdown(G);
app.ControlAdvCriteriaDD.Layout.Row = R;
app.ControlAdvCriteriaDD.Layout.Column = 2;
app.ControlAdvCriteriaDD.FontSize = 16;
app.ControlAdvCriteriaDD.FontWeight = 'normal';
app.ControlAdvCriteriaDD.Items     = [g(1,:), {'< Define >'}];
app.ControlAdvCriteriaDD.ItemsData = [g(2,:), {'abr.Tools.define_adv_fcn'}];
app.ControlAdvCriteriaDD.Value = 'abr_adv_num_sweeps';
app.ControlAdvCriteriaDD.ValueChangedFcn = createCallbackFcn(app, @update_advance_function, true);

% Create Panel_2
app.Panel_2 = uipanel(G);
app.Panel_2.Layout.Row = [2 6];
app.Panel_2.Layout.Column = 4;


nRows = 3; nCols = 2;
Gpanel = uigridlayout(app.Panel_2,[nRows nCols]);
Gpanel.RowHeight = repmat({'1x'},1,nRows);
Gpanel.ColumnWidth = {'2x' '1x'}; 
    
R = 1;
% Create ControlAdvanceButton
app.ControlAdvanceButton = uibutton(Gpanel, 'push');
app.ControlAdvanceButton.Layout.Row = R;
app.ControlAdvanceButton.Layout.Column = 1;
app.ControlAdvanceButton.FontSize = 16;
app.ControlAdvanceButton.Text = 'Advance';
app.ControlAdvanceButton.Icon = fullfile(app.iconPath,'advance.gif');
app.ControlAdvanceButton.IconAlignment = 'right';
app.ControlAdvanceButton.Enable = 'off';
app.ControlAdvanceButton.ButtonPushedFcn = createCallbackFcn(app, @advance_schedule,false);

R = R + 1;
% Create ControlRepeatButton
app.ControlRepeatButton = uibutton(Gpanel, 'state');
app.ControlRepeatButton.Text = 'Repeat';
app.ControlRepeatButton.Layout.Row = R;
app.ControlRepeatButton.Layout.Column = 1;
app.ControlRepeatButton.FontSize = 16;
app.ControlRepeatButton.Icon = fullfile(app.iconPath,'repeat.gif');
app.ControlRepeatButton.IconAlignment = 'right';
app.ControlRepeatButton.Enable = 'off';
app.ControlRepeatButton.ValueChangedFcn = createCallbackFcn(app, @repeat_schedule_idx,true);


R = R + 1;
% Create ControlPauseButton
app.ControlPauseButton = uibutton(Gpanel, 'state');
app.ControlPauseButton.Text = 'Pause';
app.ControlPauseButton.Layout.Row = R;
app.ControlPauseButton.Layout.Column = 1;
app.ControlPauseButton.FontSize = 16;
app.ControlPauseButton.Icon = fullfile(app.iconPath,'pause.gif');
app.ControlPauseButton.IconAlignment = 'right';
app.ControlPauseButton.Enable = 'off';
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
app.ControlStimInfoLabel.FontWeight = 'bold';
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


%% POSTPROCESSING TAB -----------------------------------------------------
app.PostProcessingTab = uitab(app.TabGroup);
app.PostProcessingTab.Title = 'Post-Processing';

nRows = 6; nCols = 3;
G = uigridlayout(app.PostProcessingTab,[nRows,nCols]);
G.RowHeight   = repmat({'1x'},1,nRows);
G.ColumnWidth = {200,100,100};

R = 2;

% Create PPMovingAvgLabel
app.PPMovingAvgLabel = uilabel(G);
app.PPMovingAvgLabel.FontSize = 14;
app.PPMovingAvgLabel.FontWeight = 'bold';
app.PPMovingAvgLabel.Layout.Row = R;
app.PPMovingAvgLabel.Layout.Column = 1;
app.PPMovingAvgLabel.Text = 'Moving Average Span';
app.PPMovingAvgLabel.HorizontalAlignment = 'right';

% Create PPMovingAvgDD
app.PPMovingAvgDD = uidropdown(G);
app.PPMovingAvgDD.Tag = 'smooth';
app.PPMovingAvgDD.FontSize = 16;
app.PPMovingAvgDD.Items = {'None','2','3','4','5','5','7','6','9','10','11'};
app.PPMovingAvgDD.ItemsData = [0 2:11];
app.PPMovingAvgDD.Layout.Row = R;
app.PPMovingAvgDD.Layout.Column = 2;
app.PPMovingAvgDD.Value = 0;
app.PPMovingAvgDD.ValueChangedFcn = createCallbackFcn(app, @update_postprocessing, true);


R = R + 1;

% Create PPDetrendLabel
app.PPDetrendLabel = uilabel(G);
app.PPDetrendLabel.FontSize = 14;
app.PPDetrendLabel.FontWeight = 'bold';
app.PPDetrendLabel.Layout.Row = R;
app.PPDetrendLabel.Layout.Column = 1;
app.PPDetrendLabel.Text = 'Detrend Waveform';
app.PPDetrendLabel.HorizontalAlignment = 'right';

% Create PPDetrendDD
app.PPDetrendDD = uidropdown(G);
app.PPDetrendDD.Tag = 'detrend';
app.PPDetrendDD.FontSize = 16;
app.PPDetrendDD.Layout.Row = R;
app.PPDetrendDD.Layout.Column = [2 3];
app.PPDetrendDD.Items = [{'None'},{'Subtract Mean'},cellfun(@num2str,num2cell(1:7),'uni',0)];
app.PPDetrendDD.ItemsData = -1:7;
app.PPDetrendDD.Value = -1;
app.PPDetrendDD.ValueChangedFcn = createCallbackFcn(app, @update_postprocessing, true);


R = R + 1;
% 
% % Create PPArtifactRejectLabel
% app.PPArtifactRejectLabel = uilabel(G);
% app.PPArtifactRejectLabel.FontSize = 14;
% app.PPArtifactRejectLabel.FontWeight = 'bold';
% app.PPArtifactRejectLabel.Layout.Row = R;
% app.PPArtifactRejectLabel.Layout.Column = 1;
% app.PPArtifactRejectLabel.Text = 'Detrend Polynomial';
% app.PPArtifactRejectLabel.HorizontalAlignment = 'right';
% 
% % Create PPArtifactRejectDD
% app.PPArtifactRejectDD = uidropdown(G);
% app.PPArtifactRejectDD.Tag = 'detrend';
% app.PPArtifactRejectDD.FontSize = 16;
% app.PPArtifactRejectDD.Items = [{'None'},cellfun(@num2str,num2cell(1:7),'uni',0)];
% app.PPArtifactRejectDD.ItemsData = 0:7;
% app.PPArtifactRejectDD.Value = 1;
% app.PPArtifactRejectDD.ValueChangedFcn = createCallbackFcn(app, @update_postprocessing, true);




%% UTILITIES TAB ----------------------------------------------------------
% Create UtilitiesTab
app.UtilitiesTab = uitab(app.TabGroup);
app.UtilitiesTab.Title = 'Utilities';


nRows = 5; nCols = 2;
G = uigridlayout(app.UtilitiesTab,[nRows nCols]);
G.RowHeight   = repmat({'1x'},1,nRows);
G.ColumnWidth = repmat({'1x'},1,nCols);
    
R = 2;

% Create UtilityScheduleDesignButton
app.UtilityScheduleDesignButton = uibutton(G, 'push');
app.UtilityScheduleDesignButton.Layout.Row = R;
app.UtilityScheduleDesignButton.Layout.Column = 1;
app.UtilityScheduleDesignButton.Text = 'Schedule Design';
app.UtilityScheduleDesignButton.FontSize = 16;
% app.UtilityScheduleDesignButton.FontWeight = 'bold';
app.UtilityScheduleDesignButton.ButtonPushedFcn = createCallbackFcn(app,@abr.ScheduleDesign,false);

R = R + 1;
% Create UtilityScheduleButton
app.UtilityScheduleButton = uibutton(G, 'push');
app.UtilityScheduleButton.Layout.Row = R;
app.UtilityScheduleButton.Layout.Column = 1;
app.UtilityScheduleButton.FontSize = 16;
% app.UtilityScheduleButton.FontWeight = 'bold';
app.UtilityScheduleButton.Text = 'Schedule';
app.UtilityScheduleButton.ButtonPushedFcn = createCallbackFcn(app,@abr.Schedule,false);

R = R + 1;
% Create UtilitySoundCalibrationButton
app.UtilitySoundCalibrationButton = uibutton(G, 'push');
app.UtilitySoundCalibrationButton.Layout.Row = R;
app.UtilitySoundCalibrationButton.Layout.Column = 1;
app.UtilitySoundCalibrationButton.Text = 'Sound Calibration';
app.UtilitySoundCalibrationButton.FontSize = 16;
% app.UtilitySoundCalibrationButton.FontWeight = 'bold';
app.UtilitySoundCalibrationButton.ButtonPushedFcn = createCallbackFcn(app,@abr.CalibrationUtility,false);

R = R + 1;
% Create UtilityABRDataViewerButton
app.UtilityABRDataViewerButton = uibutton(G, 'push');
app.UtilityABRDataViewerButton.Layout.Row = R;
app.UtilityABRDataViewerButton.Layout.Column = 1;
app.UtilityABRDataViewerButton.Text = 'Trace Organizer';
app.UtilityABRDataViewerButton.FontSize = 16;
% app.UtilityABRDataViewerButton.FontWeight = 'bold';
app.UtilityABRDataViewerButton.ButtonPushedFcn = createCallbackFcn(app,@abr.traces.Organizer,false);



