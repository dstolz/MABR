function verify_calibration_latency()
% verify_calibration_latency  Confirm mabr.stim.CalibrationAdapter removes
%                             the device round-trip latency from what it
%                             hands stimgen, using the timing loop-back.
%
%   A duplex device returns its input aligned to the output STREAM, so a
%   record carries the converters' round trip (tens of ms on ASIO) on top of
%   the acoustic path. Uncorrected, a 10 cm speaker-to-mic path measured as a
%   25 ms conduction delay -- metres of air. The adapter now sends a pulse on
%   the timing channel with every record and shifts the mic record by the lag
%   that pulse comes back with.
%
%   Part A (the arithmetic): alignToLoopback recovers a planted lag exactly,
%   returns the n samples after it, and reports NaN -- leaving the record
%   unshifted -- for a missing pulse or a record too short to shift.
%   Part B (the adapter): over a simulated device with a 25 ms round trip and
%   a 10 cm acoustic path, play_and_record's record puts the excitation at the
%   acoustic delay alone, LastLatency is the round trip, and the record is the
%   length stimgen handed in.
%   Part C (the number the user saw): stimgen's own measure_conduction_delay,
%   run through that adapter, reads the acoustic delay (~0.29 ms), and with
%   CompensateLatency off reads the old bulk figure -- so the test can fail.
%   Skips when the stimgen submodule is absent.
%   Part D (degradation): no pulse back, or a timing input shared with the
%   mic, still returns a record -- uncompensated, LastLatency NaN -- because
%   levels do not depend on latency and a missing cable must not stop a
%   calibration.
%
%   No hardware, no parallel pool, no prefs. Run:  >> verify_calibration_latency
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_calibration_latency ==\n');

cfg = mabr.Config;
fs  = cfg.DACSampleRate;
audio = mabr.AudioSettings();
audio.Testing = false;          % the adapter refuses Test Mode
audio.PlayerChannels   = [1 2];
audio.RecorderChannels = [1 2];
audio.MicChannel       = 3;     % a mic input distinct from the timing input

L = round(0.02519*fs);          % ASIO round trip, as measured on the rig
A = round(0.10/343.2*fs);       % 10 cm of air at 20 C

% ---- Part A: the arithmetic ------------------------------------------------
n = 1000;
x = randn(n + 400,1);
t = zeros(n + 400,1); t(38:60) = 1;          % pulse from sample 1, 37 late
[y,lag] = mabr.stim.CalibrationAdapter.alignToLoopback(x,t,n);
assert(lag == 37,'the lag is the loop-back onset minus one (got %g)',lag);
assert(isequal(y,x(38:37+n)),'the record must be the n samples after the lag');

[y,lag] = mabr.stim.CalibrationAdapter.alignToLoopback(x,zeros(size(t)),n);
assert(isnan(lag) && isequal(y,x(1:n)),'no pulse: NaN lag and an unshifted record');

t2 = zeros(n + 400,1); t2(450:470) = 1;      % lag 449 > the 400-sample tail
[y,lag] = mabr.stim.CalibrationAdapter.alignToLoopback(x,t2,n);
assert(isnan(lag) && isequal(y,x(1:n)), ...
    'a lag the record cannot be shifted by must be refused, not read past the end');
fprintf('  PASS Part A: alignToLoopback recovers the lag and refuses what it cannot shift\n');

% ---- Part B: the adapter -----------------------------------------------------
ad = mabrtest.LatentAdapter(audio,cfg,L,A);
ad.Noise = 0;
sig = zeros(1,4000); sig(101) = 1;           % one sample, at sample 101
rec = ad.play_and_record(sig);
assert(isequal(size(rec),size(sig)),'the record must be the length stimgen handed in');
assert(ad.LastLatency == L,'LastLatency should be the round trip (%d), got %g',L,ad.LastLatency);
[~,pk] = max(abs(rec));
assert(pk == 101 + A, ['the excitation must come back after the acoustic delay ' ...
    'alone: expected sample %d, got %d'],101 + A,pk);

% The tail matters on its own: before, a response arriving L samples late was
% cut off L samples early. An excitation near the end of the record (closer
% than L, further than A) must now come back.
sig = zeros(1,4000); sig(end-99) = 1;
rec = ad.play_and_record(sig);
[~,pk] = max(abs(rec));
assert(pk == numel(sig) - 99 + A && rec(pk) == ad.Gain, ...
    'an excitation near the end of the record must not lose its response to the latency');
fprintf('  PASS Part B: record aligned to the air, LastLatency = %d samples (%.2f ms)\n', ...
    ad.LastLatency,ad.LastLatency/fs*1e3);

% ---- Part C: the number the user saw ------------------------------------
[avail,why] = mabr.stim.stimgenAvailable();
if ~avail
    fprintf('  SKIP Part C: %s\n',why);
else
    ad  = mabrtest.LatentAdapter(audio,cfg,L,A);
    eng = stimgen.calibration.Engine(ad);
    d   = eng.measure_conduction_delay();
    assert(d.valid,'the conduction-delay measurement should be valid');
    assert(abs(d.delay_samples - A) <= 2, ['conduction delay should read the ' ...
        '%d-sample acoustic path (%.3f ms), got %d samples (%.3f ms)'], ...
        A,A/fs*1e3,d.delay_samples,d.delay_s*1e3);
    fprintf('  PASS Part C: measured %.3f ms / %.3f m (expected %.3f ms / 0.10 m)\n', ...
        d.delay_s*1e3,d.path_m,A/fs*1e3);

    ad.CompensateLatency = false;
    d = eng.measure_conduction_delay();
    assert(abs(d.delay_samples - (L + A)) <= 2, ['uncompensated, the delay must ' ...
        'include the round trip -- otherwise Part C proves nothing']);
    assert(isnan(ad.LastLatency),'LastLatency must be NaN when nothing was removed');
    fprintf('  PASS Part C: uncompensated reads %.3f ms, as the rig did\n',d.delay_s*1e3);
end

% ---- Part D: degradation -----------------------------------------------------
fprintf('  (two red "latency is NOT removed" warnings below are expected)\n');
ad = mabrtest.LatentAdapter(audio,cfg,L,A);
ad.Noise = 0; ad.Loopback = false;
sig = zeros(1,4000); sig(101) = 1;
rec = ad.play_and_record(sig);
assert(isequal(size(rec),size(sig)) && isnan(ad.LastLatency), ...
    'no pulse back: still a record of the right length, LastLatency NaN');
assert(all(rec == 0),'uncompensated, the 25 ms-late response lies past this short record');
assert(ad.LatencyWarned,'a missing loop-back must be reported');

shared = audio; shared.MicChannel = shared.RecorderChannels(2);
ad = mabrtest.LatentAdapter(shared,cfg,L,A);
assert(~ad.hasLoopback(),'a mic patched to the timing input leaves no loop-back');
rec = ad.play_and_record(sig);
assert(isequal(size(rec),size(sig)) && isnan(ad.LastLatency) && ad.LatencyWarned, ...
    'a shared timing input: uncompensated, reported, still a record');
fprintf('  PASS Part D: no loop-back degrades to an uncompensated record, reported once\n');

fprintf('== verify_calibration_latency PASSED ==\n');
end
