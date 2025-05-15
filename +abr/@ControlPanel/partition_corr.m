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
% auditory brain stem response. Ear and Hearing, 6(3), 144�150.


M = [mean(preSweep(1:2:end,:), 1); 
     mean(preSweep(2:2:end,:), 1); 
     mean(postSweep(1:2:end,:), 1); 
     mean(postSweep(2:2:end,:), 1)];


% compute auto and cross correlation between preSweep and postSweep stimulus means
M = M - mean(M, 2);
M = M ./ std(M, 0, 2);
R = (M * M.') / (size(M, 2) - 1);

R = max(R(4,3) -  R(2,1),0);

