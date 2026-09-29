function verify_stimgen_launcher()
% verify_stimgen_launcher  The stimgen tools launcher, no hardware.
%
%   mabr.ui.StimgenLauncher opens stimgen's four windows on one rig. This
%   checks the parts that are decisions rather than drawing:
%
%   Part A (settings): defaults, forgiving sanitizing (junk fields fall back,
%   the recent list is de-duplicated and capped), the preference round trip,
%   and that the configuration-file half carries the hardware choice and the
%   calibration file but not the per-machine history -- and merging one over
%   the prefs leaves that history alone.
%   Part B (the rig): Test Mode under the MABR rig is reported and yields no
%   adapter (with a reason) rather than an adapter that fails later; Offline
%   yields none; a real setting yields a CalibrationAdapter that is REUSED
%   while nothing it was built from changes and rebuilt when it does.
%   Part C (the tools): the designer opens at the rig's sample rate with
%   capture routed to an adapter built from it -- the SAME adapter the
%   launcher holds (one owner per device) -- and its preview output on that
%   adapter, since with no HardwareHost the capture adapter is also the
%   designer's hardware Play route (Offline stays on the speakers, and with
%   no adapter the hardware output is refused); the designer behind the main
%   window's Design… button (mabr.ui.App.putDesignerOnRig) lands on that same
%   adapter with its Output dropdown back and the session controls still
%   hidden, and stays on the speakers, saying why, under Test Mode and
%   Offline; the calibration window opens
%   on the shared engine and is raised, not duplicated, on a second press;
%   the inspector reads a stimulus out of a .mat; every tool button carries
%   its icon and the Help button is there.
%   Part D (calibration): a remembered calibration file that has gone is
%   dropped with a status, not a launcher that will not open.
%
%   Skips (and passes) without the stimgen submodule. The user's own
%   preferences are saved and restored around the run, and every window this
%   opens is closed again.
%
%   See also mabr.ui.StimgenLauncher, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('=== verify_stimgen_launcher ===\n');

[avail,why] = mabr.stim.stimgenAvailable();
if ~avail
    fprintf('  SKIP: %s\n',why);
    return
end

prefNames = {'StimgenTools','WindowPos_StimgenLauncher'};
saved = save_prefs(prefNames);
restorePrefs = onCleanup(@() restore_prefs(prefNames,saved)); %#ok<NASGU>
clear_prefs(prefNames);

figsBefore = findall(groot,'Type','figure');
closeNew = onCleanup(@() close_new(figsBefore)); %#ok<NASGU>


% ---- Part A: settings ----------------------------------------------------
d = mabr.ui.StimgenLauncher.defaults();
assert(strcmp(d.Source,'mabr') && isempty(d.CalibrationFile) && isempty(d.Recent), ...
    'defaults should be the MABR rig, no calibration, no history');

junk = mabr.ui.StimgenLauncher.sanitize(struct('Source','nonsense','CalibrationFile',42,'Recent',{{'a','A','b','a'}}));
assert(strcmp(junk.Source,'mabr') && isempty(junk.CalibrationFile), ...
    'invalid fields must fall back to the default, not throw or stick');
assert(isequal(junk.Recent,{'a','b'}), ...
    'the recent list must be de-duplicated (case-insensitively), order kept');
many = mabr.ui.StimgenLauncher.sanitize(struct('Recent',{arrayfun(@(k) sprintf('f%d',k),1:30,'UniformOutput',false)}));
assert(numel(many.Recent) == mabr.ui.StimgenLauncher.MaxRecent,'the recent list must be capped');
assert(isequal(mabr.ui.StimgenLauncher.sanitize('not a struct'),d),'a non-struct pref must sanitize to the defaults');
fprintf('  A: defaults and sanitizing\n');

s = d; s.Source = 'soundcard'; s.CalibrationFile = 'C:\x\rig.esgc'; s.Recent = {'r1.spl'};
mabr.ui.StimgenLauncher.savePrefs(s);
back = mabr.ui.StimgenLauncher.loadPrefs();
assert(isequal(back,mabr.ui.StimgenLauncher.sanitize(s)),'the settings must survive the preference round trip');

c = mabr.ui.StimgenLauncher.configStruct();
assert(isequal(sort(fieldnames(c)),{'CalibrationFile';'Source'}), ...
    'a configuration carries the hardware choice and the calibration, and no history');
mabr.ui.StimgenLauncher.saveConfigStruct(struct('Source','offline','CalibrationFile',''));
after = mabr.ui.StimgenLauncher.loadPrefs();
assert(strcmp(after.Source,'offline') && isempty(after.CalibrationFile), ...
    'saveConfigStruct must write the configuration''s fields');
assert(isequal(after.Recent,{'r1.spl'}), ...
    'merging a configuration must leave the per-machine history alone');
assert(isequal(mabr.ui.StimgenLauncher.mergeConfig(after,'junk'),after),'a non-struct configuration block is ignored');
clear_prefs(prefNames);
fprintf('  A: preference and configuration round trips\n');

% ---- Part B: the rig -----------------------------------------------------
audio = mabr.AudioSettings;
audio.Testing = true;
audio.SampleRate = 48000;
lch = mabr.ui.StimgenLauncher(AudioFcn=@() audio,Show=false, ...
    Settings=struct('Source','mabr'));
cleanL = onCleanup(@() delete(lch)); %#ok<NASGU>

[txt,warn] = lch.describeRig();
assert(warn && contains(txt,'Test Mode'),'Test Mode under the MABR rig must be reported');
[ad,whyNone] = lch.resolveAdapter();
assert(isempty(ad) && ~isempty(whyNone),'Test Mode must yield no adapter, with a reason');

lch.setSource('offline');
[txt,warn] = lch.describeRig();
assert(~warn && contains(txt,'Offline'),'Offline is not a warning');
assert(isempty(lch.resolveAdapter()),'Offline must yield no adapter');

audio.Testing = false;
lch.AudioFcn = @() audio;   % a value object: hand over the edited copy
lch.setSource('mabr');
[txt,warn] = lch.describeRig();
assert(~warn && contains(txt,'48'),'the rig line must name the sample rate: %s',txt);
ad1 = lch.resolveAdapter();
assert(isa(ad1,'mabr.stim.CalibrationAdapter'),'the MABR rig must build a CalibrationAdapter');
assert(ad1.sample_rate() == 48000,'the adapter must measure at the rig''s rate');
assert(ad1 == lch.resolveAdapter(),'an adapter must be reused while nothing it depends on changed');
audio.MicChannel = 2;
lch.AudioFcn = @() audio;
ad2 = lch.resolveAdapter();
assert(ad2 ~= ad1 && ad2.Audio.MicChannel == 2, ...
    'changing the microphone input must rebuild the adapter');
refused = false;
try
    lch.setSource('nonsense');
catch me
    refused = strcmp(me.identifier,'mabr:ui:StimgenLauncher:badSource');
end
assert(refused,'an unknown hardware choice must be refused');
fprintf('  B: rig description and adapters\n');

% ---- Part C: the tools ---------------------------------------------------
btn = findall(lch.Figure,'Type','uibutton');
icons = arrayfun(@(b) ~isempty(b.Icon),btn);
tool = arrayfun(@(b) any(strcmp(b.Text,{'Stimulus Designer','Calibration','Spot Check','Stimulus Inspector'})),btn);
assert(nnz(tool) == 4,'expected the four tool buttons');
assert(all(icons(tool)),'every tool button must carry its icon');
assert(any(arrayfun(@(b) contains(b.Text,'Help'),btn)),'the launcher must have a Help button');

sp = lch.openDesigner();
assert(~isempty(sp) && isvalid(sp),'the designer must open');
assert(sp.Fs == 48000,'the designer must open at the rig''s sample rate (got %g)',sp.Fs);
assert(isa(sp.CaptureAdapter,'function_handle'),'capture must be routed through the rig');
capAd = sp.CaptureAdapter();
assert(isa(capAd,'mabr.stim.CalibrationAdapter') && capAd.sample_rate() == 48000, ...
    'the designer''s capture adapter must be the rig''s');
assert(capAd == lch.resolveAdapter() && capAd == sp.CaptureAdapter(), ...
    'the designer and the launcher must share one adapter (one owner per device)');
% With no HardwareHost, the capture adapter is also the designer's hardware
% preview route -- Play must reach the rig, not the computer speakers.
assert(sp.PlaybackOutput == "Hardware", ...
    'the designer must open with its preview output on the rig (got %s)',sp.PlaybackOutput);
sp.PlaybackOutput = "Speakers";
sp.PlaybackOutput = "Hardware";   % selectable by hand, not only at open
sp.CaptureAdapter = [];
assert(sp.PlaybackOutput == "Speakers", ...
    'taking the adapter away must take the hardware preview route with it');
refused = false;
try
    sp.PlaybackOutput = "Hardware";
catch me
    refused = strcmp(me.identifier,'stimgen:StimPlayer:NoHardwareHost');
end
assert(refused,'hardware preview with no host and no adapter must be refused');
delete(sp);

lch.setSource('offline');
sp = lch.openDesigner();
assert(isempty(sp.CaptureAdapter),'offline: the designer must get no capture adapter');
assert(sp.PlaybackOutput == "Speakers",'offline: the designer must preview on the speakers');
delete(sp);

% The main window's Design… button opens its own designer with the session
% controls hidden, and must put it on the same rig the same way.
lch.setSource('mabr');
sp = stimgen.StimPlayer();
sp.set_control_visibility(All=false);
[routed,note] = mabr.ui.App.putDesignerOnRig(sp,'mabr',audio,[]);
assert(routed && sp.PlaybackOutput == "Hardware", ...
    'Design: Play must reach the rig, not the speakers (%s)',note);
assert(sp.Fs == 48000,'Design: the designer must be at the rig''s sample rate (got %g)',sp.Fs);
assert(sp.CaptureAdapter() == lch.resolveAdapter(), ...
    'Design: the designer must share the launcher''s adapter (one owner per device)');
vis = sp.ControlVisibility;
assert(vis.Output,'Design: a routed designer must show its Output dropdown');
assert(~vis.Run && ~vis.ISI && ~vis.Reps && ~vis.SampleRate, ...
    'Design: the session controls MABR owns must stay hidden');
delete(sp);

testing = audio; testing.Testing = true;
for c = {{'mabr',testing,'Test Mode'},{'offline',audio,'Offline'}}
    sp = stimgen.StimPlayer();
    sp.set_control_visibility(All=false);
    [routed,note] = mabr.ui.App.putDesignerOnRig(sp,c{1}{1},c{1}{2},[]);
    assert(~routed && sp.PlaybackOutput == "Speakers" && isempty(sp.CaptureAdapter), ...
        'Design, %s: the designer must stay on the speakers',c{1}{3});
    assert(contains(note,c{1}{3}),'Design, %s: the status must say why (%s)',c{1}{3},note);
    vis = sp.ControlVisibility;
    assert(~vis.Output,'Design, %s: with one output there is no dropdown to show',c{1}{3});
    delete(sp);
end
lch.setSource('offline');

g1 = lch.openCalibration();
assert(~isempty(g1) && isvalid(g1),'the calibration window must open (offline is fine)');
g2 = lch.openCalibration();
assert(g1 == g2,'a second press must raise the calibration window, not open another');
delete(g1);
fprintf('  C: designer and calibration\n');

% An inspector reads a stimulus out of a .mat, no hardware.
tmp = tempname; mkdir(tmp);
cleanTmp = onCleanup(@() rmdir(tmp,'s')); %#ok<NASGU>
t = stimgen.Tone; t.Frequency = 4000; t.Duration = 0.02; t.update_signal;
tone = t.toStruct(); %#ok<NASGU>
file = fullfile(tmp,'tone.mat');
save(file,'tone');
items = mabr.ui.StimgenLauncher.loadStimuli(file);
assert(numel(items) == 1 && isa(items(1).Stim,'stimgen.StimType'), ...
    'loadStimuli must find the stimulus in a .mat');
n = lch.openInspector(file);
assert(n == 1,'the inspector should have opened one window');
assert(isequal(lch.recentFiles(),{file}),'a file that was opened must join the recent list');
assert(isempty(mabr.ui.StimgenLauncher.loadStimuli(save_empty(tmp))),'a .mat with no stimulus must yield none');
fprintf('  C: inspector\n');

% ---- Part D: a calibration that has gone ---------------------------------
gone = fullfile(tmp,'not_there.esgc');
l2 = mabr.ui.StimgenLauncher(AudioFcn=@() audio,Show=false, ...
    Settings=struct('Source','offline','CalibrationFile',gone));
cleanL2 = onCleanup(@() delete(l2)); %#ok<NASGU>
assert(isempty(l2.Settings.CalibrationFile) && strcmp(l2.describeCalibration(),'none loaded'), ...
    'a remembered calibration that has moved must be dropped, not fatal');
assert(~l2.loadCalibration(gone),'loading a missing calibration must report failure, not throw');
fprintf('  D: missing calibration\n');

fprintf('verify_stimgen_launcher: PASS\n');
end

% -------------------------------------------------------------------------
function f = save_empty(folder)
x = 1; %#ok<NASGU>
f = fullfile(folder,'empty.mat');
save(f,'x');
end

function close_new(before)
now = findall(groot,'Type','figure');
for f = now(:).'
    if ~any(f == before)
        try, delete(f); catch, end
    end
end
end

function s = save_prefs(names)
s = struct('name',{},'value',{});
for i = 1:numel(names)
    if ispref('MABR',names{i})
        s(end+1) = struct('name',names{i},'value',getpref('MABR',names{i})); %#ok<AGROW>
    end
end
end

function restore_prefs(names,s)
had = {s.name};
for i = 1:numel(had)
    setpref('MABR',had{i},s(i).value);
end
for i = 1:numel(names)
    if ~any(strcmp(names{i},had)) && ispref('MABR',names{i})
        rmpref('MABR',names{i});
    end
end
end

function clear_prefs(names)
for i = 1:numel(names)
    if ispref('MABR',names{i}), rmpref('MABR',names{i}); end
end
end
