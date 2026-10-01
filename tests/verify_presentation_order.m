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
%     Part G  one column per parameter, sorted by two keys chosen outside the
%             table, remembered.
%     Part H  the buttons: Skip next (the next run's condition, named in its
%             tooltip, greyed when nothing waits), Disable above / below the
%             selected row in the order the TABLE shows (the selection follows
%             its condition through a re-sort), Enable all, a switched-off
%             condition's label greyed without any "(off)" added, every button
%             carrying a picture, and Stay on top (the window's style, the pref
%             written from the button only, a new window opening as left).
%     Part I  the y axis is in the TABLE's order, whatever Sort by / then by
%             say: the labels, the height of every mark (done, pending, off),
%             the active highlight through a re-sort, a sort on a count that
%             moves (Upcoming), and a box ticked leaving every row where it is
%             -- and Disable above reaches what is above on the plot.
%     Part J  switching is off while an intermixed run plays: the On boxes stop
%             being editable and the four buttons grey, each saying why, and a
%             callback driven anyway changes nothing; it comes back when the run
%             ends, is not there while a later run waits, and a conventional
%             plan is never locked.
%
%   Run:  >> verify_presentation_order
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_presentation_order ==\n');

prefNames = {'OrderSpan','OrderWindow','OrderSortKeys','OrderSortDirs','OrderOnTop'};
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
% A switched-off row is greyed, and nothing is added to its name.
lblE = po.Axes.YTickLabel;
assert(~any(contains(lblE,'off')),'a row label still says "(off)": %s',strjoin(lblE,' | '));
assert(contains(lblE{row},'\color[rgb]{0.600,0.620,0.650}'),'the switched-off row is not greyed');
assert(~contains(lblE{row},'\bf'),'a condition that is not playing should not be bold');

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
drop = findobj(po.Figure,'Tag','OrderSpan');
drop.Value = 'plan';
drop.ValueChangedFcn(drop,[]);
vr = po.visibleRange();
assert(vr(1) <= 1 && vr(2) >= numel(seqF),'Whole plan does not show the whole plan');
assert(strcmp(getpref('MABR','OrderSpan'),'plan'),'the control strip did not persist Span');
fprintf('  PASS Part F: the span follows the active presentation\n');

% ---- Part G: one column per parameter, sorted by two keys chosen outside the table
schG = mabr.stim.Schedule(bank,cfg);
schG.Strategy    = 'conventional';
schG.Repetitions = 10;
schG.ISI         = 0.02;
schG.build();
po.listenTo([]);
po.attach(schG,bank);
t0 = po.Table;
assert(isequal(t0.ColumnName(:).',{'On','Frequency (kHz)','Level (dB)','Upcoming'}), ...
    'the table is not one column per varying parameter: %s',strjoin(string(t0.ColumnName),' | '));
assert(isequal(size(t0.Data),[n 4]),'table data is %s',mat2str(size(t0.Data)));
assert(t0.Data{1,2} == 8 && t0.Data{1,3} == 30 && t0.Data{n,2} == 32 && t0.Data{n,3} == 60, ...
    'the parameter columns do not hold the rows'' values');
for p = ["ColumnSortable","ColumnRearrangeable"]
    assert(~isprop(t0,p) || ~any(t0.(p)),'the uitable still sorts or rearranges itself (%s)',p);
end
assert(isempty(t0.DisplayDataChangedFcn),'the table still reports its own sorting');
key1 = findobj(po.Figure,'Tag','OrderSortKey1');
key2 = findobj(po.Figure,'Tag','OrderSortKey2');
dir1 = findobj(po.Figure,'Tag','OrderSortDir1');
dir2 = findobj(po.Figure,'Tag','OrderSortDir2');
assert(strcmp(char(key2.Enable),'off'),'the second key is live before the first is chosen');
pick = @(h,v) set_dropdown(h,v);

% Frequency ascending, then Level descending: 8 kHz 60, 8 kHz 30, 16 kHz 60, ...
pick(key1,'Frequency');
assert(strcmp(char(key2.Enable),'on'),'the second key stays off after the first is chosen');
pick(key2,'Level'); pick(dir2,'descend');
fl = cell2mat(po.Table.Data(:,2:3));
assert(isequal(fl,[8 60; 8 30; 16 60; 16 30; 32 60; 32 30]), ...
    'Frequency ascending then Level descending: %s',mat2str(fl));
assert(po.Table == t0,'the table was replaced instead of updated in place');
assert(isequal(getpref('MABR','OrderSortKeys'),{'Frequency','Level'}) ...
    && isequal(getpref('MABR','OrderSortDirs'),{'ascend','descend'}),'the sort was not remembered');
assert(~any(strcmp(key2.ItemsData,'Frequency')),'the second key offers the first key''s column');

% Frequency descending: the second key still orders the ties.
pick(dir1,'descend'); pick(dir2,'ascend');
fl = cell2mat(po.Table.Data(:,2:3));
assert(isequal(fl,[32 30; 32 60; 16 30; 16 60; 8 30; 8 60]),'descending/ascending: %s',mat2str(fl));
pick(dir1,'ascend'); pick(dir2,'descend');

% A tick on a sorted table reaches the condition it is on; the row stays put.
po.Table.CellEditCallback(po.Table,struct('Indices',[1 1],'NewData',false,'PreviousData',true));
assert(isequal(find(~schG.isEnabled()),2), ...
    'the On box of a sorted row reached the wrong condition (8 kHz, 60 dB is stimulus 2)');
assert(isequal(po.Table.Data(1,1:3),{false,8,60}),'a row moved when its On box was ticked');
enable = findobj(po.Figure,'Type','uibutton','Text','Enable all');
enable.ButtonPushedFcn(enable,[]);
assert(all(schG.isEnabled()),'Enable all left something off');

% Level alone, then a sort on a parameter column that exists in no other bank.
pick(key2,''); pick(key1,'Level'); pick(dir1,'descend');
lv = cell2mat(po.Table.Data(:,3));
assert(isequal(lv(:).',[60 60 60 30 30 30]),'Level descending: %s',mat2str(lv));
% Clearing the first key clears the second.
pick(key2,'Frequency');
pick(key1,'');
assert(strcmp(char(key2.Enable),'off') && isempty(key2.Value) ...
    && isempty(getpref('MABR','OrderSortKeys')),'clearing the first key left a second one');
assert(isequal(cell2mat(po.Table.Data(:,3)).',[30 60 30 60 30 60]),'plot order did not come back');

% A new window comes up on the keys the last was left with.
pick(key1,'Frequency'); pick(dir1,'ascend'); pick(key2,'Level'); pick(dir2,'descend');
po2 = mabr.ui.PresentationOrder();
clean2 = onCleanup(@() delete(po2)); %#ok<NASGU>
po2.MinInterval = 0;
po2.attach(schG,bank);
assert(strcmp(findobj(po2.Figure,'Tag','OrderSortKey1').Value,'Frequency') ...
    && strcmp(findobj(po2.Figure,'Tag','OrderSortKey2').Value,'Level') ...
    && strcmp(findobj(po2.Figure,'Tag','OrderSortDir2').Value,'descend'), ...
    'a new window did not restore the sort');
assert(isequal(cell2mat(po2.Table.Data(:,2:3)),[8 60; 8 30; 16 60; 16 30; 32 60; 32 30]), ...
    'a new window did not sort its rows');
delete(po2);

% Prefs that do not fit the bank, or are junk, are ignored.
setpref('MABR','OrderSortKeys',{'Gone'}); setpref('MABR','OrderSortDirs',{'ascend'});
po3 = mabr.ui.PresentationOrder();
clean3 = onCleanup(@() delete(po3)); %#ok<NASGU>
po3.attach(schG,bank);
assert(isequal(po3.Table.Data{1,2},8) && isequal(cell2mat(po3.Table.Data(:,3)).',[30 60 30 60 30 60]), ...
    'a saved key the bank has no column for was not ignored');
delete(po3);
setpref('MABR','OrderSortKeys',{'Level','Frequency'}); setpref('MABR','OrderSortDirs',{'ascend'});
po4 = mabr.ui.PresentationOrder();
clean4 = onCleanup(@() delete(po4)); %#ok<NASGU>
po4.attach(schG,bank);
assert(isempty(findobj(po4.Figure,'Tag','OrderSortKey1').Value),'a mismatched pref was taken');
fprintf('  PASS Part G: a column per parameter, sorted by two keys, remembered\n');

% ---- Part H: the buttons -----------------------------------------------------
% A fresh window and plan, so nothing above leaks in. Its sort starts as the
% last window left it (the prefs just written), which the sort controls reset.
for iP = 1:numel(prefNames)
    if ispref('MABR',prefNames{iP}), rmpref('MABR',prefNames{iP}); end
end
schH = mabr.stim.Schedule(bank,cfg);
schH.Strategy    = 'conventional';
schH.Repetitions = 10;
schH.ISI         = 0.02;
schH.build();
poH = mabr.ui.PresentationOrder();
cleanH = onCleanup(@() delete(poH)); %#ok<NASGU>
poH.MinInterval = 0;
poH.attach(schH,bank);
btnSkip  = findobj(poH.Figure,'Tag','OrderSkipNext');
btnAbove = findobj(poH.Figure,'Tag','OrderDisAbove');
btnBelow = findobj(poH.Figure,'Tag','OrderDisBelow');
btnAll   = findobj(poH.Figure,'Tag','OrderEnableAll');
btnTop   = findobj(poH.Figure,'Tag','OrderOnTop');
isOn = @(b) strcmp(char(b.Enable),'on');
for b = [btnSkip btnAbove btnBelow btnAll btnTop]
    assert(~isempty(b.Icon) && isfile(b.Icon),'the "%s" button has no picture',b.Text);
end

% -- Skip next: the next run's condition, then the one after it ------------
assert(isOn(btnSkip) && ~isOn(btnAll),'Skip next / Enable all start in the wrong state');
nextA = schH.Runs{2}(1);
nextB = schH.Runs{3}(1);
assert(contains(btnSkip.Tooltip,poH.RowLabels{poH.Rows == nextA}), ...
    'Skip next does not name the condition it would skip: "%s"',btnSkip.Tooltip);
btnSkip.ButtonPushedFcn(btnSkip,[]);
assert(isequal(find(~schH.isEnabled()),nextA),'Skip next did not switch off the next run''s condition');
assert(isequal(po_row_on(poH,nextA),false),'the table does not show the skipped condition off');
assert(isOn(btnAll),'Enable all stays greyed with a condition off');
assert(contains(btnSkip.Tooltip,poH.RowLabels{poH.Rows == nextB}), ...
    'after one skip the tooltip should name the next one: "%s"',btnSkip.Tooltip);
btnSkip.ButtonPushedFcn(btnSkip,[]);
assert(isequal(find(~schH.isEnabled()),sort([nextA nextB])),'a second Skip next did not take the one after');
for k = 1:n, btnSkip.ButtonPushedFcn(btnSkip,[]); end   % past the end: harmless
assert(isequal(find(schH.isEnabled()),schH.Runs{1}(1)), ...
    'Skip next should leave only the run in progress''s condition on');
assert(~isOn(btnSkip) && contains(btnSkip.Tooltip,'Nothing to skip'), ...
    'Skip next is live with nothing left to skip');
btnAll.ButtonPushedFcn(btnAll,[]);
assert(all(schH.isEnabled()) && isOn(btnSkip) && ~isOn(btnAll),'Enable all did not put everything back');

% An intermixed plan is one run: there is no next run to skip.
schHi = mabr.stim.Schedule(bank,cfg);
schHi.Strategy = 'interleaved-random'; schHi.Repetitions = 20; schHi.ISI = 0.02; schHi.build();
poH.attach(schHi,bank);
assert(~isOn(btnSkip),'Skip next is live on a plan that is one run');
poH.attach(schH,bank);
assert(isOn(btnSkip),'Skip next did not come back with a plan that has runs waiting');

% -- Disable above / below: counted in the order the TABLE shows ---------------
key1 = findobj(poH.Figure,'Tag','OrderSortKey1');
key2 = findobj(poH.Figure,'Tag','OrderSortKey2');
dir2 = findobj(poH.Figure,'Tag','OrderSortDir2');
assert(~isOn(btnAbove) && ~isOn(btnBelow),'Disable above / below are live with no row selected');
pick = @(h,v) set_dropdown(h,v);
pick(key1,'Frequency'); pick(key2,'Level'); pick(dir2,'descend');
% Table order: 8/60 8/30 16/60 16/30 32/60 32/30 = stimuli 2 1 4 3 6 5.
assert(isequal(cell2mat(poH.Table.Data(:,2:3)),[8 60; 8 30; 16 60; 16 30; 32 60; 32 30]), ...
    'the table is not in the order this part assumes');
if ~(isprop(poH.Table,'Selection') && isprop(poH.Table,'SelectionType'))
    fprintf('  SKIP Part H (row selection): this release''s uitable cannot select rows\n');
else
    assert(strcmp(char(poH.Table.SelectionType),'row'),'a click should pick a whole row');
    select_row(poH,3);                                  % 16 kHz, 60 dB = stimulus 4
    assert(isOn(btnAbove) && isOn(btnBelow),'Disable above / below stay greyed with a row selected');
    btnAbove.ButtonPushedFcn(btnAbove,[]);
    assert(isequal(find(~schH.isEnabled()),[1 2]),'Disable above did not take rows 1-2 of the table: off = %s', ...
        mat2str(find(~schH.isEnabled())));
    assert(isequal(poH.Table.Selection(:)',3),'the selection did not survive the table being rewritten');
    assert(~isOn(btnAbove) && isOn(btnBelow),'Disable above should grey once nothing above is on');
    btnBelow.ButtonPushedFcn(btnBelow,[]);
    assert(isequal(find(schH.isEnabled()),4),'Disable below did not take rows 4-6 of the table: on = %s', ...
        mat2str(find(schH.isEnabled())));
    assert(~isOn(btnAbove) && ~isOn(btnBelow),'both should grey once only the selected one is on');
    assert(isequal(cell2mat(poH.Table.Data(:,1)).',logical([0 0 1 0 0 0])),'the On column does not show the result');

    % The selection follows its CONDITION through a re-sort, and "above" then means
    % above in the new order.
    pick(dir2,'ascend');                                % 8/30 8/60 16/30 16/60 ...: stimulus 4 is row 4
    assert(isequal(poH.Table.Selection(:)',4),'the selection did not follow its condition through a re-sort');
    btnAll.ButtonPushedFcn(btnAll,[]);
    pick(key1,'Frequency'); pick(dir2,'descend');       % back to 2 1 4 3 6 5
    select_row(poH,2);                                  % 8 kHz, 30 dB = stimulus 1, first in the PLOT
    btnAbove.ButtonPushedFcn(btnAbove,[]);
    assert(isequal(find(~schH.isEnabled()),2), ...
        'Disable above used the plot''s order, not the table''s: off = %s',mat2str(find(~schH.isEnabled())));
    btnBelow.ButtonPushedFcn(btnBelow,[]);
    assert(isequal(find(schH.isEnabled()),1),'Disable below from row 2: on = %s',mat2str(find(schH.isEnabled())));
    btnAll.ButtonPushedFcn(btnAll,[]);

    % Two rows picked: the reach starts at the outer edge of the selection.
    poH.Table.Selection = [2 4];
    poH.Table.SelectionChangedFcn(poH.Table,[]);
    btnAbove.ButtonPushedFcn(btnAbove,[]);
    assert(isequal(find(~schH.isEnabled()),2),'Disable above with two rows picked should reach from the upper one');
    assert(isequal(poH.Table.Selection(:)',[2 4]), ...
        'a two-row selection did not survive the table being rewritten: %s',mat2str(poH.Table.Selection));
    btnAll.ButtonPushedFcn(btnAll,[]);
    poH.Table.Selection = [2 4];
    poH.Table.SelectionChangedFcn(poH.Table,[]);
    btnBelow.ButtonPushedFcn(btnBelow,[]);
    % Table order 2 1 4 3 6 5, rows 2 and 4 picked: below row 4 is stimuli 6 and 5.
    assert(isequal(sort(find(~schH.isEnabled())),[5 6]),'Disable below with two rows picked should reach from the lower one');
    btnAll.ButtonPushedFcn(btnAll,[]);
    pick(key1,'');                                      % leave the sort as a new window finds it
end

% -- A switched-off condition: greyed, no "(off)"; bold grey when it is playing --
fcH = mabrtest.FakeController(schH,bank);
poH.listenTo(fcH);
fcH.setState(mabr.ui.ProgState.PrepBlock);
fcH.setState(mabr.ui.ProgState.Acquire);
fcH.metrics(3);
playing = schH.Runs{1}(1);
schH.setEnabled(playing,false);                          % the run's rendered; the label says what's next
poH.refresh(true);
lblH = poH.Axes.YTickLabel;
rowP = find(poH.Rows == playing);
assert(~any(contains(lblH,'off')),'a row label still says "(off)": %s',strjoin(lblH,' | '));
assert(startsWith(lblH{rowP},'\bf\color[rgb]{0.600,0.620,0.650}'), ...
    'the playing, switched-off condition should be bold grey: "%s"',lblH{rowP});
schH.setEnabled(playing,true);
poH.refresh(true);
assert(startsWith(poH.Axes.YTickLabel{rowP},'\bf\color[rgb]{0.702,0.420,0.000}'), ...
    'a playing condition that is on should be bold amber');
poH.listenTo([]);
poH.attach(schH,bank);

% -- Stay on top ---------------------------------------------------------------
assert(~strcmp(char(poH.Figure.WindowStyle),'alwaysontop') && ~btnTop.Value,'the window starts on top');
btnTop.Value = true;
btnTop.ValueChangedFcn(btnTop,struct('Value',true));
assert(strcmp(char(poH.Figure.WindowStyle),'alwaysontop') && poH.AlwaysOnTop, ...
    'Stay on top did not put the window on top');
assert(isequal(getpref('MABR','OrderOnTop'),true),'the button did not remember Stay on top');
poT = mabr.ui.PresentationOrder();
cleanT = onCleanup(@() delete(poT)); %#ok<NASGU>
assert(strcmp(char(poT.Figure.WindowStyle),'alwaysontop') && poT.AlwaysOnTop ...
    && findobj(poT.Figure,'Tag','OrderOnTop').Value,'a new window did not open on top as the last was left');
delete(poT);
btnTop.Value = false;
btnTop.ValueChangedFcn(btnTop,struct('Value',false));
assert(strcmp(char(poH.Figure.WindowStyle),'normal') && ~poH.AlwaysOnTop,'Stay on top did not let go');
assert(isequal(getpref('MABR','OrderOnTop'),false),'the button did not remember turning it off');
% A script setting the property moves the window and the button, never the pref.
poH.AlwaysOnTop = true;
assert(strcmp(char(poH.Figure.WindowStyle),'alwaysontop') && btnTop.Value,'the property did not reach the window and the button');
assert(isequal(getpref('MABR','OrderOnTop'),false),'setting the property rewrote the pref');
poH.AlwaysOnTop = false;
fprintf('  PASS Part H: Skip next, Disable above / below, Enable all, greyed labels, Stay on top\n');

% ---- Part I: the y axis is in the table's order ----------------------------------
for iP = 1:numel(prefNames)
    if ispref('MABR',prefNames{iP}), rmpref('MABR',prefNames{iP}); end
end
FREQ  = [8 8 16 16 32 32];           % stimulus index -> its parameters (see the bank above)
LEVEL = [30 60 30 60 30 60];
nameOf = @(s) sprintf('%g kHz, %g dB',FREQ(s),LEVEL(s));
schI = mabr.stim.Schedule(bank,cfg);
schI.Strategy    = 'conventional';
schI.Repetitions = 10;
schI.ISI         = 0.02;
schI.build();
poI = mabr.ui.PresentationOrder();
cleanI = onCleanup(@() delete(poI)); %#ok<NASGU>
poI.MinInterval = 0;
poI.attach(schI,bank);
key1 = findobj(poI.Figure,'Tag','OrderSortKey1');
key2 = findobj(poI.Figure,'Tag','OrderSortKey2');
dir1 = findobj(poI.Figure,'Tag','OrderSortDir1');
dir2 = findobj(poI.Figure,'Tag','OrderSortDir2');
pick = @(h,v) set_dropdown(h,v);

% No sort: the bank's parameters ascending, on the axis as in the table.
assert(isequal(plot_labels(poI),arrayfun(nameOf,1:n,'UniformOutput',false)), ...
    'with no sort the y axis should read the bank in order: %s',strjoin(plot_labels(poI),' | '));
assert_plot_follows_table(poI,nameOf);

% Frequency ascending, then Level descending: the table's order, now the plot's.
pick(key1,'Frequency'); pick(key2,'Level'); pick(dir2,'descend');
want = {'8 kHz, 60 dB','8 kHz, 30 dB','16 kHz, 60 dB','16 kHz, 30 dB','32 kHz, 60 dB','32 kHz, 30 dB'};
assert(isequal(plot_labels(poI),want),'the y axis did not take the table''s order: %s', ...
    strjoin(plot_labels(poI),' | '));
assert(isequal(poI.Rows,[2 1 4 3 6 5]),'Rows is %s',mat2str(poI.Rows));
assert_plot_follows_table(poI,nameOf);

% The highlight and every mark follow their condition through a re-sort.
fcI = mabrtest.FakeController(schI,bank);
poI.listenTo(fcI);
fcI.setState(mabr.ui.ProgState.PrepBlock);
fcI.setState(mabr.ui.ProgState.Acquire);
fcI.metrics(4);
cur1 = schI.Runs{1}(1);
assert(numel(poI.DoneLine.XData) == 4,'the run''s four presentations are not drawn as done');
check_active(poI,cur1);
assert_plot_follows_table(poI,nameOf);
pick(dir2,'ascend');                                   % 8/30 8/60 16/30 16/60 32/30 32/60
assert(isequal(poI.Rows,1:6),'Frequency, Level ascending: %s',mat2str(poI.Rows));
check_active(poI,cur1); assert_plot_follows_table(poI,nameOf);
pick(dir1,'descend');                                  % 32/30 32/60 16/30 16/60 8/30 8/60
assert(isequal(poI.Rows,[5 6 3 4 1 2]),'Frequency descending, Level ascending: %s',mat2str(poI.Rows));
check_active(poI,cur1); assert_plot_follows_table(poI,nameOf);

% A sort on a count that moves re-lays the plot when the count does. The
% conditions with nothing left to come -- the run in progress, then the one
% before it -- gather at the bottom of the table, and of the plot.
pick(key1,'Upcoming'); pick(dir1,'descend'); pick(key2,'');
u = cell2mat(poI.Table.Data(:,strcmp(poI.Table.ColumnName,'Upcoming')));
assert(all(diff(u) <= 0) && u(end) == 0 && poI.Rows(end) == cur1, ...
    'Upcoming descending: the run in progress should be last (rows %s, upcoming %s)', ...
    mat2str(poI.Rows),mat2str(u(:).'));
assert_plot_follows_table(poI,nameOf);
schI.recordRun(1,accumarray(schI.Runs{1}(:),1,[n 1]).');
fcI.setState(mabr.ui.ProgState.BlockComplete);
schI.advance();
fcI.setState(mabr.ui.ProgState.PrepBlock);
fcI.setState(mabr.ui.ProgState.Acquire);
fcI.metrics(2);
cur2 = schI.Runs{2}(1);
u = cell2mat(poI.Table.Data(:,strcmp(poI.Table.ColumnName,'Upcoming')));
assert(all(diff(u) <= 0) && isequal(sort(poI.Rows(end-1:end)),sort([cur1 cur2])), ...
    'after run 2 starts the two finished conditions should be last: rows %s',mat2str(poI.Rows));
assert_plot_follows_table(poI,nameOf);
check_active(poI,cur2);

% A box ticked does not move a row -- on the axis any more than in the table --
% until the next sort, which then puts the off condition where On says.
pick(key1,'On'); pick(dir1,'ascend');
base = plot_labels(poI);
tog = schI.Runs{4}(1);
r = find(poI.Rows == tog);
poI.Table.CellEditCallback(poI.Table,struct('Indices',[r 1],'NewData',false,'PreviousData',true));
assert(~schI.isEnabled(tog),'the On box did not reach the schedule');
assert(isequal(plot_labels(poI),base),'ticking an On box moved a row on the y axis');
assert_plot_follows_table(poI,nameOf);
pick(dir1,'descend');                                  % on first, off last
assert(poI.Rows(end) == tog && ~poI.Table.Data{end,1},'On descending should put the off condition last');
assert_plot_follows_table(poI,nameOf);
pick(dir1,'ascend');                                   % off first
assert(poI.Rows(1) == tog && ~poI.Table.Data{1,1},'On ascending should put the off condition first');
assert_plot_follows_table(poI,nameOf);
% Its upcoming presentations are the crosses, at the height of its row.
xs = poI.OffLine.XData; ys = poI.OffLine.YData;
assert(numel(xs) == 10 && all(ys == 1) && all(poI.Sequence(xs) == tog), ...
    'the crosses are not at the switched-off condition''s row');

% Disable above reaches what is above on the PLOT.
if isprop(poI.Table,'Selection') && isprop(poI.Table,'SelectionType')
    select_row(poI,3);
    btnA = findobj(poI.Figure,'Tag','OrderDisAbove');
    btnA.ButtonPushedFcn(btnA,[]);
    assert(isequal(sort(find(~schI.isEnabled())),sort(poI.Rows(1:2))), ...
        'Disable above did not take the two rows at the top of the plot: off = %s, rows %s', ...
        mat2str(find(~schI.isEnabled())),mat2str(poI.Rows));
    assert(isequal(plot_labels(poI),plot_labels_from_rows(poI,nameOf)),'the plot lost its order');
end
btnAll = findobj(poI.Figure,'Tag','OrderEnableAll');
btnAll.ButtonPushedFcn(btnAll,[]);
pick(key1,'');                                         % leave the sort as a new window finds it
assert_plot_follows_table(poI,nameOf);
fprintf('  PASS Part I: the y axis is in the table''s order\n');

% ---- Part J: switching is off while an intermixed run plays ------------------------
schJ = mabr.stim.Schedule(bank,cfg);
schJ.Strategy    = 'interleaved-random';
schJ.Repetitions = 50;
schJ.ISI         = 0.02;
schJ.build();
poJ = mabr.ui.PresentationOrder();
cleanJ = onCleanup(@() delete(poJ)); %#ok<NASGU>
poJ.MinInterval = 0;
poJ.attach(schJ,bank);
bSkip  = findobj(poJ.Figure,'Tag','OrderSkipNext');
bAbove = findobj(poJ.Figure,'Tag','OrderDisAbove');
bBelow = findobj(poJ.Figure,'Tag','OrderDisBelow');
bAll   = findobj(poJ.Figure,'Tag','OrderEnableAll');
isOn   = @(b) strcmp(char(b.Enable),'on');
canSelect = isprop(poJ.Table,'Selection') && isprop(poJ.Table,'SelectionType');
lockedNow = @() any(contains({bAll.Tooltip,bAbove.Tooltip,bBelow.Tooltip,bSkip.Tooltip,poJ.Table.Tooltip}, ...
    'Not available'));
noteSays  = @() any(contains(string({findall(poJ.Figure,'Type','uilabel').Text}),'Not available'));
onCol = @() find(strcmp(poJ.Table.ColumnName,'On'));

% Nothing playing: the boxes are there to use.
assert(isequal(poJ.Table.ColumnEditable,[true false false false]),'the On boxes are not editable at rest');
schJ.setEnabled(1,false);                              % something to switch back on
fcJ = mabrtest.FakeController(schJ,bank);
poJ.listenTo(fcJ);
if canSelect, select_row(poJ,3); end
assert(isOn(bAll) && (~canSelect || (isOn(bAbove) && isOn(bBelow))),'the switches should be live before the run');
assert(~lockedNow() && ~noteSays(),'a lock is explained with nothing playing');

fcJ.setState(mabr.ui.ProgState.PrepBlock);
fcJ.setState(mabr.ui.ProgState.Acquire);
fcJ.metrics(10);
assert(~isOn(bAll) && ~isOn(bAbove) && ~isOn(bBelow) && ~isOn(bSkip), ...
    'the buttons are live while an intermixed run plays');
assert(~any(poJ.Table.ColumnEditable),'the On boxes are still editable while an intermixed run plays');
assert(lockedNow() && noteSays(),'the lock does not say why');
assert(all(contains({bAll.Tooltip,bAbove.Tooltip,bBelow.Tooltip,bSkip.Tooltip,poJ.Table.Tooltip}, ...
    'Not available')),'a locked control is missing its reason');
% Driven anyway (a script, a stale click), nothing happens and the table says what the plan holds.
offBefore = find(~schJ.isEnabled());
poJ.Table.CellEditCallback(poJ.Table,struct('Indices',[2 onCol()],'NewData',false,'PreviousData',true));
for b = [bAll bAbove bBelow bSkip], b.ButtonPushedFcn(b,[]); end
assert(isequal(find(~schJ.isEnabled()),offBefore),'a locked window changed the schedule');
assert(isequal(cell2mat(poJ.Table.Data(:,onCol())).',schJ.isEnabled(poJ.Rows)), ...
    'the table does not show what the plan holds after a refused edit');
% The views stay live: the sort still answers.
pick(findobj(poJ.Figure,'Tag','OrderSortKey1'),'Level');
assert(isequal(cell2mat(poJ.Table.Data(:,3)).',[30 30 30 60 60 60]),'the sort stopped answering while locked');

% The run ends: everything comes back.
sch1 = accumarray(schJ.Runs{1}(:),1,[n 1]).';
schJ.recordRun(1,sch1);
fcJ.setState(mabr.ui.ProgState.BlockComplete);
assert(isOn(bAll) && isequal(poJ.Table.ColumnEditable(onCol()),true),'the switches did not come back when the run ended');
assert(~lockedNow() && ~noteSays(),'the lock is still explained after the run');
if canSelect
    select_row(poJ,3);
    assert(isOn(bAbove) && isOn(bBelow),'Disable above / below did not come back');
end
btnAllJ = bAll; btnAllJ.ButtonPushedFcn(btnAllJ,[]);
assert(all(schJ.isEnabled()),'Enable all does nothing after the run');

% A later run waiting: an intermixed plan with a make-up run behind it is not
% locked while the first plays, and is for the last.
schK = mabr.stim.Schedule(bank,cfg);
schK.Strategy = 'interleaved-random'; schK.Repetitions = 50; schK.ISI = 0.02; schK.build();
schK.appendMakeup([0 0 0 0 0 5]);
assert(schK.NumRuns == 2,'expected a make-up run behind the intermixed one');
fcK = mabrtest.FakeController(schK,bank);
poJ.listenTo(fcK);
fcK.setState(mabr.ui.ProgState.PrepBlock);
fcK.setState(mabr.ui.ProgState.Acquire);
assert(poJ.Table.ColumnEditable(onCol()) && ~lockedNow(),'locked with a later run waiting for the switch');
schK.recordRun(1,accumarray(schK.Runs{1}(:),1,[n 1]).');
fcK.setState(mabr.ui.ProgState.BlockComplete);
schK.advance();
fcK.setState(mabr.ui.ProgState.PrepBlock);
fcK.setState(mabr.ui.ProgState.Acquire);
assert(~poJ.Table.ColumnEditable(onCol()) && lockedNow(),'not locked while the last run plays');

% A conventional plan is never locked: its runs each present one condition.
schL = mabr.stim.Schedule(bank,cfg);
schL.Strategy = 'conventional'; schL.Repetitions = 10; schL.ISI = 0.02; schL.build();
fcL = mabrtest.FakeController(schL,bank);
poJ.listenTo(fcL);
fcL.setState(mabr.ui.ProgState.PrepBlock);
fcL.setState(mabr.ui.ProgState.Acquire);
fcL.metrics(3);
assert(poJ.Table.ColumnEditable(onCol()) && isOn(bSkip) && ~lockedNow() && ~noteSays(), ...
    'a conventional plan was locked while it played');
fprintf('  PASS Part J: switching is off while an intermixed run plays\n');

fprintf('== verify_presentation_order: all checks passed ==\n');
end

% ----------------------------------------------------------------------
function set_dropdown(h,v)
% Choose a value as a user does: set it, then run the control's callback.
h.Value = v;
h.ValueChangedFcn(h,struct('Value',v));
end

function select_row(po,r)
% Pick a table row as a click does: the table holds the selection, then
% reports it.
po.Table.Selection = r;
po.Table.SelectionChangedFcn(po.Table,[]);
end

function tf = po_row_on(po,stim)
% What the table's On box shows for a stimulus. The table and the y axis are
% one list (Rows), so the stimulus's row is the same in both.
tf = po.Table.Data{find(po.Rows == stim,1),1};
end

function lbl = plot_labels(po)
% What the y axis reads, top to bottom, with the markup of the active row
% (bold) and a switched-off row (grey) taken off.
lbl = regexprep(po.Axes.YTickLabel(:).','^(\\bf)?(\\color\[rgb\]\{[^}]*\})?','');
end

function lbl = plot_labels_from_rows(po,nameOf)
% What the y axis should read for the stimuli in po.Rows, in that order.
lbl = arrayfun(nameOf,po.Rows,'UniformOutput',false);
end

function assert_plot_follows_table(po,nameOf)
% The y axis and the table are one list: the same conditions in the same
% order -- and every mark (pending, done, switched off) sits at the height of
% its own condition's label, so the order is what is drawn and not only what
% is written beside it.
lbl = plot_labels(po);
D   = po.Table.Data;
fc  = find(strcmp(po.Table.ColumnName,'Frequency (kHz)'));
lc  = find(strcmp(po.Table.ColumnName,'Level (dB)'));
fromTable = arrayfun(@(r) sprintf('%g kHz, %g dB',D{r,fc},D{r,lc}),1:size(D,1),'UniformOutput',false);
assert(isequal(lbl,fromTable),'the y axis and the table disagree:\n  plot  %s\n  table %s', ...
    strjoin(lbl,' | '),strjoin(fromTable,' | '));
assert(isequal(lbl,plot_labels_from_rows(po,nameOf)),'the y axis does not read po.Rows: %s', ...
    strjoin(lbl,' | '));
for h = [po.PendingLine po.DoneLine po.OffLine]
    x = h.XData; y = h.YData;
    ok = ~isnan(x) & ~isnan(y);
    assert(all(y(ok) >= 1 & y(ok) <= numel(lbl)),'a mark is off the y axis');
    assert(isequal(lbl(y(ok)),arrayfun(nameOf,po.Sequence(x(ok)),'UniformOutput',false)), ...
        'a mark is not at its own condition''s height on the y axis');
end
end

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
