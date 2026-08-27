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
%   Fixed and randomized ISI
%   ------------------------
%   ISIMode picks which of two settings decides the spacing:
%
%     'fixed'   every interval is ISI. Onsets land on a strict grid.
%     'random'  each interval is drawn independently and uniformly from
%               ISIRange = [min max] seconds. The draw happens in renderSpec,
%               once per run, so a plan built and rendered twice is not
%               expected to be sample-identical unless Seed is set.
%
%   Randomizing decorrelates the presentation rate from line noise and from
%   any periodicity in the response itself, which a strict grid can otherwise
%   average up alongside the signal. It costs the run its exact duration --
%   summary() reports the EXPECTED duration, mean(ISIRange) per interval --
%   and nothing more: the timing channel still carries one pulse per onset, so
%   sweep extraction, the sweep window, and every downstream metric are
%   indifferent to how evenly the onsets are spaced. MinISI, not the mean, is
%   what has to clear the stimulus duration (see overlaps) and the sweep
%   window, because the shortest interval drawn is the one that collides.
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
%     'custom'           the order YOUR function returns. StrategyFcn is
%                        called once per build with a struct describing the
%                        design (mabr.stim.strategy.context) and returns the
%                        run(s) to present; see mabr.stim.strategy.
%                        custom_template for the contract and a worked
%                        example. Left unset, build() refuses rather than
%                        falling back to a built-in order.
%
%   The first five are permutations of a FIXED multiset, never probabilistic
%   sampling: each entry is presented exactly its repetition count in all of
%   them. The names say "shuffled" rather than "random" for exactly that
%   reason. A 'custom' strategy is EXPECTED to hold to the same invariant and
%   is warned when it does not (mabr.stim.strategy.normalize), but is not
%   refused -- departing on purpose is a legitimate reason to write one.
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
%   'interleaved', 'shuffled-cycles' and 'shuffled' INTERMIX different stimuli
%   inside one continuous acquisition run (isIntermixed is true), and so may a
%   'custom' one -- which is why isIntermixed asks a built custom plan whether
%   any of its runs actually holds more than one stimulus, rather than
%   answering from the strategy's name. MABR records which stimulus fired
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
%   Make-up runs are appended to the end of the plan (a run's presentation
%   plan is fixed before streaming starts and cannot grow mid-flight), hold one
%   stimulus each, and are bounded by MakeupLimit. reset() drops them, so a
%   re-started schedule always begins from the plan build() produced, and
%   dropPendingMakeup() drops just the ones not yet reached — what the
%   controller calls when the user turns Repeat off mid-schedule.
%
%   Manual repeat
%   -------------
%   repeatRun appends the same shape of run -- one stimulus, its scheduled
%   repetition count -- but on the user's direct request (the GUI's Repeat
%   button, mabr.ui.AcqController.repeatLastBlock) rather than as artifact
%   recovery, so it is NOT bounded by MakeupLimit. It is tracked in IsRepeat,
%   a separate flag from IsMakeup, so dropPendingMakeup (which only withdraws
%   make-up runs) cannot mistake one for the other; reset() drops both kinds
%   alike, since neither belongs to the plan build() produced.
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
        Strategies = {'blocked','shuffled-blocks','interleaved','shuffled-cycles','shuffled','custom'};
        ISIModes   = {'fixed','random'};
    end

    properties
        Set                             % mabr.stim.StimulusSet
        Config                          % mabr.Config
        Repetitions      (1,:) double = []      % per stimulus entry
        Strategy         (1,:) char   = 'blocked'

        % The user's own ordering function, used when Strategy is 'custom'.
        % Called ONCE per build with the canonical context struct
        % (mabr.stim.strategy.context) and returning the run(s) to present;
        % mabr.stim.strategy.normalize reads whatever shape it returned. Left
        % empty under 'custom', build() refuses rather than quietly falling
        % back to a built-in order -- a session presented in an order nobody
        % chose is worse than one that will not start.
        StrategyFcn                   = []

        % Tuning knobs passed through into the context, the way AdvanceParams
        % are passed to an advance criterion. Anything here reaches the
        % strategy under its own field name.
        StrategyParams   (1,1) struct = struct()

        ISI              (1,1) double = 1/21.1  % s, onset-to-onset ('fixed')

        % Which of ISI / ISIRange decides the spacing. Kept as a separate
        % switch rather than inferred from a degenerate range, so turning
        % randomization off and on again cannot lose the range it was set to
        % (the GUI's checkbox is exactly this property).
        ISIMode          (1,:) char {mustBeMember(ISIMode,{'fixed','random'})} = 'fixed'

        % [min max] s, onset-to-onset, drawn uniformly per interval ('random').
        ISIRange         (1,2) double {mustBePositive,mustBeFinite} = [1 1]/21.1

        Seed                          = []      % [] = nondeterministic shuffle
        SilencePad       (1,1) double = 0.25    % s of silence bracketing a run
        PlayerChannels   (1,2) double = [1 2]   % [DACsignal DACtiming]
        RecorderChannels (1,2) double = [1 2]   % [ADCsignal ADCtiming]
        Device           (1,:) char   = ''

        % Playback + timing pulse, nothing recorded (mabr.AudioSettings.
        % StimulationOnly). Unlike Testing -- which is baked into the worker at
        % parfeval time -- this rides per-block in the render spec, because
        % worker_loop's prepare_device rebuilds the device on every Prep. The
        % play matrix is unaffected: both columns are still emitted, since the
        % timing pulse is as much an output as the signal.
        StimulationOnly  (1,1) logical = false

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
        IsRepeat    (1,:) logical = false(1,0)  % parallel to Runs; user-requested repeat?
        CurrentRun  (1,1) double = 0   % 0 = not started / complete
        RunCounts   (1,:) double = []  % presentations actually recorded, per stimulus
        MakeupUsed  (1,:) double = []  % make-up presentations appended, per stimulus
    end

    properties (Dependent)
        NumRuns
        MeanISI     % s: the interval a duration estimate should be built on
        MinISI      % s: the shortest interval that can occur -- the worst case
    end

    methods
        function obj = Schedule(set,cfg)
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end
            if nargin < 1 || isempty(set), set = mabr.stim.StimulusSet([],cfg); end
            % One clock, checked at the point a plan is built rather than
            % discovered when the worker opens the device at one rate and the
            % ring buffer is windowed at another. renderSpec sends the SET's
            % rate to the device while mabr.ui.AcqController decimates by the
            % CONFIG's, so a mismatch here is not a rounding problem -- it is
            % two different clocks, and every latency the session reports would
            % be wrong by their ratio. Reached when the audio device's sample
            % rate is changed under a bank that cannot be regenerated at the
            % new one (see mabr.ui.App.retuneStimuli).
            assert(set.numStimuli == 0 || set.SampleRate == cfg.DACSampleRate, ...
                'mabr:stim:Schedule:sampleRate', ...
                ['The stimulus bank is rendered at %g Hz but the device is set to ' ...
                 '%g Hz. Reload or rebuild the bank at %g Hz, or set the device ' ...
                 'back to %g Hz in Settings > Audio Device (ASIO).'], ...
                set.SampleRate,cfg.DACSampleRate,cfg.DACSampleRate,set.SampleRate);
            obj.Set         = set;
            obj.Config      = cfg;
            obj.Repetitions = mabr.stim.Schedule.startingRepetitions(set);
            obj.RunCounts   = zeros(1,set.numStimuli);
            obj.build();
        end

        function n = get.NumRuns(obj), n = numel(obj.Runs); end

        function v = get.MeanISI(obj)
            if obj.isRandomISI(), v = mean(obj.ISIRange); else, v = obj.ISI; end
        end

        function v = get.MinISI(obj)
            if obj.isRandomISI(), v = obj.ISIRange(1); else, v = obj.ISI; end
        end

        function set.ISIRange(obj,v)
            % Ascending, and never silently sorted: [50 20] is a mistake about
            % which bound is which, and quietly swapping it would hide that.
            assert(v(2) >= v(1),'mabr:stim:Schedule:isiRange', ...
                'ISI range must be [min max] with max >= min (got [%g %g] s).',v(1),v(2));
            obj.ISIRange = v;
        end

        function tf = isRandomISI(obj)
            % True when each interval is drawn from ISIRange rather than fixed
            % at ISI.
            tf = strcmpi(obj.ISIMode,'random');
        end

        function tf = isIntermixed(obj)
            % True when a single run mixes more than one stimulus.
            %
            % For the five built-in strategies the name settles it. For
            % 'custom' it cannot -- whether a user's plan intermixes is a
            % property of the runs it produced, not of the fact that a
            % function produced them -- so the built plan is asked directly.
            % That is the truthful answer and the one everything downstream
            % needs: mabr.ui.AcqController gates early stop, the repeat
            % button, and the live view's correlation bar on it, and a custom
            % strategy that emits one stimulus per run should keep all three.
            % With no plan built yet, the static's conservative `true` stands.
            if strcmpi(obj.Strategy,'custom') && ~isempty(obj.Runs)
                tf = any(cellfun(@(v) numel(unique(v)) > 1,obj.Runs));
                return
            end
            tf = mabr.stim.Schedule.strategyIntermixes(obj.Strategy);
        end

        function s = strategyLabel(obj)
            % How the strategy should be NAMED in a record of the session --
            % the .stimlog's Presentation.Strategy, a log line, a status line.
            % 'custom' alone does not say which custom, and a file recording
            % only that the order was "custom" cannot be reproduced from.
            s = obj.Strategy;
            if strcmpi(s,'custom') && ~isempty(obj.StrategyFcn)
                s = ['custom: ' mabr.stim.Schedule.fcnName(obj.StrategyFcn)];
            end
        end

        % --- Plan construction ----------------------------------------------
        function build(obj)
            % (Re)build the run list from Repetitions + Strategy. Call after
            % changing either; reset() alone does not rebuild.
            n    = obj.Set.numStimuli;
            reps = obj.normalizedRepetitions();

            obj.RunCounts  = zeros(1,n);
            obj.MakeupUsed = zeros(1,n);
            obj.Runs       = {};
            obj.Polarities = {};
            obj.IsMakeup   = false(1,0);
            obj.IsRepeat   = false(1,0);
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

                case 'custom'
                    [obj.Runs,obj.Polarities] = obj.customRuns(rs);

                otherwise
                    error('mabr:stim:Schedule:strategy', ...
                        'Unknown strategy "%s". Expected one of: %s.', ...
                        obj.Strategy,strjoin(mabr.stim.Schedule.Strategies,', '));
            end

            obj.IsMakeup = false(1,numel(obj.Runs));
            obj.IsRepeat = false(1,numel(obj.Runs));
            obj.reset();
        end

        function reset(obj)
            % Make-up runs and user-requested repeat runs (see repeatRun)
            % belong to the acquisition that produced them, not to the plan, so
            % re-starting drops both: reset() returns the schedule to exactly
            % the state build() left it in, and the make-up budget starts over
            % with it.
            m = obj.IsMakeup | obj.IsRepeat;
            if any(m)
                obj.Runs(m)       = [];
                obj.Polarities(m) = [];
                obj.IsMakeup(m)   = [];
                obj.IsRepeat(m)   = [];
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
            %   the run that lost the sweeps: a run's presentation plan is
            %   fixed before the worker starts streaming it and cannot grow
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

            reps   = obj.normalizedRepetitions();
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
                obj.IsRepeat(end+1)   = false;
                obj.MakeupUsed(i)     = obj.MakeupUsed(i) + k;
                added(i)              = k;

                mabr.log.vprintf(1,'Appended make-up run %d: %d x stimulus %d', ...
                    numel(obj.Runs),k,i);
            end
        end

        function dropped = dropPendingMakeup(obj)
            % Discard make-up runs that have not started yet.
            %
            %   dropped = dropPendingMakeup() removes every make-up run after
            %   the current one and returns how many runs were removed. The
            %   budget they consumed is refunded, so turning make-up back on
            %   later starts from the same MakeupLimit headroom as before.
            %
            %   Called by mabr.ui.AcqController when the user clears
            %   ArtifactPolicy.Repeat mid-schedule: the queued make-up runs
            %   were appended on the old policy's authority, and presenting
            %   them anyway would ignore the instruction just given. Runs
            %   already played are untouched — their data exists.
            dropped = 0;
            % CurrentRun == 0 means the schedule has not started or has
            % finished; either way nothing is pending, and the make-up runs
            % still listed are ones that were played. reset() is what clears
            % those, at the start of the next acquisition.
            if isempty(obj.Runs) || obj.CurrentRun == 0, return; end
            m = obj.IsMakeup;
            m(1:min(obj.CurrentRun,numel(m))) = false;   % keep the current run
            if ~any(m), return; end

            for r = find(m)
                i = obj.Runs{r}(1);      % a make-up run holds one stimulus
                obj.MakeupUsed(i) = max(0,obj.MakeupUsed(i) - numel(obj.Runs{r}));
            end
            obj.Runs(m)       = [];
            obj.Polarities(m) = [];
            obj.IsMakeup(m)   = [];
            obj.IsRepeat(m)   = [];
            dropped           = sum(m);

            mabr.log.vprintf(1,'Dropped %d pending artifact make-up run(s).',dropped);
        end

        function n = repeatRun(obj,stimIndex)
            % Append one more full run of stimIndex, at its scheduled
            % repetition count -- the user's direct "run this again" request
            % (mabr.ui.AcqController.repeatLastBlock), NOT a recovery of sweeps
            % an artifact took. Independent of MakeupLimit, which bounds
            % appendMakeup only.
            %
            % Only sensible when a run holds a single stimulus, i.e. a blocked
            % strategy: mabr.ui.AcqController.canRepeat gates the GUI button on
            % isIntermixed() and never records a stimulus to repeat for an
            % intermixed run.
            assert(stimIndex >= 1 && stimIndex <= obj.Set.numStimuli, ...
                'mabr:stim:Schedule:repeatRange', ...
                'Stimulus index %d out of range (1..%d).',stimIndex,obj.Set.numStimuli);
            reps = obj.normalizedRepetitions();
            n    = reps(stimIndex);
            assert(n > 0,'mabr:stim:Schedule:repeatZero', ...
                'Stimulus %d has 0 scheduled repetitions -- nothing to repeat.',stimIndex);

            alt = obj.Set.alternatesPolarity();
            obj.Runs{end+1}       = repmat(stimIndex,1,n);
            obj.Polarities{end+1} = mabr.stim.Schedule.polaritySeries(n,alt(stimIndex));
            obj.IsMakeup(end+1)   = false;
            obj.IsRepeat(end+1)   = true;

            mabr.log.vprintf(1,'Appended repeat run %d: %d x stimulus %d (user requested).', ...
                numel(obj.Runs),n,stimIndex);
        end

        function resumeAt(obj,r)
            % Point the plan at run r, so advance() continues normally from
            % there. Needed after repeatRun appends a run onto a schedule that
            % had already reached SchedComplete (CurrentRun == 0): appending
            % alone does not restart automatic advancement, since nothing calls
            % advance() again on its own once the plan was walked to its end.
            assert(r >= 1 && r <= obj.NumRuns,'mabr:stim:Schedule:runRange', ...
                'Run index %d out of range (1..%d).',r,obj.NumRuns);
            obj.CurrentRun = r;
        end

        % --- Rendering --------------------------------------------------------
        function spec = renderSpec(obj,r)
            % Build the acquisition play-matrix spec for run r.
            if nargin < 2 || isempty(r), r = obj.CurrentRun; end
            seq = obj.runSequence(r);
            pol = obj.runPolarity(r);

            Fs     = obj.Set.SampleRate;
            nPres  = numel(seq);

            % One interval before each presentation after the first, so the
            % onsets are a cumulative sum rather than a multiple of a period:
            % under 'random' no two gaps need be the same.
            periods = obj.onsetPeriods(nPres,Fs);
            onsets  = [1; 1 + cumsum(periods)];

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

            % The shortest interval is what collides, so a randomized run is
            % judged on the bottom of its range, not its mean.
            longest   = obj.Set.maxDuration()*Fs;
            minPeriod = round(Fs*obj.MinISI);
            if longest > minPeriod
                if obj.isRandomISI(), what = 'shortest ISI in the range'; else, what = 'ISI'; end
                mabr.log.vprintf(0,1, ...
                    ['Stimulus (%.2f ms) is longer than the %s (%.2f ms); ' ...
                     'presentations overlap and are summed.'], ...
                    1e3*longest/Fs,what,1e3*minPeriod/Fs);
            end

            % Nothing is allocated here. The run is described -- the stimuli
            % it presents, where, and with what sign -- and the worker
            % synthesizes each frame from that as the device is ready for it
            % (mabr.stim.PlayPlan; overlapping presentations are summed there
            % exactly as a whole-matrix render would, and the GUI warns about
            % the overlap up front). So a run costs the client the size of
            % its bank, not of its duration, and the Prep message the same.
            %
            % `total` already brackets the run in SilencePad (2P) and rounds it
            % up to whole frames -- the padding the matrix used to carry.
            onsets  = onsets + P;                 % silence bracket in front
            present = unique(seq,'stable');
            [~,loc] = ismember(seq,present);      % bank index -> plan index
            signals = arrayfun(@(u) obj.Set.signal(u),present,'UniformOutput',false);
            timings = arrayfun(@(u) obj.Set.timing(u),present,'UniformOutput',false);
            plan    = mabr.stim.PlayPlan(signals,timings,onsets,loc(:),pol(:),total);

            spec = struct();
            spec.Plan              = plan;
            spec.SampleRate        = Fs;
            spec.ExpectedOnsets    = onsets;
            spec.StimulusIndex     = seq(:);      % which stimulus at each onset
            spec.Polarity          = pol(:);      % +1/-1 applied at each onset
            spec.PlayerChannels    = obj.PlayerChannels;
            spec.RecorderChannels  = obj.RecorderChannels;
            spec.StimulationOnly   = obj.StimulationOnly;
            spec.TestingFrameDelay = obj.TestingFrameDelay;
            spec.Meta              = obj.Set.meta(seq(1));
            if ~isempty(obj.Device), spec.Device = obj.Device; end
        end

        % --- Reporting --------------------------------------------------------
        function s = summary(obj)
            % Plan overview for the GUI: counts and estimated wall-clock time.
            reps = obj.normalizedRepetitions();
            s = struct();
            s.numStimuli   = obj.Set.numStimuli;
            s.numRuns      = obj.NumRuns;
            s.repetitions  = reps;
            s.presentations = sum(reps);
            s.intermixed   = obj.isIntermixed();

            s.isiMode = obj.ISIMode;
            s.isi     = obj.MeanISI;

            % Under 'random' this is an EXPECTED duration: each interval
            % averages mean(ISIRange), and a finite run lands near it rather
            % than on it.
            s.duration = 0;
            for r = 1:obj.NumRuns
                n = numel(obj.Runs{r});
                s.duration = s.duration + (n-1)*obj.MeanISI + obj.Set.maxDuration() ...
                             + 2*obj.SilencePad;
            end
        end

        function tf = overlaps(obj)
            % True when the longest stimulus does not fit inside the shortest
            % interval that can occur -- which under 'random' is the bottom of
            % the range, not its mean: one short draw is enough to overlap.
            tf = obj.Set.numStimuli > 0 && obj.Set.maxDuration() > obj.MinISI;
        end

        function reps = normalizedRepetitions(obj)
            % Repetitions as the plan actually uses them: a scalar expanded
            % over the bank, a short vector zero-filled, negatives clamped and
            % everything rounded. Public because it is half of what a custom
            % strategy is handed (mabr.stim.strategy.context) -- the count it
            % is expected to permute -- and reading Repetitions raw would give
            % it the un-normalized form.
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
            % The schedule's own RandStream, so building a plan never perturbs
            % global rng (and an explicit Seed makes the plan exactly
            % reproducible). A FRESH stream each call: build() takes one and
            % passes that same one on, rather than letting a second caller
            % re-seed and draw the identical numbers.
            if isempty(obj.Seed)
                rs = RandStream('twister','Seed','shuffle');
            else
                rs = RandStream('twister','Seed',obj.Seed);
            end
        end
    end

    methods (Access = private)
        function p = onsetPeriods(obj,nPres,Fs)
            % The nPres-1 onset-to-onset intervals of a run, in samples.
            if obj.isRandomISI()
                lo = obj.ISIRange(1); hi = obj.ISIRange(2);
                assert(round(Fs*lo) >= 1,'mabr:stim:Schedule:isi', ...
                    'Shortest ISI in the range (%g s) is shorter than one sample at %g Hz.', ...
                    lo,Fs);
                % Drawn from the schedule's own RandStream for the same reason
                % the shuffles are: building or rendering a plan must not
                % perturb the global rng, and an explicit Seed must make the
                % whole plan -- order AND timing -- reproducible.
                rs = obj.stream();
                p  = round(Fs.*(lo + (hi-lo).*rand(rs,max(0,nPres-1),1)));
                p  = max(1,p);
            else
                period = round(Fs*obj.ISI);
                assert(period >= 1,'mabr:stim:Schedule:isi', ...
                    'ISI (%g s) is shorter than one sample at %g Hz.',obj.ISI,Fs);
                p = repmat(period,max(0,nPres-1),1);
            end
        end

        function [runs,pols] = customRuns(obj,rs)
            % Call the user's ordering function and read what it returned.
            %
            % The refusal is deliberate and comes first: 'custom' with no
            % function is not a strategy MABR can guess at, and falling back
            % to blocked would present a whole session in an order nobody
            % chose while the GUI still said "custom".
            assert(isa(obj.StrategyFcn,'function_handle'), ...
                'mabr:stim:Schedule:noStrategyFcn', ...
                ['Strategy is "custom" but StrategyFcn is not set. Assign the ' ...
                 'ordering function (see mabr.stim.strategy.custom_template), ' ...
                 'or pick one of: %s.'], ...
                strjoin(setdiff(mabr.stim.Schedule.Strategies,{'custom'},'stable'),', '));

            ctx = mabr.stim.strategy.context(obj,obj.StrategyParams,rs);
            name = mabr.stim.Schedule.fcnName(obj.StrategyFcn);

            % A user function's error is re-thrown named, and as a Schedule
            % error rather than whatever it happened to throw: the plan simply
            % does not exist, and the caller (refreshPlan's preview, onStart)
            % needs to say WHICH function failed -- the stack alone does not,
            % once the handle came from a file the GUI resolved.
            try
                out = obj.StrategyFcn(ctx);
            catch me
                error('mabr:stim:Schedule:strategyFcn', ...
                    'Custom strategy "%s" errored: %s',name,me.message);
            end

            [runs,pols] = mabr.stim.strategy.normalize(out,ctx);
            mabr.log.vprintf(1,'Custom strategy "%s" planned %d run(s), %d presentations.', ...
                name,numel(runs),sum(cellfun(@numel,runs)));
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
            % Answered from the NAME alone, which is all a caller holding no
            % plan has -- the GUI deciding whether to offer early stop before
            % anything is built. 'custom' is therefore true: whether a user's
            % plan intermixes cannot be known from its name, and assuming it
            % does not would offer an early stop that truncates whichever
            % stimuli fell last. A built schedule knows better and says so --
            % see the isIntermixed METHOD, which is the authority once a plan
            % exists.
            tf = ismember(lower(strategy), ...
                {'interleaved','shuffled-cycles','shuffled','custom'});
        end

        function s = fcnName(fcn)
            % A function handle's name for a log line or a saved record.
            % func2str puts an @ on a simple handle and returns the whole body
            % of an anonymous one; neither is what a record wants to read.
            if ~isa(fcn,'function_handle'), s = ''; return, end
            s = func2str(fcn);
            if startsWith(s,'@('), s = 'anonymous'; return, end
            s = strrep(s,'@','');
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
