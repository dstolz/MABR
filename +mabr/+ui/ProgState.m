classdef ProgState < int8
% mabr.ui.ProgState  Foreground program-flow state for the AcqController.
%
%   A single explicit state object that replaces the legacy abr.stateProgram
%   global-driven StateMachine. Transitions are driven by engine events and
%   user actions (event-driven), not polled from shared memory.
%
%   Idle          nothing running; waiting for the user to start
%   PrepBlock     rendering + arming the current block on the worker
%   Acquire       streaming/recording the current block
%   BlockComplete current block finished; finalize + save
%   AdvanceBlock  choosing the next block in the schedule
%   SchedComplete the whole schedule finished
%   Error         an error occurred

    enumeration
        Idle          (0)
        PrepBlock     (1)
        Acquire       (2)
        BlockComplete (3)
        AdvanceBlock  (4)
        SchedComplete (5)
        Error         (-1)
    end
end
