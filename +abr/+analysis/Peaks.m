classdef Peaks < abr.analysis.Analysis
    
    properties
        Polarity (1,1) double {mustBeMember(Polarity,[-1, 1])}   = 1;
        NumPeaks (1,1) double {mustBePositive,mustBeFinite}     = 6;
        Threshold       (1,1) double {mustBeNonnegative}        = 0;
        MinPeakDistance (1,1) double {mustBeNonnegative}        = 10;
        MinPeakWidth    (1,1) double {mustBeNonnegative}        = 0;
        MaxPeakWidth    (1,1) double {mustBePositive}           = inf;
    end
    
    properties (SetAccess = private)
        PkAmplitude
        PkLocation
        PkWidth
        PkProminence
    end
    
    properties (Constant)
        Type = 'Peaks';
    end
    
    methods
        function obj = Peaks(data,Fs)
            if nargin < 1, data = []; end
            if nargin < 2, Fs = 1;    end
            obj.Data = data;
            obj.Fs   = Fs;
            obj.Unit = {'V','s','s','V'};
        end
        
        
        function obj = compute(obj)
            [pks,locs,w,p] = findpeaks( ...
                obj.Polarity*mean(obj.Data,obj.SampleDim), ...
                'NPeaks',obj.NumPeaks, ...
                'Threshold',obj.Threshold, ...
                'MinPeakDistance',obj.MinPeakDistance, ...
                'MinPeakWidth',obj.MinPeakWidth, ...
                'MaxPeakWidth',obj.MaxPeakWidth);
            
            obj.PkAmplitude  = obj.Polarity*pks;
            obj.PkLocation   = locs;
            obj.PkWidth      = w;
            obj.PkProminence = p;
            
            obj.Result = obj.PkAmplitude;
        end
    end
    
end