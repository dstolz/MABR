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
%
%   verify_input_calibration uses it as a loop-back cable with a gain knob:
%   Gain scales what it "records" (and, once set, clips it at +/-1 as a real
%   converter would), and Realtime = false drops the per-frame wait so a
%   measurement does not take its own length to test.

    properties (Nontunable)
        SampleRate             = 192000
        PlayerChannelMapping   = [1 2]
        RecorderChannelMapping = [1 2]
        BitDepth               = '32-bit float'
        Device                 = 'Fake'
    end

    properties
        Gain     = 1        % what the loop "records" per unit played
        Realtime = true     % pace each call at the device's frame rate
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
            if obj.Gain ~= 1, y = min(max(obj.Gain*x,-1),1); end
            nUnder = 0;
            nOver  = 0;
            if obj.Realtime, pause(size(x,1)/obj.SampleRate); end
        end
    end
end
