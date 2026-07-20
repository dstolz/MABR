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
%   The last three INTERMIX different stimuli inside one continuous
%   acquisition run (isIntermixed is true). MABR records which stimulus fired
%   at each onset in the rendered spec's StimulusIndex, and the controller
%   de-interleaves the recorded sweeps at save time so each stimulus ID still
%   lands in its own .abr file. Because an intermixed run cannot be stopped
%   early for one stimulus without disturbing the balance of the others,
%   online correlation-threshold advance is unavailable in those modes and the
%   run always plays to completion.
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
    end

    properties (SetAccess = private)
        Runs        (1,:) cell = {}    % each cell: stimulus indices, in play order
        CurrentRun  (1,1) double = 0   % 0 = not started / complete
        RunCounts   (1,:) double = []  % presentations actually recorded, per stimulus
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

            obj.RunCounts = zeros(1,n);
            obj.Runs      = {};
            if n == 0 || ~any(reps > 0), obj.CurrentRun = 0; return; end

            rs = obj.stream();

            switch lower(obj.Strategy)
                case 'blocked'
                    obj.Runs = obj.blockRuns(1:n,reps);

                case 'shuffled-blocks'
                    obj.Runs = obj.blockRuns(randperm(rs,n),reps);

                case 'interleaved'
                    obj.Runs = {obj.cycleSequence(reps,false,rs)};

                case 'shuffled-cycles'
                    obj.Runs = {obj.cycleSequence(reps,true,rs)};

                case 'shuffled'
                    seq = obj.cycleSequence(reps,false,rs);
                    obj.Runs = {seq(randperm(rs,numel(seq)))};

                otherwise
                    error('mabr:stim:Schedule:strategy', ...
                        'Unknown strategy "%s". Expected one of: %s.', ...
                        obj.Strategy,strjoin(mabr.stim.Schedule.Strategies,', '));
            end

            obj.reset();
        end

        function reset(obj)
            obj.RunCounts(:) = 0;
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

        function recordRun(obj,r,counts)
            % counts: presentations actually acquired, indexed by stimulus.
            if isempty(counts), return; end
            obj.RunCounts = obj.RunCounts + counts(:)';
            mabr.log.vprintf(2,'Run %d recorded (%s)',r,mat2str(counts(:)'));
        end

        % --- Rendering --------------------------------------------------------
        function spec = renderSpec(obj,r)
            % Build the acquisition play-matrix spec for run r.
            if nargin < 2 || isempty(r), r = obj.CurrentRun; end
            seq = obj.runSequence(r);

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
                samples(i0:i1) = samples(i0:i1) + w;

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

        function runs = blockRuns(~,order,reps)
            runs = {};
            for i = order
                if reps(i) > 0, runs{end+1} = repmat(i,1,reps(i)); end %#ok<AGROW>
            end
        end

        function seq = cycleSequence(~,reps,shuffleWithin,rs)
            % Walk cycles of the still-owed stimuli. An entry leaves the cycle
            % once it has been scheduled its full repetition count, so unequal
            % repetition counts stay spread out instead of clumping at the end.
            seq = [];
            for c = 1:max(reps)
                due = find(reps >= c);
                if shuffleWithin, due = due(randperm(rs,numel(due))); end
                seq = [seq due]; %#ok<AGROW>
            end
        end
    end

    methods (Static)
        function tf = strategyIntermixes(strategy)
            tf = ismember(lower(strategy),{'interleaved','shuffled-cycles','shuffled'});
        end

        function reps = startingRepetitions(set)
            % Per-entry Repetitions where the source supplied one, else 512.
            reps = set.defaultRepetitions();
            reps(reps <= 0) = 512;
        end
    end
end
