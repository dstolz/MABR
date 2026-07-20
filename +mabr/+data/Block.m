classdef Block
% mabr.data.Block  One stimulus condition's acquired result.
%
%   A value container bundling everything produced for one stimulus: the
%   stimulus metadata handed in by the external stimulus package, the recorded
%   ADC signal channel (a mabr.data.Recording), optional timing channel,
%   computed live metrics, and the start time of the run it came from.
%
%   One acquisition run yields one Block per stimulus it presented — usually
%   just one (blocked strategies), but an intermixed run is de-interleaved by
%   mabr.ui.AcqController into a Block per stimulus ID.
%
%   Stim is struct('Meta',...,'SampleRate',...), where Meta comes from
%   mabr.stim.StimulusSet.meta: the stimulus ID plus every passthrough field
%   the external package supplied, with informativeParams/Label driving
%   display and the offline-compatible .abr write.
%
%   SweepPolarity records the sign (+1/-1) the stimulus was presented with at
%   each sweep, aligned element-for-element with ADC.SweepOnsets. It is all +1
%   unless the entry set alternatePolarity, and is written to the .abr file as
%   ADC.SweepPolarity so offline analysis can separate the two polarities.
%
% Daniel Stolzberg (c) 2019-2026

    properties
        Stim      (1,1) struct = struct();      % external stimulus metadata
        ADC       (1,1) mabr.data.Recording     % recorded signal channel
        Timing    (1,1) mabr.data.Recording     % recorded timing channel (optional)
        Metrics   (1,1) struct = struct();      % computed metrics
        StartTime (1,:) char = '';              % ISO-ish timestamp
        SweepPolarity (1,:) double = [];        % +1/-1 per ADC.SweepOnsets entry
    end

    properties (Dependent)
        NumSweeps
        Label
    end

    methods
        function obj = Block(stim,adc,startTime)
            if nargin >= 1 && ~isempty(stim), obj.Stim = stim; end
            if nargin >= 2 && ~isempty(adc),  obj.ADC  = adc;  end
            if nargin >= 3 && ~isempty(startTime)
                obj.StartTime = startTime;
            else
                obj.StartTime = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
            end
        end

        function n = get.NumSweeps(obj)
            n = numel(obj.ADC.SweepOnsets);
        end

        function lbl = get.Label(obj)
            if isfield(obj.Stim,'Meta') && isfield(obj.Stim.Meta,'Label')
                lbl = obj.Stim.Meta.Label;
            else
                lbl = {};
            end
        end

        function obj = computeMetrics(obj)
            % Compute the standard live metrics over the ADC sweeps using the
            % tested mabr.metrics functions (the single source of truth).
            D = obj.ADC.SweepData;      % [nSamples x nSweeps]
            m = struct();
            if isempty(D) || size(D,2) < 2
                m.corr = 0; m.rms = NaN; m.snr = NaN;
            else
                m.corr = mabr.metrics.mean_pairwise_corr(D);
                m.rms  = mabr.metrics.rms_metric(D);
                m.snr  = mabr.metrics.snr(D);
            end
            obj.Metrics = m;
        end
    end
end
