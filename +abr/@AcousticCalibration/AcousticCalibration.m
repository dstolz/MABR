classdef AcousticCalibration
    
    
    properties
        filename      (1,:) char
        
        
        Device        (1,:) char
        DeviceInfo
        SampleRate    (1,1) double {mustBePositive,mustBeFinite} = 44100;
        BitDepth      (1,1) uint8  {mustBePositive,mustBeLessThanOrEqual(BitDepth,64)} = 24;
        
        ReferenceFreq (1,1) double {mustBePositive,mustBeFinite} = 1000; % Hz
        ReferenceSPL  (1,1) double {mustBePositive,mustBeFinite} = 114; % dB SPL
        ReferenceV    (1,1) double {mustBePositive,mustBeFinite} = 0.1;
        
        StimulusV     (1,1) double {mustBePositive,mustBeFinite,mustBeLessThanOrEqual(StimulusV,1)} = 1;
                
        SIG    
        
        DAC           (1,1) Buffer
        ADC           (1,1) Buffer
        
        Timestamp
        
        Note
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
    end
    
    methods (Access = private)
        
    end
    
    methods (Static)
        
    end
    
end