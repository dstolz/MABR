classdef Marker < handle
% mabr.ui.Marker  A peak marker (point + label) on a trace axes.
%
%   Rebuild of the broken legacy abr.traces.Marker, which had a mismatched
%   constructor name (TraceMarker), an invalid id expression fix(rand(1),1e9),
%   and a no-op set.FontSize. This version draws a filled marker and an
%   attached text label and keeps them in sync.
%
%   m = mabr.ui.Marker(ax,x,y,'I');
%
% Daniel Stolzberg (c) 2019-2026

    properties
        Style     (1,1) char {mustBeMember(Style,{'o','+','*','.','x','d','s','^','v','>','<','p','h'})} = 'v';
        Size      (1,1) double {mustBePositive,mustBeFinite} = 36;
        Color     (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0.85 0.1 0.1];
        X         (1,1) double = NaN;
        Y         (1,1) double = NaN;
        Text      (1,:) char = '';
        FontSize  (1,1) double {mustBePositive,mustBeFinite} = 9;
    end

    properties (SetAccess = private)
        ID
    end

    properties (SetAccess = private, Transient)
        MarkerHandle
        LabelHandle
    end

    methods
        function obj = Marker(ax,x,y,txt)
            obj.ID = fix(rand(1)*1e9);          % fixes legacy fix(rand(1),1e9)
            if nargin >= 2 && ~isempty(x),   obj.X = x;     end
            if nargin >= 3 && ~isempty(y),   obj.Y = y;     end
            if nargin >= 4 && ~isempty(txt), obj.Text = txt; end
            if nargin >= 1 && ~isempty(ax) && isgraphics(ax), obj.draw(ax); end
        end

        function draw(obj,ax)
            obj.MarkerHandle = scatter(ax,obj.X,obj.Y,obj.Size,obj.Color,obj.Style,'filled');
            obj.LabelHandle  = text(ax,obj.X,obj.Y,['  ' obj.Text], ...
                'FontSize',obj.FontSize,'Color',obj.Color, ...
                'VerticalAlignment','bottom','Clipping','on');
        end

        function move(obj,x,y)
            obj.X = x; obj.Y = y;
            if obj.isDrawn()
                set(obj.MarkerHandle,'XData',x,'YData',y);
                set(obj.LabelHandle,'Position',[x y 0]);
            end
        end

        function set.Text(obj,str)
            obj.Text = str;
            if obj.isDrawn(), obj.LabelHandle.String = ['  ' str]; end %#ok<MCSUP>
        end

        function set.FontSize(obj,n)
            obj.FontSize = n;
            if obj.isDrawn(), obj.LabelHandle.FontSize = n; end %#ok<MCSUP>
        end

        function delete(obj)
            try, delete(obj.MarkerHandle); end %#ok<TRYNC>
            try, delete(obj.LabelHandle);  end %#ok<TRYNC>
        end
    end

    methods (Access = private)
        function tf = isDrawn(obj)
            tf = ~isempty(obj.LabelHandle) && isgraphics(obj.LabelHandle);
        end
    end
end
