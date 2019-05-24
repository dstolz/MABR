function ABR = playrec(ABR,app,livePlotAx,liveAnalysisAx,varargin)
% playrec(ABR,app,livePlotAx,liveAnalysisAx,'Name','Value')
%
% This function handles the acquisition of a batch of sweeps as well as
% updating live data plot.
%
% Daniel Stolzberg, PhD (c) 2019

global ACQSTATE

options.showtimingstats = false;
options.showstimulusplot = false;
for i = 1:2:length(varargin)
    options.(lower(varargin{i})) = varargin{i+1};
end

ABR = ABR.prepareSweep;




% PAD dacSweep WITH SILENCE TO GENERATE CORRECT INTER-dacSweep-INTERVAL
frsz = ABR.DAC.FrameSize; % temporarily set FrameSize to 1 so it doesn't get padded
ABR.DAC.FrameSize = 1;
n = ceil(ABR.DAC.SampleRate ./ ABR.sweepRate - ABR.DAC.N);
silence  = zeros(n,1,'like',ABR.DAC.Data);
dacSweep = [ABR.DAC.Data; silence];


if ABR.altPolarity
    % alternate stimulus polarity for every presentation
    n = ABR.numSweeps/2;
    data = repmat([dacSweep; -dacSweep],n,1);
    if mod(ABR.numSweeps,2) == 1
        ABR.DAC.Data = data(1:end-length(dacSweep));
    else
        ABR.DAC.Data = data;
    end
else
    ABR.DAC.Data = repmat(dacSweep,ABR.numSweeps,1);
end

ABR.DAC.FrameSize = frsz;

ABR.DAC.SweepLength = length(dacSweep);
ABR.DAC.SweepOnsets = 1:ABR.DAC.SweepLength:ABR.DAC.N;


% Initialize ADC Buffer
decfrsz = frsz/ABR.adcDecimationFactor;
decIdx  = 1:ABR.adcDecimationFactor:frsz;

% CREATE INDEXES MATCHING THE DECIMATED ADC BUFFER
dacSweepIdx = repmat(1:ABR.numSweeps,length(dacSweep),1);
dacSweepIdx = dacSweepIdx(:);
adcSweepIdx = dacSweepIdx(1:ABR.adcDecimationFactor:end);

ABR.ADC.preallocate(decfrsz*length(adcSweepIdx));
ABR.ADC.SweepOnsets = [1; find(diff(adcSweepIdx))];
% ABR.ADC.SweepLength = min(arrayfun(@(a) sum(adcSweepIdx==a),unique(adcSweepIdx)));
ABR.ADC.SweepLength = length(ABR.adcWindowSamps);

[hl,hs] = setup_plot;

ACQSTATE = abr.ACQSTATE.ACQUIRE;

updateTime = hat+1;


k = 1;
m = 1:frsz:ABR.DAC.N;
midx = (0:frsz-1)'+m;


ABR = ABR.initDACtiming;

OUTPUT = [ABR.DAC.Data ABR.DACtiming.Data];

% timing = zeros(length(m),1);
for i = 1:length(m)
        
    % look for change in acquisition state
    while ACQSTATE == abr.ACQSTATE.PAUSED && ~isempty(app)
        app.AcquisitionStateLamp.Color = [1 1 .3];
        pause(0.25);
        app.AcquisitionStateLamp.Color = [.7 .7 0];
        pause(0.25);
    end
    
    if ACQSTATE ~= abr.ACQSTATE.ACQUIRE, return; end    
   
    
    % playback/record audio data
%     timing(i) = hat;
    [INPUT,nu,no] = ABR.APR(OUTPUT(midx(:,i),:));
    
    if nu, fprintf('Number of underruns = %d\n',nu); end
    if no, fprintf('Number of overruns  = %d\n',no); end
    
    
    INPUTsignal = INPUT(:,1);
    
    % transfer INPUT timing to corresponding buffer
    ABR.ADCtiming.Data(k:k+frsz-1) = INPUT(:,2);

    
    % downsample acquired signal 
    % > NOTE NO EXPLICIT ANTI-ALIASING FILTER FOR ONLINE PERFORMANCE
    INPUTsignal = INPUTsignal(decIdx,1);
    
    
    % optional digital filter of downsampled data; try to avoid
    % onset/offset transients by extending first and last samples, acausal
    % filtering, and then trimming to INPUTsignal signal
    if ABR.adcUseBPFilter
        INPUTsignal = filtfilt(ABR.adcFilterDesign, ...
            [repmat(INPUTsignal(1),decfrsz,1); INPUTsignal; repmat(INPUTsignal(end),decfrsz,1)]);
        INPUTsignal = INPUTsignal(decfrsz+1:decfrsz*2);
    end
    if ABR.adcUseNotchFilter
        INPUTsignal = filtfilt(ABR.adcNotchFilterDesign, ...
            [repmat(INPUTsignal(1),decfrsz,1); INPUTsignal; repmat(INPUTsignal(end),decfrsz,1)]);
        INPUTsignal = INPUTsignal(decfrsz+1:decfrsz*2);
    end
    
        
    % copy INPUTsignal to ABR.ADC.Data buffer in the correct position
    adcIdx = k:k+frsz/ABR.adcDecimationFactor-1;
    k = adcIdx(end)+1;
    ABR.ADC.Data(adcIdx) = INPUTsignal;
    
    
    % update plot only every 100 ms or so
    if hat >= updateTime + 0.1 % seconds
        update_plot(hl,hs);
        updateTime = hat;
        app.ControlSweepCountGauge.Value = dacSweepIdx(m(i));
        drawnow limitrate
    end
    
end

ACQSTATE = abr.ACQSTATE.IDLE;

update_plot(hl,hs);



if options.showtimingstats
    display_timing_results;
end




% local functions -----------------------------------------------------
    
    function [hl,hs] = setup_plot
        hs = [];
        
        cla(livePlotAx);
        
        % axis lines
        line(livePlotAx,'xdata',ABR.ADC.TimeVector([1 end])*1000,'ydata',[0 0], ...
            'color',[0.5 0.5 0.5],'linewidth',1);
        line(livePlotAx,'xdata',[0 0],'ydata',[-100 100], ...
            'color',[0.5 0.5 0.5],'linewidth',1);
        
        if options.showstimulusplot
            hs = line(livePlotAx,'xdata',ABR.dacBufferTimeVector*1000, ...
                'ydata',ABR.DAC.Data./max(abs(ABR.DAC.Data)), ...
                'linewidth',2, ...
                'color',[0.2 0.8 0.2 0.5]);
        end
        
        hl = line(livePlotAx,'xdata',ABR.ADC.TimeVector*1000, ...
            'ydata',nan(ABR.ADC.SweepLength,1), ...
            'linewidth',3,'color',[0.2 0.2 1]);
        
        livePlotAx.XLim = ABR.adcWindow*1000; % s -> ms
        
        drawnow
    end

    function update_plot(hl,hs)
        sweepSamps = ABR.timing_samples;
        
        if isempty(sweepSamps)
            if i > 10
                fprintf(2,'UNABLE TO LOCK ON LOOP-BACK SIGNAL!\n')
            end
            y = ABR.ADC.SweepMean; 
        else
%             y = ABR.ADC.Data;
            % TESTING ----
            y = ABR.ADCtiming.Data;
            y = y(1:16:length(y));
            % ------------
            
            y = mean(y(sweepSamps));
        end
        
        hl.YData = y * 1000; % V -> mV
        
        yl = max(abs(y));
        yl = ceil(yl.*10);
        yl = yl-mod(yl,10)+10;
        yl = yl./10;
        
        if ~isempty(hs)
            hs.YData = yl.*ABR.DAC.SweepData(:,1)./max(abs(ABR.DAC.SweepData(:,1)));
        end
        
        if isnan(yl), yl = 1; end
        
        livePlotAx.YAxis.Limits = [-1 1] * yl;
        livePlotAx.Title.String = sprintf('Sweep %d/%d',dacSweepIdx(m(i)),ABR.numSweeps);
        
        
    end

    function display_timing_results
        
        d = diff(timing(2:end)); % first dacSweep time is not true
        
        intendedRate = 1/ABR.sweepRate;
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
        tax.XAxis.Label.String = 'dacSweep #';
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
        
        
        fprintf(['1/sweepRate\t%0.9f sec\nd(t) ', ...
            'median\t\t%9.3f us\nd(t) ', ...
            'mean\t\t%9.3f us\nd(t) std\t\t%9.3f us\n'], ...
            intendedRate,mn,md,std(d,'omitnan'))
        fprintf('d(t) max\t\t%9.3f us\nd(t) min\t\t%9.3f us\nd(t) range\t\t%9.3f us\n', ...
            max(d),min(d),max(d)-min(d))
    end
end





