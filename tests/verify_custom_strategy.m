function verify_custom_strategy()
% verify_custom_strategy  The custom presentation-strategy contract: the
%                         canonical context, the return-shape normalizer, the
%                         conformance validator, the stereotype template, and
%                         a user function selected from a file driving a real
%                         acquisition.
%
%   Part A (context): mabr.stim.strategy.context describes a real Schedule's
%   design in the documented fields, carries StrategyParams through, and hands
%   over the schedule's OWN RandStream rather than making a second one.
%
%   Part B (normalize): every accepted return shape -- a vector, a cell of
%   vectors, a struct with explicit polarities -- reads back as the same
%   canonical run list, and every structural fault is refused by identifier.
%
%   Part C (polarity): the assignment normalize makes is BIT-IDENTICAL to what
%   the built-in strategies produce for the same sequence, and continues
%   across runs rather than restarting -- which is the whole claim that lets a
%   custom reordering inherit the built-ins' polarity balance.
%
%   Part D (validate): the validator accepts the template and well-formed
%   strategies, and rejects the ways one can be wrong -- not a handle, errors
%   on a context field, returns something that is not a plan.
%
%   Part E (template): mabr.stim.strategy.custom_template orders the bank the
%   way it documents (grouped by frequency, loudest first), and degrades to
%   bank order on a bank carrying no such parameters.
%
%   Part F (Schedule): 'custom' builds from StrategyFcn, refuses without one,
%   names the function in strategyLabel, answers isIntermixed from the RUNS
%   rather than the strategy name, and renders a plan that survives
%   renderSpec. The invariant departure is warned about, not refused.
%
%   Part G (end-to-end): resolve a strategy FROM A FILE the way the GUI does
%   (folder onto the path, str2func by name, validate), hand it to a real
%   mabr.ui.AcqController in TESTING loopback, and confirm the blocks come
%   back in the order it asked for -- the whole point of letting a user supply
%   their own.
%
%   Requires the Parallel Computing Toolbox (Part G only). Run:
%       >> verify_custom_strategy
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_custom_strategy ==\n');

cfg = mabr.Config;

% ---- Part A: canonical context -----------------------------------------
set = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',[30 60 90]);
sch = mabr.stim.Schedule(set,cfg);
sch.Repetitions    = [64 64 32 64 64 32];
sch.Seed           = 7;
sch.StrategyParams = struct('myKnob',3);

rs  = sch.stream();
ctx = mabr.stim.strategy.context(sch,sch.StrategyParams,rs);
for f = {'numStimuli','repetitions','alternatePolarity','IDs','durations', ...
         'params','sampleRate','isi','isiMode','isiRange','minISI','meanISI', ...
         'silencePad','maxRunSamples','randStream'}
    assert(isfield(ctx,f{1}),'context missing documented field %s',f{1});
end
assert(ctx.numStimuli == 6,'numStimuli wrong');
assert(isequal(ctx.repetitions,[64 64 32 64 64 32]),'repetitions not normalized through');
assert(ctx.myKnob == 3,'a StrategyParams knob did not pass through');
assert(ctx.randStream == rs,'context must carry the stream it was handed, not a new one');
assert(all(ismember({'Frequency','Level'},ctx.params.Names)), ...
    'params.Names must carry the bank''s dimensions, got: %s', ...
    strjoin(ctx.params.Names,','));
assert(isequal(size(ctx.params.Values),[6 numel(ctx.params.Names)]), ...
    'params.Values must be [nStim x nP]');
assert(isequal(size(ctx.params.Varying),[1 numel(ctx.params.Names)]), ...
    'params.Varying must be one flag per parameter');
assert(all(ctx.params.Varying(ismember(ctx.params.Names,{'Frequency','Level'}))), ...
    'both Frequency and Level vary across this bank');
% Repetitions given as a SCALAR must arrive expanded -- a strategy indexing
% ctx.repetitions(i) must not have to normalize it again.
sch.Repetitions = 128;
assert(isequal(mabr.stim.strategy.context(sch,struct(),rs).repetitions,repmat(128,1,6)), ...
    'a scalar Repetitions must reach the context expanded over the bank');
fprintf('  PASS Part A: context describes the design in the documented fields\n');

% ---- Part B: return shapes ---------------------------------------------
c = mabr.stim.strategy.sampleContext();
n = c.numStimuli;

[r1,p1] = mabr.stim.strategy.normalize([1 2 3],c);
assert(numel(r1) == 1 && isequal(r1{1},[1 2 3]),'a vector must become one run');
assert(numel(p1) == 1 && numel(p1{1}) == 3,'polarity must mirror the run');

[r2,~] = mabr.stim.strategy.normalize({[1 1],[2 2 2]},c);
assert(numel(r2) == 2 && isequal(r2{2},[2 2 2]),'a cell must become that many runs');

% A column vector is a vector: a strategy building one with (:) must work.
[r3,~] = mabr.stim.strategy.normalize([1;2;3],c);
assert(isequal(r3{1},[1 2 3]),'a column vector must normalize to a row run');

% Struct form, with polarity supplied verbatim.
[r4,p4] = mabr.stim.strategy.normalize( ...
    struct('Runs',{{[1 1 1]}},'Polarities',{{[1 -1 1]}}),c);
assert(isequal(r4{1},[1 1 1]) && isequal(p4{1},[1 -1 1]), ...
    'supplied polarities must be taken verbatim');

% Empty runs are dropped, not streamed as a block of silence.
[r5,p5] = mabr.stim.strategy.normalize({[],[1 2],[]},c);
assert(numel(r5) == 1 && isequal(r5{1},[1 2]),'empty runs must be dropped');
assert(numel(p5) == 1,'polarities must be dropped with their runs');

% Nothing at all is a plan with nothing in it, not an error.
[r6,~] = mabr.stim.strategy.normalize([],c);
assert(isempty(r6),'an empty return must give an empty plan');

% Structural faults, by identifier.
bad = { {[1 2 n+1], 'mabr:stim:strategy:runRange'}, ...
        {[0 1],     'mabr:stim:strategy:runRange'}, ...
        {[1 1.5],   'mabr:stim:strategy:runIndex'}, ...
        {[1 NaN],   'mabr:stim:strategy:runIndex'}, ...
        {{'a','b'}, 'mabr:stim:strategy:runType'} };
for k = 1:numel(bad)
    assertRefused(bad{k}{1},c,bad{k}{2});
end

% Polarity faults.
polBad = { {struct('Runs',{{[1 1]}},'Polarities',{{[1 -1 1]}}), ...
            'mabr:stim:strategy:polarityLength'}, ...
           {struct('Runs',{{[1 1]}},'Polarities',{{[1 0]}}), ...
            'mabr:stim:strategy:polarityValue'}, ...
           {struct('Runs',{{[1 1],[2 2]}},'Polarities',{{[1 -1]}}), ...
            'mabr:stim:strategy:polarityCount'}, ...
           {struct('Nope',1), ...
            'mabr:stim:strategy:shape'} };
for k = 1:numel(polBad)
    assertRefused(polBad{k}{1},c,polBad{k}{2});
end
fprintf('  PASS Part B: every return shape reads back, every fault is refused\n');

% ---- Part C: polarity parity with the built-ins -------------------------
% A bank where some entries alternate and some do not, with ODD repetition
% counts, so an off-by-one in the assignment cannot hide.
demo = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',[30 60]);
raw  = struct('signal',{},'ID',{},'SampleRate',{},'alternatePolarity',{});
for i = 1:demo.numStimuli
    raw(i).signal            = demo.signal(i);
    raw(i).ID                = demo.IDs{i};
    raw(i).SampleRate        = demo.SampleRate;
    raw(i).alternatePolarity = mod(i,2) == 1;      % entries 1 and 3 alternate
end
altSet = mabr.stim.StimulusSet(raw,cfg);
reps   = [7 6 5 4];

% Replaying a built-in's own sequence through a custom strategy must give
% back that built-in's own polarity, to the bit.
for strat = {'blocked','interleaved','shuffled-cycles'}
    [Rb,Pb] = planWith(altSet,cfg,reps,strat{1},[]);
    [Rc,Pc] = planWith(altSet,cfg,reps,'custom',@(cc) Rb);
    assert(isequal(Rb,Rc),'%s: sequence changed under normalize',strat{1});
    assert(isequal(Pb,Pc), ...
        '%s: custom polarity differs from the built-in for the same sequence',strat{1});
end

% Across runs the alternation CONTINUES rather than restarting -- entry 1
% alternates and is owed 7, so a 3+4 split must still come out ceil/floor
% (4 positive, 3 negative), which a per-run restart would not give.
[~,Pm]  = planWith(altSet,cfg,reps,'custom',@(cc) {[1 1 1],[1 1 1 1]});
allPol  = [Pm{:}];
assert(isequal(allPol,[1 -1 1 -1 1 -1 1]), ...
    'polarity must continue across runs, got %s',mat2str(allPol));
assert(sum(allPol == 1) == 4 && sum(allPol == -1) == 3, ...
    'an odd count must split ceil/floor between the polarities');

% An entry that does NOT alternate keeps +1 throughout, however it is ordered.
[~,Pn] = planWith(altSet,cfg,reps,'custom',@(cc) {[2 2 2 2 2 2]});
assert(all(Pn{1} == 1),'a non-alternating entry must never be inverted');
fprintf('  PASS Part C: polarity matches the built-ins and continues across runs\n');

% ---- Part D: conformance validator -------------------------------------
assert(mabr.stim.strategy.validate(@mabr.stim.strategy.custom_template), ...
    'the template must validate');
assert(mabr.stim.strategy.validate(@(cc) 1:cc.numStimuli), ...
    'a well-formed anonymous strategy should validate');
assert(mabr.stim.strategy.validate(@(cc) repelem(1:cc.numStimuli,cc.repetitions)), ...
    'a strategy reading repetitions should validate');
assert(mabr.stim.strategy.validate(@(cc) {[1 1],[2 2]}), ...
    'a multi-run strategy should validate');
assert(~mabr.stim.strategy.validate(42),'a non-handle must be rejected');
assert(~mabr.stim.strategy.validate(@(cc) cc.no_such_field_zzz), ...
    'a strategy that errors on a missing field must be rejected');
assert(~mabr.stim.strategy.validate(@(cc) 'nonsense'), ...
    'a strategy returning a non-plan must be rejected');
assert(~mabr.stim.strategy.validate(@(cc) 1:(cc.numStimuli+5)), ...
    'a strategy indexing off the end of the bank must be rejected');
% Departing from the repetition invariant is a WARNING, not a rejection.
assert(mabr.stim.strategy.validate(@(cc) 1), ...
    'presenting fewer sweeps than scheduled is a warning, not a validation failure');
fprintf('  PASS Part D: validator accepts conforming strategies and refuses the rest\n');

% ---- Part E: the template's documented behaviour ------------------------
tset = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',[30 60 90]);
tsch = mabr.stim.Schedule(tset,cfg);
tsch.Repetitions = 16;
tsch.Strategy    = 'custom';
tsch.StrategyFcn = @mabr.stim.strategy.custom_template;
tsch.build();
P   = tset.paramTable();
% By NAME, not column order: the demo bank carries a Polarity parameter too,
% and a positional read would silently compare the wrong columns.
jF  = find(strcmp(P.Names,'Frequency'),1);
jL  = find(strcmp(P.Names,'Level'),1);
got = zeros(tsch.NumRuns,2);
for r = 1:tsch.NumRuns
    v = tsch.runSequence(r);
    assert(numel(unique(v)) == 1,'template must emit one stimulus per run');
    got(r,:) = P.Values(v(1),[jF jL]);
end
assert(isequal(got,[8 90; 8 60; 8 30; 16 90; 16 60; 16 30]), ...
    'template must group by frequency, loudest first; got %s',mat2str(got));

% A bank with no Frequency/Level must degrade to bank order rather than throw.
plain = struct('signal',{},'ID',{},'SampleRate',{});
for i = 1:3
    plain(i).signal     = zeros(96,1);
    plain(i).ID         = sprintf('s%d',i);
    plain(i).SampleRate = cfg.DACSampleRate;
end
pset = mabr.stim.StimulusSet(plain,cfg);
psch = mabr.stim.Schedule(pset,cfg);
psch.Repetitions = 4;
psch.Strategy    = 'custom';
psch.StrategyFcn = @mabr.stim.strategy.custom_template;
psch.build();
assert(psch.NumRuns == 3,'template must still plan a parameterless bank');
assert(isequal(cellfun(@(v) v(1),psch.Runs),[1 2 3]), ...
    'a parameterless bank must come back in bank order');
fprintf('  PASS Part E: template orders loudest-first per frequency, degrades gracefully\n');

% ---- Part F: Schedule integration ---------------------------------------
% No function under 'custom' is refused, and named so the user can act on it.
nosch = mabr.stim.Schedule(tset,cfg);
nosch.Repetitions = 8;
nosch.Strategy    = 'custom';
assertBuildFails(nosch,'mabr:stim:Schedule:noStrategyFcn');

% A strategy that throws is re-thrown as a Schedule error naming it.
badsch = mabr.stim.Schedule(tset,cfg);
badsch.Repetitions = 8;
badsch.Strategy    = 'custom';
badsch.StrategyFcn = @(cc) error('deliberate:boom','boom');
assertBuildFails(badsch,'mabr:stim:Schedule:strategyFcn');

% strategyLabel names the function; the built-ins keep their plain names.
assert(strcmp(tsch.strategyLabel(),'custom: mabr.stim.strategy.custom_template'), ...
    'strategyLabel must name the function, got "%s"',tsch.strategyLabel());
bsch = mabr.stim.Schedule(tset,cfg);
bsch.Repetitions = 4;
bsch.build();
assert(strcmp(bsch.strategyLabel(),'blocked'),'a built-in label must be its plain name');

% isIntermixed is answered from the RUNS, not from the strategy's name.
assert(~tsch.isIntermixed(), ...
    'a custom plan of one-stimulus runs must NOT report as intermixed');
mix = mabr.stim.Schedule(tset,cfg);
mix.Repetitions = 8;
mix.Strategy    = 'custom';
mix.StrategyFcn = @(cc) repelem(1:cc.numStimuli,cc.repetitions);
mix.build();
assert(mix.isIntermixed(),'a custom plan with a mixed run must report as intermixed');
% With no plan built, the static's conservative answer stands.
assert(mabr.stim.Schedule.strategyIntermixes('custom'), ...
    'the static must answer conservatively for custom');

% Departing from the invariant is used as returned, not refused.
few = mabr.stim.Schedule(tset,cfg);
few.Repetitions = 100;
few.Strategy    = 'custom';
few.StrategyFcn = @(cc) [1 1 1 2 2];
few.build();
assert(few.NumRuns == 1 && numel(few.runSequence(1)) == 5, ...
    'a plan departing from the repetition counts must be used as returned');

% The plan must render: nothing downstream of build() is a special case.
spec = tsch.renderSpec(1);
seq  = tsch.runSequence(1);
assert(numel(spec.ExpectedOnsets) == numel(seq),'onsets must match the sequence');
assert(isequal(spec.StimulusIndex(:)',seq),'renderSpec must carry the custom sequence');
assert(all(abs(spec.Polarity) == 1),'renderSpec must carry a valid polarity per onset');

% A Seed must reproduce a shuffling custom strategy exactly...
assert(isequal(seededRuns(tset,cfg,11),seededRuns(tset,cfg,11)), ...
    'a Seed must reproduce a shuffling strategy');
assert(~isequal(seededRuns(tset,cfg,11),seededRuns(tset,cfg,12)), ...
    'different seeds should give different orders');
% ...without perturbing global rng doing it.
rng(1234); a = rand();
rng(1234); seededRuns(tset,cfg,99); b = rand();
assert(a == b,'building a custom plan must not perturb global rng');
fprintf('  PASS Part F: Schedule builds, refuses, names, and renders a custom plan\n');

% ---- Part G: end-to-end through a real controller -----------------------
if isempty(ver('parallel'))
    fprintf('  SKIP Part G: Parallel Computing Toolbox not available\n');
    fprintf('== verify_custom_strategy PASSED ==\n');
    return
end

% Write a strategy to a file and resolve it the way the GUI does. Reverse
% bank order, one stimulus per run -- unmistakable in the block order, and
% something no built-in strategy produces.
tmp  = tempname;
mkdir(tmp);
name = 'mabr_verify_reverse_strategy';
fid  = fopen(fullfile(tmp,[name '.m']),'w');
fprintf(fid,'function runs = %s(ctx)\n',name);
fprintf(fid,'runs = {};\n');
fprintf(fid,'for i = ctx.numStimuli:-1:1\n');
fprintf(fid,'    runs{end+1} = repmat(i,1,ctx.repetitions(i));\n');
fprintf(fid,'end\n');
fprintf(fid,'end\n');
fclose(fid);

addpath(tmp);
% One cleanup for both, in that order: rmdir takes the folder off the path as
% a side effect, so a separate rmpath afterwards warns about a directory that
% is already gone.
cleanTmp = onCleanup(@() dropTemp(tmp)); %#ok<NASGU>
fcn      = str2func(name);
[ok,why] = mabr.stim.strategy.validate(fcn);
assert(ok,'the file-resolved strategy must validate: %s',why);

ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl)); %#ok<NASGU>
ctrl.waitUntilReady();

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',60));
ctrl.Schedule.Strategy    = 'custom';
ctrl.Schedule.StrategyFcn = fcn;
ctrl.Schedule.Repetitions = 6;
ctrl.Schedule.ISI         = 1/21.1;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.004;
ctrl.Window  = [0 0.01];
ctrl.Session.OutputPath = '';       % record without saving

ids = ctrl.Stimuli.IDs();
assert(ctrl.Schedule.NumRuns == 2,'expected one run per stimulus');
assert(isequal(cellfun(@(v) v(1),ctrl.Schedule.Runs),[2 1]), ...
    'the file-resolved strategy must have reversed the bank order');

ctrl.start();
t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 120
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete,'schedule did not complete');
assert(ctrl.Session.NumBlocks == 2, ...
    'expected two finalized blocks, got %d',ctrl.Session.NumBlocks);

% Blocks are appended in run order, so the session IS the presentation order.
order = arrayfun(@(b) char(string(b.Stim.Meta.ID)),ctrl.Session.Blocks, ...
    'UniformOutput',false);
assert(strcmp(order{1},ids{2}) && strcmp(order{2},ids{1}), ...
    'blocks arrived as %s; the custom order was not honoured',strjoin(order,' then '));
fprintf('  PASS Part G: file-resolved strategy drove the run order (%s)\n', ...
    strjoin(order,' then '));

fprintf('== verify_custom_strategy PASSED ==\n');
end

% --- helpers --------------------------------------------------------------

function assertRefused(out,ctx,id)
% normalize must refuse OUT with exactly identifier ID.
try
    mabr.stim.strategy.normalize(out,ctx);
    error('verify:notRefused','expected %s to be refused',id);
catch me
    assert(strcmp(me.identifier,id),'expected %s, got %s (%s)', ...
        id,me.identifier,me.message);
end
end

function assertBuildFails(sch,id)
% sch.build() must fail with exactly identifier ID.
try
    sch.build();
    error('verify:notRefused','expected build to fail with %s',id);
catch me
    assert(strcmp(me.identifier,id),'expected %s, got %s (%s)', ...
        id,me.identifier,me.message);
end
end

function dropTemp(tmp)
% Off the path, then gone. Both are best-effort: a test must not fail in its
% own teardown.
try, rmpath(tmp); catch, end %#ok<CTCH>
try, rmdir(tmp,'s'); catch, end %#ok<CTCH>
end

function [R,P] = planWith(set,cfg,reps,strategy,fcn)
% One plan under STRATEGY, at a fixed seed so the shuffled ones are stable.
s = mabr.stim.Schedule(set,cfg);
s.Repetitions = reps;
s.Seed        = 42;
s.Strategy    = strategy;
if ~isempty(fcn), s.StrategyFcn = fcn; end
s.build();
R = s.Runs;
P = s.Polarities;
end

function R = seededRuns(set,cfg,seed)
% A deliberately shuffling custom strategy, planned at SEED.
s = mabr.stim.Schedule(set,cfg);
s.Repetitions = 8;
s.Seed        = seed;
s.Strategy    = 'custom';
s.StrategyFcn = @(cc) randperm(cc.randStream,cc.numStimuli);
s.build();
R = s.Runs;
end
