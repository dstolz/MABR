function make_wiki_shots(which)
% make_wiki_shots          - regenerate every wiki screenshot of the acquisition GUI
% make_wiki_shots("main")  - just the main window and its dialogs
% make_wiki_shots("views") - just the viewer windows
%
% Writes PNGs into docs/tools/out/ (gitignored). Copy what changed into the
% wiki clone's images/ folder; the wiki is a separate repository
% (github.com/dstolz/MABR.wiki) and nothing here writes to it. The image
% names are the ones the wiki pages embed.
%
% RUN IT IN A SEPARATE MATLAB WITH ITS OWN PREFERENCES FOLDER. The main
% window restores the last session from MATLAB prefs and writes them back on
% close, and this script sets them freely, so it refuses to run against the
% real preferences. From PowerShell in the MABR folder:
%
%   $env:MATLAB_PREFDIR = "$env:TEMP\mabr_wiki_prefs"; mkdir -Force $env:MATLAB_PREFDIR
%   matlab -batch "cd('$PWD\docs\tools'); make_wiki_shots"
%
% (cmd: set MATLAB_PREFDIR=%TEMP%\mabr_wiki_prefs, then the same with
% %CD% for $PWD.) The cd is inside the batch command rather than -sd because
% a startup.m may change folder after -sd has. The folder's MABR pref group
% is cleared at the start, so each run begins from a fresh install's
% defaults.
%
% Nothing here touches hardware, a parallel pool, or the ring buffer, so it
% is safe beside a MATLAB that is acquiring:
%   - every viewer is fed synthetic data -- mabrtest.SyntheticABR's response
%     shape (waves I-V growing with level), band-limited noise, and a
%     mabrtest.FakeController walking a real mabr.stim.Schedule;
%   - the stimulus bank is a stimgen tone bank (4/8/16 kHz x 20-80 dB)
%     carrying an illustrative tone calibration, so it reads "calibrated";
%   - device enumeration is shimmed (audioPlayerRecorder, getAudioDevices
%     and asiosettings are shadowed by stubs written to a temp folder for the
%     run, and removed afterwards), because opening the audio settings
%     dialog lists ASIO devices, and an ASIO driver has one owner. The stubs
%     are written at run time rather than kept in the tree because MABR.m
%     puts every subfolder on the path, where they would shadow the real
%     device in a real session.
% uifigures are captured with exportapp; the classic figures (live plot,
% online analysis, trace organizer and inspector) with getframe.
%
% Requires the stimgen submodule. Takes about three minutes.
%
% Daniel Stolzberg (c) 2026

arguments
    which (1,1) string {mustBeMember(which,["all" "main" "views"])} = "all"
end

pd = getenv('MATLAB_PREFDIR');
assert(~isempty(pd) && strcmpi(strip(prefdir,'right',filesep),strip(pd,'right',filesep)), ...
    ['make_wiki_shots must run in a MATLAB started with MATLAB_PREFDIR set ' ...
     'to a folder of its own (prefdir is %s). See help make_wiki_shots.'],prefdir);
if ispref('MABR'), rmpref('MABR'); end

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
p = split(string(genpath(root)),pathsep); p(p==""|contains(p,'.git'))=[];
addpath(char(join(p,pathsep)));
addpath(fullfile(root,'tests'));

assert(mabr.stim.stimgenAvailable(),'make_wiki_shots needs the stimgen submodule.');
tmp = tempname;
mkdir(tmp);
writeShims(tmp);
addpath(tmp);                                    % in front of everything
cleanup = onCleanup(@() dropShims(tmp)); %#ok<NASGU>

mabr.log.configure();
warning('off','all');

out = fullfile(here,'out');
if ~isfolder(out), mkdir(out); end

cfg = mabr.Config;
bankFile = makeBank(tmp);

if any(which == ["all" "main"]),    shotsMain(out,bankFile);          end
if any(which == ["all" "views"]),   shotsViewers(out,bankFile,cfg);   end

fprintf('\nWrote:\n');
d = dir(fullfile(out,'*.png'));
for k = 1:numel(d), fprintf('  %-34s %6.0f kB\n',d(k).name,d(k).bytes/1024); end
end

% ======================================================================
function writeShims(d)
% Stubs standing in for the audio device for the length of the run.
put(d,'audioPlayerRecorder.m',{ ...
    'function obj = audioPlayerRecorder(varargin)'
    '% make_wiki_shots stub: never construct a real device object.'
    'obj = struct(''ShimDevice'',true);'
    'end'});
put(d,'getAudioDevices.m',{ ...
    'function names = getAudioDevices(~)'
    '% make_wiki_shots stub: a plausible device list.'
    'names = {''Focusrite USB ASIO'',''ASIO4ALL v2''};'
    'end'});
put(d,'asiosettings.m',{ ...
    'function asiosettings(varargin)'
    'end'});

% WORKAROUND, remove once fixed: mabr.stim.fromStimgen asserts on
% StimType.IsMultiObj, which stimgen removed (79320f7, "remove dead
% stimulus-side code"), so no stimgen bank imports at that pin. Shadow a copy
% that checks the property exists first -- only while the mismatch exists.
src = fileread(which('mabr.stim.fromStimgen'));
old = 'assert(~stimObj.IsMultiObj,';
if contains(src,old) && ~any(strcmp(properties('stimgen.Tone'),'IsMultiObj'))
    pd = fullfile(d,'+mabr','+stim');
    mkdir(pd);
    src = strrep(src,old,'assert(~(isprop(stimObj,''IsMultiObj'') && stimObj.IsMultiObj),');
    fid = fopen(fullfile(pd,'fromStimgen.m'),'w','n','UTF-8');
    fwrite(fid,src,'char'); fclose(fid);
    fprintf('  (patched copy of mabr.stim.fromStimgen in use: stimgen has no IsMultiObj)\n');
end
end

function put(d,name,lines)
fid = fopen(fullfile(d,name),'w');
fprintf(fid,'%s\n',lines{:});
fclose(fid);
end

function dropShims(d)
rmpath(d);
try rmdir(d,'s'); catch, end
end

% ======================================================================
function bankFile = makeBank(d)
% A calibrated stimgen tone bank: 4/8/16 kHz x 20..80 dB, 5 ms pips.
% The calibration is an illustrative tone LUT (an imaginary rig).
bankFile = fullfile(d,'ABR_tones.spl');
calS = struct('version',2, ...
    'CalibrationData',struct('tone',struct( ...
        'frequency',[1000 2000 4000 8000 16000 32000], ...
        'voltage',  [0.10 0.08 0.20 0.12 0.05 0.25])), ...
    'MicSensitivity',0.03,'NormativeValue',80, ...
    'CalibrationTimestamp',datetime(2026,10,6,9,12,40));
cal = stimgen.StimCalibration.loadobj(calS);
t = stimgen.Tone;
t.Frequency   = [4000 8000 16000];
t.SoundLevel  = 20:10:80;
t.Duration    = 0.005;
t.DisplayName = "pip";
t.Calibration = cal;
sp = stimgen.StimPlay(t);
sp.Reps = 512;
sp.Name = "ABR tones";
bank = struct('ISI',[1 1],'SelectionType',"Serial",'NItems',1, ...
              'Items',{{sp.toStruct}});
save(bankFile,'-struct','bank','-v7');
end

% ======================================================================
function shotsMain(out,bankFile)
fprintf('=== main window ===\n');
if ispref('MABR','LastSession'), rmpref('MABR','LastSession'); end
% Histories as a rig would have them, so the dropdowns read like one.
setpref('MABR','History_Subject',{'SUBJ-ID-1254','SUBJ-ID-1253','SUBJ-ID-1249'});
setpref('MABR','History_Output',{'D:\ABR\NoiseExposure\2026','D:\ABR\Pilot'});
setpref('MABR',mabr.stim.BankHistory.PrefName,{bankFile});
setpref('MABR','CollapsedPanels',{});
setpref('MABR','AudioTesting',true);
setpref('MABR','AudioStimulationOnly',false);

app = mabr.ui.App();
f = appFig();
f.Position(1:2) = [60 60];

% Bank: pick the listed file, which loads it.
dd = findDrop(f,'(no bank loaded)');
pick(dd,bankFile);
settle(1);
assert(~isempty(app.Stimuli) && app.Stimuli.numStimuli > 0, ...
    'The bank did not load -- see the main window''s status line.');
% Order: Frequency as listed, then Level descending.
byRow = @(item) sortByRow(findall(f,'Type','uidropdown', ...
    '-function',@(h) any(strcmp(h.Items,item))));
O = byRow('Bank order');  setItem(O(1),'Frequency');  settle;
O = byRow('Bank order');  setItem(O(2),'Level');      settle;
Dd = byRow('As listed');  setItem(Dd(1),'As listed'); settle;
Dd = byRow('As listed');  setItem(Dd(2),'Descending'); settle;
% Advance on correlation; artifacts by voltage, made up.
setItemAny(f,'All Repetitions','Correlation Threshold'); settle;
setItemAny(f,'None — keep every sweep','Voltage threshold'); settle;
cb = findall(f,'Type','uicheckbox','-function',@(h) contains(h.Text,'Repeat sweeps'));
if ~isempty(cb), cb.Value = true; fire(cb,'ValueChangedFcn',struct('Value',true,'PreviousValue',false)); end
settle(1);
snap(f,fullfile(out,'main-window.png'));

% --- dialogs opened from the window ---------------------------------
modal(@() fire(findBtn(f,'Per stimulus'),'ButtonPushedFcn',[]), ...
      'Repetitions',fullfile(out,'repetitions-dialog.png'));
modal(@() fire(findBtn(f,'Filters'),'ButtonPushedFcn',[]), ...
      'Display Filters',fullfile(out,'filter-dialog.png'));
modal(@() fire(findMenu(f,'Session Folders'),'MenuSelectedFcn',[]), ...
      'Session Folders',fullfile(out,'folder-scheme.png'));
modal(@() fire(findMenu(f,'Audio Device'),'MenuSelectedFcn',[]), ...
      'Audio Device (ASIO)',fullfile(out,'audio-settings-testmode.png'));

% Audio dialog as a rig would have it: Test Mode off, a device chosen.
a = app.Audio; a.Testing = false; a.Device = 'Focusrite USB ASIO';
a.PlayerChannels = [1 2]; a.RecorderChannels = [1 2]; a.MicChannel = 3;
a.AmplifierGain = 10000;
modal(@() mabr.ui.AudioSettingsDialog(a,app.Config,[]), ...
      'Audio Device (ASIO)',fullfile(out,'audio-settings.png'));
a.InputFullScale = 0.354; a.OutputFullScale = 1.41;
try a.InputCalibrated = datetime(2026,10,6,9,40,0); catch, end
try a.OutputCalibrated = datetime(2026,9,29,15,2,0); catch, end
modal(@() mabr.ui.InputCalibrationDialog(a,app.Config,[]), ...
      'Input Calibration',fullfile(out,'input-calibration.png'));

% stimgen tools launcher (non-modal)
try
    before = allFigs();
    fire(findMenu(f,'stimgen Tools'),'MenuSelectedFcn',[]);
    settle(2);
    g = newFig(before);
    if ~isempty(g), snap(g,fullfile(out,'stimgen-tools.png')); delete(g); end
catch me, fprintf('  stimgen tools: %s\n',me.message);
end

% Folded panels: their titles carry the settings.
names = {'Session','Stimulus','Acquisition'};
try
    delete(app); settle(1);
    base = getpref('MABR','LastSession');
    c = base; c.CollapsedPanels = names;
    setpref('MABR','LastSession',c);
    app = mabr.ui.App(); f = appFig(); f.Position(1:2) = [60 60]; settle(1.5);
    snap(f,fullfile(out,'main-window-folded.png'));
catch me, fprintf('  folded: %s\n',me.message);
end

% Stimulation only: the Acquisition panel greys out as a unit.
try
    delete(app); settle(1);
    c = base; c.CollapsedPanels = {};
    c.Audio.Testing = false; c.Audio.StimulationOnly = true;
    c.Audio.Device = 'Focusrite USB ASIO';
    setpref('MABR','LastSession',c);
    setpref('MABR','CollapsedPanels',{});
    if ispref('MABR','WindowPos_MABR'), rmpref('MABR','WindowPos_MABR'); end
    app = mabr.ui.App(); f = appFig(); f.Position(1:2) = [60 60]; settle(1.5);
    snap(f,fullfile(out,'main-window-stimonly.png'));
catch me, fprintf('  stim only: %s\n',me.message);
end
setpref('MABR','AudioTesting',true);
setpref('MABR','AudioStimulationOnly',false);
delete(app);
end

% ======================================================================
function shotsViewers(out,bankFile,cfg)
fprintf('=== viewers ===\n');
bank = mabr.stim.StimulusSet.fromFile(bankFile,cfg);
n   = bank.numStimuli;
V   = zeros(n,2); ids = cell(1,n);
for i = 1:n
    m = bank.meta(i); V(i,:) = [m.Frequency m.Level]; ids{i} = m.ID;
end
truth = mabrtest.SyntheticABR.defaults();
rs = RandStream('threefry','Seed',20261007);

% --- Stimulus viewer ---------------------------------------------------
try
    sv = mabr.ui.StimulusViewer(bank);
    settle(1);
    lb = findall(sv.Figure,'Type','uilistbox');
    if ~isempty(lb)
        it = lb(1).ItemsData; if isempty(it), it = lb(1).Items; end
        sel = find(V(:,1) == 8 & ismember(V(:,2),[40 60 80]));
        lb(1).Value = it(sel);
        fire(lb(1),'ValueChangedFcn',struct('Value',{it(sel)}));
    end
    settle(1);
    snap(sv.Figure,fullfile(out,'stimulus-viewer.png'));
    delete(sv);
catch me, fprintf('  stimulus viewer: %s\n',me.message);
end

% --- Live plot ---------------------------------------------------------
Fs = 12000;
t  = (-120:120)/Fs;                         % s, -10..10 ms
nPer = 240; sweepSD = 3e-6;
M = zeros(n,numel(t)); SD = M; cnt = zeros(n,3);
for c = 1:n
    Y = sweeps(t*1000,V(c,2),V(c,1),truth,nPer,sweepSD,rs);
    M(c,:) = mean(Y,1); SD(c,:) = std(Y,0,1);
    rej = randi(rs,[0 4]);
    cnt(c,:) = [nPer nPer+rej rej];
    if c == n, latest = Y(end,:); end
end
stats = struct('RunId',1,'Time',t,'NumSamples',numel(t),'Latest',latest, ...
    'LatestBad',false,'LatestStim',n,'Corr',0.31,'NumSweeps',sum(cnt(:,2)), ...
    'NumClean',sum(cnt(:,1)),'NumArtifacts',sum(cnt(:,3)),'Stimuli',1:n, ...
    'Mean',M,'SD',SD,'CondCounts',cnt);
info = struct('Stimuli',1:n,'Labels',{ids}, ...
    'Params',struct('Names',{{'Frequency','Level'}},'Values',V, ...
        'Units',{{'kHz','dB'}},'Varying',[true true]), ...
    'target',512*n);
try
    lp = mabr.ui.LivePlot();
    lp.Figure.Position = [40 40 1180 780];
    try lp.setFilterText('10–3000 Hz + 60 Hz notch'); catch, end
    lp.updateStats(stats,info);
    lp.Layout = 'grid'; lp.ErrorBand = 'sem'; lp.AmpMode = 'common';
    lp.updateStats(stats,info); settle(1);
    snap(lp.Figure,fullfile(out,'live-plot.png'));
    lp.Layout = 'stacked'; lp.updateStats(stats,info); settle(1);
    snap(lp.Figure,fullfile(out,'live-plot-stacked.png'));
    delete(lp);
catch me, fprintf('  live plot: %s\n',me.message);
end

% --- finalized blocks: online analysis + trace organizer ------------------
blocks = mabr.data.Block.empty;
for c = 1:n
    blocks(c) = makeBlock(V(c,1),V(c,2),ids{c},truth,400,sweepSD,rs);
end
try
    mp = mabr.ui.MetricPlot();
    mp.UpdateInterval = 60;
    mp.Figure.Position = [60 60 820 560];
    mp.Metric = 'p2p'; mp.Window = [1 7];
    mp.XParam = 'Level'; mp.SeriesParam = 'Frequency';
    try mp.Style.Legend = 'southeast'; catch, end
    for c = 1:n, mp.addBlock(blocks(c)); end
    try mp.render(true); catch, end
    settle(1.5);
    snap(mp.Figure,fullfile(out,'online-analysis.png'));
    delete(mp);
catch me, fprintf('  metric plot: %s\n',me.message);
end
try
    to = mabr.ui.TraceOrganizer();
    for c = 1:n, to.addBlock(blocks(c)); end
    if isempty(to.Figure) || ~isgraphics(to.Figure), to.show(); end
    fh = to.Figure; fh.Position = [60 60 1000 720];
    to.SplitBy = 'Frequency';
    to.setOrder('Level','descending');
    to.LabelBy = 'params';
    settle(1.5);
    snap(to.Figure,fullfile(out,'trace-organizer.png'));
    delete(to);
catch me, fprintf('  trace organizer: %s\n',me.message);
end

% --- Trace inspector ---------------------------------------------------
try
    tt = (0:119)'/Fs;
    y  = mean(sweeps(tt'*1000,70,8,truth,600,sweepSD,rs),1)';
    tr = mabr.ui.Trace(y,tt,'8 kHz, 70 dB','Tone_8kHz_70dB');
    tr.Color = [0 0.4 0.8];
    before = allFigs();
    insp = mabr.ui.TraceInspector(tr);
    settle(1.5);
    snap(insp.Figure,fullfile(out,'trace-inspector.png'));
    insp.showMatrices(); settle(1.5);
    g = newFig([before; insp.Figure]);
    if ~isempty(g), snap(g(1),fullfile(out,'trace-inspector-compare.png')); end
    delete(insp);
catch me, fprintf('  trace inspector: %s\n',me.message);
end

% --- Progress monitor + presentation order (a conventional plan mid-way) -
try
    sch = mabr.stim.Schedule(bank,cfg);
    sch.Strategy = 'conventional';
    sch.Repetitions = 512;
    sch.OrderBy = {'Frequency','Level'};
    sch.OrderDirection = {'listed','descending'};
    sch.build();
    fc = mabrtest.FakeController(sch,bank);
    pm = mabr.ui.ProgressMonitor(); pm.MinInterval = 0;
    pm.listenTo(fc);
    po = mabr.ui.PresentationOrder(); po.MinInterval = 0;
    po.listenTo(fc);
    nDone = 9;
    for k = 1:nDone
        fc.setState(mabr.ui.ProgState.PrepBlock);
        fc.setState(mabr.ui.ProgState.Acquire);
        fc.metrics(512,randi(rs,[0 3]));
        sch.recordRun(k,accumarray(sch.Runs{k}(:),1,[n 1]).');
        fc.setState(mabr.ui.ProgState.BlockComplete);
        sch.advance();
    end
    % switch one upcoming condition off, to show what that looks like
    off = find(V(:,1) == 16 & V(:,2) == 20);
    sch.setEnabled(off,false);
    fc.setState(mabr.ui.ProgState.PrepBlock);
    fc.setState(mabr.ui.ProgState.Acquire);
    fc.metrics(318,2);
    pm.refresh(true); settle(1);
    snap(pm.Figure,fullfile(out,'progress-monitor.png'));
    pm.View = 'heatmap'; pm.refresh(true); settle(1);
    snap(pm.Figure,fullfile(out,'progress-monitor-heatmap.png'));
    try po.refresh(true); catch, end
    po.Figure.Position(3:4) = [1100 560];
    settle(1.5);
    snap(po.Figure,fullfile(out,'presentation-order.png'));
    delete(pm); delete(po);
catch me, fprintf('  progress/order: %s\n%s\n',me.message,me.getReport);
end

% --- Input spectrum -----------------------------------------------------
try
    fsS = 192000; dur = 6; ts = (0:dur*fsS-1)'/fsS;
    x = 1.2e-6*randn(rs,numel(ts),1);
    [b,a] = butter(2,[20 8000]/(fsS/2));
    x = filter(b,a,x)*3;
    hum = [60 180 300 420]; amp = [9 3 1.6 0.8]*1e-6;
    for k = 1:numel(hum), x = x + amp(k)*sin(2*pi*hum(k)*ts + k); end
    x = x + 1.1e-6*sin(2*pi*7812.5*ts);              % a switching supply
    S0 = struct('Samples',single(x),'Head',numel(x),'Seq',1,'SampleRate',fsS, ...
        'Gain',1,'Source','monitor','Testing',false,'Monitoring',true,'Note','');
    spv = mabr.ui.SpectrumViewer('SourceFcn',@(m) clip(S0,m), ...
        'MonitorFcn',@(tf) deal(true,''),'AutoRefresh',false);
    spv.refresh(); settle(1); spv.refresh(); settle(1);
    snap(spv.Figure,fullfile(out,'input-spectrum.png'));
    delete(spv);
catch me, fprintf('  spectrum: %s\n',me.message);
end

% --- Notes ------------------------------------------------------------
try
    store = mabr.data.SessionNotes();
    store.add('impedance 2.8 k / 3.1 k, ground 1.9 k');
    store.add('ear bar left, speaker 10 cm from the right pinna');
    store.ContextFcn = @() struct('Run',4,'NumRuns',21,'Sweep',212);
    store.add('animal twitched, a few sweeps rejected');
    store.ContextFcn = @() struct('Run',9,'NumRuns',21,'Sweep',57);
    store.add('re-seated ear plug');
    store.ContextFcn = [];
    nv = mabr.ui.Notes(store);
    settle(1);
    snap(nv.Figure,fullfile(out,'notes.png'));
    delete(nv);
catch me, fprintf('  notes: %s\n',me.message);
end

% --- Test runner (the list only; nothing is run) ---------------------------
try
    tr2 = mabr.ui.TestRunner();
    settle(2);
    snap(tr2.UIFigure,fullfile(out,'test-runner.png'));
    delete(tr2);
catch me, fprintf('  test runner: %s\n',me.message);
end
end

% ======================================================================
function S = clip(S,m)
m = min(m,numel(S.Samples));
S.Samples = S.Samples(end-m+1:end);
end

function Y = sweeps(tMs,level,freq,truth,nSw,sd,rs)
% nSw single sweeps of the synthetic response, each with its own gain and
% band-limited noise (300-3000 Hz at 12 kHz).
y0 = mabrtest.SyntheticABR.template(tMs(:),level,freq,truth)';
[b,a] = butter(2,[300 3000]/6000);
N = numel(tMs);
E = filter(b,a,randn(rs,nSw,N+200),[],2);
E = E(:,201:end); E = sd*E/std(E(:));
g = 1 + 0.2*randn(rs,nSw,1);
Y = g.*y0 + E;
end

function blk = makeBlock(f,L,id,truth,nSw,sd,rs)
Fs = 12000; sweepLen = 120; period = 292;
tMs = (0:sweepLen-1)/Fs*1000;
Y = sweeps(tMs,L,f,truth,nSw,sd,rs);
Nn = 50 + nSw*period + period;
[b,a] = butter(2,[300 3000]/6000);
data = filter(b,a,randn(rs,Nn,1)); data = sd*data/std(data);
onsets = (50 + (0:nSw-1)*period)';
for i = 1:nSw
    data(onsets(i)+(0:sweepLen-1)) = Y(i,:)';
end
rec  = mabr.data.Recording(Fs,data,onsets,sweepLen,1);
meta = struct('ID',id,'Frequency',f,'Level',L,'alternatePolarity',true, ...
    'informativeParams',{{'Frequency','Level'}},'Label',{{['ID = ' id]}});
blk  = mabr.data.Block(struct('Meta',meta,'SampleRate',192000),rec);
end

% ---- capture ---------------------------------------------------------
function snap(f,file)
drawnow; pause(0.3); drawnow;
try
    exportapp(f,file);
catch
    fr = getframe(f);
    imwrite(fr.cdata,file);
end
fprintf('  %s\n',file);
end

function modal(trigger,name,file)
tm = timer('StartDelay',3,'TimerFcn',@(~,~) grab(name,file));
start(tm);
try
    trigger();
catch me
    % grab() closes the dialog to end its uiwait, and a dialog that reads
    % its controls after uiwait then finds them gone. That is expected.
    if ~contains(me.message,'Invalid or deleted')
        fprintf('  %s: %s\n',name,me.message);
    end
end
stop(tm); delete(tm);
settle(0.5);
end

function grab(name,file)
f = findall(groot,'Type','figure','Name',name);
if isempty(f), fprintf('  no window "%s"\n',name); return; end
f = f(1);
try snap(f,file); catch me, fprintf('  snap %s: %s\n',name,me.message); end
b = findall(f,'Type','uibutton','-function',@(h) any(strcmp(h.Text,{'Cancel','Close'})));
if ~isempty(b) && strcmp(b(1).Enable,'on')
    try fire(b(1),'ButtonPushedFcn',[]); catch, end
end
if isvalid(f), delete(f); end
end

function settle(s)
if nargin < 1, s = 0.3; end
drawnow; pause(s); drawnow;
end

function f = appFig()
f = findall(groot,'Type','figure','Tag',mabr.ui.App.InstanceTag);
f = f(1);
end

function F = allFigs()
F = findall(groot,'Type','figure');
end

function g = newFig(before)
F = allFigs();
g = F(~ismember(F,before));
end

function fire(h,prop,evt)
cb = h.(prop);
if isempty(cb), return; end
if isempty(evt), evt = struct('Source',h); end
if iscell(cb)
    feval(cb{1},h,evt,cb{2:end});
else
    cb(h,evt);
end
end

function b = findBtn(f,txt)
b = findall(f,'Type','uibutton','-function',@(h) startsWith(string(h.Text),txt));
b = b(1);
end

function m = findMenu(f,txt)
m = findall(f,'Type','uimenu','-function',@(h) startsWith(string(h.Text),txt));
m = m(1);
end

function d = findDrop(f,item)
d = findall(f,'Type','uidropdown','-function',@(h) any(strcmp(h.Items,item)));
d = d(1);
end

function pick(d,value)
old = d.Value;
d.Value = value;
fire(d,'ValueChangedFcn',struct('Source',d,'Value',value,'PreviousValue',old));
end

function setItem(d,itemText)
k = find(strcmp(d.Items,itemText),1);
if isempty(k), fprintf('  no item "%s"\n',itemText); return; end
v = d.ItemsData;
if isempty(v), v = d.Items{k};
elseif iscell(v), v = v{k};
else, v = v(k);
end
pick(d,v);
end

function D = sortByRow(D)
r = arrayfun(@(h) h.Layout.Row,D);
[~,i] = sort(r); D = D(i);
end

function setItemAny(f,hasItem,itemText)
% Match the item text ignoring dash style.
norm = @(s) regexprep(string(s),'[—–-]+','-');
D = findall(f,'Type','uidropdown');
for k = 1:numel(D)
    if any(norm(D(k).Items) == norm(hasItem))
        i = find(norm(D(k).Items) == norm(itemText),1);
        if ~isempty(i), setItem(D(k),D(k).Items{i}); return; end
    end
end
fprintf('  could not set "%s"\n',itemText);
end
