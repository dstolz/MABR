function h = ScheduleDesign()
% Daniel Stolzberg, PhD (c) 2019

h.fig = findobj('type','figure','-and','name','Schedule Design');
if isempty(h.fig)
    h.fig = figure('name','Schedule Design', 'Position',[100 250 550 400], ...
        'MenuBar','none','IntegerHandle','off');
else
    % already exists, so just make active and return
    figure(h.fig);
    h = guidata(h.fig);
    return
end


% Signal Type
h.SigTypeLabel = uicontrol(h.fig,'Style','text');
h.SigTypeLabel.Position = [20 345 100 25];
h.SigTypeLabel.String = 'Signal:';
h.SigTypeLabel.FontSize = 16;


h.SigType = uicontrol(h.fig,'Style','popupmenu');
h.SigType.Position = [120 350 100 25];
h.SigType.FontSize = 16;
h.SigType.String = {'Tone','Noise','Click','File'};
h.SigType.Callback = @SigType_Callback;


% Signal Definition Table
h.SigDefTable = uitable(h.fig);
h.SigDefTable.Position = [20 20 500 300];
h.SigDefTable.FontSize = 12;
h.SigDefTable.ColumnName = {'Parameter','Alternate','Value'};
h.SigDefTable.ColumnEditable = [false,true,true];
h.SigDefTable.ColumnWidth = {150,50,300};
h.SigDefTable.ColumnFormat = {'char','logical','numeric'};
h.SigDefTable.RowName = [];
h.SigDefTable.CellEditCallback = @SigDefTable_Callback;
h.SigDefTable.CellSelectionCallback = @SigDefTabel_Selection;

SigType_Callback(h.SigType,[]); % init













    function SigType_Callback(src,event)
        sigType = src.String{src.Value};
        
        h.SIG = sigdef.sigs.(sigType);
        
        props = properties(h.SIG);
        ind = startsWith(props,'D_');
        props(~ind) = [];
        
        h.SigFiles = [];
        h.SigDefTable.Data = {[]};
        for i = 1:length(props)
            
            h.SigDefTable.Data{end+1,1} = h.SIG.(props{i});
            v = h.SIG.(props{i}(3:end));
            if isnumeric(v)
                v = mat2str(v);
            end
            h.SigDefTable.Data{end,3} = v;
            if isprop(h.SIG,(['A' props{i}(2:end)]))
                h.SigDefTable.Data{end,2} = h.SIG.(['A' props{i}(2:end)]);
            end
            
        end
        h.SigDefTable.Data(1,:) = [];
        
        h.SigDefTable.UserData = cellfun(@(a) a(3:end),props,'uni',0);

    end




    function SigDefTabel_Selection(src,event)
        if isempty(event.Indices), return; end
        prop = src.UserData{event.Indices(1)};
        
        switch event.Indices(2)
            case 1 % NAME
            case 2 % ALTERNATE
            case 3 % VALUE
                if isprop(h.SIG,['F_' prop])
                    % call a function
                    result = feval(eval(['h.SIG.F_' prop]));
                                        
                    if isempty(result), return; end
                    
                    for i = 1:length(result)
                        switch prop
                            case 'fullFilename'
                                h.SigFiles = result;
                                
                            case 'windowFcn'
                                h.SIG.windowFcn = result;
                                src.Data{event.Indices(1),event.Indices(2)} = result;
                        end
                    end
                end
                
        end
        
    end

    function SigDefTable_Callback(src,event,t)

        switch event.Indices(2)
            case 1 % NAME
            case 2 % ALTERNATE
            case 3
                try
                    nd = eval(event.NewData);
                catch me
                    src.Data{event.Indices(1),event.Indices(2)} = event.PreviousData;
                    helpdlg(sprintf('Unable to evaluate: "%s"',event.NewData));
                end
                
                
        end
        
        
        props = h.SigDefTable.UserData;
        data  = h.SigDefTable.Data;
        
        h.SCH = sigdef.Schedule;
        
        h.SCH.preprocess(h.SigType.String{h.SigType.Value},props,data,h.SigFiles);
        h.SCH.compile;
        h.SCH.update;
        
    end



    
end









