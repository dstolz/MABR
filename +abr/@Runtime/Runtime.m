classdef Runtime < handle
% Daniel Stolzberg (c) 2019

    properties
        Role (1,:) char {mustBeMember(Role,{'foreground','background'})} = 'foreground';
        
        mapCom          % memmapfile object
        mapInputBuffer  % memmapfile object
    end
    
    properties (SetAccess = private)
        Timer % timer object
        
        Universal   abr.Universal
    end
    
    properties (Access = private)
        AFR     % dsp.AudioFileReader
        APR     % auidoPlayerRecorder
    end
    
    properties (Constant)
        timerPeriod = 0.05;
    end
    
    methods

        % Constructor
        function obj = Runtime(Role)
            if nargin == 0 || isempty(Role), Role = 'foreground'; end
            obj.Role = Role;

            obj.create_memmapfile;

            if isequal(Role,'background')
                
                % Make sure MATLAB is running at full steam
                [s,w] = dos('wmic process where name="MATLAB.exe" CALL setpriority 128'); % 128 = High
                if s ~=0
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
            fwrite(f, abr.ACQSTATE.INIT, 'int8'); % BoregroundState
            fwrite(f,  1, 'double'); % LatestIdx
            
            fclose(f);

            
            
            
            % second memmapped file for input buffer
            if exist(obj.Universal.inputBufferFile, 'file'), delete(obj.Universal.inputBufferFile); end
            [f, msg] = fopen(obj.Universal.inputBufferFile, 'wb');
            if f == -1
                error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                    'Cannot open file "%s": %s.', obj.Universal.inputBufferFile, msg);
            end
            fwrite(f, zeros(60e6,2,'single'), 'single'); % Buffer
            fclose(f);
            
            
            
            % Memory map the file.
            % Both roles writeable for two-way communication
            obj.mapCom = memmapfile(obj.Universal.comFile,'Writable', true,...
            'Format', { ...
                'int8',     [1,1], 'ForegroundState'; ...
                'int8',     [1,1], 'BackgroundState'; ...
                'uint32'    [1 1], 'LatestIdx'});
            
            % Writeable for the background process only
            obj.mapInputBuffer = memmapfile(obj.Universal.inputBufferFile, ...
                'Writable', isequal(obj.Role,'background'), ...
                'Format', {'single' [60e6 2] 'InputBuffer'});
                
        end
        
        
        
        function initialize_timer(obj)
            % for background process
            obj.build_timer;
            start(obj.Timer);
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

        function timer_start(obj)
            % make sure there's a global file to monitor
            obj.create_memmapfile;

        end
        
        function timer_runtime(obj)
            % monitor the global file
            
        end
        
        function timer_stop(obj)
            % all done
        end
        
        function timer_error(obj)
            % wtf
        end



    end
end