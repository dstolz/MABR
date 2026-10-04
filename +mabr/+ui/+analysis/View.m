classdef (Abstract) View < handle
% mabr.ui.analysis.View  What every tab of the analysis app has in common.
%
%   A view is one tab of mabr.ui.AnalysisApp -- Session, Grid, Series,
%   Trials, Study -- drawing what mabr.ui.analysis.Model holds and sending
%   every change back through Model methods (never through Session's own
%   mutating methods, which would skip undo, autosave and the events every
%   other view listens to). This base class is the part they share:
%
%     - LAZY BUILD. The app constructs a view the first time its tab is
%       shown: View(parent,model,host) stores its arguments, runs the
%       subclass's build() into Parent, and subscribes to every Model event.
%       Build into obj.Parent through ONE root container (a uigridlayout,
%       usually): Parent is a 1x1 grid the empty-state overlay shares.
%     - EVENTS INTO REFRESH. While its tab is showing, a Model event calls
%       refresh(what,keys) (ChangeData's What and Keys); while hidden the
%       view only marks itself Dirty, and activate() refreshes it in one go
%       ("all") when its tab is shown again -- so five views listening to
%       one Model cost one redraw, not five. Status chatter does not make a
%       hidden view Dirty: StatusChanged with What "message" (every note a
%       Session makes while it analyses) or "save" (every autosave). refresh
%       therefore receives words it may not care about ("message", "save",
%       "busy", "idle", "queue", ...) and must return at once for any it
%       does not draw -- never redraw everything for an unknown word.
%       SessionChanged and RootChanged always arrive as "all". A
%       ResultsChanged raised by the same Model call as the
%       SettingsChanged(all) just before it (a settings change that
%       re-fits) is passed over: the "all" already drew it
%       (coalescedEvent; a subclass overriding onModelEvent calls it first).
%     - WRITE ON CHANGE. put(key,h,prop,v) writes a graphics property only
%       when it differs from what was last written THERE (Written), never by
%       reading the graphics back: reading a uifigure property goes through
%       the browser, and writing an unchanged axes property relays it out.
%     - NO RE-ENTRY. renderGuarded(fcn) runs a render once at a time; a
%       render asked for while one is in progress (legend() and drawnow
%       process events, so a timer tick can land inside one) is remembered
%       and run once more when the outer pass returns -- LivePlot's rule.
%     - EMPTY STATES. showEmpty(text,actions) lays a message (and up to two
%       buttons) over the view, Tag Analysis<Name>Empty; hideEmpty() lifts
%       it. The texts are the app's (11 sec. 12), e.g. "Open a session from
%       the browser (double-click, Enter, or Open)."
%     - LOOK PERSISTENCE. Each subclass defines static factoryDefaults(),
%       loadDefaults() and saveDefaults(d) over its own pref (ViewPrefKey,
%       "OfflineAnalysis<Name>") -- View.loadLook/saveLook do the forgiving
%       part -- and the instance displaySettings()/applySettings(s)/
%       savePrefs(). The constructor applies loadDefaults() BEFORE build(),
%       so the controls are drawn from the saved look. savePrefs is called
%       ONLY from that view's own control callbacks: a script or a test
%       driving a view must not change how the user's next window looks.
%
%     - TIME AXES. Latencies are shown re SOUND ARRIVAL when the session
%       has a latency offset (a conduction delay and/or a system time
%       offset; mabr.ui.analysis.Model.latencyOffset). The stored times
%       (Session.Time, Peaks latencies) are raw -- re the timing pulse --
%       so every time axis goes through the ONE helper here: T =
%       timeAxis() gives Offset (ms), Label ("Time re sound arrival (ms)"
%       with a conduction delay, "Time re onset (ms) − 0.08 ms offset" with
%       a system offset alone, else "Time re onset (ms)"), Tip (the delay in
%       words, Settings.describe's sentence; "" at 0) and Subtitle; x =
%       earTime(tRaw) converts (tRaw - Offset); tRaw = rawTime(x) is the
%       inverse a click handler needs before calling Model.setPeak (which
%       takes RAW ms); labelTimeAxis(ax) writes the x label (and, with
%       Subtitle=true, the delay as the axes' subtitle) on change only.
%       Wave search windows (Settings.Waves) are in the RECORDING's time
%       (re the timing pulse), like the stored latencies: they are where
%       Session.pickPeaks searches, and a delay changes no pick. Draw them
%       through earTime too, or a window sits the offset later than the
%       samples it searched.
%
%   WHAT A VIEW CALLS. State: obj.Model's properties (Session, Selection,
%   Status, Settings, Busy, BlindReview, ...) read at refresh time, never
%   cached; every change through a Model method (11 sec. 2.2 and the
%   Model's help). The window, through obj.Host when it is not [] (a test
%   may build a view with no host):
%     obj.viewWrap(fcn[,area])   every component callback (Host.cb: errors
%                                reach the status line, keys go back to the
%                                plots afterwards); area "browser" for the
%                                browser's own controls
%     Host.setStatus(text,level) the status line (0 info, 1 warning, 2 error)
%     Host.activateTab(name)     "Session" | "Grid" | "Series" | "Trials" | "Study"
%     Host.openDialog(name,...)  "settings" (Tab=...), "export", "batch"
%                                (keys), "review" (keys), "levels" (column),
%                                "figureExport" (axes or panel)
%     Host.NoteEditor.open(target,text)   never a note typed into a table
%     Host.Visible               "off" while a test drives the window
%   and the shared statics: mabr.ui.analysis.Commands.hint(scope) for the
%   hint strip, FigureExport.addContextItems(cm,ax,obj.Host) to end every
%   plot's context menu, FigureExport.copyTable(tbl) for "Copy table",
%   Style (colours, glyphs, formatThreshold/formatUV/formatMs,
%   setButtonIcon with a LITERAL glyph), Compat (the only post-R2021b UI).
%
%   A subclass implements build() and refresh(what,keys). It may override
%   onCommand(id) for the keys its tab owns (the keymap is
%   mabr.ui.analysis.Commands), hoverPointer() for the pointer over what it
%   lets the mouse drag, flush() for debounced work, onModelEvent
%   (name,data) for finer routing than refresh gets, and displaySettings/
%   applySettings when its look is more than the ViewLook struct.
%
%   Names this class adds beyond the contract carry a View prefix (ViewName,
%   ViewPrefKey, ViewLook, viewWrap, ...) so a subclass's own property and
%   method names cannot collide with them.
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.Model,
%   mabr.ui.analysis.ChangeData, mabr.ui.analysis.Commands
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = protected)
        Model                       % mabr.ui.analysis.Model
        Host                        % mabr.ui.AnalysisApp (or [] in a test)
        Parent                      % the container the view builds into
        Handles   = struct()        % named graphics; special lines carry Tags
        Listeners = event.listener.empty
        Dirty     (1,1) logical = true
        IsActive  (1,1) logical = false
        Built     (1,1) logical = false
        Written   = struct()        % what put() last wrote, by key
        Rendering     (1,1) logical = false
        RenderPending (1,1) logical = false
        ViewLook  = struct()        % the display settings (displaySettings)
        ViewEvent (1,1) string = "" % the Model event refresh() is answering
    end

    properties (Dependent)
        ViewName                    % "Session", "Grid", ... (from the class name)
        ViewPrefKey                 % "OfflineAnalysis" + ViewName
    end

    properties (Access = private)
        VwEmptyPanel = []
        VwEmptyLabel = []
        VwEmptyButtons = gobjects(0)
        VwPendingRender = []
        VwAllOrigin (1,1) string = ""   % the call whose SettingsChanged(all) was the last event
        VwLayoutTimer = []              % layoutSoon's second look, once the window has drawn
    end

    methods (Abstract)
        build(obj)                  % create the view's graphics in obj.Parent
        refresh(obj,what,keys)      % redraw what changed (ChangeData's What/Keys)
    end

    methods
        function obj = View(parent,model,host)
            % View(parent,model,host): store, build, listen.
            %   parent  a container (uitab, uipanel, uigridlayout)
            %   model   mabr.ui.analysis.Model
            %   host    mabr.ui.AnalysisApp, or [] (tests drive a view alone)
            if nargin < 3, host = []; end
            obj.Model  = model;
            obj.Host   = host;
            % A 1x1 frame the subclass builds into, so the empty-state overlay
            % can share the subclass's cell and sit on top of it.
            frame = uigridlayout(parent,[1 1],'Padding',[0 0 0 0], ...
                'RowSpacing',0,'ColumnSpacing',0);
            try
                frame.BackgroundColor = mabr.ui.analysis.Style.Panel;
            catch
            end
            obj.Parent = frame;
            try
                obj.ViewLook = obj.viewLoadLook();
            catch
                obj.ViewLook = struct();
            end
            obj.build();
            obj.Built = true;
            obj.listen();
        end

        function delete(obj)
            try
                if ~isempty(obj.VwLayoutTimer) && isvalid(obj.VwLayoutTimer)
                    stop(obj.VwLayoutTimer);
                    delete(obj.VwLayoutTimer);
                end
            catch
            end
            try
                delete(obj.Listeners);
            catch
            end
            obj.Listeners = event.listener.empty;
            try
                if ~isempty(obj.Parent) && isvalid(obj.Parent), delete(obj.Parent); end
            catch
            end
        end

        function n = get.ViewName(obj)
            c = string(class(obj));
            c = extractAfter(c,max(strfind(c,".")));   % drop the package
            if endsWith(c,"View") && strlength(c) > 4
                c = extractBefore(c,strlength(c) - 3);
            end
            n = c;
        end

        function k = get.ViewPrefKey(obj)
            k = "OfflineAnalysis" + obj.ViewName;
        end

        function activate(obj)
            % The tab is now showing: catch up on anything missed while
            % hidden, and lay out again what is placed in pixels (the window
            % may have been resized while the tab was hidden, and a hidden
            % tab's panels are not told).
            obj.IsActive = true;
            if obj.Dirty
                obj.Dirty = false;
                obj.safeRefresh("all",strings(0,1));
            end
            if obj.Built, obj.layoutSoon(); end
        end

        function layoutSoon(obj)
            % relayoutNow now, with the sizes as they stand, and once more
            % a moment later -- when the window has drawn the tab and its
            % panels have their real sizes (a panel's SizeChangedFcn need
            % not fire for a size it reached while hidden). No timer when
            % the Model runs without them (tests: AutoRefresh false).
            try
                obj.relayoutNow();
            catch me
                mabr.log.vprintf(2,'%s view: layout (%s).',obj.ViewName,me.message);
            end
            try
                if isempty(obj.Model) || ~isvalid(obj.Model) || ~obj.Model.AutoRefresh, return; end
                if isempty(obj.VwLayoutTimer) || ~isvalid(obj.VwLayoutTimer)
                    obj.VwLayoutTimer = timer('Tag','MABR_OfflineLayout','StartDelay',0.35, ...
                        'ExecutionMode','singleShot','BusyMode','drop', ...
                        'TimerFcn',@(~,~) obj.vwLayoutTick());
                end
                stop(obj.VwLayoutTimer);
                start(obj.VwLayoutTimer);
            catch
            end
        end

        function relayoutNow(obj) %#ok<MANU>
            % Place what the view lays out in PIXELS for its panels' sizes
            % now (subclasses; the default has nothing to place).
        end

        function deactivate(obj)
            % The tab is no longer showing; events now only mark it Dirty.
            obj.IsActive = false;
        end

        function handled = onCommand(obj,id) %#ok<INUSD>
            % A key command the active view handles itself (Target "view" in
            % Commands.spec, and any other it chooses to intercept). Return
            % true when consumed; the default handles nothing.
            handled = false;
        end

        function p = hoverPointer(obj) %#ok<MANU>
            % The mouse pointer the view wants where the pointer is now (the
            % app asks on every move of the mouse over its window): "top"
            % over something that drags up and down, "left" over something
            % that drags sideways, "hand" over something a click sets, ""
            % for the ordinary arrow. Cheap: one CurrentPoint read and
            % arithmetic on what the view last drew, never a redraw. The
            % default wants nothing.
            p = "";
        end

        function flush(obj)
            % Run any pending debounced work now (tests call this rather
            % than waiting for a timer). The default catches up a Dirty view.
            if obj.IsActive && obj.Dirty
                obj.Dirty = false;
                obj.safeRefresh("all",strings(0,1));
            end
        end

        function s = displaySettings(obj)
            % The view's look as a plain struct (pref and configuration form).
            s = obj.ViewLook;
        end

        function applySettings(obj,s)
            % Adopt a look (a pref or a configuration), field by field and
            % forgivingly: only fields the view's factoryDefaults name are
            % taken, each in its own try, and the view redraws.
            if ~isstruct(s) || ~isscalar(s), return; end
            d = obj.viewFactory();
            f = fieldnames(d);
            for i = 1:numel(f)
                if ~isfield(s,f{i}), continue; end
                try
                    obj.ViewLook.(f{i}) = s.(f{i});
                catch me
                    mabr.log.vprintf(2,'%s view: ignoring %s (%s).',obj.ViewName,f{i},me.message);
                end
            end
            obj.refreshOrMark("all",strings(0,1));
        end

        function savePrefs(obj)
            % Remember the look for the next window -- ONLY from this view's
            % own control callbacks (never a setter, a script or a test).
            mabr.ui.analysis.View.saveLook(obj.ViewPrefKey,obj.displaySettings());
        end

        function T = timeAxis(obj)
            % The time axis of the open session (see the class help): struct
            % Offset (ms), Label, Tip, Subtitle.
            T = mabr.ui.analysis.View.timeAxisFor(obj.Model);
        end

        function x = earTime(obj,tRaw)
            % Raw times (ms re the timing pulse) as drawn: ms re sound
            % arrival when the session has a latency offset (tRaw - Offset).
            x = tRaw - mabr.ui.analysis.View.offsetOf(obj.Model);
        end

        function t = rawTime(obj,x)
            % The inverse of earTime: an axis position back to raw ms (what
            % Model.setPeak and every Session method take).
            t = x + mabr.ui.analysis.View.offsetOf(obj.Model);
        end

        function T = labelTimeAxis(obj,ax,opts)
            % Write the time axis' x label on AX (and, opts.Subtitle, the
            % delay as its subtitle) -- only when they changed (opts.Key
            % names the Written record; one per axes).
            arguments
                obj
                ax
                opts.Key (1,1) string = "vw_timeaxis"
                opts.Subtitle (1,1) logical = false
            end
            T = obj.timeAxis();
            try
                obj.put(opts.Key + "_x",ax.XLabel,'String',char(T.Label));
                obj.put(opts.Key + "_xtip",ax.XLabel,'UserData',char(T.Tip));
                if opts.Subtitle
                    obj.put(opts.Key + "_sub",ax.Subtitle,'String',char(T.Subtitle));
                end
            catch me
                mabr.log.vprintf(2,'%s view: time axis not labelled (%s).',obj.ViewName,me.message);
            end
        end

        function onModelEvent(obj,name,data)
            % Route one Model event. The default: SessionChanged/RootChanged
            % rebuild ("all"), everything else passes ChangeData's What/Keys
            % on to refresh -- now if the tab is showing, else at activate().
            obj.ViewEvent = string(name);
            if obj.coalescedEvent(name,data), return; end
            what = "all"; keys = strings(0,1);
            try
                what = data.What;
                keys = data.Keys;
            catch
            end
            if name == "SessionChanged" || name == "RootChanged"
                what = "all";
            end
            % Status chatter -- a sentence for the status line, an autosave --
            % changes nothing a view draws, so a hidden view does not count
            % it as missed work (a status message arrives with every note a
            % Session makes while it analyses, and an autosave after every
            % edit: counting them would make every tab switch a full redraw).
            % A showing view still hears them, and may ignore them.
            if ~(obj.IsActive && obj.Built) && name == "StatusChanged" && ...
                    any(what == ["message","save"])
                return
            end
            obj.refreshOrMark(what,keys);
        end
    end

    methods (Access = protected)
        function listen(obj)
            % One listener per Model event, each into onModelEvent.
            names = ["RootChanged","ProjectChanged","SessionChanged","ResultsChanged", ...
                "SelectionChanged","SettingsChanged","StatusChanged","BusyChanged"];
            L = event.listener.empty;
            for n = names
                L(end+1) = addlistener(obj.Model,char(n), ...
                    @(~,e) obj.viewEventSafe(n,e)); %#ok<AGROW>
            end
            obj.Listeners = L;
        end

        function skip = coalescedEvent(obj,name,data)
            % True for an event a view should pass over because the one
            % before it already drew it: ResultsChanged raised by the same
            % Model call as the SettingsChanged(all) just before it -- the
            % Model re-fits BEFORE raising either (setSettings), so the
            % "all" redraw already shows what the second announces. Call it
            % first thing in onModelEvent, for EVERY event (it remembers
            % which was the last). The events' order is the contract's.
            skip = false;
            origin = "";  what = "";
            try
                origin = string(data.Origin);
                what = string(data.What);
            catch
            end
            after = obj.VwAllOrigin;
            obj.VwAllOrigin = "";
            name = string(name);
            if name == "ResultsChanged" && origin ~= "" && origin == after
                skip = true;
            elseif name == "SettingsChanged" && what == "all"
                obj.VwAllOrigin = origin;
            end
        end

        function put(obj,key,h,prop,v)
            % Write h.(prop) = v only when v differs from what was last
            % written under KEY. Use one key per (object, property).
            key = char(key);
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                h.(char(prop)) = v;
                obj.Written.(key) = v;
            catch me
                mabr.log.vprintf(2,'%s view: could not set %s (%s).',obj.ViewName,char(prop),me.message);
            end
        end

        function forgetWritten(obj,prefix)
            % Drop the Written records whose key starts with PREFIX (all of
            % them when omitted) -- after the objects they describe were
            % rebuilt, or written behind put's back.
            if nargin < 2 || isempty(prefix)
                obj.Written = struct();
                return
            end
            f = fieldnames(obj.Written);
            drop = f(startsWith(f,char(prefix)));
            if ~isempty(drop), obj.Written = rmfield(obj.Written,drop); end
        end

        function renderGuarded(obj,fcn)
            % Run FCN (no arguments) unless a render is already running; one
            % asked for meanwhile runs once more when the outer pass ends.
            if obj.Rendering
                obj.RenderPending = true;
                obj.VwPendingRender = fcn;
                return
            end
            obj.Rendering = true;
            guard = onCleanup(@() obj.viewEndRender());
            fcn();
            n = 0;
            while isvalid(obj) && obj.RenderPending && n < 3
                obj.RenderPending = false;
                f = obj.VwPendingRender;
                obj.VwPendingRender = [];
                if isempty(f), f = fcn; end
                f();
                n = n + 1;
            end
        end

        function showEmpty(obj,text,actions)
            % Lay TEXT over the view, with up to two buttons beneath it.
            %   text     the sentence (11 sec. 12 wording)
            %   actions  struct array Text, Fcn (no-argument function), and
            %            optionally Glyph (a mabr.ui.Icon name) and Tooltip;
            %            [] for none. Buttons are tagged
            %            Analysis<Name>EmptyAction1/2.
            if nargin < 3, actions = []; end
            obj.viewEnsureEmpty();
            obj.put('vw_empty_text',obj.VwEmptyLabel,'Text',char(text));
            for k = 1:2
                b = obj.VwEmptyButtons(k);
                if k <= numel(actions)
                    a = actions(k);
                    obj.put("vw_empty_b" + k + "_text",b,'Text',char(a.Text));
                    tip = "";
                    if isfield(a,'Tooltip'), tip = string(a.Tooltip); end
                    obj.put("vw_empty_b" + k + "_tip",b,'Tooltip',char(tip));
                    fcn = a.Fcn;
                    b.ButtonPushedFcn = obj.viewWrap(@(~,~) fcn());
                    glyph = "";
                    if isfield(a,'Glyph') && ~isempty(a.Glyph), glyph = string(a.Glyph); end
                    gk = char("vw_empty_b" + k + "_glyph");
                    if ~isfield(obj.Written,gk) || obj.Written.(gk) ~= glyph
                        % a button reused for an action without a picture
                        % must not keep the last one's
                        if glyph == ""
                            try
                                b.Icon = '';
                            catch
                            end
                        else
                            mabr.ui.analysis.View.viewIcon(b,glyph);
                        end
                        obj.Written.(gk) = glyph;
                    end
                    obj.put("vw_empty_b" + k + "_vis",b,'Visible','on');
                else
                    obj.put("vw_empty_b" + k + "_vis",b,'Visible','off');
                end
            end
            obj.put('vw_empty_vis',obj.VwEmptyPanel,'Visible','on');
        end

        function hideEmpty(obj)
            % Lift the empty-state overlay (no-op when it was never shown).
            if isempty(obj.VwEmptyPanel) || ~isvalid(obj.VwEmptyPanel), return; end
            obj.put('vw_empty_vis',obj.VwEmptyPanel,'Visible','off');
        end

        function tf = isEmptyShown(obj)
            % True while the empty-state overlay is up.
            tf = ~isempty(obj.VwEmptyPanel) && isvalid(obj.VwEmptyPanel) && ...
                strcmp(obj.VwEmptyPanel.Visible,'on');
        end

        function f = viewWrap(obj,fcn,area)
            % A component callback wrapped by the host's cb() (so keyboard
            % routing knows where the user is), or FCN itself with no host.
            if nargin < 3, area = "workspace"; end
            if ~isempty(obj.Host) && isvalid(obj.Host)
                f = obj.Host.cb(fcn,area);
            else
                f = fcn;
            end
        end

        function refreshOrMark(obj,what,keys)
            % refresh now when the tab is showing, else remember to.
            if obj.IsActive && obj.Built
                obj.safeRefresh(what,keys);
            else
                obj.Dirty = true;
            end
        end

        function safeRefresh(obj,what,keys)
            % refresh, with any error logged rather than thrown into the
            % event that triggered it.
            try
                obj.refresh(what,keys);
            catch me
                mabr.log.vprintf(1,'%s view: refresh (%s) failed: %s',obj.ViewName,what,me.message);
                mabr.log.vprintf(2,me);
            end
        end
    end

    methods (Static)
        function d = loadLook(prefKey,factory)
            % Forgiving pref read: FACTORY with every field the stored struct
            % holds under the same name and a compatible type; any problem
            % gives FACTORY. A subclass's loadDefaults() is one line over it.
            d = factory;
            try
                k = char(prefKey);
                if ~ispref('MABR',k), return; end
                p = getpref('MABR',k);
                if ~isstruct(p) || ~isscalar(p), return; end
                f = fieldnames(d);
                for i = 1:numel(f)
                    if ~isfield(p,f{i}), continue; end
                    v = p.(f{i});  dv = d.(f{i});
                    if strcmp(class(v),class(dv))
                        d.(f{i}) = v;
                    elseif isnumeric(v) && (isnumeric(dv) || islogical(dv))
                        d.(f{i}) = cast(v,'like',dv);
                    elseif islogical(v) && isnumeric(dv)
                        d.(f{i}) = double(v);
                    elseif (ischar(v) || isstring(v)) && (ischar(dv) || isstring(dv))
                        if isstring(dv), d.(f{i}) = string(v);
                        else,            d.(f{i}) = char(v); end
                    end
                end
            catch
                d = factory;
            end
        end

        function saveLook(prefKey,d)
            % Guarded pref write (a rig whose prefs are not writable must not
            % lose a window over a look it cannot store). A subclass's
            % saveDefaults(d) is one line over it.
            try
                setpref('MABR',char(prefKey),d);
            catch
            end
        end

        function T = timeAxisFor(model)
            % The time axis for a Model (see the class help): struct Offset
            % (ms; raw - Offset = drawn), Label, Tip, Subtitle. A conduction
            % delay makes it "re sound arrival"; a system time offset alone
            % keeps "re onset" and names the offset (11 sec. 7.3). Also for
            % dialogs and tests.
            [o,d,t] = mabr.ui.analysis.View.offsetOf(model);
            T = struct('Offset',o,'Label',"Time re onset (ms)",'Tip',"",'Subtitle',"");
            if o == 0 && d == 0, return; end
            if d ~= 0
                T.Label = "Time re sound arrival (ms)";
                T.Subtitle = string(sprintf('re sound arrival (%.2f ms after the timing pulse)',o));
            else
                T.Label = "Time re onset (ms) − " + string(sprintf('%g',t)) + " ms offset";
                T.Subtitle = string(sprintf('less a %g ms system offset',t));
            end
            tip = "";
            try
                tip = string(model.latencyText());
            catch
            end
            if tip == ""
                tip = string(sprintf('Times are %.2f ms earlier than the timing pulse''s.',o));
            end
            T.Tip = tip;
        end

        function [o,d,t] = offsetOf(model)
            % Model.latencyOffset ([o,d,t] in ms), zeros when there is none
            % to ask.
            o = 0; d = 0; t = 0;
            try
                if ~isempty(model) && isvalid(model)
                    [o,d,t] = model.latencyOffset();
                end
            catch
                o = 0; d = 0; t = 0;
            end
            if ~isscalar(o) || ~isfinite(o), o = 0; end
            if ~isscalar(d) || ~isfinite(d), d = 0; end
            if ~isscalar(t) || ~isfinite(t), t = 0; end
        end

        function ok = viewIcon(btn,glyph)
            % Style.setButtonIcon for a glyph held in a variable. Literal
            % glyph names belong in the callers (verify_icons reads them).
            ok = mabr.ui.analysis.Style.setButtonIcon(btn,glyph,'left');
        end
    end

    methods (Access = private)
        function viewEventSafe(obj,name,e)
            if ~isvalid(obj), return; end
            try
                obj.onModelEvent(name,e);
            catch me
                mabr.log.vprintf(1,'%s view: %s handler failed: %s',obj.ViewName,name,me.message);
            end
        end

        function vwLayoutTick(obj)
            try
                if isvalid(obj) && obj.Built && obj.IsActive, obj.relayoutNow(); end
            catch
            end
        end

        function viewEndRender(obj)
            % (also after an error, and after the third nested pass: a render
            % still pending then is dropped rather than left to run inside
            % some later, unrelated render)
            if isvalid(obj)
                obj.Rendering = false;
                obj.RenderPending = false;
                obj.VwPendingRender = [];
            end
        end

        function viewEnsureEmpty(obj)
            if ~isempty(obj.VwEmptyPanel) && isvalid(obj.VwEmptyPanel), return; end
            p = uipanel(obj.Parent,'BorderType','none','Visible','off', ...
                'BackgroundColor',mabr.ui.analysis.Style.Panel, ...
                'Tag',char("Analysis" + obj.ViewName + "EmptyPanel"));
            p.Layout.Row = 1; p.Layout.Column = 1;
            g = uigridlayout(p,[4 4],'Padding',[20 20 20 20]);
            g.RowHeight   = {'1x','fit',30,'1x'};
            g.ColumnWidth = {'1x',220,220,'1x'};
            g.BackgroundColor = mabr.ui.analysis.Style.Panel;
            lab = uilabel(g,'Text','','HorizontalAlignment','center','WordWrap','on', ...
                'FontSize',14,'FontColor',mabr.ui.analysis.Style.Muted, ...
                'Tag',char("Analysis" + obj.ViewName + "Empty"));
            lab.Layout.Row = 2; lab.Layout.Column = [1 4];
            b = gobjects(1,2);
            for k = 1:2
                b(k) = uibutton(g,'Text','','Visible','off', ...
                    'Tag',char("Analysis" + obj.ViewName + "EmptyAction" + k));
                b(k).Layout.Row = 3; b(k).Layout.Column = k + 1;
            end
            obj.VwEmptyPanel   = p;
            obj.VwEmptyLabel   = lab;
            obj.VwEmptyButtons = b;
            obj.forgetWritten('vw_empty_');
        end

        function d = viewLoadLook(obj)
            % The subclass's loadDefaults() if it has one, else its factory
            % look, else nothing.
            d = struct();
            cls = class(obj);
            try
                d = feval([cls '.loadDefaults']);
                return
            catch
            end
            try
                d = feval([cls '.factoryDefaults']);
            catch
            end
        end

        function d = viewFactory(obj)
            d = struct();
            try
                d = feval([class(obj) '.factoryDefaults']);
            catch
                d = obj.ViewLook;
            end
            if ~isstruct(d), d = struct(); end
        end
    end
end
