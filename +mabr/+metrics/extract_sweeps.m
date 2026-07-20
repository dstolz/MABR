function [preSweep,postSweep,onsets,state] = extract_sweeps(rb,params,state)
% mabr.metrics.extract_sweeps  Slice pre-/post-onset sweep windows from the
% acquisition ring buffer.
%
%   [preSweep,postSweep,onsets,state] = extract_sweeps(rb,params,state)
%
%   Rewrite of the legacy abr.Runtime.extract_sweeps with EXPLICIT state
%   instead of a persistent variable, so the caller (AcqController) owns the
%   incremental extraction cursor. Returns only sweeps discovered since the
%   previous call unless state is reset.
%
%   Inputs
%     rb      a mabr.acq.RingBuffer (read-only) exposing WriteHead, BlockSeq,
%             readTiming(lo,hi) and readSignalAt(idxMatrix).
%     params  struct with fields
%               SampleRate  (Hz) ring-buffer sample rate (e.g. DAC rate)
%               window      [t0 t1] seconds relative to onset
%               decimation  positive integer stride applied to windows
%               threshold   (optional) onset detection threshold (default 0.1)
%               shadow      (optional) min onset spacing, seconds (default 2 ms)
%     state   struct carried across calls: .lastHead, .onsets, .blockSeq.
%             Pass [] or struct() on the first call / to reset.
%
%   Outputs (empty when no new sweeps)
%     preSweep   [nSweeps x nSamples] baseline window before each onset
%     postSweep  [nSweeps x nSamples] response window at/after each onset
%     onsets     [nSweeps x 1] absolute onset sample indices (this block)
%     state      updated cursor state
%
% Daniel Stolzberg (c) 2019-2026

preSweep = []; postSweep = []; onsets = [];

if nargin < 3 || isempty(state), state = struct(); end
if ~isfield(state,'onsets'),   state.onsets   = []; end
if ~isfield(state,'lastHead'), state.lastHead = 0;  end
if ~isfield(state,'blockSeq'), state.blockSeq = -1; end

% Reset on a new block or a buffer wrap.
seq  = rb.BlockSeq;
head = rb.WriteHead;
if seq ~= state.blockSeq || state.lastHead > head
    state.blockSeq = seq;
    state.lastHead = 0;
    state.onsets   = [];
end

if head <= state.lastHead, return; end   % no new data

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
LB = max(1,state.lastHead+1);
BH = head;
timingSlice = rb.readTiming(LB,BH);
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

if isempty(state.onsets), return; end

% --- window offsets (post-onset response, pre-onset baseline) ------------
w  = round(Fs .* params.window);          % [w1 w2] samples
df = params.decimation;
swin = w(1):df:w(2);                       % post-onset offsets
bwin = (w(1)-1):-df:-(w(1)+w(2)+1);        % pre-onset (baseline) offsets

o = state.onsets(:);

postIdx = o + swin;                        % [nSweeps x nPost]
preIdx  = o + bwin;                        % [nSweeps x nPre]

% keep only fully in-range sweeps (indices within [1, head])
valid = ~any(postIdx < 1 | postIdx > head,2) & ~any(preIdx < 1 | preIdx > head,2);
postIdx = postIdx(valid,:);
preIdx  = preIdx(valid,:);
onsets  = o(valid);

if isempty(onsets), preSweep = []; postSweep = []; return; end

postSweep = double(rb.readSignalAt(postIdx));   % [nSweeps x nPost]
preSweep  = double(rb.readSignalAt(preIdx));    % [nSweeps x nPre]

if size(postSweep,2) == 1, postSweep = postSweep.'; end
if size(preSweep,2)  == 1, preSweep  = preSweep.';  end
end
