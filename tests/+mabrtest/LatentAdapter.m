classdef LatentAdapter < mabr.stim.CalibrationAdapter
% mabrtest.LatentAdapter  A CalibrationAdapter over a simulated duplex device.
%
%   adapter = mabrtest.LatentAdapter(audio,cfg,latency,acoustic) stands in
%   for audioPlayerRecorder with a device whose round trip is LATENCY samples
%   on every input, plus ACOUSTIC more samples on the mic input only -- the
%   air between speaker and microphone. The timing loop-back is a wire, so it
%   carries the round trip alone. Everything else in play_and_record runs as
%   it does on a rig.
%
%   Loopback = false simulates a missing loop-back cable (the timing input
%   records silence). Gain and Noise shape the mic input.

    properties
        Latency  (1,1) double = 0
        Acoustic (1,1) double = 0
        Loopback (1,1) logical = true
        Gain     (1,1) double = 0.05
        Noise    (1,1) double = 1e-5
        Streams  (1,1) double = 0       % how many times the device was used
    end

    methods
        function obj = LatentAdapter(audio,cfg,latency,acoustic)
            obj@mabr.stim.CalibrationAdapter(audio,cfg);
            obj.Latency  = latency;
            obj.Acoustic = acoustic;
        end
    end

    methods (Access = protected)
        function [rec,nUnder,nOver] = stream(obj,play,~,~,inMap)
            obj.Streams = obj.Streams + 1;
            nPad = size(play,1);
            rec  = zeros(nPad,numel(inMap));
            rec(:,1) = obj.Gain*delay(play(:,1),obj.Latency + obj.Acoustic) ...
                     + obj.Noise*randn(nPad,1);
            if numel(inMap) > 1 && obj.Loopback
                rec(:,2) = delay(play(:,2),obj.Latency);
            end
            nUnder = 0; nOver = 0;
        end
    end
end

function y = delay(x,d)
y = [zeros(d,1); x(:)];
y = y(1:numel(x));
end
