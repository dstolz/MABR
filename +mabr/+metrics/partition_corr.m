function R = partition_corr(preSweep,postSweep)
% mabr.metrics.partition_corr  Onset-contrast correlation for online advance.
%
%   R = partition_corr(preSweep,postSweep) returns the difference between the
%   odd/even split-half correlation of the post-onset response and that of the
%   pre-onset baseline, floored at zero. High R indicates a reproducible
%   evoked response above the ongoing-noise correlation.
%
%   Inputs are [nSweeps x nSamples] matrices (rows = sweeps), as produced by
%   mabr.metrics.extract_sweeps. Computed after Arnold et al. (1985), Ear &
%   Hearing 6(3):144-150. Ported unchanged from the legacy ControlPanel; the
%   arithmetic after the four means is mabr.metrics.partition_corr_from_means,
%   which mabr.compute.Pipeline calls with running means instead.
%
% Daniel Stolzberg (c) 2019-2026

M = [mean(preSweep(1:2:end,:), 1); ...
     mean(preSweep(2:2:end,:), 1); ...
     mean(postSweep(1:2:end,:),1); ...
     mean(postSweep(2:2:end,:),1)];

R = mabr.metrics.partition_corr_from_means(M);
end
