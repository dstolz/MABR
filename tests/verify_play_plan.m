function verify_play_plan()
% verify_play_plan  mabr.stim.PlayPlan: frames on demand equal the matrix.
%
%   The worker no longer receives a play matrix: mabr.stim.Schedule.renderSpec
%   hands it a mabr.stim.PlayPlan and mabr.acq.worker_loop asks it for each
%   frame as the device is ready. The claim that makes that safe is that
%   synthesizing a frame at a time is BIT-IDENTICAL to rendering the whole
%   matrix -- overlapping presentations summed in the same order, alternating
%   polarity applied at the same onsets, explicit and synthesized timing
%   channels alike. Parts A-D check that with no hardware and no pool; Part E
%   streams a plan through the engine in TESTING loopback and reads the run
%   back off the ring buffer.
%
%   Run from anywhere on the MABR path:  >> verify_play_plan
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_play_plan ==\n');

cfg = mabr.Config;
Fs  = cfg.DACSampleRate;
fl  = cfg.frameLength;

% ---- A bank that exercises every branch of the render ------------------
% Three pips: one plain, one with alternating polarity AND an explicit 1 ms
% timing pulse, and one long enough to overlap the next presentation at the
% ISI below (so the "summed, not clipped" path is on the table).
S = struct('signal',{},'ID',{},'SampleRate',{},'Timing',{},'alternatePolarity',{});
S(1) = entry(pip(Fs,4e3,0.003),'plain',Fs,[],false);
w2   = pip(Fs,8e3,0.002);
t2   = zeros(size(w2),'single'); t2(1:round(0.001*Fs)) = 1;
S(2) = entry(w2,'alt+timing',Fs,t2,true);
S(3) = entry(pip(Fs,2e3,0.008),'long',Fs,[],false);
set  = mabr.stim.StimulusSet(S,cfg);

% ---- Part A: the plan renders the matrix the old loop did ---------------
sch = mabr.stim.Schedule(set,cfg);
sch.Strategy    = 'shuffled';
sch.Repetitions = [6 6 6];
sch.ISIMode     = 'random';
sch.ISIRange    = [0.004 0.007];        % shorter than the 8 ms pip: overlaps
sch.Seed        = 7;
sch.SilencePad  = 0.01;                 % keep N small enough for 1-sample frames
sch.build();
spec = sch.renderSpec(sch.current());

assert(isfield(spec,'Plan') && isa(spec.Plan,'mabr.stim.PlayPlan'), ...
    'renderSpec must emit a mabr.stim.PlayPlan in spec.Plan');
assert(~isfield(spec,'PlayMatrix'), ...
    'renderSpec must no longer materialize spec.PlayMatrix');
assert(sch.overlaps(),'the test bank is meant to overlap at this ISI');

plan = spec.Plan;
N    = plan.N;
assert(mod(N,fl) == 0,'the plan length must be frame-padded (N = %d)',N);
assert(isequal(plan.Onsets,spec.ExpectedOnsets(:)), ...
    'the plan''s onsets must be the spec''s ExpectedOnsets');

M   = plan.matrix();
ref = reference_matrix(set,spec);
assert(isa(M,'single') && isequal(size(M),[N 2]),'matrix() must be [N x 2] single');
assert(isequal(M,ref), ...
    'PlayPlan.matrix() differs from a whole-matrix render (max |diff| %.3g)', ...
    max(abs(double(M(:)) - double(ref(:)))));
assert(any(M(:,1) < 0) && any(M(:,2) > 0),'the render should carry signal and timing');
fprintf('  PASS Part A: plan of %d presentations renders %d x 2 identically to the old loop\n', ...
    numel(plan.Onsets),N);

% ---- Part B: any frame boundary gives the same samples ------------------
for frameLen = [fl 1000 1]
    Y = zeros(N,2,'single');
    i = 1;
    while i <= N
        hi = min(i+frameLen-1,N);
        Y(i:hi,:) = plan.range(i,hi);
        i = hi + 1;
    end
    assert(isequal(Y,M), ...
        'frames of %d samples concatenated differ from matrix()',frameLen);
end
fprintf('  PASS Part B: frame-wise synthesis is bit-identical at 1024, 1000 and 1-sample frames\n');

% ---- Part C: the cursor survives being asked out of order ---------------
plan.range(5*fl+1,6*fl);                               % somewhere in the middle
assert(isequal(plan.range(1,fl),M(1:fl,:)),'range() must rewind for an earlier request');
plan.range(N-fl+1,N);
o = plan.Onsets(3);
assert(isequal(plan.range(o-5,o+fl),M(o-5:o+fl,:)),'range() straddling an onset after a rewind');
assert(isempty(plan.range(10,9)),'an empty range is allowed and empty');
fprintf('  PASS Part C: cursor rewinds and re-walks correctly\n');

% ---- Part D: fromMatrix / fromSpec wrap an explicit matrix --------------
pm = mabr.stim.PlayPlan.fromMatrix(M);
assert(pm.N == N && isequal(pm.matrix(),M),'fromMatrix must wrap the matrix as-is');
assert(isequal(pm.range(fl+1,3*fl),M(fl+1:3*fl,:)),'fromMatrix range() must slice');
fs1 = mabr.stim.PlayPlan.fromSpec(struct('PlayMatrix',M));
fs2 = mabr.stim.PlayPlan.fromSpec(spec);
assert(isequal(fs1.matrix(),M) && fs2 == plan, ...
    'fromSpec must take the Plan when present and wrap PlayMatrix otherwise');
threw = false;
try, mabr.stim.PlayPlan.fromSpec(struct('SampleRate',Fs)); catch, threw = true; end
assert(threw,'a spec with neither Plan nor PlayMatrix must be refused');
fprintf('  PASS Part D: fromMatrix / fromSpec\n');

% ---- Part E: the worker streams from a plan -----------------------------
% A non-overlapping plan this time, so every timing pulse has a rising edge
% of its own to be recovered from the loopback.
sch2 = mabr.stim.Schedule(set,cfg);
sch2.Strategy    = 'interleaved';
sch2.Repetitions = [8 8 8];
sch2.ISI         = 0.012;
sch2.SilencePad  = 0.02;
sch2.build();
spec2 = sch2.renderSpec(sch2.current());
spec2.TestingFrameDelay = 0;            % as fast as the loopback can copy
N2 = spec2.Plan.N;
M2 = spec2.Plan.matrix();

eng = mabr.acq.Engine(cfg,true);
cleaner = onCleanup(@() delete(eng));
eng.waitUntilReady();
fprintf('  worker ready (PID %d)\n',eng.WorkerPID);

eng.prep(spec2);
wait_until(@() eng.State == mabr.acq.State.Ready,10);
eng.run();
wait_until(@() eng.State == mabr.acq.State.Completed,60);
assert(eng.State == mabr.acq.State.Completed,'plan-driven block did not complete');
assert(eng.LastStream.samples == N2, ...
    'worker streamed %d of %d samples',eng.LastStream.samples,N2);
assert(eng.head() == N2,'ring write head (%d) should equal the plan length (%d)',eng.head(),N2);

recSig = eng.RingBuffer.readSignal(1,N2);
err    = max(abs(double(recSig) - double(M2(:,1))));
assert(err < 1e-3,'loopback signal differs from the plan''s matrix (max err %.2e)',err);

recTim = eng.RingBuffer.readTiming(1,N2);
found  = mabr.metrics.find_timing_onsets(recTim,round(0.002*Fs),0.1);
assert(isequal(found(:),spec2.ExpectedOnsets(:)), ...
    'recovered %d onsets for %d planned',numel(found),numel(spec2.ExpectedOnsets));
fprintf('  PASS Part E: worker streamed %d samples from the plan; %d/%d onsets recovered, err %.1e\n', ...
    N2,numel(found),numel(spec2.ExpectedOnsets),err);

eng.kill();
fprintf('== verify_play_plan PASSED ==\n');
end


% =====================================================================
function w = pip(Fs,f,dur)
% A sine-squared-gated tone pip, [n x 1] single.
n = round(dur*Fs);
k = (0:n-1)';
w = single(0.4*sin(2*pi*f*k/Fs) .* sin(pi*k/(n-1)).^2);
end

function s = entry(w,id,Fs,t,alt)
s = struct('signal',w,'ID',id,'SampleRate',Fs,'Timing',t,'alternatePolarity',alt);
end

function y = reference_matrix(set,spec)
% The render mabr.stim.Schedule.renderSpec used to perform in full: every
% presentation summed into a preallocated matrix, in presentation order.
onsets = spec.ExpectedOnsets(:);
seq    = spec.StimulusIndex(:);
pol    = spec.Polarity(:);
N      = spec.Plan.N;
samples = zeros(N,1,'single');
timing  = zeros(N,1,'single');
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
