function v = hang(~)
% mabrtest.hang  A metric that never returns.
%
%   v = mabrtest.hang(ctx) loops forever. It exists so verify_compute_worker
%   can wedge the metrics worker on purpose and confirm that the wedge costs
%   that window and nothing else -- the reason the metrics run in their own
%   process. The loop is interruptible (pause is an interruption point, and
%   so is every iteration if pause has been switched off), which is what
%   lets mabr.compute.ComputeEngine's cancel-and-relaunch recover the worker.
%
% Daniel Stolzberg (c) 2026

while true
    pause(0.1);
end
v = NaN; %#ok<UNRCH>
end
