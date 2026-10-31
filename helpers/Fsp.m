function r = Fsp(data,point)
% r = Fsp(data,[point])
%
% Fsp (Elberling & Don) is a variance ratio (hence the F) the numerator of
% which is the sample variance, across time, of the average sweep and the
% denominator of which is the variance of the set of data values at a fixed
% single point in the time window across the N sweeps, divided by N (the
% variance of the average at that point if the noise is stationary):
%
%   Fsp = var(mean(x,1)) / ( var(x(:,point)) / N )
%
% data   [N sweeps x samples] matrix, one sweep per row
% point  sample index of the single point (default 1)
%
% Earlier versions used the pooled variance of all single-sweep values,
% var(data(:)), as the numerator and left out the division by N, so they did
% not compute Fsp.


if nargin < 2 || isempty(point), point = 1; end
if point > size(data,2), point = size(data,2); end

N = size(data,1);

Sp = var(data(:,point)) ./ N;     % variance of the average at the single point
Sy = var(mean(data,1));           % variance across time of the average sweep

r = Sy./Sp;
    