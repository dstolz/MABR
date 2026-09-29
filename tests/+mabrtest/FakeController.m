classdef FakeController < handle
% mabrtest.FakeController  Stand-in for mabr.ui.AcqController in tests.
%
%   Carries the three properties a viewer reads (Schedule, Stimuli, State) and
%   raises the same events with the same payloads, so anything that follows a
%   controller -- mabr.ui.ProgressMonitor, mabr.ui.TraceOrganizer -- can be
%   verified without a parallel pool, an acquisition engine, or a rig.
%
%   The schedule handed in is a REAL mabr.stim.Schedule, so the progress a
%   viewer computes from it is computed from the same plan an acquisition
%   would walk.
%
%   Engine is a mabrtest.FakeEngine, standing where AcqController's
%   mabr.acq.Engine does: pauseAcq/resumeAcq change ITS state, exactly as the
%   real ones do, and leave the controller's own State alone -- which is the
%   whole of why a viewer that wants to show a pause has to look there.
%
% Daniel Stolzberg (c) 2026

    properties
        Schedule
        Stimuli
        State (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        Engine
    end

    events
        StateChanged
        MetricsUpdated
        BlockReady
        BlockSaved
        ScheduleComplete
    end

    methods
        function obj = FakeController(schedule,stimuli)
            if nargin >= 1, obj.Schedule = schedule; end
            if nargin >= 2
                obj.Stimuli = stimuli;
            elseif nargin >= 1 && ~isempty(schedule)
                obj.Stimuli = schedule.Set;
            end
            obj.Engine = mabrtest.FakeEngine();
        end

        function setState(obj,state)
            obj.State = state;
            notify(obj,'StateChanged',mabr.ui.ProgStateEventData(state));
        end

        % As mabr.ui.AcqController's: the worker reports Paused, then Acquire
        % again on resume, and the program state does not move at all.
        function pauseAcq(obj),  obj.Engine.setState(mabr.acq.State.Paused);  end
        function resumeAcq(obj), obj.Engine.setState(mabr.acq.State.Acquire); end

        function metrics(obj,numSweeps,numArtifacts)
            % The live tick's payload, exactly as AcqController.live_tick_body
            % builds it.
            if nargin < 3, numArtifacts = 0; end
            info = struct('numSweeps',numSweeps,'numArtifacts',numArtifacts, ...
                          'numClean',numSweeps-numArtifacts,'corr',0);
            notify(obj,'MetricsUpdated',mabr.ui.ProgStateEventData(obj.State,info));
        end

        function emit(obj,block)
            % One finalized block, as mabr.ui.AcqController announces it.
            notify(obj,'BlockReady',mabr.ui.ProgStateEventData( ...
                mabr.ui.ProgState.BlockComplete,struct('block',block)));
        end

        function complete(obj)
            obj.setState(mabr.ui.ProgState.SchedComplete);
            notify(obj,'ScheduleComplete');
        end
    end
end
