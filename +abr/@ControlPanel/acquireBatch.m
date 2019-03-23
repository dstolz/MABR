function acquireBatch(obj,ax,varargin)
% acquireBatch(obj,ax,'Name','Value')
%
% This function handles the acquisition of a batch of sweeps as well as
% updating live data plot.
%
% Daniel Stolzberg, PhD (c) 2019

global ACQSTATE

options.showtimingstats = false;
options.showstimulusplot = true;
for i = 1:2:length(varargin)
    options.(lower(varargin{i})) = varargin{i+1};
end

[hl,hs] = setup_plot;

obj.ABR.prepareSweep;

ACQSTATE = 'ACQUIRE';

updateTime = hat;
for i = 1:obj.ABR.numSweeps
    
    while isequal(ACQSTATE,'PAUSED')
        obj.ControlAcquireLamp.Color = [1 1 .3];
        pause(0.25);
        obj.ControlAcquireLamp.Color = [.7 .7 0];
        pause(0.25);
    end
    
    if ~isequal(ACQSTATE,'ACQUIRE'), break; end
    
    obj.ABR.triggerSweep;
    
    if hat >= updateTime + 1
        updateTime = hat;
        update_plot(hl,hs);
    end
    
end
update_plot(hl,hs);



if options.showtimingstats
    display_timing_results;
end


    function [hl,hs] = setup_plot
        cla(ax);
        % axis lines
        line(ax,'xdata',obj.ABR.adcBufferTimeVector([1 end])*1000,'ydata',[0 0], ...
            'color',[0.5 0.5 0.5],'linewidth',1);
        line(ax,'xdata',[0 0],'ydata',[-100 100], ...
            'color',[0.5 0.5 0.5],'linewidth',1);
        
        if options.showstimulusplot
            hs = line(ax,'xdata',obj.ABR.dacBufferTimeVector*1000, ...
                'ydata',obj.ABR.dacBuffer,'linewidth',1, ...
                'color',[0.2 1 0.2]);
        end
        
        hl = line(ax,'xdata',obj.ABR.adcBufferTimeVector*1000, ...
            'ydata',nan(obj.ABR.adcBufferLength,1), ...
            'linewidth',3,'color',[0.2 0.2 1]);
        
        ax.XLim = obj.ABR.adcBufferTimeVector([1 end])*1000+[0; -1];
        
        drawnow
    end

    function update_plot(hl,hs)
        hl.YData = mean(obj.ABR.adcDataFiltered(:,1:i),2)*1000;
        yl = max(abs(hl.YData)); 
        if yl == 0 || isnan(yl), yl = 0.001; end
        ax.YAxis.Limits = [-1.1 1.1] * yl;
        ax.Title.String = sprintf('Sweep %d/%d',i,obj.ABR.numSweeps);
        
        if options.showstimulusplot
            hs.YData = obj.ABR.dacBuffer*ax.YAxis.Limits(2);
        end
        
        obj.ControlSweepCountGauge.Value = i;
        
        drawnow limitrate
    end

    function display_timing_results
        
        d = diff(obj.ABR.sweepOnsets(2:end)); % first sweep time is not true
        
        intendedRate = 1/obj.ABR.sweepRate;
        d = d - intendedRate;
        d = d * 1e6; % sec -> us
        
        md = mean(d,'omitnan');
        mn = median(d,'omitnan');
        f = findobj('type','figure','-and','name','acquireBatch_TimingStats');
        if isempty(f)
            f = figure('name','acquireBatch_TimingStats','color','w');
        end
        figure(f);
        clf(f);
        
        tax = subplot(1,4,[1 3]);
        hold(tax,'on');
        plot(tax,1:length(d),d,'o','color',[0.3 0.3 0.3],'markerfacecolor',[0.3 0.3 0.3], ...
            'markersize',3);
        p = plot(tax, ...
            [1 length(d)],[1 1]*md,'-b', ...
            [1 length(d)],[1 1]*mn,'--r');
        
        set(p,'linewidth',2);
        hold(tax,'off');
        tax.Title.String = 'Timing Stats';
        tax.YAxis.Label.String = 'abs(\Deltat) \mus';
        tax.XAxis.Label.String = 'Sweep #';
        grid(tax,'on');
        box(tax,'on');
        axis(tax,'tight');
        
        legend(tax,p, ...
            sprintf('mean(abs(\\Deltat)   = %0.3f \\mus',md), ...
            sprintf('median(abs(\\Deltat) = %0.3f \\mus',mn), ...
            'Location','best');
        
        hax = subplot(1,4,4);
        
        histogram(hax,d,'Orientation','horizontal', ...
            'Normalization','count','BinMethod','sturges');
        hax.YAxis.Limits = tax.YAxis.Limits;
        
        hold(hax,'on');
        p = plot(hax, ...
            xlim(hax),[1 1]*md,'-b', ...
            xlim(hax),[1 1]*mn,'--r');
        set(p,'linewidth',2);
        grid(hax,'on');
        hax.XAxis.Label.String = 'count';
        hold(hax,'off');
        
        tax.FontSize = 10;
        hax.FontSize = 10;
        hax.Position([2 4]) = tax.Position([2 4]);
        
        
        fprintf('ABR.timingAdjustment = %g sec\n',obj.ABR.timingAdjustment)
        fprintf(['1/sweepRate\t%0.9f sec\nd(t) ', ...
            'median\t\t%9.3f us\nd(t) ', ...
            'mean\t\t%9.3f us\nd(t) std\t\t%9.3f us\n'], ...
            intendedRate,mn,md,std(d,'omitnan'))
        fprintf('d(t) max\t\t%9.3f us\nd(t) min\t\t%9.3f us\nd(t) range\t\t%9.3f us\n', ...
            max(d),min(d),max(d)-min(d))
    end
end