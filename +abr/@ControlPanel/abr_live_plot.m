function abr_live_plot(app,postSweep,tvec,R)

persistent h

if nargin < 2 || isempty(h) || ~isfield(h,'axMean') || ~isvalid(h.axMean)
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

meanSweeps = mean(postSweep,1); % mean
h.meanLine.XData = tvec;
h.meanLine.YData = meanSweeps * 1000; % V -> mV
h.axMean.Title.String = sprintf('%d / %d postSweep',size(postSweep,1),app.ABR.numSweeps);

h.recentLine.XData = tvec;
h.recentLine.YData = postSweep(end,:) * 1000; % V -> mV

% control y axis scaling
m = logspace(-3,5,20);

may = max(abs(h.meanLine.YData));
s = m(find(m>may,1,'first'));
if isempty(s), s = may; end
h.axMean.YAxis.Limits = [-1 1] * s;
h.axMean.XAxis.Limits = app.ABR.adcWindow*1000;


may = max(abs(h.recentLine.YData));
s = m(find(m>may,1,'first'));
if isempty(s), s = may; end
h.axRecent.YAxis.Limits = [-1 1] * s;
h.axRecent.XAxis.Limits = h.axMean.XAxis.Limits;

h.corrBar.YData = R;

m = .5:.25:1;
m = m(find(m>max(R),1,'first'));
h.axCorr.YAxis.Limits = [0 m];



function h = setup(app)
vprintf(3,'Setting up abr_live_plot')
f = findobj('type','figure','-and','name','MABR Live Plot');

if isempty(f)
    p = app.ControlPanelUIFigure.Position;
    f = figure('name','MABR Live Plot','color','w','NumberTitle','off', ...
        'Position',[p(1)+p(3)+20 p(2)+p(4)-280 600 250], ...
        'tag','MABR_FIG');
end

clf(f);


axMean = subplot(1,3,[1 2],'parent',f);
axRecent = axes(f,'position',axMean.Position,'Color','none');
axCorr = subplot(1,3,3,'parent',f);


grid(axMean,'on');
box(axMean,'on');

axMean.XAxis.Label.String = 'time (ms)';
axMean.YAxis.Label.String = 'amplitude (mV)';



axMean.XAxis.Limits   = app.ABR.adcWindow * 1000; % s -> ms
axRecent.XAxis.Limits = app.ABR.adcWindow * 1000;

axRecent.YAxisLocation = 'right';
axRecent.YColor = [0.2 0.6 1];

% axMean.Toolbar.Visible = 'off'; % disable zoom/pan options
axMean.HitTest = 'off';

h.zeroLine   = line(axMean,[0 1000],[0 0],'linewidth',2,'color',[0.6 0.6 0.6]);
h.meanLine   = line(axMean,nan,nan,'linewidth',2,'color',[0 0 0]);
h.recentLine = line(axRecent,nan,nan,'linewidth',1,'color',[0.2 0.6 1]);

h.abrLegend = legend(axMean, ...
    [h.recentLine, h.meanLine], ...
    'labels',{'Latest Sweep','Mean Response'}, ...
    'Location','southeast', ...
    'Orientation','vertical', ...
    'Box','off', ...
    'AutoUpdate','off');


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
axCorr.XAxis.Limits = [0.5 3.5];

h.axMean   = axMean;
h.axRecent = axRecent;
h.axCorr   = axCorr;
h.fig = f;

figure(f);
