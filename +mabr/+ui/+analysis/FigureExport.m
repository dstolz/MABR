classdef FigureExport < handle
% mabr.ui.analysis.FigureExport  A plot of the analysis app as a publication figure.
%
%   Every plot in the analysis app ends its context menu with Export
%   figure..., Copy data and Copy image. They come here, so a figure leaves
%   the app the same way from every view:
%
%       files = mabr.ui.analysis.FigureExport.run(ax,Format="pdf",WidthCm=12, ...
%                   HeightCm=9,File="grid.pdf");
%       txt   = mabr.ui.analysis.FigureExport.copyData(ax);   % what is shown; also on the clipboard
%       mabr.ui.analysis.FigureExport.markForCopy(h);     % a hidden line Copy data copies
%       mabr.ui.analysis.FigureExport.copyImage(ax);
%       d     = mabr.ui.analysis.FigureExport(ax,app);        % the dialog
%       mabr.ui.analysis.FigureExport.addContextItems(cm,ax,app); % a plot's menu ends
%       txt   = mabr.ui.analysis.FigureExport.copyTable(tbl);  % "Copy table"
%
%   run() never draws on the window the user is looking at: it copies the
%   axes (or every axes of a panel, legends and colour bars with them) into
%   an invisible classic figure of the asked size in centimetres, sets the
%   font, a white background and the legend, writes the file -- vector for
%   pdf/svg/eps, at DPI for png/tiff -- and deletes the copy. What a journal
%   gets is therefore exactly what was plotted, at a size and font the
%   window's own layout never dictated.
%
%   Options (run, and the dialog's fields): Format "png"|"pdf"|"svg"|"tiff"|
%   "eps" (default "pdf"), WidthCm 12, HeightCm 9, DPI 300, FontName "Arial",
%   FontSize 9, Legend true, File "" (asked for with PickFileFcn when empty).
%
%   The dialog (Tags AnalysisFigureFormat, AnalysisFigureWidth,
%   AnalysisFigureHeight, AnalysisFigureDPI, AnalysisFigureFont,
%   AnalysisFigureFontSize, AnalysisFigureLegend, AnalysisFigureOK,
%   AnalysisFigureCancel) remembers its options in the MABR pref
%   OfflineAnalysisFigureExport -- written on OK only -- and its position
%   (mabr.ui.WindowPos, "OfflineAnalysisFigureExport").
%
%   See also exportgraphics, copygraphics, mabr.ui.analysis.View
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        PrefKey  = "OfflineAnalysisFigureExport"
        Formats  = ["pdf","png","svg","tiff","eps"]
        DefaultPosition = [280 200 420 340]
    end

    properties (SetAccess = private)
        Figure = []
        Source = []                 % the axes or panel being exported
        Host   = []                 % mabr.ui.AnalysisApp (or [])
        LastFile (1,1) string = ""  % the file the last ok() wrote
    end

    properties (Access = private)
        Ctrl = struct()
    end

    methods
        function obj = FigureExport(axOrPanel,host,opts)
            % FigureExport(axOrPanel,host,Visible=..): the export dialog.
            arguments
                axOrPanel
                host = []
                opts.Visible (1,1) string {mustBeMember(opts.Visible,["on","off"])} = "on"
            end
            obj.Source = axOrPanel;
            obj.Host   = host;
            if ~isempty(host) && isprop(host,'Visible') && opts.Visible == "on"
                try
                    if string(host.Visible) == "off", opts.Visible = "off"; end
                catch
                end
            end
            d = mabr.ui.analysis.FigureExport.loadDefaults();

            f = uifigure('Name','Export figure','Tag','MABR_OFFLINE_FIGUREEXPORT', ...
                'Position',obj.DefaultPosition,'Visible','off','Resize','off');
            mabr.ui.WindowPos.restore(f,'OfflineAnalysisFigureExport',obj.DefaultPosition);
            mabr.ui.analysis.Compat.setLightTheme(f);
            f.CloseRequestFcn = @(~,~) obj.cancel();
            obj.Figure = f;

            g = uigridlayout(f,[9 2]);
            g.RowHeight   = {24,24,24,24,24,24,24,'1x',30};
            g.ColumnWidth = {130,'1x'};
            g.Padding     = [12 12 12 10];
            g.RowSpacing  = 6;

            obj.Ctrl.Format = obj.row(g,1,"Format",uidropdown(g,'Items',cellstr(obj.Formats), ...
                'Value',char(d.Format),'Tag','AnalysisFigureFormat', ...
                'Tooltip','File format: pdf, svg and eps stay vector; png and tiff are drawn at the DPI below.'));
            obj.Ctrl.Width = obj.row(g,2,"Width (cm)",uieditfield(g,'numeric','Limits',[2 60], ...
                'Value',d.WidthCm,'Tag','AnalysisFigureWidth', ...
                'Tooltip','Width of the exported figure in centimetres.'));
            obj.Ctrl.Height = obj.row(g,3,"Height (cm)",uieditfield(g,'numeric','Limits',[2 60], ...
                'Value',d.HeightCm,'Tag','AnalysisFigureHeight', ...
                'Tooltip','Height of the exported figure in centimetres.'));
            obj.Ctrl.DPI = obj.row(g,4,"Resolution (DPI)",uieditfield(g,'numeric','Limits',[50 1200], ...
                'Value',d.DPI,'Tag','AnalysisFigureDPI', ...
                'Tooltip','Dots per inch of a png or tiff (vector formats ignore it).'));
            obj.Ctrl.Font = obj.row(g,5,"Font",uidropdown(g, ...
                'Items',{'Arial','Helvetica','Calibri','Times New Roman','Courier New'}, ...
                'Editable','on','Value',char(d.FontName),'Tag','AnalysisFigureFont', ...
                'Tooltip','Font of every label, tick and legend in the exported figure.'));
            obj.Ctrl.FontSize = obj.row(g,6,"Font size (pt)",uieditfield(g,'numeric','Limits',[4 40], ...
                'Value',d.FontSize,'Tag','AnalysisFigureFontSize', ...
                'Tooltip','Font size in points.'));
            lg = uicheckbox(g,'Text','Legend','Value',logical(d.Legend),'Tag','AnalysisFigureLegend', ...
                'Tooltip','Keep the legend in the exported figure.');
            lg.Layout.Row = 7; lg.Layout.Column = 2;
            obj.Ctrl.Legend = lg;

            bg = uigridlayout(g,[1 3],'Padding',[0 0 0 0]);
            bg.Layout.Row = 9; bg.Layout.Column = [1 2];
            bg.ColumnWidth = {'1x',110,90};
            okb = uibutton(bg,'Text','Export…','Tag','AnalysisFigureOK', ...
                'Tooltip','Choose a file and write the figure to it.', ...
                'ButtonPushedFcn',@(~,~) obj.okSafe());
            okb.Layout.Column = 2;
            mabr.ui.analysis.Style.setButtonIcon(okb,'figure','left');
            cb = uibutton(bg,'Text','Cancel','Tag','AnalysisFigureCancel', ...
                'Tooltip','Close without exporting.','ButtonPushedFcn',@(~,~) obj.cancel());
            cb.Layout.Column = 3;

            f.Visible = char(opts.Visible);
        end

        function delete(obj)
            obj.closeFigure();
        end

        function v = read(obj)
            % The options the fields hold (run()'s options, File "").
            v = mabr.ui.analysis.FigureExport.factoryDefaults();
            if ~obj.isopen(), return; end
            v.Format   = string(obj.Ctrl.Format.Value);
            v.WidthCm  = obj.Ctrl.Width.Value;
            v.HeightCm = obj.Ctrl.Height.Value;
            v.DPI      = obj.Ctrl.DPI.Value;
            v.FontName = string(obj.Ctrl.Font.Value);
            v.FontSize = obj.Ctrl.FontSize.Value;
            v.Legend   = logical(obj.Ctrl.Legend.Value);
        end

        function write(obj,v)
            % Put options V (any subset of the fields) into the dialog.
            if ~obj.isopen() || ~isstruct(v), return; end
            % option -> control, and how the control wants the value
            map = {'Format','Format',@char; 'WidthCm','Width',@double; ...
                'HeightCm','Height',@double; 'DPI','DPI',@double; ...
                'FontName','Font',@char; 'FontSize','FontSize',@double; ...
                'Legend','Legend',@logical};
            for i = 1:size(map,1)
                if ~isfield(v,map{i,1}), continue; end
                try
                    obj.Ctrl.(map{i,2}).Value = map{i,3}(v.(map{i,1}));
                catch me
                    mabr.log.vprintf(2,'FigureExport: ignoring %s (%s).',map{i,1},me.message);
                end
            end
        end

        function file = apply(obj)
            % Export with the fields' options (asks for the file); the
            % dialog stays open.
            v = obj.read();
            file = obj.exportWith(v);
        end

        function file = ok(obj)
            % Export, remember the options (pref), and close.
            v = obj.read();
            file = obj.exportWith(v);
            if strlength(file) > 0
                mabr.ui.analysis.FigureExport.saveDefaults(rmfield(v,'File'));
                obj.closeFigure();
            end
        end

        function cancel(obj)
            % Close without exporting.
            obj.closeFigure();
        end

        function tf = isopen(obj)
            tf = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end
    end

    methods (Static)
        function file = run(axOrPanel,opts)
            % Write the axes (or the panel's axes) to a file. Returns the
            % file written ("" when the user cancelled the file choice).
            arguments
                axOrPanel
                opts.Format (1,1) string {mustBeMember(opts.Format,["png","pdf","svg","tiff","eps"])} = "pdf"
                opts.WidthCm (1,1) double {mustBePositive} = 12
                opts.HeightCm (1,1) double {mustBePositive} = 9
                opts.DPI (1,1) double {mustBePositive} = 300
                opts.FontName (1,1) string = "Arial"
                opts.FontSize (1,1) double {mustBePositive} = 9
                opts.Legend (1,1) logical = true
                opts.File (1,1) string = ""
                opts.PickFileFcn = []
            end
            file = opts.File;
            if file == ""
                filt = "*." + opts.Format;
                def  = "figure_" + string(datetime('now','Format','yyMMdd''T''HHmmss')) + "." + opts.Format;
                if isempty(opts.PickFileFcn)
                    [fn,pn] = uiputfile({char(filt),char(upper(opts.Format) + " file")},'Export figure',char(def));
                    if isequal(fn,0), file = ""; return; end
                    file = string(fullfile(pn,fn));
                else
                    file = string(opts.PickFileFcn(filt,"Export figure","save",def));
                    if strlength(file) == 0, return; end
                end
            end
            [~,~,ext] = fileparts(file);
            if ext == "", file = file + "." + opts.Format; end
            d = fileparts(file);
            if strlength(d) > 0 && ~isfolder(d), mkdir(d); end

            fig = mabr.ui.analysis.FigureExport.copyToFigure(axOrPanel,opts);
            cleanup = onCleanup(@() delete(fig));
            switch opts.Format
                case {"pdf","eps"}
                    exportgraphics(fig,char(file),'ContentType','vector','BackgroundColor','white');
                case "svg"
                    % exportgraphics writes no SVG on every release; print
                    % does ('-vector' from R2022a, '-painters' before it).
                    try
                        print(fig,char(file),'-dsvg','-vector');
                    catch
                        print(fig,char(file),'-dsvg','-painters'); %#ok<PRTPT> (R2021b has no -vector)
                    end
                otherwise
                    exportgraphics(fig,char(file),'Resolution',opts.DPI,'BackgroundColor','white');
            end
            clear cleanup
        end

        function ok = copyImage(ax)
            % The axes (or panel) as an image on the clipboard -- without
            % what a view draws for the mouse (a threshold divider's grip, a
            % drag's readout), as an export leaves it out (copyToFigure):
            % hidden for the copy, shown again after.
            ok = false;
            hid = gobjects(0);
            try
                hid = findall(ax,'-regexp','Tag','Threshold(Grip|Readout|Drag)$','Visible','on');
                set(hid,'Visible','off');
            catch
            end
            try
                copygraphics(ax,'BackgroundColor','white');
                ok = true;
            catch me
                mabr.log.vprintf(2,'FigureExport: copy image failed (%s).',me.message);
            end
            try
                set(hid(isgraphics(hid)),'Visible','on');
            catch
            end
        end

        function h = markForCopy(h)
            % Mark hidden line(s) H as carrying a plot's values for Copy
            % data: a line drawn rescaled (on a second ruler) is copied in
            % its drawn units, so a view keeps the true values in an
            % invisible line beside it, and copyData copies that one.
            for k = 1:numel(h)
                try
                    setappdata(h(k),'MABRCopyData',true);
                catch
                end
            end
        end

        function txt = copyData(ax)
            % Every line of the axes (or of each axes in a panel) that is
            % SHOWN -- a line switched off (Visible 'off', or inside a
            % hidden group) is not copied, unless it is a carrier of the
            % plot's values made for this (markForCopy) -- as tab-separated
            % columns x,y per line, header row from each line's DisplayName
            % (else Tag, else "line k"); also put on the clipboard. Lines of
            % different lengths pad with blanks. A line with hidden handles
            % (a drawn ruler, a key, an outline) is drawing, not data, and
            % is passed by however the root's ShowHiddenHandles is set --
            % findobj alone would hand them over with it on.
            axs = mabr.ui.analysis.FigureExport.axesOf(ax);
            names = strings(1,0);  cols = {};
            k = 0;
            for a = reshape(axs,1,[])
                L = findall(a,'Type','line','-or','Type','errorbar');
                L = flipud(L(:));            % creation order
                for i = 1:numel(L)
                    carrier = false;
                    try
                        carrier = isappdata(L(i),'MABRCopyData') && logical(getappdata(L(i),'MABRCopyData'));
                    catch
                    end
                    if ~carrier && ~strcmp(L(i).HandleVisibility,'on'), continue; end
                    if ~mabr.ui.analysis.FigureExport.isShown(L(i),a), continue; end
                    x = double(L(i).XData(:));  y = double(L(i).YData(:));
                    if isempty(x) || all(isnan(y)), continue; end
                    k = k + 1;
                    nm = string(L(i).DisplayName);
                    if nm == "", nm = string(L(i).Tag); end
                    if nm == "", nm = "line " + k; end
                    names(end+1:end+2) = [nm + " x", nm + " y"];
                    cols{end+1} = x; %#ok<AGROW>
                    cols{end+1} = y; %#ok<AGROW>
                end
            end
            if isempty(cols)
                txt = "";
                return
            end
            n = max(cellfun(@numel,cols));
            lines = strings(n+1,1);
            lines(1) = strjoin(names,char(9));
            for r = 1:n
                cells = strings(1,numel(cols));
                for c = 1:numel(cols)
                    if r <= numel(cols{c}) && ~isnan(cols{c}(r))
                        cells(c) = string(sprintf('%.10g',cols{c}(r)));
                    end
                end
                lines(r+1) = strjoin(cells,char(9));
            end
            txt = strjoin(lines,newline);
            try
                clipboard('copy',char(txt));
            catch
            end
        end

        function txt = copyTable(src)
            % A table as tab-separated text with a header row, also put on
            % the clipboard -- every uitable's "Copy table" item.
            %   src  a uitable (its Data and ColumnName) or a MATLAB table
            T = src;
            names = strings(1,0);
            try
                if isa(src,'matlab.ui.control.Table')
                    T = src.Data;
                    cn = string(src.ColumnName);
                    if ~istable(T)
                        T = cell2table(num2cell(T));
                    end
                    if numel(cn) == width(T), names = reshape(cn,1,[]); end
                end
            catch
            end
            if ~istable(T)
                txt = "";
                return
            end
            if isempty(names), names = string(T.Properties.VariableNames); end
            C = strings(height(T),width(T));
            for j = 1:width(T)
                v = T{:,j};
                for i = 1:height(T)
                    if iscell(v), x = v{i}; else, x = v(i,:); end
                    C(i,j) = mabr.ui.analysis.FigureExport.cellText(x);
                end
            end
            lines = [strjoin(names,char(9)); join(C,char(9),2)];
            txt = strjoin(lines,newline);
            try
                clipboard('copy',char(txt));
            catch
            end
        end

        function items = addContextItems(cm,target,host)
            % The three items every plot's context menu ends with: Export
            % figure… (the dialog), Copy data, Copy image -- after a
            % separator, Tags AnalysisMenuFigureExport/CopyData/CopyImage.
            %   cm      a uicontextmenu
            %   target  the axes (or panel) they act on, or a function
            %           returning it at the moment the item is chosen
            %   host    mabr.ui.AnalysisApp ([] works: no status line)
            if nargin < 3, host = []; end
            tgt = @() mabr.ui.analysis.FigureExport.resolveTarget(target);
            items = gobjects(1,3);
            items(1) = uimenu(cm,'Text','Export figure…','Separator','on', ...
                'Tag','AnalysisMenuFigureExportItem', ...
                'MenuSelectedFcn',@(~,~) mabr.ui.analysis.FigureExport.openFor(tgt(),host));
            items(2) = uimenu(cm,'Text','Copy data','Tag','AnalysisMenuCopyDataItem', ...
                'MenuSelectedFcn',@(~,~) mabr.ui.analysis.FigureExport.copyData(tgt()));
            items(3) = uimenu(cm,'Text','Copy image','Tag','AnalysisMenuCopyImageItem', ...
                'MenuSelectedFcn',@(~,~) mabr.ui.analysis.FigureExport.copyImage(tgt()));
        end

        function d = factoryDefaults()
            d = struct('Format',"pdf",'WidthCm',12,'HeightCm',9,'DPI',300, ...
                'FontName',"Arial",'FontSize',9,'Legend',true,'File',"");
        end

        function d = loadDefaults()
            % The options the last OK used (pref OfflineAnalysisFigureExport),
            % forgiving of a pref from another version.
            d = mabr.ui.analysis.View.loadLook(mabr.ui.analysis.FigureExport.PrefKey, ...
                mabr.ui.analysis.FigureExport.factoryDefaults());
            if ~any(d.Format == mabr.ui.analysis.FigureExport.Formats), d.Format = "pdf"; end
            d.File = "";
        end

        function saveDefaults(d)
            % Remember the options -- from the dialog's OK, or a configuration.
            if isfield(d,'File'), d = rmfield(d,'File'); end
            mabr.ui.analysis.View.saveLook(mabr.ui.analysis.FigureExport.PrefKey,d);
        end
    end

    methods (Static, Access = private)
        function t = resolveTarget(target)
            if isa(target,'function_handle')
                t = target();
            else
                t = target;
            end
        end

        function openFor(target,host)
            if ~isempty(host) && isvalid(host)
                host.openDialog("figureExport",target);
            else
                mabr.ui.analysis.FigureExport(target,[]);
            end
        end

        function s = cellText(x)
            if isempty(x)
                s = "";
            elseif isstring(x) || ischar(x) || iscategorical(x)
                s = string(x);
                if ismissing(s), s = ""; end
                s = strjoin(s(:).'," ");
            elseif islogical(x)
                if all(x), s = "TRUE"; else, s = "FALSE"; end
            elseif isdatetime(x)
                s = string(x,'yyyy-MM-dd''T''HH:mm:ss');
                if ismissing(s), s = ""; end
            elseif isnumeric(x)
                x = double(x);
                if isscalar(x)
                    if isnan(x), s = ""; else, s = string(sprintf('%.10g',x)); end
                else
                    s = strjoin(string(x(:).'),' ');
                end
            else
                s = "";
            end
        end

        function axs = axesOf(h)
            % The axes to export: h itself, or every axes inside a container.
            if isa(h,'matlab.graphics.axis.Axes') || isa(h,'matlab.ui.control.UIAxes')
                axs = h;
            else
                axs = findall(h,'Type','axes');
                axs = flipud(axs(:));
            end
        end

        function tf = isShown(h,ax)
            % Whether graphics object H is drawn: it and every group between
            % it and its axes AX have Visible 'on' (the axes' own visibility
            % is the caller's: an axes in an invisible test window still
            % counts as shown). A carrier of values (markForCopy) counts.
            tf = true;
            try
                if isappdata(h,'MABRCopyData') && isequal(getappdata(h,'MABRCopyData'),true), return; end
            catch
            end
            p = h;
            while ~isempty(p) && isvalid(p) && p ~= ax
                try
                    if strcmp(p.Visible,'off'), tf = false; return; end
                catch
                end
                p = p.Parent;
            end
        end

        function fig = copyToFigure(src,opts)
            % An invisible classic figure WidthCm x HeightCm holding copies
            % of the axes (with their legends and colour bars).
            fig = figure('Visible','off','Color','w','Units','centimeters', ...
                'Position',[2 2 opts.WidthCm opts.HeightCm],'MenuBar','none', ...
                'ToolBar','none','InvertHardcopy','off','PaperUnits','centimeters', ...
                'PaperSize',[opts.WidthCm opts.HeightCm], ...
                'PaperPosition',[0 0 opts.WidthCm opts.HeightCm],'Tag','MABR_OFFLINE_EXPORTCOPY');
            axs = mabr.ui.analysis.FigureExport.axesOf(src);
            single = isscalar(axs) && isequal(axs,src);
            if ~single
                try
                    srcPos = getpixelposition(src);
                catch
                    srcPos = [0 0 1 1];
                end
            end
            for a = reshape(axs,1,[])
                extras = gobjects(0);
                try
                    if ~isempty(a.Legend) && isvalid(a.Legend), extras(end+1) = a.Legend; end %#ok<AGROW>
                catch
                end
                try
                    if ~isempty(a.Colorbar) && isvalid(a.Colorbar), extras(end+1) = a.Colorbar; end %#ok<AGROW>
                catch
                end
                c = copyobj([extras a],fig);
                na = c(end);
                na.Units = 'normalized';
                if single
                    na.OuterPosition = [0 0 1 1];
                else
                    try
                        p = getpixelposition(a,true);
                        rel = [(p(1)-srcPos(1))/srcPos(3) (p(2)-srcPos(2))/srcPos(4) ...
                            p(3)/srcPos(3) p(4)/srcPos(4)];
                        if all(isfinite(rel)) && all(rel(3:4) > 0)
                            na.Position = rel;
                        end
                    catch
                    end
                end
                try
                    na.Color = 'w';
                    na.ContextMenu = [];
                catch
                end
                try
                    na.Interactions = [];
                catch
                end
            end
            % (what a view draws for the mouse -- a threshold divider's grip,
            % a drag's readout -- is not part of the figure)
            delete(findall(fig,'-regexp','Tag','Threshold(Grip|Readout|Drag)$'));
            set(findall(fig,'-property','FontName'),'FontName',char(opts.FontName));
            set(findall(fig,'-property','FontSize'),'FontSize',opts.FontSize);
            lg = findall(fig,'Type','legend');
            if ~isempty(lg)
                set(lg,'Visible',matlab.lang.OnOffSwitchState(opts.Legend));
            end
        end
    end

    methods (Access = private)
        function h = row(~,g,r,label,ctrl)
            lab = uilabel(g,'Text',char(label),'HorizontalAlignment','right');
            lab.Layout.Row = r; lab.Layout.Column = 1;
            ctrl.Layout.Row = r; ctrl.Layout.Column = 2;
            h = ctrl;
        end

        function okSafe(obj)
            try
                obj.ok();
            catch me
                obj.report(me);
            end
        end

        function file = exportWith(obj,v)
            pick = [];
            if ~isempty(obj.Host) && isvalid(obj.Host)
                try
                    pick = obj.Host.Model.PickFileFcn;
                catch
                    pick = [];
                end
            end
            args = {'Format',v.Format,'WidthCm',v.WidthCm,'HeightCm',v.HeightCm,'DPI',v.DPI, ...
                'FontName',v.FontName,'FontSize',v.FontSize,'Legend',v.Legend};
            if ~isempty(pick), args = [args {'PickFileFcn',pick}]; end
            file = mabr.ui.analysis.FigureExport.run(obj.Source,args{:});
            obj.LastFile = file;
            if strlength(file) > 0 && ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus("Figure written to " + file,0);
            end
        end

        function report(obj,me)
            if ~isempty(obj.Host) && isvalid(obj.Host)
                obj.Host.setStatus("The figure was not exported: " + string(me.message),2);
            end
            mabr.log.vprintf(1,'FigureExport: %s',me.message);
        end

        function closeFigure(obj)
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            mabr.ui.WindowPos.remember(f,'OfflineAnalysisFigureExport');
            delete(f);
            obj.Figure = [];
        end
    end
end
