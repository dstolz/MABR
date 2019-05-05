classdef Marker < handle & matlab.mixin.SetGet
    
    properties
        Style     (1,1) char   {mustBeMember(Style,{'o','+','*','.','x','d','s','^','v','>','<','p','h'})} = 's';
        Size      (1,1) double {mustBePositive,mustBeFinite} = 5;
        Color     (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        LineWidth (1,1) double {mustBeNonnegative,mustBeFinite} = 0.5;
        FaceColor (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(FaceColor,1)} = [0 0 0];
        EdgeAlpha (1,1) double {mustBeNonnegative,mustBeLessThanOrEqual(EdgeAlpha,1)} = 0.5;
        FaceAlpha (1,1) double {mustBeNonnegative,mustBeLessThanOrEqual(FaceAlpha,1)} = 0.5;
        
        X         (1,1) double = nan;
        Y         (1,1) double = nan;
        
        Text          (1,:) char
        FontSize      (1,1) double {mustBePositive,mustBeFinite} = 8;
        FontColor     (1,3) double {mustBeNonnegative,mustBeFinite} = [0 0 0];
        LabelXOffset  (1,1) double {mustBeFinite} = 5; % pixels
        LabelYOffset  (1,1) double {mustBeFinite} = 10; % pixels
        
    end
    
    properties (SetAccess = private)
        MarkerHandle
        LabelHandle
        
        ID
    end
    
    methods
        % Constructor
        function obj = TraceMarker(ax,x,y)
            if nargin < 1 || isempty(ax), ax = gca; end
            if nargin < 2 || isempty(x),   x = nan; end
            if nargin < 3 || isempty(y),   y = nan; end
            
            obj.ID = fix(rand(1),1e9);
            
            h = scatter(ax,x,y,obj.Size,obj.Color,obj.Style);
            
            h.LineWidth = obj.LineWidth;
            h.MarkerFaceColor = obj.FaceColor;
            h.MarkerFaceAlpha = obj.FaceAlpha;
            h.MarkerEdgeAlpha = obj.EdgeAlpha;
            
            obj.MarkerHandle = h;
            
            obj.LabelHandle = text(ax,x+obj.LabelXOffset,y+obj.LabelYOffset,obj.Text, ...
                'FontSize',obj.FontSize,'Units','pixels');
            
        end
        
        function set.Text(obj,str)
            obj.LabelHandle.String = str;
        end
        
        function set.FontSize(obj,n)

        end
        
    end
    
end