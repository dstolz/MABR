function [preSweep,postSweep,onsets,state] = extract_sweeps(rb,params,state)
% mabr.metrics.extract_sweeps  Slice pre-/post-onset sweep windows from the
% acquisition ring buffer.
%
%   [preSweep,postSweep,onsets,state] = extract_sweeps(rb,params,state)
%
%   Rewrite of the legacy abr.Runtime.extract_sweeps with EXPLICIT state
%   instead of a persistent variable, so the caller (AcqController) owns the
%   incremental extraction cursor. Each call detects onsets only in the
%   freshly arrived region and windows only the newly completed sweeps,
%   caching them in state; it returns the full accumulated pre/post matrices
%   (rebuilt from the cache, not re-read from the memmap every call).
%
%   Inputs
%     rb      a mabr.acq.RingBuffer (read-only) exposing WriteHead, BlockSeq,
%             MaxLength, readTiming(lo,hi) and readSignalAt(idxMatrix).
%     params  struct with fields
%               SampleRate  (Hz) ring-buffer sample rate (e.g. DAC rate)
%               window      [t0 t1] seconds relative to onset
%               decimation  positive integer stride applied to windows
%               threshold   (optional) onset detection threshold (default 0.1)
%               shadow      (optional) min onset spacing, seconds (default 2 ms)
%     state   struct carried across calls (pass [] or struct() to reset).
%
%   Outputs (empty until at least one sweep is complete)
%     preSweep   [nSweeps x nSamples] baseline window before each onset
%     postSweep  [nSweeps x nSamples] response window at/after each onset
%     onsets     [nSweeps x 1] absolute onset sample indices (this block)
%     state      updated cursor + sweep cache
%
% Daniel Stolzberg (c) 2019-2026

preSweep = []; postSweep = []; onsets = [];

if nargin < 3 || isempty(state), state = struct(); end
if ~isfield(state,'onsets'),     state.onsets     = []; end
if ~isfield(state,'lastHead'),   state.lastHead   = 0;  end
if ~isfield(state,'blockSeq'),   state.blockSeq   = -1; end
if ~isfield(state,'nWindowed'),  state.nWindowed  = 0;  end
if ~isfield(state,'preCache'),   state.preCache   = []; end   % [nSamples x nSweeps]
if ~isfield(state,'postCache'),  state.postCache  = []; end   % [nSamples x nSweeps]
if ~isfield(state,'onsetCache'), state.onsetCache = []; end

% Reset on a new block or a head decrease (block boundary).
seq  = rb.BlockSeq;
head = rb.WriteHead;
if seq ~= state.blockSeq || state.lastHead > head
    state.blockSeq   = seq;
    state.lastHead   = 0;
    state.onsets     = [];
    state.nWindowed  = 0;
    state.preCache   = [];
    state.postCache  = [];
    state.onsetCache = [];
end

Fs = params.SampleRate;
if isfield(params,'threshold') && ~isempty(params.threshold)
    thr = params.threshold;
else
    thr = 0.1;
end
if isfield(params,'shadow') && ~isempty(params.shadow)
    shadowSamples = round(params.shadow*Fs);
else
    shadowSamples = round(0.002*Fs);      % 2 ms
end

% --- detect new onsets in the freshly arrived region ---------------------
if head > state.lastHead
    LB = max(1,state.lastHead+1);
    timingSlice = rb.readTiming(LB,head);
    rel = mabr.metrics.find_timing_onsets(timingSlice,shadowSamples,thr);
    newOnsets = LB + rel - 1;                 % absolute indices
    state.onsets = [state.onsets; newOnsets(:)];
    % de-duplicate across the slice boundary
    if ~isempty(state.onsets)
        state.onsets = sort(state.onsets);
        keep = [true; diff(state.onsets) >= shadowSamples];
        state.onsets = state.onsets(keep);
    end
    state.lastHead = head;
end

% --- window offsets (post-onset response, pre-onset baseline) ------------
% The baseline is the same number of (decimated) samples as the response,
% taken immediately before the onset, so pre/post always share a column count
% (required by mabr.metrics.partition_corr) for any window(1).
w    = round(Fs .* params.window);            % [w1 w2] samples
df   = params.decimation;
swin = w(1):df:w(2);                          % post-onset offsets
L    = numel(swin);
bwin = -df*(L:-1:1);                          % pre-onset (baseline) offsets

respEnd     = w(2);                           % last response offset
oldestValid = max(1,head - rb.MaxLength + 1); % oldest sample still retained

% --- window only the newly completed, in-range sweeps --------------------
i = state.nWindowed;
while i < numel(state.onsets)
    o = state.onsets(i+1);
    if o + respEnd > head, break; end         % response not fully recorded yet
    i = i + 1;
    postI = o + swin;
    preI  = o + bwin;
    if any(preI < oldestValid) || any(postI > head)
        continue;                             % baseline/response outside retained range
    end
    state.postCache(:,end+1) = double(rb.readSignalAt(postI(:)));
    state.preCache(:,end+1)  = double(rb.readSignalAt(preI(:)));
    state.onsetCache(end+1,1) = o;
end
state.nWindowed = i;

if isempty(state.postCache), return; end

postSweep = state.postCache.';                % [nSweeps x nSamples]
preSweep  = state.preCache.';
onsets    = state.onsetCache;
end
