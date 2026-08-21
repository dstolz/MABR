function verify_live_plot()
% verify_live_plot  Exercise the multi-stimulus live view.
%
%   Feeds mabr.ui.LivePlot synthetic sweeps from several stimuli and checks,
%   with no audio hardware and no acquisition engine:
%       1. the latest sweep gets its own axes at the top, drawn from the most
%          recent sweep only;
%       2. one running mean per stimulus, each averaging that stimulus's
%          sweeps and nothing else;
%       3. sweeps flagged as artifact are excluded from the means but still
%          reported;
%       4. Overlaid / Separate puts the means on one axes or one each;
%       5. the time base defaults to [-2 10] ms, follows TimeBase, and is
%          clamped to what was actually recorded;
%       6. amplitude scaling: each / shared / manual;
%       7. the control strip drives exactly those properties;
%       8. a call with no stimulus info still behaves as a single-mean view;
%       9. the whole view embeds into a caller-supplied container.
%
%   Run:  >> verify_live_plot
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_live_plot ==\n');

% Three stimuli with deliberately different response amplitudes, so a shared
% scale and an individual one cannot be confused for each other.
amps  = [1 4 16]*1e-7;          % V, peak -- comfortably inside the uV decade
nStim = numel(amps);
repsPer = 6;

[Y,t,stimIdx] = make_sweeps(amps,repsPer);
info = struct('StimIndex',stimIdx,'Stimuli',1:nStim, ...
              'Labels',{{'8kHz_30dB','8kHz_50dB','8kHz_70dB'}});
bad  = false(1,numel(stimIdx));

lp = mabr.ui.LivePlot();
clean = onCleanup(@() delete(lp));

% --- 1/2. latest sweep and per-stimulus means ---------------------------
lp.update(Y,t,0.42,numel(stimIdx),bad,info);

assert(isgraphics(lp.axLatest),'no latest-sweep axes');
assert(numel(lp.axLatest.Position) == 4 && ...
       lp.axLatest.Position(2) > lp.axMean(1).Position(2), ...
       'the latest sweep is not the axes at the TOP');

mult = 1e6;                                  % uV: what pickScale must choose
latest = findobj(lp.axLatest,'Type','line');
latest = latest(arrayfun(@(h) numel(h.XData) > 2,latest));
assert(isscalar(latest),'expected exactly one trace on the latest axes');
assert(max(abs(latest.YData - Y(end,:)*mult)) < 1e-9, ...
    'the latest axes is not showing the most recent sweep');

means = mean_ydata(lp);
assert(size(means,1) == nStim,'expected %d mean traces, got %d',nStim,size(means,1));
for k = 1:nStim
    want = mean(Y(stimIdx == k,:),1)*mult;
    assert(max(abs(means(k,:) - want)) < 1e-9, ...
        'mean %d is not the average of that stimulus''s sweeps',k);
end
fprintf('  PASS: latest sweep on its own top axes, %d per-stimulus means\n',nStim);

% --- 3. artifact sweeps are excluded ------------------------------------
badOne = bad;
badOne(find(stimIdx == 2,1)) = true;         % reject one sweep of stimulus 2
lp.update(Y,t,0.42,numel(stimIdx),badOne,info);
means = mean_ydata(lp);
want  = mean(Y(stimIdx == 2 & ~badOne,:),1)*mult;
assert(max(abs(means(2,:) - want)) < 1e-9, ...
    'a rejected sweep still reached the running mean');
assert(max(abs(means(1,:) - mean(Y(stimIdx == 1,:),1)*mult)) < 1e-9, ...
    'rejecting a sweep of one stimulus disturbed another''s mean');
txt = findobj(lp.axLatest,'Type','text');
assert(any(contains({txt.String},'rejected')), ...
    'the rejection was not reported on the view');
lp.update(Y,t,0.42,numel(stimIdx),bad,info);
fprintf('  PASS: artifact sweeps excluded from the means and reported\n');

% --- 4. overlaid vs separate --------------------------------------------
assert(strcmp(lp.Layout,'overlay') && isscalar(lp.axMean), ...
    'the default layout is not a single overlaid mean axes');
lp.Layout = 'separate';
assert(numel(lp.axMean) == nStim, ...
    'Separate did not give each stimulus its own axes (%d)',numel(lp.axMean));
means = mean_ydata(lp);
for k = 1:nStim
    assert(max(abs(means(k,:) - mean(Y(stimIdx == k,:),1)*mult)) < 1e-9, ...
        'mean %d is wrong after switching layout',k);
    assert(contains(lp.axMean(k).Title.String,info.Labels{k}), ...
        'panel %d is not titled with its stimulus ID',k);
end
fprintf('  PASS: Overlaid -> 1 axes, Separate -> %d titled panels\n',nStim);

% --- 5. time base --------------------------------------------------------
assert(isequal(lp.TimeBase,[-2 10]),'the default time base is not [-2 10] ms');
assert(abs(lp.axMean(1).XLim(1) - -2) < 1e-9 && abs(lp.axMean(1).XLim(2) - 10) < 1e-9, ...
    'the axes do not show the default [-2 10] ms window: %s',mat2str(lp.axMean(1).XLim));
assert(t(1)*1000 < -2,'the sweeps carry no pre-onset baseline to show');

lp.TimeBase = [-1 5];
for a = 1:numel(lp.axMean)
    assert(isequal(lp.axMean(a).XLim,[-1 5]),'panel %d ignored the new time base',a);
end
assert(isequal(lp.axLatest.XLim,[-1 5]),'the latest axes ignored the new time base');

lp.TimeBase = [-500 500];                    % wider than the data
assert(lp.axMean(1).XLim(1) >= t(1)*1000-1e-6 && ...
       lp.axMean(1).XLim(2) <= t(end)*1000+1e-6, ...
       'the time base was not clamped to the recorded window: %s', ...
       mat2str(lp.axMean(1).XLim));
lp.TimeBase = [-2 10];
fprintf('  PASS: time base defaults to [-2 10] ms, follows TimeBase, clamps\n');

% --- 6. amplitude scaling ------------------------------------------------
lp.AmpMode = 'each';
lim = arrayfun(@(a) a.YLim(2),lp.axMean);
assert(all(diff(lim) > 0), ...
    'individual scaling did not give each stimulus its own limit: %s',mat2str(lim));
for k = 1:nStim
    assert(abs(lim(k)/(max(abs(means(k,:)))*1.1) - 1) < 1e-6, ...
        'panel %d is not scaled to its own peak',k);
end

lp.AmpMode = 'common';
lim = arrayfun(@(a) a.YLim(2),lp.axMean);
assert(max(abs(diff(lim))) < 1e-9,'shared scaling left the panels on different limits');
assert(abs(lim(1)/(max(abs(means(:)))*1.1) - 1) < 1e-6, ...
    'the shared limit is not the largest response');

lp.AmpMode     = 'manual';
lp.ManualLimit = 2e-6;                        % 2 uV
lim = arrayfun(@(a) a.YLim(2),lp.axMean);
assert(max(abs(lim - 1.1*2)) < 1e-9, ...
    'manual scaling did not pin the panels to +/-2 uV: %s',mat2str(lim));
lp.update(Y*4,t,0.42,numel(stimIdx),bad,info);   % data grows...
lim2 = arrayfun(@(a) a.YLim(2),lp.axMean);
assert(isequal(lim,lim2),'a manual limit moved when the data changed');
lp.update(Y,t,0.42,numel(stimIdx),bad,info);
fprintf('  PASS: amplitude each / shared / manual\n');

% --- 7. the control strip drives the same settings ----------------------
c = live_controls(lp);
set_control(c.layout,1);                      % Overlaid
assert(strcmp(lp.Layout,'overlay'),'the layout control did not reach Layout');
set_control(c.layout,2);
assert(strcmp(lp.Layout,'separate'),'the layout control did not reach Layout');

c.t0.String = '-3'; c.t1.String = '8';
set_control(c.t1,[]);
assert(isequal(lp.TimeBase,[-3 8]),'the time fields did not reach TimeBase');
c.t0.String = '99';                           % start after the end: refused
set_control(c.t0,[]);
assert(isequal(lp.TimeBase,[-3 8]),'an invalid time base was accepted');
lp.TimeBase = [-2 10];

set_control(c.amp,1); assert(strcmp(lp.AmpMode,'each'),  'amplitude control (each)');
set_control(c.amp,2); assert(strcmp(lp.AmpMode,'common'),'amplitude control (shared)');
set_control(c.amp,3); assert(strcmp(lp.AmpMode,'manual'),'amplitude control (manual)');
% Switching into Manual seeds the limit from what is on screen rather than
% jumping to a remembered number.
assert(abs(lp.ManualLimit - max(abs(means(:)))/1e6) < 1e-12, ...
    'Manual did not seed its limit from the current view');
c.manual.String = '3';                        % 3 uV, in the displayed unit
set_control(c.manual,[]);
assert(abs(lp.ManualLimit - 3e-6) < 1e-12, ...
    'the manual field is not read in the unit it is captioned with (got %g V)', ...
    lp.ManualLimit);
assert(strcmp(c.manualUnit.String,'uV'),'the manual unit caption is wrong: %s', ...
    c.manualUnit.String);
fprintf('  PASS: control strip drives layout, time base, and amplitude\n');

% --- 8. no stimulus info => single mean ---------------------------------
lp.Layout = 'separate';
lp.AmpMode = 'common';
lp.update(Y,t,0.3,numel(stimIdx),bad);
assert(isscalar(lp.axMean),'without stimulus info the view should hold one mean axes');
means = mean_ydata(lp);
assert(max(abs(means - mean(Y,1)*mult)) < 1e-9, ...
    'the single mean is not the average of every sweep');
lp.reset();
assert(all(isnan(mean_ydata(lp))),'reset did not clear the traces');
fprintf('  PASS: legacy single-mean call still works; reset clears\n');

% --- 9. embedded in a container -----------------------------------------
% docs/Extending.md promises a host UI can pass its own container and get the
% whole view -- axes, means, and control strip -- inside it.
host = figure('Visible','off','Position',[100 100 700 520]);
cleanHost = onCleanup(@() delete(host));
panel = uipanel(host,'Position',[0 0 1 1]);
lp2 = mabr.ui.LivePlot(panel);
clean2 = onCleanup(@() delete(lp2));
lp2.Layout = 'separate';
lp2.update(Y,t,0.5,numel(stimIdx),bad,info);
assert(numel(lp2.axMean) == nStim,'the embedded view did not build its panels');
assert(isequal(ancestor(lp2.axMean(1),'figure'),host), ...
    'the embedded view did not build inside the container it was given');
assert(~isempty(findobj(lp2.CtrlPanel,'Style','popupmenu')), ...
    'the embedded view has no control strip');
fprintf('  PASS: embeds into a caller-supplied container\n');

fprintf('== verify_live_plot PASSED ==\n');
end


% =====================================================================
function [Y,t,stimIdx] = make_sweeps(amps,repsPer)
% Sweeps as the live path delivers them: baseline and response as one
% contiguous segment, so the time base runs from before the onset.
Fs = 12000;
tPre  = (-round(0.01*Fs):-1)/Fs;
tPost = (0:round(0.01*Fs))/Fs;
t     = [tPre tPost];

nStim   = numel(amps);
stimIdx = repmat(1:nStim,1,repsPer);          % interleaved A B C A B C ...
Y       = zeros(numel(stimIdx),numel(t));
wave    = sin(2*pi*700*tPost).*exp(-tPost/0.004);
for i = 1:numel(stimIdx)
    r = 1e-9*sin(2*pi*37*(1:numel(t))/Fs + i);   % deterministic "noise"
    Y(i,:) = r + [zeros(1,numel(tPre)) amps(stimIdx(i))*wave];
end
end

function M = mean_ydata(lp)
% The YData of every per-stimulus mean line, in stimulus order.
lines = gobjects(1,0);
for a = 1:numel(lp.axMean)
    h = findobj(lp.axMean(a),'Type','line');
    h = h(arrayfun(@(x) numel(x.XData) > 2 || all(isnan(x.XData)),h));
    lines = [lines h(end:-1:1)']; %#ok<AGROW>  findobj returns newest first
end
M = cell2mat(arrayfun(@(h) h.YData,lines,'UniformOutput',false)');
end

function c = live_controls(lp)
% The control strip, found the way a user would: by what it says.
p = lp.CtrlPanel;
pop  = findobj(p,'Style','popupmenu');
ed   = findobj(p,'Style','edit');
txt  = findobj(p,'Style','text');
pop  = sort_by_x(pop);  ed = sort_by_x(ed);  txt = sort_by_x(txt);
c.layout = pop(1);  c.amp = pop(2);
c.t0 = ed(1); c.t1 = ed(2); c.manual = ed(3);
c.manualUnit = txt(end);
end

function h = sort_by_x(h)
x = arrayfun(@(o) o.Position(1),h);
[~,i] = sort(x);
h = h(i);
end

function set_control(h,value)
if ~isempty(value), h.Value = value; end
h.Callback(h,struct());
end
