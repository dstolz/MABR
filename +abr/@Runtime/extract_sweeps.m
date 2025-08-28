function [preSweep,postSweep,sweepOnsets] = extract_sweeps(obj,ABR,doAll,observedBuffer)
% extract_sweeps  Slice pre-/post-onset sweep windows from a circular buffer.
%
%   [preSweep, postSweep, sweepOnsets] = extract_sweeps(obj, ABR)
%   [preSweep, postSweep, sweepOnsets] = extract_sweeps(obj, ABR, doAll)
%   [preSweep, postSweep, sweepOnsets] = extract_sweeps(obj, ABR, doAll, observedBuffer)
%
% Description
%   Finds sweep onset indices within obj’s buffer and extracts decimated
%   windows of samples immediately before and after each onset. The function
%   keeps state across calls (persistent) to return only newly arrived sweeps
%   unless doAll = true.
%
% Inputs
%   obj                 Handle to an acquisition/buffer object exposing:
%                       • obj.BufferIndex(2) -> current buffer head (sample idx)
%                       • obj.find_timing_onsets(iStart, iEnd) -> [k×1] double
%                         onset sample indices in [iStart, iEnd]
%                       • obj.(observedBuffer).Data -> vector of buffered samples
%
%   ABR                 Struct with acquisition/ADC parameters:
%                       • ABR.DAC.SampleRate            (1,1) double, Hz
%                       • ABR.adcWindow                 (1,2) double, seconds
%                           [t0  t1] relative to the onset; t0 ≤ t1.
%                       • ABR.adcDecimationFactor       (1,1) positive integer
%                           Step (in samples) used when indexing the buffer.
%
%   doAll              (optional) logical scalar, default = false
%                       false -> return sweeps detected since the last call
%                                 (uses persistent lastBufferIdx).
%                       true  -> ignore state and re-extract from buffer start.
%
%   observedBuffer     (optional) string/char, default = 'mapSignalBuffer'
%                       Name of the obj property holding the data buffer to
%                       slice (e.g., 'mapSignalBuffer' or 'mapTimingBuffer').
%
% Outputs
%   preSweep           [nSweeps × nPreSamples] double
%                       Decimated samples immediately preceding each onset.
%                       nPreSamples = numel((w1-1):-ABR.adcDecimationFactor:-(w1+w2+1))
%                       where [w1 w2] = round(ABR.DAC.SampleRate * ABR.adcWindow).
%                       Each row corresponds to one sweep; columns are time.
%
%   postSweep          [nSweeps × nPostSamples] double
%                       Decimated samples starting at each onset.
%                       nPostSamples = numel(w1:ABR.adcDecimationFactor:w2).
%                       Each row corresponds to one sweep; columns are time.
%
%   sweepOnsets        [nSweeps × 1] double
%                       Absolute sample indices (1-based) of detected onsets
%                       in the observed buffer’s sample coordinates.
%
% Behavior & Notes
%   • Windows are constructed in sample indices as:
%       w  = round(ABR.DAC.SampleRate * ABR.adcWindow);  % [w1 w2] samples
%       swin  = w1:ABR.adcDecimationFactor:w2;           % post-onset offsets
%       bswin = (w1-1):-ABR.adcDecimationFactor:-(w1+w2+1); % pre-onset offsets
%     Out-of-range rows (any index < 1 or > buffer head) are dropped.
%   • Persistent state (lastBufferIdx, blockSweepOnsets) is reset if the
%     buffer head wraps (lastBufferIdx > buffer head) or when doAll = true.
%   • If no new sweeps are found, outputs are returned as NaN.
%
% Example
%   % Extract new sweeps from the signal buffer:
%   [preS, postS, onsets] = extract_sweeps(obj, ABR, false, 'mapSignalBuffer');
%
%   % Force reprocessing from the start of the current buffer:
%   [preS, postS, onsets] = extract_sweeps(obj, ABR, true);
%


persistent lastBufferIdx blockSweepOnsets

if nargin < 3 || isempty(doAll), doAll = false; end
if nargin < 4 || isempty(observedBuffer), observedBuffer = 'mapSignalBuffer'; end % mapTimingBuffer or mapSignalBuffer

preSweep = nan;
postSweep = nan;
sweepOnsets = nan;


bufferHead = obj.BufferIndex(2);

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
postSweep = obj.(observedBuffer).Data(samps);
if size(postSweep,2) == 1, postSweep = postSweep'; end


% extract signal preceding sweep onsets
bsamps = w(1)-1:-ABR.adcDecimationFactor:-w(1)-w(2)-1;
bsamps = blockSweepOnsets + bsamps;
bsamps(any(bsamps < 1,2) | any(bsamps>bufferHead,2),:) = [];

preSweep = obj.(observedBuffer).Data(bsamps);
if size(preSweep,2) == 1, preSweep = preSweep'; end



vprintf(4,'size(preSweep) = %s',mat2str(size(preSweep)))
vprintf(4,'size(postSweep) = %s',mat2str(size(postSweep)))

% update this last
lastBufferIdx = bufferHead;

sweepOnsets  = blockSweepOnsets;
