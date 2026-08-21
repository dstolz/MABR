classdef StimulusSet < handle
% mabr.stim.StimulusSet  A bank of single, pre-computed stimuli.
%
%   set = mabr.stim.StimulusSet(stim) wraps the struct array supplied by the
%   external stimulus package. Each element describes ONE presentation of one
%   stimulus -- not a repeated train:
%
%       stim(i).signal   [N x 1]  precomputed, calibrated waveform for a
%                                 SINGLE presentation (no repetition, no ISI
%                                 padding, no timing channel)
%       stim(i).ID       string   name identifying the stimulus condition
%
%   Any other field is carried through untouched into the block metadata that
%   reaches the saved .abr file, so the external package can add parameters
%   without MABR changing. Three names are given meaning if present:
%
%       SampleRate   (1,1) double  defaults to Config.DACSampleRate
%       Repetitions  (1,1) double  per-entry default repetition count, used
%                                  as the starting value in the GUI
%       Timing       [N x 1]       an explicit timing channel for this
%                                  stimulus (otherwise MABR synthesizes one
%                                  unit pulse at each onset)
%       alternatePolarity (1,1) logical  present this entry with alternating
%                                  polarity: successive presentations are
%                                  multiplied by +1, -1, +1, ... so half the
%                                  repetitions are inverted. It does NOT add
%                                  presentations -- the repetition count is
%                                  unchanged, it is only split between the two
%                                  polarities (see mabr.stim.Schedule).
%
%       informativeParams (1,:) cellstr  the passthrough fields that identify
%                                  this condition, declared explicitly. When
%                                  absent MABR infers the list -- every numeric
%                                  scalar extra -- which is right for a
%                                  hand-built bank whose only extras ARE its
%                                  parameters. A generator emits far more than
%                                  that (a stimgen variant carries Duration,
%                                  WindowDuration, OnsetPhase, ...), and every
%                                  name on this list becomes a grouping
%                                  dimension in the offline pipeline, so a
%                                  source that knows which of its parameters
%                                  actually vary should say so rather than let
%                                  MABR guess from types.
%
%   Numeric scalar extras are otherwise advertised as informativeParams so
%   the offline pipeline picks them up (see mabr.data.io.buildSIG).
%
%   MABR -- not the stimulus package -- owns presentation. The spacing between
%   stimuli, how entries are combined across the array (blocked, interleaved,
%   shuffled), and how many times each is repeated are all decided by
%   mabr.stim.Schedule from settings the operator chooses in the GUI. A
%   StimulusSet is therefore inert: it is a bank of waveforms and nothing more.
%
%   See also mabr.stim.Schedule, mabr.stim.demoStimuli.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant, Access = private)
        % Fields MABR interprets itself; everything else is passthrough metadata.
        ReservedFields = {'signal','ID','SampleRate','Repetitions','Timing', ...
                          'alternatePolarity','informativeParams'};
    end

    properties (SetAccess = private)
        Stimuli    (1,:) struct     % validated, normalized struct array
        SampleRate (1,1) double     % common DAC rate for every entry

        % Where this bank came from. Not part of the stimulus contract -- no
        % entry carries it and nothing in acquisition reads it -- but a
        % calibrated stimgen bank and the uncalibrated demo bank are otherwise
        % indistinguishable once they are struct arrays, which is exactly the
        % confusion worth being unable to have. mabr.ui.App shows it beside the
        % entry count and mabr.data.io writes it into the .abr as provenance.
        %   Kind         'stimgen' | 'file' | 'demo' | '' (unknown)
        %   File         source path, where there was one
        %   Calibration  .esgc file the waveforms were built against, if any
        %   Generated    datetime the bank was materialized
        Source     (1,1) struct = struct('Kind','','File','','Calibration','','Generated',NaT)
    end

    methods
        function obj = StimulusSet(stim,cfg,source)
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end
            if nargin >= 3 && ~isempty(source)
                obj.Source = mabr.stim.StimulusSet.normalizeSource(source);
            end
            if nargin < 1 || isempty(stim)
                obj.Stimuli    = struct([]);
                obj.SampleRate = cfg.DACSampleRate;
                return
            end

            assert(isstruct(stim),'mabr:stim:StimulusSet:notStruct', ...
                'A stimulus definition must be a struct array.');

            % Validate into a cell first: normalization can add fields (e.g.
            % SampleRate), and assigning a struct with a different field set
            % back into a struct-array element errors ("dissimilar structures").
            v = cell(1,numel(stim));
            for i = 1:numel(stim)
                v{i} = mabr.stim.StimulusSet.validate(stim(i),i,cfg);
            end
            obj.Stimuli = [v{:}];

            rates = [obj.Stimuli.SampleRate];
            assert(all(rates == rates(1)),'mabr:stim:StimulusSet:mixedRates', ...
                ['Every stimulus must share one SampleRate (found %s). MABR ' ...
                 'renders a single play matrix per run, so one clock is required.'], ...
                mat2str(unique(rates)));
            obj.SampleRate = rates(1);

            assert(obj.SampleRate == cfg.DACSampleRate, ...
                'mabr:stim:StimulusSet:sampleRate', ...
                ['Stimulus SampleRate (%g Hz) must equal Config.DACSampleRate ' ...
                 '(%g Hz) -- the ring buffer and sweep windowing assume it.'], ...
                obj.SampleRate,cfg.DACSampleRate);
        end

        function n = numStimuli(obj)
            n = numel(obj.Stimuli);
        end

        function s = get(obj,i)
            obj.checkRange(i);
            s = obj.Stimuli(i);
        end

        function w = signal(obj,i)
            obj.checkRange(i);
            w = obj.Stimuli(i).signal;
        end

        function t = timing(obj,i)
            % Explicit timing channel for stimulus i, or [] if MABR should
            % synthesize a pulse at the onset.
            obj.checkRange(i);
            t = [];
            if isfield(obj.Stimuli,'Timing'), t = obj.Stimuli(i).Timing; end
        end

        function tf = alternatesPolarity(obj,i)
            % True where the entry asks to be presented with alternating
            % polarity. With no argument, the flag for the whole bank.
            if nargin < 2 || isempty(i), i = 1:obj.numStimuli; end
            tf = false(size(i));
            if obj.numStimuli == 0 || ~isfield(obj.Stimuli,'alternatePolarity')
                return
            end
            for k = 1:numel(i)
                obj.checkRange(i(k));
                tf(k) = obj.Stimuli(i(k)).alternatePolarity;
            end
        end

        function s = id(obj,i)
            obj.checkRange(i);
            s = obj.Stimuli(i).ID;
        end

        function c = IDs(obj)
            if obj.numStimuli == 0, c = {}; return; end
            c = {obj.Stimuli.ID};
        end

        function d = duration(obj,i)
            % Duration (s) of one presentation of stimulus i. This is the full
            % signal length -- not a trailing-zero-trimmed estimate -- because
            % the whole waveform is written into the play matrix at each onset
            % and therefore is what can collide with the next one.
            if nargin < 2 || isempty(i), i = 1:obj.numStimuli; end
            d = zeros(size(i));
            for k = 1:numel(i)
                obj.checkRange(i(k));
                d(k) = numel(obj.Stimuli(i(k)).signal)./obj.SampleRate;
            end
        end

        function d = maxDuration(obj)
            % Longest single presentation (s) -- the worst case for ISI overlap.
            if obj.numStimuli == 0, d = 0; else, d = max(obj.duration()); end
        end

        function r = defaultRepetitions(obj)
            % Per-entry starting repetition counts for the GUI: the entry's own
            % Repetitions field where supplied, else 0 meaning "no preference".
            r = zeros(1,obj.numStimuli);
            if obj.numStimuli == 0 || ~isfield(obj.Stimuli,'Repetitions'), return; end
            for i = 1:obj.numStimuli
                v = obj.Stimuli(i).Repetitions;
                if ~isempty(v), r(i) = double(v); end
            end
        end

        function m = meta(obj,i)
            % Metadata struct for stimulus i, as handed to mabr.data.Block and
            % on to the .abr writer. Every non-reserved field passes through;
            % numeric scalars are advertised as informativeParams.
            obj.checkRange(i);
            s = obj.Stimuli(i);

            m    = struct();
            m.ID = char(string(s.ID));
            % Reserved, but carried into metadata anyway: how the condition was
            % presented is part of what it means, and offline analysis needs it.
            m.alternatePolarity = logical(s.alternatePolarity);

            extra = setdiff(fieldnames(s),mabr.stim.StimulusSet.ReservedFields,'stable');
            ip    = {};
            for k = 1:numel(extra)
                f = extra{k};
                v = s.(f);
                m.(f) = v;
                if isnumeric(v) && isscalar(v), ip{end+1} = f; end %#ok<AGROW>
            end

            % A declared list wins over the inferred one. Keep only names that
            % actually arrived as fields: a generator naming a parameter it
            % then failed to pass through would otherwise put a phantom
            % grouping dimension into every .abr it wrote.
            if isfield(s,'informativeParams') && ~isempty(s.informativeParams)
                declared = cellstr(s.informativeParams);
                ip = declared(ismember(declared,extra));
            end

            m.informativeParams = ip(:)';

            lbl = cell(1,numel(ip));
            for k = 1:numel(ip)
                lbl{k} = sprintf('%s = %g',ip{k},double(m.(ip{k})));
            end
            m.Label = [{sprintf('ID = %s',m.ID)} lbl];
        end
    end

    methods (Access = private)
        function checkRange(obj,i)
            assert(isscalar(i) && i >= 1 && i <= obj.numStimuli, ...
                'mabr:stim:StimulusSet:range', ...
                'Stimulus index %s out of range (1..%d).',mat2str(i),obj.numStimuli);
        end
    end

    methods (Static)
        function s = validate(s,idx,cfg)
            % Validate and normalize one stimulus entry against the contract.
            if nargin < 2 || isempty(idx), idx = 1; end
            if nargin < 3 || isempty(cfg), cfg = mabr.Config; end

            assert(isstruct(s) && isscalar(s),'mabr:stim:StimulusSet:badEntry', ...
                'Stimulus entry %d must be a scalar struct.',idx);
            assert(isfield(s,'signal') && ~isempty(s.signal), ...
                'mabr:stim:StimulusSet:noSignal', ...
                'Stimulus entry %d needs a nonempty "signal".',idx);
            assert(isfield(s,'ID') && ~isempty(s.ID), ...
                'mabr:stim:StimulusSet:noID', ...
                'Stimulus entry %d needs a nonempty "ID".',idx);

            s.signal = single(s.signal(:));
            s.ID     = char(string(s.ID));

            if ~isfield(s,'SampleRate') || isempty(s.SampleRate)
                s.SampleRate = cfg.DACSampleRate;
            end
            assert(isscalar(s.SampleRate),'mabr:stim:StimulusSet:badRate', ...
                'Stimulus entry %d has a non-scalar SampleRate.',idx);

            % Normalized (rather than left absent) so every entry carries the
            % field: struct-array concatenation needs one common field set.
            if ~isfield(s,'alternatePolarity') || isempty(s.alternatePolarity)
                s.alternatePolarity = false;
            end
            assert(isscalar(s.alternatePolarity) && ...
                   (islogical(s.alternatePolarity) || isnumeric(s.alternatePolarity)), ...
                'mabr:stim:StimulusSet:badAltPolarity', ...
                'Stimulus entry %d: alternatePolarity must be a logical scalar.',idx);
            s.alternatePolarity = logical(s.alternatePolarity);

            if isfield(s,'informativeParams') && ~isempty(s.informativeParams)
                assert(iscellstr(s.informativeParams) || isstring(s.informativeParams), ...
                    'mabr:stim:StimulusSet:badInformativeParams', ...
                    ['Stimulus entry %d: informativeParams must be a cellstr or ' ...
                     'string array of field names.'],idx);
                s.informativeParams = cellstr(s.informativeParams(:)');
            end

            if isfield(s,'Timing') && ~isempty(s.Timing)
                s.Timing = single(s.Timing(:));
                assert(numel(s.Timing) == numel(s.signal), ...
                    'mabr:stim:StimulusSet:timingLength', ...
                    'Stimulus entry %d: Timing (%d) must match signal (%d).', ...
                    idx,numel(s.Timing),numel(s.signal));
            end
        end

        function set = fromFile(ffn,cfg)
            % Load a stimulus definition from file. A .spl is a stimgen bank
            % (parameters, regenerated at the DAC rate -- see
            % mabr.stim.fromStimgen); anything else is read as a .mat holding
            % either a saved StimulusSet or a struct array with signal + ID.
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end

            [~,~,ext] = fileparts(ffn);
            if strcmpi(ext,'.spl')
                set = mabr.stim.fromStimgen(ffn,cfg);
                return
            end

            S  = load(ffn);
            fn = fieldnames(S);
            src = struct('Kind','file','File',char(ffn));
            for i = 1:numel(fn)
                v = S.(fn{i});
                if isa(v,'mabr.stim.StimulusSet'), set = v; return; end
                if isstruct(v) && isfield(v,'signal') && isfield(v,'ID')
                    set = mabr.stim.StimulusSet(v,cfg,src);
                    return
                end
            end
            error('mabr:stim:StimulusSet:noStimuli', ...
                ['"%s" contains no stimulus definition (needs a struct array ' ...
                 'with "signal" and "ID" fields).'],ffn);
        end

        function s = emptySource()
            s = struct('Kind','','File','','Calibration','','Generated',NaT);
        end

        function s = normalizeSource(src)
            % Fill a partial source description out to the full field set, so
            % every StimulusSet carries the same shape whatever built it.
            s = mabr.stim.StimulusSet.emptySource();
            if ~isstruct(src) || ~isscalar(src), return; end
            f = intersect(fieldnames(src),fieldnames(s),'stable');
            for i = 1:numel(f), s.(f{i}) = src.(f{i}); end
        end
    end

    methods
        function s = describeSource(obj)
            % One-line provenance for the status line / bank label, in the
            % shape of FilterPolicy.describe and AudioSettings.describe.
            src = obj.Source;
            switch lower(src.Kind)
                case 'stimgen', s = 'stimgen';
                case 'demo',    s = 'built-in demo';
                case 'file'
                    [~,n,e] = fileparts(src.File);
                    s = [n e];
                otherwise, s = '';
            end
            % Both suffixes hang off a named source. With no Kind there is
            % nothing to qualify, and a bare "(uncalibrated)" would read as a
            % claim about a bank we know nothing about -- most banks predate
            % this field entirely.
            if isempty(s), return; end

            if ~isempty(src.Calibration)
                [~,n,e] = fileparts(src.Calibration);
                s = sprintf('%s, cal %s',s,[n e]);
            else
                [cal,known] = obj.isCalibrated();
                if known && ~cal, s = [s ' (uncalibrated)']; end
            end
        end

        function [tf,known] = isCalibrated(obj)
            % tf    - every entry says it was built against a measurement
            % known - the bank said anything about calibration at all
            %
            % A bank is a unit here: half-calibrated is not a state worth
            % reporting as calibrated, since the levels across it are then not
            % comparable.
            %
            % The second output is what keeps the first honest. A bank that
            % never carried the field -- any .mat from an external package,
            % anything written before this existed -- is UNKNOWN, not
            % uncalibrated, and callers must not label it either way. Treating
            % silence as "uncalibrated" would put a warning on a properly
            % calibrated bank, which is worse than saying nothing: it teaches
            % people to ignore the warning that matters.
            tf = false;
            known = obj.numStimuli > 0 && isfield(obj.Stimuli,'Calibrated');
            if ~known, return; end
            tf = all(logical([obj.Stimuli.Calibrated]));
        end
    end
end
