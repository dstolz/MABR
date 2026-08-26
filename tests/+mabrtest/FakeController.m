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
% Daniel Stolzberg (c) 2026

    properties
        Schedule
        Stimuli
        State (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
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
        end

        function setState(obj,state)
            obj.State = state;
            notify(obj,'StateChanged',mabr.ui.ProgStateEventData(state));
        end

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
