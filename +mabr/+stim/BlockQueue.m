classdef BlockQueue < handle
% mabr.stim.BlockQueue  Ordered pre-rendered blocks + schedule walk.
%
%   Holds a mabr.stim.StimulusSource and walks its blocks in order, rendering
%   each into the 2-channel play matrix the acquisition worker streams. This
%   is the in-memory replacement for the legacy prepare_block_fg.m dac.wav
%   handoff: MABR pairs the external signal channel with a timing-pulse
%   channel it synthesizes (one unit pulse per sweep onset), pads to a frame
%   multiple, and brackets the block with a little silence for device
%   settling.
%
%   MABR also owns the inter-stimulus interval. A source hands over a block
%   already tiled at whatever rate it chose; BlockQueue extracts the single
%   sweep waveform back out and re-tiles it at SweepInterval (seconds,
%   onset-to-onset), so the operator sets the presentation rate at acquisition
%   time. Setting SweepInterval to 0 keeps the source's own SweepOnsets.
%
%   Typical walk (driven by the AcqController):
%       q = mabr.stim.BlockQueue(source,cfg);
%       idx  = q.current();
%       spec = q.renderSpec(idx);      % -> engine.prep(spec)
%       ...acquire...
%       q.recordRun(idx,nSweeps);
%       idx = q.advance();             % [] when the schedule is complete
%
% Daniel Stolzberg (c) 2019-2026

    properties
        Source                        % mabr.stim.StimulusSource
        Config                        % mabr.Config
        Order            (1,:) double % block indices, in play order
        Selected         (1,:) logical
        RunCounts        (1,:) double % sweeps completed per block index
        TargetSweeps     (1,1) double = 512;  % default per-block target
        SweepInterval    (1,1) double = 1/21.1; % ISI (s), onset-to-onset
        SilencePad       (1,1) double = 0.25; % seconds of silence each end
        PlayerChannels   (1,2) double = [1 2];% [DACsignal DACtiming]
        RecorderChannels (1,2) double = [1 2];% [ADCsignal ADCtiming]
        Device           (1,:) char = '';
        TestingFrameDelay (1,1) double = 0;   % s/frame; loopback pacing for tests only
    end

    properties (SetAccess = private)
        CurrentIndex (1,1) double = 0;   % current block index (0 = not started)
    end

    methods
        function obj = BlockQueue(source,cfg)
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end
            obj.Source    = source;
            obj.Config    = cfg;
            n             = source.numBlocks;
            obj.Order     = 1:n;
            obj.Selected  = true(1,n);
            obj.RunCounts = zeros(1,n);
            obj.reset();
        end

        function n = numBlocks(obj), n = obj.Source.numBlocks; end

        function reset(obj)
            obj.RunCounts(:) = 0;
            sel = obj.Order(obj.Selected(obj.Order));
            if isempty(sel), obj.CurrentIndex = 0; else, obj.CurrentIndex = sel(1); end
        end

        function idx = current(obj), idx = obj.CurrentIndex; end

        function tf = isComplete(obj)
            tf = obj.CurrentIndex == 0 || isempty(obj.nextSelected());
        end

        function idx = advance(obj)
            % Move to the next selected block after the current one.
            idx = obj.nextSelected();
            if isempty(idx), obj.CurrentIndex = 0; idx = []; else, obj.CurrentIndex = idx; end
        end

        function recordRun(obj,idx,nSweeps)
            obj.RunCounts(idx) = nSweeps;
        end

        function t = targetSweeps(obj,idx)
            % Per-block override via Meta.NumSweeps, else the queue default.
            t = obj.TargetSweeps;
            blk = obj.Source.getBlock(idx);
            if isfield(blk,'Meta') && isfield(blk.Meta,'NumSweeps') && ~isempty(blk.Meta.NumSweeps)
                t = blk.Meta.NumSweeps;
            elseif isfield(blk,'NumSweeps') && ~isempty(blk.NumSweeps)
                t = blk.NumSweeps;
            end
        end

        function spec = renderSpec(obj,idx)
            % Build the acquisition play-matrix spec for block idx.
            if nargin < 2 || isempty(idx), idx = obj.CurrentIndex; end
            blk = mabr.stim.StimulusSource.validateBlock(obj.Source.getBlock(idx));
            spec = mabr.stim.BlockQueue.buildSpec(blk,obj.Config,obj.SilencePad, ...
                obj.SweepInterval);
            spec.PlayerChannels    = obj.PlayerChannels;
            spec.RecorderChannels  = obj.RecorderChannels;
            spec.TestingFrameDelay = obj.TestingFrameDelay;
            if isfield(blk,'Device') && ~isempty(blk.Device)
                spec.Device = blk.Device;
            elseif ~isempty(obj.Device)
                spec.Device = obj.Device;
            end
        end

        function d = stimulusDuration(obj,idx)
            % Duration (s) of the longest single sweep waveform, for checking
            % that a chosen SweepInterval does not make sweeps overlap. With
            % no idx, the worst case over every selected block.
            if nargin < 2 || isempty(idx), idx = obj.Order(obj.Selected(obj.Order)); end
            d = mabr.stim.BlockQueue.sourceStimulusDuration(obj.Source,idx);
        end
    end

    methods (Access = private)
        function idx = nextSelected(obj)
            % First selected block strictly after CurrentIndex in Order.
            pos = find(obj.Order == obj.CurrentIndex,1);
            if isempty(pos), rest = obj.Order; else, rest = obj.Order(pos+1:end); end
            rest = rest(obj.Selected(rest));
            if isempty(rest), idx = []; else, idx = rest(1); end
        end
    end

    methods (Static)
        function spec = buildSpec(blk,cfg,silencePad,sweepInterval)
            % Synthesize the [N x 2] play matrix (signal + timing) and pad it.
            % sweepInterval (s) re-tiles the block at that ISI; 0/omitted keeps
            % the source's own sweep timing.
            if nargin < 3 || isempty(silencePad),   silencePad   = 0; end
            if nargin < 4 || isempty(sweepInterval), sweepInterval = 0; end

            if sweepInterval > 0
                blk = mabr.stim.BlockQueue.retile(blk,sweepInterval);
            end

            samples = single(blk.samples(:));
            Fs = blk.SampleRate;
            N  = numel(samples);

            % MABR records into a ring buffer clocked at the DAC rate and the
            % downstream windowing/decimation assume it, so a block must be
            % rendered at Config.DACSampleRate. Fail fast rather than silently
            % mis-window a differently-clocked source.
            if Fs ~= cfg.DACSampleRate
                error('mabr:stim:BlockQueue:sampleRate', ...
                    ['Block SampleRate (%g Hz) must equal Config.DACSampleRate ' ...
                     '(%g Hz).'],Fs,cfg.DACSampleRate);
            end

            onsets = mabr.stim.BlockQueue.resolveOnsets(blk,N);

            if isfield(blk,'Timing') && ~isempty(blk.Timing)
                timing = single(blk.Timing(:));
                if numel(timing) ~= N
                    error('mabr:stim:BlockQueue:timingLength', ...
                        'Provided Timing (%d) must match samples (%d).',numel(timing),N);
                end
            else
                timing = zeros(N,1,'single');
                v = onsets >= 1 & onsets <= N;
                timing(onsets(v)) = 1;
            end

            y = [samples timing];

            % bracket with silence for device settling / response tail
            P = round(silencePad*Fs);
            if P > 0
                y = [zeros(P,2,'single'); y; zeros(P,2,'single')];
                onsets = onsets + P;
            end

            % pad to an integer number of frames
            fl = cfg.frameLength;
            rem_ = mod(size(y,1),fl);
            if rem_ > 0
                y = [y; zeros(fl-rem_,2,'single')];
            end

            spec = struct();
            spec.PlayMatrix     = y;
            spec.SampleRate     = Fs;
            spec.ExpectedOnsets = onsets;
            spec.Meta           = mabr.stim.BlockQueue.getdef(blk,'Meta',struct());
        end

        function d = sourceStimulusDuration(source,idx)
            % Longest single-sweep duration (s) over a source's blocks. The
            % GUI uses this before a queue exists, to check a chosen ISI.
            if nargin < 2 || isempty(idx), idx = 1:source.numBlocks; end
            d = 0;
            for k = idx
                blk = mabr.stim.StimulusSource.validateBlock(source.getBlock(k));
                w   = mabr.stim.BlockQueue.sweepWaveform(blk);
                d   = max(d,numel(w)/blk.SampleRate);
            end
        end

        function w = sweepWaveform(blk)
            % Recover the single-sweep waveform from an already-tiled block:
            % the samples from the first onset up to the next one (or the end
            % for a single-sweep block), with trailing silence trimmed off so
            % the waveform's length is the real stimulus duration.
            samples = single(blk.samples(:));
            onsets  = mabr.stim.BlockQueue.resolveOnsets(blk,numel(samples));
            if isempty(onsets), w = samples; return; end
            i0 = onsets(1);
            if numel(onsets) > 1, i1 = onsets(2)-1; else, i1 = numel(samples); end
            w  = samples(i0:min(i1,numel(samples)));
            last = find(w ~= 0,1,'last');
            if isempty(last), w = w(1); else, w = w(1:last); end
        end

        function blk = retile(blk,sweepInterval)
            % Re-lay the block's sweep waveform out at the requested ISI,
            % keeping the block's sweep count. Overlapping sweeps are summed
            % (and logged) rather than clipped -- the GUI warns up front.
            Fs      = blk.SampleRate;
            nSweeps = numel(mabr.stim.BlockQueue.resolveOnsets(blk,numel(blk.samples)));
            if nSweeps < 1, return; end

            w      = mabr.stim.BlockQueue.sweepWaveform(blk);
            period = round(Fs*sweepInterval);
            if period < 1
                error('mabr:stim:BlockQueue:sweepInterval', ...
                    'SweepInterval (%g s) is shorter than one sample at %g Hz.', ...
                    sweepInterval,Fs);
            end
            if numel(w) > period
                mabr.log.vprintf(0,1, ...
                    ['Stimulus (%.2f ms) is longer than the inter-stimulus interval ' ...
                     '(%.2f ms); sweeps overlap.'],1e3*numel(w)/Fs,1e3*period/Fs);
            end

            onsets  = (0:nSweeps-1)'*period + 1;
            samples = zeros(onsets(end)+numel(w)-1,1,'single');
            for k = 1:nSweeps
                i0 = onsets(k);
                samples(i0:i0+numel(w)-1) = samples(i0:i0+numel(w)-1) + w;
            end

            blk.samples     = samples;
            blk.SweepOnsets = onsets;
            % A source-supplied Timing channel described the OLD layout, so it
            % no longer applies; let buildSpec synthesize one at the new onsets.
            if isfield(blk,'Timing'), blk.Timing = []; end
        end

        function onsets = resolveOnsets(blk,N)
            if isfield(blk,'SweepOnsets') && ~isempty(blk.SweepOnsets)
                onsets = round(blk.SweepOnsets(:));
            else
                r = round(blk.SampleRate./blk.SweepRate);
                if isfield(blk,'NumSweeps') && ~isempty(blk.NumSweeps)
                    nSweeps = blk.NumSweeps;
                else
                    nSweeps = floor(N./r);
                end
                onsets = (0:nSweeps-1)'.*r + 1;
            end
            onsets = onsets(onsets >= 1 & onsets <= N);
        end

        function v = getdef(s,f,d)
            if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end
    end
end
