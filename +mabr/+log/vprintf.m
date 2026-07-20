function vprintf(verbose_level,varargin)
% mabr.log.vprintf(verbose_level,[red],msg,[moreinputs])
%
% Verbosity-gated logger for the MABR toolbox (moved, not rewritten, from
% the legacy helpers/vprintf.m). Prints a timestamped message to the command
% window and mirrors it to a daily log file, gated on the global GVerbosity:
%   -1 log message, but do not print to screen
%    0 suppresses nearly all non-critical messages
%    1 low    - generally useful information
%    2 medium - helpful for debugging
%    3 high   - lots of detail (debugging; may perturb critical timing)
%
% Uses fprintf semantics; additional inputs correspond to the escape
% characters in msg. Always appends a newline.
%
%   mabr.log.vprintf(1,1,'Critical message in red: %d',42)
%
% If msg is an MException, the full error message and stack are logged.
%
% Daniel Stolzberg (c) 2015-2026

global GVerbosity

if isempty(GVerbosity) || ~isnumeric(GVerbosity), GVerbosity = 1; end

if verbose_level > GVerbosity, return; end

curTimeStr = datestr(now,'HH:MM:SS.FFF'); %#ok<DATST>

moreinputs = [];
red = 0;

if nargin == 2
    msg = varargin{1};

elseif nargin > 2 && ~ischar(varargin{1})
    red = varargin{1};
    msg = varargin{2};
    if nargin > 2
        moreinputs = varargin(3:end);
    end

elseif nargin > 2
    msg = varargin{1};
    moreinputs = varargin(2:end);
end

% log an exception with its full stack
if isa(msg,'MException')
    mabr.log.vprintf(verbose_level,red,msg.identifier);
    mabr.log.vprintf(verbose_level,red,msg.message);
    for i = 1:length(msg.stack)
        mabr.log.vprintf(verbose_level,red,'Stack %d\n\tfile:\t%s\n\tname:\t%s\n\tline:\t%d', ...
            i,msg.stack(i).file,msg.stack(i).name,msg.stack(i).line);
    end
    return
end

% mirror to the log file
logmessage(msg,curTimeStr,moreinputs);

% verbose_level == -1 means log-only
if verbose_level == -1, return; end

% print to the command window
if isempty(moreinputs)
    if red
        fprintf(2,['%s: ' msg '\n'],curTimeStr); %#ok<CTPCT>
    else
        fprintf(['%s: ' msg '\n'],curTimeStr);
    end
else
    if red
        fprintf(2,['%s: ' msg '\n'],curTimeStr,moreinputs{:}); %#ok<CTPCT>
    else
        fprintf(['%s: ' msg '\n'],curTimeStr,moreinputs{:});
    end
end
end


function logmessage(msg,curTimeStr,moreinputs)
% Append the message to a daily log file under the runtime error-log folder.
global GLogFID

try
    ftell(GLogFID);
    needNewLog = false;
catch %#ok<CTCH>
    needNewLog = true;
end

if needNewLog || isempty(GLogFID) || GLogFID == -1
    errlogs = mabr.Config.errorLogDir;
    GLogFID = fopen(fullfile(errlogs,['error_log_' datestr(now,'ddmmmyyyy') '.txt']),'at'); %#ok<DATST>
end

if isnumeric(GLogFID) && GLogFID > 2
    st = dbstack;
    if length(st) >= 3
        st = st(3);
    else
        st = st(end);
    end
    if isempty(moreinputs)
        fprintf(GLogFID,['%s,%s,%d: ' msg '\n'],curTimeStr,st.name,st.line);
    else
        fprintf(GLogFID,['%s,%s,%d: ' msg '\n'],curTimeStr,st.name,st.line,moreinputs{:});
    end
end
end
