function R = backgroundRecord(B,varargin)
% mabr.stim.backgroundRecord  What a record says about a run's ongoing background.
%
%   R = mabr.stim.backgroundRecord()                 no background
%   R = mabr.stim.backgroundRecord(B)                from one element of
%                                                    mabr.stim.StimulusSet.Backgrounds
%   R = mabr.stim.backgroundRecord(B,Name,Value,...) with the presentation
%                                                    half filled in
%
%   One plain struct with ONE field set, whatever the run played -- so the
%   field a file was written with never depends on whether there was a
%   background, and a reader need not guess what a missing field means. It
%   holds no waveform: a background is identified by its Key, its settings and
%   its seed, which is what stimgen regenerates it from.
%
%       Type          'none', else the source's own name for it ('Noise', 'Tone')
%       Kind          '' | 'loop' | 'tone' -- how it was rendered
%       Key           text equal for two runs that played the same background
%       Level         dB (SPL when Calibrated), NaN where the source gave none
%       HighPass, LowPass   Hz, the noise band; NaN otherwise
%       Frequency     Hz of a tone; NaN otherwise
%       LoopDuration  s, the period the loop repeats with; NaN for a tone
%       Seed          seed of the noise; NaN where unknown
%       Calibrated    the level is a measured dB SPL
%       LevelScale    linear gain an UNcalibrated background was given to put
%                     it on the bank's relative level scale (1 otherwise)
%       Rms, Peak     of the background as played, in converter units
%   Presentation (Name,Value; NaN until mabr.stim.Schedule fills them in):
%       LeadIn        s of background before the run's first presentation
%       Ramp          s of fade at each end of the run
%       LoopOffset    sample of the background the run's first sample played
%
%   See also mabr.stim.backgroundText, mabr.stim.Schedule.renderSpec,
%   mabr.data.io.buildStruct.
%
% Daniel Stolzberg (c) 2026

R = struct('Type','none','Kind','','Key','', ...
    'Level',NaN,'HighPass',NaN,'LowPass',NaN,'Frequency',NaN, ...
    'LoopDuration',NaN,'Seed',NaN,'Calibrated',false,'LevelScale',1, ...
    'Rms',NaN,'Peak',NaN,'LeadIn',NaN,'Ramp',NaN,'LoopOffset',NaN);

if nargin < 1 || isempty(B), return; end

R.Type         = char(string(B.Type));
R.Kind         = char(string(B.Kind));
R.Key          = char(string(B.Key));
R.Level        = double(B.Level);
R.HighPass     = double(B.HighPass);
R.LowPass      = double(B.LowPass);
R.LoopDuration = double(B.LoopDuration);
R.Seed         = double(B.Seed);
R.Calibrated   = logical(B.Calibrated);
R.LevelScale   = double(B.LevelScale);

switch R.Kind
    case 'tone'
        R.Frequency = double(B.Frequency);
        R.Peak      = double(B.Amplitude);
        R.Rms       = R.Peak/sqrt(2);
    otherwise
        x      = double(B.signal(:));
        R.Peak = max(abs(x));
        R.Rms  = sqrt(mean(x.^2));
end

for k = 1:2:numel(varargin)
    name = char(string(varargin{k}));
    assert(any(strcmp(name,{'LeadIn','Ramp','LoopOffset'})), ...
        'mabr:stim:backgroundRecord:field', ...
        '"%s" is not a presentation field of a background record.',name);
    R.(name) = double(varargin{k+1});
end
end
