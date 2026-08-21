classdef Notes < handle
% mabr.ui.Notes  The rig notebook, as a reusable GUI component.
%
%   A view over a mabr.data.SessionNotes store: a log of timestamped notes, an
%   entry field, and a commit button. It exists so an operator can write down
%   what happened WHILE it is happening -- "ear plug slipped", "impedance
%   3.2k", "animal woke up" -- instead of reconstructing it afterwards from
%   file timestamps. Everything committed is saved with the data (see
%   mabr.data.SessionNotes).
%
%   Three forms, all over the same store:
%
%       n = mabr.ui.Notes(store);                  % its own window
%       n = mabr.ui.Notes(store,container);        % embedded panel
%       n = mabr.ui.Notes(store,[],'ButtonOnly',true);   % nothing until popOut
%
%   ...and one line for a host that already has a toolbar, which is how both
%   mabr.ui.App and mabr.ui.TraceOrganizer use it:
%
%       n = mabr.ui.Notes.toolbarButton(obj.Toolbar,store);
%
%   The embedded form fills whatever row the host's layout gives it: a '1x'
%   row gets a full-height log, a fixed 90 px row a three-line one. There is
%   no size to set.
%
%   ANY NUMBER OF VIEWS may be open on one store at once -- the App's notes
%   window, the trace organizer's -- and they stay in step because each one
%   listens to the store's NotesChanged event and redraws from the store. A
%   note typed in one appears in the others as it is committed. That is also
%   why the store, not the view, is the thing a host owns and hands around.
%
%   The log is READ-ONLY until the right-click "Editable" is ticked, which is
%   remembered per host. Locked is the right default: the log is a record, and
%   the common accident is typing into it instead of into the entry field.
%   Unlocking it is still worth having, because the other common accident is a
%   typo in a note taken one-handed at the bench, and the only place to fix
%   one is the log the operator can see (mabr.data.SessionNotes.setFromLog
%   keeps each edited line's original stamp and record).
%
%   Right-click menu: Editable · Copy All · Clear Notes… · Open in Separate
%   Window (embedded form only).
%
%   See also mabr.data.SessionNotes, mabr.ui.App, mabr.ui.TraceOrganizer.
%
% Daniel Stolzberg (c) 2026

    properties
        % How a note committed from THIS view is stamped: 'auto' (run and
        % sweep count while acquiring, wall clock otherwise), 'clock',
        % 'elapsed', or 'none'. Per view rather than per store, because a note
        % window and an offline trace organizer are asking different questions
        % about "when".
        TimeStamp (1,:) char {mustBeMember(TimeStamp, ...
            {'auto','clock','elapsed','none'})} = 'auto';
        FontSize (1,1) double {mustBePositive,mustBeFinite} = 12;
    end

    properties (SetAccess = private)
        Store        % mabr.data.SessionNotes
        Editable     (1,1) logical = false;
        IsButtonOnly (1,1) logical = false;
        % Names this view in the prefs (its window position and its Editable
        % state) and in each note's Source field, so a log can say which window
        % a note was typed into.
        Name   (1,:) char = 'Notes';
    end

    properties (SetAccess = private, Transient)
        Figure      % the popped-out window, when there is one
    end

    properties (Access = private, Transient)
        Grid
        LogArea
        EntryField
        CommitButton
        Button          % the ButtonOnly form's button, when embedded
        Tool            % a host's toolbar button, when one was handed over
        ContextMenu
        EditItem
        StoreListener
        Placeholder (1,:) char = 'Type a note and press Enter…';
        HostFigure      % figure the embedded form lives in
    end

    properties (Constant, Access = private)
        DefaultPos = [200 200 420 380];
        Ink        = [0.16 0.26 0.42];
    end

    methods
        function obj = Notes(store,container,varargin)
            if nargin < 1 || isempty(store), store = mabr.data.SessionNotes(); end
            if nargin < 2, container = []; end

            p = struct('ButtonOnly',false,'TimeStamp','auto','Editable',[], ...
                       'FontSize',12,'Placeholder',obj.Placeholder,'Name','Notes');
            for i = 1:2:numel(varargin)
                p.(varargin{i}) = varargin{i+1};
            end

            obj.Store        = store;
            obj.IsButtonOnly = logical(p.ButtonOnly);
            obj.TimeStamp    = p.TimeStamp;
            obj.FontSize     = p.FontSize;
            obj.Placeholder  = p.Placeholder;
            obj.Name         = p.Name;
            if isempty(p.Editable)
                obj.Editable = getpref('MABR',['NotesEditable_' obj.Name],false);
            else
                obj.Editable = logical(p.Editable);
            end

            % Every view redraws from the store rather than from its own copy,
            % so two windows open on one session cannot disagree about the log.
            obj.StoreListener = addlistener(store,'NotesChanged', ...
                @(~,~) obj.refresh());

            if obj.IsButtonOnly
                % With no container there is nothing to build yet: the host
                % (a toolbar button, a menu item) opens the window itself.
                if ~isempty(container) && isgraphics(container)
                    obj.buildButton(container);
                end
            elseif isempty(container)
                obj.popOut();
            else
                obj.buildPanel(container);
            end
        end

        function delete(obj)
            try, delete(obj.StoreListener); end %#ok<TRYNC>
            obj.close();
        end

        % --- Notes ------------------------------------------------------------
        function commit(obj)
            % Commit whatever is in the entry field. A blank entry is a stray
            % Enter, so it commits nothing rather than an empty note.
            if isempty(obj.EntryField) || ~isgraphics(obj.EntryField), return; end
            txt = obj.EntryField.Value;
            obj.EntryField.Value = '';
            obj.addNote(txt);
            obj.focusEntry();
        end

        function addNote(obj,text)
            % Add a note programmatically, stamped as this view stamps.
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end
            obj.Store.add(text,'Source',obj.Name,'TimeStamp',obj.TimeStamp);
        end

        function clearNotes(obj)
            % Discard the whole log. Unconfirmed -- the right-click item
            % confirms before calling this; a programmatic caller has already
            % decided.
            if ~isempty(obj.Store) && isvalid(obj.Store), obj.Store.clear(); end
        end

        function setTool(obj,h)
            % Adopt a toolbar button the host built, so the count can reach it.
            % A uipushtool has no label to carry one, but it has a tooltip, and
            % a notebook with something in it should not look identical to an
            % empty one -- otherwise the only way to find out whether anything
            % was written is to open the window.
            obj.Tool = h;
            obj.syncButtonLabel();
        end

        function setStore(obj,store)
            % Point this view at a different notebook -- what a host calls when
            % it adopts the running session's store in place of its own (see
            % mabr.ui.TraceOrganizer.useNotes). Re-pointing rather than
            % rebuilding the view keeps whatever handle the host's button or
            % menu item already holds valid.
            if isempty(store) || ~isa(store,'mabr.data.SessionNotes') || ~isvalid(store)
                return
            end
            % '==' rather than isequal: the question is whether it is the SAME
            % store, not one that happens to hold the same notes.
            if ~isempty(obj.Store) && isvalid(obj.Store) && obj.Store == store
                return
            end
            try, delete(obj.StoreListener); end %#ok<TRYNC>
            obj.Store = store;
            obj.StoreListener = addlistener(store,'NotesChanged', ...
                @(~,~) obj.refresh());
            obj.refresh();
        end

        function setEditable(obj,tf)
            obj.Editable = logical(tf);
            setpref('MABR',['NotesEditable_' obj.Name],obj.Editable);
            obj.syncEditable();
        end

        function copyAll(obj)
            % The whole log to the clipboard, for pasting into a lab notebook.
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end
            clipboard('copy',obj.Store.text());
        end

        % --- Window -----------------------------------------------------------
        function popOut(obj)
            % Open (or raise) the notes in their own window. This is the whole
            % UI of the ButtonOnly form and an overflow for the embedded one.
            if obj.isopen()
                figure(obj.Figure);
                obj.focusEntry();
                return
            end
            obj.Figure = uifigure('Name',['MABR Notes — ' obj.Name], ...
                'Position',obj.DefaultPos, ...
                'CloseRequestFcn',@(~,~) obj.close());
            mabr.ui.WindowPos.restore(obj.Figure,['Notes_' obj.Name], ...
                obj.DefaultPos,[300 200]);
            obj.buildPanel(obj.Figure);
            obj.focusEntry();
        end

        function show(obj)
            obj.popOut();
        end

        function tf = isopen(obj)
            tf = ~isempty(obj.Figure) && isgraphics(obj.Figure);
        end

        function close(obj)
            if obj.isopen()
                mabr.ui.WindowPos.remember(obj.Figure,['Notes_' obj.Name]);
                delete(obj.Figure);
            end
            obj.Figure = [];
        end

        function lines = displayedLog(obj)
            % What this view's log box is actually showing, as a cellstr --
            % which is not the same question as what the store holds, and is
            % the one worth asking of a view (tests/verify_notes.m asks it of
            % two views on one store).
            lines = {};
            if ~isempty(obj.LogArea) && isgraphics(obj.LogArea)
                lines = cellstr(obj.LogArea.Value);
            end
        end

        function refresh(obj)
            % Redraw the log from the store. Called on every NotesChanged, so
            % it must survive being fired at a view whose window has since been
            % closed -- which is exactly what happens when one of two open
            % views is shut while the other is still committing.
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end
            % The button first: a ButtonOnly view has no log to redraw, and its
            % count is the only thing it can show.
            obj.syncButtonLabel();
            if isempty(obj.LogArea) || ~isgraphics(obj.LogArea), return; end
            lines = obj.Store.log();
            if isempty(lines), lines = {''}; end
            obj.LogArea.Value = lines;
            try, scroll(obj.LogArea,'bottom'); end %#ok<TRYNC>
        end
    end

    methods (Access = private)
        % --- Building ---------------------------------------------------------
        function buildPanel(obj,container)
            % Log on top, entry beneath. The log takes a '1x' row, so the whole
            % component fills whatever height the host gives it and there is no
            % size for a host to get wrong.
            obj.HostFigure = ancestor(container,'figure');
            obj.Grid = uigridlayout(container,[2 2]);
            obj.Grid.RowHeight     = {'1x',26};
            obj.Grid.ColumnWidth   = {'1x','fit'};
            obj.Grid.Padding       = [6 6 6 6];
            obj.Grid.RowSpacing    = 5;
            obj.Grid.ColumnSpacing = 5;

            obj.LogArea = uitextarea(obj.Grid,'Editable','off', ...
                'FontSize',obj.FontSize,'FontName','Consolas', ...
                'Tooltip',['Every note is stamped with the run and sweep it was ' ...
                           'taken at, and saved with the data.'], ...
                'ValueChangedFcn',@(src,~) obj.onLogEdited(src));
            obj.LogArea.Layout.Row = 1; obj.LogArea.Layout.Column = [1 2];

            obj.EntryField = uieditfield(obj.Grid,'text', ...
                'FontSize',obj.FontSize, ...
                'ValueChangedFcn',@(~,~) obj.commit());
            obj.EntryField.Layout.Row = 2; obj.EntryField.Layout.Column = 1;
            obj.setPlaceholder(obj.EntryField,obj.Placeholder);

            obj.CommitButton = uibutton(obj.Grid,'Text','Add', ...
                'Tooltip','Commit this note (Enter)', ...
                'ButtonPushedFcn',@(~,~) obj.commit());
            obj.CommitButton.Layout.Row = 2; obj.CommitButton.Layout.Column = 2;

            obj.buildContextMenu();
            obj.syncEditable();
            obj.refresh();
        end

        function buildButton(obj,container)
            % The ButtonOnly form: one button that opens the window. For a host
            % whose layout has no room for a log but every reason to offer one.
            obj.HostFigure = ancestor(container,'figure');
            obj.Button = uibutton(container,'Text','Notes…', ...
                'Tooltip','Compose notes for this session (saved with the data)', ...
                'ButtonPushedFcn',@(~,~) obj.popOut());
            obj.syncButtonLabel();
        end

        function buildContextMenu(obj)
            if isempty(obj.HostFigure) || ~isgraphics(obj.HostFigure), return; end
            obj.ContextMenu = uicontextmenu(obj.HostFigure);
            obj.EditItem = uimenu(obj.ContextMenu,'Text','Editable', ...
                'Checked',matlab.lang.OnOffSwitchState(obj.Editable), ...
                'MenuSelectedFcn',@(~,~) obj.setEditable(~obj.Editable));
            uimenu(obj.ContextMenu,'Text','Copy All','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.copyAll());
            uimenu(obj.ContextMenu,'Text','Clear Notes…', ...
                'MenuSelectedFcn',@(~,~) obj.onClearNotes());
            if ~obj.isopen()
                % Only worth offering where the log is embedded in someone
                % else's window -- it IS the separate window otherwise.
                uimenu(obj.ContextMenu,'Text','Open in Separate Window', ...
                    'Separator','on','MenuSelectedFcn',@(~,~) obj.popOut());
            end
            try
                obj.LogArea.ContextMenu = obj.ContextMenu;
            catch
                % Older releases: a text area may not accept one. The menu bar
                % / toolbar routes still work, so this is not worth failing on.
            end
        end

        % --- Callbacks ---------------------------------------------------------
        function onLogEdited(obj,src)
            % Only reachable with Editable ticked (the area is read-only
            % otherwise). Write the edited text back through the store so every
            % other open view -- and the journal -- follows.
            if ~obj.Editable, return; end
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end
            obj.Store.setFromLog(src.Value);
            obj.refresh();      % re-render, so a mangled line comes back tidy
        end

        function onClearNotes(obj)
            n = 0;
            if ~isempty(obj.Store) && isvalid(obj.Store), n = obj.Store.NumNotes; end
            if n == 0, return; end
            fig = obj.Figure;
            if isempty(fig) || ~isgraphics(fig), fig = obj.HostFigure; end
            msg = sprintf(['Discard all %d note(s)?\n\nNotes already written into a ' ...
                           'saved file are not affected.'],n);
            if ~isempty(fig) && isgraphics(fig)
                sel = uiconfirm(fig,msg,'Clear Notes', ...
                    'Options',{'Clear','Cancel'},'DefaultOption',2, ...
                    'CancelOption',2,'Icon','warning');
                if ~strcmp(sel,'Clear'), return; end
            end
            obj.clearNotes();
        end

        % --- Sync --------------------------------------------------------------
        function syncEditable(obj)
            if ~isempty(obj.LogArea) && isgraphics(obj.LogArea)
                obj.LogArea.Editable = matlab.lang.OnOffSwitchState(obj.Editable);
            end
            if ~isempty(obj.EditItem) && isgraphics(obj.EditItem)
                obj.EditItem.Checked = matlab.lang.OnOffSwitchState(obj.Editable);
            end
        end

        function syncButtonLabel(obj)
            % The button carries the count, so a host with no room for a log
            % still shows that there ARE notes -- an empty-looking button next
            % to a full notebook is the one thing this form could get wrong.
            n = 0;
            if ~isempty(obj.Store) && isvalid(obj.Store), n = obj.Store.NumNotes; end
            if ~isempty(obj.Button) && isgraphics(obj.Button)
                if n > 0
                    obj.Button.Text = sprintf('Notes (%d)…',n);
                else
                    obj.Button.Text = 'Notes…';
                end
            end
            % A toolbar button has no room for a label, so the count goes in
            % the tooltip -- the only thing a uipushtool can say.
            if ~isempty(obj.Tool) && isgraphics(obj.Tool)
                if n > 0
                    obj.Tool.Tooltip = sprintf( ...
                        'Session notes — %d so far (saved with the data)',n);
                else
                    obj.Tool.Tooltip = 'Session notes (saved with the data)';
                end
            end
        end

        function focusEntry(obj)
            if isempty(obj.EntryField) || ~isgraphics(obj.EntryField), return; end
            try, focus(obj.EntryField); end %#ok<TRYNC>   % R2022a+
        end

        function setPlaceholder(~,h,txt)
            % Placeholder text landed on uieditfield in R2023a; MABR still
            % supports R2021b, where the same hint has to be a tooltip.
            if isempty(txt), return; end
            if isprop(h,'Placeholder')
                h.Placeholder = txt;
            else
                h.Tooltip = txt;
            end
        end
    end

    methods (Static)
        function [obj,tool] = toolbarButton(toolbar,store,varargin)
            % Put a notes button on an existing toolbar and return the view it
            % opens. One line for any host with a uitoolbar -- classic figure
            % or uifigure, since uipushtool works on both:
            %
            %   obj.NotesView = mabr.ui.Notes.toolbarButton(obj.Toolbar,store);
            %
            % Options are mabr.ui.Notes' own, plus 'Color' and 'Separator' for
            % the button itself.
            rgb = mabr.ui.Notes.Ink;
            sep = false;
            keep = true(1,numel(varargin));
            for i = 1:2:numel(varargin)
                switch lower(varargin{i})
                    case 'color',     rgb = varargin{i+1}; keep(i:i+1) = false;
                    case 'separator', sep = varargin{i+1}; keep(i:i+1) = false;
                end
            end
            opts = varargin(keep);

            obj = mabr.ui.Notes(store,[],'ButtonOnly',true,opts{:});
            sepStr = 'off'; if sep, sepStr = 'on'; end
            tool = uipushtool(toolbar,'Separator',sepStr, ...
                'CData',mabr.ui.Icon.fromArt(mabr.ui.Notes.glyph(),rgb), ...
                'ClickedCallback',@(~,~) obj.popOut());
            obj.setTool(tool);      % also writes the tooltip
        end

        function rows = glyph()
            % A ruled notepad with a spiral binding: 16x16 art for a toolbar
            % button. See mabr.ui.Icon.
            rows = {'................'
                    '...X..X..X..X...'
                    '..XXXXXXXXXXXX..'
                    '..X..........X..'
                    '..X.XXXXXXXX.X..'
                    '..X..........X..'
                    '..X.XXXXXXXX.X..'
                    '..X..........X..'
                    '..X.XXXXXXXX.X..'
                    '..X..........X..'
                    '..X.XXXX.....X..'
                    '..X..........X..'
                    '..XXXXXXXXXXXX..'
                    '................'
                    '................'
                    '................'};
        end
    end
end
