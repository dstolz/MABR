function C = catalog(key)
% mabr.metrics.online.catalog  The built-in online-analysis metrics.
%
%   C = mabr.metrics.online.catalog returns a struct array of every metric
%   mabr.ui.MetricPlot offers, in the order the window lists them. Each entry:
%
%       Key      short identifier, saved in a .mabrcfg / a window's prefs
%       Name     what the menu and the axis label call it
%       Units    the unit its value is in ('' for a pure number)
%       Summary  one line for the tooltip
%       Fcn      the metric itself: v = Fcn(ctx), one numeric scalar
%
%   C = mabr.metrics.online.catalog(key) returns just that entry (error
%   'mabr:metrics:online:catalog:unknown' if there is no such key).
%
%   Every metric is a pure function of the context struct built by
%   mabr.metrics.online.context -- the same struct a user-supplied metric
%   receives, so a custom one is a peer of these, not a special case. The
%   heavy lifting is delegated to the tested functions in +mabr/+metrics
%   (rms_metric, snr, mean_pairwise_corr, find_peaks) rather than
%   reimplemented here, so a number in this window and the same number in a
%   saved Block cannot disagree.
%
%   VALUES ARE RETURNED IN THE UNIT ADVERTISED, not in volts: a metric that
%   says microvolts returns microvolts. The plot labels its axis from Units
%   and exports the same numbers, so there is no scaling step anywhere
%   downstream to get wrong.
%
%   See also mabr.metrics.online.context, mabr.metrics.online.validate,
%   mabr.ui.MetricPlot.
%
% Daniel Stolzberg (c) 2019-2026

C = [ ...
    entry('rms','RMS amplitude','uV', ...
          'Root-mean-square of the averaged response in the analysis window.', ...
          @metric_rms); ...
    entry('p2p','Peak-to-peak','uV', ...
          'Largest positive minus largest negative excursion of the average.', ...
          @metric_p2p); ...
    entry('peak','Peak amplitude','uV', ...
          'Largest absolute excursion of the average.', ...
          @metric_peak); ...
    entry('latency','Peak latency','ms', ...
          'Time of the most prominent peak of the average, re stimulus onset.', ...
          @metric_latency); ...
    entry('corr','Sweep correlation','r (Fisher z)', ...
          'Mean pairwise Pearson correlation across sweeps -- response reliability.', ...
          @metric_corr); ...
    entry('splithalf','Split-half correlation','r', ...
          'Pearson correlation between the odd-sweep and even-sweep averages.', ...
          @metric_splithalf); ...
    entry('snr','SNR','dB', ...
          'Signal-to-noise ratio by plus/minus averaging (mabr.metrics.snr).', ...
          @metric_snr); ...
    entry('noise','Residual noise','uV', ...
          'RMS of the odd-minus-even difference: what is left after averaging.', ...
          @metric_noise); ...
    entry('area','Rectified area','uV*ms', ...
          'Area under the rectified average across the analysis window.', ...
          @metric_area); ...
    entry('sweeps','Clean sweeps','count', ...
          'Sweeps contributing to the average (artifact-rejected ones excluded).', ...
          @metric_sweeps); ...
    entry('artifacts','Artifact rate','%', ...
          'Percentage of acquired sweeps rejected as artifact.', ...
          @metric_artifacts)];

if nargin >= 1 && ~isempty(key)
    i = find(strcmp({C.Key},key),1);
    assert(~isempty(i),'mabr:metrics:online:catalog:unknown', ...
        'No built-in metric with key "%s".',char(key));
    C = C(i);
end
end


% ===================== the metrics themselves ========================
% Each takes the context struct (mabr.metrics.online.context) and returns one
% scalar in the unit its catalog entry advertises. NaN is the honest answer
% for "not enough data yet" and is what the plot leaves as a gap.

function v = metric_rms(ctx)
if isempty(ctx.Mean), v = NaN; return; end
v = sqrt(mean(ctx.Mean.^2,'omitnan'))*1e6;
end

function v = metric_p2p(ctx)
if isempty(ctx.Mean), v = NaN; return; end
v = (max(ctx.Mean) - min(ctx.Mean))*1e6;
end

function v = metric_peak(ctx)
if isempty(ctx.Mean), v = NaN; return; end
v = max(abs(ctx.Mean))*1e6;
end

function v = metric_latency(ctx)
% The MOST PROMINENT peak, not the first and not the largest: prominence is
% what mabr.ui.TraceInspector's auto-detect ranks by, and a latency picked
% here should agree with one picked there. With no turning point at all in
% the window (a monotonic flank) the segment maximum stands in -- the same
% fallback, and for the same reason: the latency it reports is what tells the
% operator the window is wrong.
v = NaN;
if numel(ctx.Mean) < 3, return; end
r = mabr.metrics.find_peaks(ctx.Mean,10,false);
if isempty(r.locs)
    [~,i] = max(ctx.Mean);
else
    [~,k] = max(r.p);
    i = r.locs(k);
end
v = ctx.Time(i);        % already ms re onset
end

function v = metric_corr(ctx)
if size(ctx.Sweeps,2) < 2, v = NaN; return; end
v = mabr.metrics.mean_pairwise_corr(ctx.Sweeps);
end

function v = metric_splithalf(ctx)
if size(ctx.Sweeps,2) < 2, v = NaN; return; end
a = mean(ctx.Sweeps(:,1:2:end),2,'omitnan');
b = mean(ctx.Sweeps(:,2:2:end),2,'omitnan');
if std(a) == 0 || std(b) == 0, v = NaN; return; end
r = corrcoef(a,b);
v = r(1,2);
end

function v = metric_snr(ctx)
if size(ctx.Sweeps,2) < 2, v = NaN; return; end
v = mabr.metrics.snr(ctx.Sweeps);
end

function v = metric_noise(ctx)
if size(ctx.Sweeps,2) < 2, v = NaN; return; end
d = mean(ctx.Sweeps(:,1:2:end),2,'omitnan') - mean(ctx.Sweeps(:,2:2:end),2,'omitnan');
v = sqrt(mean(d.^2,'omitnan'))*1e6;
end

function v = metric_area(ctx)
if numel(ctx.Mean) < 2, v = NaN; return; end
v = trapz(ctx.Time,abs(ctx.Mean))*1e6;      % Time is ms => uV*ms
end

function v = metric_sweeps(ctx)
v = ctx.NumSweeps;
end

function v = metric_artifacts(ctx)
v = ctx.ArtifactRate;
end


% ============================ helper =================================
function s = entry(key,name,units,summary,fcn)
s = struct('Key',key,'Name',name,'Units',units,'Summary',summary,'Fcn',fcn);
end
