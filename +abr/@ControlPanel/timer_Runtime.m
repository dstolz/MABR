function timer_Runtime(T,event,app)

persistent lastBufferIdx 

if isempty(lastBufferIdx), lastBufferIdx = [0 0]; end

C = app.Runtime.mapCom;

% look for updated buffer index
if isequal(C.Data.BufferIndex,lastBufferIdx), return; end

lastBufferIdx = C.Data.BufferIndex;



% copy recent data to ADC buffer
app.ABR.ADC.Data(


% find stimulus onsets in timing signal
samps = app.ABR.timing_samples;


% organize incoming signal


% update plots





% check status of recording
bgState = abr.stateAcq(app.Runtime.mapCom.Data.BackgroundState);
switch bgState
    case abr.stateAcq.ACQUIRE
        
        
    case abr.stateAcq.COMPLETED
        app.stateProgram = abr.stateProgram.REPCOMPLETE;
        stop(T);
        
    case abr.stateAcq.ERROR
        app.stateProgram = abr.stateProgram.ACQUISITIONERROR;
        stop(T);
end
