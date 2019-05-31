function abr_live_plot(app,postSweep,tvec,R)

persistent h

if nargin < 2 || isempty(h) || ~all(structfun(@isvalid,h))
    h = setup(app); 
    return
end

if isempty(postSweep)
    h.meanLine.YData   = nan;
    h.meanLine.XData   = nan;
    h.recentLine.YData = nan;
    h.recentLine.XData = nan;
    drawnow limitrate
    return
end

tvec = cast(tvec,'like',postSweep);
tvec = tvec * 1000; % s -> ms

meanSweeps = mean(postSweep); % mean
h.meanLine.XData = tvec;
h.meanLine.YData = meanSweeps * 1000; % V -> mV

h.recentLine.XData = tvec;
h.recentLine.YData = postSweep(end,:) * 1000; % V -> mV

y = max(abs(postSweep(:)))*1000;
y = ceil(y.*10);
y = y-mod(y,10)+10;
y = y./10;
if isnan(y), y = 1; end
h.ax.YAxis.Limits = [-1 1] * y;
h.ax.XAxis.Limits = app.ABR.adcWindow*1000;

h.ax.Title.String = sprintf('%d / %d postSweep',size(postSweep,1),app.ABR.numSweeps);

h.corrBar.YData = R;

x = h.axCorr.YAxis.Limits;
h.axCorr.YAxis.Limits = [0 max([x(2) .25])];



function h = setup(app)
f = findobj('type','figure','-and','name','MABR Live Plot');

if isempty(f)
    p = app.ControlPanelUIFigure.Position;
    f = figure('name','MABR Live Plot','color','w','NumberTitle','off', ...
        'Position',[p(1)+p(3)+20 p(2)+p(4)-280 600 250], ...
        'tag','MABR_FIG');
end

clf(f);


ax = subplot(1,5,[1 4],'parent',f);

grid(ax,'on');
box(ax,'on');

ax.XAxis.Label.String = 'time (ms)';
ax.YAxis.Label.String = 'amplitude (mV)';

ax.XAxis.Limits = app.ABR.adcWindow * 1000; % s -> ms

ax.Toolbar.Visible = 'off'; % disable zoom/pan options
ax.HitTest = 'off';

h.zeroLine   = line(ax,[0 1000],[0 0],'linewidth',2,'color',[0.6 0.6 0.6]);
h.meanLine   = line(ax,nan,nan,'linewidth',2,'color',[0 0 0]);
h.recentLine = line(ax,nan,nan,'linewidth',1,'color',[0.2 0.6 1]);

h.abrLegend = legend(ax, ...
    [h.recentLine, h.meanLine], ...
    'labels',{'Latest Sweep','Block Avg'}, ...
    'Location','southeast', ...
    'Orientation','vertical', ...
    'Box','off', ...
    'AutoUpdate','off');


axCorr = subplot(1,5,5,'parent',f);

h.corrBar = bar(axCorr, ...
    [1 2 3],[nan nan nan],1, ...
    'FaceColor','Flat','EdgeColor','none', ...
    'CData',[1 .4 .4; 1 .6 .2; .2 1 .2]);

axCorr.YAxisLocation = 'right';
grid(axCorr,'on');
axCorr.YAxis.Label.String = 'correlation';
axCorr.XAxis.TickValues = [1 2 3];
axCorr.XAxis.TickLabels = {'Pre'; 'Cross'; 'Post'};
axCorr.XAxis.TickLabelRotation = 45;


h.ax = ax;
h.axCorr = axCorr;
h.fig = f;

figure(f);
