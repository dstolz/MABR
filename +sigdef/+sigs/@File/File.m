classdef File < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        fullFilename   (1,:) char = '';
        windowFcn      (1,:) char   {mustBeNonempty} = 'blackmanharris'; % doc window
        windowOpts     cell = {};
        windowRFTime   (1,2) double {mustBeNonempty,mustBeNonnegative,mustBeFinite} = 0.001; % seconds
        
    end
    
    properties (SetAccess = private, GetAccess = public, Hidden = true)
        info
        filename = '';
        filepath = '';
        fileext  = '';
    end
    
    properties (Constant = true)
        D_fullFilename = 'Filename';
        F_fullFilename = @sigdef.sigs.File.selectFiles;
    end
    
    methods
        
        % Constructor
        function obj = File(fullFilename)
            if nargin < 1 || isempty(fullFilename), fullFilename = ''; end
            
            obj.fullFilename = fullFilename;
            
        end
        
        function update(~)
            % update in set.fullFilename to avoid recursive loop when calling
            % obj.processUpdate
        end
        
        function set.fullFilename(obj,fn)
            if isempty(fn), return; end
            
            obj.fullFilename = fn;
                        
            if isempty(obj.fileext)  %#ok<MCSUP>
                % workspace variable?
                
            else % assume audio file
                obj.info = audioinfo(obj.fullFilename); %#ok<MCSUP>
                [y,obj.Fs] = audioread(obj.fullFilename);
                obj.data = y';
                obj.duration = obj.info.Duration; %#ok<MCSUP>
                
            end
            
            obj.processUpdate;
        end
        
        
        function pth = get.filepath(obj)
            [pth,fn,~] = fileparts(obj.fullFilename);
            if isempty(fn), pth = '';
                return
            elseif isempty(pth)
                pth = cd; 
            end
        end
        
        function fn = get.filename(obj)
            [~,fn,~] =  fileparts(obj.fullFilename);
        end
        
        function ext = get.fileext(obj)
            [~,~,ext] =  fileparts(obj.fullFilename);
        end
        
        
        function set.windowFcn(obj,w)
            obj.windowFcn = w;
            obj.processUpdate;
        end
        
        function set.windowOpts(obj,w)
            obj.windowOpts = w;
            obj.processUpdate;
        end
        
        function set.windowRFTime(obj,wrf)
            if numel(wrf) == 1, wrf = [wrf wrf]; end
            obj.windowRFTime = wrf;
            obj.processUpdate;
        end
        
    end
    
    
    methods (Static)
        function ffn = selectFiles
            ffn = [];
            
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
            
            if isequal(fn,0), return; end
            
            if iscell(fn)
                ffn = cellfun(@(a) fullfile(pn,a),fn,'uni',0);
            else
                ffn = {fullfile(pn,fn)};
            end
        end
        
    end
    
end