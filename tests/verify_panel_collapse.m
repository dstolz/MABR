function verify_panel_collapse()
% verify_panel_collapse  The main window's folding panels, no hardware, no window.
%
%   Every panel of the main window but Run folds up to its title bar, and the
%   window's height is refitted to the panels as they are. The arithmetic is
%   mabr.ui.App.fittedHeight and the reading of a saved list is
%   mabr.ui.App.collapsedList, statics of plain values, so they are verified
%   here without constructing an App (the suite runs from inside that window,
%   and a second one refuses to open). Nothing here touches a preference.
%
%   Part A (the height): the window's own rows give the height it has always
%   had (806 px), and folding a panel takes off exactly its open height less
%   the title bar it keeps -- the '1x' spacer contributing no height of its own
%   and every row its spacing.
%   Part B (a saved list): names are read back in window order, once each, and
%   anything else -- Run, an unknown panel, a char, a string, a number, junk --
%   is passed over rather than refused.
%   Part C (the wiring): Run is not foldable and the four other panels are, the
%   chevrons are in no control list (so a running schedule never locks them),
%   and what is folded travels in a configuration both ways.
%
%   Run:  >> verify_panel_collapse
%
%   See also mabr.ui.App, verify_history_remove, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_panel_collapse ==\n');
root = fileparts(fileparts(mfilename('fullpath')));
src  = fileread(fullfile(root,'+mabr','+ui','App.m'));
fit  = @mabr.ui.App.fittedHeight;

% ---- Part A: the height -----------------------------------------------------
tok = regexp(src,'app\.Grid\.RowHeight\s*=\s*(\{[^}]*\});','tokens','once');
assert(~isempty(tok),'could not find the main grid''s RowHeight in App.m');
rows = eval(tok{1});
sp   = 8;
pad  = [10 10 10 6];
sl   = mabr.ui.App.WindowSlack;
assert(fit(rows,sp,pad,sl) == 806, ...
    'with every panel open the window must be the 806 px it has always been (got %g)', ...
    fit(rows,sp,pad,sl));

T = 24;
for k = 1:4
    r = rows; r{k} = T;
    assert(fit(rows,sp,pad,sl) - fit(r,sp,pad,sl) == rows{k} - T, ...
        'folding row %d must take off its open height less the title bar',k);
end
r = rows; r(1:4) = {T};
assert(fit(r,sp,pad,sl) == 806 - sum([rows{1:4}]) + 4*T, ...
    'folding all four must take off all four');
assert(fit({'1x'},sp,[0 0 0 0],0) == 0 && fit({'1x',10},sp,[0 0 0 0],0) == 10 + sp, ...
    'a ''1x'' row has spacing and no height of its own');
fprintf('  PASS Part A: the window is fitted to its panels, open or folded\n');

% ---- Part B: a saved list ---------------------------------------------------
known = mabr.ui.App.CollapsibleSections;
cl = @(v) mabr.ui.App.collapsedList(v,known);
assert(isequal(cl({'Acquisition','Session'}),{'Session','Acquisition'}), ...
    'names must come back in window order');
assert(isequal(cl({'Stimulus','Stimulus'}),{'Stimulus'}),'a name must come back once');
assert(isequal(cl('Presentation'),{'Presentation'}),'a char must read as one name');
assert(isequal(cl(["Session" "Stimulus"]),{'Session','Stimulus'}),'a string array must read');
assert(isempty(cl({'Run'})),'Run is not a panel that folds');
assert(isempty(cl({'Nope',3,struct()})),'unknown names and junk must be passed over');
for v = {[],3,struct('a',1),{},'',true}
    c = cl(v{1});
    assert(iscell(c) && isempty(c),'junk must read as nothing folded');
end
fprintf('  PASS Part B: a saved list is read forgivingly\n');

% ---- Part C: the wiring -----------------------------------------------------
assert(~any(strcmp(known,'Run')) && numel(known) == 4,'every panel but Run must fold');
for nm = known
    assert(~isempty(regexp(src,['app\.sectionGrid\(''' nm{1} ''''],'once')), ...
        'the %s panel must be built by sectionGrid',nm{1});
end
assert(~isempty(regexp(src,'app\.panelGrid\(''Run''','once')), ...
    'the Run panel must be an ordinary panel');
for fn = {'configControls','liveControls','allControls'}
    body = regexp(src,['function h = ' fn{1} '\(app\)(.*?)\n        end'],'tokens','once');
    assert(~isempty(body),'could not find %s in App.m',fn{1});
    assert(~contains(body{1},'Toggle') && ~contains(body{1},'Sections'), ...
        'the chevrons must not be in %s: folding a panel must never be locked',fn{1});
end
assert(contains(src,'cfg.CollapsedPanels = app.collapsedNames()'), ...
    'a configuration must carry which panels are folded');
assert(contains(src,'isfield(cfg,''CollapsedPanels'')'), ...
    'loading a configuration must fold what it names');
fprintf('  PASS Part C: Run stays open, the chevrons are never locked, configurations carry it\n');

fprintf('== verify_panel_collapse PASSED ==\n');
end
