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
        ViewParameterEditField         matlab.ui.control.EditField
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
        SIG              % abr.sigdefs.sigs...

        STATE           {mustBeMember(STATE,{'setup','idle','prerun','running','postrun','error','usercancelled'})} = 'idle';
        lastError   % me
        
        
        thisLamp
        
        %
        stimulusV       (1,1) double {mustBePositive,mustBeLessThanOrEqual(stimulusV,1)} = 1;
        
        % params
        sweepOnsets     (1,:) double {mustBeNonnegative,mustBeFinite} % sec
        sweepRate       (1,1) double {mustBePositive,mustBeFinite} = 4; % Hz
        sweepDuration   (1,:) double {mustBePositive,mustBeFinite} = 0.1; % sec
        
        % tone params
        F1  (1,1) double {mustBePositive,mustBeFinite} = 1000;   % First frequency Hz
        F2  (1,1) double {mustBePositive,mustBeFinite} = 64000; % Second frequency Hz (should be set to ~.45*Fs)
        Fn  (1,1) double {mustBePositive,mustBeInteger} = 25;  % number of samples between F1 and F2 (lin)
        
        % noise params
        FHp (1,:) double {mustBePositive,mustBeFinite} = 500;   % High-Pass Frequency Corner (Hz)
        FLp (1,:) double {mustBePositive,mustBeFinite} = 64000; % Low-Pass Frequency Corner (Hz)
        
        
        ResponseFigure
        ReferenceFigure

        Runtime (1,1) abr.Runtime

        Calibration      (1,1) abr.SoundCalibration;
        CalibrationPhase (1,1) uint8 = 0;

        Timer (1,1) timer
        
        Universal abr.Universal = abr.Universal;
    end
    
    methods
        
        function set.STATE(app,newState)
            
            h = app.thisLamp;
            
            h.Color = [0.8 0.8 0.8];
            e = findobj(app.CalibrationFigure,'-property','Enable');
            switch newState
                case 'setup'
                    h.Tooltip = 'Starting';
                    h.Color = [1 1 0];
                    set(e,'Enable','off');

                case 'idle'
                    h.Tooltip = 'Idle';
                    set(e,'Enable','on');
                    
                case 'prerun'
                    h.Tooltip = 'Prepping';
                    h.Color = [1 1 0];
                    set(e,'Enable','off');
                    
                case 'running'
                    h.Tooltip = 'Running';
                    h.Color = [0.2 1 0.2];
                    set(e,'Enable','off');
                    app.RunCalibrationSwitch.Enable = 'on';
                    
                case 'postrun'
                    h.Tooltip = 'Done';
                    app.RunCalibrationSwitch.Value = 'Idle';
                    set(e,'Enable','on');
                    
                case 'error'
                    % vprintf(0,1,app.lastError.message)
                    h.Tooltip = 'An Error Occurred';
                    h.Color = [1 0 0];
                    app.RunCalibrationSwitch.Value = 'Idle';
                    set(e,'Enable','on');
                    
                case 'usercancelled'
                    h.Tooltip = 'Cancelled';
                    app.RunCalibrationSwitch.Value = 'Idle';
                    set(e,'Enable','on');
            end
            
            h.Enable = 'on';
            
            if isequal(app.SIG,0)
                app.RunCalibrationSwitch.Enable = 'off';
            end
            
            drawnow
        end
        
        
        function v = get.FHp(app)
            app.gather_parameters;
            v = app.Calibration.Fs*0.45;
        end
        
        
        
        function v = get.FLp(app)
            app.gather_parameters;
            v = 1000;
        end
    end
    
    methods (Access = private)
        createComponents(app)

        function gather_parameters(app)
            app.Calibration.NormDB = app.NormLeveldBEditField.Value;
            
            app.Calibration.Device        = app.AudioDeviceDropDown.Value;
            app.Calibration.Fs            = str2double(app.SamplingRateDropDown.Value);
            
            app.Calibration.ReferenceFreq = app.FrequencyHzEditField.Value;
            app.Calibration.ReferenceSPL  = app.SoundLeveldBSPLEditField.Value;
            app.Calibration.ReferenceVoltage = app.MeasuredVoltagemVEditField.Value./1000;
            
% %             app.SIG.(app.Calibration.CalibratedParameter) = abr.sigdef.sigs.(app.Calibration.CalibratedParameter);
%             app.Calibration.CalibratedValues = app.SIG.(app.Calibration.CalibratedParameter).realValue;

            app.Calibration.Note = app.NoteTextArea.Value;
        end
        
        
        
        function setup_playrec(app,waitForBG)
            D = uiprogressdlg(app.CalibrationFigure, ...
                'Title','Starting',...
                'Indeterminate','on','icon','info',...
                'Message','Please wait ...');
            
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
            
            vprintf(3,'Checking for BG process is running...')
            while waitForBG && ~app.Runtime.BgIsRunning
                vprintf(4,'Waiting on BG process...')
                pause(0.5);
            end
            
            if isequal(app.SIG,0), close(D); return; end
            
            
            % tell background process to prep for acquisition
            vprintf(3,'Request BG to prepare for running')
            app.Runtime.CommandToBg = abr.Cmd.Prep;
            
            % wait for state of background process to update
            while app.Runtime.BackgroundState ~= abr.stateAcq.READY
                vprintf(4,'app.Runtime.BackgroundState ~= abr.stateAcq.READY')
                pause(0.5);
                if app.Runtime.BackgroundState == abr.stateAcq.ERROR
                    app.STATE = 'error';
                    return
                end
                app.Runtime.CommandToBg = abr.Cmd.Prep;
            end
            
            close(D);

        end
        
        function setup_stimulus(app)
            if app.CalibrationPhase < 2
                app.Calibration.reset;
            end

            % generate stimulus from SIG obj
            app.SIG.soundLevel.Value = app.NormLeveldBEditField.Value; % db
            app.SIG = app.SIG.update;
            
            app.SIG = sort(app.SIG,app.SIG.SortProperty,'ascend');
            
            app.Calibration.CalibratedValues = app.SIG.(app.Calibration.CalibratedParameter).realValue;
            
            if app.CalibrationPhase < 2
                app.Calibration.StimulusVoltage = repmat(app.stimulusV,app.SIG.signalCount,1);
                stimData = cellfun(@times,num2cell(app.Calibration.StimulusVoltage),app.SIG.data,'uni',0);
            else
                stimData = app.SIG.data;
%                 stimData = cellfun(@times,stimData,num2cell(app.Calibration.CalibratedVoltage),'uni',0);
            end
            
            sweepInterval = 1./app.sweepRate;
            sweepIntervalSamps = app.SIG.Fs*sweepInterval;
            app.sweepOnsets = 0:sweepInterval:sweepInterval*(app.SIG.signalCount-1);
                        
            % initialize Buffers
%             data = cell2mat(stimData'); % assuming all the same duration
            data = zeros(sweepIntervalSamps,length(stimData),'single');
            for i = 1:length(stimData)
                data(1:length(stimData{i}),i) = stimData{i};
            end

            
            % add timing signal to secound output channel
            timingSignal(sweepIntervalSamps,1) = 0;
            timingSignal(1) = 1;
            timingSignal = repmat(timingSignal,app.SIG.signalCount,1);
            data = [data(:) timingSignal];
            
            % pad onset/offset with some silence
            data = [zeros(app.SIG.Fs,2); data; zeros(app.Calibration.DAC.SampleRate,2)];
            
            app.Calibration.DAC.Data = data(:,1);
            app.Calibration.ADC.Data = [];
            
            app.Calibration.DAC.SweepOnsets = find(data(:,2));
            app.Calibration.ADC.SweepOnsets = [];
            
            app.Calibration.ADC.SweepLength = sweepIntervalSamps;
            app.Calibration.DAC.SweepLength = sweepIntervalSamps;
                        
            % write wav file to disk
            afw = dsp.AudioFileWriter( ...
                app.Universal.dacFile, ...
                'FileFormat','WAV', ...
                'SampleRate',app.Calibration.DAC.SampleRate, ...
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
            app.gather_parameters;
            
            sigtype = app.TypeDropDown.Value;
            
            if nargin == 2 && ~isempty(SIG) && isa(SIG,['abr.sigdef.sigs.' sigtype])
                app.SIG = SIG;
                app.SIG.Fs = str2double(app.SamplingRateDropDown.Value);
                app.RunCalibrationSwitch.Enable = 'on';
                return
            end
            
            app.SIG = abr.sigdef.sigs.(sigtype);
            app.SIG.Fs = app.Calibration.Fs;
            
            
            
            % defaults
            app.SIG.soundLevel.Value = app.NormLeveldBEditField.Value; % db
            
            app.Calibration.Method = 'rms';
            
            app.SIG.duration.MaxLength = 1;
            app.SIG.soundLevel.MaxLength = 1;
            switch app.SIG.Type
                case 'Tone'
                    app.F2 = round(app.Calibration.Fs*0.45,-2);
%                     app.SIG.frequency.Value  = sprintf('linspace(%g,%g,%d)',app.F1/1000,app.F2/1000,app.Fn); % kHz
                    app.SIG.frequency.Value  = sprintf('%.2f:.25:%.2f',app.F1/1000,app.F2/1000);
                    app.SIG.duration.Value   = 50; % ms
                    app.SIG.windowFcn.Value  = 'blackmanharris';
                    app.SIG.windowRFTime.Value = 1000.*4./app.F1; % ramp over at least one cycle
                    
                    app.Calibration.CalibratedParameter = 'frequency';
                    app.Calibration.Method = 'rms';
                    app.Calibration.InterpMethod = 'makima';
                                        
                case 'Noise'
                    app.SIG.HPfreq.Value     = app.FHp/1000;
                    app.SIG.LPfreq.Value     = app.FLp/1000;
                    app.SIG.duration.Value   = 250; % ms
                    app.SIG.windowFcn.Value  = 'blackmanharris';
                    app.SIG.windowRFTime.Value = 1000.*2./app.FHp; % ramp over at least one cycle
                    
                    app.Calibration.CalibratedParameter = 'HPfreq';
                    app.Calibration.Method = 'rms';
                    app.Calibration.InterpMethod = 'nearest';
                    
                case 'Click'
                    app.SIG.duration.Value   = 0.1; % ms
                    app.SIG.duration.MaxLength = inf;
                    app.SIG.duration.MinValue = 1/app.SIG.Fs;
                    app.SIG.polarity.Value = 1;
                    
                    app.Calibration.CalibratedParameter = 'duration';
                    app.Calibration.Method = 'peak';
                    app.Calibration.InterpMethod = 'makima';
                    
                case 'File'
                    uiconfirm(app.ScheduleFigure, ...
                        'File calibration not yet implemented.','Calibration', ...
                        'Icon','info');
                    app.RunCalibrationSwitch.Enable = 'off';
                    
                    app.Calibration.Method = 'rms';
                    app.Calibration.CalibratedParameter = 'file';
                    app.Calibration.InterpMethod = 'none';
                    return
            end
            
            app.Calibration.CalibratedValues = app.SIG.(app.Calibration.CalibratedParameter).realValue;
            
            dur = app.SIG.duration.realValue;
            if isequal(app.Calibration.Method,'rms')
                rf  = app.SIG.windowRFTime.realValue;
                app.Calibration.CalcWindow = [rf dur-rf];
            else
                app.Calibration.CalcWindow = [1/app.Calibration.ADC.SampleRate 1/app.sweepRate];
            end
            
            app.update_ViewParameter;
            
            app.RunCalibrationSwitch.Enable = 'on';
        end
        

        % Code that executes after component creation
        function startupFcn(app)
            app.STATE = 'setup';
            
            app.setup_playrec(true);
            
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
            
            lastused = getpref('SoundCalibration','samplingRate','48000');
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
            app.thisLamp = app.CalibrationStateLamp;
            
            switch app.RunCalibrationSwitch.Value
                case 'Run'
                    
                    app.gather_parameters;

                    app.STATE = 'prerun';

                    app.CalibrationPhase = 0;
                
                    try
                        close(app.Calibration.hFig);
                    end
                    
                    app.start_timer;

                case 'Idle'
                    app.Runtime.CommandToBg = abr.Cmd.Idle;
                    
                    app.CalibrationPhase = 3;
                    
                    if ~isempty(app.Timer) && isvalid(app.Timer)
                        stop(app.Timer);
                        delete(app.Timer);
                    end
                                        
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
            app.thisLamp = app.ReferenceLamp;
            try
                app.STATE = 'prerun';
                
                app.setup_playrec(true);
                
                Fs = str2double(app.SamplingRateDropDown.Value);
                
                Duration = 1; % seconds
                
                % add a second to be removed after acquisition
                Duration = Duration + 1;
                
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
                pause(1);
                
                app.STATE = 'running';
                app.Runtime.CommandToBg = abr.Cmd.Run;
                
                timeout(Duration+5);
                while ~timeout && app.Runtime.BackgroundState <= abr.stateAcq.ACQUIRE, pause(0.1); end
                
                if app.Runtime.BackgroundState == abr.stateAcq.ERROR
                    errordlg('An error was reported by the background process. You may need to restart Matlab and try again.', ...
                        'Mic Sensitivity','modal');
                    app.STATE = 'error';
                    return
                end
                
                if timeout
                    errordlg('The background process never completed acquiring data. You may need to restart Matlab and try again.', ...
                        'Mic Sensitivity','modal');
                    app.STATE = 'error';
                    return
                end

                
                pause(0.5);
                Y = app.Runtime.mapSignalBuffer.Data(1:app.Runtime.BufferIndex(2));
                
                % discard first second of audio in case of recording onset
                % artifact
                n = round(Fs);
                if length(Y) <= n || all(Y==0)
                    errordlg(sprintf('Something is wrong.\n\nUnable to read data from sound card.\n\nPlease try again.'),'Mic Sensitivity','modal');
                    app.STATE = 'error';
                    return
                end
                Y(1:n) = [];

                Yrms = rms(Y);
                
                % plot time & freq representations of ADC
                f = findobj('type','figure','-and','name','Reference');
                if isempty(f)
                    f = figure('name','Reference','IntegerHandle','off', ...
                        'Color','w','Position',[500 150 500 300]);
                end
                figure(f);
                clf(f);
                
                % Time-domain plot
                ax = subplot(2,4,[1 3],'Parent',f);
                [unit,multiplier] = abr.Tools.voltage_gauge(max(abs(Y)));
                tvec = 0:1/Fs:length(Y)/Fs-1/Fs;
                plot(ax,tvec([1 end])*1000,[0 0],'-k','linewidth',2);
                hold(ax,'on');
                plot(ax,tvec*1000,Y*multiplier);
                hold(ax,'off');
                
                axis(ax,'tight');
                ax.XAxis.Label.String = 'time (ms)';
                ax.YAxis.Label.String = sprintf('amplitude (%s)',unit);
                
                [unit,multiplier] = abr.Tools.voltage_gauge(Yrms);
                ax.Title.String = sprintf('Reference Tone RMS = %.3f %s RMS',Yrms*multiplier,unit);
                grid(ax,'on');
                
                
                % Zoom time-domain plot
                ax = subplot(2,4,4,'Parent',f);
                L = length(Y);
                n = round(Fs*4/app.FrequencyHzEditField.Value);
                idx = round(L/2):round(L/2)+n-1;
                zY = Y(idx);
                zT = 1000*tvec(idx);
                plot(ax,zT,zY);
                axis(ax,'tight');
                ax.XAxis.Label.String = 'time (ms)';
                grid(ax,'on');
                
                
                % Freq-domain plot
                L = length(Y);
                w = flattopwin(L);
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
                
                ax.XScale = 'linear';
                ax.XAxis.Exponent = 0;
                ax.XAxis.TickLabelFormat = '%.1f kHz';
                ax.XAxis.Label.String = 'frequency (kHz)';
                ax.YAxis.Label.String = 'Magnitude (dB)';
                
                box(ax,'on');
                grid(ax,'on');
                
                
                % zoomed freq plot
                ax = subplot(2,4,8,'Parent',f);
                
                fb = rFreq .* 2.^([-.25 .25]);
                ind = freq >= fb(1) & freq <= fb(2);
                
                h = line(ax,freq(ind),M(ind));
                line(ax,[1 1]*rFreq,ax.YLim,'linestyle','-','linewidth',2, ...
                    'color',[.6 1 .2]);
                uistack(h,'top');
                
                ax.XScale = 'log';
                ax.XAxis.Exponent = 0;
                ax.XAxis.Label.String = 'frequency (kHz)';
                axis(ax,'tight');
                
                box(ax,'on');
                grid(ax,'on');
                
                
                % Measure signal power and update field
                app.MeasuredVoltagemVEditField.Value = double(Yrms).*1000;
                app.MeasuredVoltagemVEditField.BackgroundColor = [.6 1 .2];
                
                app.STATE = 'postrun';
                
            catch me
                app.STATE = 'error';
                app.lastError = me;
                rethrow(me); % handle error message
            end
        end
        
        

        % Button pushed function: ModifyButton
        function ModifyButtonPushed(app)
            
            app.load_sig(app.SIG);
            
            opts.Resize = 'on';
            opts.WindowStyle = 'modal';
            opts.Interpreter = 'none';
            
            switch app.SIG.Type
                case 'Tone'
                    dfltAns = {app.SIG.frequency.Value};
                    prompt = ['Modify ' app.SIG.frequency.DescriptionWithUnit];
                case 'Click'
                    dfltAns = {app.SIG.duration.Value};
                    prompt = ['Modify ' app.SIG.duration.DescriptionWithUnit];
                case 'Noise'
                    dfltAns = {app.SIG.HPfreq.Value; app.SIG.LPfreq.Value};
                    prompt = {['Modify ' app.SIG.HPfreq.DescriptionWithUnit]; ['Modify ' app.SIG.LPfreq.DescriptionWithUnit]};
                case 'File'
                    dfltAns = {app.SIG.filename.Value};
                    prompt = ['Modify ' app.SIG.filename.DescriptionWithUnit];
            end
            
            
            if isnumeric(dfltAns{1}), dfltAns = cellfun(@num2str,dfltAns,'uni',0); end
            a = inputdlg(prompt,app.SIG.Type, ...
                1,dfltAns,opts);
            
            if isempty(a), return; end
            
            try
                switch app.SIG.Type
                    case 'Tone'
                        app.SIG.frequency.Value = a{1};
                    case 'Click'
                        app.SIG.duration.Value = a{1};
                    case 'Noise'
                        app.SIG.HPfreq.Value = a{1};
                        app.SIG.LPfreq.Value = a{2};
                        
                    case 'File'
                        app.SIG.filename.Value = a{1};
                end
            catch me
                h = errordlg(me.message,app.SIG.Type,'modal');
                uiwait(h);
            end
            
            app.update_ViewParameter;
        end

        function update_ViewParameter(app)
            
            switch app.SIG.Type
                case 'Tone'
                    app.ViewParameterEditField.Value = app.SIG.frequency.unitValueString;
                    app.ViewParameterEditField.Tooltip = app.SIG.frequency.Description;
                case 'Click'
                    app.ViewParameterEditField.Value = app.SIG.duration.unitValueString;
                    app.ViewParameterEditField.Tooltip = app.SIG.duration.Description;
                case 'Noise'
                    HP = app.SIG.HPfreq.Evaluated; 
                    LP = app.SIG.LPfreq.Evaluated;
                    HPs = [app.SIG.HPfreq.ValueFormat ' ' app.SIG.HPfreq.Unit];
                    LPs = [app.SIG.LPfreq.ValueFormat ' ' app.SIG.LPfreq.Unit];
                    s = [HPs ' - ' LPs];
                    s = sprintf([s ','],HP,LP);
                    s(end) = [];
                    app.ViewParameterEditField.Value = s;
                    app.ViewParameterEditField.Tooltip = {app.SIG.HPfreq.Description; app.SIG.LPfreq.Description};
                    
                case 'File'
                    app.ViewParameterEditField.Value = app.SIG.filename.Value;
                    app.ViewParameterEditField.Tooltip = app.SIG.filename.Description;
            end
            
        end
        
        
        
        
        
        % Menu selected function: SaveCalibrationDataMenu
        function SaveCalibrationDataMenuSelected(app)
            if ~app.Calibration.calibration_is_valid
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
            
%             Calibration = app.SIG.Calibration; %#ok<ADPROP> % ????
            Calibration = app.Calibration; %#ok<ADPROP>
            
            save(ffn,'Calibration','-mat');
            
            setpref('SoundCalibration','dataPath',pn);
        end

        % Menu selected function: LoadCalibrationDataMenu
        function LoadCalibrationDataMenuSelected(app)
            dfltpn = getpref('SoundCalibration','dataPath',cd);
            [fn,pn] = uigetfile({'*.cal','Calibration (*.cal)'}, ...
                'Load Calibration Data', ...
                dfltpn,'MultiSelect','off');
            
            if isequal(fn,0), return; end
            
            ffn = fullfile(pn,fn);
            
            fprintf('Loading %s\n',ffn)
            
            load(ffn,'Calibration','-mat');
            
            app.Calibration = Calibration; %#ok<ADPROP>
%             app.SIG.Calibration = Calibration; %#ok<ADPROP> % ?????
            
            fprintf('\tCalibration from: %s\n',app.Calibration.Timestamp);
            
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

            % update infoData with channel ids
            app.Runtime.update_infoData('DACsignalCh',1);
            app.Runtime.update_infoData('DACtimingCh',2);
            app.Runtime.update_infoData('ADCsignalCh',1);
            app.Runtime.update_infoData('ADCtimingCh',2);


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
            
            vprintf(3,'time_Start:Calibration Phase = %d',app.CalibrationPhase)

            app.setup_stimulus;
            
            app.setup_playrec;

            % TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!
%             app.Runtime.CommandToBg = abr.Cmd.Test;
            % TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!TEST MODE!!!!
            
            % get the plot ready
            app.Calibration = app.Calibration.plot(app.SIG,app.CalibrationPhase);

            figure(app.Calibration.hFig);
            
            app.STATE = 'running';
            app.Runtime.CommandToBg = abr.Cmd.Run;
        end

        function timer_Runtime(T,event,app)
            try
                vprintf(4,'time_Runtime:Calibration Phase = %d',app.CalibrationPhase)
            if app.CalibrationPhase == 0, return; end
            
            mC  = app.Runtime.mapCom;
            mSB = app.Runtime.mapSignalBuffer;
            mTB = app.Runtime.mapTimingBuffer;
            BH = double(mC.Data.BufferIndex(2));
            LB = app.Calibration.ADC.N;
            if LB == 0, LB = 1; end


            % gather data from background process
            switch app.Runtime.BackgroundState
                case abr.stateAcq.COMPLETED
                    app.Calibration.ADC.Data = mSB.Data(1:BH);
                    app.Calibration.ADC.SweepOnsets = app.Runtime.find_timing_onsets(1,BH);
                    stop(T);
                    return
                    
                case abr.stateAcq.ACQUIRE
                    data = mSB.Data(LB:BH);
                    app.Calibration.ADC = app.Calibration.ADC.appendData(data);
                    
                    % find stimulus onsets in timing signal
                    idx = app.Runtime.find_timing_onsets(LB,BH);
                    if isempty(idx), return; end
                    app.Calibration.ADC.SweepOnsets(end+1:end+length(idx)) = idx;
                    
                    
                case abr.stateAcq.ERROR
                    errordlg('Dang it! Background Process Threw an Error!','Error','modal');
                    stop(T);
                    return
            end
            
            vprintf(4,'# sweeps acquired = %d',app.Calibration.ADC.NumSweeps)
            
            
            app.Calibration = app.Calibration.plot(app.SIG,app.CalibrationPhase);
            
            catch me
                rethrow(me)
            end
        end

        function timer_Stop(T,event,app)
            vprintf(4,'time_Stop:Calibration Phase = %d',app.CalibrationPhase)

            app.Calibration = app.Calibration.plot(app.SIG,app.CalibrationPhase);

            if app.CalibrationPhase == 1
                adjV = app.Calibration.compute_adjusted_voltage;
                ind = adjV > 1 | adjV <= 0;
                if any(ind)
                    errordlg(sprintf('%d stimuli have an adjusted voltage <= 0 or > 1!',sum(ind)));
                    app.STATE = 'error';
                end
                app.Calibration.NormVoltage       = adjV;
                app.Calibration.CalibratedVoltage = adjV;
%                 app.Calibration.StimulusVoltage   = adjV;

                app.SIG.Calibration = app.Calibration;
                
                app.start_timer; % start second phase
            else
                vprintf(1,'Completed calibration')
                app.STATE = 'postrun';

                app.SIG.Calibration.CalibratedVoltage = app.SIG.Calibration.NormVoltage;
                
                if ~isequal(app.STATE,'error')
                    app.SaveCalibrationDataMenuSelected;
                end
            end
        end

        function timer_Error(T,event,app)
            app.Runtime.CommandToBg = abr.Cmd.Error;
            app.CalibrationPhase = 0;
            app.STATE = 'error';
            s = abr.Tools.stack_str(5);
            s = strrep(s,'\','\\');
            vprintf(1,1,sprintf('Calibration Error Occurred\n%s\n\tmessageID: %s\n\tmessage: %s', ...
                s,event.Data.messageID,event.Data.message))
        end
    end

end