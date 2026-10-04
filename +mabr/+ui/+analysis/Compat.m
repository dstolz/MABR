classdef Compat
% mabr.ui.analysis.Compat  Everything the analysis app needs from MATLAB releases after R2021b.
%
%   MABR's floor is R2021b (mabr.Config), while the bench runs R2025a. A few
%   conveniences the analysis window wants -- a tree's double-click callback,
%   moving keyboard focus, a hint inside an empty edit field, a light theme,
%   a table's row selection -- arrived after R2021b, and a property that does
%   not exist is an error on the older release, not a no-op. So every such
%   identifier is named in THIS file and nowhere else in +mabr/+ui/+analysis
%   or AnalysisApp.m (tests/verify_offline_app.m scans for them), and each
%   helper degrades to what the older release can do: an Open button instead
%   of a double-click, a tooltip instead of a placeholder.
%
%       Compat.setDoubleClick(tree,@(s,e) openIt())   % nothing on R2021b
%       Compat.tryFocus(fig)                          % keyboard focus back to the figure
%       rows = Compat.selectedRows(tbl,evt)           % whichever API this release has
%       Compat.setPointer(fig,"top")                  % a pointer, or nothing
%
%   Static methods only; none of them throws for a missing feature.
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.Style
%
% Daniel Stolzberg (c) 2026

    methods (Static)
        function ok = setDoubleClick(h,fcn)
            % Wire a double-click callback where the component has one
            % (DoubleClickedFcn, R2022b+). Elsewhere nothing: the Enter key
            % and an Open button reach the same action.
            %   ok  (returned) true when the callback was installed
            ok = false;
            try
                if isprop(h,'DoubleClickedFcn')
                    h.DoubleClickedFcn = fcn;
                    ok = true;
                end
            catch
            end
        end

        function ok = setClicked(h,fcn)
            % A single-click callback on a tree or list (ClickedFcn, R2022b+).
            ok = false;
            try
                if isprop(h,'ClickedFcn')
                    h.ClickedFcn = fcn;
                    ok = true;
                end
            catch
            end
        end

        function ok = tryFocus(h)
            % Give h the keyboard focus (focus(), R2022a+). Inside a try: an
            % invisible or older figure simply keeps whatever had it.
            ok = false;
            try
                if isempty(h) || ~isvalid(h), return; end
                % focus() warns (it does not throw) on a component of an
                % invisible window; there is nothing to give the keys to.
                f = ancestor(h,'figure');
                if isempty(f) || ~strcmp(f.Visible,'on'), return; end
                focus(h);
                ok = true;
            catch
            end
        end

        function setPlaceholder(h,text)
            % Grey hint text in an empty edit field (Placeholder, R2023a+);
            % the tooltip carries it on an older release.
            try
                if isprop(h,'Placeholder')
                    h.Placeholder = char(text);
                    return
                end
            catch
            end
            try
                if isprop(h,'Tooltip') && isempty(h.Tooltip)
                    h.Tooltip = char(text);
                end
            catch
            end
        end

        function ok = enableRowSelection(tbl,fcn)
            % Whole-row selection with a SelectionChangedFcn where the table
            % has them; else a CellSelectionCallback. Either way FCN is
            % called (src,evt) and Compat.selectedRows reads the rows.
            %   ok  (returned) true when whole-row selection is in force
            ok = false;
            try
                if isprop(tbl,'SelectionType') && isprop(tbl,'SelectionChangedFcn')
                    tbl.SelectionType = 'row';
                    tbl.SelectionChangedFcn = fcn;
                    ok = true;
                    return
                end
            catch
            end
            try
                tbl.CellSelectionCallback = fcn;
            catch
            end
        end

        function rows = selectedRows(tbl,evt)
            % The table rows selected, from whichever API delivered them:
            % the table's own Selection (row selection), or the cell indices
            % of a CellSelectionCallback event. Unique and sorted; empty
            % when nothing is selected.
            rows = zeros(1,0);
            try
                if nargin >= 2 && ~isempty(evt) && isprop(evt,'Indices') && ~isempty(evt.Indices)
                    rows = unique(evt.Indices(:,1)).';
                    return
                end
            catch
            end
            try
                if nargin >= 2 && ~isempty(evt) && isstruct(evt) && isfield(evt,'Indices') ...
                        && ~isempty(evt.Indices)
                    rows = unique(evt.Indices(:,1)).';
                    return
                end
            catch
            end
            try
                if isprop(tbl,'Selection') && ~isempty(tbl.Selection)
                    sel = double(tbl.Selection);
                    type = 'cell';
                    if isprop(tbl,'SelectionType'), type = char(tbl.SelectionType); end
                    switch type
                        case 'row'
                            % a 1-by-N row vector of row indices
                            rows = unique(sel(:)).';
                        case 'column'
                            % columns, not rows: nothing row-wise is selected
                            rows = zeros(1,0);
                        otherwise
                            % 'cell': an N-by-2 [row column] list
                            rows = unique(sel(:,1)).';
                    end
                end
            catch
            end
        end

        function setSelectedRows(tbl,rows)
            % Select whole table rows programmatically where the release
            % allows it (Selection); a no-op elsewhere. Row selection takes a
            % 1-by-N row vector (a column errors); cell selection takes the
            % rows' first cells as an N-by-2 [row column] list.
            try
                if ~isprop(tbl,'Selection'), return; end
                rows = unique(double(rows(:))).';
                if isempty(rows)
                    tbl.Selection = [];
                    return
                end
                type = 'cell';
                if isprop(tbl,'SelectionType'), type = char(tbl.SelectionType); end
                if strcmp(type,'row')
                    tbl.Selection = rows;
                elseif strcmp(type,'cell')
                    tbl.Selection = [rows(:) ones(numel(rows),1)];
                end
            catch
            end
        end

        function tf = isTextComponent(h)
            % True for a component the user types into, where a letter key
            % is text and not a command: an edit field (text or numeric), a
            % text area, an editable dropdown, a spinner, or a table with an
            % editable cell selected. Empty or deleted handles are not.
            tf = false;
            try
                if isempty(h) || ~isvalid(h), return; end
            catch
                return
            end
            try
                c = class(h);
                switch c
                    case {'matlab.ui.control.EditField','matlab.ui.control.NumericEditField', ...
                          'matlab.ui.control.TextArea','matlab.ui.control.Spinner'}
                        tf = true;
                    case 'matlab.ui.control.DropDown'
                        tf = strcmp(h.Editable,'on');
                    case 'matlab.ui.control.Table'
                        tf = mabr.ui.analysis.Compat.editableCellSelected(h);
                    case 'matlab.ui.control.UIControl'
                        tf = strcmp(h.Style,'edit');
                end
            catch
                tf = false;
            end
        end

        function setLightTheme(fig)
            % Pin a uifigure to the light theme (Theme, R2025a), so a dark
            % desktop does not invert colours the views choose to mean
            % something. Earlier releases have only the light theme.
            try
                if isprop(fig,'Theme')
                    fig.Theme = 'light';
                end
            catch
            end
        end

        function setColorLimits(ax,lim)
            % Colour limits of an axes, through caxis (clim is R2022a+).
            try
                lim = double(lim);
                if numel(lim) == 2 && all(isfinite(lim)) && lim(2) > lim(1)
                    caxis(ax,lim); %#ok<CAXIS>
                end
            catch
            end
        end

        function h = hitObject(fig,evt)
            % The graphics object under a click: the event's HitObject when
            % the event carries one, else the figure's CurrentObject.
            if nargin >= 2 && ~isempty(evt)
                try
                    if (isstruct(evt) && isfield(evt,'HitObject')) || ...
                            (~isstruct(evt) && isprop(evt,'HitObject'))
                        h = evt.HitObject;
                        return
                    end
                catch
                end
            end
            try
                h = fig.CurrentObject;
            catch
                h = [];
            end
        end

        function h = makeLink(parent,text,fcn)
            % A hyperlink (uihyperlink, with a callback from R2023a) or, on
            % an older release, a flat button that looks close enough.
            % FCN is called with no arguments.
            link = [];
            try
                link = uihyperlink(parent,'Text',char(text));
                if isprop(link,'HyperlinkClickedFcn')
                    link.HyperlinkClickedFcn = @(~,~) fcn();
                    h = link;
                    return
                end
            catch
            end
            try
                if ~isempty(link) && isvalid(link), delete(link); end
            catch
            end
            h = uibutton(parent,'Text',char(text),'ButtonPushedFcn',@(~,~) fcn(), ...
                'BackgroundColor',[1 1 1],'FontColor',[0.216 0.451 0.678]);
        end

        function setSortable(tbl,tf)
            % Switch a table's interactive column sorting and rearranging
            % (ColumnSortable/ColumnRearrangeable) where the properties exist:
            % a table sorted by a click no longer lines up with the rows a
            % view holds keys for.
            v = matlab.lang.OnOffSwitchState(logical(tf));
            try
                if isprop(tbl,'ColumnSortable'), tbl.ColumnSortable = logical(tf); end
            catch
            end
            try
                if isprop(tbl,'ColumnRearrangeable'), tbl.ColumnRearrangeable = v; end
            catch
            end
        end

        function scrollTo(h,where)
            % Scroll a component (scroll(), R2021a+ for most, later for some)
            % to 'top', 'bottom', or a tree node / table row.
            try
                scroll(h,where);
            catch
            end
        end

        function ok = setPointer(fig,name)
            % The window's mouse pointer by name: "arrow", "top" (the
            % vertical resize arrows, over a divider that drags up and
            % down), "left" (the horizontal ones), "hand", "watch". A window
            % that refuses one keeps the pointer it has -- a pointer is a
            % hint, never worth an error.
            %   ok  (returned) true when the pointer was set
            ok = false;
            try
                if isempty(fig) || ~isvalid(fig), return; end
                fig.Pointer = char(name);
                ok = true;
            catch
            end
        end
    end

    methods (Static, Access = private)
        function tf = editableCellSelected(tbl)
            % A table with a selected cell whose column is editable.
            tf = false;
            try
                ed = tbl.ColumnEditable;
                if isempty(ed) || ~any(ed), return; end
                if ~isprop(tbl,'Selection') || isempty(tbl.Selection), return; end
                sel = tbl.Selection;
                if size(sel,2) >= 2
                    cols = sel(:,2);
                elseif isprop(tbl,'SelectionType') && strcmp(tbl.SelectionType,'column')
                    cols = sel(:);
                else
                    return
                end
                if isscalar(ed)
                    tf = logical(ed);
                else
                    cols = cols(cols >= 1 & cols <= numel(ed));
                    tf = any(ed(cols));
                end
            catch
                tf = false;
            end
        end
    end
end
