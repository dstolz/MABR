classdef RingBuffer < handle
% mabr.acq.RingBuffer  Thin wrapper over the memory-mapped sample buffers
% shared between the acquisition worker (writer) and the GUI client (reader).
%
%   This is the single memory-mapped surface retained from the legacy
%   two-process design. It replaces input_buffer.dat / input_timing.dat and
%   the BufferIndex fields of mabr_com.dat with:
%       * signalBufferFile - recorded signal channel (single, maxLen)
%       * timingBufferFile - recorded timing channel (single, maxLen)
%       * headerFile       - tiny header holding the circular write head
%
%   The worker opens it writable and appends frames with writeFrame(); the
%   client opens it read-only and slices new samples with readSignal()/
%   readTiming(). Commands and state travel over DataQueues, NOT through here.
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
    end

    properties (Dependent)
        WriteHead    % index of the most recently written sample (0 = empty)
        FrameStart   % index of the first sample of the last written frame
        WrapCount    % number of times the circular buffer has wrapped
        BlockSeq     % increments on every reset() (new block boundary)
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
                @() zeros(1,4,'uint32'));

            obj.mapSignal = memmapfile(cfg.signalBufferFile, ...
                'Writable',obj.Writable,'Format','single','Repeat',Inf);
            obj.mapTiming = memmapfile(cfg.timingBufferFile, ...
                'Writable',obj.Writable,'Format','single','Repeat',Inf);
            obj.mapHeader = memmapfile(cfg.headerFile, ...
                'Writable',obj.Writable,'Repeat',1, ...
                'Format',{ ...
                    'uint32',[1 1],'WriteHead'; ...
                    'uint32',[1 1],'FrameStart'; ...
                    'uint32',[1 1],'WrapCount'; ...
                    'uint32',[1 1],'BlockSeq'});
        end

        % --- Header accessors -----------------------------------------------
        function v = get.WriteHead(obj),  v = double(obj.mapHeader.Data.WriteHead);  end
        function v = get.FrameStart(obj), v = double(obj.mapHeader.Data.FrameStart); end
        function v = get.WrapCount(obj),  v = double(obj.mapHeader.Data.WrapCount);  end
        function v = get.BlockSeq(obj),   v = double(obj.mapHeader.Data.BlockSeq);   end

        % --- Worker-side writing --------------------------------------------
        function reset(obj)
            % Mark the start of a new block: clear the write head and bump the
            % block sequence so the client can detect the boundary.
            obj.assert_writable();
            obj.mapHeader.Data.WriteHead  = uint32(0);
            obj.mapHeader.Data.FrameStart = uint32(0);
            obj.mapHeader.Data.WrapCount  = uint32(0);
            obj.mapHeader.Data.BlockSeq   = obj.mapHeader.Data.BlockSeq + 1;
        end

        function [idx,k] = writeFrame(obj,sigFrame,timFrame)
            % Append one frame to both channels, wrapping at the end of the
            % circular buffer. Returns the [start end] index of the write.
            % Analogue of the legacy acquire_block.m buffer bookkeeping.
            obj.assert_writable();

            n   = numel(sigFrame);
            idx = obj.mapHeader.Data.WriteHead + 1;
            k   = idx + n - 1;

            % wrap to the beginning when the next frame would run off the end,
            % leaving a one-frame margin (as in the legacy acquire_block loop)
            if k > obj.MaxLength - n
                idx = 1;
                k   = n;
                obj.mapHeader.Data.WrapCount = obj.mapHeader.Data.WrapCount + 1;
            end

            obj.mapSignal.Data(idx:k) = single(sigFrame(:));
            obj.mapTiming.Data(idx:k) = single(timFrame(:));

            obj.mapHeader.Data.FrameStart = uint32(idx);
            obj.mapHeader.Data.WriteHead  = uint32(k);
        end

        % --- Reader-side slicing --------------------------------------------
        function y = readSignal(obj,lo,hi)
            % Slice signal samples [lo hi] directly from mapped memory.
            if nargin < 2, lo = 1; end
            if nargin < 3, hi = obj.WriteHead; end
            if hi < lo, y = single([]); return; end
            y = obj.mapSignal.Data(lo:hi);
        end

        function y = readTiming(obj,lo,hi)
            if nargin < 2, lo = 1; end
            if nargin < 3, hi = obj.WriteHead; end
            if hi < lo, y = single([]); return; end
            y = obj.mapTiming.Data(lo:hi);
        end

        function y = readSignalAt(obj,idx)
            % Read signal samples at arbitrary (possibly matrix) indices,
            % preserving the shape of idx. Used for scattered sweep windows.
            y = obj.mapSignal.Data(idx);
        end

        function y = readTimingAt(obj,idx)
            y = obj.mapTiming.Data(idx);
        end
    end

    methods (Access = private)
        function assert_writable(obj)
            assert(obj.Writable,'mabr:acq:RingBuffer:readOnly', ...
                'This RingBuffer was opened read-only and cannot be written.');
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
