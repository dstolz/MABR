classdef BatchReport < handle
% mabr.ui.analysis.BatchReport  What a batch did, session by session, and what to do next.
%
%   Opens when a batch (mabr.ui.analysis.BatchDialog, Model.batch) ends, and
%   again from Batch ▸ Last Batch Report (with the settings that batch ran
%   with, Model.LastBatch.Settings): one row per session -- its key,
%   what happened ("ok", "ok (no thresholds)", "skipped", "failed",
%   "cancelled"), how long it took and the message -- with a line counting
%   them. Failed rows are tinted red, cancelled amber, skipped grey. From
%   here a session opens in the app (Open, the selected row), the failures
%   run again (Retry failed: Model.batch over the failed and cancelled
%   sessions, with the same settings, nothing skipped; their rows are
%   replaced, here and in Model.LastBatch.Summary), the table goes to the
%   clipboard (Copy) and the batch's CSV
%   log opens (Log).
%
%       r = mabr.ui.analysis.BatchReport(model,T,logFile);
%       r = mabr.ui.analysis.BatchReport(model,T,logFile,Visible="off");   % a test
%       T = r.read();       % the summary as it stands (Retry updates it)
%       r.apply();          % Retry failed
%       r.ok();             % close
%
%   Options (name-value): Visible "on"|"off"; Settings (what the batch ran
%   with, for Retry; [] = the project's); OpenFcn (fcn(file) for Log; [] =
%   the system's viewer).
%
%   Non-modal, and it writes no preference but its position
%   (mabr.ui.WindowPos, "OfflineAnalysisBatchReport"), remembered on every
%   way out. Retry is disabled while the Model is busy.
%
%   Tags: AnalysisBatchReportSummary, AnalysisBatchReportTable,
%   AnalysisBatchReportOpen, AnalysisBatchReportRetry,
%   AnalysisBatchReportCopy, AnalysisBatchReportLog, AnalysisBatchReportClose.
%
%   See also mabr.ui.analysis.BatchDialog, mabr.analysis.Batch
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPosition = [260 180 760 460]
        MinSize = [520 300]
    end

    properties (SetAccess = private)
        Figure = []
        Model = []
        Summary = table()          % Batch.run's table, updated by Retry
        LogFile (1,1) string = ""  % the batch's CSV log (the latest run's)
        Settings = []              % what the batch ran with ([] = the project's)
        Selected = zeros(1,0)      % table rows selected
        Done (1,1) logical = false
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners = event.listener.empty
        OpenFcn = []
        Written = struct()
    end

    methods
        function obj = BatchReport(model,summary,logFile,opts)
            % BatchReport(model,summary,logFile,Visible=,Settings=,OpenFcn=)
            arguments
                model
                summary = table()
                logFile = ""
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.Settings = []
                opts.OpenFcn = []
            end
            if ~isa(model,'mabr.ui.analysis.Model')
                error('mabr:ui:BatchReport:badModel','BatchReport needs a mabr.ui.analysis.Model.');
            end
            obj.Model = model;
            obj.LogFile = string(logFile);
            if isempty(obj.LogFile) || ismissing(obj.LogFile), obj.LogFile = ""; end
            obj.Settings = opts.Settings;
            obj.OpenFcn = opts.OpenFcn;
            if isempty(obj.OpenFcn)
                obj.OpenFcn = @(f) mabr.ui.analysis.BatchReport.openInSystem(f);
            end

            f = uifigure('Name','Batch report','Tag','MABR_OFFLINE_BATCHREPORT', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','on');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisBatchReport',obj.DefaultPosition,obj.MinSize);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;
            obj.build();
            obj.write(summary);
            obj.Listeners = event.listener(model,'BusyChanged',@(~,~) obj.syncEnable());
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        % ---- the common dialog API ----------------------------------------
        function T = read(obj)
            % The batch summary as it stands (Batch.run's columns).
            T = obj.Summary;
        end

        function write(obj,T)
            % Show summary T (Batch.run's table: Key, Status, Seconds,
            % Message, ...).
            if isempty(T), T = mabr.ui.analysis.BatchReport.emptySummary(); end
            if ~istable(T)
                error('mabr:ui:BatchReport:badSummary','The summary is a table (Batch.run''s).');
            end
            obj.Summary = T;
            obj.Selected = zeros(1,0);
            obj.redraw();
        end

        function T = apply(obj)
            % Retry failed: the failed and cancelled sessions again, nothing
            % skipped, with the settings the batch ran with; their rows are
            % replaced by the new outcome. T: the retry's own summary ([]
            % when nothing was retried).
            T = [];
            if ~obj.isopen(), return; end
            S = obj.Summary;
            if isempty(S) || height(S) == 0, return; end
            st = string(S.Status);
            keys = string(S.Key(st == "failed" | st == "cancelled"));
            if isempty(keys)
                obj.setNote("Nothing failed — there is nothing to retry.");
                return
            end
            m = obj.Model;
            try
                % (MergeInto: the Model keeps the merged summary as its
                % LastBatch, so the report reopened later lists every row)
                T = m.batch(keys,'SkipCurrent',false,'Settings',obj.Settings,'MergeInto',S);
            catch me
                obj.setNote("The retry did not run: " + string(me.message));
                return
            end
            if isempty(T), return; end
            if ~isempty(m.LastBatch), obj.LogFile = string(m.LastBatch.LogFile); end
            obj.Summary = mabr.ui.analysis.BatchReport.merge(S,T);
            obj.redraw();
        end

        function ok(obj)
            % Close.
            obj.cancel();
        end

        function cancel(obj)
            if obj.Done, return; end
            obj.Done = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function select(obj,rows)
            % Select table rows (what Open acts on).
            rows = unique(double(rows(:))).';
            obj.Selected = rows(rows >= 1 & rows <= height(obj.Summary));
            try
                mabr.ui.analysis.Compat.setSelectedRows(obj.Ctrl.Table,obj.Selected);
            catch
            end
            obj.syncEnable();
        end

        function openSelected(obj)
            % Open: the selected row's session in the app.
            if isempty(obj.Selected)
                obj.setNote("Select a session's row to open it.");
                return
            end
            key = string(obj.Summary.Key(obj.Selected(1)));
            try
                obj.Model.openSession(key);
            catch me
                obj.setNote("Could not open " + key + ": " + string(me.message));
            end
        end

        function txt = copy(obj)
            % Copy: the table as tab-separated text (also on the clipboard).
            txt = mabr.ui.analysis.FigureExport.copyTable(obj.Ctrl.Table);
            obj.setNote("The table is on the clipboard.");
        end

        function openLog(obj)
            % Log: the batch's CSV log.
            if obj.LogFile == "" || ~isfile(obj.LogFile)
                obj.setNote("There is no log file for this batch.");
                return
            end
            try
                obj.OpenFcn(obj.LogFile);
            catch me
                obj.setNote("The log could not be opened: " + string(me.message));
            end
        end
    end

    methods (Static)
        function T = merge(S,R)
            % Summary S with the rows of retry R replacing those of the same
            % Key (new keys appended).
            T = S;
            for i = 1:height(R)
                k = find(string(T.Key) == string(R.Key(i)),1);
                row = R(i,:);
                % (the columns S has; a missing one keeps its old value)
                if isempty(k)
                    try
                        T = [T; row(:,T.Properties.VariableNames)]; %#ok<AGROW>
                    catch
                    end
                    continue
                end
                for c = intersect(string(T.Properties.VariableNames),string(R.Properties.VariableNames),'stable')
                    try
                        T.(c)(k) = R.(c)(i);
                    catch
                    end
                end
            end
        end

        function T = emptySummary()
            T = table(strings(0,1),strings(0,1),zeros(0,1),strings(0,1), ...
                'VariableNames',{'Key','Status','Seconds','Message'});
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            f = obj.Figure;
            g = uigridlayout(f,[4 1]);
            g.RowHeight = {22,'1x',20,30};
            g.Padding = [12 12 12 10];
            g.RowSpacing = 6;
            obj.Ctrl.Summary = uilabel(g,'Text','','Tag','AnalysisBatchReportSummary','FontWeight','bold');
            t = uitable(g,'Tag','AnalysisBatchReportTable','RowName',{}, ...
                'ColumnName',{'Session','Status','Seconds','Message'}, ...
                'ColumnWidth',{300,110,70,'auto'}, ...
                'Tooltip','One row per session. Select a row and press Open to look at it.');
            mabr.ui.analysis.Compat.setSortable(t,false);
            mabr.ui.analysis.Compat.enableRowSelection(t,@(src,e) obj.onSelect(src,e));
            cm = uicontextmenu(f);
            uimenu(cm,'Text','Copy table','MenuSelectedFcn',@(~,~) obj.copy());
            t.ContextMenu = cm;
            obj.Ctrl.Table = t;
            obj.Ctrl.Note = uilabel(g,'Text','','FontColor',mabr.ui.analysis.Style.Muted, ...
                'Tag','AnalysisBatchReportNote');

            r = uigridlayout(g,[1 6],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.ColumnWidth = {90,120,90,100,'1x',90};
            ob = uibutton(r,'Text','Open','Tag','AnalysisBatchReportOpen', ...
                'Tooltip','Open the selected session in the analysis window.', ...
                'ButtonPushedFcn',@(~,~) obj.openSelected());
            mabr.ui.analysis.Style.setButtonIcon(ob,'inspect','left');
            obj.Ctrl.Open = ob;
            rb = uibutton(r,'Text','Retry failed','Tag','AnalysisBatchReportRetry', ...
                'Tooltip','Analyse the failed and cancelled sessions again, with the same settings.', ...
                'ButtonPushedFcn',@(~,~) obj.apply());
            mabr.ui.analysis.Style.setButtonIcon(rb,'repeat','left');
            obj.Ctrl.Retry = rb;
            cb = uibutton(r,'Text','Copy','Tag','AnalysisBatchReportCopy', ...
                'Tooltip','Copy the table to the clipboard (tab-separated, with a header row).', ...
                'ButtonPushedFcn',@(~,~) obj.copy());
            mabr.ui.analysis.Style.setButtonIcon(cb,'copy','left');
            lb = uibutton(r,'Text','Open log','Tag','AnalysisBatchReportLog', ...
                'Tooltip','Open the batch''s CSV log.','ButtonPushedFcn',@(~,~) obj.openLog());
            obj.Ctrl.Log = lb;
            xb = uibutton(r,'Text','Close','Tag','AnalysisBatchReportClose', ...
                'Tooltip','Close this report (Esc).','ButtonPushedFcn',@(~,~) obj.ok());
            xb.Layout.Column = 6;
        end

        function redraw(obj)
            if ~obj.isopen(), return; end
            S = obj.Summary;
            n = height(S);
            key = mabr.ui.analysis.BatchReport.col(S,'Key',"");
            st  = mabr.ui.analysis.BatchReport.col(S,'Status',"");
            msg = mabr.ui.analysis.BatchReport.col(S,'Message',"");
            sec = zeros(n,1);
            if ismember('Seconds',S.Properties.VariableNames), sec = round(double(S.Seconds),1); end
            % seconds as text: a numeric column would read "3.2000"
            secTxt = arrayfun(@(x) sprintf('%.1f',x),sec,'UniformOutput',false);
            secTxt(~isfinite(sec)) = {''};
            t = obj.Ctrl.Table;
            t.Data = table(cellstr(key),cellstr(st),secTxt,cellstr(msg), ...
                'VariableNames',{'Key','Status','Seconds','Message'});
            try
                removeStyle(t);
                addStyle(t,uistyle('HorizontalAlignment','right'),'column',3);
                fl = find(st == "failed");
                if ~isempty(fl)
                    addStyle(t,uistyle('BackgroundColor',mabr.ui.analysis.Style.BarRed),'row',fl);
                end
                ca = find(st == "cancelled");
                if ~isempty(ca)
                    addStyle(t,uistyle('BackgroundColor',mabr.ui.analysis.Style.BarAmber),'row',ca);
                end
                sk = find(st == "skipped");
                if ~isempty(sk)
                    addStyle(t,uistyle('FontColor',mabr.ui.analysis.Style.Muted),'row',sk);
                end
            catch
            end
            % "12 ok · 1 failed · 3 skipped — 4 min in all"
            kinds = ["ok","ok (no thresholds)","skipped","failed","cancelled"];
            parts = strings(1,0);
            for k = kinds
                c = sum(st == k);
                if c > 0, parts(end+1) = sprintf('%d %s',c,k); end %#ok<AGROW>
            end
            other = n - sum(ismember(st,kinds));
            if other > 0, parts(end+1) = sprintf('%d other',other); end
            if isempty(parts)
                txt = "No sessions.";
            else
                txt = strjoin(parts,"  ·  ");
                tot = sum(sec(isfinite(sec)));
                if tot > 0
                    txt = txt + " — " + replace(mabr.ui.analysis.Style.formatSeconds(tot),"≈","") + " in all";
                end
            end
            obj.Ctrl.Summary.Text = char(txt);
            obj.Ctrl.Summary.FontColor = mabr.ui.analysis.BatchReport.summaryColor(st);
            obj.Ctrl.Log.Tooltip = char("Open the batch's CSV log: " + obj.LogFile);
            obj.Selected = obj.Selected(obj.Selected <= n);
            obj.syncEnable();
        end

        function onSelect(obj,src,e)
            obj.Selected = mabr.ui.analysis.Compat.selectedRows(src,e);
            obj.syncEnable();
        end

        function syncEnable(obj)
            if ~obj.isopen(), return; end
            busy = false;
            try
                busy = obj.Model.Busy;
            catch
            end
            st = mabr.ui.analysis.BatchReport.col(obj.Summary,'Status',"");
            anyFailed = any(st == "failed" | st == "cancelled");
            obj.put('retry',obj.Ctrl.Retry,'Enable',matlab.lang.OnOffSwitchState(anyFailed && ~busy));
            obj.put('open',obj.Ctrl.Open,'Enable',matlab.lang.OnOffSwitchState(~isempty(obj.Selected) && ~busy));
            obj.put('log',obj.Ctrl.Log,'Enable',matlab.lang.OnOffSwitchState(obj.LogFile ~= "" && isfile(obj.LogFile)));
        end

        function setNote(obj,txt)
            if obj.isopen(), obj.Ctrl.Note.Text = char(txt); end
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
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisBatchReport');
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end

    methods (Static, Access = private)
        function v = col(T,name,default)
            n = height(T);
            if ismember(name,T.Properties.VariableNames)
                v = string(T.(name));
                v(ismissing(v)) = default;
            else
                v = repmat(string(default),n,1);
            end
            v = reshape(v,[],1);
        end

        function c = summaryColor(st)
            if any(st == "failed")
                c = mabr.ui.analysis.Style.Error;
            elseif any(st == "cancelled")
                c = mabr.ui.analysis.Style.AccentText;
            else
                c = mabr.ui.analysis.Style.Good;
            end
        end

        function openInSystem(f)
            f = char(f);
            if ~isfile(f), return; end
            if ispc
                winopen(f);
            else
                system(['open "' f '"']);
            end
        end
    end
end
