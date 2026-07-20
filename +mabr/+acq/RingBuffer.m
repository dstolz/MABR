classdef RingBuffer < handle
% mabr.acq.RingBuffer  Thin wrapper over the memory-mapped sample buffers
% shared between the acquisition worker (writer) and the GUI client (reader).
%
%   This is the single memory-mapped surface retained from the legacy
%   two-process design. It replaces input_buffer.dat / input_timing.dat and
%   the BufferIndex fields of mabr_com.dat with:
%       * signalBufferFile - recorded signal channel (single, maxLen)
%       * timingBufferFile - recorded timing channel (single, maxLen)
%       * headerFile       - tiny header holding the monotonic write head
%
%   It is a TRUE circular buffer. WriteHead is the monotonic count of samples
%   written since the last reset() (NOT a physical index); physical storage
%   position is WriteHead modulo MaxLength, and writes that straddle the end
%   are split across the wrap. Readers address samples by their monotonic
%   absolute index and the buffer maps them back to physical storage, so a
%   block longer than one lap is still read in chronological order (only the
%   oldest MaxLength samples survive). Commands and state travel over
%   DataQueues, NOT through here.
%
%   Usage:
%       rb = mabr.acq.RingBuffer(cfg,true)    % worker (writable)
%       rb = mabr.acq.RingBuffer(cfg,false)   % client (read-only)
%
% Daniel Stolzberg (c) 2019-2026

    properties (SetAccess = immutable)
        Writable  (1,1) logical
        MaxLength (1,1) double     % maxInputBufferLength (samples)
    end

    properties (Access = private)
        mapSignal    % memmapfile - signal channel
        mapTiming    % memmapfile - timing channel
        mapHeader    % memmapfile - write-head header

        % Writer-side cache of the header so the hot writeFrame path performs
        % exactly one header write per frame and never reads it back.
        CacheHead (1,1) double = 0
        CacheSeq  (1,1) double = 0
    end

    properties (Dependent)
        WriteHead    % monotonic count of samples written this block (0 = empty)
        BlockSeq     % increments on every reset() (new block boundary)
        NumValid     % samples currently retained (min(WriteHead,MaxLength))
    end

    methods
        function obj = RingBuffer(cfg,writable)
            if nargin < 2 || isempty(writable), writable = false; end
            obj.Writable  = logical(writable);
            obj.MaxLength = cfg.maxInputBufferLength;

            mabr.acq.RingBuffer.ensure_file(cfg.signalBufferFile, ...
                @() zeros(obj.MaxLength,1,'single'));
            mabr.acq.RingBuffer.ensure_file(cfg.timingBufferFile, ...
                @() zeros(obj.MaxLength,1,'single'));
            mabr.acq.RingBuffer.ensure_file(cfg.headerFile, ...
                @() zeros(1,2,'uint32'));

            obj.mapSignal = memmapfile(cfg.signalBufferFile, ...
                'Writable',obj.Writable,'Format','single','Repeat',Inf);
            obj.mapTiming = memmapfile(cfg.timingBufferFile, ...
                'Writable',obj.Writable,'Format','single','Repeat',Inf);
            obj.mapHeader = memmapfile(cfg.headerFile, ...
                'Writable',obj.Writable,'Repeat',1, ...
                'Format',{ ...
                    'uint32',[1 1],'WriteHead'; ...
                    'uint32',[1 1],'BlockSeq'});

            % Seed the writer cache from whatever is on disk (reset() will
            % zero the head and bump the sequence at the next block).
            obj.CacheHead = double(obj.mapHeader.Data.WriteHead);
            obj.CacheSeq  = double(obj.mapHeader.Data.BlockSeq);
        end

        % --- Header accessors -----------------------------------------------
        function v = get.WriteHead(obj)
            if obj.Writable, v = obj.CacheHead;
            else,            v = double(obj.mapHeader.Data.WriteHead); end
        end

        function v = get.BlockSeq(obj)
            if obj.Writable, v = obj.CacheSeq;
            else,            v = double(obj.mapHeader.Data.BlockSeq); end
        end

        function v = get.NumValid(obj)
            v = min(obj.WriteHead,obj.MaxLength);
        end

        % --- Worker-side writing --------------------------------------------
        function reset(obj)
            % Mark the start of a new block: clear the write head and bump the
            % block sequence so the client can detect the boundary.
            obj.assert_writable();
            obj.CacheHead = 0;
            obj.CacheSeq  = obj.CacheSeq + 1;
            obj.mapHeader.Data.WriteHead = uint32(0);
            obj.mapHeader.Data.BlockSeq  = uint32(obj.CacheSeq);
        end

        function writeFrame(obj,sigFrame,timFrame)
            % Append one frame to both channels, wrapping within the circular
            % buffer (splitting the write across the end when needed). One
            % header write per call. Analogue of the legacy acquire_block.m
            % buffer bookkeeping.
            obj.assert_writable();

            s = single(sigFrame(:));
            t = single(timFrame(:));
            n = numel(s);

            start0 = mod(obj.CacheHead,obj.MaxLength);   % 0-based physical start
            if start0 + n <= obj.MaxLength
                obj.mapSignal.Data(start0+1:start0+n) = s;
                obj.mapTiming.Data(start0+1:start0+n) = t;
            else
                first = obj.MaxLength - start0;
                obj.mapSignal.Data(start0+1:obj.MaxLength) = s(1:first);
                obj.mapTiming.Data(start0+1:obj.MaxLength) = t(1:first);
                obj.mapSignal.Data(1:n-first) = s(first+1:end);
                obj.mapTiming.Data(1:n-first) = t(first+1:end);
            end

            obj.CacheHead = obj.CacheHead + n;
            obj.mapHeader.Data.WriteHead = uint32(obj.CacheHead);
        end

        % --- Reader-side slicing --------------------------------------------
        function y = readSignal(obj,lo,hi)
            % Slice signal samples for the monotonic absolute range [lo hi].
            if nargin < 2, lo = max(1,obj.WriteHead-obj.NumValid+1); end
            if nargin < 3, hi = obj.WriteHead; end
            y = obj.read_range(obj.mapSignal,lo,hi);
        end

        function y = readTiming(obj,lo,hi)
            if nargin < 2, lo = max(1,obj.WriteHead-obj.NumValid+1); end
            if nargin < 3, hi = obj.WriteHead; end
            y = obj.read_range(obj.mapTiming,lo,hi);
        end

        function [sig,tim] = readBlock(obj)
            % Return the whole retained block in chronological order (oldest
            % surviving sample first). Used at finalization.
            head = obj.WriteHead;
            nv   = obj.NumValid;
            if nv < 1, sig = single([]); tim = single([]); return; end
            lo  = head - nv + 1;
            sig = obj.read_range(obj.mapSignal,lo,head);
            tim = obj.read_range(obj.mapTiming,lo,head);
        end

        function y = readSignalAt(obj,idx)
            % Read signal samples at arbitrary (possibly matrix) monotonic
            % absolute indices, preserving the shape of idx.
            y = obj.mapSignal.Data(obj.wrap_index(idx));
        end

        function y = readTimingAt(obj,idx)
            y = obj.mapTiming.Data(obj.wrap_index(idx));
        end
    end

    methods (Access = private)
        function assert_writable(obj)
            assert(obj.Writable,'mabr:acq:RingBuffer:readOnly', ...
                'This RingBuffer was opened read-only and cannot be written.');
        end

        function p = wrap_index(obj,idx)
            % Map monotonic absolute indices to physical 1-based storage.
            p = mod(idx-1,obj.MaxLength) + 1;
        end

        function y = read_range(obj,map,lo,hi)
            % Read the contiguous monotonic range [lo hi] from a mapped
            % channel, spanning at most one physical wrap, as a column vector.
            n = hi - lo + 1;
            if n <= 0, y = single([]); return; end
            p0 = mod(lo-1,obj.MaxLength);     % 0-based physical start
            if p0 + n <= obj.MaxLength
                y = map.Data(p0+1:p0+n);
            else
                first = obj.MaxLength - p0;
                y = [map.Data(p0+1:obj.MaxLength); map.Data(1:n-first)];
            end
            y = y(:);
        end
    end

    methods (Static, Access = private)
        function ensure_file(ffn,makeData)
            % Create a binary file of the correct size/type if it does not yet
            % exist (the client typically creates it before the worker opens).
            if exist(ffn,'file') == 2, return; end
            [fid,msg] = fopen(ffn,'wb');
            if fid == -1
                error('mabr:acq:RingBuffer:cannotOpenFile', ...
                    'Cannot create "%s": %s.',ffn,msg);
            end
            data = makeData();
            fwrite(fid,data,class(data));
            fclose(fid);
        end
    end
end
