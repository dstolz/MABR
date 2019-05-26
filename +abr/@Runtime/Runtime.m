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
            % prepare

        end
        
        function timer_runtime(~,~,obj)
            % kick-out if states agree
            if obj.mapCom.Data.ForegroundState == obj.mapCom.Data.BackgroundState, return; end

            if obj.isBackground
                % check if the foreground state has changed


                switch obj.mapCom.Data.ForegroundState

                    case abr.ACQSTATE.ERROR

                    case abr.ACQSTATE.IDLE

                    case abr.ACQSTATE.ACQUIRE

                    case abr.ACQSTATE.CANCELLED

                    case abr.ACQSTATE.PAUSED

                    case abr.ACQSTATE.ADVANCE

                    case abr.ACQSTATE.REPEAT

                    case abr.ACQSTATE.COMPLETED

                    case abr.ACQSTATE.START

                    case abr.ACQSTATE.STOP

                end

            else
                % check if the backgorund state has changed
                switch obj.mapCom.Data.BackgroundState

                    case abr.ACQSTATE.ERROR

                    case abr.ACQSTATE.IDLE

                    case abr.ACQSTATE.ACQUIRE

                    case abr.ACQSTATE.CANCELLED

                    case abr.ACQSTATE.PAUSED

                    case abr.ACQSTATE.ADVANCE

                    case abr.ACQSTATE.REPEAT

                    case abr.ACQSTATE.COMPLETED

                    case abr.ACQSTATE.START

                    case abr.ACQSTATE.STOP

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