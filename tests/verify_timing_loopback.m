function results = verify_timing_loopback(opts)
% verify_timing_loopback  Measure and plot the integrity of the timing loop-back.
%
%   results = verify_timing_loopback(...) streams a train of timing pulses at a
%   chosen rate through the real Engine.prep/run path, recovers them from the
%   ring buffer with the SAME detector the acquisition pipeline uses
%   (mabr.metrics.find_timing_onsets), and reports how well they came back.
%
%   mabr.ui.AcqController.verifyTimingLoop only answers "did ANY pulse come
%   back" -- enough to catch an unplugged cable at Start, but blind to a
%   loop-back that is attenuated to the edge of the 0.1 detection threshold, a
%   device that drops frames, or DAC/ADC clocks that drift apart over a block.
%   Every sweep window in a session is cut relative to these onsets
%   (mabr.metrics.extract_sweeps), so a timing channel that is merely *mostly*
%   right smears every average built on it. This is the instrument for that:
%   run it on the rig with Testing=false whenever the wiring, the ASIO device,
%   or the buffer settings change.
%
%   Options (name-value):
%       PulseRate         (Hz)  pulses per second, default 40. This is the
%                               quantity to sweep -- a loop-back that is clean
%                               at 20 Hz can start dropping pulses at 500 Hz.
%       Duration          (s)   length of the pulse train, default 5
%       PulseWidth        (s)   pulse duration, default 8 samples
%       Testing        (logical) true (default) = hardware-free loopback, which
%                               is bit-exact and therefore the reference the
%                               real numbers are read against; false = open the
%                               real ASIO device
%       Device            (char) ASIO device name ('' = default)
%       PlayerChannels          [DACsignal DACtiming], default [1 2]
%       RecorderChannels        [ADCsignal ADCtiming], default [1 2]
%       Threshold               detection threshold, default 0.1 -- the value
%                               hard-coded throughout the pipeline, so this is
%                               the one the margins below are judged against
%       SignalTone        (Hz)  tone on the signal channel, default 1000
%                               (0 = silence). Present so bleed from the signal
%                               channel into the timing channel is measurable.
%       MaxJitter        (us)   onset jitter allowed before FAIL, default 50
%       Plot           (logical) draw the diagnostic figure, default true
%       Assert         (logical) throw on a failed criterion, default true
%       Corrupt         (struct) deliberately damage the pulse train before it
%                               is played, to check that the measurements below
%                               actually SEE a defect. A bit-exact loopback
%                               reports zero for everything, which is equally
%                               what a broken measurement reports. Fields (all
%                               optional): Gain (scales the timing channel),
%                               Noise (RMS of noise added to it), DriftPPM
%                               (stretches pulse spacing), Drop (pulse indices
%                               to omit). Corruption is injected into the play
%                               matrix, so it travels the whole engine path.
%
%   Returns a struct of every measured quantity (plus .Figure), so a rig can be
%   characterised across pulse rates in a loop:
%       for r = [20 40 100 250 500]
%           R(end+1) = verify_timing_loopback('PulseRate',r,'Testing',false, ...
%                                             'Plot',false,'Assert',false);
%       end
%
%   Requires the Parallel Computing Toolbox. Audio hardware only when
%   Testing=false.
%
%   See also mabr.metrics.find_timing_onsets, mabr.metrics.extract_sweeps,
%   mabr.ui.AcqController/verifyTimingLoop, verify_timing_selftest.
%
% Daniel Stolzberg (c) 2026

arguments
    opts.PulseRate        (1,1) double  {mustBePositive} = 40
    opts.Duration         (1,1) double  {mustBePositive} = 5
    opts.PulseWidth       (1,1) double  {mustBeNonnegative} = 0
    opts.Testing          (1,1) logical = true
    opts.Device           (1,:) char    = ''
    opts.PlayerChannels   (1,2) double  = [1 2]
    opts.RecorderChannels (1,2) double  = [1 2]
    opts.Threshold        (1,1) double  {mustBePositive} = 0.1
    opts.SignalTone       (1,1) double  {mustBeNonnegative} = 1000
    opts.MaxJitter        (1,1) double  {mustBePositive} = 50
    opts.Plot             (1,1) logical = true
    opts.Assert           (1,1) logical = true
    opts.Corrupt          (1,1) struct  = struct()
end

fprintf('== verify_timing_loopback ==\n');

cfg = mabr.Config;
Fs  = cfg.DACSampleRate;
fl  = cfg.frameLength;

% ---- Build the pulse train ------------------------------------------------
period = round(Fs/opts.PulseRate);
if opts.PulseWidth > 0
    pulseLen = max(1,round(opts.PulseWidth*Fs));
else
    pulseLen = 8;                            % as mabr.ui.AcqController
end
assert(period >= 4*pulseLen,'mabr:test:timing:rateTooHigh', ...
    ['A %g Hz rate is %d samples apart but the pulse is %d samples wide; ' ...
     'pulses would run together. Shorten PulseWidth or lower PulseRate.'], ...
    opts.PulseRate,period,pulseLen);

nPulses = floor(opts.Duration*opts.PulseRate);
assert(nPulses >= 8,'mabr:test:timing:tooFewPulses', ...
    'Duration %g s at %g Hz yields only %d pulses; need at least 8 for statistics.', ...
    opts.Duration,opts.PulseRate,nPulses);

% Injected defects, if any. expIdx stays the NOMINAL grid -- it is the ruler
% every measurement below is read against -- while playIdx is where the pulses
% actually go, so a drift or a drop shows up as a discrepancy between them.
cGain  = getdef_(opts.Corrupt,'Gain',1);
cNoise = getdef_(opts.Corrupt,'Noise',0);
cDrift = getdef_(opts.Corrupt,'DriftPPM',0);
cDrop  = getdef_(opts.Corrupt,'Drop',[]);
corrupted = cGain ~= 1 || cNoise ~= 0 || cDrift ~= 0 || ~isempty(cDrop);

lead    = round(0.05*Fs);                     % device settling before pulse 1
tail    = max(round(0.05*Fs),period);         % room after the last pulse
expIdx  = lead + (0:nPulses-1)'*period + 1;   % commanded onset sample indices
playIdx = lead + round((0:nPulses-1)'*period*(1 + cDrift/1e6)) + 1;
keep    = true(nPulses,1);
keep(cDrop(cDrop >= 1 & cDrop <= nPulses)) = false;
N       = ceil((max(playIdx) + pulseLen + tail)/fl)*fl;

assert(N <= cfg.maxInputBufferLength,'mabr:test:timing:tooLong', ...
    'Run needs %d samples but the ring buffer holds %d (%.1f s). Shorten Duration.', ...
    N,cfg.maxInputBufferLength,cfg.maxInputBufferLength/Fs);

timing = zeros(N,1,'single');
for k = 1:nPulses
    if ~keep(k), continue; end
    timing(playIdx(k):playIdx(k)+pulseLen-1) = cGain;
end
if cNoise > 0
    timing = timing + single(cNoise*randn(N,1));
end

if opts.SignalTone > 0
    t      = (0:N-1)'/Fs;
    signal = single(0.2*sin(2*pi*opts.SignalTone*t));
else
    signal = zeros(N,1,'single');
end

fprintf('  %g Hz x %.1f s = %d pulses, %d samples apart, %d samples wide (%.1f us) @ %g Hz\n', ...
    opts.PulseRate,opts.Duration,nPulses,period,pulseLen,1e6*pulseLen/Fs,Fs);
if corrupted
    fprintf('  INJECTED DEFECTS: gain %g, noise %g RMS, drift %g ppm, %d pulses dropped\n', ...
        cGain,cNoise,cDrift,nnz(~keep));
end
if opts.Testing
    fprintf('  mode: TESTING loopback (no hardware) -- reference case, expect exact recovery\n');
else
    dev = opts.Device; if isempty(dev), dev = '<default ASIO device>'; end
    fprintf('  mode: HARDWARE, device %s, player [%d %d], recorder [%d %d]\n', ...
        dev,opts.PlayerChannels,opts.RecorderChannels);
end

% ---- Stream it through the real engine path -------------------------------
eng = mabr.acq.Engine(cfg,opts.Testing);
cleaner = onCleanup(@() delete(eng));
assert(eng.waitUntilReady(60),'Acquisition worker never became ready');

spec = struct('PlayMatrix',[signal timing],'SampleRate',Fs, ...
    'PlayerChannels',opts.PlayerChannels,'RecorderChannels',opts.RecorderChannels);
if ~isempty(opts.Device), spec.Device = opts.Device; end

eng.prep(spec);
wait_until(@() eng.State == mabr.acq.State.Ready || eng.State == mabr.acq.State.Error, 20);
assert(eng.State ~= mabr.acq.State.Error,'mabr:test:timing:prepFailed', ...
    'Worker errored during prep -- see the log above (device unavailable?).');

eng.run();
timeout = max(60,4*N/Fs);
wait_until(@() eng.State == mabr.acq.State.Completed || eng.State == mabr.acq.State.Error, timeout);
assert(eng.State == mabr.acq.State.Completed,'mabr:test:timing:blockFailed', ...
    'Block did not complete within %g s (state = %s).',timeout,string(eng.State));

head = eng.head();
assert(head > 0,'mabr:test:timing:noSamples','No samples reached the ring buffer.');
assert(head <= eng.RingBuffer.MaxLength, ...
    'Block wrapped the ring buffer; recorded indices no longer align with played ones.');
recSig = double(eng.RingBuffer.readSignal(1,head));
recTim = double(eng.RingBuffer.readTiming(1,head));
fprintf('  streamed %d of %d samples (%.3f s)\n',head,N,head/Fs);

% ---- Detect, using exactly what the pipeline uses --------------------------
% extract_sweeps' 2 ms default shadow would merge pulses above 250 Hz, so the
% shadow tracks the commanded period instead: wide enough to reject a ringing
% edge, never wide enough to swallow the next pulse.
shadow = max(1,round(0.4*period));
det    = mabr.metrics.find_timing_onsets(recTim,shadow,opts.Threshold);

% ---- Match detections to commanded onsets ---------------------------------
% Matched by proximity rather than by ordinal position: with a dropped pulse in
% the middle, index-wise pairing mislabels every pulse after it as late.
tol     = period/2;
matched = nan(nPulses,1);
claimed = false(numel(det),1);
for k = 1:nPulses
    avail = find(~claimed);
    if isempty(avail), break; end
    [d,jj] = min(abs(det(avail) - expIdx(k)));
    if d <= tol
        matched(k)      = det(avail(jj));
        claimed(avail(jj)) = true;
    end
end
ok      = ~isnan(matched);
nFound  = nnz(ok);
nMissed = nPulses - nFound;
nExtra  = nnz(~claimed);        % detections matching no commanded pulse

% ---- Latency, drift, jitter ------------------------------------------------
err = matched(ok) - expIdx(ok);          % samples, recorded minus commanded
kk  = find(ok);
latencySamp = median(err);
if nFound >= 3
    p         = polyfit(kk,err,1);
    driftPPM  = 1e6*p(1)/period;         % clock mismatch DAC vs ADC
    resid     = err - polyval(p,kk);
else
    p = [0 latencySamp]; driftPPM = NaN; resid = err - latencySamp;
end
jitterRMS = std(resid);                  % samples
if isempty(resid), jitterPP = NaN; else, jitterPP = max(resid) - min(resid); end
us        = @(n) 1e6*n/Fs;

% ---- Inter-pulse intervals -------------------------------------------------
ipi     = diff(det)/Fs;                  % s
nominal = period/Fs;
if isempty(ipi)
    ipiStats = struct('mean',NaN,'std',NaN,'min',NaN,'max',NaN);
    nDropGaps = 0;
else
    ipiStats  = struct('mean',mean(ipi),'std',std(ipi),'min',min(ipi),'max',max(ipi));
    ratio     = ipi/nominal;
    nDropGaps = nnz(round(ratio) > 1 & abs(ratio - round(ratio)) < 0.1);
end

% ---- Pulse shape, amplitude, and baseline ----------------------------------
% A pulse that arrives smeared and shrunken still detects -- until the day it
% doesn't. Peak height relative to Threshold is the margin that matters.
% Two windows, because they answer different questions. The shape window is a
% tight zoom (>= 1 ms, or 16x the commanded width) so a smeared or ringing
% pulse is legible; the mask window is deliberately generous so that same
% ringing tail is kept OUT of the baseline estimate below.
win     = 0:min(period-1,max(16*pulseLen,round(0.001*Fs)));
maskWin = min(period-1,round(0.25*period));
onsAll  = matched(ok);
segs    = zeros(numel(onsAll),numel(win));
peaks   = zeros(numel(onsAll),1);
widths  = zeros(numel(onsAll),1);
for k = 1:numel(onsAll)
    idx = onsAll(k) + win;
    idx = idx(idx >= 1 & idx <= numel(recTim));
    s   = recTim(idx(:));
    segs(k,1:numel(s)) = s;
    peaks(k)  = max(s);
    above     = s >= opts.Threshold;
    widths(k) = find([above(:); false] == 0,1,'first') - 1;   % run length from onset
end
if isempty(peaks), peaks = 0; widths = 0; end

pulseMask = false(size(recTim));
for k = 1:numel(onsAll)
    lo = max(1,onsAll(k) - shadow);
    hi = min(numel(recTim),onsAll(k) + maskWin);
    pulseMask(lo:hi) = true;
end
if ~isempty(onsAll)
    span = (onsAll(1):onsAll(end))';
    base = recTim(span(~pulseMask(span)));
else
    base = recTim;
end
if isempty(base), base = 0; end
baseMax = max(abs(base));
baseRMS = rms_(base);

% ---- Threshold robustness sweep --------------------------------------------
% The width of the plateau over which the count stays right is the honest
% measure of headroom: a knife-edge plateau means the next slightly noisier
% electrode or slightly quieter DAC breaks detection.
refPeak = median(peaks);
% Sweep against the largest thing actually on the channel, not against the
% detected pulse height. When nothing is detected at all -- the attenuated
% loop-back case -- the pulse height is 0 and a sweep scaled to it would say
% nothing; scaled to the channel maximum, the sweep shows the threshold at
% which the pulses WOULD have come back, which names the fault.
sweepTop = max(abs(recTim));
if isempty(sweepTop) || ~isfinite(sweepTop) || sweepTop <= 0, sweepTop = 1; end
thrSweep = linspace(0.02,1.05,60)'*sweepTop;
counts   = arrayfun(@(th) numel(mabr.metrics.find_timing_onsets(recTim,shadow,th)),thrSweep);
good     = counts == nPulses;
if any(good)
    plateau = [min(thrSweep(good)) max(thrSweep(good))];
else
    plateau = [NaN NaN];
end

% ---- Signal channel (is channel 1 alive, and does it bleed?) ---------------
sigRMS = rms_(recSig);
if opts.SignalTone > 0 && numel(recSig) > 16
    n2   = 2^floor(log2(numel(recSig)));
    P    = abs(fft(recSig(1:n2).*hann_(n2)));
    P    = P(1:floor(n2/2));
    [~,b] = max(P);
    sigPeakHz = (b-1)*Fs/n2;
else
    sigPeakHz = NaN;
end

% ---- Report -----------------------------------------------------------------
fprintf('\n  -- pulse recovery ------------------------------------------------\n');
fprintf('    detected / commanded : %d / %d   (missed %d, spurious %d)\n', ...
    nFound,nPulses,nMissed,nExtra);
fprintf('    dropped-pulse gaps   : %d  (IPIs at an integer multiple of nominal)\n',nDropGaps);
fprintf('  -- onset timing --------------------------------------------------\n');
fprintf('    loop-back latency    : %.1f us (%g samples)\n',us(latencySamp),latencySamp);
fprintf('    jitter (RMS / p-p)   : %.2f us / %.2f us\n',us(jitterRMS),us(jitterPP));
fprintf('    clock drift          : %.2f ppm over the block\n',driftPPM);
fprintf('  -- inter-pulse interval ------------------------------------------\n');
fprintf('    nominal              : %.4f ms (%g Hz)\n',1e3*nominal,opts.PulseRate);
fprintf('    mean +/- sd          : %.4f +/- %.4f ms\n',1e3*ipiStats.mean,1e3*ipiStats.std);
fprintf('    min / max            : %.4f / %.4f ms\n',1e3*ipiStats.min,1e3*ipiStats.max);
fprintf('  -- amplitude margin (detector threshold = %.3f) ------------------\n',opts.Threshold);
fprintf('    pulse peak min/med   : %.4f / %.4f  -> worst margin %.1fx threshold\n', ...
    min(peaks),refPeak,min(peaks)/opts.Threshold);
fprintf('    pulse width med      : %.1f us commanded, %.1f us returned\n', ...
    us(pulseLen),us(median(widths)));
fprintf('    baseline max / RMS   : %.5f / %.5f  (headroom %.4f)\n', ...
    baseMax,baseRMS,min(peaks)-baseMax);
if any(good)
    fprintf('    threshold plateau    : %.3f to %.3f  (%.0f%% to %.0f%% of channel max %.4f)\n', ...
        plateau(1),plateau(2),100*plateau(1)/sweepTop,100*plateau(2)/sweepTop,sweepTop);
else
    fprintf(['    threshold plateau    : none -- no threshold recovers all %d pulses ' ...
             '(best %d, at %.4f)\n'],nPulses,max(counts),thrSweep(find(counts == max(counts),1)));
end
fprintf('  -- signal channel ------------------------------------------------\n');
fprintf('    recovered RMS        : %.4f, dominant %.0f Hz (played %g Hz)\n', ...
    sigRMS,sigPeakHz,opts.SignalTone);
if baseRMS > 0 && refPeak > 0
    fprintf('    bleed into timing    : %.1f dB below pulse peak\n',20*log10(refPeak/baseRMS));
elseif baseRMS > 0
    fprintf('    bleed into timing    : %.5f RMS (no pulse recovered to compare against)\n',baseRMS);
else
    fprintf('    bleed into timing    : none measurable (baseline is exactly zero)\n');
end
if corrupted
    fprintf('  -- injected vs recovered (does the instrument see the defect?) ---\n');
    fprintf('    dropped pulses       : injected %d, reported missed %d\n',nnz(~keep),nMissed);
    fprintf('    drift                : injected %g ppm, reported %.2f ppm\n',cDrift,driftPPM);
    fprintf('    pulse gain           : injected %g, median peak %.4f\n',cGain,refPeak);
    fprintf('    noise                : injected %g RMS, baseline %.5f RMS, %d spurious\n', ...
        cNoise,baseRMS,nExtra);
end
fprintf('\n');

results = struct( ...
    'PulseRate',opts.PulseRate,'Duration',opts.Duration,'SampleRate',Fs, ...
    'Testing',opts.Testing,'Threshold',opts.Threshold,'Corrupted',corrupted, ...
    'NumCommanded',nPulses,'NumDetected',nFound,'NumMissed',nMissed, ...
    'NumSpurious',nExtra,'NumDropGaps',nDropGaps, ...
    'LatencySamples',latencySamp,'LatencyUS',us(latencySamp), ...
    'JitterRMS_US',us(jitterRMS),'JitterPP_US',us(jitterPP),'DriftPPM',driftPPM, ...
    'IPI',ipiStats,'NominalIPI',nominal, ...
    'PulsePeaks',peaks,'PulseWidths',widths,'MinMargin',min(peaks)/opts.Threshold, ...
    'BaselineMax',baseMax,'BaselineRMS',baseRMS, ...
    'ThresholdPlateau',plateau,'ThresholdSweep',thrSweep,'SweepCounts',counts, ...
    'SignalRMS',sigRMS,'SignalPeakHz',sigPeakHz, ...
    'CommandedOnsets',expIdx,'DetectedOnsets',det,'OnsetError',err, ...
    'Figure',gobjects(1));

% ---- Plot -------------------------------------------------------------------
if opts.Plot
    results.Figure = draw_report(recTim,det,expIdx,segs,win,ipi,nominal,kk,err,p, ...
        thrSweep,counts,nPulses,Fs,opts,sweepTop);
end

% ---- Verdict ----------------------------------------------------------------
if opts.Assert
    assert(nMissed == 0,'mabr:test:timing:missedPulses', ...
        ['%d of %d timing pulses did not come back. Sweep windows are cut ' ...
         'relative to these onsets, so every missed pulse is a lost sweep.'], ...
        nMissed,nPulses);
    assert(nExtra == 0,'mabr:test:timing:spuriousPulses', ...
        ['%d spurious onsets detected. Ringing or noise on the timing channel ' ...
         'is crossing threshold and will fabricate sweeps.'],nExtra);
    assert(min(peaks) > opts.Threshold,'mabr:test:timing:noMargin', ...
        'Weakest pulse peaked at %.4f, at or below the %.3f detection threshold.', ...
        min(peaks),opts.Threshold);
    assert(us(jitterRMS) <= opts.MaxJitter,'mabr:test:timing:jitter', ...
        'Onset jitter %.2f us RMS exceeds the %.1f us tolerance.', ...
        us(jitterRMS),opts.MaxJitter);
    if opts.Testing && ~corrupted
        % The loopback branch of worker_loop passes the timing column through
        % untouched, so anything but bit-exact recovery is a bug in the
        % engine or the detector, not in a cable.
        assert(latencySamp == 0 && jitterRMS == 0, ...
            'mabr:test:timing:loopbackNotExact', ...
            ['TESTING loopback should recover onsets exactly (latency %g ' ...
             'samples, jitter %g samples).'],latencySamp,jitterRMS);
    end
    fprintf('== verify_timing_loopback PASSED ==\n');
else
    fprintf('== verify_timing_loopback complete (assertions disabled) ==\n');
end
end


% =====================================================================
function wait_until(pred,timeout)
% Pause (letting DataQueue callbacks run) until pred() is true or timeout.
t0 = tic;
while ~pred() && toc(t0) < timeout
    pause(0.02);
end
end


% =====================================================================
function fig = draw_report(recTim,det,expIdx,segs,win,ipi,nominal,kk,err,p, ...
    thrSweep,counts,nPulses,Fs,opts,sweepTop)

fig = figure('Name',sprintf('Timing loop-back @ %g Hz',opts.PulseRate), ...
    'Color','w','Position',[80 80 1180 780]);
tl = tiledlayout(fig,3,2,'TileSpacing','compact','Padding','compact');
if opts.Testing, mode = 'TESTING loopback'; else, mode = 'hardware'; end
title(tl,sprintf('Timing loop-back: %g Hz, %d pulses, %s (Fs = %g kHz)', ...
    opts.PulseRate,nPulses,mode,Fs/1e3),'FontWeight','bold');

us = @(n) 1e6*n/Fs;

% --- 1. whole recovered trace ------------------------------------------
% Pulses are a handful of samples wide, so plain decimation would step over
% them; a max envelope keeps every pulse visible at any zoom-out.
ax = nexttile(tl,1);
[te,ye] = envelope_(recTim,Fs,4000);
plot(ax,te,ye,'Color',[0.25 0.45 0.75]); hold(ax,'on');
yline(ax,opts.Threshold,'r--','threshold','LabelHorizontalAlignment','left');
plot(ax,det/Fs,repmat(opts.Threshold,size(det)),'v','Color',[0.85 0.33 0.1], ...
    'MarkerFaceColor',[0.85 0.33 0.1],'MarkerSize',4);
hold(ax,'off'); grid(ax,'on'); axis(ax,'tight');
xlabel(ax,'time (s)'); ylabel(ax,'timing ch.');
title(ax,sprintf('Recovered timing channel (envelope) — %d onsets detected',numel(det)));

% --- 2. zoom on the first few pulses ------------------------------------
ax = nexttile(tl,2);
nz  = min(5,nPulses);
per = expIdx(2)-expIdx(1);
lo  = max(1,expIdx(1) - round(0.25*per));
hi  = min(numel(recTim),expIdx(min(nz,numel(expIdx))) + round(0.5*per));
idx = (lo:max(lo,hi))';
plot(ax,1e3*idx/Fs,recTim(idx),'-','Color',[0.25 0.45 0.75],'LineWidth',1); hold(ax,'on');
% One xline per commanded onset: vector-valued xline is not available on the
% R2021b floor this toolbox targets (mabr.Config.RequiredToolboxes).
ec = expIdx(expIdx>=lo & expIdx<=hi);
for j = 1:numel(ec), xline(ax,1e3*ec(j)/Fs,':','Color',[0.5 0.5 0.5]); end
d = det(det>=lo & det<=hi);
plot(ax,1e3*d/Fs,recTim(d),'o','Color',[0.85 0.33 0.1],'MarkerFaceColor','w','LineWidth',1.2);
yline(ax,opts.Threshold,'r--');
hold(ax,'off'); grid(ax,'on'); axis(ax,'tight');
xlabel(ax,'time (ms)'); ylabel(ax,'timing ch.');
title(ax,sprintf('First %d pulses (dotted = commanded, circle = detected)',nz));

% --- 3. inter-pulse interval histogram ----------------------------------
ax = nexttile(tl,3);
if isempty(ipi)
    text(ax,0.5,0.5,'no intervals','Units','normalized','HorizontalAlignment','center');
else
    % A perfect train is one bin wide, which auto-binning stretches to fill the
    % axes and reads as "spread everywhere" -- exactly backwards. Pin a narrow
    % bin and a +/-0.1% view so zero jitter looks like zero jitter.
    if max(ipi) - min(ipi) < 1e-9
        histogram(ax,1e3*ipi,'BinWidth',max(1e-6,1e3*nominal*2e-4), ...
            'FaceColor',[0.25 0.45 0.75],'EdgeColor','none');
        xlim(ax,1e3*nominal*[0.999 1.001]);
    else
        histogram(ax,1e3*ipi,'FaceColor',[0.25 0.45 0.75],'EdgeColor','none');
    end
    hold(ax,'on'); xline(ax,1e3*nominal,'r--','LineWidth',1.2); hold(ax,'off');
end
grid(ax,'on');
xlabel(ax,'inter-pulse interval (ms)'); ylabel(ax,'count');
title(ax,sprintf('IPI: %.4f \\pm %.4f ms (nominal %.4f)', ...
    1e3*mean(ipi),1e3*std(ipi),1e3*nominal));

% --- 4. onset error: latency, drift, jitter ------------------------------
ax = nexttile(tl,4);
plot(ax,kk,us(err),'.','Color',[0.25 0.45 0.75],'MarkerSize',8); hold(ax,'on');
plot(ax,kk,us(polyval(p,kk)),'-','Color',[0.85 0.33 0.1],'LineWidth',1.2);
hold(ax,'off'); grid(ax,'on');
if isempty(err) || max(err) - min(err) < 1e-9
    ylim(ax,us(median([err;0])) + [-1 1]);
end
xlabel(ax,'pulse #'); ylabel(ax,'detected - commanded (\mus)');
title(ax,sprintf('Onset error: latency %.1f \\mus, drift %.2f ppm', ...
    us(median(err)),1e6*p(1)/(nominal*Fs)));

% --- 5. overlaid pulse shapes -------------------------------------------
ax = nexttile(tl,5);
tw = us(win);
if isempty(segs)
    text(ax,0.5,0.5,'no pulses recovered','Units','normalized', ...
        'HorizontalAlignment','center','Color',[0.6 0.2 0.2]);
    title(ax,'Pulse shape');
else
    plot(ax,tw,segs.','-','Color',[0.62 0.72 0.85]); hold(ax,'on');
    plot(ax,tw,median(segs,1),'k-','LineWidth',1.5);
    yline(ax,opts.Threshold,'r--');
    hold(ax,'off'); axis(ax,'tight');
    title(ax,sprintf('All %d pulses overlaid (black = median)',size(segs,1)));
end
grid(ax,'on');
xlabel(ax,'time from onset (\mus)'); ylabel(ax,'timing ch.');

% --- 6. threshold robustness --------------------------------------------
ax = nexttile(tl,6);
good = counts == nPulses;
ymax = max(1,max(counts))*1.15;
if any(good)
    lo = min(thrSweep(good)); hi = max(thrSweep(good));
    patch(ax,[lo hi hi lo],[0 0 1 1]*ymax,[0.85 0.93 0.85],'EdgeColor','none');
    hold(ax,'on');
end
plot(ax,thrSweep,counts,'-','Color',[0.25 0.45 0.75],'LineWidth',1.2); hold(ax,'on');
yline(ax,nPulses,'k:','commanded');
xline(ax,opts.Threshold,'r--','in use','LabelVerticalAlignment','bottom');
hold(ax,'off'); grid(ax,'on');
xlim(ax,[min(thrSweep) max(thrSweep)]); ylim(ax,[0 ymax]);
xlabel(ax,'detection threshold'); ylabel(ax,'onsets detected');
if any(good)
    title(ax,sprintf('All %d recovered for %.0f-%.0f%% of channel max (%.3f)', ...
        nPulses,100*lo/sweepTop,100*hi/sweepTop,sweepTop));
else
    title(ax,sprintf('No threshold recovers all %d (best %d)',nPulses,max(counts)));
end
end


% =====================================================================
function [te,ye] = envelope_(y,Fs,nOut)
% Max-magnitude envelope over ~nOut chunks, so short pulses survive
% downsampling for display.
n = numel(y);
if n <= nOut, te = (1:n)'/Fs; ye = y(:); return; end
c = ceil(n/nOut);
y = [y(:); zeros(c*ceil(n/c)-n,1)];
M = reshape(y,c,[]);
[~,i] = max(abs(M),[],1);
ye = M(sub2ind(size(M),i,1:size(M,2))).';
te = ((0:size(M,2)-1)*c + c/2).'/Fs;
end


% =====================================================================
function v = getdef_(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end


% =====================================================================
function v = rms_(x)
x = x(:);
if isempty(x), v = 0; else, v = sqrt(mean(x.^2)); end
end


% =====================================================================
function w = hann_(n)
% Local Hann so this script does not depend on which toolbox owns hann().
w = 0.5 - 0.5*cos(2*pi*(0:n-1)'/(n-1));
end
