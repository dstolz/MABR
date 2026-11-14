function verify_run_archive()
% verify_run_archive  A run of any length: recorded runs longer than the
%                     acquisition ring buffer, archived as they stream.
%
%   The ring buffer holds Config.maxInputBufferLength samples (5.8 min at
%   192 kHz), and a recorded run used to be refused past that
%   (mabr:stim:Schedule:tooLong), because finalization read the run whole out
%   of the ring. A run longer than the ring is now archived as it streams
%   (mabr.compute.RunArchive): its onsets and its decimated signal are made a
%   slice at a time, and finalization works from them. This file shows the
%   archive is the whole read, exactly, and that what cannot be read is said.
%
%   Part A: mabr.metrics.OnsetTracker, fed a timing channel a slice at a time
%           (one call, random slices, one sample at a time), finds exactly
%           find_timing_onsets' onsets over the whole channel -- through
%           dropouts inside pulses, a channel that starts high, pulses closer
%           than the shadow, and negative noise.
%   Part B: mabr.compute.Decimator, fed a signal in uneven pieces, is
%           resample(x,1,q) for every decimation factor a supported rate
%           gives (reported: bit-identical or not, and the largest error).
%   Part C: a run that FITS the ring, archived (stepped, and archived only
%           at close as a late reader would) and not: the same finalization
%           -- onsets, pairing, parts, flags -- and the same data.
%   Part D: a run SEVEN TIMES the ring, through a ring that genuinely
%           overwrites (mabrtest.WrappingRing): finalized from its archive it
%           is the run finalized from a ring long enough to hold it; and its
%           live statistics are those of a pipeline that saw it whole.
%   Part E: a reader that falls a whole lap behind: the archive stops at the
%           first sample it could not read, says so, and what came before is
%           kept exactly -- a run stopped at that sample.
%   Part F: a wrapped block with NO archive is refused, never finalized from
%           its last lap (which would pair the first pulse left with the
%           first presentation).
%   Part G: mabr.stim.Schedule renders a recorded run longer than the ring
%           (it used to refuse with tooLong), stimulation only too, and the
%           custom-strategy context reads no run-length limit.
%   Part H: the ring header counts past 2^32 samples (6.2 h at 192 kHz),
%           and a header from before that is recreated, not misread.
%
%   No hardware, no pool. Run:  >> verify_run_archive
%
%   The end-to-end paths -- a controller archiving a run in Test Mode, and
%   the DSP worker archiving it with the controller keeping its own copy --
%   are verify_stimulus_alignment Part J and verify_compute_worker Part I.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_run_archive ==\n');

cfg = mabr.Config;
fs  = cfg.DACSampleRate;
df  = cfg.decimationFactor;
shadow = round(mabr.Config.OnsetShadow*fs);
rearm  = round(mabr.Config.OnsetRearm*fs);
thr    = mabr.Config.OnsetThreshold;
rs = RandStream('mt19937ar','Seed',20261114);

%% ---- Part A: the onset tracker is find_timing_onsets -------------------
n   = 60000;
tim = single(0.03*randn(rs,n,1));          % negative half included
tim(1:500) = 1;                            % starts inside a pulse
k = 2000;
while k < n - 2000
    w = randi(rs,[4 1500]);                % short and long pulses
    tim(k:k+w-1) = 1;
    if w > 400 && rand(rs) < 0.5           % a microframe dropout inside it
        d = k + randi(rs,[50 w-80]);
        tim(d:d+23) = 0;
    end
    k = k + w + randi(rs,[20 2500]);       % some gaps shorter than the re-arm
end
tim(45000:45010) = 1; tim(45200:45210) = 1; tim(45400:45410) = 1;   % a chain within one shadow
tim(50000:50300) = single(0.7);            % the single rounding of a threshold

cases = {shadow,thr,rearm; shadow,thr,0; 1,thr,1; 5,0.7,40; shadow,0.95,200};
for c = 1:size(cases,1)
    [sh,th,ra] = cases{c,:};
    ref = col(mabr.metrics.find_timing_onsets(tim,sh,th,ra));
    assert(numel(ref) > 3,'Part A case %d: the test channel should have onsets',c);
    for mode = 1:2
        t = mabr.metrics.OnsetTracker(sh,th,ra);
        switch mode
            case 1, t.feed(tim);
            case 2
                i = 1;
                while i <= n
                    m = min(n - i + 1,randi(rs,[1 3000]));
                    t.feed(tim(i:i+m-1));
                    i = i + m;
                end
        end
        assert(isequal(col(t.onsets()),ref), ...
            'Part A case %d, mode %d: the tracker found %d onsets, find_timing_onsets %d', ...
            c,mode,t.NumOnsets,numel(ref));
    end
    % One sample at a time, over the first stretch (every boundary there is).
    m3  = 12000;
    t   = mabr.metrics.OnsetTracker(sh,th,ra);
    for i = 1:m3, t.feed(tim(i)); end
    assert(isequal(col(t.onsets()),col(mabr.metrics.find_timing_onsets(tim(1:m3),sh,th,ra))), ...
        'Part A case %d: fed one sample at a time, the tracker differs',c);
    % ...and the double path too.
    t = mabr.metrics.OnsetTracker(sh,th,ra);
    t.feed(double(tim(1:30000))); t.feed(double(tim(30001:end)));
    assert(isequal(col(t.onsets()),col(mabr.metrics.find_timing_onsets(double(tim),sh,th,ra))), ...
        'Part A case %d: the double path differs',c);
end
fprintf('  PASS Part A: the onset tracker equals find_timing_onsets however the channel is sliced\n');

%% ---- Part B: the decimator is resample ---------------------------------
qs = unique(arrayfun(@mabr.Config.decimationFor,mabr.Config.SupportedSampleRates));
qs = unique([qs 1 df]);
for q = qs
    for L = [400 1001 4099 60005]
        x   = randn(rs,L,1);
        ref = resample(x,1,q);
        d   = mabr.compute.Decimator(q);
        y   = zeros(0,1);
        i   = 1;
        while i <= L
            m = min(L - i + 1,randi(rs,[1 max(2,round(L/7))]));
            y = [y; d.push(x(i:i+m-1))]; %#ok<AGROW>
            i = i + m;
        end
        y = [y; d.finish()]; %#ok<AGROW>
        assert(numel(y) == numel(ref), ...
            'Part B q=%d L=%d: %d outputs, resample gives %d',q,L,numel(y),numel(ref));
        e = max(abs(y - ref))/max(abs(ref));
        assert(e <= 1e-12,'Part B q=%d L=%d: differs from resample by %.3g (relative)',q,L,e);
    end
    R = mabr.compute.Decimator.selfCheck(q);
    assert(R.Length == R.Expected && R.MaxError <= 1e-12, ...
        'Part B q=%d: the self-check differs from resample (%.3g)',q,R.MaxError);
    fprintf('    q = %2d: %s\n',q,tern(R.Exact,'bit-identical to resample', ...
        sprintf('within %.2g of resample (not bit-identical on this release)',R.MaxError)));
end
fprintf('  PASS Part B: the decimator is resample(x,1,q) for q = %s\n',mat2str(qs));

%% ---- shared: a synthetic intermixed run --------------------------------
win  = [0 0.01];
filt = mabr.FilterPolicy;
arts = mabr.ArtifactPolicy('voltage',0.1,false);       % condition 3 is "bad"

%% ---- Part C: a run that fits, archived and not -------------------------
[sig,tim,on,seq] = synth_run(fs,2.0,0.019,3,rs);
info = struct('RunId',1,'StimIndex',seq,'Stimuli',1:3);

g0 = mabrtest.GrowingRing(sig,tim);
p0 = make(cfg,win,filt,arts,info,false);
S0 = replay(p0,g0,rs);
F0 = p0.finalize(g0,seq,on);

g1 = mabrtest.GrowingRing(sig,tim);
p1 = make(cfg,win,filt,arts,info,true);
S1 = replay(p1,g1,rs);
F1 = p1.finalize(g1,seq,on);

g2 = mabrtest.GrowingRing(sig,tim); g2.Head = g2.full();
p2 = make(cfg,win,filt,arts,info,true);       % never stepped: all read at close
F2 = p2.finalize(g2,seq,on);

assert(~F0.Archive.Used && F1.Archive.Used && F2.Archive.Used, ...
    'Part C: F.Archive.Used should say which path made each');
assert(F1.Archive.Complete && F2.Archive.Complete && F1.Archive.Samples == numel(sig), ...
    'Part C: the archives should be complete and hold every sample');
x1 = same_finalization(F1,F0,'Part C (stepped)');
x2 = same_finalization(F2,F0,'Part C (read at close)');
same_stats(S1,S0,'Part C');
sumC = p1.archiveSummary();
assert(~p1.archiving() && ~sumC.Used, ...
    'Part C: finalize should let the archive go');
fprintf('  PASS Part C: a run that fits finalizes the same archived or not (%d onsets, %d parts; %s)\n', ...
    F0.NumOnsets,numel(F0.Parts),tern(x1 && x2,'bit-identical','within single rounding'));

%% ---- Part D: seven times the ring --------------------------------------
ring = 2^18;                                   % 1.37 s at 192 kHz
[sig,tim,on,seq] = synth_run(fs,10.0,0.019,3,rs);
assert(numel(sig) > 7*ring,'Part D: the run should be several laps of the ring');
info = struct('RunId',2,'StimIndex',seq,'Stimuli',1:3,'Samples',numel(sig));

gR = mabrtest.GrowingRing(sig,tim);            % a ring long enough to hold it
pR = make(cfg,win,filt,arts,info,false);
SR = replay(pR,gR,rs);
FR = pR.finalize(gR,seq,on);

w  = mabrtest.WrappingRing(sig,tim,ring);
pW = make(cfg,win,filt,arts,info,true);
SW = [];
while w.Remaining > 0
    w.advance(randi(rs,[2000 20000]));         % 10-100 ms a step, as a 20 Hz tick reads it
    s = pW.step(w);
    if ~isempty(s), SW = s; end
end
assert(~pW.archiveLost(),'Part D: an archive read every step lost samples');
FW = pW.finalize(w,seq,on);
assert(FW.Archive.Used && FW.Archive.Complete && FW.Archive.Samples == numel(sig), ...
    'Part D: the archive should hold all %d samples',numel(sig));
xD = same_finalization(FW,FR,'Part D');
same_stats(SW,SR,'Part D');
assert(SW.NumSweeps == numel(on),'Part D: the live view saw %d of %d sweeps',SW.NumSweeps,numel(on));
fprintf(['  PASS Part D: a run of %.1f s through a %.2f s ring finalizes as if the ring held it ' ...
    '(%d onsets, %s); live statistics identical\n'], ...
    numel(sig)/fs,ring/fs,FW.NumOnsets,tern(xD,'bit-identical','within single rounding'));

%% ---- Part E: a lap the reader missed -----------------------------------
[sig,tim,on,seq] = synth_run(fs,6.0,0.019,1,rs);
info = struct('RunId',3,'StimIndex',seq,'Stimuli',1);
gR = mabrtest.GrowingRing(sig,tim); gR.Head = gR.full();
pR = make(cfg,win,filt,arts,info,false);
FR = pR.finalize(gR,seq,on);

w  = mabrtest.WrappingRing(sig,tim,ring);
pE = make(cfg,win,filt,arts,info,true);
while w.WriteHead < round(2.0*fs)
    w.advance(9600);
    pE.step(w);
end
h0 = w.WriteHead;                              % the archive has read this far
w.advance(round(1.5*ring));                    % ...and is kept from reading for 1.5 laps
pE.step(w);
assert(pE.archiveLost(),'Part E: a lap the reader never saw went unnoticed');
while w.Remaining > 0
    w.advance(9600);
    pE.step(w);
end
FE = pE.finalize(w,seq,on);
assert(FE.Archive.Used && ~FE.Archive.Complete && FE.Archive.LostAt == h0 + 1, ...
    'Part E: the archive should end at sample %d (it says %g)',h0+1,FE.Archive.LostAt);
before = FR.OnsetsAll(FR.OnsetsAll <= h0);
assert(isequal(FE.OnsetsAll,before), ...
    'Part E: the onsets before the loss should be the whole read''s (%d, got %d)', ...
    numel(before),numel(FE.OnsetsAll));
nE = FE.NumOnsets;
assert(nE == numel(before) && nE < FR.NumOnsets && isequal(FE.Seq,FR.Seq(1:nE)), ...
    'Part E: the presentations before the loss should be paired by order');
a = FE.Parts(1); b = FR.Parts(1);
assert(isequal(a.Onsets,b.Onsets(1:nE)),'Part E: the sweep onsets before the loss moved');
m = numel(a.Data);
assert(m <= ceil(h0/df) && m > ceil(h0/df) - 16, ...
    'Part E: the kept trace (%d samples) should end where the loss began (~%d)',m,ceil(h0/df));
eE = max(abs(double(a.Data) - double(b.Data(1:m))));
assert(eE <= 4*eps(single(max(abs(double(b.Data))))), ...
    'Part E: the kept trace is not the whole read''s (max diff %.3g)',eE);
fprintf(['  PASS Part E: 1.5 laps unread -- the archive ends at %.2f s, the %d presentations ' ...
    'before it kept exactly, the %d after it not attributed\n'], ...
    h0/fs,nE,FR.NumOnsets - nE);

%% ---- Part F: a wrapped block without an archive is refused --------------
pF = make(cfg,win,filt,arts,info,false);
w  = mabrtest.WrappingRing(sig,tim,ring);
w.advance(numel(sig));
try
    pF.finalize(w,seq,on);
    error('verify:run_archive:F','Part F: a wrapped block with no archive was finalized');
catch me
    assert(strcmp(me.identifier,'mabr:compute:Pipeline:notArchived'), ...
        'Part F: refused with %s, expected mabr:compute:Pipeline:notArchived',me.identifier);
end
fprintf('  PASS Part F: a wrapped block with no archive is refused, not read from its last lap\n');

%% ---- Part G: the schedule renders a run longer than the ring -----------
bank = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',[30 60]);
sch  = mabr.stim.Schedule(bank,cfg);
sch.Strategy    = 'interleaved';
sch.ISI         = 0.05;
sch.Repetitions = ceil(1.2*cfg.maxInputBufferLength/fs/sch.ISI/bank.numStimuli);
sch.build();
spec = sch.renderSpec(1);
assert(spec.Plan.N > cfg.maxInputBufferLength, ...
    'Part G: the run (%d samples) should be longer than the ring (%d)',spec.Plan.N,cfg.maxInputBufferLength);
y = spec.Plan.range(spec.Plan.N - 1023,spec.Plan.N);
assert(isequal(size(y),[1024 2]),'Part G: the end of a long run did not render');
sch.StimulationOnly = true;
spec2 = sch.renderSpec(1);
assert(spec2.Plan.N == spec.Plan.N,'Part G: stimulation only rendered a different run');
ctx = mabr.stim.strategy.context(sch);
assert(isinf(ctx.maxRunSamples),'Part G: a custom strategy should read no run-length limit');
fprintf('  PASS Part G: a %.1f min intermixed run renders (the ring holds %.1f min)\n', ...
    spec.Plan.N/fs/60,cfg.maxInputBufferLength/fs/60);

%% ---- Part H: the ring header counts past 2^32 --------------------------
d = tempname; mkdir(d);
cleanD = onCleanup(@() rmdir_quiet(d)); %#ok<NASGU>
c = struct('maxInputBufferLength',4096, ...
    'signalBufferFile',fullfile(d,'s.dat'),'timingBufferFile',fullfile(d,'t.dat'), ...
    'headerFile',fullfile(d,'h.dat'));
fid = fopen(c.headerFile,'wb'); fwrite(fid,[123 7],'uint32'); fclose(fid);   % an old 8-byte header
big = 2^33 + 5*4096;                          % 12.4 h at 192 kHz
rbW = mabr.acq.RingBuffer(c,true);
hd  = dir(c.headerFile);
assert(hd.bytes == 16,'Part H: an 8-byte header from an older MABR should be recreated (%d bytes)',hd.bytes);
clear rbW
fid = fopen(c.headerFile,'r+b'); fwrite(fid,big,'double'); fclose(fid);
rbW = mabr.acq.RingBuffer(c,true);
rbR = mabr.acq.RingBuffer(c,false);
frame = single((1:1024)');
rbW.writeFrame(frame,-frame);
assert(rbR.WriteHead == big + 1024,'Part H: the head read back as %.0f, not %.0f',rbR.WriteHead,big+1024);
assert(isequal(rbR.readSignal(big+1,big+1024),frame) && isequal(rbR.readTiming(big+1,big+1024),-frame), ...
    'Part H: samples written past 2^32 did not read back');
clear rbW rbR
fprintf('  PASS Part H: the write head counts past 2^32 samples; an old header is recreated\n');

fprintf('== verify_run_archive PASSED ==\n');
end


% =====================================================================
function [sig,tim,on,seq] = synth_run(fs,dur,isi,nStim,rs)
% A run of tone bursts, each on a 5 ms timing pulse -- some with a 24-sample
% microframe dropout inside it, which is part of the pulse, not a new onset.
N   = round(dur*fs);
on  = round((0.05:isi:dur-0.06)*fs);
seq = mod(0:numel(on)-1,nStim) + 1;
sig = 0.002*randn(rs,N,1);
tim = zeros(N,1);
amp = [0.02 0.05 0.3];
pw  = round(0.005*fs);
nb  = round(0.008*fs);
tb  = (0:nb)'/fs;
for k = 1:numel(on)
    i0 = on(k);
    tim(i0:i0+pw-1) = 1;
    if mod(k,7) == 3, tim(i0+300:i0+323) = 0; end
    sig(i0:i0+nb) = sig(i0:i0+nb) + amp(seq(k))*sin(2*pi*1000*tb);
end
end


function p = make(cfg,win,filt,arts,info,archive)
p = mabr.compute.Pipeline(cfg);
p.configure(win,filt,arts);
info.Archive = archive;
p.beginRun(info);
end


function S = replay(p,g,rs)
% Step a pipeline over a GrowingRing in 10-100 ms slices to the end.
S = [];
n = g.full();
g.Head = 0;
while g.Head < n
    g.Head = min(n,g.Head + randi(rs,[2000 20000]));
    s = p.step(g);
    if ~isempty(s), S = s; end
end
end


function exact = same_finalization(Fa,Fb,label)
% Fa is Fb: the same onsets, pairing and parts, the same flags and counts,
% and the same data -- bit for bit, or (a release whose upfirdn sums an
% output differently by where its input began) within single rounding.
for f = {'NumOnsets','Seq','OnsetsRaw','OnsetsAll','AmplifierGain'}
    assert(isequal(Fa.(f{1}),Fb.(f{1})),'%s: %s differs',label,f{1});
end
assert(isequal(Fa.Pairing,Fb.Pairing),'%s: the pairing differs',label);
assert(numel(Fa.Parts) == numel(Fb.Parts),'%s: %d parts, expected %d',label, ...
    numel(Fa.Parts),numel(Fb.Parts));
exact = true;
for i = 1:numel(Fb.Parts)
    a = Fa.Parts(i); b = Fb.Parts(i);
    for f = {'Stimulus','Onsets','SweepLength','Flags','Count'}
        assert(isequal(a.(f{1}),b.(f{1})),'%s: part %d differs in %s',label,i,f{1});
    end
    assert(isequal(size(a.Data),size(b.Data)) && isequal(size(a.Processed),size(b.Processed)), ...
        '%s: part %d''s traces are a different length',label,i);
    exact = exact && isequal(a.Data,b.Data) && isequal(a.Processed,b.Processed);
    top = max(abs(double(b.Data)));
    e   = max(abs(double(a.Data) - double(b.Data)));
    assert(e <= 4*eps(single(top)),'%s: part %d''s Data differs by %.3g',label,i,e);
    topP = max(abs(double(b.Processed)));
    eP   = max(abs(double(a.Processed) - double(b.Processed)));
    assert(eP <= 1e-5*topP,'%s: part %d''s Processed differs by %.3g',label,i,eP);
end
end


function same_stats(Sa,Sb,label)
assert(~isempty(Sa) && ~isempty(Sb),'%s: no live statistics',label);
for f = {'NumSweeps','NumClean','NumArtifacts','Stimuli','CondCounts','Mean','SD','Corr','Latest'}
    assert(isequaln(Sa.(f{1}),Sb.(f{1})),'%s: the live %s differs',label,f{1});
end
end


function v = col(x)
v = double(x(:));
end


function v = tern(c,a,b)
if c, v = a; else, v = b; end
end


function rmdir_quiet(d)
try, rmdir(d,'s'); end %#ok<TRYNC>
end
