classdef Group < handle
    
    
    properties
        Name        (1,:) Char
        Description (1,:) Char
        Traces      (1,:) Trace
        Color       (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        LineWidth   (1,1) double {mustBePositive,mustBeFinite} = 1;
        LineStyle   (1,:) char   {mustBeMember(LineStyle,{'-','--',':','-.'})} = '-';
    end
    
    properties (SetAccess = private)
        ID
        TraceIDs
        LineHandles
        GT_IDs
        N
    end
    
    methods
        
        % Constructor
        function obj = TraceGroup(name)
            obj.ID = fix(rand(1)*1e9);
                        
            if nargin < 1 || isempty(name), name = sprintf('Group_%d',obj.ID); end
            
            obj.Name = name;
        end
        
        function addTrace(obj,trace)
            obj.Traces(end+1) = trace;
        end
        
        function removeTrace(obj,idx)
            obj.Traces(idx) = [];
        end
        
        function set.Color(obj,c)
            obj.Color = c;
            set(obj.LineHandles,'Color',c);
        end
        
        function set.LineWidth(obj,w)
            obj.LineWidth = w;
            set(obj.LineHandles,'LineWidth',w);
        end
        
        function set.LineStyle(obj,s)
            obj.LineStyle = s;
            set(obj.LineHandles,'LineStyle',s);
        end
        
        function ids = get.GT_IDs(obj)
            ids = [repmat(obj.ID,1,obj.N); obj.TraceIDs];
        end
        
        function n = get.N(obj)
            n = length(obj.Traces);
        end
        
        function id = get.TraceIDs(obj)
            id = [obj.Traces.ID];
        end
        
        function h = get.LineHandles(obj)
            h = [obj.Traces.LineHandle];
        end
        
        function removeTrace(obj,traceID)
            ind = ismember(obj.TraceIDs,traceID);
            if ~any(ind), return; end
            obj.Traces(ind) = []; % but don't destroy handle to Trace
        end
    end
    
    
end