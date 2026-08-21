function verify_test_runner()
% verify_test_runner  Exercise the GUI that runs this suite.
%
%   Checks, with no audio hardware and no acquisition engine:
%       1. discovery finds every verify_*.m in tests/ -- nothing is listed
%          here by hand, so a test that exists is a test the window offers;
%       2. the list is ordered the way run_all_verifications runs it, which
%          mabr.ui.TestRunner reads out of that file rather than repeating;
%       3. every discovered name is actually callable and carries its H1 line
%          as a description;
%       4. the output capture: a passing call reports PASS with its printed
%          output, a throwing one reports FAIL with the message AND keeps
%          what was printed before the throw, and name-value arguments reach
%          the test;
%       5. an end-to-end run driven the way a user drives it -- tick a box in
%          the table, press Run Selected -- lands a verdict in the table, the
%          output in the log, and a tally in the summary, and leaves the
%          tests that were not ticked alone.
%
%   The App's Help-menu item is deliberately not checked here: constructing
%   mabr.ui.App stands up the whole acquisition window for one uimenu -- and
%   this file runs *inside* the window it is testing when the suite is
%   launched from that very menu.
%
%   The nested run uses verify_filters: it is the cheapest test in the suite
%   that needs neither a parallel pool nor a device, so this stays quick and
%   cannot recurse.
%
%   Run:  >> verify_test_runner
%
%   See also mabr.ui.TestRunner, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_test_runner ==\n');

% --- 1-3. discovery ------------------------------------------------------
w = mabr.ui.TestRunner();
clean = onCleanup(@() delete(w));
t = w.Tests;

folder  = fileparts(which('run_all_verifications'));
onDisk  = dir(fullfile(folder,'verify_*.m'));
assert(numel(t) == numel(onDisk), ...
    'discovered %d tests but tests/ holds %d verify_*.m files',numel(t),numel(onDisk));
assert(isequal(sort({t.Name}),sort(erase({onDisk.name},'.m'))), ...
    'the discovered names are not the files on disk');

% The order the suite runs them in, read from the same place the window reads
% it, so this asserts they agree rather than asserting a copy of the list.
listed = regexp(fileread(fullfile(folder,'run_all_verifications.m')),'@(verify_\w+)','tokens');
listed = unique([listed{:}],'stable');
assert(isequal({t(1:numel(listed)).Name},listed), ...
    'the window does not list the suite in run_all_verifications'' order');

assert(all(cellfun(@(n) ~isempty(which(n)),{t.Name})), ...
    'a discovered test is not on the path -- the window could not run it');
assert(all(~cellfun(@isempty,{t.Summary})),'every test should carry its H1 line');
assert(all([t.Selected]),'everything should start ticked');
fprintf('  PASS 1-3: %d tests discovered, in suite order, all callable\n',numel(t));

% --- 4. output capture and verdicts --------------------------------------
[ok,msg,out] = mabr.ui.TestRunner.runOne(@() fprintf('quiet success\n'),{});
assert(ok && isempty(msg),'a clean call must pass with no message');
assert(contains(out,'quiet success'),'printed output was not captured');

[ok,msg,out] = mabr.ui.TestRunner.runOne(@() thrower(),{});
assert(~ok,'a throwing call must fail');
assert(strcmp(msg,'boom 3'),'the error message was not carried: %s',msg);
assert(contains(out,'printed before the throw'), ...
    'output printed before the failure was lost -- that is the part that says how far it got');
assert(contains(out,'mabr:test:boom') || contains(out,'boom 3'), ...
    'the error report should be in the captured text');

[ok,~,out] = mabr.ui.TestRunner.runOne(@(varargin) fprintf('%d args\n',numel(varargin)), ...
    {'Testing',false});
assert(ok && contains(out,'2 args'),'name-value arguments did not reach the test');
fprintf('  PASS 4: pass/fail verdicts, partial output kept, arguments forwarded\n');

% --- 5. an end-to-end run, driven through the controls -------------------
% This window's own handle, not whatever findall turns up: run from the App's
% Help menu, this test executes with a second runner already on screen.
fig = w.UIFigure;
assert(isgraphics(fig),'the runner window did not open');
tbl = findall(fig,'Type','uitable');
assert(size(tbl.Data,2) == 5 && islogical(tbl.Data{1,1}), ...
    'the Run column must be logical so it draws as a checkbox');

keep = find(strcmp({t.Name},'verify_filters'));
for i = 1:numel(t)
    if i ~= keep
        tbl.CellEditCallback(tbl,struct('Indices',[i 1],'NewData',false));
    end
end
assert(sum([w.Tests.Selected]) == 1,'unticking through the table did not take');

btn = findall(fig,'Type','uibutton','Text','Run Selected');
btn.ButtonPushedFcn(btn,struct());
drawnow

assert(strcmp(w.Tests(keep).Status,'PASS'), ...
    'verify_filters reported "%s" through the window',w.Tests(keep).Status);
assert(w.Tests(keep).Time > 0,'no elapsed time was recorded');
others = setdiff(1:numel(t),keep);
assert(all(cellfun(@isempty,{w.Tests(others).Status})), ...
    'a test that was not ticked was run anyway');
assert(strcmp(tbl.Data{keep,3},'PASS'),'the table did not pick up the verdict');

log = findall(fig,'Type','uitextarea').Value;
assert(any(contains(log,'verify_filters PASSED')),'the test output did not reach the log');
assert(any(contains(log,'1 passed, 0 failed')),'the log has no tally');
labels = findall(fig,'Type','uilabel');
assert(any(contains({labels.Text},'1 passed, 0 failed')),'the summary label was not updated');
fprintf('  PASS 5: Run Selected drives the table, the log, and the summary\n');

fprintf('== verify_test_runner PASSED ==\n');
end


% =====================================================================
function thrower()
fprintf('printed before the throw\n');
error('mabr:test:boom','boom %d',3);
end
