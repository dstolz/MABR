classdef (Abstract) StimulusSource < handle
% mabr.stim.StimulusSource  Contract MABR consumes for stimulus delivery.
%
%   MABR no longer generates signals or applies calibration. An external
%   package supplies, per session, an ordered set of pre-computed, calibrated
%   blocks through this contract. Concrete subclasses (or the reference
%   mabr.stim.PrecomputedSource) implement:
%
%       n   = numBlocks(obj)        number of blocks in the session
%       blk = getBlock(obj,idx)     block spec struct for block idx
%
%   Each block spec struct MUST provide:
%       samples      [N x 1] single  precomputed, calibrated signal channel
%       SampleRate   (1,1)  double   DAC sample rate (Hz)
%   and MUST provide sweep timing as ONE of:
%       SweepOnsets  [k x 1] double  onset sample indices into samples, OR
%       SweepRate    (1,1)  double   sweeps/second (with optional NumSweeps)
%   and SHOULD provide:
%       Meta         (1,1)  struct   display + .abr metadata, with fields
%                     Frequency, Level, Polarity, Label (cellstr),
%                     informativeParams (cellstr of the numeric field names)
%   and MAY provide:
%       Timing       [N x 1] single  its own timing channel (otherwise MABR
%                                     synthesizes one pulse per sweep onset)
%       Device       (1,:)  char     ASIO device name override
%
%   MABR owns the timing-pulse contract because sweep extraction
%   (mabr.metrics.find_timing_onsets / extract_sweeps) depends on it; unless a
%   block supplies its own Timing, mabr.stim.BlockQueue synthesizes a single
%   unit pulse at each sweep onset.
%
% Daniel Stolzberg (c) 2019-2026

    methods (Abstract)
        n   = numBlocks(obj)
        blk = getBlock(obj,idx)
    end

    methods (Static)
        function blk = validateBlock(blk)
            % Validate and normalize a block spec against the contract.
            assert(isstruct(blk),'mabr:stim:StimulusSource:badBlock', ...
                'A block spec must be a struct.');
            assert(isfield(blk,'samples') && ~isempty(blk.samples), ...
                'mabr:stim:StimulusSource:noSamples','Block spec needs nonempty samples.');
            assert(isfield(blk,'SampleRate') && isscalar(blk.SampleRate), ...
                'mabr:stim:StimulusSource:noSampleRate','Block spec needs a scalar SampleRate.');
            assert((isfield(blk,'SweepOnsets') && ~isempty(blk.SweepOnsets)) || ...
                   (isfield(blk,'SweepRate')  && ~isempty(blk.SweepRate)), ...
                'mabr:stim:StimulusSource:noTiming', ...
                'Block spec needs SweepOnsets or SweepRate.');

            blk.samples = single(blk.samples(:));
            if ~isfield(blk,'Meta') || isempty(blk.Meta), blk.Meta = struct(); end
        end
    end
end
