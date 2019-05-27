classdef ACQSTATE < int8
    
    enumeration
        INIT        (-2)
        ERROR       (-1)
        IDLE        (0)
        ACQUIRE     (1)
        CANCELLED   (2)
        PAUSED      (3)
        COMPLETED   (4)
    end
    
end