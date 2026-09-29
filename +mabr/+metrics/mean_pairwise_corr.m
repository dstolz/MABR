function r = mean_pairwise_corr(D)
% mabr.metrics.mean_pairwise_corr  Fisher-z mean pairwise sweep correlation.
%
%   r = mean_pairwise_corr(D) computes the Pearson correlation between every
%   pair of sweeps (the columns of D, a [nSamples x nSweeps] matrix), applies
%   the Fisher z-transform, and returns the mean. Ported from the legacy
%   abr.ABR.analysis('corr').
%
%   The pairs are taken a tile of rows at a time rather than through the
%   whole nSweeps x nSweeps corrcoef matrix, which for a long block was the
%   largest allocation MABR made (435 MB at 7,374 sweeps, and a copy of it
%   for tril) -- on the GUI thread, at finalization, where running out of
%   memory lost the run. Memory is now about a tile (~32 MB) whatever the
%   sweep count; the arithmetic is the same (to rounding) and so are the
%   rules: every pair below the diagonal, an exact zero dropped along with the
%   upper triangle as tril/(r ~= 0) always did, |r| clamped to 1 as corrcoef
%   does, and a NaN (a constant sweep) left out of the mean. The one place
%   rounding shows is the degenerate one: two bit-identical sweeps come out at
%   1 - eps (a z near 18) where corrcoef's arithmetic lands on exactly 1 (Inf).
%
% Daniel Stolzberg (c) 2019-2026

if size(D,2) < 2, r = 0; return; end

X = double(D);
X = X - mean(X,1);
X = X ./ sqrt(sum(X.^2,1));        % unit-norm columns: X'*X is the correlation matrix
n = size(X,2);

tile = max(1,floor(2^22/n));       % rows of the correlation matrix per pass
s = 0;
c = 0;
for i0 = 1:tile:n
    i1 = min(n,i0+tile-1);
    C  = X(:,i0:i1).' * X(:,1:i1);             % rows i0..i1 against columns 1..i1
    % corrcoef's round-off fix-up -- by comparison, not min/max, which
    % would turn a constant sweep's NaN into +/-1 (they ignore NaN).
    C(C > 1)  = 1;
    C(C < -1) = -1;
    C  = tril(C,i0-2);                         % keep column < row: below the diagonal
    v  = C(C ~= 0);
    z  = (log(1+v) - log(1-v))/2;              % z' = 0.5[ln(1+r) - ln(1-r)]
    z  = z(~isnan(z));
    s  = s + sum(z);
    c  = c + numel(z);
end
r = s/c;                                       % NaN when no pair survived, as mean([]) is
end
