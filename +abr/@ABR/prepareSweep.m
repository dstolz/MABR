function prepareSweep(obj)
% initialize and preallocate variables
% 
% Daniel Stolzberg, PhD (c) 2019

% if obj.STATE >= 0, return; end

if ishandle(obj.APR)
    release(obj.APR);
else
    obj.APR = audioPlayerRecorder;
end

obj.APR.Device      = obj.audioDevice;
obj.APR.SampleRate  = obj.dacFs;
switch class(obj.dacBuffer)
    case {'double','single'}
        obj.APR.BitDepth = '32-bit float';        
    case 'int16'
        obj.APR.BitDepth = '16-bit integer';
    case 'int8'
        obj.APR.BitDepth = '8-bit integer';
end
obj.sweepCount    = 1;
obj.nextSweepTime = hat;
obj.sweepOnsets   = nan(obj.numSweeps,1);

obj.adcBuffer = nan(obj.adcBufferLength,1);
obj.adcData   = nan(obj.adcBufferLength,obj.numSweeps);
obj.adcDataFiltered = obj.adcData;

obj.STATE = 0;
