function xy = figxy2axisxy(ax,fXY)

if nargin == 0, ax = gca; end
f = ancestor(ax,'figure');

origFigUnits = f.Units;
origAxUnits  = ax.Units;

f.Units  = 'pixels';
ax.Units = 'pixels';

if nargin < 2 || isempty(fXY)
    fXY = f.CurrentPoint;
end

axPos = ax.Position;

axLeft   = axPos(1);
axBottom = axPos(2);
axWidth  = axPos(3);
axHeight = axPos(4);

axX  = ax.XAxis.Limits;
axY  = ax.YAxis.Limits;

% axis unit per pixel
axXn = diff(axX) ./ axWidth;
axYn = diff(axY) ./ axHeight;


xy = [axXn axYn] .* (fXY - [axLeft axBottom]);

f.Units  = origFigUnits;
ax.Units = origAxUnits;

