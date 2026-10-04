classdef ScriptWriter
% mabr.analysis.ScriptWriter  A plain MATLAB script that reproduces an analysis exactly.
%
%   An analysis made in the offline GUI is the sum of things that are easy to
%   lose track of: which files were left out, every setting in force, and the
%   hand edits -- sweeps rejected, detections overridden, peaks placed or
%   marked absent, thresholds accepted, set or excluded. ScriptWriter writes
%   all of it down as one script that needs nothing but MABR and the data, so
%   the analysis can be re-run, read, reviewed, or handed to someone without
%   the GUI:
%
%       code = mabr.analysis.ScriptWriter.session(S);           % an analysed Session
%       code = mabr.analysis.ScriptWriter.session("x.mat");     % or its results (v2)
%       code = mabr.analysis.ScriptWriter.study(items);         % Project.exportItems(...)
%       file = mabr.analysis.ScriptWriter.write("replicate_analysis.m",code);
%       run(file)
%
%   THE SCRIPT, in order (each part a %% section):
%     1  a header: what it reproduces, what wrote it (the MABR commit, the
%        MATLAB version and the time) and how to point it at moved data;
%     2  setup: MABRROOT, DATAROOT (the folder the session folders are under)
%        and OUTFOLDER (where the export goes), then MABR on the path the way
%        MABR.m puts it there. DATAROOT and OUTFOLDER are assigned only when
%        not already defined, so a caller can set them and run(file);
%     3  the settings: mabr.analysis.Settings with EVERY property written as a
%        literal, then an assertion that they still hash to the value the
%        results were made with -- if a later MABR adds a setting or reads one
%        differently, the script stops and says so rather than quietly
%        analysing something else;
%     4  per session: the Session built from the same folders with the same
%        files excluded, its TimeOffset and ConductionDelayOverride (both
%        always written, NaN when the session has none); the recorded edits replayed
%        through Session.adoptEdits as literal tables (so they can be read and
%        changed); Session.analyze; and a check of the results against the
%        values recorded when the script was written;
%     5  the export: Export.tables/write/writeRScript/writeDictionary/
%        writeManifest into OUTFOLDER, every option written out;
%     6  optionally figures (the response grid and the audiogram).
%   It opens no window (unless figures are asked for), reads or writes no
%   MATLAB preference and touches no project file.
%
%   EXACT, NOT APPROXIMATE. Every value goes through literal(), whose text
%   evaluates back to a value isequaln to the one written: doubles in the
%   shortest decimal that round-trips (never more than %.17g), NaN/Inf/-Inf/
%   -0, empties at their sizes, text with every character it holds (quotes,
%   newlines, non-ASCII), datetimes to the last bit of their sub-millisecond
%   part, struct arrays, tables with their properties, nested cells. An edit
%   replayed from a literal is the edit that was made -- the manual
%   rejections included, which Session re-applies by (FileId, SweepIndex) and
%   never by position.
%
%   THE CHECK. The expected values -- each series' Threshold, Status and
%   Final value with its decision, each condition's p, detection and sweep
%   counts, each peak's latencies and values -- are written into the script
%   when it is generated; after analyze() a local function compares them by
%   key with isequaln and prints "replicated exactly", or every value that
%   differs. A floating-point value within 1e-6 of its own size of the
%   recorded one is rounding, not a different analysis -- a session opened
%   from a results file written before the condition means were stored in
%   double precision re-picks its peaks from single-precision means -- and is
%   counted ("replicated (n values compared; m of them within floating-point
%   rounding ...)") rather than listed. It never throws: a comparison must
%   not cost the analysis above
%   it, and a difference is information (a peak placed by hand at a level
%   whose lower levels the GUI did not re-track, say, which a fresh analysis
%   does track).
%
%   WHAT IT IS NOT. The script re-runs the analysis; it does not carry the
%   results across (that is what a results file is for). A v1 results file,
%   or a session never put through Session.analyze, records no Settings and
%   cannot be replicated: session() refuses it and study() leaves it out
%   (info.Skipped says which, and why).
%
%   See also mabr.analysis.Session, mabr.analysis.Settings,
%   mabr.analysis.Export, mabr.analysis.Project

    properties (Constant)
        % Characters per line before a long literal is continued with "...".
        LineWidth = 96

        % Columns of the Thresholds table a replication carries as edits: the
        % curation Session.estimateThresholds keeps by series key.
        CurationColumns = ["Decision","ManualValue","ManualKind","Note", ...
            "ReviewedBy","ReviewedAt","ReviewedValue","ReviewedMethod"]

        % Columns recorded as the expected results, per table (those present).
        ExpectedColumns = struct( ...
            'Thresholds',["Key","Threshold","Status","Censored","Final","FinalCensored", ...
                          "FinalLo","FinalHi","Decision"], ...
            'Conditions',["Key","p","isSig","Detected","nClean","nRejected"], ...
            'Peaks',["Key","Wave","State","PeakLatency","PeakValue","TroughLatency","TroughValue", ...
                     "LatencyOffset"])

        % Export options, by the function each belongs to. The values are the
        % defaults (Tables: Export.DefaultTables); the script writes every one
        % out, so a later change of a default cannot change what it exports.
        ExportTablesDefaults = struct( ...
            'Tables',["sessions","subjects","conditions","thresholds","peaks", ...
                      "peak_measures","io_slopes","waveforms","notes"], ...
            'ThresholdsAll',false,'OnlyReviewed',false,'IncludeExcluded',false, ...
            'IncludeTestMode',false,'WaveformWindow',[-2 10])
        ExportWriteDefaults = struct('Formats',"csv")

        % Tables that need a Session holding its sweeps: built by
        % Export.tables from the item's Session, except sweeps, which only
        % Export.writeRaw writes (one session at a time).
        RawTables = ["trial_waves","blocks","block_waves","sweeps"]
    end

    methods (Static)
        % =================================================================
        %  Scripts
        % =================================================================
        function [code,info] = session(src,opts)
            % The script that reproduces one analysed session.
            %
            %   src                 an analysed mabr.analysis.Session, a results
            %                       v2 struct (Session.toStruct), or the path of
            %                       a results file (Session.saveResults)
            %   opts.Title          first line of the header ("" = "Replicate
            %                       the analysis of <name>")
            %   opts.DataRoot       the folder the session folder is written
            %                       relative to ("" = the session folder's
            %                       parent); a folder outside it is written in full
            %   opts.OutputFolder   OUTFOLDER, where the export goes ("" =
            %                       fullfile(tempdir,"mabr_replication_<stamp>"))
            %   opts.IncludeEdits   replay the recorded edits (true)
            %   opts.IncludeExport  write the export section (true)
            %   opts.ExportOptions  Export options (struct, see below)
            %   opts.IncludePlots   draw the response grid and audiogram (false)
            %   opts.IncludeCheck   compare with the recorded results (true)
            %   opts.Labels         the session's export Labels (10 section 15.1;
            %                       [] = made from the results: its subject, no
            %                       timepoint or group, in the study)
            %   opts.Notes          its notes table (Catalog.notes; [] = none)
            %   code  (returned) the script, 1x1 string (lines joined by newline)
            %   info  (returned) struct: Keys, Skipped (table Key, Reason),
            %         Warnings (string column, also written into the header),
            %         DataRoot, Commit, SettingsHash (one per session)
            %
            %   ExportOptions fields: Tables, ThresholdsAll, OnlyReviewed,
            %   IncludeExcluded, IncludeTestMode, WaveformWindow, Subjects,
            %   BlockSize (for Export.tables), Formats, Prefix, Append (for
            %   Export.write) and RScript (also write the R script and the column
            %   dictionary; true). The raw tables trial_waves/blocks/block_waves
            %   are built from the sessions the script has just analysed, and
            %   sweeps is written per session by Export.writeRaw. Any other field
            %   is left out of the script, with a line in info.Warnings and in the
            %   script's header.
            arguments
                src
                opts.Title (1,1) string = ""
                opts.DataRoot (1,1) string = ""
                opts.OutputFolder (1,1) string = ""
                opts.IncludeEdits (1,1) logical = true
                opts.IncludeExport (1,1) logical = true
                opts.ExportOptions (1,1) struct = struct()
                opts.IncludePlots (1,1) logical = false
                opts.IncludeCheck (1,1) logical = true
                opts.Labels = []
                opts.Notes = []
            end
            R = mabr.analysis.ScriptWriter.asResults(src);
            item = struct('Key',"",'Results',R,'Labels',{opts.Labels},'Notes',{opts.Notes});
            [code,info] = mabr.analysis.ScriptWriter.generate(item,opts,"session");
        end

        function [code,info] = study(items,opts)
            % The script that reproduces several analysed sessions and their export.
            %
            %   items  struct array as Project.exportItems returns it (10 section
            %          15.1): Key, Results (a results v2 struct, the path of a
            %          results file, or a Session), Labels, Notes, and Session
            %          ([] or a Session, used when Results is empty)
            %   opts   as session() (without Labels/Notes: each item has its own)
            %   code   (returned) the script, 1x1 string
            %   info   (returned) as session(); Skipped lists the items that
            %          cannot be replicated (never analysed, v1 results) and why
            arguments
                items struct
                opts.Title (1,1) string = ""
                opts.DataRoot (1,1) string = ""
                opts.OutputFolder (1,1) string = ""
                opts.IncludeEdits (1,1) logical = true
                opts.IncludeExport (1,1) logical = true
                opts.ExportOptions (1,1) struct = struct()
                opts.IncludePlots (1,1) logical = false
                opts.IncludeCheck (1,1) logical = true
            end
            list = struct('Key',{},'Results',{},'Labels',{},'Notes',{});
            skipped = table(strings(0,1),strings(0,1),'VariableNames',{'Key','Reason'});
            for k = 1:numel(items)
                it  = items(k);
                key = string(getOr(it,'Key',""));
                try
                    R = getOr(it,'Results',[]);         % a struct, a file, or a Session
                    if isempty(R)
                        R = getOr(it,'Session',[]);
                    end
                    if isempty(R)
                        error('mabr:analysis:ScriptWriter:notAnalysed','No results.');
                    end
                    R = mabr.analysis.ScriptWriter.asResults(R);
                catch ME
                    skipped(end+1,:) = {key,string(ME.message)}; %#ok<AGROW>
                    continue
                end
                list(end+1) = struct('Key',key,'Results',R, ...
                    'Labels',{getOr(it,'Labels',[])},'Notes',{getOr(it,'Notes',[])}); %#ok<AGROW>
            end
            if isempty(list)
                error('mabr:analysis:ScriptWriter:noSessions', ...
                    'None of the %d sessions can be replicated: %s',numel(items), ...
                    strjoin(skipped.Key + " (" + skipped.Reason + ")","; "));
            end
            [code,info] = mabr.analysis.ScriptWriter.generate(list,opts,"study");
            info.Skipped = [skipped; info.Skipped];
        end

        function file = write(file,code)
            % Write a script as UTF-8, creating its folder.
            %
            % A script runs by its file name, so the name must be a MATLAB
            % identifier: one that is not (a subject's "SUBJ-ID-9001_...") is
            % made one with matlab.lang.makeValidName, and the name actually
            % written is returned.
            %
            %   file  destination (".m" added when it has no extension)
            %   code  the script: text, or a string array / cellstr of lines
            %   file  (returned) 1x1 string, the file written
            arguments
                file (1,1) string
                code {mustBeText}
            end
            code = string(code);
            if ~isscalar(code), code = strjoin(reshape(code,1,[]),newline); end
            [d,nm,e] = fileparts(file);
            if e == "", e = ".m"; end
            if ~isvarname(nm)
                nm = string(matlab.lang.makeValidName(char(nm)));
                nm = extractBefore(nm,min(strlength(nm),namelengthmax)+1);
            end
            if d ~= "" && ~isfolder(d)
                [ok,msg] = mkdir(d);
                if ~ok
                    error('mabr:analysis:ScriptWriter:writeFailed','Could not create %s: %s',d,msg);
                end
            end
            file = fullfile(d,nm + e);
            if ~endsWith(code,newline), code = code + newline; end
            fid = fopen(file,'w');
            if fid < 0
                error('mabr:analysis:ScriptWriter:writeFailed','Could not write %s.',file);
            end
            closer = onCleanup(@() fclose(fid));
            fwrite(fid,unicode2native(char(code),'UTF-8'),'uint8');
            delete(closer);
        end

        % =================================================================
        %  Literals
        % =================================================================
        function s = literal(v)
            % The exact MATLAB literal of a value: eval(literal(v)) is isequaln v.
            %
            %   double/single/integer  the shortest decimal that round-trips
            %                          (never more than %.17g), NaN, Inf, -Inf,
            %                          -0; complex and sparse; empties at their
            %                          sizes; 64-bit integers past 2^53 exactly
            %   logical, char, string  quotes, control characters, non-ASCII
            %                          text, <missing>; missing
            %   datetime               ISO text with its InputFormat when that is
            %                          exact, else the epoch plus milliseconds to
            %                          the last bit; NaT; TimeZone
            %   duration, categorical
            %   struct (scalar, array, empty), cell, table (variable and row
            %   names, dimension names, units, descriptions, description, user
            %   data), N-D arrays of any of these, and mabr.analysis.Settings
            %   (its constructor with every property)
            %
            % Long arrays continue over lines with "...". Anything else (a
            % function handle, another object) errors
            % mabr:analysis:ScriptWriter:unsupported.
            %
            %   v  the value
            %   s  (returned) 1x1 string, possibly several lines
            s = string(mabr.analysis.ScriptWriter.lit(v));
        end
    end

    % =====================================================================
    %  The generator
    % =====================================================================
    methods (Static, Access = private)
        function R = asResults(src)
            % A results v2 struct from a Session, a struct or a file, or an
            % error saying why it cannot be replicated.
            if isa(src,'mabr.analysis.Session')
                if ~isscalar(src)
                    error('mabr:analysis:ScriptWriter:badSource','One Session at a time.');
                end
                R = src.toStruct(false,false);
            elseif isstruct(src) && isscalar(src)
                R = src;
            elseif (isstring(src) && isscalar(src)) || ischar(src)
                f = string(src);
                if ~isfile(f)
                    error('mabr:analysis:ScriptWriter:badSource','No results file %s.',f);
                end
                R = load(f,'-mat');
            else
                error('mabr:analysis:ScriptWriter:badSource', ...
                    'Give an analysed Session, a results struct or a results file.');
            end
            v = getOr(R,'Version',1);
            if ~isnumeric(v) || ~isscalar(v) || v < 2 || ~isfield(R,'Summary')
                error('mabr:analysis:ScriptWriter:notReplicable', ...
                    ['These are version 1 results, which record no analysis settings: ' ...
                     'analyse the session again (Session.analyze) to replicate it.']);
            end
            st = getOr(R,'Settings',[]);
            if isa(st,'mabr.analysis.Settings') && isscalar(st)
                R.Settings = st.toStruct();             % an object where a struct is expected
                st = R.Settings;
            end
            if isempty(st) || ~isstruct(st)
                error('mabr:analysis:ScriptWriter:notAnalysed', ...
                    ['The session has not been analysed with Session.analyze, so there ' ...
                     'are no settings to replicate.']);
            end
            paths = string(getOr(R.Summary,'Paths',strings(0,1)));
            if isempty(paths) || all(paths == "")
                error('mabr:analysis:ScriptWriter:notReplicable', ...
                    'The results name no session folder (Summary.Paths) to read again.');
            end
        end

        function [code,info] = generate(items,opts,kind)
            % The script for a list of {Key, Results, Labels, Notes}.
            n = numel(items);
            warn = strings(0,1);
            q = @mabr.analysis.ScriptWriter.literal;

            % ---- what each session needs ----------------------------------
            Dc = cell(1,n);
            for k = 1:n
                [Dc{k},w] = mabr.analysis.ScriptWriter.describe(items(k),opts);
                warn = [warn; w]; %#ok<AGROW>
            end
            D = [Dc{:}];

            % ---- one Settings variable per distinct set of settings ----------
            sv = strings(1,n);                  % the variable each session uses
            uniq = {};  names = strings(0,1);  users = {};
            for k = 1:n
                hit = 0;
                for u = 1:numel(uniq)
                    if isequaln(uniq{u}.toStruct(),D(k).Settings.toStruct())
                        hit = u;
                        break
                    end
                end
                if hit == 0
                    uniq{end+1} = D(k).Settings; %#ok<AGROW>
                    if isempty(names), names = "settings";
                    else, names(end+1,1) = "settings" + (numel(names)+1); end %#ok<AGROW>
                    users{end+1} = k; %#ok<AGROW>
                    hit = numel(uniq);
                else
                    users{hit}(end+1) = k; %#ok<AGROW>
                end
                sv(k) = names(hit);
            end

            % ---- where the data is ----------------------------------------
            [root,rel] = mabr.analysis.ScriptWriter.layout({D.Paths},opts.DataRoot);
            if root == "" && opts.DataRoot ~= ""
                warn(end+1,1) = "Not every session folder is under DataRoot " + opts.DataRoot + ...
                    ", so their paths are written in full.";
            end
            [X,w] = mabr.analysis.ScriptWriter.exportOptions(opts.ExportOptions);
            warn = [warn; w];

            commit = mabr.analysis.ScriptWriter.commitText();
            now_   = datetime('now');
            stamp  = string(char(now_,'yyMMdd''T''HHmmss'));
            L = strings(0,1);

            % ---- 1 header -------------------------------------------------
            ttl = opts.Title;
            if ttl == ""
                if kind == "session", ttl = "Replicate the analysis of " + D(1).Name;
                else, ttl = "Replicate the analysis of " + n + " sessions"; end
            end
            L(end+1,1) = "% " + regexprep(ttl,'[\r\n]+',' ');
            L(end+1,1) = "%";
            if kind == "session"
                L = [L; comment("Reproduces the offline ABR analysis of session """ + D(1).Name + ...
                    """" + subjectText(D(1)) + " without the GUI.")];
            else
                L = [L; comment("Reproduces the offline ABR analysis of these " + n + ...
                    " sessions, and their export, without the GUI:")];
                for k = 1:n
                    L(end+1,1) = "%   " + k + ". " + D(k).Name + subjectText(D(k)); %#ok<AGROW>
                end
            end
            L(end+1,1) = "%";
            what = "It reads " + ternary(kind == "session","the session","each session") + ...
                " from the same .abr files, leaving out the same files; " + ...
                "applies every analysis setting, written out below and checked against the hash " + ...
                "of the settings the results were made with; ";
            if opts.IncludeEdits
                what = what + "replays the manual edits made to " + ...
                    ternary(kind == "session","it","them") + " (" + editSummary(D) + "); ";
            else
                what = what + "does NOT replay the manual edits (results that depend on them " + ...
                    "will differ); ";
            end
            what = what + "and runs the analysis";
            if opts.IncludeCheck
                what = what + ", then compares the results with those recorded when this " + ...
                    "script was written";
            end
            what = what + ".";
            if opts.IncludeExport
                what = what + " It then writes the export tables into OUTFOLDER.";
            end
            if opts.IncludePlots
                what = what + " It draws the response grid and the audiogram.";
            end
            L = [L; comment(what)];
            L(end+1,1) = "%";
            L = [L; comment("Generated by mabr.analysis.ScriptWriter: MABR " + commit + ", MATLAB " + ...
                string(version) + ", " + string(mabr.analysis.Stats.isoTime(now_)) + ".")];
            L(end+1,1) = "%";
            how = "To run it on another computer, or after moving the data, edit MABRROOT (the MABR " + ...
                "toolbox) and DATAROOT (the folder the session folders are in)";
            if opts.IncludeExport
                how = how + " and OUTFOLDER (where the export goes) below, or define DATAROOT and " + ...
                    "OUTFOLDER before calling run() on this file.";
            else
                how = how + " below, or define DATAROOT before calling run() on this file.";
            end
            how = how + " Nothing here opens a window";
            if opts.IncludePlots, how = how + " other than the figures"; end
            how = how + ", reads or writes a MATLAB preference, or touches a project file.";
            L = [L; comment(how)];
            if ~isempty(warn)
                L(end+1,1) = "%";
                L(end+1,1) = "% Warnings when this script was written:";
                for w = reshape(warn,1,[])
                    L = [L; comment("- " + w)]; %#ok<AGROW>
                end
            end

            % ---- 2 setup --------------------------------------------------
            L(end+1,1) = "";
            L(end+1,1) = "%% Setup";
            L(end+1,1) = "MABRROOT = " + q(string(mabr.Config.root())) + ";";
            if root ~= ""
                L(end+1,1) = "if ~exist('DATAROOT','var'), DATAROOT = " + q(root) + "; end";
            else
                L(end+1,1) = "% The session folders share no parent folder, so their paths are written in full.";
                L(end+1,1) = "if ~exist('DATAROOT','var'), DATAROOT = """"; end";
            end
            if opts.IncludeExport
                if opts.OutputFolder ~= ""
                    L(end+1,1) = "if ~exist('OUTFOLDER','var'), OUTFOLDER = " + q(opts.OutputFolder) + "; end";
                else
                    L(end+1,1) = "if ~exist('OUTFOLDER','var'), OUTFOLDER = fullfile(tempdir," + ...
                        q("mabr_replication_" + stamp) + "); end";
                end
            end
            L(end+1,1) = "% MABR and every folder under it except .git, as MABR.m adds them.";
            L(end+1,1) = "mabrPath = split(string(genpath(MABRROOT)),pathsep);";
            L(end+1,1) = "mabrPath(mabrPath == """" | contains(mabrPath,'.git')) = [];";
            L(end+1,1) = "addpath(char(join(mabrPath,pathsep)));";

            % ---- 3 settings -----------------------------------------------
            for u = 1:numel(uniq)
                s = uniq{u};
                L(end+1,1) = ""; %#ok<AGROW>
                if isscalar(uniq)
                    L(end+1,1) = "%% Settings"; %#ok<AGROW>
                    L = [L; comment("Every analysis setting, as the results were made with them. " + ...
                        "Change one here to see what it changes.")]; %#ok<AGROW>
                else
                    L(end+1,1) = "%% Settings " + u + " of " + numel(uniq); %#ok<AGROW>
                    L = [L; comment("Used by " + strjoin([D(users{u}).Name],", ") + ".")]; %#ok<AGROW>
                end
                L(end+1,1) = names(u) + " = " + mabr.analysis.ScriptWriter.settingsLit(s) + ";"; %#ok<AGROW>
                h = s.hash();
                L(end+1,1) = "assert(" + names(u) + ".hash() == " + q(h) + ", ..."; %#ok<AGROW>
                L(end+1,1) = "    'mabr:analysis:ScriptWriter:settingsHash', ..."; %#ok<AGROW>
                L(end+1,1) = "    ['These settings no longer hash to " + h + ", as the settings the ' ..."; %#ok<AGROW>
                L(end+1,1) = "     'results were made with did: this MABR has a setting they did not ' ..."; %#ok<AGROW>
                L(end+1,1) = "     'have, or reads one differently, so the analysis would not be the same.']);"; %#ok<AGROW>
            end

            % ---- 4 sessions -----------------------------------------------
            if kind == "study"
                L(end+1,1) = "";
                if opts.IncludeCheck
                    L(end+1,1) = "replicated = false(1," + n + ");";
                end
                if opts.IncludeExport
                    L(end+1,1) = "items = struct('Key',{},'Results',{},'Labels',{},'Notes',{},'Session',{});";
                    if any(X.Tables.Tables == "sweeps")
                        L(end+1,1) = "sweepFiles = table();";
                    end
                end
            end
            for k = 1:n
                d = D(k);
                L(end+1,1) = ""; %#ok<AGROW>
                if kind == "session"
                    L(end+1,1) = "%% Session: " + d.Name; %#ok<AGROW>
                else
                    L(end+1,1) = "%% Session " + k + " of " + n + ": " + d.Name; %#ok<AGROW>
                end
                L = [L; mabr.analysis.ScriptWriter.sessionComment(d)]; %#ok<AGROW>
                L(end+1,1) = "S = mabr.analysis.Session(" + ...
                    mabr.analysis.ScriptWriter.pathsLit(d.Paths,rel{k}) + ", ..."; %#ok<AGROW>
                L(end+1,1) = "    Name=" + q(d.Name) + ", ..."; %#ok<AGROW>
                if d.Key ~= ""
                    L(end+1,1) = "    Key=" + q(d.Key) + ", ..."; %#ok<AGROW>
                end
                if ~isempty(d.FolderKeys)
                    L(end+1,1) = "    FolderKeys=" + indentMore(q(d.FolderKeys),"    ") + ", ..."; %#ok<AGROW>
                end
                if mabr.analysis.ScriptWriter.mixedSubjects(d.Paths)
                    L(end+1,1) = "    Force=true, ...    % the folders name different subjects"; %#ok<AGROW>
                end
                L(end+1,1) = "    Exclude=" + indentMore(q(d.Exclude),"    ") + ", ..."; %#ok<AGROW>
                L(end+1,1) = "    UnitOverride=" + indentMore(q(d.UnitOverride),"    ") + ", ..."; %#ok<AGROW>
                L(end+1,1) = "    Verbose=true);"; %#ok<AGROW>
                L(end+1,1) = "% The session's own latency offsets (ms; NaN = the settings' TimeOffset and"; %#ok<AGROW>
                L(end+1,1) = "% conduction delay): reported latencies are re sound arrival."; %#ok<AGROW>
                L(end+1,1) = "S.TimeOffset = " + q(d.TimeOffset) + ";"; %#ok<AGROW>
                L(end+1,1) = "S.ConductionDelayOverride = " + q(d.ConductionDelayOverride) + ";"; %#ok<AGROW>

                if opts.IncludeEdits
                    L(end+1,1) = ""; %#ok<AGROW>
                    L = [L; comment("The manual edits, as recorded: sweeps rejected or restored by " + ...
                        "hand (by file and sweep number), detection overrides, peaks placed by hand " + ...
                        "or marked absent, and threshold decisions (with any set aside when a " + ...
                        "regrouping lost their series). analyze() applies each where it belongs.")]; %#ok<AGROW>
                    L = [L; mabr.analysis.ScriptWriter.structLines("edits",d.Edits)]; %#ok<AGROW>
                    L(end+1,1) = "S.adoptEdits(edits);"; %#ok<AGROW>
                end

                L(end+1,1) = ""; %#ok<AGROW>
                L(end+1,1) = "S.analyze(" + sv(k) + ");"; %#ok<AGROW>

                if opts.IncludeCheck
                    L(end+1,1) = ""; %#ok<AGROW>
                    L = [L; comment("The results recorded when this script was written, to compare with.")]; %#ok<AGROW>
                    L = [L; mabr.analysis.ScriptWriter.structLines("expected",d.Expected)]; %#ok<AGROW>
                    if kind == "session"
                        L(end+1,1) = "replicatedExactly = compareWithRecorded(S,expected," + q(d.Name) + ");"; %#ok<AGROW>
                    else
                        L(end+1,1) = "replicated(" + k + ") = compareWithRecorded(S,expected," + q(d.Name) + ");"; %#ok<AGROW>
                    end
                end

                if kind == "study"
                    if opts.IncludeExport
                        L(end+1,1) = ""; %#ok<AGROW>
                        L = [L; mabr.analysis.ScriptWriter.itemLines(d,"items(" + k + ")",X)]; %#ok<AGROW>
                    end
                    if opts.IncludePlots
                        L(end+1,1) = "S.plotGrid();"; %#ok<AGROW>
                        L(end+1,1) = "S.plotAudiogram();"; %#ok<AGROW>
                    end
                end
            end
            if kind == "study" && opts.IncludeCheck
                L(end+1,1) = "";
                L(end+1,1) = "fprintf('%d of %d sessions replicated.\n',sum(replicated),numel(replicated));";
            end

            % ---- 5 export -------------------------------------------------
            if opts.IncludeExport
                L(end+1,1) = "";
                L(end+1,1) = "%% Export";
                if kind == "session"
                    L = [L; mabr.analysis.ScriptWriter.itemLines(D(1),"items",X)];
                end
                L = [L; mabr.analysis.ScriptWriter.exportLines(X,names(1),numel(uniq) > 1, ...
                    "Replication: " + ttl)];
            end

            % ---- 6 figures --------------------------------------------------
            if opts.IncludePlots && kind == "session"
                L(end+1,1) = "";
                L(end+1,1) = "%% Figures";
                L(end+1,1) = "S.plotGrid();";
                L(end+1,1) = "S.plotAudiogram();";
            end

            % ---- the comparison, a local function ---------------------------
            if opts.IncludeCheck
                L(end+1,1) = "";
                L(end+1,1) = "%% Local function";
                L = [L; mabr.analysis.ScriptWriter.checkFunction()];
            end

            code = strjoin(L,newline) + newline;
            info = struct('Keys',reshape([D.Key],[],1), ...
                'Skipped',table(strings(0,1),strings(0,1),'VariableNames',{'Key','Reason'}), ...
                'Warnings',warn,'DataRoot',root,'Commit',commit, ...
                'SettingsHash',reshape([D.Hash],[],1));
        end

        function [d,warn] = describe(item,opts)
            % Everything the script needs about one session, from its results.
            warn = strings(0,1);
            R  = item.Results;
            Sm = R.Summary;
            d = struct();
            d.Name    = string(getOr(Sm,'Name',""));
            d.Key     = string(item.Key);
            if d.Key == "", d.Key = string(getOr(Sm,'Key',"")); end
            d.Subject = string(getOr(Sm,'Subject',""));
            d.Paths   = reshape(string(getOr(Sm,'Paths',strings(0,1))),[],1);
            if d.Name == ""
                [~,nm] = fileparts(d.Paths(1));
                d.Name = string(nm);
            end
            % The member folders' catalog keys, written only where they are not
            % what Session would make of the folders itself (the Key for one
            % folder, the folder names for a pool).
            fk = reshape(string(getOr(Sm,'Keys',strings(0,1))),[],1);
            fk = fk(~ismissing(fk) & fk ~= "");
            if isscalar(d.Paths)
                dflt = d.Key;
            else
                dflt = strings(numel(d.Paths),1);
                for i = 1:numel(d.Paths)
                    [~,nm,ext] = fileparts(regexprep(d.Paths(i),'[\\/]+$',''));
                    dflt(i) = string(nm) + string(ext);
                end
            end
            if isempty(fk) || isequal(fk,dflt), fk = strings(0,1); end
            d.FolderKeys = fk;
            ex = getOr(Sm,'Exclude',strings(0,1));
            if isempty(ex), ex = strings(0,1); end
            d.Exclude = reshape(string(ex),[],1);
            uo = getOr(Sm,'UnitOverride',[]);
            if ~isstruct(uo) || ~isscalar(uo)
                uo = struct('InputFullScale',NaN,'AmplifierGain',NaN);
            end
            d.UnitOverride = uo;
            % The session's own latency offsets (ms; NaN = none, the settings'
            % own in force): Session's defaults are NaN, and a results file
            % from before they were is read the same way (a stored 0 stays 0,
            % which is what it meant then).
            d.TimeOffset = scalarNumber(getOr(Sm,'TimeOffset',NaN));
            d.ConductionDelayOverride = scalarNumber(getOr(Sm,'ConductionDelayOverride',NaN));
            dt = getOr(Sm,'Date',"");
            if isdatetime(dt)
                if isnat(dt), dt = ""; else, dt = string(char(dt,'yyyy-MM-dd')); end
            end
            d.Date = string(dt);
            if ~isscalar(d.Date) || ismissing(d.Date), d.Date = ""; end
            d.Date = regexprep(d.Date,'^(\d{4}-\d{2}-\d{2})T.*$','$1');   % the day is enough

            % The settings, and whether they still are the ones recorded.
            [s,w] = mabr.analysis.Settings.fromStruct(R.Settings);
            for x = reshape(w,1,[])
                warn(end+1,1) = d.Name + ": a recorded setting could not be restored: " + x; %#ok<AGROW>
            end
            d.Settings = s;
            d.Hash = s.hash();
            rec = string(getOr(getOr(R,'Provenance',struct()),'SettingsHash',""));
            if isscalar(rec) && ~ismissing(rec) && rec ~= "" && rec ~= d.Hash
                warn(end+1,1) = d.Name + ": the results record settings hash " + rec + ...
                    ", these settings hash to " + d.Hash + ...
                    " (a setting has changed meaning since).";
            end

            % Labels and notes for the export.
            lab = item.Labels;
            if isempty(lab) || ~isstruct(lab)
                lab = mabr.analysis.ScriptWriter.defaultLabels(R);
            end
            d.Labels = lab;
            nt = item.Notes;
            if ~istable(nt)
                nt = table(NaT(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
                    strings(0,1),strings(0,1),'VariableNames', ...
                    {'Time','Stamp','Text','Run','Sweep','Source','Scope'});
            end
            d.Notes = nt;

            % The edits, as tables (empty ones keep their columns, so the
            % script shows where an edit would go).
            E = struct();
            E.ManualRejections = tableOr(R,'ManualRejections', ...
                table(strings(0,1),zeros(0,1),false(0,1),NaT(0,1),strings(0,1), ...
                'VariableNames',{'FileId','SweepIndex','Reject','Time','By'}));
            E.DetectionOverrides = tableOr(R,'DetectionOverrides', ...
                table(strings(0,1),zeros(0,1),NaT(0,1),strings(0,1), ...
                'VariableNames',{'Key','Value','Time','By'}));
            E.PeakOverrides = tableOr(R,'PeakOverrides', ...
                table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),zeros(0,1), ...
                NaT(0,1),strings(0,1),'VariableNames', ...
                {'Key','Wave','Kind','State','Latency','Time','By'}));
            E.Thresholds = mabr.analysis.ScriptWriter.curation(tableOr(R,'Thresholds',table()),false);
            E.CurationArchive = mabr.analysis.ScriptWriter.curation(tableOr(R,'CurationArchive',table()),true);
            d.Edits = E;
            d.NumEdits = struct('Rejections',height(E.ManualRejections), ...
                'Detections',height(E.DetectionOverrides),'Peaks',height(E.PeakOverrides), ...
                'Decisions',height(E.Thresholds));

            % The expected results.
            Xp = struct();
            for f = reshape(string(fieldnames(mabr.analysis.ScriptWriter.ExpectedColumns)),1,[])
                T = tableOr(R,f,table());
                want = mabr.analysis.ScriptWriter.ExpectedColumns.(f);
                vars = string(T.Properties.VariableNames);
                if ~ismember("Key",vars), continue; end
                have = want(ismember(want,vars));
                if f == "Peaks" && ~ismember("Wave",have), continue; end
                Xp.(f) = T(:,cellstr(have));
            end
            d.Expected = Xp;
            if opts.IncludeCheck && isempty(fieldnames(Xp))
                warn(end+1,1) = d.Name + ": the results hold no Thresholds, Conditions or " + ...
                    "Peaks to compare with.";
            end
        end

        function T = curation(Th,allRows)
            % Key and the curation columns of a Thresholds (or archive) table;
            % unless allRows, only the rows carrying a decision, a note or a
            % review -- the others carry nothing.
            cols = ["Key",mabr.analysis.ScriptWriter.CurationColumns];
            if width(Th) == 0 || ~ismember("Key",string(Th.Properties.VariableNames))
                T = table(strings(0,1),strings(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
                    strings(0,1),NaT(0,1),zeros(0,1),strings(0,1),'VariableNames',cellstr(cols));
                return
            end
            if allRows
                T = Th;
                if ismember("Fit",string(T.Properties.VariableNames)), T.Fit = []; end
                return
            end
            have = cols(ismember(cols,string(Th.Properties.VariableNames)));
            T = Th(:,cellstr(have));
            keep = false(height(T),1);
            for c = have(2:end)
                v = T.(c);
                if isdatetime(v)
                    keep = keep | ~isnat(v);
                elseif isnumeric(v)
                    keep = keep | ~isnan(v);
                else
                    v = string(v);
                    keep = keep | (~ismissing(v) & v ~= "");
                end
            end
            T = T(keep,:);
        end

        function lab = defaultLabels(R)
            % Export labels for a session with no project around it: its own
            % subject, no timepoint or group, in the study, every series used.
            Sm = R.Summary;
            lab = struct( ...
                'Subject',string(getOr(Sm,'Subject',"")), ...
                'SubjectRaw',string(getOr(Sm,'SubjectRaw',"")), ...
                'Timepoint',"",'TimepointOrder',1,'Group',"",'InStudy',true, ...
                'TestMode',logical(getOr(Sm,'TestMode',false)), ...
                'DaysFromReference',NaN, ...
                'TimeOffset',scalarNumber(getOr(Sm,'TimeOffset',NaN)), ...
                'ConductionDelay',scalarNumber(getOr(Sm,'ConductionDelayOverride',NaN)), ...
                'Comment',"",'Free',struct(), ...
                'UsedInStudy',struct('SeriesKey',strings(0,1),'Used',false(0,1)));
            Th = getOr(R,'Thresholds',table());
            if istable(Th) && ismember("Key",string(Th.Properties.VariableNames))
                lab.UsedInStudy = struct('SeriesKey',string(Th.Key),'Used',true(height(Th),1));
            end
        end

        function tf = mixedSubjects(paths)
            % Do the folders name more than one subject, so that Session needs
            % Force (its own rule: distinct subjects among those named)?
            subj = strings(numel(paths),1);
            for i = 1:numel(paths)
                subj(i) = mabr.analysis.AbrFile.subjectOf(paths(i));
            end
            tf = numel(unique(subj(subj ~= ""))) > 1;
        end

        function [root,rel] = layout(pathSets,dataRoot)
            % DATAROOT, and each session folder as names below it.
            %   pathSets  cell, one string column of folders per session
            %   root      (returned) "" when the folders are written in full
            %   rel       (returned) cell like pathSets, each a cell of string
            %             rows (the folder names below root); {} = in full
            rel = cell(size(pathSets));
            all_ = vertcat(pathSets{:});
            for i = 1:numel(all_), all_(i) = normPath(all_(i)); end
            if dataRoot ~= ""
                root = normPath(dataRoot);
            else
                parents = strings(numel(all_),1);
                for i = 1:numel(all_), parents(i) = string(fileparts(all_(i))); end
                root = commonFolder(parents);
            end
            if root == "", return; end
            for k = 1:numel(pathSets)
                p = pathSets{k};
                r = cell(numel(p),1);
                for i = 1:numel(p)
                    r{i} = below(normPath(p(i)),root);
                    if isempty(r{i}) && ~isstring(r{i})
                        root = "";          % one folder outside: every path in full
                        rel = cell(size(pathSets));
                        return
                    end
                end
                rel{k} = r;
            end
        end

        function s = pathsLit(paths,rel)
            % The session-folder argument: fullfile(DATAROOT,...) or full paths.
            e = strings(numel(paths),1);
            for i = 1:numel(paths)
                if isempty(rel)
                    e(i) = mabr.analysis.ScriptWriter.literal(normPath(paths(i)));
                else
                    e(i) = "fullfile(DATAROOT";
                    for p = rel{i}
                        e(i) = e(i) + "," + mabr.analysis.ScriptWriter.literal(p);
                    end
                    e(i) = e(i) + ")";
                end
            end
            if isscalar(e)
                s = e;
            else
                s = "[" + strjoin(e,"; ..." + newline + "    ") + "]";
            end
        end

        function L = sessionComment(d)
            % The comment opening one session block.
            t = "Subject " + ternary(d.Subject == "","unknown",d.Subject);
            if d.Date ~= "", t = t + ", " + d.Date; end
            t = t + "; " + numel(d.Paths) + " folder" + ternary(isscalar(d.Paths),"","s");
            if ~isempty(d.Exclude)
                t = t + "; " + numel(d.Exclude) + " file" + ternary(isscalar(d.Exclude),"","s") + ...
                    " left out by hand";
            end
            if isfinite(d.ConductionDelayOverride)
                t = t + "; conduction delay " + d.ConductionDelayOverride + " ms (this session's own)";
            end
            t = t + "; analysed with settings hash " + d.Hash + ".";
            L = comment(t);
        end

        function L = structLines(var,S)
            % var = struct('a',<table>, ...) with one field per line.
            f = reshape(string(fieldnames(S)),1,[]);
            if isempty(f)
                L = var + " = struct();";
                return
            end
            L = var + " = struct( ...";
            for j = 1:numel(f)
                v = S.(f(j));
                t = mabr.analysis.ScriptWriter.literal(v);
                if iscell(v), t = "{" + t + "}"; end
                sep = ", ...";
                if j == numel(f), sep = ");"; end
                L(end+1,1) = "    '" + f(j) + "', " + indentMore(t,"    ") + sep; %#ok<AGROW>
            end
        end

        function L = itemLines(d,target,X)
            % One export item: the session just analysed, with its labels (and
            % the Session itself when a raw table is exported, since only it
            % holds the sweeps).
            q = @mabr.analysis.ScriptWriter.literal;
            L = target + " = struct('Key',S.Key,'Results',S.toStruct(false,true), ...";
            L(end+1,1) = "    'Labels'," + indentMore(q(d.Labels),"    ") + ", ...";
            L(end+1,1) = "    'Notes'," + indentMore(q(d.Notes),"    ") + ", ...";
            if any(ismember(X.Tables.Tables,mabr.analysis.ScriptWriter.RawTables))
                L(end+1,1) = "    'Session',S);";
            else
                L(end+1,1) = "    'Session',[]);";
            end
            if any(X.Tables.Tables == "sweeps")
                w = X.Write;
                w = rmfield(w,intersect(fieldnames(w),{'Append'}));
                if ~isfield(w,'Formats') || isequal(string(w.Formats),"csv")
                    w.Formats = "parquet";          % writeRaw refuses CSV for sweeps
                end
                L(end+1,1) = "sweepFiles = [sweepFiles; mabr.analysis.Export.writeRaw(S," + target + ...
                    ",OUTFOLDER,Tables=""sweeps""" + mabr.analysis.ScriptWriter.nameValues(w) + ")];";
                if target == "items"
                    L = ["if ~isfolder(OUTFOLDER), mkdir(OUTFOLDER); end"; "sweepFiles = table();"; L];
                end
            end
        end

        function t = nameValues(S)
            % ",Name=<literal>,..." for every field of S.
            t = "";
            for f = reshape(string(fieldnames(S)),1,[])
                t = t + "," + f + "=" + mabr.analysis.ScriptWriter.literal(S.(f));
            end
        end

        function [X,warn] = exportOptions(o)
            % ExportOptions split by the function each belongs to, with the
            % defaults filled in. A field that is not an export option is left
            % out of the script and said so (warn), rather than refused: the
            % export dialog hands its options over as they are.
            X.Tables  = mabr.analysis.ScriptWriter.ExportTablesDefaults;
            if exist('mabr.analysis.Export','class') == 8
                X.Tables.Tables = mabr.analysis.Export.DefaultTables;
            end
            X.Write   = mabr.analysis.ScriptWriter.ExportWriteDefaults;
            X.RScript = true;
            warn = strings(0,1);
            for f = reshape(string(fieldnames(o)),1,[])
                v = o.(f);
                switch f
                    case {'Tables','ThresholdsAll','OnlyReviewed','IncludeExcluded', ...
                          'IncludeTestMode','WaveformWindow','Subjects','BlockSize'}
                        if f == "Tables", v = reshape(string(v),1,[]); end
                        X.Tables.(f) = v;
                    case {'Formats','Prefix','Append'}
                        X.Write.(f) = v;
                    case "RScript"
                        X.RScript = logical(v);
                    otherwise
                        warn(end+1,1) = "ExportOptions." + f + " is not an export option the " + ...
                            "script can pass on (Tables, ThresholdsAll, OnlyReviewed, " + ...
                            "IncludeExcluded, IncludeTestMode, WaveformWindow, Subjects, BlockSize, " + ...
                            "Formats, Prefix, Append, RScript); it is left out."; %#ok<AGROW>
                end
            end
            % what the manifest records: the options in force, as plain values
            G = rmfield(X.Tables,intersect(fieldnames(X.Tables),{'Subjects'}));
            for f = reshape(string(fieldnames(X.Write)),1,[]), G.(f) = X.Write.(f); end
            G.RScript = X.RScript;
            X.Given = G;
        end

        function L = exportLines(X,settingsVar,mixed,scope)
            % The export section: the tables, the files, the R script and the
            % dictionary, the manifest.
            q = @mabr.analysis.ScriptWriter.literal;
            L = strings(0,1);
            if mixed
                L = [L; comment("The sessions were analysed with different settings; the export " + ...
                    "is described by " + settingsVar + " (each session's own are in its results).")];
            end
            L(end+1,1) = "if ~isfolder(OUTFOLDER), mkdir(OUTFOLDER); end";
            L(end+1,1) = "exportTables = mabr.analysis.Export.tables(items, ...";
            tb = X.Tables;
            tb.Tables = tb.Tables(tb.Tables ~= "sweeps");      % Export.writeRaw writes those
            for f = reshape(string(fieldnames(tb)),1,[])
                L(end+1,1) = "    " + f + "=" + indentMore(q(tb.(f)),"    ") + ", ..."; %#ok<AGROW>
            end
            L(end+1,1) = "    Settings=" + settingsVar + ");";
            L(end+1,1) = "exportFiles = mabr.analysis.Export.write(exportTables,OUTFOLDER" + ...
                mabr.analysis.ScriptWriter.nameValues(X.Write) + ");";
            if any(X.Tables.Tables == "sweeps")
                L(end+1,1) = "exportFiles = [exportFiles; sweepFiles];";
            end
            if X.RScript
                L(end+1,1) = "mabr.analysis.Export.writeRScript(OUTFOLDER,exportFiles,exportTables);";
                L(end+1,1) = "mabr.analysis.Export.writeDictionary(OUTFOLDER,exportTables);";
            end
            L(end+1,1) = "mabr.analysis.Export.writeManifest(OUTFOLDER,exportTables,Files=exportFiles, ...";
            L(end+1,1) = "    Scope=" + q(scope) + ", ...";
            L(end+1,1) = "    Options=" + indentMore(q(X.Given),"    ") + ");";
            L(end+1,1) = "fprintf('Exported %d file(s) into %s\n',height(exportFiles),OUTFOLDER);";
        end

        function L = checkFunction()
            % The local function the script compares its results with.
            L = [ ...
"function same = compareWithRecorded(S,expected,label)"
"% compareWithRecorded  Say whether S reproduces the results recorded when this"
"% script was written: ""replicated exactly"", or every value that differs (by"
"% key, with isequaln). A floating-point value within 1e-6 of its size of the"
"% recorded one is rounding, not a different analysis (a session the results"
"% were recorded from may have been opened from a results file holding its"
"% averages in single precision), and is counted rather than listed. It never"
"% throws: a failed comparison must not cost the analysis above it."
"same = false;"
"diffs = strings(0,1);"
"nCompared = 0;"
"nClose = 0;"
"worst = 0;"
"try"
"    for what = reshape(string(fieldnames(expected)),1,[])"
"        E = expected.(what);"
"        T = S.(what);"
"        ids = intersect([""Key"",""Wave""],string(E.Properties.VariableNames),'stable');"
"        kE = rowKeys(E,ids);"
"        kT = strings(0,1);"
"        if all(ismember(ids,string(T.Properties.VariableNames)))"
"            kT = rowKeys(T,ids);"
"        end"
"        [~,iE,iT] = intersect(kE,kT,'stable');"
"        for k = reshape(setdiff(kE,kT,'stable'),1,[])"
"            diffs(end+1,1) = what + "" "" + k + "": recorded, but not reproduced""; %#ok<AGROW>"
"        end"
"        for k = reshape(setdiff(kT,kE,'stable'),1,[])"
"            diffs(end+1,1) = what + "" "" + k + "": reproduced, but not recorded""; %#ok<AGROW>"
"        end"
"        for v = setdiff(string(E.Properties.VariableNames),ids,'stable')"
"            if ~ismember(v,string(T.Properties.VariableNames))"
"                diffs(end+1,1) = what + "": no "" + v + "" column""; %#ok<AGROW>"
"                continue"
"            end"
"            a = E.(v)(iE,:);"
"            b = T.(v)(iT,:);"
"            for r = 1:numel(iE)"
"                nCompared = nCompared + 1;"
"                if isequaln(a(r,:),b(r,:)), continue; end"
"                d = roundingOnly(a(r,:),b(r,:));"
"                if isfinite(d)"
"                    nClose = nClose + 1;"
"                    worst = max(worst,d);"
"                else"
"                    diffs(end+1,1) = what + "" "" + kE(iE(r)) + "": "" + v + "" was "" + ..."
"                        valueText(a(r,:),b(r,:)) + "", now "" + valueText(b(r,:),a(r,:)); %#ok<AGROW>"
"                end"
"            end"
"        end"
"    end"
"catch err"
"    fprintf('%s: could not compare with the recorded results (%s).\n',label,err.message);"
"    return"
"end"
"same = isempty(diffs);"
"try"
"    if same && nClose == 0"
"        fprintf('%s: replicated exactly (%d recorded values compared).\n',label,nCompared);"
"    elseif same"
"        fprintf(['%s: replicated (%d recorded values compared; %d of them within floating-point ' ..."
"            'rounding of the recorded value, the largest a relative %.2g).\n'],label,nCompared,nClose,worst);"
"    else"
"        diffs(ismissing(diffs)) = ""(a value that cannot be shown)"";"
"        fprintf('%s: %d value(s) differ from the recorded results:\n',label,numel(diffs));"
"        fprintf('  %s\n',diffs(1:min(end,40)));"
"        if numel(diffs) > 40, fprintf('  ... and %d more\n',numel(diffs)-40); end"
"    end"
"catch err"
"    fprintf('%s: could not list the differences (%s).\n',label,err.message);"
"end"
"end"
""
"function d = roundingOnly(a,b)"
"% The largest relative difference between two floating-point values that differ by"
"% rounding alone -- the same size, NaN in the same places, every other"
"% element within 1e-6 of its own size (relative: a peak value is a few"
"% microvolts) -- or Inf."
"d = Inf;"
"if ~(isfloat(a) && isfloat(b) && isequal(size(a),size(b))), return; end"
"a = double(a);  b = double(b);"
"if ~isequal(isnan(a),isnan(b)), return; end"
"k = ~isnan(a);"
"if ~isequal(a(k & ~isfinite(a)),b(k & ~isfinite(a))), return; end"
"k = k & isfinite(a);"
"e = abs(a(k) - b(k))./max(abs(a(k)),abs(b(k)));"
"e(isnan(e)) = 0;                                  % 0 and 0"
"if all(e <= 1e-6)"
"    d = max([e(:); 0]);"
"end"
"end"
""
"function k = rowKeys(T,ids)"
"% One text key per row: Key, or Key / Wave."
"k = string(T.(ids(1)));"
"for c = ids(2:end)"
"    k = k + "" / "" + string(T.(c));"
"end"
"k(ismissing(k)) = ""<missing>"";"
"end"
""
"function t = valueText(x,other)"
"% A value as text, with the digits it takes to tell it from other."
"if isnumeric(x) || islogical(x)"
"    t = string(mat2str(double(x),6));"
"    if (isnumeric(other) || islogical(other)) && t == string(mat2str(double(other),6))"
"        t = string(mat2str(double(x),17));"
"    end"
"elseif isdatetime(x)"
"    t = strjoin(string(x),"", "");"
"else"
"    x = string(x);"
"    t = """""""" + x + """""""";"
"    t(ismissing(x)) = ""<missing>"";"
"    t = strjoin(t,"", "");"
"end"
"end"];
        end

        function c = commitText()
            % The MABR commit this was written from: the short hash, "(with
            % uncommitted changes)" when the tree is dirty, or "unknown".
            c = "unknown";
            try
                root = string(mabr.Config.root());
                [st,out] = system(sprintf('git -C "%s" rev-parse --short HEAD',root));
                out = strtrim(string(out));
                if st == 0 && ~isempty(regexp(out,'^[0-9a-f]{4,40}$','once'))
                    c = out;
                    [st,out] = system(sprintf('git -C "%s" status --porcelain --untracked-files=no',root));
                    if st == 0 && strtrim(string(out)) ~= ""
                        c = c + " (with uncommitted changes)";
                    end
                end
            catch
                c = "unknown";
            end
        end

        % =================================================================
        %  Literals, by class
        % =================================================================
        function s = lit(v)
            % Dispatch on class; an N-D array is a reshape of its column.
            if ~(istable(v) || isa(v,'mabr.analysis.Settings')) && ~ismatrix(v)
                s = "reshape(" + mabr.analysis.ScriptWriter.lit(reshape(v,[],1)) + ", " + ...
                    sizeText(size(v)) + ")";
                return
            end
            if isa(v,'mabr.analysis.Settings')
                if ~isscalar(v)
                    error('mabr:analysis:ScriptWriter:unsupported', ...
                        'literal() writes one Settings at a time.');
                end
                s = mabr.analysis.ScriptWriter.settingsLit(v);
            elseif isstring(v)
                s = mabr.analysis.ScriptWriter.stringLit(v);
            elseif ischar(v)
                s = mabr.analysis.ScriptWriter.charLit(v);
            elseif islogical(v)
                s = mabr.analysis.ScriptWriter.logicalLit(v);
            elseif isnumeric(v)
                s = mabr.analysis.ScriptWriter.numericLit(v);
            elseif isdatetime(v)
                s = mabr.analysis.ScriptWriter.datetimeLit(v);
            elseif isduration(v)
                s = "milliseconds(" + mabr.analysis.ScriptWriter.numericLit(milliseconds(v)) + ")";
            elseif iscategorical(v)
                s = mabr.analysis.ScriptWriter.categoricalLit(v);
            elseif istable(v)
                s = mabr.analysis.ScriptWriter.tableLit(v);
            elseif isstruct(v)
                s = mabr.analysis.ScriptWriter.structLit(v);
            elseif iscell(v)
                s = mabr.analysis.ScriptWriter.cellLit(v);
            elseif isa(v,'missing')
                if isscalar(v), s = "missing";
                else, s = "repmat(missing, " + sizeText(size(v)) + ")"; end
            else
                error('mabr:analysis:ScriptWriter:unsupported', ...
                    'literal() cannot write a %s.',class(v));
            end
        end

        function s = numericLit(v)
            % double, single and the integers; complex; sparse.
            cls = class(v);
            if issparse(v)
                [i,j,x] = find(v);
                s = "sparse(" + mabr.analysis.ScriptWriter.numericLit(reshape(i,1,[])) + ", " + ...
                    mabr.analysis.ScriptWriter.numericLit(reshape(j,1,[])) + ", " + ...
                    mabr.analysis.ScriptWriter.numericLit(reshape(full(x),1,[])) + ", " + ...
                    sizeText(size(v)) + ")";
                return
            end
            if ~isreal(v)
                s = "complex(" + mabr.analysis.ScriptWriter.numericLit(real(v)) + ", " + ...
                    mabr.analysis.ScriptWriter.numericLit(imag(v)) + ")";
                return
            end
            sz = size(v);
            isDouble = isa(v,'double');
            clsArg = "";
            if ~isDouble, clsArg = ", '" + cls + "'"; end
            if isempty(v)
                if isDouble && isequal(sz,[0 0]), s = "[]";
                else, s = "zeros(" + sizeText(sz) + clsArg + ")"; end
                return
            end
            % One value repeated is said once: zeros, ones, NaN, Inf, repmat.
            % (isequaln cannot tell -0 from 0, so a zero's sign decides too.)
            neg0 = isfloat(v) & v == 0 & 1./v < 0;
            if numel(v) > 1 && isequaln(v,repmat(v(1),sz)) && (all(neg0(:)) || ~any(neg0(:)))
                x = v(1);
                if all(neg0(:)),               s = "-zeros(" + sizeText(sz) + clsArg + ")";
                elseif x == 0,                 s = "zeros(" + sizeText(sz) + clsArg + ")";
                elseif x == 1,                 s = "ones(" + sizeText(sz) + clsArg + ")";
                elseif isfloat(x) && isnan(x), s = "NaN(" + sizeText(sz) + clsArg + ")";
                elseif isfloat(x) && x == Inf, s = "Inf(" + sizeText(sz) + clsArg + ")";
                else
                    s = "repmat(" + mabr.analysis.ScriptWriter.numericLit(x) + ", " + sizeText(sz) + ")";
                end
                return
            end
            if isinteger(v)
                if (isa(v,'int64') && any(v(:) > int64(flintmax) | v(:) < -int64(flintmax))) || ...
                        (isa(v,'uint64') && any(v(:) > uint64(flintmax)))
                    % Past 2^53 a decimal literal would be read as a double
                    % first; sscanf reads the 64-bit integer itself.
                    t = strings(1,numel(v));
                    for i = 1:numel(v), t(i) = string(v(i)); end      % exact for integers
                    fmt = ternary(isa(v,'int64'),"%ld","%lu");
                    s = "sscanf('" + strjoin(t," ") + "', '" + fmt + "')";
                    if ~isscalar(v), s = "reshape(" + s + ", " + sizeText(sz) + ")"; end
                    return
                end
                txt = reshape(compose("%d",double(v(:))),sz);
            else
                txt = mabr.analysis.ScriptWriter.numTexts(double(v),isa(v,'single'));
            end
            if isscalar(v)
                body = txt;
            else
                body = mabr.analysis.ScriptWriter.matrix(txt," ","[","]");
            end
            if isDouble, s = body;
            else, s = cls + "(" + body + ")"; end
        end

        function t = numTexts(x,isSingle)
            % The shortest decimal per element that parses back to it exactly
            % -- as a single when isSingle, so single(0.1) is written "0.1"
            % rather than the 17 digits of the double it widens to (9
            % significant digits always round-trip a single, 17 a double).
            if nargin < 2, isSingle = false; end
            sz = size(x);
            x = reshape(x,[],1);
            if isSingle
                digits = 6:9;
                back = @(t) double(single(str2double(t)));
            else
                digits = 15:17;
                back = @(t) str2double(t);
            end
            t = compose("%." + digits(1) + "g",x);
            for dg = digits(2:end)
                bad = ~(back(t) == x);
                if ~any(bad), break; end
                t(bad) = compose("%." + dg + "g",x(bad));
            end
            t(isnan(x)) = "NaN";
            t(x == Inf) = "Inf";
            t(x == -Inf) = "-Inf";
            t(x == 0 & 1./x < 0) = "-0";
            t = reshape(t,sz);
        end

        function s = logicalLit(v)
            sz = size(v);
            if issparse(v)
                s = "sparse(" + mabr.analysis.ScriptWriter.logicalLit(full(v)) + ")";
            elseif isempty(v)
                s = "false(" + sizeText(sz) + ")";
            elseif isscalar(v)
                s = ternary(v,"true","false");
            elseif all(v(:))
                s = "true(" + sizeText(sz) + ")";
            elseif ~any(v(:))
                s = "false(" + sizeText(sz) + ")";
            else
                t = repmat("false",sz);
                t(v) = "true";
                s = mabr.analysis.ScriptWriter.matrix(t," ","[","]");
            end
        end

        function s = charLit(v)
            sz = size(v);
            if isempty(v)
                if isequal(sz,[0 0]), s = "''";
                else, s = "char(zeros(" + sizeText(sz) + "))"; end
            elseif sz(1) == 1
                s = mabr.analysis.ScriptWriter.textExpr(v,"char");
            elseif all(mabr.analysis.ScriptWriter.printable(v(:)))
                rows = strings(sz(1),1);
                for r = 1:sz(1)
                    rows(r) = "'" + replace(string(v(r,:)),"'","''") + "'";
                end
                s = mabr.analysis.ScriptWriter.wrapJoin(rows,";","[","]");
            else
                s = "reshape(" + mabr.analysis.ScriptWriter.textExpr(reshape(v,1,[]),"char") + ...
                    ", " + sizeText(sz) + ")";
            end
        end

        function s = stringLit(v)
            sz = size(v);
            if isempty(v)
                s = "strings(" + sizeText(sz) + ")";
                return
            end
            e = strings(sz);
            for i = 1:numel(v)
                if ismissing(v(i))
                    e(i) = "string(missing)";
                else
                    e(i) = mabr.analysis.ScriptWriter.textExpr(char(v(i)),"string");
                end
            end
            if isscalar(v)
                s = e;
            elseif all(e(:) == e(1))
                s = "repmat(" + e(1) + ", " + sizeText(sz) + ")";
            else
                plus_ = contains(e," + ") & ~startsWith(e,"""");
                e(plus_) = "(" + e(plus_) + ")";
                s = mabr.analysis.ScriptWriter.matrix(e,", ","[","]");
            end
        end

        function s = textExpr(c,kind)
            % A char row as a char or a string expression: quoted runs of
            % printable characters, char(...) for every other character.
            c = reshape(c,1,[]);
            if isempty(c)
                s = ternary(kind == "char","char(zeros(1,0))","""""");
                return
            end
            ok = mabr.analysis.ScriptWriter.printable(c);
            edges = [1, find(diff(ok)) + 1, numel(c) + 1];
            parts = strings(1,numel(edges)-1);
            for k = 1:numel(parts)
                seg = c(edges(k):edges(k+1)-1);
                if ok(edges(k))
                    if kind == "char"
                        parts(k) = "'" + replace(string(seg),"'","''") + "'";
                    else
                        parts(k) = """" + replace(string(seg),"""","""""") + """";
                    end
                elseif isequal(double(seg),10)
                    parts(k) = "newline";               % (checkcode prefers it to char(10))
                elseif isscalar(seg)
                    parts(k) = "char(" + double(seg) + ")";
                else
                    parts(k) = "char([" + strjoin(string(double(seg))," ") + "])";
                end
            end
            if isscalar(parts)
                s = parts;
                if kind == "string" && ~ok(1)
                    s = "string(" + s + ")";
                end
            elseif kind == "char"
                s = mabr.analysis.ScriptWriter.wrapJoin(parts," ","[","]");
            else
                % runs alternate, so a quoted part is always among them, and
                % char + string is a string
                s = mabr.analysis.ScriptWriter.wrapJoin(parts," + ","","");
            end
        end

        function ok = printable(c)
            % Characters a quoted literal in a UTF-8 file can hold as they are:
            % not control characters, lone surrogates, line or paragraph
            % separators, the byte-order mark or noncharacters.
            d = double(c);
            ok = (d >= 32 & d < 127) | ...
                 (d >= 160 & ~(d >= 55296 & d <= 57343) & d ~= 8232 & d ~= 8233 & ...
                  d ~= 65279 & d ~= 65534 & d ~= 65535);
        end

        function s = cellLit(v)
            sz = size(v);
            if isempty(v)
                if isequal(sz,[0 0]), s = "{}";
                else, s = "cell(" + sizeText(sz) + ")"; end
                return
            end
            e = strings(sz);
            for i = 1:numel(v)
                e(i) = mabr.analysis.ScriptWriter.lit(v{i});
            end
            s = mabr.analysis.ScriptWriter.matrix(e,", ","{","}");
        end

        function s = structLit(v)
            f = reshape(string(fieldnames(v)),1,[]);
            sz = size(v);
            if isempty(f)
                if isequal(sz,[1 1]), s = "struct()";
                else, s = "repmat(struct(), " + sizeText(sz) + ")"; end
                return
            end
            args = strings(1,numel(f));
            for k = 1:numel(f)
                if isempty(v)
                    val = "cell(" + sizeText(sz) + ")";
                elseif isscalar(v)
                    x = v.(f(k));
                    val = mabr.analysis.ScriptWriter.lit(x);
                    if iscell(x), val = "{" + val + "}"; end   % struct() would expand a cell
                else
                    e = strings(sz);
                    for i = 1:numel(v)
                        e(i) = mabr.analysis.ScriptWriter.lit(v(i).(f(k)));
                    end
                    val = mabr.analysis.ScriptWriter.matrix(e,", ","{","}");
                end
                args(k) = "'" + f(k) + "', " + val;
            end
            s = mabr.analysis.ScriptWriter.callArgs("struct",args);
        end

        function s = tableLit(T)
            names = string(T.Properties.VariableNames);
            n = height(T);
            if isempty(names)
                if n == 0, s = "table()";
                else, s = "table.empty(" + n + ", 0)"; end
            else
                % table() reads any char row argument as a parameter name, so a
                % one-row table holding char text is built two rows high and
                % cut back to its first.
                charRow = false;
                if n == 1
                    for k = 1:numel(names), charRow = charRow || ischar(T.(names(k))); end
                end
                args = strings(1,numel(names));
                for k = 1:numel(names)
                    args(k) = mabr.analysis.ScriptWriter.lit(T.(names(k)));
                    if charRow, args(k) = "repmat(" + args(k) + ", 2, 1)"; end
                end
                args(end+1) = "'VariableNames', " + mabr.analysis.ScriptWriter.lit(cellstr(names));
                rn = T.Properties.RowNames;
                if ~isempty(rn)
                    args(end+1) = "'RowNames', " + mabr.analysis.ScriptWriter.lit(reshape(rn,1,[]));
                end
                s = mabr.analysis.ScriptWriter.callArgs("table",args);
                if charRow, s = "head(" + s + ", 1)"; end
            end
            % The properties isequaln also compares, where they are not a new
            % table's.
            P = T.Properties;
            props = {};
            if ~isequal(P.DimensionNames,{'Row','Variables'})
                props(end+1,:) = {'DimensionNames',P.DimensionNames};
            end
            if ~isempty(P.VariableUnits) && any(~cellfun(@isempty,P.VariableUnits))
                props(end+1,:) = {'VariableUnits',P.VariableUnits};
            end
            if ~isempty(P.VariableDescriptions) && any(~cellfun(@isempty,P.VariableDescriptions))
                props(end+1,:) = {'VariableDescriptions',P.VariableDescriptions};
            end
            if ~isempty(P.Description)
                props(end+1,:) = {'Description',P.Description};
            end
            if ~isempty(P.UserData)
                props(end+1,:) = {'UserData',P.UserData};
            end
            for k = 1:size(props,1)
                s = "setfield(" + s + ", 'Properties', '" + props{k,1} + "', " + ...
                    mabr.analysis.ScriptWriter.lit(props{k,2}) + ")";
            end
        end

        function s = datetimeLit(v)
            sz = size(v);
            tz = string(v.TimeZone);
            tzArg = "";
            if tz ~= "", tzArg = ", 'TimeZone', '" + tz + "'"; end
            if isempty(v) || all(isnat(v(:)))
                s = "NaT(" + sizeText(sz) + tzArg + ")";
                return
            end
            % ISO text, when it says the value to the last bit (a value with
            % more than nanoseconds in it is not; then the epoch form below).
            fmts = ["yyyy-MM-dd'T'HH:mm:ss","yyyy-MM-dd'T'HH:mm:ss.SSS", ...
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS"];
            for fmt = fmts
                try
                    txt = string(v,fmt);
                    txt(isnat(v)) = "NaT";
                    if tz == ""
                        back = datetime(txt,'InputFormat',fmt);
                    else
                        back = datetime(txt,'InputFormat',fmt,'TimeZone',tz);
                    end
                catch
                    continue
                end
                if isequaln(back,v)
                    s = "datetime(" + mabr.analysis.ScriptWriter.stringLit(txt) + ...
                        ", 'InputFormat', """ + fmt + """" + tzArg + ")";
                    return
                end
            end
            % The time to the millisecond, plus what is left of it (a time read
            % off the clock has a sub-millisecond part no text format holds)...
            fmt = "yyyy-MM-dd'T'HH:mm:ss.SSS";
            try
                txt = string(v,fmt);
                txt(isnat(v)) = "NaT";
                if tz == "", base = datetime(txt,'InputFormat',fmt);
                else, base = datetime(txt,'InputFormat',fmt,'TimeZone',tz); end
                rest = milliseconds(v - base);
                rest(isnat(v)) = 0;
                if isequaln(base + milliseconds(rest),v)
                    s = "datetime(" + mabr.analysis.ScriptWriter.stringLit(txt) + ...
                        ", 'InputFormat', """ + fmt + """" + tzArg + ") + milliseconds(" + ...
                        mabr.analysis.ScriptWriter.numericLit(rest) + ")";
                    return
                end
            catch
            end
            % ...or else the epoch plus milliseconds in two parts: the double
            % nearest the value and what is left over -- a datetime holds more
            % than one double's worth of precision, and both parts are exact.
            if tz == "", E = datetime(1970,1,1); else, E = datetime(1970,1,1,'TimeZone',tz); end
            hi = milliseconds(v - E);
            lo = milliseconds(v - (E + milliseconds(hi)));
            lo(isnan(hi)) = NaN;
            s = "datetime(1970,1,1" + tzArg + ") + milliseconds(" + ...
                mabr.analysis.ScriptWriter.numericLit(hi) + ")";
            if any(lo(:) ~= 0 & ~isnan(lo(:)))
                s = s + " + milliseconds(" + mabr.analysis.ScriptWriter.numericLit(lo) + ")";
            end
        end

        function s = categoricalLit(v)
            cats = reshape(string(categories(v)),1,[]);
            vals = string(v);
            vals(isundefined(v)) = missing;
            if isempty(cats)
                c = "strings(1,0)";
            else
                c = mabr.analysis.ScriptWriter.stringLit(cats);
            end
            s = "categorical(" + mabr.analysis.ScriptWriter.stringLit(vals) + ", " + c;
            if isordinal(v)
                s = s + ", 'Ordinal', true";
            elseif isprotected(v)
                s = s + ", 'Protected', true";
            end
            s = s + ")";
        end

        function s = settingsLit(st)
            % mabr.analysis.Settings(Name=Value, ...) with every property.
            S = st.toStruct();
            f = reshape(string(fieldnames(S)),1,[]);
            f(f == "SettingsVersion") = [];
            args = strings(1,numel(f));
            for k = 1:numel(f)
                args(k) = f(k) + "=" + indentMore(mabr.analysis.ScriptWriter.lit(S.(f(k))),"    ");
            end
            s = "mabr.analysis.Settings( ..." + newline + "    " + ...
                strjoin(args,", ..." + newline + "    ") + ")";
        end

        % =================================================================
        %  Layout of literal text
        % =================================================================
        function s = matrix(e,sep,opener,closer)
            % A 2-D array of element texts as [a b; c d] (or {...}), continued
            % over lines with "..." between elements -- never inside one.
            [r,c] = size(e);
            if r == 1
                one = strjoin(e,sep);
                if strlength(one) <= mabr.analysis.ScriptWriter.LineWidth && ~contains(one,newline)
                    s = opener + one + closer;
                    return
                end
            end
            pieces = strings(r*c,1);
            k = 0;
            for i = 1:r
                for j = 1:c
                    k = k + 1;
                    if j < c
                        pieces(k) = e(i,j) + strtrim(sep);
                    elseif i < r
                        pieces(k) = e(i,j) + ";";
                    else
                        pieces(k) = e(i,j);
                    end
                end
            end
            s = opener + mabr.analysis.ScriptWriter.flow(pieces) + closer;
        end

        function s = wrapJoin(parts,sep,opener,closer)
            % parts joined by sep, continued over lines when long.
            one = strjoin(parts,sep);
            if strlength(one) <= mabr.analysis.ScriptWriter.LineWidth && ~contains(one,newline)
                s = opener + one + closer;
                return
            end
            pieces = parts;
            pieces(1:end-1) = pieces(1:end-1) + strip(sep,'right');
            s = opener + mabr.analysis.ScriptWriter.flow(pieces) + closer;
        end

        function s = flow(pieces)
            % Pieces filled into lines of about LineWidth characters, space
            % separated; a full line ends in " ..." and the next is indented.
            W = mabr.analysis.ScriptWriter.LineWidth;
            lines = strings(0,1);
            cur = "";
            for k = 1:numel(pieces)
                p = pieces(k);
                last = cur;
                if contains(cur,newline), last = extractAfter(cur,strlength(cur) - ...
                        strlength(regexprep(cur,'^.*\n',''))); end
                if cur == ""
                    cur = p;
                elseif strlength(last) + strlength(p) + 1 > W || contains(p,newline)
                    lines(end+1,1) = cur + " ..."; %#ok<AGROW>
                    cur = p;
                else
                    cur = cur + " " + p;
                end
            end
            lines(end+1,1) = cur;
            s = strjoin(lines,newline + "        ");
        end

        function s = callArgs(fn,args)
            % fn(a, b, ...) on one line, or one argument a line when long.
            one = fn + "(" + strjoin(args,", ") + ")";
            if strlength(one) <= mabr.analysis.ScriptWriter.LineWidth && ~contains(one,newline)
                s = one;
            else
                s = fn + "( ..." + newline + "    " + ...
                    strjoin(indentMore(args,"    "),", ..." + newline + "    ") + ")";
            end
        end
    end
end

% =========================================================================
%  Local helpers
% =========================================================================
function v = getOr(S,name,default)
% S.(name) if S is a struct with that field (or an object with that
% property), else default.
v = default;
try
    if isstruct(S) && isscalar(S) && isfield(S,name)
        v = S.(name);
    elseif isobject(S) && isscalar(S) && isprop(S,name)
        v = S.(name);
    end
catch
    v = default;
end
end

function T = tableOr(R,name,default)
% R.(name) when it is a table, else default.
T = getOr(R,name,[]);
if ~istable(T), T = default; end
end

function v = ternary(c,a,b)
if c, v = a; else, v = b; end
end

function s = sizeText(sz)
s = strjoin(string(sz),",");
end

function L = comment(text)
% A paragraph as "% " comment lines of at most about 92 characters.
words = split(strtrim(string(text))," ");
L = strings(0,1);
cur = "%";
for w = reshape(words,1,[])
    if strlength(cur) + 1 + strlength(w) > 92 && cur ~= "%"
        L(end+1,1) = cur; %#ok<AGROW>
        cur = "%";
    end
    cur = cur + " " + w;
end
L(end+1,1) = cur;
end

function s = indentMore(s,pad)
% Indent the continuation lines of a multi-line literal by pad.
s = replace(s,newline,newline + pad);
end

function x = scalarNumber(v)
% A real scalar double, or NaN.
x = NaN;
if (isnumeric(v) || islogical(v)) && isscalar(v) && isreal(v), x = double(v); end
end

function t = subjectText(d)
if d.Subject == "", t = ""; else, t = " (" + d.Subject + ")"; end
end

function t = editSummary(D)
% "2 sweep rejections, 1 detection override, ..." over every session.
n = zeros(1,4);
for d = D
    n = n + [d.NumEdits.Rejections, d.NumEdits.Detections, d.NumEdits.Peaks, d.NumEdits.Decisions];
end
what = ["sweep rejection","detection override","peak override","threshold decision"];
parts = strings(1,4);
for k = 1:4
    parts(k) = n(k) + " " + what(k) + ternary(n(k) == 1,"","s");
end
t = strjoin(parts,", ");
end

function p = normPath(p)
% One spelling of a folder: native separators, no trailing separator.
p = string(p);
if ispc, p = replace(p,"/","\"); end
while strlength(p) > 1 && endsWith(p,filesep) && ~endsWith(p,":" + filesep)
    p = extractBefore(p,strlength(p));
end
end

function r = below(p,root)
% The folder names of p below root (a string row; strings(1,0) when p IS
% root), or [] when p is not under root.
r = [];
a = char(p); b = char(root);
if ispc, a = lower(a); b = lower(b); end
if strcmp(a,b), r = strings(1,0); return; end
if ~endsWith(b,filesep), b = [b filesep]; end
if startsWith(a,b)
    rest = extractAfter(p,numel(b));
    r = reshape(split(rest,filesep),1,[]);
    r(r == "") = [];
end
end

function root = commonFolder(folders)
% The deepest folder every one of folders is in (or is); "" if none.
root = "";
if isempty(folders), return; end
first = reshape(split(folders(1),filesep),1,[]);
n = numel(first);
for k = 2:numel(folders)
    other = reshape(split(folders(k),filesep),1,[]);
    m = min(n,numel(other));
    a = first(1:m); b = other(1:m);
    if ispc, same = lower(a) == lower(b); else, same = a == b; end
    stop = find(~same,1);
    if isempty(stop), n = m; else, n = stop - 1; end
end
if n == 0 || all(first(1:n) == ""), return; end     % nothing shared but a leading \\
root = strjoin(first(1:n),filesep);
if ispc && endsWith(root,":"), root = root + filesep; end
end
