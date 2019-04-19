classdef Trace
    
    properties
        SampleRate      (1,1) {mustBePositive,mustBeFinite} = 1;
        Data            (1,:) double
        Props           (1,1) struct
        FirstTimepoint  (1,1) double {mustBeFinite,mustBeNonempty,mustBeNonNan} = 0;
        
        LineHandle      (1,1) = -1;
        LabelHandle     (1,1) = -1;
        Color           (1,:) {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        LineWidth       (1,1) {mustBePositive,mustBeFinite} = 1;
    end
    
    properties (SetAccess = private, Dependent)
        TimeVector
        N
    end
    
    properties (SetAccess = private, Transient)
        ID
    end
    
    methods
        % Constructor
        function obj = Trace(data,props,firstTimepoint,Fs)
            if nargin >= 1 && ~isempty(data),           obj.Data = data(:); end
            if nargin >= 2 && ~isempty(props) && isstruct(props), obj.Props = props; end
            if nargin >= 3 && ~isempty(firstTimepoint), obj.FirstTimepoint = firstTimepoint; end
            if nargin == 4 && ~isempty(Fs),             obj.SampleRate = Fs; end
        end
        
        % Destructor
        function delete(obj)
            for i = 1:length(obj)
                try
                    delete(obj(i).LineHandle);
                end
                try
                    delete(obj(i).LabelHandle);
                end
            end
            try
                delete(obj);
            end
        end
        
        function t = get.TimeVector(obj)
            t = 0:1/obj.SampleRate:obj.N/obj.SampleRate-1/obj.SampleRate;
            t = t + obj.FirstTimepoint;
        end
        
        function n = get.N(obj)
            n = length(obj.Data);
        end
        
        function id = get.ID(obj)
            if isempty(obj.ID)
                id = randn(1)*1e9;
            else
                id = obj.ID;
            end
        end
        
        % Overloaded Functions --------------------------------------------
        function v = isvalid(obj)
            v = ~isempty(obj.Data);
        end
        
        function obj = plot(obj,ax,varargin)
            if isempty(obj.lineHandle) || ~obj.lineHandle.isvalid
                h = line(ax,nan,nan,varargin{:});
            else
                h = obj.lineHandle;
            end
            
            h.XData = obj.TimeVector;
            h.YData = obj.Data;
            
            obj.lineHandle = h;
        end
    end
end