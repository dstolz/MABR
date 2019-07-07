classdef Runtime < handle
    % Daniel Stolzberg (c) 2019
    
    properties        
        mapCom          % memmapfile object: communications
        mapSignalBuffer  % memmapfile object: signal buffer       
        mapTimingBuffer % memmapfile object: timing buffer
        
        CommandToBg     (1,1) abr.Cmd
        CommandToFg     (1,1) abr.Cmd
        
        BackgroundState (1,1) abr.stateAcq
        ForegroundState (1,1) abr.stateAcq
        
        InputAmpGain    (1,1) double = 1;
    end
    
    properties (SetAccess = private)
        Role (1,:) char {mustBeMember(Role,{'Foreground','Background'})} = 'Foreground';

        isBackground (1,1) logical
        isForeground (1,1) logical
        
        BgIsRunning (1,1) logical
        FgIsRunning (1,1) logical
        
        Timer % timer object
        
        Universal   (1,1) abr.Universal = abr.Universal;
        
        infoData
        
        timer_RuntimeFcn (1,1) = @abr.Runtime.timer_runtime; % function handle
        timer_StopFcn    (1,1) = @abr.Runtime.timer_stop; % function handle
        timer_ErrorFcn   (1,1) = @abr.Runtime.timer_error; % function handle
        
        lastReceivedCmd     abr.Cmd
    end
    
    properties (Access = private)
        AFR     % dsp.AudioFileReader
        APR     % auidoPlayerRecorder
        
    end
    
    properties (Constant)
        timerPeriod = 0.01;
    end
    
    methods
        [preSweep,postSweep,sweepCount] = extract_sweeps(obj,timeWindow,doAll);
        idx = find_timing_onsets(obj,varargin);

        % Constructor
        function obj = Runtime(Role)
            abr.Universal.addpaths;

            if nargin == 0 || isempty(Role), Role = 'Foreground'; end
            obj.Role = Role;
            
            obj.update_infoData(sprintf('%s_ProcessID',obj.Role),feature('getpid'));
            
            
            if obj.isBackground
                
                abr.Universal.startup;

                obj.create_memmapfile;

                abr.Runtime.print_do_not_close;

                % Make sure MATLAB is running at full steam
                wmicStr = sprintf('wmic process where processid=''%d'' CALL setpriority 128',obj.infoData.Background_ProcessID);
                [s,w] = dos(wmicStr); % 128 = High
                if s ~= 0
                    warning('Failed to elevate the priority of MATLAB.exe')
                    disp(w)
                end
                
                % reset command to foreground and background state
                obj.CommandToFg     = abr.Cmd.Undef;
                obj.BackgroundState = abr.stateAcq.IDLE;
                
                
                obj.initialize_timer;
                
%                 % HIDE MATLAB PROCESS - doesn't seem to work or not stable
%                 com.mathworks.mde.desk.MLDesktop.getInstance.getMainFrame.hide;
                
            else
                obj.create_memmapfile;

                wmicStr = sprintf('wmic process where processid=''%d'' CALL setpriority 32768',obj.infoData.Foreground_ProcessID);
                [s,w] = dos(wmicStr); % 32768 = Above Normal
                if s ~= 0
                    warning('Failed to elevate the priority of MATLAB.exe')
                    disp(w)
                end
                % reset command to background and foreground state
                obj.CommandToBg     = abr.Cmd.Undef;
                obj.ForegroundState = abr.stateAcq.IDLE;
            end
            
            
        end
        
        
        % Destructor
        function delete(obj)
            
            try
                stop(obj.Timer);
                delete(obj.Timer);
            end
            
            try
                if obj.isBackground
                    obj.BackgroundState = abr.stateAcq.DELETED;
                else
                    obj.ForegroundState = abr.stateAcq.DELETED;
                end
            end
            
            if obj.isBackground
                seppuku;
            end
        end
        
        function tf = get.BgIsRunning(obj)
            pids = obj.get_all_matlab_pids;
            i = obj.infoData;
            if ~isfield(i,'Background_ProcessID'), obj.update_infoData('Background_ProcessID',-1); end
            tf = any(obj.infoData.Background_ProcessID == pids);
        end
        
        
        function tf = get.FgIsRunning(obj)
            pids = obj.get_all_matlab_pids;
            i = obj.infoData;
            if ~isfield(i,'Foreground_ProcessID'), obj.update_infoData('Foreground_ProcessID',-1); end
            tf = any(obj.infoData.Foreground_ProcessID == pids);
        end
        
        function create_memmapfile(obj)
            % Create the communications file
            % This needs to be done for all involved instances of matlab.
            
            % remove .dat files which will be rewritten
            d = dir(fullfile(obj.Universal.runtimePath,'*.dat'));
            if isempty(d), return; end
            ffn = cellfun(@fullfile,{d.folder},{d.name},'uni',0);
            ind = cellfun(@exist,ffn) ~= 2;
            if all(ind), return; end
            ffn(ind) = [];
            warning('off','MATLAB:DELETE:Permission');
            cellfun(@delete,ffn);
            warning('on','MATLAB:DELETE:Permission');
            
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
                fclose(f);
            end
            
            % memmapped file for the input buffer
            if ~exist(obj.Universal.inputBufferFile, 'file')
                [f, msg] = fopen(obj.Universal.inputBufferFile, 'wb');
                if f == -1
                    error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                        'Cannot open file "%s": %s.', obj.Universal.inputBufferFile, msg);
                end
                fwrite(f, zeros(obj.Universal.maxInputBufferLength,1,'single'), 'single'); % Buffer
                fclose(f);
            end
            
            % memmapped file for the timing buffer
            if ~exist(obj.Universal.inputTimingFile, 'file')
                [f, msg] = fopen(obj.Universal.inputTimingFile, 'wb');
                if f == -1
                    error('abr:Runtime:create_memmapfile:cannotOpenFile', ...
                        'Cannot open file "%s": %s.', obj.Universal.inputTimingFile, msg);
                end
                fwrite(f, zeros(obj.Universal.maxInputBufferLength,1,'single'), 'single'); % Buffer
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
                'uint32',   [1 2], 'BufferIndex'}, ...
                'Repeat',1);
            
            % Writeable for the Background process only
            obj.mapSignalBuffer = memmapfile(obj.Universal.inputBufferFile, ...
                'Writable', obj.isBackground, ...
                'Format', 'single', ...
                'Repeat', inf);
            
            
            obj.mapTimingBuffer = memmapfile(obj.Universal.inputTimingFile, ...
                'Writable', obj.isBackground, ...
                'Format', 'single', ...
                'Repeat', inf);

            % reset memmaps
            if obj.isBackground
                obj.mapCom.Data.BackgroundState = int8(abr.stateAcq.INIT);
            else
                obj.ForegroundState = int8(abr.stateAcq.INIT);
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
            

            % not sure why, but every once in a while this will fail even
            % though the file exists and is not locked 
            while 1
                try
                    info = load(obj.Universal.infoFile);
                    break
                catch
                    pause(0.01);
                    vprintf(4,1,'Loading infoData FAILED!')
                end
            end
 
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
        
        function set.BackgroundState(obj,state)
            vprintf(3,'BackgroundState set to %s',state);
            obj.mapCom.Data.BackgroundState = int8(state);
        end
        
        function state = get.BackgroundState(obj)
            state = abr.stateAcq(obj.mapCom.Data.BackgroundState);
        end
        
        function set.ForegroundState(obj,state)
            vprintf(3,'ForegroundState set to %s',state);
            obj.mapCom.Data.ForegroundState = int8(state);
        end
        
        function state = get.ForegroundState(obj)
            state = abr.stateAcq(obj.mapCom.Data.ForegroundState);
        end
        
        function set.CommandToFg(obj,cmd)
            vprintf(3,'CommandToFg set to %s',cmd);
            obj.mapCom.Data.CommandToFg = int8(cmd);
        end
        
        function cmd = get.CommandToFg(obj)
            cmd = abr.Cmd(obj.mapCom.Data.CommandToFg);
        end
        
        function set.CommandToBg(obj,cmd)
            vprintf(3,'CommandToBg set to %s',cmd);
            obj.mapCom.Data.CommandToBg = int8(cmd);
            if cmd == abr.Cmd.Test
                vprintf(0,1,'TEST MODE ENABLED!!!!\n%s',obj.Tools.stack_str(2));
            end
        end
        
        function cmd = get.CommandToBg(obj)
            cmd = abr.Cmd(obj.mapCom.Data.CommandToBg);
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
            T.ExecutionMode = 'fixedRate';
            T.TasksToExecute = inf;
            T.Period = obj.timerPeriod;
            
            T.TimerFcn = {obj.timer_RuntimeFcn,obj};
            T.ErrorFcn = {obj.timer_ErrorFcn,obj};
            
            obj.Timer = T;
        end
        
        
    end
    
    methods (Static)
        timer_runtime(T,event,obj);
        timer_stop(T,event,obj);
        timer_error(T,event,obj);
        
        function pid = get_all_matlab_pids
            [~,pidstr] = system('Wmic process where (Name like ''MATLAB.exe'') get ProcessId');
            p = splitlines(pidstr);
            p(1) = [];
            pid = cellfun(@str2double,cellfun(@deblank,p,'uni',0));
        end
        
        function launch_bg_process
            
            U = abr.Universal;
            
            % setup Background process
            cmdStr = sprintf('addpath(''%s''); H = abr.Runtime(''Background'');', ...
                fileparts(U.root));
            
            vprintf(3,'Launching background process; cmdStr = %s',cmdStr)
            
            [s,w] = system(sprintf('"%s" -sd "%s" -logfile "%s" -nodesktop -minimize -noFigureWindows -nosplash -r "%s"', ...
                U.matlabExePath,U.runtimePath,fullfile(U.runtimePath,'Background_process_log.txt'),cmdStr));
            
            if s
                vprintf(0,1,'FAILED TO LAUNCH BACKGROUND PROCESS!  OH SHIT!\nTry restarting Matlab')
            else
                vprintf(3,'Launched background process; message: %s',w)
            end

        end
        
        
        
        function print_do_not_close
            s = [{' _______    ______         __    __   ______  ________         ______   __        ______    ______   ________  __ '}; ...
                {'|       \  /      \       |  \  |  \ /      \|        \       /      \ |  \      /      \  /      \ |        \|  \'}; ...
                {'| $$$$$$$\|  $$$$$$\      | $$\ | $$|  $$$$$$\\$$$$$$$$      |  $$$$$$\| $$     |  $$$$$$\|  $$$$$$\| $$$$$$$$| $$'}; ...
                {'| $$  | $$| $$  | $$      | $$$\| $$| $$  | $$  | $$         | $$   \$$| $$     | $$  | $$| $$___\$$| $$__    | $$'}; ...
                {'| $$  | $$| $$  | $$      | $$$$\ $$| $$  | $$  | $$         | $$      | $$     | $$  | $$ \$$    \ | $$  \   | $$'}; ...
                {'| $$  | $$| $$  | $$      | $$\$$ $$| $$  | $$  | $$         | $$   __ | $$     | $$  | $$ _\$$$$$$\| $$$$$    \$$'}; ...
                {'| $$__/ $$| $$__/ $$      | $$ \$$$$| $$__/ $$  | $$         | $$__/  \| $$_____| $$__/ $$|  \__| $$| $$_____  __ '}; ...
                {'| $$    $$ \$$    $$      | $$  \$$$ \$$    $$  | $$          \$$    $$| $$     \\$$    $$ \$$    $$| $$     \|  \'}; ...
                {' \$$$$$$$   \$$$$$$        \$$   \$$  \$$$$$$    \$$           \$$$$$$  \$$$$$$$$ \$$$$$$   \$$$$$$  \$$$$$$$$ \$$'}];
            
            for i = 1:length(s)
                fprintf('%s\n',s{i})
            end

        end
    end
end