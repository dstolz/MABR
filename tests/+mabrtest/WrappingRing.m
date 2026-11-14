classdef WrappingRing < handle
% mabrtest.WrappingRing  A genuine circular buffer, far shorter than the
% recording written into it.
%
%   mabrtest.GrowingRing replays a recording the ring holds whole. This one
%   is the other case, and the one a run longer than the acquisition ring is:
%   the recording is written into MaxLength samples of storage a slice at a
%   time, and every sample older than one lap is OVERWRITTEN by a newer one,
%   exactly as mabr.acq.RingBuffer does it -- so a reader that falls behind
%   reads the next lap's samples, not an error. That is what lets a test show
%   a run several laps long finalized as though the ring had held it
%   (mabr.compute.RunArchive), and a lost lap detected rather than read.
%
%       w = mabrtest.WrappingRing(signal,timing,maxLength);
%       w.advance(9600);   stats = pipeline.step(w);
%       w.advance(9600);   stats = pipeline.step(w);
%
%   Implements the surface the pipeline uses: WriteHead, BlockSeq, MaxLength,
%   NumValid, readSignal/readTiming(lo,hi), readSignalAt/readTimingAt(idx)
%   and readBlock() (the last lap, as the real one returns it).
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Head (1,1) double = 0          % samples written
        Seq  (1,1) double = 1
        MaxLength (1,1) double
    end

    properties (Dependent)
        WriteHead
        BlockSeq
        NumValid
        Remaining                      % samples of the recording not yet written
    end

    properties (Access = private)
        SrcSig
        SrcTim
        Sig
        Tim
    end

    methods
        function obj = WrappingRing(signal,timing,maxLength)
            obj.SrcSig = single(signal(:));
            obj.SrcTim = single(timing(:));
            assert(numel(obj.SrcSig) == numel(obj.SrcTim), ...
                'mabrtest:WrappingRing:length','signal and timing must be the same length');
            obj.MaxLength = maxLength;
            obj.Sig = zeros(maxLength,1,'single');
            obj.Tim = zeros(maxLength,1,'single');
        end

        function v = get.WriteHead(obj), v = obj.Head; end
        function v = get.BlockSeq(obj),  v = obj.Seq;  end
        function v = get.NumValid(obj),  v = min(obj.Head,obj.MaxLength); end
        function v = get.Remaining(obj), v = numel(obj.SrcSig) - obj.Head; end

        function n = advance(obj,n)
            % Write the next n samples of the recording (fewer at its end).
            n = max(0,min(n,obj.Remaining));
            if n == 0, return; end
            idx = obj.Head + (1:n)';
            if n > obj.MaxLength, idx = idx(end-obj.MaxLength+1:end); end
            p = mod(idx - 1,obj.MaxLength) + 1;
            obj.Sig(p) = obj.SrcSig(idx);
            obj.Tim(p) = obj.SrcTim(idx);
            obj.Head = obj.Head + n;
        end

        function y = readSignal(obj,lo,hi), y = obj.Sig(obj.phys(lo:hi)); end
        function y = readTiming(obj,lo,hi), y = obj.Tim(obj.phys(lo:hi)); end
        function y = readSignalAt(obj,idx), y = reshape(obj.Sig(obj.phys(idx)),size(idx)); end
        function y = readTimingAt(obj,idx), y = reshape(obj.Tim(obj.phys(idx)),size(idx)); end

        function [sig,tim] = readBlock(obj)
            n = obj.NumValid;
            if n < 1, sig = single([]); tim = single([]); return; end
            lo  = obj.Head - n + 1;
            sig = obj.readSignal(lo,obj.Head);
            tim = obj.readTiming(lo,obj.Head);
        end
    end

    methods (Access = private)
        function p = phys(obj,idx)
            p = mod(idx(:) - 1,obj.MaxLength) + 1;
        end
    end
end
