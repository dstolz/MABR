function settings = AudioSettingsDialog(settings0,cfg)
% mabr.ui.AudioSettingsDialog  Modal editor for Testing (loopback) mode, the
% ASIO device, and the channel mapping.
%
%   s = mabr.ui.AudioSettingsDialog(s0,cfg) opens a small modal window over a
%   mabr.AudioSettings and returns the edited settings, or [] if the user
%   cancelled.
%
%   Testing (loopback, no hardware) lives at the top: it decides whether a
%   device is opened at all (mabr.acq.worker_loop's prepare_device creates
%   none when it is set), so it belongs beside the device it overrides, not
%   on the main window. Checking it greys out the device dropdown, channel
%   fields, and Test Device button -- none of them matter when nothing is
%   going to be opened.
%
%   Stimulation only (no recording / no loop-back) sits directly beneath it,
%   and is the same kind of switch one step less drastic: a real output device
%   IS opened (an audioDeviceWriter), so the device, player channels, and Test
%   Device all still matter -- but nothing is recorded, so the recorder
%   channels and the microphone input do not. The two are mutually exclusive
%   and Testing wins: it opens no device at all, which leaves nothing for
%   stimulation only to be a mode of.
%
%   The DAC/ADC sample rates are shown but not editable here: mabr.Config
%   fixes them because every stimulus must already be rendered at
%   Config.DACSampleRate (see mabr.stim.StimulusSet). What this dialog adds is
%   a way to DETERMINE whether the selected device actually honours that rate
%   -- "Test Device" briefly opens a real audioPlayerRecorder and reports back
%   what it granted, rather than trusting the request silently.
%
% Daniel Stolzberg (c) 2026

if nargin < 1 || isempty(settings0), settings0 = mabr.AudioSettings; end
if nargin < 2 || isempty(cfg),       cfg = mabr.Config; end

settings = [];                       % [] unless OK is pressed
devices  = mabr.AudioSettings.availableDevices();

% ---- layout -------------------------------------------------------------
fig = uifigure('Name','Audio Device (ASIO)','Position',[100 100 440 452], ...
    'WindowStyle','modal','Resize','off', ...
    'CloseRequestFcn',@(~,~) onCancel());
mabr.ui.WindowPos.restore(fig,'AudioSettingsDialog',fig.Position);

g = uigridlayout(fig,[11 3]);
g.RowHeight   = {28,28,28,32,32,32,48,24,32,18,32};
g.ColumnWidth = {100,'1x','fit'};
g.Padding     = [12 10 12 10];
g.RowSpacing  = 8;

% Row 1: Testing (loopback) mode -- decides whether anything below matters
testCheck = uicheckbox(g,'Text','Testing (loopback, no hardware)', ...
    'Value',settings0.Testing, ...
    'Tooltip','Run the whole engine without an audio device. Changing this rebuilds the worker.', ...
    'ValueChangedFcn',@(~,~) onTestingChanged());
testCheck.Layout.Row = 1; testCheck.Layout.Column = [1 3];

% Row 2: stimulation-only mode -- a real output device, but nothing recorded
stimCheck = uicheckbox(g,'Text','Stimulation only (no recording / no loop-back)', ...
    'Value',settings0.StimulationOnly && ~settings0.Testing, ...
    'Tooltip',['Play the signal and timing pulse through an output-only device. ' ...
               'Nothing is recorded, no loop-back cable is needed, and no .abr files are written.'], ...
    'ValueChangedFcn',@(~,~) onStimOnlyChanged());
stimCheck.Layout.Row = 2; stimCheck.Layout.Column = [1 3];

% Row 3: device
devLabel = uilabel(g,'Text','Device','HorizontalAlignment','right');
devLabel.Layout.Row = 3; devLabel.Layout.Column = 1;
devDrop = uidropdown(g,'Tooltip', ...
    'ASIO devices audioPlayerRecorder can see on this machine.', ...
    'ValueChangedFcn',@(~,~) onChange());
devDrop.Layout.Row = 3; devDrop.Layout.Column = 2;
setDeviceItems(devices,settings0.Device);
refreshBtn = uibutton(g,'Text','Refresh', ...
    'Tooltip','Re-query the system for ASIO devices.', ...
    'ButtonPushedFcn',@(~,~) onRefresh());
refreshBtn.Layout.Row = 3; refreshBtn.Layout.Column = 3;

% Row 4: player (output) channels -- [signal timing]
plLabel = uilabel(g,'Text','Player ch.','HorizontalAlignment','right', ...
    'Tooltip','[signal timing] output channels.');
plLabel.Layout.Row = 4; plLabel.Layout.Column = 1;
plRow = uigridlayout(g,[1 4]);
plRow.Layout.Row = 4; plRow.Layout.Column = [2 3];
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

% Row 5: recorder (input) channels -- [signal timing]
rcLabel = uilabel(g,'Text','Recorder ch.','HorizontalAlignment','right', ...
    'Tooltip','[signal timing] input channels.');
rcLabel.Layout.Row = 5; rcLabel.Layout.Column = 1;
rcRow = uigridlayout(g,[1 4]);
rcRow.Layout.Row = 5; rcRow.Layout.Column = [2 3];
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

% Row 6: the calibration microphone input. Separate from the recorder mapping
% above because the two describe different sessions on the same wires --
% acquisition records an electrode, calibration records a measurement mic --
% and only mabr.stim.CalibrationAdapter ever reads this one.
micLabel = uilabel(g,'Text','Microphone');
micLabel.Layout.Row = 6; micLabel.Layout.Column = 1;
micRow = uigridlayout(g,[1 2]);
micRow.Layout.Row = 6; micRow.Layout.Column = [2 3];
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

% Row 7: the fixed rates -- informational only, see mabr.Config
rateLbl = uilabel(g,'WordWrap','on','FontColor',[0.3 0.3 0.3], ...
    'Text',sprintf(['Fixed by Config: %g kHz full-duplex, decimated %gx to %g ' ...
        'kHz for storage/analysis. Every stimulus must already be rendered ' ...
        'at %g kHz.'], ...
        cfg.DACSampleRate/1e3,cfg.decimationFactor,cfg.ADCSampleRate/1e3,cfg.DACSampleRate/1e3));
rateLbl.Layout.Row = 7; rateLbl.Layout.Column = [1 3];

% Row 8: determine the sample rate the selected device actually grants
probeBtn = uibutton(g,'Text','Test Device','ButtonPushedFcn',@(~,~) onProbe());
probeBtn.Layout.Row = 8; probeBtn.Layout.Column = 1;
probeLbl = uilabel(g,'Text','','WordWrap','on');
probeLbl.Layout.Row = 8; probeLbl.Layout.Column = [2 3];

% Row 9: what this does and does not touch
noteLbl = uilabel(g,'WordWrap','on','FontColor',[0.3 0.3 0.3], ...
    'Text','Locked while a schedule is running -- switching devices mid-acquisition is not supported.');
noteLbl.Layout.Row = 9; noteLbl.Layout.Column = [1 3];

% Row 10: validation / status
msgLbl = uilabel(g,'Text','','FontColor',[0.8 0.2 0]);
msgLbl.Layout.Row = 10; msgLbl.Layout.Column = [1 3];

% Row 11: transport
okBtn = uibutton(g,'Text','OK','BackgroundColor',[0.6 0.9 0.6], ...
    'FontWeight','bold','ButtonPushedFcn',@(~,~) onOK());
okBtn.Layout.Row = 11; okBtn.Layout.Column = 2;
cancelBtn = uibutton(g,'Text','Cancel','ButtonPushedFcn',@(~,~) onCancel());
cancelBtn.Layout.Row = 11; cancelBtn.Layout.Column = 3;

if isempty(devices)
    msgLbl.Text = 'No ASIO devices found -- check the driver is installed and selected.';
end

syncTestingEnable();

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

    function p = readControls()
        p = mabr.AudioSettings;
        p.Testing          = testCheck.Value;
        % Testing wins: it opens no device at all, so there is nothing for
        % stimulation only to be a mode of. The checkbox is greyed rather than
        % cleared while Testing is set, so this is where the two are reconciled.
        p.StimulationOnly  = stimCheck.Value && ~testCheck.Value;
        p.Device            = devDrop.Value;
        p.PlayerChannels   = [plSig.Value plTim.Value];
        p.RecorderChannels = [rcSig.Value rcTim.Value];
        p.MicChannel       = micField.Value;
    end

    function syncTestingEnable()
        % Nothing below matters when Testing is set -- worker_loop's
        % prepare_device opens no device at all in that mode, so the device
        % picker, channel mapping, and probe are all moot.
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
        devDrop.Enable    = onoff;
        refreshBtn.Enable = onoff;
        plSig.Enable = onoff; plTim.Enable = onoff;
        rcSig.Enable = inputs; rcTim.Enable = inputs;
        % The mic channel goes with the recorder mapping under Testing --
        % calibration needs a real device just as much as acquisition does, and
        % mabr.stim.CalibrationAdapter refuses to run in Testing mode for
        % exactly that reason -- and with it under stimulation only, where the
        % device being opened has no input side to measure through.
        micField.Enable = inputs;
        probeBtn.Enable = onoff;
        if testing
            probeBtn.Tooltip = 'Not available in Testing (loopback) mode -- there is no device to probe.';
        else
            probeBtn.Tooltip = 'Briefly opens the selected device and reports the sample rate it actually grants.';
        end
    end

    function onTestingChanged()
        if ~isgraphics(fig), return; end
        syncTestingEnable();
        probeLbl.Text = '';
    end

    function onStimOnlyChanged()
        if ~isgraphics(fig), return; end
        syncTestingEnable();
        probeLbl.Text = '';
    end

    function onChange()
        if ~isgraphics(fig), return; end
        msgLbl.Text = '';
        probeLbl.Text = '';
    end

    function onRefresh()
        devices = mabr.AudioSettings.availableDevices();
        setDeviceItems(devices,devDrop.Value);
        if isempty(devices)
            msgLbl.Text = 'No ASIO devices found -- check the driver is installed and selected.';
        else
            msgLbl.Text = '';
        end
    end

    function onProbe()
        probeLbl.Text = 'Probing…'; probeLbl.FontColor = [0.3 0.3 0.3]; drawnow;
        working = readControls();
        [~,ok,msg] = working.probeSampleRate(cfg);
        probeLbl.Text = msg;
        if ok
            probeLbl.FontColor = [0 0.5 0];
        else
            probeLbl.FontColor = [0.8 0.2 0];
        end
    end

    function onOK()
        settings = readControls();
        mabr.ui.WindowPos.remember(fig,'AudioSettingsDialog');
        delete(fig);
    end

    function onCancel()
        settings = [];
        mabr.ui.WindowPos.remember(fig,'AudioSettingsDialog');
        delete(fig);
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end
