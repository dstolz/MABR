classdef AcqController < handle
% mabr.ui.AcqController  Wires the UI to the acquisition engine.
%
%   Owns the mabr.acq.Engine, the mabr.data.Session, the mabr.stim.Schedule,
%   and the live view. Translates user actions into engine commands and engine
%   events into UI updates and program-state transitions. There is NO global
%   state and NO busy-wait: engine State transitions arrive as events, and two
%   timers refresh the views from the ring buffer.
%
%   The two are split by PRIORITY. LiveTimer (~20 Hz) does the work the live
%   trace and the advance criterion depend on: step the mabr.compute.Pipeline
%   -- which extracts the new sweeps, filters them, previews the artifact
%   verdict and correlates; the DSP lives there, not here -- then draw and
%   decide. AuxTimer (~2 Hz, see AuxPeriod) raises the MetricsUpdated event
%   the progress tally and the Run panel's readouts ride. The aux timer is
%   'fixedSpacing'; the live one polls every LivePoll (10 ms) and draws a
%   frame once LivePeriod (50 ms) has passed since the last one BEGAN
%   (on_live_tick) -- so it holds 20 Hz while a frame costs less than about
%   40 ms, and work in it still comes straight off the frame rate beyond
%   that, which is the whole reason the slow half is not in it.
%
%   The snapshot the online analysis windows pull (liveSnapshot) is built by
%   neither timer: it is a copy of every sweep of the run so far, so it is
%   made when a window asks for it -- at most once per AuxPeriod however
%   many ask, and only while the run's sweeps are in this process
%   (LiveLocal). It used to be built on every aux tick, read or not: ~10 ms
%   of the GUI thread twice a second at 9,000 sweeps, with nothing open to
%   look at it.
%
%   Because the worker polls commands every frame, an online advance criterion
%   (e.g. mabr.stim.advance.corr_threshold) can stop a run early the moment a
%   response is detected — the capability the legacy design could not offer.
%   That applies only to BLOCKED strategies, where a run holds one stimulus.
%   An intermixed run (interleaved / random) always plays to completion:
%   stopping it early would truncate whichever stimuli happened to fall last
%   in the sequence, unbalancing the design.
%
%   For the same reason, repeatLastBlock (the GUI's Repeat button) only ever
%   has something to repeat after a BLOCKED run: canRepeat() and
%   LastRunStimulus track the stimulus of the most recently completed
%   single-stimulus run, and stay unset across an intermixed one.
%
%   Loop (the GUI's Loop toggle) holds the plan on the condition in progress:
%   while it is set, every run that ends by itself -- played out, or stopped
%   by the advance criterion -- is presented again, pass after pass, and the
%   plan goes on to the next run only once Loop is cleared. Like Repeat it is
%   for a BLOCKED plan, one condition per run (canLoop): an intermixed run is
%   every condition at once, and repeating it would repeat the session, not
%   hold a condition. Recorded or stimulation-only, each pass is a run of its
%   own, finalized, saved and credited like any other (see loop_run).
%   Advance (stopBlock) still means advance: it ends the pass and moves on,
%   and the next run is then held in its turn. Abort still halts.
%
%   A run may contain more than one stimulus. At finalization the recorded
%   sweeps are de-interleaved by mabr.stim.Schedule's per-onset stimulus
%   index, so each stimulus ID still becomes its own mabr.data.Block and its
%   own .abr file regardless of how the presentation was ordered.
%
%   Schedule.StimulationOnly (from mabr.AudioSettings) removes the recording
%   half of all of that: the worker opens an output-only device, so start()
%   skips the loop-back self-test, no live timer runs, and a completed run is
%   not finalized -- no Block, no BlockReady, no .abr. The plan still advances
%   run by run to SchedComplete, which is all there is to report when nothing
%   is coming back.
%
%   What such a run DOES save is the stimulation sequence itself (see
%   log_stim_run): one .stimlog file per run, holding every presentation in
%   play order with its stimulus, polarity, and onset time, plus which of them
%   actually went out. Nothing is recorded, but what was played is still the
%   experimental record -- and on a rig where another system does the
%   recording it is the only thing that can align the two. BlockSaved fires
%   for it, so the GUI reports a written stimulation log exactly as it reports
%   a written .abr.
%
%   Artifact rejection is DECIDED at that same finalization, which is why the
%   Artifacts policy is settable at any time, including mid-acquisition: the
%   live path holds no verdict of its own. It does preview one — live_tick_body
%   applies the current policy to the sweeps it has, so the live mean shows the
%   average the block will hold and a noisy electrode is visible as it happens
%   — but nothing there is recorded, and re-pointing Artifacts simply changes
%   what the next tick previews. See the property and set.Artifacts below.
%
%   The session's rig notebook (mabr.data.SessionNotes) rides along with all
%   of that: finalize_run copies the log onto each Block it builds and
%   log_stim_run puts it in each .stimlog, so every file a run writes carries
%   what the operator had written by the time it was written. noteContext is
%   the other direction -- it tells the notebook where the session is, so a
%   note taken mid-run is stamped with that run and its sweep count.
%
%   The INPUT MONITOR (startMonitor/stopMonitor) records with no stimulus at
%   all: silent blocks streamed through the same worker, device and ring
%   buffer a run uses, re-armed lap after lap until stopped, so the raw input
%   can be watched -- mabr.ui.SpectrumViewer's power spectrum -- while
%   electrical noise is hunted down with the electrodes in place and no
%   schedule loaded. Like the timing self-test, a monitor block is invisible
%   to everything a run drives: no ProgState change, no live timer, no
%   finalization, no Block, no file. inputSamples is what a view reads the
%   newest raw samples through, whether the monitor, a run, or nothing is
%   filling the ring. start() stops the monitor first -- a schedule owns
%   the device.
%
%   Events the App can listen to:
%       StateChanged     - program flow changed (mabr.ui.ProgStateEventData)
%       MetricsUpdated   - live metrics changed (ProgStateEventData.Info)
%       BlockReady       - a finalized mabr.data.Block is available
%                          (.Info.block); fires once per stimulus recovered
%                          from the run, whether or not it was written to
%                          disk. This is what viewers (mabr.ui.TraceOrganizer)
%                          listen to so a trace appears as each block lands.
%       BlockSaved       - a file was written (.Info.file), and only when the
%                          Session has an OutputPath: once per stimulus
%                          recovered from a recorded run, or once per run for
%                          the .stimlog of a stimulation-only one
%       ScheduleComplete - the whole schedule finished
%       MetricsReset     - resetMetrics() was called: the online analysis
%                          windows forget the conditions gathered so far
%       MonitorChanged   - the input monitor started or stopped (Monitoring;
%                          MonitorError says why, if the worker stopped it)
%       AlignmentChecked - a finished run's recovered onsets were held
%                          against the onsets the plan rendered
%                          (.Info.report, a mabr.metrics.alignment_report).
%                          Raised for EVERY recorded run, not only in Test
%                          Mode: a drifting offset means the k-th sweep is
%                          not the k-th presentation, which is as much a
%                          fault on a rig as it is in loopback. What Test
%                          Mode adds is the sample-exact waveform comparison
%                          the report's MaxError carries -- see alignmentCheck.
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Config
        % How many of Session's blocks resetMetrics() has already put behind
        % the online analysis: a window attached later backfills from the
        % block after this one, so a reset is not undone by opening another.
        MetricsBase (1,1) double = 0
        Engine      mabr.acq.Engine
        Session     mabr.data.Session
        Stimuli     mabr.stim.StimulusSet
        Schedule    mabr.stim.Schedule
        LivePlot    mabr.ui.LivePlot
        % Every computation made from recorded samples -- sweep extraction,
        % the display chain, the artifact preview, the correlation, the
        % per-condition statistics, and the finalization DSP. Stepped from
        % the live tick and asked to finalize at the end of a run; the
        % controller itself does no signal processing (see
        % mabr.compute.Pipeline).
        Pipeline
        State (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        Testing (1,1) logical = false
        % Whether the compute workers were asked for at construction, and
        % the mabr.compute.ComputeEngine that runs them -- [] when they were
        % not asked for, the pool could not hold them, or they failed to
        % start. Every path that could use one checks hasDSP()/hasMetrics()
        % on it first and does the work here otherwise (see live_tick_body),
        % so a controller built without one -- which is what every
        % verification script builds -- is the in-process path by
        % construction.
        UsingCompute (1,1) logical = false
        Compute = []
        % True once verifyTimingLoop has confirmed the timing loop-back is
        % wired FOR THE CURRENT Device/PlayerChannels/RecorderChannels (see
        % VerifiedAudioConfig below), so start() only pays for the check once
        % per audio configuration rather than once per controller. Device and
        % channel mapping are a mabr.ui.App "config control" that re-locks
        % during acquisition but is editable again between runs on the same
        % controller (mabr.ui.App.ensureController reuses one across Start
        % clicks) -- so a stale cache here could silently skip re-verifying
        % after the user changes ASIO device or wiring mid-session.
        TimingVerified (1,1) logical = false
        % What the last finished run's onsets came back as, held against what
        % the plan rendered (see alignmentCheck). [] until a run finalizes.
        % Kept rather than only announced because the question it answers --
        % "is the sweep I am looking at the presentation the file says it is"
        % -- is asked after the fact at least as often as during.
        LastAlignment = []
        % Where the last finished run's live-view ticks spent their time: a
        % mabr.ui.LiveTiming summary (rates, per-phase percentiles in ms, a
        % one-line verdict, and .Text, the report as logged). [] until a
        % recorded run completes. See report_live_timing.
        LastLiveTiming = []
        % The input monitor is streaming (see startMonitor), and -- once it
        % has stopped -- why, when it was the worker that stopped it ('' when
        % it was asked to).
        Monitoring   (1,1) logical = false
        MonitorError (1,:) char = ''
    end

    properties
        Window        (1,2) double = [0 0.01];   % ADC window (s) relative to onset
        AdvanceFcn    (1,1) = @mabr.stim.advance.num_sweeps;
        AdvanceParams (1,1) struct = struct('targetSweeps',512,'corrThreshold',0.5, ...
                                            'minSweeps',32,'maxSweeps',Inf);
        % Digital filtering of everything VIEWED — the live plot's traces and
        % correlation bar, and the sweeps a finalized Block reports on. Like
        % Artifacts it may be REASSIGNED WHILE ACQUIRING (mabr.ui.App's filter
        % dialog does exactly that): the live path re-reads it every tick and
        % finalization re-reads it per run, so a change is visible on the next
        % refresh and costs nothing. It never touches Recording.Data, so the
        % .abr file carries the raw trace whatever this says — retuning the
        % chain is a display decision, not a data decision. See set.Filters,
        % which caches the design so designfilt stays out of the 20 Hz tick.
        Filters       (1,1) mabr.FilterPolicy = mabr.FilterPolicy;
        % How sweeps are judged for artifact, and whether losses are made up.
        % DECIDED at finalization (see finalize_run) and merely previewed live,
        % so like Filters it may be REASSIGNED WHILE ACQUIRING: mabr.ui.App
        % leaves its artifact controls live and writes here on every change.
        % The next tick previews the new rule and every run finalized from then
        % on is judged by it; runs already finalized keep the verdict they were
        % judged under. See set.Artifacts for the one consequence that cannot
        % simply wait for the next run.
        Artifacts     (1,1) mabr.ArtifactPolicy = mabr.ArtifactPolicy;
        % The gain the recorded signal is divided by, so that everything
        % computed from it -- live view, artifact thresholds, metrics, and
        % the Data every .abr carries -- is in volts at the electrodes:
        % mabr.AudioSettings.recordingGain, the external amplifier over the
        % input's full scale (1 = neither). Applied by the pipeline, never to
        % the ring, so the timing channel and the alignment check stay in
        % converter units.
        AmplifierGain (1,1) double {mustBePositive,mustBeFinite} = 1;
        % The input's full scale inside that divisor (volts at the recorder
        % input reading as 1.0; mabr.AudioSettings.inputFullScale). Scales
        % nothing itself: it is recorded on each Block, so a file can state
        % the external gain and the knob separately.
        InputFullScale (1,1) double {mustBePositive,mustBeFinite} = 1;
        % How often the LOW-priority views are served (s). The live trace is
        % fixed at 20 Hz and is not negotiable -- this is the other timer, the
        % one carrying the progress tally -- and the most often the online
        % analysis snapshot is rebuilt, however many windows pull it.
        % Raise it on a slow machine or with several analysis windows open:
        % nothing on it is time-critical, and every tick it does not take is a
        % tick the live view gets. Applied on assignment, mid-run included.
        %
        % 0.5 s (2 Hz) because none of it is read faster than that: a tally
        % moving in units of a sweep and a metric averaged over a condition
        % both change on the scale of a run. It is deliberately slower than
        % mabr.ui.ProgressMonitor's own MinInterval throttle (0.2 s), which
        % therefore no longer binds -- that window now repaints once per event
        % rather than dropping three of every four.
        AuxPeriod     (1,1) double {mustBePositive} = 0.5;
        % How long (s, plus a per-sample allowance) the DSP worker is given
        % to finalize a run before this process does it instead (see
        % on_finalize_timeout). Generous: finalization is a resample of the
        % whole block, and a slow reply is worth waiting for where a dead
        % worker is not -- the ring still holds the block either way.
        FinalizeTimeout (1,1) double {mustBePositive} = 30;
        % Hold the plan on the run in progress (mabr.ui.App's Loop toggle).
        % Read when a run ENDS, not when it starts, so it may be set or
        % cleared at any time, mid-run included: set, the run that is
        % playing is presented again when it ends, and again after that;
        % cleared, the pass playing finishes and the plan goes on from the
        % run that was next. Never cleared by the controller itself -- only
        % whoever set it can decide the loop is over. Honoured only for a
        % plan of one condition per run (canLoop); under an intermixed one
        % it is ignored, and the log says so. See loop_run.
        Loop (1,1) logical = false;
        % How long one lap of the input monitor is (s): a block that long is
        % streamed, then another, until stopMonitor. Each lap restarts the
        % ring, so a spectrum view briefly has less than its full average to
        % work with at every boundary -- long laps make that rare. Capped at
        % the ring's length. Read at startMonitor.
        MonitorSeconds  (1,1) double {mustBePositive} = 300;
    end

    properties (Constant)
        % The live view's frame pacing (s; see on_live_tick). A frame is
        % drawn once LivePeriod has passed since the last one began, and the
        % timer asks every LivePoll whether one is due -- so a frame's own
        % work no longer adds to the interval between frames, and the thread
        % still has LivePoll to itself after every tick.
        LivePeriod = 0.05
        LivePoll   = 0.01
    end

    properties (Access = private)
        LiveTimer
        % The second, slower timer. The live view is the one thing that has to
        % keep up with the electrode -- an ABR average is watched as it forms,
        % and a stuttering trace is the difference between seeing a bad
        % electrode now and seeing it after the block. Everything ELSE drawn
        % from a running block (the progress tally, the online analysis
        % windows) is answering a question that moves on the scale of a run,
        % not a sweep, and there is no reason for it to be recomputed twenty
        % times a second.
        %
        % The two are split because every millisecond of low-priority work in
        % the live tick comes straight off the live view's frame rate: a
        % frame is due LivePeriod after the last one began, so once a tick
        % costs more than that (less the poll) it drags the whole view down
        % with it. Moving the slow work here buys the trace back.
        AuxTimer
        % Whether the run streaming has its sweeps in THIS process: set by
        % a live tick whose statistics came from this controller's own
        % pipeline, cleared by one served by the DSP worker (which leaves
        % no sweep matrix here), when a run begins, and when it ends
        % (stop_timer). liveSnapshot builds only while it is set, so a
        % finished run cannot be served to a puller after the fact.
        LiveLocal (1,1) logical = false
        % Frame pacing (on_live_tick): when the last frame began, in seconds
        % on LiveClock (a tic taken at construction). -Inf = the next poll
        % draws.
        LiveClock      = uint64(0)
        LastFrameStart (1,1) double = -Inf
        CurMetrics (1,1) struct = struct('numSweeps',0,'numArtifacts',0, ...
                                         'numClean',0,'corr',0);
        BlockStart (1,:) char = '';
        % tic reference for the run currently streaming, so an advance
        % criterion can reason in wall-clock seconds (ctx.elapsedSeconds).
        % 0 until the first run of a session begins.
        RunStartTic (1,1) uint64 = uint64(0);
        % Names each run to the compute workers: a counter unique for this
        % controller's lifetime rather than the schedule index, which recurs
        % from one Start to the next -- a publish left over from the last
        % schedule's run 1 must not be taken for this one's.
        RunSerial  (1,1) double = 0;
        % The RunStart for the compute workers, held from begin_current_run
        % until the run's FIRST Acquire (see on_engine_state), and [] once
        % sent or once the run is over. A worker windows whatever the ring
        % holds, and until the acquisition worker resets it for the run --
        % which it does just before reporting Acquire -- the ring holds the
        % PREVIOUS run: told any earlier, the DSP worker published that run's
        % sweeps under the new run's id, and the first live tick's advance
        % check stopped the new run one frame in, with nothing recorded.
        PendingRunStart = []
        CurRun     (1,1) double = 0;    % index of the run being acquired
        CurSeq     (1,:) double = [];   % stimulus index at each of its onsets
        CurPol     (1,:) double = [];   % polarity (+1/-1) at each of its onsets
        % Where each of those onsets sits in the run's play matrix, straight
        % from mabr.stim.Schedule.renderSpec. Recorded runs recover the onsets
        % that actually came back off the timing channel and have no use for
        % these; a stimulation-only run has no input at all, so the rendered
        % positions are what its .stimlog reports (see log_stim_run).
        CurOnsets  (1,:) double = [];
        % The stimuli this run presents and what to call them, worked out once
        % when the run is prepared rather than on every one of the 20 live
        % ticks a second. The live view lays out one mean per entry, so the
        % list is the RUN's, in presentation order -- not the whole bank's.
        CurStim    (1,:) double = [];
        CurLabels  (1,:) cell   = {};
        % The stimulus parameters behind those entries (see
        % mabr.stim.StimulusSet.paramTable), row-aligned with CurStim. The
        % live view labels, orders, groups, and colours its means from this --
        % a Frequency x Level run is not a list, and presentation order is not
        % the order to read it in. Worked out once per run alongside the labels.
        CurParams  (1,1) struct = struct('Names',{{}},'Values',zeros(0,0), ...
                                         'Varying',false(1,0),'Units',{{}});
        HaltAfterBlock (1,1) logical = false;
        % The user pressed Advance (stopBlock) during the run in progress: an
        % instruction to move on, so loop_run does not hold the plan on this
        % run whatever Loop says. One-shot -- cleared as each run begins --
        % and deliberately NOT set by the advance criterion, which only
        % decides when a pass has enough (see loop_run).
        AdvanceRequested (1,1) logical = false;
        % Stimulus index of the most recently completed run, for the GUI's
        % Repeat button -- 0 until one exists. Only ever set for a BLOCKED
        % run (see on_block_completed): an intermixed run has no single
        % stimulus to repeat, so it is left at 0 and canRepeat() stays false
        % for the run's whole duration.
        LastRunStimulus (1,1) double = 0;
        Listeners
        % Pre-run hardware self-test: streams a synthetic timing-only block
        % through the real Engine.prep/run path before the first real block
        % of a session (see verifyTimingLoop). Makes that synthetic block
        % invisible to on_engine_state/on_block_completed -- it must not
        % touch ProgState, the live timer, or finalize_run.
        SelfTestActive  (1,1) logical = false
        % Blocks the engine has reported complete, self-test and monitor laps
        % included. verifyTimingLoop waits for this to move rather than for
        % the engine's State to read Completed, which it already does after
        % any earlier block -- a stopped monitor lap, a finished run -- and
        % would let the check read the ring before its own block was in it.
        CompletedCount  (1,1) double = 0
        % The input monitor, while it runs: whether another lap is wanted when
        % this one ends (cleared by stopMonitor), and the render spec each lap
        % is prepared from (see startMonitor).
        MonitorWanted   (1,1) logical = false
        MonitorSpec     = []
        % This controller has streamed into the ring (a run or a monitor
        % lap). Until it has, the ring holds whatever an earlier MATLAB
        % session left in the files, which inputSamples must not pass off as
        % this rig's input.
        HasRecorded     (1,1) logical = false
        % Device/PlayerChannels/RecorderChannels last confirmed by
        % verifyTimingLoop, [] until the first pass. start() re-verifies
        % whenever obj.Schedule's current values no longer match this.
        VerifiedAudioConfig = []
        % Finalization on the DSP worker is asynchronous: on_block_completed
        % sends Finalize and returns, leaving ProgState in BlockComplete,
        % and the schedule-advance tail runs when the reply arrives
        % (on_finalized) -- or when this single-shot timer fires first and
        % the run is finalized here from the ring, which nothing overwrites
        % until the next Run. The flag and the run id make a late reply for
        % a run already finalized here harmless.
        FinalizeTimer   = []
        FinalizePending (1,1) logical = false
        FinalizeRunId   (1,1) double = 0
        % The last snapshot a window pulled (see liveSnapshot), and when it
        % was made (s on LiveClock), so several windows asking within one
        % AuxPeriod share one copy. Cleared when a run begins and again the
        % moment one completes, so a puller can never double-count the
        % sweeps a finished run is about to be finalized into.
        LiveSnap = []
        LiveSnapAt (1,1) double = -Inf
        % Per-tick timing of the run in progress (mabr.ui.LiveTiming): reset
        % at begin_current_run, fed by on_live_tick/on_aux_tick, summarized
        % into LastLiveTiming when the run completes.
        Timing
    end

    events
        StateChanged
        MetricsUpdated
        BlockReady
        BlockSaved
        ScheduleComplete
        MetricsReset
        MonitorChanged
        AlignmentChecked
    end

    methods
        function obj = AcqController(cfg,testing,progressFcn,stimOnly,useCompute)
            % progressFcn (optional) receives char status messages while the
            % engine starts up; forwarded straight to mabr.acq.Engine.
            % stimOnly (optional) only names the worker it launches -- the mode
            % itself is Schedule.StimulationOnly and rides per block, so this
            % is purely so the startup messages say "stimulus worker" from the
            % first one rather than after start() re-labels it.
            % useCompute (optional, default false) asks for the compute
            % workers (mabr.compute.ComputeEngine). The parallel pool must
            % already be big enough -- mabr.ui.App sizes it with mabr.pool
            % before building a controller -- and if it is not, or the
            % workers fail to start, the controller simply computes
            % in-process, which is what it does whenever this is false.
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            if nargin < 2 || isempty(testing), testing = false; end
            if nargin < 3, progressFcn = []; end
            if nargin < 4 || isempty(stimOnly), stimOnly = false; end
            if nargin < 5 || isempty(useCompute), useCompute = false; end
            obj.Config       = cfg;
            obj.Testing      = logical(testing);
            obj.UsingCompute = logical(useCompute);

            obj.Session = mabr.data.Session(cfg);
            obj.Engine  = mabr.acq.Engine(cfg,obj.Testing,progressFcn, ...
                mabr.ui.AcqController.workerRole(stimOnly));
            obj.Listeners = [ ...
                addlistener(obj.Engine,'StateChanged', @(~,e) obj.on_engine_state(e)); ...
                addlistener(obj.Engine,'BlockCompleted',@(~,~) obj.on_block_completed()); ...
                addlistener(obj.Engine,'WorkerError',  @(~,e) obj.on_engine_error(e))];

            % The compute workers, if asked for. Never fatal: a rig whose
            % pool cannot hold them, or on which they fail to start, still
            % acquires -- the controller just does the DSP itself.
            if obj.UsingCompute
                try
                    obj.Compute = mabr.compute.ComputeEngine(cfg,progressFcn);
                    obj.Listeners(end+1) = addlistener(obj.Compute,'WorkerError', ...
                        @(~,e) obj.on_compute_error(e));
                    obj.Listeners(end+1) = addlistener(obj.Compute,'Finalized', ...
                        @(~,e) obj.on_finalized(e));
                catch me
                    obj.Compute = [];
                    mabr.log.vprintf(0,1,'Compute workers unavailable (%s); computing in-process.', ...
                        me.message);
                end
            end

            % A poll, not a frame clock: every LivePoll it asks whether a frame
            % is due (on_live_tick), and one is once LivePeriod has passed
            % since the last BEGAN. A 50 ms 'fixedSpacing' timer measured its
            % period from the END of a tick, so the realized interval was
            % 50 ms PLUS the frame -- ~70 ms, about 14 Hz, before anything else
            % ran. Polling holds 20 Hz up to a ~40 ms frame and follows a
            % slower frame by one poll, and 'fixedSpacing' at the poll still
            % leaves the thread LivePoll to itself after EVERY tick, so the
            % engine's states and a finalize reply always get their moment
            % ('fixedRate' at 50 ms reaches 20 Hz too, but halves the rate
            % the moment a frame outgrows the gap it would leave). A poll that
            % draws nothing costs ~0.02 ms.
            obj.LiveTimer = timer('Tag','MABR_LiveView', ...
                'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                'Period',obj.LivePoll,'TasksToExecute',Inf, ...
                'TimerFcn',@(~,~) obj.on_live_tick());
            obj.LiveClock = tic;

            % Ten times slower, and everything on it is something nobody
            % reads at 20 Hz anyway: a sweep tally, a metric across
            % conditions. 'drop' rather than 'queue' is the priority setting
            % MATLAB actually offers -- a slow repaint here is skipped instead
            % of accumulating a backlog that would later compete with the live
            % view for the same single thread.
            obj.AuxTimer = timer('Tag','MABR_AuxView', ...
                'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                'Period',obj.AuxPeriod,'TasksToExecute',Inf, ...
                'TimerFcn',@(~,~) obj.on_aux_tick());
            obj.Timing = mabr.ui.LiveTiming();

            % Property defaults bypass the setters, so the pipeline is
            % configured explicitly here or the first ticks would run with
            % nothing designed.
            obj.Pipeline = mabr.compute.Pipeline(cfg);
            obj.configure_pipeline();
        end

        function delete(obj)
            obj.stop_timer();
            try, obj.disarm_finalize_timeout(); end %#ok<TRYNC>
            try, delete(obj.LiveTimer); end %#ok<TRYNC>
            try, delete(obj.AuxTimer);  end %#ok<TRYNC>
            try, delete(obj.Listeners);  end %#ok<TRYNC>
            try, delete(obj.LivePlot);   end %#ok<TRYNC>
            try, delete(obj.Compute);    end %#ok<TRYNC>
            try, delete(obj.Engine);     end %#ok<TRYNC>
        end

        function waitUntilReady(obj,timeout)
            if nargin < 2, timeout = 120; end
            obj.Engine.waitUntilReady(timeout);
            % The DSP worker's handshake is waited for too, but bounded and
            % never fatal: without it the session computes in-process.
            if ~isempty(obj.Compute)
                obj.Compute.waitUntilReady(min(timeout,60));
                obj.configure_pipeline();     % the worker gets the policies
                % ... and has designed its chain before any run needs it: a
                % fresh worker's first design takes seconds, which the first
                % run's live view would otherwise spend empty (see
                % mabr.compute.ComputeEngine.waitConfigured).
                obj.Compute.waitConfigured(min(timeout,30));
            end
        end

        function tf = usingWorkerDSP(obj)
            % Whether the live path is currently served by the DSP worker.
            tf = ~isempty(obj.Compute) && obj.Compute.hasDSP();
        end

        % --- Configuration --------------------------------------------------
        function setStimuli(obj,stimuli)
            % stimuli: a mabr.stim.StimulusSet, or the raw struct array the
            % external package supplies (signal + ID per entry).
            if ~isa(stimuli,'mabr.stim.StimulusSet')
                stimuli = mabr.stim.StimulusSet(stimuli,obj.Config);
            end
            obj.Stimuli  = stimuli;
            obj.Schedule = mabr.stim.Schedule(stimuli,obj.Config);
            % A stale index from a previous stimulus set would point at the
            % wrong entry (or none at all) in this one.
            obj.LastRunStimulus = 0;
        end

        function set.Filters(obj,p)
            % The live path cannot afford to design the chain itself (see
            % mabr.compute.Pipeline), so the one moment the settings can
            % change is the one moment worth spending designfilt in. Same
            % MCSUP caveat as set.Artifacts below: a controller is never
            % deserialized.
            obj.Filters = p;
            obj.configure_pipeline();
        end

        function set.AmplifierGain(obj,g)
            % Same MCSUP caveat as set.Filters: never deserialized.
            obj.AmplifierGain = g;
            obj.configure_pipeline();
        end

        function set.Window(obj,w)
            % The window decides the sweep length, so the pipeline re-extracts
            % under a new one -- from the ring, which still holds the block.
            obj.Window = w;
            obj.configure_pipeline();
        end

        function set.AuxPeriod(obj,v)
            % Retune the running timer rather than waiting for the next run:
            % the reason to raise this is that the machine is struggling NOW.
            % A timer's Period is read-only while it runs, so it is stopped
            % and restarted -- cheap, and only the low-priority views miss a
            % beat. Same MCSUP caveat as set.Filters: never deserialized.
            obj.AuxPeriod = v;
            obj.apply_aux_period();
        end

        function setLivePlot(obj,lp)
            obj.LivePlot = lp;
            obj.caption_live_plot();
        end

        function set.Artifacts(obj,p)
            % The policy is re-read wherever it is used — every live tick, and
            % every finalization — so a new one needs no handshake with the
            % worker: store it and the next run to finish is judged by it,
            % costing nothing in between. The exception is Repeat, which has
            % already had a physical consequence — make-up runs appended to the
            % plan. Clearing it mid-schedule has to withdraw the ones not yet
            % reached, or the user would sit through re-presentations of a
            % policy they just switched off.
            %
            % Reaching Schedule from a set method is flagged (MCSUP) because
            % property set ORDER is undefined when an object is deserialized.
            % A controller is never saved or loaded — it owns a live pool
            % worker — so there is no such moment here.
            wasRepeating = obj.Artifacts.Repeat;
            obj.Artifacts = p;
            if wasRepeating && ~p.Repeat && ~isempty(obj.Schedule) %#ok<MCSUP>
                obj.Schedule.dropPendingMakeup();                 %#ok<MCSUP>
            end
            obj.configure_pipeline();
        end

        % --- User actions ---------------------------------------------------
        function start(obj)
            assert(~isempty(obj.Schedule),'mabr:ui:AcqController:noStimuli', ...
                'No stimuli set. Call setStimuli() first.');
            assert(obj.Schedule.NumRuns > 0,'mabr:ui:AcqController:emptySchedule', ...
                'The schedule is empty — every stimulus has 0 repetitions.');
            % The ring buffer is what the DSP worker is finalizing from, and
            % the next Run resets it.
            assert(~obj.FinalizePending,'mabr:ui:AcqController:finalizing', ...
                'The previous run is still being finalized; try again in a moment.');
            % A schedule owns the device: the input monitor gives it up
            % first, and is waited for, so its last lap is over before the
            % self-test or the first run is prepared behind it.
            obj.stopMonitor();
            % One worker is reused across runs that may switch modes between
            % them, so what it is about to spend the session doing is decided
            % here, not at construction.
            obj.Engine.setRole(mabr.ui.AcqController.workerRole( ...
                obj.Schedule.StimulationOnly));
            % Stimulation only has no input side at all -- the worker opens an
            % output-only audioDeviceWriter -- so there is no loop-back to
            % verify and requiring one would make the mode impossible to use.
            if ~obj.Schedule.StimulationOnly
                audioCfg = struct('Device',obj.Schedule.Device, ...
                    'PlayerChannels',obj.Schedule.PlayerChannels, ...
                    'RecorderChannels',obj.Schedule.RecorderChannels);
                obj.TimingVerified = ~isempty(obj.VerifiedAudioConfig) && ...
                    isequal(obj.VerifiedAudioConfig,audioCfg);
                if ~obj.TimingVerified
                    if ~obj.verifyTimingLoop()
                        error('mabr:ui:AcqController:timingNotDetected', ...
                            ['Timing pulse not detected on the loop-back input during the ' ...
                             'pre-run check. Check that the timing output channel is physically ' ...
                             'wired to the timing input channel (default channel 2 to channel 2) ' ...
                             'and that the loop-back level is not excessively attenuated.']);
                    end
                    obj.VerifiedAudioConfig = audioCfg;
                    obj.TimingVerified = true;
                end
            end
            obj.HaltAfterBlock = false;
            obj.Schedule.reset();
            % A new schedule: the live view's finished conditions belong to
            % the last one (and possibly another bank).
            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot), obj.LivePlot.clearSession(); end
            obj.begin_current_run();
        end

        function pauseAcq(obj),  obj.Engine.pause();  end
        function resumeAcq(obj), obj.Engine.resume(); end

        function stopBlock(obj)
            % Finish the current block early and advance to the next -- with
            % Loop set too: the user asked to move on, and the next run is
            % then the one held (see loop_run).
            obj.HaltAfterBlock   = false;
            obj.AdvanceRequested = true;
            obj.Engine.stop();
        end

        function abort(obj)
            % Finish the current block early and halt the schedule.
            obj.HaltAfterBlock = true;
            obj.Engine.stop();
        end

        % --- Input monitor --------------------------------------------------
        function startMonitor(obj,audio)
            % Record the input with no stimulus: silence goes out on both
            % channels, the input comes back into the ring buffer, and
            % inputSamples reads it -- which is all a noise hunt needs, and
            % needs a subject, electrodes and a quiet rig but no bank, no
            % schedule and no files. audio (optional) names the device and
            % channel mapping, as mabr.AudioSettings holds them:
            % .Device, .PlayerChannels, .RecorderChannels.
            %
            % Refused while a schedule is running or a run is still being
            % finalized from the ring -- a monitor lap resets the ring, and a
            % finalization reads it. Returns at once; the worker streams
            % laps of MonitorSeconds, re-armed as each ends (on_block_completed),
            % until stopMonitor. A worker error ends it (on_engine_error),
            % leaving the reason in MonitorError.
            if nargin < 2 || isempty(audio), audio = struct(); end
            if obj.Monitoring, return; end
            assert(~obj.FinalizePending,'mabr:ui:AcqController:finalizing', ...
                'The last run is still being finalized; try again in a moment.');
            assert(mabr.ui.ProgState.isTerminal(obj.State), ...
                'mabr:ui:AcqController:busy', ...
                'A schedule is running; the input monitor needs the device to itself.');

            fs = obj.Config.DACSampleRate;
            fl = obj.Config.frameLength;
            N  = min(round(obj.MonitorSeconds*fs),obj.Config.maxInputBufferLength);
            N  = max(fl,fl*floor(N/fl));
            % A plan with no presentations is silence on both columns: no
            % signal, and no timing pulse for anything downstream to take
            % for an onset.
            spec = struct('Plan',mabr.stim.PlayPlan({},{},[],[],[],N), ...
                'SampleRate',fs, ...
                'PlayerChannels',getdef(audio,'PlayerChannels',[1 2]), ...
                'RecorderChannels',getdef(audio,'RecorderChannels',[1 2]), ...
                'StimulationOnly',false);
            dev = getdef(audio,'Device','');
            if ~isempty(dev), spec.Device = dev; end
            % No device paces Test Mode: one frame per frame duration, as a
            % run gets (begin_current_run), so a lap takes as long as it says.
            if obj.Testing, spec.TestingFrameDelay = fl/fs; end

            obj.MonitorSpec   = spec;
            obj.MonitorWanted = true;
            obj.MonitorError  = '';
            obj.Monitoring    = true;
            obj.Engine.setRole('acquisition');
            obj.arm_monitor();
            mabr.log.vprintf(1,'Input monitor started (%s laps, nothing played, nothing saved).', ...
                durationWords(N/fs));
            notify(obj,'MonitorChanged');
        end

        function stopMonitor(obj,timeout)
            % Stop the input monitor and wait (bounded, default 3 s) for the
            % worker to say its lap is over, so whatever is prepared next --
            % the self-test, a run, a calibration borrowing the device -- is
            % not queued behind a block still streaming. A no-op when the
            % monitor is not running.
            if ~obj.Monitoring, return; end
            if nargin < 2 || isempty(timeout), timeout = 3; end
            obj.MonitorWanted = false;
            try
                obj.Engine.stop();
            catch me
                mabr.log.vprintf(1,1,'Input monitor: could not ask the worker to stop (%s).',me.message);
            end
            t0 = tic;
            while obj.Monitoring && toc(t0) < timeout
                pause(0.02);            % lets the engine's state callbacks run
            end
            if obj.Monitoring
                % The worker never answered. Nothing more can be done from
                % here than to stop claiming it is monitoring.
                mabr.log.vprintf(0,1,'Input monitor: the worker did not confirm the stop within %g s.',timeout);
                obj.end_monitor('');
            end
        end

        function S = inputSamples(obj,n)
            % The newest n samples of the RAW recorded signal, for a view of
            % the input itself (mabr.ui.SpectrumViewer) -- as the converter
            % delivered them, before the display filter and before the
            % amplifier gain is divided out (S.Gain says what it is, so the
            % view can refer them to the electrodes). Fewer than n when the
            % block holds fewer.
            %
            %   Samples     [m x 1] single, the newest last
            %   Head        the block's absolute sample the last one is
            %   Seq         the block (RingBuffer.BlockSeq); a new one is new data
            %   SampleRate  Hz (the DAC rate -- the ring is not decimated)
            %   Gain        AmplifierGain
            %   Source      'monitor'  the input monitor is streaming
            %               'run'      a schedule is under way (the ring holds
            %                          its run in progress, or the last one
            %                          until the next begins)
            %               'held'     nothing is streaming; the ring holds
            %                          the last thing that did
            %               'none'     nothing this controller streamed
            %   Testing     Test Mode: the input is the stimulus copied back
            %   Monitoring  the input monitor is running
            %   Note        why there is nothing, when there is nothing
            S = struct('Samples',zeros(0,1,'single'),'Head',0,'Seq',NaN, ...
                'SampleRate',obj.Config.DACSampleRate,'Gain',obj.AmplifierGain, ...
                'Source','none','Testing',obj.Testing,'Monitoring',obj.Monitoring, ...
                'Note',obj.MonitorError);
            if obj.SelfTestActive
                S.Note = 'Checking the timing loop-back…';
                return
            end
            inRun = any(obj.State == [mabr.ui.ProgState.PrepBlock, ...
                mabr.ui.ProgState.Acquire,mabr.ui.ProgState.BlockComplete, ...
                mabr.ui.ProgState.AdvanceBlock]);
            if obj.Monitoring
                S.Source = 'monitor';
            elseif inRun && ~isempty(obj.Schedule) && obj.Schedule.StimulationOnly
                S.Note = 'Stimulation only: nothing is recorded.';
                return
            elseif inRun && obj.HasRecorded
                S.Source = 'run';
            elseif obj.HasRecorded
                S.Source = 'held';
            else
                return
            end
            rb = obj.Engine.RingBuffer;
            % The worker may start a new block between reading the header and
            % reading the samples; a sequence that moved means the samples may
            % straddle the two, so read again (the PublishBuffer discipline).
            for attempt = 1:3
                seq  = rb.BlockSeq;
                head = rb.WriteHead;
                m    = min([n head rb.MaxLength]);
                x    = rb.readSignal(head-m+1,head);
                if rb.BlockSeq == seq, break; end
            end
            S.Samples = x;
            S.Head    = head;
            S.Seq     = seq;
        end

        function ctx = noteContext(obj)
            % Where the session is right now, for stamping a note taken at this
            % moment (mabr.data.SessionNotes.ContextFcn -- mabr.ui.App points
            % the store's here).
            %
            % Run and Sweep are left NaN unless a run is actually under way,
            % because that is the honest answer: a note typed between runs
            % belongs to no run, and stamping it with the last one -- or the
            % next -- would put it in the wrong place in the record. Sweep is
            % the count within the CURRENT run, the same number the Run panel's
            % readout shows, so "S0128" and the operator's screen agree.
            ctx = struct('Run',NaN,'NumRuns',NaN,'Sweep',NaN,'Running',false, ...
                         'State',char(obj.State));
            inRun = any(obj.State == [mabr.ui.ProgState.PrepBlock, ...
                                      mabr.ui.ProgState.Acquire]);
            if ~inRun || isempty(obj.Schedule) || obj.CurRun < 1, return; end
            ctx.Running = true;
            ctx.Run     = obj.CurRun;
            ctx.NumRuns = obj.Schedule.NumRuns;
            % No sweeps to count in stimulation-only mode -- nothing is
            % recorded, so the run index is the whole of the context.
            if ~obj.Schedule.StimulationOnly
                ctx.Sweep = obj.CurMetrics.numSweeps;
            end
        end

        function resetMetrics(obj)
            % Start the online analysis over: every analysis window drops the
            % conditions it holds (MetricsReset), the metrics worker drops the
            % session table they share, and windows opened from now on
            % backfill only from blocks finalized after this. Nothing else is
            % touched -- the Session keeps its blocks and every file stays as
            % written -- and the run in progress carries on, its finalized
            % block joining the fresh table when it lands.
            if ~isempty(obj.Session) && isvalid(obj.Session)
                obj.MetricsBase = obj.Session.NumBlocks;
            else
                obj.MetricsBase = 0;
            end
            if ~isempty(obj.Compute) && isvalid(obj.Compute)
                try
                    obj.Compute.clearConditions();
                catch me
                    mabr.log.vprintf(1,1,'Could not clear the metrics worker''s table: %s', ...
                        me.message);
                end
            end
            notify(obj,'MetricsReset');
        end

        function snap = liveSnapshot(obj)
            % The sweeps of the run CURRENTLY STREAMING, as of the last live
            % tick -- or [] when no run is. A pull, deliberately: the live
            % view is pushed at 20 Hz because it is drawing every sweep as it
            % lands, while an online-analysis window (mabr.ui.MetricPlot)
            % refreshes at 1 Hz or slower and there may be several of them, so
            % they read this when they are ready rather than being handed
            % copies twenty times a second.
            %
            % BUILT WHEN ASKED FOR. The snapshot is a copy of every sweep of
            % the run so far, so it is made here rather than on a timer, and
            % kept: a pull within AuxPeriod of the last one made -- or with
            % no sweep since -- gets that one, so however many windows ask,
            % the run is copied at most once per AuxPeriod. Only while the
            % run's sweeps are in this process (LiveLocal); with the DSP
            % worker doing the signal processing there are none here, this
            % is [], and the metrics worker serves the analysis windows.
            %
            % Fields:
            %   Run         index of the run in the schedule
            %   SampleRate  Hz of the sweeps (the ADC rate)
            %   Time        [1 x nSamples] seconds re onset; STARTS NEGATIVE,
            %               because the live path carries the pre-onset
            %               baseline as part of one contiguous segment
            %   Columns     [nSamples x nSweeps] volts, filtered by the
            %               display chain in force -- ONE SWEEP PER COLUMN,
            %               the orientation the pipeline caches them in and
            %               mabr.compute.ConditionStore.fromLive holds them in
            %   StimIndex   [1 x nSweeps] which stimulus evoked each sweep
            %   Bad         [1 x nSweeps] the artifact PREVIEW for each
            %   Stimuli     [1 x nStim] stimulus indices this run presents
            %   Labels      {1 x nStim} their IDs
            %
            % Nothing here is authoritative: the artifact verdict and the
            % filtering are previews of what finalization will decide (see
            % live_tick_body), which is exactly what makes them the right
            % thing to watch WHILE it happens.
            snap = [];
            if ~obj.LiveLocal, return; end
            stale = isempty(obj.LiveSnap) ...
                || (size(obj.LiveSnap.Columns,2) ~= obj.CurMetrics.numSweeps ...
                    && toc(obj.LiveClock) - obj.LiveSnapAt >= obj.AuxPeriod);
            if stale, obj.build_live_snapshot(); end
            snap = obj.LiveSnap;
        end

        function R = alignmentCheck(obj,F)
            % Hold the run that just finished against the run that was
            % planned, and say whether they are the same experiment.
            %
            % Two questions, and the second is only answerable in TEST MODE:
            %
            %   1. Are the recovered onsets where the plan put them? Pure
            %      arithmetic on two index vectors (mabr.metrics.alignment_
            %      report) -- meaningful on a rig too, where the offset is the
            %      loop-back latency and the JITTER around it is what must be
            %      zero. Asked after every recorded run.
            %
            %   2. Are the samples at each onset the stimulus the schedule
            %      assigned to it, sign included? Only in Test Mode, where the
            %      stimulus buffer is copied straight into the acquisition
            %      ring buffer (mabr.acq.worker_loop) so there IS a right
            %      answer to compare against -- what comes back through a real
            %      converter is not the waveform that went out, so on a rig
            %      this is skipped rather than failed.
            %
            % Together they are the whole of the correspondence every other
            % number rests on: the k-th recovered sweep is paired with the
            % k-th planned presentation everywhere downstream, so if these two
            % agree then the stimulus metadata saved beside a sweep really is
            % the stimulus that produced it.
            %
            % F is mabr.compute.Pipeline.finalize's output (from this process
            % or from the DSP worker -- the answer must not depend on which).
            %
            % The two halves are also callable apart: conclude_run computes
            % the report as soon as the run is finalized -- while the ring and
            % the device's report are still this run's -- and announces it
            % once the run's blocks have been announced.
            R = obj.alignment_compute(F);
            obj.alignment_announce(R);
        end

        function tf = canLoop(obj)
            % Whether Loop can hold this schedule: only when it presents one
            % condition per run -- a conventional strategy, or a custom one
            % whose runs do (mabr.stim.Schedule.isIntermixed asks the built
            % plan). Loop holds a CONDITION, and an intermixed run is every
            % condition at once; repeating one would repeat the session.
            % The same line canRepeat and the advance criterion draw.
            tf = ~isempty(obj.Schedule) && ~obj.Schedule.isIntermixed();
        end

        function tf = canRepeat(obj)
            % True once a blocked-strategy run has completed, so its stimulus
            % can be repeated with a fresh run appended to the plan (see
            % repeatLastBlock). Always false for an intermixed run: it has no
            % single stimulus to repeat, and LastRunStimulus is never set for
            % one (see on_block_completed).
            tf = ~isempty(obj.Schedule) && obj.LastRunStimulus > 0;
        end

        function repeatLastBlock(obj)
            % Append one more full run of the most recently completed block's
            % stimulus to the end of the plan -- the user-triggered "run this
            % again" (mabr.ui.App's Repeat button), as distinct from
            % mabr.stim.Schedule.appendMakeup, which recovers sweeps an
            % artifact took and is bounded by MakeupLimit.
            assert(obj.canRepeat(),'mabr:ui:AcqController:noRepeat', ...
                'Nothing to repeat yet -- available once a blocked-strategy run has completed.');
            n = obj.Schedule.repeatRun(obj.LastRunStimulus);
            mabr.log.vprintf(1,'User requested a repeat of stimulus %d (%d sweeps).', ...
                obj.LastRunStimulus,n);
            % When the engine is actively working through the plan it will
            % reach the newly appended run on its own -- the same mechanism
            % appendMakeup already relies on mid-schedule. Otherwise (the
            % schedule finished, or Abort halted it) nothing is left driving
            % Schedule.advance() forward, so kick it off here.
            if obj.State == mabr.ui.ProgState.Idle || obj.State == mabr.ui.ProgState.SchedComplete
                obj.stopMonitor();      % the run needs the device, as start() does
                obj.Schedule.resumeAt(obj.Schedule.NumRuns);
                obj.begin_current_run();
            end
        end
    end

    methods (Access = private)
        % --- Program flow ---------------------------------------------------
        function begin_current_run(obj)
            % An Advance belongs to the run it was pressed in. Cleared first,
            % before set_state below hands the event queue a chance to run
            % (the App's state handler flushes it), so a press landing then
            % is kept for this run rather than wiped.
            obj.AdvanceRequested = false;
            r = obj.Schedule.current();
            if isempty(r) || r == 0
                obj.set_state(mabr.ui.ProgState.SchedComplete);
                notify(obj,'ScheduleComplete');
                return
            end
            obj.set_state(mabr.ui.ProgState.PrepBlock);

            obj.CurMetrics = struct('numSweeps',0,'numArtifacts',0, ...
                                    'numClean',0,'corr',0);
            obj.LiveSnap  = [];
            obj.LiveLocal = false;  % liveSnapshot must not serve the last run
            obj.BlockStart = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            obj.RunStartTic = tic;
            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot), obj.LivePlot.reset(); end

            % Where the analysis stops reading after an onset, so the run's
            % closing silence is long enough for the last response to reach
            % the recording (mabr.stim.Schedule.trailPad). Every run, since
            % the window can change between them.
            obj.Schedule.ResponseWindow = max(0,obj.Window(2));
            spec = obj.Schedule.renderSpec(r);

            % In TESTING there is no audio device, so nothing throttles the
            % worker to the sample clock and the run would finish far faster
            % than the ISI implies. Pace it at one frame per frame-duration so
            % loopback presentation happens at the requested rate. An explicit
            % Schedule.TestingFrameDelay (the verification scripts set one)
            % still wins.
            if obj.Testing && spec.TestingFrameDelay <= 0
                spec.TestingFrameDelay = obj.Config.frameLength/spec.SampleRate;
            end

            obj.CurRun    = r;
            obj.CurSeq    = spec.StimulusIndex(:)';
            obj.CurPol    = spec.Polarity(:)';
            obj.CurOnsets = spec.ExpectedOnsets(:)';

            % 'stable', so an interleaved run's live panels sit in the order
            % the stimuli are actually presented in.
            obj.CurStim   = unique(obj.CurSeq,'stable');
            obj.CurLabels = arrayfun(@(u) obj.Stimuli.id(u),obj.CurStim, ...
                'UniformOutput',false);
            obj.CurParams = obj.stimParams(obj.CurStim);
            obj.send_stimulus_waves();

            % Tell the pipeline what this run's onsets belong to. Its cursor
            % starts over here too, so nothing from the last run can be
            % attributed to this one.
            obj.RunSerial = obj.RunSerial + 1;
            obj.Timing.reset(obj.CurRun,obj.LivePeriod,obj.LivePoll);
            info = struct('RunId',obj.RunSerial, ...
                'StimIndex',obj.CurSeq,'Stimuli',obj.CurStim, ...
                'Labels',{obj.CurLabels});
            obj.Pipeline.beginRun(info);
            % The workers get the same, plus the bank's metadata -- they
            % hold no StimulusSet, and the metrics worker names and places a
            % condition from its meta exactly as mabr.ui.MetricPlot would.
            % Held, not sent: they start the run at its Acquire, once the
            % ring holds it (see PendingRunStart).
            obj.PendingRunStart = [];
            if ~isempty(obj.Compute)
                info.Meta = arrayfun(@(u) obj.Stimuli.meta(u), ...
                    1:obj.Stimuli.numStimuli,'UniformOutput',false);
                obj.PendingRunStart = info;
            end

            % The live view's progress bar tracks this run's own presentation
            % count, which the schedule — not the advance criterion — fixes.
            p = obj.AdvanceParams;
            p.targetSweeps = numel(obj.CurSeq);
            obj.AdvanceParams = p;

            obj.Engine.prep(spec);
            obj.Engine.run();
        end

        function ok = verifyTimingLoop(obj)
            % One-time hardware check, run before the first real block of a
            % session: streams a few synthetic timing pulses (no signal)
            % through the actual Engine.prep/run path and confirms at least
            % one comes back on the timing input channel. Catches a broken or
            % mis-mapped loop-back cable -- "the most common rig problem" per
            % Troubleshooting.md -- at Start, instead of after a whole block
            % streams and finalize_run finds no onsets at all.
            %
            % Runs unconditionally, including in Testing mode: worker_loop's
            % loopback branch passes the timing column straight through, so
            % this trivially passes there too, exercising the identical code
            % path a real device would use.
            %
            % SelfTestActive suppresses on_engine_state/on_block_completed for
            % the duration, so this synthetic block never reaches ProgState,
            % the live timer, or finalize_run/Schedule/Session bookkeeping.
            % stream_block's own rb.reset() at the start of the next Run
            % discards this block's ring-buffer contents automatically, so
            % nothing here needs cleaning up afterward.
            fs       = obj.Config.DACSampleRate;
            nPulses  = 3;
            gap      = round(0.02*fs);      % 20 ms between pulses
            pulseLen = 8;                   % samples
            n        = (nPulses+1)*gap;

            sig = zeros(n,1,'single');
            tim = zeros(n,1,'single');
            for k = 1:nPulses
                i0 = (k-1)*gap + 1;
                tim(i0:i0+pulseLen-1) = 1;
            end

            spec = struct('PlayMatrix',[sig tim],'SampleRate',fs, ...
                'PlayerChannels',obj.Schedule.PlayerChannels, ...
                'RecorderChannels',obj.Schedule.RecorderChannels);
            % Test the actual selected ASIO device, not whatever
            % audioPlayerRecorder opens by default -- renderSpec applies the
            % same rule (mabr.stim.Schedule.renderSpec).
            if ~isempty(obj.Schedule.Device), spec.Device = obj.Schedule.Device; end

            obj.SelfTestActive = true;
            n0 = obj.CompletedCount;
            obj.Engine.prep(spec);
            obj.Engine.run();

            % THIS block's completion, not the engine reading Completed: it
            % already does after any earlier block (a stopped monitor lap, a
            % finished run), which would read the ring before this one was in
            % it -- and pass or fail on somebody else's samples.
            t0 = tic;
            while obj.CompletedCount == n0 && toc(t0) < 5
                pause(0.02);
            end
            obj.SelfTestActive = false;

            if obj.CompletedCount == n0
                ok = false;
                return
            end
            [~,recTiming] = obj.Engine.RingBuffer.readBlock();
            onsets = mabr.metrics.find_timing_onsets(recTiming, ...
                round(mabr.Config.OnsetShadow*fs),mabr.Config.OnsetThreshold, ...
                round(mabr.Config.OnsetRearm*fs));
            ok = ~isempty(onsets);
        end

        function on_engine_state(obj,e)
            if obj.SelfTestActive, return; end   % see verifyTimingLoop
            if obj.Monitoring, return; end       % see startMonitor
            switch e.State
                case mabr.acq.State.Acquire
                    % The ring now holds something this controller streamed.
                    % Nothing, in stimulation only: that mode writes no input.
                    if ~obj.Schedule.StimulationOnly, obj.HasRecorded = true; end
                    % The worker resets the ring and THEN reports Acquire, so
                    % from here the ring holds this run and nothing else: the
                    % moment the compute workers can safely start on it. Once
                    % per run -- a Resume reports Acquire again. Before the
                    % state change, so a listener to it sees the workers
                    % already on this run.
                    if ~isempty(obj.PendingRunStart)
                        info = obj.PendingRunStart;
                        obj.PendingRunStart = [];
                        if ~isempty(obj.Compute), obj.Compute.runStart(info); end
                    end
                    obj.set_state(mabr.ui.ProgState.Acquire);
                    % Nothing is recorded in stimulation-only mode, so there
                    % is nothing for the live timer to read out of the ring
                    % buffer; run progress comes from the state transitions.
                    if ~obj.Schedule.StimulationOnly
                        obj.start_timer();
                    end
                % Ready / Paused / Idle need no program-state change here
            end
        end

        function on_block_completed(obj)
            obj.CompletedCount = obj.CompletedCount + 1;
            if obj.SelfTestActive, return; end   % see verifyTimingLoop
            if obj.Monitoring
                % A monitor lap: nothing to finalize. Another lap while one is
                % wanted and this one ran its length; anything else -- a Stop,
                % from stopMonitor or anybody -- is the end of the monitor.
                if obj.MonitorWanted && strcmp(obj.Engine.LastStream.reason,'completed')
                    try
                        obj.arm_monitor();
                    catch me
                        mabr.log.vprintf(0,1,'Input monitor could not start its next lap: %s',me.message);
                        obj.end_monitor(me.message);
                    end
                else
                    obj.end_monitor('');
                end
                return
            end
            obj.stop_timer();
            obj.report_live_timing();
            % Drop the live snapshot BEFORE anything is finalized: from here
            % the run's sweeps arrive as a Block, and a puller that still saw
            % the partial copy would count them twice.
            obj.LiveSnap = [];
            obj.set_state(mabr.ui.ProgState.BlockComplete);

            % Remember what can be repeated -- only meaningful for a run that
            % held a single stimulus. CurSeq/CurRun are about to be overwritten
            % by begin_current_run() for whatever comes next, so this is the
            % last moment they still describe the run that just finished.
            if ~obj.Schedule.isIntermixed() && ~isempty(obj.CurSeq)
                obj.LastRunStimulus = obj.CurSeq(1);
            end

            % Stimulation only records nothing, so there is nothing to
            % finalize: no sweeps to extract, no Block to build, no .abr to
            % write, and nothing to announce to a viewer. What it does have is
            % the sequence it just played, which is written out instead. The
            % schedule-advance tail below runs either way -- the plan must
            % drive itself to completion exactly as it would with a recording
            % attached.
            if obj.Schedule.StimulationOnly
                try
                    file = obj.log_stim_run();
                    if ~isempty(file)
                        notify(obj,'BlockSaved',mabr.ui.ProgStateEventData( ...
                            obj.State,struct('file',file)));
                    end
                catch me
                    mabr.log.vprintf(0,1,'Stimulation log failed: %s',me.message);
                end
                obj.loop_run(obj.CurRun);
                obj.after_finalize();
                return
            end

            % A recorded run. The finalization DSP -- reading the ring,
            % resampling the whole block, filtering, judging -- goes to the
            % DSP worker when there is one, and this returns at once with
            % ProgState left in BlockComplete: the tail runs when the reply
            % lands (on_finalized) or the timeout fires (on_finalize_timeout).
            % The GUI stays responsive across the block boundary either way.
            % Without a worker the same work is done here, now.
            if obj.usingWorkerDSP() && obj.Compute.finalize(obj.RunSerial,obj.CurSeq)
                obj.FinalizePending = true;
                obj.FinalizeRunId   = obj.RunSerial;
                obj.arm_finalize_timeout();
                return
            end
            obj.finalize_here();
        end

        function finalize_here(obj)
            % Finalize the run in this process, from the ring buffer, and move
            % the plan on (conclude_run). A DSP failure still moves it on: a
            % run whose recording cannot be read is lost either way, and the
            % schedule must not stall on it.
            F = [];
            try
                F = obj.finalize_run();
            catch me
                mabr.log.vprintf(0,1,'Finalize failed: %s',me.message);
            end
            obj.conclude_run(F);
        end

        function conclude_run(obj,F)
            % The tail of every recorded run once its finalization DSP is done
            % (F, from this process or the DSP worker; [] if that failed):
            % credit the run, move the plan on, and build and announce its
            % blocks -- in THAT order whenever the plan goes on.
            %
            % Nothing about the next run depends on this run's Blocks: its
            % presentations are credited from F (credit_run), any make-up is
            % appended before advance() looks at the plan, and the alignment
            % verdict is COMPUTED now -- it reads the ring and the device's
            % report, both of which the next run's Prep/Run replace -- and only
            % announced later. So the next run is already streaming while
            % this one's Blocks are assembled, saved, and handed to the
            % viewers, instead of the rig sitting silent through all of it
            % (with the organizer, analysis windows and files, the part that
            % grows over a session).
            %
            % The LAST run of a plan, and a halt, keep the old order, so
            % ScheduleComplete (and Idle after an abort) still means every
            % Block is built and every file written.
            ctx = obj.run_context();
            R   = [];
            if ~isempty(F)
                try
                    R = obj.alignment_compute(F);
                catch me
                    % A diagnostic must never be the reason a run's data is lost.
                    mabr.log.vprintf(1,1,'Alignment check failed: %s',me.message);
                end
                obj.credit_run(F,ctx);
            end
            % Before the plan is asked whether it is complete: a looped run
            % is never the last one, so its next pass streams while this
            % pass's blocks are assembled, like any other next run.
            obj.loop_run(ctx.CurRun);
            goOn = ~obj.HaltAfterBlock && ~obj.Schedule.isComplete();
            if goOn, obj.after_finalize(); end
            if ~isempty(F)
                try
                    [files,blocks] = obj.assemble_blocks(F,ctx);
                    obj.emit_blocks(files,blocks,R);
                catch me
                    mabr.log.vprintf(0,1,'Finalize failed: %s',me.message);
                end
            end
            if ~goOn, obj.after_finalize(); end
        end

        function ctx = run_context(obj)
            % What assembling a run's Blocks needs to know about the run
            % itself, taken before begin_current_run overwrites it for the
            % next one (see conclude_run).
            ctx = struct('CurRun',obj.CurRun,'CurSeq',obj.CurSeq, ...
                         'CurPol',obj.CurPol,'CurOnsets',obj.CurOnsets, ...
                         'BlockStart',obj.BlockStart);
        end

        function credit_run(obj,F,ctx)
            % Book what the run presented into the schedule -- and, if asked,
            % append a make-up for what the artifact policy rejected -- from
            % the finalization output alone, so it can happen before the
            % Blocks exist. counts(u) is every sweep recovered for stimulus u,
            % lost(u) those the policy flagged (the same numbers the Blocks
            % will carry: Count and nnz(Flags) are what Recording.NumSweeps
            % and NumArtifacts come from). A run with no onsets is credited
            % nothing, as it always was.
            if isempty(F) || F.NumOnsets < 1, return; end
            n      = obj.Stimuli.numStimuli;
            counts = zeros(1,n);
            lost   = zeros(1,n);
            for i = 1:numel(F.Parts)
                u         = F.Parts(i).Stimulus;
                counts(u) = F.Parts(i).Count;
                lost(u)   = nnz(F.Parts(i).Flags);
            end
            obj.Schedule.recordRun(ctx.CurRun,counts);
            % Win back what the artifacts cost, if asked to. The schedule
            % appends the make-up to the end of the plan and caps it, so this
            % converges even when the rejection rate stays high.
            if obj.Artifacts.Repeat && any(lost > 0)
                obj.Schedule.appendMakeup(lost);
            end
        end

        function emit_blocks(obj,files,blocks,R)
            % Announce the blocks themselves first: a viewer should get the
            % data whether or not the session is writing files.
            for i = 1:numel(blocks)
                notify(obj,'BlockReady',mabr.ui.ProgStateEventData( ...
                    obj.State,struct('block',blocks(i))));
            end
            for i = 1:numel(files)
                notify(obj,'BlockSaved',mabr.ui.ProgStateEventData( ...
                    obj.State,struct('file',files{i})));
            end
            % The alignment verdict goes LAST. Both of the events above write
            % the status line ("Saved ...abr"), so a verdict raised before
            % them -- above all a MISALIGNED one -- would be on screen for a
            % few milliseconds and then gone. It was computed when the run
            % was concluded (alignment_compute), from the ring and the device
            % report as they stood then, so it describes the run these blocks
            % came from even when the next run is already streaming.
            if nargin >= 4 && ~isempty(R)
                obj.alignment_announce(R);
            end
        end

        function loop_run(obj,r)
            % Hold the plan on run r, which has just ended, while Loop is set:
            % insert another pass of it directly after it (mabr.stim.Schedule.
            % loopRun), so the advance() that follows lands on the pass and
            % the rest of the plan waits behind it. Called at the end of every
            % run, recorded or stimulation-only, after the run is credited and
            % BEFORE the plan is advanced.
            %
            % A run the advance criterion stopped is looped: the criterion
            % decides when a pass has enough, not when to leave the run. A
            % run the user ended with Advance is not -- that is an instruction
            % to move on, and with Loop still set the next run is held in its
            % turn -- and neither is one ended by Abort.
            %
            % Never fatal: a loop that cannot be extended leaves the plan to
            % go on as though Loop were clear, rather than stalling it.
            if ~obj.Loop || obj.HaltAfterBlock || obj.AdvanceRequested, return; end
            if isempty(obj.Schedule) || r < 1 || r > obj.Schedule.NumRuns, return; end
            if ~obj.canLoop()
                % Set by a script, not the GUI (which greys Loop out under an
                % intermixed strategy): said rather than obeyed or thrown.
                mabr.log.vprintf(1,['Loop is set, but this schedule presents several ' ...
                    'conditions in a run (%s); it only holds a plan of one condition ' ...
                    'per run, so the plan goes on.'],obj.Schedule.strategyLabel());
                return
            end
            try
                obj.Schedule.loopRun(r);
            catch me
                mabr.log.vprintf(0,1,'Could not loop run %d: %s',r,me.message);
            end
        end

        function after_finalize(obj)
            % The schedule-advance tail, once a run's results are in:
            % halt if asked, else move the plan on to the next run or to
            % completion. Shared by every finalization path.
            if obj.HaltAfterBlock
                obj.set_state(mabr.ui.ProgState.Idle);
                return
            end

            obj.set_state(mabr.ui.ProgState.AdvanceBlock);
            nextRun = obj.Schedule.advance();
            if isempty(nextRun)
                obj.set_state(mabr.ui.ProgState.SchedComplete);
                notify(obj,'ScheduleComplete');
            else
                obj.begin_current_run();
            end
        end

        function on_finalized(obj,e)
            % The DSP worker's reply to Finalize. A reply nobody is waiting
            % for -- the timeout already finalized the run here, or it
            % answers a manual request -- is ignored.
            msg = e.Data;
            if ~obj.FinalizePending || msg.runId ~= obj.FinalizeRunId, return; end
            obj.FinalizePending = false;
            obj.disarm_finalize_timeout();
            if ~isempty(msg.error) || isempty(msg.result)
                mabr.log.vprintf(0,1,['The DSP worker could not finalize the run (%s); ' ...
                    'finalizing here.'],msg.error);
                obj.finalize_here();
            else
                obj.conclude_run(msg.result);
            end
        end

        function on_finalize_timeout(obj)
            % No reply in time: the worker is suspect, the ring is intact,
            % and the run is finalized here from it.
            if ~obj.FinalizePending, return; end
            obj.FinalizePending = false;
            mabr.log.vprintf(0,1,['The DSP worker did not finalize the run in time; ' ...
                'finalizing here.']);
            if ~isempty(obj.Compute)
                try, obj.Compute.reportStall('dsp','finalization timed out'); end %#ok<TRYNC>
            end
            obj.finalize_here();
        end

        function arm_finalize_timeout(obj)
            obj.disarm_finalize_timeout();
            % The allowance grows with the block: a five-minute run is a
            % resample of ~60 M samples, not a 30 s job on a slow machine.
            delay = obj.FinalizeTimeout + obj.Engine.head()/2e6;
            delay = round(max(0.1,delay)*1000)/1000;     % timer wants whole ms
            obj.FinalizeTimer = timer('Tag','MABR_Finalize', ...
                'ExecutionMode','singleShot','StartDelay',delay, ...
                'TimerFcn',@(~,~) obj.on_finalize_timeout());
            start(obj.FinalizeTimer);
        end

        function disarm_finalize_timeout(obj)
            t = obj.FinalizeTimer;
            obj.FinalizeTimer = [];
            if isempty(t) || ~isvalid(t), return; end
            try, stop(t);   end %#ok<TRYNC>
            try, delete(t); end %#ok<TRYNC>
        end

        function on_engine_error(obj,e)
            if obj.Monitoring
                % The monitor's own failure -- most often a device that would
                % not open. No schedule is running, so there is no program
                % state to put in Error: the monitor ends and says why, and
                % the worker (which fails the command, not itself) is ready
                % for whatever comes next.
                mabr.log.vprintf(0,1,'Input monitor stopped [%s]: %s',e.Identifier,e.Message);
                obj.end_monitor(e.Message);
                return
            end
            obj.stop_timer();
            obj.set_state(mabr.ui.ProgState.Error);
            mabr.log.vprintf(0,1,'Acquisition error [%s]: %s',e.Identifier,e.Message);
        end

        % --- Live view ------------------------------------------------------
        function on_live_tick(obj)
            % Every poll lands here; most of them only look at the clock. A
            % frame is due LivePeriod after the last one BEGAN -- less half a
            % poll, so a poll landing just short of it does not push the
            % frame a whole poll later. A due poll that finds nothing new (no
            % sweep yet, or nothing the DSP worker has published since) is
            % not a frame: the next poll asks again, and LiveTiming counts the
            % time spent waiting rather than logging it as a tick.
            %
            % Wrapped so a transient error never kills the live-view timer;
            % a failing tick is paced like a frame, so a persistent error is
            % reported at the frame rate rather than every poll. The timing
            % brackets the whole frame, errors included, so every frame is
            % counted and the gaps between them are real.
            t0 = toc(obj.LiveClock);
            if t0 - obj.LastFrameStart < obj.LivePeriod - obj.LivePoll/2
                return
            end
            obj.Timing.beginTick();
            fresh = true;
            try
                fresh = obj.live_tick_body();
            catch me
                mabr.log.vprintf(2,1,'Live tick error: %s',me.message);
            end
            if fresh
                obj.LastFrameStart = t0;
                obj.Timing.endTick(obj.CurMetrics.numSweeps);
            else
                obj.Timing.noData();
            end
        end

        function fresh = live_tick_body(obj)
            % One step of the pipeline: extract whatever sweeps have completed,
            % filter and judge the new ones, correlate. [] until a sweep exists.
            % Everything below only reads what it produced -- the traces, the
            % correlation and the artifact preview all come off the FILTERED
            % sweeps, and only the display path sees the chain: the ring
            % buffer keeps the raw samples, and it is the raw samples
            % finalization reads and io writes. The artifact flags are a
            % PREVIEW of the verdict finalization will record, under the same
            % policy and the same detector (see mabr.compute.Pipeline).
            %
            % Where the numbers come from is decided every tick: the DSP
            % worker while it is up, this controller's own pipeline
            % otherwise. Both produce the same struct, so nothing below
            % cares -- and a worker that dies mid-run is covered on the very
            % next tick, since the pipeline here has been following the run
            % too and re-extracts from the ring, which still holds it.
            %
            % fresh = false when there was nothing to draw from, which is
            % what tells on_live_tick the poll was not a frame.
            %
            % LiveLocal says which it was, for liveSnapshot: the sweeps are
            % in this process only while its own pipeline is being stepped.
            % With the worker doing the DSP there is no sweep matrix here --
            % the metrics worker serves the analysis windows then.
            fresh  = false;
            tStats = tic;
            if obj.usingWorkerDSP()
                obj.LiveLocal = false;
                [stats,changed] = obj.Compute.live();
                obj.Timing.stats(toc(tStats),'worker');
                % Nothing new since the last tick is nothing to do: the
                % whole tick then costs one word read from the memory map.
                if isempty(stats) || ~changed || stats.NumSweeps < 1, return; end
            else
                stats = obj.Pipeline.step(obj.Engine.RingBuffer);
                obj.Timing.stats(toc(tStats),'local');
                if isempty(stats), return; end
                obj.LiveLocal = true;
            end
            fresh = true;
            R = stats.Corr;

            obj.CurMetrics.numSweeps    = stats.NumSweeps;
            obj.CurMetrics.numArtifacts = stats.NumArtifacts;
            obj.CurMetrics.numClean     = stats.NumClean;
            obj.CurMetrics.corr         = R;

            % The view is fed statistics, not sweeps: the latest sweep, the
            % per-condition means and spreads over the baseline and the
            % response as one unbroken segment (the view's time base starts
            % BEFORE the onset, and pre-onset samples are the only thing that
            % can fill it), and the counts.
            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot)
                info        = obj.live_info(stats.NumSweeps);
                info.target = obj.AdvanceParams.targetSweeps;
                tRender = tic;
                obj.LivePlot.updateStats(stats,info);
                obj.Timing.render(toc(tRender),obj.LivePlot.RenderTiming);
            end

            % Online advance: stop the run early if the criterion is met. Only
            % meaningful when the run holds a single stimulus — pooling an
            % intermixed run's sweeps would compare different conditions, and
            % stopping it would truncate whichever stimuli fell last in the
            % sequence. Those runs play out in full.
            if obj.State == mabr.ui.ProgState.Acquire ...
                    && ~obj.Schedule.isIntermixed() && obj.advance_met()
                mabr.log.vprintf(1,'Advance criterion met at %d sweeps (r=%.3f); stopping run', ...
                    obj.CurMetrics.numSweeps,R);
                obj.Engine.stop();
            end
        end

        function on_aux_tick(obj)
            % The low-priority half of the live path: tell everyone whose
            % numbers just moved. Nothing here is recomputed -- the fast tick
            % already did the sweep extraction, filtering and artifact
            % preview -- and nothing is copied: the analysis windows' snapshot
            % is built when one of them asks (liveSnapshot).
            tAux = tic;
            try
                obj.aux_tick_body();
            catch me
                % A failing progress bar must not take the acquisition with
                % it, exactly as on_live_tick treats the live view.
                mabr.log.vprintf(1,'Aux view tick failed: %s',me.message);
            end
            % Includes every MetricsUpdated listener (the Run panel, the
            % progress monitor), and says whether it ran from INSIDE a live
            % tick -- i.e. from the live render's drawnow.
            obj.Timing.aux(toc(tAux));
        end

        function report_live_timing(obj)
            % Summarize the run's live-view timing (mabr.ui.LiveTiming) into
            % LastLiveTiming and the log. The full breakdown goes out at
            % level 2 (always in the daily file, whose gate defaults to Inf);
            % a run whose view fell well short of the timer's rate also gets
            % one level-1 line, so the operator sees it without turning the
            % console up. Not red: it is a performance note, not a fault in
            % the data.
            try
                if isempty(obj.Timing) || obj.Timing.RunId == 0 ...
                        || isempty(obj.Timing.Start)
                    return
                end
                S = obj.Timing.summary();
                obj.LastLiveTiming = S;
                mabr.log.vprintf(2,'%s',S.Text);
                if S.Drawn > 2 && S.RealizedHz < 0.5*S.TargetHz
                    mabr.log.vprintf(1, ...
                        'Live view drew at %.1f Hz (target %.0f Hz) in run %d: %s. See LastLiveTiming.Text.', ...
                        S.RealizedHz,S.TargetHz,S.RunId,S.Verdict);
                end
            catch me
                mabr.log.vprintf(2,'Live timing report failed: %s',me.message);
            end
        end

        function aux_tick_body(obj)
            % The tally and the Run panel ride this whichever process did
            % the DSP: nothing to say until the first sweep has been counted.
            if obj.CurMetrics.numSweeps < 1, return; end
            notify(obj,'MetricsUpdated', ...
                mabr.ui.ProgStateEventData(obj.State,obj.CurMetrics));
        end

        function build_live_snapshot(obj)
            % The run so far as liveSnapshot hands it over: the pipeline's
            % sweeps as they are cached, one per column (see
            % mabr.compute.Pipeline.columns), with the stimulus the plan put
            % behind each -- the same pairing finalization de-interleaves by.
            S = obj.Pipeline.columns();
            obj.LiveSnap = struct('Run',obj.CurRun, ...
                'SampleRate',obj.Config.ADCSampleRate, ...
                'Time',S.t,'Columns',S.Y, ...
                'StimIndex',obj.CurSeq(1:min(S.n,numel(obj.CurSeq))), ...
                'Bad',S.bad(:)','Stimuli',obj.CurStim,'Labels',{obj.CurLabels});
            obj.LiveSnapAt = toc(obj.LiveClock);
        end

        function apply_aux_period(obj)
            % Period is read-only on a running timer, so retuning means a stop
            % and a start. Guarded on the timer existing because the property
            % can be assigned before the constructor has built it.
            if isempty(obj.AuxTimer) || ~isvalid(obj.AuxTimer), return; end
            wasRunning = strcmp(obj.AuxTimer.Running,'on');
            if wasRunning, stop(obj.AuxTimer); end
            obj.AuxTimer.Period = obj.AuxPeriod;
            if wasRunning, start(obj.AuxTimer); end
        end

        function info = live_info(obj,nSweeps)
            % Which stimulus evoked each sweep so far, and the run's full
            % stimulus list. The k-th recorded onset is the k-th presentation
            % the schedule ordered -- the same pairing finalize_run makes when
            % it de-interleaves the run, which is why the live means and the
            % saved blocks agree about what belongs to what.
            n = min(nSweeps,numel(obj.CurSeq));
            info = struct('StimIndex',obj.CurSeq(1:n), ...
                          'Stimuli',  obj.CurStim, ...
                          'Labels',   {obj.CurLabels});
            % Assigned rather than passed to struct(): a struct field value is
            % fine there, but only a cell is expanded, so keeping the two
            % kinds apart is one less thing to get subtly wrong.
            info.Params = obj.CurParams;
            % Whether this run pools several conditions. The live view drops
            % its onset-contrast bar when it does, for the same reason the
            % advance criterion below is not evaluated: the metric watches one
            % condition's average converge, and an intermixed run has no such
            % average. Answered from the strategy rather than left to the view
            % to infer, so a blocked run that happens to have reached only one
            % of its stimuli is still called blocked. Left out entirely with no schedule to ask, which is the view's
            % cue to fall back on the run's own stimulus count.
            if ~isempty(obj.Schedule)
                info.Intermixed = obj.Schedule.isIntermixed();
            end
        end

        function send_stimulus_waves(obj)
            % The waveform behind each of this run's conditions, for the live
            % view's Show stimulus waveform option. Once per run rather than
            % in live_info: the view compares what it is handed with what it
            % drew last on every frame, and a run's waveforms do not change
            % under it. The samples are the bank's own (single, at the DAC
            % rate); the view crops, scales and thins them to what it draws.
            % Never fatal -- a view without it is a view without a picture
            % behind its traces, not a run without a recording.
            if isempty(obj.LivePlot) || ~isvalid(obj.LivePlot), return; end
            try
                sig = arrayfun(@(u) obj.Stimuli.signal(u),obj.CurStim, ...
                    'UniformOutput',false);
                obj.LivePlot.setStimulusWaves(obj.CurStim,obj.Stimuli.SampleRate,sig);
            catch me
                mabr.log.vprintf(2,'Stimulus waveforms unavailable for the live view: %s', ...
                    me.message);
            end
        end

        function P = stimParams(obj,idx)
            % The parameter table for this run's stimuli, for the live view.
            %
            % Tabulated over the whole BANK and then cut down to this run's
            % rows, rather than tabulated over the run: which parameters are
            % informative is a property of the EXPERIMENT, not of one run. A
            % blocked run holds a single condition and therefore varies
            % nothing, and a view that dropped every parameter for that reason
            % would leave the operator's own dimensions off the one label that
            % says what is being acquired. `Varying` travels with the values so
            % the view uses the bank's answer instead of re-deriving a run's.
            %
            % Never fatal: a bank whose extras cannot be tabulated costs the
            % view its parameter labels, not the run its acquisition.
            P = struct('Names',{{}},'Values',zeros(numel(idx),0), ...
                       'Varying',false(1,0),'Units',{{}});
            try
                if ~isempty(obj.Stimuli) && isvalid(obj.Stimuli)
                    P        = obj.Stimuli.paramTable();
                    P.Values = P.Values(idx,:);
                    P.IDs    = P.IDs(idx);
                end
            catch me
                mabr.log.vprintf(2,'Stimulus parameters unavailable for the live view: %s', ...
                    me.message);
            end
        end

        function configure_pipeline(obj)
            % Hand the pipeline the window and the two policies. Called from
            % every setter that changes one -- so the next tick, and the next
            % finalization, run under it -- and at construction, since
            % property defaults bypass the setters. The pipeline keeps what
            % has not changed, so this costs nothing when nothing has.
            if isempty(obj.Pipeline), return; end
            obj.Pipeline.configure(obj.Window,obj.Filters,obj.Artifacts, ...
                obj.AmplifierGain);
            % And the workers', so every process agrees about what a sweep is.
            if ~isempty(obj.Compute)
                obj.Compute.configure(obj.Config.DACSampleRate,obj.Window, ...
                    obj.Filters,obj.Artifacts,obj.AmplifierGain);
            end
            obj.caption_live_plot();
        end

        function on_compute_error(obj,e)
            % A compute worker's error costs its acceleration, never the
            % acquisition: log it and carry on in-process.
            mabr.log.vprintf(0,1,'Compute worker (%s) error: %s',e.Role, ...
                e.Data.message);
        end

        function caption_live_plot(obj)
            % Keep the live view's caption honest about what it is showing:
            % the chain as the pipeline actually designed it, which is the
            % unfiltered fallback if the requested one could not be realized.
            if isempty(obj.LivePlot) || ~isvalid(obj.LivePlot), return; end
            if isempty(obj.Pipeline), return; end
            obj.LivePlot.setFilterText(obj.Pipeline.LiveFilter.describe());
        end

        function tf = advance_met(obj)
            % Build the canonical context (mabr.stim.advance.context is the
            % authoritative field list) from the user's parameters plus the
            % current live metrics, and hand it to whatever criterion is set
            % -- num_sweeps, corr_threshold, or a custom function the user
            % selected in the GUI. numSweeps is the CLEAN count, since that is
            % what the average is built from: a criterion asking for 512
            % sweeps, or for a correlation over at least minSweeps of them,
            % means clean ones.
            live = struct( ...
                'numSweeps',     obj.CurMetrics.numClean, ...
                'numTotal',      obj.CurMetrics.numSweeps, ...
                'numArtifacts',  obj.CurMetrics.numArtifacts, ...
                'corr',          obj.CurMetrics.corr, ...
                'elapsedSeconds',obj.run_elapsed());
            ctx = mabr.stim.advance.context(obj.AdvanceParams,live);
            tf  = obj.AdvanceFcn(ctx);
        end

        function s = run_elapsed(obj)
            % Seconds since the current run began streaming, for a criterion
            % that wants a time budget. 0 before the first run of a session.
            if obj.RunStartTic == 0, s = 0; else, s = toc(obj.RunStartTic); end
        end

        % --- Finalization / save -------------------------------------------
        function d = deviceReport(obj)
            % What the audio device said about the run that just streamed, in
            % the shape mabr.metrics.alignment_report takes: so a MISALIGNED
            % verdict can name the underrun that stepped the offset instead of
            % leaving the operator to find "# Underruns" in the log. Only ever
            % read AFTER the run (the worker reports it once, before its
            % Completed state), and it belongs to this run because
            % Engine.prep clears it and nothing preps again before
            % emit_blocks has announced the verdict.
            d = struct('SampleRate',obj.Config.DACSampleRate, ...
                'Underruns',0,'Overruns',0,'UnderrunAt',zeros(1,0),'OverrunAt',zeros(1,0));
            s = obj.Engine.LastStream;
            if isfield(s,'underruns')
                d.Underruns  = s.underruns;
                d.Overruns   = s.overruns;
                d.UnderrunAt = s.underrunAt;
                d.OverrunAt  = s.overrunAt;
            end
        end

        function R = alignment_compute(obj,F)
            % alignmentCheck's verdict, without announcing it. Reads CurOnsets,
            % CurSeq/CurPol (Test Mode), the ring (Test Mode) and the device's
            % report -- everything the next run replaces -- so it must run
            % before that run is begun (see conclude_run).
            recovered = zeros(1,0);
            if isstruct(F) && isfield(F,'OnsetsAll'), recovered = F.OnsetsAll; end

            % How much departure from a constant offset is allowed before the
            % run is called misaligned, and it is not the same question in the
            % two modes.
            %
            % In TEST MODE the answer is zero. Nothing is being measured: the
            % onsets came off the very timing channel the plan rendered, with
            % no converter in between, so one sample of drift is a defect in
            % the plan, the render, the ring buffer or the extraction.
            %
            % On a RIG it is 50 us, deliberately the same line
            % verify_timing_loopback draws (its MaxJitter default) so MABR and
            % its own rig diagnostic cannot disagree about whether a rig is
            % healthy. Zero would be wrong here and worse than no check at
            % all: a red warning that fires on every ordinary run is one the
            % operator learns to ignore, which is exactly how the run that
            % genuinely is misaligned gets ignored with it.
            %
            % For the same reason a rig may also STEP its offset by up to one
            % USB microframe (125 us: 24 samples at 192 kHz), give or take
            % that jitter. A USB audio device slips its output by exactly that
            % now and then mid-stream, moving every later onset AND its
            % response together, so every sweep is still paired with its own
            % presentation. It used to be flagged MISALIGNED all the same.
            % Anything bigger -- an underrun's audio frame, or the whole
            % interval a spurious or missing pulse shifts the pairing by --
            % still is. Test Mode allows no step at all.
            if obj.Testing
                tol     = 0;
                stepTol = 0;
            else
                fs      = obj.Config.DACSampleRate;
                tol     = max(1,round(50e-6*fs));
                stepTol = round(125e-6*fs) + tol;
            end
            R = mabr.metrics.alignment_report(obj.CurOnsets,recovered,tol, ...
                obj.deviceReport(),stepTol);
            R.Tolerance = tol;
            % The waveform fields exist in EVERY report, Test Mode or not, so
            % a consumer reads one shape of struct rather than testing for
            % half of it: NaN/0/false is "not compared here", which is the
            % honest answer on a rig and a different thing from "compared and
            % failed".
            R.Run            = obj.CurRun;
            R.TestMode       = obj.Testing;
            R.MaxError       = NaN;
            R.NumWaveforms   = 0;
            R.WaveformsMatch = false;
            if obj.Testing
                R = obj.compare_waveforms(R,recovered);
            end
        end

        function alignment_announce(obj,R)
            % Record, log and raise a verdict alignment_compute reached.
            obj.LastAlignment = R;
            if R.Aligned
                mabr.log.vprintf(1,'Alignment: %s',R.Summary);
            else
                % Level 0 in red: a run whose sweeps are attributed to the
                % wrong conditions is not a warning, it is data that must not
                % be believed -- and the operator has to hear that whether or
                % not they were watching the status line at the time.
                mabr.log.vprintf(0,1,'Alignment: %s',R.Summary);
            end
            notify(obj,'AlignmentChecked',mabr.ui.ProgStateEventData( ...
                obj.State,struct('report',R)));
        end

        function R = compare_waveforms(obj,R,recovered)
            % The half of alignmentCheck that only TEST MODE makes answerable:
            % the samples sitting at each recovered onset must BE the stimulus
            % the schedule assigned to that presentation, times the polarity
            % it assigned. In Test Mode the stimulus buffer is copied straight
            % into the acquisition ring buffer, so there is a right answer to
            % hold them against; on a rig there is not, and this is skipped
            % rather than failed (what returns through a converter is not the
            % waveform that went out).
            %
            % This is the check that catches the failures the onset arithmetic
            % cannot see: a plan whose waveforms are rendered in one order and
            % labelled in another, or a polarity applied to the wrong
            % presentation. Both leave every onset exactly where it belongs.
            %
            % The tolerance is deliberately loose. Loopback adds ~1e-6 of
            % dither (mabr.acq.worker_loop) and single precision costs another
            % ~1e-7 on a full-scale sample, while a presentation attributed to
            % the wrong stimulus is wrong by order 1 -- so anything between
            % those two settles it, and picking the loose end means this can
            % never fail over arithmetic noise.
            tol = 1e-3;

            if R.NumCompared < 1 || isempty(obj.Stimuli) || isempty(obj.CurSeq)
                return
            end

            rb   = obj.Engine.RingBuffer;
            head = rb.WriteHead;
            n    = min([R.NumCompared numel(obj.CurSeq) numel(obj.CurPol)]);
            worst = 0; worstK = 0; checked = 0;
            for k = 1:n
                w  = double(obj.Stimuli.signal(obj.CurSeq(k)));
                w  = w(:);
                i0 = recovered(k);
                % A run stopped mid-presentation leaves its last waveform
                % half-written. Skipping it is right: the samples that ARE
                % there are not evidence of a mismatch.
                if i0 < 1 || i0 + numel(w) - 1 > head, continue; end
                got = double(rb.readSignalAt(i0 + (0:numel(w)-1)'));
                e   = max(abs(got - obj.CurPol(k)*w));
                if e > worst, worst = e; worstK = k; end
                checked = checked + 1;
            end

            R.NumWaveforms = checked;
            if checked < 1, return; end
            R.MaxError       = worst;
            R.WaveformsMatch = worst <= tol;
            if R.WaveformsMatch
                R.Summary = sprintf('%s; every presentation matches its own waveform (max error %.1e)', ...
                    R.Summary,worst);
            else
                % Whatever the onsets said, the sweeps are not the stimuli
                % they are labelled with -- so the verdict is overruled here.
                R.Aligned = false;
                R.Summary = sprintf(['MISALIGNED: the samples at presentation %d are not ' ...
                    'stimulus %d (max error %.2e over %d presentations checked)'], ...
                    worstK,obj.CurSeq(max(1,worstK)),worst,checked);
            end
        end

        function F = finalize_run(obj)
            % The DSP half of splitting the run's recording into one Block
            % (and one .abr) per stimulus that appeared in it, done in this
            % process: reading the ring, recovering the onsets, decimating,
            % splitting by stimulus, filtering, judging. That is
            % mabr.compute.Pipeline.finalize, which can run in any process --
            % the DSP worker does the same thing when there is one. The rest
            % (crediting, the Blocks, the files) is conclude_run's, whichever
            % process produced F.
            F = obj.Pipeline.finalize(obj.Engine.RingBuffer,obj.CurSeq);
        end

        function [files,blocks] = assemble_blocks(obj,F,ctx)
            % Turn the pipeline's finalization output (see
            % mabr.compute.Pipeline.finalize) into Recordings, Blocks and
            % files. Nothing here filters a sample: the filtered trace arrives
            % with each part and is adopted through
            % mabr.data.Recording.withProcessed, so a Block's every accessor
            % reads a kept copy rather than running the chain again.
            %
            % ctx is the run's own context (run_context), taken before the
            % next run was begun -- by the time this runs the next one may
            % already be streaming, so nothing here reads the Cur* fields.
            % The schedule has already been credited (credit_run).
            if nargin < 3 || isempty(ctx), ctx = obj.run_context(); end
            files  = {};
            blocks = mabr.data.Block.empty;
            if isempty(F) || F.NumOnsets < 1, return; end

            n     = F.NumOnsets;
            seq   = F.Seq;
            adcFs = obj.Config.ADCSampleRate;      % analysis/storage rate
            % The chain the parts were filtered with, as settings (a struct
            % crosses a process boundary; a designed policy need not).
            made = F.Filters;
            if isstruct(made), made = mabr.FilterPolicy.fromStruct(made); end
            gain = 1;
            if isfield(F,'AmplifierGain'), gain = F.AmplifierGain; end
            % Polarity is per presentation, so it truncates with the sequence
            % -- a run can end early (Stop/Abort, or an advance criterion).
            pol = ctx.CurPol;
            if numel(pol) >= n, pol = pol(1:n); else, pol = ones(1,n); end

            for i = 1:numel(F.Parts)
                p = F.Parts(i);
                u = p.Stimulus;

                % The Recording carries the raw trace and the chain separately:
                % the chain only decides what SweepData/SweepMean look like,
                % and io writes Data. So the .abr file below is unfiltered no
                % matter what the operator has the filter dialog set to.
                % Rejected sweeps are marked, never dropped — the samples still
                % reach the .abr file so an offline reanalysis can make its
                % own call.
                rec = mabr.data.Recording(adcFs,p.Data,p.Onsets,p.SweepLength,1);
                rec.Filters    = obj.Filters;
                rec            = rec.withProcessed(p.Processed,made);
                rec.IsArtifact = p.Flags;
                nLost          = rec.NumArtifacts;
                if nLost > 0
                    mabr.log.vprintf(1,'Stimulus %d: %d of %d sweeps rejected (%s)', ...
                        u,nLost,p.Count,obj.Artifacts.describe());
                end

                % keep only lightweight metadata on the Block (not the waveform)
                stimMeta = struct('Meta',obj.Stimuli.meta(u), ...
                                  'SampleRate',obj.Stimuli.SampleRate);
                blk = mabr.data.Block(stimMeta,rec,ctx.BlockStart);
                % Test Mode blocks are marked at the source. Everything
                % downstream -- the viewers, the .abr, an analysis six months
                % from now -- reads it off the block rather than having to
                % know what the audio settings were at the time.
                blk.TestMode = obj.Testing;
                % The gain Data was already divided by -- the one the parts
                % were MADE with, like `made` above -- split back into the
                % external amplifier and the input's full scale, so the file
                % can say what each was and what the raw converter samples
                % were. A config control, so it cannot have changed mid-run.
                blk.InputFullScale = obj.InputFullScale;
                blk.AmplifierGain  = gain*obj.InputFullScale;
                % Per-sweep polarity, in the same order as the Recording's
                % SweepOnsets, so the offline pipeline can average (or split)
                % the two polarities of an alternating condition.
                blk.SweepPolarity = pol(seq == u);
                % The rig notebook as it stands right now, copied onto the
                % block as a plain struct so the value carries its own record
                % (and io writes it into the .abr). Taken here rather than at
                % write time because a Block reaches a viewer through
                % BlockReady whether or not the session is saving.
                blk.Notes         = obj.Session.noteRecord();

                % The file first: nothing in it depends on the metrics below
                % (io writes the Recording, never Block.Metrics), and a
                % metric that fails or runs out of memory must cost the
                % metric -- not this block's .abr and every later one of the
                % run, which is what an error here used to do.
                if ~isempty(obj.Session.OutputPath)
                    files{end+1} = mabr.data.io.writeABR(blk, ...
                        obj.Session.OutputPath,obj.Session.Subject.ID); %#ok<AGROW>
                end
                try
                    blk = blk.computeMetrics();
                catch me
                    mabr.log.vprintf(1,1,'Block metrics for stimulus %d not computed: %s', ...
                        u,me.message);
                end

                obj.Session.addBlock(blk);
                blocks(end+1) = blk; %#ok<AGROW>
                % The metrics worker keeps the same table of finalized
                % conditions the analysis windows do; this is where it
                % gets each row. Never fatal.
                if ~isempty(obj.Compute)
                    try
                        c = mabr.compute.ConditionStore.fromBlock(blk);
                        if ~isempty(c), obj.Compute.addCondition(c); end
                    catch me
                        mabr.log.vprintf(1,1,'Could not hand the block to the metrics worker: %s', ...
                            me.message);
                    end
                end
            end
        end

        function file = log_stim_run(obj)
            % Save the run's stimulation sequence, and return the file written
            % ('' when the Session has no OutputPath -- the same
            % run-without-saving rule Preview relies on for .abr files).
            %
            % This is the stimulation-only counterpart of finalize_run. There
            % is no recording to segment and no Block to build, but the plan
            % that was just played out IS the record of the experiment: what
            % went out, in what order, with what polarity, and when. Written
            % per run as the run ends, so a session interrupted halfway keeps
            % the log of everything already presented.
            %
            % The onsets are the RENDERED ones (see CurOnsets), not recovered
            % ones -- there is no input to recover them from. They are exact:
            % the same play matrix carries a timing pulse at every one of them,
            % so a system recording elsewhere aligns on the pulse and reads the
            % labels here.
            file = '';

            % What the worker actually got through before the run ended. A
            % Stop/Abort cuts the matrix short, and the presentations past that
            % point never happened -- io.buildStimLog flags them rather than
            % quietly writing the whole plan as though it had played.
            stream = obj.Engine.LastStream;

            info = struct();
            info.Run             = obj.CurRun;
            info.NumRuns         = obj.Schedule.NumRuns;
            info.StartTime       = obj.BlockStart;
            info.Subject         = obj.Session.Subject.ID;
            info.Device          = obj.Schedule.Device;
            info.SampleRate      = obj.Config.DACSampleRate;
            info.PlayerChannels  = obj.Schedule.PlayerChannels;
            info.StimulusIndex   = obj.CurSeq;
            info.Polarity        = obj.CurPol;
            info.OnsetSample     = obj.CurOnsets;
            % Left OUT when the worker made no report (it always does, but a
            % missing one must not be read as "0 samples streamed", which would
            % mark a run that played perfectly well as never presented).
            if ~isempty(stream.reason)
                info.StreamedSamples = stream.samples;
                info.StopReason      = stream.reason;
            end
            % strategyLabel, not Strategy: 'custom' alone does not say WHICH
            % custom, and a record of what was presented that cannot name the
            % function that ordered it cannot be reproduced from.
            info.Strategy        = obj.Schedule.strategyLabel();
            info.ISIMode         = obj.Schedule.ISIMode;
            info.ISI             = obj.Schedule.ISI;
            info.ISIRange        = obj.Schedule.ISIRange;
            info.SilencePad      = obj.Schedule.SilencePad;
            info.IDs             = obj.Stimuli.IDs();
            info.StimulusMeta    = arrayfun(@(u) obj.Stimuli.meta(u), ...
                1:obj.Stimuli.numStimuli,'UniformOutput',false);
            % A stimulation-only session writes no .abr, so the .stimlog is the
            % only file its notes can reach.
            info.Notes           = obj.Session.noteRecord();

            % Tally what was presented against the plan, exactly as a recorded
            % run tallies what came back -- so the schedule's own bookkeeping
            % (and anything reading RunCounts) is as true here as there.
            counts = zeros(1,obj.Stimuli.numStimuli);
            presented = obj.CurSeq;
            if ~isempty(stream.reason) && ~isempty(obj.CurOnsets)
                presented = obj.CurSeq(obj.CurOnsets <= stream.samples);
            end
            for u = unique(presented)
                counts(u) = nnz(presented == u);
            end
            obj.Schedule.recordRun(obj.CurRun,counts);

            mabr.log.vprintf(1,'Run %d of %d: %d of %d presentations played (%s).', ...
                obj.CurRun,obj.Schedule.NumRuns,numel(presented),numel(obj.CurSeq), ...
                stream.reason);

            if isempty(obj.Session.OutputPath), return; end
            file = mabr.data.io.writeStimLog(info,obj.Session.OutputPath, ...
                obj.Session.Subject.ID);
        end

        % --- Input monitor --------------------------------------------------
        function arm_monitor(obj)
            % One lap: the silent block prepared and streamed. The worker
            % resets the ring at the Run, so what is in it from here is this
            % controller's.
            obj.Engine.prep(obj.MonitorSpec);
            obj.Engine.run();
            obj.HasRecorded = true;
        end

        function end_monitor(obj,why)
            obj.Monitoring    = false;
            obj.MonitorWanted = false;
            obj.MonitorSpec   = [];
            obj.MonitorError  = why;
            if isempty(why)
                mabr.log.vprintf(1,'Input monitor stopped.');
            end
            notify(obj,'MonitorChanged');
        end

        % --- Helpers --------------------------------------------------------
        function set_state(obj,s)
            if obj.State == s, return; end
            obj.State = s;
            notify(obj,'StateChanged',mabr.ui.ProgStateEventData(s));
        end

        function start_timer(obj)
            % Both views start together; they only differ in how often they
            % are served. The run's first frame is due as soon as there is a
            % sweep to draw.
            obj.LastFrameStart = -Inf;
            if strcmp(obj.LiveTimer.Running,'off')
                start(obj.LiveTimer);
            end
            if ~isempty(obj.AuxTimer) && isvalid(obj.AuxTimer) ...
                    && strcmp(obj.AuxTimer.Running,'off')
                start(obj.AuxTimer);
            end
        end

        function stop_timer(obj)
            try
                if strcmp(obj.LiveTimer.Running,'on'), stop(obj.LiveTimer); end
            catch %#ok<CTCH>
            end
            try
                if strcmp(obj.AuxTimer.Running,'on'), stop(obj.AuxTimer); end
            catch %#ok<CTCH>
            end
            % The run is over: nothing should be able to pull a snapshot of it
            % after the fact, and the pipeline stops attributing sweeps to it.
            obj.LiveLocal = false;
            obj.PendingRunStart = [];   % a run over before it streamed never starts
            if ~isempty(obj.Pipeline), obj.Pipeline.endRun(); end
            if ~isempty(obj.Compute) && obj.Compute.InRun
                obj.Compute.runEnd(obj.RunSerial);
            end
        end
    end

    methods (Static)
        function role = workerRole(stimOnly)
            % What to call the worker for a run of this kind (mabr.acq.Engine's
            % Role). A worker that records nothing is not an acquisition
            % worker, and a log that calls it one is misleading in exactly the
            % mode where the user most needs to be sure nothing is being
            % recorded.
            if stimOnly, role = 'stimulus'; else, role = 'acquisition'; end
        end
    end

end

% ======================= local helpers ================================
function v = getdef(s,f,d)
% A field of a settings struct, or the default where it is absent or empty.
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function s = durationWords(secs)
if secs < 90, s = sprintf('%.3g s',secs); else, s = sprintf('%.3g min',secs/60); end
end
