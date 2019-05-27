function timer_runtime(T,event,obj)

if obj.isBackground
    
    if obj.lastReceivedCmd == obj.mapCom.Data.CommandToBg, return; end
    obj.lastReceivedCmd = abr.CMD(obj.mapCom.Data.CommandToBg);
    
    switch obj.mapCom.Data.CommandToBg
        case abr.CMD.Prep
            obj.prepare_block_bg; % sets up audioFileReader and audioPlayerRecorder
            obj.mapCom.Data.CommandToFg = int8(abr.CMD.Ready);
            
        case abr.CMD.Run
            obj.acquire_block; % runs playback/acquisition
            obj.mapCom.Data.CommandToFg = int8(abr.CMD.Completed);
            
    end
    
    
else
    if obj.lastReceivedCmd == obj.mapCom.Data.CommandToFg, return; end
    obj.lastReceivedCmd = abr.CMD(obj.mapCom.Data.CommandToFg);
    
    switch obj.mapCom.Data.CommandToFg
        case abr.CMD.Idle
        case abr.CMD.Prep
        case abr.CMD.Run
        case abr.CMD.Stop
    end
end
end
