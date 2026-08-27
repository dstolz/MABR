function verify_compute_worker()
% verify_compute_worker  The compute workers: the signal processing running
% in another process, and the foreground reading its results.
%
%   Part A (no pool): the publish buffers -- mabr.compute.LiveBuffer,
%           MetricBuffer and RequestBuffer -- round-trip a payload exactly, a
%           second publish lands in the other half and wins, a heartbeat
%           (a cycle with no sweep yet) reads back as a struct rather than
%           nothing, and a reader never sees a torn payload.
%   Part B: a controller built WITH the workers serves a loopback schedule
%           from the DSP worker: its own pipeline is never stepped, the
%           blocks still finalize, the tally still fires, the live view
%           still draws -- from statistics, with no sweep matrix here.
%   Part C: PARITY. The worker's statistics over a block are bit-identical
%           to mabr.compute.Pipeline stepping over the same ring bytes in
%           this process. Same code, same doubles: any difference is a bug,
%           not a tolerance.
%   Part D: priorities are actually applied (mabr.acq.Engine.set_priority
%           through .NET): this process reads back what it was set to, and
%           the DSP worker sits below normal.
%   Part E: the metrics worker evaluates a window's metric off-process and
%           the values match the same window evaluating in-process; a window
%           opened with every slot taken falls back; a hung custom metric
%           costs its window and not the live path, and the worker comes
%           back without it.
%   Part G: the online advance criterion still stops a run early when the
%           correlation it judges is the worker's.
%   Part F: a DSP worker lost mid-run -- the run is finalized anyway (by
%           this process from the intact ring when the reply never comes)
%           and the schedule completes.
%
%   Parts B-G need a parallel pool of three workers (mabr.pool). Where the
%   machine's cluster profile cannot provide one they are SKIPPED and Part A
%   alone decides -- a suite must not fail over a core count.
%
%   Requires the Parallel Computing Toolbox. No audio hardware.
%
%   See also mabr.compute.ComputeEngine, mabr.compute.compute_loop,
%   mabr.compute.Pipeline, verify_live_refresh.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_compute_worker ==\n');
cfg = mabr.Config;

%% ---- Part A: the publish buffers ---------------------------------------
w = mabr.compute.LiveBuffer(cfg,true);
r = mabr.compute.LiveBuffer(cfg,false);
w.zero();
assert(r.seq() == 0,'zero() did not reset the sequence');

s = mabr.compute.Pipeline.emptyStats(7);
nS = 240;
s.Time         = (1:nS)/12000 - 0.01;
s.NumSamples   = nS;
s.Latest       = randn(1,nS);
s.LatestBad    = true;
s.LatestStim   = 5;
s.Corr         = 0.5;
s.NumSweeps    = 10;
s.NumClean     = 9;
s.NumArtifacts = 1;
s.Stimuli      = [2 5];
s.Mean         = randn(2,nS);
s.SD           = rand(2,nS);
s.CondCounts   = [4 5 1; 5 5 0];
s.ReqSeq       = 3;

w.publish(s);
[P,sq] = r.read();
assert(sq == 1 && ~isempty(P),'the first publish did not read back');
f = fieldnames(s);
for i = 1:numel(f)
    assert(isequaln(P.(f{i}),s.(f{i})),'LiveBuffer field %s did not round-trip',f{i});
end

s2 = s; s2.Mean = -s.Mean; s2.RunId = 8;
w.publish(s2);
[P2,sq2] = r.read();
assert(sq2 == 2 && P2.RunId == 8 && isequal(P2.Mean,s2.Mean), ...
    'the second publish (other half) did not win');

w.publish(mabr.compute.Pipeline.emptyStats(9));
[P3,~] = r.read();
assert(~isempty(P3) && P3.NumSweeps == 0 && P3.RunId == 9 && isempty(P3.Time), ...
    'a heartbeat must read back as a struct with nothing in it, not as nothing');
assert(r.seq() == 3,'seq() does not count publishes');

% Rapid alternation: whatever a reader gets is one whole publish, never a
% mixture of two -- RunId and the sign of Mean always agree.
for k = 1:200
    if mod(k,2), w.publish(s); else, w.publish(s2); end
    if mod(k,37) == 0
        [Pk,~] = r.read();
        assert(~isempty(Pk),'read() returned nothing under rapid publishing');
        if Pk.RunId == 7, assert(isequal(Pk.Mean,s.Mean),'torn read (RunId 7)');
        else,             assert(isequal(Pk.Mean,s2.Mean),'torn read (RunId 8)');
        end
    end
end

mw = mabr.compute.MetricBuffer(cfg,true);
mr = mabr.compute.MetricBuffer(cfg,false);
mw.zero();
V = rand(cfg.MaxComputeJobs,5);
mw.publish(struct('RosterId',4,'Values',V,'ReqSeq',2,'Incomplete',5));
[Q,~] = mr.read();
assert(isequal(Q.Values,V) && Q.RosterId == 4 && Q.Incomplete == 5 && Q.ReqSeq == 2, ...
    'MetricBuffer did not round-trip');

qw = mabr.compute.RequestBuffer(cfg,true);
qr = mabr.compute.RequestBuffer(cfg,false);
qw.zero();
J = zeros(cfg.MaxComputeJobs,4); J(3,:) = [1 2 0 10];
qw.publish(struct('LivePeriod',0.05,'MetricPeriod',0.5,'Jobs',J));
[R,~] = qr.read();
assert(isequal(R.Jobs,J) && R.MetricPeriod == 0.5 && R.LivePeriod == 0.05, ...
    'RequestBuffer did not round-trip');
clear w r mw mr qw qr
fprintf('  PASS Part A: publish buffers round-trip, double-buffer, heartbeat\n');

%% ---- Pool: three workers, or stop here --------------------------------
[pool,ok] = mabr.pool(3);
if ~ok
    fprintf(['  SKIP Parts B-G: the parallel pool cannot hold three workers on ' ...
             'this machine (it has %d).\n'],pool.NumWorkers);
    fprintf('== verify_compute_worker PASSED (buffers only) ==\n');
    return
end

%% ---- Part B: a worker-served run ---------------------------------------
ctrl = mabr.ui.AcqController(cfg,true,[],false,true);
cleaner = onCleanup(@() delete(ctrl)); %#ok<NASGU>
ctrl.waitUntilReady();
assert(~isempty(ctrl.Compute),'no ComputeEngine was built');
assert(ctrl.Compute.hasDSP(),'the DSP worker did not handshake');
assert(ctrl.usingWorkerDSP(),'the controller does not report the DSP worker');

bank = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',[30 60]);
ctrl.setStimuli(bank);
ctrl.Session.Subject.ID = 'COMPUTE';
ctrl.Session.OutputPath = '';            % record without saving
ctrl.Schedule.Strategy    = 'interleaved';
ctrl.Schedule.Repetitions = 48;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 1024/cfg.DACSampleRate;

lp = mabr.ui.LivePlot();
ctrl.setLivePlot(lp);
cleanV = onCleanup(@() delete(lp)); %#ok<NASGU>

cnt = containers.Map({'aux'},{0});
lh  = addlistener(ctrl,'MetricsUpdated',@(~,~) bump(cnt,'aux')); %#ok<NASGU>
steps0 = ctrl.Pipeline.StepCount;

ctrl.start();
wait_until(@() ctrl.State == mabr.ui.ProgState.SchedComplete,120);
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not complete (state %s)',string(ctrl.State));
assert(ctrl.Pipeline.StepCount == steps0, ...
    ['the controller stepped its own pipeline %d times with a DSP worker up -- ' ...
     'the signal processing came back into the GUI process'], ...
    ctrl.Pipeline.StepCount - steps0);
assert(ctrl.Session.NumBlocks == 4,'expected 4 finalized blocks, got %d',ctrl.Session.NumBlocks);
assert(cnt('aux') > 0,'MetricsUpdated never fired in worker mode (the tally would freeze)');
h = findobj(lp.axLatest,'Type','line');
h = h(arrayfun(@(x) numel(x.XData) > 2,h));
assert(~isempty(h),'the live view drew nothing from the published statistics');
fprintf('  PASS Part B: worker-served run -- %d blocks, no in-process DSP, tally fired %d times\n', ...
    ctrl.Session.NumBlocks,cnt('aux'));

%% ---- Part C: parity, worker vs in-process ------------------------------
% The ring still holds the last run. Ask the worker to attribute and
% extract it afresh, and do the same here with a Pipeline of our own.
rr   = ctrl.Schedule.NumRuns;
seq  = ctrl.Schedule.runSequence(rr);
stim = unique(seq,'stable');
info = struct('RunId',12345,'StimIndex',seq,'Stimuli',stim, ...
    'Labels',{arrayfun(@(u) bank.id(u),stim,'UniformOutput',false)});
info.Meta = arrayfun(@(u) bank.meta(u),1:bank.numStimuli,'UniformOutput',false);

ctrl.Compute.runStart(info);
stats = []; last = -1; t0 = tic;
while toc(t0) < 15
    pause(0.1);
    s = ctrl.Compute.live();
    if isempty(s), continue; end
    if s.NumSweeps > 0 && s.NumSweeps == last, stats = s; break; end
    last = s.NumSweeps;
end
ctrl.Compute.runEnd(12345);
assert(~isempty(stats),'the DSP worker published nothing for the parity run');

p = mabr.compute.Pipeline(cfg);
p.configure(ctrl.Window,ctrl.Filters,ctrl.Artifacts);
p.beginRun(info);
ref = p.step(ctrl.Engine.RingBuffer);
assert(~isempty(ref) && ref.NumSweeps == stats.NumSweeps, ...
    'sweep counts differ: worker %d, in-process %d',stats.NumSweeps,ref.NumSweeps);
for f = {'Time','Latest','LatestBad','LatestStim','Corr','NumSweeps','NumClean', ...
         'NumArtifacts','Stimuli','Mean','SD','CondCounts'}
    assert(isequaln(stats.(f{1}),ref.(f{1})), ...
        'worker and in-process pipelines disagree on %s',f{1});
end
fprintf('  PASS Part C: worker statistics bit-identical to in-process (%d sweeps, %d conditions)\n', ...
    ref.NumSweeps,numel(ref.Stimuli));

% And the finalization DSP: the parts the worker replies with are the parts
% this process makes from the same ring bytes.
got = containers.Map('KeyType','char','ValueType','any');
lf  = addlistener(ctrl.Compute,'Finalized',@(~,e) put(got,'reply',e.Data)); %#ok<NASGU>
ctrl.Compute.finalize(777,seq);
wait_until(@() got.isKey('reply'),60);
assert(got.isKey('reply'),'the DSP worker never replied to Finalize');
reply = got('reply');
assert(isempty(reply.error),'the worker''s finalization errored: %s',reply.error);
Fw = reply.result;
Fl = p.finalize(ctrl.Engine.RingBuffer,seq);
assert(Fw.NumOnsets == Fl.NumOnsets && isequal(Fw.Seq,Fl.Seq), ...
    'finalization pairs onsets differently on the worker');
assert(numel(Fw.Parts) == numel(Fl.Parts),'finalization finds different stimuli on the worker');
for i = 1:numel(Fl.Parts)
    for f = {'Stimulus','Data','Processed','Onsets','SweepLength','Flags','Count'}
        assert(isequaln(Fw.Parts(i).(f{1}),Fl.Parts(i).(f{1})), ...
            'finalization part %d differs on the worker in %s',i,f{1});
    end
end
delete(lf);
fprintf('  PASS Part C: finalization on the worker bit-identical too (%d parts)\n',numel(Fl.Parts));

%% ---- Part D: priorities actually applied -------------------------------
pid = feature('getpid');
mabr.acq.Engine.set_priority(pid,'below normal');
mine = read_priority(pid);
mabr.acq.Engine.set_priority(pid,'normal');
assert(strcmp(mine,'BelowNormal'),'set_priority did not take (read back "%s")',mine);
assert(strcmp(read_priority(pid),'Normal'),'set_priority did not restore normal');
assert(strcmp(read_priority(ctrl.Compute.DSP.PID),'BelowNormal'), ...
    'the DSP worker is not below normal priority');
fprintf('  PASS Part D: priorities read back as set (DSP worker below normal)\n');

%% ---- Part E: the metrics worker ----------------------------------------
mp = mabr.ui.MetricPlot(ctrl);
cleanM = onCleanup(@() delete(mp)); %#ok<NASGU>
mp.Metric = 'rms';
assert(~isempty(mp.Slot),'the analysis window took no slot on the metrics worker');
t0 = tic;
while ~ctrl.Compute.hasMetrics() && toc(t0) < 60, pause(0.1); end
assert(ctrl.Compute.hasMetrics(),'the metrics worker did not handshake');

% The window's values must come from the worker, and match what the same
% window computes in-process over the same finalized blocks.
V = []; t0 = tic;
while toc(t0) < 30
    pause(0.3);
    V = mp.values();
    if ~isempty(V) && mp.ServedByWorker && all(isfinite([V.Value])), break; end
end
assert(~isempty(V) && mp.ServedByWorker,'the window is not being served by the metrics worker');
fprintf('    (served by the worker after %.1f s)\n',toc(t0));
ref = mp.localValues();
assert(numel(V) == numel(ref),'condition counts differ: worker %d, local %d',numel(V),numel(ref));
[~,ia] = sort({V.Key}); [~,ib] = sort({ref.Key});
V = V(ia); ref = ref(ib);
assert(isequal({V.Key},{ref.Key}),'the worker''s roster differs from the window''s');
assert(isequaln([V.Value],[ref.Value]), ...
    'metric values differ between the worker and in-process (max |d| = %g)', ...
    max(abs([V.Value]-[ref.Value])));

% Slots run out gracefully: with every other slot taken, a new window gets
% none, evaluates in-process, and nothing else changes.
taken = zeros(1,0);
while true
    s = ctrl.Compute.acquireSlot();
    if isempty(s), break; end
    taken(end+1) = s; %#ok<AGROW>
end
assert(numel(taken) == cfg.MaxComputeJobs-1, ...
    'expected %d free slots beside the window''s, found %d',cfg.MaxComputeJobs-1,numel(taken));
extra  = mabr.ui.MetricPlot(ctrl);
cleanX = onCleanup(@() delete(extra)); %#ok<NASGU>
assert(isempty(extra.Slot),'a window opened with every slot taken should have none');
assert(~isempty(extra.values()) && ~extra.ServedByWorker, ...
    'a window without a slot must compute in-process');
delete(extra); clear cleanX
for s = taken, ctrl.Compute.releaseSlot(s); end
assert(~isempty(ctrl.Compute.acquireSlot()),'released slots did not come back');

% A custom metric that never returns wedges the metrics worker and nothing
% else: the DSP worker and the acquisition are untouched, the slot is
% flagged so its window evaluates nothing in-process (a hang here is the one
% thing the third worker exists to prevent), and the worker is relaunched
% without it and comes back for the catalog metrics. Pushed through the
% engine rather than setCustomMetric, whose validator would run it here.
ctrl.Compute.setCustomMetric(mp.Slot,@mabrtest.hang);
ctrl.Compute.setJob(mp.Slot,mabr.compute.RequestBuffer.Custom,[0 10]);
fprintf('    (hung metric pushed; waiting for the watchdog)\n');
t0 = tic; lastSay = 0;
while ~ctrl.Compute.isStalled(mp.Slot) && toc(t0) < 90
    pause(0.5);
    mp.values();                     % the watchdog rides the consumer's polls
    if toc(t0) - lastSay >= 5
        lastSay = toc(t0);
        fprintf('    (%.0f s: worker %s)\n',lastSay,char(ctrl.Compute.Metrics.State));
    end
end
fprintf('    (stalled after %.1f s)\n',toc(t0));
assert(ctrl.Compute.isStalled(mp.Slot),'a hung custom metric was not detected');
assert(ctrl.Compute.hasDSP(),'the DSP worker was taken down with the metrics worker');
assert(mp.Stalled,'the window does not report its stalled slot');
assert(~ctrl.Compute.Metrics.Dead,'the metrics worker was written off instead of relaunched');
mp.Metric = 'p2p';                   % picking another metric clears the stall
assert(~mp.Stalled,'choosing a new metric did not clear the stall');
t0 = tic;
while toc(t0) < 90 && ~(ctrl.Compute.hasMetrics() && mp.ServedByWorker)
    pause(0.3);
    mp.values();
end
fprintf('    (worker back after %.1f s)\n',toc(t0));
assert(ctrl.Compute.hasMetrics() && mp.ServedByWorker, ...
    'the relaunched metrics worker did not come back to serve the window');
fprintf('  PASS Part E: metrics worker matches in-process; slots run out gracefully; a hung metric is contained\n');

%% ---- Part G: the advance criterion through the worker ------------------
% The correlation the criterion judges is the worker's: a blocked run with a
% threshold it will meet stops early, exactly as it does in-process
% (verify_online_advance), at most one worker cycle later.
%
% 1 kHz, deliberately. In loopback the "recording" IS the stimulus, so the
% criterion only has something to find if the stimulus survives the analysis
% path -- and the default display chain (10-3000 Hz) would remove the 8 kHz
% demo pip, which the live path's decimation has already aliased down. Rather
% than switch filtering off (verify_online_advance's answer to the same trap),
% pick a frequency that lives through the whole chain: this then tests the
% criterion on a FILTERED response, which is what it judges on a rig. 50 dB
% keeps the pip well under the default artifact threshold, so no sweep is
% rejected out from under the correlation.
delete(mp); clear cleanM
one = mabr.stim.demoStimuli(cfg,'Frequencies',1,'Levels',50);
ctrl.setStimuli(one);
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = 200;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 1024/cfg.DACSampleRate;
ctrl.AdvanceFcn    = @mabr.stim.advance.corr_threshold;
ctrl.AdvanceParams = struct('corrThreshold',0.3,'minSweeps',16,'maxSweeps',Inf, ...
                            'targetSweeps',200);
n0     = ctrl.Session.NumBlocks;
steps0 = ctrl.Pipeline.StepCount;
ctrl.start();
wait_until(@() ctrl.State == mabr.ui.ProgState.SchedComplete,120);
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the advance-criterion run did not complete (state %s)',string(ctrl.State));
assert(ctrl.Session.NumBlocks == n0 + 1,'expected one block from the blocked run');
nAdv = ctrl.Session.Blocks(end).NumSweeps;
assert(nAdv >= 10 && nAdv < 0.75*200, ...
    'the advance criterion did not stop the run early through the worker (%d of 200)',nAdv);
assert(ctrl.Pipeline.StepCount == steps0,'in-process DSP ran during the advance test');
fprintf('  PASS Part G: advance criterion fired through the worker at %d of 200 sweeps\n',nAdv);

%% ---- Part F: a DSP worker lost mid-run ---------------------------------
% The run still finalizes -- by the relaunched worker if it is back in time,
% by this process from the intact ring if not -- and the schedule completes.
ctrl.setStimuli(bank);
ctrl.Schedule.Strategy    = 'interleaved';
ctrl.Schedule.Repetitions = 48;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 1024/cfg.DACSampleRate;
ctrl.AdvanceFcn    = @mabr.stim.advance.num_sweeps;
ctrl.AdvanceParams = struct('targetSweeps',192,'corrThreshold',0.5,'minSweeps',32,'maxSweeps',Inf);
ctrl.FinalizeTimeout = 3;
n0 = ctrl.Session.NumBlocks;
ctrl.start();
pause(0.5);
cancel(ctrl.Compute.DSP.Future);         % the worker dies under a run
wait_until(@() ctrl.State == mabr.ui.ProgState.SchedComplete,120);
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not complete after the DSP worker was lost (state %s)',string(ctrl.State));
assert(ctrl.Session.NumBlocks == n0 + 4, ...
    'expected %d blocks after the DSP worker was lost, got %d',n0+4,ctrl.Session.NumBlocks);
assert(ctrl.Compute.DSP.Relaunched || ctrl.Compute.DSP.Dead, ...
    'the lost DSP worker was neither relaunched nor written off');
fprintf('  PASS Part F: a DSP worker lost mid-run -- run finalized, schedule completed, worker %s\n', ...
    tern(ctrl.Compute.hasDSP(),'relaunched','written off'));

fprintf('== verify_compute_worker PASSED ==\n');
end


% =====================================================================
function wait_until(pred,timeout)
t0 = tic;
while ~pred() && toc(t0) < timeout
    pause(0.02);
end
end

function bump(m,k)
m(k) = m(k) + 1;
end

function put(m,k,v)
m(k) = v;
end

function s = tern(tf,a,b)
if tf, s = a; else, s = b; end
end

function s = read_priority(pid)
s = char(System.Diagnostics.Process.GetProcessById(int32(pid)).PriorityClass.ToString());
end
