classdef StimgenLogSink < stimgen.LogSink
% mabr.log.StimgenLogSink  Route stimgen's log messages through MABR's logger.
%
%   stimgen ships its own logger (console plus a daily file under tempdir),
%   which left a MABR session writing two log files describing one experiment.
%   stimgen's LogSink seam exists for exactly this: mabr.ui.App installs one
%   of these at startup (stimgen.util.logSink), after which every
%   stimgen.util.vprintf call lands in mabr.log.vprintf -- same console, same
%   .error_logs/ file -- and stimgen writes nothing of its own.
%
%   Verbosity stays one setting with no work here: both packages gate on the
%   same global GVerbosity, and stimgen's default LogSink.isEnabled reads it,
%   so a message suppressed for one logger is suppressed for the other.
%
%   This class can only load where the optional submodule is on the path (the
%   superclass is stimgen's) -- callers guard on mabr.stim.stimgenAvailable.
%
%   See also stimgen.LogSink, stimgen.util.logSink, mabr.log.vprintf.
%
% Daniel Stolzberg (c) 2026

    methods
        function emit(~,level,red,msg,args)
            % stimgen's contract: msg arrives RAW -- char/string, an
            % MException, or a struct carrying .message -- with args as a cell
            % ({} meaning msg is literal text, not a format string). And emit
            % must never throw: stimgen logs from inside catch blocks, and an
            % exception raised while reporting an exception destroys the
            % report (stimgen would fall back to its own logger, defeating
            % the sink).
            try
                if isa(msg,'MException')
                    mabr.log.vprintf(level,red,msg);  % vprintf logs id + stack itself
                    return
                end
                if isstruct(msg)
                    if ~isfield(msg,'message'), return; end
                    msg = msg.message;
                end
                msg = char(msg);
                if isempty(args)
                    % Through '%s' so literal text stays literal --
                    % mabr.log.vprintf treats its msg as a printf format, the
                    % one place the two logging contracts disagree.
                    mabr.log.vprintf(level,red,'%s',msg);
                else
                    mabr.log.vprintf(level,red,msg,args{:});
                end
            catch
                % Deliberately silent; see above.
            end
        end
    end
end
