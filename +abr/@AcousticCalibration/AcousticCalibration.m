classdef AcousticCalibration
    
    
    properties
        filename      (1,:) char
        timestamp
        
        Device        (1,:) char
        DeviceInfo
        SampleRate    (1,1) double {mustBePositive,mustBeFinite} = 44100;
        BitDepth      (1,1) uint8  {mustBePositive,mustBeLessThanOrEqual(BitDepth,64)} = 24;
        
        ReferenceFreq (1,1) double {mustBePositive,mustBeFinite} = 1000; % Hz
        ReferenceSPL  (1,1) double {mustBePositive,mustBeFinite} = 114; % dB SPL
        ReferenceV    (1,1) double {mustBePositive,mustBeFinite} = 0.1;
        
        StimulusV     (1,1) double {mustBePositive,mustBeFinite,mustBeLessThanOrEqual(StimulusV,1)} = 1;
           
        CalibratedV   (:,1) double {mustBePositive,mustBeLessThanOrEqual(CalibratedV,1)}
        
        MeasuredV     (:,1) double {mustBeFinite,mustBePositive}
        MeasuredSPL   (:,1) double {mustBeFinite}
        
        
        NormDB        (1,1) double {mustBePositive,mustBeFinite} = 80; % dB SPL
        NormalizedV   (:,1) double {mustBeFinite,mustBePositive}
        
        CalcWindow    (1,2) double {mustBeNonnegative,mustBeFinite} = [0 1];
        
        SIG           (1,1)
        
        DAC           (1,1) Buffer
        ADC           (1,1) Buffer
        
        
        
        Note
    end
    
    properties (SetAccess = private,Dependent)
        
    end
    
    methods
        % Constructor
        function obj = AcousticCalibration
            
        end
        
        function obj = set.SampleRate(obj,Fs)
            obj.DAC.SampleRate = Fs;
            obj.ADC.SampleRate = Fs;
            obj.SampleRate = Fs;
        end
        
        function v = get.MeasuredV(obj)
            y = obj.ADC.SweepData;
            v = rms(y(obj.analysis_idx,:));
        end
        
        function dB = get.MeasuredSPL(obj)
            % compute calibrated SPL of recorded stimuli
            dB = 20 .* log10(obj.MeasuredV ./ obj.ReferenceV) + obj.ReferenceSPL;
        end
        

        function v = computeCalibratedV(obj,targetSPL)
            % compute the voltage to produce a target sound level (dB SPL)
            v = obj.CalibratedV .* 10 .^ ((targetSPL - obj.NormDB) ./ 20);
        end
        
        function v = computeAdjV(obj)
            % compute voltage to produce sound level at the NormDB value
            v  = obj.StimulusV .* 10 .^ ((obj.NormDB - obj.MeasuredSPL) ./ 20); 
        end
    end
    
    methods (Access = private)
        function idx = analysis_idx(obj)
            idx = round(obj.CalcWindow(1).*obj.SampleRate):round(obj.CalcWindow(2).*obj.SampleRate);
        end
        
    end
    
    methods (Static)
        
    end
    
end