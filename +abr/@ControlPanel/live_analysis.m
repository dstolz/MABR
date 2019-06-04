function R = live_analysis(app,preSweep,postSweep)

R = nan;

if isnan(preSweep(1)) || isnan(postSweep(1)), return; end

if app.ABR.sweepCount > 1 
    R = app.partition_corr(preSweep,postSweep);
else
    R = [0 0 0];
end
