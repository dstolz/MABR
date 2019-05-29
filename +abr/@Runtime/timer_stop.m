function timer_stop(T,event,obj)

if obj.isBackground
    obj.mapCom.Data.BackgroundState = int8(abr.stateAcq.IDLE);
else
    obj.mapCom.Data.ForegroundState = int8(abr.stateAcq.IDLE);
end