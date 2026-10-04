classdef NoteEditor < handle
% mabr.ui.analysis.NoteEditor  The note box that floats over the analysis workspace.
%
%   A note on a threshold ("electrode loose at 30 dB") or a comment on a
%   session is written here and nowhere else -- never into a table cell,
%   where a stray keystroke edits data. It is a panel inside the main window,
%   not a window of its own, so it cannot end up behind it:
%
%       ed.open(struct('Kind',"series",'Key',k),"old text")   % shows it
%       ed.commit()      % Model.setNote(target,text); hides it
%       ed.cancel()      % hides it, writes nothing
%
%   While it is open Model.KeysSuspended is true, so the app's key
%   dispatcher ignores every key but Escape (cancel) and Ctrl+Enter (save):
%   typing "tinnitus" into the note must not accept a threshold (a), mark a
%   level (t), declare no response (i) and normalise the traces (n) on the
%   way. Pressing x (exclude) opens it right after the exclusion, because an
%   exclusion without a reason is the one a reviewer cannot judge later.
%
%   Tags: AnalysisNoteEditor (the panel), AnalysisNoteEditorTitle,
%   AnalysisNoteEditorText, AnalysisNoteEditorSave, AnalysisNoteEditorCancel.
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.Model.setNote
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Model                     % mabr.ui.analysis.Model
        Host                      % mabr.ui.AnalysisApp (or [])
        Panel = []
        Target = []               % struct Kind ("series"|"session"), Key
        IsOpen (1,1) logical = false
    end

    properties (Access = private)
        Title = []
        Text  = []
        Typed = ""                % what the text area holds, as typed
    end

    methods
        function obj = NoteEditor(parent,model,host,opts)
            % NoteEditor(parent,model,host,Row=..,Column=..)
            %   parent  the grid the panel floats in (it shares a cell with
            %           whatever it covers, and is created after it, so it
            %           draws on top)
            arguments
                parent
                model
                host = []
                opts.Row = 1
                opts.Column = 1
            end
            obj.Model = model;
            obj.Host  = host;
            p = uipanel(parent,'Title','','Visible','off','Tag','AnalysisNoteEditor', ...
                'BackgroundColor',[1 1 1],'BorderType','line','FontWeight','bold');
            try
                p.Layout.Row = opts.Row;
                p.Layout.Column = opts.Column;
            catch
            end
            g = uigridlayout(p,[3 3]);
            g.RowHeight   = {22,'1x',30};
            g.ColumnWidth = {'1x',150,110};
            g.Padding     = [10 8 10 8];
            g.RowSpacing  = 6;
            g.BackgroundColor = [1 1 1];

            t = uilabel(g,'Text','Note','FontWeight','bold','Tag','AnalysisNoteEditorTitle', ...
                'FontColor',mabr.ui.analysis.Style.Ink);
            t.Layout.Row = 1; t.Layout.Column = [1 3];

            ta = uitextarea(g,'Value',{''},'Tag','AnalysisNoteEditorText', ...
                'Tooltip','Write the note. Ctrl+Enter saves it, Esc closes without saving.');
            ta.Layout.Row = 2; ta.Layout.Column = [1 3];
            try
                if isprop(ta,'ValueChangingFcn')
                    ta.ValueChangingFcn = @(~,e) obj.onTyping(e);
                end
            catch
            end
            ta.ValueChangedFcn = @(src,~) obj.onTyping(struct('Value',{src.Value}));

            sv = uibutton(g,'Text','Save (Ctrl+Enter)','Tag','AnalysisNoteEditorSave', ...
                'Tooltip','Save the note with the results (Ctrl+Enter).', ...
                'ButtonPushedFcn',@(~,~) obj.commit());
            sv.Layout.Row = 3; sv.Layout.Column = 2;
            cn = uibutton(g,'Text','Cancel (Esc)','Tag','AnalysisNoteEditorCancel', ...
                'Tooltip','Close without saving (Esc).','ButtonPushedFcn',@(~,~) obj.cancel());
            cn.Layout.Row = 3; cn.Layout.Column = 3;

            obj.Panel = p;
            obj.Title = t;
            obj.Text  = ta;
        end

        function delete(obj)
            try
                if ~isempty(obj.Panel) && isvalid(obj.Panel), delete(obj.Panel); end
            catch
            end
        end

        function open(obj,target,text)
            % Show the editor for TARGET (struct Kind "series"|"session",
            % Key), holding TEXT (the note so far).
            if nargin < 3 || isempty(text), text = ""; end
            text = string(text);
            if ismissing(text), text = ""; end
            obj.Target = target;
            obj.Title.Text = char(obj.titleFor(target));
            obj.write(text);
            obj.IsOpen = true;
            obj.Model.KeysSuspended = true;
            obj.Panel.Visible = 'on';
            mabr.ui.analysis.Compat.tryFocus(obj.Text);
        end

        function commit(obj)
            % Save the text as the target's note and close.
            if ~obj.IsOpen, return; end
            txt = obj.read();
            target = obj.Target;
            obj.close();
            try
                obj.Model.setNote(target,txt);
            catch me
                obj.report(me);
            end
        end

        function cancel(obj)
            % Close without saving.
            obj.close();
        end

        function v = read(obj)
            % The text as typed (lines joined by newline).
            v = obj.Typed;
        end

        function write(obj,v)
            % Replace the text (as if typed).
            v = string(v);
            if isempty(v) || ismissing(v), v = ""; end
            lines = splitlines(v);
            obj.Text.Value = cellstr(lines);
            obj.Typed = strjoin(lines,newline);
        end
    end

    methods (Access = private)
        function close(obj)
            obj.IsOpen = false;
            try
                obj.Model.KeysSuspended = false;
            catch
            end
            try
                obj.Panel.Visible = 'off';
            catch
            end
            if ~isempty(obj.Host) && isvalid(obj.Host)
                try
                    mabr.ui.analysis.Compat.tryFocus(obj.Host.Figure);
                catch
                end
            end
        end

        function onTyping(obj,e)
            try
                v = e.Value;
                if iscell(v), v = strjoin(string(v),newline); end
                obj.Typed = string(v);
            catch
            end
        end

        function s = titleFor(obj,target)
            s = "Note";
            try
                if string(target.Kind) == "session"
                    s = "Comment — session";
                else
                    s = "Note — " + obj.Model.seriesLabel(string(target.Key)) + " threshold";
                end
            catch
            end
        end

        function report(obj,me)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                if strcmp(me.identifier,'mabr:ui:analysis:busy')
                    obj.Host.setStatus("Busy — try again when the current step ends",1);
                else
                    obj.Host.setStatus("The note was not saved: " + string(me.message),2);
                end
            end
            mabr.log.vprintf(2,'NoteEditor: %s',me.message);
        end
    end
end
