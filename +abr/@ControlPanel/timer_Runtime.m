function timer_Runtime(T,event,app)

% extract sweeps relative to timing signal
[preSweep,postSweep] = app.Runtime.extract_sweeps(app.ABR.adcWindowTVec);


% update signal amplitude by InputAmpGain
A = app.Config.Parameters.InputAmpGain;
preSweep  = preSweep ./ A;
postSweep = postSweep ./ A;

if isnan(postSweep(1))
    app.check_rec_status;
    return
end

% do online analysis
R = app.live_analysis(preSweep,postSweep);

if isnan(R), return; end

% update plots
app.abr_live_plot(postSweep,app.ABR.adcWindowTVec,R);

% sweep analysis
% for i = 1:length(app.summaryAnalysisType)
%     R = app.summary_analysis(postSweep,app.summaryAnalysisType{i},oapp.summaryAnalysisOptions{i});
% end

% update GUI
app.ControlSweepCountGauge.Value = app.ABR.sweepCount;

drawnow limitrate


