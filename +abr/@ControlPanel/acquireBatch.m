function e = abrAcquireBatch(obj,ax,varargin)
% e = abrAcquireBatch(obj,ax,'Name','Value')
% 
% This function handles the acquisition of a batch of sweeps as well as
% updating live data plot.
% 
% Daniel Stolzberg, PhD (c) 2019

e = 0;

options.showTimingStats = false;
options.showStimulusPlot = true;
for i = 1:2:length(varargin)
    options.(lower(varargin{i})) = varargin{i+1};
end


% axis lines
line(ax,'xdata',obj.adcBufferTimeVector([1 end])*1000,'ydata',[0 0], ...
    'color',[0.5 0.5 0.5],'linewidth',1);
line(ax,'xdata',[0 0],'ydata',[-100 100], ...
    'color',[0.5 0.5 0.5],'linewidth',1);

if options.showStimulusPlot
    hs = line(ax,'xdata',obj.dacBufferTimeVector*1000, ...
        'ydata',obj.dacBuffer,'linewidth',1, ...
        'color',[0.2 1 0.2]);
end

hl = line(ax,'xdata',obj.adcBufferTimeVector*1000, ...
             'ydata',nan(obj.adcBufferLength,1), ...
             'linewidth',3,'color',[0.2 0.2 1]);

ax.XLim = obj.adcBufferTimeVector([1 end])*1000+[0; -1];

drawnow

obj.prepareSweep;
tic
for i = 1:obj.numSweeps
    obj.triggerSweep;
    if mod(i,24) == 0
        hl.YData = mean(obj.adcDataFiltered(:,1:i),2)*1000;
        ax.YAxis.Limits = [-1.1 1.1] * max(abs(hl.YData));
        ax.Title.String = sprintf('Sweep %d/%d',i,obj.numSweeps);
        
        if options.showStimulusPlot
            hs.YData = obj.dacBuffer*ax.YAxis.Limits(2);
        end
        
        drawnow limitrate
    end
end
toc

%
d = diff(obj.sweepOnsets(2:end)); % first sweep time is not true

fprintf('1/sweepRate\t%0.9f\nmedian\t\t%0.9f\nmean\t\t%0.9f\nstd\t\t\t%0.9f\n', ...
    1/obj.sweepRate,median(d),mean(d),std(d))

fprintf('max\t\t\t%0.9f\nmin\t\t\t%0.9f\nrange\t\t%0.9f\n',max(d),min(d),max(d)-min(d))

e = 1;
