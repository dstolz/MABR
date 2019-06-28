classdef SoundCalibration < matlab.mixin.Copyable
    
    
    properties        
        Device        (1,:) char
        DeviceInfo

        BitDepth      (1,1) uint8  {mustBePositive,mustBeLessThanOrEqual(BitDepth,64)} = 24;
        
        ReferenceFreq (1,1) double {mustBePositive,mustBeFinite} = 1000; % Hz
        ReferenceSPL  (1,1) double {mustBePositive,mustBeFinite} = 114; % dB SPL
        ReferenceVoltage  (1,1) double {mustBePositive,mustBeFinite} = 0.1;
        
        CalibratedParameter (1,:) char
        
        StimulusVoltage   (:,1) double {mustBePositive,mustBeFinite,mustBeLessThanOrEqual(StimulusVoltage,1)} = 1;
           
        MeasuredVoltage   (:,1) double {mustBeFinite,mustBePositive}
        MeasuredSPL       (:,1) double {mustBeFinite}
        
        CalibratedValues  (:,1) 
        CalibratedVoltage (:,1) double {mustBePositive} %,mustBeLessThanOrEqual(CalibratedVoltage,1)}
        
        
        NormDB            (1,1) double {mustBePositive,mustBeFinite} = 80; % dB SPL
        NormalizedVoltage (:,1) double {mustBeFinite,mustBePositive}
        
        InterpMethod  (1,:) char {mustBeMember(InterpMethod,{'linear','nearest','next','previous','pchip','cubic','v5cubic','makima','spline'})} = 'nearest';
        CalcWindow    (1,2) double {mustBeNonnegative,mustBeFinite} = [0 1];
        
        DAC           (1,1) abr.Buffer
        ADC           (1,1) abr.Buffer
                
        Note          (1,:) char
    end

    properties (NonCopyable, Transient)
        FigCalibration
    end
    
    
    properties (SetAccess = private,Dependent)
        CalStats
    end

    properties (Access = private, NonCopyable, Transient)
        axSL
        axTD
        axFD 
    end
    
    properties (SetAccess = immutable)
        Timestamp = datestr(now);
    end
    
    methods
        obj = plot_calibration(obj,phase);

        % Constructor
        function obj = SoundCalibration
            
        end
        
        function fs = set.Fs(obj,Fs)
            obj.Fs = Fs;
            obj.DAC.SampleRate = Fs;
            obj.ADC.SampleRate = Fs;
        end
        
        function v = get.MeasuredVoltage(obj)
            v = nan;
            y = obj.ADC.SweepData;
            if isempty(y), return; end
            idx = obj.analysis_idx;
            if isequal(idx(1),0), return; end
            v = rms(y(idx,:));
        end
        
        function dB = get.MeasuredSPL(obj)
            % compute calibrated SPL of recorded stimuli
            dB = 20 .* log10(obj.MeasuredVoltage ./ obj.ReferenceVoltage) + obj.ReferenceSPL;
        end
        

        function v = compute_calibrated_voltage(obj,targetSPL)
            % compute the voltage to produce a target sound level (dB SPL)
            v = obj.CalibratedVoltage .* 10 .^ ((targetSPL - obj.NormDB) ./ 20);
        end
        
        function v = compute_adjusted_voltage(obj)
            % compute voltage to produce sound level at the NormDB value
            v  = obj.StimulusVoltage(:) .* 10 .^ ((obj.NormDB - obj.MeasuredSPL(:)) ./ 20); 
        end
        




        function v = estimate_calibrated_voltage(obj,values,targetSPL)
            y = obj.compute_calibrated_voltage(targetSPL);
            x = obj.(obj.CalibratedParameter).realValue;
            
            if ismember(obj.InterpMethod,{'pchip','spline','cubic'}) && length(x) < 4
                warning('Selected interpolation method is "%s", but there are too few points.\nSwitching to "makima" method.',obj.InterpMethod);
                obj.InterpMethod = 'makima';
            end
            if any(values > max(x) | values < min(x))
                warning('Value outside calibrated range.  Extrapolating calibration value!');
            end
            v = interp1(x,y,values,obj.InterpMethod,'extrap');            
        end
        





        function S = get.CalStats(obj)
            
            S.CalibratedParameter = obj.CalibratedParameter;
            S.CalibratedValues    = obj.CalibratedValues;

            S.MeasuredSPL = obj.MeasuredSPL;
            S.NormDB      = obj.NormDB;
            S.Diff        = S.MeasuredSPL - S.NormDB;
            S.absDiff     = abs(S.Diff);
            S.Mean        = mean(S.absDiff);
            S.Median      = median(S.absDiff);
            S.Max         = max(S.absDiff);
            S.Min         = min(S.absDiff);
            S.Std         = std(S.absDiff);
            S.N           = length(S.Diff);
            S.SEM         = S.Std./sqrt(S.N);
            
%             [r,harmpow,harmfreq] = obj.thd;
%             S.THD.R = r;
%             S.THD.HarmPow = harmpow;
%             S.THD.HarmFreq = harmfreq;
        end








        
        function r = calibration_is_valid(obj)
            r = ~(all(isnan(obj.MeasuredVoltage)) || isempty(obj.CalibratedVoltage));
        end



    
        
    end
    
    methods (Access = private)
        function idx = analysis_idx(obj)
            idx = round(obj.CalcWindow(1).*obj.ADC.SampleRate):round(obj.CalcWindow(2).*obj.ADC.SampleRate);
        end
        
    end
    
    methods (Static)
        
    end
    
end