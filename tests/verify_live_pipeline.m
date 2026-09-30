function verify_live_pipeline()
% verify_live_pipeline  mabr.compute.Pipeline's live statistics are
%                       incremental, exact, and independent of slicing.
%
%   The live cycle used to recompute everything from every sweep of the run on
%   every 50 ms step -- the per-condition means and spreads, the onset-contrast
%   correlation, the whole filtered cache copied as it grew -- so a run cost
%   the square of its length. It now keeps running statistics, updated one
%   sweep at a time in sweep order (mabr.compute.Pipeline.accumulate), over a
%   column-per-sweep cache filled in place, and extract_sweeps hands back only
%   the sweeps each call windowed.
%
%   Part A: the statistics are those of the sweeps -- mean, std and
%           partition_corr computed directly from sweeps() -- to rounding.
%   Part B: they do not depend on how the run arrives: one call, random
%           slices, and one sweep at a time give BIT-IDENTICAL results (what
%           keeps a DSP worker and this process in agreement).
%   Part C: one condition, reached a sweep at a time, passes through exactly
%           one clean sweep (SD 0) without tripping over its own masks.
%   Part D: a new artifact policy mid-run re-judges and rebuilds, and ends
%           where a pipeline that had it from the start does.
%   Part E: a new gain or filter chain mid-run rewinds extraction and ends
%           where a pipeline configured that way from the start does.
%   Part F: a dropout inside a timing pulse is part of that pulse -- not a
%           new onset -- in the detector, the live pipeline however the run
%           arrives, and finalization.
%
%   No hardware, no pool. Run:  >> verify_live_pipeline
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_live_pipeline ==\n');

cfg = mabr.Config;
fs  = cfg.DACSampleRate;
rng(11);

% ---- a synthetic run: three conditions, one of them loud enough to be judged
N   = round(2.0*fs);
tt  = (0:N-1)'/fs;
on  = round((0.02:0.019:1.96)*fs);
sig = 0.002*randn(N,1);
tim = zeros(N,1);
seq = mod(0:numel(on)-1,3) + 1;
amp = [0.02 0.05 0.3];
for k = 1:numel(on)
    i0 = on(k);
    tim(i0:i0+round(0.001*fs)) = 1;
    w = i0:i0+round(0.008*fs);
    sig(w) = sig(w) + amp(seq(k))*sin(2*pi*1000*tt(w - i0 + 1));
end
info = struct('RunId',1,'StimIndex',seq,'Stimuli',1:3);
win  = [0 0.01];
filt = mabr.FilterPolicy;
arts = mabr.ArtifactPolicy('voltage',0.1,false);      % condition 3 is "bad"

% ---- Part A: the numbers are the sweeps' ---------------------------------
p = make(cfg,win,filt,arts,info);
S = run_slices(p,sig,tim,N);                  % one call
X = p.sweeps();
assert(S.NumSweeps == numel(on) && X.n == numel(on), ...
    'expected %d sweeps, got %d',numel(on),S.NumSweeps);
L = numel(X.t)/2;
for c = 1:3
    good = X.stimIdx == c & ~X.bad;
    assert(isequal(S.CondCounts(c,:),[nnz(good) nnz(X.stimIdx == c) nnz(X.stimIdx == c & X.bad)]), ...
        'condition %d counts are wrong',c);
    if ~any(good), assert(all(isnan(S.Mean(c,:)))); continue; end
    Y = X.Y(good,:);
    assert(max(abs(S.Mean(c,:) - mean(Y,1))) <= 1e-12*max(abs(Y(:))), ...
        'condition %d: the running mean is not the mean of its sweeps',c);
    assert(max(abs(S.SD(c,:) - std(Y,0,1))) <= 1e-9*max(std(Y,0,1)), ...
        'condition %d: the running SD is not the SD of its sweeps',c);
end
clean = ~X.bad;
Rref  = mabr.metrics.partition_corr(X.Y(clean,1:L),X.Y(clean,L+1:end));
assert(abs(S.Corr - Rref) < 1e-10,'Corr %.15g is not partition_corr''s %.15g',S.Corr,Rref);
assert(S.NumArtifacts == nnz(X.bad) && S.NumArtifacts > 0, ...
    'the loud condition should have been judged artifact');
fprintf('  PASS Part A: means, SDs, counts and Corr are those of the sweeps (%d sweeps, %d rejected)\n', ...
    S.NumSweeps,S.NumArtifacts);

% ---- Part B: however the run arrives, the same bits ------------------------
cuts = sort(randperm(N-1,40));
q = make(cfg,win,filt,arts,info);
Srand = run_slices(q,sig,tim,[cuts N]);                  % random slices
r = make(cfg,win,filt,arts,info);
Sone = run_slices(r,sig,tim,[on + round(0.012*fs) N]);   % a sweep at a time
for f = {'Mean','SD','Corr','CondCounts','Latest','NumSweeps','NumClean','NumArtifacts'}
    assert(isequaln(S.(f{1}),Srand.(f{1})) && isequaln(S.(f{1}),Sone.(f{1})), ...
        'the %s depends on how the run was sliced',f{1});
end
fprintf('  PASS Part B: one call, 40 random slices and one sweep at a time agree bit for bit\n');

% ---- Part C: one condition, one sweep at a time ----------------------------
one = struct('RunId',2,'StimIndex',ones(1,numel(on)),'Stimuli',1);
p1  = make(cfg,win,filt,mabr.ArtifactPolicy,one);
g   = mabrtest.GrowingRing(sig,tim);
g.Head = on(1) + round(0.012*fs);
s = p1.step(g);
assert(s.NumSweeps == 1 && all(s.SD(1,:) == 0),'one sweep: its SD is 0');
g.Head = on(2) + round(0.012*fs);
s = p1.step(g);
assert(s.NumSweeps == 2 && any(s.SD(1,:) > 0),'two sweeps: a spread');
fprintf('  PASS Part C: one condition steps through a single clean sweep\n');

% ---- Part D: a new artifact policy mid-run ---------------------------------
arts2 = mabr.ArtifactPolicy('voltage',1,false);      % nothing is bad now
d = make(cfg,win,filt,arts,info);
g = mabrtest.GrowingRing(sig,tim);
g.Head = round(N/2); d.step(g);
d.configure([],[],arts2);
g.Head = N; Sd = d.step(g);
e = make(cfg,win,filt,arts2,info);
Se = run_slices(e,sig,tim,[round(N/2) N]);
assert(Sd.NumArtifacts == 0,'the new policy should have cleared every flag');
for f = {'Mean','SD','Corr','CondCounts'}
    assert(isequaln(Sd.(f{1}),Se.(f{1})),'re-judged %s differs from judging it so all along',f{1});
end
fprintf('  PASS Part D: a new artifact policy re-judges and rebuilds exactly\n');

% ---- Part E: a new gain or chain mid-run -------------------------------------
G = 250;
h = make(cfg,win,filt,arts2,info);
g = mabrtest.GrowingRing(sig,tim);
g.Head = round(N/2); h.step(g);
h.configure([],[],[],G);
g.Head = N; Sh = h.step(g);
k = make(cfg,win,filt,arts2,info,G);
Sk = run_slices(k,sig,tim,[round(N/2) N]);
for f = {'Mean','SD','Corr','CondCounts','Latest'}
    assert(isequaln(Sh.(f{1}),Sk.(f{1})),'after a gain change the %s differs',f{1});
end
lp = mabr.FilterPolicy(false,1500,false);
h.configure([],lp);
Sl = h.step(g);
m = make(cfg,win,lp,arts2,info,G);
Sm = run_slices(m,sig,tim,N);
for f = {'Mean','SD','Corr','CondCounts'}
    assert(isequaln(Sl.(f{1}),Sm.(f{1})),'after a filter change the %s differs',f{1});
end
fprintf('  PASS Part E: a new gain or chain rewinds extraction and matches a fresh pipeline\n');

% ---- Part F: a dropout inside a pulse is not a new onset ---------------------
% On hardware a timing pulse can fall below threshold for a moment in the
% middle -- a lost USB microframe is 24 samples at 192 kHz -- and once the 2 ms
% shadow had passed, the far side of that dropout used to be read as a new
% onset: one sweep too many, and every later sweep paired with the wrong
% presentation. The rig showed it 4 ms into a 5 ms pulse. The detector now
% re-arms only once the channel has been low for mabr.Config.OnsetRearm.
sh = round(mabr.Config.OnsetShadow*fs);
th = mabr.Config.OnsetThreshold;
ra = round(mabr.Config.OnsetRearm*fs);
pw   = round(0.005*fs);                       % 5 ms pulses, as on the rig
onF  = round((0.02:0.02:1.96)*fs);            % 20 ms apart
timF = zeros(N,1);
for k = 1:numel(onF), timF(onF(k):onF(k)+pw-1) = 0.55; end   % the rig's loop-back height
at   = [100 400 769 900];                     % samples into the pulse; 769 is the rig's
hit  = 5:7:numel(onF);
drop = zeros(1,numel(hit));
for j = 1:numel(hit)
    drop(j) = onF(hit(j)) + at(mod(j-1,numel(at)) + 1);
    timF(drop(j):drop(j)+23) = 0;             % one microframe
end
old = mabr.metrics.find_timing_onsets(timF,sh,th);        % no re-arm: the old rule
new = mabr.metrics.find_timing_onsets(timF,sh,th,ra);
assert(isequal(new(:)',onF),'with re-arm the onsets should be exactly the pulses');
assert(numel(old) > numel(onF), ...
    'the old rule should read the far side of a late dropout as an onset (the rig''s fault)');
assert(isequal(mabr.metrics.find_timing_onsets(single(timF),sh,th,ra),new), ...
    'the single and double paths disagree under re-arm');
% The boundary: a low run of exactly the re-arm length ends a pulse; one sample
% shorter does not. Past it a gap is indistinguishable from a real one, which is
% why a gap between presentations must be at least that long.
edge = [zeros(50,1); 0.55*ones(500,1); zeros(ra,1); 0.55*ones(500,1); zeros(50,1)];
assert(numel(mabr.metrics.find_timing_onsets(edge,1,th,ra)) == 2, ...
    'a low run of exactly OnsetRearm samples should end the pulse');
edge(550+ra) = 0.55;
assert(numel(mabr.metrics.find_timing_onsets(edge,1,th,ra)) == 1, ...
    'a low run one sample short of OnsetRearm should not end the pulse');

infoF = struct('RunId',3,'StimIndex',ones(1,numel(onF)),'Stimuli',1);
a = make(cfg,win,filt,mabr.ArtifactPolicy,infoF);
Sall = run_slices(a,sig,timF,N);                          % one call
assert(Sall.NumSweeps == numel(onF), ...
    'the live pipeline counted %d sweeps for %d pulses',Sall.NumSweeps,numel(onF));
% Slices that end INSIDE a dropout, just after one, and at random: the far side
% of a dropout then begins a slice, and only the look-back can tell.
cutsF = sort(unique([drop + 5, drop + 24, randperm(N-1,40)]));
b = make(cfg,win,filt,mabr.ArtifactPolicy,infoF);
Scut = run_slices(b,sig,timF,[cutsF N]);
for f = {'Mean','SD','Corr','CondCounts','NumSweeps'}
    assert(isequaln(Sall.(f{1}),Scut.(f{1})), ...
        'with dropouts, the %s depends on how the run was sliced',f{1});
end
gF = mabrtest.GrowingRing(sig,timF);
gF.Head = N;
F = a.finalize(gF,infoF.StimIndex);
assert(isequal(F.OnsetsAll(:)',onF),'finalization found %d onsets for %d pulses', ...
    numel(F.OnsetsAll),numel(onF));
fprintf(['  PASS Part F: %d microframe dropouts inside 5 ms pulses are not onsets ' ...
    '(the old rule read %d); live slices and finalization agree\n'], ...
    numel(hit),numel(old) - numel(onF));

fprintf('== verify_live_pipeline PASSED ==\n');
end


% =====================================================================
function p = make(cfg,win,filt,arts,info,gain)
if nargin < 6, gain = 1; end
p = mabr.compute.Pipeline(cfg);
p.configure(win,filt,arts,gain);
p.beginRun(info);
end

function S = run_slices(p,sig,tim,heads)
% Replay the recording to each head in turn; the last answer is the run's.
g = mabrtest.GrowingRing(sig,tim);
S = [];
for h = heads(:)'
    g.Head = h;
    s = p.step(g);
    if ~isempty(s), S = s; end
end
end
