classdef RunArchive < handle
% mabr.compute.RunArchive  A recorded run kept as it streams, so it may be
% longer than the acquisition ring buffer.
%
%   The ring (mabr.acq.RingBuffer) keeps the newest Config.maxInputBufferLength
%   samples -- 5.8 min at 192 kHz -- and finalization used to read the run
%   whole out of it, which capped a run at one lap. Everything finalization
%   takes from the raw stream is two things: the onsets in the timing channel,
%   and the signal decimated to the analysis rate. Both can be made a slice at
%   a time, and this object makes them while the run streams, from whichever
%   process runs the pipeline (mabr.compute.Pipeline: the DSP worker, or the
%   controller itself). The ring then only has to hold what arrived since the
%   last slice was read -- a twentieth of a second -- and the run may be as
%   long as the decimated trace can be held in memory, 48 kB a second at
%   12 kHz.
%
%       a = mabr.compute.RunArchive(cfg,gain,plannedSamples);
%       a.update(rb);      % read whatever the ring holds that is new
%       a.close(rb);       % the run is over: read the rest, end the signal
%       x = a.signal();    % single, ADC rate, divided by gain
%       o = a.onsets();    % absolute ring-sample indices
%
%   EXACT, NOT APPROXIMATE
%   The onsets are mabr.metrics.find_timing_onsets' over the whole block
%   (mabr.metrics.OnsetTracker) and the signal is single(resample(x,1,df)/gain)
%   over the whole block (mabr.compute.Decimator) -- what
%   mabr.compute.Pipeline.finalize computes from a run the ring holds. So a
%   run finalized from its archive is the run finalized from the ring, had the
%   ring been long enough (verify_run_archive holds the two against each
%   other). The gain is the one in force when the archive was made, fixed once
%   the first sample is read (a config control, so it does not change mid-run
%   from the GUI); Gain says which, and finalization reports it.
%
%   SAMPLES THAT ARE GONE STAY GONE
%   A reader that falls a whole lap behind the writer -- a process frozen for
%   minutes -- finds the samples it had not yet read overwritten. That is
%   detected, never papered over: an update checks before it reads that the
%   range is still in the ring, and again after (the writer may have lapped
%   it during the read; its data can lead its header by a frame, WriteAhead),
%   and on a loss the archive stops at the first sample it could not read
%   (Truncated, LostAt). Everything before that is exact, and is finalized
%   like a run stopped at that sample: the k-th onset is still the k-th
%   presentation. Nothing after it is kept -- past a gap of unknown length
%   the order of the pulses no longer says which presentation each one is.
%   The controller keeps an archive of its own as well whenever the DSP
%   worker keeps one, so a worker that is lost or falls behind does not take
%   the run with it (mabr.ui.AcqController).
%
%   See also mabr.compute.Pipeline, mabr.compute.Decimator,
%   mabr.metrics.OnsetTracker, mabr.acq.RingBuffer.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Factor   (1,1) double = 1      % decimation, DAC rate / ADC rate
        Gain     (1,1) double = 1      % what the decimated signal is divided by
        SampleRate (1,1) double = 0    % DAC rate of the samples read
        BlockSeq (1,1) double = -1     % the ring block this archive is of
        Head     (1,1) double = 0      % raw samples read (absolute, from 1)
        NumOut   (1,1) double = 0      % decimated samples kept
        Truncated (1,1) logical = false
        LostAt   (1,1) double = Inf    % first raw sample that could not be read
        Closed   (1,1) logical = false
        Updates  (1,1) double = 0      % update() calls that read something
    end

    properties (Access = private)
        Decim                          % mabr.compute.Decimator
        Tracker                        % mabr.metrics.OnsetTracker
        Sig = zeros(0,1,'single')      % decimated signal, with spare capacity
        WriteAhead (1,1) double = 1024 % samples the writer's data can lead its header by
        Chunk    (1,1) double = 2^20   % raw samples read at once
    end

    methods
        function obj = RunArchive(cfg,gain,plannedSamples)
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            if nargin < 2 || isempty(gain), gain = 1; end
            if nargin < 3 || isempty(plannedSamples), plannedSamples = 0; end
            fs = cfg.DACSampleRate;
            obj.Factor     = cfg.decimationFactor;
            obj.Gain       = mabr.AudioSettings.coerceGain(gain,1);
            obj.SampleRate = fs;
            obj.WriteAhead = cfg.frameLength;
            obj.Decim      = mabr.compute.Decimator(obj.Factor);
            obj.Tracker    = mabr.metrics.OnsetTracker( ...
                round(mabr.Config.OnsetShadow*fs),mabr.Config.OnsetThreshold, ...
                round(mabr.Config.OnsetRearm*fs));
            % Room for the planned run from the start (it fills in place);
            % doubling past that, since a run never streams more than its plan.
            if plannedSamples > 0
                obj.Sig = zeros(ceil(plannedSamples/obj.Factor) + 64,1,'single');
            end
        end

        function setGain(obj,gain)
            % A gain set before the first sample is read is the archive's;
            % after that it is the next run's (Pipeline.configure).
            if obj.Head == 0
                obj.Gain = mabr.AudioSettings.coerceGain(gain,obj.Gain);
            end
        end

        function update(obj,rb,final)
            % Read everything the ring holds past Head. `final` = the writer
            % has stopped (the block is complete), so nothing can be
            % overwritten during the read.
            if nargin < 3 || isempty(final), final = false; end
            if obj.Closed || obj.Truncated, return; end
            seq  = rb.BlockSeq;
            head = rb.WriteHead;
            if obj.BlockSeq < 0 || (obj.Head == 0 && seq ~= obj.BlockSeq)
                obj.BlockSeq = seq;            % adopted on the first read
            elseif seq ~= obj.BlockSeq || head < obj.Head
                % The ring started another block before this one was read to
                % its end: what was not read is gone.
                obj.lose(obj.Head + 1,'the ring started a new block');
                return
            end
            lo = obj.Head + 1;
            if lo > head, return; end
            ahead = obj.WriteAhead*~final;
            if lo < head - rb.MaxLength + 1 + ahead
                obj.lose(lo,'the ring overwrote it before it was read');
                return
            end
            while lo <= head
                hi  = min(head,lo + obj.Chunk - 1);
                sig = rb.readSignal(lo,hi);
                tim = rb.readTiming(lo,hi);
                if ~final
                    % The writer may have lapped the range while it was read.
                    if rb.BlockSeq ~= obj.BlockSeq ...
                            || lo < rb.WriteHead - rb.MaxLength + 1 + ahead
                        obj.lose(lo,'the ring overwrote it while it was read');
                        return
                    end
                end
                obj.Tracker.feed(tim);
                obj.append(obj.Decim.push(sig));
                obj.Head = hi;
                lo = hi + 1;
            end
            obj.Updates = obj.Updates + 1;
        end

        function close(obj,rb)
            % The run is over: read what is left and end the signal, so the
            % last outputs are made against the zeros resample pads its end
            % with. A truncated archive ends where its last output had every
            % input it reaches -- nothing is made against samples that were
            % lost rather than absent. Idempotent.
            if obj.Closed, return; end
            if nargin > 1 && ~isempty(rb), obj.update(rb,true); end
            if ~obj.Truncated
                obj.append(obj.Decim.finish());
            end
            obj.Closed = true;
        end

        function x = signal(obj)
            % The decimated signal, single, divided by Gain.
            x = obj.Sig(1:obj.NumOut);
        end

        function o = onsets(obj)
            % Every onset found, as absolute raw-sample indices (a column).
            o = obj.Tracker.onsets();
        end

        function n = numOnsets(obj)
            n = obj.Tracker.NumOnsets;
        end

        function S = summary(obj)
            % What finalization reports about where its samples came from
            % (Pipeline.finalize's F.Archive).
            S = mabr.compute.RunArchive.noArchive();
            S.Used      = true;
            S.Complete  = ~obj.Truncated;
            S.Truncated = obj.Truncated;
            S.LostAt    = obj.LostAt;
            S.Samples   = obj.Head;
            S.Seconds   = obj.Head/max(obj.SampleRate,eps);
            S.Onsets    = obj.Tracker.NumOnsets;
            S.Gain      = obj.Gain;
            S.Updates   = obj.Updates;
            chk         = mabr.compute.Decimator.selfCheck(obj.Factor);
            S.Exact     = chk.Exact;
        end

        function release(obj)
            % Let the buffers go; the archive is spent.
            obj.Sig    = zeros(0,1,'single');
            obj.NumOut = 0;
            obj.Closed = true;
        end
    end

    methods (Access = private)
        function append(obj,y)
            k = numel(y);
            if k == 0, return; end
            need = obj.NumOut + k;
            if need > numel(obj.Sig)
                s = zeros(max([need, 2*numel(obj.Sig), 2^16]),1,'single');
                s(1:obj.NumOut) = obj.Sig(1:obj.NumOut);
                obj.Sig = s;
            end
            % Divided in double and only then made single -- the order
            % Pipeline.finalize uses on a run it resamples whole.
            obj.Sig(obj.NumOut+1:need) = single(y/obj.Gain);
            obj.NumOut = need;
        end

        function lose(obj,at,why)
            % Said here at level 1, from whichever process holds the archive;
            % the controller says it in red once it knows whether another
            % archive of the same run is complete (AcqController.report_archive).
            obj.Truncated = true;
            obj.LostAt    = at;
            mabr.log.vprintf(1,['Run archive: samples from %.3f s were lost (%s); ' ...
                'this archive ends there.'],(at-1)/max(obj.SampleRate,eps),why);
        end
    end

    methods (Static)
        function S = noArchive()
            % F.Archive for a run finalized from the ring: nothing archived.
            S = struct('Used',false,'Complete',true,'Truncated',false,'LostAt',Inf, ...
                'Samples',0,'Seconds',0,'Onsets',0,'Gain',NaN,'Updates',0,'Exact',true);
        end
    end
end
