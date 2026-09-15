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
%     Up / Down            amplitude larger / smaller
%     Shift+Up / Down      spacing wider / narrower
%     Ctrl+Up / Down       move selected trace up / down the stack
%     0                    reset amplitude to 1x
%     n                    toggle per-trace vs. common normalization
%     r                    restack evenly in current visual order
%     a / Escape           select all / none
%     l                    toggle stimulus ID labels
%     p / c                mark peaks / clear markers
%     b                    cycle the error band
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
%   normalization mode, and axis limits -- so loadView reproduces the view
%   exactly as it was saved.
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
        % optional field with isfield for exactly this reason.
        FileVersion = 4;
        CILevels    = [0.90 0.95 0.99];   % the levels the Band menu offers
    end

    properties (SetAccess = private, Transient)
        Figure      % readable so callers can export or annotate the view
        Axes
    end

    properties (Access = private, Transient)
        Toolbar
        ContextMenu
        dragIdx     = [];
        dragStartY  = 0;
        dragStartOffset = 0;
        dragMoved   = false;
        FigTag (1,:) char = '';
        BlockListener   % listener on an AcqController's BlockReady event
        Inspector       % mabr.ui.TraceInspector, at most one at a time
        NotesView       % mabr.ui.Notes, the button-and-window form
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
            obj.addTrace(m,t,lbl,sid,sweeps);
        end

        function tr = addTrace(obj,data,time,label,stimID,sweeps)
            if nargin < 4, label  = ''; end
            if nargin < 5, stimID = ''; end
            if nargin < 6, sweeps = []; end
            tr = mabr.ui.Trace(data,time,label,stimID);
            tr.ID = numel(obj.Traces)+1;
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
            obj.computeBands(numel(obj.Traces));
            if obj.isvalidView(), obj.plotAll(true); end
        end

        function clear(obj)
            delete(obj.Traces);
            obj.Traces = mabr.ui.Trace.empty;
            obj.pruneInspector();
            if obj.isvalidView(), cla(obj.Axes); obj.refreshStatus(); end
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
            [~,ord] = sort([obj.Traces.YOffset],'descend');
            obj.Traces = obj.Traces(ord);
            for k = 1:numel(obj.Traces)
                obj.Traces(k).YOffset = -(k-1)*obj.YSpacing;
            end
            obj.plotAll(false);
            obj.refreshStatus();
        end

        function moveTrace(obj,idx,delta)
            % Swap a trace with its neighbour in the stack.
            if numel(idx) ~= 1, obj.status('Select one trace to move.'); return; end
            j = idx + delta;
            if j < 1 || j > numel(obj.Traces), return; end
            obj.Traces([idx j]) = obj.Traces([j idx]);
            for k = 1:numel(obj.Traces)
                obj.Traces(k).YOffset = -(k-1)*obj.YSpacing;
            end
            obj.plotAll(false);
        end

        function removeTraces(obj,idx)
            if nargin < 2, idx = obj.selectedIndices(); end
            if isempty(idx), obj.status('Select a trace first.'); return; end
            delete(obj.Traces(idx));
            obj.Traces(idx) = [];
            obj.pruneInspector();
            obj.plotAll(false);
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
                obj.ensureFigure();
                obj.plotAll(true);
                if ~isempty(V.XLim), obj.Axes.XLim = V.XLim; end
                if ~isempty(V.YLim), obj.Axes.YLim = V.YLim; end
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
            obj.Axes = axes('Parent',obj.Figure,'Box','on','NextPlot','add', ...
                'YTick',[],'XGrid','on','YGrid','on','GridLineStyle',':');
            mabr.ui.hideAxesToolbar(obj.Axes);
            xlabel(obj.Axes,'Time (ms)');
            obj.buildToolbar();
            obj.buildMenus();
            obj.refreshStatus();
        end

        function buildToolbar(obj)
            % Every action here is also in the menu bar -- the toolbar is a
            % shortcut, never the only route to a function. Each button draws
            % the glyph named in obj.glyph so its meaning is readable without
            % having to hover for the tooltip.
            ink   = [0.16 0.26 0.42];   % amplitude / spacing / file
            alert = [0.72 0.12 0.12];   % peaks
            warn  = [0.45 0.16 0.16];   % destructive

            obj.Toolbar = uitoolbar(obj.Figure);
            obj.toolButton('grow',   ink,  'Larger amplitude (Up arrow)',        @() obj.scaleTraces(obj.GainStep));
            obj.toolButton('shrink', ink,  'Smaller amplitude (Down arrow)',     @() obj.scaleTraces(1/obj.GainStep));
            obj.toolButton('spread', ink,  'Wider spacing (Shift+Up)',           @() obj.setSpacing(obj.YSpacing*obj.SpacingStep),true);
            obj.toolButton('squeeze',ink,  'Tighter spacing (Shift+Down)',       @() obj.setSpacing(obj.YSpacing/obj.SpacingStep));
            obj.toolButton('peaks',  alert,'Mark peaks on selection (p)',        @() obj.markPeaks(),true);
            obj.toolButton('inspect',alert,'Inspect selected trace (i, or double-click)',@() obj.inspectTrace());
            % The same notes component the main window carries, over the same
            % store once listenTo has adopted the session's -- so a note about
            % a trace can be written where the trace is being looked at.
            % Routed through showNotes rather than built with
            % mabr.ui.Notes.toolbarButton because this figure (and so this
            % toolbar) is rebuilt every time a closed organizer is shown again,
            % and a view built here each time would strand the previous one.
            notesTool = uipushtool(obj.Toolbar,'Separator','on', ...
                'Tooltip','Session notes (saved with the data)', ...
                'CData',mabr.ui.Icon.fromArt(mabr.ui.Notes.glyph(),ink), ...
                'ClickedCallback',@(~,~) obj.showNotes());
            obj.ensureNotesView();
            obj.NotesView.setTool(notesTool);   % so the count reaches the tooltip
            obj.toolButton('save',   ink,  'Save view (Ctrl+S)',                 @() obj.saveView(),true);
            obj.toolButton('load',   ink,  'Load view (Ctrl+O)',                 @() obj.loadView());
            obj.toolButton('trash',  warn, 'Remove all traces',                  @() obj.clear());
            obj.toolButton('help',   ink,  'Keyboard shortcuts (F1)',            @() obj.showHelp(),true);
        end

        function toolButton(obj,name,rgb,tip,fcn,sep)
            if nargin < 6, sep = false; end
            sepStr = 'off'; if sep, sepStr = 'on'; end
            uipushtool(obj.Toolbar,'Tooltip',tip,'CData',obj.icon(name,rgb), ...
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
                it('Move up'                     ,@() obj.moveTrace(obj.selectedIndices(),-1),'sep',true) , ...
                it('Move down'                   ,@() obj.moveTrace(obj.selectedIndices(),+1)) , ...
                it('Rename...'                   ,@() obj.promptRename(),'sep',true) , ...
                it('Set colour...'               ,@() obj.promptColor()) , ...
                it('Show stimulus ID labels'     ,@() obj.toggleLabels(),'sep',true,'tag','labels') , ...
                it('Hide/show selected'          ,@() obj.toggleVisible()) , ...
                it('Remove selected'             ,@() obj.removeTraces(),'sep',true) , ...
                it('Clear all'                   ,@() obj.clear()) };

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
        function plotAll(obj,resetLimits)
            if ~obj.isvalidView(), return; end
            if nargin < 2, resetLimits = false; end
            if isempty(obj.Traces), obj.refreshStatus(); return; end

            sc = obj.yscale();

            if resetLimits
                tAll = arrayfun(@(t) reshape(t.Time([1 end]),1,2)*1000, ...
                    obj.Traces,'UniformOutput',false);
                tAll = vertcat(tAll{:});
                obj.Axes.XLim = [min(tAll(:,1)) max(tAll(:,2))];
            end
            labelX = obj.labelX();

            for k = 1:numel(obj.Traces)
                tr = obj.Traces(k);
                tr.ShowLabel = obj.ShowLabels;
                tr.plot(obj.Axes,sc(k),labelX);
                tr.LineHandle.ButtonDownFcn  = @(~,~) obj.onTraceClick(k);
                tr.LabelHandle.ButtonDownFcn = @(~,~) obj.onTraceClick(k);
                obj.attachContextMenu(tr.LineHandle);
                obj.attachContextMenu(tr.LabelHandle);
            end

            if resetLimits
                allY = [obj.Traces.YOffset];
                obj.Axes.YLim = [min(allY)-obj.YSpacing, max(allY)+obj.YSpacing];
            end
            obj.fitLabelMargin();
            obj.refreshStatus();
        end

        function x = labelX(obj)
            % Anchor for the right-aligned labels: just left of the y-axis, so
            % the text runs outward into the margin instead of over the traces.
            x = obj.Axes.XLim(1) - 0.015*diff(obj.Axes.XLim);
        end

        function fitLabelMargin(obj)
            % Widen the axes' left inset to whatever the longest label needs.
            % Label pixel width depends only on the font, not on the axes size,
            % so measuring and then resizing cannot chase its own tail.
            % Also fires as a resize callback, possibly before the axes exists.
            if ~obj.isvalidView() || isempty(obj.Axes) || ~isgraphics(obj.Axes)
                return
            end
            ax        = obj.Axes;
            rightEdge = 0.955;     % held fixed; only the left edge moves
            minLeft   = 0.13;      % MATLAB's default inset
            left      = minLeft;

            if obj.ShowLabels && ~isempty(obj.Traces)
                figPos = getpixelposition(obj.Figure);
                w = 0;
                for k = 1:numel(obj.Traces)
                    h = obj.Traces(k).LabelHandle;
                    if isempty(h) || ~isgraphics(h) || strcmp(h.Visible,'off')
                        continue
                    end
                    u = h.Units;
                    h.Units = 'pixels';
                    w = max(w,h.Extent(3));
                    h.Units = u;
                end
                if w > 0
                    left = min(0.5,max(minLeft,(w+16)/figPos(3)));
                end
            end
            ax.Position = [left ax.Position(2) rightEdge-left ax.Position(4)];
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
        function onTraceClick(obj,k)
            mods  = get(obj.Figure,'SelectionType');
            % 'open' = double-click. MATLAB delivers the first click of the
            % pair as a normal one, so a drag is already armed by the time
            % this arrives -- disarm it, or the inspector opens with the
            % trace still following the mouse.
            if strcmp(mods,'open')
                obj.dragIdx   = [];
                obj.dragMoved = false;
                obj.select(k);
                obj.inspectTrace(k);
                return
            end
            % 'extend' = shift-click, 'alt' = ctrl-click (or right-click, which
            % the context menu handles before this fires).
            extend = any(strcmp(mods,{'extend','alt'}));
            obj.select(k,extend);

            obj.dragIdx = k;
            cp = obj.Axes.CurrentPoint;
            obj.dragStartY = cp(1,2);
            obj.dragStartOffset = obj.Traces(k).YOffset;
            obj.dragMoved = false;
        end

        function doDrag(obj)
            if isempty(obj.dragIdx), return; end
            cp = obj.Axes.CurrentPoint;
            dy = cp(1,2) - obj.dragStartY;
            if dy == 0, return; end
            obj.dragMoved = true;
            sc = obj.yscale();
            obj.Traces(obj.dragIdx).YOffset = obj.dragStartOffset + dy;
            obj.Traces(obj.dragIdx).plot(obj.Axes,sc(obj.dragIdx),obj.labelX());
        end

        function endDrag(obj)
            moved = obj.dragMoved;
            obj.dragIdx = [];
            obj.dragMoved = false;
            if moved, obj.refreshStatus(); end
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
                case 'i'
                    obj.inspectTrace();
                case 'h'
                    obj.toggleVisible();
                case {'delete','backspace'}
                    obj.removeTraces();
                case 's'
                    if ctrl, obj.saveView(); end
                case 'o'
                    if ctrl, obj.loadView(); end
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
                'Amplitude commands act on the selection, or on all traces'
                'when nothing is selected.'
                ''
                'Up / Down            amplitude larger / smaller'
                'Shift+Up / Down      spacing wider / narrower'
                'Ctrl+Up / Down       move selected trace up / down'
                '0                    reset amplitude to 1x'
                'n                    per-trace vs. common normalization'
                'r                    restack evenly'
                'a / Escape           select all / none'
                'l                    toggle stimulus ID labels'
                'p / c                mark peaks / clear markers'
                'b                    cycle the error band'
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
            obj.status(sprintf('%d trace(s), %d selected  |  spacing %.3g  |  %s scale%s', ...
                n,numel(s),obj.YSpacing,mode,band));
        end

        function status(obj,txt)
            if obj.isvalidView()
                title(obj.Axes,txt,'FontWeight','normal','FontSize',9, ...
                    'Interpreter','none');
            end
        end
    end

    methods (Static, Access = private)
        function c = icon(name,rgb)
            % 16x16 CData from a named glyph.
            c = mabr.ui.Icon.fromArt(mabr.ui.TraceOrganizer.glyph(name),rgb);
        end

        function rows = glyph(name)
            % ASCII art, one 16-char string per row. Kept as art rather than
            % index math because the shapes have to be legible at 16 px and
            % that is only checkable by looking at them.
            switch name
                case 'grow'      % arrow up off a baseline: bigger amplitude
                    rows = {'.......XX.......'
                            '......XXXX......'
                            '.....XXXXXX.....'
                            '....XXXXXXXX....'
                            '...XXXXXXXXXX...'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '................'
                            'XXXXXXXXXXXXXXXX'
                            '................'
                            '................'
                            '................'};
                case 'shrink'    % arrow down toward a baseline
                    rows = {'XXXXXXXXXXXXXXXX'
                            '................'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '.......XX.......'
                            '...XXXXXXXXXX...'
                            '....XXXXXXXX....'
                            '.....XXXXXX.....'
                            '......XXXX......'
                            '.......XX.......'
                            '................'
                            '................'
                            '................'};
                case 'spread'    % two rails, arrows pushing them apart
                    rows = {'................'
                            'XXXXXXXXXXXXXXXX'
                            '................'
                            '.......XX.......'
                            '......XXXX......'
                            '.....XXXXXX.....'
                            '................'
                            '................'
                            '................'
                            '.....XXXXXX.....'
                            '......XXXX......'
                            '.......XX.......'
                            '................'
                            'XXXXXXXXXXXXXXXX'
                            '................'
                            '................'};
                case 'squeeze'   % two rails, arrows pulling them together
                    rows = {'................'
                            'XXXXXXXXXXXXXXXX'
                            '................'
                            '.....XXXXXX.....'
                            '......XXXX......'
                            '.......XX.......'
                            '................'
                            '................'
                            '................'
                            '.......XX.......'
                            '......XXXX......'
                            '.....XXXXXX.....'
                            '................'
                            'XXXXXXXXXXXXXXXX'
                            '................'
                            '................'};
                case 'peaks'     % marker dropped onto a waveform peak
                    rows = {'................'
                            '....XXXXXXX.....'
                            '.....XXXXX......'
                            '......XXX.......'
                            '.......X........'
                            '................'
                            '................'
                            '.......XX.......'
                            '......X..X......'
                            '.....X....X.....'
                            '....X......X....'
                            '...X........X...'
                            'XXX..........XXX'
                            '................'
                            '................'
                            '................'};
                case 'inspect'   % magnifying glass: look at one trace closely
                    rows = {'................'
                            '.....XXXX.......'
                            '...XX....XX.....'
                            '..X........X....'
                            '..X........X....'
                            '..X........X....'
                            '..X........X....'
                            '...XX....XX.....'
                            '.....XXXX.X.....'
                            '..........XX....'
                            '...........XX...'
                            '............XX..'
                            '.............XX.'
                            '................'
                            '................'
                            '................'};
                case 'save'      % floppy disk
                    rows = {'................'
                            '.XXXXXXXXXXXXXX.'
                            '.X....XXXX....X.'
                            '.X....XXXX....X.'
                            '.X....XXXX....X.'
                            '.X............X.'
                            '.X.XXXXXXXXXX.X.'
                            '.X.X........X.X.'
                            '.X.X........X.X.'
                            '.X.X........X.X.'
                            '.X.XXXXXXXXXX.X.'
                            '.XXXXXXXXXXXXXX.'
                            '................'
                            '................'
                            '................'
                            '................'};
                case 'load'      % folder with a waveform lifting out of it
                    rows = {'................'
                            '................'
                            '.......XX.......'
                            '......XXXX......'
                            '.....XXXXXX.....'
                            '.......XX.......'
                            '.......XX.......'
                            '................'
                            'XXXX............'
                            'X..XXXXX........'
                            'X......XXXXXXXX.'
                            'X..............X'
                            'X..............X'
                            'XXXXXXXXXXXXXXXX'
                            '................'
                            '................'};
                case 'trash'     % waste bin: removes every trace
                    rows = {'................'
                            '......XXXX......'
                            '...XXXXXXXXXX...'
                            '................'
                            '..XXXXXXXXXXXX..'
                            '..X.X.X..X.X.X..'
                            '..X.X.X..X.X.X..'
                            '..X.X.X..X.X.X..'
                            '..X.X.X..X.X.X..'
                            '..X.X.X..X.X.X..'
                            '..X.X.X..X.X.X..'
                            '..X.X.X..X.X.X..'
                            '..XXXXXXXXXXXX..'
                            '................'
                            '................'
                            '................'};
                case 'help'      % question mark
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

        function s = shortName(file)
            [~,n,e] = fileparts(file);
            s = [n e];
        end
    end
end
