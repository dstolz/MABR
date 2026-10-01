function verify_history_remove()
% verify_history_remove  The − beside Subject ID and Output, no hardware, no window.
%
%   Subject ID and Output are dropdowns of what was used before (Subject ID
%   editable, Output showing the end of each path), and a
%   − beside each takes the entry on show off that list. What it does to the
%   list is mabr.ui.App.withoutHistoryValue, a static of plain values, so it is
%   verified here without constructing an App (the suite runs from inside that
%   window, and a second one refuses to open). Nothing here touches a preference.
%
%   Part A (removing): the entry on show goes, and the field moves on to the
%   one that took its place -- the next one down, or the last if it was last --
%   so pressing − again walks down the list; the list keeps its shape.
%   Part B (not there): a value typed but never used, an empty field, and a
%   different case change nothing, and say so.
%   Part C (the last one): a list this empties starts over from its default,
%   because the dropdown always has an item to show; and the one entry that is
%   already the default stays.
%   Part D (the buttons): both − buttons are locked with the fields they belong
%   to while a schedule runs, and Browse is a picture rather than a caption.
%   Part E (the Output labels): Output is not editable, because an editable
%   dropdown shows the START of a long path. Each folder is labelled by the END
%   of its path (mabr.ui.App.tailLabels), whole folders from the right behind a
%   leading …, within the room the box has; the labels are distinct however
%   alike the paths end, since they are dropdown items; and "(not saved)" is the
%   one value that reads back as the empty path.
%
%   Run:  >> verify_history_remove
%
%   See also mabr.ui.App, verify_recent_banks, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_history_remove ==\n');
wo = @mabr.ui.App.withoutHistoryValue;
dflt = {'D'};

% ---- Part A: removing -----------------------------------------------------------
[it,nx,rm] = wo({'a','b','c'},'b',dflt);
assert(rm && isequal(it,{'a','c'}) && strcmp(nx,'c'), ...
    'removing the middle entry must leave the others, and show the one that moved up');
[it,nx,rm] = wo({'a','b','c'},'a',dflt);
assert(rm && isequal(it,{'b','c'}) && strcmp(nx,'b'), ...
    'removing the first entry must show the one that is now first');
[it,nx,rm] = wo({'a','b','c'},'c',dflt);
assert(rm && isequal(it,{'a','b'}) && strcmp(nx,'b'), ...
    'removing the last entry must show the one before it');
assert(isequal(size(it),[1 2]),'the list must stay a row');

% Pressing it again with whatever is then on show walks down the list.
it = {'a','b','c','d'};
shown = {};
for k = 1:3
    v = it{1};
    [it,nx,~] = wo(it,v,dflt);
    shown{end+1} = nx; %#ok<AGROW>
end
assert(isequal(shown,{'b','c','d'}) && isequal(it,{'d'}), ...
    'repeated removal from the top must walk the list down, one at a time');
fprintf('  PASS Part A: the entry on show goes and the field moves on\n');

% ---- Part B: not on the list ----------------------------------------------------
orig = {'a','b','c'};
for v = {'z','','B'}
    [it,nx,rm] = wo(orig,v{1},dflt);
    assert(~rm && isequal(it,orig) && strcmp(nx,v{1}), ...
        'a value not on the list ("%s") must leave the list and the field alone',v{1});
end
fprintf('  PASS Part B: a value that was never used changes nothing\n');

% ---- Part C: the last one -------------------------------------------------------
[it,nx,rm] = wo({'a'},'a',dflt);
assert(rm && isequal(it,dflt) && strcmp(nx,'D'), ...
    'emptying the list must start it over from its default, and show that');
[it,nx,rm] = wo({'D'},'D',dflt);
assert(rm && isequal(it,{'D'}) && strcmp(nx,'D'), ...
    'the only entry, when it is the default, must stay');
fprintf('  PASS Part C: the list is never left without an item to show\n');

% ---- Part D: the buttons --------------------------------------------------------
root = fileparts(fileparts(mfilename('fullpath')));
src = fileread(fullfile(root,'+mabr','+ui','App.m'));
body = regexp(src,'function h = configControls\(app\)(.*?)\n        end','tokens','once');
assert(~isempty(body),'could not find configControls in App.m');
for nm = {'SubjectRemoveButton','OutputRemoveButton','BrowseButton'}
    assert(contains(body{1},['app.' nm{1}]), ...
        '%s must be a config control: it changes the field that locks while a schedule runs',nm{1});
end
assert(~isempty(regexp(src,'setButtonIcon\(\s*app\.BrowseButton\s*,\s*''load''','once')), ...
    'Browse must be a picture (the open-folder glyph), not a caption');
fprintf('  PASS Part D: the − buttons lock with their fields, and Browse is a folder\n');

% ---- Part E: the Output labels --------------------------------------------------
tl = @mabr.ui.App.tailLabels;
dots = char(8230);
short = 'C:\Data\Mouse12';
long  = 'C:\Users\dstolz\Documents\ABR\2026\Cohort3\Mouse12';
lb = tl({short,long},30);
assert(strcmp(lb{1},short),'a path that fits must be shown whole');
assert(numel(lb{2}) <= 30 && lb{2}(1) == dots && endsWith(long,lb{2}(2:end)), ...
    'a path that does not fit must be its own end behind a leading …');
assert(lb{2}(2) == '\', ...
    'the cut must fall on a folder boundary, so only whole folders are shown');
assert(endsWith(lb{2},'Mouse12'),'the lowest folder is the one that must always show');

% One folder longer than the room: a cut name, never its start.
lb = tl({'C:\x\AVeryLongFolderNameIndeedItIsLongerThanTheBox'},20);
assert(numel(lb{1}) <= 20 && lb{1}(1) == dots && endsWith(lb{1},'ThanTheBox'), ...
    'a last folder longer than the box must show its end');

% Paths that end alike are told apart by their first folders -- and a label
% is still the start of its path, a …, and the end of it, within the room.
p = {'C:\A\2026\Cohort3\Mouse12','D:\B\2026\Cohort3\Mouse12','C:\A\2026\Cohort3\Mouse12b'};
lb = tl(p,18);
assert(numel(unique(lb)) == numel(p),'labels are dropdown items and must be distinct');
for k = 1:numel(p)
    assert(numel(lb{k}) <= 18,'label %d must fit the room',k);
    assert(isLabelOf(lb{k},p{k}),'label %d must be made of its own path',k);
    assert(endsWith(lb{k},'Mouse12') || endsWith(lb{k},'Mouse12b'),'label %d must end the path',k);
end

% The same long folder on two drives: both fit the room, and both end at the
% lowest folder -- the case a longer tail would have answered with the whole path.
a = 'D:\Experiments\Rig2\Auditory\Brainstem\2026-09\Gerbil_Cohort3\Mouse10_baseline';
b = ['E' a(2:end)];
lb = tl({a,b},36);
assert(numel(unique(lb)) == 2 && all(cellfun(@numel,lb) <= 36),'both must fit, and differ');
assert(startsWith(lb{1},'D:\') && startsWith(lb{2},'E:\'),'the drive is what tells them apart');
assert(all(endsWith(lb,'\Mouse10_baseline')),'the lowest folder must still show');
assert(isLabelOf(lb{1},a) && isLabelOf(lb{2},b),'each label must be made of its own path');

% Where only the middle differs and no room remains for a head and an end, the
% tail is widened until they separate: distinct, never merged.
c = {'C:\Data\ABR\2026\CohortA\Mouse12','C:\Data\ABR\2026\CohortB\Mouse12'};
lb = tl(c,16);
assert(numel(unique(lb)) == 2,'labels that cannot share a head and an end must still differ');
assert(isempty(tl({},20)),'no paths must give no labels');
lone = tl({short},8);
assert(isscalar(lone) && strcmp(lone{1},[dots 'Mouse12']), ...
    'a lone path is only ever cut to the room there is, never widened');

% "(not saved)" is the one item that is not a folder.
assert(~isempty(mabr.ui.App.NoOutputSentinel) && ~isempty(mabr.ui.App.NoOutputText), ...
    'the not-saved item needs both a value and a label');
assert(~strcmp(mabr.ui.App.NoOutputSentinel,mabr.ui.App.NoOutputText), ...
    'the label is for people and the value for code; they must not be the same text');
assert(~isempty(regexp(src,'function v = outputFolder\(app\).*?NoOutputSentinel\), v = '''';','once')), ...
    'outputFolder must turn the not-saved item back into the empty path');
assert(isempty(regexp(src,'uidropdown\(g,''Editable'',''on'',[^;]*loadHistory\(''Output''','once')), ...
    'Output must not be an editable dropdown');
fprintf('  PASS Part E: Output shows the end of each path, distinctly, and "(not saved)" is empty\n');

fprintf('== verify_history_remove PASSED ==\n');
end

function tf = isLabelOf(label,p)
% LABEL is P itself, or its start, a …, and its end.
parts = strsplit(label,char(8230),'CollapseDelimiters',false);
if isscalar(parts)
    tf = strcmp(label,p);
else
    tf = numel(parts) == 2 && startsWith(p,parts{1}) && endsWith(p,parts{2});
end
end
