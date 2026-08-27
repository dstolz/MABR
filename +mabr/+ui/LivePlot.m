classdef LivePlot < handle
% mabr.ui.LivePlot  Live acquisition view: latest sweep + per-stimulus means.
%
%   A clean, object-oriented rebuild of the legacy abr_live_plot.m (which used
%   a persistent handle struct). It owns its own figure, split into three
%   regions:
%
%     * a LATEST axes across the top, always showing the single most recent
%       sweep on its own -- it is a different quantity from an average (one
%       sweep, tens of times larger) and sharing an axis with the means would
%       flatten them, so it keeps its own,
%     * a narrow correlation bar beside it (the online onset-contrast metric)
%       -- present only while the run holds ONE condition, since that metric
%       is an average converging on itself and an intermixed run's average is
%       several conditions at once (see corrVisible),
%     * and below, the RUNNING MEAN of every stimulus the current run is
%       presenting -- overlaid, one axes each, or arranged by parameter.
%
%   That lower region is the point of the window during an intermixed run: the
%   run interleaves several conditions, so a single pooled average would mix
%   them and show nothing. Sweeps are sorted by the stimulus that evoked them
%   (mabr.stim.Schedule's per-onset stimulus index, handed over by
%   mabr.ui.AcqController) and averaged separately.
%
%       lp = mabr.ui.LivePlot();                    % own figure
%       lp.update(sweeps,tvec,R,target,bad,info);   % sweeps [nSweeps x nSamples]
%       lp.updateStats(stats,info);                 % or their statistics
%       lp.reset();                                 % clear
%
%   updateStats takes what mabr.compute.Pipeline.step returns -- the latest
%   sweep, the correlation, the counts, and per condition the mean, SD and
%   counts -- so the view can be driven with no sweep matrix in the
%   foreground at all, which is how it runs when a compute worker is doing
%   the signal processing. Both entry points end in the same render.
%
%   `info` carries the per-sweep stimulus identity; without it every sweep is
%   treated as one condition and the window degenerates to the old single-mean
%   view. See update() for the fields.
%
%   MULTIPLE PARAMETERS
%   -------------------
%   A bank almost never varies along one dimension: the ordinary ABR run is a
%   Frequency x Level grid, and a list of means labelled `Tone_8000_30` in
%   whatever order the schedule happened to present them is not a view of it.
%   Handed the stimuli's informative parameters (`info.Params`, which is what
%   mabr.stim.StimulusSet.paramTable returns) the view uses them:
%
%     * conditions are LABELLED by the parameters that actually vary across
%       this run -- '8 kHz, 30 dB' rather than a raw ID,
%     * they are ORDERED by those parameters rather than by presentation
%       order, so a level series reads as a series wherever it is drawn,
%     * they are GROUPED by one of them (`GroupBy`), which decides both the
%       colours -- one hue per group, ramping light-to-dark with the
%       within-group parameter, so the members of a series are visibly a
%       series and not seven unrelated colours -- and the arrangement of the
%       two parameter-aware layouts:
%
%           'grid'      one tile per condition, groups across columns and the
%                       within-group parameter down rows with the largest
%                       value at the top: the live analogue of the offline
%                       pipeline's plotABRGrid,
%           'stacked'   one axes per group, its conditions offset vertically
%                       into the stack a threshold series is actually read
%                       from, each labelled on the y axis.
%
%   GroupBy defaults to automatic: Frequency where the run varies one, else
%   the coarsest varying parameter (fewest distinct values), and NO grouping
%   when only one parameter varies -- a single dimension is the series
%   itself, not a way of dividing it. 'none' switches grouping off. Without
%   parameters altogether nothing changes: the view is the ID-labelled,
%   presentation-ordered list it always was.
%
%   ERROR BANDS
%   -----------
%   Every mean can carry a shaded band, drawn as a patch behind its trace and
%   in its colour. Which statistic it shows is `ErrorBand`, chosen from the
%   RIGHT-CLICK menu over the means (or set programmatically):
%
%       'std'  +/- 1 SD across sweeps -- how much a single sweep varies. It
%              does not shrink as sweeps accumulate: it describes the
%              RECORDING, and a band that stays wide is telling you the noise
%              floor has not moved,
%       'sem'  +/- 1 SEM -- how well the MEAN is pinned down, which is the one
%              that visibly tightens as an average builds,
%       'ci'   the parametric confidence interval for the mean at
%              `ConfidenceLevel` (Student's t, so it is honest over the first
%              few sweeps). The menu offers 90 / 95 / 99%.
%
%   A condition with fewer than two clean sweeps has no spread to report and
%   gets no band -- not a band of zero width, which would claim a precision
%   nothing has established.
%
%   SEM and CI bands are part of the amplitude scaling, so turning one on
%   frames it rather than clipping it. An SD band deliberately is NOT: on an
%   ABR the spread of a single sweep is tens of times the average, and letting
%   it set the scale would flatten every mean in the window to a flat line.
%   It is drawn, and runs off the axes when that is the truth about the
%   recording -- which is the thing it was turned on to say.
%
%   Display controls (also settable programmatically, which is what the strip
%   along the bottom of the window and the right-click menu do):
%
%       Layout       'overlay' | 'separate' | 'grid' | 'stacked'
%       GroupBy      '' (auto) | 'none' | a parameter name
%       TimeBase     [t0 t1] ms               default [-2 10]; the negative
%                                             half is the pre-onset baseline
%       AmpMode      'each' | 'common' | 'manual'
%       ManualLimit  volts                    the +/- limit AmpMode 'manual' uses
%       ErrorBand    'none' | 'std' | 'sem' | 'ci'
%       ConfidenceLevel  0<c<1                default 0.95, used by 'ci'
%
%   'each' lets every stimulus autoscale to its own response, which is what
%   you want when levels differ by 40 dB; 'common' holds them all to one scale,
%   which is the only way an amplitude difference between conditions is
%   visible; 'manual' pins the scale so it stops moving between refreshes.
%   Overlaid means share one axes and therefore one scale, so 'each' behaves as
%   'common' there; in 'stacked' the mode sets the offset between traces the
%   same way, per group or shared.
%
%   The latest sweep keeps its own scale under every one of those modes -- a
%   single sweep is tens of times a mean, and a limit chosen to frame the
%   averages would clip it off the axes -- but that scale moves in DISCRETE
%   STEPS rather than tracking the peak. See LatestLadder.
%
%   Sweeps flagged in `bad` are EXCLUDED from the running means -- one electrode
%   pop otherwise smears across the whole average and the view stops reflecting
%   what the block will contain. They are reported instead: the count and rate
%   appear in red above the latest trace, and the latest sweep is drawn in red
%   when it was the one rejected, so a noisy electrode is visible as it happens
%   rather than at the end of the block.
%
%   The control strip ends with NEW ANALYSIS…, which asks the host to open an
%   online-analysis window (mabr.ui.MetricPlot) -- one metric across the
%   conditions, refreshed while the schedule runs. It is deliberately a
%   "new one every press": watching a trace is exactly when the question
%   "and how is this growing with level?" arrives, and answering it should
%   not cost the plot already on screen. See NewAnalysisFcn.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant, Access = private)
        % Where the display settings below are remembered between sessions.
        % The same group everything else in MABR persists into, and the same
        % idiom mabr.ui.MetricPlot follows: the WINDOW owns its look, and a
        % look chosen once should be the one the next session opens with.
        PrefGroup     = 'MABR';
        PrefKey       = 'LivePlot';
        RecentColor   = [0.2 0.6 1];      % latest sweep, kept
        ArtifactColor = [0.85 0.15 0.1];  % latest sweep, rejected
        ZeroColor     = [0.6 0.6 0.6];
        ControlHeight = 30;   % px reserved for the control strip
        TilesPerCol   = 4;    % separate plots stack this deep before columning
        MaxLegend     = 12;   % overlaid means beyond this get no legend
        StackCols     = 4;    % stacked groups sit this many across before wrapping
        BandAlpha     = 0.18; % error-band patch opacity
        CILevels      = [0.90 0.95 0.99];   % offered in the right-click menu
        % Vertical split of the plot region: the latest sweep on top, the
        % means below it. Fractions of the plot panel.
        TopFrac       = 0.34;
        % Horizontal split of that top region: the RIGHT EDGE of the latest
        % sweep's axes with the correlation bar beside it, and once the bar is
        % gone (see corrVisible) -- the trace takes the room back rather than
        % leaving a gap where a hidden axes used to be. Right edges rather
        % than widths because the LEFT edge is measured from the labels that
        % have to fit beside it (see fitLabelGutters), and only one of the two
        % can be the fixed one.
        LatestRightNarrow = 0.81;   % with the correlation bar beside it
        LatestRightWide   = 0.97;   % without
        OverlayRight      = 0.81;   % ... and the overlaid means' right edge
        % Bounds on a measured label gutter. The floor is there for an axes
        % that answers with nothing; the ceiling is the point past which a
        % margin wide enough for the labels has swallowed the plot they were
        % labelling, and clipping them is the better trade.
        MinGutter     = 0.02;
        MaxGutter     = 0.30;
        % The latest sweep's own vertical scale. It is ONE sweep, redrawn at
        % the live tick rate, and the single question a raw sweep is watched
        % for -- is this one bigger than the last? -- is exactly the one a
        % limit tracking its own peak destroys, since the ruler then grows
        % with the thing being measured and every sweep looks the same size.
        % The limit therefore stands on a 1-2-5 ladder and moves in whole
        % rungs: UP the instant a sweep would not fit (clipping the signal is
        % never the better trade) and DOWN only after the smaller rung has
        % been enough for LatestShrinkHold consecutive refreshes, so one big
        % sweep does not leave the scale walking back down over the quiet ones
        % behind it. The rungs are also where MATLAB puts readable ticks.
        LatestLadder     = [1 2 5 10];
        LatestShrinkHold = 15;   % refreshes (~0.75 s at the 20 Hz live tick)
    end

    properties
        Title (1,:) char = 'MABR Live Plot';
        % What the Analysis button opens. A handle taking no arguments,
        % supplied by the host (mabr.ui.App points it at its own
        % onMetricPlot), because THIS view has no business knowing about the
        % controller or how many analysis windows are open -- it only knows
        % that the operator asked for one more while watching a trace. Left
        % empty the button is there but disabled: an unwired button that
        % opened a window with nothing in it would be worse than a dead one.
        NewAnalysisFcn = []
    end

    properties (SetAccess = private)
        Figure
        Container       % figure or the container this view was built into
        PlotPanel
        CtrlPanel
        axLatest
        axCorr
        axMean = gobjects(1,0);   % one (overlay), one per stimulus, or one per group
    end

    % --- Display settings ------------------------------------------------
    % Public so a script can drive the view; the control strip writes exactly
    % these, and each setter re-renders from the cached last update, so a
    % change is visible immediately whether or not sweeps are still arriving.
    properties
        Layout      (1,:) char   = 'overlay'
        GroupBy     (1,:) char   = ''          % '' = auto, 'none', or a param name
        TimeBase    (1,2) double = [-2 10]     % ms
        AmpMode     (1,:) char   = 'common'
        ManualLimit (1,1) double = 5e-6        % volts, +/-
        ErrorBand   (1,:) char   = 'none'      % none | std | sem | ci
        ConfidenceLevel (1,1) double = 0.95    % used by ErrorBand 'ci'
    end

    properties (Access = private)
        meanLines  = gobjects(1,0);   % one per stimulus, in layout order
        bandPatches = gobjects(1,0);  % error band behind each of them
        ContextMenu                   % right-click menu over the plot region
        BandItems  = gobjects(1,0);   % its error-band entries, in menu order
        BandModes  = {};              % the ErrorBand each one selects
        BandConfs  = [];              % ... and the ConfidenceLevel, or NaN
        latestLine
        corrBar
        artifactText
        legendHandle
        Ctrl = struct();      % the control-strip uicontrols
        StimList   = [];      % stimulus indices the current axes were built for
        StimLabels = {};
        TileIsLeft = [];      % which tiles sit in the left column of a grid
        LayoutKey  (1,:) char = '';
        FilterText (1,:) char = '';
        % The parameter names the Group menu is currently offering -- this
        % run's varying ones, worked out at render. Kept here so syncControls
        % can refresh the menu without asking the widget what it already says.
        GroupChoices = {};
        Last = [];            % last update() payload, for re-render on a control change
        % The latest-sweep axes' current +/- limit in VOLTS (0 = none chosen
        % yet) and how many consecutive refreshes have asked for a smaller
        % rung than it. See LatestLadder.
        LatestLim    (1,1) double = 0
        LatestShrink (1,1) double = 0
        % Room reserved for the y axis labels, in fractions of the plot panel:
        % left of the first column of means, between columns, and left of the
        % latest-sweep axes. All three are MEASURED from what is actually on
        % screen (fitLabelGutters) rather than assumed -- see it for why no
        % fixed margin is right for every layout. These are only the starting
        % estimates; the fit is the sole writer after that.
        LeftGutter   (1,1) double = 0.075
        ColGutter    (1,1) double = 0
        LatestGutter (1,1) double = 0.09
        GutterKey    (1,:) char   = ''     % what those were last measured for
        % render() is NOT re-entrant: legend() and drawnow both process the
        % event queue, so a live tick can land inside a render started by a
        % control callback (or the other way about) -- and the inner call
        % rebuilds the mean axes the outer one is still holding handles to,
        % which leaves the outer's axes orphaned on the panel and its
        % captions written onto somebody else's. A render that finds one in
        % progress is REMEMBERED rather than run: the outer call draws it
        % once it is done, from obj.Last, which by then is the newer data.
        % (Skipping outright, as mabr.ui.MetricPlot does, is right for a
        % window whose timer will come round again; here a setting changed
        % BETWEEN runs would have no tick behind it and would never appear.)
        Rendering     (1,1) logical = false
        RenderPending (1,1) logical = false
        PanelPx      (1,1) double = 0      % plot panel width, px (see relayout)
        CorrShown    (1,1) logical = true  % is the correlation bar in place?
        LastGroup    = []      % last resolved grouping, for a re-fit on resize
    end

    methods
        function obj = LivePlot(parent)
            if nargin >= 1 && ~isempty(parent) && isgraphics(parent)
                obj.Container = parent;
            else
                obj.Figure = figure('Name',obj.Title,'NumberTitle','off','Color','w', ...
                    'Tag','MABR_LIVEPLOT','Position',[100 100 780 580]);
                obj.Container = obj.Figure;
            end
            % Whatever layout, time base, scaling and error band the last
            % window was left showing. Applied BEFORE build(), so the control
            % strip is drawn from them rather than flickering through the
            % class defaults on the way. Nothing is persisted from here -- see
            % savePrefs, which only user-driven changes call.
            obj.applySettings(mabr.ui.LivePlot.loadDefaults());
            obj.build();
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isgraphics(obj.Figure), delete(obj.Figure); end
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.PlotPanel) && isgraphics(obj.PlotPanel);
        end

        function reset(obj)
            % Forget the run just finished. The axes stay as they are: the
            % next run rebuilds them for its own stimulus list on the first
            % update, and rebuilding here would flash an empty grid in between.
            obj.Last = [];
            % The next run is scaled on its own evidence: a rung held over
            % from the run before would frame the first sweeps of this one
            % against an amplitude nothing here has shown.
            obj.LatestLim    = 0;
            obj.LatestShrink = 0;
            if ~obj.isvalidView(), return; end
            set(obj.meanLines(isgraphics(obj.meanLines)),'XData',nan,'YData',nan);
            set(obj.bandPatches(isgraphics(obj.bandPatches)), ...
                'XData',nan(3,1),'YData',nan(3,1));
            if isgraphics(obj.latestLine)
                set(obj.latestLine,'XData',nan,'YData',nan,'Color',obj.RecentColor);
            end
            if isgraphics(obj.artifactText), obj.artifactText.String = ''; end
            if isgraphics(obj.corrBar), obj.corrBar.YData = 0; end
            title(obj.axLatest,'');
            for k = 1:numel(obj.axMean)
                if isgraphics(obj.axMean(k)), title(obj.axMean(k),''); end
            end
        end

        function update(obj,sweeps,tvec,R,target,bad,info)
            % sweeps : [nSweeps x nSamples]  tvec : [1 x nSamples] SECONDS,
            %          spanning the pre-onset baseline and the response, so a
            %          negative time base has something to show
            % R      : scalar correlation     target : target sweep count
            % bad    : [1 x nSweeps] logical, sweeps flagged as artifact
            % info   : optional struct
            %            .StimIndex [1 x nSweeps] stimulus behind each sweep
            %            .Stimuli   [1 x nStim]   stimuli this run presents
            %            .Labels    {1 x nStim}   fallback label for each --
            %                                     used where .Params cannot
            %                                     name the condition better
            %            .Params    the informative parameters of those
            %                       stimuli, ROW-ALIGNED with .Stimuli:
            %                         .Names   {1 x nP}
            %                         .Values  [nStim x nP]
            %                         .Varying (1 x nP) logical, optional --
            %                                  which parameters count as
            %                                  informative. The caller's answer
            %                                  wins because the right SCOPE for
            %                                  that question is the experiment,
            %                                  not this run: a blocked run holds
            %                                  one condition and varies nothing,
            %                                  and dropping every parameter for
            %                                  that reason would leave the
            %                                  operator's own dimensions off the
            %                                  one label naming what is being
            %                                  acquired. Absent, it is computed
            %                                  from the values handed over.
            %                         .Units   {1 x nP}  ('' where unknown)
            %                       exactly what mabr.stim.StimulusSet.paramTable
            %                       returns (over the BANK, with this run's rows
            %                       taken out of it -- see AcqController).
            %            .Intermixed  logical, optional -- does ONE run mix
            %                         several conditions (an interleaved or
            %                         shuffled strategy)? It decides whether
            %                         the onset-contrast bar is drawn at all;
            %                         absent, a run presenting more than one
            %                         stimulus is taken to be intermixed.
            %            .DetrendPoly, .SmoothSpan  cosmetic post-processing
            %          Omit it and every sweep counts as one condition.
            if nargin < 4, R = []; end
            if nargin < 5, target = NaN; end
            if nargin < 6, bad = []; end
            if nargin < 7 || ~isstruct(info), info = struct(); end
            if ~obj.isvalidView(), return; end
            if isempty(sweeps), obj.reset(); return; end

            n = size(sweeps,1);
            if numel(bad) == n, bad = logical(bad(:)'); else, bad = false(1,n); end
            if isempty(target), target = NaN; end

            S        = struct();
            S.Y      = double(sweeps);
            S.t      = double(tvec(:)')*1000;          % s -> ms
            S.R      = R;
            S.target = target;
            S.bad    = bad;
            S.opts   = mabr.ui.LivePlot.resolveOpts(info);
            [S.stimIdx,S.stimList,S.labels] = mabr.ui.LivePlot.resolveStimuli(info,n);
            S.params = mabr.ui.LivePlot.resolveParams(info,numel(S.stimList));
            % What render() actually reads of the sweeps, so it can be fed by
            % updateStats -- which has no sweeps -- through the same fields.
            S.stats      = [];
            S.latest     = S.Y(end,:);
            S.latestBad  = S.bad(end);
            S.latestStim = S.stimIdx(end);
            S.nTotal     = numel(S.bad);
            S.nBad       = nnz(S.bad);

            obj.Last = S;
            obj.render();
        end

        function updateStats(obj,stats,info)
            % The same view from STATISTICS rather than sweeps: what
            % mabr.compute.Pipeline.step returns, whichever process ran it --
            % the latest sweep, the correlation, the counts, and per condition
            % the mean, the SD and the counts. Every band this window draws
            % is a function of (mean, SD, n) (mabr.metrics.band_from_stats),
            % so nothing a sweep matrix could add is missing, and the
            % foreground never holds one. `info` is exactly update()'s, plus
            % an optional .target (the run's presentation count).
            %
            % Rows of stats.Mean/SD/CondCounts are in stats.Stimuli order,
            % which need not be the order the view lays the conditions out
            % in; stimulusMeans maps by stimulus index.
            if nargin < 3 || ~isstruct(info), info = struct(); end
            if ~obj.isvalidView(), return; end
            if isempty(stats) || ~isstruct(stats) || stats.NumSweeps < 1
                obj.reset(); return
            end

            S         = struct();
            S.stats   = stats;
            S.Y       = [];
            S.bad     = [];
            S.stimIdx = [];
            S.t       = double(stats.Time(:)')*1000;     % s -> ms
            S.R       = stats.Corr;
            S.target  = NaN;
            if isfield(info,'target') && ~isempty(info.target), S.target = info.target; end
            S.opts    = mabr.ui.LivePlot.resolveOpts(info);
            [~,S.stimList,S.labels] = mabr.ui.LivePlot.resolveStimuli(info,stats.NumSweeps);
            S.params     = mabr.ui.LivePlot.resolveParams(info,numel(S.stimList));
            S.latest     = double(stats.Latest(:)');
            S.latestBad  = logical(stats.LatestBad);
            S.latestStim = stats.LatestStim;
            S.nTotal     = stats.NumSweeps;
            S.nBad       = stats.NumArtifacts;

            obj.Last = S;
            obj.render();
        end

        function setFilterText(obj,txt)
            % Caption the view with the display filter chain in force. The
            % whole point of the filter dialog is that these traces are NOT the
            % raw signal, so the window says which corners it is showing you
            % rather than leaving that to memory. It rides on the latest axes'
            % subtitle, which is the one caption nothing else claims.
            obj.FilterText = char(txt);
            obj.applyFilterText();
        end

        % --- Display settings ------------------------------------------------
        function set.NewAnalysisFcn(obj,f)
            obj.NewAnalysisFcn = f;
            obj.syncAnalysisButton();
        end

        function set.Layout(obj,v)
            obj.Layout = validatestring(v,{'overlay','separate','grid','stacked'}, ...
                'mabr.ui.LivePlot','Layout');
            obj.afterSettingChange();
        end

        function set.GroupBy(obj,v)
            % Free text, deliberately: it names a stimulus parameter, and which
            % names exist is a property of the bank being run, not of this
            % class. A name no parameter answers to falls back to automatic at
            % render rather than erroring at whoever typed it.
            if isempty(v), obj.GroupBy = '';
            else,          obj.GroupBy = char(string(v));
            end
            obj.afterSettingChange();
        end

        function set.AmpMode(obj,v)
            obj.AmpMode = validatestring(v,{'each','common','manual'}, ...
                'mabr.ui.LivePlot','AmpMode');
            obj.afterSettingChange();
        end

        function set.TimeBase(obj,v)
            assert(v(2) > v(1),'mabr:ui:LivePlot:timeBase', ...
                'TimeBase must be increasing ([t0 t1] in ms).');
            obj.TimeBase = double(v);
            obj.afterSettingChange();
        end

        function set.ManualLimit(obj,v)
            assert(isfinite(v) && v > 0,'mabr:ui:LivePlot:manualLimit', ...
                'ManualLimit must be a positive number of volts.');
            obj.ManualLimit = double(v);
            obj.afterSettingChange();
        end

        function set.ErrorBand(obj,v)
            obj.ErrorBand = validatestring(v,{'none','std','sem','ci'}, ...
                'mabr.ui.LivePlot','ErrorBand');
            obj.afterSettingChange();
        end

        function set.ConfidenceLevel(obj,v)
            assert(isscalar(v) && isfinite(v) && v > 0 && v < 1, ...
                'mabr:ui:LivePlot:confidenceLevel', ...
                'ConfidenceLevel must be a probability strictly between 0 and 1.');
            obj.ConfidenceLevel = double(v);
            obj.afterSettingChange();
        end

        % --- Persistence ------------------------------------------------------
        % Every display setting above in one struct: what the pref holds, and
        % what mabr.ui.App's configuration file carries so that a named setup
        % restores the view it was arranged with. Deliberately NOT written by
        % the setters: a script driving the view (or a verification script) is
        % not a user choosing a look, and only a choice belongs in a
        % preference. The control strip and the right-click menu -- the two
        % places a person changes one -- call savePrefs themselves.
        function s = displaySettings(obj)
            s = struct('Layout',obj.Layout,'GroupBy',obj.GroupBy, ...
                       'TimeBase',obj.TimeBase,'AmpMode',obj.AmpMode, ...
                       'ManualLimit',obj.ManualLimit,'ErrorBand',obj.ErrorBand, ...
                       'ConfidenceLevel',obj.ConfidenceLevel);
        end

        function applySettings(obj,s)
            % Inverse of displaySettings(), forgiving field by field -- a struct from
            % an older MABR, a hand-edited pref, or a configuration file must
            % restore whatever validates and leave the rest alone rather than
            % refusing the lot. Each assignment goes through the property's
            % own setter, so nothing invalid gets in by this door either.
            if ~isstruct(s) || ~isscalar(s), return; end
            f = {'Layout','GroupBy','TimeBase','AmpMode','ManualLimit', ...
                 'ErrorBand','ConfidenceLevel'};
            for i = 1:numel(f)
                if ~isfield(s,f{i}), continue; end
                try
                    obj.(f{i}) = s.(f{i});
                catch me
                    mabr.log.vprintf(2,'LivePlot: ignoring %s (%s).',f{i},me.message);
                end
            end
        end

        function savePrefs(obj)
            % Guarded: a rig with no writable prefs must not lose a window
            % over a look it cannot store.
            try
                setpref(mabr.ui.LivePlot.PrefGroup,mabr.ui.LivePlot.PrefKey, ...
                    obj.displaySettings());
            catch %#ok<CTCH>
            end
        end
    end

    % =====================================================================
    methods (Static)
        function d = loadDefaults()
            % What a NEW live view opens with: the settings last chosen in
            % one. Defensive throughout, the rule every loadPrefs in MABR
            % follows -- a pref written by an older version is missing
            % whatever has been added since, and must not stop a window from
            % opening. Validating each value is applySettings' job (and
            % ultimately the property setters'), so whatever is in there
            % survives being handed back.
            d = struct('Layout','overlay','GroupBy','','TimeBase',[-2 10], ...
                       'AmpMode','common','ManualLimit',5e-6, ...
                       'ErrorBand','none','ConfidenceLevel',0.95);
            try
                if ~ispref(mabr.ui.LivePlot.PrefGroup,mabr.ui.LivePlot.PrefKey)
                    return
                end
                p = getpref(mabr.ui.LivePlot.PrefGroup,mabr.ui.LivePlot.PrefKey);
                if ~isstruct(p) || ~isscalar(p), return; end
                f = fieldnames(d);
                for i = 1:numel(f)
                    if isfield(p,f{i}), d.(f{i}) = p.(f{i}); end
                end
            catch %#ok<CTCH>
            end
        end

        function saveDefaults(d)
            % Write the pref with no window in hand: what mabr.ui.App does
            % when a configuration file restores a live-view look while no
            % live view is open, so the next one opens wearing it.
            try
                setpref(mabr.ui.LivePlot.PrefGroup,mabr.ui.LivePlot.PrefKey,d);
            catch %#ok<CTCH>
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        % --- Construction ----------------------------------------------------
        function build(obj)
            c = obj.Container;
            obj.PlotPanel = uipanel('Parent',c,'BorderType','none', ...
                'BackgroundColor','w','Units','normalized');
            obj.CtrlPanel = uipanel('Parent',c,'BorderType','none', ...
                'BackgroundColor',get(0,'defaultUicontrolBackgroundColor'), ...
                'Units','normalized');
            obj.buildControls();
            obj.buildTop();
            obj.buildContextMenu();
            obj.buildMeanAxes(mabr.ui.LivePlot.emptyGroup());
            obj.relayout();
            if isprop(c,'SizeChangedFcn'), c.SizeChangedFcn = @(~,~) obj.relayout(); end
        end

        function relayout(obj)
            % The control strip keeps a fixed PIXEL height whatever the window
            % does, so its contents can be laid out in pixels once and never
            % move; only the plot region above it stretches.
            if ~obj.isvalidView(), return; end
            h = obj.ControlHeight / max(1,obj.containerHeight());
            h = min(max(h,0.02),0.5);
            obj.CtrlPanel.Position = [0 0 1 h];
            obj.PlotPanel.Position = [0 h 1 1-h];
            obj.measurePanelPx();
            % The label gutters are fractions of that panel, so a resize is a
            % new question even though nothing was redrawn: the same labels
            % now take a different share of the width.
            obj.fitLabelGutters(obj.LastGroup);
        end

        function px = containerHeight(obj)
            c = obj.Container;
            oldU = c.Units; c.Units = 'pixels';
            px = c.Position(4);
            c.Units = oldU;
        end

        function buildTop(obj)
            p = obj.PlotPanel;
            y = 1 - obj.TopFrac;
            obj.axLatest = axes('Parent',p,'Units','normalized', ...
                'Position',[obj.LatestGutter y+0.06, ...
                    obj.LatestRightNarrow-obj.LatestGutter obj.TopFrac-0.13], ...
                'Box','on','NextPlot','add');
            grid(obj.axLatest,'on');
            yline(obj.axLatest,0,'Color',obj.ZeroColor,'LineWidth',1);
            xline(obj.axLatest,0,'Color',obj.ZeroColor,'LineStyle',':');
            obj.latestLine = line(obj.axLatest,nan,nan, ...
                'Color',obj.RecentColor,'LineWidth',1);

            % Sits in the axes' top-left corner in normalized units, so it
            % stays put as the trace rescales around it.
            obj.artifactText = text(obj.axLatest,0.02,0.96,'', ...
                'Units','normalized','Color',obj.ArtifactColor, ...
                'FontWeight','bold','VerticalAlignment','top', ...
                'HorizontalAlignment','left','Clipping','off');

            obj.axCorr = axes('Parent',p,'Units','normalized', ...
                'Position',[0.88 y+0.06 0.09 obj.TopFrac-0.13],'Box','on');
            mabr.ui.hideAxesToolbar([obj.axLatest obj.axCorr]);
            obj.corrBar = bar(obj.axCorr,1,0,'FaceColor',[0.2 0.2 0.2]);
            obj.axCorr.YLim  = [0 1];
            obj.axCorr.XTick = [];
            title(obj.axCorr,'\rho_{post}-\rho_{pre}','FontSize',8);
        end

        function tf = corrVisible(~,S)
            % Whether the rho_post-rho_pre bar means anything for this run.
            %
            % It is the online onset-contrast metric over the run's POOLED
            % sweeps -- the correlation between the running average and the
            % sweeps still arriving, post-onset against the pre-onset
            % baseline. That is a statement about ONE condition: the response
            % has stopped changing as sweeps accumulate. An INTERMIXED run
            % (interleaved / shuffled-cycles / shuffled) pools several
            % conditions into that average, so the number compares one
            % condition's mean against another condition's sweeps and is a
            % convergence measure of nothing. It is the same reason
            % mabr.ui.AcqController evaluates no advance criterion for those
            % runs -- and the bar goes with it, rather than sitting there
            % being read.
            %
            % The caller's answer wins (info.Intermixed, which AcqController
            % takes from mabr.stim.Schedule.isIntermixed, so the view follows
            % the strategy rather than guessing at it); absent one, a run
            % presenting more than one stimulus is intermixed by definition.
            if isfield(S.opts,'Intermixed') && ~isempty(S.opts.Intermixed)
                tf = ~logical(S.opts.Intermixed);
            else
                tf = numel(S.stimList) <= 1;
            end
        end

        function applyCorrBar(obj,tf)
            % Show or hide the bar, handing its width to the latest-sweep axes
            % when it goes -- an empty strip where an axes used to be reads as
            % a plot that failed to draw. The axes is hidden, never destroyed:
            % the next run may well be blocked, and rebuilding the top region
            % would take the trace on screen with it.
            if ~isgraphics(obj.axCorr) || ~isgraphics(obj.axLatest), return; end
            obj.CorrShown = tf;
            obj.applyLatestPosition();
            % An invisible axes still draws its children, so the bar itself
            % has to be told; the title follows the axes.
            obj.axCorr.Visible = onOff(tf);
            kids = obj.axCorr.Children;
            if ~isempty(kids), set(kids,'Visible',onOff(tf)); end
        end

        function buildMeanAxes(obj,G)
            % (Re)build the lower region for exactly the stimuli this run
            % presents, in the arrangement `G` resolved for them. Called only
            % when that arrangement changes, never on a plain refresh.
            delete(obj.axMean(isgraphics(obj.axMean)));
            obj.axMean      = gobjects(1,0);
            obj.meanLines   = gobjects(1,0);
            obj.bandPatches = gobjects(1,0);
            obj.legendHandle = [];
            % Belt and braces over the re-entrancy guard above: whatever the
            % cause, an axes on this panel that is not one of ours is one an
            % earlier build lost track of, and it would otherwise sit there
            % for the rest of the session with a stale run drawn on it.
            % Nothing but this view puts axes here, so the sweep is safe and
            % makes the leak self-healing rather than permanent.
            obj.dropStrayAxes();

            obj.StimList   = G.stimList;
            obj.StimLabels = G.labels;
            n   = max(1,numel(G.stimList));
            col = G.colors;
            if size(col,1) < n, col = mabr.ui.LivePlot.stimColors(n); end
            p   = obj.PlotPanel;

            obj.TileIsLeft = true(1,n);
            switch G.mode
                case 'separate'
                    [pos,isBottom,isLeft] = obj.tilePositions(n);
                    obj.TileIsLeft = isLeft;
                    for k = 1:n
                        ax = obj.newTile(p,pos(k,:),isBottom(k),isLeft(k),true);
                        obj.axMean(k) = ax;
                        [obj.bandPatches(k),obj.meanLines(k)] = obj.newMean(ax,col(k,:));
                    end

                case 'grid'
                    [pos,isBottom,isLeft] = obj.gridPositions(G);
                    obj.TileIsLeft = isLeft;
                    for k = 1:n
                        ax = obj.newTile(p,pos(k,:),isBottom(k),isLeft(k),true);
                        obj.axMean(k) = ax;
                        [obj.bandPatches(k),obj.meanLines(k)] = obj.newMean(ax,col(k,:));
                    end

                case 'stacked'
                    % One axes per group; the group's conditions are offset
                    % into it at render, so the lines belong to the group's
                    % axes but stay indexed by stimulus like every other mode.
                    [pos,isLeft] = obj.stackPositions(G.nGroups);
                    obj.TileIsLeft = isLeft;
                    for g = 1:G.nGroups
                        obj.axMean(g) = obj.newTile(p,pos(g,:),true,true,false);
                    end
                    for k = 1:n
                        g  = 1;
                        if k <= numel(G.group), g = G.group(k); end
                        [obj.bandPatches(k),obj.meanLines(k)] = ...
                            obj.newMean(obj.axMean(g),col(k,:));
                    end

                otherwise   % 'overlay'
                    ax = axes('Parent',p,'Units','normalized', ...
                        'Position',obj.overlayPosition(), ...
                        'Box','on','NextPlot','add');
                    mabr.ui.hideAxesToolbar(ax);
                    grid(ax,'on');
                    yline(ax,0,'Color',obj.ZeroColor);
                    xline(ax,0,'Color',obj.ZeroColor,'LineStyle',':');
                    obj.axMean = ax;
                    for k = 1:n
                        [obj.bandPatches(k),obj.meanLines(k)] = obj.newMean(ax,col(k,:));
                    end
                    obj.addOverlayLegend(G.labels);
                    xlabel(obj.axMean(1),'Time (ms)');
            end
            obj.attachContextMenu(obj.axMean);
            obj.attachContextMenu(obj.meanLines);
            obj.attachContextMenu(obj.bandPatches);
            obj.LayoutKey = mabr.ui.LivePlot.layoutKey(G);
        end

        function dropStrayAxes(obj)
            % Delete any axes on the plot panel that this view is not holding
            % a handle to. Called from buildMeanAxes, where the mean axes have
            % just been given up and are about to be rebuilt, so the only
            % things left to keep are the two at the top.
            if ~obj.isvalidView(), return; end
            keep = [obj.axMean(:); obj.axLatest(:); obj.axCorr(:)];
            keep = keep(isgraphics(keep));
            stray = findobj(obj.PlotPanel,'-depth',1,'Type','axes');
            for k = numel(stray):-1:1
                if any(stray(k) == keep), stray(k) = []; end
            end
            if ~isempty(stray), delete(stray); end
        end

        function [band,ln] = newMean(obj,ax,c)
            % One condition's band and mean trace, in that order: the patch is
            % created FIRST so the line it belongs to draws over it rather
            % than under its own shading. 'PickableParts' none keeps the band
            % out of the way of a right-click, which belongs to the axes.
            band = patch('Parent',ax,'XData',nan(3,1),'YData',nan(3,1), ...
                'FaceColor',c,'FaceAlpha',obj.BandAlpha,'EdgeColor','none', ...
                'PickableParts','none');
            ln   = line(ax,nan,nan,'Color',c,'LineWidth',1.5);
        end

        function ax = newTile(obj,p,pos,bottom,left,zeroLine)
            ax = axes('Parent',p,'Units','normalized','Position',pos, ...
                'Box','on','NextPlot','add','FontSize',8);
            mabr.ui.hideAxesToolbar(ax);
            grid(ax,'on');
            if zeroLine, yline(ax,0,'Color',obj.ZeroColor); end
            xline(ax,0,'Color',obj.ZeroColor,'LineStyle',':');
            % Only the tile at the foot of each column is labelled: repeating
            % "Time (ms)" under every one of a dozen tiles costs the height the
            % traces need.
            if bottom, xlabel(ax,'Time (ms)','FontSize',8);
            else,      ax.XTickLabel = [];
            end
            if ~left, ax.YTickLabel = []; end
        end

        function addOverlayLegend(obj,labels)
            % Overlaid means need naming, but a legend that eats the axes is
            % worse than none: it is drawn INSIDE (so the manual axes layout
            % stays authoritative), small, and dropped entirely once there are
            % more conditions than it could label legibly -- at which point
            % Separate plots is the answer, and the tile titles name them.
            if numel(labels) < 2 || numel(labels) > obj.MaxLegend, return; end
            obj.legendHandle = legend(obj.axMean(1),obj.meanLines,labels, ...
                'Location','northeast','Box','off','AutoUpdate','off', ...
                'FontSize',7,'NumColumns',ceil(numel(labels)/6), ...
                'Interpreter','none');   % IDs like 8kHz_30dB are not TeX
        end

        function [pos,isBottom,isLeft] = tilePositions(obj,n)
            % Stack tiles down a column before adding another column: traces
            % are wide and short, so height is the scarce dimension.
            cols = max(1,ceil(n/obj.TilesPerCol));
            rows = ceil(n/cols);
            [pos,isBottom,isLeft] = deal(zeros(n,4),false(1,n),false(1,n));
            [x0,y1,wGap,hGap,w,h] = mabr.ui.LivePlot.tileGeometry( ...
                cols,rows,1-obj.TopFrac-0.05,obj.LeftGutter,obj.ColGutter);
            for k = 1:n
                c = floor((k-1)/rows);          % fill top-to-bottom, then across
                r = mod(k-1,rows);
                pos(k,:) = [x0 + c*(w+wGap), y1 - (r+1)*h - r*hGap, w, h];
                isBottom(k) = (r == rows-1) || (k == n);
                isLeft(k)   = (c == 0);
            end
        end

        function [pos,isBottom,isLeft] = gridPositions(obj,G)
            % One tile per condition: groups across columns, the within-group
            % parameter down rows with the LARGEST value at the top -- the way
            % a level series is drawn everywhere else, including the offline
            % pipeline's grid. A group with fewer members than the tallest
            % column is bottom-aligned, so a missing high level leaves a hole
            % where it belongs rather than shifting the series.
            n    = numel(G.stimList);
            cols = max(1,G.nGroups);
            rows = max(1,max(G.within));
            % A little extra headroom: the top tile of each column carries the
            % group name above its own title.
            [x0,y1,wGap,hGap,w,h] = mabr.ui.LivePlot.tileGeometry( ...
                cols,rows,1-obj.TopFrac-0.085,obj.LeftGutter,obj.ColGutter);
            [pos,isBottom,isLeft] = deal(zeros(n,4),false(1,n),false(1,n));
            for k = 1:n
                c = G.group(k) - 1;
                r = rows - G.within(k);         % within 1 = lowest = bottom row
                pos(k,:) = [x0 + c*(w+wGap), y1 - (r+1)*h - r*hGap, w, h];
                isBottom(k) = G.within(k) == 1;
                isLeft(k)   = (c == 0);
            end
        end

        function pos = meanPositions(obj,G)
            % Where the mean axes go, in axMean order, for the arrangement G
            % and the label gutters as currently measured. buildMeanAxes
            % CREATES them here and fitLabelGutters MOVES them here -- one
            % answer to the question, so a re-measured gutter cannot leave the
            % two disagreeing about where a tile belongs.
            switch G.mode
                case 'separate', pos = obj.tilePositions(max(1,numel(G.stimList)));
                case 'grid',     pos = obj.gridPositions(G);
                case 'stacked',  pos = obj.stackPositions(G.nGroups);
                otherwise,       pos = obj.overlayPosition();
            end
        end

        function pos = overlayPosition(obj)
            % The overlaid means: one axes, its right edge fixed and its left
            % wherever the y label and the numbers need it to be.
            x = min(max(obj.LeftGutter,obj.MinGutter),obj.MaxGutter);
            pos = [x 0.11 max(0.1,obj.OverlayRight-x) 1-obj.TopFrac-0.16];
        end

        function applyMeanPositions(obj,G)
            pos = obj.meanPositions(G);
            for k = 1:min(size(pos,1),numel(obj.axMean))
                if ~isgraphics(obj.axMean(k)), continue; end
                if ~isequal(obj.axMean(k).Position,pos(k,:))
                    obj.axMean(k).Position = pos(k,:);
                end
            end
        end

        function applyLatestPosition(obj)
            % The latest-sweep axes between its measured left gutter and
            % whichever right edge the correlation bar has left it.
            if ~isgraphics(obj.axLatest), return; end
            r = obj.LatestRightWide;
            if obj.CorrShown, r = obj.LatestRightNarrow; end
            x   = min(max(obj.LatestGutter,obj.MinGutter),obj.MaxGutter);
            pos = obj.axLatest.Position;
            new = [x pos(2) max(0.1,r-x) pos(4)];
            if ~isequal(pos,new), obj.axLatest.Position = new; end
        end

        function fitLabelGutters(obj,G)
            % Give the y axis labels the room they actually take.
            %
            % How much that is depends on the layout, and no fixed margin is
            % right for all of them: a mean axes is labelled with three-digit
            % microvolts, while a 'stacked' one is labelled with the condition
            % NAMES ("60 dB (136)") and EVERY column of stacks carries them,
            % not just the leftmost. A margin sized for the numbers clips the
            % names -- and clips them into the neighbouring tile, where they
            % land on top of somebody else's trace rather than simply being
            % cut off. So the margins are measured from what is on screen
            % (TightInset is exactly the room the labels asked for) and the
            % tiles are re-tiled around them.
            %
            % Measuring costs a graphics query, so it is done only when the
            % answer could have changed: a new arrangement, a label that
            % gained a character, or a resized window -- the margins are
            % fractions of the panel, so its width is part of the question.
            if ~obj.isvalidView() || isempty(G), return; end
            key = obj.gutterKey(G);
            if strcmp(key,obj.GutterKey), return; end
            obj.GutterKey = key;

            [l,c,lat] = obj.measureGutters();
            l   = obj.pickGutter(obj.LeftGutter,l);
            c   = obj.pickGutter(obj.ColGutter,c);
            lat = obj.pickGutter(obj.LatestGutter,lat);
            if isequal([l c lat],[obj.LeftGutter obj.ColGutter obj.LatestGutter])
                return
            end
            obj.LeftGutter   = l;
            obj.ColGutter    = c;
            obj.LatestGutter = lat;
            obj.applyMeanPositions(G);
            obj.applyLatestPosition();
        end

        function g = pickGutter(~,cur,want)
            % Take a measured gutter, or keep the one in force.
            %
            % It GROWS the instant the labels need it -- a label that does not
            % fit is the whole reason this exists -- and shrinks only once
            % there is real room to give back. The asymmetry is what keeps the
            % fit stable: a narrower axes can be relabelled by MATLAB with
            % shorter ticks, which would ask for a narrower gutter, which
            % would widen the axes again, and a symmetric rule would sit there
            % swapping between the two answers on alternate refreshes.
            if want > cur + 0.002 || want < cur - 0.015
                g = want;
            else
                g = cur;
            end
        end

        function [l,c,lat] = measureGutters(obj)
            % What the labels now drawn need, in fractions of the plot panel:
            % left of the first column, between columns, and left of the
            % latest-sweep axes. TightInset(1) IS that width -- the tick
            % labels plus the y label where there is one -- and the pad is the
            % gap between a label and whatever sits to its left.
            pad = 0.006;
            l = obj.MinGutter; c = 0; lat = obj.MinGutter;
            for k = 1:numel(obj.axMean)
                ti = obj.leftInset(obj.axMean(k));
                if isnan(ti), continue; end
                if k > numel(obj.TileIsLeft) || obj.TileIsLeft(k)
                    l = max(l,ti+pad);
                else
                    c = max(c,ti+pad);
                end
            end
            ti = obj.leftInset(obj.axLatest);
            if ~isnan(ti), lat = max(lat,ti+pad); end
            l   = min(l,obj.MaxGutter);
            c   = min(c,obj.MaxGutter);
            lat = min(lat,obj.MaxGutter);
        end

        function v = leftInset(~,ax)
            % The room an axes' y labels take, in the axes' OWN units (which
            % are normalized to the panel, as every axes here is). NaN rather
            % than zero for an axes that cannot answer -- one not yet drawn
            % reports zeros, and zero is not a measurement.
            v = NaN;
            if isempty(ax) || ~isgraphics(ax), return; end
            try
                ti = ax.TightInset;
            catch
                return
            end
            if ~isempty(ti) && isfinite(ti(1)) && ti(1) > 0, v = ti(1); end
        end

        function k = gutterKey(obj,G)
            % What a measured gutter depends on: the arrangement, the panel's
            % width (the gutters are fractions of it), and how LONG the labels
            % are. Their length rather than their text, deliberately -- a
            % sweep count ticking from 136 to 137 is not a new question, and
            % asking it twenty times a second would put a graphics query in
            % the live tick for nothing.
            ax = [obj.axMean(:).' obj.axLatest];
            n  = zeros(1,numel(ax));
            for i = 1:numel(ax)
                n(i) = mabr.ui.LivePlot.labelWidthChars(ax(i));
            end
            if obj.PanelPx <= 0, obj.measurePanelPx(); end
            k = sprintf('%s|%d|%s',G.mode,round(obj.PanelPx),mat2str(n));
        end

        function measurePanelPx(obj)
            % The plot panel's width in pixels, cached. It can only change
            % when the container is resized, which is exactly when relayout
            % runs -- and asking for it means flipping the panel's Units
            % twice, which is not something the live tick should be doing
            % twenty times a second for an answer that has not moved.
            p = obj.PlotPanel;
            oldU = p.Units; p.Units = 'pixels';
            obj.PanelPx = max(1,p.Position(3));
            p.Units = oldU;
        end

        function [pos,isLeft] = stackPositions(obj,nG)
            % Stacks are tall: keep the groups on one row for as long as they
            % fit, and only then wrap.
            %
            % Unlike the other tiled layouts EVERY stack is labelled -- the y
            % ticks are the condition names, not a scale a neighbour repeats
            % -- so isLeft is reported for the gutter measurement's sake and
            % is the only thing that tells the first column's labels (which
            % have the panel edge to grow into) from the rest (which have a
            % tile there instead).
            nG   = max(1,nG);
            cols = min(nG,obj.StackCols);
            rows = ceil(nG/cols);
            [x0,y1,wGap,hGap,w,h] = mabr.ui.LivePlot.tileGeometry( ...
                cols,rows,1-obj.TopFrac-0.05,obj.LeftGutter,obj.ColGutter);
            pos = zeros(nG,4); isLeft = false(1,nG);
            for g = 1:nG
                c = mod(g-1,cols);              % fill across, then down
                r = floor((g-1)/cols);
                pos(g,:) = [x0 + c*(w+wGap), y1 - (r+1)*h - r*hGap, w, h];
                isLeft(g) = (c == 0);
            end
        end

        % --- Right-click menu ------------------------------------------------
        function buildContextMenu(obj)
            % One context menu for the whole plot region: right-click the
            % means (or the panel behind them) to choose an error band.
            %
            % A menu rather than another control in the strip, because the
            % strip is already full at the window's minimum width, and because
            % the band is a question you ask OF the traces you are looking at
            % -- which is exactly what a right-click on them is for.
            f = ancestor(obj.PlotPanel,'figure');
            if isempty(f), return; end
            obj.ContextMenu = uicontextmenu(f);
            parent = uimenu(obj.ContextMenu,'Label','Error band');

            % A flat radio list, deliberately: one click reaches any of the
            % six answers, where a Statistic > Level nesting would cost two
            % for the confidence intervals and buy nothing.
            nCI = numel(obj.CILevels);
            obj.BandModes = [{'none','std','sem'} repmat({'ci'},1,nCI)];
            obj.BandConfs = [NaN NaN NaN obj.CILevels];
            labels = [{'None','± 1 SD','± 1 SEM'} ...
                arrayfun(@(c) sprintf('%g%% confidence',100*c),obj.CILevels, ...
                         'UniformOutput',false)];
            sep = false(1,numel(labels));
            sep(min(2,end)) = true;      % None | the two descriptive bands
            sep(min(4,end)) = true;      % ... | the confidence intervals

            obj.BandItems = gobjects(1,numel(labels));
            for i = 1:numel(labels)
                % 'Label'/'Callback' rather than 'Text'/'MenuSelectedFcn', the
                % same pair mabr.ui.TraceOrganizer uses: both work everywhere.
                obj.BandItems(i) = uimenu(parent,'Label',labels{i}, ...
                    'Callback',@(~,~) obj.onBandMenu(i));
                if sep(i), obj.BandItems(i).Separator = 'on'; end
            end

            obj.attachContextMenu(obj.PlotPanel);
            obj.syncBandMenu();
        end

        function attachContextMenu(obj,h)
            % ContextMenu is R2020a+; UIContextMenu is what came before it.
            % The same two-release dance mabr.ui.TraceOrganizer does.
            if isempty(obj.ContextMenu) || ~isgraphics(obj.ContextMenu), return; end
            for k = 1:numel(h)
                if ~isgraphics(h(k)), continue; end
                try
                    h(k).ContextMenu = obj.ContextMenu;
                catch
                    set(h(k),'UIContextMenu',obj.ContextMenu);
                end
            end
        end

        function onBandMenu(obj,i)
            % Level first, then the statistic: the mode is what puts a band on
            % screen, so setting it last means the band is never briefly drawn
            % at the level the user just moved away from.
            if ~isnan(obj.BandConfs(i)), obj.ConfidenceLevel = obj.BandConfs(i); end
            obj.ErrorBand = obj.BandModes{i};
            obj.savePrefs();
        end

        function syncBandMenu(obj)
            % Tick the entry the view is actually showing. A ConfidenceLevel
            % only a script could have set (0.9973, say) matches no entry and
            % leaves them all unticked -- the axis label still names it.
            for i = 1:numel(obj.BandItems)
                if ~isgraphics(obj.BandItems(i)), continue; end
                on = strcmp(obj.ErrorBand,obj.BandModes{i});
                if on && ~isnan(obj.BandConfs(i))
                    on = abs(obj.ConfidenceLevel - obj.BandConfs(i)) < 1e-9;
                end
                obj.BandItems(i).Checked = onOff(on);
            end
        end

        % --- Control strip ---------------------------------------------------
        function buildControls(obj)
            p = obj.CtrlPanel;
            x = 8;
            [~,x] = obj.addText(p,'Means:',x,40);
            [obj.Ctrl.layout,x] = obj.addPopup(p, ...
                {'Overlaid','Separate','Grid','Stacked'},x,88, ...
                @() obj.onLayoutControl(), ...
                ['One axes for every stimulus mean, one axes each, a grid ' ...
                 'arranged by stimulus parameter, or one offset stack per ' ...
                 'group.  Right-click the means for an error band.']);

            x = x + 10;
            [~,x] = obj.addText(p,'Group:',x,40);
            [obj.Ctrl.group,x] = obj.addPopup(p,{'Auto','None'},x,92, ...
                @() obj.onGroupControl(), ...
                ['The stimulus parameter the conditions are grouped by: it ' ...
                 'colours each group as a series and forms the columns of ' ...
                 'Grid and Stacked.']);

            x = x + 10;
            [~,x] = obj.addText(p,'Time (ms):',x,62);
            [obj.Ctrl.t0,x] = obj.addEdit(p,x,42,@() obj.onTimeControl(), ...
                'Start of the displayed window, relative to stimulus onset (may be negative).');
            [~,x] = obj.addText(p,'to',x,16);
            [obj.Ctrl.t1,x] = obj.addEdit(p,x,42,@() obj.onTimeControl(), ...
                'End of the displayed window, relative to stimulus onset.');

            x = x + 10;
            [~,x] = obj.addText(p,'Amp:',x,32);
            [obj.Ctrl.amp,x] = obj.addPopup(p, ...
                {'Auto (each)','Auto (shared)','Manual'},x,104,@() obj.onAmpControl(), ...
                ['How the mean axes are scaled: each stimulus to its own peak, ' ...
                 'all to one shared scale, or a fixed limit you set.']);
            [obj.Ctrl.manual,x] = obj.addEdit(p,x,54,@() obj.onManualControl(), ...
                'Fixed +/- limit for the mean axes.');
            [obj.Ctrl.manualUnit,x] = obj.addText(p,'uV',x,26);

            % Opening an online-analysis window from HERE is the point of
            % putting it here: the moment you want a metric plotted across
            % conditions is the moment you are staring at the traces and
            % wondering whether the response is growing with level. Every
            % press opens ANOTHER window (mabr.ui.MetricPlot is deliberately
            % not a singleton), which is why it says "New".
            x = x + 10;
            obj.Ctrl.analysis = uicontrol(p,'Style','pushbutton', ...
                'String','Analysis…','Units','pixels', ...
                'Position',[x 4 86 22],'Callback',@(~,~) obj.onAnalysis(), ...
                'TooltipString',['Open ANOTHER online-analysis window: one ' ...
                                 'metric across the conditions, refreshed ' ...
                                 'while the schedule runs.']);

            obj.syncAnalysisButton();
            obj.syncControls();
        end

        function [h,x] = addText(~,p,txt,x,w)
            h = uicontrol(p,'Style','text','String',txt,'Units','pixels', ...
                'Position',[x 5 w 16],'HorizontalAlignment','left', ...
                'BackgroundColor',p.BackgroundColor);
            x = x + w + 3;
        end

        function [h,x] = addPopup(~,p,items,x,w,fcn,tip)
            h = uicontrol(p,'Style','popupmenu','String',items,'Units','pixels', ...
                'Position',[x 4 w 20],'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        function [h,x] = addEdit(~,p,x,w,fcn,tip)
            h = uicontrol(p,'Style','edit','String','','Units','pixels', ...
                'Position',[x 5 w 20],'BackgroundColor','w', ...
                'Callback',@(~,~) fcn(),'TooltipString',tip);
            x = x + w + 3;
        end

        function onAnalysis(obj)
            if isempty(obj.NewAnalysisFcn), return; end
            obj.NewAnalysisFcn();
        end

        function syncAnalysisButton(obj)
            if ~isfield(obj.Ctrl,'analysis') || ~isgraphics(obj.Ctrl.analysis)
                return
            end
            obj.Ctrl.analysis.Enable = onOff(~isempty(obj.NewAnalysisFcn));
        end

        function onLayoutControl(obj)
            modes = {'overlay','separate','grid','stacked'};
            obj.Layout = modes{obj.Ctrl.layout.Value};
            obj.savePrefs();
        end

        function onGroupControl(obj)
            items = cellstr(obj.Ctrl.group.String);
            v     = min(max(1,obj.Ctrl.group.Value),numel(items));
            switch v
                case 1, obj.GroupBy = '';        % Auto
                case 2, obj.GroupBy = 'none';
                otherwise, obj.GroupBy = items{v};
            end
            obj.savePrefs();
        end

        function onAmpControl(obj)
            modes = {'each','common','manual'};
            newMode = modes{obj.Ctrl.amp.Value};
            % Switching INTO manual seeds the limit from whatever is on screen,
            % so "Manual" starts by holding the current view still rather than
            % jumping to some remembered number from an hour ago.
            if strcmp(newMode,'manual') && ~isempty(obj.Last)
                lim = obj.dataLimit();
                if isfinite(lim) && lim > 0, obj.ManualLimit = lim; end
            end
            obj.AmpMode = newMode;
            obj.savePrefs();
        end

        function onTimeControl(obj)
            t = obj.TimeBase;
            v0 = str2double(obj.Ctrl.t0.String);
            v1 = str2double(obj.Ctrl.t1.String);
            if isfinite(v0) && isfinite(v1) && v1 > v0
                obj.TimeBase = [v0 v1];
                obj.savePrefs();
            else
                obj.syncControls();   % reject: put the old values back
                obj.TimeBase = t;
            end
        end

        function onManualControl(obj)
            v = str2double(obj.Ctrl.manual.String);
            s = obj.currentScale();
            if isfinite(v) && v > 0
                obj.ManualLimit = v / s.mult;   % typed in the displayed unit
                obj.AmpMode     = 'manual';     % typing a limit means using it
                obj.savePrefs();
            end
            obj.syncControls();
        end

        function syncControls(obj)
            % Push the settings into the strip. The manual field is shown in
            % whatever unit the axes are currently labelled in, so the number
            % beside "uV" always means what it says.
            if ~isfield(obj.Ctrl,'layout') || ~isgraphics(obj.Ctrl.layout), return; end
            obj.Ctrl.layout.Value = find(strcmp(obj.Layout, ...
                {'overlay','separate','grid','stacked'}),1);
            obj.Ctrl.amp.Value    = find(strcmp(obj.AmpMode,{'each','common','manual'}),1);
            obj.Ctrl.t0.String    = num2str(obj.TimeBase(1),'%g');
            obj.Ctrl.t1.String    = num2str(obj.TimeBase(2),'%g');
            s = obj.currentScale();
            obj.Ctrl.manual.String     = num2str(obj.ManualLimit*s.mult,'%.4g');
            obj.Ctrl.manualUnit.String = s.plain;
            obj.Ctrl.manual.Enable     = onOff(strcmp(obj.AmpMode,'manual'));
            obj.syncGroupControl();
        end

        function syncGroupControl(obj,choices)
            % The Group menu is the run's own vocabulary: whichever of the
            % bank's parameters actually vary across the stimuli on screen.
            % Rebuilt only when that list changes -- this runs at 20 Hz behind
            % the live tick, and rewriting a popupmenu's String every frame
            % would drop the mouse out of it mid-click.
            if nargin < 2, choices = obj.GroupChoices; end
            obj.GroupChoices = choices;
            if ~isfield(obj.Ctrl,'group') || ~isgraphics(obj.Ctrl.group), return; end
            h     = obj.Ctrl.group;
            items = [{'Auto','None'} choices(:)'];

            v = 1;
            if strcmpi(obj.GroupBy,'none')
                v = 2;
            elseif ~isempty(obj.GroupBy)
                j = find(strcmpi(choices,obj.GroupBy),1);
                if ~isempty(j), v = 2 + j; end
            end

            if ~isequal(h.String(:)',items)
                h.Value  = 1;          % never leave Value past the new list
                h.String = items;
            end
            if h.Value ~= v, h.Value = v; end
            newEnable = onOff(~isempty(choices));
            if ~strcmp(h.Enable,newEnable), h.Enable = newEnable; end
        end

        function afterSettingChange(obj)
            % Every setter lands here: keep the strip honest and redraw from
            % the cached sweeps, so a control does something even between runs.
            if ~obj.isvalidView(), return; end
            obj.syncControls();
            obj.syncBandMenu();
            if ~isempty(obj.Last), obj.render(); end
        end

        % --- Rendering -------------------------------------------------------
        function render(obj)
            % One pass, and never two at once -- see Rendering. The pending
            % pass runs at most once: anything arriving during THAT one has a
            % live tick behind it (nothing else can reach here while a render
            % is running), and looping until the queue is quiet would let a
            % 20 Hz tick keep a slow render from ever returning.
            if ~obj.isvalidView(), return; end
            if obj.Rendering, obj.RenderPending = true; return; end
            obj.Rendering = true;
            guard = onCleanup(@() obj.endRender()); %#ok<NASGU>
            obj.renderOnce();
            if obj.RenderPending
                obj.RenderPending = false;
                obj.renderOnce();
            end
        end

        function endRender(obj)
            if isvalid(obj), obj.Rendering = false; end
        end

        function renderOnce(obj)
            S = obj.Last;
            if isempty(S) || ~obj.isvalidView(), return; end

            G   = obj.resolveGrouping(S);
            obj.LastGroup = G;
            key = mabr.ui.LivePlot.layoutKey(G);
            if ~strcmp(key,obj.LayoutKey)
                obj.buildMeanAxes(G);
                obj.applyFilterText();
            end
            obj.syncGroupControl(G.paramChoices);

            D      = obj.stimulusMeans(S,G);
            latest = S.latest;
            % D.A is what the mean axes have to fit -- the traces plus any
            % band that speaks for them -- so switching a SEM or CI band on
            % frames it instead of clipping it.
            scale  = obj.pickScale(max([D.A(:); abs(latest(:)); 0]));

            % --- latest sweep ------------------------------------------------
            set(obj.latestLine,'XData',S.t,'YData',latest*scale.mult);
            if S.latestBad, obj.latestLine.Color = obj.ArtifactColor;
            else,           obj.latestLine.Color = obj.RecentColor;
            end
            % The latest sweep scales on its own even under AmpMode 'manual':
            % it is a single sweep, tens of times the size of a mean, and a
            % limit chosen to frame the averages would clip it off the axes
            % entirely. It scales in RUNGS (latestLimit) rather than to the
            % peak, and the rung already stands at or above that peak, so it
            % is applied unpadded -- a pad would only push the ticks off it.
            obj.setLimits(obj.axLatest,S.t, ...
                obj.latestLimit(max(abs(latest)))*scale.mult,1);
            ylabel(obj.axLatest,sprintf('Amplitude (%s)',scale.unit));
            % Interpreter 'none' wherever a stimulus ID can appear: an ID like
            % 8kHz_30dB is not TeX, and the default interpreter renders the
            % underscore as a subscript.
            title(obj.axLatest,obj.latestTitle(S,G,D.counts),'Interpreter','none');
            obj.showArtifacts(S.nBad,S.nTotal);

            % --- per-stimulus means ------------------------------------------
            if strcmp(G.mode,'stacked')
                obj.renderStacked(S,G,D,scale);
            else
                obj.renderPanels(S,G,D,scale);
            end

            % --- onset-contrast bar ------------------------------------------
            showCorr = obj.corrVisible(S);
            obj.applyCorrBar(showCorr);
            if showCorr && ~isempty(S.R) && isscalar(S.R) && ~isnan(S.R)
                obj.corrBar.YData = max(0,min(1,S.R));
            end
            drawnow limitrate
            % Last, and after the drawnow: the labels this refresh wrote have
            % to exist before the room they need can be measured, and a tile
            % that moves as a result moves on the next refresh -- 50 ms away
            % at the live tick rate, and never mid-draw.
            obj.fitLabelGutters(G);
        end

        function renderPanels(obj,S,G,D,scale)
            % Overlay / Separate / Grid: one line per stimulus on its own axes
            % or on the shared one. Only the titling differs between them.
            yl = obj.meanLimits(D.A,scale);
            for k = 1:numel(obj.meanLines)
                set(obj.meanLines(k),'XData',S.t,'YData',D.M(k,:)*scale.mult);
                obj.setBand(obj.bandPatches(k),S.t,D.M(k,:),D.E(k,:),scale.mult,0);
            end
            for a = 1:numel(obj.axMean)
                obj.setLimits(obj.axMean(a),S.t,yl(min(a,numel(yl))));
            end

            if numel(obj.axMean) > 1
                isTop = mabr.ui.LivePlot.gridTopMask(G);
                % A tile away from the left edge is normally left unlabelled --
                % it repeats its neighbour's scale. Under 'each' it does not:
                % every tile is on its own scale, and hiding the numbers would
                % leave a column of traces with no way to tell how big they are.
                showAll = strcmp(obj.AmpMode,'each');
                for k = 1:numel(obj.axMean)
                    ax = obj.axMean(k);
                    leftTile = k > numel(obj.TileIsLeft) || obj.TileIsLeft(k);
                    if showAll || leftTile
                        if ~strcmp(ax.YTickLabelMode,'auto')
                            ax.YTickLabelMode = 'auto';
                        end
                    elseif ~isempty(ax.YTickLabel)
                        ax.YTickLabel = [];
                    end
                    nEff = D.counts(k) - D.rejected(k);
                    if strcmp(G.mode,'grid')
                        txt = sprintf('%s  (n=%d)',G.shortLabels{k},nEff);
                        gl  = G.groupLabels{G.group(k)};
                        if isTop(k) && ~isempty(gl), txt = {gl; txt}; end
                        obj.setTitle(ax,txt,'FontSize',7, ...
                            'FontWeight','normal','Interpreter','none');
                    else
                        obj.setTitle(ax,sprintf('%s  (n=%d)',G.labels{k},nEff), ...
                            'FontSize',8,'FontWeight','normal','Interpreter','none');
                    end
                end
                ylabel(obj.axMean(1),obj.meanYLabel(scale));
            else
                ylabel(obj.axMean(1),obj.meanYLabel(scale));
                title(obj.axMean(1),obj.overlayTitle(G,D.counts,D.rejected), ...
                    'Interpreter','none');
            end
        end

        function setTitle(~,ax,txt,varargin)
            % A title is rewritten on every refresh and hardly any refresh
            % changes it. Writing the same string back is not free: a title is
            % CENTRED, so it is re-laid out and moved whenever its width
            % changes -- and at the live tick rate under `drawnow limitrate`
            % a caption that keeps shifting is drawn again before the last one
            % has been erased, which is what reads as doubled text.
            h = get(ax,'Title');
            same = isequal(h.String,txt);
            for i = 1:2:numel(varargin)
                if ~same, break; end
                same = isequal(h.(varargin{i}),varargin{i+1});
            end
            if ~same, title(ax,txt,varargin{:}); end
        end

        function setYTicks(~,ax,ticks,lbl)
            % The same reasoning as setTitle, for the tick labels that ARE the
            % condition names in a stack: they carry a sweep count that
            % changes far less often than the refresh does. YTick goes first
            % because setting it puts the labels back on 'auto', so a tick
            % that moved forces its label to be rewritten with it.
            moved = ~isequal(ax.YTick,ticks);
            if moved, ax.YTick = ticks; end
            cur = ax.YTickLabel;
            if ischar(cur), cur = cellstr(cur); end
            if moved || ~isequal(cur(:).',lbl(:).')
                ax.YTickLabel = lbl;
            end
        end

        function setBand(~,h,t,m,e,mult,offset)
            % One condition's band as a closed polygon: the lower edge left to
            % right, the upper edge back again. All three statistics are
            % symmetric about the mean, so one half-width draws both edges.
            %
            % A band with any non-finite edge is blanked outright rather than
            % drawn with a gap: a patch is one face, and a NaN vertex in the
            % middle of it does not mean "no data here", it means the polygon
            % is undefined. e is all-NaN exactly when there is no band to draw
            % (band off, or fewer than two clean sweeps), so this is
            % all-or-nothing by construction.
            if isempty(h) || ~isgraphics(h), return; end
            lo = (m - e)*mult + offset;
            hi = (m + e)*mult + offset;
            if ~all(isfinite(lo)) || ~all(isfinite(hi))
                set(h,'XData',nan(3,1),'YData',nan(3,1));
                return
            end
            t = t(:);
            set(h,'XData',[t; flipud(t)],'YData',[lo(:); flipud(hi(:))]);
        end

        function s = meanYLabel(obj,scale)
            % The mean axes' y label doubles as the statement of what the band
            % is: it is written once per layout, in the place the reader is
            % already looking to find out what the numbers mean.
            b = obj.bandLabel();
            if isempty(b), s = sprintf('Mean (%s)',scale.unit);
            else,          s = sprintf('Mean %s (%s)',b,scale.unit);
            end
        end

        function s = bandLabel(obj)
            switch obj.ErrorBand
                case 'std', s = '± 1 SD';
                case 'sem', s = '± 1 SEM';
                case 'ci',  s = sprintf('± %g%% CI',100*obj.ConfidenceLevel);
                otherwise,  s = '';
            end
        end

        function renderStacked(obj,S,G,D,scale)
            % One axes per group, its conditions offset into a stack and named
            % on the y axis -- the y ticks ARE the labels, so a series needs no
            % legend and no per-trace annotation to read.
            Md = D.M*scale.mult;
            Ad = D.A*scale.mult;      % mean + band: what has to clear the gap
            for g = 1:numel(obj.axMean)
                ax  = obj.axMean(g);
                sel = find(G.group == g);
                if isempty(sel)
                    ax.YTick = []; continue
                end
                [~,ord] = sort(G.within(sel));
                sel  = sel(ord);
                step = obj.stackStep(Ad,G,g,scale.mult);
                offs = (0:numel(sel)-1)*step;

                lbl = cell(1,numel(sel));
                for j = 1:numel(sel)
                    k = sel(j);
                    set(obj.meanLines(k),'XData',S.t,'YData',Md(k,:)+offs(j));
                    obj.setBand(obj.bandPatches(k),S.t,D.M(k,:),D.E(k,:), ...
                        scale.mult,offs(j));
                    lbl{j} = sprintf('%s (%d)',G.shortLabels{k}, ...
                        D.counts(k)-D.rejected(k));
                end

                obj.setXLim(ax,S.t);
                ax.YLim     = [offs(1)-0.75*step, offs(end)+0.75*step];
                ax.FontSize = 8;
                obj.setYTicks(ax,offs,lbl);
                head = G.groupLabels{g};
                if isempty(head), head = 'Means'; end
                % No y label here -- the y axis carries the condition names --
                % so the band is named in the same parenthetical as the step.
                tail = obj.bandLabel();
                if ~isempty(tail), tail = [', ' tail]; end
                obj.setTitle(ax,sprintf('%s   (step %.3g %s%s)', ...
                    head,step,scale.plain,tail), ...
                    'FontSize',8,'FontWeight','normal','Interpreter','none');
            end
        end

        function step = stackStep(obj,Ad,G,g,mult)
            % The vertical offset between the traces of one stack, in DISPLAY
            % units, measured against the mean PLUS its band (Ad) so that
            % switching a band on widens the stack instead of overlapping it.
            % AmpMode decides the scope, exactly as it decides an axis limit
            % elsewhere: the group's own largest response ('each'), the largest
            % anywhere ('common'), or the fixed limit. 2.2x it, so neighbouring
            % traces have somewhere to go before they collide.
            switch obj.AmpMode
                case 'manual'
                    step = 2.2*obj.ManualLimit*mult;
                case 'each'
                    step = 2.2*max(Ad(G.group == g,:),[],'all');
                otherwise
                    step = 2.2*max(Ad,[],'all');
            end
            % Nothing averaged yet (every mean still NaN), or a dead channel:
            % any positive step will do -- the labels still have to sit apart.
            if isempty(step) || ~isfinite(step) || step <= 0, step = 1; end
        end

        function D = stimulusMeans(obj,S,G)
            % One running mean per stimulus, over the sweeps that survived the
            % artifact preview -- the average the block will actually hold --
            % together with the error band around it and the sweep counts
            % behind both. Returned as one bundle because every consumer wants
            % the same four things and they must describe the same sweeps.
            %
            %   .M  [n x nSamples] the means            .counts   sweeps seen
            %   .E  [n x nSamples] band half-widths     .rejected of those, bad
            %   .A  what the axes have to fit, and what a stack has to clear:
            %       abs(M), plus the band where the band is a statement about
            %       the MEAN (see below)
            n = numel(obj.meanLines);
            D = struct('M',nan(n,numel(S.t)),'E',nan(n,numel(S.t)), ...
                       'A',nan(n,numel(S.t)), ...
                       'counts',zeros(1,n),'rejected',zeros(1,n));
            wantBand  = ~strcmp(obj.ErrorBand,'none');
            fromStats = isfield(S,'stats') && ~isempty(S.stats);
            for k = 1:n
                % Each condition's mean, spread and counts -- from the sweeps
                % when update() handed them over, from the published
                % statistics when updateStats() did. The two branches are the
                % same arithmetic (error_band IS band_from_stats over
                % std(Y,0,1)), which is what lets the rest of this method not
                % care which it got.
                e = [];
                if fromStats
                    st = S.stats;
                    r  = [];
                    if k <= numel(G.stimList), r = find(st.Stimuli == G.stimList(k),1); end
                    if isempty(r), continue; end
                    D.counts(k)   = st.CondCounts(r,2);
                    D.rejected(k) = st.CondCounts(r,3);
                    nGood = st.CondCounts(r,1);
                    if nGood < 1, continue; end
                    m = st.Mean(r,:);
                    if wantBand
                        e = mabr.metrics.band_from_stats(st.SD(r,:),nGood, ...
                            obj.ErrorBand,obj.ConfidenceLevel);
                    end
                else
                    if k <= numel(G.stimList), sel = S.stimIdx == G.stimList(k);
                    else,                      sel = true(size(S.stimIdx));
                    end
                    D.counts(k)   = nnz(sel);
                    D.rejected(k) = nnz(sel & S.bad);
                    good = sel & ~S.bad;
                    % Every sweep of this condition rejected so far: there is
                    % no mean to show, and a flat line at zero would be a lie.
                    if ~any(good), continue; end
                    m = mean(S.Y(good,:),1);
                    if wantBand
                        e = mabr.metrics.error_band(S.Y(good,:), ...
                            obj.ErrorBand,obj.ConfidenceLevel);
                    end
                end
                D.M(k,:) = mabr.ui.LivePlot.postprocess(m,S.t,S.opts);
                if ~wantBand, continue; end
                % Smoothed with the mean it is drawn around, so the two follow
                % the same curve. NOT detrended: a detrend moves a mean, it
                % does not change a spread.
                if S.opts.SmoothSpan > 0, e = movmean(e,S.opts.SmoothSpan); end
                D.E(k,:) = e;
            end
            D.A = abs(D.M);
            % A band that describes the MEAN -- its standard error, or a
            % confidence interval for it -- is part of the thing being drawn
            % and has to be framed. An SD band is not: it describes a single
            % SWEEP, which on an ABR is tens of times the average, so folding
            % it into the scale would squash every mean to a flat line. It is
            % drawn and left to run off the axes, which is exactly the
            % statement it was switched on to make.
            if any(strcmp(obj.ErrorBand,{'sem','ci'}))
                ok = isfinite(D.E);
                D.A(ok) = D.A(ok) + D.E(ok);
            end
        end

        function yl = meanLimits(obj,A,scale)
            % One limit per mean axes, in display units, from A -- the mean
            % plus its band, so a band is framed rather than clipped. Overlaid
            % means share an axes and so cannot be scaled individually --
            % 'each' collapses to 'common' there rather than silently picking
            % one stimulus.
            n = size(A,1);
            switch obj.AmpMode
                case 'manual'
                    yl = repmat(obj.ManualLimit*scale.mult,1,n);
                case 'each'
                    if numel(obj.axMean) > 1
                        yl = max(A,[],2).'*scale.mult;
                    else
                        yl = repmat(max(A(:))*scale.mult,1,n);
                    end
                otherwise
                    yl = repmat(max(A(:))*scale.mult,1,n);
            end
            yl(~isfinite(yl) | yl == 0) = 1;
        end

        function setXLim(obj,ax,t)
            % Clamp the requested time base to what was actually recorded: the
            % window can be widened past the extracted sweep, and an axis
            % showing empty space either side reads as missing data.
            xl = obj.TimeBase;
            xl(1) = max(xl(1),t(1));
            xl(2) = min(xl(2),t(end));
            if ~(xl(2) > xl(1)), xl = [t(1) t(end)]; end
            ax.XLim = xl;
        end

        function setLimits(obj,ax,t,ylim_,pad)
            % pad defaults to 1.1 -- headroom above a limit taken straight
            % from the data, so a peak is not drawn on the axes edge. A caller
            % passing a limit that already stands clear of its data
            % (latestLimit) passes 1.
            if nargin < 5, pad = 1.1; end
            obj.setXLim(ax,t);
            if ~isfinite(ylim_) || ylim_ == 0, ylim_ = 1; end
            ax.YLim = [-pad pad]*ylim_;
        end

        function lim = latestLimit(obj,peak)
            % The +/- limit for the latest-sweep axes, in VOLTS, quantized to
            % the LatestLadder rungs and hysteretic on the way down. Called
            % once per render and the only thing that moves that axis --
            % nothing else writes LatestLim.
            if ~isfinite(peak) || peak <= 0
                % Nothing to scale to (an empty or all-NaN sweep). Leave the
                % ruler where it is rather than collapsing it: the next real
                % sweep is about to be measured against it.
                lim = obj.LatestLim; return
            end
            want = mabr.ui.LivePlot.ladderStep(peak);
            if want > obj.LatestLim
                obj.LatestLim    = want;   % never clip: step up at once
                obj.LatestShrink = 0;
            elseif want < obj.LatestLim
                obj.LatestShrink = obj.LatestShrink + 1;
                if obj.LatestShrink >= obj.LatestShrinkHold
                    obj.LatestLim    = want;
                    obj.LatestShrink = 0;
                end
            else
                obj.LatestShrink = 0;      % the rung still fits: start over
            end
            lim = obj.LatestLim;
        end

        function lim = dataLimit(obj)
            % The +/- limit the mean axes are currently using, in VOLTS -- what
            % "Manual" seeds itself from.
            lim = 0;
            if isempty(obj.Last), return; end
            D   = obj.stimulusMeans(obj.Last,obj.resolveGrouping(obj.Last));
            lim = max(D.A(:));
            if ~isfinite(lim) || lim == 0, lim = obj.ManualLimit; end
        end

        function s = currentScale(obj)
            % The unit the axes are labelled in right now, so the manual field
            % and its unit caption agree with them.
            if strcmp(obj.AmpMode,'manual')
                s = obj.pickScale(obj.ManualLimit);
            else
                s = obj.pickScale(obj.dataLimit());
            end
        end

        function txt = latestTitle(~,S,G,counts)
            done = sum(counts);
            if isnan(S.target), sweeps = sprintf('%d sweeps',done);
            else,               sweeps = sprintf('%d / %d sweeps',done,S.target);
            end
            % Name the condition the latest sweep belongs to only when the run
            % holds more than one -- otherwise it just repeats the axes below.
            if numel(G.stimList) > 1
                k = find(G.stimList == S.latestStim,1);
                if ~isempty(k)
                    txt = sprintf('Latest — %s   (%s)',G.labels{k},sweeps);
                    return
                end
            end
            txt = sprintf('Latest sweep   (%s)',sweeps);
        end

        function txt = overlayTitle(~,G,counts,rejected)
            done = sum(counts) - sum(rejected);
            if numel(G.stimList) > 1
                txt = sprintf('Means — %d stimuli, %d sweeps averaged', ...
                    numel(G.stimList),done);
            elseif ~isempty(G.named) && G.named(1)
                % A blocked run is one condition, and the axes below is the
                % only thing in the window that could say WHICH -- but only
                % where the parameters actually named it. A fallback label is
                % either the ID (already on the file this becomes) or the
                % placeholder 'Stimulus 1', and neither is worth a title.
                txt = sprintf('%s — mean of %d sweeps',G.labels{1},done);
            else
                txt = sprintf('Mean of %d sweeps',done);
            end
        end

        function showArtifacts(obj,nBad,nTotal)
            % Silent when nothing has been rejected: an always-present "0
            % rejected" is noise the eye learns to skip, and the point of the
            % readout is that it appears the moment it matters.
            if ~isgraphics(obj.artifactText), return; end
            if nBad < 1
                obj.artifactText.String = '';
            else
                obj.artifactText.String = sprintf('%d rejected (%.0f%%)', ...
                    nBad,100*nBad/max(1,nTotal));
            end
        end

        function applyFilterText(obj)
            if isempty(obj.axLatest) || ~isgraphics(obj.axLatest), return; end
            subtitle(obj.axLatest,obj.FilterText,'FontWeight','normal', ...
                'FontAngle','italic','Color',[0.45 0.45 0.45]);
        end

        % --- Parameter-aware grouping ----------------------------------------
        function G = resolveGrouping(obj,S)
            % Work out, from this run's stimuli and their parameters, the order
            % to lay the means out in, what to call each, which group it
            % belongs to, and what colour it gets. Recomputed on every render
            % rather than cached at update(): GroupBy and Layout can change
            % between sweeps, and the answer depends on both.
            G    = mabr.ui.LivePlot.emptyGroup();
            list = S.stimList(:)';
            n    = numel(list);
            if n == 0, return; end

            P    = S.params;
            vary = mabr.ui.LivePlot.varyingCols(P,n);
            G.paramChoices = P.Names(vary);
            gCol = obj.pickGroupCol(P,vary);
            if gCol > 0, G.groupName = P.Names{gCol}; end

            % --- order --------------------------------------------------------
            if isempty(vary)
                order = 1:n;                    % nothing to sort by: as given
            else
                cols = vary;
                if gCol > 0, cols = [gCol vary(vary ~= gCol)]; end
                [~,order] = sortrows(P.Values(:,cols));
                order = order(:)';
            end
            G.order    = order;
            G.stimList = list(order);

            % --- labels -------------------------------------------------------
            % `named` records which labels the PARAMETERS produced, as opposed
            % to the caller's fallback -- the difference between naming a
            % condition and repeating a stimulus ID (or, with no info at all,
            % the placeholder 'Stimulus 1', which is worth saying nowhere).
            G.labels      = cell(1,n);
            G.shortLabels = cell(1,n);
            G.named       = false(1,n);
            within = vary(vary ~= gCol);
            for k = 1:n
                r   = order(k);
                lab = mabr.ui.LivePlot.paramText(P,r,vary);
                G.named(k)  = ~isempty(lab);
                if isempty(lab), lab = S.labels{r}; end
                G.labels{k} = lab;
                G.shortLabels{k} = '';
                if gCol > 0 && ~isempty(within)
                    G.shortLabels{k} = mabr.ui.LivePlot.paramText(P,r,within);
                end
                if isempty(G.shortLabels{k}), G.shortLabels{k} = G.labels{k}; end
            end

            % --- groups -------------------------------------------------------
            if gCol > 0
                gv = P.Values(order,gCol);
                % `order` already sorted by this column, so unique's ascending
                % answer runs left to right across the columns of a grid.
                [uv,~,gi] = unique(gv);
                G.group       = gi(:)';
                G.nGroups     = numel(uv);
                G.groupLabels = cell(1,G.nGroups);
                for j = 1:G.nGroups
                    G.groupLabels{j} = mabr.ui.LivePlot.paramValueText(P,gCol,uv(j));
                end
            else
                G.group = ones(1,n); G.nGroups = 1; G.groupLabels = {''};
            end

            G.within = zeros(1,n);
            for j = 1:G.nGroups
                sel = find(G.group == j);
                G.within(sel) = 1:numel(sel);   % ascending in the within-param
            end

            G.colors = mabr.ui.LivePlot.seriesColors(G);
            G.mode   = obj.Layout;
            % One condition is one axes whatever the setting says: a grid of a
            % single tile and a stack of a single trace are both just the mean.
            if n < 2, G.mode = 'overlay'; end
        end

        function gCol = pickGroupCol(obj,P,vary)
            % Which parameter column groups the run, or 0 for none.
            gCol = 0;
            if isempty(vary) || strcmpi(obj.GroupBy,'none'), return; end
            names = P.Names(vary);

            if ~isempty(obj.GroupBy)
                j = find(strcmpi(names,obj.GroupBy),1);
                if ~isempty(j), gCol = vary(j); return; end
                % Named a parameter this run does not vary: fall through to
                % automatic rather than showing one undivided group. The menu
                % re-derives itself from the run, so this settles by itself.
            end

            % ONE varying parameter is the series itself, not a way of
            % dividing it -- grouping by it would put every condition in a
            % group of one and destroy exactly the comparison it is for.
            if numel(vary) < 2, return; end

            j = find(strcmpi(names,'Frequency'),1);
            if ~isempty(j), gCol = vary(j); return; end

            % Otherwise the coarsest dimension: fewest distinct values, so the
            % grid comes out wide and short rather than one column per level.
            nu = zeros(1,numel(vary));
            for k = 1:numel(vary)
                v     = P.Values(:,vary(k));
                nu(k) = numel(unique(v(~isnan(v))));
            end
            [~,k] = min(nu);
            gCol  = vary(k);
        end
    end

    % =====================================================================
    methods (Static, Access = private)
        function [idx,list,labels] = resolveStimuli(info,nSweeps)
            % Which stimulus evoked each sweep, which stimuli to lay out, and
            % what to call them. Absent info means one unnamed condition, which
            % is the old single-mean view.
            idx = ones(1,nSweeps);
            if isfield(info,'StimIndex') && ~isempty(info.StimIndex)
                v = double(info.StimIndex(:)');
                k = min(numel(v),nSweeps);
                idx(1:k) = v(1:k);
                % More onsets recorded than the schedule planned should not
                % happen; if it does, the extras belong with the last one
                % rather than inventing a condition for them.
                if k < nSweeps, idx(k+1:end) = v(k); end
            end

            if isfield(info,'Stimuli') && ~isempty(info.Stimuli)
                list = double(info.Stimuli(:)');
            else
                list = unique(idx,'stable');
            end

            labels = cell(1,numel(list));
            given  = {};
            if isfield(info,'Labels') && iscell(info.Labels), given = info.Labels; end
            for k = 1:numel(list)
                if k <= numel(given) && ~isempty(given{k})
                    labels{k} = char(string(given{k}));
                else
                    labels{k} = sprintf('Stimulus %d',list(k));
                end
            end
        end

        function P = resolveParams(info,nStim)
            % Normalize info.Params. Anything that does not line up with the
            % stimulus list is DROPPED rather than half-used: mislabelling a
            % condition is worse than not naming its parameters at all.
            P = struct('Names',{{}},'Values',zeros(nStim,0), ...
                       'Varying',false(1,0),'Units',{{}});
            if ~isfield(info,'Params') || ~isstruct(info.Params) ...
                    || ~isscalar(info.Params), return; end
            Q = info.Params;
            if ~isfield(Q,'Names') || ~isfield(Q,'Values'), return; end
            if isempty(Q.Names) || isempty(Q.Values), return; end

            names = cellstr(Q.Names);
            names = names(:)';
            V     = double(Q.Values);
            if size(V,1) ~= nStim || size(V,2) ~= numel(names), return; end

            units = repmat({''},1,numel(names));
            if isfield(Q,'Units') && numel(Q.Units) == numel(names)
                u = cellstr(Q.Units);
                units = u(:)';
            end

            % Which parameters are informative: the caller's answer where it
            % gave one (see above -- it knows the experiment, this view only
            % sees a run), otherwise whatever differs across the stimuli here.
            varying = false(1,numel(names));
            for j = 1:numel(names)
                v = V(:,j);
                v = v(~isnan(v));
                varying(j) = numel(unique(v)) > 1;
            end
            if isfield(Q,'Varying') && numel(Q.Varying) == numel(names)
                varying = logical(Q.Varying(:)');
            end

            P.Names   = names;
            P.Values  = V;
            P.Varying = varying;
            P.Units   = units;
        end

        function vary = varyingCols(P,n)
            % The informative parameter columns -- the dimensions the
            % experiment varies. A parameter constant across the whole bank
            % names every condition identically and is only clutter, so it
            % never reaches a label; resolveParams settled which is which.
            vary = zeros(1,0);
            if isempty(P.Names) || size(P.Values,1) ~= n, return; end
            vary = find(P.Varying(:)');
        end

        function s = paramValueText(P,col,v)
            % One parameter value as it is written on a label. Frequency and
            % Level carry the units the whole toolbox fixes for them (kHz, dB
            % -- see mabr.data.io.buildFilename and mabr.stim.fromStimgen);
            % anything else is named rather than given a unit MABR would be
            % guessing at.
            if isnan(v), s = ''; return; end
            u = '';
            if col <= numel(P.Units), u = P.Units{col}; end
            if isempty(u), s = sprintf('%s %g',P.Names{col},v);
            else,          s = sprintf('%g %s',v,u);
            end
        end

        function s = paramText(P,row,cols)
            parts = cell(1,numel(cols));
            for j = 1:numel(cols)
                parts{j} = mabr.ui.LivePlot.paramValueText(P,cols(j),P.Values(row,cols(j)));
            end
            parts = parts(~cellfun(@isempty,parts));
            s = strjoin(parts,', ');
        end

        function G = emptyGroup()
            G = struct('mode','overlay','order',[],'stimList',[], ...
                'labels',{{}},'shortLabels',{{}},'named',false(1,0), ...
                'group',[],'within',[],'nGroups',1,'groupLabels',{{''}}, ...
                'groupName','','colors',zeros(0,3),'paramChoices',{{}});
        end

        function n = labelWidthChars(ax)
            % How long an axes' longest y tick label is, in characters. The
            % change detector behind gutterKey, and deliberately not a width
            % in pixels: the point is to notice when a label could no longer
            % fit the room it has, not to measure it -- measuring is what
            % TightInset is for, and it costs a graphics query.
            n = 0;
            if isempty(ax) || ~isgraphics(ax), return; end
            lab = ax.YTickLabel;
            if isempty(lab), return; end
            if ischar(lab), lab = cellstr(lab); end
            n = max(cellfun(@numel,lab));
        end

        function k = layoutKey(G)
            % Everything the built axes depend on -- the arrangement, the
            % conditions in it, and what they are called. Not the colours or
            % the short labels: those are written on every render anyway.
            k = sprintf('%s|%s|%s|%s|%s',G.mode,mat2str(G.stimList(:).'), ...
                strjoin(G.labels,'>'),mat2str(G.group(:).'),mat2str(G.within(:).'));
        end

        function m = gridTopMask(G)
            % The topmost occupied tile of each column -- the one that carries
            % the group's name above its own title.
            n = numel(G.stimList);
            m = false(1,n);
            for k = 1:n
                m(k) = G.within(k) == max(G.within(G.group == G.group(k)));
            end
        end

        function c = seriesColors(G)
            % Ungrouped, every condition gets its own colour, as it always
            % has. GROUPED, colour has a second job: it has to say which
            % conditions belong to one series. So each group takes a hue and
            % its members ramp from pale to full along the within-group
            % parameter -- a level series looks like a level series, and two
            % frequencies never trade colours between refreshes.
            n = numel(G.stimList);
            if G.nGroups < 2 || n < 2
                c = mabr.ui.LivePlot.stimColors(max(1,n));
                return
            end
            base = mabr.ui.LivePlot.stimColors(G.nGroups);
            c    = zeros(n,3);
            for j = 1:G.nGroups
                sel = find(G.group == j);
                m   = numel(sel);
                for r = 1:m
                    if m < 2, s = 1; else, s = 0.40 + 0.60*(r-1)/(m-1); end
                    c(sel(r),:) = 1 - s*(1 - base(j,:));
                end
            end
        end

        function [x0,y1,wGap,hGap,w,h] = tileGeometry(cols,rows,yTop,lGut,cGut)
            % One tile grid, shared by every multi-axes layout: the left edge,
            % the top edge, the gaps, and a tile size. The GAPS shrink as the
            % grid deepens rather than the tiles vanishing -- a cramped grid is
            % still a grid, one whose tiles have gone to zero height is not.
            %
            % lGut is the room the labels of the FIRST column need and cGut
            % what the labels of the ones after it need (nothing, wherever
            % those tiles repeat their neighbour's scale and go unlabelled).
            % Both are measured -- see fitLabelGutters -- and cGut is a FLOOR
            % under the plain visual gap between tiles, never a replacement
            % for it: labels that need no room must still not touch.
            if nargin < 4 || isempty(lGut), lGut = 0.075; end
            if nargin < 5 || isempty(cGut), cGut = 0;     end
            x1 = 0.985; y0 = 0.10; y1 = yTop;
            cols = max(1,cols); rows = max(1,rows);
            x0   = min(max(lGut,mabr.ui.LivePlot.MinGutter), ...
                       mabr.ui.LivePlot.MaxGutter);
            wGap = max(min(0.055,(x1-x0)/(3*cols)),cGut);
            % A tile keeps at least half of its own column whatever the labels
            % ask for: a gutter that has eaten the plot has answered the wrong
            % question.
            wGap = min(wGap,0.5*(x1-x0)/cols);
            hGap = min(0.030,(y1-y0)/(2*rows));
            % The columns tile the whole width, the gaps sitting BETWEEN them,
            % so the last column still ends at x1 however wide a gutter the
            % labels turned out to need.
            w = (x1 - x0 - (cols-1)*wGap)/cols;
            h = (y1-y0)/rows - hGap;
        end

        function c = stimColors(n)
            % lines() only holds seven distinct colours before it repeats, and
            % two conditions sharing a colour on one overlaid axes is worse
            % than no colour at all. Past that, a continuous map: a bank is
            % almost always an ordered series (levels, frequencies), so the
            % gradient carries the ordering the repeat would have destroyed.
            if n <= 7
                c = lines(7);
                c = c(1:n,:);
            else
                c = turbo(n+2);
                c = c(2:end-1,:);   % drop the near-black ends
            end
        end

        function m = postprocess(m,tms,opts)
            if opts.SmoothSpan > 0, m = movmean(m,opts.SmoothSpan); end
            if opts.DetrendPoly == 0
                m = m - mean(m);
            elseif opts.DetrendPoly > 0
                [p,~,mu] = polyfit(tms,m,opts.DetrendPoly);
                m = m - polyval(p,tms,[],mu);
            end
        end

        function opts = resolveOpts(info)
            % Intermixed is left EMPTY rather than false when the caller
            % says nothing: 'not stated' and 'stated to be blocked' are
            % different answers, and corrVisible falls back on the run's own
            % stimulus count for the first.
            opts = struct('DetrendPoly',-1,'SmoothSpan',0,'Intermixed',[]);
            if isfield(info,'DetrendPoly'), opts.DetrendPoly = info.DetrendPoly; end
            if isfield(info,'SmoothSpan'),  opts.SmoothSpan  = info.SmoothSpan;  end
            if isfield(info,'Intermixed'),  opts.Intermixed  = info.Intermixed;  end
        end

        function v = ladderStep(x)
            % The smallest 1-2-5-decade value at or above x -- the rungs the
            % latest-sweep axes is allowed to stand on. x is assumed finite
            % and positive; latestLimit is the only caller and checks.
            rungs = mabr.ui.LivePlot.LatestLadder;
            d = floor(log10(x));
            m = x / 10^d;                     % in [1,10)
            % The tolerance keeps a peak that IS a rung on that rung: the
            % division above is not exact, and 2e-6 landing on 5e-6 would be
            % a visible jump for a rounding error.
            k = find(rungs >= m - 1e-9,1);
            if isempty(k), k = numel(rungs); end
            v = rungs(k) * 10^d;
        end

        function s = pickScale(maxAbs)
            % Choose a sensible voltage unit for display. `unit` is TeX for an
            % axis label, `plain` is what a uicontrol caption can render.
            if ~isfinite(maxAbs) || maxAbs == 0
                s = struct('mult',1e6,'unit','\muV','plain','uV'); return
            end
            if     maxAbs >= 1e-1, s = struct('mult',1,   'unit','V',    'plain','V');
            elseif maxAbs >= 1e-4, s = struct('mult',1e3, 'unit','mV',   'plain','mV');
            elseif maxAbs >= 1e-7, s = struct('mult',1e6, 'unit','\muV', 'plain','uV');
            else,                  s = struct('mult',1e9, 'unit','nV',   'plain','nV');
            end
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end
