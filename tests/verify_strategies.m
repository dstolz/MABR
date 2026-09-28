function verify_strategies()
% verify_strategies  Confirm the built-in presentation strategies present
%                    the designs they are named for.
%
%   The strategies are named for four acquisition designs -- conventional,
%   interleaved ramp, interleaved plateau, interleaved random -- plus a
%   shuffled variant of the first and a fully shuffled order. The names are
%   claims about ORDER, so this checks the order.
%
%   Part A (names): Schedule.Strategies is the new set, every name from
%   before the rename is translated on assignment (and by the static
%   strategyIntermixes), and an unknown name is still refused by build().
%   Part B (ramp): one cycle walks one frequency at a time with its levels
%   ASCENDING, whatever order the bank lists the levels in, and keeps the
%   frequencies in the bank's own order (32, 16, 8 here -- not sorted).
%   Part C (plateau): one cycle climbs the levels, every frequency at each
%   one, again in the bank's frequency order.
%   Part D (bank layout): a bank listed level-major gives the same ramp and
%   plateau as one listed frequency-major -- the order comes from the
%   parameters, not from how the bank happens to be laid out.
%   Part E (no Level): a bank that does not vary a Level is cycled in bank
%   order under either name, rather than regrouped by guesswork.
%   Part F (invariants): every built-in presents each entry exactly its
%   repetition count (unequal counts included, where an entry drops out of
%   later cycles), and only the conventional ones are not intermixed.
%
%   No hardware, no parallel pool. Run:  >> verify_strategies
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_strategies ==\n');
cfg = mabr.Config;

% ---- Part A: names -------------------------------------------------------
expected = {'conventional','conventional-shuffled','interleaved-ramp', ...
            'interleaved-plateau','interleaved-random','shuffled','custom'};
assert(isequal(mabr.stim.Schedule.Strategies,expected), ...
    'Schedule.Strategies is not the renamed set: %s', ...
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
    s.build();                                    % and it plans
end
s = mabr.stim.Schedule(set0,cfg);
s.Strategy = 'Interleaved-Plateau';
assert(strcmp(s.Strategy,'interleaved-plateau'),'names must be case-insensitive');
s.Strategy = 'no-such-strategy';
try
    s.build();
    error('verify:strategies:noThrow','an unknown strategy must be refused');
catch me
    assert(strcmp(me.identifier,'mabr:stim:Schedule:strategy'), ...
        'unknown strategy threw %s, not mabr:stim:Schedule:strategy',me.identifier);
end
fprintf('  PASS Part A: renamed set, legacy names translated, unknown refused\n');

% ---- Part B/C: ramp and plateau on a frequency-major bank -------------------
% Frequencies deliberately NOT ascending, and levels listed DESCENDING, so
% sorting the wrong thing (or nothing) shows up.
F = [32 16 8];  L = [70 40 10];
fm = toneBank(cfg,F,L,false);                     % frequency-major
ramp    = cycleOf(fm,cfg,'interleaved-ramp');
plateau = cycleOf(fm,cfg,'interleaved-plateau');

wantRamp    = pairs(F,sort(L),'ramp');
wantPlateau = pairs(F,sort(L),'plateau');
assertOrder(fm,ramp,wantRamp,'ramp (frequency-major bank)');
fprintf('  PASS Part B: ramp walks %s kHz, levels ascending within each\n', ...
    mat2str(F));
assertOrder(fm,plateau,wantPlateau,'plateau (frequency-major bank)');
fprintf('  PASS Part C: plateau climbs %s dB, every frequency at each level\n', ...
    mat2str(sort(L)));

% ---- Part D: the same designs from a level-major bank ---------------------
lm = toneBank(cfg,F,L,true);                      % frequency varies fastest
assertOrder(lm,cycleOf(lm,cfg,'interleaved-ramp'),wantRamp,'ramp (level-major bank)');
assertOrder(lm,cycleOf(lm,cfg,'interleaved-plateau'),wantPlateau,'plateau (level-major bank)');
fprintf('  PASS Part D: the order follows the parameters, not the bank layout\n');

% ---- Part E: no varying Level -> bank order --------------------------------
nl = toneBank(cfg,F,60,false);                    % one level only
for name = {'interleaved-ramp','interleaved-plateau'}
    got = cycleOf(nl,cfg,name{1});
    assert(isequal(got,1:nl.numStimuli), ...
        '%s without a varying Level should keep bank order, got %s', ...
        name{1},mat2str(got));
end
fprintf('  PASS Part E: without a varying Level both keep bank order\n');

% ---- Part F: repetition invariant and intermixing ------------------------
reps = [5 3 4 1 2 6 2 3 4];                       % unequal, one per entry
for name = setdiff(mabr.stim.Schedule.Strategies,{'custom'},'stable')
    s = mabr.stim.Schedule(fm,cfg);
    s.Strategy    = name{1};
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
% Unequal counts under the ramp: an entry drops out of later cycles and the
% ones still due keep the ramp order among themselves.
s = mabr.stim.Schedule(fm,cfg);
s.Strategy = 'interleaved-ramp'; s.Repetitions = reps; s.build();
seq  = s.Runs{1};
full = cycleOf(fm,cfg,'interleaved-ramp');
due  = full(reps(full) >= 2);
c2   = seq(nnz(reps >= 1)+(1:numel(due)));        % the second cycle
assert(isequal(c2,due), ...
    'second ramp cycle should be %s, got %s',mat2str(due),mat2str(c2));
fprintf('  PASS Part F: every entry its count; only conventional runs one stimulus at a time\n');

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

function c = cycleOf(set,cfg,strategy)
% One cycle of a cycled strategy: the run's first numStimuli presentations,
% with every entry owed the same count so the cycle is the whole bank.
s = mabr.stim.Schedule(set,cfg);
s.Strategy    = strategy;
s.Repetitions = 3;
s.build();
seq = s.Runs{1};
c   = seq(1:set.numStimuli);
assert(isequal(seq,repmat(c,1,3)), ...
    '%s: every cycle should repeat the first under equal counts',strategy);
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
