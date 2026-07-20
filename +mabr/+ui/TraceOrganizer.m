classdef TraceOrganizer < handle
% mabr.ui.TraceOrganizer  Interactive stacked-waveform viewer.
%
%   A rebuilt, self-contained version of the legacy abr.traces.Organizer. It
%   stacks mean-sweep traces (one per acquired block), lets you drag a trace
%   vertically to reposition it, and mark response peaks. The broken legacy
%   Group/Marker classes and the user32.dll mouse hook are gone; interaction
%   uses standard figure callbacks and the fixed mabr.ui.Marker.
%
%   to = mabr.ui.TraceOrganizer();
%   to.addBlock(block);      % add a finalized mabr.data.Block
%   to.show();
%
% Daniel Stolzberg (c) 2019-2026

    properties
        YSpacing (1,1) double {mustBePositive,mustBeFinite} = 1;
        YScaling (1,1) double {mustBePositive,mustBeFinite} = 0.8;
        Colors   (:,3) double = lines(7);
    end

    properties (SetAccess = private)
        Traces (1,:) mabr.ui.Trace = mabr.ui.Trace.empty;
    end

    properties (Access = private, Transient)
        Figure
        Axes
        Toolbar
        SelectedIdx = [];
        dragIdx     = [];
        dragStartY  = 0;
        dragStartOffset = 0;
        FigTag (1,:) char = '';
    end

    methods
        function obj = TraceOrganizer()
            obj.FigTag = sprintf('MABR_TRACEORG_%d',round(rand*1e9));
        end

        function delete(obj)
            delete(obj.Traces);
            try, delete(obj.Figure); end %#ok<TRYNC>
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Figure) && isgraphics(obj.Figure);
        end

        % --- Adding data ----------------------------------------------------
        function addBlock(obj,block)
            try
                m   = block.ADC.SweepMean;
                t   = block.ADC.TimeVector;
                lbl = char(join(string(block.Label),', '));
            catch
                return
            end
            if isempty(m), return; end
            obj.addTrace(m,t,lbl);
        end

        function addTrace(obj,data,time,label)
            tr = mabr.ui.Trace(data,time,label);
            tr.ID = numel(obj.Traces)+1;
            if isempty(obj.Traces)
                tr.YOffset = 0;
            else
                tr.YOffset = min([obj.Traces.YOffset]) - obj.YSpacing;
            end
            tr.Color = obj.Colors(mod(numel(obj.Traces),size(obj.Colors,1))+1,:);
            if isempty(obj.Traces), obj.Traces = tr; else, obj.Traces(end+1) = tr; end
            if obj.isvalidView(), obj.plotAll(); end
        end

        function clear(obj)
            delete(obj.Traces);
            obj.Traces = mabr.ui.Trace.empty;
            obj.SelectedIdx = [];
            if obj.isvalidView(), cla(obj.Axes); end
        end

        % --- View -----------------------------------------------------------
        function show(obj)
            obj.ensureFigure();
            obj.plotAll();
            figure(obj.Figure);
        end

        function markPeaks(obj)
            k = obj.SelectedIdx;
            if isempty(k), obj.status('Select a trace first.'); return; end
            tr = obj.Traces(k);
            r  = mabr.metrics.find_peaks(tr.Data,5,false);
            tr.clearMarkers();
            sc = obj.yscale();
            for i = 1:numel(r.locs)
                x = tr.Time(r.locs(i))*1000;
                y = tr.Data(r.locs(i))*sc + tr.YOffset;
                tr.addMarker(obj.Axes,x,y,sprintf('%d',i));
            end
        end
    end

    methods (Access = private)
        function ensureFigure(obj)
            if obj.isvalidView(), return; end
            obj.Figure = figure('Name','MABR Trace Organizer','NumberTitle','off', ...
                'Color','w','Tag',obj.FigTag,'MenuBar','none','Position',[820 120 560 600], ...
                'WindowButtonMotionFcn',@(~,~) obj.doDrag(), ...
                'WindowButtonUpFcn',@(~,~) obj.endDrag());
            obj.Axes = axes('Parent',obj.Figure,'Box','on','NextPlot','add', ...
                'YTick',[],'XGrid','on','YGrid','on','GridLineStyle',':');
            xlabel(obj.Axes,'Time (ms)');
            obj.buildToolbar();
        end

        function buildToolbar(obj)
            obj.Toolbar = uitoolbar(obj.Figure);
            uipushtool(obj.Toolbar,'Tooltip','Mark peaks on selected trace', ...
                'CData',obj.icon([0.85 0.1 0.1]),'ClickedCallback',@(~,~) obj.markPeaks());
            uipushtool(obj.Toolbar,'Tooltip','Clear all', ...
                'CData',obj.icon([0.4 0.4 0.4]),'ClickedCallback',@(~,~) obj.clear());
            uipushtool(obj.Toolbar,'Tooltip','Save…', ...
                'CData',obj.icon([0.1 0.4 0.85]),'ClickedCallback',@(~,~) obj.save());
            uipushtool(obj.Toolbar,'Tooltip','Load…', ...
                'CData',obj.icon([0.1 0.7 0.3]),'ClickedCallback',@(~,~) obj.load());
        end

        function plotAll(obj)
            if isempty(obj.Traces), return; end
            sc = obj.yscale();
            for k = 1:numel(obj.Traces)
                obj.Traces(k).plot(obj.Axes,sc);
                obj.Traces(k).LineHandle.ButtonDownFcn = @(~,~) obj.selectAndDrag(k);
                obj.Traces(k).LineHandle.LineWidth = obj.widthFor(k);
            end
            allY = arrayfun(@(t) t.YOffset,obj.Traces);
            obj.Axes.YLim = [min(allY)-obj.YSpacing, max(allY)+obj.YSpacing];
            allX = obj.Traces(1).Time([1 end])*1000;
            obj.Axes.XLim = allX;
        end

        function sc = yscale(obj)
            mx = max(arrayfun(@(t) max(abs(t.Data)),obj.Traces));
            if isempty(mx) || mx == 0, sc = 1; else, sc = obj.YScaling*obj.YSpacing/mx; end
        end

        function w = widthFor(obj,k)
            if isequal(obj.SelectedIdx,k), w = 3; else, w = 1; end
        end

        % --- Interaction ----------------------------------------------------
        function selectAndDrag(obj,k)
            obj.SelectedIdx = k;
            for j = 1:numel(obj.Traces)
                if isgraphics(obj.Traces(j).LineHandle)
                    obj.Traces(j).LineHandle.LineWidth = obj.widthFor(j);
                end
            end
            obj.dragIdx = k;
            cp = obj.Axes.CurrentPoint;
            obj.dragStartY = cp(1,2);
            obj.dragStartOffset = obj.Traces(k).YOffset;
        end

        function doDrag(obj)
            if isempty(obj.dragIdx), return; end
            cp = obj.Axes.CurrentPoint;
            dy = cp(1,2) - obj.dragStartY;
            obj.Traces(obj.dragIdx).YOffset = obj.dragStartOffset + dy;
            obj.Traces(obj.dragIdx).plot(obj.Axes,obj.yscale());
        end

        function endDrag(obj)
            obj.dragIdx = [];
        end

        % --- Persistence ----------------------------------------------------
        function save(obj)
            [fn,pn] = uiputfile({'*.torg','Trace Organizer (*.torg)'},'Save Traces');
            if isequal(fn,0), return; end
            S = struct('Data',{},'Time',{},'Label',{},'Color',{},'YOffset',{}); %#ok<NASGU>
            for k = 1:numel(obj.Traces)
                t = obj.Traces(k);
                S(k) = struct('Data',t.Data,'Time',t.Time,'Label',t.Label, ...
                    'Color',t.Color,'YOffset',t.YOffset); %#ok<AGROW>
            end
            save(fullfile(pn,fn),'S','-mat');
        end

        function load(obj)
            [fn,pn] = uigetfile({'*.torg','Trace Organizer (*.torg)'},'Load Traces');
            if isequal(fn,0), return; end
            L = load(fullfile(pn,fn),'-mat','S');
            obj.clear();
            for k = 1:numel(L.S)
                obj.addTrace(L.S(k).Data,L.S(k).Time,L.S(k).Label);
                obj.Traces(end).YOffset = L.S(k).YOffset;
                obj.Traces(end).Color   = L.S(k).Color;
            end
            obj.plotAll();
        end

        function status(obj,txt)
            if obj.isvalidView(), title(obj.Axes,txt); end
        end
    end

    methods (Static, Access = private)
        function c = icon(rgb)
            c = repmat(reshape(rgb,1,1,3),16,16);
        end
    end
end
