classdef ReviewDialog < handle
% mabr.ui.analysis.ReviewDialog  Start a review queue: which sessions, in what order, blind or not.
%
%   The analysis app's Review Queue… window. A review queue walks the
%   series of several sessions one session after the other
%   (Model.startReviewQueue; Session ▸ Next Session moves on) -- the
%   sessions of the browser's selection, of the study, or every analysed
%   one; only those with series still to review, or all of them; in the
%   browser's order or a seeded random one (so one reviewer's order can be
%   given to another); and, for blind review, with subject, folder, date,
%   timepoint and group hidden everywhere until the queue ends.
%
%       d = mabr.ui.analysis.ReviewDialog(model,selectedKeys);
%       d = mabr.ui.analysis.ReviewDialog(model,keys,Visible="off");   % a test
%       v = d.read();     % Scope, Keys, UnreviewedOnly, Order, Seed, Blind
%       d.ok();           % start the queue and close
%       tf = mabr.ui.analysis.ReviewDialog.run(model,keys);   % wait (interactive)
%
%   Start is disabled while the Model is busy or when the scope holds no
%   analysed session; the line above the buttons says how many sessions the
%   queue will hold. The window writes no preference but its position
%   (mabr.ui.WindowPos, "OfflineAnalysisReview"), remembered on every way
%   out.
%
%   Tags: AnalysisReviewScope, AnalysisReviewUnreviewed, AnalysisReviewOrder,
%   AnalysisReviewSeed, AnalysisReviewBlind, AnalysisReviewCount,
%   AnalysisReviewStart, AnalysisReviewCancel.
%
%   See also mabr.ui.analysis.Model, mabr.ui.AnalysisApp
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPosition = [240 160 480 340]
        Scopes = ["selected","instudy","analysed"]
    end

    properties (SetAccess = private)
        Figure = []
        Model = []
        Keys (:,1) string = strings(0,1)   % the browser's selection
        Started (1,1) logical = false      % a queue was started from here
        Done (1,1) logical = false
    end

    properties (Access = private)
        Ctrl = struct()
        Listeners = event.listener.empty
        Written = struct()
        WhyNot (1,1) string = ""
    end

    methods
        function obj = ReviewDialog(model,keys,opts)
            % ReviewDialog(model,keys,Visible=)
            arguments
                model
                keys string = strings(0,1)
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
            end
            if ~isa(model,'mabr.ui.analysis.Model')
                error('mabr:ui:ReviewDialog:badModel','ReviewDialog needs a mabr.ui.analysis.Model.');
            end
            obj.Model = model;
            obj.Keys = reshape(keys,[],1);

            f = uifigure('Name','Review queue','Tag','MABR_OFFLINE_REVIEW', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','off');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisReview',obj.DefaultPosition);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn   = @(~,~) obj.cancel();
            f.WindowKeyPressFcn = @(~,e) obj.onKey(e);
            obj.Figure = f;
            obj.build();
            if numel(obj.Keys) < 2
                obj.Ctrl.Scope.Value = 'instudy';
            end
            obj.recompute();
            obj.Listeners = event.listener(model,'BusyChanged',@(~,~) obj.syncEnable());
            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        % ---- the common dialog API ----------------------------------------
        function v = read(obj)
            % Scope, Keys (the analysed sessions of the scope), UnreviewedOnly,
            % Order ("browser" | "random"), Seed, Blind.
            v = struct('Scope',"instudy",'Keys',strings(0,1),'UnreviewedOnly',true, ...
                'Order',"browser",'Seed',12,'Blind',false);
            if ~obj.isopen(), return; end
            c = obj.Ctrl;
            v.Scope = string(c.Scope.Value);
            v.Keys = obj.scopeKeys(v.Scope);
            v.UnreviewedOnly = logical(c.Unreviewed.Value);
            v.Order = string(c.Order.Value);
            v.Seed = double(c.Seed.Value);
            v.Blind = logical(c.Blind.Value);
        end

        function write(obj,v)
            % Put choices V (any of read()'s fields) into the window.
            if ~obj.isopen() || ~isstruct(v), return; end
            c = obj.Ctrl;
            if isfield(v,'Keys') && isfield(v,'Scope') && string(v.Scope) == "selected"
                obj.Keys = reshape(string(v.Keys),[],1);
                obj.syncScopeItems();
            end
            if isfield(v,'Scope') && any(obj.Scopes == string(v.Scope))
                c.Scope.Value = char(string(v.Scope));
            end
            if isfield(v,'UnreviewedOnly'), c.Unreviewed.Value = logical(v.UnreviewedOnly); end
            if isfield(v,'Order') && any(string(v.Order) == ["browser","random"])
                c.Order.Value = char(string(v.Order));
            end
            if isfield(v,'Seed') && isnumeric(v.Seed) && isscalar(v.Seed) && isfinite(v.Seed)
                c.Seed.Value = round(double(v.Seed));
            end
            if isfield(v,'Blind'), c.Blind.Value = logical(v.Blind); end
            obj.recompute();
        end

        function tf = apply(obj)
            % Start the queue (the window stays open). Refused (false) when
            % the scope holds nothing to review or the Model is busy.
            tf = false;
            if ~obj.isopen(), return; end
            obj.recompute();
            if obj.WhyNot ~= "" || obj.isBusy(), return; end
            v = obj.read();
            obj.Model.startReviewQueue(v.Keys,'Order',v.Order,'Seed',v.Seed, ...
                'UnreviewedOnly',v.UnreviewedOnly,'Blind',v.Blind);
            obj.Started = true;
            tf = true;
        end

        function tf = ok(obj)
            % Start: start the queue and close.
            tf = obj.apply();
            if tf
                obj.Done = true;
                obj.closeFigure();
            end
        end

        function cancel(obj)
            if obj.Done, return; end
            obj.Done = true;
            obj.closeFigure();
        end

        function tf = isopen(obj)
            tf = ~obj.Done && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end
    end

    methods (Static)
        function tf = run(model,keys,varargin)
            % Show the dialog and wait (uiwait) until it closes: true when a
            % queue was started from it. Interactive use only.
            if nargin < 2, keys = strings(0,1); end
            d = mabr.ui.analysis.ReviewDialog(model,keys,varargin{:});
            if d.isopen()
                uiwait(d.Figure);
            end
            tf = d.Started;
            delete(d);
        end
    end

    % =====================================================================
    methods (Access = private)
        function build(obj)
            f = obj.Figure;
            g = uigridlayout(f,[8 2]);
            g.RowHeight = {26,24,26,26,24,'1x',22,30};
            g.ColumnWidth = {110,'1x'};
            g.Padding = [14 12 14 10];
            g.RowSpacing = 7;

            uilabel(g,'Text','Sessions');
            obj.Ctrl.Scope = uidropdown(g,'Items',{'Selected','In study','All analysed'}, ...
                'ItemsData',cellstr(obj.Scopes),'Tag','AnalysisReviewScope', ...
                'Tooltip','Which sessions the queue walks through (only those with results).', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            obj.syncScopeItems();
            k = uicheckbox(g,'Text','Only sessions with series still to review','Value',true, ...
                'Tag','AnalysisReviewUnreviewed', ...
                'Tooltip','Leave out the sessions whose every series already has a decision.', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            k.Layout.Row = 2; k.Layout.Column = [1 2];
            obj.Ctrl.Unreviewed = k;
            uilabel(g,'Text','Order');
            obj.Ctrl.Order = uidropdown(g,'Items',{'Browser order','Random'},'ItemsData',{'browser','random'}, ...
                'Tag','AnalysisReviewOrder', ...
                'Tooltip','The browser''s order, or a random one fixed by the seed (so it can be repeated).', ...
                'ValueChangedFcn',@(~,~) obj.recompute());
            uilabel(g,'Text','Seed');
            obj.Ctrl.Seed = uieditfield(g,'numeric','Value',12,'Limits',[0 Inf],'RoundFractionalValues','on', ...
                'ValueDisplayFormat','%d','Tag','AnalysisReviewSeed', ...
                'Tooltip','The seed of the random order: the same seed gives the same order.');
            k = uicheckbox(g,'Text','Blind review: hide subject, folder, date, timepoint and group', ...
                'Value',false,'Tag','AnalysisReviewBlind', ...
                'Tooltip','Until the queue ends the window shows each session only by its place in the queue.');
            k.Layout.Row = 5; k.Layout.Column = [1 2];
            obj.Ctrl.Blind = k;
            nt = uilabel(g,'WordWrap','on','VerticalAlignment','top','FontColor',mabr.ui.analysis.Style.Muted, ...
                'Text',char("The queue opens each session in turn: review its series, then " + ...
                mabr.ui.analysis.ReviewDialog.nextKey() + " (Session ▸ Next Session) moves on to the " + ...
                "next one. Session ▸ End Review leaves the queue."));
            nt.Layout.Row = 6; nt.Layout.Column = [1 2];
            cnt = uilabel(g,'Text','','Tag','AnalysisReviewCount','FontWeight','bold');
            cnt.Layout.Row = 7; cnt.Layout.Column = [1 2];
            obj.Ctrl.Count = cnt;

            r = uigridlayout(g,[1 3],'Padding',[0 0 0 0],'ColumnSpacing',8);
            r.Layout.Row = 8; r.Layout.Column = [1 2];
            r.ColumnWidth = {'1x',110,90};
            st = uibutton(r,'Text','Start','Tag','AnalysisReviewStart', ...
                'Tooltip','Start the review queue with the first session.','ButtonPushedFcn',@(~,~) obj.ok());
            st.Layout.Column = 2;
            mabr.ui.analysis.Style.setButtonIcon(st,'preview','left');
            obj.Ctrl.Start = st;
            cb = uibutton(r,'Text','Cancel','Tag','AnalysisReviewCancel', ...
                'Tooltip','Close without starting a queue (Esc).','ButtonPushedFcn',@(~,~) obj.cancel());
            cb.Layout.Column = 3;
        end

        function syncScopeItems(obj)
            items = obj.Ctrl.Scope.Items;
            if isempty(obj.Keys)
                items{1} = 'Selected (none)';
            else
                items{1} = sprintf('Selected (%d)',numel(obj.Keys));
            end
            obj.Ctrl.Scope.Items = items;
        end

        function keys = scopeKeys(obj,scope)
            % The analysed sessions of a scope.
            m = obj.Model;
            try
                switch string(scope)
                    case "selected"
                        keys = obj.Keys;
                    case "instudy"
                        keys = string(m.Project.studyKeys());
                    otherwise
                        keys = m.allKeys();      % (the hidden ones left out)
                end
            catch
                keys = strings(0,1);
            end
            keys = reshape(keys,[],1);
            keep = false(numel(keys),1);
            for i = 1:numel(keys)
                keep(i) = m.hasResults(keys(i));
            end
            keys = keys(keep);
            % in the browser's order, as the queue will walk them
            try
                order = m.BrowserOrder;
                if ~isempty(order)
                    [tf,pos] = ismember(keys,order);
                    pos(~tf) = numel(order) + find(~tf);
                    [~,ix] = sort(pos);
                    keys = keys(ix);
                end
            catch
            end
        end

        function recompute(obj)
            if ~obj.isopen(), return; end
            c = obj.Ctrl;
            scope = string(c.Scope.Value);
            keys = obj.scopeKeys(scope);
            n = numel(keys);
            nLeft = n;
            if c.Unreviewed.Value && n > 0
                % Model.startReviewQueue's rule (sessionNeedsReview): an
                % analysed session -- not "none" or "failed" in the project
                % view -- with series and not all of them reviewed. A key the
                % view does not list is left out, as the queue leaves it.
                try
                    V = obj.Model.projectView();
                    [tf,loc] = ismember(keys,string(V.Key));
                    R = V(loc(tf),:);
                    ns = double(R.NumSeries);
                    nLeft = sum(~ismember(string(R.Status),["none","failed"]) & ns > 0 & ...
                        double(R.Reviewed) < ns);
                catch
                end
            end
            if n == 0
                if scope == "selected"
                    why = "No analysed session is selected in the browser.";
                elseif scope == "instudy"
                    why = "No session in the study has results yet.";
                else
                    why = "No session has results yet.";
                end
                txt = why;
            elseif nLeft == 0
                why = "Every series of these sessions is reviewed — untick “Only sessions with series still to review” to go through them again.";
                txt = why;
            else
                why = "";
                if nLeft == 1, txt = "1 session in the queue"; else, txt = sprintf('%d sessions in the queue',nLeft); end
            end
            obj.WhyNot = why;
            obj.put('count',c.Count,'Text',char(txt));
            obj.put('seedOn',c.Seed,'Enable',matlab.lang.OnOffSwitchState(string(c.Order.Value) == "random"));
            obj.syncEnable();
        end

        function tf = isBusy(obj)
            tf = false;
            try
                tf = obj.Model.Busy;
            catch
            end
        end

        function syncEnable(obj)
            if ~obj.isopen(), return; end
            busy = obj.isBusy();
            on = obj.WhyNot == "" && ~busy;
            obj.put('startOn',obj.Ctrl.Start,'Enable',matlab.lang.OnOffSwitchState(on));
            if busy
                tip = 'Wait for the running job to finish.';
            elseif obj.WhyNot ~= ""
                tip = char(obj.WhyNot);
            else
                tip = 'Start the review queue with the first session.';
            end
            obj.put('startTip',obj.Ctrl.Start,'Tooltip',tip);
        end

        function put(obj,key,h,prop,v)
            key = char(key);
            if isfield(obj.Written,key) && isequal(obj.Written.(key),v), return; end
            try
                h.(prop) = v;
                obj.Written.(key) = v;
            catch
            end
        end

        function onKey(obj,e)
            if strcmpi(e.Key,'escape'), obj.cancel(); end
        end

        function closeFigure(obj)
            try
                delete(obj.Listeners);
            catch
            end
            obj.Listeners = event.listener.empty;
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisReview');
            try
                uiresume(f);
            catch
            end
            delete(f);
            obj.Figure = [];
        end
    end

    methods (Static, Access = private)
        function k = nextKey()
            % The key of Session ▸ Next Session, from the one keymap.
            k = "Ctrl+PageDown";
            try
                S = mabr.ui.analysis.Commands.sheet("global");
                r = find(S.Id == "session.next",1);
                if ~isempty(r), k = S.Keys(r); end
            catch
            end
        end
    end
end
