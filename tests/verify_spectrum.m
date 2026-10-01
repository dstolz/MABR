function verify_spectrum()
% verify_spectrum  The input spectrum: the estimate, the window, the monitor.
%
%   mabr.ui.SpectrumViewer shows the power spectrum of the RAW input so that
%   electrical noise can be found and removed, and every number it shows is
%   a claim about volts at the electrodes. This checks those claims, then the
%   window, then the INPUT MONITOR that lets it be used with no schedule:
%
%     Part A  mabr.compute.SpectrumEstimator + mabr.metrics.noise_summary on
%             a synthetic input of known lines and known noise: the mains
%             fundamental and a harmonic, a line between bins, the noise
%             floor's density, total and in-band RMS, the largest non-mains
%             line, a DC offset kept out of it all, the amplifier gain, and
%             mains at 50 Hz finding the 60 Hz line as "other".
%     Part B  the incremental estimate is BIT-IDENTICAL to the one-shot one
%             over the same samples, however the input arrives, and
%             transforms each segment once; a new block starts it over.
%     Part C  the window, driven as a user drives it: the readouts, a
%             setting from a script (no pref written) against one from a
%             control (pref written), forgiving applySettings, freeze, the
%             reference, the Monitor button's failure and success, the CSV
%             export, and a display envelope that keeps every line.
%     Part D  the input monitor through a real Test Mode worker: silent laps
%             re-armed until stopped, the dither coming back flat, nothing
%             reaching ProgState, the Session or a listener; then a Start
%             straight after it, whose timing self-test must wait for its OWN
%             block (the engine already reads Completed from the monitor's
%             last lap) and whose run must not inherit a monitor sample.
%
%   Parts A-C need no pool and no hardware; Part D needs the Parallel
%   Computing Toolbox, as the engine tests do. The spectrum window's pref is
%   saved and put back.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_spectrum ==\n');
part_a();
part_b();
part_c();
part_d();
fprintf('== verify_spectrum PASSED ==\n');
end


% =====================================================================
function [x,fs,truth] = synthetic(T)
% Known content: 10 µV of 60 Hz, 2 µV of its third harmonic, 0.5 µV at
% 32 kHz, 1 µV RMS of white noise, and a 5 mV DC offset on top of it all.
fs = 192000;
rng(7);
t = (0:round(T*fs)-1)'/fs;
truth = struct('f60',10e-6,'f180',2e-6,'f32k',0.5e-6,'sigma',1e-6,'dc',5e-3);
x = sqrt(2)*truth.f60*sin(2*pi*60*t + 0.3) ...
  + sqrt(2)*truth.f180*sin(2*pi*180*t + 1.1) ...
  + sqrt(2)*truth.f32k*sin(2*pi*32000*t) ...
  + truth.sigma*randn(size(t)) + truth.dc;
end


% =====================================================================
function part_a()
fprintf('-- Part A: the estimate and the numbers read off it\n');
[x,fs,tr] = synthetic(6);
[f,P,info] = mabr.compute.SpectrumEstimator.welch(x,fs,1,8);
assert(info.Segments == 8,'expected 8 averages, got %d',info.Segments);
assert(abs(info.Resolution - 1) < 1e-12,'expected 1 Hz bins, got %g',info.Resolution);
assert(numel(f) == numel(P) && f(1) == 0,'f must start at DC and match P');

R = mabr.metrics.noise_summary(f,P,'LineFrequency',60,'Band',[100 3000]);
near(R.Line.Fundamental,tr.f60,0.03,'60 Hz line');
near(R.Line.RMS(3),tr.f180,0.03,'180 Hz harmonic');
assert(R.Line.RMS(2) < 0.05*tr.f180,'120 Hz holds no line, but read %g V',R.Line.RMS(2));
near(R.Line.Total,sqrt(sum(R.Line.RMS.^2)),1e-12,'harmonic total');
fprintf('   mains: 60 Hz %.3g µV, 180 Hz %.3g µV\n',1e6*R.Line.Fundamental,1e6*R.Line.RMS(3));

% The floor: white noise of variance s^2 over 0..fs/2 is s^2/(fs/2) V^2/Hz.
flat = f > 1000 & f < 20000 & abs(f - 32000) > 50;
near(mean(P(flat)),tr.sigma^2/(fs/2),0.03,'noise floor density');
% DC is removed before the transform, so 5 mV of offset is nowhere.
expTotal = sqrt(tr.sigma^2 + tr.f60^2 + tr.f180^2 + tr.f32k^2);
near(R.TotalRMS,expTotal,0.03,'total RMS (DC excluded)');
expBand = sqrt(tr.f180^2 + tr.sigma^2*(R.Band(2)-R.Band(1))/(fs/2));
near(R.BandRMS,expBand,0.05,'in-band RMS');
assert(P(1) < 1e-3*tr.dc^2,'the DC bin carries the offset (%g)',P(1));

% The largest line that is not mains: the 32 kHz one.
assert(abs(R.Peak.Frequency - 32000) <= 1,'largest other line at %g Hz, not 32 kHz', ...
    R.Peak.Frequency);
near(R.Peak.RMS,tr.f32k,0.05,'32 kHz line');
assert(R.Peak.AboveFloor > 10,'the 32 kHz line stands %g dB over the floor',R.Peak.AboveFloor);

% Mains at 50 Hz: 60 Hz is no longer mains, so it IS the largest other line.
R50 = mabr.metrics.noise_summary(f,P,'LineFrequency',50);
assert(abs(R50.Peak.Frequency - 60) <= 1,'with 50 Hz mains the 60 Hz line should be "other" (got %g)', ...
    R50.Peak.Frequency);
assert(R50.Line.Fundamental < 0.1*tr.f60,'no 50 Hz line, but read %g V',R50.Line.Fundamental);
R0 = mabr.metrics.noise_summary(f,P,'LineFrequency',0);
assert(isempty(R0.Line.RMS) && isnan(R0.Line.Fundamental),'mains off reports no line');

% A line between two bins is still measured whole.
t  = (0:6*fs-1)'/fs;
xo = sqrt(2)*10e-6*sin(2*pi*60.5*t) + 1e-7*randn(size(t));
[fo,Po] = mabr.compute.SpectrumEstimator.welch(xo,fs,1,8);
Ro = mabr.metrics.noise_summary(fo,Po,'LineFrequency',60);
near(Ro.Line.Fundamental,10e-6,0.03,'60.5 Hz line (half a bin off)');

% The amplifier gain divides the power by its square, exactly.
[~,Pg] = mabr.compute.SpectrumEstimator.welch(x,fs,1,8,1000);
assert(isequal(Pg,P/1000^2),'the gain must divide the PSD by gain^2 exactly');
fprintf('   PASS\n');
end


% =====================================================================
function part_b()
fprintf('-- Part B: incremental = one-shot, each segment transformed once\n');
[x,fs] = synthetic(5);
e = mabr.compute.SpectrumEstimator(fs,2,4);
L = e.SegmentLength; h = e.Hop;
want = e.samplesWanted() + h;       % what the window asks for
rng(11);
head = 0;
calls = 0;
while head < numel(x)
    head = min(numel(x),head + randi([1 h]));      % never more than a hop
    lo   = max(1,head - want + 1);
    [f,P,info] = e.update(x(lo:head),head,1,1);
    calls = calls + 1;
end
[f1,P1] = mabr.compute.SpectrumEstimator.welch(x(1:head),fs,2,4);
assert(isequal(f,f1),'frequency grids differ');
assert(isequal(P,P1),'incremental estimate differs from the one-shot (max rel %g)', ...
    max(abs(P-P1)./P1));
nSeg = floor((head - L)/h) + 1;
assert(e.FFTCount == nSeg,'%d segments transformed for %d on the grid -- some twice', ...
    e.FFTCount,nSeg);
assert(info.NewSegments <= 1,'the last slice should add at most one segment');
fprintf('   %d calls, %d segments, each transformed once; bit-identical\n',calls,e.FFTCount);

% Slices bigger than the average: still the newest segments, still identical.
e2 = mabr.compute.SpectrumEstimator(fs,2,4);
for head2 = [3*L, 3*L+7, 5*L, numel(x)]
    e2.update(x(max(1,head2-want+1):head2),head2,1,1);
end
[~,P2] = e2.update(x(max(1,head2-want+1):head2),head2,1,1);
assert(isequal(P2,P1),'large slices differ from the one-shot');

% A new block starts over; less than one segment is no estimate.
[~,P3,i3] = e2.update(x(1:L-1),L-1,2,1);
assert(isempty(P3) && i3.Segments == 0,'a new block short of one segment must give no estimate');
assert(isequal(e2.Seq,2) && isempty(e2.SegIndex),'the cache must belong to the new block');
fprintf('   PASS\n');
end


% =====================================================================
function part_c()
fprintf('-- Part C: the window\n');
g = mabr.ui.SpectrumViewer.PrefGroup;
k = mabr.ui.SpectrumViewer.PrefKey;
had = ispref(g,k);
if had, old = getpref(g,k); else, old = []; end
restorePref = onCleanup(@() putBack(g,k,had,old));
if had, rmpref(g,k); end

[x,fs] = synthetic(6);
state = struct('head',0,'seq',1,'gain',1,'monitoring',false,'monitorOK',false);

sv = mabr.ui.SpectrumViewer('SourceFcn',@source,'MonitorFcn',@monitor,'AutoRefresh',false);
closer = onCleanup(@() delete(sv));
assert(isempty(sv.Spectrum),'nothing recorded yet, but a spectrum is shown');
assert(contains(sv.Input.Note,'Monitor input'),'the empty window should say how to fill it');

state.head = 3*fs;
sv.refresh();
assert(~isempty(sv.Spectrum),'no spectrum from 3 s of input');
assert(sv.Spectrum.info.Segments == 4,'expected the default 4 averages, got %d', ...
    sv.Spectrum.info.Segments);
near(sv.Summary.Line.Fundamental,10e-6,0.05,'window: 60 Hz line');
% The largest-line search covers what is on the axis (10 kHz by default),
% where the only lines are mains; the 32 kHz one appears with the axis.
assert(isnan(sv.Summary.Peak.Frequency),'window: a line found below 10 kHz at %g Hz', ...
    sv.Summary.Peak.Frequency);
sv.MaxFrequency = Inf;
assert(abs(sv.Summary.Peak.Frequency - 32000) <= 1,'window: largest other line to Nyquist');
sv.MaxFrequency = 10000;
b60 = sv.Summary.Line.Fundamental;

% Referred to the electrodes: a gain of 1000 divides every voltage by it.
state.gain = 1000; state.seq = 2;
sv.refresh();
near(sv.Summary.Line.Fundamental,b60/1000,1e-9,'window: gain');
state.gain = 1;

% A setting from a script redraws, and writes no pref.
sv.Mains = 50;
assert(sv.Summary.Line.Frequency == 50,'Mains = 50 did not re-read the numbers');
assert(~ispref(g,k),'a property set by a script wrote the pref');
% ... one from a control is the user's choice, and is remembered.
d = findall(sv.Figure,'Tag','SpectrumAverages');
d.Value = 8;
d.ValueChangedFcn(d,[]);
assert(sv.Averages == 8,'the Averages control did not set Averages');
p = getpref(g,k);
assert(p.Averages == 8 && p.Mains == 50,'the control did not remember the look');

% Forgiving: what validates is taken, the rest is left.
sv.applySettings(struct('Resolution',3,'Averages',2,'Bogus',1,'Scale','asd'));
assert(sv.Resolution == 1 && sv.Averages == 2 && strcmp(sv.Scale,'asd'), ...
    'applySettings must take what validates and leave the rest');
assert(d.Value == 2,'a script''s setting must show in the controls');
sc = findall(sv.Figure,'Tag','SpectrumScale');
assert(strcmp(sc.Value,'asd'),'scale control out of step');

% Freeze holds the spectrum; unfreezing picks the input up again.
sv.setFrozen(true);
h0 = sv.Spectrum.info.Head;
state.head = 4*fs;
sv.refresh();
assert(sv.Spectrum.info.Head == h0,'a frozen window followed the input');
sv.setFrozen(false);
assert(sv.Spectrum.info.Head == 4*fs,'unfreezing did not pick the input up');

% The reference.
sv.holdReference('before');
assert(~isempty(sv.Reference) && strcmp(sv.Reference.Label,'before'),'no reference held');
sv.clearReference();
assert(isempty(sv.Reference),'the reference was not cleared');

% The Monitor button: a refusal puts it back and says why; a start shows.
bt = findall(sv.Figure,'Tag','SpectrumMonitor');
assert(strcmp(bt.Enable,'on'),'Monitor should be available with a MonitorFcn');
bt.Value = true;  bt.ValueChangedFcn(bt,[]);
assert(~bt.Value && contains(sv.Note,'refused for the test'),'a refused start must revert and say why');
state.monitorOK = true;
bt.Value = true;  bt.ValueChangedFcn(bt,[]);
assert(bt.Value && strcmp(bt.Text,'Stop monitor') && isempty(sv.Note), ...
    'a started monitor must show as running');
bt.Value = false; bt.ValueChangedFcn(bt,[]);
assert(~bt.Value && strcmp(bt.Text,'Monitor input'),'a stopped monitor must show as stopped');

% The display envelope: to Nyquist at 0.5 Hz is 192,000 bins; a few
% thousand are drawn, and the tallest bin is among them.
sv.Scale = 'db'; sv.Resolution = 0.5; sv.MaxFrequency = Inf;
state.head = 6*fs;
sv.refresh(true);
ln = findall(sv.Figure,'Type','line','Color',[0.10 0.25 0.55]);
assert(isscalar(ln),'expected one spectrum line');
assert(numel(ln.XData) <= 3002,'%d points drawn -- the envelope did not thin',numel(ln.XData));
Pv = sv.Spectrum.P(2:end);
assert(abs(max(ln.YData) - 10*log10(max(Pv)*1e12)) < 1e-9,'the tallest bin did not survive the envelope');

% Export.
csv = [tempname '.csv'];
rmCsv = onCleanup(@() delete(csv));
sv.exportCSV(csv);
T = readtable(csv);
assert(height(T) == numel(sv.Spectrum.f),'the CSV does not hold the spectrum');
clear rmCsv closer
fprintf('   PASS\n');

    function S = source(n)
        m = min(n,state.head);
        S = struct('Samples',single(x(state.head-m+1:state.head)),'Head',state.head, ...
            'Seq',state.seq,'SampleRate',fs,'Gain',state.gain,'Source','monitor', ...
            'Testing',false,'Monitoring',state.monitoring,'Note','');
        if state.head == 0, S.Source = 'none'; end
    end

    function [ok,msg] = monitor(tf)
        ok = state.monitorOK; msg = '';
        if ~ok, msg = 'refused for the test'; return; end
        state.monitoring = tf;
    end
end


% =====================================================================
function part_d()
fprintf('-- Part D: the input monitor, through a Test Mode worker\n');
cfg  = mabr.Config;
ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

S0 = ctrl.inputSamples(1e5);
assert(strcmp(S0.Source,'none') && isempty(S0.Samples), ...
    'before anything streams, the ring is an earlier session''s, not this rig''s input');

counts = struct('state',0,'ready',0,'monitor',0);
ls = [addlistener(ctrl,'StateChanged',@(~,~) bump('state')); ...
      addlistener(ctrl,'BlockReady',  @(~,~) bump('ready')); ...
      addlistener(ctrl,'MonitorChanged',@(~,~) bump('monitor'))];
rmLs = onCleanup(@() delete(ls));

ctrl.MonitorSeconds = 0.6;      % short laps, so re-arming is exercised
ctrl.startMonitor(struct());
assert(ctrl.Monitoring && counts.monitor == 1,'the monitor did not start');
assert(ctrl.State == mabr.ui.ProgState.Idle,'a monitor lap reached ProgState');
seq1 = waitForInput(ctrl,5);
wait_s(2.2);
% Read once the lap in progress holds enough: a read just after a lap
% boundary holds the few samples of the new one.
t0 = tic;
S = ctrl.inputSamples(round(0.5*cfg.DACSampleRate));
while numel(S.Samples) < 0.3*cfg.DACSampleRate && toc(t0) < 3
    pause(0.02);
    S = ctrl.inputSamples(round(0.5*cfg.DACSampleRate));
end
assert(strcmp(S.Source,'monitor') && S.Monitoring,'the source should be the monitor');
assert(S.Seq >= seq1 + 2,'laps were not re-armed (block %d, then %d)',seq1,S.Seq);
assert(numel(S.Samples) >= 0.3*cfg.DACSampleRate,'too little input: %d samples',numel(S.Samples));
% Test Mode copies the silent "stimulus" back with its 1e-6 dither.
near(std(double(S.Samples)),1e-6,0.1,'Test Mode monitor dither');
[f,P] = mabr.compute.SpectrumEstimator.welch(S.Samples,S.SampleRate,10,4);
near(mean(P(f > 100)),(1e-6)^2/(S.SampleRate/2),0.1,'flat dither floor');
R = mabr.metrics.noise_summary(f,P);
assert(isnan(R.Peak.Frequency),'silence has no line in it, but one was found at %g Hz', ...
    R.Peak.Frequency);
assert(counts.state == 0 && counts.ready == 0 && ctrl.Session.NumBlocks == 0, ...
    'monitor laps leaked into the run machinery (%d states, %d blocks)',counts.state,counts.ready);

t0 = tic;
ctrl.stopMonitor();
assert(~ctrl.Monitoring && counts.monitor == 2,'the monitor did not stop');
assert(toc(t0) < 3,'stopping took %.1f s',toc(t0));
assert(isempty(ctrl.MonitorError),'an asked-for stop is not an error');
S2 = ctrl.inputSamples(1000);
assert(strcmp(S2.Source,'held'),'after the monitor, the ring holds its last lap');
fprintf('   monitor: %d laps, dither %.3g V RMS, stopped in %.2f s\n', ...
    S.Seq-seq1+1,std(double(S.Samples)),toc(t0));

% Start with the monitor running: start() stops it, and the self-test waits
% for its own block rather than taking the stopped lap's Completed for it.
ctrl.startMonitor(struct());
waitForInput(ctrl,5);
ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'conventional';
ctrl.Schedule.Repetitions = 4;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.002;
ctrl.Session.OutputPath = '';
ctrl.start();
assert(~ctrl.Monitoring,'start() left the monitor running');
assert(ctrl.TimingVerified,'the timing self-test failed straight after the monitor');
% A schedule owns the device: the monitor is refused while it runs.
try
    ctrl.startMonitor(struct());
    error('verify_spectrum:noRefusal','the monitor started over a running schedule');
catch me
    assert(strcmp(me.identifier,'mabr:ui:AcqController:busy'), ...
        'wrong refusal: %s (%s)',me.identifier,me.message);
end
t1 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t1) < 30
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete,'the schedule did not complete');
assert(ctrl.Session.NumBlocks == 1 && ctrl.Session.Blocks(1).NumSweeps == 4, ...
    'expected one block of 4 sweeps -- a monitor lap leaked into the run');
S3 = ctrl.inputSamples(1000);
assert(strcmp(S3.Source,'held'),'after the schedule, the ring holds its last run');
clear rmLs cleaner
fprintf('   PASS\n');

    function bump(name)
        counts.(name) = counts.(name) + 1;
    end
end


% =====================================================================
function seq = waitForInput(ctrl,timeout)
t0 = tic;
S = ctrl.inputSamples(10);
while (isempty(S.Samples) || ~strcmp(S.Source,'monitor')) && toc(t0) < timeout
    pause(0.05);
    S = ctrl.inputSamples(10);
end
assert(~isempty(S.Samples),'no input arrived from the monitor within %g s',timeout);
seq = S.Seq;
end

function wait_s(T)
t0 = tic;
while toc(t0) < T, pause(0.05); end
end

function near(v,want,tol,what)
err = abs(v - want)/max(abs(want),realmin);
assert(err <= tol,'%s: got %.4g, expected %.4g (%.1f%% off, %.1f%% allowed)', ...
    what,v,want,100*err,100*tol);
end

function putBack(g,k,had,old)
if had
    setpref(g,k,old);
elseif ispref(g,k)
    rmpref(g,k);
end
end
