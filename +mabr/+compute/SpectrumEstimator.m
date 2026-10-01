classdef SpectrumEstimator < handle
% mabr.compute.SpectrumEstimator  Welch power spectrum of the newest input.
%
%   The spectrum window (mabr.ui.SpectrumViewer) shows the power spectral
%   density of the RAW recorded signal -- what the electrodes and amplifier
%   deliver before any display filter -- which is where electrical noise is
%   diagnosed: mains at 50/60 Hz and its harmonics, a switching supply at tens
%   of kHz, a monitor's line rate. This is the estimate behind it.
%
%   Welch's method: Hann-windowed segments of L = round(fs/Resolution)
%   samples, each hop = floor(L/2) apart, the mean of each segment removed,
%   and the periodograms of the newest MaxSegments complete segments
%   averaged. One-sided, in V^2/Hz, so sum(P)*df is the signal's variance
%   (Parseval) and the power in a line is the sum of the bins it occupies.
%
%   INCREMENTAL. Segments sit on a fixed grid in absolute samples -- segment
%   j covers [j*hop+1, j*hop+L] of the block -- so a segment already
%   transformed is the same segment at the next refresh, and its periodogram
%   is cached. A refresh transforms only the segments completed since the
%   last one: at the window's 1 s refresh that is two FFTs, whatever the
%   averaging, where recomputing the lot would be up to sixteen -- on the GUI
%   thread, during a run, beside the 20 Hz live view. The average is still
%   formed from every cached column in one sum, so an estimate built a slice
%   at a time is BIT-IDENTICAL to welch() over the same samples.
%
%       e = mabr.compute.SpectrumEstimator(fs,1,4);   % 1 Hz bins, 4 averages
%       [f,P,info] = e.update(x,head,seq,gain);       % x ends at sample head
%       [f,P,info] = mabr.compute.SpectrumEstimator.welch(x,fs,1,4,gain);
%
%   update's x is the newest samples of a block, ending at its absolute
%   sample `head` (mabr.acq.RingBuffer.WriteHead), and `seq` names the block
%   (BlockSeq): a new block starts the cache over. `gain` (default 1) is the
%   external amplifier's, and P is divided by gain^2 -- the periodograms are
%   cached in converter units, so a change of gain costs nothing.
%
%   See also mabr.ui.SpectrumViewer, mabr.metrics.noise_summary.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = immutable)
        SampleRate  (1,1) double
        SegmentLength (1,1) double     % L, samples
        Hop         (1,1) double       % samples between segment starts
        MaxSegments (1,1) double       % how many are averaged, at most
    end

    properties (SetAccess = private)
        Frequency   (:,1) double       % Hz, one per bin
        Resolution  (1,1) double       % Hz between bins, fs/L
        ENBW        (1,1) double       % the window's equivalent noise bandwidth, Hz
        % The block the cache belongs to (BlockSeq), and the segments in it,
        % ascending, with one periodogram per column (converter units^2/Hz).
        Seq         (1,1) double = NaN
        SegIndex    (1,:) double = zeros(1,0)
        Periodograms           = []
        % Segments transformed over this object's life: a test's evidence
        % that a refresh costs what arrived since the last, not the average.
        FFTCount    (1,1) double = 0
    end

    properties (Access = private)
        Window      (:,1) double
        Scale       (1,1) double       % 1/(fs*sum(w.^2))
        NumBins     (1,1) double
    end

    methods
        function obj = SpectrumEstimator(fs,resolution,maxSegments)
            assert(isnumeric(fs) && isscalar(fs) && fs > 0 && isfinite(fs), ...
                'mabr:compute:SpectrumEstimator:rate','The sample rate must be a positive number.');
            assert(isnumeric(resolution) && isscalar(resolution) && resolution > 0 ...
                && isfinite(resolution),'mabr:compute:SpectrumEstimator:resolution', ...
                'The resolution must be a positive number of Hz.');
            if nargin < 3 || isempty(maxSegments), maxSegments = 4; end
            assert(isnumeric(maxSegments) && isscalar(maxSegments) && maxSegments >= 1 ...
                && mod(maxSegments,1) == 0,'mabr:compute:SpectrumEstimator:segments', ...
                'The number of averages must be a positive whole number.');

            L = max(8,round(fs/resolution));
            obj.SampleRate    = fs;
            obj.SegmentLength = L;
            obj.Hop           = floor(L/2);
            obj.MaxSegments   = maxSegments;
            obj.Resolution    = fs/L;

            % Periodic Hann: the Welch convention, and the one whose bins a
            % tone centred on a bin occupies exactly three of.
            w = 0.5 - 0.5*cos(2*pi*(0:L-1)'/L);
            obj.Window    = w;
            obj.Scale     = 1/(fs*sum(w.^2));
            obj.ENBW      = fs*sum(w.^2)/sum(w)^2;
            obj.NumBins   = floor(L/2) + 1;
            obj.Frequency = (0:obj.NumBins-1)'*obj.Resolution;
        end

        function n = samplesWanted(obj)
            % How many of the newest samples a full average spans.
            n = obj.SegmentLength + (obj.MaxSegments-1)*obj.Hop;
        end

        function reset(obj)
            obj.Seq          = NaN;
            obj.SegIndex     = zeros(1,0);
            obj.Periodograms = [];
        end

        function [f,P,info] = update(obj,x,head,seq,gain)
            % The Welch average over the newest complete segments in x, the
            % samples of block `seq` that end at its absolute sample `head`.
            % P is [] (and info.Segments 0) while not one segment has been
            % completed yet.
            if nargin < 3 || isempty(head), head = numel(x); end
            if nargin < 4 || isempty(seq),  seq  = 1; end
            if nargin < 5 || isempty(gain), gain = 1; end
            x = x(:);
            L = obj.SegmentLength;
            h = obj.Hop;

            % A new block is new data: nothing cached describes it.
            if ~isequal(seq,obj.Seq)
                obj.reset();
                obj.Seq = seq;
            end

            first = head - numel(x) + 1;               % absolute sample of x(1)
            jMax  = floor((head - L)/h);               % newest complete segment
            jMin  = ceil((first - 1)/h);               % oldest wholly inside x
            want  = max(jMin,jMax-obj.MaxSegments+1):jMax;
            want  = want(want >= 0);

            % Keep what is still wanted, transform what is not cached yet.
            keep = ismember(obj.SegIndex,want);
            obj.SegIndex     = obj.SegIndex(keep);
            if isempty(obj.Periodograms)
                obj.Periodograms = zeros(obj.NumBins,0);
            else
                obj.Periodograms = obj.Periodograms(:,keep);
            end
            nNew = 0;
            for j = want(~ismember(want,obj.SegIndex))
                i0 = j*h + 1 - first + 1;              % within x
                obj.Periodograms(:,end+1) = obj.periodogram(x(i0:i0+L-1));
                obj.SegIndex(end+1) = j;
                nNew = nNew + 1;
            end
            [obj.SegIndex,ord] = sort(obj.SegIndex);
            obj.Periodograms   = obj.Periodograms(:,ord);
            obj.FFTCount       = obj.FFTCount + nNew;

            f = obj.Frequency;
            n = numel(obj.SegIndex);
            if n == 0
                P = [];
            else
                P = sum(obj.Periodograms,2)/n/gain^2;
            end
            info = struct('Segments',n,'NewSegments',nNew, ...
                'SegmentLength',L,'Resolution',obj.Resolution,'ENBW',obj.ENBW, ...
                'Duration',(L + max(0,n-1)*h)/obj.SampleRate, ...
                'Head',head,'Seq',seq,'Gain',gain, ...
                'Needed',obj.samplesWanted(),'Available',min(numel(x),head));
        end
    end

    methods (Static)
        function [f,P,info] = welch(x,fs,resolution,maxSegments,gain)
            % One-shot: the same estimate over the whole of x, its segments
            % on the same grid (x(1) is sample 1). What update() is held
            % against, and the call for offline use.
            if nargin < 4, maxSegments = []; end
            if nargin < 5 || isempty(gain), gain = 1; end
            e = mabr.compute.SpectrumEstimator(fs,resolution,maxSegments);
            [f,P,info] = e.update(x,numel(x),1,gain);
        end
    end

    methods (Access = private)
        function p = periodogram(obj,s)
            % One segment's one-sided periodogram. The segment's own mean is
            % removed first: a converter's DC offset is millivolts where the
            % noise of interest is microvolts, and the window's sidelobes
            % would carry it into the lowest bins, mains included.
            s = double(s);
            s = s - mean(s);
            X = fft(s.*obj.Window);
            p = abs(X(1:obj.NumBins)).^2*obj.Scale;
            % Every bin but DC (and, for an even L, Nyquist) stands for its
            % negative-frequency twin too.
            if mod(obj.SegmentLength,2) == 0
                p(2:end-1) = 2*p(2:end-1);
            else
                p(2:end) = 2*p(2:end);
            end
        end
    end
end
