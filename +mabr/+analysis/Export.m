classdef Export
% mabr.analysis.Export  Tidy tables of analysis results, and the files R reads them from.
%
%   Turns saved analysis results -- one results struct per session, as
%   Session.saveResults writes them and Project.exportItems collects them --
%   into tidy tables (one row per observation, one column per variable,
%   snake_case names) and writes them as CSV, XLSX, Parquet or MAT, with a
%   column dictionary, a manifest and an R script that reads them back:
%
%       items = project.exportItems(keys,catalog);          % or hand-built
%       T     = mabr.analysis.Export.tables(items);           % struct of tables
%       files = mabr.analysis.Export.write(T,folder,Formats=["csv" "parquet"]);
%       mabr.analysis.Export.writeDictionary(folder,T);      % mabr_columns.csv
%       mabr.analysis.Export.writeRScript(folder,files,T);   % mabr_import.R
%       mabr.analysis.Export.writeManifest(folder,T,Files=files);
%
%   Nothing here needs raw data except the raw tables (trial_waves, blocks,
%   block_waves, sweeps), which writeRaw writes one session at a time from a
%   Session that holds its sweeps. Everything else -- waveforms from the stored
%   means, trials from the stored per-sweep info -- comes out of the results
%   file alone, so a study of hundreds of sessions exports without reopening a
%   single .abr file.
%
%   ONE SCHEMA. schema() is the single source of truth for every column of
%   every table: its order, type, unit and meaning. The tables are ASSEMBLED
%   from it (a column the schema does not list cannot be produced, and one it
%   lists cannot be forgotten), the dictionary is written from it, and the R
%   script reads its column types from that dictionary. Columns that depend on
%   the data -- one per stimulus parameter, one per free label column -- are
%   placeholders in the schema ("<params>", "<group params>", "<free session
%   columns>", "<free subject columns>") expanded per export, and each table
%   carries what it expanded them to (Properties.UserData.Dynamic), so
%   dictionary(T) still describes exactly the columns written.
%
%   THRESHOLDS ARE CENSORED, AND INF IS NEVER WRITTEN. A series with no
%   response is not missing: its threshold lies above the loudest level
%   tested, and dropping it or writing Inf (which R reads as a number) biases
%   exactly the group x time comparison a noise-exposure study makes. Every
%   threshold row says how it is censored, in the coding brms cens() and
%   survival::Surv(type="interval2") read directly:
%       cens       threshold_db       thr_lo_db      thr_hi_db     thr_upper_db
%       none       the estimate       = threshold    = threshold   = threshold
%       left       lowest level       NA             lowest level  = threshold
%       right      highest level      highest level  NA            = threshold
%       interval   convention point   L(k*-1)        L(k*)         = thr_hi_db
%       "" (excluded / insufficient)  every value NA
%   threshold_imputed_db (right: highest + step, left: lowest - step) exists
%   for plots and sensitivity analyses only, and imputation_rule says so on
%   every row. The curated value (Decision) is what threshold_db reports; the
%   method's own estimate is threshold_fit_db.
%
%   CONVERSION RULES (write). CSV is UTF-8 with text quoted where it needs to
%   be; a numeric column holding a non-finite value is written as text with
%   "%.10g" and an EMPTY field for NaN/Inf, every other number is rounded to
%   the same ten significant digits, logicals are TRUE/FALSE, datetimes ISO
%   8601 (local time, no zone). XLSX takes only the small tables and refuses
%   one over 1,048,575 rows (sheet names <= 31 characters). Parquet writes
%   large tables (waveforms, trials, the raw tables) one file per session
%   under a folder of the table's name, which arrow::open_dataset reads as
%   one. MAT is one struct of tables, MABRExport.
%
%   UNITS. Amplitudes are volts inside the model and MICROVOLTS here (every
%   column ending _uv); amp_unit says what that unit really is for files whose
%   gain was not recorded. Latencies (and every time_ms) are milliseconds
%   re SOUND ARRIVAL when a conduction delay is set: the latency re the
%   recorded (electrical) stimulus onset minus the session's latency offset
%   = conduction_delay_ms + time_offset_ms (Peaks.reported, the one place
%   it is applied); lat_peak_raw_ms keeps the raw value. The offset is the
%   one the session's peaks were tracked with (the results' Peaks
%   LatencyOffset) unless the item's labels override it (Project
%   ConductionDelay / TimeOffset overrides). Interpeak intervals are
%   differences and do not depend on it.
%
%   LEVEL AXES. On an attenuation axis (LevelDirection "descending") no
%   response is LEFT-censored at the lowest attenuation (the model's Final
%   is -Inf there, as it is +Inf for no response on an ascending axis);
%   either infinity is encoded as its bound exactly like the other and is
%   never written. level_re_thr_db is the sensation level on either axis
%   (positive = louder than threshold).
%
%   Every table carries session_id, subject, timepoint, timepoint_order,
%   group, settings_hash and test_mode where it is per session, and every
%   condition-level table a condition_key (the model's stable key), so a join
%   in R is never a guess over parameter columns.
%
%   Nothing here prints, opens a window or touches a preference.
%
%   See also mabr.analysis.Session, mabr.analysis.SeriesThreshold,
%   mabr.analysis.Peaks, mabr.analysis.Settings
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        % Bump when a column is renamed or changes meaning (mabr_export.json).
        SchemaVersion = 1

        % Tables tables() builds by default, and the ones it builds on request.
        DefaultTables  = ["sessions","subjects","conditions","thresholds","peaks", ...
                          "peak_measures","io_slopes","waveforms","notes"]
        OptionalTables = ["trials","trial_waves","blocks","block_waves","sweeps"]

        % Tables that need the raw sweeps (writeRaw).
        RawTables = ["trial_waves","blocks","block_waves","sweeps"]

        % Tables written one Parquet file per session and held with
        % categorical text in memory (millions of rows in a study).
        LargeTables = ["waveforms","trials","trial_waves","blocks","block_waves","sweeps"]

        % Tables an Excel workbook may hold, and the most rows a sheet holds
        % below its header.
        XLSXTables  = ["sessions","subjects","conditions","thresholds","peaks", ...
                       "peak_measures","io_slopes","notes"]
        XLSXMaxRows = 1048575

        % Formats write() knows.
        Formats = ["csv","xlsx","parquet","mat"]

        % Schema placeholders expanded per export.
        Placeholders = ["<params>","<group params>","<free session columns>","<free subject columns>"]
    end

    methods (Static)
        % =================================================================
        %  The schema
        % =================================================================
        function S = schema()
            % Every column of every table: the single source of truth.
            %
            %   S  (returned) table Table, Column, Type, Unit, Description --
            %      one row per column in table order and column order. Type is
            %      what the files hold: string, double, integer, logical, date
            %      (ISO yyyy-MM-dd) or datetime (ISO yyyy-MM-ddTHH:mm:ss, local
            %      time). A Column in angle brackets is a placeholder expanded
            %      per export (one column per stimulus parameter or free label).
            L = schemaList();
            S = table(L.Table,L.Column,L.Type,L.Unit,L.Description, ...
                'VariableNames',{'Table','Column','Type','Unit','Description'});
        end

        function D = dictionary(T)
            % The dictionary rows of exactly the columns a set of tables holds.
            %
            %   T  struct of tables (tables()'s output, or any subset of it)
            %   D  (returned) table Table, Column, Type, Unit, Description --
            %      one row per column actually present, in table order; a
            %      placeholder's columns described one by one. A column the
            %      schema cannot describe gets Type from its class and the
            %      Description "(not in the schema)".
            arguments
                T (1,1) struct
            end
            tb = strings(0,1); cl = tb; ty = tb; un = tb; de = tb;
            for name = tableNames(T)
                t = T.(name);
                spec = specFor(name);
                dyn = tableDynamic(t);
                for c = string(t.Properties.VariableNames)
                    k = find(colsOf(spec) == c & ~phOf(spec),1);
                    j = find(colsOf(dyn) == c,1);
                    if ~isempty(k)
                        r = {spec(k).Type, spec(k).Unit, spec(k).Description};
                    elseif ~isempty(j)
                        r = {dyn(j).Type, dyn(j).Unit, dyn(j).Description};
                    else
                        r = {classType(t.(c)), "", "(not in the schema)"};
                    end
                    tb(end+1,1) = name; cl(end+1,1) = c; %#ok<AGROW>
                    ty(end+1,1) = r{1}; un(end+1,1) = r{2}; de(end+1,1) = r{3}; %#ok<AGROW>
                end
            end
            D = table(tb,cl,ty,un,de,'VariableNames',{'Table','Column','Type','Unit','Description'});
        end

        function n = columnName(param)
            % The export column of a stimulus parameter: snake_case + unit.
            %
            %   Frequency -> frequency_khz, Level -> level_db (the two units the
            %   toolbox fixes by name: mabr.stim.StimulusSet.paramUnit),
            %   Stim_Polarity -> stim_polarity, SoundLevel -> sound_level,
            %   ISIMode -> isi_mode. A name starting with a digit gets an "x".
            %
            %   param  text (char, string array or cellstr)
            %   n      (returned) string, same size as param
            arguments
                param {mustBeText}
            end
            p = string(param);
            n = strings(size(p));
            for k = 1:numel(p)
                s = snake(p(k));
                u = lower(paramUnitOf(p(k)));
                if u ~= "" && ~endsWith(s,"_" + u)
                    s = s + "_" + u;
                end
                n(k) = s;
            end
        end

        % =================================================================
        %  Tables
        % =================================================================
        function T = tables(items,opts)
            % Tidy tables from analysis results.
            %
            %   items  struct array (or cell array of structs), one per session
            %          or pool, as Project.exportItems builds them:
            %            Key      session key (session_id)
            %            Results  results struct (v1 or v2), a results file
            %                     path, or a mabr.analysis.Session
            %            Labels   struct Subject, SubjectRaw, Timepoint,
            %                     TimepointOrder, Group, InStudy, TestMode,
            %                     DaysFromReference, TimeOffset (ms),
            %                     ConductionDelay (ms; the Project's
            %                     ConductionDelayOverride, NaN = none),
            %                     Comment, Free (struct of free session
            %                     columns), UsedInStudy (SeriesKey, Used); any
            %                     field may be missing. A finite TimeOffset or
            %                     ConductionDelay overrides the latency offset
            %                     the results stored (Peaks LatencyOffset).
            %            Notes    Catalog.notes table (or [])
            %            Session  [] or a Session holding sweeps (raw tables)
            %   opts.Tables           tables to build (DefaultTables; also
            %                         "trials" and the raw ones, which need a
            %                         Session -- "sweeps" only writeRaw writes)
            %   opts.ThresholdsAll    add a row per built-in method per series,
            %                         from the stored per-condition columns
            %                         (false)
            %   opts.OnlyReviewed     series tables only for reviewed series
            %                         (false)
            %   opts.IncludeExcluded  sessions/subjects not in the study (false)
            %   opts.IncludeTestMode  Test Mode sessions (false)
            %   opts.WaveformWindow   ms of each mean written ([-2 10])
            %   opts.Settings         Settings (object or struct) for results
            %                         that carry none ([])
            %   opts.Subjects         Project.Subjects table ([] = from labels)
            %   opts.BlockSize        sweeps per block of the raw tables (64)
            %   opts.ProgressFcn      [] or @(message,count,total)
            %   T  (returned) struct, one table per requested name
            arguments
                items = struct([])
                opts.Tables (1,:) string = mabr.analysis.Export.DefaultTables
                opts.ThresholdsAll (1,1) logical = false
                opts.OnlyReviewed (1,1) logical = false
                opts.IncludeExcluded (1,1) logical = false
                opts.IncludeTestMode (1,1) logical = false
                opts.WaveformWindow (1,2) double = [-2 10]
                opts.Settings = []
                opts.Subjects = []
                opts.BlockSize (1,1) double {mustBeInteger,mustBePositive} = 64
                opts.ProgressFcn = []
            end
            want = checkTables(opts.Tables);
            list = itemList(items);
            nI   = numel(list);
            parts = struct();
            for w = want, parts.(w) = {}; end
            kept = {};
            settingsSeen = emptySettingsList();
            for i = 1:nI
                report(opts.ProgressFcn,"Export: reading results",i-1,nI);
                it = prepareItem(list{i},opts);
                if ~keepItem(it,opts), continue; end
                kept{end+1} = it; %#ok<AGROW>
                settingsSeen = addSettings(settingsSeen,it.Ctx.SettingsHash,it.Ctx.Settings);
                P = itemTables(it,want,opts);
                for w = string(fieldnames(P)).'
                    parts.(w){end+1} = P.(w);
                end
            end
            report(opts.ProgressFcn,"Export: reading results",nI,nI);

            T = struct();
            for w = want
                if w == "subjects"
                    t = subjectsTable(kept,opts);
                else
                    t = stackParts(w,parts.(w));
                end
                if w == "sweeps"
                    t.Properties.UserData.Note = "sweeps are written by Export.writeRaw, not built in memory";
                elseif ismember(w,mabr.analysis.Export.RawTables) && ...
                        ~any(cellfun(@(x) ~isempty(x.Session),kept))
                    t.Properties.UserData.Note = "needs a Session with sweeps (Export.writeRaw)";
                end
                t.Properties.UserData.Settings = settingsSeen;
                T.(w) = t;
            end
        end

        function T = stack(tables,name)
            % Union of tables of one kind: columns in schema order, missing
            % values filled (NaN, "", false, NaT, undefined).
            %
            %   tables  a table or a cell array of tables of ONE export table
            %           (each knows its kind in Properties.UserData)
            %   name    the export table name, when the tables do not carry
            %           it ("" = read it from the first table)
            %   T       (returned) one table: the schema's fixed columns in
            %           order, each placeholder's columns in first-seen order,
            %           anything unknown at the end
            arguments
                tables
                name (1,1) string = ""
            end
            if istable(tables), tables = {tables}; end
            if ~iscell(tables)
                error('mabr:analysis:Export:badInput','stack takes a table or a cell array of tables.');
            end
            tables = tables(cellfun(@istable,tables));
            if name == ""
                for k = 1:numel(tables)
                    ud = tables{k}.Properties.UserData;
                    if isstruct(ud) && isfield(ud,'ExportTable')
                        name = string(ud.ExportTable);
                        break
                    end
                end
            end
            if name == ""
                error('mabr:analysis:Export:badInput', ...
                    'stack: the tables do not say which export table they are; pass the name.');
            end
            T = stackParts(name,tables);
        end

        % =================================================================
        %  Writing
        % =================================================================
        function files = write(T,folder,opts)
            % Write tables as CSV, XLSX, Parquet and/or MAT.
            %
            %   T            struct of tables (tables())
            %   folder       destination folder (created)
            %   opts.Formats string array applied to every table, or a struct
            %                table -> formats (a field "default" for the rest;
            %                else csv); default "csv"
            %   opts.Prefix  file name prefix ("mabr_")
            %   opts.Append  add to files already there (CSV rows appended,
            %                columns reconciled; Parquet per-session files
            %                added; MAT and single Parquet files stacked)
            %   opts.ProgressFcn  [] or @(message,count,total)
            %   files  (returned) table Table, Format, File, Rows, Note -- one
            %          row per table and format; File "" when a table was not
            %          written, Note saying why
            arguments
                T (1,1) struct
                folder {mustBeTextScalar}
                opts.Formats = "csv"
                opts.Prefix (1,1) string = "mabr_"
                opts.Append (1,1) logical = false
                opts.ProgressFcn = []
            end
            folder = string(folder);
            ensureFolder(folder);
            names = tableNames(T);
            files = emptyFiles();
            matT  = struct();
            xlsx  = struct('File',fullfile(folder,opts.Prefix + "tables.xlsx"),'Started',false,'Sheets',strings(0,1));
            for k = 1:numel(names)
                name = names(k);
                t = T.(name);
                report(opts.ProgressFcn,"Export: writing " + name,k-1,numel(names));
                for f = formatsFor(name,opts.Formats)
                    switch f
                        case "csv"
                            r = writeCsvTable(t,name,fullfile(folder,opts.Prefix + name + ".csv"),opts.Append);
                        case "xlsx"
                            [r,xlsx] = writeXlsxTable(t,name,xlsx,opts);
                        case "parquet"
                            r = writeParquetTable(t,name,folder,opts);
                        case "mat"
                            matT.(name) = t;
                            continue
                    end
                    files = [files; r]; %#ok<AGROW>
                end
            end
            if ~isempty(fieldnames(matT))
                files = [files; writeMat(matT,fullfile(folder,opts.Prefix + "export.mat"),opts.Append)];
            end
            report(opts.ProgressFcn,"Export: writing",numel(names),numel(names));
        end

        function files = writeRaw(session,labels,folder,opts)
            % Write one session's raw tables (trial_waves, blocks, block_waves,
            % sweeps), appending to what earlier sessions wrote.
            %
            %   session  a mabr.analysis.Session holding sweeps (HasSweeps), or
            %            a struct with the same fields (Key, Time, Conditions
            %            with Key/Sweeps/Rejected/Polarity/SweepOrder/Excess,
            %            Peaks, KeyParams, ResponseWindow, Settings, ...)
            %   labels   the session's Labels struct (tables()'s items), or a
            %            whole item (Key + Labels); [] for none
            %   folder   export folder
            %   opts.Tables     raw tables to write (all four)
            %   opts.Formats    as write(); default "parquet". sweeps takes
            %                   "parquet" (long: one row per sample) or "mat"
            %                   (<session>_sweeps.mat, one single [nT x n]
            %                   matrix per condition); CSV is REFUSED for sweeps
            %                   (a Note, nothing written) -- a session is
            %                   millions of rows
            %   opts.Prefix     file name prefix ("mabr_")
            %   opts.BlockSize  sweeps per block (64, polarity balanced)
            %   opts.SessionId  session_id ("" = the session's Key)
            %   opts.ProgressFcn  [] or @(message,count,total)
            %   files  (returned) table Table, Format, File, Rows, Note
            arguments
                session
                labels = []
                folder {mustBeTextScalar} = ""
                opts.Tables (1,:) string = mabr.analysis.Export.RawTables
                opts.Formats = "parquet"
                opts.Prefix (1,1) string = "mabr_"
                opts.BlockSize (1,1) double {mustBeInteger,mustBePositive} = 64
                opts.SessionId (1,1) string = ""
                opts.ProgressFcn = []
            end
            want = opts.Tables(ismember(opts.Tables,mabr.analysis.Export.RawTables));
            bad  = opts.Tables(~ismember(opts.Tables,mabr.analysis.Export.RawTables));
            if ~isempty(bad)
                error('mabr:analysis:Export:unknownTable', ...
                    'writeRaw writes only %s; not %s.',strjoin(mabr.analysis.Export.RawTables,', '),strjoin(bad,', '));
            end
            folder = string(folder);
            if folder == "", folder = string(pwd); end
            ensureFolder(folder);
            if isobject(session) && isprop(session,'HasSweeps') && ~session.HasSweeps
                error('mabr:analysis:Export:noRaw', ...
                    'writeRaw needs a Session holding its sweeps; call loadRaw() first.');
            end
            ctx = rawContext(session,labels,opts.SessionId);
            report(opts.ProgressFcn,"Export: raw tables of " + ctx.Id,0,1);
            files = emptyFiles();

            tw = want(want ~= "sweeps");
            if ~isempty(tw)
                R = rawTables(session,ctx,tw,opts.BlockSize);
                S = struct();
                for w = tw, S.(w) = R.(w); end
                files = [files; mabr.analysis.Export.write(S,folder,Formats=opts.Formats, ...
                    Prefix=opts.Prefix,Append=true)];
            end
            if ismember("sweeps",want)
                files = [files; writeSweeps(session,ctx,folder,opts)];
            end
            report(opts.ProgressFcn,"Export: raw tables of " + ctx.Id,1,1);
        end

        function f = writeRScript(folder,files,T)
            % Write mabr_import.R: read every exported table, and the models.
            %
            %   folder  the export folder
            %   files   write()'s files table ([] = assume <prefix>name.csv for
            %           every table of T, prefix "mabr_")
            %   T       the tables (which exist, and whether blocks were
            %           exported)
            %   f       (returned) the script's path
            %
            % The script reads each CSV with readr::read_csv(..., na = c("",
            % "NA", "NaN")) and the column types of mabr_columns.csv (Parquet
            % with arrow), orders the timepoint factor by timepoint_order, and
            % carries -- behind RUN_MODELS, since brms takes minutes -- the
            % censored brms threshold model, the survival interval2
            % alternative, the imputed-value lmer as a COMMENTED sensitivity
            % analysis, the log-amplitude and latency mixed models restricted
            % to detectable peaks at least 10 dB above threshold with rn_uv and
            % n_used as covariates, a glmmTMB Gamma alternative, Holm-adjusted
            % emmeans contrasts by frequency, and a block drift model when
            % blocks were exported.
            arguments
                folder {mustBeTextScalar}
                files = []
                T (1,1) struct = struct()
            end
            folder = string(folder);
            ensureFolder(folder);
            paths = rPaths(folder,files,T);
            hasBlocks = isKey(paths,'blocks');
            txt = rScriptText(folder,paths,hasBlocks);
            f = fullfile(folder,"mabr_import.R");
            writeText(f,txt);
        end

        function f = writeDictionary(folder,T)
            % Write mabr_columns.csv: one row per column written.
            %
            %   folder  the export folder
            %   T       the tables written
            %   f       (returned) the file's path; columns table, column,
            %           type, unit, description (lower case for R)
            arguments
                folder {mustBeTextScalar}
                T (1,1) struct
            end
            folder = string(folder);
            ensureFolder(folder);
            D = mabr.analysis.Export.dictionary(T);
            D.Properties.VariableNames = lower(D.Properties.VariableNames);
            f = fullfile(folder,"mabr_columns.csv");
            writeCsvRaw(D,f,false);
        end

        function f = writeManifest(folder,T,opts)
            % Write mabr_export.json (what was exported, by what) and
            % mabr_settings.json (every settings set, by its hash).
            %
            %   folder        the export folder
            %   T             the tables (row counts; settings they carry)
            %   opts.Files    write()'s files table ([] = none listed)
            %   opts.Scope    text: what was exported (e.g. "In study")
            %   opts.Options  struct of the export options (recorded as given)
            %   opts.Settings extra settings to record (Settings object,
            %                 struct, or a cell array of them)
            %   f             (returned) path of mabr_export.json
            %
            % The manifest: {SchemaVersion: 1, Created, MABR: {Version, Commit
            % (git rev-parse --short HEAD, "unknown" when that fails)},
            % MATLAB, SettingsHash: [...], Scope, Options, Tables: [{name,
            % files, rows}]}. Non-finite numbers are written as the strings
            % "Inf", "-Inf" and "NaN" (JSON has none of its own).
            arguments
                folder {mustBeTextScalar}
                T (1,1) struct
                opts.Files = []
                opts.Scope (1,1) string = ""
                opts.Options = struct()
                opts.Settings = []
            end
            folder = string(folder);
            ensureFolder(folder);
            names = tableNames(T);
            sets = emptySettingsList();
            for name = names
                ud = T.(name).Properties.UserData;
                if isstruct(ud) && isfield(ud,'Settings') && ~isempty(ud.Settings)
                    for s = reshape(ud.Settings,1,[])
                        sets = addSettings(sets,s.Hash,s.Settings);
                    end
                end
            end
            extra = opts.Settings;
            if ~iscell(extra), extra = {extra}; end
            for k = 1:numel(extra)
                [h,st] = settingsHashOf(extra{k});
                sets = addSettings(sets,h,st);
            end

            tabs = struct('name',{},'files',{},'rows',{});
            F = opts.Files;
            for name = names
                fl = {};
                if istable(F) && height(F) > 0 && ismember('Table',F.Properties.VariableNames)
                    r = F(string(F.Table) == name & string(F.File) ~= "",:);
                    fl = cellstr(relativeTo(folder,unique(string(r.File),'stable')));
                end
                tabs(end+1) = struct('name',char(name),'files',{fl},'rows',height(T.(name))); %#ok<AGROW>
            end
            M = struct();
            M.SchemaVersion = mabr.analysis.Export.SchemaVersion;
            M.Created = mabr.analysis.Stats.isoTime(datetime('now'));
            M.MABR = struct('Version',mabrVersion(),'Commit',gitCommit());
            M.MATLAB = version;
            if isempty(sets), M.SettingsHash = {}; else, M.SettingsHash = cellstr([sets.Hash]); end
            M.Scope = char(opts.Scope);
            M.Options = jsonSafe(opts.Options);
            M.Tables = tabs;
            f = fullfile(folder,"mabr_export.json");
            writeText(f,jsonencode(M,'PrettyPrint',true));

            if ~isempty(sets)
                mp = containers.Map('KeyType','char','ValueType','any');
                for s = sets
                    mp(char(s.Hash)) = jsonSafe(s.Settings);
                end
                js = jsonencode(mp,'PrettyPrint',true);
            else
                js = '{}';
            end
            writeText(fullfile(folder,"mabr_settings.json"),js);
        end

        % =================================================================
        %  Estimate
        % =================================================================
        function E = estimate(items,opts)
            % Rows and file sizes each table would have, without building it.
            %
            %   items  as tables()
            %   opts   as tables() (Tables defaults to every table)
            %   E  (returned) table Table, Rows, CSVBytes, ParquetBytes,
            %      XLSXAllowed (an XLSX table with <= 1,048,575 rows),
            %      NeedsRaw (the table needs a Session with sweeps). Rows are
            %      exact for the stored tables and upper bounds for the derived
            %      ones; the byte counts are estimates.
            arguments
                items = struct([])
                opts.Tables (1,:) string = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables]
                opts.ThresholdsAll (1,1) logical = false
                opts.OnlyReviewed (1,1) logical = false
                opts.IncludeExcluded (1,1) logical = false
                opts.IncludeTestMode (1,1) logical = false
                opts.WaveformWindow (1,2) double = [-2 10]
                opts.Settings = []
                opts.Subjects = []
                opts.BlockSize (1,1) double {mustBeInteger,mustBePositive} = 64
                opts.ProgressFcn = []
            end
            want = checkTables(opts.Tables);
            list = itemList(items);
            rows = zeros(1,numel(want));
            subj = strings(0,1);
            nPar = 0;
            for i = 1:numel(list)
                it = prepareItem(list{i},opts);
                if ~keepItem(it,opts), continue; end
                subj(end+1,1) = it.Ctx.Subject; %#ok<AGROW>
                nPar = max(nPar,numel(it.Ctx.Params));
                for k = 1:numel(want)
                    rows(k) = rows(k) + estimateRows(want(k),it,opts);
                end
            end
            k = find(want == "subjects",1);
            if ~isempty(k), rows(k) = numel(unique(subj)); end
            Tbl  = want(:);
            Rows = rows(:);
            CSVBytes = zeros(numel(want),1);
            ParquetBytes = CSVBytes;
            for k = 1:numel(want)
                [c,p] = bytesPerRow(want(k),nPar);
                CSVBytes(k)     = round(Rows(k)*c + 200);
                ParquetBytes(k) = round(Rows(k)*p + 2000);
            end
            XLSXAllowed = ismember(Tbl,mabr.analysis.Export.XLSXTables) & Rows <= mabr.analysis.Export.XLSXMaxRows;
            NeedsRaw = ismember(Tbl,mabr.analysis.Export.RawTables);
            E = table(Tbl,Rows,CSVBytes,ParquetBytes,XLSXAllowed,NeedsRaw, ...
                'VariableNames',{'Table','Rows','CSVBytes','ParquetBytes','XLSXAllowed','NeedsRaw'});
        end
    end
end

% =========================================================================
%  The schema
% =========================================================================
function L = schemaList()
% Every table's columns, in order, with type, unit and description: struct
% of string columns Table, Column, Type, Unit, Description.
persistent cache
if ~isempty(cache), L = cache; return; end
order = tableOrders();
spec  = columnSpecs();
tb = strings(0,1); cl = tb; ty = tb; un = tb; de = tb;
for name = string(fieldnames(order)).'
    for c = order.(name)
        key = char(name + "." + c);
        if isKey(spec,key), s = spec(key);
        elseif isKey(spec,char(c)), s = spec(char(c));
        else
            error('mabr:analysis:Export:schema','No description for %s.%s.',name,c);
        end
        tb(end+1,1) = name; cl(end+1,1) = c; %#ok<AGROW>
        ty(end+1,1) = s(1); un(end+1,1) = s(2); de(end+1,1) = s(3); %#ok<AGROW>
    end
end
L = struct('Table',tb,'Column',cl,'Type',ty,'Unit',un,'Description',de);
cache = L;
end

function O = tableOrders()
% The column order of every table (placeholders in angle brackets).
ID   = ["session_id","subject","timepoint","timepoint_order","group"];
TAIL = ["settings_hash","test_mode"];
O = struct();
O.sessions = ["session_id","subject","subject_raw","timepoint","timepoint_order","group", ...
    "in_study","test_mode","date","start_time","days_from_reference","n_files","n_conditions", ...
    "n_sweeps","stimuli","acq_modes","processing","units","level_unit","settings_hash", ...
    "analyzed_at","data_fingerprint","comment","<free session columns>"];
O.subjects = ["subject","group","in_study","comment","<free subject columns>"];
O.conditions = [ID,"stimulus","acq_mode","<params>","condition_key","series_key","level_ref", ...
    "calibration_time","n_total","n_rejected","n_rejected_rig","n_rejected_auto", ...
    "n_rejected_manual","n_used","n_pos","n_neg","processing","extent_ms","hp_6db_hz", ...
    "lp_6db_hz","pad_mode","response_window_ms","perm_p","detected","detected_override", ...
    "perm_strength","rn_uv","rn_pm_uv","response_rms_uv","baseline_rms_uv","power_f", ...
    "power_p","snr_db","snr_corr_db","fsp","fsp_df1","fsp_df2","fsp_p","split_r", ...
    "split_r_sd","split_r_p025","split_r_p975","split_n_per_half","split_avg_mode", ...
    "xcorr_up","xcorr_lag_ms","xcorr_up_lag0","amp_unit","input_full_scale","flags",TAIL];
O.thresholds = [ID,"stimulus","acq_mode","<group params>","series_key","level_param", ...
    "method","metric","model","criterion","criterion_unit","threshold_db","cens","thr_lo_db", ...
    "thr_hi_db","thr_upper_db","convention","threshold_fit_db","fit_status","ci_lo_db", ...
    "ci_hi_db","ci_method","threshold_imputed_db","imputation_rule","level_step_db", ...
    "n_levels","n_levels_used","n_detected","n_used_min","rn_uv_at_threshold","decision", ...
    "reviewed","reviewed_by","reviewed_at","note","flags","used_in_study","is_primary", ...
    "level_ref",TAIL];
O.peaks = [ID,"stimulus","acq_mode","<params>","condition_key","series_key", ...
    "level_re_thr_db","wave","state","detectable","below_threshold","edge_affected", ...
    "lat_peak_ms","lat_trough_ms","lat_peak_raw_ms","conduction_delay_ms","time_offset_ms", ...
    "amp_pt_uv","amp_bp_uv","amp_bt_uv","amp_p0_uv","prominence_uv","prominence_rn", ...
    "latency_method","lat_se_ms","lat_ci_lo_ms","lat_ci_hi_ms","amp_pt_se_uv", ...
    "amp_pt_ci_lo_uv","amp_pt_ci_hi_uv","boot_unstable","processing","amp_unit", ...
    "used_in_study",TAIL];
O.peak_measures = [ID,"stimulus","acq_mode","<params>","condition_key","measure","value", ...
    "unit","conduction_delay_ms","time_offset_ms","used_in_study",TAIL];
O.io_slopes = [ID,"stimulus","acq_mode","<group params>","series_key","wave","quantity", ...
    "slope","unit","intercept","n_levels","level_min","level_max","used_in_study",TAIL];
O.waveforms = [ID,"stimulus","acq_mode","<params>","condition_key","polarity","time_ms", ...
    "mean_uv","sem_uv","n",TAIL];
O.notes = [ID,"time","run","sweep","stamp","text","source","scope",TAIL];
O.trials = [ID,"stimulus","acq_mode","<params>","condition_key","sweep_order","file_id", ...
    "sweep_in_file","time_s","t_session_s","polarity","rejected","reject_reason","excess", ...
    "rms_uv","p2p_uv","maxabs_uv","baseline_rms_uv","template_amp","template_r",TAIL];
O.trial_waves = [ID,"stimulus","acq_mode","<params>","condition_key","sweep_order","wave", ...
    "lat_peak_ms","lat_peak_raw_ms","conduction_delay_ms","time_offset_ms","p_uv","pn_uv","proj",TAIL];
O.blocks = [ID,"stimulus","acq_mode","<params>","condition_key","block","n","first_order", ...
    "last_order","rn_uv","response_rms_uv",TAIL];
O.block_waves = [ID,"stimulus","acq_mode","<params>","condition_key","block","wave", ...
    "lat_peak_ms","lat_peak_raw_ms","conduction_delay_ms","time_offset_ms","amp_pt_uv",TAIL];
O.sweeps = [ID,"stimulus","acq_mode","<params>","condition_key","sweep_order","polarity", ...
    "rejected","excess","time_ms","value_uv",TAIL];
end

function M = columnSpecs()
% Type, unit and description of every column, by name; "table.column"
% entries override for a table where a name means something else.
M = containers.Map('KeyType','char','ValueType','any');
M('session_id') = ["string" "" "Session key: the session folder relative to the study root (/ separated), or pool:<hash> for a pool of folders. Joins every table."];
M('subject') = ["string" "" "Subject, canonical SUBJ-ID-<token> (one spelling per animal)."];
M('subject_raw') = ["string" "" "Subject as spelled in the file and folder names."];
M('timepoint') = ["string" "" "Visit label (Project Timepoint), e.g. Baseline."];
M('timepoint_order') = ["integer" "" "Position of the timepoint in the study's timepoint order (1 = first); the R script orders the timepoint factor by it."];
M('group') = ["string" "" "Subject group (Project Group, a subject attribute)."];
M('in_study') = ["logical" "" "TRUE when the session is part of the study (Project InStudy)."];
M('subjects.in_study') = ["logical" "" "TRUE when the subject is part of the study."];
M('test_mode') = ["logical" "" "TRUE for Test Mode data: the samples are the stimulus looped back, not a subject."];
M('date') = ["date" "" "Day of the session (ISO 8601 yyyy-MM-dd, local)."];
M('start_time') = ["datetime" "" "Start of the session's first file (ISO 8601 yyyy-MM-ddTHH:mm:ss, local time, no zone)."];
M('days_from_reference') = ["double" "days" "Days from the subject's reference timepoint to this session."];
M('n_files') = ["integer" "" ".abr files included in the analysis."];
M('n_conditions') = ["integer" "" "Stimulus conditions."];
M('n_sweeps') = ["integer" "" "Sweeps recorded over all conditions, rejected ones included."];
M('stimuli') = ["string" "" "Stimulus classes present, comma separated."];
M('acq_modes') = ["string" "" "Acquisition modes present: conventional (one condition per run), interleaved (intermixed runs), pooled."];
M('sessions.processing') = ["string" "" "Processing paths used: continuous (FIR on the whole trace) and/or windowed (each sweep filtered on its own)."];
M('units') = ["string" "" "Amplitude unit of the files: V (volts at the electrodes), V-unscaled (input full scale assumed 1), converter, or mixed."];
M('level_unit') = ["string" "" "Level reference of the files: dB SPL (calibrated), dB re max, dB, or mixed."];
M('settings_hash') = ["string" "" "8-hex-digit hash of the analysis settings behind these numbers (mabr_settings.json holds each set)."];
M('analyzed_at') = ["datetime" "" "When the session was analysed (ISO 8601, local)."];
M('data_fingerprint') = ["string" "" "Hash of the session's files (names, sizes, modification times) and exclusions when it was analysed."];
M('comment') = ["string" "" "Session comment (Project)."];
M('subjects.comment') = ["string" "" "Subject comment (Project)."];
M('<free session columns>') = ["any" "" "Free session label columns defined in the Project, snake_case."];
M('<free subject columns>') = ["any" "" "Free subject label columns defined in the Project, snake_case."];
M('stimulus') = ["string" "" "Stimulus class (Tone, ClickTrain, ...); empty when the files name none."];
M('acq_mode') = ["string" "" "Acquisition mode: conventional, interleaved, or pooled (both analysed as one)."];
M('<params>') = ["double" "" "One column per stimulus parameter, named by Export.columnName: frequency_khz (kHz), level_db (dB, reference in level_ref); others as stored."];
M('<group params>') = ["double" "" "The series' grouping parameters (stimulus parameters other than the level), named as in conditions."];
M('condition_key') = ["string" "" "Condition key, Name=Value pairs joined by | (stable across re-analyses); joins conditions, peaks, waveforms and trials."];
M('series_key') = ["string" "" "Series key: the condition key without the level parameter; joins thresholds, peaks and io_slopes."];
M('level_ref') = ["string" "" "What the level's dB is re: dB SPL (calibrated), dB re max (relative levels of an uncalibrated bank) or dB."];
M('calibration_time') = ["string" "" "When the stimulus calibration was measured, as recorded in the files (empty when not recorded)."];
M('n_total') = ["integer" "" "Sweeps recorded."];
M('n_rejected') = ["integer" "" "Sweeps rejected: by the rig, the artifact rule or by hand."];
M('n_rejected_rig') = ["integer" "" "Sweeps rejected by the acquisition rig's artifact flag."];
M('n_rejected_auto') = ["integer" "" "Sweeps rejected by the offline artifact rule."];
M('n_rejected_manual') = ["integer" "" "Sweeps rejected by hand."];
M('n_used') = ["integer" "" "Clean sweeps used: not rejected and not beyond the per-condition cap."];
M('n_pos') = ["integer" "" "Clean sweeps of positive stimulus polarity."];
M('n_neg') = ["integer" "" "Clean sweeps of negative stimulus polarity."];
M('processing') = ["string" "" "continuous (FIR on the whole trace) or windowed (each sweep filtered on its own)."];
M('extent_ms') = ["string" "ms" "Time the condition's sweeps hold, start-end ms re onset (a windowed condition can hold less than the window)."];
M('hp_6db_hz') = ["double" "Hz" "High-pass -6 dB corner of the filter as applied (zero phase); NA when off or unknown."];
M('lp_6db_hz') = ["double" "Hz" "Low-pass -6 dB corner of the filter as applied; NA when off or unknown."];
M('pad_mode') = ["string" "" "Padding of a windowed condition's filter: reflect or zeroleft; empty for continuous."];
M('response_window_ms') = ["string" "ms" "Response window, start-end ms re onset (detection, measures, artifact features)."];
M('perm_p') = ["double" "p" "Permutation-test p-value of a response (sign flips, response window)."];
M('detected') = ["logical" "" "Response detected (p < alpha, after any human override); FALSE when detection was not run."];
M('detected_override') = ["double" "" "Human detection override: 1 = response, 0 = no response, NA = automatic."];
M('perm_strength') = ["double" "statistic" "Permutation test statistic (TFCE, cluster mass or t-max; its scale depends on the method and N)."];
M('rn_uv') = ["double" "uV" "Residual noise: RMS over the response window of the SEM of the polarity-balanced mean."];
M('rn_pm_uv') = ["double" "uV" "Residual noise from the +/- reference (balanced sign-flipped average)."];
M('response_rms_uv') = ["double" "uV" "RMS over the response window of the polarity-balanced mean (its mean removed)."];
M('baseline_rms_uv') = ["double" "uV" "RMS of the mean over the baseline window; NA when the baseline overlaps the previous response."];
M('power_f') = ["double" "" "Response power over residual noise power (about 1 without a response)."];
M('power_p') = ["double" "p" "Sign-flip permutation p-value of power_f."];
M('snr_db') = ["double" "dB" "10 log10 power_f (about 0 dB without a response)."];
M('snr_corr_db') = ["double" "dB" "10 log10(power_f - 1), the bias-corrected SNR; NA when power_f <= 1."];
M('fsp') = ["double" "" "Fsp: multi-point F with estimated degrees of freedom."];
M('fsp_df1') = ["double" "" "Estimated numerator degrees of freedom of fsp."];
M('fsp_df2') = ["double" "" "Denominator degrees of freedom of fsp."];
M('fsp_p') = ["double" "p" "p-value of fsp."];
M('split_r') = ["double" "r" "Split-half correlation, mean over random partitions."];
M('split_r_sd') = ["double" "r" "SD of the split-half correlation over partitions."];
M('split_r_p025') = ["double" "r" "2.5th percentile of split_r over partitions (partition variability, not a confidence interval)."];
M('split_r_p975') = ["double" "r" "97.5th percentile of split_r over partitions."];
M('split_n_per_half') = ["integer" "" "Sweeps of each polarity in each half."];
M('split_avg_mode') = ["string" "" "Sub-average of each half: median or mean."];
M('xcorr_up') = ["double" "r" "Correlation with the next-louder level's average at the best lag in [0, max lag]; NA at the loudest level."];
M('xcorr_lag_ms') = ["double" "ms" "Lag of xcorr_up (this level later)."];
M('xcorr_up_lag0') = ["double" "r" "Correlation with the next-louder level's average at lag 0."];
M('amp_unit') = ["string" "" "What the *_uv columns are: uV (volts at the electrodes x 1e6), uV-unscaled (input full scale assumed 1), converter-x1e6 (converter units x 1e6), or mixed."];
M('input_full_scale') = ["double" "V" "Input full scale the recording was scaled by (NA when not recorded)."];
M('flags') = ["string" "" "Flags, ; separated."];
M('level_param') = ["string" "" "The parameter the series is swept along (e.g. Level)."];
M('method') = ["string" "" "Threshold method: perm-glm, perm-descending, power-descending, fsp-descending, presto, xcorr or custom."];
M('metric') = ["string" "" "Per-level statistic: detection, power, fsp, splithalf, xcorr, snr or strength."];
M('model') = ["string" "" "Model actually used: descending, glm, presto-sigmoid, presto-power, isotonic, sigmoid or minimum."];
M('criterion') = ["double" "" "Criterion the metric was judged at (unit in criterion_unit)."];
M('criterion_unit') = ["string" "" "p, probability, r, dB, statistic or fraction of range."];
M('threshold_db') = ["double" "dB" "The threshold (curated when reviewed). Censored rows hold their bound: left the lowest level, right the highest level. NA when excluded or not estimable; never infinite."];
M('cens') = ["string" "" "Censoring: none, left (at or below threshold_db), right (above threshold_db), interval (between thr_lo_db and thr_hi_db); empty when excluded or insufficient. brms cens() coding. No response is right-censored at the highest level on an ascending level axis, left-censored at the lowest attenuation on an attenuation axis."];
M('thr_lo_db') = ["double" "dB" "Lower bound (survival::Surv interval2): NA for left, the highest level for right, L(k*-1) for interval, threshold_db for none."];
M('thr_hi_db') = ["double" "dB" "Upper bound: the lowest level for left, NA for right, L(k*) for interval, threshold_db for none."];
M('thr_upper_db') = ["double" "dB" "brms y2: thr_hi_db for interval rows, threshold_db otherwise (never NA where cens is set)."];
M('convention') = ["string" "" "Point reported inside an interval: midpoint, lowest_level or crossing."];
M('threshold_fit_db') = ["double" "dB" "The method's own estimate before curation; NA when not finite (no response)."];
M('fit_status') = ["string" "" "The method's outcome: ok, no-response, all-respond, insufficient or failed."];
M('ci_lo_db') = ["double" "dB" "Lower confidence limit of the method's estimate (method in ci_method); NA when none."];
M('ci_hi_db') = ["double" "dB" "Upper confidence limit of the method's estimate."];
M('ci_method') = ["string" "" "profile, bootstrap, montecarlo or none."];
M('threshold_imputed_db') = ["double" "dB" "FOR PLOTS AND SENSITIVITY ANALYSES ONLY: threshold_db with censored rows imputed (right: highest level + step, left: lowest level - step)."];
M('imputation_rule') = ["string" "" "How threshold_imputed_db was made: none, max + step or min - step; empty with no threshold."];
M('level_step_db') = ["double" "dB" "Median spacing of the series' usable levels."];
M('n_levels') = ["integer" "" "Levels presented in the series."];
M('n_levels_used') = ["integer" "" "Usable levels (enough sweeps of each polarity, a defined metric)."];
M('n_detected') = ["integer" "" "Levels with a detected response."];
M('n_used_min') = ["integer" "" "Fewest clean sweeps at any level of the series."];
M('rn_uv_at_threshold') = ["double" "uV" "Residual noise at the level nearest the threshold."];
M('decision') = ["string" "" "Curation: empty (unreviewed), accepted, manual, noresponse, allrespond or excluded."];
M('reviewed') = ["logical" "" "TRUE when a curation decision was recorded."];
M('reviewed_by') = ["string" "" "Who reviewed the series."];
M('reviewed_at') = ["datetime" "" "When the series was reviewed (ISO 8601, local)."];
M('note') = ["string" "" "Curator's note."];
M('used_in_study') = ["logical" "" "TRUE when this session provides this series to the study (the duplicate policy's choice)."];
M('is_primary') = ["logical" "" "TRUE for the session's own (curated) method; FALSE for the extra rows of an all-methods export."];
M('level_re_thr_db') = ["double" "dB" "Sensation level: level minus the series' threshold_db (threshold minus attenuation on an attenuation axis), positive above threshold; NA when the series has no response (no finite threshold), is excluded or has no threshold."];
M('wave') = ["string" "" "Wave name (I, II, ... or a name of the user's)."];
M('state') = ["string" "" "auto (picked), manual (placed by hand), absent (marked absent by hand) or none (nothing found)."];
M('detectable') = ["logical" "" "Peak prominence at least the detectable multiple of the residual noise (PeakDetectableRN; 4 by default). A size criterion, NOT a detection test: every pick is the best of several local maxima, so noise picks are routinely 2-3 times the residual noise. Judge a response by below_threshold / level_re_thr_db."];
M('below_threshold') = ["logical" "" "The level is below the series' threshold."];
M('edge_affected') = ["logical" "" "Windowed condition with the peak within the edge margin of its extent."];
M('lat_peak_ms') = ["double" "ms" "Peak latency (parabolic refinement), re SOUND ARRIVAL when a conduction delay is set: the latency re the recorded stimulus onset minus conduction_delay_ms minus time_offset_ms."];
M('lat_trough_ms') = ["double" "ms" "Latency of the following trough, on the time base of lat_peak_ms (minus conduction_delay_ms and time_offset_ms)."];
M('lat_peak_raw_ms') = ["double" "ms" "Peak latency re the recorded (electrical) stimulus onset, the timing pulse; no delay or offset applied."];
M('conduction_delay_ms') = ["double" "ms" "Sound conduction delay subtracted from every latency: the acoustic travel time from the speaker to the ear (Settings ConductionDelayMode: a delay, or speaker distance / speed of sound; or the Project override). 0 when none is set; latencies are then re the recorded onset."];
M('time_offset_ms') = ["double" "ms" "Additional fixed system offset subtracted from every latency beyond conduction_delay_ms (e.g. a converter or onset-rounding bias). lat_peak_ms = lat_peak_raw_ms - conduction_delay_ms - time_offset_ms."];
M('peak_measures.conduction_delay_ms') = ["double" "ms" "Sound conduction delay of the session's latencies. Interpeak latencies are differences and do not depend on it."];
M('peak_measures.time_offset_ms') = ["double" "ms" "Fixed system offset of the session's latencies. Interpeak latencies are differences and do not depend on it."];
M('amp_pt_uv') = ["double" "uV" "Peak-to-following-trough amplitude (the primary amplitude)."];
M('amp_bp_uv') = ["double" "uV" "Baseline-to-peak amplitude; NA for windowed conditions."];
M('amp_bt_uv') = ["double" "uV" "Baseline-to-trough amplitude."];
M('amp_p0_uv') = ["double" "uV" "Peak value re 0 (diagnostic only)."];
M('prominence_uv') = ["double" "uV" "Peak prominence."];
M('prominence_rn') = ["double" "" "Peak prominence in multiples of the residual noise."];
M('latency_method') = ["string" "" "How latencies were refined (parabolic)."];
M('lat_se_ms') = ["double" "ms" "Bootstrap standard error of the latency; NA without a bootstrap."];
M('lat_ci_lo_ms') = ["double" "ms" "Bootstrap percentile interval of the latency, lower (on the time base of lat_peak_ms)."];
M('lat_ci_hi_ms') = ["double" "ms" "Bootstrap percentile interval of the latency, upper (on the time base of lat_peak_ms)."];
M('amp_pt_se_uv') = ["double" "uV" "Bootstrap standard error of amp_pt_uv."];
M('amp_pt_ci_lo_uv') = ["double" "uV" "Bootstrap percentile interval of amp_pt_uv, lower."];
M('amp_pt_ci_hi_uv') = ["double" "uV" "Bootstrap percentile interval of amp_pt_uv, upper."];
M('boot_unstable') = ["logical" "" "More than 10% of the bootstrap re-picks fell on a window edge."];
M('measure') = ["string" "" "IPL_<a>_<b>: interpeak latency between consecutive picked waves; IPL_<first>_<last>; LOGRATIO_<last>_<first> = log(amp_pt last) - log(amp_pt first)."];
M('value') = ["double" "" "Value of the measure (unit in unit)."];
M('peak_measures.unit') = ["string" "" "ms (interpeak latency) or ln ratio."];
M('quantity') = ["string" "" "amp_pt (peak-to-trough amplitude) or latency."];
M('slope') = ["double" "" "Least-squares slope against level, at and above threshold (unit in unit)."];
M('io_slopes.unit') = ["string" "" "uV/dB or ms/dB."];
M('intercept') = ["double" "" "Intercept at level 0 (uV for amp_pt; ms on the time base of lat_peak_ms -- re sound arrival when a conduction delay is set -- for latency)."];
M('io_slopes.n_levels') = ["integer" "" "Levels in the fit (picked, detectable, at or above threshold); fewer than 3 gives no slope."];
M('level_min') = ["double" "dB" "Lowest level in the fit."];
M('level_max') = ["double" "dB" "Highest level in the fit."];
M('waveforms.polarity') = ["string" "" "balanced ((mean of + and mean of -)/2), positive or negative."];
M('time_ms') = ["double" "ms" "Time on the time base of lat_peak_ms: re sound arrival when a conduction delay is set (the recorded onset minus conduction delay and time offset)."];
M('mean_uv') = ["double" "uV" "Average of the clean sweeps."];
M('sem_uv') = ["double" "uV" "Standard error of the balanced mean (pooled within file x polarity); balanced rows only."];
M('waveforms.n') = ["integer" "" "Sweeps averaged."];
M('time') = ["datetime" "" "When the note was taken (ISO 8601, local)."];
M('run') = ["integer" "" "Run number when the note was taken during acquisition; NA between runs."];
M('sweep') = ["integer" "" "Sweep count of that run when the note was taken."];
M('stamp') = ["string" "" "The note's stamp as written in the notebook."];
M('text') = ["string" "" "The note."];
M('source') = ["string" "" "Where the note was read: the files' notes or the .notes journal."];
M('scope') = ["string" "" "session (taken during this session) or earlier."];
M('sweep_order') = ["integer" "" "Rank of the sweep within its condition in acquisition order."];
M('file_id') = ["string" "" "File the sweep came from (folder/name)."];
M('sweep_in_file') = ["integer" "" "Onset ordinal of the sweep within its file."];
M('time_s') = ["double" "s" "Onset time from the file's first sample; NA for compact (interleaved) files, which record none."];
M('t_session_s') = ["double" "s" "Onset time from the session's start (file start times have 1 s resolution); NA for compact files."];
M('polarity') = ["integer" "" "Stimulus polarity, +1 or -1."];
M('rejected') = ["logical" "" "The sweep is rejected."];
M('reject_reason') = ["string" "" "none, rig, auto or manual."];
M('excess') = ["logical" "" "Beyond the per-condition sweep cap: not rejected, not used."];
M('rms_uv') = ["double" "uV" "Sweep RMS over the response window."];
M('blocks.rn_uv') = ["double" "uV" "Residual noise of the block: RMS of its +/- reference over the response window."];
M('p2p_uv') = ["double" "uV" "Sweep peak-to-peak over the response window."];
M('maxabs_uv') = ["double" "uV" "Largest absolute value over the response window."];
M('trials.baseline_rms_uv') = ["double" "uV" "Sweep RMS over the baseline window."];
M('template_amp') = ["double" "" "Projection on the leave-one-out average, scaled to mean 1 (2 = twice the typical response). NA for every sweep of a condition whose average holds no response (mean projection under 3 standard errors above 0), where the scaling would divide by noise."];
M('template_r') = ["double" "r" "Correlation with the leave-one-out average (a QC feature, not a detection statistic)."];
M('trial_waves.lat_peak_ms') = ["double" "ms" "Peak latency re-picked on the leave-one-out average, re sound arrival when a conduction delay is set (raw minus conduction_delay_ms and time_offset_ms)."];
M('trial_waves.lat_peak_raw_ms') = ["double" "ms" "That latency re the recorded (electrical) stimulus onset, no delay or offset applied."];
M('p_uv') = ["double" "uV" "The sweep's value at that latency."];
M('pn_uv') = ["double" "uV" "The sweep's peak minus its trough."];
M('proj') = ["double" "" "Projection of the sweep on the leave-one-out average around the wave (1 = a typical response)."];
M('block') = ["integer" "" "Block number in acquisition order."];
M('blocks.n') = ["integer" "" "Sweeps in the block (polarity balanced)."];
M('first_order') = ["integer" "" "sweep_order of the block's first sweep."];
M('last_order') = ["integer" "" "sweep_order of the block's last sweep."];
M('blocks.response_rms_uv') = ["double" "uV" "RMS of the block average over the response window."];
M('block_waves.lat_peak_ms') = ["double" "ms" "Peak latency of the block average, re sound arrival when a conduction delay is set (raw minus conduction_delay_ms and time_offset_ms)."];
M('block_waves.lat_peak_raw_ms') = ["double" "ms" "That latency re the recorded (electrical) stimulus onset, no delay or offset applied."];
M('block_waves.amp_pt_uv') = ["double" "uV" "Peak-to-trough amplitude of the block average."];
M('sweeps.time_ms') = ["double" "ms" "Time on the time base of lat_peak_ms: re sound arrival when a conduction delay is set (the recorded onset minus conduction delay and time offset)."];
M('value_uv') = ["double" "uV" "The sweep's sample."];
end

function S = specFor(name)
% One table's schema rows as a struct array: Column, Type, Unit,
% Description, Placeholder.
persistent cache
if isempty(cache), cache = containers.Map('KeyType','char','ValueType','any'); end
key = char(name);
if isKey(cache,key), S = cache(key); return; end
L = schemaList();
r = find(L.Table == name);
S = struct('Column',cellstr(L.Column(r)),'Type',cellstr(L.Type(r)),'Unit',cellstr(L.Unit(r)), ...
    'Description',cellstr(L.Description(r)),'Placeholder',num2cell(startsWith(L.Column(r),"<")));
for k = 1:numel(S)
    S(k).Column = string(S(k).Column); S(k).Type = string(S(k).Type);
    S(k).Unit = string(S(k).Unit); S(k).Description = string(S(k).Description);
end
S = reshape(S,1,[]);
cache(key) = S;
end

function n = allFixedColumns()
% Every fixed column name of every table (param columns must not collide).
persistent cache
if isempty(cache)
    L = schemaList();
    cache = unique(L.Column(~startsWith(L.Column,"<")));
end
n = cache;
end

% =========================================================================
%  Items, results and labels
% =========================================================================
function list = itemList(items)
% items as a cell array of item structs.
if isempty(items)
    list = {};
elseif iscell(items)
    list = reshape(items,1,[]);
elseif isstruct(items)
    list = num2cell(reshape(items,1,[]));
else
    error('mabr:analysis:Export:badInput', ...
        'items is a struct array (or a cell array of structs) of Key, Results, Labels, Notes, Session.');
end
for k = 1:numel(list)
    if ~isstruct(list{k}) || ~isscalar(list{k})
        error('mabr:analysis:Export:badInput','Item %d is not a struct.',k);
    end
end
end

function it = prepareItem(item,opts)
% One item, normalized: Results (v2 shape), Labels (every field), Notes,
% Session, and the context the builders read.
it = struct();
R = getf(item,'Results',[]);
R = loadResults(R);
it.Results = normalizeResults(R);
it.Key = string(getf(item,'Key',""));
if it.Key == "" || ismissing(it.Key)
    it.Key = string(getf(it.Results.Summary,'Key',""));
    if it.Key == "", it.Key = string(getf(it.Results.Summary,'Name',"")); end
end
it.Labels  = normalizeLabels(getf(item,'Labels',struct()),it.Results);
it.Notes   = getf(item,'Notes',[]);
it.Session = getf(item,'Session',[]);
it.Ctx     = context(it,opts);
end

function R = loadResults(R)
% A results struct from a struct, a file path or a Session.
if ischar(R) || (isstring(R) && isscalar(R))
    f = string(R);
    if ~isfile(f)
        error('mabr:analysis:Export:noResults','Results file not found: %s',f);
    end
    R = load(char(f),'-mat');
elseif isobject(R) && ismethod(R,'toStruct')
    try
        R = R.toStruct(false,true);
    catch
        R = R.toStruct();
    end
end
if isempty(R), R = struct(); end
if ~isstruct(R)
    error('mabr:analysis:Export:badInput','Results must be a results struct, a results file or a Session.');
end
end

function N = normalizeResults(R)
% Every field the builders read, from a v2 results struct or a v1 one.
N = struct();
N.Version = double(getf(R,'Version',1));
v1 = N.Version < 2 && ~isfield(R,'Summary');

% ---- Summary ------------------------------------------------------------
if v1
    S = struct();
    for f = ["Path","Name","Subject","SampleRate","Window","ResponseWindow","Time", ...
             "ParamNames","TestMode","FilterDescription"]
        if isfield(R,f), S.(f) = R.(f); end
    end
    S.Key = getf(R,'Name',"");
    if isfield(R,'Date') && isdatetime(R.Date), S.Date = mabr.analysis.Stats.isoTime(R.Date); end
else
    S = getf(R,'Summary',struct());
    if ~isstruct(S), S = struct(); end
end
N.Summary = S;
N.Files = tableOr(getf(R,'Files',table()));
N.Conditions = tableOr(getf(R,'Conditions',table()));
N.Thresholds = tableOr(getf(R,'Thresholds',table()));
N.Peaks = tableOr(getf(R,'Peaks',table()));
N.DetectionOverrides = tableOr(getf(R,'DetectionOverrides',table()));
N.Means = getf(R,'Means',[]);
N.SweepInfo = getf(R,'SweepInfo',[]);
so = getf(R,'StepOptions',struct());
if ~isstruct(so), so = struct(); end
N.StepOptions = so;

% ---- provenance and settings ---------------------------------------------
P = getf(R,'Provenance',struct());
if ~isstruct(P), P = struct(); end
N.Provenance = P;
st = getf(R,'Settings',[]);
if isobject(st) && ismethod(st,'toStruct'), st = st.toStruct(); end
if ~isstruct(st) || isempty(fieldnames(st)), st = []; end
N.Settings = st;

% ---- the defaults every builder can rely on -----------------------------
N.Summary.ParamNames = rowStr(getf(N.Summary,'ParamNames',strings(1,0)));
kp = rowStr(getf(N.Summary,'KeyParams',strings(1,0)));
if isempty(kp)
    pn = N.Summary.ParamNames;
    rest = sortCI(pn(~ismember(pn,["Stimulus","AcqMode"])));
    kp = ["AcqMode" rest];
    if ismember("Stimulus",pn) || ismember("Stimulus",string(N.Conditions.Properties.VariableNames))
        kp = ["Stimulus" kp];
    end
end
N.Summary.KeyParams = kp;
C = N.Conditions;
nC = height(C);
if nC > 0
    vn = string(C.Properties.VariableNames);
    if ~ismember("AcqMode",vn), C.AcqMode = repmat("conventional",nC,1); end
    if ~ismember("Key",vn), C.Key = keyFor(C,kp); end
    C.Key = toStr(C.Key,nC);
    if ~ismember("nClean",vn) && ismember("nSweeps",vn)
        nr = toDbl(tcol(C,'nRejected',0),nC);
        C.nClean = toDbl(C.nSweeps,nC) - nr;
    end
    if ~ismember("nPos",vn) && ismember("Polarity",vn) && iscell(C.Polarity)
        [C.nPos,C.nNeg] = polarityCounts(C);
    end
    N.Conditions = C;
end
if v1 && height(N.Thresholds) > 0
    N.Thresholds = legacyThresholds(N.Thresholds,N);
end
T = N.Thresholds;
if height(T) > 0 && ~ismember("Key",string(T.Properties.VariableNames))
    lp = string(getf(N.Summary,'LevelParam',""));
    T.Key = keyFor(T,kp(kp ~= lp & ismember(kp,[string(T.Properties.VariableNames) "AcqMode"])));
    N.Thresholds = T;
end
end

function T = legacyThresholds(T,N)
% A v1 Thresholds table in the v2 columns this class reads: the fit is the
% method's estimate, Curated/IsCurated the curation (Inf no response, NaN
% excluded -- the legacy setThreshold meaning).
n = height(T);
th = toDbl(tcol(T,'Threshold',NaN),n);
cur = toDbl(tcol(T,'Curated',NaN),n);
isc = toLgc(tcol(T,'IsCurated',false),n);
cens = repmat("none",n,1);
cens(th == Inf) = "right";
cens(th == -Inf) = "left";       % no response on an attenuation axis
cens(isnan(th)) = "";
lo = th; hi = th; mn = nan(n,1); mx = nan(n,1); stp = nan(n,1);
for i = 1:n
    f = [];
    if ismember("Fit",string(T.Properties.VariableNames)), f = T.Fit(i); end
    if iscell(f), f = f{1}; end
    x = [];
    if isstruct(f) && isfield(f,'X'), x = unique(double(f.X(:))); x = x(isfinite(x)); end
    if ~isempty(x)
        mn(i) = min(x); mx(i) = max(x);
        if numel(x) > 1, stp(i) = median(diff(x)); end
    end
    if cens(i) == "right", lo(i) = mx(i); hi(i) = NaN; end
    if cens(i) == "left", lo(i) = NaN; hi(i) = mn(i); end
end
T.Method = repmat("custom",n,1);
T.Metric = repmat("detection",n,1);
T.Censored = cens; T.ThrLo = lo; T.ThrHi = hi;
T.MinLevel = mn; T.MaxLevel = mx; T.LevelStep = stp;
dec = strings(n,1); kind = strings(n,1); mv = nan(n,1);
dec(isc & isfinite(cur)) = "manual"; kind(isc & isfinite(cur)) = "value"; mv(isc & isfinite(cur)) = cur(isc & isfinite(cur));
dec(isc & isinf(cur)) = "noresponse";
dec(isc & isnan(cur)) = "excluded";
T.Decision = dec; T.ManualKind = kind; T.ManualValue = mv;
if ~ismember("LevelParam",string(T.Properties.VariableNames))
    T.LevelParam = repmat(string(getf(N.Summary,'LevelParam',"")),n,1);
end
end

function L = normalizeLabels(L,R)
% Labels with every field, defaulted from the results.
if ~isstruct(L) || isempty(L), L = struct(); end
S = R.Summary;
d = struct('Subject',string(getf(S,'Subject',"")), ...
    'SubjectRaw',string(getf(S,'SubjectRaw',getf(S,'Subject',""))), ...
    'Timepoint',"",'TimepointOrder',NaN,'Group',"",'InStudy',true, ...
    'TestMode',logical(getf(S,'TestMode',false)),'DaysFromReference',NaN,'TimeOffset',NaN, ...
    'ConductionDelay',NaN,'Comment',"",'Free',struct(),'UsedInStudy',struct('SeriesKey',strings(0,1),'Used',false(0,1)));
for f = string(fieldnames(d)).'
    if isfield(L,f) && ~isempty(L.(f)) && ~(isstring(L.(f)) && all(ismissing(L.(f))))
        d.(f) = L.(f);
    end
end
d.Subject = scalarStr(d.Subject); d.SubjectRaw = scalarStr(d.SubjectRaw);
d.Timepoint = scalarStr(d.Timepoint); d.Group = scalarStr(d.Group); d.Comment = scalarStr(d.Comment);
d.TimepointOrder = scalarDbl(d.TimepointOrder);
d.DaysFromReference = scalarDbl(d.DaysFromReference);
d.TimeOffset = scalarDbl(d.TimeOffset);
d.ConductionDelay = scalarDbl(d.ConductionDelay);
d.InStudy = scalarLgc(d.InStudy,true);
d.TestMode = scalarLgc(d.TestMode,false) || scalarLgc(getf(S,'TestMode',false),false);
if ~isstruct(d.Free) || ~isscalar(d.Free), d.Free = struct(); end
L = d;
end

function ctx = context(it,opts)
% What every builder needs to know about one session.
R = it.Results; L = it.Labels; S = R.Summary;
ctx = struct();
ctx.Id = it.Key;
ctx.Subject = L.Subject;
if ctx.Subject == "", ctx.Subject = "(unknown subject)"; end
ctx.SubjectRaw = L.SubjectRaw;
ctx.Timepoint = L.Timepoint;
ctx.TimepointOrder = L.TimepointOrder;
ctx.Group = L.Group;
ctx.InStudy = L.InStudy;
ctx.TestMode = L.TestMode;
% A subject taken out of the study takes its sessions with it.
Sub = opts.Subjects;
if istable(Sub) && height(Sub) > 0 && all(ismember(["Subject","InStudy"],string(Sub.Properties.VariableNames)))
    k = find(string(Sub.Subject) == ctx.Subject,1);
    if ~isempty(k) && ~logical(Sub.InStudy(k)), ctx.InStudy = false; end
    if ctx.Group == "" && ~isempty(k) && ismember("Group",string(Sub.Properties.VariableNames))
        ctx.Group = scalarStr(Sub.Group(k));
    end
end
% Settings the session was analysed with (else the caller's).
st = R.Settings;
if isempty(st) && ~isempty(opts.Settings)
    [~,st] = settingsHashOf(opts.Settings);
end
ctx.Settings = st;
h = string(getf(R.Provenance,'SettingsHash',""));
if (h == "" || ismissing(h)) && ~isempty(st)
    h = settingsHashOf(st);
end
ctx.SettingsHash = h;
% The latency offset (A9): conduction delay + fixed time offset.
[ctx.ConductionDelay,ctx.TimeOffset,ctx.LatencyOffset] = latencyParts(L,S,st, ...
    tcol(R.Peaks,'LatencyOffset',[]));
% Parameters: the key parameters other than Stimulus and AcqMode.
kp = S.KeyParams;
ctx.Params = kp(~ismember(kp,["Stimulus","AcqMode"]));
ctx.ParamCols = paramColumns(ctx.Params);
ctx.LevelParam = levelParamOf(R);
gp = rowStr(getf(S,'GroupParams',strings(1,0)));
if isempty(gp)
    gp = ctx.Params(ctx.Params ~= ctx.LevelParam);
    T = R.Thresholds;
    if height(T) > 0
        gp = gp(ismember(gp,string(T.Properties.VariableNames)));
    end
end
ctx.GroupParams = gp(~ismember(gp,["Stimulus","AcqMode",ctx.LevelParam]));
ctx.GroupCols = paramColumns(ctx.GroupParams);
% The series the study uses from this session.
U = L.UsedInStudy;
if istable(U), U = table2struct(U,'ToScalar',true); end
ctx.UsedKeys = toStr(getf(U,'SeriesKey',strings(0,1)),[]);
ctx.UsedVals = toLgc(getf(U,'Used',false(0,1)),numel(ctx.UsedKeys));
ctx.DefaultUsed = ctx.InStudy && ~ctx.TestMode;
% Condition keys -> series keys.
C = R.Conditions;
if height(C) > 0
    ctx.CondKeys = toStr(C.Key,height(C));
    ctx.CondSeries = seriesKeyOf(ctx.CondKeys,ctx.LevelParam);
else
    ctx.CondKeys = strings(0,1); ctx.CondSeries = strings(0,1);
end
ctx.AmpUnits = ampUnit(toStr(tcol(C,'Units',string(getf(S,'Units',""))),height(C)));
ctx.SessionAmpUnit = ampUnit(string(getf(S,'Units',"")));
end

function [cd,to,lo] = latencyParts(L,S,st,stored)
% The latency offset of one session and its two parts (A9), ms:
%   cd  conduction delay: the label's (Project ConductionDelayOverride),
%       else the session's own override (Summary/Session
%       ConductionDelayOverride), else the settings' conductionDelay(),
%       else 0
%   to  fixed time offset: the label's (Project TimeOffsetOverride), else
%       the session's (Summary/Session TimeOffset; NaN, the default, means
%       none), else the settings' TimeOffset, else 0
%   Every override is "set" exactly when it is finite -- Session's own rule
%   for its LatencyOffset.
%   lo  cd + to -- unless no label overrides either part and the session
%       stored the offset its peaks were tracked with (the Peaks table's
%       LatencyOffset column, or a Session's LatencyOffset): that value is
%       then the offset, and to is what is left of it after cd, so that
%       lat_peak_raw_ms - conduction_delay_ms - time_offset_ms is always
%       exactly lat_peak_ms.
% The model stores raw latencies; this is only the subtraction
% Peaks.reported makes.
cd = L.ConductionDelay;
if ~isfinite(cd), cd = scalarDbl(getf(S,'ConductionDelayOverride',NaN)); end
if ~isfinite(cd), cd = scalarDbl(getf(S,'ConductionDelay',NaN)); end
if ~isfinite(cd), cd = settingsDelay(st); end
if ~isfinite(cd), cd = 0; end
to = L.TimeOffset;
if ~isfinite(to), to = scalarDbl(getf(S,'TimeOffset',NaN)); end
if ~isfinite(to), to = scalarDbl(getf(st,'TimeOffset',NaN)); end
if ~isfinite(to), to = 0; end
lo = cd + to;
labelled = isfinite(L.ConductionDelay) || isfinite(L.TimeOffset);
v = [];
if isnumeric(stored) && ~isempty(stored)
    v = double(stored(:));
    v = v(isfinite(v));
end
if ~labelled && ~isempty(v)
    lo = v(1);
    to = lo - cd;
end
end

function d = settingsDelay(st)
% Settings.conductionDelay() of a settings struct (or object): 0 for mode
% "none", ConductionDelay for "delay", 10*SpeakerDistance/SpeedOfSound for
% "distance"; NaN when the settings say nothing.
d = NaN;
if isempty(st), return; end
if isobject(st) && ismethod(st,'conductionDelay')
    d = double(st.conductionDelay());
    return
end
mode = lower(string(getf(st,'ConductionDelayMode',"")));
switch mode
    case "none",     d = 0;
    case "delay",    d = scalarDbl(getf(st,'ConductionDelay',NaN));
    case "distance", d = 10*scalarDbl(getf(st,'SpeakerDistance',NaN))/scalarDbl(getf(st,'SpeedOfSound',NaN));
end
end

function tf = keepItem(it,opts)
% The session filters: Test Mode, and sessions out of the study.
tf = true;
if ~opts.IncludeTestMode && it.Ctx.TestMode, tf = false; end
if ~opts.IncludeExcluded && ~it.Ctx.InStudy, tf = false; end
end

% =========================================================================
%  Building one session's tables
% =========================================================================
function P = itemTables(it,want,opts)
% The per-session part of every requested table.
P = struct();
F = [];          % the series' final values, shared by thresholds and peaks
for w = want
    switch w
        case "sessions",      P.sessions = sessionsPart(it);
        case "subjects"       % built across items
        case "conditions",    P.conditions = conditionsPart(it);
        case "thresholds"
            [P.thresholds,F] = thresholdsPart(it,opts);
        case "peaks"
            if isempty(F), [~,F] = thresholdsPart(it,setfield(opts,'ThresholdsAll',false)); end %#ok<SFLD>
            P.peaks = peaksPart(it,F,opts);
        case {"peak_measures","io_slopes"}
            if isempty(F), [~,F] = thresholdsPart(it,setfield(opts,'ThresholdsAll',false)); end %#ok<SFLD>
            if ~isfield(P,'peak_measures') && ~isfield(P,'io_slopes')
                [pm,io] = measuresPart(it,F,opts);
                if ismember("peak_measures",want), P.peak_measures = pm; end
                if ismember("io_slopes",want), P.io_slopes = io; end
            end
        case "waveforms",     P.waveforms = waveformsPart(it,opts.WaveformWindow);
        case "notes",         P.notes = notesPart(it);
        case "trials",        P.trials = trialsPart(it);
        case {"trial_waves","blocks","block_waves"}
            if ~isempty(it.Session) && ~isfield(P,w)
                rw = want(ismember(want,["trial_waves","blocks","block_waves"]));
                Rw = rawTables(it.Session,rawCtxFrom(it),rw,opts.BlockSize);
                for x = rw, P.(x) = Rw.(x); end
            end
        case "sweeps"         % written by writeRaw only
    end
end
end

function t = sessionsPart(it)
% One sessions row.
R = it.Results; S = R.Summary; c = it.Ctx; L = it.Labels;
C = R.Conditions; Fl = R.Files;
fx = identity(c,1);
fx.subject_raw = c.SubjectRaw;
fx.in_study = c.InStudy;
fx.test_mode = c.TestMode;
st = parseTime(getf(S,'Date',NaT));
if isnat(st) && height(Fl) > 0 && ismember("timestamp",string(Fl.Properties.VariableNames))
    ts = Fl.timestamp;
    if isdatetime(ts), st = min(ts); end
end
fx.start_time = st;
if isnat(st), fx.date = NaT; else, fx.date = dateshift(st,'start','day'); end
fx.days_from_reference = L.DaysFromReference;
nf = scalarDbl(getf(S,'NumFiles',NaN));
if ~isfinite(nf)
    if ismember("Include",string(Fl.Properties.VariableNames)), nf = sum(logical(Fl.Include));
    else, nf = height(Fl); end
end
fx.n_files = nf;
nc = scalarDbl(getf(S,'NumConditions',NaN));
if ~isfinite(nc), nc = height(C); end
fx.n_conditions = nc;
ns = scalarDbl(getf(S,'NumSweeps',NaN));
if ~isfinite(ns), ns = sum(toDbl(tcol(C,'nSweeps',0),height(C)),'omitnan'); end
fx.n_sweeps = ns;
stim = toStr(tcol(C,'Stimulus',""),height(C));
stim = unique(stim(stim ~= ""),'stable');
fx.stimuli = strjoin(stim,", ");
am = rowStr(getf(S,'AcqModes',strings(1,0)));
if isempty(am), am = unique(toStr(tcol(C,'AcqMode',"conventional"),height(C)),'stable').'; end
fx.acq_modes = strjoin(am,", ");
pr = unique(toStr(tcol(C,'Processing',""),height(C)),'stable');
fx.processing = strjoin(pr(pr ~= ""),", ");
fx.units = string(getf(S,'Units',""));
fx.level_unit = string(getf(S,'LevelUnit',""));
fx.settings_hash = c.SettingsHash;
fx.analyzed_at = parseTime(getf(R.Provenance,'AnalyzedAt',NaT));
fx.data_fingerprint = string(getf(S,'DataFingerprint',""));
fx.comment = L.Comment;
dyn.free_session = freeColumns(L.Free,"<free session columns>","Free session label column");
t = assemble("sessions",1,fx,dyn);
end

function t = subjectsTable(kept,opts)
% One row per subject of the exported sessions: from Project.Subjects when
% given (its free columns too), else from the labels.
subj = strings(0,1); grp = strings(0,1); ins = false(0,1);
for k = 1:numel(kept)
    c = kept{k}.Ctx;
    j = find(subj == c.Subject,1);
    if isempty(j)
        subj(end+1,1) = c.Subject; grp(end+1,1) = c.Group; ins(end+1,1) = c.InStudy; %#ok<AGROW>
    else
        ins(j) = ins(j) || c.InStudy;
        if grp(j) == "", grp(j) = c.Group; end
    end
end
[subj,o] = mabr.analysis.Stats.naturalSort(subj);
grp = grp(o); ins = ins(o);
n = numel(subj);
cm = strings(n,1);
free = struct('Placeholder',{},'Column',{},'Source',{},'Type',{},'Unit',{},'Description',{},'Values',{});
Sub = opts.Subjects;
if istable(Sub) && height(Sub) > 0 && ismember("Subject",string(Sub.Properties.VariableNames))
    vn = string(Sub.Properties.VariableNames);
    [tf,loc] = ismember(subj,string(Sub.Subject));
    if ismember("Group",vn)
        g = toStr(Sub.Group,height(Sub)); grp(tf) = g(loc(tf));
    end
    if ismember("InStudy",vn)
        s = toLgc(Sub.InStudy,height(Sub)); ins(tf) = s(loc(tf));
    end
    if ismember("Comment",vn)
        s = toStr(Sub.Comment,height(Sub)); cm(tf) = s(loc(tf));
    end
    fv = vn(~ismember(vn,["Subject","Group","InStudy","Comment","Modified"]));
    st = struct();
    for f = fv
        col = Sub.(f);
        if ~isvector(col) && ~isempty(col), continue; end
        if isstring(col) || ischar(col) || iscellstr(col) || iscategorical(col)
            v = strings(n,1); s = toStr(col,height(Sub)); v(tf) = s(loc(tf));
        elseif islogical(col)
            v = false(n,1); v(tf) = col(loc(tf));
        elseif isnumeric(col)
            v = nan(n,1); v(tf) = double(col(loc(tf)));
        else
            continue
        end
        st.(matlab.lang.makeValidName(f)) = v;
        st = renameSource(st,matlab.lang.makeValidName(f),f);
    end
    free = freeColumns(st,"<free subject columns>","Free subject label column",n);
end
fx = struct('subject',subj,'group',grp,'in_study',ins,'comment',cm);
dyn.free_subject = free;
t = assemble("subjects",n,fx,dyn);
end

function t = conditionsPart(it)
% One row per condition.
R = it.Results; C = R.Conditions; c = it.Ctx; S = R.Summary;
n = height(C);
fx = identity(c,n);
fx = condIdentity(fx,C,c,n);
fx.condition_key = c.CondKeys;
fx.series_key = c.CondSeries;
fx.level_ref = toStr(tcol(C,'LevelUnit',string(getf(S,'LevelUnit',""))),n);
cf = condFiles(R);
fx.calibration_time = fileText(R.Files,cf,'CalibrationTime',n);
fx.n_total = toDbl(tcol(C,'nSweeps',NaN),n);
fx.n_rejected = toDbl(tcol(C,'nRejected',NaN),n);
[rig,auto,man] = rejectCounts(R,n);
fx.n_rejected_rig = rig; fx.n_rejected_auto = auto; fx.n_rejected_manual = man;
fx.n_used = toDbl(tcol(C,'nClean',NaN),n);
fx.n_pos = toDbl(tcol(C,'nPos',NaN),n);
fx.n_neg = toDbl(tcol(C,'nNeg',NaN),n);
proc = toStr(tcol(C,'Processing',""),n);
fx.processing = proc;
E = tcol(C,'Extent',[]);
if isnumeric(E) && size(E,1) == n && size(E,2) == 2
    fx.extent_ms = rangeText(E(:,1),E(:,2));
else
    w = rowDbl(getf(S,'Window',[NaN NaN]),2);
    fx.extent_ms = repmat(rangeText(w(1),w(2)),n,1);
end
[hp,lp] = filterCorners(R,c);
fx.hp_6db_hz = hp; fx.lp_6db_hz = lp;
pad = padMode(R,c);
pm = strings(n,1); pm(proc == "windowed") = pad;
fx.pad_mode = pm;
rw = rowDbl(getf(S,'ResponseWindow',[NaN NaN]),2);
fx.response_window_ms = repmat(rangeText(rw(1),rw(2)),n,1);
fx.perm_p = toDbl(tcol(C,'p',NaN),n);
det = tcol(C,'Detected',[]);
if isempty(det), det = tcol(C,'isSig',false); end
fx.detected = toLgc(det,n);
fx.detected_override = overrideValues(R.DetectionOverrides,c.CondKeys);
fx.perm_strength = toDbl(tcol(C,'strength',NaN),n);
fx.rn_uv = 1e6*toDbl(tcol(C,'RN',NaN),n);
fx.rn_pm_uv = 1e6*toDbl(tcol(C,'RNPM',NaN),n);
fx.response_rms_uv = 1e6*toDbl(tcol(C,'ResponseRMS',NaN),n);
fx.baseline_rms_uv = 1e6*toDbl(tcol(C,'BaselineRMS',NaN),n);
fx.power_f = toDbl(tcol(C,'F',NaN),n);
fx.power_p = toDbl(tcol(C,'PowerP',NaN),n);
fx.snr_db = toDbl(tcol(C,'SNR',NaN),n);
fx.snr_corr_db = toDbl(tcol(C,'SNRCorr',NaN),n);
fx.fsp = toDbl(tcol(C,'Fsp',NaN),n);
fx.fsp_df1 = toDbl(tcol(C,'FspDF1',NaN),n);
fx.fsp_df2 = toDbl(tcol(C,'FspDF2',NaN),n);
fx.fsp_p = toDbl(tcol(C,'FspP',NaN),n);
fx.split_r = toDbl(tcol(C,'SplitR',NaN),n);
fx.split_r_sd = toDbl(tcol(C,'SplitRSD',NaN),n);
fx.split_r_p025 = toDbl(tcol(C,'SplitRP025',NaN),n);
fx.split_r_p975 = toDbl(tcol(C,'SplitRP975',NaN),n);
fx.split_n_per_half = toDbl(tcol(C,'SplitN',NaN),n);
mode = "";
if ismember("SplitR",string(C.Properties.VariableNames)) && ~isempty(c.Settings)
    mode = string(getf(c.Settings,'SplitHalfMode',""));
end
sm = repmat(mode,n,1); sm(isnan(fx.split_r)) = "";
fx.split_avg_mode = sm;
fx.xcorr_up = toDbl(tcol(C,'XCorrUp',NaN),n);
fx.xcorr_lag_ms = toDbl(tcol(C,'XCorrLag',NaN),n);
fx.xcorr_up_lag0 = toDbl(tcol(C,'XCorrUp0',NaN),n);
fx.amp_unit = c.AmpUnits;
fx.input_full_scale = inputFullScale(R,cf,n);
fx.flags = flagText(tcol(C,'Flags',""),n);
fx = tailCols(fx,c);
dyn.params = paramDyn(c,paramValues(C,c.Params,n));
t = assemble("conditions",n,fx,dyn);
end

function [t,F] = thresholdsPart(it,opts)
% One row per series (primary method), plus one per other built-in method
% with ThresholdsAll. F: the primary final values by series key, for peaks.
R = it.Results; T = R.Thresholds; C = R.Conditions; c = it.Ctx;
n = height(T);
F = struct('Key',strings(0,1),'Threshold',zeros(0,1),'Cens',strings(0,1),'Decision',strings(0,1), ...
    'Descending',false(0,1));
rows = {};
for i = 1:n
    row = table2struct(T(i,:));
    sk = scalarStr(getf(row,'Key',""));
    idx = find(c.CondSeries == sk);
    base = seriesBase(row,sk,idx,R,c);
    fin = finalOf(row);
    enc = encodeFinal(fin,scalarDbl(getf(row,'LevelStep',NaN)), ...
        scalarDbl(getf(row,'MinLevel',NaN)),scalarDbl(getf(row,'MaxLevel',NaN)));
    r = base;
    r.method = scalarStr(getf(row,'Method',""));
    r.metric = scalarStr(getf(row,'Metric',""));
    r.model = scalarStr(getf(row,'Type',""));
    r.criterion = scalarDbl(getf(row,'Criterion',NaN));
    r.criterion_unit = scalarStr(getf(row,'CriterionUnit',""));
    r.convention = scalarStr(getf(row,'Convention',""));
    r.threshold_fit_db = finiteOr(scalarDbl(getf(row,'Threshold',NaN)));
    r.fit_status = scalarStr(getf(row,'Status',""));
    r.ci_lo_db = finiteOr(scalarDbl(getf(row,'CILower',NaN)));
    r.ci_hi_db = finiteOr(scalarDbl(getf(row,'CIUpper',NaN)));
    r.ci_method = scalarStr(getf(row,'CIMethod',""));
    r.level_step_db = scalarDbl(getf(row,'LevelStep',NaN));
    r.n_levels = scalarDbl(getf(row,'NumLevels',NaN));
    r.n_levels_used = scalarDbl(getf(row,'NumUsable',NaN));
    r.n_detected = scalarDbl(getf(row,'NumSig',NaN));
    r.decision = lower(scalarStr(getf(row,'Decision',"")));
    r.reviewed = r.decision ~= "";
    r.reviewed_by = scalarStr(getf(row,'ReviewedBy',""));
    r.reviewed_at = parseTime(getf(row,'ReviewedAt',NaT));
    r.note = scalarStr(getf(row,'Note',""));
    r.flags = flagText(getf(row,'Flags',""),1);
    r.is_primary = true;
    r = mergeStruct(r,enc);
    r.rn_uv_at_threshold = rnAt(C,idx,c.LevelParam,enc.threshold_db);
    rows{end+1} = r; %#ok<AGROW>
    F.Key(end+1,1) = sk; F.Threshold(end+1,1) = enc.threshold_db;
    F.Cens(end+1,1) = enc.cens; F.Decision(end+1,1) = r.decision;
    F.Descending(end+1,1) = seriesDescending(row,c);

    if opts.ThresholdsAll
        others = builtinMethods();
        others = others(others ~= r.method);
        for m = others
            x = otherMethodRow(m,base,C,idx,R,c);
            if ~isempty(x)
                x.rn_uv_at_threshold = rnAt(C,idx,c.LevelParam,x.threshold_db);
                rows{end+1} = x; %#ok<AGROW>
            end
        end
    end
end
if opts.OnlyReviewed
    rows = rows(cellfun(@(r) ~r.is_primary || r.reviewed,rows));
    keepKeys = string(cellfun(@(r) r.series_key,rows(cellfun(@(r) r.is_primary,rows)),'UniformOutput',false));
    rows = rows(cellfun(@(r) ismember(r.series_key,keepKeys),rows));
end
t = rowsToTable("thresholds",rows,c);
end

function base = seriesBase(row,sk,idx,R,c)
% The columns a series' rows share, whatever the method.
C = R.Conditions;
base = identity(c,1);
base.stimulus = scalarStr(getf(row,'Stimulus',firstOf(toStr(tcol(C,'Stimulus',""),height(C)),idx,"")));
base.acq_mode = scalarStr(getf(row,'AcqMode',firstOf(toStr(tcol(C,'AcqMode',"conventional"),height(C)),idx,"conventional")));
base.series_key = sk;
lp = scalarStr(getf(row,'LevelParam',c.LevelParam));
if lp == "", lp = c.LevelParam; end
base.level_param = lp;
gv = nan(1,numel(c.GroupParams));
for k = 1:numel(c.GroupParams)
    v = getf(row,c.GroupParams(k),[]);
    if isempty(v)
        v = firstOf(toDbl(tcol(C,c.GroupParams(k),NaN),height(C)),idx,NaN);
    end
    gv(k) = scalarDbl(v);
end
base.GroupValues = gv;
base.n_used_min = minOr(toDbl(tcol(C,'nClean',NaN),height(C)),idx);
lu = toStr(tcol(C,'LevelUnit',""),height(C));
lu = unique(lu(idx));
lu = lu(lu ~= "");
if isempty(lu), lu = string(getf(R.Summary,'LevelUnit',"")); elseif numel(lu) > 1, lu = "mixed"; end
base.level_ref = lu;
base.used_in_study = usedFor(c,sk);
end

function n = permutationsOf(~,st)
% The permutations behind a permutation p under the analysed settings (NaN
% when they do not say): SeriesThreshold.estimate flags the detections within
% twice their Monte-Carlo error of Alpha as borderline, as Session does.
n = NaN;
try
    v = double(getf(st,'NumPermutations',NaN));
    if isscalar(v) && isfinite(v), n = v; end
catch
end
end

function x = otherMethodRow(m,base,C,idx,R,c)
% One series by another built-in method, from the stored per-condition
% columns -- the same SeriesThreshold.estimate Session.estimateThresholds
% runs, with the settings the session was analysed with. Uncurated.
x = [];
if isempty(idx), return; end
need = metricColumnOf(m,c.Settings);
if need ~= "" && (~ismember(need,string(C.Properties.VariableNames)) || ...
        ~any(isfinite(toDbl(C.(need)(idx),numel(idx)))))
    return      % the measure this method needs was never computed
end
st = c.Settings;
lp = base.level_param;
levels = toDbl(tcol(C,lp,NaN),height(C));
levels = levels(idx);
Y = struct();
map = ["P","p"; "IsSig","isSig"; "Strength","strength"; "PowerP","PowerP"; "FspP","FspP"; ...
       "SplitR","SplitR"; "SplitRSD","SplitRSD"; "XCorrUp","XCorrUp"; "SNR","SNR"; ...
       "NClean","nClean"; "NPos","nPos"; "NNeg","nNeg"];
for k = 1:size(map,1)
    if ismember(map(k,2),string(C.Properties.VariableNames))
        Y.(map(k,1)) = toDbl(C.(map(k,2))(idx),numel(idx));
    end
end
ov = overrideValues(R.DetectionOverrides,c.CondKeys);
Y.Override = ov(idx);
% A level with no noise is ignored for that reason, as Session.seriesY says.
if ismember("Flags",string(C.Properties.VariableNames))
    Y.ZeroVariance = reshape(contains(string(C.Flags(idx)), ...
        mabr.analysis.SingleTrial.FlagZeroVariance),[],1);
end
npos = toDbl(tcol(C,'nPos',NaN),height(C)); nneg = toDbl(tcol(C,'nNeg',NaN),height(C));
alternating = any(npos(idx) > 0 & nneg(idx) > 0) || all(isnan(npos(idx)));
dirn = string(getf(st,'LevelDirection',"auto"));
if dirn == "auto"
    if contains(lower(lp),"attenuation"), dirn = "descending"; else, dirn = "ascending"; end
end
x = base;
try
    meth = mabr.analysis.SeriesThreshold.resolve(m,st);
    out = mabr.analysis.SeriesThreshold.estimate(levels,Y,meth, ...
        Alpha=double(getf(st,'Alpha',0.05)), ...
        MinConsecutive=double(getf(st,'MinConsecutive',2)), ...
        Convention=string(getf(st,'ThresholdConvention',"midpoint")), ...
        Interpolate=logical(getf(st,'Interpolate',true)), ...
        MinSweeps=double(getf(st,'MinSweeps',100)), ...
        MinPerPolarity=double(getf(st,'MinPerPolarity',40)), ...
        Alternating=alternating, ...
        Extrapolate=logical(getf(st,'Extrapolate',true)), ...
        NearestLevel=logical(getf(st,'NearestLevel',false)), ...
        CIAlpha=double(getf(st,'CIAlpha',0.05)), ...
        CINumSamples=double(getf(st,'CINumSamples',2000)), ...
        Seed=double(getf(st,'Seed',1)), ...
        LevelDirection=dirn, ...
        FlagWideCI=double(getf(st,'FlagWideCI',0.35)), ...
        FlagNonMonotoneTol=double(getf(st,'FlagNonMonotoneTol',0)), ...
        NumPermutations=permutationsOf(m,st));
    fin = struct('Final',out.Threshold,'FinalCensored',out.Censored,'FinalLo',out.ThrLo,'FinalHi',out.ThrHi);
    enc = encodeFinal(fin,out.LevelStep,min(levels),max(levels));
    x.method = m;
    x.metric = meth.Metric;
    x.model = string(out.Type);
    x.criterion = out.Criterion;
    x.criterion_unit = string(out.CriterionUnit);
    x.convention = string(out.Convention);
    x.threshold_fit_db = finiteOr(out.Threshold);
    x.fit_status = string(out.Status);
    x.ci_lo_db = finiteOr(out.CILower);
    x.ci_hi_db = finiteOr(out.CIUpper);
    x.ci_method = string(out.CIMethod);
    x.level_step_db = out.LevelStep;
    x.n_levels = out.NumLevels;
    x.n_levels_used = out.NumUsable;
    x.n_detected = out.NumSig;
    x.flags = strjoin(string(out.Flags),"; ");
catch ME
    enc = encodeFinal(struct('Final',NaN,'FinalCensored',"",'FinalLo',NaN,'FinalHi',NaN),NaN,NaN,NaN);
    x.method = m; x.metric = ""; x.model = ""; x.criterion = NaN; x.criterion_unit = "";
    x.convention = ""; x.threshold_fit_db = NaN; x.fit_status = "failed";
    x.ci_lo_db = NaN; x.ci_hi_db = NaN; x.ci_method = "none"; x.level_step_db = NaN;
    x.n_levels = numel(levels); x.n_levels_used = NaN; x.n_detected = NaN;
    x.flags = "error: " + string(ME.message);
end
x.decision = ""; x.reviewed = false; x.reviewed_by = ""; x.reviewed_at = NaT; x.note = "";
x.is_primary = false;
x = mergeStruct(x,enc);
end

function t = rowsToTable(name,rows,c)
% Row structs (thresholds) into the table, group parameters as dynamic columns.
n = numel(rows);
fx = struct();
spec = specFor(name);
fixedCols = colsOf(spec(~phOf(spec)));
gv = nan(n,numel(c.GroupParams));
if n == 0
    for f = fixedCols, fx.(f) = zeros(0,1); end
else
    rows = cellfun(@(r) tailCols(r,c),rows,'UniformOutput',false);
    for f = fixedCols
        v = cellfun(@(r) r.(f),rows,'UniformOutput',false);
        fx.(f) = vertcat(v{:});
    end
    for i = 1:n, gv(i,:) = rows{i}.GroupValues; end
end
fx = fixTypes(fx,spec,n);
dyn.group = groupDyn(c,gv);
t = assemble(name,n,fx,dyn);
end

function enc = encodeFinal(F,step,minL,maxL)
% The censoring columns of one row from its final value (10 §15.2):
%   left     threshold = thr_hi = lowest level, thr_lo NA
%   right    threshold = thr_lo = highest level, thr_hi NA
%   interval thr_lo = L(k*-1), thr_hi = L(k*), threshold = the convention point
%   none     thr_lo = thr_hi = threshold
% thr_upper (brms y2) = thr_hi on interval rows, the threshold otherwise.
% Nothing infinite survives: +Inf (no response on an ascending axis,
% right-censored) and -Inf (no response on an attenuation axis,
% left-censored) are both stood for by their bound -- FinalLo / FinalHi, or
% when a row lacks it the series' MaxLevel / MinLevel -- and a value with no
% finite bound is no threshold at all.
if nargin < 3, minL = NaN; end
if nargin < 4, maxL = NaN; end
c  = lower(scalarStr(getf(F,'FinalCensored',"")));
v  = scalarDbl(getf(F,'Final',NaN));
lo = scalarDbl(getf(F,'FinalLo',NaN));
hi = scalarDbl(getf(F,'FinalHi',NaN));
th = NaN; tl = NaN; tu = NaN; up = NaN; imp = NaN; rule = "";
switch c
    case "none"
        th = v; tl = v; tu = v;
    case "interval"
        th = v; tl = lo; tu = hi;
    case "left"
        b = hi;
        if ~isfinite(b), b = v; end
        if ~isfinite(b), b = minL; end
        th = b; tu = b;
    case "right"
        b = lo;
        if ~isfinite(b), b = v; end
        if ~isfinite(b), b = maxL; end
        th = b; tl = b;
    otherwise
        c = "";
end
if ~isfinite(th) || (c == "interval" && ~(isfinite(tl) && isfinite(tu)))
    c = ""; th = NaN; tl = NaN; tu = NaN;
end
if c ~= ""
    if c == "interval", up = tu; else, up = th; end
    switch c
        case "right", imp = th + step; rule = "max + step";
        case "left",  imp = th - step; rule = "min - step";
        otherwise,    imp = th; rule = "none";
    end
    if ~isfinite(imp), imp = NaN; end
end
enc = struct('threshold_db',th,'cens',string(c),'thr_lo_db',tl,'thr_hi_db',tu, ...
    'thr_upper_db',up,'threshold_imputed_db',imp,'imputation_rule',string(rule));
end

function tf = seriesDescending(row,c)
% Is the series' level an attenuation (descending) axis? Its fit says so
% (SeriesThreshold.estimate records LevelDirection), else a LevelDirection
% column, else the settings, else a level parameter named like an
% attenuation -- the rule Session.estimateThresholds applies to "auto".
fit = getf(row,'Fit',[]);
if iscell(fit) && ~isempty(fit), fit = fit{1}; end
d = "";
if isstruct(fit) && isfield(fit,'LevelDirection'), d = scalarStr(fit.LevelDirection); end
if d == "" || d == "auto", d = scalarStr(getf(row,'LevelDirection',"")); end
if d == "" || d == "auto", d = scalarStr(getf(c.Settings,'LevelDirection',"")); end
if d == "" || d == "auto"
    lp = scalarStr(getf(row,'LevelParam',c.LevelParam));
    if lp == "", lp = c.LevelParam; end
    tf = contains(lower(lp),"attenuation");
    return
end
tf = lower(d) == "descending";
end

function F = finalOf(row)
% A Thresholds row's curated final value: the stored Final columns, else
% SeriesThreshold.finalValue of the row.
if isfield(row,'FinalCensored') && isfield(row,'Final')
    F = struct('Final',scalarDbl(row.Final),'FinalCensored',scalarStr(row.FinalCensored), ...
        'FinalLo',scalarDbl(getf(row,'FinalLo',NaN)),'FinalHi',scalarDbl(getf(row,'FinalHi',NaN)));
    return
end
conv = scalarStr(getf(row,'Convention',"midpoint"));
if ~ismember(conv,["midpoint","lowest_level","crossing"]), conv = "midpoint"; end
try
    F = mabr.analysis.SeriesThreshold.finalValue(row,conv);
catch
    F = struct('Final',scalarDbl(getf(row,'Threshold',NaN)), ...
        'FinalCensored',scalarStr(getf(row,'Censored',"")), ...
        'FinalLo',scalarDbl(getf(row,'ThrLo',NaN)),'FinalHi',scalarDbl(getf(row,'ThrHi',NaN)));
end
end

function t = peaksPart(it,F,opts)
% Every stored pick.
R = it.Results; P = R.Peaks; C = R.Conditions; c = it.Ctx;
P = filterSeriesRows(P,F,opts,c);
n = height(P);
fx = identity(c,n);
key = toStr(tcol(P,'Key',""),n);
[~,ci] = ismember(key,c.CondKeys);
fx = condIdentityAt(fx,P,C,ci,n);
fx.condition_key = key;
sk = peakSeries(P,key,c);
fx.series_key = sk;
lev = peakLevels(P,C,ci,c);
[tfF,fi] = ismember(sk,F.Key);
% Sensation level: positive above threshold on either axis. A series with
% no response has no threshold to be above (right-censored on an ascending
% axis, left-censored on an attenuation one); all-respond keeps its bound.
rel = nan(n,1);
ok = tfF;
desc = false(n,1);
desc(ok) = F.Descending(fi(ok));
noResp = repmat("right",n,1); noResp(desc) = "left";
ok(ok) = ismember(F.Cens(fi(ok)),["none","interval","left","right"]) & ...
    F.Cens(fi(ok)) ~= noResp(ok) & isfinite(F.Threshold(fi(ok)));
rel(ok) = lev(ok) - F.Threshold(fi(ok));
rel(ok & desc) = -rel(ok & desc);
fx.level_re_thr_db = rel;
fx.wave = toStr(tcol(P,'Wave',""),n);
fx.state = toStr(tcol(P,'State',""),n);
fx.detectable = toLgc(tcol(P,'Detectable',false),n);
fx.below_threshold = toLgc(tcol(P,'BelowThreshold',false),n);
fx.edge_affected = toLgc(tcol(P,'EdgeAffected',false),n);
off = c.LatencyOffset;
latRaw = toDbl(tcol(P,'PeakLatency',NaN),n);
fx.lat_peak_ms = mabr.analysis.Peaks.reported(latRaw,off);
fx.lat_trough_ms = mabr.analysis.Peaks.reported(toDbl(tcol(P,'TroughLatency',NaN),n),off);
fx.lat_peak_raw_ms = latRaw;
fx.conduction_delay_ms = repmat(c.ConductionDelay,n,1);
fx.time_offset_ms = repmat(c.TimeOffset,n,1);
pv = toDbl(tcol(P,'PeakValue',NaN),n);
tv = toDbl(tcol(P,'TroughValue',NaN),n);
amp = toDbl(tcol(P,'AmpPT',NaN),n);
noAmp = isnan(amp); amp(noAmp) = pv(noAmp) - tv(noAmp);
fx.amp_pt_uv = 1e6*amp;
proc = condText(C,'Processing',ci,"");
bp = 1e6*toDbl(tcol(P,'AmpBP',NaN),n);
bp(proc == "windowed") = NaN;
fx.amp_bp_uv = bp;
fx.amp_bt_uv = 1e6*toDbl(tcol(P,'AmpBT',NaN),n);
fx.amp_p0_uv = 1e6*pv;
fx.prominence_uv = 1e6*toDbl(tcol(P,'Prominence',NaN),n);
fx.prominence_rn = toDbl(tcol(P,'ProminenceRN',NaN),n);
fx.latency_method = toStr(tcol(P,'LatencyMethod',"parabolic"),n);
fx.lat_se_ms = toDbl(tcol(P,'LatencySE',NaN),n);
fx.lat_ci_lo_ms = mabr.analysis.Peaks.reported(toDbl(tcol(P,'LatencyCILo',NaN),n),off);
fx.lat_ci_hi_ms = mabr.analysis.Peaks.reported(toDbl(tcol(P,'LatencyCIHi',NaN),n),off);
fx.amp_pt_se_uv = 1e6*toDbl(tcol(P,'AmpPTSE',NaN),n);
fx.amp_pt_ci_lo_uv = 1e6*toDbl(tcol(P,'AmpPTCILo',NaN),n);
fx.amp_pt_ci_hi_uv = 1e6*toDbl(tcol(P,'AmpPTCIHi',NaN),n);
fx.boot_unstable = toLgc(tcol(P,'BootstrapUnstable',false),n);
fx.processing = proc;
fx.amp_unit = condTextVec(c.AmpUnits,ci,c.SessionAmpUnit);
fx.used_in_study = usedFor(c,sk);
fx = tailCols(fx,c);
dyn.params = paramDyn(c,peakParams(P,C,ci,c,n));
t = assemble("peaks",n,fx,dyn);
end

function [pm,io] = measuresPart(it,F,opts)
% Interpeak latencies, amplitude ratios and I/O slopes (Peaks.derived) from
% the stored picks, at or above threshold when PeaksAboveThresholdOnly.
R = it.Results; P = R.Peaks; C = R.Conditions; c = it.Ctx;
above = logical(getf(c.Settings,'PeaksAboveThresholdOnly',true));
P = filterSeriesRows(P,F,opts,c);
n = height(P);
if n > 0
    key = toStr(tcol(P,'Key',""),n);
    [~,ci] = ismember(key,c.CondKeys);
    P2 = table(key,peakSeries(P,key,c),peakLevels(P,C,ci,c),toStr(tcol(P,'Wave',""),n), ...
        toStr(tcol(P,'State',""),n),toDbl(tcol(P,'PeakLatency',NaN),n), ...
        'VariableNames',{'Key','SeriesKey','Level','Wave','State','PeakLatency'});
    amp = toDbl(tcol(P,'AmpPT',NaN),n);
    noAmp = isnan(amp);
    pt = toDbl(tcol(P,'PeakValue',NaN),n) - toDbl(tcol(P,'TroughValue',NaN),n);
    amp(noAmp) = pt(noAmp);
    P2.AmpPT = amp;
    P2.Detectable = toLgc(tcol(P,'Detectable',true),n);
    below = toLgc(tcol(P,'BelowThreshold',false),n);
    if above
        % A series with no threshold (excluded, insufficient) has no level
        % "at or above" it: none of its picks may count.
        [tfF,fi] = ismember(P2.SeriesKey,F.Key);
        none = ~tfF;
        none(tfF) = F.Cens(fi(tfF)) == "";
        below = below | none;
    end
    P2.BelowThreshold = below;
    [M,G] = mabr.analysis.Peaks.derived(P2,AboveThresholdOnly=above);
else
    M = table(strings(0,1),strings(0,1),zeros(0,1),strings(0,1),'VariableNames',{'Key','Measure','Value','Unit'});
    G = table(strings(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),strings(0,1), ...
        zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'SeriesKey','Wave','Quantity','Slope', ...
        'Intercept','Unit','NLevels','LevelMin','LevelMax'});
end

% ---- peak_measures
m = height(M);
fx = identity(c,m);
key = toStr(M.Key,m);
[~,ci] = ismember(key,c.CondKeys);
fx = condIdentityAt(fx,table(),C,ci,m);
fx.condition_key = key;
fx.measure = toStr(M.Measure,m);
fx.value = toDbl(M.Value,m);
fx.unit = toStr(M.Unit,m);
fx.conduction_delay_ms = repmat(c.ConductionDelay,m,1);
fx.time_offset_ms = repmat(c.TimeOffset,m,1);
fx.used_in_study = usedFor(c,seriesKeyOf(key,c.LevelParam));
fx = tailCols(fx,c);
dyn.params = paramDyn(c,paramValues(C,c.Params,height(C),ci));
pm = assemble("peak_measures",m,fx,dyn);

% ---- io_slopes
g = height(G);
fx = identity(c,g);
sk = toStr(G.SeriesKey,g);
[tfT,ti] = ismember(sk,toStr(tcol(R.Thresholds,'Key',""),height(R.Thresholds)));
stim = strings(g,1); acq = repmat("conventional",g,1); gv = nan(g,numel(c.GroupParams));
for i = 1:g
    idx = find(c.CondSeries == sk(i));
    stim(i) = firstOf(toStr(tcol(C,'Stimulus',""),height(C)),idx,"");
    acq(i)  = firstOf(toStr(tcol(C,'AcqMode',"conventional"),height(C)),idx,"conventional");
    for k = 1:numel(c.GroupParams)
        v = NaN;
        if tfT(i) && ismember(c.GroupParams(k),string(R.Thresholds.Properties.VariableNames))
            v = scalarDbl(R.Thresholds.(c.GroupParams(k))(ti(i)));
        end
        if isnan(v), v = firstOf(toDbl(tcol(C,c.GroupParams(k),NaN),height(C)),idx,NaN); end
        gv(i,k) = v;
    end
end
fx.stimulus = stim; fx.acq_mode = acq;
fx.series_key = sk;
fx.wave = toStr(G.Wave,g);
q = toStr(G.Quantity,g);
isAmp = q == "AmpPT";
slope = toDbl(G.Slope,g); icpt = toDbl(G.Intercept,g);
slope(isAmp) = 1e6*slope(isAmp);
icpt(isAmp) = 1e6*icpt(isAmp);
icpt(~isAmp) = mabr.analysis.Peaks.reported(icpt(~isAmp),c.LatencyOffset);
qq = q; qq(isAmp) = "amp_pt"; qq(q == "Latency") = "latency";
un = toStr(G.Unit,g); un(isAmp) = "uV/dB";
fx.quantity = qq; fx.slope = slope; fx.unit = un; fx.intercept = icpt;
fx.n_levels = toDbl(G.NLevels,g);
fx.level_min = toDbl(G.LevelMin,g);
fx.level_max = toDbl(G.LevelMax,g);
fx.used_in_study = usedFor(c,sk);
fx = tailCols(fx,c);
dyn = struct();
dyn.group = groupDyn(c,gv);
io = assemble("io_slopes",g,fx,dyn);
end

function P = filterSeriesRows(P,F,opts,c)
% OnlyReviewed applies to every series-level table.
if ~opts.OnlyReviewed || height(P) == 0, return; end
n = height(P);
key = toStr(tcol(P,'Key',""),n);
sk = peakSeries(P,key,c);
rev = F.Key(F.Decision ~= "");
P = P(ismember(sk,rev),:);
end

function t = waveformsPart(it,win)
% The stored per-condition means, long: condition x polarity x time.
R = it.Results; C = R.Conditions; c = it.Ctx; S = R.Summary;
M = R.Means;
time = toDbl(getf(S,'Time',[]),[]);
[keys,B,Pp,Ng,SE,N] = meansOf(M,R,c,numel(time));
t0 = mabr.analysis.Peaks.reported(time,c.LatencyOffset);
inW = t0 >= win(1) - 1e-9 & t0 <= win(2) + 1e-9;
tw = t0(inW);
nW = numel(tw);
[tfK,loc] = ismember(c.CondKeys,keys);
ci = find(tfK);
cols = loc(tfK);
nCw = numel(ci);
n = nCw*3*nW;
fx = identity(c,n);
condRow = repelem(ci(:),3*nW,1);
fx = condIdentityAt(fx,table(),C,condRow,n);
fx.condition_key = c.CondKeys(condRow);
pl = ["balanced";"positive";"negative"];
fx.polarity = repmat(repelem(pl,nW,1),nCw,1);
fx.time_ms = repmat(tw(:),3*nCw,1);
X = cat(3,B(inW,cols),Pp(inW,cols),Ng(inW,cols));      % nW x nCw x 3
fx.mean_uv = 1e6*double(reshape(permute(X,[1 3 2]),[],1));
Z = cat(3,SE(inW,cols),nan(nW,nCw),nan(nW,nCw));
fx.sem_uv = 1e6*double(reshape(permute(Z,[1 3 2]),[],1));
npos = toDbl(tcol(C,'nPos',NaN),height(C)); nneg = toDbl(tcol(C,'nNeg',NaN),height(C));
nb = N(cols); np = npos(ci); nn = nneg(ci);
cnt = [nb(:) np(:) nn(:)].';                             % 3 x nCw
fx.n = reshape(repelem(cnt(:),nW,1),[],1);
fx = tailCols(fx,c);
dyn.params = paramDyn(c,paramValues(C,c.Params,height(C),condRow));
t = assemble("waveforms",n,fx,dyn);
end

function [keys,B,Pp,Ng,SE,N] = meansOf(M,R,c,nT)
% The stored means (v2), or means computed from v1 sweeps when those were
% saved; [nT x nC] each, keys in column order.
keys = strings(0,1); B = zeros(nT,0); Pp = B; Ng = B; SE = B; N = zeros(0,1);
if isstruct(M) && isfield(M,'Keys') && isfield(M,'Balanced')
    keys = toStr(M.Keys,[]);
    B = double(M.Balanced);
    nC = numel(keys);
    Pp = matOr(M,'Positive',nT,nC); Ng = matOr(M,'Negative',nT,nC); SE = matOr(M,'SEM',nT,nC);
    N = toDbl(getf(M,'N',nan(nC,1)),nC);
    return
end
C = R.Conditions;
vn = string(C.Properties.VariableNames);
if height(C) == 0 || ~ismember("Sweeps",vn) || ~iscell(C.Sweeps), return; end
nC = height(C);
keys = c.CondKeys;
B = nan(nT,nC); Pp = B; Ng = B; SE = B; N = nan(nC,1);
for i = 1:nC
    X = C.Sweeps{i};
    if isempty(X) || size(X,1) ~= nT, continue; end
    keep = true(1,size(X,2));
    if ismember("Rejected",vn) && iscell(C.Rejected) && numel(C.Rejected{i}) == size(X,2)
        keep = ~logical(C.Rejected{i});
    end
    pol = ones(1,size(X,2));
    if ismember("Polarity",vn) && iscell(C.Polarity) && numel(C.Polarity{i}) == size(X,2)
        pol = double(C.Polarity{i});
    end
    X = double(X(:,keep)); pol = pol(keep);
    if isempty(X), continue; end
    [B(:,i),SE(:,i),info] = mabr.analysis.Stats.balancedMean(X,pol,[]);
    if any(pol > 0), Pp(:,i) = mean(X(:,pol > 0),2); end
    if any(pol < 0), Ng(:,i) = mean(X(:,pol < 0),2); end
    N(i) = info.N;
end
end

function t = notesPart(it)
% The session's notebook (Catalog.notes).
c = it.Ctx;
Nt = it.Notes;
if isstruct(Nt) && ~isempty(Nt), Nt = struct2table(Nt(:),'AsArray',true); end
if ~istable(Nt), Nt = table(); end
n = height(Nt);
fx = identity(c,n);
fx.time = toDT(tcol(Nt,'Time',NaT),n);
fx.run = toDbl(tcol(Nt,'Run',NaN),n);
fx.sweep = toDbl(tcol(Nt,'Sweep',NaN),n);
fx.stamp = toStr(tcol(Nt,'Stamp',""),n);
fx.text = toStr(tcol(Nt,'Text',""),n);
fx.source = toStr(tcol(Nt,'Source',""),n);
fx.scope = toStr(tcol(Nt,'Scope',""),n);
fx = tailCols(fx,c);
t = assemble("notes",n,fx,struct());
end

function t = trialsPart(it)
% One row per sweep, from the stored per-sweep info (no raw data).
R = it.Results; C = R.Conditions; c = it.Ctx; Fl = R.Files;
SI = R.SweepInfo;
if ~isstruct(SI) || ~isfield(SI,'Cond')
    SI = struct('Cond',zeros(0,1));
end
cond = double(SI.Cond(:));
n = numel(cond);
fx = identity(c,n);
fx = condIdentityAt(fx,table(),C,cond,n);
fx.condition_key = keyAt(c.CondKeys,cond);
fx.sweep_order = siCol(SI,'Order',n);
file = siCol(SI,'File',n);
fid = strings(n,1);
nf = height(Fl);
okF = isfinite(file) & file >= 1 & file <= nf;
if nf > 0 && ismember("FileId",string(Fl.Properties.VariableNames))
    ids = toStr(Fl.FileId,nf); fid(okF) = ids(file(okF));
end
fx.file_id = fid;
fx.sweep_in_file = siCol(SI,'Index',n);
ts = siCol(SI,'Time',n);
fx.time_s = ts;
tsess = nan(n,1);
if nf > 0 && ismember("timestamp",string(Fl.Properties.VariableNames)) && isdatetime(Fl.timestamp)
    stamps = Fl.timestamp;
    inc = true(nf,1);
    if ismember("Include",string(Fl.Properties.VariableNames)), inc = logical(Fl.Include); end
    t0 = min(stamps(inc & ~isnat(stamps)));
    if ~isempty(t0)
        off = nan(n,1);
        off(okF) = seconds(stamps(file(okF)) - t0);
        tsess = off + ts;
    end
end
fx.t_session_s = tsess;
fx.polarity = siCol(SI,'Polarity',n);
fx.rejected = toLgc(siCol(SI,'Rejected',n),n);
rs = ["none";"rig";"auto";"manual"];
rr = siCol(SI,'Reason',n); rr(~isfinite(rr) | rr < 0 | rr > 3) = 0;
fx.reject_reason = rs(rr + 1);
fx.excess = toLgc(siCol(SI,'Excess',n),n);
fx.rms_uv = 1e6*siCol(SI,'RMS',n);
fx.p2p_uv = 1e6*siCol(SI,'P2P',n);
fx.maxabs_uv = 1e6*siCol(SI,'MaxAbs',n);
fx.baseline_rms_uv = 1e6*siCol(SI,'BaselineRMS',n);
fx.template_amp = siCol(SI,'TemplateAmp',n);
fx.template_r = siCol(SI,'TemplateR',n);
fx = tailCols(fx,c);
dyn.params = paramDyn(c,paramValues(C,c.Params,height(C),cond));
t = assemble("trials",n,fx,dyn);
end

% =========================================================================
%  Raw tables (a Session with sweeps)
% =========================================================================
function ctx = rawContext(s,labels,sessionId)
% The context of a Session (or session-like struct) and its labels.
key = "";
if isstruct(labels) && isfield(labels,'Labels')
    key = string(getf(labels,'Key',""));
    labels = labels.Labels;
end
if ~isstruct(labels), labels = struct(); end
R = struct('Summary',struct('Subject',string(getf(s,'Subject',"")), ...
    'SubjectRaw',string(getf(s,'SubjectRaw',getf(s,'Subject',""))), ...
    'TestMode',logical(getf(s,'TestMode',false))));
L = normalizeLabels(labels,R);
ctx = struct();
if sessionId ~= "", key = sessionId; end
if key == "", key = string(getf(s,'Key',"")); end
if key == "", key = string(getf(s,'Name',"")); end
ctx.Id = key;
ctx.Subject = L.Subject; if ctx.Subject == "", ctx.Subject = "(unknown subject)"; end
ctx.SubjectRaw = L.SubjectRaw;
ctx.Timepoint = L.Timepoint; ctx.TimepointOrder = L.TimepointOrder; ctx.Group = L.Group;
ctx.InStudy = L.InStudy; ctx.TestMode = L.TestMode;
st = getf(s,'Settings',[]);
[h,stS] = settingsHashOf(st);
ctx.SettingsHash = h; ctx.Settings = stS;
stored = getf(s,'LatencyOffset',[]);
if isempty(stored), stored = tcol(tableOr(getf(s,'Peaks',table())),'LatencyOffset',[]); end
[ctx.ConductionDelay,ctx.TimeOffset,ctx.LatencyOffset] = latencyParts(L,s,stS,stored);
C = tableOr(getf(s,'Conditions',table()));
kp = rowStr(getf(s,'KeyParams',strings(1,0)));
if isempty(kp)
    pn = rowStr(getf(s,'ParamNames',strings(1,0)));
    kp = ["AcqMode" sortCI(pn(~ismember(pn,["Stimulus","AcqMode"])))];
    if ismember("Stimulus",pn), kp = ["Stimulus" kp]; end
end
ctx.Params = kp(~ismember(kp,["Stimulus","AcqMode"]));
ctx.ParamCols = paramColumns(ctx.Params);
nC = height(C);
if nC > 0 && ismember("Key",string(C.Properties.VariableNames))
    ctx.CondKeys = toStr(C.Key,nC);
else
    if nC > 0 && ~ismember("AcqMode",string(C.Properties.VariableNames))
        C.AcqMode = repmat("conventional",nC,1);
    end
    ctx.CondKeys = keyFor(C,kp);
end
ctx.Conditions = C;
end

function ctx = rawCtxFrom(it)
% A raw context for an item that carries a Session (tables()).
ctx = rawContext(it.Session,struct('Key',it.Key,'Labels',it.Labels),it.Key);
end

function R = rawTables(s,ctx,want,blockSize)
% trial_waves, blocks and block_waves of one session.
C = ctx.Conditions;
nC = height(C);
time = toDbl(getf(s,'Time',[]),[]);
rw = rowDbl(getf(s,'ResponseWindow',getf(ctx.Settings,'ResponseWindow',[0.5 8])),2);
Pk = tableOr(getf(s,'Peaks',table()));
pkKey = toStr(tcol(Pk,'Key',""),height(Pk));
pkState = toStr(tcol(Pk,'State',""),height(Pk));
pkLat = toDbl(tcol(Pk,'PeakLatency',NaN),height(Pk));
tw = {}; bl = {}; bw = {};
twr = []; blr = [];
for i = 1:nC
    [X,pol,ord,clean] = conditionSweeps(C,i,numel(time));
    if isempty(X), continue; end
    % Clean sweeps only, and only the samples every one of them holds (a
    % windowed condition's rows outside its extent are NaN).
    Xc = X(:,clean); pc = pol(clean); oc = ord(clean);
    fin = all(isfinite(Xc),2);
    if ~any(fin) || isempty(Xc), continue; end
    Xc = Xc(fin,:); tc = time(fin);
    rows = tc >= rw(1) & tc <= rw(2);
    pr = find(pkKey == ctx.CondKeys(i) & ismember(pkState,["auto","manual"]) & isfinite(pkLat));
    picks = [];
    if ~isempty(pr)
        picks = table(toStr(Pk.Wave(pr),numel(pr)),pkLat(pr),toDbl(tcol(Pk(pr,:),'TroughLatency',NaN),numel(pr)), ...
            'VariableNames',{'Wave','PeakLatency','TroughLatency'});
    end
    if ismember("trial_waves",want) && ~isempty(picks) && size(Xc,2) >= 2
        V = mabr.analysis.Peaks.singleTrial(tc,Xc,picks);
        % Peaks.singleTrial numbers the sweeps it was given; the export
        % numbers them in acquisition order, as every other table does.
        V.SweepOrder = reshape(oc(V.Sweep),[],1);
        tw{end+1} = V; twr(end+1) = i; %#ok<AGROW>
    end
    if any(ismember(["blocks","block_waves"],want))
        [Tb,Tw] = mabr.analysis.SingleTrial.blocks(Xc,pc,oc,rows,tc,blockSize,picks);
        bl{end+1} = Tb; bw{end+1} = Tw; blr(end+1) = i; %#ok<AGROW>
    end
end
R = struct();
if ismember("trial_waves",want), R.trial_waves = rawTrialWaves(tw,twr,ctx,C); end
if ismember("blocks",want), R.blocks = rawBlocks(bl,blr,ctx,C); end
if ismember("block_waves",want), R.block_waves = rawBlockWaves(bw,blr,ctx,C); end
end

function [X,pol,ord,clean] = conditionSweeps(C,i,nT)
% One condition's sweeps with polarity, acquisition order and the clean
% mask (not rejected, not excess).
X = []; pol = []; ord = []; clean = [];
vn = string(C.Properties.VariableNames);
if ~ismember("Sweeps",vn), return; end
S = C.Sweeps;
if iscell(S), X = S{i}; else, X = S(i,:); end
if isempty(X), return; end
X = double(X);
if size(X,1) ~= nT && size(X,2) == nT, X = X.'; end
N = size(X,2);
pol = cellRow(C,'Polarity',i,ones(1,N));
pol(~(pol < 0)) = 1; pol(pol < 0) = -1;
ord = cellRow(C,'SweepOrder',i,1:N);
rej = logical(cellRow(C,'Rejected',i,false(1,N)));
exc = logical(cellRow(C,'Excess',i,false(1,N)));
clean = ~rej & ~exc;
end

function v = cellRow(C,name,i,default)
% One condition's per-sweep vector from a cell column, else the default.
v = default;
if ~ismember(name,string(C.Properties.VariableNames)), return; end
x = C.(name);
if iscell(x), x = x{i}; else, x = x(i,:); end
if numel(x) == numel(default), v = reshape(double(x),1,[]); end
if islogical(default), v = logical(v); end
end

function t = rawTrialWaves(parts,rows,ctx,C)
n = sum(cellfun(@height,parts));
fx = identity(ctx,n);
ci = zeros(n,1); so = nan(n,1); wv = strings(n,1); lat = nan(n,1); p = lat; pn = lat; pj = lat;
k = 0;
for j = 1:numel(parts)
    V = parts{j}; m = height(V); r = k + (1:m);
    ci(r) = rows(j); so(r) = V.SweepOrder; wv(r) = string(V.Wave);
    lat(r) = V.PeakLatency; p(r) = V.PValue; pn(r) = V.PNValue; pj(r) = V.Proj;
    k = k + m;
end
fx = condIdentityAt(fx,table(),C,ci,n);
fx.condition_key = keyAt(ctx.CondKeys,ci);
fx.sweep_order = so; fx.wave = wv;
fx.lat_peak_ms = mabr.analysis.Peaks.reported(lat,ctx.LatencyOffset);
fx.lat_peak_raw_ms = lat;
fx.conduction_delay_ms = repmat(ctx.ConductionDelay,n,1);
fx.time_offset_ms = repmat(ctx.TimeOffset,n,1);
fx.p_uv = 1e6*p; fx.pn_uv = 1e6*pn; fx.proj = pj;
fx = tailCols(fx,ctx);
dyn.params = paramDyn(ctx,paramValues(C,ctx.Params,height(C),ci));
t = assemble("trial_waves",n,fx,dyn);
end

function t = rawBlocks(parts,rows,ctx,C)
n = sum(cellfun(@height,parts));
fx = identity(ctx,n);
ci = zeros(n,1); b = nan(n,1); nb = b; fo = b; lo = b; rn = b; rr = b;
k = 0;
for j = 1:numel(parts)
    V = parts{j}; m = height(V); r = k + (1:m);
    ci(r) = rows(j); b(r) = V.Block; nb(r) = V.N; fo(r) = V.FirstOrder; lo(r) = V.LastOrder;
    rn(r) = V.RN; rr(r) = V.ResponseRMS;
    k = k + m;
end
fx = condIdentityAt(fx,table(),C,ci,n);
fx.condition_key = keyAt(ctx.CondKeys,ci);
fx.block = b; fx.n = nb; fx.first_order = fo; fx.last_order = lo;
fx.rn_uv = 1e6*rn; fx.response_rms_uv = 1e6*rr;
fx = tailCols(fx,ctx);
dyn.params = paramDyn(ctx,paramValues(C,ctx.Params,height(C),ci));
t = assemble("blocks",n,fx,dyn);
end

function t = rawBlockWaves(parts,rows,ctx,C)
n = sum(cellfun(@height,parts));
fx = identity(ctx,n);
ci = zeros(n,1); b = nan(n,1); wv = strings(n,1); lat = b; amp = b;
k = 0;
for j = 1:numel(parts)
    V = parts{j}; m = height(V); r = k + (1:m);
    ci(r) = rows(j); b(r) = V.Block; wv(r) = string(V.Wave); lat(r) = V.PeakLatency; amp(r) = V.AmpPT;
    k = k + m;
end
fx = condIdentityAt(fx,table(),C,ci,n);
fx.condition_key = keyAt(ctx.CondKeys,ci);
fx.block = b; fx.wave = wv;
fx.lat_peak_ms = mabr.analysis.Peaks.reported(lat,ctx.LatencyOffset);
fx.lat_peak_raw_ms = lat;
fx.conduction_delay_ms = repmat(ctx.ConductionDelay,n,1);
fx.time_offset_ms = repmat(ctx.TimeOffset,n,1);
fx.amp_pt_uv = 1e6*amp;
fx = tailCols(fx,ctx);
dyn.params = paramDyn(ctx,paramValues(C,ctx.Params,height(C),ci));
t = assemble("block_waves",n,fx,dyn);
end

function files = writeSweeps(s,ctx,folder,opts)
% The sweeps of one session: Parquet long (one row per sample) and/or a
% MAT file of single matrices. CSV is refused.
files = emptyFiles();
fm = formatsFor("sweeps",opts.Formats);
C = ctx.Conditions;
time = toDbl(getf(s,'Time',[]),[]);
nT = numel(time);
tr = mabr.analysis.Peaks.reported(time,ctx.LatencyOffset);
dest = fullfile(folder,"sweeps");
for f = fm
    switch f
        case {"csv","xlsx"}
            files = [files; fileRow("sweeps",f,"",0, ...
                upper(f) + " refused for sweeps: a session is millions of rows; use parquet or mat")]; %#ok<AGROW>
        case "parquet"
            parts = {};
            for i = 1:height(C)
                [X,pol,ord] = conditionSweeps(C,i,nT);
                if isempty(X), continue; end
                rej = logical(cellRow(C,'Rejected',i,false(1,size(X,2))));
                exc = logical(cellRow(C,'Excess',i,false(1,size(X,2))));
                keepT = any(isfinite(X),2);
                Xk = X(keepT,:); tk = tr(keepT);
                [nr,ns] = size(Xk);
                m = nr*ns;
                fx = identity(ctx,m);
                ci = repmat(i,m,1);
                fx = condIdentityAt(fx,table(),C,ci,m);
                fx.condition_key = repmat(ctx.CondKeys(i),m,1);
                fx.sweep_order = reshape(repelem(ord(:),nr,1),[],1);
                fx.polarity = reshape(repelem(pol(:),nr,1),[],1);
                fx.rejected = reshape(repelem(rej(:),nr,1),[],1);
                fx.excess = reshape(repelem(exc(:),nr,1),[],1);
                fx.time_ms = repmat(tk(:),ns,1);
                fx.value_uv = 1e6*Xk(:);
                fx = tailCols(fx,ctx);
                dyn.params = paramDyn(ctx,paramValues(C,ctx.Params,height(C),ci));
                parts{end+1} = assemble("sweeps",m,fx,dyn); %#ok<AGROW>
            end
            t = stackParts("sweeps",parts);
            ensureFolder(dest);
            file = fullfile(dest,safeName(ctx.Id) + ".parquet");
            note = "";
            if height(t) > 0
                parquetwrite(char(file),parquetReady(t));
            else
                file = ""; note = "no sweeps";
            end
            files = [files; fileRow("sweeps","parquet",file,height(t),note)]; %#ok<AGROW>
        case "mat"
            ensureFolder(dest);
            Q = struct('Key',{},'Stimulus',{},'AcqMode',{},'Params',{},'Sweeps',{},'Info',{});
            nTot = 0;
            for i = 1:height(C)
                [X,pol,ord] = conditionSweeps(C,i,nT);
                if isempty(X), continue; end
                rej = logical(cellRow(C,'Rejected',i,false(1,size(X,2))));
                exc = logical(cellRow(C,'Excess',i,false(1,size(X,2))));
                pv = struct();
                for p = ctx.Params
                    pv.(matlab.lang.makeValidName(p)) = scalarDbl(tcolRow(C,p,i,NaN));
                end
                info = table(ord(:),pol(:),rej(:),exc(:),'VariableNames', ...
                    {'sweep_order','polarity','rejected','excess'});
                q = struct('Key',ctx.CondKeys(i), ...
                    'Stimulus',scalarStr(tcolRow(C,'Stimulus',i,"")), ...
                    'AcqMode',scalarStr(tcolRow(C,'AcqMode',i,"conventional")), ...
                    'Params',pv,'Sweeps',single(1e6*X),'Info',info);
                Q(end+1) = q; %#ok<AGROW>
                nTot = nTot + size(X,2);
            end
            MABRSweeps = struct('SessionId',ctx.Id,'Subject',ctx.Subject,'Unit',"uV", ...
                'TimeMs',tr(:),'TimeRawMs',time(:),'ConductionDelayMs',ctx.ConductionDelay, ...
                'TimeOffsetMs',ctx.TimeOffset,'LatencyOffsetMs',ctx.LatencyOffset,'SettingsHash',ctx.SettingsHash, ...
                'Conditions',Q);
            file = fullfile(dest,safeName(ctx.Id) + "_sweeps.mat");
            save(char(file),'MABRSweeps','-v7.3');
            files = [files; fileRow("sweeps","mat",file,nTot,"one single [nT x n] matrix (uV) per condition")]; %#ok<AGROW>
    end
end
end

% =========================================================================
%  Shared column builders
% =========================================================================
function fx = identity(c,n) %#ok<INUSD>
% The per-session identity columns every table starts with.
fx = struct('session_id',c.Id,'subject',c.Subject,'timepoint',c.Timepoint, ...
    'timepoint_order',c.TimepointOrder,'group',c.Group);
end

function fx = tailCols(fx,c)
% The per-session columns every table ends with.
fx.settings_hash = c.SettingsHash;
fx.test_mode = c.TestMode;
end

function fx = condIdentity(fx,C,c,n) %#ok<INUSD>
% stimulus and acq_mode of every condition row.
fx.stimulus = toStr(tcol(C,'Stimulus',""),n);
fx.acq_mode = toStr(tcol(C,'AcqMode',"conventional"),n);
end

function fx = condIdentityAt(fx,P,C,ci,n)
% stimulus and acq_mode of rows that point at condition rows ci (0 = none),
% preferring the row's own columns when P has them.
fx.stimulus = condText(C,'Stimulus',ci,"");
fx.acq_mode = condText(C,'AcqMode',ci,"conventional");
if height(P) == n && n > 0
    vn = string(P.Properties.VariableNames);
    if ismember("Stimulus",vn), s = toStr(P.Stimulus,n); fx.stimulus(s ~= "") = s(s ~= ""); end
    if ismember("AcqMode",vn), s = toStr(P.AcqMode,n); fx.acq_mode(s ~= "") = s(s ~= ""); end
end
end

function v = condText(C,name,ci,default)
% A text column of the conditions at rows ci (0 or out of range -> default).
n = numel(ci);
v = repmat(string(default),n,1);
if height(C) == 0, return; end
col = toStr(tcol(C,name,string(default)),height(C));
ok = ci >= 1 & ci <= height(C);
v(ok) = col(ci(ok));
end

function v = condTextVec(col,ci,default)
n = numel(ci);
v = repmat(string(default),n,1);
ok = ci >= 1 & ci <= numel(col);
v(ok) = col(ci(ok));
end

function k = keyAt(keys,ci)
k = strings(numel(ci),1);
ok = ci >= 1 & ci <= numel(keys);
k(ok) = keys(ci(ok));
end

function V = paramValues(C,params,nC,ci)
% [n x nP] parameter values of condition rows ci (default: every row).
if nargin < 4, ci = (1:nC).'; end
ci = ci(:);
V = nan(numel(ci),numel(params));
ok = ci >= 1 & ci <= height(C);
for k = 1:numel(params)
    col = toDbl(tcol(C,params(k),NaN),height(C));
    V(ok,k) = col(ci(ok));
end
end

function V = peakParams(P,C,ci,c,n)
% Parameters of peak rows: the row's own columns, else its condition's.
V = paramValues(C,c.Params,height(C),ci);
vn = string(P.Properties.VariableNames);
for k = 1:numel(c.Params)
    if ismember(c.Params(k),vn)
        x = toDbl(P.(c.Params(k)),n);
        V(isfinite(x),k) = x(isfinite(x));
    end
end
end

function D = paramDyn(c,V)
% Dynamic <params> columns.
D = emptyDyn();
for k = 1:numel(c.Params)
    u = paramUnitOf(c.Params(k));
    if c.Params(k) == "Level"
        de = "Stimulus parameter Level (dB; reference in level_ref).";
    else
        de = "Stimulus parameter " + c.Params(k) + ternary(u ~= "", " (" + u + ").", ".");
    end
    D(end+1) = struct('Placeholder',"<params>",'Column',c.ParamCols(k),'Source',c.Params(k), ...
        'Type',"double",'Unit',u,'Description',de,'Values',V(:,k)); %#ok<AGROW>
end
end

function D = groupDyn(c,V)
% Dynamic <group params> columns.
D = emptyDyn();
for k = 1:numel(c.GroupParams)
    u = paramUnitOf(c.GroupParams(k));
    D(end+1) = struct('Placeholder',"<group params>",'Column',c.GroupCols(k), ...
        'Source',c.GroupParams(k),'Type',"double",'Unit',u, ...
        'Description',"Series grouping parameter " + c.GroupParams(k) + ternary(u ~= "", " (" + u + ").", "."), ...
        'Values',V(:,k)); %#ok<AGROW>
end
end

function D = freeColumns(st,placeholder,what,n)
% Dynamic free label columns from a struct of values.
if nargin < 4, n = 1; end
D = emptyDyn();
if ~isstruct(st) || ~isscalar(st), return; end
src = struct();
if isfield(st,'MABRSourceNames__'), src = st.MABRSourceNames__; st = rmfield(st,'MABRSourceNames__'); end
used = allFixedColumns();
for f = string(fieldnames(st)).'
    v = st.(f);
    nm = f;
    if isfield(src,f), nm = string(src.(f)); end
    col = snake(nm);
    if ismember(col,used) || ismember(col,colsOf(D)), col = "free_" + col; end
    if isstring(v) || ischar(v) || iscellstr(v) || iscategorical(v)
        v = toStr(v,n); ty = "string";
    elseif islogical(v)
        v = toLgc(v,n); ty = "logical";
    elseif isnumeric(v)
        v = toDbl(v,n); ty = "double";
    elseif isdatetime(v)
        v = toDT(v,n); ty = "datetime";
    else
        continue
    end
    D(end+1) = struct('Placeholder',placeholder,'Column',col,'Source',nm,'Type',ty,'Unit',"", ...
        'Description',what + " """ + nm + """ (Project).",'Values',v); %#ok<AGROW>
end
end

function st = renameSource(st,f,orig)
% Remember a free column's original name across makeValidName.
if ~isfield(st,'MABRSourceNames__'), st.MABRSourceNames__ = struct(); end
st.MABRSourceNames__.(f) = orig;
end

function D = emptyDyn()
D = struct('Placeholder',{},'Column',{},'Source',{},'Type',{},'Unit',{},'Description',{},'Values',{});
end

function c = colsOf(S)
% The Column field of a struct array as a string row (empty: 1x0 string,
% never [] -- which no text comparison accepts).
c = strings(1,0);
if ~isempty(S), c = reshape(string({S.Column}),1,[]); end
end

function p = phOf(S)
% The Placeholder flags of schema rows (1x0 logical when there are none).
p = false(1,0);
if ~isempty(S), p = reshape([S.Placeholder],1,[]); end
end

function c = placeholdersOf(S)
c = strings(1,0);
if ~isempty(S), c = reshape(string({S.Placeholder}),1,[]); end
end

function c = paramColumns(params)
% Export columns of parameters, never colliding with a fixed column.
c = mabr.analysis.Export.columnName(params);
used = allFixedColumns();
for k = 1:numel(c)
    if ismember(c(k),used), c(k) = "stim_" + c(k); end
end
end

function u = paramUnitOf(p)
% The unit a parameter is carried in (mabr.stim.StimulusSet.paramUnit).
try
    u = string(mabr.stim.StimulusSet.paramUnit(char(p)));
catch
    switch lower(string(p))
        case "frequency", u = "kHz";
        case "level",     u = "dB";
        otherwise,        u = "";
    end
end
end

function s = snake(p)
% snake_case of a name (no unit suffix).
s = char(p);
s = regexprep(s,'([a-z0-9])([A-Z])','$1_$2');
s = regexprep(s,'([A-Z]+)([A-Z][a-z])','$1_$2');
s = lower(s);
s = regexprep(s,'[^a-z0-9]+','_');
s = regexprep(s,'^_+|_+$','');
if isempty(s), s = 'x'; end
if s(1) >= '0' && s(1) <= '9', s = ['x' s]; end
s = string(s);
end

% =========================================================================
%  Assembling and stacking tables
% =========================================================================
function t = assemble(name,n,fixed,dyn)
% A table in exactly the schema's order: fixed columns from the struct
% fixed (a scalar is expanded to n rows), placeholders from dyn. Errors on a
% schema column the builder did not supply or one the schema does not list.
spec = specFor(name);
large = ismember(name,mabr.analysis.Export.LargeTables);
vals = {}; names = strings(1,0); units = strings(1,0); descs = strings(1,0);
info = emptyDyn();
info = rmfield(info,'Values');
used = strings(1,0);
for k = 1:numel(spec)
    s = spec(k);
    if s.Placeholder
        D = dynFor(dyn,s.Column);
        for j = 1:numel(D)
            v = D(j).Values;
            if isscalar(v) && n ~= 1, v = repmat(v,n,1); end
            v = reshape(v,[],1);
            if numel(v) ~= n
                error('mabr:analysis:Export:internal','%s.%s has %d values for %d rows.',name,D(j).Column,numel(v),n);
            end
            if large && isstring(v), v = categorical(v); end
            if isnumeric(v), v = double(v); v(isinf(v)) = NaN; end
            vals{end+1} = v; %#ok<AGROW>
            names(end+1) = D(j).Column; units(end+1) = D(j).Unit; descs(end+1) = D(j).Description; %#ok<AGROW>
            info(end+1) = rmfield(D(j),'Values'); %#ok<AGROW>
        end
    else
        f = char(s.Column);
        if ~isfield(fixed,f)
            error('mabr:analysis:Export:internal','The %s table was built without its %s column.',name,f);
        end
        vals{end+1} = coerce(fixed.(f),n,s.Type,large); %#ok<AGROW>
        names(end+1) = s.Column; units(end+1) = s.Unit; descs(end+1) = s.Description; %#ok<AGROW>
        used(end+1) = s.Column; %#ok<AGROW>
    end
end
extra = setdiff(string(fieldnames(fixed)),used);
if ~isempty(extra)
    error('mabr:analysis:Export:internal','The %s table was given columns the schema does not list: %s.', ...
        name,strjoin(extra,', '));
end
t = table(vals{:},'VariableNames',cellstr(names));
t.Properties.VariableUnits = cellstr(units);
t.Properties.VariableDescriptions = cellstr(descs);
t.Properties.UserData = struct('ExportTable',name,'Dynamic',info,'Settings',emptySettingsList(),'Note',"");
end

function D = dynFor(dyn,placeholder)
% The dynamic entries a placeholder expands to.
D = emptyDyn();
switch placeholder
    case "<params>",               f = 'params';
    case "<group params>",         f = 'group';
    case "<free session columns>", f = 'free_session';
    case "<free subject columns>", f = 'free_subject';
    otherwise,                     f = '';
end
if isstruct(dyn) && ~isempty(f) && isfield(dyn,f) && ~isempty(dyn.(f))
    D = dyn.(f);
end
end

function v = coerce(v,n,type,large)
% One fixed column in its schema type, n rows.
switch type
    case "string"
        v = toStr(v,n);
        if large, v = categorical(v); end
    case {"double","integer"}
        v = toDbl(v,n);
        v(isinf(v)) = NaN;
    case "logical"
        v = toLgc(v,n);
    case "date"
        v = toDT(v,n);
        v.Format = 'yyyy-MM-dd';
    case "datetime"
        v = toDT(v,n);
        v.Format = 'yyyy-MM-dd''T''HH:mm:ss';
    otherwise
        if isscalar(v) && n ~= 1, v = repmat(v,n,1); end
        v = reshape(v,[],1);
end
end

function fx = fixTypes(fx,spec,n)
% Row-struct columns vertcat'ed from scalars: make every one n x 1.
for s = spec(~phOf(spec))
    f = char(s.Column);
    v = fx.(f);
    if isempty(v) && n > 0
        fx.(f) = fillByType(s.Type,n);
    end
end
end

function v = fillByType(type,n)
switch type
    case "string",              v = strings(n,1);
    case {"double","integer"},  v = nan(n,1);
    case "logical",             v = false(n,1);
    case {"date","datetime"},   v = NaT(n,1);
    otherwise,                  v = strings(n,1);
end
end

function T = stackParts(name,parts)
% The union of per-session tables of one kind (Export.stack).
spec = specFor(name);
parts = parts(cellfun(@istable,parts));
if isempty(parts)
    T = emptyTable(name);
    return
end
% Union of the dynamic columns, first-seen order, and of the settings.
dynAll = rmfield(emptyDyn(),'Values');
cls = containers.Map('KeyType','char','ValueType','any');
sets = emptySettingsList();
notes = strings(0,1);
for k = 1:numel(parts)
    ud = parts{k}.Properties.UserData;
    if isstruct(ud) && isfield(ud,'Dynamic')
        for d = reshape(ud.Dynamic,1,[])
            if ~ismember(d.Column,colsOf(dynAll)), dynAll(end+1) = d; end %#ok<AGROW>
        end
    end
    if isstruct(ud) && isfield(ud,'Settings')
        for s = reshape(ud.Settings,1,[]), sets = addSettings(sets,s.Hash,s.Settings); end
    end
    if isstruct(ud) && isfield(ud,'Note') && string(ud.Note) ~= "", notes(end+1) = string(ud.Note); end %#ok<AGROW>
    for v = string(parts{k}.Properties.VariableNames)
        x = parts{k}.(v);
        key = char(v);
        if ~isKey(cls,key)
            cls(key) = x([]);
        elseif ~strcmp(class(cls(key)),class(x))
            cls(key) = strings(0,1);          % conflicting classes: text
        end
    end
end
% The final column order: the schema's, placeholders expanded, unknown last.
order = strings(1,0);
for s = spec
    if s.Placeholder
        order = [order colsOf(dynAll(placeholdersOf(dynAll) == s.Column))]; %#ok<AGROW>
    else
        order(end+1) = s.Column; %#ok<AGROW>
    end
end
for k = 1:numel(parts)
    v = string(parts{k}.Properties.VariableNames);
    order = [order v(~ismember(v,order))]; %#ok<AGROW>
end
for k = 1:numel(parts)
    t = parts{k};
    h = height(t);
    for v = order
        key = char(v);
        if ~ismember(v,string(t.Properties.VariableNames))
            if isKey(cls,key)
                proto = cls(key);
            else
                % No part holds it: the schema's type says what is missing.
                j = find(colsOf(spec) == v & ~phOf(spec),1);
                if isempty(j), proto = nan(0,1); else, proto = fillByType(spec(j).Type,0); end
            end
            t.(key) = fillOf(proto,h);
        elseif isstring(cls(key)) && ~isstring(t.(key))
            t.(key) = toStr(t.(key),h);
        end
    end
    parts{k} = t(:,cellstr(order));
end
T = vertcat(parts{:});
% Units and descriptions from the schema and the dynamic entries.
un = strings(1,numel(order)); de = un;
for j = 1:numel(order)
    k = find(colsOf(spec) == order(j) & ~phOf(spec),1);
    d = find(colsOf(dynAll) == order(j),1);
    if ~isempty(k), un(j) = spec(k).Unit; de(j) = spec(k).Description;
    elseif ~isempty(d), un(j) = dynAll(d).Unit; de(j) = dynAll(d).Description; end
end
T.Properties.VariableUnits = cellstr(un);
T.Properties.VariableDescriptions = cellstr(de);
T.Properties.UserData = struct('ExportTable',name,'Dynamic',dynAll,'Settings',sets, ...
    'Note',strjoin(unique(notes,'stable'),"; "));
end

function t = emptyTable(name)
% A table with the schema's fixed columns and no rows.
spec = specFor(name);
fx = struct();
for s = spec(~phOf(spec))
    fx.(char(s.Column)) = fillByType(s.Type,0);
end
t = assemble(name,0,fx,struct());
end

function v = fillOf(proto,n)
% n missing values of a column's class.
if isstring(proto),         v = strings(n,1);
elseif iscategorical(proto), v = categorical(strings(n,1));
elseif islogical(proto),     v = false(n,1);
elseif isdatetime(proto),    v = NaT(n,1); v.Format = proto.Format;
elseif isnumeric(proto),     v = nan(n,1);
elseif iscell(proto),        v = cell(n,1);
else,                        v = strings(n,1);
end
end

function d = tableDynamic(t)
% The dynamic-column records a table carries.
d = rmfield(emptyDyn(),'Values');
ud = t.Properties.UserData;
if isstruct(ud) && isfield(ud,'Dynamic') && ~isempty(ud.Dynamic)
    d = ud.Dynamic;
    if isfield(d,'Values'), d = rmfield(d,'Values'); end
end
end

function names = tableNames(T)
% The fields of T that are tables, in order.
names = string(fieldnames(T)).';
names = names(arrayfun(@(f) istable(T.(f)),names));
end

function want = checkTables(want)
known = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables];
bad = want(~ismember(want,known));
if ~isempty(bad)
    error('mabr:analysis:Export:unknownTable','Unknown table(s) %s. Known: %s.', ...
        strjoin(bad,', '),strjoin(known,', '));
end
want = unique(want,'stable');
end

% =========================================================================
%  Writers
% =========================================================================
function files = emptyFiles()
files = table(strings(0,1),strings(0,1),strings(0,1),zeros(0,1),strings(0,1), ...
    'VariableNames',{'Table','Format','File','Rows','Note'});
end

function r = fileRow(tbl,fmt,file,rows,note)
r = table(string(tbl),string(fmt),string(file),double(rows),string(note), ...
    'VariableNames',{'Table','Format','File','Rows','Note'});
end

function F = formatsFor(name,formats)
% The formats one table is written in.
if isstruct(formats)
    if isfield(formats,name), F = formats.(name);
    elseif isfield(formats,'default'), F = formats.default;
    else, F = "csv";
    end
else
    F = formats;
end
F = unique(lower(string(F)),'stable');
F = F(F ~= "");
bad = F(~ismember(F,mabr.analysis.Export.Formats));
if ~isempty(bad)
    error('mabr:analysis:Export:badFormat','Unknown format(s) %s. Known: %s.', ...
        strjoin(bad,', '),strjoin(mabr.analysis.Export.Formats,', '));
end
F = reshape(F,1,[]);
end

function r = writeCsvTable(t,name,file,append)
% One table as CSV; a large table one session at a time, so the text it is
% converted to never holds the whole study.
if append && isfile(file)
    appendCsv(t,file);
    r = fileRow(name,"csv",file,height(t),"appended");
    return
end
if ismember(name,mabr.analysis.Export.LargeTables) && height(t) > 200000 && ...
        ismember('session_id',t.Properties.VariableNames)
    [~,~,g] = unique(string(t.session_id),'stable');      % sessions in their own order
    for k = 1:max(g)
        writeCsvRaw(t(g == k,:),file,k > 1);
    end
else
    writeCsvRaw(t,file,false);
end
r = fileRow(name,"csv",file,height(t),"");
end

function writeCsvRaw(t,file,append)
% writetable of the CSV form of a table (csvReady), UTF-8, text quoted.
c = csvReady(t);
args = {'Encoding','UTF-8','FileType','text','Delimiter',','};
if append, args = [args {'WriteMode','append'}]; end
q = quoteMode();
writetable(c,char(file),args{:},'QuoteStrings',q);
end

function q = quoteMode()
% "minimal" quotes only text that needs it (numbers and TRUE/FALSE stay
% bare, empty fields stay empty); MATLAB before it took only true.
persistent mode
if isempty(mode)
    mode = true;
    try
        d = tempname; mkdir(d);
        c = onCleanup(@() rmdir(d,'s'));
        writetable(table(1),fullfile(d,'q.csv'),'QuoteStrings','minimal');
        mode = 'minimal';
    catch
    end
end
q = mode;
end

function c = csvReady(t)
% The text form of a table for CSV and XLSX: a numeric column with a
% non-finite value becomes text ("%.10g", empty for NaN/Inf), every other
% number is rounded to ten significant digits, logicals become TRUE/FALSE,
% datetimes ISO 8601 and categoricals text (undefined empty).
c = t;
c.Properties.UserData = [];
c.Properties.VariableUnits = {};
c.Properties.VariableDescriptions = {};
for v = string(t.Properties.VariableNames)
    x = t.(v);
    if isnumeric(x)
        x = double(x);
        fin = isfinite(x);
        if all(fin)
            c.(v) = round(x,10,'significant');
        else
            s = missingStr(size(x));
            s(fin) = compose("%.10g",x(fin));
            c.(v) = s;
        end
    elseif islogical(x)
        c.(v) = categorical(double(x),[0 1],{'FALSE','TRUE'});
    elseif isdatetime(x)
        if strcmp(x.Format,'yyyy-MM-dd'), fmt = 'yyyy-MM-dd'; else, fmt = 'yyyy-MM-dd''T''HH:mm:ss'; end
        s = string(x,fmt);
        c.(v) = s;
    elseif iscategorical(x)
        c.(v) = string(x);
    elseif iscell(x)
        c.(v) = toStr(x,height(t));
    end
end
end

function appendCsv(t,file)
% Add rows to a CSV already written: in its column order, missing columns
% empty; a column the file does not have yet means rewriting it with the
% union (rows read back as text).
fid = fopen(file,'r','n','UTF-8');
hdr = fgetl(fid);
fclose(fid);
if ~ischar(hdr), hdr = ''; end
cols = strtrim(string(split(string(hdr),",")));
cols = erase(cols,"""");
cols = cols(cols ~= "").';
new = string(t.Properties.VariableNames);
if isempty(cols)
    writeCsvRaw(t,file,false);
    return
end
if all(ismember(new,cols))
    c = t;
    for v = cols(~ismember(cols,new))
        c.(char(v)) = missingStr(height(c),1);
    end
    c = c(:,cellstr(cols));
    writeCsvRaw(c,file,true);
    return
end
% The file lacks a column: read it back as text and rewrite the union.
o = detectImportOptions(file,'Delimiter',',','Encoding','UTF-8','TextType','string');
o = setvartype(o,'string');
o.VariableNamingRule = 'preserve';
old = readtable(file,o);
union = [cols new(~ismember(new,cols))];
c = csvReady(t);
for v = string(c.Properties.VariableNames)
    c.(char(v)) = toStr(c.(char(v)),height(c));
end
for v = union
    if ~ismember(v,string(old.Properties.VariableNames)), old.(char(v)) = missingStr(height(old),1); end
    if ~ismember(v,string(c.Properties.VariableNames)), c.(char(v)) = missingStr(height(c),1); end
end
both = [old(:,cellstr(union)); c(:,cellstr(union))];
for v = string(both.Properties.VariableNames)
    x = both.(char(v));
    x(x == "") = missing;
    both.(char(v)) = x;
end
writetable(both,char(file),'Encoding','UTF-8','FileType','text','Delimiter',',', ...
    'QuoteStrings',quoteMode());
end

function [r,xlsx] = writeXlsxTable(t,name,xlsx,opts)
% One table as a sheet of the export workbook.
mx = mabr.analysis.Export.XLSXMaxRows;
if ~ismember(name,mabr.analysis.Export.XLSXTables)
    r = fileRow(name,"xlsx","",0,"not written: XLSX holds only the small tables (" + ...
        strjoin(mabr.analysis.Export.XLSXTables,", ") + ")");
    return
end
if height(t) > mx
    r = fileRow(name,"xlsx","",0,sprintf("not written: %d rows exceed the %d an Excel sheet holds", ...
        height(t),mx));
    return
end
sheet = char(opts.Prefix + name);
sheet = regexprep(sheet,'[:\\/?*\[\]]','_');
sheet = sheet(1:min(31,end));
base = sheet; k = 1;
while ismember(string(sheet),xlsx.Sheets)
    k = k + 1; sfx = sprintf('_%d',k);
    sheet = [base(1:min(31-numel(sfx),end)) sfx];
end
c = csvReady(t);
% Excel holds numbers as numbers: undo the text form of numeric columns
% (NaN is written as an empty cell).
for v = string(t.Properties.VariableNames)
    if isnumeric(t.(v))
        x = double(t.(v)); x(~isfinite(x)) = NaN;
        c.(v) = x;
    end
end
if ~xlsx.Started && ~opts.Append
    mode = 'replacefile';
else
    mode = 'overwritesheet';
end
writetable(c,char(xlsx.File),'Sheet',sheet,'WriteMode',mode);
xlsx.Started = true;
xlsx.Sheets(end+1) = string(sheet);
r = fileRow(name,"xlsx",xlsx.File,height(t),"sheet " + string(sheet));
end

function r = writeParquetTable(t,name,folder,opts)
% A small table as one Parquet file; a large one as one file per session in
% a folder named after the table (an arrow dataset).
large = ismember(name,mabr.analysis.Export.LargeTables) && ismember('session_id',t.Properties.VariableNames);
if large
    dest = fullfile(folder,name);
    ensureFolder(dest);
    if ~opts.Append
        old = dir(fullfile(dest,'*.parquet'));
        for k = 1:numel(old), delete(fullfile(old(k).folder,old(k).name)); end
    end
    if height(t) == 0
        r = fileRow(name,"parquet","",0,"no rows");
        return
    end
    ids = string(t.session_id);
    [u,~,g] = unique(ids,'stable');
    for k = 1:numel(u)
        parquetwrite(char(fullfile(dest,safeName(u(k)) + ".parquet")),parquetReady(t(g == k,:)));
    end
    r = fileRow(name,"parquet",dest,height(t),sprintf("%d files, one per session (an arrow dataset)",numel(u)));
else
    file = fullfile(folder,opts.Prefix + name + ".parquet");
    if opts.Append && isfile(file)
        % Another session's table need not hold the same columns (a click
        % session has no frequency_khz): the union, as stack() builds it.
        old = parquetread(char(file));
        t = stackParts(name,{old,parquetReady(t)});
    end
    parquetwrite(char(file),parquetReady(t));
    r = fileRow(name,"parquet",file,height(t),"");
end
end

function p = parquetReady(t)
% Parquet takes NaN but no Inf, and no table properties of ours.
p = t;
p.Properties.UserData = [];
for v = string(t.Properties.VariableNames)
    x = t.(v);
    if isnumeric(x)
        x = double(x); x(isinf(x)) = NaN; p.(v) = x;
    elseif iscell(x)
        p.(v) = toStr(x,height(t));
    end
end
end

function r = writeMat(S,file,append)
% The tables as one struct, MABRExport, in one MAT-file.
if append && isfile(file)
    old = load(char(file),'MABRExport');
    if isfield(old,'MABRExport')
        for f = string(fieldnames(old.MABRExport)).'
            if isfield(S,f)
                S.(f) = mabr.analysis.Export.stack({old.MABRExport.(f),S.(f)},f);
            else
                S.(f) = old.MABRExport.(f);
            end
        end
    end
end
MABRExport = S;
w = whos('MABRExport');
if w.bytes > 1.9e9, ver = '-v7.3'; else, ver = '-v7'; end
save(char(file),'MABRExport',ver);
names = string(fieldnames(S));
r = emptyFiles();
for f = names.'
    r = [r; fileRow(f,"mat",file,height(S.(f)),"MABRExport." + f)]; %#ok<AGROW>
end
end

function s = safeName(id)
% A session key as a file name: anything but letters, digits, . _ - becomes _.
s = regexprep(char(id),'[^A-Za-z0-9._-]','_');
if isempty(s), s = 'session'; end
s = string(s);
end

function ensureFolder(f)
if ~isfolder(f), mkdir(char(f)); end
end

function writeText(file,txt)
% UTF-8 text, newline endings.
fid = fopen(char(file),'w','n','UTF-8');
if fid < 0
    error('mabr:analysis:Export:write','Cannot write %s.',file);
end
c = onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(char(txt),'UTF-8'));
end

% =========================================================================
%  The R script
% =========================================================================
function paths = rPaths(folder,files,T)
% Table -> path relative to the export folder, CSV preferred over Parquet.
paths = containers.Map('KeyType','char','ValueType','any');
if istable(files) && height(files) > 0
    for fmt = ["parquet","csv"]
        r = files(string(files.Format) == fmt & string(files.File) ~= "",:);
        for k = 1:height(r)
            paths(char(r.Table(k))) = relativeTo(folder,string(r.File(k)));
        end
    end
else
    for name = tableNames(T)
        paths(char(name)) = "mabr_" + name + ".csv";
    end
end
end

function p = relativeTo(folder,p)
% Paths below folder, relative to it, with forward slashes.
f = replace(string(folder),"\","/");
p = replace(string(p),"\","/");
pre = f + "/";
k = startsWith(p,pre,'IgnoreCase',true);
p(k) = extractAfter(p(k),strlength(pre));
end

function txt = rScriptText(folder,paths,hasBlocks)
% The text of mabr_import.R.
created = mabr.analysis.Stats.isoTime(datetime('now'));
L = strings(0,1);
L(end+1) = "# mabr_import.R -- read a MABR export into R, and the models it was made for";
L(end+1) = "#";
L(end+1) = "# Written by mabr.analysis.Export on " + created + " (MABR " + mabrVersion() + ", commit " + gitCommit() + ").";
L(end+1) = "# Every table is tidy -- one row per observation -- and keyed by session_id;";
L(end+1) = "# mabr_columns.csv says what each column is and in which unit.";
L(end+1) = "#";
L(end+1) = "# THRESHOLDS ARE CENSORED DATA. A series with no response at the loudest level";
L(end+1) = "# tested has a threshold ABOVE that level -- it is not missing -- and dropping";
L(end+1) = "# it, or imputing a number for it, biases exactly the comparison a noise-exposure";
L(end+1) = "# study makes. cens says how each row is censored, in the coding brms cens() and";
L(end+1) = "# survival::Surv(type = ""interval2"") read:";
L(end+1) = "#   none      threshold_db is the estimate (thr_lo_db = thr_hi_db = threshold_db)";
L(end+1) = "#   left      at or below threshold_db, the lowest level tested (thr_lo_db NA)";
L(end+1) = "#   right     above threshold_db, the highest level tested (thr_hi_db NA)";
L(end+1) = "#   interval  between thr_lo_db and thr_hi_db; threshold_db is the reported point";
L(end+1) = "# A row with an empty cens (excluded, too few levels) has no threshold.";
L(end+1) = "#";
L(end+1) = "# Usage: source(""mabr_import.R"") reads every table into a data frame. The models";
L(end+1) = "# at the end run only with RUN_MODELS <- TRUE (brms takes minutes); they need";
L(end+1) = "# brms, survival, lmerTest, glmmTMB and emmeans.";
L(end+1) = "";
L(end+1) = "export_dir <- """ + replace(string(folder),"\","/") + """";
L(end+1) = "if (!dir.exists(export_dir)) export_dir <- getwd()   # moved? run it from the export folder";
L(end+1) = "RUN_MODELS <- FALSE";
L(end+1) = "";
L(end+1) = "suppressPackageStartupMessages({";
L(end+1) = "  library(readr)";
L(end+1) = "  library(dplyr)";
L(end+1) = "})";
L(end+1) = "";
L(end+1) = "# The file of each table (a folder is an arrow dataset: one Parquet file per session)";
L(end+1) = "mabr_files <- list(";
ks = string(keys(paths));
order = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables];
ks = [order(ismember(order,ks)) ks(~ismember(ks,order))];
for k = 1:numel(ks)
    sep = ","; if k == numel(ks), sep = ""; end
    L(end+1) = "  " + ks(k) + " = """ + string(paths(char(ks(k)))) + """" + sep; %#ok<AGROW>
end
L(end+1) = ")";
L(end+1) = "";
L(end+1) = "# ---- reading -------------------------------------------------------------";
L(end+1) = "mabr_dict <- NULL";
L(end+1) = "if (file.exists(file.path(export_dir, ""mabr_columns.csv"")))";
L(end+1) = "  mabr_dict <- readr::read_csv(file.path(export_dir, ""mabr_columns.csv""),";
L(end+1) = "                               col_types = readr::cols(.default = ""c""), progress = FALSE)";
L(end+1) = "";
L(end+1) = "# Column types from the dictionary, so a column is never guessed from its first rows";
L(end+1) = "mabr_types <- function(table) {";
L(end+1) = "  if (is.null(mabr_dict)) return(readr::cols(.default = readr::col_guess()))";
L(end+1) = "  d <- mabr_dict[mabr_dict$table == table, ]";
L(end+1) = "  code <- c(string = ""c"", double = ""d"", integer = ""d"", logical = ""l"", date = ""D"", datetime = ""c"")";
L(end+1) = "  ct <- code[d$type]";
L(end+1) = "  keep <- !is.na(ct)";
L(end+1) = "  ct <- as.list(unname(ct[keep]))";
L(end+1) = "  names(ct) <- d$column[keep]";
L(end+1) = "  do.call(readr::cols, c(ct, list(.default = readr::col_guess())))";
L(end+1) = "}";
L(end+1) = "";
L(end+1) = "# Factors in the study's order; ISO 8601 times as local date-times";
L(end+1) = "mabr_prepare <- function(d, table) {";
L(end+1) = "  if (all(c(""timepoint"", ""timepoint_order"") %in% names(d)))";
L(end+1) = "    d <- dplyr::mutate(d, timepoint = factor(timepoint, levels = unique(timepoint[order(timepoint_order)])))";
L(end+1) = "  for (v in intersect(c(""subject"", ""group"", ""session_id""), names(d)))";
L(end+1) = "    d[[v]] <- factor(d[[v]])";
L(end+1) = "  if (!is.null(mabr_dict)) {";
L(end+1) = "    tv <- mabr_dict$column[mabr_dict$table == table & mabr_dict$type == ""datetime""]";
L(end+1) = "    for (v in intersect(tv, names(d)))";
L(end+1) = "      if (is.character(d[[v]])) d[[v]] <- as.POSIXct(d[[v]], format = ""%Y-%m-%dT%H:%M:%S"", tz = """")";
L(end+1) = "  }";
L(end+1) = "  d";
L(end+1) = "}";
L(end+1) = "";
L(end+1) = "mabr_read <- function(table) {";
L(end+1) = "  f <- mabr_files[[table]]";
L(end+1) = "  if (is.null(f)) return(NULL)";
L(end+1) = "  p <- file.path(export_dir, f)";
L(end+1) = "  if (!file.exists(p) && !dir.exists(p)) return(NULL)";
L(end+1) = "  if (grepl(""\\.csv$"", f)) {";
L(end+1) = "    d <- readr::read_csv(p, na = c("""", ""NA"", ""NaN""), col_types = mabr_types(table), progress = FALSE)";
L(end+1) = "  } else {";
L(end+1) = "    if (!requireNamespace(""arrow"", quietly = TRUE))";
L(end+1) = "      stop(""Reading "", f, "" needs the arrow package: install.packages('arrow')"")";
L(end+1) = "    d <- if (dir.exists(p)) dplyr::collect(arrow::open_dataset(p)) else arrow::read_parquet(p)";
L(end+1) = "  }";
L(end+1) = "  mabr_prepare(d, table)";
L(end+1) = "}";
L(end+1) = "";
for name = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables]
    if name == "sweeps"
        % A study's sweeps do not fit in memory: open the dataset and filter.
        L(end+1) = "# sweeps: one row per sample -- open, filter, then collect:"; %#ok<AGROW>
        L(end+1) = "# sweeps <- arrow::open_dataset(file.path(export_dir, mabr_files$sweeps))"; %#ok<AGROW>
        continue
    end
    L(end+1) = sprintf('%-14s<- mabr_read("%s")',name,name); %#ok<AGROW>
end
L(end+1) = "";
L(end+1) = "# Frequency as a factor in ascending order; a click series is named by its stimulus";
L(end+1) = "mabr_freq <- function(d) {";
L(end+1) = "  f <- if (""frequency_khz"" %in% names(d)) d$frequency_khz else rep(NA_real_, nrow(d))";
L(end+1) = "  s <- if (""stimulus"" %in% names(d)) as.character(d$stimulus) else rep("""", nrow(d))";
L(end+1) = "  lab <- ifelse(is.na(f), s, paste(as.character(f), ""kHz""))";
L(end+1) = "  factor(lab, levels = unique(lab[order(is.na(f), f)]))";
L(end+1) = "}";
L(end+1) = "";
L(end+1) = "# ---- thresholds: censored, one row per subject x timepoint x series --------";
L(end+1) = "if (!is.null(thresholds)) {";
L(end+1) = "  thr <- dplyr::filter(thresholds, is_primary, used_in_study, !test_mode,";
L(end+1) = "                      cens %in% c(""none"", ""left"", ""right"", ""interval""))";
L(end+1) = "  thr$freq_f <- mabr_freq(thr)";
L(end+1) = "  # brms reads an interval row as y < threshold <= y2: lower bound in y, upper in thr_upper_db";
L(end+1) = "  thr$y <- ifelse(thr$cens == ""interval"", thr$thr_lo_db, thr$threshold_db)";
L(end+1) = "";
L(end+1) = "  if (RUN_MODELS && requireNamespace(""brms"", quietly = TRUE)) {";
L(end+1) = "    # Primary model: a censored Gaussian mixed model of the threshold";
L(end+1) = "    m_thr <- brms::brm(y | cens(cens, thr_upper_db) ~ group*timepoint*freq_f + (1 + timepoint | subject),";
L(end+1) = "                       data = thr, family = gaussian(), chains = 4, cores = 4, seed = 1)";
L(end+1) = "    print(summary(m_thr))";
L(end+1) = "  }";
L(end+1) = "  if (RUN_MODELS && requireNamespace(""survival"", quietly = TRUE)) {";
L(end+1) = "    # Frequentist alternative: interval-censored regression, subjects as clusters";
L(end+1) = "    # (interval2: thr_lo_db NA = left-censored, thr_hi_db NA = right-censored)";
L(end+1) = "    library(survival)";
L(end+1) = "    m_surv <- survival::survreg(Surv(thr_lo_db, thr_hi_db, type = ""interval2"") ~ group*timepoint*freq_f + cluster(subject),";
L(end+1) = "                                data = thr, dist = ""gaussian"")";
L(end+1) = "    print(summary(m_surv))";
L(end+1) = "    # Group differences at each frequency, Holm-adjusted";
L(end+1) = "    if (requireNamespace(""emmeans"", quietly = TRUE))";
L(end+1) = "      print(emmeans::emmeans(m_surv, pairwise ~ group | freq_f, adjust = ""holm""))";
L(end+1) = "  }";
L(end+1) = "  # Sensitivity analysis ONLY -- imputed values are not measurements (no response";
L(end+1) = "  # at the highest level + one step, every level responding at the lowest - one step):";
L(end+1) = "  # m_imp <- lmerTest::lmer(threshold_imputed_db ~ group*timepoint*freq_f + (1|subject), data = thr)";
L(end+1) = "}";
L(end+1) = "";
L(end+1) = "# ---- suprathreshold amplitude and latency -------------------------------------";
L(end+1) = "if (!is.null(peaks)) {";
L(end+1) = "  pk <- dplyr::filter(peaks, used_in_study, !test_mode, state %in% c(""auto"", ""manual""),";
L(end+1) = "                     detectable, level_re_thr_db >= 10, amp_pt_uv > 0)";
L(end+1) = "  if (!is.null(conditions))   # recording quality per condition: residual noise, sweeps used";
L(end+1) = "    pk <- dplyr::left_join(pk, conditions[, c(""session_id"", ""condition_key"", ""rn_uv"", ""n_used"")],";
L(end+1) = "                           by = c(""session_id"", ""condition_key""))";
L(end+1) = "  pk$level_c <- (pk$level_re_thr_db - mean(pk$level_re_thr_db, na.rm = TRUE)) / 10   # tens of dB, centred";
L(end+1) = "  pk$freq_f <- mabr_freq(pk)";
L(end+1) = "  pk_w <- dplyr::filter(pk, wave == ""I"")   # wave I, the synaptopathy endpoint: change as needed";
L(end+1) = "";
L(end+1) = "  if (RUN_MODELS && requireNamespace(""lmerTest"", quietly = TRUE)) {";
L(end+1) = "    # Amplitude on a log scale: a proportional loss is one coefficient at every level";
L(end+1) = "    m_amp <- lmerTest::lmer(log(amp_pt_uv) ~ group*timepoint*level_c + rn_uv + n_used + (1 + level_c | subject) + (1 | subject:session_id),";
L(end+1) = "                            data = pk_w)";
L(end+1) = "    print(summary(m_amp))";
L(end+1) = "    # Latency of the same wave (ms re sound arrival when a conduction delay was set: raw minus conduction_delay_ms and time_offset_ms)";
L(end+1) = "    m_lat <- lmerTest::lmer(lat_peak_ms ~ group*timepoint*level_c + (1 + level_c | subject) + (1 | subject:session_id),";
L(end+1) = "                            data = pk_w)";
L(end+1) = "    print(summary(m_lat))";
L(end+1) = "  }";
L(end+1) = "  if (RUN_MODELS && requireNamespace(""glmmTMB"", quietly = TRUE)) {";
L(end+1) = "    # Alternative: a Gamma GLMM of the amplitude itself, log link";
L(end+1) = "    m_amp_g <- glmmTMB::glmmTMB(amp_pt_uv ~ group*timepoint*level_c + rn_uv + n_used + (1 + level_c | subject) + (1 | subject:session_id),";
L(end+1) = "                                family = Gamma(link = ""log""), data = pk_w)";
L(end+1) = "    print(summary(m_amp_g))";
L(end+1) = "  }";
L(end+1) = "}";
L(end+1) = "# With few subjects, random slopes such as (1 + level_c | subject) and";
L(end+1) = "# (1 + timepoint | subject) often end in ""boundary (singular) fit"": simplify to";
L(end+1) = "# (1 | subject) rather than report a singular fit.";
if hasBlocks
    L(end+1) = "";
    L(end+1) = "# ---- drift within a run: consecutive polarity-balanced block averages -----------";
    L(end+1) = "if (!is.null(blocks)) {";
    L(end+1) = "  bl <- blocks";
    L(end+1) = "  bl$block_c <- bl$block - 1";
    L(end+1) = "  if (RUN_MODELS && requireNamespace(""lmerTest"", quietly = TRUE)) {";
    L(end+1) = "    # Does the block response fall (adaptation, drying electrodes) as sweeps accumulate?";
    L(end+1) = "    m_drift <- lmerTest::lmer(response_rms_uv ~ block_c + rn_uv + (1 + block_c | subject) + (1 | subject:session_id),";
    L(end+1) = "                              data = bl)";
    L(end+1) = "    print(summary(m_drift))";
    L(end+1) = "  }";
    L(end+1) = "}";
end
txt = strjoin(L,newline) + newline;
end

% =========================================================================
%  Estimate
% =========================================================================
function n = estimateRows(name,it,opts)
% Rows one session contributes to a table.
R = it.Results; C = R.Conditions; P = R.Peaks;
nC = height(C);
switch name
    case "sessions",   n = 1;
    case "subjects",   n = 0;
    case "conditions", n = nC;
    case "thresholds"
        n = height(R.Thresholds);
        if opts.ThresholdsAll, n = n*numel(builtinMethods()); end
    case "peaks",      n = height(P);
    case "peak_measures"
        k = picksPerCondition(P);
        n = sum(max(k-1,0) + (k >= 3) + (k >= 2));
    case "io_slopes"
        if height(P) == 0 || ~ismember("Wave",string(P.Properties.VariableNames)), n = 0;
        else
            key = toStr(tcol(P,'Key',""),height(P));
            sk = seriesKeyOf(key,it.Ctx.LevelParam);
            n = 2*numel(unique(sk + "|" + toStr(P.Wave,height(P))));
        end
    case "waveforms"
        time = toDbl(getf(R.Summary,'Time',[]),[]);
        t0 = time - it.Ctx.LatencyOffset;
        nW = sum(t0 >= opts.WaveformWindow(1) & t0 <= opts.WaveformWindow(2));
        M = R.Means; nK = 0;
        if isstruct(M) && isfield(M,'Keys'), nK = numel(M.Keys); elseif ismember("Sweeps",string(C.Properties.VariableNames)), nK = nC; end
        n = nK*3*nW;
    case "notes"
        Nt = it.Notes;
        if istable(Nt), n = height(Nt); elseif isstruct(Nt), n = numel(Nt); else, n = 0; end
    case "trials"
        SI = R.SweepInfo;
        if isstruct(SI) && isfield(SI,'Cond'), n = numel(SI.Cond); else, n = 0; end
    case "trial_waves"
        nc = toDbl(tcol(C,'nClean',0),nC);
        k = picksPerConditionKeys(P,it.Ctx.CondKeys);
        n = sum(nc.*k,'omitnan');
    case {"blocks","block_waves"}
        nc = toDbl(tcol(C,'nClean',0),nC);
        nb = floor(nc/opts.BlockSize);
        if name == "block_waves", nb = nb.*picksPerConditionKeys(P,it.Ctx.CondKeys); end
        n = sum(nb,'omitnan');
    case "sweeps"
        time = toDbl(getf(R.Summary,'Time',[]),[]);
        n = sum(toDbl(tcol(C,'nSweeps',0),nC),'omitnan')*numel(time);
    otherwise
        n = 0;
end
end

function k = picksPerCondition(P)
% Picked waves per condition key (auto/manual with a latency).
k = zeros(0,1);
if height(P) == 0 || ~all(ismember(["Key","State","PeakLatency"],string(P.Properties.VariableNames))), return; end
use = ismember(toStr(P.State,height(P)),["auto","manual"]) & isfinite(toDbl(P.PeakLatency,height(P)));
if ~any(use), return; end
key = toStr(P.Key,height(P));
[~,~,g] = unique(key(use));
k = accumarray(g(:),1);
end

function k = picksPerConditionKeys(P,keys)
k = zeros(numel(keys),1);
if height(P) == 0 || ~all(ismember(["Key","State","PeakLatency"],string(P.Properties.VariableNames))), return; end
use = ismember(toStr(P.State,height(P)),["auto","manual"]) & isfinite(toDbl(P.PeakLatency,height(P)));
key = toStr(P.Key,height(P));
for i = 1:numel(keys), k(i) = sum(use & key == keys(i)); end
end

function [c,p] = bytesPerRow(name,nPar)
% Rough bytes per row of a table in CSV and Parquet.
spec = specFor(name);
c = 2; p = 0;
for s = spec
    if s.Placeholder
        m = nPar; if s.Column ~= "<params>" && s.Column ~= "<group params>", m = 2; end
        c = c + 9*m; p = p + 2.5*m;
        continue
    end
    switch s.Type
        case {"double","integer"}, c = c + 9;  p = p + 2.5;
        case "logical",            c = c + 6;  p = p + 0.2;
        case {"date","datetime"},  c = c + 20; p = p + 2;
        otherwise,                 c = c + 14; p = p + 0.4;
    end
end
end

% =========================================================================
%  Thresholds and series helpers
% =========================================================================
function m = builtinMethods()
% The named methods an all-methods export computes (custom is no method).
ids = mabr.analysis.SeriesThreshold.Ids;
m = ids(ids ~= "custom");
end

function c = metricColumnOf(m,settings)
% The Conditions column a method's metric reads ("" = always there).
try
    r = mabr.analysis.SeriesThreshold.resolve(m,settings);
    metric = r.Metric;
catch
    metric = "";
end
switch metric
    case "power",     c = "PowerP";
    case "fsp",       c = "FspP";
    case "splithalf", c = "SplitR";
    case "xcorr",     c = "XCorrUp";
    case "snr",       c = "SNR";
    case "detection", c = "p";
    otherwise,        c = "";
end
end

function v = rnAt(C,idx,lp,th)
% Residual noise (uV) at the series level nearest a threshold.
v = NaN;
if isempty(idx) || ~isfinite(th) || ~ismember("RN",string(C.Properties.VariableNames)), return; end
lev = toDbl(tcol(C,lp,NaN),height(C)); lev = lev(idx);
rn = toDbl(C.RN,height(C)); rn = rn(idx);
ok = isfinite(lev) & isfinite(rn);
if ~any(ok), return; end
lev = lev(ok); rn = rn(ok);
d = abs(lev - th);
k = find(d == min(d));
[~,j] = max(lev(k));          % a tie goes to the louder level
v = 1e6*rn(k(j));
end

function u = usedFor(c,sk)
% used_in_study for series keys: the study's choice, else the session's.
sk = string(sk);
u = repmat(c.DefaultUsed,size(sk));
if isempty(c.UsedKeys), return; end
[tf,loc] = ismember(sk,c.UsedKeys);
u(tf) = c.UsedVals(loc(tf));
end

function sk = seriesKeyOf(keys,lp)
% Condition keys without the level pair: the series keys.
keys = string(keys);
sk = keys;
if lp == "" || isempty(keys), return; end
for i = 1:numel(keys)
    p = split(keys(i),"|");
    nm = extractBefore(p,"=");
    nm(ismissing(nm)) = p(ismissing(nm));
    sk(i) = strjoin(p(nm ~= lp),"|");
end
end

function sk = peakSeries(P,key,c)
% A peaks table's series keys: its own column, else derived.
n = height(P);
if ismember("SeriesKey",string(P.Properties.VariableNames))
    sk = toStr(P.SeriesKey,n);
    miss = sk == "";
    if any(miss), sk(miss) = seriesKeyOf(key(miss),c.LevelParam); end
else
    sk = seriesKeyOf(key,c.LevelParam);
end
end

function lev = peakLevels(P,C,ci,c)
% The level of each peak row.
n = height(P);
vn = string(P.Properties.VariableNames);
if ismember("Level",vn) && (c.LevelParam == "" || c.LevelParam == "Level" || ~ismember(c.LevelParam,vn))
    lev = toDbl(P.Level,n);
elseif c.LevelParam ~= "" && ismember(c.LevelParam,vn)
    lev = toDbl(P.(c.LevelParam),n);
else
    lev = nan(n,1);
end
miss = isnan(lev);
if any(miss) && c.LevelParam ~= ""
    cl = toDbl(tcol(C,c.LevelParam,NaN),height(C));
    ok = miss & ci >= 1 & ci <= height(C);
    lev(ok) = cl(ci(ok));
end
end

function lp = levelParamOf(R)
% The level parameter: the results' own, the thresholds', else a name
% Session recognizes as a level.
S = R.Summary;
lp = string(getf(S,'LevelParam',""));
if lp ~= "" && ~ismissing(lp), return; end
T = R.Thresholds;
if height(T) > 0 && ismember("LevelParam",string(T.Properties.VariableNames))
    v = toStr(T.LevelParam,height(T));
    v = v(v ~= "");
    if ~isempty(v), lp = v(1); return; end
end
try
    aliases = mabr.analysis.Session.LevelAliases;
catch
    aliases = ["Level","SoundLevel","Intensity","dB","Attenuation"];
end
pn = S.KeyParams;
k = find(ismember(lower(pn),lower(aliases)),1);
if ~isempty(k), lp = pn(k); else, lp = ""; end
end

function k = keyFor(C,kp)
% Condition (or series) keys of a table's rows from its key columns (10 §1.4).
n = height(C);
k = strings(n,1);
vn = string(C.Properties.VariableNames);
first = true;
for p = kp
    if ismember(p,vn)
        v = C.(p);
    elseif p == "AcqMode"
        v = repmat("conventional",n,1);
    else
        continue
    end
    if iscell(v), v = string(v); end
    s = mabr.analysis.Stats.keyValue(v);
    s = reshape(s,[],1);
    if first
        k = p + "=" + s;
        first = false;
    else
        k = k + "|" + p + "=" + s;
    end
end
end

function [np,nn] = polarityCounts(C)
% Clean sweeps of each polarity of a v1 Conditions table.
n = height(C);
np = nan(n,1); nn = nan(n,1);
for i = 1:n
    pol = double(C.Polarity{i});
    keep = true(size(pol));
    if ismember("Rejected",string(C.Properties.VariableNames)) && iscell(C.Rejected) && ...
            numel(C.Rejected{i}) == numel(pol)
        keep = ~logical(C.Rejected{i});
    end
    np(i) = sum(pol(keep) > 0 | pol(keep) == 0);
    nn(i) = sum(pol(keep) < 0);
end
end

function cf = condFiles(R)
% Files rows each condition's sweeps came from.
C = R.Conditions;
nC = height(C);
cf = repmat({zeros(0,1)},nC,1);
SI = R.SweepInfo;
if isstruct(SI) && isfield(SI,'Cond') && isfield(SI,'File') && ~isempty(SI.Cond)
    cond = double(SI.Cond(:)); file = double(SI.File(:));
    for i = 1:nC
        cf{i} = unique(file(cond == i));
    end
elseif nC > 0 && ismember("SweepFile",string(C.Properties.VariableNames)) && iscell(C.SweepFile)
    for i = 1:nC, cf{i} = unique(double(C.SweepFile{i}(:))); end
end
end

function v = fileText(Fl,cf,name,n)
% A Files text column per condition (its files' distinct values, "; ").
v = strings(n,1);
if height(Fl) == 0 || ~ismember(name,string(Fl.Properties.VariableNames)), return; end
col = Fl.(name);
if isdatetime(col), col = string(mabr.analysis.Stats.isoTime(col)); end
col = toStr(col,height(Fl));
for i = 1:n
    f = cf{i}; f = f(f >= 1 & f <= height(Fl));
    u = unique(col(f));
    u = u(u ~= "");
    v(i) = strjoin(u,"; ");
end
end

function v = inputFullScale(R,cf,n)
% The input full scale behind each condition: a unit override, else its
% files' (one value when they agree), else NaN.
v = nan(n,1);
uo = getf(R.Summary,'UnitOverride',struct());
o = scalarDbl(getf(uo,'InputFullScale',NaN));
if isfinite(o), v(:) = o; return; end
Fl = R.Files;
if height(Fl) == 0 || ~ismember("InputFullScale",string(Fl.Properties.VariableNames)), return; end
col = toDbl(Fl.InputFullScale,height(Fl));
for i = 1:n
    f = cf{i}; f = f(f >= 1 & f <= height(Fl));
    u = unique(col(f));
    u = u(isfinite(u));
    if isscalar(u), v(i) = u; end
end
end

function [rig,auto,man] = rejectCounts(R,n)
% Rejected sweeps per condition by reason (rig 1, auto 2, manual 3).
rig = nan(n,1); auto = rig; man = rig;
SI = R.SweepInfo;
C = R.Conditions;
if isstruct(SI) && isfield(SI,'Cond') && isfield(SI,'Reason') && isfield(SI,'Rejected')
    cond = double(SI.Cond(:)); rs = double(SI.Reason(:)); rj = logical(SI.Rejected(:));
    ok = cond >= 1 & cond <= n;
    rig = accumarray(cond(ok & rj & rs == 1),1,[n 1]);
    auto = accumarray(cond(ok & rj & rs == 2),1,[n 1]);
    man = accumarray(cond(ok & rj & rs == 3),1,[n 1]);
elseif n > 0 && ismember("RejectReason",string(C.Properties.VariableNames)) && iscell(C.RejectReason)
    for i = 1:n
        rs = double(C.RejectReason{i});
        rig(i) = sum(rs == 1); auto(i) = sum(rs == 2); man(i) = sum(rs == 3);
    end
end
end

function v = overrideValues(D,keys)
% Detection overrides per condition key: 1, 0 or NaN (automatic).
v = nan(numel(keys),1);
if ~istable(D) || height(D) == 0 || ~all(ismember(["Key","Value"],string(D.Properties.VariableNames))), return; end
dk = toStr(D.Key,height(D)); dv = toDbl(D.Value,height(D));
[tf,loc] = ismember(keys,dk);
v(tf) = dv(loc(tf));
end

function [hp,lp] = filterCorners(R,c)
% The realized -6 dB corners of the session's filter (Hz). The filter the
% segment step actually applied (results StepOptions.segment.Filter) comes
% first, then the one the settings describe, each designed at the session's
% rate and cached (an equiripple design is the slow part, and a study has
% one or two); last, the corners the windowed description prints.
persistent cache
if isempty(cache), cache = containers.Map('KeyType','char','ValueType','any'); end
hp = NaN; lp = NaN;
S = R.Summary;
fs = scalarDbl(getf(S,'SampleRate',NaN));
if isfinite(fs)
    for src = 1:2
        f = [];
        try
            if src == 1
                fsx = getf(getf(R.StepOptions,'segment',struct()),'Filter',[]);
                if ~isstruct(fsx) || isempty(fsx), continue; end
                key = sprintf('%.17g|%s',fs,mabr.analysis.Stats.hex8(jsonencode(fsx)));
                if ~isKey(cache,key), f = filterFromStruct(fsx); end
            else
                st = c.Settings;
                if isempty(st), continue; end
                key = sprintf('%.17g|%s|%s|%.17g|%.17g',fs,mat2str(rowDbl(getf(st,'HighPass',[]),[]),17), ...
                    mat2str(rowDbl(getf(st,'LowPass',[]),[]),17),scalarDbl(getf(st,'FilterPassRippleDb',NaN)), ...
                    scalarDbl(getf(st,'FilterStopAttenDb',NaN)));
                if ~isKey(cache,key), f = mabr.analysis.Settings.fromStruct(st).filter(); end
            end
            if ~isempty(f)
                if ~f.IsDesigned, f = f.design(fs); end
                [h,l] = f.corners6dB();
                cache(key) = [h l];
            end
            v = cache(key); hp = v(1); lp = v(2);
            return
        catch
        end
    end
end
d = string(getf(S,'WindowedDescription',""));
tok = regexp(char(d),'-6 dB at (\S+?)-(\S+?) Hz','tokens','once');
if ~isempty(tok)
    hp = str2double(tok{1}); lp = str2double(tok{2});
end
end

function f = filterFromStruct(s)
% A mabr.analysis.Filter from the plain struct a results file keeps of it
% (Session's filterToStruct): bands for a standard design, coefficients for
% a custom one.
if isfield(s,'Custom') && ~isempty(s.Custom) && s.Custom
    f = mabr.analysis.Filter.fromCoefficients(s.HighNum,s.LowNum,HighDen=s.HighDen, ...
        LowDen=s.LowDen,SampleRate=s.SampleRate,Method=s.Method);
else
    args = {};
    for n = ["HighPass","LowPass","PassRipple","StopRipple","Density","Method"]
        if isfield(s,n), args = [args {char(n),s.(n)}]; end %#ok<AGROW>
    end
    f = mabr.analysis.Filter(args{:});
end
end

function p = padMode(R,c)
% The windowed operator's padding: what segment used, else the settings',
% else the description's.
p = string(getf(getf(R.StepOptions,'segment',struct()),'PadMode',""));
if p ~= "", return; end
p = string(getf(c.Settings,'WindowedPadMode',""));
if p ~= "", return; end
d = string(getf(R.Summary,'WindowedDescription',""));
tok = regexp(char(d),'(reflect|zeroleft) pad','tokens','once');
if ~isempty(tok), p = string(tok{1}); end
end

function u = ampUnit(units)
% What the *_uv columns are, from a Units claim.
u = strings(size(units));
for i = 1:numel(units)
    switch string(units(i))
        case "V",          u(i) = "uV";
        case "V-unscaled", u(i) = "uV-unscaled";
        case "converter",  u(i) = "converter-x1e6";
        case "mixed",      u(i) = "mixed";
        otherwise,         u(i) = "";
    end
end
end

function s = rangeText(a,b)
% "start-end" ms with at most one decimal, e.g. "0-9.9"; "" when unknown.
a = double(a(:)); b = double(b(:));
s = compose("%g-%g",round(a*10)/10,round(b*10)/10);
s(~isfinite(a) | ~isfinite(b)) = "";
end

function s = flagText(v,n)
% Flags as one "; "-joined string per row.
if isstring(v) && numel(v) > 1 && n == 1
    s = strjoin(v(v ~= ""),"; ");
    return
end
s = toStr(v,n);
end

% =========================================================================
%  Settings, JSON, version
% =========================================================================
function L = emptySettingsList()
L = struct('Hash',{},'Settings',{});
end

function L = addSettings(L,h,st)
% Add a settings set to a list by hash (first one wins).
h = string(h);
if isempty(st) || h == "" || ismissing(h), return; end
if ~isempty(L) && ismember(h,[L.Hash]), return; end
L(end+1) = struct('Hash',h,'Settings',st);
end

function [h,st] = settingsHashOf(s)
% The hash and plain struct of a Settings object or struct ("" / [] if none).
h = ""; st = [];
if isempty(s), return; end
try
    if isobject(s)
        st = s.toStruct();
        h = s.hash();
    elseif isstruct(s)
        st = s;
        h = mabr.analysis.Settings.fromStruct(s).hash();
    end
catch
end
h = string(h);
end

function v = jsonSafe(v)
% A value jsonencode keeps whole: non-finite numbers as text, datetimes ISO,
% tables and objects as structs.
if isstruct(v)
    for k = 1:numel(v)
        for f = string(fieldnames(v(k))).'
            v(k).(f) = jsonSafe(v(k).(f));
        end
    end
elseif istable(v)
    v = jsonSafe(table2struct(v));
elseif isdatetime(v)
    v = mabr.analysis.Stats.isoTime(v);
elseif isnumeric(v) && ~isempty(v) && any(~isfinite(v(:)))
    c = num2cell(double(v));
    for k = 1:numel(c)
        x = c{k};
        if isnan(x), c{k} = 'NaN'; elseif x > 0 && isinf(x), c{k} = 'Inf'; elseif isinf(x), c{k} = '-Inf'; end
    end
    if isscalar(c), v = c{1}; else, v = c; end
elseif isa(v,'function_handle')
    v = func2str(v);
elseif isobject(v) && ~isstring(v) && ~iscategorical(v)
    try
        v = jsonSafe(v.toStruct());
    catch
        v = class(v);
    end
end
end

function v = mabrVersion()
try
    v = string(mabr.Config.SoftwareVersion);
catch
    v = "unknown";
end
end

function c = gitCommit()
% The repository's short commit hash, "unknown" when git cannot say.
persistent cached
if ~isempty(cached), c = cached; return; end
c = "unknown";
try
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    [st,out] = system(sprintf('git -C "%s" rev-parse --short HEAD',root));
    out = strtrim(string(out));
    if st == 0 && ~isempty(regexp(char(out),'^[0-9a-f]{4,40}$','once'))
        c = out;
    end
catch
end
cached = c;
end

% =========================================================================
%  Small value helpers
% =========================================================================
function v = getf(s,name,default)
% A field of a struct or a property of an object; default when absent or
% empty (an empty string array counts as absent).
v = default;
if isempty(s), return; end
name = char(name);
if isstruct(s)
    if isfield(s,name), v = s(1).(name); else, return; end
elseif istable(s)
    if ismember(name,s.Properties.VariableNames), v = s.(name); else, return; end
elseif isobject(s)
    if isprop(s,name), v = s.(name); else, return; end
else
    return
end
if isempty(v) && ~isempty(default), v = default; end
end

function v = tcol(T,name,default)
% A column of a table, or the default (expanded by the caller's toX).
if istable(T) && ismember(char(name),T.Properties.VariableNames)
    v = T.(char(name));
else
    v = default;
end
end

function v = tcolRow(T,name,i,default)
v = default;
if istable(T) && ismember(char(name),T.Properties.VariableNames)
    x = T.(char(name));
    if iscell(x), v = x{i}; else, v = x(i); end
end
end

function T = tableOr(T)
if isstruct(T) && ~isempty(T)
    try
        T = struct2table(T,'AsArray',true);
    catch
        T = table();
    end
end
if ~istable(T), T = table(); end
end

function s = toStr(v,n)
% Any column as an n x 1 string, missing as "" (n [] = as many as given).
if isempty(v)
    if isempty(n), s = strings(0,1); else, s = strings(n,1); end
    return
end
if iscategorical(v) || ischar(v) || iscellstr(v) || isstring(v)
    v = string(v);
elseif isnumeric(v)
    % Ten significant digits, the CSV rule -- string() would keep five.
    x = double(v);
    v = missingStr(size(x));
    fin = isfinite(x);
    v(fin) = compose("%.10g",x(fin));
elseif islogical(v)
    v = string(v);
elseif iscell(v)
    v = string(cellfun(@(x) char(string(x)),v,'UniformOutput',false));
elseif isdatetime(v)
    v = string(mabr.analysis.Stats.isoTime(v));
else
    v = string(v);
end
v = reshape(v,[],1);
v(ismissing(v)) = "";
if ~isempty(n) && isscalar(v) && n ~= 1, v = repmat(v,n,1); end
s = v;
end

function x = toDbl(v,n)
% Any column as an n x 1 double (text that is not a number -> NaN).
if isempty(v)
    if isempty(n), x = zeros(0,1); else, x = nan(n,1); end
    return
end
if isnumeric(v) || islogical(v)
    x = double(v);
elseif isstring(v) || ischar(v) || iscellstr(v)
    x = str2double(string(v));
elseif iscell(v)
    x = cellfun(@(e) scalarDbl(e),v);
else
    x = nan(numel(v),1);
end
x = reshape(x,[],1);
if ~isempty(n) && isscalar(x) && n ~= 1, x = repmat(x,n,1); end
end

function b = toLgc(v,n)
% Any column as an n x 1 logical (NaN and text other than true/1 -> false).
if isempty(v)
    if isempty(n), b = false(0,1); else, b = false(n,1); end
    return
end
if islogical(v)
    b = v;
elseif isnumeric(v)
    b = ~isnan(v) & v ~= 0;
elseif isstring(v) || ischar(v) || iscellstr(v)
    b = ismember(lower(strtrim(string(v))),["true","1","yes"]);
else
    b = false(numel(v),1);
end
b = reshape(logical(b),[],1);
if ~isempty(n) && isscalar(b) && n ~= 1, b = repmat(b,n,1); end
end

function d = toDT(v,n)
% Any column as an n x 1 datetime (ISO text parsed; NaT when it cannot be).
if isempty(v)
    if isempty(n), d = NaT(0,1); else, d = NaT(n,1); end
    return
end
if isdatetime(v)
    d = v;
else
    s = toStr(v,[]);
    d = NaT(numel(s),1);
    for k = 1:numel(s), d(k) = parseTime(s(k)); end
end
d = reshape(d,[],1);
d.TimeZone = '';
if ~isempty(n) && isscalar(d) && n ~= 1, d = repmat(d,n,1); end
end

function t = parseTime(v)
% One time from a datetime, ISO text, the legacy display form or a datenum.
t = NaT;
if isempty(v), return; end
if isdatetime(v), t = v(1); t.TimeZone = ''; return; end
if isnumeric(v)
    if isfinite(v(1)) && v(1) > 1e5, t = datetime(v(1),'ConvertFrom','datenum'); end
    return
end
s = strtrim(string(v));
if isempty(s) || ismissing(s(1)) || s(1) == "", return; end
s = s(1);
fmts = {'yyyy-MM-dd''T''HH:mm:ss','yyyy-MM-dd''T''HH:mm:ss.SSS','yyyy-MM-dd HH:mm:ss','yyyy-MM-dd'};
for k = 1:numel(fmts)
    try
        t = datetime(s,'InputFormat',fmts{k});
        return
    catch
    end
end
try
    t = datetime(s,'InputFormat','dd-MMM-yyyy HH:mm:ss','Locale','en_US');
catch
    try
        t = datetime(s);
    catch
        t = NaT;
    end
end
end

function s = scalarStr(v)
s = toStr(v,[]);
if isempty(s), s = ""; else, s = s(1); end
end

function x = scalarDbl(v)
x = toDbl(v,[]);
if isempty(x), x = NaN; else, x = x(1); end
end

function b = scalarLgc(v,default)
if isempty(v), b = default; return; end
b = toLgc(v,[]);
b = b(1);
end

function r = rowStr(v)
% Text as a 1 x n string row ("" dropped).
if isempty(v), r = strings(1,0); return; end
r = reshape(toStr(v,[]),1,[]);
r = r(r ~= "");
end

function r = rowDbl(v,n)
r = reshape(toDbl(v,[]),1,[]);
if ~isempty(n) && numel(r) ~= n, r = nan(1,n); end
end

function s = sortCI(s)
% Case-insensitive sort of a string row.
[~,o] = sort(lower(s));
s = s(o);
end

function v = firstOf(col,idx,default)
% The first of col(idx) (default when idx is empty).
if isempty(idx), v = default; else, v = col(idx(1)); end
end

function v = minOr(col,idx)
if isempty(idx), v = NaN; return; end
x = col(idx); x = x(isfinite(x));
if isempty(x), v = NaN; else, v = min(x); end
end

function v = finiteOr(v)
if ~isfinite(v), v = NaN; end
end

function M = matOr(S,f,nT,nC)
if isfield(S,f) && ~isempty(S.(f)), M = double(S.(f)); else, M = nan(nT,nC); end
end

function x = siCol(SI,f,n)
% A SweepInfo vector as n x 1 double (NaN when absent).
if isfield(SI,f) && numel(SI.(f)) == n
    x = double(reshape(SI.(f),[],1));
else
    x = nan(n,1);
end
end

function s = mergeStruct(s,t)
for f = string(fieldnames(t)).'
    s.(f) = t.(f);
end
end

function v = ternary(c,a,b)
if c, v = a; else, v = b; end
end

function t = classType(x)
% A column's dictionary type from its class.
if islogical(x), t = "logical";
elseif isnumeric(x), t = "double";
elseif isdatetime(x), t = "datetime";
else, t = "string";
end
end

function s = missingStr(varargin)
% A string array of <missing> (written as an empty field).
s = repmat(string(missing),varargin{:});
end

function report(fcn,msg,count,total)
% The progress sink, when there is one (a sink that throws cancels).
if ~isempty(fcn), fcn(msg,count,total); end
end
