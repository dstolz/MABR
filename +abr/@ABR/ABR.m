classdef ABR < abr.Universal & handle
% ABR
% 
% Daniel Stolzberg, PhD (c) 2019
    properties
        DAC           (1,1) abr.Buffer
        ADC           (1,1) abr.Buffer
        
        DACtiming     (1,1) abr.Buffer
        ADCtiming     (1,1) abr.Buffer
        
%         Calibration   (1,1) abr.AcousticCalibration
        SIG           (1,1) % abr.sigdef.sigs....
                
        adcDecimationFactor (1,1) {mustBeInteger,mustBePositive} = 1;
        
        audioDevice   (1,:) char
        
        altPolarity   (1,1) logical = false;
        
        sweepRate     (1,1) double {mustBePositive, mustBeFinite}   = 21.1; % Hz
        numSweeps     (1,1) double {mustBeInteger,  mustBePositive} = 1024;
        
        adcWindow     (1,2) double {mustBeFinite} = [0 0.015]; % seconds
        
        adcFilterOrder (1,1) double {mustBePositive,mustBeInteger} = 10;
        adcFilterHP    (1,1) double {mustBePositive,mustBeFinite}  = 10; % Hz
        adcFilterLP    (1,1) double {mustBePositive,mustBeFinite}  = 3000; % Hz
        
        adcNotchFilterFreq (1,1) double {mustBePositive,mustBeFinite} = 60; % Hz
        
        adcUseBPFilter    (1,1) logical = true;
        adcUseNotchFilter (1,1) logical = true;
        
        ADCsignalCh   (1,1) uint8 {mustBePositive,mustBeInteger} = 1;
        ADCtimingCh   (1,1) uint8 {mustBePositive,mustBeInteger} = 2;
        DACsignalCh   (1,1) uint8 {mustBePositive,mustBeInteger} = 1;
        DACtimingCh   (1,1) uint8 {mustBePositive,mustBeInteger} = 2;
        
        
        DACfilename = fullfile(abr.Universal.root,'current_ABR_stimulus.wav');
        ADCfilename = fullfile(abr.Universal.root,'current_ABR_acquisition.wav');
        
        chunkSize = 5e6; % make this big
        
    end
    
    properties (SetAccess = private)
        RUNTIME     abr.Runtime
        APR

        adcFilterDesign;
        adcNotchFilterDesign
        
        adcWindowSamps
        
        runningMean = [];
        timingCursor
    end
    
    properties (SetAccess = private, Dependent)
        sweepCount
        
    end
    
    
    methods   
        obj = playrec(obj,app,ax,varargin);
        obj = selectAudioDevice(obj,deviceString);
        setupAudioChannels(obj);
        obj = prepareSweep(obj);
        r = analysis(obj,type,varargin);
        
        % Constructor
        function obj = ABRstartup

        end
        
        % Destructor
        function delete(obj)
            try
               delete(obj.APR); 
               delete(obj.adcFilterDesign);
            catch me
                
            end
        end
        
        
         function launch_process(obj)
            % setup Background process
            cmdStr = sprintf(['addpath(''%s''); ABRstartup; H = abr.Runtime(''Background'')'], ...
                fileparts(obj.root));
            
            [s,w] = dos(sprintf('"%s" -sd "%s" -logfile "%s" -noFigureWindows -nosplash -nodesktop -nodisplay -r "%s"', ...
                obj.matlabExePath,obj.runtimePath,fullfile(obj.runtimePath,'Background_process_log.txt'),cmdStr));
        end
                
        % DACtiming -------------------------------------------------------
        function obj = initTimingSignal(obj)
            obj.DACtiming = obj.DAC; % copy obj.DAC buffer
            
            % send an impulse at the onset of each sweep
            timingSignal(obj.DAC.N,1) = 0;
            timingSignal(obj.DACtiming.SweepOnsets) = 1;
            
            obj.DACtiming.Data = timingSignal;
            
            obj.ADCtiming.Data = zeros(size(timingSignal));
            obj.ADCtiming.SweepOnsets = zeros(size(obj.DACtiming.SweepOnsets));
                        
            obj.timingCursor = 1;
            
            obj.runningMean = [];
        end
        
        
        
        function idx = timing_onsets(obj)
            
            % find rising edges in timing signal
            D = obj.ADCtiming.Data;
            
            cs = obj.chunkSize;
            tc = obj.timingCursor;
            if tc + cs > length(D), cs = length(D) - tc; end
            
            ls = tc+cs;
            
            ind = D(tc:ls-1) > D(tc+1:ls);
            ind = ind & D(tc:ls-1) >= 0.5; % threshold
            
            idx = tc + find(ind)-1;
            
            if isempty(idx), return; end

            nidx = find(obj.ADCtiming.SweepOnsets==0,1);
            k = nidx:nidx+length(idx)-1;
            obj.ADCtiming.SweepOnsets(k) = idx;
            obj.ADC.SweepOnsets(k) = round(idx./obj.adcDecimationFactor);
            
            obj.timingCursor = idx(end)+1;
            
        end
        
        function samps = timing_samples(obj)
            aFs = obj.DAC.SampleRate;
            bFs = obj.ADC.SampleRate;
                        
            tons  = floor(bFs.*(obj.timing_onsets./aFs)); % DAC Fs -> ADC Fs
            
            samps = tons + obj.adcWindowSamps; % matrix expansion
            
            % clip any sweeps that are beyond the end of the ADC buffer
            samps(any(samps>obj.ADC.N,2),:) = [];
        end
        
        
        function m = adc_mean(obj)
            
            D = obj.ADC.Data';
            
            samps = obj.timing_samples;
            
            if isempty(samps)
                m = obj.runningMean;
                return
            end
            
            y = D(samps);
            m = mean(y,1);
            
            if ~isempty(obj.runningMean) && ~all(isnan(obj.runningMean))
                sc = obj.sweepCount;    
                y = obj.runningMean .* sc;
                n = size(samps,1);
                m = (y + n.*m)./ (sc+n);
            end
            obj.runningMean = m;
            
        end
        
        function c = get.sweepCount(obj)
            c = find(obj.ADC.SweepOnsets==0,1)-1;
        end
        
        
        % ADC -------------------------------------------------------------
        function obj = createADCfilt(obj)
            
            if isa(obj.adcFilterDesign,'digitalFilter')
                % don't bother replacing filter design if relevant
                % parameters are unchanged
                a(1) = obj.adcFilterDesign.FilterOrder == obj.adcFilterOrder;
                a(2) = obj.adcFilterDesign.CutoffFrequency1 == obj.adcFilterHP;
                a(3) = obj.adcFilterDesign.CutoffFrequency2 == obj.adcFilterLP;
                a(4) = obj.adcFilterDesign.SampleRate == obj.ADC.SampleRate;
                if all(a), return; end
            end
            
            
            % create ADC bandpassfilter
            % NOTE: properties can not be updated dynamically
            obj.adcFilterDesign = designfilt('bandpassfir', ...
                'FilterOrder',     obj.adcFilterOrder, ...
                'CutoffFrequency1',obj.adcFilterHP, ...
                'CutoffFrequency2',obj.adcFilterLP, ...
                'SampleRate',      obj.ADC.SampleRate);
            
            % Notch filter
            obj.adcNotchFilterDesign = designfilt('bandstopfir', ...
                'FilterOrder',10, ...
                'CutoffFrequency1',obj.adcNotchFilterFreq-1, ...
                'CutoffFrequency2',obj.adcNotchFilterFreq+1, ...
                'SampleRate',      obj.ADC.SampleRate);
        end
        
        function set.adcWindow(obj,win)
            assert(numel(win) == 2,'adcWindow must have two values');
            
            win = sort(win);
%             assert(win(1) <= 0 & win(2) >= obj.DAC.SweepDuration, ...
%                 'adcWindow must be at least the duration of the dac buffer'); %#ok<MCSUP>
            obj.adcWindow = win;
        end
        
        function s = get.adcWindowSamps(obj)
            bFs = obj.ADC.SampleRate;
            s = floor(bFs.*obj.adcWindow(1)):ceil(bFs.*obj.adcWindow(2));
        end
        
        function set.adcFilterHP(obj,f)
            assert(f < obj.adcFilterLP,'adcFilterHP must be lower than adcFilterLP'); %#ok<MCSUP>
            assert(f < obj.ADC.SampleRate/2,sprintf('Filter must be below Nyquist rate = %.3f Hz',obj.ADC.SampleRate/2));  %#ok<MCSUP>
            obj.adcFilterHP = f;
        end
        
        function set.adcFilterLP(obj,f)
            assert(f > obj.adcFilterHP,'adcFilterLP must be higher than adcFilterHP'); %#ok<MCSUP>
            assert(f < obj.ADC.SampleRate/2,sprintf('Filter must be below Nyquist rate = %.3f Hz',obj.ADC.SampleRate/2));  %#ok<MCSUP>
            obj.adcFilterLP = f;
        end
        
        function set.adcFilterOrder(obj,order)
            obj.adcFilterOrder = order;
        end
        
    end
    
end