function verify_metric_plot()
% verify_metric_plot  Exercise the online-analysis window and its metrics.
%
%   Drives mabr.ui.MetricPlot and the mabr.metrics.online library the way a
%   user does -- but with no audio hardware, no acquisition engine and no
%   parallel pool -- and checks:
%       1. the metric contract: the context struct's window, its units, and
%          the validator's verdict on a good and a bad custom metric;
%       2. every built-in metric returns one number for a representative
%          condition, and the ones with a knowable answer return it;
%       3. values computed per condition from finalized blocks, and how the
%          analysis window changes them;
%       4. the plot ADAPTS: one parameter -> a line with symbols, two -> one
%          line per series level, no parameters -> a bar per stimulus, and
%          heat map / contour / surface on request (with the honest fallback
%          when there is no grid to draw);
%       5. the run in progress: a live snapshot appears as a hollow point,
%          overrides the finalized value for the same stimulus, and clears;
%       6. repeats of one stimulus ACCUMULATE rather than replace;
%       7. aesthetics: the right-click menu drives marker, grid, palette,
%          legend, theme, point labels and plot type, and the menu is on the
%          plotted objects as well as the axes;
%       8. the refresh interval is adjustable and clamped;
%       9. a custom metric is adopted, and a malformed one refused;
%      10. the window is NOT a singleton -- two are independent;
%      11. the numbers come back out as a table.
%
%   Run:  >> verify_metric_plot
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_metric_plot ==\n');

% The window persists its look and last analysis choice; a verification run
% must not walk off with the operator's settings.
hadPref = ispref('MABR','MetricPlot');
oldPref = [];
if hadPref
    oldPref = getpref('MABR','MetricPlot');
    rmpref('MABR','MetricPlot');
end
restorePrefs = onCleanup(@() restore_pref(hadPref,oldPref)); %#ok<NASGU>

Fs      = 12000;
freqs   = [8 16];            % kHz
levels  = [30 60 90];        % dB
nSweeps = 10;

% --- 1. the metric contract ---------------------------------------------
ctx = mabr.metrics.online.sampleContext();
assert(all(ctx.Time >= 0 & ctx.Time <= 10), ...
    'the sample context was not windowed to [0 10] ms');
assert(max(ctx.AllTime) > 9 && min(ctx.AllTime) < -9, ...
    'the context did not keep the unwindowed sweeps');
assert(~isempty(ctx.Baseline), 'the pre-onset baseline is missing from the context');
assert(size(ctx.Sweeps,2) == ctx.NumSweeps && ctx.NumTotal > ctx.NumSweeps, ...
    'the context bookkeeping does not distinguish clean from total sweeps');
assert(abs(ctx.ArtifactRate - 100*ctx.NumArtifacts/ctx.NumTotal) < 1e-9, ...
    'the artifact rate is not the rejected fraction');

% Windowing arithmetic on a signal whose answer is known by construction.
t  = ((-12:12)/1000)';                       % ms -> s, 1 ms per sample
sw = [zeros(13,1); ones(12,1)];              % 0 before +1 ms, 1 from there
c2 = mabr.metrics.online.context(sw,t,1000,struct('Window',[1 12]));
assert(numel(c2.Time) == 12 && abs(c2.Time(1) - 1) < 1e-9, ...
    'the window selected the wrong samples: %s',mat2str(c2.Time([1 end])'));
assert(all(abs(c2.Mean - 1) < 1e-12),'the windowed mean is wrong');

[ok,~]   = mabr.metrics.online.validate(@(c) c.NumSweeps);
assert(ok,'a valid metric was rejected');
assert(mabr.metrics.online.validate(@mabr.metrics.online.custom_template), ...
    'the supplied template does not satisfy its own contract');
[ok,why] = mabr.metrics.online.validate(@(c) c.Sweeps);
assert(~ok && ~isempty(why),'a metric returning a matrix was accepted');
[ok,~]   = mabr.metrics.online.validate(@(c) error('boom'));
assert(~ok,'a metric that throws was accepted');
[ok,~]   = mabr.metrics.online.validate('not a handle');
assert(~ok,'a non-handle was accepted as a metric');
fprintf('  PASS: metric context (ms, windowed, baseline) and validator\n');

% --- 2. every built-in returns one number -------------------------------
C = mabr.metrics.online.catalog();
assert(numel(C) >= 8,'the catalog is suspiciously short (%d)',numel(C));
assert(numel(unique({C.Key})) == numel(C),'two catalog entries share a key');
for i = 1:numel(C)
    v = C(i).Fcn(ctx);
    assert(isscalar(v) && (isnumeric(v) || islogical(v)), ...
        'built-in metric "%s" did not return one number',C(i).Key);
end
eSweeps = mabr.metrics.online.catalog('sweeps');
assert(abs(eSweeps.Fcn(ctx) - ctx.NumSweeps) < 1e-9, ...
    'the sweep-count metric does not report the sweep count');
eP2P = mabr.metrics.online.catalog('p2p');
p2p  = eP2P.Fcn(ctx);
assert(abs(p2p - (max(ctx.Mean)-min(ctx.Mean))*1e6) < 1e-9, ...
    'peak-to-peak is not reported in microvolts');
eLat = mabr.metrics.online.catalog('latency');
lat  = eLat.Fcn(ctx);
assert(lat >= 0 && lat <= 10,'the peak latency (%g ms) is outside the window',lat);
fprintf('  PASS: %d built-in metrics, each one number in its stated unit\n',numel(C));

% --- 3. values from finalized blocks ------------------------------------
mp = mabr.ui.MetricPlot();
cleanup = onCleanup(@() delete(mp));
mp.UpdateInterval = 60;          % keep the window's own clock out of the way
mp.Metric = 'rms';
mp.Window = [0 10];

for f = freqs
    for L = levels
        mp.addBlock(make_block(f,L,nSweeps,Fs));
    end
end

V = mp.values();
assert(numel(V) == numel(freqs)*numel(levels), ...
    'expected %d conditions, got %d',numel(freqs)*numel(levels),numel(V));
assert(all([V.NumSweeps] == nSweeps),'a condition lost sweeps');

rms8 = arrayfun(@(L) value_of(V,8,L),levels);
assert(all(diff(rms8) > 0), ...
    'RMS did not grow with level as the synthetic data does: %s',mat2str(rms8));

mp.Metric = 'sweeps';
Vs = mp.values();
assert(all([Vs.Value] == nSweeps),'the sweep-count metric disagrees');

mp.Metric = 'rms';
mp.Window = [0 2];               % the response lives at ~3-5 ms
narrow = value_of(mp.values(),8,90);
mp.Window = [0 10];
wide   = value_of(mp.values(),8,90);
assert(narrow < wide, ...
    'narrowing the analysis window did not change the metric (%g vs %g)',narrow,wide);
fprintf('  PASS: per-condition values, and the analysis window changes them\n');

% --- 4. the plot adapts to the parameters -------------------------------
ax = mp.Axes;

% Two parameters, nothing chosen: lines with symbols, one per series level.
mp.XParam = ''; mp.SeriesParam = ''; mp.PlotType = 'auto';
h = series_lines(ax);
assert(numel(h) == numel(levels) || numel(h) == numel(freqs), ...
    'auto layout drew %d series for a 2-parameter bank',numel(h));
assert(~strcmp(h(1).Marker,'none'),'the automatic line has no symbols');
lg = get(ax,'Legend');
assert(~isempty(lg) && ~isempty(lg.String),'a multi-series plot has no legend');

% Explicitly: level on X, one line per frequency.
mp.XParam = 'Level'; mp.SeriesParam = 'Frequency';
h = series_lines(ax);
assert(numel(h) == numel(freqs),'expected one line per frequency, got %d',numel(h));
assert(numel(h(1).XData) == numel(levels),'a line does not span the levels');
assert(strcmp(ax.XLabel.String,'Level'),'the X axis is not labelled with its parameter');
assert(contains(ax.YLabel.String,'uV'), ...
    'the Y axis does not carry the metric unit: %s',ax.YLabel.String);
lg = get(ax,'Legend');
assert(strcmp(lg.Title.String,'Frequency'), ...
    'the legend is not titled with the series parameter');

% One series only.
mp.SeriesParam = 'none';
assert(numel(series_lines(ax)) == 1,'"None" still split the data into series');

% No parameter axis at all: one bar per stimulus, labelled with its ID.
mp.XParam = 'Stimulus'; mp.PlotType = 'auto';
b = findobj(ax,'Type','bar');
assert(~isempty(b),'the stimulus axis did not fall back to bars');
assert(numel(ax.XTickLabel) == numel(V),'the bars are not labelled per stimulus');

% A map, on request.
mp.XParam = 'Level'; mp.SeriesParam = 'Frequency'; mp.PlotType = 'heatmap';
im = findobj(ax,'Type','image');
assert(isscalar(im),'the heat map drew no image');
assert(isequal(size(im.CData),[numel(freqs) numel(levels)]), ...
    'the heat map grid is %s, expected %s',mat2str(size(im.CData)), ...
    mat2str([numel(freqs) numel(levels)]));
assert(~isempty(findall(mp.Figure,'Type','colorbar')),'the map has no colorbar');

mp.PlotType = 'contour';
assert(~isempty(findobj(ax,'Type','contour')),'the contour plot drew nothing');
mp.PlotType = 'surface';
assert(~isempty(findobj(ax,'Type','surface')),'the surface plot drew nothing');

% A map with only one axis to draw on is refused OUT LOUD, not faked.
mp.SeriesParam = 'none';
assert(~isempty(series_lines(ax)),'the map fallback drew nothing');
assert(contains(ax.Subtitle.String,'two parameters'), ...
    'the fallback from a map was silent: %s',ax.Subtitle.String);
mp.PlotType = 'auto'; mp.SeriesParam = 'Frequency';
fprintf('  PASS: lines / series / bars / heat map / contour / surface, and the fallback\n');

% --- 5. the run in progress ---------------------------------------------
stimuli = make_stimuli(freqs(1),levels);
snap    = make_snapshot(Fs,levels,nSweeps);
mp.updateLive(snap,stimuli);

V = mp.values();
live = V([V.Live]);
assert(numel(live) == numel(levels), ...
    'expected %d conditions acquiring, got %d',numel(levels),numel(live));
assert(contains(mp.Axes.Subtitle.String,'acquiring'), ...
    'the subtitle does not say a condition is still filling');
assert(~isempty(hollow_lines(mp.Axes)), ...
    'an in-progress condition was not drawn hollow');

% The live value overrides the finalized one for the same stimulus, and is
% computed from the live sweeps -- half as many as the block held.
liveOne = live(strcmp({live.Key},sprintf('%gkHz_%gdB',freqs(1),levels(1))));
assert(isscalar(liveOne),'the live condition did not merge onto its stimulus ID');
assert(liveOne.NumSweeps == nSweeps/2, ...
    'the live condition reports %d sweeps, expected %d',liveOne.NumSweeps,nSweeps/2);

mp.updateLive([],stimuli);
Vc = mp.values();
assert(~any([Vc.Live]),'clearing the snapshot left live conditions behind');
assert(isempty(hollow_lines(mp.Axes)),'a hollow marker outlived its run');
fprintf('  PASS: live conditions appear hollow, override, and clear\n');

% --- 6. repeats accumulate ----------------------------------------------
before = value_of_key(mp.values(),'8kHz_30dB','NumSweeps');
mp.addBlock(make_block(8,30,nSweeps,Fs));
after  = value_of_key(mp.values(),'8kHz_30dB','NumSweeps');
assert(after == before + nSweeps, ...
    'a repeat of one stimulus did not accumulate (%d -> %d)',before,after);
fprintf('  PASS: a repeated stimulus accumulates its sweeps\n');

% --- 7. aesthetics from the right-click menu ----------------------------
mp.PlotType = 'line'; mp.XParam = 'Level'; mp.SeriesParam = 'Frequency';
ax = mp.Axes;

assert(~isempty(ax.ContextMenu),'the axes has no context menu');
kid = series_lines(ax);
assert(~isempty(kid(1).ContextMenu), ...
    'right-clicking a plotted line would not open the menu');

fire_menu(mp.Figure,'Marker','s');
assert(strcmp(mp.Style.Marker,'s'),'the marker menu did not reach the style');
hm = series_lines(ax);
assert(strcmp(hm(1).Marker,'s'),'the marker menu did not reach the plot');

fire_menu(mp.Figure,'Grid','none');
assert(strcmp(ax.XGrid,'off') && strcmp(ax.YGrid,'off'),'Grid > none left the grid on');
fire_menu(mp.Figure,'Grid','both');
assert(strcmp(ax.XGrid,'on'),'Grid > both did not restore it');

hc = series_lines(ax);  col0 = hc(1).Color;
fire_menu(mp.Figure,'Series palette','turbo');
hc = series_lines(ax);  col1 = hc(1).Color;
assert(~isequal(col0,col1),'switching palette did not change a series colour');

fire_menu(mp.Figure,'Legend','northwest');
lgNW = get(ax,'Legend');
assert(strcmpi(lgNW.Location,'northwest'),'the legend did not move');

fire_menu(mp.Figure,'Theme','Dark');
assert(strcmp(mp.Style.Theme,'dark') && mean(ax.Color) < 0.3, ...
    'the dark theme did not reach the axes');
fire_menu(mp.Figure,'Theme','Light');

fire_menu(mp.Figure,'Axes','Label each point');
assert(mp.Style.ShowValues && ~isempty(findobj(ax,'Type','text')), ...
    'point labels were not drawn');
fire_menu(mp.Figure,'Axes','Label each point');

fire_menu(mp.Figure,'Plot type','Heat map');
assert(strcmp(mp.PlotType,'heatmap'),'the plot-type menu did not reach the setting');
fire_menu(mp.Figure,'Plot type','Auto');

% ...and the whole look resets to the shipped default.
fire_menu(mp.Figure,'','Reset aesthetics');
assert(isequal(mp.Style,mabr.ui.MetricPlot.defaultStyle()), ...
    'Reset aesthetics did not restore the default style');
fprintf('  PASS: context menu drives marker, grid, palette, legend, theme, labels, type\n');

% --- 8. refresh interval -------------------------------------------------
mp.UpdateInterval = 2.5;
assert(abs(mp.UpdateInterval - 2.5) < 1e-9,'the refresh interval was not taken');
mp.UpdateInterval = 1000;
assert(mp.UpdateInterval == 60,'the refresh interval was not clamped at the top');
mp.UpdateInterval = 0.001;
assert(mp.UpdateInterval == 0.25,'the refresh interval was not clamped at the bottom');
mp.UpdateInterval = 60;
fprintf('  PASS: refresh interval adjustable and clamped to [0.25 60] s\n');

% --- 9. a custom metric --------------------------------------------------
mp.setCustomMetric(@(c) 2*c.NumSweeps,'twice_the_sweeps');
V = mp.values();
assert(all([V.Value] == 2*[V.NumSweeps]),'the custom metric was not used');
assert(strcmp(mp.Axes.Title.String,'twice_the_sweeps'), ...
    'the plot is not titled with the custom metric''s name');

threw = false;
try
    mp.setCustomMetric(@(c) c.Sweeps,'not_a_scalar');
catch me
    threw = strcmp(me.identifier,'mabr:ui:MetricPlot:badMetric');
end
assert(threw,'a malformed custom metric was adopted');
assert(strcmp(mp.CustomName,'twice_the_sweeps'), ...
    'the rejected metric displaced the working one');
mp.Metric = 'rms';
fprintf('  PASS: custom metric adopted; a malformed one refused\n');

% --- 10. not a singleton -------------------------------------------------
mp2 = mabr.ui.MetricPlot();
cleanup2 = onCleanup(@() delete(mp2));
mp2.UpdateInterval = 60;
assert(~isequal(mp2.Figure,mp.Figure),'the second window reused the first figure');
mp2.Metric = 'snr';
assert(strcmp(mp.Metric,'rms'), ...
    'a setting on one analysis window changed another');
mp2.addBlock(make_block(8,30,nSweeps,Fs));
assert(numel(mp2.values()) == 1 && numel(mp.values()) > 1, ...
    'the two windows share a data store');
fprintf('  PASS: two independent windows, one metric each\n');

% --- 11. the numbers come back out --------------------------------------
T = mp.dataTable();
assert(height(T) == numel(mp.values()),'the table lost a condition');
assert(all(ismember({'Condition','Level','Frequency','Sweeps','InProgress'}, ...
    T.Properties.VariableNames)), ...
    'the table is missing a column: %s',strjoin(T.Properties.VariableNames,', '));
fprintf('  PASS: values export as a table\n');

fprintf('== verify_metric_plot PASSED ==\n');
end


% =====================================================================
function block = make_block(fkHz,levelDb,nSweeps,Fs)
% One condition's finalized block: a decaying 900 Hz wavelet at ~4 ms whose
% amplitude grows with level, on deterministic noise (no rng, so a failure is
% reproducible).
sweepLen = round(0.010*Fs);
period   = sweepLen + 20;
N        = nSweeps*period + period;

tw   = (0:sweepLen-1)'/Fs;
amp  = 1e-7 * 10^((levelDb-30)/40);           % a decade over the level range
wave = amp*sin(2*pi*900*tw).*exp(-max(tw-0.003,0)/0.002).*(tw >= 0.003);

data   = zeros(N,1);
onsets = (10 + (0:nSweeps-1)*period)';
for i = 1:nSweeps
    idx = onsets(i) + (0:sweepLen-1);
    data(idx) = wave + 2e-9*sin(2*pi*(31+i)*(1:sweepLen)'/Fs);
end

rec  = mabr.data.Recording(Fs,data,onsets,sweepLen,1);
id   = sprintf('%gkHz_%gdB',fkHz,levelDb);
meta = struct('ID',id,'Frequency',fkHz,'Level',levelDb, ...
              'informativeParams',{{'Frequency','Level'}}, ...
              'Label',{{['ID = ' id]}});
block = mabr.data.Block(struct('Meta',meta,'SampleRate',192000),rec);
end

function sset = make_stimuli(fkHz,levels)
% A bank whose IDs match the blocks above, so a live condition and a
% finalized one land on the same stimulus.
cfg = mabr.Config;
stim = struct('signal',{},'ID',{},'Frequency',{},'Level',{});
for k = 1:numel(levels)
    stim(k).signal    = zeros(round(0.001*cfg.DACSampleRate),1);
    stim(k).ID        = sprintf('%gkHz_%gdB',fkHz,levels(k));
    stim(k).Frequency = fkHz;
    stim(k).Level     = levels(k);
end
sset = mabr.stim.StimulusSet(stim,cfg);
end

function snap = make_snapshot(Fs,levels,nSweeps)
% What mabr.ui.AcqController.liveSnapshot hands over partway through an
% interleaved run: HALF the sweeps in, baseline and response as one segment.
sweepLen = round(0.010*Fs);
tPre     = (-sweepLen:-1)/Fs;
tPost    = (0:sweepLen-1)/Fs;

n       = nSweeps/2*numel(levels);
stimIdx = repmat(1:numel(levels),1,nSweeps/2);
S       = zeros(n,numel(tPre)+numel(tPost));
for i = 1:n
    amp = 1e-7 * 10^((levels(stimIdx(i))-30)/40);
    S(i,:) = [zeros(1,numel(tPre)) amp*sin(2*pi*900*tPost)] + ...
             2e-9*sin(2*pi*(29+i)*(1:size(S,2))/Fs);
end

snap = struct('Run',1,'SampleRate',Fs,'Time',[tPre tPost],'Sweeps',S, ...
    'StimIndex',stimIdx,'Bad',false(1,n),'Stimuli',1:numel(levels), ...
    'Labels',{arrayfun(@(L) sprintf('8kHz_%gdB',L),levels,'UniformOutput',false)});
end

function v = value_of(V,fkHz,levelDb)
v = value_of_key(V,sprintf('%gkHz_%gdB',fkHz,levelDb),'Value');
end

function v = value_of_key(V,key,field)
i = find(strcmp({V.Key},key),1);
assert(~isempty(i),'no condition named %s',key);
v = V(i).(field);
end

function h = series_lines(ax)
% The lines a legend would name: the per-series traces, newest first from
% findobj, so flip them back into the order they were drawn.
h = findobj(ax,'Type','line','-not','HandleVisibility','off');
h = flipud(h(:));
end

function h = hollow_lines(ax)
% The overlay marking conditions still being acquired.
h = findall(ax,'Type','line','HandleVisibility','off');
keep = arrayfun(@(x) ischar(x.MarkerFaceColor) && strcmp(x.MarkerFaceColor,'none'),h);
h = h(keep);
end

function fire_menu(fig,parentText,itemText)
% Press a context-menu item the way a user does. parentText disambiguates
% the submenus that share a label (both the palette and the colormap offer
% "gray"); pass '' for a top-level item.
items = findall(fig,'Type','uimenu','Text',itemText);
assert(~isempty(items),'no menu item labelled "%s"',itemText);
if ~isempty(parentText)
    keep = arrayfun(@(h) strcmp(h.Parent.Text,parentText),items);
    items = items(keep);
    assert(~isempty(items),'no "%s" under "%s"',itemText,parentText);
end
h = items(1);
h.MenuSelectedFcn(h,struct());
end

function restore_pref(had,value)
% Put the operator's own window settings back, whatever the test did to them.
if had
    setpref('MABR','MetricPlot',value);
elseif ispref('MABR','MetricPlot')
    rmpref('MABR','MetricPlot');
end
end
