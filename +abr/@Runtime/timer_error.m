function timer_error(T,event,obj)
% wtf
errorString = sprintf('%s\n%s',event.Data.messageID,event.Data.message);
if obj.isBackground
    obj.mapCom.Data.BackgroundState = int8(abr.ACQSTATE.ERROR);
    obj.update_infoData('lastError_Bg',errorString);
    obj.mapCom.Data.CommandToFg = int8(abr.CMD.Error);
else
    obj.mapCom.Data.Foreground = int8(abr.ACQSTATE.ERROR);
    obj.update_infoData('lastError_Fg',errorString);
    obj.mapCom.Data.CommandToBg = int8(abr.CMD.Error);
end

seppuku