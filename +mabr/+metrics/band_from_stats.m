function hw = band_from_stats(sd,n,mode,conf)
% mabr.metrics.band_from_stats  Error-band half-width from the statistics.
%
%   hw = band_from_stats(sd,n,mode,conf) is the arithmetic behind
%   mabr.metrics.error_band, taking the sample standard deviation across
%   sweeps and the sweep count instead of the sweeps themselves:
%
%       sd    [nConds x nSamples] std(Y,0,1) of each condition's sweeps (a
%             single condition is one row, which is what error_band hands in)
%       n     sweeps behind each row -- a scalar, or one value per row
%       mode  'std' | 'sem' | 'ci' | 'none'   (see error_band for meanings)
%       conf  confidence level for 'ci', default 0.95
%
%   hw is the same shape as sd. A row with fewer than two sweeps has no
%   spread to report and comes back NaN, which draws as NO band rather than
%   as a band of zero width; 'none' is all NaN.
%
%   This exists so that a view holding only a condition's mean, SD and sweep
%   count -- the live view, once the DSP has run somewhere other than the GUI
%   process and no sweep matrix is in the foreground at all -- can still draw
%   every band error_band can. error_band(Y,mode,conf) is exactly
%   band_from_stats(std(Y,0,1),size(Y,1),mode,conf), term for term and in the
%   same order, so the two agree to the bit rather than to a tolerance.
%
%   See also mabr.metrics.error_band, mabr.metrics.t_quantile.
%
% Daniel Stolzberg (c) 2026

if nargin < 3 || isempty(mode), mode = 'sem'; end
if nargin < 4 || isempty(conf), conf = 0.95;  end

sd = double(sd);
hw = nan(size(sd));

mode = lower(char(mode));
if strcmp(mode,'none') || isempty(sd), return; end

n = double(n(:));
if isscalar(n), n = repmat(n,size(sd,1),1); end
assert(numel(n) == size(sd,1),'mabr:metrics:band_from_stats:count', ...
    'n must be a scalar or hold one sweep count per row of sd.');

ok = n >= 2;
if ~any(ok), return; end

switch mode
    case 'std'
        hw(ok,:) = sd(ok,:);
    case 'sem'
        hw(ok,:) = sd(ok,:)./sqrt(n(ok));
    case 'ci'
        assert(isscalar(conf) && conf > 0 && conf < 1, ...
            'mabr:metrics:error_band:conf', ...
            'A confidence level must be a scalar strictly between 0 and 1.');
        hw(ok,:) = mabr.metrics.t_quantile(1-(1-conf)/2,n(ok)-1).*sd(ok,:)./sqrt(n(ok));
    otherwise
        error('mabr:metrics:error_band:mode', ...
            'Unknown error-band statistic "%s" (expected none/std/sem/ci).',mode);
end
end
