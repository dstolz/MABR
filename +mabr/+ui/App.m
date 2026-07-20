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
        LivePlot    mabr.ui.LivePlot
        TraceOrg    mabr.ui.TraceOrganizer
        Listeners
    end

    % --- UI components ------------------------------------------------------
    properties (Access = private)
        UIFigure
        HelpMenu
        Toolbar
        Grid
        SubjectField
        OutputField
        BrowseButton
        SourceLabel
        LoadButton
        TestButton
        TestingCheck
        StrategyDrop
        RepsField
        RepsButton
        AdvanceDrop
        CorrField
        ISIField
        RateField
        OverlapLabel
        PlanLabel
        StartButton
        PauseButton
        StopButton
        AbortButton
        StateLamp
        StateLabel
        SweepLabel
        CorrLabel
        StatusLabel
    end

    methods
        function app = App()
            app.Config = mabr.Config;
            try
                app.Config.verifyToolboxes(true);
            catch me
                uialert_or_warn(me.message);
            end
            app.createComponents();
            app.syncAdvanceEnables();
            app.openViewers();
            if nargout == 0, clear app; end
        end

        function delete(app)
            % Whatever layout the user ended up with is the one they want back
            % next session, so capture it before anything is torn down.
            app.rememberViewerPositions();
            try, delete(app.Listeners);  end %#ok<TRYNC>
            try, delete(app.Controller); end %#ok<TRYNC>
            try, delete(app.TraceOrg);   end %#ok<TRYNC>
            try, delete(app.LivePlot);   end %#ok<TRYNC>
            try, delete(app.UIFigure);   end %#ok<TRYNC>
        end
    end

    % ===================================================================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','MABR', 'Position',[100 100 480 640], ...
                'CloseRequestFcn',@(~,~) app.onClose());

            app.HelpMenu = uimenu(app.UIFigure,'Text','&Help');
            uimenu(app.HelpMenu,'Text','MABR Wiki', ...
                'MenuSelectedFcn',@(~,~) app.openHelp());

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
            app.Grid.RowHeight   = {96,60,166,90,'1x',96,22};
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
            g = app.panelGrid('Stimulus',row,{24},{app.LabelWidth,'1x','fit','fit'});

            % The count doubles as the loaded/not-loaded indicator, so it sits
            % where a value would: in the field column, not tucked by a button.
            app.addLabel(g,'Bank',1,1);
            app.SourceLabel = uilabel(g,'Text','(none loaded)','FontColor',[0.6 0 0]);
            app.SourceLabel.Layout.Row = 1; app.SourceLabel.Layout.Column = 2;
            app.LoadButton = uibutton(g,'Text','Load .mat…', ...
                'Tooltip','Load a calibrated stimulus bank from your stimulus package.', ...
                'ButtonPushedFcn',@(~,~) app.onLoadSource());
            app.LoadButton.Layout.Row = 1; app.LoadButton.Layout.Column = 3;
            app.TestButton = uibutton(g,'Text','Test Stimulus', ...
                'Tooltip','Load the built-in tone-pip bank (testing only -- not calibrated).', ...
                'ButtonPushedFcn',@(~,~) app.onTestSource());
            app.TestButton.Layout.Row = 1; app.TestButton.Layout.Column = 4;
        end

        function buildPresentationPanel(app,row)
            g = app.panelGrid('Presentation',row,{24,24,24,16,18},{app.LabelWidth,'1x','1x'});

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

            % A full-width warning line directly under the fields that cause
            % it, rather than a clipped stub squeezed in beside them.
            app.OverlapLabel = uilabel(g,'Text','','FontColor',[0.8 0.2 0]);
            app.OverlapLabel.Layout.Row = 4; app.OverlapLabel.Layout.Column = [2 3];

            % Live consequence of everything above it: runs, presentations,
            % estimated duration. Kept in this panel because those are the
            % settings that change it.
            app.PlanLabel = uilabel(g,'Text','','FontColor',[0.3 0.3 0.3], ...
                'HorizontalAlignment','right');
            app.PlanLabel.Layout.Row = 5; app.PlanLabel.Layout.Column = [1 3];
        end

        function buildAcquisitionPanel(app,row)
            g = app.panelGrid('Acquisition',row,{24,24},{app.LabelWidth,'1x','1x'});

            app.TestingCheck = uicheckbox(g,'Text','Testing (loopback, no hardware)','Value',true, ...
                'Tooltip','Run the whole engine without an audio device. Changing this rebuilds the worker.');
            app.TestingCheck.Layout.Row = 1; app.TestingCheck.Layout.Column = [2 3];

            % Early stop only applies to a run holding one stimulus, so this is
            % disabled for intermixed strategies (see syncAdvanceEnables).
            app.addLabel(g,'Advance',2,1);
            app.AdvanceDrop = uidropdown(g, ...
                'Items',{'All Repetitions','Correlation Threshold'}, ...
                'Tooltip','When a run ends: after every repetition, or once the response is reproducible enough.', ...
                'ValueChangedFcn',@(~,~) app.onAdvanceChanged());
            app.AdvanceDrop.Layout.Row = 2; app.AdvanceDrop.Layout.Column = 2;
            % The threshold field is captioned by its own display format --
            % as a bare "0.50" beside a dropdown it read as an orphan.
            app.CorrField = uieditfield(g,'numeric','Value',0.5,'Limits',[0 1], ...
                'ValueDisplayFormat','stop at r ≥ %.2f','Enable','off', ...
                'Tooltip','Correlation the running average must reach for the run to stop early.');
            app.CorrField.Layout.Row = 2; app.CorrField.Layout.Column = 3;
        end

        function buildRunPanel(app,row)
            g = app.panelGrid('Run',row,{22,32},{'1x','1x','1x','1x'});

            % Readout and transport share a panel: what the run is doing and
            % what you can do about it belong to the same glance.
            s = uigridlayout(g,[1 4]);
            s.Layout.Row = 1; s.Layout.Column = [1 4];
            % Fixed width for the state label rather than 'fit', so the sweep
            % count does not slide sideways as the state text changes length.
            s.ColumnWidth   = {18,118,'1x','fit'};
            s.Padding       = [0 0 0 0];
            s.ColumnSpacing = 8;
            app.StateLamp  = uilamp(s,'Color',[0.6 0.6 0.6]);
            app.StateLabel = uilabel(s,'Text','Idle','FontWeight','bold');
            app.SweepLabel = uilabel(s,'Text','Sweeps: 0');
            app.CorrLabel  = uilabel(s,'Text','r = —','HorizontalAlignment','right');

            app.StartButton = uibutton(g,'Text','Start','BackgroundColor',[0.6 0.9 0.6], ...
                'FontWeight','bold','ButtonPushedFcn',@(~,~) app.onStart());
            app.StartButton.Layout.Row = 2; app.StartButton.Layout.Column = 1;
            app.PauseButton = uibutton(g,'Text','Pause','Enable','off', ...
                'Tooltip','Suspend playback in place, keeping the audio device open.', ...
                'ButtonPushedFcn',@(~,~) app.onPause());
            app.PauseButton.Layout.Row = 2; app.PauseButton.Layout.Column = 2;
            app.StopButton = uibutton(g,'Text','Stop Run','Enable','off', ...
                'Tooltip','End the current run early and advance to the next.', ...
                'ButtonPushedFcn',@(~,~) app.onStopBlock());
            app.StopButton.Layout.Row = 2; app.StopButton.Layout.Column = 3;
            app.AbortButton = uibutton(g,'Text','Abort','Enable','off','BackgroundColor',[0.95 0.7 0.7], ...
                'Tooltip','Abandon the whole schedule. Data already recorded is still saved.', ...
                'ButtonPushedFcn',@(~,~) app.onAbort());
            app.AbortButton.Layout.Row = 2; app.AbortButton.Layout.Column = 4;
        end

        function buildToolbar(app)
            % The viewers are always open, so their entries here are "bring to
            % front" rather than "show" -- they reopen a window only if the
            % user closed one. Lettered glyphs (L/T/?) instead of pictograms:
            % there is no pictogram for "trace organizer" that reads better
            % than its initial at 16 px.
            ink  = [0.16 0.26 0.42];
            help = [0.35 0.35 0.35];

            app.Toolbar = uitoolbar(app.UIFigure);
            app.toolButton('L',ink, 'Live plot',       @() app.onShowLive());
            app.toolButton('T',ink, 'Trace organizer', @() app.onTraceOrg());
            app.toolButton('?',help,'Help (MABR wiki)',@() app.openHelp(),true);
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

        % --- Controller lifecycle ------------------------------------------
        function ensureController(app)
            testing = app.TestingCheck.Value;
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
            [fn,pn] = uigetfile({'*.mat','Stimulus definition (*.mat)'},'Load stimuli');
            figure(app.UIFigure);
            if isequal(fn,0), return; end
            try
                app.adoptStimuli(mabr.stim.StimulusSet.fromFile(fullfile(pn,fn),app.Config));
                app.setStatus(sprintf('Loaded %d stimuli from %s',app.Stimuli.numStimuli,fn));
            catch me
                app.setStatus(['Load failed: ' me.message]);
            end
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
            app.setSourceLabel();
            app.checkOverlap();
            app.refreshPlan();
        end

        function onAdvanceChanged(app)
            isCorr    = strcmp(app.AdvanceDrop.Value,'Correlation Threshold');
            canEarly  = ~mabr.stim.Schedule.strategyIntermixes(app.StrategyDrop.Value);
            app.CorrField.Enable = onOff(isCorr && canEarly);
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
            r = mabr.ui.RepetitionsDialog(app.Stimuli,app.Reps,app.ISIField.Value/1e3);
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

        function checkOverlap(app)
            % Warn when the longest stimulus does not fit inside the ISI, so
            % the next presentation would start before this one has finished.
            app.OverlapLabel.Text = '';
            if isempty(app.Stimuli) || app.Stimuli.numStimuli == 0, return; end
            stimMs = 1e3*app.Stimuli.maxDuration();
            if stimMs > app.ISIField.Value
                app.OverlapLabel.Text = sprintf('overlap! %.1f ms stim',stimMs);
                app.setStatus(sprintf(['Longest stimulus is %.2f ms but the ISI is only ' ...
                    '%.2f ms (%.2f Hz) — presentations will overlap and be summed. ' ...
                    'Lower the rate to %.2f Hz or below.'], ...
                    stimMs,app.ISIField.Value,app.RateField.Value,1e3/stimMs));
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
            sch.ISI         = app.ISIField.Value/1e3;      % ms -> s
            sch.build();
        end

        function onStart(app)
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
            app.setBusy('Starting…');

            try
                app.ensureController();

                app.setStatus('Configuring session…');
                app.rememberValue(app.SubjectField,'Subject');
                app.rememberValue(app.OutputField,'Output');
                app.checkOverlap();

                c = app.Controller;
                c.Session.Subject.ID = app.SubjectField.Value;
                c.Session.OutputPath = app.OutputField.Value;
                c.setStimuli(app.Stimuli);

                % The controller builds its own schedule in setStimuli; replace
                % it with the one the GUI has been previewing.
                c.Schedule.Strategy    = app.StrategyDrop.Value;
                c.Schedule.Repetitions = app.Reps;
                c.Schedule.ISI         = app.ISIField.Value/1e3;   % ms -> s
                c.Schedule.build();

                if strcmp(app.AdvanceDrop.Value,'Correlation Threshold')
                    c.AdvanceFcn = @mabr.stim.advance.corr_threshold;
                else
                    c.AdvanceFcn = @mabr.stim.advance.num_sweeps;
                end
                p = c.AdvanceParams;
                p.corrThreshold = app.CorrField.Value;
                c.AdvanceParams = p;

                if isempty(app.LivePlot) || ~isvalid(app.LivePlot), app.onShowLive(); end
                c.setLivePlot(app.LivePlot);

                s = c.Schedule.summary();
                app.setStatus(sprintf('Starting schedule (%d runs, %d presentations, ~%s)…', ...
                    s.numRuns,s.presentations,durationText(s.duration)));
                c.start();
            catch me
                app.transport(false);      % unlock so the user can fix and retry
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

        % --- Viewer windows -------------------------------------------------
        % Both viewers open with the app rather than on demand, so the toolbar
        % buttons raise an existing window and only build one the user has
        % closed. Each remembers where it was last left (mabr.ui.WindowPos).
        function openViewers(app)
            app.onTraceOrg();
            app.onShowLive();
            figure(app.UIFigure);       % the main window keeps focus
        end

        function onShowLive(app)
            if isempty(app.LivePlot) || ~isvalid(app.LivePlot)
                app.LivePlot = mabr.ui.LivePlot();
                f = app.LivePlot.Figure;
                mabr.ui.WindowPos.restore(f,'LivePlot',app.defaultViewerPos('LivePlot'));
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

        function rememberViewerPositions(app)
            try, mabr.ui.WindowPos.remember(app.LivePlot.Figure,'LivePlot'); end %#ok<TRYNC>
            try, mabr.ui.WindowPos.remember(app.TraceOrg.Figure,'TraceOrganizer'); end %#ok<TRYNC>
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
                otherwise   % live plot, top-aligned with the main window
                    pos = [a(1)+a(3)+gap+640+gap, a(2)+a(4)-280, 640, 280];
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
            switch e.State
                case {mabr.ui.ProgState.SchedComplete, mabr.ui.ProgState.Idle, mabr.ui.ProgState.Error}
                    app.transport(false);
            end
            drawnow limitrate
        end

        function onMetrics(app,e)
            app.SweepLabel.Text = sprintf('Sweeps: %d',e.Info.numSweeps);
            app.CorrLabel.Text  = sprintf('r = %.3f',e.Info.corr);
        end

        function onBlockSaved(app,e)
            [~,fn,ext] = fileparts(e.Info.file);
            app.setStatus(['Saved ' fn ext]);
        end

        function onScheduleComplete(app)
            app.setStatus('Schedule complete.');
            app.transport(false);
        end

        % --- UI helpers ----------------------------------------------------
        % Enable state has three modes, all driven from here so no callback
        % has to reason about individual components:
        %   busy    - startup/teardown in progress; everything is dead
        %   running - acquiring; only the transport controls and viewers live
        %   idle    - configurable; everything but the transport controls
        function h = configControls(app)
            % Settings that must not change once a run is under way.
            h = {app.SubjectField, app.OutputField, app.BrowseButton, ...
                 app.LoadButton, app.TestButton, app.TestingCheck, ...
                 app.StrategyDrop, app.RepsField, app.RepsButton, ...
                 app.AdvanceDrop, app.CorrField, ...
                 app.ISIField, app.RateField};
        end

        function h = allControls(app)
            h = [app.configControls, ...
                 {app.StartButton, app.PauseButton, app.StopButton, ...
                  app.AbortButton}];
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
            app.StartButton.Enable  = onOff(~running);
            app.PauseButton.Enable  = onOff(running);
            app.StopButton.Enable   = onOff(running);
            app.AbortButton.Enable  = onOff(running);
            % The toolbar is deliberately never disabled -- raising a viewer is
            % safe at any time, including while the engine is starting up.
            if ~running
                app.PauseButton.Text = 'Pause';
                app.syncAdvanceEnables();     % re-derives the Advance/Corr enables
            end
            drawnow limitrate
        end

        function setSourceLabel(app)
            n = app.Stimuli.numStimuli;
            app.SourceLabel.Text = sprintf('%d stimuli',n);
            app.SourceLabel.FontColor = [0 0.5 0];
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
            switch name
                case 'L'
                    rows = {'................'
                            '................'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXX..........'
                            '...XXXXXXXXXX...'
                            '...XXXXXXXXXX...'
                            '................'
                            '................'
                            '................'};
                case 'T'
                    rows = {'................'
                            '................'
                            '..XXXXXXXXXXXX..'
                            '..XXXXXXXXXXXX..'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '......XXX.......'
                            '................'
                            '................'
                            '................'};
                case '?'
                    rows = {'................'
                            '....XXXXXX......'
                            '...XX....XX.....'
                            '..XX......XX....'
                            '..XX......XX....'
                            '..........XX....'
                            '.........XX.....'
                            '......XXXX......'
                            '......XX........'
                            '......XX........'
                            '................'
                            '......XX........'
                            '......XX........'
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
