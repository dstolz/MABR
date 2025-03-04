function timer_runtime(T,event,obj)

if obj.isBackground
    
    if ~obj.FgIsRunning % shutdown if foreground is gone
        vprintf(0,'Foreground process disappeared!  Goodbye!')
        seppuku;
    end
    
    if obj.lastReceivedCmd == obj.CommandToBg, return; end
    obj.lastReceivedCmd = abr.Cmd(obj.CommandToBg);
    
    vprintf(1,'Background Received %s command',obj.CommandToBg)

    switch obj.CommandToBg
        case abr.Cmd.Undef
        case abr.Cmd.Idle
            obj.BackgroundState = abr.stateAcq.IDLE;
            
        case abr.Cmd.Prep
            obj.prepare_block_bg; % sets up audioFileReader and audioPlayerRecorder
            obj.BackgroundState = abr.stateAcq.READY;
            
        case abr.Cmd.Run
            obj.BackgroundState = abr.stateAcq.ACQUIRE;
            obj.acquire_block; % runs playback/acquisition
            obj.BackgroundState = abr.stateAcq.COMPLETED;
            obj.CommandToFg = abr.Cmd.Completed;
            
        case abr.Cmd.Stop
            % nothing to do here; stop is received in acquire_block
            
        case abr.Cmd.Kill
            obj.BackgroundState = abr.stateAcq.KILLED;
            seppuku;
            
        case abr.Cmd.Test
            obj.Universal.MODE = abr.Cmd.Test;
    end
    
    
else
    if obj.lastReceivedCmd == obj.CommandToFg, return; end
    obj.lastReceivedCmd = obj.CommandToFg;
    
    vprintf(1,'Foreground Received %s command',obj.CommandToFg)

    switch obj.CommandToFg
        case abr.Cmd.Idle
        case abr.Cmd.Prep
        case abr.Cmd.Run
        case abr.Cmd.Stop
    end
end

