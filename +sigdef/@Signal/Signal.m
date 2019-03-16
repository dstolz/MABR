classdef Signal % < handle
    % Signal
    %
    % Daniel Stolzberg, PhD (c) 2019
    
    
    properties (GetAccess = public, SetAccess = public)
        Fs              (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 48000; % Hz
        
        
        dacChannel      (1,1) uint8  {mustBeNonempty,mustBePositive,mustBeFinite} = 1;
        
        % COMMON SIGNAL PROPERTIES
        soundLevel      (1,1) sigdef.sigProp
        duration        (1,1) sigdef.sigProp
        onsetDelay      (1,1) sigdef.sigProp
        polarity        (1,1) sigdef.sigProp
        
        windowFcn       (1,1) sigdef.sigProp
        windowOpts      (1,1) sigdef.sigProp
        windowRFTime    (1,1) sigdef.sigProp
                
        
%         parameterTbl;
        
        
    end
    
    
    properties (GetAccess = public, SetAccess = private,Dependent)
        timeVector      (:,1) double {mustBeFinite};
        N = 0;
    end
    
    properties (SetAccess = protected, GetAccess = public)
        data % waveform data
        dataParams
        Type
    end
    
    properties (Access = protected, Hidden = true, Transient)
        ignoreProcessUpdate = false;
    end
    
    
    methods
        % Constructor
        function obj = Signal(duration,onsetDelay,soundLevelDB)
            obj.ignoreProcessUpdate = true;
            
            % Note that all time parameters should be specified in second and
            % converted before updating the property.
            obj.soundLevel  = sigdef.sigProp(60,'Sound Level','dB');
            obj.soundLevel.Alias = 'Level';
            
            obj.duration    = sigdef.sigProp(5,'Duration','ms',0.001);
            obj.duration.Alias = 'Duration';
            
            obj.onsetDelay  = sigdef.sigProp(0, 'Onset Delay','ms',0.001);
            obj.onsetDelay.Alias = 'Onset Delay';
            
            obj.polarity    = sigdef.sigProp([-1 1], 'Polarity (+1|-1)',[],[],true);
            obj.polarity.Alias = 'Polarity';
            
            obj.windowFcn   = sigdef.sigProp('blackmanharris','Window Function');
            obj.windowFcn.Alias = 'Window Fcn';
            obj.windowFcn.Validation = 'ischar(%g);';
            obj.windowFcn.Type = 'String';
            obj.windowFcn.Function = @sigdef.Signal.selectWindowFcn;
           
            obj.windowOpts = sigdef.sigProp([],'Window Options');
            obj.windowOpts.Alias = 'Window Opts';

            obj.windowRFTime = sigdef.sigProp(1,'Window Rise/Fall Time','ms',0.001);
            obj.windowRFTime.Alias = 'Window R/F Time';
            
            % obj = Signal(duration,onsetDelay,soundLevelDB,windowFcn)
            if nargin >= 1 && ~isempty(duration),     obj.duration.Value   = duration; end
            if nargin >= 2 && ~isempty(osnsetDelay),  obj.onsetDelay.Value = onsetDelay; end
            if nargin >= 3 && ~isempty(SoundLevelDB), obj.soundLevel.Value = soundLevelDB; end
            
            obj.ignoreProcessUpdate = false;
        end
        
        
        
        
        function obj = applyGate(obj)
            
            n = round(obj.Fs*obj.windowRFTime.realValue)*2;
            
            wo = obj.windowOpts.Value;
            if isempty(wo) || isequal(wo,'[]')
                w = window(str2func(obj.windowFcn.Value),n);
            else
                w = window(str2func(obj.windowFcn.Value),n,obj.windowOpts.Value{:});
            end
            
            % apply to each waveform
            for i = 1:numel(obj.data)
                wg = [w(1:n/2); ones(length(obj.data{i})-n,1); w(n/2+1:end)];
                if length(wg) > length(obj.data{i}), wg(round(length(wg)/2)) = []; end
                obj.data{i} = obj.data{i}.*wg;
            end
        end
        
        
        
        
        % Get/Set Properties
        function t = get.timeVector(obj)
            d = obj.duration.realValue;
            t = cell(size(d));
            for i = 1:length(d)
                t{i} = (0:1/obj.Fs:d(i)-1/obj.Fs)';
            end
        end
        
        function n = get.N(obj)
            n = length(obj.timeVector);
        end
        
        function obj = set.duration(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.duration = value;
            else
                mustBePositive(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.duration.Value = value;
                obj.processUpdate;
            end
        end
        
        
        function obj = set.onsetDelay(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.onsetDelay = value;
            else
                mustBeNonnegative(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.onsetDelay.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.polarity(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.polarity = value;
            else
                mustBeNonempty(value);
                mustBeMember(value,[-1 1]);
                obj.polarity.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.windowFcn(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.windowFcn = value;
            else
                mustBeNonempty(value);
                assert(ischar(value),'Must be char');
                obj.windowFcn.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.windowOpts(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.windowOpts = value;
            else
                obj.windowOpts.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.windowRFTime(obj,wrf)
            if isa(wrf,'sigdef.sigProp')
                obj.windowRFTime = wrf;
            else
                mustBePositive(wrf);
                mustBeFinite(wrf);
                mustBeNonempty(wrf);
                obj.windowRFTime.Value = wrf;
                obj.processUpdate;
            end
        end
        
        function processUpdate(obj)
            if obj.ignoreProcessUpdate, return; end
            
            obj.update; % subclass function
            
            h = findobj('type','line','-and','tag','SignalPlot');
            if ~isempty(h)
                plot(obj,h.Parent);
            end
        end
        
%         function obj = set.parameterTbl(obj,h)
%             assert(isa(h,'matlab.ui.control.Table'),'parameterTbl must be handle to a uitable object');
%             obj.parameterTbl = h;
%             
%             h.ColumnName     = {'Parameter','Value'};
%             h.ColumnEditable = [false,true];
%             h.ColumnWidth    = {125,125};
%             h.ColumnFormat   = {'char','numeric'};
%             
%             superclassProps = properties(sigdef.Signal);
%             subclassProps   = properties(obj);
%             
%             ind = ismember(subclassProps,superclassProps);
%             subclassProps(ind) = [];
%             
%             h.Data = {[]};
%             for i = 1:length(subclassProps)
%                 h.Data{i,1} = obj.getDescription(subclassProps{i});
%                 h.Data{i,2} = obj.(subclassProps{i});
%             end
%             
%             h.UserData = subclassProps;
%         end
        
%         function gatherParameterTbl(obj)
%             assert(isa(obj.parameterTbl,'matlab.ui.control.Table'),'parameterTbl must be handle to a uitable object');
%             
%             h = obj.parameterTbl;
%             
%             subclassProps = h.UserData;
%             
%             obj.ignoreProcessUpdate = true;
%             for i = 1:size(h.Data,1)
%                 obj.(subclassProps{i}) = h.Data{i,2};
%             end
%             obj.ignoreProcessUpdate = false;
%             obj.processUpdate;
%         end
        
        
        
        
        
        
        % Overloaded methods ----------------------------------------------
        function signalAnalyzer(obj)
            fprintf('Launching Signal Analyzer ...')
            signalAnalyzer(obj.data,'TimeValues',obj.timeVector);
            fprintf(' done\n')
        end
        
        function h = plot(obj,ax,varargin)
            % h = plot(obj,[ax],[varargin]);
            
            if nargin < 2 || ~ishandle(ax), ax = gca; end
                        
            
            % BROKEN!!!
            
            h = findobj(ax,'type','line','-and','tag','SignalPlot');
            if isempty(h) && ~isempty(obj.data)
                h = plot(ax,obj.timeVector*1000,obj.data,'Tag','SignalPlot', ...
                    'linewidth',2,varargin{3:end});
                grid(ax,'on');
                
                ax.XAxis.Label.String = 'time (ms)';
                ax.YAxis.Label.String = 'amplitude';
                
            elseif isempty(obj.data) 
                set(h,'XData',nan,'YData',nan);
            else
                for i = 1:size(obj.data,2)
                    set(h(i),'XData',obj.timeVector*1000,'YData',obj.data(:,i));
                end
            end
            
            if ~isempty(obj.data)
                y = max(abs(obj.data(:))) * 1.1;
                ax.YAxis.Limits = [-y y];
            end
            
        end
        
        
    end
    
    
    methods (Static)
        % FUNCTIONS MUST ACCEPT ONE INPUT WHICH WILL BE OF THIS CLASS TYPE: sigdef.Signal
        % FUNCTIONS SHOULD RETURN 'NOVALUE' INSTEAD OF EMPTY VARIABLE
        
        function w = selectWindowFcn(obj)
            
            win = {'bartlett','barthannwin','blackman','blackmanharris', ...
                'bohmanwin','chebwin','flattopwin','gausswin','hamming', ...
                'hann','kaiser','nuttallwin','parzenwin','rectwin', ...
                'taylorwin','tukeywin','triang'};
            
            iv = find(ismember(win,obj.windowFcn.Value));
            
            
            [idx,ok] = listdlg('PromptString','Select a window:', ...
                'SelectionMode','single','ListString',win,'InitialValue',iv);
            
            if ok
                w = win{idx};
            else
                w = 'NOVALUE';
            end
        end
        
        
        function ffn = selectAudioFiles(obj)
            
            ext = {'*.wav', 'WAVE (*.wav)'; ...
                '*.ogg', 'OGG (*.ogg)'; ...
                '*.flac','FLAC (*.flac)'; ...
                '*.au',  'AU (*.au)'; ...
                '*.aiff;*.aif','AIFF (*.aiff,*.ai)'; ...
                '*.aifc','AIFC (*.aifc)'};
            if ispc
                ext = [ext; ...
                    {'*.mp3','MP3 (*.mp3)'; ...
                    '*.m4a;*.mp4','MPEG-4 AAC (*.m4a,*.mp4)'}];
            end
            
            [fn,pn] = uigetfile(ext,'Audio Files','MultiSelect','on');
            
            if isequal(fn,0), ffn = 'NOVALUE'; return; end
            
            if iscell(fn)
                ffn = cellfun(@(a) fullfile(pn,a),fn,'uni',0);
            else
                ffn = {fullfile(pn,fn)};
            end
        end
    end
    
end