function timer_Runtime(T,event,app)

app.check_rec_status;

% extract sweeps relative to timing signal
[preSweep,postSweep,sweepOnsets] = app.Runtime.extract_sweeps(app.ABR.adcWindowTVec);

if isnan(postSweep(1)), return; end

app.ABR.ADC.SweepOnsets = sweepOnsets;

% update signal amplitude by InputAmpGain
A = app.Config.Parameters.InputAmpGain;
vprintf(4,'Making input gain adjustment: %g',A)
preSweep  = preSweep ./ A;
postSweep = postSweep ./ A;


% do online analysis
vprintf(4,'Calling live_analysis')
R = app.live_analysis(preSweep,postSweep);

if isnan(R), return; end

% update plots
app.abr_live_plot(postSweep,app.ABR.adcWindowTVec,R);

% sweep analysis
vprintf(4,'Sweep summary_analysis')
for i = 1:size(app.ABR.analysisSettings,2)
    R = app.summary_analysis(postSweep,app.ABR.analysisSettings{1,i},app.ABR.analysisSettings{2,i});
end

% update GUI
app.ControlSweepCountGauge.Value = app.ABR.sweepCount;

drawnow limitrate


