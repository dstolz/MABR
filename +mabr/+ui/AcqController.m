classdef AcqController < handle
% mabr.ui.AcqController  Wires the UI to the acquisition engine.
%
%   Owns the mabr.acq.Engine, the mabr.data.Session, the mabr.stim.Schedule,
%   and the live view. Translates user actions into engine commands and engine
%   events into UI updates and program-state transitions. There is NO global
%   state and NO busy-wait: engine State transitions arrive as events, and a
%   single ~20 Hz timer refreshes the live view from the ring buffer.
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
%   not finalized -- no Block, no BlockReady/BlockSaved, no .abr. The plan
%   still advances run by run to SchedComplete, which is all there is to
%   report when nothing is coming back.
%
%   Artifact rejection is DECIDED at that same finalization, which is why the
%   Artifacts policy is settable at any time, including mid-acquisition: the
%   live path holds no verdict of its own. It does preview one — live_tick_body
%   applies the current policy to the sweeps it has, so the live mean shows the
%   average the block will hold and a noisy electrode is visible as it happens
%   — but nothing there is recorded, and re-pointing Artifacts simply changes
%   what the next tick previews. See the property and set.Artifacts below.
%
%   Events the App can listen to:
%       StateChanged     - program flow changed (mabr.ui.ProgStateEventData)
%       MetricsUpdated   - live metrics changed (ProgStateEventData.Info)
%       BlockReady       - a finalized mabr.data.Block is available
%                          (.Info.block); fires once per stimulus recovered
%                          from the run, whether or not it was written to
%                          disk. This is what viewers (mabr.ui.TraceOrganizer)
%                          listen to so a trace appears as each block lands.
%       BlockSaved       - a block was written (.Info.file); fires once per
%                          stimulus recovered from the run, and only when the
%                          Session has an OutputPath
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
        State (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        Testing (1,1) logical = false
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
    end

    properties (Access = private)
        LiveTimer
        % Filters, designed once at the live sweeps' sample rate. designfilt
        % costs milliseconds; the live tick runs 20 times a second, so the
        % chain is built when the policy changes and never inside the tick.
        LiveFilter (1,1) mabr.FilterPolicy = mabr.FilterPolicy;
        SweepState (1,1) struct = struct();
        CurMetrics (1,1) struct = struct('numSweeps',0,'numArtifacts',0, ...
                                         'numClean',0,'corr',0);
        BlockStart (1,:) char = '';
        % tic reference for the run currently streaming, so an advance
        % criterion can reason in wall-clock seconds (ctx.elapsedSeconds).
        % 0 until the first run of a session begins.
        RunStartTic (1,1) uint64 = uint64(0);
        CurRun     (1,1) double = 0;    % index of the run being acquired
        CurSeq     (1,:) double = [];   % stimulus index at each of its onsets
        CurPol     (1,:) double = [];   % polarity (+1/-1) at each of its onsets
        % The stimuli this run presents and what to call them, worked out once
        % when the run is prepared rather than on every one of the 20 live
        % ticks a second. The live view lays out one mean per entry, so the
        % list is the RUN's, in presentation order -- not the whole bank's.
        CurStim    (1,:) double = [];
        CurLabels  (1,:) cell   = {};
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
    end

    events
        StateChanged
        MetricsUpdated
        BlockReady
        BlockSaved
        ScheduleComplete
    end

    methods
        function obj = AcqController(cfg,testing,progressFcn)
            % progressFcn (optional) receives char status messages while the
            % engine starts up; forwarded straight to mabr.acq.Engine.
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            if nargin < 2 || isempty(testing), testing = false; end
            if nargin < 3, progressFcn = []; end
            obj.Config  = cfg;
            obj.Testing = logical(testing);

            obj.Session = mabr.data.Session(cfg);
            obj.Engine  = mabr.acq.Engine(cfg,obj.Testing,progressFcn);
            obj.Listeners = [ ...
                addlistener(obj.Engine,'StateChanged', @(~,e) obj.on_engine_state(e)); ...
                addlistener(obj.Engine,'BlockCompleted',@(~,~) obj.on_block_completed()); ...
                addlistener(obj.Engine,'WorkerError',  @(~,e) obj.on_engine_error(e))];

            obj.LiveTimer = timer('Tag','MABR_LiveView', ...
                'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                'Period',0.05,'TasksToExecute',Inf, ...
                'TimerFcn',@(~,~) obj.on_live_tick());

            % Property defaults bypass set.Filters, so the default chain has
            % to be designed explicitly or the first ticks would run unfiltered.
            obj.refresh_live_filter();
        end

        function delete(obj)
            obj.stop_timer();
            try, delete(obj.LiveTimer); end %#ok<TRYNC>
            try, delete(obj.Listeners);  end %#ok<TRYNC>
            try, delete(obj.LivePlot);   end %#ok<TRYNC>
            try, delete(obj.Engine);     end %#ok<TRYNC>
        end

        function waitUntilReady(obj,timeout)
            if nargin < 2, timeout = 120; end
            obj.Engine.waitUntilReady(timeout);
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
            % LiveFilter), so the one moment the settings can change is the
            % one moment worth spending designfilt in. Same MCSUP caveat as
            % set.Artifacts below: a controller is never deserialized.
            obj.Filters = p;
            obj.refresh_live_filter();
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
        end

        % --- User actions ---------------------------------------------------
        function start(obj)
            assert(~isempty(obj.Schedule),'mabr:ui:AcqController:noStimuli', ...
                'No stimuli set. Call setStimuli() first.');
            assert(obj.Schedule.NumRuns > 0,'mabr:ui:AcqController:emptySchedule', ...
                'The schedule is empty — every stimulus has 0 repetitions.');
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

            obj.SweepState = struct();
            obj.CurMetrics = struct('numSweeps',0,'numArtifacts',0, ...
                                    'numClean',0,'corr',0);
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

            obj.CurRun = r;
            obj.CurSeq = spec.StimulusIndex(:)';
            obj.CurPol = spec.Polarity(:)';

            % 'stable', so an interleaved run's live panels sit in the order
            % the stimuli are actually presented in.
            obj.CurStim   = unique(obj.CurSeq,'stable');
            obj.CurLabels = arrayfun(@(u) obj.Stimuli.id(u),obj.CurStim, ...
                'UniformOutput',false);

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
            % write, and nothing to announce to a viewer. The schedule-advance
            % tail below still runs -- the plan must drive itself to
            % completion exactly as it would with a recording attached.
            if ~obj.Schedule.StimulationOnly
                try
                    [files,blocks] = obj.finalize_run();
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
                catch me
                    mabr.log.vprintf(0,1,'Finalize failed: %s',me.message);
                end
            end

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
            params = struct('SampleRate',obj.Config.DACSampleRate, ...
                'window',obj.Window,'decimation',obj.Config.decimationFactor, ...
                'threshold',0.1,'shadow',0.002);
            [pre,post,onsets,obj.SweepState,tw] = ...
                mabr.metrics.extract_sweeps(obj.Engine.RingBuffer,params,obj.SweepState);

            if isempty(post), return; end

            % Everything below this line sees FILTERED sweeps: the traces, the
            % correlation, and the artifact preview. Only the display path is
            % affected — the ring buffer keeps the raw samples, and it is the
            % raw samples finalize_run reads and io writes.
            [pre,post] = obj.filter_sweeps(pre,post);

            % Preview the artifact verdict so the live view shows the average
            % the block will actually hold, not one a single electrode pop has
            % smeared. This is a PREVIEW: the authoritative call is made at
            % finalization, on the filtered sweeps (see finalize_run). Both use
            % the same policy and the same mabr.metrics.detect_artifacts, so
            % they agree except where filtering changes a marginal sweep.
            bad  = obj.live_artifacts(post);
            keep = ~bad;

            R = 0;
            if nnz(keep) > 1, R = mabr.metrics.partition_corr(pre(keep,:),post(keep,:)); end

            obj.CurMetrics.numSweeps    = numel(onsets);
            obj.CurMetrics.numArtifacts = nnz(bad);
            obj.CurMetrics.numClean     = nnz(keep);
            obj.CurMetrics.corr         = R;

            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot)
                % Hand over the baseline as well as the response, as one
                % unbroken segment: the view's time base starts BEFORE the
                % onset (default -2 ms), and pre-onset samples are the only
                % thing that can fill it. The two windows are contiguous by
                % construction (see extract_sweeps), so [pre post] is a single
                % trace and [tw.pre tw.post] its time base.
                obj.LivePlot.update([pre post],[tw.pre tw.post],R, ...
                    obj.AdvanceParams.targetSweeps,bad,obj.live_info(numel(onsets)));
            end

            notify(obj,'MetricsUpdated',mabr.ui.ProgStateEventData(obj.State,obj.CurMetrics));

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
        end

        function [pre,post] = filter_sweeps(obj,pre,post)
            % Run the display filter chain over the live sweeps, both given as
            % [nSweeps x nSamples].
            %
            % The two windows are filtered TOGETHER because they are
            % contiguous: extract_sweeps takes the baseline as the samples
            % immediately preceding the onset at the same stride, so [pre post]
            % is one unbroken segment. Filtering it whole doubles the length
            % available to filtfilt and, more to the point, keeps the filter's
            % edge transient in the baseline instead of dumping it on the first
            % milliseconds of the response — exactly where the early waves are.
            if isempty(post) || ~obj.LiveFilter.Designed, return; end
            L = size(post,2);
            x = obj.LiveFilter.apply([pre post].');   % columns = sweeps
            pre  = x(1:end-L,:).';
            post = x(end-L+1:end,:).';
        end

        function bad = live_artifacts(obj,post)
            % Judge the live sweeps [nSweeps x nSamples] under the current
            % policy. Nothing here is recorded -- finalize_run makes the call
            % that reaches Recording.IsArtifact and the .abr file.
            %
            % detect_artifacts wants the FILTERED sweeps, and by here they are:
            % filter_sweeps has run the same chain finalization will use, so
            % the preview and the verdict differ only on a marginal sweep. With
            % the high pass switched OFF there is nothing removing a baseline
            % offset, and a sweep sitting on one would trip a voltage threshold
            % on the offset alone -- so in that case, and only that case, each
            % sweep's own mean stands in for it.
            bad = false(1,size(post,1));
            if ~obj.Artifacts.Enabled || isempty(post), return; end
            D   = double(post).';                    % [nSamples x nSweeps]
            if ~obj.LiveFilter.HighPass
                D = D - mean(D,1,'omitnan');
            end
            bad = obj.Artifacts.detect(D);
        end

        function refresh_live_filter(obj)
            % Design the chain at the rate the live sweeps actually arrive at.
            % extract_sweeps windows DAC-rate samples with a decimationFactor
            % stride, so a live sweep is at the ADC rate -- the same rate the
            % Recording is filtered at in finalize_run, which is why the two
            % views agree.
            try
                obj.LiveFilter = obj.Filters.design(obj.Config.ADCSampleRate);
            catch me
                % An unrealizable chain must not take acquisition down with it;
                % fall back to showing the trace unfiltered.
                obj.LiveFilter = mabr.FilterPolicy(false,false,false);
                mabr.log.vprintf(0,1,'Filter design failed (%s); live view unfiltered.', ...
                    me.message);
            end
            obj.caption_live_plot();
        end

        function caption_live_plot(obj)
            % Keep the live view's caption honest about what it is showing.
            if isempty(obj.LivePlot) || ~isvalid(obj.LivePlot), return; end
            obj.LivePlot.setFilterText(obj.LiveFilter.describe());
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
            files  = {};
            blocks = mabr.data.Block.empty;
            rb     = obj.Engine.RingBuffer;
            [rawSignal,rawTiming] = rb.readBlock();   % chronological, wrap-safe
            if numel(rawSignal) < 2, return; end

            Fs = obj.Config.DACSampleRate;         % ring-buffer (DAC) rate
            df = obj.Config.decimationFactor;
            adcFs = obj.Config.ADCSampleRate;      % analysis/storage rate

            onsetsRaw = mabr.metrics.find_timing_onsets(rawTiming,round(0.002*Fs),0.1);
            if isempty(onsetsRaw), return; end

            % Pair each recorded onset with the stimulus the schedule placed
            % there. A run can end early (Stop/Abort, or an advance criterion),
            % so trust whichever of the two is shorter.
            seq = obj.CurSeq;
            pol = obj.CurPol;
            n   = min(numel(onsetsRaw),numel(seq));
            if n < 1, return; end
            onsetsRaw = onsetsRaw(1:n);
            seq       = seq(1:n);
            % Polarity is per presentation, so it truncates with the sequence.
            if numel(pol) >= n, pol = pol(1:n); else, pol = ones(1,n); end

            % Decimate to the analysis rate at finalization so the Recording
            % (and its filter design) are self-consistent. io then saves it
            % as-is (DecimationFactor = 1) yielding the same offline-format
            % 12 kHz .abr the legacy save_abr_data produced.
            adcData  = single(resample(double(rawSignal),1,df));
            onsets   = max(1,round(onsetsRaw(:)./df));
            sweepLen = max(1,round(adcFs*diff(obj.Window)));

            present = unique(seq,'stable');
            counts  = zeros(1,obj.Stimuli.numStimuli);
            lost    = zeros(1,obj.Stimuli.numStimuli);   % sweeps rejected, per stimulus

            for u = present
                sel = onsets(seq == u);
                counts(u) = numel(sel);

                if isscalar(present)
                    % Homogeneous run: save the continuous trace, exactly as
                    % the one-block-per-condition path always has.
                    data = adcData;
                else
                    % Intermixed run: keep only this stimulus's sweep windows,
                    % so each .abr carries its own data instead of N copies of
                    % one shared trace. Still plain Data + SweepOnsets, so the
                    % offline pipeline reads it unchanged.
                    [data,sel] = mabr.ui.AcqController.compact_sweeps(adcData,sel,sweepLen);
                end

                % The Recording carries the raw trace and the chain separately:
                % designFilters only decides what SweepData/SweepMean look like,
                % and io writes Data. So the .abr file below is unfiltered no
                % matter what the operator has the filter dialog set to.
                rec = mabr.data.Recording(adcFs,data,sel,sweepLen,1);
                rec.Filters = obj.Filters;
                rec = rec.designFilters();

                % Judge each sweep AFTER filtering: baseline drift in a raw
                % trace trips a voltage threshold on its own. Rejected sweeps
                % are marked, never dropped — the samples still reach the .abr
                % file so an offline reanalysis can make its own call.
                %
                % Map back through ValidSweeps so the flags stay aligned with
                % SweepOnsets even when a truncated run left the last window
                % short (those sweeps are absent from SweepData entirely).
                flags = false(numel(sel),1);
                flags(rec.ValidSweeps) = obj.Artifacts.detect(rec.SweepData);
                rec.IsArtifact = flags;
                lost(u)        = rec.NumArtifacts;
                if lost(u) > 0
                    mabr.log.vprintf(1,'Stimulus %d: %d of %d sweeps rejected (%s)', ...
                        u,lost(u),numel(sel),obj.Artifacts.describe());
                end

                % keep only lightweight metadata on the Block (not the waveform)
                stimMeta = struct('Meta',obj.Stimuli.meta(u), ...
                                  'SampleRate',obj.Stimuli.SampleRate);
                blk = mabr.data.Block(stimMeta,rec,obj.BlockStart);
                % Per-sweep polarity, in the same order as the Recording's
                % SweepOnsets, so the offline pipeline can average (or split)
                % the two polarities of an alternating condition.
                blk.SweepPolarity = pol(seq == u);
                blk = blk.computeMetrics();

                obj.Session.addBlock(blk);
                blocks(end+1) = blk; %#ok<AGROW>

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

        % --- Helpers --------------------------------------------------------
        function set_state(obj,s)
            if obj.State == s, return; end
            obj.State = s;
            notify(obj,'StateChanged',mabr.ui.ProgStateEventData(s));
        end

        function start_timer(obj)
            if strcmp(obj.LiveTimer.Running,'off'), start(obj.LiveTimer); end
        end

        function stop_timer(obj)
            try
                if strcmp(obj.LiveTimer.Running,'on'), stop(obj.LiveTimer); end
            catch %#ok<CTCH>
            end
        end
    end

    methods (Static, Access = private)
        function [data,newOnsets] = compact_sweeps(src,onsets,sweepLen)
            % Concatenate just the sweep windows at `onsets` into a new trace,
            % returning it with the onsets that index into it. Used to split an
            % intermixed run so each stimulus's .abr holds only its own sweeps.
            n         = numel(onsets);
            data      = zeros(n*sweepLen,1,'single');
            newOnsets = zeros(n,1);
            for k = 1:n
                i0 = onsets(k);
                i1 = min(i0+sweepLen-1,numel(src));
                d0 = (k-1)*sweepLen + 1;
                data(d0:d0+(i1-i0)) = src(i0:i1);
                newOnsets(k) = d0;
            end
        end
    end
end
