function v = log10space(a,b,n)
% v = log10space(a,b,n)
% 
% Helper function:
%  v = logspace(log10(a),log10(b),n);
%
%

if nargin < 3 || isempty(n), n = 50; end
v = logspace(log10(a),log10(b),n);