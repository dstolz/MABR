classdef StartupDialog < handle
% mabr.ui.StartupDialog  What MABR is doing while its background workers start.
%
%   d = mabr.ui.StartupDialog(fig,steps,intro,statusFcn) lays a uiprogressdlg
%   over the uifigure fig: a title, the intro text, a checklist of steps (a
%   cellstr, each shown as not-started / in progress / done), and a detail
%   line carrying the latest milestone with the time elapsed. statusFcn
%   (optional) is handed every message too, so the owner's status line keeps
%   saying what it always said.
%
%       d.step(k)          % step k in progress, everything before it done
%       d.step(k,label)    % ...and relabel it (a plan that changed mid-way)
%       d.report(msg)      % detail line; pass @d.report as a progressFcn
%       d.close()          % take the dialog down -- an onCleanup in the
%                          % caller covers the error path
%
%   close() leaves the object alive as a pass-through to statusFcn. That is
%   deliberate: the engines keep the progressFcn they were built with for the
%   whole session (the compute watchdog reports a relaunch through it), so
%   what was the dialog's sink has to keep reaching the status line long
%   after the dialog itself is gone.
%
%   Bringing up the parallel pool and the worker handshakes blocks the
%   caller for anything up to a minute on a cold MATLAB, and a status line
%   ticking over at the bottom of the window is easy to read as a hang. The
%   bar is indeterminate on purpose: the one step that takes the time --
%   parpool -- is a single blocking call with nothing to report part way
%   through, and a determinate bar standing still for 40 s says "stuck" in
%   exactly the way this exists to avoid. The indeterminate animation runs in
%   the figure's own renderer, so it keeps moving while MATLAB is blocked.
%
%   It is an overlay on the owner's window rather than a window of its own,
%   so it has no position to remember and cannot be lost behind anything.
%   Every call is guarded: a startup must never fail because the dialog
%   describing it did.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Steps   cell   = {}     % checklist labels
        Current double = 0      % step in progress (0 = none yet)
        Detail  char   = ''     % latest milestone
    end

    properties (Access = private)
        Dlg                     % matlab.ui.dialog.ProgressDialog
        Intro   char   = ''
        StatusFcn               % function_handle, or []
        T0      uint64
    end

    properties (Constant, Access = private)
        MarkDone    = char(10003)   % check mark
        MarkCurrent = char(9656)    % small right-pointing triangle
        MarkPending = char(9675)    % white circle
    end

    methods
        function obj = StartupDialog(fig,steps,intro,statusFcn)
            if nargin < 2 || isempty(steps), steps = {}; end
            if nargin < 3 || isempty(intro), intro = ''; end
            if nargin >= 4, obj.StatusFcn = statusFcn; end
            obj.Steps = cellstr(steps);
            obj.Intro = char(intro);
            obj.T0    = tic;
            if isempty(fig) || ~isvalid(fig), return; end
            args = {'Title','Starting background workers', ...
                    'Message',obj.compose(),'Indeterminate','on', ...
                    'Cancelable','off'};
            try
                obj.Dlg = uiprogressdlg(fig,args{:},'Icon','info');
            catch
                try, obj.Dlg = uiprogressdlg(fig,args{:}); end %#ok<TRYNC>
            end
            drawnow
        end

        function delete(obj)
            obj.close();
        end

        function close(obj)
            if isempty(obj.Dlg), return; end
            try, close(obj.Dlg); end %#ok<TRYNC>
            obj.Dlg = [];
        end

        function step(obj,k,label)
            if nargin >= 3 && k >= 1 && k <= numel(obj.Steps)
                obj.Steps{k} = char(label);
            end
            obj.Current = k;
            obj.Detail  = '';
            obj.redraw();
        end

        function report(obj,msg)
            % The progressFcn every startup milestone is sent to.
            msg = char(msg);
            obj.Detail = msg;
            if ~isempty(obj.StatusFcn)
                try, obj.StatusFcn(msg); end %#ok<TRYNC>
            end
            obj.redraw();
        end

        function txt = compose(obj)
            % The dialog's whole message, as it would be shown now (public so
            % the layout can be read without a figure).
            lines = {};
            if ~isempty(obj.Intro), lines = [lines {obj.Intro ''}]; end
            for k = 1:numel(obj.Steps)
                if k < obj.Current
                    mark = obj.MarkDone;
                elseif k == obj.Current
                    mark = obj.MarkCurrent;
                else
                    mark = obj.MarkPending;
                end
                row = sprintf('   %s   %s',mark,obj.Steps{k});
                if k == obj.Current
                    % Elapsed since the dialog opened, on the step in
                    % progress. It moves only when a milestone arrives --
                    % parpool reports none while it blocks -- which is why
                    % the bar, not this, is what shows it is alive.
                    row = sprintf('%s   (%.0f s)',row,toc(obj.T0));
                end
                lines{end+1} = row; %#ok<AGROW>
            end
            if ~isempty(obj.Detail)
                lines = [lines {obj.Detail}];
            end
            txt = strjoin(lines,newline);
        end
    end

    methods (Access = private)
        function redraw(obj)
            if isempty(obj.Dlg), return; end
            try
                if ~isvalid(obj.Dlg), return; end
                obj.Dlg.Message = obj.compose();
                drawnow
            catch
            end
        end
    end
end
