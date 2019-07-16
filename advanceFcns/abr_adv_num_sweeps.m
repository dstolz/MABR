function nextIdx = abr_adv_num_sweeps(app,nReps)
if app.scheduleRunCount(app.scheduleIdx) >= nReps
    ind = app.scheduleRunCount(app.scheduleIdx+1:end) < nReps ...
        & app.Schedule.selectedData(app.scheduleIdx+1:end);
    if any(ind)
        nextIdx = app.scheduleIdx + find(ind,1,'first');
    else
        nextIdx = inf;
    end
else
    nextIdx = app.scheduleIdx;
end

