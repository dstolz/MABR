function gui_select(obj)

D = obj.ScheduleTable.Data;
varNames = D.Properties.VariableNames;

for i = 1:length(varNames)
   uV.(varNames{i}) = unique(D.(varNames{i}));   
end

ind = structfun(@numel,uV) > 1;
ind(1) = false; % Selected is always first column

D(:,~ind) = [];

f = uifigure;

g = uigridlayout(f,[2,size(D,2)+1]);
g.RowHeight = {50};
g.ColumnWidth = repmat({'1x'},1,size(D,2)+1);

varNames = D.Properties.VariableNames;
for i = 1:length(varNames)
    
    
    h = uilistbox(g);
    h.Layout.Row = 2;
    h.Layout.Column = i;
    h.Multiselect = 'on';
    h.Items = cellstr(num2str(unique(D.(varNames{i}))));
    
    hlist(i) = h;
    
    
    h = uibutton(g,'state');
    h.Layout.Row = 1;
    h.Layout.Column = i;
    h.Text = varNames{i};
    h.UserData = hlist(i);
    hbtn(i) = h;
end

set(hbtn,'ValueChangedFcn',@sort_list);
set(hlist,'ValueChangedFcn',{@update_selection,obj,D,hlist});




function update_selection(hObj,event,app,D,h)
varNames = D.Properties.VariableNames;
ind = true(size(D,1),1);
for i = 1:length(varNames)
    v = str2double(h(i).Value);
    ind = ind & ismember(D.(varNames{i}),v);
end

app.ScheduleTable.Data(:,1) = num2cell(ind);
app.ScheduleTable.UserData.Table = app.ScheduleTable.Data;

function sort_list(hObj,event)

h = hObj.UserData;
v = str2double(h.Items(:));
if event.Value
    v = sort(v,'descend');
else
    v = sort(v,'ascend');
end

h.Items = cellstr(num2str(v));




