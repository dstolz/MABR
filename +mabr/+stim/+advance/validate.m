function [ok,msg] = validate(fcn)
% mabr.stim.advance.validate  Check that a function conforms to the advance
% criterion contract before it is trusted with a run.
%
%   [ok,msg] = mabr.stim.advance.validate(fcn) returns ok=true when fcn is a
%   function handle that, called with the canonical context struct
%   (mabr.stim.advance.context), returns a single logical/numeric scalar
%   without erroring. When ok is false, msg is a one-line reason suitable for
%   a dialog. This is what mabr.ui.App runs the moment the user selects a
%   custom advance function, so a malformed one is refused at selection time
%   rather than throwing 20 times a second mid-acquisition.
%
%   It exercises the function on a representative, mid-run context (some
%   sweeps in, a partial correlation, some artifacts) rather than an empty
%   struct, so a criterion that indexes a field or compares a number is
%   actually tested doing so.
%
%   See also mabr.stim.advance.context, mabr.stim.advance.custom_template.
%
% Daniel Stolzberg (c) 2019-2026

ok = false; msg = '';

if ~isa(fcn,'function_handle')
    msg = 'Not a function handle.';
    return
end

% A representative context: partway through a run, with every documented
% field populated so a criterion touching any of them is genuinely tested.
params = struct('targetSweeps',512,'corrThreshold',0.5, ...
                'minSweeps',32,'maxSweeps',Inf);
live   = struct('numSweeps',64,'numTotal',70,'numArtifacts',6, ...
                'corr',0.42,'elapsedSeconds',3.2);
ctx    = mabr.stim.advance.context(params,live);

try
    done = fcn(ctx);
catch me
    msg = sprintf('Errored when called with a context struct: %s',me.message);
    return
end

if ~(islogical(done) || isnumeric(done)) || ~isscalar(done)
    msg = 'Must return a single logical (true = stop the run early).';
    return
end

ok = true;
end
