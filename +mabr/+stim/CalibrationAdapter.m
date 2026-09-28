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
%   Latency
%   -------
%   An ASIO round trip (output buffer + input buffer + converters) is tens of
%   milliseconds, and audioPlayerRecorder returns the input sample-aligned to
%   the OUTPUT STREAM, not to the air. Left in, it lands in everything stimgen
%   reads as a time: a 10 cm speaker-to-mic path reads as a 25 ms conduction
%   delay, i.e. metres of air. So every play_and_record also sends a unit
%   pulse out the timing channel (PlayerChannels(2)) at the excitation's first
%   sample and records it back on RecorderChannels(2) -- the same loop-back
%   cable acquisition already requires -- and returns the mic record shifted
%   by the lag found there (alignToLoopback). Both inputs pass through the
%   same converter, so what is left is the acoustic path plus the speaker/mic
%   electronics. The record is also extended by MaxLatency so the shift has
%   something to read: without it the tail of every response fell off the end.
%   A rig with no loop-back (or a timing input shared with the mic) still
%   calibrates -- levels do not depend on latency -- but the record is
%   returned uncompensated and says so once. LastLatency holds the lag.
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

        % Device round-trip latency, in samples, found on the timing loop-back
        % by the last play_and_record (NaN: not measured / not compensated).
        LastLatency (1,1) double = NaN

        % Whether the missing-loop-back warning has been given (once per adapter).
        LatencyWarned (1,1) logical = false
    end

    properties
        % Remove the device round-trip latency measured on the timing
        % loop-back from every record (see Latency above). Off returns the
        % record aligned to the output stream, converter latency included.
        CompensateLatency (1,1) logical = true

        % Largest round-trip latency the loop-back is searched for, in
        % seconds; also how much longer than the excitation every record runs.
        MaxLatency (1,1) double {mustBePositive,mustBeFinite} = 0.1
    end

    properties (Constant)
        LoopbackPulse = 1e-3    % s, width of the timing pulse sent per record
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

            cfg  = obj.Config;
            fs   = cfg.DACSampleRate;
            loop = obj.CompensateLatency && obj.hasLoopback();

            % The loop-back needs room to find the lag in, and the mic record
            % needs the same room to be shifted into: a response arriving
            % L samples late ends L samples after the excitation does.
            if loop, nTail = round(obj.MaxLatency*fs); else, nTail = 0; end

            % Pad to a whole number of frames so the last partial frame does
            % not have to be special-cased; trimmed off the result below.
            fl   = cfg.frameLength;
            nPad = ceil((n + nTail)/fl)*fl;
            play = zeros(nPad,1 + loop);
            play(1:n,1) = x;
            outMap = obj.Audio.PlayerChannels(1);
            inMap  = obj.Audio.MicChannel;
            if loop
                % The pulse starts on the excitation's first sample, so its
                % recovered onset minus one IS the lag to remove.
                play(1:max(round(obj.LoopbackPulse*fs),1),2) = 1;
                outMap = obj.Audio.PlayerChannels;
                inMap  = [obj.Audio.MicChannel obj.Audio.RecorderChannels(2)];
            end

            [recPad,nUnder,nOver] = obj.stream(play,fs,outMap,inMap);

            % Dropouts corrupt a measurement silently -- the recording still
            % has the right length, just not the right samples -- so they are
            % reported rather than swallowed.
            if nUnder > 0 || nOver > 0
                mabr.log.vprintf(0,1,['CalibrationAdapter: %d underrun(s), %d ' ...
                    'overrun(s) during a %.2f s measurement -- treat the result ' ...
                    'as suspect.'],nUnder,nOver,n/fs);
            end

            obj.LastLatency = NaN;
            mic = recPad(1:n,1);
            if loop
                [aligned,lag] = mabr.stim.CalibrationAdapter.alignToLoopback( ...
                    recPad(:,1),recPad(:,2),n);
                if isnan(lag)
                    obj.warnLatency(sprintf(['no timing pulse came back on input ' ...
                        '%d within %.0f ms'],obj.Audio.RecorderChannels(2), ...
                        obj.MaxLatency*1e3));
                else
                    mic = aligned;
                    obj.LastLatency = lag;
                    mabr.log.vprintf(2,['CalibrationAdapter: removed %d samples ' ...
                        '(%.3f ms) of device round-trip latency.'],lag,lag/fs*1e3);
                end
            elseif obj.CompensateLatency
                obj.warnLatency(sprintf(['the timing loop-back is not usable ' ...
                    '(player channels [%s], timing input %d, mic input %d)'], ...
                    num2str(obj.Audio.PlayerChannels),obj.Audio.RecorderChannels(2), ...
                    obj.Audio.MicChannel));
            end

            % stimgen's contract is a (1,:) double, matching the (1,:) it
            % hands in -- so transpose rather than return the column shape
            % MABR uses everywhere else.
            rec = mic.';
        end

        function tf = hasLoopback(obj)
            % The timing loop-back can run beside the calibration: distinct
            % outputs for the speaker and the pulse, and a timing input that
            % is not also the one the microphone is patched to.
            a  = obj.Audio;
            tf = a.PlayerChannels(1) ~= a.PlayerChannels(2) && ...
                 a.RecorderChannels(2) ~= a.MicChannel;
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

    methods (Static)
        function [mic,lag] = alignToLoopback(mic,timing,n,threshold)
            % [mic,lag] = alignToLoopback(mic,timing,n) shifts a mic record
            % by the device round-trip latency read off the timing loop-back
            % recorded beside it, and returns its first n samples.
            %
            % timing holds the loop-back of a unit pulse that started on
            % output sample 1, so its first rising edge sits at lag+1. lag is
            % NaN -- and mic is returned unshifted -- when no edge is found,
            % or when one is but the record is too short to shift n samples.
            if nargin < 4, threshold = []; end
            mic    = mic(:);
            onsets = mabr.metrics.find_timing_onsets(timing,[],threshold);
            lag    = NaN;
            if ~isempty(onsets) && onsets(1) - 1 + n <= numel(mic)
                lag = onsets(1) - 1;
            end
            if isnan(lag)
                mic = mic(1:min(n,end));
            else
                mic = mic(lag + (1:n));
            end
        end
    end

    methods (Access = protected)
        function [rec,nUnder,nOver] = stream(obj,play,fs,outMap,inMap)
            % Play the [nPad x numel(outMap)] matrix through the device a
            % frame at a time and return the [nPad x numel(inMap)] recording.
            % The one place the device is touched, so a test can stand a
            % simulated one in its place.
            args = {'SampleRate',fs,'BitDepth','32-bit float', ...
                    'PlayerChannelMapping',outMap,'RecorderChannelMapping',inMap};
            if ~isempty(obj.Audio.Device), args = [args,{'Device',obj.Audio.Device}]; end

            fl  = obj.Config.frameLength;
            apr = [];
            try
                apr = audioPlayerRecorder(args{:});

                assert(apr.SampleRate == fs, ...
                    'mabr:stim:CalibrationAdapter:sampleRate', ...
                    ['Device granted %g Hz, not the required %g Hz. Calibrating at ' ...
                     'a rate the stimuli are not rendered at would not describe ' ...
                     'them -- check the ASIO control panel.'], ...
                    apr.SampleRate,fs);

                rec = zeros(size(play,1),numel(inMap));
                nUnder = 0; nOver = 0;
                for k = 1:fl:size(play,1)
                    idx = k:k+fl-1;
                    [y,u,o] = apr(play(idx,:));
                    rec(idx,:) = y;
                    nUnder = nUnder + u;
                    nOver  = nOver  + o;
                end
            catch me
                obj.closeDevice(apr);
                rethrow(me);
            end
            obj.closeDevice(apr);
        end
    end

    methods (Access = private)
        function warnLatency(obj,why)
            % Once per adapter: every sweep of a calibration would repeat it.
            if obj.LatencyWarned, return; end
            obj.LatencyWarned = true;
            mabr.log.vprintf(0,1,['CalibrationAdapter: %s, so the device ' ...
                'round-trip latency (typically tens of ms) is NOT removed -- any ' ...
                'conduction delay measured now includes it. Levels are unaffected. ' ...
                'Check the timing loop-back cable (PlayerChannels(2) -> ' ...
                'RecorderChannels(2)) in Settings > Audio Device.'],why);
        end

        function closeDevice(~,apr)
            if isempty(apr), return; end
            try, release(apr); end %#ok<TRYNC>
            try, delete(apr);  end %#ok<TRYNC>
        end
    end
end
