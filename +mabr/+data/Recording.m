classdef Recording
% mabr.data.Recording  One acquired channel plus segmentation/metric helpers.
%
%   A cycle-free value type that replaces abr.Buffer. It carries a channel's
%   samples and the sweep bookkeeping needed to segment them, and exposes the
%   genuinely useful dependent helpers ported from abr.Buffer (SweepData,
%   SweepMean, noisePower/SNR). Unlike abr.Buffer it holds NO back-reference
%   to a parent object (the old ABRobj handle cycle that to_struct had to
%   strip); the decimation factor is passed explicitly.
%
%   Filtering is explicit and opt-in, and lives in a mabr.FilterPolicy held
%   in the Filters property (the same object the GUI's filter dialog edits
%   and the live view applies, so what you see online and what a Block
%   reports come off one set of corners). Design the chain once with
%   designFilters(); afterwards the filtered trace is used consistently in
%   segmentation (ProcessedData -> SweepData -> SweepMean). Before
%   designFilters() is called the raw Data is used. This resolves the legacy
%   ambiguity where a bandpass/notch was designed in the live path but never
%   applied.
%
%   Data itself is NEVER filtered in place, and mabr.data.io saves Data, so
%   an .abr file always carries the raw trace whatever the chain says.
%
%   Artifacts are marked, never removed. IsArtifact flags sweeps the acquisition
%   judged contaminated; the samples stay in Data and reach the .abr file
%   untouched, but everything DESCRIPTIVE (SweepMean, noisePower/SNR, RMS) is
%   computed from CleanSweepData, the flagged sweeps excluded. Use SweepData
%   when you want every sweep regardless of verdict.
%
%   Rate/decimation convention: Data is stored at its acquisition SampleRate;
%   DecimationFactor records the DAC/ADC ratio so mabr.data.io can decimate at
%   save time (preserving the legacy save_abr_data behaviour).
%
% Daniel Stolzberg (c) 2019-2026

    properties
        SampleRate  (1,1) double {mustBePositive,mustBeFinite} = 1;   % Hz
        Data        (:,1) single = single([]);
        SweepOnsets (:,1) double {mustBeNonnegative,mustBeInteger} = [];
        SweepLength (1,1) double {mustBePositive,mustBeInteger} = 1;   % samples
        SweepValue  = [];
        IsArtifact  (:,1) logical = false(0,1);

        DecimationFactor (1,1) double {mustBePositive} = 1;

        % post-processing applied to SweepMean
        DetrendPoly (1,1) double {mustBeGreaterThanOrEqual(DetrendPoly,-1), ...
                                  mustBeLessThanOrEqual(DetrendPoly,9)} = -1;
        SmoothSpan  (1,1) double {mustBeInteger,mustBeNonnegative} = 0;

        % ADC filter chain: independent high pass / low pass / notch, held in
        % the same mabr.FilterPolicy the GUI edits and the live view applies,
        % so a Block's numbers come off the corners the operator was watching.
        % Still opt-in -- designFilters() is what puts it into effect.
        Filters (1,1) mabr.FilterPolicy = mabr.FilterPolicy;

        FFTOptions = struct('windowFcn',@flattop,'inDecibels',true);
    end

    properties (Dependent)
        N
        SweepDuration
        TimeVector
        ProcessedData      % Data with the (designed) filter chain applied
        ValidSweeps        % logical per SweepOnsets: window lies inside Data
        SweepData
        CleanSweeps        % logical per SweepData column: not flagged artifact
        CleanSweepData     % SweepData with the flagged sweeps removed
        NumSweeps
        NumCleanSweeps
        SweepMean
        noisePower
        signalPower
        RMS
        SNR
        NumArtifacts
    end

    methods
        function obj = Recording(Fs,Data,SweepOnsets,SweepLength,DecimationFactor)
            if nargin >= 1 && ~isempty(Fs),          obj.SampleRate  = Fs;           end
            if nargin >= 2 && ~isempty(Data),        obj.Data        = single(Data(:)); end
            if nargin >= 3 && ~isempty(SweepOnsets), obj.SweepOnsets = SweepOnsets(:); end
            if nargin >= 4 && ~isempty(SweepLength), obj.SweepLength = SweepLength;   end
            if nargin >= 5 && ~isempty(DecimationFactor), obj.DecimationFactor = DecimationFactor; end
        end

        % --- Filtering -----------------------------------------------------
        function obj = designFilters(obj)
            % Design the enabled sections at the current SampleRate. Call once
            % after setting SampleRate/Filters; segmentation then uses them.
            % IIR (Butterworth) designs. An FIR of any practical order cannot
            % realize a 10 Hz corner at a 12 kHz sample rate: the previous
            % order-10 'bandpassfir'/'bandstopfir' pair measured 0.0 dB at both
            % DC and 60 Hz, i.e. it removed neither baseline drift nor line
            % noise. filtfilt() in mabr.FilterPolicy.apply makes the response
            % zero-phase, so the IIR phase distortion that motivates FIR here
            % does not apply.
            obj.Filters = obj.Filters.design(obj.SampleRate);
        end

        function y = applyFilter(obj,x)
            % Apply the designed filter chain (zero-phase) to a vector.
            y = single(obj.Filters.apply(double(x(:))));
        end

        function d = get.ProcessedData(obj)
            d = obj.Filters.apply(obj.Data);    % raw until designFilters()
        end

        % --- Basic sizes ---------------------------------------------------
        function n = get.N(obj),             n = numel(obj.Data);                 end
        function d = get.SweepDuration(obj), d = obj.SweepLength./obj.SampleRate; end
        function t = get.TimeVector(obj),    t = (0:obj.SweepLength-1)'/obj.SampleRate; end
        function n = get.NumArtifacts(obj),  n = nnz(obj.IsArtifact);             end

        % --- Segmentation --------------------------------------------------
        function v = get.ValidSweeps(obj)
            % Which SweepOnsets have their whole window inside Data. A run cut
            % short can leave the last onset's window running off the end;
            % those sweeps are absent from SweepData, so anything computed
            % per-sweep (IsArtifact) must be mapped back through this mask
            % rather than assumed to align with SweepOnsets.
            idx = obj.sweep_index();
            if isempty(idx), v = false(0,1); return; end
            v = ~any(idx > obj.N | idx < 1,1)';
        end

        function s = get.SweepData(obj)
            idx = obj.sweep_index();
            if isempty(idx), s = single([]); return; end
            x = obj.ProcessedData;
            s = x(idx(:,obj.ValidSweeps));
            if size(s,2) == 1 && size(s,1) ~= obj.SweepLength, s = s'; end
        end

        function v = get.CleanSweeps(obj)
            % Which SweepData columns survived artifact rejection. IsArtifact
            % is indexed by SweepOnsets and SweepData by the subset whose
            % window fits inside Data, so the flags map through ValidSweeps.
            valid = obj.ValidSweeps;
            v     = true(1,nnz(valid));
            bad   = obj.IsArtifact;
            if numel(bad) == numel(obj.SweepOnsets) && any(bad)
                v = ~reshape(bad(valid),1,[]);
            end
        end

        function s = get.CleanSweepData(obj)
            % The sweeps anything descriptive should be computed from. Flagged
            % sweeps stay in Data (and in the saved .abr) so an offline
            % reanalysis can overrule the call, but they are dropped here: a
            % single electrode pop otherwise smears across the whole average.
            s = obj.SweepData;
            if isempty(s), return; end
            keep = obj.CleanSweeps;
            if ~all(keep), s = s(:,keep); end
        end

        function n = get.NumSweeps(obj)
            n = size(obj.SweepData,2);
        end

        function n = get.NumCleanSweeps(obj)
            n = size(obj.CleanSweepData,2);
        end

        function m = get.SweepMean(obj)
            % Artifact sweeps are excluded (see CleanSweepData). With every
            % sweep rejected there is nothing to average, and an all-NaN mean
            % says so rather than returning a misleading zero.
            D = obj.CleanSweepData;
            if isempty(D), m = nan(obj.SweepLength,1,'single'); return; end
            m = mean(D,2,'omitnan');

            if obj.DetrendPoly == 0
                m = m - mean(m);
            elseif obj.DetrendPoly > 0
                t = obj.TimeVector;
                [p,~,mu] = polyfit(t,m,obj.DetrendPoly);
                m = m - polyval(p,t,[],mu);
            end
            if obj.SmoothSpan > 0
                m = movmean(m,obj.SmoothSpan);
            end
        end

        % --- Metrics -------------------------------------------------------
        function r = get.noisePower(obj)
            % plus/minus averaging as a noise estimate, over the clean sweeps
            % only -- an artifact left in would be measured as noise it is not.
            x = obj.CleanSweepData;
            if size(x,2) > 1
                x = mean(x(:,1:2:end),2) - mean(x(:,2:2:end),2);
            end
            r = sqrt(mean(x.^2));
        end

        function r = get.signalPower(obj)
            r = rms(obj.SweepMean);
        end

        function r = get.SNR(obj)
            r = 20*log10(obj.signalPower./obj.noisePower);
        end

        function r = get.RMS(obj)
            r = sqrt(mean(obj.CleanSweepData.^2,'omitnan'));
        end

        % --- FFT of the mean sweep -----------------------------------------
        function [M,f] = fft(obj)
            Y = obj.SweepMean;
            Y(isnan(Y)) = [];
            L = numel(Y);
            if L < 2, M = []; f = []; return; end
            w = window(obj.FFTOptions.windowFcn,L);
            Y = fft(Y.*w);
            P2 = abs(Y/L);
            M = P2(1:floor(L/2)+1);
            M(2:end-1) = 2*M(2:end-1);
            if obj.FFTOptions.inDecibels, M = 20*log10(M); end
            f = obj.SampleRate*(0:floor(L/2))'/L;
        end

        % --- Serialization -------------------------------------------------
        function s = to_struct(obj)
            s.SampleRate       = obj.SampleRate;
            s.Data             = obj.Data;
            s.SweepOnsets      = obj.SweepOnsets;
            s.SweepLength      = obj.SweepLength;
            s.SweepValue       = obj.SweepValue;
            s.IsArtifact       = obj.IsArtifact;
            s.DecimationFactor = obj.DecimationFactor;
        end
    end

    methods (Access = private)
        function idx = sweep_index(obj)
            if isempty(obj.SweepOnsets), idx = []; return; end
            idx = (0:obj.SweepLength-1)' + obj.SweepOnsets(:)';   % [SweepLength x nSweeps]
        end
    end
end
