function timer_runtime(T,event,obj)

if obj.isBackground
    
    if ~obj.FgIsRunning % shutdown if foreground is gone
        vprintf(0,'Foreground process disappeared!  Goodbye!')
        seppuku;
    end
    
    if obj.lastReceivedCmd == obj.CommandToBg, return; end
    obj.lastReceivedCmd = abr.Cmd(obj.CommandToBg);
    
    switch obj.CommandToBg
        case abr.Cmd.Idle
            vprintf(1,'Received Idle command')
            obj.BackgroundState = abr.stateAcq.IDLE;
            
        case abr.Cmd.Prep
            vprintf(1,'Received Prep command')
            obj.prepare_block_bg; % sets up audioFileReader and audioPlayerRecorder
            obj.BackgroundState = abr.stateAcq.READY;
            
        case abr.Cmd.Run
            vprintf(1,'Received Run command')
            obj.BackgroundState = abr.stateAcq.ACQUIRE;
            obj.acquire_block; % runs playback/acquisition
            obj.BackgroundState = abr.stateAcq.COMPLETED;
            obj.CommandToFg = abr.Cmd.Completed;
            
        case abr.Cmd.Stop
            vprintf(1,'Received Stop command')
            % nothing to do here
            
        case abr.Cmd.Kill
            vprintf(1,'Received Kill command')
            obj.BackgroundState = abr.stateAcq.KILLED;
            seppuku;
    end
    
    
else
    if obj.lastReceivedCmd == obj.CommandToFg, return; end
    obj.lastReceivedCmd = obj.mapCom.Data.CommandToFg;
    
    switch obj.CommandToFg
        case abr.Cmd.Idle
        case abr.Cmd.Prep
        case abr.Cmd.Run
        case abr.Cmd.Stop
    end
end

