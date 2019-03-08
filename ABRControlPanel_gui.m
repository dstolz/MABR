function h = ABRControlPanel_gui()
%
%
% Daniel Stolzberg, PhD (c) 2019



h.fig = findobj('type','figure','-and','name','ABR Control Panel');
if isempty(h.fig)
    h.fig = figure('name','ABR Control Panel', 'Position',[100 100 200 400], ...
        'MenuBar','none','IntegerHandle','off');
else
    % already exists, so just make active and return
    figure(h.fig);
    h = guidata(h.fig);
    return
end
    

% programmatic toolbar
% % https://www.mathworks.com/help/matlab/creating_guis/creating-toolbars-for-programmatic-guis.html
h.toolbar.t = uitoolbar(h.fig); 


% tabs
h.tabGroup = uitabgroup(h.fig);

% CONFIG --------------------------------------------
h.Config.tab = uitab(h.tabGroup,'title','Config','BackgroundColor',h.fig.Color);


% CONTROL -------------------------------------------
h.Control.tab = uitab(h.tabGroup,'Title','Control','BackgroundColor',h.fig.Color);

styles.pushbutton.FontName = 'Arial';
styles.pushbutton.FontSize = 18;

h.Control.btnState = uicontrol(h.Control.tab, ...
    'Style','pushbutton', ...
    'Callback',@abrStateControl, ...
    'Position',[10 200 100 40], ...
    'String','Begin', ...
    'BackgroundColor',[0.2 1 0.2], ...
    'FontName',styles.pushbutton.FontName, ...
    'FontSize',styles.pushbutton.FontSize);

% INFO ----------------------------------------------
h.Info.tab = uitab(h.tabGroup,'title','Info','BackgroundColor',h.fig.Color);
















guidata(h.fig,h);