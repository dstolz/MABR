classdef Trace < handle
% mabr.ui.Trace  One waveform in the TraceOrganizer stacked view.
%
%   Holds a display waveform (mean sweep), its time base, a label, colour, and
%   a vertical offset for stacking, plus any peak Markers. A clean rebuild of
%   the legacy abr.traces.Trace without the abr.ABR/abr.Buffer coupling.
%
% Daniel Stolzberg (c) 2019-2026

    properties
        Data      (:,1) double = [];
        Time      (:,1) double = [];   % seconds
        Label     (1,:) char = '';
        Color     (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        YOffset   (1,1) double {mustBeFinite} = 0;
        LineWidth (1,1) double {mustBePositive,mustBeFinite} = 1;
        Markers   (1,:) mabr.ui.Marker = mabr.ui.Marker.empty;
        ID        (1,1) double = 0;
    end

    properties (SetAccess = private, Transient)
        LineHandle
        LabelHandle
    end

    methods
        function obj = Trace(data,time,label)
            if nargin >= 1, obj.Data = double(data(:)); end
            if nargin >= 2 && ~isempty(time), obj.Time = double(time(:)); end
            if nargin >= 3 && ~isempty(label), obj.Label = label; end
            if isempty(obj.Time) && ~isempty(obj.Data)
                obj.Time = (0:numel(obj.Data)-1)';
            end
        end

        function plot(obj,ax,yscale)
            if nargin < 3 || isempty(yscale), yscale = 1; end
            tms = obj.Time*1000;                       % s -> ms
            y   = obj.Data*yscale + obj.YOffset;

            if isempty(obj.LineHandle) || ~isgraphics(obj.LineHandle)
                obj.LineHandle = line(ax,tms,y,'Color',obj.Color,'LineWidth',obj.LineWidth);
            else
                set(obj.LineHandle,'XData',tms,'YData',y,'Color',obj.Color,'LineWidth',obj.LineWidth);
            end

            lx = tms(1);
            if isempty(obj.LabelHandle) || ~isgraphics(obj.LabelHandle)
                obj.LabelHandle = text(ax,lx,obj.YOffset,obj.Label, ...
                    'HorizontalAlignment','right','FontWeight','bold', ...
                    'Color',max(obj.Color-0.2,0),'Clipping','on');
            else
                set(obj.LabelHandle,'Position',[lx obj.YOffset 0],'String',obj.Label, ...
                    'Color',max(obj.Color-0.2,0));
            end
        end

        function addMarker(obj,ax,x,y,txt)
            obj.Markers(end+1) = mabr.ui.Marker(ax,x,y,txt);
        end

        function clearMarkers(obj)
            delete(obj.Markers);
            obj.Markers = mabr.ui.Marker.empty;
        end

        function delete(obj)
            obj.clearMarkers();
            try, delete(obj.LineHandle);  end %#ok<TRYNC>
            try, delete(obj.LabelHandle); end %#ok<TRYNC>
        end
    end
end
