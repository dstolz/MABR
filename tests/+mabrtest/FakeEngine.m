classdef FakeEngine < handle
% mabrtest.FakeEngine  Stand-in for mabr.acq.Engine's state, in tests.
%
%   Carries the one thing a viewer reads off the acquisition engine rather
%   than the controller -- its State, and the StateChanged event that reports
%   it with the same payload (mabr.acq.StateEventData). That is how a pause is
%   seen: mabr.ui.ProgState has no Paused, so a paused run is still Acquire to
%   the controller, and mabr.ui.ProgressMonitor listens here to tell the two
%   apart.
%
%   Held by mabrtest.FakeController as its Engine, as mabr.ui.AcqController
%   holds the real one.
%
% Daniel Stolzberg (c) 2026

    properties
        State (1,1) mabr.acq.State = mabr.acq.State.Idle
    end

    events
        StateChanged
    end

    methods
        function setState(obj,state)
            obj.State = state;
            notify(obj,'StateChanged',mabr.acq.StateEventData(state));
        end
    end
end
