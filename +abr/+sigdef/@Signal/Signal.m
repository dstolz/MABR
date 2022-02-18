classdef (Abstract,Hidden) Signal
    % Signal
    %
    % Daniel Stolzberg, PhD (c) 2019
    
    
    properties
        Fs           (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 48000; % Hz
        Channel      (1,1) uint8  {mustBeNonempty,mustBePositive,mustBeFinite} = 1;
        
        % COMMON SIGNAL PROPERTIES
        soundLevel      (1,1) abr.sigdef.sigProp
        duration        (1,1) abr.sigdef.sigProp
        onsetDelay      (1,1) abr.sigdef.sigProp
        polarity        (1,1) abr.sigdef.sigProp
        
        windowFcn       (1,1) abr.sigdef.sigProp
        windowOpts      (1,1) abr.sigdef.sigProp
        windowRFTime    (1,1) abr.sigdef.sigProp
        
        Calibration         (1,1) abr.SoundCalibration
        UseCalibration      (1,1) = true;
        
        Label          
    end
    
    
    properties (Dependent)
        timeVector      (:,1) double {mustBeFinite}
        N
        signalCount
        LabelDefault
    end
    
    properties (SetAccess = protected)
        data % waveform data
        dataParams
        informativeParams
        SortProperty (1,:) char = 'soundLevel';
    end
    
    
    properties (Access = protected, Hidden = true, Transient)
        ignoreProcessUpdate = false;
    end
    
    
    methods
        % Constructor
        function obj = Signal(duration,onsetDelay,soundLevelDB)
            obj.ignoreProcessUpdate = true;
            
            obj.Calibration = abr.SoundCalibration;
            
            % Note that all time parameters should be specified in second and
            % converted before updating the property.
            obj.soundLevel  = abr.sigdef.sigProp(80,'Sound Level','dB');
            obj.soundLevel.ValueFormat = '%0.2f';
            obj.soundLevel.Alias = 'Level';
            
            obj.duration    = abr.sigdef.sigProp(5,'Duration','ms',0.001);
            obj.duration.Alias = 'Duration';
            obj.duration.Dependency = 'Duration';
            
            obj.onsetDelay  = abr.sigdef.sigProp(0, 'Onset Delay','ms',0.001);
            obj.onsetDelay.Alias = 'Onset Delay';
            
            obj.polarity    = abr.sigdef.sigProp([-1 1], 'Polarity (+1|-1)',[],[],true);
            obj.polarity.Alias = 'Polarity';
            
            obj.windowFcn   = abr.sigdef.sigProp('blackmanharris','Window Function');
            obj.windowFcn.Alias = 'Window Fcn';
            obj.windowFcn.Validation = 'ischar(%g);';
            obj.windowFcn.Type = 'String';
            obj.windowFcn.Function = @abr.sigdef.Signal.selectWindowFcn;
           
            obj.windowOpts = abr.sigdef.sigProp([],'Window Options');
            obj.windowOpts.Alias = 'Window Opts';

            obj.windowRFTime = abr.sigdef.sigProp(1,'Window Rise/Fall Time','ms',0.001);
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

            if isempty(wo) || ismember(wo,{'[]','~'}) || isnan(wo)
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
        function fs = get.Fs(obj)
            fs = obj.Calibration.Fs;
        end
        
        function obj = set.Fs(obj,Fs)
            obj.Calibration.Fs = Fs;
            
%             p = properties(obj);
%             ind = cellfun(@(a) isa(obj.(a),'abr.sigdef.sigProp'),p);
%             p(~ind) = [];
            
%             ind = cellfun(@(a) isequal(obj.(a).Dependency,'Nyquist'),p);
%             cellfun(@(a) set(obj.(a),'MaxValue',Fs/2),p(ind));
%             
%             ind = cellfun(@(a) isequal(obj.(a).Dependency,'Duration'),p);
%             cellfun(@(a) set(obj.(a),'MinValue',1/Fs),p(ind));
            obj.Fs = Fs;
        end
        
        
        function t = get.timeVector(obj)
            d = obj.duration.realValue;
            t = cell(size(d));
            for i = 1:length(d)
                t{i} = (0:1/obj.Fs:d(i)-1/obj.Fs)';
            end
        end
        
        function n = get.N(obj)
            n = length(obj.timeVector{1});
        end
        
        function n = get.signalCount(obj)
            n = size(obj.data,1);
        end
        
        function obj = set.duration(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.duration = value;
            else
                mustBePositive(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.duration.Value = value;
                obj.processUpdate;
            end
        end
        
        
        
        function obj = set.soundLevel(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.soundLevel = value;
            else
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.soundLevel.Value = value;
                obj.processUpdate; % superclass function
            end
        end
        
        
        function obj = set.onsetDelay(obj,value)
            if isa(value,'abr.sigdef.sigProp')
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
            if isa(value,'abr.sigdef.sigProp')
                obj.polarity = value;
            else
                mustBeNonempty(value);
                mustBeMember(value,[-1 1]);
                obj.polarity.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.windowFcn(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.windowFcn = value;
            else
                mustBeNonempty(value);
                assert(ischar(value),'Must be char');
                obj.windowFcn.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.windowOpts(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.windowOpts = value;
            else
                obj.windowOpts.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.windowRFTime(obj,wrf)
            if isa(wrf,'abr.sigdef.sigProp')
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
            
            return % FOR NOW
            
            if obj.ignoreProcessUpdate, return; end
            
            obj = obj.update; % subclass function
            
            h = findobj('type','line','-and','tag','SignalPlot');
            if ~isempty(h)
                plot(obj,h.Parent);
            end
        end
        
        
        function cal = export_calibration(obj)
            assert(obj.Calibration.calibration_is_valid,'abr.sigdef.Signal:export_calibration', ...
                'Calibration invalid');

            cal = copy(obj.Calibration);
        end
        
        
        function lbl = get.Label(obj)
            if isempty(obj.Label)
                obj.Label = obj.LabelDefault;
            end
            lbl = obj.Label;
        end
        
        function lbl = get.LabelDefault(obj)
            lbl = {};
            for i = 1:length(obj.informativeParams)
                p = obj.(obj.informativeParams{i});
                lbl{i,1} = sprintf('%s = %g %s', ...
                    p.Alias,p.Value,p.Unit);
            end
        end
        
        
        % Overloaded methods ----------------------------------------------
        function signalAnalyzer(obj)
            vprintf(0,'Launching Signal Analyzer ...')
            signalAnalyzer(obj.data{1},'TimeValues',obj.timeVector{1});
        end
        
        function h = plot(obj,ax,varargin)
            % h = plot(obj,[ax],[varargin]);
            
            if nargin < 2 || ~ishandle(ax), ax = gca; end
                                    
            h = findobj(ax,'type','line','-and','tag','SignalPlot');
            
            origHold = ax.NextPlot;
            if isequal(origHold,'replace'), cla(ax); end
            hold(ax,'on');
            for i = 1:length(obj.data)
                tvec = obj.timeVector{i} * 1000;
                plot(ax,tvec,obj.data{i},'DisplayName',char(join(obj.Label,',')));
            end
            if isequal(origHold,'replace')
                grid(ax,'on');
                legend(ax,'Location','best');
            end
            
            ax.NextPlot = origHold;
            
            if nargout == 0, clear h; end
            
        end
        
%         function disp(obj)
%             props = properties(obj);
%             props = sort(props);
%             n = max(cellfun(@length,props)) + 1;
%             d = '';
%             
%             for i = 1:length(props)
%                 v = obj.(props{i});
%                 if isnumeric(v)
%                     d = sprintf('%s%+*s: %g\n',d,n,props{i},v);
%                 elseif ischar(v)
%                     d = sprintf('%s%+*s: ''%s''\n',d,n,props{i},v);
%                 elseif isa(v,'abr.sigdef.sigProp')
%                     d = sprintf('%s%+*s: %s\n',d,n,props{i},v.info_text);
%                 end
%             end
%             
%             disp(d)
%         end
        
        function obj = sort(obj,prop,sortDir)
            if nargin < 2, prop = obj.SortProperty; end
            if nargin < 3, sortDir = 'ascend'; end
            
            mustBeMember(sortDir,{'ascend','descend'});
            
            P = properties(obj);
            ind = cellfun(@(a) isa(obj.(a),'abr.sigdef.sigProp'),P);
            P(~ind) = [];
            
            assert(ischar(prop) && ismember(prop,P),'Invalid property.');
            
            if isempty(obj.data)
                obj = obj.update;
            end
            
            [~,idx] = sort(obj.dataParams.(prop),sortDir);
            
            obj.data = obj.data(idx);
            
            dp = fieldnames(obj.dataParams);
            for i = 1:length(dp)
                obj.dataParams.(dp{i}) = obj.dataParams.(dp{i})(idx);
            end
        end

        function tf = signal_is_valid(obj)
            obj.update;
            tf = ~isempty(obj.data);
        end
        
    end
    
    
    methods (Static)
        % FUNCTIONS MUST ACCEPT ONE INPUT WHICH WILL BE OF THIS CLASS TYPE: abr.sigdef.Signal
        % FUNCTIONS SHOULD RETURN 'NOVALUE' INSTEAD OF EMPTY VARIABLE
        % ... then why are these static?
        
        function w = selectWindowFcn(obj)
            dfltwin = 'blackmanharris';
            if nargin == 1 && ~isempty(obj)
                if ischar(obj)
                    dfltwin = obj;
                else
                    dfltwin = obj.windowFcn.Value;
                end
            end
            
            win = {'bartlett','barthannwin','blackman','blackmanharris', ...
                'bohmanwin','chebwin','flattopwin','gausswin','hamming', ...
                'hann','kaiser','nuttallwin','parzenwin','rectwin', ...
                'taylorwin','tukeywin','triang'};
            
            iv = find(ismember(win,dfltwin));
            
            
            [idx,ok] = listdlg('PromptString','Select a window:', ...
                'SelectionMode','single','ListString',win,'InitialValue',iv);
            
            if ok
                w = win{idx};
            else
                w = 'NOVALUE';
            end
        end
        
        
        function ffn = selectAudioFiles
            
            ext = { ...
                '*.wav', 'WAVE (*.wav)'; ...
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