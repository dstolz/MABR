classdef Settings
% mabr.analysis.Settings  Every offline-analysis setting, as one value object.
%
%   One object holds everything Session.analyze needs to turn a folder of
%   .abr files into thresholds and peaks -- the window, the filter, artifact
%   rejection, the permutation test, the single-trial measures, the
%   threshold method and the peak-picking priors -- so that "the settings a
%   result was made with" is one thing that can be saved, compared, hashed
%   and restored:
%
%       s = mabr.analysis.Settings(NumPermutations=2000);
%       s.problems()                    % "" -> valid
%       f = s.filter();                 % the mabr.analysis.Filter it implies
%       s.thresholdDefinition()         % one sentence: what "threshold" means here
%       s.save("myLab.mabraset");       % and Settings.load to get it back
%
%   It is a VALUE object with plain public properties, validated by type: a
%   value of the wrong class or shape is refused on assignment, while a value
%   that is the right type but makes no sense together with the others (a
%   response window outside the window, a high pass above the low pass, too
%   few permutations for Alpha) is accepted and reported by problems(). That
%   split is deliberate -- a dialog has to be able to hold the settings the
%   user is half way through typing and say what is wrong with them.
%
%   TWO TIERS OF DEFAULTS. These defaults are the RECOMMENDED ones, used by
%   Session.analyze. Calling a Session step directly keeps that step's own
%   older defaults, so existing scripts give the numbers they always gave.
%
%   STEPS AND STALENESS. Each setting belongs to the first analysis step that
%   reads it (stepOf): segment, reject, detect, measure, thresholds, peaks --
%   or "none" (Profile, a label). ("report", a setting applied only when
%   numbers are shown, remains a step stepOf may answer, but no setting is
%   one now: the latency offset below is stored with every pick, in the
%   Peaks table's LatencyOffset column, so a change of it re-runs peaks.)
%   stepSettings(step) is what a results file records per step, so a result
%   is current for a step when that struct and every earlier step's still
%   match; firstChangedStep says where re-running has to start. hash() (of
%   resultsStruct()) names a set of settings in file names and exports, and
%   is NOT used to decide staleness.
%
%   LATENCY REFERENCE. Time zero in every .abr is the timing pulse -- the
%   ELECTRICAL onset of the stimulus -- and the sound reaches the eardrum
%   later by its travel time: 0.29 ms for 10 cm of air at 343 m/s, plus any
%   tubing. ConductionDelayMode says how that delay is known: "none" (latencies
%   stay re the onset), "delay" (ConductionDelay, ms, as measured) or
%   "distance" (SpeakerDistance cm at SpeedOfSound m/s); TimeOffset adds a
%   further fixed offset of the recording system. latencyOffset() =
%   conductionDelay() + TimeOffset is subtracted from every latency reported
%   (mabr.analysis.Peaks.reported), so latencies are re SOUND ARRIVAL. It is
%   a reporting correction and nothing more: the wave windows (Waves) are in
%   the recording's own time, re the timing pulse -- the time they were drawn
%   up in, on recordings -- so a delay shifts every reported latency by
%   exactly itself and changes no pick. They are peak settings only because
%   each pick is stored with the offset it is reported with: changing one
%   re-runs peaks (the same picks, a new LatencyOffset), never detection or
%   thresholds.
%
%   PERSISTENCE, twice, as every MABR setting: the MATLAB pref
%   MABR/OfflineAnalysisSettings (loadPrefs/savePrefs -- savePrefs only ever
%   from a control a user pressed, never from a setter or a script) and a
%   named .mabraset file (save/load: a MAT-file holding one variable,
%   MABRAnalysisSettings = toStruct()). Both go through toStruct/fromStruct,
%   which are plain structs and forgiving: a field this version does not know
%   is ignored, one it cannot accept keeps its default and says so.
%
%   PROFILES. profile("MABR default") is the defaults; profile("Legacy SCRATCH
%   (2025)") reproduces the 2025 batch pipeline (Firth GLM at p = 0.75 on
%   TFCE detections, a 300-1500 Hz pass band -- high pass [150 300], low pass
%   [1500 3000] -- response 0-10 ms, pooled acquisition modes, no sweep-count
%   minimum). matchingProfile() names the profile whose results-affecting
%   settings these equal, or "".
%
%   Settings does not call mabr.analysis.Peaks: its default Waves are a
%   literal copy of Peaks.defaultWaves(), the latency shift it gives a wave
%   without one a copy of Peaks.AddedLatencyShift, and its wave-name rule a
%   copy of Peaks.nameProblem (waveNameProblem), each held to the original
%   by the verification test.
%
%   See also mabr.analysis.Session, mabr.analysis.SeriesThreshold,
%   mabr.analysis.Filter

    properties (Constant)
        SettingsVersion = 1     % bump when a field changes meaning
        Steps = ["segment","reject","detect","measure","thresholds","peaks"]
        PrefGroup = "MABR"
        PrefName  = "OfflineAnalysisSettings"
    end

    properties
        % A name for this set of settings: a built-in profile's, or the
        % user's own. A label only -- matchingProfile() says whether the
        % values still are that profile.
        Profile (1,1) string = "MABR default"

        % ---- segmentation ------------------------------------------------
        % Sweep window, ms re stimulus onset.
        Window (1,2) double {mustBeFinite} = [-12 12]
        % Response window, ms: artifact features, detection and the measures.
        ResponseWindow (1,2) double {mustBeFinite} = [0.5 8]
        % Baseline window of BaselineRMS, ms.
        BaselineWindow (1,2) double {mustBeFinite} = [-10 0]
        % Baseline window peak amplitudes are measured from, ms.
        BaselineAmpWindow (1,2) double {mustBeFinite} = [-1 0]
        % [Fstop Fpass] Hz of the high pass; [] switches it off.
        HighPass (1,:) double {mustBeNonnegative,mustBeFinite} = [150 300]
        % [Fpass Fstop] Hz of the low pass; [] switches it off.
        LowPass (1,:) double {mustBeNonnegative,mustBeFinite} = [3000 4200]
        % Equiripple pass-band ripple, peak-to-peak dB (filter() converts).
        FilterPassRippleDb (1,1) double {mustBePositive,mustBeFinite} = 0.25
        % Equiripple stop-band attenuation, dB.
        FilterStopAttenDb (1,1) double {mustBePositive,mustBeFinite} = 30
        % Polynomial order each continuous-path sweep is detrended by; NaN none.
        Detrend (1,1) double = NaN
        % "auto": compact (interleaved) files windowed, the rest continuous;
        % "windowed": every condition through the windowed operator.
        Processing (1,1) string {mustBeMember(Processing,["auto","windowed"])} = "auto"
        % Butterworth order of the windowed operator.
        WindowedOrder (1,1) double {mustBeInteger,mustBeInRange(WindowedOrder,1,4)} = 2
        % Padding of a window before filtering it.
        WindowedPadMode (1,1) string {mustBeMember(WindowedPadMode,["reflect","zeroleft"])} = "reflect"
        % Pool conventional and interleaved runs of one condition.
        PoolAcqModes (1,1) logical = false
        % Clean sweeps used per condition (balanced by polarity); Inf = all.
        MaxSweepsPerCondition (1,1) double {mustBePositive} = Inf
        % Which sweeps the cap keeps: the first, or a seeded random choice.
        EqualizeMode (1,1) string {mustBeMember(EqualizeMode,["first","random"])} = "first"

        % ---- rejection ---------------------------------------------------
        % Start from the acquisition rig's own artifact flags.
        HonorAcquisitionArtifacts (1,1) logical = true
        % Relative outlier rule ("none" = the absolute ceiling only).
        RejectMethod (1,1) string {mustBeMember(RejectMethod,["none","median","mean","quartiles"])} = "median"
        % Per-sweep feature the rule is applied to (Artifacts.Features).
        RejectFeature (1,1) string {mustBeMember(RejectFeature,["rms","std","meanabs","peak2peak","posPeak","negPeak","absPeak"])} = "absPeak"
        % Outlier threshold factor of the relative rule.
        RejectFactor (1,1) double {mustBePositive,mustBeFinite} = 3
        % Reject only the large side of a non-negative feature.
        RejectUpperOnly (1,1) logical = true
        % Absolute ceiling on the feature, V; Inf = off.
        RejectCeiling (1,1) double {mustBePositive} = Inf

        % ---- detection ---------------------------------------------------
        % Permutation statistic.
        DetectMethod (1,1) string {mustBeMember(DetectMethod,["clusterMass","tmax","tfce"])} = "tfce"
        % Sign-flip permutations per condition.
        NumPermutations (1,1) double {mustBeInteger,mustBePositive} = 1000
        % Significance level of a detection.
        Alpha (1,1) double {mustBeInRange(Alpha,0,1,"exclusive")} = 0.05
        % Base seed (per-condition seeds derive from it and the condition key).
        Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 1

        % ---- single-trial measures ---------------------------------------
        % Sub-average of each split half.
        SplitHalfMode (1,1) string {mustBeMember(SplitHalfMode,["median","mean"])} = "median"
        % Random partitions per condition.
        SplitHalfResamples (1,1) double {mustBeInteger,mustBePositive} = 500
        % Window the split-half r is computed over, ms; [] = ResponseWindow.
        SplitHalfWindow double = []
        % Fewest sweeps of each polarity per half.
        SplitHalfMinPerPolarity (1,1) double {mustBeInteger,mustBeNonnegative} = 25
        % Largest lag of the next-louder-level correlation, ms: the most the
        % quieter level's response may be later than the louder one's. xcorr
        % takes one lag for the whole window; xcorr-dtw a lag in [0 MaxLag]
        % that changes along the response.
        MaxLag (1,1) double {mustBeNonnegative,mustBeFinite} = 0.3

        % ---- thresholds --------------------------------------------------
        % Named method (SeriesThreshold.methods() Ids).
        ThresholdMethod (1,1) string {mustBeMember(ThresholdMethod,["perm-glm","perm-descending","power-descending","fsp-descending","presto","xcorr","xcorr-dtw","custom"])} = "perm-glm"
        % Custom method: metric, model and criterion mode.
        ThresholdMetric (1,1) string {mustBeMember(ThresholdMetric,["detection","power","fsp","splithalf","xcorr","dtw","snr","strength"])} = "detection"
        ThresholdModel (1,1) string {mustBeMember(ThresholdModel,["descending","glm","presto","isotonic","sigmoid","minimum"])} = "glm"
        CriterionMode (1,1) string {mustBeMember(CriterionMode,["p","probability","absolute","fraction"])} = "probability"
        % Custom method's criterion; NaN = the criterion mode's default.
        Criterion (1,1) double = NaN
        % Level parameter; "" = automatic.
        LevelParam (1,1) string = ""
        % Series grouping parameters; empty = every non-level key column.
        % A list given is used as given PLUS Stimulus and AcqMode (AcqMode
        % not when PoolAcqModes is on), added when it leaves them out: a
        % series never mixes stimuli or acquisition modes, whatever is
        % typed (mabr.analysis.Session.seriesGrouping).
        GroupBy (1,:) string = string.empty
        % "auto" = descending for an Attenuation parameter, else ascending.
        LevelDirection (1,1) string {mustBeMember(LevelDirection,["auto","ascending","descending"])} = "auto"
        % Consecutive detected levels the descending rule needs.
        MinConsecutive (1,1) double {mustBeInteger,mustBeNonnegative} = 2
        % Point reported inside an interval-censored threshold.
        ThresholdConvention (1,1) string {mustBeMember(ThresholdConvention,["midpoint","lowest_level","crossing"])} = "midpoint"
        % Graded metrics: interpolate the criterion crossing.
        Interpolate (1,1) logical = true
        % Clean sweeps a level needs to count.
        MinSweeps (1,1) double {mustBeInteger,mustBeNonnegative} = 100
        % Clean sweeps of each polarity a level needs (alternating data).
        MinPerPolarity (1,1) double {mustBeInteger,mustBeNonnegative} = 40
        % Allow a model threshold outside the levels tested.
        Extrapolate (1,1) logical = true
        % Snap a model threshold to the next tested level at or above it.
        NearestLevel (1,1) logical = false
        % Two-sided level of threshold intervals.
        CIAlpha (1,1) double {mustBeInRange(CIAlpha,0,1,"exclusive")} = 0.05
        % Monte Carlo draws of a legacy interval.
        CINumSamples (1,1) double {mustBeInteger,mustBePositive} = 2000
        % Sweep-bootstrap replicates of a graded threshold; 0 = off.
        ThresholdBootstrap (1,1) double {mustBeInteger,mustBeNonnegative} = 0
        % Flag an interval wider than this fraction of the level range.
        FlagWideCI (1,1) double {mustBeNonnegative} = 0.35
        % Undetected levels above the first detection tolerated before
        % "non-monotone".
        FlagNonMonotoneTol (1,1) double {mustBeInteger,mustBeNonnegative} = 0

        % ---- peaks -------------------------------------------------------
        % Wave priors (Peaks.defaultWaves(): the TraceInspector rodent
        % windows, ms re the timing pulse -- the recording's own time, which
        % no conduction delay moves -- and each wave's latency shift, ms/dB
        % -- larger for the later waves, whose latencies grow faster).
        Waves struct = struct('Name',{"I","II","III","IV","V"}, ...
            'Enabled',{true,true,true,true,true}, ...
            'TMin',{1.0,1.8,2.6,3.4,4.2},'TMax',{2.0,2.8,3.6,4.6,5.6}, ...
            'Expected',{1.5,2.3,3.1,4.0,4.9}, ...
            'LatencyShift',{0.015,0.018,0.020,0.025,0.030}, ...
            'Stimulus',{"","","","",""})
        % Latency shift of the wave windows per octave below RefFrequency, ms.
        PeakOctaveShift (1,1) double {mustBeFinite} = 0.15
        % Frequency the wave windows are written for, kHz.
        PeakRefFrequency (1,1) double {mustBePositive,mustBeFinite} = 16
        % Moving-mean samples applied to the copy peaks are picked from; 0 off.
        PeakSmooth (1,1) double {mustBeInteger,mustBeNonnegative} = 0
        % Smallest separation of two picks, ms.
        PeakMinSeparation (1,1) double {mustBeNonnegative,mustBeFinite} = 0.3
        % Tracking window down the levels, ms before / after the louder pick.
        PeakTrackEarly (1,1) double {mustBeNonnegative,mustBeFinite} = 0.1
        PeakTrackLate (1,1) double {mustBeNonnegative,mustBeFinite} = 0.15
        % Candidate and "detectable" prominence, in multiples of RN.
        % "Detectable" is a size criterion, not a detection test: a pick is
        % the best of several local maxima in its window, so on noise it is
        % routinely 2-3 RN prominent. In real data (six sessions of
        % SUBJ-ID-1254) the picks below threshold had a median of 2.75 RN;
        % 64% of them reached 2 RN, 22% reach 4. (Session.pickPeaks called
        % directly keeps its own default, 2.)
        PeakCandidateRN (1,1) double {mustBeNonnegative,mustBeFinite} = 1
        PeakDetectableRN (1,1) double {mustBeNonnegative,mustBeFinite} = 4
        % Which average peaks are picked on.
        PeakPolarity (1,1) string {mustBeMember(PeakPolarity,["balanced","positive","negative"])} = "balanced"
        % Derived peak measures from levels at/above threshold only.
        PeaksAboveThresholdOnly (1,1) logical = true
        % Bootstrap replicates of peak latency/amplitude; 0 = off.
        PeakBootstrap (1,1) double {mustBeInteger,mustBeNonnegative} = 0
        % Margin from a windowed condition's edge inside which a pick is
        % flagged edge-affected, ms.
        PeakEdgeMs (1,1) double {mustBeNonnegative,mustBeFinite} = 1.0

        % ---- latency reference (peaks: stored with every pick) -------------
        % How the sound's travel time from the speaker to the ear is known:
        % "none" (latencies re the electrical onset), "delay" (ConductionDelay)
        % or "distance" (SpeakerDistance at SpeedOfSound). conductionDelay()
        % is the result, in ms.
        ConductionDelayMode (1,1) string {mustBeMember(ConductionDelayMode,["none","delay","distance"])} = "none"
        % Conduction delay, ms, as measured (mode "delay"). Not validated on
        % assignment, so a dialog can hold what is being typed; problems()
        % says what is wrong with it.
        ConductionDelay (1,1) double = 0
        % Speaker to ear distance, cm (mode "distance").
        SpeakerDistance (1,1) double = 10
        % Speed of sound, m/s (mode "distance"): 343 m/s is dry air at 20 C.
        SpeedOfSound (1,1) double = 343
        % A further fixed offset of the recording system, ms (an onset
        % rounding bias, a converter's delay), added to the conduction delay.
        TimeOffset (1,1) double {mustBeFinite} = 0
    end

    methods
        function obj = Settings(varargin)
            % Settings(Name=Value,...) -- the defaults, with any property set.
            %
            %   varargin  Name,Value pairs naming any property (case is
            %             ignored); an unknown name errors
            %             mabr:analysis:Settings:unknownField
            %   obj       (returned) the Settings
            if mod(numel(varargin),2) ~= 0
                error('mabr:analysis:Settings:badArguments', ...
                    'Settings takes Name,Value pairs.');
            end
            names = mabr.analysis.Settings.fieldSteps();
            names = names(:,1);
            for i = 1:2:numel(varargin)
                k = find(strcmpi(names,string(varargin{i})),1);
                if isempty(k)
                    error('mabr:analysis:Settings:unknownField', ...
                        '"%s" is not an analysis setting.',string(varargin{i}));
                end
                obj.(names(k)) = varargin{i+1};
            end
        end

        % --- value hygiene (set methods: shapes a validator cannot state) --
        function obj = set.Detrend(obj,v)
            if ~(isnan(v) || (isfinite(v) && v >= 0 && v == round(v)))
                error('mabr:analysis:Settings:badValue', ...
                    'Detrend is a non-negative polynomial order, or NaN for none (got %g).',v);
            end
            obj.Detrend = v;
        end

        function obj = set.SplitHalfWindow(obj,v)
            if isempty(v)
                obj.SplitHalfWindow = [];
                return
            end
            if ~(isnumeric(v) && numel(v) == 2 && all(isfinite(v)))
                error('mabr:analysis:Settings:badValue', ...
                    'SplitHalfWindow is [] (the response window) or [t0 t1] ms.');
            end
            obj.SplitHalfWindow = reshape(double(v),1,2);
        end

        function obj = set.GroupBy(obj,v)
            % Blank or missing entries name no parameter: a list holding
            % only those is the empty list ("auto"). Otherwise GroupBy = ""
            % (what a cleared text field gives) and GroupBy = string.empty
            % would mean the same thing yet hash, and compare for staleness,
            % as two different settings.
            v = strtrim(v);
            obj.GroupBy = reshape(v(~ismissing(v) & strlength(v) > 0),1,[]);
        end

        function obj = set.Waves(obj,v)
            obj.Waves = mabr.analysis.Settings.normalizeWaves(v);
        end

        % --- plain structs ----------------------------------------------------
        function st = toStruct(obj)
            % Every setting as a plain struct, plus SettingsVersion.
            %   st  (returned) scalar struct, one field per property
            T  = mabr.analysis.Settings.fieldSteps();
            st = struct('SettingsVersion',mabr.analysis.Settings.SettingsVersion);
            for k = 1:size(T,1)
                st.(T(k,1)) = obj.(T(k,1));
            end
        end

        function st = resultsStruct(obj)
            % The settings that can change a result (step not "none"/"report").
            %   st  (returned) scalar struct
            T  = mabr.analysis.Settings.fieldSteps();
            st = struct();
            for k = 1:size(T,1)
                if ~ismember(T(k,2),["none","report"])
                    st.(T(k,1)) = obj.(T(k,1));
                end
            end
        end

        function st = stepSettings(obj,step)
            % The settings one analysis step reads first.
            %   step  one of Settings.Steps (or "report"/"none")
            %   st    (returned) scalar struct of those fields
            arguments
                obj
                step (1,1) string {mustBeMember(step,["segment","reject","detect","measure","thresholds","peaks","report","none"])}
            end
            T  = mabr.analysis.Settings.fieldSteps();
            st = struct();
            for k = find(T(:,2) == step).'
                st.(T(k,1)) = obj.(T(k,1));
            end
        end

        % --- files --------------------------------------------------------
        function ffn = save(obj,ffn)
            % Write a .mabraset file: a MAT-file holding one variable,
            % MABRAnalysisSettings = toStruct().
            %   ffn  destination (".mabraset" added when it has no extension)
            %   ffn  (returned) the file written
            arguments
                obj
                ffn (1,1) string
            end
            [d,~,e] = fileparts(ffn);
            if e == "", ffn = ffn + ".mabraset"; end
            if d ~= "" && ~isfolder(d), mkdir(d); end
            MABRAnalysisSettings = obj.toStruct();
            save(char(ffn),'MABRAnalysisSettings','-mat');
        end

        % --- what the settings imply ------------------------------------------
        function f = filter(obj)
            % The mabr.analysis.Filter these settings describe (undesigned).
            %
            % The ripple settings are in dB and Filter's tolerances are
            % linear: PassRipple = (10^(Ap/20)-1)/(10^(Ap/20)+1) (Ap = 0.25 dB
            % gives 0.014390163418, Filter's own default) and StopRipple =
            % 10^(-As/20).
            %   f  (returned) mabr.analysis.Filter
            r = 10^(obj.FilterPassRippleDb/20);
            f = mabr.analysis.Filter('HighPass',obj.HighPass,'LowPass',obj.LowPass, ...
                'PassRipple',(r-1)/(r+1),'StopRipple',10^(-obj.FilterStopAttenDb/20));
        end

        function d = conductionDelay(obj)
            % The sound's travel time from the speaker to the ear, ms.
            %
            % ConductionDelayMode "none": 0; "delay": ConductionDelay;
            % "distance": SpeakerDistance/SpeedOfSound, which in cm over m/s
            % is 10*SpeakerDistance/SpeedOfSound ms (10 cm at 343 m/s: 0.29
            % ms). The values are used as they are; problems() is where an
            % impossible one is reported.
            %   d  (returned) ms
            switch obj.ConductionDelayMode
                case "delay"
                    d = obj.ConductionDelay;
                case "distance"
                    d = 10*obj.SpeakerDistance/obj.SpeedOfSound;
                otherwise
                    d = 0;
            end
        end

        function o = latencyOffset(obj)
            % The offset between a recording's time and the ear's, ms:
            % conductionDelay() + TimeOffset. It is subtracted from every
            % latency reported (Peaks.reported); the wave windows stay in the
            % recording's time, so it changes no pick.
            %   o  (returned) ms
            o = obj.conductionDelay() + obj.TimeOffset;
        end

        function p = problems(obj)
            % Everything that makes these settings unusable, one line each.
            %
            % Too few permutations for Alpha to ever be reached; a window that
            % is not ascending, or a sub-window (response, baseline, peak
            % baseline, split-half) that is not inside Window -- the rows it
            % names would not exist, and the settings would then describe an
            % analysis other than the one run; filter edges out of order or
            % overlapping bands; a wave without a usable name (blank, all
            % digits, or repeated among the waves of its stimulus) or with
            % TMin >= TMax; too few split-half resamples; MinConsecutive < 1;
            % a custom method resolve() refuses, criterion range included; a
            % conduction delay that is negative or not a number (mode
            % "delay"), a speaker distance outside (0, 500] cm or a speed of
            % sound outside 300-400 m/s (mode "distance"). Those three are
            % judged only under the mode that reads them, as Criterion is
            % only under the method that reads it.
            %
            %   p  (returned) string column; empty when the settings are valid
            p = strings(0,1);

            % The smallest p a sign-flip test can return is 1/(B+1).
            if 1/(obj.NumPermutations+1) >= obj.Alpha
                need = floor(1/obj.Alpha - 1) + 1;
                while 1/(need+1) >= obj.Alpha, need = need + 1; end
                p(end+1,1) = sprintf(['%d permutations is too few for α %g: no condition can ever ' ...
                    'be significant (at least %d are needed).'],obj.NumPermutations,obj.Alpha,need);
            end

            wins = ["Window","ResponseWindow","BaselineWindow","BaselineAmpWindow","SplitHalfWindow"];
            for nm = wins
                w = obj.(nm);
                if numel(w) == 2 && ~(w(2) > w(1))
                    p(end+1,1) = sprintf('%s [%g %g] ms is not ascending.',nm,w(1),w(2)); %#ok<AGROW>
                end
            end
            W = obj.Window;
            if W(2) > W(1)
                for nm = wins(2:end)
                    w = obj.(nm);
                    if numel(w) == 2 && w(2) > w(1) && (w(1) < W(1) || w(2) > W(2))
                        p(end+1,1) = sprintf('%s [%g %g] ms is not inside Window [%g %g] ms.', ...
                            nm,w(1),w(2),W(1),W(2)); %#ok<AGROW>
                    end
                end
            end

            hp = obj.HighPass; lp = obj.LowPass;
            if ~isempty(hp)
                if numel(hp) ~= 2
                    p(end+1,1) = "HighPass needs two edges, [stop pass] Hz (or [] for off).";
                elseif ~(hp(2) > hp(1))
                    p(end+1,1) = sprintf('HighPass [%g %g] Hz is not ascending ([stop pass]).',hp(1),hp(2));
                end
            end
            if ~isempty(lp)
                if numel(lp) ~= 2
                    p(end+1,1) = "LowPass needs two edges, [pass stop] Hz (or [] for off).";
                elseif ~(lp(2) > lp(1))
                    p(end+1,1) = sprintf('LowPass [%g %g] Hz is not ascending ([pass stop]).',lp(1),lp(2));
                end
            end
            if numel(hp) == 2 && numel(lp) == 2 && hp(2) >= lp(1)
                p(end+1,1) = sprintf(['The high-pass pass band (from %g Hz) is not below the ' ...
                    'low-pass pass band (to %g Hz).'],hp(2),lp(1));
            end

            % A name has to be unique among the waves that apply to one
            % stimulus -- the rows Peaks.wavesFor selects together, matching
            % Stimulus without regard to case -- not across the whole table:
            % a click-specific set of windows is named I..V like the generic
            % one, or its picks and exported columns would not line up.
            Wv = obj.Waves;
            for k = 1:numel(Wv)
                prev = Wv(1:k-1);
                prev = prev(strcmpi(string({prev.Stimulus}),Wv(k).Stimulus));
                why = mabr.analysis.Settings.waveNameProblem(Wv(k).Name,[prev.Name]);
                if strlength(why) > 0
                    p(end+1,1) = sprintf('Wave %d: %s',k,why); %#ok<AGROW>
                end
                if ~(Wv(k).TMin < Wv(k).TMax)
                    p(end+1,1) = sprintf('Wave %s: TMin %g ms is not below TMax %g ms.', ...
                        Wv(k).Name,Wv(k).TMin,Wv(k).TMax); %#ok<AGROW>
                end
            end

            if obj.SplitHalfResamples < 10
                p(end+1,1) = sprintf('SplitHalfResamples %d is too few (at least 10).',obj.SplitHalfResamples);
            end
            if obj.MinConsecutive < 1
                p(end+1,1) = "MinConsecutive must be at least 1.";
            end
            if obj.ThresholdMethod == "custom"
                try
                    mabr.analysis.SeriesThreshold.resolve("custom",obj);
                catch ME
                    p(end+1,1) = string(ME.message);
                end
            end

            % The latency reference. A sound cannot arrive before it is sent,
            % a speaker is somewhere between touching the ear and across a
            % room (5 m), and air carries sound at 331-355 m/s from 0 to 40
            % degrees C -- outside 300-400 m/s the number is in other units.
            % Only the numbers the mode in force reads are judged, as
            % Criterion is only judged under the method that reads it: a
            % settings dialog greys the fields a mode does not use, and a bad
            % value left in a greyed field would otherwise block Apply with
            % no way to reach it -- while changing nothing conductionDelay()
            % returns.
            if obj.ConductionDelayMode == "delay" && ...
                    ~(isfinite(obj.ConductionDelay) && obj.ConductionDelay >= 0)
                p(end+1,1) = sprintf(['ConductionDelay %g ms is not a delay: it must be a ' ...
                    'number of ms, 0 or more.'],obj.ConductionDelay);
            end
            if obj.ConductionDelayMode == "distance"
                if ~(obj.SpeakerDistance > 0 && obj.SpeakerDistance <= 500)
                    p(end+1,1) = sprintf('SpeakerDistance %g cm is outside (0, 500] cm.',obj.SpeakerDistance);
                end
                if ~(obj.SpeedOfSound >= 300 && obj.SpeedOfSound <= 400)
                    p(end+1,1) = sprintf(['SpeedOfSound %g m/s is outside 300-400 m/s ' ...
                        '(air carries sound at about 343 m/s).'],obj.SpeedOfSound);
                end
            end
        end

        % --- comparison ---------------------------------------------------
        function h = hash(obj)
            % 8 hex digits naming the results-affecting settings.
            %
            % FNV-1a of the canonical text of resultsStruct(): fields sorted by
            % name, "name=value", numbers %.17g joined by ",", strings in
            % double quotes, logicals true/false, struct arrays element by
            % element with their fields sorted; fields joined by ";". Profile,
            % a label, is not part of it; the latency reference is, since it
            % moves where peaks are searched for.
            %   h  (returned) 1x1 string
            h = mabr.analysis.Stats.hex8(mabr.analysis.Settings.canonicalText(obj.resultsStruct()));
        end

        function n = matchingProfile(obj)
            % The built-in profile whose results-affecting settings these
            % equal, or "".
            %   n  (returned) 1x1 string
            n = "";
            mine = obj.resultsStruct();
            for name = mabr.analysis.Settings.profileNames()
                if isequaln(mine,mabr.analysis.Settings.profile(name).resultsStruct())
                    n = name;
                    return
                end
            end
        end

        % --- words -----------------------------------------------------------
        function d = thresholdDefinition(obj)
            % One sentence: what "threshold" means under these settings.
            %   d  (returned) 1x1 string
            try
                m = mabr.analysis.SeriesThreshold.resolve(obj.ThresholdMethod,obj);
                d = mabr.analysis.SeriesThreshold.definition(m,obj);
            catch ME
                d = "The threshold method is not valid: " + string(ME.message);
            end
        end

        function d = describe(obj)
            % A human summary, one line per step.
            %   d  (returned) 1x1 string, lines separated by newline
            g  = @(v) string(sprintf('%g',v));
            ms = @(w) string(sprintf('%g to %g ms',w(1),w(2)));
            L  = strings(0,1);
            L(end+1) = "Profile: " + obj.Profile;

            if isempty(obj.HighPass) && isempty(obj.LowPass)
                filt = "no filtering";
            else
                if isempty(obj.HighPass), lo = "0"; else, lo = g(obj.HighPass(end)); end
                if isempty(obj.LowPass),  hi = "Nyquist"; else, hi = g(obj.LowPass(1)); end
                filt = sprintf('%s-%s Hz FIR (%s dB ripple, %s dB attenuation)', ...
                    lo,hi,g(obj.FilterPassRippleDb),g(obj.FilterStopAttenDb));
            end
            if isnan(obj.Detrend), dt = "no detrend"; else, dt = "detrend order " + g(obj.Detrend); end
            if obj.PoolAcqModes, pool = "acquisition modes pooled"; else, pool = "acquisition modes separate"; end
            if isinf(obj.MaxSweepsPerCondition), cap = "all sweeps";
            else, cap = sprintf('at most %s sweeps per condition (%s)',g(obj.MaxSweepsPerCondition),obj.EqualizeMode); end
            L(end+1) = sprintf(['Segmentation: window %s; %s; %s; processing %s (windowed: ' ...
                'Butterworth order %d, %s pad); %s; %s.'],ms(obj.Window),filt,dt,obj.Processing, ...
                obj.WindowedOrder,obj.WindowedPadMode,pool,cap);

            if obj.HonorAcquisitionArtifacts, rig = "rig flags honoured"; else, rig = "rig flags ignored"; end
            if obj.RejectMethod == "none", rule = "no relative rule";
            else
                % The sweep feature in the settings dialog's own words.
                feat = replace(obj.RejectFeature, ...
                    ["absPeak","peak2peak","rms","std","meanabs","posPeak","negPeak"], ...
                    ["absolute peak","peak to peak","RMS","SD","mean absolute value", ...
                     "positive peak","negative peak"]);
                rule = sprintf('%s rule on the %s, factor %s',obj.RejectMethod,feat,g(obj.RejectFactor));
                if obj.RejectUpperOnly, rule = rule + ", upper side only"; end
            end
            if isinf(obj.RejectCeiling), ceil_ = "no ceiling"; else, ceil_ = "ceiling " + g(obj.RejectCeiling) + " V"; end
            L(end+1) = sprintf('Rejection: %s; %s; %s; response window %s.',rig,rule,ceil_,ms(obj.ResponseWindow));

            dm = replace(obj.DetectMethod,["tfce","clusterMass","tmax"],["TFCE","cluster-mass","t-max"]);
            L(end+1) = sprintf('Detection: %s permutation test, %d permutations, α %s, seed %d.', ...
                dm,obj.NumPermutations,g(obj.Alpha),obj.Seed);

            if isempty(obj.SplitHalfWindow), shw = "the response window";
            else, shw = ms(obj.SplitHalfWindow); end
            L(end+1) = sprintf(['Measures: baseline %s; split-half %s sub-averages, %d resamples ' ...
                'over %s, at least %d per polarity; next-louder correlation lag up to %s ms.'], ...
                ms(obj.BaselineWindow),obj.SplitHalfMode,obj.SplitHalfResamples,shw, ...
                obj.SplitHalfMinPerPolarity,g(obj.MaxLag));

            if obj.LevelParam == "", lvl = "level parameter automatic";
            else, lvl = "level parameter " + obj.LevelParam; end
            % The grouping as estimateThresholds will apply it: a typed list
            % always keeps stimuli (and, unpooled, acquisition modes) apart.
            if isempty(obj.GroupBy)
                grp = "series of every condition sharing all but the level";
            else
                always = "Stimulus";
                if ~obj.PoolAcqModes, always(end+1) = "AcqMode"; end
                extra = always(~ismember(always,obj.GroupBy));
                grp = "series by " + strjoin(obj.GroupBy,", ");
                if ~isempty(extra), grp = grp + " (and " + strjoin(extra," and ") + ", always)"; end
            end
            L(end+1) = sprintf(['Thresholds: %s Convention %s; at least %d clean sweeps (%d per ' ...
                'polarity) per level; %s; %s; direction %s.'],obj.thresholdDefinition(), ...
                replace(obj.ThresholdConvention,"_"," "),obj.MinSweeps,obj.MinPerPolarity,lvl,grp, ...
                obj.LevelDirection);

            Wv = obj.Waves;
            on = logical([Wv.Enabled]);
            % (No enabled wave concatenates to [], a double strjoin refuses.)
            if any(on), names = strjoin([Wv(on).Name],", "); else, names = "none"; end
            if obj.PeakBootstrap > 0, bs = sprintf('%d bootstrap replicates',obj.PeakBootstrap);
            else, bs = "no bootstrap"; end
            L(end+1) = sprintf(['Peaks: %d waves (%s); %s ms per octave re %s kHz; separation %s ms; ' ...
                'tracking -%s/+%s ms; candidates at %sxRN, detectable at %sxRN; %s polarity; %s.'], ...
                sum(on),names,g(obj.PeakOctaveShift),g(obj.PeakRefFrequency),g(obj.PeakMinSeparation), ...
                g(obj.PeakTrackEarly),g(obj.PeakTrackLate),g(obj.PeakCandidateRN), ...
                g(obj.PeakDetectableRN),obj.PeakPolarity,bs);

            % e.g. "Latencies re sound arrival: 0.29 ms conduction delay (10 cm
            % at 343 m/s)." A computed delay is given to 10 us; a typed one as
            % typed.
            f2 = @(v) string(sprintf('%.2f',v));
            switch obj.ConductionDelayMode
                case "distance"
                    ref = sprintf('Latencies re sound arrival: %s ms conduction delay (%s cm at %s m/s)', ...
                        f2(obj.conductionDelay()),g(obj.SpeakerDistance),g(obj.SpeedOfSound));
                case "delay"
                    ref = sprintf('Latencies re sound arrival: %s ms conduction delay',g(obj.ConductionDelay));
                otherwise
                    ref = "Latencies re stimulus onset (no conduction delay)";
            end
            if obj.TimeOffset ~= 0
                if obj.ConductionDelayMode == "none"
                    ref = sprintf('%s, less a %s ms system offset',ref,g(obj.TimeOffset));
                else
                    ref = sprintf('%s plus a %s ms system offset, %s ms in all',ref, ...
                        g(obj.TimeOffset),f2(obj.latencyOffset()));
                end
            end
            L(end+1) = string(ref) + ".";
            d = strjoin(L,newline);
        end
    end

    methods (Static)
        % =================================================================
        %  Plain structs, prefs, files
        % =================================================================
        function [s,warn] = fromStruct(st)
            % Settings from a plain struct, forgivingly.
            %
            % Every known field is assigned on its own: an unknown field is
            % ignored, and one this class refuses (wrong type or shape) keeps
            % its default and adds a line to warn -- a settings file from an
            % older or newer MABR, or a pref edited by hand, must still give
            % usable settings.
            %
            %   st    scalar struct (toStruct's shape)
            %   s     (returned) mabr.analysis.Settings
            %   warn  (returned) string column, one line per refused field
            s = mabr.analysis.Settings();
            warn = strings(0,1);
            if ~isstruct(st) || ~isscalar(st)
                warn(end+1,1) = "Settings are not a struct; the defaults are used.";
                return
            end
            if isfield(st,'SettingsVersion') && isnumeric(st.SettingsVersion) && ...
                    isscalar(st.SettingsVersion) && st.SettingsVersion > mabr.analysis.Settings.SettingsVersion
                warn(end+1,1) = sprintf(['These settings were written by a newer MABR (settings ' ...
                    'version %g); fields this version does not know are ignored.'],st.SettingsVersion);
            end
            T  = mabr.analysis.Settings.fieldSteps();
            mc = ?mabr.analysis.Settings;
            for k = 1:size(T,1)
                nm = T(k,1);
                if ~isfield(st,nm), continue; end
                v = st.(nm);
                try
                    v = mabr.analysis.Settings.shapeFor(mc,nm,v);
                    s.(nm) = v;
                catch ME
                    warn(end+1,1) = sprintf('%s: %s The default (%s) is used.', ...
                        nm,ME.message,mabr.analysis.Settings.valueText(s.(nm))); %#ok<AGROW>
                end
            end
        end

        function s = loadPrefs()
            % The settings last saved by a user (pref MABR/OfflineAnalysisSettings).
            % Any problem reading it gives the defaults.
            %   s  (returned) mabr.analysis.Settings
            s = mabr.analysis.Settings();
            try
                g = char(mabr.analysis.Settings.PrefGroup);
                n = char(mabr.analysis.Settings.PrefName);
                if ispref(g,n)
                    s = mabr.analysis.Settings.fromStruct(getpref(g,n));
                end
            catch
                s = mabr.analysis.Settings();
            end
        end

        function savePrefs(s)
            % Remember s as the user's settings. Call it ONLY from a control a
            % user pressed (a dialog's OK/Apply) -- never from a setter, a
            % script or a test, which must not change a rig's defaults.
            %   s  mabr.analysis.Settings
            arguments
                s (1,1) mabr.analysis.Settings
            end
            setpref(char(mabr.analysis.Settings.PrefGroup), ...
                char(mabr.analysis.Settings.PrefName),s.toStruct());
        end

        function [s,warn] = load(ffn)
            % Read a .mabraset file written by save().
            %   ffn   file path
            %   s     (returned) mabr.analysis.Settings
            %   warn  (returned) string column (fromStruct's)
            arguments
                ffn (1,1) string
            end
            S = load(char(ffn),'-mat');
            if ~isfield(S,'MABRAnalysisSettings')
                error('mabr:analysis:Settings:badFile', ...
                    '%s holds no MABRAnalysisSettings variable.',ffn);
            end
            [s,warn] = mabr.analysis.Settings.fromStruct(S.MABRAnalysisSettings);
        end

        % =================================================================
        %  Steps and differences
        % =================================================================
        function st = stepOf(name)
            % The first analysis step that reads a setting.
            %   name  property name
            %   st    (returned) "segment".."peaks", "report" (applied only
            %         when numbers are shown) or "none" (a label or constant)
            arguments
                name {mustBeTextScalar}
            end
            name = string(name);
            T = mabr.analysis.Settings.fieldSteps();
            k = find(T(:,1) == name,1);
            if ~isempty(k)
                st = T(k,2);
            elseif ismember(name,["SettingsVersion","Steps","PrefGroup","PrefName"])
                st = "none";
            else
                error('mabr:analysis:Settings:unknownField', ...
                    '"%s" is not an analysis setting.',name);
            end
        end

        function D = diff(a,b)
            % The settings that differ between a and b (Profile, a label, is
            % not compared).
            %   a, b  mabr.analysis.Settings
            %   D     (returned) table Field, Step, Old, New (strings), one
            %         row per differing setting, in property order
            arguments
                a (1,1) mabr.analysis.Settings
                b (1,1) mabr.analysis.Settings
            end
            T = mabr.analysis.Settings.fieldSteps();
            f = strings(0,1); st = f; old = f; new = f;
            for k = 1:size(T,1)
                nm = T(k,1);
                if nm == "Profile", continue; end
                if ~isequaln(a.(nm),b.(nm))
                    f(end+1,1)   = nm; %#ok<AGROW>
                    st(end+1,1)  = T(k,2); %#ok<AGROW>
                    old(end+1,1) = mabr.analysis.Settings.valueText(a.(nm)); %#ok<AGROW>
                    new(end+1,1) = mabr.analysis.Settings.valueText(b.(nm)); %#ok<AGROW>
                end
            end
            D = table(f,st,old,new,'VariableNames',{'Field','Step','Old','New'});
        end

        function k = firstChangedStep(a,b)
            % The earliest analysis step whose settings differ, "" if none.
            %   a, b  mabr.analysis.Settings
            %   k     (returned) one of Settings.Steps, or ""
            arguments
                a (1,1) mabr.analysis.Settings
                b (1,1) mabr.analysis.Settings
            end
            k = "";
            for step = mabr.analysis.Settings.Steps
                if ~isequaln(a.stepSettings(step),b.stepSettings(step))
                    k = step;
                    return
                end
            end
        end

        % =================================================================
        %  Profiles
        % =================================================================
        function n = profileNames()
            % The built-in profiles. n: (returned) string row.
            n = ["MABR default","Legacy SCRATCH (2025)"];
        end

        function s = profile(name)
            % A built-in profile by name.
            %   name  one of profileNames()
            %   s     (returned) mabr.analysis.Settings with Profile = name
            arguments
                name {mustBeTextScalar}
            end
            name = string(name);
            s = mabr.analysis.Settings();
            switch name
                case "MABR default"
                    % the class defaults
                case "Legacy SCRATCH (2025)"
                    % The 2025 batch pipeline (abr_analysis/), as one setting set.
                    s.DetectMethod       = "tfce";
                    s.NumPermutations    = 2000;
                    s.ThresholdMethod    = "custom";
                    s.ThresholdMetric    = "detection";
                    s.ThresholdModel     = "glm";
                    s.CriterionMode      = "probability";
                    s.Criterion          = 0.75;
                    s.Detrend            = 1;
                    s.HighPass           = [150 300];
                    s.LowPass            = [1500 3000];
                    s.FilterPassRippleDb = 0.5;
                    s.FilterStopAttenDb  = 30;
                    s.Window             = [-12 12];
                    s.ResponseWindow     = [0 10];
                    s.RejectMethod       = "median";
                    s.RejectFeature      = "absPeak";
                    s.RejectFactor       = 3;
                    s.RejectUpperOnly    = false;
                    s.PoolAcqModes       = true;
                    s.MinSweeps          = 2;
                    s.MinPerPolarity     = 0;
                    s.MinConsecutive     = 1;
                otherwise
                    error('mabr:analysis:Settings:unknownProfile', ...
                        'No profile "%s". Known: %s.',name, ...
                        strjoin(mabr.analysis.Settings.profileNames(),', '));
            end
            s.Profile = name;
        end

        % =================================================================
        %  Waves
        % =================================================================
        function why = waveNameProblem(name,used)
            % Why a wave cannot be called name, or '' if it can: a name must
            % not be blank, not all digits (the organizer's own labels for the
            % peaks it numbers) and not the name of another wave in any case.
            % A copy of mabr.analysis.Peaks.nameProblem, held to it by the
            % verification test, so that Settings does not depend on Peaks.
            %   name  text scalar
            %   used  the other waves' names (string/cellstr/char array)
            %   why   (returned) char, '' when the name is fine
            arguments
                name
                used = strings(0,1)
            end
            name = string(name);
            if isempty(name) || all(ismissing(name)), name = ""; end
            name = strtrim(char(name(1)));
            used = string(used);
            used = strtrim(used(~ismissing(used)));
            why  = '';
            if isempty(name)
                why = 'A wave needs a name.';
            elseif ~isempty(regexp(name,'^\d+$','once'))
                why = sprintf(['"%s" is a plain number, which is how unnamed peak ' ...
                    'markers are numbered. Use a letter or a name (VI, A, N1 ...).'],name);
            elseif any(strcmpi(name,cellstr(used)))
                why = sprintf('There is already a wave named "%s".',name);
            end
        end

        function txt = canonicalText(st)
            % The canonical text hash() is taken of (see hash). st: scalar
            % struct. txt: (returned) 1x1 string.
            names = sort(string(fieldnames(st))).';
            parts = strings(1,numel(names));
            for k = 1:numel(names)
                parts(k) = names(k) + "=" + mabr.analysis.Settings.canonicalValue(st.(names(k)));
            end
            txt = strjoin(parts,";");
        end
    end

    methods (Static, Access = private)
        function T = fieldSteps()
            % Every setting with the first step that reads it, in property
            % order. The single list toStruct, stepOf, diff and the
            % constructor work from; the verification test holds it equal
            % to the class's properties. The latency reference (the last
            % five) is a peaks setting, not a report-only one: it places the
            % wave windows (Peaks.wavesFor's Offset) as well as deciding what
            % reported latencies are re, so changing it re-fits peaks.
            T = [ ...
                "Profile","none"
                "Window","segment"
                "ResponseWindow","reject"
                "BaselineWindow","measure"
                "BaselineAmpWindow","peaks"
                "HighPass","segment"
                "LowPass","segment"
                "FilterPassRippleDb","segment"
                "FilterStopAttenDb","segment"
                "Detrend","segment"
                "Processing","segment"
                "WindowedOrder","segment"
                "WindowedPadMode","segment"
                "PoolAcqModes","segment"
                "MaxSweepsPerCondition","segment"
                "EqualizeMode","segment"
                "HonorAcquisitionArtifacts","reject"
                "RejectMethod","reject"
                "RejectFeature","reject"
                "RejectFactor","reject"
                "RejectUpperOnly","reject"
                "RejectCeiling","reject"
                "DetectMethod","detect"
                "NumPermutations","detect"
                "Alpha","detect"
                "Seed","detect"
                "SplitHalfMode","measure"
                "SplitHalfResamples","measure"
                "SplitHalfWindow","measure"
                "SplitHalfMinPerPolarity","measure"
                "MaxLag","measure"
                "ThresholdMethod","thresholds"
                "ThresholdMetric","thresholds"
                "ThresholdModel","thresholds"
                "CriterionMode","thresholds"
                "Criterion","thresholds"
                "LevelParam","thresholds"
                "GroupBy","thresholds"
                "LevelDirection","thresholds"
                "MinConsecutive","thresholds"
                "ThresholdConvention","thresholds"
                "Interpolate","thresholds"
                "MinSweeps","thresholds"
                "MinPerPolarity","thresholds"
                "Extrapolate","thresholds"
                "NearestLevel","thresholds"
                "CIAlpha","thresholds"
                "CINumSamples","thresholds"
                "ThresholdBootstrap","thresholds"
                "FlagWideCI","thresholds"
                "FlagNonMonotoneTol","thresholds"
                "Waves","peaks"
                "PeakOctaveShift","peaks"
                "PeakRefFrequency","peaks"
                "PeakSmooth","peaks"
                "PeakMinSeparation","peaks"
                "PeakTrackEarly","peaks"
                "PeakTrackLate","peaks"
                "PeakCandidateRN","peaks"
                "PeakDetectableRN","peaks"
                "PeakPolarity","peaks"
                "PeaksAboveThresholdOnly","peaks"
                "PeakBootstrap","peaks"
                "PeakEdgeMs","peaks"
                "ConductionDelayMode","peaks"
                "ConductionDelay","peaks"
                "SpeakerDistance","peaks"
                "SpeedOfSound","peaks"
                "TimeOffset","peaks"];
        end

        function v = shapeFor(mc,name,v)
            % Refuse, before assignment, a value whose size the property
            % would silently EXPAND (a scalar into a [1 2] window) rather than
            % reject; orient vectors as the property's rows. mc: the metaclass.
            p = mc.PropertyList(string({mc.PropertyList.Name}) == name);
            if isempty(p) || isempty(p.Validation), return; end
            % A number field takes numbers: assignment would turn text into
            % its character codes ('ab' -> [97 98]), a valid-looking window.
            cls = '';
            if ~isempty(p.Validation.Class), cls = p.Validation.Class.Name; end
            if any(strcmp(cls,{'double','logical'})) && ~(isnumeric(v) || islogical(v))
                error('mabr:analysis:Settings:badValue','Expected a %s value, got %s.',cls,class(v));
            end
            if isempty(p.Validation.Size), return; end
            dims = p.Validation.Size;
            fixed = arrayfun(@(d) isprop(d,'Length'),dims);
            if isnumeric(v) || islogical(v) || isstring(v)
                if numel(dims) == 2 && ~fixed(2) && fixed(1) && dims(1).Length == 1 && isvector(v)
                    v = reshape(v,1,[]);                         % (1,:)
                elseif all(fixed)
                    want = prod(arrayfun(@(d) d.Length,dims));
                    if numel(v) ~= want
                        error('mabr:analysis:Settings:badValue', ...
                            'Expected %d value(s), got %d.',want,numel(v));
                    end
                    if isvector(v), v = reshape(v,arrayfun(@(d) d.Length,dims)); end
                end
            elseif ischar(v) && all(fixed) && prod(arrayfun(@(d) d.Length,dims)) == 1
                v = string(v);                                  % 'x' -> "x"
            end
        end

        function W = normalizeWaves(v)
            % Waves in their one canonical shape: a 1xN struct array with
            % fields Name (string), Enabled (logical), TMin, TMax, Expected,
            % LatencyShift (double) and Stimulus (string). Missing Expected
            % is the window centre, missing LatencyShift 0.02 ms/dB (the
            % shift of a wave added to the table: Peaks.AddedLatencyShift,
            % held equal by the verification test), missing Stimulus "" (every
            % stimulus), missing Enabled true. A table is accepted. Names are
            % trimmed but not judged here -- problems() does that, so a dialog
            % can hold a half-typed table.
            proto = struct('Name',"",'Enabled',true,'TMin',NaN,'TMax',NaN, ...
                'Expected',NaN,'LatencyShift',0.02,'Stimulus',"");
            if istable(v), v = table2struct(v); end
            if isempty(v)
                W = repmat(proto,1,0);
                return
            end
            if ~isstruct(v)
                error('mabr:analysis:Settings:badWaves', ...
                    'Waves is a struct array (Name, Enabled, TMin, TMax, Expected, LatencyShift, Stimulus).');
            end
            for f = ["Name","TMin","TMax"]
                if ~isfield(v,f)
                    error('mabr:analysis:Settings:badWaves','Waves have no %s field.',f);
                end
            end
            W = repmat(proto,1,numel(v));
            for k = 1:numel(v)
                e = v(k);
                nm = e.Name;
                if iscell(nm) && isscalar(nm), nm = nm{1}; end
                if ~(ischar(nm) || (isstring(nm) && isscalar(nm)))
                    error('mabr:analysis:Settings:badWaves','Wave %d: Name is not text.',k);
                end
                W(k).Name = strtrim(string(nm));
                t0 = mabr.analysis.Settings.waveNumber(e.TMin,k,'TMin');
                t1 = mabr.analysis.Settings.waveNumber(e.TMax,k,'TMax');
                W(k).TMin = t0;
                W(k).TMax = t1;
                if isfield(e,'Enabled') && ~isempty(e.Enabled)
                    W(k).Enabled = logical(e.Enabled(1));
                end
                if isfield(e,'Expected') && ~isempty(e.Expected) && isfinite(double(e.Expected(1)))
                    W(k).Expected = mabr.analysis.Settings.waveNumber(e.Expected,k,'Expected');
                else
                    W(k).Expected = (t0+t1)/2;
                end
                if isfield(e,'LatencyShift') && ~isempty(e.LatencyShift)
                    W(k).LatencyShift = mabr.analysis.Settings.waveNumber(e.LatencyShift,k,'LatencyShift');
                end
                if isfield(e,'Stimulus') && ~isempty(e.Stimulus)
                    st = e.Stimulus;
                    if iscell(st) && isscalar(st), st = st{1}; end
                    if ~(ischar(st) || (isstring(st) && isscalar(st)))
                        error('mabr:analysis:Settings:badWaves','Wave %d: Stimulus is not text.',k);
                    end
                    W(k).Stimulus = string(st);
                end
            end
        end

        function x = waveNumber(v,k,what)
            % One finite number of a wave row (k, what: for the message).
            if ~(isnumeric(v) && isscalar(v) && isfinite(v))
                error('mabr:analysis:Settings:badWaves','Wave %d: %s is not a finite number.',k,what);
            end
            x = double(v);
        end

        function s = canonicalValue(v)
            % One value of canonicalText.
            if isstruct(v)
                el = strings(1,numel(v));
                for i = 1:numel(v)
                    names = sort(string(fieldnames(v(i)))).';
                    parts = strings(1,numel(names));
                    for k = 1:numel(names)
                        parts(k) = names(k) + "=" + mabr.analysis.Settings.canonicalValue(v(i).(names(k)));
                    end
                    el(i) = "{" + strjoin(parts,";") + "}";
                end
                s = "[" + strjoin(el,",") + "]";
            elseif isstring(v) || ischar(v) || iscellstr(v)
                v = string(v);
                s = strjoin("""" + v(:).' + """",",");
            elseif islogical(v)
                t = ["false","true"];
                s = strjoin(t(double(v(:).')+1),",");
            elseif isnumeric(v)
                % "+ 0" turns -0 into 0: equal settings (isequaln says -0 and
                % 0 are) must hash equal, and %.17g would print "-0".
                s = strjoin(compose("%.17g",double(v(:).') + 0),",");
            else
                s = "<" + string(class(v)) + ">";
            end
            if isempty(s) || ismissing(s), s = ""; end
        end

        function t = valueText(v)
            % A setting's value as a person reads it (diff's Old/New).
            if isstruct(v)
                if isempty(v), t = "no waves"; return; end
                parts = strings(1,numel(v));
                for i = 1:numel(v)
                    parts(i) = sprintf('%s %g–%g',v(i).Name,v(i).TMin,v(i).TMax);
                    if ~v(i).Enabled, parts(i) = parts(i) + " (off)"; end
                    if v(i).Stimulus ~= "", parts(i) = parts(i) + " [" + v(i).Stimulus + "]"; end
                end
                t = strjoin(parts,", ") + " ms";
            elseif isstring(v) || ischar(v)
                v = string(v);
                if isempty(v), t = "(none)";
                else, t = strjoin(v,", "); end
            elseif islogical(v) && isscalar(v)
                if v, t = "true"; else, t = "false"; end
            elseif isnumeric(v) || islogical(v)
                if isempty(v)
                    t = "[]";
                elseif isscalar(v)
                    t = string(sprintf('%g',v));
                else
                    t = "[" + strjoin(compose("%g",double(v(:).'))," ") + "]";
                end
            else
                t = "<" + string(class(v)) + ">";
            end
        end
    end
end
