classdef Session < handle
% mabr.analysis.Session  One ABR session -- a folder, or a pool of folders -- analysed offline.
%
%   A Session is one folder of .abr files -- one animal, one sitting -- taken
%   from files on disk through to thresholds. It owns exactly that much:
%   there is nothing in here that loops over subjects or studies, because a
%   study is a loop you write, over an object that only ever has to be right
%   about one session:
%
%       paths = mabr.analysis.Session.find(rootPath);
%       for k = 1:numel(paths)
%           s = mabr.analysis.Session(paths(k));
%           s.segment();
%           s.reject();
%           s.estimateThresholds();
%           s.saveResults(fullfile(resultPath, s.Name + ".mat"));
%       end
%
%   A POOL is several folders of one animal read as one session --
%   Session([pathA; pathB]), named "A + B". Folders naming two subjects are
%   refused (mabr:analysis:Session:mixedSubjects) unless Force=true, and a file
%   copied into both folders is read once: the later copy is left out as a
%   duplicate, with its reason in Files.
%
%   The steps, each of which is one method that does one thing:
%
%     parse()               read every file through mabr.analysis.AbrFile into
%                           Files, one row per file, and decide which are
%                           INCLUDED (Files.Include) and why the rest are not
%     segment(...)          filter and window each included file into sweeps,
%                           grouped into Conditions -- one row per condition
%     reject(...)           flag artifact sweeps (flags, never deletions)
%     detect(...)           permutation-test each condition for a response
%     measure(...)          the single-trial measures (RN, power test, Fsp,
%                           split-half r, XCorrUp, DTWUp, per-sweep features)
%     estimateThresholds()  a threshold per series, by a named method
%                           (mabr.analysis.SeriesThreshold), curation kept
%     pickPeaks(...)        waves I-V picked and tracked down each series
%
%   analyze(settings) runs them all from one mabr.analysis.Settings -- the
%   RECOMMENDED defaults, per-condition seeds -- records what each step read
%   (StepState) so isStale(settings) can say what a change of settings or
%   files makes out of date, and is what the analysis app and
%   mabr.analysis.Batch call. Calling a step directly keeps that step's own
%   older defaults, so scripts written before named methods give the numbers
%   they always gave: estimateThresholds(FitTarget="binary") is the
%   detection threshold -- the level at which a response appears -- and
%   left on "auto" a sigmoid or isotonic fit is given the graded detection
%   strength instead, where Criterion = 0.5 is the half-maximum of the
%   growth function and therefore a larger number (mabr.analysis.Threshold).
%
%   EDITS are by key, atomic, logged in EditLog, and survive re-analysis:
%   acceptFit / setDecision / clearDecision / setThresholdNote curate a
%   series' threshold (Final* is the curated answer, beside the method's);
%   setSweepsRejected / clearManualRejections decide sweeps by hand (stored
%   by FileId and SweepIndex); setDetectionOverride decides a condition;
%   setExcluded leaves files out; setPeak / setPeakAbsent / clearPeak /
%   clearPeakOverrides / retrackSeries correct the peaks. A data edit runs
%   the cascade (recompute) with the options the session was analysed with.
%   editSnapshot/restoreEdits are undo; adoptEdits(E) takes the edits of a
%   results file, or of a plain struct of edit tables, and analyze() then
%   reproduces the original results bit for bit.
%
%   LATENCY OFFSET. Latencies are stored raw, re the electrical onset (the
%   timing pulse), and the wave windows are searched in that same time.
%   LatencyOffset = (ConductionDelayOverride, else the settings'
%   conductionDelay()) + (TimeOffset, else the settings' TimeOffset) -- the
%   session's value when finite, the analysed settings' otherwise -- is a
%   REPORTING correction only: mabr.analysis.Peaks.reported(PeakLatency,
%   LatencyOffset) is the latency re sound arrival, and setting a delay
%   shifts every reported latency by exactly it and changes no pick.
%
%   Everything each of them does to ONE condition lives in a separate class
%   and can be called on its own: mabr.analysis.Filter, .Artifacts, .PermTest,
%   .Threshold, .Plot, .Stats. Session is the orchestration, not the arithmetic.
%
%   CONDITIONS ARE A TABLE, not an N-D cell array, and they are identified by
%   KEY, never by row. Conditions.Key is "Name=Value" pairs joined by "|" --
%   "Stimulus=Tone|AcqMode=conventional|Frequency=8|Level=80" -- over
%   KeyParams: Stimulus (when the files name one), AcqMode, then the stimulus
%   parameters sorted by name. A parameter a stimulus does not have (a click's
%   Frequency) is NaN in its column and absent from its key, so a click and a
%   tone never share a condition and a missing value never crashes a grouping
%   (every grouping site goes through one NaN-safe helper). Rows move when a
%   session is re-segmented; keys do not, which is what lets curation, overrides
%   and manual rejections survive a re-analysis. grid() reshapes to the
%   [level x frequency] cell array and U struct the older functions use:
%
%       [S,U] = s.grid("Level","Frequency");
%
%   ACQUISITION MODES. A file holding one condition's continuous run is
%   AcqMode "conventional"; a file cut out of an intermixed run (compact:
%   10 ms windows back to back) is "interleaved". They are separate conditions
%   by default -- pooling changes the sweep count and the stimulus history, and
%   on real data lowered thresholds by up to 31 dB -- and segment(PoolAcqModes=
%   true) pools them under AcqMode "pooled".
%
%   SERIES. A threshold is fitted per series: every condition sharing all but
%   the level. Stimulus and AcqMode are ALWAYS part of a series' identity
%   (AcqMode unless the modes are pooled), whatever GroupBy is typed -- a
%   GroupBy that leaves them out has them added (seriesGrouping), so no
%   series ever fits clicks with tones, or a conventional run with an
%   interleaved one.
%
%   NO NOISE, NO STATISTIC. A condition whose clean sweeps do not vary
%   within their file x polarity groups (mabr.analysis.SingleTrial.
%   zeroVariance: an all-zero channel, a digital loop-back, noiseless data)
%   is not tested and has no noise-referenced measure: p, F, SNR, the power
%   test, Fsp and the split-half r are NaN, Conditions.Flags says "zero
%   variance", a warning names the conditions, and a threshold method
%   ignores those levels. (A sign-flip test of such sweeps has an unbounded
%   t, and its TFCE once integrated for a quarter of an hour.)
%
%   WINDOWED PROCESSING. A compact file has no pre-onset sample and a step at
%   every junction, so it is never filtered as one trace: each sweep's own
%   window is cut RAW and filtered alone (mabr.analysis.Filter.applyWindowed,
%   at the FIR chain's -6 dB points), rows of Time outside what the files hold
%   are NaN, and Conditions.Extent says which rows those are. Every other
%   condition keeps the whole-trace FIR path ("continuous").
%
%   FLAGGED SWEEPS ARE KEPT. Rejection writes a logical per sweep and nothing
%   more, with its reason (RejectReason: 1 the rig, 2 a criterion, 3 by hand);
%   sweeps() and every average exclude them by default, and asking for them
%   back is one argument away. This is the same rule the acquisition side
%   follows (mabr.data.Recording.IsArtifact), and it is what makes a rejection
%   setting something you can change your mind about without reloading. A cap
%   on the sweeps per condition (segment MaxSweepsPerCondition) marks the rest
%   Excess -- unused, not rejected.
%
%   ATOMIC STEPS. Every step computes into locals and commits in one block at
%   its end, so an error -- or a cancel, which is a progress sink throwing
%   mabr:analysis:cancelled (see ProgressFcn and mabr.analysis.Progress) --
%   leaves the object exactly as it was. Steps print only when Verbose; every
%   note and warning is also a row of Messages, and MessageFcn hears each one.
%
%   RESULTS are a plain struct of separate variables (results v2: toStruct,
%   saveResults, fromResults), written atomically, so the small parts of a
%   results file can be read without loading its sweeps.
%
%   See also mabr.analysis.AbrFile, mabr.analysis.Filter,
%   mabr.analysis.Artifacts, mabr.analysis.Threshold, mabr.analysis.Plot,
%   mabr.analysis.Stats, mabr.data.io

    properties (SetAccess = protected)
        Path    (1,1) string = ""        % Paths(1)
        Paths   (:,1) string = strings(0,1)  % folders this session was read from (a pool has several)
        Key     (1,1) string = ""        % catalog key (folder key or "pool:<hex8>"); default = Name
        FolderKeys (:,1) string = strings(0,1) % the member folders' keys (Key for one folder)
        Name    (1,1) string = ""        % folder name, or "A + B" for a pool
        Subject (1,1) string = ""        % canonical subject, "SUBJ-ID-1254"
        SubjectRaw (1,1) string = ""     % the subject as the path/file spells it
        Date    (1,1) datetime = NaT     % earliest included file's StartTime

        Files      table = table()       % one row per .abr file, included or not
        Conditions table = table()       % one row per stimulus condition
        Thresholds table = table()       % one row per threshold series
        Peaks      table = table()       % one row per condition x wave (pickPeaks)
        PeakOverrides      table = table()  % manual peak picks / absences, by key
        ManualRejections   table = table()  % per-sweep hand decisions, by FileId + SweepIndex
        DetectionOverrides table = table()  % per-condition hand verdicts, by key
        CurationArchive    table = table()  % curation of series whose key vanished
        Messages   table = table()       % every note and warning, by step
        EditLog    table = table()       % audit trail of every edit

        StepState struct = struct()      % per step: [] or struct(At,Settings,Fingerprint)
        StepOptions struct = struct()    % the options the last direct call of each step used
        Settings = []                    % mabr.analysis.Settings of the last analyze(); [] if never

        SampleRate (1,1) double = NaN    % Hz, ADC rate of the included files
        Window     (1,2) double = [-12 12]   % ms, segmentation window
        Time       (:,1) double = []     % ms, one entry per sweep sample
        ParamNames (1,:) string = string.empty  % stimulus parameters found ("Stimulus" first when named)
        KeyParams  (1,:) string = string.empty  % condition key columns, in key order
        LevelParam (1,1) string = ""     % level parameter the last estimateThresholds used
        GroupParams (1,:) string = string.empty % series parameters it used
        TestMode   (1,1) logical = false % an included file was recorded in Test Mode
        HasSweeps  (1,1) logical = false % sweeps are in memory (false for results only)
        Units      (1,1) string = ""     % "V" | "V-unscaled" | "converter" | "mixed"
        LevelUnit  (1,1) string = ""     % "dB SPL" | "dB re max" | "dB" | "mixed"
        AcqModes   (1,:) string = string.empty  % acquisition modes among included files
        DataFingerprint (1,1) string = "" % fingerprintOf every .abr of the folders
        Exclude    (:,1) string = strings(0,1)  % FileIds left out by the user
        Means      struct = struct('Keys',strings(0,1),'Balanced',zeros(0,0,'single'), ...
            'Positive',zeros(0,0,'single'),'Negative',zeros(0,0,'single'), ...
            'SEM',zeros(0,0,'single'),'N',zeros(0,1))   % results-only condition means
    end

    properties
        % Display filter applied to each whole trace before segmentation.
        Filter (1,1) mabr.analysis.Filter = mabr.analysis.Filter

        % Response window (ms) used for artifact features and detection.
        ResponseWindow (1,2) double = [0 10]

        % Regular expression a file name must match to be included.
        FilePattern (1,1) string = "\.abr$"

        % Keep each file's continuous trace in memory after parsing, so that
        % re-segmenting with another window or filter costs no disk reads.
        % Switch it off for a session too large to hold.
        KeepTraces (1,1) logical = true

        % Print progress, notes and warnings (Messages records them either way).
        Verbose (1,1) logical = true

        % Who is analysing: stamped on every edit.
        Analyst (1,1) string = string(getenv('USERNAME'))

        % Units override, applied to the traces at segment time: a finite
        % InputFullScale (V for 1.0 at the recorder) and/or AmplifierGain (V/V)
        % replace what the files recorded (see parse).
        UnitOverride struct = struct('InputFullScale',NaN,'AmplifierGain',NaN)

        % Per-session latency offsets, ms (NaN = none: the settings' own).
        % They decide LatencyOffset (below): TimeOffset replaces the
        % settings' TimeOffset (a fixed offset of the recording system) and
        % ConductionDelayOverride replaces the settings' conductionDelay()
        % (the sound's travel time from speaker to ear) for this session
        % alone -- a rig with a different speaker, say. mabr.analysis.Project
        % sets them from its Sessions.TimeOffsetOverride and
        % ConductionDelayOverride columns.
        TimeOffset (1,1) double = NaN
        ConductionDelayOverride (1,1) double = NaN
    end

    properties (Transient)
        % Progress sink fcn(message,count,total), handed to every
        % mabr.analysis.Progress a step creates. Throwing
        % MException('mabr:analysis:cancelled',...) from it cancels the step,
        % which then leaves the session unchanged.
        ProgressFcn = []

        % Called fcn(level,text) for every message appended to Messages.
        MessageFcn = []
    end

    properties (Dependent)
        NumFiles      (1,1) double
        NumConditions (1,1) double
        ResponseRows  (:,1) logical    % Time mask for ResponseWindow

        % ms between the recording's time and the ear's (read-only):
        %   (ConductionDelayOverride, else Settings.conductionDelay())
        % + (TimeOffset, else Settings.TimeOffset),
        % each part from the session when it is finite, else from the
        % settings the session was analysed with (0 when there are none).
        % Latencies are stored raw and Peaks.reported(PeakLatency,
        % LatencyOffset) is the latency re sound arrival; the wave windows
        % are searched in the recording's time whatever it is, so a delay
        % moves the reported latencies and never the picks.
        % Peaks.LatencyOffset records the value each pick is reported with.
        LatencyOffset (1,1) double
    end

    properties (Access = private)
        Traces cell = {}               % per Files row: cached raw trace, or []
        FileSweeps cell = {}           % per Files row: AbrFile's sw struct
        RawAvailable (1,1) logical = false   % parse() has read the folders
        Records = []                   % the AbrFile records parse() read (reinclude)
        FileList struct = struct('Ids',strings(0,1),'Bytes',zeros(0,1),'Modified',NaT(0,1))
    end

    properties (Access = private, Transient)
        PendingStep (1,1) string = ""  % the step whose messages are being collected
        PendingMessages table = table()
    end

    properties (Constant)
        % Column names Session reserves in its tables; a stimulus parameter
        % spelled like one is read as Stim_<name> (mabr.analysis.AbrFile).
        Reserved = mabr.analysis.AbrFile.ReservedNames

        % Parameter names recognized as the level and frequency axes when a
        % caller does not say. Case is ignored.
        LevelAliases     = ["Level","SoundLevel","Intensity","dB","Attenuation"]
        FrequencyAliases = ["Frequency","Freq","CF","Carrier"]

        Version = 2     % results file format

        % The analysis steps, in order (mabr.analysis.Settings.Steps).
        StepNames = ["segment","reject","detect","measure","thresholds","peaks"]

        % The per-condition columns measure() writes (beside Features).
        MeasureColumns = ["RN","RNPM","ResponseRMS","BaselineRMS","F","PowerP","PowerF95", ...
            "SNR","SNRCorr","Fsp","FspDF1","FspDF2","FspP","SplitR","SplitRSD","SplitRP025", ...
            "SplitRP975","SplitN","XCorrUp","XCorrLag","XCorrUp0","DTWUp","DTWLag","DTWLagRange"]

        % The human columns of Thresholds, carried by key across re-analyses.
        CurationColumns = ["Decision","ManualValue","ManualKind","Note","ReviewedBy", ...
            "ReviewedAt","ReviewedValue","ReviewedMethod"]

        % The flag measure() gives a condition whose baseline holds the
        % previous presentation's response.
        FlagBaselineOverlap = "baseline overlaps the previous response"
    end

    properties (Constant, Access = private)
        % Files columns that are not stimulus parameters. A parameter spelled
        % like one (a bank varying Duration) is read as Stim_<name>, the rule
        % AbrFile applies to the reserved names.
        FileColumns = ["timestamp","fileName","folder","nSweeps","SampleRate","TestMode", ...
            "FileId","Stimulus","StimID","AcqMode","Layout","SweepLength","AlternatePolarity", ...
            "Units","AmplifierGain","InputFullScale","LevelUnit","Calibrated","CalibrationTime", ...
            "Bytes","Modified","Duration","MinISI","Era","TruncatedSweeps","Include","Reason", ...
            "RunGroup","Short","DuplicateOf"]

        % The per-sweep cell columns of Conditions, in table order.
        SweepColumns = ["Sweeps","Rejected","RejectReason","Polarity","SweepFile", ...
            "SweepIndex","SweepOrder","SweepTime","Excess"]

        % Files in one run group start within this many seconds of the end of
        % the run so far.
        RunGap = 120

        % What a composite edit backs up, to put back on an error or cancel.
        BackupProps = ["Files","Conditions","Thresholds","Peaks","PeakOverrides", ...
            "ManualRejections","DetectionOverrides","CurationArchive","Messages","EditLog", ...
            "StepState","StepOptions","Settings","SampleRate","Window","Time","ParamNames", ...
            "KeyParams","LevelParam","GroupParams","TestMode","HasSweeps","Units","LevelUnit", ...
            "AcqModes","DataFingerprint","Exclude","Means","Date","Filter","ResponseWindow", ...
            "Traces","FileSweeps","RawAvailable","Records","FileList","Subject","SubjectRaw"]
    end

    methods
        % =================================================================
        %  Construction
        % =================================================================
        function obj = Session(sessionPaths,opts)
            % Session(paths,Name=Value) reads the file list and metadata.
            %
            %   sessionPaths         a folder of .abr files, or several (a POOL of
            %                        one subject's folders); default "" = an
            %                        empty, unparsed Session
            %   opts.FilePattern     regex a file name must match (default "\.abr$")
            %   opts.Filter          a mabr.analysis.Filter (default: the class default)
            %   opts.Window          [t0 t1] ms segmentation window (default [-12 12])
            %   opts.ResponseWindow  [t0 t1] ms response window (default [0 10])
            %   opts.KeepTraces      cache whole traces in memory (default true)
            %   opts.Verbose         print progress (default true)
            %   opts.Parse           call parse() at construction (default true)
            %   opts.Name            display name ("" = the folder name, or
            %                        "A + B (+k)" for a pool)
            %   opts.Key             catalog key ("" = Name)
            %   opts.FolderKeys      the member folders' catalog keys ("" = Key
            %                        for one folder, the folder names for a pool)
            %   opts.Exclude         FileIds ("<folder>/<file>") to leave out
            %   opts.Force           allow folders naming different subjects
            %   opts.UnitOverride    struct InputFullScale/AmplifierGain (NaN = none)
            %   opts.Analyst         who is analysing (default: the OS user)
            %   obj  (returned) the constructed Session
            arguments
                sessionPaths (:,1) string = ""
                opts.FilePattern (1,1) string = "\.abr$"
                opts.Filter = []
                opts.Window (1,2) double = [-12 12]
                opts.ResponseWindow (1,2) double = [0 10]
                opts.KeepTraces (1,1) logical = true
                opts.Verbose (1,1) logical = true
                opts.Parse (1,1) logical = true
                opts.Name (1,1) string = ""
                opts.Key (1,1) string = ""
                opts.FolderKeys (:,1) string = strings(0,1)
                opts.Exclude (:,1) string = strings(0,1)
                opts.Force (1,1) logical = false
                opts.UnitOverride struct = struct('InputFullScale',NaN,'AmplifierGain',NaN)
                opts.Analyst (1,1) string = string(getenv('USERNAME'))
            end
            obj.resetTables();
            obj.FilePattern    = opts.FilePattern;
            obj.Window         = sort(opts.Window);
            obj.ResponseWindow = sort(opts.ResponseWindow);
            obj.KeepTraces     = opts.KeepTraces;
            obj.Verbose        = opts.Verbose;
            obj.Analyst        = opts.Analyst;
            obj.UnitOverride   = opts.UnitOverride;      % checked by set.UnitOverride
            ex = opts.Exclude(~ismissing(opts.Exclude) & opts.Exclude ~= "");
            obj.Exclude        = unique(ex,'stable');
            if ~isempty(opts.Filter)
                if ~isa(opts.Filter,'mabr.analysis.Filter')
                    error('mabr:analysis:Session:badFilter', ...
                        'Filter must be a mabr.analysis.Filter, not a %s.',class(opts.Filter));
                end
                obj.Filter = opts.Filter;
            end

            paths = sessionPaths(~ismissing(sessionPaths));
            paths = paths(strtrim(paths) ~= "");
            if isempty(paths), return; end
            paths = regexprep(paths,'[\\/]+$','');
            paths = unique(paths,'stable');

            names = strings(numel(paths),1);
            for k = 1:numel(paths), names(k) = mabr.analysis.Session.folderName(paths(k)); end
            obj.Paths = paths;
            obj.Path  = paths(1);
            if opts.Name ~= ""
                obj.Name = opts.Name;
            elseif isscalar(paths)
                obj.Name = names(1);
            else
                obj.Name = names(1) + " + " + names(2);
                if numel(paths) > 2
                    obj.Name = obj.Name + " (+" + (numel(paths) - 2) + ")";
                end
            end
            if opts.Key ~= "", obj.Key = opts.Key; else, obj.Key = obj.Name; end
            fk = opts.FolderKeys(~ismissing(opts.FolderKeys) & opts.FolderKeys ~= "");
            if ~isempty(fk)
                obj.FolderKeys = fk;
            elseif isscalar(paths)
                obj.FolderKeys = obj.Key;
            else
                obj.FolderKeys = names;
            end

            % The subject comes from the folders first -- a session folder is
            % named for its animal, whatever its files were called -- and a
            % pool of two animals is refused, since averaging across animals
            % is a study-level decision, not something a folder list implies.
            subj = mabr.analysis.AbrFile.subjectOf(paths);
            have = unique(subj(subj ~= ""),'stable');
            if numel(have) > 1
                if ~opts.Force
                    error('mabr:analysis:Session:mixedSubjects', ...
                        ['These folders name different subjects (%s). Pass Force=true to ' ...
                         'pool them anyway.'],strjoin(reshape(have,1,[]),', '));
                end
                obj.warn('Pooling folders of different subjects (%s); the session is filed under %s.', ...
                    strjoin(reshape(have,1,[]),', '),have(1));
            end
            if ~isempty(have)
                obj.Subject = have(1);
                k = find(subj == have(1),1);
                [~,obj.SubjectRaw] = mabr.analysis.AbrFile.canonicalSubject(paths(k));
            end
            obj.ForceSubjects = opts.Force;

            if opts.Parse, obj.parse(); end
        end

        % =================================================================
        %  1. Parse -- every file, and which are included
        % =================================================================
        function T = parse(obj)
            % Read every matching .abr file through mabr.analysis.AbrFile into Files.
            %
            % One row per file, readable or not: the stimulus parameters
            % (ParamNames) first, then what the file says about itself and the
            % verdict -- Include, and the Reason for leaving it out:
            %   - not a readable recording (the reader's own reason);
            %   - in Exclude ("excluded by user");
            %   - the same recording found again in another folder of a pool
            %     ("duplicate of <FileId>": same name, sweeps, samples, start);
            %   - recorded in Test Mode while the session also holds real data
            %     ("Test Mode (the stimulus, not a subject)");
            %   - at a sample rate other than the session's majority one.
            % ParamNames is the union of the included files' parameters in the
            % order first seen, with "Stimulus" first when any file names one,
            % so a folder whose first file is a click still keeps Frequency.
            % RunGroup groups files that ran together (one Stimulus x AcqMode,
            % each starting within RunGap s of the run's end so far, no condition
            % twice); Short marks a run of
            % under half its group's median sweep count.
            %
            %   obj  (uses Paths, FilePattern, KeepTraces, Exclude)
            %   T    (returned) obj.Files, also stored on the object
            guard = obj.beginStep("parse"); %#ok<NASGU>
            [list,allIds,allBytes,allMod] = obj.listFiles();
            n = numel(list);

            recC = cell(n,1);  traces = cell(n,1);  sws = cell(n,1);
            p = mabr.analysis.Progress(n,sprintf('Reading %d files',n),obj.Verbose,obj.ProgressFcn);
            for i = 1:n
                [recC{i},tr,sws{i}] = mabr.analysis.AbrFile.read(list(i),ReadTrace=obj.KeepTraces);
                if obj.KeepTraces && recC{i}.Ok, traces{i} = tr; end
                p.step();
            end
            p.close();

            fp = mabr.analysis.Session.fingerprintOf(allIds,allBytes,allMod,obj.Exclude);
            if n == 0
                F = mabr.analysis.Session.emptyFiles(strings(1,0));
                obj.warn('No .abr files matching "%s" in %s.',obj.FilePattern,strjoin(reshape(obj.Paths,1,[]),'; '));
                obj.Files = F;  obj.Traces = {};  obj.FileSweeps = {};
                obj.RawAvailable = true;
                obj.Records = [];
                obj.FileList = struct('Ids',allIds,'Bytes',allBytes,'Modified',allMod);
                obj.ParamNames = string.empty;
                obj.KeyParams  = "AcqMode";
                obj.SampleRate = NaN;  obj.Date = NaT;  obj.TestMode = false;
                obj.Units = "";  obj.LevelUnit = "";  obj.AcqModes = string.empty;
                obj.DataFingerprint = fp;
                obj.StepState = mabr.analysis.Session.emptyStepState();
                obj.commitMessages("parse",true);
                T = obj.Files;
                return
            end
            recs = vertcat(recC{:});

            [F,pn,info] = obj.filesTable(recs);
            obj.reportParse(F,recs,info);

            % ---- Session-level facts, over the included files.
            inc = F.Include;
            rate = NaN;
            if any(inc), rate = F.SampleRate(find(inc,1)); end
            subject = obj.Subject;  subjectRaw = obj.SubjectRaw;
            if subject == "" && any(inc)
                [subject,subjectRaw] = mabr.analysis.Session.dominantSubject(recs(inc));
            end
            if numel(obj.Paths) > 1 && obj.Subject == ""
                obj.checkFolderSubjects(recs(inc));
            end
            dt = F.timestamp(inc);
            d0 = NaT;
            if any(~isnat(dt)), d0 = min(dt(~isnat(dt))); end
            if numel(obj.Paths) > 1
                days = unique(dateshift(dt(~isnat(dt)),'start','day'));
                if numel(days) > 1
                    obj.warn('The pooled folders span %d days (%s to %s).',numel(days), ...
                        char(days(1),'yyyy-MM-dd'),char(days(end),'yyyy-MM-dd'));
                end
            end
            tm = any(F.TestMode(inc));
            if tm
                obj.warn(['%d of %d included files were recorded in TEST MODE: those samples ' ...
                    'are the stimulus, not a subject.'],sum(F.TestMode(inc)),sum(inc));
            end
            [units,levelUnit] = obj.sessionUnits(F);
            modes = mabr.analysis.Session.acqModesOf(F.AcqMode(inc));

            % Conditions already cut point at Files rows: when the files come
            % back in another order they are re-pointed by FileId, and when
            % some are gone the conditions are stale until segment() again.
            C = obj.Conditions;
            remap = false;
            if height(C) > 0 && ismember('SweepFile',C.Properties.VariableNames) ...
                    && ismember('FileId',obj.Files.Properties.VariableNames)
                [tf,loc] = ismember(obj.Files.FileId,F.FileId);
                if ~all(tf)
                    obj.warn(['%d file(s) the conditions were cut from are no longer read; ' ...
                        'segment() again.'],sum(~tf));
                elseif ~isequal(loc(:),(1:height(obj.Files)).')
                    for r = 1:height(C)
                        C.SweepFile{r} = reshape(loc(C.SweepFile{r}),1,[]);
                    end
                    remap = true;
                end
            end

            % ---- Commit.
            if remap, obj.Conditions = C; end
            obj.Files      = F;
            obj.Traces     = traces;
            obj.FileSweeps = sws;
            obj.RawAvailable = true;
            obj.Records    = recs;
            obj.FileList   = struct('Ids',allIds,'Bytes',allBytes,'Modified',allMod);
            obj.ParamNames = pn;
            obj.KeyParams  = mabr.analysis.Session.keyParamsFor(pn);
            obj.SampleRate = rate;
            obj.Date       = d0;
            obj.TestMode   = tm;
            obj.Subject    = subject;
            obj.SubjectRaw = subjectRaw;
            obj.Units      = units;
            obj.LevelUnit  = levelUnit;
            obj.AcqModes   = modes;
            obj.DataFingerprint = fp;
            obj.StepState  = mabr.analysis.Session.emptyStepState();
            obj.commitMessages("parse",true);
            T = obj.Files;
        end

        % =================================================================
        %  2. Segment -- filter each trace, window it into sweeps
        % =================================================================
        function T = segment(obj,opts)
            % Filter and window every included file into Conditions.
            %
            % Files sharing a condition KEY are CONCATENATED into one condition
            % rather than overwriting each other, so a repeated or topped-up
            % measurement adds sweeps instead of replacing them; the sweeps of a
            % condition are in acquisition order (file start, then onset).
            %
            % A condition is "continuous" -- every file's whole trace filtered by
            % Filter (the FIR chain) and then windowed, exactly as before -- unless
            % one of its files is compact (an intermixed run), or Processing is
            % "windowed": then each sweep's own window is cut RAW over the
            % condition's Extent (Window intersected with what its compact files
            % hold, [0 (L-1)/Fs]) and filtered alone by Filter.applyWindowed, and
            % the rows of Time outside the Extent are NaN.
            %
            %   opts.Window                   [t0 t1] ms; overrides and updates obj.Window
            %   opts.Filter                   a mabr.analysis.Filter; overrides and updates obj.Filter
            %   opts.HonorAcquisitionArtifacts seed rejection flags from the
            %                                 rig's own ADC.IsArtifact (default true)
            %   opts.Detrend                  polynomial order to detrend each
            %                                 continuous sweep by, NaN = none (default NaN)
            %   opts.Processing               "auto" (default) or "windowed" (every condition)
            %   opts.WindowedOrder            Butterworth order of the windowed operator (default 2)
            %   opts.PadMode                  "reflect" (default) or "zeroleft"
            %   opts.PoolAcqModes             pool conventional and interleaved
            %                                 files of one condition (default false)
            %   opts.MaxSweepsPerCondition    cap on the clean sweeps used (default
            %                                 Inf); the rest are marked Excess
            %   opts.EqualizeMode             "first" (default) or "random" sweeps kept
            %   opts.Seed                     seed for "random" (default 1)
            %   opts.Keys                     re-segment only these condition keys
            %                                 (the Window must not change)
            %   T  (returned) obj.Conditions, also stored on the object
            arguments
                obj
                opts.Window double = []
                opts.Filter = []
                opts.HonorAcquisitionArtifacts (1,1) logical = true
                opts.Detrend (1,1) double = NaN   % polynomial order, NaN = none
                opts.Processing (1,1) string {mustBeMember(opts.Processing,["auto","windowed"])} = "auto"
                opts.WindowedOrder (1,1) double {mustBeInteger,mustBeInRange(opts.WindowedOrder,1,8)} = 2
                opts.PadMode (1,1) string {mustBeMember(opts.PadMode,["reflect","zeroleft"])} = "reflect"
                opts.PoolAcqModes (1,1) logical = false
                opts.MaxSweepsPerCondition (1,1) double {mustBePositive} = Inf
                opts.EqualizeMode (1,1) string {mustBeMember(opts.EqualizeMode,["first","random"])} = "first"
                opts.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 1
                opts.Keys (:,1) string = strings(0,1)
            end
            guard = obj.beginStep("segment"); %#ok<NASGU>
            obj.requireFiles();
            obj.requireRaw();

            win = obj.Window;
            if ~isempty(opts.Window)
                if numel(opts.Window) ~= 2
                    error('mabr:analysis:Session:badWindow','Window is [t0 t1] in ms.');
                end
                win = sort(double(reshape(opts.Window,1,2)));
            end
            subset = ~isempty(opts.Keys);
            if subset && (~isequal(win,obj.Window) || height(obj.Conditions) == 0 || isempty(obj.Time))
                error('mabr:analysis:Session:subsetWindow', ...
                    ['Re-segmenting some conditions needs the window the others were cut with ' ...
                     '([%g %g] ms); segment every condition to change it.'],obj.Window(1),obj.Window(2));
            end
            f = obj.Filter;
            if ~isempty(opts.Filter)
                if ~isa(opts.Filter,'mabr.analysis.Filter')
                    error('mabr:analysis:Session:badFilter', ...
                        'Filter must be a mabr.analysis.Filter, not a %s.',class(opts.Filter));
                end
                f = opts.Filter;
            end
            Fs = obj.SampleRate;
            if ~f.IsDesigned || f.SampleRate ~= Fs
                f = f.design(Fs);
            end

            w      = round(Fs*win/1000);
            winIdx = (w(1):w(2)).';
            time   = 1000*winIdx/Fs;
            nT     = numel(winIdx);

            % Condition identity: one key per included file, grouped NaN-safely.
            inc = find(obj.Files.Include);
            Fk  = obj.fileKeyTable(inc,opts.PoolAcqModes);
            [gid,U,ukeys] = mabr.analysis.Session.groupRows(Fk,obj.KeyParams);
            nG = height(U);
            if subset
                target = ismember(ukeys,opts.Keys);
            else
                target = true(nG,1);
            end

            % Per condition: how it is processed, and the samples it covers.
            proc = strings(nG,1);  e = zeros(nG,2);  Lmin = NaN(nG,1);
            for g = 1:nG
                fr = inc(gid == g);
                compact = obj.Files.Layout(fr) == "compact";
                if opts.Processing == "windowed" || any(compact)
                    proc(g) = "windowed";
                    if any(compact)
                        Lmin(g) = min(obj.Files.SweepLength(fr(compact)));
                        e(g,:) = [max(w(1),0) min(w(2),Lmin(g)-1)];
                    else
                        e(g,:) = w;
                    end
                else
                    proc(g) = "continuous";
                    e(g,:) = w;
                end
            end

            % ---- Cut every file's sweeps.
            files = inc(target(gid));
            gOf = zeros(height(obj.Files),1);
            gOf(inc) = gid;
            parts = repmat(struct('g',0,'X',[],'row',[],'index',[],'onset',[],'pol',[], ...
                'art',[],'stime',[],'start',[],'nTrunc',0,'nOff',0,'nBad',0),numel(files),1);
            unread = strings(0,1);
            tooShort = strings(0,1);
            nonFinite = strings(0,1);
            % How far a sample reaches through the filter, either way (the
            % zero-phase chain runs each section forward and back).
            reach = mabr.analysis.Session.filterReach(f);
            honor = opts.HonorAcquisitionArtifacts;
            p = mabr.analysis.Progress(numel(files),sprintf('Segmenting %d files',numel(files)), ...
                obj.Verbose,obj.ProgressFcn);
            for j = 1:numel(files)
                row = files(j);
                g   = gOf(row);
                parts(j).g = g;
                windowed = proc(g) == "windowed";
                nRows = nT;
                if windowed, nRows = max(0,e(g,2) - e(g,1) + 1); end
                parts(j).X = zeros(nRows,0);
                [trace,sw,why] = obj.traceFor(row);
                if isempty(trace) || isempty(sw) || isempty(sw.Onset)
                    if why ~= "", unread(end+1,1) = obj.Files.FileId(row) + " (" + why + ")"; end %#ok<AGROW>
                    p.step();
                    continue
                end
                scale = obj.unitScale(row);
                on    = sw.Onset(:).';
                valid = reshape(logical(sw.Valid),1,[]);
                % A non-finite sample (NaN, Inf) would make the filter throw
                % and cost the whole session; instead it costs the sweeps it
                % reaches. It is zeroed for the filter, and every sweep whose
                % window, widened by the filter's reach, holds one is left out
                % (named in a warning, counted in the condition's flags).
                bad = [];
                if ~windowed
                    x = double(trace(:));
                    if scale ~= 1, x = x*scale; end
                    bad = ~isfinite(x);
                    if any(bad), x(bad) = 0; else, bad = []; end
                    filtered = f.fits(numel(x));
                    if filtered
                        x = f.apply(x);
                    else
                        tooShort(end+1,1) = obj.Files.FileId(row); %#ok<AGROW>
                    end
                    idx = on + winIdx;                         % [nT x nSweeps]
                    ok  = all(idx >= 1 & idx <= numel(x),1) & valid;
                    if ~isempty(bad)
                        m = reach*filtered;
                        hit = mabr.analysis.Session.touches(bad,on + w(1) - m,on + w(2) + m);
                        parts(j).nBad = sum(ok & hit);
                        ok = ok & ~hit;
                    end
                    X   = reshape(x(idx(:,ok)),nT,[]);
                    if isfinite(opts.Detrend) && ~isempty(X)
                        X = detrend(X,opts.Detrend);
                    end
                else
                    % RAW samples only: the windowed operator filters each
                    % window on its own once the condition is assembled.
                    x = double(trace(:));
                    if scale ~= 1, x = x*scale; end
                    off = (e(g,1):e(g,2)).';
                    if isempty(off)
                        ok = valid;
                        X  = zeros(0,sum(ok));
                    else
                        idx = on + off;
                        ok  = all(idx >= 1 & idx <= numel(x),1) & valid;
                        % Each window is filtered alone: a window holding a
                        % non-finite sample is left out, no other.
                        bad = ~isfinite(x);
                        if any(bad)
                            hit = mabr.analysis.Session.touches(bad,on + off(1),on + off(end));
                            parts(j).nBad = sum(ok & hit);
                            ok = ok & ~hit;
                        else
                            bad = [];
                        end
                        X   = reshape(x(idx(:,ok)),numel(off),[]);
                    end
                end
                if ~isempty(bad)
                    nonFinite(end+1,1) = sprintf('%s (%d sample(s), %d sweep(s))', ...
                        obj.Files.FileId(row),nnz(bad),parts(j).nBad); %#ok<AGROW>
                end
                n = sum(ok);
                isCompact = obj.Files.Layout(row) == "compact";
                parts(j).X      = X;
                parts(j).row    = repmat(row,1,n);
                parts(j).index  = reshape(sw.Index(ok),1,[]);
                parts(j).onset  = on(ok);
                parts(j).pol    = reshape(sw.Polarity(ok),1,[]);
                parts(j).art    = reshape(logical(sw.IsArtifact(ok)),1,[]);
                if isCompact
                    parts(j).stime = NaN(1,n);          % a compact file records no time
                else
                    parts(j).stime = on(ok)/Fs;
                end
                t0 = obj.Files.timestamp(row);
                if isnat(t0), s0 = Inf; else, s0 = datenum(t0); end %#ok<DATNM>
                parts(j).start  = repmat(s0,1,n);
                parts(j).nTrunc = sum(~valid);
                parts(j).nOff   = sum(~ok & valid);
                p.step();
            end
            p.close();

            % ---- Assemble each condition.
            tg = find(target);
            nN = numel(tg);
            [Sw,Rj,Rr,Pl,Sf,Si,So,St,Ex] = deal(cell(nN,1));
            [nSw,nRej,nFil,nCln,nPs,nNg] = deal(zeros(nN,1));
            Proc = strings(nN,1);  Ext = NaN(nN,2);
            Un = strings(nN,1);  LU = strings(nN,1);  Fl = strings(nN,1);
            pg = [parts.g];
            K = opts.MaxSweepsPerCondition;
            overrideOn = obj.overrideActive();
            skippedWin = 0;  nTruncAll = 0;  nOffAll = 0;
            for q = 1:nN
                g = tg(q);
                P = parts(pg == g);
                if isempty(P)
                    nRows = nT;
                    if proc(g) == "windowed", nRows = max(0,e(g,2) - e(g,1) + 1); end
                    X = zeros(nRows,0);
                    [row,idx,on,pol,art,stime,start] = deal(zeros(1,0));
                else
                    X = [P.X];
                    row = [P.row];  idx = [P.index];  on = [P.onset];  pol = [P.pol];
                    art = [P.art];  stime = [P.stime];  start = [P.start];
                end
                [~,o] = sortrows([start(:) row(:) on(:)]);
                o = o(:).';
                X = X(:,o);  row = row(o);  idx = idx(o);  pol = pol(o);
                art = logical(art(o));  stime = stime(o);
                n = numel(row);
                flags = strings(1,0);

                if proc(g) == "windowed"
                    full = NaN(nT,n);
                    rowsE = (e(g,1):e(g,2)) - w(1) + 1;
                    if isempty(rowsE)
                        flags(end+1) = sprintf('the window [%g %g] ms is outside what the compact files hold (0-%.1f ms)', ...
                            win,1000*(Lmin(g)-1)/Fs); %#ok<AGROW>
                    else
                        if n > 0
                            [Y,winfo] = f.applyWindowed(X,Order=opts.WindowedOrder,PadMode=opts.PadMode);
                            if winfo.Skipped
                                skippedWin = skippedWin + 1;
                                flags(end+1) = "windows too short to filter (detrended only)"; %#ok<AGROW>
                            end
                            full(rowsE,:) = Y;
                        end
                        Ext(q,:) = [time(rowsE(1)) time(rowsE(end))];
                    end
                    X = full;
                else
                    Ext(q,:) = [time(1) time(end)];
                end

                rej = honor & art;
                reason = uint8(rej);                 % 1 = the rig
                [rej,reason] = obj.applyManual(rej,reason,row,idx);
                ex = mabr.analysis.Session.excessOf(rej,pol,K,opts.EqualizeMode,opts.Seed,ukeys(g));

                nTr = sum([P.nTrunc]);  nOf = sum([P.nOff]);
                nTruncAll = nTruncAll + nTr;  nOffAll = nOffAll + nOf;
                if nTr > 0, flags(end+1) = sprintf('%d truncated sweep(s) dropped',nTr); end %#ok<AGROW>
                if nOf > 0, flags(end+1) = sprintf('%d sweep(s) ran off their file',nOf); end %#ok<AGROW>
                nBd = sum([P.nBad]);
                if nBd > 0
                    flags(end+1) = sprintf('%d sweep(s) reaching non-finite samples dropped',nBd); %#ok<AGROW>
                end
                if n == 0, flags(end+1) = "no usable sweeps"; end %#ok<AGROW>

                fr = inc(gid == g);
                [Un(q),LU(q)] = mabr.analysis.Session.unitsOf(obj.Files.Units(fr),obj.Files.LevelUnit(fr));
                if overrideOn, Un(q) = "V"; end
                if Un(q) == "mixed", flags(end+1) = "files disagree about units"; end %#ok<AGROW>
                if LU(q) == "mixed", flags(end+1) = "files disagree about the level reference"; end %#ok<AGROW>

                Sw{q} = X;  Rj{q} = rej;  Rr{q} = reason;  Pl{q} = double(pol);
                Sf{q} = double(row);  Si{q} = double(idx);  So{q} = 1:n;
                St{q} = double(stime);  Ex{q} = ex;
                use = ~rej & ~ex;
                nSw(q)  = n;
                nRej(q) = sum(rej);
                nFil(q) = numel(unique(row));
                nCln(q) = sum(use);
                nPs(q)  = sum(use & pol > 0);
                nNg(q)  = sum(use & pol < 0);
                Proc(q) = proc(g);
                Fl(q)   = strjoin(flags,"; ");
            end

            Cn = [table(ukeys(tg),'VariableNames',{'Key'}) U(tg,:)];
            Cn.Sweeps = Sw;  Cn.Rejected = Rj;  Cn.RejectReason = Rr;  Cn.Polarity = Pl;
            Cn.SweepFile = Sf;  Cn.SweepIndex = Si;  Cn.SweepOrder = So;  Cn.SweepTime = St;
            Cn.Excess = Ex;
            Cn.nSweeps = nSw;  Cn.nRejected = nRej;  Cn.nFiles = nFil;  Cn.nClean = nCln;
            Cn.nPos = nPs;  Cn.nNeg = nNg;
            Cn.Processing = Proc;  Cn.Extent = Ext;
            Cn.Units = Un;  Cn.LevelUnit = LU;  Cn.Flags = Fl;

            if subset
                old  = obj.Conditions;
                keep = ~ismember(old.Key,opts.Keys);
                Cn   = mabr.analysis.Session.alignColumns(Cn,old);
                C    = [old(keep,:); Cn];
                C    = C(mabr.analysis.Session.sortOrder(C,obj.KeyParams),:);
            else
                C = Cn;
            end

            % ---- Messages.
            if ~isempty(unread)
                obj.warn('%d file(s) could not be read for segmenting: %s.',numel(unread), ...
                    strjoin(reshape(unread(1:min(end,3)),1,[]),'; '));
            end
            if ~isempty(tooShort)
                obj.warn('%d file(s) too short for the filter were left unfiltered: %s.',numel(tooShort), ...
                    strjoin(reshape(tooShort(1:min(end,3)),1,[]),'; '));
            end
            if ~isempty(nonFinite)
                obj.warn(['%d file(s) hold non-finite samples (NaN or Inf); the sweeps they reach ' ...
                    'were left out: %s.'],numel(nonFinite),strjoin(reshape(nonFinite(1:min(end,3)),1,[]),'; '));
            end
            if nTruncAll > 0
                obj.note('%d truncated sweep(s) dropped (a compact window the run stopped inside).',nTruncAll);
            end
            if nOffAll > 0
                obj.note('%d sweep(s) dropped: their window runs off the end of the file.',nOffAll);
            end
            if skippedWin > 0
                obj.warn('%d condition(s) have windows too short to filter; they are only detrended.',skippedWin);
            end
            empty = Cn.nSweeps == 0;
            if any(empty)
                obj.warn('%d of %d conditions have no usable sweeps.',sum(empty),height(Cn));
            end
            obj.note('%s',obj.processingSummary(Cn,f,opts,win,Fs,subset,height(C)));

            % ---- Commit.
            so = struct('Window',win,'Filter',mabr.analysis.Session.filterToStruct(f), ...
                'HonorAcquisitionArtifacts',honor,'Detrend',opts.Detrend, ...
                'Processing',opts.Processing,'WindowedOrder',opts.WindowedOrder, ...
                'PadMode',opts.PadMode,'PoolAcqModes',opts.PoolAcqModes, ...
                'MaxSweepsPerCondition',K,'EqualizeMode',opts.EqualizeMode,'Seed',opts.Seed);
            [units,levelUnit] = obj.sessionUnits(obj.Files);
            obj.Window     = win;
            obj.Time       = time;
            obj.Filter     = f;
            obj.Conditions = C;
            obj.HasSweeps  = true;
            obj.Units      = units;
            obj.LevelUnit  = levelUnit;
            obj.StepOptions.segment = so;
            if ~subset, obj.clearStepStates("segment"); end
            obj.commitMessages("segment",~subset);
            T = obj.Conditions;
        end

        % =================================================================
        %  3. Reject -- flag artifact sweeps
        % =================================================================
        function T = reject(obj,opts)
            % Flag artifact sweeps in every condition.
            %
            % Judges each condition on its own, which is the point: an
            % electrode drifts over a session, and a sweep that is an outlier
            % among its neighbours is the one worth doubting.
            %
            % The feature (Artifacts.feature) is computed over Window
            % intersected with the rows the condition holds, on ALL its sweeps.
            % A RELATIVE Method ("median","mean","quartiles") flags the sweeps
            % isoutlier puts above its upper bound (ThresholdFactor = Factor);
            % UpperOnly=false, or the signed feature negPeak, flags below the
            % lower bound too -- a sweep is an artifact for being too BIG, and a
            % two-sided criterion always finds "outliers" in clean data. Ceiling
            % adds an absolute limit (|feature| > Ceiling, volts) and Method
            % "none" leaves only that.
            %
            % The legacy path -- MethodArgs given, or Method "grubbs", "gesd" or
            % "threshold" -- is mabr.analysis.Artifacts.detect, two-sided, exactly
            % as before. "movmedian"/"movmean" are refused: isoutlier needs
            % their window as a positional argument, which this call cannot pass.
            %
            % Keep=true adds new flags to the existing ones (reason 2);
            % Keep=false starts again from the rig's flags (when segment honoured
            % them). Manual decisions are applied last, both ways.
            %
            %   opts.Feature     mabr.analysis.Artifacts.Features name (default "absPeak")
            %   opts.Method      "median" (default), "mean", "quartiles", "none";
            %                    legacy "grubbs", "gesd", "threshold"
            %   opts.Factor      isoutlier ThresholdFactor (default 3)
            %   opts.UpperOnly   flag only the high side (default true)
            %   opts.Ceiling     absolute limit on |feature|, V (default Inf = none)
            %   opts.Window      ms window the feature is computed over (default ResponseWindow)
            %   opts.Keep        keep flags already set (default true)
            %   opts.Keys        judge only these condition keys (default all)
            %   opts.MethodArgs  legacy: extra isoutlier args, as a struct
            %   opts.Threshold   legacy: threshold for Method="threshold" (V)
            %   opts.Plot        show Artifacts.plotDiagnostic per condition (default false)
            %   T  (returned) obj.Conditions, also stored on the object
            arguments
                obj
                opts.Feature (1,1) string = "absPeak"
                opts.Method (1,1) string = "median"
                opts.Factor (1,1) double {mustBePositive} = 3
                opts.UpperOnly (1,1) logical = true
                opts.Ceiling (1,1) double {mustBePositive} = Inf
                opts.Window double = []      % ms; default ResponseWindow
                opts.Keep (1,1) logical = true     % keep flags already set
                opts.Keys (:,1) string = strings(0,1)
                opts.MethodArgs struct = struct()
                opts.Threshold (1,1) double {mustBePositive} = Inf
                opts.Plot (1,1) logical = false
            end
            if ismember(opts.Method,["movmedian","movmean"])
                error('mabr:analysis:Session:badRejectMethod', ...
                    ['Method "%s" cannot be used: isoutlier needs its moving window as a ' ...
                     'positional argument, which Session.reject cannot pass. Use "median", ' ...
                     '"mean" or "quartiles".'],opts.Method);
            end
            if ~ismember(opts.Method,["median","mean","quartiles","none","grubbs","gesd","threshold"])
                error('mabr:analysis:Session:badRejectMethod', ...
                    'Unknown rejection method "%s".',opts.Method);
            end
            if ~ismember(opts.Feature,mabr.analysis.Artifacts.Features)
                error('mabr:analysis:Session:badRejectFeature', ...
                    'Unknown rejection feature "%s". Choose from: %s.',opts.Feature, ...
                    strjoin(mabr.analysis.Artifacts.Features,', '));
            end
            guard = obj.beginStep("reject"); %#ok<NASGU>
            obj.requireConditions();
            obj.requireSweeps();
            legacy = ~isempty(fieldnames(opts.MethodArgs)) || ...
                ismember(opts.Method,["grubbs","gesd","threshold"]);

            win = opts.Window;
            if isempty(win), win = obj.ResponseWindow; end
            wmask = mabr.analysis.Artifacts.windowMask(obj.Time,win);
            honor = true;
            if isfield(obj.StepOptions,'segment') && isfield(obj.StepOptions.segment,'HonorAcquisitionArtifacts')
                honor = obj.StepOptions.segment.HonorAcquisitionArtifacts;
            end
            [K,mode,seed] = obj.capSettings();

            C = obj.Conditions;
            targets = obj.targetRows(opts.Keys);
            p = mabr.analysis.Progress(numel(targets),'Rejecting artifacts',obj.Verbose,obj.ProgressFcn);
            nNew = 0;  noRows = 0;
            for r = targets(:).'
                X = C.Sweeps{r};
                n = size(X,2);
                if n == 0, p.step(); continue; end
                rows = wmask & mabr.analysis.Session.extentMask(obj.Time,C.Extent(r,:));
                info = struct('feature',[],'lower',[],'upper',[],'method',opts.Method, ...
                    'name',opts.Feature,'count',0);
                if ~any(rows)
                    flagged = false(1,n);
                    noRows = noRows + 1;
                elseif legacy
                    [flagged,info] = mabr.analysis.Artifacts.detect(X, Rows=rows, ...
                        Feature=opts.Feature, Method=opts.Method, ...
                        Threshold=opts.Threshold, MethodArgs=opts.MethodArgs);
                else
                    [flagged,info] = mabr.analysis.Session.relativeFlags(X,rows,opts);
                end
                flagged = reshape(logical(flagged),1,[]);

                old = C.Rejected{r};
                reason = C.RejectReason{r};
                if opts.Keep
                    add = flagged & ~old;
                    rej = old | flagged;
                    reason(add) = 2;
                else
                    base = false(1,n);
                    if honor, base = obj.rigFlags(C,r); end
                    rej = base | flagged;
                    reason = zeros(1,n,'uint8');
                    reason(base) = 1;
                    reason(flagged & ~base) = 2;
                end
                [rej,reason] = obj.applyManual(rej,reason,C.SweepFile{r},C.SweepIndex{r});
                nNew = nNew + sum(rej & ~old);
                C = mabr.analysis.Session.setSweepFlags(C,r,rej,reason, ...
                    mabr.analysis.Session.excessOf(rej,C.Polarity{r},K,mode,seed,C.Key(r)));

                if opts.Plot
                    mabr.analysis.Artifacts.plotDiagnostic(X,rej,info,Time=obj.Time);
                end
                p.step();
            end
            p.close();

            if noRows > 0
                obj.warn('%d condition(s) hold no samples inside the rejection window [%g %g] ms.', ...
                    noRows,win);
            end
            tot = sum(C.nSweeps(targets));
            obj.note('%d of %d sweeps rejected (%.1f%%); %d newly flagged (%s, %s).', ...
                sum(C.nRejected(targets)),tot,100*sum(C.nRejected(targets))/max(1,tot),nNew, ...
                opts.Feature,opts.Method);

            ro = struct('Feature',opts.Feature,'Method',opts.Method,'Factor',opts.Factor, ...
                'UpperOnly',opts.UpperOnly,'Ceiling',opts.Ceiling,'Window',win,'Keep',opts.Keep, ...
                'MethodArgs',opts.MethodArgs,'Threshold',opts.Threshold,'Legacy',legacy);
            obj.Conditions = C;
            obj.StepOptions.reject = ro;
            if isempty(opts.Keys), obj.clearStepStates("reject"); end
            obj.commitMessages("reject",isempty(opts.Keys));
            T = obj.Conditions;
        end

        function clearRejected(obj)
            % Drop every artifact flag, including the acquisition rig's.
            %
            % Manual decisions (ManualRejections) are the analyst's, not
            % artifact flags, and are applied again. (No inputs beyond obj, no
            % return value; mutates obj.Conditions.)
            obj.requireConditions();
            C = obj.Conditions;
            [K,mode,seed] = obj.capSettings();
            for r = 1:height(C)
                n = numel(C.Rejected{r});
                rej = false(1,n);
                reason = zeros(1,n,'uint8');
                [rej,reason] = obj.applyManual(rej,reason,C.SweepFile{r},C.SweepIndex{r});
                C = mabr.analysis.Session.setSweepFlags(C,r,rej,reason, ...
                    mabr.analysis.Session.excessOf(rej,C.Polarity{r},K,mode,seed,C.Key(r)));
            end
            obj.Conditions = C;
            obj.clearStepStates("reject");
        end

        % =================================================================
        %  4. Detect -- is there a response in each condition?
        % =================================================================
        function T = detect(obj,opts)
            % Permutation-test every condition and store p, isSig, strength.
            %
            % Each condition is tested on its CLEAN sweeps (not rejected, not
            % excess) over Window intersected with the rows it holds. A
            % condition whose clean sweeps do not vary within their file x
            % polarity groups is not tested (Threshold.detect): p NaN, flagged
            % "zero variance", and a warning names it; one whose sweeps are
            % near-noiseless has its TFCE step raised, flagged likewise. With
            % SeedMode "shared" every condition uses Seed (the behaviour of
            % every earlier MABR, and the direct default); with "per-condition"
            % each draws from Stats.conditionSeed(Seed,Key) -- so two conditions
            % with the same sweep count no longer get the same sign flips, and
            % re-testing a subset (Keys) is bit-identical to re-testing all.
            %
            %   opts.Method           "clusterMass", "tmax", or "tfce" (default "tfce")
            %   opts.NumPermutations  permutations per condition (default 1000)
            %   opts.Alpha            significance level (default 0.05)
            %   opts.MinClusterSize   minimum run length counted as a cluster (default 1)
            %   opts.Window           ms window tested (default obj.ResponseWindow)
            %   opts.Seed             permutation seed (default 1)
            %   opts.SeedMode         "shared" (default) or "per-condition"
            %   opts.Keys             test only these condition keys (default all)
            %   opts.UseParallel      accepted for old scripts and ignored: the
            %                         conditions are always tested one after
            %                         another (see below)
            %   T  (returned) obj.Conditions, with p/isSig/strength/Detection/
            %      DetectedAuto/Detected, also stored on the object. Detection{k}
            %      is a struct: p, isSig, strength, nSweeps, method, tThresh, t,
            %      pSample, sigMask, clusters (sample indices within the tested
            %      rows, which run from RowsMs(1) to RowsMs(2) of Time), RowsMs,
            %      NullP95, Seed and null (the permutation null; dropped on save)
            arguments
                obj
                opts.Method (1,1) string {mustBeMember(opts.Method,["clusterMass","tmax","tfce"])} = "tfce"
                opts.NumPermutations (1,1) double {mustBeInteger,mustBePositive} = 1000
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1)} = 0.05
                opts.MinClusterSize (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.Window double = []
                opts.Seed = 1
                opts.SeedMode (1,1) string {mustBeMember(opts.SeedMode,["shared","per-condition"])} = "shared"
                opts.Keys (:,1) string = strings(0,1)
                opts.UseParallel (1,1) logical = false
            end
            if opts.SeedMode == "per-condition" && ~(isnumeric(opts.Seed) && isscalar(opts.Seed) ...
                    && isfinite(opts.Seed) && opts.Seed == round(opts.Seed) && opts.Seed >= 0)
                error('mabr:analysis:Session:badSeed', ...
                    'SeedMode "per-condition" needs a non-negative integer Seed.');
            end
            guard = obj.beginStep("detect"); %#ok<NASGU>
            obj.requireConditions();
            obj.requireSweeps();

            win = opts.Window;
            if isempty(win), win = obj.ResponseWindow; end
            wmask = mabr.analysis.Artifacts.windowMask(obj.Time,win);

            C  = obj.Conditions;
            targets = obj.targetRows(opts.Keys);
            nT = numel(targets);
            args = cell(nT,1);
            X    = cell(nT,1);
            for k = 1:nT
                r = targets(k);
                rows = wmask & mabr.analysis.Session.extentMask(obj.Time,C.Extent(r,:));
                if any(rows)
                    rowsMs = [obj.Time(find(rows,1,'first')) obj.Time(find(rows,1,'last'))];
                else
                    rowsMs = [NaN NaN];
                end
                if opts.SeedMode == "per-condition"
                    seed = mabr.analysis.Stats.conditionSeed(opts.Seed,C.Key(r));
                else
                    seed = opts.Seed;
                end
                [X{k},pol,str] = obj.cleanSweeps(r);
                args{k} = {rows,opts.Method,opts.NumPermutations,opts.Alpha, ...
                    opts.MinClusterSize,seed,rowsMs,pol,str};
            end

            % Serial, whatever UseParallel says. A parfor here was the one
            % line that made MATLAB's dependency analysis list the Parallel
            % Computing Toolbox for the offline analysis, which must need
            % none; it bought little (each test is vectorized across its
            % permutations already), and a condition's result never depended
            % on it -- every seed is explicit -- so nothing changes but that.
            det = cell(nT,1);
            why = cell(nT,1);
            p = mabr.analysis.Progress(nT,'Permutation tests',obj.Verbose,obj.ProgressFcn);
            for k = 1:nT
                [det{k},why{k}] = mabr.analysis.Session.detectOne(X{k},args{k});
                p.step();
            end
            p.close();

            h = height(C);
            if ~ismember('p',C.Properties.VariableNames)
                C.p            = NaN(h,1);
                C.isSig        = false(h,1);
                C.strength     = NaN(h,1);
                C.Detection    = cell(h,1);
            end
            if ~ismember('DetectedAuto',C.Properties.VariableNames)
                C.DetectedAuto = false(h,1);
                C.Detected     = false(h,1);
            end
            for k = 1:nT
                r = targets(k);
                C.p(r)         = det{k}.p;
                C.isSig(r)     = det{k}.isSig;
                C.strength(r)  = det{k}.strength;
                C.Detection{r} = det{k};
            end
            % The test's own flags, replaced on every re-test: a condition
            % with no noise was not tested, and one with near-noiseless
            % sweeps had its TFCE integrated in coarser steps.
            zv = false(nT,1);  raised = false(nT,1);
            for k = 1:nT
                r = targets(k);
                old = strtrim(split(C.Flags(r),";"));
                old = old(old ~= "" & ~mabr.analysis.Session.isDetectFlag(old));
                w = reshape(string(why{k}),1,[]);
                new = [reshape(old,1,[]) w];
                C.Flags(r) = strjoin(new(new ~= ""),"; ");
                zv(k)     = any(w == mabr.analysis.SingleTrial.FlagZeroVariance);
                raised(k) = any(startsWith(w,"TFCE step raised"));
            end
            % The automatic verdict of the conditions tested; a subset leaves
            % the others' as they are (a graded threshold method may have made
            % them -- estimateThresholds of their series rewrites them anyway).
            if isempty(opts.Keys)
                C.DetectedAuto = C.isSig;
            else
                C.DetectedAuto(targets) = C.isSig(targets);
            end
            C.Detected     = obj.applyDetectionOverrides(C);

            if isempty(opts.Keys)
                obj.note('%d of %d conditions significant at alpha = %g (%s, %d permutations, %s seeds).', ...
                    sum(C.isSig),h,opts.Alpha,opts.Method,opts.NumPermutations,opts.SeedMode);
            else
                obj.note('%d of %d re-tested conditions significant at alpha = %g (%s).', ...
                    sum(C.isSig(targets)),nT,opts.Alpha,opts.Method);
            end
            short = sum(cellfun(@(x) size(x,2),X) < 2);
            if short > 0
                obj.warn('%d condition(s) have fewer than 2 clean sweeps and were not tested.',short);
            end
            if any(zv)
                obj.warn(['%d condition(s) have zero variance -- their clean sweeps do not vary ' ...
                    '(a dead channel, or noiseless data) -- and were not tested (p NaN): %s.'], ...
                    sum(zv),obj.conditionList(C.Key(targets(zv))));
            end
            if any(raised)
                obj.warn(['%d condition(s) have near-noiseless sweeps, so their TFCE step was ' ...
                    'raised to keep the test finite: %s.'],sum(raised), ...
                    obj.conditionList(C.Key(targets(raised))));
            end

            dopt = struct('Method',opts.Method,'NumPermutations',opts.NumPermutations, ...
                'Alpha',opts.Alpha,'MinClusterSize',opts.MinClusterSize,'Window',win, ...
                'Seed',opts.Seed,'SeedMode',opts.SeedMode);
            obj.Conditions = C;
            obj.StepOptions.detect = dopt;
            if isempty(opts.Keys), obj.clearStepStates("detect"); end
            obj.commitMessages("detect",isempty(opts.Keys));
            T = obj.Conditions;
        end

        % =================================================================
        %  5. Measure -- single-trial statistics per condition
        % =================================================================
        function T = measure(obj,opts)
            % Single-trial measures of every condition (mabr.analysis.SingleTrial).
            %
            % Per condition, from its CLEAN sweeps: the residual noise RN and
            % its ± reference RNPM, the response and baseline RMS, the power
            % test (F, PowerP, PowerF95, SNR, SNRCorr), Fsp, the split-half
            % correlation, and per sweep the QC Features. Each condition
            % draws from its own stream, Stats.conditionStream(Seed,Key), so
            % re-measuring a subset is bit-identical to re-measuring all. A
            % condition with no noise (SingleTrial.zeroVariance) has RN 0 and
            % every ratio over it NaN -- F, SNR, the power test, Fsp, the
            % split-half r -- flagged "zero variance" with a warning naming it.
            %
            % Two quantities are made per SERIES (every condition sharing all
            % but the level), because they compare its conditions:
            %   - the split-half K (sweeps per polarity per half) is the
            %     smallest any condition of the series can give --
            %     floor(min(nPos,nNeg)/2), or floor(N/2) without both
            %     polarities -- so every level's r is made from halves of one
            %     size and is comparable along the series (a condition whose
            %     own K is under SplitHalfMinPerPolarity has no r anyway and
            %     does not count);
            %   - XCorrUp: each condition's mean against the next HIGHER level
            %     of its series (SingleTrial.xcorrUp, lags 0..MaxLag), NaN at
            %     the top level; DTWUp the same pair after time warping
            %     (SingleTrial.dtwUp: a lag of 0..MaxLag that changes along
            %     the response), with its mean lag DTWLag and the spread of
            %     the lag DTWLagRange (ms).
            % A Keys subset is therefore widened to whole series.
            %
            % The baseline is measured only where it can be: when the shortest
            % onset-to-onset interval of a condition's files (Files.MinISI) is
            % under |BaselineWindow(1)| + ResponseWindow(2), the previous
            % presentation's response runs into the baseline, so BaselineRMS
            % is NaN and the condition is flagged "baseline overlaps the
            % previous response".
            %
            %   opts.ResponseWindow           ms (default obj.ResponseWindow)
            %   opts.BaselineWindow           ms (default [-10 0])
            %   opts.SplitHalfMode            "median" (default) | "mean"
            %   opts.SplitHalfResamples       random partitions (default 500)
            %   opts.SplitHalfWindow          ms ([] = the response window)
            %   opts.SplitHalfMinPerPolarity  smallest K (default 25)
            %   opts.NumPermutations          power-test permutations (default 1000)
            %   opts.Seed                     base seed (default 1)
            %   opts.MaxLag                   ms, XCorrUp's and DTWUp's largest
            %                                 lag (default 0.3)
            %   opts.LevelDirection           which way is louder for XCorrUp:
            %                                 "" (default: the threshold step's
            %                                 LevelDirection, else "auto") |
            %                                 "auto" | "ascending" | "descending".
            %                                 analyze passes the settings', since
            %                                 it measures before thresholds run.
            %   opts.Keys                     condition keys (default all)
            %   T  (returned) obj.Conditions with RN, RNPM, ResponseRMS,
            %      BaselineRMS, F, PowerP, PowerF95, SNR, SNRCorr, Fsp, FspDF1,
            %      FspDF2, FspP, SplitR, SplitRSD, SplitRP025, SplitRP975, SplitN,
            %      XCorrUp, XCorrLag, XCorrUp0, DTWUp, DTWLag, DTWLagRange and
            %      Features (cell of tables)
            arguments
                obj
                opts.ResponseWindow double = []
                opts.BaselineWindow (1,2) double = [-10 0]
                opts.SplitHalfMode (1,1) string {mustBeMember(opts.SplitHalfMode,["median","mean"])} = "median"
                opts.SplitHalfResamples (1,1) double {mustBeInteger,mustBePositive} = 500
                opts.SplitHalfWindow double = []
                opts.SplitHalfMinPerPolarity (1,1) double {mustBeInteger,mustBeNonnegative} = 25
                opts.NumPermutations (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
                opts.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 1
                opts.MaxLag (1,1) double {mustBeNonnegative} = 0.3
                opts.LevelDirection (1,1) string {mustBeMember(opts.LevelDirection,["","auto","ascending","descending"])} = ""
                opts.Keys (:,1) string = strings(0,1)
            end
            guard = obj.beginStep("measure"); %#ok<NASGU>
            obj.requireConditions();
            obj.requireSweeps();
            rw = opts.ResponseWindow;
            if isempty(rw), rw = obj.ResponseWindow; end
            shw = opts.SplitHalfWindow;
            if isempty(shw), shw = rw; end
            bw = opts.BaselineWindow;

            C  = obj.Conditions;
            t  = obj.Time;
            nT = numel(t);
            h  = height(C);
            dt = median(diff(t));
            sk = obj.conditionSeriesKeys();
            if isempty(opts.Keys)
                targets = (1:h).';
            else
                touched = unique(sk(obj.rowOf(unique(opts.Keys,'stable'))));
                targets = find(ismember(sk,touched));
            end

            % The split-half K of each series: the smallest its conditions give.
            kc = zeros(h,1);
            for r = 1:h
                if C.nPos(r) > 0 && C.nNeg(r) > 0
                    kc(r) = floor(min(C.nPos(r),C.nNeg(r))/2);
                else
                    kc(r) = floor(C.nClean(r)/2);
                end
            end
            % A condition too small for a split-half r of its own (K under
            % SplitHalfMinPerPolarity: nearly every sweep rejected, a short run)
            % gets NaN whatever K it is given, so it does not set the series'
            % K -- else one such level would take r away from every level.
            [us,~,gi] = unique(sk(targets));
            kSeries = zeros(numel(us),1);
            kMin = max(1,opts.SplitHalfMinPerPolarity);
            for g = 1:numel(us)
                kg = kc(targets(gi == g));
                if any(kg >= kMin), kg = kg(kg >= kMin); end
                kSeries(g) = min(kg);
            end

            names = mabr.analysis.Session.MeasureColumns;
            V = NaN(numel(targets),numel(names));
            feats = cell(numel(targets),1);
            flags = strings(numel(targets),1);
            means = cell(numel(targets),1);
            rwMask = mabr.analysis.Artifacts.windowMask(t,rw);
            bwMask = mabr.analysis.Artifacts.windowMask(t,bw);
            shMask = mabr.analysis.Artifacts.windowMask(t,shw);
            minISI = NaN(height(obj.Files),1);
            if ismember('MinISI',obj.Files.Properties.VariableNames), minISI = obj.Files.MinISI; end
            nOverlap = 0;
            p = mabr.analysis.Progress(numel(targets),'Single-trial measures',obj.Verbose,obj.ProgressFcn);
            for q = 1:numel(targets)
                r = targets(q);
                ext = mabr.analysis.Session.extentMask(t,C.Extent(r,:));
                [X,pol,str] = obj.cleanSweeps(r);
                if size(X,1) ~= nT, X = zeros(nT,0); pol = zeros(1,0); str = zeros(1,0); end
                rows = rwMask & ext;
                br   = bwMask & ext;
                isi  = minISI(unique(C.SweepFile{r}));
                fl   = strings(1,0);
                if any(isfinite(isi)) && min(isi) < abs(bw(1)) + rw(2)
                    br(:) = false;
                    fl(end+1) = mabr.analysis.Session.FlagBaselineOverlap; %#ok<AGROW>
                    nOverlap = nOverlap + 1;
                end
                S = mabr.analysis.SingleTrial.summary(X,t,pol,str,Rows=rows,BaselineRows=br, ...
                    SplitRows=shMask & ext,Stream=mabr.analysis.Stats.conditionStream(opts.Seed,C.Key(r)), ...
                    NumPermutations=opts.NumPermutations,SplitHalfMode=opts.SplitHalfMode, ...
                    SplitHalfResamples=opts.SplitHalfResamples,SplitHalfK=kSeries(gi(q)), ...
                    MinPerPolarity=opts.SplitHalfMinPerPolarity);
                for j = 1:numel(names)
                    if isfield(S,names(j)), V(q,j) = double(S.(names(j))); end
                end
                fl = [fl reshape(string(S.Flags),1,[])]; %#ok<AGROW>
                flags(q) = strjoin(unique(fl(fl ~= ""),'stable'),"; ");
                means{q} = S.Mean;
                Xall = C.Sweeps{r};
                if size(Xall,1) == nT && size(Xall,2) > 0
                    feats{q} = mabr.analysis.SingleTrial.features(Xall,rows,br);
                else
                    feats{q} = mabr.analysis.SingleTrial.features(zeros(nT,numel(C.Rejected{r})),rows,br);
                end
                p.step();
            end
            p.close();

            % XCorrUp and DTWUp: each condition against the next louder one of
            % its series.
            iU = find(names == "XCorrUp",1);  iL = find(names == "XCorrLag",1);  i0 = find(names == "XCorrUp0",1);
            iD = find(names == "DTWUp",1);  iDL = find(names == "DTWLag",1);  iDR = find(names == "DTWLagRange",1);
            lp = obj.levelParamOrEmpty();
            maxLag = round(opts.MaxLag/dt);
            if lp ~= "" && ismember(lp,string(C.Properties.VariableNames))
                % Louder is higher, on an attenuation axis lower (loudnessSign).
                lev = obj.loudnessSign(lp,opts.LevelDirection)*double(C.(lp)(targets));
                for g = 1:numel(us)
                    m = find(gi == g);
                    for a = m(:).'
                        if ~isfinite(lev(a)), continue; end
                        louder = m(isfinite(lev(m)) & lev(m) > lev(a));
                        if isempty(louder), continue; end
                        [~,k] = min(lev(louder));
                        b = louder(k);
                        rr = rwMask & mabr.analysis.Session.extentMask(t,C.Extent(targets(a),:)) ...
                            & mabr.analysis.Session.extentMask(t,C.Extent(targets(b),:));
                        if ~any(rr) || isempty(means{a}) || isempty(means{b}), continue; end
                        [V(a,iU),V(a,iL),V(a,i0)] = mabr.analysis.SingleTrial.xcorrUp( ...
                            means{a},means{b},rr,maxLag,dt);
                        [V(a,iD),V(a,iDL),V(a,iDR)] = mabr.analysis.SingleTrial.dtwUp( ...
                            means{a},means{b},rr,maxLag,dt);
                    end
                end
            end

            % ---- Into the table.
            for j = 1:numel(names)
                if ~ismember(names(j),string(C.Properties.VariableNames))
                    C.(names(j)) = NaN(h,1);
                end
                C.(names(j))(targets) = V(:,j);
            end
            if ~ismember('Features',C.Properties.VariableNames)
                C.Features = cell(h,1);
            end
            C.Features(targets) = feats;
            known = [mabr.analysis.Session.FlagBaselineOverlap mabr.analysis.SingleTrial.FlagUnbalanced ...
                mabr.analysis.SingleTrial.FlagZeroVariance];
            for q = 1:numel(targets)
                r = targets(q);
                old = strtrim(split(C.Flags(r),";"));
                old = old(old ~= "" & ~ismember(old,known));
                new = [reshape(old,1,[]) reshape(split(flags(q),"; "),1,[])];
                C.Flags(r) = strjoin(new(new ~= ""),"; ");
            end
            C = mabr.analysis.Session.canonicalConditions(C,obj.KeyParams);

            ok = isfinite(V(:,names == "F"));
            obj.note('Measured %d condition(s): median SNR %.1f dB, %d with a split-half r (K per series %s).', ...
                numel(targets),median(V(ok,names == "SNR")),sum(isfinite(V(:,names == "SplitR"))), ...
                mat2str(unique(kSeries).'));
            if nOverlap > 0
                obj.warn(['%d condition(s): the baseline window [%g %g] ms overlaps the previous ' ...
                    'presentation''s response (files'' shortest interval); their BaselineRMS is NaN.'], ...
                    nOverlap,bw);
            end
            zv = contains(flags,mabr.analysis.SingleTrial.FlagZeroVariance);
            if any(zv)
                obj.warn(['%d condition(s) have zero variance -- their clean sweeps do not vary ' ...
                    '(a dead channel, or noiseless data) -- so F, SNR, the power test, Fsp and the ' ...
                    'split-half r are NaN: %s.'],sum(zv),obj.conditionList(C.Key(targets(zv))));
            end
            mo = rmfield(opts,'Keys');
            mo.ResponseWindow = rw;
            obj.Conditions = C;
            obj.StepOptions.measure = mo;
            if isempty(opts.Keys), obj.clearStepStates("measure"); end
            obj.commitMessages("measure",isempty(opts.Keys));
            T = obj.Conditions;
        end

        % =================================================================
        %  6. Thresholds
        % =================================================================
        function T = estimateThresholds(obj,opts)
            % One threshold per level series, by a named method.
            %
            % A series is every condition sharing everything but the level:
            % GroupBy defaults to every non-level KeyParams column -- Stimulus,
            % AcqMode, frequency and whatever else the bank varies -- constants
            % included, so a tone and a click series, or a conventional and an
            % interleaved one, are never fitted together, and a series key
            % reads the same in every session. A GroupBy that is given is
            % used as given, PLUS Stimulus and AcqMode whenever it leaves them
            % out (AcqMode not when segment pooled the modes, PoolAcqModes):
            % GroupBy "Frequency" is a series per stimulus, acquisition mode
            % and frequency, never one fitting clicks, tones, conventional and
            % interleaved runs together (seriesGrouping; a note says what was
            % added). Each series goes to
            % mabr.analysis.SeriesThreshold.estimate with the per-level
            % statistics of its conditions (p, the measures, the clean sweep
            % counts, and a hand verdict from DetectionOverrides).
            %
            % METHOD. Method names one of SeriesThreshold.methods() --
            % "perm-glm", "perm-descending", "power-descending",
            % "fsp-descending", "presto", "xcorr", "xcorr-dtw" or "custom"
            % (whose metric, model and criterion are read from
            % MethodSettings). Left "" (the DIRECT, legacy call every script
            % before named methods made), the
            % method is custom with Metric "detection", Model = Type,
            % CriterionMode "probability" for glm and "fraction" otherwise,
            % Criterion as given, and FitTarget deciding what a fraction model
            % fits -- so the four calls verify_analysis Part G makes keep their
            % meaning. Every GLM is Firth-penalised with unit weights (one
            % yes/no verdict per level is one observation). Without detections
            % the legacy call runs detect() first, as it always did; a named
            % method refuses (mabr:analysis:Session:noDetection), and a method
            % on a measure refuses until measure() has run
            % (mabr:analysis:Session:noMeasures).
            %
            % CURATION SURVIVES (KeepCurated). A human decision -- Decision,
            % ManualValue, ManualKind, Note and who reviewed it, when, at what
            % value, under which method -- is carried from the previous table
            % by series KEY. A curated row whose key no longer exists (a
            % different grouping) moves to CurationArchive, and comes back
            % when its key does. An "accepted" fit that has since moved by
            % more than half a level step, or changed its censoring, loses its
            % acceptance and is flagged "fit changed since review (was X, now
            % Y)"; a decision taken under another method is flagged "reviewed
            % under <method>". Final* are then SeriesThreshold.finalValue of
            % each row: what the human decided, else what the method said.
            % Curated = Final and IsCurated = a decision other than accepted,
            % for the code written before Decision existed.
            %
            % No level parameter (a session that varies no level) gives an
            % empty Thresholds and a message, not an error.
            %
            %   opts.Method        a SeriesThreshold method Id ("" = the legacy custom path)
            %   opts.MethodSettings Settings or struct the custom method's
            %                      ThresholdMetric/Model/CriterionMode/Criterion
            %                      are read from ([] = Settings defaults)
            %   opts.LevelParam    level axis ("" = levelParam())
            %   opts.GroupBy       series parameters ([] = every non-level key column);
            %                      Stimulus and AcqMode are added when missing
            %                      (AcqMode unless the modes are pooled)
            %   opts.Type          legacy model: "glm" (default), "sigmoid", "isotonic", "minimum"
            %   opts.FitTarget     legacy: "auto" (default), "binary", "p", "strength"
            %   opts.Criterion     legacy: probability (glm) or fraction (default 0.5)
            %   opts.Extrapolate   allow a model threshold outside the levels (default true)
            %   opts.NearestLevel  snap a model threshold to the next level up (default false)
            %   opts.CIAlpha       two-sided interval level (default 0.05)
            %   opts.Seed          Monte Carlo interval seed (default 1)
            %   opts.Alpha         detection level of the p-metrics (default 0.05)
            %   opts.MinConsecutive  descending rule's run, and the legacy gate (default 1)
            %   opts.Convention    "midpoint" (default), "lowest_level", "crossing"
            %   opts.Interpolate   graded metrics: the criterion crossing (default true)
            %   opts.MinSweeps     clean sweeps a level needs (default 2)
            %   opts.MinPerPolarity  per polarity, alternating data (default 0)
            %   opts.LevelDirection "auto" (descending for an Attenuation axis),
            %                      "ascending" or "descending"
            %   opts.FlagWideCI, opts.FlagNonMonotoneTol, opts.CINumSamples
            %                      as SeriesThreshold.estimate (0.35, 0, 2000)
            %   opts.Bootstrap     sweep-bootstrap replicates of a graded
            %                      threshold's interval (default 0 = none)
            %   opts.KeepCurated   carry curation by key (default true)
            %   opts.SeriesKeys    re-estimate only these series (default all)
            %   T  (returned) obj.Thresholds: Key, the group columns, LevelParam,
            %      Method, Metric, Type, FitTarget, Criterion, CriterionUnit,
            %      Convention, Threshold, ThresholdRaw, Status, Censored, ThrLo,
            %      ThrHi, CILower, CIUpper, CIMethod, NumLevels, NumUsable,
            %      NumSig, LevelStep, MinLevel, MaxLevel, Converged, Message,
            %      Flags, Decision, ManualValue, ManualKind, Final,
            %      FinalCensored, FinalLo, FinalHi, Note, ReviewedBy,
            %      ReviewedAt, ReviewedValue, ReviewedMethod, Curated,
            %      IsCurated, Fit
            arguments
                obj
                opts.Method (1,1) string = ""
                opts.MethodSettings = []
                opts.LevelParam (1,1) string = ""
                opts.GroupBy (1,:) string = string.empty
                opts.Type (1,1) string {mustBeMember(opts.Type,["glm","sigmoid","isotonic","minimum"])} = "glm"
                opts.FitTarget (1,1) string {mustBeMember(opts.FitTarget,["auto","binary","p","strength"])} = "auto"
                opts.Criterion (1,1) double {mustBeInRange(opts.Criterion,0,1)} = 0.5
                opts.Extrapolate (1,1) logical = true
                opts.NearestLevel (1,1) logical = false
                opts.CIAlpha (1,1) double {mustBeInRange(opts.CIAlpha,0,1,"exclusive")} = 0.05
                opts.Seed = 1
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1,"exclusive")} = 0.05
                opts.MinConsecutive (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.Convention (1,1) string {mustBeMember(opts.Convention,["midpoint","lowest_level","crossing"])} = "midpoint"
                opts.Interpolate (1,1) logical = true
                opts.MinSweeps (1,1) double {mustBeNonnegative} = 2
                opts.MinPerPolarity (1,1) double {mustBeNonnegative} = 0
                opts.LevelDirection (1,1) string {mustBeMember(opts.LevelDirection,["auto","ascending","descending"])} = "auto"
                opts.FlagWideCI (1,1) double = 0.35
                opts.FlagNonMonotoneTol (1,1) double = 0
                opts.CINumSamples (1,1) double {mustBeInteger,mustBePositive} = 2000
                opts.Bootstrap (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                opts.KeepCurated (1,1) logical = true
                opts.SeriesKeys (:,1) string = strings(0,1)
            end
            legacy = opts.Method == "";
            obj.requireConditions();
            if legacy && ~ismember('isSig',obj.Conditions.Properties.VariableNames)
                obj.note('No detections yet; running detect() with its defaults.');
                obj.detect();
            end
            guard = obj.beginStep("thresholds"); %#ok<NASGU>

            % ---- The method.
            ms = mabr.analysis.Session.settingsStruct(opts.MethodSettings);
            if legacy
                mode = "fraction";
                if opts.Type == "glm", mode = "probability"; end
                ms = struct('Alpha',opts.Alpha,'MinConsecutive',opts.MinConsecutive, ...
                    'ThresholdMetric',"detection",'ThresholdModel',opts.Type, ...
                    'CriterionMode',mode,'Criterion',opts.Criterion);
                m = mabr.analysis.SeriesThreshold.resolve("custom",ms);
            else
                if isempty(ms), ms = struct(); end
                ms.Alpha = opts.Alpha;
                ms.MinConsecutive = opts.MinConsecutive;
                m = mabr.analysis.SeriesThreshold.resolve(opts.Method,ms);
            end
            C = obj.Conditions;
            cols = string(C.Properties.VariableNames);
            needP = ismember(m.Metric,["detection","strength"]) || ...
                ismember(m.Model,["isotonic","sigmoid","minimum"]);
            if needP && ~ismember("p",cols)
                error('mabr:analysis:Session:noDetection', ...
                    'The "%s" threshold method needs the permutation test: call detect() first.',m.Id);
            end
            mcol = mabr.analysis.Session.metricColumnOf(m.Metric);
            if m.NeedsMeasures && mcol ~= "" && ~ismember(mcol,cols)
                error('mabr:analysis:Session:noMeasures', ...
                    'The "%s" threshold method needs the single-trial measures: call measure() first.',m.Id);
            end

            % ---- Level axis and series.
            lvl = opts.LevelParam;
            if lvl == "", lvl = obj.levelParamOrEmpty(); end
            if lvl == ""
                obj.note('No level series: thresholds need a parameter with >= 2 values.');
                obj.Thresholds  = table();
                obj.LevelParam  = "";
                obj.GroupParams = string.empty;
                obj.StepOptions.thresholds = mabr.analysis.Session.thresholdOptions(opts,ms);
                obj.clearStepStates("thresholds");
                obj.commitMessages("thresholds",true);
                T = obj.Thresholds;
                return
            end
            if ~ismember(lvl,cols)
                error('mabr:analysis:Session:noSuchParam','"%s" is not a condition column.',lvl);
            end
            grp = opts.GroupBy;
            if ~isempty(grp)
                bad = setdiff(grp,cols);
                if ~isempty(bad)
                    error('mabr:analysis:Session:noSuchGroup', ...
                        'Cannot group by %s: not a condition column.',strjoin(bad,', '));
                end
            end
            [grp,added] = mabr.analysis.Session.seriesGrouping(grp,obj.KeyParams,lvl,obj.poolsAcqModes());
            % Said when it changed something: an added column that varies.
            varies = added(arrayfun(@(c) ismember(c,cols) && ...
                numel(unique(C.(c))) > 1,added));
            if ~isempty(varies)
                obj.note(['Series grouped by %s: %s added to the GroupBy given, since a series ' ...
                    'never mixes stimuli or acquisition modes.'],strjoin(grp,', '),strjoin(varies,' and '));
            end
            if isempty(grp)
                gid = ones(height(C),1);
                G = table();
                keys = "(all)";
            else
                [gid,G,keys] = mabr.analysis.Session.groupRows(C(:,cellstr(grp)),grp);
            end
            dirn = opts.LevelDirection;
            if dirn == "auto"
                dirn = "ascending";
                if contains(lower(lvl),"attenuation"), dirn = "descending"; end
            end
            prev = obj.Thresholds;
            subset = ~isempty(opts.SeriesKeys) && height(prev) > 0 && ...
                isequal(grp,obj.GroupParams) && lvl == obj.LevelParam && ...
                ismember('Decision',prev.Properties.VariableNames);
            if subset
                target = ismember(keys,opts.SeriesKeys);
            else
                target = true(numel(keys),1);
            end

            % ---- Per series.
            tg = find(target);
            rows = cell(numel(tg),1);
            % (A graded method may run on measures alone: no Detected column yet.)
            Det = false(height(C),1);  DetA = Det;
            if ismember("Detected",cols), Det = C.Detected; end
            if ismember("DetectedAuto",cols), DetA = C.DetectedAuto; end
            ov = obj.overrideValues(C.Key);
            % The permutations behind a permutation p (detect's, or the
            % power test's in measure): within twice its Monte-Carlo error of
            % Alpha a detection is flagged borderline.
            nPerm = NaN;
            so = obj.StepOptions;
            if m.Metric == "detection" && isfield(so,'detect') && isfield(so.detect,'NumPermutations')
                nPerm = double(so.detect.NumPermutations);
            elseif m.Metric == "power" && isfield(so,'measure') && isfield(so.measure,'NumPermutations')
                nPerm = double(so.measure.NumPermutations);
            end
            if ~(isscalar(nPerm) && isfinite(nPerm)), nPerm = NaN; end
            p = mabr.analysis.Progress(numel(tg),'Estimating thresholds',obj.Verbose,obj.ProgressFcn);
            for q = 1:numel(tg)
                g = tg(q);
                idx = find(gid == g);
                levels = double(C.(lvl)(idx));
                Y = mabr.analysis.Session.seriesY(C,idx,ov);
                yb = [];
                if opts.Bootstrap > 0 && ~ismember(m.Metric,mabr.analysis.SeriesThreshold.PMetrics)
                    yb = obj.metricBootstrap(idx,m.Metric,opts.Bootstrap,opts.Seed);
                end
                out = mabr.analysis.SeriesThreshold.estimate(levels,Y,m, ...
                    Alpha=opts.Alpha,MinConsecutive=opts.MinConsecutive,Convention=opts.Convention, ...
                    Interpolate=opts.Interpolate,MinSweeps=opts.MinSweeps, ...
                    MinPerPolarity=opts.MinPerPolarity,Alternating=any(C.nPos(idx) > 0 & C.nNeg(idx) > 0), ...
                    Extrapolate=opts.Extrapolate,NearestLevel=opts.NearestLevel,CIAlpha=opts.CIAlpha, ...
                    CINumSamples=opts.CINumSamples,Seed=opts.Seed,LevelDirection=dirn, ...
                    FlagWideCI=opts.FlagWideCI,FlagNonMonotoneTol=opts.FlagNonMonotoneTol, ...
                    LegacyFitTarget=ifelse(legacy,opts.FitTarget,"auto"),YBoot=yb, ...
                    NumPermutations=nPerm);
                Det(idx)  = out.Detected;
                DetA(idx) = out.DetectedAuto;
                rows{q} = mabr.analysis.Session.thresholdRowOf(keys(g),G,g,lvl,m,out);
                p.step();
            end
            p.close();
            if subset
                % The other series as they were; a series whose key is gone
                % leaves (carryCuration archives its curation).
                keep = ~ismember(prev.Key,keys(tg)) & ismember(prev.Key,keys);
                if isempty(rows)
                    Tn = prev(keep,:);
                else
                    New = vertcat(rows{:});
                    Tn = [mabr.analysis.Session.alignColumns(prev(keep,:),New); New];
                end
                [~,o] = ismember(keys,Tn.Key);
                Tn = Tn(o(o > 0),:);
            else
                Tn = vertcat(rows{:});
            end

            % ---- Curation, carried by key.
            arch = obj.CurationArchive;
            nArch = 0;
            if opts.KeepCurated
                [Tn,arch,nArch] = mabr.analysis.Session.carryCuration(Tn,prev,arch,tg,keys,subset);
            end
            Tn = mabr.analysis.Session.refreshCuration(Tn,m.Id,ismember(Tn.Key,keys(tg)));

            % ---- Messages.
            fin = isfinite(Tn.Threshold(ismember(Tn.Key,keys(tg))));
            st  = Tn.Status(ismember(Tn.Key,keys(tg)));
            if legacy
                obj.note('%d thresholds (%s fit, criterion %.2f); %d without a response.', ...
                    numel(tg),opts.Type,opts.Criterion,sum(~fin));
            else
                obj.note('%d thresholds by %s: %d ok, %d no response, %d all respond, %d insufficient.', ...
                    numel(tg),m.Id,sum(st == "ok"),sum(st == "no-response"),sum(st == "all-respond"), ...
                    sum(st == "insufficient"));
            end
            if nArch > 0
                obj.warn('%d curated threshold(s) no longer match a series; they are kept in CurationArchive.',nArch);
            end
            nChg = sum(contains(Tn.Flags,"fit changed since review") & Tn.Decision == "");
            if nChg > 0
                obj.warn('%d accepted fit(s) changed since review and need reviewing again.',nChg);
            end

            % ---- Commit.
            % The method's verdict per condition, whichever metric made it.
            C.Detected = Det;  C.DetectedAuto = DetA;
            obj.Conditions = mabr.analysis.Session.canonicalConditions(C,obj.KeyParams);
            obj.Thresholds      = Tn;
            obj.CurationArchive = arch;
            obj.LevelParam      = lvl;
            obj.GroupParams     = grp;
            obj.Peaks           = obj.peaksBelow(obj.Peaks,keys(tg));
            obj.StepOptions.thresholds = mabr.analysis.Session.thresholdOptions(opts,ms);
            if ~subset, obj.clearStepStates("thresholds"); end
            obj.commitMessages("thresholds",~subset);
            T = obj.Thresholds;
        end

        function setThreshold(obj,row,value)
            % LEGACY curation of one threshold by row: setDecision by another name.
            %
            % Inf records "no response" (Decision "noresponse"), NaN excludes
            % the series ("excluded"), and any other value is a manual value
            % (Decision "manual", ManualKind "value"). The fit stays in
            % Threshold and the human answer lands in Final, mirrored in
            % Curated/IsCurated as before -- because the two disagreeing is
            % information, and a curated session must still be able to say
            % what the model said. Recorded in EditLog.
            %
            %   row    row index into obj.Thresholds
            %   value  the curated threshold (Inf = no response, NaN = excluded)
            %   (no return value)
            arguments
                obj
                row (1,1) double {mustBeInteger,mustBePositive}
                value (1,1) double
            end
            obj.requireThresholds();
            if row > height(obj.Thresholds)
                error('mabr:analysis:Session:noSuchRow', ...
                    'Row %d: there are %d thresholds.',row,height(obj.Thresholds));
            end
            T = obj.Thresholds;
            if ~ismember('Decision',T.Properties.VariableNames)
                % A table from before named methods (a v1 results file).
                old = T.Curated(row);
                key = "";
                if ismember('Key',T.Properties.VariableNames), key = T.Key(row); end
                obj.Thresholds.Curated(row)   = value;
                obj.Thresholds.IsCurated(row) = true;
                obj.logEdit("setThreshold",key,old,value);
                return
            end
            if isnan(value)
                obj.setDecision(T.Key(row),"excluded");
            elseif isinf(value) && value > 0
                obj.setDecision(T.Key(row),"noresponse");
            else
                obj.setDecision(T.Key(row),"manual",Value=value,Kind="value");
            end
        end

        function row = thresholdRow(obj,param,value)
            % The threshold row for one group value, e.g. thresholdRow("Frequency",16).
            %
            %   param  grouping column name in obj.Thresholds
            %   value  value to match in that column (a NaN matches NaN -- a
            %          click series has no frequency; text matches a Stimulus
            %          or AcqMode column)
            %   row    (returned) row index of the first match, or [] when none
            arguments
                obj
                param (1,1) string
                value
            end
            obj.requireThresholds();
            if ~ismember(param,string(obj.Thresholds.Properties.VariableNames))
                error('mabr:analysis:Session:noSuchGroup', ...
                    'Thresholds are not grouped by "%s".',param);
            end
            row = find(mabr.analysis.Session.matches(obj.Thresholds.(param),value),1);
        end

        % =================================================================
        %  Access
        % =================================================================
        function r = rowOf(obj,key)
            % Conditions row(s) of condition key(s).
            %
            %   key  condition key text (string array for several)
            %   r    (returned) row indices, same size; throws
            %        mabr:analysis:Session:unknownKey for a key not there
            arguments
                obj
                key string
            end
            obj.requireConditions();
            [tf,r] = ismember(key,obj.Conditions.Key);
            if ~all(tf(:))
                bad = key(~tf);
                error('mabr:analysis:Session:unknownKey', ...
                    'No condition "%s" in %s.',bad(1),obj.Name);
            end
        end

        function r = seriesRow(obj,seriesKey)
            % Thresholds row of a series key ([] when there is none).
            arguments
                obj
                seriesKey (1,1) string
            end
            r = [];
            if height(obj.Thresholds) == 0 || ~ismember('Key',obj.Thresholds.Properties.VariableNames)
                return
            end
            r = find(obj.Thresholds.Key == seriesKey,1);
        end

        function k = seriesKeys(obj)
            % Every series key of this session's conditions, in series order.
            %
            %   k  (returned) string column: ordered by Stimulus, AcqMode, then
            %      the group parameters ascending, NaN last. A series is every
            %      condition sharing the series columns (GroupParams of the last
            %      threshold estimate, else every key column but the level); a
            %      session with no level parameter has one series per condition.
            k = strings(0,1);
            if height(obj.Conditions) == 0, return; end
            cols = obj.seriesColumns();
            if isempty(cols)
                k = "(all)";
                return
            end
            [~,~,k] = mabr.analysis.Session.groupRows(obj.Conditions(:,cellstr(cols)),cols);
        end

        function k = seriesConditions(obj,seriesKey)
            % Condition keys of one series, level ascending (NaN last).
            arguments
                obj
                seriesKey (1,1) string
            end
            k = strings(0,1);
            if height(obj.Conditions) == 0, return; end
            sk = obj.conditionSeriesKeys();
            r = find(sk == seriesKey);
            if isempty(r), return; end
            lp = obj.levelParamOrEmpty();
            if lp ~= "" && ismember(lp,string(obj.Conditions.Properties.VariableNames))
                lv = obj.Conditions.(lp)(r);
                lv(isnan(lv)) = Inf;
                [~,o] = sort(lv);
                r = r(o);
            end
            k = obj.Conditions.Key(r);
        end

        function sk = seriesOf(obj,condKey)
            % Series key of condition key(s).
            arguments
                obj
                condKey string
            end
            r  = obj.rowOf(condKey);
            every = obj.conditionSeriesKeys();
            sk = reshape(every(r),size(condKey));
        end

        function [m,sem,n] = conditionMean(obj,key,polarity)
            % One condition's mean waveform, from its sweeps or saved means.
            %
            %   key       condition key
            %   polarity  "balanced" (default: equal weight per polarity, so a
            %             polarity-following component cancels), "positive",
            %             "negative", "difference" ((m+ - m-)/2, what follows
            %             polarity), or "all" (every clean sweep alike)
            %   m, sem    (returned) [nT x 1] double, NaN outside the condition's
            %             Extent; sem is NaN where it cannot be had (results-only
            %             means carry the balanced SEM alone)
            %   n         (returned) sweeps behind m
            %
            %   From the clean sweeps (not rejected, not excess) when they are in
            %   memory, else from Means -- so it works on a results-only session.
            arguments
                obj
                key (1,1) string
                polarity (1,1) string {mustBeMember(polarity,["balanced","positive","negative","difference","all"])} = "balanced"
            end
            r = obj.rowOf(key);
            nT = numel(obj.Time);
            C = obj.Conditions;
            % With sweeps in memory they are the answer, even when a condition
            % has none: Means may be left over from a results file this
            % session was loaded from, and describes a different segmentation.
            if obj.HasSweeps && ismember('Sweeps',C.Properties.VariableNames)
                [X,pol,str] = obj.cleanSweeps(r);
                if size(X,1) ~= nT, X = NaN(nT,size(X,2)); end   % an empty, unshaped cell
                N = size(X,2);
                switch polarity
                    case "balanced"
                        [m,sem] = mabr.analysis.Stats.balancedMean(X,pol,str);
                        n = N;
                    case {"positive","negative"}
                        if polarity == "positive", s = pol > 0; else, s = pol < 0; end
                        [m,sem] = mabr.analysis.Stats.balancedMean(X(:,s),[],str(s));
                        n = sum(s);
                    case "difference"
                        s = pol > 0;
                        [mp,sp] = mabr.analysis.Stats.balancedMean(X(:,s),[],str(s));
                        [mq,sq] = mabr.analysis.Stats.balancedMean(X(:,~s),[],str(~s));
                        m = (mp - mq)/2;
                        sem = sqrt(sp.^2 + sq.^2)/2;
                        n = N;
                    case "all"
                        if N == 0
                            m = NaN(nT,1);  sem = NaN(nT,1);
                        else
                            m = mean(X,2);
                            sem = std(X,0,2)/sqrt(N);
                            if N < 2, sem(:) = NaN; end
                        end
                        n = N;
                end
                return
            end

            % Results only: the saved means.
            M = obj.Means;
            k = find(M.Keys == key,1);
            m = NaN(nT,1);  sem = NaN(nT,1);  n = 0;
            if isempty(k) || isempty(M.Balanced), return; end
            nPos = 0;  nNeg = 0;
            if ismember('nPos',C.Properties.VariableNames), nPos = C.nPos(r); nNeg = C.nNeg(r); end
            switch polarity
                case "balanced"
                    m = double(M.Balanced(:,k));  sem = double(M.SEM(:,k));  n = M.N(k);
                case "positive"
                    m = double(M.Positive(:,k));  n = nPos;
                case "negative"
                    m = double(M.Negative(:,k));  n = nNeg;
                case "difference"
                    m = (double(M.Positive(:,k)) - double(M.Negative(:,k)))/2;  n = M.N(k);
                case "all"
                    n = M.N(k);
                    if nPos > 0 && nNeg > 0
                        m = (nPos*double(M.Positive(:,k)) + nNeg*double(M.Negative(:,k)))/(nPos + nNeg);
                    else
                        m = double(M.Balanced(:,k));
                    end
            end
        end

        function s = conditionLabel(obj,key)
            % A condition named by what varies in this session: "8 kHz, 60 dB".
            %
            %   key  condition key
            %   s    (returned) 1x1 string: the varying parameters in key order
            %        ("Tone, 8 kHz, 60 dB" when the stimulus varies too; a NaN
            %        parameter is left out), units from
            %        mabr.stim.StimulusSet.paramUnit, " · <AcqMode>" when the
            %        session holds more than one acquisition mode
            arguments
                obj
                key (1,1) string
            end
            r = obj.rowOf(key);
            names = obj.varyingParams();
            if isempty(names)
                names = obj.ParamNames;
            end
            names = mabr.analysis.Session.inKeyOrder(names,obj.KeyParams);
            parts = strings(1,0);
            for nm = names
                if ~ismember(nm,string(obj.Conditions.Properties.VariableNames)), continue; end
                t = mabr.analysis.Session.valueText(nm,obj.Conditions.(nm)(r));
                if t ~= "", parts(end+1) = t; end %#ok<AGROW>
            end
            s = strjoin(parts,", ");
            if s == "", s = key; end
            if obj.multipleAcqModes()
                s = s + " · " + obj.Conditions.AcqMode(r);
            end
        end

        function s = seriesLabel(obj,seriesKey)
            % A series named for a reader: "Tone 8 kHz" (+ " · interleaved").
            %
            %   seriesKey  series key
            %   s          (returned) 1x1 string: the stimulus, then the series'
            %              other parameters with their units (NaN left out);
            %              " · <AcqMode>" when the session holds more than one
            %              acquisition mode; "(all)" for a series of everything
            arguments
                obj
                seriesKey (1,1) string
            end
            s = "(all)";
            if height(obj.Conditions) == 0, return; end
            sk = obj.conditionSeriesKeys();
            r = find(sk == seriesKey,1);
            if isempty(r)
                error('mabr:analysis:Session:unknownKey','No series "%s" in %s.',seriesKey,obj.Name);
            end
            cols = obj.seriesColumns();
            parts = strings(1,0);
            if ismember("Stimulus",cols) && obj.Conditions.Stimulus(r) ~= ""
                parts(end+1) = obj.Conditions.Stimulus(r);
            end
            for nm = setdiff(cols,["Stimulus","AcqMode"],'stable')
                t = mabr.analysis.Session.valueText(nm,obj.Conditions.(nm)(r));
                if t ~= "", parts(end+1) = t; end %#ok<AGROW>
            end
            if ~isempty(parts), s = strjoin(parts," "); end
            if obj.multipleAcqModes() && ismember('AcqMode',obj.Conditions.Properties.VariableNames)
                s = s + " · " + obj.Conditions.AcqMode(r);
            end
        end

        function c = groupColumns(obj)
            % The series (non-level key) columns of Thresholds.
            %
            %   c  (returned) string row: GroupParams of the last threshold
            %      estimate, else every key column but the level
            c = obj.seriesColumns();
        end

        function lp = levelParamOrEmpty(obj)
            % levelParam(), or "" where it cannot be told (never throws).
            try
                lp = obj.levelParam();
            catch
                lp = "";
            end
        end

        function X = sweeps(obj,row,opts)
            % Sweeps for one condition: [nSamples x nSweeps].
            %
            % Flagged sweeps are excluded by default and are one argument away;
            % so are excess ones (beyond MaxSweepsPerCondition).
            %
            %   row                    row index into obj.Conditions, or a condition key
            %   opts.IncludeRejected   include flagged sweeps (default false)
            %   opts.IncludeExcess     include sweeps beyond the cap (default false)
            %   opts.Polarity          "all" (default), "positive", or "negative"
            %   opts.Window            ms window to crop rows to (default: obj.Window, i.e. no crop)
            %   X  (returned) [nSamples x nKept] double
            arguments
                obj
                row
                opts.IncludeRejected (1,1) logical = false
                opts.IncludeExcess (1,1) logical = false
                opts.Polarity (1,1) string {mustBeMember(opts.Polarity,["all","positive","negative"])} = "all"
                opts.Window double = []
            end
            obj.requireConditions();
            r = obj.rowIndex(row);
            X = obj.Conditions.Sweeps{r};
            if isempty(X), return; end

            keep = true(1,size(X,2));
            if ~opts.IncludeRejected
                keep = keep & ~obj.Conditions.Rejected{r};
            end
            if ~opts.IncludeExcess && ismember('Excess',obj.Conditions.Properties.VariableNames)
                keep = keep & ~obj.Conditions.Excess{r};
            end
            if opts.Polarity ~= "all"
                pol = obj.Conditions.Polarity{r};
                if numel(pol) == size(X,2)
                    if opts.Polarity == "positive", keep = keep & pol > 0;
                    else,                           keep = keep & pol < 0;
                    end
                end
            end
            X = X(:,keep);

            if ~isempty(opts.Window)
                X = X(mabr.analysis.Artifacts.windowMask(obj.Time,opts.Window),:);
            end
        end

        function M = means(obj,opts)
            % Mean waveform per condition: [nSamples x nConditions].
            %
            % A condition with no surviving sweeps is a column of NaN, not a
            % column of zeros: there is no average to report, and zeros would
            % draw as a flat trace indistinguishable from a real null.
            %
            %   opts.IncludeRejected  include flagged sweeps (default false)
            %   opts.Polarity         "all" (default), "positive", or "negative"
            %   M  (returned) [nSamples x nConditions] double
            arguments
                obj
                opts.IncludeRejected (1,1) logical = false
                opts.Polarity (1,1) string = "all"
            end
            obj.requireConditions();
            n = height(obj.Conditions);
            M = nan(numel(obj.Time),n);
            for i = 1:n
                X = obj.sweeps(i,IncludeRejected=opts.IncludeRejected,Polarity=opts.Polarity);
                if ~isempty(X), M(:,i) = mean(X,2); end
            end
        end

        function [S,U,rowVals,colVals] = grid(obj,rowParam,colParam,opts)
            % Reshape conditions into the [row x col] cell array the older
            % plotting and threshold functions expect.
            %
            %   [S,U] = s.grid("Level","Frequency")
            %
            % S{r,c} is a [nSamples x nSweeps] matrix (or the mean, with
            % Reduce="mean"), empty where the session holds no such condition.
            % U is the struct of unique values, one field per parameter. A
            % condition whose row or column parameter is NaN -- a click on a
            % frequency grid -- is not on the grid; Where restricts it further
            % (NaN in a Where value matches NaN).
            %
            %   rowParam               row parameter name (default "" = levelParam())
            %   colParam               column parameter name (default "" = frequencyParam())
            %   opts.IncludeRejected   include flagged sweeps (default false)
            %   opts.Reduce            "none" (default) or "mean"
            %   opts.Where             struct of param=values to restrict to (default none)
            %   opts.Window            ms window to crop sweeps to (default: no crop)
            %   S        (returned) [nRow x nCol] cell, see above
            %   U        (returned) struct of unique parameter values, one field per parameter
            %   rowVals  (returned) unique row values, ascending, [nRow x 1]
            %   colVals  (returned) unique column values, ascending, [nCol x 1]
            %            (or 1 when colParam is "")
            arguments
                obj
                rowParam (1,1) string = ""
                colParam (1,1) string = ""
                opts.IncludeRejected (1,1) logical = false
                opts.Reduce (1,1) string {mustBeMember(opts.Reduce,["none","mean"])} = "none"
                opts.Where struct = struct()
                opts.Window double = []
            end
            obj.requireConditions();

            if rowParam == "", rowParam = obj.levelParam(); end
            if colParam == "", colParam = obj.frequencyParam(); end

            C = obj.Conditions;
            keep = obj.whereMask(opts.Where);
            keep = keep & mabr.analysis.Session.gridColumn(C,rowParam);
            if colParam ~= ""
                keep = keep & mabr.analysis.Session.gridColumn(C,colParam);
            end
            idx = find(keep);

            rowVals = unique(C.(rowParam)(idx));
            if colParam == ""
                colVals = 1;
                colOf = @(k) 1;
            else
                colVals = unique(C.(colParam)(idx));
                colOf = @(k) find(colVals == C.(colParam)(k),1);
            end

            S = cell(numel(rowVals),numel(colVals));
            for k = idx(:).'
                r = find(rowVals == C.(rowParam)(k),1);
                c = colOf(k);
                X = obj.sweeps(k,IncludeRejected=opts.IncludeRejected,Window=opts.Window);
                if opts.Reduce == "mean" && ~isempty(X), X = mean(X,2); end
                if isempty(S{r,c})
                    S{r,c} = X;
                else
                    S{r,c} = [S{r,c} X];    % two conditions folded onto one tile
                end
            end

            U = struct();
            for pn = obj.ParamNames
                if ~ismember(pn,string(C.Properties.VariableNames)), continue; end
                U.(pn) = mabr.analysis.Session.uniqueValues(C.(pn)(idx)).';
            end
        end

        function t = timeVector(obj,window)
            % Time in ms, optionally restricted to a window.
            %
            %   window  [t0 t1] ms (default [-Inf Inf] = all of obj.Time)
            %   t       (returned) [n x 1] double subset of obj.Time
            arguments
                obj
                window (1,2) double = [-Inf Inf]
            end
            t = obj.Time(obj.Time >= window(1) & obj.Time <= window(2));
        end

        function names = varyingParams(obj)
            % Parameters that take more than one value in this session.
            %
            %   names  (returned) string row vector, subset of obj.ParamNames;
            %          NaN counts as one value (a click among tones makes
            %          Frequency vary)
            names = strings(1,0);
            if isempty(obj.Conditions) || height(obj.Conditions) == 0, return; end
            for pn = obj.ParamNames
                if ~ismember(pn,string(obj.Conditions.Properties.VariableNames)), continue; end
                if numel(mabr.analysis.Session.uniqueValues(obj.Conditions.(pn))) > 1
                    names(end+1) = pn; %#ok<AGROW>
                end
            end
        end

        function pn = levelParam(obj)
            % Which parameter is the level axis.
            %
            %   pn  (returned) 1x1 string, a name in obj.ParamNames; throws
            %       mabr:analysis:Session:noLevelParam when it cannot be told
            pn = obj.matchParam(mabr.analysis.Session.LevelAliases);
            if pn == ""
                v = obj.numericVarying();
                if isscalar(v)
                    pn = v;
                else
                    error('mabr:analysis:Session:noLevelParam', ...
                        ['Cannot tell which parameter is the level. Pass LevelParam. ' ...
                         'Parameters found: %s.'],strjoin(obj.ParamNames,', '));
                end
            end
        end

        function pn = frequencyParam(obj)
            % Which parameter is the frequency axis ("" when there is none).
            %
            %   pn  (returned) 1x1 string, a name in obj.ParamNames, or ""
            pn = obj.matchParam(mabr.analysis.Session.FrequencyAliases);
            if pn == ""
                v = setdiff(obj.numericVarying(),obj.levelParam(),'stable');
                if isscalar(v), pn = v; end
            end
        end

        % =================================================================
        %  Plotting (thin wrappers; the drawing is in mabr.analysis.Plot)
        % =================================================================
        function [ax,tl] = plotGrid(obj,opts)
            % The level x frequency grid of averaged responses.
            %
            %   opts.RowParam    row parameter (default "" = levelParam())
            %   opts.ColParam    column parameter (default "" = frequencyParam())
            %   opts.Window      ms window to draw (default [-2 10])
            %   opts.Normalize   passed to mabr.analysis.Plot.grid (default "column")
            %   opts.Palette     palette name (default "linear")
            %   opts.Thresholds  draw the threshold row per column (default true)
            %   opts.Curated     use Curated rather than fitted Threshold (default true)
            %   opts.Where       struct of param=values to restrict to (default none)
            %   opts.Parent      tiledlayout to draw into (default: a new figure)
            %   ax  (returned) [nRow x nCol] array of axes handles
            %   tl  (returned) the tiledlayout
            arguments
                obj
                opts.RowParam (1,1) string = ""
                opts.ColParam (1,1) string = ""
                opts.Window (1,2) double = [-2 10]
                opts.Normalize (1,1) string = "column"
                opts.Palette (1,1) string = "linear"
                opts.Thresholds (1,1) logical = true
                opts.Curated (1,1) logical = true
                opts.Where struct = struct()
                opts.Parent = []
            end
            obj.requireConditions();
            [S,~,rowVals,colVals] = obj.grid(opts.RowParam,opts.ColParam,Reduce="mean",Where=opts.Where);
            if isempty(S)
                error('mabr:analysis:Session:emptyGrid','No condition lies on that grid.');
            end

            rp = opts.RowParam; if rp == "", rp = obj.levelParam(); end
            cp = opts.ColParam; if cp == "", cp = obj.frequencyParam(); end

            th = [];
            T = obj.Thresholds;
            if opts.Thresholds && height(T) > 0 && ismember('Curated',T.Properties.VariableNames)
                if opts.Curated, tv = T.Curated; else, tv = T.Threshold; end
                if cp ~= "" && ismember(cp,string(T.Properties.VariableNames))
                    th = NaN(1,numel(colVals));
                    for c = 1:numel(colVals)
                        k = find(mabr.analysis.Session.matches(T.(cp),colVals(c)),1);
                        if ~isempty(k), th(c) = tv(k); end
                    end
                elseif height(T) == numel(colVals)
                    th = tv.';
                end
            end

            [ax,tl] = mabr.analysis.Plot.grid(S,obj.Time,rowVals,colVals, ...
                Window=opts.Window, Normalize=opts.Normalize, Palette=opts.Palette, ...
                RowLabel=obj.axisLabel(rp), ColLabel=obj.axisLabel(cp), ...
                Threshold=th, Parent=opts.Parent);

            title(tl,char(obj.Name),'Interpreter','none');
            if ~isnat(obj.Date)
                d = obj.Date; d.Format = 'dd-MMM-uuuu';
                subtitle(tl,char(d));
            end
        end

        function ax = plotAudiogram(obj,opts)
            % Thresholds against frequency.
            %
            % Series without a frequency (a click) are skipped by
            % mabr.analysis.Plot.audiogram; the y axis is labelled in the
            % session's level reference (dB SPL only for calibrated files).
            %
            %   opts.Curated  use Curated rather than fitted Threshold (default true)
            %   opts.CI       draw CI bars when available (default true)
            %   opts.Where    struct of column=values restricting the rows (default none)
            %   opts.Parent   axes to draw into (default: a new figure's axes)
            %   opts.Hold     overlay onto Parent instead of clearing it (default false)
            %   ax  (returned) the axes
            arguments
                obj
                opts.Curated (1,1) logical = true
                opts.CI (1,1) logical = true
                opts.Where struct = struct()
                opts.Parent = []
                opts.Hold (1,1) logical = false
            end
            obj.requireThresholds();
            T = obj.Thresholds;
            fn = fieldnames(opts.Where);
            keep = true(height(T),1);
            for i = 1:numel(fn)
                if ismember(fn{i},T.Properties.VariableNames)
                    keep = keep & mabr.analysis.Session.matches(T.(fn{i}),opts.Where.(fn{i}));
                end
            end
            T = T(keep,:);

            fp = "";
            try
                fp = obj.frequencyParam();
            catch
                % No level axis either: the series are simply numbered.
            end
            xl = "Series";  xs = "linear";
            if fp == "" || ~ismember(fp,string(T.Properties.VariableNames))
                x = (1:height(T));
            else
                x = T.(fp).';
                xl = obj.axisLabel(fp);
                xs = "log";
            end

            if opts.Curated, y = T.Curated.'; else, y = T.Threshold.'; end

            ci = [];
            if opts.CI && all(ismember({'CILower','CIUpper'},T.Properties.VariableNames))
                ci = [T.CILower.'; T.CIUpper.'];
            end

            ax = mabr.analysis.Plot.audiogram(x,y, CI=ci, Parent=opts.Parent, ...
                Hold=opts.Hold, DisplayName=obj.Name, XLabel=xl, ...
                YLabel="Threshold (" + obj.levelUnitText() + ")", XScale=xs);
            title(ax,char(obj.Name),'Interpreter','none');
        end

        function ax = plotStack(obj,colValue,opts)
            % One frequency's level series as an offset waterfall.
            %
            %   colValue      the frequency-axis value to hold fixed (NaN = the
            %                 series without a frequency, e.g. a click)
            %   opts.Window   ms window to draw (default [-2 10])
            %   opts.Palette  palette name (default "linear")
            %   opts.Where    further restriction, e.g. struct('AcqMode',"conventional")
            %   opts.Parent   axes to draw into (default: a new figure's axes)
            %   ax  (returned) the axes
            arguments
                obj
                colValue (1,1) double
                opts.Window (1,2) double = [-2 10]
                opts.Palette (1,1) string = "linear"
                opts.Where struct = struct()
                opts.Parent = []
            end
            rp = obj.levelParam();
            cp = obj.frequencyParam();
            w = opts.Where;
            if cp ~= "", w.(cp) = colValue; end
            % One column, chosen by Where -- a NaN frequency included, which
            % grid() would leave off a frequency axis.
            C = obj.Conditions;
            idx = find(obj.whereMask(w) & mabr.analysis.Session.gridColumn(C,rp));
            rowVals = unique(C.(rp)(idx));
            S = cell(numel(rowVals),1);
            for k = idx(:).'
                X = obj.sweeps(k);
                if isempty(X), continue; end
                r = find(rowVals == C.(rp)(k),1);
                S{r} = [S{r} X];                % conditions folded onto one level
            end
            for r = 1:numel(S)
                if ~isempty(S{r}), S{r} = mean(S{r},2); end
            end

            th = NaN;
            T = obj.Thresholds;
            if height(T) > 0 && cp ~= "" && ismember(cp,string(T.Properties.VariableNames)) ...
                    && ismember('Curated',T.Properties.VariableNames)
                m = mabr.analysis.Session.matches(T.(cp),colValue);
                fn = fieldnames(opts.Where);
                for i = 1:numel(fn)
                    if ismember(fn{i},T.Properties.VariableNames)
                        m = m & mabr.analysis.Session.matches(T.(fn{i}),opts.Where.(fn{i}));
                    end
                end
                k = find(m,1);
                if ~isempty(k), th = T.Curated(k); end
            end
            if isempty(S)
                error('mabr:analysis:Session:emptyGrid','No condition has %s = %g.',cp,colValue);
            end

            ax = mabr.analysis.Plot.stack(S(:,1),obj.Time,rowVals, ...
                Window=opts.Window, Palette=opts.Palette, Threshold=th, Parent=opts.Parent, ...
                RowFormat="%g " + obj.levelUnitText());
            if cp == ""
                title(ax,char(obj.Name),'Interpreter','none');
            else
                title(ax,sprintf('%s  %s = %g',obj.Name,cp,colValue),'Interpreter','none');
            end
        end

        % =================================================================
        %  Persistence
        % =================================================================
        function ffn = saveResults(obj,ffn,opts)
            % Save everything this session knows to a .mat file (results v2).
            %
            % One variable per part (see toStruct), so the small ones can be
            % read without the rest: load(f,'Version','Summary','Thresholds').
            % Atomic by default: written to <ffn>.tmp-<pid>.mat and moved onto
            % ffn, so a reader -- or a crash -- never sees half a file; a move
            % that keeps failing leaves the .tmp in place and throws
            % mabr:analysis:Session:saveFailed naming it.
            %
            %   ffn                 destination file path (folders created as needed)
            %   opts.IncludeSweeps  include the sweeps (default true)
            %   opts.IncludeFits    include each threshold's Fit (default true)
            %   opts.Atomic         write via a temporary file (default true)
            %   ffn  (returned) the same file path, for chaining
            %
            %   Saving is not an analysis step and leaves no row in Messages:
            %   "Saved <file>." is printed when Verbose and that is all. The
            %   app saves after every edit, and Messages is written into the
            %   file, so a row per save would grow every results file by a
            %   line an edit. Rows an older MABR recorded under step "save"
            %   are left out of what is written, and dropped once it is.
            arguments
                obj
                ffn (1,1) string
                opts.IncludeSweeps (1,1) logical = true
                opts.IncludeFits (1,1) logical = true
                opts.Atomic (1,1) logical = true
            end
            % Anything noted while saving is printed and heard (MessageFcn)
            % but, collected under "save" and never committed, not recorded.
            guard = obj.beginStep("save"); %#ok<NASGU>
            R = obj.toStruct(opts.IncludeSweeps,opts.IncludeFits);
            isSave = mabr.analysis.Session.saveRows(R.Messages);
            R.Messages(isSave,:) = [];
            d = fileparts(char(ffn));
            if ~isempty(d) && ~isfolder(d), mkdir(d); end

            % -v7 compresses and is read by every MATLAB since 7; only sweeps
            % past its 2 GB-per-variable limit need -v7.3.
            matVer = '-v7';
            if isfield(R,'Sweeps')
                bytes = sum(cellfun(@(x) 8*numel(x),R.Sweeps));
                if bytes > 1.5e9, matVer = '-v7.3'; end
            end
            if ~opts.Atomic
                save(char(ffn),'-struct','R',matVer);
            else
                tmp = ffn + ".tmp-" + feature('getpid') + ".mat";
                save(char(tmp),'-struct','R',matVer);
                ok = false;  msg = '';
                for attempt = 1:3
                    [ok,msg] = movefile(char(tmp),char(ffn),'f');
                    if ok, break; end
                    pause(0.25);
                end
                if ~ok
                    error('mabr:analysis:Session:saveFailed', ...
                        'Could not move the results onto %s (%s). They are kept in %s.', ...
                        ffn,msg,tmp);
                end
            end
            M = obj.Messages;
            obj.Messages = M(~mabr.analysis.Session.saveRows(M),:);
            if obj.Verbose
                fprintf('  Saved %s.\n',ffn);
            end
        end

        function R = toStruct(obj,includeSweeps,includeFits)
            % Plain-struct form of the session (results v2), for saving.
            %
            % Deliberately plain: a results file that needs this class to load
            % is a results file that stops opening the day the class changes.
            % Tables, structs, strings and numbers only -- no handles, no
            % objects.
            %
            %   includeSweeps  include the sweeps as R.Sweeps (default true)
            %   includeFits    include the Fit column of Thresholds (default true)
            %   R  (returned) struct of the results-v2 variables: Version,
            %      Provenance, Settings, StepState, StepOptions, Summary, Files,
            %      Conditions (no cell columns), Means, SweepInfo, Detection,
            %      Thresholds (no function handles), CurationArchive, Peaks,
            %      PeakOverrides, ManualRejections, DetectionOverrides, Messages,
            %      EditLog, and Sweeps (cell column aligned with Conditions)
            %      when asked for and held
            arguments
                obj
                includeSweeps (1,1) logical = true
                includeFits (1,1) logical = true
            end
            R = struct();
            R.Version     = mabr.analysis.Session.Version;
            R.Provenance  = obj.provenance();
            R.Settings    = mabr.analysis.Session.settingsStruct(obj.Settings);
            R.StepState   = obj.StepState;
            R.StepOptions = obj.StepOptions;
            R.Summary     = obj.summaryStruct();
            R.Files       = obj.Files;

            C = obj.Conditions;
            if height(C) > 0 || width(C) > 0
                cells = varfun(@iscell,C,'OutputFormat','uniform');
                C(:,cells) = [];
            end
            R.Conditions = C;
            R.Means      = obj.meansStruct();
            R.SweepInfo  = obj.sweepInfoStruct();
            R.Detection  = obj.detectionStruct();

            T = obj.Thresholds;
            if ismember('Fit',T.Properties.VariableNames)
                if includeFits
                    for k = 1:height(T)
                        T.Fit{k} = mabr.analysis.Session.stripHandles(T.Fit{k});
                    end
                else
                    T.Fit = [];
                end
            end
            R.Thresholds         = T;
            R.CurationArchive    = obj.CurationArchive;
            R.Peaks              = obj.Peaks;
            R.PeakOverrides      = obj.PeakOverrides;
            R.ManualRejections   = obj.ManualRejections;
            R.DetectionOverrides = obj.DetectionOverrides;
            R.Messages           = obj.Messages;
            R.EditLog            = obj.EditLog;
            if includeSweeps && obj.HasSweeps && ismember('Sweeps',obj.Conditions.Properties.VariableNames)
                R.Sweeps = obj.Conditions.Sweeps;
            end
        end

        % =================================================================
        %  7. Peaks
        % =================================================================
        function T = pickPeaks(obj,opts)
            % Pick and track waves I-V (or the waves given) down every series.
            %
            % Per series: the condition means (conditionMean, so it works on a
            % results-only session too) loudest first through
            % mabr.analysis.Peaks.track, with the wave windows of
            % Peaks.wavesFor for the series' stimulus and frequency, in the
            % recording's own time (re the timing pulse) -- the time they were
            % drawn up in, by eye on recordings, in mabr.ui.TraceInspector.
            % The LATENCY OFFSET (conduction delay plus system offset) is not
            % added to them: it is a reporting correction, so a delay moves
            % every reported latency by exactly itself and changes no pick.
            % (Windows moved by it searched 0.29 ms later for 10 cm of air,
            % and a peak near the edge of two overlapping windows changed its
            % label when the delay was switched on.) The user's corrections in
            % PeakOverrides are the track's anchors, so a manual pick stays
            % where it was put and the levels below track from it, and an
            % absent wave stays absent. Candidates must stand CandidateRN x RN
            % (each level's residual noise) proud of their neighbours.
            %
            % Per pick: AmpPT = PeakValue - TroughValue; Baseline = the mean
            % over BaselineAmpWindow (NaN unless the condition holds that
            % window); AmpBP/AmpBT from it; ProminenceRN = Prominence/RN and
            % Detectable = ProminenceRN >= DetectableRN; BelowThreshold from
            % the series' Final threshold (SeriesThreshold.belowThreshold);
            % EdgeAffected for a windowed condition's pick within EdgeMs of its
            % Extent. Bootstrap > 0 (sweeps in memory) adds the bootstrap SE and
            % intervals of latency and AmpPT, per condition from its own stream.
            %
            % Latencies stay RAW, re the onset; the LatencyOffset column says
            % what Peaks.reported(PeakLatency,LatencyOffset) subtracts to give
            % latency re sound arrival (which is why a change of delay re-runs
            % this step: the picks come out the same, the column does not).
            %
            %   opts.Waves          wave struct array (default Peaks.defaultWaves())
            %   opts.OctaveShift    ms per octave below RefFrequency (0.15)
            %   opts.RefFrequency   kHz (16)
            %   opts.Smooth         moving-mean samples of the picking copy (0)
            %   opts.MinSeparation  ms (0.3)
            %   opts.TrackEarly, opts.TrackLate  ms (0.1, 0.15)
            %   opts.CandidateRN, opts.DetectableRN  multiples of RN (1, 2)
            %   opts.Polarity       "balanced" (default), "positive", "negative"
            %   opts.AboveThresholdOnly  recorded for the derived measures (true)
            %   opts.BaselineAmpWindow   ms ([-1 0])
            %   opts.EdgeMs         ms (1.0)
            %   opts.Bootstrap      replicates (0 = none)
            %   opts.Seed           base seed of the bootstrap (1)
            %   opts.SeriesKeys     only these series (default all)
            %   opts.LatencyOffset  ms; NaN (default) = obj.LatencyOffset
            %   T  (returned) obj.Peaks (see the class help for its columns)
            arguments
                obj
                opts.Waves = mabr.analysis.Peaks.defaultWaves()
                opts.OctaveShift (1,1) double = 0.15
                opts.RefFrequency (1,1) double {mustBePositive} = 16
                opts.Smooth (1,1) double {mustBeNonnegative} = 0
                opts.MinSeparation (1,1) double {mustBeNonnegative} = 0.3
                opts.TrackEarly (1,1) double {mustBeNonnegative} = 0.1
                opts.TrackLate (1,1) double {mustBeNonnegative} = 0.15
                opts.CandidateRN (1,1) double {mustBeNonnegative} = 1
                opts.DetectableRN (1,1) double {mustBeNonnegative} = 2
                opts.Polarity (1,1) string {mustBeMember(opts.Polarity,["balanced","positive","negative"])} = "balanced"
                opts.AboveThresholdOnly (1,1) logical = true
                opts.BaselineAmpWindow (1,2) double = [-1 0]
                opts.EdgeMs (1,1) double {mustBeNonnegative} = 1.0
                opts.Bootstrap (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                opts.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 1
                opts.SeriesKeys (:,1) string = strings(0,1)
                opts.LatencyOffset (1,1) double = NaN
            end
            guard = obj.beginStep("peaks"); %#ok<NASGU>
            obj.requireConditions();
            po = rmfield(opts,'SeriesKeys');
            po.Waves = mabr.analysis.Session.waveStruct(opts.Waves);
            lp = obj.peakLevelParam();
            if lp == ""
                obj.note('No level series: peaks are tracked down a level series, and there is none.');
                obj.Peaks = table();
                obj.StepOptions.peaks = po;
                obj.clearStepStates("peaks");
                obj.commitMessages("peaks",true);
                T = obj.Peaks;
                return
            end
            off = opts.LatencyOffset;
            if ~isfinite(off), off = obj.LatencyOffset; end
            po.UsedOffset = off;
            allS = obj.seriesKeys();
            if isempty(opts.SeriesKeys)
                tg = allS;
            else
                tg = allS(ismember(allS,opts.SeriesKeys));
            end
            parts = cell(numel(tg),1);
            p = mabr.analysis.Progress(numel(tg),'Tracking peaks',obj.Verbose,obj.ProgressFcn);
            for q = 1:numel(tg)
                parts{q} = obj.trackSeries(tg(q),po,off,[]);
                p.step();
            end
            p.close();
            New = obj.emptyPeaks();
            if ~isempty(parts), New = vertcat(New,parts{:}); end
            old = obj.Peaks;
            if ~isempty(opts.SeriesKeys) && height(old) > 0 && ismember('SeriesKey',old.Properties.VariableNames)
                P = [old(~ismember(old.SeriesKey,tg) & ismember(old.SeriesKey,allS),:); New];
            else
                P = New;
            end
            P = obj.peaksBelow(obj.orderPeaks(P),tg);
            picked = ismember(New.State,["auto","manual"]);
            obj.note('%d of %d wave picks made in %d series (latency offset %.3g ms).', ...
                sum(picked),height(New),numel(tg),off);
            obj.Peaks = P;
            obj.StepOptions.peaks = po;
            if isempty(opts.SeriesKeys), obj.clearStepStates("peaks"); end
            obj.commitMessages("peaks",isempty(opts.SeriesKeys));
            T = obj.Peaks;
        end

        % =================================================================
        %  The canonical pipeline
        % =================================================================
        function rep = analyze(obj,settings,opts)
            % Run the analysis a mabr.analysis.Settings describes (GUI and batch).
            %
            % The one place every option is mapped from the settings to a
            % step -- Window and the filter (settings.filter()) to segment,
            % the rejection rule, the permutation test with PER-CONDITION
            % seeds, the single-trial measures, the named threshold method
            % and the peak priors -- so a result made here is a function of
            % the settings and the files alone. Each step commits on its own;
            % a cancel (the progress sink throwing mabr:analysis:cancelled)
            % keeps the steps already finished and leaves the rest as they
            % were. After each step StepState.<step> records when, the
            % settings it read (settings.stepSettings(step)) and the data
            % fingerprint, which is what isStale compares.
            %
            % Curation, overrides and manual rejections are the session's own
            % and are applied by the steps (adoptEdits brings them from an
            % earlier results file); KeepCurated=false starts the threshold
            % review afresh. A session without a level parameter is analysed
            % up to the measures and reports "ok (no thresholds)".
            %
            %   settings     a mabr.analysis.Settings (default: Settings())
            %   opts.Steps   "all" (default) or a subset of Settings.Steps
            %   opts.From    re-run this step and every later one ("" = all)
            %   opts.Keys    condition subset for segment..measure; the series
            %                they belong to for thresholds and peaks
            %   opts.KeepCurated  carry curation (default true)
            %   rep  (returned) struct: Steps (string row), Seconds (per step),
            %        Status ("ok" | "ok (no thresholds)"), Messages (the rows
            %        of Messages written meanwhile)
            arguments
                obj
                settings = []
                opts.Steps (1,:) string = "all"
                opts.From (1,1) string = ""
                opts.Keys (:,1) string = strings(0,1)
                opts.KeepCurated (1,1) logical = true
            end
            s = mabr.analysis.Session.asSettings(settings);
            pr = s.problems();
            pr = pr(pr ~= "");
            if ~isempty(pr)
                error('mabr:analysis:Session:badSettings','These settings cannot be used: %s', ...
                    strjoin(reshape(pr,1,[]),'; '));
            end
            steps = mabr.analysis.Session.StepNames;
            if ~(isscalar(opts.Steps) && opts.Steps == "all")
                bad = setdiff(opts.Steps,steps);
                if ~isempty(bad)
                    error('mabr:analysis:Session:badStep','Unknown analysis step(s): %s.',strjoin(bad,', '));
                end
                steps = steps(ismember(steps,opts.Steps));
            end
            if opts.From ~= ""
                k = find(mabr.analysis.Session.StepNames == opts.From,1);
                if isempty(k)
                    error('mabr:analysis:Session:badStep','Unknown analysis step "%s".',opts.From);
                end
                steps = steps(ismember(steps,mabr.analysis.Session.StepNames(k:end)));
            end
            t0 = datetime('now');
            secs = zeros(1,numel(steps));
            keys = opts.Keys;
            sks = strings(0,1);
            for i = 1:numel(steps)
                tic0 = tic;
                st = steps(i);
                if isempty(sks) && ~isempty(keys) && ismember(st,["thresholds","peaks"])
                    sks = obj.seriesOf(keys(ismember(keys,obj.Conditions.Key)));
                    sks = unique(sks);
                end
                switch st
                    case "segment"
                        obj.segment(Window=s.Window,Filter=s.filter(), ...
                            HonorAcquisitionArtifacts=s.HonorAcquisitionArtifacts,Detrend=s.Detrend, ...
                            Processing=s.Processing,WindowedOrder=s.WindowedOrder, ...
                            PadMode=s.WindowedPadMode,PoolAcqModes=s.PoolAcqModes, ...
                            MaxSweepsPerCondition=s.MaxSweepsPerCondition, ...
                            EqualizeMode=s.EqualizeMode,Seed=s.Seed,Keys=keys);
                        obj.ResponseWindow = s.ResponseWindow;
                    case "reject"
                        obj.ResponseWindow = s.ResponseWindow;
                        obj.reject(Feature=s.RejectFeature,Method=s.RejectMethod, ...
                            Factor=s.RejectFactor,UpperOnly=s.RejectUpperOnly, ...
                            Ceiling=s.RejectCeiling,Window=s.ResponseWindow,Keep=false,Keys=keys);
                    case "detect"
                        obj.detect(Method=s.DetectMethod,NumPermutations=s.NumPermutations, ...
                            Alpha=s.Alpha,Window=s.ResponseWindow,Seed=s.Seed, ...
                            SeedMode="per-condition",Keys=keys);
                    case "measure"
                        obj.measure(ResponseWindow=s.ResponseWindow,BaselineWindow=s.BaselineWindow, ...
                            SplitHalfMode=s.SplitHalfMode,SplitHalfResamples=s.SplitHalfResamples, ...
                            SplitHalfWindow=s.SplitHalfWindow, ...
                            SplitHalfMinPerPolarity=s.SplitHalfMinPerPolarity, ...
                            NumPermutations=s.NumPermutations,Seed=s.Seed,MaxLag=s.MaxLag, ...
                            LevelDirection=s.LevelDirection,Keys=keys);
                    case "thresholds"
                        obj.estimateThresholds(Method=s.ThresholdMethod,MethodSettings=s, ...
                            LevelParam=s.LevelParam,GroupBy=s.GroupBy,Alpha=s.Alpha, ...
                            MinConsecutive=max(1,s.MinConsecutive),Convention=s.ThresholdConvention, ...
                            Interpolate=s.Interpolate,MinSweeps=s.MinSweeps, ...
                            MinPerPolarity=s.MinPerPolarity,LevelDirection=s.LevelDirection, ...
                            Extrapolate=s.Extrapolate,NearestLevel=s.NearestLevel, ...
                            CIAlpha=s.CIAlpha,CINumSamples=s.CINumSamples,Seed=s.Seed, ...
                            Bootstrap=s.ThresholdBootstrap,FlagWideCI=s.FlagWideCI, ...
                            FlagNonMonotoneTol=s.FlagNonMonotoneTol,KeepCurated=opts.KeepCurated, ...
                            SeriesKeys=sks);
                    case "peaks"
                        obj.pickPeaks(Waves=s.Waves,OctaveShift=s.PeakOctaveShift, ...
                            RefFrequency=s.PeakRefFrequency,Smooth=s.PeakSmooth, ...
                            MinSeparation=s.PeakMinSeparation,TrackEarly=s.PeakTrackEarly, ...
                            TrackLate=s.PeakTrackLate,CandidateRN=s.PeakCandidateRN, ...
                            DetectableRN=s.PeakDetectableRN,Polarity=s.PeakPolarity, ...
                            AboveThresholdOnly=s.PeaksAboveThresholdOnly, ...
                            BaselineAmpWindow=s.BaselineAmpWindow,EdgeMs=s.PeakEdgeMs, ...
                            Bootstrap=s.PeakBootstrap,Seed=s.Seed,SeriesKeys=sks, ...
                            LatencyOffset=obj.latencyOffsetFor(s));
                end
                ss = obj.StepState;
                ss.(st) = struct('At',mabr.analysis.Stats.isoTime(datetime('now')), ...
                    'Settings',s.stepSettings(st),'Fingerprint',obj.DataFingerprint);
                obj.StepState = ss;
                obj.Settings  = s;
                secs(i) = toc(tic0);
            end
            status = "ok";
            if height(obj.Thresholds) == 0, status = "ok (no thresholds)"; end
            M = obj.Messages;
            rep = struct('Steps',steps,'Seconds',secs,'Status',status, ...
                'Messages',M(M.Time >= t0 - seconds(1),:));
        end

        function [tf,D] = isStale(obj,settings)
            % Whether the results are out of date for these settings or files.
            %
            % A step is current when its recorded settings (StepState) equal
            % settings.stepSettings(step) field for field (isequaln); a step
            % never run, or run by a direct call that recorded no state, is
            % listed with Field "(not run)". The data are current when the
            % folders' files still fingerprint as they did when segment ran
            % (sizes and modification times of every .abr, and the files
            % excluded) -- read from disk when the folders are there, so a
            % results-only session can tell too.
            %
            %   settings  a mabr.analysis.Settings (default Settings())
            %   tf        (returned) true when anything differs
            %   D         (returned) table Step, Field, Old, New (strings), one
            %             row per difference; Step "data", Field "files" for
            %             changed data
            arguments
                obj
                settings = []
            end
            s = mabr.analysis.Session.asSettings(settings);
            st = strings(0,1);  fd = st;  ov = st;  nv = st;
            for step = mabr.analysis.Session.StepNames
                cur = s.stepSettings(step);
                saved = [];
                if isfield(obj.StepState,step), saved = obj.StepState.(step); end
                if isempty(saved) || ~isstruct(saved) || ~isfield(saved,'Settings')
                    st(end+1,1) = step; fd(end+1,1) = "(not run)"; ov(end+1,1) = ""; nv(end+1,1) = ""; %#ok<AGROW>
                    continue
                end
                old = saved.Settings;
                for f = string(fieldnames(cur)).'
                    if ~isstruct(old) || ~isfield(old,f)
                        a = "(none)";
                    elseif isequaln(old.(f),cur.(f))
                        continue
                    else
                        a = mabr.analysis.Session.settingText(old.(f));
                    end
                    st(end+1,1) = step; fd(end+1,1) = f; ov(end+1,1) = a; %#ok<AGROW>
                    nv(end+1,1) = mabr.analysis.Session.settingText(cur.(f)); %#ok<AGROW>
                end
            end
            % A measure the method in force reads and these conditions lack:
            % results made before it existed. Their settings can all match,
            % and re-running only the thresholds would refuse (noMeasures).
            mc = obj.missingMeasure(s);
            if mc ~= "" && ~any(st == "measure")
                st(end+1,1) = "measure"; fd(end+1,1) = mc; ov(end+1,1) = "(not measured)";
                nv(end+1,1) = "(needed by " + s.ThresholdMethod + ")";
            end
            fpNow = obj.currentFingerprint();
            fpThen = "";
            if isfield(obj.StepState,'segment') && isstruct(obj.StepState.segment) ...
                    && isfield(obj.StepState.segment,'Fingerprint')
                fpThen = string(obj.StepState.segment.Fingerprint);
            end
            if fpThen ~= "" && fpNow ~= "" && fpThen ~= fpNow
                st(end+1,1) = "data"; fd(end+1,1) = "files"; ov(end+1,1) = fpThen; nv(end+1,1) = fpNow;
            end
            D = table(st,fd,ov,nv,'VariableNames',{'Step','Field','Old','New'});
            tf = height(D) > 0;
        end

        function c = missingMeasure(obj,settings)
            % The measure column the settings' threshold method reads that
            % the conditions do not hold, or "".
            %
            % A results file analysed before a measure existed (DTWUp, which
            % came with xcorr-dtw) records every step's settings as they are
            % now, so nothing else says its measures are incomplete: pick
            % such a method and the threshold step alone would re-run, and
            % refuse (mabr:analysis:Session:noMeasures). isStale lists the
            % column under "measure", so re-running starts there.
            %
            %   settings  a mabr.analysis.Settings (default Settings())
            %   c         (returned) 1x1 string: the column, or "" when the
            %             method needs none, it is there, or there are no
            %             conditions yet
            arguments
                obj
                settings = []
            end
            c = "";
            C = obj.Conditions;
            if ~istable(C) || height(C) == 0, return; end
            s = mabr.analysis.Session.asSettings(settings);
            try
                m = mabr.analysis.SeriesThreshold.resolve(s.ThresholdMethod,s);
            catch
                return      % an invalid method is problems()'s to report
            end
            col = mabr.analysis.Session.metricColumnOf(m.Metric);
            if m.NeedsMeasures && col ~= "" && ~ismember(col,string(C.Properties.VariableNames))
                c = col;
            end
        end

        function rep = recompute(obj,condKeys,opts)
            % The cascade after a data edit, for the conditions it touched.
            %
            % reject (the session's rejection rule again, from the rig's flags,
            % then the hand decisions) -> detect -> measure (their series) ->
            % estimateThresholds (their series) -> pickPeaks (their series),
            % each with the options it last ran with -- the settings the
            % session was analysed with, never anybody's current ones. A step
            % that has never run is skipped. Atomic: an error or cancel leaves
            % the session as it was.
            %
            %   condKeys   condition keys (keys no longer present still name
            %              their series)
            %   opts.From  first step: "reject" (default), "detect", "measure",
            %              "thresholds" or "peaks"
            %   opts.SeriesKeys  further series to re-estimate (default none)
            %   rep  (returned) struct Action "recompute", Keys, Before, After
            %        (struct p per key, Threshold/Final per series), Text, e.g.
            %        "Re-tested 8 kHz 40 dB: p 0.03 -> 0.21; threshold 35 -> 42 dB"
            arguments
                obj
                condKeys string = strings(0,1)
                opts.From (1,1) string {mustBeMember(opts.From,["reject","detect","measure","thresholds","peaks"])} = "reject"
                opts.SeriesKeys (:,1) string = strings(0,1)
            end
            condKeys = unique(reshape(condKeys,[],1),'stable');
            here = condKeys(ismember(condKeys,obj.conditionKeysOrEmpty()));
            sks = unique([obj.seriesOfKeys(condKeys); opts.SeriesKeys],'stable');
            before = obj.snapshotNumbers(here,sks);
            bk = obj.stateBackup();
            try
                obj.runCascade(here,sks,opts.From);
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            after = obj.snapshotNumbers(here,sks);
            rep = struct('Action',"recompute",'Keys',condKeys,'Before',before,'After',after, ...
                'Text',obj.changeText(before,after));
        end

        % =================================================================
        %  Persistence (part B): raw data back, edits across
        % =================================================================
        function loadRaw(obj,opts)
            % Read a results-only session's raw data again, keeping every result.
            %
            % The folders are parsed, segmented and rejected with the SAVED
            % options of those steps (StepOptions), the hand decisions are
            % applied again, and the result columns (detection, measures),
            % Thresholds, Peaks, edits, StepState and Settings are kept as they
            % were. When a condition's sweep counts differ from what was
            % saved the session warns "raw data changed since analysis"; the
            % data fingerprint then differs too, and isStale says so.
            %
            %   opts.Force  re-read even when the raw data are already here (false)
            arguments
                obj
                opts.Force (1,1) logical = false
            end
            if obj.RawAvailable && obj.HasSweeps && ~opts.Force
                return
            end
            if isempty(obj.Paths)
                error('mabr:analysis:Session:noPaths','This session does not say which folders it was read from.');
            end
            bk = obj.stateBackup();
            savedC   = obj.Conditions;
            savedSS  = obj.StepState;
            savedSO  = obj.StepOptions;
            savedSet = obj.Settings;
            savedFP  = obj.DataFingerprint;
            savedLP  = obj.LevelParam;  savedGP = obj.GroupParams;
            try
                obj.parse();
                args = obj.segmentArgs(savedSO);
                obj.segment(args{:});
                if isfield(savedSO,'reject')
                    ra = obj.rejectArgs(savedSO.reject);
                    obj.reject(ra{:},Keep=false);
                end
                C = obj.Conditions;
                changed = 0;
                if height(savedC) > 0
                    [tf,loc] = ismember(C.Key,savedC.Key);
                    keep = string(savedC.Properties.VariableNames);
                    keep = keep(~ismember(keep,[string(C.Properties.VariableNames) ...
                        mabr.analysis.Session.SweepColumns "Features"]) | ismember(keep,"Features"));
                    for v = keep
                        src = savedC.(v);
                        C.(v) = mabr.analysis.Session.blankLike(src,height(C));
                        C.(v)(tf,:) = src(loc(tf),:);
                    end
                    for v = ["nSweeps","nRejected","nClean"]
                        if ismember(v,string(savedC.Properties.VariableNames))
                            changed = changed + sum(C.(v)(tf) ~= savedC.(v)(loc(tf)));
                        end
                    end
                    changed = changed + sum(~tf) + sum(~ismember(savedC.Key,C.Key));
                    if ismember('Features',string(C.Properties.VariableNames))
                        % Features are per sweep: only those of an unchanged
                        % condition still line up.
                        for r = find(tf).'
                            if ~istable(C.Features{r}) || height(C.Features{r}) ~= numel(C.Rejected{r})
                                C.Features{r} = [];
                            end
                        end
                    end
                    C = mabr.analysis.Session.canonicalConditions(C,obj.KeyParams);
                end
                obj.Conditions  = C;
                obj.StepState   = savedSS;
                obj.StepOptions = savedSO;
                obj.Settings    = savedSet;
                obj.LevelParam  = savedLP;
                obj.GroupParams = savedGP;
                if changed > 0
                    obj.warn('Raw data changed since analysis: %d condition count(s) differ from the results.',changed);
                end
                if savedFP ~= "" && obj.DataFingerprint ~= savedFP
                    obj.warn('The files changed since these results were made (data fingerprint %s, was %s).', ...
                        obj.DataFingerprint,savedFP);
                end
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
        end

        function rep = adoptEdits(obj,E)
            % Take the edits of a results file -- or of a plain struct of edit tables.
            %
            % What is copied: ManualRejections (applied by FileId and
            % SweepIndex -- never by a column index, which a re-segmentation
            % moves), DetectionOverrides and PeakOverrides (by condition key),
            % Exclude (Summary.Exclude, or a field Exclude), the threshold
            % curation of Thresholds (Key and any of Decision, ManualValue,
            % ManualKind, Note, ReviewedBy, ReviewedAt, ReviewedValue,
            % ReviewedMethod; a v1 table's Curated/IsCurated read as the
            % decisions setThreshold would make), CurationArchive, and EditLog.
            % Any of them may be missing. Curation goes where the next
            % estimateThresholds carries it from (CurationArchive, by key), and
            % onto the current Thresholds rows with the same keys at once.
            % Nothing is recomputed here: the next analyze() applies it all --
            % with per-condition seeds, so analysing the same files with the
            % same settings after adoptEdits gives the original results bit for
            % bit. This is what Batch does with an existing results file and
            % what a replication script (mabr.analysis.ScriptWriter) does with
            % its literal tables.
            %
            %   E    a results struct (v1 or v2), or a struct holding only edit
            %        tables
            %   rep  (returned) struct Action "adoptEdits", Keys, Before, After
            %        (counts), Text
            arguments
                obj
                E (1,1) struct
            end
            n0 = obj.editCounts();
            MR = mabr.analysis.Session.tableField(E,'ManualRejections',mabr.analysis.Session.emptyManualRejections());
            DO = mabr.analysis.Session.tableField(E,'DetectionOverrides',mabr.analysis.Session.emptyDetectionOverrides());
            PO = mabr.analysis.Session.tableField(E,'PeakOverrides',mabr.analysis.Session.emptyPeakOverrides());
            CA = mabr.analysis.Session.tableField(E,'CurationArchive',mabr.analysis.Session.emptyCurationArchive());
            EL = mabr.analysis.Session.tableField(E,'EditLog',mabr.analysis.Session.emptyEditLog());
            cur = mabr.analysis.Session.curationOf(mabr.analysis.Session.tableField(E,'Thresholds',table()));
            % Only rows that hold a curation: an unreviewed row has nothing to
            % carry, and archived it would linger once its series is gone.
            cur = cur(cur.Decision ~= "" | cur.Note ~= "" | cur.ReviewedBy ~= "",:);
            ex = [];
            if isfield(E,'Exclude')
                ex = E.Exclude;
            elseif isfield(E,'Summary') && isstruct(E.Summary) && isfield(E.Summary,'Exclude')
                ex = E.Summary.Exclude;
            end

            obj.ManualRejections   = mabr.analysis.Session.mergeByKey(obj.ManualRejections,MR,["FileId","SweepIndex"]);
            obj.DetectionOverrides = mabr.analysis.Session.mergeByKey(obj.DetectionOverrides,DO,"Key");
            obj.PeakOverrides      = mabr.analysis.Session.mergeByKey(obj.PeakOverrides,PO,["Key","Wave","Kind"]);
            arch = mabr.analysis.Session.mergeByKey(obj.CurationArchive,CA,"Key");
            arch = mabr.analysis.Session.mergeByKey(arch,cur,"Key");
            obj.CurationArchive = arch;
            if height(EL) > 0
                L = [EL; obj.EditLog];
                [~,u] = unique(string(L.Time,'yyyy-MM-dd HH:mm:ss.SSS') + "|" + L.Action + "|" + L.Key + "|" + L.Old + "|" + L.New,'stable');
                obj.EditLog = L(sort(u),:);
            end
            if height(obj.Thresholds) > 0 && ismember('Decision',obj.Thresholds.Properties.VariableNames) && height(cur) > 0
                T = mabr.analysis.Session.applyCuration(obj.Thresholds,cur);
                method = "";
                if height(T) > 0, method = T.Method(1); end
                obj.Thresholds = mabr.analysis.Session.refreshCuration(T,method,true(height(T),1));
            end
            if ~isempty(ex)
                ex = reshape(string(ex),[],1);
                ex = unique(ex(~ismissing(ex) & ex ~= ""),'stable');
                if ~isequal(sort(ex),sort(obj.Exclude))
                    obj.Exclude = ex;
                    if ~isempty(obj.Records)
                        obj.reinclude();
                    end
                    if height(obj.Conditions) > 0
                        obj.warn('The file exclusions changed: segment() again to apply them.');
                        obj.clearStepStates("segment");
                    end
                end
            end
            if height(obj.Conditions) > 0 && ismember('Detected',obj.Conditions.Properties.VariableNames)
                obj.Conditions.Detected = obj.applyDetectionOverrides(obj.Conditions);
            end
            n1 = obj.editCounts();
            txt = sprintf(['Adopted edits: %d manual rejection(s), %d detection override(s), ' ...
                '%d peak override(s), %d curated threshold(s), %d file(s) excluded.'], ...
                height(MR),height(DO),height(PO),height(cur),numel(obj.Exclude));
            obj.appendMessage("info",txt,"edit");
            rep = struct('Action',"adoptEdits",'Keys',strings(0,1),'Before',n0,'After',n1,'Text',string(txt));
        end

        % =================================================================
        %  Edits -- by key; each appends EditLog and returns a report
        % =================================================================
        function rep = acceptFit(obj,seriesKey)
            % Accept the method's threshold for one series (Decision "accepted").
            %
            % ReviewedBy/At/Value/Method record who accepted which value under
            % which method, so a later re-fit that moves can be told apart.
            arguments
                obj
                seriesKey (1,1) string
            end
            rep = obj.decide(seriesKey,"accepted",NaN,"","acceptFit",missing);
        end

        function rep = setDecision(obj,seriesKey,decision,opts)
            % Curate one series' threshold.
            %
            %   seriesKey  the series (Thresholds.Key)
            %   decision   "accepted", "manual", "noresponse", "allrespond",
            %              "excluded", or "" (clear the decision, keeping the note)
            %   opts.Value  the manual value (ManualKind "value") or the lowest
            %               level WITH a response (ManualKind "level")
            %   opts.Kind   "level" (default) or "value"
            %   opts.Note   a note to store with it (missing = leave the note)
            %   rep  (returned) report struct Action, Keys, Before, After, Text
            arguments
                obj
                seriesKey (1,1) string
                decision (1,1) string {mustBeMember(decision,["","accepted","manual","noresponse","allrespond","excluded"])}
                opts.Value (1,1) double = NaN
                opts.Kind (1,1) string {mustBeMember(opts.Kind,["level","value"])} = "level"
                opts.Note = missing
            end
            if decision == "manual" && ~isfinite(opts.Value)
                error('mabr:analysis:Session:badDecision','A manual threshold needs a finite Value.');
            end
            kind = "";
            if decision == "manual", kind = opts.Kind; end
            rep = obj.decide(seriesKey,decision,opts.Value,kind,"setDecision",opts.Note);
        end

        function rep = clearDecision(obj,seriesKey)
            % Remove a series' decision and its review record (the note stays).
            arguments
                obj
                seriesKey (1,1) string
            end
            rep = obj.decide(seriesKey,"",NaN,"","clearDecision",missing);
        end

        function rep = setThresholdNote(obj,seriesKey,text)
            % Store a free-text note with one series' threshold.
            arguments
                obj
                seriesKey (1,1) string
                text {mustBeTextScalar}
            end
            r = obj.requireSeries(seriesKey);
            old = obj.Thresholds.Note(r);
            obj.Thresholds.Note(r) = string(text);
            obj.logEdit("setThresholdNote",seriesKey,old,string(text));
            rep = obj.report("setThresholdNote",seriesKey,old,string(text), ...
                "Note on " + obj.seriesLabel(seriesKey) + ": " + string(text));
        end

        function rep = setDetectionOverride(obj,condKey,value)
            % A hand verdict on one condition: 1 response, 0 none, NaN automatic.
            %
            % The series is re-estimated at once (and its peaks' BelowThreshold
            % follows the new Final); nothing is re-tested.
            arguments
                obj
                condKey (1,1) string
                value (1,1) double
            end
            if ~(isnan(value) || value == 0 || value == 1)
                error('mabr:analysis:Session:badOverride','A detection override is 1, 0 or NaN.');
            end
            obj.rowOf(condKey);
            O = obj.DetectionOverrides;
            k = find(O.Key == condKey,1);
            old = NaN;
            if ~isempty(k), old = O.Value(k); O(k,:) = []; end
            if ~isnan(value)
                O(end+1,:) = {condKey,value,datetime('now'),obj.Analyst};
            end
            bk = obj.stateBackup();
            try
                obj.DetectionOverrides = O;
                if ismember('Detected',obj.Conditions.Properties.VariableNames)
                    obj.Conditions.Detected = obj.applyDetectionOverrides(obj.Conditions);
                end
                r = obj.recompute(condKey,From="thresholds");
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            obj.logEdit("setDetectionOverride",condKey,old,value);
            what = ["no response","response","automatic"];
            w = what(3);
            if ~isnan(value), w = what(value + 1); end
            rep = obj.report("setDetectionOverride",condKey,old,value, ...
                obj.conditionLabel(condKey) + " set to " + w + ". " + r.Text);
        end

        function rep = setSweepsRejected(obj,condKey,cols,tf)
            % Reject (tf true) or restore (false) sweeps of one condition by hand.
            %
            % cols index Conditions.Sweeps{row} (every sweep of the condition,
            % flagged or not). The decision is stored by (FileId, SweepIndex)
            % in ManualRejections -- a hand decision wins over the rig's and the
            % criterion's, both ways -- and the condition is re-tested, its
            % series re-measured, re-estimated and re-tracked (recompute).
            %
            %   rep  (returned) report struct; Text is recompute's
            arguments
                obj
                condKey (1,1) string
                cols double {mustBeInteger,mustBePositive}
                tf (1,1) logical
            end
            obj.requireSweeps();
            r = obj.rowOf(condKey);
            n = numel(obj.Conditions.Rejected{r});
            cols = unique(cols(:)).';
            if any(cols > n)
                error('mabr:analysis:Session:noSuchSweep','Condition %s has %d sweeps.',condKey,n);
            end
            fid = obj.Files.FileId(obj.Conditions.SweepFile{r}(cols));
            six = reshape(obj.Conditions.SweepIndex{r}(cols),[],1);
            bk = obj.stateBackup();
            try
                obj.ManualRejections = mabr.analysis.Session.upsertManual(obj.ManualRejections, ...
                    fid(:),six,tf,obj.Analyst);
                rc = obj.recompute(condKey);
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            if tf, verb = "rejected"; else, verb = "restored"; end
            obj.logEdit("setSweepsRejected",condKey,cols,verb);
            rep = obj.report("setSweepsRejected",condKey,rc.Before,rc.After, ...
                sprintf('%d sweep(s) %s in %s. %s',numel(cols),verb,obj.conditionLabel(condKey),rc.Text));
        end

        function rep = clearManualRejections(obj,condKeys)
            % Drop the hand decisions on these conditions' sweeps ([] = all) and recompute.
            arguments
                obj
                condKeys string = strings(0,1)
            end
            MR = obj.ManualRejections;
            if isempty(condKeys)
                drop = true(height(MR),1);
                keys = obj.conditionKeysOrEmpty();
            else
                keys = unique(reshape(condKeys,[],1),'stable');
                rr = obj.rowOf(keys);
                sk = strings(0,1);
                for r = reshape(rr,1,[])
                    sk = [sk; obj.Files.FileId(obj.Conditions.SweepFile{r}(:)) + "#" + ...
                        string(reshape(obj.Conditions.SweepIndex{r},[],1))]; %#ok<AGROW>
                end
                drop = ismember(MR.FileId + "#" + string(MR.SweepIndex),sk);
            end
            n = sum(drop);
            bk = obj.stateBackup();
            try
                obj.ManualRejections = MR(~drop,:);
                if n > 0 && obj.HasSweeps
                    rc = obj.recompute(keys);
                    txt = rc.Text;
                else
                    txt = "";
                end
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            obj.logEdit("clearManualRejections",strjoin(keys,","),n,0);
            rep = obj.report("clearManualRejections",keys,n,0, ...
                strtrim(sprintf('%d manual rejection(s) cleared. %s',n,txt)));
        end

        function rep = setExcluded(obj,fileIds,tf)
            % Leave files out of the session (tf true) or take them back (false).
            %
            % fileIds are Files.FileId ("<folder>/<file>"). Exclude is updated,
            % the inclusion rules are applied again (a file taken back may be a
            % duplicate, or Test Mode, or at another rate, and stays out with
            % that reason), the conditions those files belong to -- before and
            % after -- are segmented again, and the cascade (recompute) runs
            % for them. The data fingerprint includes the exclusions, so the
            % step states are re-stamped with the new one: the results are
            % current for it. Needs the raw data (loadRaw).
            %
            %   rep  (returned) report struct; Keys are the conditions touched
            arguments
                obj
                fileIds string
                tf (1,1) logical = true
            end
            obj.requireRaw();
            fileIds = unique(reshape(fileIds,[],1),'stable');
            bad = setdiff(fileIds,obj.Files.FileId);
            if ~isempty(bad)
                error('mabr:analysis:Session:unknownFile','No file "%s" in %s.',bad(1),obj.Name);
            end
            old = obj.Exclude;
            bk = obj.stateBackup();
            try
                [keys,before,after] = obj.excludeFiles(fileIds,tf,true);
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            if tf, verb = "excluded"; else, verb = "included again"; end
            obj.logEdit("setExcluded",strjoin(fileIds,","),old,obj.Exclude);
            rep = obj.report("setExcluded",keys,before,after, ...
                sprintf('%d file(s) %s; %d condition(s) re-segmented. %s',numel(fileIds),verb, ...
                numel(keys),obj.changeText(before,after)));
        end

        function rep = setPeak(obj,condKey,wave,kind,latencyMs,opts)
            % Place one wave's peak ("P") or trough ("N") by hand.
            %
            % latencyMs is RAW (re the onset, as PeakLatency). With Snap the
            % pick moves to the nearest local maximum (P) or minimum (N) of the
            % condition's mean within SnapWindow ms, refined parabolically. The
            % pick is stored in PeakOverrides and that level is re-derived:
            % its amplitudes, and its automatic troughs between the (moved)
            % peaks. The levels below are NOT re-guessed (retrackSeries does
            % that), so a correction never moves a pick nobody asked to move.
            arguments
                obj
                condKey (1,1) string
                wave (1,1) string
                kind (1,1) string {mustBeMember(kind,["P","N"])}
                latencyMs (1,1) double {mustBeFinite}
                opts.Snap (1,1) logical = true
                opts.SnapWindow (1,1) double {mustBeNonnegative} = 0.25
            end
            obj.rowOf(condKey);
            lat = latencyMs;
            if opts.Snap
                lat = obj.snapLatency(condKey,kind,latencyMs,opts.SnapWindow);
            end
            PO = obj.PeakOverrides;
            k = find(PO.Key == condKey & PO.Wave == wave & PO.Kind == kind);
            old = NaN;
            if ~isempty(k), old = PO.Latency(k(1)); PO(k,:) = []; end
            if kind == "P"
                PO(PO.Key == condKey & PO.Wave == wave & PO.State == "absent",:) = [];
            end
            PO(end+1,:) = {condKey,wave,kind,"manual",lat,datetime('now'),obj.Analyst};
            obj.applyPeakEdit(PO,condKey,"setPeak",wave + " " + kind,old,lat);
            nm = "peak"; if kind == "N", nm = "trough"; end
            rep = obj.report("setPeak",condKey,old,lat, ...
                sprintf('%s %s of %s at %.3f ms',wave,nm,obj.conditionLabel(condKey),lat));
        end

        function rep = setPeakAbsent(obj,condKey,wave,tf,opts)
            % Mark a wave absent at a level (tf true) or present again (false).
            %
            %   opts.Below  also every lower level of the series (default false)
            arguments
                obj
                condKey (1,1) string
                wave (1,1) string
                tf (1,1) logical
                opts.Below (1,1) logical = false
            end
            keys = condKey;
            if opts.Below
                sk = obj.seriesOf(condKey);
                ks = obj.seriesConditions(sk);
                lp = obj.peakLevelParam();
                if lp ~= ""
                    lv = obj.Conditions.(lp)(obj.rowOf(ks));
                    l0 = obj.Conditions.(lp)(obj.rowOf(condKey));
                    sg = obj.loudnessSign(lp);
                    keys = ks(sg*lv <= sg*l0 | ks == condKey);
                end
            end
            PO = obj.PeakOverrides;
            hit = ismember(PO.Key,keys) & PO.Wave == wave & PO.Kind == "P";
            PO(hit,:) = [];
            if tf
                for k = reshape(keys,1,[])
                    PO(end+1,:) = {k,wave,"P","absent",NaN,datetime('now'),obj.Analyst}; %#ok<AGROW>
                end
            end
            obj.applyPeakEdit(PO,keys,"setPeakAbsent",wave,~tf,tf);
            if tf, w = "absent"; else, w = "present"; end
            rep = obj.report("setPeakAbsent",keys,~tf,tf, ...
                sprintf('Wave %s %s at %d level(s) of %s',wave,w,numel(keys),obj.seriesLabel(obj.seriesOf(condKey))));
        end

        function rep = clearPeak(obj,condKey,wave,kind)
            % Remove a hand pick (or absence): back to the automatic pick.
            arguments
                obj
                condKey (1,1) string
                wave (1,1) string
                kind (1,1) string {mustBeMember(kind,["P","N"])} = "P"
            end
            PO = obj.PeakOverrides;
            hit = PO.Key == condKey & PO.Wave == wave & PO.Kind == kind;
            old = NaN;
            if any(hit), old = PO.Latency(find(hit,1)); end
            PO(hit,:) = [];
            obj.applyPeakEdit(PO,condKey,"clearPeak",wave + " " + kind,old,NaN);
            rep = obj.report("clearPeak",condKey,old,NaN, ...
                sprintf('%s back to the automatic pick at %s',wave,obj.conditionLabel(condKey)));
        end

        function rep = clearPeakOverrides(obj,seriesKey)
            % Remove every peak edit of a series ("" = of every series) and re-track it.
            arguments
                obj
                seriesKey (1,1) string = ""
            end
            PO = obj.PeakOverrides;
            if seriesKey == ""
                hit = true(height(PO),1);
                sks = obj.seriesKeys();
            else
                hit = ismember(PO.Key,obj.seriesConditions(seriesKey));
                sks = seriesKey;
            end
            n = sum(hit);
            bk = obj.stateBackup();
            try
                obj.PeakOverrides = PO(~hit,:);
                if height(obj.Peaks) > 0
                    args = obj.peakArgs();
                    obj.pickPeaks(args{:},SeriesKeys=sks);
                end
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            obj.logEdit("clearPeakOverrides",seriesKey,n,0);
            rep = obj.report("clearPeakOverrides",seriesKey,n,0,sprintf('%d peak edit(s) cleared',n));
        end

        function rep = retrackSeries(obj,seriesKey,wave,fromLevel,opts)
            % Re-track a wave ("" = every wave) down a series from fromLevel.
            %
            % The picks at fromLevel and above are taken as they stand (as
            % anchors), and every level below is tracked again from them --
            % the "re-guess the rest" a correction at a mid level asks for.
            % Overwrite also drops the manual picks strictly below fromLevel
            % first; otherwise they are kept, and tracked through.
            %
            %   opts.Overwrite  drop manual picks below fromLevel (default false)
            arguments
                obj
                seriesKey (1,1) string
                wave (1,1) string = ""
                fromLevel (1,1) double = Inf
                opts.Overwrite (1,1) logical = false
            end
            if height(obj.Peaks) == 0
                error('mabr:analysis:Session:noPeaks','No peaks. Call pickPeaks() first.');
            end
            ks = obj.seriesConditions(seriesKey);
            if isempty(ks)
                error('mabr:analysis:Session:unknownKey','No series "%s" in %s.',seriesKey,obj.Name);
            end
            lp = obj.peakLevelParam();
            lv = obj.Conditions.(lp)(obj.rowOf(ks));
            sg = obj.loudnessSign(lp);           % "below" = quieter
            if ~isfinite(fromLevel), fromLevel = sg*max(sg*lv); end
            below = ks(sg*lv < sg*fromLevel);
            PO = obj.PeakOverrides;
            nDrop = 0;
            if opts.Overwrite
                hit = ismember(PO.Key,below) & PO.State == "manual" & (wave == "" | PO.Wave == wave);
                nDrop = sum(hit);
                PO(hit,:) = [];
            end
            % The current picks at and above fromLevel, as anchors.
            P = obj.Peaks(obj.Peaks.SeriesKey == seriesKey & sg*obj.Peaks.Level >= sg*fromLevel,:);
            A = mabr.analysis.Session.anchorsFromPicks(P);
            bk = obj.stateBackup();
            try
                obj.PeakOverrides = PO;
                args = obj.peakArgs();
                po = mabr.analysis.Session.argsStruct(args);
                off = obj.peakOffset(po);
                New = obj.trackSeries(seriesKey,po,off,A);
                repl = sg*New.Level < sg*fromLevel & (wave == "" | New.Wave == wave);
                old = obj.Peaks;
                drop = old.SeriesKey == seriesKey & sg*old.Level < sg*fromLevel & (wave == "" | old.Wave == wave);
                Pn = obj.orderPeaks([old(~drop,:); New(repl,:)]);
                obj.Peaks = obj.peaksBelow(Pn,seriesKey);
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            w = wave; if w == "", w = "every wave"; end
            obj.logEdit("retrackSeries",seriesKey,fromLevel,w);
            rep = obj.report("retrackSeries",seriesKey,fromLevel,w, ...
                sprintf('%s re-tracked below %g in %s%s',w,fromLevel,obj.seriesLabel(seriesKey), ...
                ifelse(nDrop > 0,sprintf(' (%d manual pick(s) dropped)',nDrop),'')));
        end

        function W = picksAsWindows(obj,seriesKey)
            % This series' picks at its loudest level, as wave windows.
            %
            % For each wave the series picked at its loudest level, Expected is
            % that pick taken back to the reference frequency -- the octave
            % shift Peaks.wavesFor added is subtracted; windows and picks are
            % both in the recording's time, so the latency offset is not --
            % and TMin/TMax = Expected -/+ 0.5 ms; the waves
            % it did not pick keep their windows. Stimulus is the series'
            % stimulus, so the windows apply to it alone when added to a wave
            % table. Handing these back as Settings.Waves makes the next
            % analysis search where this series' waves actually were.
            %
            %   W  (returned) wave struct array (Name, Enabled, TMin, TMax,
            %      Expected, LatencyShift, Stimulus)
            arguments
                obj
                seriesKey (1,1) string
            end
            if height(obj.Peaks) == 0
                error('mabr:analysis:Session:noPeaks','No peaks. Call pickPeaks() first.');
            end
            po = mabr.analysis.Session.argsStruct(obj.peakArgs());
            ks = obj.seriesConditions(seriesKey);
            if isempty(ks)
                error('mabr:analysis:Session:unknownKey','No series "%s" in %s.',seriesKey,obj.Name);
            end
            r = obj.rowOf(ks(1));
            [stim,freq] = obj.stimulusOf(r);
            W = mabr.analysis.Peaks.wavesFor(po.Waves,stim,NaN);
            shift = 0;
            if isfinite(freq) && freq > 0, shift = po.OctaveShift*log2(po.RefFrequency/freq); end
            P = obj.Peaks(obj.Peaks.SeriesKey == seriesKey,:);
            sg = obj.loudnessSign(obj.peakLevelParam());
            top = sg*max(sg*P.Level);           % the loudest level
            P = P(P.Level == top & ismember(P.State,["auto","manual"]) & isfinite(P.PeakLatency),:);
            for k = 1:numel(W)
                j = find(P.Wave == W(k).Name,1);
                if isempty(j), continue; end
                e = P.PeakLatency(j) - shift;
                W(k).Expected = e;
                W(k).TMin = e - 0.5;
                W(k).TMax = e + 0.5;
            end
            for k = 1:numel(W), W(k).Stimulus = stim; end
        end

        function snap = editSnapshot(obj)
            % Every edit of this session, as one struct (undo/redo).
            %
            %   snap  (returned) struct: ManualRejections, DetectionOverrides,
            %         PeakOverrides, Exclude, CurationArchive, Curation (Key
            %         and the curation columns of Thresholds) and Peaks (so a
            %         peak edit is undone exactly, without re-tracking)
            snap = struct();
            snap.ManualRejections   = obj.ManualRejections;
            snap.DetectionOverrides = obj.DetectionOverrides;
            snap.PeakOverrides      = obj.PeakOverrides;
            snap.Exclude            = obj.Exclude;
            snap.CurationArchive    = obj.CurationArchive;
            snap.Curation           = mabr.analysis.Session.curationOf(obj.Thresholds);
            snap.Peaks              = obj.Peaks;
        end

        function rep = restoreEdits(obj,snap)
            % Put a snapshot's edits back, recomputing what they change (undo/redo).
            %
            % Sweep decisions and file exclusions that differ re-segment and
            % recompute the conditions they touch; detection overrides re-fit
            % their series; curation and peak edits are restored as they were.
            % Atomic.
            arguments
                obj
                snap (1,1) struct
            end
            bk = obj.stateBackup();
            try
                keys = strings(0,1);
                sks  = strings(0,1);
                % File exclusions.
                if isfield(snap,'Exclude')
                    ex = reshape(string(snap.Exclude),[],1);
                    if ~isequal(sort(ex),sort(obj.Exclude))
                        if isempty(obj.Records)
                            % No raw records to apply them to: they wait in
                            % Exclude for the next parse (loadRaw).
                            obj.Exclude = ex;
                        else
                            add = setdiff(ex,obj.Exclude);  drop = setdiff(obj.Exclude,ex);
                            if ~isempty(add),  keys = [keys; obj.excludeFiles(add,true,false)]; end
                            if ~isempty(drop), keys = [keys; obj.excludeFiles(drop,false,false)]; end
                        end
                    end
                end
                % Sweep decisions.
                if isfield(snap,'ManualRejections') && ~isequaln(snap.ManualRejections,obj.ManualRejections)
                    keys = [keys; obj.keysOfSweeps(snap.ManualRejections,obj.ManualRejections)];
                    obj.ManualRejections = snap.ManualRejections;
                end
                % Detection verdicts.
                if isfield(snap,'DetectionOverrides') && ~isequaln(snap.DetectionOverrides,obj.DetectionOverrides)
                    a = snap.DetectionOverrides;  b = obj.DetectionOverrides;
                    ka = a.Key + "=" + string(a.Value);  kb = b.Key + "=" + string(b.Value);
                    ch = unique([a.Key(~ismember(ka,kb)); b.Key(~ismember(kb,ka))]);
                    obj.DetectionOverrides = a;
                    if ismember('Detected',obj.Conditions.Properties.VariableNames)
                        obj.Conditions.Detected = obj.applyDetectionOverrides(obj.Conditions);
                    end
                    sks = [sks; obj.seriesOfKeys(ch)];
                end
                if isfield(snap,'PeakOverrides'), obj.PeakOverrides = snap.PeakOverrides; end
                keys = unique(keys);
                if ~isempty(keys) && obj.HasSweeps
                    obj.runCascade(keys(ismember(keys,obj.conditionKeysOrEmpty())), ...
                        unique([obj.seriesOfKeys(keys); sks]),"reject");
                elseif ~isempty(sks)
                    obj.runCascade(strings(0,1),unique(sks),"thresholds");
                end
                % Curation and peaks, exactly as they were.
                if isfield(snap,'CurationArchive'), obj.CurationArchive = snap.CurationArchive; end
                if isfield(snap,'Curation') && height(obj.Thresholds) > 0 && ...
                        ismember('Decision',obj.Thresholds.Properties.VariableNames)
                    T = mabr.analysis.Session.clearCuration(obj.Thresholds);
                    T = mabr.analysis.Session.applyCuration(T,snap.Curation);
                    method = "";
                    if height(T) > 0, method = T.Method(1); end
                    obj.Thresholds = mabr.analysis.Session.refreshCuration(T,method,true(height(T),1));
                end
                if isfield(snap,'Peaks') && istable(snap.Peaks)
                    obj.Peaks = obj.peaksBelow(snap.Peaks,strings(0,1));
                end
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            obj.appendMessage("info","Edits restored.","edit");
            rep = struct('Action',"restoreEdits",'Keys',keys,'Before',[],'After',[],'Text',"Edits restored");
        end

        % =================================================================
        %  Display
        % =================================================================
        function s = describe(obj)
            % One-line summary of the session. s: (returned) 1x1 string.
            nInc = 0;
            if ismember('Include',obj.Files.Properties.VariableNames), nInc = sum(obj.Files.Include); end
            s = sprintf('%s  (%s)  %d files (%d included), %d conditions, %g Hz', ...
                obj.Name, obj.Subject, obj.NumFiles, nInc, obj.NumConditions, obj.SampleRate);
            if numel(obj.Paths) > 1, s = [s sprintf('  [pool of %d folders]',numel(obj.Paths))]; end
            if obj.TestMode, s = [s '  [TEST MODE]']; end
            if ~obj.HasSweeps && obj.NumConditions > 0, s = [s '  [results only]']; end
            s = string(s);
        end

        function disp(obj)
            % Multi-line console summary. No inputs beyond obj, no return value.
            if ~isscalar(obj), builtin('disp',obj); return; end
            fprintf('  mabr.analysis.Session\n');
            fprintf('    %s\n',obj.describe());
            for k = 1:numel(obj.Paths)
                fprintf('    path       : %s\n',obj.Paths(k));
            end
            if ~isnat(obj.Date), fprintf('    date       : %s\n',string(obj.Date)); end
            fprintf('    parameters : %s\n',strjoin(obj.ParamNames,', '));
            if ~isempty(obj.AcqModes)
                fprintf('    acq modes  : %s\n',strjoin(obj.AcqModes,', '));
            end
            if obj.Units ~= ""
                fprintf('    units      : %s, levels in %s\n',obj.Units,obj.LevelUnit);
            end
            if ~isempty(obj.Time)
                fprintf('    window     : [%g %g] ms (%d samples), response [%g %g] ms\n', ...
                    obj.Window,numel(obj.Time),obj.ResponseWindow);
            end
            fprintf('    filter     : %s\n',obj.Filter.describe());
            if obj.NumConditions > 0
                fprintf('    sweeps     : %d (%d rejected)\n', ...
                    sum(obj.Conditions.nSweeps),sum(obj.Conditions.nRejected));
            end
            if height(obj.Thresholds) > 0
                fprintf('    thresholds : %d estimated\n',height(obj.Thresholds));
            end
        end

        % --- dependent ----------------------------------------------------
        % NumFiles/NumConditions: row counts of Files/Conditions.
        % ResponseRows: logical mask into Time selecting ResponseWindow.
        function set.UnitOverride(obj,o)
            % A complete override struct, whoever assigns it (NaN = none).
            obj.UnitOverride = mabr.analysis.Session.checkOverride(o);
        end

        function n = get.NumFiles(obj),      n = height(obj.Files); end
        function o = get.LatencyOffset(obj), o = obj.latencyOffsetFor(obj.Settings); end
        function n = get.NumConditions(obj), n = height(obj.Conditions); end
        function m = get.ResponseRows(obj)
            if isempty(obj.Time), m = false(0,1); return; end
            m = mabr.analysis.Artifacts.windowMask(obj.Time,obj.ResponseWindow);
        end
    end

    % =====================================================================
    %  Static
    % =====================================================================
    methods (Static)
        function paths = find(rootPath,opts)
            % Every folder under rootPath holding .abr files.
            %
            %   rootPath      folder to search recursively
            %   opts.Pattern  dir() pattern to match (default "*.abr")
            %   paths  (returned) [n x 1] string of unique folder paths
            %          (empty string.empty(0,1) when none found)
            arguments
                rootPath (1,1) string
                opts.Pattern (1,1) string = "*.abr"
            end
            d = dir(fullfile(char(rootPath),'**',char(opts.Pattern)));
            if isempty(d), paths = string.empty(0,1); return; end
            paths = unique(string({d.folder}).');
            paths(paths == "") = [];
        end

        function obj = fromResults(src,opts)
            % Rebuild a Session from a results file or struct (v1 or v2).
            %
            %   src           a .mat file written by saveResults, or the struct
            %                 load() returns for one (or toStruct's)
            %   opts.Verbose  the session's Verbose (default true, as before)
            %   obj  (returned) a Session holding every result. HasSweeps is true
            %        only when the file saved the sweeps; without them the
            %        per-sweep columns of Conditions are rebuilt from SweepInfo,
            %        the sweeps are empty, and conditionMean reads Means. Every
            %        Fit gets its Predict back (mabr.analysis.Threshold.predictor).
            %        A results-only session cannot segment, reject or detect
            %        until loadRaw() reads its files again.
            arguments
                src
                opts.Verbose (1,1) logical = true
            end
            if isstruct(src)
                R = src;
            else
                R = load(char(string(src)),'-mat');
            end
            obj = mabr.analysis.Session("",Parse=false,Verbose=opts.Verbose);
            fileVersion = 1;
            if isfield(R,'Version') && isnumeric(R.Version) && isscalar(R.Version), fileVersion = R.Version; end
            if fileVersion >= 2 && isfield(R,'Summary')
                obj.loadV2(R);
            else
                obj.loadV1(R);
            end
            if fileVersion > mabr.analysis.Session.Version
                % After the load, which brings the file's own Messages.
                obj.warn(['These results were written by a newer MABR (format %g; this one reads %d); ' ...
                    'only the fields it knows were loaded.'],fileVersion,mabr.analysis.Session.Version);
            end
        end

        function fp = fingerprintOf(fileIds,bytes,modified,exclude)
            % The data fingerprint of a session's files.
            %
            %   fp = fingerprintOf(fileIds,bytes,modified,exclude)
            %
            %   fileIds   "<folder name>/<file name>" of EVERY .abr in the
            %             session's folders (included or not)
            %   bytes     their sizes
            %   modified  their modification times (datetime, or datenum)
            %   exclude   the FileIds the user excluded (default none)
            %   fp        (returned) 1x1 string, 8 hex digits:
            %             Stats.hex8(join(sort(FileId|Bytes|isoTime(Modified)),
            %             newline) + newline + "exclude:" + join(sort(exclude),","))
            %
            %   Public and static so mabr.analysis.Project can compute the same
            %   value from Catalog rows without opening a session. The Include
            %   rules are functions of the files' contents, which size and time
            %   already fingerprint.
            arguments
                fileIds string
                bytes {mustBeNumeric}
                modified
                exclude string = strings(0,1)
            end
            fileIds = reshape(fileIds,[],1);
            bytes   = double(reshape(bytes,[],1));
            if isnumeric(modified)
                m  = NaT(numel(modified),1);
                ok = isfinite(modified(:));
                if any(ok), m(ok) = datetime(modified(ok),'ConvertFrom','datenum'); end
                modified = m;
            end
            modified = reshape(modified,[],1);
            if numel(bytes) ~= numel(fileIds) || numel(modified) ~= numel(fileIds)
                error('mabr:analysis:Session:fingerprintSize', ...
                    'fileIds, bytes and modified must have one entry per file.');
            end
            t = string(mabr.analysis.Stats.isoTime(modified));
            body = "";
            if ~isempty(fileIds)
                body = join(sort(fileIds + "|" + string(bytes) + "|" + reshape(t,[],1)),newline);
            end
            ex = reshape(exclude,[],1);
            ex = ex(~ismissing(ex) & ex ~= "");
            exText = "";
            if ~isempty(ex), exText = join(sort(ex),","); end
            fp = mabr.analysis.Stats.hex8(body + newline + "exclude:" + exText);
        end

        function sec = estimateSeconds(settings,fromStep,nFiles,nConditions,nSeries)
            % How long analyze(settings,From=fromStep) will take, roughly (s).
            %
            % A heuristic for button labels ("Analyse (~40 s)"), per step:
            % segment 0.03 s per file; reject 0.005 s per condition; detect
            % NumPermutations/1000 x (0.3 for TFCE, 0.05 otherwise) s per
            % condition; measure (SplitHalfResamples/500 x 0.1 +
            % NumPermutations/1000 x 0.03) s per condition; thresholds 0.01 s
            % per series; peaks 0.02 s per series + PeakBootstrap/500 x 0.5 s
            % per condition.
            %
            %   settings     mabr.analysis.Settings (or its struct, or [])
            %   fromStep     first step run ("" = segment, i.e. all)
            %   nFiles, nConditions, nSeries   the session's sizes
            %   sec          (returned) seconds
            arguments
                settings
                fromStep (1,1) string = ""
                nFiles (1,1) double = 0
                nConditions (1,1) double = 0
                nSeries (1,1) double = 0
            end
            s = mabr.analysis.Session.asSettings(settings);
            steps = mabr.analysis.Session.StepNames;
            k = 1;
            if fromStep ~= ""
                k = find(steps == fromStep,1);
                if isempty(k)
                    error('mabr:analysis:Session:badStep','Unknown analysis step "%s".',fromStep);
                end
            end
            perm = s.NumPermutations/1000;
            if s.DetectMethod == "tfce", d = 0.3; else, d = 0.05; end
            cost = [0.03*nFiles, 0.005*nConditions, perm*d*nConditions, ...
                (s.SplitHalfResamples/500*0.1 + perm*0.03)*nConditions, 0.01*nSeries, ...
                0.02*nSeries + s.PeakBootstrap/500*0.5*nConditions];
            sec = sum(cost(k:end));
        end

        function fp = folderFingerprint(paths,exclude)
            % fingerprintOf the .abr files of these folders as they are now.
            %
            % What Batch.isCurrent compares with a results file's fingerprint:
            % one dir() per folder, no file opened.
            %
            %   paths    session folders
            %   exclude  FileIds excluded (default none)
            %   fp       (returned) as fingerprintOf; "" when a folder is missing
            arguments
                paths string
                exclude string = strings(0,1)
            end
            ids = strings(0,1);  bytes = zeros(0,1);  modified = NaT(0,1);
            fp = "";
            for k = 1:numel(paths)
                if ~isfolder(paths(k)), return; end
                d = dir(fullfile(char(paths(k)),'*.abr'));
                d = d(~[d.isdir]);
                if isempty(d), continue; end
                fname = mabr.analysis.Session.folderName(paths(k));
                ids      = [ids; fname + "/" + reshape(string({d.name}),[],1)]; %#ok<AGROW>
                bytes    = [bytes; reshape([d.bytes],[],1)]; %#ok<AGROW>
                modified = [modified; datetime(reshape([d.datenum],[],1),'ConvertFrom','datenum')]; %#ok<AGROW>
            end
            fp = mabr.analysis.Session.fingerprintOf(ids,bytes,modified,exclude);
        end

        function s = subjectFrom(pth)
            % Subject token out of a path, if one is there to be found.
            %
            %   pth  a file or folder path, char or string
            %   s    (returned) 1x1 string, the matched "SUBJ_ID_###"-style
            %        token as spelled, or "" when none is found. (The canonical
            %        spelling is mabr.analysis.AbrFile.subjectOf.)
            s = "";
            m = regexp(char(pth),'SUBJ[_-]?ID[_-]?\d+','match','once','ignorecase');
            if ~isempty(m), s = string(m); end
        end

        function [grp,added] = seriesGrouping(groupBy,keyParams,levelParam,pooled)
            % The columns a series is keyed by, from a GroupBy as typed.
            %
            % Empty GroupBy is every key column but the level. Otherwise the
            % columns named, PLUS Stimulus and AcqMode whenever they are key
            % columns the list leaves out -- AcqMode not when the modes are
            % pooled (one "pooled" mode is no distinction) -- never the level,
            % never twice, in key order. A series is one stimulus in one
            % acquisition mode whatever is typed: GroupBy "Level" with
            % Frequency as the level axis would otherwise fit clicks, tones,
            % conventional and interleaved runs into one series per level,
            % with nothing to say so.
            %
            %   groupBy     string row as typed ([] or string.empty = default)
            %   keyParams   the session's KeyParams, in key order
            %   levelParam  the level axis (never a series column)
            %   pooled      true when segment pooled the acquisition modes
            %   grp         (returned) string row, in key order
            %   added       (returned) string row: the columns added to a
            %               typed list (empty for the default)
            arguments
                groupBy string = string.empty
                keyParams string = string.empty
                levelParam (1,1) string = ""
                pooled (1,1) logical = false
            end
            groupBy   = reshape(groupBy(~ismissing(groupBy) & strlength(groupBy) > 0),1,[]);
            keyParams = reshape(keyParams,1,[]);
            added = strings(1,0);
            if isempty(groupBy)
                grp = setdiff(keyParams,levelParam,'stable');
                return
            end
            always = "Stimulus";
            if ~pooled, always(end+1) = "AcqMode"; end
            always = always(ismember(always,keyParams) & always ~= levelParam);
            added = always(~ismember(always,groupBy));
            grp = unique([added groupBy],'stable');
            grp = mabr.analysis.Session.inKeyOrder(grp,keyParams);
            grp = reshape(string(grp),1,[]);
        end
    end

    methods (Static, Access = private)
        function tf = isDetectFlag(f)
            % Whether a Conditions.Flags entry is one detect() writes (and
            % so replaces on every re-test). f: string array; tf (returned)
            % logical, the same size.
            tf = f == mabr.analysis.SingleTrial.FlagZeroVariance | startsWith(f,"TFCE step raised");
        end

        function [d,why] = detectOne(X,args)
            % One condition's permutation test, packaged so that detect() and
            % anything testing one condition call exactly the same thing.
            %
            %   X     [nSamples x nSweeps] clean sweeps for one condition
            %   args  cell {rows,method,nPerm,alpha,minSz,seed,rowsMs[,pol,
            %         strata]}, the detect() options in positional form, and
            %         the sweeps' polarities and files (without them the
            %         sweeps are one group: see Threshold.detect)
            %   d     (returned) the Detection record (see detect)
            %   why   (returned) string row: Threshold.detect's Flags -- the
            %         condition has no noise and was not tested, or its TFCE
            %         step was raised
            [rows,method,nPerm,alpha,minSz,seed,rowsMs] = deal(args{1:7});
            pol = [];  str = [];
            if numel(args) >= 9, pol = args{8};  str = args{9}; end
            why = strings(1,0);
            d = struct('p',NaN,'isSig',false,'strength',NaN,'nSweeps',size(X,2), ...
                'method',method,'tThresh',NaN,'t',zeros(1,0),'pSample',zeros(1,0), ...
                'sigMask',false(1,0),'clusters',struct([]),'RowsMs',rowsMs,'NullP95',NaN, ...
                'Seed',seed,'null',zeros(0,1));
            if isempty(X) || size(X,2) < 2 || ~any(rows)
                return
            end
            r = mabr.analysis.Threshold.detect(X, Rows=rows, Method=method, ...
                NumPermutations=nPerm, Alpha=alpha, MinClusterSize=minSz, Seed=seed, ...
                Polarity=pol, Strata=str);
            why = reshape(string(r.Flags),1,[]);
            res = r.result;
            d.p        = r.p;
            d.isSig    = r.isSig;
            d.strength = r.strength;
            d.nSweeps  = r.nSweeps;
            if isstruct(res) && isfield(res,'t')
                d.tThresh  = res.tThresh;
                d.t        = reshape(res.t,1,[]);
                d.pSample  = reshape(res.pSample,1,[]);
                d.sigMask  = reshape(logical(res.sigMask),1,[]);
                d.clusters = res.clusters;
                d.null     = res.null(:);
                if ~isempty(res.null)
                    d.NullP95 = mabr.analysis.Stats.percentile(res.null,0.95);
                end
            end
        end

        function [gid,U,keys] = groupRows(T,keyParams)
            % Group rows by their condition key, NaN-safely.
            %
            %   T          table holding the keyParams columns
            %   keyParams  key columns, in key order
            %   gid        (returned) [height(T) x 1] group of each row
            %   U          (returned) the first row of each group, sorted by
            %              keyParams (numbers ascending, NaN last; text ascending,
            %              which puts conventional < interleaved < pooled)
            %   keys       (returned) the groups' key text, in U's order
            %
            %   Every grouping in Session comes through here: keys are text, so
            %   a NaN (a click's Frequency) is a value like any other rather
            %   than the row unique() and ismember() can never match.
            keyParams = reshape(string(keyParams),1,[]);
            n = height(T);
            if n == 0
                gid = zeros(0,1);
                U = T(:,cellstr(keyParams));
                keys = strings(0,1);
                return
            end
            rk = mabr.analysis.Session.keyText(T,keyParams);
            [ukeys,first,g] = unique(rk,'stable');
            U = T(first,cellstr(keyParams));
            o = mabr.analysis.Session.sortOrder(U,keyParams);
            U = U(o,:);
            keys = ukeys(o);
            rank = zeros(numel(o),1);
            rank(o) = 1:numel(o);
            gid = rank(g);
        end

        function k = keyText(T,cols)
            % One key per row: "Name=Value" over cols, joined by "|".
            %
            %   T     table holding cols
            %   cols  column names, in key order
            %   k     (returned) [height(T) x 1] string. Values through
            %         mabr.analysis.Stats.keyValue; a numeric NaN -- a
            %         parameter this stimulus does not have -- is left out, so a
            %         click's key is the same whether or not tones share its
            %         session. No columns: "(all)".
            n = height(T);
            cols = reshape(string(cols),1,[]);
            if isempty(cols)
                k = repmat("(all)",n,1);
                return
            end
            parts = strings(n,numel(cols));
            for j = 1:numel(cols)
                v = T.(cols(j));
                if isnumeric(v) || islogical(v)
                    v = double(v(:));
                    txt = cols(j) + "=" + mabr.analysis.Stats.keyValue(v);
                    txt(isnan(v)) = "";
                else
                    txt = cols(j) + "=" + mabr.analysis.Stats.keyValue(string(v(:)));
                end
                parts(:,j) = reshape(txt,[],1);
            end
            if n == 0
                k = strings(0,1);
                return
            end
            k = join(parts,"|",2);
            k = regexprep(k,'\|{2,}','|');
            k = regexprep(k,'^\||\|$','');
            k = reshape(k,[],1);
        end

        function o = sortOrder(T,cols)
            % Row order of T sorted by cols: numbers ascending with NaN last,
            % text ascending, earlier columns first.
            n = height(T);
            cols = reshape(string(cols),1,[]);
            if n == 0, o = zeros(0,1); return; end
            R = zeros(n,numel(cols));
            for j = 1:numel(cols)
                v = T.(cols(j));
                if isnumeric(v) || islogical(v)
                    v = double(v(:));
                    [~,~,r] = unique(v);
                    r = r(:);
                    r(isnan(v)) = max([r; 0]) + 1;
                else
                    [~,~,r] = unique(string(v(:)));
                    r = r(:);
                end
                R(:,j) = r;
            end
            [~,o] = sortrows([R (1:n).']);
            o = o(:);
        end

        function kp = keyParamsFor(pn)
            % KeyParams from ParamNames: Stimulus (when present), AcqMode, then
            % the rest sorted by name, case-insensitively.
            pn = reshape(string(pn),1,[]);
            rest = pn(pn ~= "Stimulus");
            [~,o] = sort(lower(rest));
            rest = rest(o);
            if any(pn == "Stimulus")
                kp = ["Stimulus" "AcqMode" rest];
            else
                kp = ["AcqMode" rest];
            end
        end

        function c = inKeyOrder(c,keyParams)
            % c reordered as keyParams orders them; names keyParams lacks last.
            c = reshape(string(c),1,[]);
            known = keyParams(ismember(keyParams,c));
            c = [known c(~ismember(c,keyParams))];
        end

        function m = matches(v,value)
            % Rows of column v equal to value (any of several), NaN-safe.
            if isnumeric(v) || islogical(v)
                if ~(isnumeric(value) || islogical(value))
                    m = false(size(v));
                    return
                end
                v = double(v);  value = double(value(:));
                m = ismember(v,value) | (isnan(v) & any(isnan(value)));
            else
                m = ismember(string(v),string(value));
            end
        end

        function u = uniqueValues(v)
            % unique(v) with every NaN counted once (and last).
            if isnumeric(v) || islogical(v)
                v = double(v(:));
                u = unique(v(~isnan(v)));
                if any(isnan(v)), u(end+1,1) = NaN; end
            else
                u = unique(string(v(:)));
            end
        end

        function tf = gridColumn(C,name)
            % Rows usable on a grid axis: the column exists and is numeric,
            % and the row's value is not NaN.
            if ~ismember(name,string(C.Properties.VariableNames))
                error('mabr:analysis:Session:noSuchParam','"%s" is not a condition column.',name);
            end
            v = C.(name);
            if ~(isnumeric(v) || islogical(v))
                error('mabr:analysis:Session:gridParam', ...
                    'A grid axis must be a numeric parameter; "%s" is not.',name);
            end
            tf = ~isnan(double(v));
        end

        function t = valueText(name,v)
            % One parameter value for a label: "8 kHz", "60 dB", "Tone",
            % "Rate 21.1" (no unit claimed); "" for NaN.
            if isstring(v) || ischar(v)
                t = string(v);
                return
            end
            if isnan(v), t = ""; return; end
            u = string(mabr.stim.StimulusSet.paramUnit(name));
            if u == ""
                t = name + " " + sprintf('%g',v);
            else
                t = sprintf('%g',v) + " " + u;
            end
        end

        function n = filterReach(f)
            % How many samples away a sample still moves a filtered one,
            % either way: the sum of the sections' orders (each section is
            % run forward and back by filtfilt, and its reach adds to the
            % next one's). An IIR section's tail is longer than its order;
            % a custom IIR design is counted ten times over for it.
            n = 0;
            parts = {f.HighNum,f.HighDen;f.LowNum,f.LowDen};
            for k = 1:2
                b = parts{k,1};  a = parts{k,2};
                if isempty(b), continue; end
                o = max(numel(b),numel(a)) - 1;
                if numel(a) > 1, o = 10*o; end
                n = n + o;
            end
        end

        function hit = touches(bad,lo,hi)
            % Whether each [lo(k) hi(k)] sample range holds a true of bad.
            %
            %   bad     nX x 1 logical (the non-finite samples)
            %   lo, hi  1 x n first and last sample of each range (clipped to
            %           the trace)
            %   hit     (returned) 1 x n logical
            nX = numel(bad);
            cb = [0; cumsum(double(bad(:)))];
            lo = min(max(round(lo),1),nX + 1);
            hi = min(max(round(hi),0),nX);
            hit = false(size(lo));
            ok = hi >= lo;
            hit(ok) = cb(hi(ok) + 1) - cb(lo(ok)) > 0;
            hit = reshape(hit,1,[]);
        end

        function ex = excessOf(rej,pol,K,mode,seed,key)
            % Sweeps beyond a cap of K clean sweeps per condition.
            %
            %   rej, pol  1 x n flags and polarities, in acquisition order
            %   K         the cap (Inf = none)
            %   mode      "first" (the earliest) or "random" (a seeded draw
            %             from Stats.conditionStream(seed,key))
            %   ex        (returned) 1 x n logical: clean sweeps not kept
            %
            %   A condition holding both polarities keeps floor(K/2) clean
            %   sweeps of each, so the cap cannot unbalance it; a one-polarity
            %   condition keeps K. Rejected sweeps are never excess.
            n = numel(rej);
            ex = false(1,n);
            if ~isfinite(K) || n == 0, return; end
            clean = ~reshape(logical(rej),1,[]);
            pol = reshape(double(pol),1,[]);
            rs = [];
            if mode == "random"
                rs = mabr.analysis.Stats.conditionStream(seed,key);
            end
            if any(pol > 0) && any(pol < 0)
                h = floor(K/2);
                ex = ex | spare(find(clean & pol > 0),h) | spare(find(clean & pol < 0),h);
            else
                ex = spare(find(clean),K);
            end

            function m = spare(idx,k)
                % Mask of idx entries beyond the k kept.
                m = false(1,n);
                if numel(idx) <= k, return; end
                if isempty(rs)
                    m(idx(k+1:end)) = true;
                else
                    keepIdx = idx(randperm(rs,numel(idx),k));
                    m(idx) = true;
                    m(keepIdx) = false;
                end
            end
        end

        function C = setSweepFlags(C,r,rej,reason,ex)
            % Write one condition's flags and the counts that follow from them.
            pol = C.Polarity{r};
            rej = reshape(logical(rej),1,[]);
            ex  = reshape(logical(ex),1,[]);
            C.Rejected{r}     = rej;
            C.RejectReason{r} = reshape(uint8(reason),1,[]);
            C.Excess{r}       = ex;
            use = ~rej & ~ex;
            C.nRejected(r) = sum(rej);
            C.nClean(r)    = sum(use);
            C.nPos(r)      = sum(use & pol > 0);
            C.nNeg(r)      = sum(use & pol < 0);
        end

        function [flagged,info] = relativeFlags(X,rows,opts)
            % The new rejection rule (see reject): an upper-tail isoutlier
            % criterion on a per-sweep feature, plus an absolute ceiling.
            f = mabr.analysis.Artifacts.feature(X,opts.Feature,rows);
            n = numel(f);
            flagged = false(1,n);
            lo = NaN;  up = NaN;
            if opts.Method ~= "none"
                [~,lo,up] = isoutlier(f(:),opts.Method,'ThresholdFactor',opts.Factor);
                lo = lo(1);  up = up(1);
                if opts.UpperOnly && opts.Feature ~= "negPeak"
                    flagged = f > up;
                else
                    flagged = f < lo | f > up;
                end
            end
            if isfinite(opts.Ceiling)
                flagged = flagged | abs(f) > opts.Ceiling;
            end
            flagged = reshape(flagged,1,[]);
            info = struct('feature',f,'lower',lo,'upper',up,'method',opts.Method, ...
                'name',opts.Feature,'count',sum(flagged));
        end

        function m = extentMask(t,extent)
            % Rows of t inside a condition's Extent ([NaN NaN] = none).
            if any(isnan(extent))
                m = false(size(t));
            else
                m = t >= extent(1) & t <= extent(2);
            end
        end

        function [u,l] = unitsOf(units,levelUnits)
            % One condition's (or session's) units and level reference:
            % the single value its files agree on, "mixed" when they do not.
            u = unique(units(units ~= ""));
            if isempty(u), u = ""; elseif numel(u) > 1, u = "mixed"; end
            l = unique(levelUnits(levelUnits ~= ""));
            if isempty(l), l = ""; elseif numel(l) > 1, l = "mixed"; end
        end

        function m = acqModesOf(modes)
            % The acquisition modes present, in key order.
            order = ["conventional","interleaved","pooled"];
            m = order(ismember(order,modes));
            other = setdiff(unique(modes(modes ~= "")),order);
            m = [m reshape(other,1,[])];
        end

        function [s,raw] = dominantSubject(recs)
            % The subject most of these files' names carry.
            s = "";  raw = "";
            sub = reshape([recs.Subject],[],1);
            rawAll = reshape([recs.SubjectRaw],[],1);
            ok = sub ~= "";
            if ~any(ok), return; end
            [u,~,j] = unique(sub(ok));
            [~,b] = max(accumarray(j,1));
            s = u(b);
            r = rawAll(ok);
            raw = r(find(sub(ok) == s,1));
        end

        function n = folderName(p)
            % The last component of a folder path.
            p = regexprep(char(p),'[\\/]+$','');
            [~,nm,ext] = fileparts(p);
            n = string([nm ext]);
        end

        function o = checkOverride(o)
            % A UnitOverride struct with both fields (NaN = no override).
            if ~isstruct(o) || ~isscalar(o)
                error('mabr:analysis:Session:badOverride', ...
                    'UnitOverride is a struct with InputFullScale and AmplifierGain (NaN = none).');
            end
            out = struct('InputFullScale',NaN,'AmplifierGain',NaN);
            for f = ["InputFullScale","AmplifierGain"]
                if isfield(o,f) && isnumeric(o.(f)) && isscalar(o.(f)) && isreal(o.(f))
                    v = double(o.(f));
                    if isfinite(v) && v <= 0
                        error('mabr:analysis:Session:badOverride','%s must be positive.',f);
                    end
                    out.(f) = v;
                end
            end
            o = out;
        end

        function F = emptyFiles(pn)
            % A Files table with no rows and every column.
            F = table();
            for name = reshape(string(pn),1,[])
                if name == "Stimulus", F.Stimulus = strings(0,1); else, F.(name) = zeros(0,1); end
            end
            F.timestamp = NaT(0,1);  F.fileName = strings(0,1);  F.folder = strings(0,1);
            F.nSweeps = zeros(0,1);  F.SampleRate = zeros(0,1);  F.TestMode = false(0,1);
            F.FileId = strings(0,1);
            if ~any(pn == "Stimulus"), F.Stimulus = strings(0,1); end
            F.StimID = strings(0,1);  F.AcqMode = strings(0,1);  F.Layout = strings(0,1);
            F.SweepLength = zeros(0,1);  F.AlternatePolarity = false(0,1);
            F.Units = strings(0,1);  F.LevelUnit = strings(0,1);  F.Calibrated = false(0,1);
            F.Bytes = zeros(0,1);  F.Modified = NaT(0,1);  F.Duration = zeros(0,1);
            F.MinISI = zeros(0,1);  F.Era = strings(0,1);  F.TruncatedSweeps = zeros(0,1);
            F.Include = false(0,1);  F.Reason = strings(0,1);  F.RunGroup = strings(0,1);
            F.Short = false(0,1);  F.DuplicateOf = strings(0,1);
            F.AmplifierGain = zeros(0,1);  F.InputFullScale = zeros(0,1);
            F.CalibrationTime = strings(0,1);
        end

        function S = emptyStepState()
            S = struct();
            for s = mabr.analysis.Session.StepNames, S.(s) = []; end
        end

        function M = emptyMessages()
            M = table('Size',[0 4],'VariableTypes',{'datetime','string','string','string'}, ...
                'VariableNames',{'Time','Level','Step','Text'});
        end

        function tf = saveRows(M)
            % Rows of a Messages table recorded under step "save" -- what
            % saveResults no longer records and leaves out of what it writes.
            tf = false(height(M),1);
            if istable(M) && ismember('Step',M.Properties.VariableNames)
                tf = string(M.Step) == "save";
            end
        end

        function T = emptyManualRejections()
            T = table('Size',[0 5],'VariableTypes',{'string','double','logical','datetime','string'}, ...
                'VariableNames',{'FileId','SweepIndex','Reject','Time','By'});
        end

        function T = emptyDetectionOverrides()
            T = table('Size',[0 4],'VariableTypes',{'string','double','datetime','string'}, ...
                'VariableNames',{'Key','Value','Time','By'});
        end

        function T = emptyPeakOverrides()
            T = table('Size',[0 7],'VariableTypes', ...
                {'string','string','string','string','double','datetime','string'}, ...
                'VariableNames',{'Key','Wave','Kind','State','Latency','Time','By'});
        end

        function T = emptyCurationArchive()
            T = table('Size',[0 13],'VariableTypes', ...
                {'string','string','double','string','double','string','double','double', ...
                 'string','string','datetime','double','string'}, ...
                'VariableNames',{'Key','Decision','ManualValue','ManualKind','Final', ...
                 'FinalCensored','FinalLo','FinalHi','Note','ReviewedBy','ReviewedAt', ...
                 'ReviewedValue','ReviewedMethod'});
        end

        function T = emptyEditLog()
            T = table('Size',[0 6],'VariableTypes',{'datetime','string','string','string','string','string'}, ...
                'VariableNames',{'Time','User','Action','Key','Old','New'});
        end

        function M = emptyMeans()
            M = struct('Keys',strings(0,1),'Balanced',zeros(0,0,'single'), ...
                'Positive',zeros(0,0,'single'),'Negative',zeros(0,0,'single'), ...
                'SEM',zeros(0,0,'single'),'N',zeros(0,1));
        end

        function D = emptyDetection()
            D = struct('p',cell(0,1),'isSig',cell(0,1),'strength',cell(0,1),'nSweeps',cell(0,1), ...
                'method',cell(0,1),'tThresh',cell(0,1),'t',cell(0,1),'pSample',cell(0,1), ...
                'sigMask',cell(0,1),'clusters',cell(0,1),'RowsMs',cell(0,1),'NullP95',cell(0,1), ...
                'Seed',cell(0,1));
        end

        function d = flatDetection(d)
            % A Detection record of any vintage in the current shape: a v1
            % record (p,isSig,strength,nSweeps,result) is flattened, a saved one
            % gets its null back as empty, and t/pSample are double again.
            if ~isstruct(d) || isempty(d)
                d = mabr.analysis.Session.detectOne([],{true,"",0,0.05,1,NaN,[NaN NaN]});
                return
            end
            out = mabr.analysis.Session.detectOne([],{true,"",0,0.05,1,NaN,[NaN NaN]});
            if isfield(d,'result') && isstruct(d.result)
                res = d.result;
                for f = ["p","isSig","strength","nSweeps"]
                    if isfield(d,f), out.(f) = d.(f); end
                end
                if isfield(res,'method'),   out.method   = string(res.method); end
                if isfield(res,'tThresh'),  out.tThresh  = res.tThresh; end
                if isfield(res,'t'),        out.t        = reshape(double(res.t),1,[]); end
                if isfield(res,'pSample'),  out.pSample  = reshape(double(res.pSample),1,[]); end
                if isfield(res,'sigMask'),  out.sigMask  = reshape(logical(res.sigMask),1,[]); end
                if isfield(res,'clusters'), out.clusters = res.clusters; end
                if isfield(res,'null') && ~isempty(res.null)
                    out.null    = res.null(:);
                    out.NullP95 = mabr.analysis.Stats.percentile(res.null,0.95);
                end
                d = out;
                return
            end
            for f = string(fieldnames(out)).'
                if isfield(d,f), out.(f) = d.(f); end
            end
            out.t       = reshape(double(out.t),1,[]);
            out.pSample = reshape(double(out.pSample),1,[]);
            out.sigMask = reshape(logical(out.sigMask),1,[]);
            d = out;
        end

        function s = filterToStruct(f)
            % A Filter as a plain struct (undesigned bands, or a custom design's
            % coefficients), so a results file can rebuild it.
            s = struct('HighPass',f.HighPass,'LowPass',f.LowPass,'PassRipple',f.PassRipple, ...
                'StopRipple',f.StopRipple,'Density',f.Density,'Method',f.Method, ...
                'Custom',f.Custom,'HighNum',f.HighNum,'HighDen',f.HighDen, ...
                'LowNum',f.LowNum,'LowDen',f.LowDen,'SampleRate',f.SampleRate);
        end

        function f = filterFromStruct(s)
            % filterToStruct, the way back (undesigned unless custom).
            if isfield(s,'Custom') && s.Custom
                f = mabr.analysis.Filter.fromCoefficients(s.HighNum,s.LowNum, ...
                    HighDen=s.HighDen,LowDen=s.LowDen,SampleRate=s.SampleRate,Method=s.Method);
            else
                f = mabr.analysis.Filter('HighPass',s.HighPass,'LowPass',s.LowPass, ...
                    'PassRipple',s.PassRipple,'StopRipple',s.StopRipple, ...
                    'Density',s.Density,'Method',s.Method);
            end
        end

        function x = stripHandles(x)
            % x without any function handle, at any depth of struct -- a saved
            % fit carries none (Threshold.predictor rebuilds Predict).
            if isstruct(x)
                f = fieldnames(x);
                drop = false(size(f));
                for i = 1:numel(f)
                    if isscalar(x) && isa(x.(f{i}),'function_handle')
                        drop(i) = true;
                    end
                end
                x = rmfield(x,f(drop));
                f = fieldnames(x);
                for k = 1:numel(x)
                    for i = 1:numel(f)
                        v = x(k).(f{i});
                        if isa(v,'function_handle')
                            x(k).(f{i}) = [];
                        elseif isstruct(v)
                            x(k).(f{i}) = mabr.analysis.Session.stripHandles(v);
                        end
                    end
                end
            elseif isa(x,'function_handle')
                x = [];
            end
        end

        function x = restorePredict(x)
            % Threshold.predictor over a saved fit (and a nested Fit), where
            % the class offers it; otherwise the fit is left as it is.
            if ~isstruct(x) || ~isscalar(x), return; end
            try
                if isfield(x,'Type') && isfield(x,'Model')
                    x = mabr.analysis.Threshold.predictor(x);
                end
                if isfield(x,'Fit') && isstruct(x.Fit) && isscalar(x.Fit) ...
                        && isfield(x.Fit,'Type') && isfield(x.Fit,'Model')
                    x.Fit = mabr.analysis.Threshold.predictor(x.Fit);
                end
            catch
                % An older Threshold without predictor(): the fit loads
                % without a curve, which is drawn, never computed with.
            end
        end

        function st = settingsStruct(s)
            % The settings used, as a plain struct ([] when none).
            st = [];
            if isempty(s), return; end
            if isstruct(s)
                st = s;
            elseif isobject(s) && ismethod(s,'toStruct')
                st = s.toStruct();
            end
        end

        function T = alignColumns(T,template)
            % T with every column template has (defaults where T lacks one),
            % in template's order; columns template lacks go last.
            n = height(T);
            for v = string(template.Properties.VariableNames)
                if ismember(v,string(T.Properties.VariableNames)), continue; end
                c = template.(v);
                w = size(c,2);
                if iscell(c)
                    T.(v) = cell(n,w);
                elseif isstring(c)
                    T.(v) = strings(n,w);
                elseif islogical(c)
                    T.(v) = false(n,w);
                elseif isdatetime(c)
                    T.(v) = NaT(n,w);
                elseif isfloat(c)
                    T.(v) = NaN(n,w,'like',c);
                elseif isnumeric(c)
                    T.(v) = zeros(n,w,'like',c);
                else
                    T.(v) = repmat(c([],:),n,1);
                end
            end
            order = [string(template.Properties.VariableNames) ...
                setdiff(string(T.Properties.VariableNames),string(template.Properties.VariableNames),'stable')];
            T = T(:,cellstr(order));
        end

        function C = canonicalConditions(C,keyParams)
            % Conditions columns in the order segment and detect write them.
            names = string(C.Properties.VariableNames);
            first = ["Key" keyParams mabr.analysis.Session.SweepColumns ...
                "nSweeps","nRejected","nFiles","nClean","nPos","nNeg","Processing","Extent", ...
                "Units","LevelUnit","Flags","p","isSig","strength","Detection","DetectedAuto","Detected"];
            first = first(ismember(first,names));
            last  = names(names == "Features");
            mid   = names(~ismember(names,[first last]));
            C = C(:,cellstr([first mid last]));
        end

        function t = shortText(v)
            % A value for a message line: numbers by %g, anything else as JSON.
            if isnumeric(v) && isscalar(v)
                t = string(sprintf('%g',v));
            else
                t = string(jsonencode(v));
            end
        end

        % --- part B helpers -------------------------------------------------
        function c = metricColumnOf(metric)
            % The Conditions column a threshold metric is read from.
            switch metric
                case "detection", c = "p";
                case "strength",  c = "strength";
                case "power",     c = "PowerP";
                case "fsp",       c = "FspP";
                case "splithalf", c = "SplitR";
                case "xcorr",     c = "XCorrUp";
                case "dtw",       c = "DTWUp";
                case "snr",       c = "SNR";
                otherwise,        c = "";
            end
        end

        function Y = seriesY(C,idx,ov)
            % SeriesThreshold.estimate's per-level inputs for rows idx.
            cols = string(C.Properties.VariableNames);
            n = numel(idx);
            get = @(name) mabr.analysis.Session.columnOr(C,cols,name,idx,n);
            Y = struct();
            Y.P        = get("p");
            Y.IsSig    = get("isSig");
            Y.Strength = get("strength");
            Y.PowerP   = get("PowerP");
            Y.FspP     = get("FspP");
            Y.SplitR   = get("SplitR");
            Y.SplitRSD = get("SplitRSD");
            Y.XCorrUp  = get("XCorrUp");
            Y.DTWUp    = get("DTWUp");
            Y.SNR      = get("SNR");
            Y.NClean   = double(C.nClean(idx));
            Y.NPos     = double(C.nPos(idx));
            Y.NNeg     = double(C.nNeg(idx));
            Y.Override = ov(idx);
            % A level with no noise has no metric, and says why.
            Y.ZeroVariance = false(n,1);
            if ismember("Flags",cols)
                Y.ZeroVariance = reshape(contains(C.Flags(idx), ...
                    mabr.analysis.SingleTrial.FlagZeroVariance),[],1);
            end
        end

        function v = columnOr(C,cols,name,idx,n)
            % A numeric column's rows, or NaN when the table lacks it.
            if ismember(name,cols)
                v = double(C.(name)(idx));
                v = reshape(v,[],1);
            else
                v = NaN(n,1);
            end
        end

        function R = thresholdRowOf(key,G,g,lvl,m,out)
            % One Thresholds row from SeriesThreshold.estimate's output.
            R = table(key,'VariableNames',{'Key'});
            if width(G) > 0, R = [R G(g,:)]; end
            R.LevelParam    = string(lvl);
            R.Method        = string(m.Id);
            R.Metric        = string(m.Metric);
            R.Type          = string(out.Type);
            R.FitTarget     = string(out.FitTarget);
            R.Criterion     = double(out.Criterion);
            R.CriterionUnit = string(out.CriterionUnit);
            R.Convention    = string(out.Convention);
            R.Threshold     = double(out.Threshold);
            R.ThresholdRaw  = double(out.ThresholdRaw);
            R.Status        = string(out.Status);
            R.Censored      = string(out.Censored);
            R.ThrLo         = double(out.ThrLo);
            R.ThrHi         = double(out.ThrHi);
            R.CILower       = double(out.CILower);
            R.CIUpper       = double(out.CIUpper);
            R.CIMethod      = string(out.CIMethod);
            R.NumLevels     = double(out.NumLevels);
            R.NumUsable     = double(out.NumUsable);
            R.NumSig        = double(out.NumSig);
            R.LevelStep     = double(out.LevelStep);
            R.MinLevel      = double(out.MinLevel);
            R.MaxLevel      = double(out.MaxLevel);
            R.Converged     = logical(out.Converged);
            R.Message       = string(out.Message);
            R.Flags         = strjoin(string(out.Flags),"; ");
            R.Decision      = "";
            R.ManualValue   = NaN;
            R.ManualKind    = "";
            R.Final         = NaN;
            R.FinalCensored = "";
            R.FinalLo       = NaN;
            R.FinalHi       = NaN;
            R.Note          = "";
            R.ReviewedBy    = "";
            R.ReviewedAt    = NaT;
            R.ReviewedValue = NaN;
            R.ReviewedMethod = "";
            R.Curated       = NaN;
            R.IsCurated     = false;
            R.Fit           = {out.Fit};
        end

        function s = thresholdOptions(opts,ms)
            % estimateThresholds' options as stored in StepOptions (plain).
            s = rmfield(opts,'SeriesKeys');
            s.MethodSettings = ms;
        end

        function [Tn,arch,nArch] = carryCuration(Tn,prev,arch,tg,keys,~)
            % The curation of prev (and the archive) onto the re-estimated
            % rows, by key; curated rows whose key vanished into the archive.
            cc = mabr.analysis.Session.CurationColumns;
            src = mabr.analysis.Session.curationOf(prev);
            src.PrevCensored = strings(height(src),1);
            if height(src) > 0 && ismember('Censored',prev.Properties.VariableNames)
                [tf,loc] = ismember(src.Key,prev.Key);
                src.PrevCensored(tf) = string(prev.Censored(loc(tf)));
            end
            if height(arch) > 0
                A = arch(~ismember(arch.Key,src.Key),:);
                A.PrevCensored = string(A.FinalCensored);
                A = A(:,src.Properties.VariableNames);
                src = [src; A];
            end
            targetKeys = keys(tg);
            restored = strings(0,1);
            for i = find(ismember(Tn.Key,targetKeys)).'
                j = find(src.Key == Tn.Key(i),1);
                if isempty(j), continue; end
                for c = cc
                    Tn.(c)(i) = src.(c)(j);
                end
                restored(end+1,1) = Tn.Key(i); %#ok<AGROW>
                if Tn.Decision(i) == "accepted"
                    tol = Tn.LevelStep(i)/2;
                    if ~isfinite(tol), tol = 0; end
                    moved = ~mabr.analysis.Session.sameValue(Tn.Threshold(i),Tn.ReviewedValue(i),tol) || ...
                        (src.PrevCensored(j) ~= "" && Tn.Censored(i) ~= src.PrevCensored(j));
                    if moved, Tn.Decision(i) = ""; end
                end
            end
            arch = arch(~ismember(arch.Key,restored),:);
            % Curated rows whose series is gone.
            nArch = 0;
            if height(prev) > 0 && ismember('Decision',prev.Properties.VariableNames)
                gone = ~ismember(prev.Key,Tn.Key) & (prev.Decision ~= "" | prev.Note ~= "" | prev.ReviewedBy ~= "");
                if any(gone)
                    G = mabr.analysis.Session.curationOf(prev(gone,:));
                    arch = [arch(~ismember(arch.Key,G.Key),:); G];
                    nArch = sum(gone);
                end
            end
        end

        function T = refreshCuration(T,~,mask)
            % Flags of the review state, Final* (SeriesThreshold.finalValue),
            % Curated and IsCurated for the rows in mask.
            for i = find(mask(:)).'
                fl = strtrim(split(T.Flags(i),";"));
                fl = fl(fl ~= "" & ~startsWith(fl,["fit changed since review","reviewed under"]));
                fl = reshape(fl,1,[]);
                % A review record with no decision is an acceptance carryCuration
                % took back (the fit moved, or its censoring changed): clearDecision
                % clears the record with the decision, so nothing else leaves one.
                if T.Decision(i) == "" && T.ReviewedBy(i) ~= ""
                    fl(end+1) = sprintf("fit changed since review (was %s, now %s)", ...
                        mabr.analysis.SeriesThreshold.formatValue(T.ReviewedValue(i)), ...
                        mabr.analysis.SeriesThreshold.formatValue(T.Threshold(i),T.Censored(i), ...
                        T.ThrLo(i),T.ThrHi(i))); %#ok<AGROW>
                end
                if T.Decision(i) ~= "" && T.ReviewedMethod(i) ~= "" && T.ReviewedMethod(i) ~= T.Method(i)
                    fl(end+1) = "reviewed under " + T.ReviewedMethod(i); %#ok<AGROW>
                end
                T.Flags(i) = strjoin(fl,"; ");
                F = mabr.analysis.SeriesThreshold.finalValue(T(i,:),T.Convention(i));
                T.Final(i)         = F.Final;
                T.FinalCensored(i) = F.FinalCensored;
                T.FinalLo(i)       = F.FinalLo;
                T.FinalHi(i)       = F.FinalHi;
                T.Curated(i)       = F.Final;
                T.IsCurated(i)     = ismember(T.Decision(i),["manual","noresponse","allrespond","excluded"]);
            end
        end

        function tf = sameValue(a,b,tol)
            % Two thresholds the same within tol (non-finite ones: equal).
            if isfinite(a) && isfinite(b)
                tf = abs(a - b) <= tol + 1e-9;
            else
                tf = isequaln(a,b);
            end
        end

        function K = curationOf(T)
            % Key and the curation columns of a Thresholds table, in the
            % CurationArchive's shape (a v1 table's Curated/IsCurated read as
            % the decisions setThreshold makes).
            K = mabr.analysis.Session.emptyCurationArchive();
            if ~istable(T) || height(T) == 0 || ~ismember('Key',T.Properties.VariableNames)
                return
            end
            v = string(T.Properties.VariableNames);
            if ismember("Decision",v)
                K = mabr.analysis.Session.alignTypes(T,K);
                return
            end
            if ~all(ismember(["Curated","IsCurated"],v)), return; end
            for i = reshape(find(T.IsCurated),1,[])
                c = T.Curated(i);
                if isnan(c), d = "excluded"; mv = NaN; mk = "";
                elseif isinf(c), d = "noresponse"; mv = NaN; mk = "";
                else, d = "manual"; mv = c; mk = "value";
                end
                K(end+1,:) = {string(T.Key(i)),d,mv,mk,NaN,"",NaN,NaN,"","",NaT,NaN,""}; %#ok<AGROW>
            end
        end

        function T = applyCuration(T,K)
            % K's curation (Key + columns) onto the rows of T with its keys.
            if height(K) == 0, return; end
            [tf,loc] = ismember(T.Key,K.Key);
            cc = mabr.analysis.Session.CurationColumns;
            for c = cc
                if ismember(c,string(K.Properties.VariableNames))
                    T.(c)(tf) = K.(c)(loc(tf));
                end
            end
        end

        function T = clearCuration(T)
            % Every curation column at its "no decision" value.
            n = height(T);
            T.Decision = strings(n,1);  T.ManualValue = NaN(n,1);  T.ManualKind = strings(n,1);
            T.Note = strings(n,1);  T.ReviewedBy = strings(n,1);  T.ReviewedAt = NaT(n,1);
            T.ReviewedValue = NaN(n,1);  T.ReviewedMethod = strings(n,1);
        end

        function M = mergeByKey(A,B,keyCols)
            % A's rows, with B's replacing any of the same key(s), B's new
            % ones appended (B coerced to A's columns and types).
            if ~istable(B) || height(B) == 0, M = A; return; end
            B = mabr.analysis.Session.alignTypes(B,A);
            ka = mabr.analysis.Session.joinKeys(A,keyCols);
            kb = mabr.analysis.Session.joinKeys(B,keyCols);
            [~,last] = unique(kb,'last');
            B = B(sort(last),:);
            kb = kb(sort(last));
            M = [A(~ismember(ka,kb),:); B];
        end

        function k = joinKeys(T,cols)
            k = strings(height(T),1);
            for c = reshape(string(cols),1,[])
                k = k + "|" + string(T.(c));
            end
        end

        function B = alignTypes(B,A)
            % B with exactly A's columns, in A's order and of A's types
            % (missing ones filled with "nothing": "", NaN, NaT, false).
            n = height(B);
            out = table();
            bv = string(B.Properties.VariableNames);
            for v = string(A.Properties.VariableNames)
                c = A.(v);
                if ismember(v,bv)
                    x = B.(v);
                    try
                        if isstring(c), x = string(x);
                        elseif isdatetime(c) && ~isdatetime(x), x = NaT(n,1);
                        elseif islogical(c), x = logical(x);
                        elseif isnumeric(c), x = double(x);
                        end
                    catch
                    end
                else
                    x = mabr.analysis.Session.blankLike(c,n);
                end
                if n == 0, x = c([],:); end
                out.(v) = x;
            end
            if n == 0, out = A([],:); end
            B = out;
        end

        function T = tableField(E,name,template)
            % E.(name) as a table shaped like template ([] -> the template).
            T = template;
            if isfield(E,name) && istable(E.(name)) && height(E.(name)) > 0
                if width(template) == 0
                    T = E.(name);
                else
                    T = mabr.analysis.Session.alignTypes(E.(name),template);
                end
            end
        end

        function MR = upsertManual(MR,fid,six,tf,by)
            % Hand decisions on sweeps (FileId, SweepIndex): last write wins.
            k  = MR.FileId + "#" + string(MR.SweepIndex);
            kn = string(fid(:)) + "#" + string(six(:));
            MR = MR(~ismember(k,kn),:);
            n = numel(kn);
            add = table(string(fid(:)),double(six(:)),repmat(logical(tf),n,1), ...
                repmat(datetime('now'),n,1),repmat(string(by),n,1), ...
                'VariableNames',{'FileId','SweepIndex','Reject','Time','By'});
            MR = [MR; add];
        end

        function A = anchorsFromPicks(P)
            % The picks of a Peaks table as Peaks.track anchors (manual where
            % picked, absent where marked absent; troughs only when manual).
            n = height(P);
            lev = zeros(0,1);  wv = strings(0,1);  kd = wv;  st = wv;  lt = lev;
            for i = 1:n
                if ismember(P.State(i),["auto","manual"]) && isfinite(P.PeakLatency(i))
                    lev(end+1,1) = P.Level(i); wv(end+1,1) = P.Wave(i); kd(end+1,1) = "P"; %#ok<AGROW>
                    st(end+1,1) = "manual"; lt(end+1,1) = P.PeakLatency(i); %#ok<AGROW>
                elseif P.State(i) == "absent"
                    lev(end+1,1) = P.Level(i); wv(end+1,1) = P.Wave(i); kd(end+1,1) = "P"; %#ok<AGROW>
                    st(end+1,1) = "absent"; lt(end+1,1) = NaN; %#ok<AGROW>
                end
                if P.TroughState(i) == "manual" && isfinite(P.TroughLatency(i))
                    lev(end+1,1) = P.Level(i); wv(end+1,1) = P.Wave(i); kd(end+1,1) = "N"; %#ok<AGROW>
                    st(end+1,1) = "manual"; lt(end+1,1) = P.TroughLatency(i); %#ok<AGROW>
                end
            end
            A = table(lev,wv,kd,st,lt,'VariableNames',{'Level','Wave','Kind','State','Latency'});
        end

        function a = namedArgs(s,names)
            % Name,Value pairs of the fields of s named in names.
            a = {};
            if ~isstruct(s), return; end
            for f = reshape(string(names),1,[])
                if isfield(s,f), a = [a {char(f),s.(f)}]; end %#ok<AGROW>
            end
        end

        function s = argsStruct(a)
            % Name,Value pairs as a struct, with pickPeaks' defaults beneath.
            s = struct('Waves',mabr.analysis.Peaks.defaultWaves(),'OctaveShift',0.15, ...
                'RefFrequency',16,'Smooth',0,'MinSeparation',0.3,'TrackEarly',0.1, ...
                'TrackLate',0.15,'CandidateRN',1,'DetectableRN',2,'Polarity',"balanced", ...
                'AboveThresholdOnly',true,'BaselineAmpWindow',[-1 0],'EdgeMs',1.0, ...
                'Bootstrap',0,'Seed',1,'LatencyOffset',NaN);
            for i = 1:2:numel(a)
                s.(a{i}) = a{i+1};
            end
            s.Waves = mabr.analysis.Session.waveStruct(s.Waves);
        end

        function W = waveStruct(W)
            % A wave table or struct array as a plain struct array.
            if istable(W), W = table2struct(W).'; end
            W = reshape(W,1,[]);
        end

        function d = settingsDelay(s)
            % conductionDelay() of a Settings object or struct (0 for none).
            d = 0;
            if isempty(s), return; end
            if isobject(s) && ismethod(s,'conductionDelay')
                d = double(s.conductionDelay());
                return
            end
            if ~isstruct(s) || ~isfield(s,'ConductionDelayMode'), return; end
            switch lower(string(s.ConductionDelayMode))
                case "delay"
                    d = double(s.ConductionDelay);
                case "distance"
                    d = 10*double(s.SpeakerDistance)/double(s.SpeedOfSound);
            end
            if ~isfinite(d), d = 0; end
        end

        function v = settingsNumber(s,name,default)
            % A numeric field of a Settings object or struct.
            v = default;
            if isempty(s), return; end
            try
                if (isstruct(s) && isfield(s,name)) || (isobject(s) && isprop(s,name))
                    v = double(s.(name));
                end
            catch
            end
            if ~isscalar(v) || ~isfinite(v), v = default; end
        end

        function s = asSettings(x)
            % A mabr.analysis.Settings from a Settings, a struct, or [].
            if isempty(x)
                s = mabr.analysis.Settings();
            elseif isa(x,'mabr.analysis.Settings')
                s = x;
            elseif isstruct(x)
                s = mabr.analysis.Settings.fromStruct(x);
            else
                error('mabr:analysis:Session:badSettings', ...
                    'Settings must be a mabr.analysis.Settings or its struct, not a %s.',class(x));
            end
        end

        function t = settingText(v)
            % One setting's value for an isStale row.
            if isstring(v) || ischar(v)
                v = string(v);
                if isempty(v), t = "(none)"; else, t = strjoin(v,", "); end
            elseif islogical(v) && isscalar(v)
                t = string(v);
            elseif isnumeric(v)
                if isempty(v), t = "[]"; else, t = string(mat2str(v,6)); end
            else
                t = string(jsonencode(v));
            end
        end

        function t = pText(p)
            if isnan(p), t = "n/a"; elseif p < 0.001, t = "<0.001"; else, t = sprintf('%.3g',p); end
        end

        function x = blankLike(src,n)
            % n rows of src's type holding "nothing".
            w = size(src,2);
            if iscell(src), x = cell(n,w);
            elseif isstring(src), x = strings(n,w);
            elseif islogical(src), x = false(n,w);
            elseif isdatetime(src), x = NaT(n,w);
            elseif isfloat(src), x = NaN(n,w,'like',src);
            elseif isnumeric(src), x = zeros(n,w,'like',src);
            else, x = repmat(src([],:),n,1);
            end
        end
    end

    % =====================================================================
    %  Private helpers
    % =====================================================================
    methods (Access = private)
        function resetTables(obj)
            % Every table at its empty, typed shape.
            obj.Files              = table();
            obj.Conditions         = table();
            obj.Thresholds         = table();
            obj.Peaks              = table();
            obj.PeakOverrides      = mabr.analysis.Session.emptyPeakOverrides();
            obj.ManualRejections   = mabr.analysis.Session.emptyManualRejections();
            obj.DetectionOverrides = mabr.analysis.Session.emptyDetectionOverrides();
            obj.CurationArchive    = mabr.analysis.Session.emptyCurationArchive();
            obj.Messages           = mabr.analysis.Session.emptyMessages();
            obj.EditLog            = mabr.analysis.Session.emptyEditLog();
            obj.StepState          = mabr.analysis.Session.emptyStepState();
            obj.StepOptions        = struct();
            obj.Means              = mabr.analysis.Session.emptyMeans();
            obj.PendingMessages    = mabr.analysis.Session.emptyMessages();
        end

        % --- files ---------------------------------------------------------
        function [list,ids,bytes,modified] = listFiles(obj)
            % The files to read (matching FilePattern, by name within each
            % folder) and every .abr of the folders, for the fingerprint.
            list = strings(0,1);
            ids = strings(0,1);  bytes = zeros(0,1);  modified = NaT(0,1);
            for k = 1:numel(obj.Paths)
                folder = obj.Paths(k);
                d = dir(fullfile(char(folder),'*.abr'));
                d = d(~[d.isdir]);
                if isempty(d), continue; end
                names = string({d.name}).';
                [~,o] = sort(lower(names));
                d = d(o);  names = names(o);
                fname = mabr.analysis.Session.folderName(folder);
                ids      = [ids; fname + "/" + names]; %#ok<AGROW>
                bytes    = [bytes; reshape([d.bytes],[],1)]; %#ok<AGROW>
                modified = [modified; datetime(reshape([d.datenum],[],1),'ConvertFrom','datenum')]; %#ok<AGROW>
                keep = ~cellfun(@isempty,regexp(cellstr(names),char(obj.FilePattern),'once'));
                list = [list; string(fullfile({d(keep).folder},{d(keep).name})).']; %#ok<AGROW>
            end
        end

        function [F,pn,info] = filesTable(obj,recs)
            % Files from AbrFile records: Include rules, ParamNames, RunGroup,
            % Short. info: per-reason lists, for reportParse.
            n = numel(recs);
            col = @(f) reshape([recs.(f)],[],1);
            folders = col('Folder');
            names   = col('FileName');
            ids = strings(n,1);
            for i = 1:n
                ids(i) = mabr.analysis.Session.folderName(folders(i)) + "/" + names(i);
            end

            % ---- Include rules, in order; the first reason found stands.
            ok      = col('Ok');
            include = ok;
            reason  = strings(n,1);
            errs    = col('Error');
            reason(~ok) = errs(~ok);
            reason(~ok & reason == "") = "not readable";
            dupOf = strings(n,1);

            out = include & ismember(ids,obj.Exclude);
            include(out) = false;  reason(out) = "excluded by user";

            % The same recording in two folders of a pool: same name, sweeps,
            % samples and start. The later copy goes.
            starts = col('StartTime');
            nData  = round(col('Duration').*col('SampleRate'));
            sig = names + "|" + col('NumSweeps') + "|" + nData + "|" + ...
                string(mabr.analysis.Stats.isoTime(starts));
            for i = 2:n
                if ~include(i) || isnat(starts(i)), continue; end
                j = find(ok(1:i-1) & sig(1:i-1) == sig(i) & folders(1:i-1) ~= folders(i),1);
                if ~isempty(j)
                    include(i) = false;
                    reason(i)  = "duplicate of " + ids(j);
                    dupOf(i)   = ids(j);
                end
            end

            tm = col('TestMode');
            if any(include & ~tm)
                out = include & tm;
                include(out) = false;
                reason(out)  = "Test Mode (the stimulus, not a subject)";
            end

            fs = col('SampleRate');
            if any(include)
                rate = mode(fs(include));
                out = include & fs ~= rate;
                for i = find(out).'
                    reason(i) = sprintf("sample rate %g Hz differs from the session's %g Hz",fs(i),rate);
                end
                include(out) = false;
            end

            % ---- ParamNames: the included files' parameters, first seen
            % first; Stimulus in front when any included file names one.
            src = strings(1,0);
            for i = find(include).'
                src = [src setdiff(recs(i).ParamNames,src,'stable')]; %#ok<AGROW>
            end
            stim = col('Stimulus');
            hasStim = any(stim(include) ~= "");
            pn = src;
            renamed = strings(1,0);
            for j = 1:numel(pn)
                if any(strcmpi(pn(j),mabr.analysis.Session.FileColumns))
                    renamed(end+1) = pn(j); %#ok<AGROW>
                    pn(j) = "Stim_" + pn(j);
                end
            end
            if hasStim, pn = ["Stimulus" pn]; end

            % ---- The table: parameters first.
            F = table();
            if hasStim, F.Stimulus = stim; end
            for j = 1:numel(src)
                v = NaN(n,1);
                for i = 1:n
                    P = recs(i).Params;
                    if isfield(P,src(j)), v(i) = P.(src(j)); end
                end
                F.(pn(j + hasStim)) = v;
            end
            F.timestamp  = starts;
            F.fileName   = names;
            F.folder     = folders;
            F.nSweeps    = col('NumSweeps');
            F.SampleRate = fs;
            F.TestMode   = tm;
            F.FileId     = ids;
            if ~hasStim, F.Stimulus = stim; end
            F.StimID            = col('StimID');
            F.AcqMode           = col('AcqMode');
            F.Layout            = col('Layout');
            F.SweepLength       = col('SweepLength');
            F.AlternatePolarity = col('AlternatePolarity');
            F.Units             = col('Units');
            F.LevelUnit         = col('LevelUnit');
            F.Calibrated        = col('Calibrated');
            F.Bytes             = col('Bytes');
            F.Modified          = col('Modified');
            F.Duration          = col('Duration');
            F.MinISI            = col('MinISI');
            F.Era               = col('Era');
            F.TruncatedSweeps   = col('TruncatedSweeps');
            F.Include           = include;
            F.Reason            = reason;
            F.RunGroup          = mabr.analysis.Session.runGroups(F,ok,col('ParamText'),dupOf);
            F.Short             = mabr.analysis.Session.shortRuns(F);
            F.DuplicateOf       = dupOf;
            % Beyond the listed columns: what the units override and the
            % level reference need per file.
            F.AmplifierGain     = col('AmplifierGain');
            F.InputFullScale    = col('InputFullScale');
            F.CalibrationTime   = col('CalibrationTime');

            info = struct('Renamed',renamed);
        end

        function reportParse(obj,F,recs,info)
            % The parse messages: what was read, and why files were left out.
            n = height(F);
            obj.note('%d files in %s: %d included.',n,obj.Name,sum(F.Include));
            out = ~F.Include;
            if any(out)
                kind = regexprep(F.Reason(out),'^(duplicate of|sample rate).*$','$1');
                [u,~,j] = unique(kind,'stable');
                ids = F.FileId(out);
                why = F.Reason(out);
                for k = 1:numel(u)
                    m = find(j == k);
                    eg = reshape(ids(m(1:min(end,3))),1,[]);
                    if numel(m) > 3, eg(end+1) = "..."; end %#ok<AGROW>
                    if u(k) == "excluded by user"
                        obj.note('%d file(s) excluded by user: %s.',numel(m),strjoin(eg,', '));
                    else
                        obj.warn('%d file(s) left out -- %s: %s.',numel(m),why(m(1)),strjoin(eg,', '));
                    end
                end
            end
            if ~isempty(info.Renamed)
                obj.warn(['Stimulus parameter(s) %s read as Stim_<name>: the names are ' ...
                    'Files columns of their own.'],strjoin(info.Renamed,', '));
            end
            w = arrayfun(@(r) numel(r.Warnings),recs(:));
            if any(w(F.Include) > 0)
                k = find(F.Include & w > 0,1);
                obj.note('%d included file(s) were read with warnings (e.g. %s: %s).', ...
                    sum(w(F.Include) > 0),F.FileId(k),recs(k).Warnings(1));
            end
            if sum(F.Short) > 0
                obj.note('%d short run file(s) (under half their run''s median sweep count).',sum(F.Short));
            end
            [u,l] = mabr.analysis.Session.unitsOf(F.Units(F.Include),F.LevelUnit(F.Include));
            if u == "mixed"
                obj.warn('The included files disagree about units (%s).', ...
                    strjoin(reshape(unique(F.Units(F.Include)),1,[]),', '));
            end
            if l == "mixed"
                obj.warn('The included files disagree about the level reference (%s).', ...
                    strjoin(reshape(unique(F.LevelUnit(F.Include)),1,[]),', '));
            end
        end

        function checkFolderSubjects(obj,recs)
            % A pool whose folders' names give no subject: their files'
            % names must agree on one (or Force).
            folders = reshape([recs.Folder],[],1);
            uf = unique(folders,'stable');
            subj = strings(numel(uf),1);
            for k = 1:numel(uf)
                subj(k) = mabr.analysis.Session.dominantSubject(recs(folders == uf(k)));
            end
            have = unique(subj(subj ~= ""),'stable');
            if numel(have) > 1 && ~obj.ForceSubjects
                error('mabr:analysis:Session:mixedSubjects', ...
                    ['The files of these folders name different subjects (%s). Pass ' ...
                     'Force=true to pool them anyway.'],strjoin(reshape(have,1,[]),', '));
            end
        end

        function [u,l] = sessionUnits(obj,F)
            % The session's units and level reference over its included files.
            if height(F) == 0, u = ""; l = ""; return; end
            [u,l] = mabr.analysis.Session.unitsOf(F.Units(F.Include),F.LevelUnit(F.Include));
            if obj.overrideActive(), u = "V"; end
        end

        function tf = overrideActive(obj)
            o = obj.UnitOverride;
            tf = (isfield(o,'InputFullScale') && isfinite(o.InputFullScale)) || ...
                 (isfield(o,'AmplifierGain') && isfinite(o.AmplifierGain));
        end

        function s = unitScale(obj,row)
            % The factor UnitOverride puts on one file's trace:
            % (Gain_file/IFS_file)*(IFS_eff/Gain_eff), file values 1 when absent.
            s = 1;
            if ~obj.overrideActive(), return; end
            g = obj.Files.AmplifierGain(row);   if ~isfinite(g), g = 1; end
            i = obj.Files.InputFullScale(row);  if ~isfinite(i), i = 1; end
            ie = obj.UnitOverride.InputFullScale;  if ~isfinite(ie), ie = i; end
            ge = obj.UnitOverride.AmplifierGain;   if ~isfinite(ge), ge = g; end
            s = (g/i)*(ie/ge);
        end

        function [trace,sw,why] = traceFor(obj,row)
            % One file's raw trace and sweeps, from the cache or from disk.
            trace = [];  sw = [];  why = "";
            if numel(obj.Traces) >= row && ~isempty(obj.Traces{row}) ...
                    && numel(obj.FileSweeps) >= row && ~isempty(obj.FileSweeps{row})
                trace = obj.Traces{row};
                sw    = obj.FileSweeps{row};
                return
            end
            ffn = fullfile(obj.Files.folder(row),obj.Files.fileName(row));
            [rec,tr,s] = mabr.analysis.AbrFile.read(ffn,ReadTrace=true);
            if ~rec.Ok
                why = rec.Error;
                return
            end
            trace = tr;  sw = s;
            if obj.KeepTraces
                obj.Traces{row}     = tr;
                obj.FileSweeps{row} = s;
            end
        end

        function T = fileKeyTable(obj,rows,pool)
            % The key columns of these Files rows (AcqMode "pooled" when pooling).
            T = table();
            for kp = obj.KeyParams
                if kp == "AcqMode"
                    v = obj.Files.AcqMode(rows);
                    if pool, v(:) = "pooled"; end
                    T.AcqMode = v;
                else
                    T.(kp) = obj.Files.(kp)(rows);
                end
            end
        end

        % --- sweeps -------------------------------------------------------
        function [rej,reason] = applyManual(obj,rej,reason,fileRows,sweepIdx)
            % ManualRejections over one condition's sweeps: a hand decision
            % wins both ways (Reject=false restores a rig or criterion flag).
            MR = obj.ManualRejections;
            if height(MR) == 0 || isempty(rej), return; end
            ids = obj.Files.FileId(fileRows(:));
            k  = ids + "#" + string(sweepIdx(:));
            mk = MR.FileId + "#" + string(MR.SweepIndex);
            [mk,last] = unique(mk,'last');          % last write wins
            v = MR.Reject(last);
            [tf,loc] = ismember(k,mk);
            if ~any(tf), return; end
            vv = v(loc(tf));
            rej(tf) = vv;
            rs = reason(tf);
            rs(vv) = 3;
            rs(~vv) = 0;
            reason(tf) = rs;
        end

        function f = rigFlags(obj,C,r)
            % The rig's own verdict on each sweep of condition r.
            n = numel(C.Rejected{r});
            f = false(1,n);
            rows = C.SweepFile{r};
            idx  = C.SweepIndex{r};
            if numel(obj.FileSweeps) < max([rows 0])
                f = C.RejectReason{r} == 1;     % no raw files: the reasons say
                return
            end
            for row = unique(rows)
                sw = obj.FileSweeps{row};
                m = rows == row;
                if isempty(sw), continue; end
                [tf,loc] = ismember(idx(m),sw.Index);
                v = false(1,sum(m));
                v(tf) = sw.IsArtifact(loc(tf));
                f(m) = v;
            end
        end

        function [K,mode,seed] = capSettings(obj)
            % The sweep cap segment last used.
            K = Inf;  mode = "first";  seed = 1;
            if isfield(obj.StepOptions,'segment')
                s = obj.StepOptions.segment;
                if isfield(s,'MaxSweepsPerCondition'), K = s.MaxSweepsPerCondition; end
                if isfield(s,'EqualizeMode'), mode = s.EqualizeMode; end
                if isfield(s,'Seed'), seed = s.Seed; end
            end
        end

        function [X,pol,str] = cleanSweeps(obj,r)
            % Condition r's clean sweeps, their polarities and source files.
            C = obj.Conditions;
            use = ~C.Rejected{r} & ~C.Excess{r};
            X   = C.Sweeps{r}(:,use);
            pol = C.Polarity{r}(use);
            str = C.SweepFile{r}(use);
        end

        function D = applyDetectionOverrides(obj,C)
            % Detected: the automatic verdict (DetectedAuto -- the threshold
            % method's, or the permutation test's), unless a hand verdict
            % replaces it.
            v = string(C.Properties.VariableNames);
            if ismember("DetectedAuto",v)
                D = C.DetectedAuto;
            elseif ismember("isSig",v)
                D = C.isSig;
            else
                D = false(height(C),1);
            end
            O = obj.DetectionOverrides;
            if height(O) == 0, return; end
            [tf,loc] = ismember(C.Key,O.Key);
            v = O.Value(loc(tf));
            set = ~isnan(v);
            rows = find(tf);
            D(rows(set)) = v(set) ~= 0;
        end

        function rows = targetRows(obj,keys)
            % Conditions rows of keys (all rows when keys is empty).
            if isempty(keys)
                rows = (1:height(obj.Conditions)).';
            else
                rows = obj.rowOf(unique(keys,'stable'));
                rows = rows(:);
            end
        end

        function r = rowIndex(obj,row)
            % A Conditions row from a row number or a key.
            if isstring(row) || ischar(row)
                r = obj.rowOf(string(row));
            else
                r = row;
                if ~(isscalar(r) && r >= 1 && r <= height(obj.Conditions) && r == round(r))
                    error('mabr:analysis:Session:noSuchRow', ...
                        'Row %s: there are %d conditions.',mat2str(row),height(obj.Conditions));
                end
            end
        end

        function m = whereMask(obj,where)
            % Conditions rows matching a struct of column = values.
            C = obj.Conditions;
            m = true(height(C),1);
            fn = fieldnames(where);
            for i = 1:numel(fn)
                if ~ismember(fn{i},C.Properties.VariableNames)
                    error('mabr:analysis:Session:noSuchParam','"%s" is not a condition column.',fn{i});
                end
                m = m & mabr.analysis.Session.matches(C.(fn{i}),where.(fn{i}));
            end
        end

        % --- series -------------------------------------------------------
        function cols = seriesColumns(obj)
            % The columns a series shares: GroupParams of the last threshold
            % estimate, else every key column but the level.
            if ~isempty(obj.GroupParams)
                cols = obj.GroupParams;
            else
                cols = setdiff(obj.KeyParams,obj.levelParamOrEmpty(),'stable');
            end
            if height(obj.Conditions) > 0
                cols = cols(ismember(cols,string(obj.Conditions.Properties.VariableNames)));
            end
        end

        function sk = conditionSeriesKeys(obj)
            % The series key of every condition.
            cols = obj.seriesColumns();
            sk = mabr.analysis.Session.keyText(obj.Conditions,cols);
        end

        function tf = poolsAcqModes(obj)
            % Whether segment pooled the acquisition modes (PoolAcqModes), as
            % its options say, or as the conditions show (every AcqMode
            % "pooled": a session read back from results).
            tf = false;
            so = obj.StepOptions;
            if isfield(so,'segment') && isfield(so.segment,'PoolAcqModes')
                tf = logical(so.segment.PoolAcqModes);
            elseif height(obj.Conditions) > 0 && ...
                    ismember('AcqMode',obj.Conditions.Properties.VariableNames)
                tf = all(obj.Conditions.AcqMode == "pooled");
            end
        end

        function s = conditionList(obj,keys)
            % Conditions named for a message: "8 kHz, 0 dB; 8 kHz, 20 dB"
            % (conditionLabel), the first six and "and n more".
            keys = reshape(string(keys),[],1);
            lab = strings(numel(keys),1);
            for i = 1:numel(keys)
                try
                    lab(i) = obj.conditionLabel(keys(i));
                catch
                    lab(i) = keys(i);
                end
            end
            nShow = min(numel(lab),6);
            s = strjoin(lab(1:nShow),"; ");
            if numel(lab) > nShow
                s = s + sprintf(" and %d more",numel(lab) - nShow);
            end
        end

        function tf = multipleAcqModes(obj)
            tf = height(obj.Conditions) > 0 && ...
                ismember('AcqMode',obj.Conditions.Properties.VariableNames) && ...
                numel(unique(obj.Conditions.AcqMode)) > 1;
        end

        function v = numericVarying(obj)
            % varyingParams() that are numbers (a level axis cannot be text).
            v = obj.varyingParams();
            keep = false(size(v));
            for k = 1:numel(v)
                c = obj.Conditions.(v(k));
                keep(k) = isnumeric(c) || islogical(c);
            end
            v = v(keep);
        end

        function pn = matchParam(obj,aliases)
            % aliases: candidate names to match against obj.ParamNames
            % (case-insensitive). pn: (returned) the first matching name in
            % obj.ParamNames, or "" when none match.
            pn = "";
            for a = aliases
                k = find(strcmpi(obj.ParamNames,a),1);
                if ~isempty(k), pn = obj.ParamNames(k); return; end
            end
        end

        function u = levelUnitText(obj)
            % The level reference to print on an axis: the session's own
            % ("dB SPL" only for calibrated files), "dB" when unknown.
            u = obj.LevelUnit;
            if u == "" || u == "mixed", u = "dB"; end
        end

        function s = axisLabel(obj,pn)
            % A parameter's axis label, with the unit the toolbox fixes by
            % name end to end (see mabr.stim.StimulusSet.paramUnit) -- and a
            % level in the session's own reference: "dB SPL" only when the
            % files are calibrated.
            %
            %   pn  parameter name (matched case-insensitively against
            %       LevelAliases/FrequencyAliases)
            %   s   (returned) 1x1 string, e.g. "Level (dB SPL)", or "" when pn is ""
            if pn == "", s = ""; return; end
            if any(strcmpi(pn,mabr.analysis.Session.LevelAliases))
                s = pn + " (" + obj.levelUnitText() + ")";
            elseif any(strcmpi(pn,mabr.analysis.Session.FrequencyAliases))
                s = pn + " (kHz)";
            else
                s = pn;
            end
        end

        function s = processingSummary(~,Cn,f,opts,win,Fs,subset,nTotal)
            % The segment message: conditions, sweeps and how each was processed.
            nW = sum(Cn.Processing == "windowed");
            nC = sum(Cn.Processing == "continuous");
            if subset
                s = sprintf('%d of %d conditions re-segmented, %d sweeps, %.1f ms window at %g Hz', ...
                    height(Cn),nTotal,sum(Cn.nSweeps),diff(win),Fs);
            else
                s = sprintf('%d conditions, %d sweeps, %.1f ms window at %g Hz', ...
                    height(Cn),sum(Cn.nSweeps),diff(win),Fs);
            end
            parts = strings(1,0);
            if nC > 0, parts(end+1) = sprintf('%d continuous (%s)',nC,f.describe()); end
            if nW > 0
                e = Cn.Extent(Cn.Processing == "windowed",:);
                e = e(all(isfinite(e),2),:);
                hold = "";
                if ~isempty(e)
                    hold = sprintf(', holding %.1f-%.1f ms',min(e(:,1)),max(e(:,2)));
                end
                parts(end+1) = sprintf('%d windowed (%s%s)',nW, ...
                    f.describeWindowed(Order=opts.WindowedOrder,PadMode=opts.PadMode),hold);
            end
            if ~isempty(parts), s = s + "; " + strjoin(parts,"; "); end
            s = s + ".";
            if all(ismember(["conventional","interleaved"],Cn.AcqMode))
                s = s + " Conventional and interleaved runs are separate conditions; " + ...
                    "segment(PoolAcqModes=true) pools them.";
            end
        end

        % --- persistence ----------------------------------------------------
        function P = provenance(obj)
            P = struct('AnalyzedAt',mabr.analysis.Stats.isoTime(datetime('now')), ...
                'MATLABVersion',string(version), ...
                'MABRVersion',mabr.analysis.Session.mabrVersion(), ...
                'Host',string(getenv('COMPUTERNAME')), ...
                'User',obj.Analyst, ...
                'SettingsHash',"");
            if ~isempty(obj.Settings) && isobject(obj.Settings) && ismethod(obj.Settings,'hash')
                try
                    P.SettingsHash = string(obj.Settings.hash());
                catch
                end
            end
        end

        function S = summaryStruct(obj)
            C = obj.Conditions;
            nSw = 0;  nRj = 0;
            if ismember('nSweeps',C.Properties.VariableNames), nSw = sum(C.nSweeps); end
            if ismember('nRejected',C.Properties.VariableNames), nRj = sum(C.nRejected); end
            wd = "";
            if ismember('Processing',C.Properties.VariableNames) && any(C.Processing == "windowed")
                [n,pm] = deal(2,"reflect");
                if isfield(obj.StepOptions,'segment')
                    n = obj.StepOptions.segment.WindowedOrder;
                    pm = obj.StepOptions.segment.PadMode;
                end
                wd = obj.Filter.describeWindowed(Order=n,PadMode=pm);
            end
            hasCompact = ismember('Layout',obj.Files.Properties.VariableNames) && ...
                any(obj.Files.Layout(obj.Files.Include) == "compact");
            S = struct();
            S.Key            = obj.Key;
            S.Keys           = obj.FolderKeys;
            S.Paths          = obj.Paths;
            S.Name           = obj.Name;
            S.Subject        = obj.Subject;
            S.SubjectRaw     = obj.SubjectRaw;
            S.Date           = mabr.analysis.Stats.isoTime(obj.Date);
            S.SampleRate     = obj.SampleRate;
            S.Window         = obj.Window;
            S.ResponseWindow = obj.ResponseWindow;
            S.BaselineWindow = obj.baselineWindow();
            S.Time           = obj.Time;
            S.ParamNames     = obj.ParamNames;
            S.KeyParams      = obj.KeyParams;
            S.LevelParam     = obj.LevelParam;
            S.GroupParams    = obj.GroupParams;
            S.TestMode       = obj.TestMode;
            S.Units          = obj.Units;
            S.LevelUnit      = obj.LevelUnit;
            S.AcqModes       = obj.AcqModes;
            S.DataFingerprint = obj.DataFingerprint;
            S.NumFiles       = height(obj.Files);
            S.NumConditions  = height(C);
            S.NumSweeps      = nSw;
            S.NumRejected    = nRj;
            S.FilterDescription   = obj.Filter.describe();
            S.WindowedDescription = wd;
            S.HasCompact     = hasCompact;
            S.Exclude        = obj.Exclude;
            S.UnitOverride   = obj.UnitOverride;
            S.TimeOffset     = obj.TimeOffset;
            S.ConductionDelayOverride = obj.ConductionDelayOverride;
            S.LatencyOffset  = obj.LatencyOffset;
        end

        function w = baselineWindow(obj)
            w = [-10 0];
            s = obj.Settings;
            try
                if ~isempty(s) && (isstruct(s) || isobject(s)) && isfield_or_prop(s,'BaselineWindow')
                    w = double(s.BaselineWindow);
                end
            catch
            end
            function tf = isfield_or_prop(s,f)
                if isstruct(s), tf = isfield(s,f); else, tf = isprop(s,f); end
            end
        end

        function M = meansStruct(obj)
            % Means of every condition from its clean sweeps (or the means a
            % results-only session carries).
            C = obj.Conditions;
            nC = height(C);
            if nC == 0
                M = mabr.analysis.Session.emptyMeans();
                return
            end
            if ~obj.HasSweeps || ~ismember('Sweeps',C.Properties.VariableNames)
                M = obj.Means;
                return
            end
            nT = numel(obj.Time);
            [B,P,Q,S] = deal(NaN(nT,nC));
            N = zeros(nC,1);
            for c = 1:nC
                [X,pol,str] = obj.cleanSweeps(c);
                N(c) = size(X,2);
                if N(c) == 0, continue; end
                [B(:,c),S(:,c)] = mabr.analysis.Stats.balancedMean(X,pol,str);
                if any(pol > 0), P(:,c) = mean(X(:,pol > 0),2); end
                if any(pol < 0), Q(:,c) = mean(X(:,pol < 0),2); end
            end
            % Doubles, as computed: a session opened from its results picks
            % its peaks from these, and stored in single precision they put
            % ~1e-8 ms between those picks and the ones the same analysis
            % makes from the raw files -- enough for a replication script to
            % report differences where there are none. (A file written
            % before holds singles; every reader takes double() of them.)
            M = struct('Keys',C.Key,'Balanced',B,'Positive',P, ...
                'Negative',Q,'SEM',S,'N',N);
        end

        function I = sweepInfoStruct(obj)
            % Every condition's per-sweep columns as flat vectors.
            C = obj.Conditions;
            names = string(C.Properties.VariableNames);
            if height(C) == 0 || ~all(ismember(["Rejected","Polarity","SweepFile"],names))
                z = zeros(0,1);
                I = struct('Cond',uint16(z),'File',uint16(z),'Index',uint32(z),'Order',uint32(z), ...
                    'Time',single(z),'Polarity',int8(z),'Rejected',false(0,1),'Reason',uint8(z), ...
                    'Excess',false(0,1),'RMS',single(z),'P2P',single(z),'MaxAbs',single(z), ...
                    'BaselineRMS',single(z),'TemplateAmp',single(z),'TemplateR',single(z));
                return
            end
            nC = height(C);
            cnt = cellfun(@numel,C.Rejected);
            flat = @(name,cls) cast(reshape([C.(name){:}],[],1),cls);
            I = struct();
            I.Cond     = uint16(repelem((1:nC).',cnt));
            I.File     = flat('SweepFile','uint16');
            I.Index    = flat('SweepIndex','uint32');
            I.Order    = flat('SweepOrder','uint32');
            I.Time     = flat('SweepTime','single');
            I.Polarity = flat('Polarity','int8');
            I.Rejected = reshape(logical([C.Rejected{:}]),[],1);
            I.Reason   = flat('RejectReason','uint8');
            I.Excess   = reshape(logical([C.Excess{:}]),[],1);
            total = sum(cnt);
            feat = ["RMS","P2P","MaxAbs","BaselineRMS","TemplateAmp","TemplateR"];
            for f = feat, I.(f) = NaN(total,1,'single'); end
            if ismember("Features",names)
                at = [0; cumsum(cnt(:))];
                for c = 1:nC
                    Ft = C.Features{c};
                    if ~istable(Ft) || height(Ft) ~= cnt(c), continue; end
                    for f = feat
                        if ismember(f,string(Ft.Properties.VariableNames))
                            I.(f)(at(c)+1:at(c+1)) = single(Ft.(f));
                        end
                    end
                end
            end
        end

        function D = detectionStruct(obj)
            % The Detection records of every condition, without the null.
            C = obj.Conditions;
            if height(C) == 0 || ~ismember('Detection',C.Properties.VariableNames)
                D = mabr.analysis.Session.emptyDetection();
                return
            end
            D = repmat(mabr.analysis.Session.emptyDetection(),0,1);
            for c = 1:height(C)
                d = mabr.analysis.Session.flatDetection(C.Detection{c});
                d = rmfield(d,'null');
                d.t       = single(d.t);
                d.pSample = single(d.pSample);
                D(c,1) = d;
            end
        end

        function loadV2(obj,R)
            % A results-v2 struct onto this (empty) Session.
            S = struct();
            if isfield(R,'Summary') && isstruct(R.Summary), S = R.Summary; end
            obj.Key        = mabr.analysis.Session.field(S,'Key',"");
            obj.FolderKeys = reshape(mabr.analysis.Session.field(S,'Keys',strings(0,1)),[],1);
            obj.Paths      = reshape(string(mabr.analysis.Session.field(S,'Paths',strings(0,1))),[],1);
            if ~isempty(obj.Paths), obj.Path = obj.Paths(1); end
            obj.Name       = mabr.analysis.Session.field(S,'Name',"");
            obj.Subject    = mabr.analysis.Session.field(S,'Subject',"");
            obj.SubjectRaw = mabr.analysis.Session.field(S,'SubjectRaw',"");
            d = mabr.analysis.Session.field(S,'Date','');
            obj.Date = NaT;
            if ~isempty(d)
                try
                    obj.Date = datetime(char(d),'InputFormat','yyyy-MM-dd''T''HH:mm:ss');
                catch
                end
            end
            obj.SampleRate     = mabr.analysis.Session.field(S,'SampleRate',NaN);
            obj.Window         = mabr.analysis.Session.field(S,'Window',[-12 12]);
            obj.ResponseWindow = mabr.analysis.Session.field(S,'ResponseWindow',[0 10]);
            obj.Time           = mabr.analysis.Session.field(S,'Time',zeros(0,1));
            obj.ParamNames     = reshape(string(mabr.analysis.Session.field(S,'ParamNames',strings(1,0))),1,[]);
            kp = mabr.analysis.Session.field(S,'KeyParams',strings(1,0));
            if isempty(kp), kp = mabr.analysis.Session.keyParamsFor(obj.ParamNames); end
            obj.KeyParams      = reshape(string(kp),1,[]);
            obj.LevelParam     = mabr.analysis.Session.field(S,'LevelParam',"");
            obj.GroupParams    = reshape(string(mabr.analysis.Session.field(S,'GroupParams',strings(1,0))),1,[]);
            obj.TestMode       = mabr.analysis.Session.field(S,'TestMode',false);
            obj.Units          = mabr.analysis.Session.field(S,'Units',"");
            obj.LevelUnit      = mabr.analysis.Session.field(S,'LevelUnit',"");
            obj.AcqModes       = reshape(string(mabr.analysis.Session.field(S,'AcqModes',strings(1,0))),1,[]);
            obj.DataFingerprint = mabr.analysis.Session.field(S,'DataFingerprint',"");
            obj.Exclude        = reshape(string(mabr.analysis.Session.field(S,'Exclude',strings(0,1))),[],1);
            obj.UnitOverride   = mabr.analysis.Session.field(S,'UnitOverride', ...
                struct('InputFullScale',NaN,'AmplifierGain',NaN));
            obj.TimeOffset     = mabr.analysis.Session.field(S,'TimeOffset',NaN);
            obj.ConductionDelayOverride = mabr.analysis.Session.field(S,'ConductionDelayOverride',NaN);

            if isfield(R,'Files') && istable(R.Files), obj.Files = R.Files; end
            if isfield(R,'StepState') && isstruct(R.StepState)
                ss = mabr.analysis.Session.emptyStepState();
                for s = string(fieldnames(R.StepState)).'
                    ss.(s) = R.StepState.(s);
                end
                obj.StepState = ss;
            end
            if isfield(R,'StepOptions') && isstruct(R.StepOptions)
                obj.StepOptions = R.StepOptions;
                if isfield(R.StepOptions,'segment') && isfield(R.StepOptions.segment,'Filter')
                    try
                        % The bands come back, and are designed again at the
                        % session's rate -- firpm is deterministic, so this
                        % is the design the results were computed with.
                        f = mabr.analysis.Session.filterFromStruct(R.StepOptions.segment.Filter);
                        if isfinite(obj.SampleRate) && obj.SampleRate > 0
                            f = f.design(obj.SampleRate);
                        end
                        obj.Filter = f;
                    catch
                        % An unreadable filter record leaves the class default.
                    end
                end
            end
            if isfield(R,'Settings') && ~isempty(R.Settings)
                obj.Settings = R.Settings;
                if isstruct(R.Settings) && exist('mabr.analysis.Settings','class') == 8
                    try
                        obj.Settings = mabr.analysis.Settings.fromStruct(R.Settings);
                    catch
                    end
                end
            end

            % ---- Conditions, with the per-sweep cells rebuilt.
            C = table();
            if isfield(R,'Conditions') && istable(R.Conditions), C = R.Conditions; end
            nC = height(C);
            nT = numel(obj.Time);
            if nC > 0
                I = struct();
                if isfield(R,'SweepInfo'), I = R.SweepInfo; end
                cells = mabr.analysis.Session.sweepCells(I,nC);
                for v = mabr.analysis.Session.SweepColumns(2:end)
                    C.(v) = cells.(v);
                end
                if ~isempty(cells.Features), C.Features = cells.Features; end
                sw = repmat({[]},nC,1);
                hasSweeps = false;
                if isfield(R,'Sweeps') && iscell(R.Sweeps) && numel(R.Sweeps) == nC
                    sw = reshape(R.Sweeps,[],1);
                    hasSweeps = any(~cellfun(@isempty,sw));
                end
                C.Sweeps = sw;
                if isfield(R,'Detection') && isstruct(R.Detection) && numel(R.Detection) == nC
                    det = cell(nC,1);
                    for c = 1:nC
                        det{c} = mabr.analysis.Session.flatDetection(R.Detection(c));
                    end
                    C.Detection = det;
                end
                C = mabr.analysis.Session.canonicalConditions(C,obj.KeyParams);
                obj.HasSweeps = hasSweeps && nT > 0;
            end
            obj.Conditions = C;

            if isfield(R,'Means') && isstruct(R.Means), obj.Means = R.Means; end

            % ---- Thresholds and the edit tables.
            if isfield(R,'Thresholds') && istable(R.Thresholds)
                T = R.Thresholds;
                if ismember('Fit',T.Properties.VariableNames) && iscell(T.Fit)
                    for k = 1:height(T)
                        T.Fit{k} = mabr.analysis.Session.restorePredict(T.Fit{k});
                    end
                end
                obj.Thresholds = T;
            end
            tabs = ["CurationArchive","Peaks","PeakOverrides","ManualRejections", ...
                "DetectionOverrides","Messages","EditLog"];
            for t = tabs
                if isfield(R,t) && istable(R.(t)), obj.(t) = R.(t); end
            end
            obj.RawAvailable = false;
        end

        function loadV1(obj,R)
            % A results-v1 struct (one struct, Conditions with cells) onto this
            % Session, upgraded to the current shapes.
            if isfield(R,'Path'), obj.Path = string(R.Path); end
            if obj.Path ~= "", obj.Paths = obj.Path; end
            if isfield(R,'Name'), obj.Name = string(R.Name); end
            obj.Key = obj.Name;
            obj.FolderKeys = obj.Key;
            if isfield(R,'Subject'), obj.Subject = string(R.Subject); end
            if isfield(R,'Date') && isdatetime(R.Date), obj.Date = R.Date; end
            if isfield(R,'SampleRate'), obj.SampleRate = R.SampleRate; end
            if isfield(R,'Window'), obj.Window = R.Window; end
            if isfield(R,'ResponseWindow'), obj.ResponseWindow = R.ResponseWindow; end
            if isfield(R,'Time'), obj.Time = R.Time; end
            if isfield(R,'TestMode'), obj.TestMode = logical(R.TestMode); end
            pn = strings(1,0);
            if isfield(R,'ParamNames'), pn = reshape(string(R.ParamNames),1,[]); end
            obj.ParamNames = pn;
            obj.KeyParams  = mabr.analysis.Session.keyParamsFor(pn);

            % Files: the v1 columns, plus every column v2 has.
            F = table();
            if isfield(R,'Files') && istable(R.Files), F = R.Files; end
            n = height(F);
            if n > 0
                v = string(F.Properties.VariableNames);
                if ~ismember("FileId",v) && all(ismember(["folder","fileName"],v))
                    ids = strings(n,1);
                    for i = 1:n
                        ids(i) = mabr.analysis.Session.folderName(F.folder(i)) + "/" + string(F.fileName(i));
                    end
                    F.FileId = ids;
                end
                if ~ismember("AcqMode",v), F.AcqMode = repmat("conventional",n,1); end
                if ~ismember("Layout",v),  F.Layout = repmat("continuous",n,1); end
                if ~ismember("Include",v), F.Include = true(n,1); end
                if ~ismember("Reason",v),  F.Reason = strings(n,1); end
                F = mabr.analysis.Session.alignColumns(F,mabr.analysis.Session.emptyFiles(pn));
            end
            obj.Files = F;

            % Conditions.
            C = table();
            if isfield(R,'Conditions') && istable(R.Conditions), C = R.Conditions; end
            nC = height(C);
            hasSweeps = false;
            if nC > 0
                v = string(C.Properties.VariableNames);
                if ~ismember("AcqMode",v), C.AcqMode = repmat("conventional",nC,1); end
                if ismember("Stimulus",obj.KeyParams) && ~ismember("Stimulus",v)
                    C.Stimulus = strings(nC,1);
                end
                C.Key = mabr.analysis.Session.keyText(C,obj.KeyParams);
                if ismember("Sweeps",v)
                    hasSweeps = any(~cellfun(@isempty,C.Sweeps));
                    cnt = cellfun(@(x) size(x,2),C.Sweeps);
                elseif ismember("Rejected",v)
                    C.Sweeps = repmat({[]},nC,1);
                    cnt = cellfun(@numel,C.Rejected);
                else
                    C.Sweeps = repmat({[]},nC,1);
                    cnt = zeros(nC,1);
                    if ismember("nSweeps",v), cnt = C.nSweeps; end
                end
                for col = ["Rejected","Polarity","SweepFile"]
                    if ~ismember(col,v), C.(col) = cell(nC,1); end
                end
                [Rr,Si,So,St,Ex] = deal(cell(nC,1));
                for c = 1:nC
                    k = cnt(c);
                    if ~ismember("Rejected",v), C.Rejected{c} = false(1,k); end
                    if ~ismember("Polarity",v), C.Polarity{c} = ones(1,k); end
                    if ~ismember("SweepFile",v), C.SweepFile{c} = ones(1,k); end
                    rej = reshape(logical(C.Rejected{c}),1,[]);
                    C.Rejected{c} = rej;
                    Rr{c} = uint8(rej)*2;
                    sf = reshape(double(C.SweepFile{c}),1,[]);
                    si = zeros(1,k);
                    for row = unique(sf)
                        m = sf == row;
                        si(m) = 1:sum(m);
                    end
                    Si{c} = si;  So{c} = 1:k;  St{c} = NaN(1,k);  Ex{c} = false(1,k);
                end
                C.RejectReason = Rr;  C.SweepIndex = Si;  C.SweepOrder = So;
                C.SweepTime = St;  C.Excess = Ex;
                pol = C.Polarity;
                C.nSweeps   = cnt(:);
                C.nRejected = cellfun(@sum,C.Rejected);
                if ~ismember("nFiles",v), C.nFiles = cellfun(@(x) numel(unique(x)),C.SweepFile); end
                use = cellfun(@(r) ~r,C.Rejected,'UniformOutput',false);
                C.nClean = cellfun(@sum,use);
                C.nPos = cellfun(@(u,p) sum(u & reshape(p,1,[]) > 0),use,pol);
                C.nNeg = cellfun(@(u,p) sum(u & reshape(p,1,[]) < 0),use,pol);
                C.Processing = repmat("continuous",nC,1);
                if isempty(obj.Time)
                    C.Extent = NaN(nC,2);
                else
                    C.Extent = repmat([obj.Time(1) obj.Time(end)],nC,1);
                end
                C.Units = strings(nC,1);  C.LevelUnit = strings(nC,1);  C.Flags = strings(nC,1);
                if ismember("Detection",v)
                    for c = 1:nC
                        C.Detection{c} = mabr.analysis.Session.flatDetection(C.Detection{c});
                    end
                end
                if ismember("isSig",v)
                    C.DetectedAuto = C.isSig;
                    C.Detected = C.isSig;
                end
                C = mabr.analysis.Session.canonicalConditions(C,obj.KeyParams);
            end
            obj.Conditions = C;
            obj.HasSweeps = hasSweeps;

            % Thresholds: a Key per row, from its group columns.
            T = table();
            if isfield(R,'Thresholds') && istable(R.Thresholds), T = R.Thresholds; end
            if height(T) > 0
                v = string(T.Properties.VariableNames);
                it = find(v == "Threshold",1);
                grp = strings(1,0);
                if ~isempty(it), grp = v(1:it-1); end
                grp = grp(grp ~= "Key");
                % Every v1 file was a conventional run: the series carries
                % that constant, as a v2 series key would.
                if ~ismember("AcqMode",v) && ismember("AcqMode",obj.KeyParams)
                    T.AcqMode = repmat("conventional",height(T),1);
                    T = movevars(T,'AcqMode','Before',1);
                    grp = ["AcqMode" grp];
                end
                grp = mabr.analysis.Session.inKeyOrder(grp,obj.KeyParams);
                if ~ismember("Key",v)
                    T.Key = mabr.analysis.Session.keyText(T,grp);
                    T = movevars(T,'Key','Before',1);
                end
                obj.GroupParams = grp;
                if ismember("LevelParam",v) && height(T) > 0, obj.LevelParam = string(T.LevelParam(1)); end
                if ismember("Fit",v) && iscell(T.Fit)
                    for k = 1:height(T)
                        f = T.Fit{k};
                        if isstruct(f) && isscalar(f) && (~isfield(f,'Predict') || isempty(f.Predict))
                            T.Fit{k} = mabr.analysis.Session.restorePredict(f);
                        end
                    end
                end
            end
            obj.Thresholds = T;
            obj.RawAvailable = false;
        end

        % --- steps and messages --------------------------------------------
        function c = beginStep(obj,step)
            % Start collecting a step's messages; the returned onCleanup puts
            % the collection back as it was, so a step that fails or is
            % cancelled leaves Messages untouched.
            prevStep = obj.PendingStep;
            prevMsgs = obj.PendingMessages;
            obj.PendingStep = step;
            obj.PendingMessages = mabr.analysis.Session.emptyMessages();
            c = onCleanup(@() obj.endPending(prevStep,prevMsgs));
        end

        function endPending(obj,step,msgs)
            obj.PendingStep = step;
            obj.PendingMessages = msgs;
        end

        function commitMessages(obj,step,replace)
            % A step's collected messages into Messages -- replacing that
            % step's previous rows when it ran over everything.
            M = obj.Messages;
            if replace, M = M(M.Step ~= step,:); end
            obj.Messages = [M; obj.PendingMessages];
            obj.PendingMessages = mabr.analysis.Session.emptyMessages();
        end

        function clearStepStates(obj,from)
            % Invalidate the recorded state of step `from` and every later one.
            S = obj.StepState;
            k = find(mabr.analysis.Session.StepNames == from,1);
            for s = mabr.analysis.Session.StepNames(k:end), S.(s) = []; end
            obj.StepState = S;
        end

        function logEdit(obj,action,key,old,new)
            % One row of the audit trail.
            enc = @(v) string(jsonencode(v));
            obj.EditLog(end+1,:) = {datetime('now'),obj.Analyst,string(action),string(key), ...
                enc(old),enc(new)};
            obj.appendMessage("info",sprintf('%s %s: %s -> %s',action,key, ...
                mabr.analysis.Session.shortText(old),mabr.analysis.Session.shortText(new)),"edit");
        end

        function requireFiles(obj)
            if isempty(obj.Files) || height(obj.Files) == 0
                error('mabr:analysis:Session:noFiles','No files parsed. Call parse() first.');
            end
            if ~ismember('Include',obj.Files.Properties.VariableNames) || ~any(obj.Files.Include)
                error('mabr:analysis:Session:noFiles','None of the %d files is included.',height(obj.Files));
            end
        end

        function requireRaw(obj)
            if ~obj.RawAvailable
                error('mabr:analysis:Session:noRaw', ...
                    'This session holds results only; call loadRaw() to read its raw data.');
            end
        end

        function requireSweeps(obj)
            if ~obj.HasSweeps
                error('mabr:analysis:Session:noRaw', ...
                    'This session holds results only; call loadRaw() to read its sweeps.');
            end
        end

        function requireConditions(obj)
            % Throws mabr:analysis:Session:noConditions when segment() has
            % not been run yet. No inputs beyond obj, no return value.
            if isempty(obj.Conditions) || height(obj.Conditions) == 0
                error('mabr:analysis:Session:noConditions', ...
                    'No conditions. Call segment() first.');
            end
        end

        function requireThresholds(obj)
            % Throws mabr:analysis:Session:noThresholds when
            % estimateThresholds() has not been run yet. No inputs beyond
            % obj, no return value.
            if height(obj.Thresholds) == 0
                error('mabr:analysis:Session:noThresholds', ...
                    'No thresholds. Call estimateThresholds() first.');
            end
        end

        function note(obj,fmt,varargin)
            % An sprintf-style note: always a row of Messages, printed when
            % Verbose, heard by MessageFcn. No return value.
            obj.appendMessage("info",sprintf(fmt,varargin{:}));
        end

        function warn(obj,fmt,varargin)
            % note(), at level "warning" (printed to stderr when Verbose).
            obj.appendMessage("warning",sprintf(fmt,varargin{:}));
        end

        function appendMessage(obj,level,text,step)
            % One message row: to the step collecting messages, or straight
            % into Messages outside a step.
            text  = string(text);
            level = string(level);
            if nargin < 4
                step = obj.PendingStep;
                if step == "", step = "session"; end
            end
            row = {datetime('now'),level,string(step),text};
            if obj.PendingStep ~= "" && nargin < 4
                obj.PendingMessages(end+1,:) = row;
            else
                obj.Messages(end+1,:) = row;
            end
            if obj.Verbose
                if level == "info"
                    fprintf('  %s\n',text);
                else
                    fprintf(2,'  %s\n',text);
                end
            end
            if ~isempty(obj.MessageFcn)
                try
                    obj.MessageFcn(level,text);
                catch
                    % A display callback must never break the analysis.
                end
            end
        end
        % --- part B: state, cascade, options -------------------------------
        function B = stateBackup(obj)
            % Every property a composite edit may change, for stateRestore.
            B = struct();
            for p = mabr.analysis.Session.BackupProps
                B.(p) = obj.(p);
            end
        end

        function stateRestore(obj,B)
            % Put a stateBackup back: a composite edit that failed or was
            % cancelled leaves the session exactly as it was.
            for p = string(fieldnames(B)).'
                obj.(p) = B.(p);
            end
        end

        function runCascade(obj,keys,sks,from)
            % The steps after a data edit, each with its last options: reject
            % (from the rig's flags, then the criterion, then the hand
            % decisions) -> detect -> measure -> thresholds -> peaks. Steps
            % never run are skipped.
            order = ["reject","detect","measure","thresholds","peaks"];
            k0 = find(order == from,1);
            run = @(s) find(order == s,1) >= k0;
            SO = obj.StepOptions;
            cols = string(obj.Conditions.Properties.VariableNames);
            keys = keys(ismember(keys,obj.conditionKeysOrEmpty()));
            if run("reject") && ~isempty(keys) && obj.HasSweeps
                if isfield(SO,'reject')
                    a = obj.rejectArgs(SO.reject);
                    obj.reject(a{:},Keep=false,Keys=keys);
                else
                    obj.reject(Method="none",Keep=false,Keys=keys);
                end
            end
            if run("detect") && ~isempty(keys) && obj.HasSweeps && ismember("p",cols)
                a = {};
                if isfield(SO,'detect')
                    a = mabr.analysis.Session.namedArgs(SO.detect, ...
                        ["Method","NumPermutations","Alpha","MinClusterSize","Window","Seed","SeedMode"]);
                end
                obj.detect(a{:},Keys=keys);
            end
            if run("measure") && ~isempty(keys) && obj.HasSweeps && ismember("RN",cols)
                a = {};
                if isfield(SO,'measure')
                    a = mabr.analysis.Session.namedArgs(SO.measure,["ResponseWindow","BaselineWindow", ...
                        "SplitHalfMode","SplitHalfResamples","SplitHalfWindow","SplitHalfMinPerPolarity", ...
                        "NumPermutations","Seed","MaxLag","LevelDirection"]);
                end
                obj.measure(a{:},Keys=keys);
            end
            sks = unique(sks(sks ~= ""),'stable');
            if run("thresholds") && ~isempty(sks) && height(obj.Thresholds) > 0 && ...
                    ismember('Decision',obj.Thresholds.Properties.VariableNames)
                a = {};
                if isfield(SO,'thresholds')
                    a = mabr.analysis.Session.namedArgs(SO.thresholds, ...
                        setdiff(string(fieldnames(SO.thresholds)).',"SeriesKeys"));
                end
                obj.estimateThresholds(a{:},SeriesKeys=sks);
            end
            if run("peaks") && ~isempty(sks) && height(obj.Peaks) > 0
                a = obj.peakArgs();
                obj.pickPeaks(a{:},SeriesKeys=sks);
            end
        end

        function a = segmentArgs(obj,SO)
            % segment's options as it last ran (Filter: this session's).
            a = {'Window',obj.Window,'Filter',obj.Filter};
            if nargin < 2, SO = obj.StepOptions; end
            if isfield(SO,'segment')
                a = [a mabr.analysis.Session.namedArgs(SO.segment,["Window","HonorAcquisitionArtifacts", ...
                    "Detrend","Processing","WindowedOrder","PadMode","PoolAcqModes", ...
                    "MaxSweepsPerCondition","EqualizeMode","Seed"])];
            end
        end

        function a = rejectArgs(~,so)
            % reject's options as it last ran (Keep and Keys are the caller's).
            a = mabr.analysis.Session.namedArgs(so,["Feature","Method","Factor","UpperOnly", ...
                "Ceiling","Window","MethodArgs","Threshold"]);
        end

        function a = peakArgs(obj)
            % pickPeaks' options as it last ran (defaults when it has not).
            a = {};
            if isfield(obj.StepOptions,'peaks')
                a = mabr.analysis.Session.namedArgs(obj.StepOptions.peaks,["Waves","OctaveShift", ...
                    "RefFrequency","Smooth","MinSeparation","TrackEarly","TrackLate","CandidateRN", ...
                    "DetectableRN","Polarity","AboveThresholdOnly","BaselineAmpWindow","EdgeMs", ...
                    "Bootstrap","Seed","LatencyOffset"]);
            end
        end

        function off = peakOffset(obj,po)
            % The latency offset peaks were (or are to be) tracked with.
            off = NaN;
            if isfield(po,'LatencyOffset'), off = po.LatencyOffset; end
            if ~isfinite(off), off = obj.LatencyOffset; end
        end

        function o = latencyOffsetFor(obj,s)
            % LatencyOffset under the settings s (see the property's help).
            cd = obj.ConductionDelayOverride;
            if ~isfinite(cd), cd = mabr.analysis.Session.settingsDelay(s); end
            to = obj.TimeOffset;
            if ~isfinite(to), to = mabr.analysis.Session.settingsNumber(s,'TimeOffset',0); end
            o = cd + to;
        end

        % --- part B: keys -------------------------------------------------
        function k = conditionKeysOrEmpty(obj)
            k = strings(0,1);
            if height(obj.Conditions) > 0 && ismember('Key',obj.Conditions.Properties.VariableNames)
                k = obj.Conditions.Key;
            end
        end

        function sk = seriesOfKeys(obj,keys)
            % Series keys of condition keys, present or not: a key that is gone
            % still names its series (its series columns' parts of the key).
            keys = reshape(string(keys),[],1);
            sk = strings(numel(keys),1);
            if isempty(keys), return; end
            have = obj.conditionKeysOrEmpty();
            [tf,loc] = ismember(keys,have);
            if any(tf)
                every = obj.conditionSeriesKeys();
                sk(tf) = every(loc(tf));
            end
            cols = obj.seriesColumns();
            for i = find(~tf).'
                parts = split(keys(i),"|");
                names = extractBefore(parts,"=");
                keep = parts(ismember(names,cols));
                if isempty(keep), sk(i) = "(all)"; else, sk(i) = strjoin(keep,"|"); end
            end
            sk = unique(sk,'stable');
        end

        function keys = keysOfSweeps(obj,A,B)
            % Condition keys holding the sweeps on which two ManualRejections
            % tables disagree.
            ka = A.FileId + "#" + string(A.SweepIndex);  va = ka + "#" + string(A.Reject);
            kb = B.FileId + "#" + string(B.SweepIndex);  vb = kb + "#" + string(B.Reject);
            d = unique([ka(~ismember(va,vb)); kb(~ismember(vb,va))]);
            keys = strings(0,1);
            if isempty(d) || height(obj.Conditions) == 0, return; end
            C = obj.Conditions;
            for r = 1:height(C)
                s = obj.Files.FileId(C.SweepFile{r}(:)) + "#" + string(reshape(C.SweepIndex{r},[],1));
                if any(ismember(s,d)), keys(end+1,1) = C.Key(r); end %#ok<AGROW>
            end
        end

        function r = requireSeries(obj,seriesKey)
            % The Thresholds row of a series key, or an error.
            obj.requireThresholds();
            if ~ismember('Decision',obj.Thresholds.Properties.VariableNames)
                error('mabr:analysis:Session:oldThresholds', ...
                    'These thresholds predate curation by key; estimateThresholds() again.');
            end
            r = find(obj.Thresholds.Key == seriesKey,1);
            if isempty(r)
                error('mabr:analysis:Session:unknownKey','No threshold series "%s" in %s.',seriesKey,obj.Name);
            end
        end

        % --- part B: edits ------------------------------------------------
        function rep = decide(obj,seriesKey,decision,value,kind,action,note)
            % One curation decision on a series (see setDecision).
            r = obj.requireSeries(seriesKey);
            T = obj.Thresholds;
            oldTxt = mabr.analysis.SeriesThreshold.formatValue(T.Final(r),T.FinalCensored(r),T.FinalLo(r),T.FinalHi(r));
            oldDec = T.Decision(r);
            T.Decision(r)    = decision;
            T.ManualValue(r) = NaN;
            T.ManualKind(r)  = string(kind);
            if decision == "manual", T.ManualValue(r) = value; end
            if decision == ""
                T.ReviewedBy(r) = "";  T.ReviewedAt(r) = NaT;
                T.ReviewedValue(r) = NaN;  T.ReviewedMethod(r) = "";
            else
                T.ReviewedBy(r)     = obj.Analyst;
                T.ReviewedAt(r)     = datetime('now');
                T.ReviewedValue(r)  = T.Threshold(r);
                T.ReviewedMethod(r) = T.Method(r);
            end
            if ~(isscalar(note) && ismissing(note))
                T.Note(r) = string(note);
            end
            mask = false(height(T),1);  mask(r) = true;
            T = mabr.analysis.Session.refreshCuration(T,"",mask);
            newTxt = mabr.analysis.SeriesThreshold.formatValue(T.Final(r),T.FinalCensored(r),T.FinalLo(r),T.FinalHi(r));
            obj.Thresholds = T;
            obj.Peaks = obj.peaksBelow(obj.Peaks,seriesKey);
            obj.logEdit(action,seriesKey,oldDec + " " + oldTxt,decision + " " + newTxt);
            % In words, not the decision's token ("noresponse").
            switch decision
                case "noresponse", what = "no response";
                case "allrespond", what = "all levels respond";
                case "",           what = "no decision";
                otherwise,         what = decision;
            end
            rep = obj.report(action,seriesKey,oldTxt,newTxt, ...
                obj.seriesLabel(seriesKey) + ": " + what + ", threshold " + newTxt);
        end

        function rep = report(~,action,keys,before,after,text)
            % The report struct every edit returns (the GUI echoes Text).
            rep = struct('Action',string(action),'Keys',reshape(string(keys),[],1), ...
                'Before',{before},'After',{after},'Text',string(text));
        end

        function n = editCounts(obj)
            n = struct('ManualRejections',height(obj.ManualRejections), ...
                'DetectionOverrides',height(obj.DetectionOverrides), ...
                'PeakOverrides',height(obj.PeakOverrides),'Exclude',numel(obj.Exclude));
        end

        function N = snapshotNumbers(obj,keys,sks)
            % p of the conditions and Threshold/Final of the series an edit
            % touches, for its report.
            N = struct('Keys',keys,'p',NaN(numel(keys),1),'SeriesKeys',sks, ...
                'Threshold',NaN(numel(sks),1),'Final',NaN(numel(sks),1), ...
                'FinalText',strings(numel(sks),1));
            C = obj.Conditions;
            if ~isempty(keys) && height(C) > 0 && ismember('p',C.Properties.VariableNames)
                [tf,loc] = ismember(keys,C.Key);
                N.p(tf) = C.p(loc(tf));
            end
            T = obj.Thresholds;
            if ~isempty(sks) && height(T) > 0 && ismember('Final',T.Properties.VariableNames)
                [tf,loc] = ismember(sks,T.Key);
                N.Threshold(tf) = T.Threshold(loc(tf));
                N.Final(tf) = T.Final(loc(tf));
                N.FinalText(tf) = mabr.analysis.SeriesThreshold.formatValue(T.Final(loc(tf)), ...
                    T.FinalCensored(loc(tf)),T.FinalLo(loc(tf)),T.FinalHi(loc(tf)));
            end
        end

        function t = changeText(obj,a,b)
            % "Re-tested 8 kHz, 40 dB: p 0.03 -> 0.21; threshold 35 -> 42 dB".
            parts = strings(1,0);
            for i = 1:numel(a.Keys)
                if isequaln(a.p(i),b.p(i)), continue; end
                lab = a.Keys(i);
                try
                    lab = obj.conditionLabel(a.Keys(i));
                catch
                    % a condition that is gone keeps its key as its label
                end
                parts(end+1) = sprintf('Re-tested %s: p %s -> %s',lab, ...
                    mabr.analysis.Session.pText(a.p(i)),mabr.analysis.Session.pText(b.p(i))); %#ok<AGROW>
            end
            for i = 1:numel(a.SeriesKeys)
                if isequaln(a.Final(i),b.Final(i)) && a.FinalText(i) == b.FinalText(i), continue; end
                lab = a.SeriesKeys(i);
                try
                    lab = obj.seriesLabel(a.SeriesKeys(i));
                catch
                    % a series that is gone keeps its key as its label
                end
                parts(end+1) = sprintf('%s threshold %s -> %s %s',lab,a.FinalText(i),b.FinalText(i), ...
                    obj.levelUnitText()); %#ok<AGROW>
            end
            if isempty(parts)
                t = "No change in p or threshold.";
            else
                t = strjoin(parts,"; ") + ".";
            end
        end

        function [keys,before,after] = excludeFiles(obj,fileIds,tf,cascade)
            % Exclude (tf) or include fileIds, re-segment what they touch, and
            % (cascade) recompute it; the step states take the new fingerprint.
            rows = find(ismember(obj.Files.FileId,fileIds));
            C = obj.Conditions;
            oldKeys = strings(0,1);
            for r = 1:height(C)
                if any(ismember(C.SweepFile{r},rows)), oldKeys(end+1,1) = C.Key(r); end %#ok<AGROW>
            end
            pool = false;
            if isfield(obj.StepOptions,'segment') && isfield(obj.StepOptions.segment,'PoolAcqModes')
                pool = obj.StepOptions.segment.PoolAcqModes;
            end
            if tf
                obj.Exclude = unique([obj.Exclude; fileIds],'stable');
            else
                obj.Exclude = obj.Exclude(~ismember(obj.Exclude,fileIds));
            end
            pn0 = obj.ParamNames;
            obj.reinclude();
            inc = rows(obj.Files.Include(rows));
            newKeys = strings(0,1);
            if ~isempty(inc)
                newKeys = mabr.analysis.Session.keyText(obj.fileKeyTable(inc,pool),obj.KeyParams);
            end
            keys = unique([oldKeys; newKeys],'stable');
            sks = obj.seriesOfKeys(keys);
            before = obj.snapshotNumbers(keys,sks);
            if height(C) > 0 && obj.HasSweeps
                a = obj.segmentArgs();
                if ~isequal(pn0,obj.ParamNames)
                    obj.segment(a{:});
                    keys = obj.Conditions.Key;
                    sks = obj.seriesKeys();
                else
                    obj.segment(a{:},Keys=keys);
                end
                if cascade
                    obj.runCascade(keys,unique([sks; obj.seriesOfKeys(keys)],'stable'),"reject");
                end
            end
            after = obj.snapshotNumbers(keys,sks);
            S = obj.StepState;
            for s = mabr.analysis.Session.StepNames
                if isstruct(S.(s)) && isfield(S.(s),'Fingerprint')
                    S.(s).Fingerprint = obj.DataFingerprint;
                end
            end
            obj.StepState = S;
        end

        function reinclude(obj)
            % The inclusion rules again over the records parse read, after
            % Exclude changed: Files, the session facts that follow from it,
            % and the data fingerprint. Nothing is read from disk.
            recs = obj.Records;
            [F,pn] = obj.filesTable(recs);
            inc = F.Include;
            [units,levelUnit] = obj.sessionUnits(F);
            dt = F.timestamp(inc);
            d0 = NaT;
            if any(~isnat(dt)), d0 = min(dt(~isnat(dt))); end
            rate = NaN;
            if any(inc), rate = F.SampleRate(find(inc,1)); end
            obj.Files      = F;
            obj.ParamNames = pn;
            obj.KeyParams  = mabr.analysis.Session.keyParamsFor(pn);
            obj.SampleRate = rate;
            obj.Date       = d0;
            obj.TestMode   = any(F.TestMode(inc));
            obj.Units      = units;
            obj.LevelUnit  = levelUnit;
            obj.AcqModes   = mabr.analysis.Session.acqModesOf(F.AcqMode(inc));
            L = obj.FileList;
            if isstruct(L) && isfield(L,'Ids')
                obj.DataFingerprint = mabr.analysis.Session.fingerprintOf(L.Ids,L.Bytes,L.Modified,obj.Exclude);
            end
        end

        function fp = currentFingerprint(obj)
            % The fingerprint the folders give NOW (DataFingerprint when they
            % cannot be read).
            fp = obj.DataFingerprint;
            if isempty(obj.Paths) || ~all(arrayfun(@(p) isfolder(p),obj.Paths)), return; end
            try
                [~,ids,bytes,modified] = obj.listFiles();
                fp = mabr.analysis.Session.fingerprintOf(ids,bytes,modified,obj.Exclude);
            catch
            end
        end

        % --- part B: peaks ------------------------------------------------
        function lp = peakLevelParam(obj)
            % The level axis peaks are tracked along ("" when there is none).
            lp = obj.LevelParam;
            if lp == "" || height(obj.Conditions) == 0 || ...
                    ~ismember(lp,string(obj.Conditions.Properties.VariableNames))
                lp = obj.levelParamOrEmpty();
            end
            if lp ~= "" && height(obj.Conditions) > 0 && ...
                    ~ismember(lp,string(obj.Conditions.Properties.VariableNames))
                lp = "";
            end
        end

        function sg = loudnessSign(obj,lp,dirn)
            % +1 when a higher level is louder, -1 on an attenuation axis
            % (dirn when given, else the threshold step's LevelDirection,
            % else its "auto" rule: a level parameter named like
            % "Attenuation"). Peak tracking, "below", "loudest" and XCorrUp's
            % next-louder level read it. measure() takes dirn from analyze,
            % which measures before the threshold step has stored its own.
            if nargin < 3, dirn = ""; end
            sg = 1;
            dirn = string(dirn);
            if dirn == ""
                dirn = "auto";
                if isfield(obj.StepOptions,'thresholds') && isfield(obj.StepOptions.thresholds,'LevelDirection')
                    dirn = string(obj.StepOptions.thresholds.LevelDirection);
                end
            end
            if dirn == "descending"
                sg = -1;
            elseif dirn == "auto" && contains(lower(string(lp)),"attenuation")
                sg = -1;
            end
        end

        function [stim,freq] = stimulusOf(obj,r)
            % A condition's stimulus class and frequency (kHz; NaN for none).
            C = obj.Conditions;
            stim = "";
            if ismember('Stimulus',C.Properties.VariableNames), stim = string(C.Stimulus(r)); end
            freq = NaN;
            fp = "";
            try
                fp = obj.frequencyParam();
            catch
                % no level axis either: no frequency
            end
            if fp ~= "" && ismember(fp,string(C.Properties.VariableNames)) && isnumeric(C.(fp))
                freq = double(C.(fp)(r));
            end
        end

        function P = trackSeries(obj,sk,po,off,extra)
            % One series' picks (Peaks.track with the PeakOverrides of its
            % conditions -- and any extra anchors -- as anchors), in the
            % Peaks table's columns. BelowThreshold is left for peaksBelow.
            P = obj.emptyPeaks();
            lp = obj.peakLevelParam();
            ks = obj.seriesConditions(sk);
            if isempty(ks) || lp == "", return; end
            C  = obj.Conditions;
            rr = obj.rowOf(ks);
            rr = rr(:);
            levels = double(C.(lp)(rr));
            t  = obj.Time;
            nT = numel(t);
            nL = numel(rr);
            Y  = NaN(nT,nL);
            RN = NaN(nL,1);
            hasRN = ismember('RN',C.Properties.VariableNames);
            rwm = mabr.analysis.Artifacts.windowMask(t,obj.ResponseWindow);
            for i = 1:nL
                [m,sem] = obj.conditionMean(ks(i),po.Polarity);
                Y(:,i) = m;
                if hasRN
                    RN(i) = C.RN(rr(i));
                else
                    rows = rwm & isfinite(sem) & mabr.analysis.Session.extentMask(t,C.Extent(rr(i),:));
                    if any(rows), RN(i) = sqrt(mean(sem(rows).^2)); end
                end
            end
            [stim,freq] = obj.stimulusOf(rr(1));
            % In the recording's time: off (the latency offset) is the
            % LatencyOffset column below, never a move of the windows.
            W = mabr.analysis.Peaks.wavesFor(po.Waves,stim,freq,OctaveShift=po.OctaveShift, ...
                RefFrequency=po.RefFrequency);
            % Anchors: the hand edits, and (retrack) the picks it starts from.
            PO = obj.PeakOverrides;
            PO = PO(ismember(PO.Key,ks),:);
            [~,li] = ismember(PO.Key,ks);
            A = table(levels(li),PO.Wave,PO.Kind,PO.State,PO.Latency, ...
                'VariableNames',{'Level','Wave','Kind','State','Latency'});
            if ~isempty(extra) && height(extra) > 0
                ka = string(extra.Level) + "|" + extra.Wave + "|" + extra.Kind;
                kp = string(A.Level) + "|" + A.Wave + "|" + A.Kind;
                A = [extra(:,{'Level','Wave','Kind','State','Latency'}); A(~ismember(kp,ka),:)];
            end
            % Peaks.track goes loudest (highest level) first: an attenuation
            % axis is handed over negated, and the levels taken back after.
            sg = obj.loudnessSign(lp);
            A.Level = sg*A.Level;
            Tt = mabr.analysis.Peaks.track(t,Y,sg*levels,W,MinSeparation=po.MinSeparation, ...
                CandidateProminence=po.CandidateRN*RN,Smooth=po.Smooth, ...
                TrackEarly=po.TrackEarly,TrackLate=po.TrackLate,Anchors=A);
            n = height(Tt);
            if n == 0, return; end
            lv = sg*double(Tt.Level);
            idx = zeros(n,1);
            for j = 1:n
                if isnan(lv(j)), idx(j) = find(isnan(levels),1);
                else, idx(j) = find(levels == lv(j),1);
                end
            end
            r = rr(idx);
            P = table(C.Key(r),repmat(sk,n,1),'VariableNames',{'Key','SeriesKey'});
            for kp = obj.KeyParams
                P.(kp) = C.(kp)(r);
            end
            P.Level         = lv;
            P.Wave          = string(Tt.Wave);
            P.State         = string(Tt.State);
            P.TroughState   = string(Tt.TroughState);
            P.PeakLatency   = double(Tt.PeakLatency);
            P.PeakValue     = double(Tt.PeakValue);
            P.TroughLatency = double(Tt.TroughLatency);
            P.TroughValue   = double(Tt.TroughValue);
            bw = po.BaselineAmpWindow;
            brow = t >= bw(1) - 1e-9 & t <= bw(2) + 1e-9;
            base = NaN(nL,1);
            for i = 1:nL
                e = C.Extent(rr(i),:);
                if any(brow) && all(isfinite(e)) && e(1) <= bw(1) + 1e-9 && e(2) >= bw(2) - 1e-9 ...
                        && all(isfinite(Y(brow,i)))
                    base(i) = mean(Y(brow,i));
                end
            end
            P.Baseline      = base(idx);
            P.AmpPT         = P.PeakValue - P.TroughValue;
            P.AmpBP         = P.PeakValue - P.Baseline;
            P.AmpBT         = P.TroughValue - P.Baseline;
            P.Prominence    = double(Tt.Prominence);
            P.ProminenceRN  = P.Prominence./RN(idx);
            P.Detectable    = P.ProminenceRN >= po.DetectableRN;
            P.BelowThreshold = false(n,1);
            ext = C.Extent(r,:);
            win = C.Processing(r) == "windowed";
            P.EdgeAffected  = win & (P.PeakLatency < ext(:,1) + po.EdgeMs | P.PeakLatency > ext(:,2) - po.EdgeMs);
            P.LatencyMethod = repmat("parabolic",n,1);
            nanc = NaN(n,1);
            P.LatencySE = nanc;  P.LatencyCILo = nanc;  P.LatencyCIHi = nanc;
            P.AmpPTSE = nanc;  P.AmpPTCILo = nanc;  P.AmpPTCIHi = nanc;
            P.BootstrapUnstable = false(n,1);
            P.LatencyOffset = repmat(off,n,1);
            if po.Bootstrap > 0 && obj.HasSweeps
                for i = 1:nL
                    m = find(idx == i);
                    [X,pol,str] = obj.cleanSweeps(rr(i));
                    if size(X,2) < 2 || size(X,1) ~= nT, continue; end
                    Bt = mabr.analysis.Peaks.bootstrap(t,X,pol,str,P(m,{'Wave','PeakLatency','TroughLatency'}), ...
                        B=po.Bootstrap,Stream=mabr.analysis.Stats.conditionStream(po.Seed,ks(i)));
                    [ok,loc] = ismember(P.Wave(m),Bt.Wave);
                    mm = m(ok);  lc = loc(ok);
                    P.LatencySE(mm) = Bt.LatencySE(lc);    P.LatencyCILo(mm) = Bt.LatencyCILo(lc);
                    P.LatencyCIHi(mm) = Bt.LatencyCIHi(lc); P.AmpPTSE(mm) = Bt.AmpPTSE(lc);
                    P.AmpPTCILo(mm) = Bt.AmpPTCILo(lc);    P.AmpPTCIHi(mm) = Bt.AmpPTCIHi(lc);
                    P.BootstrapUnstable(mm) = Bt.Unstable(lc);
                end
            end
        end

        function P = emptyPeaks(obj)
            % A Peaks table with no rows and every column.
            P = table(strings(0,1),strings(0,1),'VariableNames',{'Key','SeriesKey'});
            for kp = obj.KeyParams
                if ismember(kp,["Stimulus","AcqMode"]), P.(kp) = strings(0,1); else, P.(kp) = zeros(0,1); end
            end
            z = zeros(0,1);  s = strings(0,1);  b = false(0,1);
            P.Level = z;  P.Wave = s;  P.State = s;  P.TroughState = s;
            P.PeakLatency = z;  P.PeakValue = z;  P.TroughLatency = z;  P.TroughValue = z;
            P.Baseline = z;  P.AmpPT = z;  P.AmpBP = z;  P.AmpBT = z;  P.Prominence = z;
            P.ProminenceRN = z;  P.Detectable = b;  P.BelowThreshold = b;  P.EdgeAffected = b;
            P.LatencyMethod = s;  P.LatencySE = z;  P.LatencyCILo = z;  P.LatencyCIHi = z;
            P.AmpPTSE = z;  P.AmpPTCILo = z;  P.AmpPTCIHi = z;  P.BootstrapUnstable = b;
            P.LatencyOffset = z;
        end

        function P = orderPeaks(obj,P)
            % Series in series order, loudest level first, waves in order.
            if height(P) == 0, return; end
            [~,si] = ismember(P.SeriesKey,obj.seriesKeys());
            si(si == 0) = numel(obj.seriesKeys()) + 1;
            lv = -obj.loudnessSign(obj.peakLevelParam())*P.Level;
            lv(isnan(lv)) = Inf;
            names = unique(P.Wave,'stable');
            if isfield(obj.StepOptions,'peaks') && isfield(obj.StepOptions.peaks,'Waves')
                wn = string({obj.StepOptions.peaks.Waves.Name});
                names = [wn(:); names(~ismember(names,wn))];
            end
            [~,wi] = ismember(P.Wave,names);
            [~,o] = sortrows([si lv wi (1:height(P)).']);
            P = P(o,:);
        end

        function P = peaksBelow(obj,P,sks)
            % BelowThreshold of the peaks of series sks ([] = all) from each
            % series' Final threshold.
            if height(P) == 0 || ~ismember('BelowThreshold',P.Properties.VariableNames), return; end
            if isempty(sks), m = true(height(P),1); else, m = ismember(P.SeriesKey,sks); end
            T = obj.Thresholds;
            hasF = height(T) > 0 && ismember('Final',T.Properties.VariableNames);
            for sk = reshape(unique(P.SeriesKey(m)),1,[])
                rows = m & P.SeriesKey == sk;
                b = false(sum(rows),1);
                if hasF
                    r = find(T.Key == sk,1);
                    if ~isempty(r)
                        dirn = "ascending";
                        f = T.Fit{r};
                        if isstruct(f) && isfield(f,'LevelDirection') && string(f.LevelDirection) == "descending"
                            dirn = "descending";
                        end
                        lv = P.Level(rows);
                        b = mabr.analysis.SeriesThreshold.belowThreshold(lv,T.Final(r), ...
                            T.FinalCensored(r),T.FinalLo(r),Direction=dirn,FinalHi=T.FinalHi(r));
                        b = reshape(b & ~isnan(lv),[],1);
                    end
                end
                P.BelowThreshold(rows) = b;
            end
        end

        function applyPeakEdit(obj,PO,keys,action,what,old,new)
            % New PeakOverrides, and the picks of the edited levels only
            % re-derived from them (the levels below are retrackSeries' job).
            bk = obj.stateBackup();
            try
                obj.PeakOverrides = PO;
                if height(obj.Peaks) > 0
                    po = mabr.analysis.Session.argsStruct(obj.peakArgs());
                    off = obj.peakOffset(po);
                    keys = reshape(string(keys),[],1);
                    sks = obj.seriesOfKeys(keys);
                    P = obj.Peaks;
                    for sk = reshape(sks,1,[])
                        New = obj.trackSeries(sk,po,off,[]);
                        drop = P.SeriesKey == sk & ismember(P.Key,keys);
                        P = [P(~drop,:); New(ismember(New.Key,keys),:)];
                    end
                    obj.Peaks = obj.peaksBelow(obj.orderPeaks(P),sks);
                end
            catch ME
                obj.stateRestore(bk);
                rethrow(ME);
            end
            obj.logEdit(action,strjoin(reshape(string(keys),1,[]),","),old,new);
            obj.appendMessage("info",sprintf('%s: %s',action,what),"edit");
        end

        function lat = snapLatency(obj,key,kind,lat,win)
            % The nearest local maximum (P) or minimum (N) of a condition's
            % mean within win ms of lat, refined parabolically; lat itself
            % when there is none.
            po = mabr.analysis.Session.argsStruct(obj.peakArgs());
            pol = "balanced";
            if isfield(po,'Polarity'), pol = po.Polarity; end
            m = obj.conditionMean(key,pol);
            t = obj.Time;
            if kind == "P", c = islocalmax(m); else, c = islocalmin(m); end
            c = c & isfinite(m) & abs(t - lat) <= win + 1e-9;
            if ~any(c)
                obj.note('No %s within %.2f ms of %.3f ms; the pick is placed as given.', ...
                    ifelse(kind == "P","peak","trough"),win,lat);
                return
            end
            idx = find(c);
            [~,j] = min(abs(t(idx) - lat));
            lat = mabr.analysis.Peaks.refine(t,m,idx(j));
        end

        % --- part B: threshold bootstrap -------------------------------------
        function YB = metricBootstrap(obj,idx,metric,B,seed)
            % [n x B] replicate values of a graded metric for the conditions
            % idx of one series: sweeps resampled within each file x polarity
            % group, the metric made again per replicate. [] when the sweeps
            % are not here or the metric cannot be bootstrapped this way.
            YB = [];
            if ~obj.HasSweeps || ~ismember(metric,["snr","splithalf","xcorr","dtw"]), return; end
            C = obj.Conditions;
            t = obj.Time;  nT = numel(t);
            rwm = mabr.analysis.Artifacts.windowMask(t,obj.ResponseWindow);
            n = numel(idx);
            YB = NaN(n,B);
            means = cell(n,1);
            K = [];
            if metric == "splithalf"
                kc = zeros(n,1);
                for i = 1:n
                    r = idx(i);
                    if C.nPos(r) > 0 && C.nNeg(r) > 0, kc(i) = floor(min(C.nPos(r),C.nNeg(r))/2);
                    else, kc(i) = floor(C.nClean(r)/2); end
                end
                % As measure() chooses it: levels too small for an r of their
                % own do not set the series' K.
                kMin = 25;
                if isfield(obj.StepOptions,'measure') && isfield(obj.StepOptions.measure,'SplitHalfMinPerPolarity')
                    kMin = obj.StepOptions.measure.SplitHalfMinPerPolarity;
                end
                kMin = max(1,kMin);
                if any(kc >= kMin), kc = kc(kc >= kMin); end
                K = min(kc);
            end
            for i = 1:n
                r = idx(i);
                [X,pol,str] = obj.cleanSweeps(r);
                if size(X,2) < 2 || size(X,1) ~= nT, continue; end
                rows = rwm & mabr.analysis.Session.extentMask(t,C.Extent(r,:)) & all(isfinite(X),2);
                rs = mabr.analysis.Stats.conditionStream(seed,C.Key(r) + "|bootstrap");
                g = string(str) + "|" + string(pol);
                [~,~,gi] = unique(g);
                M = NaN(nT,B);
                for b = 1:B
                    pick = zeros(1,size(X,2));
                    for q = 1:max(gi)
                        w = find(gi == q);
                        pick(w) = w(randi(rs,numel(w),1,numel(w)));
                    end
                    Xb = X(:,pick);
                    [m,sem] = mabr.analysis.Stats.balancedMean(Xb,pol(pick),str(pick));
                    M(:,b) = m;
                    switch metric
                        case "snr"
                            if any(rows)
                                mr = m(rows);
                                YB(i,b) = 10*log10(mean((mr - mean(mr)).^2)/mean(sem(rows).^2));
                            end
                        case "splithalf"
                            sh = mabr.analysis.SingleTrial.splitHalf(Xb,pol(pick),rows,K=K, ...
                                Resamples=25,Stream=rs,MinPerPolarity=0);
                            YB(i,b) = sh.Mean;
                    end
                end
                means{i} = M;
            end
            if ismember(metric,["xcorr","dtw"])
                lp = obj.LevelParam;
                if lp == "", lp = obj.levelParamOrEmpty(); end
                lev = obj.loudnessSign(lp)*double(C.(lp)(idx));
                dt = median(diff(t));
                maxLag = 0;
                if isfield(obj.StepOptions,'measure'), maxLag = round(obj.StepOptions.measure.MaxLag/dt); end
                for i = 1:n
                    louder = find(isfinite(lev) & lev > lev(i));
                    if isempty(louder) || isempty(means{i}), continue; end
                    [~,k] = min(lev(louder));
                    j = louder(k);
                    if isempty(means{j}), continue; end
                    for b = 1:B
                        if metric == "dtw"
                            YB(i,b) = mabr.analysis.SingleTrial.dtwUp(means{i}(:,b),means{j}(:,b),rwm,maxLag,dt);
                        else
                            YB(i,b) = mabr.analysis.SingleTrial.xcorrUp(means{i}(:,b),means{j}(:,b),rwm,maxLag,dt);
                        end
                    end
                end
            end
        end

        function v = overrideValues(obj,keys)
            % DetectionOverrides as one value per key (NaN = none).
            v = NaN(numel(keys),1);
            O = obj.DetectionOverrides;
            if height(O) == 0, return; end
            [tf,loc] = ismember(keys,O.Key);
            v(tf) = O.Value(loc(tf));
        end
    end

    properties (Access = private)
        ForceSubjects (1,1) logical = false   % the constructor's Force
    end

    methods (Static, Access = private)
        function v = field(S,name,default)
            % S.(name) when present, else default (string defaults coerce text).
            v = default;
            if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
                v = S.(name);
                if isstring(default), v = string(v); end
            elseif isstruct(S) && isfield(S,name) && isstring(default) && isempty(S.(name))
                v = default;
            end
        end

        function rg = runGroups(F,ok,paramText,dupOf)
            % RunGroup labels (see parse): within one Stimulus x AcqMode (and
            % Test Mode, and sample rate -- those are runs of their own), files
            % in start order form one run until a gap over RunGap s or a
            % condition repeats. A duplicate takes its original's group.
            n = height(F);
            rg = strings(n,1);
            idx = find(ok & dupOf == "");
            if isempty(idx), return; end
            fam = F.Stimulus(idx) + "|" + F.AcqMode(idx) + "|" + F.TestMode(idx) + "|" + F.SampleRate(idx);
            [uf,~,fi] = unique(fam,'stable');
            members = cell(0,1);  starts = NaT(0,1);
            for k = 1:numel(uf)
                rows = idx(fi == k);
                t = F.timestamp(rows);
                key = datenum(t); %#ok<DATNM>
                key(isnat(t)) = Inf;
                [~,o] = sortrows([key rows]);
                rows = rows(o);
                % The gap is from the END of the run so far (latest start +
                % duration) to this file's start: a long recording is not a
                % pause, and start-to-start would split a run of files each
                % longer than RunGap.
                seen = strings(0,1);  last = NaT;  cur = [];
                for r = rows(:).'
                    gap = seconds(F.timestamp(r) - last);
                    fresh = isempty(cur) || (~isnan(gap) && gap > mabr.analysis.Session.RunGap) ...
                        || any(seen == paramText(r));
                    if fresh
                        if ~isempty(cur)
                            members{end+1,1} = cur; %#ok<AGROW>
                            starts(end+1,1) = F.timestamp(cur(1)); %#ok<AGROW>
                        end
                        cur = r;  seen = paramText(r);
                    else
                        cur(end+1) = r; %#ok<AGROW>
                        seen(end+1) = paramText(r); %#ok<AGROW>
                    end
                    d = F.Duration(r);
                    if ~isfinite(d) || d < 0, d = 0; end
                    if fresh || isnat(last)
                        last = F.timestamp(r) + seconds(d);
                    elseif ~isnat(F.timestamp(r))
                        last = max(last,F.timestamp(r) + seconds(d));
                    end
                end
                members{end+1,1} = cur; %#ok<AGROW>
                starts(end+1,1) = F.timestamp(cur(1)); %#ok<AGROW>
            end
            nG = numel(members);
            hhmm = strings(nG,1);  hms = strings(nG,1);  labels = strings(nG,1);
            for g = 1:nG
                if isnat(starts(g))
                    hhmm(g) = "--:--";  hms(g) = "--:--:--";
                else
                    hhmm(g) = string(char(starts(g),'HH:mm'));
                    hms(g)  = string(char(starts(g),'HH:mm:ss'));
                end
            end
            for g = 1:nG
                r = members{g};
                stim = F.Stimulus(r(1));
                mode = F.AcqMode(r(1));
                parts = [stim mode];
                parts = parts(parts ~= "");
                labels(g,1) = join(parts," ") + " (" + numel(r) + " files)";
            end
            full = hhmm + " " + labels;
            [~,~,j] = unique(full);
            cnt = accumarray(j,1);
            dup = cnt(j) > 1;
            full(dup) = hms(dup) + " " + labels(dup);
            for g = 1:nG
                k = find(full(1:g-1) == full(g));
                if ~isempty(k), full(g) = full(g) + " #" + (numel(k) + 1); end
            end
            for g = 1:nG
                rg(members{g}) = full(g);
            end
            for i = find(ok & dupOf ~= "").'
                rg(i) = rg(find(F.FileId == dupOf(i),1));
            end
        end

        function s = shortRuns(F)
            % Short: under half the median sweep count of the included files
            % of the same Stimulus and AcqMode.
            n = height(F);
            s = false(n,1);
            idx = find(F.Include);
            if isempty(idx), return; end
            fam = F.Stimulus(idx) + "|" + F.AcqMode(idx);
            [~,~,fi] = unique(fam);
            for k = 1:max(fi)
                rows = idx(fi == k);
                med = median(F.nSweeps(rows));
                s(rows) = F.nSweeps(rows) < 0.5*med;
            end
        end

        function cells = sweepCells(I,nC)
            % The per-sweep cell columns of nC conditions from SweepInfo.
            names = mabr.analysis.Session.SweepColumns(2:end);
            for v = names, cells.(v) = cell(nC,1); end
            cells.Features = {};
            need = ["Cond","File","Index","Order","Time","Polarity","Rejected","Reason","Excess"];
            if ~isstruct(I) || ~all(isfield(I,need))
                for c = 1:nC
                    cells.Rejected{c} = false(1,0);  cells.RejectReason{c} = zeros(1,0,'uint8');
                    cells.Polarity{c} = zeros(1,0);  cells.SweepFile{c} = zeros(1,0);
                    cells.SweepIndex{c} = zeros(1,0);  cells.SweepOrder{c} = zeros(1,0);
                    cells.SweepTime{c} = zeros(1,0);  cells.Excess{c} = false(1,0);
                end
                return
            end
            cond = double(I.Cond(:));
            feat = ["RMS","P2P","MaxAbs","BaselineRMS","TemplateAmp","TemplateR"];
            hasFeat = all(isfield(I,feat)) && any(arrayfun(@(f) any(isfinite(I.(f)(:))),feat));
            if hasFeat, cells.Features = cell(nC,1); end
            % One pass: the sweeps of condition c are a contiguous block.
            [~,o] = sort(cond);
            cond = cond(o);
            edges = [0; find(diff(cond)); numel(cond)];
            blocks = cell(nC,1);
            for b = 1:numel(edges)-1
                k = o(edges(b)+1:edges(b+1));
                c = cond(edges(b)+1);
                if c >= 1 && c <= nC, blocks{c} = sort(k); end
            end
            for c = 1:nC
                k = blocks{c};
                if isempty(k), k = zeros(0,1); end
                cells.Rejected{c}     = reshape(logical(I.Rejected(k)),1,[]);
                cells.RejectReason{c} = reshape(uint8(I.Reason(k)),1,[]);
                cells.Polarity{c}     = reshape(double(I.Polarity(k)),1,[]);
                cells.SweepFile{c}    = reshape(double(I.File(k)),1,[]);
                cells.SweepIndex{c}   = reshape(double(I.Index(k)),1,[]);
                cells.SweepOrder{c}   = reshape(double(I.Order(k)),1,[]);
                cells.SweepTime{c}    = reshape(double(I.Time(k)),1,[]);
                cells.Excess{c}       = reshape(logical(I.Excess(k)),1,[]);
                if hasFeat
                    Ft = table();
                    for f = feat, Ft.(f) = double(I.(f)(k)); end
                    cells.Features{c} = Ft;
                end
            end
        end

        function v = mabrVersion()
            % The repository's short git commit, once per MATLAB session.
            persistent cached
            if isempty(cached)
                cached = "unknown";
                try
                    [st,out] = system(sprintf('git -C "%s" rev-parse --short HEAD',mabr.Config.root));
                    out = strtrim(string(out));
                    out = out(end);
                    if st == 0 && ~isempty(regexp(out,'^[0-9a-f]{4,40}$','once'))
                        cached = out;
                    end
                catch
                end
            end
            v = cached;
        end
    end
end

% =========================================================================
%  Local functions
% =========================================================================
function v = ifelse(c,a,b)
% a when c, else b (for one-line messages).
if c, v = a; else, v = b; end
end
