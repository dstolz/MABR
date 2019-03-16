classdef Schedule < handle
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (GetAccess = public, SetAccess = private)
        SIG
        data
        compiled
    end
    
    properties (SetAccess = private, GetAccess = public)
        h % gui object handles
        schFig
    end
    
    properties (GetAccess = public, SetAccess = private, Dependent)
        props
        
        selectedData % rows currently selected (checked) in table
        sigArray
    end
    
    methods
        
        function obj = Schedule(filename)
            obj.createGUI;
            
            if nargin == 1 && ~isempty(filename)
                sigdef.Schedule.load_schedule(filename)
                
            end
        end
        
        function a = get.sigArray(obj)
            s = obj.selectedData;
            a = repmat(sigdef.sigs.(obj.SIG.Type),length(s),1);
            for i = 1:length(a)
                for f = fieldnames(s)'
                    a(i).(char(f)).Value = s(i).(char(f));
                end
            end
        end
        
        function s = get.selectedData(obj)
            s = [];
            d = obj.h.schTbl.Data;
            if isempty(d), return; end
            
            d(~[d{:,1}],:) = [];
            d(:,1) = [];
            
            for i = 1:length(obj.props)
                for j = 1:size(d,1)
                    s(j).(obj.props{i}) = d{j,i};
                end
            end
            
        end
        
        
        function p = get.props(obj)
            p = fieldnames(obj.data);
        end
        
        
        function preprocess(obj,SIG,props,data)
            
            obj.SIG = SIG;
            
            for i = 1:length(props)
                if isempty(data{i,3}), continue; end
                
                P = obj.SIG.(props{i});
                
                D.(props{i}).SIG = P; % store sigProp for later (???)
                
                D.(props{i}).Alternate   = data{i,2};
                D.(props{i}).Description = P.Description;
                
                
                switch P.Type
                    case 'String'
                        D.(props{i}).values = data{i,3};
                        D.(props{i}).N = 1;
                        D.(props{i}).type = 'string';
                        
                    case 'File'
                        % THIS IS NOT RIGHT
                        f = cellfun(@(a) a(find(a==filesep,1,'last')+1:find(a=='.',1,'last')-1),P.Value,'uni',0);
                        D.(props{i}).values = f;
                        D.(props{i}).N = numel(P.Value);
                        D.(props{i}).filenames = P.Value;
                        D.(props{i}).type = 'files';
                        
                    case 'Numeric'
                        v = data{i,3};
                        if v(1) ~= '[', v = ['[' v ']']; end %#ok<AGROW>
                        
                        if data{i,2}
                            D.(props{i}).values = v;
                            D.(props{i}).N = 1;
                            D.(props{i}).type = 'Numeric';
                            D.(props{i}).Alternate = 1;
                        else
                            D.(props{i}).values = eval(v);
                            D.(props{i}).N = numel(D.(props{i}).values);
                            D.(props{i}).type = 'Numeric';
                            D.(props{i}).Alternate = 0;
                        end
                end
            end
            
            obj.data = D;
        end
        
        function compile(obj)
            D = obj.data;
            
            C = {};
            
            N = structfun(@(a) a.N,D);
            
            k = 1;
            
            Ps = obj.props;
            for i = 1:length(Ps)
                if isequal(D.(Ps{i}).type,'string') || isempty(D.(Ps{i}).values) % can't be included
                    D = rmfield(D,Ps{i});
                    continue
                end
                
                vj = D.(Ps{i}).values;
                
                if D.(Ps{i}).Alternate
                    if ~iscell(vj), vj = {vj}; end
                else
                    
                    if ischar(vj)
                        vj = {vj};
                    else
                        if ~iscell(vj), vj = num2cell(vj); end
                    end
                end
                
                if isempty(C)
                    C(:,k) = vj(:);
                else
                    if N(i) > 1
                        C = [C; repmat(C,N(i)-1,1)];
                        vje = repmat(vj,size(C,1)/N(i),1);
                    else
                        vje = repmat(vj,size(C,1),1);
                    end
                    C(:,k) = vje(:);
                end
                k = k + 1;
            end
            obj.data     = D; % fields may have been removed
            obj.compiled = C;
        end
        
        function update(obj)
            obj.createGUI;
            
            n = length(obj.props);
            
            t = table;
            t.v = true(size(obj.compiled,1),1);
            alias = cell(1,n);
            for i = 1:n
                if isnumeric(obj.compiled{1,i}) || islogical(obj.compiled{1,i})
                    t.(obj.props{i}) = [obj.compiled{:,i}]';
                else
                    t.(obj.props{i}) = obj.compiled(:,i);
                end
                alias{i} = obj.SIG.(obj.props{i}).Alias;
                if isempty(alias{i}), alias{i} = obj.props{i}; end
            end
            t.Properties.VariableDescriptions = [{'Use'} alias];

            colWidth = (obj.h.schTbl.Position(3) - 80)./ length(obj.props);
            
            obj.h.schTbl.ColumnName     = t.Properties.VariableDescriptions;
            obj.h.schTbl.ColumnWidth    = num2cell([20 colWidth*ones(1,n)]);
            obj.h.schTbl.ColumnFormat   = [{'logical'},repmat({'numeric'},1,n)];
            obj.h.schTbl.ColumnEditable = [true, false(1,n)];
            obj.h.schTbl.RowStriping    = 'on';
            obj.h.schTbl.Data = table2cell(t);
            % obj.h.schTbl.Data = t; % Functionality not supported with figures created with the figure function.
            
            obj.h.schTbl.UserData.Table = t;
            obj.h.schTbl.UserData.Obj = obj;
            
        end
        
        
        
        
        
        
        function createGUI(obj)
            obj.schFig = findobj('type','figure','-and','Name','Schedule');
            
            if isempty(obj.schFig)
                obj.schFig = figure('name','Schedule', 'Position',[600 200 700 500], ...
                    'MenuBar','none','IntegerHandle','off');
                
                
                % Toolbar
                obj.h.toolbar = uitoolbar(obj.schFig);
                
                iconPath = fullfile(matlabroot,'toolbox','matlab','icons');
                
                imgFileLoad = imread(fullfile(iconPath,'file_open.png'));
                imgFileLoad = im2double(imgFileLoad);
                imgFileLoad(imgFileLoad == 0) = nan;
                
                imgFileSave = imread(fullfile(iconPath,'file_save.png'));
                imgFileSave = im2double(imgFileSave);
                imgFileSave(imgFileSave == 0) = nan;
                
                obj.h.pthLoad = uipushtool(obj.h.toolbar);
                obj.h.pthLoad.Tooltip = 'Load Schedule';
                obj.h.pthLoad.ClickedCallback = {@sigdef.Schedule.load_schedule,obj};
                obj.h.pthLoad.CData = imgFileLoad;
                
                obj.h.pthSave = uipushtool(obj.h.toolbar);
                obj.h.pthSave.Tooltip = 'Save Schedule';
                obj.h.pthSave.ClickedCallback = {@sigdef.Schedule.save_schedule,obj};
                obj.h.pthSave.CData = imgFileSave;

                % Schedule Design Table
                obj.h.schTitleLbl = uicontrol(obj.schFig,'Style','text');
                obj.h.schTitleLbl.Position = [180 460 380 30];
                obj.h.schTitleLbl.String = 'Schedule';
                obj.h.schTitleLbl.FontSize = 18;
                obj.h.schTitleLbl.HorizontalAlignment = 'left';
                
                
                obj.h.schTbl = uitable(obj.schFig,'Tag','Schedule');
                obj.h.schTbl.Position = [180 20 500 440];
                obj.h.schTbl.FontSize = 12;
                obj.h.schTbl.ColumnEditable = false;
                obj.h.schTbl.RearrangeableColumns = 'on';
                obj.h.schTbl.Tooltip = 'Select one cell in one or more columns and then click "Sort on Column"';
                obj.h.schTbl.CellSelectionCallback = @sigdef.Schedule.cell_selection;
                obj.h.schTbl.UserData.ColumnSelected = [];
                obj.h.schTbl.UserData.RowSelected = [];
                
                %                 % Turn the JIDE sorting on
                %                 jscrollpane = findjobj(obj.h.schTbl);
                %                 jtable = jscrollpane.getViewport.getView;
                %
                %                 jtable.setSortable(true);
                %                 jtable.setAutoResort(true);
                %                 jtable.setMultiColumnSortable(true);
                %                 jtable.setPreserveSelectionsAfterSorting(true);
                %                 jtable.getTableHeader.setToolTipText('<html>&nbsp;<b>Click</b> to sort;<br />&nbsp;<b>Ctrl-click</b> to sort</html>');
                %                 jtable.setRowSelectionAllowed(true);
                %                 jtable.setColumnSelectionAllowed(false);
                
                
                % selection buttons
                obj.h.buttonPanel = uipanel(obj.schFig,'Units','Pixels', ...
                    'Position',[10 20 160 440]);
                    
                R = obj.h.buttonPanel.Position(4)-50; Rspace = 40;
                
                
                obj.h.btnSortCol = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
                obj.h.btnSortCol.Position = [10 R 140 40];
                obj.h.btnSortCol.String = 'Sort on Column';
                obj.h.btnSortCol.FontSize = 14;
                obj.h.btnSortCol.Callback = @sigdef.Schedule.selection_processor;
                
                R = R - Rspace;
                obj.h.btnResetSchedule = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
                obj.h.btnResetSchedule.Position = [10 R 140 40];
                obj.h.btnResetSchedule.String = 'Reset Schedule';
                obj.h.btnResetSchedule.FontSize = 14;
                obj.h.btnResetSchedule.Callback = @sigdef.Schedule.selection_processor;
                
                R = R - Rspace*2;
                
                
                obj.h.lblSelect = uicontrol(obj.h.buttonPanel,'Style','text');
                obj.h.lblSelect.Position = [10 R 140 20];
                obj.h.lblSelect.String = 'Select ...';
                obj.h.lblSelect.FontSize = 14;
                obj.h.lblSelect.HorizontalAlignment = 'left';
                
                R = R - Rspace - 10;
                obj.h.btnAllNone = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
                obj.h.btnAllNone.Position = [10 R 140 40];
                obj.h.btnAllNone.String = 'None';
                obj.h.btnAllNone.FontSize = 14;
                obj.h.btnAllNone.Callback = @sigdef.Schedule.selection_processor;
                
                R = R - Rspace;
                obj.h.btnEverySecond = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
                obj.h.btnEverySecond.Position = [10 R 140 40];
                obj.h.btnEverySecond.String = 'Every Other';
                obj.h.btnEverySecond.FontSize = 14;
                obj.h.btnEverySecond.Callback = @sigdef.Schedule.selection_processor;
                
                R = R - Rspace;
                obj.h.btnSelectCustom = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
                obj.h.btnSelectCustom.Position = [10 R 140 40];
                obj.h.btnSelectCustom.String = 'Custom';
                obj.h.btnSelectCustom.FontSize = 14;
                obj.h.btnSelectCustom.Callback = @sigdef.Schedule.selection_processor;
                
                R = R - Rspace;
                obj.h.btnToggleSel = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
                obj.h.btnToggleSel.Position = [10 R 140 40];
                obj.h.btnToggleSel.String = 'Toggle';
                obj.h.btnToggleSel.FontSize = 14;
                obj.h.btnToggleSel.Callback = @sigdef.Schedule.selection_processor;
            end
            
            figure(obj.schFig);
            
        end
    end
    
    
    
    
    
    methods (Static)
        function load_schedule(hObj,~,obj)
            if ischar(hObj)
                ffn = hObj;
                assert(exist(ffn,'file') == 2,'File does not exist! "%s"',ffn)
            else
                dfltpth = getpref('Schedule','path',cd);
                
                [fn,pn] = uigetfile({'*.sched','Schedule (*.sched)'},'Load a file',dfltpth);
                
                if isequal(fn,0), return; end
                
                ffn = fullfile(pn,fn);
            end
            
            fprintf('Loading schedule "%s" ...',ffn)
            
            
            load(ffn,'-mat','compiled','data','SIG','tblData');
            
            obj.SIG      = SIG;
            obj.compiled = compiled;
            obj.data     = data;
            obj.update;
            obj.h.schTbl.Data = tblData;
            
            fprintf(' done\n')
            
            setpref('Schedule','path',pn);
        end
        
        function save_schedule(~,~,obj)
            dfltpth = getpref('Schedule','path',cd);
            
            [fn,pn] = uiputfile({'*.sched','Schedule (*.sched)'},'Save schedule',dfltpth);
            
            if isequal(fn,0), return; end
            
            tblData  = obj.h.schTbl.Data;
            data     = obj.data;
            compiled = obj.compiled;
            SIG      = obj.SIG;
            
            save(fullfile(pn,fn),'-mat','compiled','data','SIG','tblData');
            
            fprintf('Schedule saved as ... %s\n',fullfile(pn,fn))
            
            setpref('Scehdule','path',pn);
        end
        
        function cell_selection(hObj,event)
            if isempty(event.Indices)
                hObj.UserData.ColumnSelected = [];
                hObj.UserData.RowSelected = [];
                return
            end
            row = event.Indices(:,1);
            col = event.Indices(:,2);
            hObj.UserData.ColumnSelected = col;
            hObj.UserData.RowSelected = row;
        end
        
        function selection_processor(hObj,event)
            
            htbl = findobj(ancestor(hObj,'figure'),'Tag','Schedule','-and','Type','uitable');
            
            [M,N] = size(htbl.Data);
            
            if M == 0, return; end % no data yet
            
            switch hObj.String
                case 'None'
                    htbl.Data(:,1) = num2cell(false(M,1));
                    hObj.String = 'All';
                    
                case 'All'
                    htbl.Data(:,1) = num2cell(true(M,1));
                    hObj.String = 'None';
                    
                case 'Every Other'
                    v = [true(1,M); false(1,M)];
                    htbl.Data(:,1) = num2cell(v(1:M));
                    
                case 'Custom'
                    dflt = getpref('Schedule','SelectCustom','1:2:end');
                    
                    opts.Resize='on';
                    opts.WindowStyle='modal';
                    opts.Interpreter='tex';
                    opts.InputFontSize = 14;
                    
                    r = inputdlg('\fontsize{14} Enter expression. M = length of schedule.', ...
                        'Select',1,{dflt},opts);
                    
                    if isempty(r), return; end
                    
                    t = false(M,1);
                    try
                        eval(sprintf('t(%s) = true;',char(r)));
                        htbl.Data(:,1) = num2cell(t);
                        setpref('Schedule','SelectCustom',char(r));
                    catch me
                        errordlg(sprintf('Invalid expression: %s.\n\n%s\n%s', ...
                            char(r),me.identifier,me.message),'Select');
                    end
                    
                case 'Toggle'
                    htbl.Data(:,1) = num2cell(~[htbl.Data{:,1}]');
                    
                case 'Sort on Column'
                    % TO DO: Need to make my own nested sort algo
                    col = htbl.UserData.ColumnSelected;
                    if isempty(col), return; end
                    
                    tbl = htbl.UserData.Table;
                    p = tbl.Properties.VariableNames;
                    sortDir = repmat({'ascend'},1,length(col));
                    for i = 1:length(col)
                        if iscellstr(tbl.(p{col(i)})) %#ok<ISCLSTR>
                            if issorted(string(tbl.(p{col(i)})),sortDir{i}), sortDir{i} = 'descend'; end
                        else
                            if issortedrows(tbl,p(col(i)),sortDir{i}), sortDir{i} = 'descend'; end
                        end
                    end
                    tbl = sortrows(tbl,p(col),sortDir);
                    htbl.UserData.Table = tbl;
                    htbl.Data = table2cell(tbl);
                    
                case 'Reset Schedule'
                    htbl.UserData.Obj.update;
            end
            
            
        end
        
        
        
    end
    
    
    
end