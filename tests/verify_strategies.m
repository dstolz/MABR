function verify_strategies()
% verify_strategies  Confirm the built-in presentation strategies present
%                    the designs they are named for.
%
%   The strategies are named for the two acquisition designs, conventional
%   and interleaved, each in an order of its own choosing or a shuffled one
%   -- plus a fully shuffled order. The names are claims about ORDER, so this
%   checks the order.
%
%   Part A (names): Schedule.Strategies is the current set, every retired
%   name is translated on assignment (and by the static strategyIntermixes),
%   carrying the order it stood for where it stood for one, and an unknown
%   name is still refused by build().
%   Part B (interleaved order): every cycle follows OrderBy/OrderDirection.
%   Frequency as listed then Level ascending walks one frequency at a time
%   with its levels ASCENDING, whatever order the bank lists the levels in,
%   keeping the frequencies in the bank's own order (32, 16, 8 here -- not
%   sorted); Level ascending alone climbs the levels, every frequency at
%   each. Any order asked for gives the cycle the conventional runs would
%   play in.
%   Part C (retired names): 'interleaved-ramp' and 'interleaved-plateau'
%   still present the cycles they always did, are labelled with the order
%   they now stand for, and an OrderBy set afterwards still wins.
%   Part D (bank layout): a bank listed level-major gives the same cycles as
%   one listed frequency-major -- the order comes from the parameters, not
%   from how the bank happens to be laid out.
%   Part E (bank order): with no OrderBy, or one naming only a parameter the
%   bank does not vary, an interleaved cycle keeps bank order.
%   Part F (invariants): every built-in presents each entry exactly its
%   repetition count (unequal counts included, where an entry drops out of
%   later cycles), and only the conventional ones are not intermixed.
%   Part G (run order): 'conventional' plays its runs in the order OrderBy
%   and OrderDirection ask for -- one parameter or two, ascending,
%   descending, or as the bank lists them -- with ties left in bank order in
%   every direction; a parameter the bank does not vary is passed over
%   without shifting the directions of the others; the shuffled strategies
%   do not read the setting; and the order in force is named in
%   strategyLabel.
%
%   No hardware, no parallel pool. Run:  >> verify_strategies
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_strategies ==\n');
cfg = mabr.Config;

% ---- Part A: names -------------------------------------------------------
expected = {'conventional','conventional-shuffled','interleaved', ...
            'interleaved-random','shuffled','custom'};
assert(isequal(mabr.stim.Schedule.Strategies,expected), ...
    'Schedule.Strategies is not the current set: %s', ...
    strjoin(mabr.stim.Schedule.Strategies,', '));

set0 = toneBank(cfg,[8 16],[30 60],false);
legacy = mabr.stim.Schedule.LegacyStrategies;
for k = 1:size(legacy,1)
    s = mabr.stim.Schedule(set0,cfg);
    s.Strategy = legacy{k,1};
    assert(strcmp(s.Strategy,legacy{k,2}), ...
        'legacy "%s" should translate to "%s", got "%s"', ...
        legacy{k,1},legacy{k,2},s.Strategy);
    assert(mabr.stim.Schedule.strategyIntermixes(legacy{k,1}) == ...
           mabr.stim.Schedule.strategyIntermixes(legacy{k,2}), ...
        'strategyIntermixes disagrees between "%s" and "%s"',legacy{k,1},legacy{k,2});
    % The order comes with the name where the name stood for one, and a
    % name that stood for none leaves the order alone.
    [by,way] = mabr.stim.Schedule.legacyOrder(legacy{k,1});
    if isempty(by)
        assert(isempty(s.OrderBy),'legacy "%s" should set no order',legacy{k,1});
    else
        assert(isequal(s.OrderBy,by) && isequal(s.OrderDirection,way), ...
            'legacy "%s" should set the order %s / %s, got %s / %s',legacy{k,1}, ...
            strjoin(by,','),strjoin(way,','),strjoin(s.OrderBy,','), ...
            strjoin(s.OrderDirection,','));
    end
    s.build();                                    % and it plans
end
assert(isempty(mabr.stim.Schedule.legacyOrder('interleaved')), ...
    '"interleaved" is a current name and must not carry a retired order');
s = mabr.stim.Schedule(set0,cfg);
s.Strategy = 'Interleaved-Random';
assert(strcmp(s.Strategy,'interleaved-random'),'names must be case-insensitive');
s.Strategy = 'Interleaved-Plateau';
assert(strcmp(s.Strategy,'interleaved') && isequal(s.OrderBy,{'Level'}), ...
    'retired names must be case-insensitive, order included');
s.Strategy = 'no-such-strategy';
try
    s.build();
    error('verify:strategies:noThrow','an unknown strategy must be refused');
catch me
    assert(strcmp(me.identifier,'mabr:stim:Schedule:strategy'), ...
        'unknown strategy threw %s, not mabr:stim:Schedule:strategy',me.identifier);
end
fprintf('  PASS Part A: current set, retired names translated with their order, unknown refused\n');

% ---- Part B: the order of an interleaved cycle ---------------------------
% Frequencies deliberately NOT ascending, and levels listed DESCENDING, so
% sorting the wrong thing (or nothing) shows up.
F = [32 16 8];  L = [70 40 10];
up = sort(L);  down = sort(L,'descend');
fm = toneBank(cfg,F,L,false);                     % frequency-major
lm = toneBank(cfg,F,L,true);                      % frequency varies fastest
rampBy    = {'Frequency','Level'};  rampWay    = {'listed','ascending'};
plateauBy = {'Level'};              plateauWay = {'ascending'};

wantRamp    = pairs(F,up,'ramp');
wantPlateau = pairs(F,up,'plateau');
assertOrder(fm,cycleOf(fm,cfg,'interleaved',rampBy,rampWay),wantRamp, ...
    'Frequency as listed, then Level ascending');
assertOrder(fm,cycleOf(fm,cfg,'interleaved',plateauBy,plateauWay),wantPlateau, ...
    'Level ascending');
assertOrder(fm,cycleOf(fm,cfg,'interleaved',rampBy,{'listed','descending'}), ...
    pairs(F,down,'ramp'),'Frequency as listed, then Level descending');
% The cycle reads the setting exactly as the conventional runs do, so any
% order asked for gives the cycle those runs would play in.
orders = { ...
    'Level',              'descending'; ...
    'Frequency',          'ascending'; ...
    {'Frequency','Level'},{'ascending','descending'}; ...
    {'Frequency','Level'},{'listed','descending'}; ...
    {'Level','Frequency'},{'descending','ascending'}};
for k = 1:size(orders,1)
    for bank = {fm,lm}
        got  = cycleOf(bank{1},cfg,'interleaved',orders{k,1},orders{k,2});
        want = runOrder(bank{1},cfg,orders{k,1},orders{k,2});
        assert(isequal(got,want), ...
            'interleaved cycle %s differs from the conventional run order %s', ...
            mat2str(got),mat2str(want));
    end
end
fprintf('  PASS Part B: each cycle follows OrderBy, the same order the conventional runs take\n');

% ---- Part C: the retired interleaved names --------------------------------
assertOrder(fm,cycleOf(fm,cfg,'interleaved-ramp'),wantRamp,'interleaved-ramp');
assertOrder(fm,cycleOf(fm,cfg,'interleaved-plateau'),wantPlateau,'interleaved-plateau');
s = mabr.stim.Schedule(fm,cfg);
s.Strategy = 'interleaved-plateau';
assert(strcmp(s.strategyLabel(),'interleaved (Level ascending)'), ...
    'a retired name should be labelled with the order it stands for, got "%s"', ...
    s.strategyLabel());
% An order set after the name is the one in force.
s.OrderBy = 'Frequency';  s.OrderDirection = 'descending';
s.Repetitions = 3;  s.build();
assert(isequal(s.Runs{1}(1:fm.numStimuli),runOrder(fm,cfg,'Frequency','descending')), ...
    'an OrderBy set after a retired name must replace the order it carried');
fprintf('  PASS Part C: interleaved-ramp / -plateau present the cycles they always did\n');

% ---- Part D: the same designs from a level-major bank ---------------------
assertOrder(lm,cycleOf(lm,cfg,'interleaved',rampBy,rampWay),wantRamp, ...
    'Frequency as listed, then Level ascending (level-major bank)');
assertOrder(lm,cycleOf(lm,cfg,'interleaved',plateauBy,plateauWay),wantPlateau, ...
    'Level ascending (level-major bank)');
assertOrder(lm,cycleOf(lm,cfg,'interleaved-ramp'),wantRamp,'interleaved-ramp (level-major bank)');
assertOrder(lm,cycleOf(lm,cfg,'interleaved-plateau'),wantPlateau,'interleaved-plateau (level-major bank)');
fprintf('  PASS Part D: the order follows the parameters, not the bank layout\n');

% ---- Part E: nothing to sort by -> bank order -----------------------------
assert(isequal(cycleOf(lm,cfg,'interleaved'),1:lm.numStimuli), ...
    'interleaved with no OrderBy should keep bank order');
nl = toneBank(cfg,F,60,false);                    % one level only
assert(isequal(cycleOf(nl,cfg,'interleaved',plateauBy,plateauWay),1:nl.numStimuli), ...
    'a cycle ordered by a Level the bank does not vary should keep bank order');
assert(isequal(cycleOf(nl,cfg,'interleaved-plateau'),1:nl.numStimuli), ...
    'interleaved-plateau without a varying Level should keep bank order');
fprintf('  PASS Part E: with nothing to sort by, a cycle keeps bank order\n');

% ---- Part F: repetition invariant and intermixing ------------------------
reps = [5 3 4 1 2 6 2 3 4];                       % unequal, one per entry
for name = setdiff(mabr.stim.Schedule.Strategies,{'custom'},'stable')
    s = mabr.stim.Schedule(fm,cfg);
    s.Strategy    = name{1};
    s.OrderBy     = rampBy;  s.OrderDirection = rampWay;
    s.Repetitions = reps;
    s.Seed        = 7;
    s.build();
    seqAll = [s.Runs{:}];
    got = accumarray(seqAll(:),1,[fm.numStimuli 1])';
    assert(isequal(got,reps), ...
        '%s presented %s, expected %s',name{1},mat2str(got),mat2str(reps));
    conv = startsWith(name{1},'conventional');
    assert(s.isIntermixed() == ~conv, ...
        '%s: isIntermixed should be %d',name{1},~conv);
    if conv
        assert(s.NumRuns == fm.numStimuli,'%s should give one run per stimulus',name{1});
    else
        assert(s.NumRuns == 1,'%s should give one run',name{1});
    end
end
% Unequal counts under an ordered cycle: an entry drops out of later cycles
% and the ones still due keep the cycle's order among themselves.
s = mabr.stim.Schedule(fm,cfg);
s.Strategy = 'interleaved';  s.OrderBy = 'Level';  s.OrderDirection = 'descending';
s.Repetitions = reps;  s.build();
seq  = s.Runs{1};
full = cycleOf(fm,cfg,'interleaved','Level','descending');
due  = full(reps(full) >= 2);
c2   = seq(nnz(reps >= 1)+(1:numel(due)));        % the second cycle
assert(isequal(c2,due), ...
    'second cycle should be %s, got %s',mat2str(due),mat2str(c2));
fprintf('  PASS Part F: every entry its count; only conventional runs one stimulus at a time\n');

% ---- Part G: the order of conventional runs --------------------------------
% The same banks: frequencies listed 32, 16, 8 and levels 70, 40, 10, so
% neither ascending nor descending is the order a bank is already in.
assert(isequal(runOrder(fm,cfg,{},{}),1:fm.numStimuli), ...
    'with no OrderBy the runs should play in bank order');

% One parameter. The ties stay in bank order in BOTH directions, so
% descending reverses the levels and leaves the frequencies at 32, 16, 8.
assertOrder(fm,runOrder(fm,cfg,'Level','ascending'), ...
    pairs(F,up,'plateau'),'Level ascending');
assertOrder(fm,runOrder(fm,cfg,'Level','descending'), ...
    pairs(F,down,'plateau'),'Level descending');
assertOrder(fm,runOrder(fm,cfg,'Frequency','ascending'), ...
    pairs(sort(F),L,'ramp'),'Frequency ascending');
assertOrder(lm,runOrder(lm,cfg,'Frequency','descending'), ...
    pairs(sort(F,'descend'),L,'ramp'),'Frequency descending');
% 'listed' sorts nothing: it gathers each frequency's runs together and
% keeps the frequencies in the order the bank first lists them.
assertOrder(lm,runOrder(lm,cfg,'Frequency','listed'), ...
    pairs(F,L,'ramp'),'Frequency as listed');

% Two parameters, on the bank listed level-major so that the order asked
% for is not one it happens to be in. The threshold series first: one
% frequency at a time, loudest first within it.
assertOrder(lm,runOrder(lm,cfg,{'Frequency','Level'},{'ascending','descending'}), ...
    pairs(sort(F),down,'ramp'),'Frequency ascending, then Level descending');
assertOrder(lm,runOrder(lm,cfg,{'Frequency','Level'},{'listed','descending'}), ...
    pairs(F,down,'ramp'),'Frequency as listed, then Level descending');
assertOrder(lm,runOrder(lm,cfg,{'Frequency','Level'},{'listed','ascending'}), ...
    pairs(F,up,'ramp'),'Frequency as listed, then Level ascending');
% The same two the other way round makes the level the outer loop.
assertOrder(fm,runOrder(fm,cfg,{'Level','Frequency'},{'descending','ascending'}), ...
    pairs(sort(F),down,'plateau'),'Level descending, then Frequency ascending');
% One direction given for two parameters applies to both.
assertOrder(lm,runOrder(lm,cfg,{'Frequency','Level'},'descending'), ...
    pairs(sort(F,'descend'),down,'ramp'),'one direction for both parameters');
% Names and directions are matched without regard to case.
assertOrder(fm,runOrder(fm,cfg,'level','Descending'), ...
    pairs(F,down,'plateau'),'level / Descending');

% A parameter the bank does not vary means bank order, not an error ...
assert(isequal(runOrder(nl,cfg,'Level','descending'),1:nl.numStimuli), ...
    'ordering by a Level the bank does not vary should keep bank order');
assert(isequal(runOrder(fm,cfg,'NoSuchParameter','descending'),1:fm.numStimuli), ...
    'ordering by an unknown parameter should keep bank order');
% ... and is passed over without handing its direction to the next one.
assertOrder(fm,runOrder(fm,cfg,{'NoSuchParameter','Level'},{'descending','ascending'}), ...
    pairs(F,up,'plateau'),'an unknown name must not shift the directions');

% A direction that is not one of the three is refused where it is assigned.
s = mabr.stim.Schedule(fm,cfg);
try
    s.OrderDirection = 'sideways';
    error('verify:strategies:noThrow','an unknown direction must be refused');
catch me
    assert(strcmp(me.identifier,'mabr:stim:Schedule:orderDirection'), ...
        'unknown direction threw %s, not mabr:stim:Schedule:orderDirection', ...
        me.identifier);
end

% Ordering changes the order and nothing else: every entry still gets its
% own count in one run of its own, and an entry owed nothing is left out
% without disturbing the order of the rest.
reps0 = reps;  reps0(4) = 0;
s = mabr.stim.Schedule(fm,cfg);
s.OrderBy = 'Level';  s.OrderDirection = 'descending';
s.Repetitions = reps0;
s.build();
want = runOrder(fm,cfg,'Level','descending');
want = want(reps0(want) > 0);
got  = cellfun(@(r) r(1),s.Runs);
assert(isequal(got,want), ...
    'ordered runs with unequal counts are %s, expected %s',mat2str(got),mat2str(want));
assert(all(cellfun(@(r) isscalar(unique(r)),s.Runs)) && ~s.isIntermixed(), ...
    'an ordered conventional plan must still run one stimulus at a time');
assert(isequal(cellfun(@numel,s.Runs),reps0(want)), ...
    'an ordered conventional plan must still present each entry its count');

% The shuffled strategies do not read the setting: the same seed gives the
% same plan with an order asked for or without one, and none is named.
for name = {'conventional-shuffled','interleaved-random','shuffled'}
    a = mabr.stim.Schedule(fm,cfg);
    a.Strategy = name{1};  a.Seed = 11;  a.Repetitions = 2;
    a.build();
    b = mabr.stim.Schedule(fm,cfg);
    b.Strategy = name{1};  b.Seed = 11;  b.Repetitions = 2;
    b.OrderBy  = 'Level';  b.OrderDirection = 'descending';
    b.build();
    assert(isequal(a.Runs,b.Runs),'%s must not be reordered by OrderBy',name{1});
    assert(~mabr.stim.Schedule.strategyTakesOrder(name{1}) ...
           && isempty(b.orderLabel()) && strcmp(b.strategyLabel(),name{1}), ...
        '%s must not be labelled with an order it does not follow',name{1});
end
assert(all(cellfun(@mabr.stim.Schedule.strategyTakesOrder, ...
    {'conventional','interleaved','interleaved-ramp','blocked'})), ...
    'conventional and interleaved (and their retired names) take an order');

% What a record of the session says: the order in force, and only that.
s = mabr.stim.Schedule(lm,cfg);
s.OrderBy = {'Frequency','Level'};  s.OrderDirection = {'listed','descending'};
s.build();
assert(strcmp(s.orderLabel(),'Frequency as listed, Level descending'), ...
    'orderLabel is "%s"',s.orderLabel());
assert(strcmp(s.strategyLabel(),'conventional (Frequency as listed, Level descending)'), ...
    'strategyLabel is "%s"',s.strategyLabel());
s.Strategy = 'interleaved';
assert(strcmp(s.strategyLabel(),'interleaved (Frequency as listed, Level descending)'), ...
    'strategyLabel is "%s"',s.strategyLabel());
s = mabr.stim.Schedule(nl,cfg);
s.OrderBy = 'Level';  s.OrderDirection = 'descending';
s.build();
assert(strcmp(s.strategyLabel(),'conventional'), ...
    'an order the bank cannot give must not be named, got "%s"',s.strategyLabel());
fprintf('  PASS Part G: conventional runs follow OrderBy; ties keep bank order; shuffles ignore it\n');

fprintf('== verify_strategies PASSED ==\n');
end

% -------------------------------------------------------------------------
function set = toneBank(cfg,F,L,levelMajor)
% A Frequency x Level bank listed in the order asked for. The waveforms are
% irrelevant here -- only the order is being checked -- so they are short.
Fs = cfg.DACSampleRate;
t  = (0:round(Fs*0.002)-1)'/Fs;
[ff,ll] = ndgrid(F,L);                            % frequency varies fastest
if ~levelMajor, ff = ff'; ll = ll'; end           % level varies fastest
raw = struct('signal',{},'ID',{},'SampleRate',{},'Frequency',{},'Level',{});
for k = 1:numel(ff)
    raw(end+1) = struct( ...
        'signal',     single(10^((ll(k)-80)/20)*sin(2*pi*ff(k)*1e3*t)), ...
        'ID',         sprintf('%gkHz_%gdB',ff(k),ll(k)), ...
        'SampleRate', Fs, ...
        'Frequency',  ff(k), ...
        'Level',      ll(k)); %#ok<AGROW>
end
set = mabr.stim.StimulusSet(raw,cfg);
end

function c = cycleOf(set,cfg,strategy,by,way)
% One cycle of a cycled strategy: the run's first numStimuli presentations,
% with every entry owed the same count so the cycle is the whole bank. BY and
% WAY, when given, are the OrderBy / OrderDirection to cycle in -- assigned
% after the strategy, so they replace any order a retired name carries.
s = mabr.stim.Schedule(set,cfg);
s.Strategy    = strategy;
if nargin >= 4
    s.OrderBy        = by;
    s.OrderDirection = way;
end
s.Repetitions = 3;
s.build();
seq = s.Runs{1};
c   = seq(1:set.numStimuli);
assert(isequal(seq,repmat(c,1,3)), ...
    '%s: every cycle should repeat the first under equal counts',strategy);
end

function order = runOrder(set,cfg,by,way)
% The stimulus each conventional run presents, in play order, under the order
% asked for. Every stimulus must get exactly one run, holding nothing else.
s = mabr.stim.Schedule(set,cfg);
s.Strategy       = 'conventional';
s.OrderBy        = by;
s.OrderDirection = way;
s.Repetitions    = 2;
s.build();
assert(all(cellfun(@(r) isscalar(unique(r)),s.Runs)), ...
    'a conventional run must present one stimulus');
order = cellfun(@(r) r(1),s.Runs);
assert(isequal(sort(order),1:set.numStimuli), ...
    'every stimulus should get exactly one run, got %s',mat2str(order));
end

function P = pairs(F,L,kind)
% The expected cycle as [Frequency Level] rows.
switch kind
    case 'ramp',    [ll,ff] = ndgrid(L,F);        % level varies fastest
    case 'plateau', [ff,ll] = ndgrid(F,L);        % frequency varies fastest
end
P = [ff(:) ll(:)];
end

function assertOrder(set,order,want,what)
P   = set.paramTable();
fj  = strcmp(P.Names,'Frequency');
lj  = strcmp(P.Names,'Level');
got = [P.Values(order,fj) P.Values(order,lj)];
assert(isequal(got,want), '%s: cycle is\n%s\nexpected\n%s', ...
    what,mat2str(got),mat2str(want));
end
