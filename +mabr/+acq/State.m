classdef State < int8
% mabr.acq.State  Acquisition state reported from the worker back to the
% client (Engine) over the worker->client DataQueue.
%
%   Idle      - worker alive, no block prepared
%   Ready     - a block is prepared and armed, waiting for Run
%   Acquire   - actively streaming/recording the current block
%   Paused    - streaming suspended in place (device still open)
%   Completed - current block finished (end of stimulus or Stop)
%   Error     - worker hit an error; details follow on the error channel
%
% Replaces the legacy abr.stateAcq values that lived in the mabr_com.dat
% memmap. State now propagates as events, not polled shared memory.

    enumeration
        Idle      (0)
        Ready     (1)
        Acquire   (2)
        Paused    (3)
        Completed (4)
        Error     (5)
    end
end
