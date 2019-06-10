classdef RMS < abr.analysis.Analysis
    
    properties
        SweepLevel  (1,1) logical = true;
        
        Mean
        Std
        Max
        Min
    end
    
    properties (Constant)
        Type = 'RMS';
    end
    
    methods
        function obj = RMS(data,Fs)
            if nargin < 1, data = []; end
            if nargin < 2, Fs = 1;    end
            obj.Data = data;
            obj.Fs   = Fs;
        end
        
       
        function obj = compute(obj)
            if obj.SweepLevel
                r = rms(obj.Data,obj.SampleDim);
                obj.Mean = mean(r);
                obj.Std  = std(r);
                obj.Max  = max(r);
                obj.Min  = min(r);
            else
                obj.Mean = rms(mean(obj.Data,obj.SampleDim));
                obj.Std  = nan;
                obj.Max  = obj.Mean;
                obj.Min  = obj.Mean;
            end
            
            obj.Result = obj.Mean;
        end
    end
    
end