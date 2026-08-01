classdef App < handle
% mabr.ui.App  MABR acquisition GUI (the view).
%
%   A programmatic uifigure app that replaces abr.ControlPanel. It owns a
%   mabr.ui.AcqController and translates button presses into controller
%   actions and controller events into UI updates. There is no global state
%   and no busy-wait: the controller is entirely event-driven, and this view
%   just listens.
%
%   Launch with:  mabr.ui.App   (or the MABR launcher after cutover)
%
%   Start and Preview are the same run: Preview simply hands the controller a
%   Session with no OutputPath, so blocks are acquired, finalized, plotted and
%   organized exactly as usual but no .abr file is written.
%
%   The layout code lives in createComponents (treated as generated); the
%   wiring/logic lives in the callbacks and event handlers below.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        DefaultRateHz = 21.1;   % stimulus presentation rate (Hz)

        % Shared width of the label column in every panel, so the fields line
        % up along one edge down the whole window.
        LabelWidth = 82;

        % Display names for mabr.stim.Schedule.Strategies, in the same order
        % (the dropdown carries the canonical names as ItemsData).
        StrategyItems = { ...
            'Blocked — one stimulus per run', ...
            'Blocked, shuffled run order', ...
            'Interleaved — A B C A B C …', ...
            'Interleaved, shuffled each cycle', ...
            'Fully shuffled'};
    end

    properties (SetAccess = private)
        Config
        Controller  mabr.ui.AcqController
        Stimuli     mabr.stim.StimulusSet
        % Per-stimulus repetition counts. The GUI — not the stimulus package —
        % owns these; RepetitionsDialog edits them, and onStart hands them to
        % the schedule.
        Reps        (1,:) double = []
        % Configuration files most recently saved or loaded, most-recent-first,
        % capped at 9 -- the File > Recent Configurations submenu. Persisted in
        % the same MABR pref group as everything else here (key
        % 'RecentConfigFiles') so the list survives a restart.
        RecentConfigs (1,:) cell = {}
        % Artifact criterion, and what to do about a sweep that fails it. The
        % GUI owns this; it is remembered across sessions in MATLAB prefs
        % (mabr.ArtifactPolicy.loadPrefs) so a rig keeps whatever suits its
        % electrode chain. onStart hands it to the controller, and so does
        % every later edit — the controls stay live during a schedule, see
        % applyArtifacts.
        Artifacts   (1,1) mabr.ArtifactPolicy = mabr.ArtifactPolicy
        % Digital filtering of everything VIEWED. Owned and persisted here on
        % the same terms as Artifacts, edited through mabr.ui.FilterDialog,
        % and equally live during a schedule — the chain only ever decides
        % what a plot or a metric is computed from, never what is recorded,
        % so there is no such thing as changing it at a bad moment.
        Filters     (1,1) mabr.FilterPolicy = mabr.FilterPolicy
        % ASIO device and channel mapping. Owned and persisted on the same
        % terms as Artifacts/Filters (mabr.AudioSettings.loadPrefs), but
        % edited through mabr.ui.AudioSettingsDialog and, unlike those two,
        % a CONFIG control -- it locks once a schedule is running, since the
        % worker's audioPlayerRecorder is already open on whatever device
        % Start handed it (see configControls).
        Audio       (1,1) mabr.AudioSettings = mabr.AudioSettings
        LivePlot    mabr.ui.LivePlot
        TraceOrg    mabr.ui.TraceOrganizer
        StimViewer  mabr.ui.StimulusViewer
        TestRunner  mabr.ui.TestRunner
        Listeners
    end

    % --- UI components ------------------------------------------------------
    properties (Access = private)
        UIFigure
        FileMenu
        SaveConfigMenuItem
        LoadConfigMenuItem
        RecentConfigsMenu
        SettingsMenu
        AudioMenuItem
        CalMenuItem
        HelpMenu
        TestMenuItem
        Toolbar
        Grid
        SubjectField
        OutputField
        BrowseButton
        SourceLabel
        DesignButton
        LoadButton
        TestButton
        % The stimgen bank editor, while one is open. Held so the Design button
        % can turn into "Adopt bank" and pull the current bank back out; see
        % onDesignStimuli.
        Designer
        StrategyDrop
        RepsField
        RepsButton
        AdvanceDrop
        CorrField
        % A user-selected custom advance function, once one has been chosen
        % through the dropdown's "Custom…" item. The handle is resolved from
        % the picked .m file (its folder added to the path) and validated
        % against the mabr.stim.advance contract before it is accepted; the
        % file path is what a configuration saves, so it can be re-resolved on
        % load rather than serialising a fragile handle. LastAdvanceValue is
        % the last good, non-sentinel dropdown selection, used to fall back
        % when a Custom… pick is cancelled or rejected.
        CustomAdvanceFcn  = []
        CustomAdvanceName (1,:) char = ''
        CustomAdvanceFile (1,:) char = ''
        LastAdvanceValue  (1,:) char = 'All Repetitions'
        ArtifactDrop
        ArtifactField
        ArtifactRepeatCheck
        ArtifactLabel
        FilterLabel
        FilterButton
        ISIField
        RateField
        JitterCheck
        ISIMinField
        ISIMaxField
        OverlapLabel
        PlanLabel
        RunPanel
        StartButton
        PreviewButton
        RepeatButton
        PauseButton
        StopButton
        AbortButton
        StateLamp
        StateLabel
        SweepLabel
        CorrLabel
        StatusLabel
        % Sweeps rejected so far this schedule, for the Run panel readout:
        % ArtifactCount is what finalized blocks reported, LiveArtifacts what
        % the run currently in flight has previewed (and has not yet reported).
        ArtifactCount (1,1) double = 0
        LiveArtifacts (1,1) double = 0
        % True while the schedule now running was launched with Preview, i.e.
        % with the Session's OutputPath deliberately left empty so nothing is
        % written. Set at Start and left alone until the next one, so the
        % completion message can still say the run was not saved.
        Previewing (1,1) logical = false
    end

    methods
        function app = App()
            app.Config = mabr.Config;
            try
                app.Config.verifyToolboxes(true);
            catch me
                uialert_or_warn(me.message);
            end
            app.Artifacts = mabr.ArtifactPolicy.loadPrefs();
            app.Filters   = mabr.FilterPolicy.loadPrefs();
            app.Audio     = mabr.AudioSettings.loadPrefs();
            rc = getpref('MABR','RecentConfigFiles',{});
            if iscell(rc), app.RecentConfigs = rc; end
            app.createComponents();
            app.syncAdvanceEnables();
            app.syncArtifactFields();
            app.syncFilterFields();
            app.syncISIFields();
            app.syncRecentConfigsMenu();
            if nargout == 0, clear app; end
        end

        function delete(app)
            % Whatever layout the user ended up with is the one they want back
            % next session, so capture it before anything is torn down.
            app.rememberViewerPositions();
            mabr.ui.WindowPos.remember(app.UIFigure,'MABR');
            try, delete(app.Listeners);  end %#ok<TRYNC>
            try, delete(app.Controller); end %#ok<TRYNC>
            try, delete(app.TraceOrg);   end %#ok<TRYNC>
            try, delete(app.LivePlot);   end %#ok<TRYNC>
            try, delete(app.StimViewer); end %#ok<TRYNC>
            try, delete(app.TestRunner); end %#ok<TRYNC>
            try, delete(app.UIFigure);   end %#ok<TRYNC>
        end
    end

    % ===================================================================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','MABR', 'Position',[100 100 480 700], ...
                'CloseRequestFcn',@(~,~) app.onClose());
            mabr.ui.WindowPos.restore(app.UIFigure,'MABR',app.UIFigure.Position);

            app.FileMenu = uimenu(app.UIFigure,'Text','&File');
            app.SaveConfigMenuItem = uimenu(app.FileMenu,'Text','Save Configuration…', ...
                'Tooltip','Save subject/output, bank, presentation, artifact, filter, and audio settings to one file.', ...
                'MenuSelectedFcn',@(~,~) app.onSaveConfiguration());
            app.LoadConfigMenuItem = uimenu(app.FileMenu,'Text','Load Configuration…', ...
                'Separator','on', ...
                'Tooltip','Restore a previously saved configuration.', ...
                'MenuSelectedFcn',@(~,~) app.onLoadConfiguration());
            app.RecentConfigsMenu = uimenu(app.FileMenu,'Text','Recent Configurations', ...
                'Tooltip','Reload one of the last 9 configurations saved or loaded.');

            app.SettingsMenu = uimenu(app.UIFigure,'Text','&Settings');
            app.AudioMenuItem = uimenu(app.SettingsMenu,'Text','Audio Device (ASIO)…', ...
                'MenuSelectedFcn',@(~,~) app.onAudioSettings());
            app.CalMenuItem = uimenu(app.SettingsMenu,'Text','Calibration…', ...
                'MenuSelectedFcn',@(~,~) app.onCalibration());

            app.HelpMenu = uimenu(app.UIFigure,'Text','&Help');
            uimenu(app.HelpMenu,'Text','MABR Wiki', ...
                'MenuSelectedFcn',@(~,~) app.openHelp());
            app.TestMenuItem = uimenu(app.HelpMenu,'Text','Verification Tests…', ...
                'Separator','on','MenuSelectedFcn',@(~,~) app.onTestRunner());

            app.buildToolbar();

            % The window reads top to bottom in the order the work is actually
            % done: who and where, what to play, how to order it, when to stop,
            % then run it. Each stage is a titled panel so the eye can jump
            % straight to one instead of reading every label in between --
            % before this the controls were one undifferentiated 13-row list.
            % Panels get explicit heights rather than 'fit' because 'fit' does
            % not see through a panel to its nested grid.
            app.Grid = uigridlayout(app.UIFigure,[7 1]);
            app.Grid.ColumnWidth = {'1x'};
            app.Grid.RowHeight   = {96,60,196,150,'1x',96,22};
            app.Grid.RowSpacing  = 8;
            app.Grid.Padding     = [10 10 10 6];

            app.buildSessionPanel(1);
            app.buildStimulusPanel(2);
            app.buildPresentationPanel(3);
            app.buildAcquisitionPanel(4);
            % Row 5 is a spacer: it absorbs spare height so the run controls
            % stay pinned to the bottom of the window at any size.
            app.buildRunPanel(6);

            app.StatusLabel = uilabel(app.Grid,'Text','Ready.','FontColor',[0.3 0.3 0.3]);
            app.StatusLabel.Layout.Row = 7; app.StatusLabel.Layout.Column = 1;
        end

        % --- Layout building blocks -----------------------------------------
        % Every panel shares one label-column width, so the fields line up in a
        % single vertical edge down the whole window even across panel borders.
        function g = panelGrid(app,title,row,rowHeights,colWidths)
            p = uipanel(app.Grid,'Title',title,'FontWeight','bold');
            p.Layout.Row = row; p.Layout.Column = 1;
            g = uigridlayout(p,[numel(rowHeights) numel(colWidths)]);
            g.RowHeight     = rowHeights;
            g.ColumnWidth   = colWidths;
            g.Padding       = [8 6 8 6];
            g.RowSpacing    = 6;
            g.ColumnSpacing = 6;
        end

        function addLabel(~,g,txt,r,c)
            h = uilabel(g,'Text',txt,'HorizontalAlignment','right');
            h.Layout.Row = r; h.Layout.Column = c;
        end

        function buildSessionPanel(app,row)
            g = app.panelGrid('Session',row,{24,24},{app.LabelWidth,'1x','fit'});

            app.addLabel(g,'Subject ID',1,1);
            app.SubjectField = uidropdown(g,'Editable','on', ...
                'Items',app.loadHistory('Subject',{'SUBJ_ID_001'}), ...
                'Tooltip','Labels the session and begins every saved filename.');
            app.SubjectField.Value = app.SubjectField.Items{1};
            app.SubjectField.Layout.Row = 1; app.SubjectField.Layout.Column = [2 3];

            app.addLabel(g,'Output',2,1);
            app.OutputField = uidropdown(g,'Editable','on', ...
                'Items',app.loadHistory('Output',{pwd}), ...
                'Tooltip','Folder for .abr files, one per condition. Leave empty to record without saving.');
            app.OutputField.Value = app.OutputField.Items{1};
            app.OutputField.Layout.Row = 2; app.OutputField.Layout.Column = 2;
            app.BrowseButton = uibutton(g,'Text','Browse…','ButtonPushedFcn',@(~,~) app.onBrowse());
            app.BrowseButton.Layout.Row = 2; app.BrowseButton.Layout.Column = 3;
        end

        function buildStimulusPanel(app,row)
            g = app.panelGrid('Stimulus',row,{24},{app.LabelWidth,'1x','fit','fit','fit'});

            % The count doubles as the loaded/not-loaded indicator, so it sits
            % where a value would: in the field column, not tucked by a button.
            app.addLabel(g,'Bank',1,1);
            app.SourceLabel = uilabel(g,'Text','(none loaded)','FontColor',[0.6 0 0]);
            app.SourceLabel.Layout.Row = 1; app.SourceLabel.Layout.Column = 2;

            % Leftmost of the three, and the suggested route: stimgen is where
            % a calibrated bank comes from. The other two remain because the
            % contract is the struct array, not the package -- a bank built any
            % other way is still a first-class bank.
            app.DesignButton = uibutton(g,'Text','Design…', ...
                'ButtonPushedFcn',@(~,~) app.onDesignStimuli());
            app.DesignButton.Layout.Row = 1; app.DesignButton.Layout.Column = 3;

            app.LoadButton = uibutton(g,'Text','Load bank…', ...
                'Tooltip','Load a stimulus bank: a stimgen .spl, or a .mat holding the struct array.', ...
                'ButtonPushedFcn',@(~,~) app.onLoadSource());
            app.LoadButton.Layout.Row = 1; app.LoadButton.Layout.Column = 4;

            app.TestButton = uibutton(g,'Text','Demo', ...
                'Tooltip','Load the built-in tone-pip bank (testing only -- not calibrated).', ...
                'ButtonPushedFcn',@(~,~) app.onTestSource());
            app.TestButton.Layout.Row = 1; app.TestButton.Layout.Column = 5;

            app.syncDesignButton();
        end

        function buildPresentationPanel(app,row)
            g = app.panelGrid('Presentation',row,{24,24,24,24,16,18},{app.LabelWidth,'1x','1x'});

            app.addLabel(g,'Strategy',1,1);
            app.StrategyDrop = uidropdown(g, ...
                'Items',mabr.ui.App.StrategyItems, ...
                'ItemsData',mabr.stim.Schedule.Strategies, ...
                'Tooltip','How the bank is ordered: one stimulus per run, or intermixed within a run.', ...
                'ValueChangedFcn',@(~,~) app.onStrategyChanged());
            app.StrategyDrop.Layout.Row = 1; app.StrategyDrop.Layout.Column = [2 3];

            app.addLabel(g,'Repetitions',2,1);
            app.RepsField = uieditfield(g,'numeric','Value',512, ...
                'Limits',[0 Inf],'RoundFractionalValues','on', ...
                'Tooltip','Presentations per stimulus. Sets every entry in the bank at once.', ...
                'ValueChangedFcn',@(~,~) app.onRepsChanged());
            app.RepsField.Layout.Row = 2; app.RepsField.Layout.Column = 2;
            app.RepsButton = uibutton(g,'Text','Per stimulus…', ...
                'Tooltip','Give individual stimuli their own repetition counts.', ...
                'ButtonPushedFcn',@(~,~) app.onRepsDialog());
            app.RepsButton.Layout.Row = 2; app.RepsButton.Layout.Column = 3;

            % Two views of one number; the units live in the display format so
            % the pair needs no second label to say which is which.
            app.addLabel(g,'ISI / Rate',3,1);
            app.ISIField = uieditfield(g,'numeric', ...
                'Value',1e3/mabr.ui.App.DefaultRateHz,'Limits',[eps Inf], ...
                'ValueDisplayFormat','%.2f ms', ...
                'Tooltip','Onset-to-onset interval. Editing this updates the rate.', ...
                'ValueChangedFcn',@(~,~) app.onISIChanged());
            app.ISIField.Layout.Row = 3; app.ISIField.Layout.Column = 2;
            app.RateField = uieditfield(g,'numeric', ...
                'Value',mabr.ui.App.DefaultRateHz,'Limits',[eps Inf], ...
                'ValueDisplayFormat','%.2f Hz', ...
                'Tooltip','Presentation rate. Editing this updates the ISI.', ...
                'ValueChangedFcn',@(~,~) app.onRateChanged());
            app.RateField.Layout.Row = 3; app.RateField.Layout.Column = 3;

            % Randomized ISI: the switch and the two bounds it governs read as
            % one setting, so they share a row inside the field columns with
            % the label column left empty -- the same shape the artifact-repeat
            % checkbox uses. Checking it takes the ISI/Rate fields above out of
            % play entirely (syncISIFields greys them), because the interval is
            % then drawn per presentation and no single number describes it.
            j = uigridlayout(g,[1 3]);
            j.Layout.Row = 4; j.Layout.Column = [2 3];
            j.ColumnWidth   = {'fit','1x','1x'};
            j.Padding       = [0 0 0 0];
            j.ColumnSpacing = 6;

            app.JitterCheck = uicheckbox(j,'Text','Random', ...
                'Tooltip',['Draw each interval uniformly from the range beside it ' ...
                           'instead of holding the ISI fixed, so the presentation rate ' ...
                           'carries no periodicity of its own.'], ...
                'ValueChangedFcn',@(~,~) app.onJitterChanged());
            isi0 = 1e3/mabr.ui.App.DefaultRateHz;
            app.ISIMinField = uieditfield(j,'numeric', ...
                'Value',round(0.9*isi0,2),'Limits',[eps Inf], ...
                'ValueDisplayFormat','%.2f ms','Enable','off', ...
                'Tooltip','Shortest interval that can be drawn.', ...
                'ValueChangedFcn',@(~,~) app.onISIRangeChanged('min'));
            app.ISIMaxField = uieditfield(j,'numeric', ...
                'Value',round(1.1*isi0,2),'Limits',[eps Inf], ...
                'ValueDisplayFormat','%.2f ms','Enable','off', ...
                'Tooltip','Longest interval that can be drawn.', ...
                'ValueChangedFcn',@(~,~) app.onISIRangeChanged('max'));

            % A full-width warning line directly under the fields that cause
            % it, rather than a clipped stub squeezed in beside them.
            app.OverlapLabel = uilabel(g,'Text','','FontColor',[0.8 0.2 0]);
            app.OverlapLabel.Layout.Row = 5; app.OverlapLabel.Layout.Column = [2 3];

            % Live consequence of everything above it: runs, presentations,
            % estimated duration. Kept in this panel because those are the
            % settings that change it.
            app.PlanLabel = uilabel(g,'Text','','FontColor',[0.3 0.3 0.3], ...
                'HorizontalAlignment','right');
            app.PlanLabel.Layout.Row = 6; app.PlanLabel.Layout.Column = [1 3];
        end

        function buildAcquisitionPanel(app,row)
            g = app.panelGrid('Acquisition',row,{24,24,24,24},{app.LabelWidth,'1x','1x'});

            % Early stop only applies to a run holding one stimulus, so this is
            % disabled for intermixed strategies (see syncAdvanceEnables).
            app.addLabel(g,'Advance',1,1);
            app.AdvanceDrop = uidropdown(g, ...
                'Items',{'All Repetitions','Correlation Threshold','Custom…'}, ...
                'Tooltip',['When a run ends: after every repetition, once the response is ' ...
                           'reproducible enough, or by your own criterion. "Custom…" prompts ' ...
                           'for a function file — see +mabr/+stim/+advance/custom_template.m.'], ...
                'ValueChangedFcn',@(~,~) app.onAdvanceSelected());
            app.AdvanceDrop.Layout.Row = 1; app.AdvanceDrop.Layout.Column = 2;
            % The threshold field is captioned by its own display format --
            % as a bare "0.50" beside a dropdown it read as an orphan.
            app.CorrField = uieditfield(g,'numeric','Value',0.5,'Limits',[0 1], ...
                'ValueDisplayFormat','stop at r ≥ %.2f','Enable','off', ...
                'Tooltip','Correlation the running average must reach for the run to stop early.');
            app.CorrField.Layout.Row = 1; app.CorrField.Layout.Column = 3;

            % One threshold field serves both criteria -- they are alternatives,
            % never both at once, and two fields with only one ever live read as
            % a setting the user had forgotten to fill in. The display format
            % says which criterion the number belongs to, so the pair needs no
            % separate unit label (same trick as ISI/Rate above).
            %
            % Unlike everything above them these three stay LIVE during a
            % schedule: the criterion is applied when a run is finalized, not
            % while it streams, so retuning it is a decision about the next
            % block rather than an edit to the one in flight. That is what the
            % setting is for -- an electrode that starts drifting an hour in is
            % exactly when you need a threshold you can move.
            app.addLabel(g,'Artifacts',2,1);
            app.ArtifactDrop = uidropdown(g, ...
                'Items',mabr.ArtifactPolicy.ModeItems, ...
                'ItemsData',mabr.ArtifactPolicy.Modes, ...
                'Value',app.Artifacts.Mode, ...
                'Tooltip',['How a sweep is judged contaminated. Rejected sweeps are always ' ...
                           'marked and saved -- never silently discarded. Adjustable while ' ...
                           'acquiring: a change applies to every block finalized after it.'], ...
                'ValueChangedFcn',@(~,~) app.onArtifactModeChanged());
            app.ArtifactDrop.Layout.Row = 2; app.ArtifactDrop.Layout.Column = 2;
            app.ArtifactField = uieditfield(g,'numeric','Limits',[eps Inf], ...
                'Tooltip',['Sweeps beyond this are rejected. Each criterion keeps its own ' ...
                           'value. Adjustable while acquiring.'], ...
                'ValueChangedFcn',@(~,~) app.onArtifactThresholdChanged());
            app.ArtifactField.Layout.Row = 2; app.ArtifactField.Layout.Column = 3;

            app.ArtifactRepeatCheck = uicheckbox(g, ...
                'Text','Repeat sweeps lost to artifact','Value',app.Artifacts.Repeat, ...
                'Tooltip',['On: re-present each rejected sweep in a make-up run appended to ' ...
                           'the end of the schedule, so every condition still reaches its ' ...
                           'requested count. Off: just count them. Clearing it mid-schedule ' ...
                           'also withdraws the make-up runs not yet reached.'], ...
                'ValueChangedFcn',@(~,~) app.onArtifactRepeatChanged());
            app.ArtifactRepeatCheck.Layout.Row = 3;
            app.ArtifactRepeatCheck.Layout.Column = [2 3];

            % Filtering gets a summary and a button rather than four fields
            % inline: three independent filters need eight controls to state
            % properly and a response plot to be worth anything, which is a
            % window, not a panel row. The summary carries the whole setting
            % in one line, so the button is only pressed to CHANGE it.
            %
            % Live during a schedule for the same reason the artifact controls
            % are, only more so: the chain decides what a plot is drawn from,
            % never what is recorded, so there is no moment at which changing
            % it can cost anything.
            app.addLabel(g,'Filters',4,1);
            app.FilterLabel = uilabel(g,'Text','', ...
                'Tooltip','Applies to the live plot and the sweep metrics. Saved files stay raw.');
            app.FilterLabel.Layout.Row = 4; app.FilterLabel.Layout.Column = 2;
            app.FilterButton = uibutton(g,'Text','Filters…', ...
                'Tooltip',['Set the high pass, low pass, and notch applied to the data as ' ...
                           'you view it. The raw trace is what gets saved. Adjustable while ' ...
                           'acquiring.'], ...
                'ButtonPushedFcn',@(~,~) app.onFilters());
            app.FilterButton.Layout.Row = 4; app.FilterButton.Layout.Column = 3;
        end

        function buildRunPanel(app,row)
            g = app.panelGrid('Run',row,{22,32},{'1x','1x','1x','1x','1x','1x'});
            % Kept so a preview can say so in the title: it is the one caption
            % here with room for the words, and it sits directly above the
            % button that started the run.
            app.RunPanel = g.Parent;

            % Readout and transport share a panel: what the run is doing and
            % what you can do about it belong to the same glance.
            s = uigridlayout(g,[1 5]);
            s.Layout.Row = 1; s.Layout.Column = [1 6];
            % Fixed width for the state label rather than 'fit', so the sweep
            % count does not slide sideways as the state text changes length.
            s.ColumnWidth   = {18,112,'1x','fit','fit'};
            s.Padding       = [0 0 0 0];
            s.ColumnSpacing = 8;
            app.StateLamp  = uilamp(s,'Color',[0.6 0.6 0.6]);
            app.StateLabel = uilabel(s,'Text','Idle','FontWeight','bold');
            app.SweepLabel = uilabel(s,'Text','Sweeps: 0');
            app.CorrLabel  = uilabel(s,'Text','r = —','HorizontalAlignment','right');
            % Rejection count lives beside the other live readouts rather than
            % in the status line, which the per-block "Saved ..." messages would
            % otherwise overwrite as soon as it appeared.
            app.ArtifactLabel = uilabel(s,'Text','','HorizontalAlignment','right', ...
                'FontColor',[0.8 0.2 0], ...
                'Tooltip','Sweeps rejected as artifact so far this schedule.');

            app.StartButton = uibutton(g,'Text','Start','BackgroundColor',[0.6 0.9 0.6], ...
                'FontWeight','bold','ButtonPushedFcn',@(~,~) app.onStart());
            app.StartButton.Layout.Row = 2; app.StartButton.Layout.Column = 1;
            % Preview runs the identical schedule -- same stimuli, same
            % acquisition, same live view and organizer traces -- with the
            % Session's output folder left empty, so no .abr file is written.
            % For checking an electrode placement or an ISI without leaving
            % junk files behind.
            app.PreviewButton = uibutton(g,'Text','Preview','BackgroundColor',[0.85 0.9 0.98], ...
                'Tooltip','Run the schedule exactly as Start does, but write no .abr files.', ...
                'ButtonPushedFcn',@(~,~) app.onStart(true));
            app.PreviewButton.Layout.Row = 2; app.PreviewButton.Layout.Column = 2;
            % Only meaningful once a blocked-strategy run has completed (an
            % intermixed run has no single stimulus to repeat), so it starts
            % disabled and is re-derived by syncRepeatEnable rather than by
            % transport()'s blanket running/idle split -- see canRepeat().
            app.RepeatButton = uibutton(g,'Text','Repeat','Enable','off', ...
                'Tooltip',['Run one more full block of the same stimulus. Blocked ' ...
                           'strategies only -- an intermixed run has no single ' ...
                           'stimulus to repeat.'], ...
                'ButtonPushedFcn',@(~,~) app.onRepeat());
            app.RepeatButton.Layout.Row = 2; app.RepeatButton.Layout.Column = 3;
            app.PauseButton = uibutton(g,'Text','Pause','Enable','off', ...
                'Tooltip','Suspend playback in place, keeping the audio device open.', ...
                'ButtonPushedFcn',@(~,~) app.onPause());
            app.PauseButton.Layout.Row = 2; app.PauseButton.Layout.Column = 4;
            app.StopButton = uibutton(g,'Text','Advance','Enable','off', ...
                'Tooltip','End the current run early and advance to the next.', ...
                'ButtonPushedFcn',@(~,~) app.onStopBlock());
            app.StopButton.Layout.Row = 2; app.StopButton.Layout.Column = 5;
            app.AbortButton = uibutton(g,'Text','Abort','Enable','off','BackgroundColor',[0.95 0.7 0.7], ...
                'Tooltip','Abandon the whole schedule. Data already recorded is still saved.', ...
                'ButtonPushedFcn',@(~,~) app.onAbort());
            app.AbortButton.Layout.Row = 2; app.AbortButton.Layout.Column = 6;
        end

        function buildToolbar(app)
            % Every viewer opens on demand from here. The acquisition pair also
            % opens by itself at Start/Preview (see openViewers), so in practice
            % these two are usually "bring to front" during a run and "show"
            % before one. Each glyph draws
            % what its window shows -- one trace on axes, a stack of traces,
            % a loudspeaker -- so the toolbar reads without the tooltip, the
            % same convention mabr.ui.TraceOrganizer's toolbar uses.
            ink  = [0.16 0.26 0.42];
            help = [0.35 0.35 0.35];

            app.Toolbar = uitoolbar(app.UIFigure);
            app.toolButton('live',  ink, 'Live plot',        @() app.onShowLive());
            app.toolButton('traces',ink, 'Trace organizer',  @() app.onTraceOrg());
            app.toolButton('stim',  ink, 'Stimulus viewer',  @() app.onStimViewer());
            app.toolButton('help',  help,'Help (MABR wiki)', @() app.openHelp(),true);
        end

        function toolButton(app,glyph,rgb,tip,fcn,sep)
            if nargin < 6, sep = false; end
            sepStr = 'off'; if sep, sepStr = 'on'; end
            uipushtool(app.Toolbar,'Tooltip',tip,'Separator',sepStr, ...
                'CData',mabr.ui.Icon.fromArt(mabr.ui.App.glyph(glyph),rgb), ...
                'ClickedCallback',@(~,~) fcn());
        end

        function openHelp(~)
            web('https://github.com/dstolz/MABR/wiki','-browser');
        end

        function onTestRunner(app)
            % The verification suite builds its OWN engine and worker (and,
            % for the engine tests, its own parallel pool), so it cannot share
            % the rig with a schedule in flight -- hence a config control (see
            % configControls) rather than a live one. The window itself is
            % independent of this one and can be opened standalone.
            if ~isempty(app.TestRunner) && isvalid(app.TestRunner)
                app.TestRunner.raise();
                return
            end
            app.TestRunner = mabr.ui.TestRunner();
            app.setStatus('Verification tests opened — nothing there touches saved data.');
        end

        % --- Editable-dropdown history -------------------------------------
        % Subject ID and Output are editable dropdowns: free text is allowed,
        % and whatever gets used is remembered (most-recent first) across
        % sessions via MATLAB prefs.
        function items = loadHistory(~,name,defaults)
            items = getpref('MABR',['History_' name],defaults);
            if ~iscellstr(items) || isempty(items), items = defaults; end %#ok<ISCLSTR>
        end

        function rememberValue(app,field,name)
            v = strtrim(field.Value);
            if isempty(v), return; end
            items = [{v} field.Items(~strcmp(field.Items,v))];
            if numel(items) > 10, items = items(1:10); end
            field.Items = items;
            field.Value = v;
            setpref('MABR',['History_' name],items);
        end

        % Editable dropdowns reject a programmatic Value that is not in Items,
        % so add it first.
        function setDropValue(~,field,v)
            if ~any(strcmp(field.Items,v)), field.Items = [{v} field.Items]; end
            field.Value = v;
        end

        % --- Save/load configuration -----------------------------------------
        % A named, shareable snapshot of an entire experiment setup -- bank,
        % reps, strategy, ISI, artifacts, filters, audio -- in one file, the
        % direct analogue of the legacy +abr ConfigTab's "Save/Load a Config
        % file". This is distinct from the individual loadPrefs/savePrefs
        % each settings object already does on every change: those remember
        % the LAST used choice per rig, while a configuration file is a
        % deliberately saved, reloadable point a user names and returns to
        % (e.g. switching between protocols on the same rig). Loading one also
        % updates the prefs, exactly as editing each setting by hand would.
        function onSaveConfiguration(app)
            dflt = 'MABR_Config.mabrcfg';
            if ~isempty(app.SubjectField.Value)
                dflt = [matlab.lang.makeValidName(app.SubjectField.Value) '.mabrcfg'];
            end
            [fn,pn] = uiputfile({'*.mabrcfg','MABR configuration (*.mabrcfg)'}, ...
                'Save configuration',dflt);
            figure(app.UIFigure);
            if isequal(fn,0), return; end
            try
                file = fullfile(pn,fn);
                MABRConfig = app.captureConfiguration();
                save(file,'MABRConfig');
                app.setStatus(['Configuration saved to ' fn '.']);
                app.addRecentConfig(file);
            catch me
                app.setStatus(['Save configuration failed: ' me.message]);
            end
        end

        function onLoadConfiguration(app)
            [fn,pn] = uigetfile({'*.mabrcfg','MABR configuration (*.mabrcfg)'}, ...
                'Load configuration');
            figure(app.UIFigure);
            if isequal(fn,0), return; end
            app.loadConfigurationFile(fullfile(pn,fn));
        end

        function onLoadRecentConfiguration(app,file)
            % File > Recent Configurations entry. A file can vanish between
            % sessions (moved, deleted, a network drive unmounted); rather
            % than erroring, drop it from the list and say so -- the same
            % self-healing rule applyConfigStimuli follows for a stimulus
            % bank that has moved.
            if ~isfile(file)
                app.setStatus(['Recent configuration "' file '" no longer exists.']);
                app.removeRecentConfig(file);
                return
            end
            app.loadConfigurationFile(file);
        end

        function loadConfigurationFile(app,file)
            % Shared by the Load Configuration… dialog and a Recent
            % Configurations click, so both end up on one list and one status
            % message.
            try
                S = load(file,'-mat');
                assert(isfield(S,'MABRConfig'),'mabr:ui:App:badConfig', ...
                    '"%s" is not a MABR configuration file.',file);
                warn = app.applyConfiguration(S.MABRConfig);
                [~,fn,ext] = fileparts(file);
                msg  = ['Configuration loaded from ' fn ext '.'];
                if ~isempty(warn), msg = [msg ' ' warn]; end
                app.setStatus(msg);
                app.addRecentConfig(file);
            catch me
                app.setStatus(['Load configuration failed: ' me.message]);
            end
        end

        function addRecentConfig(app,file)
            % Move file to the front of the recent list (dropping any earlier
            % entry for the same path), cap at 9, persist, and rebuild the menu.
            file = char(file);
            list = app.RecentConfigs;
            list(strcmpi(list,file)) = [];
            list = [{file}, list];
            if numel(list) > 9, list = list(1:9); end
            app.RecentConfigs = list;
            setpref('MABR','RecentConfigFiles',list);
            app.syncRecentConfigsMenu();
        end

        function removeRecentConfig(app,file)
            list = app.RecentConfigs;
            list(strcmpi(list,file)) = [];
            app.RecentConfigs = list;
            setpref('MABR','RecentConfigFiles',list);
            app.syncRecentConfigsMenu();
        end

        function syncRecentConfigsMenu(app)
            % Rebuild the File > Recent Configurations submenu from
            % app.RecentConfigs -- most-recently-used at the top. Numbered so
            % the list order (and therefore recency) is visible at a glance,
            % titled with the file name only (the full path is the tooltip)
            % since a subject-named file is what the operator actually reads.
            delete(app.RecentConfigsMenu.Children);
            if isempty(app.RecentConfigs)
                uimenu(app.RecentConfigsMenu,'Text','(No Recent Configurations)', ...
                    'Enable','off');
                return
            end
            for k = 1:numel(app.RecentConfigs)
                file = app.RecentConfigs{k};
                [~,name,ext] = fileparts(file);
                uimenu(app.RecentConfigsMenu,'Text',sprintf('%d  %s%s',k,name,ext), ...
                    'Tooltip',file, ...
                    'MenuSelectedFcn',@(~,~) app.onLoadRecentConfiguration(file));
            end
        end

        function cfg = captureConfiguration(app)
            % Everything a configuration restores, as plain structs -- never
            % classdef objects -- so a file saved by this version still loads
            % after a class gains or loses a property (see applyConfiguration).
            cfg = struct();
            cfg.FormatVersion = 1;
            cfg.Saved         = datetime('now');
            cfg.Subject       = app.SubjectField.Value;
            cfg.OutputPath    = app.OutputField.Value;

            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0
                cfg.StimulusSource = mabr.stim.StimulusSet.emptySource();
                cfg.Reps           = struct('ID',{},'Count',{});
            else
                cfg.StimulusSource = app.Stimuli.Source;
                ids  = app.Stimuli.IDs();
                cfg.Reps = struct('ID',ids(:),'Count',num2cell(app.Reps(:)));
            end

            cfg.Strategy      = app.StrategyDrop.Value;
            cfg.Advance       = app.AdvanceDrop.Value;
            cfg.CorrThreshold = app.CorrField.Value;
            % A custom criterion is saved as its FILE, not its handle: a path
            % re-resolves across sessions and MABR versions where a serialised
            % handle (with its captured workspace) would not. cfg.Advance
            % above already holds the "Custom: <name>" label to reselect.
            cfg.AdvanceCustomFile = app.CustomAdvanceFile;
            cfg.AdvanceCustomName = app.CustomAdvanceName;
            cfg.ISIRandom     = app.JitterCheck.Value;
            cfg.ISI_ms        = app.ISIField.Value;
            cfg.ISIMin_ms     = app.ISIMinField.Value;
            cfg.ISIMax_ms     = app.ISIMaxField.Value;

            cfg.Artifacts = app.Artifacts.toStruct();
            cfg.Filters   = app.Filters.toStruct();
            cfg.Audio     = app.Audio.toStruct();
        end

        function warn = applyConfiguration(app,cfg)
            % Defensive throughout: a configuration saved by an older MABR, or
            % edited by hand, restores whatever it can rather than refusing
            % the whole file -- the same rule ArtifactPolicy/FilterPolicy/
            % AudioSettings.loadPrefs already follow for MATLAB prefs.
            %
            % Returns a one-line warning (empty if none) rather than calling
            % setStatus itself -- onLoadConfiguration's own final status
            % overwrites the label the instant this returns, so anything
            % said in here would never be seen otherwise.
            if isfield(cfg,'Subject') && ~isempty(cfg.Subject)
                app.setDropValue(app.SubjectField,char(cfg.Subject));
            end
            if isfield(cfg,'OutputPath')
                app.setDropValue(app.OutputField,char(cfg.OutputPath));
            end

            warn = app.applyConfigStimuli(cfg);

            if isfield(cfg,'Strategy') && any(strcmp(cfg.Strategy,mabr.stim.Schedule.Strategies))
                app.StrategyDrop.Value = cfg.Strategy;
            end
            % Re-resolve a saved custom criterion first, so its "Custom: <name>"
            % item is back in the dropdown before the Advance value below tries
            % to select it. Defensive throughout: a moved, deleted, or
            % no-longer-conforming file leaves the custom item simply absent,
            % and the Advance restore then falls through to a built-in.
            warn = app.applyConfigCustomAdvance(cfg,warn);
            app.syncAdvanceEnables();   % re-derives Advance/Corr for the (maybe new) strategy
            % Early stop is meaningless for an intermixed strategy (see
            % syncAdvanceEnables), so a saved 'Correlation Threshold' is only
            % restored when the strategy just set actually allows it --
            % otherwise the disabled dropdown's forced 'All Repetitions' wins.
            if strcmp(app.AdvanceDrop.Enable,'on') && isfield(cfg,'Advance') ...
                    && any(strcmp(cfg.Advance,app.AdvanceDrop.Items))
                app.AdvanceDrop.Value = cfg.Advance;
            end
            if isfield(cfg,'CorrThreshold') && isnumeric(cfg.CorrThreshold) && isscalar(cfg.CorrThreshold)
                app.CorrField.Value = cfg.CorrThreshold;
            end
            app.onAdvanceChanged();

            if isfield(cfg,'ISIRandom'), app.JitterCheck.Value = logical(cfg.ISIRandom); end
            if isfield(cfg,'ISI_ms') && isnumeric(cfg.ISI_ms) && isscalar(cfg.ISI_ms) && cfg.ISI_ms > 0
                app.ISIField.Value  = cfg.ISI_ms;
                app.RateField.Value = 1e3/cfg.ISI_ms;
            end
            if isfield(cfg,'ISIMin_ms') && isnumeric(cfg.ISIMin_ms) && isscalar(cfg.ISIMin_ms) && cfg.ISIMin_ms > 0
                app.ISIMinField.Value = cfg.ISIMin_ms;
            end
            if isfield(cfg,'ISIMax_ms') && isnumeric(cfg.ISIMax_ms) && isscalar(cfg.ISIMax_ms) && cfg.ISIMax_ms > 0
                app.ISIMaxField.Value = cfg.ISIMax_ms;
            end
            app.syncISIFields();

            if isfield(cfg,'Artifacts')
                app.Artifacts = mabr.ArtifactPolicy.fromStruct(cfg.Artifacts);
                app.ArtifactDrop.Value = app.Artifacts.Mode;
                app.syncArtifactFields();
                app.applyArtifacts();
            end
            if isfield(cfg,'Filters')
                app.Filters = mabr.FilterPolicy.fromStruct(cfg.Filters);
                app.syncFilterFields();
                app.applyFilters();
            end
            if isfield(cfg,'Audio')
                app.Audio = mabr.AudioSettings.fromStruct(cfg.Audio);
                mabr.AudioSettings.savePrefs(app.Audio);
            end

            app.checkOverlap();
            app.refreshPlan();
        end

        function warn = applyConfigStimuli(app,cfg)
            % Restore the bank a configuration was saved with, where that is
            % possible, then overlay the saved per-stimulus repetition counts
            % onto whatever bank ends up loaded. Returns a one-line warning
            % (empty if none) rather than calling setStatus -- see
            % applyConfiguration.
            warn = '';
            if ~isfield(cfg,'StimulusSource'), return; end
            src = cfg.StimulusSource;

            set = [];
            switch lower(src.Kind)
                case 'demo'
                    set = mabr.stim.demoStimuli(app.Config);
                case {'file','stimgen'}
                    if ~isempty(src.File) && isfile(src.File)
                        try
                            set = mabr.stim.StimulusSet.fromFile(src.File,app.Config);
                        catch me
                            warn = ['Configuration''s stimulus bank could not be ' ...
                                'reloaded from "' src.File '": ' me.message];
                        end
                    else
                        % Built live in the designer and never saved to a
                        % file the configuration can point back to (or the
                        % file has moved). The bank currently loaded, if any,
                        % is left alone rather than cleared.
                        warn = ['Configuration references a stimulus bank with no ' ...
                            'reloadable file -- load it manually, then re-apply repetitions.'];
                    end
                otherwise
                    % No Kind recorded (an empty bank when saved) -- nothing to restore.
            end
            if isempty(set), return; end

            app.adoptStimuli(set);   % resets Reps to the bank's own defaults

            if isfield(cfg,'Reps') && ~isempty(cfg.Reps)
                % Matched by ID, not position: a bank regenerated from the
                % same source reproduces the same IDs, and matching by name is
                % what survives the bank having gained or dropped an entry
                % since the configuration was saved.
                ids = set.IDs();
                r   = app.Reps;
                for k = 1:numel(cfg.Reps)
                    idx = find(strcmp(ids,cfg.Reps(k).ID),1);
                    if ~isempty(idx), r(idx) = cfg.Reps(k).Count; end
                end
                app.Reps = r;
                if ~isempty(app.Reps), app.RepsField.Value = app.Reps(1); end
            end
        end

        function warn = applyConfigCustomAdvance(app,cfg,warn)
            % Re-resolve the custom advance function a configuration was saved
            % with, restoring its dropdown item so cfg.Advance can select it.
            % Returns the (possibly appended) one-line warning -- see
            % applyConfiguration. A missing/moved/malformed file is not an
            % error: the item is simply not restored and the Advance value
            % falls through to a built-in.
            if ~isfield(cfg,'AdvanceCustomFile') || isempty(cfg.AdvanceCustomFile)
                return
            end
            file = char(cfg.AdvanceCustomFile);
            [pn,nm,ext] = fileparts(file);
            note = '';
            if ~isfile(file) || ~strcmpi(ext,'.m')
                note = ['Configuration''s custom advance function could not be found at "' ...
                        file '"; the built-in criterion is used instead.'];
            else
                app.addToPath(pn);
                fcn = str2func(nm);
                [ok,why] = mabr.stim.advance.validate(fcn);
                if ok
                    app.CustomAdvanceFcn  = fcn;
                    app.CustomAdvanceName = nm;
                    app.CustomAdvanceFile = file;
                    app.ensureCustomItem(nm);
                else
                    note = ['Configuration''s custom advance function "' nm ...
                            '" no longer conforms (' why '); the built-in criterion is used.'];
                end
            end
            if ~isempty(note)
                if isempty(warn), warn = note; else, warn = [warn ' ' note]; end
            end
        end

        % --- Controller lifecycle ------------------------------------------
        function ensureController(app)
            testing = app.Audio.Testing;
            if ~isempty(app.Controller) && isvalid(app.Controller) ...
                    && app.Controller.Testing == testing
                app.setStatus('Reusing the running acquisition worker.');
                return
            end
            % (Re)build for the selected mode.
            delete(app.Listeners);
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.setStatus('Shutting down the previous worker…'); drawnow;
                delete(app.Controller);
            end

            % Startup is slow (parallel pool + worker handshake), so the
            % engine reports each milestone straight into the status line.
            app.Controller = mabr.ui.AcqController(app.Config,testing, ...
                @(msg) app.setStatus(msg));
            app.Listeners = [ ...
                addlistener(app.Controller,'StateChanged',   @(~,e) app.onState(e)); ...
                addlistener(app.Controller,'MetricsUpdated', @(~,e) app.onMetrics(e)); ...
                addlistener(app.Controller,'BlockReady',     @(~,e) app.onBlockReady(e)); ...
                addlistener(app.Controller,'BlockSaved',     @(~,e) app.onBlockSaved(e)); ...
                addlistener(app.Controller,'ScheduleComplete',@(~,~) app.onScheduleComplete())];
            % An organizer left open across a controller rebuild would still be
            % listening to the deleted one, so re-point it at the new.
            if ~isempty(app.TraceOrg) && isvalid(app.TraceOrg)
                app.TraceOrg.listenTo(app.Controller);
            end
            app.Controller.waitUntilReady(120);
            app.setStatus('Worker ready.');
        end

        % --- Button callbacks ----------------------------------------------
        function onBrowse(app)
            p = uigetdir(app.OutputField.Value,'Select output folder');
            if ischar(p) && ~isequal(p,0), app.setDropValue(app.OutputField,p); end
            figure(app.UIFigure);
        end

        function onLoadSource(app)
            filt = {'*.spl;*.mat','Stimulus bank (*.spl, *.mat)'; ...
                    '*.spl','stimgen bank (*.spl)'; ...
                    '*.mat','MATLAB struct array (*.mat)'};
            [fn,pn] = uigetfile(filt,'Load stimuli');
            figure(app.UIFigure);
            if isequal(fn,0), return; end
            try
                app.adoptStimuli(mabr.stim.StimulusSet.fromFile(fullfile(pn,fn),app.Config));
                app.setStatus(sprintf('Loaded %d stimuli from %s',app.Stimuli.numStimuli,fn));
            catch me
                app.setStatus(['Load failed: ' me.message]);
            end
        end

        % --- stimgen bank designer -------------------------------------------
        % Non-modal on purpose. stimgen.StimPlayer keeps its figure handle
        % private, so there is nothing to uiwait on -- but a modal designer
        % would be the wrong shape anyway: the same button becoming "Adopt
        % bank" lets the user tune a stimulus, adopt, look at it in the
        % stimulus viewer, and adjust again without reopening anything. It
        % matches how the viewers already behave.
        function onDesignStimuli(app)
            if app.designerOpen()
                app.adoptFromDesigner();
                return
            end

            [ok,why] = mabr.stim.stimgenAvailable();
            if ~ok, app.setStatus(why); return; end

            try
                app.Designer = stimgen.StimPlayer();
                app.hideDesignerSessionControls();
                app.setStatus(['Designer open. Build a bank, then press Adopt bank ' ...
                               'to bring it into MABR.']);
            catch me
                app.Designer = [];
                app.setStatus(['Could not open the stimgen designer: ' me.message]);
            end
            app.syncDesignButton();
        end

        function hideDesignerSessionControls(app)
            % MABR owns presentation, so the designer must not appear to offer
            % it. Reps, ISI, the Shuffle/Serial dropdown and Run/Pause all
            % duplicate settings that live in the Presentation panel -- and the
            % duplicates are not merely redundant, they are inert: fromStimgen
            % drops ISI and SelectionType outright, and a session started from
            % the designer's Run button would stream through stimgen's own
            % speaker preview rather than the rig the worker holds open.
            % set_control_visibility collapses them out of the layout (the
            % properties stay settable programmatically), so the designer is
            % reduced to what it is being used for here: building a bank.
            %
            % Guarded on the method rather than assumed, since stimgen is an
            % optional submodule a rig may have checked out at an older commit
            % -- an unhidden control is a worse designer, not a broken one.
            if ~ismethod(app.Designer,'set_control_visibility')
                mabr.log.vprintf(1,['App: this stimgen has no ' ...
                    'set_control_visibility; the designer will show its own ' ...
                    'Reps/ISI/order/run controls, which MABR ignores.']);
                return
            end
            app.Designer.set_control_visibility(All=false);
        end

        function adoptFromDesigner(app)
            try
                set = mabr.stim.fromStimgen(app.Designer,app.Config);
                app.adoptStimuli(set);
                app.setStatus(sprintf('Adopted %d presentations from the designer.', ...
                    set.numStimuli));
            catch me
                app.setStatus(['Adopt failed: ' me.message]);
            end
        end

        function tf = designerOpen(app)
            tf = ~isempty(app.Designer) && isvalid(app.Designer);
        end

        function syncDesignButton(app)
            % One button, two jobs, because they are the same job at different
            % moments: open the designer, then take what it built.
            [ok,why] = mabr.stim.stimgenAvailable();
            if app.designerOpen()
                app.DesignButton.Text    = 'Adopt bank';
                app.DesignButton.Tooltip = ['Bring the designer''s current bank into MABR, ' ...
                                            'regenerated at the DAC rate.'];
            else
                app.DesignButton.Text    = 'Design…';
                if ok
                    app.DesignButton.Tooltip = ['Build a calibrated stimulus bank in stimgen ' ...
                                                '(the suggested route).'];
                else
                    app.DesignButton.Tooltip = why;
                end
            end
            app.DesignButton.Enable = onOff(ok);
        end

        function onTestSource(app)
            app.adoptStimuli(mabr.stim.demoStimuli(app.Config));
            app.setStatus('Loaded built-in test stimuli.');
        end

        function adoptStimuli(app,set)
            % Take on a new stimulus bank and reset the repetition counts to
            % whatever the bank suggests (its own Repetitions field, else the
            % schedule default).
            app.Stimuli = set;
            app.Reps    = mabr.stim.Schedule.startingRepetitions(set);
            if ~isempty(app.Reps), app.RepsField.Value = app.Reps(1); end
            % An open stimulus viewer shows the bank that is loaded, not the
            % one that was loaded when it was opened.
            if ~isempty(app.StimViewer) && isvalid(app.StimViewer)
                app.StimViewer.setStimuli(set);
            end
            app.setSourceLabel();
            app.syncDesignButton();
            app.checkOverlap();
            app.refreshPlan();
            app.warnUncalibratedLevels(set);
        end

        function warnUncalibratedLevels(app,set)
            % What an uncalibrated level series is and is not. stimgen converts
            % dB SPL to volts THROUGH the calibration; with none loaded
            % apply_calibration is a no-op, so SoundLevel never reaches the
            % amplitude. mabr.stim.fromStimgen makes the levels RELATIVE to the
            % bank's loudest entry instead (see relativeLevels), so the spacing
            % is right and a growth function still grows -- but the absolute
            % axis is arbitrary, and nobody should discover that from the data
            % months later. Hence a warning on adopt, not a refusal.
            %
            % Scoped to stimgen banks deliberately. An uncalibrated bank from
            % anywhere else may well vary amplitude with level -- demoStimuli
            % does, at 10^((L-80)/20) -- so warning on every uncalibrated bank
            % would be crying wolf at the one button whose whole job is to be
            % uncalibrated.
            if ~strcmpi(set.Source.Kind,'stimgen'), return; end
            if set.numStimuli < 2 || set.isCalibrated(), return; end
            if ~isfield(set.Stimuli,'Level'), return; end

            u = unique([set.Stimuli.Level]);
            if numel(u) < 2, return; end

            % LevelScale is fromStimgen's record that it did the rescaling. Its
            % absence here means the bank is PARTLY calibrated, which that pass
            % leaves alone for want of a common reference -- a different
            % problem, and a worse one.
            if isfield(set.Stimuli,'LevelScale')
                msg = sprintf(['This bank asks for %d different levels (%s dB) but carries ' ...
                    'no calibration, so no absolute dB SPL can be put on any of them.\n\n' ...
                    'MABR has scaled them relative to the loudest: %g dB plays at the ' ...
                    'bank''s own normalized amplitude and each lower level is attenuated ' ...
                    'by the right ratio. Level differences are therefore correct; the ' ...
                    'absolute level is not.\n\nCalibrate under Settings > Calibration…, ' ...
                    'then rebuild the bank for true SPL.'], ...
                    numel(u),strjoin(string(u),', '),max(u));
                mabr.log.vprintf(0,1,['Uncalibrated bank: %d Levels (%s dB) scaled ' ...
                    'relative to %g dB.'],numel(u),strjoin(string(u),', '),max(u));
            else
                msg = sprintf(['This bank asks for %d different levels (%s dB) and only ' ...
                    'SOME of its stimuli are calibrated, so the levels cannot be made ' ...
                    'relative to each other either — the uncalibrated ones are all at ' ...
                    'the same amplitude.\n\nCalibrate under Settings > Calibration…, ' ...
                    'then rebuild the bank.'],numel(u),strjoin(string(u),', '));
                mabr.log.vprintf(0,1,['Partly calibrated bank with %d distinct Levels ' ...
                    '(%s dB); levels left as generated.'],numel(u),strjoin(string(u),', '));
            end
            uialert(app.UIFigure,msg,'Uncalibrated bank','Icon','warning');
        end

        function onAdvanceSelected(app)
            % The dropdown's ValueChangedFcn: only fired by a genuine user
            % pick, so this is the one place the "Custom…" file picker may
            % open. Everything programmatic (syncAdvanceEnables, config load)
            % calls onAdvanceChanged directly and never trips a dialog.
            if strcmp(app.AdvanceDrop.Value,'Custom…')
                app.chooseCustomAdvance();
            end
            app.onAdvanceChanged();
        end

        function onAdvanceChanged(app)
            v         = app.AdvanceDrop.Value;
            isCorr    = strcmp(v,'Correlation Threshold');
            isCustom  = startsWith(v,'Custom: ');
            canEarly  = ~mabr.stim.Schedule.strategyIntermixes(app.StrategyDrop.Value);
            % The threshold field feeds AdvanceParams.corrThreshold, which the
            % correlation criterion reads directly and a custom one may read
            % too, so it is live for either — but never for plain "All
            % Repetitions", nor once the strategy intermixes and early stop
            % is off entirely.
            app.CorrField.Enable = onOff((isCorr || isCustom) && canEarly);
            % Remember the last real selection so a cancelled/rejected Custom…
            % pick has somewhere to fall back to.
            if ~strcmp(v,'Custom…'), app.LastAdvanceValue = v; end
        end

        function chooseCustomAdvance(app)
            % Prompt for a .m advance function, resolve it to a handle, and
            % accept it only if it conforms to the contract. On cancel or
            % rejection the dropdown falls back to the last good selection, so
            % the sentinel is never left standing as the live value.
            [fn,pn] = uigetfile({'*.m','MATLAB function (*.m)'}, ...
                'Select a custom advance function');
            figure(app.UIFigure);
            if isequal(fn,0), app.revertAdvanceSelection(); return; end

            file = fullfile(pn,fn);
            [dn,name] = fileparts(file);        % dn has no trailing separator
            app.addToPath(dn);
            fcn = str2func(name);
            [ok,why] = mabr.stim.advance.validate(fcn);
            if ~ok
                uialert(app.UIFigure, sprintf(['"%s" is not a valid advance function.\n\n%s' ...
                    '\n\nAn advance function takes one context struct and returns a single ' ...
                    'logical (true = stop the run early). Copy ' ...
                    '+mabr/+stim/+advance/custom_template.m to get the contract right.'], ...
                    name,why),'Invalid advance function');
                app.revertAdvanceSelection();
                return
            end

            app.CustomAdvanceFcn  = fcn;
            app.CustomAdvanceName = name;
            app.CustomAdvanceFile = file;
            label = app.ensureCustomItem(name);
            app.AdvanceDrop.Value = label;
            app.LastAdvanceValue  = label;
            app.setStatus(sprintf('Custom advance function: %s',name));
        end

        function label = ensureCustomItem(app,name)
            % Make sure a "Custom: <name>" item exists just before the
            % "Custom…" sentinel, replacing any previous custom item. Returns
            % the label so callers can select it. Setting Value/Items
            % programmatically does NOT fire ValueChangedFcn, so this never
            % re-enters the picker.
            label = ['Custom: ' name];
            app.AdvanceDrop.Items = ...
                {'All Repetitions','Correlation Threshold',label,'Custom…'};
        end

        function addToPath(~,folder)
            % Put a custom function's folder on the MATLAB path so str2func
            % can resolve it by name, but only when it is not already there --
            % a redundant addpath needlessly reorders the path.
            if isempty(folder), return; end
            if ~any(strcmp(folder,regexp(path,pathsep,'split')))
                addpath(folder);
            end
        end

        function revertAdvanceSelection(app)
            % Back to the last non-sentinel selection. If that was itself a
            % custom item that no longer exists (never chosen), the base list
            % has no such entry, so fall back to "All Repetitions".
            v = app.LastAdvanceValue;
            if ~any(strcmp(v,app.AdvanceDrop.Items)), v = 'All Repetitions'; end
            app.AdvanceDrop.Value = v;
        end

        function fcn = currentAdvanceFcn(app)
            % Map the dropdown's current selection to the criterion handle
            % onStart hands the controller.
            v = app.AdvanceDrop.Value;
            if strcmp(v,'Correlation Threshold')
                fcn = @mabr.stim.advance.corr_threshold;
            elseif startsWith(v,'Custom: ') && ~isempty(app.CustomAdvanceFcn)
                fcn = app.CustomAdvanceFcn;
            else
                fcn = @mabr.stim.advance.num_sweeps;
            end
        end

        function onStrategyChanged(app)
            intermixed = mabr.stim.Schedule.strategyIntermixes(app.StrategyDrop.Value);
            app.syncAdvanceEnables();
            if intermixed
                app.setStatus(['Intermixed runs play to completion — ' ...
                    'correlation early-stop is available for blocked strategies only.']);
            end
            app.refreshPlan();
        end

        function syncAdvanceEnables(app)
            % Early stop is unavailable once a run mixes stimuli: stopping it
            % would truncate whichever stimuli fell last in the sequence.
            % Called from transport() too, so it must not touch the status line.
            if mabr.stim.Schedule.strategyIntermixes(app.StrategyDrop.Value)
                app.AdvanceDrop.Value  = 'All Repetitions';
                app.AdvanceDrop.Enable = 'off';
            else
                app.AdvanceDrop.Enable = 'on';
            end
            app.onAdvanceChanged();
        end

        % --- Artifact rejection ---------------------------------------------
        % The policy object is the source of truth; these keep the three
        % controls and the saved prefs agreeing with it.
        function onArtifactModeChanged(app)
            % Hand the field's current value back to the criterion that owned
            % it BEFORE switching, so toggling voltage -> RMS -> voltage does
            % not overwrite one threshold with the other's number.
            app.Artifacts = app.Artifacts.setThreshold(app.ArtifactField.Value/1e3);
            app.Artifacts.Mode = app.ArtifactDrop.Value;
            app.syncArtifactFields();
            app.applyArtifacts();
        end

        function onArtifactThresholdChanged(app)
            app.Artifacts = app.Artifacts.setThreshold(app.ArtifactField.Value/1e3);
            app.applyArtifacts();
        end

        function onArtifactRepeatChanged(app)
            app.Artifacts.Repeat = app.ArtifactRepeatCheck.Value;
            app.applyArtifacts();
        end

        function applyArtifacts(app)
            % Remember the choice, and hand it to the controller if one exists
            % — including mid-schedule, which is the whole point of leaving
            % these three controls live while the rest of the settings lock.
            % The criterion is only DECIDED when a run is finalized, so the
            % verdict lands on the next block to complete rather than editing
            % the one in flight, and blocks already finalized keep the verdict
            % they were judged under. The live view previews the new rule
            % immediately, which is how the user sees whether the threshold
            % they just typed is the one they wanted.
            app.saveArtifactPrefs();
            msg = ['Artifact rejection: ' app.Artifacts.describe() '.'];
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.Controller.Artifacts = app.Artifacts;
                if app.isRunning()
                    msg = [msg ' Applies from the next block.'];
                end
            end
            app.setStatus(msg);
        end

        function syncArtifactFields(app)
            % Push the policy into the controls: the right threshold, captioned
            % for the criterion reading it, and both dependent controls dead
            % when nothing is being rejected. Called from transport() in both
            % directions, since these controls stay live while acquiring and
            % so have to be revived after the busy lock, not just at Idle.
            p = app.Artifacts;
            switch p.Mode
                case 'voltage'
                    app.ArtifactField.ValueDisplayFormat = '± %.4g mV';
                    app.ArtifactField.Value = 1e3*p.VoltageThreshold;
                case 'rms'
                    app.ArtifactField.ValueDisplayFormat = 'RMS > %.4g mV';
                    app.ArtifactField.Value = 1e3*p.RMSThreshold;
            end
            app.ArtifactDrop.Enable        = 'on';
            app.ArtifactField.Enable       = onOff(p.Enabled);
            app.ArtifactRepeatCheck.Enable = onOff(p.Enabled);
            app.ArtifactRepeatCheck.Value  = p.Repeat;
        end

        function saveArtifactPrefs(app)
            mabr.ArtifactPolicy.savePrefs(app.Artifacts);
        end

        % --- ASIO device / channel mapping -----------------------------------
        % Same shape as the artifact/filter settings, except this one is a
        % CONFIG control (see configControls): the worker's audioPlayerRecorder
        % is opened on whatever device Start hands it, so switching mid-run is
        % not something changing a property can safely do.
        function onAudioSettings(app)
            s = mabr.ui.AudioSettingsDialog(app.Audio,app.Config);
            figure(app.UIFigure);
            if isempty(s), return; end        % cancelled
            app.Audio = s;
            mabr.AudioSettings.savePrefs(app.Audio);
            app.setStatus(['Audio device: ' app.Audio.describe() '.']);
        end

        % --- Calibration ------------------------------------------------------
        % stimgen owns calibration; MABR owns the rig. So this opens stimgen's
        % own GUI rather than reimplementing it, over an adapter that points the
        % measurement at THIS device, output channel, and sample rate --
        % otherwise the number that comes back describes a signal chain the
        % experiment never uses. A config control: the adapter has to take the
        % ASIO device off the worker to measure at all.
        function onCalibration(app)
            [ok,why] = mabr.stim.stimgenAvailable();
            if ~ok, app.setStatus(why); return; end

            if app.Audio.Testing
                app.setStatus(['Calibration needs a real device — turn off Testing ' ...
                               '(loopback) in Settings > Audio Device first.']);
                return
            end

            try
                adapter = mabr.stim.CalibrationAdapter(app.Audio,app.Config,app.Controller);
                eng     = stimgen.calibration.Engine(adapter);
                stimgen.calibration.CalibrationGui(eng);
                app.setStatus(sprintf(['Calibration open on %s (mic in %d, out %d). ' ...
                    'Rebuild the stimulus bank afterwards so it picks the calibration up.'], ...
                    app.Audio.describe(),app.Audio.MicChannel,app.Audio.PlayerChannels(1)));
            catch me
                app.setStatus(['Calibration failed to open: ' me.message]);
            end
        end

        % --- Display filtering ----------------------------------------------
        % Same shape as the artifact controls above, and for the same reason:
        % the policy object is the source of truth and these keep the panel,
        % the controller, and the saved prefs agreeing with it.
        function onFilters(app)
            p = mabr.ui.FilterDialog(app.Filters,app.Config.ADCSampleRate);
            figure(app.UIFigure);
            if isempty(p), return; end        % cancelled
            app.Filters = p;
            app.syncFilterFields();
            app.applyFilters();
        end

        function applyFilters(app)
            % Remember the chain, and hand it to the controller if one exists —
            % including mid-schedule. The controller redesigns it at the live
            % rate on assignment, so the very next live-view tick is drawn
            % through the new corners; blocks finalized from then on report
            % through them too. Nothing already saved changes, and nothing
            % saved later changes either: .abr files hold the raw trace.
            mabr.FilterPolicy.savePrefs(app.Filters);
            msg = ['Display filters: ' app.Filters.describe() '.'];
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.Controller.Filters = app.Filters;
            end
            app.setStatus([msg ' Saved files are unaffected.']);
        end

        function syncFilterFields(app)
            % One line standing in for eight controls, so the panel says what
            % the chain is without the dialog being open. Called from
            % transport() as well: the button stays live while acquiring and
            % so has to be revived after the busy lock, not just at Idle.
            app.FilterLabel.Text = app.Filters.describe();
            if app.Filters.Enabled
                app.FilterLabel.FontColor = [0.3 0.3 0.3];
            else
                % Not an error, but worth not blending in: an unfiltered live
                % view is a legitimate choice and an easy one to forget making.
                app.FilterLabel.FontColor = [0.8 0.2 0];
            end
            app.FilterButton.Enable = 'on';
        end

        function setArtifactReadout(app)
            % Blocks already finalized plus the run in flight, which the
            % controller's live preview reports and BlockReady then replaces
            % with the verdict made on the filtered sweeps.
            n = app.ArtifactCount + app.LiveArtifacts;
            if n > 0
                app.ArtifactLabel.Text = sprintf('rejected: %d',n);
            else
                app.ArtifactLabel.Text = '';
            end
        end

        function onRepsChanged(app)
            % The plain field is the "same for all" shortcut; it overwrites any
            % per-stimulus values set through the dialog.
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0, return; end
            app.Reps = repmat(app.RepsField.Value,1,app.Stimuli.numStimuli);
            app.refreshPlan();
        end

        function onRepsDialog(app)
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0
                app.setStatus('Load stimuli first.'); return
            end
            % The dialog only estimates a duration from it, so it gets the mean
            % interval -- which under Random is all there is to give it, and the
            % caption says as much rather than quoting a fixed ISI that no
            % single presentation will be spaced by.
            [~,avgISI] = app.isiSeconds();
            lbl = '';
            if app.JitterCheck.Value, lbl = sprintf('%.2f ms mean ISI',1e3*avgISI); end
            r = mabr.ui.RepetitionsDialog(app.Stimuli,app.Reps,avgISI,lbl);
            figure(app.UIFigure);
            if isempty(r), return; end        % cancelled
            app.Reps = r;
            % Keep the shortcut field honest: show the common value, or blank
            % out to the first entry when they differ.
            app.RepsField.Value = r(1);
            app.refreshPlan();
        end

        % --- ISI <-> rate ---------------------------------------------------
        % The two fields are two views of one number: editing either recomputes
        % the other. ISI is onset-to-onset in ms, rate is 1/ISI in Hz.
        function onISIChanged(app)
            app.RateField.Value = 1e3/app.ISIField.Value;
            app.checkOverlap();
            app.refreshPlan();
        end

        function onRateChanged(app)
            app.ISIField.Value = 1e3/app.RateField.Value;
            app.checkOverlap();
            app.refreshPlan();
        end

        % --- Randomized ISI -------------------------------------------------
        function onJitterChanged(app)
            app.syncISIFields();
            app.checkOverlap();
            app.refreshPlan();
        end

        function onISIRangeChanged(app,which)
            % The bounds are a range, so the pair has to stay ordered: pushing
            % one past the other carries the other along rather than refusing
            % the edit, which is what the ISI/Rate pair above does with its own
            % dependency. Silently crossing them is the one thing not on offer.
            if app.ISIMinField.Value > app.ISIMaxField.Value
                switch which
                    case 'min', app.ISIMaxField.Value = app.ISIMinField.Value;
                    case 'max', app.ISIMinField.Value = app.ISIMaxField.Value;
                end
                app.setStatus(sprintf('ISI range collapsed to %.2f ms — the bounds crossed.', ...
                    app.ISIMinField.Value));
            end
            app.checkOverlap();
            app.refreshPlan();
        end

        function syncISIFields(app)
            % Only one of the two settings decides anything at a time, so the
            % other is greyed rather than left looking live: with Random on the
            % fixed ISI/rate is not what will be played, and with it off the
            % range is not either.
            rnd = app.JitterCheck.Value;
            app.ISIField.Enable    = onOff(~rnd);
            app.RateField.Enable   = onOff(~rnd);
            app.ISIMinField.Enable = onOff(rnd);
            app.ISIMaxField.Enable = onOff(rnd);
        end

        function m = isiMode(app)
            % The checkbox, in mabr.stim.Schedule's vocabulary.
            if app.JitterCheck.Value, m = 'random'; else, m = 'fixed'; end
        end

        function [mn,av] = isiSeconds(app)
            % What the plan will actually use, in seconds: mn is the shortest
            % interval that can occur (the overlap worst case) and av the one a
            % duration estimate should be built on. They differ only under
            % Random, where no single number describes the spacing.
            if app.JitterCheck.Value
                mn = app.ISIMinField.Value/1e3;
                av = 0.5*(app.ISIMinField.Value + app.ISIMaxField.Value)/1e3;
            else
                mn = app.ISIField.Value/1e3;
                av = mn;
            end
        end

        function checkOverlap(app)
            % Warn when the longest stimulus does not fit inside the ISI, so
            % the next presentation would start before this one has finished.
            % Judged against the SHORTEST interval that can occur: under Random
            % one unlucky draw is enough to overlap, so the bottom of the range
            % is the number that has to clear the stimulus.
            app.OverlapLabel.Text = '';
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0, return; end
            stimMs = 1e3*app.Stimuli.maxDuration();
            minMs  = 1e3*app.isiSeconds();
            if stimMs > minMs
                app.OverlapLabel.Text = sprintf('overlap! %.1f ms stim',stimMs);
                if app.JitterCheck.Value
                    app.setStatus(sprintf(['Longest stimulus is %.2f ms but the shortest ' ...
                        'interval in the range is only %.2f ms — presentations will ' ...
                        'overlap and be summed. Raise the range minimum to %.2f ms or above.'], ...
                        stimMs,minMs,stimMs));
                else
                    app.setStatus(sprintf(['Longest stimulus is %.2f ms but the ISI is only ' ...
                        '%.2f ms (%.2f Hz) — presentations will overlap and be summed. ' ...
                        'Lower the rate to %.2f Hz or below.'], ...
                        stimMs,app.ISIField.Value,app.RateField.Value,1e3/stimMs));
                end
            end
        end

        function refreshPlan(app)
            % Show what the current strategy/repetitions/ISI actually buy: how
            % many runs, how many presentations, and roughly how long.
            app.PlanLabel.Text = '';
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0, return; end
            try
                sch = app.buildSchedule();
                s   = sch.summary();
            catch me
                app.PlanLabel.Text = ['plan error: ' me.message];
                return
            end
            if s.intermixed, kind = 'intermixed'; else, kind = 'blocked'; end
            app.PlanLabel.Text = sprintf( ...
                '%d runs (%s)  ·  %d presentations  ·  ~%s', ...
                s.numRuns,kind,s.presentations,durationText(s.duration));
        end

        function sch = buildSchedule(app)
            % One place that turns the GUI's settings into a schedule, shared
            % by the plan preview and onStart so they cannot drift apart.
            sch             = mabr.stim.Schedule(app.Stimuli,app.Config);
            sch.Strategy    = app.StrategyDrop.Value;
            sch.Repetitions = app.Reps;
            % Both settings travel every time and the mode picks between them,
            % so the one not in force is still whatever the user last set it to.
            sch.ISI         = app.ISIField.Value/1e3;      % ms -> s
            sch.ISIRange    = [app.ISIMinField.Value app.ISIMaxField.Value]/1e3;
            sch.ISIMode     = app.isiMode();
            sch.Device           = app.Audio.Device;
            sch.PlayerChannels   = app.Audio.PlayerChannels;
            sch.RecorderChannels = app.Audio.RecorderChannels;
            sch.build();
        end

        function onStart(app,preview)
            % preview (default false): run everything exactly as Start does but
            % leave the Session's OutputPath empty, which is already the "record
            % without saving" path through AcqController.finalize_run — blocks
            % are still built, still reach the viewers through BlockReady, and
            % still count artifacts; only writeABR is skipped.
            if nargin < 2, preview = false; end

            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0
                app.setStatus('Load stimuli first.'); return
            end
            if sum(app.Reps) < 1
                app.setStatus('Nothing to run — every stimulus has 0 repetitions.'); return
            end

            % Lock the entire UI up front: bringing the engine up blocks this
            % callback for tens of seconds (parallel pool + worker handshake),
            % and nothing here is safe to re-enter meanwhile. The engine
            % reports each startup milestone into the status line as it goes.
            app.Previewing = preview;
            app.setRunTitle(preview);
            if preview
                app.setBusy('Starting preview…');
            else
                app.setBusy('Starting…');
            end

            try
                app.ensureController();

                app.setStatus('Configuring session…');
                app.rememberValue(app.SubjectField,'Subject');
                app.checkOverlap();

                c = app.Controller;
                c.Session.Subject.ID = app.SubjectField.Value;
                if preview
                    % Nothing written, so the folder is not part of this run and
                    % does not join the remembered history either.
                    c.Session.OutputPath = '';
                else
                    app.rememberValue(app.OutputField,'Output');
                    c.Session.OutputPath = app.OutputField.Value;
                end
                c.setStimuli(app.Stimuli);

                % The controller builds its own schedule in setStimuli; replace
                % it with the one the GUI has been previewing.
                c.Schedule.Strategy    = app.StrategyDrop.Value;
                c.Schedule.Repetitions = app.Reps;
                c.Schedule.ISI         = app.ISIField.Value/1e3;   % ms -> s
                c.Schedule.ISIRange    = [app.ISIMinField.Value app.ISIMaxField.Value]/1e3;
                c.Schedule.ISIMode     = app.isiMode();
                c.Schedule.Device           = app.Audio.Device;
                c.Schedule.PlayerChannels   = app.Audio.PlayerChannels;
                c.Schedule.RecorderChannels = app.Audio.RecorderChannels;
                c.Schedule.build();
                c.Session.Device = app.Audio.Device;

                c.AdvanceFcn = app.currentAdvanceFcn();
                p = c.AdvanceParams;
                p.corrThreshold = app.CorrField.Value;
                c.AdvanceParams = p;

                c.Artifacts = app.Artifacts;
                c.Filters   = app.Filters;
                app.ArtifactCount = 0;        % readout counts this schedule only
                app.LiveArtifacts = 0;
                app.setArtifactReadout();

                app.openViewers();
                c.setLivePlot(app.LivePlot);

                s = c.Schedule.summary();
                kind = 'schedule'; if preview, kind = 'preview (nothing will be saved)'; end
                app.setStatus(sprintf('Starting %s (%d runs, %d presentations, ~%s)…', ...
                    kind,s.numRuns,s.presentations,durationText(s.duration)));
                c.start();
            catch me
                app.transport(false);      % unlock so the user can fix and retry
                app.setRunTitle(false);    % nothing is in flight to warn about
                app.setStatus(['Start failed: ' me.message]);
                mabr.log.vprintf(0,1,'Start failed: %s',me.message);
                return
            end

            app.transport(true);
        end

        function onPause(app)
            if strcmp(app.PauseButton.Text,'Pause')
                app.Controller.pauseAcq(); app.PauseButton.Text = 'Resume';
            else
                app.Controller.resumeAcq(); app.PauseButton.Text = 'Pause';
            end
        end

        function onStopBlock(app), app.Controller.stopBlock(); end
        function onAbort(app),     app.Controller.abort(); end

        function onRepeat(app)
            try
                app.Controller.repeatLastBlock();
                app.setStatus(sprintf('Repeating %s.',app.Controller.Stimuli.id(app.Controller.LastRunStimulus)));
            catch me
                app.setStatus(['Repeat failed: ' me.message]);
            end
        end

        function syncRepeatEnable(app)
            % Re-derived rather than folded into transport()'s blanket
            % running/idle split: canRepeat() flips true partway through a
            % schedule, as soon as the first blocked-strategy run completes
            % (see onBlockReady), not just at the running/idle boundary.
            can = ~isempty(app.Controller) && isvalid(app.Controller) && app.Controller.canRepeat();
            app.RepeatButton.Enable = onOff(can);
        end

        % --- Viewer windows -------------------------------------------------
        % Both viewers open at Start/Preview rather than with the app: there is
        % nothing to watch until a schedule is in flight, and launching into
        % three windows costs the user two closes before they can even pick a
        % subject. The toolbar buttons still open either on demand at any time.
        % Each remembers where it was last left (mabr.ui.WindowPos).
        function openViewers(app)
            % Called from onStart. Only a viewer whose *window* is absent is
            % opened -- one already up is left exactly as the user arranged it,
            % and deliberately not raised over whatever is in front of it.
            newLive  = isempty(app.LivePlot) || ~isvalid(app.LivePlot);
            newTrace = isempty(app.TraceOrg) || ~isvalid(app.TraceOrg) ...
                || ~app.TraceOrg.isvalidView();
            if newTrace, app.onTraceOrg(); end
            if newLive,  app.onShowLive(); end
            if newTrace || newLive
                figure(app.UIFigure);   % the main window keeps focus
            end
        end

        function onShowLive(app)
            if isempty(app.LivePlot) || ~isvalid(app.LivePlot)
                app.LivePlot = mabr.ui.LivePlot();
                f = app.LivePlot.Figure;
                % A minimum size, because the live view is now two rows of
                % axes plus a control strip: a position remembered from the
                % single-axes days would reopen it too short to read.
                mabr.ui.WindowPos.restore(f,'LivePlot', ...
                    app.defaultViewerPos('LivePlot'),[560 420]);
                % Closing disposes the viewer outright: it holds no state worth
                % keeping, and that keeps the isvalid() check above honest.
                f.CloseRequestFcn = @(~,~) app.closeLive();
            end
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.Controller.setLivePlot(app.LivePlot);
            end
            figure(app.LivePlot.Figure);
        end

        function closeLive(app)
            mabr.ui.WindowPos.remember(app.LivePlot.Figure,'LivePlot');
            delete(app.LivePlot);
        end

        function onTraceOrg(app)
            % Only a freshly built organizer is backfilled from the session.
            % Once it exists it keeps itself current through BlockReady, so
            % pressing T is a pure raise -- re-running the backfill would
            % discard whatever the user has arranged or loaded in there.
            if isempty(app.TraceOrg) || ~isvalid(app.TraceOrg)
                app.TraceOrg = mabr.ui.TraceOrganizer();
                if ~isempty(app.Controller) && isvalid(app.Controller)
                    for i = 1:app.Controller.Session.NumBlocks
                        app.TraceOrg.addBlock(app.Controller.Session.Blocks(i));
                    end
                    app.TraceOrg.listenTo(app.Controller);
                end
            end
            isNewWindow = ~app.TraceOrg.isvalidView();
            app.TraceOrg.show();
            if isNewWindow
                % Unlike the live plot, closing this window keeps the object
                % and its traces -- show() rebuilds the figure around them.
                f = app.TraceOrg.Figure;
                mabr.ui.WindowPos.restore(f,'TraceOrganizer', ...
                    app.defaultViewerPos('TraceOrganizer'));
                f.CloseRequestFcn = @(~,~) app.closeTraceOrg();
            end
        end

        function closeTraceOrg(app)
            mabr.ui.WindowPos.remember(app.TraceOrg.Figure,'TraceOrganizer');
            delete(app.TraceOrg.Figure);
        end

        function onStimViewer(app)
            % Unlike the acquisition viewers this one is built on first press,
            % and it always shows the bank currently loaded -- reopening it
            % after loading a different bank must not show the old waveforms.
            % Asked before building, because the constructor opens the window
            % itself -- checking afterwards would always say "not new".
            isNewWindow = isempty(app.StimViewer) || ~isvalid(app.StimViewer) ...
                || ~app.StimViewer.isvalidView();
            if isempty(app.StimViewer) || ~isvalid(app.StimViewer)
                app.StimViewer = mabr.ui.StimulusViewer(app.Stimuli);
            end
            app.StimViewer.show();
            % Only on a genuine change: setStimuli resets the selection, and a
            % plain raise must not throw away the entry the user was looking at.
            if ~isequal(app.StimViewer.Stimuli,app.Stimuli)
                app.StimViewer.setStimuli(app.Stimuli);
            end
            if isNewWindow
                f = app.StimViewer.Figure;
                mabr.ui.WindowPos.restore(f,'StimulusViewer', ...
                    app.defaultViewerPos('StimulusViewer'));
                f.CloseRequestFcn = @(~,~) app.closeStimViewer();
            end
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0
                app.setStatus('No stimulus bank loaded yet — the viewer will fill in once you load one.');
            end
        end

        function closeStimViewer(app)
            mabr.ui.WindowPos.remember(app.StimViewer.Figure,'StimulusViewer');
            delete(app.StimViewer);
        end

        function rememberViewerPositions(app)
            try, mabr.ui.WindowPos.remember(app.LivePlot.Figure,'LivePlot'); end %#ok<TRYNC>
            try, mabr.ui.WindowPos.remember(app.TraceOrg.Figure,'TraceOrganizer'); end %#ok<TRYNC>
            try, mabr.ui.WindowPos.remember(app.StimViewer.Figure,'StimulusViewer'); end %#ok<TRYNC>
        end

        function pos = defaultViewerPos(app,name)
            % First-run layout only -- afterwards the remembered position wins.
            % Both viewers sit to the right of the main window, the organizer
            % beside it and the live plot beyond that, so the three are visible
            % together without overlapping.
            a   = app.UIFigure.Position;
            gap = 12;
            switch name
                case 'TraceOrganizer'
                    pos = [a(1)+a(3)+gap, a(2), 640, a(4)];
                case 'StimulusViewer'
                    % On demand and transient, so it cascades off the main
                    % window rather than claiming a slot in the run layout.
                    pos = [a(1)+40, a(2)-40, 820, 500];
                otherwise   % live plot, top-aligned with the main window
                    % Tall enough for the latest sweep AND the per-stimulus
                    % means stacked beneath it; the old 280 px only ever held
                    % one axes.
                    pos = [a(1)+a(3)+gap+640+gap, a(2)+a(4)-560, 720, 560];
            end
        end

        function onClose(app)
            delete(app);
        end

        % --- Controller event handlers -------------------------------------
        function onState(app,e)
            [c,txt] = stateAppearance(e.State);
            app.StateLamp.Color = c;
            app.StateLabel.Text = txt;
            % A preview is indistinguishable from a real run everywhere else,
            % so the panel title carries the warning for as long as one is in
            % flight, and drops it once the schedule settles.
            app.setRunTitle(app.Previewing && ~isTerminal(e.State));
            switch e.State
                case {mabr.ui.ProgState.SchedComplete, mabr.ui.ProgState.Idle, mabr.ui.ProgState.Error}
                    app.transport(false);
            end
            drawnow limitrate
        end

        function onMetrics(app,e)
            app.SweepLabel.Text = sprintf('Sweeps: %d',e.Info.numSweeps);
            app.CorrLabel.Text  = sprintf('r = %.3f',e.Info.corr);
            % The controller previews the artifact verdict every tick, so the
            % readout can move during a run instead of only when a block lands.
            app.LiveArtifacts = e.Info.numArtifacts;
            app.setArtifactReadout();
        end

        function onBlockReady(app,e)
            % Fires once per stimulus recovered from the run, whether or not it
            % was saved, so the rejection tally covers unsaved sessions too.
            % The finalized count supersedes the live preview for this run:
            % zero it here, before folding the real number into the total, so
            % the run is never counted twice.
            app.LiveArtifacts = 0;
            app.ArtifactCount = app.ArtifactCount + e.Info.block.ADC.NumArtifacts;
            app.setArtifactReadout();
            app.syncRepeatEnable();
        end

        function onBlockSaved(app,e)
            [~,fn,ext] = fileparts(e.Info.file);
            app.setStatus(['Saved ' fn ext]);
        end

        function onScheduleComplete(app)
            if app.Previewing
                app.setStatus('Preview complete — no files were written.');
            else
                app.setStatus('Schedule complete.');
            end
            app.transport(false);
        end

        % --- UI helpers ----------------------------------------------------
        % Enable state has three modes, all driven from here so no callback
        % has to reason about individual components:
        %   busy    - startup/teardown in progress; everything is dead
        %   running - acquiring; the transport controls, the viewers, the
        %             artifact criterion (judged at finalization, so safe to
        %             retune between blocks), and the display filters (which
        %             never reach the recorded data at all)
        %   idle    - configurable; everything but the transport controls
        function tf = isRunning(app)
            % A schedule is under way: the controller exists and has not
            % settled back into a resting state.
            tf = ~isempty(app.Controller) && isvalid(app.Controller) && ...
                 ~any(app.Controller.State == [mabr.ui.ProgState.Idle, ...
                      mabr.ui.ProgState.SchedComplete, mabr.ui.ProgState.Error]);
        end

        function h = configControls(app)
            % Settings that must not change once a run is under way.
            % Calibration joins them: it opens the ASIO device the running
            % worker is holding (see mabr.stim.CalibrationAdapter), so it is
            % not merely unwise mid-schedule but impossible. Load Configuration
            % joins them for the same reason as Load bank/Audio Device -- it
            % can replace the stimulus bank, ISI, and audio mapping out from
            % under a running schedule. Recent Configurations is the same
            % action by another route and joins for the same reason. Save
            % Configuration does not: it only reads the current settings, so
            % it stays live throughout.
            h = {app.SubjectField, app.OutputField, app.BrowseButton, ...
                 app.DesignButton, app.LoadButton, app.TestButton, ...
                 app.StrategyDrop, app.RepsField, app.RepsButton, ...
                 app.AdvanceDrop, app.CorrField, ...
                 app.ISIField, app.RateField, app.JitterCheck, ...
                 app.ISIMinField, app.ISIMaxField, app.AudioMenuItem, ...
                 app.CalMenuItem, app.TestMenuItem, app.LoadConfigMenuItem, ...
                 app.RecentConfigsMenu};
        end

        function h = liveControls(app)
            % Deliberately NOT config controls. Artifact rejection is judged at
            % finalization and display filtering only decides what a plot is
            % drawn from, so both stay adjustable mid-schedule (see
            % onArtifactModeChanged, onFilters). They lock only during the busy
            % window, where nothing may be touched at all.
            h = {app.ArtifactDrop, app.ArtifactField, app.ArtifactRepeatCheck, ...
                 app.FilterButton, app.RepeatButton};
        end

        function h = allControls(app)
            h = [app.configControls, app.liveControls, ...
                 {app.StartButton, app.PreviewButton, app.PauseButton, ...
                  app.StopButton, app.AbortButton}];
        end

        function setBusy(app,msg)
            % Lock the whole UI for a blocking operation (pool/worker startup).
            setEnable(app.allControls,false);
            app.UIFigure.Pointer = 'watch';
            app.setStatus(msg);
        end

        function transport(app,running)
            % Leave busy mode and settle into running/idle enable state.
            app.UIFigure.Pointer = 'arrow';
            setEnable(app.configControls,~running);
            app.StartButton.Enable   = onOff(~running);
            app.PreviewButton.Enable = onOff(~running);
            app.PauseButton.Enable  = onOff(running);
            app.StopButton.Enable   = onOff(running);
            app.AbortButton.Enable  = onOff(running);
            % Artifact rejection and display filtering are adjustable in both
            % states, so their enables are re-derived unconditionally -- setBusy
            % killed them on the way in and only this puts them back.
            app.syncArtifactFields();
            app.syncFilterFields();
            app.syncRepeatEnable();
            % Re-derived for the same reason: configControls just switched it
            % on wholesale, but it must stay off without the stimgen submodule.
            app.syncDesignButton();
            % The toolbar is deliberately never disabled -- raising a viewer is
            % safe at any time, including while the engine is starting up.
            if ~running
                app.PauseButton.Text = 'Pause';
                app.syncAdvanceEnables();     % re-derives the Advance/Corr enables
                % Same reason: configControls just switched all five ISI
                % controls back on, but only one pair of them is ever live.
                app.syncISIFields();
            end
            drawnow limitrate
        end

        function setRunTitle(app,preview)
            if preview
                app.RunPanel.Title = 'Run — PREVIEW (nothing is saved)';
            else
                app.RunPanel.Title = 'Run';
            end
        end

        function setSourceLabel(app)
            % Count plus where it came from. Two banks of the same size are
            % otherwise indistinguishable here, and the difference that matters
            % -- calibrated or not -- is exactly the one that does not show up
            % in a waveform. Amber rather than green when it is not calibrated,
            % since that is a runnable state but not a publishable one.
            n = app.Stimuli.numStimuli;
            src = app.Stimuli.describeSource();
            if isempty(src)
                app.SourceLabel.Text = sprintf('%d stimuli',n);
            else
                app.SourceLabel.Text = sprintf('%d stimuli · %s',n,src);
            end
            [cal,known] = app.Stimuli.isCalibrated();
            if n > 0 && known && ~cal
                app.SourceLabel.FontColor = [0.75 0.45 0];
            else
                app.SourceLabel.FontColor = [0 0.5 0];
            end
        end

        function setStatus(app,txt)
            if ~isvalid(app.UIFigure), return; end
            app.StatusLabel.Text = txt;
            drawnow   % status arrives mid-blocking-call; force the repaint
        end
    end

    methods (Static, Access = private)
        function rows = glyph(name)
            % 16x16 toolbar art, one 16-char string per row; see mabr.ui.Icon.
            % Kept as art rather than index math because the shapes have to
            % be legible at 16 px and that is only checkable by looking.
            switch name
                case 'live'      % one evoked trace on a pair of axes
                    rows = {'................'
                            '.X..............'
                            '.X..............'
                            '.X.....XX.......'
                            '.X....XXX.......'
                            '.X...XX.........'
                            '.X...XX..X......'
                            '.X...X...X......'
                            '.X..XX....X..XX.'
                            '.X.XX.....X.XX..'
                            '.X........XXX...'
                            '.X.........X....'
                            '.X..............'
                            '.XXXXXXXXXXXXXX.'
                            '................'
                            '................'};
                case 'traces'    % three stacked traces: the organizer's view
                    rows = {'................'
                            '......XX........'
                            '.....X..X.......'
                            'XXXXX....XXXXXXX'
                            '................'
                            '................'
                            '......XX........'
                            '.....X..X.......'
                            'XXXXX....XXXXXXX'
                            '................'
                            '................'
                            '......XX........'
                            '.....X..X.......'
                            'XXXXX....XXXXXXX'
                            '................'
                            '................'};
                case 'stim'      % loudspeaker radiating: what gets played
                    rows = {'................'
                            '................'
                            '................'
                            '.......X...X....'
                            '......XX....X...'
                            '.....XXX.X...X..'
                            '..XXXXXX..X..X..'
                            '..XXXXXX..X..X..'
                            '..XXXXXX..X..X..'
                            '..XXXXXX..X..X..'
                            '.....XXX.X...X..'
                            '......XX....X...'
                            '.......X...X....'
                            '................'
                            '................'
                            '................'};
                case 'help'      % question mark
                    rows = {'................'
                            '.....XXXXXX.....'
                            '....XX....XX....'
                            '...XX......XX...'
                            '...XX......XX...'
                            '...........XX...'
                            '..........XX....'
                            '.......XXXX.....'
                            '.......XX.......'
                            '.......XX.......'
                            '................'
                            '.......XX.......'
                            '.......XX.......'
                            '................'
                            '................'
                            '................'};
                otherwise
                    rows = repmat({repmat('.',1,16)},16,1);
            end
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function setEnable(controls,tf)
% Set Enable on a cell array of components. They are different classes, so
% they cannot be concatenated into one handle array for a vectorized set().
state = onOff(tf);
for i = 1:numel(controls)
    c = controls{i};
    if ~isempty(c) && isvalid(c), c.Enable = state; end
end
end

function s = durationText(secs)
% Compact human-readable duration for the plan summary / status line.
if secs < 90
    s = sprintf('%.0f s',secs);
elseif secs < 3600
    s = sprintf('%d min %02d s',floor(secs/60),round(mod(secs,60)));
else
    s = sprintf('%d h %02d min',floor(secs/3600),round(mod(secs,3600)/60));
end
end

function tf = isTerminal(state)
% States a schedule rests in rather than passes through.
tf = any(state == [mabr.ui.ProgState.Idle, ...
                   mabr.ui.ProgState.SchedComplete, ...
                   mabr.ui.ProgState.Error]);
end

function [c,txt] = stateAppearance(state)
switch state
    case mabr.ui.ProgState.Idle,          c = [0.6 0.6 0.6]; txt = 'Idle';
    case mabr.ui.ProgState.PrepBlock,     c = [0.95 0.8 0.2]; txt = 'Preparing block…';
    case mabr.ui.ProgState.Acquire,       c = [0.2 0.8 0.2]; txt = 'Acquiring';
    case mabr.ui.ProgState.BlockComplete, c = [0.2 0.5 0.9]; txt = 'Block complete';
    case mabr.ui.ProgState.AdvanceBlock,  c = [0.95 0.8 0.2]; txt = 'Advancing…';
    case mabr.ui.ProgState.SchedComplete, c = [0.2 0.5 0.9]; txt = 'Schedule complete';
    case mabr.ui.ProgState.Error,         c = [0.9 0.2 0.2]; txt = 'Error';
    otherwise,                            c = [0.6 0.6 0.6]; txt = char(state);
end
end

function uialert_or_warn(msg)
warning('mabr:ui:App:toolboxes','%s',msg);
end
