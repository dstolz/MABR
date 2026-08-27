classdef State < int8
% mabr.compute.State  What a compute worker reports it is doing, over the
% worker->client DataQueue (see mabr.compute.compute_loop).
%
%   Idle        alive, nothing configured or no run in progress
%   Ready       configured; waiting for a RunStart
%   Working     stepping the pipeline over a run in progress
%   Finalizing  running the finalization DSP (dsp role)
%   Error       the worker hit an error; details follow on the error channel
%
% Daniel Stolzberg (c) 2026

    enumeration
        Idle       (0)
        Ready      (1)
        Working    (2)
        Finalizing (3)
        Error      (4)
    end
end
