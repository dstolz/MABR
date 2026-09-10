classdef StimgenLogSink < stimgen.LogSink
% mabr.log.StimgenLogSink  Route stimgen's log messages through MABR's logger.
%
%   stimgen ships its own logger (console plus a daily file under tempdir),
%   which left a MABR session writing two log files describing one experiment.
%   stimgen's LogSink seam exists for exactly this: mabr.ui.App installs one
%   of these at startup (stimgen.util.logSink), after which every
%   stimgen.util.vprintf call lands in mabr.log.vprintf -- and so in granary,
%   MABR's logger -- same console, same .error_logs/ file, and stimgen writes
%   nothing of its own.
%
%   Verbosity stays one setting with no work here: both packages gate on the
%   same global GVerbosity, and stimgen's default LogSink.isEnabled reads it,
%   so a message suppressed for one logger is suppressed for the other. (What
%   reaches the FILE is now granary's separate GLogVerbosity, default Inf, so
%   a stimgen message the console is too quiet for is still on the record.)
%
%   This class is named to granary as a facade (mabr.log.configure's
%   FacadeFiles), so a stimgen message is attributed in the log to the stimgen
%   code that raised it rather than to the emit below at one fixed line.
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
                % Passed straight through, args and all. The two contracts
                % used to disagree on exactly this point -- stimgen hands
                % literal text where MABR's old logger read a printf format,
                % so a message had to be forced through '%s' to survive its
                % own backslashes. granary applies the same rule stimgen
                % does (no values means literal text; see granary.format),
                % which is what makes the forwarding a pass-through.
                mabr.log.vprintf(level,red,msg,args{:});
            catch
                % Deliberately silent; see above.
            end
        end
    end
end
