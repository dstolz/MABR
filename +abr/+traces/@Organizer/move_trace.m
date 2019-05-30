function move_trace(hFig,event,obj) %#ok<INUSL>
persistent LAST_ACCESS LAST_COORD LAST_STATE

if isempty(LAST_ACCESS), LAST_ACCESS = 0; end


if now - LAST_ACCESS < .5e-6, return; end % 1e-6 = 100 ms
LAST_ACCESS = now;

tidx = obj.TraceSelection;
if isempty(tidx), return; end

C = hFig.CurrentPoint;

L = abr.traces.Organizer.button_state_left;

if ~L, LAST_STATE = 0; return; end


if  isempty(LAST_COORD) || LAST_STATE == 0, LAST_COORD = C; end

LAST_STATE = 1;

DC = C - LAST_COORD;

if ~any(DC), return; end

LAST_COORD = C;

m = 10; % movement multiplier
obj.YPosition(tidx) = obj.YPosition(tidx) + DC(2)*m;

h = [obj.Traces(tidx).LineHandle];
k = [obj.Traces(tidx).LabelHandle];
for i = 1:length(h)
    h(i).YData = h(i).YData + DC(2)*m;
    k(i).Position(2) = obj.YPosition(tidx(i));
end
drawnow limitrate
