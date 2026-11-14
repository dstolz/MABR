classdef OnsetTracker < handle
% mabr.metrics.OnsetTracker  find_timing_onsets over a timing channel that
% arrives a slice at a time -- with the same answer as one call over the whole.
%
%   t = mabr.metrics.OnsetTracker(shadowSamples,threshold,rearmSamples);
%   new = t.feed(slice1);      % absolute onsets found in slice1
%   new = t.feed(slice2);      % ...in slice2, which follows slice1
%   all = t.onsets();          % every onset so far
%
%   The onsets are 1-based ABSOLUTE indices into the concatenation of every
%   slice fed, and t.onsets() after the last slice is exactly
%
%       mabr.metrics.find_timing_onsets([slice1; slice2; ...], ...
%           shadowSamples,threshold,rearmSamples)
%
%   whatever the slicing -- one sample at a time included (for a whole of at
%   least two samples, the length find_timing_onsets needs to say anything).
%   That equivalence is the point of the class: a run longer than the
%   acquisition ring buffer can never be read whole, so its onsets are
%   recovered as it streams (mabr.compute.RunArchive), and they must be the
%   onsets a whole read would have found. Each of find_timing_onsets' three
%   rules is local, so the state carried between slices is small:
%
%     crossing  a sample at or above threshold after one below it (or the
%               very first sample, when it is above) -- needs the previous
%               sample's verdict (PrevAbove)
%     re-arm    a crossing counts only when the channel has been below
%               threshold for rearmSamples since the last fall -- needs the
%               last fall (LastFall)
%     shadow    a crossing closer than shadowSamples to the previous one that
%               passed the re-arm rule is merged into it -- compared with
%               that previous crossing whether or not it was itself kept,
%               which is how find_timing_onsets' diff() reads them (LastCand)
%
%   mabr.metrics.extract_sweeps' own incremental detection compares a slice's
%   first crossing with the last KEPT onset instead, which agrees with the
%   whole-vector answer except where three crossings fall within a shadow of
%   one another; this class does not make that approximation.
%
%   See also mabr.metrics.find_timing_onsets, mabr.compute.RunArchive.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Shadow    (1,1) double = 1     % samples
        Threshold (1,1) double = 0.1
        Rearm     (1,1) double = 0     % samples
        Seen      (1,1) double = 0     % samples fed so far
        NumOnsets (1,1) double = 0
    end

    properties (Access = private)
        PrevAbove (1,1) logical = false
        HasFall   (1,1) logical = false
        LastFall  (1,1) double  = 0
        LastCand  (1,1) double  = -Inf
        Buf = zeros(0,1)               % onsets, with spare capacity
    end

    methods
        function obj = OnsetTracker(shadowSamples,threshold,rearmSamples)
            % The same defaults as find_timing_onsets.
            if nargin >= 1 && ~isempty(shadowSamples), obj.Shadow    = shadowSamples; end
            if nargin >= 2 && ~isempty(threshold),     obj.Threshold = threshold;     end
            if nargin >= 3 && ~isempty(rearmSamples),  obj.Rearm     = rearmSamples;  end
        end

        function new = feed(obj,timing)
            % The next samples of the channel, contiguous with those fed
            % before. Returns the onsets found in them, absolute, as a column.
            new = zeros(0,1);
            n = numel(timing);
            if n == 0, return; end
            above = mabr.metrics.OnsetTracker.aboveThreshold(timing,obj.Threshold);
            prev  = [obj.PrevAbove; above(1:end-1)];
            a0    = obj.Seen;                          % x(1) is absolute a0+1
            cand  = a0 + find(above & ~prev);
            falls = a0 + find(~above & prev);

            % Re-arm: the low run before each crossing, from the last fall
            % before it -- in this slice, or carried from an earlier one. A
            % crossing with no fall before it passes, as in the whole vector.
            if obj.Rearm > 1 && ~isempty(cand)
                allF = falls;
                if obj.HasFall, allF = [obj.LastFall; falls]; end
                if ~isempty(allF)
                    [~,~,bin] = histcounts(cand,[allF; Inf]);
                    was = bin > 0;
                    low = Inf(size(cand));
                    low(was) = cand(was) - allF(bin(was));
                    cand = cand(low >= obj.Rearm);
                end
            end

            % Shadow: each crossing against the previous one that passed the
            % re-arm rule. The first ever is always kept (-Inf before it).
            if ~isempty(cand)
                keep = (cand - [obj.LastCand; cand(1:end-1)]) >= obj.Shadow;
                new  = cand(keep);
                obj.LastCand = cand(end);
            end

            obj.PrevAbove = above(end);
            if ~isempty(falls)
                obj.LastFall = falls(end);
                obj.HasFall  = true;
            end
            obj.Seen = a0 + n;
            obj.append(new);
        end

        function o = onsets(obj)
            % Every onset found so far, absolute, as a column.
            o = obj.Buf(1:obj.NumOnsets);
        end
    end

    methods (Access = private)
        function append(obj,new)
            k = numel(new);
            if k == 0, return; end
            need = obj.NumOnsets + k;
            if need > numel(obj.Buf)
                b = zeros(max([need, 2*numel(obj.Buf), 1024]),1);
                b(1:obj.NumOnsets) = obj.Buf(1:obj.NumOnsets);
                obj.Buf = b;
            end
            obj.Buf(obj.NumOnsets+1:need) = new;
            obj.NumOnsets = need;
        end
    end

    methods (Static)
        function above = aboveThreshold(timing,threshold)
            % find_timing_onsets' own comparison, sample for sample: on
            % single samples against the smallest single at or above the
            % threshold, otherwise on the positive part in double.
            if threshold > 0 && isa(timing,'single')
                t = single(threshold);
                if double(t) < threshold, t = t + eps(t); end
                above = timing(:) >= t;
            else
                d = double(timing(:));
                d(d < 0) = 0;
                above = d >= threshold;
            end
        end
    end
end
