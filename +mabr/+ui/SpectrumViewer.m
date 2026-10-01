classdef SpectrumViewer < handle
% mabr.ui.SpectrumViewer  The power spectrum of the raw input, live.
%
%   Electrical noise is the commonest reason an ABR will not average down, and
%   it is invisible in the averaged trace until it is too late: the display
%   filter hides most of it and the average is still mostly noise. What names
%   it is the spectrum of the RAW input -- mains at 50/60 Hz and its
%   harmonics, a switching supply at tens of kHz, a monitor's line rate -- and
%   what fixes it is watching that spectrum while cables are moved, grounds
%   are tied and equipment is switched off one item at a time. That is this
%   window.
%
%   It shows the Welch power spectral density of the newest few seconds the
%   rig recorded (mabr.compute.SpectrumEstimator), before any display filter
%   and referred to the electrodes through the amplifier gain, refreshed once
%   a second, with the numbers the hunt is conducted in beside it
%   (mabr.metrics.noise_summary): the total and in-band RMS, the mains line and
%   its harmonics, and the largest other line standing above the noise floor.
%
%   Where the samples come from is the host's business, through SourceFcn:
%   mabr.ui.App reads them from the acquisition ring buffer
%   (mabr.ui.AcqController.inputSamples) -- the run in progress while a
%   schedule is acquiring, or the INPUT MONITOR, which records with no
%   stimulus at all so the noise can be watched with the electrodes in place
%   and nothing else set up. The "Monitor input" button asks the host to start
%   and stop it (MonitorFcn); without one it is disabled.
%
%       sv = mabr.ui.SpectrumViewer('SourceFcn',@(n) ctrl.inputSamples(n));
%       sv.Mains = 50;            % the settings are public properties
%       sv.holdReference();       % grey copy to compare the next change against
%
%   SourceFcn(n) returns a struct with the newest (up to) n samples:
%   .Samples (raw, newest last), .Head (the block's sample the last one is),
%   .Seq (the block), .SampleRate, .Gain, .Source ('monitor'|'run'|'held'|
%   'none'), and optionally .Testing, .Monitoring, .CanMonitor and .Note --
%   mabr.ui.AcqController.inputSamples' shape. MonitorFcn(tf) starts (true) or
%   stops (false) the monitor and returns [ok,msg].
%
%   The display settings are remembered between sessions (pref MABR/
%   SpectrumViewer, written only from the controls -- never from a property
%   set by a script) and travel in a configuration file (displaySettings /
%   applySettings, mabr.ui.App's cfg.Spectrum).
%
%   See also mabr.compute.SpectrumEstimator, mabr.metrics.noise_summary,
%   mabr.ui.AcqController.startMonitor.
%
% Daniel Stolzberg (c) 2026

    properties
        % Hz between bins. Finer resolves a line from its neighbours and
        % costs a longer segment: 1 Hz is a second of input per segment.
        Resolution   (1,1) double = 1
        % Segments averaged. More is a steadier floor over more seconds.
        Averages     (1,1) double = 4
        % Mains frequency marked and measured: 0 (off), 50 or 60 Hz.
        Mains        (1,1) double = 60
        % The top of the frequency axis, Hz (Inf = Nyquist).
        MaxFrequency (1,1) double = 10000
        % 'db' (dB re 1 µV²/Hz) or 'asd' (µV/√Hz on a log axis).
        Scale        (1,:) char   = 'db'
        LogFrequency (1,1) logical = true
        % The band the in-band RMS figure covers, Hz: where an ABR lives.
        Band         (1,2) double = [100 3000]
        % The host's hooks; see the class help.
        SourceFcn  = []
        MonitorFcn = []
    end

    properties (SetAccess = private)
        Figure
        Input     = []     % the last struct SourceFcn returned
        Spectrum  = []     % .f .P (V^2/Hz) .info .Source of what is drawn
        Summary   = []     % mabr.metrics.noise_summary of it
        Reference = []     % a held spectrum: .f .P .Label, or []
        Frozen    (1,1) logical = false
        % What the window last had to say for itself that is not a number:
        % a monitor that would not start, and the like. Shown in the status
        % line until the next change of monitor state.
        Note      (1,:) char = ''
    end

    properties (Constant)
        Resolutions    = [0.5 1 2 5 10]
        AverageChoices = [1 2 4 8 16]
        MaxChoices     = [500 1000 3000 10000 30000 Inf]
        MainsChoices   = [0 50 60]
        Harmonics      = 10
        RefreshPeriod  = 1
        PrefGroup      = 'MABR'
        PrefKey        = 'SpectrumViewer'
    end

    properties (Access = private)
        Timer
        Estimator
        LastKey  = []
        Collecting = []        % info of an estimate still short of a segment
        Building (1,1) logical = true
        ErrorLogged (1,1) logical = false
        Ax
        Line
        RefLine
        MainsLines
        PeakMark
        Ctrl = struct()
        Status
        RMSText
        LineText
        % What was last written to each graphics property that a refresh
        % can leave unchanged (see put): writing a uiaxes scale, label or
        % limit marks it for another layout even when the value is the one
        % already there, and a uifigure component's property goes through
        % the component even to be read -- so the comparison is against this
        % record, never against the graphics.
        Written = struct()
    end

    methods
        function obj = SpectrumViewer(varargin)
            p = inputParser;
            p.addParameter('SourceFcn',[]);
            p.addParameter('MonitorFcn',[]);
            % false for a test that drives refresh() itself rather than on a
            % timer's schedule.
            p.addParameter('AutoRefresh',true);
            p.parse(varargin{:});
            obj.SourceFcn  = p.Results.SourceFcn;
            obj.MonitorFcn = p.Results.MonitorFcn;

            % The look the last window was left with, BEFORE the window is
            % built, so the controls are drawn from it rather than from the
            % class defaults and then changed.
            obj.applySettings(mabr.ui.SpectrumViewer.loadDefaults());
            obj.build();
            obj.Building = false;
            obj.syncControls();
            obj.refresh(true);

            if p.Results.AutoRefresh
                obj.Timer = timer('Tag','MABR_Spectrum', ...
                    'ExecutionMode','fixedSpacing','BusyMode','drop', ...
                    'Period',obj.RefreshPeriod,'TasksToExecute',Inf, ...
                    'TimerFcn',@(~,~) obj.onTick());
                start(obj.Timer);
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.Timer) && isvalid(obj.Timer)
                    stop(obj.Timer); delete(obj.Timer);
                end
            catch %#ok<CTCH>
            end
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Figure) && isgraphics(obj.Figure);
        end

        function show(obj)
            if obj.isvalidView(), figure(obj.Figure); end
        end

        % --- Settings -------------------------------------------------------
        function set.Resolution(obj,v)
            mabr.ui.SpectrumViewer.mustBeOneOf(v,mabr.ui.SpectrumViewer.Resolutions,'Resolution');
            obj.Resolution = v;
            obj.settingChanged('estimate');
        end

        function set.Averages(obj,v)
            mabr.ui.SpectrumViewer.mustBeOneOf(v,mabr.ui.SpectrumViewer.AverageChoices,'Averages');
            obj.Averages = v;
            obj.settingChanged('estimate');
        end

        function set.Mains(obj,v)
            mabr.ui.SpectrumViewer.mustBeOneOf(v,mabr.ui.SpectrumViewer.MainsChoices,'Mains');
            obj.Mains = v;
            obj.settingChanged('summary');
        end

        function set.MaxFrequency(obj,v)
            mabr.ui.SpectrumViewer.mustBeOneOf(v,mabr.ui.SpectrumViewer.MaxChoices,'MaxFrequency');
            obj.MaxFrequency = v;
            obj.settingChanged('summary');
        end

        function set.Scale(obj,v)
            v = lower(char(v));
            assert(any(strcmp(v,{'db','asd'})),'mabr:ui:SpectrumViewer:setting', ...
                'Scale must be ''db'' or ''asd''.');
            obj.Scale = v;
            obj.settingChanged('draw');
        end

        function set.LogFrequency(obj,v)
            obj.LogFrequency = logical(v);
            obj.settingChanged('draw');
        end

        function set.Band(obj,v)
            assert(isnumeric(v) && numel(v) == 2 && all(isfinite(v)) && all(v >= 0) ...
                && v(2) > v(1),'mabr:ui:SpectrumViewer:setting', ...
                'Band must be [lo hi] Hz with lo < hi.');
            obj.Band = double(v(:)');
            obj.settingChanged('summary');
        end

        function s = displaySettings(obj)
            s = struct('Resolution',obj.Resolution,'Averages',obj.Averages, ...
                'Mains',obj.Mains,'MaxFrequency',obj.MaxFrequency, ...
                'Scale',obj.Scale,'LogFrequency',obj.LogFrequency,'Band',obj.Band);
        end

        function applySettings(obj,s)
            % Inverse of displaySettings, forgiving field by field: a pref or
            % a configuration from another version restores whatever still
            % validates and leaves the rest as it is.
            if ~isstruct(s) || ~isscalar(s), return; end
            f = fieldnames(mabr.ui.SpectrumViewer.factoryDefaults());
            for i = 1:numel(f)
                if ~isfield(s,f{i}), continue; end
                try
                    obj.(f{i}) = s.(f{i});
                catch me
                    mabr.log.vprintf(2,'SpectrumViewer: ignoring %s (%s).',f{i},me.message);
                end
            end
        end

        function savePrefs(obj)
            % Written from the controls only (see the class help).
            mabr.ui.SpectrumViewer.saveDefaults(obj.displaySettings());
        end

        % --- Actions --------------------------------------------------------
        function refresh(obj,force)
            % Pull the newest input and redraw. force (default false) redraws
            % even when nothing new has arrived -- a setting changed.
            if nargin < 2, force = false; end
            if ~obj.isvalidView(), return; end
            S = obj.pull();
            obj.Input = S;
            obj.syncMonitorButton(S);

            if obj.Frozen && ~force
                obj.drawStatus();
                return
            end
            if isempty(S.Samples) || S.Head < 1
                if strcmp(S.Source,'none')
                    % Nothing to show is not the same as the last thing shown:
                    % a spectrum left up after the monitor has gone would read
                    % as live.
                    obj.Spectrum = []; obj.Summary = []; obj.LastKey = [];
                    obj.Collecting = [];
                    obj.draw();
                end
                obj.drawStatus();
                return
            end

            e   = obj.estimator(S.SampleRate);
            key = [S.Seq S.Head S.Gain];
            if ~force && isequal(key,obj.LastKey)
                obj.drawStatus();
                return
            end
            obj.LastKey = key;
            [f,P,info] = e.update(S.Samples,S.Head,S.Seq,S.Gain);
            if isempty(P)
                % A new block (a monitor lap, the next run) has not filled one
                % segment yet. The spectrum already up stays until it has.
                obj.Collecting = info;
                obj.drawStatus();
                return
            end
            obj.Collecting = [];
            obj.Spectrum = struct('f',f,'P',P,'info',info,'Source',S.Source);
            obj.summarize();
            obj.draw();
            obj.drawStatus();
        end

        function holdReference(obj,label)
            % Keep what is on screen as a grey reference, to hold the next
            % change -- a cable moved, a supply switched off -- against.
            if isempty(obj.Spectrum), return; end
            if nargin < 2 || isempty(label)
                label = char(datetime('now','Format','HH:mm:ss'));
            end
            obj.Reference = struct('f',obj.Spectrum.f,'P',obj.Spectrum.P, ...
                'Label',label,'Summary',obj.Summary);
            obj.draw();
            obj.drawStatus();
        end

        function clearReference(obj)
            obj.Reference = [];
            obj.draw();
            obj.drawStatus();
        end

        function setFrozen(obj,tf)
            % Stop following the input (the spectrum on screen stays), or
            % pick it up again.
            obj.Frozen = logical(tf);
            if isfield(obj.Ctrl,'freeze') && isvalid(obj.Ctrl.freeze)
                obj.Ctrl.freeze.Value = obj.Frozen;
            end
            if ~obj.Frozen, obj.refresh(true); else, obj.drawStatus(); end
        end

        function exportCSV(obj,file)
            % The spectrum on screen as frequency / PSD / ASD columns, with a
            % header saying where it came from -- what to attach when asking
            % somebody else what a line is.
            assert(~isempty(obj.Spectrum),'mabr:ui:SpectrumViewer:nothing', ...
                'There is no spectrum to export yet.');
            T = table(obj.Spectrum.f,obj.Spectrum.P,sqrt(obj.Spectrum.P), ...
                'VariableNames',{'Frequency_Hz','PSD_V2_per_Hz','ASD_V_per_rtHz'});
            writetable(T,file);
        end

        function setNote(obj,txt)
            obj.Note = char(txt);
            obj.drawStatus();
        end
    end

    % =====================================================================
    methods (Static)
        function d = factoryDefaults()
            d = struct('Resolution',1,'Averages',4,'Mains',60, ...
                'MaxFrequency',10000,'Scale','db','LogFrequency',true, ...
                'Band',[100 3000]);
        end

        function d = loadDefaults()
            % What a NEW window opens with: the look the last one was left
            % with, forgiving of a pref from another version (applySettings
            % validates each value on the way in).
            d = mabr.ui.SpectrumViewer.factoryDefaults();
            try
                g = mabr.ui.SpectrumViewer.PrefGroup;
                k = mabr.ui.SpectrumViewer.PrefKey;
                if ~ispref(g,k), return; end
                p = getpref(g,k);
                if ~isstruct(p) || ~isscalar(p), return; end
                f = fieldnames(d);
                for i = 1:numel(f)
                    if isfield(p,f{i}), d.(f{i}) = p.(f{i}); end
                end
            catch %#ok<CTCH>
            end
        end

        function saveDefaults(d)
            % Guarded: a rig with no writable prefs must not lose a window
            % over a look it cannot store.
            try
                setpref(mabr.ui.SpectrumViewer.PrefGroup,mabr.ui.SpectrumViewer.PrefKey,d);
            catch %#ok<CTCH>
            end
        end

        function S = noInput(note)
            % The shape SourceFcn returns, holding nothing.
            if nargin < 1, note = ''; end
            S = struct('Samples',zeros(0,1,'single'),'Head',0,'Seq',NaN, ...
                'SampleRate',NaN,'Gain',1,'Source','none','Testing',false, ...
                'Monitoring',false,'CanMonitor',false,'Note',note);
        end
    end

    methods (Static, Access = private)
        function mustBeOneOf(v,choices,name)
            ok = isnumeric(v) && isscalar(v) && any(v == choices);
            if ~ok
                error('mabr:ui:SpectrumViewer:setting','%s must be one of %s.', ...
                    name,mat2str(choices));
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            obj.Figure = uifigure('Name','MABR Input Spectrum', ...
                'Position',[120 120 780 540],'Tag','MABR_SPECTRUM');
            obj.Figure.CloseRequestFcn = @(~,~) delete(obj);

            g = uigridlayout(obj.Figure,[4 1]);
            g.RowHeight   = {'1x',62,26,26};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 4;

            obj.Ax = uiaxes(g);
            mabr.ui.hideAxesToolbar(obj.Ax);
            grid(obj.Ax,'on'); box(obj.Ax,'on');
            hold(obj.Ax,'on');
            obj.RefLine = plot(obj.Ax,NaN,NaN,'Color',[0.62 0.62 0.62],'LineWidth',1);
            obj.Line    = plot(obj.Ax,NaN,NaN,'Color',[0.10 0.25 0.55],'LineWidth',1);
            obj.MainsLines = gobjects(1,obj.Harmonics);
            for k = 1:obj.Harmonics
                obj.MainsLines(k) = xline(obj.Ax,60*k,':','Color',[0.80 0.25 0.20], ...
                    'LineWidth',1,'Visible','off','HandleVisibility','off');
            end
            obj.PeakMark = plot(obj.Ax,NaN,NaN,'v','MarkerSize',8, ...
                'MarkerFaceColor',[0.90 0.55 0.10],'MarkerEdgeColor',[0.55 0.30 0]);
            hold(obj.Ax,'off');
            xlabel(obj.Ax,'Frequency (Hz)');

            cm = uicontextmenu(obj.Figure);
            uimenu(cm,'Text','Export spectrum (CSV)…','MenuSelectedFcn',@(~,~) obj.onExportCSV());
            uimenu(cm,'Text','Save image…','MenuSelectedFcn',@(~,~) obj.onSaveImage());
            obj.Ax.ContextMenu = cm;

            % Three lines of readout: where the input is from and how the
            % estimate stands, then the numbers.
            r = uigridlayout(g,[3 1]);
            r.RowHeight = {18,18,18}; r.Padding = [4 0 4 0]; r.RowSpacing = 2;
            obj.Status   = uilabel(r,'Text','','FontWeight','bold');
            obj.RMSText  = uilabel(r,'Text','','FontName','monospaced');
            obj.LineText = uilabel(r,'Text','','FontName','monospaced');

            % Controls: what is measured on the first row, what is marked and
            % compared on the second.
            a = uigridlayout(g,[1 11]);
            a.ColumnWidth = {118,68,74,58,52,42,78,40,120,64,'1x'};
            a.Padding = [0 0 0 0]; a.ColumnSpacing = 6;
            obj.Ctrl.monitor = uibutton(a,'state','Text','Monitor input', ...
                'Tag','SpectrumMonitor','ValueChangedFcn',@(s,~) obj.onMonitor(s));
            lbl(a,'Resolution');
            obj.Ctrl.res = uidropdown(a,'Tag','SpectrumResolution', ...
                'Items',arrayfun(@(v) sprintf('%g Hz',v),obj.Resolutions,'UniformOutput',false), ...
                'ItemsData',obj.Resolutions,'Tooltip', ...
                'Hz between bins. Finer takes a longer segment of input (1 Hz = 1 s).', ...
                'ValueChangedFcn',@(s,~) obj.onControl('Resolution',s.Value));
            lbl(a,'Averages');
            obj.Ctrl.avg = uidropdown(a,'Tag','SpectrumAverages', ...
                'Items',arrayfun(@num2str,obj.AverageChoices,'UniformOutput',false), ...
                'ItemsData',obj.AverageChoices,'Tooltip', ...
                'Segments averaged (half-overlapping). More is a steadier floor over more seconds.', ...
                'ValueChangedFcn',@(s,~) obj.onControl('Averages',s.Value));
            lbl(a,'Up to');
            obj.Ctrl.max = uidropdown(a,'Tag','SpectrumMax', ...
                'Items',{'500 Hz','1 kHz','3 kHz','10 kHz','30 kHz','Nyquist'}, ...
                'ItemsData',obj.MaxChoices, ...
                'ValueChangedFcn',@(s,~) obj.onControl('MaxFrequency',s.Value));
            lbl(a,'Scale');
            obj.Ctrl.scale = uidropdown(a,'Tag','SpectrumScale', ...
                'Items',{'dB re 1 µV²/Hz','µV/√Hz'},'ItemsData',{'db','asd'}, ...
                'ValueChangedFcn',@(s,~) obj.onControl('Scale',s.Value));
            obj.Ctrl.log = uicheckbox(a,'Text','Log f','Tag','SpectrumLog', ...
                'ValueChangedFcn',@(s,~) obj.onControl('LogFrequency',s.Value));

            b = uigridlayout(g,[1 11]);
            b.ColumnWidth = {42,70,38,64,12,64,24,118,54,70,'1x'};
            b.Padding = [0 0 0 0]; b.ColumnSpacing = 6;
            lbl(b,'Mains');
            obj.Ctrl.mains = uidropdown(b,'Tag','SpectrumMains', ...
                'Items',{'Off','50 Hz','60 Hz'},'ItemsData',obj.MainsChoices,'Tooltip', ...
                'Mark the mains frequency and its harmonics, and measure them.', ...
                'ValueChangedFcn',@(s,~) obj.onControl('Mains',s.Value));
            lbl(b,'Band');
            obj.Ctrl.bandLo = uieditfield(b,'numeric','Tag','SpectrumBandLo', ...
                'Limits',[0 Inf],'ValueDisplayFormat','%g', ...
                'Tooltip','Lower edge of the in-band RMS figure (Hz).', ...
                'ValueChangedFcn',@(~,~) obj.onBand());
            lbl(b,'–');
            obj.Ctrl.bandHi = uieditfield(b,'numeric','Tag','SpectrumBandHi', ...
                'Limits',[0 Inf],'ValueDisplayFormat','%g', ...
                'Tooltip','Upper edge of the in-band RMS figure (Hz).', ...
                'ValueChangedFcn',@(~,~) obj.onBand());
            lbl(b,'Hz');
            obj.Ctrl.hold = uibutton(b,'Text','Hold reference','Tag','SpectrumHold', ...
                'Tooltip','Keep this spectrum in grey, to compare the next change against.', ...
                'ButtonPushedFcn',@(~,~) obj.holdReference());
            obj.Ctrl.clear = uibutton(b,'Text','Clear','Tag','SpectrumClear', ...
                'Tooltip','Remove the reference.','ButtonPushedFcn',@(~,~) obj.clearReference());
            obj.Ctrl.freeze = uibutton(b,'state','Text','Freeze','Tag','SpectrumFreeze', ...
                'Tooltip','Stop following the input; the spectrum on screen stays.', ...
                'ValueChangedFcn',@(s,~) obj.setFrozen(s.Value));

            function lbl(parent,txt)
                uilabel(parent,'Text',txt,'HorizontalAlignment','right');
            end
        end

        function syncControls(obj)
            % Put the settings into the controls -- after a script or a
            % configuration changed them, as well as at build.
            if obj.Building || ~obj.isvalidView(), return; end
            c = obj.Ctrl;
            c.res.Value    = obj.Resolution;
            c.avg.Value    = obj.Averages;
            c.max.Value    = obj.MaxFrequency;
            c.scale.Value  = obj.Scale;
            c.log.Value    = obj.LogFrequency;
            c.mains.Value  = obj.Mains;
            c.bandLo.Value = obj.Band(1);
            c.bandHi.Value = obj.Band(2);
        end

        function settingChanged(obj,what)
            % Every setter comes here. 'estimate' needs the spectrum computed
            % afresh (a new segment length or averaging); 'summary' only the
            % numbers read off it; 'draw' only the drawing.
            if obj.Building, return; end
            obj.syncControls();
            if ~obj.isvalidView(), return; end
            switch what
                case 'estimate'
                    obj.Estimator = [];
                    obj.LastKey   = [];
                    obj.refresh(true);
                case 'summary'
                    obj.summarize();
                    obj.draw();
                    obj.drawStatus();
                otherwise
                    obj.draw();
            end
        end

        function onControl(obj,name,value)
            % A user choosing a look: applied, and remembered for the next
            % window (a script setting the property is neither).
            try
                obj.(name) = value;
                obj.savePrefs();
            catch me
                obj.syncControls();
                obj.setNote(me.message);
            end
        end

        function onBand(obj)
            lo = obj.Ctrl.bandLo.Value; hi = obj.Ctrl.bandHi.Value;
            if hi <= lo
                obj.syncControls();
                obj.setNote('The band''s upper edge must be above its lower edge.');
                return
            end
            obj.onControl('Band',[lo hi]);
        end

        function onMonitor(obj,src)
            want = logical(src.Value);
            if isempty(obj.MonitorFcn)
                src.Value = false;
                return
            end
            src.Enable = 'off';
            ok = false; msg = '';
            try
                [ok,msg] = obj.MonitorFcn(want);
            catch me
                msg = me.message;
            end
            if ~isvalid(obj) || ~obj.isvalidView(), return; end
            if ok
                obj.Note = '';
            else
                obj.Note = char(msg);
            end
            % The source says what actually happened; the button follows it.
            obj.refresh(true);
        end

        function onTick(obj)
            try
                obj.refresh(false);
            catch me
                % Once: a timer that errors every second would bury the log.
                if ~obj.ErrorLogged
                    obj.ErrorLogged = true;
                    mabr.log.vprintf(1,1,'Spectrum refresh failed: %s',me.message);
                end
            end
        end

        function S = pull(obj)
            % The newest input, normalized to the full shape whatever the
            % source left out.
            if isempty(obj.MonitorFcn)
                idle = 'Nothing recorded yet.';
            else
                idle = 'Nothing recorded yet. Press Monitor input to record with no stimulus.';
            end
            S = mabr.ui.SpectrumViewer.noInput(idle);
            S.CanMonitor = ~isempty(obj.MonitorFcn);
            if isempty(obj.SourceFcn), return; end
            try
                fs = 192000;
                if ~isempty(obj.Estimator), fs = obj.Estimator.SampleRate; end
                L  = round(fs/obj.Resolution);
                n  = L + obj.Averages*floor(L/2);   % a full average, off the grid
                R  = obj.SourceFcn(n);
            catch me
                S.Note = ['The input could not be read: ' me.message];
                return
            end
            if ~isstruct(R) || ~isscalar(R), return; end
            f = fieldnames(R);
            for i = 1:numel(f), S.(f{i}) = R.(f{i}); end
            if ~isfield(R,'CanMonitor'), S.CanMonitor = ~isempty(obj.MonitorFcn); end
            % A source with nothing to say about an empty ring leaves the
            % window's own suggestion in place.
            if isempty(S.Note) && strcmp(S.Source,'none'), S.Note = idle; end
            S.Samples = S.Samples(:);
        end

        function e = estimator(obj,fs)
            e = obj.Estimator;
            if isempty(e) || e.SampleRate ~= fs || e.MaxSegments ~= obj.Averages ...
                    || abs(e.Resolution - fs/round(fs/obj.Resolution)) > eps(fs)
                e = mabr.compute.SpectrumEstimator(fs,obj.Resolution,obj.Averages);
                obj.Estimator = e;
                obj.LastKey = [];
            end
        end

        function summarize(obj)
            if isempty(obj.Spectrum), obj.Summary = []; return; end
            obj.Summary = mabr.metrics.noise_summary(obj.Spectrum.f,obj.Spectrum.P, ...
                'LineFrequency',obj.Mains,'Harmonics',obj.Harmonics,'Band',obj.Band, ...
                'PeakRange',[10 obj.topFrequency()]);
        end

        function top = topFrequency(obj)
            top = obj.MaxFrequency;
            if ~isempty(obj.Spectrum), top = min(top,obj.Spectrum.f(end)); end
        end

        % --- Drawing --------------------------------------------------------
        function draw(obj)
            if ~obj.isvalidView(), return; end
            ax = obj.Ax;
            if strcmp(obj.Scale,'db')
                obj.put('ylabel',ax.YLabel,'String','PSD (dB re 1 µV²/Hz)');
            else
                obj.put('ylabel',ax.YLabel,'String','ASD (µV/√Hz)');
            end
            if isempty(obj.Spectrum)
                set([obj.Line obj.RefLine obj.PeakMark],'XData',NaN,'YData',NaN);
                set(obj.MainsLines,'Visible','off');
                obj.Written.mains = [];
                return
            end
            top = obj.topFrequency();
            [x,y]   = obj.curve(obj.Spectrum.f,obj.Spectrum.P,top);
            set(obj.Line,'XData',x,'YData',y);
            yAll = y;
            if isempty(obj.Reference)
                set(obj.RefLine,'XData',NaN,'YData',NaN);
            else
                [xr,yr] = obj.curve(obj.Reference.f,obj.Reference.P,top);
                set(obj.RefLine,'XData',xr,'YData',yr);
                yAll = [yAll; yr];
            end

            % Limits valid for the scale they meet: a log axis must never
            % hold a limit of 0, so going log the limits go first, going
            % linear the scale does.
            if obj.LogFrequency
                obj.put('xlim',ax,'XLim',[obj.Spectrum.f(2) top]);
                obj.put('xscale',ax,'XScale','log');
            else
                obj.put('xscale',ax,'XScale','linear');
                obj.put('xlim',ax,'XLim',[0 top]);
            end
            if strcmp(obj.Scale,'db')
                obj.put('yscale',ax,'YScale','linear');
                obj.put('ylim',ax,'YLim',obj.yLimits(yAll));
            else
                obj.put('ylim',ax,'YLim',obj.yLimits(yAll));
                obj.put('yscale',ax,'YScale','log');
            end

            if ~(isfield(obj.Written,'mains') && isequal(obj.Written.mains,[obj.Mains top]))
                for k = 1:obj.Harmonics
                    fk = k*obj.Mains;
                    vis = obj.Mains > 0 && fk <= top;
                    if vis, obj.MainsLines(k).Value = fk; end
                    obj.MainsLines(k).Visible = onOff(vis);
                end
                obj.Written.mains = [obj.Mains top];
            end

            pk = [];
            if ~isempty(obj.Summary), pk = obj.Summary.Peak.Frequency; end
            if isempty(pk) || ~isfinite(pk)
                set(obj.PeakMark,'XData',NaN,'YData',NaN);
            else
                [~,i] = min(abs(obj.Spectrum.f - pk));
                set(obj.PeakMark,'XData',pk,'YData',obj.toY(obj.Spectrum.P(i)));
            end
        end

        function [x,y] = curve(obj,f,P,top)
            % What to plot of one spectrum: DC dropped (it is the mean the
            % estimate removed, and it has no place on a log axis), cut at the
            % top of the axis, and thinned to a min/max envelope of about two
            % points per pixel -- a spectrum to Nyquist at 0.5 Hz is 192,000
            % bins, and the lines being hunted are single bins, so thinning by
            % averaging would erase exactly what the window is for.
            keep = 2:find(f <= top,1,'last');
            x = f(keep); y = obj.toY(P(keep));
            [x,y] = envelope(x,y,1500,obj.LogFrequency);
        end

        function y = toY(obj,P)
            P = max(P,1e-30);
            if strcmp(obj.Scale,'db')
                y = 10*log10(P*1e12);            % dB re 1 µV^2/Hz
            else
                y = 1e6*sqrt(P);                 % µV/√Hz
            end
        end

        function lim = yLimits(obj,y)
            % Whole 10 dB steps, or whole decades: a limit that moves with
            % every refresh makes the floor look as if it is moving.
            y = y(isfinite(y));
            if isempty(y), lim = [0 1]; return; end
            if strcmp(obj.Scale,'db')
                lim = [10*floor(min(y)/10) 10*ceil(max(y)/10)];
                if diff(lim) < 20, lim(2) = lim(1) + 20; end
            else
                y = y(y > 0);
                if isempty(y), lim = [1e-3 1]; return; end
                lim = 10.^[floor(log10(min(y))) ceil(log10(max(y)))];
                if lim(2) <= lim(1), lim(2) = 10*lim(1); end
            end
        end

        function drawStatus(obj)
            if ~obj.isvalidView(), return; end
            S = obj.Input;
            if isempty(S), S = mabr.ui.SpectrumViewer.noInput(); end
            switch S.Source
                case 'monitor'
                    src = 'Monitoring the input — no stimulus, nothing saved';
                case 'run'
                    src = 'The schedule''s input (stimulus included)';
                case 'held'
                    src = 'Nothing streaming — the end of the last recording';
                otherwise
                    src = S.Note;
                    if isempty(src), src = 'No input.'; end
            end
            parts = {src};
            % What the source added -- the reason the monitor stopped, say --
            % where the source line did not already say it.
            if ~strcmp(S.Source,'none') && ~isempty(S.Note)
                parts{end+1} = S.Note;
            end
            if S.Testing && ~strcmp(S.Source,'none')
                parts{end+1} = 'TEST MODE: the input is the stimulus copied back';
            end
            if ~isempty(obj.Spectrum)
                in = obj.Spectrum.info;
                parts{end+1} = sprintf('%s bins, %d of %d averages (%.1f s)', ...
                    hzText(in.Resolution),in.Segments,obj.Averages,in.Duration);
                if isfinite(in.Gain) && in.Gain ~= 1
                    parts{end+1} = sprintf('÷ %g amplifier gain',in.Gain);
                end
            end
            if ~isempty(obj.Collecting)
                c = obj.Collecting;
                parts{end+1} = sprintf('collecting… %.1f of %.1f s', ...
                    c.Available/obj.estimatorRate(),c.SegmentLength/obj.estimatorRate());
            end
            if ~isempty(obj.Note), parts{end+1} = obj.Note; end
            txt = strjoin(parts,'  ·  ');
            if obj.Frozen, txt = ['FROZEN — ' txt]; end
            obj.put('status',obj.Status,'Text',txt);
            obj.put('statusTip',obj.Status,'Tooltip',txt);

            R = obj.Summary;
            if isempty(R)
                obj.put('rms',obj.RMSText,'Text','');
                obj.put('line',obj.LineText,'Text','');
                return
            end
            rms = sprintf('RMS  total %s   in %s–%s %s', ...
                vText(R.TotalRMS),hzText(R.Band(1)),hzText(R.Band(2)),vText(R.BandRMS));
            if ~isempty(obj.Reference) && ~isempty(obj.Reference.Summary)
                rms = sprintf('%s   (reference %s: %s)',rms,obj.Reference.Label, ...
                    vText(obj.Reference.Summary.BandRMS));
            end
            obj.put('rms',obj.RMSText,'Text',rms);
            if obj.Mains > 0 && ~isempty(R.Line.RMS)
                ln = sprintf('Mains %d Hz  %s   harmonics 1–%d  %s', ...
                    obj.Mains,vText(R.Line.Fundamental),R.Line.Harmonic(end),vText(R.Line.Total));
            else
                ln = 'Mains  —';
            end
            if isfinite(R.Peak.Frequency)
                ln = sprintf('%s   ·   largest other line %s at %s (+%.0f dB)', ...
                    ln,vText(R.Peak.RMS),hzText(R.Peak.Frequency),R.Peak.AboveFloor);
            else
                ln = sprintf('%s   ·   no other line 10 dB over the floor',ln);
            end
            obj.put('line',obj.LineText,'Text',ln);
        end

        function put(obj,key,h,prop,v)
            % Write a graphics property only when it differs from what was
            % last written there (see Written).
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            h.(prop) = v;
            obj.Written.(key) = v;
        end

        function fs = estimatorRate(obj)
            fs = 192000;
            if ~isempty(obj.Estimator), fs = obj.Estimator.SampleRate; end
        end

        function syncMonitorButton(obj,S)
            b  = obj.Ctrl.monitor;
            on = logical(S.Monitoring);
            % The value is written every time: a press changes it behind
            % the record's back, and the source is what says what is true.
            b.Value = on;
            if on
                obj.put('monText',b,'Text','Stop monitor');
                obj.put('monTip',b,'Tooltip','Stop recording the input.');
            else
                obj.put('monText',b,'Text','Monitor input');
                obj.put('monTip',b,'Tooltip',['Record the input with no stimulus -- ' ...
                    'silence is played and nothing is saved -- to hunt electrical ' ...
                    'noise. Start stops it.']);
            end
            % Enable likewise: onMonitor switches it off while it works.
            b.Enable = onOff(~isempty(obj.MonitorFcn) && (S.CanMonitor || S.Monitoring));
        end

        % --- Context menu ---------------------------------------------------
        function onExportCSV(obj)
            if isempty(obj.Spectrum), obj.setNote('There is no spectrum to export yet.'); return; end
            [fn,pn] = uiputfile({'*.csv','CSV (*.csv)'},'Export spectrum', ...
                sprintf('spectrum_%s.csv',char(datetime('now','Format','yyMMdd''T''HHmmss'))));
            if isequal(fn,0), return; end
            try
                obj.exportCSV(fullfile(pn,fn));
                obj.setNote(['Exported ' fn]);
            catch me
                obj.setNote(['Export failed: ' me.message]);
            end
        end

        function onSaveImage(obj)
            [fn,pn] = uiputfile({'*.png','PNG (*.png)';'*.pdf','PDF (*.pdf)'},'Save image', ...
                sprintf('spectrum_%s.png',char(datetime('now','Format','yyMMdd''T''HHmmss'))));
            if isequal(fn,0), return; end
            try
                exportgraphics(obj.Ax,fullfile(pn,fn));
                obj.setNote(['Saved ' fn]);
            catch me
                obj.setNote(['Save failed: ' me.message]);
            end
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function s = vText(v)
% An RMS voltage in the unit that reads best.
if ~isfinite(v), s = '—'; return; end
a = abs(v);
if a < 1e-6,     s = sprintf('%.3g nV',v*1e9);
elseif a < 1e-3, s = sprintf('%.3g µV',v*1e6);
elseif a < 1,    s = sprintf('%.3g mV',v*1e3);
else,            s = sprintf('%.3g V',v);
end
end

function s = hzText(f)
if f >= 1000, s = sprintf('%g kHz',round(f/10)/100); else, s = sprintf('%g Hz',round(f*100)/100); end
end

function [xd,yd] = envelope(x,y,nb,logx)
% The smallest and largest point of each of nb buckets along x, in x order:
% drawn as a line it is indistinguishable from all the points at screen
% resolution, and every single-bin line survives it.
x = x(:); y = y(:);
if numel(x) <= 2*nb, xd = x; yd = y; return; end
if logx && x(1) > 0
    edges = logspace(log10(x(1)),log10(x(end)),nb+1);
else
    edges = linspace(x(1),x(end),nb+1);
end
b = discretize(x,edges);
b(isnan(b)) = nb;
[~,o] = sortrows([b y]);
bs = b(o);
brk = [true; diff(bs) ~= 0];
first = o(brk);                          % lowest in each bucket
last  = o([brk(2:end); true]);           % highest
keep  = unique([first; last]);
xd = x(keep); yd = y(keep);
end
