function timer_Error(T,event,app)

% app.Runtime.CommandToBg = abr.Cmd.Kill;
app.Runtime.CommandToBg = abr.Cmd.Stop;

app.stateProgram = abr.stateProgram.ACQ_ERROR;
app.StateMachine;