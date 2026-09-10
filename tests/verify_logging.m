function verify_logging()
% verify_logging  Confirm MABR's logging goes through granary, and lands where
%                 and how the rest of the toolbox assumes it does.
%
%   Part A (wiring): mabr.log.configure tells granary the four things a
%   library cannot discover about its host, and the log file it names is the
%   one MABR has always written -- <root>/.error_logs/error_log_<ddmmmyyyy>.txt.
%   Part B (call convention): every shape MABR's 130-odd call sites use --
%   literal, formatted, red, and log-only -- reaches the file with the right
%   text.
%   Part C (attribution): a message is credited to the code that logged it,
%   not to mabr.log.vprintf. This is what granary's FacadeFiles buys and the
%   thing most likely to break silently, since a mis-attributed log still
%   looks like a log.
%   Part D (format policy): a message given no values is LITERAL, so a
%   Windows path and a stray '%' survive. The old logger read every message
%   as a printf format, which is what mabr.log.StimgenLogSink had to work
%   around.
%   Part E (two gates): GVerbosity and GLogVerbosity are independent -- a
%   message too quiet for the command window is still on the record, which is
%   the behavioural change the move to granary brings.
%   Part F (one record per exception): an MException is logged as a single
%   timestamped record carrying its identifier, message and stack, not one
%   line per stack frame.
%   Part G (no granary): with the submodule off the path MABR still prints,
%   still does not throw, and says there is no log file.
%
%   The user's own log directory and verbosity globals are put back on the way
%   out, including on an error exit -- the test writes to a temporary log so a
%   rig's own daily file is not filled with probes.
%
%   Unlike verify_stimgen_import this does NOT skip when its submodule is
%   absent: stimgen is optional at runtime and granary is not (see
%   mabr.log.granaryAvailable), so a clone that never fetched it has a real
%   fault to hear about.
%
%   No hardware, no parallel pool. Run:  >> verify_logging
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_logging ==\n');

% The package's two public controls: the command window and the log file are
% gated separately. Part E is what that separation means.
global GVerbosity GLogVerbosity

[hasGranary,why] = mabr.log.granaryAvailable();
assert(hasGranary, ...
    ['granary is MABR''s logger, not an optional extra, so this test does ' ...
     'not skip: %s'],why);

% The user's settings out of the way, and back on any exit.
savedV   = GVerbosity;
savedLV  = GLogVerbosity;
cleanupG = onCleanup(@() restore_globals(savedV,savedLV)); %#ok<NASGU>

hadDir = ispref('MABR','LogDir');
if hadDir, oldDir = getpref('MABR','LogDir'); else, oldDir = ''; end
tmpDir = [tempname '_mabr_verify_logging'];

GVerbosity    = 1;
GLogVerbosity = Inf;

% ---- Part A: the host wiring, and the file it names --------------------
assert(mabr.log.configure(),'mabr.log.configure should succeed with granary present');

C = granary.config();
assert(strcmp(C.PrefGroup,'MABR'), ...
    'the log-directory override belongs in MABR''s own pref group, got "%s"',C.PrefGroup);
assert(strcmp(C.LogDirName,'.error_logs'), ...
    'the log folder must stay .error_logs, got "%s"',C.LogDirName);
assert(strcmp(C.LogRoot,mabr.Config.root), ...
    'logs belong with the toolbox, not in tempdir; LogRoot is "%s"',C.LogRoot);
assert(strcmp(granary.builtinLogDir(),fullfile(mabr.Config.root,'.error_logs')), ...
    'the built-in log directory moved away from <root>/.error_logs');

% Both of MABR's front doors must be named, or every line they carry is
% attributed to them instead of to the code that logged (Part C).
assert(any(strcmp(C.FacadeFiles,'vprintf.m')), ...
    'mabr.log.vprintf is not registered as a granary facade');
assert(any(strcmp(C.FacadeFiles,'StimgenLogSink.m')), ...
    'mabr.log.StimgenLogSink is not registered as a granary facade');

% From here on, write somewhere disposable. setLogDir is also how a rig whose
% toolbox sits on a read-only share moves its logs, so exercise it rather than
% reaching past it.
cleanupD = onCleanup(@() restore_logdir(hadDir,oldDir,tmpDir)); %#ok<NASGU>
granary.setLogDir(tmpDir);

[logPath,logDir] = mabr.log.logFile();
assert(strcmp(logDir,tmpDir), ...
    'setLogDir did not re-point the live sink (log is at "%s")',logDir);
[~,base,ext] = fileparts(logPath);
assert(~isempty(regexp([base ext],'^error_log_\d{2}[A-Z][a-z]{2}\d{4}\.txt$','once')), ...
    ['the daily filename is part of the contract -- anything offering to ' ...
     'open "the current log" rebuilds it -- but it is now "%s"'],[base ext]);
fprintf('  PASS Part A: granary wired to this installation; log path unchanged\n');

% ---- Part B: every calling shape MABR uses -----------------------------
tok = sprintf('VL%09d',randi(1e9)-1);

mabr.log.vprintf(1,[tok ' A literal message']);
mabr.log.vprintf(1,'%s B formatted: %d and %s',tok,42,'text');
mabr.log.vprintf(0,1,[tok ' C red critical']);
mabr.log.vprintf(-1,[tok ' D log only']);

txt = read_log();
assert(contains(txt,[tok ' A literal message']),'a plain message never reached the log');
assert(contains(txt,[tok ' B formatted: 42 and text']),'a formatted message was not rendered');
assert(contains(txt,[tok ' C red critical']),'a red message never reached the log');
assert(contains(txt,[tok ' D log only']),'a level -1 message must still be LOGGED');

out = evalc('mabr.log.vprintf(-1,''log-only console probe'')');
assert(~contains(out,'log-only console probe'), ...
    'a level -1 message must not reach the command window');
out = evalc('mabr.log.vprintf(1,''console probe'')');
assert(contains(out,'console probe'),'a level 1 message should print at GVerbosity 1');
fprintf('  PASS Part B: literal, formatted, red, and log-only all land correctly\n');

% ---- Part C: the message is credited to the caller, not the facade -----
caller = caller_of(txt,[tok ' A literal message']);
assert(strcmp(caller,'verify_logging'), ...
    ['a log line must name the code that logged it; this one says "%s". ' ...
     'Check mabr.log.configure''s FacadeFiles.'],caller);
assert(~strcmp(caller,'vprintf'), ...
    'mabr.log.vprintf is being reported as the origin of its own messages');
fprintf('  PASS Part C: lines attributed to the caller, not to the front door\n');

% ---- Part D: no values means literal text ------------------------------
weird = 'C:\new\tab\run.mat is 100% done';
mabr.log.vprintf(1,weird);
mabr.log.vprintf(1,'path = %s',weird);
txt = read_log();
assert(contains(txt,weird), ...
    'a message given no values must be literal -- its backslashes were interpreted');
assert(contains(txt,['path = ' weird]), ...
    'a formatted message must not escape-process its own arguments');
fprintf('  PASS Part D: runtime-built text survives its own %% and backslashes\n');

% ---- Part E: the console and the log are gated separately --------------
GVerbosity    = 0;
GLogVerbosity = Inf;
out = evalc('mabr.log.vprintf(2,''quiet console, on the record'')');
assert(~contains(out,'quiet console, on the record'), ...
    'GVerbosity 0 should have kept a level 2 message off the command window');
txt = read_log();
assert(contains(txt,'quiet console, on the record'), ...
    ['GLogVerbosity defaults to Inf: turning the command window down must ' ...
     'not throw away the record that explains a failure']);

GLogVerbosity = 1;
mabr.log.vprintf(2,'below both ceilings');
txt = read_log();
assert(~contains(txt,'below both ceilings'), ...
    'GLogVerbosity should be able to keep a level 2 message out of the file');

GVerbosity    = 1;
GLogVerbosity = Inf;
fprintf('  PASS Part E: GVerbosity and GLogVerbosity are independent\n');

% ---- Part F: an exception is ONE record --------------------------------
try
    error('mabr:verifyLogging:probe','deliberate probe failure');
catch me
    mabr.log.vprintf(0,1,me);
end

txt   = read_log();
lines = strsplit(txt,newline);
head  = find(contains(lines,'mabr:verifyLogging:probe: deliberate probe failure'));
assert(isscalar(head), ...
    'an exception should be one record, found %d lines carrying its header',numel(head));
assert(strcmp(caller_of(txt,'deliberate probe failure'),'verify_logging'), ...
    'an exception must be attributed to the catch site, not to the logger');
assert(head < numel(lines),'the exception record has no stack line after it');
next = lines{head+1};
assert(startsWith(next,'    ') && startsWith(strtrim(next),'at '), ...
    'the stack should continue the same record, indented, not start a new one');
assert(isempty(regexp(next,'^\d{2}:\d{2}:','once')), ...
    'a stack frame must not get a timestamp of its own');
fprintf('  PASS Part F: identifier, message and stack are one attributed record\n');

% ---- Part G: MABR still runs with no granary ---------------------------
gdir = fileparts(fileparts(which('granary.printf')));    % .../external/granary
assert(isfolder(gdir),'could not locate the granary package folder');
cleanupP = onCleanup(@() restore_path(gdir)); %#ok<NASGU>

% Warning suppressed rather than the folder checked against `path`: the
% comparison is case- and separator-sensitive on Windows and would be a second
% thing to get right. Whether the removal took is asked below, of granary
% itself, which is the only answer that matters here.
wstate = warning('off','MATLAB:rmpath:DirNotFound');
rmpath(gdir);
warning(wstate);
mabr.log.configure('-reset');

if mabr.log.configure()
    % granary is still reachable -- a differently-spelled path entry, or the
    % session's working directory happens to be inside the package. That is
    % about this machine's path, not about what this part checks, so it is
    % skipped rather than failed.
    restore_path(gdir);
    fprintf('  SKIP Part G: granary could not be taken off the path here\n');
else
    out = evalc('mabr.log.vprintf(1,''fallback probe'')');
    assert(contains(out,'fallback probe'), ...
        'without granary MABR must still print to the command window');
    assert(isempty(mabr.log.logFile()), ...
        'there is no log file without granary, and logFile must say so rather than guess');

    restore_path(gdir);
    assert(mabr.log.configure(), ...
        'granary should be wired again once the path is restored');
    mabr.log.vprintf(1,[tok ' E back on granary']);
    assert(contains(read_log(),[tok ' E back on granary']), ...
        'logging did not resume after the submodule came back');
    fprintf('  PASS Part G: a missing submodule degrades to the console, and recovers\n');
end

fprintf('verify_logging: OK\n');
end


% =====================================================================
function txt = read_log()
% The log as it stands on disk. mabr.log.logFile flushes first, which is the
% whole reason a caller about to read the file goes through it.
txt = '';
p = mabr.log.logFile();
if ~isempty(p) && isfile(p)
    txt = fileread(p);
end
end


function name = caller_of(txt,needle)
% The caller column of the (single) line carrying needle. granary's text sink
% writes 'HH:mm:ss.SSS,caller,line: text', and the stamp holds colons rather
% than commas, so the second comma-delimited field is the caller whatever the
% message itself contains.
name = '';
lines = strsplit(txt,newline);
hit = lines(contains(lines,needle));
if isempty(hit), return; end
parts = strsplit(hit{1},',');
if numel(parts) >= 2, name = strtrim(parts{2}); end
end


function restore_globals(v,lv)
global GVerbosity GLogVerbosity
GVerbosity    = v;
GLogVerbosity = lv;
end


function restore_path(gdir)
% addpath is idempotent, so this is safe whether Part G finished or threw.
try
    addpath(gdir);
catch
end
try
    mabr.log.configure('-reset');
catch
end
end


function restore_logdir(had,old,tmp)
% setpref/rmpref rather than granary.setLogDir: this has to work even if the
% test exited with granary off the path, and it keeps "log directory changing"
% lines out of the user's own log.
try
    if had
        setpref('MABR','LogDir',old);
    elseif ispref('MABR','LogDir')
        rmpref('MABR','LogDir');
    end
catch
end
try
    % Rebuilds the sinks from the restored preference, and closes the handle
    % on the temporary file before it is removed.
    granary.Logger.instance('-reset');
catch
end
try
    if isfolder(tmp), rmdir(tmp,'s'); end
catch
end
end
