function verify_notes()
% verify_notes  Exercise the session notes component, end to end.
%
%   Checks, with no audio hardware and no parallel pool:
%       1. a note is stamped with the run and sweep it was taken at while a
%          run is in flight, and with the wall clock when none is;
%       2. the log round-trips through render/parse, and an edited log keeps
%          each surviving line's original record;
%       3. the plain-text crash journal is rewritten whole on every change
%          and reads back with SessionNotes.fromFile;
%       4. notes reach the data: a Block carries the log it was finalized
%          under and mabr.data.io writes it to the .abr, a .stimlog carries
%          it too, and both are present (and empty-but-typed) when nothing
%          was noted;
%       5. two views on one store stay in step, and a view survives its
%          store changing under it (setStore);
%       6. mabr.ui.TraceOrganizer carries the notebook into and out of a
%          .torg, and refuses to overwrite a live session's log with one;
%       7. end to end: a note taken while a schedule is acquiring comes back
%          out of the .abr that schedule wrote, stamped with its run.
%
%   Creates figures, and part 7 drives a TESTING-loopback acquisition, so
%   that part needs the Parallel Computing Toolbox. No audio hardware. Run:
%       >> verify_notes
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_notes ==\n');

outDir = fullfile(tempdir,'mabr_notes');
if ~isfolder(outDir), mkdir(outDir); end

% --- 1. stamping ---------------------------------------------------------
n = mabr.data.SessionNotes();
n.add('electrodes in, impedance 3.2k');
assert(n.NumNotes == 1,'a note was not recorded');
assert(isnan(n.Notes(1).Run),'a note taken with no context claimed a run');
assert(~isempty(regexp(n.Notes(1).Stamp,'^\d\d:\d\d:\d\d$','once')), ...
    'a note with no acquisition context should stamp the wall clock, got "%s"', ...
    n.Notes(1).Stamp);

% Now with a context, as the App supplies one from the controller.
ctx = struct('Run',2,'NumRuns',6,'Sweep',128,'Running',true);
n.ContextFcn = @() ctx;
n.add('ear plug slipped');
r = n.Notes(2);
assert(r.Run == 2 && r.Sweep == 128,'the acquisition context did not reach the record');
assert(strncmp(r.Stamp,'R02 S0128 ',10), ...
    'expected an R/S stamp while acquiring, got "%s"',r.Stamp);
assert(startsWith(mabr.data.SessionNotes.renderLine(r),'[R02 S0128 '), ...
    'the rendered line does not carry the stamp');

% A context function that throws costs the note its run number, not the note.
n.ContextFcn = @() error('gone');
n.add('controller went away');
assert(n.NumNotes == 3,'a failing ContextFcn lost the note');
assert(isnan(n.Notes(3).Run),'a failing ContextFcn should leave the run unstamped');
n.ContextFcn = @() ctx;

% Blank entries are stray keystrokes, not notes.
n.add('   ');  n.add('');
assert(n.NumNotes == 3,'a blank entry was committed as a note');

% One note per line of a multi-line entry.
n.add(sprintf('line one\nline two'));
assert(n.NumNotes == 5,'a multi-line entry did not split into one note per line');
fprintf('  PASS: notes stamped with run/sweep when acquiring, clock when not\n');

% --- 2. render / parse / edit -------------------------------------------
lines = n.log();
assert(numel(lines) == n.NumNotes,'log() lost a line');
[st,body] = mabr.data.SessionNotes.parseLine(lines{2});
assert(strcmp(st,n.Notes(2).Stamp) && strcmp(body,n.Notes(2).Text), ...
    'a rendered line did not parse back to its own stamp and text');

% Edit the log the way the view's Editable mode does: fix a typo on one
% line, delete another, leave the rest alone.
edited = lines;
edited{2} = regexprep(edited{2},'slipped','slipped off');
edited(4) = [];
time2 = n.Notes(2).Time;
n.setFromLog(edited);
assert(n.NumNotes == 4,'setFromLog did not drop the deleted line');
assert(strcmp(n.Notes(2).Text,'ear plug slipped off'),'the edit did not take');
assert(n.Notes(2).Edited,'an edited note was not flagged');
assert(strcmp(n.Notes(2).Time,time2) && n.Notes(2).Sweep == 128, ...
    'editing a line''s text discarded the record behind it');
assert(~n.Notes(1).Edited,'an untouched line was marked edited');

% A freshly typed line, with no stamp of its own, is stamped now.
n.setFromLog([n.log(); {'typed straight into the log'}]);
assert(n.NumNotes == 5 && ~isempty(n.Notes(end).Time), ...
    'a line typed into the log was not committed as a note');
fprintf('  PASS: log renders, parses, and survives an edit with its record intact\n');

% --- 3. the crash journal -----------------------------------------------
jf = fullfile(outDir,'session.notes');
if isfile(jf), delete(jf); end
n.Subject = 'SUBJ_ID_9';
n.JournalFile = jf;
n.add('journal starts here');
assert(isfile(jf),'setting JournalFile + committing did not write the journal');

txt = fileread(jf);
assert(contains(txt,'journal starts here'),'the journal is missing the newest note');
assert(contains(txt,'ear plug slipped off'), ...
    'the journal was appended to rather than rewritten whole');
assert(contains(txt,'SUBJ_ID_9'),'the journal header does not name the subject');

back = mabr.data.SessionNotes.fromFile(jf);
assert(back.NumNotes == n.NumNotes, ...
    'fromFile read %d notes back out of a %d-note journal',back.NumNotes,n.NumNotes);
assert(strcmp(back.Notes(2).Text,n.Notes(2).Text),'fromFile mangled a note');
assert(strcmp(back.Notes(2).Stamp,n.Notes(2).Stamp),'fromFile lost a stamp');

% Editing removes a note; the journal must lose it too.
kept = n.log();
n.setFromLog(kept(1:end-1));
assert(~contains(fileread(jf),'journal starts here'), ...
    'the journal kept a note the log no longer has');

% A journal that cannot be written must not stop the operator writing notes.
n.JournalFile = fullfile(outDir,'no','such','folder','x.notes');
before = n.NumNotes;
n.add('written with a broken journal path');
assert(n.NumNotes == before+1,'a bad journal path swallowed a note');
n.JournalFile = '';
fprintf('  PASS: journal rewritten whole on every change, and reads back\n');

% --- 4. notes reach the data ---------------------------------------------
sess = mabr.data.Session(mabr.Config);
sess.Notes = n;                     % the App hands its own store in the same way
sess.Subject.ID = 'SUBJ_ID_9';
sess.OutputPath = outDir;

blk = make_block('8kHz_60dB',8);
blk.Notes = sess.noteRecord();
assert(numel(blk.Notes) == n.NumNotes,'Session.noteRecord did not fill the block');

abrFile = mabr.data.io.writeABR(blk,outDir,sess.Subject.ID);
L = load(abrFile,'-mat');
assert(isfield(L.ABR_Data,'Notes'),'writeABR did not write ABR_Data.Notes');
assert(numel(L.ABR_Data.Notes) == n.NumNotes, ...
    '.abr carries %d notes, expected %d',numel(L.ABR_Data.Notes),n.NumNotes);
assert(strcmp(L.ABR_Data.Notes(2).Text,n.Notes(2).Text),'a note was mangled on the way to the .abr');
% Kept out of SIG, where it would read as a stimulus parameter.
assert(~isfield(L.ABR_Data.SIG,'Notes'),'notes leaked into SIG');
assert(~any(strcmp(L.ABR_Data.SIG.informativeParams,'Notes')), ...
    'notes became a grouping dimension');

% Always present, with the right fields, even when nothing was noted.
bare = make_block('16kHz_60dB',16);
bareFile = mabr.data.io.writeABR(bare,outDir,'SUBJ_ID_9');
B = load(bareFile,'-mat');
assert(isfield(B.ABR_Data,'Notes'),'an un-noted session still owes ABR_Data.Notes');
assert(isempty(B.ABR_Data.Notes),'an un-noted .abr should carry an empty log');
assert(all(ismember({'Stamp','Text','Time'},fieldnames(B.ABR_Data.Notes))), ...
    'an empty log was written without its fields');

% ... and the same for the .stimlog a stimulation-only run writes instead.
info = struct('Run',1,'NumRuns',1,'StartTime',sess.StartTime,'Subject','SUBJ_ID_9', ...
    'StimulusIndex',[1 1],'Polarity',[1 -1],'OnsetSample',[1 1000], ...
    'IDs',{{'8kHz_60dB'}},'Notes',sess.noteRecord());
S = mabr.data.io.buildStimLog(info);
assert(isfield(S,'Notes') && numel(S.Notes) == n.NumNotes, ...
    'the stimulation log did not carry the notebook');

% The filename sorts with the rest of the session's files.
fn = mabr.data.io.buildNotesFilename('SUBJ_ID_9',sess.StartTime);
assert(startsWith(fn,'SUBJ_ID_9_Notes_') && endsWith(fn,'.notes'), ...
    'unexpected notes filename "%s"',fn);
fprintf('  PASS: notes saved into .abr, .stimlog, and a matching filename\n');

% --- 5. two views, one store ---------------------------------------------
v1 = mabr.ui.Notes(n,[],'Name','VerifyA');
v2 = mabr.ui.Notes(n,[],'Name','VerifyB');
cleanViews = onCleanup(@() delete([v1 v2]));
drawnow;
assert(v1.isopen() && v2.isopen(),'a standalone notes view did not open its window');

v1.addNote('typed in the first window');
drawnow;
assert(strcmp(n.Notes(end).Text,'typed in the first window'),'the view did not reach the store');
assert(any(contains(string(v2.displayedLog()),'typed in the first window')), ...
    'a second view on the same store did not follow the commit');
assert(strcmp(n.Notes(end).Source,'VerifyA'), ...
    'a note does not record which view committed it');

% A view re-pointed at another store follows the new one.
other = mabr.data.SessionNotes();
other.add('a different session entirely');
v2.setStore(other);
drawnow;
assert(any(contains(string(v2.displayedLog()),'a different session')), ...
    'setStore did not re-point the view');
v1.addNote('still going in the first');
drawnow;
assert(~any(contains(string(v2.displayedLog()),'still going in the first')), ...
    'a re-pointed view is still listening to its old store');

% Clearing is a store operation, so every view sees it.
v2.clearNotes();
assert(other.NumNotes == 0,'clearNotes did not empty the store');
fprintf('  PASS: any number of views stay in step through the store\n');

% --- 6. the trace organizer ---------------------------------------------
torgFile = fullfile(outDir,'notes.torg');
to = mabr.ui.TraceOrganizer();
cleanTo = onCleanup(@() delete(to));
to.addBlock(blk);
to.show();
assert(to.NotesOwned,'a standalone organizer should own its notebook');
to.Notes.add('this view was arranged on a Tuesday');
to.saveView(torgFile);

V = load(torgFile,'-mat');
assert(isfield(V.View,'Notes') && numel(V.View.Notes) == 1, ...
    'saveView did not carry the notebook into the .torg');

to2 = mabr.ui.TraceOrganizer();
clean2 = onCleanup(@() delete(to2));
to2.loadView(torgFile);
assert(to2.Notes.NumNotes == 1 && contains(to2.Notes.Notes(1).Text,'Tuesday'), ...
    'loadView did not restore the notebook');

% An organizer showing a LIVE session's notebook must not have it replaced
% by a file's -- the operator is still writing in that one.
live = mabr.data.SessionNotes();
live.add('acquiring right now');
to2.useNotes(live);
assert(~to2.NotesOwned,'useNotes did not mark the store as external');
to2.loadView(torgFile);
assert(to2.Notes.NumNotes == 1 && contains(live.Notes(1).Text,'acquiring right now'), ...
    'loading a view clobbered the running session''s notebook');

% A version-2 file (no Notes field at all) still loads.
V2 = V; V2.View = rmfield(V2.View,'Notes'); V2.View.Version = 2;
old = fullfile(outDir,'v2.torg');
View = V2.View;
save(old,'View','-mat');
to3 = mabr.ui.TraceOrganizer();
clean3 = onCleanup(@() delete(to3));
to3.loadView(old);
assert(numel(to3.Traces) == 1,'a version-2 .torg no longer loads');
fprintf('  PASS: the organizer carries the notebook, and never clobbers a live one\n');

% --- 7. end to end, through a real run -----------------------------------
% Everything above tests the parts. This one proves the whole: a note taken
% while a schedule is acquiring comes back out of the .abr that schedule
% wrote, stamped with the run it was taken in. Runs in TESTING loopback, so
% it needs the parallel pool but no audio hardware.
runDir = fullfile(outDir,'run');
if isfolder(runDir), rmdir(runDir,'s'); end
mkdir(runDir);

cfg  = mabr.Config;
ctrl = mabr.ui.AcqController(cfg,true);
cleanCtrl = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

live2 = mabr.data.SessionNotes();
live2.ContextFcn = @() ctrl.noteContext();   % exactly what mabr.ui.App wires up
live2.add('written before the schedule started');
ctrl.Session.Notes      = live2;
ctrl.Session.Subject.ID = 'SUBJ_ID_5';
ctrl.Session.OutputPath = runDir;

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = 24;
ctrl.Schedule.ISI         = 0.02;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.002;

% Take a note the moment the run reaches Acquire, which is the whole point of
% the component: the operator writes while it is happening.
tookOne = false;
lst = addlistener(ctrl,'StateChanged',@(~,e) noteOnAcquire(e));
cleanLst = onCleanup(@() delete(lst));

ctrl.start();
t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete,'the schedule did not complete');
assert(tookOne,'never reached Acquire, so no note was taken mid-run');

assert(ctrl.Session.NumBlocks == 1,'expected one finalized block');
blkNotes = ctrl.Session.Blocks(1).Notes;
assert(numel(blkNotes) == live2.NumNotes, ...
    'the finalized block carries %d notes, the session has %d', ...
    numel(blkNotes),live2.NumNotes);

midRun = blkNotes(strcmp({blkNotes.Text},'ear plug slipped, mid-run'));
assert(isscalar(midRun),'the mid-run note did not reach the block');
assert(midRun.Run == 1,'the mid-run note was not stamped with its run (Run=%g)',midRun.Run);
assert(startsWith(midRun.Stamp,'R01 S'), ...
    'expected a run/sweep stamp on a mid-run note, got "%s"',midRun.Stamp);

written = dir(fullfile(runDir,'*.abr'));
assert(~isempty(written),'the run wrote no .abr file');
W = load(fullfile(runDir,written(1).name),'-mat');
assert(any(strcmp({W.ABR_Data.Notes.Text},'ear plug slipped, mid-run')), ...
    'the mid-run note is not in the saved .abr');
assert(any(strcmp({W.ABR_Data.Notes.Text},'written before the schedule started')), ...
    'a note taken before Start did not follow the session into its file');
fprintf('  PASS: a note taken mid-run reaches the block and the saved .abr\n');

delete(abrFile); delete(bareFile); delete(torgFile); delete(old);
if isfile(jf), delete(jf); end
fprintf('== verify_notes PASSED ==\n');

    function noteOnAcquire(e)
        if tookOne || e.State ~= mabr.ui.ProgState.Acquire, return; end
        tookOne = true;
        live2.add('ear plug slipped, mid-run');
    end
end


% =====================================================================
function block = make_block(id,freq)
% A short synthetic block, enough to write a .abr from.
Fs = 12000; df = 1;
nSweeps = 6; period = round(Fs/21.1);
N = nSweeps*period + period;
data   = 1e-9*randn(N,1);
onsets = (round(0.05*Fs) + (0:nSweeps-1)*period)';
rec  = mabr.data.Recording(Fs,data,onsets,round(0.01*Fs),df);
meta = struct('ID',id,'Frequency',freq,'Level',60, ...
              'informativeParams',{{'Frequency','Level'}}, ...
              'Label',{{sprintf('ID = %s',id),'Level = 60'}});
block = mabr.data.Block(struct('Meta',meta,'SampleRate',Fs),rec);
end
