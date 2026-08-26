function [ok,msg] = validate(fcn)
% mabr.metrics.online.validate  Check a function against the online-metric
% contract before a plot is trusted with it.
%
%   [ok,msg] = mabr.metrics.online.validate(fcn) returns ok=true when fcn is
%   a function handle that, called with the canonical context struct
%   (mabr.metrics.online.context), returns one numeric or logical scalar
%   without erroring. When ok is false, msg is a one-line reason suitable for
%   a dialog. mabr.ui.MetricPlot runs this the moment a custom metric is
%   picked, so a malformed one is refused at selection time rather than
%   throwing on every refresh for the rest of the session.
%
%   NaN is a VALID return: it is how a metric says "not enough data yet", and
%   the plot draws a gap rather than a point. What is rejected is a function
%   that errors, returns nothing, or returns something that is not one number
%   -- a vector of per-sweep values, say, which has no place on an axis with
%   one point per condition.
%
%   The test context is a REPRESENTATIVE one -- a real evoked-looking average
%   over 64 sweeps with a pre-onset baseline and a populated Params struct --
%   so a metric that indexes a field, windows a trace, or divides by a sweep
%   count is actually exercised doing it.
%
%   See also mabr.metrics.online.context, mabr.metrics.online.catalog,
%   mabr.metrics.online.custom_template.
%
% Daniel Stolzberg (c) 2019-2026

ok = false; msg = '';

if ~isa(fcn,'function_handle')
    msg = 'Not a function handle.';
    return
end

ctx = mabr.metrics.online.sampleContext();

try
    v = fcn(ctx);
catch me
    msg = sprintf('Errored when called with a context struct: %s',me.message);
    return
end

if ~(isnumeric(v) || islogical(v))
    msg = 'Must return a number (got a non-numeric value).';
    return
end
if ~isscalar(v)
    msg = sprintf('Must return a single value; got %s.',mat2str(size(v)));
    return
end

ok = true;
end
