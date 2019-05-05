classdef Calibration < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        CalibrationFigure              matlab.ui.Figure
        FileMenu                       matlab.ui.container.Menu
        SaveCalibrationDataMenu        matlab.ui.container.Menu
        LoadCalibrationDataMenu        matlab.ui.container.Menu
        StimulusPanel                  matlab.ui.container.Panel
        TypeDropDownLabel              matlab.ui.control.Label
        TypeDropDown                   matlab.ui.control.DropDown
        StimulusInfoButton             matlab.ui.control.Button
        ModifyButton                   matlab.ui.control.Button
        HardwarePanel                  matlab.ui.container.Panel
        AudioDeviceDropDownLabel       matlab.ui.control.Label
        AudioDeviceDropDown            matlab.ui.control.DropDown
        SamplingRateDropDownLabel      matlab.ui.control.Label
        SamplingRateDropDown           matlab.ui.control.DropDown
        HardwareInfoButton             matlab.ui.control.Button
        CalibrationPanel               matlab.ui.container.Panel
        LocatePlotButton               matlab.ui.control.Button
        RunCalibrationSwitch           matlab.ui.control.RockerSwitch
        NoteTextAreaLabel              matlab.ui.control.Label
        NoteTextArea                   matlab.ui.control.TextArea
        NormLeveldBEditFieldLabel      matlab.ui.control.Label
        NormLeveldBEditField           matlab.ui.control.NumericEditField
        CalibrationStateLamp           matlab.ui.control.Lamp
        CalibrationInfoPanel           matlab.ui.control.Button
        ReferencePanel                 matlab.ui.container.Panel
        FrequencyHzEditFieldLabel      matlab.ui.control.Label
        FrequencyHzEditField           matlab.ui.control.NumericEditField
        SoundLeveldBSPLEditFieldLabel  matlab.ui.control.Label
        SoundLeveldBSPLEditField       matlab.ui.control.NumericEditField
        MeasuredVoltagemVEditFieldLabel  matlab.ui.control.Label
        MeasuredVoltagemVEditField     matlab.ui.control.NumericEditField
        SampleButton                   matlab.ui.control.Button
        ReferenceLamp                  matlab.ui.control.Lamp
        ReferenceInfoButton            matlab.ui.control.Button
    end

    
    properties (Access = private)
        AC              abr.AcousticCalibration = abr.AcousticCalibration;
        playRecObj      audioPlayerRecorder = audioPlayerRecorder;
        STATE           {mustBeMember(STATE,{'setup','idle','prerun','running','postrun','error','usercancelled'})} = 'idle';
        frameSize       (1,1) double = 1024;
        lastError   % me
        
        
        thisOne
        
        % params
        sweepOnsets     (1,:) double {mustBeNonnegative,mustBeFinite} % sec
        sweepRate       (1,1) double {mustBePositive,mustBeFinite} = 2; % Hz
        sweepDuration   (1,:) double {mustBePositive,mustBeFinite} = 0.25; % sec
        
        % tone params
        F1  (1,1) double {mustBePositive,mustBeFinite} = 500;   % First frequency Hz
        F2  (1,1) double {mustBePositive,mustBeFinite} = 86400; % Second frequency Hz (should be set to ~.45*Fs)
        Fn  (1,1) double {mustBePositive,mustBeInteger} = 25;  % number of samples between F1 and F2 (lin)
        
        % noise params
        FHp (1,:) double {mustBePositive,mustBeFinite} = 500;   % High-Pass Frequency Corner (Hz)
        FLp (1,:) double {mustBePositive,mustBeFinite} = 64000; % Low-Pass Frequency Corner (Hz)
        
        
        ResponseFigure
        ReferenceFigure
    end
    
    methods
        
        function set.STATE(app,newState)
            
            h = app.thisOne;
            
            h.Color = [0.8 0.8 0.8];
            
            switch newState
                case 'setup'
                    h.Tooltip = 'Starting';
                    h.Color = [1 1 0];
                    
                case 'idle'
                    h.Tooltip = '';
                    
                case 'prerun'
                    h.Tooltip = 'Prepping';
                    h.Color = [1 1 0];
                    
                case 'running'
                    h.Tooltip = 'Running';
                    h.Color = [0.2 1 0.2];
                    
                case 'postrun'
                    h.Tooltip = 'Done';
                    app.RunCalibrationSwitch.Value = 'Idle';
                    
                case 'error'
                    %                     h.Tooltip = app.lastError.message;
                    h.Color = [1 0 0];
                    app.RunCalibrationSwitch.Value = 'Idle';
                    
                case 'usercancelled'
                    h.Tooltip = 'Cancelled';
                    app.RunCalibrationSwitch.Value = 'Idle';
            end
            
            drawnow
        end
        
        
        
        function f = get.ResponseFigure(app)
            f = findobj('type','figure','-and','name','Response');
            if isempty(f)
                f = figure('name','Response','IntegerHandle','off', ...
                    'Color','w','Position',[300 60 860 590]);
            end
            figure(f);
        end
        
        function f = get.ReferenceFigure(app)
            f = findobj('type','figure','-and','name','Reference');
            if isempty(f)
                f = figure('name','Reference','IntegerHandle','off', ...
                    'Color','w','Position',[200 150 500 300]);
            end
            figure(f);
        end
        
    end
    
    methods (Access = private)
        
        function gather_parameters(app)
            app.AC.Device        = app.AudioDeviceDropDown.Value;
            app.AC.SampleRate    = str2double(app.SamplingRateDropDown.Value);
            
            app.AC.ReferenceFreq = app.FrequencyHzEditField.Value;
            app.AC.ReferenceSPL  = app.SoundLeveldBSPLEditField.Value;
            app.AC.ReferenceV    = app.MeasuredVoltagemVEditField.Value./1000;
            
            app.AC.Note = app.NoteTextArea.Value;
        end
        
        
        
        function setup_playrec(app)
            app.STATE = 'prerun';
            
            app.gather_parameters;
            
            if ~ismethod(app.playRecObj,'isvalid') || ~isvalid(app.playRecObj)
                app.playRecObj = audioPlayerRecorder;
            end
            release(app.playRecObj);
            
            app.playRecObj.Device     = app.AC.Device;
            app.playRecObj.SampleRate = app.AC.SampleRate;
            
            app.AC.DeviceInfo = app.playRecObj.info;
            
            % reset buffers
            app.AC.DAC = abr.Buffer(app.AC.SampleRate);
            app.AC.ADC = abr.Buffer(app.AC.SampleRate);
            
            app.AC.DAC.FrameSize = app.frameSize;
            app.AC.ADC.FrameSize = app.frameSize;
            
        end
        
        
        
        function trigger_playrec(app)
            bidx = 1:app.AC.DAC.FrameSize:app.AC.DAC.N+1;
            for i = 1:length(bidx)-1
                idx = bidx(i):bidx(i+1)-1;
                app.AC.ADC.Data(idx) = app.playRecObj(app.AC.DAC.Data(idx));
            end
        end
        
        
        
        
        
        function update_reference_plot(app)
            f = app.ReferenceFigure;
            
            % Time-domain plot
            ax = subplot(211,'Parent',f);
            app.AC.ADC.plotSweeps(ax);
            ax.Title.String = sprintf('Reference Tone RMS = %.3f mV RMS',app.AC.ADC.RMS.*1000);
            
            % Freq-domain plot
            ax = subplot(212,'Parent',f);
            app.AC.ADC.plotFFT(ax);
            ax.XAxis.Exponent = 0;
            
        end
        
        function update_response_plot(app,step)
            f = app.ResponseFigure;
            figure(f);
            
            % Sound level plot
            ax = subplot(3,2,[1 2],'Parent',f,'Units','pixels');
            
            if step == 1, cla(ax); end
            
            lineTag    = sprintf('Step%d_line',step);
            scatterTag = sprintf('Step%d_scatter',step);
            
            x = app.AC.SIG.dataParams.(app.AC.CalParam) ./ 1000;
            y = app.AC.MeasuredSPL;
            
            colors = hsv(app.AC.ADC.NumSweeps);
            
            hold(ax,'on');
            
            if step == 1
                line(ax,x([1 end]).*[0.9 1.1],[1 1].* app.AC.NormDB,'linestyle','-','color',[0 0 0],'linewidth',4);
            end
            
            line(ax,x,y,'linewidth',2,'color',[0 0 0],'tag',lineTag);
            scatter(ax,x,y,75,colors,'filled','MarkerEdgeColor','none','tag',scatterTag);
            
            hold(ax,'off');
            
            if step == 2
                h = findobj(ax,'tag','Step1_scatter');
                set(h,'SizeData',15,'MarkerFaceColor',[0.5 0.5 0.5]);
                h = findobj(ax,'tag','Step1_line');
                h.LineWidth = 0.5;
                h.Color = [0.7 0.7 0.7];
            end
            
            ax.XAxis.Limits = x([1 end]);
            
            grid(ax,'on');
            ax.XAxis.Label.String = 'frequency (kHz)';
            ax.YAxis.Label.String = 'Sound Level (dB SPL)';
            
            S = app.AC.CalStats;
            ax.Title.String = sprintf('Transfer Function | Max error from Norm = %0.3f dB',S.Max);
            
            
            
            % time domain plot
            ax = subplot(3,2,[3 5],'Parent',f);
            cla(ax);
            
            x = app.AC.ADC.TimeVector .* 1000;
            y = app.AC.SIG.dataParams.(app.AC.CalParam);
            z = app.AC.ADC.SweepData .* 1000;
            
            [~,y] = meshgrid(x,y);
            
            for i = 1:app.AC.ADC.NumSweeps
                h(i) = line(ax,x,y(i,:),z(:,i),'color',colors(i,:));
            end
            
            ax.XAxis.TickLabelFormat = '%.1f';
            ax.YAxis.TickLabelFormat = '%.1f';
            ax.ZAxis.TickLabelFormat = '%.1f';
            
            ax.XAxis.Label.String = 'time (ms)';
            ax.YAxis.Label.String = app.AC.CalParam;
            ax.ZAxis.Label.String = 'amplitude (mV)';
            
            ax.YAxis.Exponent = 0;
            
            grid(ax,'on');
            view(ax,3);
            
            
            
            % freq domain plot
            ax = subplot(3,2,[4 6],'Parent',f);
            cla(ax);
            
            warning('off','MATLAB:colon:nonIntegerIndex');
            for i = 1:app.AC.ADC.NumSweeps
                Y = z(:,i);
                L = length(Y);
                w = window('hanning',L);
                Y = Y.*w;
                Y = fft(Y);
                P2 = abs(Y/L);
                M = P2(1:L/2+1);
                M(2:end-1) = 2*M(2:end-1);
                M = 20.*log10(M);
                f = app.AC.ADC.SampleRate*(0:(L/2))/L;
                line(ax,f./1000,M,'color',colors(i,:));
            end
            warning('on','MATLAB:colon:nonIntegerIndex');
            
            grid(ax,'on');
            axis(ax,'tight');
            
            ax.XAxis.Label.String = 'frequency (kHz)';
            ax.YAxis.Label.String = 'Power (dB)';
            
            drawnow
        end
        
        function load_sig(app,SIG)
            
            sigtype = app.TypeDropDown.Value;
            
            if nargin == 2 && ~isempty(SIG) && isa(SIG,['abr.sigdef.sigs.' sigtype])
                app.AC.SIG = SIG;
                app.AC.SIG.Fs = str2double(app.SamplingRateDropDown.Value);
                app.RunCalibrationSwitch.Enable = 'on';
                return
            end
            
            app.AC.SIG = abr.sigdef.sigs.(sigtype);
            app.AC.SIG.Fs = str2double(app.SamplingRateDropDown.Value);
            
            
            
            % defaults
            app.AC.SIG.soundLevel.Value = app.NormLeveldBEditField.Value; % db
            
            switch app.AC.SIG.Type
                case 'Tone'
                    app.F2 = app.AC.SIG.Fs*0.45;
                    app.AC.SIG.frequency.Value  = sprintf('linspace(%g,%g,%d)',app.F1/1000,app.F2/1000,app.Fn); % kHz
                    app.AC.SIG.duration.Value   = 250; % ms
                    app.AC.SIG.windowFcn.Value  = 'blackmanharris';
                    app.AC.SIG.windowRFTime.Value = 1000.*4./app.F1; % ramp over at least one cycle
                    
                    app.AC.CalParam = 'frequency';
                    
                case 'Noise'
                    app.AC.SIG.HPfreq.Value     = app.FHp/1000;
                    app.AC.SIG.LPfreq.Value     = app.FLp/1000;
                    app.AC.SIG.duration.Value   = 250; % ms
                    app.AC.SIG.windowFcn.Value  = 'blackmanharris';
                    app.AC.SIG.windowRFTime.Value = 1000.*2./app.FHp; % ramp over at least one cycle
                    
                    app.AC.CalParam = 'HPFreq';
                    
                case 'Click'
                    app.AC.SIG.duration.Value   = 0.01; % ms
                    
                    app.AC.CalParam = 'duration';
                    
                case 'File'
                    uiconfirm(app.ScheduleFigure, ...
                        'File calibration not yet implemented.','Calibration', ...
                        'Icon','info');
                    app.RunCalibrationSwitch.Enable = 'off';
                    return
            end
            
            w = app.AC.SIG.windowRFTime.realValue;
            d = app.AC.SIG.duration.realValue;
            app.AC.CalcWindow = [w d-w];
            
            app.RunCalibrationSwitch.Enable = 'on';
        end
    end
    

    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.STATE = 'setup';
            
            app.playRecObj = audioPlayerRecorder;
            
            devices = app.playRecObj.getAudioDevices;
            lastused = getpref('AcousticCalibration','audioDevice',devices{1});
            ind = ismember(devices,lastused);
            if any(ind)
                lastused = devices{ind};
            else
                if ispc
                    ind = contains(devices,'ASIO','IgnoreCase',true);
                elseif isunix
                    ind = contains(devices,'ALSA','IgnoreCase',true);
                elseif ismac
                    ind = contains(devices,'CoreAudio','IgnoreCase',true);
                else
                    ind = false;
                end
                
                if any(ind)
                    lastused = devices{ind};
                else
                    lastused = devices{1};
                end
            end
            app.AudioDeviceDropDown.Items = devices;
            app.AudioDeviceDropDown.Value = lastused;
            
            lastused = getpref('AcousticCalibration','samplingRate','44100');
            app.SamplingRateDropDown.Value = lastused;
            
            app.STATE = 'idle';
        end

        % Close request function: CalibrationFigure
        function CalibrationFigureCloseRequest(app, event)
            if isequal(app.STATE,'running')
                msgbox(sprintf('I''m sorry Dave, I can''t do that.\n\nPlease stop calibration before exiting.'),'Calibration','warn','modal');
                return
            end
            delete(app)
            
        end

        % Value changed function: RunCalibrationSwitch
        function RunCalibrationSwitchValueChanged(app,event)
            app.thisOne = app.CalibrationStateLamp;
            value = app.RunCalibrationSwitch.Value;
            
            switch value
                case 'Run'
                    % initialize calibration voltage
                    app.AC.StimulusV = repmat(0.1,app.AC.DAC.NumSweeps,1);
                    
                    for i = 1:2
                        app.setup_playrec;
                        
                        % generate stimulus from SIG obj
                        app.AC.SIG.Fs = app.AC.DAC.SampleRate;
                        app.AC.SIG    = app.AC.SIG.update;
                        
                        app.AC.SIG = sort(app.AC.SIG,app.AC.CalParam,'ascend');
                        
                        if i == 2
                            % multiply full signal by calibrated value
                            stimData = cellfun(@times,num2cell(app.AC.StimulusV),app.AC.SIG.data,'uni',0);
                        else
                            stimData = app.AC.SIG.data;
                        end
                        
                        sweepInterval = 1./app.sweepRate;
                        sweepIntervalSamps = app.AC.SIG.Fs*sweepInterval;
                        app.sweepOnsets = 0:sweepInterval:sweepInterval.*(app.AC.SIG.signalCount-1);
                        
                        
                        % initialize Buffers
                        data = cell2mat(stimData'); % assuming all the same duration
                        data(sweepIntervalSamps,end) = 0;
                        app.AC.DAC.Data = data(:); clear data
                        app.AC.DAC.SweepLength = app.AC.SIG.N;
                        app.AC.DAC.SweepOnsets = round(app.AC.DAC.SampleRate.*app.sweepOnsets)+1; % single acquisition
                        
                        app.AC.ADC.preallocate(app.AC.DAC.N);
                        app.AC.ADC.SweepLength = app.AC.SIG.N;
                        app.AC.ADC.SweepOnsets = app.AC.DAC.SweepOnsets;
                        
                        
                        app.STATE = 'running';
                        
                        app.trigger_playrec;
                        
                        
                        % plot time & freq representations of ADC
                        app.update_response_plot(i);
                        
                        
                        if i == 1
                            app.AC.NormalizedV = app.AC.computeAdjustedV;
                            app.AC.StimulusV   = app.AC.NormalizedV;
                        end
                    end
                    
                    app.STATE = 'postrun';
                    
                    app.AC.CalibratedV = app.AC.NormalizedV;
                    app.SaveCalibrationDataMenuSelected;
                    
                case 'Idle'
                    app.STATE = 'usercancelled';
            end
            
            app.RunCalibrationSwitch.Value = 'Idle';
        end

        % Value changed function: AudioDeviceDropDown
        function AudioDeviceDropDownValueChanged(app, event)
            value = app.AudioDeviceDropDown.Value;
            setpref('AcousticCalibration','audioDevice',value);
        end

        % Value changed function: SamplingRateDropDown
        function SamplingRateDropDownValueChanged(app, event)
            value = app.SamplingRateDropDown.Value;
            setpref('AcousticCalibration','samplingRate',value);
        end

        % Button pushed function: SampleButton
        function SampleButtonPushed(app, event)
            app.thisOne = app.ReferenceLamp;
            try
                app.setup_playrec;
                
                % initialize Buffers
                app.AC.DAC.Data = zeros(app.AC.DAC.SampleRate,1);
                app.AC.DAC.SweepLength = app.AC.DAC.N; % same in this case
                app.AC.DAC.SweepOnsets = 1; % single acquisition
                
                app.AC.ADC.Data = zeros(app.AC.ADC.SampleRate,1);
                app.AC.ADC.SweepLength = app.AC.ADC.N; % same in this case
                app.AC.ADC.SweepOnsets = 1; % single acquisition
                
                app.STATE = 'running';
                
                app.trigger_playrec;
                
                % plot time & freq representations of ADC
                app.update_reference_plot;
                
                % Measure signal power and update field
                app.MeasuredVoltagemVEditField.Value = app.AC.ADC.RMS.*1000;
                
                app.STATE = 'postrun';
                
            catch me
                app.STATE = 'error';
                app.lastError = me;
                rethrow(me); % handle error message
            end
            
        end

        % Button pushed function: ModifyButton
        function ModifyButtonPushed(app, event)
            app.RunCalibrationSwitch.Enable = 'off'; drawnow
            
            app.load_sig(app.AC.SIG);
            
            S = abr.ScheduleDesign(app.AC.SIG,1);
            
            waitfor(S.CompileButton,'UserData'); % Must hit compile button to continue
            
            if ~isvalid(S), return; end
            
            app.AC.SIG = S.SIG;
            
            close(S.ScheduleDesignFigure);
            
            app.RunCalibrationSwitch.Enable = 'on';
        end

        % Menu selected function: SaveCalibrationDataMenu
        function SaveCalibrationDataMenuSelected(app, event)
            if ~isvalid(app.AC)
                h = msgbox('No calibration data to save.  Please run calibration.', ...
                    'Acoustic Calibration','help','modal');
                waitfor(h);
                return
            end
            
            dfltpn = getpref('AcousticCalibration','dataPath',cd);
            [fn,pn] = uiputfile({'*.cal','Calibration (*.cal)'}, ...
                'Save Calibration Data',dfltpn);
            
            if isequal(fn,0), return; end
            
            ffn = fullfile(pn,fn);
            
            CalibrationData = app.AC;
            
            CalibrationData.Timestamp = datestr(now);
            CalibrationData.Filename  = ffn;
            
            save(ffn,'CalibrationData','-mat');
            
            setpref('AcousticCalibration','dataPath',pn);
        end

        % Menu selected function: LoadCalibrationDataMenu
        function LoadCalibrationDataMenuSelected(app, event)
            dfltpn = getpref('AcousticCalibration','dataPath',cd);
            [pn,fn] = uigetfile({'*.cal','Calibration (*.cal)'}, ...
                'Load Calibration Data', ...
                dfltpn,'MultiSelect','off');
            
            if isequal(fn,0), return; end
            
            ffn = fullfile(pn,fn);
            
            fprintf('Loading %s\n',ffn)
            
            load(ffn,'CalibrationData','-mat');
            
            app.AC = CalibrationData;
            app.AC.SIG = CalibrationData.SIG;
            
            fprintf('\tCalibration from: %s\n',app.AC.Timestamp);
            
            setpref('AcousticCalibration','dataPath',pn);
            
        end

        % Button pushed function: ReferenceInfoButton
        function ReferenceInfoButtonPushed(app, event)
            msg = sprintf(['\tUse a piston phone or electronic speaker at at a known sound level to estimate the sensitivity of your microphone and amplifier.  Enter the frequency of the reference tone ' ...
                'it''s known sound level (dB SPL) and click "Sample".\n\nInspect the resulting time- and frequency-domain plots for a clean sinusoid at the specified frequency.']);
            
            msgbox(msg,'Reference Help','help','Modal');
            
        end

        % Value changed function: TypeDropDown
        function TypeDropDownValueChanged(app, event)
            app.load_sig;
        end

        % Button pushed function: LocatePlotButton
        function LocatePlotButtonPushed(app, event)
            f = findobj('type','figure','-and','name','Response');
            if ~isempty(f), figure(f); end
        end

        % Button pushed function: HardwareInfoButton
        function HardwareInfoButtonPushed(app, event)
            msg = sprintf('Select the appropriate audio device and sampling rate for your setup.');
            msgbox(msg,'Reference Help','help','Modal');
        end
    end

    % App initialization and construction
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create CalibrationFigure
            app.CalibrationFigure = uifigure;
            app.CalibrationFigure.Position = [100 100 235 550];
            app.CalibrationFigure.Name = 'UI Figure';
            app.CalibrationFigure.Resize = 'off';
            app.CalibrationFigure.CloseRequestFcn = createCallbackFcn(app, @CalibrationFigureCloseRequest, true);

            % Create FileMenu
            app.FileMenu = uimenu(app.CalibrationFigure);
            app.FileMenu.Text = 'File';

            % Create SaveCalibrationDataMenu
            app.SaveCalibrationDataMenu = uimenu(app.FileMenu);
            app.SaveCalibrationDataMenu.MenuSelectedFcn = createCallbackFcn(app, @SaveCalibrationDataMenuSelected, true);
            app.SaveCalibrationDataMenu.Accelerator = 'S';
            app.SaveCalibrationDataMenu.Text = 'Save Calibration Data';

            % Create LoadCalibrationDataMenu
            app.LoadCalibrationDataMenu = uimenu(app.FileMenu);
            app.LoadCalibrationDataMenu.MenuSelectedFcn = createCallbackFcn(app, @LoadCalibrationDataMenuSelected, true);
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
            app.TypeDropDown = uidropdown(app.StimulusPanel);
            app.TypeDropDown.Items = {'Tone', 'Noise', 'Click', 'File'};
            app.TypeDropDown.ValueChangedFcn = createCallbackFcn(app, @TypeDropDownValueChanged, true);
            app.TypeDropDown.Position = [97 34 72 22];
            app.TypeDropDown.Value = 'Tone';

            % Create StimulusInfoButton
            app.StimulusInfoButton = uibutton(app.StimulusPanel, 'push');
            app.StimulusInfoButton.Icon = 'helpicon.gif';
            app.StimulusInfoButton.IconAlignment = 'center';
            app.StimulusInfoButton.Position = [5 34 20 23];
            app.StimulusInfoButton.Text = '';

            % Create ModifyButton
            app.ModifyButton = uibutton(app.StimulusPanel, 'push');
            app.ModifyButton.ButtonPushedFcn = createCallbackFcn(app, @ModifyButtonPushed, true);
            app.ModifyButton.Position = [55 5 100 22];
            app.ModifyButton.Text = 'Modify';

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
            app.HardwareInfoButton.ButtonPushedFcn = createCallbackFcn(app, @HardwareInfoButtonPushed, true);
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
            app.LocatePlotButton.ButtonPushedFcn = createCallbackFcn(app, @LocatePlotButtonPushed, true);
            app.LocatePlotButton.FontWeight = 'bold';
            app.LocatePlotButton.Position = [11 67 88 22];
            app.LocatePlotButton.Text = 'Locate Plot';

            % Create RunCalibrationSwitch
            app.RunCalibrationSwitch = uiswitch(app.CalibrationPanel, 'rocker');
            app.RunCalibrationSwitch.Items = {'Idle', 'Run'};
            app.RunCalibrationSwitch.ValueChangedFcn = createCallbackFcn(app, @RunCalibrationSwitchValueChanged, true);
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
            app.CalibrationInfoPanel.Icon = 'helpicon.gif';
            app.CalibrationInfoPanel.IconAlignment = 'center';
            app.CalibrationInfoPanel.Position = [6 112 20 23];
            app.CalibrationInfoPanel.Text = '';

            % Create ReferencePanel
            app.ReferencePanel = uipanel(app.CalibrationFigure);
%             app.ReferencePanel.Tooltip = {'Use a piston phone or electronic speaker at at a known sound level to estimate the sensitivity of your microphone and amplifier.  Enter the frequency of the reference tone'; ' it''s known sound level (dB SPL) and click "Sample".  Inspect the resulting time- and frequency-domain plots for a clean sinusoid at the specified frequency.s'};
            app.ReferencePanel.Title = 'Reference';
            app.ReferencePanel.FontWeight = 'bold';
            app.ReferencePanel.FontSize = 14;
            app.ReferencePanel.Position = [11 275 210 160];

            % Create FrequencyHzEditFieldLabel
            app.FrequencyHzEditFieldLabel = uilabel(app.ReferencePanel);
            app.FrequencyHzEditFieldLabel.HorizontalAlignment = 'right';
            app.FrequencyHzEditFieldLabel.Position = [46 110 88 22];
            app.FrequencyHzEditFieldLabel.Text = 'Frequency (Hz)';

            % Create FrequencyHzEditField
            app.FrequencyHzEditField = uieditfield(app.ReferencePanel, 'numeric');
            app.FrequencyHzEditField.Limits = [1 1000000];
            app.FrequencyHzEditField.Position = [144 110 50 22];
            app.FrequencyHzEditField.Value = 1000;

            % Create SoundLeveldBSPLEditFieldLabel
            app.SoundLeveldBSPLEditFieldLabel = uilabel(app.ReferencePanel);
            app.SoundLeveldBSPLEditFieldLabel.HorizontalAlignment = 'right';
            app.SoundLeveldBSPLEditFieldLabel.Position = [10 79 124 22];
            app.SoundLeveldBSPLEditFieldLabel.Text = 'Sound Level (dB SPL)';

            % Create SoundLeveldBSPLEditField
            app.SoundLeveldBSPLEditField = uieditfield(app.ReferencePanel, 'numeric');
            app.SoundLeveldBSPLEditField.Limits = [1 1000000];
            app.SoundLeveldBSPLEditField.Position = [144 79 50 22];
            app.SoundLeveldBSPLEditField.Value = 114;

            % Create MeasuredVoltagemVEditFieldLabel
            app.MeasuredVoltagemVEditFieldLabel = uilabel(app.ReferencePanel);
            app.MeasuredVoltagemVEditFieldLabel.HorizontalAlignment = 'right';
            app.MeasuredVoltagemVEditFieldLabel.Position = [3 9 132 22];
            app.MeasuredVoltagemVEditFieldLabel.Text = 'Measured Voltage (mV)';

            % Create MeasuredVoltagemVEditField
            app.MeasuredVoltagemVEditField = uieditfield(app.ReferencePanel, 'numeric');
            app.MeasuredVoltagemVEditField.LowerLimitInclusive = 'off';
            app.MeasuredVoltagemVEditField.Limits = [0 1000000000];
            app.MeasuredVoltagemVEditField.Position = [145 9 50 22];
            app.MeasuredVoltagemVEditField.Value = 100;

            % Create SampleButton
            app.SampleButton = uibutton(app.ReferencePanel, 'push');
            app.SampleButton.ButtonPushedFcn = createCallbackFcn(app, @SampleButtonPushed, true);
            app.SampleButton.FontSize = 14;
            app.SampleButton.FontWeight = 'bold';
            app.SampleButton.Position = [41 39 135 32];
            app.SampleButton.Text = 'Sample';

            % Create ReferenceLamp
            app.ReferenceLamp = uilamp(app.ReferencePanel);
            app.ReferenceLamp.Position = [181 45 20 20];
            app.ReferenceLamp.Color = [0.8 0.8 0.8];

            % Create ReferenceInfoButton
            app.ReferenceInfoButton = uibutton(app.ReferencePanel, 'push');
            app.ReferenceInfoButton.ButtonPushedFcn = createCallbackFcn(app, @ReferenceInfoButtonPushed, true);
            app.ReferenceInfoButton.Icon = 'helpicon.gif';
            app.ReferenceInfoButton.IconAlignment = 'center';
            app.ReferenceInfoButton.Position = [6 110 20 23];
            app.ReferenceInfoButton.Text = '';
        end
    end

    methods (Access = public)

        % Construct app
        function app = Calibration(varargin)

            % Create and configure components
            createComponents(app)

%             % Register the app with App Designer
%             registerApp(app, app.CalibrationFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.CalibrationFigure)
        end
    end
end