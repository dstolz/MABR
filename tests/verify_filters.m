function verify_filters()
% verify_filters  Confirm the display filter chain does what it claims — and,
%                 more importantly, that it never reaches the saved data.
%
%   Part A (design): mabr.FilterPolicy builds each section independently and
%   the realized (filtfilt, so squared) response has the corners it says.
%   Part B (attenuation): a signal made of a drift, a 60 Hz hum, a 1 kHz
%   response, and an 5 kHz hiss loses exactly the components the enabled
%   sections target, and keeps the one they do not.
%   Part C (prefs): the chain round-trips through MATLAB prefs, and a corrupt
%   pref falls back to the default rather than stopping the app (the user's
%   own prefs are saved and restored, so running this does not disturb them).
%   Part D (data model): mabr.data.Recording filters everything DERIVED and
%   nothing STORED — Data is untouched, ProcessedData is filtered, and the
%   .abr struct mabr.data.io builds carries the raw samples.
%   Part E (validation): an unrealizable chain is reported, not thrown, so
%   mabr.ui.FilterDialog can grey out OK instead of erroring at the user.
%
%   No hardware, no parallel pool. Run:  >> verify_filters
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_filters ==\n');

cfg = mabr.Config;                   % default rig: 192 kHz out, 12 kHz stored
Fs = cfg.ADCSampleRate;              % the rate both views filter at

% ---- Part A: sections are independent, and the response is real ---------
p = mabr.FilterPolicy;
assert(p.HighPass && p.LowPass && p.Notch,'the default chain should be all three');
assert(p.Enabled && ~p.Designed,'a fresh policy is not yet designed');

assert(~mabr.FilterPolicy(false,false,false).Enabled, ...
    'a policy with every section off must report itself disabled');

d = p.design(Fs);
assert(d.Designed && numel(d.Designs) == 3,'expected three designed sections');
assert(d.isDesignedFor(Fs) && ~d.isDesignedFor(2*Fs), ...
    'a design is only valid at the rate it was built for');

hpOnly = mabr.FilterPolicy(10,false,false).design(Fs);
assert(isscalar(hpOnly.Designs),'high pass alone should design one section');

% filtfilt applies the chain twice, so a corner sits at -6 dB, not -3.
[mag,f] = p.response(Fs);
atHP  = interp1(f,mag,p.HighPassHz);
atLP  = interp1(f,mag,p.LowPassHz);
inBand = interp1(f,mag,1000);
assert(abs(atHP+6) < 1.5 && abs(atLP+6) < 1.5, ...
    'the corners should read -6 dB as applied, got %.1f / %.1f',atHP,atLP);
assert(abs(inBand) < 0.5,'the passband should be flat, got %.2f dB',inBand);

% The notch has to be deep AND narrow, or it eats the response it protects.
notchDepth = min(mag(f > 55 & f < 65));
assert(notchDepth < -20,'the notch is only %.1f dB deep',notchDepth);
assert(interp1(f,mag,120) > -1,'the notch is bleeding into 120 Hz');
fprintf('  PASS Part A: sections design independently; corners land where claimed\n');

% ---- Part B: what it actually removes from a signal ---------------------
t     = (0:Fs-1).'/Fs;                       % 1 s
drift = 3*sin(2*pi*0.5*t);                   % slow electrode wander
hum   = 1*sin(2*pi*60*t);                    % mains
resp  = 1*sin(2*pi*1000*t);                  % the thing we came for
hiss  = 1*sin(2*pi*5000*t);                  % above the response band
x     = drift + hum + resp + hiss;

y = d.apply(x);
power_at = @(sig,f0) abs(mean(sig(:).*exp(-2i*pi*f0*t)));

for spec = {'drift',0.5; 'hum',60; 'hiss',5000}'
    lost = power_at(y,spec{2})/power_at(x,spec{2});
    assert(lost < 0.05,'%s survived at %.1f%% of its amplitude',spec{1},100*lost);
end
kept = power_at(y,1000)/power_at(x,1000);
assert(kept > 0.95,'the 1 kHz response should survive, kept %.1f%%',100*kept);

% An undesigned policy is a no-op, the same opt-in rule Recording follows.
assert(isequal(mabr.FilterPolicy().apply(x),x), ...
    'an undesigned policy must return its input untouched');
% ... and so is a designed-but-empty one.
assert(isequal(mabr.FilterPolicy(false,false,false).design(Fs).apply(x),x), ...
    'a policy with nothing enabled must return its input untouched');

% Row vectors come back as row vectors, and single stays single: the live
% path hands this sweep matrices in whatever shape extract_sweeps produced.
assert(isrow(d.apply(x(1:200).')),'a row vector must come back as a row');
assert(isa(d.apply(single(x)),'single'),'single input should stay single');
% A sweep too short to filtfilt must pass through rather than throw — a
% truncated run should not take the live view down with it.
assert(isequal(d.apply(x(1:5)),x(1:5)),'a too-short signal should pass through');
fprintf('  PASS Part B: drift, hum, and hiss removed; the response kept\n');

% ---- Part C: pref persistence ------------------------------------------
saved   = mabr.FilterPolicy.loadPrefs();
restore = onCleanup(@() mabr.FilterPolicy.savePrefs(saved));

q = mabr.FilterPolicy;
q.HighPass = false; q.LowPassHz = 1500; q.NotchHz = 50; q.Order = 6;
mabr.FilterPolicy.savePrefs(q);
r = mabr.FilterPolicy.loadPrefs();
assert(r.sameSettings(q),'the chain did not survive a setpref/getpref round-trip');
assert(~r.sameSettings(mabr.FilterPolicy),'sameSettings should notice a difference');

setpref('MABR','FilterLowPassHz',-1);
assert(mabr.FilterPolicy.loadPrefs().LowPassHz == 3000, ...
    'an invalid saved corner should fall back to the default');
fprintf('  PASS Part C: chain persists; a corrupt pref falls back\n');

% ---- Part D: derived views filtered, stored samples not -----------------
rec = mabr.data.Recording(Fs,x,[1;301;601],300,1);
raw = rec.Data;
rec.Filters = mabr.FilterPolicy;      % settings only; not yet in effect

assert(isequal(rec.ProcessedData,raw), ...
    'filtering must stay opt-in until designFilters() is called');

rec = rec.designFilters();
assert(isequal(rec.Data,raw),'designFilters must not touch Data');
assert(~isequal(rec.ProcessedData,raw),'ProcessedData should now be filtered');
assert(max(abs(double(rec.ProcessedData) - double(raw))) > 1, ...
    'the drift alone should move ProcessedData well away from the raw trace');
assert(isequal(size(rec.SweepData),[300 3]),'segmentation should be unchanged');

meta = struct('ID','filt','informativeParams',{{}},'Label',{{}});
blk  = mabr.data.Block(struct('Meta',meta,'SampleRate',192000),rec,'');
blk.SweepPolarity = ones(1,3);
S = mabr.data.io.buildStruct(blk);
assert(isequal(single(S.ADC.Data(:)),single(raw(:))), ...
    'the .abr struct must carry the RAW trace, not the filtered one');
fprintf('  PASS Part D: derived views filtered, saved trace raw\n');

% ---- Part E: validation reports rather than throws ----------------------
bad = mabr.FilterPolicy;
bad.HighPassHz = 4000; bad.LowPassHz = 100;      % passes nothing
[ok,msg] = bad.validate(Fs);
assert(~ok && contains(msg,'below low pass'),'an inverted band should be caught');

bad = mabr.FilterPolicy; bad.LowPassHz = Fs;      % above Nyquist
assert(~bad.validate(Fs),'a corner above Nyquist should be caught');

bad = mabr.FilterPolicy; bad.NotchWidthHz = 200;  % wider than its own centre
assert(~bad.validate(Fs),'a notch wider than its centre should be caught');

assert(mabr.FilterPolicy().validate(Fs),'the default chain must be valid');
% A disabled section's numbers are not consulted, however silly they are.
odd = mabr.FilterPolicy; odd.LowPass = false; odd.LowPassHz = Fs;
assert(odd.validate(Fs),'a switched-off section must not fail validation');
fprintf('  PASS Part E: unrealizable chains are reported, not thrown\n');

fprintf('== verify_filters PASSED ==\n');
end
