function timer_Error(T,event,app)

errStr = sprintf('%s: %s',event.Data.messageID,event.Data.message);
errStr = strrep(errStr,'\','\\');
vprintf(0,1,'Timer Error: %s',errStr)
app.Runtime.CommandToBg = abr.Cmd.Stop;

app.stateProgram = abr.stateProgram.ACQ_ERROR;
app.StateMachine;