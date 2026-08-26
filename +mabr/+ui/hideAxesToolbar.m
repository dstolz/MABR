function hideAxesToolbar(ax)
%HIDEAXESTOOLBAR  Switch off the interactive axes toolbar on one or more axes.
%
%   mabr.ui.hideAxesToolbar(ax)
%
%   The default axtoolbar (zoom / pan / rotate / export glyphs that appear
%   when the mouse enters an axes) is hidden on every axes in `ax`. MABR's
%   plots are live views that redraw on a timer, and the toolbar's zoom
%   state fights the autoscaling those views do every tick; the windows
%   that need interaction (the trace organizer, the inspector) carry their
%   own. One helper so every plot in the toolbox makes the same choice.
%
%   Works on classic `axes` and `uiaxes` alike; an axes with no Toolbar
%   property (an older release, a deleted handle) is skipped rather than
%   thrown on, since a missing toolbar is the outcome asked for anyway.

for k = 1:numel(ax)
    a = ax(k);
    if ~isgraphics(a) || ~isprop(a,'Toolbar'), continue; end
    try
        a.Toolbar.Visible = 'off';
    catch
        % A toolbar that cannot be reached is as hidden as one that is.
    end
end
end
