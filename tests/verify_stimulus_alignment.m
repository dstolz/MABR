function verify_stimulus_alignment(varargin)
% verify_stimulus_alignment  Is what we recorded the stimulus we think it is?
%
%   Everything MABR reports rests on one correspondence: the samples recorded
%   at the onset the timing pulse marks are the samples of the stimulus the
%   schedule placed there. Sweep extraction, de-interleaving, the live means,
%   the per-condition metrics and every .abr file inherit it. This file tests
%   that correspondence end to end, and it is deliberately paranoid about it:
%   the bank is built so that every condition is IDENTIFIABLE FROM ITS OWN
%   SAMPLES -- one frequency per column of the design, one amplitude per row --
%   so a mis-attribution anywhere shows up as a number that cannot be
%   explained away.
%
%       Part A  the plan: onsets, sequence and polarity agree with each other,
%               and the play matrix carries each stimulus AT its own onset
%       Part B  acquisition: every timing pulse comes back exactly where it
%               was rendered, and the signal recorded there is bit-for-bit the
%               stimulus the schedule assigned to it
%       Part C  de-interleaving: each Block holds its own condition -- its
%               mean sweep's dominant frequency is its own Frequency, and its
%               sweep count is what the plan presented
%       Part D  metrics: per-condition values track the level design (a 30 dB
%               step is a 31.62x amplitude ratio), keyed by condition through
%               the online catalog, evaluateJobs, and a real analysis window
%       Part E  the live path: the per-condition statistics the view is drawn
%               from are attributed the same way the saved blocks are
%       Part F  the live path as it actually runs -- a slice per tick rather
%               than one call over a finished block, with the boundaries
%               walked through every phase of a timing pulse
%       Part G  polarity: an alternating condition's sweeps carry the signs
%               the plan assigned, in that order
%       Part H  the compute workers: the same run through the worker gives the
%               same alignment and the same numbers
%
%   In TESTING loopback the DAC frame IS the ADC frame (plus ~1e-6 of noise),
%   which is what makes Part B exact rather than approximate: with no device
%   in the path there is no latency to allow for, so a recovered onset that is
%   off by even one sample is a bug in the plan, the render, the ring buffer or
%   the extraction -- not the rig.
%
%       >> verify_stimulus_alignment                 % loopback (no hardware)
%       >> verify_stimulus_alignment('Testing',false)  % the real rig
%
%   On the rig the loop-back cable's latency shifts every onset by the same
%   amount, so Part B asserts a CONSTANT offset (and reports it) rather than
%   zero, and Part B's sample-exact waveform comparison is skipped -- what
%   comes back through a real converter is not bit-identical to what went out.
%   Everything else is asserted identically. Part H needs a three-worker pool
%   and skips where the machine cannot provide one.
%
%   See also verify_timing_loopback (pulse recovery, jitter and drift as a rig
%   diagnostic), verify_compute_worker, verify_online_advance.
%
% Daniel Stolzberg (c) 2026

opt = parse_opts(varargin{:});
fprintf('== verify_stimulus_alignment ==\n');
if ~opt.Testing
    fprintf('  (hardware mode: streaming through the real device)\n');
end

cfg   = mabr.Config;
Fs    = cfg.DACSampleRate;
df    = cfg.decimationFactor;
adcFs = cfg.ADCSampleRate;

% A bank whose conditions are told apart by their own samples: frequency
% names the column, amplitude the row. Both frequencies sit below the ADC
% Nyquist (%g kHz) and inside the display low pass, so nothing the analysis
% path does to them can move the peak this test looks for.
freqs  = [1 2];       % kHz
levels = [20 50];     % dB -- 30 dB apart, i.e. 31.62x in amplitude
bank   = tone_bank(cfg,freqs,levels,0.008,false);
fprintf('  bank: %d conditions, %g/%g kHz x %g/%g dB, ADC rate %g kHz\n', ...
    bank.numStimuli,freqs(1),freqs(2),levels(1),levels(2),adcFs/1e3);

%% ---- Part A: the plan agrees with itself ------------------------------
sch = mabr.stim.Schedule(bank,cfg);
sch.Strategy    = 'interleaved';
sch.Repetitions = 12;
sch.ISI         = 0.02;
sch.build();
spec = sch.renderSpec(1);

seq = spec.StimulusIndex(:)';
pol = spec.Polarity(:)';
ons = spec.ExpectedOnsets(:)';
assert(numel(seq) == numel(ons) && numel(pol) == numel(ons), ...
    'the plan disagrees with itself: %d onsets, %d stimuli, %d polarities', ...
    numel(ons),numel(seq),numel(pol));
assert(numel(ons) == 12*bank.numStimuli, ...
    'expected %d presentations, the plan has %d',12*bank.numStimuli,numel(ons));

gaps = diff(ons);
assert(all(gaps == round(sch.ISI*Fs)), ...
    'onsets are not on the %g ms grid (gaps %g..%g samples)', ...
    1e3*sch.ISI,min(gaps),max(gaps));

% The play matrix must carry each stimulus AT its own onset. This is the
% render side of the same correspondence Part B checks on the recorded side.
X = spec.Plan.matrix();
for k = 1:numel(ons)
    w  = double(bank.signal(seq(k)));
    i0 = ons(k);
    got = double(X(i0:i0+numel(w)-1,1));
    assert(max(abs(got - pol(k)*w)) < 1e-6, ...
        'the play matrix does not hold stimulus %d at onset %d (presentation %d)', ...
        seq(k),i0,k);
    assert(X(i0,2) > 0.5,'no timing pulse at onset %d (presentation %d)',i0,k);
end
assert(nnz(X(:,2) > 0.5 & [true; X(1:end-1,2) <= 0.5]) == numel(ons), ...
    'the timing channel does not carry exactly one pulse per presentation');
fprintf('  PASS Part A: %d presentations, each on the ISI grid with its own waveform and pulse\n', ...
    numel(ons));

%% ---- Parts B-G: one acquisition, in this process ----------------------
ctrl = mabr.ui.AcqController(cfg,opt.Testing);
cleaner = onCleanup(@() delete(ctrl)); %#ok<NASGU>
ctrl.waitUntilReady();
% Alignment is the subject; rejection is not, and a rejected sweep would only
% muddy the counts below.
ctrl.Artifacts = mabr.ArtifactPolicy('none');

R = run_bank(ctrl,bank,sch.Repetitions,sch.ISI,'interleaved',opt);
fprintf('  run: %d presentations, %d recovered onsets, %d blocks\n', ...
    numel(R.seq),numel(R.onsets),numel(R.blocks));

%% ---- Part B: recovered onsets, and what is recorded at them -----------
assert(numel(R.onsets) == numel(R.expected), ...
    'recovered %d timing pulses, the plan rendered %d', ...
    numel(R.onsets),numel(R.expected));
offset = R.onsets(:)' - R.expected(:)';
assert(all(offset == offset(1)), ...
    ['the loop-back offset is not constant (%g..%g samples): onsets are ' ...
     'drifting relative to the plan'],min(offset),max(offset));
if opt.Testing
    assert(offset(1) == 0, ...
        'loopback recovered the onsets %d samples from where they were rendered', ...
        offset(1));
    fprintf('  PASS Part B: all %d onsets recovered sample-exact (offset 0)\n',numel(R.onsets));
else
    fprintf('  PASS Part B: all %d onsets recovered at a constant offset of %d samples (%.3f ms)\n', ...
        numel(R.onsets),offset(1),1e3*offset(1)/Fs);
end

if opt.Testing
    % The whole point, stated as strongly as it can be: the samples at each
    % recovered onset ARE the stimulus the schedule put there, sign included.
    worst = 0; worstK = 0;
    for k = 1:numel(R.onsets)
        w   = double(bank.signal(R.seq(k)));
        got = double(R.rb.readSignalAt(R.onsets(k) + (0:numel(w)-1)'));
        e   = max(abs(got - R.pol(k)*w));
        if e > worst, worst = e; worstK = k; end
    end
    assert(worst < 1e-4, ...
        ['the recorded signal at onset %d is not stimulus %d (max error %.2e) -- ' ...
         'the presentation at that onset is not the one the schedule assigned'], ...
        worstK,R.seq(max(1,worstK)),worst);
    fprintf('    every presentation matches its own waveform at its own onset (max err %.1e)\n',worst);
end

%% ---- Part C: de-interleaving keeps each condition its own -------------
assert(numel(R.blocks) == bank.numStimuli, ...
    'expected one block per condition (%d), got %d',bank.numStimuli,numel(R.blocks));
for i = 1:numel(R.blocks)
    b = R.blocks(i);
    m = b.Stim.Meta;
    u = find(strcmp(bank.IDs(),m.ID),1);
    assert(~isempty(u),'block "%s" is not a condition of the bank',m.ID);

    nWanted = nnz(R.seq == u);
    assert(b.ADC.NumSweeps == nWanted, ...
        'block "%s" holds %d sweeps; the plan presented it %d times', ...
        m.ID,b.ADC.NumSweeps,nWanted);

    fMeas = dominant_hz(double(b.ADC.SweepMean),b.ADC.SampleRate);
    assert(abs(fMeas - m.Frequency*1000) < 150, ...
        ['block "%s" says Frequency = %g kHz but its mean sweep peaks at ' ...
         '%.0f Hz -- the sweeps in it belong to another condition'], ...
        m.ID,m.Frequency,fMeas);
end
fprintf('  PASS Part C: %d blocks, each with its own sweep count and its own frequency in its mean\n', ...
    numel(R.blocks));

%% ---- Part D: the metrics land on the right conditions -----------------
% Amplitude is the other axis of the design, so a metric keyed to the wrong
% condition cannot produce the ratio the levels were built with.
store = mabr.compute.ConditionStore.empty();
for i = 1:numel(R.blocks)
    store = mabr.compute.ConditionStore.merge(store, ...
        mabr.compute.ConditionStore.fromBlock(R.blocks(i)));
end
e   = mabr.metrics.online.catalog('rms');
job = struct('Name',e.Name,'Fcn',e.Fcn,'Window',[0 10]);
vals = mabr.compute.evaluateJobs(store,job);
keys = {store.Key};

expectRatio = 10^(diff(levels)/20);
for f = freqs
    lo = metric_for(keys,vals,sprintf('%gkHz_%gdB',f,levels(1)));
    hi = metric_for(keys,vals,sprintf('%gkHz_%gdB',f,levels(2)));
    got = hi/lo;
    assert(abs(got/expectRatio - 1) < 0.05, ...
        ['at %g kHz the %g dB condition is %.2fx the %g dB one; the bank was ' ...
         'built %.2fx apart -- the metric is not on the condition it is labelled'], ...
        f,levels(2),got,levels(1),expectRatio);
end
% ... and across frequency at one level the two must NOT differ, which is the
% control: it fails if the frequencies have been swapped between conditions.
for L = levels
    a = metric_for(keys,vals,sprintf('%gkHz_%gdB',freqs(1),L));
    b = metric_for(keys,vals,sprintf('%gkHz_%gdB',freqs(2),L));
    assert(abs(a/b - 1) < 0.15, ...
        'at %g dB the two frequencies differ by %.2fx; they were built at one amplitude', ...
        L,max(a,b)/min(a,b));
end

% The same numbers through a real analysis window, keyed by its own roster.
mp = mabr.ui.MetricPlot();
cleanM = onCleanup(@() delete(mp)); %#ok<NASGU>
mp.Metric = 'rms';
mp.Window = [0 10];
for i = 1:numel(R.blocks), mp.addBlock(R.blocks(i)); end
V = mp.values();
assert(numel(V) == bank.numStimuli,'the window plotted %d conditions, not %d', ...
    numel(V),bank.numStimuli);
for i = 1:numel(V)
    ref = metric_for(keys,vals,V(i).Key);
    assert(abs(V(i).Value - ref) <= 1e-9*max(1,abs(ref)), ...
        'the analysis window''s value for "%s" (%g) is not the metric for that condition (%g)', ...
        V(i).Key,V(i).Value,ref);
    u = find(strcmp(bank.IDs(),V(i).Key),1);
    assert(V(i).Params.Frequency == bank.meta(u).Frequency && ...
           V(i).Params.Level     == bank.meta(u).Level, ...
        'the analysis window has the wrong parameters on condition "%s"',V(i).Key);
end
fprintf('  PASS Part D: %.2fx level ratio recovered per frequency; window values keyed to the right conditions\n', ...
    expectRatio);

%% ---- Part E: the live statistics are attributed the same way ----------
% Re-extract the run just acquired with a pipeline of this test's own -- the
% same object the live view is fed from, whichever process runs it.
p = mabr.compute.Pipeline(cfg);
p.configure(ctrl.Window,ctrl.Filters,ctrl.Artifacts);
p.beginRun(struct('RunId',1,'StimIndex',R.seq,'Stimuli',R.stimList, ...
    'Labels',{arrayfun(@(u) bank.id(u),R.stimList,'UniformOutput',false)}));
stats = p.step(R.rb);
assert(~isempty(stats),'the pipeline recovered no sweeps from the completed run');
assert(stats.NumSweeps == numel(R.onsets), ...
    'the pipeline found %d sweeps; %d onsets were recorded',stats.NumSweeps,numel(R.onsets));

for c = 1:numel(stats.Stimuli)
    u = stats.Stimuli(c);
    m = bank.meta(u);
    assert(stats.CondCounts(c,2) == nnz(R.seq == u), ...
        'the live statistics give "%s" %d sweeps; the plan presented it %d', ...
        m.ID,stats.CondCounts(c,2),nnz(R.seq == u));
    fMeas = dominant_hz(stats.Mean(c,:),adcFs);
    assert(abs(fMeas - m.Frequency*1000) < 150, ...
        ['the live mean on row %d is labelled "%s" (%g kHz) but peaks at %.0f Hz -- ' ...
         'the sweeps behind it belong to another condition'], ...
        c,m.ID,m.Frequency,fMeas);
end
% The live means and the saved blocks are two paths over the same samples, so
% their amplitude ordering has to be the same one the bank was built with.
for f = freqs
    lo = live_rms(stats,bank,sprintf('%gkHz_%gdB',f,levels(1)));
    hi = live_rms(stats,bank,sprintf('%gkHz_%gdB',f,levels(2)));
    assert(abs((hi/lo)/expectRatio - 1) < 0.10, ...
        'the live means at %g kHz are %.2fx apart, not the %.2fx the bank was built with', ...
        f,hi/lo,expectRatio);
end
fprintf('  PASS Part E: live per-condition statistics carry the right counts, frequency and level\n');

%% ---- Part F: the same, arriving a slice at a time ----------------------
% Part E extracted a finished block in ONE call. The live path never does
% that: it extracts a slice per tick, and a timing pulse spans its whole
% presentation, so a slice boundary routinely lands INSIDE a pulse. That is
% different code -- mabr.metrics.extract_sweeps' cursor -- and it is the code
% the operator actually watches, so it gets its own assertions, with the
% boundaries driven deliberately through every phase of a pulse rather than
% wherever a timer happened to land.
[sig,tim] = R.rb.readBlock();
g = mabrtest.GrowingRing(sig,tim);
q = mabr.compute.Pipeline(cfg);
q.configure(ctrl.Window,ctrl.Filters,ctrl.Artifacts);
q.beginRun(struct('RunId',2,'StimIndex',R.seq,'Stimuli',R.stimList, ...
    'Labels',{arrayfun(@(u) bank.id(u),R.stimList,'UniformOutput',false)}));

% A step that is not a whole number of ISIs, so successive boundaries walk
% through the pulse instead of always landing at the same offset in it.
stepN = round(0.037*Fs);
inc   = [];
while g.Head < g.full()
    g.Head = min(g.Head + stepN,g.full());
    s = q.step(g);
    if ~isempty(s), inc = s; end
end
assert(~isempty(inc),'the incremental replay recovered no sweeps at all');
assert(inc.NumSweeps == numel(R.onsets), ...
    ['arriving a slice at a time gives %d sweeps; the same samples in one ' ...
     'call give %d. A pulse straddling a slice boundary is being counted ' ...
     'twice, which shifts every later sweep onto the wrong presentation'], ...
    inc.NumSweeps,numel(R.onsets));
for c = 1:numel(inc.Stimuli)
    u = inc.Stimuli(c);
    m = bank.meta(u);
    assert(inc.CondCounts(c,2) == nnz(R.seq == u), ...
        'the incremental path gives "%s" %d sweeps; the plan presented it %d', ...
        m.ID,inc.CondCounts(c,2),nnz(R.seq == u));
    fMeas = dominant_hz(inc.Mean(c,:),adcFs);
    assert(abs(fMeas - m.Frequency*1000) < 150, ...
        ['the incremental mean labelled "%s" (%g kHz) peaks at %.0f Hz -- ' ...
         'its sweeps have been attributed to the wrong presentations'], ...
        m.ID,m.Frequency,fMeas);
end
% Slice by slice must reach the same place as all at once.
for c = 1:numel(inc.Stimuli)
    c1 = find(stats.Stimuli == inc.Stimuli(c),1);
    assert(max(abs(inc.Mean(c,:) - stats.Mean(c1,:))) < 1e-9, ...
        'the incremental and single-call means differ for "%s"', ...
        bank.meta(inc.Stimuli(c)).ID);
end
fprintf('  PASS Part F: %d slices reach the same %d sweeps, counts and means as one call\n', ...
    ceil(g.full()/stepN),inc.NumSweeps);

%% ---- Part G: polarity ---------------------------------------------------
alt = tone_bank(cfg,freqs(1),levels(2),0.008,true);
A = run_bank(ctrl,alt,8,0.02,'blocked',opt);
assert(numel(A.blocks) == 1,'the alternating run produced %d blocks, not 1',numel(A.blocks));
sp = A.blocks(1).SweepPolarity(:)';
assert(numel(sp) == numel(A.seq), ...
    'the block records %d polarities for %d presentations',numel(sp),numel(A.seq));
assert(isequal(sp,A.pol(:)'), ...
    'the block''s polarities are not the ones the plan assigned');
assert(all(abs(diff(sp)) == 2), ...
    'an alternating condition did not alternate: %s',mat2str(sp));
if opt.Testing
    w = double(alt.signal(1));
    for k = 1:numel(A.onsets)
        got = double(A.rb.readSignalAt(A.onsets(k) + (0:numel(w)-1)'));
        assert(max(abs(got - A.pol(k)*w)) < 1e-4, ...
            'presentation %d was recorded with the wrong sign',k);
    end
end
fprintf('  PASS Part G: %d presentations alternate +1/-1 in the order the block records\n',numel(sp));

delete(ctrl); clear cleaner

%% ---- Part H: the same, through the compute workers ---------------------
[pool,ok] = mabr.pool(3);
if ~ok
    fprintf(['  SKIP Part H: the parallel pool cannot hold three workers on this ' ...
             'machine (it has %d).\n'],pool.NumWorkers);
    fprintf('== verify_stimulus_alignment PASSED ==\n');
    return
end

wc = mabr.ui.AcqController(cfg,opt.Testing,[],false,true);
cleanW = onCleanup(@() delete(wc)); %#ok<NASGU>
wc.waitUntilReady();
wc.Artifacts = mabr.ArtifactPolicy('none');
assert(wc.usingWorkerDSP(),'the DSP worker did not come up; Part H would prove nothing');

W = run_bank(wc,bank,sch.Repetitions,sch.ISI,'interleaved',opt);
assert(numel(W.blocks) == bank.numStimuli, ...
    'the worker-served run produced %d blocks, not %d',numel(W.blocks),bank.numStimuli);
for i = 1:numel(W.blocks)
    m = W.blocks(i).Stim.Meta;
    u = find(strcmp(bank.IDs(),m.ID),1);
    assert(W.blocks(i).ADC.NumSweeps == nnz(W.seq == u), ...
        'worker block "%s" holds %d sweeps; the plan presented it %d', ...
        m.ID,W.blocks(i).ADC.NumSweeps,nnz(W.seq == u));
    fMeas = dominant_hz(double(W.blocks(i).ADC.SweepMean),W.blocks(i).ADC.SampleRate);
    assert(abs(fMeas - m.Frequency*1000) < 150, ...
        'worker block "%s" (%g kHz) peaks at %.0f Hz',m.ID,m.Frequency,fMeas);
end

% And the worker's own live statistics, over the run still in the ring.
wc.Compute.runStart(struct('RunId',9911,'StimIndex',W.seq,'Stimuli',W.stimList, ...
    'Labels',{arrayfun(@(u) bank.id(u),W.stimList,'UniformOutput',false)}, ...
    'Meta',{arrayfun(@(u) bank.meta(u),1:bank.numStimuli,'UniformOutput',false)}));
ws = []; last = -1; t0 = tic;
while toc(t0) < 20
    pause(0.1);
    s = wc.Compute.live();
    if isempty(s), continue; end
    if s.NumSweeps > 0 && s.NumSweeps == last, ws = s; break; end
    last = s.NumSweeps;
end
wc.Compute.runEnd(9911);
assert(~isempty(ws),'the DSP worker published no statistics for the completed run');
for c = 1:numel(ws.Stimuli)
    m = bank.meta(ws.Stimuli(c));
    fMeas = dominant_hz(ws.Mean(c,:),adcFs);
    assert(abs(fMeas - m.Frequency*1000) < 150, ...
        ['the worker''s live mean on row %d is labelled "%s" (%g kHz) but peaks ' ...
         'at %.0f Hz'],c,m.ID,m.Frequency,fMeas);
    assert(ws.CondCounts(c,2) == nnz(W.seq == ws.Stimuli(c)), ...
        'the worker gives "%s" %d sweeps; the plan presented it %d', ...
        m.ID,ws.CondCounts(c,2),nnz(W.seq == ws.Stimuli(c)));
end
fprintf('  PASS Part H: the worker-served run aligns and counts identically (%d blocks, %d live conditions)\n', ...
    numel(W.blocks),numel(ws.Stimuli));

fprintf('== verify_stimulus_alignment PASSED ==\n');
end


% =====================================================================
function R = run_bank(ctrl,bank,reps,isi,strategy,opt)
% Acquire one schedule and return everything needed to hold the recording
% against the plan that produced it.
ctrl.setStimuli(bank);
ctrl.Session.Subject.ID = 'ALIGN';
ctrl.Session.OutputPath = '';                  % record without saving
ctrl.Schedule.Strategy    = strategy;
ctrl.Schedule.Repetitions = reps;
ctrl.Schedule.ISI         = isi;
apply_audio_schedule(ctrl,opt);
ctrl.Schedule.build();
if opt.Testing
    ctrl.Schedule.TestingFrameDelay = ctrl.Config.frameLength/ctrl.Config.DACSampleRate;
end
% Every presentation must be recorded for the counts below to mean anything.
ctrl.AdvanceFcn    = @mabr.stim.advance.num_sweeps;
ctrl.AdvanceParams = struct('targetSweeps',Inf,'corrThreshold',1,'minSweeps',Inf, ...
                            'maxSweeps',Inf);

nBefore = ctrl.Session.NumBlocks;
spec    = ctrl.Schedule.renderSpec(ctrl.Schedule.NumRuns);
ctrl.start();
t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 180
    pause(0.02);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not complete (state %s)',string(ctrl.State));

R    = struct();
R.rb = ctrl.Engine.RingBuffer;
R.expected = spec.ExpectedOnsets(:)';
R.seq      = spec.StimulusIndex(:)';
R.pol      = spec.Polarity(:)';
R.stimList = unique(R.seq,'stable');
[~,tim]    = R.rb.readBlock();
R.onsets   = mabr.metrics.find_timing_onsets(tim, ...
    round(0.002*ctrl.Config.DACSampleRate),0.1);
R.onsets   = R.onsets(:)';
R.blocks   = ctrl.Session.Blocks(nBefore+1:end);
end


function f = dominant_hz(x,fs)
% The frequency a trace is mostly made of. Zero-padded so the peak is read off
% a fine grid rather than the sweep's own coarse one.
x = double(x(:));
x = x - mean(x);
n = numel(x);
if n < 8, f = NaN; return; end
N = 2^nextpow2(max(4096,4*n));
X = abs(fft(x.*hann(n),N));
X = X(1:floor(N/2)+1);
[~,k] = max(X);
f = (k-1)*fs/N;
end


function v = metric_for(keys,vals,key)
i = find(strcmp(keys,key),1);
assert(~isempty(i),'no condition "%s" in the table (%s)',key,strjoin(keys,', '));
v = vals(1,i);
assert(isfinite(v),'the metric for "%s" is not a number',key);
end


function v = live_rms(stats,bank,key)
% RMS of one condition's live mean, found by the stimulus its row names.
u = find(strcmp(bank.IDs(),key),1);
c = find(stats.Stimuli == u,1);
assert(~isempty(c),'no live row for condition "%s"',key);
m = stats.Mean(c,:);
v = sqrt(mean(m(isfinite(m)).^2));
end


function set = tone_bank(cfg,freqs,levels,pipDur,alternate)
% A Frequency x Level grid of gated tone pips, like mabr.stim.demoStimuli but
% with the frequencies chosen to survive the analysis path: both below the ADC
% Nyquist AND inside the display low pass, so the peak this file looks for is
% the one that was played.
Fs   = cfg.DACSampleRate;
nPip = round(Fs*pipDur);
t    = (0:nPip-1)'/Fs;
win  = window(@blackmanharris,nPip);

stim = struct('signal',{},'ID',{},'SampleRate',{},'Repetitions',{}, ...
              'Frequency',{},'Level',{},'alternatePolarity',{});
for f = freqs
    pip0 = sin(2*pi*f*1000*t).*win;
    for L = levels
        amp = 10^((L-80)/20);
        stim(end+1) = struct( ...                                 %#ok<AGROW>
            'signal',            single(amp*pip0), ...
            'ID',                sprintf('%gkHz_%gdB',f,L), ...
            'SampleRate',        Fs, ...
            'Repetitions',       64, ...
            'Frequency',         f, ...
            'Level',             L, ...
            'alternatePolarity', alternate);
    end
end
set = mabr.stim.StimulusSet(stim,cfg,struct('Kind','demo'));
end


function opt = parse_opts(varargin)
opt = struct('Testing',true,'Device','','PlayerChannels',[],'RecorderChannels',[]);
for i = 1:2:numel(varargin)
    f = validatestring(varargin{i},fieldnames(opt),'verify_stimulus_alignment');
    opt.(f) = varargin{i+1};
end
if ~opt.Testing && isempty(opt.Device)
    % The rig's own settings, the way verify_timing_loopback takes them.
    a = mabr.AudioSettings.loadPrefs();
    opt.Device = a.Device;
    if isempty(opt.PlayerChannels),   opt.PlayerChannels   = a.PlayerChannels;   end
    if isempty(opt.RecorderChannels), opt.RecorderChannels = a.RecorderChannels; end
end
end


function apply_audio_schedule(ctrl,opt)
if opt.Testing, return; end
if ~isempty(opt.Device),           ctrl.Schedule.Device           = opt.Device;           end
if ~isempty(opt.PlayerChannels),   ctrl.Schedule.PlayerChannels   = opt.PlayerChannels;   end
if ~isempty(opt.RecorderChannels), ctrl.Schedule.RecorderChannels = opt.RecorderChannels; end
end
