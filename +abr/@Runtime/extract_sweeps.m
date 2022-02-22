function [preSweep,postSweep,sweepOnsets] = extract_sweeps(obj,ABR,doAll)

persistent lastBufferIdx blockSweepOnsets

if nargin < 3 || isempty(doAll), doAll = false; end



preSweep = nan;
postSweep = nan;
sweepOnsets = nan;


bufferHead = obj.mapCom.Data.BufferIndex(2);

if isempty(lastBufferIdx) || lastBufferIdx > bufferHead, lastBufferIdx = 1; end

if lastBufferIdx == 1, blockSweepOnsets = []; end

LB = double(lastBufferIdx);
BH = double(bufferHead);

if doAll, LB = 1; end

vprintf(4,'lastBufferIdx = %d',LB)
vprintf(4,'bufferHead = %d',BH)

idx = obj.find_timing_onsets(LB,BH);

if isempty(idx), return; end % no new data

vprintf(4,'size(sweepOnsets) = %s',mat2str(size(blockSweepOnsets)))
vprintf(4,'# new sweeps = %s',mat2str(size(idx)))

if LB == 1 || isempty(blockSweepOnsets)
    blockSweepOnsets = idx-1; 
else
    % append newly found detected sweep timing impulses
    blockSweepOnsets = [blockSweepOnsets; idx];
end


% split signal into resampled windows
w = round(ABR.DAC.SampleRate*ABR.adcWindow);
swin = w(1):ABR.adcDecimationFactor:w(2);
samps = blockSweepOnsets + swin; % matrix expansion

% make sure we do not exceed buffer head position
samps(any(samps<1,2) | any(samps>bufferHead,2),:) = []; 

if isempty(samps), return; end


% organize incoming signal
postSweep = obj.mapSignalBuffer.Data(samps);
if size(postSweep,2) == 1, postSweep = postSweep'; end


% extract signal preceding sweep onsets
bsamps = w(1)-1:-ABR.adcDecimationFactor:-w(1)-w(2)-1;
bsamps = blockSweepOnsets + bsamps;
bsamps(any(bsamps < 1,2) | any(bsamps>bufferHead,2),:) = [];

preSweep = obj.mapSignalBuffer.Data(bsamps);
if size(preSweep,2) == 1, preSweep = preSweep'; end



vprintf(4,'size(preSweep) = %s',mat2str(size(preSweep)))
vprintf(4,'size(postSweep) = %s',mat2str(size(postSweep)))

% update this last
lastBufferIdx = bufferHead;

sweepOnsets  = blockSweepOnsets;
