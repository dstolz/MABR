classdef InputCalibrator < handle
% mabr.acq.InputCalibrator  Calibrate the recorder's signal input in volts.
%
%   cal = mabr.acq.InputCalibrator(audio,cfg,controller) measures
%   mabr.AudioSettings.InputFullScale -- the volts at RecorderChannels(1) the
%   converter reports as 1.0 -- wherever the interface's input gain knob
%   happens to sit. Without it MABR takes one converter unit to be one volt,
%   and every voltage it shows, judges, or saves is off by the knob.
%
%   Two steps, only the first of which needs a meter:
%
%     1. ONCE PER RIG, the output. playForMeter plays a steady tone out of
%        PlayerChannels(1) at a known digital level; the operator reads it
%        with a true-RMS multimeter, and outputFullScale turns the reading
%        into OutputFullScale (volts peak at the output for 1.0). The output
%        has no knob in its path -- the acoustic calibration already relies
%        on that -- so it does not drift the way the input does.
%
%     2. WHENEVER THE INPUT KNOB MOVES, the input. With PlayerChannels(1)
%        patched to RecorderChannels(1) by a plain cable, measureInput plays
%        the same tone, auto-ranged to sit well inside the input's range, and
%        fits it (mabr.metrics.tone_level). The DAC is linear to far better
%        than any meter is accurate, so the tone can be played at whatever
%        level the knob needs -- -60 dBFS for a knob near the top -- and
%        still be referred to the meter reading taken at -10 dBFS:
%
%           InputFullScale = OutputFullScale * 10^(level/20) / amplitude_in
%
%   measureLoopGain is that measurement without the reference (converter
%   units in per unit out), so the loop-back can be checked on a rig whose
%   output has not been read off a meter yet.
%
%   Like mabr.stim.CalibrationAdapter it opens the device itself, on this
%   process, and refuses rather than fights: not in Test Mode (no device),
%   not under stimulation only (no input), and not while the acquisition
%   worker is running a schedule or the input monitor. The worker keeps its
%   device open while idle, so the first measurement asks it to let go
%   (Engine.releaseDevice) and retries the open while it does; the next run
%   reopens it. That logic is repeated here rather than shared with the
%   adapter because the adapter is a stimgen type, and stimgen is optional.
%
%   See also mabr.AudioSettings, mabr.ui.InputCalibrationDialog,
%   mabr.metrics.tone_level.
%
% Daniel Stolzberg (c) 2026

    properties
        % The settings measured through: device, channels, and -- for
        % measureInput -- OutputFullScale. Settable, so a dialog can hand one
        % calibrator the output reference the moment it is entered.
        Audio (1,1) mabr.AudioSettings
    end

    properties (SetAccess = private)
        Config
        Controller
        % The worker has been asked to hand the device back (once per object).
        DeviceBorrowed (1,1) logical = false
        % What the last measureLoopGain/measureInput found (see measureLoopGain).
        LastReport = []
    end

    properties
        Frequency      (1,1) double {mustBePositive} = 400   % Hz, both steps
        ProbeLevel     (1,1) double = -40    % dBFS out, the first probe
        ProbeSeconds   (1,1) double {mustBePositive} = 0.5
        MeasureSeconds (1,1) double {mustBePositive} = 2
        TargetPeak     (1,1) double {mustBePositive} = 0.25  % FS in, what autorange aims at
        MinLevel       (1,1) double = -90    % dBFS out
        MaxLevel       (1,1) double = -3     % dBFS out
        LeadSeconds    (1,1) double = 0.25   % silence the stream starts on
        TailSeconds    (1,1) double = 0.1    % recorded past the tone (round trip)
        FadeSeconds    (1,1) double = 0.01
        % Constructor of the device (TESTS ONLY; [] = audioPlayerRecorder).
        DeviceFactory  = []
        % How long an open is retried while the worker lets the device go.
        OpenRetrySeconds (1,1) double = 3
    end

    methods
        function obj = InputCalibrator(audio,cfg,controller)
            if nargin < 1 || isempty(audio), audio = mabr.AudioSettings.loadPrefs(); end
            if nargin < 2 || isempty(cfg),   cfg   = audio.config(); end
            obj.Audio  = audio;
            obj.Config = cfg;
            if nargin >= 3, obj.Controller = controller; end
        end

        % --- Step 1: the output, against a meter --------------------------
        function played = playForMeter(obj,levelDb,seconds,stopFcn)
            % Play a steady tone out of PlayerChannels(1) at levelDb dBFS for
            % seconds (or until stopFcn() returns true), for a multimeter to
            % read. Returns the seconds actually played. The input is opened
            % (the device is full-duplex) and ignored.
            if nargin < 3 || isempty(seconds), seconds = 20; end
            if nargin < 4, stopFcn = []; end
            obj.assertUsable();
            a   = obj.levelToAmp(levelDb);
            fs  = obj.Config.DACSampleRate;
            fl  = obj.Config.frameLength;
            n   = round(seconds*fs);
            nF  = max(1,round(obj.FadeSeconds*fs));
            w   = 2*pi*obj.Frequency/fs;
            dev = obj.openDevice();
            cleanup = onCleanup(@() obj.closeDevice(dev));
            k0 = 0;
            % Ask about stopping every ~0.1 s, not every frame: stopFcn is
            % expected to flush the event queue, which is not free.
            every = max(1,round(0.1*fs/fl));
            nFr = 0;
            stopped = false;
            while k0 < n
                idx = (k0:k0+fl-1)';
                env = max(0,min(1,min(idx+1,n-idx)/nF));
                dev(a*env.*sin(w*idx));
                k0 = k0 + fl;
                nFr = nFr + 1;
                if ~stopped && ~isempty(stopFcn) && mod(nFr,every) == 0 && stopFcn()
                    % Fade out from here rather than cut the tone off.
                    n = min(n,k0 + nF);
                    stopped = true;
                end
            end
            played = n/fs;
        end

        % --- Step 2: the input, through a loop-back cable -----------------
        function [ratio,rep] = measureLoopGain(obj)
            % Converter units recorded on RecorderChannels(1) per unit
            % played on PlayerChannels(1), measured with the tone
            % auto-ranged to peak near TargetPeak at the input. rep:
            %   Level       dBFS out the measurement was played at
            %   Amplitude   FS peak recorded
            %   InputDbfs   20*log10(Amplitude)
            %   SNR / Detection   dB, broadband / at the tone
            %               (mabr.metrics.tone_level)
            %   Underruns / Overruns   reported by the device
            %   Probes      the tone_level of each probe, in order
            %   Warnings    cellstr: things that make the number suspect
            obj.assertUsable();
            probes = struct('Level',{},'Fit',{});
            L = obj.ProbeLevel;
            found = false;
            for attempt = 1:6
                [r,~,~] = obj.playTone(L,obj.ProbeSeconds);
                probes(end+1) = struct('Level',L,'Fit',r); %#ok<AGROW>
                if r.Clipped
                    % Too hot for this knob: step down and try again.
                    if L <= obj.MinLevel
                        error('mabr:acq:InputCalibrator:clipped', ...
                            ['Input %d clips even at %g dBFS out -- turn its gain ' ...
                             'knob down, or check nothing else feeds it.'], ...
                            obj.Audio.RecorderChannels(1),L);
                    end
                    L = max(obj.MinLevel,L - 20);
                elseif ~r.Present
                    % Nothing came back. Try once more, much louder, before
                    % blaming the cable (a knob at its minimum can bury
                    % -40 dBFS in the converter's own noise).
                    if L >= obj.MaxLevel - 7
                        break
                    end
                    L = obj.MaxLevel - 7;
                else
                    found = true;
                    break
                end
            end
            if ~found
                error('mabr:acq:InputCalibrator:noTone', ...
                    ['No %g Hz tone came back on input %d. Patch output %d to ' ...
                     'input %d with a plain cable (speaker and electrode ' ...
                     'amplifiers unplugged) and try again.'], ...
                    obj.Frequency,obj.Audio.RecorderChannels(1), ...
                    obj.Audio.PlayerChannels(1),obj.Audio.RecorderChannels(1));
            end

            % The loop is linear, so one probe says where to play the tone for
            % it to land at TargetPeak.
            ratio0 = r.Amplitude/obj.levelToAmp(L);
            L = 20*log10(obj.TargetPeak/ratio0);
            L = min(obj.MaxLevel,max(obj.MinLevel,L));
            [r,nU,nO] = obj.playTone(L,obj.MeasureSeconds);
            if r.Clipped || ~r.Present
                error('mabr:acq:InputCalibrator:unstable', ...
                    ['The tone %s at %.1f dBFS out after a clean probe -- the ' ...
                     'input is not behaving linearly (was the knob moved?). ' ...
                     'Measure again.'],ternary(r.Clipped,'clipped','vanished'),L);
            end
            ratio = r.Amplitude/obj.levelToAmp(L);

            % Only what makes the NUMBER suspect is a warning. How precisely
            % the level is known depends on the tone against the noise at its
            % own frequency (Detection): the fit's relative error is about
            % 10^(-Detection/20)/sqrt(2).
            warn = {};
            if r.Detection < 40
                warn{end+1} = sprintf(['The tone is only %.0f dB clear of the noise ' ...
                    'at %g Hz, so the result is uncertain by about %.1f%% -- check ' ...
                    'the cable.'],r.Detection,obj.Frequency, ...
                    100*10^(-r.Detection/20)/sqrt(2));
            end
            if 20*log10(r.Amplitude) < 20*log10(obj.TargetPeak) - 12
                warn{end+1} = sprintf(['The tone reached only %.0f dBFS at the input ' ...
                    'even at %g dBFS out.'],20*log10(r.Amplitude),L);
            end
            if nU > 0 || nO > 0
                warn{end+1} = sprintf(['The device reported %d underrun and %d ' ...
                    'overrun samples -- measure again.'],nU,nO);
            end
            % Deliberately NOT judged by the broadband SNR: at 192 kHz a
            % converter's shaped noise above 50 kHz can dwarf everything in
            % band (the reference rig: -44 dBFS at 72-96 kHz, -100 dBFS at
            % 0.1-3 kHz), which gives a 26 dB SNR on a tone whose level still
            % repeats to 0.001 dB. Detection is the measure of the number.
            rep = struct('Level',L,'Amplitude',r.Amplitude, ...
                'InputDbfs',20*log10(r.Amplitude),'SNR',r.SNR, ...
                'Detection',r.Detection, ...
                'Underruns',nU,'Overruns',nO,'Probes',probes, ...
                'Ratio',ratio,'InputFullScale',NaN,'Warnings',{warn});
            obj.LastReport = rep;
        end

        function [ifs,rep] = measureInput(obj)
            % InputFullScale (volts peak at RecorderChannels(1) for 1.0),
            % measured through the loop-back against OutputFullScale. See
            % measureLoopGain for rep; rep.InputFullScale is ifs.
            assert(obj.Audio.hasOutputReference(), ...
                'mabr:acq:InputCalibrator:noReference', ...
                ['The output has not been measured yet -- play the tone for ' ...
                 'the meter and enter its reading first.']);
            [ratio,rep] = obj.measureLoopGain();
            ifs = obj.Audio.OutputFullScale/ratio;
            rep.InputFullScale = ifs;
            obj.LastReport = rep;
        end

        % --- Refusals -----------------------------------------------------
        function assertUsable(obj)
            a = obj.Audio;
            assert(~a.Testing,'mabr:acq:InputCalibrator:testingMode', ...
                ['Test Mode is on, so there is no device to calibrate. Turn it ' ...
                 'off in Settings > Audio Device first.']);
            assert(~a.isStimulationOnly(),'mabr:acq:InputCalibrator:stimOnly', ...
                ['Stimulation only records nothing, so there is no input to ' ...
                 'calibrate. Turn it off in Settings > Audio Device first.']);
            assert(~obj.engineHoldsDevice(),'mabr:acq:InputCalibrator:deviceBusy', ...
                ['The acquisition engine holds the audio device. Stop the running ' ...
                 'schedule (or the input monitor) first.']);
            obj.borrowDevice();
        end

        function tf = engineHoldsDevice(obj)
            % A schedule in flight, or the input monitor streaming.
            tf = false;
            c = obj.Controller;
            if isempty(c) || ~isvalid(c), return; end
            tf = c.State ~= mabr.ui.ProgState.Idle;
            if ~tf && isprop(c,'Monitoring'), tf = c.Monitoring; end
        end
    end

    methods (Static)
        function v = outputFullScale(vrms,levelDb)
            % Volts peak at the output for 1.0, from a true-RMS reading vrms
            % of a sine played at levelDb dBFS.
            v = vrms*sqrt(2)/10^(levelDb/20);
        end
    end

    methods (Access = private)
        function a = levelToAmp(~,levelDb)
            a = 10^(levelDb/20);
        end

        function [r,nU,nO] = playTone(obj,levelDb,seconds)
            % Play a faded tone of `seconds` between LeadSeconds of silence and
            % TailSeconds more, record the input, and fit the middle half of
            % the tone -- clear of the fades and of the device round trip.
            fs  = obj.Config.DACSampleRate;
            fl  = obj.Config.frameLength;
            nL  = round(obj.LeadSeconds*fs);
            nT  = round(seconds*fs);
            nX  = round(obj.TailSeconds*fs);
            nF  = max(1,round(obj.FadeSeconds*fs));
            N   = ceil((nL+nT+nX)/fl)*fl;
            k   = (0:nT-1)';
            env = min(1,min(k+1,nT-k)/nF);
            play = zeros(N,1);
            play(nL+(1:nT)) = obj.levelToAmp(levelDb)*env.*sin(2*pi*obj.Frequency*k/fs);

            dev = obj.openDevice();
            cleanup = onCleanup(@() obj.closeDevice(dev));
            rec = zeros(N,1);
            nU = 0; nO = 0;
            for i0 = 1:fl:N
                idx = i0:i0+fl-1;
                [y,u,o] = dev(play(idx));
                rec(idx) = y(:,1);
                nU = nU + u; nO = nO + o;
            end

            % The middle half, trimmed to whole cycles.
            i1 = nL + round(nT/4) + 1;
            n  = round(nT/2);
            cyc = floor(n*obj.Frequency/fs);
            if cyc >= 1, n = round(cyc*fs/obj.Frequency); end
            r = mabr.metrics.tone_level(rec(i1:i1+n-1),fs,obj.Frequency);
        end

        function dev = openDevice(obj)
            a = obj.Audio;
            args = {'SampleRate',obj.Config.DACSampleRate,'BitDepth','32-bit float', ...
                    'PlayerChannelMapping',a.PlayerChannels(1), ...
                    'RecorderChannelMapping',a.RecorderChannels(1)};
            if ~isempty(a.Device), args = [args,{'Device',a.Device}]; end
            ctor = obj.DeviceFactory;
            if isempty(ctor), ctor = @audioPlayerRecorder; end

            % The worker lets go of the device asynchronously (Cmd.Release is
            % acted on at its next poll), so an open straight after asking can
            % still find it held. Retry briefly rather than fail the first
            % measurement of every session.
            t0 = tic;
            while true
                try
                    dev = ctor(args{:});
                    % A System object opens on its first call; make that call
                    % here, on a frame of silence, so a held device fails
                    % inside the retry rather than mid-tone.
                    dev(zeros(obj.Config.frameLength,1));
                    break
                catch me
                    try, release(dev); end %#ok<TRYNC>
                    if toc(t0) > obj.OpenRetrySeconds, rethrow(me); end
                    pause(0.2);
                end
            end
            if isprop(dev,'SampleRate') && dev.SampleRate ~= obj.Config.DACSampleRate
                obj.closeDevice(dev);
                error('mabr:acq:InputCalibrator:sampleRate', ...
                    'Device granted %g Hz, not the %g Hz required.', ...
                    dev.SampleRate,obj.Config.DACSampleRate);
            end
        end

        function closeDevice(~,dev)
            if isempty(dev), return; end
            try, release(dev); end %#ok<TRYNC>
            try, delete(dev);  end %#ok<TRYNC>
        end

        function borrowDevice(obj)
            % Take the device off the idle worker, once per object (see
            % mabr.stim.CalibrationAdapter.borrowDevice for why it is held).
            if obj.DeviceBorrowed, return; end
            obj.DeviceBorrowed = true;
            c = obj.Controller;
            if isempty(c) || ~isvalid(c) || ~isprop(c,'Engine') || ...
                    isempty(c.Engine) || ~isvalid(c.Engine) || ...
                    ~ismethod(c.Engine,'releaseDevice')
                return
            end
            c.Engine.releaseDevice();
            mabr.log.vprintf(1,'InputCalibrator: asked the worker to release the audio device.');
        end
    end
end

function s = ternary(tf,a,b)
if tf, s = a; else, s = b; end
end
