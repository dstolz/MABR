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
%   The toolbar's notepad button opens the session's rig notebook
%   (mabr.data.SessionNotes, shown by mabr.ui.Notes): free-text notes taken
%   while a schedule runs, stamped with the run and sweep they were taken at,
%   and saved into every file the session writes. The store is owned here
%   rather than by the controller because the first notes worth taking happen
%   before Start; bindNotes hands it to the Session as soon as a controller
%   exists.
%
%   The toolbar's chart button opens an ONLINE ANALYSIS window
%   (mabr.ui.MetricPlot): one metric -- RMS, peak-to-peak, sweep correlation,
%   SNR, latency, or a function the user wrote -- computed per stimulus
%   condition and plotted against the stimulus parameters while the schedule
%   runs. Every press opens another one, and so does the live plot's own
%   "Analysis…" button, because one metric per window is the design: two
%   questions are two windows, not a mode switch that loses the first answer.
%   The App holds them only to re-point them at a rebuilt controller and to
%   close them with itself (see onMetricPlot).
%
%   PREFERENCES ARE RECALLED BETWEEN SESSIONS. Three settings objects come
%   back from MATLAB prefs on their own (mabr.ArtifactPolicy,
%   mabr.FilterPolicy, mabr.AudioSettings), each viewer window remembers where
%   it was left (mabr.ui.WindowPos) and how it was set to draw
%   (mabr.ui.LivePlot / mabr.ui.MetricPlot), WHICH windows open at Start is
%   mabr.ViewPolicy, and everything else the window owns -- subject, output
%   folder, bank, per-stimulus repetitions, strategy, advance criterion,
%   timing -- is captured at Start and at close and applied at the next launch
%   (saveLastSession/restoreLastSession, off through Settings > Restore
%   settings from last session).
%
%   The same snapshot is what File > Save/Load Configuration writes to a
%   .mabrcfg file, with File > Recent Configurations for the last nine. The
%   difference is only which door it comes through: a configuration file is a
%   named place a user returns to deliberately (one per protocol on a shared
%   rig), the pref is the one they land in by doing nothing at all.
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

        % Display names for the BUILT-IN mabr.stim.Schedule.Strategies, in the
        % same order (the dropdown carries the canonical names as ItemsData).
        % 'custom' is deliberately not here: it has no fixed label, being
        % named after whichever function the user resolved -- see
        % ensureCustomStrategyItem.
        StrategyItems = { ...
            'Blocked — one stimulus per run', ...
            'Blocked, shuffled run order', ...
            'Interleaved — A B C A B C …', ...
            'Interleaved, shuffled each cycle', ...
            'Fully shuffled'};

        % ItemsData for the dropdown's "Custom function…" item. A sentinel
        % rather than 'custom', so picking it is distinguishable from having
        % already resolved one: the sentinel opens the file picker, 'custom'
        % is the resolved selection.
        StrategyPickSentinel = '__mabr_choose_strategy__';

        % Stamped on the UIFigure so a second launch can find the first
        % instance's window rather than opening a duplicate onto the same
        % rig/audio device -- see the constructor's single-instance guard.
        InstanceTag = 'MABR_App_Instance';
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
        % Which viewer windows open by themselves at Start. Owned and
        % persisted on the same terms as the three policies above
        % (mabr.ViewPolicy.loadPrefs), and in NEITHER control list: it decides
        % nothing until the next Start, so it is safe to change mid-schedule.
        % What it cannot override is a rule about the run -- the trace
        % organizer still needs the transfer preference, and a
        % stimulation-only schedule still opens the progress monitor alone
        % (see openViewers and mabr.ViewPolicy).
        Views       (1,1) mabr.ViewPolicy = mabr.ViewPolicy
        % The rig notebook for this session: what the operator writes down
        % while it is happening, stamped with the run and sweep it happened at,
        % and saved into every file the session produces. Owned HERE rather
        % than by the controller because notes start before a schedule does --
        % impedances, animal state, what was changed since the last run -- and
        % the controller does not exist until the first Start. onStart hands
        % the store to the Session, which is what puts it in the files. A
        % handle, so every view of it stays in step; see mabr.data.SessionNotes
        % and mabr.ui.Notes. Constructed in the constructor, never as a
        % property default, which would share ONE store across every App.
        Notes       mabr.data.SessionNotes
        NotesView   mabr.ui.Notes
        LivePlot    mabr.ui.LivePlot
        % Online-analysis windows (mabr.ui.MetricPlot), an ARRAY because the
        % window is deliberately not a singleton: one metric per window is the
        % whole design, so RMS-against-level and correlation-against-frequency
        % are two windows open at once rather than one behind a mode switch.
        % Held only so they can be re-pointed at a rebuilt controller and torn
        % down with the app; each otherwise looks after itself.
        MetricPlots mabr.ui.MetricPlot
        TraceOrg    mabr.ui.TraceOrganizer
        StimViewer  mabr.ui.StimulusViewer
        ProgressMon mabr.ui.ProgressMonitor
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
        ComputeMenuItem
        PoolMenuItem
        TraceXferMenuItem
        StartupMenu
        % The checkable items under it, one per mabr.ViewPolicy window, in
        % mabr.ViewPolicy.names() order so the menu and the policy cannot
        % drift apart.
        StartupItems = gobjects(1,0)
        RestoreMenuItem
        HelpMenu
        TestMenuItem
        Toolbar
        LiveTool
        MetricTool
        AlwaysOnTopTool
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
        % A user-selected custom presentation strategy, resolved and persisted
        % exactly as the advance criterion above is (picked .m file, folder
        % onto the path, checked against mabr.stim.strategy.validate, saved by
        % path rather than as a handle). LastStrategyValue is the last good,
        % non-sentinel selection to fall back to when a pick is cancelled.
        CustomStrategyFcn  = []
        CustomStrategyName (1,:) char = ''
        CustomStrategyFile (1,:) char = ''
        LastStrategyValue  (1,:) char = 'blocked'
        % Whether the last plan that actually BUILT intermixes its runs. Only
        % consulted for 'custom', where the strategy's name cannot answer it
        % -- see currentStrategyIntermixes. True until a plan says otherwise,
        % since the conservative answer is the safe one for early stop.
        PlanIntermixed (1,1) logical = true
        % The Acquisition panel itself, so its title can say when nothing in
        % it applies -- a greyed control says "not now", a greyed panel with a
        % reason in its title says why (see syncAcquisitionEnables).
        AcqPanel
        % The theme's own panel-title colour, captured at build time so
        % syncAcquisitionEnables can grey the header and put it back without
        % hard-coding either value (it is not the same in every MATLAB theme).
        AcqPanelFG (1,3) double = [0 0 0]
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
        % True while the schedule now running is stimulation-only (playback
        % and timing pulse, nothing recorded). Captured at Start for the same
        % reason as Previewing: mabr.AudioSettings is the setting, but the
        % setting can be changed once the schedule settles, and what the Run
        % panel is describing is the run.
        StimOnlyRun (1,1) logical = false
        % True while the schedule now running is in TEST MODE -- the stimulus
        % buffer copied straight into the acquisition buffer, no device in the
        % path. Captured at Start for the same reason as StimOnlyRun: the
        % setting can be changed once the schedule settles, and what the Run
        % panel is describing is the run. It outranks both other banners
        % because it is the strongest statement of the three -- a preview
        % acquires real signal and merely declines to write it, and
        % stimulation only records nothing at all, while this one writes
        % ordinary-looking .abr files whose contents are the stimulus.
        TestRun (1,1) logical = false
        % .stimlog files written by the schedule now running, so the completion
        % message can say what a stimulation-only session actually left behind.
        % Zeroed at Start alongside the artifact tallies.
        StimLogsWritten (1,1) double = 0
    end

    methods
        function app = App()
            % Only one MABR window may be open at a time -- a second one
            % would fight the first over the same ASIO device (the worker
            % holds it open for the run) and over the same MATLAB prefs.
            % Detected by the figure itself, not a stored handle, so a
            % stale reference can never mask a window the user already
            % closed.
            existing = findall(groot,'Type','figure','Tag',mabr.ui.App.InstanceTag);
            if ~isempty(existing)
                figure(existing(1));
                error('mabr:ui:App:alreadyOpen', ...
                    'MABR is already open -- bringing the existing window to the front.');
            end
            % Audio first: the Config is built FROM it, because the rig's
            % sample rate is a setting (mabr.AudioSettings.SampleRate) and
            % everything a Config answers about rates is derived from that one
            % number. A pref that has never been written yields the 192 kHz
            % default, which is the rate every MABR before the setting ran at.
            app.Audio  = mabr.AudioSettings.loadPrefs();
            app.Config = app.Audio.config();
            try
                app.Config.verifyToolboxes(true);
            catch me
                uialert_or_warn(me.message);
            end
            app.Artifacts = mabr.ArtifactPolicy.loadPrefs();
            app.Filters   = mabr.FilterPolicy.loadPrefs();
            app.Views     = mabr.ViewPolicy.loadPrefs();
            % stimgen (when present) logs through MABR's logger from here on
            % -- one console stream and one .error_logs/ file instead of a
            % second daily file under tempdir. The seam is stimgen's
            % (stimgen.LogSink); an older submodule checkout without it just
            % keeps stimgen's own logger, which is the standalone behaviour.
            try
                if mabr.stim.stimgenAvailable()
                    stimgen.util.logSink(mabr.log.StimgenLogSink());
                end
            catch me
                mabr.log.vprintf(2,'App: stimgen log sink not installed (%s).',me.message);
            end
            rc = getpref('MABR','RecentConfigFiles',{});
            if iscell(rc), app.RecentConfigs = rc; end
            % The notebook opens with the app, not with the schedule: the first
            % things worth writing down (impedances, what was changed since
            % yesterday) happen before Start. Its stamps ask the controller
            % where the session is, which is why the function is indirected
            % through the App -- there is no controller yet.
            app.Notes = mabr.data.SessionNotes();
            app.Notes.ContextFcn = @() app.noteContext();
            app.createComponents();
            % Covers syncAdvanceEnables/syncArtifactFields/syncFilterFields --
            % the acquisition controls have one more thing to be derived from
            % than themselves (see syncAcquisitionEnables).
            app.syncAcquisitionEnables();
            app.syncISIFields();
            app.syncRecentConfigsMenu();
            % Last, once every control exists to be written into: whatever the
            % previous session was set up with -- bank, repetitions, strategy,
            % ISI, subject, output folder. The three policy objects above are
            % already back from their own prefs; this is everything else the
            % window owns, which until now had to be re-entered by hand or
            % re-loaded from a configuration file at every launch.
            app.restoreLastSession();
            if nargout == 0, clear app; end
        end

        function delete(app)
            % Whatever layout the user ended up with is the one they want back
            % next session, so capture it before anything is torn down.
            app.rememberViewerPositions();
            mabr.ui.WindowPos.remember(app.UIFigure,'MABR');
            % ... and whatever the window was set up to run. Written here
            % rather than on every edit because a setting is only "the last
            % one used" once the session that used it is over -- and again at
            % Start (see onStart), so a MATLAB that never gets to close still
            % leaves behind the settings something was actually acquired with.
            app.saveLastSession();
            try, delete(app.Listeners);  end %#ok<TRYNC>
            try, delete(app.NotesView);  end %#ok<TRYNC>
            try, delete(app.Controller); end %#ok<TRYNC>
            try, delete(app.TraceOrg);   end %#ok<TRYNC>
            try, delete(app.LivePlot);   end %#ok<TRYNC>
            try, delete(app.MetricPlots); end %#ok<TRYNC>
            try, delete(app.StimViewer); end %#ok<TRYNC>
            try, delete(app.ProgressMon); end %#ok<TRYNC>
            try, delete(app.TestRunner); end %#ok<TRYNC>
            try, delete(app.UIFigure);   end %#ok<TRYNC>
            % Last, and only once every worker above has been killed and
            % waited for -- mabr.shutdownPool leaves a busy pool alone, and
            % MABR's own futures have to be off it before that test can mean
            % what it says. After the window is gone, too: reaping workers
            % takes a moment and there is nothing left to draw.
            try %#ok<TRYNC>
                if app.poolShutdownEnabled(), mabr.shutdownPool(); end
            end
        end

        function figs = windows(app)
            % Every MABR window currently open, main window LAST.
            %
            % Two sources, because the App is not the only owner. The viewers
            % it built are taken from its own handles, which is authoritative
            % and gives them a stable order; everything else MABR puts on
            % screen -- a trace inspector opened from the organizer, a
            % notebook the organizer popped out, an analysis window's static
            % copy -- belongs to somebody whose handle is private, so it is
            % found by Tag/Name instead. 'MABR' is what those windows have in
            % common and what a user's own figures do not, which is the whole
            % test; the main window is excluded there and appended by handle
            % afterwards so it cannot land in the middle of the list.
            figs = matlab.ui.Figure.empty(1,0);
            figs = addFig(figs,viewerFigure(app.LivePlot));
            app.pruneMetricPlots();
            for i = 1:numel(app.MetricPlots)
                figs = addFig(figs,viewerFigure(app.MetricPlots(i)));
            end
            figs = addFig(figs,viewerFigure(app.TraceOrg));
            figs = addFig(figs,viewerFigure(app.StimViewer));
            figs = addFig(figs,viewerFigure(app.ProgressMon));
            figs = addFig(figs,viewerFigure(app.NotesView));
            figs = addFig(figs,viewerFigure(app.TestRunner,'UIFigure'));

            others = findall(groot,'Type','figure');
            for i = 1:numel(others)
                if mabr.ui.App.isMabrWindow(others(i))
                    figs = addFig(figs,others(i));
                end
            end
            figs = addFig(figs,app.UIFigure);
        end

        function n = bringToFront(app)
            % Raise every open MABR window above whatever else is on the
            % desktop. The main window goes last (see windows) so the press
            % hands focus back to the window it came from -- the viewers are
            % laid out beside it rather than over it, so nothing is buried by
            % that. A minimized window is restored first: figure() raises a
            % minimized window without un-minimizing it, which would quietly
            % drop it from the "all" this promises. Returns how many were
            % raised, the main window included.
            figs = app.windows();
            n = 0;
            for i = 1:numel(figs)
                f = figs(i);
                if ~isgraphics(f), continue; end
                try
                    if isprop(f,'WindowState') && strcmp(f.WindowState,'minimized')
                        f.WindowState = 'normal';
                    end
                    figure(f);
                    n = n + 1;
                catch me
                    mabr.log.vprintf(2,'App: could not raise "%s" (%s).', ...
                        get(f,'Name'),me.message);
                end
            end
            drawnow limitrate
        end
    end

    % ===================================================================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','MABR', 'Position',[100 100 480 700], ...
                'Tag',mabr.ui.App.InstanceTag, ...
                'CloseRequestFcn',@(~,~) app.onClose());
            mabr.ui.WindowPos.restore(app.UIFigure,'MABR',app.UIFigure.Position);
            if getpref('MABR','AlwaysOnTop',false)
                app.UIFigure.WindowStyle = 'alwaysontop';
            end

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
            % A preference rather than a live switch: it decides how big the
            % parallel pool is made, and a pool cannot be resized once the
            % acquisition worker is on it (see mabr.pool), so it takes effect
            % at the next Start -- and restarts the pool and the acquisition
            % worker to do so.
            app.ComputeMenuItem = uimenu(app.SettingsMenu,'Text','Background compute workers', ...
                'Separator','on','Checked',onOff(app.computeEnabled()), ...
                'Tooltip',['Run the live signal processing and the online analysis on two ' ...
                           'extra parallel-pool workers instead of in this window. Takes ' ...
                           'effect at the next Start, which restarts the parallel pool.'], ...
                'MenuSelectedFcn',@(~,~) app.onComputeWorkers());
            % The other half of that preference: the workers are killed when
            % this window closes (deleting an Engine sends Kill and waits),
            % but the pool they ran on outlives them, and an idle pool is
            % still one to three worker processes holding a MATLAB's worth of
            % memory each. Default on, since a pool nobody is acquiring with
            % is pure cost -- and mabr.shutdownPool declines to touch a busy
            % one, so a parfor of the user's own is never cancelled by it.
            app.PoolMenuItem = uimenu(app.SettingsMenu,'Text','Shut down parallel pool on exit', ...
                'Checked',onOff(app.poolShutdownEnabled()), ...
                'Tooltip',['Delete the parallel pool when MABR closes, releasing its ' ...
                           'worker processes. Switch off to keep the pool warm for ' ...
                           'other work (or for the next launch of MABR).'], ...
                'MenuSelectedFcn',@(~,~) app.onPoolShutdown());
            % A viewer preference, and unlike the one above it takes effect at
            % once: it only decides whether finished blocks are handed to the
            % trace organizer, which is safe to change at any moment -- so it
            % is in neither configControls nor liveControls and stays live
            % throughout a schedule.
            app.TraceXferMenuItem = uimenu(app.SettingsMenu,'Text','Send blocks to trace organizer', ...
                'Checked',onOff(app.traceTransferEnabled()), ...
                'Tooltip',['Add each finalized block to the trace organizer as a ' ...
                           'trace (and open it at Start, if it is in the list below). ' ...
                           'Switch off to acquire without it; the organizer can still ' ...
                           'be opened by hand to load a .torg.'], ...
                'MenuSelectedFcn',@(~,~) app.onTraceTransfer());

            % Which windows come up by themselves at Start. A submenu of
            % ticks rather than a dialog: there is one question per window and
            % the answer is yes or no, so the menu IS the editor. Like the
            % transfer preference above it is in neither control list -- it
            % decides nothing until the next Start.
            app.StartupMenu = uimenu(app.SettingsMenu,'Text','Windows to open at Start', ...
                'Separator','on', ...
                'Tooltip',['Which MABR windows open by themselves when a schedule ' ...
                           'starts. Every one of them can still be opened from the ' ...
                           'toolbar at any time.']);
            names  = mabr.ViewPolicy.names();
            labels = mabr.ViewPolicy.labels();
            app.StartupItems = gobjects(1,numel(names));
            for k = 1:numel(names)
                app.StartupItems(k) = uimenu(app.StartupMenu,'Text',labels{k}, ...
                    'Checked',onOff(app.Views.opens(names{k})), ...
                    'MenuSelectedFcn',@(~,~) app.onStartupWindow(names{k}));
            end

            % The session-to-session recall of everything else the window owns
            % (see saveLastSession/restoreLastSession). A preference because a
            % shared rig may want every session to start from the same known
            % state instead of from whatever the last user left behind, which
            % is exactly the case where reopening onto someone else's subject
            % and bank is worse than reopening empty.
            app.RestoreMenuItem = uimenu(app.SettingsMenu,'Text','Restore settings from last session', ...
                'Checked',onOff(app.restoreSessionEnabled()), ...
                'Tooltip',['Reopen MABR with the subject, output folder, stimulus ' ...
                           'bank, repetitions, strategy and timing the last session ' ...
                           'ended with. Takes effect at the next launch.'], ...
                'MenuSelectedFcn',@(~,~) app.onRestoreSession());

            app.HelpMenu = uimenu(app.UIFigure,'Text','&Help');
            uimenu(app.HelpMenu,'Text','MABR Wiki', ...
                'MenuSelectedFcn',@(~,~) app.openHelp());
            % Test Mode gets its own item rather than only a link inside the
            % audio dialog: someone reading a .abr file and wondering whether
            % it came out of a loopback run is not going to look for the
            % answer under a device setting.
            uimenu(app.HelpMenu,'Text','About Test Mode…', ...
                'Tooltip',['What Test Mode does, what it proves about ' ...
                           'stimulus/acquisition alignment, and what its ' ...
                           'files are and are not.'], ...
                'MenuSelectedFcn',@(~,~) app.openHelp('Test-Mode'));
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
                'Tooltip',['Folder for .abr files, one per condition — or, under stimulation ' ...
                           'only, .stimlog files, one per run. Leave empty to run without saving.']);
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
                'Items',[mabr.ui.App.StrategyItems {'Custom function…'}], ...
                'ItemsData',[mabr.ui.App.builtinStrategies() {mabr.ui.App.StrategyPickSentinel}], ...
                'Tooltip',['How the bank is ordered: one stimulus per run, or intermixed ' ...
                           'within a run. "Custom function…" prompts for a function file — ' ...
                           'see +mabr/+stim/+strategy/custom_template.m.'], ...
                'ValueChangedFcn',@(~,~) app.onStrategySelected());
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
            % Kept so the whole panel can say when none of it applies: every
            % control below judges, stops, or displays a RECORDING, and a
            % stimulation-only run has none (see syncAcquisitionEnables).
            app.AcqPanel   = g.Parent;
            app.AcqPanelFG = app.AcqPanel.ForegroundColor;

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
            % The live view is the one tool that has nothing to show in
            % stimulation-only mode, so it is also the one kept as a handle
            % (see syncAcquisitionEnables).
            app.LiveTool = app.toolButton('live',ink,'Live plot',@() app.onShowLive());
            % Online analysis. Like the live view it has nothing to show when
            % nothing is recorded, so it is the other tool syncAcquisitionEnables
            % greys out under stimulation only. Every press opens ANOTHER
            % window -- see onMetricPlot.
            app.MetricTool = app.toolButton('metrics',ink, ...
                'Online analysis — one metric across conditions (new window each press)', ...
                @() app.onMetricPlot());
            app.toolButton('traces',ink, 'Trace organizer',  @() app.onTraceOrg());
            app.toolButton('stim',  ink, 'Stimulus viewer',  @() app.onStimViewer());
            % Progress is the one viewer that is worth having open in EVERY
            % mode, stimulation-only included -- it is the only window there
            % that fills (see onStart), which is why it is here rather than
            % beside the live view in syncAcquisitionEnables' disable list.
            app.toolButton('progress',ink,'Acquisition progress', @() app.onProgress());
            % The notebook. Deliberately a toolbar button rather than a panel
            % row: the main window is already five panels deep and a log needs
            % height the layout does not have, while what the operator actually
            % needs is one press to write a line down at the moment something
            % happens. Like the rest of the toolbar it is never disabled --
            % writing a note is safe in any state, and the states worth writing
            % about are exactly the busy ones.
            app.NotesView = mabr.ui.Notes.toolbarButton(app.Toolbar,app.Notes, ...
                'Name','Session','Color',ink);

            % Window management, grouped together after the viewers: one
            % button gathers the windows up, the other pins this one down.
            % Never disabled, for the same reason the notebook is not --
            % losing a viewer behind another application is a thing that
            % happens most during a run, which is exactly when every other
            % control is locked.
            app.toolButton('front',ink, ...
                'Bring all MABR windows to the front', ...
                @() app.onBringToFront(),true);

            onTop = strcmp(app.UIFigure.WindowStyle,'alwaysontop');
            app.AlwaysOnTopTool = uitoggletool(app.Toolbar,'Separator','off', ...
                'CData',mabr.ui.Icon.fromArt(mabr.ui.App.glyph('pin'),ink), ...
                'State',matlab.lang.OnOffSwitchState(onTop), ...
                'Tooltip','Keep the MABR window on top of other windows', ...
                'ClickedCallback',@(src,~) app.onAlwaysOnTop(src));

            app.toolButton('help',  help,'Help (MABR wiki)', @() app.openHelp(),true);
        end

        function onAlwaysOnTop(app,src)
            % 'alwaysontop' is a documented uifigure WindowStyle value as of
            % R2021a -- MABR's minimum (R2021b) already covers it, so no
            % undocumented Java/CEF trick is needed. Persisted like the other
            % per-rig prefs (mabr.AudioSettings etc.) so it survives restart.
            onTop = src.State == matlab.lang.OnOffSwitchState.on;
            if onTop
                app.UIFigure.WindowStyle = 'alwaysontop';
            else
                app.UIFigure.WindowStyle = 'normal';
            end
            setpref('MABR','AlwaysOnTop',onTop);
        end

        function onBringToFront(app)
            n = app.bringToFront();
            if n <= 1
                app.setStatus('No other MABR windows are open.');
            else
                app.setStatus(sprintf('Raised %d MABR windows.',n));
            end
        end

        function h = toolButton(app,glyph,rgb,tip,fcn,sep)
            if nargin < 6, sep = false; end
            sepStr = 'off'; if sep, sepStr = 'on'; end
            h = uipushtool(app.Toolbar,'Tooltip',tip,'Separator',sepStr, ...
                'CData',mabr.ui.Icon.fromArt(mabr.ui.App.glyph(glyph),rgb), ...
                'ClickedCallback',@(~,~) fcn());
        end

        function openHelp(~,page)
            % The wiki front page, or a named page on it. The address itself
            % lives in mabr.ui.wikiURL, so the menu item, the toolbar button
            % and the hyperlink in the audio dialog cannot drift apart.
            if nargin < 2, page = ''; end
            web(mabr.ui.wikiURL(page),'-browser');
        end

        function ctx = noteContext(app)
            % Where the session is, for stamping a note. Indirected through the
            % App because the notebook outlives (and predates) any one
            % controller: before the first Start, and after a controller is
            % rebuilt for a different mode, there is nothing to ask -- and the
            % right answer then is an empty context, which stamps the note with
            % the wall clock alone rather than a run that is not running.
            ctx = struct();
            if isempty(app.Controller) || ~isvalid(app.Controller), return; end
            ctx = app.Controller.noteContext();
        end

        function bindNotes(app)
            % Give the controller's session THIS App's notebook, replacing the
            % empty one it built for itself. One store per session, however
            % many controllers a session outlives: notes taken before Start,
            % and notes taken before a controller was rebuilt for a different
            % mode, belong to the same log as everything since.
            if isempty(app.Controller) || ~isvalid(app.Controller), return; end
            app.Controller.Session.Notes = app.Notes;
        end

        function applyNotesJournal(app,preview)
            % Point the notebook's crash journal at this session's output
            % folder, so every note is on disk the moment it is committed
            % rather than only once a block finishes.
            %
            % A preview writes no files at all -- that is the whole of what
            % Preview means -- so it gets no journal either, and neither does a
            % run with no output folder set. The notes are still kept in memory
            % and still reach any file a later real run writes.
            app.Notes.Subject = app.SubjectField.Value;
            app.Notes.JournalFile = '';
            if preview || isempty(app.OutputField.Value), return; end
            try
                app.Notes.JournalFile = fullfile(app.OutputField.Value, ...
                    mabr.data.io.buildNotesFilename(app.Notes.Subject, ...
                                                    app.Notes.StartTime));
                app.Notes.writeJournal();
            catch me
                app.Notes.JournalFile = '';
                mabr.log.vprintf(1,1,'Notes journal not started: %s',me.message);
            end
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

            cfg.Strategy      = app.strategySetting();
            % Saved as its FILE for the same reason the advance criterion is:
            % a path re-resolves across sessions and MABR versions where a
            % serialised handle, with its captured workspace, would not.
            cfg.StrategyCustomFile = app.CustomStrategyFile;
            cfg.StrategyCustomName = app.CustomStrategyName;
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

            % The rest of what a session IS, beyond what it plays: which
            % windows come up, how they are arranged, and how the two plotting
            % windows are set to draw. A configuration that restored the
            % protocol but not the layout would still leave the operator
            % rebuilding their screen at every switch, which is most of the
            % work switching protocols actually costs.
            cfg.Views = app.Views.toStruct();
            % From the open live view where there is one -- it is the
            % authority on its own look, and its pref is only written when a
            % user changes a control (see mabr.ui.LivePlot.savePrefs).
            if isempty(app.LivePlot) || ~isvalid(app.LivePlot)
                cfg.LiveView = mabr.ui.LivePlot.loadDefaults();
            else
                cfg.LiveView = app.LivePlot.displaySettings();
            end
            % The analysis windows each own their look and write it to the
            % same pref as they are tuned, so the pref IS the last choice --
            % there is no one window to ask, and asking the first of several
            % would be a coin toss.
            cfg.Analysis = mabr.ui.MetricPlot.loadDefaults();
            % Positions are read out of the windows first, so a configuration
            % saves the layout as it is on screen rather than as it was when
            % something last closed.
            app.rememberViewerPositions();
            mabr.ui.WindowPos.remember(app.UIFigure,'MABR');
            cfg.WindowPos = mabr.ui.WindowPos.snapshot();
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

            % Before the bank, not after it: a configuration's Audio carries
            % the sample rate, and applyConfigStimuli reloads the bank AT
            % app.Config's rate. Restoring the rate afterwards would leave the
            % bank rendered at the old one and the device opened at the new.
            if isfield(cfg,'Audio')
                app.Audio = mabr.AudioSettings.fromStruct(cfg.Audio);
                mabr.AudioSettings.savePrefs(app.Audio);
                app.applySampleRate();
            end

            warn = app.applyConfigStimuli(cfg);
            % applyConfigStimuli reloads at app.Config's rate, so this is
            % normally a no-op. It is the safety net for the case it leaves
            % alone: a configuration that names no reloadable bank, restoring
            % a rate that the bank already loaded was not rendered at.
            rateWarn = app.retuneStimuli();
            if ~isempty(rateWarn)
                if isempty(warn), warn = rateWarn; else, warn = [warn ' ' rateWarn]; end
            end

            % Re-resolve a saved custom strategy first, so its "Custom: <name>"
            % item exists before cfg.Strategy tries to select 'custom'. When
            % the file has moved or no longer conforms the item is simply
            % absent, and the guard below then leaves the strategy alone
            % rather than selecting a 'custom' with no function behind it --
            % which build() would refuse at Start.
            warn = app.applyConfigCustomStrategy(cfg,warn);
            if isfield(cfg,'Strategy') ...
                    && ~strcmp(cfg.Strategy,mabr.ui.App.StrategyPickSentinel) ...
                    && any(strcmp(cfg.Strategy,app.StrategyDrop.ItemsData))
                app.StrategyDrop.Value = cfg.Strategy;
                app.LastStrategyValue  = cfg.Strategy;
            end
            % The plan decides whether a restored custom strategy intermixes,
            % and syncAdvanceEnables below is about to ask. Building it here
            % also puts the plan summary in step with the settings just
            % restored, which the ISI/repetition restores further down redo.
            app.refreshPlan();
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
            if isfield(cfg,'Views')
                app.Views = mabr.ViewPolicy.fromStruct(cfg.Views);
                mabr.ViewPolicy.savePrefs(app.Views);
                app.syncStartupMenu();
            end
            if isfield(cfg,'LiveView')
                % Into the open view AND into the pref, so the window on
                % screen changes now and the next one to open agrees with it.
                mabr.ui.LivePlot.saveDefaults(cfg.LiveView);
                if ~isempty(app.LivePlot) && isvalid(app.LivePlot)
                    app.LivePlot.applySettings(cfg.LiveView);
                end
            end
            if isfield(cfg,'Analysis')
                % Pref only: an analysis window's look is its own once opened
                % (see mabr.ui.MetricPlot.saveDefaults), so this shows up in
                % the next one opened rather than rewriting the ones up now.
                mabr.ui.MetricPlot.saveDefaults(cfg.Analysis);
            end
            if isfield(cfg,'WindowPos')
                app.applyWindowPositions(cfg.WindowPos);
            end
            % Last, and unconditionally: the Audio restored above can have put
            % the app into stimulation only, which disables the entire
            % Acquisition panel -- including the artifact and filter controls
            % the two blocks above just re-enabled from the same file.
            app.syncAcquisitionEnables();

            app.checkOverlap();
            app.refreshPlan();
        end

        function changed = applySampleRate(app)
            % Rebuild app.Config from app.Audio's rate, and report whether that
            % was actually a change. mabr.Config holds its rate immutably --
            % it is a value object half the toolbox keeps a copy of, so a rate
            % change is a NEW Config handed out, never a mutation one holder
            % sees and the rest do not. Everything downstream either reads
            % app.Config directly (buildSchedule, the filter dialog) or is
            % rebuilt around it (ensureController, which compares rates for
            % exactly this reason).
            changed = app.Config.DACSampleRate ~= app.Audio.SampleRate;
            if changed, app.Config = app.Audio.config(); end
        end

        function warn = retuneStimuli(app)
            % Bring the loaded bank onto app.Config's rate, and say so when it
            % cannot be done. A bank is rendered waveforms, so a rate change
            % invalidates it outright -- mabr.stim.StimulusSet will not be
            % built at a rate other than the Config's, and mabr.stim.Schedule
            % will not plan against a mismatch.
            %
            % Where a bank knows its own source it is simply regenerated at the
            % new rate: demoStimuli rebuilds, and a stimgen bank re-synthesizes
            % from parameters -- which is precisely why mabr.stim.fromStimgen
            % takes parameters and never a cached Signal. A bank built live in
            % the designer and never saved has no source to regenerate from; it
            % is left exactly as it is and the plan refuses until the user
            % reloads it, because silently resampling somebody's calibrated
            % waveforms would be a worse answer than asking for them again.
            %
            % Returns a one-line warning (empty if none), the same contract
            % applyConfigStimuli follows.
            warn = '';
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0, return; end
            fs = app.Config.DACSampleRate;
            if app.Stimuli.SampleRate == fs
                app.refreshPlan();   % the duration estimate moves with the rate
                return
            end

            src  = app.Stimuli.Source;
            ids  = app.Stimuli.IDs();
            reps = app.Reps;
            set  = [];
            why  = '';
            switch lower(src.Kind)
                case 'demo'
                    try
                        set = mabr.stim.demoStimuli(app.Config);
                    catch me
                        why = me.message;
                    end
                case {'file','stimgen'}
                    if ~isempty(src.File) && isfile(src.File)
                        try
                            set = mabr.stim.StimulusSet.fromFile(src.File,app.Config);
                        catch me
                            why = me.message;
                        end
                    else
                        why = 'its source file is no longer available';
                    end
                otherwise
                    why = 'it came from no reloadable source';
            end

            if isempty(set)
                warn = sprintf(['The stimulus bank is rendered at %s kHz but the device ' ...
                    'is now set to %s kHz, and it could not be regenerated (%s). ' ...
                    'Load the bank again — nothing can run until the two match.'], ...
                    mabr.Config.rateText(app.Stimuli.SampleRate), ...
                    mabr.Config.rateText(fs),why);
                app.setSourceLabel();   % the label carries the mismatch meanwhile
                app.refreshPlan();
                return
            end

            app.adoptStimuli(set,false);   % resets Reps to the bank's own defaults
            app.applyRepsById(ids,reps);
        end

        function applyRepsById(app,ids,counts)
            % Carry per-stimulus repetition counts across a bank reload,
            % matched by ID rather than position: a bank regenerated from the
            % same source reproduces the same IDs, and matching by name is what
            % survives it having gained or dropped an entry meanwhile.
            if isempty(ids) || isempty(counts), return; end
            newIds = app.Stimuli.IDs();
            r = app.Reps;
            for k = 1:min(numel(ids),numel(counts))
                idx = find(strcmp(newIds,ids{k}),1);
                if ~isempty(idx), r(idx) = counts(k); end
            end
            app.Reps = r;
            if ~isempty(app.Reps), app.RepsField.Value = app.Reps(1); end
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

        function warn = applyConfigCustomStrategy(app,cfg,warn)
            % Re-resolve the custom presentation strategy a configuration was
            % saved with, restoring its dropdown item so cfg.Strategy can
            % select 'custom'. Returns the (possibly appended) one-line
            % warning -- see applyConfiguration. A missing/moved/malformed
            % file is not an error: the item is simply not restored, and
            % because 'custom' is then absent from ItemsData the strategy
            % restore leaves whatever was selected before.
            if ~isfield(cfg,'StrategyCustomFile') || isempty(cfg.StrategyCustomFile)
                return
            end
            file = char(cfg.StrategyCustomFile);
            [pn,nm,ext] = fileparts(file);
            note = '';
            if ~isfile(file) || ~strcmpi(ext,'.m')
                note = ['Configuration''s custom presentation strategy could not be found at "' ...
                        file '"; the built-in strategy is used instead.'];
            else
                app.addToPath(pn);
                fcn = str2func(nm);
                [ok,why] = mabr.stim.strategy.validate(fcn);
                if ok
                    app.CustomStrategyFcn  = fcn;
                    app.CustomStrategyName = nm;
                    app.CustomStrategyFile = file;
                    app.ensureCustomStrategyItem(nm);
                else
                    note = ['Configuration''s custom presentation strategy "' nm ...
                            '" no longer conforms (' why '); the built-in strategy is used.'];
                end
            end
            if ~isempty(note)
                if isempty(warn), warn = note; else, warn = [warn ' ' note]; end
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
            testing    = app.Audio.Testing;
            stimOnly   = app.Audio.isStimulationOnly();
            useCompute = app.computeEnabled();
            % The sample rate joins Testing as a reason to rebuild rather than
            % reuse. Unlike the stimulation-only flag it does NOT ride per
            % block: the controller captured a mabr.Config at construction and
            % everything it does with rates reads that copy -- the live view's
            % decimation stride, the filter design rate, finalize_run's
            % resample, and the Session's own stored rates. Handing it a run
            % rendered at another rate would leave every one of those silently
            % describing a clock the data is not on.
            if ~isempty(app.Controller) && isvalid(app.Controller) ...
                    && app.Controller.Testing == testing ...
                    && app.Controller.UsingCompute == useCompute ...
                    && app.Controller.Config.DACSampleRate == app.Config.DACSampleRate
                % The mode rides per block, so a worker built for one is
                % reused for the other -- but it is re-labelled for what it is
                % about to do (mabr.acq.Engine.setRole, from AcqController's
                % start), and the message says which it is being reused as.
                app.Controller.Engine.setRole( ...
                    mabr.ui.AcqController.workerRole(stimOnly));
                app.bindNotes();
                app.setStatus(['Reusing the running ' ...
                    app.Controller.Engine.WorkerName '.']);
                return
            end
            % (Re)build for the selected mode.
            delete(app.Listeners);
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.setStatus('Shutting down the previous worker…'); drawnow;
                delete(app.Controller);
            end

            % The pool has to be the right size BEFORE the first worker
            % launches on it (see mabr.pool): one for acquisition, two more
            % for the compute workers. A pool that cannot be resized -- busy,
            % or the profile too small -- costs the compute workers for the
            % session, never the acquisition.
            [~,ok] = mabr.pool(1 + 2*useCompute,@(msg) app.setStatus(msg));
            if useCompute && ~ok
                app.setStatus(['The parallel pool could not be sized for the compute ' ...
                    'workers; computing in this window for the session.']);
                drawnow;
                useCompute = false;
            end

            % Startup is slow (parallel pool + worker handshake), so the
            % engine reports each milestone straight into the status line.
            app.Controller = mabr.ui.AcqController(app.Config,testing, ...
                @(msg) app.setStatus(msg),stimOnly,useCompute);
            app.Listeners = [ ...
                addlistener(app.Controller,'StateChanged',   @(~,e) app.onState(e)); ...
                addlistener(app.Controller,'MetricsUpdated', @(~,e) app.onMetrics(e)); ...
                addlistener(app.Controller,'BlockReady',     @(~,e) app.onBlockReady(e)); ...
                addlistener(app.Controller,'BlockSaved',     @(~,e) app.onBlockSaved(e)); ...
                addlistener(app.Controller,'AlignmentChecked',@(~,e) app.onAlignment(e)); ...
                addlistener(app.Controller,'ScheduleComplete',@(~,~) app.onScheduleComplete())];
            % Before listenTo below: the organizer adopts the session's
            % notebook when it starts tracking a controller, and the session's
            % notebook has to be the App's by then or it would adopt the fresh
            % one the controller built for itself and be left on an orphan.
            app.bindNotes();
            % An organizer left open across a controller rebuild would still be
            % listening to the deleted one, so re-point it at the new -- or
            % leave it unattached, if the transfer preference is off.
            app.bindTraceOrg();
            app.bindProgress();
            % Same for every open analysis window: attach() replaces its
            % listeners rather than adding a second set, and backfills the new
            % session's blocks, so one left open across a mode change keeps
            % working instead of quietly going dead.
            app.pruneMetricPlots();
            for i = 1:numel(app.MetricPlots)
                app.MetricPlots(i).attach(app.Controller);
            end
            app.Controller.waitUntilReady(120);
            app.setStatus([mabr.acq.Engine.capitalize( ...
                app.Controller.Engine.WorkerName) ' ready.']);
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

        function adoptStimuli(app,set,announce)
            % Take on a new stimulus bank and reset the repetition counts to
            % whatever the bank suggests (its own Repetitions field, else the
            % schedule default).
            %
            % announce (default true) governs only the uncalibrated-levels
            % alert. retuneStimuli passes false: re-rendering the bank the user
            % already adopted at a new sample rate is not a new bank, the alert
            % was raised when it was first loaded, and raising it again would
            % put a modal alert behind the still-open modal audio dialog that
            % prompted the re-render.
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
            if nargin < 3 || announce
                app.warnUncalibratedLevels(set);
            end
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
            canEarly  = ~app.currentStrategyIntermixes();
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

        function onStrategySelected(app)
            % The dropdown's ValueChangedFcn: only fired by a genuine user
            % pick, so this is the one place the "Custom function…" file
            % picker may open. Everything programmatic (config load, transport)
            % calls onStrategyChanged directly and never trips a dialog.
            if strcmp(app.StrategyDrop.Value,mabr.ui.App.StrategyPickSentinel)
                app.chooseCustomStrategy();
            end
            app.onStrategyChanged();
        end

        function onStrategyChanged(app)
            % refreshPlan FIRST: it is what builds the plan, and for a custom
            % strategy the built plan is the only thing that knows whether the
            % runs intermix (see currentStrategyIntermixes). Deriving the
            % advance enables before it would judge a custom plan on the
            % static's conservative guess and disable an early stop the plan
            % in fact allows. Nothing in refreshPlan reads the advance
            % controls, so the order is free for the built-in strategies.
            app.refreshPlan();
            intermixed = app.currentStrategyIntermixes();
            app.syncAdvanceEnables();
            % Remember the last real selection so a cancelled or rejected
            % Custom function... pick has somewhere to fall back to. Without
            % this a user who had chosen 'interleaved', then opened the
            % picker and cancelled, would land back on 'blocked' -- their
            % strategy silently changed by a dialog they dismissed.
            if ~strcmp(app.StrategyDrop.Value,mabr.ui.App.StrategyPickSentinel)
                app.LastStrategyValue = app.StrategyDrop.Value;
            end
            if intermixed
                app.setStatus(['Intermixed runs play to completion — ' ...
                    'correlation early-stop is available for blocked strategies only.']);
            end
        end

        function tf = currentStrategyIntermixes(app)
            % Whether the selected strategy mixes stimuli inside one run.
            %
            % For the five built-ins the name settles it. For 'custom' it
            % cannot -- that is a property of the runs the user's function
            % produced -- so the last plan that actually built is the
            % authority, and PlanIntermixed's conservative default stands
            % until one has (the function unresolved, or it errored).
            v = app.strategySetting();
            if strcmp(v,'custom'), tf = app.PlanIntermixed; return, end
            tf = mabr.stim.Schedule.strategyIntermixes(v);
        end

        function chooseCustomStrategy(app)
            % Prompt for a .m strategy function, resolve it to a handle, and
            % accept it only if it conforms to the contract. On cancel or
            % rejection the dropdown falls back to the last good selection, so
            % the sentinel is never left standing as the live value.
            [fn,pn] = uigetfile({'*.m','MATLAB function (*.m)'}, ...
                'Select a custom presentation strategy');
            figure(app.UIFigure);
            if isequal(fn,0), app.revertStrategySelection(); return; end

            file = fullfile(pn,fn);
            [dn,name] = fileparts(file);        % dn has no trailing separator
            app.addToPath(dn);
            fcn = str2func(name);
            [ok,why] = mabr.stim.strategy.validate(fcn);
            if ~ok
                uialert(app.UIFigure, sprintf(['"%s" is not a valid presentation strategy.' ...
                    '\n\n%s\n\nA strategy takes one context struct describing the design ' ...
                    'and returns the stimulus indices to present — a vector for one run, ' ...
                    'or a cell of vectors for several. Copy ' ...
                    '+mabr/+stim/+strategy/custom_template.m to get the contract right.'], ...
                    name,why),'Invalid presentation strategy');
                app.revertStrategySelection();
                return
            end

            app.CustomStrategyFcn  = fcn;
            app.CustomStrategyName = name;
            app.CustomStrategyFile = file;
            app.ensureCustomStrategyItem(name);
            app.StrategyDrop.Value = 'custom';
            app.LastStrategyValue  = 'custom';
            app.setStatus(sprintf('Custom presentation strategy: %s',name));
        end

        function ensureCustomStrategyItem(app,name)
            % Make sure a "Custom: <name>" item exists just before the
            % "Custom function…" sentinel, replacing any previous custom item.
            % Setting Items/Value programmatically does NOT fire
            % ValueChangedFcn, so this never re-enters the picker.
            % Both in ONE set(): assigning Items first would leave it a
            % longer list than ItemsData until the next line, and a
            % dropdown whose two lists disagree has no defined Value.
            set(app.StrategyDrop, ...
                'Items',    [mabr.ui.App.StrategyItems ...
                             {['Custom: ' name],'Custom function…'}], ...
                'ItemsData',[mabr.ui.App.builtinStrategies() ...
                             {'custom',mabr.ui.App.StrategyPickSentinel}]);
        end

        function revertStrategySelection(app)
            % Back to the last non-sentinel selection. If that was itself a
            % custom item that no longer exists (never resolved), the base
            % list has no such entry, so fall back to 'blocked'.
            v = app.LastStrategyValue;
            if ~any(strcmp(v,app.StrategyDrop.ItemsData)), v = 'blocked'; end
            app.StrategyDrop.Value = v;
        end

        function v = strategySetting(app)
            % The Strategy as a SETTING rather than as a widget state.
            %
            % The picker sentinel is a transient dropdown value -- it
            % stands only while the file dialog is open -- and is not a
            % strategy at all: saved into a configuration it would come
            % back as a dropdown reading "Custom function..." with no
            % function behind it, and Schedule.build would then refuse it
            % as an unknown strategy. Everything that treats the selection
            % as a setting -- captureConfiguration, buildSchedule, onStart
            % -- goes through here rather than reading Value raw.
            v = app.StrategyDrop.Value;
            if ~strcmp(v,mabr.ui.App.StrategyPickSentinel), return, end
            v = app.LastStrategyValue;
            if strcmp(v,mabr.ui.App.StrategyPickSentinel), v = 'blocked'; end
        end

        function fcn = currentStrategyFcn(app)
            % Map the dropdown's current selection to the ordering handle
            % buildSchedule hands the schedule. Empty for a built-in, which is
            % what Schedule.build expects for the five it plans itself.
            % strategySetting, not Value: buildSchedule asks it for the
            % strategy, so asking it anything else here could hand a
            % 'custom' Strategy an empty StrategyFcn, which build refuses.
            if strcmp(app.strategySetting(),'custom')
                fcn = app.CustomStrategyFcn;
            else
                fcn = [];
            end
        end

        function syncAdvanceEnables(app)
            % Early stop is unavailable once a run mixes stimuli: stopping it
            % would truncate whichever stimuli fell last in the sequence.
            % Called from transport() too, so it must not touch the status line.
            if app.Audio.isStimulationOnly()
                % Nothing is recorded, so there is no running average for a
                % criterion to look at -- every run plays out in full.
                app.AdvanceDrop.Enable = 'off';
                app.CorrField.Enable   = 'off';
                return
            end
            if app.currentStrategyIntermixes()
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
            % Artifact rejection judges recorded sweeps, of which a
            % stimulation-only run has none: the criterion, its threshold, and
            % the make-up runs it would append all have nothing to act on.
            live = ~app.Audio.isStimulationOnly();
            app.ArtifactDrop.Enable        = onOff(live);
            app.ArtifactField.Enable       = onOff(live && p.Enabled);
            app.ArtifactRepeatCheck.Enable = onOff(live && p.Enabled);
            app.ArtifactRepeatCheck.Value  = p.Repeat;
        end

        function saveArtifactPrefs(app)
            mabr.ArtifactPolicy.savePrefs(app.Artifacts);
        end

        % --- Stimulation only ------------------------------------------------
        function syncAcquisitionEnables(app)
            % Stimulation only (mabr.AudioSettings.StimulationOnly) opens an
            % output-only device and records NOTHING, so every acquisition
            % setting is inapplicable rather than merely unwise: an advance
            % criterion has no running average to watch, an artifact threshold
            % no sweep to judge, a filter chain nothing to draw. The three
            % sync* functions each grey their own controls (they are called
            % from transport() and would put them back otherwise); this puts
            % the reason on the panel, where a greyed control cannot.
            %
            % The live-plot toolbar button goes with them: in this mode the
            % controller is handed no LivePlot at all, so the window it opens
            % would never fill. The trace organizer stays -- it can still load
            % a saved .torg view, which has nothing to do with this run.
            stimOnly = app.Audio.isStimulationOnly();
            if stimOnly
                app.AcqPanel.Title = 'Acquisition — n/a (STIMULATION ONLY)';
            else
                app.AcqPanel.Title = 'Acquisition';
            end
            app.LiveTool.Enable   = onOff(~stimOnly);
            app.MetricTool.Enable = onOff(~stimOnly);
            % Advance is a CONFIG control: it is dead for the duration of a
            % schedule whatever the mode, and transport() owns putting it back
            % when one ends. Re-deriving it here mid-run would switch it on
            % again, so this only speaks for it while nothing is running.
            if ~app.isRunning(), app.syncAdvanceEnables(); end
            app.syncArtifactFields();
            app.syncFilterFields();

            % Last, and the one that must win: each sync* call above speaks
            % only for its own fields, which leaves every row LABEL black and
            % the header bold. The result reads as a live panel with some
            % greyed controls in it -- "not now" -- when what is true is that
            % none of it applies at all. Nothing here judges, stops, or
            % displays anything without a recording, so the panel is disabled
            % as a unit, labels and title included.
            %
            % The panel's own Enable is deliberately not used: uipanel only
            % gained one after R2021b, which mabr.Config still supports.
            if stimOnly
                set(findall(app.AcqPanel,'-property','Enable', ...
                    '-not','Type','uipanel'),'Enable','off');
                app.AcqPanel.ForegroundColor = [0.5 0.5 0.5];
            else
                % Only the labels are re-derived on the way back out: every
                % interactive control was just decided by the sync* calls
                % above and has to keep that verdict (an artifact threshold
                % stays dead under 'none', Advance under an intermixed
                % strategy), whereas a label carries no state of its own.
                set(findall(app.AcqPanel,'Type','uilabel'),'Enable','on');
                app.AcqPanel.ForegroundColor = app.AcqPanelFG;
            end
        end

        % --- Compute workers --------------------------------------------------
        function tf = computeEnabled(~)
            % The preference behind Settings > Background compute workers.
            % Default on: the workers are what keep the live trace at its
            % frame rate with the progress and analysis windows open.
            tf = getpref('MABR','ComputeWorker',true);
            tf = islogical(tf) && isscalar(tf) && tf || isnumeric(tf) && isscalar(tf) && tf ~= 0;
        end

        function onComputeWorkers(app)
            tf = ~app.computeEnabled();
            setpref('MABR','ComputeWorker',tf);
            app.ComputeMenuItem.Checked = onOff(tf);
            if tf, word = 'on'; else, word = 'off'; end
            app.setStatus(sprintf(['Background compute workers %s. Takes effect at the ' ...
                'next Start (the parallel pool is restarted).'],word));
        end

        function tf = poolShutdownEnabled(~)
            % The preference behind Settings > Shut down parallel pool on exit.
            % Default on: MABR is what sized the pool (see mabr.pool) and the
            % workers on it never return, so once this window is gone the pool
            % is only costing memory.
            tf = getpref('MABR','ShutdownPool',true);
            tf = (islogical(tf) || isnumeric(tf)) && isscalar(tf) && tf ~= 0;
        end

        function onPoolShutdown(app)
            tf = ~app.poolShutdownEnabled();
            setpref('MABR','ShutdownPool',tf);
            app.PoolMenuItem.Checked = onOff(tf);
            if tf
                msg = 'The parallel pool will be shut down when MABR closes.';
            else
                msg = 'The parallel pool will be left running when MABR closes.';
            end
            app.setStatus(msg);
        end

        % --- Transfer to the trace organizer ----------------------------------
        function tf = traceTransferEnabled(~)
            % The preference behind Settings > Send blocks to trace organizer.
            % Default on: watching the stack fill condition by condition is
            % what the organizer is for during a run. Off is for the rig that
            % only wants the live view (or one whose organizer is being used to
            % read an old .torg while a schedule runs).
            tf = getpref('MABR','TraceTransfer',true);
            tf = (islogical(tf) || isnumeric(tf)) && isscalar(tf) && tf ~= 0;
        end

        function onTraceTransfer(app)
            % Unlike the compute workers this takes effect immediately: an
            % organizer already open is attached or detached on the spot, so
            % the menu tick and what the window is doing cannot disagree.
            tf = ~app.traceTransferEnabled();
            setpref('MABR','TraceTransfer',tf);
            app.TraceXferMenuItem.Checked = onOff(tf);
            app.bindTraceOrg();
            if tf
                app.setStatus(['Finalized blocks will be sent to the trace organizer ' ...
                    '(it opens at Start when Settings > Windows to open at Start says so).']);
            else
                app.setStatus(['Finalized blocks will not be sent to the trace organizer. ' ...
                    'Open it from the toolbar to load a saved view.']);
            end
        end

        function bindTraceOrg(app)
            % The one place the preference reaches an open organizer. With the
            % transfer on it tracks the current controller (listenTo re-points
            % rather than stacking, so calling this again is safe); with it off
            % the listener is dropped -- listenTo with nothing to listen to is
            % how the organizer says "stop", and it keeps whatever traces are
            % already in there.
            if isempty(app.TraceOrg) || ~isvalid(app.TraceOrg), return; end
            if app.traceTransferEnabled() && ~isempty(app.Controller) ...
                    && isvalid(app.Controller)
                app.TraceOrg.listenTo(app.Controller);
            else
                app.TraceOrg.listenTo([]);
            end
        end

        % --- Which windows open at Start --------------------------------------
        function onStartupWindow(app,name)
            % One tick from Settings > Windows to open at Start. Takes effect
            % at the next Start; nothing is opened or closed now, since the
            % press says what the NEXT schedule should come up with and a
            % window appearing under the pointer would be a surprise nobody
            % asked for.
            app.Views = app.Views.setOpen(name,~app.Views.opens(name));
            mabr.ViewPolicy.savePrefs(app.Views);
            app.syncStartupMenu();
            app.setStatus(app.Views.summary());
        end

        function syncStartupMenu(app)
            % Re-derive the ticks from the policy -- called when it changes by
            % any route, a configuration file included.
            names = mabr.ViewPolicy.names();
            for k = 1:min(numel(app.StartupItems),numel(names))
                if ~isgraphics(app.StartupItems(k)), continue; end
                app.StartupItems(k).Checked = onOff(app.Views.opens(names{k}));
            end
        end

        % --- Session-to-session recall ----------------------------------------
        % The counterpart of the configuration FILE: everything the window
        % owns, written on the way out and read back on the way in, so a rig
        % reopens set up the way it was left instead of on the class defaults.
        % The two are the same snapshot (captureConfiguration/
        % applyConfiguration) through different doors -- a file is a named
        % place a user returns to deliberately, this is the one they land in
        % by doing nothing at all.
        function tf = restoreSessionEnabled(~)
            tf = getpref('MABR','RestoreSession',true);
            tf = (islogical(tf) || isnumeric(tf)) && isscalar(tf) && tf ~= 0;
        end

        function onRestoreSession(app)
            tf = ~app.restoreSessionEnabled();
            setpref('MABR','RestoreSession',tf);
            app.RestoreMenuItem.Checked = onOff(tf);
            if tf
                app.setStatus(['MABR will reopen with the settings this session ' ...
                    'ends with.']);
            else
                app.setStatus(['MABR will reopen with its defaults. This session''s ' ...
                    'settings are still saved, and Load Configuration still works.']);
            end
        end

        function saveLastSession(app)
            % Store the snapshot whether or not the preference is on: the
            % preference says what to do on the way IN, and a session whose
            % settings were never captured is one the user cannot get back by
            % switching it on afterwards. Guarded -- a rig with no writable
            % prefs must not fail to close over it.
            try
                setpref('MABR','LastSession',app.captureConfiguration());
            catch me
                mabr.log.vprintf(2,'App: last-session settings not saved (%s).',me.message);
            end
        end

        function restoreLastSession(app)
            % Apply that snapshot at launch. Every failure here is survivable
            % and none of them may stop the window from opening: a bank whose
            % file has moved, a pref written by another version, a struct
            % edited by hand. The status line says what happened, since a
            % window that silently comes up on someone else's subject is worse
            % than one that says whose settings these are.
            if ~app.restoreSessionEnabled(), return; end
            try
                if ~ispref('MABR','LastSession'), return; end
                cfg = getpref('MABR','LastSession');
                if ~isstruct(cfg) || ~isscalar(cfg), return; end
                warn = app.applyConfiguration(cfg);
                msg  = 'Settings restored from the last session.';
                if ~isempty(warn), msg = [msg ' ' warn]; end
                app.setStatus(msg);
            catch me
                app.setStatus(['Last session''s settings could not be restored: ' me.message]);
                mabr.log.vprintf(1,'App: last-session restore failed (%s).',me.message);
            end
        end

        % --- ASIO device / channel mapping -----------------------------------
        % Same shape as the artifact/filter settings, except this one is a
        % CONFIG control (see configControls): the worker's audioPlayerRecorder
        % is opened on whatever device Start hands it, so switching mid-run is
        % not something changing a property can safely do.
        function onAudioSettings(app)
            % Commit applies through applyAudioSettings while the dialog is
            % still open, so the settings can be pressed into the app and their
            % consequences watched here -- above all Stimulation only, which
            % takes the whole Acquisition panel out of play. Everything is
            % therefore already applied by the time this returns; the return
            % value is only what the dialog reports it committed (or [] for
            % none), and the standalone caller's route to the same thing.
            mabr.ui.AudioSettingsDialog(app.Audio,app.Config, ...
                @(p) app.applyAudioSettings(p));
            figure(app.UIFigure);
        end

        function applyAudioSettings(app,s)
            % One Commit from the audio dialog: adopt the settings, persist
            % them, and re-derive whatever the main window shows from them.
            app.Audio = s;
            mabr.AudioSettings.savePrefs(app.Audio);
            % The sample rate is the one setting here that is not confined to
            % the device: the Config is rebuilt from it and the stimulus bank
            % re-rendered at it, both before anything below reads either.
            rateWarn = '';
            rateChanged = app.applySampleRate();
            if rateChanged, rateWarn = app.retuneStimuli(); end
            % Stimulation only takes the entire Acquisition panel out of play,
            % so committing is the moment that has to be reflected.
            app.syncAcquisitionEnables();
            msg = ['Audio device: ' app.Audio.describe() '.'];
            if app.Audio.isStimulationOnly()
                msg = [msg ' Nothing will be recorded — each run saves its ' ...
                       'stimulation sequence to a .stimlog file instead.'];
            end
            if rateChanged
                % The worker's Config is fixed at construction, so a new rate
                % means a new worker (see ensureController) -- said plainly,
                % because the restart is slow and otherwise looks like a hang.
                msg = [msg ' The acquisition worker restarts on the next Start.'];
            end
            % A bank left at the wrong rate outranks all of that: nothing can
            % run until it is fixed.
            if ~isempty(rateWarn), msg = rateWarn; end
            app.setStatus(msg);
            % The dialog is modal and still up, so nothing would flush the
            % queue until it closes -- and the point of committing early is to
            % SEE the panel change behind it.
            drawnow limitrate
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
                app.setStatus(['Calibration needs a real device — turn off Test Mode ' ...
                               'in Settings ▸ Audio Device first.']);
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
            if app.Audio.isStimulationOnly()
                % The chain only ever decides what a plot or a sweep metric is
                % computed from, and there is neither. Saying so beats leaving
                % a live-looking corner frequency on a run that draws nothing.
                app.FilterLabel.Text      = 'n/a — nothing is recorded';
                app.FilterLabel.FontColor = [0.5 0.5 0.5];
                app.FilterButton.Enable   = 'off';
                return
            end
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
            % The one place a custom plan's shape becomes known -- summary()
            % asks the built runs, not the strategy's name. Recorded so
            % currentStrategyIntermixes can answer without rebuilding, and
            % left at its conservative default when the build above threw.
            app.PlanIntermixed = s.intermixed;
            if s.intermixed, kind = 'intermixed'; else, kind = 'blocked'; end
            app.PlanLabel.Text = sprintf( ...
                '%d runs (%s)  ·  %d presentations  ·  ~%s', ...
                s.numRuns,kind,s.presentations,durationText(s.duration));
        end

        function sch = buildSchedule(app)
            % One place that turns the GUI's settings into a schedule, shared
            % by the plan preview and onStart so they cannot drift apart.
            sch             = mabr.stim.Schedule(app.Stimuli,app.Config);
            sch.Strategy    = app.strategySetting();
            % Empty for the five built-ins, which is what build() expects;
            % under 'custom' it is the whole plan, and build() refuses without
            % it rather than falling back to an order nobody chose.
            sch.StrategyFcn = app.currentStrategyFcn();
            sch.Repetitions = app.Reps;
            % Both settings travel every time and the mode picks between them,
            % so the one not in force is still whatever the user last set it to.
            sch.ISI         = app.ISIField.Value/1e3;      % ms -> s
            sch.ISIRange    = [app.ISIMinField.Value app.ISIMaxField.Value]/1e3;
            sch.ISIMode     = app.isiMode();
            sch.Device           = app.Audio.Device;
            sch.PlayerChannels   = app.Audio.PlayerChannels;
            sch.RecorderChannels = app.Audio.RecorderChannels;
            sch.StimulationOnly  = app.Audio.isStimulationOnly();
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
            app.Previewing  = preview;
            app.StimOnlyRun = app.Audio.isStimulationOnly();
            app.TestRun     = app.Audio.Testing;
            app.setRunTitle(preview || app.StimOnlyRun || app.TestRun);
            if app.TestRun
                app.setBusy('Starting in Test Mode…');
            elseif preview
                app.setBusy('Starting preview…');
            elseif app.StimOnlyRun
                app.setBusy('Starting stimulation…');
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
                % The session is already on the App's notebook (bindNotes, from
                % ensureController above), so every file this run writes carries
                % the whole log -- including the notes taken while the
                % electrodes went in. All that is left is where the crash
                % journal goes, which is only knowable now that the output
                % folder is settled.
                app.applyNotesJournal(preview);

                c.setStimuli(app.Stimuli);

                % The controller builds its own schedule in setStimuli; replace
                % it with the one the GUI has been previewing.
                c.Schedule.Strategy    = app.strategySetting();
                c.Schedule.StrategyFcn = app.currentStrategyFcn();
                c.Schedule.Repetitions = app.Reps;
                c.Schedule.ISI         = app.ISIField.Value/1e3;   % ms -> s
                c.Schedule.ISIRange    = [app.ISIMinField.Value app.ISIMaxField.Value]/1e3;
                c.Schedule.ISIMode     = app.isiMode();
                c.Schedule.Device           = app.Audio.Device;
                c.Schedule.PlayerChannels   = app.Audio.PlayerChannels;
                c.Schedule.RecorderChannels = app.Audio.RecorderChannels;
                % isStimulationOnly(), not the raw flag: Testing opens no
                % device at all and wins, and buildSchedule/StimOnlyRun both
                % already ask the question that way.
                c.Schedule.StimulationOnly  = app.Audio.isStimulationOnly();
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
                app.StimLogsWritten = 0;
                app.setArtifactReadout();

                % Nothing is recorded in stimulation-only mode, so there is
                % nothing for either viewer to show and no live plot for the
                % controller to feed -- opening them would put up two empty
                % windows that never fill. Run progress is reported in the
                % Run panel instead (see setRunProgress).
                if app.StimOnlyRun
                    c.setLivePlot(mabr.ui.LivePlot.empty);
                    app.setRunReadout();
                    % The one mode where a viewer opens by itself here: nothing
                    % is recorded, so neither acquisition window has anything
                    % to fill with, but the plan still walks itself run by run
                    % and that is exactly what the progress window shows.
                    app.onProgress();
                    figure(app.UIFigure);      % the main window keeps focus
                else
                    app.openViewers();
                    c.setLivePlot(app.liveView());
                    % Clear whatever the last run left here -- a preceding
                    % stimulation-only schedule leaves run progress and "no
                    % recording" in place, which would be a lie until the
                    % first live tick overwrites them.
                    app.SweepLabel.Text = 'Sweeps: 0';
                    app.CorrLabel.Text  = 'r = —';
                end

                s = c.Schedule.summary();
                kind = 'schedule';
                if preview
                    kind = 'preview (nothing will be saved)';
                elseif app.StimOnlyRun
                    % Say what IS written, since "no recording" invites the
                    % assumption that nothing is -- one .stimlog per run, or
                    % none at all with no output folder set, which is a
                    % session that leaves no record of itself whatsoever.
                    if isempty(c.Session.OutputPath)
                        kind = 'stimulation (no recording, and no output folder — nothing will be saved)';
                    else
                        kind = 'stimulation (no recording; each run saves its sequence to a .stimlog file)';
                    end
                end
                app.setStatus(sprintf('Starting %s (%d runs, %d presentations, ~%s)…', ...
                    kind,s.numRuns,s.presentations,durationText(s.duration)));
                % Last, so an open monitor starts its clock and its tally on
                % the plan that is actually about to run rather than the one
                % the previous Start left behind.
                app.bindProgress();
                % These settings have now been used to acquire with, which is
                % the point at which they are worth reopening on -- and saving
                % them here rather than only in delete() is what makes the
                % recall survive a MATLAB that never gets to close cleanly.
                app.saveLastSession();
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
        % Viewers open at Start/Preview rather than with the app: there is
        % nothing to watch until a schedule is in flight, and launching into
        % three windows costs the user two closes before they can even pick a
        % subject. WHICH of them open is the user's (mabr.ViewPolicy, edited
        % from Settings > Windows to open at Start) -- the live view and the
        % trace organizer by default, which is what MABR always did, and any
        % of the six for a rig that works another way. The toolbar buttons
        % still open every one of them on demand at any time, and each
        % remembers where it was last left (mabr.ui.WindowPos).
        function n = openViewers(app)
            % Called from onStart. Only a viewer whose *window* is absent is
            % opened -- one already up is left exactly as the user arranged it,
            % and deliberately not raised over whatever is in front of it, so
            % this is safe to call at every Start. Returns how many were
            % opened, which is what decides whether focus has to be taken back.
            n = 0;
            % The organizer additionally needs the transfer preference:
            % nothing would ever arrive in one opened with it off, and a
            % window that stays empty for a whole session is worse than one
            % the user opened deliberately (see traceTransferEnabled).
            if app.Views.opens('TraceOrganizer') && app.traceTransferEnabled() ...
                    && (isempty(app.TraceOrg) || ~isvalid(app.TraceOrg) ...
                        || ~app.TraceOrg.isvalidView())
                app.onTraceOrg();   n = n + 1;
            end
            if app.Views.opens('LivePlot') && (isempty(app.LivePlot) || ~isvalid(app.LivePlot))
                app.onShowLive();   n = n + 1;
            end
            % One analysis window, and only when none is up: the window is
            % deliberately not a singleton, but opening a NEW one at every
            % Start would stack a session's worth of them up.
            app.pruneMetricPlots();
            if app.Views.opens('Analysis') && isempty(app.MetricPlots)
                app.onMetricPlot();  n = n + 1;
            end
            if app.Views.opens('StimulusViewer') && (isempty(app.StimViewer) ...
                    || ~isvalid(app.StimViewer) || ~app.StimViewer.isvalidView())
                app.onStimViewer();  n = n + 1;
            end
            if app.Views.opens('ProgressMonitor') && (isempty(app.ProgressMon) ...
                    || ~isvalid(app.ProgressMon))
                app.onProgress();    n = n + 1;
            end
            if app.Views.opens('Notes') && ~isempty(app.NotesView) ...
                    && isvalid(app.NotesView) && ~app.NotesView.isopen()
                app.NotesView.popOut();   n = n + 1;
            end
            if n > 0
                figure(app.UIFigure);   % the main window keeps focus
            end
        end

        function lp = liveView(app)
            % The live view to hand the controller: the one that is open, or
            % nothing. Empty is a supported answer (it is what a
            % stimulation-only run passes), and it is now also what a rig that
            % has switched the live view off at Start passes -- the controller
            % simply has nowhere to draw, which costs it a plot and nothing
            % else.
            if isempty(app.LivePlot) || ~isvalid(app.LivePlot)
                lp = mabr.ui.LivePlot.empty;
            else
                lp = app.LivePlot;
            end
        end

        function onShowLive(app)
            if isempty(app.LivePlot) || ~isvalid(app.LivePlot)
                app.LivePlot = mabr.ui.LivePlot();
                f = app.LivePlot.Figure;
                % A minimum size, because the live view is now two rows of
                % axes plus a control strip: a position remembered from the
                % single-axes days would reopen it too short to read, and the
                % strip -- which has since gained the Group menu -- too narrow
                % to show its right-hand end.
                mabr.ui.WindowPos.restore(f,'LivePlot', ...
                    app.defaultViewerPos('LivePlot'),[740 440]);
                % Closing disposes the viewer outright: it holds no state worth
                % keeping, and that keeps the isvalid() check above honest.
                f.CloseRequestFcn = @(~,~) app.closeLive();
                % The live view offers "Analysis…" but knows nothing about
                % controllers or how many windows are open; the App does, so
                % the button is pointed straight at the same handler the
                % toolbar button uses.
                app.LivePlot.NewAnalysisFcn = @() app.onMetricPlot();
            end
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.Controller.setLivePlot(app.LivePlot);
            end
            figure(app.LivePlot.Figure);
        end

        % --- Online analysis windows ----------------------------------------
        % Not a singleton, on purpose (see mabr.ui.MetricPlot): one metric per
        % window, so a second question is a second window rather than a mode
        % switch that loses the first answer. The App keeps the array only to
        % re-point them at a rebuilt controller and to close them with itself.
        function mp = onMetricPlot(app)
            app.pruneMetricPlots();
            c = app.Controller;
            if isempty(c) || ~isvalid(c), c = mabr.ui.AcqController.empty; end
            mp = mabr.ui.MetricPlot(c);
            f  = mp.Figure;
            % Every window opens from the remembered position, cascaded past
            % whatever is already up so a second one does not land exactly on
            % the first.
            mabr.ui.WindowPos.restore(f,'MetricPlot', ...
                app.defaultViewerPos('MetricPlot'),[620 420]);
            step = 28*numel(app.MetricPlots);
            f.Position(1:2) = f.Position(1:2) + [step -step];
            % ...and back onto the display, so a long cascade cannot walk a
            % window off the bottom-right corner of the screen.
            f.Position = mabr.ui.WindowPos.clampToScreen(f.Position);
            f.CloseRequestFcn = @(~,~) app.closeMetricPlot(mp);

            if isempty(app.MetricPlots)
                app.MetricPlots = mp;
            else
                app.MetricPlots(end+1) = mp;
            end
            if isempty(app.Controller) || ~isvalid(app.Controller)
                app.setStatus(['Online analysis opened — it fills in once a ' ...
                    'schedule is running.']);
            end
        end

        function closeMetricPlot(app,mp)
            % Remember the position only when this is the LAST one open:
            % every other window sits at a cascade offset, and storing one of
            % those would walk the remembered origin across the screen a
            % little further every session.
            app.pruneMetricPlots();
            if numel(app.MetricPlots) <= 1
                try, mabr.ui.WindowPos.remember(mp.Figure,'MetricPlot'); end %#ok<TRYNC>
            end
            delete(mp);
            app.pruneMetricPlots();
        end

        function pruneMetricPlots(app)
            if isempty(app.MetricPlots), return; end
            app.MetricPlots = app.MetricPlots(isvalid(app.MetricPlots));
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
            % With the transfer preference off the organizer is opened EMPTY
            % and stays that way: the backfill is as much a transfer as the
            % live one, and the reason to open it by hand in that mode is to
            % load a .torg into it.
            if isempty(app.TraceOrg) || ~isvalid(app.TraceOrg)
                app.TraceOrg = mabr.ui.TraceOrganizer();
                if app.traceTransferEnabled() && ~isempty(app.Controller) ...
                        && isvalid(app.Controller)
                    for i = 1:app.Controller.Session.NumBlocks
                        app.TraceOrg.addBlock(app.Controller.Session.Blocks(i));
                    end
                end
            end
            app.bindTraceOrg();
            % Unconditionally, and whether or not a controller exists yet: the
            % session's notebook is the App's, so an organizer opened before
            % Start shows the same log as one opened after. A no-op when it is
            % already on this store.
            app.TraceOrg.useNotes(app.Notes);
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

        function onProgress(app)
            % The schedule's progress, in its own window. On demand rather than
            % at Start like the acquisition pair -- it answers a question the
            % operator asks occasionally, not one they watch continuously --
            % with the one exception onStart makes for stimulation-only runs,
            % where it is the only window with anything in it.
            isNewWindow = isempty(app.ProgressMon) || ~isvalid(app.ProgressMon);
            if isNewWindow
                app.ProgressMon = mabr.ui.ProgressMonitor();
                f = app.ProgressMon.Figure;
                mabr.ui.WindowPos.restore(f,'ProgressMonitor', ...
                    app.defaultViewerPos('ProgressMonitor'),[420 0]);
                % The remembered SPOT is the user's; the HEIGHT belongs to the
                % view, which is why there is no minimum here and why the
                % monitor is asked to size itself afterwards -- a remembered
                % heat-map height would otherwise reopen the default (plotless)
                % view as a tall window with nothing in the middle of it.
                app.ProgressMon.fitToView();
                f.CloseRequestFcn = @(~,~) app.closeProgress();
            end
            app.bindProgress();
            figure(app.ProgressMon.Figure);
        end

        function bindProgress(app)
            % Point an open monitor at whatever is current: the controller when
            % there is one (it carries the live half of the tally), otherwise
            % the plan alone, so the window fills in before Start as well as
            % during a run. Safe to call at any time, and a no-op with no
            % window open.
            if isempty(app.ProgressMon) || ~isvalid(app.ProgressMon), return; end
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.ProgressMon.listenTo(app.Controller);
            else
                app.ProgressMon.attach([],[]);
            end
        end

        function closeProgress(app)
            mabr.ui.WindowPos.remember(app.ProgressMon.Figure,'ProgressMonitor');
            delete(app.ProgressMon);
        end

        function rememberViewerPositions(app)
            % Analysis windows cascade past one another, so only a lone one is
            % worth storing -- see closeMetricPlot for why remembering a
            % cascaded position walks the origin across the screen.
            app.pruneMetricPlots();
            if isscalar(app.MetricPlots)
                try, mabr.ui.WindowPos.remember(app.MetricPlots(1).Figure,'MetricPlot'); end %#ok<TRYNC>
            end
            try, mabr.ui.WindowPos.remember(app.LivePlot.Figure,'LivePlot'); end %#ok<TRYNC>
            try, mabr.ui.WindowPos.remember(app.TraceOrg.Figure,'TraceOrganizer'); end %#ok<TRYNC>
            try, mabr.ui.WindowPos.remember(app.StimViewer.Figure,'StimulusViewer'); end %#ok<TRYNC>
            try, mabr.ui.WindowPos.remember(app.ProgressMon.Figure,'ProgressMonitor'); end %#ok<TRYNC>
        end

        function applyWindowPositions(app,s)
            % Restore a saved layout: into the prefs, so windows not open yet
            % come up in the right place, and onto the windows that ARE open,
            % because the point of restoring a layout is watching it happen
            % rather than being told it will apply next time. Guarded per
            % window -- a monitor that has since been unplugged is
            % mabr.ui.WindowPos.place's problem to clamp, and a window this
            % MABR does not have is simply not there to move.
            n = mabr.ui.WindowPos.applyAll(s);
            if n == 0, return; end
            mabr.ui.WindowPos.place(app.UIFigure,'MABR');
            placeIf(viewerFigure(app.LivePlot),   'LivePlot');
            placeIf(viewerFigure(app.TraceOrg),   'TraceOrganizer');
            placeIf(viewerFigure(app.StimViewer), 'StimulusViewer');
            placeIf(viewerFigure(app.ProgressMon),'ProgressMonitor');
            app.pruneMetricPlots();
            if isscalar(app.MetricPlots)
                % Only a lone one, for the same reason only a lone one is
                % remembered: the others sit at cascade offsets and moving
                % them all onto one spot would stack them.
                placeIf(viewerFigure(app.MetricPlots(1)),'MetricPlot');
            end

            function placeIf(f,name)
                if isempty(f) || ~isgraphics(f), return; end
                try
                    mabr.ui.WindowPos.place(f,name);
                catch me
                    mabr.log.vprintf(2,'App: could not place "%s" (%s).',name,me.message);
                end
            end
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
                case 'MetricPlot'
                    % Below the organizer's column on first run: the two
                    % acquisition viewers own the top of the screen during a
                    % run, and an analysis window is watched between blocks
                    % rather than sweep by sweep.
                    pos = [a(1)+a(3)+gap+40, max(60,a(2)-60), 620, 460];
                case 'StimulusViewer'
                    % On demand and transient, so it cascades off the main
                    % window rather than claiming a slot in the run layout.
                    pos = [a(1)+40, a(2)-40, 820, 500];
                case 'ProgressMonitor'
                    % Cascades off the main window rather than claiming a slot
                    % in the run layout: the two acquisition viewers already
                    % own the space to the right, and this one is small, opened
                    % on demand, and usually dragged somewhere deliberate (a
                    % second monitor, a corner) -- which is then remembered.
                    % The height here is only a placeholder: fitToView sets it
                    % from the view the window actually opens in.
                    pos = [a(1)+60, a(2)-60, 520, 500];
                otherwise   % live plot, top-aligned with the main window
                    % Tall enough for the latest sweep AND the per-stimulus
                    % means stacked beneath it (the old 280 px only ever held
                    % one axes), and wide enough for the whole control strip.
                    pos = [a(1)+a(3)+gap+640+gap, a(2)+a(4)-580, 780, 580];
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
            % A preview -- and a stimulation-only run -- is indistinguishable
            % from a real one everywhere else, so the panel title carries the
            % warning for as long as one is in flight, and drops it once the
            % schedule settles.
            app.setRunTitle((app.Previewing || app.StimOnlyRun || app.TestRun) && ~isTerminal(e.State));
            % Stimulation only runs no live timer, so onMetrics never fires and
            % these two readouts would otherwise sit frozen on whatever the
            % previous run left in them. Run progress is the one thing that
            % moves, and every state transition is where it moves.
            if app.StimOnlyRun, app.setRunReadout(); end
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
            % One .abr per condition from a recorded run, or one .stimlog per
            % run from a stimulation-only one -- the event means "a file was
            % written" and the extension says which.
            [~,fn,ext] = fileparts(e.Info.file);
            if strcmpi(ext,'.stimlog')
                app.StimLogsWritten = app.StimLogsWritten + 1;
                app.setStatus(['Saved stimulation sequence ' fn ext]);
            else
                app.setStatus(['Saved ' fn ext]);
            end
        end

        function onAlignment(app,e)
            % Every recorded run reports whether its sweeps landed where the
            % plan put them (mabr.ui.AcqController.alignmentCheck). What
            % reaches the status line depends on the answer, not the mode:
            %
            %   misaligned  always said, whatever mode produced it -- the
            %               sweeps are not the presentations they are
            %               labelled with, and that is not a detail to leave
            %               in a log file (where it also goes, in red)
            %   aligned     said in Test Mode only. That is the mode the user
            %               entered in order to be told this, and on a rig the
            %               same line every run would be noise the eye stops
            %               reading -- which is exactly how a run that DOES
            %               say something goes unnoticed.
            R = e.Info.report;
            if ~R.Aligned
                app.setStatus(['Alignment: ' R.Summary]);
            elseif app.TestRun
                app.setStatus(['Test Mode — ' R.Summary]);
            end
        end

        function onScheduleComplete(app)
            if app.StimOnlyRun
                % "Nothing was recorded" is the whole point of the mode, but it
                % must not read as "nothing was saved": the sequence that was
                % played is written, and where it went is what the user needs
                % to know now.
                if app.StimLogsWritten > 0
                    app.setStatus(sprintf(['Stimulation complete — nothing recorded; ' ...
                        '%d stimulation log(s) written to %s.'], ...
                        app.StimLogsWritten,app.OutputField.Value));
                elseif app.Previewing
                    % Preview withholds the output folder, so it withholds the
                    % stimulation log with it -- the mode's only output.
                    app.setStatus(['Stimulation preview complete — nothing was ' ...
                        'recorded, and no stimulation log was written.']);
                else
                    app.setStatus(['Stimulation complete — nothing was recorded, and ' ...
                        'no stimulation log was written (no output folder set).']);
                end
            elseif app.TestRun
                % The one thing worth saying at the end of a Test Mode
                % schedule is what the files are, because nothing about them
                % says it: they are ordinary .abr files holding the stimulus
                % that was played, not a recording of anything.
                if app.Previewing
                    app.setStatus(['Test Mode complete — alignment verified; ' ...
                        'no files were written.']);
                else
                    app.setStatus(['Test Mode complete — the .abr files hold the ' ...
                        'stimulus, not a recording. See Help ▸ About Test Mode.']);
                end
            elseif app.Previewing
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
                 app.CalMenuItem, app.ComputeMenuItem, app.TestMenuItem, ...
                 app.LoadConfigMenuItem, ...
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
            % killed them on the way in and only this puts them back. Routed
            % through syncAcquisitionEnables so a stimulation-only run does not
            % get them back at all: there is nothing recorded for either to
            % apply to (it re-derives the Advance pair for the same reason).
            app.syncAcquisitionEnables();
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

        function setRunTitle(app,banner)
            % `banner` is true while a run that needs one is in flight. Which
            % banner is decided here, not by the caller, in order of how
            % strong a statement each makes about what the data are: Test Mode
            % (they are the stimulus), then stimulation only (there are none),
            % then preview (there are, but they are not being kept).
            if banner && app.TestRun
                % Outranks both: a preview acquires real signal and merely
                % declines to write it, stimulation only records nothing at
                % all, and both leave the operator with either real data or
                % none. Test Mode leaves them with .abr files that look
                % exactly like data and hold the stimulus, which is the one
                % of the three that can be mistaken for an experiment.
                app.RunPanel.Title = 'Run — TEST MODE (recording the stimulus, not a subject)';
            elseif banner && app.StimOnlyRun
                app.RunPanel.Title = 'Run — STIMULATION ONLY (no recording)';
            elseif banner
                app.RunPanel.Title = 'Run — PREVIEW (nothing is saved)';
            else
                app.RunPanel.Title = 'Run';
            end
        end

        function setRunReadout(app)
            % The Sweeps / r readouts in the Run panel, repurposed for a
            % stimulation-only schedule. There are no sweeps and no
            % correlation to report there -- nothing is recorded, and
            % AcqController never starts the live timer that normally writes
            % these -- so they carry run progress instead, which is the only
            % thing that moves.
            n = 0; r = 0;
            if ~isempty(app.Controller) && isvalid(app.Controller) && ...
                    ~isempty(app.Controller.Schedule)
                sch = app.Controller.Schedule;
                n   = sch.NumRuns;
                r   = sch.current();
                % current() is 0 once the plan is exhausted; the run that
                % finished it was the last one.
                if r == 0 && n > 0, r = n; end
            end
            app.SweepLabel.Text = sprintf('Run %d/%d',r,n);
            app.CorrLabel.Text  = 'no recording';
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
            % A bank rendered at a rate the device is no longer set to cannot
            % be played at all (mabr.stim.Schedule refuses to plan against it),
            % which outranks calibration: red, and named, since the number the
            % label otherwise shows would look perfectly healthy.
            if n > 0 && app.Stimuli.SampleRate ~= app.Config.DACSampleRate
                app.SourceLabel.Text = sprintf('%s · %s kHz ≠ device %s kHz', ...
                    app.SourceLabel.Text, ...
                    mabr.Config.rateText(app.Stimuli.SampleRate), ...
                    mabr.Config.rateText(app.Config.DACSampleRate));
                app.SourceLabel.FontColor = [0.8 0.2 0];
                return
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
        function c = builtinStrategies()
            % The canonical names of the five strategies Schedule plans
            % itself, in StrategyItems' order -- everything in
            % Schedule.Strategies except 'custom', which the dropdown carries
            % separately because its label names the resolved function.
            c = setdiff(mabr.stim.Schedule.Strategies,{'custom'},'stable');
        end

        function tf = isMabrWindow(f)
            % Is this figure one of MABR's? Every window the toolbox opens
            % names itself 'MABR ...' or carries a 'MABR...' Tag, and the
            % main window is deliberately NOT one of them here -- windows()
            % appends it by handle so it always comes last.
            tf = false;
            if ~isgraphics(f), return; end
            if strcmp(get(f,'Tag'),mabr.ui.App.InstanceTag), return; end
            tf = startsWith(get(f,'Tag'),'MABR') || startsWith(get(f,'Name'),'MABR');
        end

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
                case 'metrics'   % three rising points on axes: a metric vs a parameter
                    rows = {'................'
                            '.X..............'
                            '.X..........XX..'
                            '.X.........X..X.'
                            '.X..........XX..'
                            '.X......XX......'
                            '.X.....X..X.....'
                            '.X......XX......'
                            '.X..XX..........'
                            '.X.X..X.........'
                            '.X..XX..........'
                            '.X..............'
                            '.XXXXXXXXXXXXXX.'
                            '................'
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
                case 'progress'  % three bars of a progress chart, part-filled
                    rows = {'................'
                            '................'
                            '..XXXXXXXXXX....'
                            '..XXXXXX...X....'
                            '..XXXXXXXXXX....'
                            '................'
                            '..XXXXXXXXXXXX..'
                            '..XXXX......X...'
                            '..XXXXXXXXXXXX..'
                            '................'
                            '..XXXXXXXX......'
                            '..XX.....X......'
                            '..XXXXXXXX......'
                            '................'
                            '................'
                            '................'};
                case 'front'     % three cascaded windows, the front one solid
                    rows = {'................'
                            '..XXXXXXXXXX....'
                            '..X........X....'
                            '..X.XXXXXXXXXX..'
                            '..X.X...........'
                            '..X.X.XXXXXXXXXX'
                            '..X.X.XXXXXXXXXX'
                            '..X.X.X........X'
                            '..XXX.X........X'
                            '....X.X........X'
                            '....X.X........X'
                            '......X........X'
                            '......X........X'
                            '......XXXXXXXXXX'
                            '................'
                            '................'};
                case 'pin'       % pushpin: keep window on top
                    rows = {'................'
                            '.......XXXX....'
                            '......XXXXXX...'
                            '......XXXXXX...'
                            '......XXXXXX...'
                            '.......XXXX....'
                            '........XX.....'
                            '........XX.....'
                            '........XX.....'
                            '........XX.....'
                            '........XX.....'
                            '.......XXXX....'
                            '................'
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

function figs = addFig(figs,h)
% Append a figure handle to the list, skipping anything that is not a live
% figure and anything already in it -- the two collection passes in
% App.windows overlap by design (a viewer the App holds is also found by the
% Tag/Name sweep), and raising one twice would fight the ordering.
if isempty(h) || ~isscalar(h), return; end
if ~isa(h,'matlab.ui.Figure') || ~isgraphics(h), return; end
if any(figs == h), return; end
figs(end+1) = h;
end

function f = viewerFigure(obj,prop)
% The window a viewer object is showing, or [] when it has none: never
% built, already closed, or -- LivePlot and ProgressMonitor both support it
% -- embedded in somebody else's container rather than owning a figure.
if nargin < 2, prop = 'Figure'; end
f = [];
if isempty(obj) || ~isscalar(obj) || ~isvalid(obj) || ~isprop(obj,prop), return; end
try, f = obj.(prop); end %#ok<TRYNC>
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
tf = mabr.ui.ProgState.isTerminal(state);
end

function [c,txt] = stateAppearance(state)
% One mapping, shared with mabr.ui.ProgressMonitor's lamp.
[c,txt] = mabr.ui.ProgState.appearance(state);
end

function uialert_or_warn(msg)
warning('mabr:ui:App:toolboxes','%s',msg);
end
