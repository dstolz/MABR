function set = fromStimgen(src,cfg,opts)
% mabr.stim.fromStimgen  Build a StimulusSet from stimgen stimuli.
%
%   set = mabr.stim.fromStimgen(src) converts stimuli authored in the stimgen
%   package (external/stimgen, a git submodule) into a mabr.stim.StimulusSet.
%   src may be:
%
%       a .spl file path      a stimulus bank saved by stimgen.StimPlayer
%       stimgen.StimPlayer    a live bank editor -- its current StimPlayObjs
%       stimgen.StimPlay      one or more play items
%       stimgen.StimType      one or more stimuli directly
%
%   Options (name-value):
%       AlternatePolarity  (1,1) logical  false. Applied to every entry.
%                          stimgen has no polarity concept; MABR owns it (see
%                          mabr.stim.Schedule).
%       Calibration        (1,:) char     ''. Path of the .esgc the bank was
%                          built against, recorded as provenance.
%
%   One variant, one entry
%   ----------------------
%   A stimgen property assigned a vector expands into variant combinations --
%   a Tone with Frequency = [8000 16000] and SoundLevel = [30 60] is four
%   variants. That is exactly MABR's unit: one StimulusSet entry is ONE
%   presentation of one condition. So the conversion is a flatten over three
%   nested levels -- StimPlayer.StimPlayObjs -> StimPlay.StimObj -> variants --
%   and nothing has to be reinterpreted on the way through.
%
%   Regenerated, not resampled
%   --------------------------
%   stimgen.StimType.Fs defaults to 97656.25 Hz (a TDT rate) and a bank carries
%   whatever rate it was authored at, while mabr.stim.StimulusSet requires
%   Config.DACSampleRate. Because stimgen synthesizes from parameters rather
%   than storing waveforms, this sets Fs and calls update_signal to regenerate
%   each variant natively at the DAC rate -- no resampling, no interpolation
%   artifacts. It is the reason this function imports PARAMETERS and not the
%   Signal a bank happens to have cached.
%
%   The stimuli are copied first (StimType is matlab.mixin.Copyable), so
%   forcing Fs never mutates the objects a live StimPlayer is showing.
%
%   What is deliberately dropped
%   ----------------------------
%   stimgen.StimPlay carries Reps, ISI and SelectionType, and StimPlayer adds
%   its own ISI and SelectionType. MABR owns presentation -- ordering, spacing
%   and repetition are mabr.stim.Schedule's, chosen in the GUI -- so only Reps
%   survives, as the per-entry starting repetition count the GUI picks up.
%   stimgen's ISI is a [min max] jitter range that Schedule's scalar ISI has no
%   equivalent for, and collapsing it to a number would quietly misreport the
%   bank; SelectionType duplicates Schedule.Strategy. Both are logged and
%   ignored rather than half-honoured.
%
%   See also mabr.stim.StimulusSet, mabr.stim.Schedule, mabr.stim.stimgenAvailable.
%
% Daniel Stolzberg (c) 2026

arguments
    src
    cfg = mabr.Config
    opts.AlternatePolarity (1,1) logical = false
    opts.Calibration       (1,:) char    = ''
end

[ok,why] = mabr.stim.stimgenAvailable();
assert(ok,'mabr:stim:fromStimgen:unavailable','%s',why);

source = struct('Kind','stimgen','File','','Calibration',opts.Calibration, ...
                'Generated',datetime('now'));

% --- Resolve whatever we were handed into [StimType, Reps] pairs -----------
if (ischar(src) || isstring(src)) && isscalar(string(src))
    ffn = char(src);
    assert(isfile(ffn),'mabr:stim:fromStimgen:noFile','No such file: "%s".',ffn);
    [items,bankISI] = readBank(ffn);
    source.File = ffn;
    mabr.log.vprintf(2,'fromStimgen: bank "%s" ISI %s ignored (MABR owns presentation).', ...
        ffn,mat2str(bankISI));
elseif isa(src,'stimgen.StimPlayer')
    items = playItems(src.StimPlayObjs);
    mabr.log.vprintf(2,'fromStimgen: designer ISI %s / %s order ignored (MABR owns presentation).', ...
        mat2str(src.ISI),src.SelectionType);
elseif isa(src,'stimgen.StimPlay')
    items = playItems(src);
elseif isa(src,'stimgen.StimType')
    items = emptyItems();
    for k = 1:numel(src)
        items(end+1).Stim = src(k); %#ok<AGROW>
        items(end).Reps   = 0;      % no opinion; the GUI supplies a default
    end
else
    error('mabr:stim:fromStimgen:badSource', ...
        ['Expected a .spl path, a stimgen.StimPlayer, a stimgen.StimPlay, or a ' ...
         'stimgen.StimType -- got %s.'],class(src));
end

assert(~isempty(items),'mabr:stim:fromStimgen:emptyBank', ...
    'That stimgen bank holds no stimuli.');

% --- Flatten every variant of every stimulus into one entry ----------------
entries = {};
for i = 1:numel(items)
    stimObj = items(i).Stim;

    assert(~stimObj.IsMultiObj,'mabr:stim:fromStimgen:multiObj', ...
        ['Stimulus %d (%s) is a multi-object stimulus, which MABR does not yet ' ...
         'know how to split into presentations.'],i,class(stimObj));

    s = copy(stimObj);          % never mutate the caller's object
    s.Fs = cfg.DACSampleRate;   % regenerate natively at the DAC rate

    % Pin the variant so reading a parameter cannot move it. With
    % VariantReselectOnUpdate left at its default (true), every
    % selected_value() call OUTSIDE an update cycle re-runs the selector and
    % advances the active index -- so the metadata read back after
    % set_variant_index would describe a different variant than the Signal
    % just generated under it, and an 8 kHz waveform would be saved labelled
    % 16 kHz. The signal is always right; it is the description that drifts.
    s.VariantReselectOnUpdate = false;

    info = s.get_variant_info();
    for v = 1:info.NumCombinations
        % set_variant_index locks the index, calls update_signal, and releases
        % -- so VariantSelectionMode/VariantReselectOnUpdate cannot reselect
        % underneath us, and selected_value then reads this variant.
        s.set_variant_index(v);
        entries{end+1} = buildEntry(s,info,v,items(i).Reps,opts); %#ok<AGROW>
    end
end

entries = uniqueIDs([entries{:}]);
set = mabr.stim.StimulusSet(entries,cfg,source);

mabr.log.vprintf(1,'fromStimgen: %d stimuli -> %d presentations at %g Hz.', ...
    numel(items),set.numStimuli,set.SampleRate);
end

% =========================================================================
function e = buildEntry(s,info,v,reps,opts)
% One variant -> one StimulusSet entry.

sig = s.Signal(:);
assert(~isempty(sig),'mabr:stim:fromStimgen:emptySignal', ...
    'Variant %d of %s generated an empty signal.',v,class(s));

e = struct();
e.signal      = single(sig);
e.SampleRate  = s.Fs;
e.Repetitions = reps;
e.alternatePolarity = opts.AlternatePolarity;

% --- Parameters -------------------------------------------------------
% Level and Frequency are renamed and rescaled because the offline pipeline
% reads them by name and unit: mabr.data.io.buildFilename formats Frequency as
% kHz and Level as dB to match its default regex. stimgen names them SoundLevel
% and Frequency-in-Hz, so this is the one place the two vocabularies are
% reconciled -- everything else passes through under stimgen's own name.
e.Level = double(s.selected_value("SoundLevel"));
ip      = {'Level'};

if isprop(s,'Frequency')
    e.Frequency = double(s.selected_value("Frequency"))/1000;   % Hz -> kHz
    ip{end+1}   = 'Frequency';
end

% Every property that actually varies across the bank, under its own name.
% These -- not every numeric field on the entry -- are what identify a
% condition, which is why the list is declared rather than left to
% StimulusSet.meta to infer from types.
varying = string(info.PropertyNames);
for k = 1:numel(varying)
    p = char(varying(k));
    if strcmp(p,'SoundLevel'), continue; end        % already mapped to Level
    if strcmp(p,'Frequency'),  continue; end        % already mapped to kHz
    val = s.selected_value(varying(k));
    if isnumeric(val) && isscalar(val)
        e.(p)     = double(val);
        ip{end+1} = p; %#ok<AGROW>
    end
end
e.informativeParams = ip;

% --- Identity and provenance -----------------------------------------
e.ID           = variantID(s,info,v);
e.StimClass    = class(s);
e.VariantIndex = v;

% Whether these volts were actually derived from a measurement, and when it was
% taken. stimgen keeps no record of which .esgc a StimCalibration was loaded
% from -- CalibrationData and CalibrationTimestamp are all it exposes -- so the
% file path, when one is known at all, is the caller's (opts.Calibration) and
% lives on the set's Source rather than on every entry.
e.Calibrated      = false;
e.CalibrationTime = '';
try
    if s.ApplyCalibration && ~isempty(s.Calibration.CalibrationData)
        e.Calibrated = true;
        ts = s.Calibration.CalibrationTimestamp;
        if ~isnat(ts), e.CalibrationTime = char(ts,'yyyy-MM-dd HH:mm:ss'); end
    end
catch me
    % Calibration is optional and its state is stimgen's business; an
    % uncalibrated or half-configured bank must still import.
    mabr.log.vprintf(2,'fromStimgen: calibration state unreadable (%s).',me.message);
end
end

% =========================================================================
function id = variantID(s,info,v)
% A readable, condition-describing name: the stimulus's DisplayName followed by
% the parameters that vary. Uniqueness is enforced afterwards by uniqueIDs.
name = char(s.DisplayName);
if isempty(name) || strcmp(name,'undefined'), name = class(s); end
name = regexprep(name,'^stimgen\.','');

parts = {};
varying = string(info.PropertyNames);
for k = 1:numel(varying)
    val = s.selected_value(varying(k));
    if isnumeric(val) && isscalar(val)
        parts{end+1} = sprintf('%s%g',char(varying(k)),val); %#ok<AGROW>
    end
end
if isempty(parts), parts = {sprintf('v%d',v)}; end

id = matlab.lang.makeValidName([name '_' strjoin(parts,'_')]);
end

% =========================================================================
function entries = uniqueIDs(entries)
% IDs name the .abr files one per condition, so two entries sharing one would
% overwrite each other's results. Two variants can collide legitimately -- a
% bank holding the same stimulus twice, or a varying property that is not a
% numeric scalar and so never reached the name -- so disambiguate rather than
% refuse the bank.
ids = {entries.ID};
[~,firstAt] = unique(ids,'stable');
dupe = setdiff(1:numel(ids),firstAt);
for i = dupe
    entries(i).ID = sprintf('%s_%d',entries(i).ID,i);
end
if ~isempty(dupe)
    mabr.log.vprintf(1,'fromStimgen: %d duplicate stimulus ID(s) disambiguated.',numel(dupe));
end
end

% =========================================================================
function items = emptyItems()
% The [stimulus, repetitions] work list every source resolves down to. Stim
% holds the handle directly -- StimType is a handle class, so this shares
% rather than copies, and the copy that matters is taken once in the main loop.
items = struct('Stim',{},'Reps',{});
end

% =========================================================================
function items = playItems(sp)
% StimPlay.StimObj is declared (1,:), so one play item may hold several
% stimuli; each becomes its own entry, inheriting the item's Reps.
items = emptyItems();
for i = 1:numel(sp)
    for k = 1:numel(sp(i).StimObj)
        items(end+1).Stim = sp(i).StimObj(k); %#ok<AGROW>
        items(end).Reps   = sp(i).Reps;
    end
end
end

% =========================================================================
function [items,bankISI] = readBank(ffn)
% Read a .spl bank without going through stimgen.StimPlayer.load_bank, which is
% a GUI method: it refreshes listboxes and reports failures into a modal dialog
% instead of throwing. The file itself is a plain -mat struct.
bank = load(ffn,'-mat');
assert(isfield(bank,'Items') && isfield(bank,'NItems'), ...
    'mabr:stim:fromStimgen:badBank', ...
    '"%s" is not a stimgen bank (no Items/NItems).',ffn);

bankISI = [NaN NaN];
if isfield(bank,'ISI'), bankISI = bank.ISI; end

items = emptyItems();
for k = 1:bank.NItems
    S = bank.Items{k};

    assert(isscalar(S.StimObj),'mabr:stim:fromStimgen:multiObj', ...
        ['Bank item %d holds a multi-object stimulus, which MABR does not yet ' ...
         'know how to split into presentations.'],k);

    % Restore the stimulus WITHOUT its calibration, then put the calibration
    % back separately. stimgen.StimCalibration.loadobj currently throws on a
    % serialized calibration (it assigns Engine.MicSensitivity, which is
    % read-only), and fromStruct calls it unconditionally -- so restoring in
    % one step means one stimgen bug makes every saved bank unloadable. Split
    % apart, a bank whose calibration cannot be revived still imports, and
    % reports itself uncalibrated, which is both true and visible.
    stimStruct = S.StimObj;
    calData    = [];
    if isfield(stimStruct,'Calibration')
        calData    = stimStruct.Calibration;
        stimStruct = rmfield(stimStruct,'Calibration');
    end

    s = stimgen.StimType.fromStruct(stimStruct);

    % fromStruct restores the variant settings but not the four
    % level/duration/window properties (stimgen.StimPlayer.load_bank assigns
    % those itself), so a bank imported through fromStruct alone would silently
    % come back at the class defaults -- 60 dB, 100 ms.
    for p = ["SoundLevel","Duration","WindowDuration","WindowFcn"]
        if isfield(S.StimObj,p), s.(char(p)) = S.StimObj.(char(p)); end
    end

    if ~isempty(calData)
        try
            if isa(calData,'stimgen.StimCalibration')
                s.Calibration = calData;
            elseif isstruct(calData)
                s.Calibration = stimgen.StimCalibration.loadobj(calData);
            end
        catch me
            mabr.log.vprintf(0,1,['fromStimgen: bank item %d had a calibration that ' ...
                'could not be restored (%s) -- importing it UNCALIBRATED. Its levels ' ...
                'will not be acoustically correct.'],k,me.message);
        end
    end

    items(end+1).Stim = s; %#ok<AGROW>
    items(end).Reps   = 0;
    if isfield(S,'Reps'), items(end).Reps = double(S.Reps); end
end
end
