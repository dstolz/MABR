function live_analysis(app)

[preSweep,postSweep] = app.extract_sweeps;
if isnan(preSweep(1)) || isnan(postSweep(1)), return; end

if app.ABR.sweepCount > 1    
    % TESTING ***********
    TEST = abs(postSweep);
    % TESTING ***********
    
    R = app.partition_corr(preSweep,TEST);

else
    R = [0 0 0];
end

% update plots
app.abr_live_plot(postSweep,app.ABR.adcWindowTVec,R);

% update GUI
app.ControlSweepCountGauge.Value = length(app.ABR.ADC.SweepOnsets);

drawnow limitrate
