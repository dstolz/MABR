classdef ABR < handle % & abr.Universal 
% ABR
% 
% Daniel Stolzberg, PhD (c) 2019
    properties
        DAC           (1,1) abr.Buffer
        ADC           (1,1) abr.Buffer
        
        SIG           (1,1) % abr.sigdef.sigs....
                
        adcDecimationFactor (1,1) {mustBeInteger,mustBePositive} = 1;
        
        audioDevice   (1,:) char
        
        altPolarity   (1,1) logical = false;
        
        sweepRate     (1,1) double {mustBePositive, mustBeFinite}   = 21.1; % Hz
        numSweeps     (1,1) double {mustBeInteger,  mustBePositive} = 1024;
        
        adcWindow     (1,2) double {mustBeFinite} = [0 0.01]; % seconds
        
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
        

        
        analysisSettings (2,:) cell = {'rms'; []};

    end
    
    properties (Hidden)
        % get copied to Runtime ????
        AFR     % dsp.AudioFileReader
        APR     % audioPlayerRecorder
    end
    
    properties (SetAccess = private)
        adcFilterDesign;
        adcNotchFilterDesign
    end
    
    properties (SetAccess = private, Dependent)
        sweepCount
        adcWindowTVec
    end
    
    methods   
        obj = selectAudioDevice(obj,deviceString);
        setupAudioChannels(obj);
        r = analysis(obj,type,varargin);
        
        % Constructor
        function obj = ABR()

        end
        
        % Destructor
        function delete(obj)
            try
               delete(obj.adcFilterDesign);
            catch me
                
            end
        end
        


       
        
        
        function n = get.sweepCount(obj)
            n = length(obj.ADC.SweepOnsets);
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
        
        
        function tvec = get.adcWindowTVec(obj)
            tvec = obj.adcWindow(1):1/obj.ADC.SampleRate:obj.adcWindow(2);
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