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
%   decide. AuxTimer (~2 Hz, see
%   AuxPeriod) does everything else drawn from a running block -- the snapshot
%   the online analysis windows pull from, and the MetricsUpdated event the
%   progress tally and the Run panel's readouts ride. Both timers are
%   'fixedSpacing', so a tick's period is measured from when the previous one
%   RETURNS: work in the fast tick comes straight off the live view's frame
%   rate, which is the whole reason the slow half is not in it. Nothing on the
%   aux timer recomputes anything -- the fast tick leaves its already-built
%   sweeps in PendingLive and the aux tick reads them.
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
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Config
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
        % How often the LOW-priority views are served (s). The live trace is
        % fixed at 20 Hz and is not negotiable -- this is the other timer, the
        % one carrying the progress tally and the online analysis snapshot.
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
        % The two are split because LiveTimer runs 'fixedSpacing': the next
        % tick starts Period AFTER the previous one returns, so the realized
        % refresh rate is 1/(Period + work). Every millisecond of low-priority
        % work in that tick comes straight off the live view's frame rate.
        % Moving it here buys the trace back.
        AuxTimer
        % What the fast tick leaves for the slow one: the sweeps it has
        % already built, so the aux tick re-derives nothing. Assignment is
        % copy-on-write, so stashing these costs a reference, not an array.
        PendingLive = []
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
        % The most recent live tick's sweeps, kept so a window that refreshes
        % on its OWN clock can see the run in progress without re-reading the
        % ring buffer or forcing the 20 Hz tick to push at them (see
        % liveSnapshot). [] whenever no run is streaming: it is cleared when a
        % run begins and again the moment one completes, so a puller can never
        % double-count the sweeps a finished run is about to be finalized
        % into. Costs a copy of arrays the tick has already computed.
        LiveSnap = []
    end

    events
        StateChanged
        MetricsUpdated
        BlockReady
        BlockSaved
        ScheduleComplete
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

            obj.LiveTimer = timer('Tag','MABR_LiveView', ...
                'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                'Period',0.05,'TasksToExecute',Inf, ...
                'TimerFcn',@(~,~) obj.on_live_tick());

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
            obj.begin_current_run();
        end

        function pauseAcq(obj),  obj.Engine.pause();  end
        function resumeAcq(obj), obj.Engine.resume(); end

        function stopBlock(obj)
            % Finish the current block early and advance to the next.
            obj.HaltAfterBlock = false;
            obj.Engine.stop();
        end

        function abort(obj)
            % Finish the current block early and halt the schedule.
            obj.HaltAfterBlock = true;
            obj.Engine.stop();
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

        function snap = liveSnapshot(obj)
            % The sweeps of the run CURRENTLY STREAMING, as of the last live
            % tick -- or [] when no run is. A pull, deliberately: the live
            % view is pushed at 20 Hz because it is drawing every sweep as it
            % lands, while an online-analysis window (mabr.ui.MetricPlot)
            % refreshes at 1 Hz or slower and there may be several of them, so
            % they read this when they are ready rather than being handed
            % copies twenty times a second.
            %
            % Fields:
            %   Run         index of the run in the schedule
            %   SampleRate  Hz of the sweeps (the ADC rate)
            %   Time        [1 x nSamples] seconds re onset; STARTS NEGATIVE,
            %               because the live path carries the pre-onset
            %               baseline as part of one contiguous segment
            %   Sweeps      [nSweeps x nSamples] volts, filtered by the
            %               display chain in force -- rows are sweeps, the
            %               orientation the live path uses
            %   StimIndex   [1 x nSweeps] which stimulus evoked each sweep
            %   Bad         [1 x nSweeps] the artifact PREVIEW for each
            %   Stimuli     [1 x nStim] stimulus indices this run presents
            %   Labels      {1 x nStim} their IDs
            %
            % Nothing here is authoritative: the artifact verdict and the
            % filtering are previews of what finalization will decide (see
            % live_tick_body), which is exactly what makes them the right
            % thing to watch WHILE it happens.
            snap = obj.LiveSnap;
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
                obj.Schedule.resumeAt(obj.Schedule.NumRuns);
                obj.begin_current_run();
            end
        end
    end

    methods (Access = private)
        % --- Program flow ---------------------------------------------------
        function begin_current_run(obj)
            r = obj.Schedule.current();
            if isempty(r) || r == 0
                obj.set_state(mabr.ui.ProgState.SchedComplete);
                notify(obj,'ScheduleComplete');
                return
            end
            obj.set_state(mabr.ui.ProgState.PrepBlock);

            obj.CurMetrics = struct('numSweeps',0,'numArtifacts',0, ...
                                    'numClean',0,'corr',0);
            obj.LiveSnap    = [];
            obj.PendingLive = [];   % the aux tick must not serve the last run
            obj.BlockStart = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            obj.RunStartTic = tic;
            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot), obj.LivePlot.reset(); end

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

            % Tell the pipeline what this run's onsets belong to. Its cursor
            % starts over here too, so nothing from the last run can be
            % attributed to this one.
            obj.RunSerial = obj.RunSerial + 1;
            info = struct('RunId',obj.RunSerial, ...
                'StimIndex',obj.CurSeq,'Stimuli',obj.CurStim, ...
                'Labels',{obj.CurLabels});
            obj.Pipeline.beginRun(info);
            % The workers get the same, plus the bank's metadata -- they
            % hold no StimulusSet, and the metrics worker names and places a
            % condition from its meta exactly as mabr.ui.MetricPlot would.
            if ~isempty(obj.Compute)
                info.Meta = arrayfun(@(u) obj.Stimuli.meta(u), ...
                    1:obj.Stimuli.numStimuli,'UniformOutput',false);
                obj.Compute.runStart(info);
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
            obj.Engine.prep(spec);
            obj.Engine.run();

            t0 = tic;
            while obj.Engine.State ~= mabr.acq.State.Completed && toc(t0) < 5
                pause(0.02);
            end
            obj.SelfTestActive = false;

            if obj.Engine.State ~= mabr.acq.State.Completed
                ok = false;
                return
            end
            [~,recTiming] = obj.Engine.RingBuffer.readBlock();
            onsets = mabr.metrics.find_timing_onsets(recTiming,round(0.002*fs),0.1);
            ok = ~isempty(onsets);
        end

        function on_engine_state(obj,e)
            if obj.SelfTestActive, return; end   % see verifyTimingLoop
            switch e.State
                case mabr.acq.State.Acquire
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
            if obj.SelfTestActive, return; end   % see verifyTimingLoop
            obj.stop_timer();
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
            obj.after_finalize();
        end

        function finalize_here(obj)
            % Finalize the run in this process, from the ring buffer.
            try
                [files,blocks] = obj.finalize_run();
                obj.emit_blocks(files,blocks);
            catch me
                mabr.log.vprintf(0,1,'Finalize failed: %s',me.message);
            end
        end

        function emit_blocks(obj,files,blocks)
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
                try
                    [files,blocks] = obj.assemble_blocks(msg.result);
                    obj.emit_blocks(files,blocks);
                catch me
                    mabr.log.vprintf(0,1,'Finalize failed: %s',me.message);
                end
            end
            obj.after_finalize();
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
            obj.after_finalize();
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
            obj.stop_timer();
            obj.set_state(mabr.ui.ProgState.Error);
            mabr.log.vprintf(0,1,'Acquisition error [%s]: %s',e.Identifier,e.Message);
        end

        % --- Live view ------------------------------------------------------
        function on_live_tick(obj)
            % Wrapped so a transient error never kills the live-view timer.
            try
                obj.live_tick_body();
            catch me
                mabr.log.vprintf(2,1,'Live tick error: %s',me.message);
            end
        end

        function live_tick_body(obj)
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
            if obj.usingWorkerDSP()
                [stats,changed] = obj.Compute.live();
                % Nothing new since the last tick is nothing to do: the
                % whole tick then costs one word read from the memory map.
                if isempty(stats) || ~changed || stats.NumSweeps < 1, return; end
                S = [];
            else
                stats = obj.Pipeline.step(obj.Engine.RingBuffer);
                if isempty(stats), return; end
                S = obj.Pipeline.sweeps();
            end
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
                obj.LivePlot.updateStats(stats,info);
            end

            % The sweeps themselves, left where the aux tick can find them
            % for liveSnapshot (copy-on-write: a reference, not a copy). With
            % a worker doing the DSP there is no sweep matrix in this process
            % to leave, and liveSnapshot stays empty -- the metrics worker
            % serves the analysis windows then.
            if isempty(S)
                obj.PendingLive = [];
            else
                obj.PendingLive = struct('Y',S.Y,'t',S.t,'bad',S.bad, ...
                    'n',S.n,'metrics',obj.CurMetrics,'state',obj.State);
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
            % The low-priority half of the live path: build the snapshot the
            % analysis windows pull from, and tell everyone whose numbers just
            % moved. Nothing here is recomputed -- the fast tick already did
            % the sweep extraction, filtering and artifact preview, and left
            % the result in PendingLive.
            try
                obj.aux_tick_body();
            catch me
                % A failing progress bar must not take the acquisition with
                % it, exactly as on_live_tick treats the live view.
                mabr.log.vprintf(1,'Aux view tick failed: %s',me.message);
            end
        end

        function aux_tick_body(obj)
            % Cache what a slow puller needs (see liveSnapshot) -- only when
            % the sweeps are in this process; a worker-served run leaves none.
            P = obj.PendingLive;
            if ~isempty(P)
                obj.LiveSnap = struct('Run',obj.CurRun, ...
                    'SampleRate',obj.Config.ADCSampleRate, ...
                    'Time',P.t,'Sweeps',P.Y, ...
                    'StimIndex',obj.CurSeq(1:min(P.n,numel(obj.CurSeq))), ...
                    'Bad',P.bad(:)','Stimuli',obj.CurStim,'Labels',{obj.CurLabels});
            end

            % The tally and the Run panel ride this whichever process did
            % the DSP: nothing to say until the first sweep has been counted.
            if obj.CurMetrics.numSweeps < 1, return; end
            notify(obj,'MetricsUpdated', ...
                mabr.ui.ProgStateEventData(obj.State,obj.CurMetrics));
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
            obj.Pipeline.configure(obj.Window,obj.Filters,obj.Artifacts);
            % And the workers', so every process agrees about what a sweep is.
            if ~isempty(obj.Compute)
                obj.Compute.configure(obj.Config.DACSampleRate,obj.Window, ...
                    obj.Filters,obj.Artifacts);
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
        function [files,blocks] = finalize_run(obj)
            % Split the run's recording into one Block (and one .abr) per
            % stimulus that appeared in it, and return the blocks built and the
            % files written. There is one block per stimulus present; files is
            % empty when the Session has no OutputPath.
            %
            % Two halves. The DSP -- reading the ring, recovering the onsets,
            % decimating, splitting by stimulus, filtering, judging -- is
            % mabr.compute.Pipeline.finalize, which can run in any process;
            % assemble_blocks is the half only the GUI process can do, since
            % it owns the Session, the schedule, and the files.
            F = obj.Pipeline.finalize(obj.Engine.RingBuffer,obj.CurSeq);
            [files,blocks] = obj.assemble_blocks(F);
        end

        function [files,blocks] = assemble_blocks(obj,F)
            % Turn the pipeline's finalization output (see
            % mabr.compute.Pipeline.finalize) into Recordings, Blocks, files
            % and schedule bookkeeping. Nothing here filters a sample: the
            % filtered trace arrives with each part and is adopted through
            % mabr.data.Recording.withProcessed, so a Block's every accessor
            % reads a kept copy rather than running the chain again.
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
            % Polarity is per presentation, so it truncates with the sequence
            % -- a run can end early (Stop/Abort, or an advance criterion).
            pol = obj.CurPol;
            if numel(pol) >= n, pol = pol(1:n); else, pol = ones(1,n); end

            counts = zeros(1,obj.Stimuli.numStimuli);
            lost   = zeros(1,obj.Stimuli.numStimuli);   % sweeps rejected, per stimulus

            for i = 1:numel(F.Parts)
                p = F.Parts(i);
                u = p.Stimulus;
                counts(u) = p.Count;

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
                lost(u)        = rec.NumArtifacts;
                if lost(u) > 0
                    mabr.log.vprintf(1,'Stimulus %d: %d of %d sweeps rejected (%s)', ...
                        u,lost(u),p.Count,obj.Artifacts.describe());
                end

                % keep only lightweight metadata on the Block (not the waveform)
                stimMeta = struct('Meta',obj.Stimuli.meta(u), ...
                                  'SampleRate',obj.Stimuli.SampleRate);
                blk = mabr.data.Block(stimMeta,rec,obj.BlockStart);
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
                blk = blk.computeMetrics();

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

                if ~isempty(obj.Session.OutputPath)
                    files{end+1} = mabr.data.io.writeABR(blk, ...
                        obj.Session.OutputPath,obj.Session.Subject.ID); %#ok<AGROW>
                end
            end

            obj.Schedule.recordRun(obj.CurRun,counts);

            % Win back what the artifacts cost, if asked to. The schedule
            % appends the make-up to the end of the plan and caps it, so this
            % converges even when the rejection rate stays high.
            if obj.Artifacts.Repeat && any(lost > 0)
                obj.Schedule.appendMakeup(lost);
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

        % --- Helpers --------------------------------------------------------
        function set_state(obj,s)
            if obj.State == s, return; end
            obj.State = s;
            notify(obj,'StateChanged',mabr.ui.ProgStateEventData(s));
        end

        function start_timer(obj)
            % Both views start together; they only differ in how often they
            % are served.
            if strcmp(obj.LiveTimer.Running,'off'), start(obj.LiveTimer); end
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
            % out of the aux tick after the fact, and the pipeline stops
            % attributing sweeps to it.
            obj.PendingLive = [];
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
