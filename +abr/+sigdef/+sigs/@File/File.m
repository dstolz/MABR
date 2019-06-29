classdef File < abr.sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        fullFilename    (1,1) abr.sigdef.sigProp
    end
    
    properties (SetAccess = private, GetAccess = public, Hidden = true)
        info
        filename = '';
        filepath = '';
        fileext  = '';
    end
    
    
    properties (Constant)
        type = 'File';
    end
    
    methods
        
        % Constructor
        function obj = File(fullFilename)
            obj.ignoreProcessUpdate = true;

            if nargin < 1 || isempty(fullFilename), fullFilename = ''; end

            obj.fullFilename = abr.sigdef.sigProp(fullFilename,'Audio Files');
            obj.fullFilename.Alias    = 'Filename';
            obj.fullFilename.Type     = 'File';
            obj.fullFilename.Function = @sigdef.Signal.selectAudioFiles;
            
            obj.informativeParams = {'filename','soundLevel'};
            
            obj.ignoreProcessUpdate = false;

        end
        
        function obj = update(obj)
            ffn = obj.fullFilename.Value;
        
            fnex = cellfun(@(a) exist(a,'file')==2,ffn);
            
            assert(all(fnex==true),sprintf('%d of %d files do not exist!',sum(fnex),numel(fnex)));
            
            A    = obj.soundLevel.realValue;
            
            k = 1;

            % assume audio file
            for a = 1:numel(A)
                for f = 1:numel(ffn)
                    
                    % first check if calibration has been done
                    if obj.Calibration.calibration_is_valid
                        A_V = obj.calibration.estimate_calibrated_voltage(ffn{f},A(a));
                    else
                        A_V = 1;
                    end

                    ainfo = audioinfo(ffn{f});
                    [y,obj.Fs] = audioread(ffn{f});
                    
                    obj.dataParams.fullFilename = ffn;
                    obj.dataParams.duration     = ainfo.Duration;
                    obj.data{k,1}               = y'; 

                    k = k + 1;
                end
            end

        end
        
        function obj = set.fullFilename(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.fullFilename = value;
                return
            end
                
            if isempty(value)
                obj.duration.Value = [];
                obj.fullFilename.Value = {[]};
                return
            end
            
            obj.fullFilename.Value = cellstr(value);
            
            obj.processUpdate;
        end
        
        function info = get.info(obj)
            if isempty(obj.fullFilename.Value), info = {[]}; return; end
            
            info = cell(obj.fullFilename.N,1);
            for i = 1:length(obj.fullFilename.N)
                info{i} = audioinfo(obj.fullFilename.Value{i});
            end
        end
        
        function pth = get.filepath(obj)
            [pth,value,~] = fileparts(obj.fullFilename);
            if isempty(value), pth = '';
                return
            elseif isempty(pth)
                pth = cd; 
            end
        end
        
        function value = get.filename(obj)
            [~,value,~] =  fileparts(obj.fullFilename);
        end
        
        function ext = get.fileext(obj)
            [~,~,ext] =  fileparts(obj.fullFilename);
        end
        
        
        

        
    end
    
end