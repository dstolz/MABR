function abr_live_plot(app,postSweep,tvec,R,options)

persistent h


if nargin < 2 || isempty(h) || ~isfield(h,'axMean') || ~isvalid(h.axMean)
    h = setup(app); 
    return
end

if nargin < 2 || isempty(postSweep)
    h.meanLine.YData   = nan;
    h.meanLine.XData   = nan;
    h.recentLine.YData = nan;
    h.recentLine.XData = nan;
    h.axCorr.YData = nan(1,3);
    return
end

if nargin < 5 || isempty(options)
    options = struct('SmoothSpan',0,'DetrendPoly',-1);
end

if ~isfield(options,'SmoothSpan'),  options.SmoothSpan = 0; end
if ~isfield(options,'DetrendPoly'), options.DetrendPoly = -1; end


tvec = cast(tvec,'like',postSweep);
[unit,m] = abr.Tools.time_gauge(max(abs(tvec)));
% tvec = tvec * 1000; % s -> ms
tvec = tvec * m;


% mean trace
meanSweep = mean(postSweep,1); % mean

% optional post processing
if options.SmoothSpan > 0, meanSweep = movmean(meanSweep,options.SmoothSpan); end
% detrend
if options.DetrendPoly == 0
    meanSweep = meanSweep - mean(meanSweep);
elseif options.DetrendPoly > 0
    [p,~,mu] = polyfit(tvec,meanSweep,options.DetrendPoly);
    y = polyval(p,tvec,[],mu);
    meanSweep = meanSweep - y;
end


may = max(abs(meanSweep));
[unit,yscale] = abr.Tools.voltage_gauge(may);


h.meanLine.XData = tvec;
h.meanLine.YData = meanSweep * yscale; % V -> unit
h.axMean.Title.String = sprintf('%d / %d sweeps', ...
    size(postSweep,1),app.ABR.numSweeps);

% control y axis scaling
m = [0:0.01:0.09 0.1:.1:.4 .5:.25:.75 1:10];
may = may * yscale;
s = m(find(m>may,1,'first'));
if isempty(s), s = may; end
h.axMean.YAxis.Limits = [-1 1] * s;
h.axMean.XAxis.Limits = tvec([1 end]);
h.axMean.YAxis.TickLabelFormat = sprintf('%%3.2f %s',unit);
h.axMean.YAxis.TickValues = linspace(-s,s,5);

% most recent trace
n = min([size(postSweep,1)-1 16]);
may = max(abs(postSweep(end-n:end,:)),[],'all');
[unit,yscale] = abr.Tools.voltage_gauge(may);
may = may * yscale;

h.recentLine.XData = tvec;
h.recentLine.YData = postSweep(end,:) * yscale; % V -> unit

s = m(find(m>may,1,'first'));
if isempty(s), s = may; end
h.axRecent.YAxis.Limits = [-1 1] * s;
h.axRecent.XAxis.Limits = h.axMean.XAxis.Limits;
h.axRecent.YAxis.TickLabelFormat = sprintf('%%3.2f %s',unit);
h.axRecent.YAxis.TickValues = linspace(-s,s,5);

h.corrBar.YData = R;

m = .5:.25:1;
m = m(find(m>max(R),1,'first'));
if ~isempty(m)
    h.axCorr.YAxis.Limits = [0 m];
end
h.axCorr.Title.String = sprintf('F_s_p = %.2f',Fsp(postSweep));



function h = setup(app)
vprintf(3,'Setting up abr_live_plot')
f = findobj('type','figure','-and','name','MABR Live Plot');

if isempty(f)
    p = app.ControlPanelUIFigure.Position;
    pos = [p(1)+p(3)+20 p(2)+p(4)-280 600 250];
    pos = getpref('ABRControlPanel','abr_live_plot_fig_pos',pos);
    f = figure('name','MABR Live Plot','color','w','NumberTitle','off', ...
        'Position',pos, ...
        'CloseRequestFcn','setpref(''ABRControlPanel'',''abr_live_plot_fig_pos'',get(gcf,''Position'')); delete(gcf);', ...
        'tag','MABR_FIG');
end

clf(f);
movegui(f);

axRecent = subplot(1,3,[1 2],'parent',f);
axMean   = axes(f,'position',axRecent.Position,'Color','none');
axCorr   = subplot(1,3,3,'parent',f);
axCorr.Position(1) = 0.75;
axCorr.Position(3) = 0.15;
axCorr.YAxis.TickLabelFormat = '%2.1f';

grid(axMean,'on');
box(axMean,'on');

axMean.XAxis.Label.String = 'time (ms)';
axMean.YAxis.Label.String = '';


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
