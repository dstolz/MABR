function verify_folder_scheme()
% verify_folder_scheme  Session folders: the pattern, no hardware, no window.
%
%   mabr.FolderScheme decides where under the Output folder a session's files
%   go (Settings > Session Folders...). Everything it decides is checked here
%   without constructing mabr.ui.App (the suite runs from inside that window,
%   and a second one refuses to open) or a controller.
%
%   Part A (the default): Subject\Subject_yyMMddTHHmmss, from the moment given
%   as Start -- the folder the request asked for, to the second.
%   Part B (tokens): {Start:fmt}, {Bank}, {Strategy}, {User}; a token that
%   comes out empty takes its separator along ({Mode} on an ordinary run),
%   and a level that comes out empty is dropped.
%   Part C (stimulus tokens): {ID} and a bank parameter make a level per
%   condition, with a printf format; WITHOUT a stimulus the folder stops at
%   the level above (the session folder, where the notes journal goes).
%   Part D (safety): a value cannot add a level or hold a character a Windows
%   name cannot; '..', drive letters and unpaired braces are refused.
%   Part E (off): Enabled = false, or an empty pattern, is the Output folder
%   itself -- and a Session left alone stays that way, so a script setting
%   OutputPath finds its files where it put them.
%   Part F (Session + writeABR): a block written through Session.saveBlock
%   lands in the resolved folder, created on demand, under the file name the
%   offline pipeline expects.
%   Part G (persistence): toStruct/fromStruct and the MABR prefs round trip,
%   forgiving of junk.
%
%   The user's own preferences are saved and restored around the run.
%
%   Run:  >> verify_folder_scheme
%
%   See also mabr.FolderScheme, mabr.ui.FolderSchemeDialog, mabr.data.Session.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_folder_scheme ==\n');

prefNames = {mabr.FolderScheme.PrefEnabled, mabr.FolderScheme.PrefPattern};
saved = save_prefs(prefNames);
restorePrefs = onCleanup(@() restore_prefs(prefNames,saved));

t0  = datetime(2026,10,1,14,30,12);
ctx = mabr.FolderScheme.context('Subject','SUBJ-ID-1254','Start',t0, ...
    'Bank','tones_8-32k','Strategy','conventional','Mode','','User','tester');
root = fullfile('C:','data');

% ---- Part A: the default --------------------------------------------------
s = mabr.FolderScheme;
assert(s.Enabled && strcmp(s.Pattern,mabr.FolderScheme.DefaultPattern), ...
    'a new scheme should be the default, switched on');
d = s.resolve(root,ctx);
want = fullfile(root,'SUBJ-ID-1254','SUBJ-ID-1254_261001T143012');
assert(strcmp(d,want),'default folder: got "%s", wanted "%s"',d,want);
[ok,err] = s.validate();
assert(ok && isempty(err),'the default pattern must validate');
fprintf('  PASS Part A: %s\n',d);

% ---- Part B: session tokens -----------------------------------------------
s = mabr.FolderScheme('{Start:yyyy-MM-dd}/{Subject}_{Bank}_{Strategy}_{User}');
d = s.resolve(root,ctx);
assert(strcmp(d,fullfile(root,'2026-10-01','SUBJ-ID-1254_tones_8-32k_conventional_tester')), ...
    'session tokens: got "%s"',d);

s = mabr.FolderScheme('{Subject}/{Subject}_{Mode}_{Date}');
d = s.resolve(root,ctx);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','SUBJ-ID-1254_261001')), ...
    'an empty {Mode} must take one separator along: got "%s"',d);
ctxT = ctx; ctxT.Mode = 'TestMode';
d = s.resolve(root,ctxT);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','SUBJ-ID-1254_TestMode_261001')), ...
    'a set {Mode} must be kept: got "%s"',d);

s = mabr.FolderScheme('{Mode}/{Subject}');
d = s.resolve(root,ctx);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254')), ...
    'a level that comes out empty must be dropped: got "%s"',d);

s = mabr.FolderScheme('{subject}/{DATE}t{time}');
d = s.resolve(root,ctx);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','261001t143012')), ...
    'token names are matched without regard to case: got "%s"',d);
fprintf('  PASS Part B: session tokens, empty tokens and levels\n');

% ---- Part C: stimulus tokens ----------------------------------------------
meta = struct('ID','Tone_8_30','Frequency',8,'Level',30, ...
    'informativeParams',{{'Frequency','Level'}});
s = mabr.FolderScheme('{Subject}/{Subject}_{Date}T{Time}/{Frequency}kHz/{Level:%03g}dB');
sess = s.resolve(root,ctx);
per  = s.resolve(root,ctx,meta);
assert(strcmp(sess,fullfile(root,'SUBJ-ID-1254','SUBJ-ID-1254_261001T143012')), ...
    'without a stimulus the folder must stop at the session level: got "%s"',sess);
assert(strcmp(per,fullfile(sess,'8kHz','030dB')), ...
    'with a stimulus every level is filled: got "%s"',per);
d = mabr.FolderScheme('{Subject}/{ID}').resolve(root,ctx,meta);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','Tone_8_30')),'{ID}: got "%s"',d);
d = mabr.FolderScheme('{Subject}/x{Nope}').resolve(root,ctx,meta);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','x')), ...
    'a parameter the stimulus lacks is left out: got "%s"',d);
[ok,~,warn] = mabr.FolderScheme('{Subject}/{Nope}').validate({'Frequency','Level'});
assert(ok && contains(warn,'{Nope}'), ...
    'a token the bank does not have is a warning, not an error');
fprintf('  PASS Part C: per-condition levels, and the session folder above them\n');

% ---- Part D: safety -------------------------------------------------------
ctxB = ctx; ctxB.Subject = 'a/b:c*d.';
d = mabr.FolderScheme('{Subject}').resolve(root,ctxB);
assert(strcmp(d,fullfile(root,'a-b-c-d')), ...
    'a value must not add a level or keep an illegal character: got "%s"',d);
d = mabr.FolderScheme('{Start:yyyy/MM}').resolve(root,ctx);
assert(strcmp(d,fullfile(root,'2026-10')), ...
    'a / inside a token''s format must not split the level: got "%s"',d);
ctxN = ctx; ctxN.Subject = 'nul';
d = mabr.FolderScheme('{Subject}').resolve(root,ctxN);
assert(strcmp(d,fullfile(root,'_nul')),'a device name must not be a folder: got "%s"',d);
for bad = {'../{Subject}','C:/{Subject}','{Subject','{Subject}}','{}','a|b','{{Subject}}'}
    assert(~mabr.FolderScheme(bad{1}).validate(),'"%s" must be refused',bad{1});
end
d = mabr.FolderScheme('/{Subject}//./x/').resolve(root,ctx);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','x')), ...
    'empty and "." levels are dropped: got "%s"',d);
d = mabr.FolderScheme('{Subject}\{Date}').resolve(root,ctx);
assert(strcmp(d,fullfile(root,'SUBJ-ID-1254','261001')),'\ separates levels too: got "%s"',d);
fprintf('  PASS Part D: values sanitized, dangerous patterns refused\n');

% ---- Part E: off ------------------------------------------------------------
assert(strcmp(mabr.FolderScheme([],false).resolve(root,ctx),root), ...
    'a scheme switched off is the Output folder itself');
off = mabr.FolderScheme([],false);
assert(strcmp(off.Pattern,mabr.FolderScheme.DefaultPattern), ...
    'switching off must keep the pattern');
e = mabr.FolderScheme('{Subject}'); e.Pattern = '';
assert(strcmp(e.resolve(root,ctx),root),'an empty pattern is the Output folder itself');
s0 = mabr.FolderScheme;
assert(isempty(s0.resolve('',ctx)), ...
    'no Output folder means no folder at all (Preview)');
sess = mabr.data.Session();
sess.OutputPath = root;
assert(strcmp(sess.folderFor(),root) && strcmp(sess.folderFor(meta),root), ...
    'a Session nobody gave a scheme must write straight into OutputPath');
fprintf('  PASS Part E: off, empty, and the Session default\n');

% ---- Part F: Session + writeABR ---------------------------------------------
tmp = tempname;
cleanTmp = onCleanup(@() rmdir_quiet(tmp));
sess = mabr.data.Session();
sess.Subject.ID    = 'SUBJ-ID-1254';
sess.OutputPath    = tmp;
sess.Folders       = mabr.FolderScheme('{Subject}/{Subject}_{Date}T{Time}/{Frequency}kHz');
sess.FolderContext = mabr.FolderScheme.context('Start',t0);   % subject from the Session
assert(strcmp(sess.folderFor(),fullfile(tmp,'SUBJ-ID-1254','SUBJ-ID-1254_261001T143012')), ...
    'Session.folderFor must take the subject from the Session when the context has none');

rec = mabr.data.Recording(12000,single(randn(1200,1)),[100 500 900],120,1);
blk = mabr.data.Block(struct('Meta',meta,'SampleRate',192000),rec,char(t0));
ffn = sess.saveBlock(blk);
[p,n,x] = fileparts(ffn);
assert(strcmp(p,fullfile(tmp,'SUBJ-ID-1254','SUBJ-ID-1254_261001T143012','8kHz')), ...
    'the .abr must land in the resolved folder: got "%s"',p);
assert(isfile(ffn) && strcmp(x,'.abr'),'the .abr was not written');
% The scheme decides the folder only: the name is the one io builds, and
% that is underscore-separated tokens, each hyphenated inside.
assert(strcmp([n x],mabr.data.io.buildFilename(blk,sess.Subject.ID)), ...
    'the folder scheme must not change the file NAME: got "%s"',[n x]);
assert(strcmp([n x],'SUBJ-ID-1254_Frequency-8kHz_Level-30dB_261001T143012.abr'), ...
    'unexpected file name "%s"',[n x]);
strict = '^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr';
assert(~isempty(regexp([n x],strict,'once')),'"%s" must match the strict offline pattern',[n x]);

% Decimal point -> p, minus sign -> m, a typed SUBJ_ID_ subject and a free
% stimulus ID made one hyphenated token each.
odd = mabr.data.Block(struct('Meta',struct('ID','x','Frequency',11.3,'Level',-10)),rec,char(t0));
fn  = mabr.data.io.buildFilename(odd,'SUBJ_ID_42');
assert(strcmp(fn,'SUBJ-ID-42_Frequency-11p3kHz_Level-m10dB_261001T143012.abr'), ...
    'decimal/negative values or an underscored subject: got "%s"',fn);
assert(~isempty(regexp(fn,strict,'once')),'"%s" must match the strict offline pattern',fn);
byID = mabr.data.Block(struct('Meta',struct('ID','Click 80_dB.v2')),rec,char(t0));
fn   = mabr.data.io.buildFilename(byID,'Rat 7');
assert(strcmp(fn,'SUBJ-ID-7_Click-80-dB-v2_261001T143012.abr'), ...
    'a condition named by its ID must be one token: got "%s"',fn);
fprintf('  PASS Part F: %s\n',fullfile('...','SUBJ-ID-1254','SUBJ-ID-1254_261001T143012','8kHz',[n x]));

% ---- Part G: persistence ----------------------------------------------------
s = mabr.FolderScheme('{Subject}/{Bank}',false);
r = mabr.FolderScheme.fromStruct(s.toStruct());
assert(isequal(r,s),'toStruct/fromStruct must round-trip');
r = mabr.FolderScheme.fromStruct(struct('Enabled','yes','Pattern','../x'));
assert(isequal(r,mabr.FolderScheme),'junk fields must fall back to the defaults');
r = mabr.FolderScheme.fromStruct(42);
assert(isequal(r,mabr.FolderScheme),'a non-struct must give the default');

mabr.FolderScheme.savePrefs(s);
assert(isequal(mabr.FolderScheme.loadPrefs(),s),'the prefs must round-trip');
setpref('MABR',mabr.FolderScheme.PrefPattern,{1,2});
setpref('MABR',mabr.FolderScheme.PrefEnabled,'junk');
r = mabr.FolderScheme.loadPrefs();
assert(isa(r,'mabr.FolderScheme') && strcmp(r.Pattern,mabr.FolderScheme.DefaultPattern), ...
    'a pref holding junk must still load');
fprintf('  PASS Part G: configuration struct and prefs\n');

clear cleanTmp restorePrefs
fprintf('== verify_folder_scheme PASSED ==\n');
end

% ===================== helpers =============================================
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

function rmdir_quiet(d)
if isfolder(d)
    try, rmdir(d,'s'); catch, end
end
end
