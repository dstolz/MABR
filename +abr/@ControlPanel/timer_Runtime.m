function timer_Runtime(T,event,app)


% extrace sweeps relative to timing signal
[preSweep,postSweep] = app.extract_sweeps;

if isnan(postSweep(1))
    app.check_rec_status;
    return
end

% do online analysis
R = app.live_analysis(preSweep,postSweep);

if isnan(R), return; end

% update plots
app.abr_live_plot(postSweep,app.ABR.adcWindowTVec,R);

% update GUI
app.ControlSweepCountGauge.Value = app.ABR.sweepCount;

drawnow limitrate




