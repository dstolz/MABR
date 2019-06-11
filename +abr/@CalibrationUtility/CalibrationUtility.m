classdef CalibrationUtility < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = private)
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
        MicSensitivityPanel            matlab.ui.container.Panel
        FrequencyHzEditFieldLabel      matlab.ui.control.Label
        FrequencyHzEditField           matlab.ui.control.NumericEditField
        SoundLeveldBSPLEditFieldLabel  matlab.ui.control.Label
        SoundLeveldBSPLEditField       matlab.ui.control.NumericEditField
        MeasuredVoltagemVEditFieldLabel  matlab.ui.control.Label
        MeasuredVoltagemVEditField     matlab.ui.control.NumericEditField
        SampleButton                   matlab.ui.control.Button
        ReferenceLamp                  matlab.ui.control.Lamp
        MicSensitivityInfoButton       matlab.ui.control.Button
    end

    
    properties (Access = private)
        %SIG              abr.SoundCalibration = abr.SoundCalibration;
        SIG             (1,1) % abr.sigdefs.sigs...

        STATE           {mustBeMember(STATE,{'setup','idle','prerun','running','postrun','error','usercancelled'})} = 'idle';
        lastError   % me
        
        
        thisOne
        
        %
        stimulusV       (1,1) double {mustBePositive,mustBeLessThanOrEqual(stimulusV,1)} = 1;
        
        % params
        sweepOnsets     (1,:) double {mustBeNonnegative,mustBeFinite} % sec
        sweepRate       (1,1) double {mustBePositive,mustBeFinite} = 2; % Hz
        sweepDuration   (1,:) double {mustBePositive,mustBeFinite} = 0.25; % sec
        
        % tone params
        F1  (1,1) double {mustBePositive,mustBeFinite} = 4000;   % First frequency Hz
        F2  (1,1) double {mustBePositive,mustBeFinite} = 86400; % Second frequency Hz (should be set to ~.45*Fs)
        Fn  (1,1) double {mustBePositive,mustBeInteger} = 25;  % number of samples between F1 and F2 (lin)
        
        % noise params
        FHp (1,:) double {mustBePositive,mustBeFinite} = 500;   % High-Pass Frequency Corner (Hz)
        FLp (1,:) double {mustBePositive,mustBeFinite} = 64000; % Low-Pass Frequency Corner (Hz)
        
        
        ResponseFigure
        ReferenceFigure

        Runtime (1,1) abr.Runtime

        CalibrationPhase (1,1) uint8 = 0;

        Timer (1,1) timer
        
        Universal abr.Universal = abr.Universal;
    end
    
    methods
        
        function set.STATE(app,newState)
            
            h = app.thisOne;
            
            h.Color = [0.8 0.8 0.8];
            
            switch newState
                case 'setup'
                    h.Tooltip = 'Starting';
                    h.Color = [1 1 0];
                    app.SampleButton.Enable = 'on';
                    
                case 'idle'
                    h.Tooltip = '';
                    app.SampleButton.Enable = 'on';
                    
                case 'prerun'
                    h.Tooltip = 'Prepping';
                    h.Color = [1 1 0];
                    app.SampleButton.Enable = 'off';
                    
                case 'running'
                    h.Tooltip = 'Running';
                    h.Color = [0.2 1 0.2];
                    app.SampleButton.Enable = 'off';
                    
                case 'postrun'
                    h.Tooltip = 'Done';
                    app.SampleButton.Enable = 'on';
                    app.RunCalibrationSwitch.Value = 'Idle';
                    
                case 'error'
                    % vprintf(0,1,app.lastError.message)
                    h.Color = [1 0 0];
                    app.SampleButton.Enable = 'on';
                    app.RunCalibrationSwitch.Value = 'Idle';
                    
                case 'usercancelled'
                    h.Tooltip = 'Cancelled';
                    app.RunCalibrationSwitch.Value = 'Idle';
            end
            
            drawnow
        end
        
        
        
    end
    
    methods (Access = private)
        createComponents(app)

        function gather_parameters(app)
            app.SIG.NormDB        = app.NormLeveldBEditField.Value;
            
            app.SIG.Device        = app.AudioDeviceDropDown.Value;
            app.SIG.Fs            = str2double(app.SamplingRateDropDown.Value);
            
            
            app.SIG.ReferenceFreq = app.FrequencyHzEditField.Value;
            app.SIG.ReferenceSPL  = app.SoundLeveldBSPLEditField.Value;
            app.SIG.ReferenceVoltage = app.MeasuredVoltagemVEditField.Value./1000;
            
            app.SIG.Note = app.NoteTextArea.Value;
        end
        
        
        
        function setup_playrec(app,waitForBG) 
            if nargin < 2 || isempty(waitForBG), waitForBG = true; end

            % setup as foreground process and launch background process
            if isempty(app.Runtime) || isstruct(app.Runtime) || ~isvalid(app.Runtime) || ~app.Runtime.FgIsRunning
                app.Runtime = abr.Runtime;
            end
            
            % idle background process
            app.Runtime.CommandToBg = abr.Cmd.Idle;
            
            if ~app.Runtime.BgIsRunning
                abr.Runtime.launch_bg_process;
            end
            
            % reset background process
            app.Runtime.CommandToBg = abr.Cmd.Idle;
            
            % wait for the background process to load
            while waitForBG && ~app.Runtime.BgIsRunning, pause(0.1); end
            
            if isequal(app.SIG,0), return; end
            
            
            % tell background process to prep for acquisition
            app.Runtime.CommandToBg = abr.Cmd.Prep;
            
            % wait for state of background process to update
            while app.Runtime.BackgroundState ~= abr.stateAcq.READY
                pause(0.1);
                if app.Runtime.BackgroundState == abr.stateAcq.ERROR
                    app.stateProgram = abr.stateProgram.ERROR;
                    return
                end
            end

        end
        
        function setup_stimulus(app)
                        
            app.SIG.DAC.SampleRate = app.SIG.Fs;
            app.SIG.ADC.SampleRate = app.SIG.Fs;
            
            % generate stimulus from SIG obj
            app.SIG = app.SIG.update;
            
            app.SIG = sort(app.SIG,app.SIG.SortProperty,'ascend');
            
            
            if app.CalibrationPhase < 2
                app.SIG.StimulusVoltage = repmat(app.stimulusV,app.SIG.signalCount,1);
                stimData = cellfun(@times,num2cell(app.SIG.StimulusVoltage),app.SIG.data,'uni',0);
            else
                stimData = app.SIG.data;
            end
            
            sweepInterval = 1./app.sweepRate;
            sweepIntervalSamps = app.SIG.DAC.SampleRate*sweepInterval;
            app.sweepOnsets = 0:sweepInterval:sweepInterval*(app.SIG.signalCount-1);
                        
            % initialize Buffers
            data = cell2mat(stimData'); % assuming all the same duration
            data(sweepIntervalSamps,end) = 0;
            
            % add timing signal to secound output channel
            timingSignal = [1; zeros(sweepIntervalSamps-1,1)];
            timingSignal = repmat(timingSignal,app.SIG.signalCount,1);
            data = [data(:) timingSignal];
            
            % pad onset/offset with some silence
            data = [zeros(app.SIG.DAC.SampleRate,2); data; zeros(app.SIG.DAC.SampleRate,2)];
            
            app.SIG.DAC.Data = data(:,1);
            app.SIG.ADC.Data = [];
            
            app.SIG.DAC.SweepOnsets = find(data(:,2));
            app.SIG.ADC.SweepOnsets = [];
            
            app.SIG.ADC.SweepLength = app.SIG.N;
            app.SIG.DAC.SweepLength = app.SIG.N;
                        
            % write wav file to disk
            afw = dsp.AudioFileWriter( ...
                app.Universal.dacFile, ...
                'FileFormat','WAV', ...
                'SampleRate',app.SIG.DAC.SampleRate, ...
                'Compressor','None (uncompressed)', ...
                'DataType','Single');
            
            afw(data);
            clear data
            
            release(afw);
            delete(afw);
        end

        function start_timer(app)
            t = timerfindall('Tag','CalibrationTimer');
            if ~isempty(t) && isvalid(t)
                stop(t);
                delete(t);
            end
            
            T = timer('Tag','CalibrationTimer');
            T.BusyMode = 'drop';
            T.ExecutionMode = 'fixedRate';
            T.TasksToExecute = inf;
            T.Period = 0.02;
            T.StartDelay = 1;
            
            T.StartFcn = {@abr.CalibrationUtility.timer_Start,app};
            T.TimerFcn = {@abr.CalibrationUtility.timer_Runtime,app};
            T.StopFcn  = {@abr.CalibrationUtility.timer_Stop,app};
            T.ErrorFcn = {@abr.CalibrationUtility.timer_Error,app};
            
            app.Timer = T;
            
            start(app.Timer);

        end


        function load_sig(app,SIG)
            
            sigtype = app.TypeDropDown.Value;
            
            if nargin == 2 && ~isempty(SIG) && isa(SIG,['abr.sigdef.sigs.' sigtype])
                app.SIG = SIG;
                app.SIG.Fs = str2double(app.SamplingRateDropDown.Value);
                app.RunCalibrationSwitch.Enable = 'on';
                return
            end
            
            app.SIG = abr.sigdef.sigs.(sigtype);
            app.SIG.Fs = str2double(app.SamplingRateDropDown.Value);
            
            
            
            % defaults
            app.SIG.soundLevel.Value = app.NormLeveldBEditField.Value; % db
            
            switch app.SIG.Type
                case 'Tone'
                    app.F2 = round(app.SIG.Fs*0.45,-2);
                    app.SIG.frequency.Value  = sprintf('linspace(%g,%g,%d)',app.F1/1000,app.F2/1000,app.Fn); % kHz
                    app.SIG.duration.Value   = 250; % ms
                    app.SIG.windowFcn.Value  = 'blackmanharris';
                    app.SIG.windowRFTime.Value = 1000.*4./app.F1; % ramp over at least one cycle
                    
                    app.SIG.CalibratedParameter = 'frequency';
                    
                case 'Noise'
                    app.SIG.HPfreq.Value     = app.FHp/1000;
                    app.SIG.LPfreq.Value     = app.FLp/1000;
                    app.SIG.duration.Value   = 250; % ms
                    app.SIG.windowFcn.Value  = 'blackmanharris';
                    app.SIG.windowRFTime.Value = 1000.*2./app.FHp; % ramp over at least one cycle
                    
                    app.SIG.CalibratedParameter = 'HPFreq';
                    
                case 'Click'
                    app.SIG.duration.Value   = 0.01; % ms
                    
                    app.SIG.CalibratedParameter = 'duration';
                    
                case 'File'
                    uiconfirm(app.ScheduleFigure, ...
                        'File calibration not yet implemented.','Calibration', ...
                        'Icon','info');
                    app.RunCalibrationSwitch.Enable = 'off';
                    return
            end
            
            dur = app.SIG.duration.realValue;
            rf  = app.SIG.windowRFTime.realValue;
            
            app.SIG.CalcWindow = [rf dur-rf];
            
            w = app.SIG.windowRFTime.realValue;
            d = app.SIG.duration.realValue;
            app.SIG.CalcWindow = [w d-w];
            
            app.RunCalibrationSwitch.Enable = 'on';
        end
        

        % Code that executes after component creation
        function startupFcn(app)
            app.STATE = 'setup';
            
            app.setup_playrec(false);
            
            APR = audioPlayerRecorder;
            devices = APR.getAudioDevices;
            release(APR);
            
            
            lastused = getpref('SoundCalibration','audioDevice',devices{1});
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
            
            lastused = getpref('SoundCalibration','samplingRate','44100');
            app.SamplingRateDropDown.Value = lastused;
            
            app.STATE = 'idle';
        end

        % Close request function: CalibrationFigure
        function CalibrationFigureCloseRequest(app,event)
            if isequal(app.STATE,'running')
                msgbox(sprintf('I''m sorry Dave, I can''t do that.\n\nPlease stop calibration before exiting.'),'Calibration','warn','modal');
                return
            end
            
            app.Runtime.CommandToBg = abr.Cmd.Kill;
            
            delete(app)
        end

        % Value changed function: RunCalibrationSwitch
        function RunCalibrationSwitchValueChanged(app,event)
            app.thisOne = app.CalibrationStateLamp;
            
            switch app.RunCalibrationSwitch.Value
                case 'Run'
                    
                    app.gather_parameters;

                    app.STATE = 'prerun';

                    app.CalibrationPhase = 0;
                
                    app.start_timer;

                case 'Idle'
                    app.Runtime.CommandToBg = abr.Cmd.Idle;
                    
                    app.CalibrationPhase = 3;
                    
                    if ~isempty(app.Timer) && isvalid(app.Timer)
                        stop(app.Timer);
                        delete(app.Timer);
                    end
                    
                    app.SampleButton.Enable = 'on';
                    
                    app.STATE = 'usercancelled';
            end
            
        end


        % Value changed function: AudioDeviceDropDown
        function AudioDeviceDropDownValueChanged(app, event)
            value = app.AudioDeviceDropDown.Value;
            setpref('SoundCalibration','audioDevice',value);
        end

        % Value changed function: SamplingRateDropDown
        function SamplingRateDropDownValueChanged(app, event)
            value = app.SamplingRateDropDown.Value;
            setpref('SoundCalibration','samplingRate',value);
        end

        % Button pushed function: SampleButton
        function SampleButtonPushed(app)
            app.thisOne = app.ReferenceLamp;
            try
                
                app.STATE = 'setup';
                
                app.setup_playrec(true);
                
                Fs = str2double(app.SamplingRateDropDown.Value);
                
                Duration = 2; % seconds
                Y = zeros(round(Fs.*Duration),2,'single');
                Y(1,2) = 1;

                % write blank wav file to disk
                afw = dsp.AudioFileWriter( ...
                    app.Universal.dacFile, ...
                    'FileFormat','WAV', ...
                    'SampleRate',Fs, ...
                    'Compressor','None (uncompressed)', ...
                    'DataType','Single');
                afw(Y);
                release(afw);
                delete(afw);
                
                % tell background process to prep for acquisition
                app.Runtime.CommandToBg = abr.Cmd.Prep;
                pause(0.5);
                
                app.STATE = 'running';
                app.Runtime.CommandToBg = abr.Cmd.Run;
                pause(0.5);
                while app.Runtime.CommandToFg ~= abr.Cmd.Completed, pause(0.05); end
                pause(0.5);
                Y = app.Runtime.mapSignalBuffer.Data(1:app.Runtime.mapCom.Data.BufferIndex(2));
                
                % discard first second of audio in case of recording onset
                % artifact
                Y(1:round(Fs)) = [];
                
                if all(Y==0)
                    errordlg('Something is wrong.  Unable to read data from sound card.','Mic Sensitivity','modal');
                    app.STATE = 'error';
                    return
                end
                
                Yrms = rms(Y);
                
                % plot time & freq representations of ADC
                f = findobj('type','figure','-and','name','Reference');
                if isempty(f)
                    f = figure('name','Reference','IntegerHandle','off', ...
                        'Color','w','Position',[200 150 500 300]);
                end
                figure(f);
                clf(f);
                
                % Time-domain plot
                ax = subplot(2,4,[1 4],'Parent',f);
                [unit,multiplier] = abr.Universal.voltage_gauge(max(abs(Y)));
                tvec = 0:1/Fs:length(Y)/Fs-1/Fs;
                plot(ax,tvec([1 end])*1000,[0 0],'-k','linewidth',2);
                hold(ax,'on');
                plot(ax,tvec*1000,Y*multiplier);
                hold(ax,'off');
                
                yl = [-1.1 1.1] .* max(abs(Y)) * multiplier;
                if yl(1) == yl(2), yl(2) = yl(1) + 1; end
                ax.YAxis.Limits = yl;
                
                ax.XAxis.Label.String = 'time (ms)';
                ax.YAxis.Label.String = sprintf('amplitude (%s)',unit);
                
                [unit,multiplier] = abr.Universal.voltage_gauge(Yrms);
                ax.Title.String = sprintf('Reference Tone RMS = %.3f %s RMS',Yrms*multiplier,unit);
                grid(ax,'on');
                
                % Freq-domain plot
                L = length(Y);
                w = window('hanning',L);
                Y = Y.*w;
                Y = fft(Y);
                P2 = abs(Y/L);
                M = P2(1:L/2+1);
                M(2:end-1) = 2*M(2:end-1);
                M = 20.*log10(M);
                freq = Fs*(0:(L/2))/L;
                freq = freq ./ 1000;
                
                ax = subplot(2,4,[5 7],'Parent',f);

                ax.XLim = freq([1 end]); ax.XLimMode = 'manual';
                
                rFreq = app.FrequencyHzEditField.Value/1000;
                h = line(ax,freq,M);
                line(ax,[1 1]*rFreq,ax.YLim,'linestyle','-','linewidth',2, ...
                    'color',[.6 1 .2]);
                uistack(h,'top');
                
                ax.XScale = 'log';
                ax.XAxis.Exponent = 0;
                ax.XAxis.Label.String = 'frequency (kHz)';
                ax.YAxis.Label.String = 'Magnitude (dB)';
                
                box(ax,'on');
                grid(ax,'on');
                
                
                % zoomed
                ax = subplot(2,4,8,'Parent',f);
                
                fb = rFreq .* 2.^([-1 1]);
                ind = freq >= fb(1) & freq <= fb(2);
                
                h = line(ax,freq(ind),M(ind));
                line(ax,[1 1]*rFreq,ax.YLim,'linestyle','-','linewidth',2, ...
                    'color',[.6 1 .2]);
                uistack(h,'top');
                
                ax.XScale = 'log';
                ax.XAxis.Exponent = 0;
                ax.XAxis.Label.String = 'frequency (kHz)';
                
                box(ax,'on');
                grid(ax,'on');
                
                
                % Measure signal power and update field
                app.MeasuredVoltagemVEditField.Value = double(Yrms).*1000;
                
                app.STATE = 'postrun';
                
            catch me
                app.STATE = 'error';
                app.lastError = me;
                rethrow(me); % handle error message
            end
        end
        
        

        % Button pushed function: ModifyButton
        function ModifyButtonPushed(app)
            app.RunCalibrationSwitch.Enable = 'off'; drawnow
            
            app.load_sig(app.SIG);
            
            S = abr.ScheduleDesign(app.SIG,1);
            
            waitfor(S.CompileButton,'UserData'); % Must hit compile button to continue
            
            if ~isvalid(S), return; end
            
            app.SIG = S.SIG;
            
            try
                close(S.ScheduleDesignFigure);
            end
            
            app.RunCalibrationSwitch.Enable = 'on';
        end

        % Menu selected function: SaveCalibrationDataMenu
        function SaveCalibrationDataMenuSelected(app)
            if ~app.SIG.calibration_is_valid
                h = msgbox('No calibration data to save.  Please run calibration.', ...
                    'Sound Calibration','help','modal');
                waitfor(h);
                return
            end
                        
            dfltpn = getpref('SoundCalibration','dataPath',cd);
            [fn,pn] = uiputfile({'*.cal','Calibration (*.cal)'}, ...
                'Save Calibration Data',dfltpn);
            
            if isequal(fn,0), return; end
            
            ffn = fullfile(pn,fn);
            
            CalibrationData = app.SIG;
            
            save(ffn,'CalibrationData','-mat');
            
            setpref('SoundCalibration','dataPath',pn);
        end

        % Menu selected function: LoadCalibrationDataMenu
        function LoadCalibrationDataMenuSelected(app)
            dfltpn = getpref('SoundCalibration','dataPath',cd);
            [pn,fn] = uigetfile({'*.cal','Calibration (*.cal)'}, ...
                'Load Calibration Data', ...
                dfltpn,'MultiSelect','off');
            
            if isequal(fn,0), return; end
            
            ffn = fullfile(pn,fn);
            
            fprintf('Loading %s\n',ffn)
            
            load(ffn,'CalibrationData','-mat');
            
            app.SIG = CalibrationData;
            %app.SIG = CalibrationData.SIG;
            
            fprintf('\tCalibration from: %s\n',app.SIG.Timestamp);
            
            setpref('SoundCalibration','dataPath',pn);
            
        end

        % Value changed function: TypeDropDown
        function TypeDropDownValueChanged(app, event)
            app.load_sig;
        end

        % Button pushed function: LocatePlotButton
        function LocatePlotButtonPushed(app)
            f = findobj('type','figure','-and','-regexp','name','Calibration*');
            if ~isempty(f), figure(f); end
        end


        
        
        
        
        
        function docbox(~,event)
            switch event.Source.Parent.Title
                case 'Hardware'
                    abr.Universal.docbox('calibration','components','hardware');
                case 'Microphone Sensitivity'
                    abr.Universal.docbox('calibration','components','micsensitivity');
                case 'Stimulus'
                    abr.Universal.docbox('calibration','components','stimulus');
                case 'Calibration'
                    abr.Universal.docbox('calibration','components','calibrate');
            end
        end
    end

    methods (Access = public)

        % Construct app
        function app = CalibrationUtility(varargin)

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

    
    methods (Static)
        function timer_Start(T,event,app)
            
            app.CalibrationPhase = app.CalibrationPhase + 1;
            
            vprintf(4,'time_Start:Calibration Phase = %d',app.CalibrationPhase)

            app.setup_stimulus;
            
            app.setup_playrec;
            
            % TEST MODE!!!! *****
            app.Runtime.CommandToBg = abr.Cmd.TestMode;

            % get the plot ready
            app.SIG = app.SIG.plot_calibration(app.CalibrationPhase);

            figure(app.SIG.FigCalibration);
            
            app.STATE = 'running';
            app.Runtime.CommandToBg = abr.Cmd.Run;
        end

        function timer_Runtime(T,event,app)
            vprintf(4,'time_Runtime:Calibration Phase = %d',app.CalibrationPhase)
            if app.CalibrationPhase == 0, return; end
            
            mC = app.Runtime.mapCom;
            mSB = app.Runtime.mapSignalBuffer;
            mTB = app.Runtime.mapTimingBuffer;
            
            BH = double(mC.Data.BufferIndex(2));
            LB = app.SIG.ADC.N;
            if LB == 0, LB = 1; end
                    
            % gather data from background process
            switch app.Runtime.BackgroundState
                case abr.stateAcq.COMPLETED
                    %[~,postSweep] = app.Runtime.extract_sweeps([0 app.SIG.duration.realValue],true);
                    app.SIG.ADC.Data = mSB.Data(1:BH);
                    ind = mTB.Data(1:BH-1) > mTB.Data(2:BH);
                    ind = ind & mTB.Data(1:BH-1) >= 0.5;
                    app.SIG.ADC.SweepOnsets = find(ind);
                    stop(T);
                    return
                    
                case abr.stateAcq.ACQUIRE
                    %[~,postSweep] = app.Runtime.extract_sweeps([0 app.SIG.duration.realValue],false);
                    
                    data = mSB.Data(LB:BH);
                    app.SIG.ADC = app.SIG.ADC.appendData(data);
                    
                    % find stimulus onsets in timing signal
                    ind = mTB.Data(LB:BH-1) > mTB.Data(LB+1:BH); % rising edge
                    ind = ind & mTB.Data(LB:BH-1) >= 0.5; % threshold
                    if ~any(ind), return; end
                    app.SIG.ADC.SweepOnsets(end+1:end+sum(ind)) = LB+find(ind);
                    
                    
                case abr.stateAcq.ERROR
                    errordlg('Dang it! Background Process Threw an Error!','Error','modal');
                    stop(T);
                    return
            end
            
            vprintf(4,'# sweeps acquired = %d',app.SIG.ADC.NumSweeps)
            
            
            app.SIG = app.SIG.plot_calibration(app.CalibrationPhase);

        end

        function timer_Stop(T,event,app)
            vprintf(4,'time_Stop:Calibration Phase = %d',app.CalibrationPhase)

            if app.CalibrationPhase == 1
                adjV = app.SIG.compute_adjusted_voltage;
                ind = adjV > 1 | adjV <= 0;
                if any(ind)
                    errordlg(sprintf('%d stimuli have an adjusted voltage <= 0 or > 1!',sum(ind)));
                    app.STATE = 'error';
                end
                app.SIG.NormalizedVoltage = adjV;
                app.SIG.StimulusVoltage = app.SIG.NormalizedVoltage;

                app.start_timer; % start second phase
            else
                vprintf(1,'Completed calibration')
                app.STATE = 'postrun';

                app.SIG.CalibratedVoltage = app.SIG.NormalizedVoltage;
                app.SaveCalibrationDataMenuSelected;
                
            end
        end

        function timer_Error(T,event,app)
            app.Runtime.CommandToBg = abr.Cmd.Error;
            app.CalibrationPhase = 0;
            app.STATE = 'error';
        end
    end

end