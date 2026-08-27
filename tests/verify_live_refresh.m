function verify_live_refresh()
% verify_live_refresh  The live view keeps its frame rate with viewers open.
%
%   The live trace is the one view that has to keep up with the electrode: an
%   ABR average is watched as it forms, and a stuttering trace is the
%   difference between seeing a bad electrode now and seeing it after the
%   block. mabr.ui.AcqController therefore runs TWO timers -- a ~20 Hz
%   LiveTimer for the trace and the advance criterion, and a slower AuxTimer
%   (AuxPeriod, default 0.2 s) for everything else drawn from a running block.
%
%   Both are 'fixedSpacing', so a tick's period is measured from when the
%   previous one RETURNS: work in the fast tick comes straight off the live
%   view's frame rate. That is what this file guards. With the progress
%   monitor and an online-analysis window attached, doing their work in the
%   live tick took the realized refresh from ~13 Hz to ~1 Hz -- a regression
%   invisible to every other verification, because every number it produced
%   was still correct. Only the RATE was wrong.
%
%   Part A: the two timers exist, differ in period, and start/stop together.
%   Part B: AuxPeriod retunes the running timer rather than waiting for a run.
%   Part C: with both low-priority viewers attached, a real (loopback) run
%           serves them at AuxPeriod and NOT at the live tick's rate.
%
%   Part C deliberately tests the RATE THE SLOW WORK IS SERVED AT rather than
%   the live view's realized frame rate. Polling a line's YData from the same
%   single MATLAB thread the timers run on competes with the thing being
%   measured, so a frame-rate number read that way is too noisy to assert on.
%   The rate the aux work is served at is not: if it were back in the live
%   tick it would fire at ~20 Hz whatever AuxPeriod said, so setting AuxPeriod
%   long and watching MetricsUpdated follow it is a crisp, machine-independent
%   detector of exactly the regression this guards. The observed repaint rate
%   is printed for information.
%
%   Requires the Parallel Computing Toolbox (Part C). No audio hardware --
%   the whole thing runs in TESTING loopback mode.
%
%   See also mabr.ui.AcqController, mabr.ui.LivePlot, verify_live_plot.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_live_refresh ==\n');
cfg = mabr.Config;

%% ---- Part A: two timers, split by rate ---------------------------------
ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl));

live = timerfindall('Tag','MABR_LiveView');
aux  = timerfindall('Tag','MABR_AuxView');
assert(~isempty(live),'no live timer was created');
assert(~isempty(aux), 'no auxiliary timer was created');
assert(aux(1).Period > live(1).Period, ...
    'the aux timer (%g s) must be slower than the live timer (%g s)', ...
    aux(1).Period,live(1).Period);
assert(strcmp(aux(1).BusyMode,'drop'), ...
    ['the aux timer must DROP a late tick rather than queue a backlog that ' ...
     'would later compete with the live view for the same single thread']);
fprintf('  PASS Part A: live %g s / aux %g s, both drop-on-busy\n', ...
    live(1).Period,aux(1).Period);

%% ---- Part B: AuxPeriod is retunable ------------------------------------
% Deliberately not the default: assigning the value it already holds would
% pass whether or not the assignment reached the timer.
was = ctrl.AuxPeriod;
ctrl.AuxPeriod = 1.25;
aux = timerfindall('Tag','MABR_AuxView');
assert(abs(aux(1).Period - 1.25) < 1e-9, ...
    'assigning AuxPeriod did not reach the timer (%g)',aux(1).Period);
ctrl.AuxPeriod = was;
aux = timerfindall('Tag','MABR_AuxView');
assert(abs(aux(1).Period - was) < 1e-9,'AuxPeriod did not restore');
fprintf('  PASS Part B: AuxPeriod retunes the running timer (default %g s)\n',was);

%% ---- Part C: the trace keeps its rate with the slow viewers open -------
set = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16],'Levels',[30 60]);
ctrl.waitUntilReady();
ctrl.setStimuli(set);
ctrl.Session.Subject.ID = 'REFRESH';
ctrl.Session.OutputPath = '';            % record without saving
ctrl.Schedule.Strategy    = 'interleaved';
ctrl.Schedule.Repetitions = 128;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
% Deliberately far slower than anything the live tick could produce. The
% assertion below is that AuxPeriod actually GOVERNS the rate: with the slow
% work back inside the live tick, MetricsUpdated tracks the tick instead and
% this number stops mattering at all.
ctrl.AuxPeriod = 2.0;
% Pace the loopback like the real device -- worker_loop streams 1024-sample
% frames at the DAC rate. Without this the schedule finishes faster than the
% view can be sampled and there is no rate to measure.
ctrl.Schedule.TestingFrameDelay = 1024/cfg.DACSampleRate;

% The live view opens on the display settings last chosen in one, so take
% that pref out of the way: what this script measures must not depend on the
% layout the user happens to have left their own window in.
hadLivePref = ispref('MABR','LivePlot');
if hadLivePref
    oldLivePref = getpref('MABR','LivePlot');
    rmpref('MABR','LivePlot');
else
    oldLivePref = [];
end
restoreLivePref = onCleanup(@() restore_live_pref(hadLivePref,oldLivePref)); %#ok<NASGU>

lp = mabr.ui.LivePlot();
ctrl.setLivePlot(lp);
pm = mabr.ui.ProgressMonitor();  pm.listenTo(ctrl);
mp = mabr.ui.MetricPlot();       mp.attach(ctrl);
cleanV = onCleanup(@() delete([lp pm mp])); %#ok<NASGU>

% containers.Map is a HANDLE class: a struct counter would be handed to the
% callback by value and would never count anything.
cnt = containers.Map({'aux'},{0});
lh  = addlistener(ctrl,'MetricsUpdated',@(~,~) bump(cnt,'aux'));

ctrl.start();
t0 = tic; stamps = zeros(1,20000); ns = 0; lastY = []; hLine = [];
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 120
    if isempty(hLine) || ~all(isgraphics(hLine))
        h = findobj(lp.axLatest,'Type','line');
        h = h(arrayfun(@(x) numel(x.XData) > 2,h));
        if ~isempty(h), hLine = h(1); end
    end
    if ~isempty(hLine) && isgraphics(hLine)
        y = hLine.YData;
        if ~isequal(y,lastY), ns = ns+1; stamps(ns) = toc(t0); lastY = y; end
    end
    pause(0.002);
end
elapsed = toc(t0);
delete(lh);
assert(ctrl.State == mabr.ui.ProgState.SchedComplete, ...
    'the schedule did not complete (state %s)',string(ctrl.State));

auxN    = cnt('aux');
auxRate = auxN/elapsed;

assert(auxN > 0,'MetricsUpdated never fired -- the aux timer is not running');
% The whole assertion. The tolerance is a factor of two over nominal, which
% is not arbitrary: measured against the pre-split code -- the slow work done
% inside the live tick -- this same run served MetricsUpdated at 3.7 Hz, so
% any bound below that catches it. 2/AuxPeriod is 1.0 Hz here, comfortably
% under 3.7 and four times above the 0.5 Hz the split design actually
% produces, so the test has margin in both directions.
%
% Note it is NOT enough to assert the aux rate is merely "low": when the slow
% work sits in the live tick, the tick itself is starved and everything goes
% slow together. What separates the two designs is whether AuxPeriod GOVERNS
% the rate, which is why it is set to something the live tick could never
% produce on its own.
assert(auxRate <= 2/ctrl.AuxPeriod, ...
    ['MetricsUpdated fired at %.1f Hz with AuxPeriod = %g s (nominal %.1f ' ...
     'Hz) -- AuxPeriod is not governing the rate, so the low-priority work ' ...
     'looks like it is back in the ~%.0f Hz live tick (see ' ...
     'AcqController''s two timers)'], ...
    auxRate,ctrl.AuxPeriod,1/ctrl.AuxPeriod,1/live(1).Period);

if ns > 5
    fprintf('  (live view repainted %d times, ~%.1f Hz observed)\n', ...
        ns,1/median(diff(stamps(1:ns))));
end
fprintf(['  PASS Part C: aux served at %.1f Hz (AuxPeriod %g s) against a ' ...
    '%.0f Hz live tick\n'],auxRate,ctrl.AuxPeriod,1/live(1).Period);

fprintf('== verify_live_refresh PASSED ==\n');
end

function restore_live_pref(had,value)
% Put the user's live-view preference back exactly as it was -- including
% "there wasn't one".
if had
    setpref('MABR','LivePlot',value);
elseif ispref('MABR','LivePlot')
    rmpref('MABR','LivePlot');
end
end

function bump(m,k)
m(k) = m(k) + 1;
end
