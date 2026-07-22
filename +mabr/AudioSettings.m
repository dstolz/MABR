classdef AudioSettings
% mabr.AudioSettings  ASIO device and channel mapping for the acquisition engine.
%
%   Like mabr.Config, mabr.ArtifactPolicy, and mabr.FilterPolicy this is a
%   plain value object and a superclass of nothing. It holds exactly the
%   audioPlayerRecorder arguments mabr.acq.worker_loop's prepare_device does
%   not hard-code, plus the TESTING (loopback) mode switch that determines
%   whether a device is opened at all:
%
%       Device            ASIO device name ('' = whatever audioPlayerRecorder
%                         opens by default)
%       PlayerChannels    [DACsignal DACtiming] output channel mapping
%       RecorderChannels  [ADCsignal ADCtiming] input channel mapping
%       Testing           true = run the whole engine with no audio device
%                         (worker_loop's prepare_device creates none); false =
%                         open Device for real. Lives here, not on the main
%                         window, because it is meaningless without an
%                         opinion about which device would otherwise be
%                         opened -- mabr.ui.AudioSettingsDialog is where both
%                         are decided together, and greys the device/channel
%                         controls out while it is set.
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
%   The DAC/ADC sample rates are NOT settable here -- mabr.Config fixes them
%   (192 kHz full-duplex, decimated to 12 kHz for storage/analysis) because
%   mabr.stim.StimulusSet requires every stimulus to already be rendered at
%   Config.DACSampleRate. What IS worth determining is whether the SELECTED
%   ASIO device actually honours that rate: probeSampleRate briefly opens a
%   real audioPlayerRecorder on it and reports what it granted, rather than
%   trusting the request silently.
%
% Daniel Stolzberg (c) 2026

    properties
        Device           (1,:) char   = ''      % '' = audioPlayerRecorder default
        PlayerChannels   (1,2) double = [1 2]   % [DACsignal DACtiming]
        RecorderChannels (1,2) double = [1 2]   % [ADCsignal ADCtiming]
        Testing          (1,1) logical = true   % loopback, no hardware

        % Input the calibration microphone is patched to. Separate from
        % RecorderChannels because calibration and acquisition listen to
        % different things down the same wires: acquisition records an
        % electrode, calibration records a measurement mic. Used only by
        % mabr.stim.CalibrationAdapter -- the acquisition engine never reads
        % it, and nothing about it can reach a .abr file.
        MicChannel       (1,1) double = 1
    end

    methods
        function s = describe(obj)
            % One-line summary for the status line / menu, mirroring
            % FilterPolicy.describe / ArtifactPolicy.describe.
            if obj.Testing
                s = 'TESTING (loopback, no hardware)';
                return
            end
            if isempty(obj.Device)
                dev = 'default ASIO device';
            else
                dev = obj.Device;
            end
            s = sprintf('%s, player [%d %d], recorder [%d %d]', ...
                dev,obj.PlayerChannels,obj.RecorderChannels);
        end

        function [achievedHz,ok,msg] = probeSampleRate(obj,cfg)
            % Briefly open a real audioPlayerRecorder on this Device and
            % report the sample rate it actually grants -- so a mismatched or
            % misconfigured ASIO driver is caught from the settings dialog,
            % not partway into a session. Never called in TESTING mode: there
            % is no device to probe there.
            if nargin < 2 || isempty(cfg), cfg = mabr.Config; end
            achievedHz = NaN; ok = false;
            args = {'SampleRate',cfg.DACSampleRate,'BitDepth','32-bit float'};
            if ~isempty(obj.Device), args = [args,{'Device',obj.Device}]; end
            apr = [];
            try
                apr = audioPlayerRecorder(args{:});
                achievedHz = apr.SampleRate;
                ok = achievedHz == cfg.DACSampleRate;
                if ok
                    msg = sprintf('Confirmed: device runs at %g Hz.',achievedHz);
                else
                    msg = sprintf(['Device granted %g Hz, not the required %g Hz -- ' ...
                        'check the ASIO control panel.'],achievedHz,cfg.DACSampleRate);
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
            s = struct('Device',obj.Device,'PlayerChannels',obj.PlayerChannels, ...
                       'RecorderChannels',obj.RecorderChannels,'Testing',obj.Testing, ...
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
            obj.PlayerChannels   = mabr.AudioSettings.getChannels('AudioPlayerChannels',obj.PlayerChannels);
            obj.RecorderChannels = mabr.AudioSettings.getChannels('AudioRecorderChannels',obj.RecorderChannels);
            obj.Testing          = mabr.AudioSettings.getLogical('AudioTesting',obj.Testing);
            obj.MicChannel       = mabr.AudioSettings.getChannel('AudioMicChannel',obj.MicChannel);
        end

        function savePrefs(obj)
            setpref('MABR','AudioDevice',           obj.Device);
            setpref('MABR','AudioPlayerChannels',   obj.PlayerChannels);
            setpref('MABR','AudioRecorderChannels', obj.RecorderChannels);
            setpref('MABR','AudioTesting',          obj.Testing);
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
            if isfield(s,'PlayerChannels')
                obj.PlayerChannels = mabr.AudioSettings.coerceChannels(s.PlayerChannels,obj.PlayerChannels);
            end
            if isfield(s,'RecorderChannels')
                obj.RecorderChannels = mabr.AudioSettings.coerceChannels(s.RecorderChannels,obj.RecorderChannels);
            end
            if isfield(s,'Testing')
                obj.Testing = mabr.AudioSettings.coerceLogical(s.Testing,obj.Testing);
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
