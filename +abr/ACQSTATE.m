classdef ACQSTATE < int8
    
    enumeration
        INIT        (-2)
        ERROR       (-1)
        IDLE        (0)
        ACQUIRE     (1)
        CANCELLED   (2)
        PAUSED      (3)
        ADVANCE     (4)
        REPEAT      (5)
        COMPLETED   (6)
        START       (7)
        STOP        (8)
    end
    
end