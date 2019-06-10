function idx = find_timing_onsets(obj,LB,BH)

if nargin < 2 || isempty(LB), LB = 1; end
if nargin < 3, BH = []; end

mTB = obj.mapTimingBuffer;

if isempty(BH)
    BH = obj.mapCom.Data.BufferIndex(end);
end

LB = double(LB);
BH = double(BH);

% find stimulus onsets in timing signal
ind = mTB.Data(LB:BH-1) > mTB.Data(LB+1:BH); % rising edge
ind = ind & mTB.Data(LB:BH-1) >= 0.5; % threshold

idx = LB + find(ind);