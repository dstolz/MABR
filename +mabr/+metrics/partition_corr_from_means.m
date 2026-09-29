function R = partition_corr_from_means(M)
% mabr.metrics.partition_corr_from_means  The onset-contrast correlation from
% the four split-half means it is made of.
%
%   R = partition_corr_from_means(M), M = [4 x nSamples]:
%       M(1,:)  mean of the odd  (1st, 3rd, ...) pre-onset baselines
%       M(2,:)  mean of the even (2nd, 4th, ...) pre-onset baselines
%       M(3,:)  mean of the odd  post-onset responses
%       M(4,:)  mean of the even post-onset responses
%   returns the odd/even correlation of the response minus that of the
%   baseline, floored at zero. See mabr.metrics.partition_corr.
%
%   Split out so a caller holding only running sums -- mabr.compute.Pipeline,
%   which keeps them one sweep at a time rather than re-averaging every sweep
%   of the run on every cycle -- computes the number with the same arithmetic
%   as partition_corr does from the sweeps.
%
% Daniel Stolzberg (c) 2019-2026

M = M - mean(M,2);
M = M ./ std(M,0,2);
R = (M * M.') / (size(M,2) - 1);

R = max(R(4,3) - R(2,1),0);
end
