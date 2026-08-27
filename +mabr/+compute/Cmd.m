classdef Cmd < int8
% mabr.compute.Cmd  Commands sent from the client (mabr.compute.ComputeEngine)
% to a compute worker (mabr.compute.compute_loop) over its PollableDataQueue.
%
%   One set for both worker roles; each ignores what it does not handle.
%
%   Configure       the DAC sample rate, the analysis window, and the filter
%                   and artifact policies (as their toStruct forms). Sent to
%                   BOTH workers, and re-sent whenever a policy changes, so
%                   every process agrees about what a sweep is
%   RunStart        a run is streaming: what its onsets belong to (RunId,
%                   StimIndex, Stimuli, Labels, Meta)
%   RunEnd          the run ended: stop stepping, drop its live conditions
%   Finalize        (dsp) run the finalization DSP over the ring buffer and
%                   reply with a 'finalized' message carrying the parts
%   AddCondition    (metrics) a finalized condition for the session table
%   ClearConditions (metrics) forget the session table (a new subject)
%   SetCustomMetric (metrics) a user-supplied metric function for one slot;
%                   function handles cannot live in a memory map, so they
%                   arrive this way while everything else about a job rides
%                   in mabr.compute.RequestBuffer
%   Kill            terminate the worker loop
%
% Shaped exactly like mabr.acq.Cmd, and for the same reason: control travels
% as messages, and only bulk data through shared memory.
%
% Daniel Stolzberg (c) 2026

    enumeration
        Configure       (1)
        RunStart        (2)
        RunEnd          (3)
        Finalize        (4)
        AddCondition    (5)
        ClearConditions (6)
        SetCustomMetric (7)
        Kill            (8)
    end
end
