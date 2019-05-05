classdef ABR
% ABR
% 
% Daniel Stolzberg, PhD (c) 2019
    properties
        DAC           (1,1) abr.Buffer
        ADC           (1,1) abr.Buffer
%         Calibration   (1,1) abr.AcousticCalibration
        SIG           (1,1) % abr.sigdef.sigs....
                
        adcDecimationFactor (1,1) {mustBeInteger,mustBePositive} = 4;
        
        audioDevice   (1,:) char
        
        altPolarity   (1,1) logical = false;
        
        sweepRate     (1,1) double {mustBePositive, mustBeFinite}   = 21.1; % Hz
        numSweeps     (1,1) double {mustBeInteger,  mustBePositive} = 1024;
        eventOnset    (1,1) double {mustBePositive, mustBeFinite}   = 0.1; % seconds
        
        adcWindow     (1,2) double {mustBeFinite} = [0 0.015]; % seconds
        
        adcFilterOrder (1,1) double {mustBePositive,mustBeInteger} = 10;
        adcFilterHP    (1,1) double {mustBePositive,mustBeFinite}  = 10; % Hz
        adcFilterLP    (1,1) double {mustBePositive,mustBeFinite}  = 3000; % Hz
        
        adcNotchFilterFreq (1,1) double {mustBePositive,mustBeFinite} = 60; % Hz
        
        adcUseBPFilter    (1,1) logical = true;
        adcUseNotchFilter (1,1) logical = true;
        
    end
    
    properties (SetAccess = private)
        APR

        

        adcFilterDesign;
        adcNotchFilterDesign
        
        sweepCount = 1;
        

    end
    
    
    
    methods   
        obj = playrec(obj,app,ax,varargin);
        obj = selectAudioDevice(obj,deviceString);
        obj = prepareSweep(obj);
        r = analysis(obj,type,varargin);
        
        % Constructor
        function obj = ABR
            % Make sure MATLAB is running at full steam
            [s,w] = dos('wmic process where name="MATLAB.exe" CALL setpriority 128'); % 128 = High
            if s ~=0
                warning('Failed to elevate the priority of MATLAB.exe')
                disp(w)
            end
            

        end
        
        % Destructor
        function delete(obj)
            try
               delete(obj.APR); 
               delete(obj.adcFilterDesign);
            catch me
                
            end
        end
        
        
        
        
       
        
        % DAC -------------------------------------------------------------
     
        
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
        
        function obj = set.adcWindow(obj,win)
            assert(numel(win) == 2,'adcWindow must have two values');
            
            win = sort(win);
%             assert(win(1) <= 0 & win(2) >= obj.DAC.SweepDuration, ...
%                 'adcWindow must be at least the duration of the dac buffer'); %#ok<MCSUP>
            obj.adcWindow = win;
        end
        
        
        function obj = set.adcFilterHP(obj,f)
            assert(f < obj.adcFilterLP,'adcFilterHP must be lower than adcFilterLP'); %#ok<MCSUP>
            assert(f < obj.ADC.SampleRate/2,sprintf('Filter must be below Nyquist rate = %.3f Hz',obj.ADC.SampleRate/2));  %#ok<MCSUP>
            obj.adcFilterHP = f;
        end
        
        function obj = set.adcFilterLP(obj,f)
            assert(f > obj.adcFilterHP,'adcFilterLP must be higher than adcFilterHP'); %#ok<MCSUP>
            assert(f < obj.ADC.SampleRate/2,sprintf('Filter must be below Nyquist rate = %.3f Hz',obj.ADC.SampleRate/2));  %#ok<MCSUP>
            obj.adcFilterLP = f;
        end
        
        function obj = set.adcFilterOrder(obj,order)
            obj.adcFilterOrder = order;
        end
        
    end
    
end