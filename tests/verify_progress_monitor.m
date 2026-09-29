function verify_progress_monitor()
% verify_progress_monitor  Exercise the acquisition progress window.
%
%   Drives mabr.ui.ProgressMonitor against a real mabr.stim.Schedule with no
%   audio hardware, no acquisition engine and no parallel pool, and checks:
%       1. the tally -- planned presentations per stimulus, and what a
%          recorded run credits;
%       2. the simple view: NO plot at all, and a window sized down to suit --
%          and grown back when a plot view is asked for;
%       3. counts / percent / none, on the bars and in the header;
%       4. bars grouped by stimulus and by a stimulus parameter, aggregating
%          the right entries into the right bar;
%       5. a finished condition is coloured differently from an unfinished one;
%       6. the heat map: two parameters, the counts overlay, and a HOLE where
%          the bank has no such condition;
%       7. following a controller: sweeps counted mid-run against the run's
%          own sequence, and NOT counted twice once the run is credited;
%       8. artifact make-up enlarging the denominator;
%       9. the refresh rate limit, and force overriding it;
%      10. the control strip driving exactly the public properties;
%      11. always-on-top, and the embedded form;
%      12. stimulation only: the header clock runs with no live metrics to
%          drive it, the run's presentations are estimated from it, a pause
%          (read off the engine, not the program state) holds both, and the
%          recorded count replaces the estimate once the run is credited;
%      13. a window opened mid-session does not claim the session began when
%          it opened.
%
%   Along the way: the header's run and plan lines, the percentage in the
%   window title, the heat map outlining the conditions being presented and
%   hatching the ones the plan lacks, and a run's sweeps staying in the tally
%   between the end of the run and its credit (the finalization gap the DSP
%   worker leaves).
%
%   Run:  >> verify_progress_monitor
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_progress_monitor ==\n');

% The window persists an always-on-top preference and the height its plot
% views were last left at; a verification run must not leave the rig's own
% settings changed.
prefNames = {'ProgressOnTop','ProgressPlotHeight'};
hadPref = false(1,numel(prefNames));
oldPref = cell(1,numel(prefNames));   % defined either way: a closure captures them now
for iP = 1:numel(prefNames)
    hadPref(iP) = ispref('MABR',prefNames{iP});
    if hadPref(iP), oldPref{iP} = getpref('MABR',prefNames{iP}); end
end
restorePref = onCleanup(@() restore_prefs(prefNames,hadPref,oldPref));

cfg  = mabr.Config;
% 3 frequencies x 2 levels = 6 entries, in that order:
%   (8,30) (8,60) (16,30) (16,60) (32,30) (32,60)
bank = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16 32],'Levels',[30 60], ...
                             'PipDuration',0.002);
reps = [10 20 30 40 50 60];

sch = mabr.stim.Schedule(bank,cfg);
sch.Strategy    = 'conventional';
sch.Repetitions = reps;
sch.ISI         = 0.02;
sch.build();

pm = mabr.ui.ProgressMonitor();
clean = onCleanup(@() delete(pm));
pm.attach(sch,bank);

% --- 1. the tally -------------------------------------------------------
assert(isequal(pm.Targets,reps), ...
    'planned presentations wrong: %s',mat2str(pm.Targets));
assert(all(pm.Counts == 0),'nothing has been recorded, yet something is counted');

sch.recordRun(1,[10 0 0 0 0 0]);   % run 1 finished: 10 presentations of stim 1
sch.advance();
pm.refresh(true);
assert(isequal(pm.Counts,[10 0 0 0 0 0]), ...
    'a recorded run did not reach the tally: %s',mat2str(pm.Counts));
[~,~,~,det] = pm.headerText();
assert(contains(det,'1 of 6 conditions complete') && contains(det,'210 presentations in 6 runs'), ...
    'between runs the header should describe the plan; it reads "%s"',det);
fprintf('  PASS: planned and recorded presentations tallied per stimulus\n');

% --- 2/3. simple view: no plot, a small window, and the header numbers ---
% The default view, so this is also what the window opened as.
assert(strcmp(pm.View,'simple'),'the monitor should open in the simple view');
assert(~pm.hasPlot(),'the simple view should draw no plot');
assert(isempty(pm.TrackPatch) && isempty(pm.FillPatch) && isempty(pm.ValueText), ...
    'the simple view left bars on the axes');
compactH = pm.Figure.Position(4);
assert(compactH < 220, ...
    'the plotless window is %g px tall -- it should be sized to its two strips',compactH);

% Everything this view reports is in the header.
pct = pm.headerText();
assert(strcmp(pct,sprintf('%d / %d',10,sum(reps))), ...
    'the header reads "%s" under Counts',pct);
pm.Labels = 'percent';
pct = pm.headerText();
assert(strcmp(pct,sprintf('%.0f%%',100*10/sum(reps))), ...
    'the header reads "%s" under Percent',pct);
pm.Labels = 'counts';

% Asking for a plot grows the window; going without one shrinks it again. The
% width means the same thing either way, so it is left alone, and the top edge
% is held so the window does not jump out from under the pointer.
% Somewhere with room below it: growing a window that would otherwise hang off
% the bottom of the screen legitimately moves its top edge, and that clamping
% is not what this check is about.
pm.Figure.Position(2) = 420;
w0   = pm.Figure.Position(3);
top0 = sum(pm.Figure.Position([2 4]));
pm.View = 'bars';
assert(pm.hasPlot(),'the bars view should draw a plot');
plotH = pm.Figure.Position(4);
assert(plotH > compactH + 100, ...
    'asking for a plot left the window at %g px -- it should have grown',plotH);
assert(pm.Figure.Position(3) == w0,'switching views changed the window width');
assert(abs(sum(pm.Figure.Position([2 4])) - top0) < 1, ...
    'the window did not keep its top edge across the resize');
pm.View = 'simple';
assert(abs(pm.Figure.Position(4) - compactH) < 1, ...
    'going back to the plotless view left the window %g px tall',pm.Figure.Position(4));
fprintf('  PASS: simple view is plotless and compact; a plot view grows the window\n');

% --- 4. bars, by stimulus and by parameter ------------------------------
pm.View    = 'bars';
pm.GroupBy = 'Stimulus';
f = bar_fracs(pm);
assert(numel(f) == 6,'expected one bar per stimulus, got %d',numel(f));
assert(abs(f(1) - 1) < 1e-9 && all(f(2:end) == 0), ...
    'per-stimulus bars are wrong: %s',mat2str(f));

pm.GroupBy = 'Level';
% Level 30 is stimuli 1,3,5 (10+30+50 = 90 planned, 10 done); level 60 is
% 2,4,6 (20+40+60 = 120 planned, none done).
f = bar_fracs(pm);
assert(numel(f) == 2,'grouping by Level should give 2 bars, got %d',numel(f));
assert(abs(f(1) - 10/90) < 1e-9 && f(2) == 0, ...
    'Level grouping aggregated the wrong entries: %s',mat2str(f));
lab = strtrim(string(pm.Axes.YTickLabel));
assert(isequal(lab(:)',["30" "60"]),'the Level bars are labelled %s',join(lab,','));
txt = {pm.ValueText.String};
assert(strcmp(txt{1},'10/90'),'the Level 30 bar reads "%s"',txt{1});

pm.Labels = 'percent';
txt = {pm.ValueText.String};
assert(strcmp(txt{1},sprintf('%.0f%%',100*10/90)), ...
    'the Level 30 bar reads "%s" under Percent',txt{1});
pm.Labels = 'none';
assert(all_hidden(pm.ValueText),'None left the bar values on screen');
pm.Labels = 'counts';

pm.GroupBy = 'Frequency';
f = bar_fracs(pm);
assert(numel(f) == 3,'grouping by Frequency should give 3 bars, got %d',numel(f));
assert(abs(f(1) - 10/30) < 1e-9,'Frequency grouping is wrong: %s',mat2str(f));
fprintf('  PASS: bars by stimulus, by Level, and by Frequency\n');

% --- 5. a finished condition looks different ----------------------------
pm.GroupBy = 'Stimulus';
C = pm.FillPatch.FaceVertexCData;
assert(~isequal(C(1,:),C(2,:)), ...
    'a completed condition is drawn the same colour as an untouched one');
fprintf('  PASS: completed conditions are coloured apart from unfinished ones\n');

% --- 6. the heat map, and a hole in the design --------------------------
pm.View = 'heatmap';
assert(strcmp(pm.HeatX,'Frequency') && strcmp(pm.HeatY,'Level'), ...
    'the heat map did not default to frequency across / level up (%s / %s)', ...
    pm.HeatX,pm.HeatY);
CD = pm.HeatImage.CData;
assert(isequal(size(CD),[2 3]),'the heat map is %s, expected 2x3',mat2str(size(CD)));
assert(abs(CD(1,1) - 1) < 1e-9,'the finished condition is not full in the heat map');
assert(all(CD(2:end) == 0),'unstarted conditions are not empty in the heat map');
assert(all(pm.HeatImage.AlphaData(:) == 1), ...
    'a full factorial bank should have no empty heat-map cells');
assert(n_marks(pm.HoleHatch,9) == 0,'a full factorial bank has hatched cells');
assert(strcmp(pm.Axes.XLabel.String,'Frequency (kHz)'), ...
    'the heat map''s axis should carry the parameter''s unit, not "%s"',pm.Axes.XLabel.String);
assert(strcmp(pm.HeatText(1,1).String,'10/10'), ...
    'the counts overlay reads "%s"',pm.HeatText(1,1).String);
pm.Labels = 'percent';
assert(strcmp(pm.HeatText(1,1).String,'100%'), ...
    'the percent overlay reads "%s"',pm.HeatText(1,1).String);
pm.Labels = 'none';
assert(all_hidden(pm.HeatText),'None left the overlay on screen');
pm.Labels = 'counts';

% A bank with a missing condition: 8 kHz at 30 and 60, 16 kHz at 30 only.
sparse_ = mabr.stim.StimulusSet(sparse_bank(),cfg);
sparseSch = mabr.stim.Schedule(sparse_,cfg);
sparseSch.Repetitions = [4 4 4];
sparseSch.build();
pm.attach(sparseSch,sparse_);
pm.View = 'heatmap';
A = pm.HeatImage.AlphaData;
assert(nnz(A == 0) == 1,'a bank missing one condition should leave one empty cell (got %d)', ...
    nnz(A == 0));
assert(isempty(pm.HeatText(A == 0).String), ...
    'an empty heat-map cell should carry no number');
% ...and has to LOOK empty without the numbers: a pale cell could be 0%.
assert(n_marks(pm.HoleHatch,9) == 1,'the missing condition should be the one hatched cell (got %g)', ...
    n_marks(pm.HoleHatch,9));
fprintf('  PASS: heat map, its overlay, and a hole where a condition is absent\n');

% --- 7. following a controller ------------------------------------------
sch2 = mabr.stim.Schedule(bank,cfg);
sch2.Strategy    = 'shuffled';        % ONE intermixed run, so the pairing matters
sch2.Repetitions = [2 2 2 2 2 2];
sch2.Seed        = 7;                 % a fixed plan to check the pairing against
sch2.ISI         = 0.02;
sch2.build();

fc = mabrtest.FakeController(sch2,bank);
pm.listenTo(fc);
assert(isequal(pm.Targets,[2 2 2 2 2 2]), ...
    'the monitor did not pick up the controller''s plan');

fc.setState(mabr.ui.ProgState.Acquire);
fc.metrics(5);                        % 5 sweeps into the run
pm.refresh(true);
seq  = sch2.runSequence(1);
want = accumarray(seq(1:5)',1,[6 1])';
assert(isequal(pm.Counts,want), ...
    'mid-run sweeps were attributed as %s, expected %s', ...
    mat2str(pm.Counts),mat2str(want));
[~,st,~,det] = pm.headerText();
assert(contains(st,'run 1 of 1'),'mid-run the header should name the run; it reads "%s"',st);
assert(contains(det,'6 conditions intermixed') && contains(det,'5 / 12 this run'), ...
    'mid-run the header should describe the run; it reads "%s"',det);
assert(contains(pm.Figure.Name,'%'), ...
    'the window title should carry the percentage mid-run ("%s")',pm.Figure.Name);
% Still the heat map from part 6: every condition of an intermixed run is
% being presented, and each is outlined.
assert(strcmp(pm.View,'heatmap'),'part 7 expects the heat map left on by part 6');
assert(n_marks(pm.ActiveOutline,6) == 6, ...
    'expected all 6 conditions outlined as being presented, got %g',n_marks(pm.ActiveOutline,6));

% The run stops streaming. Until it is CREDITED -- which, with the DSP worker,
% is a finalization reply some time later -- its sweeps are still in the
% tally: dropping them here made every bar fall back by a whole run.
fc.setState(mabr.ui.ProgState.BlockComplete);
pm.refresh(true);
assert(isequal(pm.Counts,want), ...
    'the run''s sweeps left the tally before the run was credited: %s',mat2str(pm.Counts));
assert(n_marks(pm.ActiveOutline,6) == 0,'conditions stayed outlined after the run stopped');

% Finalization: the run is credited to RunCounts and the live counter must be
% given up, or every sweep would be counted twice.
sch2.recordRun(1,[2 2 2 2 2 2]);
fc.emit([]);
pm.refresh(true);
assert(isequal(pm.Counts,[2 2 2 2 2 2]), ...
    'a credited run was double-counted: %s',mat2str(pm.Counts));
fc.setState(mabr.ui.ProgState.Acquire);
pm.refresh(true);
assert(isequal(pm.Counts,[2 2 2 2 2 2]), ...
    'a stale live sweep count came back after the run was credited: %s',mat2str(pm.Counts));
fprintf('  PASS: mid-run sweeps attributed by the run''s own sequence, credited once\n');

% --- 8. make-up runs enlarge the denominator ----------------------------
fc.setState(mabr.ui.ProgState.BlockComplete);
before = sum(pm.Targets);
sch2.appendMakeup([1 0 0 0 0 0]);
pm.refresh(true);
assert(sum(pm.Targets) == before + 1, ...
    'an appended make-up run did not enlarge the plan (%d -> %d)',before,sum(pm.Targets));
assert(pm.Targets(1) == 3,'the make-up went to the wrong stimulus: %s',mat2str(pm.Targets));
fprintf('  PASS: artifact make-up enlarges the plan the bars are measured against\n');

% --- 9. the refresh rate limit -------------------------------------------
pm.MinInterval = 60;
pm.refresh(true);                     % starts the clock
sch2.recordRun(2,[0 1 0 0 0 0]);
pm.refresh(false);
assert(pm.Counts(2) == 2, ...
    'a throttled refresh repainted anyway (%d)',pm.Counts(2));
pm.refresh(true);
assert(pm.Counts(2) == 3,'force did not override the rate limit (%d)',pm.Counts(2));
pm.MinInterval = 0.2;
fprintf('  PASS: refreshes are rate limited, and force overrides it\n');

% --- 10. the control strip ----------------------------------------------
% In the order a user reaches them: the second row's controls are greyed for
% whichever view is not in force, so each is exercised under its own view.
click(find_drop(pm,1,2),'bars');
assert(strcmp(pm.View,'bars'),'the View control did not reach View');
click(find_drop(pm,2,2),'Level');
assert(strcmp(pm.GroupBy,'Level'),'the Group control did not reach GroupBy');
click(find_drop(pm,1,4),'percent');
assert(strcmp(pm.Labels,'percent'),'the Show control did not reach Labels');
click(find_drop(pm,1,2),'heatmap');
assert(strcmp(pm.View,'heatmap'),'the View control did not reach View');
click(find_drop(pm,2,4),'Level');
assert(strcmp(pm.HeatX,'Level'),'the X control did not reach HeatX');
% Y was on Level too; taking Level for X has to move Y off it rather than
% leave both axes on one parameter.
assert(~strcmp(pm.HeatY,'Level'),'both heat-map axes ended up on Level');
click(find_drop(pm,2,6),'Frequency');
assert(strcmp(pm.HeatY,'Frequency'),'the Y control did not reach HeatY');
pm.View   = 'bars';
pm.Labels = 'counts';
fprintf('  PASS: the control strip writes exactly the public properties\n');

% --- 11. always on top, and the embedded form ---------------------------
pm.AlwaysOnTop = true;
assert(strcmp(pm.Figure.WindowStyle,'alwaysontop'), ...
    'Always on top did not raise the window (%s)',pm.Figure.WindowStyle);
pm.AlwaysOnTop = false;
assert(strcmp(pm.Figure.WindowStyle,'normal'), ...
    'clearing Always on top did not release the window (%s)',pm.Figure.WindowStyle);

host = uifigure('Visible','off','Position',[100 100 600 500]);
cleanHost = onCleanup(@() delete(host));
panel = uipanel(host,'Position',[0 0 1 1]);
pm2 = mabr.ui.ProgressMonitor(panel);
clean2 = onCleanup(@() delete(pm2));
pm2.attach(sch,bank);
pm2.View = 'bars';
assert(isequal(ancestor(pm2.Axes,'figure'),host), ...
    'the embedded view did not build inside the container it was given');
assert(numel(pm2.ValueText) == 6,'the embedded view did not draw the bars');
assert(isempty(pm2.Figure),'an embedded view should own no figure of its own');
fprintf('  PASS: always-on-top toggles, and the view embeds in a container\n');

% --- 12. stimulation only: the clock, the estimate, and a pause ----------
% Nothing is recorded, so no live metrics ever arrive: the header's clock has
% to run on its own, and the run's presentations come from it.
sch3 = mabr.stim.Schedule(bank,cfg);
sch3.Strategy        = 'conventional';
sch3.Repetitions     = 400;
sch3.ISI             = 0.01;
sch3.SilencePad      = 0.05;
sch3.StimulationOnly = true;
sch3.build();
first = sch3.runSequence(1);
s1    = first(1);                     % the one stimulus run 1 presents

fc3 = mabrtest.FakeController(sch3,bank);
pm.View    = 'bars';
pm.GroupBy = 'Stimulus';
pm.listenTo(fc3);
assert(~pm.clockRunning(),'the header clock is running with nothing in flight');
fc3.setState(mabr.ui.ProgState.PrepBlock);
fc3.setState(mabr.ui.ProgState.Acquire);
assert(pm.clockRunning(),'the header clock did not start with the schedule');

pause(0.5);
pm.refresh(true);
k1 = pm.Counts(s1);
assert(pm.Estimated && k1 > 0 && k1 <= 400, ...
    'half a second into a stimulation-only run the estimate is %d (Estimated = %d)',k1,pm.Estimated);
[pct,st,tm,det] = pm.headerText();
assert(startsWith(pct,'~'),'an estimated count should be marked as one: "%s"',pct);
assert(contains(det,'~') && contains(det,'this run'),'the run line should carry the estimate: "%s"',det);
assert(contains(st,'stimulation only'),'the state line should say stimulation only: "%s"',st);
assert(contains(tm,'elapsed') && contains(tm,'left'),'the time line reads "%s"',tm);

% A pause is the ENGINE's state; the program state stays Acquire. Both the
% header and the estimate have to notice.
fc3.pauseAcq();
assert(pm.Paused,'the monitor did not see the engine pause');
[~,st,tm] = pm.headerText();
assert(startsWith(st,'Paused'),'a paused run should say so: "%s"',st);
assert(contains(tm,'paused'),'the time line should show the pause: "%s"',tm);
assert(contains(pm.Figure.Name,'paused'),'the window title should show the pause: "%s"',pm.Figure.Name);
k2 = pm.Counts(s1);
pause(0.3);
pm.refresh(true);
assert(pm.Counts(s1) == k2, ...
    'the estimate kept counting through a pause (%d -> %d)',k2,pm.Counts(s1));
fc3.resumeAcq();
assert(~pm.Paused,'the monitor did not see the engine resume');
pause(0.2);
pm.refresh(true);
assert(pm.Counts(s1) > k2,'the estimate did not pick up again after the resume');

% The run ends. Its estimate holds -- frozen, not growing -- until the run is
% credited, and then the count the controller recorded replaces it.
fc3.setState(mabr.ui.ProgState.BlockComplete);
pm.refresh(true);
k3 = pm.Counts(s1);
assert(k3 > k2,'the run''s estimate dropped out when it stopped streaming (%d)',k3);
pause(0.2);
pm.refresh(true);
assert(pm.Counts(s1) == k3,'a stopped run''s estimate kept growing (%d -> %d)',k3,pm.Counts(s1));
played = zeros(1,bank.numStimuli);
played(s1) = 400;
sch3.recordRun(1,played);
pm.refresh(true);
assert(pm.Counts(s1) == 400 && ~pm.Estimated, ...
    'the recorded count did not replace the estimate (%d, Estimated = %d)',pm.Counts(s1),pm.Estimated);

fc3.complete();
assert(~pm.clockRunning(),'the header clock kept running after the schedule completed');
[~,~,tm] = pm.headerText();
assert(startsWith(tm,'took'),'a completed schedule should say how long it took: "%s"',tm);
fprintf('  PASS: stimulation only -- the clock runs, the estimate counts, a pause holds both\n');

% --- 13. a window opened mid-session ------------------------------------
% It cannot know when the session began, so it must not say "elapsed" from
% the moment it opened -- and must not estimate the time left from that
% either, which is what made the old estimate wildly short.
sch4 = mabr.stim.Schedule(bank,cfg);
sch4.Strategy    = 'conventional';
sch4.Repetitions = 10;
sch4.ISI         = 0.02;
sch4.build();
done1 = zeros(1,bank.numStimuli);
r1    = sch4.runSequence(1);
done1(r1(1)) = 10;
sch4.recordRun(1,done1);
sch4.advance();

fc4 = mabrtest.FakeController(sch4,bank);
fc4.State = mabr.ui.ProgState.Acquire;     % already running when the window opens
pm.listenTo(fc4);
assert(pm.clockRunning(),'a window opened mid-run should start its clock');
[~,st,tm,det] = pm.headerText();
assert(~contains(tm,'elapsed'), ...
    'a window opened mid-session claimed to know how long it had been running: "%s"',tm);
assert(contains(tm,'left'),'no time left was estimated: "%s"',tm);
assert(contains(st,'run 2 of 6'),'the state line reads "%s"',st);
assert(contains(det,'10 presentations this run'), ...
    'before its first update the run''s count is unknown, and should not read as 0: "%s"',det);
fc4.metrics(3);
pm.refresh(true);
[~,~,~,det] = pm.headerText();
assert(contains(det,'3 / 10 this run'),'the first update did not reach the run line: "%s"',det);
fc4.complete();
fprintf('  PASS: a window opened mid-session measures from what it has seen\n');

fprintf('== verify_progress_monitor: all checks passed ==\n');
end

% ----------------------------------------------------------------------
function f = bar_fracs(pm)
% How full each bar is drawn, read back off the patch the window actually
% renders -- not off the numbers it was handed.
span = max(pm.TrackPatch.Vertices(:,1));
f    = (pm.FillPatch.Vertices(2:4:end,1)./span).';
end

function n = n_marks(h,per)
% How many heat-map cells a NaN-separated overlay line marks: PER entries a
% cell (9 for the hatching, 6 for an outline), NaN alone for none.
x = h.XData;
if numel(x) <= 1, n = 0; else, n = numel(x)/per; end
end

function d = find_drop(pm,row,col)
% The dropdown in one cell of the control strip's grid.
ds = findobj(pm.CtrlPanel,'Type','uidropdown');
for k = 1:numel(ds)
    if isequal(ds(k).Layout.Row,row) && isequal(ds(k).Layout.Column,col)
        d = ds(k); return
    end
end
error('verify_progress_monitor:noControl','no dropdown at row %d column %d',row,col);
end

function click(d,value)
% Set a control and fire its callback, the way a user does.
d.Value = value;
d.ValueChangedFcn(d,[]);
end

function tf = all_hidden(h)
% Visible reads back as a char in some releases and an OnOffSwitchState in
% others; string() flattens both.
tf = ~isempty(h) && all(arrayfun(@(x) strcmp(string(x.Visible),"off"),h(:)));
end

function s = sparse_bank()
% 8 kHz at 30 and 60 dB, 16 kHz at 30 only -- one missing cell in a 2x2 grid.
w = single(sin(2*pi*(0:127)'/16));
s = struct('signal',{w,w,w}, ...
           'ID',{'8kHz_30dB','8kHz_60dB','16kHz_30dB'}, ...
           'Frequency',{8,8,16}, ...
           'Level',{30,60,30});
end

function restore_prefs(names,had,values)
for k = 1:numel(names)
    if had(k)
        setpref('MABR',names{k},values{k});
    elseif ispref('MABR',names{k})
        rmpref('MABR',names{k});
    end
end
end
