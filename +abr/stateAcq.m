classdef stateAcq < int8
    
    enumeration
        NONEXISTANT (-128)
        INIT        (-1)
        IDLE        (0)
        READY       (1)
        ACQUIRE     (2)
        CANCELLED   (3)
        PAUSED      (4)
        COMPLETED   (5)
        ADVANCED    (6)
        ERROR       (125)
        DELETED     (126)
        KILLED      (127)
    end
    
end