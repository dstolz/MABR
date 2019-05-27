function timer_runtime(T,event,obj)

if obj.isBackground
    
    if obj.lastReceivedCmd == obj.mapCom.Data.CommandToBg, return; end
    obj.lastReceivedCmd = abr.Cmd(obj.mapCom.Data.CommandToBg);
    
    switch obj.mapCom.Data.CommandToBg
        case abr.Cmd.Prep
            obj.prepare_block_bg; % sets up audioFileReader and audioPlayerRecorder
            obj.mapCom.Data.CommandToFg = int8(abr.Cmd.Ready);
            
        case abr.Cmd.Run
            obj.acquire_block; % runs playback/acquisition
            obj.mapCom.Data.CommandToFg = int8(abr.Cmd.Completed);
            
    end
    
    
else
    if obj.lastReceivedCmd == obj.mapCom.Data.CommandToFg, return; end
    obj.lastReceivedCmd = abr.Cmd(obj.mapCom.Data.CommandToFg);
    
    switch obj.mapCom.Data.CommandToFg
        case abr.Cmd.Idle
        case abr.Cmd.Prep
        case abr.Cmd.Run
        case abr.Cmd.Stop
    end
end
end
