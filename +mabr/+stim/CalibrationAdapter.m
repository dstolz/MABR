classdef CalibrationAdapter < stimgen.calibration.HwAdapter
% mabr.stim.CalibrationAdapter  Calibrate a MABR rig through stimgen.
%
%   adapter = mabr.stim.CalibrationAdapter(audio,cfg) satisfies stimgen's
%   hardware contract -- sample_rate() and play_and_record(signal) -- by
%   driving the SAME ASIO device and output channel the acquisition engine
%   plays through. Hand it to stimgen's calibration engine:
%
%       adapter = mabr.stim.CalibrationAdapter(app.Audio,app.Config);
%       eng     = stimgen.calibration.Engine(adapter);
%       stimgen.calibration.CalibrationGui(eng);
%
%   Why not stimgen's own WindowsSoundCardAdapter: it opens whatever Windows
%   offers by default. A calibration measured through a different device, at a
%   different rate, on a different output than the one that will present the
%   stimuli describes a signal chain the experiment never uses. The whole point
%   of calibrating is that the number is about THIS rig.
%
%   Two channels, two jobs
%   ----------------------
%   Playback goes out on AudioSettings.PlayerChannels(1) -- the signal channel,
%   the same one Schedule.renderSpec puts stimuli on. Recording comes in on
%   AudioSettings.MicChannel, which is deliberately NOT RecorderChannels(1):
%   during acquisition that input carries an electrode, during calibration it
%   carries a measurement microphone. They are different patchings of one
%   device, so they are different settings.
%
%   Rate
%   ----
%   sample_rate() reports the rig's DAC rate (mabr.AudioSettings.SampleRate,
%   via the Config built from it), and the device is opened at it.
%   This is not bookkeeping: mabr.stim.fromStimgen regenerates every stimulus
%   at the DAC rate, and stimgen's design_filter produces a rate-specific FIR
%   equalization, so a calibration measured at any other rate would be applied
%   to signals it does not describe.
%
%   Refuses rather than fights
%   --------------------------
%   Only one process can hold an ASIO device. The acquisition worker opens one
%   for the duration of a schedule, so this errors instead of racing it (see
%   assertUsable). It also refuses in Test Mode -- there the stimulus IS the
%   recorded input, so a "calibration" measured under it would be a number
%   about nothing.
%
%   See also mabr.AudioSettings, mabr.stim.fromStimgen, stimgen.calibration.Engine.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Audio  (1,1) mabr.AudioSettings
        Config

        % The acquisition controller to check before opening the device, when
        % there is one. Held rather than searched for: a calibration launched
        % from mabr.ui.App knows its own controller, and scanning every open
        % figure to rediscover it would be both fragile and a way to find
        % somebody else's.
        Controller

        % Whether the worker has already been asked to hand the device back
        % (see borrowDevice). One request per adapter, not one per measurement.
        DeviceBorrowed (1,1) logical = false
    end

    methods
        function obj = CalibrationAdapter(audio,cfg,controller)
            if nargin < 1 || isempty(audio), audio = mabr.AudioSettings.loadPrefs(); end
            if nargin < 2 || isempty(cfg),   cfg   = audio.config(); end
            % The two arguments can only disagree about one thing, and it is
            % the one that matters most here: which rate the measurement is
            % made at. The device setting wins, because that is the rate the
            % device will actually be opened at -- calibrating at a rate the
            % stimuli are not rendered at describes a chain the experiment
            % never uses, which is the whole reason this adapter exists rather
            % than stimgen measuring through its own default path.
            if cfg.DACSampleRate ~= audio.SampleRate
                mabr.log.vprintf(1,['CalibrationAdapter: config says %g Hz, device ' ...
                    'setting says %g Hz -- measuring at the device rate.'], ...
                    cfg.DACSampleRate,audio.SampleRate);
                cfg = audio.config();
            end
            obj.Audio  = audio;
            obj.Config = cfg;
            if nargin >= 3, obj.Controller = controller; end
        end

        function fs = sample_rate(obj)
            fs = obj.Config.DACSampleRate;
        end

        function rec = play_and_record(obj,signal)
            % Play signal on the rig's output channel and return what the
            % microphone heard, sample-aligned and the same length.
            obj.assertUsable();

            x = double(signal(:));
            n = numel(x);
            assert(n > 0,'mabr:stim:CalibrationAdapter:emptySignal', ...
                'Nothing to play: the excitation signal is empty.');

            cfg = obj.Config;
            fl  = cfg.frameLength;
            out = obj.Audio.PlayerChannels(1);
            in  = obj.Audio.MicChannel;

            % Pad to a whole number of frames so the last partial frame does
            % not have to be special-cased; trimmed off the result below.
            nPad = ceil(n/fl)*fl;
            xPad = zeros(nPad,1);
            xPad(1:n) = x;

            args = {'SampleRate',cfg.DACSampleRate,'BitDepth','32-bit float', ...
                    'PlayerChannelMapping',out,'RecorderChannelMapping',in};
            if ~isempty(obj.Audio.Device), args = [args,{'Device',obj.Audio.Device}]; end

            apr = [];
            try
                apr = audioPlayerRecorder(args{:});

                assert(apr.SampleRate == cfg.DACSampleRate, ...
                    'mabr:stim:CalibrationAdapter:sampleRate', ...
                    ['Device granted %g Hz, not the required %g Hz. Calibrating at ' ...
                     'a rate the stimuli are not rendered at would not describe ' ...
                     'them -- check the ASIO control panel.'], ...
                    apr.SampleRate,cfg.DACSampleRate);

                recPad = zeros(nPad,1);
                nUnder = 0; nOver = 0;
                for k = 1:fl:nPad
                    idx = k:k+fl-1;
                    [y,u,o] = apr(xPad(idx));
                    recPad(idx) = y(:,1);
                    nUnder = nUnder + u;
                    nOver  = nOver  + o;
                end

                % Dropouts corrupt a measurement silently -- the recording
                % still has the right length, just not the right samples --
                % so they are reported rather than swallowed.
                if nUnder > 0 || nOver > 0
                    mabr.log.vprintf(0,1,['CalibrationAdapter: %d underrun(s), %d ' ...
                        'overrun(s) during a %.2f s measurement -- treat the result ' ...
                        'as suspect.'],nUnder,nOver,n/cfg.DACSampleRate);
                end

                % stimgen's contract is a (1,:) double, matching the (1,:) it
                % hands in -- so transpose rather than return the column shape
                % MABR uses everywhere else.
                rec = recPad(1:n).';
            catch me
                obj.closeDevice(apr);
                rethrow(me);
            end
            obj.closeDevice(apr);
        end

        function assertUsable(obj)
            % Everything that must be true before a device is opened.
            assert(~obj.Audio.Testing,'mabr:stim:CalibrationAdapter:testingMode', ...
                ['Test Mode is on, so no device would be opened and the ' ...
                 '"measurement" would be the excitation signal copied straight ' ...
                 'back into the acquisition buffer. Turn it off in ' ...
                 'Settings > Audio Device before calibrating.']);

            assert(~obj.engineHoldsDevice(),'mabr:stim:CalibrationAdapter:deviceBusy', ...
                ['The acquisition engine currently holds the audio device. Stop the ' ...
                 'running schedule before calibrating -- only one of them can own ' ...
                 'the ASIO device at a time.']);

            obj.borrowDevice();
        end

        function borrowDevice(obj)
            % Take the ASIO device off the idle worker, once per adapter.
            %
            % The worker opens its audioPlayerRecorder on the first prep and
            % keeps it until kill -- that is what keeps block-to-block latency
            % down -- so "idle" does NOT mean "device free". Without this, the
            % first calibration measurement after any acquisition would fail to
            % open the device and the only remedy would be restarting MABR.
            % The worker reopens on its next prep, so nothing is lost but the
            % first block's device-open latency.
            if obj.DeviceBorrowed, return; end
            obj.DeviceBorrowed = true;      % set first: one attempt, not one per sweep

            c = obj.Controller;
            if isempty(c) || ~isvalid(c) || isempty(c.Engine) || ~isvalid(c.Engine)
                return
            end
            c.Engine.releaseDevice();
            mabr.log.vprintf(1,'CalibrationAdapter: asked the worker to release the audio device.');
        end

        function tf = engineHoldsDevice(obj)
            % True when the acquisition worker is streaming. The worker owns
            % its audioPlayerRecorder for as long as a schedule runs, and a
            % second open on the same ASIO device fails -- or worse,
            % half-succeeds -- so the calibration path asks before it opens.
            tf = false;
            c = obj.Controller;
            if isempty(c) || ~isvalid(c), return; end
            tf = c.State ~= mabr.ui.ProgState.Idle;
        end
    end

    methods (Access = private)
        function closeDevice(~,apr)
            if isempty(apr), return; end
            try, release(apr); end %#ok<TRYNC>
            try, delete(apr);  end %#ok<TRYNC>
        end
    end
end
