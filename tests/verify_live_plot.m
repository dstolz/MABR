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
%       9. stimulus PARAMETERS: conditions labelled by the parameters that
%          vary, ordered by them rather than by presentation order, and each
%          mean still holding exactly its own stimulus's sweeps after the
%          reordering;
%      10. the parameter-aware layouts -- Grid (groups across columns, the
%          within-group parameter up the rows) and Stacked (one axes per
%          group, conditions offset and named on the y axis) -- and the Group
%          control that drives them;
%      11. mabr.stim.StimulusSet.paramTable, which is where a real bank's
%          parameters come from;
%      12. the whole view embeds into a caller-supplied container.
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

% --- 9. stimulus parameters: labels and ordering -------------------------
% A Frequency x Level bank handed over in PRESENTATION order (which is not
% parameter order), with a parameter that does not vary at all mixed in.
pFreq  = [16  8 16  8 16  8];
pLevel = [50 70 30 30 70 50];
nP     = numel(pFreq);
pIDs   = arrayfun(@(f,L) sprintf('%gkHz_%gdB',f,L),pFreq,pLevel, ...
    'UniformOutput',false);
pAmps  = (1:nP)*1e-7;                         % one distinct response each
[Yp,tp,pIdx] = make_sweeps(pAmps,5);

pinfo = struct('StimIndex',pIdx,'Stimuli',1:nP,'Labels',{pIDs});
pinfo.Params = struct( ...
    'Names', {{'Frequency','Level','Polarity'}}, ...
    'Values',[pFreq(:) pLevel(:) ones(nP,1)], ...
    'Units', {{'kHz','dB',''}});
pbad = false(1,numel(pIdx));

% The order the view must impose: Frequency ascending, then Level.
[~,want] = sortrows([pFreq(:) pLevel(:)]);
want = want(:)';

lp.Layout  = 'separate';
lp.AmpMode = 'common';
lp.GroupBy = '';
lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);

assert(numel(lp.axMean) == nP,'expected %d panels, got %d',nP,numel(lp.axMean));
for k = 1:nP
    ttl = lp.axMean(k).Title.String;
    lbl = sprintf('%g kHz, %g dB',pFreq(want(k)),pLevel(want(k)));
    assert(contains(ttl,lbl), ...
        'panel %d is titled "%s", not by its parameters ("%s")',k,ttl,lbl);
    assert(~contains(ttl,'Polarity'), ...
        'a parameter that never varies reached the label: %s',ttl);
    assert(~contains(ttl,pIDs{want(k)}), ...
        'panel %d fell back to the raw stimulus ID',k);
end

% The reordering must move the MEANS with the labels, not just the captions.
means = mean_ydata(lp);
for k = 1:nP
    expect = mean(Yp(pIdx == want(k),:),1)*mult;
    assert(max(abs(means(k,:) - expect)) < 1e-9, ...
        'panel %d holds the wrong stimulus''s sweeps after reordering',k);
end

% A BLOCKED run is one condition: nothing varies within it, so the caller
% says which parameters are informative (the bank's answer, not the run's)
% and the single mean is named by them instead of by its raw ID.
kOne = 2;
sel1 = pIdx == kOne;
one  = struct('StimIndex',repmat(kOne,1,nnz(sel1)),'Stimuli',kOne, ...
              'Labels',{pIDs(kOne)});
one.Params = struct('Names',{{'Frequency','Level','Polarity'}}, ...
    'Values', [pFreq(kOne) pLevel(kOne) 1], ...
    'Varying',[true true false], ...
    'Units',  {{'kHz','dB',''}});
lp.update(Yp(sel1,:),tp,0.3,nnz(sel1),false(1,nnz(sel1)),one);
assert(isscalar(lp.axMean),'a single condition should still be one axes');
ttl = lp.axMean(1).Title.String;
assert(contains(ttl,sprintf('%g kHz, %g dB',pFreq(kOne),pLevel(kOne))), ...
    'a blocked run''s mean is not named by its parameters: %s',ttl);
assert(~contains(ttl,'Polarity'), ...
    'a parameter the caller called uninformative reached the title: %s',ttl);
assert(contains(ttl,sprintf('%d sweeps',nnz(sel1))), ...
    'the single mean did not collect its run''s sweeps: %s',ttl);
assert(max(abs(mean_ydata(lp) - mean(Yp(sel1,:),1)*mult)) < 1e-9, ...
    'the single mean is not the average of that condition''s sweeps');
lp.Layout = 'separate';
lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);       % back to the whole run
fprintf('  PASS: conditions labelled and ordered by their parameters\n');

% --- 10. Grid, Stacked, and the Group control ----------------------------
lp.Layout = 'grid';
assert(numel(lp.axMean) == nP,'Grid did not give every condition a tile');
px = arrayfun(@(a) a.Position(1),lp.axMean);
py = arrayfun(@(a) a.Position(2),lp.axMean);
assert(max(abs(diff(px(1:3)))) < 1e-9 && max(abs(diff(px(4:6)))) < 1e-9, ...
    'a frequency''s levels are not in one column: %s',mat2str(px,3));
assert(px(1) < px(4),'8 kHz is not the column left of 16 kHz');
assert(all(diff(py(1:3)) > 0) && all(diff(py(4:6)) > 0), ...
    'level does not ascend up the column: %s',mat2str(py,3));
% Only the top tile of a column names the group; every tile names its own
% level, and the grid still holds the right sweeps.
assert(any(contains(string(lp.axMean(3).Title.String),'8 kHz')), ...
    'the top tile of a column does not carry the group name');
assert(any(contains(string(lp.axMean(1).Title.String),'30 dB')), ...
    'a grid tile is not titled with its own level');
means = mean_ydata(lp);
for k = 1:nP
    expect = mean(Yp(pIdx == want(k),:),1)*mult;
    assert(max(abs(means(k,:) - expect)) < 1e-9,'grid tile %d holds the wrong sweeps',k);
end
fprintf('  PASS: Grid puts %d conditions on a 2 x 3 parameter grid\n',nP);

lp.Layout = 'stacked';
assert(numel(lp.axMean) == 2,'Stacked did not give each frequency one axes');
levels = [30 50 70];                          % what each stack holds, upward
for g = 1:2
    ax  = lp.axMean(g);
    lab = cellstr(ax.YTickLabel);
    assert(numel(ax.YTick) == 3 && numel(lab) == 3, ...
        'stack %d does not hold three levels',g);
    for j = 1:3
        assert(startsWith(lab{j},sprintf('%g dB',levels(j))), ...
            'stack %d level %d is labelled "%s"',g,j,lab{j});
    end
    assert(all(diff(ax.YTick) > 0),'stack %d is not offset upward',g);
    % Each trace is its own mean, lifted by its own offset -- nothing else.
    h = stack_lines(ax);
    for j = 1:3
        idx    = want((g-1)*3 + j);
        expect = mean(Yp(pIdx == idx,:),1)*mult + ax.YTick(j);
        assert(max(abs(h(j).YData - expect)) < 1e-9, ...
            'stack %d trace %d is not its mean at its offset',g,j);
    end
end
assert(contains(lp.axMean(1).Title.String,'8 kHz'), ...
    'a stack is not titled with the group it holds');
fprintf('  PASS: Stacked gives one offset, y-labelled stack per group\n');

c = live_controls(lp);
items = cellstr(c.group.String);
assert(isequal(items(:)',{'Auto','None','Frequency','Level'}), ...
    'the Group menu does not offer exactly this run''s varying parameters: %s', ...
    strjoin(items(:)',','));
set_control(c.group,4);                       % group by Level instead
assert(strcmp(lp.GroupBy,'Level'),'the Group control did not reach GroupBy');
assert(numel(lp.axMean) == 3,'grouping by Level did not give three stacks');
set_control(c.group,2);                       % None
assert(isscalar(lp.axMean),'"None" still divided the conditions into groups');
assert(numel(findobj(lp.axMean(1),'Type','line')) == nP, ...
    'the ungrouped stack does not hold every condition');
set_control(c.group,1);                       % back to Auto
assert(isempty(lp.GroupBy) && numel(lp.axMean) == 2, ...
    'Auto did not go back to grouping by Frequency');
fprintf('  PASS: the Group control regroups the view\n');

% --- 11. where a real bank's parameters come from ------------------------
bank = mabr.stim.demoStimuli(mabr.Config,'Frequencies',[8 16],'Levels',[30 60]);
P = bank.paramTable();
assert(all(ismember({'Frequency','Level'},P.Names)), ...
    'paramTable did not report the bank''s parameters: %s',strjoin(P.Names,','));
assert(size(P.Values,1) == bank.numStimuli && size(P.Values,2) == numel(P.Names), ...
    'paramTable values do not line up with the bank');
jF = find(strcmp(P.Names,'Frequency'),1);
jL = find(strcmp(P.Names,'Level'),1);
assert(isequal(sort(unique(P.Values(:,jF)))',[8 16]) && ...
       isequal(sort(unique(P.Values(:,jL)))',[30 60]), ...
    'paramTable read the wrong values off the bank');
assert(strcmp(P.Units{jF},'kHz') && strcmp(P.Units{jL},'dB'), ...
    'paramTable did not carry the units the toolbox fixes by name');
assert(P.Varying(jF) && P.Varying(jL),'a parameter that varies was called constant');
jP = find(strcmp(P.Names,'Polarity'),1);
assert(~isempty(jP) && ~P.Varying(jP), ...
    'a parameter held constant across the bank was called varying');
sub = bank.paramTable(1:2);                   % one frequency, both levels
assert(size(sub.Values,1) == 2 && ~sub.Varying(jF) && sub.Varying(jL), ...
    'paramTable of a subset does not describe the subset');
fprintf('  PASS: StimulusSet.paramTable describes a bank and any subset\n');

% --- 12. embedded in a container ----------------------------------------
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

function h = stack_lines(ax)
% The mean traces on one stacked axes, in the order they were created (which
% is the order they are offset in). findobj returns newest first.
h = findobj(ax,'Type','line');
h = h(end:-1:1);
end

function c = live_controls(lp)
% The control strip, found the way a user would: by what it says.
p = lp.CtrlPanel;
pop  = findobj(p,'Style','popupmenu');
ed   = findobj(p,'Style','edit');
txt  = findobj(p,'Style','text');
pop  = sort_by_x(pop);  ed = sort_by_x(ed);  txt = sort_by_x(txt);
c.layout = pop(1);  c.group = pop(2);  c.amp = pop(3);
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
