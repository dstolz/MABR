function timer_error(T,event,obj)
% wtf
errorString = sprintf('%s\n%s',event.Data.messageID,event.Data.message);
errorString = strrep(errorString,'\','\\');
vprintf(0,errorString);
if obj.isBackground
    obj.BackgroundState = abr.stateAcq.ERROR;
    obj.update_infoData('lastError_Bg',errorString);
    obj.CommandToFg = abr.Cmd.Error;
%     seppuku
else
    obj.Foreground = abr.stateAcq.ERROR;
    obj.update_infoData('lastError_Fg',errorString);
    obj.CommandToBg = abr.Cmd.Error;
end

