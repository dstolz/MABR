classdef TraceOrganizer < handle
    
    properties
        SortBy          (:,1) cell
        SortOrder       (:,1) cell
        
        YPosition       (:,1) double
        YScaling        (1,1) double = 1;
        YSpacing        (1,1) double = 1;
        
        TraceColors  (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(TraceColors,1)}

        Traces      (:,1) Trace
    end
    
    properties (SetAccess = private)
        Labels      (:,1) cell
        N           (1,1) double
        
        PropertyMatrix  double
        PropertyNames   cell
        PlotOrder       (:,1)
        
        informativeProps
    end
    
    properties (Access = private,Transient)
        mainFigTag       (1,:) char
        mainFig          (1,1) %matlab.ui.Figure
        mainAx           (1,1) %matlab.graphics.axis.Axes
        
        tbh
    end
    
    methods
        
        % Constructor
        function obj = TraceOrganizer
            if isempty(obj.mainFigTag)
                obj.mainFigTag = sprintf('BUFFERORGTAG_%d',round(rand(1)*1e9));
            end
        end
        
        
        % Destructor
        function delete(obj)
            obj.clear;
            delete(obj);
        end
        
        
        
        function addTrace(obj,data,props,firstTimepoint,Fs)
            narginchk(3,5);
            if nargin >= 4 && isempty(firstTimepoint), firstTimepoint = 0; end
            if nargin == 5 && isempty(Fs), Fs = 1; end
            if isempty(obj.Traces) || isempty(obj.Traces(1).Data)
                obj.Traces = Trace(data,props,firstTimepoint,Fs);
            else
                obj.Traces(end+1) = Trace(data,props,firstTimepoint,Fs);
            end
            obj.Traces(~isvalid(obj)) = [];
        end
        
        function deleteTrace(obj,idx)
            obj.Traces(idx) = [];
        end
        
        
        
        
        
        
        
        function n = get.N(obj)
            n = numel(obj.Traces);
        end
        
        function y = get.YPosition(obj)
            
            y = 1:obj.YSpacing:obj.N*obj.YSpacing;
            
        end
        
        function set.YSpacing(obj,yspace)
            obj.YSpacing = yspace;
            obj.plot;
        end
        
        function set.YScaling(obj,yscale)
            obj.YScaling = yscale;
            obj.plot;
        end
        
        function set.TraceColors(obj,colors)
            n = size(colors,1);
            assert(n==obj.N | n==1,'A 1x3 or Nx3 matrix must be provided when setting colors using TraceColors');
            if n == 1
                colors = repmat(colors,obj.N,1);
            end
            obj.TraceColors = colors;
            for i = 1:obj.N
                obj.Traces(i).Color = colors(i,:);
            end
            obj.plot;
        end
        
        function colors = get.TraceColors(obj)
            for i = 1:obj.N
                colors(i,:) = obj.Traces(i).Color;
            end
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
            n = obj.PropertyNames(ind);
        end
        
        function s = get.Labels(obj)
            s = {};
%             b = obj.SortBy;
%             m = obj.PropertyMatrix;
            n = obj.informativeProps;
            for i = 1:obj.N
                s{i} = sprintf('\\color[rgb]{%0.3f,%0.3f,%0.3f}',obj.Traces(i).Color);
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
            for i = 1:length(propNames)
                mustBeMember(propNames{i},n);
            end
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
        
        
        
        
        
        
        
        
        
        
        % Overloaded Functions --------------------------------------------
        function clear(obj,hObj,event)
            if ~obj.N, return; end

%             delete(obj.Traces);
            
            cla(obj.mainAx);
            obj.mainAx.YTick = [];
            
            obj.Traces = Trace;
        end
        
        function load(obj,hObj,event)
            if ischar(hObj)
                % hObj is provided as a filename
                ffn = hObj;
            end
            % ... load buffer data from file
        end
        
        function save(obj,hObj,event)
            
        end
        
        function figure(obj)
            f = findobj('tag',obj.mainFigTag);
            if isempty(f)
                f = figure( ...
                    'Tag',obj.mainFigTag, ...
                    'Toolbar','none', ...
                    'Color',[1 1 1], ...
                    'Position',[800 30 570 620]);
                
                obj.mainFig = f;
                obj.create_toolbar;
                
                obj.mainAx = axes(f, ...
                    'Color',[1 1 1], ...
                    'Units','normalized', ...
                    'Position',[0.2 0.1 0.75 0.8], ...
                    'YTick',[], ...
                    'GridColor',[0.2 0.2 0.2], ...
                    'XGrid','on','YGrid','on', ...
                    'GridLineStyle',':', ...
                    'Box','on', ...
                    'YTickLabelRotation',30);
                obj.mainAx.XAxis.Label.String = 'time (ms)';
                
                
            else
                obj.mainFig = f;
            end
            figure(obj.mainFig);
            

        end
        
        function plot(obj,varargin)
            figure(obj);
            
            D = {obj.Traces.Data};
            
            % normalize trace data
            my = max(abs(cell2mat(D)));
            D = cellfun(@(a) a./ my .* obj.YScaling,D,'uni',0);
            
            pidx = obj.PlotOrder';
            
            for k = pidx
                
                x = obj.Traces(k).TimeVector .* 1000; % s -> ms
                y = D{k} + obj.YPosition(k);
                
                h = obj.Traces(k).LineHandle;
                
                if isempty(h) || ~isgraphics(h)
                    h = line;
                    h.Parent = obj.mainAx;
                end
                h.XData = x;
                h.YData = y;
                h.Color = obj.Traces(k).Color;
                h.LineWidth = obj.Traces(k).LineWidth;
                
                obj.Traces(k).LineHandle = h;
                
            end
            
            x = [obj.Traces.TimeVector];
            if isempty(x), x = [0 1]; end
            obj.mainAx.XLim = [min(x) max(x)]*1000;
            obj.mainAx.YAxis.TickValues = obj.YPosition;
            obj.mainAx.YAxis.TickLabels = obj.Labels;
            
        end
        
        
    end
    
    methods (Access = private)
        
        function create_toolbar(obj)
            obj.tbh.toolbar = uitoolbar(obj.mainFig);
            
            
            iconPath = fullfile(matlabroot,'toolbox','matlab','icons');
    
            imgFileLoad = imread(fullfile(iconPath,'file_open.png'));
            imgFileLoad = im2double(imgFileLoad);
            imgFileLoad(imgFileLoad == 0) = nan;
            
            imgFileSave = imread(fullfile(iconPath,'file_save.png'));
            imgFileSave = im2double(imgFileSave);
            imgFileSave(imgFileSave == 0) = nan;
            
            imgFileNew = imread(fullfile(iconPath,'file_new.png'));
            imgFileNew = im2double(imgFileNew);
            imgFileNew(imgFileNew == 0) = nan;
            
            
            obj.tbh.pthClear = uipushtool(obj.tbh.toolbar);
            obj.tbh.pthClear.Tooltip = 'Clear';
            obj.tbh.pthClear.ClickedCallback = @obj.clear;
            obj.tbh.pthClear.CData = imgFileNew;
            
            obj.tbh.pthLoad = uipushtool(obj.tbh.toolbar);
            obj.tbh.pthLoad.Tooltip = 'Load';
            obj.tbh.pthLoad.ClickedCallback = @obj.load;
            obj.tbh.pthLoad.CData = imgFileLoad;
            
            obj.tbh.pthSave = uipushtool(obj.tbh.toolbar);
            obj.tbh.pthSave.Tag = 'SaveButton';
            obj.tbh.pthSave.Tooltip = 'Save';
            obj.tbh.pthSave.ClickedCallback = @obj.save;
            obj.tbh.pthSave.CData = imgFileSave;

            
        end
        
    end
    
end