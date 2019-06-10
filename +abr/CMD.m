classdef Cmd < int8

    enumeration
        Kill        (-128)
        Undef       (-99)
        Error       (-1)
        Idle        (0)
        Prep        (1)
        Ready       (2)
        Run         (3)
        Pause       (4)
        Stop        (5)
        Completed   (6)
        NormalMode  (126)
        TestMode    (127)
    end

end