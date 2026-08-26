function ctx = context(sweeps,t,Fs,info)
% mabr.metrics.online.context  Build the canonical context struct handed to
% an online-analysis metric. THIS IS THE CONTRACT every metric function is
% called under: it receives exactly one struct with the fields below and
% returns a single numeric scalar (NaN = "not available yet").
%
%   ctx = mabr.metrics.online.context(sweeps,t,Fs,info)
%
%   Inputs
%     sweeps  [nSamples x nSweeps] the condition's ARTIFACT-CLEAN sweeps, in
%             volts, filtered by whatever mabr.FilterPolicy was in force. One
%             column per sweep -- the orientation mabr.metrics.rms_metric,
%             mabr.metrics.snr and mabr.metrics.mean_pairwise_corr all take.
%     t       [nSamples x 1] time of each row, SECONDS relative to stimulus
%             onset. May start negative: sweeps recovered live carry the
%             pre-onset baseline as part of the same contiguous segment,
%             while a finalized mabr.data.Recording starts at the onset.
%     Fs      sample rate (Hz) of those samples (the ADC rate).
%     info    struct of everything the samples cannot say for themselves:
%               Window        [t0 t1] ms, the analysis window (default: all)
%               Label         char, what to call the condition
%               ID            char, the stimulus ID
%               Params        struct of the stimulus's informative parameters
%               NumTotal      sweeps acquired INCLUDING rejected ones
%               NumArtifacts  sweeps rejected as artifact
%               Live          true while the run is still streaming
%
%   The returned struct, which is what a metric sees:
%
%     WINDOWED (what a metric normally measures) -- the rows of `sweeps`
%     whose time falls inside info.Window:
%       Sweeps        [nWinSamples x nSweeps] volts
%       Mean          [nWinSamples x 1] mean of those sweeps, volts
%       Time          [nWinSamples x 1] MILLISECONDS re onset. Milliseconds,
%                     not seconds, because the one thing a metric reports in
%                     time -- a latency -- is quoted in ms everywhere else in
%                     MABR (the trace inspector, the wave table, the live
%                     view's time base), and a metric returning seconds there
%                     would be wrong by a factor of a thousand in a plot
%                     nobody would think to check.
%       SampleRate    Hz
%
%     UNWINDOWED (for a metric that needs what the window excluded):
%       AllSweeps     [nSamples x nSweeps] every sample handed in
%       AllTime       [nSamples x 1] ms
%       Baseline      [nPre x nSweeps] the samples BEFORE the onset, empty
%                     when the sweeps start at it (a finalized Recording
%                     does; the live path does not)
%
%     BOOKKEEPING:
%       NumSweeps     clean sweeps contributing to Mean
%       NumTotal      sweeps acquired, rejected ones included
%       NumArtifacts  sweeps rejected as artifact
%       ArtifactRate  percent of NumTotal rejected (NaN with no sweeps)
%       Label / ID    what the condition is called
%       Params        struct of its informative parameters (numeric scalars)
%       Live          true while the run producing it is still streaming
%       Window        [t0 t1] ms, as requested
%
%   A metric is a PURE FUNCTION of this struct: no side effects, no figures,
%   no state. It is called once per condition per refresh (1 Hz or slower by
%   default), so it may be more expensive than an advance criterion -- but it
%   runs on the GUI thread during acquisition, so keep it sane.
%
%   See also mabr.metrics.online.catalog, mabr.metrics.online.validate,
%   mabr.metrics.online.custom_template, mabr.ui.MetricPlot.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 4 || isempty(info), info = struct(); end

sweeps = double(sweeps);
t      = double(t(:));
if isempty(sweeps), sweeps = zeros(numel(t),0); end

ms  = t*1000;
win = getfield_or(info,'Window',[]);
if isempty(win) || numel(win) ~= 2 || ~all(isfinite(win))
    win = [ms(1) ms(end)];
    if isempty(ms), win = [0 0]; end
end

sel = ms >= win(1) & ms <= win(2);
if ~any(sel), sel = true(size(ms)); end     % an empty window measures nothing

ctx = struct();
ctx.Sweeps     = sweeps(sel,:);
ctx.Time       = ms(sel);
ctx.SampleRate = Fs;
if isempty(ctx.Sweeps)
    % No sweeps is not a mean of zero: NaN is the honest answer, and it is
    % what every metric below already treats as "nothing to report yet".
    ctx.Mean = nan(nnz(sel),1);
else
    ctx.Mean = mean(ctx.Sweeps,2,'omitnan');
end

ctx.AllSweeps = sweeps;
ctx.AllTime   = ms;
ctx.Baseline  = sweeps(ms < 0,:);

ctx.NumSweeps    = size(sweeps,2);
ctx.NumTotal     = getfield_or(info,'NumTotal',ctx.NumSweeps);
ctx.NumArtifacts = getfield_or(info,'NumArtifacts',0);
if ctx.NumTotal > 0
    ctx.ArtifactRate = 100*ctx.NumArtifacts/ctx.NumTotal;
else
    ctx.ArtifactRate = NaN;
end

ctx.Label  = char(getfield_or(info,'Label',''));
ctx.ID     = char(getfield_or(info,'ID',''));
ctx.Params = getfield_or(info,'Params',struct());
ctx.Live   = logical(getfield_or(info,'Live',false));
ctx.Window = win;
end


% =====================================================================
function v = getfield_or(s,f,dflt)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
    v = s.(f);
else
    v = dflt;
end
end
