function done = num_sweeps(ctx)
% mabr.stim.advance.num_sweeps  Advance when the target sweep count is reached.
%
%   done = num_sweeps(ctx) returns true once ctx.numSweeps >= ctx.targetSweeps.
%   Port of the legacy advanceFcns/abr_adv_num_sweeps.m, reframed as a pure
%   predicate over an acquisition context struct:
%       ctx.numSweeps     sweeps acquired so far in the current block
%       ctx.targetSweeps  target sweep count for the block
%
% Daniel Stolzberg (c) 2019-2026

target = getfield_default(ctx,'targetSweeps',Inf);
n      = getfield_default(ctx,'numSweeps',0);
done   = n >= target;
end

function v = getfield_default(s,f,d)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
