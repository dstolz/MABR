classdef (ConstructOnLoad) ProgStateEventData < event.EventData
% mabr.ui.ProgStateEventData  Payload for AcqController events.
%
%   Carries the program State and an optional Info payload (e.g. live metrics
%   for MetricsUpdated, or a struct with a .file field for BlockSaved).

    properties
        State (1,1) mabr.ui.ProgState = mabr.ui.ProgState.Idle
        Info  (1,1) struct = struct()
    end

    methods
        function obj = ProgStateEventData(state,info)
            if nargin >= 1 && ~isempty(state), obj.State = state; end
            if nargin >= 2 && ~isempty(info),  obj.Info  = info;  end
        end
    end
end
