function [preSweep,postSweep] = extract_sweeps(app)

persistent bufferHead lastBufferIdx

if isempty(bufferHead), bufferHead = 1; end


preSweep = nan;
postSweep = nan;


% look for updated buffer index
if app.Runtime.mapCom.Data.BufferIndex(2) == bufferHead, return; end

bufferHead = app.Runtime.mapCom.Data.BufferIndex(2);


if isempty(lastBufferIdx) || lastBufferIdx > bufferHead, lastBufferIdx = 1; end


LB = double(lastBufferIdx);
BH = double(bufferHead);


mTB = app.Runtime.mapTimingBuffer;

% find stimulus onsets in timing signal
ind = mTB.Data(LB:BH-1) > mTB.Data(LB+1:BH); % rising edge
ind = ind & mTB.Data(LB:BH-1) >= 0.5; % threshold

if ~any(ind), return; end % no new post

idx = LB + find(ind);

% append newly found detected sweep timing impulses
app.ABR.ADC.SweepOnsets = [app.ABR.ADC.SweepOnsets; idx];



% split signal into resampled windows
swin  = round(app.ABR.DAC.SampleRate.*app.ABR.adcWindow);
swin  = swin(1):app.ABR.adcDecimationFactor:swin(2);
samps = app.ABR.ADC.SweepOnsets + swin; % matrix expansion

% make sure we do not exceed buffer head position
samps(any(samps<1,2) | any(samps>bufferHead,2),:) = []; 

if isempty(samps), return; end


% organize incoming signal
postSweep = app.Runtime.mapInputBuffer.Data(samps);
if app.ABR.sweepCount == 1, postSweep = postSweep'; end



% extract signal preceding sweep onsets
bsamps = -1:-1:-size(samps,2);
bsamps = app.ABR.ADC.SweepOnsets + bsamps;
bsamps(any(bsamps < 1,2) | any(bsamps>bufferHead,2),:) = [];


preSweep = app.Runtime.mapInputBuffer.Data(bsamps);


% update this last
lastBufferIdx = bufferHead;