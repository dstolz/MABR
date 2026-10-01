function verify_input_calibration()
% verify_input_calibration  Confirm the recorder input can be calibrated in volts.
%
%   The interface's input gain knob decides how many converter units a volt
%   is; mabr.acq.InputCalibrator measures it through a loop-back cable against
%   an output read once off a multimeter (see that class for the arithmetic).
%
%   Part A (tone_level): the fit recovers a tone's amplitude through noise,
%   mains hum and an offset; flags a clipped record; and finds no tone in
%   noise alone.
%   Part B (measureInput): over mabrtest.FakeAudioDevice standing as a
%   loop-back cable with a known gain, the calibrator lands the tone near its
%   target at the input and reports the full scale that gain implies; with a
%   gain so high the first probes clip, it steps down until they do not
%   rather than quoting a clipped number; with no cable, it says so.
%   Part C (refusals): no measurement in Test Mode, under stimulation only,
%   while the controller is busy, or against an output never measured; and
%   the meter tone stops when asked.
%
%   No hardware, no parallel pool, no prefs touched. Run:
%   >> verify_input_calibration
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_input_calibration ==\n');

% ---- Part A: tone_level ----------------------------------------------------
fs = 192000; f0 = 400;
rs = RandStream('mt19937ar','Seed',7);
t  = (0:round(0.5*fs)-1)'/fs;       % 200 whole cycles of 400 Hz
x  = 0.3*sin(2*pi*f0*t + 0.7) + 0.05*sin(2*pi*60*t) + 0.02*sin(2*pi*180*t) ...
     + 1e-3*randn(rs,numel(t),1) + 0.01;
r  = mabr.metrics.tone_level(x,fs,f0);
assert(abs(r.Amplitude - 0.3) < 1e-4, ...
    'tone_level: amplitude %.6f, expected 0.3 (hum and noise must not bias it)',r.Amplitude);
assert(abs(r.RMS - 0.3/sqrt(2)) < 1e-4,'tone_level: RMS should be the peak over sqrt(2)');
assert(r.Present && ~r.Clipped,'tone_level: a tone under heavy hum should still be found, unclipped');
% SNR is broadband -- the hum counts against it -- while detection is not.
snr0 = 10*log10((0.3^2/2)/(0.05^2/2 + 0.02^2/2 + 1e-6));
assert(abs(r.SNR - snr0) < 0.2,'tone_level: SNR %.2f dB, expected %.2f dB',r.SNR,snr0);

xc = min(max(1.5*sin(2*pi*f0*t),-1),1);
assert(mabr.metrics.tone_level(xc,fs,f0).Clipped,'tone_level: a record at full scale must be flagged clipped');
rn = mabr.metrics.tone_level(1e-3*randn(rs,numel(t),1),fs,f0);
assert(~rn.Present,'tone_level: noise alone must not read as a tone (SNR %.1f dB)',rn.SNR);
fprintf('  PASS Part A: tone_level fits through hum and noise, flags clipping and absence\n');

% ---- Part B: measureInput over a loop-back with a known gain ----------------
a = mabr.AudioSettings;
a.Testing = false;
a.OutputFullScale = 3;              % 1.0 out = 3 V peak (the "meter" said so)

% B1: a gain of 2 converter units in per unit out -> 1.0 in = 1.5 V.
cal = makeCal(a,2);
[ifs,rep] = cal.measureInput();
assert(abs(ifs - 1.5) < 1e-6*1.5,'measureInput: full scale %.8g V, expected 1.5 V',ifs);
assert(abs(rep.InputDbfs - 20*log10(cal.TargetPeak)) < 0.5, ...
    'measureInput: autorange should land the tone near %.1f dBFS at the input, not %.1f', ...
    20*log10(cal.TargetPeak),rep.InputDbfs);
assert(isempty(rep.Warnings),'measureInput: a clean loop-back should raise no warnings');
assert(rep.InputFullScale == ifs && isequal(cal.LastReport,rep), ...
    'measureInput: the report should carry the result');

% B2: a knob so high that -40 and -60 dBFS both clip: step down, never quote a clipped fit.
cal = makeCal(a,1000);
[ifs,rep] = cal.measureInput();
assert(abs(ifs - 3/1000) < 1e-6*3/1000,'measureInput: full scale %.8g V, expected 3 mV',ifs);
fits = [rep.Probes.Fit];
assert(numel(rep.Probes) == 3 && all([fits(1:2).Clipped]) && ~fits(3).Clipped, ...
    'measureInput: expected two clipped probes and a clean third, got %d probes',numel(rep.Probes));
assert(rep.Level < -70,'measureInput: the measurement should have been played at about -72 dBFS');

% B3: a knob so low the tone cannot reach the target: measured anyway, and said so.
cal = makeCal(a,0.01);
[ifs,rep] = cal.measureInput();
assert(abs(ifs - 300) < 1e-6*300,'measureInput: full scale %.8g V, expected 300 V',ifs);
assert(rep.Level == cal.MaxLevel && ~isempty(rep.Warnings), ...
    'measureInput: a tone held down at the top level should be measured with a warning');

% B4: nothing on the input -- the cable, not a number.
cal = makeCal(a,0);
try
    cal.measureInput();
    error('verify:noThrow','measureInput with no loop-back should throw');
catch me
    assert(strcmp(me.identifier,'mabr:acq:InputCalibrator:noTone'), ...
        'no loop-back should raise noTone, got %s',me.identifier);
end

% B5: the loop gain alone needs no output reference.
b = a; b.OutputFullScale = NaN;
cal = makeCal(b,0.5);
ratio = cal.measureLoopGain();
assert(abs(ratio - 0.5) < 1e-6,'measureLoopGain: %.8g, expected 0.5',ratio);
fprintf('  PASS Part B: measureInput autoranges, recovers the full scale, refuses a clipped or absent tone\n');

% ---- Part C: refusals, and the meter tone -----------------------------------
expectRefusal(makeCal(with(a,'Testing',true),1),'testingMode');
expectRefusal(makeCal(with(a,'StimulationOnly',true),1),'stimOnly');
ctl = mabrtest.FakeController();
ctl.State = mabr.ui.ProgState.Acquire;
calBusy = mabr.acq.InputCalibrator(a,a.config(),ctl);
expectRefusal(calBusy,'deviceBusy');
try
    makeCal(b,1).measureInput();
    error('verify:noThrow','measureInput with no output reference should throw');
catch me
    assert(strcmp(me.identifier,'mabr:acq:InputCalibrator:noReference'), ...
        'an unmeasured output should raise noReference, got %s',me.identifier);
end

cal = makeCal(a,1);
played = cal.playForMeter(-10,0.2);
assert(abs(played - 0.2) < 1e-9,'playForMeter should play for the time asked (%.3f s)',played);
played = cal.playForMeter(-10,5,@() true);
assert(played < 0.5,'playForMeter should stop, with a fade, soon after asked (%.3f s)',played);
fprintf('  PASS Part C: refuses Test Mode, stimulation only, a busy rig, no reference; the meter tone stops\n');

fprintf('== verify_input_calibration PASSED ==\n');
end

% =====================================================================
function cal = makeCal(a,gain)
% A calibrator whose "device" is a loop-back cable with the given gain,
% clipping at full scale like a real converter, and not paced in real time.
cal = mabr.acq.InputCalibrator(a,a.config());
cal.DeviceFactory = @(varargin) fakeDevice(gain,varargin{:});
end

function d = fakeDevice(gain,varargin)
d = mabrtest.FakeAudioDevice(varargin{:});
d.Gain = gain;
d.Realtime = false;
end

function a = with(a,name,value)
a.(name) = value;
end

function expectRefusal(cal,id)
try
    cal.measureLoopGain();
    error('verify:noThrow','measureLoopGain should have refused (%s)',id);
catch me
    assert(strcmp(me.identifier,['mabr:acq:InputCalibrator:' id]), ...
        'expected refusal %s, got %s: %s',id,me.identifier,me.message);
end
end
