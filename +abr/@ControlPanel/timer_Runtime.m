function timer_Runtime(T,event,app)



% check status of recording
bgState = abr.stateAcq(app.Runtime.mapCom.Data.BackgroundState);
switch bgState
    case abr.stateAcq.ACQUIRE
        return
    case abr.stateAcq.COMPLETED
        app.stateProgram = abr.stateProgram.REPCOMPLETE;
    case abr.stateAcq.ERROR
        app.stateProgram = abr.stateProgram.ACQUISITIONERROR;
end


% look for updated buffer index


% find stimulus onsets in timing signal



% organize incoming signal


% update plots