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
%   Named for the acquisition designs they implement -- conventional and
%   interleaved, each in a fixed order or a shuffled one -- plus a fully
%   shuffled order and the user's own:
%
%     'conventional'          one run per stimulus, each the full repetition
%                             train. Entries play in bank order, or in the
%                             order OrderBy asks for -- see "Order" below.
%     'conventional-shuffled' as 'conventional', but the order of the runs is
%                             shuffled.
%     'interleaved'           ONE run of repeated cycles through the bank,
%                             every cycle in the same order: bank order, or the
%                             order OrderBy asks for. Frequency as listed then
%                             Level ascending walks one frequency at a time,
%                             its levels climbing (a series of level ramps);
%                             Level ascending alone takes every frequency at
%                             each level in turn (a series of plateaus).
%     'interleaved-random'    ONE run of repeated cycles, each cycle's order
%                             shuffled independently -- every entry still gets
%                             exactly its repetition count, with no long runs
%                             of one stimulus.
%     'shuffled'              ONE run: the whole multiset of presentations
%                             shuffled uniformly, with no cycle structure.
%     'custom'                the order YOUR function returns. StrategyFcn is
%                             called once per build with a struct describing
%                             the design (mabr.stim.strategy.context) and
%                             returns the run(s) to present; see mabr.stim.
%                             strategy.custom_template for the contract and a
%                             worked example. Left unset, build() refuses
%                             rather than falling back to a built-in order.
%
%   In every cycled strategy an entry drops out of later cycles once it has
%   hit its repetition count; the entries still due keep the cycle's order
%   among themselves.
%
%   Order ('conventional' and 'interleaved')
%   ----------------------------------------
%   OrderBy names the stimulus parameter(s) the bank is sorted by, most
%   significant first, and OrderDirection says which way each one goes.
%   Under 'conventional' that is the order the runs play in; under
%   'interleaved', the order every cycle walks the bank in:
%
%     'ascending'   low to high
%     'descending'  high to low
%     'listed'      grouped by value, the groups in the order the bank first
%                   lists them -- which keeps a frequency order that was
%                   chosen on purpose (most important first, say)
%
%       sch.OrderBy = 'Level';  sch.OrderDirection = 'descending';
%           every stimulus at the loudest level, then every one at the next
%
%       sch.OrderBy        = {'Frequency','Level'};
%       sch.OrderDirection = {'listed','descending'};
%           the threshold series: one frequency at a time, in the bank's own
%           order, loudest first within each
%
%   Entries tied on every parameter named keep their bank order, in either
%   direction, so reversing a direction reverses that parameter and nothing
%   else. A name the bank does not vary is skipped, never refused. Only
%   'conventional' and 'interleaved' read the pair (strategyTakesOrder): the
%   shuffled strategies decide their own order, and so does a 'custom' one.
%
%   The first five are permutations of a FIXED multiset, never probabilistic
%   sampling: each entry is presented exactly its repetition count in all of
%   them -- 'interleaved-random' included, whose "random" is the order within
%   a cycle, not what gets presented. A 'custom' strategy is EXPECTED to hold
%   to the same invariant and is warned when it does not (mabr.stim.strategy.
%   normalize), but is not refused -- departing on purpose is a legitimate
%   reason to write one.
%
%   Retired names are still accepted and translated on assignment (see
%   canonicalStrategy), because configuration files and last-session prefs
%   saved with them carry them: 'blocked', 'shuffled-blocks' and
%   'shuffled-cycles' from before the strategies were named for their
%   designs, and 'interleaved-ramp' / 'interleaved-plateau' from before the
%   interleaved cycle took its order from OrderBy. Those two become
%   'interleaved' AND set the order they stood for (LegacyOrders) -- ramp is
%   Frequency as listed then Level ascending, plateau Level ascending -- so a
%   script or a file naming one still presents what it did. (For a bank that
%   varies Level and something other than Frequency, the old ramp grouped by
%   that other parameter; the translation names Frequency, and such a bank
%   now gets the plateau.) 'interleaved' itself is the original name of the
%   interleaved design, whose cycles followed the bank's own order -- which
%   is what it means again with no OrderBy.
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
%   The two 'interleaved' strategies and 'shuffled' INTERMIX different stimuli
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
%   Loop
%   ----
%   loopRun inserts another pass of a run DIRECTLY AFTER it, so the next
%   advance() lands on the pass instead of the run that was next --
%   mabr.ui.AcqController calls it at the end of every run while its Loop is
%   on, which holds the plan on one condition until Loop is switched off and
%   then lets it go on exactly where it was. Only for a plan that presents
%   ONE condition per run (isIntermixed false: the conventional strategies,
%   or a custom one whose runs do) -- an intermixed run is every condition at
%   once, and repeating it would be repeating the session, not holding a
%   condition -- so loopRun refuses any other (mabr:stim:Schedule:
%   loopIntermixed), the line Repeat and early stop already draw. Inserted rather than appended, unlike
%   make-up and repeat runs: those must not jump the queue, whereas a loop is
%   the queue waiting. A pass is flagged IsLoop, is never bounded (a loop ends
%   when it is switched off), and is dropped by reset() along with make-up and
%   repeat runs. A pass is a run not yet started like any other, so the
%   Disabled mask below applies to it when advance() reaches it: switching
%   the looped condition off ends the loop on it (the emptied pass is
%   dropped and the plan goes on), and a disabled stimulus drops out of an
%   intermixed pass.
%
%   Disabling upcoming conditions
%   -----------------------------
%   setEnabled(idx,false) takes stimuli out of every run that has not started
%   yet (mabr.ui.PresentationOrder is the GUI for it). The mask is applied to
%   a run at the moment advance() makes it current -- before the controller
%   renders it -- by removing the disabled stimuli's presentations from that
%   run (with their polarities), and a run left with nothing is removed from
%   the plan altogether. Applying it then, rather than when the box is
%   unticked, is what keeps the run that is rendered and the runSequence the
%   controller later pairs its onsets with the same thing: a run already
%   current is never touched, so the run in progress always plays as it was
%   rendered, and a condition can be switched back on at any time before its
%   run is reached. isComplete() answers with the mask in force, so a plan
%   whose remaining runs are all disabled is complete now rather than one run
%   later. Skipped counts what was removed, per stimulus. A disabled
%   stimulus gets no artifact make-up; a make-up run it already had is
%   refunded to the budget when it is dropped; and repeatRun switches the
%   stimulus back on, since asking for a run of it is asking for it. build()
%   and reset() clear the mask and restore the runs build() produced.
%
%   Typical walk (driven by mabr.ui.AcqController):
%       sch = mabr.stim.Schedule(stimulusSet,cfg);
%       sch.ISI = 0.0474; sch.Strategy = 'interleaved-random';
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
        Strategies = {'conventional','conventional-shuffled','interleaved', ...
                      'interleaved-random','shuffled','custom'};
        ISIModes   = {'fixed','random'};

        % The ways a parameter named in OrderBy can be ordered.
        OrderDirections = {'ascending','descending','listed'};

        % s added to ResponseWindow for the device's round trip when sizing a
        % run's closing silence: twice the reference rig's (~25 ms).
        LatencyAllowance = 0.05;

        % The strategies that play in the order OrderBy asks for; every other
        % one decides its own (see strategyTakesOrder).
        OrderedStrategies = {'conventional','interleaved'};

        % Retired names, [old new] per row. Still accepted (canonicalStrategy)
        % because .mabrcfg files and last-session prefs carry them.
        LegacyStrategies = { ...
            'blocked',             'conventional'; ...
            'shuffled-blocks',     'conventional-shuffled'; ...
            'shuffled-cycles',     'interleaved-random'; ...
            'interleaved-ramp',    'interleaved'; ...
            'interleaved-plateau', 'interleaved'};

        % The order a retired name stood for, [old OrderBy OrderDirection]
        % per row: the two interleaved designs that had an order built in
        % before the cycle took its order from OrderBy (see legacyOrder).
        LegacyOrders = { ...
            'interleaved-ramp',    {'Frequency','Level'}, {'listed','ascending'}; ...
            'interleaved-plateau', {'Level'},             {'ascending'}};
    end

    properties
        Set                             % mabr.stim.StimulusSet
        Config                          % mabr.Config
        Repetitions      (1,:) double = []      % per stimulus entry
        Strategy         (1,:) char   = 'conventional'

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

        % The parameter(s) the bank is ordered by, most significant first, and
        % which way each goes (OrderDirections) -- the order 'conventional'
        % plays its runs in and 'interleaved' walks each cycle in. Both are
        % held as cellstr rows and take a char for the one-parameter case;
        % {} = the bank's own order. OrderDirection is read in parallel with
        % OrderBy: a single direction applies to every parameter, and a
        % parameter with none of its own is 'ascending'.
        %
        % A name the bank does not vary (unknown, or constant across entries)
        % is skipped rather than refused: the setting outlives the bank it was
        % chosen for, and a configuration naming Level must still load against
        % a bank without one. Read by OrderedStrategies only -- the shuffled
        % strategies decide their own order.
        OrderBy                       = {}
        OrderDirection                = {'ascending'}

        ISI              (1,1) double = 1/21.1  % s, onset-to-onset ('fixed')

        % Which of ISI / ISIRange decides the spacing. Kept as a separate
        % switch rather than inferred from a degenerate range, so turning
        % randomization off and on again cannot lose the range it was set to
        % (the GUI's checkbox is exactly this property).
        ISIMode          (1,:) char {mustBeMember(ISIMode,{'fixed','random'})} = 'fixed'

        % [min max] s, onset-to-onset, drawn uniformly per interval ('random').
        ISIRange         (1,2) double {mustBePositive,mustBeFinite} = [1 1]/21.1

        Seed                          = []      % [] = nondeterministic shuffle
        % s of silence bracketing a run. The lead-in only has to clear the
        % first sweep's baseline window (the samples just before its onset):
        % a device starting up is warmed on unrecorded silence by the worker
        % instead (mabr.acq.worker_loop), and between runs it is kept
        % streaming, so 0.25 s of it on every run was dead time. The end is
        % at least this long, and longer where ResponseWindow says so.
        SilencePad       (1,1) double = 0.1
        % s after an onset the analysis reads to -- mabr.ui.AcqController
        % sets it from its Window at every run. When set (> 0) the run ends
        % with at least this plus LatencyAllowance of silence, so the last
        % presentation's response is in the recording before the stream
        % stops: a window left short is a sweep dropped. 0 = pad symmetric.
        ResponseWindow   (1,1) double {mustBeNonnegative,mustBeFinite} = 0
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
        IsLoop      (1,:) logical = false(1,0)  % parallel to Runs; inserted loop pass?
        CurrentRun  (1,1) double = 0   % 0 = not started / complete
        RunCounts   (1,:) double = []  % presentations actually recorded, per stimulus
        MakeupUsed  (1,:) double = []  % make-up presentations appended, per stimulus
        Disabled    (1,:) logical = false(1,0) % per stimulus: left out of runs not yet started
        Skipped     (1,:) double = []  % presentations removed by Disabled, per stimulus
    end

    properties (Access = private)
        % The runs build() produced, which reset() returns to: applying
        % Disabled edits Runs in place, so dropping appended runs alone would
        % no longer get back to the plan.
        BuiltRuns       (1,:) cell = {}
        BuiltPolarities (1,:) cell = {}
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

        function set.Strategy(obj,v)
            % Translated on the way in, so a plan built from an old name and
            % one built from its new name are the same plan with the same
            % label -- nothing downstream has to know there were two names.
            % A retired name that stood for an order sets that order too:
            % 'interleaved-plateau' is 'interleaved' AND Level ascending, and
            % translating only the name would present something else. An
            % OrderBy assigned afterwards still wins, as any later one does.
            obj.Strategy = mabr.stim.Schedule.canonicalStrategy(v);
            [by,way] = mabr.stim.Schedule.legacyOrder(v);
            if ~isempty(by)
                obj.OrderBy        = by;    %#ok<MCSUP>
                obj.OrderDirection = way;   %#ok<MCSUP>
            end
        end

        function set.OrderBy(obj,v)
            obj.OrderBy = mabr.stim.Schedule.textList(v,'OrderBy');
        end

        function set.OrderDirection(obj,v)
            % Refused here rather than at build(): a direction is one of three
            % words, and a misspelt one silently read as 'ascending' would
            % present a session backwards from what was asked for.
            v = lower(mabr.stim.Schedule.textList(v,'OrderDirection'));
            if isempty(v), v = {'ascending'}; end
            bad = ~ismember(v,mabr.stim.Schedule.OrderDirections);
            assert(~any(bad),'mabr:stim:Schedule:orderDirection', ...
                'Unknown order direction "%s". Expected one of: %s.', ...
                strjoin(v(bad),'", "'), ...
                strjoin(mabr.stim.Schedule.OrderDirections,', '));
            obj.OrderDirection = v;
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
            %
            % The same goes for a plan played in an order of its own:
            % 'conventional (Frequency as listed, Level descending)',
            % 'interleaved (Level ascending)'.
            s = obj.Strategy;
            if strcmpi(s,'custom') && ~isempty(obj.StrategyFcn)
                s = ['custom: ' mabr.stim.Schedule.fcnName(obj.StrategyFcn)];
                return
            end
            by = obj.orderLabel();
            if ~isempty(by), s = [s ' (' by ')']; end
        end

        function s = orderLabel(obj)
            % The order in force, in words -- 'Level descending',
            % 'Frequency as listed, Level descending' -- and '' for the bank's
            % own order. In force, not merely asked for: a parameter this bank
            % does not vary is left out, and a strategy that does not read
            % OrderBy (strategyTakesOrder) answers ''.
            s = '';
            if ~mabr.stim.Schedule.strategyTakesOrder(obj.Strategy), return, end
            K = obj.orderKeys();
            if isempty(K), return, end
            words = strrep({K.Direction},'listed','as listed');
            parts = cellfun(@(n,d) [n ' ' d],{K.Name},words,'UniformOutput',false);
            s = strjoin(parts,', ');
        end

        % --- Plan construction ----------------------------------------------
        function build(obj)
            % (Re)build the run list from Repetitions + Strategy (and, under
            % 'conventional' or 'interleaved', OrderBy + OrderDirection). Call
            % after changing any of them; reset() alone does not rebuild.
            n    = obj.Set.numStimuli;
            reps = obj.normalizedRepetitions();

            obj.RunCounts  = zeros(1,n);
            obj.MakeupUsed = zeros(1,n);
            obj.Disabled   = false(1,n);
            obj.Skipped    = zeros(1,n);
            obj.Runs       = {};
            obj.Polarities = {};
            obj.IsMakeup   = false(1,0);
            obj.IsRepeat   = false(1,0);
            obj.IsLoop     = false(1,0);
            obj.BuiltRuns       = {};
            obj.BuiltPolarities = {};
            if n == 0 || ~any(reps > 0), obj.CurrentRun = 0; return; end

            rs  = obj.stream();
            alt = obj.Set.alternatesPolarity();

            switch lower(obj.Strategy)
                case 'conventional'
                    [obj.Runs,obj.Polarities] = obj.blockRuns(obj.parameterOrder(),reps,alt);

                case 'conventional-shuffled'
                    [obj.Runs,obj.Polarities] = obj.blockRuns(randperm(rs,n),reps,alt);

                case 'interleaved'
                    [seq,pol] = obj.cycleSequence(reps,alt,obj.parameterOrder(),false,rs);
                    obj.Runs = {seq}; obj.Polarities = {pol};

                case 'interleaved-random'
                    [seq,pol] = obj.cycleSequence(reps,alt,1:n,true,rs);
                    obj.Runs = {seq}; obj.Polarities = {pol};

                case 'shuffled'
                    [seq,pol] = obj.cycleSequence(reps,alt,1:n,false,rs);
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
            obj.IsLoop   = false(1,numel(obj.Runs));
            obj.BuiltRuns       = obj.Runs;
            obj.BuiltPolarities = obj.Polarities;
            obj.reset();
        end

        function reset(obj)
            % Make-up runs, user-requested repeat runs (see repeatRun) and
            % loop passes (see loopRun) belong to the acquisition that
            % produced them, not to the plan, so re-starting drops all three:
            % reset() returns the schedule to exactly the state build() left
            % it in, and the make-up budget starts over with it. So does the
            % Disabled mask, and the built runs it may have edited are put
            % back.
            obj.Runs       = obj.BuiltRuns;
            obj.Polarities = obj.BuiltPolarities;
            obj.IsMakeup   = false(1,numel(obj.Runs));
            obj.IsRepeat   = false(1,numel(obj.Runs));
            obj.IsLoop     = false(1,numel(obj.Runs));
            n = obj.Set.numStimuli;
            obj.RunCounts  = zeros(1,n);
            obj.MakeupUsed = zeros(1,n);
            obj.Disabled   = false(1,n);
            obj.Skipped    = zeros(1,n);
            if isempty(obj.Runs), obj.CurrentRun = 0; else, obj.CurrentRun = 1; end
        end

        function r = current(obj), r = obj.CurrentRun; end

        function tf = isComplete(obj)
            % True when nothing is left to present after the current run --
            % with the Disabled mask in force, so a plan whose remaining runs
            % hold only disabled stimuli is complete now.
            tf = obj.CurrentRun == 0 || isempty(obj.nextRun());
        end

        function r = advance(obj)
            % Move to the next run, applying the Disabled mask to it first
            % (see setEnabled); runs the mask empties are dropped on the way.
            if obj.CurrentRun == 0 || obj.CurrentRun >= obj.NumRuns
                obj.CurrentRun = 0; r = [];
                return
            end
            k = obj.CurrentRun + 1;
            while k <= obj.NumRuns
                obj.applyDisabled(k);
                if ~isempty(obj.Runs{k}), break; end
                obj.Runs(k)       = [];
                obj.Polarities(k) = [];
                obj.IsMakeup(k)   = [];
                obj.IsRepeat(k)   = [];
                obj.IsLoop(k)     = [];
            end
            if k > obj.NumRuns
                obj.CurrentRun = 0; r = [];
            else
                obj.CurrentRun = k; r = k;
            end
        end

        % --- Disabling upcoming conditions ---------------------------------
        function setEnabled(obj,idx,tf)
            % Switch stimuli on or off for every run not yet started.
            %
            %   setEnabled(idx,tf) -- idx are stimulus indices, tf a scalar
            %   or one logical per index. Takes effect at the next advance();
            %   the current run is never changed (see the class help).
            n   = obj.Set.numStimuli;
            idx = double(idx(:)');
            assert(all(idx >= 1 & idx <= n & idx == round(idx)), ...
                'mabr:stim:Schedule:enableRange', ...
                'Stimulus index out of range (1..%d).',n);
            tf = logical(tf(:)');
            if isscalar(tf), tf = repmat(tf,1,numel(idx)); end
            assert(numel(tf) == numel(idx),'mabr:stim:Schedule:enableSize', ...
                'setEnabled needs one value, or one per stimulus index.');
            if numel(obj.Disabled) < n, obj.Disabled(end+1:n) = false; end
            was = obj.Disabled(idx);
            obj.Disabled(idx) = ~tf;
            changed = idx(was ~= ~tf);
            if isempty(changed), return; end
            on  = changed(tf(was ~= ~tf));
            off = changed(~tf(was ~= ~tf));
            if ~isempty(off)
                mabr.log.vprintf(1,'Disabled stimulus %s for the runs not yet started.', ...
                    mat2str(off));
            end
            if ~isempty(on)
                mabr.log.vprintf(1,'Re-enabled stimulus %s.',mat2str(on));
            end
        end

        function tf = isEnabled(obj,idx)
            % Whether each stimulus in idx (default: all) will be presented
            % in the runs not yet started.
            n = obj.Set.numStimuli;
            if nargin < 2, idx = 1:n; end
            d = false(1,n);
            d(1:min(n,numel(obj.Disabled))) = obj.Disabled(1:min(n,numel(obj.Disabled)));
            tf = ~d(idx);
        end

        function c = upcomingCounts(obj)
            % Presentations per stimulus in the runs after the current one --
            % the ones setEnabled can still reach -- counted as planned,
            % disabled stimuli included.
            n = obj.Set.numStimuli;
            c = zeros(1,n);
            if obj.CurrentRun == 0, return; end
            for r = obj.CurrentRun+1:obj.NumRuns
                s = obj.Runs{r};
                s = s(s >= 1 & s <= n);
                c = c + accumarray(s(:),1,[n 1]).';
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
            % A condition the user has switched off is not made up: the
            % make-up run would only be dropped when it was reached.
            counts(~obj.isEnabled()) = 0;
            if ~any(counts > 0), return; end

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
                obj.IsLoop(end+1)     = false;
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
            obj.IsLoop(m)     = [];
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
            % Only sensible when a run holds a single stimulus, i.e. a conventional
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

            % Asking for a run of it is asking for it: a disabled stimulus
            % is switched back on, or advance() would drop the run.
            if ~obj.isEnabled(stimIndex), obj.setEnabled(stimIndex,true); end

            alt = obj.Set.alternatesPolarity();
            obj.Runs{end+1}       = repmat(stimIndex,1,n);
            obj.Polarities{end+1} = mabr.stim.Schedule.polaritySeries(n,alt(stimIndex));
            obj.IsMakeup(end+1)   = false;
            obj.IsRepeat(end+1)   = true;
            obj.IsLoop(end+1)     = false;

            mabr.log.vprintf(1,'Appended repeat run %d: %d x stimulus %d (user requested).', ...
                numel(obj.Runs),n,stimIndex);
        end

        function k = loopRun(obj,r)
            % Insert another pass of run r directly after it, and return the
            % index the pass went to (r+1).
            %
            %   What mabr.ui.AcqController calls at the end of a run while its
            %   Loop is on, before it advances the plan: the advance() that
            %   follows then lands on the pass rather than on the run that was
            %   next, and that run -- with the rest of the plan behind it --
            %   is still there, one place later, for when Loop is switched
            %   off. Only runs not yet reached move; run r keeps its index and
            %   the counts already credited to it.
            %
            %   Only for a plan of one condition per run (isIntermixed false):
            %   Loop holds a CONDITION, and an intermixed run is all of them
            %   at once. Any other plan is refused
            %   (mabr:stim:Schedule:loopIntermixed).
            %
            %   The pass is run r again, presentation for presentation and
            %   sign for sign -- that condition's full train. The exception
            %   is a make-up run, which holds only what an artifact cost its
            %   stimulus rather than the condition's run: its pass is a full
            %   run of that stimulus at its scheduled repetition count -- the
            %   run repeatRun appends -- and is not charged to the make-up
            %   budget.
            %
            %   Unbounded, unlike appendMakeup: a loop ends when it is switched
            %   off, which is the whole point of it. Flagged IsLoop, and
            %   dropped by reset() with the make-up and repeat runs.
            if nargin < 2 || isempty(r), r = obj.CurrentRun; end
            assert(r >= 1 && r <= obj.NumRuns,'mabr:stim:Schedule:runRange', ...
                'Run index %d out of range (1..%d).',r,obj.NumRuns);
            assert(~obj.isIntermixed(),'mabr:stim:Schedule:loopIntermixed', ...
                ['Loop holds one condition, and this plan (%s) presents several ' ...
                 'in a run. Use a conventional strategy to loop a condition.'], ...
                obj.strategyLabel());
            seq = obj.Runs{r};
            pol = obj.Polarities{r};
            if obj.IsMakeup(r)
                i    = seq(1);                  % a make-up run holds one stimulus
                reps = obj.normalizedRepetitions();
                if reps(i) > 0
                    alt = obj.Set.alternatesPolarity();
                    seq = repmat(i,1,reps(i));
                    pol = mabr.stim.Schedule.polaritySeries(reps(i),alt(i));
                end
            end

            k = r + 1;
            obj.Runs       = [obj.Runs(1:r),       {seq}, obj.Runs(k:end)];
            obj.Polarities = [obj.Polarities(1:r), {pol}, obj.Polarities(k:end)];
            obj.IsMakeup   = [obj.IsMakeup(1:r),   false, obj.IsMakeup(k:end)];
            obj.IsRepeat   = [obj.IsRepeat(1:r),   false, obj.IsRepeat(k:end)];
            obj.IsLoop     = [obj.IsLoop(1:r),     true,  obj.IsLoop(k:end)];

            mabr.log.vprintf(1,'Loop: run %d presented again as run %d (%d presentations).', ...
                r,k,numel(seq));
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
            P     = round(obj.SilencePad*Fs);         % lead-in
            T     = round(obj.trailPad()*Fs);         % closing silence
            fl    = obj.Config.frameLength;
            total = ceil((N + P + T)/fl)*fl;
            cap   = obj.Config.maxInputBufferLength;
            assert(total <= cap,'mabr:stim:Schedule:tooLong', ...
                ['Run %d needs %d samples (%.1f s) but the ring buffer holds %d ' ...
                 '(%.1f s). Reduce repetitions, shorten the ISI, or use a ' ...
                 'conventional strategy so each run covers one stimulus.'], ...
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
            % `total` already brackets the run in silence (P in front, T
            % behind) and rounds it up to whole frames -- the padding the
            % matrix used to carry.
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
                             + obj.padSeconds();
            end
        end

        function t = trailPad(obj)
            % Seconds of silence a run ends with: SilencePad, or -- once the
            % controller has said where the analysis stops reading
            % (ResponseWindow) -- enough for the last presentation's response
            % to make the recording, round trip included, if that is longer.
            t = obj.SilencePad;
            if obj.ResponseWindow > 0
                t = max(t,obj.ResponseWindow + obj.LatencyAllowance);
            end
        end

        function t = padSeconds(obj)
            % All the silence a run carries, both ends.
            t = obj.SilencePad + obj.trailPad();
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
        function k = nextRun(obj)
            % The first run after the current one that the Disabled mask
            % leaves anything in; [] if none. Does not change the plan.
            k = [];
            d = obj.Disabled;
            for r = obj.CurrentRun+1:obj.NumRuns
                s = obj.Runs{r};
                if isempty(d)
                    on = ~isempty(s);
                else
                    on = any(s > numel(d) | ~d(min(s,numel(d))));
                end
                if on, k = r; return; end
            end
        end

        function applyDisabled(obj,r)
            % Remove the disabled stimuli's presentations from run r, which
            % is about to become current. A make-up run's removed
            % presentations go back to the make-up budget.
            s = obj.Runs{r};
            d = obj.Disabled;
            if isempty(s) || ~any(d), return; end
            n    = numel(d);
            drop = s <= n & d(min(max(s,1),n));
            if ~any(drop), return; end
            c = accumarray(reshape(s(drop),[],1),1,[n 1]).';
            obj.Skipped = obj.Skipped + c;
            if obj.IsMakeup(r)
                obj.MakeupUsed = max(0,obj.MakeupUsed - c);
            end
            obj.Runs{r}       = s(~drop);
            obj.Polarities{r} = obj.Polarities{r}(~drop);
            mabr.log.vprintf(1,'Run %d: skipped %d presentation(s) of disabled stimulus %s.', ...
                r,sum(drop),mat2str(find(c)));
        end

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
            % to conventional would present a whole session in an order nobody
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

        function order = parameterOrder(obj)
            % The bank as a permutation of 1:n in the order OrderBy asks for;
            % bank order when it asks for none this bank can give.
            %
            % One sortrows over a column per parameter, most significant
            % first, with the bank index as the last column -- so the sort is
            % stable in every direction: entries tied on every parameter keep
            % their bank order, descending included, and reversing a
            % direction reverses that parameter and nothing else.
            n     = obj.Set.numStimuli;
            order = 1:n;
            K     = obj.orderKeys();
            if isempty(K), return; end
            M = zeros(n,numel(K));
            for k = 1:numel(K)
                v = K(k).Values;
                switch K(k).Direction
                    case 'descending'
                        v = -v;
                    case 'listed'
                        % Values numbered by first appearance, so sorting on
                        % the number keeps the bank's order of the groups.
                        [~,~,v] = unique(v,'stable');
                end
                M(:,k) = v;
            end
            [~,order] = sortrows([M (1:n)']);
            order = order(:)';
        end

        function K = orderKeys(obj)
            % OrderBy as this bank can honour it: one element per parameter it
            % actually varies, in the order asked for, with the direction
            % that goes with it and its column of values.
            K = struct('Name',{},'Direction',{},'Values',{});
            if isempty(obj.OrderBy) || obj.Set.numStimuli == 0, return; end
            P = obj.Set.paramTable();
            d = obj.OrderDirection;
            for k = 1:numel(obj.OrderBy)
                j = find(strcmpi(P.Names,obj.OrderBy{k}) & P.Varying,1);
                % Named a second time a parameter adds nothing: the first has
                % already decided every comparison it could.
                if isempty(j) || any(strcmp({K.Name},P.Names{j})), continue; end
                if isscalar(d),       way = d{1};
                elseif k <= numel(d), way = d{k};
                else,                 way = 'ascending';
                end
                K(end+1) = struct('Name',P.Names{j},'Direction',way, ...
                                  'Values',P.Values(:,j)); %#ok<AGROW>
            end
        end

        function [seq,pol] = cycleSequence(~,reps,alt,order,shuffleWithin,rs)
            % Walk cycles of the still-owed stimuli, each cycle in `order`. An
            % entry leaves the cycle once it has been scheduled its full
            % repetition count, so unequal repetition counts stay spread out
            % instead of clumping at the end.
            %
            % Cycle c is, by construction, the c-th presentation of every entry
            % still due, so the alternating polarity of an entry is just the
            % sign of the cycle it appears in.
            seq = []; pol = [];
            for c = 1:max(reps)
                due = order(reps(order) >= c);
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
            tf = ismember(mabr.stim.Schedule.canonicalStrategy(strategy), ...
                {'interleaved','interleaved-random','shuffled','custom'});
        end

        function tf = strategyTakesOrder(strategy)
            % Whether a strategy plays in the order OrderBy asks for -- the
            % runs of 'conventional', each cycle of 'interleaved'. The rest
            % decide their own order, so OrderBy means nothing to them: the
            % GUI greys the order rows and orderLabel names none.
            tf = ismember(mabr.stim.Schedule.canonicalStrategy(strategy), ...
                mabr.stim.Schedule.OrderedStrategies);
        end

        function [by,way] = legacyOrder(strategy)
            % The OrderBy / OrderDirection a retired strategy name stood for
            % (LegacyOrders), or both {} for any other name. Read wherever an
            % old name is translated and the order has to come with it: the
            % Strategy setter, and mabr.ui.App restoring a configuration,
            % whose own saved order was never read under that strategy.
            by = {}; way = {};
            map = mabr.stim.Schedule.LegacyOrders;
            k = find(strcmpi(char(strategy),map(:,1)),1);
            if isempty(k), return, end
            by = map{k,2}; way = map{k,3};
        end

        function s = canonicalStrategy(s)
            % A strategy name as the plan uses it: lower case, and a retired
            % name (LegacyStrategies) translated to its successor -- the name
            % only; legacyOrder is the order that came with it.
            % Anything else passes through unchanged, so an unknown name still
            % reaches build()'s refusal naming the valid ones.
            s = lower(char(s));
            map = mabr.stim.Schedule.LegacyStrategies;
            k = find(strcmp(s,map(:,1)),1);
            if ~isempty(k), s = map{k,2}; end
        end

        function c = textList(v,what)
            % A char, a string array, or a cell of either as a cellstr row;
            % '' / [] / {} as the empty list. Empty ENTRIES are kept:
            % OrderBy and OrderDirection are read in parallel, and dropping
            % one from the middle would pair every later name with the wrong
            % direction.
            if isempty(v), c = cell(1,0); return, end
            if iscell(v) && all(cellfun(@(x) ischar(x) || ...
                    (isstring(x) && isscalar(x)),v(:)))
                c = cellfun(@char,v,'UniformOutput',false);
            elseif ischar(v) || isstring(v)
                c = cellstr(v);
            else
                error('mabr:stim:Schedule:orderList', ...
                    '%s must be a name or a list of names, not a %s.',what,class(v));
            end
            c = reshape(c,1,[]);
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
