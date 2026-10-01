classdef TraceOrganizer < handle
% mabr.ui.TraceOrganizer  Interactive stacked-waveform viewer.
%
%   A rebuilt, self-contained version of the legacy abr.traces.Organizer. It
%   stacks mean-sweep traces (one per acquired block), labels each with its
%   stimulus ID, and lets you resize, respace, reorder, drag, and mark them.
%   The broken legacy Group/Marker classes and the user32.dll mouse hook are
%   gone; interaction uses standard figure callbacks and the fixed
%   mabr.ui.Marker.
%
%       to = mabr.ui.TraceOrganizer();
%       to.addBlock(block);        % add a finalized mabr.data.Block
%       to.listenTo(controller);   % ...or let blocks arrive as they complete
%       to.show();
%
%   listenTo subscribes to an mabr.ui.AcqController's BlockReady event, so a
%   view left open during a run gains a trace as each block is finalized
%   instead of only when the organizer is reopened.
%
%   Every command is reachable three ways -- the menu bar, the right-click
%   context menu, and the keyboard -- so nothing is discoverable only by
%   memorization. Press F1 in the figure for the shortcut list.
%
%   Amplitude commands act on the selection, or on every trace when nothing
%   is selected. Click a trace (or its label) to select it; shift- or
%   ctrl-click to extend the selection.
%
%   DOUBLE-CLICK a trace to open it in mabr.ui.TraceInspector: one waveform
%   at full size, in its own units, with search windows and draggable
%   markers for measuring wave latencies. The stack is the wrong place to
%   measure anything -- every trace there is normalized to a shared scale so
%   the series stays legible -- so the peaks are picked in the inspector and
%   transferred back to the trace when it is applied.
%
%   Every mean trace can carry a shaded ERROR BAND behind it, in its own
%   colour, from the sweeps the mean was taken over -- the Band menu picks
%   which statistic (none, +/-1 SD, +/-1 SEM, a t-based confidence interval,
%   or a percentile bootstrap interval of the mean; see
%   mabr.metrics.band_edges). The sweeps travel with each trace, so the
%   statistic is a question a view loaded from a .torg can still be asked,
%   and a trace added without them (addTrace, or a version-1 file) simply
%   carries no band. The band is deliberately left OUT of the shared
%   normalization: an SD band is many times the mean it describes, and
%   folding it into the scale would flatten the series it was switched on to
%   help read. Use the spacing controls if the bands crowd each other.
%
%   The stack can be ORGANIZED BY STIMULUS PARAMETER -- each trace carries
%   the parameters its block was recorded under (Frequency, Level, ...; see
%   mabr.ui.Trace.parameters) -- from the Organize menu or by property:
%
%       to.SplitBy = 'Frequency';          % one panel per frequency
%       to.setOrder('Level','descending'); % loudest at the top of each
%       to.LabelBy = 'params';             % '60 dB' rather than the ID
%
%   SplitBy gives every value of one parameter a panel of its own, side by
%   side (wrapping to more rows when the window is too narrow for one), all
%   on one amplitude scale and one time axis, so a column compares with its
%   neighbour as directly as two traces in one stack do. OrderBy (with
%   OrderDirection, read in parallel the way mabr.stim.Schedule reads its
%   pair) sorts every stack, top to bottom, most significant parameter
%   first; ties keep the order they had. LabelBy = 'params' labels each
%   trace with the parameters that vary across the traces held, less the
%   one the panels are titled with. A name no trace carries is kept but does
%   nothing, so a setting chosen for one session survives traces that lack
%   it. While a split or an order is in force the stacks are kept even: a
%   trace that arrives during a run goes straight to its place, and a trace
%   dragged or moved by hand lands where it is dropped -- which makes the
%   order manual (OrderBy is cleared, and the status line says so).
%
%   Overlap: two or more selected traces can be laid onto one baseline
%   (overlapTraces) to compare shapes. They keep that slot through restacking,
%   organizing and saving (Trace.Group) until separateTraces, or until one is
%   dragged out. The selected member is drawn in front; stepOverlap (Tab), or
%   clicking the selected trace again, selects the next one under it.
%
%     Up / Down            amplitude larger / smaller
%     Shift+Up / Down      spacing wider / narrower
%     Ctrl+Up / Down       move selected trace up / down the stack
%     0                    reset amplitude to 1x
%     n                    toggle per-trace vs. common normalization
%     r                    restack evenly in current visual order
%     a / Escape           select all / none
%     o / u                overlap the selected traces / separate them
%     Tab / Shift+Tab      step the selection through an overlap group
%     l                    toggle stimulus ID labels
%     p / c                mark peaks / clear markers
%     b                    cycle the error band
%     g                    cycle the split (none, then each parameter)
%     i                    inspect the selected trace (or double-click it)
%     h / Delete           hide / remove selected traces
%     Ctrl+N               session notes
%     Ctrl+S / Ctrl+O      save / load the view
%
%   The toolbar's notepad button (and Ctrl+N) opens the same rig notebook the
%   main window carries -- listenTo adopts the running session's store, so a
%   note written here about a trace lands in the same log, and in the same
%   files, as one written there. A .torg carries the notebook with it.
%
%   saveView writes a .torg file holding the waveforms plus the complete
%   display state -- gains, offsets, order, colours, markers, spacing,
%   normalization mode, axis limits, and the split/order/label settings --
%   so loadView reproduces the view exactly as it was saved.
%
% Daniel Stolzberg (c) 2019-2026

    properties
        YSpacing (1,1) double {mustBePositive,mustBeFinite} = 1;
        YScaling (1,1) double {mustBePositive,mustBeFinite} = 0.8;
        Colors   (:,3) double = lines(7);
        NormalizeEach (1,1) logical = false;  % scale each trace to its own peak
        ShowLabels    (1,1) logical = true;

        % Which error band the traces carry: 'none' | 'std' | 'sem' | 'ci' |
        % 'boot' (mabr.metrics.band_edges). ConfidenceLevel is used by both
        % interval statistics, so picking a level from the Band menu and then
        % switching between 'ci' and 'boot' compares the two at one level.
        ErrorBand       (1,:) char   = 'none';
        ConfidenceLevel (1,1) double = 0.95;
        BootReps        (1,1) double = 1000;  % resamples for 'boot'

        % Organizing by stimulus parameter (see the class help). SplitBy is
        % one parameter name, '' for a single stack. OrderBy is a cellstr
        % row, most significant first, {} for the order the traces were
        % arranged in by hand; OrderDirection is read in parallel with it --
        % one direction applies to every name, and a name with none of its
        % own is 'ascending' (smallest at the top). LabelBy is 'id' (the
        % stimulus ID, as always) or 'params'. Every setter re-arranges and
        % redraws, so a script and the Organize menu do the same thing.
        SplitBy         (1,:) char   = '';
        OrderBy                      = {};
        OrderDirection               = {'ascending'};
        LabelBy         (1,:) char   = 'id';
    end

    properties (SetAccess = private)
        Traces (1,:) mabr.ui.Trace = mabr.ui.Trace.empty;

        % The rig notebook these traces belong to (mabr.data.SessionNotes).
        % A standalone organizer makes its own; listenTo (or useNotes) swaps in
        % the live session's, so the notes button here opens the SAME log the
        % main window's does rather than a second one nobody would think to
        % check. NotesOwned records which of the two it is, because it decides
        % whether loading a .torg may overwrite the log -- see loadView.
        Notes      mabr.data.SessionNotes
        NotesOwned (1,1) logical = true;
    end

    properties (Constant, Access = private)
        GainStep    = 1.25;   % multiplicative step for larger/smaller
        SpacingStep = 1.25;
        FileFilter  = {'*.torg','MABR Trace Organizer view (*.torg)'};
        % 3 adds View.Notes; 4 adds the error-band settings (and each trace's
        % Sweeps, so the statistic can be changed after a load). Older files
        % simply lack the fields and load as before -- loadView reads every
        % optional field with isfield for exactly this reason. 5 adds the
        % SplitBy/OrderBy/OrderDirection/LabelBy settings and each trace's
        % stimulus Params.
        FileVersion = 5;
        CILevels    = [0.90 0.95 0.99];   % the levels the Band menu offers
        OrderDirections = {'ascending','descending'};
        % The narrowest a panel may be drawn before the panels wrap onto
        % another row, and the least room left of one for its labels, in
        % pixels.
        MinPanelPx  = 110;
        MinGutterPx = 30;
    end

    properties (SetAccess = private, Transient)
        Figure      % readable so callers can export or annotate the view
        Axes        % the first panel (the only one, unless the view is split)
        % One axes per panel, left to right then top to bottom; the first is
        % always Axes. A single stack is one panel.
        PanelAxes
    end

    properties (Access = private, Transient)
        Toolbar
        ContextMenu
        StatusText      % the status line across the top of the figure
        dragTrace   = [];   % the mabr.ui.Trace being dragged (a handle, not an
                            % index: a block landing mid-drag may reorder)
        dragStartY  = 0;
        dragStartOffset = 0;
        dragMoved   = false;
        cycleOnRelease = false;   % a plain click on the one selected overlapped trace
        FigTag (1,:) char = '';
        BlockListener   % listener on an AcqController's BlockReady event
        Inspector       % mabr.ui.TraceInspector, at most one at a time
        NotesView       % mabr.ui.Notes, the button-and-window form
        % What the traces on screen were last drawn with: the per-trace
        % amplitude scale, and the widest label in pixels (NaN = measure
        % again). They let a trace added mid-session be drawn on its own
        % (plotAdded) while every other trace still looks exactly as a full
        % redraw would leave it. plotAll and fitLabelMargin refresh both.
        PlotScale    = zeros(1,0)
        LabelWidthPx = NaN

        % Which traces were drawn where, with what offset and caption -- the
        % rest of what lets plotAdded draw only what a new trace changed when
        % the stack is organized and the trace lands in the middle of it.
        % PlotScale is aligned with DrawnTraces.
        DrawnTraces   = mabr.ui.Trace.empty
        DrawnOffsets  = zeros(1,0)
        DrawnCaptions = {}
        DrawnPanels   = zeros(1,0)

        % The arrangement in force (arrange): each trace's panel, aligned
        % with Traces; each panel's title; the parameter table it came from
        % (aligned with Traces too); the split and the order keys actually
        % applied, which are the settings less any name no trace carries.
        PanelIndex   = zeros(1,0)
        PanelLabels  = {''}
        PanelKey     = ''           % what PanelAxes were built for
        ParamNames   = {}
        ParamValues  = zeros(0,0)
        SplitName    = ''
        OrderKeys    = struct('Name',{},'Direction',{})
        MenuParamKey = NaN          % the parameters the Organize menus list
        Suspended (1,1) logical = false   % setters defer organize() while set
    end

    methods
        function obj = TraceOrganizer()
            obj.FigTag = sprintf('MABR_TRACEORG_%d',round(rand*1e9));
            % Its own notebook until told otherwise: an organizer opened on its
            % own (to read a .torg back) is not part of any session, and the
            % notes in that file are the ones it should show.
            obj.Notes = mabr.data.SessionNotes();
        end

        function delete(obj)
            obj.stopListening();
            obj.closeInspector();
            try, delete(obj.NotesView); end %#ok<TRYNC>
            delete(obj.Traces);
            try, delete(obj.Figure); end %#ok<TRYNC>
        end

        function tf = isvalidView(obj)
            tf = ~isempty(obj.Figure) && isgraphics(obj.Figure);
        end

        % --- Error band -----------------------------------------------------
        function set.ErrorBand(obj,v)
            obj.ErrorBand = validatestring(v,{'none','std','sem','ci','boot'}, ...
                'mabr.ui.TraceOrganizer','ErrorBand');
            obj.bandChanged();
        end

        function set.ConfidenceLevel(obj,v)
            assert(isnumeric(v) && isscalar(v) && v > 0 && v < 1, ...
                'mabr:ui:TraceOrganizer:conf', ...
                'ConfidenceLevel must be a probability strictly between 0 and 1.');
            obj.ConfidenceLevel = double(v);
            obj.bandChanged();
        end

        function set.BootReps(obj,v)
            assert(isnumeric(v) && isscalar(v) && v >= 2 && isfinite(v), ...
                'mabr:ui:TraceOrganizer:bootReps', ...
                'BootReps must be a finite count of at least 2.');
            obj.BootReps = round(double(v));
            obj.bandChanged();
        end

        function setErrorBand(obj,mode,conf)
            % Pick the error band, and its level in the same call so the band
            % is never briefly drawn at the level just moved away from.
            if nargin >= 3 && ~isempty(conf), obj.ConfidenceLevel = conf; end
            obj.ErrorBand = mode;

            % A band that cannot be drawn says why: the sweeps only travel
            % with a trace added from a finalized block (or restored from a
            % version-4 .torg), so an older view has a mean and nothing to
            % put a band around, which is not the same as a band of nothing.
            n = numel(obj.Traces);
            if strcmp(obj.ErrorBand,'none') || n == 0
                obj.status(sprintf('Error band: %s.',obj.bandDescription()));
                return
            end
            k = nnz(arrayfun(@(t) t.hasBand(),obj.Traces));
            if k == 0
                obj.status(sprintf(['Error band %s: no sweeps are stored with ' ...
                    'these traces, so none can be drawn.'],obj.bandDescription()));
            elseif k < n
                obj.status(sprintf('Error band %s on %d of %d trace(s); the rest have no sweeps.', ...
                    obj.bandDescription(),k,n));
            else
                obj.status(sprintf('Error band: %s.',obj.bandDescription()));
            end
        end

        % --- Organizing by stimulus parameter -------------------------------
        function set.SplitBy(obj,v)
            v = mabr.ui.TraceOrganizer.nameArg(v,'SplitBy');
            if strcmpi(v,'none'), v = ''; end
            obj.SplitBy = v;
            obj.organize();
        end

        function set.OrderBy(obj,v)
            obj.OrderBy = mabr.stim.Schedule.textList(v,'OrderBy');
            obj.organize();
        end

        function set.OrderDirection(obj,v)
            % Refused rather than read as 'ascending': a misspelt direction
            % that quietly sorted the other way would put the series upside
            % down without a word.
            v = lower(mabr.stim.Schedule.textList(v,'OrderDirection'));
            if isempty(v), v = {'ascending'}; end
            bad = ~ismember(v,mabr.ui.TraceOrganizer.OrderDirections);
            assert(~any(bad),'mabr:ui:TraceOrganizer:orderDirection', ...
                'Unknown order direction "%s". Expected ascending or descending.', ...
                strjoin(v(bad),'", "'));
            obj.OrderDirection = v;
            obj.organize();
        end

        function set.LabelBy(obj,v)
            obj.LabelBy = validatestring(v,{'id','params'}, ...
                'mabr.ui.TraceOrganizer','LabelBy');
            obj.organize();
        end

        function setOrder(obj,by,way)
            % Set OrderBy and OrderDirection together, arranging once:
            %   to.setOrder('Level','descending')
            %   to.setOrder({'Frequency','Level'},{'ascending','descending'})
            %   to.setOrder({})                     % manual
            if nargin < 3 || isempty(way), way = {'ascending'}; end
            obj.Suspended = true;
            try
                obj.OrderDirection = way;
                obj.OrderBy        = by;
            catch me
                obj.Suspended = false;
                rethrow(me);
            end
            obj.Suspended = false;
            obj.organize();
        end

        function organize(obj)
            % Re-apply the organization settings to the traces held -- which
            % panel each is in, the order of every stack, what each label
            % reads -- and redraw. Every setter above comes here.
            if obj.Suspended, return; end
            obj.arrange(true);
            if ~obj.isvalidView(), return; end
            obj.syncOrganizeMenus();
            obj.plotAll(false,true);
        end

        function tf = isOrganized(obj)
            % True while a split or an order is set (whether or not any trace
            % carries the parameter named).
            tf = ~isempty(obj.SplitBy) || any(~cellfun(@isempty,obj.OrderBy));
        end

        function txt = statusText(obj)
            % What the status line across the top of the view reads.
            txt = '';
            if ~isempty(obj.StatusText) && isgraphics(obj.StatusText)
                txt = obj.StatusText.String;
            end
        end

        % --- Live updating --------------------------------------------------
        function listenTo(obj,controller)
            % Track an mabr.ui.AcqController: every block it finalizes is added
            % as a trace as soon as it lands, so an open view fills in during a
            % run instead of only when the organizer is reopened. Only one
            % controller is tracked at a time -- calling this again re-points
            % the listener rather than stacking a second one, so re-opening the
            % organizer cannot duplicate traces.
            obj.stopListening();
            if nargin < 2 || isempty(controller) || ~isvalid(controller), return; end
            obj.BlockListener = addlistener(controller,'BlockReady', ...
                @(~,e) obj.onBlockReady(e));
            % Tracking a controller means tracking its session, and the session
            % has a notebook. Adopting it is what makes the notes button here
            % and the one on the main window two views of one log instead of
            % two logs -- see mabr.data.SessionNotes.
            try
                obj.useNotes(controller.Session.Notes);
            catch
                % A controller without a session notebook (an older one, a
                % hand-built stub in a test) keeps this organizer on its own.
            end
        end

        function useNotes(obj,store)
            % Show an external notebook instead of this organizer's own -- the
            % running session's, normally. Every open view of that store stays
            % in step through its NotesChanged event, so nothing here has to
            % push updates anywhere.
            if isempty(store) || ~isa(store,'mabr.data.SessionNotes') || ~isvalid(store)
                return
            end
            % '==' rather than isequal: these are handles, and the question is
            % whether it is the SAME store, not one holding the same notes.
            if ~isempty(obj.Notes) && isvalid(obj.Notes) && obj.Notes == store
                return
            end
            obj.Notes      = store;
            obj.NotesOwned = false;
            % Re-point the view rather than rebuilding it: the toolbar button
            % already holds this handle, and a rebuilt view would leave it
            % opening a deleted one.
            if ~isempty(obj.NotesView) && isvalid(obj.NotesView)
                obj.NotesView.setStore(store);
            end
        end

        function stopListening(obj)
            try, delete(obj.BlockListener); end %#ok<TRYNC>
            obj.BlockListener = [];
        end

        % --- Adding data ----------------------------------------------------
        function addBlock(obj,block)
            % Add the mean sweep of a finalized mabr.data.Block, labelled with
            % the stimulus ID the stimulus package supplied. SweepMean averages
            % only the sweeps that survived artifact rejection, so a trace here
            % never carries a sweep the acquisition threw out.
            try
                m   = block.ADC.SweepMean;
                t   = block.ADC.TimeVector;
                lbl = char(join(string(block.Label),', '));
            catch
                return
            end
            % The sweeps behind that mean, for the error band. Clean rather
            % than every sweep, so the band describes the same sweeps the
            % trace does; a block that cannot supply them (a hand-built one)
            % simply carries no band.
            sweeps = [];
            try
                sweeps = double(block.ADC.CleanSweepData);
            catch
            end
            % Every sweep rejected leaves no mean to draw (SweepMean is all
            % NaN). Say so rather than stacking an invisible trace the user
            % would have to work out the absence of.
            if isempty(m) || ~any(isfinite(m))
                mabr.log.vprintf(0,1,'Trace organizer: skipping "%s" — every sweep was rejected as artifact',lbl);
                return
            end
            sid = '';
            try
                sid = char(string(block.Stim.Meta.ID));
            catch
                % No stimulus metadata (e.g. a hand-built Block) -- fall back
                % to the descriptive label in Trace.DisplayName.
            end
            % The parameters it was recorded under, for organizing the view
            % by -- exactly as the stimulus metadata states them.
            obj.addTrace(m,t,lbl,sid,sweeps, ...
                mabr.ui.TraceOrganizer.blockParams(block));
        end

        function tr = addTrace(obj,data,time,label,stimID,sweeps,params)
            % params: the stimulus parameters, a struct of numeric scalars
            % (name -> value); see mabr.ui.Trace.Params.
            if nargin < 4, label  = ''; end
            if nargin < 5, stimID = ''; end
            if nargin < 6, sweeps = []; end
            if nargin < 7, params = struct(); end
            tr = mabr.ui.Trace(data,time,label,stimID);
            tr.ID = numel(obj.Traces)+1;
            tr.Params = mabr.ui.Trace.cleanParams(params);
            % [nSamples x nSweeps], one row per sample of Data -- anything else
            % is not this trace's sweeps and is dropped rather than banded.
            if ~isempty(sweeps) && size(sweeps,1) == numel(tr.Data)
                tr.Sweeps = double(sweeps);
            end
            if isempty(obj.Traces)
                tr.YOffset = 0;
            else
                tr.YOffset = min([obj.Traces.YOffset]) - obj.YSpacing;
            end
            tr.Color     = obj.Colors(mod(numel(obj.Traces),size(obj.Colors,1))+1,:);
            tr.ShowLabel = obj.ShowLabels;
            if isempty(obj.Traces), obj.Traces = tr; else, obj.Traces(end+1) = tr; end
            % A newcomer ranks after every trace already placed, so in a
            % stack kept in hand-made order it goes to the bottom of its
            % panel; arrange then puts it wherever the settings say.
            obj.PanelIndex(end+1) = max([obj.PanelIndex 0]) + 1;
            obj.computeBands(numel(obj.Traces));
            obj.arrange(true);
            if obj.isvalidView()
                obj.syncOrganizeMenus();
                obj.plotAdded(tr);
            end
        end

        function clear(obj)
            delete(obj.Traces);
            obj.Traces        = mabr.ui.Trace.empty;
            obj.PanelIndex    = zeros(1,0);
            obj.DrawnTraces   = mabr.ui.Trace.empty;
            obj.PlotScale     = zeros(1,0);
            obj.pruneInspector();
            obj.arrange(true);
            if obj.isvalidView()
                cla(obj.Axes);
                obj.syncOrganizeMenus();
                obj.plotAll(false);   % collapses a split view to one panel
            end
        end

        % --- View -----------------------------------------------------------
        function show(obj)
            obj.ensureFigure();
            obj.plotAll(true);
            figure(obj.Figure);
        end

        function refresh(obj)
            % Redraw from the current trace state, keeping the axis limits.
            obj.plotAll(false);
        end

        function toggleVisible(obj,idx)
            if nargin < 2, idx = obj.selectedIndices(); end
            if isempty(idx), obj.status('Select a trace first.'); return; end
            for k = idx(:)', obj.Traces(k).Visible = ~obj.Traces(k).Visible; end
            obj.plotAll(false);
        end

        function idx = selectedIndices(obj)
            if isempty(obj.Traces), idx = []; return; end
            idx = find([obj.Traces.Selected]);
        end

        function idx = targetIndices(obj)
            % Commands act on the selection, or on everything when nothing is
            % selected -- so "make them bigger" works before you have picked.
            idx = obj.selectedIndices();
            if isempty(idx), idx = 1:numel(obj.Traces); end
        end

        function select(obj,idx,extend)
            if nargin < 3, extend = false; end
            if ~extend
                for k = 1:numel(obj.Traces), obj.Traces(k).Selected = false; end
            end
            for k = idx(:)'
                if k >= 1 && k <= numel(obj.Traces)
                    obj.Traces(k).Selected = ~extend || ~obj.Traces(k).Selected;
                end
            end
            obj.plotAll(false);
        end

        % --- Amplitude, spacing, order ---------------------------------------
        function scaleTraces(obj,factor,idx)
            if isempty(obj.Traces), return; end
            if nargin < 3 || isempty(idx), idx = obj.targetIndices(); end
            for k = idx(:)'
                obj.Traces(k).Gain = max(min(obj.Traces(k).Gain*factor,1e4),1e-4);
            end
            obj.plotAll(false);
            obj.status(sprintf('Amplitude x%.3g on %d trace(s).',factor,numel(idx)));
        end

        function resetGain(obj,idx)
            if nargin < 2 || isempty(idx), idx = obj.targetIndices(); end
            for k = idx(:)', obj.Traces(k).Gain = 1; end
            obj.plotAll(false);
            obj.status('Amplitude reset to 1x.');
        end

        function setSpacing(obj,spacing)
            % Set the vertical spacing and restack, keeping the current order.
            if spacing <= 0, return; end
            obj.YSpacing = spacing;
            obj.restack();
        end

        function restack(obj)
            % Space every trace evenly, top to bottom, in current visual order.
            if isempty(obj.Traces), return; end
            if obj.isArranged()
                % Each panel's stack, in the order the settings give it (or
                % its visual order, when that order is manual).
                obj.arrange(true);
                obj.plotAll(false);
                obj.refreshStatus();
                return
            end
            [~,ord] = sort([obj.Traces.YOffset],'descend');
            obj.Traces = obj.Traces(ord);
            obj.pruneGroups(ones(1,numel(obj.Traces)));
            obj.assignSlots(1:numel(obj.Traces));
            obj.plotAll(false);
            obj.refreshStatus();
        end

        % --- Overlap ----------------------------------------------------------
        function overlapTraces(obj,idx)
            % Lay the selected traces onto one baseline, to compare their
            % shapes. They share a slot in the stack -- the others close up
            % around it -- and stay a group (Trace.Group) through restacking,
            % reordering and saving, until separateTraces undoes it.
            if nargin < 2, idx = obj.selectedIndices(); end
            if numel(idx) < 2
                obj.status('Select two or more traces to overlap (click, then shift-click).');
                return
            end
            pan = ones(1,numel(obj.Traces));
            if numel(obj.PanelIndex) == numel(obj.Traces), pan = obj.PanelIndex; end
            if numel(unique(pan(idx))) > 1
                obj.status('Traces in different panels cannot be overlapped; select within one panel.');
                return
            end
            g = max([0 obj.Traces.Group]) + 1;
            top = max([obj.Traces(idx).YOffset]);
            for k = idx(:)'
                obj.Traces(k).Group   = g;
                obj.Traces(k).YOffset = top;
            end
            obj.restack();
            obj.syncMenuChecks();
            obj.status(sprintf(['%d traces overlapped. Tab / Shift+Tab (or clicking the ' ...
                'selected one again) steps through them; u separates.'],numel(idx)));
        end

        function separateTraces(obj,idx)
            % Give overlapped traces a line each again: the selected ones, or
            % every overlapped trace when none is selected. Selecting any one
            % member of a group separates that whole group.
            if nargin < 2 || isempty(idx), idx = obj.selectedIndices(); end
            grouped = [obj.Traces.Group];
            if isempty(grouped) || ~any(grouped > 0)
                obj.status('No traces are overlapped.');
                return
            end
            if isempty(idx)
                gs = unique(grouped(grouped > 0));
            else
                gs = unique(grouped(idx)); gs = gs(gs > 0);
                if isempty(gs), obj.status('The selected traces are not overlapped.'); return; end
            end
            n = 0;
            for k = 1:numel(obj.Traces)
                if any(obj.Traces(k).Group == gs)
                    obj.Traces(k).Group = 0;
                    n = n + 1;
                end
            end
            obj.restack();
            obj.status(sprintf('%d trace(s) separated.',n));
        end

        function stepOverlap(obj,delta)
            % Select the next (delta = +1) or previous overlapped trace in
            % the group of the one selected -- the way to reach a trace that
            % lies under others, which a click cannot. With nothing in an
            % overlap selected, picks up the first group's first trace.
            if isempty(obj.Traces), return; end
            sel = obj.selectedIndices();
            k = [];
            if ~isempty(sel) && obj.Traces(sel(1)).Group > 0, k = sel(1); end
            if isempty(k)
                k = find([obj.Traces.Group] > 0,1);
                if isempty(k), obj.status('No traces are overlapped.'); return; end
                obj.select(k);
                return
            end
            m = obj.groupMembers(k);
            j = find(m == k,1) + delta;
            j = mod(j-1,numel(m)) + 1;
            obj.select(m(j));
            obj.status(sprintf('Overlap: trace %d of %d, %s.',j,numel(m), ...
                obj.Traces(m(j)).DisplayName));
        end

        function selectOverlapGroup(obj)
            % Select every trace overlapped with the selected one(s).
            sel = obj.selectedIndices();
            m = [];
            for k = sel(:)'
                if obj.Traces(k).Group > 0, m = [m obj.groupMembers(k)]; end %#ok<AGROW>
            end
            if isempty(m), obj.status('Select an overlapped trace first.'); return; end
            obj.select(unique(m));
        end

        function m = groupMembers(obj,k)
            % The traces overlapped with trace k (itself included), in stack
            % order, within k's own panel.
            g = obj.Traces(k).Group;
            if g == 0, m = k; return; end
            same = [obj.Traces.Group] == g;
            if numel(obj.PanelIndex) == numel(obj.Traces)
                same = same & obj.PanelIndex == obj.PanelIndex(k);
            end
            m = find(same);
        end

        function pruneGroups(obj,panel)
            % A group is two traces or more in one panel; anything less is a
            % trace on its own line, whatever was left behind in its Group.
            n = numel(obj.Traces);
            if n == 0, return; end
            g = [obj.Traces.Group];
            for k = find(g > 0)
                if sum(g == g(k) & panel(:).' == panel(k)) < 2
                    obj.Traces(k).Group = 0;
                end
            end
        end

        function assignSlots(obj,k)
            % Offsets for the traces at positions k (one panel, top to bottom):
            % an even stack in which consecutive traces of one overlap group
            % share a slot. gatherOrder has already made members consecutive.
            slot = 0; prev = 0;
            for i = 1:numel(k)
                g = obj.Traces(k(i)).Group;
                if g == 0 || g ~= prev, slot = slot + 1; end
                prev = g;
                obj.Traces(k(i)).YOffset = -(slot-1)*obj.YSpacing;
            end
        end

        function shift = labelShift(obj,k)
            % Overlapped traces share a baseline, so their labels would be
            % written over one another; each is nudged to its own share of
            % the slot instead, in stack order.
            shift = 0;
            if obj.Traces(k).Group == 0, return; end
            m = obj.groupMembers(k);
            if numel(m) < 2, return; end
            i = find(m == k,1);
            step = obj.YSpacing/numel(m);
            shift = ((numel(m)-1)/2 - (i-1))*step;
        end

        function moveTrace(obj,idx,delta)
            % Swap a trace with its neighbour in the stack.
            if numel(idx) ~= 1, obj.status('Select one trace to move.'); return; end
            j = idx + delta;
            if j < 1 || j > numel(obj.Traces), return; end
            if obj.Traces(idx).Group > 0 || obj.Traces(j).Group > 0
                obj.status('Overlapped traces cannot be moved one at a time; separate them first (u).');
                return
            end
            if obj.isArranged()
                % Within its own panel only -- which panel a trace is in is
                % its parameter's business, not its position's.
                if obj.PanelIndex(j) ~= obj.PanelIndex(idx)
                    if delta < 0, w = 'top'; else, w = 'bottom'; end
                    obj.status(sprintf('"%s" is already at the %s of its panel.', ...
                        obj.Traces(idx).DisplayName,w));
                    return
                end
                note = obj.manualOrder();
                y = obj.Traces(idx).YOffset;
                obj.Traces(idx).YOffset = obj.Traces(j).YOffset;
                obj.Traces(j).YOffset   = y;
                obj.Traces([idx j]) = obj.Traces([j idx]);
                obj.arrange(true);
                obj.plotAll(false);
                if ~isempty(note), obj.status(note); end
                return
            end
            obj.Traces([idx j]) = obj.Traces([j idx]);
            obj.assignSlots(1:numel(obj.Traces));
            obj.plotAll(false);
        end

        function removeTraces(obj,idx)
            if nargin < 2, idx = obj.selectedIndices(); end
            if isempty(idx), obj.status('Select a trace first.'); return; end
            arranged = obj.isArranged();
            delete(obj.Traces(idx));
            obj.Traces(idx) = [];
            if max(idx) <= numel(obj.PanelIndex), obj.PanelIndex(idx) = []; end
            obj.pruneInspector();
            if numel(obj.PanelIndex) == numel(obj.Traces)
                obj.pruneGroups(obj.PanelIndex);
            else
                obj.pruneGroups(ones(1,numel(obj.Traces)));
            end
            % An organized stack closes the gap (and may lose a panel); a
            % hand-placed one keeps every other trace where it was put.
            obj.arrange(true);
            obj.syncOrganizeMenus();
            obj.plotAll(false,arranged);
            obj.refreshStatus();
        end

        function markPeaks(obj,idx)
            if nargin < 2 || isempty(idx), idx = obj.targetIndices(); end
            for k = idx(:)'
                tr = obj.Traces(k);
                if isempty(tr.Data), continue; end
                r = mabr.metrics.find_peaks(tr.Data,5,false);
                tr.setMarkers(r.locs);
            end
            obj.plotAll(false);
            obj.status(sprintf('Marked peaks on %d trace(s).',numel(idx)));
        end

        function clearMarkers(obj,idx)
            if nargin < 2 || isempty(idx), idx = obj.targetIndices(); end
            for k = idx(:)', obj.Traces(k).clearMarkers(); end
            obj.plotAll(false);
        end

        function showNotes(obj)
            % Open (or raise) the notebook. The toolbar button does the same
            % thing; this is the menu/keyboard route, so nothing here is
            % reachable only by knowing where the icons are.
            obj.ensureNotesView();
            obj.NotesView.popOut();
        end

        function insp = inspectTrace(obj,idx)
            % Open one trace in a mabr.ui.TraceInspector for measuring. The
            % stack normalizes every trace to a shared scale, which is what a
            % series needs and what a measurement cannot use, so latencies are
            % picked over there and transferred back on apply.
            insp = mabr.ui.TraceInspector.empty;
            if nargin < 2 || isempty(idx), idx = obj.selectedIndices(); end
            if numel(idx) ~= 1
                obj.status('Select one trace to inspect (or double-click it).');
                return
            end
            tr = obj.Traces(idx);
            if numel(tr.Data) < 3
                obj.status('That trace has no waveform to inspect.');
                return
            end
            % One inspector at a time: re-opening on the same trace raises the
            % window the user is already working in rather than discarding the
            % peaks they have placed in it.
            if ~isempty(obj.Inspector) && isvalid(obj.Inspector) && ...
                    obj.Inspector.isopen() && obj.Inspector.Trace == tr
                obj.Inspector.show();
                insp = obj.Inspector;
                return
            end
            obj.closeInspector();
            obj.Inspector = mabr.ui.TraceInspector(tr,@() obj.onInspectorApplied());
            insp = obj.Inspector;
            obj.status(sprintf('Inspecting "%s".',tr.DisplayName));
        end

        % --- Persistence ------------------------------------------------------
        function saveView(obj,file)
            % Write the waveforms and the complete display state to a .torg
            % file so loadView can reproduce this view exactly.
            if nargin < 2 || isempty(file)
                [fn,pn] = uiputfile(obj.FileFilter,'Save Traces');
                if isequal(fn,0), return; end
                file = fullfile(pn,fn);
            end
            View = struct();
            View.Version       = obj.FileVersion;
            View.Saved         = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            View.YSpacing      = obj.YSpacing;
            View.YScaling      = obj.YScaling;
            View.NormalizeEach = obj.NormalizeEach;
            View.ShowLabels    = obj.ShowLabels;
            View.Colors        = obj.Colors;
            View.ErrorBand       = obj.ErrorBand;
            View.ConfidenceLevel = obj.ConfidenceLevel;
            View.BootReps        = obj.BootReps;
            View.SplitBy         = obj.SplitBy;
            View.OrderBy         = obj.OrderBy;
            View.OrderDirection  = obj.OrderDirection;
            View.LabelBy         = obj.LabelBy;
            View.XLim          = [];
            View.YLim          = [];
            % The rig notebook travels with the view, on the same terms as it
            % travels with a .abr: whole, so a .torg mailed to a collaborator
            % carries what was happening while these traces were acquired.
            View.Notes         = obj.Notes.toStruct();
            if obj.isvalidView()
                View.XLim = obj.Axes.XLim;
                View.YLim = obj.Axes.YLim;
            end
            if isempty(obj.Traces)
                View.Traces = struct([]);
            else
                % Collect via a cell: arrayfun cannot return struct uniformly.
                c = cell(1,numel(obj.Traces));
                for k = 1:numel(obj.Traces), c{k} = obj.Traces(k).toStruct(); end
                View.Traces = [c{:}];
            end
            save(file,'View','-mat');
            obj.status(sprintf('Saved %d trace(s) to %s',numel(obj.Traces), ...
                obj.shortName(file)));
        end

        function loadView(obj,file)
            % Restore a .torg file, replacing the current traces.
            if nargin < 2 || isempty(file)
                [fn,pn] = uigetfile(obj.FileFilter,'Load Traces');
                if isequal(fn,0), return; end
                file = fullfile(pn,fn);
            end
            L = load(file,'-mat');
            obj.clear();
            notesWarning = '';

            % The organization the file was saved with -- and the defaults
            % (one stack, the order as arranged, IDs) for a file from before
            % there was any. Not the current settings: a view saved as one
            % stack holds offsets for one stack, and splitting those across
            % panels would show something that was never saved.
            org = struct('SplitBy','','OrderBy',{{}},'OrderDirection',{{'ascending'}}, ...
                'LabelBy','id');
            % One at a time, each falling back to its default: a value a
            % hand-edited file got wrong costs that setting, not the load.
            def = org;
            if isfield(L,'View')
                f = fieldnames(org);
                for i = 1:numel(f)
                    if isfield(L.View,f{i}), org.(f{i}) = L.View.(f{i}); end
                end
            end
            obj.Suspended = true;
            for f = {'SplitBy','OrderDirection','OrderBy','LabelBy'}
                try
                    obj.(f{1}) = org.(f{1});
                catch me
                    mabr.log.vprintf(2,1,'Trace organizer: %s not restored: %s',f{1},me.message);
                    obj.(f{1}) = def.(f{1});
                end
            end
            obj.Suspended = false;

            if isfield(L,'View')
                V = L.View;
                obj.YSpacing      = V.YSpacing;
                obj.YScaling      = V.YScaling;
                obj.NormalizeEach = V.NormalizeEach;
                obj.ShowLabels    = V.ShowLabels;
                obj.Colors        = V.Colors;
                % Version 4 and later. Restored defensively field by field --
                % a file written by another version, or edited by hand, must
                % not stop a view loading over a display setting; a file that
                % names no band leaves the current one alone, as its traces
                % carry no sweeps to draw one from anyway.
                try
                    if isfield(V,'BootReps'),        obj.BootReps        = V.BootReps;        end
                    if isfield(V,'ConfidenceLevel'), obj.ConfidenceLevel = V.ConfidenceLevel; end
                    if isfield(V,'ErrorBand'),       obj.ErrorBand       = V.ErrorBand;       end
                catch me
                    mabr.log.vprintf(2,1,'Trace organizer: error-band settings not restored: %s',me.message);
                end
                for k = 1:numel(V.Traces)
                    tr = mabr.ui.Trace.fromStruct(V.Traces(k));
                    if isempty(obj.Traces), obj.Traces = tr; else, obj.Traces(end+1) = tr; end
                end
                obj.computeBands();
                % Panels and captions only: the order and offsets stand as
                % they were saved.
                obj.arrange(false);
                obj.ensureFigure();
                obj.syncOrganizeMenus();
                obj.plotAll(true);
                obj.setLimits(V.XLim,V.YLim);
                obj.plotAll(false);   % relabel against the restored XLim
                notesWarning = obj.restoreNotes(V);
            elseif isfield(L,'S')
                % Version 1 files: waveform, label, colour, offset only.
                for k = 1:numel(L.S)
                    obj.addTrace(L.S(k).Data,L.S(k).Time,L.S(k).Label);
                    obj.Traces(end).YOffset = L.S(k).YOffset;
                    obj.Traces(end).Color   = L.S(k).Color;
                end
                obj.ensureFigure();
                obj.plotAll(true);
            else
                obj.status('Not a trace organizer file.');
                return
            end
            obj.syncMenuChecks();
            obj.refreshStatus();
            % After refreshStatus, which would otherwise overwrite it -- and
            % this is the one thing about the load the user has to be told.
            if ~isempty(notesWarning), obj.status(notesWarning); end
        end
    end

    methods (Access = private)
        function onBlockReady(obj,e)
            % Wrapped: this fires on the acquisition path, so a plotting error
            % must never propagate back into the controller mid-schedule.
            try
                if ~isfield(e.Info,'block'), return; end
                obj.addBlock(e.Info.block);
                % Keep the visible stack up to date without stealing focus --
                % the figure is not raised, so this cannot interrupt the
                % operator watching the live view.
                if obj.isvalidView(), drawnow limitrate; end
            catch me
                mabr.log.vprintf(2,1,'TraceOrganizer block update failed: %s',me.message);
            end
        end

        function ensureNotesView(obj)
            % One view per organizer, built on first need and reused across
            % figure rebuilds -- the figure is thrown away and remade every
            % time a closed organizer is shown again, and a view rebuilt with
            % it would strand the previous one (and its open window).
            if ~isempty(obj.NotesView) && isvalid(obj.NotesView), return; end
            obj.NotesView = mabr.ui.Notes(obj.Notes,[],'ButtonOnly',true, ...
                'Name','Traces');
        end

        function warn = restoreNotes(obj,V)
            % Load the notebook a .torg carries, and return what to say about
            % it (nothing, normally).
            %
            % The one case worth a word is an organizer showing the RUNNING
            % session's notebook: replacing that with a file's would discard
            % notes the operator is still taking, for traces they are still
            % acquiring. A view is loaded to look at old data; the live log is
            % not the loaded view's to overwrite. So it is left alone and the
            % status line says the file's notes were not adopted, rather than
            % either clobbering the log or silently dropping the file's.
            warn = '';
            if ~isfield(V,'Notes'), return; end          % a version 1/2 file
            if isempty(V.Notes) || ~isstruct(V.Notes), return; end
            if ~obj.NotesOwned
                warn = sprintf(['Loaded, but the view''s %d note(s) were not ' ...
                    'adopted — this organizer is showing the current session''s notes.'], ...
                    numel(V.Notes));
                return
            end
            obj.Notes.fromStruct(V.Notes);
        end

        function onInspectorApplied(obj)
            % The inspector wrote its markers straight onto the shared Trace
            % handle; all that is left here is to draw them.
            obj.plotAll(false);
            obj.refreshStatus();
        end

        function closeInspector(obj)
            if ~isempty(obj.Inspector) && isvalid(obj.Inspector)
                obj.Inspector.close();
            end
            obj.Inspector = [];
        end

        function pruneInspector(obj)
            % A trace that has been removed takes its inspector with it --
            % otherwise the window sits there editing a deleted handle.
            if isempty(obj.Inspector) || ~isvalid(obj.Inspector), return; end
            if isempty(obj.Inspector.Trace) || ~isvalid(obj.Inspector.Trace)
                obj.closeInspector();
            end
        end

        function ensureFigure(obj)
            if obj.isvalidView(), return; end
            obj.Figure = figure('Name','MABR Trace Organizer','NumberTitle','off', ...
                'Color','w','Tag',obj.FigTag,'MenuBar','none','Position',[820 120 640 700], ...
                'WindowButtonMotionFcn',@(~,~) obj.doDrag(), ...
                'WindowButtonUpFcn',@(~,~) obj.endDrag(), ...
                'WindowKeyPressFcn',@(~,e) obj.onKey(e), ...
                'SizeChangedFcn',@(~,~) obj.fitLabelMargin());
            % The status line has a row of its own across the top, rather
            % than being the axes' title as it once was: a split view titles
            % each panel with its parameter value, and the status belongs to
            % the view rather than to any one of them.
            obj.StatusText = uicontrol(obj.Figure,'Style','text', ...
                'Units','normalized','Position',[0.01 0.955 0.98 0.035], ...
                'BackgroundColor','w','HorizontalAlignment','center', ...
                'FontSize',9,'String','');
            obj.Axes = obj.newAxes();
            xlabel(obj.Axes,'Time (ms)');
            % Everything below describes graphics that went with the last
            % figure, if there was one.
            obj.PanelAxes     = obj.Axes;
            obj.PanelKey      = '';
            obj.MenuParamKey  = NaN;
            obj.DrawnTraces   = mabr.ui.Trace.empty;
            obj.PlotScale     = zeros(1,0);
            obj.LabelWidthPx  = NaN;
            obj.buildToolbar();
            obj.buildMenus();
            obj.syncOrganizeMenus();
            obj.refreshStatus();
        end

        function ax = newAxes(obj)
            % One panel's axes. Interaction is the organizer's own (click,
            % drag, the menus), so the axes toolbar is off as everywhere.
            ax = axes('Parent',obj.Figure,'Box','on','NextPlot','add', ...
                'YTick',[],'XGrid','on','YGrid','on','GridLineStyle',':');
            mabr.ui.hideAxesToolbar(ax);
            obj.attachContextMenu(ax);
        end

        function buildToolbar(obj)
            % Every action here is also in the menu bar -- the toolbar is a
            % shortcut, never the only route to a function. Each button draws
            % what it does (mabr.ui.Icon) so its meaning is readable without
            % having to hover for the tooltip: one response with its scale
            % pushed out or pressed in is amplitude, two traces pushed apart
            % or together is spacing, and orange is always the action.
            obj.Toolbar = uitoolbar(obj.Figure);
            obj.toolButton('grow',   'Larger amplitude (Up arrow)',        @() obj.scaleTraces(obj.GainStep));
            obj.toolButton('shrink', 'Smaller amplitude (Down arrow)',     @() obj.scaleTraces(1/obj.GainStep));
            obj.toolButton('spread', 'Wider spacing (Shift+Up)',           @() obj.setSpacing(obj.YSpacing*obj.SpacingStep),true);
            obj.toolButton('squeeze','Tighter spacing (Shift+Down)',       @() obj.setSpacing(obj.YSpacing/obj.SpacingStep));
            obj.toolButton('overlap','Overlap selected traces (o)',        @() obj.overlapTraces(),true);
            obj.toolButton('separate','Separate overlapped traces (u)',    @() obj.separateTraces());
            obj.toolButton('peaks',  'Mark peaks on selection (p)',        @() obj.markPeaks(),true);
            obj.toolButton('inspect','Inspect selected trace (i, or double-click)',@() obj.inspectTrace());
            % The same notes component the main window carries, over the same
            % store once listenTo has adopted the session's -- so a note about
            % a trace can be written where the trace is being looked at.
            % Routed through showNotes rather than built with
            % mabr.ui.Notes.toolbarButton because this figure (and so this
            % toolbar) is rebuilt every time a closed organizer is shown again,
            % and a view built here each time would strand the previous one.
            notesTool = uipushtool(obj.Toolbar,'Separator','on', ...
                'Tooltip','Session notes (saved with the data)', ...
                'CData',mabr.ui.Icon.toolbar('notes',obj.Toolbar), ...
                'ClickedCallback',@(~,~) obj.showNotes());
            obj.ensureNotesView();
            obj.NotesView.setTool(notesTool);   % so the count reaches the tooltip
            obj.toolButton('save',   'Save view (Ctrl+S)',                 @() obj.saveView(),true);
            obj.toolButton('load',   'Load view (Ctrl+O)',                 @() obj.loadView());
            obj.toolButton('trash',  'Remove all traces',                  @() obj.clear());
            obj.toolButton('keys',   'Keyboard shortcuts (F1)',            @() obj.showHelp(),true);
        end

        function toolButton(obj,name,tip,fcn,sep)
            if nargin < 5, sep = false; end
            sepStr = 'off'; if sep, sepStr = 'on'; end
            uipushtool(obj.Toolbar,'Tooltip',tip, ...
                'CData',mabr.ui.Icon.toolbar(name,obj.Toolbar), ...
                'Separator',sepStr,'ClickedCallback',@(~,~) fcn());
        end

        function buildMenus(obj)
            % One spec, rendered into both the menu bar and the context menu,
            % so the two can never drift apart.
            obj.ContextMenu = uicontextmenu(obj.Figure);
            for top = obj.menuSpec()
                m = uimenu(obj.Figure,'Label',top.name);
                c = uimenu(obj.ContextMenu,'Label',top.name);
                for item = top.items
                    obj.menuItem(m,item{1});
                    obj.menuItem(c,item{1});
                end
            end
            obj.attachContextMenu(obj.Axes);
            obj.syncMenuChecks();
        end

        function menuItem(~,parent,it)
            % 'Label'/'Callback' rather than the newer 'Text'/'MenuSelectedFcn':
            % both work everywhere, these also work on the R2018b floor.
            if isfield(it,'submenu')
                % A parent whose children are built later, found by its Tag.
                h = uimenu(parent,'Label',it.label,'Tag',it.submenu);
                if isfield(it,'sep') && it.sep, h.Separator = 'on'; end
                return
            end
            h = uimenu(parent,'Label',it.label,'Callback',@(~,~) it.fcn());
            if isfield(it,'sep') && it.sep, h.Separator = 'on'; end
            if isfield(it,'tag'), h.Tag = it.tag; end
            if isfield(it,'accel') && ~isempty(it.accel), h.Accelerator = it.accel; end
        end

        function spec = menuSpec(obj)
            it = @(lbl,fcn,varargin) obj.mkItem(lbl,fcn,varargin{:});
            spec = struct('name',{},'items',{});

            spec(end+1).name = 'Amplitude';
            spec(end).items  = { ...
                it('Larger'                      ,@() obj.scaleTraces(obj.GainStep)) , ...
                it('Smaller'                     ,@() obj.scaleTraces(1/obj.GainStep)) , ...
                it('Double'                      ,@() obj.scaleTraces(2)) , ...
                it('Halve'                       ,@() obj.scaleTraces(0.5)) , ...
                it('Reset to 1x'                 ,@() obj.resetGain(),'sep',true) , ...
                it('Set amplitude...'            ,@() obj.promptGain()) , ...
                it('Normalize each trace'        ,@() obj.toggleNormalize(),'sep',true,'tag','normalize') };

            spec(end+1).name = 'Spacing';
            spec(end).items  = { ...
                it('Wider'                       ,@() obj.setSpacing(obj.YSpacing*obj.SpacingStep)) , ...
                it('Tighter'                     ,@() obj.setSpacing(obj.YSpacing/obj.SpacingStep)) , ...
                it('Set spacing...'              ,@() obj.promptSpacing(),'sep',true) , ...
                it('Restack evenly'              ,@() obj.restack()) };

            spec(end+1).name = 'Traces';
            spec(end).items  = { ...
                it('Select all'                  ,@() obj.select(1:numel(obj.Traces))) , ...
                it('Select none'                 ,@() obj.select([])) , ...
                it('Invert selection'            ,@() obj.invertSelection()) , ...
                it('Overlap selected (o)'        ,@() obj.overlapTraces(),'sep',true) , ...
                it('Separate overlapped (u)'     ,@() obj.separateTraces()) , ...
                it('Next in overlap (Tab)'       ,@() obj.stepOverlap(+1)) , ...
                it('Previous in overlap (Shift+Tab)',@() obj.stepOverlap(-1)) , ...
                it('Select overlap group'        ,@() obj.selectOverlapGroup()) , ...
                it('Move up'                     ,@() obj.moveTrace(obj.selectedIndices(),-1),'sep',true) , ...
                it('Move down'                   ,@() obj.moveTrace(obj.selectedIndices(),+1)) , ...
                it('Rename...'                   ,@() obj.promptRename(),'sep',true) , ...
                it('Set colour...'               ,@() obj.promptColor()) , ...
                it('Show stimulus ID labels'     ,@() obj.toggleLabels(),'sep',true,'tag','labels') , ...
                it('Hide/show selected'          ,@() obj.toggleVisible()) , ...
                it('Remove selected'             ,@() obj.removeTraces(),'sep',true) , ...
                it('Clear all'                   ,@() obj.clear()) };

            % The three submenus list the stimulus parameters the traces
            % held actually vary, so they are filled in later, and again
            % whenever that list changes (syncOrganizeMenus).
            spec(end+1).name = 'Organize';
            spec(end).items  = { ...
                it('Split by'                    ,[],'submenu','org_split') , ...
                it('Order by'                    ,[],'submenu','org_order','sep',true) , ...
                it('Then by'                     ,[],'submenu','org_then') , ...
                it('Label by stimulus ID'        ,@() obj.pickLabel('id'),'sep',true,'tag','org_label_id') , ...
                it('Label by parameters'         ,@() obj.pickLabel('params'),'tag','org_label_params') };

            % A flat radio list, as mabr.ui.LivePlot's band menu is: one click
            % reaches any answer, where a Statistic > Level nesting would cost
            % two for the intervals and buy nothing. The confidence level is
            % shared by the two interval statistics, so picking a level and
            % then switching between t and bootstrap compares them at it.
            spec(end+1).name = 'Band';
            spec(end).items  = { ...
                it('None'                        ,@() obj.setErrorBand('none'),'tag','band_none') , ...
                it('± 1 SD'                      ,@() obj.setErrorBand('std'),'sep',true,'tag','band_std') , ...
                it('± 1 SEM'                     ,@() obj.setErrorBand('sem'),'tag','band_sem') , ...
                it('90% confidence'              ,@() obj.setErrorBand('ci',0.90),'sep',true,'tag','band_ci90') , ...
                it('95% confidence'              ,@() obj.setErrorBand('ci',0.95),'tag','band_ci95') , ...
                it('99% confidence'              ,@() obj.setErrorBand('ci',0.99),'tag','band_ci99') , ...
                it('Bootstrap interval'          ,@() obj.setErrorBand('boot'),'sep',true,'tag','band_boot') };

            spec(end+1).name = 'Peaks';
            spec(end).items  = { ...
                it('Inspect trace... (double-click)',@() obj.inspectTrace()) , ...
                it('Mark peaks'                  ,@() obj.markPeaks(),'sep',true) , ...
                it('Clear markers'               ,@() obj.clearMarkers()) };

            spec(end+1).name = 'File';
            spec(end).items  = { ...
                it('Session notes...'            ,@() obj.showNotes()) , ...
                it('Save traces...'              ,@() obj.saveView(),'accel','S','sep',true) , ...
                it('Load traces...'              ,@() obj.loadView(),'accel','O') , ...
                it('Keyboard shortcuts'          ,@() obj.showHelp(),'sep',true) };
        end

        function s = mkItem(~,lbl,fcn,varargin)
            s = struct('label',lbl,'fcn',fcn);
            for i = 1:2:numel(varargin)
                s.(varargin{i}) = varargin{i+1};
            end
        end

        function attachContextMenu(obj,h)
            if isempty(obj.ContextMenu) || ~isgraphics(obj.ContextMenu), return; end
            try
                h.ContextMenu = obj.ContextMenu;        % R2020a+
            catch
                set(h,'UIContextMenu',obj.ContextMenu); % older releases
            end
        end

        function syncMenuChecks(obj)
            if ~obj.isvalidView(), return; end
            obj.setChecks('normalize',obj.NormalizeEach);
            obj.setChecks('labels',obj.ShowLabels);

            % Tick the band the view is actually showing. A ConfidenceLevel
            % only a script could have set (0.9973, say) matches no entry and
            % leaves the interval items unticked -- the status line still
            % names it.
            isCI  = strcmp(obj.ErrorBand,'ci');
            lvl   = obj.ConfidenceLevel;
            obj.setChecks('band_none',strcmp(obj.ErrorBand,'none'));
            obj.setChecks('band_std' ,strcmp(obj.ErrorBand,'std'));
            obj.setChecks('band_sem' ,strcmp(obj.ErrorBand,'sem'));
            obj.setChecks('band_boot',strcmp(obj.ErrorBand,'boot'));
            tags = {'band_ci90','band_ci95','band_ci99'};
            for i = 1:numel(obj.CILevels)
                obj.setChecks(tags{i},isCI && abs(lvl-obj.CILevels(i)) < 1e-9);
            end

            % Organize: the label mode, and one tick in each submenu for the
            % setting in force. Tags carry the parameter in lower case so a
            % name typed in another case still ticks its item.
            obj.setChecks('org_label_id'    ,strcmp(obj.LabelBy,'id'));
            obj.setChecks('org_label_params',strcmp(obj.LabelBy,'params'));
            [by,way] = obj.orderPair();
            want = {};
            if isempty(obj.SplitBy), want{end+1} = 'org_split_none';
            else,                    want{end+1} = ['org_split_' lower(obj.SplitBy)];
            end
            if isempty(by)
                want(end+1:end+2) = {'org_order_none','org_then_none'};
            else
                want{end+1} = sprintf('org_order_%s_%s',lower(by{1}),way{1});
                if numel(by) >= 2
                    want{end+1} = sprintf('org_then_%s_%s',lower(by{2}),way{2});
                else
                    want{end+1} = 'org_then_none';
                end
            end
            h = findobj(obj.Figure,'-regexp','Tag','^org_(split|order|then)_');
            for k = 1:numel(h)
                h(k).Checked = mabr.ui.Trace.onoff(ismember(h(k).Tag,want));
            end
            % A second key means nothing without a first.
            set(findobj(obj.Figure,'Tag','org_then'),'Enable',mabr.ui.Trace.onoff(~isempty(by)));
        end

        function setChecks(obj,tag,tf)
            h = findobj(obj.Figure,'Tag',tag);
            for k = 1:numel(h)
                h(k).Checked = matlab.lang.OnOffSwitchState(tf);
            end
        end

        % --- Error band -------------------------------------------------------
        function bandChanged(obj)
            % Recompute every band, then redraw. Called from the property
            % setters so that setting ErrorBand at the command line does the
            % same thing as picking it off the menu.
            obj.computeBands();
            obj.syncMenuChecks();
            if obj.isvalidView(), obj.plotAll(false); end
        end

        function computeBands(obj,idx)
            % One pass over the sweeps per change of statistic, not per redraw:
            % the offsets are cached on each Trace (see mabr.ui.Trace.setBand),
            % which is what keeps a bootstrap band affordable in a view that
            % gains a trace every block.
            if nargin < 2 || isempty(idx), idx = 1:numel(obj.Traces); end
            none = strcmp(obj.ErrorBand,'none');
            for k = idx(:)'
                tr = obj.Traces(k);
                if none || isempty(tr.Sweeps) || size(tr.Sweeps,1) ~= numel(tr.Data)
                    tr.clearBand();
                    continue
                end
                try
                    % band_edges takes [nSweeps x nSamples]; Sweeps is stored
                    % the way a Recording hands it over, [nSamples x nSweeps].
                    [lo,hi] = mabr.metrics.band_edges(tr.Sweeps.', ...
                        obj.ErrorBand,obj.ConfidenceLevel,obj.BootReps);
                    tr.setBand(lo,hi);
                catch me
                    % A band is a display statistic: losing one must not cost
                    % the trace, least of all on the acquisition path.
                    tr.clearBand();
                    mabr.log.vprintf(2,1,'Trace organizer: error band failed on "%s": %s', ...
                        tr.DisplayName,me.message);
                end
            end
        end

        function s = bandDescription(obj)
            switch obj.ErrorBand
                case 'std',  s = '± 1 SD';
                case 'sem',  s = '± 1 SEM';
                case 'ci',   s = sprintf('± %g%% CI',100*obj.ConfidenceLevel);
                case 'boot', s = sprintf('± %g%% bootstrap CI',100*obj.ConfidenceLevel);
                otherwise,   s = 'none';
            end
        end

        function cycleBand(obj)
            % The keyboard route: step through the statistics at the current
            % confidence level, so one key reaches all of them.
            modes = {'none','std','sem','ci','boot'};
            i = find(strcmp(obj.ErrorBand,modes),1);
            if isempty(i), i = 1; end
            obj.setErrorBand(modes{mod(i,numel(modes))+1});
        end

        % --- Drawing ----------------------------------------------------------
        function plotAll(obj,resetX,resetY)
            % Draw every trace. resetX/resetY refit the time axis / the stack
            % height to the traces; resetY defaults to resetX, so
            % plotAll(true) and plotAll(false) mean what they always have.
            if ~obj.isvalidView(), return; end
            if nargin < 2, resetX = false; end
            if nargin < 3, resetY = resetX; end
            obj.syncPanels();
            if isempty(obj.Traces)
                obj.rememberDrawn(zeros(1,0));
                obj.fitLabelMargin();
                obj.refreshStatus();
                return
            end

            sc = obj.yscale();

            if resetX
                tAll = arrayfun(@(t) reshape(t.Time([1 end]),1,2)*1000, ...
                    obj.Traces,'UniformOutput',false);
                tAll = vertcat(tAll{:});
                obj.setLimits([min(tAll(:,1)) max(tAll(:,2))],[]);
            end
            labelX = obj.labelX();

            for k = 1:numel(obj.Traces)
                obj.drawTrace(k,sc(k),labelX);
            end

            if resetY, obj.setLimits([],obj.stackYLim()); end
            obj.rememberDrawn(sc);
            obj.fitLabelMargin();
            obj.refreshStatus();
        end

        function plotAdded(obj,tr)
            % Draw what adding trace tr changed, and only that. A session adds
            % a trace per finalized block, and redrawing EVERY trace each
            % time (plotAll) -- a dozen graphics writes and a label
            % measurement apiece -- made the end of each run cost more the
            % longer the session had run, for traces that had not changed.
            %
            % In a single hand-arranged stack that is the new trace alone. In
            % an organized one it is the new trace plus every trace it pushed
            % down its panel, which are only moved. Anything that would change
            % how the others are DRAWN falls back to plotAll: a new panel, a
            % new trace that moves the shared amplitude scale, the time axis
            % (the labels hang off its left end), or a label that now reads
            % differently (LabelBy 'params': a new value can make a parameter
            % vary that did not before).
            n = numel(obj.Traces);
            if n < 2 || numel(obj.DrawnTraces) ~= n-1 || numel(obj.PlotScale) ~= n-1 ...
                    || ~strcmp(mabr.ui.TraceOrganizer.panelKeyOf(obj.PanelLabels),obj.PanelKey)
                obj.plotAll(true);
                return
            end
            sc  = obj.yscale();
            redraw = false(1,n);
            for k = 1:n
                t = obj.Traces(k);
                if t == tr, redraw(k) = true; continue; end
                j = find(obj.DrawnTraces == t,1);
                if isempty(j) || sc(k) ~= obj.PlotScale(j) ...
                        || obj.PanelIndex(k) ~= obj.DrawnPanels(j) ...
                        || ~strcmp(t.Caption,obj.DrawnCaptions{j})
                    obj.plotAll(true);
                    return
                end
                redraw(k) = t.YOffset ~= obj.DrawnOffsets(j);
            end
            tl = reshape(tr.Time([1 end]),1,2)*1000;
            xl = obj.Axes.XLim;
            if tl(1) < xl(1) || tl(2) > xl(2)
                obj.plotAll(true);
                return
            end
            labelX = obj.labelX();
            for k = find(redraw)
                obj.drawTrace(k,sc(k),labelX);
            end
            obj.setLimits([],obj.stackYLim());
            obj.rememberDrawn(sc);
            obj.fitLabelMargin(tr);
            obj.refreshStatus();
        end

        function drawTrace(obj,k,sc,labelX)
            % Trace k into its panel. The click callbacks hold the Trace
            % rather than its index: an organized stack is reordered as
            % traces arrive, and an index captured here would then select
            % somebody else.
            tr = obj.Traces(k);
            tr.ShowLabel = obj.ShowLabels;
            tr.LabelShift = obj.labelShift(k);
            tr.plot(obj.panelFor(k),sc,labelX);
            if isempty(tr.LineHandle) || ~isgraphics(tr.LineHandle), return; end
            tr.LineHandle.ButtonDownFcn  = @(~,~) obj.onTraceClick(tr);
            tr.LabelHandle.ButtonDownFcn = @(~,~) obj.onTraceClick(tr);
            obj.attachContextMenu(tr.LineHandle);
            obj.attachContextMenu(tr.LabelHandle);
        end

        function rememberDrawn(obj,sc)
            obj.PlotScale     = sc(:).';
            obj.DrawnTraces   = obj.Traces;
            obj.DrawnPanels   = obj.PanelIndex;
            if isempty(obj.Traces)
                obj.DrawnOffsets  = zeros(1,0);
                obj.DrawnCaptions = {};
            else
                obj.DrawnOffsets  = [obj.Traces.YOffset];
                obj.DrawnCaptions = {obj.Traces.Caption};
            end
        end

        function ax = panelFor(obj,k)
            % The axes trace k is drawn in.
            ax = obj.Axes;
            if k > numel(obj.PanelIndex), return; end
            p = obj.PanelIndex(k);
            if p >= 1 && p <= numel(obj.PanelAxes) && isgraphics(obj.PanelAxes(p))
                ax = obj.PanelAxes(p);
            end
        end

        function setLimits(obj,xl,yl)
            % One time axis and one stack height for every panel: the panels
            % share an amplitude scale, and a scale is only shared if a
            % microvolt is the same height in each of them.
            ax = obj.PanelAxes;
            if isempty(ax), ax = obj.Axes; end
            for k = 1:numel(ax)
                if ~isgraphics(ax(k)), continue; end
                if ~isempty(xl), ax(k).XLim = xl; end
                if ~isempty(yl), ax(k).YLim = yl; end
            end
        end

        function yl = stackYLim(obj)
            allY = [obj.Traces.YOffset];
            yl   = [min(allY)-obj.YSpacing, max(allY)+obj.YSpacing];
        end

        function x = labelX(obj)
            % Anchor for the right-aligned labels: just left of the y-axis, so
            % the text runs outward into the margin instead of over the traces.
            % Every panel shares the time axis, so one anchor serves them all.
            x = obj.Axes.XLim(1) - 0.015*diff(obj.Axes.XLim);
        end

        % --- Panels -----------------------------------------------------------
        function syncPanels(obj)
            % One axes per panel of the arrangement in force. Rebuilt only when
            % the panels themselves change; the first is kept throughout (it
            % is Axes, and the panels added beside it copy its limits). A
            % trace drawn in an axes that goes is redrawn in its new one --
            % see mabr.ui.Trace.adoptAxes.
            if isempty(obj.Axes) || ~isgraphics(obj.Axes), return; end
            labels = obj.PanelLabels;
            N      = numel(labels);
            key    = mabr.ui.TraceOrganizer.panelKeyOf(labels);
            ax     = obj.PanelAxes;
            if strcmp(key,obj.PanelKey) && numel(ax) == N && all(isgraphics(ax))
                return
            end
            first = obj.Axes;
            for k = 1:numel(ax)
                if isgraphics(ax(k)) && ax(k) ~= first, delete(ax(k)); end
            end
            ax = gobjects(1,N);
            ax(1) = first;
            for k = 2:N
                ax(k) = obj.newAxes();
                ax(k).XLim = first.XLim;
                ax(k).YLim = first.YLim;
            end
            for k = 1:N
                title(ax(k),labels{k},'FontWeight','bold','FontSize',10, ...
                    'Interpreter','none');
            end
            obj.PanelAxes = ax;
            obj.PanelKey  = key;
            % New axes, new label anchors: measure every label again.
            obj.LabelWidthPx = NaN;
        end

        function layoutPanels(obj,labelPx)
            % Place every panel for labels labelPx pixels wide (see
            % panelRects), and put the time axis label under the bottom panel
            % of each column only.
            ax = obj.PanelAxes;
            if isempty(ax), ax = obj.Axes; end
            ax = ax(isgraphics(ax));
            if isempty(ax), return; end
            figPos = getpixelposition(obj.Figure);
            titled = ~isempty(obj.SplitName);
            [pos,isBottom] = mabr.ui.TraceOrganizer.panelRects(numel(ax), ...
                figPos(3),figPos(4),labelPx,titled);
            for k = 1:numel(ax)
                ax(k).Position = pos(k,:);
                if isBottom(k), want = 'Time (ms)'; else, want = ''; end
                if ~strcmp(ax(k).XLabel.String,want), ax(k).XLabel.String = want; end
            end
        end

        function fitLabelMargin(obj,added)
            % Widen the room left of each panel to whatever the longest label
            % needs, and lay the panels out around it (layoutPanels). Label
            % pixel width depends only on the font, not on the axes size, so
            % measuring and then resizing cannot chase its own tail. Also
            % fires as a resize callback, possibly before the axes exists.
            %
            % fitLabelMargin(obj,added) is the incremental form plotAdded uses:
            % only the new trace's label is measured, against the widest one
            % the last full pass found -- each measurement is a text layout,
            % and a session's worth of them per block is what it replaces.
            if ~obj.isvalidView() || isempty(obj.Axes) || ~isgraphics(obj.Axes)
                return
            end

            if nargin >= 2 && isfinite(obj.LabelWidthPx)
                if ~obj.ShowLabels, return; end
                w = max(obj.LabelWidthPx,mabr.ui.TraceOrganizer.labelWidth(added.LabelHandle));
                if w == obj.LabelWidthPx, return; end   % no wider: the margins stand
                obj.LabelWidthPx = w;
                obj.layoutPanels(w);
                return
            end

            w = 0;
            if obj.ShowLabels && ~isempty(obj.Traces)
                for k = 1:numel(obj.Traces)
                    w = max(w,mabr.ui.TraceOrganizer.labelWidth(obj.Traces(k).LabelHandle));
                end
            end
            obj.LabelWidthPx = w;
            obj.layoutPanels(w);
        end

        % --- Arrangement ------------------------------------------------------
        function arrange(obj,reorder)
            % Work out the arrangement the settings ask for: each trace's
            % panel, the panels' titles, and -- with reorder true, whenever a
            % split or an order is in force, or a split has just been lifted
            % -- the order of every stack, which is then respaced evenly.
            % reorder false (a view being loaded) classifies only, so the
            % order and offsets stand exactly as saved. Labels follow
            % LabelBy either way.
            n = numel(obj.Traces);
            params = cell(1,n);
            for k = 1:n, params{k} = obj.Traces(k).parameters(); end
            P = mabr.ui.TraceOrganizer.paramTable(params);
            A = mabr.ui.TraceOrganizer.arrangement(P,obj.SplitBy,obj.OrderBy, ...
                obj.OrderDirection,obj.visualRank());
            wasSplit = numel(obj.PanelLabels) > 1;
            if reorder && n > 0 && (obj.isOrganized() || wasSplit)
                obj.Traces = obj.Traces(A.order);
                P.Values   = P.Values(A.order,:);
                panel      = A.panel;
                % Overlapped traces stay one slot: members are gathered
                % beside the first of their group, and share its offset.
                obj.pruneGroups(panel);
                g = mabr.ui.TraceOrganizer.gatherOrder(panel,[obj.Traces.Group]);
                if ~isequal(g,1:n)
                    obj.Traces = obj.Traces(g);
                    P.Values   = P.Values(g,:);
                    panel      = panel(g);
                end
                for p = unique(panel)
                    obj.assignSlots(find(panel == p));
                end
            else
                panel = A.panelOf;
            end
            obj.PanelIndex  = panel;
            obj.PanelLabels = A.panelLabels;
            obj.ParamNames  = P.Names;
            obj.ParamValues = P.Values;
            obj.SplitName   = A.split;
            obj.OrderKeys   = A.keys;
            obj.applyCaptions(A.splitCol);
        end

        function rank = visualRank(obj)
            % Where each trace stands now, top to bottom: panel by panel, and
            % within one by height, ties going to the earlier trace. This is
            % the order an arrangement keeps wherever the settings leave it
            % free -- the whole of it, when the order is manual.
            n    = numel(obj.Traces);
            rank = zeros(1,n);
            if n == 0, return; end
            pan = obj.PanelIndex;
            if numel(pan) < n, pan(end+1:n) = max([pan 0]) + 1; end
            pan = pan(1:n);
            [~,ord] = sortrows([pan(:), -[obj.Traces.YOffset].', (1:n).']);
            rank(ord) = 1:n;
        end

        function applyCaptions(obj,splitCol)
            % LabelBy 'params': each trace is named by the parameters that
            % vary across the traces held -- a parameter every trace shares
            % says nothing -- less the one the panels are titled with. A
            % trace with none of them keeps its ID.
            n = numel(obj.Traces);
            if ~strcmp(obj.LabelBy,'params')
                for k = 1:n, obj.Traces(k).Caption = ''; end
                return
            end
            V    = obj.ParamValues;
            vary = mabr.ui.TraceOrganizer.varyingCols(V);
            vary = vary(vary ~= splitCol);
            for k = 1:n
                parts = {};
                for j = vary
                    if ~isnan(V(k,j))
                        parts{end+1} = mabr.ui.TraceOrganizer.paramValueText( ...
                            obj.ParamNames{j},V(k,j)); %#ok<AGROW>
                    end
                end
                obj.Traces(k).Caption = strjoin(parts,', ');
            end
        end

        function tf = isArranged(obj)
            % Whether the stack is laid out by arrange() -- kept even, panel
            % by panel -- rather than placed by hand. A split just lifted
            % still counts, until arrange has merged its panels.
            tf = obj.isOrganized() || numel(obj.PanelLabels) > 1;
        end

        function note = manualOrder(obj)
            % A trace moved by hand: from now on the order is the user's. A
            % parameter order is cleared (quietly -- the caller is about to
            % arrange and redraw) and the note says what it was.
            note = '';
            if ~any(~cellfun(@isempty,obj.OrderBy)), return; end
            was = obj.orderDescription();
            obj.Suspended = true;
            obj.OrderBy   = {};
            obj.Suspended = false;
            obj.syncMenuChecks();
            if isempty(was)
                note = 'Order is now manual.';
            else
                note = sprintf('Order is now manual (was %s).',was);
            end
        end

        function [by,way] = orderPair(obj)
            % OrderBy and OrderDirection as two parallel lists, one direction
            % per name, as arrangement reads them; empty names dropped.
            by  = obj.OrderBy;
            d   = obj.OrderDirection;
            way = cell(1,numel(by));
            for k = 1:numel(by)
                if isscalar(d),       way{k} = d{1};
                elseif k <= numel(d), way{k} = d{k};
                else,                 way{k} = 'ascending';
                end
            end
            keep = ~cellfun(@isempty,by);
            by   = by(keep);
            way  = way(keep);
        end

        function s = orderDescription(obj)
            % The order in force, in words ('Level descending, Frequency
            % ascending'), or '' for none.
            K = obj.OrderKeys;
            c = cell(1,numel(K));
            for k = 1:numel(K), c{k} = sprintf('%s %s',K(k).Name,K(k).Direction); end
            s = strjoin(c,', ');
        end

        % --- Organize menu ----------------------------------------------------
        function syncOrganizeMenus(obj)
            % List the parameters to split and order by, rebuilding the three
            % submenus only when that list changes (a new block seldom
            % changes it), and tick what is in force.
            if ~obj.isvalidView(), return; end
            names = obj.menuParams();
            if ~isequal(names,obj.MenuParamKey)
                obj.MenuParamKey = names;
                obj.fillOrganizeMenus(names);
            end
            obj.syncMenuChecks();
        end

        function names = menuParams(obj)
            % The parameters the traces held vary -- a constant one is a
            % single panel, and orders nothing -- plus any the settings name
            % that are not among them, so a setting in force is always on
            % the menu with its tick.
            names = obj.ParamNames(mabr.ui.TraceOrganizer.varyingCols(obj.ParamValues));
            [by,~] = obj.orderPair();
            extra  = [{obj.SplitBy} by];
            for k = 1:numel(extra)
                if ~isempty(extra{k}) && ~any(strcmpi(names,extra{k}))
                    names{end+1} = extra{k}; %#ok<AGROW>
                end
            end
            names = reshape(names,1,[]);
        end

        function fillOrganizeMenus(obj,names)
            dirs = obj.OrderDirections;
            for h = reshape(findobj(obj.Figure,'Tag','org_split'),1,[])
                delete(allchild(h));
                uimenu(h,'Label','None (one stack)','Tag','org_split_none', ...
                    'Callback',@(~,~) obj.pickSplit(''));
                for j = 1:numel(names)
                    m = uimenu(h,'Label',names{j},'Tag',['org_split_' lower(names{j})], ...
                        'Callback',@(~,~) obj.pickSplit(names{j}));
                    if j == 1, m.Separator = 'on'; end
                end
                obj.noParamsItem(h,names);
            end
            slots = {'org_order','org_then'};
            none  = {'Manual (as arranged)','None'};
            for s = 1:2
                for h = reshape(findobj(obj.Figure,'Tag',slots{s}),1,[])
                    delete(allchild(h));
                    uimenu(h,'Label',none{s},'Tag',[slots{s} '_none'], ...
                        'Callback',@(~,~) obj.pickOrder(s,'',''));
                    for j = 1:numel(names)
                        for d = 1:numel(dirs)
                            m = uimenu(h,'Label',sprintf('%s, %s',names{j},dirs{d}), ...
                                'Tag',sprintf('%s_%s_%s',slots{s},lower(names{j}),dirs{d}), ...
                                'Callback',@(~,~) obj.pickOrder(s,names{j},dirs{d}));
                            if d == 1, m.Separator = 'on'; end
                        end
                    end
                    obj.noParamsItem(h,names);
                end
            end
        end

        function noParamsItem(~,h,names)
            % Say why a submenu offers nothing rather than leave it bare.
            if ~isempty(names), return; end
            uimenu(h,'Label','(no stimulus parameter varies)','Enable','off', ...
                'Separator','on');
        end

        function pickSplit(obj,name)
            obj.SplitBy = name;
        end

        function pickOrder(obj,slot,name,way)
            % The Order by (slot 1) and Then by (slot 2) submenus. Picking the
            % first key for the parameter already second promotes it rather
            % than ordering by one name twice.
            [by,ways] = obj.orderPair();
            by   = by(1:min(2,end));
            ways = ways(1:min(2,end));
            if slot == 1
                if isempty(name)
                    by = {}; ways = {};
                else
                    if numel(by) >= 2 && strcmpi(by{2},name)
                        by(2) = []; ways(2) = [];
                    end
                    if isempty(by)
                        by = {name}; ways = {way};
                    else
                        by{1} = name; ways{1} = way;
                    end
                end
            else
                if isempty(by), return; end
                if isempty(name)
                    by = by(1); ways = ways(1);
                elseif strcmpi(by{1},name)
                    obj.status(sprintf('Already ordered by %s.',by{1}));
                    obj.syncMenuChecks();
                    return
                else
                    by = {by{1} name}; ways = {ways{1} way};
                end
            end
            obj.setOrder(by,ways);
        end

        function pickLabel(obj,mode)
            obj.LabelBy = mode;
        end

        function cycleSplit(obj)
            % The keyboard route through the Split by menu: none, then each
            % parameter the traces vary, then none again.
            names = [{''} obj.ParamNames(mabr.ui.TraceOrganizer.varyingCols(obj.ParamValues))];
            if numel(names) < 2
                obj.status('No stimulus parameter varies across these traces to split by.');
                return
            end
            i = find(strcmpi(names,obj.SplitBy),1);
            if isempty(i), i = 1; end
            obj.SplitBy = names{mod(i,numel(names))+1};
        end

        function sc = yscale(obj)
            % Per-trace normalization factor. In common mode every trace shares
            % one factor so relative amplitudes stay comparable; in per-trace
            % mode each is scaled to its own peak.
            n = numel(obj.Traces);
            sc = ones(1,n);
            if n == 0, return; end
            amps = arrayfun(@(t) t.amplitude(),obj.Traces);
            span = obj.YScaling*obj.YSpacing;
            if obj.NormalizeEach
                sc = span ./ amps;
            else
                sc = repmat(span/max(amps),1,n);
            end
        end

        % --- Interaction ------------------------------------------------------
        function onTraceClick(obj,tr)
            k = find(obj.Traces == tr,1);
            if isempty(k), return; end
            mods  = get(obj.Figure,'SelectionType');
            % 'open' = double-click. MATLAB delivers the first click of the
            % pair as a normal one, so a drag is already armed by the time
            % this arrives -- disarm it, or the inspector opens with the
            % trace still following the mouse.
            if strcmp(mods,'open')
                obj.dragTrace = [];
                obj.dragMoved = false;
                obj.select(k);
                obj.inspectTrace(k);
                return
            end
            % 'extend' = shift-click, 'alt' = ctrl-click (or right-click, which
            % the context menu handles before this fires).
            extend = any(strcmp(mods,{'extend','alt'}));
            % Clicking the one selected trace of an overlap again selects the
            % next one under it -- on release, so that pressing and dragging
            % it still moves it rather than cycling.
            obj.cycleOnRelease = ~extend && tr.Group > 0 && isequal(obj.selectedIndices(),k);
            obj.select(k,extend);

            % The trace's own panel: a drag moves it up and down its stack.
            obj.dragTrace = tr;
            ax = obj.panelFor(k);
            cp = ax.CurrentPoint;
            obj.dragStartY = cp(1,2);
            obj.dragStartOffset = tr.YOffset;
            obj.dragMoved = false;
        end

        function doDrag(obj)
            tr = obj.dragTrace;
            if isempty(tr), return; end
            k = [];
            if isvalid(tr), k = find(obj.Traces == tr,1); end
            if isempty(k), obj.dragTrace = []; return; end
            ax = obj.panelFor(k);
            cp = ax.CurrentPoint;
            dy = cp(1,2) - obj.dragStartY;
            if dy == 0, return; end
            obj.dragMoved = true;
            sc = obj.yscale();
            tr.YOffset = obj.dragStartOffset + dy;
            tr.plot(ax,sc(k),obj.labelX());
        end

        function endDrag(obj)
            moved = obj.dragMoved;
            tr    = obj.dragTrace;
            cyc   = obj.cycleOnRelease;
            obj.dragTrace = [];
            obj.dragMoved = false;
            obj.cycleOnRelease = false;
            if ~moved
                if cyc, obj.stepOverlap(+1); end
                return
            end
            % Dragging a trace out of an overlap takes it out of the group.
            if ~isempty(tr) && isvalid(tr) && tr.Group > 0
                tr.Group = 0;
                if numel(obj.PanelIndex) == numel(obj.Traces)
                    obj.pruneGroups(obj.PanelIndex);
                else
                    obj.pruneGroups(ones(1,numel(obj.Traces)));
                end
            end
            if ~obj.isArranged()
                obj.refreshStatus();   % placed by hand: it stays where it was put
                return
            end
            % An organized stack is kept even, so the trace drops into the
            % place it was let go at. A drop that crossed no other trace
            % changes nothing and snaps back, the order intact; one that did
            % is a hand-made order, which replaces a parameter one.
            note = '';
            if ~isequal(obj.visualRank(),1:numel(obj.Traces))
                note = obj.manualOrder();
            end
            obj.arrange(true);
            obj.plotAll(false);
            if ~isempty(note), obj.status(note); end
        end

        function onKey(obj,e)
            ctrl  = any(strcmpi(e.Modifier,'control'));
            shift = any(strcmpi(e.Modifier,'shift'));
            sel   = obj.selectedIndices();

            switch lower(e.Key)
                case {'uparrow','equal','add','plus'}
                    if shift,     obj.setSpacing(obj.YSpacing*obj.SpacingStep);
                    elseif ctrl,  obj.moveTrace(sel,-1);
                    else,         obj.scaleTraces(obj.GainStep);
                    end
                case {'downarrow','hyphen','subtract','minus'}
                    if shift,     obj.setSpacing(obj.YSpacing/obj.SpacingStep);
                    elseif ctrl,  obj.moveTrace(sel,+1);
                    else,         obj.scaleTraces(1/obj.GainStep);
                    end
                case '0'
                    obj.resetGain();
                case 'n'
                    % Ctrl+N for the notebook: plain n is already normalization,
                    % and the notebook is the rarer of the two.
                    if ctrl, obj.showNotes(); else, obj.toggleNormalize(); end
                case 'r'
                    obj.restack();
                case 'a'
                    if ~ctrl, obj.select(1:numel(obj.Traces)); end
                case 'escape'
                    obj.select([]);
                case 'l'
                    obj.toggleLabels();
                case 'p'
                    obj.markPeaks();
                case 'c'
                    obj.clearMarkers();
                case 'b'
                    obj.cycleBand();
                case 'g'
                    obj.cycleSplit();
                case 'i'
                    obj.inspectTrace();
                case 'h'
                    obj.toggleVisible();
                case {'delete','backspace'}
                    obj.removeTraces();
                case 's'
                    if ctrl, obj.saveView(); end
                case 'o'
                    if ctrl, obj.loadView(); else, obj.overlapTraces(); end
                case 'u'
                    obj.separateTraces();
                case 'tab'
                    if shift, obj.stepOverlap(-1); else, obj.stepOverlap(+1); end
                case {'f1','slash','help'}
                    obj.showHelp();
            end
        end

        % --- Commands needing a prompt ----------------------------------------
        function promptGain(obj)
            idx = obj.targetIndices();
            if isempty(idx), return; end
            a = inputdlg('Amplitude multiplier (relative to current):', ...
                'Set Amplitude',1,{'1'});
            if isempty(a), return; end
            v = str2double(a{1});
            if ~isfinite(v) || v <= 0, obj.status('Amplitude must be positive.'); return; end
            for k = idx(:)', obj.Traces(k).Gain = v; end
            obj.plotAll(false);
        end

        function promptSpacing(obj)
            a = inputdlg('Vertical spacing between traces:','Set Spacing',1, ...
                {num2str(obj.YSpacing)});
            if isempty(a), return; end
            v = str2double(a{1});
            if ~isfinite(v) || v <= 0, obj.status('Spacing must be positive.'); return; end
            obj.setSpacing(v);
        end

        function promptRename(obj)
            idx = obj.selectedIndices();
            if numel(idx) ~= 1, obj.status('Select one trace to rename.'); return; end
            a = inputdlg('Stimulus ID / label:','Rename Trace',1, ...
                {obj.Traces(idx).StimID});
            if isempty(a), return; end
            obj.Traces(idx).StimID = a{1};
            obj.plotAll(false);
            if strcmp(obj.LabelBy,'params') && ~isempty(obj.Traces(idx).Caption)
                obj.status(['Renamed. The labels show stimulus parameters; ' ...
                    'Organize > Label by stimulus ID shows names.']);
            end
        end

        function promptColor(obj)
            idx = obj.selectedIndices();
            if isempty(idx), obj.status('Select a trace first.'); return; end
            c = uisetcolor(obj.Traces(idx(1)).Color,'Trace Colour');
            if isequal(c,0) || numel(c) ~= 3, return; end
            for k = idx(:)', obj.Traces(k).Color = c; end
            obj.plotAll(false);
        end

        function toggleNormalize(obj)
            obj.NormalizeEach = ~obj.NormalizeEach;
            obj.syncMenuChecks();
            obj.plotAll(false);
        end

        function toggleLabels(obj)
            obj.ShowLabels = ~obj.ShowLabels;
            obj.syncMenuChecks();
            obj.plotAll(false);
        end

        function invertSelection(obj)
            for k = 1:numel(obj.Traces)
                obj.Traces(k).Selected = ~obj.Traces(k).Selected;
            end
            obj.plotAll(false);
        end

        function showHelp(~)
            msg = { ...
                'Click a trace or its label to select it.'
                'Shift- or ctrl-click extends the selection.'
                'Drag a trace vertically to reposition it.'
                'Double-click a trace to inspect and mark it full size.'
                'Overlap (o) lays the selected traces on one line; clicking the'
                'selected one again, or Tab, selects the next one under it.'
                'Amplitude commands act on the selection, or on all traces'
                'when nothing is selected.'
                'Organize splits the view into panels and orders the stacks'
                'by stimulus parameter; moving a trace by hand then makes'
                'the order manual.'
                ''
                'Up / Down            amplitude larger / smaller'
                'Shift+Up / Down      spacing wider / narrower'
                'Ctrl+Up / Down       move selected trace up / down'
                '0                    reset amplitude to 1x'
                'n                    per-trace vs. common normalization'
                'r                    restack evenly'
                'a / Escape           select all / none'
                'o / u                overlap selected traces / separate them'
                'Tab / Shift+Tab      step through the overlapped traces'
                'l                    toggle stimulus ID labels'
                'p / c                mark peaks / clear markers'
                'b                    cycle the error band'
                'g                    cycle the split by stimulus parameter'
                'i                    inspect the selected trace'
                'h                    hide / show selected'
                'Delete               remove selected'
                'Ctrl+N               session notes'
                'Ctrl+S / Ctrl+O      save / load view'
                'F1                   this help' };
            helpdlg(msg,'Trace Organizer Shortcuts');
        end

        % --- Status -----------------------------------------------------------
        function refreshStatus(obj)
            if ~obj.isvalidView(), return; end
            n = numel(obj.Traces);
            s = obj.selectedIndices();
            if obj.NormalizeEach, mode = 'per-trace'; else, mode = 'common'; end
            band = '';
            if ~strcmp(obj.ErrorBand,'none')
                band = sprintf('  |  %s',obj.bandDescription());
            end
            obj.status(sprintf('%d trace(s), %d selected  |  spacing %.3g  |  %s scale%s%s', ...
                n,numel(s),obj.YSpacing,mode,band,obj.organizeDescription()));
        end

        function s = organizeDescription(obj)
            % The split and order in force, for the status line -- and a
            % setting naming a parameter no trace carries, said as such,
            % since it is otherwise invisible.
            s = '';
            if ~isempty(obj.SplitName)
                s = sprintf('%s  |  split by %s (%d)',s,obj.SplitName,numel(obj.PanelLabels));
            elseif ~isempty(obj.SplitBy) && ~isempty(obj.Traces)
                s = sprintf('%s  |  split by %s: no trace carries it',s,obj.SplitBy);
            end
            o = obj.orderDescription();
            if ~isempty(o)
                s = sprintf('%s  |  ordered by %s',s,o);
            elseif any(~cellfun(@isempty,obj.OrderBy)) && ~isempty(obj.Traces)
                s = sprintf('%s  |  order by %s: no trace carries it',s, ...
                    strjoin(obj.OrderBy(~cellfun(@isempty,obj.OrderBy)),', '));
            end
        end

        function status(obj,txt)
            if obj.isvalidView() && ~isempty(obj.StatusText) && isgraphics(obj.StatusText)
                obj.StatusText.String = txt;
            end
        end
    end

    methods (Static)
        function g = gatherOrder(panel,group)
            % A permutation (1 x n) of traces already ordered panel by panel
            % that brings every overlap group's members next to its first
            % member, keeping everything else where it was. Pure.
            n = numel(panel);
            panel = panel(:).'; group = group(:).';
            anchor = 1:n;
            for k = 1:n
                if group(k) == 0, continue; end
                anchor(k) = find(group == group(k) & panel == panel(k),1);
            end
            [~,g] = sortrows([anchor(:) (1:n).']);
            g = g(:).';
        end

        function A = arrangement(P,splitBy,orderBy,orderDir,rank)
            % How a set of traces is arranged by stimulus parameter. Pure --
            % no graphics, no organizer -- so it is tested on its own.
            %
            %   P         .Names {1 x nP}, .Values [n x nP], NaN where a trace
            %             lacks the parameter (see paramTable)
            %   splitBy   a parameter name, '' for none
            %   orderBy   names, most significant first; {} for none
            %   orderDir  'ascending' / 'descending', read in parallel with
            %             orderBy: one applies to all, a name without one of
            %             its own is 'ascending'
            %   rank      [1 x n] where each trace stands now (1 = top): the
            %             tie-break, and the whole order when there is no
            %             key. Default 1:n.
            %
            %   A.panelOf      [1 x n] each trace's panel, in input order
            %   A.order        [1 x n] the traces top to bottom, panel by panel
            %   A.panel        [1 x n] A.panelOf(A.order)
            %   A.panelValues  [1 x nPanels] each panel's value (NaN for the
            %                  panel of traces lacking the parameter)
            %   A.panelLabels  {1 x nPanels} its title ('8 kHz'); {''} unsplit
            %   A.split        the parameter split by, as the traces name it,
            %                  '' when no split is in force
            %   A.splitCol     its column of P, 0 for none
            %   A.keys         struct('Name','Direction'), the order applied
            %
            % A name no trace carries is ignored rather than refused: the
            % setting outlives the traces it was chosen for. Panels run in
            % ascending order of their value -- descending when the split
            % parameter is itself an order key, descending -- and the traces
            % lacking it come last. Within a panel the keys sort, missing
            % values last, and rank breaks every tie, so the sort is stable
            % in either direction and reversing one key reverses nothing else.
            n = size(P.Values,1);
            if nargin < 5 || isempty(rank), rank = 1:n; end
            if ischar(orderBy)  || isstring(orderBy),  orderBy  = cellstr(orderBy);  end
            if ischar(orderDir) || isstring(orderDir), orderDir = cellstr(orderDir); end
            A = struct('panelOf',ones(1,n),'order',1:n,'panel',ones(1,n), ...
                'panelValues',NaN,'panelLabels',{{''}},'split','','splitCol',0, ...
                'keys',struct('Name',{},'Direction',{}));

            % --- the order keys this table can honour ---------------------
            cols = zeros(1,0);
            dirs = cell(1,0);
            for k = 1:numel(orderBy)
                if isempty(orderBy{k}), continue; end
                j = find(strcmpi(P.Names,orderBy{k}),1);
                % Named a second time a parameter adds nothing: the first has
                % already decided every comparison it could.
                if isempty(j) || any(cols == j), continue; end
                if isempty(orderDir),        way = 'ascending';
                elseif isscalar(orderDir),   way = lower(orderDir{1});
                elseif k <= numel(orderDir), way = lower(orderDir{k});
                else,                        way = 'ascending';
                end
                cols(end+1) = j;   %#ok<AGROW>
                dirs{end+1} = way; %#ok<AGROW>
                A.keys(end+1) = struct('Name',P.Names{j},'Direction',way);
            end

            % --- panels ---------------------------------------------------
            s = 0;
            if ~isempty(splitBy)
                j = find(strcmpi(P.Names,splitBy),1);
                if ~isempty(j) && any(~isnan(P.Values(:,j))), s = j; end
            end
            if s > 0
                v  = P.Values(:,s);
                uv = unique(v(~isnan(v))).';
                k  = find(cols == s,1);
                if ~isempty(k) && strcmp(dirs{k},'descending'), uv = fliplr(uv); end
                pv = uv;
                if any(isnan(v)), pv(end+1) = NaN; end
                panelOf = zeros(1,n);
                for i = 1:n
                    if isnan(v(i)), panelOf(i) = numel(pv);
                    else,           panelOf(i) = find(uv == v(i),1);
                    end
                end
                labels = cell(1,numel(pv));
                for i = 1:numel(pv)
                    labels{i} = mabr.ui.TraceOrganizer.paramValueText(P.Names{s},pv(i));
                end
                A.panelOf     = panelOf;
                A.panelValues = pv;
                A.panelLabels = labels;
                A.split       = P.Names{s};
                A.splitCol    = s;
            end

            % --- order: panel, then the keys, then where each stands now ---
            M = A.panelOf(:);
            for k = 1:numel(cols)
                c = P.Values(:,cols(k));
                if strcmp(dirs{k},'descending'), c = -c; end   % NaN stays last
                M = [M c]; %#ok<AGROW>
            end
            M = [M rank(:)];
            [~,ord] = sortrows(M);
            A.order = ord(:).';
            A.panel = A.panelOf(A.order);
        end

        function P = paramTable(params)
            % Traces' stimulus parameters as one table. params is a cell of
            % scalar structs, one per trace (mabr.ui.Trace.parameters).
            %   P.Names  {1 x nP} every name any trace carries, in order of
            %            first appearance
            %   P.Values [n x nP] NaN where a trace lacks it
            n = numel(params);
            names = cell(1,0);
            for k = 1:n
                f = reshape(fieldnames(params{k}),1,[]);
                names = [names f(~ismember(f,names))]; %#ok<AGROW>
            end
            V = nan(n,numel(names));
            for k = 1:n
                for j = 1:numel(names)
                    if isfield(params{k},names{j}), V(k,j) = params{k}.(names{j}); end
                end
            end
            P = struct('Names',{names},'Values',V);
        end

        function p = blockParams(block)
            % The stimulus parameters of a finalized mabr.data.Block, from
            % its metadata: the informativeParams it declares -- the
            % dimensions the offline pipeline groups by -- or, where it
            % declares none, every numeric scalar it carries, the rule
            % mabr.stim.StimulusSet follows. Real numeric scalars only, as
            % doubles (mabr.ui.Trace.cleanParams); nothing is coerced.
            p = struct();
            try
                meta = block.Stim.Meta;
            catch
                return
            end
            if ~isstruct(meta) || ~isscalar(meta), return; end
            if isfield(meta,'informativeParams') && ~isempty(meta.informativeParams)
                names = cellstr(meta.informativeParams);
            else
                names = setdiff(fieldnames(meta), ...
                    {'ID','Label','informativeParams','alternatePolarity'},'stable');
            end
            q = struct();
            for k = 1:numel(names)
                if isfield(meta,names{k}), q.(names{k}) = meta.(names{k}); end
            end
            p = mabr.ui.Trace.cleanParams(q);
        end

        function [pos,isBottom] = panelRects(N,W,H,labelPx,titled)
            % Where N panels go in a figure W x H pixels whose trace labels
            % are labelPx wide (0: none shown): normalized [x y w h] per
            % panel, left to right then top to bottom, and which have no
            % panel below them (those carry the time axis label). Pure, so
            % it is tested on its own.
            %
            % One untitled panel -- the stack as it always was -- keeps the
            % original geometry: MATLAB's default axes box, its left edge
            % moved right only as far as the labels need, half the figure at
            % most. Otherwise the panels form a grid of equal columns, each
            % with room on its left for its own labels: one row while every
            % column can still be MinPanelPx wide, more rows when not, with
            % room above each row for its titles.
            if nargin < 5, titled = false; end
            W = max(W,1); H = max(H,1);
            rightEdge = 0.955;
            if N <= 1 && ~titled
                left = 0.13;
                if labelPx > 0, left = min(0.5,max(0.13,(labelPx+16)/W)); end
                pos = [left 0.11 rightEdge-left 0.815];
                isBottom = true;
                return
            end
            N      = max(N,1);
            usable = rightEdge*W;
            gut0   = max(mabr.ui.TraceOrganizer.MinGutterPx,labelPx+16);
            gap    = 10;
            cols   = 1;
            for c = N:-1:1
                g = min(gut0,0.5*usable/c);
                if (usable - c*g - (c-1)*gap)/c >= mabr.ui.TraceOrganizer.MinPanelPx
                    cols = c;
                    break
                end
            end
            gut  = min(gut0,0.5*usable/cols);
            if cols == 1, gut = max(gut,min(0.13*W,0.5*usable)); end
            rows = ceil(N/cols);
            pw   = max(1,(usable - cols*gut - (cols-1)*gap)/cols);
            top  = 0.955*H - 22;   % under the status line, over a title
            bot  = 0.11*H;         % tick labels and the time axis label
            rgap = 48;             % one row's tick labels, the next row's titles
            ph   = max(1,(top - bot - (rows-1)*rgap)/rows);
            pos      = zeros(N,4);
            isBottom = false(N,1);
            for k = 1:N
                r = ceil(k/cols);
                c = k - (r-1)*cols;
                x = gut + (c-1)*(pw + gap + gut);
                y = top - r*ph - (r-1)*rgap;
                pos(k,:)    = [x/W y/H pw/W ph/H];
                isBottom(k) = k + cols > N;
            end
        end

        function s = paramValueText(name,v)
            % One parameter value as a label or a panel title reads it:
            % '8 kHz', '60 dB', 'Duration 0.005' -- the units
            % mabr.stim.StimulusSet claims for a name, and the name where it
            % claims none -- or 'No Frequency' for the traces that lack it.
            if isnan(v), s = sprintf('No %s',name); return; end
            u = mabr.stim.StimulusSet.paramUnit(name);
            if isempty(u), s = sprintf('%s %g',name,v);
            else,          s = sprintf('%g %s',v,u);
            end
        end

        function vary = varyingCols(V)
            % The columns of a parameter table that vary across its rows:
            % more than one value among the traces carrying it, or carried by
            % some traces and not by others.
            vary = zeros(1,0);
            for j = 1:size(V,2)
                v  = V(:,j);
                ok = ~isnan(v);
                if numel(unique(v(ok))) > 1 || (any(ok) && ~all(ok))
                    vary(end+1) = j; %#ok<AGROW>
                end
            end
        end
    end

    methods (Static, Access = private)
        function v = nameArg(v,what)
            if isstring(v) && isscalar(v), v = char(v); end
            if isempty(v), v = ''; return; end
            assert(ischar(v) && isrow(v),'mabr:ui:TraceOrganizer:name', ...
                '%s must be a stimulus parameter name.',what);
        end

        function k = panelKeyOf(labels)
            % What a set of panels is: how many, and their titles.
            k = sprintf('%d|%s',numel(labels),strjoin(labels,newline));
        end

        function w = labelWidth(h)
            % A visible label's width in pixels; 0 for one that is absent or
            % hidden. Reading Extent lays the text out, which is the cost the
            % incremental margin fit exists to avoid repeating.
            w = 0;
            if isempty(h) || ~isgraphics(h) || strcmp(h.Visible,'off'), return; end
            u = h.Units;
            h.Units = 'pixels';
            w = h.Extent(3);
            h.Units = u;
        end

        function s = shortName(file)
            [~,n,e] = fileparts(file);
            s = [n e];
        end
    end
end
