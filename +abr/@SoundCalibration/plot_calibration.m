function obj = plot_calibration(obj,phase)
    if nargin < 2 || isempty(phase), phase = 2; end

    n = sprintf('Calibration [%s]',datestr(obj.Timestamp,'dd-mmm-yyyy HH:MM PM'));

    obj.FigCalibration = findobj('type','figure','-and','name',n);
    if isempty(obj.FigCalibration)
        obj.FigCalibration = figure('name',n,'IntegerHandle','off', ...
            'Color','w','Position',[300 60 860 590]);
        figure(obj.FigCalibration);

        % Sound level plot
        obj.axSL = subplot(3,2,[1 2],'Parent',obj.FigCalibration,'Units','pixels');
        obj.axSL.XAxis.Label.String = obj.CalibratedParameter;
        obj.axSL.YAxis.Label.String = 'Sound Level (dB SPL)';
        grid(obj.axSL,'on');
        
        % time domain plot
        obj.axTD = subplot(3,2,[3 5],'Parent',obj.FigCalibration);
        obj.axTD.XAxis.TickLabelFormat = '%.1f';
        obj.axTD.YAxis.TickLabelFormat = '%.1f';
        obj.axTD.ZAxis.TickLabelFormat = '%.1f';
        obj.axTD.XAxis.Label.String = 'time (ms)';
        obj.axTD.YAxis.Label.String = obj.CalibratedParameter;
        obj.axTD.ZAxis.Label.String = 'amplitude (mV)';
        obj.axTD.YAxis.Exponent = 0;
        box(obj.axTD,'on');
        grid(obj.axTD,'on');
        view(obj.axTD,3);
        
        % freq domain plot
        obj.axFD = subplot(3,2,[4 6],'Parent',obj.FigCalibration);
        box(obj.axFD,'on');
        grid(obj.axFD,'on');
        axis(obj.axFD,'tight');
        obj.axFD.XAxis.Label.String = 'frequency (kHz)';
        obj.axFD.YAxis.Label.String = 'magnitude (dB)';
    end
    
    H = obj.axSL.UserData;
    
    if isempty(H) || length(H.tdlh) ~= obj.signalCount
        n = obj.signalCount;
        c = hsv(n);

        m = nan(1,n);
        
        H.sh   = scatter(m,m,75,'filled','parent',obj.axSL, ...
            'MarkerEdgeColor','flat','CData',c);
        H.mlh  = line(obj.axSL,nan(1,2),nan(1,2),'color',[0 0 0],'linewidth',4);
        H.p1lh = line(obj.axSL,m,m,'color',[0 0 0]);
        H.p2lh = line(obj.axSL,m,m,'color',[0 0 0]);
        uistack(H.sh,'top');
        

        for i = 1:obj.signalCount
            H.tdlh(i) = line(obj.axTD,nan,nan,'linestyle','-','marker','none','color',c(i,:));
            H.fdlh(i) = line(obj.axFD,nan,nan,'linestyle','-','marker','none','color',c(i,:));
        end        
        obj.axSL.UserData = H;
    end

    % Sound Level Plot
    x = obj.dataParams.(obj.CalibratedParameter) ./ obj.(obj.CalibratedParameter).ScalingFactor;
    y = obj.MeasuredSPL;
    
    x = x(:)';
    
    y(end+1:length(x)) = nan;
        
    H.mlh.XData = x([1 end]).*[0.9 1.1];
    H.mlh.YData = [1 1].* obj.NormDB;

    if phase == 1
        H.p1lh.XData = x;
        H.p1lh.YData = y;
        H.p1lh.LineWidth = 2;
        H.p1lh.Color = [0 0 0];
        
    elseif phase == 2
        H.p1lh.LineWidth = 0.5;
        H.p1lh.Color = [0.7 0.7 0.7];

        H.p2lh.XData = x;
        H.p2lh.YData = y;
        H.p2lh.LineWidth = 2;
        H.p2lh.Color = [0 0 0];
    end

    H.sh.XData = x;
    H.sh.YData = y;

    obj.axSL.XAxis.Limits = x([1 end]);
    obj.axSL.YLim = [0 max([y(:); obj.NormDB+40])];
    obj.axSL.XAxis.Label.String = obj.CalibratedParameter;
    obj.axSL.YAxis.Label.String = 'Sound Level (dB SPL)';
    grid(obj.axSL,'on');

    % Time Domain Plot
    x = obj.ADC.TimeVector .* 1000;
    y = obj.dataParams.(obj.CalibratedParameter);
    z = obj.ADC.SweepData;
    
    [~,y] = meshgrid(x,y);
    
    if ~isempty(z)
        n = size(z,2);
        
        [unit,mult] = abr.Universal.voltage_gauge(max(abs(z(:))));
        mz = z.*mult;
        
        % Time Domain Plot
        for i = 1:n
            H.tdlh(i).XData = x;
            H.tdlh(i).YData = y(i,:)./1000;
            H.tdlh(i).ZData = mz(:,i);
        end
        uistack(H.tdlh(n),'top');
        obj.axTD.YAxis.Label.String = sprintf('%s (kHz)',obj.CalibratedParameter);
        obj.axTD.ZAxis.Label.String = sprintf('amplitude (%s)',unit);
        obj.axTD.ZLim = [-1.1 1.1] * max(abs(mz(:)));
        
        % Frequency Domain Plot
        warning('off','MATLAB:colon:nonIntegerIndex');
        for i = 1:n
            Y = z(:,i);
            L = length(Y);
            w = window('hanning',L);
            Y = Y.*w;
            Y = fft(Y);
            P2 = abs(Y/L);
            M = P2(1:L/2+1);
            M(2:end-1) = 2*M(2:end-1);
            M = 20.*log10(M);
            f = obj.ADC.SampleRate*(0:(L/2))/L;
            H.fdlh(i).XData = f./1000;
            H.fdlh(i).YData = M;
        end
        warning('on','MATLAB:colon:nonIntegerIndex');
    end
    drawnow limitrate
end