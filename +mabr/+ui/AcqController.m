classdef AcqController < handle
% mabr.ui.AcqController  Wires the UI to the acquisition engine.
%
%   Owns the mabr.acq.Engine, the mabr.data.Session, the mabr.stim.BlockQueue,
%   and the live view. Translates user actions into engine commands and engine
%   events into UI updates and program-state transitions. There is NO global
%   state and NO busy-wait: engine State transitions arrive as events, and a
%   single ~20 Hz timer refreshes the live view from the ring buffer.
%
%   Because the worker polls commands every frame, an online advance criterion
%   (e.g. mabr.stim.advance.corr_threshold) can stop a block early the moment
%   a response is detected — the capability the legacy design could not offer.
%
%   Events the App can listen to:
%       StateChanged     - program flow changed (mabr.ui.ProgStateEventData)
%       MetricsUpdated   - live metrics changed (ProgStateEventData.Info)
%       BlockSaved       - a block was written (.Info.file)
%       ScheduleComplete - the whole schedule finished
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Config
        Engine      mabr.acq.Engine
        Session     mabr.data.Session
        Queue       mabr.stim.BlockQueue
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
    end

    properties (Access = private)
        LiveTimer
        SweepState (1,1) struct = struct();
        CurMetrics (1,1) struct = struct('numSweeps',0,'corr',0);
        BlockStart (1,:) char = '';
        HaltAfterBlock (1,1) logical = false;
        Listeners
    end

    events
        StateChanged
        MetricsUpdated
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
        function setSource(obj,source)
            obj.Queue = mabr.stim.BlockQueue(source,obj.Config);
            obj.Queue.TargetSweeps = obj.AdvanceParams.targetSweeps;
        end

        function setLivePlot(obj,lp)
            obj.LivePlot = lp;
        end

        % --- User actions ---------------------------------------------------
        function start(obj)
            assert(~isempty(obj.Queue),'mabr:ui:AcqController:noSource', ...
                'No stimulus source set. Call setSource() first.');
            obj.HaltAfterBlock = false;
            obj.Queue.reset();
            obj.begin_current_block();
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
        function begin_current_block(obj)
            idx = obj.Queue.current();
            if isempty(idx) || idx == 0
                obj.set_state(mabr.ui.ProgState.SchedComplete);
                notify(obj,'ScheduleComplete');
                return
            end
            obj.set_state(mabr.ui.ProgState.PrepBlock);

            obj.SweepState = struct();
            obj.CurMetrics = struct('numSweeps',0,'corr',0);
            obj.BlockStart = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            if ~isempty(obj.LivePlot) && isvalid(obj.LivePlot), obj.LivePlot.reset(); end

            spec = obj.Queue.renderSpec(idx);
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
                ffn = obj.finalize_block();
                if ~isempty(ffn), notify(obj,'BlockSaved',mabr.ui.ProgStateEventData( ...
                        obj.State,struct('file',ffn))); end
            catch me
                mabr.log.vprintf(0,1,'Finalize failed: %s',me.message);
            end

            if obj.HaltAfterBlock
                obj.set_state(mabr.ui.ProgState.Idle);
                return
            end

            obj.set_state(mabr.ui.ProgState.AdvanceBlock);
            nextIdx = obj.Queue.advance();
            if isempty(nextIdx)
                obj.set_state(mabr.ui.ProgState.SchedComplete);
                notify(obj,'ScheduleComplete');
            else
                obj.begin_current_block();
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

            % Online advance: stop the block early if the criterion is met.
            if obj.State == mabr.ui.ProgState.Acquire && obj.advance_met()
                mabr.log.vprintf(1,'Advance criterion met at %d sweeps (r=%.3f); stopping block', ...
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
        function ffn = finalize_block(obj)
            ffn = '';
            rb   = obj.Engine.RingBuffer;
            [rawSignal,rawTiming] = rb.readBlock();   % chronological, wrap-safe
            if numel(rawSignal) < 2, return; end

            Fs = obj.Config.DACSampleRate;         % ring-buffer (DAC) rate
            df = obj.Config.decimationFactor;
            adcFs = obj.Config.ADCSampleRate;      % analysis/storage rate

            onsetsRaw = mabr.metrics.find_timing_onsets(rawTiming,round(0.002*Fs),0.1);
            if isempty(onsetsRaw), return; end

            % Decimate to the analysis rate at finalization so the Recording
            % (and its filter design) are self-consistent. io then saves it
            % as-is (DecimationFactor = 1) yielding the same offline-format
            % 12 kHz .abr the legacy save_abr_data produced.
            adcData  = single(resample(double(rawSignal),1,df));
            onsets   = max(1,round(onsetsRaw./df));
            sweepLen = max(1,round(adcFs*diff(obj.Window)));

            rec = mabr.data.Recording(adcFs,adcData,onsets,sweepLen,1);
            rec.UseBandpass = obj.UseBandpass;
            rec.UseNotch    = obj.UseNotch;
            rec = rec.designFilters();

            idx     = obj.Queue.current();
            srcBlk  = obj.Queue.Source.getBlock(idx);
            % keep only lightweight metadata on the Block (not the waveform)
            stimMeta = struct('Meta',mabr.ui.AcqController.getdef(srcBlk,'Meta',struct()), ...
                              'SampleRate',srcBlk.SampleRate);
            blk = mabr.data.Block(stimMeta,rec,obj.BlockStart);
            blk = blk.computeMetrics();

            obj.Session.addBlock(blk);
            obj.Queue.recordRun(idx,numel(onsets));

            if ~isempty(obj.Session.OutputPath)
                ffn = mabr.data.io.writeABR(blk,obj.Session.OutputPath,obj.Session.Subject.ID);
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
        function v = getdef(s,f,d)
            if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end
    end
end
