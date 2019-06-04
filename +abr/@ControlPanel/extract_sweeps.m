function [preSweep,postSweep] = extract_sweeps(app,doAll)

persistent lastBufferIdx


if nargin < 2 || isempty(doAll), doAll = false; end

preSweep = nan;
postSweep = nan;


% look for updated buffer index
% if app.Runtime.mapCom.Data.BufferIndex(2) == bufferHead, return; end

bufferHead = app.Runtime.mapCom.Data.BufferIndex(2);


if isempty(lastBufferIdx) || lastBufferIdx > bufferHead, lastBufferIdx = 1; end


LB = double(lastBufferIdx);
BH = double(bufferHead);


if doAll, LB = 1; end

vprintf(4,'lastBufferIdx = %d',LB)
vprintf(4,'bufferHead = %d',BH)

idx = app.find_timing_onsets(LB,BH);

if isempty(idx), return; end % no new data

vprintf(4,'size(app.ABR.ADC.SweepOnsets) = %s',mat2str(size(app.ABR.ADC.SweepOnsets)))
vprintf(4,'# new sweeps = %s',mat2str(size(idx)))

if LB == 1
    app.ABR.ADC.SweepOnsets = idx-1; 
else
    % append newly found detected sweep timing impulses
    app.ABR.ADC.SweepOnsets = [app.ABR.ADC.SweepOnsets; idx];
end


% split signal into resampled windows
swin  = round(app.ABR.ADC.SampleRate*app.ABR.adcWindowTVec);
samps = app.ABR.ADC.SweepOnsets + swin; % matrix expansion

% make sure we do not exceed buffer head position
samps(any(samps<1,2) | any(samps>bufferHead,2),:) = []; 

if isempty(samps), return; end


% organize incoming signal
postSweep = app.Runtime.mapSignalBuffer.Data(samps);
if size(postSweep,2) == 1, postSweep = postSweep'; end


% extract signal preceding sweep onsets
bsamps = -1:-1:-size(samps,2);
bsamps = app.ABR.ADC.SweepOnsets + bsamps;
bsamps(any(bsamps < 1,2) | any(bsamps>bufferHead,2),:) = [];

preSweep = app.Runtime.mapSignalBuffer.Data(bsamps);
if size(preSweep,2) == 1, preSweep = preSweep'; end


% update signal amplitude by InputAmpGain
A = app.Config.Parameters.InputAmpGain;
preSweep  = preSweep ./ A;
postSweep = postSweep ./ A;

vprintf(4,'size(preSweep) = %s',mat2str(size(preSweep)))
vprintf(4,'size(postSweep) = %s',mat2str(size(postSweep)))

% update this last
lastBufferIdx = bufferHead;


