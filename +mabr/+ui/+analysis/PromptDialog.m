classdef PromptDialog < handle
% mabr.ui.analysis.PromptDialog  A one-line question with OK and Cancel, as a uifigure.
%
%   The analysis app asks for a name (a pool, an analyst, a free column) in a
%   small window of its own rather than through inputdlg, which is a classic
%   modal figure: it would sit behind the uifigure on some desktops, and it
%   cannot be driven by a test. This one can -- it is an ordinary handle
%   object whose answer is read back with read() and settled with ok() or
%   cancel() -- and the blocking form a menu callback wants is one static
%   call:
%
%       v = mabr.ui.analysis.PromptDialog.run("Pool name","Name of the pool:","Pool 1");
%       % v: the text (string), or [] when cancelled
%
%       d = mabr.ui.analysis.PromptDialog("Pool name","Name:","Pool 1",Visible="off");
%       d.write("Day 3"); d.ok(); d.Value      % a test, no waiting
%
%   opts.Visible  "on" | "off" (tests)
%   opts.Numeric  a numeric field: read() returns a double (default false)
%
%   Tags: AnalysisPromptText (the field), AnalysisPromptOK, AnalysisPromptCancel.
%   Enter is OK and Escape is Cancel. The window's position is remembered
%   (mabr.ui.WindowPos, "OfflineAnalysisPrompt") on every way out.
%
%   run() waits (uiwait), so it is for interactive use only -- the app's
%   default PromptFcn; tests inject their own PromptFcn and never call it.
%
%   See also mabr.ui.AnalysisApp, mabr.ui.WindowPos
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Figure = []
        Value = []                    % the answer after ok(); [] after cancel()
        Done  (1,1) logical = false   % ok() or cancel() has happened
        Numeric (1,1) logical = false
    end

    properties (Access = private)
        Field = []
        Typed = []                    % what is in the field, as typed
    end

    properties (Constant)
        DefaultPosition = [300 300 420 160]
    end

    methods
        function obj = PromptDialog(title,prompt,default,opts)
            % PromptDialog(title,prompt,default,Visible=..,Numeric=..)
            arguments
                title (1,1) string = "MABR"
                prompt (1,1) string = ""
                default = ""
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
                opts.Numeric (1,1) logical = false
            end
            obj.Numeric = opts.Numeric;
            f = uifigure('Name',char(title),'Tag','MABR_OFFLINE_PROMPT', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','off', ...
                'WindowStyle','normal');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisPrompt',obj.DefaultPosition);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;

            g = uigridlayout(f,[3 3]);
            g.RowHeight   = {'fit',26,30};
            g.ColumnWidth = {'1x',90,90};
            g.Padding     = [12 12 12 10];
            g.RowSpacing  = 8;

            lab = uilabel(g,'Text',char(prompt),'WordWrap','on');
            lab.Layout.Row = 1; lab.Layout.Column = [1 3];

            if obj.Numeric
                v = double(default);
                if isempty(v) || ~isscalar(v), v = 0; end
                fld = uieditfield(g,'numeric','Value',v,'Tag','AnalysisPromptText', ...
                    'Tooltip','Type a number, then press Enter or OK.');
            else
                v = string(default);
                if isempty(v) || ismissing(v), v = ""; end
                fld = uieditfield(g,'text','Value',char(v),'Tag','AnalysisPromptText', ...
                    'Tooltip','Type the answer, then press Enter or OK.');
                fld.ValueChangingFcn = @(~,e) obj.onTyping(e);
            end
            fld.Layout.Row = 2; fld.Layout.Column = [1 3];
            obj.Field = fld;
            obj.Typed = fld.Value;

            okb = uibutton(g,'Text','OK','Tag','AnalysisPromptOK', ...
                'Tooltip','Use this answer (Enter).','ButtonPushedFcn',@(~,~) obj.ok());
            okb.Layout.Row = 3; okb.Layout.Column = 2;
            cb = uibutton(g,'Text','Cancel','Tag','AnalysisPromptCancel', ...
                'Tooltip','Close without an answer (Esc).','ButtonPushedFcn',@(~,~) obj.cancel());
            cb.Layout.Row = 3; cb.Layout.Column = 3;

            f.Visible = char(opts.Visible);
            if opts.Visible == "on"
                mabr.ui.analysis.Compat.tryFocus(fld);
            end
        end

        function delete(obj)
            obj.closeFigure();
        end

        function v = read(obj)
            % What the field holds now: a string, or a double when Numeric.
            if isempty(obj.Field) || ~isvalid(obj.Field)
                v = obj.Value;
                return
            end
            if obj.Numeric
                v = double(obj.Field.Value);
            else
                v = string(obj.Typed);
                if ismissing(v), v = ""; end
            end
        end

        function write(obj,v)
            % Put V in the field, as if typed.
            if isempty(obj.Field) || ~isvalid(obj.Field), return; end
            if obj.Numeric
                obj.Field.Value = double(v);
                obj.Typed = obj.Field.Value;
            else
                obj.Field.Value = char(string(v));
                obj.Typed = obj.Field.Value;
            end
        end

        function ok(obj)
            % Settle with the field's value and close.
            if obj.Done, return; end
            obj.Value = obj.read();
            obj.Done  = true;
            obj.closeFigure();
        end

        function cancel(obj)
            % Settle with no answer ([]) and close.
            if obj.Done, return; end
            obj.Value = [];
            obj.Done  = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            % True until ok() or cancel().
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end
    end

    methods (Static)
        function v = run(title,prompt,default,opts)
            % Ask and wait: the text typed (string, or double when Numeric),
            % or [] when cancelled. Interactive use only (uiwait).
            arguments
                title (1,1) string = "MABR"
                prompt (1,1) string = ""
                default = ""
                opts.Numeric (1,1) logical = false
            end
            d = mabr.ui.analysis.PromptDialog(title,prompt,default,Numeric=opts.Numeric);
            if d.isopen()
                uiwait(d.Figure);
            end
            v = d.Value;
            delete(d);
        end
    end

    methods (Access = private)
        function onTyping(obj,e)
            try
                obj.Typed = e.Value;
            catch
            end
        end

        function onKey(obj,e)
            switch lower(string(e.Key))
                case "return"
                    % Typed follows every keystroke (ValueChangingFcn), so it
                    % already holds what the field shows even before the
                    % field commits its Value.
                    obj.ok();
                case "escape"
                    obj.cancel();
            end
        end

        function closeFigure(obj)
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisPrompt');
            % uiwait in run() returns when the figure goes away.
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end
end
