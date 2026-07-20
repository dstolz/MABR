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
            spec = mabr.stim.BlockQueue.buildSpec(blk,obj.Config,obj.SilencePad);
            spec.PlayerChannels    = obj.PlayerChannels;
            spec.RecorderChannels  = obj.RecorderChannels;
            spec.TestingFrameDelay = obj.TestingFrameDelay;
            if isfield(blk,'Device') && ~isempty(blk.Device)
                spec.Device = blk.Device;
            elseif ~isempty(obj.Device)
                spec.Device = obj.Device;
            end
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
        function spec = buildSpec(blk,cfg,silencePad)
            % Synthesize the [N x 2] play matrix (signal + timing) and pad it.
            if nargin < 3 || isempty(silencePad), silencePad = 0; end

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
