classdef stateAcq < int8
    
    enumeration
        DELETED     (-3)
        INIT        (-2)
        ERROR       (-1)
        IDLE        (0)
        READY       (1)
        ACQUIRE (2)
        CANCELLED   (3)
        PAUSED      (4)
        COMPLETED   (5)
        ADVANCED    (6)
        KILLED      (255)
    end
    
end