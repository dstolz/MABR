% Create UIFigure and components
function createComponents(app)

    % Create CalibrationFigure
    app.CalibrationFigure = uifigure;
    app.CalibrationFigure.Position = [100 100 235 550];
    app.CalibrationFigure.Name = 'Calibration';
    app.CalibrationFigure.Resize = 'off';
    app.CalibrationFigure.CloseRequestFcn = createCallbackFcn(app, @CalibrationFigureCloseRequest, true);

    % Create FileMenu
    app.FileMenu = uimenu(app.CalibrationFigure);
    app.FileMenu.Text = 'File';

    % Create SaveCalibrationDataMenu
    app.SaveCalibrationDataMenu = uimenu(app.FileMenu);
    app.SaveCalibrationDataMenu.MenuSelectedFcn = createCallbackFcn(app, @SaveCalibrationDataMenuSelected, false);
    app.SaveCalibrationDataMenu.Accelerator = 'S';
    app.SaveCalibrationDataMenu.Text = 'Save Calibration Data';

    % Create LoadCalibrationDataMenu
    app.LoadCalibrationDataMenu = uimenu(app.FileMenu);
    app.LoadCalibrationDataMenu.MenuSelectedFcn = createCallbackFcn(app, @LoadCalibrationDataMenuSelected, false);
    app.LoadCalibrationDataMenu.Accelerator = 'L';
    app.LoadCalibrationDataMenu.Text = 'Load Calibration Data';

    % Create StimulusPanel
    app.StimulusPanel = uipanel(app.CalibrationFigure);
    app.StimulusPanel.Title = 'Stimulus';
    app.StimulusPanel.FontWeight = 'bold';
    app.StimulusPanel.FontSize = 14;
    app.StimulusPanel.Position = [12 182 210 82];

    % Create TypeDropDownLabel
    app.TypeDropDownLabel = uilabel(app.StimulusPanel);
    app.TypeDropDownLabel.HorizontalAlignment = 'right';
    app.TypeDropDownLabel.Position = [50 34 32 22];
    app.TypeDropDownLabel.Text = 'Type';

    % Create TypeDropDown
    U = abr.Universal;
    app.TypeDropDown = uidropdown(app.StimulusPanel);
    app.TypeDropDown.Items = U.availableSignals;
    app.TypeDropDown.ValueChangedFcn = createCallbackFcn(app, @TypeDropDownValueChanged, true);
    app.TypeDropDown.Position = [97 34 72 22];
    app.TypeDropDown.Value = 'Tone';

    % Create StimulusInfoButton
    app.StimulusInfoButton = uibutton(app.StimulusPanel, 'push');
    app.StimulusInfoButton.ButtonPushedFcn = createCallbackFcn(app, @docbox, true);
    app.StimulusInfoButton.Icon = 'helpicon.gif';
    app.StimulusInfoButton.IconAlignment = 'center';
    app.StimulusInfoButton.Position = [5 34 20 23];
    app.StimulusInfoButton.Text = '';

    % Create ModifyButton
    app.ModifyButton = uibutton(app.StimulusPanel, 'push');
    app.ModifyButton.ButtonPushedFcn = createCallbackFcn(app, @ModifyButtonPushed, false);
    app.ModifyButton.Position = [40 5 130 22];
    app.ModifyButton.FontWeight = 'bold';
    app.ModifyButton.Text = 'Modify Stimulus';

    % Create HardwarePanel
    app.HardwarePanel = uipanel(app.CalibrationFigure);
    app.HardwarePanel.Title = 'Hardware';
    app.HardwarePanel.FontWeight = 'bold';
    app.HardwarePanel.FontSize = 14;
    app.HardwarePanel.Position = [11 447 210 95];

    % Create AudioDeviceDropDownLabel
    app.AudioDeviceDropDownLabel = uilabel(app.HardwarePanel);
    app.AudioDeviceDropDownLabel.HorizontalAlignment = 'right';
    app.AudioDeviceDropDownLabel.Position = [32 45 76 22];
    app.AudioDeviceDropDownLabel.Text = 'Audio Device';

    % Create AudioDeviceDropDown
    app.AudioDeviceDropDown = uidropdown(app.HardwarePanel);
    app.AudioDeviceDropDown.ValueChangedFcn = createCallbackFcn(app, @AudioDeviceDropDownValueChanged, true);
    app.AudioDeviceDropDown.Position = [112 45 86 22];

    % Create SamplingRateDropDownLabel
    app.SamplingRateDropDownLabel = uilabel(app.HardwarePanel);
    app.SamplingRateDropDownLabel.HorizontalAlignment = 'right';
    app.SamplingRateDropDownLabel.Position = [24 11 84 22];
    app.SamplingRateDropDownLabel.Text = 'Sampling Rate';

    % Create SamplingRateDropDown
    app.SamplingRateDropDown = uidropdown(app.HardwarePanel);
    app.SamplingRateDropDown.Items = {'44100 Hz', '48000 Hz', '96000 Hz', '176400 Hz', '192000 Hz'};
    app.SamplingRateDropDown.ItemsData = {'44100', '48000', '96000', '176400', '192000'};
    app.SamplingRateDropDown.ValueChangedFcn = createCallbackFcn(app, @SamplingRateDropDownValueChanged, true);
%             app.SamplingRateDropDown.Tooltip = {'Not all sampling rates  may be supported by your sound card.'};
    app.SamplingRateDropDown.Position = [114 11 84 22];
    app.SamplingRateDropDown.Value = '44100';

    % Create HardwareInfoButton
    app.HardwareInfoButton = uibutton(app.HardwarePanel, 'push');
    app.HardwareInfoButton.ButtonPushedFcn = createCallbackFcn(app, @docbox, true);
    app.HardwareInfoButton.Icon = 'helpicon.gif';
    app.HardwareInfoButton.IconAlignment = 'center';
    app.HardwareInfoButton.Position = [6 45 20 23];
    app.HardwareInfoButton.Text = '';

    % Create CalibrationPanel
    app.CalibrationPanel = uipanel(app.CalibrationFigure);
    app.CalibrationPanel.Title = 'Calibration';
    app.CalibrationPanel.FontWeight = 'bold';
    app.CalibrationPanel.FontSize = 14;
    app.CalibrationPanel.Position = [11 12 210 159];

    % Create LocatePlotButton
    app.LocatePlotButton = uibutton(app.CalibrationPanel, 'push');
    app.LocatePlotButton.ButtonPushedFcn = createCallbackFcn(app, @LocatePlotButtonPushed, false);
    app.LocatePlotButton.FontWeight = 'bold';
    app.LocatePlotButton.Position = [11 67 88 22];
    app.LocatePlotButton.Text = 'Locate Plot';

    % Create RunCalibrationSwitch
    app.RunCalibrationSwitch = uiswitch(app.CalibrationPanel, 'rocker');
    app.RunCalibrationSwitch.Items = {'Idle', 'Run'};
    app.RunCalibrationSwitch.ValueChangedFcn = createCallbackFcn(app, @RunCalibrationSwitchValueChanged, false);
    app.RunCalibrationSwitch.Enable = 'off';
%             app.RunCalibrationSwitch.Tooltip = {'Must sample a reference tone and define a stimulus before calibration.'};
    app.RunCalibrationSwitch.Position = [175 26 20 45];
    app.RunCalibrationSwitch.Value = 'Idle';

    % Create NoteTextAreaLabel
    app.NoteTextAreaLabel = uilabel(app.CalibrationPanel);
    app.NoteTextAreaLabel.VerticalAlignment = 'bottom';
    app.NoteTextAreaLabel.Position = [11 49 31 22];
    app.NoteTextAreaLabel.Text = 'Note';

    % Create NoteTextArea
    app.NoteTextArea = uitextarea(app.CalibrationPanel);
    app.NoteTextArea.Position = [11 9 139 41];

    % Create NormLeveldBEditFieldLabel
    app.NormLeveldBEditFieldLabel = uilabel(app.CalibrationPanel);
    app.NormLeveldBEditFieldLabel.HorizontalAlignment = 'right';
    app.NormLeveldBEditFieldLabel.Position = [32 112 93 22];
    app.NormLeveldBEditFieldLabel.Text = 'Norm Level (dB)';

    % Create NormLeveldBEditField
    app.NormLeveldBEditField = uieditfield(app.CalibrationPanel, 'numeric');
    app.NormLeveldBEditField.Limits = [-100 110];
    app.NormLeveldBEditField.Position = [131 112 37 22];
    app.NormLeveldBEditField.Value = 80;

    % Create CalibrationStateLamp
    app.CalibrationStateLamp = uilamp(app.CalibrationPanel);
    app.CalibrationStateLamp.Position = [181 113 20 20];
    app.CalibrationStateLamp.Color = [0.8 0.8 0.8];

    % Create CalibrationInfoPanel
    app.CalibrationInfoPanel = uibutton(app.CalibrationPanel, 'push');
    app.CalibrationInfoPanel.ButtonPushedFcn = createCallbackFcn(app, @docbox, true);
    app.CalibrationInfoPanel.Icon = 'helpicon.gif';
    app.CalibrationInfoPanel.IconAlignment = 'center';
    app.CalibrationInfoPanel.Position = [6 112 20 23];
    app.CalibrationInfoPanel.Text = '';

    % Create MicSensitivityPanel
    app.MicSensitivityPanel = uipanel(app.CalibrationFigure);
%             app.MicSensitivityPanel.Tooltip = {'Use a piston phone or electronic speaker at at a known sound level to estimate the sensitivity of your microphone and amplifier.  Enter the frequency of the reference tone'; ' it''s known sound level (dB SPL) and click "Sample".  Inspect the resulting time- and frequency-domain plots for a clean sinusoid at the specified frequency.s'};
    app.MicSensitivityPanel.Title = 'Microphone Sensitivity';
    app.MicSensitivityPanel.FontWeight = 'bold';
    app.MicSensitivityPanel.FontSize = 14;
    app.MicSensitivityPanel.Position = [11 275 210 160];

    % Create FrequencyHzEditFieldLabel
    app.FrequencyHzEditFieldLabel = uilabel(app.MicSensitivityPanel);
    app.FrequencyHzEditFieldLabel.HorizontalAlignment = 'right';
    app.FrequencyHzEditFieldLabel.Position = [46 110 88 22];
    app.FrequencyHzEditFieldLabel.Text = 'Frequency (Hz)';

    % Create FrequencyHzEditField
    app.FrequencyHzEditField = uieditfield(app.MicSensitivityPanel, 'numeric');
    app.FrequencyHzEditField.Limits = [1 1000000];
    app.FrequencyHzEditField.Position = [144 110 50 22];
    app.FrequencyHzEditField.Value = 1000;

    % Create SoundLeveldBSPLEditFieldLabel
    app.SoundLeveldBSPLEditFieldLabel = uilabel(app.MicSensitivityPanel);
    app.SoundLeveldBSPLEditFieldLabel.HorizontalAlignment = 'right';
    app.SoundLeveldBSPLEditFieldLabel.Position = [10 79 124 22];
    app.SoundLeveldBSPLEditFieldLabel.Text = 'Sound Level (dB SPL)';

    % Create SoundLeveldBSPLEditField
    app.SoundLeveldBSPLEditField = uieditfield(app.MicSensitivityPanel, 'numeric');
    app.SoundLeveldBSPLEditField.Limits = [1 1000000];
    app.SoundLeveldBSPLEditField.Position = [144 79 50 22];
    app.SoundLeveldBSPLEditField.Value = 114;

    % Create MeasuredVoltagemVEditFieldLabel
    app.MeasuredVoltagemVEditFieldLabel = uilabel(app.MicSensitivityPanel);
    app.MeasuredVoltagemVEditFieldLabel.HorizontalAlignment = 'right';
    app.MeasuredVoltagemVEditFieldLabel.Position = [3 9 132 22];
    app.MeasuredVoltagemVEditFieldLabel.Text = 'Measured Voltage (mV)';

    % Create MeasuredVoltagemVEditField
    app.MeasuredVoltagemVEditField = uieditfield(app.MicSensitivityPanel, 'numeric');
    app.MeasuredVoltagemVEditField.LowerLimitInclusive = 'off';
    app.MeasuredVoltagemVEditField.Limits = [0 1000000000];
    app.MeasuredVoltagemVEditField.Position = [145 9 50 22];
    app.MeasuredVoltagemVEditField.Value = 100;

    % Create SampleButton
    app.SampleButton = uibutton(app.MicSensitivityPanel, 'push');
    app.SampleButton.ButtonPushedFcn = createCallbackFcn(app, @SampleButtonPushed, false);
    app.SampleButton.FontSize = 14;
    app.SampleButton.FontWeight = 'bold';
    app.SampleButton.Position = [41 39 135 32];
    app.SampleButton.Text = 'Sample';

    % Create ReferenceLamp
    app.ReferenceLamp = uilamp(app.MicSensitivityPanel);
    app.ReferenceLamp.Position = [181 45 20 20];
    app.ReferenceLamp.Color = [0.8 0.8 0.8];

    % Create MicSensitivityInfoButton
    app.MicSensitivityInfoButton = uibutton(app.MicSensitivityPanel, 'push');
    app.MicSensitivityInfoButton.ButtonPushedFcn = createCallbackFcn(app, @docbox, true);
    app.MicSensitivityInfoButton.Icon = 'helpicon.gif';
    app.MicSensitivityInfoButton.IconAlignment = 'center';
    app.MicSensitivityInfoButton.Position = [6 110 20 23];
    app.MicSensitivityInfoButton.Text = '';
end