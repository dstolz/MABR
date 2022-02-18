classdef Trace < handle & matlab.mixin.SetGet
    
    properties
        ID              (1,1) uint32 = 1;
        GroupID         (1,1) uint32 = 1;

        YOffset         (1,1) double {mustBeFinite} = 0;

        SampleRate      (1,1) {mustBePositive,mustBeFinite} = 1;
        Data            (1,:) double
        ABR             (1,1) abr.ABR
        FirstTimepoint  (1,1) double {mustBeFinite,mustBeNonempty,mustBeNonNan} = 0;
        
        Color           (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        Alpha           (1,1) double {mustBePositive,mustBeLessThanOrEqual(Alpha,1)} = 1; % 0 = clear; 1 = opaque
        LineWidth       (1,1) double {mustBePositive,mustBeFinite} = 1;
        
        Marker          (:,1) abr.traces.Marker
        
        TimeUnit        (1,:) char {mustBeMember(TimeUnit,{'auto','s','ms','us','ns'})} = 'auto';
                
        RawData         (1,1) abr.Buffer
        
        Analysis        (1,1) % abr.analysis
        
        LabelText       
    end
    
    properties (SetAccess = private)
        Props   (1,1) struct
        LabelID   (1,:) char
    end
    
    properties (Dependent)
        TimeVector
        N
        LineHandleIsValid  
        LabelHandleIsValid
        Units (1,1) struct % same fields as props
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
        %function obj = Trace(data,SIG,firstTimepoint,Fs)
        function obj = Trace(ABR)
            if nargin == 0
                obj.ID = 0;
                return
            end
            
            obj.Data           = ABR.ADC.SweepMean;
            obj.FirstTimepoint = ABR.adcWindow(1);
            obj.SampleRate     = ABR.ADC.SampleRate;
            
            obj.ABR = copy(ABR);
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
        
        function str = get.LabelID(obj)
            gid = obj.GroupID;
            k = 2;
            while gid(1) > 26
                gid(end+1) = mod(gid(k-1),26);
                if gid(end) == 0, gid(end) = 26; end
                gid(k-1) = gid(k-1) - 26;
            end
            gid = gid+64;
            str = sprintf('%s-%d',gid,obj.ID);
        end

        function str = get.LabelText(obj)
            if isempty(obj.LabelText)
                str = obj.ABR.SIG.Label;
            else
                str = obj.LabelText;
            end
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
                
                x = x - 1;
                y = max(kobj.Data) + mean(kobj.LineHandle.YData);
                if kobj.LabelHandleIsValid
                    t = kobj.LabelHandle;
                else
                    t = text(ax,x,y,kobj.LabelID);
                end
                t.Position = [x y];
                %t.String = kobj.LabelID;
                t.String = kobj.LabelText;
                t.Color = max(kobj.Color-.2,0);
                t.FontWeight = 'bold';
%                 t.BackgroundColor = [ax.Color 0.9];
                t.BackgroundColor = 'none';
                t.Margin = 0.1;
                t.HorizontalAlignment = 'left';
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