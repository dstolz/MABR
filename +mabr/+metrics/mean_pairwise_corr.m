function r = mean_pairwise_corr(D)
% mabr.metrics.mean_pairwise_corr  Fisher-z mean pairwise sweep correlation.
%
%   r = mean_pairwise_corr(D) computes the Pearson correlation between every
%   pair of sweeps (the columns of D, a [nSamples x nSweeps] matrix), applies
%   the Fisher z-transform, and returns the mean. Ported from the legacy
%   abr.ABR.analysis('corr').
%
% Daniel Stolzberg (c) 2019-2026

if size(D,2) < 2, r = 0; return; end

r = corrcoef(double(D));
r = tril(r,-1);
r = r(r ~= 0);
z = (log(1+r) - log(1-r))/2;       % z' = 0.5[ln(1+r) - ln(1-r)]
r = mean(z,'all','omitnan');
end
