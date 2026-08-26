function verify_isi_jitter()
% verify_isi_jitter  Confirm mabr.stim.Schedule spaces presentations the way
%                    ISIMode says: a strict grid, or a uniform draw per
%                    interval from ISIRange.
%
%   Part A (defaults & validation): a fresh schedule is 'fixed', MeanISI and
%   MinISI both report the scalar ISI, a descending ISIRange is refused rather
%   than silently sorted, and an unknown ISIMode cannot be assigned at all.
%   Part B (fixed is unchanged): onsets land exactly on round(Fs*ISI), which is
%   what every existing test and every saved file assumes.
%   Part C (random): every drawn interval lies inside the range, the intervals
%   actually vary, they span the range rather than hugging one end, and the
%   presentation count is untouched -- randomizing the spacing must not add or
%   drop a single sweep.
%   Part D (the timing channel still describes it): find_timing_onsets recovers
%   the jittered onsets exactly from the rendered timing column, so sweep
%   extraction needs to know nothing about how the onsets were spaced.
%   Part E (reproducibility): a Seed fixes the timing as well as the order, and
%   drawing the intervals never disturbs the global rng.
%   Part F (reporting): MinISI drives overlaps() -- the shortest draw is what
%   collides -- while summary() estimates duration from the mean.
%
%   No hardware, no parallel pool. Run:  >> verify_isi_jitter
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_isi_jitter ==\n');

cfg = mabr.Config;
set = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 60], ...
                                'PipDuration',0.005);
Fs  = set.SampleRate;

% ---- Part A: defaults & validation ---------------------------------------
s = mabr.stim.Schedule(set,cfg);
assert(strcmp(s.ISIMode,'fixed'),'default ISIMode should be ''fixed''');
assert(~s.isRandomISI(),'a fresh schedule should not be randomizing');
assert(s.MeanISI == s.ISI && s.MinISI == s.ISI, ...
    'under ''fixed'' both MeanISI and MinISI are just ISI');

threw = false;
try, s.ISIRange = [0.05 0.02]; catch me, threw = strcmp(me.identifier,'mabr:stim:Schedule:isiRange'); end
assert(threw,'a descending ISIRange must be refused, not sorted into shape');

threw = false;
try, s.ISIMode = 'jittered'; catch, threw = true; end
assert(threw,'an unknown ISIMode must be rejected on assignment');
fprintf('  PASS Part A: defaults, and both ISI settings validate\n');

% ---- Part B: fixed spacing is exactly as before ---------------------------
s.Strategy    = 'blocked';
s.Repetitions = [8 8];
s.ISI         = 0.02;
s.build();
spec = s.renderSpec(1);
d = diff(spec.ExpectedOnsets);
assert(all(d == round(Fs*0.02)), ...
    'fixed ISI must still put every onset on the round(Fs*ISI) grid');
fprintf('  PASS Part B: ''fixed'' spacing unchanged (%d samples, %.2f ms)\n', ...
    d(1),1e3*d(1)/Fs);

% ---- Part C: random spacing lies in the range and varies ------------------
lo = 0.015; hi = 0.030;
r  = mabr.stim.Schedule(set,cfg);
r.Strategy    = 'blocked';
r.Repetitions = [200 200];
r.ISIRange    = [lo hi];
r.ISIMode     = 'random';
r.build();
rspec = r.renderSpec(1);

assert(numel(rspec.ExpectedOnsets) == 200 && numel(rspec.StimulusIndex) == 200, ...
    'randomizing the ISI must not change how many presentations a run holds');

d = diff(rspec.ExpectedOnsets);
assert(all(d >= round(Fs*lo)-1) && all(d <= round(Fs*hi)+1), ...
    'every drawn interval must lie inside ISIRange (got %.2f..%.2f ms for %.2f..%.2f)', ...
    1e3*min(d)/Fs,1e3*max(d)/Fs,1e3*lo,1e3*hi);
assert(numel(unique(d)) > 1,'random intervals must actually vary');

% Uniform over the range, not clustered: with 199 draws the extremes should
% land near the ends and the mean near the middle. Loose bounds -- this is
% catching a range that was ignored or halved, not testing rand itself.
span = round(Fs*(hi-lo));
assert(min(d) < round(Fs*lo) + 0.2*span && max(d) > round(Fs*hi) - 0.2*span, ...
    'drawn intervals should span the range, not hug one end of it');
assert(abs(mean(d) - Fs*mean([lo hi])) < 0.1*span, ...
    'the mean drawn interval should sit near the middle of the range');
fprintf('  PASS Part C: %d intervals, %.2f..%.2f ms (mean %.2f), range %.2f..%.2f ms\n', ...
    numel(d),1e3*min(d)/Fs,1e3*max(d)/Fs,1e3*mean(d)/Fs,1e3*lo,1e3*hi);

% ---- Part D: the timing channel carries the jittered onsets ---------------
% Sweep extraction reads onsets off the timing column and nothing else, so a
% jittered run is legible to it only if the pulses moved with the stimuli.
play   = rspec.Plan.matrix();
timing = play(:,2);
found  = mabr.metrics.find_timing_onsets(timing,round(0.002*Fs),0.1);
assert(isequal(found(:),rspec.ExpectedOnsets(:)), ...
    ['the timing channel must carry one pulse at each jittered onset ' ...
     '(found %d pulses for %d expected onsets)'], ...
    numel(found),numel(rspec.ExpectedOnsets));

% And the stimulus really moved with the pulse rather than staying on the old
% grid: each pip's full energy sits in the window starting at its own onset.
sig  = play(:,1);
nPip = numel(set.signal(1));
pk   = arrayfun(@(o) max(abs(sig(o:o+nPip-1))),rspec.ExpectedOnsets);
assert(all(pk > 0.5*max(abs(sig))), ...
    'each pip must sit at the jittered onset its timing pulse marks');
fprintf('  PASS Part D: all %d timing pulses recovered at the jittered onsets\n',numel(found));

% ---- Part E: reproducible under Seed, and rng-neutral ---------------------
a = mabr.stim.Schedule(set,cfg);
a.Strategy = 'shuffled'; a.Repetitions = [20 20];
a.ISIRange = [lo hi]; a.ISIMode = 'random'; a.Seed = 42;
a.build();
b = mabr.stim.Schedule(set,cfg);
b.Strategy = 'shuffled'; b.Repetitions = [20 20];
b.ISIRange = [lo hi]; b.ISIMode = 'random'; b.Seed = 42;
b.build();
assert(isequal(a.renderSpec(1).ExpectedOnsets,b.renderSpec(1).ExpectedOnsets), ...
    'a Seed must fix the drawn intervals, not just the presentation order');

st = rng();                      % the user's stream, restored below
restore = onCleanup(@() rng(st));
rng(7,'twister');
before = rand(1,3);
rng(7,'twister');
r.renderSpec(1);                 % draws 199 intervals
after = rand(1,3);
assert(isequal(before,after), ...
    'rendering must draw from the schedule''s own RandStream, not the global rng');
fprintf('  PASS Part E: seeded timing reproduces; global rng untouched\n');

% ---- Part F: MinISI warns, MeanISI estimates ------------------------------
long = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',30,'PipDuration',0.020);
o = mabr.stim.Schedule(long,cfg);
o.Repetitions = 4;
o.ISIRange = [0.015 0.030]; o.ISIMode = 'random';
o.build();
assert(o.MinISI == 0.015 && o.MeanISI == 0.0225,'MinISI/MeanISI must report the range''s ends and middle');
assert(o.overlaps(), ...
    ['a 20 ms stimulus overlaps a range whose minimum is 15 ms -- one short ' ...
     'draw is enough, so overlaps() must judge on MinISI and not the mean']);

o.ISIRange = [0.025 0.030];
assert(~o.overlaps(),'a 20 ms stimulus fits every draw from a 25..30 ms range');

sum1 = o.summary();
o2 = mabr.stim.Schedule(long,cfg); o2.Repetitions = 4;
o2.ISI = o.MeanISI; o2.build();
assert(abs(sum1.duration - o2.summary().duration) < 1e-9, ...
    'a randomized plan''s estimated duration is the fixed-ISI one at the mean interval');
assert(strcmp(sum1.isiMode,'random') && sum1.isi == o.MeanISI, ...
    'summary() must report which ISI mode produced it');
fprintf('  PASS Part F: overlaps() uses MinISI; summary() estimates from MeanISI\n');

fprintf('== verify_isi_jitter PASSED ==\n');
end
