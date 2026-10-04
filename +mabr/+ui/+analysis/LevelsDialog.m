classdef LevelsDialog < handle
% mabr.ui.analysis.LevelsDialog  Put the values of a label column in order (the timepoints, a group).
%
%   A text label column's values have an order -- Baseline before 2 weeks
%   before 8 weeks -- which decides the order of the study plots, the
%   timepoint_order column of the export, and which timepoint is the
%   reference of a threshold shift. The project guesses it from the visit
%   dates; this small window sets it: the values in a list, Up and Down to
%   move the selected one, OK to store the order (Model.setLevels, one
%   undoable step).
%
%       d = mabr.ui.analysis.LevelsDialog(model,"Timepoint");
%       d = mabr.ui.analysis.LevelsDialog(model,"Timepoint",Visible="off");   % a test
%       d.select("2 weeks"); d.moveUp(); d.read()     % the order shown
%       d.ok();                                       % store it and close
%       lv = mabr.ui.analysis.LevelsDialog.run(model,"Timepoint");   % wait (interactive)
%
%   A value in use but not listed keeps its place after the listed ones
%   (Project.setLevels), so no value is ever lost. A number column has no
%   order to set: the window says so and OK only closes. OK is disabled
%   while the Model is busy. The window writes no preference but its
%   position (mabr.ui.WindowPos, "OfflineAnalysisLevels"), remembered on
%   every way out.
%
%   Tags: AnalysisLevelsList, AnalysisLevelsUp, AnalysisLevelsDown,
%   AnalysisLevelsOK, AnalysisLevelsCancel.
%
%   See also mabr.analysis.Project, mabr.ui.analysis.Model
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPosition = [260 180 360 420]
    end

    properties (SetAccess = private)
        Figure = []
        Model = []
        Column (1,1) string = ""
        Original (1,:) string = strings(1,0)   % the order the window opened with
        Value (1,:) string = strings(1,0)      % the order last stored (apply/OK)
        Applied (1,1) logical = false
        Done (1,1) logical = false
        IsText (1,1) logical = true            % a text column (one with an order)
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners = event.listener.empty
    end

    methods
        function obj = LevelsDialog(model,columnName,opts)
            % LevelsDialog(model,columnName,Visible=)
            arguments
                model
                columnName (1,1) string = "Timepoint"
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
            end
            if ~isa(model,'mabr.ui.analysis.Model')
                error('mabr:ui:LevelsDialog:badModel','LevelsDialog needs a mabr.ui.analysis.Model.');
            end
            obj.Model = model;
            obj.Column = columnName;
            [lv,obj.IsText] = mabr.ui.analysis.LevelsDialog.levelsOf(model,columnName);
            obj.Original = lv;

            f = uifigure('Name',char("Order of " + columnName),'Tag','MABR_OFFLINE_LEVELS', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','off');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisLevels',obj.DefaultPosition);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;
            obj.build();
            obj.write(lv);
            obj.Listeners = event.listener(model,'BusyChanged',@(~,~) obj.syncEnable());
            obj.syncEnable();
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        % ---- the common dialog API ----------------------------------------
        function lv = read(obj)
            % The values in the order shown (string row).
            lv = obj.Original;
            if ~obj.isopen(), return; end
            lv = reshape(string(obj.Ctrl.List.Items),1,[]);
        end

        function write(obj,levels)
            % Show LEVELS in this order (the selection stays where it was).
            if ~obj.isopen(), return; end
            levels = reshape(string(levels),1,[]);
            h = obj.Ctrl.List;
            sel = string(h.Value);
            h.Items = cellstr(levels);
            if isempty(levels), return; end
            if ~isempty(sel) && any(levels == sel)
                h.Value = char(sel);
            else
                h.Value = char(levels(1));
            end
            obj.syncEnable();
        end

        function tf = apply(obj)
            % Store the order (Model.setLevels); the window stays open.
            % Refused (false) while the Model is busy (setLevels would throw).
            tf = false;
            if ~obj.isopen() || ~obj.IsText || obj.isBusy(), return; end
            lv = obj.read();
            if isempty(lv), return; end
            obj.Model.setLevels(obj.Column,lv);
            obj.Value = lv;
            obj.Applied = true;
            tf = true;
        end

        function tf = ok(obj)
            % Store the order (when it changed) and close.
            tf = false;
            if ~obj.isopen(), return; end
            if obj.IsText && ~isequal(obj.read(),obj.Original)
                if obj.isBusy(), return; end
                tf = obj.apply();
            end
            obj.Done = true;
            obj.closeFigure();
        end

        function cancel(obj)
            if obj.Done, return; end
            obj.Done = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        % ---- what the buttons do ------------------------------------------
        function select(obj,value)
            % Select one value of the list.
            if ~obj.isopen(), return; end
            if any(string(obj.Ctrl.List.Items) == string(value))
                obj.Ctrl.List.Value = char(string(value));
            end
            obj.syncEnable();
        end

        function moveUp(obj)
            obj.move(-1);
        end

        function moveDown(obj)
            obj.move(1);
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            f = obj.Figure;
            g = uigridlayout(f,[4 2]);
            g.RowHeight = {'fit','1x',22,30};
            g.ColumnWidth = {'1x',90};
            g.Padding = [12 12 12 10];
            g.RowSpacing = 6;
            if obj.IsText
                % "Order the timepoints (first at the top)": a one-word
                % column's values in the plural, a longer name as "the
                % values of ..."
                col = string(obj.Column);
                if ~contains(col," ") && ~endsWith(lower(col),"s")
                    what = "the " + lower(col) + "s";
                else
                    what = "the values of " + col;
                end
                txt = "Order " + what + " (first at the top). This order is used by the study " + ...
                    "plots and the export's " + lower(col) + "_order column.";
            else
                txt = obj.Column + " is a number column: its values are ordered by their value.";
            end
            lab = uilabel(g,'Text',char(txt),'WordWrap','on');
            lab.Layout.Row = 1; lab.Layout.Column = [1 2];
            lb = uilistbox(g,'Items',{},'Tag','AnalysisLevelsList', ...
                'Tooltip','Select a value, then move it with Up and Down (Alt+↑ / Alt+↓).', ...
                'ValueChangedFcn',@(~,~) obj.syncEnable());
            lb.Layout.Row = [2 3]; lb.Layout.Column = 1;
            obj.Ctrl.List = lb;
            bb = uigridlayout(g,[3 1],'Padding',[0 0 0 0],'RowSpacing',6);
            bb.Layout.Row = 2; bb.Layout.Column = 2;
            bb.RowHeight = {30,30,'1x'};
            obj.Ctrl.Up = uibutton(bb,'Text','Up','Tag','AnalysisLevelsUp', ...
                'Tooltip','Move the selected value one place up (Alt+↑).','ButtonPushedFcn',@(~,~) obj.moveUp());
            obj.Ctrl.Down = uibutton(bb,'Text','Down','Tag','AnalysisLevelsDown', ...
                'Tooltip','Move the selected value one place down (Alt+↓).','ButtonPushedFcn',@(~,~) obj.moveDown());

            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 4; r.Layout.Column = [1 2];
            r.ColumnWidth = {'1x',80,80};
            okb = uibutton(r,'Text','OK','Tag','AnalysisLevelsOK', ...
                'Tooltip','Store this order (undoable) and close.','ButtonPushedFcn',@(~,~) obj.ok());
            okb.Layout.Column = 2;
            obj.Ctrl.OK = okb;
            cb = uibutton(r,'Text','Cancel','Tag','AnalysisLevelsCancel', ...
                'Tooltip','Close without changing the order (Esc).','ButtonPushedFcn',@(~,~) obj.cancel());
            cb.Layout.Column = 3;
        end

        function move(obj,d)
            if ~obj.isopen() || ~obj.IsText, return; end
            h = obj.Ctrl.List;
            items = string(h.Items);
            k = find(items == string(h.Value),1);
            if isempty(k), return; end
            j = k + d;
            if j < 1 || j > numel(items), return; end
            items([k j]) = items([j k]);
            h.Items = cellstr(items);
            h.Value = char(items(j));
            obj.syncEnable();
        end

        function syncEnable(obj)
            if ~obj.isopen(), return; end
            h = obj.Ctrl.List;
            items = string(h.Items);
            k = [];
            if ~isempty(items), k = find(items == string(h.Value),1); end
            busy = obj.isBusy();
            obj.Ctrl.Up.Enable   = matlab.lang.OnOffSwitchState(obj.IsText && ~isempty(k) && k > 1);
            obj.Ctrl.Down.Enable = matlab.lang.OnOffSwitchState(obj.IsText && ~isempty(k) && k < numel(items));
            obj.Ctrl.OK.Enable   = matlab.lang.OnOffSwitchState(~busy);
            if busy
                obj.Ctrl.OK.Tooltip = 'Wait for the running job to finish.';
            else
                obj.Ctrl.OK.Tooltip = 'Store this order (undoable) and close.';
            end
        end

        function tf = isBusy(obj)
            tf = false;
            try
                tf = obj.Model.Busy;
            catch
            end
        end

        function onKey(obj,e)
            key = lower(string(e.Key));
            alt = any(strcmp(e.Modifier,'alt'));
            if key == "escape"
                obj.cancel();
            elseif key == "return"
                obj.ok();
            elseif alt && key == "uparrow"
                obj.moveUp();
            elseif alt && key == "downarrow"
                obj.moveDown();
            end
        end

        function closeFigure(obj)
            try
                delete(obj.Listeners);
            catch
            end
            obj.Listeners = event.listener.empty;
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisLevels');
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end

    methods (Static)
        function lv = run(model,columnName,varargin)
            % Show the dialog and wait (uiwait) until it closes: the order
            % OK stored, or [] when nothing was stored. Interactive use only.
            if nargin < 2, columnName = "Timepoint"; end
            d = mabr.ui.analysis.LevelsDialog(model,columnName,varargin{:});
            lv = [];
            if d.isopen()
                uiwait(d.Figure);
            end
            if d.Applied, lv = d.Value; end
            delete(d);
        end

        function [lv,isText] = levelsOf(model,name)
            % The values of label column NAME in their current order: its
            % stored Levels, then any value in use that they do not list.
            %   lv      (returned) string row
            %   isText  (returned) false for a number column
            lv = strings(1,0);
            isText = true;
            try
                P = model.Project;
                C = P.Columns;
                r = find(string(C.Name) == name,1);
                if isempty(r)
                    error('mabr:ui:LevelsDialog:unknownColumn','There is no label column "%s".',name);
                end
                isText = string(C.Type(r)) ~= "number";
                if ~isText, return; end
                s = C.Levels(r);
                if iscell(s), s = s{1}; end
                lv = reshape(string(s),1,[]);
                if string(C.Level(r)) == "subject"
                    used = P.Subjects.(char(name));
                else
                    used = P.Sessions.(char(name));
                end
                used = reshape(string(used),1,[]);
                used = unique(used(~ismissing(used) & used ~= ""),'stable');
                lv = [lv used(~ismember(lower(used),lower(lv)))];
                lv = lv(~ismissing(lv) & lv ~= "");
            catch me
                if strcmp(me.identifier,'mabr:ui:LevelsDialog:unknownColumn'), rethrow(me); end
                mabr.log.vprintf(2,'LevelsDialog: levels of %s not read (%s).',name,me.message);
            end
        end
    end
end
