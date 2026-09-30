function verify_recent_banks()
% verify_recent_banks  The recent stimulus banks list, no hardware, no window.
%
%   mabr.stim.BankHistory is what the Stimulus panel's Bank dropdown lists, and
%   everything that list DECIDES lives in it -- mabr.ui.App is a dropdown and
%   a few buttons over it, which is also why this does not construct one (the
%   suite runs from inside that window, and a second one refuses to open).
%
%   Part A (adding): most recent first; several at once keep the order they
%   were given in; a file already listed moves to the front rather than
%   appearing twice, whatever its case; junk is ignored.
%   Part B (the cap): a full list pushes its OLDEST off the end and says how
%   many went; re-listing a file already on a full list costs nothing.
%   Part C (removing): one entry, and an entry that is not there -- without
%   touching the object it was called on.
%   Part D (labels): a file name alone, with the folder only where two names
%   collide, and always distinct, since they are a dropdown's items.
%   Part E (preferences): a round trip through the MABR pref group, and a
%   pref that holds anything at all -- junk, too many, nothing -- still loads.
%   Part F (the folder): where the bank dialogs open -- the folder last picked
%   from while it exists, else the newest listed bank's, else nowhere; kept
%   through the prefs, and never disturbed by junk.
%
%   The user's own preference is saved and restored around the run.
%
%   Run:  >> verify_recent_banks
%
%   See also mabr.stim.BankHistory, mabr.ui.App, run_all_verifications.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_recent_banks ==\n');

prefNames = {mabr.stim.BankHistory.PrefName, mabr.stim.BankHistory.FolderPrefName};
saved = save_prefs(prefNames);
restorePrefs = onCleanup(@() restore_prefs(prefNames,saved));
clear_prefs(prefNames);

a ='C:\banks\a.spl';
b = 'C:\banks\b.spl';
c = 'D:\more\c.mat';

% ---- Part A: adding -------------------------------------------------------
h = mabr.stim.BankHistory;
assert(h.count() == 0 && isequal(size(h.Files),[1 0]), ...
    'a new list should be empty, and a 1x0 cell so it can be a (1,:) property');
assert(isempty(h.labels()),'an empty list has no labels');

h = h.add(a).add(b);
assert(isequal(h.Files,{b,a}),'the most recently added file must come first');

h = mabr.stim.BankHistory().add({a,b,c});
assert(isequal(h.Files,{a,b,c}), ...
    'several files added at once must keep the order they were given in');

h = h.add(b);
assert(isequal(h.Files,{b,a,c}), ...
    'a file already listed moves to the front; it must not appear twice');

h = h.add(upper(c));                          % D:\MORE\C.MAT -- c, in capitals
assert(h.count() == 3 && strcmp(h.Files{1},upper(c)) && h.has(c), ...
    'the same path in another case is the same file (MABR is Windows-only)');
assert(h.has('c:\banks\A.SPL'),'has() should compare case-insensitively too');

n0 = h.count();
h = h.add({'',' ',42,{'nested'}});
assert(h.count() == n0,'empty, blank and non-text entries must be ignored');
h = h.add('  C:\banks\padded.spl  ');
assert(strcmp(h.Files{1},'C:\banks\padded.spl'),'surrounding whitespace must be trimmed');
fprintf('  PASS Part A: newest first, order kept, repeats move up, junk ignored\n');

% ---- Part B: the cap ------------------------------------------------------
nMax  = mabr.stim.BankHistory.Max;
files = arrayfun(@(k) sprintf('C:\\banks\\bank%02d.spl',k),1:nMax+3, ...
                 'UniformOutput',false);

[full,dropped] = mabr.stim.BankHistory().add(files(1:nMax));
assert(full.count() == nMax && dropped == 0,'a list may fill to Max without dropping');
assert(isequal(full.Files,files(1:nMax)),'and keep them in the order given');

[over,dropped] = full.add(files(nMax+1));
assert(over.count() == nMax && dropped == 1,'one more must push exactly one off');
assert(strcmp(over.Files{1},files{nMax+1}) && ~over.has(files{nMax}) && over.has(files{1}), ...
    'the OLDEST entry falls off the end, not the newest and not the first-listed');

[over3,dropped] = full.add(files(nMax+1:nMax+3));
assert(over3.count() == nMax && dropped == 3, ...
    'adding three to a full list should report three dropped');
assert(isequal(over3.Files(1:3),files(nMax+1:nMax+3)), ...
    'several added to a full list must still lead in the order given');

[same,dropped] = full.add(full.Files{end});
assert(same.count() == nMax && dropped == 0 && strcmp(same.Files{1},files{nMax}), ...
    're-listing a file already on a full list must move it up and drop nothing');

capped = mabr.stim.BankHistory(files);
assert(capped.count() == nMax && isequal(capped.Files,files(1:nMax)), ...
    'building a list from more than Max entries must keep the first Max');
fprintf('  PASS Part B: capped at %d, oldest drops, the count is reported\n',nMax);

% ---- Part C: removing -------------------------------------------------------
h0 = mabr.stim.BankHistory().add({a,b,c});
h1 = h0.remove(b);
assert(isequal(h1.Files,{a,c}),'remove should take exactly that entry off');
assert(isequal(h0.Files,{a,b,c}), ...
    'remove must not change the object it was called on -- this is a value object');
assert(isequal(h0.remove('C:\banks\B.SPL').Files,{a,c}),'remove is case-insensitive');
assert(isequal(h0.remove('C:\nowhere\x.spl').Files,h0.Files), ...
    'removing a file that is not listed must be a no-op, not an error');
e = h0.remove(a).remove(b).remove(c);
assert(e.count() == 0 && isequal(size(e.Files),[1 0]) && h0.count() == 3, ...
    'removing every entry should leave an empty 1x0 list, and the original alone');
assert(e.remove(a).count() == 0,'removing from an empty list must not error');
fprintf('  PASS Part C: remove, and it never touches the original\n');

% ---- Part D: labels -----------------------------------------------------------
l = mabr.stim.BankHistory().add({'C:\p\solo.spl','C:\p\one\ABR.spl','C:\p\two\abr.spl'}).labels();
assert(strcmp(l{1},'solo.spl'),'a name that appears once is shown as the file name alone');
assert(contains(l{2},'ABR.spl') && contains(l{2},'(one)') && ...
       contains(l{3},'abr.spl') && contains(l{3},'(two)'), ...
    'two banks with the same name (any case) must be told apart by their folder');
assert(numel(l) == 3 && all(cellfun(@ischar,l)),'labels() must give one char per entry');

% Same name in two folders that share a name, and the same name at two drive
% roots: the folder cannot tell them apart, so the whole path has to. They are
% a dropdown's items, and a dropdown cannot be asked for "the second ABR.spl".
same = {'C:\a\x\ABR.spl','D:\b\x\ABR.spl','C:\ABR.spl','D:\ABR.spl','E:\other.spl'};
l = mabr.stim.BankHistory().add(same).labels();
assert(numel(unique(lower(l))) == numel(l),'labels() must never repeat, whatever the paths');
assert(strcmp(l{5},'other.spl'),'an unambiguous name must stay short even when others are not');
assert(strcmp(l{1},same{1}) && strcmp(l{4},same{4}), ...
    'entries the folder cannot separate must fall back to the whole path');
fprintf('  PASS Part D: labels name the folder only where two names collide, and never repeat\n');

% ---- Part E: clean() and preferences -----------------------------------------------
cl = mabr.stim.BankHistory.clean({'  a.spl  ','',42,{'nested'},'A.SPL',"s.spl",['ab';'cd']});
assert(isequal(cl,{'a.spl','s.spl'}), ...
    'clean should trim, drop blanks/non-text/multi-row char, de-duplicate, and accept strings');
assert(isequal(mabr.stim.BankHistory.clean('x.spl'),{'x.spl'}),'a lone char is one file');
assert(isequal(mabr.stim.BankHistory.clean(["x.spl","y.mat"]),{'x.spl','y.mat'}), ...
    'a string array is several files');
assert(isequal(mabr.stim.BankHistory.clean(42),cell(1,0)) && ...
       isequal(mabr.stim.BankHistory.clean(struct()),cell(1,0)), ...
    'something that is not text at all contributes nothing');

pn = mabr.stim.BankHistory.PrefName;

ld = mabr.stim.BankHistory.loadPrefs();
assert(ld.count() == 0,'with nothing ever saved the list must load empty');

h = mabr.stim.BankHistory().add({a,b,c});
mabr.stim.BankHistory.savePrefs(h);
assert(ispref('MABR',pn),'savePrefs should write the MABR pref');
ld = mabr.stim.BankHistory.loadPrefs();
assert(isequal(ld.Files,h.Files),'the list did not survive a setpref/getpref round trip');

setpref('MABR',pn,{a,7,'',upper(a),b});
ld = mabr.stim.BankHistory.loadPrefs();
assert(isequal(ld.Files,{a,b}), ...
    'a pref holding junk entries must load what is usable and nothing else');

setpref('MABR',pn,[1 2 3]);
ld = mabr.stim.BankHistory.loadPrefs();
assert(ld.count() == 0,'a pref that is not a list at all must load as an empty one, not throw');

setpref('MABR',pn,files);   % more than Max
ld = mabr.stim.BankHistory.loadPrefs();
assert(ld.count() == nMax,'a pref longer than the cap must be trimmed on the way in');
fprintf('  PASS Part E: clean() is forgiving, and the pref round-trips\n');

% ---- Part F: the folder the dialogs open in -----------------------------------
here  = fileparts(mfilename('fullpath'));   % tests/, which certainly exists
there = fileparts(here);                    % the repo root, likewise
gone  = fullfile(tempdir,'mabr_no_such_folder_4f1c');
assert(~isfolder(gone),'the test needs a folder that does not exist');

h = mabr.stim.BankHistory;
assert(isempty(h.Folder) && isempty(h.startFolder()), ...
    'with no folder and no banks there is nowhere to start: the dialog''s own default');

h = h.pickedFrom([here filesep]);
assert(strcmp(h.Folder,here),'the trailing separator uigetfile returns must be dropped');
assert(strcmp(h.startFolder(),here),'a remembered folder that exists is where to start');
assert(strcmp(h.pickedFrom('C:\').Folder,'C:\'),'a drive root keeps its separator');

h2 = h.pickedFrom(42).pickedFrom('').pickedFrom({'x'});
assert(strcmp(h2.Folder,here),'junk must leave the remembered folder alone');
assert(strcmp(h.pickedFrom(string(there)).Folder,there),'a string is a folder too');

g = mabr.stim.BankHistory().add({fullfile(gone,'a.spl'),fullfile(there,'b.spl')}).pickedFrom(gone);
assert(strcmp(g.startFolder(),there), ...
    'a remembered folder that is gone falls back to the newest listed bank whose folder exists');
g = mabr.stim.BankHistory().add(fullfile(gone,'a.spl')).pickedFrom(gone);
assert(isempty(g.startFolder()),'when nothing exists any more there is nowhere to start');

h = mabr.stim.BankHistory().add({a,b}).pickedFrom(here);
mabr.stim.BankHistory.savePrefs(h);
ld = mabr.stim.BankHistory.loadPrefs();
assert(strcmp(ld.Folder,here) && isequal(ld.Files,h.Files), ...
    'the folder must survive the pref round trip alongside the list');

setpref('MABR',mabr.stim.BankHistory.FolderPrefName,{1 2});
ld = mabr.stim.BankHistory.loadPrefs();
assert(isempty(ld.Folder) && isequal(ld.Files,h.Files), ...
    'a folder pref holding junk must load as no folder, and cost the list nothing');
fprintf('  PASS Part F: the dialogs open where a bank was last picked from\n');

fprintf('== verify_recent_banks PASSED ==\n');
end

% =========================================================================
function s = save_prefs(names)
s = struct('name',{},'value',{});
for i = 1:numel(names)
    if ispref('MABR',names{i})
        s(end+1) = struct('name',names{i},'value',getpref('MABR',names{i})); %#ok<AGROW>
    end
end
end

function restore_prefs(names,s)
% Put back exactly what was there: the saved value where there was one, and
% no pref at all where there was none.
had = {s.name};
for i = 1:numel(had)
    setpref('MABR',had{i},s(i).value);
end
for i = 1:numel(names)
    if ~any(strcmp(names{i},had)) && ispref('MABR',names{i})
        rmpref('MABR',names{i});
    end
end
end

function clear_prefs(names)
for i = 1:numel(names)
    if ispref('MABR',names{i}), rmpref('MABR',names{i}); end
end
end
