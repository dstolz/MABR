function triggerSweep(obj)
% triggerSweep(obj)
%
% Call for each frame to update dac and adc buffers
%
% This function is meant to be called from a loop for each
% sweep.  ABR.prepareSweep should be called once before the
% loop and ABR.finalizeSweep can be called once after the
% sweep.
% 
% Daniel Stolzberg, PhD (c) 2019

obj.STATE = 1; % recording

n = obj.dacBufferLength;
k = obj.frameLength;

% wait until we reach the next sweep time
while obj.nextSweepTime > hat, end

T = hat; % stimulus onset

for i = 1:k:n
    [obj.adcBuffer(i:i+k-1),nu,no] = obj.APR(obj.dacBuffer(i:i+k-1));
%     if nu, fprintf('Number of underruns = %d\n',nu); end
%     if no, fprintf('Number of overruns  = %d\n',no); end
end

obj.sweepOnsets(obj.sweepCount) = T;

obj.nextSweepTime = T + 1/obj.sweepRate;

obj.adcData(:,obj.sweepCount) = obj.adcBuffer(1:obj.adcDecimationFactor:end);

obj.adcDataFiltered(:,obj.sweepCount) = filtfilt(obj.adcFilterDesign,obj.adcData(:,obj.sweepCount));

obj.sweepCount = obj.sweepCount + 1;

obj.STATE = 2; % finished
