classdef Session < handle
% mabr.analysis.Session  One ABR session, loaded and reprocessed offline.
%
%   A Session is one folder of .abr files -- one animal, one sitting -- taken
%   from filenames on disk through to thresholds. It owns exactly that much:
%   there is nothing in here that loops over sessions, subjects or studies,
%   because a study is a loop you write, over an object that only ever has to
%   be right about one session:
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
%   The five steps, each of which is one method that does one thing:
%
%     parse()               read the filenames and each file's stimulus
%                           metadata into Files, one row per file
%     segment(...)          filter each whole trace, then window it into
%                           sweeps, grouped into Conditions -- one row per
%                           unique stimulus combination
%     reject(...)           flag artifact sweeps (flags, never deletions)
%     detect(...)           permutation-test each condition for a response
%     estimateThresholds()  fit a threshold per frequency from those detections
%
%   estimateThresholds(FitTarget="binary") is the detection threshold -- the
%   level at which a response appears. Left on "auto" a sigmoid or isotonic fit
%   is given the graded detection strength instead, where Criterion = 0.5 is
%   the half-maximum of the growth function and therefore a larger number. See
%   mabr.analysis.Threshold for why both exist.
%
%   Everything each of them does to ONE condition lives in a separate class
%   and can be called on its own: mabr.analysis.Filter, .Artifacts, .PermTest,
%   .Threshold, .Plot. Session is the orchestration, not the arithmetic.
%
%   CONDITIONS ARE A TABLE, not an N-D cell array. One row per condition, with
%   a column per stimulus parameter, which is what lets a bank vary three
%   things without anybody hard-coding which two they were. grid() reshapes to
%   the [level x frequency] cell array and U struct the older functions use,
%   for the plotting and threshold code that wants it:
%
%       [S,U] = s.grid("Level","Frequency");
%
%   FLAGGED SWEEPS ARE KEPT. Rejection writes a logical per sweep and nothing
%   more; sweeps() and every average exclude them by default, and asking for
%   them back is one argument away. This is the same rule the acquisition side
%   follows (mabr.data.Recording.IsArtifact), and it is what makes a rejection
%   setting something you can change your mind about without reloading.
%
%   Filtering is applied to the WHOLE continuous trace before segmentation,
%   never to the sweeps: a sweep is a few hundred samples and a filter's edge
%   transient would land on the response itself.
%
%   See also mabr.analysis.Filter, mabr.analysis.Artifacts,
%   mabr.analysis.Threshold, mabr.analysis.Plot, mabr.data.io

    properties (SetAccess = protected)
        Path    (1,1) string = ""       % folder this session was read from
        Name    (1,1) string = ""       % folder name
        Subject (1,1) string = ""       % subject token, if the names carry one
        Date    (1,1) datetime = NaT    % earliest file timestamp

        Files      table = table()      % one row per .abr file
        Conditions table = table()      % one row per stimulus condition
        Thresholds table = table()      % one row per threshold series

        SampleRate (1,1) double = NaN   % Hz, ADC rate of the loaded files
        Window     (1,2) double = [-12 12]   % ms, segmentation window
        Time       (:,1) double = []    % ms, one entry per sweep sample
        ParamNames (1,:) string = string.empty  % stimulus parameters found
        TestMode   (1,1) logical = false        % any file recorded in Test Mode
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

        % Print progress.
        Verbose (1,1) logical = true
    end

    properties (Dependent)
        NumFiles      (1,1) double
        NumConditions (1,1) double
        ResponseRows  (:,1) logical    % Time mask for ResponseWindow
    end

    properties (Access = private)
        Traces cell = {}               % cached full traces, one per file
        Onsets cell = {}               % cached sweep onsets, one per file
    end

    properties (Constant)
        % Column names Session reserves in the Conditions table; a stimulus
        % parameter of the same name would collide with one.
        Reserved = ["Sweeps","Rejected","Polarity","SweepFile","nSweeps", ...
                    "nRejected","nFiles","p","isSig","strength","Detection"]

        % Parameter names recognized as the level and frequency axes when a
        % caller does not say. Case is ignored.
        LevelAliases     = ["Level","SoundLevel","Intensity","dB","Attenuation"]
        FrequencyAliases = ["Frequency","Freq","CF","Carrier"]

        Version = 1     % results file format
    end

    methods
        % =================================================================
        %  Construction
        % =================================================================
        function obj = Session(sessionPath,opts)
            % Session(path,Name=Value) reads the file list and metadata.
            arguments
                sessionPath (1,1) string = ""
                opts.FilePattern (1,1) string = "\.abr$"
                opts.Filter = []
                opts.Window (1,2) double = [-12 12]
                opts.ResponseWindow (1,2) double = [0 10]
                opts.KeepTraces (1,1) logical = true
                opts.Verbose (1,1) logical = true
                opts.Parse (1,1) logical = true
            end
            obj.FilePattern    = opts.FilePattern;
            obj.Window         = sort(opts.Window);
            obj.ResponseWindow = sort(opts.ResponseWindow);
            obj.KeepTraces     = opts.KeepTraces;
            obj.Verbose        = opts.Verbose;
            if ~isempty(opts.Filter), obj.Filter = opts.Filter; end

            if sessionPath == "", return; end
            obj.Path = string(sessionPath);
            [~,nm] = fileparts(char(obj.Path));
            obj.Name = string(nm);
            obj.Subject = mabr.analysis.Session.subjectFrom(obj.Path);

            if opts.Parse, obj.parse(); end
        end

        % =================================================================
        %  1. Parse -- filenames and stimulus metadata
        % =================================================================
        function T = parse(obj)
            % Read every matching .abr file's metadata into Files.
            %
            % One row per file: a column per informative stimulus parameter,
            % plus the timestamp, sweep count, sample rate and Test Mode flag.
            % The parameter columns are named by SIG.informativeParams, which
            % is what makes this work for a bank that varies something other
            % than frequency and level.
            d = dir(fullfile(char(obj.Path),'*.abr'));
            if ~isempty(d)
                keep = ~cellfun(@isempty,regexp({d.name},char(obj.FilePattern),'once'));
                d = d(keep);
            end

            if isempty(d)
                obj.Files = table();
                obj.warn('No .abr files matching "%s" in %s.',obj.FilePattern,obj.Path);
                T = obj.Files;
                return
            end

            n = numel(d);
            rows   = cell(n,1);
            traces = cell(n,1);
            onsets = cell(n,1);
            keep   = true(n,1);

            p = mabr.analysis.Progress(n,sprintf('Reading %d files',n),obj.Verbose);
            for i = 1:n
                ffn = fullfile(d(i).folder,d(i).name);
                try
                    a = load(ffn,'-mat','ABR_Data');
                catch ME
                    obj.warn('Could not read %s (%s).',d(i).name,ME.message);
                    keep(i) = false; p.step(); continue
                end
                if ~isfield(a,'ABR_Data')
                    obj.warn('No ABR_Data in %s.',d(i).name);
                    keep(i) = false; p.step(); continue
                end
                a = a.ABR_Data;

                [rows{i},tr,on] = mabr.analysis.Session.readRecord(a,d(i));
                if isempty(rows{i})
                    keep(i) = false; p.step(); continue
                end
                if obj.KeepTraces
                    traces{i} = tr;
                    onsets{i} = on;
                end
                p.step();
            end
            p.close();

            rows = rows(keep);
            if isempty(rows)
                obj.Files = table();
                T = obj.Files;
                return
            end

            obj.Files  = mabr.analysis.Session.rowsToTable(rows);
            obj.Traces = traces(keep);
            obj.Onsets = onsets(keep);

            % Parameters are every column before 'timestamp', which is the
            % convention parseABRFiles established and every later step reads.
            v  = string(obj.Files.Properties.VariableNames);
            it = find(v == "timestamp",1);
            obj.ParamNames = v(1:it-1);

            rates = unique(obj.Files.SampleRate);
            if numel(rates) > 1
                obj.warn('Files disagree about the sample rate (%s Hz); using the first.', ...
                    strjoin(compose('%g',rates.'),', '));
            end
            obj.SampleRate = rates(1);

            obj.Date = min(obj.Files.timestamp);
            obj.TestMode = any(obj.Files.TestMode);
            if obj.TestMode
                obj.warn(['%d of %d files were recorded in TEST MODE: those samples ' ...
                    'are the stimulus, not a subject.'], ...
                    sum(obj.Files.TestMode), height(obj.Files));
            end
            if obj.Subject == "" && ismember('subject',obj.Files.Properties.VariableNames)
                obj.Subject = obj.Files.subject(1);
            end

            T = obj.Files;
        end

        % =================================================================
        %  2. Segment -- filter each trace, window it into sweeps
        % =================================================================
        function T = segment(obj,opts)
            % Filter and window every file into Conditions.
            %
            % Files sharing a stimulus condition are CONCATENATED into one
            % condition rather than overwriting each other, so a repeated or
            % topped-up measurement adds sweeps instead of replacing them.
            arguments
                obj
                opts.Window double = []
                opts.Filter = []
                opts.HonorAcquisitionArtifacts (1,1) logical = true
                opts.Detrend (1,1) double = NaN   % polynomial order, NaN = none
            end
            if isempty(obj.Files) || height(obj.Files) == 0
                error('mabr:analysis:Session:noFiles', ...
                    'No files parsed. Call parse() first.');
            end
            if ~isempty(opts.Window),  obj.Window = sort(opts.Window); end
            if ~isempty(opts.Filter),  obj.Filter = opts.Filter; end

            Fs = obj.SampleRate;
            swin   = round(Fs*obj.Window/1000);
            winIdx = (swin(1):swin(2)).';
            obj.Time = 1000*winIdx/Fs;

            f = obj.Filter;
            if ~f.IsDesigned || f.SampleRate ~= Fs
                f = f.design(Fs);
                obj.Filter = f;
            end

            % Condition identity: the unique combination of parameter values.
            % Condition order is parameter order, not file order, so a
            % session reads the same way whatever sequence it was run in.
            P    = obj.Files(:,cellstr(obj.ParamNames));
            Pu   = sortrows(unique(P,'rows'));
            [~,gidx] = ismember(P,Pu,'rows');

            nG = height(Pu);
            sweeps = cell(nG,1);  rejected = cell(nG,1);
            pol    = cell(nG,1);  srcFile  = cell(nG,1);

            n = height(obj.Files);
            p = mabr.analysis.Progress(n,sprintf('Segmenting %d files',n),obj.Verbose);
            for i = 1:n
                [trace,on,acqArt,sp] = obj.traceFor(i);
                p.step();
                if isempty(trace) || isempty(on), continue; end

                x = f.apply(double(trace(:)));

                idx = on(:).' + winIdx;                      % [nWin x nSweeps]
                ok  = all(idx >= 1 & idx <= numel(x),1);
                if ~any(ok), continue; end
                X = x(idx(:,ok));
                X = reshape(X,numel(winIdx),[]);

                if isfinite(opts.Detrend)
                    X = detrend(X,opts.Detrend);
                end

                g = gidx(i);
                sweeps{g}   = [sweeps{g}   X];
                srcFile{g}  = [srcFile{g}  repmat(i,1,size(X,2))];
                pol{g}      = [pol{g}      reshape(sp(ok),1,[])];
                if opts.HonorAcquisitionArtifacts
                    rejected{g} = [rejected{g} reshape(acqArt(ok),1,[])];
                else
                    rejected{g} = [rejected{g} false(1,size(X,2))];
                end
            end
            p.close();

            C = Pu;
            C.Sweeps    = sweeps;
            C.Rejected  = rejected;
            C.Polarity  = pol;
            C.SweepFile = srcFile;
            C.nSweeps   = cellfun(@(x) size(x,2),sweeps);
            C.nRejected = cellfun(@sum,rejected);
            C.nFiles    = cellfun(@(x) numel(unique(x)),srcFile);
            obj.Conditions = C;

            empty = C.nSweeps == 0;
            if any(empty)
                obj.warn('%d of %d conditions have no usable sweeps.',sum(empty),nG);
            end
            obj.note('%d conditions, %d sweeps, %.1f ms window at %g Hz.', ...
                nG,sum(C.nSweeps),diff(obj.Window),Fs);

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
            arguments
                obj
                opts.Feature (1,1) string = "absPeak"
                opts.Method (1,1) string = "median"
                opts.Threshold (1,1) double = Inf
                opts.MethodArgs struct = struct()
                opts.Window double = []      % ms; default ResponseWindow
                opts.Keep (1,1) logical = true     % keep flags already set
                opts.Plot (1,1) logical = false
            end
            obj.requireConditions();

            win = opts.Window;
            if isempty(win), win = obj.ResponseWindow; end
            rows = mabr.analysis.Artifacts.windowMask(obj.Time,win);

            C = obj.Conditions;
            nC = height(C);
            p = mabr.analysis.Progress(nC,'Rejecting artifacts',obj.Verbose);
            for i = 1:nC
                X = C.Sweeps{i};
                if isempty(X), p.step(); continue; end

                [isArt,info] = mabr.analysis.Artifacts.detect(X, ...
                    Rows=rows, Feature=opts.Feature, Method=opts.Method, ...
                    Threshold=opts.Threshold, MethodArgs=opts.MethodArgs);

                if opts.Keep
                    % The acquisition rig's own verdict, and any earlier pass,
                    % stand: a second criterion adds sweeps to the rejected set
                    % and never argues one back into it.
                    C.Rejected{i} = C.Rejected{i} | isArt;
                else
                    C.Rejected{i} = isArt;
                end

                if opts.Plot
                    mabr.analysis.Artifacts.plotDiagnostic(X,C.Rejected{i},info,Time=obj.Time);
                end
                p.step();
            end
            p.close();

            C.nRejected = cellfun(@sum,C.Rejected);
            obj.Conditions = C;
            obj.note('%d of %d sweeps rejected (%.1f%%).', ...
                sum(C.nRejected),sum(C.nSweeps),100*sum(C.nRejected)/max(1,sum(C.nSweeps)));
            T = obj.Conditions;
        end

        function clearRejected(obj)
            % Drop every artifact flag, including the acquisition rig's.
            obj.requireConditions();
            obj.Conditions.Rejected = cellfun(@(x) false(size(x)), ...
                obj.Conditions.Rejected,'UniformOutput',false);
            obj.Conditions.nRejected(:) = 0;
        end

        % =================================================================
        %  4. Detect -- is there a response in each condition?
        % =================================================================
        function T = detect(obj,opts)
            % Permutation-test every condition and store p, isSig, strength.
            arguments
                obj
                opts.Method (1,1) string {mustBeMember(opts.Method,["clusterMass","tmax","tfce"])} = "tfce"
                opts.NumPermutations (1,1) double {mustBeInteger,mustBePositive} = 1000
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1)} = 0.05
                opts.MinClusterSize (1,1) double {mustBeInteger,mustBePositive} = 1
                opts.Window double = []
                opts.Seed = 1
                opts.UseParallel (1,1) logical = false
            end
            obj.requireConditions();

            win = opts.Window;
            if isempty(win), win = obj.ResponseWindow; end
            rows = mabr.analysis.Artifacts.windowMask(obj.Time,win);

            C  = obj.Conditions;
            nC = height(C);
            X  = obj.sweepCell();          % clean sweeps, one cell per condition

            det = repmat(struct('p',NaN,'isSig',false,'strength',NaN,'nSweeps',0,'result',struct()),nC,1);

            args = {rows,opts.Method,opts.NumPermutations,opts.Alpha,opts.MinClusterSize,opts.Seed};
            if opts.UseParallel && nC > 1
                parfor i = 1:nC
                    det(i) = mabr.analysis.Session.detectOne(X{i},args);
                end
            else
                p = mabr.analysis.Progress(nC,'Permutation tests',obj.Verbose);
                for i = 1:nC
                    det(i) = mabr.analysis.Session.detectOne(X{i},args);
                    p.step();
                end
                p.close();
            end

            C.p        = [det.p].';
            C.isSig    = [det.isSig].';
            C.strength = [det.strength].';
            C.Detection = num2cell(det);
            obj.Conditions = C;

            obj.note('%d of %d conditions significant at alpha = %g (%s).', ...
                sum(C.isSig),nC,opts.Alpha,opts.Method);
            T = obj.Conditions;
        end

        % =================================================================
        %  5. Thresholds
        % =================================================================
        function T = estimateThresholds(obj,opts)
            % Fit one threshold per group, along the level axis.
            %
            % GroupBy defaults to every varying parameter except the level --
            % usually frequency, but a bank varying frequency and rate gets a
            % threshold for each combination, which is the right answer and the
            % reason this is not hard-coded to two dimensions.
            arguments
                obj
                opts.LevelParam (1,1) string = ""
                opts.GroupBy (1,:) string = string.empty
                opts.Type (1,1) string {mustBeMember(opts.Type,["glm","sigmoid","isotonic","minimum"])} = "glm"
                opts.FitTarget (1,1) string {mustBeMember(opts.FitTarget,["auto","binary","p","strength"])} = "auto"
                opts.Criterion (1,1) double {mustBeInRange(opts.Criterion,0,1)} = 0.5
                opts.Extrapolate (1,1) logical = true
                opts.NearestLevel (1,1) logical = false
                opts.CIAlpha (1,1) double = 0.05
                opts.Seed = 1
            end
            obj.requireConditions();
            if ~ismember('isSig',obj.Conditions.Properties.VariableNames)
                obj.note('No detections yet; running detect() with its defaults.');
                obj.detect();
            end

            lvl = opts.LevelParam;
            if lvl == "", lvl = obj.levelParam(); end

            grp = opts.GroupBy;
            if isempty(grp)
                grp = setdiff(obj.varyingParams(),lvl,'stable');
            end

            C = obj.Conditions;
            if isempty(grp)
                gid = ones(height(C),1);        % one series, no grouping
                G   = table();
            else
                [gid,G] = findgroups(C(:,cellstr(grp)));
            end

            nG = max(gid);
            th = nan(nG,1); ciLo = nan(nG,1); ciHi = nan(nG,1);
            type = strings(nG,1); target = strings(nG,1);
            nLev = zeros(nG,1); nSig = zeros(nG,1);
            fits = cell(nG,1);

            p = mabr.analysis.Progress(nG,'Estimating thresholds',obj.Verbose);
            for g = 1:nG
                idx = find(gid == g);
                [levels,o] = sort(C.(lvl)(idx));
                idx = idx(o);

                det = struct('p',num2cell(C.p(idx)), ...
                             'isSig',num2cell(C.isSig(idx)), ...
                             'strength',num2cell(C.strength(idx)), ...
                             'nSweeps',num2cell(C.nSweeps(idx) - C.nRejected(idx)));

                f = mabr.analysis.Threshold.estimate(levels,det, ...
                    Type=opts.Type, FitTarget=opts.FitTarget, Criterion=opts.Criterion, ...
                    Extrapolate=opts.Extrapolate, NearestLevel=opts.NearestLevel, ...
                    CIAlpha=opts.CIAlpha, Seed=opts.Seed);

                th(g)     = f.Threshold;
                ciLo(g)   = f.CI(1);
                ciHi(g)   = f.CI(2);
                type(g)   = f.Type;
                target(g) = f.FitTarget;
                nLev(g)   = numel(levels);
                nSig(g)   = sum(C.isSig(idx));
                fits{g}   = f;
                p.step();
            end
            p.close();

            if isempty(grp)
                T = table();
            else
                T = G;
            end
            T.Threshold  = th;
            T.CILower    = ciLo;
            T.CIUpper    = ciHi;
            T.Curated    = th;          % what a human would edit; seeded with the fit
            T.IsCurated  = false(nG,1);
            T.Type       = type;
            T.FitTarget  = target;
            T.NumLevels  = nLev;
            T.NumSig     = nSig;
            T.Fit        = fits;
            T.LevelParam = repmat(lvl,nG,1);

            obj.Thresholds = T;
            obj.note('%d thresholds (%s fit, criterion %.2f); %d without a response.', ...
                nG,opts.Type,opts.Criterion,sum(~isfinite(th)));
        end

        function setThreshold(obj,row,value)
            % Curate one threshold by hand, keeping the fitted value intact.
            %
            % The fit stays in Threshold and the human answer goes in Curated,
            % because the two disagreeing is information -- and because a
            % curated session must still be able to say what the model said.
            % Pass Inf for "no response", the same convention the fit uses.
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
            obj.Thresholds.Curated(row)   = value;
            obj.Thresholds.IsCurated(row) = true;
        end

        function row = thresholdRow(obj,param,value)
            % The threshold row for one group value, e.g. thresholdRow("Frequency",16).
            arguments
                obj
                param (1,1) string
                value (1,1) double
            end
            obj.requireThresholds();
            if ~ismember(param,string(obj.Thresholds.Properties.VariableNames))
                error('mabr:analysis:Session:noSuchGroup', ...
                    'Thresholds are not grouped by "%s".',param);
            end
            row = find(obj.Thresholds.(param) == value,1);
        end

        % =================================================================
        %  Access
        % =================================================================
        function X = sweeps(obj,row,opts)
            % Sweeps for one condition: [nSamples x nSweeps].
            %
            % Flagged sweeps are excluded by default and are one argument away.
            arguments
                obj
                row (1,1) double
                opts.IncludeRejected (1,1) logical = false
                opts.Polarity (1,1) string {mustBeMember(opts.Polarity,["all","positive","negative"])} = "all"
                opts.Window double = []
            end
            obj.requireConditions();
            X = obj.Conditions.Sweeps{row};
            if isempty(X), return; end

            keep = true(1,size(X,2));
            if ~opts.IncludeRejected
                keep = keep & ~obj.Conditions.Rejected{row};
            end
            if opts.Polarity ~= "all"
                pol = obj.Conditions.Polarity{row};
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
            % U is the struct of unique values, one field per parameter.
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
            keep = true(height(C),1);
            fn = fieldnames(opts.Where);
            for i = 1:numel(fn)
                keep = keep & ismember(C.(fn{i}),opts.Where.(fn{i}));
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
                U.(pn) = unique(C.(pn)(idx)).';
            end
        end

        function t = timeVector(obj,window)
            % Time in ms, optionally restricted to a window.
            arguments
                obj
                window (1,2) double = [-Inf Inf]
            end
            t = obj.Time(obj.Time >= window(1) & obj.Time <= window(2));
        end

        function names = varyingParams(obj)
            % Parameters that take more than one value in this session.
            names = string.empty;
            if isempty(obj.Conditions) || height(obj.Conditions) == 0, return; end
            for pn = obj.ParamNames
                if numel(unique(obj.Conditions.(pn))) > 1, names(end+1) = pn; end %#ok<AGROW>
            end
        end

        function pn = levelParam(obj)
            % Which parameter is the level axis.
            pn = obj.matchParam(mabr.analysis.Session.LevelAliases);
            if pn == ""
                v = obj.varyingParams();
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
            pn = obj.matchParam(mabr.analysis.Session.FrequencyAliases);
            if pn == ""
                v = setdiff(obj.varyingParams(),obj.levelParam(),'stable');
                if isscalar(v), pn = v; end
            end
        end

        % =================================================================
        %  Plotting (thin wrappers; the drawing is in mabr.analysis.Plot)
        % =================================================================
        function [ax,tl] = plotGrid(obj,opts)
            % The level x frequency grid of averaged responses.
            arguments
                obj
                opts.RowParam (1,1) string = ""
                opts.ColParam (1,1) string = ""
                opts.Window (1,2) double = [-2 10]
                opts.Normalize (1,1) string = "column"
                opts.Palette (1,1) string = "linear"
                opts.Thresholds (1,1) logical = true
                opts.Curated (1,1) logical = true
                opts.Parent = []
            end
            obj.requireConditions();
            [S,~,rowVals,colVals] = obj.grid(opts.RowParam,opts.ColParam,Reduce="mean");

            th = [];
            if opts.Thresholds && height(obj.Thresholds) == numel(colVals)
                if opts.Curated, th = obj.Thresholds.Curated.'; else, th = obj.Thresholds.Threshold.'; end
            end

            rp = opts.RowParam; if rp == "", rp = obj.levelParam(); end
            cp = opts.ColParam; if cp == "", cp = obj.frequencyParam(); end

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
            arguments
                obj
                opts.Curated (1,1) logical = true
                opts.CI (1,1) logical = true
                opts.Parent = []
                opts.Hold (1,1) logical = false
            end
            obj.requireThresholds();
            T = obj.Thresholds;

            fp = obj.frequencyParam();
            if fp == "" || ~ismember(fp,string(T.Properties.VariableNames))
                x = (1:height(T));
            else
                x = T.(fp).';
            end

            if opts.Curated, y = T.Curated.'; else, y = T.Threshold.'; end

            ci = [];
            if opts.CI && all(ismember({'CILower','CIUpper'},T.Properties.VariableNames))
                ci = [T.CILower.'; T.CIUpper.'];
            end

            ax = mabr.analysis.Plot.audiogram(x,y, CI=ci, Parent=opts.Parent, ...
                Hold=opts.Hold, DisplayName=obj.Name);
            title(ax,char(obj.Name),'Interpreter','none');
        end

        function ax = plotStack(obj,colValue,opts)
            % One frequency's level series as an offset waterfall.
            arguments
                obj
                colValue (1,1) double
                opts.Window (1,2) double = [-2 10]
                opts.Palette (1,1) string = "linear"
                opts.Parent = []
            end
            cp = obj.frequencyParam();
            rp = obj.levelParam();
            w = struct(); w.(cp) = colValue;
            [S,~,rowVals] = obj.grid(rp,cp,Reduce="mean",Where=w);

            th = NaN;
            if height(obj.Thresholds) > 0 && ismember(cp,string(obj.Thresholds.Properties.VariableNames))
                k = find(obj.Thresholds.(cp) == colValue,1);
                if ~isempty(k), th = obj.Thresholds.Curated(k); end
            end

            ax = mabr.analysis.Plot.stack(S(:,1),obj.Time,rowVals, ...
                Window=opts.Window, Palette=opts.Palette, Threshold=th, Parent=opts.Parent);
            title(ax,sprintf('%s  %s = %g',obj.Name,cp,colValue),'Interpreter','none');
        end

        % =================================================================
        %  Persistence
        % =================================================================
        function ffn = saveResults(obj,ffn,opts)
            % Save everything this session knows to a .mat file.
            arguments
                obj
                ffn (1,1) string
                opts.IncludeSweeps (1,1) logical = true
                opts.IncludeFits (1,1) logical = true
            end
            R = obj.toStruct(opts.IncludeSweeps,opts.IncludeFits);
            d = fileparts(char(ffn));
            if ~isempty(d) && ~isfolder(d), mkdir(d); end
            save(ffn,'-struct','R');
            obj.note('Saved %s.',ffn);
        end

        function R = toStruct(obj,includeSweeps,includeFits)
            % Plain-struct form of the session, for saving.
            %
            % Deliberately plain: a results file that needs this class to load
            % is a results file that stops opening the day the class changes.
            arguments
                obj
                includeSweeps (1,1) logical = true
                includeFits (1,1) logical = true
            end
            C = obj.Conditions;
            if ~includeSweeps && ismember('Sweeps',C.Properties.VariableNames)
                C.Sweeps = [];
            end
            T = obj.Thresholds;
            if ~includeFits && ismember('Fit',T.Properties.VariableNames)
                T.Fit = [];
            end

            R = struct();
            R.Version        = mabr.analysis.Session.Version;
            R.Path           = obj.Path;
            R.Name           = obj.Name;
            R.Subject        = obj.Subject;
            R.Date           = obj.Date;
            R.SampleRate     = obj.SampleRate;
            R.Window         = obj.Window;
            R.ResponseWindow = obj.ResponseWindow;
            R.Time           = obj.Time;
            R.ParamNames     = obj.ParamNames;
            R.TestMode       = obj.TestMode;
            R.Files          = obj.Files;
            R.Conditions     = C;
            R.Thresholds     = T;
            R.FilterDescription = obj.Filter.describe();
        end

        % =================================================================
        %  Display
        % =================================================================
        function s = describe(obj)
            s = sprintf('%s  (%s)  %d files, %d conditions, %g Hz', ...
                obj.Name, obj.Subject, obj.NumFiles, obj.NumConditions, obj.SampleRate);
            if obj.TestMode, s = [s '  [TEST MODE]']; end
            s = string(s);
        end

        function disp(obj)
            if ~isscalar(obj), builtin('disp',obj); return; end
            fprintf('  mabr.analysis.Session\n');
            fprintf('    %s\n',obj.describe());
            fprintf('    path       : %s\n',obj.Path);
            if ~isnat(obj.Date), fprintf('    date       : %s\n',string(obj.Date)); end
            fprintf('    parameters : %s\n',strjoin(obj.ParamNames,', '));
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
        function n = get.NumFiles(obj),      n = height(obj.Files); end
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
            arguments
                rootPath (1,1) string
                opts.Pattern (1,1) string = "*.abr"
            end
            d = dir(fullfile(char(rootPath),'**',char(opts.Pattern)));
            if isempty(d), paths = string.empty(0,1); return; end
            paths = unique(string({d.folder}).');
            paths(paths == "") = [];
        end

        function obj = fromResults(ffn)
            % Rebuild a Session from a file written by saveResults.
            arguments
                ffn (1,1) string
            end
            R = load(ffn);
            obj = mabr.analysis.Session("",Parse=false);
            f = ["Path","Name","Subject","Date","SampleRate","Window","Time", ...
                 "ParamNames","TestMode","Files","Conditions","Thresholds"];
            for k = f
                if isfield(R,k), obj.(k) = R.(k); end
            end
            if isfield(R,'ResponseWindow'), obj.ResponseWindow = R.ResponseWindow; end
        end

        function s = subjectFrom(pth)
            % Subject token out of a path, if one is there to be found.
            s = "";
            m = regexp(char(pth),'SUBJ[_-]?ID[_-]?\d+','match','once','ignorecase');
            if ~isempty(m), s = string(m); end
        end
    end

    methods (Static, Access = private)
        function d = detectOne(X,args)
            % One condition's permutation test, packaged so that the serial
            % and parfor branches call exactly the same thing.
            [rows,method,nPerm,alpha,minSz,seed] = deal(args{:});
            if isempty(X) || size(X,2) < 2
                d = struct('p',NaN,'isSig',false,'strength',NaN,'nSweeps',size(X,2),'result',struct());
                return
            end
            d = mabr.analysis.Threshold.detect(X, Rows=rows, Method=method, ...
                NumPermutations=nPerm, Alpha=alpha, MinClusterSize=minSz, Seed=seed);
        end

        function [row,trace,onsets] = readRecord(a,dirEntry)
            % One file's metadata (and, when asked for, its trace).
            row = []; trace = []; onsets = [];
            if ~isfield(a,'ADC') || ~isfield(a.ADC,'Data') || ~isfield(a.ADC,'SweepOnsets')
                return
            end

            row = struct();
            if isfield(a,'SIG') && isstruct(a.SIG) && isfield(a.SIG,'informativeParams')
                p = cellstr(a.SIG.informativeParams);
                for j = 1:numel(p)
                    v = [];
                    if isfield(a.SIG,p{j}), v = double(a.SIG.(p{j})); end
                    if isempty(v) && isfield(a.SIG,'dataParams') && isfield(a.SIG.dataParams,p{j})
                        v = double(a.SIG.dataParams.(p{j}));   % older format
                    end
                    if isempty(v), v = NaN; end
                    row.(p{j}) = v(1);
                end
            end

            if isfield(a,'StartTime')
                try
                    row.timestamp = datetime(a.StartTime);
                catch
                    row.timestamp = NaT;
                end
            else
                row.timestamp = NaT;
            end
            row.fileName   = string(dirEntry.name);
            row.folder     = string(dirEntry.folder);
            row.nSweeps    = numel(a.ADC.SweepOnsets);
            row.SampleRate = double(a.ADC.SampleRate);
            row.TestMode   = isfield(a,'TestMode') && logical(a.TestMode);

            onsets = struct();
            onsets.idx = double(a.ADC.SweepOnsets(:));
            if isfield(a.ADC,'IsArtifact') && numel(a.ADC.IsArtifact) == numel(onsets.idx)
                onsets.art = reshape(logical(a.ADC.IsArtifact),1,[]);
            else
                onsets.art = false(1,numel(onsets.idx));
            end
            if isfield(a.ADC,'SweepPolarity') && numel(a.ADC.SweepPolarity) == numel(onsets.idx)
                onsets.pol = reshape(double(a.ADC.SweepPolarity),1,[]);
            else
                onsets.pol = ones(1,numel(onsets.idx));
            end

            trace = a.ADC.Data(:);      % left in its stored precision
        end

        function T = rowsToTable(rows)
            % Struct rows to a table, tolerating a file that carries a
            % parameter the others do not.
            names = string([]);
            for i = 1:numel(rows), names = union(names,string(fieldnames(rows{i})),'stable'); end
            S = struct();
            for k = names(:).'
                vals = cell(numel(rows),1);
                for i = 1:numel(rows)
                    if isfield(rows{i},k), vals{i} = rows{i}.(k); else, vals{i} = missingLike(rows,k); end
                end
                try
                    S.(k) = vertcat(vals{:});
                catch
                    S.(k) = vals;
                end
            end
            T = struct2table(S,'AsArray',false);

            function m = missingLike(rows,k)
                m = NaN;
                for j = 1:numel(rows)
                    if isfield(rows{j},k)
                        v = rows{j}.(k);
                        if isstring(v), m = ""; elseif islogical(v), m = false; end
                        return
                    end
                end
            end
        end
    end

    % =====================================================================
    %  Private helpers
    % =====================================================================
    methods (Access = private)
        function [trace,onsets,art,pol] = traceFor(obj,i)
            % One file's trace and onsets, from the cache or from disk.
            trace = []; onsets = []; art = []; pol = [];
            if obj.KeepTraces && numel(obj.Traces) >= i && ~isempty(obj.Traces{i})
                trace  = obj.Traces{i};
                o      = obj.Onsets{i};
            else
                ffn = fullfile(obj.Files.folder(i),obj.Files.fileName(i));
                try
                    a = load(ffn,'-mat','ABR_Data');
                catch ME
                    obj.warn('Could not re-read %s (%s).',obj.Files.fileName(i),ME.message);
                    return
                end
                [~,trace,o] = mabr.analysis.Session.readRecord(a.ABR_Data, ...
                    struct('name',char(obj.Files.fileName(i)),'folder',char(obj.Files.folder(i))));
                if obj.KeepTraces
                    obj.Traces{i} = trace;
                    obj.Onsets{i} = o;
                end
            end
            if isempty(o), return; end
            onsets = o.idx; art = o.art; pol = o.pol;
        end

        function X = sweepCell(obj)
            % Clean sweeps for every condition, as a cell -- the form the
            % per-condition functions and a parfor both want.
            n = height(obj.Conditions);
            X = cell(n,1);
            for i = 1:n, X{i} = obj.sweeps(i); end
        end

        function pn = matchParam(obj,aliases)
            pn = "";
            for a = aliases
                k = find(strcmpi(obj.ParamNames,a),1);
                if ~isempty(k), pn = obj.ParamNames(k); return; end
            end
        end

        function s = axisLabel(~,pn)
            % A parameter's axis label, with the units the toolbox fixes by
            % name end to end (see mabr.stim.StimulusSet.paramTable).
            if pn == "", s = ""; return; end
            if any(strcmpi(pn,mabr.analysis.Session.LevelAliases))
                s = pn + " (dB SPL)";
            elseif any(strcmpi(pn,mabr.analysis.Session.FrequencyAliases))
                s = pn + " (kHz)";
            else
                s = pn;
            end
        end

        function requireConditions(obj)
            if isempty(obj.Conditions) || height(obj.Conditions) == 0
                error('mabr:analysis:Session:noConditions', ...
                    'No conditions. Call segment() first.');
            end
        end

        function requireThresholds(obj)
            if height(obj.Thresholds) == 0
                error('mabr:analysis:Session:noThresholds', ...
                    'No thresholds. Call estimateThresholds() first.');
            end
        end

        function note(obj,fmt,varargin)
            if obj.Verbose, fprintf(['  ' fmt '\n'],varargin{:}); end
        end

        function warn(obj,fmt,varargin)
            if obj.Verbose, fprintf(2,['  ' fmt '\n'],varargin{:}); end
        end
    end
end
