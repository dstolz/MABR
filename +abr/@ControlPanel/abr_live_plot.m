function abr_live_plot(app,sweeps,tvec)

persistent h

if nargin < 2 || isempty(h) || ~all(structfun(@isvalid,h))
    h = setup(app); 
    return
end

if isempty(sweeps)
    h.meanLine.YData   = nan;
    h.meanLine.XData   = nan;
    h.recentLine.YData = nan;
    h.recentLine.XData = nan;
    drawnow limitrate
    return
end

tvec = cast(tvec,'like',sweeps);

meanSweeps = mean(sweeps); % mean
h.meanLine.XData = tvec;
h.meanLine.YData = meanSweeps * 1000; % V -> mV

h.recentLine.XData = tvec;
h.recentLine.YData = sweeps(end,:) * 1000; % V -> mV


y = max(abs(sweeps(:)))*1000;
y = ceil(y.*10);
y = y-mod(y,10)+10;
y = y./10;
if isnan(y), y = 1; end
h.ax.YAxis.Limits = [-1 1] * y;


h.ax.Title.String = sprintf('%d / %d sweeps',size(sweeps,1),app.ABR.numSweeps);




function h = setup(app)
f = findobj('type','figure','-and','name','Live Plot');

if isempty(f)
    p = app.ControlPanelUIFigure.Position;
    f = figure('name','Live Plot','color','w','NumberTitle','off', ...
        'Position',[p(1)+p(3)+20 p(2)+p(4)-280 600 250]);
end

clf(f);
ax = axes(f,'tag','live_plot','color','none');

grid(ax,'on');
box(ax,'on');

ax.XAxis.Label.String = 'time (ms)';
ax.YAxis.Label.String = 'amplitude (mV)';

ax.XAxis.Limits = app.ABR.adcWindow * 1000; % s -> ms

ax.Toolbar.Visible = 'off'; % disable zoom/pan options
ax.HitTest = 'off';

h.zeroLine   = line(ax,app.ABR.adcWindow,[0 0],'linewidth',2,'color',[0.6 0.6 0.6]);
h.meanLine   = line(ax,nan,nan,'linewidth',2,'color',[0 0 0]);
h.recentLine = line(ax,nan,nan,'linewidth',1,'color',[0.2 0.2 1]);
h.ax = ax;
h.fig = f;

figure(f);