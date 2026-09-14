function verify_audio_settings()
% verify_audio_settings  Confirm mabr.AudioSettings behaves as the GUI's Audio
%                        Device (ASIO) dialog and mabr.stim.Schedule expect.
%
%   Part A (defaults & describe): a fresh settings object matches the
%   documented defaults, and describe() names the device it holds.
%   Part B (prefs): the settings round-trip through setpref/getpref, and a
%   corrupt channel-mapping pref falls back to the default rather than
%   stopping the app (the user's own prefs are saved and restored, so running
%   this does not disturb them).
%   Part C (device query never throws): availableDevices() returns a cellstr
%   even with no ASIO driver present -- it feeds a settings dialog, not a
%   start-up check, and must not error out of it.
%   Part D (schedule wiring): assigning Device/PlayerChannels/RecorderChannels
%   onto a mabr.stim.Schedule and rendering a spec carries them through
%   exactly as mabr.acq.worker_loop's prepare_device expects.
%   Part E (sample rate): the rate the Audio Device (ASIO) dialog now sets
%   persists like the rest of the settings, becomes a mabr.Config through
%   config(), derives an integer decimation to a storage rate, and reaches the
%   rendered spec -- while a bank left at another rate is refused by
%   mabr.stim.Schedule rather than played at one clock and windowed at
%   another.
%   Part F (amplifier gain): the external amplifier gain persists like the
%   rest, is ignored in Test Mode, divides the recorded signal in
%   mabr.compute.Pipeline's live step and finalization without moving a
%   single onset, and is written to (and read back from) ADC.AmplifierGain.
%
%   No hardware, no parallel pool. Run:  >> verify_audio_settings
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_audio_settings ==\n');

% ---- Part A: defaults & describe -----------------------------------------
a = mabr.AudioSettings;
assert(isempty(a.Device),'default Device should be empty (system default)');
assert(isequal(a.PlayerChannels,[1 2]) && isequal(a.RecorderChannels,[1 2]), ...
    'default channel mappings should be [1 2]');
assert(islogical(a.Testing) && a.Testing,'default Testing should be true (loopback)');
assert(a.SampleRate == mabr.Config.DefaultDACSampleRate, ...
    'default SampleRate should be the Config default (%g Hz)',mabr.Config.DefaultDACSampleRate);
assert(contains(a.describe(),'TEST MODE'),'describe should lead with TEST MODE while Testing is set');
% The rate is named in every branch, Testing included: it is the one setting
% here that still governs something (stimulus rendering) with no device open.
assert(contains(a.describe(),'192 kHz'), ...
    'describe should name the sample rate even while Testing is set');

b = a; b.Device = 'Fireface UCX';
assert(contains(b.describe(),'TEST MODE'), ...
    'describe should still read TEST MODE regardless of Device while Testing is set');
b.Testing = false;
assert(contains(b.describe(),'Fireface UCX'),'describe should name a selected device once Test Mode is off');
assert(contains(b.describe(),'192 kHz'),'describe should name the sample rate with a device selected');
fprintf('  PASS Part A: defaults and describe()\n');

% ---- Part B: pref persistence --------------------------------------------
saved   = mabr.AudioSettings.loadPrefs();
restore = onCleanup(@() mabr.AudioSettings.savePrefs(saved));

q = mabr.AudioSettings;
q.Device = 'Test Device'; q.PlayerChannels = [2 1]; q.RecorderChannels = [1 3];
q.Testing = false; q.SampleRate = 96000;
mabr.AudioSettings.savePrefs(q);
r = mabr.AudioSettings.loadPrefs();
assert(strcmp(r.Device,q.Device),'Device did not survive a setpref/getpref round-trip');
assert(isequal(r.PlayerChannels,q.PlayerChannels), ...
    'PlayerChannels did not survive a setpref/getpref round-trip');
assert(isequal(r.RecorderChannels,q.RecorderChannels), ...
    'RecorderChannels did not survive a setpref/getpref round-trip');
assert(islogical(r.Testing) && r.Testing == false, ...
    'Testing did not survive a setpref/getpref round-trip');
assert(r.SampleRate == 96000,'SampleRate did not survive a setpref/getpref round-trip');

setpref('MABR','AudioPlayerChannels',[1 2 3]);   % invalid: wrong size
assert(isequal(mabr.AudioSettings.loadPrefs().PlayerChannels,[1 2]), ...
    'an invalid saved channel mapping should fall back to the default');

setpref('MABR','AudioTesting','not a logical');   % invalid: wrong type
assert(isequal(mabr.AudioSettings.loadPrefs().Testing,true), ...
    'an invalid saved Testing value should fall back to the default');

setpref('MABR','AudioSampleRate',-1);            % invalid: not a rate at all
assert(mabr.AudioSettings.loadPrefs().SampleRate == mabr.Config.DefaultDACSampleRate, ...
    'an invalid saved SampleRate should fall back to the default');
setpref('MABR','AudioSampleRate',8000);          % invalid: below the analysis rate
assert(mabr.AudioSettings.loadPrefs().SampleRate == mabr.Config.DefaultDACSampleRate, ...
    'a SampleRate below the analysis rate should fall back to the default');
fprintf('  PASS Part B: settings persist; a corrupt pref falls back\n');

% ---- Part C: device query never throws -----------------------------------
names = mabr.AudioSettings.availableDevices();
assert(iscell(names),'availableDevices must return a cellstr even with no ASIO driver');
fprintf('  PASS Part C: device query is graceful with no ASIO driver present\n');

% ---- Part D: schedule wiring ----------------------------------------------
cfg = mabr.Config;
set = mabr.stim.demoStimuli(cfg);
sch = mabr.stim.Schedule(set,cfg);
sch.Repetitions(:) = 1;
sch.Device           = 'Loopback Device';
sch.PlayerChannels   = [2 3];
sch.RecorderChannels = [4 5];
sch.build();
spec = sch.renderSpec(sch.current());
assert(strcmp(spec.Device,'Loopback Device'),'Device must reach the rendered spec');
assert(isequal(spec.PlayerChannels,[2 3]),'PlayerChannels must reach the rendered spec');
assert(isequal(spec.RecorderChannels,[4 5]),'RecorderChannels must reach the rendered spec');

% The default ('' = audioPlayerRecorder's own default) is deliberately left
% OFF the spec, not sent as an empty Device -- prepare_device only adds the
% 'Device' name-value pair when spec.Device is present (see worker_loop.m).
sch2 = mabr.stim.Schedule(set,cfg);
sch2.Repetitions(:) = 1;
sch2.build();
spec2 = sch2.renderSpec(sch2.current());
assert(~isfield(spec2,'Device'),'an empty Device must be omitted from the spec, not sent as ''''');
fprintf('  PASS Part D: Device/channel mapping reach the rendered spec\n');

% ---- Part E: the sample rate ----------------------------------------------
% E1: config() is the one place the setting becomes a mabr.Config, and the
% analysis rate is DERIVED there rather than being a second setting.
e = mabr.AudioSettings;
c = e.config();
assert(isa(c,'mabr.Config'),'config() must return a mabr.Config');
assert(c.DACSampleRate == e.SampleRate,'config() must carry the settings'' rate');
assert(c.ADCSampleRate == 12000 && c.decimationFactor == 16, ...
    'the 192 kHz default should derive 12 kHz storage at a stride of 16 (got %g Hz, %g)', ...
    c.ADCSampleRate,c.decimationFactor);

e.SampleRate = 96000;
c96 = e.config();
assert(c96.DACSampleRate == 96000 && c96.ADCSampleRate == 12000 && c96.decimationFactor == 8, ...
    '96 kHz should derive 12 kHz storage at a stride of 8');

% The decimation stride is an INTEGER because extract_sweeps windows the ring
% buffer with it as a colon stride -- so the 44.1 kHz family lands on 11.025
% kHz rather than on a 12 kHz that no whole stride can reach.
assert(mabr.Config.decimationFor(44100) == 4 && mabr.Config.adcRateFor(44100) == 11025, ...
    '44.1 kHz should decimate by 4 to 11.025 kHz, not to a rate no integer stride reaches');
for fs = mabr.Config.SupportedSampleRates
    df = mabr.Config.decimationFor(fs);
    assert(df == round(df) && df >= 1, ...
        'decimationFor(%g) must be a positive integer (got %g)',fs,df);
    assert(abs(mabr.Config.adcRateFor(fs)*df - fs) < 1e-9, ...
        'adcRateFor(%g) x decimation must return the DAC rate exactly',fs);
end

% E2: what is and is not a rate. Validation lives in mabr.Config so there is
% one rule, and AudioSettings' coercion defers to it (exercised in Part B).
for bad = {0,-1,NaN,Inf,'nope',[48000 96000]}
    refused = false;
    try, mabr.Config.validateSampleRate(bad{1}); catch, refused = true; end
    assert(refused,'validateSampleRate should refuse %s',mat2str(bad{1}));
end
assert(mabr.Config.validateSampleRate(48000) == 48000,'48 kHz is a perfectly good rate');

% E3: the configuration file. A .mabrcfg written before this setting existed
% has no SampleRate field at all, and must restore at the default rather than
% at whatever the struct happens not to say.
t = e.toStruct();
assert(isfield(t,'SampleRate') && t.SampleRate == 96000,'toStruct must carry SampleRate');
assert(mabr.AudioSettings.fromStruct(t).SampleRate == 96000, ...
    'SampleRate did not survive a toStruct/fromStruct round-trip');
legacy = rmfield(t,'SampleRate');
assert(mabr.AudioSettings.fromStruct(legacy).SampleRate == mabr.Config.DefaultDACSampleRate, ...
    'a configuration saved before the setting existed should restore at the default rate');

% E4: a bank rendered at the rate reaches the device at that rate, and the run
% is correspondingly longer in samples -- the ISI is in seconds, so doubling
% the clock doubles the sample count for the same plan.
cfgLo  = mabr.Config(48000);
setLo  = mabr.stim.demoStimuli(cfgLo);
assert(setLo.SampleRate == 48000,'demoStimuli must render at the Config rate');
schLo  = mabr.stim.Schedule(setLo,cfgLo);
schLo.Repetitions(:) = 2; schLo.build();
specLo = schLo.renderSpec(schLo.current());
assert(specLo.SampleRate == 48000,'the rendered spec must carry the bank''s rate to the device');

cfgHi  = mabr.Config(96000);
setHi  = mabr.stim.demoStimuli(cfgHi);
schHi  = mabr.stim.Schedule(setHi,cfgHi);
schHi.Repetitions(:) = 2; schHi.build();
specHi = schHi.renderSpec(schHi.current());
ratio  = specHi.Plan.N/specLo.Plan.N;
assert(abs(ratio - 2) < 0.01, ...
    'doubling the sample rate should roughly double the play matrix (got %.3fx)',ratio);

% E5: the mismatch that matters. renderSpec sends the BANK's rate to the
% device while mabr.ui.AcqController decimates by the CONFIG's, so a bank left
% at another rate is two clocks, not a rounding error -- refused at plan time.
threw = false;
try
    mabr.stim.Schedule(setLo,cfgHi);
catch me
    threw = strcmp(me.identifier,'mabr:stim:Schedule:sampleRate');
end
assert(threw,'a Schedule must refuse a bank rendered at a rate other than the Config''s');
fprintf('  PASS Part E: sample rate persists, derives its storage rate, and reaches the spec\n');

% ---- Part F: amplifier gain ------------------------------------------------
% F1: the setting persists both ways, and a nonsense value falls back.
f = mabr.AudioSettings;
assert(f.AmplifierGain == 1,'default AmplifierGain should be 1 (no external amplifier)');
f.AmplifierGain = 10000; f.Testing = false;
mabr.AudioSettings.savePrefs(f);
assert(mabr.AudioSettings.loadPrefs().AmplifierGain == 10000, ...
    'AmplifierGain did not survive a setpref/getpref round-trip');
setpref('MABR','AudioAmplifierGain',-3);
assert(mabr.AudioSettings.loadPrefs().AmplifierGain == 1, ...
    'a non-positive saved AmplifierGain should fall back to the default');
t = f.toStruct();
assert(mabr.AudioSettings.fromStruct(t).AmplifierGain == 10000, ...
    'AmplifierGain did not survive a toStruct/fromStruct round-trip');
assert(mabr.AudioSettings.fromStruct(rmfield(t,'AmplifierGain')).AmplifierGain == 1, ...
    'a configuration saved before the setting existed should restore at gain 1');
assert(contains(f.describe(),'gain 10000'),'describe should name a non-unity amplifier gain');

% F2: Test Mode has no amplifier in the path, so the gain is not applied there.
assert(f.recordingGain() == 10000,'recordingGain should be the setting off Test Mode');
f.Testing = true;
assert(f.recordingGain() == 1,'recordingGain must be 1 in Test Mode');

% F3: the pipeline divides the recorded signal -- live AND finalized -- and
% leaves the timing channel alone (the same onsets are recovered either way).
fs  = cfg.DACSampleRate;
N   = round(0.25*fs);
tt  = (0:N-1)'/fs;
sig = 0.02*sin(2*pi*1000*tt) + 0.002*randn(N,1);
tim = zeros(N,1);
on  = round((0.02:0.02:0.22)*fs);   % clear of both ends: a baseline precedes each
for k = on, tim(k:k+round(0.001*fs)) = 1; end
seq  = ones(1,numel(on));
info = struct('RunId',1,'StimIndex',seq,'Stimuli',1);
G    = 1000;

p1 = mabr.compute.Pipeline(cfg); p1.configure([0 0.01],mabr.FilterPolicy,mabr.ArtifactPolicy);
pG = mabr.compute.Pipeline(cfg); pG.configure([0 0.01],mabr.FilterPolicy,mabr.ArtifactPolicy,G);
p1.beginRun(info); pG.beginRun(info);
r1 = mabrtest.GrowingRing(sig,tim); r1.Head = N;
rG = mabrtest.GrowingRing(sig,tim); rG.Head = N;
s1 = p1.step(r1); sG = pG.step(rG);
assert(~isempty(s1) && sG.NumSweeps == s1.NumSweeps && s1.NumSweeps == numel(on), ...
    'the gain must not change which sweeps are found (%d vs %d of %d)', ...
    sG.NumSweeps,s1.NumSweeps,numel(on));
assert(max(abs(sG.Mean(:)*G - s1.Mean(:))) <= 1e-5*max(abs(s1.Mean(:))), ...
    'the live mean was not divided by the amplifier gain');

F1 = p1.finalize(r1,seq); FG = pG.finalize(rG,seq);
assert(isequal(FG.OnsetsRaw,F1.OnsetsRaw),'the gain must not move the recovered onsets');
assert(FG.AmplifierGain == G && F1.AmplifierGain == 1, ...
    'finalization must report the gain its Data was divided by');
d1 = double(F1.Parts(1).Data); dG = double(FG.Parts(1).Data);
assert(max(abs(dG*G - d1)) <= 1e-5*max(abs(d1)), ...
    'the finalized Data was not divided by the amplifier gain');

% Changing the gain mid-run rescales what is already cached.
pG.configure([],[],[],1);
s1b = pG.step(rG);
assert(isequal(s1b.Mean,s1.Mean),'reconfiguring the gain must refilter the cached sweeps');

% F4: the .abr records it, and reading one back restores it.
rec = mabr.data.Recording(cfg.ADCSampleRate,FG.Parts(1).Data,FG.Parts(1).Onsets, ...
    FG.Parts(1).SweepLength,1);
blk = mabr.data.Block(struct('Meta',struct('ID','gain')),rec);
blk.AmplifierGain = G;
ABR_Data = mabr.data.io.buildStruct(blk);
assert(isfield(ABR_Data.ADC,'AmplifierGain') && ABR_Data.ADC.AmplifierGain == G, ...
    'the .abr must carry ADC.AmplifierGain');
tmp = [tempname '.abr'];
cleanTmp = onCleanup(@() delete(tmp)); %#ok<NASGU>
save(tmp,'ABR_Data','-mat');
assert(mabr.data.io.importLegacy(tmp).AmplifierGain == G, ...
    'importLegacy did not read ADC.AmplifierGain back');
fprintf('  PASS Part F: amplifier gain persists, scales live and saved data, reaches the .abr\n');

fprintf('== verify_audio_settings PASSED ==\n');
end
