classdef Signal < handle % & matlab.mixin.Heterogeneous
    % Signal
    %
    % Daniel Stolzberg, PhD (c) 2019
    
    
    properties (GetAccess = public, SetAccess = public)
        Fs             (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 48000; % Hz
        
        dacChannel     (1,1) uint8  {mustBeNonempty,mustBePositive,mustBeFinite} = 1;
        soundLevelDB   (1,1) double {mustBeNonempty,mustBeFinite,mustBeNonNan} = 60; % dB
        duration       (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 0.005; % seconds
        onsetDelay     (1,1) double {mustBeNonempty,mustBeNonnegative,mustBeLessThanOrEqual(onsetDelay,0.5)} = 0; % seconds
        polarity       (1,1) int8   {mustBeNonempty,mustBeMember(polarity,[-1, 1])} = 1; % -1 or +1
        
        name           (1,:) char = '';
        
        data           (:,1) double {mustBeFinite,mustBeGreaterThanOrEqual(data,-1),mustBeLessThanOrEqual(data,1)}; % summed signal
        
        
        parameterTbl;
    end
    
    properties (Constant = true)
        % Note that all time parameters should be specified in second and
        % converted before updating the property.
        D_soundLevelDB  = 'Sound Level (dB)';
        D_duration      = 'Duration (ms)';
        D_onsetDelay    = 'Onset Delay (ms)';
        D_polarity      = 'Polarity (+1 | -1)';
        F_windowFcn     = @sigdef.Signal.selectWindowFcn;
        M_windowFcn     = 'string'; % str
    end
    
    properties (GetAccess = public, SetAccess = private, Dependent)
        timeVector    (:,1) double {mustBeFinite};
        N = 0;
    end
    
    
    properties (GetAccess = protected, SetAccess = private, Hidden = true, Transient)
        ignoreProcessUpdate = false;
        
        guiRowSpacing = 20;
        guiColSpacing = 10;
        guiLblWidth   = 60;
        guiTxtWidth   = 40;
        guiCmpHeight  = 20;
    end
    
    
    methods
        % Constructor
        function obj = Signal(duration,onsetDelay,soundLevelDB,windowFcn)
            % obj = Signal(duration,onsetDelay,soundLevelDB,windowFcn)
            if nargin >= 1, obj.duration = duration; end
            if nargin >= 2, obj.onsetDelay = onsetDelay; end
            if nargin >= 3, obj.soundLevelDB = soundLevelDB; end
            if nargin >= 4, obj.windowFcn = windowFcn; end
            
        end
        
        % Destructor
        function delete(obj)
            
        end
        
        function applyGate(obj)
            if isequal(obj.windowFcn,'none'), return; end
                
            n = round(obj.Fs*obj.windowRFTime)*2;
            w = window(str2func(obj.windowFcn),n,obj.windowOpts{:});
            
            
            w = [w(1:n/2); ones(obj.N-n,1); w(n/2+1:end)];
            if length(w) > obj.N, w(round(length(w)/2)) = []; end
            
            obj.data = obj.data.*w;
        end
        
        
        
        
        % Get/Set Properties
        function t = get.timeVector(obj)
            t = 0:1/obj.Fs:obj.duration-1/obj.Fs;
        end
        
        function n = get.N(obj)
            n = length(obj.timeVector);
        end
        
        function set.duration(obj,dur)
            obj.duration = dur;
            obj.processUpdate;
        end
        
        function set.onsetDelay(obj,od)
            obj.onsetDelay = od;
            obj.processUpdate;
        end
        
        
        function set.polarity(obj,p)
            obj.polarity = p;
            obj.processUpdate;
        end
        
        function processUpdate(obj)
            if obj.ignoreProcessUpdate, return; end
            
            obj.update; % subclass function
            
            h = findobj('type','line','-and','tag','SignalPlot');
            if ~isempty(h)
                plot(obj,h.Parent);
            end
        end
        
        function set.parameterTbl(obj,h)
            assert(isa(h,'matlab.ui.control.Table'),'parameterTbl must be handle to a uitable object');
            obj.parameterTbl = h;

            h.ColumnName = {'Parameter','Value'};
            h.ColumnEditable = [false,true];
            h.ColumnWidth = {125,125};
            h.ColumnFormat = {'char','numeric'};
            
            superclassProps = properties(sigdef.Signal);
            subclassProps   = properties(obj);
            
            ind = ismember(subclassProps,superclassProps);
            subclassProps(ind) = [];
            
            h.Data = {[]};
            for i = 1:length(subclassProps)
                h.Data{i,1} = obj.(['D_' subclassProps{i}]);
                h.Data{i,2} = obj.(subclassProps{i});
            end
            
            h.UserData = subclassProps;
        end
        
        function gatherParameterTbl(obj)
            assert(isa(obj.parameterTbl,'matlab.ui.control.Table'),'parameterTbl must be handle to a uitable object');
            
            h = obj.parameterTbl;
            
            subclassProps = h.UserData;
            
            obj.ignoreProcessUpdate = true;
            for i = 1:size(h.Data,1)
                obj.(subclassProps{i}) = h.Data{i,2};
            end
            obj.ignoreProcessUpdate = false;
            obj.processUpdate;
        end
        
        % Overloaded methods
        function signalAnalyzer(obj)
            fprintf('Launching Signal Analyzer ...')
            signalAnalyzer(obj.data,'TimeValues',obj.timeVector);
            fprintf(' done\n')
        end
        
        function h = plot(obj,ax,varargin)
            % h = plot(obj,[ax],[varargin]);
                        
            if nargin < 2 || ~ishandle(ax), ax = gca; end
            
            h = findobj(ax,'type','line','-and','tag','SignalPlot');
            if isempty(h) && ~isempty(obj.data)
                h = plot(ax,obj.timeVector*1000,obj.data,'Tag','SignalPlot', ...
                    'linewidth',2,varargin{3:end});
                grid(ax,'on');
                
            elseif isempty(obj.data)
                h.XData = nan;
                h.YData = nan;
            else
                h.XData = obj.timeVector*1000;
                h.YData = obj.data;
            end
            
            ax.XAxis.Label.String = 'time (ms)';
            ax.YAxis.Label.String = 'amplitude';
            
            if ~isempty(obj.data)
                y = max(abs(obj.data)) * 1.1;
                ax.YAxis.Limits = [-y y];
            end
            
        end
        
        
    end
    
    
    methods (Static)
        function w = selectWindowFcn
            win = {'bartlett','barthannwin','blackman','blackmanharris', ...
                'bohmanwin','chebwin','flattopwin','gausswin','hamming', ...
                'hann','kaiser','nuttallwin','parzenwin','rectwin', ...
                'taylorwin','tukeywin','triang'};
                        
            [idx,ok] = listdlg('PromptString','Select a window:', ...
                'SelectionMode','single','ListString',win);
            
            if ok
                w = win{idx};
            else
                w = [];
            end
        end
    end
    
end