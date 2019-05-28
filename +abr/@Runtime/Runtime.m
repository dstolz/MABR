classdef Runtime < handle
    % Daniel Stolzberg (c) 2019
    
    properties        
        mapCom          % memmapfile object: communications
        mapInputBuffer  % memmapfile object: circular buffer        
    end
    
    properties (SetAccess = private)
        Role (1,:) char {mustBeMember(Role,{'Foreground','Background'})} = 'Foreground';

        isBackground (1,1) logical
        isForeground (1,1) logical
        
        BgIsRunning (1,1) logical
        FgIsRunning (1,1) logical
        
        Timer % timer object
        
        Universal = abr.Universal;
        
        infoData
        
        
        timer_RuntimeFcn (1,1) = @abr.Runtime.timer_runtime; % function handle
        timer_ErrorFcn   (1,1) = @abr.Runtime.timer_error; % function handle
        
        
        lastReceivedCmd     abr.Cmd
    end
    
    properties (Access = private)
        AFR     % dsp.AudioFileReader
        APR     % auidoPlayerRecorder
        
    end
    
    properties (Constant)
        timerPeriod = 0.01;
        maxInputBufferLength = 2^25; % should be power of 2 enough for at least a minute of data at 192kHz sampling rate
    end
    
    methods
        
        % Constructor
        function obj = Runtime(Role)
            if nargin == 0 || isempty(Role), Role = 'Foreground'; end
            obj.Role = Role;
            
            obj.create_memmapfile;
            
            if obj.isBackground
                
                abr.Universal.startup;
                
                % Make sure MATLAB is running at full steam
                [s,w] = dos('wmic process where name="MATLAB.exe" CALL setpriority 128'); % 128 = High
                if s ~= 0
                    warning('Failed to elevate the priority of MATLAB.exe')
                    disp(w)
                end
                
                obj.mapCom.Data.BackgroundState = int8(abr.stateAcq.IDLE);
                
                obj.initialize_timer;
                
            else
                obj.mapCom.Data.ForegroundState = int8(abr.stateAcq.IDLE);
            end
            
            obj.update_infoData(sprintf('%s_ProcessID',obj.Role),feature('getpid'));
            
        end
        
        
        % Destructor
        function delete(obj)
            try
                if obj.isBackground
                    obj.mapCom.Data.BackgroundState = int8(abr.stateAcq.DELETED);
                else
                    obj.mapCom.Data.ForegroundState = int8(abr.stateAcq.DELETED);
                end
            end
            
            try
                stop(obj.Timer);
                delete(obj.Timer);
            end
        end
        
        function tf = get.BgIsRunning(obj)
%             tf = obj.mapCom.Data.BackgroundState > -3;
            [~,pidstr] = system('Wmic process where (Name like ''MATLAB.exe'') get ProcessId');
            p = splitlines(pidstr);
            p(1) = [];
            p = cellfun(@deblank,p,'uni',0);
            ind = ismember(num2str(obj.infoData.Background_ProcessID),p);
            tf = any(ind);
        end
        
        
        function tf = get.FgIsRunning(obj)
%             tf = obj.mapCom.Data.ForegroundState > -3;
            [~,pidstr] = system('Wmic process where (Name like ''MATLAB.exe'') get ProcessId');
            p = splitlines(pidstr);
            p(1) = [];
            p = cellfun(@deblank,p,'uni',0);
            ind = ismember(num2str(obj.infoData.Foreground_ProcessID),p);
            tf = any(ind);
        end
        
        function create_memmapfile(obj)
            % Create the communications file
            % This needs to be done for all involved instances of matlab.
            
            % NOTE memmapfile does not support char, but can simply convert using char(m.Data)
            if ~exist(obj.Universal.comFile, 'file')
                [f, msg] = fopen(obj.Universal.comFile, 'wb');
                if f == -1
                    error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                        'Cannot open file "%s": %s.', obj.Universal.comFile, msg);
                end
                
                % State needs to be padded to a predicatable size
                fwrite(f, -99, 'int8'); % ForegroundState
                fwrite(f, -99, 'int8'); % BackgroundState
                fwrite(f, -99, 'int8'); % CommandToFg
                fwrite(f, -99, 'int8'); % CommandToBg
                fwrite(f, [1 obj.Universal.frameLength], 'uint32'); % BufferIndex
                fwrite(f, 0,   'uint32');
                fclose(f);
            end
            
            % memmapped file for the input buffer
            if ~exist(obj.Universal.inputBufferFile, 'file')
                [f, msg] = fopen(obj.Universal.inputBufferFile, 'wb');
                if f == -1
                    error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                        'Cannot open file "%s": %s.', obj.Universal.inputBufferFile, msg);
                end
                fwrite(f, zeros(obj.maxInputBufferLength,2,'single'), 'single'); % Buffer
                fclose(f);
            end
            
            
            % Memory map the file.
            % Both roles writeable for two-way communication
            obj.mapCom = memmapfile(obj.Universal.comFile,'Writable', true,...
                'Format', { ...
                'int8',     [1,1], 'ForegroundState'; ...
                'int8',     [1,1], 'BackgroundState'; ...
                'int8',     [1,1], 'CommandToFg'; ...
                'int8',     [1,1], 'CommandToBg'; ...
                'uint32',   [1 2], 'BufferIndex'; ...
                'uint32',   [1 1], 'TimingIndex'});
            
            % Writeable for the Background process only
            obj.mapInputBuffer = memmapfile(obj.Universal.inputBufferFile, ...
                'Writable', obj.isBackground, ...
                'Format', { ...
                'single' [obj.maxInputBufferLength 2] 'InputBuffer'});
            
            % reset memmaps
            if obj.isBackground
                obj.mapCom.Data.BackgroundState = int8(abr.stateAcq.INIT);
            else
                obj.mapCom.Data.ForegroundState = int8(abr.stateAcq.INIT);
            end
            
        end
        
        
        
        function initialize_timer(obj)
            % for Background process
            obj.build_timer;
            
            start(obj.Timer);
        end
        
        function tf = get.isBackground(obj)
            tf = isequal(obj.Role,'Background');
        end
        
        function tf = get.isForeground(obj)
            tf = isequal(obj.Role,'Foreground');
        end
        
        function info = get.infoData(obj)
            % should be non-time critical data used to communicate between foreground and background process.
            
            % ADC.channels.signal
            % ADC.channels.timing
            % DAC.channels.signal
            % DAC.channels.timing
            
            info = load(obj.Universal.infoFile);
        end
        
        function update_infoData(obj,varname,vardata)
            switch class(vardata)
                case {'single','double'}
                    e = '%s = %f;';
                case {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'}
                    e = '%s = %d;';
                case {'char','string'}
                    e = '%s = %s;';
            end
            
            eval(sprintf(e,varname,vardata));
            
            lastUpdated = now;
            
            if exist(obj.Universal.infoFile,'file') == 2
                save(obj.Universal.infoFile,varname,'lastUpdated','-append');
            else
                save(obj.Universal.infoFile,varname,'lastUpdated');
            end
        end
    end
    
    
    
    methods (Access = private)
        
        function build_timer(obj)
            t = timerfindall('Tag','ABR_Runtime');
            if ~isempty(t) && isvalid(t)
                stop(t);
                delete(t);
            end
            
            T = timer('Tag','ABR_Runtime');
            T.BusyMode = 'drop';
            T.ExecutionMode = 'fixedSpacing';
            T.TasksToExecute = inf;
            T.Period = obj.timerPeriod;
            
            T.TimerFcn = {obj.timer_RuntimeFcn,obj};
            T.ErrorFcn = {obj.timer_ErrorFcn,obj};
            
            obj.Timer = T;
        end
    end
    
    methods (Static)
        timer_runtime(T,event,obj);
        timer_error(T,event,obj);
    end
end