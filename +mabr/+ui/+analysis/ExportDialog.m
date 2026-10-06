classdef ExportDialog < handle
% mabr.ui.analysis.ExportDialog  Choose what to export, see what it will cost, and export.
%
%   The analysis app's Export window (File ▸ Export…, Ctrl+E): which
%   sessions (the open one, the browser's selection, the study, everything
%   with results), which tidy tables -- each with the rows and the CSV and
%   Parquet sizes mabr.analysis.Export.estimate expects, and whether it needs
%   the raw .abr files read again -- in which formats, with which options,
%   into which folder. Export hands read() to Model.export, which writes the
%   tables, the R script and column dictionary, and (on by default) a MATLAB
%   script, replicate_analysis.m, that reproduces this export without the app
%   (mabr.analysis.ScriptWriter, built with the same export options).
%
%       d = mabr.ui.analysis.ExportDialog(model,Keys=selected);
%       d = mabr.ui.analysis.ExportDialog(model,Visible="off");   % a test
%       v = d.read();            % the struct Model.export takes
%       files = d.apply();       % export now, the dialog stays open
%       d.ok();                  % export and close
%       files = mabr.ui.analysis.ExportDialog.run(model);   % wait (interactive)
%
%   FORMATS. CSV, XLSX, Parquet and MAT are ticked for the whole export and
%   resolved per table (formatsFor): the large tables -- waveforms, trials
%   and the raw tables, millions of rows in a study -- go to Parquet instead
%   of CSV whenever Parquet is ticked (the default), the others to CSV, or
%   to Parquet when CSV is not ticked; XLSX takes only the tables a sheet can
%   hold (at most 1,048,575 rows); MAT holds every table in one file.
%
%   The line above the buttons says what the export will contain that the
%   user may not mean it to: "4 sessions out of date · 37 series not
%   reviewed · 2 Test Mode sessions left out" -- and the Export button then
%   reads "Export anyway". With nothing to export (no session in the scope
%   has results, no table ticked, no format that writes one) Export is
%   disabled and its tooltip says why. A finished export leaves a note with
%   [Open folder] in the window, and the next Export goes to a new stamped
%   folder.
%
%   Options (name-value): Visible "on"|"off"; Keys (the browser's selection,
%   for the "Selected sessions" scope); Scope ("" = selected when Keys are
%   given, else the open session, else all); PickFolderFcn ([] = the
%   Model's); OpenFolderFcn (fcn(folder); [] = the system's file browser).
%
%   PERSISTENCE. Pressing Export remembers the choices (tables, formats,
%   options -- not the scope or the folder) in the MABR pref
%   OfflineAnalysisExport (loadDefaults/saveDefaults, also what the
%   acquisition app's configuration file carries); nothing else writes it.
%   The window's position is remembered (mabr.ui.WindowPos,
%   "OfflineAnalysisExport") on every way out.
%
%   Tags: AnalysisExportScope, AnalysisExportCount, AnalysisExportTables,
%   AnalysisExportCSV/XLSX/Parquet/MAT, AnalysisExportAllMethods,
%   AnalysisExportOnlyReviewed, AnalysisExportIncludeExcluded,
%   AnalysisExportIncludeTestMode, AnalysisExportWindowStart/End,
%   AnalysisExportRScript, AnalysisExportScript, AnalysisExportFolder,
%   AnalysisExportBrowse, AnalysisExportWarnings, AnalysisExportResult,
%   AnalysisExportOpenFolder, AnalysisExportWriteScript, AnalysisExportGo,
%   AnalysisExportCancel.
%
%   See also mabr.analysis.Export, mabr.analysis.ScriptWriter,
%   mabr.ui.analysis.Model
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        PrefKey = "OfflineAnalysisExport"
        DefaultPosition = [220 140 760 640]
        MinSize = [680 520]
        Scopes = ["current","selected","instudy","all"]
    end

    properties (SetAccess = private)
        Figure = []
        Model = []
        Keys (:,1) string = strings(0,1)   % the selection the dialog was opened with
        Estimate = table()                 % Export.estimate of the scope, every table
        LastFiles = table()                % Export.write's files of the last export
        LastFolder (1,1) string = ""       % where the last export went
        LastScript (1,1) string = ""       % the last script Write script… wrote
        Done (1,1) logical = false
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners = event.listener.empty
        Items                              % containers.Map: key -> export item
        Written = struct()
        DefaultFolder (1,1) string = ""
        PickFolderFcn = []
        OpenFolderFcn = []
        WhyNot (1,1) string = ""           % why Export is disabled
    end

    methods
        function obj = ExportDialog(model,opts)
            % ExportDialog(model,Visible=,Keys=,Scope=,PickFolderFcn=,OpenFolderFcn=)
            arguments
                model
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.Keys string = strings(0,1)
                opts.Scope (1,1) string = ""
                opts.PickFolderFcn = []
                opts.OpenFolderFcn = []
            end
            if ~isa(model,'mabr.ui.analysis.Model')
                error('mabr:ui:ExportDialog:badModel','ExportDialog needs a mabr.ui.analysis.Model.');
            end
            obj.Model = model;
            obj.Keys  = reshape(opts.Keys,[],1);
            obj.Items = containers.Map('KeyType','char','ValueType','any');
            obj.PickFolderFcn = opts.PickFolderFcn;
            if isempty(obj.PickFolderFcn), obj.PickFolderFcn = model.PickFolderFcn; end
            obj.OpenFolderFcn = opts.OpenFolderFcn;
            if isempty(obj.OpenFolderFcn)
                obj.OpenFolderFcn = @(p) mabr.ui.analysis.ExportDialog.openInSystem(p);
            end

            f = uifigure('Name','Export analysis tables','Tag','MABR_OFFLINE_EXPORT', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','on');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisExport',obj.DefaultPosition,obj.MinSize);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;
            obj.build();

            scope = opts.Scope;
            if scope == ""
                if ~isempty(obj.Keys)
                    scope = "selected";
                elseif model.SessionKey ~= ""
                    scope = "current";
                else
                    scope = "all";
                end
            end
            if ~any(obj.Scopes == scope)
                error('mabr:ui:ExportDialog:badScope','Scope is one of %s.',strjoin(obj.Scopes,', '));
            end
            obj.Ctrl.Scope.Value = char(scope);
            obj.newFolder();
            obj.write(mabr.ui.analysis.ExportDialog.loadDefaults());   % (estimates)
            obj.Listeners = event.listener(model,'BusyChanged',@(~,~) obj.syncEnable());
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        % ---- the common dialog API ----------------------------------------
        function v = read(obj)
            % The options Model.export takes: Scope, Keys, Tables, Formats
            % (per table), RawFormats, ThresholdsAll, OnlyReviewed,
            % IncludeExcluded, IncludeTestMode, WaveformWindow, RScript,
            % Script, Folder -- plus Choice (CSV/XLSX/Parquet/MAT ticked).
            v = struct();
            if ~obj.isopen()
                v = mabr.ui.analysis.ExportDialog.factoryDefaults();
                return
            end
            c = obj.Ctrl;
            v.Scope = string(c.Scope.Value);
            if v.Scope == "selected", v.Keys = obj.Keys; else, v.Keys = strings(0,1); end
            v.Tables = obj.usedTables();
            v.Choice = struct('CSV',logical(c.CSV.Value),'XLSX',logical(c.XLSX.Value), ...
                'Parquet',logical(c.Parquet.Value),'MAT',logical(c.MAT.Value));
            F = mabr.ui.analysis.ExportDialog.formatsFor(v.Tables,v.Choice,obj.Estimate);
            v.Formats = F;
            v.RawFormats = F;
            v.ThresholdsAll   = logical(c.AllMethods.Value);
            v.OnlyReviewed    = logical(c.OnlyReviewed.Value);
            v.IncludeExcluded = logical(c.IncludeExcluded.Value);
            v.IncludeTestMode = logical(c.IncludeTestMode.Value);
            v.WaveformWindow  = [c.WindowStart.Value c.WindowEnd.Value];
            v.RScript = logical(c.RScript.Value);
            v.Script  = logical(c.Script.Value);
            v.Folder  = strtrim(string(c.Folder.Value));
        end

        function write(obj,v)
            % Put options V (read()'s fields, or the remembered defaults --
            % any subset) into the controls.
            if ~obj.isopen() || ~isstruct(v), return; end
            c = obj.Ctrl;
            if isfield(v,'Scope') && any(obj.Scopes == string(v.Scope))
                c.Scope.Value = char(string(v.Scope));
            end
            if isfield(v,'Keys') && ~isempty(v.Keys)
                obj.Keys = reshape(string(v.Keys),[],1);
                obj.syncScopeItems();
            end
            if isfield(v,'Tables')
                D = c.Tables.Data;
                D.Use = ismember(string(D.Table),string(v.Tables));
                c.Tables.Data = D;
            end
            ch = [];
            if isfield(v,'Choice') && isstruct(v.Choice)
                ch = v.Choice;
            elseif all(isfield(v,{'CSV','XLSX','Parquet','MAT'}))
                ch = struct('CSV',v.CSV,'XLSX',v.XLSX,'Parquet',v.Parquet,'MAT',v.MAT);
            elseif isfield(v,'Formats') && (isstring(v.Formats) || ischar(v.Formats) || iscellstr(v.Formats))
                fm = lower(string(v.Formats));
                ch = struct('CSV',any(fm == "csv"),'XLSX',any(fm == "xlsx"), ...
                    'Parquet',any(fm == "parquet"),'MAT',any(fm == "mat"));
            end
            if ~isempty(ch)
                for k = ["CSV","XLSX","Parquet","MAT"]
                    if isfield(ch,k), c.(k).Value = logical(ch.(k)); end
                end
            end
            map = ["ThresholdsAll","AllMethods"; "AllMethods","AllMethods"; ...
                "OnlyReviewed","OnlyReviewed"; "IncludeExcluded","IncludeExcluded"; ...
                "IncludeTestMode","IncludeTestMode"; "RScript","RScript"; "Script","Script"];
            for k = 1:size(map,1)
                if isfield(v,map(k,1))
                    try
                        c.(map(k,2)).Value = logical(v.(map(k,1)));
                    catch
                    end
                end
            end
            if isfield(v,'WaveformWindow') && numel(v.WaveformWindow) == 2
                c.WindowStart.Value = double(v.WaveformWindow(1));
                c.WindowEnd.Value   = double(v.WaveformWindow(2));
            end
            if isfield(v,'Folder')
                fd = string(v.Folder);
                if isempty(fd) || ismissing(fd) || fd == "", fd = obj.DefaultFolder; end
                c.Folder.Value = char(fd);
            end
            obj.recompute();
        end

        function files = apply(obj)
            % Export with the options shown; the dialog stays open with a
            % note of what was written. files: Export.write's table (empty
            % when nothing was exported).
            files = table();
            if ~obj.isopen(), return; end
            obj.recompute();
            if obj.WhyNot ~= ""
                obj.setResult(obj.WhyNot,true);
                return
            end
            v = obj.read();
            m = obj.Model;
            try
                files = m.export(v);
            catch me
                obj.setResult("Export failed: " + string(me.message),true);
                return
            end
            if ~obj.isopen(), return; end
            if isempty(files) || height(files) == 0
                txt = m.LastMessage;
                if txt == "", txt = "Nothing was exported."; end
                obj.setResult(txt,true);
                return
            end
            obj.LastFiles  = files;
            obj.LastFolder = m.LastExportFolder;
            n = sum(string(files.File) ~= "");
            txt = sprintf('Exported %d file(s) to %s',n,obj.LastFolder);
            if v.Script && isfile(fullfile(obj.LastFolder,'replicate_analysis.m'))
                txt = txt + " — with replicate_analysis.m";
            end
            obj.setResult(string(txt),false);
            obj.Ctrl.Cancel.Text = 'Close';
            % The next Export goes to a new folder, not over this one.
            if strtrim(string(obj.Ctrl.Folder.Value)) == obj.DefaultFolder
                obj.newFolder();
                obj.Ctrl.Folder.Value = char(obj.DefaultFolder);
                obj.recompute(false);          % (the folder's tooltip)
            end
        end

        function files = ok(obj)
            % Export, then close.
            files = obj.apply();
            if ~isempty(files) && height(files) > 0
                obj.Done = true;
                obj.closeFigure();
            end
        end

        function cancel(obj)
            % Close (an export already made stays made).
            if obj.Done, return; end
            obj.Done = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function txt = warnings(obj)
            % The warnings line as it reads now ("" when there is none).
            txt = "";
            if obj.isopen(), txt = string(obj.Ctrl.Warnings.Text); end
        end

        function file = writeScript(obj)
            % Write script… : only the replication script of the scope's
            % sessions (Model.exportScript asks where).
            file = "";
            if ~obj.isopen(), return; end
            scope = string(obj.Ctrl.Scope.Value);
            if scope == "current"
                % no keys = the open session to Model.exportScript; with none
                % open it would write a study script of the in-study sessions,
                % which is not what this scope says
                if obj.Model.SessionKey == ""
                    obj.setResult("No session is open — choose another scope to write a script for.",true);
                    return
                end
                keys = strings(0,1);
            else
                keys = obj.scopeKeys(scope);
                if isempty(keys)
                    obj.setResult("No session in this scope has results to write a script for.",true);
                    return
                end
            end
            try
                file = obj.Model.exportScript('Keys',keys);
            catch me
                obj.setResult("The script was not written: " + string(me.message),true);
                return
            end
            if file ~= ""
                obj.LastScript = file;
                obj.setResult("Wrote the replication script " + file,false);
            end
        end
    end

    methods (Static)
        function files = run(model,varargin)
            % Show the dialog and wait (uiwait) until it closes: the files of
            % the last export made from it (an empty table when none was).
            % Interactive use only.
            d = mabr.ui.analysis.ExportDialog(model,varargin{:});
            if d.isopen()
                uiwait(d.Figure);
            end
            files = d.LastFiles;
            delete(d);
        end

        function d = factoryDefaults()
            % What the dialog opens with on a fresh install.
            d = struct('Tables',mabr.analysis.Export.DefaultTables, ...
                'CSV',true,'XLSX',false,'Parquet',true,'MAT',false, ...
                'ThresholdsAll',false,'OnlyReviewed',false,'IncludeExcluded',false, ...
                'IncludeTestMode',false,'WaveformWindow',[-2 10],'RScript',true,'Script',true);
        end

        function d = loadDefaults()
            % The choices the last Export remembered (pref
            % OfflineAnalysisExport), forgivingly: a field that is missing or
            % not usable keeps its factory value.
            d = mabr.ui.analysis.ExportDialog.factoryDefaults();
            try
                g = 'MABR';  n = char(mabr.ui.analysis.ExportDialog.PrefKey);
                if ispref(g,n)
                    d = mabr.ui.analysis.ExportDialog.sanitize(getpref(g,n));
                end
            catch
                d = mabr.ui.analysis.ExportDialog.factoryDefaults();
            end
        end

        function saveDefaults(d)
            % Remember D (loadDefaults' shape, or read()'s) in the pref. Only
            % the Export button and the acquisition app's Load Configuration
            % call this.
            d = mabr.ui.analysis.ExportDialog.sanitize(d);
            setpref('MABR',char(mabr.ui.analysis.ExportDialog.PrefKey),d);
        end

        function d = sanitize(v)
            % A defaults struct from anything: known fields of the right
            % type are taken, the rest keep the factory values.
            d = mabr.ui.analysis.ExportDialog.factoryDefaults();
            if ~isstruct(v) || ~isscalar(v), return; end
            if isfield(v,'Choice') && isstruct(v.Choice)
                for k = ["CSV","XLSX","Parquet","MAT"]
                    if isfield(v.Choice,k), v.(k) = v.Choice.(k); end
                end
            end
            if isfield(v,'AllMethods') && ~isfield(v,'ThresholdsAll'), v.ThresholdsAll = v.AllMethods; end
            if isfield(v,'Tables')
                try
                    t = reshape(string(v.Tables),1,[]);
                    known = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables];
                    d.Tables = t(ismember(t,known));
                catch
                end
            end
            for k = ["CSV","XLSX","Parquet","MAT","ThresholdsAll","OnlyReviewed","IncludeExcluded", ...
                    "IncludeTestMode","RScript","Script"]
                if isfield(v,k) && (islogical(v.(k)) || isnumeric(v.(k))) && isscalar(v.(k))
                    d.(k) = logical(v.(k));
                end
            end
            if isfield(v,'WaveformWindow') && isnumeric(v.WaveformWindow) && numel(v.WaveformWindow) == 2 ...
                    && all(isfinite(v.WaveformWindow)) && v.WaveformWindow(2) > v.WaveformWindow(1)
                d.WaveformWindow = reshape(double(v.WaveformWindow),1,2);
            end
        end

        function F = formatsFor(tables,choice,E)
            % The formats each table is written in (Export.write's struct
            % form, a field per table plus "default").
            %
            %   tables  the tables exported (string row)
            %   choice  struct CSV, XLSX, Parquet, MAT (logical)
            %   E       Export.estimate's table ([] = every table a sheet
            %           takes counts as fitting one)
            %   F       (returned) struct: F.<table> string row of formats
            %           ("" fields absent: a table no format writes gets
            %           strings(1,0)), F.default the same rule for a small
            %           table
            %
            % Large tables (Export.LargeTables) go to Parquet whenever it is
            % ticked, in place of CSV; small ones to CSV, or to Parquet when
            % CSV is not ticked. XLSX only for a table a sheet can hold;
            % sweeps never CSV (Export.writeRaw refuses it).
            if nargin < 3, E = []; end
            F = struct();
            tables = reshape(string(tables),1,[]);
            for t = [tables "default"]
                large = ismember(t,mabr.analysis.Export.LargeTables);
                fm = strings(1,0);
                if choice.Parquet && (large || ~choice.CSV)
                    fm(end+1) = "parquet"; %#ok<AGROW>
                end
                if choice.CSV && ~(large && choice.Parquet) && t ~= "sweeps"
                    fm(end+1) = "csv"; %#ok<AGROW>
                end
                if choice.XLSX && mabr.ui.analysis.ExportDialog.xlsxFits(t,E)
                    fm(end+1) = "xlsx"; %#ok<AGROW>
                end
                if choice.MAT
                    fm(end+1) = "mat"; %#ok<AGROW>
                end
                F.(t) = fm;
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            f = obj.Figure;
            g = uigridlayout(f,[11 1]);
            g.RowHeight = {26,'1x',24,24,24,24,24,26,36,26,32};
            g.Padding = [12 12 12 10];
            g.RowSpacing = 6;

            % ---- scope
            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 1;
            r.ColumnWidth = {130,230,'1x'};
            uilabel(r,'Text','Sessions');
            sc = uidropdown(r,'Items',{'Current session','Selected sessions','In study','All with results'}, ...
                'ItemsData',cellstr(obj.Scopes),'Tag','AnalysisExportScope', ...
                'Tooltip','Which sessions the export holds: the open one, the browser''s selection, the study, or every session with results.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            obj.Ctrl.Scope = sc;
            cnt = uilabel(r,'Text','','Tag','AnalysisExportCount','FontColor',mabr.ui.analysis.Style.Muted);
            obj.Ctrl.Count = cnt;
            obj.syncScopeItems();

            % ---- tables
            all_ = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables];
            n = numel(all_);
            D = table(false(n,1),cellstr(all_(:)),zeros(n,1),repmat({''},n,1),repmat({''},n,1), ...
                repmat({''},n,1),'VariableNames',{'Use','Table','Rows','CSV','Parquet','Raw'});
            t = uitable(g,'Data',D,'Tag','AnalysisExportTables','RowName',{}, ...
                'ColumnName',{'Use','Table','Rows','CSV size','Parquet size','Needs raw data'}, ...
                'ColumnEditable',[true false false false false false], ...
                'ColumnWidth',{44,'auto',90,90,90,110}, ...
                'Tooltip',['Tick the tables to export. Rows and sizes are estimates; a table that needs ' ...
                'raw data reads every session''s .abr files again (slow).']);
            t.Layout.Row = 2;
            t.CellEditCallback = @(~,~) obj.recompute(false);
            cm = uicontextmenu(f);
            uimenu(cm,'Text','Copy table','MenuSelectedFcn',@(~,~) mabr.ui.analysis.FigureExport.copyTable(t));
            t.ContextMenu = cm;
            obj.Ctrl.Tables = t;

            % ---- formats
            r = uigridlayout(g,[1 5],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 3;
            r.ColumnWidth = {130,90,110,90,'1x'};
            uilabel(r,'Text','Formats');
            obj.Ctrl.CSV = uicheckbox(r,'Text','CSV','Tag','AnalysisExportCSV', ...
                'Tooltip','Comma-separated text, UTF-8: every table that is not written as Parquet.', ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));
            obj.Ctrl.XLSX = uicheckbox(r,'Text','Excel (XLSX)','Tag','AnalysisExportXLSX', ...
                'Tooltip',['One workbook, a sheet per table -- only the tables a sheet can hold ' ...
                '(at most 1,048,575 rows; not waveforms, trials or the raw tables).'], ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));
            obj.Ctrl.Parquet = uicheckbox(r,'Text','Parquet','Tag','AnalysisExportParquet', ...
                'Tooltip',['Parquet (what R''s arrow reads): the large tables -- waveforms, trials and the ' ...
                'raw tables -- are written as Parquet instead of CSV; every table when CSV is not ticked.'], ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));
            obj.Ctrl.MAT = uicheckbox(r,'Text','MAT','Tag','AnalysisExportMAT', ...
                'Tooltip','Every table in one MATLAB file (MABRExport, a struct of tables).', ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));

            % ---- options
            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 4;
            r.ColumnWidth = {130,'1x','1x'};
            uilabel(r,'Text','Include');
            obj.Ctrl.AllMethods = uicheckbox(r,'Text','Every threshold method','Tag','AnalysisExportAllMethods', ...
                'Tooltip','Add a row per built-in threshold method per series, from the stored per-level numbers.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            obj.Ctrl.OnlyReviewed = uicheckbox(r,'Text','Only reviewed series','Tag','AnalysisExportOnlyReviewed', ...
                'Tooltip','The series tables hold only series whose threshold was reviewed.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 5;
            r.ColumnWidth = {130,'1x','1x'};
            uilabel(r,'Text','');
            obj.Ctrl.IncludeExcluded = uicheckbox(r,'Text','Sessions left out of the study', ...
                'Tag','AnalysisExportIncludeExcluded', ...
                'Tooltip','Also export the sessions and subjects that are not in the study.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            obj.Ctrl.IncludeTestMode = uicheckbox(r,'Text','Test Mode sessions','Tag','AnalysisExportIncludeTestMode', ...
                'Tooltip','Also export sessions recorded in Test Mode (their samples are the stimulus, not a subject).', ...
                'ValueChangedFcn',@(~,~) obj.recompute());

            r = uigridlayout(g,[1 4],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 6;
            r.ColumnWidth = {130,74,74,'1x'};
            uilabel(r,'Text','Waveforms (ms)','Tooltip','The stretch of each mean the waveforms table holds.');
            obj.Ctrl.WindowStart = uieditfield(r,'numeric','ValueDisplayFormat','%.6g', ...
                'Tag','AnalysisExportWindowStart','Tooltip','Waveforms table: the first time written, ms.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            obj.Ctrl.WindowEnd = uieditfield(r,'numeric','ValueDisplayFormat','%.6g', ...
                'Tag','AnalysisExportWindowEnd','Tooltip','Waveforms table: the last time written, ms.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());

            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 7;
            r.ColumnWidth = {130,230,'1x'};
            uilabel(r,'Text','Also write');
            obj.Ctrl.RScript = uicheckbox(r,'Text','R script and column dictionary','Tag','AnalysisExportRScript', ...
                'Tooltip','mabr_import.R (reads every table, with the models), mabr_columns.csv and a manifest.', ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));
            obj.Ctrl.Script = uicheckbox(r,'Text','Also write a MATLAB script that reproduces this export', ...
                'Tag','AnalysisExportScript', ...
                'Tooltip',['replicate_analysis.m beside the exported files: re-analyses the sessions from ' ...
                'the .abr files with the same settings and edits and writes this export again, without the app.'], ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));

            % ---- folder
            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 8;
            r.ColumnWidth = {130,'1x',90};
            uilabel(r,'Text','Folder');
            obj.Ctrl.Folder = uieditfield(r,'text','Tag','AnalysisExportFolder', ...
                'Tooltip','Where the files go (created). By default a new stamped folder under the results folder''s exports.', ...
                'ValueChangedFcn',@(~,~) obj.recompute(false));
            obj.Ctrl.Browse = uibutton(r,'Text','Browse…','Tag','AnalysisExportBrowse', ...
                'Tooltip','Choose the folder the files go into.','ButtonPushedFcn',@(~,~) obj.browse());
            mabr.ui.analysis.Style.setButtonIcon(obj.Ctrl.Browse,'load','left');

            % ---- warnings, result
            w = uilabel(g,'Text','','Tag','AnalysisExportWarnings','WordWrap','on', ...
                'FontColor',mabr.ui.analysis.Style.AccentText,'VerticalAlignment','top', ...
                'Tooltip','What the export holds that you may not mean it to.');
            w.Layout.Row = 9;
            obj.Ctrl.Warnings = w;
            r = uigridlayout(g,[1 2],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 10;
            r.ColumnWidth = {'1x',120};
            obj.Ctrl.Result = uilabel(r,'Text','','Tag','AnalysisExportResult', ...
                'FontColor',mabr.ui.analysis.Style.Good);
            ob = uibutton(r,'Text','Open folder','Tag','AnalysisExportOpenFolder','Visible','off', ...
                'Tooltip','Show the exported files.','ButtonPushedFcn',@(~,~) obj.openFolder());
            mabr.ui.analysis.Style.setButtonIcon(ob,'load','left');
            obj.Ctrl.OpenFolder = ob;

            % ---- buttons
            r = uigridlayout(g,[1 4],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 11;
            r.ColumnWidth = {130,'1x',130,90};
            ws = uibutton(r,'Text','Write script…','Tag','AnalysisExportWriteScript', ...
                'Tooltip',['Write only a MATLAB script that reproduces the analysis of these sessions ' ...
                '(asks where), without exporting.'], ...
                'ButtonPushedFcn',@(~,~) obj.writeScript());
            ws.Layout.Column = 1;
            mabr.ui.analysis.Style.setButtonIcon(ws,'script','left');
            obj.Ctrl.WriteScript = ws;
            goBtn = uibutton(r,'Text','Export','Tag','AnalysisExportGo', ...
                'Tooltip','Write the ticked tables into the folder.','ButtonPushedFcn',@(~,~) obj.onGo());
            goBtn.Layout.Column = 3;
            mabr.ui.analysis.Style.setButtonIcon(goBtn,'export','left');
            obj.Ctrl.Go = goBtn;
            cb = uibutton(r,'Text','Cancel','Tag','AnalysisExportCancel', ...
                'Tooltip','Close this window (Esc).','ButtonPushedFcn',@(~,~) obj.cancel());
            cb.Layout.Column = 4;
            obj.Ctrl.Cancel = cb;
        end

        function syncScopeItems(obj)
            n = numel(obj.Keys);
            items = obj.Ctrl.Scope.Items;
            if n > 0
                items{2} = sprintf('Selected sessions (%d)',n);
            else
                items{2} = 'Selected sessions';
            end
            obj.Ctrl.Scope.Items = items;
        end

        function onGo(obj)
            % The Export button: export, and remember the choices (pref).
            files = obj.apply();
            if ~isempty(files) && height(files) > 0
                try
                    mabr.ui.analysis.ExportDialog.saveDefaults(obj.read());
                catch me
                    mabr.log.vprintf(2,'ExportDialog: export options not remembered (%s).',me.message);
                end
            end
        end

        function browse(obj)
            start = strtrim(string(obj.Ctrl.Folder.Value));
            p = string(obj.PickFolderFcn(start,"Export into folder"));
            if isempty(p) || ismissing(p) || p == "", return; end
            obj.Ctrl.Folder.Value = char(p);
            obj.recompute(false);
        end

        function openFolder(obj)
            if obj.LastFolder == "", return; end
            try
                obj.OpenFolderFcn(obj.LastFolder);
            catch me
                obj.setResult("The folder could not be opened: " + string(me.message),true);
            end
        end

        function newFolder(obj)
            % A fresh stamped folder; one already there (two exports in a
            % second) gets _2, _3, ... With no results folder (no root
            % open) there is none to suggest: a bare "exports\<stamp>"
            % would land wherever MATLAB's current folder happens to be.
            rf = string(obj.Model.resultsFolder());
            if rf == ""
                obj.DefaultFolder = "";
                return
            end
            base = string(fullfile(rf,'exports', ...
                string(datetime('now','Format','yyMMdd''T''HHmmss'))));
            p = base;
            k = 1;
            while isfolder(p) || p == obj.LastFolder
                k = k + 1;
                p = base + "_" + k;
            end
            obj.DefaultFolder = p;
            if isfield(obj.Ctrl,'Folder') && isvalid(obj.Ctrl.Folder) && ...
                    strtrim(string(obj.Ctrl.Folder.Value)) == ""
                obj.Ctrl.Folder.Value = char(p);
            end
        end

        function keys = scopeKeys(obj,scope)
            % The sessions of a scope that have results (the rule
            % Model.export applies).
            m = obj.Model;
            keys = strings(0,1);
            try
                switch string(scope)
                    case "current"
                        if m.SessionKey ~= "", keys = m.SessionKey; end
                    case "selected"
                        keys = obj.Keys;
                    case "instudy"
                        keys = string(m.Project.studyKeys());
                    otherwise
                        keys = m.allKeys();      % (the hidden ones left out)
                end
            catch
                keys = strings(0,1);
            end
            keys = reshape(keys,[],1);
            keep = false(numel(keys),1);
            for i = 1:numel(keys)
                keep(i) = m.hasResults(keys(i));
            end
            keys = keys(keep);
        end

        function items = itemsFor(obj,keys)
            % Project.exportItems for KEYS, each read once per dialog.
            items = struct('Key',{},'Results',{},'Labels',{},'Notes',{},'Session',{});
            m = obj.Model;
            need = keys(~cellfun(@(k) isKey(obj.Items,char(k)),cellstr(keys)));
            if ~isempty(need)
                try
                    it = m.Project.exportItems(need,m.Catalog,'Notes',false);
                    for i = 1:numel(it)
                        obj.Items(char(it(i).Key)) = it(i);
                    end
                catch me
                    mabr.log.vprintf(2,'ExportDialog: results not read for the estimate (%s).',me.message);
                end
            end
            for i = 1:numel(keys)
                if isKey(obj.Items,char(keys(i)))
                    items(end+1) = obj.Items(char(keys(i))); %#ok<AGROW>
                end
            end
        end

        function recompute(obj,estimate)
            % Re-estimate (scope and options) and re-derive the warnings and
            % the Export button. estimate false: only the warnings/enables.
            if nargin < 2, estimate = true; end
            if ~obj.isopen(), return; end
            c = obj.Ctrl;
            scope = string(c.Scope.Value);
            keys = obj.scopeKeys(scope);
            if estimate || isempty(obj.Estimate)
                obj.Estimate = obj.estimateFor(keys);
                D = c.Tables.Data;
                E = obj.Estimate;
                for i = 1:height(D)
                    k = find(string(E.Table) == string(D.Table{i}),1);
                    if isempty(k), continue; end
                    D.Rows(i) = E.Rows(k);
                    D.CSV{i} = char(mabr.ui.analysis.ExportDialog.bytesText(E.CSVBytes(k)));
                    D.Parquet{i} = char(mabr.ui.analysis.ExportDialog.bytesText(E.ParquetBytes(k)));
                    if E.NeedsRaw(k), D.Raw{i} = 'yes'; else, D.Raw{i} = ''; end
                end
                c.Tables.Data = D;
            end
            switch scope
                case "current"
                    if obj.Model.SessionKey == ""
                        cnt = "No session is open.";
                    elseif isempty(keys)
                        cnt = "The open session has no results yet.";
                    else
                        cnt = "1 session with results";
                    end
                otherwise
                    cnt = sprintf('%d session(s) with results',numel(keys));
            end
            obj.put('count',c.Count,'Text',char(cnt));
            % the field shows the start of a long path; the tooltip all of it
            fd = strtrim(string(c.Folder.Value));
            if fd == ""
                fdTip = "Where the files go (created): choose a folder.";
            else
                fdTip = "Where the files go (created): " + fd;
            end
            obj.put('folderTip',c.Folder,'Tooltip',char(fdTip));
            obj.syncWarnings(scope,keys);
            obj.syncEnable();
        end

        function E = estimateFor(obj,keys)
            all_ = [mabr.analysis.Export.DefaultTables mabr.analysis.Export.OptionalTables];
            n = numel(all_);
            E = table(all_(:),zeros(n,1),zeros(n,1),zeros(n,1), ...
                ismember(all_(:),mabr.analysis.Export.XLSXTables), ...
                ismember(all_(:),mabr.analysis.Export.RawTables), ...
                'VariableNames',{'Table','Rows','CSVBytes','ParquetBytes','XLSXAllowed','NeedsRaw'});
            if isempty(keys), return; end
            c = obj.Ctrl;
            items = obj.itemsFor(keys);
            if isempty(items), return; end
            try
                E = mabr.analysis.Export.estimate(items,'Tables',all_, ...
                    'ThresholdsAll',logical(c.AllMethods.Value),'OnlyReviewed',logical(c.OnlyReviewed.Value), ...
                    'IncludeExcluded',logical(c.IncludeExcluded.Value), ...
                    'IncludeTestMode',logical(c.IncludeTestMode.Value), ...
                    'WaveformWindow',obj.windowOrDefault(),'Settings',obj.Model.Settings);
            catch me
                mabr.log.vprintf(2,'ExportDialog: no estimate (%s).',me.message);
            end
        end

        function w = windowOrDefault(obj)
            w = [obj.Ctrl.WindowStart.Value obj.Ctrl.WindowEnd.Value];
            if ~(all(isfinite(w)) && w(2) > w(1)), w = [-2 10]; end
        end

        function t = usedTables(obj)
            D = obj.Ctrl.Tables.Data;
            t = reshape(string(D.Table(logical(D.Use))),1,[]);
        end

        function syncWarnings(obj,scope,keys)
            % The warnings line and why Export may be disabled.
            c = obj.Ctrl;
            m = obj.Model;
            parts = strings(1,0);
            why = "";
            tables = obj.usedTables();
            choice = struct('CSV',c.CSV.Value,'XLSX',c.XLSX.Value,'Parquet',c.Parquet.Value,'MAT',c.MAT.Value);
            F = mabr.ui.analysis.ExportDialog.formatsFor(tables,choice,obj.Estimate);

            if isempty(keys)
                if scope == "current" && m.SessionKey == ""
                    why = "No session is open — choose another scope.";
                elseif scope == "selected" && isempty(obj.Keys)
                    why = "No session is selected in the browser — choose another scope.";
                else
                    why = "No session in this scope has results — analyse them first.";
                end
            elseif isempty(tables)
                why = "No table is ticked.";
            elseif ~any(arrayfun(@(t) ~isempty(F.(t)),tables))
                why = "No ticked format writes the ticked tables.";
            elseif strtrim(string(c.Folder.Value)) == ""
                why = "Choose a folder to export into.";
            end

            V = table();
            try
                V = m.projectView();
            catch
            end
            if ~isempty(keys) && ~isempty(V) && height(V) > 0
                [tf,loc] = ismember(keys,string(V.Key));
                R = V(loc(tf),:);
                nStale = sum(string(R.Status) == "stale");
                if nStale > 0
                    parts(end+1) = sprintf('%d session(s) out of date',nStale);
                end
                if ismember('NumSeries',R.Properties.VariableNames)
                    nUn = sum(max(double(R.NumSeries) - double(R.Reviewed),0));
                    if nUn > 0
                        if c.OnlyReviewed.Value
                            parts(end+1) = sprintf('%d series not reviewed (left out)',nUn);
                        else
                            parts(end+1) = sprintf('%d series not reviewed',nUn);
                        end
                    end
                end
                if ~c.IncludeTestMode.Value && ismember('TestMode',R.Properties.VariableNames)
                    nT = sum(string(R.TestMode) == "all");
                    if nT > 0
                        parts(end+1) = sprintf('%d Test Mode session(s) left out',nT);
                    end
                end
            end
            if any(scope == ["selected","instudy"])
                nAll = numel(obj.scopeKeysAll(scope));
                if nAll > numel(keys)
                    parts(end+1) = sprintf('%d session(s) without results left out',nAll - numel(keys));
                end
            end
            raw = tables(ismember(tables,mabr.analysis.Export.RawTables));
            if ~isempty(raw)
                parts(end+1) = "the raw tables read every session's .abr files again (slow)";
            end
            if choice.XLSX
                noX = tables(arrayfun(@(t) ~any(F.(t) == "xlsx"),tables));
                if ~isempty(noX)
                    parts(end+1) = "XLSX leaves out " + strjoin(noX,", ");
                end
            end
            if any(tables == "sweeps") && isempty(F.sweeps)
                parts(end+1) = "sweeps is never written as CSV — tick Parquet or MAT";
            end
            obj.WhyNot = why;
            txt = strjoin(parts,"  ·  ");
            obj.put('warn',c.Warnings,'Text',char(txt));
            quality = ~isempty(parts);
            if quality, lab = 'Export anyway'; else, lab = 'Export'; end
            obj.put('goText',c.Go,'Text',lab);
        end

        function keys = scopeKeysAll(obj,scope)
            % A scope's sessions, with results or not.
            keys = strings(0,1);
            try
                if scope == "selected"
                    keys = obj.Keys;
                elseif scope == "instudy"
                    keys = string(obj.Model.Project.studyKeys());
                end
            catch
            end
        end

        function syncEnable(obj)
            if ~obj.isopen(), return; end
            busy = false;
            try
                busy = obj.Model.Busy;
            catch
            end
            on = obj.WhyNot == "" && ~busy;
            obj.put('goOn',obj.Ctrl.Go,'Enable',matlab.lang.OnOffSwitchState(on));
            if busy
                tip = 'Wait for the running job to finish.';
            elseif obj.WhyNot ~= ""
                tip = char(obj.WhyNot);
            else
                tip = 'Write the ticked tables into the folder.';
            end
            obj.put('goTip',obj.Ctrl.Go,'Tooltip',tip);
            obj.put('wsOn',obj.Ctrl.WriteScript,'Enable',matlab.lang.OnOffSwitchState(~busy));
        end

        function setResult(obj,txt,isProblem)
            if ~obj.isopen(), return; end
            if isProblem
                col = mabr.ui.analysis.Style.Warn;
            else
                col = mabr.ui.analysis.Style.Good;
            end
            obj.Ctrl.Result.Text = char(txt);
            obj.Ctrl.Result.FontColor = col;
            obj.Ctrl.Result.Tooltip = char(txt);
            obj.Ctrl.OpenFolder.Visible = matlab.lang.OnOffSwitchState(~isProblem && obj.LastFolder ~= "");
        end

        function put(obj,key,h,prop,v)
            key = char(key);
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                h.(prop) = v;
                obj.Written.(key) = v;
            catch
            end
        end

        function onKey(obj,e)
            if strcmpi(e.Key,'escape'), obj.cancel(); end
        end

        function closeFigure(obj)
            try
                delete(obj.Listeners);
            catch
            end
            obj.Listeners = event.listener.empty;
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisExport');
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end

    methods (Static, Access = private)
        function tf = xlsxFits(t,E)
            tf = ismember(t,mabr.analysis.Export.XLSXTables) || t == "default";
            if ~tf || isempty(E) || t == "default", return; end
            k = find(string(E.Table) == t,1);
            if ~isempty(k), tf = logical(E.XLSXAllowed(k)); end
        end

        function s = bytesText(b)
            if ~isfinite(b) || b <= 0
                s = "–";
            elseif b < 1e3
                s = sprintf('%d B',round(b));
            elseif b < 1e6
                s = sprintf('%.0f kB',b/1e3);
            elseif b < 1e9
                s = sprintf('%.1f MB',b/1e6);
            else
                s = sprintf('%.2f GB',b/1e9);
            end
            s = string(s);
        end

        function openInSystem(p)
            p = char(p);
            if isfile(p), p = fileparts(p); end
            if ~isfolder(p), return; end
            if ispc
                winopen(p);
            else
                system(['open "' p '"']);
            end
        end
    end
end
