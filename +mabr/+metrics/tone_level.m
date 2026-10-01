function r = tone_level(x,fs,f0,minDetect)
% mabr.metrics.tone_level  Amplitude of a tone of known frequency in a record.
%
%   r = tone_level(x,fs,f0) fits x = a*sin(2*pi*f0*t) + b*cos(2*pi*f0*t) + c
%   by least squares and returns what an input calibration needs to know
%   about the tone in it:
%
%       Amplitude  sqrt(a^2+b^2) -- the tone's PEAK, in x's units
%       RMS        Amplitude/sqrt(2)
%       Peak       max(abs(x)) -- the record's own peak, tone or not
%       Clipped    Peak >= 0.99, i.e. the converter was at (or next to) full
%                  scale somewhere, and Amplitude cannot be trusted
%       SNR        dB, the fitted tone's power over everything else's (hum,
%                  noise, the tone's own harmonics) -- how clean the record
%                  is, broadband
%       Detection  dB, the fitted amplitude against what the residual alone
%                  would give a fit at f0 (A^2*n/(4*var), about 0 dB for no
%                  tone at all) -- whether there is a tone, narrowband
%       Present    Detection >= minDetect (default 20 dB): there is a tone
%                  here worth quoting a level for. Judged narrowband, not by
%                  SNR, so a tone under heavy hum is still found: the hum is
%                  not at f0 and does not move the fit
%       Offset     c
%
%   The frequency is given rather than searched for because the case this is
%   for plays the tone itself: the DAC and the ADC run off one clock, so f0 is
%   exact, and a fit at exactly f0 rejects mains hum and its harmonics outright
%   rather than letting them into the level the way a broadband RMS would.
%   Fit over whole cycles where possible (the caller's job); the error from a
%   partial cycle is small either way, since sin and cos are both in the fit.
%
%   A pure function: nothing is recorded, played, or opened.
%
%   See also mabr.acq.InputCalibrator.
%
% Daniel Stolzberg (c) 2026

if nargin < 4 || isempty(minDetect), minDetect = 20; end

x = double(x(:));
n = numel(x);
r = struct('Amplitude',NaN,'RMS',NaN,'Peak',NaN,'Clipped',false, ...
           'SNR',-Inf,'Detection',-Inf,'Present',false,'Offset',NaN);
if n < 3, return; end

t = (0:n-1)'/fs;
w = 2*pi*f0*t;
M = [sin(w) cos(w) ones(n,1)];
p = M\x;

r.Amplitude = hypot(p(1),p(2));
r.RMS       = r.Amplitude/sqrt(2);
r.Offset    = p(3);
r.Peak      = max(abs(x));
r.Clipped   = r.Peak >= 0.99;

res  = x - M*p;
pRes = mean(res.^2);
pTone = r.Amplitude^2/2;
if pRes > 0
    r.SNR       = 10*log10(pTone/pRes);
    r.Detection = 10*log10(r.Amplitude^2*n/(4*pRes));
elseif pTone > 0
    r.SNR       = Inf;          % a noiseless record (a simulated device)
    r.Detection = Inf;
end
r.Present = r.Detection >= minDetect;
end
