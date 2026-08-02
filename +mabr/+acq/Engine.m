classdef Engine < handle
% mabr.acq.Engine  Client-side controller for the acquisition worker.
%
%   The Engine runs in the GUI process. It keeps a warm 1-process parallel
%   pool, launches mabr.acq.worker_loop once via parfeval, and owns the
%   read-only view of the shared ring buffer. Control and state flow over
%   parallel queues; recorded samples flow through the memmap ring buffer.
%
%   This replaces the entire legacy machinery: abr.Runtime, launch_bg_process
%   (system('matlab.exe ...')), the Wmic PID liveness checks, info.mat, the
%   dac.wav handoff, and the mabr_com.dat command/state memmap. Crucially, it
%   removes every "while ... pause(0.01)" busy-wait: worker messages arrive on
%   a DataQueue and are dispatched by an afterEach callback, so the Engine is
%   event-driven.
%
%   Events (listen to drive a UI):
%       StateChanged   - notified with mabr.acq.StateEventData (.State)
%       BlockCompleted - the current block finished (or was stopped)
%       WorkerError    - the worker reported an error (.Identifier/.Message)
%
%   The worker is named by its Role in every message it appears in --
%   "acquisition worker" while it is recording, "stimulus worker" while it is
%   only playing out (mabr.AudioSettings.StimulationOnly). The label follows
%   what the run actually does; it changes nothing about how the worker runs.
%
%   Typical use:
%       eng = mabr.acq.Engine(cfg,testing);
%       eng.waitUntilReady();          % one-time worker handshake
%       eng.prep(blockSpec);           % arm a block
%       eng.run();                     % start streaming
%       ... eng.pause()/eng.resume()/eng.stop() ...
%       eng.kill();                    % tear down the worker
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Config
        Testing   (1,1) logical = false
        State     (1,1) mabr.acq.State = mabr.acq.State.Idle
        WorkerPID (1,1) double = -1
        RingBuffer               % read-only mabr.acq.RingBuffer

        % What this worker is currently DOING, for every message that names it:
        % 'acquisition' (playback + recording) or 'stimulus' (playback only --
        % mabr.AudioSettings.StimulationOnly, where nothing is recorded and
        % calling it an acquisition worker is simply untrue). Purely a label:
        % it changes no behaviour, and the mode itself rides per block in the
        % render spec (see mabr.stim.Schedule.StimulationOnly). Set at
        % construction and re-set by mabr.ui.AcqController.start, since one
        % controller -- and therefore one worker -- is reused across runs that
        % may switch modes between them.
        Role      (1,:) char = 'acquisition'

        % What the worker reported about the last block it streamed:
        %   .samples  play-matrix samples actually emitted
        %   .reason   'completed' | 'stopped' | 'killed'
        % Cleared at each prep. In stimulation-only mode nothing comes back
        % through the ring buffer, so this is the only record of how far
        % through a run that was stopped early the presentation actually got
        % (see mabr.ui.AcqController's stimulation log).
        LastStream (1,1) struct = struct('samples',0,'reason','')
    end

    properties (Dependent)
        WorkerName   % 'acquisition worker' / 'stimulus worker'
    end

    properties (Access = private)
        Pool
        Future
        ResultQueue              % DataQueue  (worker -> client)
        CmdQueue                 % PollableDataQueue (client -> worker)
        MsgListener
        Progress = @(~) []       % startup progress sink, fcn(char)
    end

    events
        StateChanged
        BlockCompleted
        WorkerError
    end

    methods
        function obj = Engine(cfg,testing,progressFcn,role)
            % progressFcn (optional) is called with a char status message at
            % each startup milestone so a UI can show what is happening while
            % the pool spins up (that can take tens of seconds).
            % role (optional) labels the worker in those messages and in the
            % log -- see the Role property and setRole.
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            if nargin < 2 || isempty(testing), testing = false; end
            if nargin >= 3 && ~isempty(progressFcn), obj.Progress = progressFcn; end
            if nargin >= 4 && ~isempty(role), obj.Role = mabr.acq.Engine.checkRole(role); end
            obj.Config  = cfg;
            obj.Testing = logical(testing);

            % Read-only view of the ring buffer (also creates the backing
            % files if this is a fresh checkout).
            obj.report('Mapping ring buffer…');
            obj.RingBuffer = mabr.acq.RingBuffer(cfg,false);

            % Warm pool + async worker.
            obj.Pool = mabr.acq.Engine.ensure_pool(obj.Progress);
            obj.report('Parallel pool ready (%d worker(s)).',obj.Pool.NumWorkers);
            % Ensure the +mabr namespace resolves on the worker BEFORE the cfg
            % argument is deserialized (defends against a reused pool that
            % predates the MABR path; a fresh pool already has it via
            % AutoAddClientPath). Adding the repo root suffices for packages.
            try
                pctRunOnAll(['addpath(''' mabr.Config.root ''')']);
            catch me
                mabr.log.vprintf(2,'pctRunOnAll addpath skipped: %s',me.message);
            end
            obj.ResultQueue = parallel.pool.DataQueue;
            obj.MsgListener = afterEach(obj.ResultQueue,@(m) obj.on_worker_message(m));

            obj.report('Launching %s…',obj.WorkerName);
            mabr.log.vprintf(1,'Launching %s (testing = %d)',obj.WorkerName,obj.Testing);
            obj.Future = parfeval(obj.Pool,@mabr.acq.worker_loop,0, ...
                mabr.Config.root,obj.ResultQueue,obj.Testing);
        end

        function delete(obj)
            try, obj.kill(); end %#ok<TRYNC>
            try, delete(obj.MsgListener); end %#ok<TRYNC>
            try, cancel(obj.Future); end %#ok<TRYNC>
        end

        function n = get.WorkerName(obj)
            n = [obj.Role ' worker'];
        end

        function setRole(obj,role)
            % Re-label a worker that is already running. The same process
            % streams whatever the next spec asks of it, so switching between
            % recording and stimulation only does not (and must not) restart
            % it -- but every message about it from here on should say which
            % of the two it is doing. Logged on change, since "the worker" in
            % a log is otherwise silently two different things.
            role = mabr.acq.Engine.checkRole(role);
            if strcmp(role,obj.Role), return; end
            obj.Role = role;
            mabr.log.vprintf(1,'Worker re-labelled: %s (PID %d)',obj.WorkerName,obj.WorkerPID);
        end

        % --- Lifecycle ------------------------------------------------------
        function tf = waitUntilReady(obj,timeout)
            % Block (bounded) until the worker handshake arrives. This is a
            % one-time startup wait, not a per-frame poll.
            if nargin < 2 || isempty(timeout), timeout = 120; end
            t0 = tic; lastReport = -Inf;
            while isempty(obj.CmdQueue) && toc(t0) < timeout
                if ~isempty(obj.Future) && strcmp(obj.Future.State,'finished') ...
                        && ~isempty(obj.Future.Error)
                    error('mabr:acq:Engine:workerFailed', ...
                        'Worker failed to start: %s',obj.Future.Error.message);
                end
                if toc(t0) - lastReport >= 1
                    lastReport = toc(t0);
                    obj.report('Waiting for the %s handshake… (%.0f s of %.0f)', ...
                        obj.WorkerName,lastReport,timeout);
                end
                pause(0.05);   % lets the afterEach handshake callback run
            end
            tf = ~isempty(obj.CmdQueue);
            if tf
                obj.report('%s ready (PID %d).', ...
                    mabr.acq.Engine.capitalize(obj.WorkerName),obj.WorkerPID);
            end
            if ~tf
                error('mabr:acq:Engine:handshakeTimeout', ...
                    'Timed out waiting for the %s handshake.',obj.WorkerName);
            end
        end

        function tf = isReady(obj)
            tf = ~isempty(obj.CmdQueue);
        end

        % --- Commands to the worker ----------------------------------------
        function prep(obj,blockSpec)
            % Arm the worker with a pre-rendered block (2-channel play matrix
            % + parameters). See mabr.acq.worker_loop for the payload shape.
            % The previous block's stream report belongs to the previous block:
            % clear it here so nothing downstream can mistake a stale count for
            % this block's.
            obj.LastStream = struct('samples',0,'reason','');
            obj.send_cmd(mabr.acq.Cmd.Prep,blockSpec);
        end

        function run(obj),    obj.send_cmd(mabr.acq.Cmd.Run);    end
        function pause(obj),  obj.send_cmd(mabr.acq.Cmd.Pause);  end
        function resume(obj), obj.send_cmd(mabr.acq.Cmd.Resume); end
        function stop(obj),   obj.send_cmd(mabr.acq.Cmd.Stop);   end

        function releaseDevice(obj)
            % Ask the worker to close the audio device, keeping it (and the
            % warm pool) alive. The worker holds its audioPlayerRecorder from
            % the first prep until kill, so anything else needing the ASIO
            % device -- mabr.stim.CalibrationAdapter -- has to ask for it back
            % first. The next prep reopens it. Safe to call when no worker is
            % running, since that is already the state it asks for.
            if isempty(obj.CmdQueue), return; end
            try, obj.send_cmd(mabr.acq.Cmd.Release); end %#ok<TRYNC>
        end

        function kill(obj)
            if ~isempty(obj.CmdQueue)
                try, obj.send_cmd(mabr.acq.Cmd.Kill); end %#ok<TRYNC>
            end
        end

        % --- Live view access ----------------------------------------------
        function h = head(obj), h = obj.RingBuffer.WriteHead; end
    end

    methods (Access = private)
        function report(obj,fmt,varargin)
            % Push a startup status message to the UI sink (never fatal).
            try
                obj.Progress(sprintf(fmt,varargin{:}));
            catch me
                mabr.log.vprintf(2,'Progress callback failed: %s',me.message);
            end
        end

        function send_cmd(obj,cmd,data)
            if nargin < 3, data = []; end
            assert(~isempty(obj.CmdQueue),'mabr:acq:Engine:notReady', ...
                'Worker is not ready; call waitUntilReady() first.');
            send(obj.CmdQueue,struct('cmd',cmd,'data',data));
        end

        function on_worker_message(obj,msg)
            % afterEach dispatcher for worker -> client messages.
            switch msg.type
                case 'handshake'
                    obj.CmdQueue  = msg.cmdQueue;
                    obj.WorkerPID = msg.pid;
                    obj.elevate_priority();
                    mabr.log.vprintf(1,'Worker handshake received (PID %d)',obj.WorkerPID);

                case 'streamed'
                    % Always arrives before the Completed state that raises
                    % BlockCompleted, so a listener on that event can read it.
                    obj.LastStream = struct('samples',double(msg.samples), ...
                                            'reason',char(msg.reason));

                case 'state'
                    prev = obj.State;
                    obj.State = msg.state;
                    notify(obj,'StateChanged',mabr.acq.StateEventData(msg.state));
                    if msg.state == mabr.acq.State.Completed && prev ~= mabr.acq.State.Completed
                        notify(obj,'BlockCompleted');
                    end

                case 'error'
                    mabr.log.vprintf(0,1,'Worker error [%s]: %s',msg.identifier,msg.message);
                    obj.State = mabr.acq.State.Error;
                    notify(obj,'WorkerError',mabr.acq.StateEventData( ...
                        mabr.acq.State.Error,msg.identifier,msg.message));
            end
        end

        function elevate_priority(obj)
            % Raise the worker process priority (reuses the legacy wmic call).
            if obj.WorkerPID <= 0 || ~ispc, return; end
            try
                mabr.acq.Engine.set_priority(obj.WorkerPID,'high priority');
            catch me
                mabr.log.vprintf(1,1,'Could not elevate worker priority: %s',me.message);
            end
        end
    end

    methods (Static)
        function role = checkRole(role)
            % Only the two the worker can actually be doing. A typo here would
            % otherwise reach the log and a status line as though it meant
            % something.
            role = lower(char(role));
            assert(ismember(role,{'acquisition','stimulus'}), ...
                'mabr:acq:Engine:badRole', ...
                'Worker role must be ''acquisition'' or ''stimulus'' (got "%s").',role);
        end

        function s = capitalize(s)
            if ~isempty(s), s(1) = upper(s(1)); end
        end

        function pool = ensure_pool(progressFcn)
            % Reuse an existing 1-process pool or create one.
            if nargin < 1 || isempty(progressFcn), progressFcn = @(~) []; end
            progressFcn('Checking for a parallel pool…');
            pool = gcp('nocreate');
            if ~isempty(pool)
                if pool.NumWorkers >= 1
                    progressFcn('Reusing the existing parallel pool.');
                    return
                end
                delete(pool);
            end
            progressFcn('Starting parallel pool (first launch can take ~30–60 s)…');
            try
                pool = parpool('Processes',1);
            catch
                pool = parpool('local',1);   % older release fallback
            end
        end

        function set_priority(pid,level)
            % Ported from abr.Tools.set_priority.
            numLevels = 2.^([5:8 14 15]);
            txtLevels = {'normal','idle','high priority','real time','below normal','above normal'};
            ind = ismember(txtLevels,lower(level));
            assert(any(ind),'mabr:acq:Engine:badPriority','Invalid priority level: %s',level);
            [e,w] = dos(sprintf('wmic process where processid=''%d'' CALL setpriority %d', ...
                pid,numLevels(ind)));
            if e ~= 0
                mabr.log.vprintf(0,1,'Failed to set priority of PID %d to "%s"',pid,level);
                disp(w);
            end
        end
    end
end
