classdef (ConstructOnLoad) MessageEventData < event.EventData
% mabr.compute.MessageEventData  Payload for mabr.compute.ComputeEngine events:
% which worker (Role), what happened (Type), and whatever came with it (Data).
%
% Daniel Stolzberg (c) 2026

    properties
        Role (1,:) char = ''
        Type (1,:) char = ''
        Data = []
    end

    methods
        function obj = MessageEventData(role,type,data)
            if nargin >= 1, obj.Role = char(role); end
            if nargin >= 2, obj.Type = char(type); end
            if nargin >= 3, obj.Data = data; end
        end
    end
end
