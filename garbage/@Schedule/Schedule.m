classdef Schedule < handle
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Access = public)
        filename (1,:) char
    end
    
    properties (GetAccess = public, SetAccess = private)
        SIG      (:,1)
        data
        compiled
                
        scheduleDesignFilename (1,:) char
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
        createGUI(obj);
        
        % Constructor
        function obj = Schedule(filename)
            
            if nargin == 1 && ~isempty(filename)
                obj.filename = filename;
            end
        end
        
        function set.filename(obj,ffn)
            obj.filename = ffn;
            obj.load_schedule;
        end
        
        function a = get.sigArray(obj)
            d = obj.h.schTbl.Data;
            a = repmat(abr.sigdef.sigs.(obj.SIG.Type),size(d,1),1);
            for i = 1:length(obj.props)
                for j = 1:size(d,1)
                     a(j).(obj.props{i}).Value = d{j,i+1};
                end
            end
        end
        
        function s = get.selectedData(obj)
            s = [];
            d = obj.h.schTbl.Data;
            if isempty(d), return; end
            s = [d{:,1}];
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
                alias{i} = obj.SIG.(obj.props{i}).AliasWithUnit;
                if isempty(alias{i}), alias{i} = obj.props{i}; end
            end
            t.Properties.VariableDescriptions = [{'Use'} alias];

%             colWidth = (obj.h.schTbl.Position(3) - 80)./ length(obj.props);
            
            obj.h.schTbl.ColumnName     = t.Properties.VariableDescriptions;
%             obj.h.schTbl.ColumnWidth    = num2cell([20 colWidth*ones(1,n)]);
            obj.h.schTbl.ColumnWidth    = [{20} repmat({'auto'},1,n)];
            obj.h.schTbl.ColumnFormat   = [{'logical'},repmat({'numeric'},1,n)];
            obj.h.schTbl.ColumnEditable = [true, false(1,n)];
            obj.h.schTbl.RowStriping    = 'on';
            obj.h.schTbl.Data = table2cell(t);
            % obj.h.schTbl.Data = t; % Functionality not supported with figures created with the figure function.
            
            obj.h.schTbl.UserData.Table = t;
            obj.h.schTbl.UserData.Obj = obj;
            
            
            [~,fn,~] = fileparts(obj.filename);
            obj.h.schTitleLbl.String  = sprintf('Schedule: %s',fn);
            obj.h.schTitleLbl.Tooltip = obj.filename;
            
        end
        
        function update_highlight(obj,row)
            persistent jUIScrollPane
            
            if isempty(jUIScrollPane)
                jUIScrollPane = findjobj(obj.h.schTbl);
            end
            jUITable = jUIScrollPane.getViewport.getView;
            jUITable.changeSelection(row-1,0, false, false);
            jUITable.changeSelection(row-1,size(obj.h.schTbl.Data,2)-1,false,true);
            
            jUIScrollPane.getVerticalScrollBar.setValue(row-1);
            jUIScrollPane.getHorizontalScrollBar.setValue(0);
        end
        
        function load_schedule(obj)
            ffn = obj.filename;
            if ~isempty(ffn) && ischar(ffn)
                assert(exist(ffn,'file') == 2,'File does not exist! "%s"',ffn)
            else
                dfltpth = getpref('Schedule','path',cd);
                
                [fn,pn] = uigetfile({'*.sched','Schedule (*.sched)'},'Load a file',dfltpth);
                
                if isequal(fn,0), return; end
                
                ffn = fullfile(pn,fn);
                
                setpref('Schedule','path',pn);
            end
            
            fprintf('Loading schedule "%s" ...',ffn)
            
            load(ffn,'-mat','compiled','data','SIG','tblData');
            
            obj.SIG      = SIG; %#ok<PROP>
            obj.compiled = compiled; %#ok<PROP>
            obj.data     = data; %#ok<PROP>
            
%             obj.filename = ffn;
            
            obj.update;
            obj.h.schTbl.Data = tblData;
                      
            
            obj.h.pthSave.Enable = 'off';
            
            fprintf(' done\n')
            
        end
        
        
    end
    
    methods (Access = private)
        function save_schedule(obj)
            dfltpth = getpref('Schedule','path',cd);
            
            [fn,pn] = uiputfile({'*.sched','Schedule (*.sched)'},'Save schedule',dfltpth);
            
            if isequal(fn,0), return; end
            
            tblData  = obj.h.schTbl.Data;
            data     = obj.data; %#ok<PROP>
            compiled = obj.compiled; %#ok<PROP>
            SIG      = obj.SIG; %#ok<PROP>
            
            save(fullfile(pn,fn),'-mat','compiled','data','SIG','tblData');
            
            fprintf('Schedule saved as ... %s\n',fullfile(pn,fn))
            
            obj.filename = fullfile(pn,fn);
            [~,fn,~] = fileparts(obj.filename);
            obj.h.schTitleLbl.String  = sprintf('Schedule: %s',fn);
            obj.h.schTitleLbl.Tooltip = obj.filename;
            
            setpref('Scehdule','path',pn);
            
            obj.h.pthSave.Enable = 'off';
        end
        
       
    end
    
    
    
    
    
    methods (Static)
        
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
        
        function cell_edit(hObj,event)
            hfig = ancestor(hObj,'figure','toplevel');
            hsave = findobj(hfig,'Tag','SaveButton');
            hsave.Enable = 'on';
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
            
            hsave = findobj(ancestor(hObj,'figure','toplevel'),'Tag','SaveButton');
            hsave.Enable = 'on';
        end
        
        function ext_load_schedule(~,~,obj)
            obj.filename = '';
            obj.load_schedule;
        end
        
        function ext_save_schedule(~,~,obj)
            obj.save_schedule;
        end
    end
    
    
    
end