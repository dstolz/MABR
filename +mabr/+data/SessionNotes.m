classdef SessionNotes < handle
% mabr.data.SessionNotes  The rig notebook for one session.
%
%   A handle store of timestamped free-text notes -- "ear plug slipped",
%   "electrode impedance 3.2 k", "animal moved" -- kept alongside the data and
%   written into every file the session produces. It is the data half of the
%   notes component; mabr.ui.Notes is the view, and any number of views can be
%   open on one store at once (the App's window, the trace organizer's) because
%   every change fires NotesChanged and each view redraws from the store rather
%   than from its own copy.
%
%       notes = mabr.data.SessionNotes();
%       notes.ContextFcn = @() controller.noteContext();   % optional
%       notes.add('ear plug slipped');
%
%   WHAT A NOTE IS STAMPED WITH is the point of the class. A wall clock alone
%   does not say where in an experiment something happened -- the operator
%   would have to reconstruct that from file timestamps afterwards -- so a note
%   committed while a schedule is running carries the run and the sweep count
%   as well:
%
%       [R02 S0128 09:17:05] ear plug slipped
%       [09:03:11] impedance 3.2k on both electrodes
%
%   The second form is a note taken while nothing is acquiring, which is the
%   honest thing to show: there is no run to name. The acquisition context
%   comes from ContextFcn, a niladic function the owner sets (mabr.ui.App
%   points it at mabr.ui.AcqController.noteContext); with none set, every note
%   is a clock note. Sweep is the count within the CURRENT RUN, which is what
%   the Run panel's readout shows and what "it happened partway through this
%   average" means.
%
%   SAVED WITH THE DATA, always in full. Every file a session writes carries
%   the whole log as of the moment it was written:
%       .abr      ABR_Data.Notes     (via mabr.data.Block.Notes)
%       .stimlog  MABR_StimLog.Notes
%       .torg     View.Notes         (mabr.ui.TraceOrganizer)
%   Writing the whole log into each file rather than the notes "since the last
%   one" means no file depends on another to be read, and a session recovered
%   from a single surviving .abr still has its notebook.
%
%   THE JOURNAL is the other half of that. Set JournalFile and every commit
%   rewrites the entire log to it as PLAIN TEXT -- deliberately not a MAT-file
%   like the rest of MABR's outputs, because the whole reason the journal
%   exists is to survive a crash, and a format that needs MATLAB to read is the
%   wrong one for that. fromFile reads one back.
%
%   See also mabr.ui.Notes, mabr.data.Session, mabr.data.io.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        % One element per note, in the order they were committed. See
        % emptyRecord for the fields.
        Notes struct = struct('Stamp',{},'Text',{},'Time',{},'Elapsed',{}, ...
                              'Run',{},'NumRuns',{},'Sweep',{},'Source',{},'Edited',{});

        % When this store began, which is what an 'elapsed' stamp is relative
        % to. Set at construction and never moved: a note log spans a session,
        % and a session starts when the operator sits down, not when the first
        % schedule does.
        StartTime (1,:) char = '';
    end

    properties
        % Niladic function returning the acquisition context for a stamp, or
        % [] for none. It may return any subset of the fields noteContext
        % supplies (Run, NumRuns, Sweep, Running); anything missing is simply
        % not stamped. Wrapped in a try at every call -- a notebook must not
        % become un-writable because a controller was deleted mid-note.
        ContextFcn = [];

        % Plain-text crash journal, rewritten whole on every change. '' (the
        % default) writes nothing, which is what a preview run wants: it
        % deliberately writes no files at all.
        JournalFile (1,:) char = '';

        % Named in the journal's header so a stray .notes file on a rig says
        % whose session it was.
        Subject (1,:) char = '';

        % Default stamp format for add(): 'auto' (run/sweep when acquiring,
        % clock otherwise), 'clock', 'elapsed', or 'none'. A view may override
        % it per commit; see mabr.ui.Notes.TimeStamp.
        TimeStamp (1,:) char {mustBeMember(TimeStamp, ...
            {'auto','clock','elapsed','none'})} = 'auto';
    end

    properties (Dependent)
        NumNotes
    end

    properties (Access = private)
        StartTic (1,1) uint64 = uint64(0);
    end

    events
        % Fired on every add, clear, replacement, or edit, so every open view
        % redraws from the store. Views never mutate each other.
        NotesChanged
    end

    methods
        function obj = SessionNotes()
            obj.StartTime = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            obj.StartTic  = tic;
        end

        function n = get.NumNotes(obj)
            n = numel(obj.Notes);
        end

        % --- Committing -----------------------------------------------------
        function rec = add(obj,text,varargin)
            % Commit one note (or one per line of a multi-line entry) and
            % return what was recorded.
            %
            %   n.add('ear plug slipped')
            %   n.add(txt,'Source','TraceOrganizer','TimeStamp','clock')
            %
            % Blank lines are dropped rather than committed: an empty note is
            % a stray Enter, never something the operator meant to record.
            p = struct('Source','','TimeStamp',obj.TimeStamp);
            for i = 1:2:numel(varargin)
                p.(varargin{i}) = varargin{i+1};
            end

            lines = mabr.data.SessionNotes.toLines(text);
            rec   = mabr.data.SessionNotes.emptyRecord();
            ctx   = obj.context();
            for k = 1:numel(lines)
                s = strtrim(lines{k});
                if isempty(s), continue; end
                rec(end+1) = obj.makeRecord(s,p.TimeStamp,p.Source,ctx); %#ok<AGROW>
            end
            if isempty(rec), return; end

            if isempty(obj.Notes)
                obj.Notes = rec;
            else
                obj.Notes(end+1:end+numel(rec)) = rec;
            end
            obj.changed();
        end

        function clear(obj)
            if isempty(obj.Notes), return; end
            obj.Notes = mabr.data.SessionNotes.emptyRecord();
            obj.changed();
        end

        function setFromLog(obj,lines)
            % Replace the log with edited text, one note per line, keeping the
            % stamp each line already carries.
            %
            % This is what the view's right-click "Editable" writes back: a
            % typo in a note taken at the bench is worth being able to fix, and
            % the only place a user can fix one is the log they can see. A line
            % that keeps its "[stamp] text" shape keeps the record behind it
            % (time, run, sweep) intact and is not marked edited; a line whose
            % text has changed keeps the stamp but is flagged Edited, and a
            % line typed fresh is stamped now like any other commit.
            lines = mabr.data.SessionNotes.toLines(lines);
            old   = obj.Notes;
            used  = false(1,numel(old));
            ctx   = obj.context();
            rec   = mabr.data.SessionNotes.emptyRecord();
            for k = 1:numel(lines)
                [stamp,body] = mabr.data.SessionNotes.parseLine(lines{k});
                if isempty(body), continue; end
                % Match against the note that was on this line before the edit
                % first, then anywhere in the old log -- reordering a log is a
                % legitimate edit and must not restamp everything. Each old
                % note is claimed at most once, so two notes sharing a stamp
                % (committed in the same second) cannot both collapse onto one.
                j = mabr.data.SessionNotes.matchNote(old,used,stamp,body,k);
                if ~isempty(j), used(j) = true; end
                if isempty(j)
                    r = obj.makeRecord(body,obj.TimeStamp,'edit',ctx);
                    if ~isempty(stamp)
                        r.Stamp  = stamp;      % the user kept a stamp; honour it
                        r.Edited = true;
                    end
                else
                    r = old(j);
                    if ~strcmp(r.Text,body)
                        r.Text   = body;
                        r.Edited = true;
                    end
                    r.Stamp = stamp;
                end
                rec(end+1) = r; %#ok<AGROW>
            end
            if isequal(rec,obj.Notes), return; end
            obj.Notes = rec;
            obj.changed();
        end

        % --- Reading ---------------------------------------------------------
        function lines = log(obj)
            % The log as a cellstr, one rendered line per note.
            lines = cell(numel(obj.Notes),1);
            for k = 1:numel(obj.Notes)
                lines{k} = mabr.data.SessionNotes.renderLine(obj.Notes(k));
            end
        end

        function s = text(obj)
            % The whole log as one char array with newlines -- what Copy All
            % puts on the clipboard, and what the journal writes.
            s = char(join(string(obj.log()),newline));
            if isempty(s), s = ''; end
        end

        function S = toStruct(obj)
            % The log as a plain struct array, for saving into a data file.
            % Always 1xN (or 1x0) so a caller can concatenate or iterate it
            % without testing its orientation first.
            S = obj.Notes;
            if isempty(S)
                S = mabr.data.SessionNotes.emptyRecord();
            else
                S = reshape(S,1,[]);
            end
        end

        function fromStruct(obj,S)
            % Replace the log with one read back out of a file, tolerating a
            % record written by a version with more or fewer fields -- the same
            % forgiving rule mabr.ArtifactPolicy.fromStruct follows.
            rec = mabr.data.SessionNotes.emptyRecord();
            if ~isempty(S) && isstruct(S)
                blank = mabr.data.SessionNotes.blankRecord();
                for k = 1:numel(S)
                    r = blank;
                    f = intersect(fieldnames(S(k)),fieldnames(blank));
                    for i = 1:numel(f), r.(f{i}) = S(k).(f{i}); end
                    rec(end+1) = r; %#ok<AGROW>
                end
            end
            obj.Notes = rec;
            obj.changed();
        end

        % --- The crash journal ------------------------------------------------
        function tf = writeJournal(obj)
            % Rewrite the ENTIRE log to JournalFile. Called on every change, so
            % a crash loses at most the note being typed. Whole-file rewrite
            % rather than append because the log is editable: an appended
            % journal would keep the typo the operator just fixed.
            %
            % Fail-soft by design -- a full disk or a folder that has gone away
            % must not stop the operator writing notes, so it reports and
            % returns false rather than throwing into a keystroke callback.
            tf = false;
            if isempty(obj.JournalFile), return; end
            try
                d = fileparts(obj.JournalFile);
                if ~isempty(d) && ~isfolder(d), mkdir(d); end
                fid = fopen(obj.JournalFile,'w');
                if fid < 0, error('cannot open %s',obj.JournalFile); end
                c = onCleanup(@() fclose(fid));
                subj = obj.Subject; if isempty(subj), subj = '(no subject)'; end
                fprintf(fid,'%% MABR session notes — %s — session started %s\n', ...
                    subj,obj.StartTime);
                fprintf(fid,'%% Rewritten in full on every change; last written %s\n', ...
                    char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss')));
                lines = obj.log();
                for k = 1:numel(lines), fprintf(fid,'%s\n',lines{k}); end
                tf = true;
            catch me
                mabr.log.vprintf(1,1,'Could not write the notes journal: %s',me.message);
            end
        end
    end

    methods (Access = private)
        function ctx = context(obj)
            % Whatever the owner can tell us about where we are in the session.
            % Never throws: a stale ContextFcn costs a note its run number, not
            % the note.
            ctx = struct();
            if isempty(obj.ContextFcn), return; end
            try
                c = obj.ContextFcn();
                if isstruct(c) && isscalar(c), ctx = c; end
            catch me
                mabr.log.vprintf(3,'Note context unavailable: %s',me.message);
            end
        end

        function r = makeRecord(obj,body,mode,source,ctx)
            r = mabr.data.SessionNotes.blankRecord();
            r.Text    = body;
            r.Time    = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            r.Elapsed = obj.elapsed();
            r.Source  = char(source);
            g = @(f) mabr.data.SessionNotes.getdef(ctx,f,NaN);
            r.Run     = g('Run');
            r.NumRuns = g('NumRuns');
            r.Sweep   = g('Sweep');
            r.Stamp   = mabr.data.SessionNotes.renderStamp(mode,r);
        end

        function s = elapsed(obj)
            if obj.StartTic == 0, s = 0; else, s = toc(obj.StartTic); end
        end

        function changed(obj)
            obj.writeJournal();
            notify(obj,'NotesChanged');
        end
    end

    methods (Static)
        function n = fromFile(file)
            % Read a plain-text .notes journal back into a store. The stamps
            % survive as text; the structured fields behind them (run, sweep,
            % elapsed) do not, since the journal is a log rather than a record
            % -- for those, read Notes out of the .abr the session wrote.
            n = mabr.data.SessionNotes();
            txt = fileread(file);
            lines = mabr.data.SessionNotes.toLines(txt);
            rec = mabr.data.SessionNotes.emptyRecord();
            blank = mabr.data.SessionNotes.blankRecord();
            for k = 1:numel(lines)
                s = lines{k};
                if isempty(strtrim(s)) || startsWith(strtrim(s),'%'), continue; end
                [stamp,body] = mabr.data.SessionNotes.parseLine(s);
                if isempty(body), continue; end
                r = blank; r.Stamp = stamp; r.Text = body;
                rec(end+1) = r; %#ok<AGROW>
            end
            n.Notes = rec;
        end

        function S = emptyRecord()
            % A 0x0 struct carrying the note fields, so an empty log still has
            % a schema -- code reading Notes(k).Text off an empty log gets an
            % empty index rather than "no such field".
            S = struct('Stamp',{},'Text',{},'Time',{},'Elapsed',{}, ...
                       'Run',{},'NumRuns',{},'Sweep',{},'Source',{},'Edited',{});
        end

        function s = blankRecord()
            s = struct('Stamp','','Text','','Time','','Elapsed',NaN, ...
                       'Run',NaN,'NumRuns',NaN,'Sweep',NaN,'Source','','Edited',false);
        end

        function stamp = renderStamp(mode,r)
            % What goes between the brackets. 'auto' names the run and sweep
            % when there is one and falls back to the wall clock when there is
            % not -- a note taken while nothing is acquiring has no run to name,
            % and inventing one would be worse than saying the time.
            switch lower(char(mode))
                case 'none'
                    stamp = '';
                case 'clock'
                    stamp = mabr.data.SessionNotes.clockOf(r.Time);
                case 'elapsed'
                    % Leading '+' so an elapsed stamp is never mistaken for a
                    % wall clock at a glance -- they are the same six digits.
                    stamp = ['+' mabr.data.SessionNotes.hhmmss(r.Elapsed)];
                otherwise   % 'auto'
                    parts = {};
                    if isfinite(r.Run) && r.Run >= 1
                        parts{end+1} = sprintf('R%02d',r.Run);
                    end
                    if isfinite(r.Sweep) && r.Sweep >= 0
                        parts{end+1} = sprintf('S%04d',r.Sweep);
                    end
                    parts{end+1} = mabr.data.SessionNotes.clockOf(r.Time);
                    stamp = strjoin(parts,' ');
            end
        end

        function s = renderLine(r)
            if isempty(r.Stamp)
                s = r.Text;
            else
                s = sprintf('[%s] %s',r.Stamp,r.Text);
            end
        end

        function [stamp,body] = parseLine(line)
            % The inverse of renderLine. A line with no leading bracket is all
            % body, which is also how a freshly typed line in an editable log
            % arrives.
            stamp = '';
            body  = strtrim(char(line));
            t = regexp(body,'^\[([^\]]*)\]\s*(.*)$','tokens','once');
            if ~isempty(t)
                stamp = strtrim(t{1});
                body  = strtrim(t{2});
            end
        end

        function s = hhmmss(secs)
            if ~isfinite(secs) || secs < 0, secs = 0; end
            secs = floor(secs);
            s = sprintf('%02d:%02d:%02d',floor(secs/3600), ...
                mod(floor(secs/60),60),mod(secs,60));
        end
    end

    methods (Static, Access = private)
        function s = clockOf(isoTime)
            % HH:mm:ss out of an ISO stamp, without re-reading the clock: the
            % rendered time must be the time the note was taken, not the time
            % it was rendered.
            s = '';
            if isempty(isoTime), return; end
            i = strfind(isoTime,'T');
            if isempty(i), s = isoTime; else, s = isoTime(i(1)+1:end); end
        end

        function j = matchNote(old,used,stamp,body,k)
            % Which old note an edited line came from, out of the ones not yet
            % claimed by an earlier line.
            %
            % Untouched lines are matched first (stamp AND text), so a line the
            % user did not touch is never mistaken for the one they rewrote --
            % which is what would happen on two notes committed in the same
            % second, since their stamps are identical. Only then does a
            % stamp-only match apply, which is the edited-text case.
            j = [];
            if isempty(old), return; end
            avail  = ~used;
            byBoth = arrayfun(@(i) strcmp(old(i).Stamp,stamp) && ...
                                   strcmp(old(i).Text,body),1:numel(old)) & avail;
            if k <= numel(old) && byBoth(k), j = k; return; end
            hit = find(byBoth,1);
            if ~isempty(hit), j = hit; return; end
            if isempty(stamp), return; end
            byStamp = arrayfun(@(i) strcmp(old(i).Stamp,stamp),1:numel(old)) & avail;
            if k <= numel(old) && byStamp(k), j = k; return; end
            j = find(byStamp,1);
        end

        function c = toLines(txt)
            % Anything a caller might hand in -- char with newlines, cellstr,
            % string array -- as a cellstr of lines.
            if isstring(txt), txt = cellstr(txt); end
            if ischar(txt),   txt = {txt}; end
            if ~iscell(txt),  txt = {char(string(txt))}; end
            c = {};
            for k = 1:numel(txt)
                s = char(txt{k});
                if isempty(s), c{end+1} = ''; continue; end %#ok<AGROW>
                parts = regexp(s,'\r\n|\n|\r','split');
                c = [c parts]; %#ok<AGROW>
            end
            c = reshape(c,1,[]);
        end

        function v = getdef(s,f,d)
            if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
                v = double(s.(f));
                if ~isscalar(v), v = d; end
            else
                v = d;
            end
        end
    end
end
