classdef SettingsDialog < handle
% mabr.ui.analysis.SettingsDialog  Every analysis setting of a project, in one window.
%
%   The analysis app's Settings dialog: a window over one
%   mabr.analysis.Settings, with a tab per part of the analysis (Signal,
%   Artifacts, Detection & measures, Thresholds, Peaks, Profiles). Every
%   control edits a copy (Current); nothing reaches the project until Apply
%   or OK hands it to the applyFcn the owner supplied -- the analysis app's
%   is Model.setSettings(s,Persist=true), which stores the settings in the
%   project and in the user's defaults and says which steps are now out of
%   date.
%
%       d = mabr.ui.analysis.SettingsDialog(model.Settings,@(s) model.setSettings(s), ...
%               Model=model,Tab="Thresholds");
%       d = mabr.ui.analysis.SettingsDialog(s,fcn,Visible="off");   % a test
%       h = findall(d.Figure,'Tag','AnalysisSettingsNumPermutations');
%       h.Value = 2000; h.ValueChangedFcn(h,[]);                      % as typed
%       d.apply();  d.read()                                          % Settings
%       s = mabr.ui.analysis.SettingsDialog.run(s,fcn);               % wait (interactive)
%
%   A value the Settings class refuses (a wrong type, a negative count) is
%   kept as a problem of its own rather than thrown at the user; a value
%   that is the right type but makes no sense with the others is what
%   Settings.problems() reports. Both are listed under the tabs
%   (AnalysisSettingsProblems), and Apply and OK stay disabled until the
%   list is empty -- and while the Model is busy (an analysis, a batch, an
%   export), since the settings cannot change under a running job. Beside
%   them a line says what Apply would change and how much of the analysis
%   it makes out of date ("2 changes (NumPermutations, Alpha) -- re-runs the
%   permutation test (slow)"); after Apply it carries the applyFcn's report.
%
%   THE SIGNAL TAB also draws the FIR response the filter settings imply
%   (as applied, i.e. squared under filtfilt) with its realized -6 dB
%   corners, and holds the latency reference: the sound conduction delay
%   (None | Delay (ms) | Speaker distance (cm) at a speed of sound, with a
%   live readout such as "= 0.29 ms"; the fields a mode does not read are
%   greyed) and the system TimeOffset, beside the onset bias of the open
%   session's files -- (1 - 1/df)/Fs of the ADC, about +0.078 ms at 192/12
%   kHz, the amount SweepOnsets' rounding puts time zero early -- with a
%   [Use it] button that copies it into TimeOffset.
%
%   The dialog follows its Model while it is open: settings changed
%   elsewhere (a profile from the menu, another root opened) become what
%   Apply is measured against, and are shown when no edit is pending -- an
%   edit pending is never overwritten; a session opened brings its onset
%   bias, rate and parameters. Tabs are built the first time they are shown
%   (showTab, or a click), since most visits touch one.
%
%   Options (name-value): Visible "on"|"off"; Tab "Signal"|"Artifacts"|
%   "Detection"|"Thresholds"|"Peaks"|"Profiles" (the tab shown first);
%   Title (the window name, e.g. "Project settings — <root>"); Model (a
%   mabr.ui.analysis.Model: the open session's parameters, sample rate and
%   onset bias, and the busy state; when it is not given, the Model the
%   applyFcn closes over -- the analysis app's -- is used if there is one);
%   PickFileFcn (path = fcn(filter,title,mode,default), "" = cancelled; [] =
%   the Model's, else uigetfile/uiputfile) for the profile Load... and
%   Save As... buttons.
%
%   Tags: AnalysisSettings<Field> for every scalar setting (e.g.
%   AnalysisSettingsNumPermutations), <Field>Start / <Field>End for windows
%   (AnalysisSettingsWindowStart), AnalysisSettingsHighPassOn/Stop/Pass,
%   AnalysisSettingsLowPassOn/Pass/Stop, AnalysisSettingsSplitHalfWindowAuto,
%   AnalysisSettingsWaves (+ WaveAdd, WaveRemove), AnalysisSettingsOnsetBias
%   (+ UseOnsetBias), AnalysisSettingsConductionReadout, AnalysisSettingsFilterAxes
%   (+ FilterCorners), the Profiles tab's AnalysisSettingsProfileList (+
%   ProfileUse, Matches, Describe), and AnalysisSettingsApply, ...OK,
%   ...Cancel, ...Defaults, ...Load, ...SaveAs, ...Problems, ...Changes.
%
%   The window's position is remembered (mabr.ui.WindowPos,
%   "OfflineAnalysisSettings") on OK, Cancel, closing and delete. This class
%   writes no preference of its own: the applyFcn decides whether the
%   settings become the user's defaults.
%
%   See also mabr.analysis.Settings, mabr.ui.analysis.Model, mabr.ui.AnalysisApp
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPosition = [200 120 860 640]
        MinSize  = [760 560]
        TabNames = ["Signal","Artifacts","Detection","Thresholds","Peaks","Profiles"]
    end

    properties (SetAccess = private)
        Figure = []
        Model = []                     % mabr.ui.analysis.Model, or []
        Current                        % mabr.analysis.Settings as edited
        Baseline                       % the Settings in force (opened with, or last applied)
        Value = []                     % the Settings OK closed with; [] after cancel()
        Done (1,1) logical = false     % ok() or cancel() has happened
        LastReport (1,1) string = ""   % what the last Apply reported
        ApplyCount (1,1) double = 0    % how many times the applyFcn ran
        OnsetBias (1,:) double = []    % ms, one per sample-rate pair of the open session's files
        SampleRate (1,1) double = 12000   % Hz the filter response is drawn at
    end

    properties (Access = private)
        ApplyFcn = []
        PickFileFcn = []
        Ctrl = struct()
        Setters = struct('Prop',{},'Fcn',{})   % settings -> controls, per property
        FieldErrors = struct()         % property -> message of a value the class refused
        Listeners = event.listener.empty
        Written = struct()
        FilterKey (1,1) string = ""
        WaveSel = zeros(1,0)           % rows of the waves table last selected
        Params (1,:) string = strings(1,0)
        TabBuilt = struct()            % tab name -> its controls exist (built on first show)
        FieldLabels = struct()         % property -> the label the dialog shows for it
    end

    methods
        function obj = SettingsDialog(settings,applyFcn,opts)
            % SettingsDialog(settings,applyFcn,Visible=,Tab=,Title=,Model=,PickFileFcn=)
            %   settings  mabr.analysis.Settings (or its struct; [] = defaults)
            %   applyFcn  txt = applyFcn(s) for Apply and OK ([] = none; the
            %             returned text, when there is one, is shown)
            arguments
                settings = []
                applyFcn = []
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.Tab (1,1) string = "Signal"
                opts.Title (1,1) string = "Analysis settings"
                opts.Model = []
                opts.PickFileFcn = []
            end
            if isempty(settings)
                settings = mabr.analysis.Settings();
            elseif isstruct(settings)
                settings = mabr.analysis.Settings.fromStruct(settings);
            end
            if ~isa(settings,'mabr.analysis.Settings')
                error('mabr:ui:SettingsDialog:badSettings', ...
                    'SettingsDialog takes a mabr.analysis.Settings (or its struct).');
            end
            obj.Current  = settings;
            obj.Baseline = settings;
            obj.ApplyFcn = applyFcn;
            obj.Model = opts.Model;
            if isempty(obj.Model)
                obj.Model = mabr.ui.analysis.SettingsDialog.modelOf(applyFcn);
            end
            obj.PickFileFcn = opts.PickFileFcn;
            if isempty(obj.PickFileFcn) && ~isempty(obj.Model)
                try
                    obj.PickFileFcn = obj.Model.PickFileFcn;
                catch
                end
            end
            obj.readSession();

            f = uifigure('Name',char(opts.Title),'Tag','MABR_OFFLINE_SETTINGS', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','on');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisSettings',obj.DefaultPosition,obj.MinSize);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;
            obj.build();
            obj.showTab(opts.Tab);         % builds that tab (the others on first show)
            obj.write(settings);
            obj.Baseline = obj.Current;

            if ~isempty(obj.Model)
                % Busy: Apply/OK off while a job runs. The project's settings
                % changed elsewhere (a profile from the menu, another root):
                % the dialog measures its edits against them, and shows them
                % when it holds no edit of its own. Another session: its
                % onset bias and parameters.
                try
                    obj.Listeners = [ ...
                        event.listener(obj.Model,'BusyChanged',@(~,~) obj.refreshStatus()), ...
                        event.listener(obj.Model,'SettingsChanged',@(~,~) obj.onModelSettings()), ...
                        event.listener(obj.Model,'SessionChanged',@(~,~) obj.onModelSession())];
                catch
                end
            end
            obj.refreshStatus();
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        % ---- the common dialog API ----------------------------------------
        function s = read(obj)
            % The settings as the controls hold them (mabr.analysis.Settings).
            s = obj.Current;
        end

        function write(obj,s)
            % Put settings S (a Settings or its struct) into every control.
            if isstruct(s), s = mabr.analysis.Settings.fromStruct(s); end
            obj.Current = s;
            obj.FieldErrors = struct();
            obj.LastReport = "";
            if ~obj.isopen(), return; end
            for k = 1:numel(obj.Setters)
                try
                    obj.Setters(k).Fcn(s);
                catch me
                    mabr.log.vprintf(2,'SettingsDialog: %s not shown (%s).',obj.Setters(k).Prop,me.message);
                end
            end
            obj.syncDependents("all");
            obj.refreshStatus();
        end

        function ok = apply(obj)
            % Hand the edited settings to the applyFcn; the dialog stays open.
            % Refused (false) while there are problems or the Model is busy.
            ok = false;
            if ~isempty(obj.problemList())
                obj.LastReport = "Not applied: fix the problems listed first.";
                obj.refreshStatus();
                return
            end
            if obj.isBusy()
                obj.LastReport = "Not applied: wait for the running job to finish.";
                obj.refreshStatus();
                return
            end
            s = obj.Current;
            own = mabr.ui.analysis.SettingsDialog.changeText(obj.Baseline,s,obj.FieldLabels);
            txt = "";
            if ~isempty(obj.ApplyFcn)
                try
                    txt = obj.callApply(s);
                catch me
                    obj.LastReport = "Not applied: " + string(me.message);
                    obj.refreshStatus();
                    return
                end
            end
            obj.Baseline = s;
            obj.ApplyCount = obj.ApplyCount + 1;
            if txt == ""
                txt = "Applied — " + own;
            end
            obj.LastReport = txt;
            obj.refreshStatus();
            ok = true;
        end

        function tf = ok(obj)
            % Apply what changed, then close. Nothing changed: just close.
            tf = false;
            if obj.Done, tf = true; return; end
            if ~isempty(obj.problemList()) || obj.isBusy()
                obj.apply();          % says why it is refused
                return
            end
            if obj.isDirty()
                if ~obj.apply(), return; end
            end
            obj.Value = obj.Current;
            obj.Done = true;
            obj.closeFigure();
            tf = true;
        end

        function cancel(obj)
            % Close without applying anything more (an earlier Apply stays).
            if obj.Done, return; end
            obj.Value = [];
            obj.Done = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            % True until ok() or cancel() (or the window is gone).
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        % ---- what a test or the owner may also want ----------------------
        function p = problems(obj)
            % Every problem listed (refused values first), string column.
            p = obj.problemList();
        end

        function showTab(obj,name)
            % Bring one tab forward, building its controls the first time:
            % "Signal" ... "Profiles" (a prefix is enough; "Detection &
            % measures" names Detection). A test calls this before it looks
            % for a tab's controls by Tag.
            if ~obj.isopen(), return; end
            name = lower(strtrim(string(name)));
            low = lower(obj.TabNames);
            k = find(startsWith(low,name) | arrayfun(@(t) startsWith(name,t),low),1);
            if isempty(k), k = 1; end
            obj.ensureTab(obj.TabNames(k));
            try
                obj.Ctrl.TabGroup.SelectedTab = obj.Ctrl.Tabs.(obj.TabNames(k));
            catch
            end
        end

        function selectWaves(obj,rows)
            % Select rows of the waves table (what Remove acts on).
            obj.WaveSel = unique(double(rows(:))).';
        end
    end

    methods (Static)
        function s = run(settings,applyFcn,varargin)
            % Show the dialog and wait (uiwait): the Settings OK closed with,
            % or [] when cancelled. Interactive use only.
            d = mabr.ui.analysis.SettingsDialog(settings,applyFcn,varargin{:});
            if d.isopen()
                uiwait(d.Figure);
            end
            s = d.Value;
            delete(d);
        end

        function txt = changeText(a,b,labels)
            % What changing settings A into B does, in words: how many
            % settings differ, which -- by the names the dialog shows for
            % them (LABELS: struct property -> label; a property without one
            % is spelled out from its name, "ConductionDelayMode" ->
            % "conduction delay mode") -- and how much of the analysis
            % re-runs.
            if nargin < 3 || ~isstruct(labels), labels = struct(); end
            D = mabr.analysis.Settings.diff(a,b);
            if height(D) == 0
                if a.Profile ~= b.Profile
                    txt = "only the profile name changed.";
                else
                    txt = "nothing changed.";
                end
                return
            end
            names = string(D.Field(1:min(end,4)));
            for k = 1:numel(names)
                names(k) = mabr.ui.analysis.SettingsDialog.fieldLabel(names(k),labels);
            end
            list = strjoin(names,", ");
            if height(D) > 4, list = list + ", …"; end
            k = mabr.analysis.Settings.firstChangedStep(a,b);
            switch k
                case "segment"
                    what = "every session is re-segmented and analysed from the start (slow)";
                case "reject"
                    what = "re-runs from artifact rejection, the permutation test included (slow)";
                case "detect"
                    what = "re-runs the permutation test and what follows it (slow)";
                case "measure"
                    what = "re-runs the single-trial measures, then thresholds and peaks";
                case "thresholds"
                    what = "re-fits the thresholds (instant)";
                case "peaks"
                    what = "re-picks the peaks (instant)";
                otherwise
                    what = "changes no result";
            end
            txt = sprintf('%d change(s) (%s) — %s.',height(D),list,what);
            txt = string(txt);
        end

        function s = fieldLabel(prop,labels)
            % The words for a setting: LABELS' (what the dialog shows), a
            % few the dialog shows without a label of their own, else its
            % property name spelled out ("MinSweeps" -> "Min sweeps").
            if nargin < 2 || ~isstruct(labels), labels = struct(); end
            prop = string(prop);
            if isfield(labels,char(prop))
                s = string(labels.(char(prop)));
                return
            end
            switch prop
                case "ConductionDelayMode", s = "Sound conduction delay";
                case "WindowedPadMode",     s = "Windowed filter padding";
                case "Waves",               s = "Wave windows";
                case "LevelParam",          s = "Level parameter";
                case "Criterion",           s = "Criterion";
                otherwise
                    w = regexprep(char(prop),'([a-z0-9])([A-Z])','$1 $2');
                    w = regexprep(w,'([A-Z]+)([A-Z][a-z])','$1 $2');
                    s = string(w);
                    parts = split(s," ");
                    for k = 2:numel(parts)
                        % (lower case, but keep acronyms: "ADC", "CI")
                        if ~all(isstrprop(char(parts(k)),'upper')), parts(k) = lower(parts(k)); end
                    end
                    s = strjoin(parts," ");
            end
        end

        function b = onsetBiasOf(fsADC,fsDAC)
            % The onset bias of a file, ms: (1 - 1/df)/fsADC with df =
            % round(fsDAC/fsADC) -- SweepOnsets = round(iRaw/df) puts time
            % zero that many ADC samples early, so latencies read long by it
            % (0.078125 ms at 192 kHz / 12 kHz). NaN when a rate is unknown.
            b = NaN;
            if ~(isfinite(fsADC) && fsADC > 0 && isfinite(fsDAC) && fsDAC > 0), return; end
            df = round(fsDAC/fsADC);
            if df < 1, return; end
            b = 1000*(1 - 1/df)/fsADC;
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- building -----------------------------------------------------
        function build(obj)
            f = obj.Figure;
            g = uigridlayout(f,[4 1]);
            g.RowHeight = {'1x',36,34,30};
            g.Padding = [10 10 10 10];
            g.RowSpacing = 6;

            % Each tab's controls are built the first time it is shown
            % (ensureTab): ~150 components cost seconds to create, and most
            % visits to this window touch one tab.
            tg = uitabgroup(g,'Tag','AnalysisSettingsTabs');
            tg.Layout.Row = 1;
            obj.Ctrl.TabGroup = tg;
            titles = ["Signal","Artifacts","Detection & measures","Thresholds","Peaks","Profiles"];
            for k = 1:numel(obj.TabNames)
                t = uitab(tg,'Title',char(titles(k)),'Tag',char("AnalysisSettingsTab" + obj.TabNames(k)));
                obj.Ctrl.Tabs.(obj.TabNames(k)) = t;
                obj.TabBuilt.(obj.TabNames(k)) = false;
            end
            tg.SelectionChangedFcn = @(src,~) obj.onTabChanged(src);

            pr = uilabel(g,'Text','','Tag','AnalysisSettingsProblems','WordWrap','on', ...
                'FontColor',mabr.ui.analysis.Style.Error,'VerticalAlignment','top', ...
                'Tooltip','What makes these settings unusable. Apply and OK stay disabled until the list is empty.');
            pr.Layout.Row = 2;
            obj.Ctrl.Problems = pr;
            ch = uilabel(g,'Text','','Tag','AnalysisSettingsChanges','WordWrap','on', ...
                'FontColor',mabr.ui.analysis.Style.Muted,'VerticalAlignment','top', ...
                'Tooltip','What Apply would change, and how much of the analysis it makes out of date.');
            ch.Layout.Row = 3;
            obj.Ctrl.Changes = ch;

            bg = uigridlayout(g,[1 5],'Padding',[0 0 0 0],'ColumnSpacing',8);
            bg.Layout.Row = 4;
            bg.ColumnWidth = {110,'1x',90,90,90};
            d = uibutton(bg,'Text','Defaults','Tag','AnalysisSettingsDefaults', ...
                'Tooltip','Put every setting back to the MABR defaults (nothing is applied until Apply or OK).', ...
                'ButtonPushedFcn',@(~,~) obj.write(mabr.analysis.Settings()));
            d.Layout.Column = 1;
            a = uibutton(bg,'Text','Apply','Tag','AnalysisSettingsApply', ...
                'Tooltip','Use these settings for the project now; the window stays open.', ...
                'ButtonPushedFcn',@(~,~) obj.apply());
            a.Layout.Column = 3;
            okb = uibutton(bg,'Text','OK','Tag','AnalysisSettingsOK', ...
                'Tooltip','Use these settings for the project and close.', ...
                'ButtonPushedFcn',@(~,~) obj.ok());
            okb.Layout.Column = 4;
            c = uibutton(bg,'Text','Cancel','Tag','AnalysisSettingsCancel', ...
                'Tooltip','Close without applying what changed since the last Apply (Esc).', ...
                'ButtonPushedFcn',@(~,~) obj.cancel());
            c.Layout.Column = 5;
            obj.Ctrl.Apply = a;  obj.Ctrl.OK = okb;  obj.Ctrl.Cancel = c;
        end

        function ensureTab(obj,name)
            % Build one tab's controls (once) and show the settings in them.
            name = string(name);
            if ~isfield(obj.TabBuilt,name) || obj.TabBuilt.(name), return; end
            n0 = numel(obj.Setters);
            t = obj.Ctrl.Tabs.(name);
            switch name
                case "Signal",     obj.buildSignal(t);
                case "Artifacts",  obj.buildArtifacts(t);
                case "Detection",  obj.buildDetection(t);
                case "Thresholds", obj.buildThresholds(t);
                case "Peaks",      obj.buildPeaks(t);
                case "Profiles",   obj.buildProfiles(t);
            end
            obj.TabBuilt.(name) = true;
            for k = n0+1:numel(obj.Setters)
                try
                    obj.Setters(k).Fcn(obj.Current);
                catch me
                    mabr.log.vprintf(2,'SettingsDialog: %s not shown (%s).',obj.Setters(k).Prop,me.message);
                end
            end
            obj.syncDependents("all");
            obj.refreshStatus();
        end

        function onTabChanged(obj,tg)
            k = find(cellfun(@(t) t == tg.SelectedTab,struct2cell(obj.Ctrl.Tabs)),1);
            if ~isempty(k), obj.ensureTab(obj.TabNames(k)); end
        end

        function g = fieldGrid(~,parent,nRows)
            % A column of setting rows: label | field | field | extra.
            g = uigridlayout(parent,[nRows 4]);
            g.ColumnWidth = {200,74,74,'1x'};
            g.RowHeight = repmat({22},1,nRows);
            g.RowSpacing = 4;
            g.ColumnSpacing = 6;
            g.Padding = [10 10 10 10];
            try
                g.Scrollable = 'on';
            catch
            end
        end

        function buildSignal(obj,tab)
            outer = uigridlayout(tab,[1 2],'Padding',[0 0 0 0],'ColumnSpacing',0);
            outer.ColumnWidth = {'1.45x','1x'};
            g = obj.fieldGrid(outer,17);
            g.ColumnWidth = {176,70,70,'1x'};
            obj.pairRow(g,1,"Sweep window (ms)","Window", ...
                "The sweep cut out around each onset, ms re stimulus onset (start, end).");
            obj.pairRow(g,2,"Response window (ms)","ResponseWindow", ...
                "Where a response is looked for: artifact features, detection and the measures (start, end, ms).");
            obj.pairRow(g,3,"Baseline window (ms)","BaselineWindow", ...
                "The pre-stimulus stretch the baseline noise (BaselineRMS) is measured over, ms.");
            obj.pairRow(g,4,"Peak baseline window (ms)","BaselineAmpWindow", ...
                "The stretch peak amplitudes are measured from, ms.");
            obj.dropRow(g,5,"Detrend","Detrend",["None","Order 0 (mean)","Order 1 (linear)","Order 2","Order 3"], ...
                ["none","0","1","2","3"], ...
                "Polynomial each continuous-path sweep is detrended by before averaging.", ...
                @(v) mabr.ui.analysis.SettingsDialog.detrendValue(v), ...
                @(v) mabr.ui.analysis.SettingsDialog.detrendText(v));
            obj.dropRow(g,6,"Processing","Processing",["Automatic","Every condition windowed"], ...
                ["auto","windowed"], ...
                "Automatic: interleaved (compact) files are filtered window by window, the rest as a continuous trace.");
            obj.numRow(g,7,"Windowed filter: order, padding","WindowedOrder", ...
                "Butterworth order of the window-by-window filter (1-4).",Limits=[1 4],Integer=true);
            obj.dropAt(g,7,[3 4],"WindowedPadMode",["Reflect padding","Zero padding (left)"], ...
                ["reflect","zeroleft"],"How a window is padded before it is filtered on its own.");
            obj.checkRow(g,8,"Pool conventional and interleaved runs","PoolAcqModes", ...
                "Analyse a condition's conventional and interleaved runs as one series (off: two series per frequency).");
            obj.numRow(g,9,"Sweeps per condition at most","MaxSweepsPerCondition", ...
                "Clean sweeps used per condition, balanced by polarity; Inf = all of them.",Limits=[1 Inf],Integer=true);
            obj.dropRow(g,10,"The cap keeps","EqualizeMode",["The first sweeps","A seeded random choice"], ...
                ["first","random"],"Which sweeps the cap above keeps.");

            obj.header(g,11,"Latency reference");
            % mode | readout share the row's field columns, so the longest
            % mode ("Speaker distance (cm)") is not cut off
            tip = "How long the sound takes to reach the ear: none (latencies re the electrical onset), " + ...
                "a measured delay, or a speaker distance at the speed of sound.";
            obj.label(g,12,1,"Sound conduction delay",tip);
            dg = uigridlayout(g,[1 2],'Padding',[0 0 0 0],'ColumnSpacing',8);
            dg.Layout.Row = 12; dg.Layout.Column = [2 4];
            dg.ColumnWidth = {'1x',72};
            obj.dropAt(dg,1,1,"ConductionDelayMode",["None","Delay (ms)","Speaker distance (cm)"], ...
                ["none","delay","distance"],tip);
            rd = uilabel(dg,'Text','','Tag','AnalysisSettingsConductionReadout', ...
                'FontWeight','bold','FontColor',mabr.ui.analysis.Style.DataBlue, ...
                'Tooltip','The conduction delay these settings give, ms: latencies are reported re sound arrival.');
            rd.Layout.Row = 1; rd.Layout.Column = 2;
            obj.Ctrl.DelayReadout = rd;
            obj.Ctrl.ConductionDelay = obj.numRow(g,13,"Delay (ms)","ConductionDelay", ...
                "The measured acoustic delay from the stimulus onset to the ear, ms (mode Delay).");
            obj.Ctrl.SpeakerDistance = obj.numRow(g,14,"Speaker distance (cm)","SpeakerDistance", ...
                "Speaker to ear distance, cm (mode Speaker distance): 10 cm of air is 0.29 ms.");
            obj.Ctrl.SpeedOfSound = obj.numRow(g,15,"Speed of sound (m/s)","SpeedOfSound", ...
                "Speed of sound, m/s (mode Speaker distance): 343 m/s is dry air at 20 °C.");
            obj.numRow(g,16,"System time offset (ms)","TimeOffset", ...
                "A further fixed offset of the recording system, ms (e.g. the onset rounding bias below), added to the conduction delay.");
            bl = uilabel(g,'Text','','Tag','AnalysisSettingsOnsetBias', ...
                'FontColor',mabr.ui.analysis.Style.Muted, ...
                'Tooltip',['SweepOnsets are rounded to the ADC grid, which puts time zero (1 - 1/df) ADC ' ...
                'samples early: latencies read long by this much.']);
            bl.Layout.Row = 17; bl.Layout.Column = [1 3];
            ub = uibutton(g,'Text','Use it','Tag','AnalysisSettingsUseOnsetBias', ...
                'Tooltip','Copy the onset bias into the system time offset.', ...
                'ButtonPushedFcn',@(~,~) obj.useOnsetBias());
            ub.Layout.Row = 17; ub.Layout.Column = 4;
            obj.Ctrl.OnsetBias = bl;  obj.Ctrl.UseOnsetBias = ub;

            % ---- the filter, and its response -------------------------------
            r = uigridlayout(outer,[6 4]);
            r.ColumnWidth = {100,62,62,'1x'};
            r.RowHeight = {22,22,22,22,34,'1x'};
            r.RowSpacing = 4; r.ColumnSpacing = 6; r.Padding = [6 10 10 10];
            obj.bandRow(r,1,"HighPass","High pass",["Stop","Pass"], ...
                "High pass: [stop pass] edges, Hz (equiripple FIR, applied forwards and backwards).");
            obj.bandRow(r,2,"LowPass","Low pass",["Pass","Stop"], ...
                "Low pass: [pass stop] edges, Hz.");
            obj.numRow(r,3,"Ripple (dB)","FilterPassRippleDb", ...
                "Pass-band ripple of the FIR design, peak-to-peak dB.",Limits=[0 Inf]);
            obj.numRow(r,4,"Attenuation (dB)","FilterStopAttenDb", ...
                "Stop-band attenuation of the FIR design, dB.",Limits=[0 Inf]);
            cr = uilabel(r,'Text','','Tag','AnalysisSettingsFilterCorners','WordWrap','on', ...
                'FontColor',mabr.ui.analysis.Style.Muted, ...
                'Tooltip',['The chain''s realized -6 dB points as applied (filtfilt squares the response); ' ...
                'the windowed filter is designed at these corners.']);
            cr.Layout.Row = 5; cr.Layout.Column = [1 4];
            obj.Ctrl.FilterCorners = cr;
            p = uipanel(r,'BorderType','none','BackgroundColor',[1 1 1]);
            p.Layout.Row = 6; p.Layout.Column = [1 4];
            ax = axes(p,'Units','normalized','Position',[0.17 0.16 0.78 0.76], ...
                'Tag','AnalysisSettingsFilterAxes','XScale','log','YLim',[-80 5],'Box','on', ...
                'FontSize',8,'XGrid','on','YGrid','on');
            mabr.ui.hideAxesToolbar(ax);
            try
                disableDefaultInteractivity(ax);
            catch
            end
            xlabel(ax,'Frequency (Hz)'); ylabel(ax,'Magnitude (dB)');
            % (margins in pixels: the panel shrinks when the problems row
            % grows, and fractions of a smaller panel cut the frequency
            % ticks and their label off)
            mabr.ui.analysis.Style.pinAxes(p,ax,[50 36 12 8]);
            line(ax,[1 1e5],[-6 -6],'Color',[0.6 0.6 0.6],'LineStyle','--','HitTest','off');
            obj.Ctrl.FilterLine = line(ax,NaN,NaN,'Color',mabr.ui.analysis.Style.DataBlue,'LineWidth',1.5, ...
                'Tag','AnalysisSettingsFilterResponse','HitTest','off');
            obj.Ctrl.FilterAxes = ax;
        end

        function buildArtifacts(obj,tab)
            g = obj.fieldGrid(tab,8);
            obj.checkRow(g,1,"Start from the rig's own artifact flags","HonorAcquisitionArtifacts", ...
                "Sweeps the acquisition rig flagged as artifacts start rejected.");
            obj.dropRow(g,2,"Relative rule","RejectMethod",["None (the ceiling only)","Median","Mean","Quartiles"], ...
                ["none","median","mean","quartiles"], ...
                "An outlier rule applied to each condition's sweeps: factor x the median (or mean, or the quartile range).");
            obj.dropRow(g,3,"Sweep feature","RejectFeature", ...
                ["Absolute peak","Peak to peak","RMS","SD","Mean absolute","Positive peak","Negative peak"], ...
                ["absPeak","peak2peak","rms","std","meanabs","posPeak","negPeak"], ...
                "The per-sweep number the rule judges, taken over the response window.");
            obj.numRow(g,4,"Factor","RejectFactor","The outlier threshold factor of the relative rule.",Limits=[0 Inf]);
            obj.checkRow(g,5,"Reject only the large side","RejectUpperOnly", ...
                "For a non-negative feature, only unusually large sweeps are rejected.");
            obj.numRow(g,6,"Absolute ceiling (µV)","RejectCeiling", ...
                "Any sweep whose feature exceeds this is rejected, µV; Inf = off.",Limits=[0 Inf],Scale=1e6);
            note = uilabel(g,'Text',['Rejected sweeps are flagged, never deleted: changing these re-runs ' ...
                'rejection and everything after it, and manual rejections are kept.'],'WordWrap','on', ...
                'FontColor',mabr.ui.analysis.Style.Muted);
            note.Layout.Row = [7 8]; note.Layout.Column = [1 4];
        end

        function buildDetection(obj,tab)
            g = obj.fieldGrid(tab,11);
            obj.header(g,1,"Detection (permutation test)");
            obj.dropRow(g,2,"Statistic","DetectMethod",["TFCE","Cluster mass","t-max"], ...
                ["tfce","clusterMass","tmax"],"The sign-flip permutation statistic a condition is judged by.");
            obj.numRow(g,3,"Permutations","NumPermutations", ...
                "Sign-flip permutations per condition; the smallest p is 1/(B+1).",Limits=[1 Inf],Integer=true);
            obj.numRow(g,4,"α","Alpha","Significance level of a detection.",Limits=[0 1]);
            obj.numRow(g,5,"Seed","Seed","Base seed of the permutations (each condition's derives from it).", ...
                Limits=[0 Inf],Integer=true);
            obj.header(g,6,"Single-trial measures");
            obj.dropRow(g,7,"Split-half sub-average","SplitHalfMode",["Median","Mean"],["median","mean"], ...
                "How each half of a split is averaged.");
            obj.numRow(g,8,"Split-half resamples","SplitHalfResamples", ...
                "Random partitions per condition (at least 10).",Limits=[1 Inf],Integer=true);
            [h1,h2] = obj.pairRow(g,9,"Split-half window (ms)","SplitHalfWindow", ...
                "The window the split-half r is computed over, ms.");
            ck = uicheckbox(g,'Text','the response window','Tag','AnalysisSettingsSplitHalfWindowAuto', ...
                'Tooltip','Use the response window for the split-half r.');
            ck.Layout.Row = 9; ck.Layout.Column = 4;
            ck.ValueChangedFcn = @(~,~) obj.onSplitHalfAuto();
            obj.Ctrl.SplitHalfAuto = ck;  obj.Ctrl.SplitHalfStart = h1;  obj.Ctrl.SplitHalfEnd = h2;
            obj.numRow(g,10,"Fewest per polarity per half","SplitHalfMinPerPolarity", ...
                "Fewest sweeps of each polarity in each half.",Limits=[0 Inf],Integer=true);
            obj.numRow(g,11,"Next-louder correlation lag (ms)","MaxLag", ...
                ['The most the quieter level''s response may be later than the louder one''s, ms: ' ...
                'one lag for the whole window (suthakar-liberman; 0 is the paper''s), or a lag up ' ...
                'to this that changes along the response (xcorr-dtw).'],Limits=[0 Inf]);
        end

        function buildThresholds(obj,tab)
            outer = uigridlayout(tab,[2 2],'Padding',[0 0 0 0],'ColumnSpacing',0,'RowSpacing',0);
            outer.RowHeight = {96,'1x'};
            outer.ColumnWidth = {'1x','1x'};
            top = uigridlayout(outer,[2 2],'Padding',[10 10 10 0],'RowSpacing',4,'ColumnSpacing',6);
            top.Layout.Row = 1; top.Layout.Column = [1 2];
            top.ColumnWidth = {200,'1x'};
            top.RowHeight = {24,'1x'};
            M = mabr.analysis.SeriesThreshold.methods();
            obj.dropRow(top,1,"Threshold method","ThresholdMethod",string({M.Label}),string({M.Id}), ...
                "How a series' threshold is found: the named methods, or Custom… (the fields below).");
            df = uilabel(top,'Text','','Tag','AnalysisSettingsThresholdDefinition','WordWrap','on', ...
                'VerticalAlignment','top','FontColor',mabr.ui.analysis.Style.Ink, ...
                'Tooltip','What "threshold" means under these settings.');
            df.Layout.Row = 2; df.Layout.Column = [1 2];
            obj.Ctrl.Definition = df;

            g = obj.fieldGrid(outer,11);
            g.Layout.Row = 2; g.Layout.Column = 1;
            g.ColumnWidth = {170,'1x',4,4};
            obj.Ctrl.ThresholdMetric = obj.dropRow(g,1,"Custom: metric","ThresholdMetric", ...
                ["Detection (p)","Power","Fsp","Split-half r","Next-louder correlation", ...
                 "Next-louder correlation (DTW)","SNR","Strength"], ...
                ["detection","power","fsp","splithalf","xcorr","dtw","snr","strength"], ...
                "Custom method: the per-level number the threshold is read from.");
            obj.Ctrl.ThresholdModel = obj.dropRow(g,2,"Custom: model","ThresholdModel", ...
                ["Descending (consecutive levels)","Psychometric GLM","ABRpresto-like fit","Isotonic","Sigmoid","Minimum"], ...
                ["descending","glm","presto","isotonic","sigmoid","minimum"], ...
                "Custom method: how the threshold is read off the levels.");
            obj.Ctrl.CriterionMode = obj.dropRow(g,3,"Custom: criterion is","CriterionMode", ...
                ["A p-value","A probability","An absolute value","A fraction of the range"], ...
                ["p","probability","absolute","fraction"],"Custom method: what the criterion below is.");
            cr = uieditfield(g,'text','Tag','AnalysisSettingsCriterion', ...
                'Tooltip','Custom method: the criterion; blank = the default of the criterion kind.');
            cr.Layout.Row = 4; cr.Layout.Column = 2;
            obj.label(g,4,1,"Custom: criterion","Custom method: the criterion; blank = the default.");
            cr.ValueChangedFcn = @(src,~) obj.onCriterion(src.Value);
            obj.addSetter("Criterion",@(s) obj.setText(cr,mabr.ui.analysis.SettingsDialog.numberText(s.Criterion)));
            obj.Ctrl.Criterion = cr;
            lp = uidropdown(g,'Items',{'(automatic)'},'Editable','on','Tag','AnalysisSettingsLevelParam', ...
                'Tooltip','The stimulus parameter that is the level axis of a series; automatic finds it by name.');
            lp.Layout.Row = 5; lp.Layout.Column = 2;
            obj.label(g,5,1,"Level parameter","The stimulus parameter that is the level axis.");
            lp.ValueChangedFcn = @(src,~) obj.onLevelParam(src.Value);
            obj.addSetter("LevelParam",@(s) obj.setLevelParam(s.LevelParam));
            obj.Ctrl.LevelParam = lp;
            gbTip = ['Parameters a series is grouped by, comma separated; blank = every non-level ' ...
                'parameter. Stimulus and acquisition mode are always added (the mode not when pooled), ' ...
                'so a series never mixes them.'];
            gb = uieditfield(g,'text','Tag','AnalysisSettingsGroupBy','Tooltip',gbTip);
            gb.Layout.Row = 6; gb.Layout.Column = 2;
            obj.label(g,6,1,"Group series by",gbTip);
            gb.ValueChangedFcn = @(src,~) obj.assign("GroupBy",mabr.ui.analysis.SettingsDialog.splitNames(src.Value));
            obj.addSetter("GroupBy",@(s) obj.setText(gb,strjoin(s.GroupBy,", ")));
            obj.dropRow(g,7,"Level direction","LevelDirection",["Automatic","Ascending (louder up)","Descending (attenuation)"], ...
                ["auto","ascending","descending"], ...
                "Which way the level axis runs; automatic is descending for a parameter named like Attenuation.");
            obj.numRow(g,8,"Consecutive detected levels","MinConsecutive", ...
                "How many consecutive detected levels the descending rule needs.",Limits=[0 Inf],Integer=true);
            obj.dropRow(g,9,"Interval convention","ThresholdConvention",["Midpoint","Lowest level","Crossing"], ...
                ["midpoint","lowest_level","crossing"], ...
                "The point reported inside an interval-censored threshold.");
            obj.checkRow(g,10,"Interpolate the criterion crossing","Interpolate", ...
                "Graded metrics: interpolate between levels rather than take a tested level.");

            h = obj.fieldGrid(outer,11);
            h.Layout.Row = 2; h.Layout.Column = 2;
            h.ColumnWidth = {200,'1x',4,4};
            obj.numRow(h,1,"Fewest clean sweeps per level","MinSweeps", ...
                "A level with fewer clean sweeps does not count.",Limits=[0 Inf],Integer=true);
            obj.numRow(h,2,"… of each polarity","MinPerPolarity", ...
                "Fewest clean sweeps of each polarity a level needs (alternating data).",Limits=[0 Inf],Integer=true);
            obj.checkRow(h,3,"Extrapolate beyond the levels tested","Extrapolate", ...
                "Allow a model threshold outside the levels tested.");
            obj.checkRow(h,4,"Next tested level at or above","NearestLevel", ...
                "Snap a model threshold to the next tested level at or above it.");
            obj.numRow(h,5,"Interval α","CIAlpha","Two-sided level of the threshold intervals.",Limits=[0 1]);
            obj.numRow(h,6,"Monte Carlo draws","CINumSamples","Draws of a legacy interval.",Limits=[1 Inf],Integer=true);
            obj.numRow(h,7,"Bootstrap replicates","ThresholdBootstrap", ...
                "Sweep-bootstrap replicates of a graded threshold; 0 = off.",Limits=[0 Inf],Integer=true);
            obj.numRow(h,8,"Flag an interval wider than","FlagWideCI", ...
                "Flag a threshold whose interval is wider than this fraction of the level range.",Limits=[0 Inf]);
            obj.numRow(h,9,"Undetected levels tolerated","FlagNonMonotoneTol", ...
                "Undetected levels above the first detection tolerated before a series is flagged non-monotone.", ...
                Limits=[0 Inf],Integer=true);
        end

        function buildPeaks(obj,tab)
            outer = uigridlayout(tab,[2 2],'Padding',[0 0 0 0],'ColumnSpacing',0,'RowSpacing',0);
            outer.RowHeight = {196,'1x'};
            outer.ColumnWidth = {'1x','1x'};
            top = uigridlayout(outer,[3 2],'Padding',[10 10 10 0],'RowSpacing',4,'ColumnSpacing',6);
            top.Layout.Row = 1; top.Layout.Column = [1 2];
            top.ColumnWidth = {'1x',96};
            top.RowHeight = {28,28,'1x'};
            t = uitable(top,'Tag','AnalysisSettingsWaves', ...
                'ColumnName',{'Name','On','Start (ms)','End (ms)','Expected (ms)','Shift (ms/dB)','Stimulus'}, ...
                'ColumnEditable',true,'RowName',{}, ...
                'Tooltip',['The waves peaks are picked for: search windows in ms re the timing pulse (the ' ...
                'recording''s own time: a conduction delay changes reported latencies, not where waves ' ...
                'are searched), the latency ' ...
                'shift per dB below the loudest level, and a stimulus (blank = every stimulus).']);
            t.Layout.Row = [1 3]; t.Layout.Column = 1;
            t.CellEditCallback = @(src,~) obj.onWavesEdited(src);
            t.CellSelectionCallback = @(src,e) obj.onWavesSelected(src,e);
            cm = uicontextmenu(obj.Figure);
            uimenu(cm,'Text','Copy table','MenuSelectedFcn',@(~,~) mabr.ui.analysis.FigureExport.copyTable(t));
            t.ContextMenu = cm;
            obj.Ctrl.Waves = t;
            obj.addSetter("Waves",@(s) obj.setWaves(s.Waves));
            ad = uibutton(top,'Text','Add wave','Tag','AnalysisSettingsWaveAdd', ...
                'Tooltip','Add a wave (named A, B, ...) one ms after the last window.', ...
                'ButtonPushedFcn',@(~,~) obj.addWave());
            ad.Layout.Row = 1; ad.Layout.Column = 2;
            rm = uibutton(top,'Text','Remove','Tag','AnalysisSettingsWaveRemove', ...
                'Tooltip','Remove the selected wave(s).', ...
                'ButtonPushedFcn',@(~,~) obj.removeWaves());
            rm.Layout.Row = 2; rm.Layout.Column = 2;

            g = obj.fieldGrid(outer,7);
            g.Layout.Row = 2; g.Layout.Column = 1;
            g.ColumnWidth = {190,'1x',4,4};
            obj.numRow(g,1,"Octave shift (ms per octave)","PeakOctaveShift", ...
                "How much later the wave windows sit per octave below the reference frequency, ms.");
            obj.numRow(g,2,"Reference frequency (kHz)","PeakRefFrequency", ...
                "The frequency the wave windows are written for, kHz.",Limits=[0 Inf]);
            obj.numRow(g,3,"Smoothing (samples)","PeakSmooth", ...
                "Moving-mean samples of the copy peaks are picked from; 0 = off.",Limits=[0 Inf],Integer=true);
            obj.numRow(g,4,"Smallest separation (ms)","PeakMinSeparation", ...
                "The smallest separation of two picks, ms.",Limits=[0 Inf]);
            obj.numRow(g,5,"Track earlier by up to (ms)","PeakTrackEarly", ...
                "Down the levels, how much earlier than the louder pick a wave may be found, ms.",Limits=[0 Inf]);
            obj.numRow(g,6,"Track later by up to (ms)","PeakTrackLate", ...
                "Down the levels, how much later than the louder pick (plus the wave's shift) a wave may be found, ms.", ...
                Limits=[0 Inf]);

            h = obj.fieldGrid(outer,7);
            h.Layout.Row = 2; h.Layout.Column = 2;
            h.ColumnWidth = {190,'1x',4,4};
            obj.numRow(h,1,"Candidate prominence (× RN)","PeakCandidateRN", ...
                "A turning point is a candidate when its prominence reaches this many residual-noise units.",Limits=[0 Inf]);
            obj.numRow(h,2,"Detectable prominence (× RN)","PeakDetectableRN", ...
                "A pick counts as detectable at this many residual-noise units.",Limits=[0 Inf]);
            obj.dropRow(h,3,"Picked on","PeakPolarity",["Balanced average","Positive sweeps","Negative sweeps"], ...
                ["balanced","positive","negative"],"Which average peaks are picked on.");
            obj.checkRow(h,4,"Measures above threshold only","PeaksAboveThresholdOnly", ...
                "Derived peak measures from levels at or above threshold only.");
            obj.numRow(h,5,"Bootstrap replicates","PeakBootstrap", ...
                "Bootstrap replicates of peak latency and amplitude; 0 = off.",Limits=[0 Inf],Integer=true);
            obj.numRow(h,6,"Edge margin (ms)","PeakEdgeMs", ...
                "A pick this close to a windowed condition's edge is flagged edge-affected, ms.",Limits=[0 Inf]);
        end

        function buildProfiles(obj,tab)
            g = uigridlayout(tab,[6 3]);
            g.ColumnWidth = {200,'1x',120};
            g.RowHeight = {24,96,30,24,24,'1x'};
            g.RowSpacing = 6; g.Padding = [10 10 10 10];
            obj.label(g,1,1,"Profile name","A name for this set of settings (a label: it is not compared).");
            pn = uieditfield(g,'text','Tag','AnalysisSettingsProfile', ...
                'Tooltip','A name for this set of settings; Save As… writes it into the file.');
            pn.Layout.Row = 1; pn.Layout.Column = 2;
            pn.ValueChangedFcn = @(src,~) obj.assign("Profile",string(src.Value));
            obj.addSetter("Profile",@(s) obj.setText(pn,s.Profile));
            obj.label(g,2,1,"Built-in profiles","MABR's own sets of settings.");
            lb = uilistbox(g,'Items',cellstr(mabr.analysis.Settings.profileNames()), ...
                'Tag','AnalysisSettingsProfileList', ...
                'Tooltip','MABR default: the recommended settings. Legacy SCRATCH (2025): the 2025 batch pipeline.');
            lb.Layout.Row = 2; lb.Layout.Column = 2;
            obj.Ctrl.ProfileList = lb;
            ub = uibutton(g,'Text','Use this profile','Tag','AnalysisSettingsProfileUse', ...
                'Tooltip','Put the selected built-in profile into every field (applied with Apply or OK).', ...
                'ButtonPushedFcn',@(~,~) obj.useProfile(string(lb.Value)));
            ub.Layout.Row = 2; ub.Layout.Column = 3;
            bb = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            bb.Layout.Row = 3; bb.Layout.Column = 2;
            bb.ColumnWidth = {110,110,'1x'};
            ld = uibutton(bb,'Text','Load…','Tag','AnalysisSettingsLoad', ...
                'Tooltip','Read settings from a .mabraset file into every field.', ...
                'ButtonPushedFcn',@(~,~) obj.loadFile(""));
            mabr.ui.analysis.Style.setButtonIcon(ld,'load','left');
            sv = uibutton(bb,'Text','Save As…','Tag','AnalysisSettingsSaveAs', ...
                'Tooltip','Write these settings to a .mabraset file (to share them, or use them in a batch).', ...
                'ButtonPushedFcn',@(~,~) obj.saveFile(""));
            mabr.ui.analysis.Style.setButtonIcon(sv,'save','left');
            mt = uilabel(g,'Text','','Tag','AnalysisSettingsMatches', ...
                'Tooltip','Whether the settings that change a result equal a built-in profile''s.');
            mt.Layout.Row = 4; mt.Layout.Column = [1 3];
            obj.Ctrl.Matches = mt;
            obj.label(g,5,1,"In words","Settings.describe(): one line per analysis step.");
            ds = uitextarea(g,'Editable','off','Tag','AnalysisSettingsDescribe', ...
                'Tooltip','The settings in words, one line per step.');
            ds.Layout.Row = 6; ds.Layout.Column = [1 3];
            obj.Ctrl.Describe = ds;
        end

        % ---- row helpers --------------------------------------------------
        function lab = label(~,g,row,col,text,tip)
            lab = uilabel(g,'Text',char(text),'Tooltip',char(tip));
            lab.Layout.Row = row; lab.Layout.Column = col;
        end

        function nameField(obj,prop,label)
            % Remember the words the dialog shows for a setting (the change
            % summary names a setting by them, not by its property name).
            label = strtrim(regexprep(string(label),'\s*\([^)]*\)\s*$',''));
            if label == "", return; end
            obj.FieldLabels.(char(prop)) = label;
        end

        function header(~,g,row,text)
            lab = uilabel(g,'Text',char(text),'FontWeight','bold','FontColor',mabr.ui.analysis.Style.Ink);
            lab.Layout.Row = row; lab.Layout.Column = [1 4];
        end

        function h = numRow(obj,g,row,label,prop,tip,opts)
            % label | numeric field: one scalar setting (the label names
            % its unit).
            arguments
                obj
                g
                row (1,1) double
                label (1,1) string
                prop (1,1) string
                tip (1,1) string
                opts.Limits (1,2) double = [-Inf Inf]
                opts.Integer (1,1) logical = false
                opts.Scale (1,1) double = 1     % shown = stored x Scale
            end
            obj.label(g,row,1,label,tip);
            obj.nameField(prop,label);
            h = uieditfield(g,'numeric','Limits',opts.Limits,'ValueDisplayFormat','%.6g', ...
                'Tag',char("AnalysisSettings" + prop),'Tooltip',char(tip));
            if opts.Integer, h.RoundFractionalValues = 'on'; end
            h.Layout.Row = row; h.Layout.Column = 2;
            sc = opts.Scale;
            h.ValueChangedFcn = @(src,~) obj.assign(prop,src.Value/sc);
            obj.addSetter(prop,@(s) obj.setNumber(h,s.(prop)*sc));
            obj.Ctrl.(prop) = h;
        end

        function [h1,h2] = pairRow(obj,g,row,label,prop,tip)
            % label | start | end: a [t0 t1] window.
            obj.label(g,row,1,label,tip);
            obj.nameField(prop,label);
            h1 = uieditfield(g,'numeric','ValueDisplayFormat','%.6g', ...
                'Tag',char("AnalysisSettings" + prop + "Start"),'Tooltip',char(tip + " — start"));
            h1.Layout.Row = row; h1.Layout.Column = 2;
            h2 = uieditfield(g,'numeric','ValueDisplayFormat','%.6g', ...
                'Tag',char("AnalysisSettings" + prop + "End"),'Tooltip',char(tip + " — end"));
            h2.Layout.Row = row; h2.Layout.Column = 3;
            fcn = @(~,~) obj.assign(prop,[h1.Value h2.Value]);
            h1.ValueChangedFcn = fcn;
            h2.ValueChangedFcn = fcn;
            obj.addSetter(prop,@(s) obj.setPair(h1,h2,s.(prop)));
        end

        function h = dropRow(obj,g,row,label,prop,items,data,tip,toValue,toText)
            % label | dropdown (spanning the field columns).
            if nargin < 9 || isempty(toValue), toValue = @(v) string(v); end
            if nargin < 10 || isempty(toText), toText = @(v) string(v); end
            obj.label(g,row,1,label,tip);
            obj.nameField(prop,label);
            h = uidropdown(g,'Items',cellstr(items),'ItemsData',cellstr(data), ...
                'Tag',char("AnalysisSettings" + prop),'Tooltip',char(tip));
            h.Layout.Row = row;
            nc = numel(g.ColumnWidth);
            if nc >= 3 && ~isequal(g.ColumnWidth{3},4)
                h.Layout.Column = [2 3];
            else
                h.Layout.Column = 2;
            end
            h.ValueChangedFcn = @(src,~) obj.assign(prop,toValue(src.Value));
            obj.addSetter(prop,@(s) obj.setDrop(h,toText(s.(prop))));
            obj.Ctrl.(prop) = h;
        end

        function h = dropAt(obj,g,row,cols,prop,items,data,tip)
            % A dropdown with no label of its own, at given columns.
            h = uidropdown(g,'Items',cellstr(items),'ItemsData',cellstr(data), ...
                'Tag',char("AnalysisSettings" + prop),'Tooltip',char(tip));
            h.Layout.Row = row; h.Layout.Column = cols;
            h.ValueChangedFcn = @(src,~) obj.assign(prop,string(src.Value));
            obj.addSetter(prop,@(s) obj.setDrop(h,s.(prop)));
            obj.Ctrl.(prop) = h;
        end

        function h = checkRow(obj,g,row,text,prop,tip)
            % A checkbox spanning the row.
            obj.nameField(prop,text);
            h = uicheckbox(g,'Text',char(text),'Tag',char("AnalysisSettings" + prop),'Tooltip',char(tip));
            h.Layout.Row = row; h.Layout.Column = [1 numel(g.ColumnWidth)];
            h.ValueChangedFcn = @(src,~) obj.assign(prop,logical(src.Value));
            obj.addSetter(prop,@(s) obj.setCheck(h,s.(prop)));
            obj.Ctrl.(prop) = h;
        end

        function bandRow(obj,g,row,prop,label,edges,tip)
            % [x] High pass | stop | pass: a band edge pair that may be off ([]).
            obj.nameField(prop,label);
            on = uicheckbox(g,'Text',char(label),'Tag',char("AnalysisSettings" + prop + "On"), ...
                'Tooltip',char(tip + " Untick to switch it off."));
            on.Layout.Row = row; on.Layout.Column = 1;
            a = uieditfield(g,'numeric','Limits',[0 Inf],'ValueDisplayFormat','%.6g', ...
                'Tag',char("AnalysisSettings" + prop + edges(1)),'Tooltip',char(tip + " — " + lower(edges(1)) + " edge, Hz"));
            a.Layout.Row = row; a.Layout.Column = 2;
            b = uieditfield(g,'numeric','Limits',[0 Inf],'ValueDisplayFormat','%.6g', ...
                'Tag',char("AnalysisSettings" + prop + edges(2)),'Tooltip',char(tip + " — " + lower(edges(2)) + " edge, Hz"));
            b.Layout.Row = row; b.Layout.Column = 3;
            u = uilabel(g,'Text','Hz','FontColor',mabr.ui.analysis.Style.Muted);
            u.Layout.Row = row; u.Layout.Column = 4;
            fcn = @(~,~) obj.onBand(prop,on,a,b);
            on.ValueChangedFcn = fcn;  a.ValueChangedFcn = fcn;  b.ValueChangedFcn = fcn;
            obj.addSetter(prop,@(s) obj.setBand(on,a,b,s.(prop)));
        end

        function addSetter(obj,prop,fcn)
            obj.Setters(end+1) = struct('Prop',string(prop),'Fcn',fcn);
        end

        function runSetter(obj,prop)
            for k = find([obj.Setters.Prop] == prop)
                obj.Setters(k).Fcn(obj.Current);
            end
        end

        % ---- settings -> controls ------------------------------------------
        function setNumber(~,h,v)
            try
                if isempty(v) || isnan(v), return; end
                h.Value = double(v);
            catch
                % outside the field's Limits: keep what it shows
            end
        end

        function setPair(~,h1,h2,v)
            if numel(v) == 2
                h1.Value = v(1);  h2.Value = v(2);
            end
        end

        function setDrop(~,h,v)
            v = char(string(v));
            if any(strcmp(h.ItemsData,v)), h.Value = v; end
        end

        function setCheck(~,h,v)
            h.Value = logical(v);
        end

        function setText(~,h,v)
            v = string(v);
            if isempty(v) || ismissing(v), v = ""; end
            h.Value = char(v);
        end

        function setBand(~,on,a,b,v)
            on.Value = ~isempty(v);
            if numel(v) == 2
                a.Value = v(1);  b.Value = v(2);
            end
            a.Enable = matlab.lang.OnOffSwitchState(on.Value);
            b.Enable = matlab.lang.OnOffSwitchState(on.Value);
        end

        function setLevelParam(obj,v)
            h = obj.Ctrl.LevelParam;
            items = ["(automatic)", obj.Params];
            v = string(v);
            if v ~= "" && ~any(items == v), items(end+1) = v; end
            h.Items = cellstr(items);
            if v == "", h.Value = '(automatic)'; else, h.Value = char(v); end
        end

        function setWaves(obj,W)
            names = {'Name','On','Start','End','Expected','Shift','Stimulus'};
            if isempty(W)
                T = table(cell(0,1),false(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),cell(0,1), ...
                    'VariableNames',names);
            else
                T = table(cellstr(reshape([W.Name],[],1)),reshape([W.Enabled],[],1), ...
                    reshape([W.TMin],[],1),reshape([W.TMax],[],1),reshape([W.Expected],[],1), ...
                    reshape([W.LatencyShift],[],1),cellstr(reshape([W.Stimulus],[],1)), ...
                    'VariableNames',names);
            end
            obj.Ctrl.Waves.Data = T;
        end

        % ---- controls -> settings ------------------------------------------
        function assign(obj,prop,v)
            % One setting from a control. A value the class refuses is kept
            % as a problem of its own (the control keeps showing it).
            s = obj.Current;
            try
                s.(prop) = v;
                obj.Current = s;
                if isfield(obj.FieldErrors,prop)
                    obj.FieldErrors = rmfield(obj.FieldErrors,prop);
                end
            catch me
                obj.FieldErrors.(prop) = string(prop) + ": " + string(me.message);
            end
            obj.LastReport = "";
            obj.syncDependents(prop);
            obj.refreshStatus();
        end

        function onBand(obj,prop,on,a,b)
            a.Enable = matlab.lang.OnOffSwitchState(on.Value);
            b.Enable = matlab.lang.OnOffSwitchState(on.Value);
            if on.Value
                obj.assign(prop,[a.Value b.Value]);
            else
                obj.assign(prop,zeros(1,0));
            end
        end

        function onSplitHalfAuto(obj)
            ck = obj.Ctrl.SplitHalfAuto;
            if ck.Value
                obj.assign("SplitHalfWindow",[]);
            else
                obj.assign("SplitHalfWindow",[obj.Ctrl.SplitHalfStart.Value obj.Ctrl.SplitHalfEnd.Value]);
            end
        end

        function onCriterion(obj,txt)
            txt = strtrim(string(txt));
            if txt == ""
                obj.assign("Criterion",NaN);
                return
            end
            v = str2double(txt);
            if isnan(v)
                obj.FieldErrors.Criterion = "Criterion: """ + txt + """ is not a number (blank = the default).";
                obj.LastReport = "";
                obj.refreshStatus();
                return
            end
            obj.assign("Criterion",v);
        end

        function onLevelParam(obj,v)
            v = strtrim(string(v));
            if v == "(automatic)", v = ""; end
            obj.assign("LevelParam",v);
        end

        function onWavesEdited(obj,t)
            % Every edit rebuilds the waves from the table (never rewriting
            % the table's Data from inside its own callback).
            D = t.Data;
            n = height(D);
            W = struct('Name',cell(1,n),'Enabled',[],'TMin',[],'TMax',[],'Expected',[], ...
                'LatencyShift',[],'Stimulus',[]);
            for k = 1:n
                W(k).Name = string(D.Name{k});
                W(k).Enabled = logical(D.On(k));
                W(k).TMin = D.Start(k);
                W(k).TMax = D.End(k);
                W(k).Expected = D.Expected(k);
                W(k).LatencyShift = D.Shift(k);
                W(k).Stimulus = string(D.Stimulus{k});
            end
            obj.assign("Waves",W);
        end

        function onWavesSelected(obj,t,e)
            obj.WaveSel = mabr.ui.analysis.Compat.selectedRows(t,e);
        end

        function addWave(obj)
            W = obj.Current.Waves;
            name = string(mabr.ui.TraceInspector.nextWaveName(cellstr([W.Name])));
            if isempty(W)
                t0 = 1;
            else
                t0 = max([W.TMax]);
            end
            w = struct('Name',name,'Enabled',true,'TMin',t0,'TMax',t0 + 1,'Expected',t0 + 0.5, ...
                'LatencyShift',mabr.analysis.Peaks.AddedLatencyShift,'Stimulus',"");
            if isempty(W)
                W = w;
            else
                W(end+1) = w;
            end
            obj.assign("Waves",W);
            obj.runSetter("Waves");
        end

        function removeWaves(obj)
            W = obj.Current.Waves;
            rows = obj.WaveSel(obj.WaveSel >= 1 & obj.WaveSel <= numel(W));
            if isempty(rows)
                obj.LastReport = "Select the wave(s) to remove in the table first.";
                obj.refreshStatus();
                return
            end
            W(rows) = [];
            obj.WaveSel = zeros(1,0);
            obj.assign("Waves",W);
            obj.runSetter("Waves");
        end

        function useOnsetBias(obj)
            b = obj.OnsetBias(isfinite(obj.OnsetBias));
            if isempty(b), return; end
            v = mode(round(b,9));
            obj.assign("TimeOffset",v);
            obj.runSetter("TimeOffset");
        end

        function useProfile(obj,name)
            try
                obj.write(mabr.analysis.Settings.profile(name));
                obj.LastReport = "Profile " + name + " put into every field — Apply or OK to use it.";
            catch me
                obj.LastReport = "No profile " + name + ": " + string(me.message);
            end
            obj.refreshStatus();
        end

        function loadFile(obj,file)
            % Load… : a .mabraset file into every field.
            if file == ""
                file = obj.pick("*.mabraset","Load analysis settings","open","");
                if file == "", return; end
            end
            try
                [s,warn] = mabr.analysis.Settings.load(file);
            catch me
                obj.LastReport = "Could not read " + file + ": " + string(me.message);
                obj.refreshStatus();
                return
            end
            obj.write(s);
            [~,nm,ext] = fileparts(file);
            txt = "Loaded " + nm + ext + " — Apply or OK to use it.";
            if ~isempty(warn), txt = txt + " " + strjoin(warn," "); end
            obj.LastReport = txt;
            obj.refreshStatus();
        end

        function saveFile(obj,file)
            % Save As… : the settings as edited, into a .mabraset file.
            s = obj.Current;
            if file == ""
                nm = matlab.lang.makeValidName(char(s.Profile));
                file = obj.pick("*.mabraset","Save analysis settings","save",string(nm) + ".mabraset");
                if file == "", return; end
            end
            [~,base] = fileparts(file);
            if ismember(s.Profile,mabr.analysis.Settings.profileNames()) && s.matchingProfile() ~= s.Profile
                % A built-in's name on settings that are no longer it would
                % make the file claim to be that profile.
                s.Profile = string(base);
                obj.Current = s;
                obj.runSetter("Profile");
            end
            try
                f = s.save(file);
            catch me
                obj.LastReport = "Could not write " + file + ": " + string(me.message);
                obj.refreshStatus();
                return
            end
            obj.LastReport = "Saved to " + string(f);
            obj.refreshStatus();
        end

        % ---- derived displays ---------------------------------------------
        function syncDependents(obj,prop)
            if ~obj.isopen(), return; end
            all_ = prop == "all";
            if all_ || ismember(prop,["HighPass","LowPass","FilterPassRippleDb","FilterStopAttenDb"])
                obj.redrawFilter();
            end
            if all_ || ismember(prop,["ConductionDelayMode","ConductionDelay","SpeakerDistance", ...
                    "SpeedOfSound","TimeOffset"])
                obj.syncDelay();
            end
            if all_ || ismember(prop,["ThresholdMethod","ThresholdMetric","ThresholdModel", ...
                    "CriterionMode","Criterion","Alpha","MinConsecutive"])
                obj.syncMethod();
            end
            if all_ || prop == "SplitHalfWindow"
                obj.syncSplitHalf();
            end
        end

        function redrawFilter(obj)
            if ~obj.TabBuilt.Signal, return; end
            s = obj.Current;
            key = string(sprintf('%.10g,',[s.HighPass -1 s.LowPass -1 s.FilterPassRippleDb ...
                s.FilterStopAttenDb obj.SampleRate]));
            if key == obj.FilterKey, return; end
            obj.FilterKey = key;
            L = obj.Ctrl.FilterLine;
            fs = obj.SampleRate;
            try
                if isempty(s.HighPass) && isempty(s.LowPass)
                    set(L,'XData',[1 fs/2],'YData',[0 0]);
                    obj.put('corners',obj.Ctrl.FilterCorners,'Text','No filtering: both bands are off.');
                else
                    f = s.filter().design(fs);
                    [fr,mag] = f.response(2048);
                    set(L,'XData',fr(2:end),'YData',mag(2:end));
                    [c1,c2] = f.corners6dB();
                    txt = "−6 dB";
                    if isfinite(c1), txt = txt + sprintf(' at %.0f Hz',c1); end
                    if isfinite(c2)
                        if isfinite(c1), txt = txt + " and"; end
                        txt = txt + sprintf(' %.0f Hz',c2);
                    end
                    txt = txt + sprintf(' (as applied, order %d, at %g kHz)',f.Order,fs/1000);
                    obj.put('corners',obj.Ctrl.FilterCorners,'Text',char(txt));
                end
                xlim(obj.Ctrl.FilterAxes,[10 fs/2]);
            catch me
                set(L,'XData',NaN,'YData',NaN);
                obj.put('corners',obj.Ctrl.FilterCorners,'Text', ...
                    char("The filter cannot be designed: " + string(me.message)));
            end
        end

        function syncDelay(obj)
            if ~obj.TabBuilt.Signal, return; end
            s = obj.Current;
            m = s.ConductionDelayMode;
            obj.put('delayOn',obj.Ctrl.ConductionDelay,'Enable',matlab.lang.OnOffSwitchState(m == "delay"));
            obj.put('distOn',obj.Ctrl.SpeakerDistance,'Enable',matlab.lang.OnOffSwitchState(m == "distance"));
            obj.put('speedOn',obj.Ctrl.SpeedOfSound,'Enable',matlab.lang.OnOffSwitchState(m == "distance"));
            if m == "none"
                txt = "re onset";
            else
                d = s.conductionDelay();
                if isfinite(d), txt = sprintf('= %.2f ms',d); else, txt = "= ? ms"; end
            end
            tip = "Latencies re stimulus onset.";
            try
                L = splitlines(s.describe());
                tip = L(end);
            catch
            end
            obj.put('delayTxt',obj.Ctrl.DelayReadout,'Text',char(txt));
            obj.put('delayTip',obj.Ctrl.DelayReadout,'Tooltip',char(tip));

            b = obj.OnsetBias(isfinite(obj.OnsetBias));
            if isempty(b)
                if isempty(obj.Model) || isempty(obj.Model.Session)
                    t = "Onset bias: open a session to compute it from its files.";
                else
                    t = "Onset bias: these files do not record the stimulus rate.";
                end
                use = false;
            elseif isscalar(unique(round(b,9)))
                t = sprintf('Onset bias of this session''s files: %+.3f ms',b(1));
                use = true;
            else
                t = sprintf('Onset bias of this session''s files: %+.3f to %+.3f ms',min(b),max(b));
                use = true;
            end
            obj.put('biasTxt',obj.Ctrl.OnsetBias,'Text',char(t));
            obj.put('biasUse',obj.Ctrl.UseOnsetBias,'Enable',matlab.lang.OnOffSwitchState(use));
        end

        function syncMethod(obj)
            if ~obj.TabBuilt.Thresholds, return; end
            s = obj.Current;
            custom = s.ThresholdMethod == "custom";
            en = matlab.lang.OnOffSwitchState(custom);
            obj.put('mMetric',obj.Ctrl.ThresholdMetric,'Enable',en);
            obj.put('mModel',obj.Ctrl.ThresholdModel,'Enable',en);
            obj.put('mMode',obj.Ctrl.CriterionMode,'Enable',en);
            obj.put('mCrit',obj.Ctrl.Criterion,'Enable',en);
            obj.put('mDef',obj.Ctrl.Definition,'Text',char(s.thresholdDefinition()));
        end

        function syncSplitHalf(obj)
            if ~obj.TabBuilt.Detection, return; end
            auto = isempty(obj.Current.SplitHalfWindow);
            obj.Ctrl.SplitHalfAuto.Value = auto;
            en = matlab.lang.OnOffSwitchState(~auto);
            obj.put('shStart',obj.Ctrl.SplitHalfStart,'Enable',en);
            obj.put('shEnd',obj.Ctrl.SplitHalfEnd,'Enable',en);
            if auto
                w = obj.Current.ResponseWindow;
                obj.Ctrl.SplitHalfStart.Value = w(1);
                obj.Ctrl.SplitHalfEnd.Value = w(2);
            end
        end

        function refreshStatus(obj)
            % The problems, what changed, the profile match, and the enables.
            if ~obj.isopen(), return; end
            p = obj.problemList();
            if isempty(p)
                obj.put('probTxt',obj.Ctrl.Problems,'Text','');
                obj.put('probTip',obj.Ctrl.Problems,'Tooltip', ...
                    'What makes these settings unusable. Apply and OK stay disabled until the list is empty.');
            else
                obj.put('probTxt',obj.Ctrl.Problems,'Text',char(strjoin(p,"   ·   ")));
                % the row holds two lines; the tooltip holds them all
                obj.put('probTip',obj.Ctrl.Problems,'Tooltip',char(strjoin(p,newline)));
            end
            if obj.LastReport ~= ""
                txt = obj.LastReport;
            else
                txt = mabr.ui.analysis.SettingsDialog.changeText(obj.Baseline,obj.Current,obj.FieldLabels);
                txt = upper(extractBefore(txt,2)) + extractAfter(txt,1);
            end
            obj.put('chgTxt',obj.Ctrl.Changes,'Text',char(txt));
            s = obj.Current;
            if obj.TabBuilt.Profiles
                n = s.matchingProfile();
                if n == "", mt = "Matches no built-in profile.";
                else, mt = "Matches the built-in profile “" + n + "”."; end
                obj.put('matches',obj.Ctrl.Matches,'Text',char(mt));
                try
                    obj.put('describe',obj.Ctrl.Describe,'Value',cellstr(splitlines(s.describe())));
                catch
                end
            end
            busy = obj.isBusy();
            okOn = isempty(p) && ~busy;
            applyOn = okOn && obj.isDirty();
            obj.put('applyOn',obj.Ctrl.Apply,'Enable',matlab.lang.OnOffSwitchState(applyOn));
            obj.put('okOn',obj.Ctrl.OK,'Enable',matlab.lang.OnOffSwitchState(okOn));
            if busy
                tip = 'Wait for the running job (an analysis, a batch, an export) to finish.';
            elseif ~isempty(p)
                tip = 'Fix the problems listed above first.';
            else
                tip = 'Use these settings for the project and close.';
            end
            obj.put('okTip',obj.Ctrl.OK,'Tooltip',tip);
        end

        function p = problemList(obj)
            p = strings(0,1);
            f = fieldnames(obj.FieldErrors);
            for k = 1:numel(f)
                p(end+1,1) = obj.FieldErrors.(f{k}); %#ok<AGROW>
            end
            try
                p = [p; obj.Current.problems()];
            catch me
                p(end+1,1) = string(me.message);
            end
        end

        function tf = isDirty(obj)
            tf = ~isequaln(obj.Current.toStruct(),obj.Baseline.toStruct());
        end

        function tf = isBusy(obj)
            tf = false;
            try
                tf = ~isempty(obj.Model) && isvalid(obj.Model) && obj.Model.Busy;
            catch
            end
        end

        function put(obj,key,h,prop,v)
            % Write a property only when it differs from what was last
            % written there.
            key = char(key);
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                h.(prop) = v;
                obj.Written.(key) = v;
            catch
            end
        end

        % ---- the session the dialog was opened over -----------------------
        function readSession(obj)
            % The open session's sample rate, parameters and onset bias
            % (none without a session; the sample rate keeps its last value).
            obj.OnsetBias = zeros(1,0);
            obj.Params = strings(1,0);
            m = obj.Model;
            if isempty(m), return; end
            try
                S = m.Session;
            catch
                S = [];
            end
            if isempty(S), return; end
            try
                fs = double(S.SampleRate);
                if isscalar(fs) && isfinite(fs) && fs > 0, obj.SampleRate = fs; end
            catch
            end
            try
                pn = reshape(string(S.ParamNames),1,[]);
                obj.Params = pn(~ismember(pn,["Stimulus","AcqMode"]));
            catch
            end
            obj.OnsetBias = mabr.ui.analysis.SettingsDialog.sessionOnsetBias(S);
        end

        function onModelSettings(obj)
            % SettingsChanged: the project's settings are the new baseline.
            % With no edit pending they are shown too; an edit pending stays
            % (it is what Apply would hand over).
            if ~obj.isopen(), return; end
            try
                s = obj.Model.Settings;
            catch
                return
            end
            if isempty(s) || ~isa(s,'mabr.analysis.Settings'), return; end
            pending = obj.isDirty() || ~isempty(fieldnames(obj.FieldErrors));
            if ~pending && ~isequaln(s.toStruct(),obj.Current.toStruct())
                obj.write(s);
            end
            obj.Baseline = s;
            try
                % "Project settings — <root>" follows the root the Model has open
                if startsWith(string(obj.Figure.Name),"Project settings") && ~isempty(obj.Model.Catalog)
                    obj.Figure.Name = char("Project settings — " + string(obj.Model.Catalog.Root));
                end
            catch
            end
            obj.refreshStatus();
        end

        function onModelSession(obj)
            % SessionChanged: the onset bias, rate and parameters of the
            % session now open.
            if ~obj.isopen(), return; end
            obj.readSession();
            if obj.TabBuilt.Signal
                obj.syncDelay();
                obj.redrawFilter();
            end
            if obj.TabBuilt.Thresholds
                try
                    obj.setLevelParam(obj.Current.LevelParam);
                catch
                end
            end
        end

        function txt = callApply(obj,s)
            % txt = applyFcn(s), or applyFcn(s) when it returns nothing.
            fcn = obj.ApplyFcn;
            n = -1;
            try
                n = nargout(fcn);
            catch
            end
            if n == 0
                fcn(s);
                txt = "";
                return
            end
            try
                out = fcn(s);
            catch me
                if any(strcmp(me.identifier,{'MATLAB:maxlhs','MATLAB:TooManyOutputs'}))
                    fcn(s);
                    txt = "";
                    return
                end
                rethrow(me);
            end
            txt = "";
            if (ischar(out) || isstring(out)) && ~isempty(out)
                txt = strjoin(string(out)," ");
            end
        end

        function f = pick(obj,filter,title,mode,default)
            % A file through PickFileFcn, or the standard dialogs.
            f = "";
            if ~isempty(obj.PickFileFcn)
                f = string(obj.PickFileFcn(filter,title,mode,default));
            elseif mode == "save"
                [fn,pn] = uiputfile(char(filter),char(title),char(default));
                if ~isequal(fn,0), f = string(fullfile(pn,fn)); end
            else
                [fn,pn] = uigetfile(char(filter),char(title));
                if ~isequal(fn,0), f = string(fullfile(pn,fn)); end
            end
            if isempty(f) || ismissing(f), f = ""; end
        end

        function onKey(obj,e)
            if strcmpi(e.Key,'escape')
                obj.cancel();
            end
        end

        function closeFigure(obj)
            try
                delete(obj.Listeners);
            catch
            end
            obj.Listeners = event.listener.empty;
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisSettings');
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end

    methods (Static, Access = private)
        function m = modelOf(fcn)
            % The Model an applyFcn closes over: the analysis app hands
            % @(s) app.applySettingsFromDialog(s), whose workspace holds the
            % app (and so its Model). [] when there is none.
            m = [];
            if isempty(fcn) || ~isa(fcn,'function_handle'), return; end
            try
                info = functions(fcn);
                if ~isfield(info,'workspace') || isempty(info.workspace), return; end
                ws = info.workspace{1};
                names = fieldnames(ws);
                for k = 1:numel(names)
                    v = ws.(names{k});
                    if isa(v,'mabr.ui.analysis.Model') && isscalar(v)
                        m = v;
                        return
                    end
                    if isobject(v) && isscalar(v) && isprop(v,'Model') && isa(v.Model,'mabr.ui.analysis.Model')
                        m = v.Model;
                        return
                    end
                end
            catch
                m = [];
            end
        end

        function b = sessionOnsetBias(S)
            % The onset bias of each distinct ADC rate among the session's
            % included files, ms: one file per rate is read for the rate its
            % stimulus was played at (the files are not otherwise opened).
            b = zeros(1,0);
            try
                F = S.Files;
                if isempty(F) || height(F) == 0, return; end
                use = true(height(F),1);
                if ismember('Include',F.Properties.VariableNames), use = logical(F.Include); end
                F = F(use,:);
                [~,first] = unique(double(F.SampleRate),'stable');
                for r = reshape(first,1,[])
                    p = fullfile(string(F.folder(r)),string(F.fileName(r)));
                    if ~isfile(p), continue; end
                    rec = mabr.analysis.AbrFile.read(p,'ReadTrace',false);
                    v = mabr.ui.analysis.SettingsDialog.onsetBiasOf(rec.SampleRate,rec.DACSampleRate);
                    if isfinite(v), b(end+1) = v; end %#ok<AGROW>
                    if numel(b) >= 4, break; end
                end
            catch me
                mabr.log.vprintf(2,'SettingsDialog: onset bias not read (%s).',me.message);
            end
        end

        function v = detrendValue(t)
            v = str2double(string(t));       % "none" -> NaN
        end

        function t = detrendText(v)
            if isnan(v), t = "none"; else, t = string(sprintf('%d',v)); end
        end

        function t = numberText(v)
            if isnan(v), t = ""; else, t = string(sprintf('%.6g',v)); end
        end

        function n = splitNames(t)
            n = strtrim(split(string(t),[",",";"," "]));
            n = reshape(n(n ~= ""),1,[]);
            if isempty(n), n = string.empty(1,0); end
        end
    end
end
