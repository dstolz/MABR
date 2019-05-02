classdef Trace < handle &  matlab.mixin.SetGet
    
    properties
        SampleRate      (1,1) {mustBePositive,mustBeFinite} = 1;
        Data            (1,:) double
        Props           (1,1) struct
        FirstTimepoint  (1,1) double {mustBeFinite,mustBeNonempty,mustBeNonNan} = 0;
        
        Color           (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        Alpha           (1,1) double {mustBePositive,mustBeLessThanOrEqual(Alpha,1)} = 1; % 0 = clear; 1 = opaque
        LineWidth       (1,1) double {mustBePositive,mustBeFinite} = 1;
        
        Marker          (:,1) traces.Marker
        LabelText       (1,:) char = '';
        
        TimeUnit        (1,:) char {mustBeMember(TimeUnit,{'auto','s','ms','us','ns'})} = 'auto';
    end
    
    properties (SetAccess = private)
        ID  (1,1) int32
    end
    
    properties (SetAccess = private, Dependent)
        TimeVector
        N
        LineHandleIsValid  = false;
        LabelHandleIsValid = false;
    end
    
    properties (SetAccess = private, Transient)
        LineHandle      (1,1)
        LabelHandle     (1,1)
        
        MarkerHandles       (1,:)
        MarkerLabelHandles  (1,:)
        
        Parent
    end
    
    methods
        % Constructor
        function obj = Trace(data,props,firstTimepoint,Fs)
            if nargin == 0
                obj.ID = -1;
                return
            end
            narginchk(2,4);
            if nargin >= 3 && ~isempty(firstTimepoint), obj.FirstTimepoint = firstTimepoint; end
            if nargin == 4 && ~isempty(Fs),             obj.SampleRate = Fs; end

            obj.ID = fix(rand(1)*1e9);
            
            obj.Data  = data(:);
            obj.Props = props;
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
%             try
%                 delete(obj);
%             end
        end
        
        function t = get.TimeVector(obj)
            t = 0:1/obj.SampleRate:obj.N/obj.SampleRate-1/obj.SampleRate;
            t = t + obj.FirstTimepoint;
        end
        
        function n = get.N(obj)
            n = length(obj.Data);
        end
        
        function p = get.Parent(obj)
            p = obj.LineHandle.Parent;
        end
        
        function createLineHandleIfNone(obj)
            if ~obj.LineHandleIsValid, plot(obj); end
        end
        
        function v = get.LineHandleIsValid(obj)
            try
                v = isvalid(obj.LineHandle);
            catch
                v = false;
            end
        end
        
        function v = get.LabelHandleIsValid(obj)
            try
                v = isvalid(obj.LabelHandle);
            catch
                v = false;
            end
        end
        
        function h = get.MarkerHandles(obj)
            h = [obj.Marker.MarkerHandle];
        end
        
        function h = get.MarkerLabelHandles(obj)
            h = [obj.Marker.LabelHandle];
        end
        
        
        % Overloaded Functions --------------------------------------------
        function plot(obj,ax)
            if nargin < 2 || isempty(ax), ax = gca; end
            
            for kobj = obj
                if kobj.LineHandleIsValid
                    h = kobj.LineHandle;
                else
                    h = line(kobj,ax);
                end
                
                kobj.LineHandle = h;
                
                h.Color = kobj.Color;
                
                
                % label
                x = h.XData(1);
                
                y = max(kobj.LineHandle.YData) * 0.8;
                if kobj.LabelHandleIsValid
                    t = kobj.LabelHandle;
                else
                    t = text(ax,x,y,kobj.LabelText);
                end
                t.Color = kobj.Color;
                t.FontWeight = 'bold';
                t.BackgroundColor = [ax.Color 0.9];
                t.Margin = 0.1;
                t.HorizontalAlignment = 'center';
                t.VerticalAlignment   = 'baseline';
                kobj.LabelHandle = t;
                
            end
            
        end
        
        function h = line(obj,ax)
            h = line(ax,nan,nan);
            
            x = obj.TimeVector;
            
            tu = obj.TimeUnit;
            
            if isequal(tu,'auto')
                mx = x(end);
                if mx > 1
                    tu = 's';
                elseif mx <= 1
                    tu = 'ms';
                elseif mx <= .01
                    tu = 'us';
                elseif mx <= 0.001
                    tu = 'ns';
                end
            end
                
            switch tu
                case 'ms'
                    x = x .* 1e3; % s -> ms
                case 'us'
                    x = x .* 1e6; % s -> us
                case 'ns'
                    x = x .* 1e9; % s -> ns
            end
            
            h.XData = x;
            h.YData = obj.Data;
            h.Color = obj.Color;
            
            ax.XAxis.Label.String = sprintf('time (%s)',tu);
        end
        
        
    end
end