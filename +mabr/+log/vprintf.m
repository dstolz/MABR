function vprintf(verbose_level,varargin)
% mabr.log.vprintf(verbose_level,[red],msg,[values...])
% mabr.log.vprintf(verbose_level,[red],exception)
%
% MABR's logging front door, and the only one: every message the toolbox
% prints to the command window and every line in .error_logs/ comes through
% here. The work is done by granary (external/granary, a git submodule) --
% this function is the facade that keeps MABR's own spelling and hands the
% call straight to granary.printf, whose calling convention is identical.
%
% Levels:
%   -1 log the message, but do not print it to the command window
%    0 critical
%    1 low    - generally useful information
%    2 medium - helpful for debugging
%    3 high   - lots of detail (debugging; may perturb critical timing)
%    4 trace  - per-iteration detail
% granary.Level gives them names, and may be passed in place of the number.
%
% The two destinations are gated SEPARATELY, which is the one behavioural
% change the move to granary brings:
%   GVerbosity    - command window. Default 1, as before.
%   GLogVerbosity - error log. Default Inf, so every message is written no
%                   matter how quiet the console is. Turning the command
%                   window down no longer throws away the detail that explains
%                   a failure. Lower it on a rig where a level-3 or level-4
%                   message sits in a per-frame loop and the file write would
%                   cost real time.
%
% Format policy, also granary's and also a change worth knowing:
%   with values : msg is a printf format string, exactly as documented.
%   no values   : msg is LITERAL text -- nothing is interpreted -- so a
%                 runtime-built message such as me.message or a Windows path
%                 survives intact instead of being mangled by its own '\' and
%                 '%'. The old logger interpreted it either way, which is what
%                 mabr.log.StimgenLogSink had to work around.
% A trailing newline is never needed and is stripped if present.
%
% msg may also be an MException, or any struct carrying .message (a timer
% ErrorFcn event). Identifier, message, stack and nested causes are written
% as ONE record attributed to the catch site -- the old logger emitted a
% separate timestamped line per stack frame.
%
%   mabr.log.vprintf(1,1,'Critical message in red: %d',42)
%   mabr.log.vprintf(0,1,me)
%
% This function is registered with granary as a facade
% (see mabr.log.configure), so the caller column of the log names the code
% that logged rather than this file.
%
% Without the granary submodule MABR still runs: messages are printed to the
% command window by the fallback below and a one-time notice says the log
% file is unavailable. Fetch it with "git submodule update --init" and
% restart. See mabr.log.granaryAvailable.
%
% See also mabr.log.configure, mabr.log.granaryAvailable, mabr.log.logFile,
%          granary.printf, granary.Level, granary.setLogDir.
%
% Daniel Stolzberg (c) 2015-2026

% Wired once per MATLAB process -- this one included on a parallel worker,
% which has its own copy of granary's settings, so leaving this to the GUI
% would send a worker's messages to <tempdir> instead of the session's log.
% Asked on every message rather than cached in a persistent here: the answer
% IS a persistent, one level down, so this costs a function call reading a
% cached flag -- and keeping the decision in one place means it can be
% re-made. mabr.log.configure('-reset') is then all it takes to pick up a
% submodule fetched mid-session, or to exercise the fallback below, neither
% of which a persistent in this file could be talked out of without
% "clear functions".
if mabr.log.configure()
    granary.printf(verbose_level,varargin{:});
else
    fallback(verbose_level,varargin{:});
end
end


% =====================================================================
function fallback(verbose_level,varargin)
% Command-window printing with no granary present. Deliberately NOT a second
% file logger: reproducing that here would put back the duplicate logger this
% facade exists to remove, and would let a broken installation look healthy.
% It follows granary's calling convention and format policy exactly, so a
% message reads the same whether or not the submodule was fetched.
%
% Never throws, for the same reason nothing in granary does.

global GVerbosity

try
    notifyOnce();

    if isempty(GVerbosity) || ~isnumeric(GVerbosity) || ~isscalar(GVerbosity) ...
            || ~isfinite(GVerbosity)
        GVerbosity = 1;
    end

    % A malformed level is treated as critical rather than silently dropped
    % forever, which is the call granary.record makes for the same case.
    if ~isnumeric(verbose_level) || ~isscalar(verbose_level), verbose_level = 0; end

    % Negative levels are log-only, and there is no log.
    if verbose_level < 0 || verbose_level > GVerbosity || isempty(varargin), return; end

    % Same convention as granary.printf: the red flag is only a flag when it
    % is a numeric or logical scalar with something after it.
    if numel(varargin) >= 2 && (isnumeric(varargin{1}) || islogical(varargin{1})) ...
            && isscalar(varargin{1})
        red    = logical(varargin{1});
        msg    = varargin{2};
        values = varargin(3:end);
    else
        red    = false;
        msg    = varargin{1};
        values = varargin(2:end);
    end

    if isa(msg,'MException') || (isstruct(msg) && isfield(msg,'message'))
        txt = exceptionText(msg);
    elseif isempty(values)
        txt = char(string(msg));            % literal, per granary's policy
    else
        txt = sprintf(char(string(msg)),values{:});
    end

    c = clock; %#ok<CLOCK> - matches granary; datetime costs ~275 us per message
    stamp = sprintf('%02d:%02d:%06.3f',c(4),c(5),c(6));

    if red, fid = 2; else, fid = 1; end
    fprintf(fid,'%s: %s\n',stamp,deblank(txt));
catch
    % A logger that raised while reporting a failure would replace it.
end
end


% ---------------------------------------------------------------------
function txt = exceptionText(me)
% One record, the way granary.formatException builds it: identifier, message
% and stack together rather than a timestamped line per frame. A struct
% carrying .message need not carry the rest, so each part is asked for before
% it is read -- an error here would lose the exception being reported.
txt = '';
try
    if hasField(me,'identifier') && ~isempty(me.identifier)
        txt = [char(string(me.identifier)) newline];
    end
    txt = [txt char(string(me.message))];
    if hasField(me,'stack')
        st = me.stack;
        for i = 1:numel(st)
            txt = [txt sprintf('\n    %s (line %d)',st(i).name,st(i).line)]; %#ok<AGROW>
        end
    end
catch
    if isempty(txt), txt = 'unprintable exception'; end
end
end


% ---------------------------------------------------------------------
function tf = hasField(x,name)
tf = false;
try
    tf = (isstruct(x) && isfield(x,name)) || (~isstruct(x) && isprop(x,name));
catch
end
end


% ---------------------------------------------------------------------
function notifyOnce()
% Said once per process, in red, naming the fix. A missing logger must not be
% something a rig can run for a week without noticing.
persistent told
if ~isempty(told), return; end
told = true;
[~,why] = mabr.log.granaryAvailable();
fprintf(2,'MABR: %s\n',why);
end
