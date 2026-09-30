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
%       S     = p.columns();                     % the filtered sweeps behind it
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
%   map twenty times a second. columns() is there for the consumers that do
%   need the matrix (the in-process snapshot the analysis windows read, and
%   the metrics worker's condition table), in the cache's own orientation,
%   one sweep per column -- the one a condition holds its sweeps in, so
%   nothing between here and a metric transposes the run. It is a copy of
%   every sweep so far, so it is made only when asked for, and CopyCount
%   says how often that was. sweeps() is the same with rows as sweeps.
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
        % External amplifier gain (mabr.AudioSettings.AmplifierGain). The
        % ring holds converter units; every signal sample read from it is
        % divided by this before anything else happens, so the sweeps, the
        % artifact verdicts, and a finalized part's Data are in volts at the
        % electrodes. The timing channel is never scaled.
        Gain       (1,1) double = 1
        % What the onsets of the run in progress belong to (see beginRun);
        % [] between runs, and step() does nothing then.
        Run = []
        % Cycles performed since construction. A detector, not bookkeeping:
        % a controller served by a worker never steps its own pipeline, and
        % a test can read that off this number.
        StepCount (1,1) double = 0
        % Copies of the sweep matrix handed out (columns / sweeps) since
        % construction -- the same kind of detector: a controller whose live
        % snapshot no analysis window pulls never makes one.
        CopyCount (1,1) double = 0
    end

    properties (Access = private)
        Configured (1,1) logical = false
        SweepState = struct()        % extract_sweeps cursor: onsets, not sweeps
        BlockSeq   (1,1) double = -1 % ring-buffer block the cache belongs to
        Epoch      (1,1) double = -1 % ...and the extraction pass (SweepState.epoch)
        % The filtered sweeps, ONE COLUMN PER SWEEP ([pre; post], 2L rows),
        % preallocated for the planned run and filled in place. As rows of a
        % column-major matrix, every step's new sweeps used to reallocate and
        % copy the whole run so far.
        Filt = zeros(0,0)
        Bad  = false(1,0)            % artifact preview, one per column of Filt
        Idx  = zeros(1,0)            % stimulus behind each column of Filt
        NumFiltered (1,1) double = 0
        L    (1,1) double = 0        % samples in the post-onset window
        Time = zeros(1,0)            % [1 x 2L] s re onset, starts negative
        NeedRejudge (1,1) logical = false
        Row  = zeros(1,0)            % stimulus index -> row of the per-condition stats
        % RUNNING statistics, updated one sweep at a time in sweep order
        % (accumulate): per condition a Welford mean and sum of squared
        % deviations, and over every clean sweep the odd/even split-half
        % sums the onset-contrast correlation is made of. Recomputing all of
        % it from every sweep of the run on every 50 ms cycle made a run cost
        % the square of its length. One sweep at a time, in order, is also
        % what keeps a worker (many small steps) and this process (perhaps
        % one big one) bit-identical: the result depends on the sweeps, never
        % on where the step boundaries fell.
        Acc  = []
        LastStats = []               % step()'s last answer, reused while nothing changes
    end

    methods
        function obj = Pipeline(cfg)
            if nargin < 1 || isempty(cfg), cfg = mabr.Config; end
            obj.Config = cfg;
        end

        % --- Configuration --------------------------------------------------
        function configure(obj,window,filters,artifacts,gain)
            % Adopt the analysis window, the two policies, and the amplifier
            % gain. Safe to call with the values already in force -- nothing
            % is thrown away unless it has actually changed -- and safe
            % mid-run: a new chain or gain refilters the cached sweeps on the
            % next step, a new artifact policy re-judges them, and a new
            % window re-extracts them from the ring, which still holds the
            % block.
            if nargin < 2 || isempty(window),    window    = obj.Window;    end
            if nargin < 3 || isempty(filters),   filters   = obj.Filters;   end
            if nargin < 4 || isempty(artifacts), artifacts = obj.Artifacts; end
            if nargin < 5 || isempty(gain),      gain      = obj.Gain;      end
            window = double(window(:)');
            gain   = mabr.AudioSettings.coerceGain(gain,1);

            % A new gain or chain changes every filtered sweep: forget them
            % and rewind the extraction cursor, so the next step reads them
            % all back off the ring (which still holds the block) and filters
            % them afresh. A new window changes which samples a sweep IS, so
            % extraction starts over entirely.
            if gain ~= obj.Gain
                obj.Gain = gain;
                obj.invalidateFiltered(true);
            end

            if ~obj.Configured || ~filters.sameSettings(obj.Filters)
                obj.Filters = filters;
                obj.designLive();
                obj.invalidateFiltered(true);
            end
            if ~obj.Configured || ~isequal(window,obj.Window)
                obj.Window     = window;
                obj.restartExtraction();
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
            obj.Run = runInfo;
            st      = double(runInfo.Stimuli(:)');
            obj.Row = zeros(1,max([st 0]));
            obj.Row(st) = 1:numel(st);
            obj.restartExtraction();
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

            % The detection rule finalize uses too (mabr.Config.Onset*), so the
            % live sweeps and the saved blocks are paired by the same onsets.
            params = struct('SampleRate',obj.Config.DACSampleRate, ...
                'window',obj.Window,'decimation',obj.Config.decimationFactor, ...
                'threshold',mabr.Config.OnsetThreshold, ...
                'shadow',mabr.Config.OnsetShadow,'rearm',mabr.Config.OnsetRearm);
            [pre,post,~,obj.SweepState,tw] = ...
                mabr.metrics.extract_sweeps(rb,params,obj.SweepState);
            obj.StepCount = obj.StepCount + 1;

            % extract_sweeps starts over on a block boundary (a BlockSeq bump
            % or a head that went backwards), and what it just returned is
            % then the new block's first sweeps: the cache follows it, or it
            % would describe sweeps that no longer exist.
            if obj.SweepState.blockSeq ~= obj.BlockSeq || obj.SweepState.epoch ~= obj.Epoch
                obj.invalidateFiltered(false);
                obj.BlockSeq = obj.SweepState.blockSeq;
                obj.Epoch    = obj.SweepState.epoch;
            end

            L        = numel(tw.post);
            obj.L    = L;
            obj.Time = [tw.pre tw.post];

            % The sweeps this call windowed -- only those -- filtered and
            % judged into the next columns of the cache.
            k       = size(post,1);
            changed = k > 0;
            if changed
                n0   = obj.NumFiltered;
                cols = n0+1:n0+k;
                obj.ensureCapacity(n0+k);
                Y = obj.filterCols(pre/obj.Gain,post/obj.Gain);
                obj.Filt(:,cols) = Y;
                obj.Bad(cols)    = obj.judgeCols(Y(L+1:end,:));
                obj.Idx(cols)    = obj.stimulusAt(cols);
                obj.NumFiltered  = n0 + k;
            end
            n = obj.NumFiltered;

            % A new artifact policy re-judges every cached sweep, and the
            % running statistics are rebuilt from them in sweep order --
            % exactly what accumulating them one at a time would have given.
            if obj.NeedRejudge
                obj.NeedRejudge = false;
                if n > 0
                    obj.Bad(1:n) = obj.judgeCols(obj.Filt(L+1:end,1:n));
                    obj.resetStats();
                    obj.accumulate(1:n);
                    changed = true;
                end
            elseif changed
                if isempty(obj.Acc), obj.resetStats(); end
                obj.accumulate(cols);
            end

            if n == 0, return; end
            if ~changed && ~isempty(obj.LastStats)
                stats = obj.LastStats;          % nothing new: the same answer
                return
            end
            stats = obj.buildStats();
            obj.LastStats = stats;
        end

        function S = columns(obj)
            % The filtered sweeps behind the last step(): Y [2L x nSweeps],
            % ONE SWEEP PER COLUMN, t [1 x 2L] s re onset, bad [1 x nSweeps],
            % stimIdx [1 x nSweeps] the stimulus behind each, n. What a
            % consumer that needs the matrix rather than its statistics
            % reads -- a COPY of the part in use, built on request: the
            % analysis snapshot is made at most twice a second, and only
            % while a window pulls it, and the metrics worker asks once a
            % cycle, and only while a window has a job there. Neither may
            % hold the cache itself (the next step writes into it in place).
            % Columns, because that is how the cache holds them and how a
            % condition does (mabr.compute.ConditionStore): handed over as
            % rows, the run was transposed here and straight back there,
            % each time a full copy of it.
            n = obj.NumFiltered;
            obj.CopyCount = obj.CopyCount + 1;
            S = struct('Y',obj.Filt(:,1:n),'t',obj.Time,'bad',obj.Bad(1:n), ...
                       'stimIdx',obj.Idx(1:n),'n',n);
        end

        function S = sweeps(obj)
            % columns() with ROWS as sweeps: Y [nSweeps x 2L], the orientation
            % a caller holding the sweeps as a list of traces wants.
            n = obj.NumFiltered;
            obj.CopyCount = obj.CopyCount + 1;
            S = struct('Y',obj.Filt(:,1:n).','t',obj.Time,'bad',obj.Bad(1:n), ...
                       'stimIdx',obj.Idx(1:n),'n',n);
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
            %   F.AmplifierGain  the gain Data was divided by (see Gain)
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
                       'AmplifierGain',obj.Gain, ...
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

            onsetsRaw = mabr.metrics.find_timing_onsets(rawTiming, ...
                round(mabr.Config.OnsetShadow*Fs),mabr.Config.OnsetThreshold, ...
                round(mabr.Config.OnsetRearm*Fs));
            % The timing channel has said all it will: let it go before the
            % resample below makes its double copy of the signal (a full ring
            % is 256 MB a channel as single, 512 MB as double).
            rawTiming = []; %#ok<NASGU>
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
            % Referred to the electrodes here, once, so the .abr, the
            % filtered trace, and the artifact verdicts below all agree.
            x         = double(rawSignal);
            rawSignal = []; %#ok<NASGU>          % only the double copy from here
            adcData   = single(resample(x,1,df)/obj.Gain);
            x         = []; %#ok<NASGU>
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

        function invalidateFiltered(obj,rewind)
            % Forget the filtered sweeps and everything accumulated from them.
            % rewind = true also sends extraction back to the run's first
            % onset, so the next step reads every sweep back off the ring (a
            % new chain or gain); false leaves the cursor where it is (the
            % ring started a new block, and extraction already started over).
            obj.Filt        = zeros(0,0);
            obj.Bad         = false(1,0);
            obj.Idx         = zeros(1,0);
            obj.NumFiltered = 0;
            obj.NeedRejudge = false;
            obj.Acc         = [];
            obj.LastStats   = [];
            if rewind && isfield(obj.SweepState,'nWindowed')
                obj.SweepState.nWindowed = 0;
            end
        end

        function restartExtraction(obj)
            % Extraction from scratch: onsets, cursor and all (a new run, a
            % new window).
            obj.SweepState = struct();
            obj.BlockSeq   = -1;
            obj.Epoch      = -1;
            obj.invalidateFiltered(false);
        end

        function ensureCapacity(obj,need)
            % Room for `need` sweeps, and for the run's planned presentations
            % from the start, so a run fills its cache in place; doubling past
            % that (extra onsets are not planned for, and not expected).
            cap = size(obj.Filt,2);
            if need <= cap && size(obj.Filt,1) == 2*obj.L, return; end
            planned = 0;
            if ~isempty(obj.Run), planned = numel(obj.Run.StimIndex); end
            newCap = max([need, 2*cap, planned + 64, 64]);
            n = obj.NumFiltered;
            F = zeros(2*obj.L,newCap);
            B = false(1,newCap);
            I = zeros(1,newCap);
            if n > 0
                F(:,1:n) = obj.Filt(:,1:n);
                B(1:n)   = obj.Bad(1:n);
                I(1:n)   = obj.Idx(1:n);
            end
            obj.Filt = F; obj.Bad = B; obj.Idx = I;
        end

        function idx = stimulusAt(obj,cols)
            % Which stimulus evoked each of these sweeps: the k-th recorded
            % onset is the k-th planned presentation. More onsets than the
            % plan should not happen; if it does, the extras belong with the
            % last one rather than inventing a condition for them (the live
            % view's own rule).
            seq = double(obj.Run.StimIndex(:)');
            if isempty(seq)
                idx = ones(size(cols));
            else
                idx = seq(min(cols,numel(seq)));
            end
        end

        function Y = filterCols(obj,pre,post)
            % Run the display chain over sweeps given as [nSweeps x nSamples]
            % -- the baseline and the response as ONE segment each (see the
            % class help) -- and return them as COLUMNS, [2L x nSweeps], the
            % cache's own orientation. apply is column-wise, and any grouping
            % of two or more columns filters each column identically -- but a
            % LONE column takes filtfilt's vector path, which rounds
            % differently (~1e-14). A step that windowed exactly one sweep
            % (the norm at a slow ISI) therefore filters it as a pair with
            % itself, so a sweep's filtered samples never depend on how many
            % arrived with it: that is what keeps a worker and this process
            % bit-identical (verify_live_pipeline Part B).
            Y = [pre post].';
            if isempty(post) || ~obj.LiveFilter.Designed, return; end
            if size(Y,2) == 1
                Y = obj.LiveFilter.apply([Y Y]);
                Y = Y(:,1);
            else
                Y = obj.LiveFilter.apply(Y);
            end
        end

        function bad = judgeCols(obj,P)
            % Preview the artifact verdict on [L x nSweeps] filtered response
            % windows. detect_artifacts wants the FILTERED sweeps, and by here
            % they are. With the high pass switched OFF there is nothing
            % removing a baseline offset, and a sweep sitting on one would
            % trip a voltage threshold on the offset alone -- so in that case,
            % and only that case, each sweep's own mean stands in for it.
            bad = false(1,size(P,2));
            if ~obj.Artifacts.Enabled || isempty(P), return; end
            D = double(P);
            if ~obj.LiveFilter.HighPass
                D = D - mean(D,1,'omitnan');
            end
            bad = obj.Artifacts.detect(D);
            bad = logical(bad(:)');
        end

        function resetStats(obj)
            nC = numel(obj.Run.Stimuli);
            m  = 2*obj.L;
            obj.Acc = struct('Mean',zeros(m,nC),'M2',zeros(m,nC), ...
                'Clean',zeros(1,nC),'Total',zeros(1,nC),'Rejected',zeros(1,nC), ...
                'Odd',zeros(m,1),'Even',zeros(m,1),'NumOdd',0,'NumEven',0,'NumBad',0);
        end

        function accumulate(obj,cols)
            % Fold these sweeps into the running statistics, one at a time and
            % in order. Per condition, Welford's update of the mean and of the
            % sum of squared deviations (numerically stable, and a mean of one
            % sweep is that sweep exactly); over every CLEAN sweep, whichever
            % of the odd/even split-half sums its place among the clean ones
            % puts it in -- mabr.metrics.partition_corr's odd and even rows.
            A = obj.Acc;
            obj.Acc = [];                 % sole owner, so the updates are in place
            for j = cols
                c = 0;
                u = obj.Idx(j);
                if u >= 1 && u <= numel(obj.Row), c = obj.Row(u); end
                if c > 0, A.Total(c) = A.Total(c) + 1; end
                if obj.Bad(j)
                    A.NumBad = A.NumBad + 1;
                    if c > 0, A.Rejected(c) = A.Rejected(c) + 1; end
                    continue
                end
                y = obj.Filt(:,j);
                if mod(A.NumOdd + A.NumEven,2) == 0
                    A.Odd  = A.Odd + y;  A.NumOdd  = A.NumOdd + 1;
                else
                    A.Even = A.Even + y; A.NumEven = A.NumEven + 1;
                end
                if c > 0
                    k = A.Clean(c) + 1;
                    A.Clean(c)  = k;
                    d = y - A.Mean(:,c);
                    A.Mean(:,c) = A.Mean(:,c) + d/k;
                    A.M2(:,c)   = A.M2(:,c) + d.*(y - A.Mean(:,c));
                end
            end
            obj.Acc = A;
        end

        function stats = buildStats(obj)
            % The run so far, from the running statistics: nothing here is
            % proportional to the number of sweeps.
            A = obj.Acc;
            n = obj.NumFiltered;
            L = obj.L;
            stimuli = double(obj.Run.Stimuli(:)');
            nC = numel(stimuli);
            M  = nan(nC,2*L);
            SD = nan(nC,2*L);
            % Each guarded by any(): with ONE condition these masks are
            % scalars, and a 1x1 indexed by a scalar false is 0x0 rather
            % than 1x0 -- which does not broadcast against [2L x 0].
            has  = A.Clean > 0;
            if any(has), M(has,:) = A.Mean(:,has).'; end
            % std of one sweep is 0; of more, from the squared deviations
            % (floored at 0 against round-off).
            SD(A.Clean == 1,:) = 0;
            many = A.Clean > 1;
            if any(many)
                SD(many,:) = sqrt(max(A.M2(:,many),0) ./ (A.Clean(many) - 1)).';
            end

            R = 0;
            if A.NumOdd + A.NumEven > 1
                mo = (A.Odd/A.NumOdd).';
                me = (A.Even/A.NumEven).';
                R  = mabr.metrics.partition_corr_from_means( ...
                    [mo(1:L); me(1:L); mo(L+1:end); me(L+1:end)]);
            end

            stats = struct('RunId',obj.Run.RunId,'Time',obj.Time, ...
                'NumSamples',numel(obj.Time), ...
                'Latest',obj.Filt(:,n).','LatestBad',obj.Bad(n),'LatestStim',obj.Idx(n), ...
                'Corr',R, ...
                'NumSweeps',n,'NumClean',n - A.NumBad,'NumArtifacts',A.NumBad, ...
                'Stimuli',stimuli,'Mean',M,'SD',SD, ...
                'CondCounts',[A.Clean(:) A.Total(:) A.Rejected(:)]);
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
