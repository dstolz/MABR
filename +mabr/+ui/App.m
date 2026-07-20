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

    properties (SetAccess = private)
        Config
        Controller  mabr.ui.AcqController
        Source      mabr.stim.StimulusSource
        LivePlot    mabr.ui.LivePlot
        TraceOrg    mabr.ui.TraceOrganizer
        Listeners
    end

    % --- UI components ------------------------------------------------------
    properties (Access = private)
        UIFigure
        Grid
        SubjectField
        OutputField
        BrowseButton
        SourceLabel
        LoadButton
        TestButton
        TestingCheck
        AdvanceDrop
        TargetField
        CorrField
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
            app.UIFigure = uifigure('Name','MABR', 'Position',[100 100 460 560], ...
                'CloseRequestFcn',@(~,~) app.onClose());

            app.Grid = uigridlayout(app.UIFigure,[10 4]);
            app.Grid.RowHeight   = {30,30,30,25,30,30,'1x',30,40,26};
            app.Grid.ColumnWidth = {'fit','1x','1x','fit'};

            % Row 1: Subject
            app.addLabel('Subject ID',1,1);
            app.SubjectField = uieditfield(app.Grid,'text','Value','SUBJ_ID_001');
            app.SubjectField.Layout.Row = 1; app.SubjectField.Layout.Column = [2 4];

            % Row 2: Output folder
            app.addLabel('Output',2,1);
            app.OutputField = uieditfield(app.Grid,'text','Value',pwd);
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

            % Row 5: Advance criterion
            app.addLabel('Advance',5,1);
            app.AdvanceDrop = uidropdown(app.Grid, ...
                'Items',{'Number of Sweeps','Correlation Threshold'}, ...
                'ValueChangedFcn',@(~,~) app.onAdvanceChanged());
            app.AdvanceDrop.Layout.Row = 5; app.AdvanceDrop.Layout.Column = [2 4];

            % Row 6: Advance params
            app.addLabel('Target / Thr',6,1);
            app.TargetField = uieditfield(app.Grid,'numeric','Value',256,'Limits',[1 Inf],'RoundFractionalValues','on');
            app.TargetField.Layout.Row = 6; app.TargetField.Layout.Column = 2;
            app.CorrField = uieditfield(app.Grid,'numeric','Value',0.5,'Limits',[0 1],'Enable','off');
            app.CorrField.Layout.Row = 6; app.CorrField.Layout.Column = 3;

            % Row 7: live plot region host buttons (spacer row grows)
            app.LiveButton = uibutton(app.Grid,'Text','Show Live Plot','ButtonPushedFcn',@(~,~) app.onShowLive());
            app.LiveButton.Layout.Row = 7; app.LiveButton.Layout.Column = [1 2];
            app.TraceButton = uibutton(app.Grid,'Text','Trace Organizer','ButtonPushedFcn',@(~,~) app.onTraceOrg());
            app.TraceButton.Layout.Row = 7; app.TraceButton.Layout.Column = [3 4];

            % Row 8: metrics
            app.StateLamp = uilamp(app.Grid,'Color',[0.6 0.6 0.6]);
            app.StateLamp.Layout.Row = 8; app.StateLamp.Layout.Column = 1;
            app.StateLabel = uilabel(app.Grid,'Text','Idle','FontWeight','bold');
            app.StateLabel.Layout.Row = 8; app.StateLabel.Layout.Column = 2;
            app.SweepLabel = uilabel(app.Grid,'Text','Sweeps: 0');
            app.SweepLabel.Layout.Row = 8; app.SweepLabel.Layout.Column = 3;
            app.CorrLabel = uilabel(app.Grid,'Text','r = —');
            app.CorrLabel.Layout.Row = 8; app.CorrLabel.Layout.Column = 4;

            % Row 9: transport
            app.StartButton = uibutton(app.Grid,'Text','Start','BackgroundColor',[0.6 0.9 0.6], ...
                'ButtonPushedFcn',@(~,~) app.onStart());
            app.StartButton.Layout.Row = 9; app.StartButton.Layout.Column = 1;
            app.PauseButton = uibutton(app.Grid,'Text','Pause','Enable','off','ButtonPushedFcn',@(~,~) app.onPause());
            app.PauseButton.Layout.Row = 9; app.PauseButton.Layout.Column = 2;
            app.StopButton = uibutton(app.Grid,'Text','Stop Block','Enable','off','ButtonPushedFcn',@(~,~) app.onStopBlock());
            app.StopButton.Layout.Row = 9; app.StopButton.Layout.Column = 3;
            app.AbortButton = uibutton(app.Grid,'Text','Abort','Enable','off','BackgroundColor',[0.95 0.7 0.7], ...
                'ButtonPushedFcn',@(~,~) app.onAbort());
            app.AbortButton.Layout.Row = 9; app.AbortButton.Layout.Column = 4;

            % Row 10: status line
            app.StatusLabel = uilabel(app.Grid,'Text','Ready.','FontColor',[0.3 0.3 0.3]);
            app.StatusLabel.Layout.Row = 10; app.StatusLabel.Layout.Column = [1 4];
        end

        function addLabel(app,txt,r,c)
            h = uilabel(app.Grid,'Text',txt);
            h.Layout.Row = r; h.Layout.Column = c;
        end

        % --- Controller lifecycle ------------------------------------------
        function ensureController(app)
            testing = app.TestingCheck.Value;
            if ~isempty(app.Controller) && isvalid(app.Controller) ...
                    && app.Controller.Testing == testing
                return
            end
            % (Re)build for the selected mode.
            delete(app.Listeners);
            if ~isempty(app.Controller) && isvalid(app.Controller), delete(app.Controller); end

            app.setStatus('Starting acquisition worker…'); drawnow;
            app.Controller = mabr.ui.AcqController(app.Config,testing);
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
            if ischar(p) && ~isequal(p,0), app.OutputField.Value = p; end
            figure(app.UIFigure);
        end

        function onLoadSource(app)
            [fn,pn] = uigetfile({'*.mat','Stimulus blocks (*.mat)'},'Load stimulus source');
            figure(app.UIFigure);
            if isequal(fn,0), return; end
            try
                S = load(fullfile(pn,fn));
                blocks = pick_blocks(S);
                app.Source = mabr.stim.PrecomputedSource(blocks);
                app.setSourceLabel();
            catch me
                app.setStatus(['Load failed: ' me.message]);
            end
        end

        function onTestSource(app)
            app.Source = mabr.stim.demoSource(app.Config);
            app.setSourceLabel();
            app.setStatus('Loaded built-in test stimulus.');
        end

        function onAdvanceChanged(app)
            isCorr = strcmp(app.AdvanceDrop.Value,'Correlation Threshold');
            app.CorrField.Enable = onOff(isCorr);
        end

        function onStart(app)
            if isempty(app.Source)
                app.setStatus('Load a stimulus source first.'); return
            end
            try
                app.ensureController();
            catch me
                app.setStatus(['Worker error: ' me.message]); return
            end

            c = app.Controller;
            c.Session.Subject.ID = app.SubjectField.Value;
            c.Session.OutputPath = app.OutputField.Value;
            c.setSource(app.Source);

            if strcmp(app.AdvanceDrop.Value,'Correlation Threshold')
                c.AdvanceFcn = @mabr.stim.advance.corr_threshold;
            else
                c.AdvanceFcn = @mabr.stim.advance.num_sweeps;
            end
            p = c.AdvanceParams;
            p.targetSweeps  = app.TargetField.Value;
            p.corrThreshold = app.CorrField.Value;
            c.AdvanceParams = p;
            c.Queue.TargetSweeps = app.TargetField.Value;

            if isempty(app.LivePlot) || ~isvalid(app.LivePlot), app.onShowLive(); end
            c.setLivePlot(app.LivePlot);

            c.start();
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
        function transport(app,running)
            app.StartButton.Enable = onOff(~running);
            app.PauseButton.Enable = onOff(running);
            app.StopButton.Enable  = onOff(running);
            app.AbortButton.Enable = onOff(running);
            app.TestingCheck.Enable = onOff(~running);
            if ~running, app.PauseButton.Text = 'Pause'; end
        end

        function setSourceLabel(app)
            n = app.Source.numBlocks;
            app.SourceLabel.Text = sprintf('%d blocks',n);
            app.SourceLabel.FontColor = [0 0.5 0];
        end

        function setStatus(app,txt)
            app.StatusLabel.Text = txt;
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function blocks = pick_blocks(S)
% Extract a struct array of block specs from a loaded .mat.
fn = fieldnames(S);
blocks = [];
for i = 1:numel(fn)
    v = S.(fn{i});
    if isstruct(v) && isfield(v,'samples') && isfield(v,'SampleRate')
        blocks = v; return
    end
end
error('mabr:ui:App:noBlocks', ...
    'The .mat file has no struct array of block specs (needs samples + SampleRate).');
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
