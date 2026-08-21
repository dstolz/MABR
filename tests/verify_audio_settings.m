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
assert(contains(a.describe(),'TESTING'),'describe should lead with TESTING while Testing is set');

b = a; b.Device = 'Fireface UCX';
assert(contains(b.describe(),'TESTING'), ...
    'describe should still read TESTING regardless of Device while Testing is set');
b.Testing = false;
assert(contains(b.describe(),'Fireface UCX'),'describe should name a selected device once Testing is off');
fprintf('  PASS Part A: defaults and describe()\n');

% ---- Part B: pref persistence --------------------------------------------
saved   = mabr.AudioSettings.loadPrefs();
restore = onCleanup(@() mabr.AudioSettings.savePrefs(saved));

q = mabr.AudioSettings;
q.Device = 'Test Device'; q.PlayerChannels = [2 1]; q.RecorderChannels = [1 3];
q.Testing = false;
mabr.AudioSettings.savePrefs(q);
r = mabr.AudioSettings.loadPrefs();
assert(strcmp(r.Device,q.Device),'Device did not survive a setpref/getpref round-trip');
assert(isequal(r.PlayerChannels,q.PlayerChannels), ...
    'PlayerChannels did not survive a setpref/getpref round-trip');
assert(isequal(r.RecorderChannels,q.RecorderChannels), ...
    'RecorderChannels did not survive a setpref/getpref round-trip');
assert(islogical(r.Testing) && r.Testing == false, ...
    'Testing did not survive a setpref/getpref round-trip');

setpref('MABR','AudioPlayerChannels',[1 2 3]);   % invalid: wrong size
assert(isequal(mabr.AudioSettings.loadPrefs().PlayerChannels,[1 2]), ...
    'an invalid saved channel mapping should fall back to the default');

setpref('MABR','AudioTesting','not a logical');   % invalid: wrong type
assert(isequal(mabr.AudioSettings.loadPrefs().Testing,true), ...
    'an invalid saved Testing value should fall back to the default');
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

fprintf('== verify_audio_settings PASSED ==\n');
end
