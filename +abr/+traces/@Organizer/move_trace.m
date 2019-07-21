function move_trace(hFig,event,obj) %#ok<INUSL>
persistent LAST_ACCESS LAST_COORD LAST_STATE

if isempty(LAST_ACCESS), LAST_ACCESS = 0; end


if now - LAST_ACCESS < .5e-6, return; end % 1e-6 = 100 ms
LAST_ACCESS = now;

tidx = obj.TraceSelection;
if isempty(tidx), return; end

% C = hFig.CurrentPoint;
XY = figxy2axisxy(obj.mainAx);

yl = obj.mainAx.YLim;
% fprintf('XY = [%.3f %.3f];\tYLim = [%.3f %.3f]\n',[XY yl])

% if XY(2) < yl(1) || XY(2) > yl(2), return; end

L = abr.traces.Organizer.button_state_left;

if ~L, LAST_STATE = 0; return; end

if  isempty(LAST_COORD) || LAST_STATE == 0, LAST_COORD = XY; end

LAST_STATE = 1;


DC = XY - LAST_COORD;

if ~any(DC), return; end


LAST_COORD = XY;

obj.update_yoffset(tidx,[obj.Traces(tidx).YOffset] + DC(2));

h = [obj.Traces(tidx).LineHandle];
k = [obj.Traces(tidx).LabelHandle];
for i = 1:length(h)
    %h(i).YData = h(i).YData + DC(2)*m;
    h(i).YData = h(i).YData + DC(2);
    k(i).Position(2) = obj.YOffset(tidx(i));
end

obj.plot_amp_scale;

drawnow limitrate
