classdef AbrFile
% mabr.analysis.AbrFile  The one reader of .abr files for offline analysis.
%
%   Everything the offline analysis knows about a recording it learns here.
%   mabr.analysis.Session reads a file through read() to analyse it and
%   mabr.analysis.Catalog reads it to list it, so the two cannot disagree
%   about what a file holds -- its subject, stimulus, parameters, layout,
%   units and sweeps -- whichever of them looked first.
%
%       [rec,trace,sw] = mabr.analysis.AbrFile.read(ffn);
%       rec = mabr.analysis.AbrFile.read(ffn,ReadTrace=false);      % metadata
%       [~,~,~,notes] = mabr.analysis.AbrFile.read(ffn,ReadNotes=true);
%
%   READ NEVER THROWS FOR A BAD FILE. A folder of recordings is read in a
%   loop, and one corrupt file, one legacy index file or one file from a
%   future writer must cost that file and nothing else. A file that cannot be
%   used comes back with Ok = false and Error saying why; one that is not a
%   recording at all (a legacy -v7.3 "output file" carrying a .abr
%   extension, a MAT-file holding something else) also has Skipped = true.
%   Ok is true exactly when the file is a usable recording.
%
%   NOTHING IS PRINTED. A warning MATLAB raises while loading -- a legacy
%   file rebuilding objects whose classes are gone -- and everything the
%   reader notices on its own (an unreadable or renamed parameter, a dropped
%   onset) is collected in rec.Warnings instead. The global warning state and
%   lastwarn are put back as they were, whatever happens.
%
%   METADATA COMES FROM INSIDE THE FILE, NEVER FROM ITS NAME. File names have
%   changed grammar four times, spell one subject two ways in one folder, and
%   carry stimgen's "SoundLevel80" where SIG says Level; a long one was even
%   truncated at 63 characters. The name is read for the subject alone
%   (subjectOf), which no file records anywhere else.
%     Era        "E0" for a legacy +abr file (no SoftwareVersion), else "E1+".
%                Eras are told apart by which fields exist, never by version
%                strings, which never changed.
%     Params     SIG.informativeParams, each value from SIG.(name) when that
%                is a real non-integer number, else from SIG.dataParams.(name)
%                -- where an E0 file keeps its values, its SIG fields having
%                loaded as uint32 placeholders for a class that no longer
%                exists (and where an E0 frequency is in Hz, not kHz).
%                frequency, soundLevel and level become Frequency and Level,
%                and a name the analysis tables reserve for a column of their
%                own (ReservedNames, any case) becomes Stim_<name>.
%     Stimulus   the stimgen class without its package ("ClickTrain"), else
%                the first token of the stimulus ID. Two stimuli presented at
%                one level are two conditions; without this a click and a
%                noise burst at 60 dB would be averaged together.
%     Units      "V" when ADC carries both AmplifierGain and InputFullScale
%                (Data is volts at the electrodes); "V-unscaled" with the
%                gain alone (files of 2026-09-13 to 2026-10-01, written before
%                InputFullScale existed, when it was implicitly 1); "converter"
%                with neither (E0 files and the first MABR files).
%     LevelUnit  "dB SPL" only for a calibrated stimulus; "dB re max" for an
%                uncalibrated stimgen bank, its levels relative to its loudest
%                entry (SIG.LevelScale); "dB" otherwise.
%     Layout     an intermixed run is saved COMPACT -- each condition's 0 to
%                10 ms windows back to back, with no pre-onset sample and no
%                continuity from one window to the next (isCompact) -- and is
%                AcqMode "interleaved"; anything else is "continuous" and
%                "conventional". A compact file's last window is zero-filled
%                when the run stopped inside it, which nothing else marks: it
%                comes back Valid = false.
%
%   OUTPUTS (see read for every field of rec)
%     rec    scalar struct, every field always present
%     trace  ADC.Data(:) in its stored class (single), or [] when ReadTrace is
%            false or the file is not Ok
%     sw     the usable sweeps: Onset (n x 1, all finite and >= 1), Index
%            (1 x n, each onset's original 1-based ordinal -- an E0 onset of
%            0 is dropped and the others keep their numbers), IsArtifact,
%            Polarity (+1/-1) and Valid (1 x n each)
%     notes  with ReadNotes, ABR_Data.Notes as an n x 1 struct array (Stamp,
%            Text, Time as a datetime, Run, Sweep, Source); else 0 x 1
%
%   ReaderVersion goes up whenever what read() returns for the same file
%   changes: mabr.analysis.Catalog caches rec structs and rebuilds its cache
%   when the version it saved differs.
%
%   See also mabr.analysis.Session, mabr.analysis.Stats, mabr.data.io,
%   mabr.data.SessionNotes.
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        % Bump when read() returns something different for the same file.
        ReaderVersion = 1

        % Column names the analysis tables keep for themselves. A stimulus
        % parameter spelled like one of them (in any case) is read as
        % Stim_<name>, so it can never overwrite a column -- the demo bank's
        % Polarity, for one, would otherwise replace the per-sweep polarity.
        ReservedNames = ["Key","Stimulus","AcqMode","Sweeps","Rejected","Polarity","SweepFile", ...
            "SweepIndex","SweepOrder","SweepTime","RejectReason","Excess","nSweeps","nRejected", ...
            "nFiles","nClean","nPos","nNeg","p","isSig","strength","Detection","Detected", ...
            "DetectedAuto","Processing","Extent","Flags","Units","LevelUnit"]
    end

    methods (Static)
        function [rec,trace,sw,notes] = read(ffn,opts)
            % Read one .abr file: its metadata, its sweeps, and on request
            % its trace and notes.
            %
            %   [rec,trace,sw,notes] = read(ffn,ReadTrace=true,ReadNotes=false)
            %
            %   ffn             the file, char or string
            %   opts.ReadTrace  hand ADC.Data back as trace (default true).
            %                   The file is loaded whole either way -- a MAT
            %                   v5 file cannot load half a struct -- but false
            %                   hands nothing large back
            %   opts.ReadNotes  hand ABR_Data.Notes back as notes (default false)
            %
            %   rec  (returned) scalar struct, every field always present:
            %     Path, Folder, FileName  string; Path as dir() resolves it
            %     Bytes, Modified     from dir() (NaN / NaT for a missing file)
            %     Ok                  true only for a usable recording
            %     Skipped             true when the file is not a recording
            %     Error               why not Ok / why Skipped; "" when Ok
            %     Era                 "E0" | "E1+" ("" when nothing was read)
            %     StartTime           datetime when the run started; NaT if
            %                         unparseable
            %     SampleRate          Hz of ADC.Data
            %     DACSampleRate       Hz of the stimulus (NaN if absent)
            %     NumSweeps           usable onsets, after dropping any < 1
            %                         or not finite
            %     SweepLength         ADC.SweepLength, samples (NaN if absent)
            %     Layout, AcqMode     "continuous"/"conventional" or
            %                         "compact"/"interleaved" ("" unread)
            %     Duration            s, numel(ADC.Data)/SampleRate
            %     MinISI              ms, the shortest onset-to-onset
            %                         interval; NaN for a compact file or
            %                         fewer than two onsets
            %     TestMode            ABR_Data.TestMode (false if absent):
            %                         the samples are the stimulus itself
            %     Stimulus            "Tone", "ClickTrain", ... ("" unknown)
            %     StimClass           SIG.StimClass as written ("" if absent)
            %     StimID              the stimulus ID, from SIG.Label's
            %                         "ID = ..." entry, else SIG.ID
            %     ParamNames          1 x k string, mapped and renamed, in the
            %                         file's order
            %     Params              struct, one double per ParamNames entry
            %                         (NaN where unreadable)
            %     ParamText           "Frequency=8; Level=80": %g values, names
            %                         sorted as condition keys sort them
            %     AlternatePolarity   SIG.alternatePolarity ~= 0
            %     Units               "V" | "V-unscaled" | "converter"
            %     AmplifierGain, InputFullScale   as recorded; NaN if absent
            %     Calibrated          SIG.Calibrated (false if absent)
            %     CalibrationTime     SIG.CalibrationTime ("" if absent)
            %     LevelScale          SIG.LevelScale (NaN if absent)
            %     LevelUnit           "dB SPL" | "dB re max" | "dB"
            %     TruncatedSweeps     compact windows cut short (0 or 1)
            %     Subject             canonical subject from the file name,
            %                         "SUBJ-ID-1254" ("" when there is none)
            %     SubjectRaw          that subject as the name spells it
            %     Warnings            string column, one line per warning:
            %                         MATLAB's while loading (lastwarn keeps
            %                         the last) and every one of the reader's
            %   trace  (returned) ADC.Data(:), or [] (ReadTrace false, not Ok)
            %   sw     (returned) struct: Onset, Index, IsArtifact, Polarity,
            %          Valid (see the class help); empty fields when not Ok
            %   notes  (returned) n x 1 struct array, or 0 x 1
            arguments
                ffn (1,1) string
                opts.ReadTrace (1,1) logical = true
                opts.ReadNotes (1,1) logical = false
            end
            % A <missing> path (an empty cell of a string column) names no
            % file; char() of it would throw before anything is guarded.
            if ismissing(ffn), ffn = ""; end
            rec = blankRecord(ffn);
            try
                [rec,trace,sw,notes] = readFile(rec,opts);
            catch ME
                % A file shape nobody foresaw, or a reader bug: either way it
                % costs this one file, not the loop reading a folder.
                rec.Ok    = false;
                rec.Error = "could not read: " + string(ME.message);
                trace = [];  sw = emptySweeps();  notes = emptyNotes();
            end
        end

        function s = subjectOf(pth)
            % The canonical subject in a path or file name.
            %
            %   s = subjectOf(pth)
            %
            %   pth  a path or a name (string array for several)
            %   s    (returned) "SUBJ-ID-" + upper(id) for the FIRST match from
            %        the left of SUBJ[-_ ]?ID[-_ ]?([A-Za-z0-9]+), ignoring case;
            %        "" when there is none. Same size as pth.
            %
            %   First from the left, so the shallowest folder naming a subject
            %   wins: .../SUBJ-ID-1254/SUBJ-ID-1254_261001T140000/x.abr is
            %   SUBJ-ID-1254. One canonical spelling because the writers have
            %   used several -- SUBJ-ID-1254 and SUBJ_ID_1254 sit side by side
            %   in one folder of the user's own data -- and one animal must not
            %   become two subjects.
            arguments
                pth string
            end
            s = strings(size(pth));
            for k = 1:numel(pth)
                s(k) = matchSubject(pth(k));
            end
        end

        function [s,raw] = canonicalSubject(token)
            % One subject spelling, canonical.
            %
            %   [s,raw] = canonicalSubject(token)
            %
            %   token  a bare id ("1254", "abc") or any spelling of a subject
            %          ("SUBJ_ID_1254", "subj-id-959")
            %   s      (returned) "SUBJ-ID-" + upper(id); "" for empty text
            %   raw    (returned) the subject as found in token: the matched
            %          spelling ("SUBJ_ID_1254"), or the bare id itself
            %
            %   What a typed subject override goes through, so "959",
            %   "subj_id_959" and "SUBJ-ID-959" all name one animal.
            arguments
                token (1,1) string
            end
            s = "";  raw = "";
            if ismissing(token), return; end
            t = strtrim(token);
            if t == "", return; end
            raw = t;
            [c,r] = matchSubject(t);
            if c ~= ""
                s = c;  raw = r;
            elseif isempty(regexp(char(t),'^SUBJ[-_ ]?ID[-_ ]?$','once','ignorecase'))
                s = "SUBJ-ID-" + upper(t);
            end
        end

        function tf = isCompact(onsets,L,numelData)
            % Whether a file holds an intermixed run's back-to-back windows.
            %
            %   tf = isCompact(onsets,L,numelData)
            %
            %   onsets     ADC.SweepOnsets
            %   L          ADC.SweepLength (anything but a positive integer:
            %              false)
            %   numelData  numel(ADC.Data)
            %   tf         (returned) numel(onsets) >= 1 && onsets(1) == 1 &&
            %              all(diff(onsets) == L) && numelData == n*L
            %
            %   mabr.compute.Pipeline cuts each condition of an intermixed run
            %   out as windows placed end to end, so those are exactly its
            %   files' shape. A continuous run never matches: its trace begins
            %   with at least 0.1 s of silence, so its first onset is far past
            %   sample 1. The layout is judged from the samples, never from a
            %   name or a strategy setting, neither of which the file records.
            arguments
                onsets {mustBeNumeric}
                L {mustBeNumeric}
                numelData {mustBeNumeric}
            end
            tf = false;
            if ~isscalar(L) || ~isscalar(numelData), return; end
            L = double(L);
            if ~(isfinite(L) && L > 0 && L == round(L)), return; end
            on = double(onsets(:));
            n  = numel(on);
            tf = n >= 1 && on(1) == 1 && all(diff(on) == L) && double(numelData) == n*L;
        end
    end
end

% =========================================================================
%  Reading
% =========================================================================
function [rec,trace,sw,notes] = readFile(rec,opts)
% The file on disk, loaded under a scoped warning capture, then parsed.
trace = [];  sw = emptySweeps();  notes = emptyNotes();
[rec.Subject,rec.SubjectRaw] = matchSubject(rec.FileName);
if ~isfile(rec.Path)
    rec.Error = "file not found";
    return
end
d = dir(char(rec.Path));
if numel(d) ~= 1
    rec.Error = "file not found";
    return
end
rec.Path     = string(fullfile(d.folder,d.name));
rec.Folder   = string(d.folder);
rec.FileName = string(d.name);
rec.Bytes    = d.bytes;
rec.Modified = datetime(d.datenum,'ConvertFrom','datenum');
[rec.Subject,rec.SubjectRaw] = matchSubject(rec.FileName);

% Every warning is switched off for the load and the parse and collected
% from lastwarn instead, so a folder's worth of legacy files reconstructing
% audioPlayerRecorders and sigProps prints nothing -- and a warning a caller
% had set to 'error' cannot turn a readable file into a failure. The
% caller's state, lastwarn included, is restored by onCleanup on every path
% out, error or not. quietDeviceWarnings is redundant under 'off all' but is
% the guard every .abr load in MABR holds.
w0 = warning;
[lwMsg,lwId] = lastwarn;
restore = onCleanup(@() restoreWarnings(w0,lwMsg,lwId));
quiet = mabr.data.io.quietDeviceWarnings(); %#ok<NASGU>
warning('off','all');
lastwarn('');
warns = strings(0,1);
try
    S = load(char(rec.Path),'-mat','ABR_Data');
catch ME
    rec.Error    = "could not load: " + string(ME.message);
    rec.Warnings = takeLastwarn(warns,"load");
    return
end
warns = takeLastwarn(warns,"load");
try
    [rec,trace,sw,notes,warns] = parseFile(S,rec,opts,warns);
catch ME
    rec.Ok    = false;
    rec.Error = "could not read: " + string(ME.message);
    trace = [];  sw = emptySweeps();  notes = emptyNotes();
end
rec.Warnings = takeLastwarn(warns,"read");
end

function [rec,trace,sw,notes,warns] = parseFile(S,rec,opts,warns)
% Fill rec, sw, trace and notes from a loaded file's variables.
trace = [];  sw = emptySweeps();  notes = emptyNotes();
notRecording = "not an ABR recording (no ADC.Data/SweepOnsets)";
if ~isfield(S,'ABR_Data') || ~isstruct(S.ABR_Data) || ~isscalar(S.ABR_Data)
    rec.Skipped = true;
    rec.Error   = notRecording;
    return
end
A = S.ABR_Data;
if isfield(A,'SoftwareVersion'), rec.Era = "E1+"; else, rec.Era = "E0"; end
if ~(isfield(A,'ADC') && isstruct(A.ADC) && isscalar(A.ADC) ...
        && isfield(A.ADC,'Data') && isfield(A.ADC,'SweepOnsets'))
    rec.Skipped = true;
    rec.Error   = notRecording;
    return
end
ADC = A.ADC;

% ---- What the file says about the run, the stimulus and the units.
if isfield(A,'StartTime'), rec.StartTime = parseTime(A.StartTime); end
rec.TestMode = flagField(A,'TestMode');
if isfield(A,'DAC') && isstruct(A.DAC) && isscalar(A.DAC)
    rec.DACSampleRate = numberField(A.DAC,'SampleRate');
end
SIG = struct();
if isfield(A,'SIG') && isstruct(A.SIG) && isscalar(A.SIG), SIG = A.SIG; end
[rec.Stimulus,rec.StimClass,rec.StimID] = stimulusOf(SIG);
[rec.ParamNames,rec.Params,warns] = parametersOf(SIG,rec.Era,warns);
rec.ParamText = paramText(rec.ParamNames,rec.Params);
alt = numberField(SIG,'alternatePolarity');
rec.AlternatePolarity = ~isnan(alt) && alt ~= 0;
rec.Calibrated      = flagField(SIG,'Calibrated');
rec.CalibrationTime = textField(SIG,'CalibrationTime');
rec.LevelScale      = numberField(SIG,'LevelScale');
if rec.Calibrated
    rec.LevelUnit = "dB SPL";
elseif isfield(SIG,'LevelScale')
    rec.LevelUnit = "dB re max";       % relative to the bank's loudest entry
else
    rec.LevelUnit = "dB";
end
rec.AmplifierGain  = numberField(ADC,'AmplifierGain');
rec.InputFullScale = numberField(ADC,'InputFullScale');
hasGain = hasNumber(ADC,'AmplifierGain');
if hasGain && hasNumber(ADC,'InputFullScale')
    rec.Units = "V";
elseif hasGain
    rec.Units = "V-unscaled";
else
    rec.Units = "converter";
end

% ---- The samples and the sweeps.
data = ADC.Data;
if ~isnumeric(data) || ~isnumeric(ADC.SweepOnsets)
    rec.Error = "ADC.Data or ADC.SweepOnsets is not numeric";
    return
end
Fs = numberField(ADC,'SampleRate');
rec.SampleRate  = Fs;
rec.SweepLength = numberField(ADC,'SweepLength');
on0   = double(ADC.SweepOnsets(:));
n0    = numel(on0);
nData = numel(data);
compact = mabr.analysis.AbrFile.isCompact(on0,rec.SweepLength,nData);
if compact
    rec.Layout = "compact";     rec.AcqMode = "interleaved";
else
    rec.Layout = "continuous";  rec.AcqMode = "conventional";
end
if ~(isfinite(Fs) && Fs > 0)
    rec.Error = "ADC.SampleRate is missing or not a positive number";
    return
end
if nData == 0
    rec.Error = "ADC.Data holds no samples";
    return
end
rec.Duration = nData/Fs;
% A NaN or Inf in the samples (a dropped buffer, a bad conversion) is said
% here and handled by the segmenter, which leaves out the sweeps it reaches:
% the file is still a recording, and one bad sample must cost those sweeps,
% not the file -- and still less the session, as it did when it reached the
% filter.
nBad = nnz(~isfinite(data));
if nBad > 0
    warns(end+1,1) = sprintf(['ADC.Data holds %d non-finite sample(s) (NaN or Inf); the sweeps ' ...
        'they reach are left out when the session is segmented'],nBad);
end

% An E0 file decimated its onsets with round(onset/16) and no floor, so its
% first onset can be 0 -- not an index. Such onsets go, as does one that is
% not a number at all (NaN, Inf: no sample anywhere, and an Inf kept would
% count as a sweep and then fail every index made from it); every other
% sweep keeps its original ordinal in Index, so a manual rejection recorded
% against "sweep 40" still means the same sweep.
keep = on0 >= 1 & isfinite(on0);        % NaN fails the first test, Inf the second
if ~all(keep)
    bad  = find(~keep);
    list = strjoin(string(bad(1:min(end,5))).',', ');
    if numel(bad) > 5, list = list + ", ..."; end
    warns(end+1,1) = sprintf(['%d sweep onset(s) before sample 1 or not finite dropped ' ...
        '(sweep %s); the others keep their numbers'],numel(bad),list);
end
on  = on0(keep);
idx = reshape(find(keep),1,[]);
n   = numel(on);
if n >= 2 && any(diff(on) <= 0)
    warns(end+1,1) = "sweep onsets are not in increasing order";
end
if ~compact && n >= 2
    rec.MinISI = min(diff(on))/Fs*1000;
end
[art,warns] = artifactsOf(ADC,n0,warns);
[pol,warns] = polarityOf(ADC,n0,warns);

% A compact file's windows are copied whole even when the run stopped part
% way through the last one, and the uncovered part stays 0 -- so Data is
% exactly n*L long and no bounds check can tell. A final millisecond of
% exact zeros, which no recorded signal holds, is the tell.
valid = true(1,n);
if compact
    k = min(max(1,round(1e-3*Fs)),rec.SweepLength);
    if nData >= k && all(data(end-k+1:end) == 0)
        valid(end) = false;
        rec.TruncatedSweeps = 1;
    end
end

rec.NumSweeps = n;
sw = struct('Onset',on,'Index',idx,'IsArtifact',art(keep),'Polarity',pol(keep),'Valid',valid);
rec.Ok = true;
if opts.ReadTrace, trace = data(:); end
if opts.ReadNotes, [notes,warns] = notesOf(A,warns); end
end

% =========================================================================
%  The stimulus
% =========================================================================
function [stim,cls,id] = stimulusOf(SIG)
% Stimulus (the class without its package, else the ID's first token),
% StimClass as written, and the stimulus ID.
cls = textField(SIG,'StimClass');
id  = "";
if isfield(SIG,'Label')
    lbl = textArray(SIG.Label);
    for k = 1:numel(lbl)
        tok = regexp(char(lbl(k)),'^\s*ID\s*=\s*(.*\S)\s*$','tokens','once');
        if ~isempty(tok), id = string(tok{1}); break; end
    end
end
if id == "" && isfield(SIG,'ID')
    x = SIG.ID;
    if (ischar(x) && isrow(x)) || (isstring(x) && isscalar(x) && ~ismissing(x))
        id = strtrim(string(x));
    end
end
if cls ~= ""
    stim = string(regexp(char(cls),'[^.]*$','match','once'));
elseif id ~= ""
    stim = string(regexp(char(id),'^[^_]*','match','once'));
else
    stim = "";
end
end

function [names,P,warns] = parametersOf(SIG,era,warns)
% The informative parameters, mapped, renamed and valued (see the class help).
names = strings(1,0);
P = struct();
if ~isfield(SIG,'informativeParams'), return; end
try
    raw = cellstr(SIG.informativeParams);
catch
    warns(end+1,1) = "SIG.informativeParams is not text; no parameters read";
    return
end
raw = reshape(raw,1,[]);
reserved = mabr.analysis.AbrFile.ReservedNames;
for j = 1:numel(raw)
    p = strtrim(raw{j});
    if isempty(p), continue; end
    [v,src,why] = parameterValue(SIG,p);
    if src == ""
        warns(end+1,1) = sprintf('parameter %s: %s; read as NaN',p,why); %#ok<AGROW>
    elseif why ~= ""
        warns(end+1,1) = sprintf('parameter %s: %s',p,why); %#ok<AGROW>
    end
    nm = canonicalParam(p);
    if era == "E0" && src == "dataParams" && strcmpi(p,'frequency')
        v = v/1000;                     % legacy dataParams are in Hz; Frequency is kHz
    end
    if any(strcmpi(nm,reserved))
        warns(end+1,1) = sprintf(['parameter %s read as Stim_%s: %s is a column name ' ...
            'the analysis tables reserve'],nm,nm,nm); %#ok<AGROW>
        nm = "Stim_" + nm;
    end
    if ~isvarname(nm)
        good = string(matlab.lang.makeValidName(nm));
        warns(end+1,1) = sprintf('parameter "%s" read as %s, a valid name',nm,good); %#ok<AGROW>
        nm = good;
    end
    if any(names == nm)
        warns(end+1,1) = sprintf('parameter %s is listed twice (again as %s); the first is kept',nm,p); %#ok<AGROW>
        continue
    end
    names(end+1) = nm; %#ok<AGROW>
    P.(nm) = v;
end
end

function [v,src,why] = parameterValue(SIG,p)
% One parameter's value: SIG.(p) when it is a real non-integer number (a
% uint32 there is the placeholder MATLAB loads for a missing class), else
% SIG.dataParams.(p), else NaN. src says which ("" = neither); why says
% what was wrong, or that only the first of several values was taken.
v = NaN;  src = "";  why = "";
if isfield(SIG,p)
    x = SIG.(p);
    if isnumeric(x) && isreal(x) && ~isinteger(x) && ~isempty(x)
        v = double(x(1));  src = "SIG";
        if numel(x) > 1
            why = sprintf('SIG holds %d values; the first is used',numel(x));
        end
        return
    elseif isinteger(x)
        why = sprintf('SIG holds a %s, the placeholder for an object MATLAB could not load',class(x));
    else
        why = sprintf('SIG holds a %s, not a number',class(x));
    end
else
    why = "not in SIG";
end
dp = [];
if isfield(SIG,'dataParams') && isstruct(SIG.dataParams) && isscalar(SIG.dataParams)
    f = fieldnames(SIG.dataParams);
    k = find(strcmp(f,p),1);
    if isempty(k), k = find(strcmpi(f,p),1); end
    if ~isempty(k), dp = SIG.dataParams.(f{k}); end
end
if isnumeric(dp) && ~isempty(dp)
    v = double(real(dp(1)));  src = "dataParams";  why = "";
    if numel(dp) > 1
        why = sprintf('SIG.dataParams holds %d values; the first is used',numel(dp));
    end
    return
end
why = why + " and SIG.dataParams has none";
end

function nm = canonicalParam(p)
% The names MABR fixes end to end, whatever case a writer used.
switch lower(p)
    case 'frequency'
        nm = "Frequency";
    case {'soundlevel','level'}
        nm = "Level";
    otherwise
        nm = string(p);
end
end

function s = paramText(names,P)
% "Frequency=8; Level=80": %g values, names sorted case-insensitively -- the
% order condition keys put parameters in -- so two files of one condition
% read alike whatever order their informativeParams were written in.
s = "";
if isempty(names), return; end
[~,o] = sort(lower(names));
parts = strings(1,numel(o));
for k = 1:numel(o)
    parts(k) = names(o(k)) + "=" + sprintf('%g',P.(names(o(k))));
end
s = join(parts,"; ");
end

% =========================================================================
%  The sweeps
% =========================================================================
function [art,warns] = artifactsOf(ADC,n0,warns)
% The rig's artifact flags, one per ORIGINAL onset. A scalar false is how an
% E0 file says "none"; any other count that does not match is ignored.
art = false(1,n0);
if ~isfield(ADC,'IsArtifact'), return; end
a = ADC.IsArtifact;
if ~(islogical(a) || isnumeric(a))
    warns(end+1,1) = "ADC.IsArtifact is not logical; no sweep flagged";
    return
end
if numel(a) == n0
    a   = double(reshape(a,1,[]));
    art = ~isnan(a) & a ~= 0;
elseif ~(isscalar(a) && double(a) == 0)
    warns(end+1,1) = sprintf(['ADC.IsArtifact holds %d value(s) for %d sweep onsets; ' ...
        'ignored, no sweep flagged'],numel(a),n0);
end
end

function [pol,warns] = polarityOf(ADC,n0,warns)
% Per-onset polarity as sign(ADC.SweepPolarity), 0 and NaN read as +1; all
% +1 where the field is absent (E0, and files before polarity was saved).
pol = ones(1,n0);
if ~isfield(ADC,'SweepPolarity'), return; end
p = ADC.SweepPolarity;
if isnumeric(p) && numel(p) == n0
    p = sign(double(reshape(p,1,[])));
    p(p == 0 | isnan(p)) = 1;
    pol = p;
else
    warns(end+1,1) = sprintf('ADC.SweepPolarity holds %d value(s) for %d sweep onsets; read as all +1', ...
        numel(p),n0);
end
end

function [notes,warns] = notesOf(A,warns)
% ABR_Data.Notes as an n x 1 struct array, tolerant of missing fields.
notes = emptyNotes();
if ~isfield(A,'Notes') || isempty(A.Notes), return; end
N = A.Notes;
if ~isstruct(N)
    warns(end+1,1) = "ABR_Data.Notes is not a struct; notes not read";
    return
end
N = N(:);
m = numel(N);
notes = repmat(struct('Stamp',"",'Text',"",'Time',NaT,'Run',NaN,'Sweep',NaN,'Source',""),m,1);
hasTime = isfield(N,'Time');
for k = 1:m
    notes(k).Stamp  = textField(N(k),'Stamp');
    notes(k).Text   = textField(N(k),'Text');
    if hasTime, notes(k).Time = parseTime(N(k).Time); end
    notes(k).Run    = numberField(N(k),'Run');
    notes(k).Sweep  = numberField(N(k),'Sweep');
    notes(k).Source = textField(N(k),'Source');
end
end

% =========================================================================
%  Small readers -- each tolerant of an absent or malformed field
% =========================================================================
function t = parseTime(x)
% A StartTime: ISO first (every MABR file), then the en_US 'dd-MMM-yyyy
% HH:mm:ss' of a legacy +abr file, then whatever datetime() makes of it.
t = NaT;
try
    if isdatetime(x)
        if ~isempty(x), t = x(1); end
        return
    end
    if isnumeric(x)
        if isscalar(x) && isfinite(x) && x > 0, t = datetime(x,'ConvertFrom','datenum'); end
        return
    end
    if isstring(x) && isscalar(x) && ~ismissing(x), x = char(x); end
    if ~ischar(x) || isempty(x), return; end
    s = strtrim(x(1,:));
    if isempty(s), return; end
    try
        t = datetime(s,'InputFormat','yyyy-MM-dd''T''HH:mm:ss');
        return
    catch
    end
    try
        t = datetime(s,'InputFormat','dd-MMM-yyyy HH:mm:ss','Locale','en_US');
        return
    catch
    end
    t = datetime(s);
    if ~isscalar(t), t = NaT; end
catch
    t = NaT;
end
end

function v = numberField(s,f)
% s.(f)(1) as a double, NaN when absent, empty or not a number.
v = NaN;
if isfield(s,f)
    x = s.(f);
    if (isnumeric(x) || islogical(x)) && ~isempty(x)
        v = double(real(x(1)));
    end
end
end

function tf = hasNumber(s,f)
% Whether s.(f) exists and holds a number.
tf = isfield(s,f) && (isnumeric(s.(f)) || islogical(s.(f))) && ~isempty(s.(f));
end

function tf = flagField(s,f)
% s.(f) as a logical: false when absent, empty, NaN or not a number.
v  = numberField(s,f);
tf = ~isnan(v) && v ~= 0;
end

function v = textField(s,f)
% s.(f) as a string scalar, "" when absent or not a text scalar.
v = "";
if isfield(s,f)
    x = s.(f);
    if ischar(x) && (isrow(x) || isempty(x))
        v = string(x);
    elseif isstring(x) && isscalar(x) && ~ismissing(x)
        v = x;
    end
end
end

function s = textArray(x)
% A label of any text shape (char row or matrix, cellstr, string array, or a
% cell mixing them) as a string column; anything else as none.
s = strings(0,1);
try
    if ischar(x)
        s = string(cellstr(x));
    elseif isstring(x)
        s = x;
    elseif iscell(x)
        ok = cellfun(@(e) (ischar(e) && (isrow(e) || isempty(e))) || (isstring(e) && isscalar(e)),x);
        s = string(x(ok));
    end
    s = reshape(s,[],1);
    s(ismissing(s)) = [];
catch
    s = strings(0,1);
end
end

% =========================================================================
%  Subjects
% =========================================================================
function [canon,raw] = matchSubject(text)
% The first SUBJ...ID...<id> in text: canonical, and as spelled.
canon = "";  raw = "";
text = string(text);
if ~isscalar(text) || ismissing(text), return; end
[tok,m] = regexp(char(text),'SUBJ[-_ ]?ID[-_ ]?([A-Za-z0-9]+)','tokens','match','once','ignorecase');
if isempty(m), return; end
canon = "SUBJ-ID-" + upper(string(tok{1}));
raw   = string(m);
end

% =========================================================================
%  Blanks and warnings
% =========================================================================
function rec = blankRecord(ffn)
% Every field of rec at the value a file that was never read has.
[folder,name,ext] = fileparts(char(ffn));
rec = struct( ...
    'Path',ffn,'Folder',string(folder),'FileName',string([name ext]), ...
    'Bytes',NaN,'Modified',NaT, ...
    'Ok',false,'Skipped',false,'Error',"", ...
    'Era',"",'StartTime',NaT,'SampleRate',NaN,'DACSampleRate',NaN, ...
    'NumSweeps',0,'SweepLength',NaN,'Layout',"",'AcqMode',"", ...
    'Duration',NaN,'MinISI',NaN,'TestMode',false, ...
    'Stimulus',"",'StimClass',"",'StimID',"", ...
    'ParamNames',strings(1,0),'Params',struct(),'ParamText',"", ...
    'AlternatePolarity',false,'Units',"",'AmplifierGain',NaN,'InputFullScale',NaN, ...
    'Calibrated',false,'CalibrationTime',"",'LevelScale',NaN,'LevelUnit',"", ...
    'TruncatedSweeps',0,'Subject',"",'SubjectRaw',"",'Warnings',strings(0,1));
end

function sw = emptySweeps()
sw = struct('Onset',zeros(0,1),'Index',zeros(1,0),'IsArtifact',false(1,0), ...
    'Polarity',zeros(1,0),'Valid',false(1,0));
end

function notes = emptyNotes()
notes = struct('Stamp',cell(0,1),'Text',cell(0,1),'Time',cell(0,1), ...
    'Run',cell(0,1),'Sweep',cell(0,1),'Source',cell(0,1));
end

function warns = takeLastwarn(warns,stage)
% Move whatever MATLAB last warned into warns, labelled with the stage it
% was raised in ("load" or "read"), and clear it.
msg = lastwarn;
if ~isempty(msg)
    warns(end+1,1) = stage + ": " + string(strtrim(msg));
end
lastwarn('');
end

function restoreWarnings(w0,msg,id)
% The caller's warning state and lastwarn, exactly as they were.
warning(w0);
lastwarn(msg,id);
end
