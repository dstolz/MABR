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
%   A run may contain more than one stimulus. At finalization the recorded
%   sweeps are de-interleaved by mabr.stim.Schedule's per-onset stimulus
%   index, so each stimulus ID still becomes its own mabr.data.Block and its
%   own .abr file regardless of how the presentation was ordered.
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
    end

    properties
        Window        (1,2) double = [0 0.01];   % ADC window (s) relative to onset
        AdvanceFcn    (1,1) = @mabr.stim.advance.num_sweeps;
        AdvanceParams (1,1) struct = struct('targetSweeps',512,'corrThreshold',0.5, ...
                                            'minSweeps',32,'maxSweeps',Inf);
        UseBandpass   (1,1) logical = true;
        UseNotch      (1,1) logical = true;
        % How sweeps are judged for artifact, and whether losses are made up.
        % Applied at finalization (see finalize_run); mabr.ui.App loads the
        % user's remembered choice into it at Start.
        Artifacts     (1,1) mabr.ArtifactPolicy = mabr.ArtifactPolicy;
    end

    properties (Access = private)
        LiveTimer
        SweepState (1,1) struct = struct();
        CurMetrics (1,1) struct = struct('numSweeps',0,'corr',0);
        BlockStart (1,:) char = '';
        CurRun     (1,1) double = 0;    % index of the run being acquired
        CurSeq     (1,:) double = [];   % stimulus index at each of its onsets
        CurPol     (1,:) double = [];   % polarity (+1/-1) at each of its onsets
        HaltAfterBlock (1,1) logical = false;
        Listeners
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
        end

        function setLivePlot(obj,lp)
            obj.LivePlot = lp;
        end

        % --- User actions ---------------------------------------------------
        function start(obj)
            assert(~isempty(obj.Schedule),'mabr:ui:AcqController:noStimuli', ...
                'No stimuli set. Call setStimuli() first.');
            assert(obj.Schedule.NumRuns > 0,'mabr:ui:AcqController:emptySchedule', ...
                'The schedule is empty — every stimulus has 0 repetitions.');
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
            obj.CurMetrics = struct('numSweeps',0,'corr',0);
            obj.BlockStart = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
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

            % The live view's progress bar tracks this run's own presentation
            % count, which the schedule — not the advance criterion — fixes.
            p = obj.AdvanceParams;
            p.targetSweeps = numel(obj.CurSeq);
            obj.AdvanceParams = p;

            obj.Engine.prep(spec);
            obj.Engine.run();
        end

        function on_engine_state(obj,e)
            switch e.State
                case mabr.acq.State.Acquire
                    obj.set_state(mabr.ui.ProgState.Acquire);
                    obj.start_timer();
                % Ready / Paused / Idle need no program-state change here
            end
        end

        function on_block_completed(obj)
            obj.stop_timer();
            obj.set_state(mabr.ui.ProgState.BlockComplete);

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
            [pre,post,onsets,obj.SweepState] = ...
                mabr.metrics.extract_sweeps(obj.Engine.RingBuffer,params,obj.SweepState);

            if isempty(post), return; end

            R = 0;
            if size(post,1) > 1, R = mabr.metrics.partition_corr(pre,post); end

            obj.CurMetrics.numSweeps = numel(onsets);
            obj.CurMetrics.corr      = R;

            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot)
                w    = round(obj.Config.DACSampleRate.*obj.Window);
                tvec = (w(1):obj.Config.decimationFactor:w(2))/obj.Config.DACSampleRate;
                obj.LivePlot.update(post,tvec,R,obj.AdvanceParams.targetSweeps);
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

        function tf = advance_met(obj)
            ctx = obj.AdvanceParams;
            ctx.numSweeps = obj.CurMetrics.numSweeps;
            ctx.corr      = obj.CurMetrics.corr;
            tf = obj.AdvanceFcn(ctx);
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

                rec = mabr.data.Recording(adcFs,data,sel,sweepLen,1);
                rec.UseBandpass = obj.UseBandpass;
                rec.UseNotch    = obj.UseNotch;
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
