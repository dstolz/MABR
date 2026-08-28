classdef AudioSettings
% mabr.AudioSettings  ASIO device and channel mapping for the acquisition engine.
%
%   Like mabr.Config, mabr.ArtifactPolicy, and mabr.FilterPolicy this is a
%   plain value object and a superclass of nothing. It holds exactly the
%   audioPlayerRecorder arguments mabr.acq.worker_loop's prepare_device does
%   not hard-code, plus the TEST MODE switch that determines whether a device
%   is opened at all:
%
%       Device            ASIO device name ('' = whatever audioPlayerRecorder
%                         opens by default)
%       SampleRate        Hz the device is opened at, and therefore the rate
%                         every stimulus must be rendered at and the ring
%                         buffer runs at. config() is the one place it becomes
%                         a mabr.Config; the analysis/storage rate is DERIVED
%                         from it there (mabr.Config.adcRateFor), never chosen
%                         separately.
%       PlayerChannels    [DACsignal DACtiming] output channel mapping
%       RecorderChannels  [ADCsignal ADCtiming] input channel mapping
%       Testing           TEST MODE, as the GUI names it: true = run the
%                         whole engine with no audio device (worker_loop's
%                         prepare_device creates none) and copy each frame of
%                         the stimulus straight into the acquisition ring
%                         buffer instead; false = open Device for real. The
%                         copy is what makes it a check rather than merely a
%                         way to run without hardware -- a recorded sweep is
%                         the presentation the schedule placed at that onset,
%                         so mabr.ui.AcqController.alignmentCheck can hold the
%                         two against each other after every run. Lives here,
%                         not on the main window, because it is meaningless
%                         without an opinion about which device would
%                         otherwise be opened -- mabr.ui.AudioSettingsDialog
%                         is where both are decided together, and greys the
%                         device/channel controls out while it is set. The
%                         property keeps its old name: it is what prefs and
%                         every .mabrcfg ever saved call it, and renaming a
%                         stored field to improve a label would cost every
%                         one of those files its setting.
%       StimulationOnly   true = play the signal and the timing pulse but
%                         record nothing (worker_loop's prepare_device builds
%                         an output-only audioDeviceWriter), so MABR can drive
%                         stimuli for a rig where something else records --
%                         and on hardware with no input channels at all. It
%                         is a real device, so it sits beside Testing rather
%                         than inside it, and the two are mutually exclusive.
%
%   mabr.ui.AudioSettingsDialog edits one; mabr.ui.App owns it (loaded via
%   loadPrefs at startup) and hands Device/PlayerChannels/RecorderChannels to
%   mabr.stim.Schedule in buildSchedule, the same one place Strategy/
%   Repetitions/ISI already become a schedule. loadPrefs/savePrefs persist the
%   choice in the same 'MABR' pref group as ArtifactPolicy and FilterPolicy,
%   so a rig keeps whatever ASIO device and wiring suits it. Unlike those two
%   it is a CONFIG control, not a live one: it locks once a schedule starts
%   (mabr.ui.App.configControls), because the worker's audioPlayerRecorder is
%   already open on whatever device Start handed it.
%
%   SampleRate is the one setting here that reaches beyond the device. It is
%   the rate the ASIO device is opened at, so it is also the rate
%   mabr.stim.StimulusSet requires every stimulus to already be rendered at
%   and the rate the ring buffer is filled at -- which is why changing it is
%   not merely a device edit: mabr.ui.App.applyAudioSettings rebuilds its
%   mabr.Config from it, regenerates the stimulus bank at the new rate where
%   the bank's own Source allows, and rebuilds the acquisition controller so
%   the engine, the live view, and finalization are all on one clock. The
%   ANALYSIS rate is not a second setting: mabr.Config derives it by integer
%   decimation, because sweep extraction windows the ring buffer with a whole
%   stride and cannot take a fraction.
%
%   Asking for a rate is not the same as getting one: probeSampleRate briefly
%   opens a real device on it and reports what the driver actually granted,
%   rather than trusting the request silently.
%
% Daniel Stolzberg (c) 2026

    properties
        Device           (1,:) char   = ''      % '' = audioPlayerRecorder default

        % Hz the device is opened at (and every stimulus rendered at). The
        % storage/analysis rate is NOT a companion setting -- mabr.Config
        % derives it from this one by integer decimation, so there is no way
        % to pick a pair that cannot actually be resampled between.
        SampleRate       (1,1) double = mabr.Config.DefaultDACSampleRate

        PlayerChannels   (1,2) double = [1 2]   % [DACsignal DACtiming]
        RecorderChannels (1,2) double = [1 2]   % [ADCsignal ADCtiming]
        Testing          (1,1) logical = true   % TEST MODE: stimulus -> acquisition buffer

        % Playback + timing pulse only: a real output device is opened, but
        % nothing is recorded and no loop-back is required (see
        % mabr.acq.worker_loop's prepare_device and mabr.ui.AcqController's
        % start, which skips the timing self-test). Mutually exclusive with
        % Testing (Test Mode), which opens no device at all -- Test Mode wins
        % wherever both are somehow set.
        StimulationOnly  (1,1) logical = false  % play only, record nothing

        % Input the calibration microphone is patched to. Separate from
        % RecorderChannels because calibration and acquisition listen to
        % different things down the same wires: acquisition records an
        % electrode, calibration records a measurement mic. Used only by
        % mabr.stim.CalibrationAdapter -- the acquisition engine never reads
        % it, and nothing about it can reach a .abr file.
        MicChannel       (1,1) double = 1
    end

    methods
        function tf = isStimulationOnly(obj)
            % Stimulation only, as everything downstream should ask it.
            % Testing wins -- it opens no device at all, so there is nothing
            % for stimulation only to be a mode of -- and asking the question
            % here rather than reading the raw property keeps a hand-edited
            % pref or an old configuration file holding both flags from
            % putting the app in a half state (the dialog enforces the same
            % rule at the point of edit; this is the backstop).
            tf = obj.StimulationOnly && ~obj.Testing;
        end

        function cfg = config(obj)
            % The one place this setting becomes a mabr.Config. Everything
            % downstream reads the rate off a Config -- the schedule renders
            % against it, extract_sweeps strides by its decimationFactor,
            % finalize_run resamples to its ADCSampleRate -- so building the
            % Config here, from the setting, is what keeps those three on one
            % clock instead of three copies of a constant.
            cfg = mabr.Config(obj.SampleRate);
        end

        function s = describe(obj)
            % One-line summary for the status line / menu, mirroring
            % FilterPolicy.describe / ArtifactPolicy.describe.
            %
            % The rate is named in EVERY branch, Test Mode included: it is
            % the rate stimuli are rendered at and the ring buffer is filled
            % at, which a Test Mode run does just as much as a real one -- it
            % is the only setting here that still means something with no
            % device open.
            rate = sprintf('%s kHz',mabr.Config.rateText(obj.SampleRate));
            if obj.Testing
                % Named for what it DOES, not for what it lacks: "no hardware"
                % describes a limitation, while what an operator has to know
                % from a one-line summary is that the samples being recorded
                % are the stimulus.
                s = sprintf('TEST MODE (stimulus copied to acquisition), %s',rate);
                return
            end
            if isempty(obj.Device)
                dev = 'default ASIO device';
            else
                dev = obj.Device;
            end
            if obj.isStimulationOnly()
                % No recorder mapping to report -- an output-only device has
                % no input side to map.
                s = sprintf('%s @ %s, player [%d %d], stimulation only (no recording)', ...
                    dev,rate,obj.PlayerChannels);
                return
            end
            s = sprintf('%s @ %s, player [%d %d], recorder [%d %d]', ...
                dev,rate,obj.PlayerChannels,obj.RecorderChannels);
        end

        function [achievedHz,ok,msg] = probeSampleRate(obj)
            % Briefly open a real device on this Device and report the sample
            % rate it actually grants -- so a mismatched or misconfigured ASIO
            % driver is caught from the settings dialog, not partway into a
            % session. Never called in TESTING mode: there is no device to
            % probe there.
            %
            % The rate requested is this object's own SampleRate, not a
            % Config's: the dialog probes what the user is about to commit,
            % which is the whole point of a Test Device button sitting under an
            % editable rate picker. Nothing is adopted from the answer -- a
            % driver that quietly substitutes another rate is reported, not
            % accommodated, because the stimuli are rendered at the requested
            % one and a silent substitution would mis-scale every one of them.
            %
            % The device opened is the one the worker will open (see
            % mabr.acq.worker_loop's prepare_device): an output-only
            % audioDeviceWriter under StimulationOnly, an audioPlayerRecorder
            % otherwise. Probing full-duplex in stimulation-only mode would
            % fail on exactly the input-less hardware that mode exists for.
            wantHz = obj.SampleRate;
            achievedHz = NaN; ok = false;
            args = {'SampleRate',wantHz,'BitDepth','32-bit float'};
            if ~isempty(obj.Device), args = [args,{'Device',obj.Device}]; end
            apr = [];
            try
                if obj.isStimulationOnly()
                    % 'Driver' named explicitly for the same reason
                    % worker_loop's prepare_device names it: audioDeviceWriter
                    % defaults to DirectSound, and this Device came off the
                    % ASIO list.
                    apr = audioDeviceWriter(args{:},'Driver','ASIO');
                else
                    apr = audioPlayerRecorder(args{:});
                end
                achievedHz = apr.SampleRate;
                ok = achievedHz == wantHz;
                if ok
                    msg = sprintf('Confirmed: device runs at %g Hz (stores %g Hz).', ...
                        achievedHz,mabr.Config.adcRateFor(achievedHz));
                else
                    msg = sprintf(['Device granted %g Hz, not the %g Hz requested -- ' ...
                        'check the ASIO control panel, or select %g Hz here.'], ...
                        achievedHz,wantHz,achievedHz);
                end
            catch me
                msg = sprintf('Could not open device: %s',me.message);
            end
            if ~isempty(apr)
                try, release(apr); end %#ok<TRYNC>
                try, delete(apr);  end %#ok<TRYNC>
            end
        end

        function s = toStruct(obj)
            % Plain-struct snapshot for mabr.ui.App's save/load CONFIGURATION
            % file -- a named, shareable setup, distinct from loadPrefs/
            % savePrefs's "last used" persistence in MATLAB prefs, though the
            % two travel through the same validated fields.
            s = struct('Device',obj.Device,'SampleRate',obj.SampleRate, ...
                       'PlayerChannels',obj.PlayerChannels, ...
                       'RecorderChannels',obj.RecorderChannels,'Testing',obj.Testing, ...
                       'StimulationOnly',obj.StimulationOnly, ...
                       'MicChannel',obj.MicChannel);
        end
    end

    methods (Static)
        function names = availableDevices()
            % ASIO device names audioPlayerRecorder can see on this machine,
            % or {} if none are visible (no driver installed, no device
            % plugged in, or the Audio Toolbox license is unavailable) --
            % never throws, since this feeds a settings dialog, not a
            % start-up check.
            try
                names = getAudioDevices(audioPlayerRecorder);
            catch me
                names = {};
                mabr.log.vprintf(1,'ASIO device query failed: %s',me.message);
            end
        end

        function obj = loadPrefs()
            % Restore the last session's device/channels, falling back to the
            % property defaults for anything never saved (or saved invalid --
            % a pref edited by hand should not stop the app from opening).
            obj = mabr.AudioSettings;
            obj.Device           = mabr.AudioSettings.getChar('AudioDevice',obj.Device);
            obj.SampleRate       = mabr.AudioSettings.getRate('AudioSampleRate',obj.SampleRate);
            obj.PlayerChannels   = mabr.AudioSettings.getChannels('AudioPlayerChannels',obj.PlayerChannels);
            obj.RecorderChannels = mabr.AudioSettings.getChannels('AudioRecorderChannels',obj.RecorderChannels);
            obj.Testing          = mabr.AudioSettings.getLogical('AudioTesting',obj.Testing);
            obj.StimulationOnly  = mabr.AudioSettings.getLogical('AudioStimulationOnly',obj.StimulationOnly);
            obj.MicChannel       = mabr.AudioSettings.getChannel('AudioMicChannel',obj.MicChannel);
        end

        function savePrefs(obj)
            setpref('MABR','AudioDevice',           obj.Device);
            setpref('MABR','AudioSampleRate',       obj.SampleRate);
            setpref('MABR','AudioPlayerChannels',   obj.PlayerChannels);
            setpref('MABR','AudioRecorderChannels', obj.RecorderChannels);
            setpref('MABR','AudioTesting',          obj.Testing);
            setpref('MABR','AudioStimulationOnly',  obj.StimulationOnly);
            setpref('MABR','AudioMicChannel',       obj.MicChannel);
        end

        function obj = fromStruct(s)
            % Inverse of toStruct. Forgiving of a struct saved by an older
            % MABR or edited by hand -- the same rule loadPrefs follows:
            % restore whatever field validates and fall back to the property
            % default for anything that does not.
            obj = mabr.AudioSettings;
            if isfield(s,'Device')
                obj.Device = mabr.AudioSettings.coerceChar(s.Device,obj.Device);
            end
            if isfield(s,'SampleRate')
                obj.SampleRate = mabr.AudioSettings.coerceRate(s.SampleRate,obj.SampleRate);
            end
            if isfield(s,'PlayerChannels')
                obj.PlayerChannels = mabr.AudioSettings.coerceChannels(s.PlayerChannels,obj.PlayerChannels);
            end
            if isfield(s,'RecorderChannels')
                obj.RecorderChannels = mabr.AudioSettings.coerceChannels(s.RecorderChannels,obj.RecorderChannels);
            end
            if isfield(s,'Testing')
                obj.Testing = mabr.AudioSettings.coerceLogical(s.Testing,obj.Testing);
            end
            if isfield(s,'StimulationOnly')
                obj.StimulationOnly = mabr.AudioSettings.coerceLogical(s.StimulationOnly,obj.StimulationOnly);
            end
            if isfield(s,'MicChannel')
                obj.MicChannel = mabr.AudioSettings.coerceChannel(s.MicChannel,obj.MicChannel);
            end
        end
    end

    methods (Static, Access = private)
        function v = getChar(name,default)
            v = mabr.AudioSettings.coerceChar(getpref('MABR',name,default),default);
        end

        function v = getLogical(name,default)
            v = mabr.AudioSettings.coerceLogical(getpref('MABR',name,default),default);
        end

        function v = getRate(name,default)
            v = mabr.AudioSettings.coerceRate(getpref('MABR',name,default),default);
        end

        function v = getChannel(name,default)
            % Scalar sibling of getChannels, same forgiving contract: a pref
            % edited by hand should not stop the app from opening.
            v = mabr.AudioSettings.coerceChannel(getpref('MABR',name,default),default);
        end

        function v = getChannels(name,default)
            v = mabr.AudioSettings.coerceChannels(getpref('MABR',name,default),default);
        end

        function v = coerceChar(v,default)
            if ~ischar(v), v = default; end
        end

        function v = coerceLogical(v,default)
            if ~islogical(v) && ~(isnumeric(v) && isscalar(v)), v = default; end
            v = logical(v);
        end

        function v = coerceRate(v,default)
            % Same forgiving contract as the rest: a pref or configuration file
            % holding a rate this MABR will not accept falls back to the
            % default rather than stopping the app from opening. Validation is
            % mabr.Config's, so there is one rule about what a rate may be.
            try
                v = mabr.Config.validateSampleRate(v);
            catch
                v = default;
            end
        end

        function v = coerceChannel(v,default)
            if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v < 1 || mod(v,1) ~= 0
                v = default;
            else
                v = double(v);
            end
        end

        function v = coerceChannels(v,default)
            if ~isnumeric(v) || numel(v) ~= 2 || any(~isfinite(v)) || any(v < 1) || any(mod(v,1) ~= 0)
                v = default;
            else
                v = double(v(:)');
            end
        end
    end
end
