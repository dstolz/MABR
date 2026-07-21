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
%   Filenames are built to match the pipeline's default regex:
%       SUBJ_ID_<id>_Frequency_<f>kHz_Level_<L>dB_<yyMMdd'T'HHmmss>.abr
%
%   Two further fields are written for polarity-alternating conditions. The
%   pipeline above does not read them, but offline analysis needs them to tell
%   the two polarities apart, and both are always present:
%       ABR_Data.ADC.SweepPolarity        (+1/-1, one per SweepOnsets entry)
%       ABR_Data.SIG.alternatePolarity    (0/1, whether the condition alternated)
%
%   Save-time ADC decimation (by Recording.DecimationFactor) is preserved
%   exactly as the legacy save_abr_data did: resample(Data,1,df) and
%   round(SweepOnsets/df), with ADC.SampleRate = SampleRate/df.
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
            ffn = fullfile(outputPath,fn);

            x = whos('ABR_Data');
            mabr.log.vprintf(1,'Saving %s (%.1f MB) [%s]',fn,x.bytes/1e6,ffn);
            save(ffn,'ABR_Data','-mat','-nocompression');
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

            ABR_Data.StartTime = mabr.data.io.startTimeChar(block.StartTime);

            ABR_Data.SIG = mabr.data.io.buildSIG(block);

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

            if isfield(meta,'Label')
                SIG.Label = meta.Label;
            else
                SIG.Label = ip(:)';
            end
        end

        function fn = buildFilename(block,baseName)
            % Build a filename that matches the offline pipeline's default
            % regex when Frequency/Level are present; otherwise a label-based
            % fallback. Frequency is formatted in kHz with '.' -> '_'.
            if isfield(block.Stim,'Meta'), meta = block.Stim.Meta; else, meta = block.Stim; end

            subj = char(baseName);
            if isempty(subj) && isfield(meta,'SubjectID'), subj = char(string(meta.SubjectID)); end
            if isempty(subj), subj = 'SUBJ_ID_0'; end
            if ~startsWith(subj,'SUBJ')
                % Prefer the numeric part, but fall back to the sanitized name:
                % stripping non-digits from a purely alphabetic ID yielded
                % 'SUBJ_ID_', collapsing every such subject onto one filename.
                digits = regexprep(subj,'\D','');
                if isempty(digits)
                    subj = ['SUBJ_ID_' matlab.lang.makeValidName(subj)];
                else
                    subj = ['SUBJ_ID_' digits];
                end
            end

            t = mabr.data.io.timestampToken(block.StartTime);

            hasFL = isfield(meta,'Frequency') && isfield(meta,'Level');
            if hasFL
                fkHz = mabr.data.io.plainValue(meta.Frequency);
                lvl  = mabr.data.io.plainValue(meta.Level);
                fStr = strrep(sprintf('%g',fkHz),'.','_');
                lStr = strrep(sprintf('%g',lvl),'.','_');
                fn = sprintf('%s_Frequency_%skHz_Level_%sdB_%s.abr',subj,fStr,lStr,t);
            else
                % No Frequency/Level to match the pipeline's default regex, so
                % fall back to the stimulus ID — which every entry supplies and
                % which is far more legible than a joined Label.
                if isfield(meta,'ID') && ~isempty(meta.ID)
                    lbl = char(string(meta.ID));
                elseif isfield(meta,'Label') && ~isempty(meta.Label)
                    lbl = char(join(string(meta.Label),'_'));
                else
                    lbl = 'block';
                end
                lbl = regexprep(lbl,'\s+','');
                fn  = matlab.lang.makeValidName(sprintf('%s_%s_%s',subj,lbl,t));
                fn  = [fn '.abr'];
            end
        end

        % --- Loading / import ----------------------------------------------
        function block = importLegacy(ffn)
            % Load a legacy (or new) ABR_Data .abr file into a mabr.data.Block.
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
        end
    end

    methods (Static, Access = private)
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
