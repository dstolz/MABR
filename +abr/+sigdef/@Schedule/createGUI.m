function createGUI(obj)
obj.schFig = findobj('type','figure','-and','Name','ABR Schedule');

if isempty(obj.schFig)
    obj.schFig = figure('name','ABR Schedule', 'Position',[600 200 700 500], ...
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
    obj.h.pthLoad.ClickedCallback = {@abr.sigdef.Schedule.ext_load_schedule,obj};
    obj.h.pthLoad.CData = imgFileLoad;
    
    obj.h.pthSave = uipushtool(obj.h.toolbar);
    obj.h.pthSave.Tag = 'SaveButton';
    obj.h.pthSave.Tooltip = 'Save Schedule';
    obj.h.pthSave.ClickedCallback = {@abr.sigdef.Schedule.ext_save_schedule,obj};
    obj.h.pthSave.CData = imgFileSave;
    obj.h.pthSave.Enable = 'off';
    
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
    obj.h.schTbl.CellSelectionCallback = @abr.sigdef.Schedule.cell_selection;
    obj.h.schTbl.CellEditCallback      = @abr.sigdef.Schedule.cell_edit;
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
    obj.h.btnSortCol.Callback = @abr.sigdef.Schedule.selection_processor;
    
    R = R - Rspace;
    obj.h.btnResetSchedule = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
    obj.h.btnResetSchedule.Position = [10 R 140 40];
    obj.h.btnResetSchedule.String = 'Reset Schedule';
    obj.h.btnResetSchedule.FontSize = 14;
    obj.h.btnResetSchedule.Callback = @abr.sigdef.Schedule.selection_processor;
    
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
    obj.h.btnAllNone.Callback = @abr.sigdef.Schedule.selection_processor;
    
    R = R - Rspace;
    obj.h.btnEverySecond = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
    obj.h.btnEverySecond.Position = [10 R 140 40];
    obj.h.btnEverySecond.String = 'Every Other';
    obj.h.btnEverySecond.FontSize = 14;
    obj.h.btnEverySecond.Callback = @abr.sigdef.Schedule.selection_processor;
    
    R = R - Rspace;
    obj.h.btnSelectCustom = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
    obj.h.btnSelectCustom.Position = [10 R 140 40];
    obj.h.btnSelectCustom.String = 'Custom';
    obj.h.btnSelectCustom.FontSize = 14;
    obj.h.btnSelectCustom.Callback = @abr.sigdef.Schedule.selection_processor;
    
    R = R - Rspace;
    obj.h.btnToggleSel = uicontrol(obj.h.buttonPanel,'Style','pushbutton');
    obj.h.btnToggleSel.Position = [10 R 140 40];
    obj.h.btnToggleSel.String = 'Toggle';
    obj.h.btnToggleSel.FontSize = 14;
    obj.h.btnToggleSel.Callback = @abr.sigdef.Schedule.selection_processor;
end

figure(obj.schFig);

