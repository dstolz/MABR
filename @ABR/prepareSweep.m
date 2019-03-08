function prepareSweep(obj)
% initialize and preallocate variables
% 
% Daniel Stolzberg, PhD (c) 2019

% if obj.STATE >= 0, return; end

release(obj.APR);

obj.APR.Device      = obj.audioDevice;
obj.APR.SampleRate  = obj.dacFs;
obj.APR.BitDepth    = sprintf('%d-bit integer',obj.dacBitDepth);

obj.sweepCount    = 1;
obj.nextSweepTime = hat;
obj.sweepOnsets   = nan(obj.numSweeps,1);

obj.adcBuffer = nan(obj.adcBufferLength,1);
obj.adcData   = nan(obj.adcBufferLength,obj.numSweeps);
obj.adcDataFiltered = obj.adcData;

obj.STATE = 0;
