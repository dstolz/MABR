function R = partition_corr(preSweep,postSweep)
% Compute Pearson's correlation in a similar fashion to Arnold et al, 1985
% Arnold, S.A., et al (1985). Objective versus visual detection of the
% auditory brain stem response. Ear and Hearing, 6(3), 144–150.

% partition the sweeps into two random subsamples
n = min([size(preSweep,1) size(postSweep,1)]);
m = round(n/2);
i = randperm(n);

preMean1  = mean(preSweep(i(1:m),:),1)';
preMean2  = mean(preSweep((i(m+1:end)),:),1)';
postMean1 = mean(postSweep(i(1:m),:),1)';
postMean2 = mean(postSweep(i(m+1:end),:),1)';

% compute auto and cross correlation between preSweep and postSweep stimulus means
R = corrcoef([preMean1 preMean2 postMean1 postMean2]);

Rpre   = R(2,1);
Rcross = mean(R(sub2ind([4 4],[3 3 4 4],[1 2 1 2])));
Rpost  = R(4,3);

R = abs([Rpre Rcross Rpost]);

