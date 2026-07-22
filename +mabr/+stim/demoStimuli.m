function set = demoStimuli(cfg,opts)
% mabr.stim.demoStimuli  Built-in tone-pip stimulus bank for testing/demos.
%
%   set = mabr.stim.demoStimuli(cfg) returns a mabr.stim.StimulusSet holding a
%   small Frequency x Level grid of gated tone pips -- one SINGLE pip per
%   entry, in the shape the external stimulus package is expected to supply.
%   Repetition, spacing, and ordering are not its business: those come from
%   mabr.stim.Schedule.
%
%   This is a TESTING/DEMO convenience only. MABR does not generate or
%   calibrate stimuli in production (that is the external package's job) --
%   this simply lets the engine, GUI, and verification scripts run end-to-end
%   with no hardware and no external dependency.
%
%   Options (name-value):
%       Frequencies  (kHz)  default [8 16]
%       Levels       (dB)   default [30 60]
%       PipDuration  (s)    default 0.005
%       Repetitions         default 256, written onto each entry as the
%                           starting repetition count the GUI picks up
%
%   See also mabr.stim.StimulusSet, mabr.stim.Schedule.
%
% Daniel Stolzberg (c) 2026

arguments
    cfg = mabr.Config
    opts.Frequencies (1,:) double = [8 16]
    opts.Levels      (1,:) double = [30 60]
    opts.PipDuration (1,1) double = 0.005
    opts.Repetitions (1,1) double = 256
end

Fs   = cfg.DACSampleRate;
nPip = round(Fs*opts.PipDuration);

t   = (0:nPip-1)'/Fs;
win = window(@blackmanharris,nPip);

% Calibrated is stated rather than left absent: this bank KNOWS it is
% uncalibrated, and an absent field means "never said", which viewers must not
% read as either answer (see mabr.stim.StimulusSet.isCalibrated). Saying so is
% what turns the bank label amber.
stim = struct('signal',{},'ID',{},'SampleRate',{},'Repetitions',{}, ...
              'Frequency',{},'Level',{},'Polarity',{},'Calibrated',{});

for f = opts.Frequencies
    pip0 = sin(2*pi*f*1000*t).*win;         % gated tone pip
    for L = opts.Levels
        amp = 10^((L-80)/20);               % arbitrary (uncalibrated) level -> amplitude

        stim(end+1) = struct( ...
            'signal',      single(amp*pip0), ...
            'ID',          sprintf('%gkHz_%gdB',f,L), ...
            'SampleRate',  Fs, ...
            'Repetitions', opts.Repetitions, ...
            'Frequency',   f, ...           % kHz
            'Level',       L, ...           % dB
            'Polarity',    1, ...
            'Calibrated',  false); %#ok<AGROW>
    end
end

set = mabr.stim.StimulusSet(stim,cfg, ...
    struct('Kind','demo','Generated',datetime('now')));
end
