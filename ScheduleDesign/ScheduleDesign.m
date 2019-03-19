function h = ScheduleDesign(schedDesignFile)
% TO DO: Loading and saving of schedule design file
%
% Daniel Stolzberg, PhD (c) 2019

if nargin == 1 && ~isempty(schedDesignFile), h.schedDesignFile = schedDesignFile; end

h.fig = findobj('type','figure','-and','name','Schedule Design');
if isempty(h.fig)
    h.fig = figure('name','Schedule Design', 'Position',[100 250 650 400], ...
        'MenuBar','none','IntegerHandle','off');
else
    % already exists, so just make active and return
    figure(h.fig);
    h = guidata(h.fig);
    return
end


% Toolbar
h.toolbar = uitoolbar(h.fig);

iconPath = fullfile(matlabroot,'toolbox','matlab','icons');

imgFileLoad = imread(fullfile(iconPath,'file_open.png'));
imgFileLoad = im2double(imgFileLoad);
imgFileLoad(imgFileLoad == 0) = nan;

imgFileSave = imread(fullfile(iconPath,'file_save.png'));
imgFileSave = im2double(imgFileSave);
imgFileSave(imgFileSave == 0) = nan;

h.pthLoad = uipushtool(h.toolbar);
h.pthLoad.Tooltip = 'Load Schedule';
h.pthLoad.ClickedCallback = @load_schedule_design;
h.pthLoad.CData = imgFileLoad;

h.pthSave = uipushtool(h.toolbar);
h.pthSave.Tooltip = 'Save Schedule';
h.pthSave.ClickedCallback = @save_schedule_design;
h.pthSave.CData = imgFileSave;

% Signal Type
h.SigTypeLabel          = uicontrol(h.fig,'Style','text');
h.SigTypeLabel.Position = [20 345 100 25];
h.SigTypeLabel.String   = 'Signal:';
h.SigTypeLabel.FontSize = 16;


h.SigType = uicontrol(h.fig,'Style','popupmenu');
h.SigType.Position      = [120 350 100 25];
h.SigType.FontSize      = 16;
h.SigType.String        = {'Tone','Noise','Click','File'};
h.SigType.Callback      = @SigType_Callback;


% Buttons
cspace = 10;
h.buttonPanel = uipanel(h.fig,'Units','pixels','Position',[250 330 350 60]);

h.btnSigSched = uicontrol(h.buttonPanel,'Style','pushbutton');
h.btnSigSched.Position   = [cspace 10 90 40];
h.btnSigSched.FontSize   = 14;
h.btnSigSched.String     = 'Compile';
h.btnSigSched.Callback   = @btnSigSched_Callback;

cspace = cspace + 100;
h.btnSigPlot = uicontrol(h.buttonPanel,'Style','pushbutton');
h.btnSigPlot.Position   = [cspace 10 60 40];
h.btnSigPlot.FontSize   = 14;
h.btnSigPlot.String     = 'Plot';
h.btnSigPlot.Callback   = @btnSigPlot_Callback;

% Signal Definition Table
h.SigDefTable = uitable(h.fig);
h.SigDefTable.Position      = [20 20 600 300];
h.SigDefTable.FontSize      = 14;
h.SigDefTable.ColumnName    = {'Parameter','Alternate','Value/Expression'};
h.SigDefTable.ColumnEditable = [false,true,true];
h.SigDefTable.ColumnWidth   = {200,50,320};
h.SigDefTable.ColumnFormat  = {'char','logical','numeric'};
h.SigDefTable.RowName       = [];
h.SigDefTable.CellEditCallback      = @SigDefTable_Callback;
h.SigDefTable.CellSelectionCallback = @SigDefTable_Selection;

f = findobj(h,'-property','Units');
set(f,'Units','Normalized');

f = findobj(h,'-property','FontUnits');
set(f,'FontUnits','Normalized');



SigType_Callback(h.SigType,[]); % init







    function SigType_Callback(src,event)
        sigType = src.String{src.Value};
        
        h.SIG = sigdef.sigs.(sigType);
        
        props = properties(h.SIG);
        
        ind = cellfun(@(a) isa(h.SIG.(a),'sigdef.sigProp'),props);
        props(~ind) = [];
        
        ind = cellfun(@(a) h.SIG.(a).Active,props);
        props(~ind) = [];
        
        h.SigFiles = [];
        h.SigDefTable.Data = {[]};
        for i = 1:length(props)
            
            if ~isa(h.SIG.(props{i}),'sigdef.sigProp') || ~h.SIG.(props{i}).Active, continue; end
            
            descr = h.SIG.(props{i}).DescriptionWithUnit;
            if isempty(descr), continue; end % only include properties with descriptions
            
            h.SigDefTable.Data{end+1,1} = descr;
            v = h.SIG.(props{i}).Value;
            
            if isnumeric(v), v = mat2str(v); end
            
            h.SigDefTable.Data{end,3} = v;
            
            % Alternating parameter?
            h.SigDefTable.Data{end,2} = h.SIG.(props{i}).Alternate;
        end
        h.SigDefTable.Data(1,:) = [];
        
        h.SigDefTable.UserData = props;

    end




    function SigDefTable_Selection(src,event)
        if isempty(event.Indices), return; end
        
        row = event.Indices(1);
        col = event.Indices(2);
        
        prop = src.UserData{row};

        switch col
            case 1 % NAME
            case 2 % ALTERNATE
            case 3 % VALUE

                if ~isempty(h.SIG.(prop).Function)
                    % call a function
                    result = feval(h.SIG.(prop).Function,h.SIG);
                                        
                    if isequal(result,'NOVALUE'), return; end
                    
                    h.SIG.(prop).Value = result;
                    
                    switch h.SIG.(prop).Type
                        case 'File'
                            f = cellfun(@(a) a(find(a==filesep,1,'last')+1:find(a=='.',1,'last')-1),result,'uni',0);
                            src.Data{row,col} = sprintf('"%s" ',f{:});
                                                        
                        case 'String'
                            src.Data{row,col} = result;
                    end
                end
        end
    end

    function SigDefTable_Callback(src,event,~)
        
        if isempty(event.Indices), return; end
        
        row = event.Indices(1);
        col = event.Indices(2);
        
        v = src.Data{row,3};
        
        if v(1) ~= '[', v = ['[' v ']']; end
                            
        try
            nd = eval(v);
            
        catch me
            switch me.identifier
                case 'MATLAB:UndefinedFunction'
                    src.Data{row,col} = event.PreviousData;
                    helpdlg(sprintf('Unable to evaluate: "%s"',event.NewData));
                    return
                    
                otherwise
                    rethrow(me)
            end
            
        end
        
        switch col
            case 1 % NAME
            case 2 % ALTERNATE
                
                if src.Data{row,col} == true && numel(nd) ~= 2
                    helpdlg('Must have two values to use Alternate option.');
                    src.Data{row,col} = false;
                end
                
            case 3 % VALUE
                if numel(nd) ~= 2
                    src.Data{row,2} = false;
                end
                
                try
                    updateSIG;
                    h.SIG = h.SIG.update;
                    
                catch me
                    errordlg(sprintf('Invalid expression:\n\n%s\n\n%s', ...
                        me.identifier,me.message),'Schedule Design','modal');
                    src.Data{row,3} = event.PreviousData;
                end
                
        end
        
        updateSIG;
        h.SIG = h.SIG.update;
        
    end


    function updateSIG
        
        props = h.SigDefTable.UserData;
        data  = h.SigDefTable.Data;
        
        for i = 1:length(props)
            h.SIG.(props{i}).Alternate = data{i,2};
            h.SIG.(props{i}).Value     = data{i,3};
        end
    end

    function btnSigSched_Callback(src,event,ignoreFigure)
        set(h.fig,'Pointer','watch'); drawnow
        
        props = h.SigDefTable.UserData;
        data  = h.SigDefTable.Data;
        
        if ~isfield(h,'SCH') || ~isa(h.SCH,'sigdef.Schedule')
            h.SCH = sigdef.Schedule;
        end
        
        h.SCH.preprocess(h.SIG,props,data);
        h.SCH.compile;
        h.SCH.update;
        
        if nargin < 3 || ~ignoreFigure
            figure(h.SCH.schFig);
        end
        
        set(h.fig,'Pointer','arrow');
    end


    function btnSigPlot_Callback(src,event)
        set(h.fig,'Pointer','watch'); drawnow

        
        if ~isfield(h,'figSigPlot') || isempty(h.figSigPlot)
            h.figSigPlot = figure('name','SigPlot','color','w'); 
            h.axSigPlot  = axes(h.figSigPlot,'Tag','SigPlot');
        end
        
        h.SIG = h.SIG.update;
        
        figure(h.figSigPlot);

%         btnSigSched_Callback([],[],true);
        cla(h.axSigPlot);
        grid(h.axSigPlot,'on');
        
        h.axSigPlot.XAxis.Label.String = 'time (ms)';
        h.axSigPlot.YAxis.Label.String = 'amplitude';
        for k = 1:numel(h.SIG.data)
            if length(h.SIG.timeVector) == 1
                t = h.SIG.timeVector{1}; 
            else
                t = h.SIG.timeVector{k};
            end
            hl(k) = line(h.axSigPlot,t*1000,h.SIG.data{k},'linestyle','-', ...
                'marker','o','markersize',4,'linewidth',2);
            if numel(hl) > 1
                set(hl(1:end-1),'marker','none','color',[0.8 0.8 0.8],'linewidth',1);
            end
            
%             y = max(abs(h.SIG.data{k}(:))) * 1.1;
%             h.axSigPlot.YAxis.Limits = [-y y];
            h.axSigPlot.YAxis.Limits = [-1.1 1.1];
            
            if isa(h.SIG,'sigdef.sigs.File')
                fn = h.SIG.fullFilename.Value{k};
                fn = fn(find(fn==filesep,1,'last')+1:find(fn=='.',1,'last')-1);
                pstr = sprintf('Filename: "%s"',fn);
            else
                x = h.SIG.dataParams;
                N = structfun(@(a) numel(unique(a)),x);
                p = fieldnames(x);
                x = rmfield(x,p(N==1));
                
                pstr = '';
                for i = fieldnames(x)'
                    v = x.(char(i));
                    pstr = sprintf('%s| %s: %.2f ',pstr,h.SIG.(char(i)).Alias,v(k));
                end
                pstr([1:2 end]) = [];
            end
            h.axSigPlot.Title.String = pstr;
            
            pause(0.5)
        end
        
        set(h.fig,'Pointer','arrow');

    end


    function load_schedule_design(hObj,event)
        
        disp('Load')
    end

    function save_schedule_design(hObj,event)
        disp('Save')
    end
end









