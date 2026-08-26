function t = t_quantile(p,nu)
% mabr.metrics.t_quantile  Student's t inverse CDF, without a toolbox.
%
%   t = t_quantile(p,nu) returns the value x for which P(T <= x) = p, where T
%   follows Student's t distribution with nu degrees of freedom. p and nu are
%   combined by implicit expansion, so either may be scalar.
%
%   MABR needs this for the parametric confidence band the live view can draw
%   (see mabr.metrics.error_band), and mabr.Config.RequiredToolboxes
%   deliberately does NOT list Statistics and Machine Learning -- so tinv()
%   cannot be assumed to exist on a rig. The identity used is EXACT, not an
%   approximation or a table:
%
%       nu / (nu + T^2)  ~  Beta(nu/2, 1/2)
%
%   so with q = 2*(1-p) the two-sided tail mass and y solving
%   I_y(nu/2,1/2) = q, the quantile is x = sqrt(nu*(1-y)/y). betaincinv is
%   core MATLAB; nothing here needs a toolbox.
%
%   Degenerate inputs return NaN rather than erroring -- the caller is a
%   redraw at 20 Hz, and a band that cannot be computed should simply not be
%   drawn: nu < 1 (fewer than two observations), p outside (0,1), or a
%   non-finite value anywhere. p = 0.5 is 0, as it should be.
%
%   Examples (standard table values):
%       t_quantile(0.975,10)   ->  2.2281
%       t_quantile(0.975,1)    -> 12.7062
%       t_quantile(0.975,1e9)  ->  1.9600  (the normal quantile, in the limit)
%
%   See also mabr.metrics.error_band.
%
% Daniel Stolzberg (c) 2026

p  = double(p);
nu = double(nu);

% Implicit expansion decides the result shape, then both inputs are broadcast
% onto it so the masks below can index either one the same way.
t  = nan(size(p + nu));
p  = p  + zeros(size(t));
nu = nu + zeros(size(t));

ok = isfinite(p) & isfinite(nu) & p > 0 & p < 1 & nu > 0;
if ~any(ok(:)), return; end

% Symmetric about zero: solve the upper half and mirror, so betaincinv is
% only ever asked about a tail mass in (0,1].
low = p < 0.5;
pu  = p;
pu(low) = 1 - pu(low);

q = 2*(1 - pu(ok));                             % two-sided tail mass
y = betaincinv(q,nu(ok)/2,0.5);
t(ok) = sqrt(nu(ok).*(1-y)./y);

flip = ok & low;
t(flip) = -t(flip);
end
