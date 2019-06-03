function timer_Runtime(T,event,app)


app.live_analysis;


% % make sure the background process is still running
% if ~app.Runtime.BgIsRunning
%     app.stateProgram = abr.stateProgram.ACQ_ERROR;
%     app.StateMachine;
%     stop(T);
% end


% check status of recording
switch app.Runtime.BackgroundState
    case {abr.stateAcq.COMPLETED, abr.stateAcq.ADVANCED}
        app.stateProgram = abr.stateProgram.BLOCK_COMPLETE;
        app.StateMachine;
        
        
    case abr.stateAcq.ERROR
        app.stateProgram = abr.stateProgram.ACQ_ERROR;
        app.StateMachine;
        stop(T);
end

