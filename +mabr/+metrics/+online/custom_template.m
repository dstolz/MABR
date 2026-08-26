function v = custom_template(ctx)
% custom_template  Template for a user-defined online-analysis metric.
%
%   COPY THIS FILE, rename it, and pick it from the Metric menu of an online
%   analysis window (mabr.ui.MetricPlot -- the toolbar's chart button, or the
%   Analysis button on the live plot). It is checked against the contract by
%   mabr.metrics.online.validate the moment you select it, so a mistake here
%   is a dialog at selection time, not an error on every refresh.
%
%   THE CONTRACT
%       v = my_metric(ctx)   ->   ONE numeric scalar, in whatever unit you
%                                 want the axis to read. NaN means "not
%                                 enough data yet" and is drawn as a gap.
%
%   It is called once per stimulus condition per refresh (1 Hz by default,
%   adjustable), on the GUI thread, during acquisition. Keep it pure: no
%   figures, no files, no persistent state.
%
%   WHAT ctx HOLDS (mabr.metrics.online.context is the authoritative list):
%       ctx.Sweeps      [nSamples x nSweeps] clean sweeps IN the analysis
%                       window, volts, filtered as the live view shows them
%       ctx.Mean        [nSamples x 1] their average, volts
%       ctx.Time        [nSamples x 1] MILLISECONDS re stimulus onset
%       ctx.SampleRate  Hz
%       ctx.Baseline    [nPre x nSweeps] pre-onset samples ([] once the run
%                       has been finalized -- a saved sweep starts at onset)
%       ctx.AllSweeps / ctx.AllTime   the unwindowed sweeps and their time
%       ctx.NumSweeps / ctx.NumTotal / ctx.NumArtifacts / ctx.ArtifactRate
%       ctx.Label / ctx.ID            what the condition is called
%       ctx.Params      struct of its informative parameters, e.g.
%                       ctx.Params.Frequency, ctx.Params.Level
%       ctx.Live        true while the run producing it is still streaming
%       ctx.Window      [t0 t1] ms, the window that was applied
%
%   Develop it at the command line without an acquisition:
%       ctx = mabr.metrics.online.sampleContext;
%       v   = custom_template(ctx)
%
%   See also mabr.metrics.online.catalog (the built-ins, worth reading as
%   worked examples), mabr.metrics.online.validate, mabr.ui.MetricPlot.
%
% Daniel Stolzberg (c) 2019-2026

% ---- example: RMS of the average over the first 5 ms of the window, in uV,
%      normalized by the residual noise. Replace everything below. ---------

v = NaN;
if isempty(ctx.Mean) || size(ctx.Sweeps,2) < 2, return; end

early = ctx.Time <= ctx.Time(1) + 5;
sig   = sqrt(mean(ctx.Mean(early).^2,'omitnan'));

noise = mean(ctx.Sweeps(:,1:2:end),2,'omitnan') - ...
        mean(ctx.Sweeps(:,2:2:end),2,'omitnan');
noise = sqrt(mean(noise.^2,'omitnan'));

if noise <= 0, return; end
v = sig/noise;
end
