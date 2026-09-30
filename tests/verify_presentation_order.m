function verify_presentation_order()
% verify_presentation_order  The presentation-order window, and switching
% upcoming conditions off.
%
%   No audio hardware, no acquisition engine, no parallel pool. Checks:
%     Part A  mabr.stim.Schedule.setEnabled on a conventional plan: a disabled
%             condition's run is dropped when it is reached, never before; the
%             current run is never changed; re-enabling before the run is
%             reached restores it; isComplete answers with the mask; reset()
%             restores the built plan and clears the mask.
%     Part B  the same on a multi-run intermixed plan: the disabled stimulus is
%             removed from the next run with its polarities, the rest of the
%             run is untouched, and Skipped counts what went.
%     Part C  a disabled stimulus gets no artifact make-up, and repeatRun
%             switches it back on.
%     Part D  the window: the plan's sequence, rows sorted and named by the
%             varying parameters, and the ACTIVE condition following a
%             controller's live count -- the marker, the band on its row, and
%             the header all naming the stimulus the run's sequence puts there.
%     Part E  the window's switches: the On box (driven through the table's
%             own callback) disables a condition, its upcoming presentations
%             are drawn as crosses and not as pending marks, and Enable all
%             puts everything back.
%     Part F  Span: the whole plan for a conventional plan, a window that
%             follows the active presentation for an intermixed one.
%
%   Run:  >> verify_presentation_order
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_presentation_order ==\n');

prefNames = {'OrderSpan','OrderWindow'};
hadPref = false(1,numel(prefNames));
oldPref = cell(1,numel(prefNames));
for iP = 1:numel(prefNames)
    hadPref(iP) = ispref('MABR',prefNames{iP});
    if hadPref(iP), oldPref{iP} = getpref('MABR',prefNames{iP}); end
end
restorePref = onCleanup(@() restore_prefs(prefNames,hadPref,oldPref)); %#ok<NASGU>
% The window opens on the stored Span; the checks below assume the default.
for iP = 1:numel(prefNames)
    if ispref('MABR',prefNames{iP}), rmpref('MABR',prefNames{iP}); end
end

cfg  = mabr.Config;
% 3 frequencies x 2 levels = 6 entries, in that order:
%   (8,30) (8,60) (16,30) (16,60) (32,30) (32,60)
bank = mabr.stim.demoStimuli(cfg,'Frequencies',[8 16 32],'Levels',[30 60], ...
                             'PipDuration',0.002);
n = bank.numStimuli;

% ---- Part A: conventional ---------------------------------------------------
sch = mabr.stim.Schedule(bank,cfg);
sch.Strategy    = 'conventional';
sch.Repetitions = 10;
sch.ISI         = 0.02;
sch.build();
assert(sch.NumRuns == n && sch.current() == 1,'expected one run per stimulus');
first = sch.runSequence(1);

sch.setEnabled(first(1),false);        % the CURRENT run's stimulus
assert(isequal(sch.runSequence(1),first), ...
    'disabling the current run''s stimulus changed the run in progress');
sch.setEnabled(first(1),true);

s3 = sch.Runs{3}(1);
s5 = sch.Runs{5}(1);
sch.setEnabled([s3 s5],false);
assert(sch.NumRuns == n,'disabling must not drop a run before it is reached');
assert(isequal(sch.isEnabled([s3 s5]),[false false]),'isEnabled does not read the mask');
sch.setEnabled(s5,true);               % changed my mind before its run came up

assert(sch.advance() == 2,'run 2 was not reached');
r = sch.advance();                      % run 3 (s3) is dropped on the way
assert(r == 3 && sch.NumRuns == n-1,'the disabled run was not dropped when reached');
assert(all(sch.runSequence(r) ~= s3),'the disabled stimulus is still in the run reached');
assert(sch.Skipped(s3) == 10 && sum(sch.Skipped) == 10, ...
    'Skipped does not count the presentations removed: %s',mat2str(sch.Skipped));
assert(any(cellfun(@(x) any(x == s5),sch.Runs)), ...
    'a condition re-enabled before its run was reached was dropped anyway');

% Everything after the current run off: complete now, not one run later.
rest = unique([sch.Runs{sch.current()+1:end}]);
sch.setEnabled(rest,false);
assert(sch.isComplete(),'isComplete ignores the mask');
assert(isempty(sch.advance()) && sch.current() == 0, ...
    'advance should walk off a plan whose remaining runs are all disabled');

sch.reset();
assert(sch.NumRuns == n && all(sch.isEnabled()) && all(sch.Skipped == 0), ...
    'reset() must restore the built plan and clear the mask');
assert(isequal(sch.runSequence(1),first),'reset() did not restore the first run');
fprintf('  PASS Part A: a conventional run is dropped when reached, and only then\n');

% ---- Part B: intermixed, several runs ---------------------------------------
schB = mabr.stim.Schedule(bank,cfg);
schB.Repetitions = 2;
schB.ISI         = 0.02;
schB.Strategy    = 'custom';
schB.StrategyFcn = @(~) {1:n, n:-1:1};
schB.build();
assert(schB.NumRuns == 2,'the custom plan should hold two intermixed runs');
schB.setEnabled(2,false);
assert(isequal(schB.runSequence(1),1:n),'the run in progress was changed');
up = schB.upcomingCounts();
assert(up(2) == 1 && sum(up) == n,'upcomingCounts is wrong: %s',mat2str(up));
schB.advance();
seq = schB.runSequence(2);
assert(isequal(seq,setdiff(n:-1:1,2,'stable')), ...
    'the disabled stimulus was not removed cleanly: %s',mat2str(seq));
assert(numel(schB.runPolarity(2)) == numel(seq), ...
    'polarities no longer line up with the run''s presentations');
assert(schB.Skipped(2) == 1,'Skipped should count the one presentation removed');
fprintf('  PASS Part B: an intermixed run loses only the disabled stimulus\n');

% ---- Part C: make-up and repeat ------------------------------------------------
schC = mabr.stim.Schedule(bank,cfg);
schC.Strategy    = 'conventional';
schC.Repetitions = 10;
schC.build();
schC.setEnabled(4,false);
added = schC.appendMakeup([0 0 0 5 5 0]);
assert(added(4) == 0 && added(5) == 5,'a disabled stimulus was made up: %s',mat2str(added));
schC.repeatRun(4);
assert(schC.isEnabled(4),'asking for a repeat run of a stimulus should switch it back on');
fprintf('  PASS Part C: no make-up for a disabled stimulus; a repeat re-enables it\n');

% ---- Part D: the window follows the active condition ---------------------------
sch = mabr.stim.Schedule(bank,cfg);
sch.Strategy    = 'conventional';
sch.Repetitions = 10;
sch.ISI         = 0.02;
sch.build();

po = mabr.ui.PresentationOrder();
clean = onCleanup(@() delete(po)); %#ok<NASGU>
po.MinInterval = 0;
po.attach(sch,bank);
assert(numel(po.Sequence) == 10*n,'the window does not hold the whole plan');
assert(isequal(po.RunStarts,0:10:10*n),'run starts wrong: %s',mat2str(po.RunStarts));
assert(numel(po.Rows) == n && isequal(sort(po.Rows),1:n),'one row per condition expected');
assert(strcmp(po.RowLabels{1},'8 kHz, 30 dB') && strcmp(po.RowLabels{end},'32 kHz, 60 dB'), ...
    'rows are not named and sorted by the varying parameters: %s', ...
    strjoin(po.RowLabels,' | '));
assert(po.Current == 0,'nothing should be highlighted with no controller running');

fc = mabrtest.FakeController(sch,bank);
po.listenTo(fc);
fc.setState(mabr.ui.ProgState.PrepBlock);
assert(po.Current == 1 && po.ActiveStimulus == sch.Runs{1}(1), ...
    'a run being prepared should highlight its first presentation');
fc.setState(mabr.ui.ProgState.Acquire);
fc.metrics(4);
assert(po.Current == 4,'the live count did not move the highlight (at %d)',po.Current);
check_active(po,sch.Runs{1}(1));

% Next run.
sch.recordRun(1,accumarray(sch.Runs{1}(:),1,[n 1]).');
fc.setState(mabr.ui.ProgState.BlockComplete);
assert(po.Current == 4,'between runs the last presentation should stay highlighted');
sch.advance();
fc.setState(mabr.ui.ProgState.PrepBlock);
fc.setState(mabr.ui.ProgState.Acquire);
fc.metrics(7);
assert(po.Current == 17 && po.Done == 17,'run 2''s position is wrong (%d, %d done)', ...
    po.Current,po.Done);
check_active(po,sch.Runs{2}(1));
assert(strcmp(po.resolvedSpan(),'plan'),'a conventional plan should show the whole plan');
fprintf('  PASS Part D: the active condition is highlighted where the live count says\n');

% ---- Part E: the On boxes ---------------------------------------------------
target = sch.Runs{4}(1);
row = find(po.Rows == target);
evt = struct('Indices',[row 1],'NewData',false,'PreviousData',true);
po.Table.CellEditCallback(po.Table,evt);          % as a click on the box does
assert(~sch.isEnabled(target),'the On box did not reach the schedule');
assert(isequal(po.Table.Data{row,1},false),'the table does not show the condition off');
assert(numel(po.OffLine.XData) == 10 && all(po.OffLine.XData > 30 & po.OffLine.XData <= 40), ...
    'the switched-off presentations are not the ones drawn as crosses');
pend = po.PendingLine.YData(31:40);
assert(all(isnan(pend)),'a switched-off presentation is still drawn as pending');
[~,info] = header(po);
assert(contains(info,'1 condition off'),'the header does not say a condition is off: "%s"',info);

% The run in progress cannot be switched off.
cur = sch.Runs{2}(1);
po.Table.CellEditCallback(po.Table,struct('Indices',[find(po.Rows == cur) 1], ...
    'NewData',false,'PreviousData',true));
assert(isequal(sch.runSequence(2),repmat(cur,1,10)),'the run in progress was changed');
check_active(po,cur);

btn = findobj(po.Figure,'Type','uibutton','Text','Enable all');
btn.ButtonPushedFcn(btn,[]);
assert(all(sch.isEnabled()),'Enable all left something off');
assert(numel(po.OffLine.XData) <= 1 && all(isnan(po.OffLine.XData)), ...
    'crosses remain after Enable all');
fc.complete();
assert(po.Done == numel(po.Sequence) && po.Current == 0, ...
    'a complete plan should show everything done and nothing active');
fprintf('  PASS Part E: the On box switches a condition off and back on\n');

% ---- Part F: an intermixed plan's window ------------------------------------
schF = mabr.stim.Schedule(bank,cfg);
schF.Strategy    = 'interleaved-random';
schF.Repetitions = 50;
schF.ISI         = 0.02;
schF.build();
fcF = mabrtest.FakeController(schF,bank);
po.listenTo(fcF);
fcF.setState(mabr.ui.ProgState.PrepBlock);
fcF.setState(mabr.ui.ProgState.Acquire);
fcF.metrics(123);
assert(strcmp(po.resolvedSpan(),'window'),'an intermixed plan should show a window');
seqF = schF.runSequence(1);
assert(po.Current == 123 && po.ActiveStimulus == seqF(123), ...
    'the active stimulus is not the one the run''s sequence puts at 123');
check_active(po,seqF(123));
vr = po.visibleRange();
assert(vr(1) <= 123 && vr(2) >= 123 && diff(vr) <= po.WindowLength, ...
    'the window does not follow the active presentation: %s',mat2str(vr));
drop = findobj(po.Figure,'Type','uidropdown');
drop.Value = 'plan';
drop.ValueChangedFcn(drop,[]);
vr = po.visibleRange();
assert(vr(1) <= 1 && vr(2) >= numel(seqF),'Whole plan does not show the whole plan');
assert(strcmp(getpref('MABR','OrderSpan'),'plan'),'the control strip did not persist Span');
fprintf('  PASS Part F: the span follows the active presentation\n');

fprintf('== verify_presentation_order: all checks passed ==\n');
end

% ----------------------------------------------------------------------
function check_active(po,stim)
% What the window DRAWS for the active condition, read back off the objects.
row = find(po.Rows == stim);
assert(po.ActiveStimulus == stim,'active stimulus %d, expected %d',po.ActiveStimulus,stim);
assert(strcmp(string(po.ActiveBand.Visible),"on"),'the active row is not highlighted');
assert(abs(mean(po.ActiveBand.YData) - row) < 1e-9,'the band is on the wrong row');
assert(po.ActiveMarker.XData == po.Current && po.ActiveMarker.YData == row, ...
    'the marker is not on the active presentation');
lbl = po.Axes.YTickLabel;
assert(startsWith(lbl{row},'\bf'),'the active row''s label is not bold');
[now,~] = header(po);
assert(contains(now,po.RowLabels{row}),'the header does not name the active condition: "%s"',now);
end

function [now,info] = header(po)
now  = po.NowLabel.Text;
info = po.InfoLabel.Text;
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
