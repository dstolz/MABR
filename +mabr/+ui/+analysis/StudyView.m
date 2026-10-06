classdef StudyView < mabr.ui.analysis.View
% mabr.ui.analysis.StudyView  The Study tab: labels, thresholds, growth and grand averages across sessions.
%
%   The other tabs look at one session; this one compares them. It is built
%   from the RESULTS FILES alone (mabr.analysis.Project.aggregate), never
%   from raw data, so a study of forty sessions opens in a moment -- and it
%   is the place the labels the comparison rests on are edited:
%
%     Sessions          every session with In study, Timepoint, Group and
%                       the project's own columns editable in place (each
%                       edit is Model.label: undoable, autosaved, and a
%                       value differing from one in use only by case or
%                       spacing becomes that one, with a note on the status
%                       line), and what the comparison needs to know of each:
%                       status, review count, processing, noise, rejection,
%                       the fewest clean sweeps, units, the settings hash
%                       (a cell differing from the majority is highlighted),
%                       the Duration of the recording and the number of
%                       stimuli presented. Dropdowns filter the rows by In
%                       study, Subject, Day, Group, Stimuli and Status, and
%                       Sort by / then by order them by any column (the
%                       sort is remembered; filters are not). The table's own
%                       header sort stays off: every callback maps a row to
%                       its session through SessionKeys, so the view orders
%                       the rows itself.
%                       Beneath, the subjects: Group, In study and their own
%                       columns in place, the Comment through the table's
%                       Edit comment… (no note is typed into a table cell).
%     Thresholds        one point per subject x timepoint x series, across
%                       a parameter (Frequency) or across timepoints, with
%                       summaries across SUBJECTS (n in every legend entry).
%                       A series without a response is drawn as a triangle
%                       on a dashed ceiling at the value the No-response rule
%                       gives it -- and the rule is the plot's subtitle, so a
%                       mean that contains invented numbers says so. With a
%                       Reference the plot is the per-subject SHIFT, a point
%                       involving a censored value hollow.
%     Growth & latency  a wave's amplitude or latency (or an interpeak
%                       interval) against level or level re the subject's
%                       threshold, in µV or as % of the subject's reference
%                       timepoint. Latencies are the REPORTED ones, re sound
%                       arrival when a session has a conduction delay (13 A9).
%     Waveforms         the grand average of one condition across subjects:
%                       the mean of per-subject means, ± SEM across subjects.
%                       Series and Level each offer All: All levels stacks
%                       every level, loudest at the top, as the Grid tab
%                       does for one session -- a column per series (All
%                       series too: a frequency x level grid; a click family
%                       is one column), each subject's curve and each colour
%                       group's summary in its row, the row spacing from
%                       Scale (per column, global, fixed µV) written in each
%                       column's corner. All series at one level is a panel
%                       per series. One panel per subject makes a column per
%                       subject and series.
%
%   DUPLICATES. When two in-study sessions measured the same series of one
%   animal at one visit, Project.DuplicatePolicy decides which one the study
%   uses -- the one with most sweeps (default), the latest, or the mean of
%   both. The policy is the user's choice (the Duplicates dropdown, or the
%   banner's Choose…), is stored in the project (Model.setDuplicatePolicy,
%   undoable), and a banner says which duplicates there are and what is used.
%
%   BANNERS (one at a time, the most important): level units that differ
%   (those sessions are left out of the threshold plot), sessions analysed
%   with different settings ([Re-analyse them]), processing or amplitude
%   units that differ (left out of the growth plot), clean-sweep counts that
%   differ by more than 20% between the plotted groups, duplicated series.
%
%   The look (family, x axis, colouring, summary, layout, reference,
%   no-response rule, measure, y and x modes, the waveforms' All series /
%   All levels and their row scale) persists in the pref
%   OfflineAnalysisStudy, written ONLY from these controls' callbacks.
%
%   FOR TESTS (no clicks needed): showSub(name), selectSessions(keys),
%   clickPoint(k,Open=,Plot=), clickAt(x,y,Plot=,Tile=,Open=) (what a click
%   on the axes does), thresholdTable(), growthTable(), waveTable(),
%   the read-only ThrPoints/GrowthPoints/WaveCurves/WaveGrid/Readout/
%   BannerKind/PlotNotes, the pure statics thresholdUnits and settingsOdd, and
%   UseDialogs = false, which makes the Analyse and Review buttons call the
%   Model directly instead of opening their dialogs.
%
%   See also mabr.ui.analysis.View, mabr.ui.analysis.Model,
%   mabr.analysis.Project.aggregate, mabr.ui.AnalysisApp
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        ColorByItems = ["Timepoint","Group","Group × Timepoint","Subject","Session"]
        ColorByCodes = ["timepoint","group","group-timepoint","subject","session"]
        ShowItems    = ["Individuals","Mean ± SEM","Median (IQR)","Individuals + summary"]
        ShowCodes    = ["individuals","mean","median","both"]
        LayoutItems  = ["Overlay","One panel per subject"]
        LayoutCodes  = ["overlay","subject"]
        NoRespItems  = ["Max level + step","Max level + 5 dB","Exclude"]
        NoRespCodes  = ["step","5db","exclude"]
        PolicyItems  = ["Most sweeps","Latest","Mean of sessions"]
        PolicyCodes  = ["most-sweeps","latest","mean"]
        MeasureItems = ["P–N amplitude","Baseline–peak","Latency","Interpeak I–III","Interpeak I–V"]
        MeasureCodes = ["amp-pt","amp-bp","latency","ipl-I-III","ipl-I-V"]
        YModeCodes   = ["uv","percent"]
        XModeItems   = ["dB","dB re threshold"]
        XModeCodes   = ["db","re-threshold"]
        WaveScaleItems = ["Per column","Global","Fixed µV"]
        WaveScaleCodes = ["column","global","fixed"]      % GridView.ScaleIds
        WaveAllCode  = "(all)"        % the waveforms' Series / Level item "All …"
        FilterNames  = ["InStudy","Subject","Day","Group","Stimuli","Status"]   % the Sessions table's filters
        FilterTitles = ["In study","Subject","Day","Group","Stimuli","Status"]
        SubTabNames  = ["Sessions","Thresholds","Growth","Waveforms"]
        SubTabTitles = ["Sessions","Thresholds","Growth & latency","Waveforms"]
        SweepTolerance = 0.2          % groups whose median clean sweeps differ by more: banner
        ClickRadius = 0.06            % normalized axes distance a click may miss a point by
    end

    properties
        % false: the Analyse/Review buttons call the Model (batch,
        % startReviewQueue) instead of opening BatchDialog/ReviewDialog --
        % for tests, and for a MABR without those dialogs.
        UseDialogs (1,1) logical = true
    end

    properties (SetAccess = private)
        ActiveSub (1,1) string = "Sessions"   % the sub-tab showing
        Data = []                     % the cached study (see ensureData)
        SelectedKeys (:,1) string = strings(0,1)   % sessions selected in the table
        SelectedColumn (1,1) string = ""         % the label column last selected
        ThrPoints = table()           % the threshold points drawn (one per unit)
        GrowthPoints = table()        % the growth points drawn
        WaveCurves = table()          % the per-subject curves the waveforms draw
        % What the stacked waveform grid (All levels) last drew: Columns
        % (titles, left to right), Levels (bottom to top), RowY, RowScale
        % (µV between two rows, per column), Groups (colour groups);
        % struct() when the waveforms are not a grid.
        WaveGrid = struct()
        Readout (1,1) string = ""     % the last point's readout
        BannerKind (1,1) string = ""  % "" | units | settings | processing | sweeps | duplicates
        PlotNotes = struct('Thresholds',"",'Growth',"",'Waveforms',"")   % each plot's subtitle
    end

    properties (Access = private)
        StaleData (1,1) logical = true      % the aggregate must be rebuilt
        WaitIdle (1,1) logical = false      % a render waits for the job to end
        AggPendingSave (1,1) logical = false% aggregated while a save was pending
        SubDirty = struct('Sessions',true,'Thresholds',true,'Growth',true,'Waveforms',true)
        SessionKeys (:,1) string = strings(0,1)  % the Sessions table's rows
        SessionCols (1,:) string = strings(1,0)  % label name per column ("" = read-only)
        % The Sessions table's filters ("" = all): a facet's code. Not part
        % of the look -- the values on offer belong to one study.
        SessFilter = struct('InStudy',"",'Subject',"",'Day',"",'Group',"",'Stimuli',"",'Status',"")
        SubjectKeys (:,1) string = strings(0,1)
        SubjectCols (1,:) string = strings(1,0)
        SelectedSubjects (:,1) string = strings(0,1)  % rows selected in the Subjects table
        EmptyDismissed (1,1) logical = false
        Choice = struct('Wave',"",'At',"",'Processing',"",'WaveSeries',"",'WaveLevel',"")
        BannerFcn = []                      % the banner button's action
        Selected = struct('Plot',"",'Row',0)% the point the readout describes
        % What each plot last drew (its points and look): a render that
        % would draw the same again leaves the axes alone -- an autosave
        % landing after an edit, a label that changes nothing plotted.
        DrawnSig = struct('thresholds',[],'growth',[],'waveforms',[])
        Pass = struct()                     % one render's memo (growth data, family rows)
    end

    % =====================================================================
    methods
        function obj = StudyView(parent,model,host)
            % StudyView(parent,model,host) -- see mabr.ui.analysis.View.
            if nargin < 3, host = []; end
            obj@mabr.ui.analysis.View(parent,model,host);
        end

        % ---- the View contract -------------------------------------------
        function build(obj)
            S = mabr.ui.analysis.Style;
            g = uigridlayout(obj.Parent,[3 1],'Padding',[6 6 6 6],'RowSpacing',4, ...
                'BackgroundColor',S.Panel,'Tag','AnalysisStudyRoot');
            g.RowHeight = {0,0,'1x'};
            g.Layout.Row = 1; g.Layout.Column = 1;
            obj.Handles.Root = g;

            % Row 1: the banners, two panels sharing one cell (only one shows).
            bg = uigridlayout(g,[1 1],'Padding',[0 0 0 0],'BackgroundColor',S.Panel);
            bg.Layout.Row = 1; bg.Layout.Column = 1;
            [obj.Handles.Duplicates,obj.Handles.DuplicatesText,obj.Handles.DuplicatesAction] = ...
                obj.bannerPanel(bg,"AnalysisStudyDuplicates","Choose…", ...
                "Choose how duplicated series are resolved (most sweeps, latest, or the mean of sessions)", ...
                @(~,~) obj.chooseDuplicatePolicy());
            [obj.Handles.Banner,obj.Handles.BannerText,obj.Handles.BannerAction] = ...
                obj.bannerPanel(bg,"AnalysisStudyBanner","Re-analyse them", ...
                "Analyse the sessions this banner names with the project's settings", ...
                @(~,~) obj.onBannerAction());

            % Row 2: what every plot shares -- family, colouring, summary, layout.
            sc = uigridlayout(g,[1 8],'Padding',[0 0 0 0],'ColumnSpacing',6, ...
                'BackgroundColor',S.Panel,'Tag','AnalysisStudyControls');
            sc.ColumnWidth = {'fit','1x','fit','1x','fit','1x','fit','1x'};
            sc.Layout.Row = 2; sc.Layout.Column = 1;
            obj.Handles.Family = obj.dropdown(sc,1,"Family","AnalysisStudyFamily","","", ...
                @(s,~) obj.onLook("Family",s.Value), ...
                "The stimulus family to compare (and the acquisition mode, when a family was recorded both ways)");
            obj.Handles.ColorBy = obj.dropdown(sc,3,"Colour by","AnalysisStudyColorBy", ...
                obj.ColorByItems,obj.ColorByCodes,@(s,~) obj.onLook("ColorBy",s.Value), ...
                "What the colours (and the summaries) group by");
            obj.Handles.Show = obj.dropdown(sc,5,"Show","AnalysisStudyShow",obj.ShowItems, ...
                obj.ShowCodes,@(s,~) obj.onLook("Show",s.Value), ...
                "Each subject, a summary across subjects, or both");
            obj.Handles.Layout = obj.dropdown(sc,7,"Layout","AnalysisStudyLayout",obj.LayoutItems, ...
                obj.LayoutCodes,@(s,~) obj.onLook("Layout",s.Value), ...
                "One plot for everybody, or one panel per subject");

            % Row 3: the sub-tabs.
            tg = uitabgroup(g,'Tag','AnalysisStudyTabs');
            tg.Layout.Row = 3; tg.Layout.Column = 1;
            tg.SelectionChangedFcn = obj.viewWrap(@(~,e) obj.onSubTab(e));
            obj.Handles.Tabs = tg;
            for k = 1:numel(obj.SubTabNames)
                t = uitab(tg,'Title',char(obj.SubTabTitles(k)), ...
                    'Tag',char("AnalysisStudyTab" + obj.SubTabNames(k)),'BackgroundColor',S.Panel);
                obj.Handles.("Tab" + obj.SubTabNames(k)) = t;
            end
            obj.buildSessions(obj.Handles.TabSessions);
            obj.buildThresholds(obj.Handles.TabThresholds);
            obj.buildGrowth(obj.Handles.TabGrowth);
            obj.buildWaveforms(obj.Handles.TabWaveforms);
            obj.ActiveSub = "Sessions";
        end

        function refresh(obj,what,keys) %#ok<INUSD>
            % Redraw. The routing that decides WHETHER to is onModelEvent;
            % whatever reaches here draws (activate, applySettings and the
            % events that change what the study is made of).
            if ~isvalid(obj) || ~obj.Built, return; end
            obj.render();
        end

        function onModelEvent(obj,name,data)
            % Which Model events change what the Study draws. The study is
            % made of results files and project labels, so the open session
            % moving (selection, level, a peak being dragged) changes
            % nothing here; labels, pools, settings, a batch, and any
            % results change do. A job in progress is waited out.
            what = "all";
            try
                what = string(data.What);
            catch
            end
            obj.ViewEvent = string(name);
            % (a settings change that re-fits: one aggregate, not two)
            if obj.coalescedEvent(name,data), return; end
            switch string(name)
                case "SelectionChanged"
                    return
                case "BusyChanged"
                    if what == "idle" && obj.WaitIdle
                        obj.WaitIdle = false;
                        obj.refreshOrMark("all",strings(0,1));
                    end
                    return
                case "StatusChanged"
                    % An autosave that has just landed the edits a previous
                    % aggregate could not see (they were still pending).
                    if what == "save" && obj.AggPendingSave && ...
                            any(obj.Model.SaveState == ["saved","readonly","conflict"])
                        obj.StaleData = true;
                        obj.refreshOrMark("all",strings(0,1));
                    end
                    return
                case "RootChanged"
                    % another folder: its own "no results yet" state
                    obj.EmptyDismissed = false;
                    for nm = obj.FilterNames, obj.SessFilter.(nm) = ""; end   % (its sessions are not these)
                case "SessionChanged"
                    % Blind review starts and ends with one: draw again. The
                    % study itself is not changed by which session is open
                    % -- every aggregate flushes the pending edits first, and
                    % an edit made since raised its own Results/ProjectChanged
                    % -- so this is no reason to read the results again,
                    % unless the last aggregate could not see edits that a
                    % conflict or a read-only store held back (Load theirs).
                    if obj.AggPendingSave, obj.StaleData = true; end
                    obj.refreshOrMark("all",strings(0,1));
                    return
            end
            obj.StaleData = true;
            obj.refreshOrMark(what,strings(0,1));
        end

        function s = displaySettings(obj)
            s = obj.ViewLook;
        end

        % ---- public, for the window and for tests ---------------------
        function showSub(obj,name)
            % Show a sub-tab: "Sessions" | "Thresholds" | "Growth" |
            % "Waveforms" (the titles work too).
            arguments
                obj
                name (1,1) string
            end
            k = find(lower(obj.SubTabNames) == lower(name) | lower(obj.SubTabTitles) == lower(name),1);
            if isempty(k)
                error('mabr:ui:StudyView:badTab','There is no "%s" sub-tab.',name);
            end
            obj.Handles.Tabs.SelectedTab = obj.Handles.("Tab" + obj.SubTabNames(k));
            obj.switchSub(obj.SubTabNames(k));
        end

        function selectSessions(obj,keys)
            % Select sessions (rows of the Sessions table) by key.
            keys = reshape(string(keys),[],1);
            obj.SelectedKeys = keys(ismember(keys,obj.SessionKeys));
            [~,rows] = ismember(obj.SelectedKeys,obj.SessionKeys);
            mabr.ui.analysis.Compat.setSelectedRows(obj.Handles.Sessions,rows);
            obj.syncButtons();
        end

        function txt = clickPoint(obj,k,opts)
            % What a click on the k-th point of a plot does: the readout,
            % and with Open (a double-click) the session opened on that
            % series in the Series tab.
            %   k          row of ThrPoints (Plot "thresholds") or GrowthPoints
            %   opts.Open  a double-click (default false)
            %   opts.Plot  "thresholds" (default) | "growth"
            arguments
                obj
                k (1,1) double {mustBeInteger,mustBePositive}
                opts.Open (1,1) logical = false
                opts.Plot (1,1) string {mustBeMember(opts.Plot,["thresholds","growth"])} = "thresholds"
            end
            txt = obj.selectPoint(opts.Plot,k,opts.Open);
        end

        function txt = clickAt(obj,x,y,opts)
            % A click on a plot at (x,y) in data units -- what the axes'
            % ButtonDownFcn does with CurrentPoint: the nearest point within
            % reach is read out (and, with Open, its session opened on that
            % series). "" when no point is near.
            %   opts.Plot  "thresholds" (default) | "growth"
            %   opts.Tile  which panel ("" = the first; a subject's name
            %              under one panel per subject, "8 kHz" across
            %              timepoints)
            %   opts.Open  a double-click (default false)
            arguments
                obj
                x (1,1) double
                y (1,1) double
                opts.Plot (1,1) string {mustBeMember(opts.Plot,["thresholds","growth"])} = "thresholds"
                opts.Tile (1,1) string = ""
                opts.Open (1,1) logical = false
            end
            txt = "";
            key = char("Ax_" + opts.Plot);
            if ~isfield(obj.Handles,key), return; end
            ax = obj.Handles.(key);
            ax = ax(isgraphics(ax));
            for a = reshape(ax,1,[])
                ud = a.UserData;
                if ~isstruct(ud) || ~isfield(ud,'Tile'), continue; end
                if string(ud.Tile) == opts.Tile || (opts.Tile == "" && a == ax(1))
                    txt = obj.pointAt(a,x,y,opts.Open);
                    return
                end
            end
        end

        function T = thresholdTable(obj)
            % The threshold points drawn (ThrPoints).
            T = obj.ThrPoints;
        end

        function k = tableKeys(obj)
            % The session key of each row of the Sessions table, in order.
            k = obj.SessionKeys;
        end

        function txt = copyTable(obj,which)
            % A table as tab-separated text with its header row (also put
            % on the clipboard) -- the tables' "Copy table".
            %   which  "sessions" (default) | "subjects"
            arguments
                obj
                which (1,1) string {mustBeMember(which,["sessions","subjects"])} = "sessions"
            end
            if which == "subjects", t = obj.Handles.Subjects; else, t = obj.Handles.Sessions; end
            txt = "";
            try
                names = cellstr(matlab.lang.makeUniqueStrings(string(t.ColumnName)));
                D = t.Data;
                if iscell(D)
                    T = cell2table(D,'VariableNames',names);
                else
                    T = D;
                end
                txt = mabr.ui.analysis.FigureExport.copyTable(T);
            catch me
                mabr.log.vprintf(2,'Study view: copy table failed (%s).',me.message);
            end
        end

        function T = growthTable(obj)
            T = obj.GrowthPoints;
        end

        function T = waveTable(obj)
            T = obj.WaveCurves;
        end

        function flush(obj)
            % Draw now whatever is waiting (tests call this).
            if obj.IsActive && (obj.Dirty || obj.StaleData)
                obj.Dirty = false;
                obj.safeRefresh("all",strings(0,1));
            end
        end
    end

    % =====================================================================
    methods (Static)
        function d = factoryDefaults()
            % The look a new window opens with.
            d = struct('Family',"",'X',"",'ColorBy',"timepoint",'Show',"both", ...
                'Layout',"overlay",'Reference',"none",'NoResponse',"step", ...
                'Measure',"amp-pt",'YMode',"uv",'XMode',"db", ...
                'WaveAllSeries',false,'WaveAllLevels',false,'WaveScale',"column",'WaveFixed',5, ...
                'SessSort1',"",'SessDir1',"ascending",'SessSort2',"",'SessDir2',"ascending");
        end

        function d = loadDefaults()
            % The look the last window was left with (pref
            % OfflineAnalysisStudy), forgiving of a pref from another version.
            % (the Constants by class name: naming the class alone would
            % construct a view)
            f = mabr.ui.analysis.StudyView.factoryDefaults();
            d = mabr.ui.analysis.View.loadLook("OfflineAnalysisStudy",f);
            chk = {'ColorBy',mabr.ui.analysis.StudyView.ColorByCodes; ...
                'Show',mabr.ui.analysis.StudyView.ShowCodes; ...
                'Layout',mabr.ui.analysis.StudyView.LayoutCodes; ...
                'NoResponse',mabr.ui.analysis.StudyView.NoRespCodes; ...
                'Measure',mabr.ui.analysis.StudyView.MeasureCodes; ...
                'YMode',mabr.ui.analysis.StudyView.YModeCodes; ...
                'XMode',mabr.ui.analysis.StudyView.XModeCodes; ...
                'WaveScale',mabr.ui.analysis.StudyView.WaveScaleCodes};
            for i = 1:size(chk,1)
                if ~any(string(d.(chk{i,1})) == chk{i,2}), d.(chk{i,1}) = f.(chk{i,1}); end
            end
            for n = ["Family","X","Reference","SessSort1","SessSort2"]
                d.(n) = string(d.(n));
                if ~isscalar(d.(n)) || ismissing(d.(n)), d.(n) = f.(n); end
            end
            for n = ["SessDir1","SessDir2"]
                d.(n) = string(d.(n));
                if ~isscalar(d.(n)) || ~any(d.(n) == ["ascending","descending"]), d.(n) = f.(n); end
            end
            for n = ["WaveAllSeries","WaveAllLevels"]
                v = d.(n);
                if (islogical(v) || isnumeric(v)) && isscalar(v), d.(n) = logical(v); else, d.(n) = f.(n); end
            end
            v = d.WaveFixed;
            if isnumeric(v) && isscalar(v) && isfinite(v) && v > 0
                d.WaveFixed = double(v);
            else
                d.WaveFixed = f.WaveFixed;
            end
        end

        function saveDefaults(d)
            % Remember the look (from the controls, or a configuration).
            mabr.ui.analysis.View.saveLook("OfflineAnalysisStudy",d);
        end

        function [P,info] = thresholdUnits(T,opts)
            % The threshold plot's points from Thresholds rows (pure).
            %
            %   T  aggregate Thresholds rows of ONE family, already filtered
            %      to UsedInStudy (Session, Subject, Timepoint, TimepointOrder,
            %      Group, Key, Final, FinalCensored, FinalLo, FinalHi,
            %      Decision, MinLevel, MaxLevel, LevelStep; optionally
            %      StartTime, the session's start in posix seconds)
            %   opts.NoResponse  "step" | "5db" | "exclude"
            %   opts.Reference   "none" | "first" | "tp:<timepoint>" -- "first"
            %                    is each subject's first session of the
            %                    series: in Timepoint order, the start time
            %                    breaking ties and ordering sessions that
            %                    have no timepoint
            %   opts.Params      the family's group parameters (X axis)
            %   opts.Direction   the settings' LevelDirection ("auto" |
            %                    "ascending" | "descending"): which way a
            %                    row's levels are louder when T has no
            %                    LevelDirection column; "auto" reads a level
            %                    parameter named like Attenuation as
            %                    descending (Session's rule)
            %   P  (returned) one row per subject x timepoint x series:
            %      Subject, Timepoint, TimepointOrder, Group, Session (first
            %      key), Sessions ("|"-joined: the "mean" policy may use
            %      several), SeriesKey, X (first parameter's value, NaN none),
            %      Series ("8 kHz"), Value (the threshold as plotted, no-
            %      response substituted), Kind ("value"|"noresponse"|
            %      "allrespond"), Censored, Plotted (Value, or the shift),
            %      Hollow, Decision, Reviewed, Text, RefText, Ceiling,
            %      StartTime (the earliest of its sessions'), RefTimepoint
            %   info  NoResponse (count), Ceilings, AllRespond, Excluded,
            %         NoReference, Shift (logical), RefName
            arguments
                T table
                opts.NoResponse (1,1) string = "step"
                opts.Reference (1,1) string = "none"
                opts.Params (1,:) string = strings(1,0)
                opts.Direction (1,1) string {mustBeMember(opts.Direction,["auto","ascending","descending"])} = "auto"
            end
            info = struct('NoResponse',0,'Ceilings',zeros(0,1),'AllRespond',0,'Excluded',0, ...
                'Dropped',0,'NoReference',0,'Shift',false,'RefName',"");
            P = mabr.ui.analysis.StudyView.emptyUnits();
            if isempty(T) || height(T) == 0, return; end
            n = height(T);
            col = @(name,def) mabr.ui.analysis.StudyView.column(T,name,def);
            dec = col("Decision",strings(n,1));
            dec(ismissing(dec)) = "";
            keep = dec ~= "excluded";
            info.Excluded = nnz(~keep);
            fin  = double(col("Final",NaN(n,1)));
            cen  = col("FinalCensored",repmat("none",n,1));
            cen(ismissing(cen)) = "none";
            lo   = double(col("FinalLo",NaN(n,1)));
            hi   = double(col("FinalHi",NaN(n,1)));
            mx   = double(col("MaxLevel",NaN(n,1)));
            mn   = double(col("MinLevel",NaN(n,1)));
            st   = double(col("LevelStep",NaN(n,1)));
            st(~(st > 0)) = 5;
            val  = fin;
            kind = repmat("value",n,1);
            ceil_ = NaN(n,1);
            % Censoring describes the NUMBERS (SeriesThreshold): "right"
            % (above the largest) is no response on a dB SPL axis but all
            % respond on an attenuation axis, and "left" the other way about
            % -- SeriesView.censorMeaning's rule, per row.
            sgn = mabr.ui.analysis.StudyView.levelSigns(T,opts.Direction);
            nr = (cen == "right" & sgn > 0) | (cen == "left" & sgn < 0) | (isinf(fin) & sign(fin) == sgn);
            lf = ((cen == "left" & sgn > 0) | (cen == "right" & sgn < 0) | ...
                (isinf(fin) & sign(fin) == -sgn)) & ~nr;
            % no response is drawn a step beyond the loudest level tested
            % (above the largest dB SPL, below the smallest attenuation);
            % all respond at the quietest bound
            loud = mx;   loud(sgn < 0) = mn(sgn < 0);
            quiet = mn;  quiet(sgn < 0) = mx(sgn < 0);
            bound = hi;  bound(sgn < 0) = lo(sgn < 0);
            switch opts.NoResponse
                case "5db",     ceil_(nr) = loud(nr) + 5*sgn(nr);
                case "exclude", keep = keep & ~nr;
                otherwise,      ceil_(nr) = loud(nr) + st(nr).*sgn(nr);
            end
            val(nr) = ceil_(nr);
            kind(nr) = "noresponse";
            a = bound(lf);  q = quiet(lf);
            a(~isfinite(a)) = q(~isfinite(a));
            val(lf) = a;
            kind(lf) = "allrespond";
            if opts.NoResponse == "exclude", info.Dropped = nnz(nr & dec ~= "excluded"); end
            keep = keep & isfinite(val);
            txt = reshape(mabr.analysis.SeriesThreshold.formatValue(fin,cen,lo,hi),[],1);
            sk = string(col("Key",strings(n,1)));
            % the first parameter's value and the series' name
            x = NaN(n,1);  ser = strings(n,1);
            for i = 1:n
                [x(i),ser(i)] = mabr.ui.analysis.StudyView.seriesValue(sk(i),opts.Params);
            end
            U = table(string(col("Subject",strings(n,1))),string(col("Timepoint",strings(n,1))), ...
                double(col("TimepointOrder",NaN(n,1))),string(col("Group",strings(n,1))), ...
                string(col("Session",strings(n,1))),sk,x,ser,val,kind,kind ~= "value",dec, ...
                dec ~= "",txt,ceil_,double(col("StartTime",NaN(n,1))),'VariableNames', ...
                {'Subject','Timepoint','TimepointOrder','Group','Session','SeriesKey','X', ...
                'Series','Value','Kind','Censored','Decision','Reviewed','Text','Ceiling','StartTime'});
            U = U(keep,:);
            if height(U) == 0, return; end

            % One unit per subject x timepoint x series: the "mean" policy
            % lets several sessions provide one; they are averaged here.
            ukey = U.Subject + "|" + lower(U.Timepoint) + "|" + U.SeriesKey;
            [gk,first,j] = unique(ukey,'stable');
            m = numel(gk);
            P = U(first,:);
            P.Sessions = P.Session;
            for q = 1:m
                r = find(j == q);
                if numel(r) < 2, continue; end
                P.Value(q) = mean(U.Value(r));
                P.Sessions(q) = join(U.Session(r),"|");
                k = unique(U.Kind(r));
                if isscalar(k), P.Kind(q) = k; else, P.Kind(q) = "value"; end
                P.Censored(q) = any(U.Censored(r));
                P.Reviewed(q) = all(U.Reviewed(r));
                P.Text(q) = join(U.Text(r)," / ");
                P.Ceiling(q) = max(U.Ceiling(r));
                P.StartTime(q) = min(U.StartTime(r));
            end
            P.Plotted = P.Value;
            P.Hollow  = false(height(P),1);
            P.RefText = strings(height(P),1);
            P.RefTimepoint = strings(height(P),1);

            info.NoResponse = nnz(P.Kind == "noresponse");
            info.AllRespond = nnz(P.Kind == "allrespond");
            info.Ceilings = unique(P.Ceiling(P.Kind == "noresponse"));

            % The shift re a reference timepoint, per subject and series.
            ref = opts.Reference;
            if ref == "none" || ref == "", return; end
            info.Shift = true;
            haveRef = false(height(P),1);
            for i = 1:height(P)
                rows = find(P.Subject == P.Subject(i) & P.SeriesKey == P.SeriesKey(i));
                if startsWith(ref,"tp:")
                    name = extractAfter(ref,3);
                    r0 = rows(lower(P.Timepoint(rows)) == lower(name));
                else
                    r0 = rows(mabr.ui.analysis.StudyView.firstOf(P.TimepointOrder(rows), ...
                        P.StartTime(rows)));
                end
                if isempty(r0), continue; end
                r0 = r0(1);
                haveRef(i) = true;
                P.Plotted(i) = P.Value(i) - P.Value(r0);
                P.Hollow(i)  = P.Censored(i) || P.Censored(r0);
                P.RefText(i) = P.Text(r0);
                P.RefTimepoint(i) = P.Timepoint(r0);
            end
            info.NoReference = nnz(~haveRef);
            P = P(haveRef,:);
            if startsWith(ref,"tp:"), info.RefName = extractAfter(ref,3); else, info.RefName = "the first session"; end
        end

        function odd = settingsOdd(hashes,projectHash)
            % Which sessions the settings banner names (pure).
            %
            %   hashes       each used session's results SettingsHash ("" =
            %                unknown, never named)
            %   projectHash  the project's settings' hash
            %   odd  (returned) logical, true for a hash differing from the
            %        reference: the project's own whenever any session was
            %        analysed with it -- [Re-analyse them] analyses with the
            %        project's settings, so measuring against anything else
            %        (an older majority) would name sessions it cannot change
            %        and the banner would stay up for good -- else the
            %        commonest hash.
            h = reshape(string(hashes),[],1);
            h(ismissing(h)) = "";
            ok = h ~= "";
            projectHash = string(projectHash);
            if ~isempty(projectHash) && ~ismissing(projectHash) && projectHash ~= "" && ...
                    any(h(ok) == projectHash)
                ref = projectHash;
            else
                ref = mabr.ui.analysis.StudyView.mostCommon(h(ok));
            end
            odd = ok & h ~= ref;
        end

        function [x,label] = seriesValue(seriesKey,params)
            % The first group parameter's value of a series key, and the
            % series' name ("8 kHz"; the stimulus when there is no parameter).
            x = NaN;
            names = strings(1,0);
            for p = reshape(string(params),1,[])
                v = mabr.ui.analysis.StudyView.keyField(seriesKey,p);
                d = str2double(v);
                if v == "", continue; end
                if isnan(x) && ~isnan(d), x = d; end
                names(end+1) = mabr.ui.analysis.StudyView.paramText(p,v); %#ok<AGROW>
            end
            if isempty(names)
                label = mabr.ui.analysis.StudyView.keyField(seriesKey,"Stimulus");
                if label == "", label = string(seriesKey); end
            else
                label = strjoin(names,", ");
            end
        end

        function v = keyField(key,name)
            % "Value" of the "Name=Value" part of a "|"-joined key ("" none).
            v = "";
            parts = split(string(key),"|");
            hit = startsWith(parts,string(name) + "=");
            if any(hit)
                v = extractAfter(parts(find(hit,1)),strlength(string(name)) + 1);
            end
        end

        function s = paramText(name,value)
            % "8 kHz", "60 dB", "Duration 5": a parameter as the plots name it.
            u = "";
            try
                u = string(mabr.stim.StimulusSet.paramUnit(char(name)));
            catch
            end
            if u ~= ""
                s = string(value) + " " + u;
            else
                s = string(name) + " " + string(value);
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- building -----------------------------------------------------
        function [p,lab,btn] = bannerPanel(obj,parent,tag,btnText,tip,fcn)
            S = mabr.ui.analysis.Style;
            p = uipanel(parent,'BorderType','none','Visible','off','Tag',char(tag), ...
                'BackgroundColor',S.BarBlue);
            p.Layout.Row = 1; p.Layout.Column = 1;
            g = uigridlayout(p,[1 2],'Padding',[8 2 4 2],'ColumnSpacing',8,'BackgroundColor',S.BarBlue);
            g.ColumnWidth = {'1x','fit'};
            lab = uilabel(g,'Text','','Tag',char(tag + "Text"),'FontColor',S.Ink,'WordWrap','on');
            btn = uibutton(g,'Text',char(btnText),'Tag',char(tag + "Action"),'Tooltip',char(tip), ...
                'ButtonPushedFcn',obj.viewWrap(fcn));
        end

        function dd = dropdown(obj,parent,col,label,tag,items,codes,fcn,tip)
            % A label and a dropdown in columns col and col+1 of a grid.
            S = mabr.ui.analysis.Style;
            l = uilabel(parent,'Text',char(label),'FontColor',S.Muted,'HorizontalAlignment','right');
            l.Layout.Row = 1; l.Layout.Column = col;
            dd = uidropdown(parent,'Items',cellstr(items),'ItemsData',cellstr(codes), ...
                'Tag',char(tag),'Tooltip',char(tip),'ValueChangedFcn',obj.viewWrap(fcn));
            dd.Layout.Row = 1; dd.Layout.Column = col + 1;
        end

        function buildSessions(obj,tab)
            S = mabr.ui.analysis.Style;
            % Two button rows, not one: the labelling tools above the
            % table, the actions beneath -- seven buttons in one row do not
            % fit the tab at the window's minimum width (Export… fell off).
            g = uigridlayout(tab,[7 1],'Padding',[4 4 4 4],'RowSpacing',4,'BackgroundColor',S.Panel);
            g.RowHeight = {30,40,26,'1x',18,130,30};
            a = uigridlayout(g,[1 4],'Padding',[0 0 0 0],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            a.Layout.Row = 1;
            a.ColumnWidth = {'fit','fit','fit','1x'};
            obj.Handles.AddColumn = uibutton(a,'Text','Add column…','Tag','AnalysisStudyAddColumn', ...
                'Tooltip','Add a column of your own (a session or a subject column, text or number)', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.addColumn()));
            obj.Handles.RemoveColumn = uibutton(a,'Text','Remove column…','Tag','AnalysisStudyRemoveColumn', ...
                'Tooltip','Remove one of your own columns (Ctrl+Z brings it back)', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.removeColumn()));
            obj.Handles.Timepoints = uibutton(a,'Text','Timepoint order…','Tag','AnalysisStudyTimepoints', ...
                'Tooltip','The order of the timepoints (the plots'' x axis and the reference choices)', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.timepointOrder()));
            % Filters: a small caption over each dropdown (a dropdown shows
            % only its value, and at this width there is no room beside it).
            fg = uigridlayout(g,[2 7],'Padding',[0 0 0 0],'ColumnSpacing',6,'RowSpacing',0,'BackgroundColor',S.Panel);
            fg.Layout.Row = 2;
            fg.RowHeight = {14,24};
            fg.ColumnWidth = {'1x','1x','1x','1x','1x','1x',90};
            obj.Handles.Filter = struct();
            for k = 1:numel(obj.FilterNames)
                nm = obj.FilterNames(k);
                l = uilabel(fg,'Text',char(obj.FilterTitles(k)),'FontSize',10,'FontColor',S.Muted);
                l.Layout.Row = 1;  l.Layout.Column = k;
                d = uidropdown(fg,'Items',{'All'},'ItemsData',{''},'Tag',char("AnalysisStudyFilter" + nm), ...
                    'Tooltip',char("Show only the sessions whose " + obj.FilterTitles(k) + " is…"), ...
                    'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onSessionFilter(nm,s.Value)));
                d.Layout.Row = 2;  d.Layout.Column = k;
                obj.Handles.Filter.(nm) = d;
            end
            obj.Handles.FilterCount = uilabel(fg,'Text','','Tag','AnalysisStudyFilterCount', ...
                'FontSize',10,'FontColor',S.Muted,'HorizontalAlignment','right');
            obj.Handles.FilterCount.Layout.Row = 1;  obj.Handles.FilterCount.Layout.Column = 7;
            obj.Handles.FilterClear = uibutton(fg,'Text','Clear filters','Tag','AnalysisStudyFilterClear', ...
                'Tooltip','Show every session again','ButtonPushedFcn',obj.viewWrap(@(~,~) obj.onClearFilters()));
            obj.Handles.FilterClear.Layout.Row = 2;  obj.Handles.FilterClear.Layout.Column = 7;

            % Sort: the table's own header sort is off (see renderSessions).
            sg = uigridlayout(g,[1 5],'Padding',[0 0 0 0],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            sg.Layout.Row = 3;
            sg.ColumnWidth = {'fit','1x',100,'1x',100};
            sl = uilabel(sg,'Text','Sort by','FontColor',S.Muted,'HorizontalAlignment','right');
            sl.Layout.Column = 1;
            dirItems = {'Ascending','Descending'};  dirCodes = {'ascending','descending'};
            sortSpec = {2,'SessSort1','AnalysisStudySortBy1','Sort the sessions by this column'; ...
                3,'SessDir1','AnalysisStudySortDir1','The direction of the first sort'; ...
                4,'SessSort2','AnalysisStudySortBy2','Then, among equal values, by this column'; ...
                5,'SessDir2','AnalysisStudySortDir2','The direction of the second sort'};
            for k = 1:4
                col = sortSpec{k,1};  fld = sortSpec{k,2};
                d = uidropdown(sg,'Items',{'(table order)'},'ItemsData',{''},'Tag',sortSpec{k,3}, ...
                    'Tooltip',sortSpec{k,4},'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onSessionSort(fld,s.Value)));
                d.Layout.Column = col;
                if startsWith(fld,"SessDir"), set(d,'Items',dirItems,'ItemsData',dirCodes); end
                obj.Handles.(erase(sortSpec{k,3},'AnalysisStudy')) = d;   % SortBy1 SortDir1 SortBy2 SortDir2
            end
            t = uitable(g,'Tag','AnalysisStudySessions','RowName',{}, ...
                'Tooltip','Every session; edit In study, Timepoint, Group and your own columns in place (Ctrl+Z undoes)');
            t.Layout.Row = 4;
            t.CellEditCallback = obj.viewWrap(@(s,e) obj.onSessionEdit(e));
            t.CellSelectionCallback = obj.viewWrap(@(s,e) obj.onSessionSelect(s,e));
            mabr.ui.analysis.Compat.setSortable(t,false);
            obj.tableMenu(t,"sessions");
            obj.Handles.Sessions = t;
            l = uilabel(g,'Text','Subjects','FontWeight','bold','FontColor',S.Ink);
            l.Layout.Row = 5;
            u = uitable(g,'Tag','AnalysisStudySubjects','RowName',{}, ...
                'Tooltip',['The animals: edit Group, In study and your own subject columns in place; ' ...
                'right-click for Edit comment…']);
            u.Layout.Row = 6;
            u.CellEditCallback = obj.viewWrap(@(s,e) obj.onSubjectEdit(e));
            u.CellSelectionCallback = obj.viewWrap(@(s,e) obj.onSubjectSelect(s,e));
            mabr.ui.analysis.Compat.setSortable(u,false);
            obj.tableMenu(u,"subjects");
            obj.Handles.Subjects = u;

            b = uigridlayout(g,[1 5],'Padding',[0 0 0 0],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            b.Layout.Row = 7;
            b.ColumnWidth = {'1x','fit','fit','fit','fit'};
            sp = uilabel(b,'Text','');
            sp.Layout.Column = 1;
            bt = uibutton(b,'Text','Analyse 0 selected…','Tag','AnalysisStudyAnalyseSelected', ...
                'Tooltip','Analyse the sessions selected in the table', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.analyseSelected()));
            mabr.ui.analysis.Style.setButtonIcon(bt,'batch','left');
            obj.Handles.AnalyseSelected = bt;
            bs = uibutton(b,'Text','Analyse 0 out-of-date…','Tag','AnalysisStudyAnalyseStale', ...
                'Tooltip','Analyse the study''s sessions that are not up to date', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.analyseStale()));
            mabr.ui.analysis.Style.setButtonIcon(bs,'batch','left');
            obj.Handles.AnalyseStale = bs;
            br = uibutton(b,'Text','Review queue…','Tag','AnalysisStudyReview', ...
                'Tooltip','Review the thresholds of the selected (or every) study session, one after the other', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.reviewQueue()));
            mabr.ui.analysis.Style.setButtonIcon(br,'preview','left');
            obj.Handles.Review = br;
            be = uibutton(b,'Text','Export…','Tag','AnalysisStudyExport', ...
                'Tooltip','Export the study''s tables (Ctrl+E)', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.exportStudy()));
            mabr.ui.analysis.Style.setButtonIcon(be,'export','left');
            obj.Handles.Export = be;
        end

        function buildThresholds(obj,tab)
            S = mabr.ui.analysis.Style;
            g = uigridlayout(tab,[3 1],'Padding',[4 4 4 4],'RowSpacing',4,'BackgroundColor',S.Panel);
            g.RowHeight = {30,'1x',22};
            c = uigridlayout(g,[1 8],'Padding',[0 2 0 2],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            c.ColumnWidth = {'fit','1x','fit','1x','fit','1x','fit','1x'};
            obj.Handles.X = obj.dropdown(c,1,"X axis","AnalysisStudyX",["Frequency","Timepoint"], ...
                ["","Timepoint"],@(s,~) obj.onLook("X",s.Value), ...
                "Thresholds across a stimulus parameter (an audiogram) or across timepoints");
            obj.Handles.Reference = obj.dropdown(c,3,"Reference","AnalysisStudyReference","None", ...
                "none",@(s,~) obj.onLook("Reference",s.Value), ...
                "Plot each subject's SHIFT from this timepoint (None: the thresholds themselves)");
            obj.Handles.NoResponse = obj.dropdown(c,5,"No response","AnalysisStudyNoResponse", ...
                obj.NoRespItems,obj.NoRespCodes,@(s,~) obj.onLook("NoResponse",s.Value), ...
                "What a series without any response counts as (the plot's subtitle states the rule)");
            obj.Handles.DuplicatePolicy = obj.dropdown(c,7,"Duplicates","AnalysisStudyDuplicatePolicy", ...
                obj.PolicyItems,obj.PolicyCodes,@(s,~) obj.onPolicy(s.Value), ...
                "Which session the study uses when two measured the same series of one subject at one timepoint");
            p = obj.plotPanel(g,"AnalysisStudyThresholdPanel");
            p.Layout.Row = 2;
            obj.Handles.ThrPanel = p;
            r = uilabel(g,'Text','Click a point for its details; double-click opens the session on that series.', ...
                'Tag','AnalysisStudyReadout','FontColor',S.Muted);
            r.Layout.Row = 3;
            obj.Handles.ThrReadout = r;
        end

        function buildGrowth(obj,tab)
            S = mabr.ui.analysis.Style;
            g = uigridlayout(tab,[4 1],'Padding',[4 4 4 4],'RowSpacing',4,'BackgroundColor',S.Panel);
            g.RowHeight = {30,30,'1x',22};
            c1 = uigridlayout(g,[1 6],'Padding',[0 2 0 2],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            c1.ColumnWidth = {'fit','1x','fit','1x','fit','1x'};
            c1.Layout.Row = 1;
            obj.Handles.Measure = obj.dropdown(c1,1,"Measure","AnalysisStudyMeasure",obj.MeasureItems, ...
                obj.MeasureCodes,@(s,~) obj.onLook("Measure",s.Value), ...
                "What is plotted: an amplitude, a latency (re sound arrival when a delay is set), or an interpeak interval");
            obj.Handles.Wave = obj.dropdown(c1,3,"Wave","AnalysisStudyWave","I","I", ...
                @(s,~) obj.onChoice("Wave",s.Value),"The wave whose amplitude or latency is plotted");
            obj.Handles.At = obj.dropdown(c1,5,"At","AnalysisStudyAt","","", ...
                @(s,~) obj.onChoice("At",s.Value),"The series (e.g. 8 kHz) of the family");
            c2 = uigridlayout(g,[1 6],'Padding',[0 2 0 2],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            c2.ColumnWidth = {'fit','1x','fit','1x','fit','1x'};
            c2.Layout.Row = 2;
            obj.Handles.YMode = obj.dropdown(c2,1,"Y","AnalysisStudyYMode",["µV","% of the subject's reference timepoint"], ...
                obj.YModeCodes,@(s,~) obj.onLook("YMode",s.Value), ...
                "Absolute values, or each subject's as a percentage of its own reference timepoint");
            obj.Handles.XMode = obj.dropdown(c2,3,"X","AnalysisStudyXMode",obj.XModeItems,obj.XModeCodes, ...
                @(s,~) obj.onLook("XMode",s.Value),"Level, or level re the subject's own threshold for that series");
            obj.Handles.Processing = obj.dropdown(c2,5,"Processing","AnalysisStudyProcessing","","", ...
                @(s,~) obj.onChoice("Processing",s.Value), ...
                "Only conditions processed this way are plotted (the banner counts the sessions left out)");
            p = obj.plotPanel(g,"AnalysisStudyGrowthPanel");
            p.Layout.Row = 3;
            obj.Handles.GrowthPanel = p;
            r = uilabel(g,'Text','Click a point for its details; double-click opens the session on that series.', ...
                'Tag','AnalysisStudyGrowthReadout','FontColor',S.Muted);
            r.Layout.Row = 4;
            obj.Handles.GrowthReadout = r;
        end

        function buildWaveforms(obj,tab)
            S = mabr.ui.analysis.Style;
            g = uigridlayout(tab,[3 1],'Padding',[4 4 4 4],'RowSpacing',4,'BackgroundColor',S.Panel);
            g.RowHeight = {30,'1x',0};
            obj.Handles.WavesGrid = g;
            c = uigridlayout(g,[1 9],'Padding',[0 2 0 2],'ColumnSpacing',6,'BackgroundColor',S.Panel);
            c.ColumnWidth = {'fit','1x','fit','1x','fit','1x',56,'fit','0.5x'};
            obj.Handles.WaveSeries = obj.dropdown(c,1,"Series","AnalysisStudyWaveSeries","","", ...
                @(s,~) obj.onWaveChoice("WaveSeries",s.Value), ...
                "The series whose grand average is drawn (All series: one column, or panel, per series)");
            obj.Handles.WaveLevel = obj.dropdown(c,3,"Level","AnalysisStudyWaveLevel","","", ...
                @(s,~) obj.onWaveChoice("WaveLevel",s.Value), ...
                "The level whose grand average is drawn (All levels: every level stacked, loudest at the top, as on the Grid tab)");
            obj.Handles.WaveScale = obj.dropdown(c,5,"Scale","AnalysisStudyWaveScale",obj.WaveScaleItems, ...
                obj.WaveScaleCodes,@(s,~) obj.onLook("WaveScale",s.Value), ...
                ['Row spacing of the stacked levels (Level: All levels): the largest curve of each ' ...
                'column, of the whole grid, or a fixed number of microvolts']);
            fixed = mabr.ui.analysis.StudyView.factoryDefaults().WaveFixed;
            if isfield(obj.ViewLook,'WaveFixed'), fixed = double(obj.ViewLook.WaveFixed); end
            f = uieditfield(c,'numeric','Value',fixed, ...
                'Limits',[1e-3 1e6],'LowerLimitInclusive','on','Tag','AnalysisStudyWaveFixed', ...
                'Tooltip','Microvolts between two rows when Scale is Fixed µV', ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onLook("WaveFixed",s.Value)));
            f.Layout.Row = 1;  f.Layout.Column = 7;
            obj.Handles.WaveFixed = f;
            u = uilabel(c,'Text','µV','FontColor',S.Muted);
            u.Layout.Row = 1;  u.Layout.Column = 8;
            p = obj.plotPanel(g,"AnalysisStudyWavesPanel");
            p.Layout.Row = 2;
            obj.Handles.WavesPanel = p;
            % (the grid's note: its columns are too narrow for a subtitle)
            n = uilabel(g,'Text','','Tag','AnalysisStudyWaveNote','FontColor',S.Muted,'FontSize',10);
            n.Layout.Row = 3;
            obj.Handles.WaveNote = n;
        end

        function p = plotPanel(~,g,tag)
            % A plot's panel. AutoResizeChildren off: the axes are placed in
            % normalized units and must stay there. With it on, axes made
            % before the panel's first layout -- a sub-tab drawn in the very
            % callback that shows it, before the panel has its size -- are
            % rescaled by the resizer from the placeholder size (260 x 221
            % px) and end up squeezed into a corner.
            p = uipanel(g,'Tag',char(tag),'BorderType','none','BackgroundColor',[1 1 1], ...
                'AutoResizeChildren','off');
        end

        function tableMenu(obj,t,which)
            % Every table's context menu: Copy table (and, the subjects',
            % Edit comment…).
            try
                fig = ancestor(t,'figure');
                cm = uicontextmenu(fig);
                if which == "subjects"
                    uimenu(cm,'Text','Edit comment…','Tag','AnalysisStudyEditComment', ...
                        'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.editComment()));
                end
                uimenu(cm,'Text','Copy table','Tag','AnalysisStudyCopyTable', ...
                    'Separator',obj.pick(which == "subjects",'on','off'), ...
                    'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.copyTable(which)));
                t.ContextMenu = cm;
            catch me
                mabr.log.vprintf(2,'Study view: no table menu (%s).',me.message);
            end
        end

        % ---- rendering ----------------------------------------------------
        function render(obj)
            obj.renderGuarded(@() obj.renderNow());
        end

        function renderNow(obj)
            m = obj.Model;
            if isempty(m) || ~isvalid(m), return; end
            if m.Busy
                % a scan, an analysis or a batch is changing what the study
                % is made of: draw once it has finished
                obj.WaitIdle = true;
                return
            end
            if isempty(m.Catalog) || isempty(m.Project)
                obj.Data = [];
                obj.showEmpty("Open a data folder (Ctrl+O) to compare its sessions.");
                return
            end
            if m.BlindReview
                obj.showEmpty("The Study tab is off during blind review.");
                return
            end
            obj.ensureData(obj.ActiveSub == "Waveforms");
            D = obj.Data;
            V = D.V;
            inStudy = V.InStudy & V.SubjectInStudy;
            nStudy = nnz(inStudy);
            nDone = nnz(inStudy & V.Status ~= "none");
            if nStudy > 0 && nDone == 0 && ~obj.EmptyDismissed
                acts = struct('Text',{char("Analyse " + nStudy + " sessions…"),'Label sessions first'}, ...
                    'Fcn',{@() obj.analyseKeys(V.Key(inStudy)),@() obj.dismissEmpty()}, ...
                    'Glyph',{"batch",""}, ...
                    'Tooltip',{'Analyse every session in the study','Edit the timepoints and groups before analysing'});
                obj.showEmpty(sprintf('%d of %d sessions analysed — select them and press Analyse.', ...
                    nDone,nStudy),acts);
            else
                obj.hideEmpty();
            end
            obj.SubDirty = struct('Sessions',true,'Thresholds',true,'Growth',true,'Waveforms',true);
            obj.syncControls();
            obj.renderSub();
            obj.syncButtons();
        end

        function renderSub(obj)
            % The showing sub-tab (the others draw when they are shown).
            if isempty(obj.Data), return; end
            obj.Pass = struct();      % the banner and the plot share one pass's data
            obj.renderBanner();
            switch obj.ActiveSub
                case "Sessions",   obj.renderSessions();
                case "Thresholds", obj.renderThresholds();
                case "Growth",     obj.renderGrowth();
                case "Waveforms",  obj.renderWaveforms();
            end
            obj.SubDirty.(obj.ActiveSub) = false;
            obj.layoutRows();
        end

        function layoutRows(obj)
            % The banner row (when one shows) and the shared control strip
            % (not on Sessions, where nothing is plotted). One Written
            % record for the one property.
            h = 0;
            if obj.BannerKind ~= "", h = 32; end
            obj.put('root_rows',obj.Handles.Root,'RowHeight', ...
                {h,obj.pick(obj.ActiveSub == "Sessions",0,30),'1x'});
        end

        function userDrawn(obj)
            % The end of a render a person asked for (a control, a sub-tab):
            % let it reach the screen. Never from a Model event, and not
            % while the window is invisible (a test drives it).
            try
                if ~isempty(obj.Host) && isvalid(obj.Host) && obj.Host.Visible == "on"
                    drawnow limitrate
                end
            catch
            end
        end

        function switchSub(obj,name)
            if obj.ActiveSub == name && ~obj.SubDirty.(name), return; end
            obj.ActiveSub = name;
            obj.Readout = "";
            if isempty(obj.Data) || ~obj.IsActive, return; end
            if name == "Waveforms" && ~obj.Data.HasMeans
                obj.render();          % needs the means: aggregate again
                return
            end
            obj.renderGuarded(@() obj.renderSub());
        end

        function onSubTab(obj,e)
            name = "";
            try
                name = erase(string(e.NewValue.Tag),"AnalysisStudyTab");
            catch
            end
            if any(obj.SubTabNames == name)
                obj.switchSub(name);
                obj.userDrawn();
            end
        end

        % ---- the data ---------------------------------------------------
        function ensureData(obj,needMeans)
            % Project.aggregate over every session (the Sessions table
            % reports on sessions out of the study too; the plots keep
            % UsedInStudy), cached until something it is made of changes.
            m = obj.Model;
            if ~obj.StaleData && ~isempty(obj.Data) && (~needMeans || obj.Data.HasMeans), return; end
            % Edits still waiting for the autosave are not in the files yet.
            % (Cleared first: the save this flush announces is not news to
            % an aggregate that has not been made yet.)
            obj.AggPendingSave = false;
            if m.SaveState == "pending" && ~m.Busy
                try
                    m.flush();
                catch me
                    mabr.log.vprintf(2,'Study view: flush before the study failed (%s).',me.message);
                end
            end
            % (anything but "saved": a conflict or a read-only store keeps
            % the open session's edits out of the files too)
            obj.AggPendingSave = m.SaveState ~= "saved";
            V = m.projectView();
            if isempty(V) || width(V) == 0
                V = mabr.ui.analysis.StudyView.emptyView();
            end
            % A hidden session is not this study's (the browser's Exclude
            % and hide): no row in the tables, nothing aggregated from it.
            if ismember('Hidden',V.Properties.VariableNames)
                V = V(~logical(V.Hidden),:);
            end
            A = [];
            try
                A = m.Project.aggregate(string(V.Key),m.Catalog,Waveforms=needMeans);
            catch me
                try
                    A = m.Project.aggregate(strings(0,1),m.Catalog,Waveforms=needMeans);
                catch me2
                    mabr.log.vprintf(1,'Study view: the study tables could not be built: %s',me2.message);
                end
                mabr.log.vprintf(2,'Study view: aggregate over every key failed (%s).',me.message);
            end
            A = mabr.ui.analysis.StudyView.completeAggregate(A);
            D = struct();
            D.V = V;
            D.A = A;
            D.HasMeans = needMeans;
            D.Stats = mabr.ui.analysis.StudyView.sessionStats(A.Conditions);
            D.SeriesSweeps = mabr.ui.analysis.StudyView.seriesSweepTable(A.Conditions,A.Thresholds);
            D.TpNames = strings(1,0);
            try
                C = m.Project.Columns;
                lv = C.Levels{C.Name == "Timepoint"};
                D.TpNames = reshape(string(lv),1,[]);
            catch
            end
            D.Families = mabr.ui.analysis.StudyView.familiesOf(A.Thresholds);
            D.Hash = "";
            try
                D.Hash = string(m.Settings.hash());
            catch
            end
            obj.Data = D;
            obj.StaleData = false;
            obj.Pass = struct();
        end

        % ---- controls -----------------------------------------------------
        function syncControls(obj)
            % Items and values of every dropdown from the data and the look.
            D = obj.Data;
            L = obj.ViewLook;
            F = D.Families;
            if height(F) == 0
                obj.setChoice('family',obj.Handles.Family,"(no analysed series)","","");
            else
                fam = string(L.Family);
                if ~any(F.Code == fam), fam = F.Code(1); end
                obj.setChoice('family',obj.Handles.Family,F.Label,F.Code,fam);
            end
            obj.setChoice('colorby',obj.Handles.ColorBy,obj.ColorByItems,obj.ColorByCodes,L.ColorBy);
            obj.setChoice('show',obj.Handles.Show,obj.ShowItems,obj.ShowCodes,L.Show);
            obj.setChoice('layout',obj.Handles.Layout,obj.LayoutItems,obj.LayoutCodes,L.Layout);
            obj.setChoice('noresp',obj.Handles.NoResponse,obj.NoRespItems,obj.NoRespCodes,L.NoResponse);
            pol = "most-sweeps";
            try
                pol = string(obj.Model.Project.DuplicatePolicy);
            catch
            end
            obj.setChoice('policy',obj.Handles.DuplicatePolicy,obj.PolicyItems,obj.PolicyCodes,pol);

            % X: the family's parameters, then Timepoint
            params = obj.familyParams();
            if isempty(params)
                obj.setChoice('x',obj.Handles.X,"Timepoint","Timepoint","Timepoint");
                obj.put('x_enable',obj.Handles.X,'Enable','off');
                obj.put('x_tip',obj.Handles.X,'Tooltip', ...
                    'This family has no parameter besides level, so its thresholds are plotted across timepoints');
            else
                items = strings(1,numel(params));
                for k = 1:numel(params), items(k) = obj.paramAxisName(params(k)); end
                items = [items,"Timepoint"];
                codes = [params,"Timepoint"];
                x = string(L.X);
                if ~any(codes == x), x = codes(1); end
                obj.setChoice('x',obj.Handles.X,items,codes,x);
                obj.put('x_enable',obj.Handles.X,'Enable','on');
                obj.put('x_tip',obj.Handles.X,'Tooltip', ...
                    'Thresholds across a stimulus parameter (an audiogram) or across timepoints');
            end

            % Reference: None, each timepoint in order, First session
            tps = obj.studyTimepoints();
            items = ["None",tps,"First session"];
            codes = ["none","tp:" + tps,"first"];
            ref = string(L.Reference);
            if ~any(codes == ref), ref = "none"; end
            obj.setChoice('ref',obj.Handles.Reference,items,codes,ref);

            % Growth
            obj.setChoice('measure',obj.Handles.Measure,obj.MeasureItems,obj.MeasureCodes,L.Measure);
            isLat = any(string(L.Measure) == ["latency","ipl-I-III","ipl-I-V"]);
            yItems = [obj.pick(isLat,"ms","µV"),"% of the subject's reference timepoint"];
            obj.setChoice('ymode',obj.Handles.YMode,yItems,obj.YModeCodes,L.YMode);
            obj.setChoice('xmode',obj.Handles.XMode,obj.XModeItems,obj.XModeCodes,L.XMode);
            P = obj.familyPeaks();
            waves = strings(1,0);
            if height(P) > 0, waves = reshape(unique(string(P.Wave),'stable'),1,[]); end
            if isempty(waves), waves = "I"; end
            w = obj.Choice.Wave;
            if ~any(waves == w), w = waves(1); end
            obj.Choice.Wave = w;
            obj.setChoice('wave',obj.Handles.Wave,waves,waves,w);
            obj.put('wave_enable',obj.Handles.Wave,'Enable',obj.pick(startsWith(string(L.Measure),"ipl"),'off','on'));
            [codes,items] = obj.familySeries();
            obj.Choice.At = obj.firstOr(obj.Choice.At,codes);
            obj.setChoice('at',obj.Handles.At,items,codes,obj.Choice.At);
            obj.Choice.WaveSeries = obj.firstOr(obj.Choice.WaveSeries,codes);
            wv = obj.Choice.WaveSeries;
            if numel(codes) > 1
                % (a family of one series has nothing to put side by side)
                if logical(L.WaveAllSeries), wv = obj.WaveAllCode; end
                items = ["All series",items];
                codes = [obj.WaveAllCode,codes];
            end
            obj.setChoice('wseries',obj.Handles.WaveSeries,items,codes,wv);
            obj.setChoice('wscale',obj.Handles.WaveScale,obj.WaveScaleItems,obj.WaveScaleCodes,L.WaveScale);
            obj.put('wave_fixed',obj.Handles.WaveFixed,'Value',double(L.WaveFixed));
        end

        function setChoice(obj,key,h,items,codes,value)
            % A dropdown's Items/ItemsData and Value, written on change only
            % (a new item list resets Value, so its record is dropped then).
            items = reshape(string(items),1,[]);
            codes = reshape(string(codes),1,[]);
            if isempty(items), items = ""; codes = ""; end
            value = string(value);
            if ~any(codes == value), value = codes(1); end
            k = char("dd_" + key);
            list = {cellstr(items),cellstr(codes)};
            if ~isfield(obj.Written,k) || ~isequal(obj.Written.(k),list)
                try
                    set(h,'Items',list{1},'ItemsData',list{2});
                    obj.Written.(k) = list;
                    obj.forgetWritten([k '_value']);
                catch me
                    mabr.log.vprintf(2,'Study view: %s items not set (%s).',key,me.message);
                end
            end
            obj.put([k '_value'],h,'Value',char(value));
        end

        function onLook(obj,field,value)
            % A look control: remember it (the user chose it) and redraw.
            % (a dropdown's text as a string; a number stays one)
            if ischar(value) || isstring(value), value = string(value); end
            obj.ViewLook.(field) = value;
            obj.savePrefs();
            obj.Readout = "";
            if any(field == ["Family","Measure"])
                obj.syncControls();          % the family decides the other lists
            end
            obj.SubDirty = struct('Sessions',true,'Thresholds',true,'Growth',true,'Waveforms',true);
            obj.renderGuarded(@() obj.renderSub());
            obj.userDrawn();
        end

        function onChoice(obj,field,value)
            % A choice that is not part of the look (it depends on the data).
            obj.Choice.(field) = string(value);
            obj.Readout = "";
            obj.renderGuarded(@() obj.renderSub());
            obj.userDrawn();
        end

        function onWaveChoice(obj,field,value)
            % The waveforms' Series or Level. Which series or level is a
            % choice that depends on the data (Choice); "All" is part of
            % the look (WaveAllSeries / WaveAllLevels), remembered when the
            % user changes it, and the one series or level last picked is
            % kept for when they go back to one.
            %   field  "WaveSeries" | "WaveLevel"
            value = string(value);
            if field == "WaveSeries"
                flag = "WaveAllSeries";  key = "wseries";
            else
                flag = "WaveAllLevels";  key = "wlevel";
            end
            obj.forgetWritten(char("dd_" + key + "_value"));
            isAll = value == obj.WaveAllCode;
            if ~isAll, obj.Choice.(field) = value; end
            if logical(obj.ViewLook.(flag)) ~= isAll
                obj.ViewLook.(flag) = isAll;
                obj.savePrefs();
            end
            obj.Readout = "";
            obj.renderGuarded(@() obj.renderSub());
            obj.userDrawn();
        end

        function onPolicy(obj,value)
            % The duplicate policy is the project's (undoable, autosaved).
            % The control now shows the person's pick, not what put() last
            % wrote: forget that record, and when the Model refuses (busy,
            % read-only) put the project's policy back on the control before
            % the error reaches the status line.
            value = string(value);
            obj.forgetWritten('dd_policy_value');
            cur = string(obj.Model.Project.DuplicatePolicy);
            if value == cur, return; end
            try
                obj.Model.setDuplicatePolicy(value);
            catch me
                obj.put('dd_policy_value',obj.Handles.DuplicatePolicy,'Value',char(cur));
                rethrow(me);
            end
        end

        function syncButtons(obj)
            % The Analyse buttons name their counts.
            if isempty(obj.Data), return; end
            V = obj.Data.V;
            n = numel(obj.SelectedKeys);
            obj.put('btn_sel_text',obj.Handles.AnalyseSelected,'Text',char("Analyse " + n + " selected…"));
            obj.put('btn_sel_en',obj.Handles.AnalyseSelected,'Enable',obj.pick(n > 0,'on','off'));
            k = obj.staleKeys(V);
            obj.put('btn_stale_text',obj.Handles.AnalyseStale,'Text',char("Analyse " + numel(k) + " out-of-date…"));
            obj.put('btn_stale_en',obj.Handles.AnalyseStale,'Enable',obj.pick(~isempty(k),'on','off'));
            obj.put('btn_stale_tip',obj.Handles.AnalyseStale,'Tooltip', ...
                char("Analyse the " + numel(k) + " study sessions that are not up to date (out of date, failed or never analysed)"));
        end

        % ---- Sessions sub-tab -------------------------------------------
        function renderSessions(obj)
            S = mabr.ui.analysis.Style;
            D = obj.Data;
            V = D.V;
            P = obj.Model.Project;
            n = height(V);
            [free,flevel,ftype] = obj.freeColumns();
            names = ["In study","Subject","Session","Day","Timepoint","Group",free, ...
                "Stimuli","N presented","Duration","Status","Reviewed","Processing","Noise (µV)", ...
                "% rejected","Min N","Units","Settings"];
            cols = ["InStudy","","","","Timepoint","Group",free,strings(1,11)];
            C = cell(n,numel(names));
            txt = @mabr.ui.analysis.StudyView.cellText;
            [dur,npres] = mabr.ui.analysis.StudyView.sessionExtent(V);
            for i = 1:n
                C{i,1} = logical(V.InStudy(i));
                C{i,2} = txt(V.Subject(i));
                C{i,3} = txt(V.Name(i));
                if isnat(V.Day(i)), C{i,4} = '(unknown date)';
                else, C{i,4} = char(string(V.Day(i),'yyyy-MM-dd')); end
                C{i,5} = txt(V.Timepoint(i));
                C{i,6} = txt(V.Group(i));
                for j = 1:numel(free)
                    C{i,6+j} = txt(obj.freeValue(P,V(i,:),free(j),flevel(j),ftype(j)));
                end
                c0 = 6 + numel(free);
                C{i,c0+1} = txt(V.Stimuli(i));
                if isnan(npres(i)), C{i,c0+2} = ''; else, C{i,c0+2} = sprintf('%d',npres(i)); end
                C{i,c0+3} = mabr.ui.analysis.StudyView.durationText(dur(i));
                full = V.NumSeries(i) > 0 && V.Reviewed(i) >= V.NumSeries(i);
                st = S.statusGlyph(V.Status(i),full) + " " + V.StatusText(i);
                if V.TestMode(i) == "all", st = S.BadgeTest + " " + st; end
                C{i,c0+4} = char(st);
                if V.NumSeries(i) > 0, C{i,c0+5} = sprintf('%d/%d',V.Reviewed(i),V.NumSeries(i));
                else, C{i,c0+5} = ''; end
                C{i,c0+6} = txt(V.Processing(i));
                r = find(D.Stats.Session == V.Key(i),1);
                if isempty(r)
                    C(i,c0+7:c0+9) = {''};
                else
                    C{i,c0+7} = obj.numText(D.Stats.Noise(r)*1e6,3);
                    C{i,c0+8} = obj.numText(D.Stats.PctRejected(r),3);
                    C{i,c0+9} = obj.numText(D.Stats.MinN(r),6);
                end
                uu = [string(txt(V.Units(i))), string(txt(V.LevelUnit(i)))];
                C{i,c0+10} = char(strjoin(uu(uu ~= ""),", "));
                C{i,c0+11} = txt(V.SettingsHash(i));
            end

            % Filter, then sort: the rows shown, in order. The table's own
            % header sort stays off (every callback maps a row to its
            % session through SessionKeys), so the order is decided here.
            facets = obj.sessionFacets(V);
            obj.syncSessionControls(facets,names);
            ord = find(obj.sessionMask(facets,n));
            ord = obj.sortedRows(ord,V,names,C,dur);
            obj.put('sess_count',obj.Handles.FilterCount,'Text', ...
                char(obj.pick(numel(ord) == n,sprintf('%d sessions',n),sprintf('Showing %d of %d',numel(ord),n))));
            C = C(ord,:);
            t = obj.Handles.Sessions;
            ed = cols ~= "";
            fmt = repmat({'char'},1,numel(names));
            fmt{1} = 'logical';
            obj.put('sess_names',t,'ColumnName',cellstr(names));
            obj.put('sess_fmt',t,'ColumnFormat',fmt);
            obj.put('sess_edit',t,'ColumnEditable',ed);
            obj.put('sess_data',t,'Data',C);
            obj.SessionKeys = string(V.Key(ord));
            obj.SessionCols = cols;
            % Styles: rows out of the study muted; a settings hash that is
            % not the majority's highlighted (the majority of the whole
            % study, not of the rows showing).
            hc = numel(names);
            h = V.SettingsHash;
            maj = mabr.ui.analysis.StudyView.mostCommon(h(h ~= ""));
            odd = find(h(ord) ~= "" & h(ord) ~= maj);
            out = find(~(V.InStudy(ord) & V.SubjectInStudy(ord)));
            sig = {reshape(odd,1,[]),reshape(out,1,[]),numel(ord),hc};
            if ~isfield(obj.Written,'sess_styles') || ~isequal(obj.Written.sess_styles,sig)
                try
                    removeStyle(t);
                    if ~isempty(out)
                        addStyle(t,uistyle('FontColor',S.Muted),'row',out(:));
                    end
                    if ~isempty(odd)
                        addStyle(t,uistyle('BackgroundColor',S.BarAmber),'cell',[odd(:) repmat(hc,numel(odd),1)]);
                    end
                    obj.Written.sess_styles = sig;
                catch me
                    mabr.log.vprintf(2,'Study view: table styles not set (%s).',me.message);
                end
            end
            obj.SelectedKeys = obj.SelectedKeys(ismember(obj.SelectedKeys,obj.SessionKeys));

            % Subjects
            U = P.Subjects;
            sfree = free(flevel == "subject");
            stype = ftype(flevel == "subject");
            snames = ["Subject","Group","In study","Comment",sfree];
            % (the Comment is shown, not typed into: no note is ever typed
            % into a table cell -- the table's Edit comment… asks for it)
            scols  = ["","Group","InStudy","",sfree];
            m = height(U);
            C2 = cell(m,numel(snames));
            for i = 1:m
                C2{i,1} = txt(U.Subject(i));
                C2{i,2} = txt(U.Group(i));
                C2{i,3} = logical(U.InStudy(i));
                C2{i,4} = txt(U.Comment(i));
                for j = 1:numel(sfree)
                    v = U.(sfree(j))(i);
                    C2{i,4+j} = txt(obj.valueText(v,stype(j)));
                end
            end
            u = obj.Handles.Subjects;
            sfmt = repmat({'char'},1,numel(snames));
            sfmt{3} = 'logical';
            obj.put('subj_names',u,'ColumnName',cellstr(snames));
            obj.put('subj_fmt',u,'ColumnFormat',sfmt);
            obj.put('subj_edit',u,'ColumnEditable',scols ~= "");
            obj.put('subj_data',u,'Data',C2);
            obj.SubjectKeys = string(U.Subject);
            obj.SubjectCols = scols;
        end

        % ---- Sessions table: filters and sort ----------------------------
        function F = sessionFacets(obj,V)
            % What each filter offers and what each session holds for it
            % (pure over V): F.(name) = struct Values (n-by-1 cell of string
            % arrays -- a session may hold several stimuli), Items, Codes
            % (the choices, "All" first with the code "").
            n = height(V);
            nat = @(s) reshape(mabr.analysis.Stats.naturalSort(reshape(string(s),[],1)),[],1);
            clean = @(s) reshape(s(~ismissing(s) & s ~= ""),[],1);
            lastOf = @(u,tail) [u(u ~= tail); u(u == tail)];
            none = "(none)";  unk = "(unknown date)";
            F = struct();

            v = repmat("no",n,1);  v(logical(V.InStudy)) = "yes";
            codes = ["yes";"no"];  items = ["Yes";"No"];
            keep = ismember(codes,v);
            F.InStudy = obj.facet(num2cell(v),items(keep),codes(keep));

            v = string(V.Subject);  v(ismissing(v)) = "";
            u = nat(unique(clean(v)));
            F.Subject = obj.facet(num2cell(v),u,u);

            v = repmat(unk,n,1);  ok = ~isnat(V.Day);
            v(ok) = string(V.Day(ok),'yyyy-MM-dd');
            u = lastOf(sort(unique(v)),unk);
            F.Day = obj.facet(num2cell(v),u,u);

            v = string(V.Group);  v(ismissing(v) | v == "") = none;
            u = lastOf(nat(unique(v)),none);
            F.Group = obj.facet(num2cell(v),u,u);

            toks = cell(n,1);
            for i = 1:n
                t = strtrim(split(string(V.Stimuli(i)),","));
                toks{i} = reshape(t(t ~= "" & ~ismissing(t)),[],1);
            end
            u = nat(unique(clean(vertcat(strings(0,1),toks{:}))));
            F.Stimuli = obj.facet(toks,u,u);

            v = string(V.Status);  v(ismissing(v)) = "";
            codes = ["current";"stale";"none";"failed"];
            items = ["Up to date";"Out of date";"Not analysed";"Failed"];
            keep = ismember(codes,v);
            F.Status = obj.facet(num2cell(v),items(keep),codes(keep));
        end

        function s = facet(~,values,items,codes)
            s = struct('Values',{values},'Items',["All";reshape(string(items),[],1)], ...
                'Codes',["";reshape(string(codes),[],1)]);
        end

        function keep = sessionMask(obj,F,n)
            % The sessions the filters let through.
            keep = true(n,1);
            for nm = obj.FilterNames
                code = string(obj.SessFilter.(nm));
                if code == "", continue; end
                v = F.(nm).Values;
                hit = false(n,1);
                for i = 1:n, hit(i) = any(string(v{i}) == code); end
                keep = keep & hit;
            end
        end

        function syncSessionControls(obj,F,names)
            % The filter and sort dropdowns' items and values. A filter
            % value the data no longer holds (another study, a label
            % edited away) goes back to All.
            for nm = obj.FilterNames
                f = F.(nm);
                code = string(obj.SessFilter.(nm));
                if ~any(f.Codes == code), code = ""; obj.SessFilter.(nm) = ""; end
                obj.setChoice(char("sf_" + nm),obj.Handles.Filter.(nm),f.Items,f.Codes,code);
            end
            anyOn = any(structfun(@(c) string(c) ~= "",obj.SessFilter));
            obj.put('sf_clear',obj.Handles.FilterClear,'Enable',obj.pick(anyOn,'on','off'));

            L = obj.ViewLook;
            s1 = string(L.SessSort1);
            if ~any(names == s1), s1 = ""; end
            s2 = string(L.SessSort2);
            if s1 == "" || s2 == s1 || ~any(names == s2), s2 = ""; end
            obj.setChoice('ss_by1',obj.Handles.SortBy1,["(table order)",names],["",names],s1);
            rest = names(names ~= s1);
            obj.setChoice('ss_by2',obj.Handles.SortBy2,["(then by)",rest],["",rest],s2);
            dirs = ["Ascending","Descending"];  dcodes = ["ascending","descending"];
            obj.setChoice('ss_dir1',obj.Handles.SortDir1,dirs,dcodes,L.SessDir1);
            obj.setChoice('ss_dir2',obj.Handles.SortDir2,dirs,dcodes,L.SessDir2);
            obj.put('ss_en_by2',obj.Handles.SortBy2,'Enable',obj.pick(s1 ~= "",'on','off'));
            obj.put('ss_en_dir1',obj.Handles.SortDir1,'Enable',obj.pick(s1 ~= "",'on','off'));
            obj.put('ss_en_dir2',obj.Handles.SortDir2,'Enable',obj.pick(s2 ~= "",'on','off'));
        end

        function ord = sortedRows(obj,ord,V,names,C,dur)
            % ORD (rows of V, in table order) put in the order of the two
            % sort columns; ties keep table order, descending included.
            L = obj.ViewLook;
            keys = zeros(numel(ord),0);
            used = strings(1,0);
            for j = 1:2
                nm = string(L.("SessSort" + j));
                col = find(names == nm,1);
                if nm == "" || isempty(col) || any(used == nm), continue; end
                used(end+1) = nm; %#ok<AGROW>
                txt = strings(size(C,1),1);                  % (In study holds logicals, not text)
                if nm ~= "In study", txt = string(C(:,col)); end
                [k,miss] = obj.sessionSortKey(nm,V,txt,dur);
                k = k(ord);  miss = miss(ord);
                if string(L.("SessDir" + j)) == "descending", k = -k; end
                k(miss) = Inf;                    % what has no value goes last, either way
                keys(:,end+1) = k; %#ok<AGROW>
            end
            if isempty(keys) || isempty(ord), return; end
            [~,i] = sortrows([keys,(1:numel(ord)).']);
            ord = ord(i);
        end

        function [k,miss] = sessionSortKey(obj,name,V,txt,dur)
            % A number per session to sort NAME by (over every row of V; txt
            % is the column's cell text, in V's order), and which sessions
            % have no value. Numbers sort as numbers, dates as dates,
            % timepoints in the study's timepoint order, the rest the way a
            % person reads numbers in text (SUBJ-ID-959 before 1254).
            n = height(V);
            miss = false(n,1);
            switch name
                case "In study"
                    k = double(V.InStudy);
                case "Day"
                    k = posixtime(V.Day);  miss = isnan(k);
                case "Duration"
                    k = dur;  miss = isnan(k);
                case "Reviewed"
                    k = double(V.Reviewed)./max(double(V.NumSeries),1);  miss = V.NumSeries == 0;
                case "Timepoint"
                    tps = obj.studyTimepoints();
                    k = numel(tps) + obj.textRank(txt);
                    [tf,loc] = ismember(lower(string(V.Timepoint)),lower(tps));
                    k(tf) = loc(tf);
                    miss = txt == "";
                case "Status"
                    codes = ["failed","none","stale","current"];   % the labels' alphabetical order
                    [~,k] = ismember(string(V.Status),codes);
                otherwise
                    miss = txt == "";
                    num = str2double(txt);
                    if any(~miss) && all(~isnan(num(~miss)))
                        k = num;
                    else
                        k = obj.textRank(txt);
                    end
            end
            k = reshape(double(k),[],1);
            k(isnan(k)) = 0;
            if isempty(k), k = zeros(n,1); end
        end

        function k = textRank(~,txt)
            % Equal texts share a rank; ranks follow natural order.
            txt = reshape(string(txt),[],1);
            txt(ismissing(txt)) = "";
            n = numel(txt);
            k = ones(n,1);
            if n < 2, return; end
            [s,i] = mabr.analysis.Stats.naturalSort(txt);
            g = [1; 1 + cumsum(lower(s(2:end)) ~= lower(s(1:end-1)))];
            k(i) = g;
        end

        function onSessionFilter(obj,name,code)
            % A filter dropdown. Not part of the look (it belongs to this
            % study), so nothing is remembered.
            obj.SessFilter.(char(name)) = string(code);
            obj.afterSessionView();
        end

        function onClearFilters(obj)
            for nm = obj.FilterNames, obj.SessFilter.(nm) = ""; end
            obj.afterSessionView();
        end

        function onSessionSort(obj,field,value)
            % A sort dropdown: the user's choice, so remembered (pref).
            obj.ViewLook.(char(field)) = string(value);
            obj.savePrefs();
            obj.afterSessionView();
        end

        function afterSessionView(obj)
            % The dropdown just showed what the user picked, not what put()
            % last wrote: forget those records, then redraw the table.
            for nm = obj.FilterNames, obj.forgetWritten(char("dd_sf_" + nm + "_value")); end
            for nm = ["by1","by2","dir1","dir2"], obj.forgetWritten(char("dd_ss_" + nm + "_value")); end
            obj.renderGuarded(@() obj.renderSessions());
            obj.restoreSessionSelection();
            obj.syncButtons();
            obj.userDrawn();
        end

        function restoreSessionSelection(obj)
            % Rows moved or went: select the same sessions again (those
            % still showing; renderSessions dropped the rest).
            [~,rows] = ismember(obj.SelectedKeys,obj.SessionKeys);
            mabr.ui.analysis.Compat.setSelectedRows(obj.Handles.Sessions,rows(rows > 0));
        end

        function onSessionEdit(obj,evt)
            % A Sessions cell edited: Model.label (coerced; the note reaches
            % the status line through the Model's own StatusChanged).
            obj.forgetWritten('sess_data');
            [r,c,val] = obj.editOf(evt);
            if r < 1 || r > numel(obj.SessionKeys) || c < 1 || c > numel(obj.SessionCols), return; end
            name = obj.SessionCols(c);
            if name == "", return; end
            obj.applyLabel(obj.SessionKeys(r),name,val);
        end

        function onSubjectEdit(obj,evt)
            obj.forgetWritten('subj_data');
            [r,c,val] = obj.editOf(evt);
            if r < 1 || r > numel(obj.SubjectKeys) || c < 1 || c > numel(obj.SubjectCols), return; end
            name = obj.SubjectCols(c);
            if name == "", return; end
            obj.applyLabel(obj.SubjectKeys(r),name,val);
        end

        function applyLabel(obj,key,name,val)
            if name == "InStudy", val = logical(val); end
            try
                obj.Model.label(key,name,val);
            catch me
                % refused (a number column given text, ...): say so and put
                % the table back as the project holds it
                obj.status("Not changed: " + string(me.message),2);
                obj.renderGuarded(@() obj.renderSessions());
            end
        end

        function onSessionSelect(obj,src,evt)
            % Rows selected (for the Analyse/Review buttons) and the column
            % (for Remove column…). Only the buttons change here: a table's
            % Data is never rewritten from its own selection callback.
            rows = mabr.ui.analysis.Compat.selectedRows(src,evt);
            rows = rows(rows >= 1 & rows <= numel(obj.SessionKeys));
            obj.SelectedKeys = reshape(obj.SessionKeys(rows),[],1);
            c = obj.cellColumn(evt);
            if c >= 1 && c <= numel(obj.SessionCols)
                obj.SelectedColumn = obj.SessionCols(c);
            end
            obj.syncButtons();
        end

        function onSubjectSelect(obj,src,evt)
            % The column (for Remove column…) and the subject (for Edit
            % comment…). Nothing in the table changes here.
            c = obj.cellColumn(evt);
            if c >= 1 && c <= numel(obj.SubjectCols)
                obj.SelectedColumn = obj.SubjectCols(c);
            end
            rows = mabr.ui.analysis.Compat.selectedRows(src,evt);
            rows = rows(rows >= 1 & rows <= numel(obj.SubjectKeys));
            obj.SelectedSubjects = reshape(obj.SubjectKeys(rows),[],1);
        end

        function editComment(obj)
            % The selected subjects' Comment, asked for (the Browser's
            % Comment… does the same for a session) -- one undoable label.
            subj = obj.SelectedSubjects;
            if isempty(subj)
                obj.status("Select a subject in the Subjects table first.",0);
                return
            end
            cur = "";
            try
                U = obj.Model.Project.Subjects;
                r = find(U.Subject == subj(1),1);
                if ~isempty(r), cur = string(U.Comment(r)); end
            catch
            end
            if ismissing(cur), cur = ""; end
            if isscalar(subj), what = subj; else, what = numel(subj) + " subjects"; end
            v = obj.Model.PromptFcn("Comment on " + what + ":","Comment",cur);
            if isempty(v), return; end
            obj.Model.label(subj,"Comment",string(v));
        end

        function addColumn(obj)
            % Name (PromptFcn), then session or subject, then text or number.
            m = obj.Model;
            v = m.PromptFcn("Name of the new column (e.g. Weight, Ear, Cage):","Add column","");
            if isempty(v), return; end
            name = strtrim(string(v));
            if name == "", return; end
            lev = m.ConfirmFcn("Does “" + name + "” describe each session (a visit) or each " + ...
                "subject (the animal)?","Add column",["Session","Subject","Cancel"],"Session");
            if string(lev) == "Cancel" || string(lev) == "", return; end
            typ = m.ConfirmFcn("What does “" + name + "” hold?","Add column", ...
                ["Text","Number","Cancel"],"Text");
            if string(typ) == "Cancel" || string(typ) == "", return; end
            m.addColumn(name,lower(string(lev)),lower(string(typ)));
        end

        function removeColumn(obj)
            % The selected column when it is one of the user's own; else ask
            % which (Ctrl+Z brings a removed column back with its values).
            free = obj.freeColumns();
            if isempty(free)
                obj.status("There is no column of your own to remove (Add column… makes one).",1);
                return
            end
            name = obj.SelectedColumn;
            if ~any(free == name)
                c = obj.Model.ConfirmFcn("Remove which column? Its values go with it (Ctrl+Z " + ...
                    "brings them back).","Remove column",[free,"Cancel"],"Cancel");
                name = string(c);
                if ~any(free == name), return; end
            end
            obj.Model.removeColumn(name);
            obj.SelectedColumn = "";
        end

        function timepointOrder(obj)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.openDialog("levels","Timepoint");
            else
                obj.status("The timepoint order is set in the Timepoint order dialog.",0);
            end
        end

        function analyseSelected(obj)
            obj.analyseKeys(obj.SelectedKeys);
        end

        function analyseStale(obj)
            obj.analyseKeys(obj.staleKeys(obj.Data.V));
        end

        function analyseKeys(obj,keys)
            % The batch dialog for these sessions -- or, without one (or
            % with UseDialogs false), the batch itself after a confirmation.
            keys = reshape(string(keys),[],1);
            if isempty(keys)
                obj.status("No sessions to analyse.",0);
                return
            end
            if obj.UseDialogs && ~isempty(obj.Host) && isvalid(obj.Host) && ...
                    exist('mabr.ui.analysis.BatchDialog','class') == 8
                obj.Host.openDialog("batch",keys);
                return
            end
            m = obj.Model;
            c = m.ConfirmFcn(sprintf('Analyse %d session(s) with the project''s settings?',numel(keys)), ...
                "Analyse sessions",["Analyse","Cancel"],"Analyse");
            if string(c) ~= "Analyse", return; end
            m.batch(keys,SkipCurrent=false);
        end

        function reviewQueue(obj)
            V = obj.Data.V;
            keys = obj.SelectedKeys;
            if isempty(keys)
                keys = V.Key(V.InStudy & V.SubjectInStudy & V.Status ~= "none");
            end
            if obj.UseDialogs && ~isempty(obj.Host) && isvalid(obj.Host) && ...
                    exist('mabr.ui.analysis.ReviewDialog','class') == 8
                obj.Host.openDialog("review",keys);
                return
            end
            obj.Model.startReviewQueue(keys,UnreviewedOnly=true);
        end

        function exportStudy(obj)
            % The export dialog on what this tab is about: the sessions
            % selected in the table, else the study.
            if isempty(obj.Host) || ~isvalid(obj.Host)
                obj.status("Export… needs the analysis window (File ▸ Export…).",1);
                return
            end
            if isempty(obj.SelectedKeys)
                obj.Host.openDialog("export",'Scope',"instudy");
            else
                obj.Host.openDialog("export",'Keys',obj.SelectedKeys,'Scope',"selected");
            end
        end

        function dismissEmpty(obj)
            obj.EmptyDismissed = true;
            obj.hideEmpty();
            obj.showSub("Sessions");
        end

        % ---- Thresholds sub-tab -----------------------------------------
        function renderThresholds(obj)
            S = mabr.ui.analysis.Style;
            L = obj.ViewLook;
            panel = obj.Handles.ThrPanel;
            obj.ThrPoints = table();
            [T,uinfo] = obj.familyThresholds();
            params = obj.familyParams();
            dirn = "auto";
            try
                dirn = string(obj.Model.Settings.LevelDirection);
            catch
            end
            [P,info] = mabr.ui.analysis.StudyView.thresholdUnits(T,NoResponse=string(L.NoResponse), ...
                Reference=obj.referenceCode(),Params=params,Direction=dirn);
            xAxis = string(obj.Handles.X.Value);
            byTime = xAxis == "Timepoint" || isempty(params);
            unit = uinfo.Unit;
            if unit == "", unit = "dB"; end
            if height(P) == 0
                obj.emptyAxes("thresholds",panel,"No thresholds of this family are in the study yet.");
                obj.PlotNotes.Thresholds = "";
                obj.put('readout_thresholds',obj.Handles.ThrReadout,'Text','');
                return
            end
            % where each point goes
            P.Tile = obj.tileKeys(P,byTime);
            if byTime
                P.XPlot = obj.timepointPositions(P.Timepoint,P.TimepointOrder);
                P.Line  = P.Subject + "|" + P.Series;
            else
                P.XPlot = P.X;
                P.Line  = P.Subject + "|" + P.Timepoint + "|" + P.Sessions;
            end
            [P.Color,glabels] = obj.colourKeys(P);
            obj.ThrPoints = P;

            tiles = obj.tileOrder(P);
            note = obj.ruleText(info,unit);
            obj.PlotNotes.Thresholds = note;
            sig = {P,L,tiles,glabels,byTime,params,unit,note,obj.Data.TpNames};
            if obj.sameDrawn("thresholds",sig), return; end
            ax = obj.tiles("thresholds",panel,numel(tiles));
            perSubject = string(L.Layout) == "subject";
            showInd = perSubject || any(string(L.Show) == ["individuals","both"]);
            showSum = ~perSubject && any(string(L.Show) == ["mean","median","both"]);
            fade = showInd && showSum;
            ng = numel(glabels);
            nt = numel(tiles);
            [tH,tL,tG] = deal(cell(nt,1));
            for t = 1:nt
                a = ax(t);
                a.UserData = struct('Plot',"thresholds",'Tile',tiles(t));
                rows = P.Tile == tiles(t);
                H = gobjects(0);  labs = strings(0,1);  gs = zeros(1,0);
                for gi = 1:ng
                    gr = rows & P.Color == glabels(gi);
                    if ~any(gr), continue; end
                    c = S.colorFor(gi,ng);
                    ci = c;
                    if fade, ci = c + (1 - c)*0.55; end
                    hLeg = gobjects(0);
                    if showInd
                        hLeg = obj.drawIndividuals(a,P(gr,:),ci,info.Shift,c);
                    end
                    nSubj = numel(unique(P.Subject(gr)));
                    if showSum
                        hs = obj.drawSummary(a,P.XPlot(gr),P.Plotted(gr),P.Subject(gr),c, ...
                            string(L.Show) == "median",glabels(gi),[],P.Kind(gr));
                        if ~isempty(hs), hLeg = hs; end
                    end
                    if ~isempty(hLeg)
                        H(end+1) = hLeg(1); %#ok<AGROW>
                        gs(end+1) = gi; %#ok<AGROW>
                        if perSubject
                            labs(end+1) = glabels(gi); %#ok<AGROW>
                        else
                            labs(end+1) = glabels(gi) + " (n = " + nSubj + ")"; %#ok<AGROW>
                        end
                    end
                end
                [tH{t},tL{t},tG{t}] = deal(H,labs,gs);
                % the censored points (▲ no response, ▼ all respond) above
                % the summary: they are the values the subtitle's rule is
                % about, and a summary's filled circle would hide them
                cen = findobj(a,'-regexp','Tag','^AnalysisStudy(NoResponse|AllRespond)Points');
                if ~isempty(cen)
                    try
                        uistack(cen,'top');
                    catch
                    end
                end
                obj.axisX(a,P.XPlot(rows),byTime,params,P.Timepoint(rows));
                yv = P.Plotted(rows);
                obj.axisY(a,yv);
                if ~info.Shift
                    ce = unique(P.Ceiling(rows & P.Kind == "noresponse"));
                    ce = ce(isfinite(ce));
                    xl = a.XLim;
                    for q = reshape(ce,1,[])
                        line(a,xl,[q q],'LineStyle','--','Color',S.Muted,'LineWidth',0.8, ...
                            'Tag','AnalysisStudyCeiling','HitTest','off','HandleVisibility','off');
                    end
                end
                if info.Shift
                    ylabel(a,sprintf('Threshold shift re %s (%s)',info.RefName,'dB'));
                else
                    ylabel(a,sprintf('Threshold (%s)',unit));
                end
                if tiles(t) ~= "", title(a,tiles(t),'Interpreter','none','FontWeight','normal'); end
            end
            obj.placeLegends(ax,tH,tL,tG,glabels,perSubject);
            obj.tileNote(ax,note);
            obj.Readout = "";
            obj.put('readout_thresholds',obj.Handles.ThrReadout,'Text', ...
                'Click a point for its details; double-click opens the session on that series.');
            obj.DrawnSig.thresholds = sig;
        end

        function tf = sameDrawn(obj,plot,sig)
            % Would this render draw exactly what PLOT's axes already show?
            key = char("Ax_" + plot);
            tf = isfield(obj.Handles,key) && ~isempty(obj.Handles.(key)) && ...
                all(isgraphics(obj.Handles.(key))) && isequaln(obj.DrawnSig.(char(plot)),sig);
        end

        function note = ruleText(~,info,unit)
            % The plot's subtitle: how no response (and all-respond) was counted.
            parts = strings(1,0);
            u = "dB";
            if contains(unit,"dB"), u = unit; end
            if info.Dropped > 0
                parts(end+1) = "no response left out (n = " + info.Dropped + ")";
            elseif info.NoResponse > 0
                ce = info.Ceilings;
                if isscalar(ce)
                    parts(end+1) = "no response counted as " + sprintf('%g',ce) + " " + u + ...
                        " (n = " + info.NoResponse + ")";
                else
                    parts(end+1) = "no response counted as " + sprintf('%g',min(ce)) + "–" + ...
                        sprintf('%g',max(ce)) + " " + u + " (n = " + info.NoResponse + ")";
                end
            end
            if info.AllRespond > 0
                parts(end+1) = "all levels responding plotted at the quietest level (n = " + info.AllRespond + ")";
            end
            if info.Excluded > 0
                parts(end+1) = info.Excluded + " excluded";
            end
            if info.NoReference > 0
                parts(end+1) = info.NoReference + " without a reference left out";
            end
            note = strjoin(parts,"; ");
        end

        function h = drawIndividuals(~,a,P,c,shift,strong)
            % Each subject's points (one marker line per kind and fill) and
            % the lines joining them (one NaN-gapped line), hit-test off: a
            % click goes to the axes, which finds the nearest point.
            % Returns the group's legend key.
            [~,~,j] = unique(P.Line,'stable');
            X = zeros(0,1);  Y = zeros(0,1);
            for q = 1:max(j)
                r = find(j == q);
                [~,o] = sort(P.XPlot(r));
                r = r(o);
                X = [X; P.XPlot(r); NaN]; %#ok<AGROW>
                Y = [Y; P.Plotted(r); NaN]; %#ok<AGROW>
            end
            line(a,X,Y,'Color',c,'LineWidth',0.8,'Tag','AnalysisStudyIndividuals','HitTest','off', ...
                'HandleVisibility','off','DisplayName',char(P.Color(1)));
            % The group's legend key: a line and a filled circle in its
            % colour, whatever kinds of point it holds (a group of no-
            % response points alone would otherwise be keyed by a ▲, the
            % no-response symbol). No data, so Copy data passes it by.
            h = line(a,NaN,NaN,'Color',strong,'LineWidth',0.8,'Marker','o','MarkerSize',5, ...
                'MarkerFaceColor',strong,'Tag','AnalysisStudyLegendKey','HitTest','off', ...
                'DisplayName',char(P.Color(1)));
            kinds = ["value","noresponse","allrespond"];
            marks = ["o","^","v"];
            % (not "AnalysisStudyNoResponse": that Tag is the rule's dropdown)
            tags  = ["AnalysisStudyPoints","AnalysisStudyNoResponsePoints","AnalysisStudyAllRespondPoints"];
            % hollow only means something in a shift plot (a shift that
            % involves a censored value); there, filled and hollow markers
            % are separate lines so each keeps its own face
            holes = false;
            if shift, holes = [false true]; end
            for k = 1:3
                for hol = holes
                    r = P.Kind == kinds(k);
                    if shift, r = r & P.Hollow == hol; end
                    if ~any(r), continue; end
                    % a censored value -- and a shift involving one --
                    % keeps the group's full colour even when the
                    % individuals recede behind a summary: it is the point
                    % the rule in the subtitle is about (and a hollow
                    % marker in a faded colour all but disappears)
                    ec = c;  ms = 6;
                    if k > 1 || hol, ec = strong;  ms = 7; end
                    fc = ec;
                    tag = tags(k);
                    if hol, fc = 'none'; tag = tag + "Hollow"; end
                    line(a,P.XPlot(r),P.Plotted(r),'LineStyle','none', ...
                        'Marker',char(marks(k)),'MarkerSize',ms,'MarkerEdgeColor',ec, ...
                        'MarkerFaceColor',fc,'Tag',char(tag),'HitTest','off', ...
                        'DisplayName',char(P.Color(1)));
                end
            end
        end

        function h = drawSummary(~,a,x,y,subj,c,useMedian,name,xpos,kinds)
            % Across SUBJECTS at each x: each subject's mean first, then the
            % mean ± SEM (or median and IQR) of those.
            %   xpos   where each point really is, when x only groups them
            %          (growth re threshold: x is a bin); the summary is then
            %          drawn at the subjects' mean position in the bin, not
            %          at the bin's centre, which can sit half a level step
            %          from every point it summarises. Default x.
            %   kinds  each point's kind ("value", "noresponse",
            %          "allrespond"; thresholds only): a summary point made
            %          of censored values alone is drawn with their symbol,
            %          hollow (▲ / ▼, or a hollow circle for a mix) -- it is
            %          a substituted number, not a measured one
            if nargin < 9 || isempty(xpos), xpos = x; end
            if nargin < 10, kinds = []; end
            h = gobjects(0);
            ux = unique(x(isfinite(x)));
            if isempty(ux), return; end
            m = NaN(numel(ux),1);  lo = m;  hi = m;
            px = ux;
            sym = strings(numel(ux),1);           % "" measured, else the censored symbol
            for i = 1:numel(ux)
                r = x == ux(i) & isfinite(y);
                if ~isempty(kinds) && any(r)
                    kk = string(kinds(r));
                    if all(kk == "noresponse"), sym(i) = "^";
                    elseif all(kk == "allrespond"), sym(i) = "v";
                    elseif all(kk ~= "value"), sym(i) = "o";
                    end
                end
                s = unique(subj(r));
                v = NaN(numel(s),1);
                w = NaN(numel(s),1);
                for k = 1:numel(s)
                    v(k) = mean(y(r & subj == s(k)));
                    w(k) = mean(xpos(r & subj == s(k)));
                end
                if isempty(v), continue; end
                if all(isfinite(w)), px(i) = mean(w); end
                if useMedian
                    q = mabr.analysis.Stats.percentile(v,[0.25 0.5 0.75]);
                    m(i) = q(2);  lo(i) = q(2) - q(1);  hi(i) = q(3) - q(2);
                else
                    m(i) = mean(v);
                    if numel(v) > 1, lo(i) = std(v)/sqrt(numel(v)); else, lo(i) = 0; end
                    hi(i) = lo(i);
                end
            end
            ok = isfinite(m);
            if ~any(ok), return; end
            h = errorbar(a,px(ok),m(ok),lo(ok),hi(ok),'Color',c,'LineWidth',1.8,'Marker','o', ...
                'MarkerSize',7,'MarkerFaceColor',c,'CapSize',5,'Tag','AnalysisStudySummary','HitTest','off', ...
                'DisplayName',char(name));
            % censored-only points: the filled circle covered in white,
            % then the censoring symbol, hollow (hidden handles: drawing,
            % not data -- Copy data takes the summary itself)
            for g = ["^","v","o"]
                sel = ok & sym == g;
                if ~any(sel), continue; end
                line(a,px(sel),m(sel),'LineStyle','none','Marker','o','MarkerSize',9, ...
                    'MarkerFaceColor',[1 1 1],'MarkerEdgeColor',[1 1 1],'HitTest','off', ...
                    'HandleVisibility','off','Tag','AnalysisStudySummaryCensored');
                line(a,px(sel),m(sel),'LineStyle','none','Marker',char(g),'MarkerSize',8, ...
                    'MarkerFaceColor',[1 1 1],'MarkerEdgeColor',c,'LineWidth',1.5,'HitTest','off', ...
                    'HandleVisibility','off','Tag','AnalysisStudySummaryCensored');
            end
        end

        % ---- Growth sub-tab ---------------------------------------------
        function renderGrowth(obj)
            S = mabr.ui.analysis.Style;
            L = obj.ViewLook;
            panel = obj.Handles.GrowthPanel;
            obj.GrowthPoints = table();
            [G,info] = obj.growthData();
            obj.GrowthPoints = G;
            if height(G) == 0
                obj.emptyAxes("growth",panel,"No " + lower(info.MeasureText) + " to plot for this series.");
                obj.PlotNotes.Growth = info.Note;
                obj.put('readout_growth',obj.Handles.GrowthReadout,'Text','');
                return
            end
            [G.Color,glabels] = obj.colourKeys(G);
            perSubject = string(L.Layout) == "subject";
            if perSubject, G.Tile = G.Subject; else, G.Tile = repmat("",height(G),1); end
            obj.GrowthPoints = G;
            tiles = obj.tileOrder(G);
            obj.PlotNotes.Growth = info.Note;
            sig = {G,L,tiles,glabels,info};
            if obj.sameDrawn("growth",sig), return; end
            ax = obj.tiles("growth",panel,numel(tiles));
            showInd = perSubject || any(string(L.Show) == ["individuals","both"]);
            showSum = ~perSubject && any(string(L.Show) == ["mean","median","both"]);
            fade = showInd && showSum;
            ng = numel(glabels);
            nt = numel(tiles);
            [tH,tL,tG] = deal(cell(nt,1));
            for t = 1:nt
                a = ax(t);
                a.UserData = struct('Plot',"growth",'Tile',tiles(t));
                rows = G.Tile == tiles(t);
                H = gobjects(0);  labs = strings(0,1);  gs = zeros(1,0);
                for gi = 1:ng
                    gr = rows & G.Color == glabels(gi);
                    if ~any(gr), continue; end
                    c = S.colorFor(gi,ng);
                    ci = c;
                    if fade, ci = c + (1 - c)*0.55; end
                    hLeg = gobjects(0);
                    if showInd
                        sub = G(gr,:);
                        [~,~,j] = unique(sub.Line,'stable');
                        X = zeros(0,1);  Y = zeros(0,1);
                        for q = 1:max(j)
                            r = find(j == q);
                            [~,o] = sort(sub.X(r));
                            r = r(o);
                            X = [X; sub.X(r); NaN]; %#ok<AGROW>
                            Y = [Y; sub.Y(r); NaN]; %#ok<AGROW>
                        end
                        hLeg = line(a,X,Y,'Color',ci,'LineWidth',0.8,'Marker','o','MarkerSize',4, ...
                            'MarkerFaceColor',ci,'Tag','AnalysisStudyGrowthIndividuals','HitTest','off', ...
                            'DisplayName',char(glabels(gi)));
                    end
                    if showSum
                        % grouped by bin (re threshold, each subject's
                        % levels fall elsewhere), drawn where the bin's
                        % subjects actually are
                        hs = obj.drawSummary(a,G.XBin(gr),G.Y(gr),G.Subject(gr),c, ...
                            string(L.Show) == "median",glabels(gi),G.X(gr));
                        if ~isempty(hs), hs.Tag = 'AnalysisStudyGrowthSummary'; hLeg = hs; end
                    end
                    if ~isempty(hLeg)
                        H(end+1) = hLeg(1); %#ok<AGROW>
                        gs(end+1) = gi; %#ok<AGROW>
                        n = numel(unique(G.Subject(gr)));
                        lab = glabels(gi);
                        if ~perSubject, lab = lab + " (n = " + n + ")"; end
                        labs(end+1) = lab; %#ok<AGROW>
                    end
                end
                [tH{t},tL{t},tG{t}] = deal(H,labs,gs);
                xv = G.X(rows);
                xv = xv(isfinite(xv));
                if ~isempty(xv)
                    pad = max(2,0.05*(max(xv) - min(xv)));
                    a.XLim = [min(xv) - pad, max(xv) + pad];
                end
                obj.axisY(a,G.Y(rows));
                xlabel(a,info.XLabel);
                ylabel(a,info.YLabel);
                if tiles(t) ~= "", title(a,tiles(t),'Interpreter','none','FontWeight','normal'); end
            end
            obj.placeLegends(ax,tH,tL,tG,glabels,perSubject);
            obj.tileNote(ax,info.Note);
            obj.Readout = "";
            obj.put('readout_growth',obj.Handles.GrowthReadout,'Text', ...
                'Click a point for its details; double-click opens the session on that series.');
            obj.DrawnSig.growth = sig;
        end

        function [G,info] = growthData(obj)
            % growthDataNow, once per render pass (the banner asks first,
            % then the plot).
            if isfield(obj.Pass,'Growth')
                [G,info] = obj.Pass.Growth{:};
                return
            end
            [G,info] = obj.growthDataNow();
            obj.Pass.Growth = {G,info};
        end

        function [G,info] = growthDataNow(obj)
            % The growth points of the chosen family, series, wave and
            % measure (A9: latencies re sound arrival when a delay is set).
            L = obj.ViewLook;
            A = obj.Data.A;
            meas = string(L.Measure);
            k = find(obj.MeasureCodes == meas,1);
            if isempty(k), k = 1; end
            info = struct('MeasureText',obj.MeasureItems(k),'XLabel',obj.growthLevelLabel(),'YLabel',"", ...
                'Note',"",'LeftOutProcessing',strings(0,1),'LeftOutUnits',strings(0,1), ...
                'Processing',"",'OtherProcessing',strings(0,1),'Units',"",'OtherUnits',strings(0,1), ...
                'Offset',false,'NoThreshold',0,'NoReference',0);
            G = mabr.ui.analysis.StudyView.emptyGrowth();
            P = obj.familyPeaks();
            if height(P) == 0, return; end
            at = obj.Choice.At;
            P = P(string(P.SeriesKeyShort) == at,:);
            if height(P) == 0, return; end
            % processing and amplitude units, per condition
            C = A.Conditions;
            ck = string(P.Session) + "#" + string(P.Key);
            proc = strings(height(P),1);  un = strings(height(P),1);
            if height(C) > 0
                cc = string(C.Session) + "#" + string(C.Key);
                [tf,loc] = ismember(ck,cc);
                if ismember('Processing',C.Properties.VariableNames)
                    proc(tf) = string(C.Processing(loc(tf)));
                end
                if ismember('Units',C.Properties.VariableNames)
                    un(tf) = string(C.Units(loc(tf)));
                end
            end
            pl = unique(proc(proc ~= ""),'stable');
            if isempty(pl), pl = ""; end
            want = obj.Choice.Processing;
            if ~any(pl == want), want = mabr.ui.analysis.StudyView.mostCommon(proc(proc ~= "")); end
            if want == "" && ~isempty(pl), want = pl(1); end
            obj.Choice.Processing = want;
            obj.setChoice('proc',obj.Handles.Processing,pl,pl,want);
            okP = proc == want | proc == "";
            info.Processing = want;
            info.LeftOutProcessing = unique(string(P.Session(~okP)));
            info.OtherProcessing = unique(proc(~okP));
            isAmp = startsWith(meas,"amp");
            okU = true(height(P),1);
            if isAmp
                umaj = mabr.ui.analysis.StudyView.mostCommon(un(un ~= ""));
                okU = un == umaj | un == "";
                info.Units = umaj;
                info.LeftOutUnits = unique(string(P.Session(~okU)));
                info.OtherUnits = unique(un(~okU));
            end
            P = P(okP & okU,:);
            % picked waves above threshold (Peaks.derived's rule)
            picked = ismember(string(P.State),["auto","manual"]) & isfinite(double(P.PeakLatency));
            if ismember('BelowThreshold',P.Properties.VariableNames)
                picked = picked & ~logical(P.BelowThreshold);
            end
            P = P(picked,:);
            if height(P) == 0, return; end
            if startsWith(meas,"ipl")
                % a difference of two latencies: the offset cancels
                w = split(extractAfter(meas,4),"-");
                [Y,P] = mabr.ui.analysis.StudyView.interpeak(P,w(1),w(2));
                info.YLabel = "Interpeak " + w(1) + "–" + w(2) + " (ms)";
            else
                P = P(string(P.Wave) == obj.Choice.Wave,:);
                switch meas
                    case "amp-bp"
                        Y = 1e6*double(P.AmpBP);
                        info.YLabel = "Wave " + obj.Choice.Wave + " baseline–peak (µV)";
                    case "latency"
                        % the REPORTED latency (ear time); the label says
                        % "re sound arrival" once a plotted point has an
                        % offset (decided below, after the points are known)
                        off = zeros(height(P),1);
                        if ismember('LatencyOffset',P.Properties.VariableNames)
                            off = double(P.LatencyOffset);  off(~isfinite(off)) = 0;
                        end
                        Y = mabr.analysis.Peaks.reported(double(P.PeakLatency),off);
                        P.Offset_ = off;
                        info.YLabel = "Wave " + obj.Choice.Wave + " latency (ms)";
                    otherwise
                        Y = 1e6*double(P.AmpPT);
                        info.YLabel = "Wave " + obj.Choice.Wave + " P–N amplitude (µV)";
                end
            end
            ok = isfinite(Y);
            P = P(ok,:);  Y = Y(ok);
            if height(P) == 0, return; end
            lev = double(P.Level);
            X = lev;
            n = height(P);
            % the subject's threshold for X re threshold
            if string(L.XMode) == "re-threshold"
                T = obj.Data.A.Thresholds;
                fin = NaN(n,1);
                if height(T) > 0
                    tk = string(T.Session) + "#" + string(T.Key);
                    [tf,loc] = ismember(string(P.Session) + "#" + string(P.SeriesKey),tk);
                    f = double(T.Final);
                    cz = mabr.ui.analysis.StudyView.column(T,"FinalCensored",repmat("none",height(T),1));
                    % only a threshold that was found: "no response" has no
                    % level to count from, and "all respond" no lower bound
                    f(~(isfinite(f) & ismember(cz,["none","interval",""]))) = NaN;
                    fin(tf) = f(loc(tf));
                end
                X = lev - fin;
                keep = isfinite(X);
                info.NoThreshold = numel(unique(string(P.Session(~keep)) + "|" + string(P.SeriesKey(~keep))));
                P = P(keep,:);  Y = Y(keep);  X = X(keep);  lev = lev(keep);
                info.XLabel = "Level re threshold (dB)";
            end
            if height(P) == 0, return; end
            if ismember('Offset_',P.Properties.VariableNames) && any(P.Offset_ ~= 0)
                info.Offset = true;
                info.YLabel = "Wave " + obj.Choice.Wave + " latency re sound arrival (ms)";
            end
            G = table(string(P.Subject),string(P.Timepoint),obj.timepointOrderOf(P), ...
                string(P.Group),string(P.Session),string(P.SeriesKey),lev,X,Y, ...
                'VariableNames',{'Subject','Timepoint','TimepointOrder','Group','Session', ...
                'SeriesKey','Level','X','Y'});
            % the "mean" policy: one value per subject x timepoint x level
            ukey = G.Subject + "|" + lower(G.Timepoint) + "|" + G.SeriesKey + "|" + string(G.Level);
            [gk,first,j] = unique(ukey,'stable');
            if numel(gk) < height(G)
                M = G(first,:);
                M.Sessions = M.Session;
                for q = 1:numel(gk)
                    r = find(j == q);
                    if numel(r) < 2, continue; end
                    M.Y(q) = mean(G.Y(r));
                    M.X(q) = mean(G.X(r));
                    M.Sessions(q) = join(unique(G.Session(r),'stable'),"|");
                end
                G = M;
            else
                G.Sessions = G.Session;
            end
            % % of the subject's reference timepoint
            if string(L.YMode) == "percent"
                ref = obj.referenceCode();
                if ref == "none"
                    % no Reference chosen: the study's reference timepoint
                    % (the project's, else the first in Timepoint order) --
                    % not each subject's own first, which would make a
                    % subject seen only later its own 100%
                    ref = "first";
                    tps = obj.studyTimepoints();
                    try
                        rp = string(obj.Model.Project.ReferenceTimepoint);
                        if rp ~= "", tps = rp; end
                    catch
                    end
                    if ~isempty(tps), ref = "tp:" + tps(1); end
                end
                keep = false(height(G),1);
                Y2 = NaN(height(G),1);
                stt = mabr.ui.analysis.StudyView.startTimes(A.Sessions,G.Session);
                for i = 1:height(G)
                    rows = find(G.Subject == G.Subject(i) & G.SeriesKey == G.SeriesKey(i) & ...
                        G.Level == G.Level(i));
                    if startsWith(ref,"tp:")
                        r0 = rows(lower(G.Timepoint(rows)) == lower(extractAfter(ref,3)));
                    else
                        r0 = rows(mabr.ui.analysis.StudyView.firstOf(G.TimepointOrder(rows),stt(rows)));
                    end
                    if isempty(r0) || ~(abs(G.Y(r0(1))) > 0), continue; end
                    Y2(i) = 100*G.Y(i)/G.Y(r0(1));
                    keep(i) = true;
                end
                info.NoReference = nnz(~keep);
                G.Y = Y2;
                G = G(keep,:);
                yl = char(info.YLabel);
                info.YLabel = string(regexprep(yl,'\((µV|ms)\)$','')) + "(% of reference)";
            end
            G.Line = G.Subject + "|" + G.Timepoint + "|" + G.Sessions;
            % summary bins: levels re threshold differ between subjects
            if string(L.XMode) == "re-threshold"
                st = median(diff(unique(G.Level)));
                if ~(st > 0), st = 5; end
                G.XBin = st*round(G.X/st);
            else
                G.XBin = G.X;
            end
            info.Note = obj.growthNote(info);
        end

        function note = growthNote(~,info)
            parts = strings(1,0);
            if ~isempty(info.LeftOutProcessing)
                parts(end+1) = "showing " + info.Processing + " processing; " + ...
                    numel(info.LeftOutProcessing) + " session(s) processed otherwise left out";
            end
            if ~isempty(info.LeftOutUnits)
                parts(end+1) = numel(info.LeftOutUnits) + " session(s) in other amplitude units left out";
            end
            if info.NoThreshold > 0
                parts(end+1) = info.NoThreshold + " series without a threshold left out";
            end
            if info.NoReference > 0
                parts(end+1) = info.NoReference + " point(s) without a reference left out";
            end
            if info.Offset
                parts(end+1) = "latencies re sound arrival";
            end
            note = strjoin(parts,"; ");
        end

        % ---- Waveforms sub-tab ------------------------------------------
        function renderWaveforms(obj)
            S = mabr.ui.analysis.Style;
            L = obj.ViewLook;
            panel = obj.Handles.WavesPanel;
            obj.WaveCurves = table();
            [W,t,info] = obj.waveData();
            obj.WaveCurves = W;
            obj.PlotNotes.Waveforms = info.Note;
            stacked = info.Mode == "levels";
            obj.syncWaveControls(stacked,info.Note);
            if height(W) == 0
                obj.WaveGrid = struct();
                obj.emptyAxes("waveforms",panel,"No averaged waveforms of this series and level are in the study.");
                return
            end
            if stacked
                obj.renderWaveGrid(W,t,info);
                return
            end
            perSubject = string(L.Layout) == "subject";
            bySeries = info.Mode == "series";          % every series at one level: a panel each
            if bySeries && perSubject
                W.Tile = W.Subject + " · " + W.Series;
            elseif bySeries
                W.Tile = W.Series;
            elseif perSubject
                W.Tile = W.Subject;
            else
                W.Tile = repmat("",height(W),1);
            end
            obj.WaveCurves = W;
            tiles = obj.tileOrder(W);
            glabels = obj.groupOrder(W);
            sig = {W,t,L,tiles,glabels,info};
            if obj.sameDrawn("waveforms",sig), return; end
            obj.WaveGrid = struct();
            ax = obj.tiles("waveforms",panel,numel(tiles));
            ng = numel(glabels);
            showInd = perSubject || any(string(L.Show) == ["individuals","both"]);
            showSum = ~perSubject && any(string(L.Show) == ["mean","median","both"]);
            fade = showInd && showSum;
            t = t(:);
            nt = numel(tiles);
            [tH,tL,tG] = deal(cell(nt,1));
            for k = 1:nt
                a = ax(k);
                a.UserData = struct('Plot',"waveforms",'Tile',tiles(k));
                rows = W.Tile == tiles(k);
                H = gobjects(0);  labs = strings(0,1);  gs = zeros(1,0);
                for gi = 1:ng
                    gr = find(rows & W.Color == glabels(gi));
                    if isempty(gr), continue; end
                    c = S.colorFor(gi,ng);
                    ci = c;
                    if fade, ci = c + (1 - c)*0.55; end
                    Yg = 1e6*cell2mat(cellfun(@(y) y(:),W.Y(gr).','UniformOutput',false));   % [nt x ns]
                    hLeg = gobjects(0);
                    if showInd
                        X = repmat([t; NaN],numel(gr),1);
                        Y = reshape([Yg; NaN(1,numel(gr))],[],1);
                        hLeg = line(a,X,Y,'Color',ci,'LineWidth',0.7,'Tag','AnalysisStudyWaveIndividuals', ...
                            'HitTest','off','DisplayName',char(glabels(gi)));
                    end
                    if showSum
                        [mu,lo,hi] = mabr.ui.analysis.StudyView.curveSummary(Yg,string(L.Show) == "median");
                        ok = isfinite(lo) & isfinite(hi);
                        if any(ok)
                            tb = t(ok);
                            patch(a,[tb; flipud(tb)],[lo(ok); flipud(hi(ok))],c,'FaceAlpha',0.18, ...
                                'EdgeColor','none','Tag','AnalysisStudyBand','HitTest','off', ...
                                'HandleVisibility','off','DisplayName',char(glabels(gi)));
                        end
                        hLeg = line(a,t,mu,'Color',c,'LineWidth',1.8,'Tag','AnalysisStudyGrandMean', ...
                            'HitTest','off','DisplayName',char(glabels(gi)));
                    end
                    H(end+1) = hLeg(1); %#ok<AGROW>
                    gs(end+1) = gi; %#ok<AGROW>
                    n = numel(unique(W.Subject(gr)));
                    lab = glabels(gi);
                    if ~perSubject, lab = lab + " (n = " + n + ")"; end
                    labs(end+1) = lab; %#ok<AGROW>
                end
                [tH{k},tL{k},tG{k}] = deal(H,labs,gs);
                a.XLim = [min(t) max(t)];
                xlabel(a,info.XLabel);
                ylabel(a,"Amplitude (µV)");
                if tiles(k) ~= "", title(a,tiles(k),'Interpreter','none','FontWeight','normal'); end
            end
            % a panel per series is one plot cut in pieces: one legend, its
            % n counted over every panel
            names = obj.groupNames(W,glabels,perSubject);
            obj.placeLegends(ax,tH,tL,tG,glabels,perSubject || bySeries,names);
            obj.tileNote(ax,info.Note);
            obj.DrawnSig.waveforms = sig;
        end

        function renderWaveGrid(obj,W,t,info)
            % All levels: a column per series (per subject and series under
            % One panel per subject) with its levels stacked, loudest at
            % the top -- the Grid tab's layout -- and in every row each
            % subject's curve and each colour group's summary across
            % subjects, coloured as every other Study plot colours them.
            % The drawn traces are offset into their rows, so they carry
            % hidden handles; Copy data copies invisible lines holding the
            % same curves in µV, one per column x row x group.
            S = mabr.ui.analysis.Style;
            L = obj.ViewLook;
            panel = obj.Handles.WavesPanel;
            perSubject = string(L.Layout) == "subject";
            ser = reshape(info.Series,[],1);
            if perSubject
                subj = reshape(mabr.analysis.Stats.naturalSort(unique(W.Subject)),[],1);
                [si,ui] = ndgrid(1:numel(ser),1:numel(subj));      % series fastest
                cSubj = subj(ui(:));  cSer = ser(si(:));
                ckey = cSubj + " · " + cSer;
                W.Tile = W.Subject + " · " + W.Series;
            else
                cSubj = strings(numel(ser),1);  cSer = ser;
                ckey = cSer;
                W.Tile = W.Series;
            end
            have = ismember(ckey,W.Tile);
            cSubj = cSubj(have);  cSer = cSer(have);  ckey = ckey(have);
            obj.WaveCurves = W;
            % the rows, bottom to top: loudest at the top (on an attenuation
            % axis the largest number is the quietest)
            lv = sort(reshape(info.Levels,[],1));
            if obj.familyDescending(), lv = flipud(lv); end
            glabels = obj.groupOrder(W);
            sig = {W,t,L,ckey,lv,glabels,info,"grid"};
            if obj.sameDrawn("waveforms",sig), return; end

            nc = numel(ckey);  ng = numel(glabels);  nR = numel(lv);
            rowY = (0:nR-1).';
            showInd = perSubject || any(string(L.Show) == ["individuals","both"]);
            showSum = ~perSubject && any(string(L.Show) == ["mean","median","both"]);
            useMedian = string(L.Show) == "median";
            fade = showInd && showSum;
            [~,ci] = ismember(W.Tile,ckey);
            [~,gi] = ismember(W.Color,glabels);
            [~,ri] = ismember(W.Level,lv);
            t = t(:);
            Y = 1e6*cell2mat(cellfun(@(y) y(:),reshape(W.Y,1,[]),'UniformOutput',false));   % [nt x nW] µV

            % the summaries across subjects, per column x group x row
            [Mu,Lo,Hi] = deal(cell(nc,ng,nR));
            if showSum
                for c = 1:nc
                    for g = 1:ng
                        for k = 1:nR
                            q = ci == c & gi == g & ri == k;
                            if any(q)
                                [Mu{c,g,k},Lo{c,g,k},Hi{c,g,k}] = ...
                                    mabr.ui.analysis.StudyView.curveSummary(Y(:,q),useMedian);
                            end
                        end
                    end
                end
            end
            % the row spacing (µV between two rows): the largest curve drawn
            % in each column, of the grid, or the fixed number
            amp = zeros(nc,1);
            for c = 1:nc
                v = zeros(0,1);
                if showInd
                    v = Y(:,ci == c);
                end
                if showSum
                    v = [v(:); vertcat(Mu{c,:,:})];
                end
                v = abs(v(isfinite(v)));
                if ~isempty(v), amp(c) = max(v); end
            end
            switch string(L.WaveScale)
                case "global", den = repmat(max(amp),nc,1);
                case "fixed",  den = repmat(double(L.WaveFixed),nc,1);
                otherwise,     den = amp;
            end
            den(~(den > 0 & isfinite(den))) = 1;

            names = obj.groupNames(W,glabels,perSubject);
            ax = obj.tiles("waveforms",panel,nc);
            [pos,colPx] = obj.waveGridPositions(panel,nc,names);
            xl = [min(t) max(t)];
            yl = [-1.1, rowY(end) + 1.1 + 0.45];    % (+ headroom for the row spacing in the corner)
            levTxt = compose("%g",lv);
            what = obj.pick(useMedian,"median","mean");
            drawn = false(1,ng);
            for c = 1:nc
                a = ax(c);
                a.UserData = struct('Plot',"waveforms",'Tile',ckey(c));
                set(a,'Position',pos(c,:),'XLim',xl,'YLim',yl,'YTick',rowY.');
                if c == 1
                    a.YTickLabel = cellstr(levTxt);
                    ylabel(a,obj.growthLevelLabel());
                    xlabel(a,info.XLabel);
                else
                    a.YTickLabel = {};
                end
                if perSubject
                    title(a,{char(cSubj(c)),char(cSer(c))},'Interpreter','none','FontWeight','normal');
                else
                    title(a,char(cSer(c)),'Interpreter','none','FontWeight','normal');
                end
                % individuals first, the summaries over them
                for g = 1:ng
                    q = find(ci == c & gi == g);
                    if isempty(q) || ~showInd, continue; end
                    drawn(g) = true;
                    col = S.colorFor(g,ng);
                    if fade, col = col + (1 - col)*0.55; end
                    X = repmat([t; NaN],numel(q),1);
                    Yd = [reshape(rowY(ri(q)),1,[]) + Y(:,q)/den(c); NaN(1,numel(q))];
                    line(a,X,Yd(:),'Color',col,'LineWidth',0.7,'Tag','AnalysisStudyWaveGridIndividuals', ...
                        'HitTest','off','HandleVisibility','off','DisplayName',char(glabels(g)));
                end
                for g = 1:ng
                    if ~showSum || all(cellfun(@isempty,Mu(c,g,:))), continue; end
                    drawn(g) = true;
                    col = S.colorFor(g,ng);
                    Xm = zeros(0,1);  Ym = zeros(0,1);  Vb = zeros(0,2);  faces = {};
                    for k = 1:nR
                        mu = Mu{c,g,k};
                        if isempty(mu), continue; end
                        Xm = [Xm; t; NaN]; %#ok<AGROW>
                        Ym = [Ym; rowY(k) + mu/den(c); NaN]; %#ok<AGROW>
                        lo = Lo{c,g,k};  hi = Hi{c,g,k};
                        ok = isfinite(lo) & isfinite(hi);
                        if any(ok)
                            tb = t(ok);
                            v0 = size(Vb,1);
                            Vb = [Vb; tb, rowY(k) + lo(ok)/den(c); flipud(tb), rowY(k) + flipud(hi(ok))/den(c)]; %#ok<AGROW>
                            faces{end+1} = v0 + (1:2*nnz(ok)); %#ok<AGROW>
                        end
                    end
                    if ~isempty(faces)
                        % one patch, a face per row (shorter faces NaN-padded)
                        F = NaN(numel(faces),max(cellfun(@numel,faces)));
                        for f = 1:numel(faces), F(f,1:numel(faces{f})) = faces{f}; end
                        patch(a,'Vertices',Vb,'Faces',F,'FaceColor',col,'FaceAlpha',0.18, ...
                            'EdgeColor','none','Tag','AnalysisStudyWaveGridBand','HitTest','off', ...
                            'HandleVisibility','off','DisplayName',char(glabels(g)));
                    end
                    line(a,Xm,Ym,'Color',col,'LineWidth',1.6,'Tag','AnalysisStudyWaveGridMean', ...
                        'HitTest','off','HandleVisibility','off','DisplayName',char(glabels(g)));
                end
                % the values themselves, for Copy data (and a row nobody has)
                for k = 1:nR
                    qk = find(ci == c & ri == k);
                    if isempty(qk)
                        text(a,mean(xl),rowY(k),'not recorded','HorizontalAlignment','center', ...
                            'Color',S.Muted,'FontSize',8,'FontAngle','italic','HitTest','off', ...
                            'Tag','AnalysisStudyWaveGridMissing');
                        continue
                    end
                    for g = 1:ng
                        nm = ckey(c) + " · " + levTxt(k) + " dB · " + glabels(g);
                        qg = qk(gi(qk) == g);
                        if showInd && ~isempty(qg)
                            Yc = [Y(:,qg); NaN(1,numel(qg))];
                            obj.copyCarrier(a,repmat([t; NaN],numel(qg),1),Yc(:),nm + " · individuals (µV)");
                        end
                        if showSum && ~isempty(Mu{c,g,k})
                            obj.copyCarrier(a,t,Mu{c,g,k},nm + " · " + what + " (µV)");
                        end
                    end
                end
                if c == 1 || string(L.WaveScale) == "column"
                    text(a,0.01,1,char(obj.rowScaleText(den(c),colPx)),'Units','normalized', ...
                        'FontSize',7.5,'Color',S.Muted,'HorizontalAlignment','left', ...
                        'VerticalAlignment','top','HitTest','off','Interpreter','none', ...
                        'BackgroundColor',[1 1 1],'Margin',1,'Tag','AnalysisStudyWaveGridScale');
                end
                if c < nc, obj.setLegend(a,gobjects(0),strings(0,1)); end
            end
            % one legend for the grid, right of its last column
            keys = gobjects(1,0);
            for g = find(drawn)
                keys(end+1) = line(ax(nc),NaN,NaN,'Color',S.colorFor(g,ng), ...
                    'LineWidth',obj.pick(showSum,1.6,0.8),'Tag','AnalysisStudyLegendKey', ...
                    'HitTest','off','DisplayName',char(names(g))); %#ok<AGROW>
            end
            obj.gridLegend(ax(nc),keys,names(drawn),pos(nc,:));
            obj.WaveGrid = struct('Columns',ckey,'Levels',lv,'RowY',rowY,'RowScale',den, ...
                'Groups',glabels);
            obj.DrawnSig.waveforms = sig;
        end

        function syncWaveControls(obj,stacked,note)
            % The row Scale acts on the stacked grid only (Fixed µV with
            % it); the grid's note goes beneath the plot, where the other
            % plots carry theirs as a subtitle.
            L = obj.ViewLook;
            obj.put('wave_scale_en',obj.Handles.WaveScale,'Enable',obj.pick(stacked,'on','off'));
            obj.put('wave_fixed_en',obj.Handles.WaveFixed,'Enable', ...
                obj.pick(stacked && string(L.WaveScale) == "fixed",'on','off'));
            txt = "";
            if stacked, txt = string(note); end
            obj.put('wave_note',obj.Handles.WaveNote,'Text',char(txt));
            obj.put('wave_rows',obj.Handles.WavesGrid,'RowHeight',{30,'1x',obj.pick(txt ~= "",18,0)});
        end

        function [pos,colPx] = waveGridPositions(~,panel,n,names)
            % The grid's columns in one row of the panel: the level labels'
            % margin on the left, the legend's room on the right (from its
            % longest name), the titles' above -- in pixels, turned into
            % normalized positions for the panel's size now.
            %   colPx  (returned) a column's width, pixels
            W = 0;  H = 0;
            try
                pp = getpixelposition(panel);
                W = pp(3);  H = pp(4);
            catch
            end
            if W < 400 || H < 250
                % not laid out yet (a sub-tab drawn in the callback that
                % shows it): the plot panel's size in the window's default
                % layout rather than a new component's placeholder size
                W = 1100;  H = 560;
            end
            leg = 0;
            if ~isempty(names)
                leg = min(0.35*W,7*double(max(strlength(names))) + 52);
            end
            ml = 62;  mb = 46;  mt = 44;  gap = 10;  mr = max(leg,14);
            colPx = max((W - ml - mr - (n - 1)*gap)/n,24);
            h = max(H - mt - mb,40);
            pos = zeros(n,4);
            for j = 1:n
                pos(j,:) = [(ml + (j - 1)*(colPx + gap))/W, mb/H, colPx/W, h/H];
            end
        end

        function gridLegend(~,a,H,labs,pos)
            % The grid's legend outside its last column (top right), the
            % column put back where it was placed: an outside legend must
            % not narrow it.
            if isempty(H)
                try
                    if ~isempty(a.Legend), delete(a.Legend); end
                catch
                end
                return
            end
            try
                legend(a,H,cellstr(labs),'Location','northeastoutside','Interpreter','none', ...
                    'AutoUpdate','off','Box','off');
                a.Position = pos;
            catch me
                mabr.log.vprintf(2,'Study view: no grid legend (%s).',me.message);
            end
        end

        function s = rowScaleText(~,uv,colPx)
            % How many microvolts apart two rows are (a curve one row tall
            % is that big): "rows 2 µV apart", "↕ 2 µV" in a narrow column.
            u = mabr.ui.analysis.Style.formatUV(uv*1e-6,2);
            s = "rows " + u + " apart";
            if strlength(s)*0.66*7.5 > colPx - 8
                s = "↕ " + u;
            end
        end

        function copyCarrier(~,a,x,y,name)
            % An invisible line holding values for Copy data (the drawn
            % traces are offset into their rows).
            h = line(a,x,y,'Visible','off','HandleVisibility','off','HitTest','off', ...
                'Tag','AnalysisStudyWaveGridData','DisplayName',char(name));
            mabr.ui.analysis.FigureExport.markForCopy(h);
        end

        function names = groupNames(~,W,glabels,perSubject)
            % Each colour group's legend entry for a plot that has ONE
            % legend: its name, with the subjects it holds anywhere in the
            % plot (none under one panel per subject, where a panel is one).
            names = reshape(glabels,[],1);
            if perSubject, return; end
            for g = 1:numel(glabels)
                names(g) = glabels(g) + " (n = " + numel(unique(W.Subject(W.Color == glabels(g)))) + ")";
            end
        end

        function tf = familyDescending(obj)
            % Whether the family's levels get quieter as they grow (an
            % attenuation axis): what most of its series say.
            tf = false;
            T = obj.familyThresholds();
            if height(T) == 0, return; end
            dirn = "auto";
            try
                dirn = string(obj.Model.Settings.LevelDirection);
            catch
            end
            s = mabr.ui.analysis.StudyView.levelSigns(T,dirn);
            tf = nnz(s < 0) > nnz(s > 0);
        end

        function [W,t,info] = waveData(obj)
            % Per-subject curves on one time grid (the majority's; others
            % resampled), in ear time: of the chosen series at the chosen
            % level -- or, with All series and/or All levels, of each of
            % them. One curve per subject, colour group, series and level
            % (its sessions averaged).
            %   info.Mode    "single" (one series, one level), "series"
            %                (every series at one level: a panel each) or
            %                "levels" (every level stacked: the grid)
            %   info.Series  the series drawn, in parameter order
            %   info.Levels  the levels drawn, ascending
            L = obj.ViewLook;
            info = struct('XLabel',"Time re onset (ms)",'Note',"",'Resampled',0, ...
                'Mode',"single",'Series',strings(0,1),'Levels',zeros(0,1));
            W = table();  t = zeros(0,1);
            A = obj.Data.A;
            M = A.Means;
            [codes,~] = obj.familySeries();
            if height(M) == 0 || isempty(codes)
                obj.setChoice('wlevel',obj.Handles.WaveLevel,"","","");
                return
            end
            fam = obj.familyCode();
            [stim,acq] = mabr.ui.analysis.StudyView.splitFamily(fam);
            key = string(M.Key);
            sess = string(M.Session);
            % the series key: the condition key without its level part
            lp = obj.levelParamOf(A.Thresholds,sess);
            sk = strings(height(M),1);  lev = NaN(height(M),1);
            for i = 1:height(M)
                parts = split(key(i),"|");
                isL = startsWith(parts,lp(i) + "=");
                if any(isL), lev(i) = str2double(extractAfter(parts(find(isL,1)),strlength(lp(i)) + 1)); end
                sk(i) = join(parts(~isL),"|");
            end
            % each series' name and first parameter value (once per series)
            params = obj.familyParams();
            [usk,~,jsk] = unique(sk);
            ux = NaN(numel(usk),1);  un = strings(numel(usk),1);
            for i = 1:numel(usk)
                [ux(i),un(i)] = mabr.ui.analysis.StudyView.seriesValue(usk(i),params);
            end
            short = reshape(un(jsk),[],1);  xs = reshape(ux(jsk),[],1);
            used = obj.usedSeries(sess,sk);
            inFam = mabr.ui.analysis.StudyView.keyField2(sk,"Stimulus") == stim;
            if acq ~= "", inFam = inFam & mabr.ui.analysis.StudyView.keyField2(sk,"AcqMode") == acq; end
            allSer = logical(L.WaveAllSeries) && numel(codes) > 1;
            if allSer, ser = codes; else, ser = obj.Choice.WaveSeries; end
            r = used & inFam & ismember(short,ser);
            lv = unique(lev(r & isfinite(lev)));
            if isempty(lv)
                obj.setChoice('wlevel',obj.Handles.WaveLevel,"","","");
                return
            end
            lvTxt = string(lv);
            want = obj.Choice.WaveLevel;
            if ~any(lvTxt == want), want = lvTxt(end); end
            obj.Choice.WaveLevel = want;
            allLev = logical(L.WaveAllLevels) && numel(lv) > 1;
            items = lvTxt + " dB";  lcodes = lvTxt;  val = want;
            if numel(lv) > 1
                items = ["All levels"; items];
                lcodes = [obj.WaveAllCode; lcodes];
                if allLev, val = obj.WaveAllCode; end
            end
            obj.setChoice('wlevel',obj.Handles.WaveLevel,items,lcodes,val);
            if allLev
                info.Mode = "levels";
                r = find(r & isfinite(lev));
            else
                if allSer, info.Mode = "series"; end
                % by the item, not by str2double of its text: string(level)
                % keeps five significant digits, so 1/3 would not come back
                r = find(r & lev == lv(find(lvTxt == want,1)));
            end
            if isempty(r), return; end
            % the sessions' latency offsets (raw - offset = ear time)
            off = zeros(numel(r),1);
            Pk = A.Peaks;
            if height(Pk) > 0 && ismember('LatencyOffset',Pk.Properties.VariableNames)
                [us,~,ju] = unique(sess(r));
                ou = zeros(numel(us),1);
                ps = string(Pk.Session);
                po = double(Pk.LatencyOffset);
                for i = 1:numel(us)
                    o = po(ps == us(i));
                    o = o(isfinite(o));
                    if ~isempty(o), ou(i) = o(1); end
                end
                off = reshape(ou(ju),[],1);
            end
            if any(off ~= 0), info.XLabel = "Time re sound arrival (ms)"; end
            % the majority grid
            tt = M.Time(r);
            sig = strings(numel(r),1);
            for i = 1:numel(r)
                ti = double(tt{i}(:));
                dt = NaN;
                if numel(ti) > 1, dt = median(diff(ti)); end
                sig(i) = numel(ti) + "|" + sprintf('%.9g',dt);
            end
            major = mabr.ui.analysis.StudyView.mostCommon(sig);
            i0 = find(sig == major,1);
            t = double(tt{i0}(:)) - off(i0);
            curves = cell(numel(r),1);
            for i = 1:numel(r)
                ti = double(tt{i}(:)) - off(i);
                yi = double(M.Mean{r(i)}(:));
                if numel(ti) == numel(t) && all(abs(ti - t) < 1e-9)
                    curves{i} = yi;
                else
                    curves{i} = interp1(ti,yi,t,'linear',NaN);
                    info.Resampled = info.Resampled + 1;
                end
            end
            % session rows -> labels
            [tf,loc] = ismember(sess(r),string(A.Sessions.Session));
            subj = strings(numel(r),1);  tp = subj;  grp = subj;  tpo = NaN(numel(r),1);
            subj(tf) = string(A.Sessions.Subject(loc(tf)));
            tp(tf)   = string(A.Sessions.Timepoint(loc(tf)));
            grp(tf)  = string(A.Sessions.Group(loc(tf)));
            tpo(tf)  = double(A.Sessions.TimepointOrder(loc(tf)));
            S = table(subj,tp,tpo,grp,sess(r),curves,short(r),lev(r),xs(r),'VariableNames', ...
                {'Subject','Timepoint','TimepointOrder','Group','Session','Y','Series','Level','X'});
            [S.Color,~] = obj.colourKeys(S);
            % one curve per subject, colour group, series and level (its
            % sessions averaged)
            uk = S.Subject + "|" + S.Color + "|" + S.Series + "|" + compose("%.10g",S.Level);
            [g,first,j] = unique(uk,'stable');
            W = S(first,:);
            W.Sessions = W.Session;
            for q = 1:numel(g)
                rr = find(j == q);
                if numel(rr) > 1
                    W.Y{q} = mean(cell2mat(reshape(S.Y(rr),1,[])),2,'omitnan');
                    W.Sessions(q) = join(S.Session(rr),"|");
                end
            end
            W.Time = repmat({t},height(W),1);
            info.Series = reshape(codes(ismember(codes,W.Series)),[],1);
            info.Levels = reshape(unique(W.Level),[],1);
            parts = strings(1,0);
            if info.Resampled > 0
                parts(end+1) = info.Resampled + " session(s) resampled onto the majority time grid";
            end
            if any(off ~= 0), parts(end+1) = "time re sound arrival"; end
            info.Note = strjoin(parts,"; ");
        end

        % ---- banners --------------------------------------------------------
        function renderBanner(obj)
            % The most important of the study's warnings, one at a time.
            S = mabr.ui.analysis.Style;
            [kind,text,fcn] = obj.bannerFor(obj.ActiveSub);
            obj.BannerKind = kind;
            obj.BannerFcn = fcn;
            isDup = kind == "duplicates";
            obj.put('ban_dup_vis',obj.Handles.Duplicates,'Visible',obj.pick(isDup,'on','off'));
            obj.put('ban_vis',obj.Handles.Banner,'Visible',obj.pick(kind ~= "" && ~isDup,'on','off'));
            if isDup
                obj.put('ban_dup_text',obj.Handles.DuplicatesText,'Text',char(text));
            elseif kind ~= ""
                obj.put('ban_text',obj.Handles.BannerText,'Text',char(text));
                bgc = S.BarAmber;
                if kind == "sweeps", bgc = S.BarYellow; end
                obj.put('ban_bg',obj.Handles.Banner,'BackgroundColor',bgc);
                try
                    obj.put('ban_bg2',obj.Handles.BannerText.Parent,'BackgroundColor',bgc);
                catch
                end
                obj.put('ban_btn_vis',obj.Handles.BannerAction,'Visible',obj.pick(~isempty(fcn),'on','off'));
            end
            obj.layoutRows();
        end

        function [kind,text,fcn] = bannerFor(obj,sub)
            kind = "";  text = "";  fcn = [];
            D = obj.Data;
            A = D.A;
            T = A.Thresholds;
            usedSess = strings(0,1);
            if height(T) > 0 && all(ismember({'UsedInStudy','Session'},T.Properties.VariableNames))
                % (a study with no results at all has a Thresholds table
                % without columns)
                usedSess = unique(string(T.Session(logical(T.UsedInStudy))));
            end
            % level units (the threshold plot)
            if sub == "Thresholds"
                [~,u] = obj.familyThresholds();
                if ~isempty(u.LeftOut)
                    kind = "units";
                    text = "Level units differ (" + u.Unit + " vs " + strjoin(u.Other,", ") + ...
                        ") — thresholds are not comparable; " + numel(u.LeftOut) + ...
                        " session(s) in " + strjoin(u.Other,", ") + " left out of this plot.";
                    return
                end
            end
            % settings: sessions analysed differently from the rest
            if ~isempty(usedSess)
                [tf,loc] = ismember(usedSess,string(A.Sessions.Session));
                h = strings(numel(usedSess),1);
                h(tf) = string(A.Sessions.SettingsHash(loc(tf)));
                odd = usedSess(mabr.ui.analysis.StudyView.settingsOdd(h,D.Hash));
                if ~isempty(odd)
                    kind = "settings";
                    text = "Analysed with different settings: " + numel(odd) + " of " + ...
                        nnz(h ~= "") + " sessions.";
                    fcn = @() obj.analyseKeys(odd);
                    return
                end
            end
            % processing / amplitude units (the growth plot)
            if sub == "Growth"
                [~,g] = obj.growthData();
                if ~isempty(g.LeftOutProcessing)
                    kind = "processing";
                    text = "Processing differs (" + g.Processing + " vs " + strjoin(g.OtherProcessing,", ") + ...
                        "): showing " + g.Processing + "; " + numel(g.LeftOutProcessing) + " session(s) left out.";
                    return
                end
                if ~isempty(g.LeftOutUnits)
                    kind = "processing";
                    text = "Amplitude units differ (" + g.Units + " vs " + strjoin(g.OtherUnits,", ") + ...
                        "): " + numel(g.LeftOutUnits) + " session(s) left out.";
                    return
                end
            end
            % clean sweeps between the plotted groups
            if any(sub == ["Thresholds","Growth","Waveforms"])
                [bad,txt] = obj.sweepsDiffer();
                if bad
                    kind = "sweeps";
                    text = txt;
                    return
                end
            end
            % duplicates
            Dp = A.Duplicates;
            if height(Dp) > 0
                kind = "duplicates";
                text = obj.duplicatesText(Dp);
            end
        end

        function txt = duplicatesText(obj,Dp)
            % "2 duplicated series (SUBJ-ID-1254 · Baseline · Tone): using
            % 140845 (512 sweeps/condition)".
            V = obj.Data.V;
            n = height(Dp);
            stim = mabr.ui.analysis.StudyView.keyField(Dp.SeriesKey(1),"Stimulus");
            if stim == "", stim = string(Dp.SeriesKey(1)); end
            what = Dp.Subject(1) + " · " + Dp.Timepoint(1) + " · " + stim;
            if n > 1 && numel(unique(Dp.Subject + "|" + Dp.Timepoint)) > 1
                what = what + ", …";
            end
            usedK = split(Dp.Used(1),"|");
            pol = string(obj.Model.Project.DuplicatePolicy);
            if pol == "mean" || numel(usedK) > 1
                using = "the mean of " + numel(split(Dp.Keys(1),"|")) + " sessions";
            else
                r = find(string(V.Key) == usedK(1),1);
                nm = usedK(1);
                if ~isempty(r), nm = mabr.ui.analysis.StudyView.shortName(V.Name(r),V.Subject(r)); end
                sw = obj.seriesSweeps(usedK(1),Dp.SeriesKey(1));
                using = nm;
                if isfinite(sw), using = using + " (" + sprintf('%g',sw) + " sweeps/condition)"; end
            end
            txt = n + " duplicated series (" + what + "): using " + using + ".";
        end

        function sw = seriesSweeps(obj,session,seriesKey)
            % The median clean sweeps of the conditions of series SERIESKEY
            % of SESSION (NaN when unknown), vectorized over both.
            S = obj.Data.SeriesSweeps;
            sw = NaN(numel(session),1);
            [tf,loc] = ismember(reshape(string(session),[],1) + "#" + reshape(string(seriesKey),[],1),S.Keys);
            sw(tf) = S.Sweeps(loc(tf));
        end

        function [bad,txt] = sweepsDiffer(obj)
            % Do the plotted colour groups' median clean sweeps differ by
            % more than SweepTolerance?
            bad = false;  txt = "";
            T = obj.familyThresholds();
            if height(T) == 0, return; end
            sw = obj.seriesSweeps(string(T.Session),string(T.Key));
            U = table(string(T.Subject),string(T.Timepoint),double(T.TimepointOrder), ...
                string(T.Group),string(T.Session),'VariableNames', ...
                {'Subject','Timepoint','TimepointOrder','Group','Session'});
            [ck,gl] = obj.colourKeys(U);
            med = NaN(numel(gl),1);
            for k = 1:numel(gl)
                v = sw(ck == gl(k) & isfinite(sw));
                if ~isempty(v), med(k) = median(v); end
            end
            ok = isfinite(med) & med > 0;
            if nnz(ok) < 2, return; end
            if max(med(ok))/min(med(ok)) - 1 > obj.SweepTolerance
                bad = true;
                parts = gl(ok) + " " + compose("%g",med(ok));
                txt = "Median clean sweeps differ by more than 20% between the plotted groups (" + ...
                    strjoin(parts,", ") + ").";
            end
        end

        function onBannerAction(obj)
            if isempty(obj.BannerFcn), return; end
            f = obj.BannerFcn;
            f();
        end

        function chooseDuplicatePolicy(obj)
            % The banner's Choose…: the three policies, each explained.
            m = obj.Model;
            Dp = obj.Data.A.Duplicates;
            lines = strings(0,1);
            for i = 1:min(5,height(Dp))
                [~,ser] = mabr.ui.analysis.StudyView.seriesValue(Dp.SeriesKey(i),obj.familyParams());
                lines(end+1) = "• " + Dp.Subject(i) + " · " + Dp.Timepoint(i) + " · " + ser + ": " + ...
                    numel(split(Dp.Keys(i),"|")) + " sessions"; %#ok<AGROW>
            end
            if height(Dp) > 5, lines(end+1) = "• … and " + (height(Dp) - 5) + " more"; end
            msg = "Two or more study sessions measured the same series of one subject at one " + ...
                "timepoint:" + newline + strjoin(lines,newline) + newline + newline + ...
                "Most sweeps: the session with the most clean sweeps (ties: the later). " + ...
                "Latest: the later session. Mean of sessions: both, averaged.";
            cur = obj.PolicyItems(obj.PolicyCodes == string(m.Project.DuplicatePolicy));
            c = m.ConfirmFcn(msg,"Duplicated series",[obj.PolicyItems,"Cancel"],cur);
            k = find(obj.PolicyItems == string(c),1);
            if isempty(k), return; end
            if obj.PolicyCodes(k) ~= string(m.Project.DuplicatePolicy)
                m.setDuplicatePolicy(obj.PolicyCodes(k));
            end
        end

        % ---- points: click, readout, open -----------------------------
        function onAxesClick(obj,a)
            % An axes' ButtonDownFcn: the point nearest the click (a
            % double-click, SelectionType 'open', also opens it).
            try
                cp = a.CurrentPoint(1,1:2);
                fig = ancestor(a,'figure');
                open = strcmp(fig.SelectionType,'open');
            catch
                return
            end
            obj.pointAt(a,cp(1),cp(2),open);
        end

        function txt = pointAt(obj,a,x0,y0,open)
            % The point of axes A nearest (x0,y0) in data units, judged in
            % normalized axes distance (log axes in log space); none farther
            % than ClickRadius. "" when nothing is near.
            txt = "";
            ud = a.UserData;
            if ~isstruct(ud) || ~isfield(ud,'Plot'), return; end
            if ud.Plot == "thresholds"
                P = obj.ThrPoints;
                if height(P) == 0, return; end
                x = P.XPlot;  y = P.Plotted;
            elseif ud.Plot == "growth"
                P = obj.GrowthPoints;
                if height(P) == 0, return; end
                x = P.X;  y = P.Y;
            else
                return
            end
            cand = find(P.Tile == ud.Tile & isfinite(x) & isfinite(y));
            if isempty(cand), return; end
            nx = obj.normAxis(a,'X',x(cand)) - obj.normAxis(a,'X',x0);
            ny = obj.normAxis(a,'Y',y(cand)) - obj.normAxis(a,'Y',y0);
            [dmin,i] = min(hypot(nx,ny));
            if dmin > obj.ClickRadius, return; end
            txt = obj.selectPoint(ud.Plot,cand(i),open);
        end

        function txt = selectPoint(obj,plot,k,open)
            % Readout (and highlight) of point k; open on a double-click.
            if plot == "thresholds", P = obj.ThrPoints; else, P = obj.GrowthPoints; end
            if k > height(P)
                error('mabr:ui:StudyView:noPoint','There is no point %d (the plot has %d).',k,height(P));
            end
            r = P(k,:);
            if plot == "thresholds"
                txt = obj.thresholdText(r);
                lab = obj.Handles.ThrReadout;
                x = r.XPlot;  y = r.Plotted;
                panel = obj.Handles.ThrPanel;
            else
                txt = obj.growthText(r);
                lab = obj.Handles.GrowthReadout;
                x = r.X;  y = r.Y;
                panel = obj.Handles.GrowthPanel;
            end
            obj.Readout = txt;
            obj.Selected = struct('Plot',plot,'Row',k);
            obj.put("readout_" + plot,lab,'Text',char(txt));
            % the highlight ring
            try
                delete(findall(panel,'Tag','AnalysisStudySelected'));
                ax = findall(panel,'Type','axes');
                for a = reshape(ax,1,[])
                    if isstruct(a.UserData) && a.UserData.Tile == r.Tile
                        line(a,x,y,'LineStyle','none','Marker','s','MarkerSize',13, ...
                            'MarkerEdgeColor',mabr.ui.analysis.Style.Accent,'LineWidth',1.5, ...
                            'Tag','AnalysisStudySelected','HitTest','off','HandleVisibility','off');
                    end
                end
            catch
            end
            if open, obj.openPoint(r); end
        end

        function openPoint(obj,r)
            % The session (the first, when several were averaged) on that
            % series, in the Series tab.
            key = split(string(r.Sessions),"|");
            key = key(1);
            obj.Model.openSession(key,SeriesKey=string(r.SeriesKey));
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.activateTab("Series");
            end
        end

        function txt = thresholdText(obj,r)
            % "SUBJ-ID-1254 · Baseline · 8 kHz · 35 dB, manual, reviewed".
            parts = [r.Subject, mabr.ui.analysis.StudyView.timepointName(r.Timepoint), r.Series];
            if obj.referenceCode() ~= "none"
                v = string(sprintf('%+.1f dB re %s',r.Plotted,r.RefTimepoint)) + ...
                    " (" + r.RefText + " → " + r.Text + ")";
            else
                v = r.Text + " dB";
                if r.Kind == "noresponse"
                    v = v + " (plotted at " + sprintf('%g',r.Value) + ")";
                elseif r.Kind == "allrespond"
                    v = v + " (plotted at " + sprintf('%g',r.Value) + ")";
                end
            end
            words = [mabr.ui.analysis.StudyView.decisionWord(r.Decision), ...
                obj.pick(r.Reviewed,"reviewed","not reviewed")];
            if contains(r.Sessions,"|"), words(end+1) = "mean of " + numel(split(r.Sessions,"|")) + " sessions"; end
            txt = strjoin(parts," · ") + " · " + v + ", " + strjoin(words,", ");
        end

        function txt = growthText(obj,r)
            unit = "µV";
            meas = string(obj.ViewLook.Measure);
            if any(meas == ["latency","ipl-I-III","ipl-I-V"]), unit = "ms"; end
            if string(obj.ViewLook.YMode) == "percent", unit = "%"; end
            txt = r.Subject + " · " + mabr.ui.analysis.StudyView.timepointName(r.Timepoint) + ...
                " · " + obj.Choice.At + " · " + ...
                sprintf('%g dB',r.Level) + " · " + sprintf('%.3g',r.Y) + " " + unit;
            if contains(r.Sessions,"|"), txt = txt + ", mean of " + numel(split(r.Sessions,"|")) + " sessions"; end
        end

        % ---- helpers over the data -----------------------------------------
        function fam = familyCode(obj)
            fam = "";
            try
                fam = string(obj.Handles.Family.Value);
            catch
            end
            F = obj.Data.Families;
            if height(F) > 0 && ~any(F.Code == fam), fam = F.Code(1); end
        end

        function [T,info] = familyThresholds(obj)
            % The used Thresholds rows of the family, those in the majority's
            % level unit (the others are left out and counted). Once per
            % render pass and family.
            code = obj.familyCode();
            if isfield(obj.Pass,'FamT') && obj.Pass.FamT{1} == code
                [T,info] = obj.Pass.FamT{2:3};
                return
            end
            [T,info] = obj.familyThresholdsNow(code);
            obj.Pass.FamT = {code,T,info};
        end

        function [T,info] = familyThresholdsNow(obj,code)
            info = struct('Unit',"",'Other',strings(1,0),'LeftOut',strings(0,1));
            A = obj.Data.A;
            T = A.Thresholds;
            if height(T) == 0, return; end
            [stim,acq] = mabr.ui.analysis.StudyView.splitFamily(code);
            r = logical(T.UsedInStudy) & string(T.Stimulus) == stim;
            if acq ~= "" && ismember('AcqMode',T.Properties.VariableNames)
                r = r & string(T.AcqMode) == acq;
            end
            T = T(r,:);
            if height(T) == 0, return; end
            [tf,loc] = ismember(string(T.Session),string(A.Sessions.Session));
            lu = strings(height(T),1);
            lu(tf) = string(A.Sessions.LevelUnit(loc(tf)));
            maj = mabr.ui.analysis.StudyView.mostCommon(lu);
            keep = lu == maj;
            info.Unit = maj;
            info.Other = reshape(unique(lu(~keep)),1,[]);
            info.LeftOut = unique(string(T.Session(~keep)));
            T = T(keep,:);
            % (the reference "First session" orders by it after the timepoint)
            T.StartTime = mabr.ui.analysis.StudyView.startTimes(A.Sessions,T.Session);
        end

        function P = familyPeaks(obj)
            % The used Peaks rows of the family, with SeriesKeyShort (the
            % series' name within the family: "4 kHz").
            P = table();
            if isempty(obj.Data), return; end
            A = obj.Data.A;
            P = A.Peaks;
            if height(P) == 0 || ~ismember('UsedInStudy',P.Properties.VariableNames), P = table(); return; end
            [stim,acq] = mabr.ui.analysis.StudyView.splitFamily(obj.familyCode());
            r = logical(P.UsedInStudy) & string(P.Stimulus) == stim;
            if acq ~= "" && ismember('AcqMode',P.Properties.VariableNames)
                r = r & string(P.AcqMode) == acq;
            end
            P = P(r,:);
            params = obj.familyParams();
            sk = string(P.SeriesKey);
            [u,~,j] = unique(sk);
            nm = strings(numel(u),1);
            for i = 1:numel(u)
                [~,nm(i)] = mabr.ui.analysis.StudyView.seriesValue(u(i),params);
            end
            P.SeriesKeyShort = nm(j);
        end

        function params = familyParams(obj)
            % The family's group parameters: the names in its series keys
            % besides Stimulus and AcqMode, in key order.
            params = strings(1,0);
            if isempty(obj.Data), return; end
            T = obj.Data.A.Thresholds;
            if height(T) == 0, return; end
            [stim,acq] = mabr.ui.analysis.StudyView.splitFamily(obj.familyCode());
            k = string(T.Key);
            r = mabr.ui.analysis.StudyView.keyField2(k,"Stimulus") == stim;
            if acq ~= "", r = r & mabr.ui.analysis.StudyView.keyField2(k,"AcqMode") == acq; end
            for key = reshape(unique(k(r),'stable'),1,[])
                parts = split(key,"|");
                for p = reshape(parts,1,[])
                    nm = extractBefore(p,"=");
                    if ismissing(nm) || any(nm == ["Stimulus","AcqMode"]) || any(params == nm), continue; end
                    params(end+1) = nm; %#ok<AGROW>
                end
            end
        end

        function [codes,items] = familySeries(obj)
            % The family's series, by parameter value ("4 kHz", "16 kHz").
            codes = strings(1,0);  items = codes;
            if isempty(obj.Data), return; end
            T = obj.familyThresholds();
            if height(T) == 0, return; end
            params = obj.familyParams();
            sk = unique(string(T.Key));
            x = NaN(numel(sk),1);  nm = strings(numel(sk),1);
            for i = 1:numel(sk)
                [x(i),nm(i)] = mabr.ui.analysis.StudyView.seriesValue(sk(i),params);
            end
            [~,o] = sortrows([x (1:numel(x))']);
            nm = nm(o);
            codes = reshape(unique(nm,'stable'),1,[]);
            items = codes;
        end

        function tps = studyTimepoints(obj)
            % The timepoints of the study's sessions, in Timepoint order.
            V = obj.Data.V;
            used = unique(V.Timepoint(V.InStudy & V.SubjectInStudy & V.Timepoint ~= ""));
            lv = obj.Data.TpNames;
            tps = lv(ismember(lower(lv),lower(used)));
            rest = used(~ismember(lower(used),lower(lv)));
            tps = [reshape(tps,1,[]),reshape(rest,1,[])];
        end

        function ref = referenceCode(obj)
            ref = "none";
            try
                ref = string(obj.Handles.Reference.Value);
            catch
            end
        end

        function o = timepointOrderOf(obj,P)
            o = NaN(height(P),1);
            if ismember('TimepointOrder',P.Properties.VariableNames)
                o = double(P.TimepointOrder);
                return
            end
            lv = obj.Data.TpNames;
            [tf,loc] = ismember(lower(string(P.Timepoint)),lower(lv));
            o(tf) = loc(tf);
        end

        function used = usedSeries(obj,sess,sk)
            T = obj.Data.A.Thresholds;
            used = false(numel(sess),1);
            if height(T) == 0, return; end
            tk = string(T.Session) + "#" + string(T.Key);
            [tf,loc] = ismember(sess + "#" + sk,tk);
            u = logical(T.UsedInStudy);
            used(tf) = u(loc(tf));
        end

        function lp = levelParamOf(~,T,sess)
            % Each session's level parameter (Thresholds.LevelParam).
            lp = repmat("Level",numel(sess),1);
            if height(T) == 0 || ~ismember('LevelParam',T.Properties.VariableNames), return; end
            [tf,loc] = ismember(sess,string(T.Session));
            v = string(T.LevelParam);
            lp(tf) = v(loc(tf));
            lp(lp == "" | ismissing(lp)) = "Level";
        end

        function [ck,labels] = colourKeys(obj,P)
            % Each row's colour group (ColorBy) and the groups in order.
            n = height(P);
            cb = string(obj.ViewLook.ColorBy);
            grp = string(P.Group);  grp(grp == "" | ismissing(grp)) = "(no group)";
            tp = mabr.ui.analysis.StudyView.timepointName(P.Timepoint);
            switch cb
                case "group",           ck = grp;
                case "group-timepoint", ck = grp + " · " + tp;
                case "subject",         ck = string(P.Subject);
                case "session"
                    ck = strings(n,1);
                    V = obj.Data.V;
                    s = string(P.Session);
                    for i = 1:n
                        r = find(string(V.Key) == s(i),1);
                        ck(i) = s(i);
                        if ~isempty(r)
                            ck(i) = V.Subject(r) + " " + ...
                                mabr.ui.analysis.StudyView.shortName(V.Name(r),V.Subject(r));
                        end
                    end
                otherwise,              ck = tp;
            end
            labels = obj.groupOrderOf(ck,P);
        end

        function labels = groupOrder(obj,W)
            labels = obj.groupOrderOf(string(W.Color),W);
        end

        function labels = groupOrderOf(obj,ck,P)
            % Timepoints in Timepoint order; everything else naturally.
            u = unique(ck);
            if isempty(u), labels = strings(0,1); return; end
            cb = string(obj.ViewLook.ColorBy);
            if cb == "timepoint" || cb == "group-timepoint"
                o = NaN(numel(u),1);
                tpo = obj.timepointOrderOf(P);
                for i = 1:numel(u)
                    v = tpo(ck == u(i));
                    v = v(isfinite(v));
                    if ~isempty(v), o(i) = min(v); end
                end
                o(isnan(o)) = Inf;
                gRank = zeros(numel(u),1);
                if cb == "group-timepoint"
                    % group first (naturally), then the timepoints in order
                    gname = extractBefore(u + " · "," · ");
                    sg = mabr.analysis.Stats.naturalSort(unique(gname));
                    [~,gRank] = ismember(gname,sg);
                end
                [~,ix] = sortrows([gRank o (1:numel(u))']);
                labels = u(ix);
            else
                labels = mabr.analysis.Stats.naturalSort(u);
            end
            labels = reshape(labels,[],1);
        end

        function keys = tileKeys(obj,P,byTime)
            n = height(P);
            if string(obj.ViewLook.Layout) == "subject"
                keys = string(P.Subject);
            elseif byTime && numel(unique(P.Series)) > 1
                keys = string(P.Series);
            else
                keys = repmat("",n,1);
            end
        end

        function tiles = tileOrder(~,P)
            u = unique(string(P.Tile),'stable');
            if ismember('X',P.Properties.VariableNames) && all(u ~= "") && ...
                    ismember('Series',P.Properties.VariableNames) && all(ismember(u,string(P.Series)))
                % series tiles in parameter order
                x = NaN(numel(u),1);
                for i = 1:numel(u)
                    v = P.X(string(P.Series) == u(i));
                    if ~isempty(v), x(i) = v(1); end
                end
                [~,o] = sortrows([x (1:numel(u))']);
                tiles = u(o);
            else
                tiles = mabr.analysis.Stats.naturalSort(u);
            end
            tiles = reshape(tiles,[],1);
        end

        function keys = staleKeys(~,V)
            % Study sessions that are not up to date (Test Mode left alone).
            r = V.InStudy & V.SubjectInStudy & V.Status ~= "current" & V.TestMode ~= "all";
            keys = reshape(string(V.Key(r)),[],1);
        end

        function [free,level,type] = freeColumns(obj)
            % The project's own (non-built-in) label columns.
            free = strings(1,0);  level = free;  type = free;
            try
                C = obj.Model.Project.Columns;
                r = ~C.Builtin;
                free  = reshape(string(C.Name(r)),1,[]);
                level = reshape(string(C.Level(r)),1,[]);
                type  = reshape(string(C.Type(r)),1,[]);
            catch
            end
        end

        function s = freeValue(obj,P,row,name,level,type)
            % A free column's value for one session row: read from the
            % project itself (Model.projectView may predate the column).
            v = [];
            try
                if level == "subject"
                    r = find(P.Subjects.Subject == row.Subject,1);
                    if ~isempty(r), v = P.Subjects.(name)(r); end
                else
                    r = find(P.Sessions.Key == row.Key,1);
                    if ~isempty(r), v = P.Sessions.(name)(r); end
                end
            catch
            end
            s = obj.valueText(v,type);
        end

        % ---- drawing helpers ------------------------------------------------
        function ax = tiles(obj,plot,panel,n)
            % n classic axes tiled over a plot's panel, each clickable and
            % carrying the panel's context menu. The axes of the last render
            % are reused when there were as many (hiding an axes toolbar is
            % a fifth of a second; a per-subject layout has one per animal)
            % -- emptied and put back to defaults first.
            n = max(1,n);
            key = char("Ax_" + plot);
            obj.DrawnSig.(char(plot)) = [];    % until the render ends, nothing is "drawn"
            ax = gobjects(1,0);
            if isfield(obj.Handles,key), ax = obj.Handles.(key); ax = ax(isgraphics(ax)); end
            if numel(ax) ~= n
                delete(ax);
                ax = gobjects(1,n);
                cm = obj.plotMenu(plot,panel);
                for k = 1:n
                    a = axes(panel,'Units','normalized','Box','off','TickDir','out', ...
                        'FontSize',9,'Color',[1 1 1],'Tag','AnalysisStudyAxes','NextPlot','add');
                    mabr.ui.hideAxesToolbar(a);
                    try
                        disableDefaultInteractivity(a);
                    catch
                    end
                    % (through the host's cb, as every component callback:
                    % the keyboard goes back to the plots, an error reaches
                    % the status line rather than the command window)
                    a.ButtonDownFcn = obj.viewWrap(@(s,~) obj.onAxesClick(s));
                    try
                        a.ContextMenu = cm;
                    catch
                    end
                    ax(k) = a;
                end
                obj.Handles.(key) = ax;
            end
            nc = ceil(sqrt(n));
            nr = ceil(n/nc);
            ink = [0.15 0.15 0.15];
            for k = 1:n
                rr = ceil(k/nc);  cc = k - (rr - 1)*nc;
                w = 1/nc;  h = 1/nr;
                if n == 1
                    pos = [0.08 0.12 0.88 0.78];
                else
                    pos = [(cc - 1)*w + 0.13*w, 1 - rr*h + 0.16*h, 0.82*w, 0.66*h];
                end
                a = ax(k);
                % every child, hidden ones too (cla leaves the ceiling,
                % the bands and the highlight, which are HandleVisibility
                % off) -- but not the axes' own title and labels
                ch = allchild(a);
                keep = [a.Title; a.XLabel; a.YLabel; a.ZLabel];
                try
                    keep = [keep; a.Subtitle]; %#ok<AGROW> (one more, when the release has it)
                catch
                end
                delete(ch(~ismember(ch,keep)));
                set(a,'Position',pos,'XScale','linear','YScale','linear','XLimMode','auto', ...
                    'YLimMode','auto','XTickMode','auto','YTickMode','auto','XTickLabelMode','auto', ...
                    'YTickLabelMode','auto','XMinorTick','off','YMinorTick','off','XColor',ink, ...
                    'YColor',ink,'UserData',struct('Plot',string(plot),'Tile',""));
                title(a,'');
                xlabel(a,'');
                ylabel(a,'');
                try
                    a.Subtitle.String = '';
                catch
                end
            end
        end

        function setLegend(~,a,H,labs)
            % Point the axes' legend at H (labels LABS), or remove it when H
            % is empty. An existing legend is re-pointed rather than made
            % anew: a fifth of the cost, and a plot redraws on every change
            % of a control.
            if isempty(H)
                try
                    if ~isempty(a.Legend), delete(a.Legend); end
                catch
                end
                return
            end
            try
                legend(a,H,cellstr(labs),'Location',char(mabr.ui.analysis.StudyView.legendCorner(a,labs)), ...
                    'Interpreter','none','AutoUpdate','off','Box','off');
            catch me
                mabr.log.vprintf(2,'Study view: no legend (%s).',me.message);
            end
        end

        function s = growthLevelLabel(obj)
            % "Level (dB SPL)": the family's level unit, as the thresholds
            % plot reads it (familyThresholds: the majority's), so the two
            % plots of one family name their level axis alike.
            u = "";
            try
                [~,ui] = obj.familyThresholds();
                u = string(ui.Unit);
            catch
            end
            if isempty(u) || any(ismissing(u)) || u == "" || u == "mixed", u = "dB"; end
            s = "Level (" + u + ")";
        end

        function placeLegends(obj,ax,tH,tL,tG,glabels,oneLegend,names)
            % Each panel's own legend -- or, with oneLegend (one panel per
            % subject; a panel per series), ONE legend on the first panel
            % naming every colour group drawn in ANY panel: a subject seen
            % at fewer timepoints than another would otherwise leave
            % colours on the page no legend names. A group the first panel
            % lacks is keyed by a copy of its key from the panel that has
            % it, emptied of data (so Copy data passes it by).
            %   tH{t}, tL{t}, tG{t}  panel t's legend handles, labels and
            %                        colour-group indices
            %   names                what the one legend calls each group
            %                        (default glabels)
            if nargin < 8, names = glabels; end
            n = numel(ax);
            if ~oneLegend || n == 1
                for t = 1:n, obj.setLegend(ax(t),tH{t},tL{t}); end
                return
            end
            H = reshape(tH{1},1,[]);  G = reshape(tG{1},1,[]);
            for t = 2:n
                for q = 1:numel(tG{t})
                    gi = tG{t}(q);
                    if any(G == gi), continue; end
                    try
                        k = copyobj(tH{t}(q),ax(1));
                        set(k,'XData',NaN,'YData',NaN,'Tag','AnalysisStudyLegendKey','HitTest','off');
                        H(end+1) = k; %#ok<AGROW>
                        G(end+1) = gi; %#ok<AGROW>
                    catch me
                        mabr.log.vprintf(2,'Study view: no legend key for %s (%s).',glabels(gi),me.message);
                    end
                end
                obj.setLegend(ax(t),gobjects(0),strings(0,1));
            end
            [G,o] = sort(G);
            obj.setLegend(ax(1),H(o),names(G));
        end

        function tileNote(~,ax,note)
            % The plot's note (the rule it counts by, what it left out) as
            % the first panel's subtitle. Over several panels it is broken
            % at its "; " into lines (a panel is narrow) and every other
            % panel gets as many blank lines, so the panels' titles stay
            % level.
            note = string(note);
            lines = {char(note)};
            if numel(ax) > 1 && note ~= ""
                lines = cellstr(split(note,"; "));
            end
            for k = 1:numel(ax)
                s = lines;
                if k > 1
                    if note == "", s = {''}; else, s = repmat({' '},numel(lines),1); end
                end
                if isscalar(s), s = s{1}; end
                try
                    ax(k).Subtitle.String = s;
                    ax(k).Subtitle.Color = mabr.ui.analysis.Style.Muted;
                catch
                end
            end
        end

        function x = timepointPositions(obj,tp,ord)
            % Positions along a timepoint axis: the Timepoint order where a
            % session's timepoint is in it; after those, any other (a
            % timepoint outside the order, or none: "(no timepoint)", last)
            % in natural order. A study not yet labelled still plots (NaN
            % positions would drop its points without a word).
            x = double(ord(:));
            miss = ~isfinite(x);
            if ~any(miss), return; end
            nm = string(tp(:));
            nm = nm(miss);
            nm(ismissing(nm)) = "";
            u = mabr.analysis.Stats.naturalSort(unique(nm));
            u = [u(u ~= ""); u(u == "")];
            [~,k] = ismember(nm,u);
            x(miss) = numel(obj.Data.TpNames) + k;
        end

        function cm = plotMenu(obj,plot,panel)
            % The plot's context menu (made once; it acts on the panel, so
            % it serves every axes the panel will hold): Export figure… /
            % Copy data / Copy image.
            key = char("Menu_" + plot);
            cm = [];
            if isfield(obj.Handles,key) && isvalid(obj.Handles.(key))
                cm = obj.Handles.(key);
                return
            end
            try
                fig = ancestor(panel,'figure');
                cm = uicontextmenu(fig,'Tag','AnalysisStudyPlotMenu');
                mabr.ui.analysis.FigureExport.addContextItems(cm,panel,obj.Host);
                obj.Handles.(key) = cm;
            catch me
                mabr.log.vprintf(2,'Study view: no plot menu (%s).',me.message);
            end
        end

        function emptyAxes(obj,plot,panel,msg)
            % One empty axes with a sentence in the middle.
            a = obj.tiles(plot,panel,1);
            obj.setLegend(a,gobjects(0),strings(0,1));
            a.XTick = [];  a.YTick = [];
            a.XColor = 'none';  a.YColor = 'none';
            a.UserData = struct('Plot',"none",'Tile',"");
            text(a,0.5,0.5,char(msg),'Units','normalized','HorizontalAlignment','center', ...
                'Color',mabr.ui.analysis.Style.Muted,'FontSize',11,'Tag','AnalysisStudyNoData');
        end

        function axisX(obj,a,x,byTime,params,tp)
            % A log parameter axis (Frequency) or the timepoints in order
            % (tp: each x's timepoint, naming the positions past the
            % Timepoint order -- see timepointPositions).
            if nargin < 6, tp = strings(numel(x),1); end
            tp = string(tp);
            ok = isfinite(x);
            x = x(ok);  tp = tp(ok);
            if isempty(x), return; end
            ux = unique(x);
            if byTime
                lv = obj.Data.TpNames;
                names = strings(1,numel(ux));
                for i = 1:numel(ux)
                    if ux(i) >= 1 && ux(i) <= numel(lv) && ux(i) == round(ux(i))
                        names(i) = lv(ux(i));
                    else
                        names(i) = mabr.ui.analysis.StudyView.timepointName(tp(find(x == ux(i),1)));
                    end
                end
                a.XTick = ux;
                a.XTickLabel = cellstr(names);
                a.XLim = [min(ux) - 0.5, max(ux) + 0.5];
                xlabel(a,'Timepoint');
            else
                p = params(1);
                if all(ux > 0)
                    a.XScale = 'log';
                    a.XMinorTick = 'off';
                    a.XLim = [min(ux)/1.35, max(ux)*1.35];
                else
                    pad = max(1,0.08*(max(ux) - min(ux)));
                    a.XLim = [min(ux) - pad, max(ux) + pad];
                end
                a.XTick = ux;
                a.XTickLabel = cellstr(compose("%g",ux(:)));
                xlabel(a,obj.paramAxisName(p));
            end
        end

        function axisY(~,a,y)
            y = y(isfinite(y));
            if isempty(y), return; end
            lo = min(y);  hi = max(y);
            pad = max(0.08*(hi - lo),max(1,0.05*max(abs([lo hi]))));
            if pad == 0, pad = 1; end
            a.YLim = [lo - pad, hi + pad];
        end

        function s = paramAxisName(~,p)
            u = "";
            try
                u = string(mabr.stim.StimulusSet.paramUnit(char(p)));
            catch
            end
            if u == "", s = string(p); else, s = string(p) + " (" + u + ")"; end
        end

        function v = normAxis(~,a,which,v)
            % Data to 0..1 along an axis (log axes in log space).
            lim = a.([which 'Lim']);
            if strcmp(a.([which 'Scale']),'log')
                v = (log10(max(v,realmin)) - log10(lim(1)))/(log10(lim(2)) - log10(lim(1)));
            else
                v = (v - lim(1))/(lim(2) - lim(1));
            end
        end

        % ---- small things -------------------------------------------------
        function status(obj,text,level)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus(text,level);
            else
                mabr.log.vprintf(max(1,level),'Study: %s',char(text));
            end
        end

        function s = valueText(~,v,type)
            if isempty(v), s = ""; return; end
            if type == "number" || isnumeric(v)
                v = double(v);
                if isnan(v), s = ""; else, s = string(sprintf('%g',v)); end
            else
                s = string(v);
                if ismissing(s), s = ""; end
            end
        end

        function s = numText(~,v,digits)
            if isempty(v) || ~isfinite(v), s = ''; else, s = sprintf('%.*g',digits,v); end
        end

        function [r,c,val] = editOf(~,evt)
            r = 0;  c = 0;  val = [];
            try
                r = evt.Indices(1);  c = evt.Indices(2);
                val = evt.NewData;
            catch
            end
            if ischar(val), val = string(val); end
        end

        function c = cellColumn(~,evt)
            c = 0;
            try
                if ~isempty(evt.Indices), c = evt.Indices(end,2); end
            catch
            end
        end

        function v = firstOr(~,v,codes)
            if isempty(codes), v = ""; return; end
            if ~any(codes == v), v = codes(1); end
        end

        function v = pick(~,tf,a,b)
            if tf, v = a; else, v = b; end
        end

    end

    % =====================================================================
    methods (Static, Access = private)
        function A = completeAggregate(A)
            % Every table aggregate may return, present (empty when absent).
            names = ["Sessions","Subjects","Conditions","Thresholds","Peaks","PeakMeasures", ...
                "IOSlopes","Means","Duplicates"];
            if ~isstruct(A), A = struct(); end
            for n = names
                if ~isfield(A,n) || ~istable(A.(n)), A.(n) = table(); end
            end
            if width(A.Sessions) == 0
                s = strings(0,1);
                A.Sessions = table(s,s,s,zeros(0,1),s,s,s,'VariableNames', ...
                    {'Session','Subject','Timepoint','TimepointOrder','Group','LevelUnit','SettingsHash'});
            end
            if width(A.Duplicates) == 0
                s = strings(0,1);
                A.Duplicates = table(s,s,s,s,s,'VariableNames',{'Subject','Timepoint','SeriesKey','Keys','Used'});
            end
            if height(A.Thresholds) > 0
                for c = ["Stimulus","AcqMode","Group","Timepoint","Subject","Session","Key","Decision","FinalCensored"]
                    if ismember(c,A.Thresholds.Properties.VariableNames)
                        v = string(A.Thresholds.(c));  v(ismissing(v)) = "";
                        A.Thresholds.(c) = v;
                    end
                end
            end
        end

        function loc = legendCorner(a,labs)
            % The inside corner of axes A where a legend of LABS covers the
            % fewest data, chosen once the limits are final: each corner is
            % scored by how many points of the axes' lines -- and of the
            % segments between them -- fall where the legend's box would be
            % (its size estimated from the labels' length and number, since
            % measuring a legend lays it out). Ties keep the usual order:
            % top right, top left, bottom right, bottom left. When every
            % corner covers data, the y axis grows by the legend's height
            % and it takes the top right, clear of everything.
            loc = "northeast"; %#ok<NASGU> (the answer should anything below fail)
            try
                pp = getpixelposition(a);
                W = max(pp(3),50);  H = max(pp(4),50);
                px = a.FontSize*96/72;               % the font's height, pixels
                w = min(0.9,(0.6*px*double(max(strlength(string(labs)))) + 36)/W);
                h = min(0.9,(numel(labs)*1.35*px + 8)/H);
                L = findall(a,'Type','line','-or','Type','errorbar');
                X = zeros(0,1);  Y = zeros(0,1);
                for k = 1:numel(L)
                    if ~strcmp(L(k).Visible,'on'), continue; end
                    x = double(L(k).XData(:));  y = double(L(k).YData(:));
                    if isempty(x) || numel(x) ~= numel(y), continue; end
                    x = mabr.ui.analysis.StudyView.toUnit(a,'X',x);
                    y = mabr.ui.analysis.StudyView.toUnit(a,'Y',y);
                    % the segments too: a line crossing a corner covers it
                    if numel(x) > 1
                        t = linspace(0,1,8);
                        xs = x(1:end-1) + (x(2:end) - x(1:end-1))*t;
                        ys = y(1:end-1) + (y(2:end) - y(1:end-1))*t;
                        x = [x; xs(:)]; %#ok<AGROW>
                        y = [y; ys(:)]; %#ok<AGROW>
                    end
                    ok = isfinite(x) & isfinite(y);
                    X = [X; x(ok)]; %#ok<AGROW>
                    Y = [Y; y(ok)]; %#ok<AGROW>
                end
                in = @(xl,yl) sum(X >= xl(1) & X <= xl(2) & Y >= yl(1) & Y <= yl(2));
                score = [in([1-w 1],[1-h 1]), in([0 w],[1-h 1]), in([1-w 1],[0 h]), in([0 w],[0 h])];
                names = ["northeast","northwest","southeast","southwest"];
                [best,k] = min(score);
                loc = names(k);
                if best > 0 && strcmp(a.YScale,'linear')
                    yl = a.YLim;
                    a.YLim = [yl(1), yl(2) + h/(1 - h)*diff(yl)];
                    loc = "northeast";
                end
            catch
                loc = "northeast";
            end
        end

        function v = toUnit(a,which,v)
            % Data to 0..1 along an axis (log axes in log space).
            lim = double(a.([which 'Lim']));
            if strcmp(a.([which 'Scale']),'log')
                v = (log10(max(v,realmin)) - log10(lim(1)))/(log10(lim(2)) - log10(lim(1)));
            else
                v = (v - lim(1))/(lim(2) - lim(1));
            end
        end

        function V = emptyView()
            s = strings(0,1);
            V = table(s,s,s,NaT(0,1),s,s,false(0,1),false(0,1),s,s,zeros(0,1),zeros(0,1),s,s,s,s,s,s, ...
                'VariableNames',{'Key','Name','Subject','Day','Timepoint','Group','InStudy', ...
                'SubjectInStudy','Status','StatusText','Reviewed','NumSeries','Processing', ...
                'Stimuli','Units','LevelUnit','SettingsHash','TestMode'});
        end

        function T = sessionStats(C)
            % Per session: median residual noise (V), % rejected, fewest clean sweeps.
            s = strings(0,1);
            T = table(s,zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames', ...
                {'Session','Noise','PctRejected','MinN'});
            if height(C) == 0 || ~ismember('Session',C.Properties.VariableNames), return; end
            col = @(n) mabr.ui.analysis.StudyView.column(C,n,NaN(height(C),1));
            rn = double(col("RN"));  nr = double(col("nRejected"));
            ns = double(col("nSweeps"));  nc = double(col("nClean"));
            [u,~,j] = unique(string(C.Session),'stable');
            k = numel(u);
            noise = NaN(k,1);  pr = NaN(k,1);  mn = NaN(k,1);
            for q = 1:k
                r = j == q;
                v = rn(r);  v = v(isfinite(v));
                if ~isempty(v), noise(q) = median(v); end
                a = sum(nr(r & isfinite(nr)));  b = sum(ns(r & isfinite(ns)));
                if b > 0, pr(q) = 100*a/b; end
                v = nc(r);  v = v(isfinite(v));
                if ~isempty(v), mn(q) = min(v); end
            end
            T = table(u,noise,pr,mn,'VariableNames',{'Session','Noise','PctRejected','MinN'});
        end

        function S = seriesSweepTable(C,T)
            % The median clean sweeps of every session x series, keyed
            % "<session>#<series key>". A condition's series key is its key
            % without the level pair (whichever place that pair holds), the
            % level parameter being the session's (Thresholds.LevelParam).
            S = struct('Keys',strings(0,1),'Sweeps',zeros(0,1));
            if height(C) == 0 || ~all(ismember({'Session','Key'},C.Properties.VariableNames)), return; end
            if ismember('nClean',C.Properties.VariableNames)
                v = double(C.nClean);
            elseif ismember('nSweeps',C.Properties.VariableNames)
                v = double(C.nSweeps);
            else
                return
            end
            sess = string(C.Session);
            key = string(C.Key);
            lp = repmat("Level",height(C),1);
            if height(T) > 0 && all(ismember({'Session','LevelParam'},T.Properties.VariableNames))
                [tf,loc] = ismember(sess,string(T.Session));
                p = string(T.LevelParam);
                lp(tf) = p(loc(tf));
                lp(lp == "" | ismissing(lp)) = "Level";
            end
            sk = key;
            for i = 1:numel(key)
                parts = split(key(i),"|");
                nm = extractBefore(parts,"=");
                sk(i) = strjoin(parts(ismissing(nm) | nm ~= lp(i)),"|");
            end
            [u,~,j] = unique(sess + "#" + sk);
            med = NaN(numel(u),1);
            for q = 1:numel(u)
                x = v(j == q);
                x = x(isfinite(x));
                if ~isempty(x), med(q) = median(x); end
            end
            S = struct('Keys',u,'Sweeps',med);
        end

        function F = familiesOf(T)
            % Stimulus families of the study's used series; the acquisition
            % mode joins the name when a stimulus was recorded both ways.
            s = strings(0,1);
            F = table(s,s,s,s,'VariableNames',{'Code','Label','Stimulus','AcqMode'});
            if height(T) == 0 || ~ismember('Stimulus',T.Properties.VariableNames), return; end
            used = true(height(T),1);
            if ismember('UsedInStudy',T.Properties.VariableNames), used = logical(T.UsedInStudy); end
            if ~any(used), used = true(height(T),1); end
            st = string(T.Stimulus(used));
            if ismember('AcqMode',T.Properties.VariableNames), am = string(T.AcqMode(used));
            else, am = strings(nnz(used),1); end
            am(ismissing(am)) = "";
            [us,~,j] = unique(st);
            cnt = accumarray(j,1);
            [~,o] = sort(cnt,'descend');
            for q = reshape(o,1,[])
                modes = unique(am(st == us(q)));
                modes = modes(modes ~= "");
                if numel(modes) > 1
                    for mm = reshape(modes,1,[])
                        F = [F; {us(q) + "|" + mm, us(q) + " · " + mm, us(q), mm}]; %#ok<AGROW>
                    end
                else
                    F = [F; {us(q), us(q), us(q), ""}]; %#ok<AGROW>
                end
            end
        end

        function [stim,acq] = splitFamily(code)
            parts = split(string(code),"|");
            stim = parts(1);
            acq = "";
            if numel(parts) > 1, acq = parts(2); end
        end

        function v = keyField2(keys,name)
            % keyField over a string array.
            v = strings(size(keys));
            for i = 1:numel(keys)
                v(i) = mabr.ui.analysis.StudyView.keyField(keys(i),name);
            end
        end

        function [mu,lo,hi] = curveSummary(Y,useMedian)
            % A summary of curves across subjects, one per column of Y
            % [nt x ns]: the mean ± SEM (no band below two subjects), or the
            % median and its interquartile range.
            if useMedian
                Q = mabr.analysis.Stats.percentileCols(Y.',[0.25 0.5 0.75]);
                mu = Q(2,:).';  lo = Q(1,:).';  hi = Q(3,:).';
            else
                mu = mean(Y,2,'omitnan');
                nn = sum(isfinite(Y),2);
                se = std(Y,0,2,'omitnan')./sqrt(max(nn,1));
                se(nn < 2) = NaN;
                lo = mu - se;  hi = mu + se;
            end
        end

        function [Y,P] = interpeak(P,w1,w2)
            % lat(w2) - lat(w1) per condition (the offset cancels); P is
            % reduced to one row per condition (the first wave's).
            key = string(P.Session) + "#" + string(P.Key);
            wave = string(P.Wave);
            lat = double(P.PeakLatency);
            [u,~,j] = unique(key,'stable');
            Y = NaN(numel(u),1);
            first = zeros(numel(u),1);
            for q = 1:numel(u)
                r = find(j == q);
                a = r(wave(r) == w1);  b = r(wave(r) == w2);
                first(q) = r(1);
                if ~isempty(a) && ~isempty(b), Y(q) = lat(b(1)) - lat(a(1)); end
            end
            P = P(first,:);
        end

        function U = emptyUnits()
            s = strings(0,1);  d = zeros(0,1);
            U = table(s,s,d,s,s,s,s,d,s,d,s,false(0,1),d,false(0,1),s,true(0,1),s,s,d,s,d, ...
                'VariableNames',{'Subject','Timepoint','TimepointOrder','Group','Session', ...
                'Sessions','SeriesKey','X','Series','Value','Kind','Censored','Plotted','Hollow', ...
                'Decision','Reviewed','Text','RefText','Ceiling','RefTimepoint','StartTime'});
        end

        function k = firstOf(order,startTime)
            % Index of the first session: lowest Timepoint order, the start
            % time (posix s) breaking ties and ranking sessions with no
            % order; [] when there is nothing to choose from.
            k = zeros(0,1);
            if isempty(order), return; end
            o = double(order(:));  o(~isfinite(o)) = Inf;
            s = double(startTime(:));  s(~isfinite(s)) = Inf;
            [~,ix] = sortrows([o s (1:numel(o))']);
            k = ix(1);
        end

        function t = startTimes(Sess,keys)
            % Each session key's start (posix s; NaN unknown), from the
            % aggregate's Sessions table.
            keys = reshape(string(keys),[],1);
            t = NaN(numel(keys),1);
            if height(Sess) == 0 || ~all(ismember({'Session','Start'},Sess.Properties.VariableNames))
                return
            end
            try
                st = posixtime(Sess.Start);
            catch
                return
            end
            [tf,loc] = ismember(keys,string(Sess.Session));
            t(tf) = st(loc(tf));
        end

        function G = emptyGrowth()
            s = strings(0,1);  d = zeros(0,1);
            G = table(s,s,d,s,s,s,s,d,d,d,d,s,'VariableNames',{'Subject','Timepoint', ...
                'TimepointOrder','Group','Session','Sessions','SeriesKey','Level','X','Y','XBin','Line'});
        end

        function v = column(T,name,default)
            % T.(name), or DEFAULT when the table lacks the column.
            if ismember(char(name),T.Properties.VariableNames)
                v = T.(char(name));
                if isstring(v) || iscellstr(v) || ischar(v)
                    v = string(v);  v(ismissing(v)) = "";
                end
            else
                v = default;
            end
        end

        function s = levelSigns(T,dirn)
            % +1 where a row's levels get louder as they grow (dB SPL), -1
            % where they get quieter (attenuation): T's LevelDirection column
            % when it has one, else DIRN (the settings' LevelDirection), and
            % "auto" a level parameter named like Attenuation (Session's
            % rule) -- per row, since sessions may differ.
            n = height(T);
            s = ones(n,1);
            if n == 0, return; end
            d = mabr.ui.analysis.StudyView.column(T,"LevelDirection",repmat(string(dirn),n,1));
            d = lower(string(d));
            d(d == "") = lower(string(dirn));
            lp = lower(mabr.ui.analysis.StudyView.column(T,"LevelParam",strings(n,1)));
            s(d == "descending") = -1;
            s(d == "auto" & contains(lp,"attenuation")) = -1;
        end

        function m = mostCommon(x)
            % The most frequent value of a string array ("" when empty;
            % a tie goes to the value that sorts first).
            m = "";
            x = reshape(string(x),[],1);
            x = x(~ismissing(x));
            if isempty(x), return; end
            [u,~,j] = unique(x);
            cnt = accumarray(j,1);
            [~,k] = max(cnt);
            m = u(k);
        end

        function s = shortName(name,subject)
            % A session's name without its subject: "SUBJ-ID-1254_261001T140845"
            % -> "140845" (the time of day), "SUBJ-ID-959_Baseline" -> "Baseline".
            s = string(name);
            subject = string(subject);
            rest = s;
            if subject ~= "" && ~ismissing(subject)
                rest = erase(rest,subject);
            end
            rest = regexprep(rest,'^[_\-\s]+|[_\-\s]+$','');
            tok = regexp(rest,'^\d{6}T(\d{6})$','tokens','once');
            if ~isempty(tok)
                rest = string(tok{1});
            end
            if rest ~= "", s = rest; end
        end

        function s = timepointName(tp)
            % A timepoint as the plots name it: "(no timepoint)" for none.
            s = string(tp);
            s(ismissing(s) | strtrim(s) == "") = "(no timepoint)";
        end

        function [dur,npres] = sessionExtent(V)
            % Per session of V: its duration in seconds -- first start to
            % last end of its files (an intermixed run's end is estimated by
            % the Catalog), a pool's the sum of its members' (the span
            % between their days is not recording) -- and the number of
            % stimuli presented (sweeps in the files a Session includes).
            % NaN where the catalog could not say.
            n = height(V);
            dur = NaN(n,1);  npres = NaN(n,1);
            vn = V.Properties.VariableNames;
            if all(ismember({'Start','Stop'},vn))
                dur = reshape(seconds(V.Stop - V.Start),[],1);
                if all(ismember({'IsPool','Members','Key'},vn))
                    for i = reshape(find(V.IsPool),1,[])
                        [tf,loc] = ismember(split(string(V.Members(i)),"|"),string(V.Key));
                        d = dur(loc(tf));
                        dur(i) = NaN;
                        if any(~isnan(d)), dur(i) = sum(d,'omitnan'); end
                    end
                end
            end
            if ismember('NumSweeps',vn), npres = reshape(double(V.NumSweeps),[],1); end
        end

        function s = durationText(sec)
            % "1:23:45" ('' when unknown).
            if isnan(sec), s = ''; return; end
            sec = round(max(sec,0));
            s = sprintf('%d:%02d:%02d',floor(sec/3600),floor(mod(sec,3600)/60),mod(sec,60));
        end

        function c = cellText(v)
            % A table cell's text: '' for a missing or empty value (char of
            % a missing string throws, and a label column can hold one).
            v = string(v);
            if isempty(v) || ismissing(v(1)), c = ''; else, c = char(v(1)); end
        end

        function w = decisionWord(d)
            switch string(d)
                case "accepted",   w = "accepted";
                case "manual",     w = "manual";
                case "noresponse", w = "no response";
                case "allrespond", w = "all respond";
                case "excluded",   w = "excluded";
                otherwise,         w = "fit";
            end
        end
    end
end
