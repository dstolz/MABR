function txt = backgroundText(R)
% mabr.stim.backgroundText  A background record in a few words.
%
%   txt = mabr.stim.backgroundText(R) for R from mabr.stim.backgroundRecord
%   (or one element of mabr.stim.StimulusSet.Backgrounds, which carries the
%   same descriptive fields):
%
%       'none'
%       'noise 4-16 kHz, 50 dB SPL'
%       'tone 8 kHz, 60 dB SPL'
%       'noise 0.5-20 kHz, 50 dB (uncalibrated)'
%
%   The one wording the bank label, the Presentation panel, the stimulus
%   viewer and the log lines share.
%
% Daniel Stolzberg (c) 2026

if isempty(R) || ~isstruct(R) || ~isfield(R,'Type') || strcmpi(R.Type,'none')
    txt = 'none';
    return
end

kind = '';
if isfield(R,'Kind'), kind = char(string(R.Kind)); end
what = lower(char(string(R.Type)));

if strcmp(kind,'tone') || (isfield(R,'Frequency') && isfinite(R.Frequency))
    txt = sprintf('%s %s kHz',what,num(R.Frequency/1000));
elseif isfield(R,'HighPass') && isfinite(R.HighPass) && isfinite(R.LowPass)
    txt = sprintf('%s %s-%s kHz',what,num(R.HighPass/1000),num(R.LowPass/1000));
else
    txt = what;
end

if isfield(R,'Level') && isfinite(R.Level)
    if isfield(R,'Calibrated') && R.Calibrated
        txt = sprintf('%s, %s dB SPL',txt,num(R.Level));
    else
        txt = sprintf('%s, %s dB (uncalibrated)',txt,num(R.Level));
    end
elseif isfield(R,'Calibrated') && ~R.Calibrated
    txt = [txt ' (uncalibrated)'];
end
end

function s = num(v)
s = sprintf('%.4g',v);
end
