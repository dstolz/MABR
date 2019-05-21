function v = octaves(a,b,n)
% v = octaves(a,b,[n])
% 
% Returns a vector of n numbers (default = 10) spaced equally in log2 space 
% between a and b.
%
% Ex:
%  v = octaves(1,32,6)
% v =
%      1     2     4     8    16    32
% 
% Ex:
%  v = octaves(1,32,5)
% v =
%     1.0000    2.3784    5.6569   13.4543   32.0000
%
% Daniel Stolzberg, PhD (c) 2019

narginchk(2,3);
if nargin < 3 || isempty(n), n = 10; end

mustBeFinite([a b n]);
v = a.*2.^(linspace(0,log2(b./a),n));