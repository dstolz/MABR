classdef BlockNotifier < handle
% mabrtest.BlockNotifier  Stand-in for mabr.ui.AcqController in tests.
%
%   Raises the same BlockReady event with the same payload, so
%   mabr.ui.TraceOrganizer.listenTo can be verified without starting a
%   parallel pool or an acquisition engine.
%
% Daniel Stolzberg (c) 2026

    events
        BlockReady
    end

    methods
        function emit(obj,block)
            notify(obj,'BlockReady',mabr.ui.ProgStateEventData( ...
                mabr.ui.ProgState.BlockComplete,struct('block',block)));
        end
    end
end
