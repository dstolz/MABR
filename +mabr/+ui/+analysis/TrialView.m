classdef TrialView < mabr.ui.analysis.View
% mabr.ui.analysis.TrialView  The Trials tab: one condition's single sweeps, judged one at a time.
%
%   An average is only as good as the sweeps in it, and this tab is where
%   they are looked at sweep by sweep -- the condition selected anywhere in
%   the analysis app (the Grid, the Series stack, the arrow keys), drawn as
%   four panels under one header:
%
%     (a) AnalysisTrialsImage: the sweeps as an image, time across, one row
%         per sweep (acquisition order, or sorted by the feature), coloured
%         symmetrically at the 99th percentile of |x| of the clean sweeps --
%         an artifact is a stripe. Red ticks right of a row mark it rejected
%         (grey: beyond the per-condition cap, unused), grey lines the file
%         boundaries in acquisition order, and a mark at the far right the
%         sweep a rig note was written at.
%     (b) AnalysisTrialsMean: the balanced mean with its band (SEM, or a 95%
%         bootstrap band), the +/- reference in grey -- the same sweeps with
%         balanced signs, so the response cancels and what is left is the
%         noise the mean still holds -- the polarity means when asked, the
%         condition's picked peaks, the wave search windows as a ruler along
%         the top, and the highlighted sweep behind it all in light grey.
%     (c) AnalysisTrialsFeaturePlot: one quality feature per sweep (RMS,
%         peak-to-peak, max |x| over the response window, or the template
%         amplitude/r of mabr.analysis.SingleTrial.features) against the
%         sweep's acquisition order, its time in the run, or its block (file),
%         rejected sweeps red, a running median of the clean ones, the
%         "Reject above" line, the selection, and the note ticks.
%     (d) AnalysisTrialsPanel, one of: the convergence of the residual noise
%         RN with the number of sweeps (log-log, against the 1/sqrt(N) an
%         average that works follows) with the SNR on the right axis; the
%         split-half r over random partitions with its mean and the 2.5-97.5%
%         PARTITION range (a statement about this one dataset's halves,
%         never a confidence interval); or the permutation test -- the t map
%         over the response window with its threshold and significant spans,
%         and the null distribution with the observed statistic while the
%         null is in memory (results files do not keep it).
%
%   The header (AnalysisTrialsHeader) says what the measures of the
%   analysis say about the condition: "Tone 8 kHz, 40 dB · N 512 / clean
%   503 / rejected 9 (manual 2) · RN 0.42 µV · SNR 6.1 dB · F 4.1 (p 0.001)
%   · Fsp 3.9 (p 0.002) · split-half r 0.61 (SD 0.05; partition 2.5–97.5%
%   0.50–0.71) · perm p 0.005 · I 1.42 ms 2.1 µV".
%
%   RAW DATA. Single sweeps exist only in memory: a session opened from its
%   results file has the averages, so the tab offers AnalysisTrialsLoadRaw
%   ("Load raw data (≈3 s)", Model.ensureRaw) instead of the panels.
%
%   SELECTION is the Model's (Selection.Sweeps: column indices into the
%   condition's sweeps, every sweep counted, rejected or not). A click on an
%   image row or a feature point selects that sweep, Shift+click extends
%   from the anchor IN THE ORDER SHOWN, Ctrl+click toggles (the figure calls
%   a Ctrl+click and a right click both 'alt'; the hit's Button tells them
%   apart), and a drag across the feature plot selects the x range (Esc
%   cancels it); the right-click menu also selects every sweep shown, or
%   none. Reject
%   selected (r) and Restore selected (Shift+R) are hand decisions
%   (Model.setSweepsRejected), undoable, that re-test the condition -- the
%   status line then says what the re-test changed. "Reject above" rejects
%   every sweep whose feature exceeds the value (in this condition, or in
%   every level of the series: Model.rejectAbove), and "Clear manual
%   rejections" drops the hand decisions of the condition.
%
%   TIME. Every time axis is the session's (View.timeAxis): re sound
%   arrival when a conduction delay is set, the delay named in the mean
%   axes' subtitle and the header's tooltip; the stored times stay raw.
%   The sweeps, the response window, the picks and the wave windows (written
%   and searched in the recording's time) all take the same offset off.
%
%   COST. Drawing a condition is cheap and happens at once; what needs
%   random draws -- the +/- reference, a bootstrap band, the convergence and
%   split-half resampling -- waits until nothing has changed for 150 ms
%   (timer MABR_OfflineTrials, or none when Model.AutoRefresh is false), and
%   flush() runs it now. The split-half partitions are REPLAYED from the
%   condition's own stream (Stats.conditionStream(Seed,Key), drawn by the
%   +/- reference, the power test, then the split-half, as
%   SingleTrial.summary drew them), so the histogram's mean is the r the
%   analysis stored. What the heavy pass made is kept only while the
%   session, the condition's sweeps and flags, and the options measure()
%   drew with are all unchanged -- a re-analysis with another Seed, window
%   or number of partitions, or a re-segmentation, makes it again.
%
%   CONTROLS. Four strips -- the feature and its layout; the mean's polarity,
%   band and panel (d); the selection's buttons; Reject above -- two a row
%   when the tab is at least WideControls px wide (the default window), one
%   a row when it is narrower (the window's minimum size beside the browser),
%   so nothing is ever cut off. The panel holding them re-lays them out on
%   its SizeChangedFcn, and every full render measures them too (an
%   invisible window gets no SizeChangedFcn).
%
%   Public gestures (tests drive the tab with them, as a person would):
%     clickSweep(k,mods)   k a column index into the condition's sweeps;
%                          mods "" | "shift" | "control"
%     cols = selectRange(x1,x2)  every shown sweep whose feature-plot x is
%                          within [x1 x2] (the X axis control's units)
%   and the read-only state Trial (what is drawn), Heavy, HeavyPending,
%   HeavyRuns, ColorScale, RejectValue, ControlLayout ("wide" | "narrow").
%
%   Look (pref OfflineAnalysisTrials, written only from this tab's own
%   controls): Feature, XAxis, PanelD, Band, Polarity, Order,
%   IncludeRejected.
%
%   See also mabr.ui.analysis.View, mabr.ui.analysis.Model,
%   mabr.analysis.SingleTrial, mabr.analysis.Session
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DebounceSeconds = 0.15      % a heavy recompute waits this long after a change
        MedianSpan = 21             % sweeps in the feature plot's running median
        BootstrapReplicates = 500   % replicates of the bootstrap band
        ScaleStep = 1.5             % one +/- press, on the image's colour scale
        WideControls = 1120         % px: the controls take two rows from this width up
        StripBWidth = 490           % px: the right-hand column of the two-row layout

        Features      = ["RMS","P2P","MaxAbs","TemplateAmp","TemplateR"]
        FeatureLabels = ["RMS","P–P","max |x|","Template amp","Template r"]
        XAxes         = ["sweep","time","block"]
        XAxisLabels   = ["Sweep order","Time (s)","Block"]
        PanelsD       = ["convergence","splithalf","permutation"]
        PanelDLabels  = ["Convergence","Split-half","Permutation test"]
        Bands         = ["sem","bootstrap"]
        BandLabels    = ["SEM","Bootstrap 95%"]
        Polarities    = ["balanced","positive","negative","overlay","difference"]
        PolarityLabels = ["Balanced","+","−","+/− overlay","Difference"]
        Orders        = ["acquisition","feature"]
        OrderLabels   = ["Acquisition","By feature"]

        NoSessionText = "Open a session from the browser (double-click, Enter, or Open)."
        NoConditionText = "Select a condition in the Grid or Series tab (or with the arrow keys)."
        FewText   = "Fewer than two clean sweeps — nothing to show."
        NoNullText = "Null distribution not saved — re-run detection to see it"
        PrefKey   = "OfflineAnalysisTrials"
    end

    properties (SetAccess = private)
        Trial = []                      % what is drawn: the condition's sweeps and derived values
        Heavy = []                      % what the debounced pass computed (Stamp, Ref, Boot, Conv, Split)
        HeavyPending (1,1) logical = false   % a heavy pass is waiting (flush() runs it)
        HeavyRuns (1,1) double = 0      % heavy passes run (tests)
        ColorScale (1,1) double = 1     % image contrast: +/- multiply it by ScaleStep
        RejectValue (1,1) double = NaN  % the "Reject above" value in display units (NaN = suggest)
        ControlLayout (1,1) string = "" % "wide" (two rows of controls) | "narrow" (four)
    end

    properties (Access = private)
        Timer = []
        Drag = []
        AnchorCol (1,1) double = NaN    % the anchor of Shift+click, in the order shown
        NotesFor (1,1) string = ""      % session key the cached notes belong to
        NotesCache = []
        WaveG = struct()                % wave name -> struct Patch, Label, Peak, Trough
    end

    % =====================================================================
    methods
        function delete(obj)
            obj.stopTimer();
            try
                if ~isempty(obj.Timer) && isvalid(obj.Timer), delete(obj.Timer); end
            catch
            end
            obj.Timer = [];
            obj.endDrag();
        end

        function build(obj)
            St = mabr.ui.analysis.Style;
            g = uigridlayout(obj.Parent,[4 1],'Padding',[6 4 6 2],'RowSpacing',4, ...
                'BackgroundColor',St.Panel);
            g.RowHeight = {'fit',2*26 + 4,'1x',16};
            g.Layout.Row = 1;  g.Layout.Column = 1;
            obj.Handles.Root = g;
            h = uilabel(g,'Text',' ','WordWrap','on','FontColor',St.Ink, ...
                'Tag','AnalysisTrialsHeader', ...
                'Tooltip','The selected condition: its sweep counts and the single-trial measures of the analysis.');
            h.Layout.Row = 1;
            obj.Handles.Header = h;
            obj.buildControls(g);
            obj.buildPanels(g);
            obj.buildRawPanel(g);
            hint = uilabel(g,'Text',char(mabr.ui.analysis.Commands.hint("trials")), ...
                'FontColor',St.Muted,'FontSize',10,'Tag','AnalysisTrialsHints');
            hint.Layout.Row = 4;
            obj.Handles.Hints = hint;
            obj.setControlLayout("wide");
            obj.syncLook();
        end

        function refresh(obj,what,keys)
            % Redraw what the Model's change touches (see the class help);
            % words this tab does not draw return at once.
            if nargin < 3, keys = strings(0,1); end
            what = string(what);
            switch what
                case {"message","save","busy","queue","status","labels","columns", ...
                        "pools","curation","thresholds","files"}
                    % (nothing this tab draws; "files" is a staged file
                    % selection, which changes the sweeps only once applied --
                    % and that arrives as "all")
                    return
                case "idle"
                    if obj.HeavyPending, obj.scheduleHeavy(); end
                    return
                case "sweeps"
                    obj.drawSelection();
                    return
                case "wave"
                    obj.redrawPeaks();
                    return
                case "peaks"
                    if isempty(keys) || isempty(obj.Trial) || any(keys == obj.Trial.Key)
                        obj.redrawPeaks();
                    end
                    return
                case {"condition","series","level"}
                    if ~isempty(obj.Trial) && obj.Model.Selection.ConditionKey == obj.Trial.Key ...
                            && ~isempty(obj.Model.Session)
                        obj.drawSelection();
                        return
                    end
                otherwise
                    if what ~= "all" && ~isempty(keys) && ~isempty(obj.Trial) && ...
                            ~any(keys == obj.Trial.Key) && ...
                            obj.Model.Selection.ConditionKey == obj.Trial.Key
                        return
                    end
            end
            obj.renderGuarded(@() obj.renderAll());
        end

        function handled = onCommand(obj,id)
            % The tab's own keys: +/- scale the image's colour, Ctrl+0
            % resets it, Esc cancels a drag across the feature plot (and
            % only then: otherwise Esc is the app's). Everything else (r,
            % Shift+R, the arrows) is the Model's.
            handled = true;
            switch string(id)
                case "nav.escape"
                    handled = ~isempty(obj.Drag);
                    obj.endDrag();
                    return
                case "view.scaleUp",   obj.ColorScale = obj.ColorScale*obj.ScaleStep;
                case "view.scaleDown", obj.ColorScale = obj.ColorScale/obj.ScaleStep;
                case "view.resetZoom", obj.ColorScale = 1;
                otherwise
                    handled = false;
                    return
            end
            obj.applyColorLimits();
        end

        function flush(obj)
            % Catch up a dirty tab, then run any waiting heavy pass now.
            flush@mabr.ui.analysis.View(obj);
            if obj.HeavyPending
                obj.stopTimer();
                obj.runHeavy();
            end
        end

        function savePrefs(obj)
            % Remember the look (pref OfflineAnalysisTrials) -- only from this
            % tab's own controls.
            mabr.ui.analysis.TrialView.saveDefaults(obj.displaySettings());
        end

        % ---- gestures ----------------------------------------------------
        function clickSweep(obj,k,mods)
            % Click sweep k (a column index into the condition's sweeps):
            % mods "" selects it, "shift" extends from the anchor in the
            % order the image shows, "control" toggles it.
            arguments
                obj
                k (1,1) double {mustBeInteger,mustBePositive}
                mods (1,:) string = ""
            end
            D = obj.Trial;
            if isempty(D) || k > D.N
                error('mabr:ui:TrialView:noSweep','There is no sweep %d to click.',k);
            end
            obj.clickAt(k,lower(mods),D.Display);
        end

        function cols = selectRange(obj,x1,x2)
            % Select every shown sweep whose feature-plot x lies within
            % [x1 x2] (units of the X axis control: sweep number, seconds,
            % block) -- what a drag across the feature plot does.
            arguments
                obj
                x1 (1,1) double
                x2 (1,1) double
            end
            D = obj.Trial;
            cols = zeros(1,0);
            if isempty(D), return; end
            lo = min(x1,x2);  hi = max(x1,x2);
            in = D.Visible & isfinite(D.PX) & D.PX >= lo & D.PX <= hi;
            cols = find(in);
            [~,o] = sort(D.PX(cols));
            cols = cols(o);
            obj.Model.selectSweeps(cols);
            if isempty(cols), obj.AnchorCol = NaN; else, obj.AnchorCol = cols(1); end
            obj.drawSelection();
        end
    end

    % =====================================================================
    methods (Static)
        function d = factoryDefaults()
            % The tab's look as it first opens.
            d = struct('Feature',"MaxAbs",'XAxis',"sweep",'PanelD',"convergence", ...
                'Band',"sem",'Polarity',"balanced",'Order',"acquisition",'IncludeRejected',true);
        end

        function d = loadDefaults()
            % The look the user last left (pref OfflineAnalysisTrials),
            % forgiving of a pref from another version.
            d = mabr.ui.analysis.View.loadLook(mabr.ui.analysis.TrialView.PrefKey, ...
                mabr.ui.analysis.TrialView.factoryDefaults());
            d = mabr.ui.analysis.TrialView.sanitizeLook(d);
        end

        function saveDefaults(d)
            % Remember a look -- from this tab's controls, or a configuration.
            mabr.ui.analysis.View.saveLook(mabr.ui.analysis.TrialView.PrefKey, ...
                mabr.ui.analysis.TrialView.sanitizeLook(d));
        end

        function d = sanitizeLook(d)
            % Every field one this tab can draw; anything else the factory's.
            f0 = mabr.ui.analysis.TrialView.factoryDefaults();
            if ~isstruct(d) || ~isscalar(d), d = f0; return; end
            allowed = struct('Feature',mabr.ui.analysis.TrialView.Features, ...
                'XAxis',mabr.ui.analysis.TrialView.XAxes,'PanelD',mabr.ui.analysis.TrialView.PanelsD, ...
                'Band',mabr.ui.analysis.TrialView.Bands,'Polarity',mabr.ui.analysis.TrialView.Polarities, ...
                'Order',mabr.ui.analysis.TrialView.Orders);
            out = f0;
            for f = string(fieldnames(allowed)).'
                if ~isfield(d,f), continue; end
                try
                    v = string(d.(f));
                    if isscalar(v) && any(allowed.(f) == v), out.(f) = v; end
                catch
                end
            end
            if isfield(d,'IncludeRejected')
                try
                    v = d.IncludeRejected;
                    if isscalar(v) && (islogical(v) || isnumeric(v)) && ~isnan(double(v))
                        out.IncludeRejected = logical(v);
                    end
                catch
                end
            end
            d = out;
        end
    end

    % =====================================================================
    methods (Access = private)
        % ---- building ----------------------------------------------------
        function buildControls(obj,g)
            % The tab's controls as four strips -- (A) what is plotted per
            % sweep, (B) how the mean and panel (d) are drawn, (C) what is
            % done to the selection, (D) Reject above -- two strips a row
            % when the tab is wide enough, one a row when it is not (at the
            % window's minimum size the tab beside the browser is about
            % 780 px, too little for two). The panel's SizeChangedFcn decides.
            St = mabr.ui.analysis.Style;
            cp = uipanel(g,'BorderType','none','BackgroundColor',St.Panel, ...
                'AutoResizeChildren','off','Tag','AnalysisTrialsControls');
            cp.Layout.Row = 2;
            cp.SizeChangedFcn = @(s,~) obj.onControlsResized(s);
            cg = uigridlayout(cp,[2 2],'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',12, ...
                'BackgroundColor',St.Panel);
            obj.Handles.ControlsPanel = cp;
            obj.Handles.Controls = cg;
            strip = @(n) uigridlayout(cg,[1 n],'Padding',[0 0 0 0],'ColumnSpacing',5, ...
                'BackgroundColor',St.Panel);

            % (A) the feature and how its sweeps are laid out
            a = strip(8);
            a.ColumnWidth = {'fit',105,'fit',105,'fit',100,'fit','1x'};
            obj.rowLabel(a,'Feature');
            obj.Handles.Feature = obj.lookDropdown(a,'Feature', ...
                mabr.ui.analysis.TrialView.FeatureLabels,mabr.ui.analysis.TrialView.Features,'AnalysisTrialsFeature', ...
                'The per-sweep feature the feature plot shows, the image can be sorted by, and Reject above compares.');
            obj.rowLabel(a,'X axis');
            obj.Handles.XAxis = obj.lookDropdown(a,'XAxis', ...
                mabr.ui.analysis.TrialView.XAxisLabels,mabr.ui.analysis.TrialView.XAxes,'AnalysisTrialsXAxis', ...
                'What the feature plot''s x axis counts: sweeps in acquisition order, seconds into the run, or the block (file) each sweep came from.');
            obj.rowLabel(a,'Order');
            obj.Handles.Order = obj.lookDropdown(a,'Order', ...
                mabr.ui.analysis.TrialView.OrderLabels,mabr.ui.analysis.TrialView.Orders,'AnalysisTrialsOrder', ...
                'The order of the image''s rows: as acquired, or sorted by the feature (largest at the bottom).');
            obj.Handles.IncludeRejected = uicheckbox(a,'Text','Include rejected','Tag','AnalysisTrialsIncludeRejected', ...
                'Tooltip','Show rejected sweeps in the image and the feature plot (marked red), so they can be selected and restored.', ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onLook('IncludeRejected',logical(s.Value))));
            obj.Handles.StripA = a;

            % (B) the mean and panel (d)
            b = strip(8);
            obj.spacer(b,1);
            obj.rowLabel(b,'Polarity');
            obj.Handles.Polarity = obj.lookDropdown(b,'Polarity', ...
                mabr.ui.analysis.TrialView.PolarityLabels,mabr.ui.analysis.TrialView.Polarities,'AnalysisTrialsPolarity', ...
                'Which mean is drawn: polarity-balanced, one polarity, both overlaid, or their difference (what follows the stimulus sign).');
            obj.rowLabel(b,'Band');
            obj.Handles.Band = obj.lookDropdown(b,'Band', ...
                mabr.ui.analysis.TrialView.BandLabels,mabr.ui.analysis.TrialView.Bands,'AnalysisTrialsBand', ...
                'The band around the mean: its standard error, or a 95% bootstrap band over the sweeps.');
            obj.rowLabel(b,'Panel');
            obj.Handles.PanelD = obj.lookDropdown(b,'PanelD', ...
                mabr.ui.analysis.TrialView.PanelDLabels,mabr.ui.analysis.TrialView.PanelsD,'AnalysisTrialsPanelD', ...
                'The fourth panel: the noise against the number of sweeps, the split-half correlation, or the permutation test.');
            obj.spacer(b,8);
            obj.Handles.StripB = b;

            % (C) the selection and what is done to it
            c = strip(5);
            c.ColumnWidth = {'fit','fit','fit','fit','1x'};
            obj.Handles.Reject = uibutton(c,'Text','Reject selected (r)','Tag','AnalysisTrialsReject', ...
                'Tooltip','Reject the selected sweeps (r): they leave the average and the condition is re-tested.', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.rejectSelected(true)));
            mabr.ui.analysis.Style.setButtonIcon(obj.Handles.Reject,'reject','left');
            obj.Handles.Restore = uibutton(c,'Text','Restore selected (Shift+R)','Tag','AnalysisTrialsRestore', ...
                'Tooltip','Restore the selected sweeps (Shift+R) -- a hand decision that wins over the rig''s and the criterion''s flags.', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.rejectSelected(false)));
            mabr.ui.analysis.Style.setButtonIcon(obj.Handles.Restore,'restore','left');
            obj.Handles.ClearManual = uibutton(c,'Text','Clear manual rejections','Tag','AnalysisTrialsClearManual', ...
                'Tooltip','Drop every hand rejection and restore of this condition; the rig''s and the criterion''s flags stand.', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.clearManual()));
            mabr.ui.analysis.Style.setButtonIcon(obj.Handles.ClearManual,'trash','left');
            obj.Handles.SelectionLabel = uilabel(c,'Text','No sweeps selected','Tag','AnalysisTrialsSelection', ...
                'FontColor',St.Muted, ...
                'Tooltip','Click a sweep (image row or feature point), Shift+click to extend, Ctrl+click to toggle, drag across the feature plot for a range.');
            obj.Handles.StripC = c;

            % (D) Reject above
            d = strip(6);
            obj.spacer(d,1);
            obj.Handles.RejectAbove = uibutton(d,'Text','Reject above','Tag','AnalysisTrialsRejectAbove', ...
                'Tooltip','Reject every sweep of this condition whose feature is above the value beside it.', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.rejectAbove(false)));
            mabr.ui.analysis.Style.setButtonIcon(obj.Handles.RejectAbove,'reject','left');
            obj.Handles.RejectAboveValue = uieditfield(d,'numeric','Value',0,'Limits',[0 Inf], ...
                'Tag','AnalysisTrialsRejectAboveValue', ...
                'Tooltip','The feature value Reject above compares with (µV for RMS, P–P and max |x|); drawn as the dashed line on the feature plot.', ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onRejectValue(s.Value)));
            obj.Handles.RejectAboveUnit = uilabel(d,'Text','µV','FontColor',St.Muted, ...
                'Tag','AnalysisTrialsRejectAboveUnit');
            obj.Handles.RejectAboveSeries = uibutton(d,'Text','…in every level of this series', ...
                'Tag','AnalysisTrialsRejectAboveSeries', ...
                'Tooltip','Reject the sweeps above the value in every level of this series, each level re-tested.', ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.rejectAbove(true)));
            obj.spacer(d,6);
            obj.Handles.StripD = d;
        end

        function onControlsResized(obj,src)
            % The controls' panel changed size (MATLAB calls this only for
            % a visible window; renderAll asks too).
            if ~isvalid(obj), return; end
            try
                obj.fitControls(src.Position(3));
            catch me
                mabr.log.vprintf(2,'Trials view: controls not re-laid out (%s).',me.message);
            end
        end

        function fitControls(obj,w)
            % Lay the controls out for a width W (px; the panel's own when
            % omitted). 300 px or less is the panel before its first
            % layout, not a size, and leaves the layout as it is.
            if nargin < 2
                try
                    w = obj.Handles.ControlsPanel.Position(3);
                catch
                    return
                end
            end
            if ~(isfinite(w) && w > 300), return; end
            if w >= mabr.ui.analysis.TrialView.WideControls
                obj.setControlLayout("wide");
            else
                obj.setControlLayout("narrow");
            end
        end

        function setControlLayout(obj,mode)
            % "wide": strips A | B over C | D, B and D right-aligned;
            % "narrow": A, B, C, D one a row, all left-aligned.
            if mode == obj.ControlLayout, return; end
            H = obj.Handles;
            obj.ControlLayout = mode;
            if mode == "wide"
                n = 2;
                H.Controls.RowHeight = {26,26};
                H.Controls.ColumnWidth = {'1x',mabr.ui.analysis.TrialView.StripBWidth};
                place = [1 1; 1 2; 2 1; 2 2];
                lead = '1x';  trail = 0;
            else
                n = 4;
                H.Controls.RowHeight = {26,26,26,26};
                H.Controls.ColumnWidth = {'1x'};
                place = [1 1; 2 1; 3 1; 4 1];
                lead = 0;  trail = '1x';
            end
            s = [H.StripA H.StripB H.StripC H.StripD];
            for k = 1:4
                s(k).Layout.Row = place(k,1);
                s(k).Layout.Column = place(k,2);
            end
            H.StripB.ColumnWidth = {lead,'fit',100,'fit',112,'fit',125,trail};
            H.StripD.ColumnWidth = {lead,'fit',70,'fit','fit',trail};
            H.Root.RowHeight{2} = n*26 + (n - 1)*4;
        end

        function buildPanels(obj,g)
            St = mabr.ui.analysis.Style;
            pg = uigridlayout(g,[2 2],'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',4, ...
                'BackgroundColor',St.Panel);
            pg.Layout.Row = 3;
            obj.Handles.Panels = pg;
            fig = ancestor(obj.Parent,'figure');

            % (a) the image
            [p,ax] = obj.plotPanel(pg,1,1,'AnalysisTrialsImage');
            obj.Handles.ImagePanel = p;
            obj.Handles.ImageAxes = ax;
            ax.YDir = 'reverse';
            ax.Layer = 'top';
            colormap(ax,mabr.ui.analysis.TrialView.divergingMap(256));
            obj.Handles.Image = image(ax,'CData',NaN,'XData',[0 1],'YData',[1 1], ...
                'CDataMapping','scaled','AlphaData',0,'Tag','TrialsImage');
            obj.Handles.ImageFiles = line(ax,NaN,NaN,'Color',[0.55 0.55 0.55],'LineWidth',0.75, ...
                'PickableParts','none','Tag','TrialsFileBoundaries','DisplayName','file boundaries');
            obj.Handles.ImageRejected = line(ax,NaN,NaN,'Color',St.Error,'LineWidth',4, ...
                'PickableParts','none','Tag','TrialsRejectedTicks','DisplayName','rejected');
            obj.Handles.ImageExcess = line(ax,NaN,NaN,'Color',St.SubThreshold,'LineWidth',4, ...
                'PickableParts','none','Tag','TrialsExcessTicks','DisplayName','unused (beyond the cap)');
            obj.Handles.ImageSelection = line(ax,NaN,NaN,'Color',St.Accent,'LineWidth',4, ...
                'PickableParts','none','Tag','TrialsImageSelection','DisplayName','selected');
            obj.Handles.ImageNotes = line(ax,NaN,NaN,'LineStyle','none','Marker','<', ...
                'MarkerSize',6,'MarkerFaceColor',St.AccentText,'MarkerEdgeColor',St.AccentText, ...
                'PickableParts','none','Tag','TrialsImageNotes','DisplayName','notes');
            try
                % (the unit is in the title: a colour bar's Label costs half
                % a second to make)
                obj.Handles.ImageColorbar = colorbar(ax);
            catch
                obj.Handles.ImageColorbar = [];
            end
            ax.ButtonDownFcn = obj.viewWrap(@(~,e) obj.onImageDown(e));
            obj.Handles.Image.ButtonDownFcn = obj.viewWrap(@(~,e) obj.onImageDown(e));
            cm = obj.sweepMenu(fig,ax);
            obj.Handles.Image.ContextMenu = cm;

            % (b) the mean
            [p,ax] = obj.plotPanel(pg,1,2,'AnalysisTrialsMean');
            obj.Handles.MeanPanel = p;
            obj.Handles.MeanAxes = ax;
            obj.Handles.MeanWindow = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',[0.93 0.93 0.93], ...
                'EdgeColor','none','PickableParts','none','Tag','TrialsResponseWindow');
            obj.Handles.MeanBand = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',St.DataBlue, ...
                'FaceAlpha',0.22,'EdgeColor','none','PickableParts','none','Tag','TrialsMeanBand');
            obj.Handles.MeanZero = line(ax,NaN,NaN,'Color',[0.75 0.75 0.75],'LineWidth',0.5, ...
                'PickableParts','none','Tag','TrialsMeanZero');
            obj.Handles.MeanSweep = line(ax,NaN,NaN,'Color',[0.82 0.82 0.82],'LineWidth',0.75, ...
                'PickableParts','none','Tag','TrialsHighlightedSweep','DisplayName','highlighted sweep');
            obj.Handles.MeanRef = line(ax,NaN,NaN,'Color',St.Muted,'LineWidth',1, ...
                'PickableParts','none','Tag','TrialsPlusMinus','DisplayName','± reference');
            obj.Handles.MeanPos = line(ax,NaN,NaN,'Color',St.OkabeIto(1,:),'LineWidth',1.5, ...
                'PickableParts','none','Tag','TrialsMeanPositive','DisplayName','+ mean');
            obj.Handles.MeanNeg = line(ax,NaN,NaN,'Color',St.OkabeIto(2,:),'LineWidth',1.5, ...
                'PickableParts','none','Tag','TrialsMeanNegative','DisplayName','− mean');
            obj.Handles.MeanLine = line(ax,NaN,NaN,'Color',St.DataBlue,'LineWidth',1.5, ...
                'PickableParts','none','Tag','TrialsMean','DisplayName','mean');
            obj.Handles.MeanFew = text(ax,0.5,0.5,'','Units','normalized','HorizontalAlignment','center', ...
                'Color',St.Muted,'FontSize',11,'Tag','TrialsFewSweeps','Interpreter','none');
            ylabel(ax,'µV');
            cm = uicontextmenu(fig);
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            ax.ContextMenu = cm;

            % (c) the feature plot
            [p,ax] = obj.plotPanel(pg,2,1,'AnalysisTrialsFeaturePlot');
            obj.Handles.FeaturePanel = p;
            obj.Handles.FeatureAxes = ax;
            obj.Handles.FeatureDrag = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',St.Accent, ...
                'FaceAlpha',0.15,'EdgeColor',St.Accent,'PickableParts','none','Visible','off', ...
                'Tag','TrialsFeatureDrag');
            obj.Handles.FeatureNotes = line(ax,NaN,NaN,'LineStyle',':','Color',St.AccentText, ...
                'LineWidth',1,'PickableParts','none','Tag','TrialsFeatureNotes','DisplayName','notes');
            obj.Handles.FeatureExcess = line(ax,NaN,NaN,'LineStyle','none','Marker','.', ...
                'MarkerSize',8,'Color',St.SubThreshold,'PickableParts','none', ...
                'Tag','TrialsFeatureExcess','DisplayName','unused');
            obj.Handles.FeatureClean = line(ax,NaN,NaN,'LineStyle','none','Marker','.', ...
                'MarkerSize',9,'Color',St.DataBlue,'PickableParts','none', ...
                'Tag','TrialsFeatureClean','DisplayName','clean');
            obj.Handles.FeatureRejected = line(ax,NaN,NaN,'LineStyle','none','Marker','.', ...
                'MarkerSize',11,'Color',St.Error,'PickableParts','none', ...
                'Tag','TrialsFeatureRejected','DisplayName','rejected');
            obj.Handles.FeatureMedian = line(ax,NaN,NaN,'Color',St.Ink,'LineWidth',1.25, ...
                'PickableParts','none','Tag','TrialsFeatureMedian','DisplayName','running median');
            obj.Handles.FeatureAbove = line(ax,NaN,NaN,'LineStyle','--','Color',St.Warn, ...
                'LineWidth',1,'PickableParts','none','Tag','TrialsRejectAboveLine', ...
                'DisplayName','reject above');
            % a ring round each selected point, so its colour (clean,
            % rejected, unused) still shows through
            obj.Handles.FeatureSelection = line(ax,NaN,NaN,'LineStyle','none','Marker','o', ...
                'MarkerSize',8,'LineWidth',1.5,'MarkerEdgeColor',St.Accent,'MarkerFaceColor','none', ...
                'PickableParts','none','Tag','TrialsFeatureSelection','DisplayName','selected');
            ax.ButtonDownFcn = obj.viewWrap(@(~,e) obj.onFeatureDown(e));
            obj.sweepMenu(fig,ax);

            % (d) convergence / split-half / permutation
            % (three sub-panels in one grid cell, one shown at a time)
            p = uipanel(pg,'Tag','AnalysisTrialsPanel','BorderType','line','BackgroundColor',[1 1 1]);
            p.Layout.Row = 2;  p.Layout.Column = 2;
            obj.Handles.DPanel = p;
            dg = uigridlayout(p,[1 1],'Padding',[0 0 0 0],'BackgroundColor',[1 1 1]);
            obj.buildConvergence(dg,fig);
            obj.buildSplitHalf(dg,fig);
            obj.buildPermutation(dg,fig);
        end

        function buildConvergence(obj,p,fig)
            St = mabr.ui.analysis.Style;
            sp = uipanel(p,'BorderType','none','BackgroundColor',[1 1 1],'AutoResizeChildren','off', ...
                'Tag','AnalysisTrialsConvergence');
            sp.Layout.Row = 1;  sp.Layout.Column = 1;
            ax = axes(sp,'Units','normalized','OuterPosition',[0 0 1 1],'FontSize',9,'Box','on', ...
                'TitleFontSizeMultiplier',1,'Tag','AnalysisTrialsConvergenceAxes');
            yyaxis(ax,'left');
            obj.Handles.ConvGuide = line(ax,NaN,NaN,'LineStyle','--','Color',St.Muted, ...
                'PickableParts','none','Tag','TrialsConvergenceGuide','DisplayName','1/√N');
            obj.Handles.ConvRN = line(ax,NaN,NaN,'Marker','o','MarkerSize',4,'Color',St.DataBlue, ...
                'MarkerFaceColor',St.DataBlue,'PickableParts','none','Tag','TrialsConvergenceRN', ...
                'DisplayName','RN (µV)');
            ax.YScale = 'log';
            ylabel(ax,'RN (µV)');
            yyaxis(ax,'right');
            obj.Handles.ConvSNR = line(ax,NaN,NaN,'Marker','s','MarkerSize',4,'Color',St.AccentText, ...
                'PickableParts','none','Tag','TrialsConvergenceSNR','DisplayName','SNR (dB)');
            ylabel(ax,'SNR (dB)');
            try
                ax.YAxis(1).Color = St.DataBlue;
                ax.YAxis(2).Color = St.AccentText;
            catch
            end
            yyaxis(ax,'left');
            ax.XScale = 'log';
            xlabel(ax,'Clean sweeps (acquisition order)');
            obj.Handles.ConvNote = text(ax,0.5,0.5,'','Units','normalized','HorizontalAlignment','center', ...
                'Color',St.Muted,'FontSize',10,'Tag','TrialsConvergenceNote','Interpreter','none');
            mabr.ui.analysis.TrialView.quietAxes(ax);
            cm = uicontextmenu(fig);
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            ax.ContextMenu = cm;
            obj.Handles.ConvPanel = sp;
            obj.Handles.ConvAxes = ax;
        end

        function buildSplitHalf(obj,p,fig)
            St = mabr.ui.analysis.Style;
            sp = uipanel(p,'BorderType','none','BackgroundColor',[1 1 1],'Visible','off', ...
                'AutoResizeChildren','off','Tag','AnalysisTrialsSplitHalf');
            sp.Layout.Row = 1;  sp.Layout.Column = 1;
            ax = axes(sp,'Units','normalized','OuterPosition',[0 0 1 1],'FontSize',9,'Box','on', ...
                'TitleFontSizeMultiplier',1,'Tag','AnalysisTrialsSplitHalfAxes');
            obj.Handles.SplitFill = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',St.DataBlue, ...
                'FaceAlpha',0.35,'EdgeColor','none','PickableParts','none','Tag','TrialsSplitHalfFill');
            obj.Handles.SplitOutline = line(ax,NaN,NaN,'Color',St.DataBlue,'LineWidth',1, ...
                'PickableParts','none','Tag','TrialsSplitHalfHistogram','DisplayName','partitions');
            obj.Handles.SplitBounds = line(ax,NaN,NaN,'LineStyle','--','Color',St.Muted,'LineWidth',1, ...
                'PickableParts','none','Tag','TrialsSplitHalfBounds','DisplayName','partition 2.5–97.5%');
            obj.Handles.SplitMean = line(ax,NaN,NaN,'Color',St.Ink,'LineWidth',1.75, ...
                'PickableParts','none','Tag','TrialsSplitHalfMean','DisplayName','mean r');
            obj.Handles.SplitBoundsLabel = text(ax,NaN,NaN,'partition 2.5–97.5%', ...
                'HorizontalAlignment','center','VerticalAlignment','bottom','Color',St.Muted, ...
                'FontSize',9,'Tag','TrialsSplitHalfBoundsLabel','Interpreter','none');
            obj.Handles.SplitNote = text(ax,0.5,0.5,'','Units','normalized','HorizontalAlignment','center', ...
                'Color',St.Muted,'FontSize',10,'Tag','TrialsSplitHalfNote','Interpreter','none');
            xlabel(ax,'Split-half r');
            ylabel(ax,'Partitions');
            mabr.ui.analysis.TrialView.quietAxes(ax);
            cm = uicontextmenu(fig);
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            ax.ContextMenu = cm;
            obj.Handles.SplitPanel = sp;
            obj.Handles.SplitAxes = ax;
        end

        function buildPermutation(obj,p,fig)
            St = mabr.ui.analysis.Style;
            sp = uipanel(p,'BorderType','none','BackgroundColor',[1 1 1],'Visible','off', ...
                'AutoResizeChildren','off','Tag','AnalysisTrialsPermutation');
            sp.Layout.Row = 1;  sp.Layout.Column = 1;
            ax = axes(sp,'Units','normalized','OuterPosition',[0 0.5 1 0.5],'FontSize',9,'Box','on', ...
                'TitleFontSizeMultiplier',1,'Tag','AnalysisTrialsPermTAxes');
            obj.Handles.PermSpans = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',St.Accent, ...
                'FaceAlpha',0.3,'EdgeColor','none','PickableParts','none','Tag','TrialsPermSignificant');
            obj.Handles.PermZero = line(ax,NaN,NaN,'Color',[0.75 0.75 0.75],'LineWidth',0.5, ...
                'PickableParts','none','Tag','TrialsPermZero');
            obj.Handles.PermThreshold = line(ax,NaN,NaN,'LineStyle','--','Color',St.Muted, ...
                'PickableParts','none','Tag','TrialsPermThreshold','DisplayName','±t threshold');
            obj.Handles.PermT = line(ax,NaN,NaN,'Color',St.DataBlue,'LineWidth',1.25, ...
                'PickableParts','none','Tag','TrialsPermT','DisplayName','t');
            obj.Handles.PermTNote = text(ax,0.5,0.5,'','Units','normalized','HorizontalAlignment','center', ...
                'Color',St.Muted,'FontSize',10,'Tag','TrialsPermTNote','Interpreter','none');
            ylabel(ax,'t');
            mabr.ui.analysis.TrialView.quietAxes(ax);
            obj.Handles.PermTAxes = ax;
            ax2 = axes(sp,'Units','normalized','OuterPosition',[0 0 1 0.47],'FontSize',9,'Box','on', ...
                'TitleFontSizeMultiplier',1,'Tag','AnalysisTrialsPermNullAxes');
            obj.Handles.PermNullFill = patch(ax2,'XData',NaN,'YData',NaN,'FaceColor',St.SubThreshold, ...
                'FaceAlpha',0.6,'EdgeColor','none','PickableParts','none','Tag','TrialsPermNullFill');
            obj.Handles.PermNull = line(ax2,NaN,NaN,'Color',St.Muted,'LineWidth',1, ...
                'PickableParts','none','Tag','TrialsPermNull','DisplayName','null');
            obj.Handles.PermObserved = line(ax2,NaN,NaN,'Color',St.Error,'LineWidth',2, ...
                'PickableParts','none','Tag','TrialsPermObserved','DisplayName','observed');
            obj.Handles.PermNullText = text(ax2,0.5,0.5,'','Units','normalized', ...
                'HorizontalAlignment','center','Color',St.Muted,'FontSize',10, ...
                'Tag','TrialsPermNullText','Interpreter','none');
            ylabel(ax2,'Permutations');
            mabr.ui.analysis.TrialView.quietAxes(ax2);
            obj.Handles.PermNullAxes = ax2;
            obj.Handles.PermPanel = sp;
            for a = [ax ax2]
                cm = uicontextmenu(fig);
                mabr.ui.analysis.FigureExport.addContextItems(cm,@() obj.Handles.PermPanel,obj.Host);
                a.ContextMenu = cm;
            end
        end

        function buildRawPanel(obj,g)
            St = mabr.ui.analysis.Style;
            rp = uipanel(g,'BorderType','none','BackgroundColor',St.Panel,'Visible','off', ...
                'Tag','AnalysisTrialsRawPanel');
            rp.Layout.Row = 3;
            rg = uigridlayout(rp,[4 3],'BackgroundColor',St.Panel);
            rg.RowHeight = {'1x','fit',34,'1x'};
            rg.ColumnWidth = {'1x',280,'1x'};
            t = uilabel(rg,'Text',['The Trials tab shows single sweeps, and this session was opened ' ...
                'from its results file, which keeps only the averages.'], ...
                'WordWrap','on','HorizontalAlignment','center','FontSize',13,'FontColor',St.Muted, ...
                'Tag','AnalysisTrialsRawText');
            t.Layout.Row = 2;  t.Layout.Column = [1 3];
            obj.Handles.LoadRaw = uibutton(rg,'Text','Load raw data','Tag','AnalysisTrialsLoadRaw', ...
                'Tooltip',['Read the .abr files again and segment them with the settings this session ' ...
                'was analysed with; every result and edit is kept.'], ...
                'ButtonPushedFcn',obj.viewWrap(@(~,~) obj.Model.ensureRaw()));
            obj.Handles.LoadRaw.Layout.Row = 3;  obj.Handles.LoadRaw.Layout.Column = 2;
            mabr.ui.analysis.Style.setButtonIcon(obj.Handles.LoadRaw,'load','left');
            obj.Handles.RawPanel = rp;
            obj.Handles.RawText = t;
        end

        function [p,ax] = plotPanel(obj,pg,row,col,tag)
            % A white panel holding one classic axes that fills it. The
            % panel's AutoResizeChildren is off: left on, a uifigure rescales
            % the axes from the size the panel had before the grid laid it
            % out, and a normalized axes stays at a corner of its panel.
            p = uipanel(pg,'Tag',tag,'BorderType','line','BackgroundColor',[1 1 1], ...
                'AutoResizeChildren','off');
            p.Layout.Row = row;  p.Layout.Column = col;
            ax = axes(p,'Units','normalized','OuterPosition',[0 0 1 1],'FontSize',9,'Box','on', ...
                'TitleFontSizeMultiplier',1,'Tag',[tag 'Axes']);
            mabr.ui.analysis.TrialView.quietAxes(ax);
            obj.forgetWritten([tag '_']);
        end

        function cm = sweepMenu(obj,fig,ax)
            % The context menu of a plot of sweeps: what can be done to the
            % selection, then the three export items every plot ends with.
            cm = uicontextmenu(fig);
            uimenu(cm,'Text','Reject selected (r)','Tag','AnalysisTrialsMenuReject', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.rejectSelected(true)));
            uimenu(cm,'Text','Restore selected (Shift+R)','Tag','AnalysisTrialsMenuRestore', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.rejectSelected(false)));
            uimenu(cm,'Text','Select all shown','Separator','on','Tag','AnalysisTrialsMenuSelectAll', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.selectShown()));
            uimenu(cm,'Text','Select none','Tag','AnalysisTrialsMenuSelectNone', ...
                'MenuSelectedFcn',obj.viewWrap(@(~,~) obj.Model.selectSweeps(zeros(1,0))));
            mabr.ui.analysis.FigureExport.addContextItems(cm,ax,obj.Host);
            ax.ContextMenu = cm;
        end

        function h = rowLabel(~,parent,text)
            h = uilabel(parent,'Text',text,'FontColor',mabr.ui.analysis.Style.Muted, ...
                'HorizontalAlignment','right');
        end

        function h = spacer(~,parent,col)
            % An empty cell that takes up a strip's slack (column COL).
            h = uilabel(parent,'Text','');
            h.Layout.Column = col;
        end

        function h = lookDropdown(obj,parent,field,labels,keys,tag,tip)
            h = uidropdown(parent,'Items',cellstr(labels),'ItemsData',cellstr(keys), ...
                'Tag',tag,'Tooltip',tip, ...
                'ValueChangedFcn',obj.viewWrap(@(s,~) obj.onLook(field,string(s.Value))));
        end

        % ---- the look ----------------------------------------------------
        function syncLook(obj)
            % The controls show ViewLook (after a pref or a configuration).
            obj.ViewLook = mabr.ui.analysis.TrialView.sanitizeLook(obj.ViewLook);
            L = obj.ViewLook;
            H = obj.Handles;
            obj.put('ctl_Feature',H.Feature,'Value',char(L.Feature));
            obj.put('ctl_XAxis',H.XAxis,'Value',char(L.XAxis));
            obj.put('ctl_Order',H.Order,'Value',char(L.Order));
            obj.put('ctl_Polarity',H.Polarity,'Value',char(L.Polarity));
            obj.put('ctl_Band',H.Band,'Value',char(L.Band));
            obj.put('ctl_PanelD',H.PanelD,'Value',char(L.PanelD));
            obj.put('ctl_IncludeRejected',H.IncludeRejected,'Value',logical(L.IncludeRejected));
            if mabr.ui.analysis.TrialView.isRatio(L.Feature), u = ''; else, u = 'µV'; end
            obj.put('ctl_unit',H.RejectAboveUnit,'Text',u);
            mode = L.PanelD;
            obj.put('d_conv_vis',H.ConvPanel,'Visible',mabr.ui.analysis.TrialView.onoff(mode == "convergence"));
            obj.put('d_split_vis',H.SplitPanel,'Visible',mabr.ui.analysis.TrialView.onoff(mode == "splithalf"));
            obj.put('d_perm_vis',H.PermPanel,'Visible',mabr.ui.analysis.TrialView.onoff(mode == "permutation"));
        end

        function onLook(obj,field,value)
            % A control changed the look: remember it (the user's own
            % choice, so the pref too) and redraw.
            old = obj.ViewLook;
            obj.ViewLook.(field) = value;
            obj.ViewLook = mabr.ui.analysis.TrialView.sanitizeLook(obj.ViewLook);
            % the control already shows the value: record it as written
            v = obj.ViewLook.(field);
            if isstring(v), v = char(v); end
            obj.Written.(['ctl_' field]) = v;
            if field == "Feature" && ~strcmp(old.Feature,obj.ViewLook.Feature)
                obj.RejectValue = NaN;            % another feature, another scale
            end
            obj.savePrefs();
            obj.renderGuarded(@() obj.renderAll());
            drawnow limitrate
        end

        function onRejectValue(obj,v)
            obj.RejectValue = double(v);
            if ~isempty(obj.Trial), obj.drawFeature(obj.Trial); end
        end

        % ---- rendering ---------------------------------------------------
        function renderAll(obj)
            m = obj.Model;
            obj.syncLook();
            obj.fitControls();      % (an invisible window gets no SizeChangedFcn)
            S = m.Session;
            if isempty(S)
                obj.Trial = [];
                obj.put('raw_vis',obj.Handles.RawPanel,'Visible','off');
                obj.showEmpty(mabr.ui.analysis.TrialView.NoSessionText,[]);
                obj.stopTimer();
                obj.HeavyPending = false;
                return
            end
            ck = m.Selection.ConditionKey;
            known = ck ~= "" && height(S.Conditions) > 0 && any(S.Conditions.Key == ck);
            if ~known
                obj.Trial = [];
                obj.put('raw_vis',obj.Handles.RawPanel,'Visible','off');
                obj.showEmpty(mabr.ui.analysis.TrialView.NoConditionText,[]);
                return
            end
            obj.hideEmpty();
            obj.drawHeader(S,ck);
            if ~S.HasSweeps
                % results only: the averages are here, the sweeps are not
                obj.Trial = [];
                obj.showRaw(S);
                obj.drawSelection();    % no sweeps: "No sweeps selected", actions off
                return
            end
            obj.put('raw_vis',obj.Handles.RawPanel,'Visible','off');
            prev = obj.Trial;
            D = obj.buildTrial(S,ck);
            if isempty(prev) || prev.Key ~= D.Key
                obj.AnchorCol = NaN;
            end
            obj.Trial = D;
            if D.N < 2
                obj.showEmpty(mabr.ui.analysis.TrialView.FewText,[]);
                return
            end
            obj.drawImage(D);
            obj.drawFeature(D);
            obj.drawMean(D);
            obj.drawPanelD(D);
            obj.drawSelection();
            if obj.needsHeavy(D)
                obj.scheduleHeavy();
            end
        end

        function showRaw(obj,S)
            % The Load raw data offer, with what it should cost.
            txt = "Load raw data";
            try
                st = obj.settingsOf(S);
                nF = height(S.Files);  nC = height(S.Conditions);
                nS = numel(obj.Model.seriesKeys());
                sec = mabr.analysis.Session.estimateSeconds(st,"segment",nF,nC,nS) - ...
                    mabr.analysis.Session.estimateSeconds(st,"detect",nF,nC,nS);
                e = mabr.ui.analysis.Style.formatSeconds(max(sec,0));
                if e ~= "", txt = txt + " (" + e + ")"; end
            catch
            end
            obj.put('raw_text',obj.Handles.LoadRaw,'Text',char(txt));
            obj.put('raw_vis',obj.Handles.RawPanel,'Visible','on');
        end

        function D = buildTrial(obj,S,ck)
            % Everything about the condition the panels draw, from the
            % Session as it is now.
            C = S.Conditions;
            r = S.rowOf(ck);
            X = C.Sweeps{r};
            n = size(X,2);
            % a condition without a usable sweep may hold an unshaped empty
            % (Session.conditionMean guards the same)
            if size(X,1) ~= numel(S.Time), X = NaN(numel(S.Time),n); end
            vars = string(C.Properties.VariableNames);
            cell1 = @(name,def) mabr.ui.analysis.TrialView.cellRow(C,vars,name,r,def,n);
            D = struct();
            D.Key = ck;
            D.Row = r;
            D.N = n;
            D.X = X;
            D.T = S.Time(:);
            D.Rejected = logical(cell1('Rejected',false(1,n)));
            D.Reason = double(cell1('RejectReason',zeros(1,n)));
            D.Excess = logical(cell1('Excess',false(1,n)));
            % +1/-1, 0 and NaN counting as +1 (Stats.balancedMean's rule, so
            % the means and draws here are the analysis' own)
            pol = double(cell1('Polarity',ones(1,n)));
            pol(~(pol < 0)) = 1;
            pol(pol < 0) = -1;
            D.Pol = pol;
            D.File = double(cell1('SweepFile',ones(1,n)));
            D.Index = double(cell1('SweepIndex',1:n));
            D.Order = double(cell1('SweepOrder',1:n));
            D.STime = double(cell1('SweepTime',NaN(1,n)));
            D.Clean = ~D.Rejected & ~D.Excess;
            D.NClean = sum(D.Clean);
            if ismember("Extent",vars) && all(isfinite(C.Extent(r,:)))
                D.Extent = C.Extent(r,:);
            else
                D.Extent = [D.T(1) D.T(end)];
            end
            ext = D.T >= D.Extent(1) & D.T <= D.Extent(2);
            o = obj.measureOpts(S);
            D.Opts = o;
            D.MeasureRows = mabr.analysis.Artifacts.windowMask(D.T,o.ResponseWindow) & ext;
            D.SplitRows   = mabr.analysis.Artifacts.windowMask(D.T,o.SplitHalfWindow) & ext;
            D.BaselineRows = mabr.analysis.Artifacts.windowMask(D.T,o.BaselineWindow) & ext;
            % What the heavy pass's results depend on: the session and
            % condition, which sweeps are clean, the sweeps themselves (a
            % re-segmentation with another filter keeps every count and flag)
            % and the options measure() drew with (a new Seed, window or
            % number of partitions after a re-analysis). Anything less and a
            % +/- reference or split-half of the old analysis is drawn as
            % this one's.
            try
                oj = string(jsonencode(o));
            catch
                oj = "";
            end
            fp = string(sprintf('%.17g|%.17g|%d|%.17g|%.17g',sum(X,'all','omitnan'), ...
                sum(abs(X),'all','omitnan'),numel(D.T),D.T(1),D.T(end)));
            D.Stamp = string(mabr.analysis.Stats.hex8(obj.Model.SessionKey + "|" + ck + "|" + n + "|" + ...
                string(char('0' + D.Clean)) + "|" + string(char('0' + D.Rejected)) + "|" + ...
                string(char('0' + (D.Pol > 0))) + "|" + fp + "|" + oj));

            % per-sweep features: measure()'s, or made here when there are none
            Ft = [];
            if ismember("Features",vars)
                try
                    Ft = C.Features{r};
                catch
                    Ft = [];
                end
            end
            if ~istable(Ft) || height(Ft) ~= n
                Ft = mabr.analysis.SingleTrial.features(X,D.MeasureRows,D.BaselineRows);
            end
            D.Features = Ft;

            % files: block number and time origin
            F = S.Files;
            uf = unique(D.File);
            ts = NaT(numel(uf),1);
            ids = strings(numel(uf),1);
            fv = string(F.Properties.VariableNames);
            if ismember("timestamp",fv), ts = F.timestamp(uf); ts = ts(:); end
            if ismember("FileId",fv), ids = string(F.FileId(uf)); ids = ids(:); end
            key = ts;  key(isnat(key)) = datetime(9999,1,1);
            [~,ord] = sortrows(table(key,ids));
            blk = zeros(1,n);
            for i = 1:numel(uf)
                blk(D.File == uf(i)) = find(ord == i);
            end
            D.Block = blk;
            D.NumBlocks = numel(uf);
            t0 = min(ts(~isnat(ts)));
            tx = NaN(1,n);
            if ~isempty(t0)
                for i = 1:numel(uf)
                    if isnat(ts(i)), continue; end
                    k = D.File == uf(i);
                    tx(k) = seconds(ts(i) - t0) + D.STime(k);
                end
            end
            D.RunTime = tx;
            % within a block, sweeps spread over [b-0.4 b+0.4] in their order
            bx = NaN(1,n);
            for b = 1:D.NumBlocks
                k = find(blk == b);
                [~,oo] = sort(D.Order(k));
                pos = zeros(1,numel(k));
                pos(oo) = 1:numel(k);
                bx(k) = b - 0.4 + 0.8*(pos - 0.5)/max(numel(k),1);
            end
            D.BlockX = bx;

            % colour scale: the 99th percentile of |x| of the clean sweeps
            Z = X(:,D.Clean);
            if isempty(Z), Z = X; end
            z = abs(Z(isfinite(Z)));
            D.ColorLimit = NaN;
            if ~isempty(z), D.ColorLimit = 1e6*mabr.analysis.Stats.percentile(z,0.99); end

            D.Notes = obj.noteSweeps(S,D);
            D = mabr.ui.analysis.TrialView.derive(D,obj.ViewLook);
        end

        function N = noteSweeps(obj,S,D)
            % The rig notes written while this condition's continuous files
            % were recording, each at the sweep its time falls on: sweep ~
            % (note time - file start)/ISI, made exact by the note's own
            % sweep count when that agrees within the clock's second.
            N = struct('Col',cell(1,0),'Text',cell(1,0),'Time',cell(1,0));
            T = obj.sessionNotes();
            if isempty(T) || height(T) == 0, return; end
            F = S.Files;
            fv = string(F.Properties.VariableNames);
            if ~all(ismember(["timestamp","Duration"],fv)), return; end
            for i = 1:height(T)
                tn = T.Time(i);
                if isnat(tn), continue; end
                for f = unique(D.File)
                    t0 = F.timestamp(f);
                    dur = double(F.Duration(f));
                    if isnat(t0) || ~isfinite(dur), continue; end
                    if tn < t0 || tn > t0 + seconds(dur), continue; end
                    cols = find(D.File == f & isfinite(D.STime));
                    if isempty(cols), continue; end           % a compact file: no times
                    el = seconds(tn - t0);
                    [~,j] = min(abs(D.STime(cols) - el));
                    c = cols(j);
                    sw = NaN;
                    if ismember("Sweep",string(T.Properties.VariableNames))
                        sw = double(T.Sweep(i));
                    end
                    if isfinite(sw)
                        c2 = cols(D.Index(cols) == sw);
                        isi = NaN;
                        if ismember("MinISI",fv), isi = double(F.MinISI(f))/1000; end
                        if ~isfinite(isi), isi = 0; end
                        if ~isempty(c2) && abs(D.STime(c2(1)) - el) <= 1 + isi
                            c = c2(1);
                        end
                    end
                    N(end+1) = struct('Col',c,'Text',string(T.Text(i)),'Time',tn); %#ok<AGROW>
                end
            end
        end

        function T = sessionNotes(obj)
            % The open session's rig notes (Catalog.notes of its folders),
            % cached for the session.
            m = obj.Model;
            if m.SessionKey == obj.NotesFor && ~isempty(obj.NotesCache)
                T = obj.NotesCache;
                return
            end
            T = table(NaT(0,1),strings(0,1),zeros(0,1),'VariableNames',{'Time','Text','Sweep'});
            keys = m.SessionKeys;
            if isempty(keys), keys = m.SessionKey; end
            for k = reshape(keys,1,[])
                try
                    Tk = m.Catalog.notes(k);
                    if height(Tk) == 0, continue; end
                    sw = NaN(height(Tk),1);
                    if ismember('Sweep',Tk.Properties.VariableNames), sw = double(Tk.Sweep); end
                    T = [T; table(Tk.Time,string(Tk.Text),sw,'VariableNames',{'Time','Text','Sweep'})]; %#ok<AGROW>
                catch me
                    mabr.log.vprintf(2,'Trials view: no notes for %s (%s).',k,me.message);
                end
            end
            if height(T) > 1
                k = string(T.Time) + "|" + T.Text;
                [~,first] = unique(k,'stable');
                T = T(sort(first),:);
            end
            obj.NotesFor = m.SessionKey;
            obj.NotesCache = T;
        end

        % ---- the four panels ---------------------------------------------
        function drawImage(obj,D)
            H = obj.Handles;
            L = obj.ViewLook;
            cols = D.Display;
            t = obj.earTime(D.T);
            t1 = t(1);  t2 = t(end);
            span = max(t2 - t1,eps);
            nR = numel(cols);
            if nR == 0
                Cd = NaN(1,numel(t));  yd = [1 1];
            else
                Cd = 1e6*D.X(:,cols).';
                yd = [1 nR];
            end
            obj.put('img_c',H.Image,'CData',Cd);
            obj.put('img_a',H.Image,'AlphaData',double(~isnan(Cd)));
            obj.put('img_x',H.Image,'XData',[t1 t2]);
            obj.put('img_y',H.Image,'YData',yd);
            obj.put('img_xlim',H.ImageAxes,'XLim',[t1 - 0.04*span, t2 + 0.075*span]);
            obj.put('img_ylim',H.ImageAxes,'YLim',[0.5 max(nR,1) + 0.5]);
            obj.applyColorLimits();
            % rejected (red) and unused (grey) ticks right of the rows
            xr = t2 + 0.025*span;
            [xs,ys] = mabr.ui.analysis.TrialView.ticks(find(D.Rejected(cols)),xr);
            obj.put('img_rej_x',H.ImageRejected,'XData',xs);
            obj.put('img_rej_y',H.ImageRejected,'YData',ys);
            [xs,ys] = mabr.ui.analysis.TrialView.ticks(find(D.Excess(cols) & ~D.Rejected(cols)),xr);
            obj.put('img_exc_x',H.ImageExcess,'XData',xs);
            obj.put('img_exc_y',H.ImageExcess,'YData',ys);
            % file boundaries, in acquisition order
            xs = NaN;  ys = NaN;
            if L.Order == "acquisition" && nR > 1
                b = find(diff(D.File(cols)) ~= 0);
                xs = reshape([repmat([t1;t2],1,numel(b)); NaN(1,numel(b))],1,[]);
                ys = reshape([repmat(b + 0.5,2,1); NaN(1,numel(b))],1,[]);
                if isempty(b), xs = NaN; ys = NaN; end
            end
            obj.put('img_files_x',H.ImageFiles,'XData',xs);
            obj.put('img_files_y',H.ImageFiles,'YData',ys);
            % notes, at the far right of their sweep's row
            [nrow,ntext] = obj.noteRows(D,cols);
            obj.put('img_notes_x',H.ImageNotes,'XData',repmat(t2 + 0.06*span,1,numel(nrow)));
            obj.put('img_notes_y',H.ImageNotes,'YData',nrow);
            obj.put('img_notes_u',H.ImageNotes,'UserData',ntext);
            if L.Order == "acquisition"
                yl = 'Sweep (acquisition order)';
            else
                yl = ['Sweep (by ' char(mabr.ui.analysis.TrialView.featureLabel(L.Feature)) ', smallest first)'];
            end
            obj.put('img_ylabel',H.ImageAxes.YLabel,'String',yl);
            obj.labelTimeAxis(H.ImageAxes,Key="img_time");
        end

        function applyColorLimits(obj)
            D = obj.Trial;
            if isempty(D), return; end
            lim = D.ColorLimit/obj.ColorScale;
            nShown = numel(D.Display);
            if isfinite(lim) && lim > 0
                if ~isfield(obj.Written,'img_clim') || ~isequal(obj.Written.img_clim,lim)
                    mabr.ui.analysis.Compat.setColorLimits(obj.Handles.ImageAxes,[-lim lim]);
                    obj.Written.img_clim = lim;
                end
                ttl = sprintf('%d sweeps · colour ±%s µV',nShown,mabr.ui.analysis.TrialView.num(lim,3));
            else
                ttl = sprintf('%d sweeps',nShown);
            end
            obj.put('img_title',obj.Handles.ImageAxes.Title,'String',ttl);
        end

        function [rows,texts] = noteRows(~,D,cols)
            rows = zeros(1,0);  texts = strings(1,0);
            for i = 1:numel(D.Notes)
                k = find(cols == D.Notes(i).Col,1);
                if isempty(k), continue; end
                rows(end+1) = k; %#ok<AGROW>
                texts(end+1) = D.Notes(i).Text; %#ok<AGROW>
            end
        end

        function drawFeature(obj,D)
            H = obj.Handles;
            L = obj.ViewLook;
            St = mabr.ui.analysis.Style;
            x = D.PX;  y = D.FV;
            vis = D.Visible;
            put2 = @(k,h,xx,yy) obj.putXY(k,h,xx,yy);
            m = vis & D.Clean;
            put2('feat_clean',H.FeatureClean,x(m),y(m));
            m = vis & D.Rejected;
            put2('feat_rej',H.FeatureRejected,x(m),y(m));
            m = vis & D.Excess & ~D.Rejected;
            put2('feat_exc',H.FeatureExcess,x(m),y(m));
            % running median of the clean sweeps, in x order
            k = find(D.Clean & vis & isfinite(x) & isfinite(y));
            if numel(k) >= 2
                [xs,o] = sort(x(k));
                ys = movmedian(y(k(o)),obj.MedianSpan,'omitnan');
            else
                xs = NaN;  ys = NaN;
            end
            put2('feat_med',H.FeatureMedian,xs,ys);
            % limits
            xx = x(vis & isfinite(x));
            if isempty(xx), xl = [0 1];
            elseif min(xx) == max(xx), xl = min(xx) + [-1 1];
            else, xl = [min(xx) max(xx)] + [-1 1]*0.02*(max(xx) - min(xx));
            end
            rv = obj.rejectValueShown(D);
            yy = y(vis & isfinite(y));
            hi = max([yy(:); rv]);
            lo = min([0; yy(:)]);
            if isempty(hi) || ~isfinite(hi) || hi <= lo, hi = lo + 1; end
            yl = [lo, hi + 0.08*(hi - lo)];
            obj.put('feat_xlim',H.FeatureAxes,'XLim',xl);
            obj.put('feat_ylim',H.FeatureAxes,'YLim',yl);
            put2('feat_above',H.FeatureAbove,xl,[rv rv]);
            % note ticks across the plot
            nx = zeros(1,0);
            for i = 1:numel(D.Notes)
                c = D.Notes(i).Col;
                if vis(c) && isfinite(x(c)), nx(end+1) = x(c); end %#ok<AGROW>
            end
            if isempty(nx)
                put2('feat_notes',H.FeatureNotes,NaN,NaN);
            else
                put2('feat_notes',H.FeatureNotes, ...
                    reshape([nx; nx; NaN(1,numel(nx))],1,[]), ...
                    reshape([repmat(yl(:),1,numel(nx)); NaN(1,numel(nx))],1,[]));
            end
            obj.put('feat_notes_u',H.FeatureNotes,'UserData',[D.Notes.Text]);
            % the field shows the value the line is drawn at
            obj.put('ctl_rejval',H.RejectAboveValue,'Value',max(rv,0));
            % labels
            switch L.XAxis
                case "time",  xlab = 'Time into the condition''s first run (s)';
                case "block", xlab = 'Block (file, in acquisition order)';
                otherwise,    xlab = 'Sweep (acquisition order)';
            end
            obj.put('feat_xlabel',H.FeatureAxes.XLabel,'String',xlab);
            if L.XAxis == "block"
                obj.put('feat_ticks',H.FeatureAxes,'XTick',1:max(D.NumBlocks,1));
                obj.forgetWritten('feat_tickmode');
            else
                obj.put('feat_tickmode',H.FeatureAxes,'XTickMode','auto');
                obj.forgetWritten('feat_ticks');
            end
            fl = mabr.ui.analysis.TrialView.featureLabel(L.Feature);
            if mabr.ui.analysis.TrialView.isRatio(L.Feature)
                ylab = char(fl);
            else
                ylab = [char(fl) ' (µV)'];
            end
            obj.put('feat_ylabel',H.FeatureAxes.YLabel,'String',ylab);
            obj.put('feat_title',H.FeatureAxes.Title,'String',sprintf('%s per sweep',fl));
            obj.put('feat_title_c',H.FeatureAxes.Title,'Color',St.Ink);
            sub = sprintf('red: rejected · line: running median of %d',obj.MedianSpan);
            if any(vis & D.Excess & ~D.Rejected)
                sub = [sub ' · grey: unused (beyond the cap)'];
            end
            if L.XAxis == "time" && any(vis & ~isfinite(D.RunTime))
                sub = sprintf('%s · %d without a time (intermixed files)',sub, ...
                    sum(vis & ~isfinite(D.RunTime)));
            end
            obj.put('feat_sub',H.FeatureAxes.Subtitle,'String',sub);
        end

        function rv = rejectValueShown(obj,D)
            % The "Reject above" value: the user's, else the largest value
            % of a sweep not yet rejected rounded up -- a line that rejects
            % nothing until moved (Model.rejectAbove compares every sweep not
            % rejected, the unused ones beyond the cap included).
            rv = obj.RejectValue;
            if isfinite(rv), return; end
            y = D.FV(~D.Rejected & isfinite(D.FV));
            if isempty(y), rv = 0; return; end
            v = max(y);
            if v <= 0, rv = 0; return; end
            p = 10^(floor(log10(v)) - 1);
            rv = ceil(v/p)*p;
        end

        function drawMean(obj,D)
            H = obj.Handles;
            L = obj.ViewLook;
            St = mabr.ui.analysis.Style;
            t = obj.earTime(D.T).';
            M = obj.meanOf(D,L.Polarity);
            few = D.NClean < 2;
            if few
                obj.put('mean_few',H.MeanFew,'String',char(mabr.ui.analysis.TrialView.FewText));
            else
                obj.put('mean_few',H.MeanFew,'String','');
            end
            uv = @(v) 1e6*reshape(v,1,[]);
            if few
                main = NaN(size(t));  lo = main;  hi = main;  pos = main;  neg = main;
            else
                pos = NaN(size(t));  neg = pos;
                if L.Polarity == "overlay"
                    main = NaN(size(t));
                    pos = uv(M.Pos);  neg = uv(M.Neg);
                else
                    main = uv(M.Mean);
                end
                [lo,hi,bandName] = obj.bandOf(D,M,L);
                lo = uv(lo);  hi = uv(hi);
            end
            obj.putXY('mean_line',H.MeanLine,t,main);
            obj.putXY('mean_pos',H.MeanPos,t,pos);
            obj.putXY('mean_neg',H.MeanNeg,t,neg);
            ok = isfinite(lo) & isfinite(hi);
            if any(ok)
                % one closed polygon per run of finite samples
                [bx,by] = mabr.ui.analysis.TrialView.bandPolygon(t,lo,hi);
            else
                bx = NaN;  by = NaN;
            end
            obj.put('mean_band_x',H.MeanBand,'XData',bx);
            obj.put('mean_band_y',H.MeanBand,'YData',by);
            % the +/- reference (heavy) and the highlighted sweep
            ref = NaN(size(t));
            Hv = obj.Heavy;
            if ~few && ~isempty(Hv) && Hv.Stamp == D.Stamp && ~isempty(Hv.Ref)
                ref = uv(Hv.Ref);
            end
            obj.putXY('mean_ref',H.MeanRef,t,ref);
            obj.drawHighlight();
            % limits from what describes the mean (a single sweep is tens
            % of times larger and is left to run off the axes)
            v = [main(:); pos(:); neg(:); lo(:); hi(:); ref(:)];
            v = v(isfinite(v));
            if isempty(v), yl = [-1 1];
            else
                a = min(v);  b = max(v);
                if a == b, a = a - 1; b = b + 1; end
                pad = 0.08*(b - a);
                yl = [a - pad, b + 2.2*pad];
            end
            xl = [t(1) t(end)];
            obj.put('mean_xlim',H.MeanAxes,'XLim',xl);
            obj.put('mean_ylim',H.MeanAxes,'YLim',yl);
            obj.putXY('mean_zero',H.MeanZero,xl,[0 0]);
            % the response window, raw like the sweeps, drawn in ear time
            rw = obj.earTime(D.Opts.ResponseWindow);
            obj.put('mean_rw_x',H.MeanWindow,'XData',[rw(1) rw(2) rw(2) rw(1)]);
            obj.put('mean_rw_y',H.MeanWindow,'YData',[yl(1) yl(1) yl(2) yl(2)]);
            obj.drawWaves(D,yl);
            % title and axes
            if few
                ttl = 'Mean';
            else
                switch L.Polarity
                    case "overlay"
                        % each mean named in its own line's colour (there is
                        % no legend to say which is which)
                        ttl = sprintf(['{\\color[rgb]{%.3f %.3f %.3f}+ mean (n = %d)} and ' ...
                            '{\\color[rgb]{%.3f %.3f %.3f}− mean (n = %d)}'], ...
                            St.OkabeIto(1,:),M.NPos,St.OkabeIto(2,:),M.NNeg);
                    case "positive",   ttl = sprintf('+ mean ± %s (n = %d)',bandName,M.N);
                    case "negative",   ttl = sprintf('− mean ± %s (n = %d)',bandName,M.N);
                    case "difference", ttl = sprintf('Difference (+ − −)/2 ± %s (n = %d)',bandName,M.N);
                    otherwise,         ttl = sprintf('Balanced mean ± %s (n = %d)',bandName,M.N);
                end
            end
            obj.put('mean_title',H.MeanAxes.Title,'String',ttl);
            obj.put('mean_title_c',H.MeanAxes.Title,'Color',St.Ink);
            obj.labelTimeAxis(H.MeanAxes,Key="mean_time");
            obj.writeMeanSubtitle();
        end

        function writeMeanSubtitle(obj)
            % The mean axes' subtitle: the time base when it is not onset
            % time (View.timeAxis: the delay it is re), then what the grey
            % lines are -- the +/- reference once computed, the sweep the
            % light grey one is.
            D = obj.Trial;
            key = strings(1,0);
            if ~isempty(D) && D.NClean >= 2
                Hv = obj.Heavy;
                if ~isempty(Hv) && Hv.Stamp == D.Stamp && ~isempty(Hv.Ref)
                    key(end+1) = "grey: ± reference";
                end
                c = obj.highlightCol();
                if isfinite(c), key(end+1) = "light grey: sweep " + D.Order(c); end
            end
            key = strjoin(key," · ");
            T = obj.timeAxis();
            if T.Subtitle ~= "" && key ~= ""
                s = {char(T.Subtitle); char(key)};
            elseif T.Subtitle ~= ""
                s = char(T.Subtitle);
            else
                s = char(key);
            end
            obj.put('mean_sub',obj.Handles.MeanAxes.Subtitle,'String',s);
        end

        function [lo,hi,name] = bandOf(obj,D,M,L)
            % The band around the mean: SEM, or the bootstrap band when it
            % has been computed for this polarity (the overlay and the
            % difference keep the SEM: a bootstrap band is of one mean).
            name = "SEM";
            lo = M.Mean - M.SEM;  hi = M.Mean + M.SEM;
            if L.Polarity == "overlay"
                lo = NaN(size(M.Mean));  hi = lo;  name = "";
                return
            end
            if L.Band == "bootstrap" && L.Polarity ~= "difference"
                name = "95% bootstrap";
                Hv = obj.Heavy;
                key = char(L.Polarity);
                if ~isempty(Hv) && Hv.Stamp == D.Stamp && isfield(Hv.Boot,key)
                    lo = Hv.Boot.(key)(:,1);  hi = Hv.Boot.(key)(:,2);
                else
                    lo = NaN(size(M.Mean));  hi = lo;    % computing
                end
            end
        end

        function M = meanOf(~,D,polarity)
            % The mean drawn, from the clean sweeps -- the arithmetic of
            % Session.conditionMean, so the two cannot differ.
            c = D.Clean;
            X = D.X(:,c);  pol = D.Pol(c);  str = D.File(c);
            nT = size(D.X,1);
            M = struct('Mean',NaN(nT,1),'SEM',NaN(nT,1),'Pos',NaN(nT,1),'Neg',NaN(nT,1), ...
                'N',size(X,2),'NPos',sum(pol > 0),'NNeg',sum(pol < 0));
            if isempty(X), return; end
            s = pol > 0;
            if any(s), M.Pos = mabr.analysis.Stats.balancedMean(X(:,s),[],str(s)); end
            if any(~s), M.Neg = mabr.analysis.Stats.balancedMean(X(:,~s),[],str(~s)); end
            switch polarity
                case "positive"
                    if any(s), [M.Mean,M.SEM] = mabr.analysis.Stats.balancedMean(X(:,s),[],str(s)); end
                    M.N = sum(s);
                case "negative"
                    if any(~s), [M.Mean,M.SEM] = mabr.analysis.Stats.balancedMean(X(:,~s),[],str(~s)); end
                    M.N = sum(~s);
                case "difference"
                    [mp,sp] = mabr.analysis.Stats.balancedMean(X(:,s),[],str(s));
                    [mq,sq] = mabr.analysis.Stats.balancedMean(X(:,~s),[],str(~s));
                    M.Mean = (mp - mq)/2;
                    M.SEM = sqrt(sp.^2 + sq.^2)/2;
                otherwise
                    [M.Mean,M.SEM] = mabr.analysis.Stats.balancedMean(X,pol,str);
            end
        end

        function drawWaves(obj,D,yl)
            % The wave search windows as a ruler along the top of the mean
            % axes, and the condition's picked peaks and troughs. The windows
            % are written, and searched, in the recording's time (re the
            % timing pulse), like the sweeps; the axis is in ear time, so they
            % take the latency offset off (earTime) as the traces and picks
            % do, and each pick stays over the samples its window searched.
            W = obj.wavesOf(D);
            names = string(fieldnames(obj.WaveG)).';
            shown = strings(1,0);
            y0 = yl(2) - 0.07*(yl(2) - yl(1));
            for i = 1:numel(W)
                nm = string(W(i).Name);
                g = obj.waveGraphics(nm);
                fn = matlab.lang.makeValidName(nm);
                shown(end+1) = fn; %#ok<AGROW>
                tw = obj.earTime([W(i).TMin W(i).TMax]);
                xw = [tw(1) tw(2) tw(2) tw(1)];
                obj.put("wave_" + fn + "_px",g.Patch,'XData',xw);
                obj.put("wave_" + fn + "_py",g.Patch,'YData',[y0 y0 yl(2) yl(2)]);
                obj.put("wave_" + fn + "_lp",g.Label,'Position',[mean(tw) y0 0]);
                obj.put("wave_" + fn + "_vis",g.Patch,'Visible','on');
                obj.put("wave_" + fn + "_lvis",g.Label,'Visible','on');
            end
            for fn = setdiff(names,shown)
                g = obj.WaveG.(fn);
                obj.put("wave_" + fn + "_vis",g.Patch,'Visible','off');
                obj.put("wave_" + fn + "_lvis",g.Label,'Visible','off');
            end
            obj.redrawPeaks();
        end

        function W = wavesOf(obj,D)
            % The enabled waves of this condition's stimulus, shifted for its
            % frequency, in the RECORDING's time (Offset 0: the windows are
            % written, and Session.pickPeaks searches them, so); drawWaves
            % converts them to the axis' ear time.
            W = struct('Name',{},'TMin',{},'TMax',{});
            S = obj.Model.Session;
            st = obj.settingsOf(S);
            try
                Wv = st.Waves;
                stim = "";  fr = NaN;
                C = S.Conditions;
                vars = string(C.Properties.VariableNames);
                if ismember("Stimulus",vars), stim = string(C.Stimulus(D.Row)); end
                fp = "";
                try
                    fp = string(S.frequencyParam());
                catch
                end
                if fp ~= "" && ismember(fp,vars), fr = double(C.(fp)(D.Row)); end
                Wv = mabr.analysis.Peaks.wavesFor(Wv,stim,fr,OctaveShift=st.PeakOctaveShift, ...
                    RefFrequency=st.PeakRefFrequency,Offset=0);
                for i = 1:numel(Wv)
                    if isfield(Wv,'Enabled') && ~Wv(i).Enabled, continue; end
                    W(end+1) = struct('Name',string(Wv(i).Name),'TMin',Wv(i).TMin,'TMax',Wv(i).TMax); %#ok<AGROW>
                end
            catch me
                mabr.log.vprintf(2,'Trials view: no wave windows (%s).',me.message);
            end
        end

        function g = waveGraphics(obj,name)
            fn = matlab.lang.makeValidName(name);
            if isfield(obj.WaveG,fn) && isvalid(obj.WaveG.(fn).Patch)
                g = obj.WaveG.(fn);
                return
            end
            ax = obj.Handles.MeanAxes;
            c = mabr.ui.analysis.Style.waveColor(name);
            g.Patch = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',c,'FaceAlpha',0.35, ...
                'EdgeColor','none','PickableParts','none','Tag',char("TrialsWaveWindow_" + fn));
            g.Label = text(ax,NaN,NaN,char(name),'HorizontalAlignment','center', ...
                'VerticalAlignment','bottom','FontSize',8,'Color',c*0.7,'PickableParts','none', ...
                'Tag',char("TrialsWaveLabel_" + fn),'Interpreter','none');
            g.Peak = line(ax,NaN,NaN,'LineStyle','none','Marker','^','MarkerSize',6, ...
                'MarkerFaceColor',c,'MarkerEdgeColor',[0 0 0],'PickableParts','none', ...
                'Tag',char("TrialsPeak_" + fn),'DisplayName',char(name + " peak"));
            g.Trough = line(ax,NaN,NaN,'LineStyle','none','Marker','v','MarkerSize',5, ...
                'MarkerFaceColor',[1 1 1],'MarkerEdgeColor',c,'PickableParts','none', ...
                'Tag',char("TrialsTrough_" + fn),'DisplayName',char(name + " trough"));
            obj.WaveG.(fn) = g;
            for pre = ["wave_","pk_","tr_"]
                obj.forgetWritten(char(pre + fn));
            end
        end

        function redrawPeaks(obj)
            % The picked peaks of the condition (ear time, µV) -- on the
            % balanced mean they were picked from -- and the header's wave.
            D = obj.Trial;
            S = obj.Model.Session;
            if ~isempty(S) && obj.Model.Selection.ConditionKey ~= ""
                try
                    obj.drawHeader(S,obj.Model.Selection.ConditionKey);
                catch
                end
            end
            if isempty(D) || isempty(S), return; end
            P = S.Peaks;
            names = string(fieldnames(obj.WaveG)).';
            drawn = strings(1,0);
            show = obj.ViewLook.Polarity == "balanced" && D.NClean >= 2;
            if show && height(P) > 0 && all(ismember(["Key","Wave","PeakLatency","PeakValue"], ...
                    string(P.Properties.VariableNames)))
                rows = find(string(P.Key) == D.Key);
                for i = reshape(rows,1,[])
                    nm = string(P.Wave(i));
                    fn = matlab.lang.makeValidName(nm);
                    g = obj.waveGraphics(nm);
                    drawn(end+1) = fn; %#ok<AGROW>
                    obj.putXY("pk_" + fn,g.Peak,obj.earTime(double(P.PeakLatency(i))),1e6*double(P.PeakValue(i)));
                    tl = NaN;  tv = NaN;
                    if ismember("TroughLatency",string(P.Properties.VariableNames))
                        tl = double(P.TroughLatency(i));  tv = double(P.TroughValue(i));
                    end
                    obj.putXY("tr_" + fn,g.Trough,obj.earTime(tl),1e6*tv);
                    sel = obj.Model.Selection.Wave == nm;
                    obj.put("pk_" + fn + "_ms",g.Peak,'MarkerSize',6 + 3*sel);
                end
            end
            for fn = setdiff(names,drawn)
                g = obj.WaveG.(fn);
                obj.putXY("pk_" + fn,g.Peak,NaN,NaN);
                obj.putXY("tr_" + fn,g.Trough,NaN,NaN);
            end
        end

        function drawHighlight(obj)
            % The highlighted sweep -- the anchor of the selection, else its
            % last -- in light grey behind the mean.
            D = obj.Trial;
            if isempty(D), return; end
            t = obj.earTime(D.T).';
            c = obj.highlightCol();
            if isfinite(c)
                y = 1e6*reshape(D.X(:,c),1,[]);
            else
                y = NaN(size(t));
            end
            obj.putXY('mean_sweep',obj.Handles.MeanSweep,t,y);
            if isfinite(c)
                obj.put('mean_sweep_name',obj.Handles.MeanSweep,'DisplayName', ...
                    sprintf('sweep %d',D.Order(c)));
            end
            obj.writeMeanSubtitle();
        end

        function c = highlightCol(obj)
            c = NaN;
            sel = obj.selectedCols();
            if isempty(sel), return; end
            if ismember(obj.AnchorCol,sel)
                c = obj.AnchorCol;
            else
                c = sel(end);
            end
        end

        function drawPanelD(obj,D)
            mode = obj.ViewLook.PanelD;
            switch mode
                case "convergence", obj.drawConvergence(D);
                case "splithalf",   obj.drawSplitHalf(D);
                otherwise,          obj.drawPermutation(D);
            end
        end

        function drawConvergence(obj,D)
            H = obj.Handles;
            Hv = obj.Heavy;
            C = [];
            if ~isempty(Hv) && Hv.Stamp == D.Stamp, C = Hv.Conv; end
            ax = H.ConvAxes;
            if D.NClean < 2
                note = char(mabr.ui.analysis.TrialView.FewText);
            elseif isempty(C)
                note = 'Computing…';
            else
                note = '';
            end
            obj.put('conv_note',H.ConvNote,'String',note);
            if isempty(C) || D.NClean < 2
                obj.putXY('conv_rn',H.ConvRN,NaN,NaN);
                obj.putXY('conv_guide',H.ConvGuide,NaN,NaN);
                obj.putXY('conv_snr',H.ConvSNR,NaN,NaN);
                obj.put('conv_title',ax.Title,'String','Residual noise against sweeps');
                obj.put('conv_sub',ax.Subtitle,'String','');
                return
            end
            ok = isfinite(C.RN) & C.RN > 0;
            n = reshape(C.N(ok),1,[]);
            rn = 1e6*reshape(C.RN(ok),1,[]);
            obj.putXY('conv_rn',H.ConvRN,n,rn);
            if numel(n) >= 1
                % 1/sqrt(N) through the last point: where an average that
                % works would have been at each earlier N
                g = rn(end)*sqrt(n(end)./n);
                obj.putXY('conv_guide',H.ConvGuide,n,g);
            else
                obj.putXY('conv_guide',H.ConvGuide,NaN,NaN);
            end
            obj.putXY('conv_snr',H.ConvSNR,reshape(C.N,1,[]),reshape(C.SNR,1,[]));
            if ~isempty(n) && min(n) < max(n)
                obj.put('conv_xlim',ax,'XLim',[min(n)*0.9 max(n)*1.1]);
            end
            if numel(n) >= 2
                sl = polyfit(log(n),log(rn),1);
                sub = sprintf('log–log slope %.2f (−0.50: averaging works)',sl(1));
            else
                sub = '';
            end
            obj.put('conv_title',ax.Title,'String','Residual noise against sweeps');
            obj.put('conv_sub',ax.Subtitle,'String',sub);
        end

        function drawSplitHalf(obj,D)
            H = obj.Handles;
            Hv = obj.Heavy;
            R = [];
            if ~isempty(Hv) && Hv.Stamp == D.Stamp, R = Hv.Split; end
            ax = H.SplitAxes;
            blank = @() obj.splitBlank();
            if D.NClean < 2
                blank();
                obj.put('split_note',H.SplitNote,'String',char(mabr.ui.analysis.TrialView.FewText));
                return
            end
            if isempty(R)
                blank();
                obj.put('split_note',H.SplitNote,'String','Computing…');
                return
            end
            if isempty(R.R)
                blank();
                obj.put('split_note',H.SplitNote,'String',{'Too few sweeps for a split-half r:'; ...
                    sprintf('K = %d per polarity per half,',R.K); ...
                    sprintf('under the %d the settings ask for.',D.Opts.SplitHalfMinPerPolarity)});
                return
            end
            r = R.R(:).';
            [e,cnt] = mabr.ui.analysis.TrialView.histEdges(r);
            [ox,oy] = mabr.ui.analysis.TrialView.stairsOutline(e,cnt);
            obj.put('split_fill_x',H.SplitFill,'XData',ox);
            obj.put('split_fill_y',H.SplitFill,'YData',oy);
            obj.putXY('split_outline',H.SplitOutline,ox,oy);
            top = max(cnt)*1.18;
            if top <= 0, top = 1; end
            obj.putXY('split_mean',H.SplitMean,[R.Mean R.Mean],[0 top/1.18]);
            obj.putXY('split_bounds',H.SplitBounds,[R.P025 R.P025 NaN R.P975 R.P975], ...
                [0 top/1.18 NaN 0 top/1.18]);
            obj.put('split_blpos',H.SplitBoundsLabel,'Position',[mean([R.P025 R.P975]) top/1.18 0]);
            obj.put('split_blvis',H.SplitBoundsLabel,'Visible','on');
            obj.put('split_note',H.SplitNote,'String','');
            lo = min([e(1) R.P025]);  hi = max([e(end) R.P975]);
            if hi <= lo, hi = lo + 0.1; end
            obj.put('split_xlim',ax,'XLim',[lo hi] + [-1 1]*0.04*(hi - lo));
            obj.put('split_ylim',ax,'YLim',[0 top]);
            obj.put('split_title',ax.Title,'String',sprintf(['Split-half r %.2f (SD %.2f; partition ' ...
                '2.5–97.5%% %.2f–%.2f)'],R.Mean,R.SD,R.P025,R.P975));
            obj.put('split_sub',ax.Subtitle,'String',sprintf( ...
                '%d partitions · K = %d per polarity per half · %s halves',numel(r),R.K,R.Mode));
        end

        function splitBlank(obj)
            H = obj.Handles;
            obj.put('split_fill_x',H.SplitFill,'XData',NaN);
            obj.put('split_fill_y',H.SplitFill,'YData',NaN);
            obj.putXY('split_outline',H.SplitOutline,NaN,NaN);
            obj.putXY('split_mean',H.SplitMean,NaN,NaN);
            obj.putXY('split_bounds',H.SplitBounds,NaN,NaN);
            obj.put('split_blvis',H.SplitBoundsLabel,'Visible','off');
            obj.put('split_title',H.SplitAxes.Title,'String','Split-half r');
            obj.put('split_sub',H.SplitAxes.Subtitle,'String','');
        end

        function drawPermutation(obj,D)
            H = obj.Handles;
            S = obj.Model.Session;
            d = [];
            try
                C = S.Conditions;
                if ismember('Detection',C.Properties.VariableNames)
                    d = C.Detection{D.Row};
                end
            catch
            end
            ax = H.PermTAxes;  ax2 = H.PermNullAxes;
            if ~isstruct(d) || isempty(d) || ~isfield(d,'t') || isempty(d.t)
                obj.putXY('perm_t',H.PermT,NaN,NaN);
                obj.putXY('perm_thr',H.PermThreshold,NaN,NaN);
                obj.putXY('perm_zero',H.PermZero,NaN,NaN);
                obj.put('perm_span_x',H.PermSpans,'XData',NaN);
                obj.put('perm_span_y',H.PermSpans,'YData',NaN);
                obj.put('perm_tnote',H.PermTNote,'String','Not tested yet — press Analyse (Ctrl+Enter).');
                obj.put('perm_title',ax.Title,'String','Permutation test');
                obj.nullBlank('');
                return
            end
            obj.put('perm_tnote',H.PermTNote,'String','');
            tv = double(d.t(:)).';
            tt = obj.permTimes(D,d,numel(tv));
            x = obj.earTime(tt);
            obj.putXY('perm_t',H.PermT,x,tv);
            thr = NaN;
            if isfield(d,'tThresh'), thr = double(d.tThresh); end
            xl = [x(1) x(end)];
            if xl(1) == xl(2), xl = xl + [-0.5 0.5]; end
            obj.putXY('perm_thr',H.PermThreshold,[xl NaN xl],[thr thr NaN -thr -thr]);
            obj.putXY('perm_zero',H.PermZero,xl,[0 0]);
            a = max(abs([tv thr]),[],'omitnan');
            if ~isfinite(a) || a == 0, a = 1; end
            yl = [-a a]*1.1;
            obj.put('perm_xlim',ax,'XLim',xl);
            obj.put('perm_ylim',ax,'YLim',yl);
            % significant spans
            mask = obj.sigMaskOf(d,numel(tv));
            [sx,sy] = mabr.ui.analysis.TrialView.spans(mask,x,yl);
            obj.put('perm_span_x',H.PermSpans,'XData',sx);
            obj.put('perm_span_y',H.PermSpans,'YData',sy);
            method = "";
            if isfield(d,'method'), method = string(d.method); end
            obj.put('perm_title',ax.Title,'String',sprintf('t over the response window (%s; %d sweeps)', ...
                method,mabr.ui.analysis.TrialView.fieldNum(d,'nSweeps')));
            obj.labelTimeAxis(ax,Key="perm_time");
            % the null
            nul = [];
            if isfield(d,'null'), nul = double(d.null(:)).'; end
            if isempty(nul)
                obj.nullBlank(char(mabr.ui.analysis.TrialView.NoNullText));
                return
            end
            obs = mabr.ui.analysis.TrialView.fieldNum(d,'strength');
            e = mabr.ui.analysis.TrialView.histEdges([nul obs]);
            cnt = histcounts(nul,e);
            [ox,oy] = mabr.ui.analysis.TrialView.stairsOutline(e,cnt);
            obj.put('null_fill_x',H.PermNullFill,'XData',ox);
            obj.put('null_fill_y',H.PermNullFill,'YData',oy);
            obj.putXY('null_line',H.PermNull,ox,oy);
            top = max([cnt 1])*1.1;
            obj.putXY('null_obs',H.PermObserved,[obs obs],[0 top]);
            obj.put('null_text',H.PermNullText,'String','');
            lo = min([e(1) obs]);  hi = max([e(end) obs]);
            if hi <= lo, hi = lo + 1; end
            obj.put('null_xlim',ax2,'XLim',[lo hi] + [-1 1]*0.03*(hi - lo));
            obj.put('null_ylim',ax2,'YLim',[0 top]);
            p = mabr.ui.analysis.TrialView.fieldNum(d,'p');
            obj.put('null_title',ax2.Title,'String',sprintf('Null (%s, B = %d): observed %s, p %s', ...
                method,numel(nul),mabr.ui.analysis.TrialView.num(obs,3),mabr.ui.analysis.TrialView.pText(p)));
            obj.put('null_xlabel',ax2.XLabel,'String',char("Max " + method + " statistic"));
        end

        function nullBlank(obj,txt)
            H = obj.Handles;
            obj.put('null_fill_x',H.PermNullFill,'XData',NaN);
            obj.put('null_fill_y',H.PermNullFill,'YData',NaN);
            obj.putXY('null_line',H.PermNull,NaN,NaN);
            obj.putXY('null_obs',H.PermObserved,NaN,NaN);
            obj.put('null_text',H.PermNullText,'String',txt);
            obj.put('null_title',H.PermNullAxes.Title,'String','Null distribution');
        end

        function tt = permTimes(~,D,d,n)
            % The times (raw ms) of the tested rows: RowsMs(1) to RowsMs(2)
            % of the session's Time.
            rm = [NaN NaN];
            if isfield(d,'RowsMs') && numel(d.RowsMs) == 2, rm = double(d.RowsMs); end
            if all(isfinite(rm))
                k = find(D.T >= rm(1) - 1e-9 & D.T <= rm(2) + 1e-9);
                if numel(k) == n
                    tt = reshape(D.T(k),1,[]);
                    return
                end
                tt = linspace(rm(1),rm(2),n);
                return
            end
            k = find(D.MeasureRows);
            if numel(k) == n, tt = reshape(D.T(k),1,[]); else, tt = 1:n; end
        end

        function mask = sigMaskOf(obj,d,n)
            % What is significant: the clusters with p < alpha for
            % clusterMass (its sigMask compares |t| with a cluster-mass
            % null), the per-sample mask for tmax and tfce.
            mask = false(1,n);
            method = "";
            if isfield(d,'method'), method = string(d.method); end
            if method == "clusterMass"
                alpha = obj.detectAlpha();
                if isfield(d,'clusters') && ~isempty(d.clusters)
                    for k = 1:numel(d.clusters)
                        c = d.clusters(k);
                        if c.p < alpha
                            mask(max(1,c.first):min(n,c.last)) = true;
                        end
                    end
                end
            elseif isfield(d,'sigMask') && numel(d.sigMask) == n
                mask = logical(d.sigMask(:)).';
            end
        end

        function a = detectAlpha(obj)
            a = 0.05;
            S = obj.Model.Session;
            try
                if isfield(S.StepOptions,'detect') && isfield(S.StepOptions.detect,'Alpha')
                    a = S.StepOptions.detect.Alpha;
                    return
                end
            catch
            end
            try
                a = obj.settingsOf(S).Alpha;
            catch
            end
        end

        % ---- header and selection ----------------------------------------
        function drawHeader(obj,S,ck)
            txt = obj.headerText(S,ck);
            obj.put('hdr_text',obj.Handles.Header,'Text',char(txt));
            T = obj.timeAxis();
            tip = 'The selected condition: its sweep counts and the single-trial measures of the analysis.';
            if T.Tip ~= "", tip = [tip ' ' char(T.Tip)]; end
            obj.put('hdr_tip',obj.Handles.Header,'Tooltip',tip);
        end

        function txt = headerText(obj,S,ck)
            % "Tone 8 kHz, 40 dB · N 512 / clean 503 / rejected 9 (manual
            % 2) · RN 0.42 µV · SNR 6.1 dB · F 4.1 (p 0.001) · ..."
            C = S.Conditions;
            r = S.rowOf(ck);
            vars = string(C.Properties.VariableNames);
            v = @(name) mabr.ui.analysis.TrialView.colNum(C,vars,name,r);
            parts = obj.conditionTitle(S,ck);
            n = v('nSweeps');
            rej = v('nRejected');
            nCl = v('nClean');
            man = NaN;  exc = NaN;
            if ismember("Rejected",vars) && ismember("RejectReason",vars)
                try
                    rr = logical(C.Rejected{r});
                    man = sum(rr(:) & double(C.RejectReason{r}(:)) == 3);
                    if ~isfinite(n), n = numel(rr); end
                    if ~isfinite(rej), rej = sum(rr); end
                catch
                end
            end
            if ismember("Excess",vars)
                try
                    exc = sum(logical(C.Excess{r}));
                catch
                end
            end
            if isfinite(n)
                s = sprintf('N %d',n);
                if isfinite(nCl), s = [s sprintf(' / clean %d',nCl)]; end
                if isfinite(rej)
                    s = [s sprintf(' / rejected %d',rej)];
                    if isfinite(man), s = [s sprintf(' (manual %d)',man)]; end
                end
                if isfinite(exc) && exc > 0, s = [s sprintf(' / unused %d',exc)]; end
                parts(end+1) = string(s);
            end
            if isfinite(v('RN')), parts(end+1) = "RN " + mabr.ui.analysis.Style.formatUV(v('RN'),2); end
            if isfinite(v('SNR')), parts(end+1) = string(sprintf('SNR %.1f dB',v('SNR'))); end
            if isfinite(v('F'))
                parts(end+1) = "F " + mabr.ui.analysis.TrialView.num(v('F'),2) + " (p " + mabr.ui.analysis.TrialView.pText(v('PowerP')) + ")";
            end
            if isfinite(v('Fsp'))
                parts(end+1) = "Fsp " + mabr.ui.analysis.TrialView.num(v('Fsp'),2) + " (p " + mabr.ui.analysis.TrialView.pText(v('FspP')) + ")";
            end
            if isfinite(v('SplitR'))
                parts(end+1) = string(sprintf('split-half r %.2f (SD %.2f; partition 2.5–97.5%% %.2f–%.2f)', ...
                    v('SplitR'),v('SplitRSD'),v('SplitRP025'),v('SplitRP975')));
            end
            if isfinite(v('p')), parts(end+1) = "perm p " + mabr.ui.analysis.TrialView.pText(v('p')); end
            w = obj.waveReadout(S,ck);
            if w ~= "", parts(end+1) = w; end
            txt = strjoin(parts," · ");
        end

        function s = conditionTitle(obj,S,ck)
            % "Tone 8 kHz, 40 dB": the series, then the level.
            m = obj.Model;
            s = m.conditionLabel(ck);
            try
                sk = S.seriesOf(ck);
                lp = m.levelParam();
                C = S.Conditions;
                if lp ~= "" && ismember(lp,string(C.Properties.VariableNames))
                    lv = double(C.(lp)(S.rowOf(ck)));
                    if isfinite(lv)
                        u = string(mabr.stim.StimulusSet.paramUnit(lp));
                        if u == "", lt = lp + " " + sprintf('%g',lv); else, lt = sprintf('%g',lv) + " " + u; end
                        s = m.seriesLabel(sk) + ", " + lt;
                    end
                end
            catch
            end
        end

        function w = waveReadout(obj,S,ck)
            % "I 1.42 ms 2.1 µV": the selected wave, else wave I, else the
            % first wave picked at this level -- latency in the axes' time.
            w = "";
            P = S.Peaks;
            if height(P) == 0 || ~all(ismember(["Key","Wave","PeakLatency"],string(P.Properties.VariableNames)))
                return
            end
            rows = find(string(P.Key) == ck);
            if isempty(rows), return; end
            waves = string(P.Wave(rows));
            want = obj.Model.Selection.Wave;
            k = find(waves == want,1);
            if isempty(k), k = find(waves == "I" & isfinite(P.PeakLatency(rows)),1); end
            if isempty(k), k = find(isfinite(P.PeakLatency(rows)),1); end
            if isempty(k), return; end
            i = rows(k);
            lat = double(P.PeakLatency(i));
            if ~isfinite(lat)
                w = waves(k) + " absent";
                return
            end
            w = waves(k) + " " + mabr.ui.analysis.Style.formatMs(obj.earTime(lat),2);
            if ismember("AmpPT",string(P.Properties.VariableNames)) && isfinite(P.AmpPT(i))
                w = w + " " + mabr.ui.analysis.Style.formatUV(double(P.AmpPT(i)),2);
            end
        end

        function drawSelection(obj)
            % The selection: ticks left of the image rows, rings on the
            % feature points, the highlighted sweep, the label and buttons.
            D = obj.Trial;
            H = obj.Handles;
            if isempty(D)
                obj.put('sel_text',H.SelectionLabel,'Text','No sweeps selected');
                obj.enableActions(false);
                return
            end
            sel = obj.selectedCols();
            switch numel(sel)
                case 0, txt = 'No sweeps selected';
                case 1, txt = '1 sweep selected';
                otherwise, txt = sprintf('%d sweeps selected',numel(sel));
            end
            obj.put('sel_text',H.SelectionLabel,'Text',txt);
            t = obj.earTime(D.T);
            span = max(t(end) - t(1),eps);
            rows = find(ismember(D.Display,sel));
            [xs,ys] = mabr.ui.analysis.TrialView.ticks(rows,t(1) - 0.02*span);
            obj.put('img_sel_x',H.ImageSelection,'XData',xs);
            obj.put('img_sel_y',H.ImageSelection,'YData',ys);
            k = sel(D.Visible(sel));
            obj.putXY('feat_sel',H.FeatureSelection,D.PX(k),D.FV(k));
            obj.drawHighlight();
            obj.enableActions(true);
        end

        function cols = selectedCols(obj)
            cols = zeros(1,0);
            D = obj.Trial;
            if isempty(D), return; end
            sel = obj.Model.Selection;
            if sel.ConditionKey ~= D.Key, return; end
            cols = sel.Sweeps(sel.Sweeps >= 1 & sel.Sweeps <= D.N);
            cols = reshape(cols,1,[]);
        end

        function enableActions(obj,on)
            H = obj.Handles;
            D = obj.Trial;
            haveSel = on && ~isempty(obj.selectedCols());
            raw = on && ~isempty(D);
            nMan = 0;
            if raw, nMan = obj.manualCount(D); end
            onoff = @(tf) mabr.ui.analysis.TrialView.onoff(tf);
            obj.put('en_reject',H.Reject,'Enable',onoff(haveSel));
            obj.put('en_restore',H.Restore,'Enable',onoff(haveSel));
            obj.put('en_clear',H.ClearManual,'Enable',onoff(nMan > 0));
            obj.put('en_above',H.RejectAbove,'Enable',onoff(raw));
            obj.put('en_aboveS',H.RejectAboveSeries,'Enable',onoff(raw));
            obj.put('en_aboveV',H.RejectAboveValue,'Enable',onoff(raw));
        end

        function n = manualCount(obj,D)
            % Hand decisions (rejections and restores) on this condition's sweeps.
            n = 0;
            S = obj.Model.Session;
            try
                MR = S.ManualRejections;
                if height(MR) == 0, return; end
                fid = string(S.Files.FileId(D.File));
                k = fid(:) + "#" + string(D.Index(:));
                n = sum(ismember(string(MR.FileId) + "#" + string(MR.SweepIndex),k));
            catch
            end
        end

        % ---- actions -----------------------------------------------------
        function rejectSelected(obj,tf)
            obj.Model.setSweepsRejected(tf);
        end

        function clearManual(obj)
            obj.Model.clearManualRejections("condition");
        end

        function rejectAbove(obj,series)
            D = obj.Trial;
            if isempty(D), return; end
            f = obj.ViewLook.Feature;
            v = obj.rejectValueShown(D);
            if ~mabr.ui.analysis.TrialView.isRatio(f), v = v*1e-6; end
            obj.Model.rejectAbove(v,f,Series=series);
        end

        function selectShown(obj)
            % Every sweep the image shows (a sweep with no time is still
            % shown, though it has no x on a Time axis).
            D = obj.Trial;
            if isempty(D), return; end
            obj.Model.selectSweeps(D.Display);
            if isempty(D.Display), obj.AnchorCol = NaN; else, obj.AnchorCol = D.Display(1); end
            obj.drawSelection();
        end

        function clickAt(obj,k,mods,order)
            % One click on sweep k with the order the clicked plot shows.
            m = obj.Model;
            if any(mods == "shift")
                a = obj.AnchorCol;
                if ~isfinite(a), a = m.Selection.Anchor; end
                pa = find(order == a,1);  pk = find(order == k,1);
                if ~isfinite(a) || isempty(pa) || isempty(pk)
                    m.selectSweeps(k);
                    obj.AnchorCol = k;
                    return
                end
                seg = order(min(pa,pk):max(pa,pk));
                if isequal(m.Selection.Anchor,a) && isequal(sort(seg),min(a,k):max(a,k))
                    m.selectSweeps(k,Mode="extend");
                else
                    m.selectSweeps(seg,Mode="replace");
                end
                obj.AnchorCol = a;
            elseif any(mods == "control")
                m.selectSweeps(k,Mode="toggle");
                obj.AnchorCol = k;
            else
                m.selectSweeps(k);
                obj.AnchorCol = k;
            end
            obj.drawSelection();
        end

        % ---- mouse -------------------------------------------------------
        function onImageDown(obj,evt)
            D = obj.Trial;
            if isempty(D), return; end
            ax = obj.Handles.ImageAxes;
            cp = ax.CurrentPoint;
            row = round(cp(1,2));
            if row < 1 || row > numel(D.Display), return; end
            k = D.Display(row);
            mods = obj.clickMods(ax,evt);
            if mods == "context"
                if ~ismember(k,obj.selectedCols()), obj.clickAt(k,"",D.Display); end
                return
            end
            obj.clickAt(k,mods,D.Display);
        end

        function onFeatureDown(obj,evt)
            D = obj.Trial;
            if isempty(D), return; end
            ax = obj.Handles.FeatureAxes;
            cp = ax.CurrentPoint;
            mods = obj.clickMods(ax,evt);
            if mods == "context"
                k = obj.nearestPoint(cp(1,1),cp(1,2));
                if isfinite(k) && ~ismember(k,obj.selectedCols())
                    obj.clickAt(k,"",obj.featureOrder());
                end
                return
            end
            fig = ancestor(ax,'figure');
            obj.endDrag();
            obj.Drag = struct('X0',cp(1,1),'Y0',cp(1,2),'Mods',mods,'Fig',fig, ...
                'Motion',{fig.WindowButtonMotionFcn},'Up',{fig.WindowButtonUpFcn},'Moved',false);
            fig.WindowButtonMotionFcn = @(~,~) obj.onDragMotion();
            fig.WindowButtonUpFcn = @(~,~) obj.onDragUp();
        end

        function onDragMotion(obj)
            if isempty(obj.Drag) || ~isvalid(obj), return; end
            ax = obj.Handles.FeatureAxes;
            cp = ax.CurrentPoint;
            x = cp(1,1);
            xl = ax.XLim;  yl = ax.YLim;
            if abs(x - obj.Drag.X0) > 0.005*diff(xl)
                obj.Drag.Moved = true;
            end
            h = obj.Handles.FeatureDrag;
            h.XData = [obj.Drag.X0 x x obj.Drag.X0];
            h.YData = [yl(1) yl(1) yl(2) yl(2)];
            h.Visible = 'on';
        end

        function onDragUp(obj)
            if isempty(obj.Drag) || ~isvalid(obj), return; end
            dr = obj.Drag;
            ax = obj.Handles.FeatureAxes;
            cp = ax.CurrentPoint;
            obj.endDrag();
            try
                if dr.Moved
                    obj.selectRange(dr.X0,cp(1,1));
                else
                    k = obj.nearestPoint(dr.X0,dr.Y0);
                    if isfinite(k), obj.clickAt(k,dr.Mods,obj.featureOrder()); end
                end
            catch me
                if ~isempty(obj.Host) && isvalid(obj.Host)
                    obj.Host.setStatus(string(me.message),2);
                end
                mabr.log.vprintf(2,me);
            end
        end

        function endDrag(obj)
            dr = obj.Drag;
            obj.Drag = [];
            if isempty(dr), return; end
            try
                if isvalid(dr.Fig)
                    dr.Fig.WindowButtonMotionFcn = dr.Motion;
                    dr.Fig.WindowButtonUpFcn = dr.Up;
                end
            catch
            end
            try
                obj.Handles.FeatureDrag.Visible = 'off';
            catch
            end
        end

        function k = nearestPoint(obj,x,y)
            % The shown sweep nearest a point of the feature plot, measured
            % in fractions of the axes (NaN when none is close).
            k = NaN;
            D = obj.Trial;
            ax = obj.Handles.FeatureAxes;
            xl = ax.XLim;  yl = ax.YLim;
            c = find(D.Visible & isfinite(D.PX) & isfinite(D.FV));
            if isempty(c), return; end
            d = hypot((D.PX(c) - x)/diff(xl),(D.FV(c) - y)/diff(yl));
            [dm,i] = min(d);
            if dm <= 0.05, k = c(i); end
        end

        function order = featureOrder(obj)
            D = obj.Trial;
            c = find(D.Visible);
            [~,o] = sort(D.PX(c));
            order = c(o);
        end

        function mods = clickMods(~,ax,evt)
            % "" | "shift" | "control" | "context" for the click just made.
            % The figure's SelectionType says 'alt' for a Ctrl+click AND for
            % a right click; the hit's Button (1 left, 3 right) tells them
            % apart, and without one the click is taken as the right click
            % (the context menu opens either way).
            mods = "";
            try
                switch ancestor(ax,'figure').SelectionType
                    case 'extend'
                        mods = "shift";
                    case 'alt'
                        mods = "context";
                        if nargin > 2 && isobject(evt) && isprop(evt,'Button') && evt.Button == 1
                            mods = "control";
                        end
                end
            catch
            end
        end

        % ---- heavy work --------------------------------------------------
        function tf = needsHeavy(obj,D)
            tf = false;
            if D.NClean < 2, return; end
            Hv = obj.Heavy;
            if isempty(Hv) || Hv.Stamp ~= D.Stamp, tf = true; return; end
            L = obj.ViewLook;
            tf = isempty(Hv.Ref) || ...
                (L.PanelD == "convergence" && isempty(Hv.Conv)) || ...
                (L.PanelD == "splithalf" && isempty(Hv.Split)) || ...
                (L.Band == "bootstrap" && any(L.Polarity == ["balanced","positive","negative"]) && ...
                 ~isfield(Hv.Boot,char(L.Polarity)));
        end

        function scheduleHeavy(obj)
            obj.HeavyPending = true;
            if ~obj.Model.AutoRefresh, return; end
            try
                t = obj.ensureTimer();
                if strcmp(t.Running,'on'), stop(t); end
                start(t);
            catch me
                mabr.log.vprintf(2,'Trials view: debounce timer not started (%s).',me.message);
            end
        end

        function t = ensureTimer(obj)
            t = obj.Timer;
            if ~isempty(t) && isvalid(t), return; end
            t = timer('Tag','MABR_OfflineTrials','ExecutionMode','singleShot', ...
                'StartDelay',obj.DebounceSeconds,'BusyMode','drop', ...
                'TimerFcn',@(~,~) obj.onTimer());
            obj.Timer = t;
        end

        function stopTimer(obj)
            try
                if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running,'on')
                    stop(obj.Timer);
                end
            catch
            end
        end

        function onTimer(obj)
            if ~isvalid(obj) || ~obj.HeavyPending, return; end
            try
                if obj.Model.Busy, return; end    % "idle" reschedules it
                if ~obj.IsActive
                    obj.Dirty = true;             % activate() redraws, and asks again
                    return
                end
                obj.runHeavy();
            catch me
                mabr.log.vprintf(1,'Trials view: the single-trial panels failed: %s',me.message);
            end
        end

        function runHeavy(obj)
            % What needs random draws, for the condition drawn: the +/-
            % reference and the split-half partitions (replayed from the
            % condition's stream, as measure() drew them), the convergence,
            % the bootstrap band.
            obj.HeavyPending = false;
            D = obj.Trial;
            S = obj.Model.Session;
            if isempty(D) || isempty(S) || ~S.HasSweeps || D.NClean < 2, return; end
            if obj.Model.Selection.ConditionKey ~= D.Key, return; end
            L = obj.ViewLook;
            o = D.Opts;
            Hv = obj.Heavy;
            if isempty(Hv) || Hv.Stamp ~= D.Stamp
                Hv = struct('Stamp',D.Stamp,'Ref',[],'Boot',struct(),'Conv',[],'Split',[]);
            end
            c = find(D.Clean);
            Xc = D.X(:,c);  pc = D.Pol(c);  sc = D.File(c);
            if isempty(Hv.Ref) || (L.PanelD == "splithalf" && isempty(Hv.Split))
                % the draws of SingleTrial.summary, in its order
                st = mabr.analysis.Stats.conditionStream(o.Seed,D.Key);
                Hv.Ref = mabr.analysis.SingleTrial.plusMinus(Xc,pc,sc,st);
                if L.PanelD == "splithalf"
                    rows = D.MeasureRows;
                    if o.NumPermutations > 0 && any(mabr.ui.analysis.TrialView.usable(Xc,rows))
                        mabr.analysis.SingleTrial.powerTest(Xc,pc,sc,rows,o.NumPermutations,st);
                    end
                    K = [];
                    try
                        k = double(S.Conditions.SplitN(D.Row));
                        if isfinite(k) && k >= 0, K = k; end
                    catch
                    end
                    Hv.Split = mabr.analysis.SingleTrial.splitHalf(Xc,pc,D.SplitRows,K=K, ...
                        Resamples=o.SplitHalfResamples,Mode=o.SplitHalfMode,Stream=st, ...
                        MinPerPolarity=o.SplitHalfMinPerPolarity);
                end
            end
            if L.PanelD == "convergence" && isempty(Hv.Conv)
                [~,ord] = sort(D.Order(c));
                Hv.Conv = mabr.analysis.SingleTrial.convergence(Xc(:,ord),pc(ord),sc(ord), ...
                    D.MeasureRows,[],mabr.analysis.Stats.conditionStream(o.Seed,D.Key + "|convergence"));
            end
            key = char(L.Polarity);
            if L.Band == "bootstrap" && any(L.Polarity == ["balanced","positive","negative"]) && ...
                    ~isfield(Hv.Boot,key)
                switch L.Polarity
                    case "positive", s = pc > 0;  pb = [];
                    case "negative", s = pc < 0;  pb = [];
                    otherwise,       s = true(size(pc));  pb = pc;
                end
                lo = NaN(size(D.X,1),1);  hi = lo;
                if sum(s) >= 2
                    if isempty(pb), pb = ones(1,sum(s)); end
                    [lo,hi] = mabr.analysis.SingleTrial.bootstrapBand(Xc(:,s),pb,sc(s), ...
                        obj.BootstrapReplicates,0.05, ...
                        mabr.analysis.Stats.conditionStream(o.Seed,D.Key + "|band"));
                end
                Hv.Boot.(key) = [lo hi];
            end
            obj.Heavy = Hv;
            obj.HeavyRuns = obj.HeavyRuns + 1;
            obj.drawMean(D);
            obj.drawPanelD(D);
        end

        % ---- settings ----------------------------------------------------
        function st = settingsOf(obj,S)
            % The settings the session was analysed with, else the project's.
            st = [];
            try
                st = S.Settings;
            catch
            end
            if isempty(st), st = obj.Model.Settings; end
            if isempty(st), st = mabr.analysis.Settings(); end
        end

        function o = measureOpts(obj,S)
            % The options measure() last used on this session (StepOptions),
            % else the settings': what the split-half replay must match.
            st = obj.settingsOf(S);
            o = struct('ResponseWindow',S.ResponseWindow,'BaselineWindow',st.BaselineWindow, ...
                'SplitHalfWindow',st.SplitHalfWindow,'SplitHalfMode',st.SplitHalfMode, ...
                'SplitHalfResamples',st.SplitHalfResamples, ...
                'SplitHalfMinPerPolarity',st.SplitHalfMinPerPolarity, ...
                'NumPermutations',st.NumPermutations,'Seed',st.Seed);
            try
                if isfield(S.StepOptions,'measure') && isstruct(S.StepOptions.measure)
                    % exactly what measure() was given -- an empty
                    % SplitHalfWindow included, which it read as the
                    % response window (the settings may say otherwise since)
                    mo = S.StepOptions.measure;
                    for f = string(fieldnames(o)).'
                        if isfield(mo,f) && (~isempty(mo.(f)) || f == "SplitHalfWindow")
                            o.(f) = mo.(f);
                        end
                    end
                end
            catch
            end
            if isempty(o.ResponseWindow), o.ResponseWindow = S.ResponseWindow; end
            if isempty(o.SplitHalfWindow), o.SplitHalfWindow = o.ResponseWindow; end
            o.SplitHalfMode = string(o.SplitHalfMode);
        end

        % ---- small helpers -----------------------------------------------
        function putXY(obj,key,h,x,y)
            obj.put([char(key) '_x'],h,'XData',x);
            obj.put([char(key) '_y'],h,'YData',y);
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function quietAxes(ax)
            % No axes toolbar and no default interactions (the house rule:
            % mabr.ui.hideAxesToolbar + disableDefaultInteractivity). An
            % empty toolbar is given first, so hiding it does not build the
            % default one -- eleven buttons per axes, a tenth of a second
            % each axes, only to hide them.
            try
                axtoolbar(ax,{});
            catch
            end
            mabr.ui.hideAxesToolbar(ax);
            disableDefaultInteractivity(ax);
        end

        function D = derive(D,L)
            % What depends on the look: the feature, the x of every sweep,
            % which sweeps are shown and the image's row order.
            f = L.Feature;
            v = NaN(1,D.N);
            try
                v = reshape(double(D.Features.(char(f))),1,[]);
            catch
            end
            if ~mabr.ui.analysis.TrialView.isRatio(f), v = 1e6*v; end
            D.FV = v;
            switch L.XAxis
                case "time",  D.PX = D.RunTime;
                case "block", D.PX = D.BlockX;
                otherwise,    D.PX = D.Order;
            end
            D.Visible = true(1,D.N);
            if ~L.IncludeRejected, D.Visible = ~D.Rejected; end
            cols = find(D.Visible);
            if L.Order == "feature"
                key = v(cols);
                key(~isfinite(key)) = Inf;
                [~,o] = sortrows([key(:) D.Order(cols).']);
            else
                [~,o] = sort(D.Order(cols));
            end
            D.Display = cols(o);
        end

        function v = cellRow(C,vars,name,r,def,n)
            % One per-sweep cell of row r, as a row; DEF when absent or
            % the wrong length.
            v = def;
            if ~ismember(string(name),vars), return; end
            try
                x = C.(name){r};
                if numel(x) == n, v = reshape(x,1,[]); end
            catch
            end
        end

        function v = colNum(C,vars,name,r)
            v = NaN;
            if ~ismember(string(name),vars), return; end
            try
                x = C.(name)(r);
                if isnumeric(x) || islogical(x), v = double(x); end
            catch
            end
        end

        function v = fieldNum(s,name)
            v = NaN;
            try
                if isfield(s,name) && ~isempty(s.(name)), v = double(s.(name)(1)); end
            catch
            end
        end

        function s = num(v,digits)
            % DIGITS significant digits, never in exponent form for a number
            % that has more whole digits than that ("F 340", not "F 3.4e+02").
            if nargin < 2, digits = 3; end
            if ~isfinite(v), s = "–"; return; end
            s = sprintf('%.*g',digits,v);
            if contains(s,'e+'), s = sprintf('%.0f',v); end
            s = string(s);
        end

        function s = pText(p)
            if ~isfinite(p), s = "–"; return; end
            s = string(sprintf('%.3g',p));
        end

        function tf = isRatio(feature)
            tf = any(string(feature) == ["TemplateAmp","TemplateR"]);
        end

        function s = featureLabel(feature)
            keys = mabr.ui.analysis.TrialView.Features;
            labels = mabr.ui.analysis.TrialView.FeatureLabels;
            s = labels(keys == string(feature));
            if isempty(s), s = string(feature); end
        end

        function s = onoff(tf)
            if tf, s = 'on'; else, s = 'off'; end
        end

        function rows = usable(X,rows)
            % summary's useRows: the rows asked for that hold no NaN.
            rows = logical(rows(:)) & all(isfinite(X),2);
        end

        function [xs,ys] = ticks(rows,x)
            % Short vertical ticks at x, one per row, NaN-separated.
            if isempty(rows)
                xs = NaN;  ys = NaN;
                return
            end
            rows = reshape(rows,1,[]);
            xs = reshape(repmat([x; x; NaN],1,numel(rows)),1,[]);
            ys = reshape([rows - 0.45; rows + 0.45; NaN(1,numel(rows))],1,[]);
        end

        function [bx,by] = bandPolygon(t,lo,hi)
            % One closed polygon per run of finite samples (NaN-separated
            % vertex lists are one patch face per column).
            ok = isfinite(lo) & isfinite(hi) & isfinite(t);
            d = diff([false ok false]);
            a = find(d == 1);  b = find(d == -1) - 1;
            L = max(b - a + 1)*2;
            bx = NaN(L,numel(a));  by = bx;
            for k = 1:numel(a)
                i = a(k):b(k);
                xx = [t(i) fliplr(t(i))];
                yy = [lo(i) fliplr(hi(i))];
                bx(1:numel(xx),k) = xx;
                by(1:numel(yy),k) = yy;
                % pad a short column with its last vertex (a patch face needs
                % every column the same length)
                if numel(xx) < L
                    bx(numel(xx)+1:end,k) = xx(end);
                    by(numel(yy)+1:end,k) = yy(end);
                end
            end
        end

        function [e,cnt] = histEdges(x)
            % Bin edges for a histogram of x: about sqrt(n) bins, 8 to 30.
            x = x(isfinite(x));
            if isempty(x), e = [0 1]; cnt = 0; return; end
            nb = min(30,max(8,round(sqrt(numel(x)))));
            lo = min(x);  hi = max(x);
            if hi <= lo, lo = lo - 0.5; hi = hi + 0.5; end
            e = linspace(lo,hi,nb + 1);
            cnt = histcounts(x,e);
        end

        function [x,y] = stairsOutline(e,cnt)
            % The outline of a histogram, from the baseline round and back.
            e = reshape(e,1,[]);  cnt = reshape(cnt,1,[]);
            x = reshape([e(1:end-1); e(2:end)],1,[]);
            y = reshape([cnt; cnt],1,[]);
            x = [e(1) x e(end)];
            y = [0 y 0];
        end

        function [sx,sy] = spans(mask,x,yl)
            % Rectangles over the runs of a mask (a patch face each).
            d = diff([false mask(:).' false]);
            a = find(d == 1);  b = find(d == -1) - 1;
            if isempty(a)
                sx = NaN;  sy = NaN;
                return
            end
            dx = 0;
            if numel(x) > 1, dx = median(diff(x))/2; end
            sx = [x(a) - dx; x(b) + dx; x(b) + dx; x(a) - dx];
            sy = repmat([yl(1); yl(1); yl(2); yl(2)],1,numel(a));
        end

        function map = divergingMap(n)
            % Blue through white to red: negative and positive voltage.
            St = mabr.ui.analysis.Style;
            h = floor(n/2);
            a = St.DataBlue;  b = St.FitRed;  w = [1 1 1];
            t = linspace(0,1,h).';
            map = [a + (w - a).*t; w + (b - w).*t(2:end); b];
            map = map(1:n,:);
        end
    end
end
