function R = noise_summary(f,P,varargin)
% mabr.metrics.noise_summary  What an input spectrum says about noise, in volts.
%
%   R = mabr.metrics.noise_summary(f,P) reads a one-sided power spectral
%   density P (V^2/Hz) at the evenly spaced frequencies f (Hz, from 0) --
%   mabr.compute.SpectrumEstimator's output -- and reduces it to the handful
%   of numbers a noise hunt is conducted in. Every figure is an RMS voltage,
%   the square root of the power in the bins it names (sum(P)*df, Parseval),
%   so it reads directly against a microvolt-scale response.
%
%   Name-value options:
%       LineFrequency  mains, Hz (default 60; 50 in most of the world). 0
%                      turns the mains readout off.
%       Harmonics      how many multiples of it to report (default 10)
%       Band           [lo hi] Hz of the in-band figure (default [100 3000],
%                      where an ABR lives)
%       LineWidth      half-width, in bins, a line is summed over (default 3:
%                      a Hann-windowed tone occupies three bins when centred on
%                      one and spreads into its neighbours when not)
%       PeakRange      [lo hi] Hz the largest-peak search covers (default
%                      [10 Nyquist])
%       Prominence     how far above the local noise floor a bin must stand
%                      to count as a peak, as a power ratio (default 10 = 10 dB)
%
%   R fields:
%       Resolution  Hz between bins
%       TotalRMS    every bin but DC: the input's whole broadband noise
%       Band        the band actually covered (clipped to f)
%       BandRMS     the bins inside Band
%       Line        mains: .Frequency (fundamental), .Harmonic (1..n, those
%                   below the top bin), .At (Hz of each), .RMS (V of each),
%                   .Fundamental (= .RMS(1)), .Total (root-sum-square of all of
%                   them) -- or NaN/empty with LineFrequency 0
%       Peak        the largest line that is NOT a mains harmonic and stands
%                   Prominence above the local floor: .Frequency, .RMS, and
%                   .AboveFloor (dB). .Frequency is NaN when nothing does.
%
%   A line's figure is the power in the bins it occupies, the noise floor's
%   share included, so it never reads below what the floor alone puts there
%   -- a clean input shows its mains line at the floor, not at zero.
%
%   See also mabr.compute.SpectrumEstimator, mabr.ui.SpectrumViewer.
%
% Daniel Stolzberg (c) 2026

p = inputParser;
p.addParameter('LineFrequency',60,@(v) isnumeric(v) && isscalar(v) && v >= 0);
p.addParameter('Harmonics',10,@(v) isnumeric(v) && isscalar(v) && v >= 1);
p.addParameter('Band',[100 3000],@(v) isnumeric(v) && numel(v) == 2);
p.addParameter('LineWidth',3,@(v) isnumeric(v) && isscalar(v) && v >= 0);
p.addParameter('PeakRange',[10 Inf],@(v) isnumeric(v) && numel(v) == 2);
p.addParameter('Prominence',10,@(v) isnumeric(v) && isscalar(v) && v > 0);
p.parse(varargin{:});
o = p.Results;

f = double(f(:));
P = double(P(:));
nanLine = struct('Frequency',o.LineFrequency,'Harmonic',zeros(1,0),'At',zeros(1,0), ...
    'RMS',zeros(1,0),'Fundamental',NaN,'Total',NaN);
nanPeak = struct('Frequency',NaN,'RMS',NaN,'AboveFloor',NaN);
R = struct('Resolution',NaN,'TotalRMS',NaN,'Band',[NaN NaN],'BandRMS',NaN, ...
    'Line',nanLine,'Peak',nanPeak);
if numel(f) < 2 || numel(P) ~= numel(f), return; end

df = f(2) - f(1);
R.Resolution = df;
R.TotalRMS   = sqrt(sum(P(2:end))*df);

band = sort(o.Band(:)).';
band = [max(band(1),f(1)) min(band(2),f(end))];
R.Band = band;
in = f >= band(1) & f <= band(2);
R.BandRMS = sqrt(sum(P(in))*df);

% --- Mains ---------------------------------------------------------------
f0 = o.LineFrequency;
isMains = false(size(f));
if f0 > 0
    % Never so wide that neighbouring harmonics share a bin.
    hw = max(1,min(round(o.LineWidth),floor(0.45*f0/df)));
    k  = 1:floor(min(o.Harmonics,f(end)/f0));
    at = k*f0;
    r  = zeros(size(at));
    for i = 1:numel(at)
        r(i) = lineRMS(round(at(i)/df) + 1,hw);
    end
    R.Line = struct('Frequency',f0,'Harmonic',k,'At',at,'RMS',r, ...
        'Fundamental',firstOr(r,NaN),'Total',sqrt(sum(r.^2)));
    % Every multiple up to Nyquist is mains, reported or not, and none of
    % them is the "other" peak the search below is for.
    c = round((f0:f0:f(end))/df) + 1;
    for i = 1:numel(c)
        isMains(max(1,c(i)-hw):min(numel(f),c(i)+hw)) = true;
    end
end

% --- The largest other line ------------------------------------------------
lo = max(o.PeakRange(1),df);
hi = min(o.PeakRange(2),f(end));
cand = find(f >= lo & f <= hi & ~isMains);
if isempty(cand), return; end
% The floor a peak stands above is LOCAL: the input's noise is anything but
% flat (1/f below a few hundred Hz, the anti-alias roll-off at the top), and
% a line judged against the whole spectrum's median would be a slope.
% Only over the searched range (and half a window either side of it, so
% every candidate still gets a whole window): to Nyquist at 0.5 Hz is
% 192,000 bins, and the window refreshes once a second.
half   = 25;
span   = max(1,cand(1)-half):min(numel(P),cand(end)+half);
floorP = zeros(size(P));
floorP(span) = movmedian(P(span),2*half+1);
ratio  = P(cand)./max(floorP(cand),realmin);
qual   = cand(ratio >= o.Prominence);
if isempty(qual), return; end
% The biggest of the qualifying bins, not the most prominent: the question is
% what is putting the most voltage in, not what is sharpest.
[~,j] = max(P(qual));
kPk = qual(j);
hwPk = max(1,round(o.LineWidth));
R.Peak = struct('Frequency',f(kPk),'RMS',lineRMS(kPk,hwPk), ...
    'AboveFloor',10*log10(P(kPk)/max(floorP(kPk),realmin)));

    function v = lineRMS(centre,half)
        % RMS of the line centred on bin `centre`: the bins within `half`.
        if centre > numel(P), v = NaN; return; end
        v = sqrt(sum(P(max(1,centre-half):min(numel(P),centre+half)))*df);
    end
end

function v = firstOr(x,d)
if isempty(x), v = d; else, v = x(1); end
end
