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
%       6. amplitude scaling: each / shared / manual, plus the latest
%          sweep's own limit -- quantized to 1-2-5 rungs, stepping up at
%          once and down only after the smaller rung has held;
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
%      12. ERROR BANDS: the SD / SEM / confidence-interval patch drawn around
%          each mean, the statistics behind them (mabr.metrics.error_band and
%          mabr.metrics.t_quantile), and the axis limits growing to fit;
%      13. the right-click menu that chooses one;
%      14. the whole view embeds into a caller-supplied container;
%      15. the onset-contrast (rho_post - rho_pre) bar is drawn for a
%          blocked run and dropped for an intermixed one, the trace taking
%          back the width it leaves;
%      16. every axes has at least as much room to its left as its own y
%          labels take -- in every layout, at any window size -- so a
%          condition name in a stack is never clipped off the panel or
%          drawn over the tile beside it;
%      17. the arrangement can be changed WHILE sweeps are arriving without
%          leaving the old axes behind: render() is not re-entrant, and a
%          rebuild sweeps up anything on the panel it is not holding.
%
%   Run:  >> verify_live_plot
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_live_plot ==\n');

% The live view now opens on the display settings last CHOSEN in one
% (mabr.ui.LivePlot.loadDefaults) and writes them back whenever the control
% strip or the right-click menu is used -- both of which this script does. So
% the pref is taken out of the way for the duration and put back exactly as it
% was, or every assertion here would depend on how the user last left their
% own window, and running the suite would rearrange it.
hadLivePref = ispref('MABR','LivePlot');
if hadLivePref
    oldLivePref = getpref('MABR','LivePlot');
    rmpref('MABR','LivePlot');
else
    oldLivePref = [];
end
restoreLivePref = onCleanup(@() restore_live_pref(hadLivePref,oldLivePref)); %#ok<NASGU>

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

% --- 6b. the latest sweep's limit moves in discrete steps ---------------
% A single sweep is redrawn at the live tick rate, and a limit tracking its
% peak makes the ruler grow with the thing being measured -- every sweep then
% looks the same size, which is the one comparison a raw sweep is watched for.
% The limit stands on a 1-2-5 ladder instead: up the instant a sweep would not
% fit, held while the peak stays inside the rung, and down only after the
% smaller rung has been enough for several refreshes running.
lp.AmpMode = 'common';
lp.reset();

qInfo = struct('StimIndex',ones(1,4),'Stimuli',1,'Labels',{{'q'}});
qBad  = false(1,4);
qUpd  = @(pk) lp.update(flat_sweeps(t,pk,4),t,0,4,qBad,qInfo);

qUpd(1.2e-6);
assert(abs(lp.axLatest.YLim(2) - 2) < 1e-9, ...
    'the latest axes did not snap to the 2 uV rung: %s',mat2str(lp.axLatest.YLim));
assert(abs(lp.axLatest.YLim(1) + 2) < 1e-9, ...
    'the latest axes is not symmetric about zero: %s',mat2str(lp.axLatest.YLim));
qUpd(1.9e-6);                       % ... a bigger sweep, still inside the rung
assert(abs(lp.axLatest.YLim(2) - 2) < 1e-9, ...
    'the latest axes moved for a peak inside its own rung: %s', ...
    mat2str(lp.axLatest.YLim));
qUpd(3.0e-6);                       % ... one the rung cannot hold
assert(abs(lp.axLatest.YLim(2) - 5) < 1e-9, ...
    'the latest axes did not step UP at once: %s',mat2str(lp.axLatest.YLim));
qUpd(0.3e-6);                       % ... and one far below it
assert(abs(lp.axLatest.YLim(2) - 5) < 1e-9, ...
    'the latest axes shrank on the first quiet sweep');
nHold = 1;
while abs(lp.axLatest.YLim(2) - 5) < 1e-9 && nHold < 60
    qUpd(0.3e-6); nHold = nHold + 1;
end
assert(abs(lp.axLatest.YLim(2) - 0.5) < 1e-9, ...
    'the latest axes never stepped down to the 0.5 uV rung: %s', ...
    mat2str(lp.axLatest.YLim));
assert(nHold > 2,'the step down was not held off at all');

% A manual limit frames the MEANS; the latest sweep is tens of times one and
% keeps its own rung, or it would be clipped off the axes entirely.
lp.AmpMode     = 'manual';
lp.ManualLimit = 2e-6;
qUpd(3.0e-6);
assert(abs(lp.axLatest.YLim(2) - 5) < 1e-9, ...
    'a manual limit reached the latest sweep: %s',mat2str(lp.axLatest.YLim));

lp.reset();                         % the next run scales on its own evidence
qUpd(0.3e-6);
assert(abs(lp.axLatest.YLim(2) - 0.5) < 1e-9, ...
    'reset did not clear the rung the run before had reached: %s', ...
    mat2str(lp.axLatest.YLim));

lp.ManualLimit = 2e-6;              % leave section 7 the state section 6 left
lp.update(Y,t,0.42,numel(stimIdx),bad,info);
fprintf('  PASS: latest sweep scales in rungs, %d refreshes before shrinking\n',nHold);

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

% --- 12. error bands -----------------------------------------------------
% The arithmetic first, on its own: a band is a claim about the data, and a
% plausible-looking shaded region computed the wrong way is worse than none.
assert(abs(mabr.metrics.t_quantile(0.975,10) - 2.228138852) < 1e-6, ...
    't_quantile(0.975,10) should be the table value 2.2281');
assert(abs(mabr.metrics.t_quantile(0.975,1) - 12.70620474) < 1e-6, ...
    't_quantile(0.975,1) should be the table value 12.7062');
assert(abs(mabr.metrics.t_quantile(0.975,1e6) - 1.959963985) < 1e-4, ...
    't_quantile should approach the normal quantile as nu grows');
assert(abs(mabr.metrics.t_quantile(0.5,7)) < 1e-12, ...
    'the median of a t distribution is 0');
assert(abs(mabr.metrics.t_quantile(0.025,10) + 2.228138852) < 1e-6, ...
    't_quantile is not symmetric about zero');
assert(all(isnan(mabr.metrics.t_quantile([0 1 0.5],[5 5 0]))), ...
    'a degenerate p or nu should give NaN rather than a number or an error');

nSw = 5;                                      % sweeps per condition, above
oneCond = Yp(pIdx == 1,:);
assert(all(isnan(mabr.metrics.error_band(oneCond(1,:),'sem'))), ...
    'a single sweep has no spread to report, so the band must be NaN');
assert(max(abs(mabr.metrics.error_band(oneCond,'std') - std(oneCond,0,1))) < 1e-18, ...
    'the std band is not the sample standard deviation');
assert(max(abs(mabr.metrics.error_band(oneCond,'sem') - std(oneCond,0,1)/sqrt(nSw))) < 1e-18, ...
    'the SEM band is not std/sqrt(n)');

lp.Layout  = 'separate';
lp.AmpMode = 'common';
assert(strcmp(lp.ErrorBand,'none'),'the default view should draw no band');
bands = band_patches(lp);
assert(numel(bands) == nP,'expected one band patch per panel');
assert(all(arrayfun(@(h) all(isnan(h.YData(:))),bands)), ...
    'a band was drawn with ErrorBand ''none''');

for mode = {'std','sem','ci'}
    lp.ErrorBand = mode{1};
    bands = band_patches(lp);
    for k = 1:nP
        Ysel = Yp(pIdx == want(k),:);
        hw   = expected_halfwidth(Ysel,mode{1},lp.ConfidenceLevel);
        [lo,hi] = band_edges(bands(k));
        assert(max(abs(lo - (mean(Ysel,1)-hw)*mult)) < 1e-9 && ...
               max(abs(hi - (mean(Ysel,1)+hw)*mult)) < 1e-9, ...
            'the %s band on panel %d is not mean +/- the right half-width',mode{1},k);
        assert(isequal(bands(k).XData(:).',[t_ms(lp) fliplr(t_ms(lp))]), ...
            'the %s band on panel %d is not a closed polygon over the time base', ...
            mode{1},k);
    end
end
fprintf('  PASS: SD / SEM / CI bands drawn as mean +/- the right half-width\n');

% A wider confidence level is a wider band -- the one thing a reader would
% assume without checking, and the one a wrong tail probability would break.
lp.ErrorBand = 'ci';
lp.ConfidenceLevel = 0.90;  w90 = band_width(band_patches(lp),1);
lp.ConfidenceLevel = 0.99;  w99 = band_width(band_patches(lp),1);
assert(w99 > w90,'a 99%% band is not wider than a 90%% one (%g vs %g)',w99,w90);

% An SD band describes a single SWEEP, which on an ABR is tens of times the
% average -- so it is drawn but is deliberately NOT allowed to set the scale,
% or every mean in the window would be squashed to a flat line.
lp.ErrorBand = 'none'; limNone = lp.axMean(1).YLim(2);
lp.ErrorBand = 'std';  limStd  = lp.axMean(1).YLim(2);
assert(abs(limStd - limNone) < 1e-12, ...
    'an SD band was allowed to drive the amplitude scale (%g -> %g)',limNone,limStd);
assert(contains(lp.axMean(1).YLabel.String,'SD'), ...
    'the y label does not say which statistic the band is: %s', ...
    lp.axMean(1).YLabel.String);

% A SEM band DOES describe the mean, so it is framed rather than clipped: the
% shared limit is the outermost edge of the widest one.
lp.ErrorBand = 'sem';
Aall = 0;
for k = 1:nP
    Ysel = Yp(pIdx == want(k),:);
    Aall = max(Aall,max(abs(mean(Ysel,1)) + std(Ysel,0,1)/sqrt(nSw)));
end
lim = arrayfun(@(a) a.YLim(2),lp.axMean);
assert(max(abs(lim - 1.1*Aall*mult)) < 1e-9, ...
    'the axes are scaled to the means, not to the outside of their SEM bands');
assert(lim(1) > limNone,'the SEM band did not widen the axes at all');

lp.ErrorBand = 'none';
assert(all(arrayfun(@(h) all(isnan(h.YData(:))),band_patches(lp))), ...
    'turning the band off did not clear the patches');
fprintf('  PASS: bands widen with confidence, fit inside the axes, and clear\n');

% --- 13. the right-click menu picks the statistic ------------------------
% Found by what it offers rather than by being the only one in the figure --
% MATLAB creates context menus of its own for the figure's own furniture.
cm = findall(lp.Figure,'Type','uicontextmenu');
cm = cm(arrayfun(@(c) ~isempty(findall(c,'Type','uimenu','Label','Error band')),cm));
assert(isscalar(cm),'the live plot has no single Error band right-click menu');
assert(isequal(lp.PlotPanel.ContextMenu,cm) && isequal(lp.axMean(1).ContextMenu,cm), ...
    'the right-click menu is not attached to the plot region and its axes');
assert(strcmp(band_item(cm,'None').Checked,'on'), ...
    '"None" is not ticked while no band is shown');

fire_menu(band_item(cm,'± 1 SEM'));
assert(strcmp(lp.ErrorBand,'sem'),'the menu did not set the band statistic');
assert(strcmp(band_item(cm,'± 1 SEM').Checked,'on') && ...
       strcmp(band_item(cm,'None').Checked,'off'), ...
    'the tick did not follow the selection');

fire_menu(band_item(cm,'99% confidence'));
assert(strcmp(lp.ErrorBand,'ci') && abs(lp.ConfidenceLevel - 0.99) < 1e-12, ...
    'the menu did not set both the statistic and its confidence level');
assert(strcmp(band_item(cm,'95% confidence').Checked,'off'), ...
    'two confidence levels are ticked at once');
assert(contains(lp.axMean(1).YLabel.String,'99'), ...
    'the y label does not name the confidence level in force');

fire_menu(band_item(cm,'None'));
assert(strcmp(lp.ErrorBand,'none') && ...
       all(arrayfun(@(h) all(isnan(h.YData(:))),band_patches(lp))), ...
    'the menu did not turn the band back off');
fprintf('  PASS: the right-click menu drives the band and ticks what is shown\n');

% --- 14. embedded in a container ----------------------------------------
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

% --- 15. the onset-contrast bar only appears for a blocked run -----------
% rho_post - rho_pre watches ONE condition's average converge. An intermixed
% run pools several into that average, so the number means nothing and the
% bar is not drawn -- the same reason AcqController evaluates no advance
% criterion for those runs. The strategy is the authority (info.Intermixed);
% with none stated, a run presenting more than one stimulus is intermixed.
lp3 = mabr.ui.LivePlot();
clean3 = onCleanup(@() delete(lp3));

oneInfo = struct('StimIndex',ones(1,repsPer),'Stimuli',1,'Labels',{{'8kHz_30dB'}});
oneY    = Y(stimIdx == 1,:);
lp3.update(oneY,t,0.42,repsPer,false(1,repsPer),oneInfo);
corrBar = findobj(lp3.axCorr,'Type','bar');
assert(vis_on(lp3.axCorr), ...
    'a blocked run should keep the onset-contrast bar');
assert(isscalar(corrBar) && vis_on(corrBar), ...
    'the bar itself stayed hidden on a blocked run');
assert(abs(corrBar.YData - 0.42) < 1e-9, ...
    'the bar does not carry the correlation it was given');
% Its RIGHT edge is what the bar hands back and forth; the left one belongs
% to the y labels and is measured from them (see 16).
narrowRight = sum(lp3.axLatest.Position([1 3]));

% Intermixed by strategy, even though every sweep so far is one stimulus.
oneInfo.Intermixed = true;
lp3.update(oneY,t,0.42,repsPer,false(1,repsPer),oneInfo);
assert(~vis_on(lp3.axCorr), ...
    'an intermixed run still shows the onset-contrast bar');
assert(~vis_on(corrBar), ...
    'the axes was hidden but the bar inside it was left drawn');
assert(sum(lp3.axLatest.Position([1 3])) > narrowRight + 1e-6, ...
    'the latest-sweep axes did not take back the width the bar left');

% ... and inferred where the caller says nothing: three stimuli in one run.
lp3.update(Y,t,0.42,numel(stimIdx),bad,info);
assert(~vis_on(lp3.axCorr), ...
    'a run presenting several stimuli should be taken as intermixed');

% Back to blocked: the bar returns rather than having been destroyed.
lp3.update(oneY,t,0.31,repsPer,false(1,repsPer),rmfield(oneInfo,'Intermixed'));
assert(vis_on(lp3.axCorr) && vis_on(corrBar), ...
    'the bar did not come back for the next blocked run');
assert(abs(corrBar.YData - 0.31) < 1e-9,'the restored bar did not update');
assert(abs(sum(lp3.axLatest.Position([1 3])) - narrowRight) < 1e-9, ...
    'the latest-sweep axes did not give the width back');
fprintf('  PASS: onset-contrast bar shown for blocked runs, dropped for intermixed\n');

% --- 16. the y axis labels always have room ------------------------------
% The widest thing on a y axis is a three-digit microvolt number in most
% layouts and a whole condition name ("60 dB (136)") in Stacked, where EVERY
% column of stacks is labelled rather than just the leftmost. A fixed margin
% cannot be right for both, and getting it wrong does not merely crop a
% label: it draws it over the tile to its left. So the view measures what
% the labels take and re-tiles around them (LivePlot.fitLabelGutters), and
% what that has to guarantee is exactly this.
lp.AmpMode = 'common';
lp.GroupBy = '';
for layout = {'overlay','separate','grid','stacked'}
    lp.Layout = layout{1};
    lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);
    assert_labels_fit(lp,layout{1});
end

% ... and under 'each', where every tile is on its own scale and therefore
% carries its own numbers rather than repeating its neighbour's.
lp.Layout  = 'separate';
lp.AmpMode = 'each';
lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);
assert_labels_fit(lp,'separate/each');

% A resized window is a new question: the gutters are FRACTIONS of the panel,
% so the same labels take a different share of a narrower one.
lp.Layout  = 'stacked';
lp.AmpMode = 'common';
lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);
for w = [560 1400 700]
    pos = lp.Figure.Position; pos(3) = w;
    lp.Figure.Position = pos;
    drawnow;
    lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);
    assert_labels_fit(lp,sprintf('stacked at %d px',w));
end
fprintf('  PASS: y axis labels have room in every layout, at any width\n');

% --- 17. changing the arrangement mid-run leaves nothing behind ----------
% legend() and drawnow both process the event queue, so a live tick can land
% INSIDE a render started by the control strip. The inner call rebuilds the
% mean axes the outer one is still holding handles to -- which leaves the
% outer's axes orphaned on the panel, drawn over the new ones with a stale
% run on them, and the outer call writing captions onto somebody else's
% axes (or indexing past the end of an emptied list). render() is therefore
% not re-entrant, and buildMeanAxes additionally sweeps up any axes on the
% panel it is not holding, so an orphan from ANY cause cannot outlive the
% next change of arrangement.
lp.Layout = 'overlay';
lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);
planted = axes('Parent',lp.PlotPanel,'Units','normalized', ...
    'Position',[0.1 0.15 0.8 0.3]);                 % an orphan, by hand
lp.Layout = 'stacked';
lp.update(Yp,tp,0.4,numel(pIdx),pbad,pinfo);
assert(~isgraphics(planted), ...
    'a rebuild left an untracked axes on the panel');
assert(stray_axes(lp) == 0,'the panel still holds axes the view has lost');

% ... and the same thing for real: sweeps arriving from a timer, as
% acquisition delivers them, while the "user" changes the arrangement.
% The timer's own UserData carries the verdict: an anonymous ErrorFcn has
% nowhere else to put one, and a tick that throws is exactly the other face
% of this bug (a render indexing past an axes list an inner call emptied).
tk = timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
    'UserData',false,'TimerFcn',@(~,~) live_tick(lp,Yp,tp,pbad,pinfo), ...
    'ErrorFcn',@(src,~) set(src,'UserData',true));
cleanTimer = onCleanup(@() stop_timer(tk));
modes = {'overlay','stacked','grid','separate'};
start(tk);
t0 = tic; i = 0; worst = 0;
while toc(t0) < 3
    i = i + 1;
    lp.Layout = modes{mod(i-1,numel(modes))+1};
    drawnow; pause(0.005);
    worst = max(worst,stray_axes(lp));
end
stop(tk); drawnow;
assert(~tk.UserData,'a live tick errored while the arrangement was changing');
assert(worst == 0 && stray_axes(lp) == 0, ...
    'changing the arrangement under a live timer left %d axes behind',worst);
fprintf('  PASS: %d arrangement changes under a live timer, nothing left behind\n',i);

fprintf('== verify_live_plot PASSED ==\n');
end


% =====================================================================
function restore_live_pref(had,value)
% Put the user's live-view preference back exactly as it was -- including
% "there wasn't one".
if had
    setpref('MABR','LivePlot',value);
elseif ispref('MABR','LivePlot')
    rmpref('MABR','LivePlot');
end
end

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

function Y = flat_sweeps(t,pk,n)
% n identical sweeps whose peak is EXACTLY pk, so the rung the view lands on
% is arithmetic rather than an approximation.
w = sin(2*pi*700*t).*exp(-t/0.004);
w(t < 0) = 0;                       % the pre-onset baseline is silent
Y = repmat(pk*w/max(abs(w)),n,1);
end

function assert_labels_fit(lp,what)
% Every visible axes in the view has at least as much room to the left of it
% as its own y labels take. TightInset(1) IS that width -- the tick labels
% plus the y label where there is one -- and the room is the distance back to
% whatever sits to its left on the same rows, or to the panel edge where
% nothing does.
drawnow;
ax = [lp.axMean(:).' lp.axLatest lp.axCorr];
ax = ax(arrayfun(@(h) isgraphics(h) && vis_on(h),ax));
for i = 1:numel(ax)
    pos  = ax(i).Position;
    ti   = ax(i).TightInset;
    room = pos(1);                          % ... back to the panel's edge
    for j = 1:numel(ax)
        if j == i, continue; end
        bp = ax(j).Position;
        if bp(2) >= pos(2)+pos(4)-1e-9 || pos(2) >= bp(2)+bp(4)-1e-9
            continue                        % a different row: no obstacle
        end
        r = bp(1) + bp(3);
        if r <= pos(1) + 1e-9, room = min(room,pos(1)-r); end
    end
    assert(room >= ti(1) - 1e-6, ...
        ['%s: the y labels of axes %d take %.3f of the panel and have ' ...
         '%.3f of room -- they are drawn over what is to their left'], ...
        what,i,ti(1),room);
end
end

function live_tick(lp,Y,t,bad,info)
if isvalid(lp), lp.update(Y,t,0.4,size(Y,1),bad,info); end
end

function stop_timer(tk)
try, stop(tk); catch, end
try, delete(tk); catch, end
end

function k = stray_axes(lp)
% Axes on the plot panel that the view is no longer holding a handle to.
keep = [lp.axMean(:); lp.axLatest(:); lp.axCorr(:)];
keep = keep(isgraphics(keep));
ax = findobj(lp.PlotPanel,'-depth',1,'Type','axes');
for j = numel(ax):-1:1
    if any(ax(j) == keep), ax(j) = []; end
end
k = numel(ax);
end

function tf = vis_on(h)
% Visible reads back as a char in some releases and an OnOffSwitchState in
% others; string() flattens both.
tf = strcmp(string(h.Visible),"on");
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

function P = band_patches(lp)
% The error-band patch of every mean, in panel order (one per axes in the
% Separate layout, which is what the band checks use).
P = gobjects(1,0);
for a = 1:numel(lp.axMean)
    h = findobj(lp.axMean(a),'Type','patch');
    P = [P h(end:-1:1)']; %#ok<AGROW>  findobj returns newest first
end
end

function [lo,hi] = band_edges(h)
% A band patch is the lower edge left-to-right then the upper edge back, so
% the second half reversed is the upper edge sample for sample.
y  = h.YData(:).';
n  = numel(y)/2;
lo = y(1:n);
hi = fliplr(y(n+1:end));
end

function w = band_width(P,k)
[lo,hi] = band_edges(P(k));
w = max(hi - lo);
end

function t = t_ms(lp)
% The time base the view is drawing on, in ms, read back off a mean trace.
h = findobj(lp.axMean(1),'Type','line');
h = h(arrayfun(@(x) numel(x.XData) > 2,h));
t = h(end).XData;
end

function hw = expected_halfwidth(Y,mode,conf)
n  = size(Y,1);
sd = std(Y,0,1);
switch mode
    case 'std', hw = sd;
    case 'sem', hw = sd/sqrt(n);
    case 'ci',  hw = mabr.metrics.t_quantile(1-(1-conf)/2,n-1)*sd/sqrt(n);
end
end

function h = band_item(cm,label)
h = findall(cm,'Type','uimenu','Label',label);
assert(isscalar(h),'expected exactly one "%s" entry in the right-click menu',label);
end

function fire_menu(h)
h.Callback(h,struct());
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
