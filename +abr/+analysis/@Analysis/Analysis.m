classdef (Abstract) Analysis
    
    properties
        Data        double
        TimeVector  double
        
        Fs (1,1) double {mustBePositive,mustBeFinite} = 1;
        SampleDim (1,1) double {mustBeMember(SampleDim,[1,2])} = 1;
    end
    
    properties (Dependent)        
        NumSamples (1,1)
        NumSweeps  (1,1)
        
        SweepDim   (1,1)
    end
    
    
    properties (SetAccess = protected)
        Result
        Unit      (:,1) cell % corresponds to rows in Result
    end
    
    methods
        function obj = Analysis()
            
        end
        
%         function R = get.Result(obj)
%             obj = obj.compute;
%         end
        
        function obj = set.TimeVector(obj,tvec)
            assert(size(tvec,obj.SampleDim)==obj.NumSamples, ...
                'TimeVector must have the same length as the dimension %d of Data which = %d', ...
                obj.SampleDim,obj.NumSamples);
        end
        
        function d = get.SweepDim(obj)
            if obj.SampleDim == 1
                d = 2;
            else
                d = 1;
            end
        end
        
        function n = get.NumSamples(obj)
            n = size(obj.Data,obj.SampleDim);
        end
        
        function n = get.NumSweeps(obj)
            n = size(obj.Data,obj.SweepDim);
        end
    end
    
    
end