function timer_stop(T,event,obj)

if obj.isBackground
    obj.BackgroundState = abr.stateAcq.IDLE;
else
    obj.ForegroundState = abr.stateAcq.IDLE;
end