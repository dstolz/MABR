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
g.ColumnWidth = [repmat({'1x'},1,size(D,2)) 100];

varNames = D.Properties.VariableNames;
for i = 1:length(varNames)
    
    
    h = uilistbox(g);
    h.Layout.Row = 2;
    h.Layout.Column = i;
    h.Multiselect = 'on';
    d = unique(D.(varNames{i}));
    h.Items = cellstr(num2str(d,5));
    
    hlist(i) = h;
    
    
    h = uibutton(g,'state');
    h.Layout.Row = 1;
    h.Layout.Column = i;
    h.Text = obj.SIG.(varNames{i}).AliasWithUnit;
    h.UserData = hlist(i);
    
    hbtn(i) = h;
end

hinfo = uilabel(g);
hinfo.Layout.Row = 2;
hinfo.Layout.Column = length(hlist)+1;
hinfo.Text = '';


set(hbtn,'ValueChangedFcn',@sort_list);
set(hlist,'ValueChangedFcn',{@update_selection,obj,D,hlist,hinfo});


function update_selection(hObj,event,app,D,h,hinfo)
varNames = D.Properties.VariableNames;
ind = true(size(D,1),1);
for i = 1:length(varNames)
    v = str2double(h(i).Value);
    ind = ind & ismembertol(D.(varNames{i}),v,1e-5);
end

app.ScheduleTable.Data(:,1) = num2cell(ind);
app.ScheduleTable.UserData.Table = app.ScheduleTable.Data;

hinfo.Text = sprintf('%d stimuli selected',sum(ind));

function sort_list(hObj,event)

h = hObj.UserData;
v = str2double(h.Items(:));
if event.Value
    v = sort(v,'descend');
else
    v = sort(v,'ascend');
end

h.Items = cellstr(num2str(v,5));




