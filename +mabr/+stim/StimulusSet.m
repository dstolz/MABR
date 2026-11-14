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
%   AN ONGOING BACKGROUND. A stimulus may be EMBEDDED in a sound that plays
%   continuously through the run -- a tone in noise, a gap in noise, FM of a
%   steady tone (docs/Background.md). The run's signal is then
%
%       y(i) = env(i) * G(i) * B(i, theta(i))  +  sum of the signals
%
%   and three more names are given meaning on an entry:
%
%       Background      char      key of the background this entry is embedded
%                                 in ('' = none), naming an element of the
%                                 set's Backgrounds
%       BackgroundGain  [N x 1]   gain G applied to the background over this
%                                 presentation ([] = 1): AM, a silent gap
%       BackgroundPhase [N x 1]   phase deviation theta of a TONE background,
%                                 radians, starting at 0 ([] = none): FM. Its
%                                 last value is where the tone carries on from
%
%   An entry that only modulates the background still carries a `signal`:
%   zeros of the event's length. The timing pulse, duration and overlap
%   arithmetic therefore see an ordinary entry.
%
%   The backgrounds themselves are the set's fourth constructor argument, a
%   struct array (see validateBackground):
%
%       Key        char     what entries name
%       Kind       'loop' | 'tone'
%       signal     [n x 1]  one seamless lap of the background ('loop')
%       Frequency, Amplitude   Hz and peak, of a 'tone'
%       Type, Level, HighPass, LowPass, LoopDuration, Seed, Calibrated,
%       LevelScale          description only, carried into the records
%
%   A run has ONE background: mabr.stim.Schedule refuses a run whose stimuli
%   do not all name the same one.
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
                          'alternatePolarity','informativeParams', ...
                          'Background','BackgroundGain','BackgroundPhase'};
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

        % The ongoing backgrounds the entries are embedded in, one element
        % per distinct background (see the class help). Empty for a bank
        % presented in quiet.
        Backgrounds (1,:) struct = struct([])
    end

    methods
        function obj = StimulusSet(stim,cfg,source,backgrounds)
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end
            if nargin >= 3 && ~isempty(source)
                obj.Source = mabr.stim.StimulusSet.normalizeSource(source);
            end
            if nargin >= 4 && ~isempty(backgrounds)
                assert(isstruct(backgrounds),'mabr:stim:StimulusSet:badBackground', ...
                    'Backgrounds must be a struct array.');
                b = cell(1,numel(backgrounds));
                for i = 1:numel(backgrounds)
                    b{i} = mabr.stim.StimulusSet.validateBackground(backgrounds(i),i);
                end
                obj.Backgrounds = [b{:}];
                keys = {obj.Backgrounds.Key};
                assert(numel(unique(keys)) == numel(keys), ...
                    'mabr:stim:StimulusSet:badBackground', ...
                    'Two backgrounds share one Key.');
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

            obj.checkEmbedding();
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

        % --- Ongoing background --------------------------------------------
        function key = backgroundKey(obj,i)
            % Key of the background entry i is embedded in; '' for none.
            obj.checkRange(i);
            key = '';
            if isfield(obj.Stimuli,'Background') && ~isempty(obj.Stimuli(i).Background)
                key = char(string(obj.Stimuli(i).Background));
            end
        end

        function tf = hasBackground(obj,i)
            % True where an entry is embedded in a background. With no
            % argument, for the whole bank.
            if nargin < 2 || isempty(i), i = 1:obj.numStimuli; end
            tf = false(size(i));
            for k = 1:numel(i)
                tf(k) = ~isempty(obj.backgroundKey(i(k)));
            end
        end

        function B = background(obj,key)
            % The background with this Key, or [] for '' (none).
            B = [];
            key = char(string(key));
            if isempty(key), return; end
            k = [];
            if ~isempty(obj.Backgrounds)
                k = find(strcmp({obj.Backgrounds.Key},key),1);
            end
            assert(~isempty(k),'mabr:stim:StimulusSet:unknownBackground', ...
                'This bank holds no background with the key "%s".',key);
            B = obj.Backgrounds(k);
        end

        function B = backgroundOf(obj,i)
            % The background entry i is embedded in, or [].
            B = obj.background(obj.backgroundKey(i));
        end

        function g = gain(obj,i)
            % Gain envelope entry i applies to its background, or [] for none.
            obj.checkRange(i);
            g = [];
            if isfield(obj.Stimuli,'BackgroundGain'), g = obj.Stimuli(i).BackgroundGain; end
        end

        function p = phase(obj,i)
            % Phase deviation (rad) entry i applies to a tone background, or [].
            obj.checkRange(i);
            p = [];
            if isfield(obj.Stimuli,'BackgroundPhase'), p = obj.Stimuli(i).BackgroundPhase; end
        end

        function mode = embeddingMode(obj,i)
            % How entry i meets its background:
            %   'none'      it has none
            %   'add'       its signal is summed onto the background
            %   'modulate'  it changes the background (gain and/or phase) and
            %               adds nothing
            %   'both'      it does both
            mode = 'none';
            if ~obj.hasBackground(i), return; end
            mods = ~isempty(obj.gain(i)) || ~isempty(obj.phase(i));
            adds = any(obj.Stimuli(i).signal ~= 0);
            if mods && adds,  mode = 'both';
            elseif mods,      mode = 'modulate';
            else,             mode = 'add';
            end
        end

        function w = displayWave(obj,i)
            % A waveform that SHOWS entry i, for a view that draws the
            % stimulus normalized: its signal -- or, for an entry that only
            % modulates its background and so has a signal of zeros, the
            % modulation itself: the gain's departure from 1, else the
            % frequency deviation its phase describes (Hz).
            w = obj.signal(i);
            if any(w ~= 0), return; end
            g = obj.gain(i);
            if ~isempty(g)
                w = single(double(g(:)) - 1);
                return
            end
            p = obj.phase(i);
            if numel(p) > 1
                d = diff(double(p(:))).*obj.SampleRate./(2*pi);
                w = single([d; d(end)]);
            end
        end

        function [y,t] = embedded(obj,i,pre,post)
            % One presentation of entry i rendered in its background, with
            % `pre` and `post` seconds of background around it (default 0),
            % as [N x 1] single; t is seconds, 0 at the onset. Without a
            % background, the signal between silences.
            %
            % Rendered by a one-presentation mabr.stim.PlayPlan with no
            % run-edge ramp and no loop offset, so this is the arithmetic an
            % acquisition performs and not a second copy of it -- and, for a
            % stimgen bank, the same samples as that stimulus's
            % embedded_signal(pre,post).
            if nargin < 3 || isempty(pre),  pre  = 0; end
            if nargin < 4 || isempty(post), post = 0; end
            obj.checkRange(i);
            Fs   = obj.SampleRate;
            w    = obj.signal(i);
            nPre = round(pre*Fs);
            N    = nPre + numel(w) + round(post*Fs);
            bg   = mabr.stim.PlayPlan.backgroundSpec(obj.backgroundOf(i),Fs, ...
                       {obj.gain(i)},{obj.phase(i)},0,0);
            plan = mabr.stim.PlayPlan({w},{obj.timing(i)},nPre+1,1,1,N,bg);
            y    = plan.range(1,N);
            y    = y(:,1);
            t    = ((0:N-1)' - nPre)./Fs;
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

            % An EMPTY extra is a field this entry does not have: a bank
            % mixing stimulus kinds carries one field set (struct-array
            % concatenation requires it), and the fields one kind lacks are
            % filled with []. Copying those through would hand every reader
            % of the metadata -- the file name, the .abr's SIG -- a parameter
            % with no value.
            [ip,extra] = mabr.stim.StimulusSet.informativeNames(s);
            for k = 1:numel(extra)
                if ~isempty(s.(extra{k}))
                    m.(extra{k}) = s.(extra{k});
                end
            end
            ip = ip(isfield(m,ip));

            % How this entry is embedded in its background, where it has one.
            % A word, not the background itself: that is recorded once per
            % block (mabr.stim.backgroundRecord).
            mode = obj.embeddingMode(i);
            if ~strcmp(mode,'none'), m.Embedding = mode; end

            m.informativeParams = ip(:)';

            lbl = cell(1,numel(ip));
            for k = 1:numel(ip)
                lbl{k} = sprintf('%s = %g',ip{k},double(m.(ip{k})));
            end
            m.Label = [{sprintf('ID = %s',m.ID)} lbl];
        end

        function P = paramTable(obj,idx)
            % The informative parameters of a set of entries, as a table --
            % which parameters they share, what each entry's value is, and
            % which of those actually vary across the set.
            %
            %   P.Names   {1 x nP}       parameter names, in the order the
            %                            first entry declares them
            %   P.Values  [nStim x nP]   the value of each, row-aligned with
            %                            `idx` (NaN where an entry lacks one)
            %   P.Varying (1 x nP) logical   parameters that differ across idx
            %   P.Units   {1 x nP}       'kHz' / 'dB' / '' -- see paramUnit
            %   P.IDs     {1 x nStim}    each entry's ID
            %
            % `idx` defaults to the whole bank, and `Varying` is answered for
            % exactly the entries asked for. Which SCOPE to ask about is the
            % caller's decision and it matters: mabr.ui.AcqController asks for
            % the whole bank and slices out the rows of the run it is about to
            % play, because which parameters are informative is a property of
            % the experiment rather than of one run -- a blocked run holds a
            % single condition and therefore varies nothing at all.
            %
            % Only NUMERIC SCALAR parameters are tabulated. This is a table of
            % dimensions to sort, group, and shade by, and a name with no
            % order over its values cannot do any of those; the full metadata
            % of an entry, categorical fields included, is meta().
            %
            % See also meta, mabr.ui.LivePlot.
            if nargin < 2 || isempty(idx), idx = 1:obj.numStimuli; end
            idx = double(idx(:)');
            n   = numel(idx);

            P = struct('Names',{{}},'Values',zeros(n,0), ...
                       'Varying',false(1,0),'Units',{{}},'IDs',{cell(1,n)});
            if n == 0 || obj.numStimuli == 0, return; end

            % Names shared by EVERY requested entry: a parameter only some of
            % them carry cannot describe the set, and a half-filled column
            % would sort and group on values that mean nothing.
            names = {};
            for k = 1:n
                obj.checkRange(idx(k));
                s = obj.Stimuli(idx(k));
                nk = mabr.stim.StimulusSet.informativeNames(s);
                nk = nk(cellfun(@(f) isnumeric(s.(f)) && isscalar(s.(f)),nk));
                if k == 1, names = nk;
                else,      names = names(ismember(names,nk));
                end
            end

            nP  = numel(names);
            V   = nan(n,nP);
            ids = cell(1,n);
            for k = 1:n
                s      = obj.Stimuli(idx(k));
                ids{k} = char(string(s.ID));
                for j = 1:nP
                    V(k,j) = double(s.(names{j}));
                end
            end

            varying = false(1,nP);
            units   = cell(1,nP);
            for j = 1:nP
                v = V(:,j);
                varying(j) = numel(unique(v(~isnan(v)))) > 1;
                units{j}   = mabr.stim.StimulusSet.paramUnit(names{j});
            end

            P.Names   = names(:)';
            P.Values  = V;
            P.Varying = varying;
            P.Units   = units;
            P.IDs     = ids;
        end
    end

    methods (Static, Access = private)
        function [names,extra] = informativeNames(s)
            % The parameters that identify one entry, and the passthrough
            % fields they were chosen from. Inferred -- every numeric scalar
            % extra -- unless the entry declares informativeParams, in which
            % case the declared list wins. Either way only names that actually
            % arrived as fields survive: a generator naming a parameter it then
            % failed to pass through would otherwise put a phantom grouping
            % dimension into every .abr it wrote.
            extra = setdiff(fieldnames(s),mabr.stim.StimulusSet.ReservedFields,'stable');
            names = {};
            for k = 1:numel(extra)
                v = s.(extra{k});
                if isnumeric(v) && isscalar(v), names{end+1} = extra{k}; end %#ok<AGROW>
            end
            if isfield(s,'informativeParams') && ~isempty(s.informativeParams)
                declared = cellstr(s.informativeParams);
                names    = declared(ismember(declared,extra));
            end
            names = names(:)';
            extra = extra(:)';
        end
    end

    methods (Access = private)
        function checkEmbedding(obj)
            % Every background an entry names must exist, and a phase
            % deviation needs a tone to act on: noise has no phase to shift.
            for i = 1:obj.numStimuli
                key = obj.backgroundKey(i);
                if isempty(key)
                    assert(isempty(obj.gain(i)) && isempty(obj.phase(i)), ...
                        'mabr:stim:StimulusSet:modulationNeedsBackground', ...
                        ['Stimulus entry %d (%s) carries a BackgroundGain or ' ...
                         'BackgroundPhase but names no Background to apply it to.'], ...
                        i,obj.Stimuli(i).ID);
                    continue
                end
                B = obj.background(key);
                assert(isempty(obj.phase(i)) || strcmp(B.Kind,'tone'), ...
                    'mabr:stim:StimulusSet:phaseNeedsTone', ...
                    ['Stimulus entry %d (%s) modulates the PHASE of its background ' ...
                     '(frequency modulation), which needs a tone; its background is ' ...
                     'a %s.'],i,obj.Stimuli(i).ID,B.Kind);
                assert(B.SampleRate == obj.SampleRate, ...
                    'mabr:stim:StimulusSet:backgroundRate', ...
                    ['The background of stimulus entry %d (%s) is at %g Hz, but the ' ...
                     'bank is at %g Hz.'],i,obj.Stimuli(i).ID,B.SampleRate,obj.SampleRate);
            end
        end

        function checkRange(obj,i)
            assert(isscalar(i) && i >= 1 && i <= obj.numStimuli, ...
                'mabr:stim:StimulusSet:range', ...
                'Stimulus index %s out of range (1..%d).',mat2str(i),obj.numStimuli);
        end
    end

    methods (Static)
        function u = paramUnit(name)
            % The unit a parameter is carried in. Only the two the toolbox
            % fixes by name and unit end-to-end are claimed: Frequency in kHz
            % and Level in dB, which mabr.stim.fromStimgen converts into and
            % mabr.data.io.buildFilename writes back out. Everything else is
            % left unitless rather than guessed at -- a label reading '5 ms'
            % over a parameter that was actually seconds is worse than one
            % reading 'Duration 0.005'. Public so that a view naming a
            % parameter (mabr.ui.TraceOrganizer) states it in the units this
            % table does.
            switch lower(char(name))
                case 'frequency', u = 'kHz';
                case 'level',     u = 'dB';
                otherwise,        u = '';
            end
        end

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

            % The embedding fields, normalized onto every entry for the same
            % reason alternatePolarity is: one common field set.
            if ~isfield(s,'Background') || isempty(s.Background)
                s.Background = '';
            end
            assert(ischar(s.Background) || (isstring(s.Background) && isscalar(s.Background)), ...
                'mabr:stim:StimulusSet:badBackground', ...
                'Stimulus entry %d: Background must be the key of a background (text).',idx);
            s.Background = char(string(s.Background));

            if ~isfield(s,'BackgroundGain'),  s.BackgroundGain  = []; end
            if ~isfield(s,'BackgroundPhase'), s.BackgroundPhase = []; end
            if ~isempty(s.BackgroundGain)
                g = double(s.BackgroundGain(:));
                assert(numel(g) == numel(s.signal) && all(isfinite(g)) && all(g >= 0), ...
                    'mabr:stim:StimulusSet:badGain', ...
                    ['Stimulus entry %d: BackgroundGain must be finite, non-negative ' ...
                     'and the length of signal (%d).'],idx,numel(s.signal));
                s.BackgroundGain = g;
            else
                s.BackgroundGain = [];
            end
            if ~isempty(s.BackgroundPhase)
                ph = double(s.BackgroundPhase(:));
                assert(numel(ph) == numel(s.signal) && all(isfinite(ph)), ...
                    'mabr:stim:StimulusSet:badPhase', ...
                    ['Stimulus entry %d: BackgroundPhase must be finite and the ' ...
                     'length of signal (%d).'],idx,numel(s.signal));
                assert(abs(ph(1)) < 1e-9,'mabr:stim:StimulusSet:badPhase', ...
                    ['Stimulus entry %d: BackgroundPhase must start at 0 (it starts ' ...
                     'at %g rad), or the background would jump at the onset.'],idx,ph(1));
                s.BackgroundPhase = ph;
            else
                s.BackgroundPhase = [];
            end
        end

        function b = validateBackground(b,idx)
            % Validate and normalize one background against the contract in
            % the class help. Description fields are filled with NaN / ''
            % where the source said nothing.
            if nargin < 2 || isempty(idx), idx = 1; end
            assert(isstruct(b) && isscalar(b),'mabr:stim:StimulusSet:badBackground', ...
                'Background %d must be a scalar struct.',idx);
            assert(isfield(b,'Key') && ~isempty(b.Key),'mabr:stim:StimulusSet:badBackground', ...
                'Background %d needs a nonempty Key.',idx);
            assert(isfield(b,'Kind') && any(strcmpi(char(string(b.Kind)),{'loop','tone'})), ...
                'mabr:stim:StimulusSet:badBackground', ...
                'Background %d: Kind must be ''loop'' or ''tone''.',idx);
            assert(isfield(b,'SampleRate') && isscalar(b.SampleRate) && b.SampleRate > 0, ...
                'mabr:stim:StimulusSet:badBackground', ...
                'Background %d needs its SampleRate.',idx);

            out = struct();
            out.Key        = char(string(b.Key));
            out.Kind       = lower(char(string(b.Kind)));
            out.SampleRate = double(b.SampleRate);
            out.signal     = zeros(0,1,'single');
            out.Frequency  = NaN;
            out.Amplitude  = NaN;

            switch out.Kind
                case 'loop'
                    assert(isfield(b,'signal') && isnumeric(b.signal) && numel(b.signal) >= 2 ...
                           && all(isfinite(b.signal(:))), ...
                        'mabr:stim:StimulusSet:badBackground', ...
                        'Background %d (loop) needs a finite "signal" of at least two samples.',idx);
                    out.signal = single(b.signal(:));
                case 'tone'
                    ok = isfield(b,'Frequency') && isfield(b,'Amplitude') ...
                         && isscalar(b.Frequency) && isscalar(b.Amplitude) ...
                         && isfinite(b.Frequency) && isfinite(b.Amplitude) ...
                         && b.Frequency > 0 && b.Frequency < out.SampleRate/2 ...
                         && b.Amplitude >= 0;
                    assert(ok,'mabr:stim:StimulusSet:badBackground', ...
                        ['Background %d (tone) needs a Frequency between 0 and half ' ...
                         'the sample rate and a non-negative Amplitude.'],idx);
                    out.Frequency = double(b.Frequency);
                    out.Amplitude = double(b.Amplitude);
            end

            % Description: what the records say about it. Never read by the
            % renderer.
            out.Type         = bgText(b,'Type',out.Kind);
            out.Level        = bgNumber(b,'Level');
            out.HighPass     = bgNumber(b,'HighPass');
            out.LowPass      = bgNumber(b,'LowPass');
            out.LoopDuration = bgNumber(b,'LoopDuration');
            out.Seed         = bgNumber(b,'Seed');
            out.Calibrated   = isfield(b,'Calibrated') && ~isempty(b.Calibrated) ...
                               && logical(b.Calibrated(1));
            out.LevelScale   = bgNumber(b,'LevelScale');
            if isnan(out.LevelScale), out.LevelScale = 1; end
            if strcmp(out.Kind,'loop') && isnan(out.LoopDuration)
                out.LoopDuration = numel(out.signal)/out.SampleRate;
            end
            b = out;
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
                if isa(v,'mabr.stim.StimulusSet')
                    % A saved set is waveforms already rendered at the rate it
                    % was saved at, and it skips the constructor's rate check
                    % on the way in -- so it is checked here, or a bank on
                    % another clock loads without a word and is only refused
                    % when a Schedule is built from it.
                    assert(v.numStimuli == 0 || v.SampleRate == cfg.DACSampleRate, ...
                        'mabr:stim:StimulusSet:sampleRate', ...
                        ['"%s" holds a stimulus bank rendered at %g Hz, but the ' ...
                         'device is set to %g Hz. A saved bank is waveforms, not ' ...
                         'parameters, so it cannot be re-rendered; rebuild it at ' ...
                         '%g Hz.'],ffn,v.SampleRate,cfg.DACSampleRate,cfg.DACSampleRate);
                    set = v;
                    return
                end
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
        function [s,detail] = describeSource(obj)
            % One-line provenance for the status line / bank label, in the
            % shape of FilterPolicy.describe and AudioSettings.describe.
            %
            % detail is the same line with nothing left out -- WHICH
            % calibration, by when it was measured -- for a tooltip or a log,
            % where s has to fit a label sharing its row with two buttons.
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
            detail = s;
            if isempty(s), return; end

            if ~isempty(src.Calibration)
                [~,n,e] = fileparts(src.Calibration);
                s = sprintf('%s, cal %s',s,[n e]);
                detail = s;
            else
                [cal,known] = obj.isCalibrated();
                if known && ~cal
                    s = [s ' (uncalibrated)'];
                    detail = s;
                elseif known
                    % Said, not implied. Until this read "(calibrated)" the
                    % only evidence of a calibrated bank was the ABSENCE of
                    % "(uncalibrated)" and a green label -- and an operator
                    % holding a log line that said otherwise had nothing on
                    % screen to weigh against it.
                    when   = obj.calibrationTime();
                    detail = [s ' (calibrated)'];
                    if ~isempty(when)
                        detail = sprintf('%s (calibrated, measured %s)',s,when);
                    end
                    s = [s ' (calibrated)'];
                end
            end
        end

        function t = calibrationTime(obj)
            % When the calibration behind this bank was measured, as text, or
            % '' where the bank does not say. Entries built against different
            % measurements give the span, earliest to latest: the stamps are
            % 'yyyy-MM-dd HH:mm:ss', which sorts as text the way it sorts as
            % time.
            t = '';
            if obj.numStimuli == 0 || ~isfield(obj.Stimuli,'CalibrationTime')
                return
            end
            c = {obj.Stimuli.CalibrationTime};
            keep = cellfun(@(x) (ischar(x) || isstring(x)) && ...
                                all(strlength(string(x)) > 0) && isscalar(string(x)),c);
            if ~any(keep), return; end
            u = unique(cellstr(string(c(keep))));
            if isscalar(u)
                t = u{1};
            else
                t = sprintf('%s .. %s',u{1},u{end});
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


% =========================================================================
function v = bgNumber(b,f)
% A numeric scalar field of a background description, or NaN.
v = NaN;
if isfield(b,f) && isnumeric(b.(f)) && isscalar(b.(f))
    v = double(b.(f));
end
end

function v = bgText(b,f,default)
% A text field of a background description, or the default.
v = default;
if isfield(b,f) && ~isempty(b.(f)), v = char(string(b.(f))); end
end
