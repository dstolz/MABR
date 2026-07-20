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
        LiveButton
        TraceButton
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
            if nargout == 0, clear app; end
        end

        function delete(app)
            try, delete(app.Listeners);  end %#ok<TRYNC>
            try, delete(app.Controller); end %#ok<TRYNC>
            try, delete(app.TraceOrg);   end %#ok<TRYNC>
            try, delete(app.UIFigure);   end %#ok<TRYNC>
        end
    end

    % ===================================================================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','MABR', 'Position',[100 100 470 640], ...
                'CloseRequestFcn',@(~,~) app.onClose());

            app.HelpMenu = uimenu(app.UIFigure,'Text','&Help');
            uimenu(app.HelpMenu,'Text','MABR Wiki', ...
                'MenuSelectedFcn',@(~,~) web('https://github.com/dstolz/MABR/wiki','-browser'));

            app.Grid = uigridlayout(app.UIFigure,[13 4]);
            app.Grid.RowHeight   = {30,30,30,25,30,30,30,30,22,'1x',30,40,26};
            app.Grid.ColumnWidth = {'fit','1x','1x','fit'};

            % Row 1: Subject (editable dropdown of previously used IDs)
            app.addLabel('Subject ID',1,1);
            app.SubjectField = uidropdown(app.Grid,'Editable','on', ...
                'Items',app.loadHistory('Subject',{'SUBJ_ID_001'}));
            app.SubjectField.Value = app.SubjectField.Items{1};
            app.SubjectField.Layout.Row = 1; app.SubjectField.Layout.Column = [2 4];

            % Row 2: Output folder (editable dropdown of previously used paths)
            app.addLabel('Output',2,1);
            app.OutputField = uidropdown(app.Grid,'Editable','on', ...
                'Items',app.loadHistory('Output',{pwd}));
            app.OutputField.Value = app.OutputField.Items{1};
            app.OutputField.Layout.Row = 2; app.OutputField.Layout.Column = [2 3];
            app.BrowseButton = uibutton(app.Grid,'Text','Browse…','ButtonPushedFcn',@(~,~) app.onBrowse());
            app.BrowseButton.Layout.Row = 2; app.BrowseButton.Layout.Column = 4;

            % Row 3: Stimulus source
            app.addLabel('Stimulus',3,1);
            app.SourceLabel = uilabel(app.Grid,'Text','(none loaded)','FontColor',[0.6 0 0]);
            app.SourceLabel.Layout.Row = 3; app.SourceLabel.Layout.Column = 2;
            app.LoadButton = uibutton(app.Grid,'Text','Load .mat…','ButtonPushedFcn',@(~,~) app.onLoadSource());
            app.LoadButton.Layout.Row = 3; app.LoadButton.Layout.Column = 3;
            app.TestButton = uibutton(app.Grid,'Text','Test Stimulus','ButtonPushedFcn',@(~,~) app.onTestSource());
            app.TestButton.Layout.Row = 3; app.TestButton.Layout.Column = 4;

            % Row 4: Testing mode
            app.TestingCheck = uicheckbox(app.Grid,'Text','Testing (loopback, no hardware)','Value',true);
            app.TestingCheck.Layout.Row = 4; app.TestingCheck.Layout.Column = [1 4];

            % Row 5: how stimuli are combined across the bank
            app.addLabel('Strategy',5,1);
            app.StrategyDrop = uidropdown(app.Grid, ...
                'Items',mabr.ui.App.StrategyItems, ...
                'ItemsData',mabr.stim.Schedule.Strategies, ...
                'ValueChangedFcn',@(~,~) app.onStrategyChanged());
            app.StrategyDrop.Layout.Row = 5; app.StrategyDrop.Layout.Column = [2 4];

            % Row 6: repetitions per stimulus entry
            app.addLabel('Repetitions',6,1);
            app.RepsField = uieditfield(app.Grid,'numeric','Value',512, ...
                'Limits',[0 Inf],'RoundFractionalValues','on', ...
                'ValueChangedFcn',@(~,~) app.onRepsChanged());
            app.RepsField.Layout.Row = 6; app.RepsField.Layout.Column = 2;
            app.RepsButton = uibutton(app.Grid,'Text','Per stimulus…', ...
                'ButtonPushedFcn',@(~,~) app.onRepsDialog());
            app.RepsButton.Layout.Row = 6; app.RepsButton.Layout.Column = [3 4];

            % Row 7: inter-stimulus interval <-> presentation rate (linked)
            app.addLabel('ISI / Rate',7,1);
            app.ISIField = uieditfield(app.Grid,'numeric', ...
                'Value',1e3/mabr.ui.App.DefaultRateHz,'Limits',[eps Inf], ...
                'ValueDisplayFormat','%.2f ms', ...
                'ValueChangedFcn',@(~,~) app.onISIChanged());
            app.ISIField.Layout.Row = 7; app.ISIField.Layout.Column = 2;
            app.RateField = uieditfield(app.Grid,'numeric', ...
                'Value',mabr.ui.App.DefaultRateHz,'Limits',[eps Inf], ...
                'ValueDisplayFormat','%.2f Hz', ...
                'ValueChangedFcn',@(~,~) app.onRateChanged());
            app.RateField.Layout.Row = 7; app.RateField.Layout.Column = 3;
            app.OverlapLabel = uilabel(app.Grid,'Text','','FontColor',[0.8 0.2 0]);
            app.OverlapLabel.Layout.Row = 7; app.OverlapLabel.Layout.Column = 4;

            % Row 8: advance criterion. Early stop only applies to a run that
            % holds one stimulus, so this is disabled for intermixed strategies.
            app.addLabel('Advance',8,1);
            app.AdvanceDrop = uidropdown(app.Grid, ...
                'Items',{'All Repetitions','Correlation Threshold'}, ...
                'ValueChangedFcn',@(~,~) app.onAdvanceChanged());
            app.AdvanceDrop.Layout.Row = 8; app.AdvanceDrop.Layout.Column = [2 3];
            app.CorrField = uieditfield(app.Grid,'numeric','Value',0.5,'Limits',[0 1],'Enable','off');
            app.CorrField.Layout.Row = 8; app.CorrField.Layout.Column = 4;

            % Row 9: plan summary (runs / presentations / estimated duration)
            app.PlanLabel = uilabel(app.Grid,'Text','','FontColor',[0.3 0.3 0.3]);
            app.PlanLabel.Layout.Row = 9; app.PlanLabel.Layout.Column = [1 4];

            % Row 10: live plot region host buttons (spacer row grows)
            app.LiveButton = uibutton(app.Grid,'Text','Show Live Plot','ButtonPushedFcn',@(~,~) app.onShowLive());
            app.LiveButton.Layout.Row = 10; app.LiveButton.Layout.Column = [1 2];
            app.TraceButton = uibutton(app.Grid,'Text','Trace Organizer','ButtonPushedFcn',@(~,~) app.onTraceOrg());
            app.TraceButton.Layout.Row = 10; app.TraceButton.Layout.Column = [3 4];

            % Row 11: metrics
            app.StateLamp = uilamp(app.Grid,'Color',[0.6 0.6 0.6]);
            app.StateLamp.Layout.Row = 11; app.StateLamp.Layout.Column = 1;
            app.StateLabel = uilabel(app.Grid,'Text','Idle','FontWeight','bold');
            app.StateLabel.Layout.Row = 11; app.StateLabel.Layout.Column = 2;
            app.SweepLabel = uilabel(app.Grid,'Text','Sweeps: 0');
            app.SweepLabel.Layout.Row = 11; app.SweepLabel.Layout.Column = 3;
            app.CorrLabel = uilabel(app.Grid,'Text','r = —');
            app.CorrLabel.Layout.Row = 11; app.CorrLabel.Layout.Column = 4;

            % Row 12: transport
            app.StartButton = uibutton(app.Grid,'Text','Start','BackgroundColor',[0.6 0.9 0.6], ...
                'ButtonPushedFcn',@(~,~) app.onStart());
            app.StartButton.Layout.Row = 12; app.StartButton.Layout.Column = 1;
            app.PauseButton = uibutton(app.Grid,'Text','Pause','Enable','off','ButtonPushedFcn',@(~,~) app.onPause());
            app.PauseButton.Layout.Row = 12; app.PauseButton.Layout.Column = 2;
            app.StopButton = uibutton(app.Grid,'Text','Stop Run','Enable','off','ButtonPushedFcn',@(~,~) app.onStopBlock());
            app.StopButton.Layout.Row = 12; app.StopButton.Layout.Column = 3;
            app.AbortButton = uibutton(app.Grid,'Text','Abort','Enable','off','BackgroundColor',[0.95 0.7 0.7], ...
                'ButtonPushedFcn',@(~,~) app.onAbort());
            app.AbortButton.Layout.Row = 12; app.AbortButton.Layout.Column = 4;

            % Row 13: status line
            app.StatusLabel = uilabel(app.Grid,'Text','Ready.','FontColor',[0.3 0.3 0.3]);
            app.StatusLabel.Layout.Row = 13; app.StatusLabel.Layout.Column = [1 4];
        end

        function addLabel(app,txt,r,c)
            h = uilabel(app.Grid,'Text',txt);
            h.Layout.Row = r; h.Layout.Column = c;
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

        function onShowLive(app)
            if isempty(app.LivePlot) || ~isvalid(app.LivePlot)
                app.LivePlot = mabr.ui.LivePlot();
            end
            if ~isempty(app.Controller) && isvalid(app.Controller)
                app.Controller.setLivePlot(app.LivePlot);
            end
        end

        function onTraceOrg(app)
            if isempty(app.TraceOrg) || ~isvalid(app.TraceOrg)
                app.TraceOrg = mabr.ui.TraceOrganizer();
            end
            if ~isempty(app.Controller) && isvalid(app.Controller)
                % Rebuild from scratch: addBlock appends, so re-pressing the
                % button would otherwise duplicate every trace.
                app.TraceOrg.clear();
                for i = 1:app.Controller.Session.NumBlocks
                    app.TraceOrg.addBlock(app.Controller.Session.Blocks(i));
                end
            end
            app.TraceOrg.show();
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
                  app.AbortButton, app.LiveButton, app.TraceButton}];
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
            app.LiveButton.Enable   = 'on';   % viewers are safe at any time
            app.TraceButton.Enable  = 'on';
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
