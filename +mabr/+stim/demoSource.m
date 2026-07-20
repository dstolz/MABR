function source = demoSource(cfg,opts)
% mabr.stim.demoSource  Built-in tone-pip StimulusSource for testing/demos.
%
%   source = mabr.stim.demoSource(cfg) returns a mabr.stim.PrecomputedSource
%   with a small Frequency x Level grid of gated tone-pip blocks. This is a
%   TESTING/DEMO convenience only: MABR does not generate or calibrate stimuli
%   in production (that is the external package's job) — this simply lets the
%   engine, GUI, and verification scripts run end-to-end with no hardware and
%   no external dependency.
%
%   Options (name-value):
%       Frequencies  (kHz)  default [8 16]
%       Levels       (dB)   default [30 60]
%       NumSweeps           default 256
%       SweepRate    (Hz)   default 21.1
%       PipDuration  (s)    default 0.005
%
% Daniel Stolzberg (c) 2026

arguments
    cfg = mabr.Config
    opts.Frequencies (1,:) double = [8 16]
    opts.Levels      (1,:) double = [30 60]
    opts.NumSweeps   (1,1) double = 256
    opts.SweepRate   (1,1) double = 21.1
    opts.PipDuration (1,1) double = 0.005
end

Fs     = cfg.DACSampleRate;
period = round(Fs/opts.SweepRate);
nPip   = round(Fs*opts.PipDuration);

t   = (0:nPip-1)'/Fs;
win = window(@blackmanharris,nPip);

blocks = struct('samples',{},'SampleRate',{},'SweepOnsets',{},'Meta',{});
for f = opts.Frequencies
    pip0 = sin(2*pi*f*1000*t).*win;         % gated tone pip
    for L = opts.Levels
        amp = 10^((L-80)/20);               % arbitrary (uncalibrated) level->amplitude
        pip = single(amp*pip0);

        N = opts.NumSweeps*period;
        samples = zeros(N,1,'single');
        onsets  = (0:opts.NumSweeps-1)'*period + 1;
        for k = 1:opts.NumSweeps
            i0 = onsets(k);
            samples(i0:i0+nPip-1) = pip;
        end

        meta = struct();
        meta.Frequency = f;                 % kHz
        meta.Level     = L;                 % dB
        meta.Polarity  = 1;
        meta.NumSweeps = opts.NumSweeps;
        meta.informativeParams = {'Frequency','Level'};
        meta.Label = {sprintf('Frequency = %g kHz',f), sprintf('Level = %g dB',L)};

        blocks(end+1) = struct('samples',samples,'SampleRate',Fs, ...
            'SweepOnsets',onsets,'Meta',meta); %#ok<AGROW>
    end
end

source = mabr.stim.PrecomputedSource(blocks);
end
