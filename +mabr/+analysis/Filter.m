classdef Filter
% mabr.analysis.Filter  Zero-phase FIR band for offline ABR reprocessing.
%
%   The offline analysis band, as one designed-once object: an equiripple
%   high pass (default 150 Hz stop / 300 Hz pass) and low pass (3000 Hz pass /
%   4200 Hz stop), applied with FILTFILT so the chain adds no phase distortion
%   and therefore no latency shift to a peak measurement.
%
%   It is a VALUE object with a cached design, the same idiom as
%   mabr.FilterPolicy: design(Fs) returns a copy carrying the coefficients for
%   that rate, and apply(x) runs them. Designing is the expensive half and a
%   session has one sample rate, so it happens once per session rather than
%   once per file.
%
%       f = mabr.analysis.Filter;              % defaults
%       f = f.design(12000);
%       y = f.apply(x);                        % x: [nSamples x nChannels]
%
%   Apply it to the WHOLE continuous trace before segmenting into sweeps, not
%   to the sweeps themselves. A sweep is a few hundred samples and the filter's
%   own edge transient would land squarely on the response; the continuous
%   trace has no such edge except at its two ends.
%
%   Custom designs are accepted wholesale, which is how a caller supplies the
%   fdesign/dsp.FIRFilter objects designed elsewhere:
%
%       f = mabr.analysis.Filter.fromObject(HdHP,HdLP);
%       f = mabr.analysis.Filter.fromCoefficients(bHP,bLP);
%
%   Either switch is independently disabled by setting its band to empty:
%
%       f.HighPass = [];      % low pass only
%
%   See also mabr.analysis.Session, mabr.FilterPolicy, filtfilt

    properties
        % [Fstop Fpass] Hz for the high pass; empty disables it.
        HighPass (1,:) double {mustBeNonnegative} = [150 300]

        % [Fpass Fstop] Hz for the low pass; empty disables it.
        LowPass (1,:) double {mustBeNonnegative} = [3000 4200]

        % Equiripple design tolerances (linear, not dB) and density factor.
        PassRipple (1,1) double {mustBePositive} = 0.014390163418
        StopRipple (1,1) double {mustBePositive} = 0.031622776602
        Density    (1,1) double {mustBePositive} = 20

        % "filtfilt" (zero phase, the default and what a latency measurement
        % needs) or "filter" (causal, one pass).
        Method (1,1) string {mustBeMember(Method,["filtfilt","filter"])} = "filtfilt"
    end

    properties (SetAccess = private)
        SampleRate (1,1) double = NaN   % rate the cached design is for
        HighNum (1,:) double = []       % numerator, high pass
        HighDen (1,:) double = 1
        LowNum  (1,:) double = []       % numerator, low pass
        LowDen  (1,:) double = 1
        Custom  (1,1) logical = false   % coefficients supplied, not designed
        Designed (1,1) logical = false  % design(Fs) has been called
    end

    properties (Dependent)
        IsDesigned  (1,1) logical
        Order       (1,1) double   % longest section, in samples
        MinLength   (1,1) double   % shortest signal filtfilt will accept
    end

    methods
        function obj = Filter(varargin)
            % Filter(Name,Value,...) sets any of the public properties.
            for i = 1:2:numel(varargin)
                obj.(varargin{i}) = varargin{i+1};
            end
        end

        % --- design -------------------------------------------------------
        function obj = design(obj,Fs)
            % Design (or redesign) the chain at Fs and cache the result.
            arguments
                obj
                Fs (1,1) double {mustBePositive,mustBeFinite}
            end
            if obj.Custom
                % Coefficients were handed in; nothing to design, but record
                % the rate they are being used at so callers can check it.
                obj.SampleRate = Fs;
                obj.Designed   = true;
                return
            end

            obj.HighNum = []; obj.HighDen = 1;
            obj.LowNum  = []; obj.LowDen  = 1;

            nyq = Fs/2;
            if ~isempty(obj.HighPass)
                e = sort(obj.HighPass(:).');
                mabr.analysis.Filter.checkNyquist(e,nyq,'HighPass');
                [N,Fo,Ao,W] = firpmord(e/nyq,[0 1],[obj.StopRipple obj.PassRipple]);
                obj.HighNum = firpm(N,Fo,Ao,W,{obj.Density});
            end
            if ~isempty(obj.LowPass)
                e = sort(obj.LowPass(:).');
                mabr.analysis.Filter.checkNyquist(e,nyq,'LowPass');
                [N,Fo,Ao,W] = firpmord(e/nyq,[1 0],[obj.PassRipple obj.StopRipple]);
                obj.LowNum = firpm(N,Fo,Ao,W,{obj.Density});
            end
            obj.SampleRate = Fs;
            obj.Designed   = true;
        end

        % --- application ---------------------------------------------------
        function y = apply(obj,x)
            % Run the designed chain over x (columns filtered independently).
            %
            % A signal too short for FILTFILT is returned UNFILTERED with a
            % warning rather than throwing: one truncated run must not stop a
            % whole session from being analysed.
            if ~obj.IsDesigned
                error('mabr:analysis:Filter:notDesigned', ...
                    'Filter has not been designed. Call design(Fs) first.');
            end
            y = double(x);
            if isempty(y), return; end

            % Both bands switched off is a legitimate setting -- "reprocess
            % without filtering" -- and must pass the trace through untouched
            % rather than refuse, so that it can be compared against a filtered
            % pass of the same data.
            if isempty(obj.HighNum) && isempty(obj.LowNum), return; end

            if size(y,1) < obj.MinLength
                warning('mabr:analysis:Filter:tooShort', ...
                    'Signal is %d samples; %s needs at least %d. Left unfiltered.', ...
                    size(y,1), obj.Method, obj.MinLength);
                return
            end

            if ~isempty(obj.HighNum), y = obj.run(y,obj.HighNum,obj.HighDen); end
            if ~isempty(obj.LowNum),  y = obj.run(y,obj.LowNum, obj.LowDen);  end
        end

        function tf = fits(obj,n)
            % True when a signal of n samples is long enough to be filtered.
            tf = ~obj.IsDesigned || n >= obj.MinLength;
        end

        % --- description ----------------------------------------------------
        function [f,mag] = response(obj,n)
            % Magnitude response of the chain AS APPLIED, in dB.
            %
            % Under "filtfilt" the realized response is |H|^2, so a -3 dB
            % design corner reads -6 dB here. That is the honest number: it is
            % what the data actually saw.
            arguments
                obj
                n (1,1) double {mustBePositive} = 4096
            end
            if ~obj.IsDesigned
                error('mabr:analysis:Filter:notDesigned', ...
                    'Filter has not been designed. Call design(Fs) first.');
            end
            f = linspace(0,obj.SampleRate/2,n).';
            H = ones(n,1);
            if ~isempty(obj.HighNum)
                H = H .* abs(freqz(obj.HighNum,obj.HighDen,f,obj.SampleRate));
            end
            if ~isempty(obj.LowNum)
                H = H .* abs(freqz(obj.LowNum,obj.LowDen,f,obj.SampleRate));
            end
            if obj.Method == "filtfilt", H = H.^2; end
            mag = 20*log10(max(H,eps));
        end

        function ax = plotResponse(obj,ax)
            % Draw the response of the chain as applied.
            arguments
                obj
                ax = []
            end
            if isempty(ax)
                ax = axes(figure('Name','ABR filter response','Color','w'));
            end
            [f,mag] = obj.response();
            line(ax,f,mag,'Color',[0 0.35 0.7],'LineWidth',1.5);
            yline(ax,-6,'--','-6 dB','Color',[0.6 0.6 0.6]);
            set(ax,'XScale','log','YLim',[-80 5]);
            xlim(ax,[max(1,f(2)) obj.SampleRate/2]);
            grid(ax,'on'); box(ax,'on');
            xlabel(ax,'Frequency (Hz)'); ylabel(ax,'Magnitude (dB)');
            title(ax,char(obj.describe()));
            mabr.analysis.Plot.plainAxes(ax);
        end

        function s = describe(obj)
            % One-line summary, e.g. "300-3000 Hz FIR (filtfilt, order 214)".
            if isempty(obj.HighNum) && isempty(obj.LowNum) && ~obj.Custom
                s = "no filtering";
                return
            end
            if obj.Custom
                % The bands of a supplied design are unknown, and naming them
                % DC-to-Nyquist would be a claim rather than an absence.
                s = string(sprintf('custom FIR (%s, order %d)',obj.Method,obj.Order));
                return
            end
            if isempty(obj.HighPass), lo = "DC"; else, lo = string(sprintf('%g',max(obj.HighPass))); end
            if isempty(obj.LowPass),  hi = "Nyq"; else, hi = string(sprintf('%g',min(obj.LowPass))); end
            if obj.Custom, kind = "custom FIR"; else, kind = "FIR"; end
            if obj.IsDesigned
                s = sprintf('%s-%s Hz %s (%s, order %d)',lo,hi,kind,obj.Method,obj.Order);
            else
                s = sprintf('%s-%s Hz %s (%s, undesigned)',lo,hi,kind,obj.Method);
            end
            s = string(s);
        end

        % --- dependent -------------------------------------------------------
        function tf = get.IsDesigned(obj)
            tf = obj.Designed && isfinite(obj.SampleRate);
        end

        function n = get.Order(obj)
            n = max([numel(obj.HighNum) numel(obj.LowNum) 1]) - 1;
        end

        function n = get.MinLength(obj)
            if obj.Method == "filter" || (isempty(obj.HighNum) && isempty(obj.LowNum))
                n = 1;
            else
                n = 3*max([numel(obj.HighNum) numel(obj.HighDen) ...
                           numel(obj.LowNum)  numel(obj.LowDen)] - 1) + 1;
            end
        end
    end

    methods (Access = private)
        function y = run(obj,x,b,a)
            if obj.Method == "filtfilt"
                y = filtfilt(b,a,x);
            else
                y = filter(b,a,x);
            end
        end
    end

    methods (Static)
        function obj = fromCoefficients(hpNum,lpNum,opts)
            % Build from numerators (or [b,a] pairs) designed elsewhere.
            arguments
                hpNum = []
                lpNum = []
                opts.HighDen (1,:) double = 1
                opts.LowDen  (1,:) double = 1
                opts.SampleRate (1,1) double = NaN
                opts.Method (1,1) string {mustBeMember(opts.Method,["filtfilt","filter"])} = "filtfilt"
            end
            obj = mabr.analysis.Filter;
            obj.Custom  = true;
            obj.Method  = opts.Method;
            obj.HighNum = hpNum(:).';
            obj.HighDen = opts.HighDen;
            obj.LowNum  = lpNum(:).';
            obj.LowDen  = opts.LowDen;
            obj.SampleRate = opts.SampleRate;
            % The bands are unknown for a supplied design; describe() uses them
            % only for its label, so leave them empty rather than inventing
            % edges the coefficients may not have.
            obj.HighPass = [];
            obj.LowPass  = [];
        end

        function obj = fromObject(hp,lp,opts)
            % Build from dfilt.*/dsp.* filter objects, as extractABRResponses
            % accepted through HighpassHd/LowpassHd.
            arguments
                hp = []
                lp = []
                opts.SampleRate (1,1) double = NaN
                opts.Method (1,1) string {mustBeMember(opts.Method,["filtfilt","filter"])} = "filtfilt"
            end
            [bh,ah] = mabr.analysis.Filter.coefficientsOf(hp);
            [bl,al] = mabr.analysis.Filter.coefficientsOf(lp);
            obj = mabr.analysis.Filter.fromCoefficients(bh,bl, ...
                HighDen=ah, LowDen=al, SampleRate=opts.SampleRate, Method=opts.Method);
        end

        function [b,a] = coefficientsOf(hd)
            % Pull [b,a] out of whatever filter representation was handed in.
            b = []; a = 1;
            if isempty(hd), return; end
            if isnumeric(hd), b = hd(:).'; return; end
            if isprop(hd,'Numerator') || (isstruct(hd) && isfield(hd,'Numerator'))
                b = hd.Numerator(:).';
                if isprop(hd,'Denominator'), a = hd.Denominator(:).'; end
                return
            end
            try
                [b,a] = tf(hd);
            catch
                error('mabr:analysis:Filter:unsupported', ...
                    'Cannot extract coefficients from a %s.', class(hd));
            end
        end

        function checkNyquist(edges,nyq,name)
            % A corner at or past Nyquist is a design that cannot exist.
            if any(edges >= nyq)
                error('mabr:analysis:Filter:aboveNyquist', ...
                    '%s edge %g Hz is at or above Nyquist (%g Hz).', ...
                    name, max(edges), nyq);
            end
        end
    end
end
