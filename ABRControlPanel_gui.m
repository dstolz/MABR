function h = ABRControlPanel_gui()

h.fig = findobj('type','figure','-and','name','ABR Control Panel');
if isempty(h.fig)
    h.fig = figure('name','ABR Control Panel', 'Position',[100 100 300 400], ...
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

h.tabs.Config = uitab(h.tabGroup,'title','Config', ...
    'BackgroundColor',h.fig.Color);

h.tabs.Control = uitab(h.tabGroup,'Title','Control', ...
    'BackgroundColor',h.fig.Color);

h.tabs.Info = uitab(h.tabGroup,'title','Info', ...
    'BackgroundColor',h.fig.Color);
















guidata(h.fig,h);