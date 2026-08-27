classdef GrowingRing < handle
% mabrtest.GrowingRing  A ring buffer being written to, replayed on demand.
%
%   Stands in for mabr.acq.RingBuffer over a recording that is already
%   complete, exposing only as much of it as Head says. Advancing Head
%   replays the acquisition a slice at a time, which is what lets a test drive
%   the INCREMENTAL path -- mabr.metrics.extract_sweeps' cursor, and the
%   mabr.compute.Pipeline cycle built on it -- deterministically, with the
%   slice boundaries falling exactly where the test wants them rather than
%   wherever a 20 Hz timer happened to land.
%
%   That distinction matters: extracting a finished block in one call and
%   extracting it in twenty exercise different code. A pulse that straddles a
%   slice boundary is only visible to the second.
%
%       g = mabrtest.GrowingRing(signal,timing);
%       g.Head = 5000;  stats = pipeline.step(g);
%       g.Head = 9000;  stats = pipeline.step(g);
%
%   Implements the surface extract_sweeps uses: WriteHead, BlockSeq,
%   MaxLength, readTiming(lo,hi), readSignalAt(idx), plus readBlock() so
%   finalization can be driven over the same samples.
%
% Daniel Stolzberg (c) 2026

    properties
        Head (1,1) double = 0       % how much of the recording is "written"
        Seq  (1,1) double = 1       % BlockSeq; bump it to signal a new block
    end

    properties (SetAccess = immutable)
        Signal
        Timing
        MaxLength (1,1) double
    end

    properties (Dependent)
        WriteHead
        BlockSeq
        NumValid
    end

    methods
        function obj = GrowingRing(signal,timing)
            obj.Signal    = single(signal(:));
            obj.Timing    = single(timing(:));
            assert(numel(obj.Signal) == numel(obj.Timing), ...
                'mabrtest:GrowingRing:length', ...
                'signal (%d) and timing (%d) must be the same length', ...
                numel(obj.Signal),numel(obj.Timing));
            obj.MaxLength = numel(obj.Signal);
        end

        function v = get.WriteHead(obj), v = obj.Head; end
        function v = get.BlockSeq(obj),  v = obj.Seq;  end
        function v = get.NumValid(obj),  v = min(obj.Head,obj.MaxLength); end

        function n = full(obj)
            % Everything there is, for a caller that wants to finish the replay.
            n = obj.MaxLength;
        end

        function y = readTiming(obj,lo,hi)
            y = obj.slice(obj.Timing,lo,hi);
        end

        function y = readSignal(obj,lo,hi)
            y = obj.slice(obj.Signal,lo,hi);
        end

        function y = readSignalAt(obj,idx)
            y = obj.Signal(idx);
        end

        function y = readTimingAt(obj,idx)
            y = obj.Timing(idx);
        end

        function [sig,tim] = readBlock(obj)
            n = obj.NumValid;
            if n < 1, sig = single([]); tim = single([]); return; end
            sig = obj.Signal(1:n);
            tim = obj.Timing(1:n);
        end
    end

    methods (Access = private)
        function y = slice(obj,x,lo,hi)
            % No wrap: this replays a recording that fits, which is what a
            % test wants to reason about.
            lo = max(1,lo);
            hi = min([hi obj.Head obj.MaxLength]);
            if hi < lo, y = single([]); return; end
            y = x(lo:hi);
        end
    end
end
