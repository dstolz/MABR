function done = corr_threshold(ctx)
% mabr.stim.advance.corr_threshold  Advance when the online correlation metric
% crosses a threshold (a real implementation of the empty legacy stub
% advanceFcns/abr_adv_corr_thr.m).
%
%   done = corr_threshold(ctx) returns true once the running onset-contrast
%   correlation (mabr.metrics.partition_corr) reaches ctx.corrThreshold, after
%   a minimum number of sweeps. Because the worker polls commands every frame,
%   honoring this predicate lets a block stop early the moment a response is
%   detected — the capability the legacy design explicitly could not provide
%   ("NOT CURRENTLY POSSIBLE TO UPDATE THE NUMBER OF SWEEPS DURING PLAYBACK").
%
%   Context fields:
%       ctx.corr           current correlation metric (0..1)
%       ctx.corrThreshold  threshold to reach (default 0.5)
%       ctx.minSweeps      sweeps required before the criterion can fire (default 32)
%       ctx.numSweeps      sweeps acquired so far
%       ctx.maxSweeps      (optional) hard cap; also completes the block
%
% Daniel Stolzberg (c) 2019-2026

thr  = getfield_default(ctx,'corrThreshold',0.5);
minN = getfield_default(ctx,'minSweeps',32);
maxN = getfield_default(ctx,'maxSweeps',Inf);
r    = getfield_default(ctx,'corr',0);
n    = getfield_default(ctx,'numSweeps',0);

done = (n >= minN && r >= thr) || (n >= maxN);
end

function v = getfield_default(s,f,d)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
