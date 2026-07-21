classdef Schedule < handle
% mabr.stim.Schedule  Turns a StimulusSet into an ordered presentation plan.
%
%   The external stimulus package supplies single waveforms (see
%   mabr.stim.StimulusSet); MABR decides how they are presented. This class
%   owns all three of those decisions, driven from the GUI:
%
%       ISI          spacing between successive onsets (s, onset-to-onset)
%       Repetitions  how many times each entry is presented (per entry)
%       Strategy     how entries are combined across the array
%
%   Strategies
%   ----------
%     'blocked'          one run per stimulus, each the full repetition train.
%                        Entries play in array order. Equivalent to the old
%                        one-block-per-condition behaviour.
%     'shuffled-blocks'  as 'blocked', but the order of the runs is shuffled.
%     'interleaved'      ONE run cycling A B C A B C ...; an entry drops out of
%                        later cycles once it has hit its repetition count.
%     'shuffled-cycles'  as 'interleaved', but each cycle's order is shuffled
%                        independently -- every entry still gets exactly its
%                        repetition count, with no long runs of one stimulus.
%     'shuffled'         ONE run: the whole multiset of presentations shuffled
%                        uniformly.
%
%   Every strategy is a permutation of a FIXED multiset, never probabilistic
%   sampling: each entry is presented exactly its repetition count in all five.
%   The names say "shuffled" rather than "random" for exactly that reason.
%
%   Alternating polarity
%   -------------------
%   An entry flagged alternatePolarity (see mabr.stim.StimulusSet) has its
%   successive presentations multiplied by +1, -1, +1, ... so half of them are
%   inverted. This SPLITS the entry's repetition count between the two
%   polarities -- it does not double it. Polarity is assigned per presentation
%   and travels with it through shuffling, so under a shuffled strategy the
%   inverted presentations land in shuffled positions too. renderSpec reports
%   the sign used at each onset in the spec's Polarity field.
%
%   The last three INTERMIX different stimuli inside one continuous
%   acquisition run (isIntermixed is true). MABR records which stimulus fired
%   at each onset in the rendered spec's StimulusIndex, and the controller
%   de-interleaves the recorded sweeps at save time so each stimulus ID still
%   lands in its own .abr file. Because an intermixed run cannot be stopped
%   early for one stimulus without disturbing the balance of the others,
%   online correlation-threshold advance is unavailable in those modes and the
%   run always plays to completion.
%
%   Artifact make-up
%   ----------------
%   When mabr.ArtifactPolicy.Repeat is set, the controller calls appendMakeup
%   after finalizing a run to re-present whatever that run lost to artifact.
%   Make-up runs are appended to the end of the plan (a run's play matrix is
%   rendered before streaming starts and cannot grow mid-flight), hold one
%   stimulus each, and are bounded by MakeupLimit. reset() drops them, so a
%   re-started schedule always begins from the plan build() produced.
%
%   Typical walk (driven by mabr.ui.AcqController):
%       sch = mabr.stim.Schedule(stimulusSet,cfg);
%       sch.ISI = 0.0474; sch.Strategy = 'shuffled-cycles';
%       sch.Repetitions(:) = 512;
%       sch.build();
%       r    = sch.current();
%       spec = sch.renderSpec(r);      % -> engine.prep(spec)
%       ...acquire...
%       r = sch.advance();             % [] when the plan is complete
%
%   See also mabr.stim.StimulusSet, mabr.ui.AcqController.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        Strategies = {'blocked','shuffled-blocks','interleaved','shuffled-cycles','shuffled'};
    end

    properties
        Set                             % mabr.stim.StimulusSet
        Config                          % mabr.Config
        Repetitions      (1,:) double = []      % per stimulus entry
        Strategy         (1,:) char   = 'blocked'
        ISI              (1,1) double = 1/21.1  % s, onset-to-onset
        Seed                          = []      % [] = nondeterministic shuffle
        SilencePad       (1,1) double = 0.25    % s of silence bracketing a run
        PlayerChannels   (1,2) double = [1 2]   % [DACsignal DACtiming]
        RecorderChannels (1,2) double = [1 2]   % [ADCsignal ADCtiming]
        Device           (1,:) char   = ''
        TestingFrameDelay (1,1) double = 0      % s/frame; loopback pacing, tests only

        % Ceiling on artifact make-up (see appendMakeup), as a multiple of each
        % stimulus's scheduled repetitions. 1 means a condition can at most be
        % presented twice over: enough to recover a realistic artifact rate,
        % while a permanently noisy electrode -- where every make-up sweep is
        % rejected too, asking for yet more -- still terminates.
        MakeupLimit      (1,1) double {mustBeNonnegative} = 1
    end

    properties (SetAccess = private)
        Runs        (1,:) cell = {}    % each cell: stimulus indices, in play order
        Polarities  (1,:) cell = {}    % each cell: +1/-1 per onset, same size
        IsMakeup    (1,:) logical = false(1,0)  % parallel to Runs; appended make-up?
        CurrentRun  (1,1) double = 0   % 0 = not started / complete
        RunCounts   (1,:) double = []  % presentations actually recorded, per stimulus
        MakeupUsed  (1,:) double = []  % make-up presentations appended, per stimulus
    end

    properties (Dependent)
        NumRuns
    end

    methods
        function obj = Schedule(set,cfg)
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end
            if nargin < 1 || isempty(set), set = mabr.stim.StimulusSet([],cfg); end
            obj.Set         = set;
            obj.Config      = cfg;
            obj.Repetitions = mabr.stim.Schedule.startingRepetitions(set);
            obj.RunCounts   = zeros(1,set.numStimuli);
            obj.build();
        end

        function n = get.NumRuns(obj), n = numel(obj.Runs); end

        function tf = isIntermixed(obj)
            % True when a single run mixes more than one stimulus.
            tf = mabr.stim.Schedule.strategyIntermixes(obj.Strategy);
        end

        % --- Plan construction ----------------------------------------------
        function build(obj)
            % (Re)build the run list from Repetitions + Strategy. Call after
            % changing either; reset() alone does not rebuild.
            n    = obj.Set.numStimuli;
            reps = obj.normalizedReps();

            obj.RunCounts  = zeros(1,n);
            obj.MakeupUsed = zeros(1,n);
            obj.Runs       = {};
            obj.Polarities = {};
            obj.IsMakeup   = false(1,0);
            if n == 0 || ~any(reps > 0), obj.CurrentRun = 0; return; end

            rs  = obj.stream();
            alt = obj.Set.alternatesPolarity();

            switch lower(obj.Strategy)
                case 'blocked'
                    [obj.Runs,obj.Polarities] = obj.blockRuns(1:n,reps,alt);

                case 'shuffled-blocks'
                    [obj.Runs,obj.Polarities] = obj.blockRuns(randperm(rs,n),reps,alt);

                case 'interleaved'
                    [seq,pol] = obj.cycleSequence(reps,alt,false,rs);
                    obj.Runs = {seq}; obj.Polarities = {pol};

                case 'shuffled-cycles'
                    [seq,pol] = obj.cycleSequence(reps,alt,true,rs);
                    obj.Runs = {seq}; obj.Polarities = {pol};

                case 'shuffled'
                    [seq,pol] = obj.cycleSequence(reps,alt,false,rs);
                    % One permutation applied to both, so each presentation
                    % keeps the polarity it was assigned: shuffling the order
                    % shuffles which onsets are inverted.
                    p = randperm(rs,numel(seq));
                    obj.Runs = {seq(p)}; obj.Polarities = {pol(p)};

                otherwise
                    error('mabr:stim:Schedule:strategy', ...
                        'Unknown strategy "%s". Expected one of: %s.', ...
                        obj.Strategy,strjoin(mabr.stim.Schedule.Strategies,', '));
            end

            obj.IsMakeup = false(1,numel(obj.Runs));
            obj.reset();
        end

        function reset(obj)
            % Make-up runs belong to the acquisition that produced them, not to
            % the plan, so re-starting drops them: reset() returns the schedule
            % to exactly the state build() left it in, and the make-up budget
            % starts over with it.
            m = obj.IsMakeup;
            if any(m)
                obj.Runs(m)       = [];
                obj.Polarities(m) = [];
                obj.IsMakeup(m)   = [];
            end
            obj.RunCounts(:)  = 0;
            obj.MakeupUsed(:) = 0;
            if isempty(obj.Runs), obj.CurrentRun = 0; else, obj.CurrentRun = 1; end
        end

        function r = current(obj), r = obj.CurrentRun; end

        function tf = isComplete(obj)
            tf = obj.CurrentRun == 0 || obj.CurrentRun >= obj.NumRuns;
        end

        function r = advance(obj)
            if obj.CurrentRun == 0 || obj.CurrentRun >= obj.NumRuns
                obj.CurrentRun = 0; r = [];
            else
                obj.CurrentRun = obj.CurrentRun + 1; r = obj.CurrentRun;
            end
        end

        function seq = runSequence(obj,r)
            % Stimulus index presented at each onset of run r, in order.
            if nargin < 2 || isempty(r), r = obj.CurrentRun; end
            assert(r >= 1 && r <= obj.NumRuns,'mabr:stim:Schedule:runRange', ...
                'Run index %d out of range (1..%d).',r,obj.NumRuns);
            seq = obj.Runs{r};
        end

        function pol = runPolarity(obj,r)
            % Polarity (+1/-1) applied at each onset of run r, in order.
            if nargin < 2 || isempty(r), r = obj.CurrentRun; end
            assert(r >= 1 && r <= obj.NumRuns,'mabr:stim:Schedule:runRange', ...
                'Run index %d out of range (1..%d).',r,obj.NumRuns);
            pol = obj.Polarities{r};
        end

        function recordRun(obj,r,counts)
            % counts: presentations actually acquired, indexed by stimulus.
            if isempty(counts), return; end
            obj.RunCounts = obj.RunCounts + counts(:)';
            mabr.log.vprintf(2,'Run %d recorded (%s)',r,mat2str(counts(:)'));
        end

        function added = appendMakeup(obj,counts)
            % Append run(s) re-presenting sweeps lost to artifact.
            %
            %   added = appendMakeup(counts) appends make-up presentations for
            %   each stimulus, counts(i) of stimulus i, and returns how many
            %   were actually appended (MakeupLimit can cap it below what was
            %   asked). Called by mabr.ui.AcqController at finalization when
            %   mabr.ArtifactPolicy.Repeat is set.
            %
            %   The make-up goes at the END of the plan rather than extending
            %   the run that lost the sweeps: a run's play matrix is rendered
            %   in full before the worker starts streaming it and cannot grow
            %   mid-flight. Appending also keeps every condition's first pass
            %   ahead of any second, so a session cut short still covers the
            %   whole design rather than over-sampling its early conditions.
            %
            %   One make-up run holds ONE stimulus even under an intermixed
            %   strategy: it exists to recover a specific condition's losses,
            %   and one stimulus per run keeps that accounting exact.
            added = zeros(1,obj.Set.numStimuli);
            if isempty(counts) || ~any(counts > 0), return; end

            counts = max(0,round(counts(:)'));
            if numel(counts) < numel(added), counts(end+1:numel(added)) = 0; end
            counts = counts(1:numel(added));

            reps   = obj.normalizedReps();
            alt    = obj.Set.alternatesPolarity();
            budget = floor(obj.MakeupLimit.*reps) - obj.MakeupUsed;

            for i = find(counts > 0)
                k = min(counts(i),max(0,budget(i)));
                if k < counts(i)
                    mabr.log.vprintf(0,1, ...
                        ['Artifact make-up for stimulus %d capped at %d of %d ' ...
                         'requested presentations (limit %g x %d scheduled). ' ...
                         'Artifacts are outpacing recovery — check the electrode.'], ...
                        i,k,counts(i),obj.MakeupLimit,reps(i));
                end
                if k <= 0, continue; end

                obj.Runs{end+1}       = repmat(i,1,k);
                obj.Polarities{end+1} = mabr.stim.Schedule.polaritySeries(k,alt(i));
                obj.IsMakeup(end+1)   = true;
                obj.MakeupUsed(i)     = obj.MakeupUsed(i) + k;
                added(i)              = k;

                mabr.log.vprintf(1,'Appended make-up run %d: %d x stimulus %d', ...
                    numel(obj.Runs),k,i);
            end
        end

        % --- Rendering --------------------------------------------------------
        function spec = renderSpec(obj,r)
            % Build the acquisition play-matrix spec for run r.
            if nargin < 2 || isempty(r), r = obj.CurrentRun; end
            seq = obj.runSequence(r);
            pol = obj.runPolarity(r);

            Fs     = obj.Set.SampleRate;
            period = round(Fs*obj.ISI);
            assert(period >= 1,'mabr:stim:Schedule:isi', ...
                'ISI (%g s) is shorter than one sample at %g Hz.',obj.ISI,Fs);

            nPres  = numel(seq);
            onsets = (0:nPres-1)'.*period + 1;

            % The run must be long enough to hold the last stimulus in full.
            tail = 0;
            for k = 1:nPres
                tail = max(tail,numel(obj.Set.signal(seq(k))));
            end
            N = onsets(end) + tail - 1;

            % Check the run fits the ring buffer BEFORE allocating anything: an
            % over-ambitious plan is many gigabytes, and running out of memory
            % here would mask the real problem behind a MATLAB:nomem.
            P     = round(obj.SilencePad*Fs);
            fl    = obj.Config.frameLength;
            total = ceil((N + 2*P)/fl)*fl;
            cap   = obj.Config.maxInputBufferLength;
            assert(total <= cap,'mabr:stim:Schedule:tooLong', ...
                ['Run %d needs %d samples (%.1f s) but the ring buffer holds %d ' ...
                 '(%.1f s). Reduce repetitions, shorten the ISI, or use a ' ...
                 'blocked strategy so each run covers one stimulus.'], ...
                r,total,total/Fs,cap,cap/Fs);

            longest = obj.Set.maxDuration()*Fs;
            if longest > period
                mabr.log.vprintf(0,1, ...
                    ['Stimulus (%.2f ms) is longer than the ISI (%.2f ms); ' ...
                     'presentations overlap and are summed.'], ...
                    1e3*longest/Fs,1e3*period/Fs);
            end

            samples = zeros(N,1,'single');
            timing  = zeros(N,1,'single');
            for k = 1:nPres
                i  = seq(k);
                w  = obj.Set.signal(i);
                i0 = onsets(k);
                i1 = i0 + numel(w) - 1;
                % Overlapping presentations are summed rather than clipped; the
                % GUI warns about this up front and the log line above records it.
                samples(i0:i1) = samples(i0:i1) + pol(k).*w;

                t = obj.Set.timing(i);
                if isempty(t)
                    timing(i0) = 1;
                else
                    timing(i0:i1) = max(timing(i0:i1),t);
                end
            end

            y = [samples timing];

            % bracket with silence for device settling / response tail
            if P > 0
                y      = [zeros(P,2,'single'); y; zeros(P,2,'single')];
                onsets = onsets + P;
            end

            % pad to an integer number of frames (to `total`, already checked
            % against the ring-buffer capacity above)
            rem_ = mod(size(y,1),fl);
            if rem_ > 0, y = [y; zeros(fl-rem_,2,'single')]; end

            spec = struct();
            spec.PlayMatrix        = y;
            spec.SampleRate        = Fs;
            spec.ExpectedOnsets    = onsets;
            spec.StimulusIndex     = seq(:);      % which stimulus at each onset
            spec.Polarity          = pol(:);      % +1/-1 applied at each onset
            spec.PlayerChannels    = obj.PlayerChannels;
            spec.RecorderChannels  = obj.RecorderChannels;
            spec.TestingFrameDelay = obj.TestingFrameDelay;
            spec.Meta              = obj.Set.meta(seq(1));
            if ~isempty(obj.Device), spec.Device = obj.Device; end
        end

        % --- Reporting --------------------------------------------------------
        function s = summary(obj)
            % Plan overview for the GUI: counts and estimated wall-clock time.
            reps = obj.normalizedReps();
            s = struct();
            s.numStimuli   = obj.Set.numStimuli;
            s.numRuns      = obj.NumRuns;
            s.repetitions  = reps;
            s.presentations = sum(reps);
            s.intermixed   = obj.isIntermixed();

            s.duration = 0;
            for r = 1:obj.NumRuns
                n = numel(obj.Runs{r});
                s.duration = s.duration + (n-1)*obj.ISI + obj.Set.maxDuration() ...
                             + 2*obj.SilencePad;
            end
        end

        function tf = overlaps(obj)
            % True when the longest stimulus does not fit inside the ISI.
            tf = obj.Set.numStimuli > 0 && obj.Set.maxDuration() > obj.ISI;
        end
    end

    methods (Access = private)
        function reps = normalizedReps(obj)
            n    = obj.Set.numStimuli;
            reps = obj.Repetitions;
            if isempty(reps)
                reps = zeros(1,n);
            elseif isscalar(reps)
                reps = repmat(reps,1,n);
            end
            if numel(reps) < n, reps(end+1:n) = 0; end
            reps = max(0,round(reps(1:n)));
        end

        function rs = stream(obj)
            % A private RandStream so building a plan never perturbs global rng
            % (and an explicit Seed makes the plan exactly reproducible).
            if isempty(obj.Seed)
                rs = RandStream('twister','Seed','shuffle');
            else
                rs = RandStream('twister','Seed',obj.Seed);
            end
        end

        function [runs,pols] = blockRuns(~,order,reps,alt)
            runs = {}; pols = {};
            for i = order
                if reps(i) <= 0, continue; end
                runs{end+1} = repmat(i,1,reps(i));  %#ok<AGROW>
                pols{end+1} = mabr.stim.Schedule.polaritySeries(reps(i),alt(i)); %#ok<AGROW>
            end
        end

        function [seq,pol] = cycleSequence(~,reps,alt,shuffleWithin,rs)
            % Walk cycles of the still-owed stimuli. An entry leaves the cycle
            % once it has been scheduled its full repetition count, so unequal
            % repetition counts stay spread out instead of clumping at the end.
            %
            % Cycle c is, by construction, the c-th presentation of every entry
            % still due, so the alternating polarity of an entry is just the
            % sign of the cycle it appears in.
            seq = []; pol = [];
            for c = 1:max(reps)
                due = find(reps >= c);
                p   = ones(1,numel(due));
                if mod(c,2) == 0, p(alt(due)) = -1; end
                if shuffleWithin
                    k = randperm(rs,numel(due));
                    due = due(k); p = p(k);
                end
                seq = [seq due]; pol = [pol p]; %#ok<AGROW>
            end
        end
    end

    methods (Static)
        function tf = strategyIntermixes(strategy)
            tf = ismember(lower(strategy),{'interleaved','shuffled-cycles','shuffled'});
        end

        function p = polaritySeries(n,alternates)
            % +1/-1 for n successive presentations of one entry. Alternating
            % splits the SAME n presentations between the two polarities
            % (ceil(n/2) normal, floor(n/2) inverted) -- it never adds any.
            p = ones(1,n);
            if alternates, p(2:2:end) = -1; end
        end

        function reps = startingRepetitions(set)
            % Per-entry Repetitions where the source supplied one, else 512.
            reps = set.defaultRepetitions();
            reps(reps <= 0) = 512;
        end
    end
end
