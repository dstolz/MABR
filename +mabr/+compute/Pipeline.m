classdef Pipeline < handle
% mabr.compute.Pipeline  The signal processing between the ring buffer and
% everything that looks at it -- in whichever process it runs.
%
%   Everything MABR computes from recorded samples while a schedule runs is
%   here, and only here: sweep extraction, the display filter chain, the
%   artifact preview, the onset-contrast correlation, the per-condition
%   running mean and spread the live view draws, and the finalization DSP
%   that turns a completed run into per-stimulus Recordings. It was lifted
%   out of mabr.ui.AcqController's live tick and finalize_run so that the
%   same object can be stepped by a compute worker (mabr.compute.compute_loop)
%   or, with no worker, by the controller itself -- one implementation, so the
%   two cannot disagree.
%
%       p = mabr.compute.Pipeline(cfg);
%       p.configure(window,filters,artifacts);   % designs the chain at the ADC rate
%       p.beginRun(runInfo);                     % what the onsets belong to
%       stats = p.step(ringBuffer);              % one cycle, [] until a sweep exists
%       S     = p.sweeps();                      % the filtered sweeps behind it
%       F     = p.finalize(ringBuffer,seq);      % the DSP half of finalization
%       p.endRun();
%
%   INCREMENTAL, AND EXACT
%   mabr.metrics.extract_sweeps already caches the raw windowed sweeps in its
%   cursor state and windows only the newly completed ones. This object keeps
%   a parallel FILTERED cache and passes only the new sweeps through the
%   chain, so a cycle costs the sweeps that arrived since the last one rather
%   than the whole run so far. That is bit-identical to filtering the whole
%   matrix every time, which is what the live tick used to do: filtfilt
%   treats the columns of a matrix independently (mabr.FilterPolicy.apply is
%   column-wise), the no-high-pass baseline removal is per sweep, and both
%   artifact criteria judge a sweep on its own samples. A configure() that
%   changes the chain or the window throws the cache away and the next step
%   rebuilds it; one that changes only the artifact policy re-judges the
%   cached sweeps without refiltering them.
%
%   The pre-onset baseline and the response are filtered TOGETHER, as one
%   contiguous segment per sweep: extract_sweeps takes the baseline as the
%   samples immediately preceding the onset at the same stride, so [pre post]
%   is one unbroken trace. Filtering it whole doubles the length available
%   to filtfilt and, more to the point, keeps the filter's edge transient in
%   the baseline instead of dumping it on the first milliseconds of the
%   response -- exactly where the early waves are.
%
%   WHAT step() RETURNS
%   A struct of SUFFICIENT STATISTICS, never the sweep matrix: the latest
%   sweep, the correlation, the sweep counts, and per condition the mean, the
%   standard deviation and the counts. Every band the live view can draw is a
%   function of (mean, SD, n) -- see mabr.metrics.band_from_stats -- so this
%   is all a view needs, and it is small enough to publish through a memory
%   map twenty times a second. sweeps() is there for the consumers that do
%   need the matrix (the in-process snapshot the analysis windows read, and
%   the metrics worker's condition table).
%
%   PREVIEW, NOT VERDICT
%   The artifact flags step() reports are a preview: the authoritative call
%   is made at finalization on the sweeps of the decimated, whole-trace
%   filtered Recording (see finalize), and recorded in Recording.IsArtifact.
%   Both use the same policy and the same mabr.metrics.detect_artifacts, so
%   they agree except where the two filterings differ on a marginal sweep.
%
%   See also mabr.ui.AcqController, mabr.compute.compute_loop,
%   mabr.metrics.extract_sweeps, mabr.FilterPolicy, mabr.ArtifactPolicy.
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Config
        Window     (1,2) double = [0 0.01];   % ADC window (s) relative to onset
        % The chain as configured, and the same chain designed at the rate
        % the live sweeps actually arrive at: extract_sweeps windows DAC-rate
        % samples with a decimationFactor stride, so a live sweep is at the
        % ADC rate -- the rate a finalized Recording is filtered at, which is
        % why the live view and the Block agree. designfilt costs
        % milliseconds and step() may run twenty times a second, so the
        % design is made when the policy changes and never inside a step.
        Filters    (1,1) mabr.FilterPolicy   = mabr.FilterPolicy;
        LiveFilter (1,1) mabr.FilterPolicy   = mabr.FilterPolicy;
        Artifacts  (1,1) mabr.ArtifactPolicy = mabr.ArtifactPolicy;
        % What the onsets of the run in progress belong to (see beginRun);
        % [] between runs, and step() does nothing then.
        Run = []
        % Cycles performed since construction. A detector, not bookkeeping:
        % a controller served by a worker never steps its own pipeline, and
        % a test can read that off this number.
        StepCount (1,1) double = 0
    end

    properties (Access = private)
        Configured (1,1) logical = false
        SweepState = struct()        % extract_sweeps cursor + raw sweep cache
        BlockSeq   (1,1) double = -1 % ring-buffer block the cache belongs to
        Filt = zeros(0,0)            % [nSweeps x 2L] filtered [pre post], rows = sweeps
        Bad  = false(1,0)            % artifact preview, one per row of Filt
        NumFiltered (1,1) double = 0
        L    (1,1) double = 0        % samples in the post-onset window
        Time = zeros(1,0)            % [1 x 2L] s re onset, starts negative
        Idx  = zeros(1,0)            % stimulus behind each row of Filt
        NeedRejudge (1,1) logical = false
    end

    methods
        function obj = Pipeline(cfg)
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            obj.Config = cfg;
        end

        % --- Configuration --------------------------------------------------
        function configure(obj,window,filters,artifacts)
            % Adopt the analysis window and the two policies. Safe to call
            % with the values already in force -- nothing is thrown away
            % unless it has actually changed -- and safe mid-run: a new chain
            % refilters the cached sweeps on the next step, a new artifact
            % policy re-judges them, and a new window re-extracts them from
            % the ring, which still holds the block.
            if nargin < 2 || isempty(window),    window    = obj.Window;    end
            if nargin < 3 || isempty(filters),   filters   = obj.Filters;   end
            if nargin < 4 || isempty(artifacts), artifacts = obj.Artifacts; end
            window = double(window(:)');

            if ~obj.Configured || ~filters.sameSettings(obj.Filters)
                obj.Filters = filters;
                obj.designLive();
                obj.invalidateFiltered();
            end
            if ~obj.Configured || ~isequal(window,obj.Window)
                obj.Window     = window;
                obj.SweepState = struct();
                obj.invalidateFiltered();
            end
            if ~obj.Configured || ~isequal(artifacts.toStruct(),obj.Artifacts.toStruct())
                obj.Artifacts   = artifacts;
                obj.NeedRejudge = true;
            end
            obj.Configured = true;
        end

        function beginRun(obj,runInfo)
            % Start attributing sweeps to a run. runInfo fields:
            %   RunId      any scalar naming the run (the schedule index)
            %   StimIndex  [1 x nPres] stimulus behind each planned onset --
            %              the k-th recorded onset is the k-th presentation,
            %              the same pairing finalization de-interleaves by
            %   Stimuli    [1 x nStim] the stimuli this run presents, in the
            %              order the per-condition rows of step() come in
            %   Labels     {1 x nStim} their IDs (optional)
            %   Meta       {1 x nStim} their StimulusSet.meta structs (optional)
            assert(isstruct(runInfo) && isfield(runInfo,'StimIndex'), ...
                'mabr:compute:Pipeline:runInfo', ...
                'beginRun needs a struct with at least a StimIndex field.');
            if ~isfield(runInfo,'RunId') || isempty(runInfo.RunId), runInfo.RunId = 0; end
            if ~isfield(runInfo,'Stimuli') || isempty(runInfo.Stimuli)
                runInfo.Stimuli = unique(double(runInfo.StimIndex(:)'),'stable');
            end
            obj.Run        = runInfo;
            obj.SweepState = struct();
            obj.invalidateFiltered();
        end

        function endRun(obj)
            obj.Run = [];
        end

        function tf = inRun(obj)
            tf = ~isempty(obj.Run);
        end

        % --- The live cycle -------------------------------------------------
        function stats = step(obj,rb)
            % One cycle over the ring buffer: extract whatever sweeps have
            % completed since the last one, filter and judge the new ones,
            % and return the statistics of the run so far -- or [] while no
            % sweep is complete (or no run is in progress).
            %
            %   RunId, Time [1 x 2L] s, NumSamples
            %   Latest [1 x 2L] the most recent (filtered) sweep, LatestBad,
            %   LatestStim (the stimulus that evoked it)
            %   Corr           mabr.metrics.partition_corr over the clean sweeps
            %   NumSweeps / NumClean / NumArtifacts   this run so far
            %   Stimuli [1 x nStim], and row-aligned with it:
            %   Mean, SD [nStim x 2L], CondCounts [nStim x 3] clean total rejected
            stats = [];
            if isempty(obj.Run), return; end
            assert(obj.Configured,'mabr:compute:Pipeline:notConfigured', ...
                'configure() must be called before step().');

            params = struct('SampleRate',obj.Config.DACSampleRate, ...
                'window',obj.Window,'decimation',obj.Config.decimationFactor, ...
                'threshold',0.1,'shadow',0.002);
            [pre,post,~,obj.SweepState,tw] = ...
                mabr.metrics.extract_sweeps(rb,params,obj.SweepState);
            obj.StepCount = obj.StepCount + 1;
            if isempty(post), return; end

            % extract_sweeps starts over on a block boundary (a BlockSeq bump
            % or a head that went backwards); the filtered cache has to
            % follow it, or it would describe sweeps that no longer exist.
            n = size(post,1);
            if obj.SweepState.blockSeq ~= obj.BlockSeq || n < obj.NumFiltered
                obj.invalidateFiltered();
                obj.BlockSeq = obj.SweepState.blockSeq;
            end

            L = size(post,2);
            obj.L    = L;
            obj.Time = [tw.pre tw.post];

            if n > obj.NumFiltered
                new = obj.NumFiltered+1:n;
                Yn  = obj.filterRows(pre(new,:),post(new,:));
                obj.Filt(new,:) = Yn;
                obj.Bad(new)    = obj.judge(Yn(:,L+1:end));
                obj.NumFiltered = n;
            end
            if obj.NeedRejudge
                obj.Bad         = obj.judge(obj.Filt(:,L+1:end));
                obj.NeedRejudge = false;
            end

            keep = ~obj.Bad;
            R = 0;
            if nnz(keep) > 1
                R = mabr.metrics.partition_corr(obj.Filt(keep,1:L),obj.Filt(keep,L+1:end));
            end
            stats = obj.buildStats(R);
        end

        function S = sweeps(obj)
            % The filtered sweeps behind the last step(): Y [nSweeps x 2L]
            % (rows = sweeps, the orientation the live path uses), t [1 x 2L]
            % s re onset, bad [1 x nSweeps], stimIdx [1 x nSweeps] the
            % stimulus behind each, n. What a consumer that needs the matrix
            % rather than its statistics reads.
            S = struct('Y',obj.Filt,'t',obj.Time,'bad',obj.Bad, ...
                       'stimIdx',obj.Idx,'n',size(obj.Filt,1));
        end

        % --- Finalization ---------------------------------------------------
        function F = finalize(obj,rb,seq)
            % The DSP half of finalizing a completed run: read the whole
            % retained block, recover the onsets, decimate to the analysis
            % rate, split by stimulus, filter, and judge each sweep. Returns
            %
            %   F.NumOnsets   onsets paired with a presentation (0 = nothing)
            %   F.OnsetsAll   EVERY onset recovered, absolute, before the
            %                 pairing below trimmed the list to the plan.
            %                 More of these than there are presentations
            %                 means spurious pulses, which is precisely the
            %                 fault that shifts later sweeps onto the wrong
            %                 condition -- so the extras have to survive to
            %                 be reported even though nothing can be
            %                 attributed to them
            %   F.Seq         [1 x NumOnsets] the stimulus behind each
            %   F.OnsetsRaw   [1 x NumOnsets] where those onsets were
            %                 recovered, as ABSOLUTE ring-buffer sample
            %                 indices at the DAC rate -- the same numbering
            %                 mabr.stim.Schedule's ExpectedOnsets uses, so
            %                 the two can be held against each other
            %                 (mabr.metrics.alignment_report). Kept raw and
            %                 undecimated deliberately: the whole question is
            %                 whether a recovered onset is where the plan put
            %                 it, and dividing by the stride first would throw
            %                 away the samples that answer it.
            %   F.Filters     the settings (FilterPolicy.toStruct) the
            %                 Processed traces were made with
            %   F.Parts       one per stimulus present, in first-seen order:
            %       Stimulus, Data (single, decimated, raw), Processed (the
            %       same trace through the chain), Onsets (into Data),
            %       SweepLength, Flags (IsArtifact per onset), Count
            %
            % Plain data, deliberately: the client half
            % (mabr.ui.AcqController.assemble_blocks) turns these into
            % Recordings and Blocks, and plain data is what crosses a
            % process boundary without ceremony. A part's Processed trace is
            % installed with mabr.data.Recording.withProcessed, so no
            % consumer of the Block ever filters the trace again.
            %
            % `seq` is the run's per-onset stimulus index (the schedule's).
            % A run can end early, so whichever of the recorded onsets and
            % the planned sequence is shorter is trusted.
            F = struct('NumOnsets',0,'Seq',zeros(1,0),'OnsetsRaw',zeros(1,0), ...
                       'OnsetsAll',zeros(1,0),'Filters',obj.Filters.toStruct(), ...
                       'Parts',mabr.compute.Pipeline.emptyParts());
            [rawSignal,rawTiming] = rb.readBlock();   % chronological, wrap-safe
            if numel(rawSignal) < 2, return; end
            % readBlock starts at the oldest sample still retained, which is
            % sample 1 of the block for any run the ring can hold (longer runs
            % are refused at build -- mabr:stim:Schedule:tooLong). Recovering
            % the base anyway is what keeps OnsetsRaw absolute rather than
            % quietly relative to whatever survived.
            base = rb.WriteHead - numel(rawSignal) + 1;

            cfg   = obj.Config;
            Fs    = cfg.DACSampleRate;         % ring-buffer (DAC) rate
            df    = cfg.decimationFactor;
            adcFs = cfg.ADCSampleRate;         % analysis/storage rate

            onsetsRaw = mabr.metrics.find_timing_onsets(rawTiming,round(0.002*Fs),0.1);
            F.OnsetsAll = base + onsetsRaw(:)' - 1;   % before any trimming
            if isempty(onsetsRaw), return; end

            seq = double(seq(:)');
            n   = min(numel(onsetsRaw),numel(seq));
            if n < 1, return; end
            onsetsRaw = onsetsRaw(1:n);
            seq       = seq(1:n);

            % Decimate to the analysis rate at finalization so the Recording
            % (and its filter design) are self-consistent. io then saves it
            % as-is (DecimationFactor = 1) yielding the same offline-format
            % 12 kHz .abr the legacy save_abr_data produced.
            adcData  = single(resample(double(rawSignal),1,df));
            onsets   = max(1,round(onsetsRaw(:)./df));
            sweepLen = max(1,round(adcFs*diff(obj.Window)));

            present = unique(seq,'stable');
            parts   = mabr.compute.Pipeline.emptyParts();
            for u = present
                sel = onsets(seq == u);

                if isscalar(present)
                    % Homogeneous run: the continuous trace, exactly as the
                    % one-block-per-condition path always has.
                    data = adcData;
                else
                    % Intermixed run: keep only this stimulus's sweep windows,
                    % so each .abr carries its own data instead of N copies of
                    % one shared trace. Still plain Data + SweepOnsets, so the
                    % offline pipeline reads it unchanged.
                    [data,sel] = mabr.compute.Pipeline.compact_sweeps(adcData,sel,sweepLen);
                end

                % The Recording carries the raw trace and the chain separately:
                % designFilters only decides what SweepData looks like, and io
                % writes Data. So the .abr this becomes is unfiltered no matter
                % what the operator has the filter dialog set to.
                rec = mabr.data.Recording(adcFs,data,sel,sweepLen,1);
                rec.Filters = obj.Filters;
                rec = rec.designFilters();

                % Judge each sweep AFTER filtering: baseline drift in a raw
                % trace trips a voltage threshold on its own. Rejected sweeps
                % are marked, never dropped -- the samples still reach the
                % .abr file so an offline reanalysis can make its own call.
                %
                % Mapped back through ValidSweeps so the flags stay aligned
                % with SweepOnsets even when a truncated run left the last
                % window short (those sweeps are absent from SweepData).
                flags = false(numel(sel),1);
                flags(rec.ValidSweeps) = obj.Artifacts.detect(rec.SweepData);

                parts(end+1) = struct('Stimulus',u,'Data',data, ...
                    'Processed',rec.ProcessedData,'Onsets',sel(:), ...
                    'SweepLength',sweepLen,'Flags',flags,'Count',numel(sel)); %#ok<AGROW>
            end

            F.NumOnsets = n;
            F.Seq       = seq;
            F.OnsetsRaw = base + onsetsRaw(:)' - 1;
            F.Parts     = parts;
        end
    end

    % =====================================================================
    methods (Access = private)
        function designLive(obj)
            % Design the chain at the rate the live sweeps arrive at. An
            % unrealizable chain must not take acquisition down with it: fall
            % back to showing the trace unfiltered, and say so.
            try
                obj.LiveFilter = obj.Filters.design(obj.Config.ADCSampleRate);
            catch me
                obj.LiveFilter = mabr.FilterPolicy(false,false,false);
                mabr.log.vprintf(0,1,'Filter design failed (%s); live view unfiltered.', ...
                    me.message);
            end
        end

        function invalidateFiltered(obj)
            obj.Filt        = zeros(0,0);
            obj.Bad         = false(1,0);
            obj.NumFiltered = 0;
            obj.NeedRejudge = false;
        end

        function Y = filterRows(obj,pre,post)
            % Run the display chain over sweeps given as [nSweeps x nSamples]
            % -- the baseline and the response as ONE segment each (see the
            % class help) -- and return them as [nSweeps x 2L], still rows.
            Y = [pre post];
            if isempty(post) || ~obj.LiveFilter.Designed, return; end
            Y = obj.LiveFilter.apply(Y.').';      % columns = sweeps inside apply
        end

        function bad = judge(obj,post)
            % Preview the artifact verdict on [nSweeps x L] filtered response
            % windows. detect_artifacts wants the FILTERED sweeps, and by here
            % they are. With the high pass switched OFF there is nothing
            % removing a baseline offset, and a sweep sitting on one would
            % trip a voltage threshold on the offset alone -- so in that case,
            % and only that case, each sweep's own mean stands in for it.
            bad = false(1,size(post,1));
            if ~obj.Artifacts.Enabled || isempty(post), return; end
            D = double(post).';                     % [nSamples x nSweeps]
            if ~obj.LiveFilter.HighPass
                D = D - mean(D,1,'omitnan');
            end
            bad = obj.Artifacts.detect(D);
            bad = logical(bad(:)');
        end

        function stats = buildStats(obj,R)
            Y   = obj.Filt;
            bad = obj.Bad;
            n   = size(Y,1);
            keep = ~bad;

            % Which stimulus evoked each sweep: the k-th recorded onset is the
            % k-th planned presentation. More onsets than the plan should not
            % happen; if it does, the extras belong with the last one rather
            % than inventing a condition for them (the live view's own rule).
            seq = double(obj.Run.StimIndex(:)');
            idx = ones(1,n);
            k   = min(numel(seq),n);
            if k > 0
                idx(1:k) = seq(1:k);
                if k < n, idx(k+1:end) = seq(k); end
            end
            obj.Idx = idx;

            stimuli = double(obj.Run.Stimuli(:)');
            nC = numel(stimuli);
            M  = nan(nC,size(Y,2));
            SD = nan(nC,size(Y,2));
            counts = zeros(nC,3);
            for c = 1:nC
                sel  = idx == stimuli(c);
                good = sel & keep;
                counts(c,:) = [nnz(good) nnz(sel) nnz(sel & bad)];
                if ~any(good), continue; end
                M(c,:)  = mean(Y(good,:),1);
                SD(c,:) = std(Y(good,:),0,1);
            end

            stats = struct('RunId',obj.Run.RunId,'Time',obj.Time, ...
                'NumSamples',numel(obj.Time), ...
                'Latest',Y(end,:),'LatestBad',bad(end),'LatestStim',idx(end), ...
                'Corr',R, ...
                'NumSweeps',n,'NumClean',nnz(keep),'NumArtifacts',nnz(bad), ...
                'Stimuli',stimuli,'Mean',M,'SD',SD,'CondCounts',counts);
        end
    end

    % =====================================================================
    methods (Static)
        function stats = emptyStats(runId)
            % What step() would return if it returned something with no
            % sweep in it: the shape of a stats struct with nothing to
            % report. A worker publishes this on a cycle with no complete
            % sweep yet so its heartbeat is visible to the client's
            % watchdog; a consumer treats NumSweeps < 1 as "nothing yet".
            if nargin < 1, runId = 0; end
            stats = struct('RunId',runId,'Time',zeros(1,0),'NumSamples',0, ...
                'Latest',zeros(1,0),'LatestBad',false,'LatestStim',0,'Corr',0, ...
                'NumSweeps',0,'NumClean',0,'NumArtifacts',0, ...
                'Stimuli',zeros(1,0),'Mean',zeros(0,0),'SD',zeros(0,0), ...
                'CondCounts',zeros(0,3));
        end

        function p = emptyParts()
            p = struct('Stimulus',{},'Data',{},'Processed',{},'Onsets',{}, ...
                       'SweepLength',{},'Flags',{},'Count',{});
        end

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
