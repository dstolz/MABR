function [pm,nA,nB] = plus_minus(D,pol)
% mabr.metrics.plus_minus  The plus/minus reference of a sweep set.
%
%   pm = plus_minus(D) returns the plus/minus reference (Schimmel 1967) of the
%   sweeps in D, a [nSamples x nSweeps] matrix: HALF the difference between
%   the mean of the odd sweeps and the mean of the even sweeps, a column
%   vector. Its RMS is the noise left in mean(D,2): each half-mean carries
%   2/N of a sweep's noise variance, the two are independent, and the
%   halving brings the difference back to the 1/N of the grand mean.
%
%   pm = plus_minus(D,pol) takes the per-sweep polarity (+1/-1, one per
%   column; [] or all equal means no split) and divides each polarity class
%   alternately between the two halves, so the halves are balanced in sign.
%   Without it, under alternating polarity the odd sweeps ARE the positive
%   ones and the even sweeps the negative, and the "noise" difference holds
%   twice the polarity-locked response -- the cochlear microphonic, the
%   stimulus artifact -- that alternation exists to cancel; and after one
%   rejected sweep the parity shifts and the two signs mix at random.
%
%   [pm,nA,nB] = ... also returns how many sweeps each half held.
%
%   Fewer than two sweeps have no reference: pm is all NaN.
%
%   See also mabr.metrics.snr, mabr.data.Recording.noisePower,
%   mabr.metrics.online.catalog.
%
% Daniel Stolzberg (c) 2026

D = double(D);
n = size(D,2);
pm = nan(size(D,1),1);
nA = 0; nB = 0;
if n < 2, return; end

if nargin < 2 || isempty(pol) || numel(pol) ~= n || numel(unique(sign(pol(:)))) < 2
    inA = mod(1:n,2) == 1;                 % odd / even, as always
else
    % Within each polarity class, alternate between the halves in sweep
    % order, so each half holds (as nearly as possible) half of each class.
    inA = false(1,n);
    s = sign(pol(:)');
    for v = unique(s)
        k = find(s == v);
        inA(k(1:2:end)) = true;
    end
end
nA = nnz(inA); nB = n - nA;
if nA == 0 || nB == 0
    inA = mod(1:n,2) == 1;                 % a class of one: fall back to odd/even
    nA = nnz(inA); nB = n - nA;
end
pm = (mean(D(:,inA),2) - mean(D(:,~inA),2))/2;
end
