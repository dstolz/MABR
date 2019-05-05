classdef ACQSTATE < int8
    
    enumeration
        ERROR       (-1)
        IDLE        (0)
        ACQUIRE     (1)
        CANCELLED   (2)
        PAUSED      (3)
    end
    
end