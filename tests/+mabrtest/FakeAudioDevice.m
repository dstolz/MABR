classdef FakeAudioDevice < matlab.System
% mabrtest.FakeAudioDevice  Stands in for audioPlayerRecorder on a worker.
%
%   dev = mabrtest.FakeAudioDevice('SampleRate',fs,...) accepts the arguments
%   mabr.acq.worker_loop's prepare_device builds a real device with, and is
%   called the same way: [recorded,nUnder,nOver] = dev(frame). What it
%   "records" is the frame it was handed -- a loop-back, as Test Mode is --
%   and every call takes a frame's worth of wall-clock time, so a loop it
%   paces runs at the rate a real device would pace it. release() works as it
%   does on a System object.
%
%   It exists for verify_device_reuse. The suite runs in Test Mode, where no
%   device is opened at all, so without a stand-in nothing could check that
%   the worker keeps its device between runs rather than building a new one.
%   A spec selects it per Prep through its DeviceFactory field; nothing on a
%   rig sets that.

    properties (Nontunable)
        SampleRate             = 192000
        PlayerChannelMapping   = [1 2]
        RecorderChannelMapping = [1 2]
        BitDepth               = '32-bit float'
        Device                 = 'Fake'
    end

    methods
        function obj = FakeAudioDevice(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end

    methods (Access = protected)
        function n = getNumOutputsImpl(~)
            n = 3;
        end

        function tf = isInputSizeMutableImpl(~,~)
            tf = true;       % a block's last frame is short; idle frames are not
        end

        function [y,nUnder,nOver] = stepImpl(obj,x)
            y = x;
            nUnder = 0;
            nOver  = 0;
            pause(size(x,1)/obj.SampleRate);
        end
    end
end
