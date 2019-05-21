function obj = prepareSweep(obj)
% initialize and preallocate variables
% 
% Daniel Stolzberg, PhD (c) 2019



if ismethod(obj.APR,'isvalid') && obj.APR.isvalid, delete(obj.APR); end

obj.APR = audioPlayerRecorder;
obj.APR.Device = obj.audioDevice;

% release(obj.APR);

% channel mapping
obj.APR.PlayerChannelMapping   = [obj.DACsignalCh obj.DACtimingCh];
obj.APR.RecorderChannelMapping = [obj.ADCsignalCh obj.ADCtimingCh];

obj.APR.SampleRate = obj.DAC.SampleRate;

obj.DACtiming.SampleRate = obj.DAC.SampleRate;
obj.ADCtiming.SampleRate = obj.DAC.SampleRate;

switch class(obj.DAC.Data)
    case {'double','single'}
        obj.APR.BitDepth = '32-bit float';
    case 'int16'
        obj.APR.BitDepth = '16-bit integer';
    case 'int8'
        obj.APR.BitDepth = '8-bit integer';
end

obj.sweepCount = 1;
