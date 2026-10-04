classdef SyntheticABR
% mabrtest.SyntheticABR  Ground-truth .abr datasets for the offline-analysis tests.
%
%   Writes real .abr files -- the ABR_Data struct mabr.data.io.buildStruct
%   writes today, field for field -- holding a response whose every parameter
%   is known: the level at which it appears, where each wave's peak and trough
%   sit, how large they are, and everything laid on top of it. A test reads
%   the files through the same code a user's data goes through and compares
%   what comes out with the truth that went in.
%
%       truth = mabrtest.SyntheticABR.defaults();
%       info  = mabrtest.SyntheticABR.writeSession(folder,truth);
%       y     = mabrtest.SyntheticABR.template(tMs,80,8,info.Truth);
%       W     = mabrtest.SyntheticABR.waveTruth(80,8,info.Truth);
%       study = mabrtest.SyntheticABR.writeStudy(root,truth);
%       c     = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(root));
%
%   THE RESPONSE. Five waves, I-V, each a Gaussian peak followed 0.45 ms later
%   by a Gaussian trough 0.8 times as deep. Latency lengthens as level falls (a
%   slope per wave) and as frequency falls (0.25 ms an octave below 16 kHz; a
%   click is 0.2 ms early). Amplitude is EXACTLY zero below each condition's
%   threshold and grows monotonically from 0.35 of its scale at threshold, so
%   "no response" means none and detection truth is crisp. template() is that
%   response, noiseless; waveTruth() tabulates its Gaussian centres and
%   heights. Every sweep then gets
%     - a gain, N(1,AmplitudeJitter) times a linear decline of Drift from the
%       first sweep to the last, renormalized so a file's gains average 1;
%     - a latency shift, N(0,LatencyJitter) ms, centred to average 0 -- so the
%       mean of a file's sweeps is template() widened by the jitter alone
%       (peaks ~3% lower at the defaults; LatencyJitter = 0 makes it exact);
%     - a cochlear microphonic that FOLLOWS polarity, a damped 1 kHz
%       oscillation neither jittered nor scaled: it cancels exactly in a
%       polarity-balanced mean and shows in (+)-(-), which is what makes it a
%       trap for a +/- noise reference whose signs follow polarity;
%   and every trace white noise (NoiseSD) plus 60 Hz hum of random phase. In
%   every continuous file sweeps 5, 40 and 77 carry a +/-250 uV, 2 ms
%   transient, of which ADC.IsArtifact flags only 40, as a rig that missed two
%   would. Volts at the electrodes throughout, as ADC.Data is.
%
%   THE FILES are written as the rig writes them. A CONTINUOUS file is one
%   condition's whole run: LeadSamples, nSweeps onsets ISISamples apart, then
%   TailSamples. A COMPACT file is one condition's share of an intermixed run:
%   all tone conditions are presented in one shuffled stream (the 'shuffled'
%   strategy -- each condition's polarities balanced but not alternating in
%   file order, as on the rig), and each condition's [onset, onset+L-1]
%   windows are then cut back to back exactly as
%   mabr.compute.Pipeline.compact_sweeps does: Data is n*L long, SweepOnsets
%   is (0:n-1)'*L+1, there is no pre-onset sample, and every file of the run
%   shares one StartTime. writeSession's options add the variants a reader
%   meets in the wild: an E0-era (legacy +abr) file, a Test Mode file, an
%   11025 Hz file, a truncated compact window, notes in every file and in a
%   .notes journal, and the three naming styles files have carried.
%
%   DETERMINISM. Every draw comes from a RandStream('threefry') of its own,
%   seeded truth.Seed plus a key per file, with a substream per purpose
%   (noise, hum, sweep gains and shifts, presentation order) -- never the
%   global stream, since these run inside mabr.ui.TestRunner beside tests that
%   seed rng themselves. The same call writes the same samples, and zeroing
%   one ingredient (NoiseSD, say) leaves every other draw where it was.
%
%   See also mabr.data.io, mabr.compute.Pipeline, mabr.analysis.Session,
%   mabr.data.SessionNotes, verify_analysis.
%
% Daniel Stolzberg (c) 2026

    methods (Static)
        function truth = defaults()
            % The ground truth every dataset is built from: small and fast.
            %
            %   truth  (returned) struct:
            %     Fs, ISISamples, SweepLength    12000 Hz; 292 (24.33 ms); 120 (10 ms)
            %     LeadSamples, TailSamples       1500 before the first onset, 600
            %                                    after the last sweep's ISI
            %     Freqs, Levels                  [4 8 16] kHz; 0:10:80 dB
            %     Threshold                      [30 20 40]: the first level WITH a
            %                                    response, one per Freqs
            %     ClickThreshold                 30
            %     nSweeps, Polarity              128 per condition (even);
            %                                    "alternate" | "positive"
            %     NoiseSD, Hum, HumFrequency     6e-6 V white per sample; 0.5e-6 V
            %                                    amplitude at 60 Hz
            %     Waves                          struct: Name ["I".."V"], Latency80
            %                                    (ms at 80 dB, 16 kHz), LatencySlope
            %                                    (ms per dB below 80), PeakAmp80 (V,
            %                                    each wave's scale), Width (ms, the
            %                                    Gaussians' SD), TroughDelay (ms),
            %                                    TroughRatio (trough depth / peak)
            %     GrowthFloor, GrowthTau         amplitude = PeakAmp80 x (Floor +
            %                                    (1-Floor)(1-exp(-(L-thr)/Tau))) at
            %                                    and above threshold, 0 below; so at
            %                                    80 dB it is below PeakAmp80
            %     OctaveLatency, RefFrequency    +0.25 ms per octave below 16 kHz
            %     ClickLatencyOffset             -0.2 ms
            %     CMAmp80, CMSlope,              3e-6 V x 10^((L-80)/40), 1000 Hz,
            %       CMFrequency, CMTau           decaying with a 1.5 ms constant
            %     AmplitudeJitter, LatencyJitter 0.2 (SD of the gain); 0.03 ms (SD)
            %     Drift                          0.2: the gain falls 20% from the
            %                                    first sweep to the last
            %     ArtifactSweeps, FlaggedSweeps  [5 40 77]; 40 (ADC.IsArtifact)
            %     ArtifactAmp, ArtifactDuration, 250e-6 V peak, one 2 ms cycle,
            %       ArtifactOnset                starting 3 ms after the onset
            %     AmplifierGain, InputFullScale, 1000, 0.354, 192000: recorded in
            %       DACSampleRate                the files, never applied (Data is
            %                                    already volts at the electrodes)
            %     Seed                           20261001
            truth = struct();
            truth.Fs                 = 12000;
            truth.ISISamples         = 292;
            truth.SweepLength        = 120;
            truth.LeadSamples        = 1500;
            truth.TailSamples        = 600;
            truth.Freqs              = [4 8 16];
            truth.Levels             = 0:10:80;
            truth.Threshold          = [30 20 40];
            truth.ClickThreshold     = 30;
            truth.nSweeps            = 128;
            truth.Polarity           = "alternate";
            truth.NoiseSD            = 6e-6;
            truth.Hum                = 0.5e-6;
            truth.HumFrequency       = 60;
            truth.Waves = struct( ...
                'Name',         ["I" "II" "III" "IV" "V"], ...
                'Latency80',    [1.40 2.20 3.00 3.90 4.80], ...
                'LatencySlope', [0.015 0.018 0.020 0.025 0.030], ...
                'PeakAmp80',    [2.0 1.0 1.5 1.2 2.5]*1e-6, ...
                'Width',        0.12, ...
                'TroughDelay',  0.45, ...
                'TroughRatio',  0.8);
            truth.GrowthFloor        = 0.35;
            truth.GrowthTau          = 25;
            truth.OctaveLatency      = 0.25;
            truth.RefFrequency       = 16;
            truth.ClickLatencyOffset = -0.2;
            truth.CMAmp80            = 3e-6;
            truth.CMSlope            = 40;
            truth.CMFrequency        = 1000;
            truth.CMTau              = 1.5;
            truth.AmplitudeJitter    = 0.2;
            truth.LatencyJitter      = 0.03;
            truth.Drift              = 0.2;
            truth.ArtifactSweeps     = [5 40 77];
            truth.FlaggedSweeps      = 40;
            truth.ArtifactAmp        = 250e-6;
            truth.ArtifactDuration   = 2;
            truth.ArtifactOnset      = 3;
            truth.AmplifierGain      = 1000;
            truth.InputFullScale     = 0.354;
            truth.DACSampleRate      = 192000;
            truth.Seed               = 20261001;
        end

        function info = writeSession(folder,truth,opts)
            % Write one session folder of .abr files, and say what is in it.
            %
            %   info = writeSession(folder,truth,Name=Value)
            %
            %   folder               created if absent; files already in it are
            %                        kept (a clashing name gets _2, as
            %                        mabr.data.io.writeABR's does)
            %   truth                from defaults() (the default)
            %   opts.Subject         "SUBJ-ID-9001", the subject as typed on the rig
            %   opts.Start           datetime(2026,10,1,10,0,0): the first file's
            %                        StartTime; each later file is 15 s on
            %   opts.Stimuli         "Tone" | ["Tone" "ClickTrain"] | "ClickTrain";
            %                        a click has no Frequency (NaN in info)
            %   opts.Layout          "continuous" | "compact" | "both" (one of each
            %                        per tone condition, as in a folder that
            %                        holds a conventional and an intermixed run).
            %                        Clicks are always continuous
            %   opts.ThresholdShift  dB added to every threshold (0)
            %   opts.ShiftByFreq     dB added per truth.Freqs ([] = none)
            %   opts.AmplitudeScale  multiplies wave I only (1), synaptopathy-like
            %   opts.Notes           note texts ({}): written into ABR_Data.Notes
            %                        (each file holds the notes taken before it
            %                        ended, as on the rig) and a .notes journal
            %   opts.Legacy          add one E0-era file (false): no SoftwareVersion,
            %                        lowercase {'frequency','soundLevel'} read off
            %                        SIG.dataParams (Hz), the sigProp fields as the
            %                        uint32 placeholders MATLAB loads a missing
            %                        class as, 'dd-MMM-yyyy HH:mm:ss' StartTime,
            %                        scalar IsArtifact, Data in converter units
            %   opts.TestModeFile    add one TestMode file (false); its samples are
            %                        a 1 kHz pip at each onset, the stimulus
            %   opts.OtherRateFile   add one file at 11025 Hz (false)
            %   opts.Truncated       stop the intermixed run 6 ms into its last
            %                        presentation, so that window is zero-filled
            %                        after 6 ms (false; needs a compact layout)
            %   opts.NamingStyle     "current"  SUBJ-ID-9001_Frequency-8kHz_Level-30dB_<stamp>.abr
            %                        "old"      the writer before 219549d: the typed
            %                                   subject kept, then _Frequency_8kHz_
            %                                   Level_30dB_<stamp>; anything else
            %                                   makeValidName'd (SUBJ_ID_9001_ClickTrain_
            %                                   SoundLevel80_<stamp>)
            %                        "stimgen"  every file makeValidName'd from its
            %                                   stimulus ID, tones included
            %                        The legacy file is always named as E0 named it.
            %
            %   info  (returned) struct:
            %     Folder, Subject
            %     Files       table, one row per .abr in write order: FileName,
            %                 Stimulus ("Tone"/"ClickTrain"), Level, Frequency,
            %                 Layout ("continuous"/"compact"), nSweeps,
            %                 ArtifactSweeps and FlaggedSweeps (cells of sweep
            %                 indices), TestMode, SampleRate, Legacy, Truncated,
            %                 StartTime, SweepGain and SweepJitter (cells, per
            %                 sweep in file order: the gain and the latency shift
            %                 in ms each was given -- empty for the TestMode file)
            %     Thresholds  table Stimulus, Frequency, Threshold, FirstLevel
            %                 (the first PRESENTED level with a response, Inf if none)
            %     Truth       truth with the shifts applied: hand it to template
            %                 and waveTruth to describe THESE files
            %     Notes       the note texts (cellstr)
            %     NotesFile   the .notes journal ('' when there are no notes)
            arguments
                folder (1,1) string
                truth  (1,1) struct = mabrtest.SyntheticABR.defaults()
                opts.Subject (1,1) string = "SUBJ-ID-9001"
                opts.Start (1,1) datetime = datetime(2026,10,1,10,0,0)
                opts.Stimuli (1,:) string {mustBeNonempty,mustBeMember(opts.Stimuli,["Tone" "ClickTrain"])} = "Tone"
                opts.Layout (1,1) string {mustBeMember(opts.Layout,["continuous" "compact" "both"])} = "continuous"
                opts.ThresholdShift (1,1) double = 0
                opts.ShiftByFreq double = []
                opts.AmplitudeScale (1,1) double {mustBeNonnegative} = 1
                opts.Notes {mustBeText} = {}
                opts.Legacy (1,1) logical = false
                opts.TestModeFile (1,1) logical = false
                opts.OtherRateFile (1,1) logical = false
                opts.Truncated (1,1) logical = false
                opts.NamingStyle (1,1) string {mustBeMember(opts.NamingStyle,["current" "old" "stimgen"])} = "current"
            end
            folder = char(folder);
            checkTruth(truth);
            T = withShifts(truth,opts.ThresholdShift,opts.ShiftByFreq,opts.AmplitudeScale);

            stims    = unique(opts.Stimuli,'stable');
            hasTone  = any(stims == "Tone");
            hasClick = any(stims == "ClickTrain");
            if opts.Layout ~= "continuous" && ~hasTone
                error('mabrtest:SyntheticABR:compactNeedsTones', ...
                    'A "%s" layout intermixes the tone conditions, and Stimuli has no Tone.', ...
                    opts.Layout);
            end
            if opts.Truncated && opts.Layout == "continuous"
                error('mabrtest:SyntheticABR:truncatedNeedsCompact', ...
                    'Truncated cuts short the intermixed run; Layout "continuous" has none.');
            end
            if opts.Legacy && ~hasTone
                error('mabrtest:SyntheticABR:legacyNeedsTones', ...
                    'The legacy (E0) file is a tone file, and Stimuli has no Tone.');
            end
            if ~isfolder(folder), mkdir(folder); end

            % ---- The plan: every file, in the order a rig would write them.
            % Seed keys are fixed per condition, so a file's samples do not
            % depend on which other files a call asked for.
            nF = numel(T.Freqs);  nL = numel(T.Levels);  [~,top] = max(T.Levels);
            jobs = newJob("","",NaN,NaN,0,0,0,"");  jobs(1) = [];
            if hasTone && opts.Layout ~= "compact"
                for fi = 1:nF
                    for li = nL:-1:1                     % a threshold series, loudest first
                        jobs(end+1) = newJob("tone","Tone",T.Levels(li),T.Freqs(fi), ...
                            fi,li,100*fi+li,"tone"); %#ok<AGROW>
                    end
                end
            end
            if hasTone && opts.Layout ~= "continuous"
                jobs(end+1) = newJob("compact","Tone",NaN,NaN,0,0,6000,"compact");
            end
            if hasClick
                for li = nL:-1:1
                    jobs(end+1) = newJob("click","ClickTrain",T.Levels(li),NaN, ...
                        0,li,5000+li,"click"); %#ok<AGROW>
                end
            end
            % The extras each stand for a different condition, so they never
            % share a name with one another.
            if opts.Legacy
                jobs(end+1) = newJob("legacy","Tone",T.Levels(top),T.Freqs(1), ...
                    1,top,7001,"legacy");
            end
            if opts.TestModeFile
                [st,fr,fi] = extraStimulus(hasTone,T,min(2,nF));
                jobs(end+1) = newJob("testmode",st,T.Levels(top),fr,fi,top,7002,"testmode");
            end
            if opts.OtherRateFile
                [st,fr,fi] = extraStimulus(hasTone,T,nF);
                jobs(end+1) = newJob("otherrate",st,T.Levels(top),fr,fi,top,7003,"otherrate");
            end
            jobs = schedule(jobs,T,opts.Start);

            % ---- The notebook, opened ten minutes before the first run.
            bookStart = opts.Start - minutes(10);
            texts = reshape(cellstr(opts.Notes),1,[]);
            [notes,noteTimes] = noteRecords(texts,jobs,bookStart);

            % ---- Render and write.
            calTime = char(dateshift(opts.Start,'start','day') - hours(8),'yyyy-MM-dd HH:mm:ss');
            rows = {};
            for k = 1:numel(jobs)
                q = jobs(k);
                N = notesUpTo(notes,noteTimes,q.Start + seconds(q.Duration));
                switch q.Kind
                    case {"tone","click","otherrate","testmode"}
                        isTM = q.Kind == "testmode";
                        if isTM, R = renderTestMode(T,q); else, R = renderContinuous(T,q); end
                        [SIG,meta] = sigFor(q.Stim,q.Level,q.Freq,q.FI,q.LI,T,calTime);
                        A = currentStruct(T,R,SIG,q.Start,N,isTM,q.Fs, ...
                            T.DACSampleRate*q.Fs/T.Fs);
                        name = writeFile(folder,fileName(opts.NamingStyle,opts.Subject,meta,q.Start),A);
                        rows{end+1} = fileRow(name,q.Stim,q.Level,q.Freq,"continuous",R, ...
                            isTM,q.Fs,false,false,q.Start); %#ok<AGROW>

                    case "compact"
                        parts = renderCompact(T,q,opts.Truncated);
                        for c = 1:numel(parts)
                            P = parts(c);
                            [SIG,meta] = sigFor("Tone",P.Level,P.Freq,P.FI,P.LI,T,calTime);
                            A = currentStruct(T,P,SIG,q.Start,N,false,T.Fs,T.DACSampleRate);
                            name = writeFile(folder,fileName(opts.NamingStyle,opts.Subject,meta,q.Start),A);
                            rows{end+1} = fileRow(name,"Tone",P.Level,P.Freq,"compact",P, ...
                                false,T.Fs,false,P.Truncated,q.Start); %#ok<AGROW>
                        end

                    case "legacy"
                        R = renderContinuous(T,q);
                        A = legacyStruct(T,q,R);
                        name = writeFile(folder,legacyName(opts.Subject,A.SIG.Label,q.Start),A);
                        R.Flagged = zeros(1,0);         % E0 never flagged a sweep
                        rows{end+1} = fileRow(name,"Tone",q.Level,q.Freq,"continuous",R, ...
                            false,q.Fs,true,false,q.Start); %#ok<AGROW>
                end
            end

            notesFile = '';
            if ~isempty(texts)
                notesFile = writeJournal(folder,opts.NamingStyle,opts.Subject,bookStart, ...
                    notes,noteTimes(end));
            end

            info = struct();
            info.Folder     = folder;
            info.Subject    = opts.Subject;
            info.Files      = filesTable(rows);
            info.Thresholds = thresholdTable(T,hasTone,hasClick);
            info.Truth      = T;
            info.Notes      = texts;
            info.NotesFile  = notesFile;
        end

        function info = writeStudy(root,truth,opts)
            % Write several subjects at several timepoints, as a study folder.
            %
            %   info = writeStudy(root,truth,Name=Value)
            %
            %   Each subject's sessions sit under root/<subject>/, as the default
            %   folder scheme puts them:
            %     <subject>_Baseline      the truth as given
            %     <subject>_2weeks        14 days later, thresholds shifted by
            %                             ShiftByFreq and wave I scaled by
            %                             AmplitudeScale
            %     <subject>_<yyMMddTHHmmss>   (first subject, Mixed = true) a
            %                             default-scheme folder at 14:00 on the
            %                             baseline day: Tone + ClickTrain, both
            %                             layouts, notes and a .notes journal
            %   Every session draws its own noise (truth.Seed + 10000 per session).
            %
            %   root                 the study folder (created if absent)
            %   truth                from defaults() (the default)
            %   opts.Subjects        ["SUBJ-ID-9001" "SUBJ-ID-9002"]; each an hour
            %                        after the last
            %   opts.Start           datetime(2026,10,1,10,0,0): the first baseline
            %   opts.ShiftByFreq     the 2-week shift per truth.Freqs ([] = +20 dB
            %                        at 16 kHz only)
            %   opts.AmplitudeScale  wave I at 2 weeks (0.6)
            %   opts.Mixed           write the mixed session (true)
            %   opts.Notes           the mixed session's note texts
            %
            %   info  (returned) struct:
            %     Root, Truth (as given)
            %     Sessions     table, one row per session: Subject, Folder (name),
            %                  Path, Timepoint ("Baseline", "2weeks", or the
            %                  yyyy-MM-dd a default-scheme folder name implies),
            %                  Layout, Stimuli ("Tone" / "ClickTrain, Tone"),
            %                  Start, NumFiles
            %     SessionInfo  struct array, writeSession's info for each row
            arguments
                root  (1,1) string
                truth (1,1) struct = mabrtest.SyntheticABR.defaults()
                opts.Subjects (1,:) string = ["SUBJ-ID-9001" "SUBJ-ID-9002"]
                opts.Start (1,1) datetime = datetime(2026,10,1,10,0,0)
                opts.ShiftByFreq double = []
                opts.AmplitudeScale (1,1) double {mustBeNonnegative} = 0.6
                opts.Mixed (1,1) logical = true
                opts.Notes {mustBeText} = {'Gerbil anesthetized with ket/xyl 80/3.2 mg/kg IP', ...
                    'Electrode impedance 3.2 kOhm', 'Ear plug slipped; reseated'}
            end
            root  = char(root);
            checkTruth(truth);
            shift = opts.ShiftByFreq;
            if isempty(shift), shift = 20*(abs(truth.Freqs - 16) < 1e-9); end
            day0  = dateshift(opts.Start,'start','day');

            % {subject, folder label, timepoint, start, writeSession options}
            plan = cell(0,5);
            for s = 1:numel(opts.Subjects)
                sub  = opts.Subjects(s);
                base = opts.Start + hours(s-1);
                plan(end+1,:) = {sub,"Baseline","Baseline",base,{}}; %#ok<AGROW>
                plan(end+1,:) = {sub,"2weeks","2weeks",base + days(14), ...
                    {'ShiftByFreq',shift,'AmplitudeScale',opts.AmplitudeScale}}; %#ok<AGROW>
                if s == 1 && opts.Mixed
                    t14 = day0 + hours(14);
                    plan(end+1,:) = {sub,string(char(t14,'yyMMdd''T''HHmmss')), ...
                        string(char(t14,'yyyy-MM-dd')),t14, ...
                        {'Stimuli',["Tone" "ClickTrain"],'Layout',"both",'Notes',opts.Notes}}; %#ok<AGROW>
                end
            end

            n = size(plan,1);
            [Subject,Folder,Path,Timepoint,Layout,Stimuli] = deal(strings(n,1));
            Start = NaT(n,1);  NumFiles = zeros(n,1);  infos = cell(n,1);
            for k = 1:n
                [sub,label,tp,t0,args] = plan{k,:};
                Tk      = truth;
                Tk.Seed = truth.Seed + 10000*(k-1);
                name    = sub + "_" + label;
                p       = fullfile(root,char(sub),char(name));
                si = mabrtest.SyntheticABR.writeSession(p,Tk,'Subject',sub,'Start',t0,args{:});

                Subject(k)   = sub;
                Folder(k)    = name;
                Path(k)      = string(p);
                Timepoint(k) = tp;
                Layout(k)    = "continuous";
                if any(si.Files.Layout == "compact"), Layout(k) = "both"; end
                Stimuli(k)   = join(reshape(sort(unique(si.Files.Stimulus)),1,[]),", ");
                Start(k)     = t0;
                NumFiles(k)  = height(si.Files);
                infos{k}     = si;
            end

            info = struct();
            info.Root        = root;
            info.Truth       = truth;
            info.Sessions    = table(Subject,Folder,Path,Timepoint,Layout,Stimuli,Start,NumFiles);
            info.SessionInfo = reshape([infos{:}],[],1);
        end

        function y = template(tMs,level,freq,truth,polarity)
            % The noiseless response planted at an onset, in volts.
            %
            %   y = template(tMs,level,freq,truth)
            %   y = template(tMs,level,freq,truth,polarity)
            %
            %   tMs       time re the onset, ms (any vector)
            %   level     dB
            %   freq      kHz, one of truth.Freqs; NaN for the click
            %   truth     from defaults(), or info.Truth for a session written
            %             with shifts
            %   polarity  0 (default) the response alone -- the expected mean of a
            %             polarity-balanced average, before jitter smoothing; +1 or
            %             -1 adds the cochlear microphonic with that sign, which is
            %             what a single sweep of that polarity carries
            %   y         (returned) column, V
            %
            %   The renderers call the same arithmetic, so with NoiseSD, Hum,
            %   AmplitudeJitter, LatencyJitter and Drift all 0 and no artifacts,
            %   each sweep of a file IS template(...,polarity), to single
            %   precision -- continuous or compact, at its own polarity.
            arguments
                tMs double {mustBeVector}
                level (1,1) double
                freq (1,1) double
                truth (1,1) struct = mabrtest.SyntheticABR.defaults()
                polarity (1,1) double {mustBeMember(polarity,[-1 0 1])} = 0
            end
            t = tMs(:);
            [lat,amp] = waveParams(level,freq,truth);
            y = abrShape(t,lat,amp,truth.Waves);
            if polarity ~= 0
                y = y + polarity*cmShape(t,level,truth);
            end
        end

        function W = waveTruth(level,freq,truth)
            % Where template() puts each wave, and how big it is.
            %
            %   W = waveTruth(level,freq,truth)
            %
            %   level, freq, truth  as for template (freq NaN = the click)
            %   W  (returned) table, one row per wave:
            %        Wave           "I".."V"
            %        PeakLatency    ms, the peak Gaussian's centre
            %        PeakAmp        V, its height (0 below threshold)
            %        TroughLatency  ms, PeakLatency + TroughDelay
            %        TroughAmp      V, signed: -TroughRatio x PeakAmp
            %        PeakToTrough   V, PeakAmp - TroughAmp
            %        Level, Frequency  the condition, so tables stack
            %
            %   These are the Gaussians' parameters. Neighbouring waves overlap a
            %   little, so the sampled extremum of template() sits within one
            %   sample of each latency and a percent or two off each amplitude.
            arguments
                level (1,1) double
                freq (1,1) double
                truth (1,1) struct = mabrtest.SyntheticABR.defaults()
            end
            [lat,amp] = waveParams(level,freq,truth);
            V  = truth.Waves;
            nW = numel(lat);
            Wave          = reshape(string(V.Name),[],1);
            PeakLatency   = lat;
            PeakAmp       = amp;
            TroughLatency = lat + perWave(V.TroughDelay,nW);
            TroughAmp     = 0 - perWave(V.TroughRatio,nW).*amp;   % 0 - : no -0 below threshold
            PeakToTrough  = PeakAmp - TroughAmp;
            Level         = repmat(level,nW,1);
            Frequency     = repmat(freq,nW,1);
            W = table(Wave,PeakLatency,PeakAmp,TroughLatency,TroughAmp,PeakToTrough, ...
                Level,Frequency);
        end

        function ok = rmdirQuiet(root)
            % Remove a folder tree without ever throwing -- for onCleanup.
            %
            %   ok = rmdirQuiet(root)
            %
            %   root  folder to remove; absent is fine. A drive root is refused.
            %   ok    (returned) true when nothing is left
            %
            %   Tries three times, a moment apart: on Windows a virus scanner or
            %   a lagging file handle can hold a just-written file briefly, and
            %   a test's cleanup failing over that is not a test failure.
            ok = true;
            root = char(root);
            if isempty(root) || ~isfolder(root), return; end
            bare = regexprep(root,'[\\/]+$','');
            if isempty(bare) || ~isempty(regexp(bare,'^[A-Za-z]:$','once'))
                ok = false;
                return
            end
            for attempt = 1:3
                ok = rmdir(root,'s');               % with an output, never throws
                if ok || ~isfolder(root), ok = true; return; end
                pause(0.2);
            end
        end
    end
end

% =========================================================================
%  The response
% =========================================================================
function [lat,amp] = waveParams(level,freq,T)
% Each wave's peak latency (ms) and height (V) for one condition, [nW x 1].
V = T.Waves;
if isnan(freq)
    thr = T.ClickThreshold;
    off = T.ClickLatencyOffset;
else
    i = find(abs(T.Freqs - freq) < 1e-9,1);
    if isempty(i)
        error('mabrtest:SyntheticABR:frequency', ...
            '%g kHz is not one of truth.Freqs (%s); NaN is the click.', ...
            freq,strjoin(compose('%g',T.Freqs),', '));
    end
    thr = T.Threshold(i);
    off = T.OctaveLatency*log2(T.RefFrequency/freq);
end
lat = V.Latency80(:) + V.LatencySlope(:)*(80 - level) + off;
amp = V.PeakAmp80(:)*growth(level,thr,T);
end

function g = growth(level,thr,T)
% Zero below threshold, then monotone towards 1.
if level < thr
    g = 0;
else
    g = T.GrowthFloor + (1 - T.GrowthFloor)*(1 - exp(-(level - thr)/T.GrowthTau));
end
end

function Y = abrShape(Tm,lat,amp,V)
% Sum of the waves' peak/trough Gaussian pairs at times Tm (ms). lat and amp
% are [nW x 1] for one condition or [nW x nCols], one column per column of Tm.
% template() and both renderers come through here, so they cannot disagree.
Y  = zeros(size(Tm));
nW = size(lat,1);
s  = perWave(V.Width,nW);
d  = perWave(V.TroughDelay,nW);
r  = perWave(V.TroughRatio,nW);
for w = 1:nW
    a = amp(w,:);
    if ~any(a), continue; end
    c = lat(w,:);
    Y = Y + a.*(exp(-0.5*((Tm - c)/s(w)).^2) - r(w)*exp(-0.5*((Tm - c - d(w))/s(w)).^2));
end
end

function Y = cmShape(t,level,T)
% The cochlear microphonic for a positive-polarity presentation: causal, so
% zero before the onset. t is [nT x 1] ms; level a scalar or one per column.
a = T.CMAmp80*10.^((reshape(level,1,[]) - 80)/T.CMSlope);
u = zeros(size(t));
m = t >= 0;
u(m) = sin(2*pi*T.CMFrequency*t(m)/1000).*exp(-t(m)/T.CMTau);
Y = u.*a;
end

function v = perWave(v,nW)
% A per-wave setting given once for all waves or once per wave, as [nW x 1].
if isscalar(v), v = repmat(v,nW,1); else, v = v(:); end
end

% =========================================================================
%  Rendering
% =========================================================================
function [gain,jit] = sweepDraws(g,j,T)
% Per-sweep gain and latency shift from raw N(0,1) draws, in file order: the
% drift is a straight line from the first sweep to the last, and both are
% renormalized so a file's gains average exactly 1 and its shifts exactly 0.
n    = numel(g);
gain = 1 + T.AmplitudeJitter*g;
if n > 1, gain = gain.*(1 - T.Drift*(0:n-1)/(n-1)); end
gain = gain/mean(gain);
jit  = T.LatencyJitter*j;
jit  = jit - mean(jit);
end

function p = polaritySeries(T,n)
% +1,-1,+1,... for an alternating condition, else all +1 -- Schedule's rule.
if string(T.Polarity) == "alternate"
    p = (-1).^(0:n-1);
else
    p = ones(1,n);
end
end

function [art,flag] = artifactSweeps(T,n)
art  = unique(T.ArtifactSweeps(T.ArtifactSweeps >= 1 & T.ArtifactSweeps <= n));
flag = unique(T.FlaggedSweeps(T.FlaggedSweeps >= 1 & T.FlaggedSweeps <= n));
art  = reshape(art,1,[]);
flag = reshape(flag,1,[]);
end

function x = addNoise(x,rs,T,fs)
% White noise over the whole trace, then the mains line at a random phase.
N = numel(x);
rs.Substream = 1;
x = x + T.NoiseSD*randn(rs,N,1);
rs.Substream = 2;
phi = 2*pi*rand(rs);
x = x + T.Hum*sin(2*pi*T.HumFrequency*(0:N-1)'/fs + phi);
end

function R = renderContinuous(T,q)
% One condition's whole run at q.Fs: each sweep's response is laid over the
% ISI that follows its onset, so no sweep spills into another's.
fs = q.Fs;  isi = q.ISI;  lead = q.Lead;  n = T.nSweeps;
rs = RandStream('threefry','Seed',T.Seed + q.Key);
rs.Substream = 3;
g = randn(rs,1,n);
j = randn(rs,1,n);
[gain,jit] = sweepDraws(g,j,T);
pol = polaritySeries(T,n);

t = (0:isi-1)'/fs*1000;                          % ms after each onset
[lat,amp] = waveParams(q.Level,q.Freq,T);
Y = abrShape(t - jit,lat,amp,T.Waves).*gain + cmShape(t,q.Level,T).*pol;

x = zeros(lead + n*isi + q.Tail,1);
x(lead+1:lead+n*isi) = Y(:);
onsets = lead + (0:n-1)'*isi + 1;

[art,flag] = artifactSweeps(T,n);
if ~isempty(art)
    nA   = round(T.ArtifactDuration*fs/1000);
    a0   = round(T.ArtifactOnset*fs/1000);
    blip = T.ArtifactAmp*sin(2*pi*(0:nA-1)'/nA);  % one cycle: +A then -A
    for a = art
        i0 = onsets(a) + a0;
        x(i0:i0+nA-1) = x(i0:i0+nA-1) + blip;
    end
end
x = addNoise(x,rs,T,fs);

R = struct('Data',single(x),'Onsets',onsets,'SweepLength',q.L,'Polarity',pol(:), ...
    'IsArtifact',ismember((1:n)',flag),'Gain',gain,'Jitter',jit, ...
    'Artifacts',art,'Flagged',flag);
end

function R = renderTestMode(T,q)
% What a Test Mode run records: the stimulus itself -- here a 5 ms Hann-gated
% 1 kHz pip at every onset, with the onset's polarity -- and nothing else.
fs = q.Fs;  isi = q.ISI;  lead = q.Lead;  n = T.nSweeps;
onsets = lead + (0:n-1)'*isi + 1;
pol = polaritySeries(T,n);
m   = round(0.005*fs);
k   = (0:m-1)';
pip = 1e-4*sin(2*pi*1000*k/fs).*(0.5 - 0.5*cos(2*pi*k/(m-1)));
x   = zeros(lead + n*isi + q.Tail,1);
for s = 1:n
    x(onsets(s)+k) = pol(s)*pip;
end
R = struct('Data',single(x),'Onsets',onsets,'SweepLength',q.L,'Polarity',pol(:), ...
    'IsArtifact',false(n,1),'Gain',zeros(1,0),'Jitter',zeros(1,0), ...
    'Artifacts',zeros(1,0),'Flagged',zeros(1,0));
end

function parts = renderCompact(T,q,truncated)
% One intermixed run of every tone condition, cut into per-condition compact
% traces. The plan is mabr.stim.Schedule's 'shuffled' strategy: cycle k
% presents every condition once, with the polarity an alternating entry's
% k-th presentation gets, and ONE permutation is applied to both -- so each
% condition is polarity-balanced but not alternating in file order.
fs = T.Fs;  isi = q.ISI;  lead = q.Lead;  L = q.L;  n = T.nSweeps;
nF = numel(T.Freqs);  nL = numel(T.Levels);  nC = nF*nL;  nP = nC*n;
[LI,FI] = ndgrid(1:nL,1:nF);                     % condition c = (fi-1)*nL + li
LI = LI(:)';  FI = FI(:)';
lev = T.Levels(LI);
frq = T.Freqs(FI);

rs  = RandStream('threefry','Seed',T.Seed + q.Key);
seq = repmat(1:nC,1,n);
pol = repelem(polaritySeries(T,n),nC);
rs.Substream = 4;
p   = randperm(rs,nP);
seq = seq(p);
pol = pol(p);

rs.Substream = 3;
g = randn(rs,1,nP);
j = randn(rs,1,nP);
gain = zeros(1,nP);  jit = zeros(1,nP);
for c = 1:nC
    k = find(seq == c);                          % this condition, chronologically
    [gain(k),jit(k)] = sweepDraws(g(k),j(k),T);
end

nW  = numel(T.Waves.Latency80);
lat = zeros(nW,nC);  amp = zeros(nW,nC);
for c = 1:nC
    [lat(:,c),amp(:,c)] = waveParams(lev(c),frq(c),T);
end
t = (0:isi-1)'/fs*1000;
Y = abrShape(t - jit,lat(:,seq),amp(:,seq),T.Waves).*gain + cmShape(t,lev(seq),T).*pol;

x = zeros(lead + nP*isi + q.Tail,1);
x(lead+1:lead+nP*isi) = Y(:);
x = addNoise(x,rs,T,fs);
onsets = lead + (0:nP-1)'*isi + 1;
if truncated
    % Stopped 6 ms into the last presentation: the recording ends there, and
    % compact_sweeps zero-fills the rest of that window.
    x = x(1:onsets(end) + round(0.006*fs) - 1);
end
src = single(x);                                 % adcData is single on the rig

parts = cell(1,nC);
for c = 1:nC
    k = find(seq == c);
    [data,on] = compactSweeps(src,onsets(k),L);
    parts{c} = struct('Level',lev(c),'Freq',frq(c),'FI',FI(c),'LI',LI(c), ...
        'Data',data,'Onsets',on,'SweepLength',L,'Polarity',pol(k)', ...
        'IsArtifact',false(numel(k),1),'Gain',gain(k),'Jitter',jit(k), ...
        'Artifacts',zeros(1,0),'Flagged',zeros(1,0), ...
        'Truncated',truncated && k(end) == nP);
end
parts = [parts{:}];
end

function [data,newOnsets] = compactSweeps(src,onsets,sweepLen)
% mabr.compute.Pipeline.compact_sweeps, line for line. Copied rather than
% called on purpose: these are files as they ARE on disk, and a file already
% written keeps its layout whatever the writer does next.
n         = numel(onsets);
data      = zeros(n*sweepLen,1,'single');
newOnsets = zeros(n,1);
for k = 1:n
    i0 = onsets(k);
    i1 = min(i0+sweepLen-1,numel(src));
    d0 = (k-1)*sweepLen + 1;
    data(d0:d0+(i1-i0)) = src(i0:i1);
    newOnsets(k) = d0;
end
end

% =========================================================================
%  The session plan and its notebook
% =========================================================================
function j = newJob(kind,stim,level,freq,fi,li,key,group)
% One run of the plan: a file, or for "compact" the run all compact files come
% from. Key seeds its RandStream; schedule() fills in the rest.
j = struct('Kind',kind,'Stim',stim,'Level',level,'Freq',freq,'FI',fi,'LI',li, ...
    'Key',key,'Group',group,'Start',NaT,'Duration',NaN,'Run',NaN,'NumRuns',NaN, ...
    'RunSweeps',NaN,'Fs',NaN,'Lead',NaN,'ISI',NaN,'Tail',NaN,'L',NaN);
end

function [st,fr,fi] = extraStimulus(hasTone,T,fi)
% The condition an extra file stands for: a tone where there are tones.
if hasTone
    st = "Tone";  fr = T.Freqs(fi);
else
    st = "ClickTrain";  fr = NaN;  fi = 0;
end
end

function jobs = schedule(jobs,T,start)
% Sample geometry, run numbering and start times. Each Start on the rig
% numbers its runs from 1 (a conventional series, the intermixed run, the
% click series and each extra are separate Starts), and each run starts 15 s
% after the one before began -- or 5 s after it ended, if that is later.
groups = [jobs.Group];
for g = unique(groups,'stable')
    k = find(groups == g);
    for r = 1:numel(k)
        jobs(k(r)).Run     = r;
        jobs(k(r)).NumRuns = numel(k);
    end
end
clock = start;
for k = 1:numel(jobs)
    fs = T.Fs;
    if jobs(k).Kind == "otherrate", fs = 11025; end
    f = fs/T.Fs;
    jobs(k).Fs   = fs;
    jobs(k).Lead = round(T.LeadSamples*f);
    jobs(k).ISI  = round(T.ISISamples*f);
    jobs(k).Tail = round(T.TailSamples*f);
    jobs(k).L    = round(T.SweepLength*f);       % 110 at 11025 Hz, as the rig's
    jobs(k).RunSweeps = T.nSweeps;
    if jobs(k).Kind == "compact"
        jobs(k).RunSweeps = numel(T.Freqs)*numel(T.Levels)*T.nSweeps;
    end
    jobs(k).Duration = (jobs(k).Lead + jobs(k).RunSweeps*jobs(k).ISI + jobs(k).Tail)/fs;
    jobs(k).Start    = clock;
    clock = clock + seconds(15 + max(0,ceil(jobs(k).Duration) - 10));
end
end

function [S,times] = noteRecords(texts,jobs,bookStart)
% Note records as mabr.data.SessionNotes makes them, at known times: the first
% is taken at the bench before anything runs (a clock stamp), the rest part
% way through runs spread over the session (run and sweep in the stamp).
S = mabr.data.SessionNotes.emptyRecord();
times = NaT(1,0);
m = numel(texts);
if m == 0, return; end
blank = mabr.data.SessionNotes.blankRecord();
nJ = numel(jobs);
for k = 1:m
    r = blank;
    r.Text = char(texts{k});
    if k == 1
        t = jobs(1).Start - minutes(2);
    else
        q  = jobs(1 + floor((k-2)*nJ/(m-1)));
        sw = floor(q.RunSweeps/2);
        t  = q.Start + seconds(floor((q.Lead + sw*q.ISI)/q.Fs));
        r.Run = q.Run;  r.NumRuns = q.NumRuns;  r.Sweep = sw;
    end
    r.Time    = isoChar(t);
    r.Elapsed = seconds(t - bookStart);
    r.Stamp   = mabr.data.SessionNotes.renderStamp('auto',r);
    S(end+1)  = r; %#ok<AGROW>
    times(end+1) = t; %#ok<AGROW>
end
end

function N = notesUpTo(S,times,tEnd)
% The notebook as it stood when a file was finalized.
N = mabr.data.SessionNotes.emptyRecord();
if isempty(S), return; end
m = times <= tEnd;
if any(m), N = S(m); end
end

function ffn = writeJournal(folder,style,subject,bookStart,S,lastTime)
% The plain-text journal SessionNotes.writeJournal writes, with its clock
% reads replaced by the session's own times so the file is reproducible.
ffn = fullfile(folder,journalName(style,subject,bookStart));
fid = fopen(ffn,'w','n','UTF-8');
if fid < 0
    error('mabrtest:SyntheticABR:journal','Cannot write %s.',ffn);
end
c = onCleanup(@() fclose(fid));
dash = char(8212);
fprintf(fid,'%% MABR session notes %s %s %s session started %s\n', ...
    dash,char(subject),dash,isoChar(bookStart));
fprintf(fid,'%% Rewritten in full on every change; last written %s\n',isoChar(lastTime));
for k = 1:numel(S)
    fprintf(fid,'%s\n',mabr.data.SessionNotes.renderLine(S(k)));
end
end

% =========================================================================
%  The files
% =========================================================================
function [SIG,meta] = sigFor(stim,level,freq,fi,li,T,calTime)
% SIG as io.buildSIG flattens a stimgen entry (fromStimgen's buildEntry):
% Level and Frequency (kHz) by MABR's names, the ID in stimgen's own.
SIG = struct();
if stim == "Tone"
    id = matlab.lang.makeValidName(sprintf('Tone_Frequency%g_SoundLevel%g',freq*1000,level));
    SIG.informativeParams = {'Level','Frequency'};
    SIG.Level     = level;
    SIG.Frequency = freq;
    variant = (fi-1)*numel(T.Levels) + li;
    meta = struct('ID',id,'Level',level,'Frequency',freq);
else
    id = matlab.lang.makeValidName(sprintf('ClickTrain_SoundLevel%g',level));
    SIG.informativeParams = {'Level'};
    SIG.Level = level;
    variant = li;
    meta = struct('ID',id,'Level',level);
end
SIG.alternatePolarity = double(string(T.Polarity) == "alternate");
SIG.StimClass       = ['stimgen.' char(stim)];
SIG.VariantIndex    = variant;
SIG.Calibrated      = true;
SIG.CalibrationTime = calTime;
ip  = SIG.informativeParams;
lbl = cell(1,numel(ip));
for k = 1:numel(ip)
    lbl{k} = sprintf('%s = %g',ip{k},SIG.(ip{k}));
end
SIG.Label = [{['ID = ' id]} lbl];
end

function A = currentStruct(T,R,SIG,startTime,notes,testMode,fs,dacFs)
% ABR_Data exactly as mabr.data.io.buildStruct lays it out today.
A = struct();
A.ADC.SampleRate     = fs;
A.ADC.Data           = R.Data;
A.ADC.SweepOnsets    = R.Onsets;
A.ADC.SweepLength    = R.SweepLength;
A.ADC.SweepPolarity  = R.Polarity;
A.ADC.IsArtifact     = R.IsArtifact;
A.ADC.AmplifierGain  = T.AmplifierGain;
A.ADC.InputFullScale = T.InputFullScale;
A.StartTime          = isoChar(startTime);
A.SIG                = SIG;
A.Notes              = notes;
A.TestMode           = logical(testMode);
A.SoftwareVersion    = mabr.Config.SoftwareVersion;
A.DataVersion        = mabr.Config.DataVersion;
A.DecimationFactor   = 1;
A.DAC.SampleRate     = dacFs;
end

function A = legacyStruct(T,q,R)
% An E0-era (legacy +abr) file as it loads today, without the +abr package.
fs = q.Fs;
A = struct();
A.ADC.SampleRate  = fs;
A.ADC.Data        = single(double(R.Data)*T.AmplifierGain/T.InputFullScale);  % converter units
A.ADC.SweepOnsets = R.Onsets;
A.ADC.SweepLength = round(fs*0.010) + 1;
A.ADC.IsArtifact  = false;
A.StartTime = char(q.Start,'dd-MMM-yyyy HH:mm:ss','en_US');
A.SIG.informativeParams = {'frequency','soundLevel'};
% The parameters were abr.sigdef.sigProp objects; with the class gone, LOAD
% hands back the object reference as uint32 -- a number that is not the value.
A.SIG.frequency  = uint32([3707764736;2;1;1;1;1]);
A.SIG.soundLevel = uint32([3707764736;2;1;1;2;1]);
A.SIG.dataParams = struct('frequency',q.Freq*1000,'soundLevel',q.Level);
A.SIG.Label = {sprintf('Frequency = %g kHz',q.Freq); sprintf('Level = %g dB',q.Level)};
A.altPolarity         = string(T.Polarity) == "alternate";
A.numSweeps           = T.nSweeps;
A.sweepRate           = fs/q.ISI;
A.adcWindow           = [0 0.010];
A.adcDecimationFactor = round(T.DACSampleRate/fs);
A.sweepCount          = T.nSweeps;
A.DAC.SampleRate      = T.DACSampleRate;
end

function fn = fileName(style,subject,meta,startTime)
% The name a writer of the chosen era gives this condition's file.
stamp =char(startTime,'yyMMdd''T''HHmmss');
switch style
    case "current"
        % The live writer, so "current" stays current.
        fn = mabr.data.io.buildFilename(struct('Stim',struct('Meta',meta), ...
            'StartTime',isoChar(startTime)),char(subject));
    case "old"
        % io.buildFilename as it was before 219549d.
        subj = oldSubject(subject);
        if isfield(meta,'Frequency') && isfield(meta,'Level')
            fStr = strrep(sprintf('%g',meta.Frequency),'.','_');
            lStr = strrep(sprintf('%g',meta.Level),'.','_');
            fn = sprintf('%s_Frequency_%skHz_Level_%sdB_%s.abr',subj,fStr,lStr,stamp);
        else
            fn = [matlab.lang.makeValidName(sprintf('%s_%s_%s',subj, ...
                regexprep(meta.ID,'\s+',''),stamp)) '.abr'];
        end
    case "stimgen"
        fn = [matlab.lang.makeValidName(sprintf('%s_%s_%s',oldSubject(subject), ...
            meta.ID,stamp)) '.abr'];
end
end

function fn = legacyName(subject,label,startTime)
% The legacy +abr writer: makeValidName of subject, Label and stamp.
lbl = strjoin(regexprep(label(:)','\s+',''),'_');
fn  = [matlab.lang.makeValidName(sprintf('%s_%s_%s',char(subject),lbl, ...
    char(startTime,'yyMMdd''T''HHmmss'))) '.abr'];
end

function fn = journalName(style,subject,bookStart)
if style == "current"
    fn = mabr.data.io.buildNotesFilename(char(subject),bookStart);
else
    fn = sprintf('%s_Notes_%s.notes',oldSubject(subject),char(bookStart,'yyMMdd''T''HHmmss'));
end
end

function s = oldSubject(subject)
% io.subjectToken before 219549d: a SUBJ... subject kept as typed.
s = char(subject);
if isempty(s), s = 'SUBJ_ID_0'; return; end
if ~startsWith(s,'SUBJ')
    d = regexprep(s,'\D','');
    if isempty(d)
        s = ['SUBJ_ID_' matlab.lang.makeValidName(s)];
    else
        s = ['SUBJ_ID_' d];
    end
end
end

function name = writeFile(folder,name,ABR_Data)
% Save one ABR_Data, uncompressed like the rig's files, never over an
% existing one.
ffn = uniqueFile(fullfile(folder,name));
save(ffn,'ABR_Data','-v6');
[~,n,e] = fileparts(ffn);
name = [n e];
end

function ffn = uniqueFile(ffn)
% io's rule: never overwrite; the later file gets _2, _3, ... after the stamp.
if ~isfile(ffn), return; end
[p,n,e] = fileparts(ffn);
k = 2;
while isfile(fullfile(p,sprintf('%s_%d%s',n,k,e))), k = k + 1; end
ffn = fullfile(p,sprintf('%s_%d%s',n,k,e));
end

function s = isoChar(t)
s = char(t,'yyyy-MM-dd''T''HH:mm:ss');
end

% =========================================================================
%  info
% =========================================================================
function r = fileRow(name,stim,level,freq,layout,R,testMode,fs,legacy,truncated,startTime)
% One row of info.Files, as a struct (filesTable stacks them).
r = struct('FileName',name,'Stimulus',char(stim),'Level',level,'Frequency',freq, ...
    'Layout',char(layout),'nSweeps',numel(R.Onsets),'ArtifactSweeps',R.Artifacts, ...
    'FlaggedSweeps',R.Flagged,'TestMode',logical(testMode),'SampleRate',fs, ...
    'Legacy',legacy,'Truncated',truncated,'StartTime',startTime, ...
    'SweepGain',R.Gain,'SweepJitter',R.Jitter);
end

function F = filesTable(rows)
% Built column by column so the cell columns stay cells whatever their sizes.
r = [rows{:}];
c = @(f) reshape({r.(f)},[],1);
v = @(f) reshape([r.(f)],[],1);
F = table(string(c('FileName')),string(c('Stimulus')),v('Level'),v('Frequency'), ...
    string(c('Layout')),v('nSweeps'),c('ArtifactSweeps'),c('FlaggedSweeps'), ...
    v('TestMode'),v('SampleRate'),v('Legacy'),v('Truncated'),v('StartTime'), ...
    c('SweepGain'),c('SweepJitter'), ...
    'VariableNames',{'FileName','Stimulus','Level','Frequency','Layout','nSweeps', ...
    'ArtifactSweeps','FlaggedSweeps','TestMode','SampleRate','Legacy','Truncated', ...
    'StartTime','SweepGain','SweepJitter'});
end

function Th = thresholdTable(T,hasTone,hasClick)
% info.Thresholds: one row per tone frequency, one for the click.
Stimulus =strings(0,1);  Frequency = zeros(0,1);  Threshold = zeros(0,1);
if hasTone
    Stimulus  = [Stimulus; repmat("Tone",numel(T.Freqs),1)];
    Frequency = [Frequency; T.Freqs(:)];
    Threshold = [Threshold; T.Threshold(:)];
end
if hasClick
    Stimulus(end+1,1)  = "ClickTrain";
    Frequency(end+1,1) = NaN;
    Threshold(end+1,1) = T.ClickThreshold;
end
FirstLevel = inf(size(Threshold));
for k = 1:numel(Threshold)
    at = T.Levels(T.Levels >= Threshold(k));
    if ~isempty(at), FirstLevel(k) = min(at); end
end
Th = table(Stimulus,Frequency,Threshold,FirstLevel);
end

% =========================================================================
%  truth
% =========================================================================
function T = withShifts(truth,thresholdShift,shiftByFreq,amplitudeScale)
% The session's own truth: thresholds shifted, wave I scaled.
T  = truth;
nF = numel(truth.Freqs);
if isempty(shiftByFreq), shiftByFreq = zeros(1,nF); end
if numel(shiftByFreq) ~= nF
    error('mabrtest:SyntheticABR:shiftByFreq', ...
        'ShiftByFreq has %d values; truth.Freqs has %d.',numel(shiftByFreq),nF);
end
T.Threshold      = reshape(truth.Threshold,1,[]) + thresholdShift + reshape(shiftByFreq,1,[]);
T.ClickThreshold = truth.ClickThreshold + thresholdShift;
T.Waves.PeakAmp80(1) = truth.Waves.PeakAmp80(1)*amplitudeScale;
end

function checkTruth(T)
% Refuse a truth the builders cannot honour, before anything is written.
need ={'Fs','ISISamples','SweepLength','LeadSamples','TailSamples','Freqs','Levels', ...
    'Threshold','ClickThreshold','nSweeps','Polarity','NoiseSD','Hum','HumFrequency', ...
    'Waves','GrowthFloor','GrowthTau','OctaveLatency','RefFrequency', ...
    'ClickLatencyOffset','CMAmp80','CMSlope','CMFrequency','CMTau','AmplitudeJitter', ...
    'LatencyJitter','Drift','ArtifactSweeps','FlaggedSweeps','ArtifactAmp', ...
    'ArtifactDuration','ArtifactOnset','AmplifierGain','InputFullScale', ...
    'DACSampleRate','Seed'};
miss = setdiff(need,fieldnames(T));
if ~isempty(miss)
    error('mabrtest:SyntheticABR:truth', ...
        'truth lacks %s -- start from mabrtest.SyntheticABR.defaults().',strjoin(miss,', '));
end
wv = setdiff({'Name','Latency80','LatencySlope','PeakAmp80','Width','TroughDelay', ...
    'TroughRatio'},fieldnames(T.Waves));
if ~isempty(wv)
    error('mabrtest:SyntheticABR:truth','truth.Waves lacks %s.',strjoin(wv,', '));
end
if numel(T.Threshold) ~= numel(T.Freqs)
    error('mabrtest:SyntheticABR:truth','truth.Threshold needs one value per truth.Freqs.');
end
if ~any(string(T.Polarity) == ["alternate" "positive"])
    error('mabrtest:SyntheticABR:truth','truth.Polarity is "alternate" or "positive".');
end
n = T.nSweeps;
if ~(isscalar(n) && n >= 1 && n == round(n))
    error('mabrtest:SyntheticABR:truth','truth.nSweeps must be a positive integer.');
end
if string(T.Polarity) == "alternate" && mod(n,2) ~= 0
    error('mabrtest:SyntheticABR:truth', ...
        'An alternating condition needs an even nSweeps to be polarity-balanced.');
end
if ~isempty(T.ArtifactSweeps) && ...
        round(T.ArtifactOnset*T.Fs/1000) + round(T.ArtifactDuration*T.Fs/1000) > T.ISISamples
    error('mabrtest:SyntheticABR:truth','An artifact must end inside its own sweep''s ISI.');
end
end
