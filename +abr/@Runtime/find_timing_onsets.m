function idx = find_timing_onsets(obj,LB,BH,shadowSamples)

if nargin < 2 || isempty(LB), LB = 1; end
if nargin < 3, BH = []; end
if nargin < 4
    if isa(obj,'abr.ABR')
        Fs = obj.ADC.SampleRate;
    elseif isa(obj,'abr.Runtime')
        Fs = obj.ABR.ADC.SampleRate;
    end
    shadowSamples = round(0.1*Fs); 
end
    
if isempty(BH)
    BH = obj.mapCom.Data.BufferIndex(end);
end

d = abs(obj.mapTimingBuffer.Data(LB:BH));

% find stimulus onsets in timing signal
ind = d(1:end-1) < d(2:end); % rising edge
ind = ind & d(1:end-1) >= .25; % threshold

x = find(ind);
dx = diff(x);
dxidx = find(dx < shadowSamples) + 1;
x(dxidx) = [];

idx = LB + x - 1;
% vprintf(3,'Timing onsets returned = %d',length(idx))