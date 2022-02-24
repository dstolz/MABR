function gui_select(obj)

D = obj.ScheduleTable.Data;
varNames = D.Properties.VariableNames;

for i = 1:length(varNames)
    uV.(varNames{i}) = unique(D.(varNames{i}));
end

ind = structfun(@numel,uV) > 1;
ind(1) = false; % Selected is always first column

D(:,~ind) = [];

pos = getpref('MABR_Schedule_gui_select','figPosition',[400 200 250 400]);

f = findall(0,'Tag','gui_select');
if isempty(f)
    f = uifigure('Tag','gui_select','Name','Select Values', ...
        'CloseRequestFcn',@closeme,'Position',pos);
end
movegui(f,'onscreen');
figure(f);


g = uigridlayout(f,[3,size(D,2)]);
g.RowHeight = {25,25,'1x'};
g.ColumnWidth = repmat({'1x'},1,size(D,2));

varNames = D.Properties.VariableNames;
for i = 1:length(varNames)
    
    
    h = uilistbox(g);
    h.Layout.Row = 3;
    h.Layout.Column = i;
    h.Multiselect = 'on';
    d = unique(D.(varNames{i}));
    h.Items = cellstr(num2str(d,5));
    h.UserData = varNames{i};
    hlist(i) = h;
    
    
    h = uibutton(g,'state');
    h.Layout.Row = 2;
    h.Layout.Column = i;
    h.Text = obj.SIG.(varNames{i}).AliasWithUnit;
    h.UserData = hlist(i);
    
    hbtn(i) = h;
end

hinfo = uilabel(g);
hinfo.Layout.Row = 1;
hinfo.Layout.Column = [1 length(hlist)];
hinfo.HorizontalAlignment = 'center';
hinfo.FontSize = 14;
hinfo.Text = '';


set(hbtn,'ValueChangedFcn',@sort_list);
set(hlist,'ValueChangedFcn',{@update_selection,obj,hlist,hinfo});


    function update_selection(hObj,event,app,h,hinfo)
        D = app.ScheduleTable.Data;
        
        ind = true(size(D,1),1);
        for i = 1:length(h)
            v = str2double(h(i).Value);
            ind = ind & ismembertol(D.(h(i).UserData),v,1e-5);
        end
        
        app.ScheduleTable.Data(:,1) = num2cell(ind);
        app.ScheduleTable.UserData.Table = app.ScheduleTable.Data;
        
        if sum(ind) == 1
            hinfo.Text = sprintf('%d stimulus selected',sum(ind));
        else
            hinfo.Text = sprintf('%d stimuli selected',sum(ind));
        end
    end

    function sort_list(hObj,event)
        
        h = hObj.UserData;
        v = str2double(h.Items(:));
        if event.Value
            v = sort(v,'descend');
        else
            v = sort(v,'ascend');
        end
        
        h.Items = cellstr(num2str(v,5));
    end

    function closeme(hObj,event)
        setpref('MABR_Schedule_gui_select','figPosition',hObj.Position);
        delete(hObj);
    end
end


