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

    methods (Static)
        function [rgb,txt] = appearance(state)
            % Lamp colour and label for a state, in ONE place: the main window
            % and mabr.ui.ProgressMonitor both show the same lamp, and two
            % copies of this mapping would eventually disagree about what
            % "Acquiring" looks like.
            switch state
                case mabr.ui.ProgState.Idle,          rgb = [0.6 0.6 0.6];  txt = 'Idle';
                case mabr.ui.ProgState.PrepBlock,     rgb = [0.95 0.8 0.2]; txt = 'Preparing block…';
                case mabr.ui.ProgState.Acquire,       rgb = [0.2 0.8 0.2];  txt = 'Acquiring';
                case mabr.ui.ProgState.BlockComplete, rgb = [0.2 0.5 0.9];  txt = 'Block complete';
                case mabr.ui.ProgState.AdvanceBlock,  rgb = [0.95 0.8 0.2]; txt = 'Advancing…';
                case mabr.ui.ProgState.SchedComplete, rgb = [0.2 0.5 0.9];  txt = 'Schedule complete';
                case mabr.ui.ProgState.Error,         rgb = [0.9 0.2 0.2];  txt = 'Error';
                otherwise,                            rgb = [0.6 0.6 0.6];  txt = char(state);
            end
        end

        function tf = isTerminal(state)
            % States a schedule RESTS in, rather than passes through.
            tf = any(state == [mabr.ui.ProgState.Idle, ...
                               mabr.ui.ProgState.SchedComplete, ...
                               mabr.ui.ProgState.Error]);
        end
    end
end
