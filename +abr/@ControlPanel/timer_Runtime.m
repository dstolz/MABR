function timer_Runtime(T,event,app)

app.check_rec_status;

% extract sweeps relative to timing signal
[preSweep,postSweep,sweepCount] = app.Runtime.extract_sweeps(app.ABR.adcWindowTVec);

if isnan(postSweep(1))
    return
end

% update signal amplitude by InputAmpGain
A = app.Config.Parameters.InputAmpGain;
preSweep  = preSweep ./ A;
postSweep = postSweep ./ A;


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
app.ControlSweepCountGauge.Value = sweepCount;

drawnow limitrate


