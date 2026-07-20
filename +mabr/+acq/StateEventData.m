classdef (ConstructOnLoad) StateEventData < event.EventData
% mabr.acq.StateEventData  Payload for mabr.acq.Engine state/error events.
%
%   Carries the new acquisition State (and, for errors, the identifier and
%   message) to listeners of the Engine's StateChanged / WorkerError events.

    properties
        State      (1,1) mabr.acq.State = mabr.acq.State.Idle
        Identifier (1,:) char
        Message    (1,:) char
    end

    methods
        function obj = StateEventData(state,identifier,message)
            if nargin >= 1 && ~isempty(state),      obj.State      = state;      end
            if nargin >= 2 && ~isempty(identifier), obj.Identifier = identifier; end
            if nargin >= 3 && ~isempty(message),    obj.Message    = message;    end
        end
    end
end
