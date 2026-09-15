function [lo,hi] = band_edges(Y,mode,conf,nBoot,seed)
% mabr.metrics.band_edges  Lower and upper offsets of an error band.
%
%   [lo,hi] = band_edges(Y,mode,conf) returns the OFFSETS of an error band
%   from the mean of Y = [nSweeps x nSamples], one value per column:
%
%       lower edge = mean(Y,1) + lo        upper edge = mean(Y,1) + hi
%
%   so lo is negative and hi positive. This is mabr.metrics.error_band with
%   room for an ASYMMETRIC band, which is the whole reason it exists: the
%   three parametric statistics are symmetric about the mean and one
%   half-width describes both their edges, but a percentile bootstrap
%   interval is not, and forcing it into a half-width would be a different
%   statistic wearing its name.
%
%       'std' | 'sem' | 'ci' | 'none'
%               exactly mabr.metrics.error_band, mirrored: lo = -hw,
%               hi = +hw. See that function for what each one claims.
%       'boot'  the percentile bootstrap confidence interval of the MEAN:
%               nBoot resamples of the sweeps with replacement, the conf
%               central quantiles of the resampled means. It assumes nothing
%               about the distribution of a sweep, which is what recommends
%               it over 'ci' on a handful of sweeps, and it is the one
%               statistic here that can come back lopsided. This is the
%               Statistics Toolbox's bootci in the one case MABR needs, done
%               without it -- mabr.Config.RequiredToolboxes does not list it
%               (see also the toolbox-free arithmetic in
%               mabr.analysis.Threshold).
%
%   nBoot defaults to 1000 and seed to 0. The seed is fixed rather than
%   shuffled so that redrawing a view does not make the band breathe: the
%   band is a property of the sweeps, and a reader must not be able to move
%   it by resizing the window.
%
%   Offsets rather than absolute edges, because the caller may be drawing a
%   mean that has been shifted -- a detrended or smoothed display trace
%   (mabr.data.Recording.SweepMean does both) -- and a band is still the
%   right width about it. Adding the offsets keeps the band on the trace
%   actually on screen.
%
%   Fewer than two sweeps has no spread to report and returns NaN, which
%   draws as NO band rather than one of zero width; 'none' is all NaN. A
%   NaN edge blanks the band outright rather than putting a hole in it -- a
%   patch is one face (see mabr.ui.Trace.plot).
%
%   See also mabr.metrics.error_band, mabr.metrics.band_from_stats,
%   mabr.ui.TraceOrganizer.
%
% Daniel Stolzberg (c) 2026

if nargin < 2 || isempty(mode),  mode  = 'sem'; end
if nargin < 3 || isempty(conf),  conf  = 0.95;  end
if nargin < 4 || isempty(nBoot), nBoot = 1000;  end
if nargin < 5 || isempty(seed),  seed  = 0;     end

Y  = double(Y);
n  = size(Y,1);
lo = nan(1,size(Y,2));
hi = lo;

mode = lower(char(mode));
if strcmp(mode,'none') || n < 2 || isempty(Y), return; end

if ~strcmp(mode,'boot')
    hw = mabr.metrics.error_band(Y,mode,conf);
    lo = -hw;
    hi =  hw;
    return
end

assert(isscalar(conf) && conf > 0 && conf < 1, ...
    'mabr:metrics:band_edges:conf', ...
    'A confidence level must be a scalar strictly between 0 and 1.');
nBoot = max(2,round(double(nBoot)));

% Resample by COUNTS rather than by indexing the sweeps: the mean of a
% resample is (counts * Y)/n, so every resample is one row of a single
% matrix product instead of nBoot passes over the sweep matrix.
s = RandStream('threefry','Seed',double(seed));
C = zeros(n,nBoot);
draws = randi(s,n,n,nBoot);
for b = 1:nBoot
    C(:,b) = accumarray(draws(:,b),1,[n 1]);
end
M = (C'*Y)/n;                                   % [nBoot x nSamples]

m = mean(Y,1);
q = quantile_cols(M,[(1-conf)/2, 1-(1-conf)/2]);
lo = q(1,:) - m;
hi = q(2,:) - m;
end


% =====================================================================
function q = quantile_cols(M,p)
% Column-wise linear-interpolation quantiles -- the same convention as
% mabr.analysis.Threshold.percentile, and for the same reason (no
% Statistics toolbox). Every column has the same number of rows, so the
% interpolation position is computed once for all of them.
B  = size(M,1);
Ms = sort(M,1);
pos = min(max(p(:)*B + 0.5,1),B);
i0  = floor(pos);
i1  = min(i0+1,B);
w   = pos - i0;
q   = (1-w).*Ms(i0,:) + w.*Ms(i1,:);
end
