classdef ComputeEngine < handle
% mabr.compute.ComputeEngine  Client-side facade for the compute workers.
%
%   Runs in the GUI process and owns everything about the two optional
%   workers mabr.compute.compute_loop provides -- the DSP worker, launched
%   with this object, and the metrics worker, launched lazily by the first
%   analysis window (ensureMetrics) -- the way mabr.acq.Engine owns the
%   acquisition worker: their parfeval futures, their result DataQueues and
%   afterEach dispatchers, the writable mabr.compute.RequestBuffer, and
%   read-only views of what they publish (mabr.compute.LiveBuffer,
%   MetricBuffer). No busy-waits: worker messages arrive as events, and the
%   published data is read when a consumer asks for it.
%
%       ce = mabr.compute.ComputeEngine(cfg,progressFcn);
%       ce.waitUntilReady();                 % DSP handshake, never throws
%       ce.configure(fs,window,filters,artifacts);
%       ce.runStart(info); ...; [stats,fresh] = ce.live(); ...; ce.runEnd(id);
%       slot = ce.acquireSlot(); ce.setJob(slot,metricIdx,window); V = ce.values(slot);
%
%   DEGRADATION IS PER ROLE. hasDSP() and hasMetrics() say whether each
%   worker is up, and every consumer checks before it asks: a controller
%   whose DSP worker is absent steps its own pipeline, an analysis window
%   whose metrics worker is absent evaluates in-process. Absent means never
%   launched, not yet handshaken, or declared dead by the watchdog -- never
%   merely slow. Stale is not absent: a consumer that finds no new publish
%   keeps its last values, because computing in-process the moment a worker
%   is slow would reproduce the overload the workers exist to remove, at
%   exactly the moment the machine is struggling.
%
%   THE WATCHDOG rides the consumers' own polls; there is no timer here. A
%   worker publishes on every cycle (a heartbeat, even with nothing to say),
%   so a Seq that has not moved for far longer than its period while it
%   should be cycling means it is wedged. A wedged worker is cancelled and
%   relaunched ONCE; cancel() interrupts MATLAB code, but a hang inside a
%   builtin or a MEX may not answer it, so if the fresh handshake never
%   arrives the role is marked dead for the session and the status line
%   says so. The pool is never deleted or recreated here -- that would kill
%   the acquisition worker.
%
%   What a late-launched or relaunched worker missed is replayed to it at
%   its handshake: the last Configure, the run in progress, the custom
%   metrics, and (metrics) every condition finalized so far.
%
%   Events:
%       Finalized   the DSP worker finished a Finalize (MessageEventData.Data
%                   = the reply: runId, result, error)
%       WorkerError a worker reported an error
%       RosterChanged the metrics worker's condition roster changed
%
%   See also mabr.compute.compute_loop, mabr.compute.Pipeline,
%   mabr.ui.AcqController, mabr.ui.MetricPlot.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Config
        Pool
        Live            % mabr.compute.LiveBuffer (read-only)
        Metric          % mabr.compute.MetricBuffer (read-only)
        Requests        % mabr.compute.RequestBuffer (writable)
        DSP             % worker record (see newWorker)
        Metrics         % worker record
        Roster = struct('Id',0,'Keys',{{}},'Params',{{}})
        Slots           % logical [1 x MaxJobs]: taken
        Jobs            % [MaxJobs x 4]: Active MetricIdx WinLo WinHi (ms)
        % Slots whose custom metric was running when the metrics worker
        % stalled. Every custom metric is suspect then -- there is no telling
        % which one hung -- so they are all dropped from the relaunched
        % worker and their slots flagged, and a window whose slot is flagged
        % must NOT evaluate that function in-process instead: a hang here
        % is the one outcome the third worker exists to prevent. Cleared by
        % the next setJob for the slot (the user picked another metric).
        StalledSlots    % logical [1 x MaxJobs]
        SlotPeriods     % [1 x MaxJobs] each window's refresh interval (s)
        LivePeriod   (1,1) double = 0.05
        MetricPeriod (1,1) double = 1
        CurrentRunId (1,1) double = 0
        InRun        (1,1) logical = false
    end

    properties (Access = private)
        Progress = @(~) []
        LastConfigure = []      % replayed to a worker at its handshake
        LastRunStart  = []
        CustomFcns    = {}
        Conditions    = {}      % every AddCondition so far (metrics replay)
        % The last live Seq a consumer took, so live() can say "unchanged"
        % without reading, and the time it last changed (the watchdog).
        LiveSeq   (1,1) double = -1
        MetricSeq (1,1) double = -1
    end

    events
        Finalized
        WorkerError
        RosterChanged
    end

    methods
        function obj = ComputeEngine(cfg,progressFcn)
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            if nargin >= 2 && ~isempty(progressFcn), obj.Progress = progressFcn; end
            obj.Config = cfg;

            obj.Pool = gcp('nocreate');
            assert(~isempty(obj.Pool) && obj.Pool.NumWorkers >= 2, ...
                'mabr:compute:ComputeEngine:poolTooSmall', ...
                ['The compute workers need a parallel pool with at least two ' ...
                 'workers (one is the acquisition worker''s); see mabr.pool.']);

            % The client creates the files (so the sizes are right before
            % any worker maps them) and holds the request buffer's pen.
            obj.report('Mapping compute buffers…');
            obj.Requests = mabr.compute.RequestBuffer(cfg,true);
            obj.Live     = mabr.compute.LiveBuffer(cfg,false);
            obj.Metric   = mabr.compute.MetricBuffer(cfg,false);
            obj.Slots        = false(1,cfg.MaxComputeJobs);
            obj.Jobs         = zeros(cfg.MaxComputeJobs,4);
            obj.StalledSlots = false(1,cfg.MaxComputeJobs);
            obj.SlotPeriods  = ones(1,cfg.MaxComputeJobs);
            obj.CustomFcns   = cell(1,cfg.MaxComputeJobs);
            obj.Requests.zero();
            obj.writeRequests();

            obj.DSP     = mabr.compute.ComputeEngine.newWorker('dsp');
            obj.Metrics = mabr.compute.ComputeEngine.newWorker('metrics');
            obj.launch('dsp');
        end

        function delete(obj)
            obj.kill();
            for role = {'dsp','metrics'}
                w = obj.(obj.field(role{1}));
                % Let a loop that heard Kill exit on its own, so the pool's
                % slot is free when this returns (see mabr.acq.Engine.delete).
                try, wait(w.Future,'finished',5); end %#ok<TRYNC>
                try, delete(w.Listener); end %#ok<TRYNC>
                try, cancel(w.Future);   end %#ok<TRYNC>
            end
        end

        % --- Lifecycle ------------------------------------------------------
        function tf = waitUntilReady(obj,timeout)
            % Bounded wait for the DSP handshake. Never throws: a compute
            % worker that fails to come up costs its acceleration, not the
            % session, so the answer is a logical and the caller carries on.
            if nargin < 2 || isempty(timeout), timeout = 60; end
            t0 = tic; lastReport = -Inf;
            while ~obj.DSP.Ready && ~obj.DSP.Dead && toc(t0) < timeout
                if obj.future_failed(obj.DSP)
                    obj.markDead('dsp','the worker failed to start');
                    break
                end
                if toc(t0) - lastReport >= 1
                    lastReport = toc(t0);
                    obj.report('Waiting for the DSP worker handshake… (%.0f s of %.0f)', ...
                        lastReport,timeout);
                end
                pause(0.05);
            end
            tf = obj.hasDSP();
            if tf
                obj.report('DSP worker ready (PID %d).',obj.DSP.PID);
            elseif ~obj.DSP.Dead
                mabr.log.vprintf(1,1,'DSP worker handshake timed out; computing in-process.');
            end
        end

        function tf = hasDSP(obj)
            tf = obj.DSP.Ready && ~obj.DSP.Dead;
        end

        function tf = hasMetrics(obj)
            tf = obj.Metrics.Ready && ~obj.Metrics.Dead;
        end

        function tf = canHaveMetrics(obj)
            % Whether a metrics worker could run at all: a third pool slot,
            % and not already given up on.
            tf = ~obj.Metrics.Dead && ~isempty(obj.Pool) && obj.Pool.NumWorkers >= 3;
        end

        function ensureMetrics(obj)
            % Launch the metrics worker if it is not running. Lazy: a session
            % that never opens an analysis window never pays for it. Returns
            % at once; the handshake arrives as a message.
            if ~isempty(obj.Metrics.Future) || obj.Metrics.Dead, return; end
            if ~obj.canHaveMetrics()
                mabr.log.vprintf(1,'No pool slot for a metrics worker; analysis runs in-process.');
                return
            end
            obj.launch('metrics');
        end

        function kill(obj)
            for role = {'dsp','metrics'}
                obj.sendTo(role{1},mabr.compute.Cmd.Kill,[]);
            end
        end

        % --- Configuration and run state ------------------------------------
        function configure(obj,dacSampleRate,window,filters,artifacts)
            % Broadcast the rate, window and policies. Re-sent on every
            % policy change, so every process agrees about what a sweep is.
            obj.LastConfigure = struct('DACSampleRate',dacSampleRate, ...
                'Window',double(window(:)'),'Filters',filters.toStruct(), ...
                'Artifacts',artifacts.toStruct());
            obj.broadcast(mabr.compute.Cmd.Configure,obj.LastConfigure);
        end

        function runStart(obj,info)
            % info: RunId, StimIndex, Stimuli, Labels, Meta (see
            % mabr.compute.Pipeline.beginRun). The watchdog clock restarts
            % here, so the first publish has the whole window to arrive in.
            obj.CurrentRunId = info.RunId;
            obj.InRun        = true;
            obj.LastRunStart = info;
            obj.DSP.LastChange     = tic;
            obj.Metrics.LastChange = tic;
            obj.broadcast(mabr.compute.Cmd.RunStart,info);
        end

        function runEnd(obj,runId)
            if nargin < 2, runId = obj.CurrentRunId; end
            obj.InRun        = false;
            obj.LastRunStart = [];
            obj.broadcast(mabr.compute.Cmd.RunEnd,struct('RunId',runId));
        end

        function tf = finalize(obj,runId,seq)
            % Ask the DSP worker to finalize the run just ended. The reply
            % arrives as the Finalized event; false means there is no DSP
            % worker to ask and the caller should finalize itself.
            tf = obj.hasDSP();
            if ~tf, return; end
            obj.DSP.LastChange = tic;
            obj.sendTo('dsp',mabr.compute.Cmd.Finalize, ...
                struct('RunId',runId,'StimIndex',double(seq(:)')));
        end

        % --- The metrics worker's table -------------------------------------
        function addCondition(obj,c)
            obj.Conditions{end+1} = c;
            obj.sendTo('metrics',mabr.compute.Cmd.AddCondition,c);
        end

        function clearConditions(obj)
            obj.Conditions = {};
            obj.sendTo('metrics',mabr.compute.Cmd.ClearConditions,[]);
        end

        % --- What consumers read --------------------------------------------
        function [stats,changed] = live(obj)
            % The DSP worker's latest publish for the run in progress, or []
            % -- and whether it is new since the last call, so a 20 Hz tick
            % with nothing new does nothing. A publish for another run (the
            % previous one, before the worker caught up) is not returned.
            stats = []; changed = false;
            obj.watchRelaunch('dsp');
            if ~obj.hasDSP(), return; end
            s = obj.Live.seq();
            if s == obj.LiveSeq
                % Nothing new -- the only moment silence is judged. The
                % order matters: a run's preparation can take seconds
                % between runStart (which restarts the clock) and the first
                % tick, and the worker has been heartbeating throughout;
                % judging before reading would call that a stall.
                obj.watchSilence('dsp',max(5,20*obj.LivePeriod));
                return
            end
            [P,sq] = obj.Live.read();
            if isempty(P), return; end       % torn: next poll
            obj.LiveSeq        = sq;
            obj.DSP.LastChange = tic;
            changed = true;
            if P.RunId ~= obj.CurrentRunId, return; end
            stats = P;
        end

        function V = values(obj,slot)
            % The metrics worker's latest values for one slot: .Values
            % [1 x nConds], and row-aligned with them .Keys, .Params,
            % .NumSweeps and .Live (the roster those columns are); .RosterId;
            % .Current, whether they answer the request table as it stands
            % now (a metric just changed is answered a cycle later, and the
            % old metric's numbers must not be drawn under the new one's
            % name); .Incomplete, whether a time budget cut this slot short;
            % .Age, seconds since the worker last published. [] with no
            % metrics worker, nothing published yet, or a publish whose
            % roster has not arrived yet.
            V = [];
            obj.watchRelaunch('metrics');
            if ~obj.hasMetrics(), return; end
            s = obj.Metric.seq();
            if s ~= obj.MetricSeq
                obj.MetricSeq = s;
                obj.Metrics.LastChange = tic;
            else
                obj.watchSilence('metrics',max(10,5*obj.MetricPeriod));
                if ~obj.hasMetrics(), return; end
            end
            [P,~] = obj.Metric.read();
            if isempty(P) || P.RosterId ~= obj.Roster.Id, return; end
            if slot < 1 || slot > size(P.Values,1), return; end
            nC = numel(obj.Roster.Keys);
            if numel(P.NumSweeps) ~= nC, return; end     % roster moved under it
            V = struct('Values',P.Values(slot,:),'Keys',{obj.Roster.Keys}, ...
                'Params',{obj.Roster.Params},'NumSweeps',P.NumSweeps, ...
                'Live',P.Live,'RosterId',P.RosterId, ...
                'Current',P.ReqSeq == obj.Requests.seq(), ...
                'Incomplete',bitand(uint32(P.Incomplete),uint32(2^(slot-1))) > 0, ...
                'Age',toc(obj.Metrics.LastChange));
        end

        function reportStall(obj,role,why)
            % A consumer's own evidence that a worker is wedged -- the
            % controller's finalization timeout -- handled exactly as the
            % watchdog's: one relaunch, then written off.
            obj.stall(role,why);
        end

        function tf = isStalled(obj,slot)
            tf = ~isempty(slot) && slot >= 1 && slot <= numel(obj.StalledSlots) ...
                && obj.StalledSlots(slot);
        end

        % --- Job slots (one per analysis window) ----------------------------
        function slot = acquireSlot(obj)
            % A slot for one analysis window, or [] when all are taken --
            % the window then evaluates in-process, and nothing else changes.
            slot = find(~obj.Slots,1);
            if isempty(slot), return; end
            obj.Slots(slot)  = true;
            obj.Jobs(slot,:) = 0;
            obj.ensureMetrics();
        end

        function releaseSlot(obj,slot)
            if isempty(slot) || slot < 1 || slot > numel(obj.Slots), return; end
            obj.Slots(slot)        = false;
            obj.Jobs(slot,:)       = 0;
            obj.CustomFcns{slot}   = [];
            obj.StalledSlots(slot) = false;
            obj.SlotPeriods(slot)  = 1;
            obj.writeRequests();
        end

        function setJob(obj,slot,metricIdx,window)
            % metricIdx: index into mabr.metrics.online.catalog, or
            % RequestBuffer.Custom after setCustomMetric. window [t0 t1] ms.
            % Picking a metric for a stalled slot is what clears the stall.
            if isempty(slot), return; end
            if nargin < 4 || isempty(window) || numel(window) ~= 2, window = [0 0]; end
            obj.Jobs(slot,:)       = [1 metricIdx double(window(:)')];
            obj.StalledSlots(slot) = false;
            obj.writeRequests();
        end

        function setSlotPeriod(obj,slot,period)
            % Each window refreshes on its own clock; the worker cycles at
            % the fastest of them.
            if isempty(slot) || ~isfinite(period) || period <= 0, return; end
            obj.SlotPeriods(slot) = period;
            obj.MetricPeriod = min(obj.SlotPeriods(obj.Slots));
            obj.writeRequests();
        end

        function setCustomMetric(obj,slot,fcn)
            if isempty(slot), return; end
            obj.CustomFcns{slot} = fcn;
            obj.sendTo('metrics',mabr.compute.Cmd.SetCustomMetric, ...
                struct('Slot',slot,'Fcn',fcn));
        end

        function setPeriods(obj,livePeriod,metricPeriod)
            if nargin >= 2 && ~isempty(livePeriod),   obj.LivePeriod   = livePeriod;   end
            if nargin >= 3 && ~isempty(metricPeriod), obj.MetricPeriod = metricPeriod; end
            obj.writeRequests();
        end
    end

    % =====================================================================
    methods (Access = private)
        function launch(obj,role)
            f = obj.field(role);
            w = obj.(f);
            w.Queue    = parallel.pool.DataQueue;
            w.Listener = afterEach(w.Queue,@(m) obj.onMessage(role,m));
            w.Ready    = false;
            w.CmdQueue = [];
            w.LastChange = tic;
            obj.report('Launching %s worker…',role);
            mabr.log.vprintf(1,'Launching compute worker (%s)',role);
            w.Future = parfeval(obj.Pool,@mabr.compute.compute_loop,0, ...
                mabr.Config.root,w.Queue,role);
            obj.(f) = w;
        end

        function onMessage(obj,role,msg)
            f = obj.field(role);
            switch msg.type
                case 'handshake'
                    obj.(f).CmdQueue = msg.cmdQueue;
                    obj.(f).PID      = msg.pid;
                    obj.(f).Ready    = true;
                    obj.(f).LastChange = tic;
                    mabr.log.vprintf(1,'Compute worker handshake (%s, PID %d)',role,msg.pid);
                    % Below the acquisition worker, always: this is a
                    % real-time audio rig, and these are the processes that
                    % must lose when the CPU is short. The one running user
                    % code sits lowest of all.
                    if strcmp(role,'dsp'), level = 'below normal'; else, level = 'idle'; end
                    try
                        mabr.acq.Engine.set_priority(msg.pid,level);
                    catch me
                        mabr.log.vprintf(1,1,'Could not set %s worker priority: %s',role,me.message);
                    end
                    obj.replay(role);

                case 'state'
                    obj.(f).State = msg.state;

                case 'roster'
                    params = {};
                    if isfield(msg,'params'), params = msg.params; end
                    obj.Roster = struct('Id',double(msg.id),'Keys',{msg.keys}, ...
                                        'Params',{params});
                    notify(obj,'RosterChanged', ...
                        mabr.compute.MessageEventData(role,'roster',obj.Roster));

                case 'finalized'
                    obj.DSP.LastChange = tic;
                    notify(obj,'Finalized', ...
                        mabr.compute.MessageEventData(role,'finalized',msg));

                case 'error'
                    mabr.log.vprintf(0,1,'Compute worker (%s) error [%s]: %s', ...
                        role,msg.identifier,msg.message);
                    obj.(f).State = mabr.compute.State.Error;
                    notify(obj,'WorkerError', ...
                        mabr.compute.MessageEventData(role,'error',msg));
            end
        end

        function replay(obj,role)
            % Everything a worker that has just (re)started needs to know.
            if ~isempty(obj.LastConfigure)
                obj.sendTo(role,mabr.compute.Cmd.Configure,obj.LastConfigure);
            end
            if strcmp(role,'metrics')
                for i = 1:numel(obj.Conditions)
                    obj.sendTo(role,mabr.compute.Cmd.AddCondition,obj.Conditions{i});
                end
                for s = find(~cellfun(@isempty,obj.CustomFcns))
                    obj.sendTo(role,mabr.compute.Cmd.SetCustomMetric, ...
                        struct('Slot',s,'Fcn',obj.CustomFcns{s}));
                end
            end
            if obj.InRun && ~isempty(obj.LastRunStart)
                obj.sendTo(role,mabr.compute.Cmd.RunStart,obj.LastRunStart);
            end
        end

        function watchRelaunch(obj,role)
            % After a relaunch, did the fresh handshake ever arrive? cancel()
            % interrupts MATLAB code, but a hang inside a builtin or a MEX
            % may not answer it, and then the relaunched loop is queued
            % behind a worker that never frees.
            f = obj.field(role);
            w = obj.(f);
            if w.Dead || isempty(w.Future) || w.Ready, return; end
            if w.Relaunched && toc(w.LastChange) > 60
                obj.markDead(role,'the relaunched worker never handshook');
            end
        end

        function watchSilence(obj,role,limit)
            % Called from a consumer's poll that found nothing new: has the
            % worker been silent for longer than it possibly could be while
            % cycling? It publishes every cycle, sweeps or none, so silence
            % is the one thing a wedged worker and a live one do not share.
            f = obj.field(role);
            w = obj.(f);
            if w.Dead || ~w.Ready, return; end
            cycling = strcmp(role,'metrics') || obj.InRun;
            if ~cycling, return; end
            if toc(w.LastChange) < limit, return; end
            obj.stall(role,sprintf('no publish for %.1f s',toc(w.LastChange)));
        end

        function stall(obj,role,why)
            f = obj.field(role);
            if obj.(f).Relaunched
                obj.markDead(role,[why ' after a relaunch']);
                return
            end
            mabr.log.vprintf(0,1,'Compute worker (%s) stalled (%s); relaunching once.',role,why);
            if strcmp(role,'metrics')
                % Whichever custom metric hung, none of them comes back:
                % flag their slots (their windows show a note and evaluate
                % nothing) and take them out of the job table before the
                % relaunched worker reads it.
                suspect = ~cellfun(@isempty,obj.CustomFcns);
                obj.StalledSlots(suspect) = true;
                obj.Jobs(suspect,1) = 0;
                obj.CustomFcns = cell(1,numel(obj.CustomFcns));
                obj.writeRequests();
                if any(suspect)
                    obj.report('A custom metric hung the analysis worker; it has been dropped.');
                end
            end
            obj.(f).Relaunched = true;
            obj.(f).Ready      = false;
            try, cancel(obj.(f).Future); end %#ok<TRYNC>
            try, delete(obj.(f).Listener); end %#ok<TRYNC>
            obj.launch(role);
        end

        function markDead(obj,role,why)
            f = obj.field(role);
            obj.(f).Dead  = true;
            obj.(f).Ready = false;
            mabr.log.vprintf(0,1,['Compute worker (%s) is unavailable for the rest of ' ...
                'the session (%s); computing in-process.'],role,why);
            obj.report('%s worker unavailable — computing in-process.', ...
                mabr.acq.Engine.capitalize(role));
        end

        function broadcast(obj,cmd,data)
            obj.sendTo('dsp',cmd,data);
            obj.sendTo('metrics',cmd,data);
        end

        function sendTo(obj,role,cmd,data)
            w = obj.(obj.field(role));
            if ~w.Ready || w.Dead || isempty(w.CmdQueue), return; end
            try
                send(w.CmdQueue,struct('cmd',cmd,'data',data));
            catch me
                mabr.log.vprintf(1,1,'Could not send %s to the %s worker: %s', ...
                    char(cmd),role,me.message);
            end
        end

        function writeRequests(obj)
            obj.Requests.publish(struct('LivePeriod',obj.LivePeriod, ...
                'MetricPeriod',obj.MetricPeriod,'Jobs',obj.Jobs));
        end

        function report(obj,fmt,varargin)
            try
                obj.Progress(sprintf(fmt,varargin{:}));
            catch me
                mabr.log.vprintf(2,'Progress callback failed: %s',me.message);
            end
        end
    end

    methods (Static, Access = private)
        function w = newWorker(role)
            w = struct('Role',role,'Future',[],'Queue',[],'Listener',[], ...
                'CmdQueue',[],'PID',-1,'State',mabr.compute.State.Idle, ...
                'Ready',false,'Dead',false,'Relaunched',false, ...
                'LastChange',uint64(0));
        end

        function f = field(role)
            if strcmp(role,'dsp'), f = 'DSP'; else, f = 'Metrics'; end
        end

        function tf = future_failed(w)
            tf = ~isempty(w.Future) && strcmp(w.Future.State,'finished') ...
                && ~isempty(w.Future.Error);
        end
    end
end
