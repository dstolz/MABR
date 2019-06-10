classdef CorrCoef < abr.analysis.Analysis
    
    properties
        MaxSweeps (1,1) double {mustBePositive,mustBeInteger} = 2^11;
    end
    
    properties (SetAccess = private)
        R
        P
        Rlower
        Rupper
        Z
    end
    
    properties (Constant)
        Type = 'CorrCoef';
    end
    
    methods
        function obj = CorrCoef(data,Fs)
            if nargin < 1, data = []; end
            if nargin < 2, Fs = 1;    end
            obj.Data = data;
            obj.Fs   = Fs;
        end
        
       
        function obj = compute(obj)
            data = obj.Data;
            
            if obj.SampleDim == 2, data = data'; end
            
            n = min([obj.NumSweeps obj.MaxSweeps]);
            i = randperm(obj.NumSweeps,n);
            if obj.SweepDim == 1
                data = data(i,:);
            else
                data = data(:,i);
            end
                
            [rm,p,rlo,rup] = corrcoef(data);
            r = rm(tril(true(size(rm)),-1));
            
            obj.Result = mean(r,'all');
            
            obj.R = rm;
            obj.P = p;
            obj.Rlower = rlo;
            obj.Rupper = rup;
            
            obj.Z = 0.5.*(log(1+rm) - log(1-rm)); % Fischer's Z-transform
        end
    end
    
end