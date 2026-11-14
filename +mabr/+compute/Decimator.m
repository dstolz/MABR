classdef Decimator < handle
% mabr.compute.Decimator  resample(x,1,q) over a signal that arrives a piece
% at a time.
%
%   d = mabr.compute.Decimator(q);
%   y1 = d.push(x1);     % the outputs x1 completes
%   y2 = d.push(x2);     % ...and x2, which follows x1
%   yN = d.finish();     % the last outputs, once the signal has ended
%
%   [y1; y2; ...; yN] is resample(double([x1; x2; ...]),1,q): the same
%   anti-alias filter (taken from resample itself, never re-designed here),
%   the same zero-phase alignment -- output j is centred on input sample
%   1 + (j-1)*q -- the same zero padding at both ends, and the same length,
%   ceil(numel(x)/q). This is what lets a run longer than the acquisition
%   ring buffer be decimated as it streams (mabr.compute.RunArchive) and still
%   be the trace mabr.compute.Pipeline.finalize would have made by resampling
%   the whole of it at once.
%
%   HOW IT STAYS EXACT
%   resample is a call to upfirdn(x,h,1,q) with the designed filter, padded
%   in front with nz zeros so the decimation lands on the centre tap, and the
%   first `delay` outputs dropped. Here the same upfirdn runs over a buffer
%   holding only the input the next outputs need, starting on a sample
%   1 + q*s, and output j of the whole is output j + delay - s of the buffer.
%   An output is taken only once every input it reaches is in the buffer --
%   or lies beyond the signal's own ends, where the whole call sees zeros
%   too -- so each is the same sum of the same products: bit-identical to
%   resample wherever upfirdn's sum for one output does not depend on where
%   the input began, which selfCheck() confirms against resample itself on
%   the release in use (verify_run_archive asserts it).
%
%   q = 1 is resample's own special case: the input, unchanged.
%
%   See also resample, upfirdn, mabr.compute.RunArchive.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Factor (1,1) double = 1        % q
        Taps   (1,:) double = 1        % resample's filter, zero-padded as resample pads it
        Delay  (1,1) double = 0        % outputs resample drops from the front
        NumIn  (1,1) double = 0        % input samples pushed so far
        NumOut (1,1) double = 0        % outputs returned so far
        Finished (1,1) logical = false
    end

    properties (Access = private)
        Buf = zeros(0,1)               % input samples BufStart..NumIn, double
        BufStart (1,1) double = 1      % absolute index of Buf(1); always 1 + q*s
    end

    methods
        function obj = Decimator(q)
            assert(isnumeric(q) && isscalar(q) && q >= 1 && q == round(q), ...
                'mabr:compute:Decimator:factor', ...
                'The decimation factor must be a positive integer (got %s).',mat2str(q));
            obj.Factor = double(q);
            if q == 1, return; end
            [obj.Taps,obj.Delay] = mabr.compute.Decimator.design(obj.Factor);
        end

        function y = push(obj,x)
            % The next input samples. Returns, as a double column, every
            % output whose input is now all here.
            assert(~obj.Finished,'mabr:compute:Decimator:finished', ...
                'push after finish: the signal has already ended.');
            x = double(x(:));
            obj.NumIn = obj.NumIn + numel(x);
            if obj.Factor == 1
                y = x;
                obj.NumOut = obj.NumIn;
                return
            end
            obj.Buf = [obj.Buf; x];
            % The last output whose rightmost tap falls on an input already
            % here: output j reaches input (j + Delay - 1)*q + 1.
            jmax = floor((obj.NumIn - 1)/obj.Factor) - obj.Delay + 1;
            y = obj.emit(jmax);
        end

        function y = finish(obj)
            % The signal has ended: the outputs left, whose taps reach past
            % its end into the zeros resample pads it with.
            if obj.Finished, y = zeros(0,1); return; end
            obj.Finished = true;
            if obj.Factor == 1, y = zeros(0,1); return; end
            y = obj.emit(ceil(obj.NumIn/obj.Factor));
            obj.Buf = zeros(0,1);
        end
    end

    methods (Access = private)
        function y = emit(obj,jmax)
            j0 = obj.NumOut + 1;
            y  = zeros(0,1);
            if jmax < j0 || isempty(obj.Buf), return; end
            q  = obj.Factor;
            % The filter as a row, exactly as resample hands it to upfirdn.
            yc = upfirdn(obj.Buf,obj.Taps,1,q);
            s  = (obj.BufStart - 1)/q;
            y  = yc((j0:jmax)' + obj.Delay - s);
            obj.NumOut = jmax;
            % Keep only what the next output reaches back to: input
            % (j + Delay - 1)*q + 2 - numel(Taps), for j = jmax + 1, rounded
            % down onto the 1 + q*s grid the buffer has to start on.
            lo = (jmax + obj.Delay)*q + 2 - numel(obj.Taps);
            newStart = max(obj.BufStart,1 + q*floor((lo - 1)/q));
            drop = newStart - obj.BufStart;
            if drop > 0
                obj.Buf      = obj.Buf(drop+1:end);
                obj.BufStart = newStart;
            end
        end
    end

    methods (Static)
        function [taps,delay] = design(q)
            % resample's filter for 1:q, and how resample pads and aligns it.
            % The filter itself comes from resample's second output -- the
            % designed taps with its padding stripped -- so nothing here can
            % design a different one; the padding is resample's rule: nz
            % leading zeros so the decimation hits the centre tap, and the
            % first floor(ceil(Lhalf+nz)/q) outputs dropped for the filter's
            % delay.
            [~,h] = resample(zeros(64*q,1),1,q);
            h      = double(h(:)).';
            % resample returns the taps with its padding removed; any exact
            % zero left at an end would be padding by another name, and
            % would move the centre tap.
            nzIdx  = find(h);
            h      = h(nzIdx(1):nzIdx(end));
            Lhalf  = (numel(h) - 1)/2;
            nz     = floor(q - mod(Lhalf,q));
            taps   = [zeros(1,nz) h];
            delay  = floor(ceil(Lhalf + nz)/q);
        end

        function R = selfCheck(q)
            % Is this the resample of the release in use? A seeded probe
            % (never the global stream) resampled whole, and decimated here a
            % piece at a time in uneven pieces. R.Exact is bit-identity;
            % R.MaxError the largest difference relative to the probe's
            % largest output. Remembered per factor for the session.
            persistent memo
            if isempty(memo), memo = containers.Map('KeyType','double','ValueType','any'); end
            if isKey(memo,q), R = memo(q); return; end
            rs  = RandStream('mt19937ar','Seed',20261114);
            n   = 40*q*11 + 7;
            x   = randn(rs,n,1);
            ref = resample(x,1,q);
            d   = mabr.compute.Decimator(q);
            y   = zeros(0,1);
            i   = 1;
            while i <= n
                k = min(n - i + 1,randi(rs,[1 6*q*11]));
                y = [y; d.push(x(i:i+k-1))]; %#ok<AGROW>
                i = i + k;
            end
            y = [y; d.finish()];
            R = struct('Factor',q,'Exact',isequal(y,ref), ...
                'MaxError',NaN,'Length',numel(y),'Expected',numel(ref));
            if numel(y) == numel(ref)
                R.MaxError = max(abs(y - ref))/max(abs(ref));
            end
            memo(q) = R;
        end
    end
end
