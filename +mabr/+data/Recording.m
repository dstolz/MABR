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
%   Filtering is explicit and opt-in. Design the ADC filter chain once with
%   designFilters(); afterwards the filtered trace is used consistently in
%   segmentation (ProcessedData -> SweepData -> SweepMean). Before
%   designFilters() is called the raw Data is used. This resolves the legacy
%   ambiguity where a bandpass/notch was designed in the live path but never
%   applied.
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

        % ADC filter chain (HP 10 / LP 3000 bandpass + 60 Hz notch by default)
        UseBandpass (1,1) logical = false;
        UseNotch    (1,1) logical = false;
        FilterHP    (1,1) double {mustBePositive,mustBeFinite} = 10;    % Hz
        FilterLP    (1,1) double {mustBePositive,mustBeFinite} = 3000;  % Hz
        FilterOrder (1,1) double {mustBePositive,mustBeInteger} = 10;
        NotchFreq   (1,1) double {mustBePositive,mustBeFinite} = 60;    % Hz

        FFTOptions = struct('windowFcn',@flattop,'inDecibels',true);
    end

    properties (SetAccess = private)
        BandpassDesign = [];   % digitalFilter (designed by designFilters)
        NotchDesign    = [];   % digitalFilter
    end

    properties (Dependent)
        N
        SweepDuration
        TimeVector
        ProcessedData      % Data with the (designed) filter chain applied
        SweepData
        NumSweeps
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
            % Design the enabled filters at the current SampleRate. Call once
            % after setting SampleRate/params; segmentation then uses them.
            if obj.UseBandpass
                obj.BandpassDesign = designfilt('bandpassfir', ...
                    'FilterOrder',     obj.FilterOrder, ...
                    'CutoffFrequency1',obj.FilterHP, ...
                    'CutoffFrequency2',obj.FilterLP, ...
                    'SampleRate',      obj.SampleRate);
            else
                obj.BandpassDesign = [];
            end
            if obj.UseNotch
                obj.NotchDesign = designfilt('bandstopfir', ...
                    'FilterOrder',10, ...
                    'CutoffFrequency1',obj.NotchFreq-1, ...
                    'CutoffFrequency2',obj.NotchFreq+1, ...
                    'SampleRate',      obj.SampleRate);
            else
                obj.NotchDesign = [];
            end
        end

        function y = applyFilter(obj,x)
            % Apply the designed filter chain (zero-phase) to a vector.
            y = double(x(:));
            if numel(y) < 4, y = single(y); return; end   % too short to filtfilt
            if ~isempty(obj.BandpassDesign), y = filtfilt(obj.BandpassDesign,y); end
            if ~isempty(obj.NotchDesign),    y = filtfilt(obj.NotchDesign,y);    end
            y = single(y);
        end

        function d = get.ProcessedData(obj)
            if isempty(obj.BandpassDesign) && isempty(obj.NotchDesign)
                d = obj.Data;
            else
                d = obj.applyFilter(obj.Data);
            end
        end

        % --- Basic sizes ---------------------------------------------------
        function n = get.N(obj),             n = numel(obj.Data);                 end
        function d = get.SweepDuration(obj), d = obj.SweepLength./obj.SampleRate; end
        function t = get.TimeVector(obj),    t = (0:obj.SweepLength-1)'/obj.SampleRate; end
        function n = get.NumArtifacts(obj),  n = nnz(obj.IsArtifact);             end

        % --- Segmentation --------------------------------------------------
        function s = get.SweepData(obj)
            idx = obj.sweep_index();
            if isempty(idx), s = single([]); return; end
            x = obj.ProcessedData;
            valid = ~any(idx > obj.N | idx < 1,1);
            s = x(idx(:,valid));
            if size(s,2) == 1 && size(s,1) ~= obj.SweepLength, s = s'; end
        end

        function n = get.NumSweeps(obj)
            n = size(obj.SweepData,2);
        end

        function m = get.SweepMean(obj)
            m = mean(obj.SweepData,2,'omitnan');

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
            % plus/minus averaging as a noise estimate
            x = obj.SweepData;
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
            r = sqrt(mean(obj.SweepData.^2,'omitnan'));
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
