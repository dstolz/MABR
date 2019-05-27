classdef Runtime < handle
% Daniel Stolzberg (c) 2019

    properties
        Role (1,:) char {mustBeMember(Role,{'Foreground','Background'})} = 'Foreground';
        
        mapCom          % memmapfile object: communications
        mapInputBuffer  % memmapfile object: circular buffer
    end
    
    properties (SetAccess = private)
        isBackground (1,1) logical
        isForeground (1,1) logical

        Timer % timer object
        
        Universal   abr.Universal

        infoData
    end
    
    properties (Access = private)
        AFR     % dsp.AudioFileReader
        APR     % auidoPlayerRecorder

        lastReceivedCmd     abr.CMD
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
                
                % Make sure MATLAB is running at full steam
                [s,w] = dos('wmic process where name="MATLAB.exe" CALL setpriority 128'); % 128 = High
                if s ~= 0
                    warning('Failed to elevate the priority of MATLAB.exe')
                    disp(w)
                end

                obj.mapCom.BackgroundState = abr.ACQSTATE.IDLE;

            else
                obj.mapCom.ForegroundState = abr.ACQSTATE.IDLE;

            end

            
        end
        
        
        % Destructor
        function delete(obj)
            
        end
        
        

        function create_memmapfile(obj)
            % Create the communications file
            % This needs to be done for all involved instances of matlab.

            % NOTE memmapfile does not support char, but can simply convert using char(m.Data)
            if exist(obj.Universal.comFile, 'file'), delete(obj.Universal.comFile); end
            [f, msg] = fopen(obj.Universal.comFile, 'wb');
            if f == -1
                error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                    'Cannot open file "%s": %s.', obj.Universal.comFile, msg);
            end
            
            % State needs to be padded to a predicatable size
            fwrite(f, abr.ACQSTATE.INIT, 'int8'); % ForegroundState
            fwrite(f, abr.ACQSTATE.INIT, 'int8'); % BackgroundState
            fwrite(f, abr.ACQSTATE.INIT, 'int8'); % CommandToFg
            fwrite(f, abr.ACQSTATE.INIT, 'int8'); % CommandToBg
            fwrite(f,  1, 'double'); % LatestIdx
            
            fclose(f);

            
            
            % memmapped file for the input buffer
            if exist(obj.Universal.inputBufferFile, 'file'), delete(obj.Universal.inputBufferFile); end
            [f, msg] = fopen(obj.Universal.inputBufferFile, 'wb');
            if f == -1
                error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                    'Cannot open file "%s": %s.', obj.Universal.inputBufferFile, msg);
            end
            fwrite(f, zeros(obj.maxInputBufferLength,2,'single'), 'single'); % Buffer
            fclose(f);
            
            
            
            % Memory map the file.
            % Both roles writeable for two-way communication
            obj.mapCom = memmapfile(obj.Universal.comFile,'Writable', true,...
            'Format', { ...
                'int8',     [1,1], 'ForegroundState'; ...
                'int8',     [1,1], 'BackgroundState'; ...
                'int8',     [1,1], 'CommandToFg'; ...
                'int8',     [1,1], 'CommandToBg'; ...
                'uint32'    [1 1], 'LatestIdx'});
            
            % Writeable for the Background process only
            obj.mapInputBuffer = memmapfile(obj.Universal.inputBufferFile, ...
                'Writable', obj.isBackground, ...
                'Format', {'single' [obj.maxInputBufferLength 2] 'InputBuffer'});
                
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

            eval(e,varname,vardata);

            lastUpdated = now;
            save(obj.Universal.infoFile,varname,'lastUpdated','-append')
        end
    end
    
    
    
    methods (Access = private)

        function build_timer(obj)
            t = timerfindall('Tag','ABR_Runtime');
            if ~isempty(t) && isvalid(t)
                stop(t);
                delete(t);
            end
            
            T = timer('Name',obj.Name);
            T.BusyMode = 'drop';
            T.ExecutionMode = 'fixedSpacing';
            T.TasksToExecute = inf;
            T.Period = obj.Period;

            T.StartFcn = {obj.timer_start};
            T.TimerFcn = {obj.timer_runtime};
            T.StopFcn  = {obj.timer_stop};
            T.ErrorFcn = {obj.timer_error};
        end



    end

    
    
    methods (Static)

        function timer_start(~,~,obj)

        end
        
        function timer_runtime(~,~,obj)
            
            if obj.isBackground
                if obj.lastReceivedCmd == obj.mapCom.Data.CommandToBg, return; end
                obj.lastReceivedCmd = obj.mapCom.Data.CommandToBg;

                try
                    switch obj.mapCom.Data.CommandToBg
                        case abr.CMD.Prep
                                obj.prepare_block_bg; % sets up audioFileReader and audioPlayerRecorder
                                obj.mapCom.Data.CommandToFg = abr.CMD.Ready;

                        case abr.CMD.Run
                                obj.acquire_block; % runs playback/acquisition
                                obj.mapCom.Data.CommandToFg = abr.CMD.Completed;
                            
                    end
                catch me
                    obj.mapCom.Data.CommandToFg = abr.CMD.Error;
                    str = sprintf('%s\n%s',me.identifier,me.message);
                    obj.update_infoData('lastError_Bg',str);
                end

                
            else
                if obj.lastReceivedCmd == obj.mapCom.Data.CommandToFg, return; end
                obj.lastReceivedCmd = obj.mapCom.Data.CommandToFg;

                switch obj.mapCom.Data.CommandToFg
                    case abr.CMD.Idle
                    case abr.CMD.Prep
                    case abr.CMD.Run
                    case abr.CMD.Stop
                end
            end
        end
        
        function timer_stop(~,~,obj)
            % all done
        end
        
        function timer_error(~,~,obj)
            % wtf
            obj.mapCom.Data.([obj.Role 'State']) = abr.ACQSTATE.ERROR;
        end
    end
end