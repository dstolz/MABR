classdef (ConstructOnLoad = true) Organizer < handle
    
    properties
        SortBy          (:,1) cell
        SortOrder       (:,1) cell
        
        YPosition       (:,1) double {mustBeFinite} = 0;
        YScaling        (1,1) double {mustBePositive,mustBeNonempty,mustBeFinite} = 0.7;
        YSpacing        (1,1) double {mustBePositive,mustBeNonempty,mustBeFinite} = 1;
        
        Traces          (1,:) abr.traces.Trace
        
        groupColors     (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(groupColors,1)} = lines;

        defaultTraceWidth  (1,1) double {mustBeNonnegative,mustBeFinite} = 1;
        selectedTraceWidth (1,1) double {mustBeNonnegative,mustBeFinite} = 3;
    end
    
    properties (SetAccess = private)
        Labels          (1,:) cell
        N               (1,1) double
        
        PropertyMatrix  double
        PropertyNames   cell
        PlotOrder       (1,:)
        
        TraceSelection  (1,:) uint32
        
        informativeProps
        
        TraceIdx    (:,1)
        GroupIdx    (:,1)
    end
    
    properties (Access = private,Transient)
        mainFigTag       (1,:) char
        mainFig          (1,1) %matlab.ui.Figure
        mainAx           (1,1) %matlab.graphics.axis.Axes
        
        ContextMenu
        
        tbh % structure with toolbar handles
        
        traceTimer timer
    end
    
    
    
    methods
        
        % Constructor
        function obj = Organizer(traces)
            
            abr.Universal.addpaths;
            
            if isempty(obj.mainFigTag)
                obj.mainFigTag = sprintf('TRACEORGANIZER_%d',round(rand(1)*1e9));
            end
            
            if nargin == 0, return; end
            
            if isa(traces,'abr.traces.Trace')
                for i = 1:length(traces)
                    obj.add_trace(traces(i).Data,traces(i).Props,traces(i).FirstTimepoint,traces(i).SampleRate);
                end
                
            elseif ischar(traces) && exist(traces,'file')
                load(traces,'-mat');
            end
        end
        
        
        % Destructor
        function delete(obj)
            try obj.clear; end
            delete(obj);
        end
        
        
        function add_trace(obj,data,props,firstTimepoint,Fs)
            narginchk(3,5);
            
            vprintf(2,'Adding trace to Organizer')
            
            if nargin < 4 || isempty(firstTimepoint), firstTimepoint = 0; end
            if nargin < 5 || isempty(Fs), Fs = 1; end
            if isempty(obj.Traces) || obj.N == 1 && obj.Traces.ID == -1
                obj.Traces = abr.traces.Trace(data,props,firstTimepoint,Fs);
                obj.YPosition = 0;
                obj.GroupIdx  = 1; % default group
            else
                obj.Traces(end+1) = abr.traces.Trace(data,props,firstTimepoint,Fs);
                obj.YPosition(end+1) = min(obj.YPosition) - obj.YSpacing;
                obj.GroupIdx(end+1) = 1; % default group
            end
            
            obj.Traces(end).Color = obj.groupColors(obj.GroupIdx(end),:);

            plot(obj);
        end
                
        function delete_trace(obj,idx)
            obj.YPosition(idx) = [];
            obj.Labels(idx) = [];
            obj.TraceSelection(ismember(obj.TraceSelection,idx)) = [];
            obj.TraceIdx(ismember(obj.TraceIdx,idx)) = [];
            obj.GroupIdx(idx) = [];
            obj.Traces(idx) = [];
        end
        
        function n = get.N(obj)
            n = numel(obj.Traces);
        end
        
        
        function set.YSpacing(obj,yspace)
            obj.YSpacing = yspace;
            obj.plot;
        end
        
        function set.YScaling(obj,yscale)
            obj.YScaling = yscale;
            obj.plot;
        end
                
        function m = get.PropertyMatrix(obj)
            n = obj.PropertyNames;
            m = nan(obj.N,length(n));
            for i = 1:obj.N
                for j = 1:length(n)
                    if ~isfield(obj.Traces(i).Props,n{j}), continue; end
                    m(i,j) = obj.Traces(i).Props.(n{j});
                end
            end
        end
        
        function n = get.PropertyNames(obj)
            n = {};
            for i = 1:obj.N
                n = [n fieldnames(obj.Traces(i).Props)]; %#ok<AGROW>
            end
            n = unique(n);
        end
        
        function n = get.informativeProps(obj)
            m = obj.PropertyMatrix;
            ind = false(1,size(m,2));
            for i = 1:size(m,2)
                u = unique(m(:,i));
                ind(i) = length(u) > 1;
            end
            if ~any(ind), ind = true(size(ind)); end
            n = obj.PropertyNames(ind);
        end
        
        function s = get.Labels(obj)
            s = {};
%             b = obj.SortBy;
%             m = obj.PropertyMatrix;
            n = obj.informativeProps;
            if isempty(n), return; end
                
            for i = 1:obj.N
                s{i} = '';
%                 s{i} = sprintf('\\color[rgb]{%0.3f,%0.3f,%0.3f}',obj.Traces(i).Color);
                %for j = 1:length(b)
                    %s{i} = sprintf('%s%0.1f,',s{i},m(i,j));
                for j = 1:length(n)
                    s{i} = sprintf('%s%0.1f|',s{i},obj.Traces(i).Props.(n{j}));
                end
                s{i}(end) = [];
            end
        end
        
        function i = get.PlotOrder(obj)
            c = [];
            b = obj.SortBy;
            for k = 1:length(b)
                c(k) = find(ismember(obj.PropertyNames,b{k}));
            end
            [~,i] = sortrows(obj.PropertyMatrix, ...
                c,obj.SortOrder, ...
                'MissingPlacement','last');
        end
        
        function n = get.SortBy(obj)
            if isempty(obj.SortBy)
                n = obj.PropertyNames;
            else
                n = obj.SortBy;
            end
        end
        
        function set.SortBy(obj,propNames)
            n = obj.PropertyNames; %#ok<MCSUP>
            assert(all(ismember(propNames,n)),'Invalid property name');
            
            obj.SortBy = propNames;
        end
        
        function d = get.SortOrder(obj)
            if isempty(obj.SortOrder)
                d = repmat({'descend'},1,length(obj.PropertyNames));
            else
                d = obj.SortOrder;
            end
        end
        
        function set.SortOrder(obj,dir)
            for i = 1:length(dir)
                mustBeMember(dir{i},{'ascend','descend'});
            end
            obj.SortOrder = dir;
        end
        
        
        
        function y = get.YPosition(obj)
            if isempty(obj.YPosition)
                y = arrayfun(@(a) mean(a.Data),obj.Traces);
                y = y + [0 cumsum(repmat(obj.YSpacing,size(y)))];
            else
                y = obj.YPosition;
            end
            
        end
        
        
        
        
        % Overloaded Functions --------------------------------------------
        function clear(obj,hObj,event)
            if ~obj.N, return; end

            delete(obj.Traces);
            obj.Traces = abr.traces.Trace;

            try
                cla(obj.mainAx);
                obj.mainAx.YTick = [];
            end
            
        end
        
        function load(obj,hObj,event) %#ok<INUSD>
            if nargin == 2 && ischar(obj)
                % happens on load from file
                ffn = obj; 
                
            elseif nargin >= 2 && ischar(hObj)
                % hObj is provided as a filename
                ffn = hObj;
            
            elseif nargin < 2
                % ... load buffer data from file
                dfltpn = getpref('TraceOrganizer','dfltpath',cd);
                
                [fn,pn] = uigetfile({'*.torg','Trace Organizer File (*.torg)'}, ...
                    'Load Trace Organizer',dfltpn);
                
                if isequal(pn,0), return; end
                
                ffn = fullfile(pn,fn);
            end
            load(ffn,'TO','-mat');
            
            obj = TO;
            
            figure(obj);
            plot(obj);
            
            setpref('TraceOrganizer','dfltpath',pn);
        end
        
        function save(obj,hObj,event) %#ok<INUSD>
            if nargin == 2 && ischar(hObj)
                ffn = hObj;
            else
                dfltpn = getpref('TraceOrganizer','dfltpath',cd);
                [fn,pn] = uiputfile({'*.torg','Trace Organizer File (*.torg)'}, ...
                    'Save Trace Organizer',dfltpn);
                if isequal(pn,0), return; end
                ffn = fullfile(pn,fn);
            end
            
            TO = obj; % this actually works for a handle class?

            save(ffn,'TO','-mat'); 
            setpref('TraceOrganizer','dfltpath',pn);
        end
        
        function figure(obj)
            if isempty(obj.mainFigTag)
                obj.mainFigTag = sprintf('TRACEORGANIZER_%d',round(rand(1)*1e9));
            end
            f = findobj('tag',obj.mainFigTag);
            if isempty(f)
                f = figure( ...
                    'Tag',obj.mainFigTag, ...
                    'Toolbar','none', ...
                    'Name','Trace Organizer', ...
                    'NumberTitle','off', ...
                    'Color',[1 1 1], ...
                    'MenuBar','none', ...
                    'KeyPressFcn',{'abr.traces.Organizer.key_processor',obj}, ...
                    'WindowButtonMotionFcn',{'abr.traces.Organizer.move_trace',obj}, ...
                    'Units','pixels', ...
                    'Position',[800 30 570 620]);
                
                f.Units = 'normalized';
                
                obj.mainFig = f;
                obj.create_toolbar;
                
                obj.mainAx = axes(f, ...
                    'Color',[1 1 1], ...
                    'Units','normalized', ...
                    'Position',[0.02 0.15 0.96 0.8], ...
                    'YTick',[], ...
                    'GridColor',[0.2 0.2 0.2], ...
                    'XGrid','on','YGrid','on', ...
                    'GridLineStyle',':', ...
                    'Box','on', ...
                    'ButtonDownFcn',{'abr.traces.Organizer.axes_clicked',obj}, ...
                    'HandleVisibility','off', ...
                    'YTickLabelRotation',30);
                
                
                
                c = uicontextmenu;
                m1 = uimenu(c,'Label','Delete Trace', ...
                    'Callback',{'abr.traces.Organizer.key_processor',obj,'delete'});
                obj.ContextMenu = c;
                
%                 obj.init_timer;
            else
                obj.mainFig = f;
            end
            figure(obj.mainFig);
            
        end
        
        function plot(obj)
            figure(obj);
            
            D = {obj.Traces.Data};
            
            % normalize trace data
            my = max(cellfun(@(a) max(abs(a)),D));
            D = cellfun(@(a) a./ my .* obj.YScaling,D,'uni',0);
            
            pidx = obj.PlotOrder';
            
            obj.TraceIdx = [];
            for k = pidx
                obj.Traces(k).Color     = obj.groupColors(obj.GroupIdx(k),:);
                obj.Traces(k).LabelText = obj.Labels{k};

                obj.Traces(k).plot(obj.mainAx);
                obj.Traces(k).LineHandle.YData = D{k} + obj.YPosition(k);
                obj.Traces(k).LineHandle.ButtonDownFcn  = {'abr.traces.Organizer.trace_clicked',obj,k};
                obj.Traces(k).LabelHandle.ButtonDownFcn = {'abr.traces.Organizer.trace_label_clicked',obj,k};
                obj.TraceIdx(k) = k;
                
                obj.Traces(k).LabelHandle.Position(2) = obj.YPosition(k);
                
                obj.Traces(k).LineHandle.UIContextMenu = obj.ContextMenu;
                obj.Traces(k).LabelHandle.UIContextMenu = obj.ContextMenu;
            end
            
            
            x = [obj.Traces(k).LineHandle.XData];
            if isempty(x), x = [0 1]; end
            obj.mainAx.XLim = [min(x) max(x)];
            
            
        end
        
        
    end
    
    methods (Access = private)
        
        function create_toolbar(obj)
            obj.tbh.toolbar = uitoolbar(obj.mainFig);
                
            A = abr.Universal;
            
            obj.tbh.Clear = uipushtool(obj.tbh.toolbar);
            obj.tbh.Clear.Tooltip = 'Clear';
            obj.tbh.Clear.ClickedCallback = @obj.clear;
            obj.tbh.Clear.CData = A.icon_img('file_new');
            
            obj.tbh.Load = uipushtool(obj.tbh.toolbar);
            obj.tbh.Load.Tooltip = 'Load';
            obj.tbh.Load.ClickedCallback = @obj.load;
            obj.tbh.Load.CData = A.icon_img('file_open');
            
            obj.tbh.Save = uipushtool(obj.tbh.toolbar);
            obj.tbh.Save.Tag = 'SaveButton';
            obj.tbh.Save.Tooltip = 'Save';
            obj.tbh.Save.ClickedCallback = @obj.save;
            obj.tbh.Save.CData = A.icon_img('file_save');
            
            obj.tbh.Info = uipushtool(obj.tbh.toolbar);
            obj.tbh.Info.Tooltip = 'Info';
            obj.tbh.Info.ClickedCallback = @obj.display_info;
            obj.tbh.Info.CData = A.icon_img('helpicon');

        end
        
        function display_info(obj,hObj,event)
            fprintf('%s\nTrace Organizer Commands\n\n',repmat('~',1,50))
            fprintf('%-25sSelect a trace\n%-25sClick background to deselect all traces\n','Left-Click',' ')
            fprintf('%-25sSelect one or more traces\n','Ctrl+Left-Click')
            fprintf('%-25sSelect range of traces\n','Shift+Left-Click')
            fprintf('%-25sSelect all traces within a group\n','Ctrl+Shift+Left-Click')
            fprintf('\n')
            fprintf(['a\t\tSelect all traces\n', ...
                's\t\tSave current Trace Organizer\n', ...
                'o\t\tOpen a Trace Organizer\n', ...
                'f\t\tExport figure as an image (jpg,tif,etc.) or vector file (pdf,eps,etc.)\n'])
            fprintf('\n')
            fprintf([ ...
                'k/m\t\tIncrease/Decrease trace spacing\n', ...
                'j/n\t\tIncrease/Decrease trace amplitude\n'])
            fprintf('\n')
            fprintf([ ...
                'c\t\tClear all traces\n', ...
                'd\t\tDelete selected traces\n', ...
                'e\t\tExport selected traces to the workspace\n', ...
                'g/u\t\tGroup/Ungroup selected traces\n', ...
                'p\t\tOpen selected traces in new Trace Organizer Window\n', ...
                'v\t\tOverlap selected traces\n', ...
                'q\t\tChange the color of the selected traces\n'])
            fprintf('%s\n\n',repmat('~',1,50))
            commandwindow;
        end
    end
    
    
    methods (Static)
        key_processor(hFig,KeyData,obj,Cmd);
        move_trace(hFig,event,obj);
        window_click(hFig,event,obj);
        trace_clicked(h,event,obj,traceIdx);
        
        function trace_label_clicked(h,event,obj,traceIdx) 
            vprintf(2,'Clicked Label: %s',h.String)
            abr.traces.Organizer.trace_clicked(h,event,obj,traceIdx); % FOR NOW
        end
            
        function axes_clicked(h,event,obj) %#ok<INUSL>
            % deselect all traces
            vprintf(2,'Deselected all traces')
            obj.TraceSelection = [];
            set([obj.Traces.LineHandle],'LineWidth',obj.defaultTraceWidth);
        end
        
        function L = button_state_left
            if ispc
                if ~libisloaded('user32')
                    loadlibrary('C:\WINDOWS\system32\user32.dll','user32.h');
                end
                L = calllib('user32', 'GetAsyncKeyState', int32(1)) ~= 0;
                %             R = calllib('user32', 'GetAsyncKeyState', int32(2)) ~= 0;
                %             M = calllib('user32', 'GetAsyncKeyState', int32(4)) ~= 0;
            else
                vprintf(3,1,'No support yet for non-Windows operating systems!')
                L = 0;
            end
        end
        
    end
    
end