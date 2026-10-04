function verify_offline_session()
% verify_offline_session  mabr.analysis.Session (part A) on synthetic files: pools, keys, modes, windowed processing, atomic steps, results v2.
%
%   mabr.analysis.Session is where a folder of .abr files becomes conditions,
%   and every later number rests on that being right: which files are read,
%   which sweeps belong to which condition, and what samples each sweep holds.
%   Every claim below is held against files mabrtest.SyntheticABR wrote, so
%   the truth is known rather than eyeballed.
%
%   Part A  the small classes: Progress's explicit sink (when it is called,
%           that a throw cancels and the destructor stays quiet), Filter's
%           describe() of an undesigned band (defect 12), corners6dB, the
%           windowed operator (linear, padded, skipped when too short), and
%           Plot.audiogram's labels, linear axis and skipped NaN frequency
%   Part B  pools: two sibling folders of one subject read as "a + b", a file
%           copied into both read once (duplicate of ...), Exclude, the data
%           fingerprint, and two subjects refused unless Force
%   Part C  a folder mixing tones and clicks, both run layouts, in the CURRENT
%           and the OLD naming (the old one crashed segment with badsubscript,
%           the current one silently pooled clicks with tones): ParamNames
%           is the union (defect 7), clicks have Frequency NaN and their own
%           keys, no condition mixes stimuli, and grid, varyingParams,
%           thresholdRow, plotStack, conditionLabel and seriesLabel are NaN-safe
%           (defect 13)
%   Part D  acquisition modes: conventional and interleaved runs are separate
%           conditions (continuous vs windowed, Extent [0 9.917]) unless
%           PoolAcqModes, and separate series even under a typed GroupBy
%           that leaves AcqMode out (pooled, it is not added); with the
%           filters off every compact sweep is its OWN window of its file,
%           detrended, and nothing else (defect 14)
%   Part E  the windowed operator's acceptance: on continuous data, the raw
%           0-L windows averaged and passed through applyWindowed put waves
%           II-V where the whole-trace FIR average does (within one sample,
%           P-N within 10%); wave I is printed, not asserted
%   Part F  per-condition seeds: a subset re-test is bit-identical to the full
%           one, and two conditions of equal N no longer share sign flips
%           (defect 20)
%   Part G  atomic steps: a progress sink throwing mabr:analysis:cancelled
%           inside parse, segment, reject, detect and estimateThresholds
%           leaves the session exactly as it was
%   Part H  results v2: a 54-condition session saved without sweeps is under
%           2 MB, reloads results-only with every per-sweep column rebuilt and
%           conditionMean within 1e-6; with sweeps it reloads whole; saving
%           adds no row to Messages, in memory or in the file, however often
%           it is repeated (a "save" row an older MABR wrote is dropped), and
%           its note is printed under Verbose only; a hand-written v1 struct
%           loads; loadRaw is checked when it exists
%   Part I  defects 9 (an 11025 Hz file left out), 17 (a Test Mode file left
%           out), 10 (movmedian/movmean refused), 15 (uncalibrated levels are
%           labelled dB, not dB SPL), and Messages kept with Verbose false
%           while nothing is printed
%   Part J  rejection (rig, criterion and their reasons; Keep; the legacy
%           path), the sweep cap (balanced, Excess not Rejected),
%           UnitOverride, and the access helpers
%   Part K  no part-B method is left a stub (verify_offline_analyze checks them)
%   Part L  static scan: no Statistics Toolbox call in Session, Filter, Plot
%           or Progress, and requiredFilesAndProducts lists only MATLAB and
%           the Signal Processing Toolbox for every +mabr/+analysis file (no
%           Parallel Computing Toolbox)
%   Part M  hand decisions (ManualRejections, DetectionOverrides, brought in
%           by a results struct) applied last by reject/clearRejected/detect;
%           a subset re-segment equals the full one and a new window refuses;
%           run groups split on a pause after a file ENDS, not start to start
%   Part N  non-finite samples (NaN/Inf) in a continuous and a compact file
%           cost the sweeps they reach -- the kept ones the clean session's,
%           bit for bit -- name the files in a warning, and the session still
%           analyses
%
%   Everything is written under one tempname folder removed on the way out;
%   figures are invisible and closed. No preference is read or written, no
%   pool is started, and the global random stream is never drawn from.
%
%   Run:  >> verify_offline_session
%
%   See also mabr.analysis.Session, mabr.analysis.Filter,
%   mabr.analysis.Progress, mabrtest.SyntheticABR, verify_analysis.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_session ==\n');
tAll  = tic;
rng0  = rng;
figs0 = findall(groot,'Type','figure');
root  = string(tempname);
mkdir(root);
cleanup = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(root));

truth = mabrtest.SyntheticABR.defaults();
Fs    = truth.Fs;
L     = truth.SweepLength;
small = truth;
small.Freqs = [4 16];  small.Threshold = [30 40];  small.Levels = 20:20:80;  small.nSweeps = 64;

% =========================================================================
%  Part A -- Progress, Filter, Plot
% =========================================================================
tp = tic;
rec = containers.Map('KeyType','char','ValueType','any');
rec('calls') = zeros(0,2);
rec('msg') = strings(0,1);
sink = @(m,c,t) recordCall(rec,m,c,t);
p = mabr.analysis.Progress(5,"probe",false,sink);
assert(isequal(rec('calls'),[0 5]) && rec('msg') == "probe", ...
    'The sink was not called once, with count 0, at construction.');
for k = 1:4, p.step(); end
assert(size(rec('calls'),1) == 1,'The sink was called again within 0.1 s.');
p.step();
c = rec('calls');
assert(size(c,1) == 2 && isequal(c(end,:),[5 5]),'The last step (count == total) was not reported.');
p.close();
delete(p);
assert(size(rec('calls'),1) == 2,'close/delete called the sink.');
p = mabr.analysis.Progress(10,"slow",false,sink);
n0 = size(rec('calls'),1);
pause(0.12);
p.step();
assert(size(rec('calls'),1) == n0 + 1,'A step 0.1 s after the last call was not reported.');
delete(p);
p = mabr.analysis.Progress(2,"cancel",false,@(m,c,t) cancelAt(c,2));
p.step();
id = "";
try
    p.step();
catch ME
    id = string(ME.identifier);
end
assert(id == "mabr:analysis:cancelled",'A throwing sink did not propagate out of step() (%s).',id);
delete(p);                                      % must not throw
id = "";
try
    mabr.analysis.Progress(1,"x",false,42);
catch ME
    id = string(ME.identifier);
end
assert(id == "mabr:analysis:Progress:sink",'A non-handle sink was accepted.');
out = evalc('q = mabr.analysis.Progress(3,"quiet",false,sink); q.step(3); q.close();');
assert(isempty(out),'A disabled Progress printed: "%s".',out);
assert(mabr.analysis.Progress.duration(119.7) == "2 m 00 s" && ...
    mabr.analysis.Progress.duration(59.97) == "1 m 00 s" && ...
    mabr.analysis.Progress.duration(3599.9) == "1 h 00 m", ...
    'Progress.duration rounds into "60" (e.g. "%s").',mabr.analysis.Progress.duration(119.7));

% Filter: describe() of an undesigned filter (defect 12), the -6 dB corners,
% and the windowed operator.
f0 = mabr.analysis.Filter();
d0 = f0.describe();
assert(contains(d0,"300-3000") && contains(d0,"undesigned"), ...
    'describe() of an undesigned Filter said "%s".',d0);
assert(mabr.analysis.Filter('HighPass',[],'LowPass',[]).describe() == "no filtering", ...
    'Both bands off is not "no filtering".');
f = f0.design(Fs);
[hp6,lp6] = f.corners6dB();
assert(hp6 > 200 && hp6 < 300 && lp6 > 3000 && lp6 < 4200, ...
    'corners6dB of the default FIR at 12 kHz: %.1f / %.1f Hz.',hp6,lp6);
gHP = 40*log10(abs(freqz(f.HighNum,f.HighDen,[hp6 hp6],Fs)));   % squared: as applied
gLP = 40*log10(abs(freqz(f.LowNum,f.LowDen,[lp6 lp6],Fs)));
assert(abs(gHP(1) + 6) < 0.05 && abs(gLP(1) + 6) < 0.05, ...
    'A section is not -6 dB at its corners6dB (%.3f / %.3f dB).',gHP(1),gLP(1));
[a,b] = mabr.analysis.Filter('HighPass',[]).design(Fs).corners6dB();
assert(isnan(a) && b > 3000,'A band that is off must give NaN.');

rs = RandStream('threefry','Seed',7);
X  = 1e-6*randn(rs,L,40) + linspace(0,2e-6,L).';
[Y,info] = f.applyWindowed(X);
assert(isequal(size(Y),size(X)) && isa(Y,'double'),'applyWindowed changed the shape.');
ym = f.applyWindowed(mean(X,2));
assert(max(abs(mean(Y,2) - ym)) < 1e-9*max(abs(ym)), ...
    'The windowed operator is not linear (filtering the average != averaging the filtered).');
P = min(L-1,max(12,ceil(5*sqrt(2)/(2*pi*hp6)*Fs)));
assert(info.Pad == P && info.Order == 2 && info.PadMode == "reflect" && ~info.Skipped ...
    && info.HP6 == hp6 && info.LP6 == lp6,'applyWindowed info is wrong.');
assert(startsWith(info.Description,"Butterworth order 2, -6 dB at ") && ...
    info.Description == f.describeWindowed(),'The windowed description is "%s".',info.Description);
[Yz,iz] = f.applyWindowed(X,PadMode="zeroleft");
assert(iz.PadMode == "zeroleft" && ~isequal(Yz,Y),'zeroleft padding made no difference.');
[Ys,is] = f.applyWindowed(X(1:3,:));
assert(is.Skipped && isequal(size(Ys),[3 40]),'A 3-sample window was not skipped.');
t  = (0:599).'/Fs;
mid = 150:450;
y1 = f.applyWindowed(sin(2*pi*1000*t));
y2 = f.applyWindowed(sin(2*pi*50*t));
g1 = sqrt(mean(y1(mid).^2))/sqrt(0.5);
g2 = sqrt(mean(y2(mid).^2))/sqrt(0.5);
assert(g1 > 0.9 && g2 < 0.1,'The windowed operator is not the band (1 kHz x%.2f, 50 Hz x%.2f).',g1,g2);

% Plot.audiogram: the defaults draw what they always drew; labels, a linear
% axis and a skipped NaN frequency are new.
fig = figure('Visible','off');
ax  = axes(fig);
mabr.analysis.Plot.audiogram([4 8 16],[30 20 40],Parent=ax);
assert(strcmp(ax.XLabel.String,'Frequency (kHz)') && strcmp(ax.YLabel.String,'Threshold (dB SPL)') ...
    && strcmp(ax.XScale,'log'),'audiogram defaults changed.');
clf(fig);
ax = axes(fig);
mabr.analysis.Plot.audiogram([4 NaN 16],[30 50 Inf],Parent=ax,YLabel="Threshold (dB)", ...
    CI=[25 45 NaN; 35 55 NaN]);
dashed = findall(ax,'Type','line','LineStyle','--');
assert(strcmp(ax.YLabel.String,'Threshold (dB)') && isequal(dashed.XData,[4 16]), ...
    'A NaN frequency was drawn, or YLabel was ignored.');
mabr.analysis.Plot.audiogram([1 2 3],[30 40 50],Parent=ax,XScale="linear",XLabel="Series");
assert(strcmp(ax.XScale,'linear') && strcmp(ax.XLabel.String,'Series'),'XScale/XLabel were ignored.');
clf(fig);
ax = axes(fig);
mabr.analysis.Plot.audiogram(NaN,40,Parent=ax,YLabel="Threshold (dB)");   % a click series alone
assert(isempty(findall(ax,'Type','line')) && strcmp(ax.YLabel.String,'Threshold (dB)'), ...
    'An audiogram with nothing drawable did not leave labelled, empty axes.');
close(fig);
fprintf(['  PASS Part A: Progress sink (count 0, last step, 0.1 s throttle, cancel propagates, ' ...
    'quiet destructor); Filter describe() undesigned, corners6dB %.0f-%.0f Hz, windowed operator ' ...
    '(linear, pad %d, zeroleft, skip); Plot.audiogram options (%.1f s)\n'],hp6,lp6,P,toc(tp));

% =========================================================================
%  Part B -- pools of folders
% =========================================================================
tp = tic;
Tp = truth;  Tp.Freqs = 8;  Tp.Threshold = 20;  Tp.Levels = [20 50 80];  Tp.nSweeps = 32;
pa = fullfile(root,"pool","SUBJ-ID-9001","a");
pb = fullfile(root,"pool","SUBJ-ID-9001","b");
ia = mabrtest.SyntheticABR.writeSession(pa,Tp,Start=datetime(2026,10,1,10,0,0));
mabrtest.SyntheticABR.writeSession(pb,Tp,Start=datetime(2026,10,1,11,0,0));
dup = string(ia.Files.FileName(1));
copyfile(fullfile(pa,dup),fullfile(pb,dup));

s = mabr.analysis.Session([pa;pb],Verbose=false);
assert(isequal(s.Paths,[pa;pb]) && s.Path == pa,'Paths are wrong.');
assert(s.Name == "a + b",'A pool of two folders is named "%s".',s.Name);
assert(s.Subject == "SUBJ-ID-9001",'Pool subject "%s".',s.Subject);
assert(height(s.Files) == 7 && sum(s.Files.Include) == 6,'The pool read %d files, %d included.', ...
    height(s.Files),sum(s.Files.Include));
k = find(s.Files.FileId == "b/" + dup);
assert(isscalar(k) && ~s.Files.Include(k) && s.Files.Reason(k) == "duplicate of a/" + dup ...
    && s.Files.DuplicateOf(k) == "a/" + dup,'The copied file was not left out as a duplicate.');
assert(numel(unique(s.Files.RunGroup(s.Files.Include))) == 2, ...
    'Two runs an hour apart should be two run groups.');
s.segment();
assert(s.NumConditions == 3 && all(s.Conditions.nFiles == 2) && all(s.Conditions.nSweeps == 64), ...
    'Pooled folders did not concatenate their conditions.');

% The fingerprint: every .abr of the folders, and the exclusions.
dd  = [dir(fullfile(pa,'*.abr')); dir(fullfile(pb,'*.abr'))];
ids = strings(numel(dd),1);
for i = 1:numel(dd)
    [~,fn] = fileparts(dd(i).folder);
    ids(i) = string(fn) + "/" + string(dd(i).name);
end
fp = mabr.analysis.Session.fingerprintOf(ids,[dd.bytes],[dd.datenum]);
assert(strlength(s.DataFingerprint) == 8 && fp == s.DataFingerprint, ...
    'fingerprintOf from a listing differs from the session''s.');
ex = "a/" + string(ia.Files.FileName(2));
sx = mabr.analysis.Session([pa;pb],Verbose=false,Exclude=ex);
assert(~sx.Files.Include(sx.Files.FileId == ex) && sx.Files.Reason(sx.Files.FileId == ex) == "excluded by user", ...
    'Exclude did not leave the file out.');
assert(sx.DataFingerprint ~= s.DataFingerprint && ...
    sx.DataFingerprint == mabr.analysis.Session.fingerprintOf(ids,[dd.bytes],[dd.datenum],ex), ...
    'The exclusions are not part of the fingerprint.');

% Two subjects: refused, unless forced.
Tq = Tp;  Tq.Levels = 80;
pc = fullfile(root,"subjects","SUBJ-ID-9001_x");
pd = fullfile(root,"subjects","SUBJ-ID-9002_y");
mabrtest.SyntheticABR.writeSession(pc,Tq,Subject="SUBJ-ID-9001");
mabrtest.SyntheticABR.writeSession(pd,Tq,Subject="SUBJ-ID-9002");
id = "";
try
    mabr.analysis.Session([pc;pd],Verbose=false);
catch ME
    id = string(ME.identifier);
end
assert(id == "mabr:analysis:Session:mixedSubjects",'Two subjects were pooled without Force (%s).',id);
s2 = mabr.analysis.Session([pc;pd],Verbose=false,Force=true);
assert(any(s2.Messages.Level == "warning" & contains(s2.Messages.Text,"different subjects")), ...
    'Forcing two subjects together said nothing.');
s3 = mabr.analysis.Session([pa;pb;pc],Verbose=false,Force=true);
assert(s3.Name == "a + b (+1)",'Three folders are named "%s".',s3.Name);
fprintf(['  PASS Part B: pool "a + b" (7 files, the copy left out as "duplicate of a/..."), ' ...
    'Exclude, fingerprintOf, mixed subjects refused unless Force (%.1f s)\n'],toc(tp));

% =========================================================================
%  Part C -- tones and clicks, both layouts, current and old names
% =========================================================================
tp = tic;
nL = numel(small.Levels);  nF = numel(small.Freqs);
for style = ["current","old"]
    fm = fullfile(root,"mixed_" + style,"SUBJ-ID-9001_261001T140000");
    mabrtest.SyntheticABR.writeSession(fm,small,Stimuli=["Tone","ClickTrain"],Layout="both",NamingStyle=style);
    s = mabr.analysis.Session(fm,Verbose=false);
    assert(isequal(s.ParamNames,["Stimulus","Level","Frequency"]), ...
        '%s: ParamNames are [%s].',style,strjoin(s.ParamNames,' '));
    assert(isequal(s.KeyParams,["Stimulus","AcqMode","Frequency","Level"]),'%s: KeyParams.',style);
    if style == "current"
        % The case that used to drop Frequency: the first file is a click.
        assert(s.Files.Stimulus(1) == "ClickTrain",'Expected a click file first in current naming.');
    end
    s.segment();
    C = s.Conditions;
    assert(height(C) == 2*nL*nF + nL,'%s: %d conditions.',style,height(C));
    click = C.Stimulus == "ClickTrain";
    assert(sum(click) == nL && all(isnan(C.Frequency(click))) && all(C.AcqMode(click) == "conventional") ...
        && ~any(contains(C.Key(click),"Frequency")),'%s: click conditions are wrong.',style);
    assert(numel(unique(C.Key)) == height(C),'%s: keys are not unique.',style);
    for r = 1:height(C)
        fr = unique(C.SweepFile{r});
        assert(all(s.Files.Stimulus(fr) == C.Stimulus(r)) && all(s.Files.AcqMode(fr) == C.AcqMode(r)) ...
            && all(s.Files.Level(fr) == C.Level(r)) ...
            && all(isequaln(s.Files.Frequency(fr),repmat(C.Frequency(r),numel(fr),1))), ...
            '%s: condition %s mixes files of different conditions.',style,C.Key(r));
    end
    assert(isequal(s.varyingParams(),["Stimulus","Level","Frequency"]),'%s: varyingParams.',style);
    [S,U,rv,cv] = s.grid("Level","Frequency",Where=struct('AcqMode',"conventional"));
    assert(isequal(size(S),[nL nF]) && isequal(rv.',small.Levels) && isequal(cv.',small.Freqs) ...
        && isequal(U.Stimulus,"Tone"),'%s: grid over a mixed folder is wrong.',style);
    S2 = s.grid("Level","Frequency");
    assert(size(S2{end,1},2) > size(S{end,1},2),'%s: grid did not fold both runs onto a tile.',style);
    ck = C.Key(find(C.Stimulus == "Tone" & C.AcqMode == "conventional" & C.Frequency == 4 ...
        & C.Level == 20,1));
    assert(s.conditionLabel(ck) == "Tone, 4 kHz, 20 dB · conventional", ...
        '%s: conditionLabel "%s".',style,s.conditionLabel(ck));
    kc = C.Key(find(click,1));
    assert(s.conditionLabel(kc) == "ClickTrain, 20 dB · conventional", ...
        '%s: click label "%s".',style,s.conditionLabel(kc));

    s.detect(Method="tmax",NumPermutations=50);
    s.estimateThresholds(Type="glm");
    T = s.Thresholds;
    assert(height(T) == 1 + 2*nF && isequal(s.GroupParams,["Stimulus","AcqMode","Frequency"]), ...
        '%s: %d threshold series.',style,height(T));
    rc = s.thresholdRow("Frequency",NaN);
    rt = s.thresholdRow("Frequency",16);
    assert(isscalar(rc) && T.Stimulus(rc) == "ClickTrain" && T.Stimulus(rt) == "Tone", ...
        '%s: thresholdRow is not NaN-safe.',style);
    sk = s.seriesKeys();
    assert(numel(sk) == height(T) && isequal(sort(sk),sort(T.Key)),'%s: seriesKeys.',style);
    ski = T.Key(T.AcqMode == "interleaved" & T.Frequency == 16);
    assert(s.seriesLabel(ski) == "Tone 16 kHz · interleaved" && ...
        s.seriesLabel(T.Key(rc)) == "ClickTrain · conventional",'%s: seriesLabel.',style);
    sc = s.seriesConditions(T.Key(rc));
    assert(numel(sc) == nL && isequal(C.Level(s.rowOf(sc)).',small.Levels),'%s: seriesConditions.',style);

    fig = figure('Visible','off');
    ax = axes(fig); %#ok<LAXES> one figure per naming style
    s.plotStack(NaN,Parent=ax);
    nTr = numel(findobj(ax,'Type','line','-function',@(h) numel(h.XData) > 2));
    assert(nTr == nL,'%s: the click stack drew %d traces.',style,nTr);
    cla(ax);
    s.plotStack(16,Parent=ax,Where=struct('AcqMode',"interleaved"));
    close(fig);
end
fprintf(['  PASS Part C: tones + clicks, both layouts, current and old names: ParamNames ' ...
    '[Stimulus Level Frequency] (union), clicks keyed without Frequency, no mixed condition, ' ...
    'grid/varyingParams/thresholdRow/plotStack/labels NaN-safe (%.1f s)\n'],toc(tp));

% =========================================================================
%  Part D -- acquisition modes and compact correctness
% =========================================================================
tp = tic;
fb = fullfile(root,"both","SUBJ-ID-9001_261001T140000");
mabrtest.SyntheticABR.writeSession(fb,small,Layout="both");
nT = nL*nF;
ext = [0 1000*(L-1)/Fs];
s = mabr.analysis.Session(fb,Verbose=false);
s.segment();
C = s.Conditions;
conv = C.AcqMode == "conventional";
inter = C.AcqMode == "interleaved";
assert(height(C) == 2*nT && sum(conv) == nT && sum(inter) == nT, ...
    'Two runs of one grid should be %d conditions, not %d.',2*nT,height(C));
assert(all(C.Processing(conv) == "continuous") && all(C.Processing(inter) == "windowed"), ...
    'Processing per mode is wrong.');
assert(all(abs(C.Extent(inter,:) - ext) < 1e-9,'all') && all(abs(C.Extent(conv,:) - [-12 12]) < 1e-9,'all'), ...
    'Extents are wrong.');
r = find(inter,1);
inside = s.Time >= C.Extent(r,1) & s.Time <= C.Extent(r,2);
assert(all(isnan(C.Sweeps{r}(~inside,:)),'all') && all(isfinite(C.Sweeps{r}(inside,:)),'all'), ...
    'Rows outside an interleaved condition''s Extent are not NaN.');
assert(all(isnan(C.SweepTime{r})) && all(isfinite(C.SweepTime{find(conv,1)})), ...
    'SweepTime must be NaN for compact sweeps only.');
assert(all(C.SweepOrder{r} == 1:C.nSweeps(r)),'SweepOrder is not the acquisition rank.');

sp = mabr.analysis.Session(fb,Verbose=false);
sp.segment(PoolAcqModes=true);
Pc = sp.Conditions;
assert(height(Pc) == nT && all(Pc.AcqMode == "pooled") && all(Pc.Processing == "windowed") ...
    && all(abs(Pc.Extent - ext) < 1e-9,'all') && all(Pc.nSweeps == 2*small.nSweeps) && all(Pc.nFiles == 2), ...
    'PoolAcqModes=true did not pool the two runs into windowed conditions.');

% A typed GroupBy keeps the acquisition modes apart (seriesGrouping): with
% "Frequency" alone the conventional and the interleaved run of a frequency
% were once fitted as one series. Pooled, AcqMode is one value and is not added.
s.detect(Method="tmax",NumPermutations=20);
s.estimateThresholds(Method="perm-descending",GroupBy="Frequency",MinSweeps=0,MinPerPolarity=0);
want = s.KeyParams(ismember(s.KeyParams,["Stimulus" "AcqMode" "Frequency"]));
skm = arrayfun(@(k) s.seriesOf(k),s.Conditions.Key);
mixedModes = arrayfun(@(k) numel(unique(s.Conditions.AcqMode(skm == k))) > 1,unique(skm));
assert(isequal(s.GroupParams,want) && any(want == "AcqMode") && height(s.Thresholds) == 2*nF && ...
    ~any(mixedModes) && any(contains(s.Messages.Text,"AcqMode added to the GroupBy given")), ...
    'GroupBy "Frequency" mixed the acquisition modes (GroupParams %s, %d series).', ...
    strjoin(s.GroupParams,", "),height(s.Thresholds));
sp.detect(Method="tmax",NumPermutations=20);
sp.estimateThresholds(Method="perm-descending",GroupBy="Frequency",MinSweeps=0,MinPerPolarity=0);
assert(~ismember("AcqMode",sp.GroupParams) && height(sp.Thresholds) == nF, ...
    'Pooled modes: GroupBy "Frequency" should not add AcqMode (GroupParams %s).',strjoin(sp.GroupParams,", "));

% Filters off: a compact sweep is its own window, detrended -- not a sample
% from the windows on either side of it.
raw = mabr.analysis.Filter('HighPass',[],'LowPass',[]);
s0 = mabr.analysis.Session(fb,Verbose=false,Filter=raw);
s0.segment();
C0 = s0.Conditions;
nChecked = 0;
for r = find(C0.AcqMode == "interleaved").'
    ins = s0.Time >= C0.Extent(r,1) - 1e-9 & s0.Time <= C0.Extent(r,2) + 1e-9;
    fr = C0.SweepFile{r};
    for row = unique(fr)
        [~,tr,sw] = mabr.analysis.AbrFile.read(fullfile(s0.Files.folder(row),s0.Files.fileName(row)));
        cols = find(fr == row);
        for k = cols
            on  = sw.Onset(sw.Index == C0.SweepIndex{r}(k));
            want = detrend(double(tr(on + (0:L-1))),1);
            got  = C0.Sweeps{r}(ins,k);
            assert(max(abs(got - want)) < 1e-12,'%s sweep %d is not its own window.',C0.Key(r),k);
            nChecked = nChecked + 1;
        end
    end
end

% A run stopped inside its last presentation: that zero-filled window is
% dropped, said so, and nothing else is.
Tt = small;  Tt.Freqs = 8;  Tt.Threshold = 20;  Tt.Levels = [40 80];
ft = fullfile(root,"truncated","SUBJ-ID-9001_T");
mabrtest.SyntheticABR.writeSession(ft,Tt,Layout="compact",Truncated=true);
st = mabr.analysis.Session(ft,Verbose=false);
st.segment();
tr1 = contains(st.Conditions.Flags,"1 truncated sweep(s) dropped");
assert(sum(tr1) == 1 && st.Conditions.nSweeps(tr1) == Tt.nSweeps - 1 && ...
    all(st.Conditions.nSweeps(~tr1) == Tt.nSweeps) && any(contains(st.Messages.Text,"truncated")), ...
    'The truncated compact window was not dropped with a flag and a message.');
fprintf(['  PASS Part D: conventional/interleaved split (%d + %d conditions, continuous/windowed, ' ...
    'Extent [0 %.3f] ms, NaN outside), PoolAcqModes (%d pooled, 2 files each), a typed GroupBy ' ...
    '"Frequency" keeps the modes apart (AcqMode added; not when pooled), %d compact sweeps ' ...
    'each exactly its own window, a truncated window dropped (%.1f s)\n'],nT,nT,ext(2),nT,nChecked,toc(tp));

% =========================================================================
%  Part E -- the windowed operator against the continuous chain
% =========================================================================
tp = tic;
Tw = truth;  Tw.Freqs = 16;  Tw.Threshold = 40;  Tw.Levels = 80;
Tw.ArtifactSweeps = [];  Tw.FlaggedSweeps = [];
fw = fullfile(root,"windowed","SUBJ-ID-9001_W");
iw = mabrtest.SyntheticABR.writeSession(fw,Tw);
win = [0 1000*(L-1)/Fs];
sr = mabr.analysis.Session(fw,Verbose=false,Filter=raw,Window=win);
sr.segment();
mraw = mean(sr.sweeps(1,IncludeRejected=true),2);
[mwin,winfo] = f.applyWindowed(mraw);
sf = mabr.analysis.Session(fw,Verbose=false,Window=win);
sf.segment();
mfir = mean(sf.sweeps(1,IncludeRejected=true),2);
tm = sr.Time;
W  = mabrtest.SyntheticABR.waveTruth(80,16,iw.Truth);
dt = 1000/Fs;
waves = strings(0,1);
for w = 1:height(W)
    [lw,pw] = extremumNear(tm,mwin,W.PeakLatency(w),"max");
    [lf,pf] = extremumNear(tm,mfir,W.PeakLatency(w),"max");
    [~,nw]  = extremumNear(tm,mwin,W.TroughLatency(w),"min");
    [~,nf]  = extremumNear(tm,mfir,W.TroughLatency(w),"min");
    dPN = (pw - nw)/(pf - nf) - 1;
    waves(end+1) = sprintf('%s %+.3f ms %+.1f%%',W.Wave(w),lw - lf,100*dPN); %#ok<AGROW>
    if w == 1, continue; end                       % wave I: printed, not asserted
    assert(abs(lw - lf) <= dt + 1e-9,'Wave %s peaks %.3f ms apart (windowed vs continuous).',W.Wave(w),lw - lf);
    assert(abs(dPN) <= 0.10,'Wave %s P-N differs by %.1f%%.',W.Wave(w),100*dPN);
end
fprintf(['  PASS Part E: windowed vs continuous at 80 dB/16 kHz (%s): waves II-V within one sample, ' ...
    'P-N within 10%% [%s] (%.1f s)\n'],winfo.Description,strjoin(waves,', '),toc(tp));

% =========================================================================
%  Part F -- per-condition seeds (defect 20)
% =========================================================================
tp = tic;
s.detect(Method="tfce",NumPermutations=100,SeedMode="per-condition");
pFull = s.Conditions.p;
Dfull = s.Conditions.Detection;
sub = [2 5 11];
keys = s.Conditions.Key(sub);
s.detect(Method="tfce",NumPermutations=100,SeedMode="per-condition",Keys=keys);
assert(isequaln(s.Conditions.p,pFull),'A subset re-test changed p.');
for i = 1:numel(sub)
    d = s.Conditions.Detection{sub(i)};
    assert(d.Seed == mabr.analysis.Stats.conditionSeed(1,keys(i)) && isequal(d.null,Dfull{sub(i)}.null), ...
        'The subset re-test of %s is not bit-identical.',keys(i));
end
C = s.Conditions;
r1 = find(C.AcqMode == "interleaved",1);
r2 = find(C.AcqMode == "interleaved" & C.nClean == C.nClean(r1),2);
r2 = r2(2);
assert(C.Detection{r1}.Seed ~= C.Detection{r2}.Seed,'Two conditions drew the same seed.');
rows = mabr.analysis.Artifacts.windowMask(s.Time,s.ResponseWindow) & s.Time >= C.Extent(r1,1) & s.Time <= C.Extent(r1,2);
X1 = s.sweeps(r1);
[~,res] = mabr.analysis.PermTest.run(X1(rows,:),Method="tfce",NumPermutations=100, ...
    Seed=mabr.analysis.Stats.conditionSeed(1,C.Key(r1)));
assert(isequal(res.null,C.Detection{r1}.null),'The per-condition null is not PermTest''s under that seed.');
% The same sweeps flipped by the other condition's draw give another null:
% the two conditions' sign-flip sets differ (with one shared seed they were
% the same set, which is defect 20).
[~,res2] = mabr.analysis.PermTest.run(X1(rows,:),Method="tfce",NumPermutations=100, ...
    Seed=mabr.analysis.Stats.conditionSeed(1,C.Key(r2)));
assert(~isequal(res2.null,res.null),'Two equal-N conditions drew the same sign flips.');
s.detect(Method="tfce",NumPermutations=100,SeedMode="shared");
[~,res1] = mabr.analysis.PermTest.run(X1(rows,:),Method="tfce",NumPermutations=100,Seed=1);
assert(isequal(s.Conditions.Detection{r1}.null,res1.null) && ~isequal(res1.null,res.null), ...
    'SeedMode "shared" is not today''s behaviour.');
fprintf(['  PASS Part F: a subset re-test (3 of %d keys) is bit-identical; equal-N conditions draw ' ...
    'different seeds; per-condition and shared nulls are PermTest''s under those seeds (%.1f s)\n'], ...
    height(C),toc(tp));

% =========================================================================
%  Part G -- atomic steps under a cancelling progress sink
% =========================================================================
tp = tic;
Ta = small;  Ta.Freqs = [8 16];  Ta.Threshold = [20 40];
fa = fullfile(root,"atomic","SUBJ-ID-9001_A");
mabrtest.SyntheticABR.writeSession(fa,Ta);
s = mabr.analysis.Session(fa,Verbose=false);
s.segment();  s.reject();  s.detect(Method="tmax",NumPermutations=50);  s.estimateThresholds();
S0 = snapshot(s);
s.ProgressFcn = @(m,c,t) cancelAt(c,2);
steps = {@() s.parse(), @() s.segment(Window=[-5 8]), @() s.reject(Method="mean",Keep=false), ...
    @() s.detect(NumPermutations=60), @() s.estimateThresholds(Type="isotonic")};
names = ["parse","segment","reject","detect","estimateThresholds"];
for i = 1:numel(steps)
    id = "";
    try
        steps{i}();
    catch ME
        id = string(ME.identifier);
    end
    assert(id == "mabr:analysis:cancelled",'%s was not cancelled (%s).',names(i),id);
    assert(isequaln(snapshot(s),S0),'A cancelled %s changed the session.',names(i));
end
s.ProgressFcn = [];
s.segment(Window=[-5 8]);
assert(~isequaln(snapshot(s),S0),'Without the sink the step did nothing.');
fprintf('  PASS Part G: cancelled parse, segment, reject, detect and estimateThresholds leave the session unchanged (%.1f s)\n',toc(tp));

% =========================================================================
%  Part H -- results v2
% =========================================================================
tp = tic;
fr = fullfile(root,"results","SUBJ-ID-9001_261001T140000");
mabrtest.SyntheticABR.writeSession(fr,truth,Layout="both");
s = mabr.analysis.Session(fr,Verbose=false);
s.segment();  s.reject();  s.detect(Method="tmax",NumPermutations=50);  s.estimateThresholds(Type="glm");
assert(s.NumConditions == 54,'Expected 54 conditions, got %d.',s.NumConditions);
outDir = fullfile(root,"out");
f1 = s.saveResults(fullfile(outDir,"small.mat"),IncludeSweeps=false);
d1 = dir(f1);
assert(d1.bytes < 2e6,'A 54-condition results file without sweeps is %.2f MB.',d1.bytes/1e6);
assert(isempty(dir(fullfile(outDir,'*.tmp-*'))),'The atomic save left a temporary file.');
vars = string(who('-file',f1));
need = ["Version","Provenance","Settings","StepState","Summary","Files","Conditions","Means", ...
    "SweepInfo","Detection","Thresholds","CurationArchive","Peaks","PeakOverrides", ...
    "ManualRejections","DetectionOverrides","Messages","EditLog"];
assert(all(ismember(need,vars)) && ~ismember("Sweeps",vars),'Results variables: %s.',strjoin(vars,', '));
Lr = load(f1,'Version','Summary','StepState','Thresholds');
assert(Lr.Version == 2 && Lr.Summary.NumConditions == 54 && istable(Lr.Thresholds), ...
    'The small variables do not read on their own.');
R = load(f1);
assert(~any(varfun(@iscell,R.Conditions,'OutputFormat','uniform')),'Saved Conditions hold a cell column.');
assert(~any(cellfun(@(x) isstruct(x) && isfield(x,'Predict'),R.Thresholds.Fit)),'A saved Fit kept Predict.');
assert(~isfield(R.Detection,'null'),'The permutation null was saved.');

r = mabr.analysis.Session.fromResults(f1,Verbose=false);
assert(~r.HasSweeps && all(cellfun(@isempty,r.Conditions.Sweeps)),'A results-only session has sweeps.');
assert(isequal(r.Conditions.Properties.VariableNames,s.Conditions.Properties.VariableNames), ...
    'The reloaded Conditions columns differ: %s.',strjoin(r.Conditions.Properties.VariableNames,' '));
for col = ["Key","Rejected","RejectReason","Polarity","SweepFile","SweepIndex","SweepOrder","Excess", ...
        "nSweeps","nClean","nPos","nNeg","Processing","Extent","p","isSig","Detected"]
    assert(isequaln(r.Conditions.(col),s.Conditions.(col)),'Reloaded %s differs.',col);
end
dT = cellfun(@(a,b) max([0 abs(a - b)./max(1,abs(b))]),r.Conditions.SweepTime,s.Conditions.SweepTime);
assert(all(dT < 1e-6 | isnan(dT)),'Reloaded SweepTime differs beyond single precision.');
assert(isequal(r.Conditions.Detection{7}.p,s.Conditions.Detection{7}.p) && ...
    max(abs(r.Conditions.Detection{7}.t - s.Conditions.Detection{7}.t)) < 1e-5, ...
    'Reloaded Detection differs.');
assert(isequaln(r.Files,s.Files) && isequal(r.Time,s.Time) && isequal(r.ParamNames,s.ParamNames) ...
    && isequal(r.KeyParams,s.KeyParams) && r.Name == s.Name && r.Subject == s.Subject ...
    && r.DataFingerprint == s.DataFingerprint && r.Units == s.Units && r.LevelUnit == s.LevelUnit ...
    && isequal(r.AcqModes,s.AcqModes) && r.Filter.describe() == s.Filter.describe(), ...
    'The reloaded session''s summary differs.');
assert(isequal(r.Thresholds.Threshold,s.Thresholds.Threshold) && ...
    isa(r.Thresholds.Fit{1}.Predict,'function_handle') && ...
    max(abs(r.Thresholds.Fit{1}.Predict([20;40]) - s.Thresholds.Fit{1}.Predict([20;40]))) < 1e-12, ...
    'Reloaded thresholds or their Predict differ.');
worst = 0;
for key = s.Conditions.Key(1:5:end).'
    for pol = ["balanced","positive","negative","difference","all"]
        m0 = s.conditionMean(key,pol);
        m1 = r.conditionMean(key,pol);
        assert(isequal(isnan(m0),isnan(m1)),'conditionMean(%s,%s) NaN pattern differs.',key,pol);
        e = max(abs(m1 - m0),[],'omitnan')/max(abs(m0),[],'omitnan');
        worst = max(worst,e);
        assert(e <= 1e-6,'conditionMean(%s,%s) differs by %.2g (relative).',key,pol,e);
    end
end
for step = ["segment","reject","detect"]
    id = "";
    try
        r.(step)();
    catch ME
        id = string(ME.identifier);
    end
    assert(id == "mabr:analysis:Session:noRaw",'A results-only %s did not refuse (%s).',step,id);
end
try
    r.loadRaw();
    assert(r.HasSweeps && isequal(r.Conditions.nSweeps,s.Conditions.nSweeps), ...
        'loadRaw did not restore the sweeps with identical counts.');
    lrNote = "loadRaw restores the sweeps";
catch ME
    if ME.identifier ~= "mabr:analysis:Session:notImplemented", rethrow(ME); end
    lrNote = "loadRaw SKIP (part B)";
end

Rn = s.toStruct(false,false);
Rn.Version = 3;
qn = mabr.analysis.Session.fromResults(Rn,Verbose=false);
assert(qn.NumConditions == s.NumConditions && ...
    any(qn.Messages.Level == "warning" & contains(qn.Messages.Text,"newer MABR")), ...
    'A results file from a newer format did not load with a warning.');

f2 = s.saveResults(fullfile(outDir,"full.mat"));
d2 = dir(f2);
r2 = mabr.analysis.Session.fromResults(f2,Verbose=false);
assert(d2.bytes > d1.bytes && r2.HasSweeps && isequaln(r2.Conditions.Sweeps,s.Conditions.Sweeps), ...
    'A results file with sweeps did not reload them.');
r2.detect(Method="tmax",NumPermutations=50);
assert(isequaln(r2.Conditions.p,s.Conditions.p),'Re-testing reloaded sweeps changed p.');

% Saving leaves no row in Messages (the app saves after every edit, and
% Messages is written into the file): repeated saves keep the table and the
% file's copy the same size, a "save" row an older MABR recorded is left out
% of the file and dropped, and the note is still printed under Verbose.
Rs = s.toStruct(false,false);
Rs.Messages(end+1,:) = {datetime('now'),"info","save","Saved an older file."};
qs = mabr.analysis.Session.fromResults(Rs,Verbose=false);
assert(sum(qs.Messages.Step == "save") == 1,'The planted save row did not load.');
fs = fullfile(outDir,"saves.mat");
qs.saveResults(fs,IncludeSweeps=false);
n0 = height(qs.Messages);
Lm = load(fs,'Messages');
assert(~any(qs.Messages.Step == "save") && ~any(Lm.Messages.Step == "save"), ...
    'A save row is still in Messages or in the file.');
qs.Verbose = true;
for k = 1:3
    out = evalc('qs.saveResults(fs,IncludeSweeps=false);');
    assert(contains(out,"Saved " + fs),'A Verbose save did not print its note: "%s".',out);
end
qs.Verbose = false;
Lm = load(fs,'Messages');
assert(height(qs.Messages) == n0 && height(Lm.Messages) == n0 && ~any(Lm.Messages.Step == "save"), ...
    'Saving grew Messages (%d -> %d rows; the file holds %d).',n0,height(qs.Messages),height(Lm.Messages));
assert(isempty(strtrim(evalc('qs.saveResults(fs,IncludeSweeps=false);'))), ...
    'A save printed with Verbose false.');

% A hand-written v1 results struct (the format before keys) loads.
k1 = find(s.Conditions.AcqMode == "conventional" & s.Conditions.Frequency == 8);
C1 = s.Conditions(k1,:);
v1C = table(C1.Frequency,C1.Level,C1.Sweeps,C1.Rejected,C1.Polarity,C1.SweepFile,C1.nSweeps, ...
    C1.nRejected,C1.nFiles,C1.p,C1.isSig,C1.strength, ...
    'VariableNames',{'Frequency','Level','Sweeps','Rejected','Polarity','SweepFile','nSweeps', ...
    'nRejected','nFiles','p','isSig','strength'});
v1C.Detection = num2cell(struct('p',num2cell(C1.p),'isSig',num2cell(C1.isSig), ...
    'strength',num2cell(C1.strength),'nSweeps',num2cell(C1.nClean),'result',struct()));
v1F = s.Files(:,{'Frequency','Level','timestamp','fileName','folder','nSweeps','SampleRate','TestMode'});
fit1 = mabr.analysis.Threshold.fit(C1.Level,double(C1.isSig),Type="glm",Seed=1);
v1T = table(8,fit1.Threshold,NaN,NaN,fit1.Threshold,false,"glm","binary",height(C1),sum(C1.isSig), ...
    {fit1},"Level",'VariableNames',{'Frequency','Threshold','CILower','CIUpper','Curated', ...
    'IsCurated','Type','FitTarget','NumLevels','NumSig','Fit','LevelParam'});
v1 = struct('Version',1,'Path',fr,'Name',"v1",'Subject',"SUBJ-ID-9001",'Date',s.Date, ...
    'SampleRate',Fs,'Window',s.Window,'ResponseWindow',s.ResponseWindow,'Time',s.Time, ...
    'ParamNames',["Frequency" "Level"],'TestMode',false,'Files',v1F,'Conditions',v1C, ...
    'Thresholds',v1T,'FilterDescription',"300-3000 Hz FIR");
save(fullfile(outDir,"v1.mat"),'-struct','v1');
for src = {v1, fullfile(outDir,"v1.mat")}
    q = mabr.analysis.Session.fromResults(src{1});
    assert(q.NumConditions == height(C1) && q.HasSweeps && q.Name == "v1", ...
        'A v1 struct did not load its conditions.');
    vq = string(q.Conditions.Properties.VariableNames);
    assert(all(ismember(["Key","AcqMode","RejectReason","SweepIndex","Excess","nClean","nPos", ...
        "nNeg","Processing","Extent","DetectedAuto"],vq)),'A v1 load lacks the current columns.');
    assert(q.Conditions.Key(1) == "AcqMode=conventional|Frequency=8|Level=" + C1.Level(1), ...
        'A v1 key reads "%s".',q.Conditions.Key(1));
    m0 = s.conditionMean(C1.Key(3));
    m1 = q.conditionMean(q.Conditions.Key(3));
    assert(max(abs(m1 - m0)) < 1e-12,'A v1 condition mean differs.');
    assert(q.Thresholds.Key == "AcqMode=conventional|Frequency=8" && ...
        q.Conditions.Detection{1}.p == C1.p(1),'A v1 Thresholds/Detection did not load.');
end
fprintf(['  PASS Part H: results v2 (no sweeps %.2f MB, all variables, small ones load alone; ' ...
    'per-sweep cells rebuilt; conditionMean within %.1g; results-only steps refuse; %s; ' ...
    'with sweeps %.1f MB reloads whole); saving adds no Messages row (a legacy one dropped, ' ...
    'the note printed under Verbose only); a hand-written v1 struct loads (%.1f s)\n'], ...
    d1.bytes/1e6,worst,lrNote,d2.bytes/1e6,toc(tp));

% =========================================================================
%  Part I -- defects 9, 10, 15, 17; Messages without printing
% =========================================================================
tp = tic;
Td = truth;  Td.Freqs = 8;  Td.Threshold = 20;  Td.Levels = [20 50 80];  Td.nSweeps = 32;
fd = fullfile(root,"defects","SUBJ-ID-9001_D");
mabrtest.SyntheticABR.writeSession(fd,Td,OtherRateFile=true,TestModeFile=true);
msgs = containers.Map('KeyType','char','ValueType','any');
msgs('rows') = strings(0,2);
s = mabr.analysis.Session(fd,Verbose=false,Parse=false);
s.MessageFcn = @(lvl,txt) recordMessage(msgs,lvl,txt);
out = evalc('s.parse();');
assert(isempty(strtrim(out)),'parse printed with Verbose false: "%s".',out);
F = s.Files;
k = F.SampleRate == 11025;
assert(nnz(k) == 1 && ~F.Include(k) && F.Reason(k) == "sample rate 11025 Hz differs from the session's 12000 Hz", ...
    'The 11025 Hz file was not left out with its reason (defect 9).');
k = F.TestMode;
assert(nnz(k) == 1 && ~F.Include(k) && F.Reason(k) == "Test Mode (the stimulus, not a subject)", ...
    'The Test Mode file was not left out with its reason (defect 17).');
assert(~s.TestMode && s.SampleRate == 12000 && sum(F.Include) == numel(Td.Levels), ...
    'The session is not the animal''s files at 12 kHz.');
M = s.Messages;
mr = msgs('rows');
assert(any(M.Level == "warning" & M.Step == "parse") && any(mr(:,1) == "warning") ...
    && size(mr,1) == height(M),'Warnings did not reach Messages and MessageFcn.');
out = evalc('s.segment(); s.reject(); s.detect(Method="tmax",NumPermutations=50); s.estimateThresholds();');
assert(isempty(strtrim(out)),'A step printed with Verbose false: "%s".',out);
assert(all(ismember(["parse","segment","reject","detect","thresholds"],s.Messages.Step)), ...
    'Every step should leave a message.');
nSeg = sum(s.Messages.Step == "segment");
s.segment();
assert(sum(s.Messages.Step == "segment") == nSeg,'Re-running segment did not replace its messages.');
for m = ["movmedian","movmean"]
    id = "";
    try
        s.reject(Method=m);
    catch ME
        id = string(ME.identifier);
    end
    assert(id == "mabr:analysis:Session:badRejectMethod",'reject(Method="%s") was not refused (defect 10).',m);
end

fu = fullfile(root,"uncal","SUBJ-ID-9001_U");
iu = mabrtest.SyntheticABR.writeSession(fu,Td);
for i = 1:height(iu.Files)
    ffn = fullfile(fu,iu.Files.FileName(i));
    A = load(ffn,'-mat','ABR_Data');
    ABR_Data = A.ABR_Data;
    ABR_Data.SIG.Calibrated = false;
    save(ffn,'ABR_Data','-v6');
end
su = mabr.analysis.Session(fu,Verbose=false);
assert(su.LevelUnit == "dB" && s.LevelUnit == "dB SPL",'LevelUnit: "%s" / "%s".',su.LevelUnit,s.LevelUnit);
su.segment();  su.detect(Method="tmax",NumPermutations=50);  su.estimateThresholds();
fig = figure('Visible','off');
ax = axes(fig);
su.plotAudiogram(Parent=ax);
yu = ax.YLabel.String;
clf(fig);
ax = axes(fig);
s.plotAudiogram(Parent=ax);
yc = ax.YLabel.String;
clf(fig);
tl = tiledlayout(fig,1,1);
su.plotGrid(Parent=tl);
yg = tl.YLabel.String;
close(fig);
assert(strcmp(yu,'Threshold (dB)') && strcmp(yc,'Threshold (dB SPL)') && strcmp(yg,'Level (dB)'), ...
    'Level labels: "%s", "%s", "%s" (defect 15).',yu,yc,yg);
fprintf(['  PASS Part I: 11025 Hz and Test Mode files left out with their reasons (defects 9, 17); ' ...
    'movmedian/movmean refused (10); uncalibrated levels labelled dB (15); %d messages kept and ' ...
    'heard with Verbose false, nothing printed, a re-run step replaces its own (%.1f s)\n'], ...
    height(s.Messages),toc(tp));

% =========================================================================
%  Part J -- rejection, the sweep cap, UnitOverride, access helpers
% =========================================================================
tp = tic;
Tj = truth;  Tj.Freqs = 16;  Tj.Threshold = 40;  Tj.Levels = [40 80];
fj = fullfile(root,"reject","SUBJ-ID-9001_J");
mabrtest.SyntheticABR.writeSession(fj,Tj);
s = mabr.analysis.Session(fj,Verbose=false);
s.segment();
for r = 1:s.NumConditions
    assert(isequal(find(s.Conditions.Rejected{r}),40) && s.Conditions.RejectReason{r}(40) == 1, ...
        'The rig''s flag (sweep 40, reason 1) was not honoured.');
end
s.reject();
for r = 1:s.NumConditions
    rej = s.Conditions.Rejected{r};  why = s.Conditions.RejectReason{r};
    assert(all(rej([5 40 77])) && why(40) == 1 && why(5) == 2 && why(77) == 2, ...
        'The criterion did not add the unflagged artifacts 5 and 77 (reason 2).');
    assert(isequal(why(rej) > 0,true(1,sum(rej))) && all(why(~rej) == 0),'Reasons and flags disagree.');
end
keepTrue = s.Conditions.Rejected;
s.reject(Keep=false);
assert(isequal(s.Conditions.Rejected,keepTrue),'Keep=false is not "rig flags | this criterion".');
s.segment(HonorAcquisitionArtifacts=false);
assert(all(cellfun(@(x) ~any(x),s.Conditions.Rejected)),'Unhonoured rig flags were applied.');
s.reject(Keep=false);
assert(all(cellfun(@(x) x(40) == 2,s.Conditions.RejectReason)),'Sweep 40 should now be the criterion''s.');
s.segment();
s.clearRejected();
assert(all(s.Conditions.nRejected == 0),'clearRejected left flags.');
s.reject(Method="threshold",Threshold=100e-6);
for r = 1:s.NumConditions
    assert(isequal(find(s.Conditions.Rejected{r}),[5 40 77]),'The legacy threshold path flagged the wrong sweeps.');
end

s.segment(MaxSweepsPerCondition=64);
C = s.Conditions;
for r = 1:height(C)
    ex = C.Excess{r};  rej = C.Rejected{r};  pol = C.Polarity{r};
    assert(C.nClean(r) == 64 && C.nPos(r) == 32 && C.nNeg(r) == 32 && ~any(ex & rej) ...
        && sum(ex) == C.nSweeps(r) - C.nRejected(r) - 64 && isequal(find(rej),40), ...
        'The cap is not 32 clean sweeps per polarity, Excess apart from Rejected.');
    keepPos = find(~rej & ~ex & pol > 0);
    cleanPos = find(~rej & pol > 0);
    assert(isequal(keepPos,cleanPos(1:32)),'EqualizeMode "first" did not keep the earliest.');
end
assert(size(s.sweeps(1),2) == 64 && size(s.sweeps(1,IncludeExcess=true),2) == C.nSweeps(1) - 1, ...
    'sweeps() does not leave Excess out by default.');
s.segment(MaxSweepsPerCondition=64,EqualizeMode="random",Seed=3);
e1 = s.Conditions.Excess;
s.segment(MaxSweepsPerCondition=64,EqualizeMode="random",Seed=3);
assert(isequal(e1,s.Conditions.Excess) && ~isequal(e1,C.Excess) && all(s.Conditions.nClean == 64), ...
    'EqualizeMode "random" is not a seeded, balanced draw.');
s.reject();
assert(all(s.Conditions.nClean == 64),'Excess was not recomputed after reject.');

sv = mabr.analysis.Session(fj,Verbose=false,UnitOverride=struct('InputFullScale',0.5,'AmplifierGain',NaN));
sv.segment();
s.segment();
g = (Tj.AmplifierGain/Tj.InputFullScale)*(0.5/Tj.AmplifierGain);
Xv = sv.Conditions.Sweeps{1};  X0 = s.Conditions.Sweeps{1};
assert(sv.Units == "V" && all(sv.Conditions.Units == "V") && max(abs(Xv - g*X0),[],'all') < 1e-9*max(abs(X0),[],'all'), ...
    'UnitOverride did not rescale the traces by %.4f.',g);

sk = s.seriesKeys();
ck = s.seriesConditions(sk);
assert(isequal(sk,"Stimulus=Tone|AcqMode=conventional|Frequency=16") && ...
    isequal(ck,["Stimulus=Tone|AcqMode=conventional|Frequency=16|Level=40"; ...
    "Stimulus=Tone|AcqMode=conventional|Frequency=16|Level=80"]),'seriesKeys/seriesConditions.');
assert(s.seriesOf(ck(2)) == sk && s.conditionLabel(ck(2)) == "80 dB" && s.seriesLabel(sk) == "Tone 16 kHz", ...
    'seriesOf/conditionLabel/seriesLabel.');
assert(isequal(s.groupColumns(),["Stimulus","AcqMode","Frequency"]) && s.levelParamOrEmpty() == "Level", ...
    'groupColumns/levelParamOrEmpty.');
id = "";
try
    s.rowOf("Stimulus=Noise");
catch ME
    id = string(ME.identifier);
end
assert(id == "mabr:analysis:Session:unknownKey",'rowOf accepted an unknown key.');
[m,sem,n] = s.conditionMean(ck(2));
X   = s.sweeps(2);
pol = s.Conditions.Polarity{2}(~s.Conditions.Rejected{2} & ~s.Conditions.Excess{2});
want = (mean(X(:,pol > 0),2) + mean(X(:,pol < 0),2))/2;
assert(n == size(X,2) && max(abs(m - want)) < 1e-15 && all(sem > 0), ...
    'conditionMean is not the polarity-balanced mean (equal weight per polarity).');
mAll = s.conditionMean(ck(2),"all");
assert(max(abs(mAll - mean(X,2))) < 1e-15,'conditionMean "all" is not the plain mean.');
fprintf(['  PASS Part J: rig/criterion flags with reasons, Keep, HonorAcquisitionArtifacts, the legacy ' ...
    'threshold path; the cap (32 per polarity, first and seeded random, Excess not Rejected); ' ...
    'UnitOverride x%.3f; access helpers (%.1f s)\n'],g,toc(tp));

% =========================================================================
%  Part K -- no part-B stub left
% =========================================================================
% The part-B methods (measure, pickPeaks, analyze, the edits, loadRaw,
% adoptEdits ...) are checked by verify_offline_analyze; here only that none
% of them is still a stub.
src = fileread(which('mabr.analysis.Session'));
assert(~contains(src,'notImplemented'),'Session still holds a notImplemented stub.');
for m = ["measure","pickPeaks","analyze","isStale","recompute","loadRaw","adoptEdits", ...
        "acceptFit","setDecision","clearDecision","setThresholdNote","setDetectionOverride", ...
        "setSweepsRejected","clearManualRejections","setExcluded","setPeak","setPeakAbsent", ...
        "clearPeak","clearPeakOverrides","retrackSeries","picksAsWindows","editSnapshot","restoreEdits"]
    assert(ismember(m,string(methods('mabr.analysis.Session'))),'Session has no method %s.',m);
end
fprintf('  PASS Part K: every part-B method exists and none is a stub\n');

% =========================================================================
%  Part L -- no Statistics Toolbox call
% =========================================================================
for cls = ["mabr.analysis.Session","mabr.analysis.Filter","mabr.analysis.Plot","mabr.analysis.Progress"]
    hits = forbiddenCalls(which(cls));
    assert(isempty(hits),'Statistics Toolbox identifiers in %s:\n%s',cls,strjoin(hits,newline));
end
% And MATLAB's own dependency analysis agrees, for every file of the
% package: MATLAB and the Signal Processing Toolbox, nothing else. (A legacy
% parfor in Session.detect once made it list the Parallel Computing Toolbox.)
tp = tic;
pkg = dir(fullfile(fileparts(which("mabr.analysis.Session")),'*.m'));
pkgFiles = string(fullfile({pkg.folder},{pkg.name}));
[~,pl] = matlab.codetools.requiredFilesAndProducts(cellstr(pkgFiles),'toponly');
prods = string({pl.Name});
extra = setdiff(prods,["MATLAB","Signal Processing Toolbox"]);
assert(isempty(extra),'The offline analysis requires %s.',strjoin(extra,', '));
fprintf(['  PASS Part L: Session, Filter, Plot and Progress call no Statistics Toolbox function; ' ...
    'the %d files of +mabr/+analysis need %s only (%.1f s)\n'],numel(pkgFiles),strjoin(prods," and "),toc(tp));

% =========================================================================
%  Part M -- hand decisions re-applied, subset segment, run groups
% =========================================================================
% Part A has no edit methods (those are part B), so ManualRejections and
% DetectionOverrides arrive the way a results file brings them: the steps
% that follow must apply them last, and both ways.
tp = tic;
s = mabr.analysis.Session(fj,Verbose=false);
s.segment();
R = s.toStruct(true,false);
c1 = 1;
fid = s.Files.FileId(s.Conditions.SweepFile{c1}([40 7]));
six = s.Conditions.SweepIndex{c1}([40 7]);
R.ManualRejections = table(fid(:),six(:),[false;true],repmat(datetime('now'),2,1),["t";"t"], ...
    'VariableNames',{'FileId','SweepIndex','Reject','Time','By'});
rm = mabr.analysis.Session.fromResults(R,Verbose=false);
rm.reject(Method="none");
rej = rm.Conditions.Rejected{c1};  why = rm.Conditions.RejectReason{c1};
assert(~rej(40) && why(40) == 0 && rej(7) && why(7) == 3 && rm.Conditions.nRejected(c1) == 1, ...
    'reject() did not apply the manual restore (sweep 40) and rejection (sweep 7) last.');
rm.reject(Method="threshold",Threshold=100e-6);
rej = rm.Conditions.Rejected{c1};
assert(~rej(40) && rej(7) && all(rej([5 77])),'A criterion overrode a manual decision.');
rm.clearRejected();
assert(isequal(find(rm.Conditions.Rejected{c1}),7),'clearRejected dropped the manual rejection.');
% Both ways: the 40 dB condition (no response at a 40 dB threshold) forced
% detected, the 80 dB one forced not.
kOv = [s.Conditions.Key(s.Conditions.Level == 40); s.Conditions.Key(s.Conditions.Level == 80)];
R.DetectionOverrides = table(kOv,[1;0],repmat(datetime('now'),2,1),["t";"t"], ...
    'VariableNames',{'Key','Value','Time','By'});
R.ManualRejections = R.ManualRejections([],:);
rd = mabr.analysis.Session.fromResults(R,Verbose=false);
rd.detect(Method="tmax",NumPermutations=50);
ro = rd.rowOf(kOv);
assert(isequal(rd.Conditions.Detected(ro),[true;false]) && ...
    isequal(rd.Conditions.DetectedAuto,rd.Conditions.isSig) && ~rd.Conditions.isSig(ro(1)), ...
    'Detection overrides were not applied over the automatic verdict.');

% A subset re-segment is the full one for those keys; a changed window refuses.
C0 = s.Conditions;
s.segment(Keys=C0.Key(2));
assert(isequaln(s.Conditions,C0),'A subset re-segment differs from the full segment.');
id = "";
try
    s.segment(Window=[-5 5],Keys=C0.Key(2));
catch ME
    id = string(ME.identifier);
end
assert(id == "mabr:analysis:Session:subsetWindow",'A subset re-segment with a new window ran (%s).',id);

% Run groups: the gap is from the end of the run so far. Files 150 s apart,
% start to start, but each ~35 s long are one run; a 215 s pause is not.
Tg = truth;  Tg.Freqs = 8;  Tg.Threshold = 20;  Tg.Levels = [40 60 80];  Tg.nSweeps = 1400;
fg = fullfile(root,"rungroups","SUBJ-ID-9001_G");
ig = mabrtest.SyntheticABR.writeSession(fg,Tg);
t0 = datetime(2026,10,1,10,0,0);
starts = t0 + seconds([0 150 400]);
for i = 1:height(ig.Files)
    ffn = fullfile(fg,ig.Files.FileName(i));
    A = load(ffn,'-mat','ABR_Data');
    ABR_Data = A.ABR_Data;
    ABR_Data.StartTime = char(starts(i),'yyyy-MM-dd''T''HH:mm:ss');
    save(ffn,'ABR_Data','-v6');
end
sg = mabr.analysis.Session(fg,Verbose=false);
[~,o] = sort(sg.Files.timestamp);
rgs = sg.Files.RunGroup(o);
assert(all(sg.Files.Duration > 30) && rgs(1) == rgs(2) && rgs(3) ~= rgs(2) && ...
    startsWith(rgs(1),"10:00 Tone conventional (2 files)"), ...
    'Run groups: [%s].',strjoin(rgs,' | '));
fprintf(['  PASS Part M: manual rejections/restores and detection overrides applied last; a subset ' ...
    're-segment equals the full one, a new window refuses; run groups split on a gap after a file ' ...
    'ends (%.1f s)\n'],toc(tp));

% =========================================================================
%  Part N -- non-finite samples cost the sweeps they reach, not the session
% =========================================================================
% One NaN in one file used to stop segment() at the filter (expected finite
% input), and with it the whole session: it could not be analysed, opened,
% or have the file excluded. Now the samples are zeroed for the filter and
% the sweeps whose window -- widened by the filter's reach, on a continuous
% trace -- holds one are left out, the file named in a warning.
tp = tic;
tn = small;  tn.Freqs = 16;  tn.Threshold = 40;  tn.Levels = [40 80];
fc = fullfile(root,"nonfinite","clean","SUBJ-ID-9001_N");
fn = fullfile(root,"nonfinite","dirty","SUBJ-ID-9001_N");
infoN = mabrtest.SyntheticABR.writeSession(fc,tn,Layout="both");
FN = infoN.Files;
mkdir(fn);
copyfile(fullfile(fc,'*'),fn);
ic = find(FN.Layout == "continuous" & FN.Level == 80 & FN.Stimulus == "Tone",1);
iw = find(FN.Layout == "compact" & FN.Level == 80 & FN.Stimulus == "Tone",1);
assert(~isempty(ic) && ~isempty(iw),'The session has no continuous and compact 80 dB tone files.');
Ld = load(fullfile(fn,FN.FileName(ic)),'-mat','ABR_Data');
ABR_Data = Ld.ABR_Data;
onc = double(ABR_Data.ADC.SweepOnsets);
ABR_Data.ADC.Data(onc(10)+30:onc(10)+32) = NaN;         % a run of NaN in sweep 10
ABR_Data.ADC.Data(onc(40)+60) = Inf;                     % and an Inf in sweep 40
save(fullfile(fn,FN.FileName(ic)),'ABR_Data','-v6');
Ld = load(fullfile(fn,FN.FileName(iw)),'-mat','ABR_Data');
ABR_Data = Ld.ABR_Data;
onw = double(ABR_Data.ADC.SweepOnsets);
ABR_Data.ADC.Data(onw(5)+20) = NaN;                      % one NaN in compact window 5
save(fullfile(fn,FN.FileName(iw)),'ABR_Data','-v6');
sC = mabr.analysis.Session(fc,Verbose=false);  sC.segment();
sD = mabr.analysis.Session(fn,Verbose=false);  sD.segment();
CC = sC.Conditions;  CD = sD.Conditions;
assert(isequal(CC.Key,CD.Key),'The conditions differ from the clean session''s.');
rc = find(CD.AcqMode == "conventional" & CD.Level == 80 & CD.Stimulus == "Tone",1);
rw = find(CD.AcqMode == "interleaved" & CD.Level == 80 & CD.Stimulus == "Tone",1);
% continuous: sweeps 10 and 40 and their filter neighbours gone; every sweep
% kept bit for bit the clean session's (the zeroed samples reach no further)
gone = setdiff(CC.SweepIndex{rc},CD.SweepIndex{rc});
kept = ismember(CC.SweepIndex{rc},CD.SweepIndex{rc});
assert(all(ismember([10 40],gone)) && numel(gone) <= 10 && all(isfinite(CD.Sweeps{rc}(:))) && ...
    isequal(CD.Sweeps{rc},CC.Sweeps{rc}(:,kept)), ...
    'Continuous: dropped sweeps %s; the kept ones are not the clean session''s.',mat2str(gone));
% compact: window 5 alone gone, the rest as clean (each window filtered alone)
goneW = setdiff(CC.SweepIndex{rw},CD.SweepIndex{rw});
keptW = ismember(CC.SweepIndex{rw},CD.SweepIndex{rw});
dW = CD.Sweeps{rw} - CC.Sweeps{rw}(:,keptW);
assert(isequal(goneW,5) && max(abs(dW(:)),[],'omitnan') <= 1e-12*max(abs(CC.Sweeps{rw}(:))) && ...
    isequal(isnan(CD.Sweeps{rw}),isnan(CC.Sweeps{rw}(:,keptW))), ...
    'Compact: dropped windows %s (expected 5 alone), or the rest changed.',mat2str(goneW));
others = setdiff(1:height(CD),[rc rw]);
assert(all(arrayfun(@(r) isequaln(CD.Sweeps{r},CC.Sweeps{r}),others)), ...
    'A condition without non-finite samples changed.');
assert(contains(CD.Flags(rc),"sweep(s) reaching non-finite samples dropped") && ...
    contains(CD.Flags(rw),"1 sweep(s) reaching non-finite samples dropped"), ...
    'The conditions'' flags do not say why sweeps went: "%s" / "%s".',CD.Flags(rc),CD.Flags(rw));
wn = sD.Messages.Text(sD.Messages.Level == "warning" & contains(sD.Messages.Text,"non-finite"));
[~,bc] = fileparts(FN.FileName(ic));  [~,bw] = fileparts(FN.FileName(iw));
assert(isscalar(wn) && contains(wn,"2 file(s)") && contains(wn,bc) && contains(wn,bw), ...
    'The warning does not name both files: "%s".',strjoin(wn,' | '));
rep = sD.analyze(mabr.analysis.Settings(NumPermutations=20,SplitHalfResamples=10,MinSweeps=10, ...
    MinPerPolarity=5,PeakBootstrap=0));
assert(startsWith(rep.Status,"ok") && height(sD.Thresholds) > 0,'The session did not analyse: %s.',rep.Status);
fprintf(['  PASS Part N: NaN/Inf samples in a continuous and a compact file cost %d and %d sweep(s), ' ...
    'the kept ones bit for bit (compact: to 1e-12) the clean session''s, every other condition ' ...
    'untouched, both files named in a warning; the session analyses (%.1f s)\n'], ...
    numel(gone),numel(goneW),toc(tp));

% =========================================================================
%  Leaks
% =========================================================================
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_session left a figure open.');
tmr = timerfindall;
if ~isempty(tmr)
    assert(~any(startsWith(string(get(tmr,'Tag')),"MABR_Offline")),'A MABR_Offline* timer leaked.');
end
assert(isequal(rng,rng0),'The global random stream was drawn from.');
clear cleanup
assert(~isfolder(root),'The temporary folder was not removed.');
fprintf('== verify_offline_session PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Helpers
% =========================================================================
function recordCall(rec,m,c,t)
% A progress sink that remembers every call.
x = rec('calls');
x(end+1,:) = [c t];
rec('calls') = x;
rec('msg') = [rec('msg'); string(m)]; %#ok<NASGU> (a containers.Map: a handle)
end

function cancelAt(c,k)
% A progress sink that cancels once the count reaches k.
if c >= k
    error('mabr:analysis:cancelled','Cancelled by user.');
end
end

function recordMessage(rec,level,text)
% A MessageFcn that remembers every message.
x = rec('rows');
x(end+1,:) = [string(level) string(text)];
rec('rows') = x; %#ok<NASGU> (a containers.Map: a handle)
end

function S = snapshot(s)
% What a cancelled step must leave untouched.
S = struct('Window',s.Window,'Time',s.Time,'Filter',s.Filter,'Files',s.Files, ...
    'Conditions',s.Conditions,'Thresholds',s.Thresholds,'Peaks',s.Peaks, ...
    'ManualRejections',s.ManualRejections,'Messages',s.Messages, ...
    'StepState',s.StepState,'ParamNames',s.ParamNames);
end

function [lat,val] = extremumNear(t,y,c,kind)
% The largest local maximum (or smallest local minimum) of y within 0.3 ms
% of c.
if kind == "max"
    m = islocalmax(y);
else
    m = islocalmin(y);
end
m = m & t >= c - 0.3 & t <= c + 0.3;
idx = find(m);
assert(~isempty(idx),'No local %s within 0.3 ms of %.2f ms.',kind,c);
if kind == "max"
    [val,j] = max(y(idx));
else
    [val,j] = min(y(idx));
end
lat = t(idx(j));
end

function hits = forbiddenCalls(file)
% Statistics Toolbox functions called (or the names range/corr/mad used as
% variables) in a file, comments and strings removed.
bad = ["prctile","quantile","iqr","mad","range","zscore","nanmean","nanstd","nanmedian", ...
    "corr","fcdf","finv","tcdf","tinv","normcdf","norminv","normpdf","randsample","datasample", ...
    "bootstrp","fitglm","fitlm","boxplot","ksdensity","grpstats","skewness","kurtosis"];
txt = splitlines(string(fileread(file)));
hits = strings(0,1);
for k = 1:numel(txt)
    s = regexprep(txt(k),'"[^"]*"','""');                    % string literals
    s = regexprep(s,'(?<![\w\)\]\}\.''])''[^'']*''','''''');  % char literals (not transposes)
    s = regexprep(s,'%.*$','');                              % comments
    for b = bad
        callPat = "(?<![\w\.])" + b + "\s*\(";
        varPat  = "(?<![\w\.])" + b + "\s*=(?!=)";
        if ~isempty(regexp(s,callPat,'once')) || ~isempty(regexp(s,varPat,'once'))
            hits(end+1,1) = sprintf('%d: %s',k,strtrim(txt(k))); %#ok<AGROW>
        end
    end
end
end
