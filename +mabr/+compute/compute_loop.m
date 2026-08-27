function compute_loop(rootPath,resultQueue,role)
% mabr.compute.compute_loop  The compute worker's loop, run ON a parpool
% worker -- one function for both roles.
%
%   compute_loop(rootPath,resultQueue,role) is launched via parfeval by
%   mabr.compute.ComputeEngine with role 'dsp' or 'metrics', and runs until
%   Kill. It is shaped exactly like mabr.acq.worker_loop: a handshake that
%   hands back a PollableDataQueue for commands, state and error reports on
%   the result queue, and bulk data through memory-mapped files.
%
%     'dsp'      steps a mabr.compute.Pipeline over the acquisition ring
%                buffer every LivePeriod while a run is in progress and
%                publishes its statistics to mabr.compute.LiveBuffer; at the
%                end of a run it performs the finalization DSP on request
%                and replies with a 'finalized' message.
%     'metrics'  steps its OWN pipeline over the same ring every
%                MetricPeriod (the online metrics need the sweep matrix,
%                which the live surface deliberately does not carry), keeps
%                the session's condition table, evaluates the requested
%                metrics and publishes them to mabr.compute.MetricBuffer.
%                This is the process user-supplied metric functions run in,
%                so a hung one costs the analysis windows and nothing else.
%
%   Both read the client's mabr.compute.RequestBuffer (cadences, job table)
%   and the ring buffer read-only; neither talks to the other. Because both
%   derive from the same ring bytes under the same Configure, their sweeps
%   and verdicts agree by construction.
%
%   Message shapes:
%       client -> worker : struct('cmd',mabr.compute.Cmd,'data',payload)
%           Configure       DACSampleRate, Window, Filters (struct),
%                           Artifacts (struct)
%           RunStart        RunId, StimIndex, Stimuli, Labels, Meta
%           RunEnd          RunId
%           Finalize        RunId, StimIndex             (dsp)
%           AddCondition    a ConditionStore condition    (metrics)
%           ClearConditions -                             (metrics)
%           SetCustomMetric Slot, Fcn                     (metrics)
%           Kill            -
%       worker -> client : struct('type',...)
%           handshake  cmdQueue, pid, role
%           state      mabr.compute.State
%           error      identifier, message
%           roster     id, keys                           (metrics)
%           finalized  runId, result (Pipeline.finalize's F), error (dsp)
%
%   The sample rate is NOT optional: a compute worker needs it for the
%   decimation stride and the filter design, so the Config it builds comes
%   from Configure, and nothing is stepped before one arrives.
%
%   A worker publishes on every cycle of a run, sweeps or none, so a client
%   watchdog can tell "alive with nothing to say" from "hung" by the Seq
%   moving. The metrics worker cycles between runs too -- a metric can be
%   changed while nothing streams, and the finalized conditions are there to
%   evaluate it over.
%
% Daniel Stolzberg (c) 2026

if ~isempty(rootPath) && isfolder(rootPath)
    addpath(rootPath);
end
role  = lower(char(role));
isDSP = strcmp(role,'dsp');
assert(isDSP || strcmp(role,'metrics'),'mabr:compute:compute_loop:role', ...
    'role must be ''dsp'' or ''metrics'' (got "%s").',role);

cmdQueue = parallel.pool.PollableDataQueue;
send(resultQueue,struct('type','handshake','cmdQueue',cmdQueue, ...
    'pid',feature('getpid'),'role',role));

% Paths and buffer sizes only; the rate arrives with Configure.
cfg = mabr.Config;
req = mabr.compute.RequestBuffer(cfg,false);
if isDSP, out = mabr.compute.LiveBuffer(cfg,true);
else,     out = mabr.compute.MetricBuffer(cfg,true);
end
out.zero();
rb = mabr.acq.RingBuffer(cfg,false);

pipe       = [];                % mabr.compute.Pipeline, once configured
run        = [];                % the RunStart payload while a run streams
store      = mabr.compute.ConditionStore.empty();
custom     = cell(1,cfg.MaxComputeJobs);
catalog    = mabr.metrics.online.catalog();
rosterId   = 0;
rosterKeys = {};
periods    = [0.05 1];
jobs       = zeros(0,4);
reqSeq     = -1;
lastTic    = uint64(0);

send_state(resultQueue,mabr.compute.State.Idle);
mabr.log.vprintf(1,'Compute worker (%s) started',role);

try
    running = true;
    while running
        period = periods(1 + ~isDSP);
        if cycle_due(pipe,run,isDSP)
            wait = max(0,period - elapsed(lastTic));
        else
            wait = 0.1;
        end
        [msg,ok] = poll(cmdQueue,min(wait,0.1));
        if ok
            switch msg.cmd
                case mabr.compute.Cmd.Configure
                    d = msg.data;
                    if isempty(pipe) || pipe.Config.DACSampleRate ~= d.DACSampleRate
                        cfg  = mabr.Config(d.DACSampleRate);
                        pipe = mabr.compute.Pipeline(cfg);
                        if ~isempty(run), pipe.beginRun(run); end
                    end
                    pipe.configure(d.Window, ...
                        mabr.FilterPolicy.fromStruct(d.Filters), ...
                        mabr.ArtifactPolicy.fromStruct(d.Artifacts));
                    mabr.log.vprintf(2,'Compute worker (%s) configured: %g Hz, window [%g %g] s', ...
                        role,d.DACSampleRate,d.Window(1),d.Window(2));
                    if isempty(run), send_state(resultQueue,mabr.compute.State.Ready);
                    else,            send_state(resultQueue,mabr.compute.State.Working);
                    end

                case mabr.compute.Cmd.RunStart
                    run = msg.data;
                    if ~isempty(pipe), pipe.beginRun(run); end
                    lastTic = uint64(0);            % first cycle right away
                    mabr.log.vprintf(2,'Compute worker (%s) run %d started (%d presentations)', ...
                        role,run.RunId,numel(run.StimIndex));
                    send_state(resultQueue,mabr.compute.State.Working);

                case mabr.compute.Cmd.RunEnd
                    run = [];
                    if ~isempty(pipe), pipe.endRun(); end
                    mabr.log.vprintf(2,'Compute worker (%s) run ended',role);
                    send_state(resultQueue,mabr.compute.State.Ready);

                case mabr.compute.Cmd.Finalize
                    if isDSP
                        send_state(resultQueue,mabr.compute.State.Finalizing);
                        reply = struct('type','finalized','runId',msg.data.RunId, ...
                                       'result',[],'error','');
                        try
                            assert(~isempty(pipe),'mabr:compute:compute_loop:notConfigured', ...
                                'Finalize before Configure.');
                            reply.result = pipe.finalize(rb,msg.data.StimIndex);
                        catch me
                            reply.error = me.message;
                            mabr.log.vprintf(0,1,'Finalization failed on the worker: %s',me.message);
                        end
                        send(resultQueue,reply);
                        send_state(resultQueue,mabr.compute.State.Ready);
                    end

                case mabr.compute.Cmd.AddCondition
                    if ~isDSP
                        store = mabr.compute.ConditionStore.merge(store,msg.data);
                    end

                case mabr.compute.Cmd.ClearConditions
                    store = mabr.compute.ConditionStore.empty();

                case mabr.compute.Cmd.SetCustomMetric
                    d = msg.data;
                    if d.Slot >= 1 && d.Slot <= numel(custom)
                        custom{d.Slot} = d.Fcn;
                        mabr.log.vprintf(1,'Compute worker (%s): custom metric %s in slot %d', ...
                            role,func2str(d.Fcn),d.Slot);
                    end

                case mabr.compute.Cmd.Kill
                    running = false;
            end
            continue                        % drain commands before a cycle
        end

        % --- the client's requests: cadences and the job table -------------
        if req.seq() ~= reqSeq
            [R,rs] = req.read();
            if ~isempty(R)
                reqSeq = rs;
                if R.LivePeriod   > 0, periods(1) = R.LivePeriod;   end
                if R.MetricPeriod > 0, periods(2) = R.MetricPeriod; end
                jobs = R.Jobs;
            end
        end

        if ~cycle_due(pipe,run,isDSP) || elapsed(lastTic) < period, continue; end
        lastTic = tic;

        if isDSP
            stats = pipe.step(rb);
            if isempty(stats), stats = mabr.compute.Pipeline.emptyStats(run.RunId); end
            stats.ReqSeq = reqSeq;
            out.publish(stats);
        else
            [rosterId,rosterKeys] = metric_cycle(pipe,rb,run,store,jobs,custom, ...
                catalog,out,resultQueue,rosterId,rosterKeys,reqSeq,period,cfg);
        end
    end

catch me
    send_error(resultQueue,me.identifier,me.message);
    mabr.log.vprintf(0,1,me);
end

send_state(resultQueue,mabr.compute.State.Idle);
mabr.log.vprintf(1,'Compute worker (%s) exiting',role);
end


% =====================================================================
function [rosterId,rosterKeys] = metric_cycle(pipe,rb,run,store,jobs,custom, ...
    catalog,out,resultQueue,rosterId,rosterKeys,reqSeq,budget,cfg)
% One pass of the metrics worker: the run in progress as live conditions
% over the finalized table, then every requested metric over the result.
L = mabr.compute.ConditionStore.empty();
if ~isempty(run)
    pipe.step(rb);
    S = pipe.sweeps();
    if S.n > 0
        snap = struct('Sweeps',S.Y,'Time',S.t,'StimIndex',S.stimIdx,'Bad',S.bad, ...
            'Stimuli',run.Stimuli,'Labels',{getf(run,'Labels',{})}, ...
            'SampleRate',cfg.ADCSampleRate);
        L = mabr.compute.ConditionStore.fromLive(snap,getf(run,'Meta',[]));
    end
end
C    = mabr.compute.ConditionStore.conditions(store,L);
keys = mabr.compute.ConditionStore.roster(C);
if ~isequal(keys,rosterKeys)
    % Sent BEFORE the values that use it, so the client has the keys (and
    % the parameters that place each condition on an axis) by the time it
    % reads a publish carrying the new id.
    rosterKeys = keys;
    rosterId   = rosterId + 1;
    send(resultQueue,struct('type','roster','id',rosterId,'keys',{keys}, ...
        'params',{{C.Params}}));
end

nSlots = cfg.MaxComputeJobs;
J = build_jobs(jobs,custom,catalog,nSlots);
active = find(~cellfun(@isempty,{J.Fcn}));
vals   = nan(nSlots,numel(C));
incomplete = 0;
if ~isempty(active) && ~isempty(C)
    [v,~,done] = mabr.compute.evaluateJobs(C,J(active),budget);
    vals(active,:) = v;
    late = active(any(~done,2));
    incomplete = sum(2.^(late-1));
end
out.publish(struct('RosterId',rosterId,'Values',vals,'ReqSeq',reqSeq, ...
    'Incomplete',incomplete, ...
    'NumSweeps',arrayfun(@(c) size(c.Sweeps,2),C), ...
    'Live',logical([C.Live])));
end


function J = build_jobs(jobs,custom,catalog,nSlots)
% The request table as evaluateJobs jobs, one per slot; an inactive slot
% (or one whose function is missing) has an empty Fcn.
J = repmat(struct('Name','','Fcn',[],'Window',[]),1,nSlots);
for i = 1:min(nSlots,size(jobs,1))
    row = jobs(i,:);
    if row(1) <= 0, continue; end
    idx = row(2);
    if idx == mabr.compute.RequestBuffer.Custom
        if isempty(custom{i}), continue; end
        J(i).Fcn  = custom{i};
        J(i).Name = sprintf('custom metric (slot %d)',i);
    elseif idx >= 1 && idx <= numel(catalog)
        J(i).Fcn  = catalog(idx).Fcn;
        J(i).Name = catalog(idx).Name;
    else
        continue
    end
    if row(4) > row(3), J(i).Window = row(3:4); end
end
end


function tf = cycle_due(pipe,run,isDSP)
% The DSP worker has something to publish only during a run; the metrics
% worker cycles whenever it is configured (a metric can change between
% runs, and the finalized conditions are there to evaluate it over).
tf = ~isempty(pipe) && (~isDSP || ~isempty(run));
end

function s = elapsed(t)
if t == 0, s = Inf; else, s = toc(t); end
end

function v = getf(s,f,d)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function send_state(q,state)
send(q,struct('type','state','state',state));
end

function send_error(q,id,msg)
send(q,struct('type','error','identifier',id,'message',msg));
end
