classdef Cmd < int8
% mabr.acq.Cmd  Commands sent from the client (Engine) to the acquisition
% worker over the client->worker PollableDataQueue.
%
%   Prep   - configure the worker for a new block (payload carries the
%            pre-rendered 2-channel play matrix + block parameters)
%   Run    - begin streaming the prepared block from the start
%   Pause  - pause streaming in place, keeping the audio device open
%   Resume - continue a paused block (ignored unless a block is paused, so it
%            can never re-run an already-completed block)
%   Stop   - end the current block early and return to Ready
%   Kill   - release the device and terminate the worker loop
%
% Replaces the legacy abr.Cmd values that were multiplexed through the
% mabr_com.dat memmap; here they travel as messages, not shared memory.

    enumeration
        Prep   (1)
        Run    (2)
        Pause  (3)
        Stop   (4)
        Kill   (5)
        Resume (6)
    end
end
