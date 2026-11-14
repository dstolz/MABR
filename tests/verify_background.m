function verify_background()
% verify_background  Stimuli embedded in an ongoing background, no hardware.
%
%   A run may play on a sound that continues through it (docs/Background.md):
%
%       y(i) = env(i) * G(i) * B(i, theta(i))  +  sum of pol*w
%
%   B a tiled loop or a closed-form tone, env the fade at each end of the run,
%   G and theta what each presentation does to the background (a gain
%   envelope: AM, a gap; a phase deviation: FM), and the last term the
%   presentations added to it, as before. This checks every link from the bank
%   to the file, on hand-built banks -- no stimgen, no device:
%
%   Part A  the bank contract: which entries have a background, how each
%           meets it, what reaches the metadata, and what is refused.
%   Part B  the plan renders the run: against a naive whole-run render that
%           shares none of its code, and the timing channel untouched.
%   Part C  any frame boundary gives the same samples -- exactly on a loop,
%           to the rounding of sin() on a tone -- and the cursor rewinds.
%   Part D  the run's edges: fade in from the first sample, the lead-in in
%           place of SilencePad, fade out to the last, the loop entered at a
%           recorded offset that differs from run to run, and a bank in quiet
%           rendered exactly as it always was.
%   Part E  a tone background: continuous through a frequency modulation,
%           and carrying on from the phase it ended at.
%   Part F  the fade-out and the pre-roll the worker plays, and never
%           records, when a block stops early or resumes from a pause.
%   Part G  one background per run: a run that would mix them is refused,
%           and a conventional plan gives each run its own.
%   Part H  the worker streams it: a Test Mode run, a paused one and a
%           stopped one leave exactly the plan's samples in the ring, and
%           every onset is recovered.
%   Part I  the controller says the run is aligned, holding the ring against
%           the plan on its background -- and can be made to say it is not.
%   Part J  the records: every Block, .abr and stimulation log says what the
%           run played on, and a file recorded on a background is named so.
%
%   Parts H and I start a worker on the parallel pool, as verify_play_plan
%   and verify_test_mode do.
%
%   Run from anywhere on the MABR path:  >> verify_background
%
%   See also mabr.stim.PlayPlan, mabr.stim.Schedule, mabr.stim.StimulusSet,
%   verify_play_plan, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_background ==\n');

cfg = mabr.Config;
Fs  = cfg.DACSampleRate;
fl  = cfg.frameLength;

% ---- Two backgrounds and the entries embedded in them -------------------
% A noise loop deliberately short and not a whole number of frames, so a
% short run laps it many times and the lap never falls on a frame boundary.
rs    = RandStream('twister','Seed',20261114);
nLoop = 7001;
loopB = struct('Key','noise-A','Kind','loop','SampleRate',Fs, ...
    'signal',single(0.05*randn(rs,nLoop,1)), ...
    'Type','Noise','Level',50,'HighPass',4000,'LowPass',16000, ...
    'Seed',3,'Calibrated',true);
toneB = struct('Key','tone-A','Kind','tone','SampleRate',Fs, ...
    'Frequency',3000,'Amplitude',0.1,'Type','Tone','Level',60,'Calibrated',true);

n5 = round(0.005*Fs);                       % a 5 ms event
k5 = (0:n5-1)';
amGain  = 1 + 0.5*sin(2*pi*400*k5/Fs);                  % two cycles of 400 Hz AM
gapGain = 1 - hannRamp(n5,round(0.001*Fs));             % a gap with 1 ms ramps
% FM that does NOT return to zero phase: half a cycle of a 100 Hz modulator.
df     = 300*sin(2*pi*100*k5/Fs);
fmPhi  = (2*pi/Fs)*[0; cumsum(df(1:end-1))];
assert(abs(fmPhi(end)) > 0.1,'the test FM is meant to leave the tone at a new phase');

% Bank 1: on the noise loop -- an added pip (alternating), AM, a gap.
L = struct('signal',{},'ID',{},'SampleRate',{},'alternatePolarity',{}, ...
           'Background',{},'BackgroundGain',{},'BackgroundPhase',{},'Level',{});
L(1) = entry(pip(Fs,6e3,0.004),'pip-in-noise',Fs,true, 'noise-A',[],[],40);
L(2) = entry(zeros(n5,1,'single'),'am',Fs,false,'noise-A',amGain,[],50);
L(3) = entry(zeros(n5,1,'single'),'gap',Fs,false,'noise-A',gapGain,[],50);
setL = mabr.stim.StimulusSet(L,cfg,[],loopB);

% Bank 2: on the tone -- FM, and an added pip.
T = L([]);
T(1) = entry(zeros(n5,1,'single'),'fm',Fs,false,'tone-A',[],fmPhi,60);
T(2) = entry(pip(Fs,9e3,0.003),'pip-on-tone',Fs,false,'tone-A',[],[],45);
setT = mabr.stim.StimulusSet(T,cfg,[],toneB);

% ======================================================================
%  Part A -- the bank contract
% ======================================================================
assert(isequal(setL.hasBackground(),[true true true]),'every entry of bank 1 has a background');
assert(strcmp(setL.embeddingMode(1),'add') && strcmp(setL.embeddingMode(2),'modulate') ...
    && strcmp(setL.embeddingMode(3),'modulate'),'an added pip adds; AM and a gap modulate');
assert(strcmp(setL.backgroundKey(2),'noise-A') && strcmp(setL.backgroundOf(2).Kind,'loop'), ...
    'an entry names its background and the set returns it');
assert(isequal(setL.gain(2),amGain) && isempty(setL.phase(2)) && isempty(setL.gain(1)), ...
    'gain and phase are returned as given, [] where an entry has none');
assert(isequal(setT.phase(1),fmPhi) && strcmp(setT.backgroundOf(1).Kind,'tone'), ...
    'the FM entry carries its phase on a tone');

m = setL.meta(2);
assert(strcmp(m.Embedding,'modulate'),'the metadata says how the entry meets its background');
assert(~any(isfield(m,{'Background','BackgroundGain','BackgroundPhase','signal'})), ...
    'no waveform, envelope or key may travel in the metadata');
% What defines the background is among the entry's parameters -- the set puts
% it there from the background's own description -- so a recording made on a
% background is keyed apart from the same stimulus in quiet whoever built
% the bank.
assert(isequal(m.informativeParams,{'Level','BackgroundLevel','BackgroundHighPass','BackgroundLowPass'}) ...
    && m.Level == 50 && m.BackgroundLevel == 50 ...
    && m.BackgroundHighPass == 4000 && m.BackgroundLowPass == 16000, ...
    'an entry on a noise background carries the background''s level and band as parameters');
mT = setT.meta(1);
assert(isequal(mT.informativeParams,{'Level','BackgroundLevel','BackgroundFrequency'}) ...
    && mT.BackgroundLevel == 60 && mT.BackgroundFrequency == 3000, ...
    'an entry on a tone background carries the tone''s level and frequency as parameters');

% A struct-array bank saved to a .mat carries its backgrounds in the same
% file, as a second variable.
bankFile    = [tempname '.mat'];
bankEntries = L;      %#ok<NASGU>
bankBacks   = loopB;  %#ok<NASGU>
save(bankFile,'bankEntries','bankBacks');
bankCleaner = onCleanup(@() delete(bankFile));
setF = mabr.stim.StimulusSet.fromFile(bankFile,cfg);
assert(setF.numStimuli == 3 && all(setF.hasBackground()) ...
    && isequal(setF.backgroundOf(1).signal,setL.backgroundOf(1).signal) ...
    && isequal(setF.gain(2),amGain), ...
    'a .mat holding the entries and their backgrounds loads as the bank it describes');
clear bankCleaner

% A modulation-only entry has a signal of zeros; what there is to show of it
% is the modulation.
d = setL.displayWave(3);
assert(any(d ~= 0) && abs(min(double(d)) + 1) < 1e-6, ...
    'a gap is shown as its gain''s departure from 1 (down to -1)');
assert(isequal(setL.displayWave(1),setL.signal(1)),'an added stimulus is shown as itself');
assert(any(setT.displayWave(1) ~= 0),'FM is shown as its frequency deviation');

% A bank in quiet is what it always was.
Q = mabr.stim.StimulusSet(struct('signal',pip(Fs,4e3,0.003),'ID','quiet'),cfg);
assert(~Q.hasBackground(1) && strcmp(Q.embeddingMode(1),'none') && isempty(Q.Backgrounds) ...
    && ~isfield(Q.meta(1),'Embedding'),'a bank with no background says nothing of one');

refused('mabr:stim:StimulusSet:phaseNeedsTone', ...          % FM needs a tone
    @() mabr.stim.StimulusSet(entry(zeros(n5,1,'single'),'x',Fs,false,'noise-A',[],fmPhi,1),cfg,[],loopB));
refused('mabr:stim:StimulusSet:modulationNeedsBackground', ...
    @() mabr.stim.StimulusSet(entry(zeros(n5,1,'single'),'x',Fs,false,'',amGain,[],1),cfg));
refused('mabr:stim:StimulusSet:unknownBackground', ...
    @() mabr.stim.StimulusSet(entry(zeros(n5,1,'single'),'x',Fs,false,'nowhere',[],[],1),cfg,[],loopB));
refused('mabr:stim:StimulusSet:badGain', ...
    @() mabr.stim.StimulusSet(entry(zeros(n5,1,'single'),'x',Fs,false,'noise-A',amGain(1:10),[],1),cfg,[],loopB));
refused('mabr:stim:StimulusSet:badPhase', ...                 % must start at 0
    @() mabr.stim.StimulusSet(entry(zeros(n5,1,'single'),'x',Fs,false,'tone-A',[],fmPhi + 1,1),cfg,[],toneB));
fprintf('  PASS Part A: the bank says what is embedded in what, and how; five malformed banks refused\n');

% ======================================================================
%  Part B -- the plan renders the run
% ======================================================================
sch = mabr.stim.Schedule(setL,cfg);
sch.Strategy         = 'shuffled';
sch.Repetitions      = [6 6 6];
sch.ISIMode          = 'random';
sch.ISIRange         = [0.009 0.013];
sch.Seed             = 11;
sch.SilencePad       = 0.01;
sch.BackgroundLeadIn = 0.03;
sch.BackgroundRamp   = 0.005;
sch.build();
spec = sch.renderSpec(sch.current());
plan = spec.Plan;
N    = plan.N;
assert(plan.hasBackground(),'a run of embedded stimuli must render on its background');
assert(strcmp(spec.Background.Key,'noise-A') && strcmp(spec.Background.Type,'Noise'), ...
    'the spec records which background the run plays on');

M   = plan.matrix();
ref = reference_run(setL,spec);
err = max(abs(double(M(:,1)) - double(ref(:,1))));
assert(err < 1e-6,'the plan''s render differs from a naive whole-run render (max %.3g)',err);
assert(isequal(M(:,2),ref(:,2)),'the timing channel must be exactly the one a run in quiet has');

% The same presentations with no background: the timing channel is the same
% samples, and what the background adds is everything else.
quiet = mabr.stim.PlayPlan(plan.Signals,plan.Timings,plan.Onsets,plan.StimIndex,plan.Polarity,N);
M0    = quiet.matrix();
assert(isequal(M(:,2),M0(:,2)),'a background must never write the timing channel');
between = true(N,1);
for k = 1:numel(plan.Onsets)
    between(plan.Onsets(k) + (0:numel(plan.Signals{plan.StimIndex(k)})-1)) = false;
end
assert(~any(M0(between,1)) && nnz(M(between,1)) > 0.9*nnz(between), ...
    'between presentations a run in quiet is silent and a run on a background is not');
fprintf('  PASS Part B: %d presentations on a noise loop render as the naive sum (max %.1e); timing untouched\n', ...
    numel(plan.Onsets),err);

% ======================================================================
%  Part C -- any frame boundary gives the same samples
% ======================================================================
assert(N > 5*nLoop,'the run should lap the loop several times (N = %d)',N);
rsF = RandStream('twister','Seed',5);
for frameLen = {fl,1000,1,'random'}
    Y = zeros(N,2,'single');
    i = 1;
    while i <= N
        if ischar(frameLen{1}), step = randi(rsF,2*fl); else, step = frameLen{1}; end
        hi = min(i+step-1,N);
        Y(i:hi,:) = plan.range(i,hi);
        i = hi + 1;
    end
    assert(isequal(Y,M),'frames of %s samples concatenated differ from matrix()', ...
        num2str(frameLen{1}));
end
plan.range(5*fl+1,6*fl);
assert(isequal(plan.range(1,fl),M(1:fl,:)),'range() must rewind for an earlier request');
o = plan.Onsets(4);
assert(isequal(plan.range(o-7,o+fl),M(o-7:o+fl,:)),'range() straddling an onset after a rewind');

% The tone: sin() is evaluated per frame, so equality is to its rounding.
schT = mabr.stim.Schedule(setT,cfg);
schT.Strategy         = 'interleaved';
schT.Repetitions      = [5 5];
schT.ISI              = 0.012;
schT.SilencePad       = 0.01;
schT.BackgroundLeadIn = 0.03;
schT.BackgroundRamp   = 0.005;
schT.build();
specT = schT.renderSpec(schT.current());
planT = specT.Plan;
MT    = planT.matrix();
NT    = planT.N;
Y = zeros(NT,2,'single');
i = 1;
while i <= NT
    hi = min(i+999,NT);
    Y(i:hi,:) = planT.range(i,hi);
    i = hi + 1;
end
errT = max(abs(double(Y(:)) - double(MT(:))));
assert(errT < 1e-6 && isequal(Y(:,2),MT(:,2)), ...
    'a tone background must be the same however it is sliced (max %.3g)',errT);
refT = reference_run(setT,specT);
errR = max(abs(double(MT(:,1)) - double(refT(:,1))));
assert(isequal(MT(:,2),refT(:,2)),'the tone run''s timing channel is the one a run in quiet has');
assert(errR < 1e-6,'the tone run differs from the naive render (max %.3g)',errR);
fprintf(['  PASS Part C: bit-identical on a loop at 1024-, 1000-, 1-sample and random frames; ' ...
    'a tone to %.1e\n'],max(errT,errR));

% ======================================================================
%  Part D -- the run's edges
% ======================================================================
R    = round(sch.BackgroundRamp*Fs);
lead = max(sch.BackgroundLeadIn,sch.BackgroundRamp + sch.SilencePad);
assert(abs(sch.leadPad(1) - lead) < 1e-12 && spec.ExpectedOnsets(1) == round(lead*Fs) + 1, ...
    'the first onset follows the background''s lead-in, not SilencePad');
assert(M(1,1) == 0 && M(N,1) == 0,'the background fades in from and out to silence');
assert(all(abs(M(1:R,1)) <= abs(setL.Backgrounds(1).signal(mod((0:R-1)' + spec.Background.LoopOffset,nLoop)+1)) + 1e-9), ...
    'inside the fade-in the background is never above its steady level');
% Past the ramp and before the first onset it is the loop itself, at the
% offset the record states.
i  = (R+1:spec.ExpectedOnsets(1)-1)';
assert(isequal(M(i,1),setL.Backgrounds(1).signal(mod(i - 1 + spec.Background.LoopOffset,nLoop) + 1)), ...
    'the steady lead-in must be the loop, sample for sample, from the recorded offset');
assert(abs(spec.Background.LeadIn - lead) < 1e-9 && abs(spec.Background.Ramp - R/Fs) < 1e-12, ...
    'the record states the lead-in and ramp the run was rendered with');

% A lead-in shorter than the ramp plus the baseline is lengthened to it.
sch.BackgroundLeadIn = 0;
assert(abs(sch.leadPad(1) - (sch.BackgroundRamp + sch.SilencePad)) < 1e-12, ...
    'the lead-in in force is never shorter than the ramp plus SilencePad');
sch.BackgroundLeadIn = 0.03;

% The run closes on its usual pad plus the fade-out, which therefore lies
% beyond the last response window.
closing = N - (spec.ExpectedOnsets(end) + numel(setL.signal(spec.StimulusIndex(end))) - 1);
assert(closing >= round(sch.trailPad(1)*Fs) && sch.trailPad(1) >= sch.SilencePad + sch.BackgroundRamp - 1e-12, ...
    'the closing pad must hold the fade-out beyond the usual pad');
assert(abs(sch.padSeconds(1) - (sch.leadPad(1) + sch.trailPad(1))) < 1e-12,'padSeconds adds both ends');

% Each run enters the loop somewhere else, by a rule and not a draw.
schC = mabr.stim.Schedule(setL,cfg);
schC.Strategy = 'conventional'; schC.Repetitions = 3; schC.ISI = 0.012;
schC.SilencePad = 0.01; schC.BackgroundLeadIn = 0.03; schC.BackgroundRamp = 0.005;
schC.build();
assert(schC.NumRuns == 3,'one run per stimulus');
s1 = schC.renderSpec(1); s2 = schC.renderSpec(2);
assert(s1.Background.LoopOffset ~= s2.Background.LoopOffset ...
    && s2.Background.LoopOffset == mabr.stim.Schedule.backgroundOffset(setL.Backgrounds(1),2), ...
    'successive runs must enter the loop at different, recorded places');
again = schC.renderSpec(2);
assert(isequal(again.Plan.matrix(),s2.Plan.matrix()),'rendering a run twice gives the same samples');

% A bank in quiet: no background, the old lead-in, the record of "none".
schQ = mabr.stim.Schedule(Q,cfg);
schQ.Repetitions = 4; schQ.ISI = 0.02; schQ.build();
sq = schQ.renderSpec(1);
assert(~sq.Plan.hasBackground() && strcmp(sq.Background.Type,'none') ...
    && sq.ExpectedOnsets(1) == round(schQ.SilencePad*Fs) + 1 ...
    && abs(schQ.padSeconds() - (schQ.SilencePad + schQ.trailPad())) < 1e-12 ...
    && ~schQ.runHasBackground(1), ...
    'a bank in quiet must render exactly as before, and say it had no background');
fprintf('  PASS Part D: fade in, %.0f ms lead-in, fade out; the loop entered at a recorded offset; quiet unchanged\n', ...
    1e3*lead);

% ======================================================================
%  Part E -- a tone background, through a frequency modulation
% ======================================================================
quietT = mabr.stim.PlayPlan(planT.Signals,planT.Timings,planT.Onsets,planT.StimIndex,planT.Polarity,NT);
MT0    = quietT.matrix();
bgT    = double(MT(:,1)) - double(MT0(:,1));        % the tone alone
A      = toneB.Amplitude;
RT     = round(schT.BackgroundRamp*Fs);
steady = (RT+1:NT-RT)';
% No step anywhere: the largest sample-to-sample change is bounded by the
% highest instantaneous frequency (carrier + deviation).
bound = A*2*pi*(toneB.Frequency + 300)/Fs;
assert(max(abs(diff(bgT(steady)))) <= bound + 1e-6, ...
    'the tone must be continuous through every modulation (max step %.3g, bound %.3g)', ...
    max(abs(diff(bgT(steady)))),bound);
assert(abs(max(abs(bgT(steady))) - A) < 1e-4,'frequency modulation must not change the tone''s amplitude');

% Before the first FM it is the plain tone; after the k-th it carries on
% from k times the phase one modulation leaves behind.
isFM  = planT.StimIndex == find(strcmp({setT.Stimuli(unique(specT.StimulusIndex,'stable')).ID},'fm'));
fmOn  = planT.Onsets(isFM);
pos   = @(i) i - 1 + specT.Background.LoopOffset;
tone  = @(i,phi) A*sin(2*pi*mod(toneB.Frequency*pos(i)/Fs,1) + phi);
i     = (RT+1:fmOn(1)-1)';
assert(max(abs(bgT(i) - tone(i,0))) < 1e-5,'before any modulation the background is the plain tone');
for k = 1:2
    i = (fmOn(k)+n5 : fmOn(k)+n5+200)';
    assert(max(abs(bgT(i) - tone(i,k*fmPhi(end)))) < 1e-5, ...
        'after modulation %d the tone must carry on from %d x its end phase',k,k);
end
fprintf('  PASS Part E: the tone is continuous through FM and keeps the phase each modulation leaves\n');

% ======================================================================
%  Part F -- the fade-out and the pre-roll
% ======================================================================
bgL  = double(M(:,1)) - double(M0(:,1));           % the noise background alone
i0   = spec.ExpectedOnsets(5) + 3;                 % stop in the middle of a presentation
nT   = ceil(R/fl)*fl;
tail = plan.backgroundTail(i0,nT);
assert(isequal(size(tail),[nT 2]) && ~any(tail(:,2)),'a tail is whole frames with no timing pulse');
assert(abs(double(tail(1,1)) - bgL(i0)) < 1e-6,'the tail begins where the block left off');
assert(~any(tail(R+1:end,1)) && all(abs(double(tail(1:R,1))) <= abs(bgL(i0+(0:R-1))) + 1e-6), ...
    'the tail fades to silence over the ramp and stays there');

nP   = 3*fl;
pre  = plan.backgroundLead(i0,nP);
assert(isequal(size(pre),[nP 2]) && ~any(pre(:,2)),'a pre-roll is whole frames with no timing pulse');
assert(pre(1,1) == 0,'the pre-roll fades in from silence');
assert(max(abs(double(pre(R+1:end,1)) - bgL(i0-nP+R:i0-1))) < 1e-6, ...
    'past its fade the pre-roll is the background that precedes the resume point, to the sample');
assert(~any(plan.backgroundLead(1,fl),'all'),'there is nothing to lead in before the run');

% The worker asks for the pre-roll a frame at a time: the same pre-roll.
preF = zeros(nP,2,'single');
for a = 1:fl:nP
    preF(a:a+fl-1,:) = plan.backgroundLead(i0,nP,a,a+fl-1);
end
assert(max(abs(double(preF(:)) - double(pre(:)))) < 1e-6, ...
    'the pre-roll rendered a frame at a time must be the pre-roll rendered whole');
% Resuming less than a pre-roll into the run: silence where the run had not
% begun, whole or by frame.
iE   = fl + 7;
preE = plan.backgroundLead(iE,nP);
preG = zeros(nP,2,'single');
for a = 1:fl:nP
    preG(a:a+fl-1,:) = plan.backgroundLead(iE,nP,a,a+fl-1);
end
assert(~any(preE(1:nP-iE+1,1)) && any(preE(:,1)) ...
    && max(abs(double(preG(:)) - double(preE(:)))) < 1e-6, ...
    'a pre-roll reaching back before the run is silence there, whole or by frame');
assert(~quiet.hasBackground() && ~any(quiet.backgroundTail(i0,fl),'all') ...
    && ~any(quiet.backgroundLead(i0,fl),'all'),'a run in quiet has neither');
assert(isequal(plan.range(1,N),M),'rendering a tail or a pre-roll must not disturb the plan');
fprintf('  PASS Part F: stop fades the background out, resume leads it back in, and neither is in the plan\n');

% ======================================================================
%  Part G -- one background per run
% ======================================================================
X = L([]);
X(1) = entry(pip(Fs,6e3,0.004),'in-noise',Fs,false,'noise-A',[],[],40);
X(2) = entry(pip(Fs,6e3,0.004),'in-quiet',Fs,false,'',[],[],40);
setX = mabr.stim.StimulusSet(X,cfg,[],loopB);
schX = mabr.stim.Schedule(setX,cfg);           % conventional: one stimulus per run
schX.Repetitions = 3; schX.ISI = 0.012; schX.build();
a = schX.renderSpec(1); b = schX.renderSpec(2);
assert(strcmp(a.Background.Type,'Noise') && strcmp(b.Background.Type,'none') ...
    && a.Plan.hasBackground() && ~b.Plan.hasBackground(), ...
    'a conventional plan gives each run its own stimulus''s background');
assert(b.ExpectedOnsets(1) == round(schX.SilencePad*Fs) + 1 ...
    && a.ExpectedOnsets(1) == round(schX.leadPad(1)*Fs) + 1 && schX.leadPad(1) > schX.leadPad(2), ...
    'only the run on a background plays a lead-in');
mIn = setX.meta(1); mQ = setX.meta(2);
assert(isfield(mIn,'BackgroundLevel') && ~isfield(mQ,'BackgroundLevel') ...
    && isequal(mQ.informativeParams,{'Level'}), ...
    'in one bank, only the entry in the background carries the background''s parameters');
schX.Strategy = 'interleaved';
refused('mabr:stim:Schedule:mixedBackground',@() schX.build());
assert(schX.NumRuns == 0 && schX.current() == 0, ...
    'a refused plan must not be left in place (%d runs)',schX.NumRuns);

% Two different backgrounds cannot share a run either.
Y2 = L([]);
Y2(1) = entry(pip(Fs,6e3,0.004),'on-noise',Fs,false,'noise-A',[],[],40);
Y2(2) = entry(pip(Fs,6e3,0.004),'on-tone', Fs,false,'tone-A', [],[],40);
tb = toneB; tb.Type = 'Tone';
setY = mabr.stim.StimulusSet(Y2,cfg,[],[mabr.stim.StimulusSet.validateBackground(loopB,1), ...
                                        mabr.stim.StimulusSet.validateBackground(tb,2)]);
schY = mabr.stim.Schedule(setY,cfg);
schY.Repetitions = 2; schY.ISI = 0.012; schY.build();
assert(strcmp(schY.runBackground(1),'noise-A') && strcmp(schY.runBackground(2),'tone-A'), ...
    'each run names its own background');
schY.Strategy = 'shuffled';
refused('mabr:stim:Schedule:mixedBackground',@() schY.build());
fprintf('  PASS Part G: a run has one background; a plan that would mix them is refused at build\n');

% ======================================================================
%  Part H -- the worker streams it
% ======================================================================
schH = mabr.stim.Schedule(setL,cfg);
schH.Strategy         = 'interleaved';
schH.Repetitions      = [8 8 8];
schH.ISI              = 0.012;
schH.SilencePad       = 0.02;
schH.BackgroundLeadIn = 0.05;
schH.BackgroundRamp   = 0.005;
schH.build();
specH = schH.renderSpec(schH.current());
specH.TestingFrameDelay = 0;            % as fast as the loopback can copy
NH = specH.Plan.N;
MH = specH.Plan.matrix();

eng = mabr.acq.Engine(cfg,true);
engCleaner = onCleanup(@() delete(eng));
eng.waitUntilReady();
fprintf('  worker ready (PID %d)\n',eng.WorkerPID);

eng.prep(specH);
wait_until(@() eng.State == mabr.acq.State.Ready,10);
eng.run();
wait_until(@() eng.State == mabr.acq.State.Completed,60);
assert(eng.State == mabr.acq.State.Completed,'the block did not complete');
assert(eng.LastStream.samples == NH && eng.head() == NH, ...
    'the worker streamed %d of %d samples',eng.LastStream.samples,NH);
errH = max(abs(double(eng.RingBuffer.readSignal(1,NH)) - double(MH(:,1))));
assert(errH < 1e-3,'the ring differs from the plan on its background (max %.2e)',errH);
found = mabr.metrics.find_timing_onsets(eng.RingBuffer.readTiming(1,NH),round(0.002*Fs),0.1);
assert(isequal(found(:),specH.ExpectedOnsets(:)), ...
    'a background must not disturb onset recovery (%d found, %d planned)', ...
    numel(found),numel(specH.ExpectedOnsets));

% Paused part way: nothing is written while paused or by the resume, and the
% run still ends as the plan's samples (the fade-out and pre-roll are played
% through a device only, and there is none here). A longer run, paced at
% real time, so that there is a "part way" to pause and stop it in.
schH.Repetitions = [70 70 70];
schH.build();
specP = schH.renderSpec(schH.current());
specP.TestingFrameDelay = fl/Fs;
NP = specP.Plan.N;
MP = specP.Plan.matrix();
% Streaming, and past the first frames: the head is read off the ring, which
% still holds the last run until this one's Acquire.
partWay = @() eng.State == mabr.acq.State.Acquire && eng.head() > 4*fl && eng.head() < NP;

eng.prep(specP);
wait_until(@() eng.State == mabr.acq.State.Ready,10);
eng.run();
wait_until(partWay,20);
eng.pause();
wait_until(@() eng.State == mabr.acq.State.Paused,10);
assert(eng.State == mabr.acq.State.Paused,'the block did not pause');
h0 = eng.head();
pause(0.3);
assert(eng.head() == h0 && h0 > 0 && h0 < NP,'nothing may be recorded while paused');
eng.resume();
wait_until(@() eng.State == mabr.acq.State.Completed,60);
assert(eng.State == mabr.acq.State.Completed && eng.head() == NP,'the paused block did not finish');
errP = max(abs(double(eng.RingBuffer.readSignal(1,NP)) - double(MP(:,1))));
assert(errP < 1e-3,'a paused run must still record exactly the plan (max %.2e)',errP);

% Stopped part way: what was streamed is the plan's first samples, and the
% fade-out is not among them.
eng.prep(specP);
wait_until(@() eng.State == mabr.acq.State.Ready,10);
eng.run();
wait_until(partWay,20);
eng.stop();
wait_until(@() eng.State == mabr.acq.State.Completed,30);
nS = eng.LastStream.samples;
assert(strcmp(eng.LastStream.reason,'stopped') && nS > 0 && nS < NP && eng.head() == nS, ...
    'a stopped block reports how far it got (%d of %d, head %d)',nS,NP,eng.head());
errS = max(abs(double(eng.RingBuffer.readSignal(1,nS)) - double(MP(1:nS,1))));
assert(errS < 1e-3,'a stopped run holds the plan''s samples up to the stop (max %.2e)',errS);
fprintf('  PASS Part H: complete, paused and stopped runs leave the plan''s samples in the ring; %d/%d onsets\n', ...
    numel(found),numel(specH.ExpectedOnsets));
eng.kill();
clear engCleaner

% ...and through a DEVICE, where the fade-out and the pre-roll are actually
% played. mabrtest.FakeAudioDevice is a loop-back paced at the device's rate:
% what it "records" is the frame it was handed, and only a block's own frames
% are written to the ring. So a pre-roll or a fade that reached the recording
% would be in these samples, and the run would no longer be the plan's. This
% is the one place the suite executes that code; that it SOUNDS continuous is
% still a rig check.
specD = specP;
specD.DeviceFactory    = @mabrtest.FakeAudioDevice;
specD.IdleClockSeconds = 30;
engD = mabr.acq.Engine(cfg,false);          % NOT Test Mode: a device is opened
engDCleaner = onCleanup(@() delete(engD));
engD.waitUntilReady();
partWayD = @() engD.State == mabr.acq.State.Acquire && engD.head() > 4*fl && engD.head() < NP;

engD.prep(specD);
wait_until(@() engD.State == mabr.acq.State.Ready,10);
engD.run();
wait_until(partWayD,20);
engD.pause();
wait_until(@() engD.State == mabr.acq.State.Paused,10);
assert(engD.State == mabr.acq.State.Paused,'the block did not pause on a device');
pause(0.2);                                 % the fade-out has been played by now
h0 = engD.head();
pause(0.2);
assert(engD.head() == h0 && h0 > 0 && h0 < NP, ...
    'neither the fade-out nor the paused device may be recorded');
engD.resume();
wait_until(@() engD.State == mabr.acq.State.Completed,60);
assert(engD.State == mabr.acq.State.Completed && engD.head() == NP ...
    && engD.LastStream.samples == NP, ...
    'the paused block did not finish on a device (head %d of %d)',engD.head(),NP);
errD = max(abs(double(engD.RingBuffer.readSignal(1,NP)) - double(MP(:,1))));
assert(errD < 1e-6, ...
    'on a device the fade-out and the pre-roll must stay out of the recording (max %.2e)',errD);

engD.prep(specD);
wait_until(@() engD.State == mabr.acq.State.Ready,10);
engD.run();
wait_until(partWayD,20);
engD.stop();
wait_until(@() engD.State == mabr.acq.State.Completed,30);
nD = engD.LastStream.samples;
assert(strcmp(engD.LastStream.reason,'stopped') && nD > 0 && nD < NP && engD.head() == nD, ...
    'a block stopped on a device reports how far it got (%d of %d, head %d)',nD,NP,engD.head());
errD = max(abs(double(engD.RingBuffer.readSignal(1,nD)) - double(MP(1:nD,1))));
assert(errD < 1e-6,'the fade-out a stop plays must not be recorded (max %.2e)',errD);
fprintf('  PASS Part H (device): paused, resumed and stopped through a device; only the plan''s samples recorded\n');
engD.kill();
clear engDCleaner

% ======================================================================
%  Part I -- the controller's own verdict
% ======================================================================
outDir = fullfile(tempdir, ...
    ['mabr_background_' char(datetime('now','Format','yyyyMMdd''T''HHmmssSSS'))]);
mkdir(outDir);
cleanDir = onCleanup(@() rmdir(outDir,'s')); %#ok<NASGU>

ctrl = mabr.ui.AcqController(cfg,true);      % true = Test Mode
ctrlCleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();
ctrl.setStimuli(setL);
ctrl.Session.Subject.ID = 'SUBJ_ID_BG';
ctrl.Session.OutputPath = outDir;
ctrl.Schedule.Strategy         = 'conventional';
ctrl.Schedule.Repetitions      = 6;
ctrl.Schedule.ISI              = 0.02;
ctrl.Schedule.SilencePad       = 0.02;      % so the 50 ms lead-in is the one in force
ctrl.Schedule.BackgroundLeadIn = 0.05;
ctrl.Schedule.BackgroundRamp   = 0.005;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.001;
nRuns = ctrl.Schedule.NumRuns;

ctrl.start();
t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not run to completion (state %s)',string(ctrl.State));

V = ctrl.LastAlignment;
assert(~isempty(V) && V.Aligned && V.WaveformsMatch && V.MaxError < 1e-3, ...
    'a run on a background must still check as aligned: %s',V.Summary);
assert(contains(V.Summary,'on its background'), ...
    'the verdict should say it was held against the plan on its background: %s',V.Summary);
assert(V.NumWaveforms == V.NumCompared,'every presentation should have been compared');

% ...and it can fail. The ring still holds the last run.
specI = ctrl.Schedule.renderSpec(nRuns);
good  = double(specI.ExpectedOnsets(:)');
V = ctrl.alignmentCheck(struct('OnsetsAll',good));
assert(V.Aligned && V.WaveformsMatch,'the undoctored onsets must still pass');
bad = good; bad(ceil(end/2):end) = bad(ceil(end/2):end) + 5;
V = ctrl.alignmentCheck(struct('OnsetsAll',bad));
assert(~V.Aligned && V.MaxError > 1e-3, ...
    'onsets five samples off must not match the plan on its background (max %.2e)',V.MaxError);
fprintf('  PASS Part I: %d runs on a background checked as aligned; a five-sample shift is caught\n',nRuns);

% ======================================================================
%  Part J -- the records
% ======================================================================
assert(ctrl.Session.NumBlocks == nRuns,'one block per run');
for k = 1:nRuns
    blk = ctrl.Session.Blocks(k);
    assert(isstruct(blk.Background) && strcmp(blk.Background.Key,'noise-A') ...
        && blk.Background.Level == 50 && abs(blk.Background.LeadIn - 0.05) < 1e-9 ...
        && isfinite(blk.Background.LoopOffset), ...
        'block %d must carry the background its run played on',k);
end
files = dir(fullfile(outDir,'*.abr'));
assert(numel(files) == nRuns,'one .abr per run (%d found)',numel(files));
for k = 1:numel(files)
    assert(contains(files(k).name,'_Background-50dB_'), ...
        'a file recorded on a background must say so in its name: %s',files(k).name);
    D = load(fullfile(files(k).folder,files(k).name),'-mat');
    D = D.ABR_Data;
    assert(isequal(fieldnames(D.Background),fieldnames(mabr.stim.backgroundRecord())) ...
        && strcmp(D.Background.Type,'Noise') && D.Background.HighPass == 4000 ...
        && D.Background.Seed == 3 && D.Background.Calibrated, ...
        'the file must record the background: %s',files(k).name);
end
clear ctrlCleaner                     % deletes the controller and its worker

% A block recorded in quiet: the record of "none", and the name it always had.
rec  = mabr.data.Recording(cfg.ADCSampleRate,zeros(240,1,'single'),[1 121],120,1);
meta = struct('ID','tone','alternatePolarity',false,'Frequency',8,'Level',30, ...
              'informativeParams',{{'Frequency','Level'}});
blkQ = mabr.data.Block(struct('Meta',meta,'SampleRate',Fs),rec,'2026-11-14T10:00:00');
DQ   = mabr.data.io.buildStruct(blkQ);
assert(strcmp(DQ.Background.Type,'none') ...
    && isequal(fieldnames(DQ.Background),fieldnames(mabr.stim.backgroundRecord())), ...
    'a block in quiet writes the record of no background, with the same fields');
nameQ = mabr.data.io.buildFilename(blkQ,'SUBJ-ID-7');
assert(~isempty(regexp(nameQ,'^SUBJ-ID-7_Frequency-8kHz_Level-30dB_\d{6}T\d{6}\.abr$','once')), ...
    'a file recorded in quiet keeps the strict name: %s',nameQ);
blkB = blkQ;
blkB.Background = mabr.stim.backgroundRecord(setL.Backgrounds(1),'LeadIn',1,'Ramp',0.02,'LoopOffset',0);
nameB = mabr.data.io.buildFilename(blkB,'SUBJ-ID-7');
assert(~isempty(regexp(nameB,'^SUBJ-ID-7_Frequency-8kHz_Level-30dB_Background-50dB_\d{6}T\d{6}\.abr$','once')) ...
    && isempty(regexp(nameB,'^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr','once')), ...
    'on a background the name gains its token and no longer matches the strict pattern: %s',nameB);
assert(isempty(mabr.data.io.backgroundToken(mabr.stim.backgroundRecord())) ...
    && strcmp(mabr.data.io.backgroundToken(struct('Type','Noise','Level',-7.5)),'Background-m7p5dB') ...
    && strcmp(mabr.data.io.backgroundToken(struct('Type','Tone','Level',NaN)),'Background'), ...
    'the token is empty in quiet, carries the level where there is one, and is one token');

% The stimulation log says the same.
info = struct('Run',1,'NumRuns',1,'StartTime','2026-11-14T10:00:00','SampleRate',Fs, ...
    'StimulusIndex',[1 1],'Polarity',[1 1],'OnsetSample',[1000 3000], ...
    'IDs',{{'tone'}},'StimulusMeta',{{meta}},'Background',blkB.Background);
S = mabr.data.io.buildStimLog(info);
assert(strcmp(S.Presentation.Background.Key,'noise-A') && S.Presentation.Background.LeadIn == 1, ...
    'the stimulation log records the background the run played on');
info = rmfield(info,'Background');
S = mabr.data.io.buildStimLog(info);
assert(strcmp(S.Presentation.Background.Type,'none'),'and the record of none where there was none');
assert(strcmp(mabr.stim.backgroundText(blkB.Background),'noise 4-16 kHz, 50 dB SPL') ...
    && strcmp(mabr.stim.backgroundText(mabr.stim.backgroundRecord()),'none'), ...
    'a record reads back in a few words: %s',mabr.stim.backgroundText(blkB.Background));
fprintf('  PASS Part J: blocks, .abr files, their names and the stimulation log all say what the run played on\n');

fprintf('== verify_background PASSED ==\n');
end


% =====================================================================
function w = pip(Fs,f,dur)
% A sine-squared-gated tone pip, [n x 1] single.
n = round(dur*Fs);
k = (0:n-1)';
w = single(0.4*sin(2*pi*f*k/Fs) .* sin(pi*k/(n-1)).^2);
end

function g = hannRamp(n,r)
% [n x 1]: up over r samples, 1, down over r samples.
g = ones(n,1);
u = sin(pi/2*(0:r-1)'/r).^2;
g(1:r)         = u;
g(n-r+1:n)     = flipud(u);
end

function s = entry(w,id,Fs,alt,bg,gain,phase,level)
s = struct('signal',w,'ID',id,'SampleRate',Fs,'alternatePolarity',alt, ...
    'Background',bg,'BackgroundGain',gain,'BackgroundPhase',phase,'Level',level);
end

function refused(id,fcn)
% fcn must throw the error identified by id.
try
    fcn();
catch me
    assert(strcmp(me.identifier,id),'expected %s, got %s: %s',id,me.identifier,me.message);
    return
end
error('verify_background:notRefused','expected the error %s, and nothing was raised.',id);
end

function y = reference_run(set,spec)
% The run rendered whole, the obvious way: the background over every sample,
% each presentation's gain and phase applied to it in presentation order, the
% run-edge ramp, and then the presentations summed on top. Shares no code
% with mabr.stim.PlayPlan.
onsets = spec.ExpectedOnsets(:);
seq    = spec.StimulusIndex(:);
pol    = spec.Polarity(:);
N      = spec.Plan.N;
Fs     = set.SampleRate;
rec    = spec.Background;
B      = set.background(rec.Key);

G  = ones(N,1);
TH = zeros(N,1);
for k = 1:numel(seq)
    span = onsets(k) + (0:numel(set.signal(seq(k)))-1)';
    g = set.gain(seq(k));
    if ~isempty(g), G(span) = G(span).*g; end
    p = set.phase(seq(k));
    if ~isempty(p)
        TH(span) = TH(span) + p;
        TH(span(end)+1:N) = TH(span(end)+1:N) + p(end);
    end
end

pos = (0:N-1)' + rec.LoopOffset;
if strcmp(B.Kind,'tone')
    b = B.Amplitude*sin(2*pi*mod(B.Frequency*pos/Fs,1) + TH);
else
    b = double(B.signal(mod(pos,numel(B.signal)) + 1));
end
b = G.*b;

R   = round(rec.Ramp*Fs);
env = ones(N,1);
up  = sin(pi/2*(0:R-1)'/R).^2;
env(1:R)     = up;
env(N-R+1:N) = env(N-R+1:N).*flipud(up);
samples = single(b.*env);

timing = zeros(N,1,'single');
for k = 1:numel(seq)
    w  = set.signal(seq(k));
    i0 = onsets(k);
    i1 = i0 + numel(w) - 1;
    samples(i0:i1) = samples(i0:i1) + pol(k).*w;
    t = set.timing(seq(k));
    if isempty(t)
        timing(i0:i1) = 1;
    else
        timing(i0:i1) = max(timing(i0:i1),t);
    end
end
y = [samples timing];
end

function wait_until(pred,timeout)
t0 = tic;
while ~pred() && toc(t0) < timeout
    pause(0.02);
end
end
