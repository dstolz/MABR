function [preSweep,postSweep] = extract_sweeps(obj,timeWindow,doAll)

persistent lastBufferIdx sweepOnsets

if nargin < 2 || (nargin == 3 && isempty(doAll)), doAll = false; end

preSweep = nan;
postSweep = nan;


bufferHead = obj.mapCom.Data.BufferIndex(2);

if isempty(lastBufferIdx) || lastBufferIdx > bufferHead, lastBufferIdx = 1; end

if lastBufferIdx == 1, sweepOnsets = []; end

LB = double(lastBufferIdx);
BH = double(bufferHead);


if doAll, LB = 1; end

vprintf(4,'lastBufferIdx = %d',LB)
vprintf(4,'bufferHead = %d',BH)

idx = obj.find_timing_onsets(LB,BH);

if isempty(idx), return; end % no new data

vprintf(4,'size(sweepOnsets) = %s',mat2str(size(sweepOnsets)))
vprintf(4,'# new sweeps = %s',mat2str(size(idx)))

if LB == 1 || isempty(sweepOnsets)
    sweepOnsets = idx-1; 
else
    % append newly found detected sweep timing impulses
    sweepOnsets = [sweepOnsets; idx];
end


% split signal into resampled windows
swin  = round(abr.Universal.ADCSampleRate*timeWindow);
samps = sweepOnsets + swin; % matrix expansion

% make sure we do not exceed buffer head position
samps(any(samps<1,2) | any(samps>bufferHead,2),:) = []; 

if isempty(samps), return; end


% organize incoming signal
postSweep = obj.mapSignalBuffer.Data(samps);
if size(postSweep,2) == 1, postSweep = postSweep'; end


% extract signal preceding sweep onsets
bsamps = -1:-1:-size(samps,2);
bsamps = sweepOnsets + bsamps;
bsamps(any(bsamps < 1,2) | any(bsamps>bufferHead,2),:) = [];

preSweep = obj.mapSignalBuffer.Data(bsamps);
if size(preSweep,2) == 1, preSweep = preSweep'; end



vprintf(4,'size(preSweep) = %s',mat2str(size(preSweep)))
vprintf(4,'size(postSweep) = %s',mat2str(size(postSweep)))

% update this last
lastBufferIdx = bufferHead;


