function R = partition_corr(preSweep,postSweep)
% Compute the correlation coefficents for data following a stimulus
% onset (postSweep), preceding a stimulus onset (preSweep), as well as
% their crosscorrelation.
%
% To do this efficiently, just split the data into two datasets, odd sweeps
% and even sweeps, and then compute the correlation coefficients using
% corrcoef.
%
% Compute Pearson's correlation in a similar fashion to Arnold et al, 1985
% Arnold, S.A., et al (1985). Objective versus visual detection of the
% auditory brain stem response. Ear and Hearing, 6(3), 144–150.



preMean1  = mean(preSweep(1:2:end,:),1)';
preMean2  = mean(preSweep((2:2:end),:),1)';
postMean1 = mean(postSweep(1:2:end,:),1)';
postMean2 = mean(postSweep(2:2:end,:),1)';

% compute auto and cross correlation between preSweep and postSweep stimulus means
R = corrcoef([preMean1 preMean2 postMean1 postMean2]);

Rpre   = R(2,1);
Rcross = mean(R(sub2ind([4 4],[3 3 4 4],[1 2 1 2])));
Rpost  = R(4,3);

R = abs([Rpre Rcross Rpost]);

