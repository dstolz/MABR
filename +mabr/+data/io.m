classdef io
% mabr.data.io  Save/load for MABR session data.
%
%   Writes .abr files whose ABR_Data struct satisfies the UNCHANGED offline
%   abr_analysis/ pipeline, and reads legacy ABR_Data structs back into the
%   new mabr.data model via an import shim.
%
%   The offline pipeline reads exactly these fields (see parseABRFiles.m and
%   extractABRResponses.m):
%       ABR_Data.ADC.SampleRate           (Hz, post-decimation)
%       ABR_Data.ADC.Data                 (single vector)
%       ABR_Data.ADC.SweepOnsets          (indices into ADC.Data)
%       ABR_Data.StartTime                (datetime-parseable)
%       ABR_Data.SIG.informativeParams    (cellstr of param names)
%       ABR_Data.SIG.(param)              (numeric, one per informativeParam)
%       ABR_Data.SIG.Label                (cellstr; also drives the filename)
%
%   Filenames are underscore-separated TOKENS, each token hyphenated inside
%   (a name-value pair is one token), and match the strict offline pattern
%       ^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr
%   e.g. SUBJ-ID-1254_Frequency-8kHz_Level-30dB_261001T143012.abr. Underscores
%   appear ONLY between tokens, so a name splits unambiguously on them; a
%   decimal point in a value is written p (11.3 kHz -> 11p3kHz) and a minus
%   sign m (-10 dB -> m10dB), since '.' and '-' are taken.
%
%   No file is ever overwritten. The stamp is to the second, so two runs of
%   one condition started within the same second -- short passes of a looped
%   run (mabr.ui.AcqController.Loop), a Repeat pressed straight after a run --
%   would be given one name, and save() would replace the first run's data
%   with the second's without a word. The later file is written as
%   <name>_2.abr (then _3, ...) instead, and the log says so. That name still
%   starts with the subject token parseABRFiles selects on and still ends in
%   .abr, but NOT the strict pattern above, which ends at the timestamp: a
%   script filtering on that pattern has to allow the suffix to see the file.
%
%   Two further fields are written for polarity-alternating conditions. The
%   pipeline above does not read them, but offline analysis needs them to tell
%   the two polarities apart, and both are always present:
%       ABR_Data.ADC.SweepPolarity        (+1/-1, one per SweepOnsets entry)
%       ABR_Data.SIG.alternatePolarity    (0/1, whether the condition alternated)
%
%   And one more the pipeline does not read either: the session's rig notebook,
%   written WHOLE into every file rather than split across them, so a .abr
%   recovered on its own still carries what the operator wrote while it was
%   being acquired (see mabr.data.SessionNotes):
%       ABR_Data.Notes                    (struct array; 1x0 when nothing noted)
%       ABR_Data.TestMode                 (logical; true = Test Mode, i.e. the
%                                          samples ARE the stimulus, not a
%                                          recording of a subject)
%       ABR_Data.ADC.AmplifierGain        (the external amplifier gain; 1 = none)
%       ABR_Data.ADC.InputFullScale       (volts at the recorder input that
%                                          read as 1.0, i.e. the input gain
%                                          knob as calibrated; 1 = uncalibrated.
%                                          ADC.Data was divided by
%                                          AmplifierGain/InputFullScale)
%
%   Save-time ADC decimation (by Recording.DecimationFactor) is preserved
%   exactly as the legacy save_abr_data did: resample(Data,1,df) and
%   round(SweepOnsets/df), with ADC.SampleRate = SampleRate/df.
%
%   writeStimLog is the other output this class produces, and the only one a
%   STIMULATION-ONLY session writes (mabr.AudioSettings.StimulationOnly): there
%   is no recording to put in a .abr, but what was played, in what order, with
%   what polarity, and at what time is still the experimental record -- and
%   without it a rig where something else did the recording has no way to line
%   its own data up with the stimuli. One MAT-file per run, named as the run's
%   .abr would be with STIM after the subject (see buildStimLogFilename):
%       SUBJ-ID-<id>_STIM_Frequency-<f>kHz_Level-<L>dB_<yyMMdd'T'HHmmss>.mat
%   holding a single MABR_StimLog struct: one entry per trial (onset, stimulus,
%   polarity, and that stimulus's parameters) plus the session's notes.
%
% Daniel Stolzberg (c) 2019-2026

    methods (Static)
        function ffn = writeABR(block,outputPath,baseName)
            % Write one mabr.data.Block to an offline-compatible .abr file.
            if nargin < 2 || isempty(outputPath), outputPath = pwd; end
            if nargin < 3, baseName = ''; end
            if ~isfolder(outputPath), mkdir(outputPath); end

            ABR_Data = mabr.data.io.buildStruct(block); %#ok<NASGU>

            fn  = mabr.data.io.buildFilename(block,baseName);
            ffn = mabr.data.io.uniqueFile(fullfile(outputPath,fn));
            [~,n,e] = fileparts(ffn);
            fn  = [n e];

            x = whos('ABR_Data');
            mabr.log.vprintf(1,'Saving %s (%.1f MB) [%s]',fn,x.bytes/1e6,ffn);
            save(ffn,'ABR_Data','-mat','-nocompression');
        end

        function ffn = writeStimLog(info,outputPath,baseName)
            % Write one run's stimulation sequence to a _STIM_ .mat file and
            % return the full path ('' when there is no output folder, the
            % same record-without-saving rule writeABR follows via its caller).
            %
            % This is what a STIMULATION-ONLY session saves in place of the
            % .abr files it cannot produce. See buildStimLog for the contents
            % and mabr.ui.AcqController.log_stim_run for who fills `info` in.
            if nargin < 3, baseName = ''; end
            ffn = '';
            if nargin < 2 || isempty(outputPath), return; end
            if ~isfolder(outputPath), mkdir(outputPath); end

            MABR_StimLog = mabr.data.io.buildStimLog(info); %#ok<NASGU>

            fn  = mabr.data.io.buildStimLogFilename(info,baseName);
            ffn = mabr.data.io.uniqueFile(fullfile(outputPath,fn));
            [~,n,e] = fileparts(ffn);
            fn  = [n e];

            mabr.log.vprintf(1,'Saving stimulation log %s [%s]',fn,ffn);
            save(ffn,'MABR_StimLog','-mat','-nocompression');
        end

        function S = buildStimLog(info)
            % Assemble the MABR_StimLog struct from one run's plan and what the
            % worker reported actually going out.
            %
            % The sequence is stored as parallel arrays, one element per
            % PRESENTATION in play order, so struct2table(S.Sequence) is a
            % readable log on the spot:
            %       Order StimulusIndex ID Polarity OnsetSample OnsetTime Presented
            % followed by one column per stimulus parameter (S.Parameters).
            %
            % OnsetSample indexes the run's play matrix (silence pad included,
            % see mabr.stim.Schedule.renderSpec) and OnsetTime is that in
            % seconds from the first sample of the run -- which is also the
            % moment the timing pulse for that presentation went out on the
            % timing output channel, so a system recording elsewhere can align
            % on the pulse and read the label here.
            %
            % Presented is the honest part: a run stopped early (Advance/Abort,
            % or a Kill) emits only part of its matrix, and the presentations
            % past that point never happened. The plan is written whole and
            % flagged, rather than truncated, so the file records both what was
            % intended and what occurred.
            g   = @(f,d) mabr.data.io.getdef(info,f,d);
            cfg = mabr.Config;

            Fs  = g('SampleRate',cfg.DACSampleRate);
            idx = double(g('StimulusIndex',[]));  idx = idx(:)';
            pol = double(g('Polarity',ones(size(idx))));  pol = pol(:)';
            ons = double(g('OnsetSample',[]));    ons = ons(:)';
            ids = g('IDs',{});
            n   = numel(idx);
            if numel(pol) ~= n, pol = ones(1,n); end
            if numel(ons) ~= n, ons = nan(1,n);  end

            % Everything up to the last sample the worker actually emitted was
            % played; nothing after it was.
            streamed = double(g('StreamedSamples',NaN));
            if isnan(streamed)
                presented = true(1,n);
            else
                presented = ons <= streamed;
            end

            S = struct();
            S.SoftwareVersion = cfg.SoftwareVersion;
            S.DataVersion     = cfg.DataVersion;
            % Named so nothing reading this file has to infer why there is no
            % recording in it.
            S.Mode      = 'stimulation-only';
            S.Recorded  = false;
            S.StartTime = mabr.data.io.startTimeChar(g('StartTime',''));
            S.Subject   = char(string(g('Subject','')));
            S.Device    = char(string(g('Device','')));

            S.Run      = g('Run',1);
            S.NumRuns  = g('NumRuns',1);
            S.Complete = strcmp(char(string(g('StopReason','completed'))),'completed');
            S.StopReason = char(string(g('StopReason','completed')));

            S.DAC = struct('SampleRate',Fs, ...
                           'PlayerChannels',g('PlayerChannels',[1 2]), ...
                           'StreamedSamples',streamed, ...
                           'StreamedSeconds',streamed/Fs);

            S.Presentation = struct( ...
                'Strategy',char(string(g('Strategy',''))), ...
                'ISIMode', char(string(g('ISIMode',''))), ...
                'ISI',     g('ISI',NaN), ...
                'ISIRange',g('ISIRange',[NaN NaN]), ...
                'SilencePad',g('SilencePad',NaN));

            seqIDs = repmat({''},1,n);
            for k = 1:n
                if idx(k) >= 1 && idx(k) <= numel(ids)
                    seqIDs{k} = char(string(ids{idx(k)}));
                end
            end
            S.Sequence = struct( ...
                'Order',         1:n, ...
                'StimulusIndex', idx, ...
                'ID',            {seqIDs}, ...
                'Polarity',      pol, ...
                'OnsetSample',   ons, ...
                'OnsetTime',     (ons-1)/Fs, ...
                'Presented',     presented);

            % The stimulus parameters of every trial, as more parallel arrays
            % beside the ones above -- so struct2table(S.Sequence) reads
            % "trial 37: 8 kHz, 30 dB, polarity -1, onset 1.234 s" without a
            % lookup into Stimuli. The names are every informativeParams of
            % the bank (the same values a .abr's SIG holds, flattened by the
            % same buildSIG), listed in S.Parameters; a trial whose stimulus
            % lacks one reads NaN. A name that would overwrite one of the
            % fixed columns above is written as Stim_<name>.
            meta = g('StimulusMeta',{});
            sig  = cell(1,numel(meta));
            pn   = cell(1,0);
            for u = 1:numel(meta)
                sig{u} = mabr.data.io.buildSIG(struct('Stim',struct('Meta',meta{u})));
                new = setdiff(sig{u}.informativeParams,pn,'stable');
                pn  = [pn reshape(new,1,[])]; %#ok<AGROW>
            end
            S.Parameters = cell(1,0);
            for i = 1:numel(pn)
                v = nan(1,n);
                for k = 1:n
                    u = idx(k);
                    if u >= 1 && u <= numel(sig) && isfield(sig{u},pn{i}) && ...
                            isscalar(sig{u}.(pn{i}))
                        v(k) = sig{u}.(pn{i});
                    end
                end
                col = pn{i};
                if isfield(S.Sequence,col), col = ['Stim_' col]; end
                S.Sequence.(col) = v;
                S.Parameters{end+1} = col;
            end
            S.NumPlanned   = n;
            S.NumPresented = nnz(presented);

            % The rig notebook, on the same terms as a .abr's Notes: whole, and
            % always present. A stimulation-only session writes no .abr at all,
            % so this is the ONLY place its notes are saved -- which makes it
            % the more important of the two, not the lesser.
            S.Notes = mabr.data.io.noteRecord(g('Notes',[]));

            % The bank as this run used it, flattened the same way a .abr's SIG
            % is -- so the parameters of a stimulus in the log read exactly as
            % they would in a recorded file, and a per-stimulus tally says how
            % many times each one went out.
            S.Stimuli = struct('Index',{},'ID',{},'SIG',{},'NumPresented',{});
            for u = unique(idx(idx >= 1))
                e = struct();
                e.Index = u;
                e.ID    = '';
                if u <= numel(ids), e.ID = char(string(ids{u})); end
                if u <= numel(sig)
                    e.SIG = sig{u};
                else
                    e.SIG = struct();
                end
                e.NumPresented = nnz(idx == u & presented);
                S.Stimuli(end+1) = e;
            end
        end

        function fn = buildStimLogFilename(info,baseName)
            % The .abr name with STIM after the subject, as a .mat file:
            %   <SUBJ-ID-n>_STIM_Frequency-8kHz_Level-30dB_<yyMMdd'T'HHmmss>.mat
            % for a run of one stimulus (the condition named exactly as its
            % .abr would be, or by its ID when it has no Frequency/Level), and
            %   <SUBJ-ID-n>_STIM_Run-<k>_<yyMMdd'T'HHmmss>.mat
            % for a run that intermixes several, which has no one condition to
            % name. STIM says what the file is at a glance, and the .mat
            % extension (rather than .abr) keeps it out of everything that
            % reads a folder of .abr files as recordings.
            subj = mabr.data.io.subjectToken(baseName);
            g    = @(f,d) mabr.data.io.getdef(info,f,d);
            t    = mabr.data.io.timestampToken(g('StartTime',''));

            idx  = double(g('StimulusIndex',[]));
            u    = unique(idx(idx >= 1));
            meta = g('StimulusMeta',{});
            cond = '';
            if isscalar(u) && u <= numel(meta)
                cond = mabr.data.io.conditionToken(meta{u});
            end
            if isempty(cond)
                cond = sprintf('Run-%d',g('Run',1));
            end
            fn = sprintf('%s_STIM_%s_%s.mat',subj,cond,t);
        end

        function fn = buildNotesFilename(subject,startTime)
            % <SUBJ-ID-n>_Notes_<yyMMdd'T'HHmmss>.notes -- the plain-text crash
            % journal mabr.data.SessionNotes rewrites on every commit. Named on
            % the same pattern as the .abr and _STIM_ .mat files beside it (one
            % subjectToken for all three) so a session's outputs sort together,
            % and stamped with when the SESSION started rather than when the
            % note was taken: there is one journal per session, rewritten, not
            % one per note.
            if nargin < 2, startTime = ''; end
            subj = mabr.data.io.subjectToken(subject);
            t    = mabr.data.io.timestampToken(startTime);
            fn   = sprintf('%s_Notes_%s.notes',subj,t);
        end

        function ABR_Data = buildStruct(block)
            % Build the offline-compatible ABR_Data struct from a Block.
            rec = block.ADC;
            df  = rec.DecimationFactor;

            if df > 1
                data   = single(resample(double(rec.Data),1,df));
                % max(1,...): onsets below df/2 round to 0, which is an invalid
                % index into ADC.Data for the offline pipeline.
                onsets = max(1,round(rec.SweepOnsets(:)./df));
                Fs     = rec.SampleRate./df;
            else
                data   = rec.Data;
                onsets = rec.SweepOnsets(:);
                Fs     = rec.SampleRate;
            end

            ABR_Data = struct();
            ABR_Data.ADC.SampleRate  = Fs;
            ABR_Data.ADC.Data        = single(data(:));
            ABR_Data.ADC.SweepOnsets = onsets;
            ABR_Data.ADC.SweepLength = max(1,round(rec.SweepLength./df));

            % Per-sweep stimulus polarity, aligned with SweepOnsets (decimation
            % moves onsets but never changes how many there are). Always written
            % -- all +1 for a fixed-polarity condition -- so offline code can
            % read the field unconditionally instead of testing for it.
            pol = block.SweepPolarity(:);
            if numel(pol) ~= numel(onsets), pol = ones(numel(onsets),1); end
            ABR_Data.ADC.SweepPolarity = pol;

            % Which sweeps acquisition judged to be artifact, aligned with
            % SweepOnsets the same way. Always written -- all false when
            % rejection was off -- so offline code can read it unconditionally.
            % Flagged sweeps are NOT removed from ADC.Data: the flag records
            % the judgement and leaves the samples intact, so a reanalysis can
            % override it or apply abr_analysis/rejectArtifacts instead.
            art = logical(rec.IsArtifact(:));
            if numel(art) ~= numel(onsets), art = false(numel(onsets),1); end
            ABR_Data.ADC.IsArtifact = art;

            % The external amplifier gain and the input's full scale: ADC.Data
            % was divided by AmplifierGain/InputFullScale, so it is volts at
            % the electrodes, and Data*AmplifierGain/InputFullScale recovers
            % the converter samples. Always written, 1 when unset.
            ABR_Data.ADC.AmplifierGain  = double(block.AmplifierGain);
            ABR_Data.ADC.InputFullScale = double(block.InputFullScale);

            ABR_Data.StartTime = mabr.data.io.startTimeChar(block.StartTime);

            ABR_Data.SIG = mabr.data.io.buildSIG(block);

            % The rig notebook, whole, as it stood when this block was
            % finalized (mabr.data.SessionNotes). Always written -- a 1x0
            % struct with the right fields when nothing was noted -- so offline
            % code can read ABR_Data.Notes unconditionally the same way it
            % reads ADC.IsArtifact. Deliberately at the top level rather than
            % under SIG: a note describes the session, not the stimulus, and
            % anything under SIG risks being read as a parameter.
            ABR_Data.Notes = mabr.data.io.noteRecord(block.Notes);

            % Whether this came out of Test Mode -- the stimulus copied into
            % the acquisition buffer rather than anything recorded from a
            % subject. Always written, false for an ordinary run, for the same
            % reason ADC.IsArtifact always is: a field that appears only
            % sometimes is one offline code has to guess about, and the guess
            % that a missing field means "real data" is exactly the wrong way
            % round. Top level, not under SIG, so it can never be read as a
            % stimulus parameter or become a grouping dimension.
            ABR_Data.TestMode = logical(block.TestMode);

            % Provenance / metadata (harmless extras; offline pipeline ignores)
            cfg = mabr.Config;
            ABR_Data.SoftwareVersion = cfg.SoftwareVersion;
            ABR_Data.DataVersion     = cfg.DataVersion;
            ABR_Data.DecimationFactor = df;
            if isfield(block.Stim,'SampleRate')
                ABR_Data.DAC.SampleRate = block.Stim.SampleRate;
            end
        end

        function SIG = buildSIG(block)
            % Flatten the external stimulus metadata into an offline-readable
            % SIG substruct (plain-numeric params, not sigProp structs).
            SIG = struct();
            if isfield(block.Stim,'Meta')
                meta = block.Stim.Meta;
            else
                meta = block.Stim;
            end

            if isfield(meta,'informativeParams')
                ip = cellstr(meta.informativeParams);
            else
                ip = {};
            end
            SIG.informativeParams = ip(:)';

            for i = 1:numel(ip)
                p = ip{i};
                if isfield(meta,p)
                    SIG.(p) = double(mabr.data.io.plainValue(meta.(p)));
                end
            end

            % Whether the condition was presented with alternating polarity, as
            % a plain 0/1 so it reads like any other SIG param. Deliberately NOT
            % added to informativeParams: those become grouping dimensions in
            % the offline pipeline, and this is a property of how a condition
            % was run, not a stimulus parameter that defines a separate one.
            % The per-sweep detail is in ADC.SweepPolarity.
            if isfield(meta,'alternatePolarity')
                SIG.alternatePolarity = double(meta.alternatePolarity);
            else
                SIG.alternatePolarity = 0;
            end

            % How this waveform was made, for the same reasons and under the
            % same rule as alternatePolarity above: recorded because offline
            % analysis and reproduction need it, and kept OUT of
            % informativeParams because a generator's class or a variant's
            % ordinal is not a condition -- promoting either would split an
            % otherwise-single group in the offline pipeline. Calibrated is the
            % one that decides whether the levels in this file mean anything
            % (see mabr.stim.fromStimgen), and LevelScale says what they mean
            % when it is false: the linear gain the uncalibrated waveform was
            % given relative to the loudest entry of its bank. Present only on
            % such a file, which is itself the tell -- Level is dB SPL where it
            % is absent and Calibrated is true, and dB relative to an arbitrary
            % reference where it is not.
            for f = {'StimClass','VariantIndex','Calibrated','CalibrationTime','LevelScale'}
                if isfield(meta,f{1}), SIG.(f{1}) = meta.(f{1}); end
            end

            if isfield(meta,'Label')
                SIG.Label = meta.Label;
            else
                SIG.Label = ip(:)';
            end
        end

        function fn = buildFilename(block,baseName)
            % <subject>_<condition>_<yyMMdd'T'HHmmss>.abr, matching the
            % strict offline pattern (see the class help) when Frequency/Level
            % are present; otherwise the condition is the stimulus ID. Every
            % token is hyphenated inside, so underscores only separate tokens.
            if isfield(block.Stim,'Meta'), meta = block.Stim.Meta; else, meta = block.Stim; end

            subj = char(baseName);
            if isempty(subj) && isfield(meta,'SubjectID'), subj = char(string(meta.SubjectID)); end
            subj = mabr.data.io.subjectToken(subj);

            t = mabr.data.io.timestampToken(block.StartTime);

            cond = mabr.data.io.conditionToken(meta);
            fn   = sprintf('%s_%s_%s.abr',subj,cond,t);
        end

        function tok = conditionToken(meta)
            % The condition part of a filename: Frequency-<f>kHz_Level-<L>dB
            % (kHz; see numberToken) where the stimulus has both, which is what
            % the strict offline pattern matches; otherwise the stimulus ID --
            % which every entry supplies and which is far more legible than a
            % joined Label -- as ONE token (wordToken). Shared by the .abr and
            % stimulation-log names so one condition is spelled the same in
            % both.
            if isfield(meta,'Frequency') && isfield(meta,'Level')
                fStr = mabr.data.io.numberToken(mabr.data.io.plainValue(meta.Frequency));
                lStr = mabr.data.io.numberToken(mabr.data.io.plainValue(meta.Level));
                tok  = sprintf('Frequency-%skHz_Level-%sdB',fStr,lStr);
            else
                if isfield(meta,'ID') && ~isempty(meta.ID)
                    tok = char(string(meta.ID));
                elseif isfield(meta,'Label') && ~isempty(meta.Label)
                    tok = char(join(string(meta.Label),'_'));
                else
                    tok = 'block';
                end
                tok = mabr.data.io.wordToken(tok);
                if isempty(tok), tok = 'block'; end
            end
        end

        % --- Loading / import ----------------------------------------------
        function c = quietDeviceWarnings()
            % Silence the "Unrecognized device" warning a legacy .abr load raises.
            %
            % Legacy files carry a serialized audioPlayerRecorder alongside
            % the data, so LOAD reconstructs it and the object warns that the
            % rig's ASIO device is not on this machine -- once per file, which
            % over a session's worth of files is pure noise (and shreds any
            % carriage-return progress bar reading them). Nothing that reads an
            % .abr uses that object. abr_analysis/parseABRFiles silenced the
            % same identifier; this is that, as a guard the caller cannot
            % forget to lift -- hold the returned onCleanup for the scope of
            % the load and the previous warning state comes back, error or not.
            ws = warning('off','audio:audioPlayerRecorder:invalidDevice');
            c  = onCleanup(@() warning(ws));
        end

        function block = importLegacy(ffn)
            % Load a legacy (or new) ABR_Data .abr file into a mabr.data.Block.
            quiet = mabr.data.io.quietDeviceWarnings(); %#ok<NASGU>
            a = load(ffn,'-mat','ABR_Data');
            assert(isfield(a,'ABR_Data'),'mabr:data:io:noABRData', ...
                'File "%s" contains no ABR_Data.',ffn);
            D = a.ABR_Data;

            if isfield(D.ADC,'SweepLength') && ~isempty(D.ADC.SweepLength)
                swLen = double(D.ADC.SweepLength);
            else
                swLen = 1;
            end

            rec = mabr.data.Recording(double(D.ADC.SampleRate), ...
                D.ADC.Data, double(D.ADC.SweepOnsets), swLen);

            % Legacy files predate artifact flagging; a missing field means no
            % sweep was rejected, not that the judgement is unknown.
            if isfield(D.ADC,'IsArtifact') && ...
                    numel(D.ADC.IsArtifact) == numel(rec.SweepOnsets)
                rec.IsArtifact = logical(D.ADC.IsArtifact(:));
            end

            % Reconstruct stimulus metadata (handles both plain-numeric SIG
            % from the new writer and sigProp-struct SIG from legacy files).
            meta = struct();
            if isfield(D,'SIG') && isstruct(D.SIG)
                if isfield(D.SIG,'informativeParams')
                    ip = cellstr(D.SIG.informativeParams);
                    meta.informativeParams = ip(:)';
                    for i = 1:numel(ip)
                        p = ip{i};
                        if isfield(D.SIG,p)
                            meta.(p) = mabr.data.io.plainValue(D.SIG.(p));
                        end
                    end
                end
                if isfield(D.SIG,'Label'), meta.Label = D.SIG.Label; end
                if isfield(D.SIG,'alternatePolarity')
                    meta.alternatePolarity = logical(D.SIG.alternatePolarity);
                end
            end

            stim = struct('Meta',meta);
            if isfield(D,'DAC') && isfield(D.DAC,'SampleRate')
                stim.SampleRate = D.DAC.SampleRate;
            end

            st = '';
            if isfield(D,'StartTime'), st = mabr.data.io.startTimeChar(D.StartTime); end

            block = mabr.data.Block(stim,rec,st);

            % Legacy files predate SweepPolarity; a missing field means the
            % condition was fixed-polarity, not that the information is lost.
            if isfield(D.ADC,'SweepPolarity') && ~isempty(D.ADC.SweepPolarity)
                block.SweepPolarity = double(D.ADC.SweepPolarity(:))';
            else
                block.SweepPolarity = ones(1,numel(rec.SweepOnsets));
            end

            % Files written before the setting existed were never scaled.
            if isfield(D.ADC,'AmplifierGain') && isscalar(D.ADC.AmplifierGain)
                block.AmplifierGain = double(D.ADC.AmplifierGain);
            end
            % Nor calibrated: 1 V per converter unit, which keeps
            % Data*AmplifierGain/InputFullScale the converter units for them.
            if isfield(D.ADC,'InputFullScale') && isscalar(D.ADC.InputFullScale)
                block.InputFullScale = double(D.ADC.InputFullScale);
            end
        end
    end

    methods (Static, Access = private)
        function ffn = uniqueFile(ffn)
            % ffn itself when nothing is there, else the first of <name>_2,
            % <name>_3, ... (same folder, same extension) that is free. The
            % suffix goes AFTER the timestamp, so the name still says when
            % the run started -- bumping the stamp instead would put a time
            % in the name that nothing happened at. See the class help.
            if ~isfile(ffn), return; end
            [p,n,e] = fileparts(ffn);
            k = 2;
            while isfile(fullfile(p,sprintf('%s_%d%s',n,k,e)))
                k = k + 1;
            end
            taken = [n e];
            ffn   = fullfile(p,sprintf('%s_%d%s',n,k,e));
            mabr.log.vprintf(1,'%s already exists and is kept; writing this one as %s_%d%s.', ...
                taken,n,k,e);
        end

        function subj = subjectToken(subj)
            % The SUBJ-ID-<n> filename stem, shared by .abr, _STIM_ .mat and
            % .notes so a session's files sort together whatever it wrote. One
            % token: hyphens inside, never an underscore (SUBJ_ID_42 as typed
            % is written SUBJ-ID-42).
            subj = strtrim(char(subj));
            if isempty(subj), subj = 'SUBJ-ID-0'; end
            if startsWith(subj,'SUBJ')
                subj = mabr.data.io.wordToken(subj);
            else
                % Prefer the numeric part, but fall back to the sanitized name:
                % stripping non-digits from a purely alphabetic ID yielded
                % 'SUBJ-ID-', collapsing every such subject onto one filename.
                digits = regexprep(subj,'\D','');
                if isempty(digits)
                    subj = ['SUBJ-ID-' mabr.data.io.wordToken(subj)];
                else
                    subj = ['SUBJ-ID-' digits];
                end
            end
        end

        function s = numberToken(v)
            % A number as part of one filename token: %g, with the decimal
            % point written p and a minus sign m (11.3 -> 11p3, -10 -> m10),
            % because '.' would read as an extension and '-' joins a token.
            s = sprintf('%g',double(v(1)));
            s = strrep(strrep(s,'.','p'),'-','m');
        end

        function s = wordToken(s)
            % Free text as ONE filename token: a decimal point between digits
            % becomes p, every other run of characters that is not a letter or
            % digit becomes a single hyphen, and none is left at either end.
            s = char(s);
            s = regexprep(s,'(?<=\d)\.(?=\d)','p');
            s = regexprep(s,'[^A-Za-z0-9]+','-');
            s = regexprep(s,'^-+|-+$','');
        end

        function v = getdef(s,f,d)
            % Field f of s, or the default -- the same forgiving contract
            % worker_loop's getdef uses on a render spec, so a caller may omit
            % anything it has no opinion about.
            if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end

        function S = noteRecord(notes)
            % Normalize a session's notebook for writing: a plain 1xN struct
            % array, or a 1x0 one carrying the same fields when there is
            % nothing to say. Accepts either a mabr.data.SessionNotes handle or
            % the struct array it produces, so a caller can pass whichever it
            % happens to be holding. Never throws -- a notebook that cannot be
            % serialized must not cost the file the data in it.
            S = mabr.data.SessionNotes.emptyRecord();
            try
                if isa(notes,'mabr.data.SessionNotes')
                    if isvalid(notes), S = notes.toStruct(); end
                elseif isstruct(notes) && ~isempty(notes)
                    S = reshape(notes,1,[]);
                end
            catch me
                mabr.log.vprintf(1,1,'Notes could not be saved with this file: %s', ...
                    me.message);
            end
        end

        function v = plainValue(x)
            % Extract a plain numeric/char value, unwrapping a legacy sigProp
            % struct (which stores the value in a .Value field).
            if isstruct(x) && isfield(x,'Value')
                v = x.Value;
            else
                v = x;
            end
        end

        function s = startTimeChar(t)
            if isempty(t)
                dt = datetime('now');
            else
                dt = datetime(t);
            end
            dt.Format = 'yyyy-MM-dd''T''HH:mm:ss';
            s = char(dt);
        end

        function t = timestampToken(startTime)
            if isempty(startTime), dt = datetime('now'); else, dt = datetime(startTime); end
            dt.Format = 'yyMMdd''T''HHmmss';
            t = char(dt);
        end
    end
end
