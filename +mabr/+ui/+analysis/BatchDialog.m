classdef BatchDialog < handle
% mabr.ui.analysis.BatchDialog  Analyse many sessions at once, with a cost said up front.
%
%   The analysis app's Analyse Sessions… window: which sessions (the
%   browser's selection, the ones out of date, all of them), with which
%   settings (the project's, a built-in profile, or a .mabraset file -- a
%   profile analyses with those settings without making them the
%   project's), and how (skip what is up to date, Test Mode sessions, a
%   summary figure per session, stop at the first failure), with an
%   estimate of what that costs ("40 sessions · ≈51 min"). Start closes the
%   window and runs Model.batch -- in this MATLAB, with a progress window
%   whose Cancel stops after the session in progress -- then opens the
%   mabr.ui.analysis.BatchReport of what happened.
%
%       d = mabr.ui.analysis.BatchDialog(model,selectedKeys);
%       d = mabr.ui.analysis.BatchDialog(model,keys,Visible="off");   % a test
%       v = d.read();     % Scope, Keys, Profile, Settings, SkipCurrent, ...
%       d.ok();           % close, run the batch, open the report (d.Report)
%
%   Options (name-value): Visible "on"|"off"; PickFileFcn (path =
%   fcn(filter,title,mode,default); [] = the Model's) for "Settings file…";
%   OpenReport (true: Start opens the BatchReport).
%
%   Start is disabled while the Model is busy, and when the scope holds
%   nothing to analyse (its tooltip and the estimate line say why). The
%   window writes no preference but its position (mabr.ui.WindowPos,
%   "OfflineAnalysisBatch"), remembered on every way out.
%
%   Tags: AnalysisBatchScope, AnalysisBatchProfile, AnalysisBatchSkipCurrent,
%   AnalysisBatchTestMode, AnalysisBatchFigures, AnalysisBatchStopOnError,
%   AnalysisBatchEstimate, AnalysisBatchStart, AnalysisBatchCancel.
%
%   See also mabr.analysis.Batch, mabr.ui.analysis.BatchReport,
%   mabr.ui.analysis.Model
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPosition = [240 160 560 420]
        Scopes = ["selected","outofdate","all"]
        FileItem = "Settings file…"
    end

    properties (SetAccess = private)
        Figure = []
        Model = []
        Keys (:,1) string = strings(0,1)   % the browser's selection
        Report = []                        % the BatchReport Start opened
        LastSummary = []                   % Model.batch's table of the last run
        Done (1,1) logical = false
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners = event.listener.empty
        PickFileFcn = []
        OpenReport (1,1) logical = true
        Profiles = struct('Label',{},'Kind',{},'Value',{},'Settings',{})
        LastProfile (1,1) double = 1
        Written = struct()
        WhyNot (1,1) string = ""
    end

    methods
        function obj = BatchDialog(model,keys,opts)
            % BatchDialog(model,keys,Visible=,PickFileFcn=,OpenReport=)
            arguments
                model
                keys string = strings(0,1)
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.PickFileFcn = []
                opts.OpenReport (1,1) logical = true
            end
            if ~isa(model,'mabr.ui.analysis.Model')
                error('mabr:ui:BatchDialog:badModel','BatchDialog needs a mabr.ui.analysis.Model.');
            end
            obj.Model = model;
            obj.Keys = reshape(keys,[],1);
            obj.PickFileFcn = opts.PickFileFcn;
            if isempty(obj.PickFileFcn), obj.PickFileFcn = model.PickFileFcn; end
            obj.OpenReport = opts.OpenReport;
            obj.Profiles = struct('Label',"Project settings",'Kind',"project",'Value',"",'Settings',[]);
            for n = mabr.analysis.Settings.profileNames()
                obj.Profiles(end+1) = struct('Label',n,'Kind',"builtin",'Value',n,'Settings',[]);
            end

            f = uifigure('Name','Analyse sessions','Tag','MABR_OFFLINE_BATCH', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','off');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisBatch',obj.DefaultPosition);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;
            obj.build();
            if isempty(obj.Keys)
                obj.Ctrl.Scope.Value = 'outofdate';
            end
            obj.recompute();
            obj.Listeners = event.listener(model,'BusyChanged',@(~,~) obj.syncEnable());
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
            try
                if ~isempty(obj.Report) && isvalid(obj.Report), delete(obj.Report); end
            catch
            end
        end

        % ---- the common dialog API ----------------------------------------
        function v = read(obj)
            % The batch as chosen: Scope, Keys (the sessions it would
            % analyse), Profile (label), Settings ([] = the project's),
            % SkipCurrent, IncludeTestMode, SummaryFigure, StopOnError.
            v = struct('Scope',"selected",'Keys',strings(0,1),'Profile',"Project settings", ...
                'Settings',[],'SkipCurrent',true,'IncludeTestMode',false,'SummaryFigure',false, ...
                'StopOnError',false);
            if ~obj.isopen(), return; end
            c = obj.Ctrl;
            v.Scope = string(c.Scope.Value);
            v.Keys = obj.scopeKeys(v.Scope);
            p = obj.Profiles(obj.profileIndex());
            v.Profile = p.Label;
            v.Settings = obj.settingsOf(p);
            v.SkipCurrent     = logical(c.SkipCurrent.Value);
            v.IncludeTestMode = logical(c.TestMode.Value);
            v.SummaryFigure   = logical(c.Figures.Value);
            v.StopOnError     = logical(c.StopOnError.Value);
        end

        function write(obj,v)
            % Put choices V (any of read()'s fields; Profile a label of the
            % list, a built-in's name, or a .mabraset path) into the window.
            if ~obj.isopen() || ~isstruct(v), return; end
            c = obj.Ctrl;
            if isfield(v,'Keys') && isfield(v,'Scope') && string(v.Scope) == "selected"
                obj.Keys = reshape(string(v.Keys),[],1);
                obj.syncScopeItems();
            end
            if isfield(v,'Scope') && any(obj.Scopes == string(v.Scope))
                c.Scope.Value = char(string(v.Scope));
            end
            if isfield(v,'Profile')
                obj.chooseProfile(string(v.Profile));
            end
            map = ["SkipCurrent","SkipCurrent"; "IncludeTestMode","TestMode"; ...
                "SummaryFigure","Figures"; "StopOnError","StopOnError"];
            for k = 1:size(map,1)
                if isfield(v,map(k,1)), c.(map(k,2)).Value = logical(v.(map(k,1))); end
            end
            obj.recompute();
        end

        function T = apply(obj)
            % Run the batch now (the window stays open): Model.batch's
            % summary table ([] when refused or nothing ran).
            T = [];
            if ~obj.isopen(), return; end
            obj.recompute();
            if obj.WhyNot ~= ""
                obj.say(obj.WhyNot);
                return
            end
            T = obj.runBatch(obj.read());
        end

        function T = ok(obj)
            % Start: close the window, run the batch, open the report.
            T = [];
            if ~obj.isopen(), return; end
            obj.recompute();
            if obj.WhyNot ~= ""
                obj.say(obj.WhyNot);
                return
            end
            v = obj.read();
            vis = string(obj.Figure.Visible);
            obj.Done = true;
            obj.closeFigure();
            T = obj.runBatch(v);
            if ~isempty(T) && obj.OpenReport
                m = obj.Model;
                log = "";
                if ~isempty(m.LastBatch), log = string(m.LastBatch.LogFile); end
                obj.Report = mabr.ui.analysis.BatchReport(m,T,log,'Settings',v.Settings,'Visible',vis);
            end
        end

        function cancel(obj)
            if obj.Done, return; end
            obj.Done = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function txt = estimateText(obj)
            % The estimate line as it reads now.
            txt = "";
            if obj.isopen(), txt = string(obj.Ctrl.Estimate.Text); end
        end
    end

    methods (Static)
        function T = run(model,keys,varargin)
            % Show the dialog and wait (uiwait); the batch's summary, or []
            % when cancelled. The BatchReport Start opened stays open.
            % Interactive use only.
            d = mabr.ui.analysis.BatchDialog(model,keys,varargin{:});
            if d.isopen()
                uiwait(d.Figure);
            end
            T = d.LastSummary;
            % The report Start opened must outlive this function: d's
            % delete (when d goes out of scope here) closes the report it
            % holds, so it lets go of it first. The report's own window
            % callbacks keep it alive until the user closes it.
            d.Report = [];
            delete(d);
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            f = obj.Figure;
            g = uigridlayout(f,[9 2]);
            g.RowHeight = {26,26,24,24,24,24,'fit','1x',30};
            g.ColumnWidth = {120,'1x'};
            g.Padding = [14 12 14 10];
            g.RowSpacing = 7;

            uilabel(g,'Text','Sessions');
            obj.Ctrl.Scope = uidropdown(g,'Items',{'Selected','Out of date or not analysed','All'}, ...
                'ItemsData',cellstr(obj.Scopes),'Tag','AnalysisBatchScope', ...
                'Tooltip','Which sessions to analyse: the browser''s selection, those not up to date, or every session.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            obj.syncScopeItems();
            uilabel(g,'Text','Settings');
            obj.Ctrl.Profile = uidropdown(g,'Items',{'x'},'Tag','AnalysisBatchProfile', ...
                'Tooltip',['The project''s settings, a built-in profile, or a .mabraset file. A profile ' ...
                'analyses with its settings without making them the project''s.'], ...
                'ValueChangedFcn',@(~,~) obj.onProfile());
            obj.syncProfileItems(1);
            k = uicheckbox(g,'Text','Skip sessions already up to date','Value',true, ...
                'Tag','AnalysisBatchSkipCurrent', ...
                'Tooltip','Leave alone a session whose results match these settings and its files.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            k.Layout.Row = 3; k.Layout.Column = [1 2];
            obj.Ctrl.SkipCurrent = k;
            k = uicheckbox(g,'Text','Include Test Mode sessions','Value',false,'Tag','AnalysisBatchTestMode', ...
                'Tooltip','Test Mode sessions recorded the stimulus, not a subject; they are skipped unless ticked.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            k.Layout.Row = 4; k.Layout.Column = [1 2];
            obj.Ctrl.TestMode = k;
            k = uicheckbox(g,'Text','A summary figure per session','Value',false,'Tag','AnalysisBatchFigures', ...
                'Tooltip','Write a response grid and threshold figure for each session beside its results.');
            k.Layout.Row = 5; k.Layout.Column = [1 2];
            obj.Ctrl.Figures = k;
            k = uicheckbox(g,'Text','Stop at the first failure','Value',false,'Tag','AnalysisBatchStopOnError', ...
                'Tooltip','Stop the batch when a session fails (otherwise it is logged and the batch goes on).');
            k.Layout.Row = 6; k.Layout.Column = [1 2];
            obj.Ctrl.StopOnError = k;
            e = uilabel(g,'Text','','Tag','AnalysisBatchEstimate','FontWeight','bold', ...
                'WordWrap','on','Tooltip','How many sessions will be analysed, and roughly how long it takes.');
            e.Layout.Row = 7; e.Layout.Column = [1 2];
            obj.Ctrl.Estimate = e;
            nt = uilabel(g,'WordWrap','on','VerticalAlignment','top','FontColor',mabr.ui.analysis.Style.Muted, ...
                'Text',['The batch runs in this MATLAB: Cancel in its progress window stops after the ' ...
                'session in progress. Every session''s edits survive the re-analysis, and a log is written ' ...
                'under the results folder''s logs.']);
            nt.Layout.Row = 8; nt.Layout.Column = [1 2];
            obj.Ctrl.Note = nt;

            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 9; r.Layout.Column = [1 2];
            r.ColumnWidth = {'1x',110,90};
            st = uibutton(r,'Text','Start','Tag','AnalysisBatchStart', ...
                'Tooltip','Close this window and analyse the sessions.','ButtonPushedFcn',@(~,~) obj.ok());
            st.Layout.Column = 2;
            mabr.ui.analysis.Style.setButtonIcon(st,'play','left');
            obj.Ctrl.Start = st;
            cb = uibutton(r,'Text','Cancel','Tag','AnalysisBatchCancel', ...
                'Tooltip','Close without analysing anything (Esc).','ButtonPushedFcn',@(~,~) obj.cancel());
            cb.Layout.Column = 3;
        end

        function syncScopeItems(obj)
            items = obj.Ctrl.Scope.Items;
            if isempty(obj.Keys)
                items{1} = 'Selected (none)';
            else
                items{1} = sprintf('Selected (%d)',numel(obj.Keys));
            end
            obj.Ctrl.Scope.Items = items;
        end

        function syncProfileItems(obj,k)
            labels = [obj.Profiles.Label obj.FileItem];
            obj.Ctrl.Profile.Items = cellstr(labels);
            obj.Ctrl.Profile.ItemsData = num2cell(1:numel(labels));
            obj.Ctrl.Profile.Value = k;
            obj.LastProfile = k;
        end

        function k = profileIndex(obj)
            k = obj.Ctrl.Profile.Value;
            if ~isnumeric(k) || k < 1 || k > numel(obj.Profiles), k = obj.LastProfile; end
        end

        function onProfile(obj)
            k = obj.Ctrl.Profile.Value;
            if k > numel(obj.Profiles)
                % "Settings file…": choose one; cancelled leaves the last choice
                f = string(obj.PickFileFcn("*.mabraset","Settings for the batch","open",""));
                if isempty(f) || ismissing(f) || f == ""
                    obj.Ctrl.Profile.Value = obj.LastProfile;
                    return
                end
                if ~obj.addFile(f)
                    obj.Ctrl.Profile.Value = obj.LastProfile;
                    return
                end
            else
                obj.LastProfile = k;
            end
            obj.recompute();
        end

        function ok = addFile(obj,f)
            % A .mabraset file as a choice of the list (selected).
            ok = false;
            try
                s = mabr.analysis.Settings.load(f);
            catch me
                obj.say("Could not read " + f + ": " + string(me.message));
                return
            end
            [~,nm,ext] = fileparts(f);
            k = find([obj.Profiles.Kind] == "file" & [obj.Profiles.Value] == f,1);
            if isempty(k)
                obj.Profiles(end+1) = struct('Label',"File: " + nm + ext,'Kind',"file",'Value',f,'Settings',s);
                k = numel(obj.Profiles);
            else
                obj.Profiles(k).Settings = s;
            end
            obj.syncProfileItems(k);
            ok = true;
        end

        function chooseProfile(obj,p)
            k = find([obj.Profiles.Label] == p | [obj.Profiles.Value] == p,1);
            if isempty(k) && (endsWith(p,".mabraset") || isfile(p))
                obj.addFile(p);
                return
            end
            if isempty(k), return; end
            obj.syncProfileItems(k);
        end

        function s = settingsOf(~,p)
            % [] for the project's; the profile's or the file's Settings.
            switch p.Kind
                case "builtin"
                    s = mabr.analysis.Settings.profile(p.Value);
                case "file"
                    s = p.Settings;
                otherwise
                    s = [];
            end
        end

        function keys = scopeKeys(obj,scope)
            % The sessions a scope names (before skipping): the selection,
            % the ones not current, or every session and pool -- the last
            % two leaving the hidden ones out.
            m = obj.Model;
            keys = strings(0,1);
            V = obj.view();
            shown = true(height(V),1);
            if ~isempty(V) && ismember('Hidden',V.Properties.VariableNames)
                shown = ~logical(V.Hidden);
            end
            switch string(scope)
                case "selected"
                    keys = obj.Keys;
                case "outofdate"
                    if ~isempty(V) && height(V) > 0
                        keys = string(V.Key(string(V.Status) ~= "current" & shown));
                    end
                otherwise
                    if ~isempty(V) && height(V) > 0
                        keys = string(V.Key(shown));
                    else
                        try
                            keys = m.allKeys();
                        catch
                        end
                    end
            end
            keys = reshape(keys,[],1);
        end

        function V = view(obj)
            V = table();
            try
                V = obj.Model.projectView();
            catch
            end
        end

        function recompute(obj)
            % The estimate line, and whether Start can run.
            if ~obj.isopen(), return; end
            c = obj.Ctrl;
            scope = string(c.Scope.Value);
            keys = obj.scopeKeys(scope);
            p = obj.Profiles(obj.profileIndex());
            s = obj.settingsOf(p);
            if isempty(s), s = obj.Model.Settings; end
            V = obj.view();
            nCur = 0; nTest = 0; sec = 0;
            run = keys;
            if ~isempty(V) && height(V) > 0 && ~isempty(keys)
                [tf,loc] = ismember(keys,string(V.Key));
                R = V(loc(tf),:);
                drop = false(height(R),1);
                if ~c.TestMode.Value && ismember('TestMode',R.Properties.VariableNames)
                    t = string(R.TestMode) == "all";
                    nTest = sum(t);
                    drop = drop | t;
                end
                % "Up to date" is judged against the project's settings; a
                % profile is assumed to make every session out of date.
                if c.SkipCurrent.Value && p.Kind == "project"
                    cur = string(R.Status) == "current" & ~drop;
                    nCur = sum(cur);
                    drop = drop | cur;
                end
                R = R(~drop,:);
                run = string(R.Key);
                for i = 1:height(R)
                    sec = sec + obj.sessionSeconds(R(i,:),s);
                end
                run = [run; keys(~tf)];             % keys the view does not list
            end
            n = numel(run);
            skipped = strings(1,0);
            if nCur > 0, skipped(end+1) = sprintf('%d up to date',nCur); end
            if nTest > 0, skipped(end+1) = sprintf('%d Test Mode',nTest); end
            why = "";
            if obj.Model.ReadOnly
                why = "The results folder cannot be written — choose another (Settings ▸ Results Folder…).";
            elseif isempty(keys)
                if scope == "selected"
                    why = "No session is selected in the browser.";
                elseif scope == "outofdate"
                    why = "Every session is up to date.";
                else
                    why = "There are no sessions.";
                end
            elseif n == 0
                why = "Nothing to analyse: every session in this scope is skipped (" + strjoin(skipped,", ") + ").";
            end
            if why ~= ""
                txt = why;
            else
                if n == 1, nm = "1 session"; else, nm = sprintf('%d sessions',n); end
                txt = nm + " · " + mabr.ui.analysis.Style.formatSeconds(sec);
                if ~isempty(skipped)
                    txt = txt + " (skipping " + strjoin(skipped,", ") + ")";
                end
            end
            obj.WhyNot = why;
            obj.put('est',c.Estimate,'Text',char(txt));
            obj.syncEnable();
        end

        function sec = sessionSeconds(~,row,s)
            % Session.estimateSeconds for one view row, plus reading it.
            nf = mabr.ui.analysis.BatchDialog.rowNumber(row,'NumFiles');
            nc = mabr.ui.analysis.BatchDialog.rowNumber(row,'NumConditions');
            ns = mabr.ui.analysis.BatchDialog.rowNumber(row,'NumSeries');
            if ~isfinite(nf), nf = 0; end
            if ~isfinite(nc), nc = 0; end
            if ~(isfinite(ns) && ns > 0), ns = ceil(nc/5); end
            sec = 1 + 0.02*nf;
            try
                sec = sec + mabr.analysis.Session.estimateSeconds(s,"",nf,nc,ns);
            catch
            end
        end

        function T = runBatch(obj,v)
            m = obj.Model;
            T = [];
            try
                T = m.batch(v.Keys,'SkipCurrent',v.SkipCurrent,'IncludeTestMode',v.IncludeTestMode, ...
                    'SummaryFigure',v.SummaryFigure,'StopOnError',v.StopOnError,'Settings',v.Settings);
            catch me
                obj.say("The batch did not run: " + string(me.message));
                mabr.log.vprintf(1,'Batch dialog: %s',me.message);
            end
            obj.LastSummary = T;
        end

        function syncEnable(obj)
            if ~obj.isopen(), return; end
            busy = false;
            try
                busy = obj.Model.Busy;
            catch
            end
            on = obj.WhyNot == "" && ~busy;
            obj.put('startOn',obj.Ctrl.Start,'Enable',matlab.lang.OnOffSwitchState(on));
            if busy
                tip = 'Wait for the running job to finish.';
            elseif obj.WhyNot ~= ""
                tip = char(obj.WhyNot);
            else
                tip = 'Close this window and analyse the sessions.';
            end
            obj.put('startTip',obj.Ctrl.Start,'Tooltip',tip);
        end

        function say(obj,txt)
            try
                if obj.isopen()
                    obj.Ctrl.Note.Text = char(txt);
                    obj.Ctrl.Note.FontColor = mabr.ui.analysis.Style.Warn;
                end
            catch
            end
            mabr.log.vprintf(2,'Batch dialog: %s',char(txt));
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
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisBatch');
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end

    methods (Static, Access = private)
        function v = rowNumber(row,name)
            % A numeric column of one view row (0 when absent or not a number).
            v = 0;
            try
                if ismember(name,row.Properties.VariableNames)
                    v = double(row.(name)(1));
                end
            catch
                v = 0;
            end
        end
    end
end
