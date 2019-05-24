classdef PROGRAMSTATE < int8
    
    enumeration
        STARTUP             (0)
        PREFLIGHT           (1)
        REPADVANCE          (2)
        ACQUIRE             (3)
        REPCOMPLETE         (4)
        SCHEDCOMPLETE       (5)
        USERIDLE            (6)
        ACQUISITIONERROR    (7)
        ERROR               (-1)
    end
end
