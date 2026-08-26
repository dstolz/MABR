function hw = error_band(Y,mode,conf)
% mabr.metrics.error_band  Half-width of an error band about a sweep average.
%
%   hw = error_band(Y,mode) returns the HALF-WIDTH of an error band about
%   mean(Y,1), one value per column of Y = [nSweeps x nSamples]. The band is
%   mean +/- hw: all three statistics are symmetric about the mean, so one
%   vector describes both edges.
%
%       'std'  the sample standard deviation across sweeps -- how much a
%              SINGLE sweep varies. It does not shrink as sweeps accumulate,
%              because it is a statement about the recording rather than
%              about the average
%       'sem'  std/sqrt(n) -- how well the MEAN is pinned down, which is what
%              visibly tightens as an average builds
%       'ci'   the parametric confidence interval for the mean:
%              t(1-(1-conf)/2, n-1) * sem, using Student's t (see
%              mabr.metrics.t_quantile) rather than the normal quantile so a
%              band drawn over the first few sweeps is honest about how
%              little it yet knows. conf defaults to 0.95.
%       'none' no band; all NaN.
%
%   Fewer than two sweeps has no spread to report and returns NaN, which draws
%   as NO band rather than as a band of zero width -- a zero-width band would
%   be a claim of perfect precision made from a single observation.
%
%   Nothing here is recorded: this is a display statistic over the sweeps the
%   artifact policy kept, computed for the live view and for nothing else.
%
%   See also mabr.metrics.t_quantile, mabr.ui.LivePlot.
%
% Daniel Stolzberg (c) 2026

if nargin < 2 || isempty(mode), mode = 'sem'; end
if nargin < 3 || isempty(conf), conf = 0.95;  end

Y  = double(Y);
n  = size(Y,1);
hw = nan(1,size(Y,2));

mode = lower(char(mode));
if strcmp(mode,'none') || n < 2 || isempty(Y), return; end

s = std(Y,0,1);
switch mode
    case 'std'
        hw = s;
    case 'sem'
        hw = s./sqrt(n);
    case 'ci'
        assert(isscalar(conf) && conf > 0 && conf < 1, ...
            'mabr:metrics:error_band:conf', ...
            'A confidence level must be a scalar strictly between 0 and 1.');
        hw = mabr.metrics.t_quantile(1-(1-conf)/2,n-1).*s./sqrt(n);
    otherwise
        error('mabr:metrics:error_band:mode', ...
            'Unknown error-band statistic "%s" (expected none/std/sem/ci).',mode);
end
end
