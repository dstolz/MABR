classdef stateProgram < int8
    
    enumeration
        STARTUP             (0)
        PREP_BLOCK          (1)
        ADVANCE_BLOCK       (2)
        ACQUIRE       (3)
        BLOCK_COMPLETE      (4)
        SCHED_COMPLETE      (5)
        USER_IDLE           (6)
        ACQ_ERROR           (7)
        ERROR               (-1)
    end
end
