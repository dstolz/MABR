function r = Fsp(data,point)
% r = Fsp(data,[point])
%
% Fsp involves calculation of a variance ratio (hence the F) the
% numerator of which is essentially the sample variance of the
% average and the denominator of which is the variance of the set
% of data values at a fixed single point in the time window across a group
% of sweeps.


if nargin < 2 || isempty(point), point = 1; end
if point > size(data,2), point = size(data,2); end

Sp = var(data(:,point));
Sy = var(data(:));

r = Sy./Sp;
    