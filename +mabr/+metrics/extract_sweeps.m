function [preSweep,postSweep,onsets,state,tvec] = extract_sweeps(rb,params,state)
% mabr.metrics.extract_sweeps  Slice pre-/post-onset sweep windows from the
% acquisition ring buffer, incrementally.
%
%   [preSweep,postSweep,onsets,state,tvec] = extract_sweeps(rb,params,state)
%
%   Rewrite of the legacy abr.Runtime.extract_sweeps with EXPLICIT state
%   instead of a persistent variable, so the caller (mabr.compute.Pipeline)
%   owns the incremental extraction cursor. Each call detects onsets only in
%   the freshly arrived region and windows only the sweeps completed since the
%   last call, and returns THOSE -- not the run so far. It keeps no sweeps: a
%   caller that needs them again (a new filter chain, a new gain) rewinds the
%   cursor (state.nWindowed = 0) and they are read back off the ring, which
%   still holds the block. Returning the whole run on every call, which it
%   used to do from a cache of every sweep so far, made each call cost the run
%   so far: two copies of the cache per call, twenty calls a second.
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
%   Outputs
%     preSweep   [nNew x nSamples] baseline window before each onset
%     postSweep  [nNew x nSamples] response window at/after each onset
%     onsets     [nNew x 1] absolute onset sample indices of those sweeps
%     state      updated cursor. state.nWindowed is how many onsets have been
%                windowed so far, state.onsets every onset found, and
%                state.epoch counts the times it started over (a new block,
%                or a head that went backwards) -- when it moves, the sweeps
%                returned are the first of a new block, not more of the last
%     tvec       struct with .pre and .post: the time (SECONDS, relative to
%                onset) of each column of the matching matrix. The two are
%                contiguous, so [tvec.pre tvec.post] is one unbroken time
%                base running from before the onset to the end of the
%                response -- which is what a live view needs to draw a
%                negative time axis. Returned here rather than recomputed by
%                the caller so the baseline offsets cannot drift apart from
%                the ones the samples were actually taken at.
%
% Daniel Stolzberg (c) 2019-2026

onsets = zeros(0,1);

if nargin < 3 || isempty(state), state = struct(); end
if ~isfield(state,'onsets'),     state.onsets     = zeros(0,1); end
if ~isfield(state,'lastHead'),   state.lastHead   = 0;  end
if ~isfield(state,'blockSeq'),   state.blockSeq   = -1; end
if ~isfield(state,'nWindowed'),  state.nWindowed  = 0;  end
if ~isfield(state,'epoch'),      state.epoch      = 0;  end

% Reset on a new block or a head decrease (block boundary).
seq  = rb.BlockSeq;
head = rb.WriteHead;
if seq ~= state.blockSeq || state.lastHead > head
    state.blockSeq  = seq;
    state.lastHead  = 0;
    state.onsets    = zeros(0,1);
    state.nWindowed = 0;
    state.epoch     = state.epoch + 1;
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

    % A pulse that began in the PREVIOUS slice is not a new onset.
    % find_timing_onsets reports sample 1 of a vector that starts above
    % threshold, which is right for a vector read on its own and wrong here:
    % what it found is the middle of a pulse whose start was counted last
    % time. The shadow interval below cannot be relied on to remove it -- a
    % timing pulse spans its whole presentation (5 ms for the demo bank),
    % which is routinely LONGER than the shadow (2 ms), so a boundary landing
    % more than shadowSamples into a pulse leaves the duplicate standing.
    % That inflates the sweep count and, because the k-th onset is paired
    % with the k-th planned presentation, shifts the attribution of every
    % sweep after it.
    %
    % The sample immediately before this slice settles it. It is always still
    % retained: it was inside the previous slice, and the ring holds minutes.
    if ~isempty(rel) && rel(1) == 1 && LB > 1
        prev = rb.readTiming(LB-1,LB-1);
        if ~isempty(prev) && double(prev(1)) >= thr, rel(1) = []; end
    end

    % Every new onset lies after every old one, and find_timing_onsets has
    % already merged those within the shadow of each other -- so the one
    % pair that can still be closer than the shadow is the last old onset
    % and the first new one. (The whole list used to be re-sorted and
    % re-merged on every call to reach the same answer.)
    newOnsets = LB + rel(:) - 1;              % absolute indices
    if ~isempty(newOnsets) && ~isempty(state.onsets) ...
            && newOnsets(1) - state.onsets(end) < shadowSamples
        newOnsets(1) = [];
    end
    state.onsets   = [state.onsets; newOnsets];
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
tvec = struct('pre',bwin/Fs,'post',swin/Fs);

preSweep  = zeros(0,L);
postSweep = zeros(0,L);

respEnd     = w(2);                           % last response offset
oldestValid = max(1,head - rb.MaxLength + 1); % oldest sample still retained

% --- window the newly completed, in-range sweeps: ONE read per half --------
% The onsets whose response has been fully recorded, from the cursor on.
first = state.nWindowed + 1;
last  = first - 1;
while last < numel(state.onsets) && state.onsets(last+1) + respEnd <= head
    last = last + 1;
end
state.nWindowed = last;
if last < first, return; end

o     = state.onsets(first:last).';           % [1 x k]
postI = o + swin(:);                          % [L x k] absolute indices
preI  = o + bwin(:);
% A baseline or response outside the retained range is skipped, as it
% always was (a run longer than the ring is refused at build, so this is a
% guard rather than a path).
ok = all(preI >= oldestValid,1) & all(postI <= head,1);
if ~any(ok), return; end
postSweep = double(rb.readSignalAt(postI(:,ok))).';   % [k x L]
preSweep  = double(rb.readSignalAt(preI(:,ok))).';
onsets    = o(ok).';
end
