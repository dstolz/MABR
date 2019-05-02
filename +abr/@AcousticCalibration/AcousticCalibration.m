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
        
        StimulusV     (:,1) double {mustBePositive,mustBeFinite,mustBeLessThanOrEqual(StimulusV,1)} = 1;
           
        CalibratedV   (:,1) double {mustBePositive,mustBeLessThanOrEqual(CalibratedV,1)}
        
        MeasuredV     (:,1) double {mustBeFinite,mustBePositive}
        MeasuredSPL   (:,1) double {mustBeFinite}
        
        
        NormDB        (1,1) double {mustBePositive,mustBeFinite} = 80; % dB SPL
        NormalizedV   (:,1) double {mustBeFinite,mustBePositive}
        
        CalParam      (1,:) char
        CalInterpMethod (1,:) char {mustBeMember(CalInterpMethod,{'linear','nearest','next','previous','pchip','cubic','v5cubic','makima','spline'})} = 'makima';
        CalcWindow    (1,2) double {mustBeNonnegative,mustBeFinite} = [0 1];
        
        SIG           (1,1)
        
        DAC           (1,1) Buffer
        ADC           (1,1) Buffer
        
        
        Note
    end
    
    properties (SetAccess = private,Dependent)
        CalStats
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
        
        function v = computeAdjustedV(obj)
            % compute voltage to produce sound level at the NormDB value
            v  = obj.StimulusV(:) .* 10 .^ ((obj.NormDB - obj.MeasuredSPL(:)) ./ 20); 
        end
        
        function v = estimateCalibratedV(obj,value,targetSPL)
            y = obj.computeCalibratedV(targetSPL);
            x = obj.SIG.(obj.CalParam).realValue;
            
            v = nan(size(x));
            
            switch obj.SIG.CalibrationType
                case 'lut'
                    if ~isequal(value,x)
                        me = MException([mfilename '.estimateCalibratedV:value'], ...
                            'Only one value was calibrated so we can''t interpolate or guess the correct calibration value.');
                        throw(me);
                    end
                    v = y(x == value);
                    
                case 'interp'
                    if ismember(obj.CalParam,{'pchip','spline','cubic'}) && length(x) < 4
                        warning('Selected interpolation method is "%s", but there are too few points.\nSwitching to "makima" method.',obj.CalInterpMethod);
                        obj.CalInterpMethod = 'makima';
                    end
                    if any(value > max(x) | value < min(x))
                        warning('Value outside calibrated range.  Extrapolating calibration value!');
                    end
                    v = interp1(x,y,value,obj.CalInterpMethod,'extrap');
            end
            
        end
        
        function S = get.CalStats(obj)
            
            S.CalibratedParameter = obj.CalParam;
            S.CalibratedValues    = obj.SIG.(obj.CalParam).realValue;
            
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
            
            [r,harmpow,harmfreq] = obj.thd;
            S.THD.R = r;
            S.THD.HarmPow = harmpow;
            S.THD.HarmFreq = harmfreq;
        end
        
        
        function varargout = thd(obj)
            if nargout == 0
%                 thd(obj.ADC.SweepData,obj.ADC.SampleRate,5);
                % should setup to plot
                
            else
                for i = 1:obj.ADC.NumSweeps
                    [r(1,i),harmpow(:,i),harmfreq(:,i)] = thd(obj.ADC.SweepData(:,i),obj.ADC.SampleRate,5);
                end
                varargout{1} = r;
                varargout{2} = harmpow;
                varargout{3} = harmfreq;
            end
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