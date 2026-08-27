function [ok,msg] = validate(fcn)
% mabr.stim.strategy.validate  Check that a function conforms to the custom
% presentation-strategy contract before it is trusted with a session.
%
%   [ok,msg] = mabr.stim.strategy.validate(fcn) returns ok=true when fcn is a
%   function handle that, called with a canonical context struct
%   (mabr.stim.strategy.context), returns something
%   mabr.stim.strategy.normalize can read as a plan. When ok is false, msg is
%   a one-line reason suitable for a dialog. This is what mabr.ui.App runs the
%   moment the user picks a custom strategy, so a malformed one is refused at
%   selection time rather than throwing at Start with the rig warmed up.
%
%   It exercises the function on a REPRESENTATIVE design -- a small
%   Frequency x Level bank with unequal repetition counts, one entry
%   alternating polarity -- rather than an empty one, so a strategy that
%   indexes ctx.params.Values, sorts by a parameter, or reasons about
%   repetitions is genuinely tested doing so. Unequal counts are deliberate:
%   the commonest bug in a hand-written strategy is a cycle that assumes every
%   entry is owed the same number and drops the remainder of the others.
%
%   The invariant warning normalize emits is NOT a failure here: a strategy is
%   allowed to present a different number of sweeps on purpose. Only a
%   structural fault -- erroring, or returning something that is not a plan --
%   fails validation.
%
%   See also mabr.stim.strategy.context, mabr.stim.strategy.normalize,
%   mabr.stim.strategy.custom_template.
%
% Daniel Stolzberg (c) 2019-2026

ok = false; msg = '';

if ~isa(fcn,'function_handle')
    msg = 'Not a function handle.';
    return
end

ctx = mabr.stim.strategy.sampleContext();

try
    out = fcn(ctx);
catch me
    msg = sprintf('Errored when called with a context struct: %s',me.message);
    return
end

% normalize is the authority on what counts as a plan, so validation asks it
% rather than re-deriving the rules and drifting from them -- quietly, since
% its invariant warning is about a plan nothing has been asked to present.
try
    [runs,pols] = mabr.stim.strategy.normalize(out,ctx,true);
catch me
    msg = sprintf('Did not return a usable plan: %s',me.message);
    return
end

if numel(runs) ~= numel(pols)
    msg = 'Returned runs and polarities of different lengths.';
    return
end

ok = true;
end
