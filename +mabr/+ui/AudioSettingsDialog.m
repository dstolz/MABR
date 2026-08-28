function settings = AudioSettingsDialog(settings0,cfg,applyFcn)
% mabr.ui.AudioSettingsDialog  Modal editor for Test Mode, the ASIO device,
% and the channel mapping.
%
%   s = mabr.ui.AudioSettingsDialog(s0,cfg) opens a small modal window over a
%   mabr.AudioSettings and returns the last COMMITTED settings, or [] if
%   nothing was committed.
%
%   s = mabr.ui.AudioSettingsDialog(s0,cfg,applyFcn) additionally calls
%   applyFcn(settings) each time Commit is pressed. The dialog stays open, so
%   the owner (mabr.ui.App.applyAudioSettings) can take the new parameters
%   straight away and re-derive the main window from them -- which matters
%   most for Stimulation only, where committing takes the entire Acquisition
%   panel out of play. Seeing that happen while the dialog is still open is
%   the point: the consequence of the checkbox is visible at the moment it is
%   committed, rather than only after the window is gone and cannot be put
%   back without reopening it.
%
%   Commit / Cancel rather than OK / Cancel because the two are no longer the
%   same act: Commit applies and leaves the dialog up, Cancel closes. Commit
%   greys out when the controls match what was last committed (nothing to
%   apply), and Cancel then reads 'Close', since there is nothing left to
%   cancel back to -- edits already committed have been applied and stand.
%
%   Test Mode lives at the top: it decides whether a device is opened at all
%   (mabr.acq.worker_loop's prepare_device creates none when it is set), so it
%   belongs beside the device it overrides, not on the main window. Checking it
%   greys out the device dropdown, channel fields, and Test Device button --
%   none of them matter when nothing is going to be opened.
%
%   What it does instead of opening one is the point, and the reason it is a
%   named mode rather than a developer switch: each frame of the stimulus is
%   written straight into the acquisition ring buffer, so the sweeps that come
%   back ARE the presentations the schedule placed, sample for sample. A run
%   in Test Mode therefore answers the question everything else rests on --
%   whether the stimulus a file is labelled with is the stimulus that produced
%   its sweeps -- and mabr.ui.AcqController.alignmentCheck reports the verdict
%   after every run. The wiki page linked under the checkbox is the long
%   version; it is linked from there because a mode whose output looks exactly
%   like data needs its explanation beside the switch.
%
%   Stimulation only (no recording / no loop-back) sits directly beneath it,
%   and is the same kind of switch one step less drastic: a real output device
%   IS opened (an audioDeviceWriter), so the device, player channels, and Test
%   Device all still matter -- but nothing is recorded, so the recorder
%   channels and the microphone input do not. The two are mutually exclusive
%   and Test Mode wins: it opens no device at all, which leaves nothing for
%   stimulation only to be a mode of.
%
%   Sample rate is the setting with the longest reach, and the one control
%   here that stays live under Test Mode: it is the rate the device is opened at
%   AND the rate every stimulus is rendered at and the ring buffer filled at,
%   so a loopback run depends on it exactly as much as a real one. Committing
%   a change to it is therefore not just a device edit -- mabr.ui.App rebuilds
%   its mabr.Config, regenerates the stimulus bank at the new rate where the
%   bank can be regenerated, and rebuilds the acquisition worker. The picker
%   is EDITABLE rather than a fixed list: the listed rates
%   (mabr.Config.SupportedSampleRates) are the ones worth offering, not the
%   only ones a device may run at.
%
%   The storage/analysis rate beside it is DERIVED and deliberately not a
%   second control: sweep extraction windows the ring buffer with a whole-
%   number stride (mabr.metrics.extract_sweeps), so the only reachable
%   analysis rates are the DAC rate over an integer. mabr.Config picks the
%   integer landing closest to 12 kHz and the readout says what that works out
%   to -- 192/96/48 kHz all give exactly 12 kHz; 44.1 kHz gives 11.025 kHz.
%
%   Asking a driver for a rate is not the same as getting it, which is what
%   "Test Device" is for: it briefly opens the real device at the rate
%   currently selected and reports what was actually granted, rather than
%   letting a silent substitution be discovered from the data. Audio Toolbox
%   offers no way to enumerate the rates a device supports -- info() reports
%   the driver, the name, and the channel counts, and nothing else -- so
%   asking one at a time is the only answer there is.
%
%   "ASIO panel..." is the other half of that. On most ASIO hardware the
%   DRIVER owns the rate: MATLAB asks and the device serves whatever its own
%   control panel is set to. asiosettings opens that panel, so the argument
%   can be settled here rather than somewhere else on the machine -- set it
%   there, press Test Device, and the readout says whether the two now agree.
%
% Daniel Stolzberg (c) 2026

if nargin < 1 || isempty(settings0), settings0 = mabr.AudioSettings; end
if nargin < 2 || isempty(cfg),       cfg = mabr.Config; end
if nargin < 3,                       applyFcn = []; end

settings  = [];                      % [] unless Commit is pressed
committed = [];                      % what the controls last agreed with
devices   = mabr.AudioSettings.availableDevices();

% ---- layout -------------------------------------------------------------
fig = uifigure('Name','Audio Device (ASIO)','Position',[100 100 460 548], ...
    'WindowStyle','modal','Resize','off', ...
    'CloseRequestFcn',@(~,~) onCancel());
mabr.ui.WindowPos.restore(fig,'AudioSettingsDialog',fig.Position);

g = uigridlayout(fig,[13 3]);
g.RowHeight   = {28,48,28,28,32,32,32,32,48,24,32,18,32};
g.ColumnWidth = {100,'1x','fit'};
g.Padding     = [12 10 12 10];
g.RowSpacing  = 8;

% Row 1: Test Mode -- decides whether anything below matters
testCheck = uicheckbox(g,'Text','Test Mode — copy the stimulus into the acquisition buffer', ...
    'Value',settings0.Testing, ...
    'Tooltip',['No audio device is opened. Each frame of the stimulus is written ' ...
        'straight into the acquisition ring buffer, so a recorded sweep IS the ' ...
        'presentation the schedule placed there — which is what makes it a check ' ...
        'on stimulus/acquisition alignment rather than only a way to run without ' ...
        'hardware. Changing this rebuilds the worker.'], ...
    'ValueChangedFcn',@(~,~) onTestingChanged());
testCheck.Layout.Row = 1; testCheck.Layout.Column = [1 3];

% Row 2: what Test Mode is for, and the page that explains it. A mode whose
% output is indistinguishable from real data needs its explanation beside the
% switch, not three menus away -- so the wiki page it links to is part of the
% control, not a footnote to it.
testRow = uigridlayout(g,[1 2]);
testRow.Layout.Row = 2; testRow.Layout.Column = [1 3];
testRow.ColumnWidth  = {'1x','fit'};
testRow.Padding      = [22 0 0 0];      % indented under the checkbox above
testRow.ColumnSpacing = 8;
testNote = uilabel(testRow,'WordWrap','on','FontColor',[0.3 0.3 0.3],'Text', ...
    ['Every sweep comes back as the exact stimulus that was scheduled at that ' ...
     'onset, so a run confirms the plan, the timing channel and the sweep ' ...
     'attribution agree. The .abr files it writes hold the stimulus, not a subject.']);
testNote.Layout.Row = 1; testNote.Layout.Column = 1;
testLink = mabr.ui.wikiLink(testRow,'Test-Mode','What Test Mode proves', ...
    'Opens the Test Mode page of the MABR wiki in your browser.');
testLink.Layout.Row = 1; testLink.Layout.Column = 2;

% Row 3: stimulation-only mode -- a real output device, but nothing recorded
stimCheckTooltip = ['Play the signal and timing pulse through an output-only device. ' ...
    'Nothing is recorded, no loop-back cable is needed, and no .abr files are ' ...
    'written — each run instead saves the sequence it played to a .stimlog ' ...
    'file, so it can be lined up with whatever did the recording. The whole ' ...
    'Acquisition panel is disabled while this is set.'];
stimCheck = uicheckbox(g,'Text','Stimulation only (no recording / no loop-back)', ...
    'Value',settings0.StimulationOnly && ~settings0.Testing, ...
    'Tooltip',stimCheckTooltip, ...
    'ValueChangedFcn',@(~,~) onStimOnlyChanged());
stimCheck.Layout.Row = 3; stimCheck.Layout.Column = [1 3];

% Row 4: device
devLabel = uilabel(g,'Text','Device','HorizontalAlignment','right');
devLabel.Layout.Row = 4; devLabel.Layout.Column = 1;
devDrop = uidropdown(g,'Tooltip', ...
    'ASIO devices audioPlayerRecorder can see on this machine.', ...
    'ValueChangedFcn',@(~,~) onChange());
devDrop.Layout.Row = 4; devDrop.Layout.Column = 2;
setDeviceItems(devices,settings0.Device);
refreshBtn = uibutton(g,'Text','Refresh', ...
    'Tooltip','Re-query the system for ASIO devices.', ...
    'ButtonPushedFcn',@(~,~) onRefresh());
refreshBtn.Layout.Row = 4; refreshBtn.Layout.Column = 3;

% Row 5: player (output) channels -- [signal timing]
plLabel = uilabel(g,'Text','Player ch.','HorizontalAlignment','right', ...
    'Tooltip','[signal timing] output channels.');
plLabel.Layout.Row = 5; plLabel.Layout.Column = 1;
plRow = uigridlayout(g,[1 4]);
plRow.Layout.Row = 5; plRow.Layout.Column = [2 3];
plRow.ColumnWidth = {'fit',50,'fit',50};
plRow.Padding      = [0 0 0 0];
plRow.ColumnSpacing = 6;
plSigLbl = uilabel(plRow,'Text','signal'); plSigLbl.Layout.Row = 1; plSigLbl.Layout.Column = 1;
plSig = uieditfield(plRow,'numeric','Value',settings0.PlayerChannels(1), ...
    'Limits',[1 Inf],'RoundFractionalValues','on','ValueChangedFcn',@(~,~) onChange());
plSig.Layout.Row = 1; plSig.Layout.Column = 2;
plTimLbl = uilabel(plRow,'Text','timing'); plTimLbl.Layout.Row = 1; plTimLbl.Layout.Column = 3;
plTim = uieditfield(plRow,'numeric','Value',settings0.PlayerChannels(2), ...
    'Limits',[1 Inf],'RoundFractionalValues','on','ValueChangedFcn',@(~,~) onChange());
plTim.Layout.Row = 1; plTim.Layout.Column = 4;

% Row 6: recorder (input) channels -- [signal timing]
rcLabel = uilabel(g,'Text','Recorder ch.','HorizontalAlignment','right', ...
    'Tooltip','[signal timing] input channels.');
rcLabel.Layout.Row = 6; rcLabel.Layout.Column = 1;
rcRow = uigridlayout(g,[1 4]);
rcRow.Layout.Row = 6; rcRow.Layout.Column = [2 3];
rcRow.ColumnWidth = {'fit',50,'fit',50};
rcRow.Padding      = [0 0 0 0];
rcRow.ColumnSpacing = 6;
rcSigLbl = uilabel(rcRow,'Text','signal'); rcSigLbl.Layout.Row = 1; rcSigLbl.Layout.Column = 1;
rcSig = uieditfield(rcRow,'numeric','Value',settings0.RecorderChannels(1), ...
    'Limits',[1 Inf],'RoundFractionalValues','on','ValueChangedFcn',@(~,~) onChange());
rcSig.Layout.Row = 1; rcSig.Layout.Column = 2;
rcTimLbl = uilabel(rcRow,'Text','timing'); rcTimLbl.Layout.Row = 1; rcTimLbl.Layout.Column = 3;
rcTim = uieditfield(rcRow,'numeric','Value',settings0.RecorderChannels(2), ...
    'Limits',[1 Inf],'RoundFractionalValues','on','ValueChangedFcn',@(~,~) onChange());
rcTim.Layout.Row = 1; rcTim.Layout.Column = 4;

% Row 7: the calibration microphone input. Separate from the recorder mapping
% above because the two describe different sessions on the same wires --
% acquisition records an electrode, calibration records a measurement mic --
% and only mabr.stim.CalibrationAdapter ever reads this one.
micLabel = uilabel(g,'Text','Microphone');
micLabel.Layout.Row = 7; micLabel.Layout.Column = 1;
micRow = uigridlayout(g,[1 2]);
micRow.Layout.Row = 7; micRow.Layout.Column = [2 3];
micRow.ColumnWidth  = {50,'1x'};
micRow.Padding      = [0 0 0 0];
micRow.ColumnSpacing = 6;
micField = uieditfield(micRow,'numeric','Value',settings0.MicChannel, ...
    'Limits',[1 Inf],'RoundFractionalValues','on', ...
    'Tooltip','Input the calibration microphone is patched to. Used by calibration only, never by acquisition.', ...
    'ValueChangedFcn',@(~,~) onChange());
micField.Layout.Row = 1; micField.Layout.Column = 1;
micNote = uilabel(micRow,'Text','input channel, calibration only', ...
    'FontColor',[0.4 0.4 0.4]);
micNote.Layout.Row = 1; micNote.Layout.Column = 2;

% Row 8: the rate the device is opened at -- and, because the play matrix is
% rendered against it, the rate the whole session runs at. Editable rather
% than a fixed list: SupportedSampleRates is what is worth offering, not a
% claim about what hardware exists. The last value that VALIDATED is kept
% beside it, so a half-typed rate cannot make readControls throw on the
% keystroke-by-keystroke path syncCommitEnable runs on.
lastGoodRate = settings0.SampleRate;
rateLabel = uilabel(g,'Text','Sample rate','HorizontalAlignment','right', ...
    'Tooltip','Hz the ASIO device is opened at, and the rate every stimulus is rendered at.');
rateLabel.Layout.Row = 8; rateLabel.Layout.Column = 1;
rateRow = uigridlayout(g,[1 3]);
rateRow.Layout.Row = 8; rateRow.Layout.Column = [2 3];
rateRow.ColumnWidth  = {90,'1x','fit'};
rateRow.Padding      = [0 0 0 0];
rateRow.ColumnSpacing = 8;
rateDrop = uidropdown(rateRow,'Editable','on', ...
    'Tooltip',['Hz. Pick a standard rate or type one the device supports. ' ...
        'This is the only setting here that still matters under Test Mode: ' ...
        'stimuli are rendered at it whether or not a device is opened.'], ...
    'ValueChangedFcn',@(~,~) onRateChanged());
rateDrop.Layout.Row = 1; rateDrop.Layout.Column = 1;
setRateItems(settings0.SampleRate);
rateNote = uilabel(rateRow,'Text','','FontColor',[0.3 0.3 0.3]);
rateNote.Layout.Row = 1; rateNote.Layout.Column = 2;
% Many ASIO drivers own the rate outright: MATLAB asks, and the driver serves
% whatever its own control panel is set to. Audio Toolbox ships a function
% that opens exactly that panel (asiosettings), so the honest place to finish
% an argument about the rate is one button away rather than somewhere else on
% the machine. Set the panel, then press Test Device to see what was granted.
panelBtn = uibutton(rateRow,'Text','ASIO panel…', ...
    'Tooltip',['Open the device driver''s own control panel. Most ASIO drivers ' ...
        'set the sample rate there and MATLAB follows it -- change it, then ' ...
        'press Test Device to confirm what the device grants.'], ...
    'ButtonPushedFcn',@(~,~) onAsioPanel());
panelBtn.Layout.Row = 1; panelBtn.Layout.Column = 3;

% Row 9: what the rate above costs and constrains -- informational only
rateLbl = uilabel(g,'WordWrap','on','FontColor',[0.3 0.3 0.3],'Text', ...
    ['The storage rate is derived, not chosen: sweeps are windowed with a whole-' ...
     'sample stride, so it is always the rate above divided by an integer (the ' ...
     'one closest to 12 kHz). Committing a new rate re-renders the stimulus ' ...
     'bank at it and rebuilds the worker.']);
rateLbl.Layout.Row = 9; rateLbl.Layout.Column = [1 3];

% Row 10: determine the sample rate the selected device actually grants
probeBtn = uibutton(g,'Text','Test Device','ButtonPushedFcn',@(~,~) onProbe());
probeBtn.Layout.Row = 10; probeBtn.Layout.Column = 1;
probeLbl = uilabel(g,'Text','','WordWrap','on');
probeLbl.Layout.Row = 10; probeLbl.Layout.Column = [2 3];

% Row 11: what this does and does not touch
noteLbl = uilabel(g,'WordWrap','on','FontColor',[0.3 0.3 0.3], ...
    'Text','Locked while a schedule is running -- switching devices mid-acquisition is not supported.');
noteLbl.Layout.Row = 11; noteLbl.Layout.Column = [1 3];

% Row 12: validation / status
msgLbl = uilabel(g,'Text','','FontColor',[0.8 0.2 0]);
msgLbl.Layout.Row = 12; msgLbl.Layout.Column = [1 3];

% Row 13: transport. Commit applies without closing (see the header), so the
% pair is Commit/Cancel rather than OK/Cancel.
commitBtn = uibutton(g,'Text','Commit','BackgroundColor',[0.6 0.9 0.6], ...
    'FontWeight','bold','ButtonPushedFcn',@(~,~) onCommit());
commitBtn.Layout.Row = 13; commitBtn.Layout.Column = 2;
cancelBtn = uibutton(g,'Text','Cancel','ButtonPushedFcn',@(~,~) onCancel());
cancelBtn.Layout.Row = 13; cancelBtn.Layout.Column = 3;

if isempty(devices)
    msgLbl.Text = 'No ASIO devices found -- check the driver is installed and selected.';
end

% The controls were just filled from settings0, so reading them back is the
% NORMALIZED starting point (readControls reconciles StimulationOnly against
% Test Mode) -- which is what the dirty comparison has to be against, or a
% settings0 holding both flags would show as pending the moment it opened.
committed = readControls();

refreshRateNote();
syncTestingEnable();
syncCommitEnable();

uiwait(fig);

% ===================== nested callbacks ==================================
    function setDeviceItems(names,selected)
        % Populate the dropdown from a device list, keeping '' ("system
        % default") as the first entry always -- getAudioDevices never
        % includes it, and it is the one selection guaranteed to work when
        % nothing else does.
        items = [{'(system default)'}, names(:)'];
        data  = [{''},                 names(:)'];
        devDrop.Items     = items;
        devDrop.ItemsData = data;
        if any(strcmp(data,selected))
            devDrop.Value = selected;
        else
            devDrop.Value = '';
        end
    end

    function setRateItems(selected)
        % Standard rates plus whatever is actually selected, so a rig running
        % at a rate nobody listed still shows its own value rather than
        % silently snapping to a listed one.
        rates = mabr.Config.SupportedSampleRates;
        if ~any(rates == selected), rates = sort([rates selected]); end
        rateDrop.Items = arrayfun(@(r) sprintf('%g',r),rates,'UniformOutput',false);
        rateDrop.Value = sprintf('%g',selected);
    end

    function [fs,ok] = readRate()
        % Never throws: syncCommitEnable reads the controls on every edit, and
        % an editable dropdown is mid-typing for most of them. An unusable
        % entry reports itself and the last rate that DID validate stands in,
        % so the rest of the dialog keeps working while the field is wrong.
        fs = str2double(rateDrop.Value);
        ok = true;
        try
            fs = mabr.Config.validateSampleRate(fs);
            lastGoodRate = fs;
        catch
            ok = false;
            fs = lastGoodRate;
        end
    end

    function refreshRateNote()
        % What the selected rate works out to downstream: the derived storage
        % rate and the stride to it. The longest run the ring buffer can hold
        % scales with the rate too, which is a real consequence of the choice
        % and the reason cfg is still worth having here.
        [fs,ok] = readRate();
        df  = mabr.Config.decimationFor(fs);
        adc = mabr.Config.adcRateFor(fs);
        rateNote.Text = sprintf('→ %s kHz stored (÷%d)',mabr.Config.rateText(adc),df);
        rateNote.Tooltip = sprintf(['Storage/analysis rate, derived. At %s kHz the ' ...
            'ring buffer holds a run of up to %.1f min.'], ...
            mabr.Config.rateText(fs),cfg.maxInputBufferLength/fs/60);
        if ok
            rateNote.FontColor = [0.3 0.3 0.3];
        else
            rateNote.FontColor = [0.8 0.2 0];
        end
    end

    function onRateChanged()
        if ~isgraphics(fig), return; end
        [fs,ok] = readRate();
        if ~ok
            setMessage(sprintf('Not a usable sample rate — keeping %g Hz.',fs),false);
            setRateItems(fs);         % put the field back to the last good value
        else
            setMessage('',false);
            setRateItems(fs);         % normalize "192000.0" etc. to a listed item
        end
        % A probe result describes the rate it was run at, so it stops being
        % true the moment the rate changes.
        probeLbl.Text = '';
        refreshRateNote();
        syncCommitEnable();
    end

    function p = readControls()
        p = mabr.AudioSettings;
        p.Testing          = testCheck.Value;
        p.SampleRate       = readRate();
        % Test Mode wins: it opens no device at all, so there is nothing for
        % stimulation only to be a mode of. The checkbox is greyed rather than
        % cleared while Test Mode is set, so this is where the two are reconciled.
        p.StimulationOnly  = stimCheck.Value && ~testCheck.Value;
        p.Device            = devDrop.Value;
        p.PlayerChannels   = [plSig.Value plTim.Value];
        p.RecorderChannels = [rcSig.Value rcTim.Value];
        p.MicChannel       = micField.Value;
    end

    function syncTestingEnable()
        % Nothing below matters when Test Mode is set -- worker_loop's
        % prepare_device opens no device at all in that mode, so the device
        % picker, channel mapping, and probe are all moot. The explanation and
        % its wiki link stay live: they are most worth reading at the moment
        % the box is being ticked.
        %
        % Stimulation only is the same argument applied to half the dialog: a
        % real output device IS opened, so the device, the player mapping, and
        % the probe all still matter, but nothing is recorded, so the recorder
        % mapping and the mic input do not.
        testing  = testCheck.Value;
        stimOnly = stimCheck.Value && ~testing;
        onoff    = onOff(~testing);
        inputs   = onOff(~testing && ~stimOnly);
        stimCheck.Enable  = onoff;
        if testing
            % Explains the grey-out rather than leaving it to be discovered:
            % without this, checking the box while Test Mode is still on looks
            % like the setting silently failed to take, or failed to persist,
            % rather than that it was never live in the first place.
            stimCheck.Tooltip = 'Disabled while Test Mode is set -- turn that off first.';
        else
            stimCheck.Tooltip = stimCheckTooltip;
        end
        devDrop.Enable    = onoff;
        refreshBtn.Enable = onoff;
        % The rate picker stays live under Test Mode (see below); the button that
        % opens a real driver's panel cannot.
        panelBtn.Enable   = onoff;
        % rateDrop is deliberately absent from all of this and never greyed.
        % Every other control here describes a device; the rate also decides
        % what mabr.stim.Schedule renders and what the ring buffer is clocked
        % at, both of which a Test Mode run does exactly as a real one does.
        plSig.Enable = onoff; plTim.Enable = onoff;
        rcSig.Enable = inputs; rcTim.Enable = inputs;
        % The mic channel goes with the recorder mapping under Test Mode --
        % calibration needs a real device just as much as acquisition does, and
        % mabr.stim.CalibrationAdapter refuses to run in Test Mode for
        % exactly that reason -- and with it under stimulation only, where the
        % device being opened has no input side to measure through.
        micField.Enable = inputs;
        probeBtn.Enable = onoff;
        if testing
            probeBtn.Tooltip = 'Not available in Test Mode -- there is no device to probe.';
        else
            probeBtn.Tooltip = ['Briefly opens the selected device at the rate above and ' ...
                'reports the rate it actually grants.'];
        end
    end

    function syncCommitEnable()
        % Commit is live only while the controls disagree with what was last
        % committed -- greyed, it says "nothing pending" without a word.
        %
        % Cancel is re-labelled by the same test, because what it means
        % depends on it: with an edit pending it cancels that edit, and with
        % none it is simply Close. Calling it Cancel in the second case would
        % imply committed settings are about to be undone, which they are not
        % -- they have already been applied.
        working = readControls();
        dirty   = ~isequal(working.toStruct(),committed.toStruct());
        commitBtn.Enable = onOff(dirty);
        if dirty
            commitBtn.Tooltip = 'Apply these settings now. The dialog stays open.';
            cancelBtn.Text    = 'Cancel';
            cancelBtn.Tooltip = 'Close, discarding the changes not yet committed.';
        else
            commitBtn.Tooltip = 'No changes to apply.';
            cancelBtn.Text    = 'Close';
            cancelBtn.Tooltip = 'Close. Everything shown here has been applied.';
        end
    end

    function onTestingChanged()
        if ~isgraphics(fig), return; end
        syncTestingEnable();
        syncCommitEnable();
        probeLbl.Text = '';
    end

    function onStimOnlyChanged()
        if ~isgraphics(fig), return; end
        syncTestingEnable();
        syncCommitEnable();
        probeLbl.Text = '';
    end

    function onChange()
        if ~isgraphics(fig), return; end
        msgLbl.Text = '';
        probeLbl.Text = '';
        syncCommitEnable();
    end

    function onRefresh()
        devices = mabr.AudioSettings.availableDevices();
        setDeviceItems(devices,devDrop.Value);
        if isempty(devices)
            setMessage('No ASIO devices found -- check the driver is installed and selected.',false);
        else
            setMessage('',false);
        end
        % A refresh can drop the selected device off the list, which
        % setDeviceItems falls back from -- that is an edit like any other.
        syncCommitEnable();
    end

    function onAsioPanel()
        % The panel is the driver's, not MATLAB's, so this only ever opens it
        % -- nothing is read back. Whatever the user changes there shows up in
        % what Test Device reports, which is the one number this dialog can
        % honestly state about the device.
        working = readControls();
        try
            if isempty(working.Device)
                asiosettings();
            else
                asiosettings(working.Device);
            end
            setMessage('ASIO panel opened — press Test Device to see the result.',true);
        catch me
            setMessage(sprintf('Could not open the ASIO panel: %s',me.message),false);
        end
    end

    function onProbe()
        probeLbl.Text = 'Probing…'; probeLbl.FontColor = [0.3 0.3 0.3]; drawnow;
        working = readControls();
        [~,ok,msg] = working.probeSampleRate();
        probeLbl.Text = msg;
        if ok
            probeLbl.FontColor = [0 0.5 0];
        else
            probeLbl.FontColor = [0.8 0.2 0];
        end
    end

    function onCommit()
        % Apply, and stay open. The owner's applyFcn is what actually updates
        % the parameters and re-derives the main window from them, so a failure
        % there leaves the edit uncommitted rather than reporting a success the
        % app never had.
        working = readControls();
        if ~isempty(applyFcn)
            try
                applyFcn(working);
            catch me
                setMessage(sprintf('Could not apply: %s',me.message),false);
                return
            end
        end
        committed = working;
        settings  = working;
        % The one-line status row is too narrow for describe(), and the app's
        % own status line already carries it (applyAudioSettings), so the
        % summary goes in the tooltip rather than being clipped here.
        setMessage('Committed.',true);
        msgLbl.Tooltip = working.describe();
        syncCommitEnable();
    end

    function onCancel()
        % `settings` is left exactly as the last Commit set it (or [] if there
        % never was one): an edit still pending is discarded, but anything
        % already committed has been applied and stands.
        mabr.ui.WindowPos.remember(fig,'AudioSettingsDialog');
        delete(fig);
    end

    function setMessage(txt,good)
        msgLbl.Text = txt;
        if good
            msgLbl.FontColor = [0 0.5 0];
        else
            msgLbl.FontColor = [0.8 0.2 0];
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end
