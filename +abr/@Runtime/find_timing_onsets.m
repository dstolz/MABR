function idx = find_timing_onsets(obj,LB,BH,shadowSamples)

if nargin < 2 || isempty(LB), LB = 1; end
if nargin < 3, BH = []; end
if nargin < 4, shadowSamples = 0; end

mTB = obj.mapTimingBuffer;

if isempty(BH)
    BH = obj.mapCom.Data.BufferIndex(end);
end

% find stimulus onsets in timing signal
ind = mTB.Data(LB:BH-1) > mTB.Data(LB+1:BH); % rising edge
ind = ind & mTB.Data(LB:BH-1) >= .5; % threshold

x = find(ind);
dx = diff(x);
dxidx = find(dx < shadowSamples) + 1;
x(dxidx) = [];

idx = LB + x - 1;
% vprintf(3,'Timing onsets returned = %d',length(idx))