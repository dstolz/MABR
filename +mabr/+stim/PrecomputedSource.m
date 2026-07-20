classdef PrecomputedSource < mabr.stim.StimulusSource
% mabr.stim.PrecomputedSource  Reference StimulusSource over a struct array.
%
%   src = mabr.stim.PrecomputedSource(blocks) wraps a struct array of block
%   specs (see mabr.stim.StimulusSource for the required fields). This is the
%   adapter the external stimulus package plugs its output into, and the
%   source used by the no-hardware verification scripts.
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = private)
        Blocks (1,:) struct
    end

    methods
        function obj = PrecomputedSource(blocks)
            if nargin < 1 || isempty(blocks)
                obj.Blocks = struct([]);
                return
            end
            for i = 1:numel(blocks)
                blocks(i) = mabr.stim.StimulusSource.validateBlock(blocks(i));
            end
            obj.Blocks = blocks;
        end

        function n = numBlocks(obj)
            n = numel(obj.Blocks);
        end

        function blk = getBlock(obj,idx)
            assert(idx >= 1 && idx <= obj.numBlocks,'mabr:stim:PrecomputedSource:range', ...
                'Block index %d out of range (1..%d).',idx,obj.numBlocks);
            blk = obj.Blocks(idx);
        end
    end
end
