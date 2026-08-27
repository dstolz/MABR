classdef PublishBuffer < handle
% mabr.compute.PublishBuffer  A double-buffered, memory-mapped table with one
% writer and any number of readers in other processes.
%
%   The discipline the compute workers publish through, held in one place
%   because the flip-and-recheck is the subtle part:
%
%     * The file holds TWO copies (halves) of every payload field plus a
%       two-word header, Seq and Half. The writer fills the IDLE half, then
%       flips Half to name it, then bumps Seq -- in that order.
%     * A reader reads Seq, reads the half Half names, and reads Seq again.
%       If Seq moved, the writer published (possibly twice) underneath it
%       and the payload may be torn: the reader keeps what it had and tries
%       again on its next poll. One poll of staleness costs nothing.
%
%   The Seq re-check is the CORRECTNESS guarantee -- it covers every field
%   read between the two, halved or not. The halves are the FAST PATH: in
%   steady state the writer and the reader never touch the same bytes, so a
%   complete read succeeds first time. Seq is uint32 and compared for
%   equality, so wrapping is harmless.
%
%   This is the same relationship mabr.acq.RingBuffer has with its files --
%   a memmapfile over a size-checked file, worker-writable and client
%   read-only -- applied to a table that changes wholesale rather than a
%   stream that appends. Subclasses (mabr.compute.LiveBuffer, MetricBuffer,
%   RequestBuffer) supply the payload layout and the two conversions between
%   a payload struct and the fields of one half.
%
%   A "half" is encoded in the SHAPE of each field, not in a third dimension:
%   a per-half matrix [m x n] is stored as [2m x n] and half h owns rows
%   h*m+1 : (h+1)*m; a per-half column [m x 1] is stored as [m x 2]. Readers
%   index the field rather than copying it -- memmapfile subscripting is
%   lazy, so a poll touches the rows it asks for and not the file.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = immutable)
        File     (1,:) char
        Writable (1,1) logical
    end

    properties (Access = protected)
        Map                          % memmapfile
    end

    properties (Access = private)
        % Writer-side cache, so publish() never reads the header back.
        WriteSeq  (1,1) double = 0
        WriteHalf (1,1) double = 0
    end

    methods
        function obj = PublishBuffer(file,format,writable)
            % format: the payload fields, {type dims name; ...}, each already
            % shaped for two halves (see the class help). The header is
            % prepended here.
            if nargin < 3 || isempty(writable), writable = false; end
            obj.File     = char(file);
            obj.Writable = logical(writable);

            fmt = [{'uint32',[1 1],'Seq'; 'uint32',[1 1],'Half'}; format];
            mabr.compute.PublishBuffer.ensure_file(obj.File, ...
                mabr.compute.PublishBuffer.format_bytes(fmt));
            obj.Map = memmapfile(obj.File,'Writable',obj.Writable, ...
                'Repeat',1,'Format',fmt);
            obj.WriteSeq  = double(obj.Map.Data.Seq);
            obj.WriteHalf = double(obj.Map.Data.Half);
        end

        % --- Writer side ----------------------------------------------------
        function zero(obj)
            % Start from nothing: a fresh worker must not leave a previous
            % session's last publish where a reader could take it for new.
            obj.assert_writable();
            obj.WriteSeq  = 0;
            obj.WriteHalf = 0;
            obj.Map.Data.Half = uint32(0);
            obj.Map.Data.Seq  = uint32(0);
        end

        function seq = publish(obj,payload)
            % Write payload into the idle half and make it current.
            obj.assert_writable();
            idle = 1 - obj.WriteHalf;
            obj.writeHalf(idle,payload);
            obj.Map.Data.Half = uint32(idle);
            obj.WriteSeq = mod(obj.WriteSeq + 1,2^32);
            obj.Map.Data.Seq = uint32(obj.WriteSeq);
            obj.WriteHalf = idle;
            seq = obj.WriteSeq;
        end

        % --- Reader side ----------------------------------------------------
        function s = seq(obj)
            % What has been published so far, cheaply -- a reader compares
            % this with the last Seq it drew before paying for a read.
            s = double(obj.Map.Data.Seq);
        end

        function [payload,seq] = read(obj)
            % The current payload and its Seq, or [] and -1 if three
            % consecutive attempts were torn by a writer publishing faster
            % than this reader reads -- keep the last good one and come back.
            for attempt = 1:3
                s1   = double(obj.Map.Data.Seq);
                half = double(obj.Map.Data.Half);
                payload = obj.readHalf(half);
                s2   = double(obj.Map.Data.Seq);
                if s1 == s2, seq = s1; return; end
            end
            payload = [];
            seq     = -1;
        end
    end

    methods (Abstract, Access = protected)
        writeHalf(obj,half,payload)     % store payload's fields into half (0/1)
        payload = readHalf(obj,half)    % read them back as the same struct
    end

    methods (Access = protected)
        function assert_writable(obj)
            assert(obj.Writable,'mabr:compute:PublishBuffer:readOnly', ...
                'This buffer was opened read-only and cannot be written.');
        end

        function r = rows(~,half,m,n)
            % The row range of half `half` in a [2m x *] field, for its
            % first n entries.
            r = half*m + (1:n);
        end
    end

    methods (Static, Access = protected)
        function ensure_file(ffn,expectBytes)
            % Create (zero-filled) or recreate a backing file of exactly the
            % expected size -- a stale file left by another layout would be
            % mapped as-is and read as nonsense. Same rule as
            % mabr.acq.RingBuffer.ensure_file.
            d = dir(ffn);
            if ~isempty(d) && d(1).bytes == expectBytes, return; end
            if ~isempty(d)
                mabr.log.vprintf(1,1, ...
                    'Compute buffer "%s" is %d bytes, expected %d; recreating.', ...
                    ffn,d(1).bytes,expectBytes);
            end
            [fid,msg] = fopen(ffn,'wb');
            if fid == -1
                error('mabr:compute:PublishBuffer:cannotOpenFile', ...
                    'Cannot create "%s": %s.',ffn,msg);
            end
            % Written in chunks: a buffer can be tens of megabytes, and one
            % zeros() call of that size for a file write is a needless spike.
            chunk = zeros(min(expectBytes,2^20),1,'uint8');
            left  = expectBytes;
            while left > 0
                n = min(left,numel(chunk));
                fwrite(fid,chunk(1:n),'uint8');
                left = left - n;
            end
            fclose(fid);
        end

        function b = format_bytes(fmt)
            % Total size of a memmapfile Format cell, in bytes.
            b = 0;
            for i = 1:size(fmt,1)
                switch fmt{i,1}
                    case {'double','int64','uint64'}, w = 8;
                    case {'single','int32','uint32'}, w = 4;
                    case {'int16','uint16'},          w = 2;
                    otherwise,                        w = 1;
                end
                b = b + w*prod(fmt{i,2});
            end
        end
    end
end
