classdef File < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        fullFilename (1,:) char = '';
    end
    
    properties (SetAccess = private, GetAccess = public, Hidden = true)
        info
        filename = '';
        filepath = '';
        fileext  = '';
    end
    
    properties (Constant = true, Hidden = true)
        D_fullFilename = 'Filename';
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
    end
    
    
    methods (Static)
        function obj = createDisplay(parent)
            % setup custom fields in some parent figure or panel
        end
    end
    
end