classdef Trace < handle
% mabr.ui.Trace  One waveform in the TraceOrganizer stacked view.
%
%   Holds a display waveform (mean sweep), its time base, a stimulus ID and
%   label, colour, a per-trace amplitude Gain, and a vertical offset for
%   stacking, plus any peak Markers. A clean rebuild of the legacy
%   abr.traces.Trace without the abr.ABR/abr.Buffer coupling.
%
%   Display y is  Data*yscale*Gain + YOffset, where yscale is the common
%   normalization the organizer computes from the spacing and YScaling. Gain
%   is the per-trace deviation from it, so "make this one bigger" never
%   perturbs the shared scale.
%
%   Markers are stored as sample indices (MarkerLocs) rather than plotted
%   coordinates, so they follow the trace through rescaling, restacking, and
%   a save/load round-trip.
%
%   toStruct/fromStruct round-trip the complete display state, which is what
%   lets TraceOrganizer restore a saved view exactly as it was.
%
% Daniel Stolzberg (c) 2019-2026

    properties
        Data       (:,1) double = [];
        Time       (:,1) double = [];   % seconds
        Label      (1,:) char = '';     % descriptive label (e.g. informative params)
        StimID     (1,:) char = '';     % stimulus ID from the stimulus package
        Color      (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        YOffset    (1,1) double {mustBeFinite} = 0;
        Gain       (1,1) double {mustBePositive,mustBeFinite} = 1;
        LineWidth  (1,1) double {mustBePositive,mustBeFinite} = 1;
        Visible    (1,1) logical = true;
        Selected   (1,1) logical = false;
        ShowLabel  (1,1) logical = true;
        MarkerLocs (1,:) double = [];   % sample indices into Data
        MarkerText (1,:) cell   = {};
        ID         (1,1) double = 0;
    end

    properties (Dependent)
        DisplayName     % what the on-plot label reads
    end

    properties (SetAccess = private, Transient)
        LineHandle
        LabelHandle
        Markers (1,:) mabr.ui.Marker = mabr.ui.Marker.empty;
    end

    methods
        function obj = Trace(data,time,label,stimID)
            if nargin >= 1, obj.Data = double(data(:)); end
            if nargin >= 2 && ~isempty(time), obj.Time = double(time(:)); end
            if nargin >= 3 && ~isempty(label), obj.Label = label; end
            if nargin >= 4 && ~isempty(stimID), obj.StimID = stimID; end
            if isempty(obj.Time) && ~isempty(obj.Data)
                obj.Time = (0:numel(obj.Data)-1)';
            end
        end

        function name = get.DisplayName(obj)
            if ~isempty(obj.StimID)
                name = obj.StimID;
            elseif ~isempty(obj.Label)
                name = obj.Label;
            else
                name = sprintf('Trace %d',obj.ID);
            end
            if abs(obj.Gain-1) > 1e-3
                name = sprintf('%s  (x%.3g)',name,obj.Gain);
            end
        end

        function a = amplitude(obj)
            % Peak absolute amplitude, or 1 for an empty/degenerate trace so
            % callers can divide by it safely.
            a = 1;
            if isempty(obj.Data), return; end
            a = max(abs(obj.Data));
            if ~isfinite(a) || a == 0, a = 1; end
        end

        function y = displayY(obj,yscale)
            y = obj.Data*yscale*obj.Gain + obj.YOffset;
        end

        function plot(obj,ax,yscale,labelX)
            if nargin < 3 || isempty(yscale), yscale = 1; end
            if isempty(obj.Data), return; end
            tms = obj.Time*1000;                       % s -> ms
            y   = obj.displayY(yscale);
            vis = mabr.ui.Trace.onoff(obj.Visible);
            lw  = obj.LineWidth + 2*obj.Selected;

            if isempty(obj.LineHandle) || ~isgraphics(obj.LineHandle)
                obj.LineHandle = line(ax,tms,y,'Color',obj.Color,'LineWidth',lw);
            else
                set(obj.LineHandle,'XData',tms,'YData',y,'Color',obj.Color,'LineWidth',lw);
            end
            obj.LineHandle.Visible = vis;

            if nargin < 4 || isempty(labelX), labelX = tms(1); end
            showLbl = mabr.ui.Trace.onoff(obj.ShowLabel && obj.Visible);
            if obj.Selected, weight = 'bold'; else, weight = 'normal'; end

            if isempty(obj.LabelHandle) || ~isgraphics(obj.LabelHandle)
                obj.LabelHandle = text(ax,labelX,obj.YOffset,obj.DisplayName, ...
                    'HorizontalAlignment','left','VerticalAlignment','bottom', ...
                    'Interpreter','none','Clipping','on');
            else
                set(obj.LabelHandle,'Position',[labelX obj.YOffset 0], ...
                    'String',obj.DisplayName);
            end
            set(obj.LabelHandle,'Color',max(obj.Color-0.2,0), ...
                'FontWeight',weight,'Visible',showLbl);

            obj.redrawMarkers(ax,yscale);
        end

        % --- Markers ---------------------------------------------------------
        function setMarkers(obj,locs,txt)
            % Define markers by sample index. txt is optional; defaults to
            % sequential numbering (wave I, II, ...).
            locs = round(locs(:)');
            locs = locs(locs >= 1 & locs <= numel(obj.Data));
            if nargin < 3 || isempty(txt)
                txt = arrayfun(@(i) sprintf('%d',i),1:numel(locs),'UniformOutput',false);
            end
            obj.clearMarkers();
            obj.MarkerLocs = locs;
            obj.MarkerText = txt(1:numel(locs));
        end

        function redrawMarkers(obj,ax,yscale)
            delete(obj.Markers);
            obj.Markers = mabr.ui.Marker.empty;
            if isempty(obj.MarkerLocs) || ~obj.Visible, return; end
            y = obj.displayY(yscale);
            for i = 1:numel(obj.MarkerLocs)
                k = obj.MarkerLocs(i);
                obj.Markers(end+1) = mabr.ui.Marker(ax,obj.Time(k)*1000,y(k),obj.MarkerText{i});
            end
        end

        function addMarker(obj,ax,x,y,txt) %#ok<INUSD>
            % Backwards-compatible entry point: x is time in ms, snapped to the
            % nearest sample so the marker tracks later rescaling.
            [~,k] = min(abs(obj.Time*1000 - x));
            obj.MarkerLocs(end+1) = k;
            obj.MarkerText{end+1} = txt;
        end

        function clearMarkers(obj)
            delete(obj.Markers);
            obj.Markers    = mabr.ui.Marker.empty;
            obj.MarkerLocs = [];
            obj.MarkerText = {};
        end

        % --- Persistence -----------------------------------------------------
        function s = toStruct(obj)
            s = struct( ...
                'Data',       obj.Data, ...
                'Time',       obj.Time, ...
                'Label',      obj.Label, ...
                'StimID',     obj.StimID, ...
                'Color',      obj.Color, ...
                'YOffset',    obj.YOffset, ...
                'Gain',       obj.Gain, ...
                'LineWidth',  obj.LineWidth, ...
                'Visible',    obj.Visible, ...
                'ShowLabel',  obj.ShowLabel, ...
                'MarkerLocs', obj.MarkerLocs, ...
                'MarkerText', {obj.MarkerText}, ...
                'ID',         obj.ID);
        end
    end

    methods (Static)
        function s = onoff(tf)
            % Plain 'on'/'off' rather than matlab.lang.OnOffSwitchState, which
            % is newer than the R2018b floor in mabr.Config.RequiredToolboxes.
            if tf, s = 'on'; else, s = 'off'; end
        end

        function obj = fromStruct(s)
            obj = mabr.ui.Trace(s.Data,s.Time);
            f = {'Label','StimID','Color','YOffset','Gain','LineWidth', ...
                 'Visible','ShowLabel','MarkerLocs','MarkerText','ID'};
            for i = 1:numel(f)
                if isfield(s,f{i}) && ~isempty(s.(f{i}))
                    obj.(f{i}) = s.(f{i});
                end
            end
        end
    end

    methods
        function delete(obj)
            delete(obj.Markers);
            try, delete(obj.LineHandle);  end %#ok<TRYNC>
            try, delete(obj.LabelHandle); end %#ok<TRYNC>
        end
    end
end
