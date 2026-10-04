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
%   THE WINDOWED OPERATOR. An intermixed run is saved COMPACT -- each
%   condition's 10 ms windows back to back, with no pre-onset sample and a step
%   at every junction -- and a whole-trace filter would smear each junction's
%   step onto the response. applyWindowed(X) filters each window ON ITS OWN
%   instead: a linear detrend, an explicit padding (odd reflection, or zeros
%   on the left), and a zero-phase Butterworth pair whose corners are this FIR
%   chain's REALIZED -6 dB points (corners6dB) -- not its nominal pass edges,
%   at which the FIR is barely -0.25 dB -- so a windowed and a continuous
%   condition of one study are filtered to the same band:
%
%       f = f.design(12000);
%       [fHP6,fLP6] = f.corners6dB();          % about 240 and 3400 Hz
%       [Y,info]    = f.applyWindowed(X);      % X: [L x nWindows], raw
%
%   Every stage is linear, so filtering each window and then averaging equals
%   filtering the average -- which is what lets the operator be validated on
%   averages against the continuous chain.
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
            %
            %   varargin  Name,Value pairs, any public property above
            %             (HighPass, LowPass, PassRipple, StopRipple,
            %             Density, Method)
            %   obj       (returned) undesigned Filter with those properties set
            for i = 1:2:numel(varargin)
                obj.(varargin{i}) = varargin{i+1};
            end
        end

        % --- design -------------------------------------------------------
        function obj = design(obj,Fs)
            % Design (or redesign) the chain at Fs and cache the result.
            %
            %   Fs   sample rate, Hz, scalar > 0
            %   obj  (returned) copy of this Filter with HighNum/LowNum
            %        designed for Fs (or, for a Custom filter, unchanged
            %        coefficients simply stamped with SampleRate = Fs)
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
            %
            %   x  [nSamples x nChannels] numeric, any class (cast to double)
            %   y  (returned) [nSamples x nChannels] double, same size as x
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
            %
            %   n   number of samples, scalar
            %   tf  (returned) 1x1 logical
            tf = ~obj.IsDesigned || n >= obj.MinLength;
        end

        % --- the windowed operator --------------------------------------------
        function [fHP6,fLP6] = corners6dB(obj)
            % The chain's realized -6 dB points, one per section.
            %
            %   [fHP6,fLP6] = corners6dB(obj)
            %
            %   fHP6  (returned) Hz, the lowest frequency at which the high
            %         pass section's response RISES through -6 dB; NaN when
            %         the high pass is off
            %   fLP6  (returned) Hz, the lowest frequency above the low pass's
            %         pass band at which that section FALLS through -6 dB; NaN
            %         when the low pass is off
            %
            %   Each section is evaluated on its own over linspace(0,Fs/2,8192)
            %   and squared under "filtfilt" -- the response AS APPLIED -- and
            %   the crossing is interpolated linearly between grid points. These
            %   are the corners the windowed operator is designed at, because a
            %   zero-phase Butterworth is exactly -6 dB at its design corner:
            %   matching them is what makes a windowed condition and a
            %   continuous one carry the same band.
            if ~obj.IsDesigned
                error('mabr:analysis:Filter:notDesigned', ...
                    'Filter has not been designed. Call design(Fs) first.');
            end
            f = linspace(0,obj.SampleRate/2,8192).';
            fHP6 = NaN;
            fLP6 = NaN;
            if ~isempty(obj.HighNum)
                dB = obj.sectionDB(obj.HighNum,obj.HighDen,f);
                k  = find(dB(1:end-1) < -6 & dB(2:end) >= -6,1,'first');
                if ~isempty(k), fHP6 = mabr.analysis.Filter.crossing(f,dB,k); end
            end
            if ~isempty(obj.LowNum)
                dB = obj.sectionDB(obj.LowNum,obj.LowDen,f);
                k0 = 1;
                if ~isempty(obj.LowPass)
                    % "Above the pass band": an equiripple pass band never
                    % comes near -6 dB, but a custom design might wobble, and
                    % only the edge past the pass band is the corner.
                    kk = find(f >= min(obj.LowPass),1,'first');
                    if ~isempty(kk), k0 = max(1,kk-1); end
                end
                k = find(dB(k0:end-1) >= -6 & dB(k0+1:end) < -6,1,'first');
                if ~isempty(k), fLP6 = mabr.analysis.Filter.crossing(f,dB,k + k0 - 1); end
            end
        end

        function [Y,info] = applyWindowed(obj,X,opts)
            % Filter short windows, one per column, each on its own.
            %
            %   [Y,info] = applyWindowed(obj,X,Order=2,PadMode="reflect")
            %
            %   X             [L x N] RAW windows, one per column (any numeric
            %                 class; cast to double)
            %   opts.Order    Butterworth order of each section (default 2)
            %   opts.PadMode  "reflect" (default): odd reflection at both ends;
            %                 "zeroleft": zeros before the window (what was
            %                 before the onset is unknown, and after the detrend
            %                 zero is its expected value), odd reflection after
            %   Y             (returned) [L x N] double
            %   info          (returned) struct: HP6, LP6 (Hz, NaN = off), Pad
            %                 (samples each side), Order, PadMode, Skipped
            %                 (true when L < 4 or the padded window is too
            %                 short for filtfilt: Y is then only detrended and
            %                 the caller should say so), Description
            %
            %   1. each column is linearly detrended (detrend(X,1)) -- linear,
            %      unlike subtracting the window's mean, which would remove the
            %      response's own mean;
            %   2. Butterworth sections at this chain's corners6dB(): HP
            %      butter(Order,fHP6/(Fs/2),'high') and LP
            %      butter(Order,fLP6/(Fs/2),'low'), each where this chain has
            %      that band;
            %   3. P samples padded on each side, P = min(L-1, max(6*Order,
            %      ceil(5*tau*Fs))) with tau = sqrt(2)/(2*pi*fHP6) the high
            %      pass's time constant (min(L-1,6*Order) without one) --
            %      filtfilt's own padding is a fraction of a millisecond, far
            %      shorter than the ~3 ms a 250 Hz high pass takes to settle, so
            %      its edge transient would otherwise land on waves I and II;
            %   4. filtfilt high pass then low pass over the padded block, and
            %      the middle L rows kept.
            %   Requires a designed filter (the corners are the design's).
            arguments
                obj
                X {mustBeNumeric}
                opts.Order (1,1) double {mustBeInteger,mustBeInRange(opts.Order,1,8)} = 2
                opts.PadMode (1,1) string {mustBeMember(opts.PadMode,["reflect","zeroleft"])} = "reflect"
            end
            if ~obj.IsDesigned
                error('mabr:analysis:Filter:notDesigned', ...
                    'Filter has not been designed. Call design(Fs) first.');
            end
            if ~ismatrix(X)
                error('mabr:analysis:Filter:notMatrix', ...
                    'applyWindowed takes an [L x N] matrix of windows, one per column.');
            end
            [hp6,lp6] = obj.corners6dB();
            info = struct('HP6',hp6,'LP6',lp6,'Pad',0,'Order',opts.Order, ...
                'PadMode',opts.PadMode,'Skipped',false,'Description',"");

            X = double(X);
            [L,N] = size(X);
            Y = X;
            if L == 0 || N == 0
                info.Description = mabr.analysis.Filter.windowedText(hp6,lp6,opts.Order,opts.PadMode,0);
                return
            end

            % 1. Linear detrend, column by column (a single sample has no
            % trend: its own value goes).
            if L >= 2
                Y = detrend(X,1);
            else
                Y = X - X;
            end

            hasHP = isfinite(hp6);
            hasLP = isfinite(lp6);
            if L < 4
                info.Skipped = true;
                info.Description = mabr.analysis.Filter.windowedText(hp6,lp6,opts.Order,opts.PadMode,0) + ...
                    " (skipped: window shorter than 4 samples)";
                return
            end
            if ~hasHP && ~hasLP
                % Both bands off is "reprocess without filtering": the detrend
                % is all there is to do.
                info.Description = mabr.analysis.Filter.windowedText(hp6,lp6,opts.Order,opts.PadMode,0);
                return
            end

            % 3. The padding.
            Fs = obj.SampleRate;
            n  = opts.Order;
            if hasHP
                tau = sqrt(2)/(2*pi*hp6);
                P = min(L-1, max(6*n, ceil(5*tau*Fs)));
            else
                P = min(L-1, 6*n);
            end
            right = 2*Y(end,:) - Y(end-1:-1:end-P,:);
            if opts.PadMode == "zeroleft"
                left = zeros(P,N);
            else
                left = 2*Y(1,:) - Y(P+1:-1:2,:);
            end
            Z = [left; Y; right];
            info.Pad = P;
            info.Description = mabr.analysis.Filter.windowedText(hp6,lp6,n,opts.PadMode,P);

            % filtfilt needs more than 3*(nfilt-1) = 3*Order samples.
            if size(Z,1) <= 3*n
                info.Skipped = true;
                info.Description = info.Description + " (skipped: window too short for this order)";
                return
            end

            % 2 and 4. The Butterworth pair, zero phase.
            nyq = Fs/2;
            if hasHP
                [b,a] = butter(n,hp6/nyq,'high');
                Z = filtfilt(b,a,Z);
            end
            if hasLP
                [b,a] = butter(n,lp6/nyq,'low');
                Z = filtfilt(b,a,Z);
            end
            Y = Z(P+1:P+L,:);
        end

        function s = describeWindowed(obj,opts)
            % One-line summary of the windowed operator applyWindowed runs.
            %
            %   s = describeWindowed(obj,Order=2,PadMode="reflect")
            %
            %   opts.Order, opts.PadMode  as applyWindowed
            %   s  (returned) 1x1 string, e.g. "Butterworth order 2, -6 dB at
            %      237-3418 Hz (filtfilt), linear detrend, reflect pad 57". The
            %      pad is the one an unclipped window gets; a window shorter
            %      than the pad is padded by L-1 (applyWindowed's info says
            %      which). Undesigned, the corners are not known yet and the
            %      text says whose they will be.
            arguments
                obj
                opts.Order (1,1) double {mustBeInteger,mustBeInRange(opts.Order,1,8)} = 2
                opts.PadMode (1,1) string {mustBeMember(opts.PadMode,["reflect","zeroleft"])} = "reflect"
            end
            n = opts.Order;
            if ~obj.IsDesigned
                s = sprintf(['Butterworth order %d at the -6 dB points of %s, linear detrend, ' ...
                    '%s pad'],n,obj.describe(),opts.PadMode);
                s = string(s);
                return
            end
            [hp6,lp6] = obj.corners6dB();
            if ~isfinite(hp6) && ~isfinite(lp6)
                P = 0;
            elseif isfinite(hp6)
                P = max(6*n, ceil(5*sqrt(2)/(2*pi*hp6)*obj.SampleRate));
            else
                P = 6*n;
            end
            s = mabr.analysis.Filter.windowedText(hp6,lp6,n,opts.PadMode,P);
        end

        % --- description ----------------------------------------------------
        function [f,mag] = response(obj,n)
            % Magnitude response of the chain AS APPLIED, in dB.
            %
            % Under "filtfilt" the realized response is |H|^2, so a -3 dB
            % design corner reads -6 dB here. That is the honest number: it is
            % what the data actually saw.
            %
            %   n    number of frequency points to evaluate (default 4096)
            %   f    (returned) [n x 1] double, Hz, 0 to SampleRate/2
            %   mag  (returned) [n x 1] double, dB magnitude at each f
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
            %
            %   ax  axes to draw into (default: a new figure's axes)
            %   ax  (returned) the same axes
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
            %
            %   s  (returned) 1x1 string
            %
            %   Read from the BANDS, so an undesigned filter says what it will
            %   do -- "300-3000 Hz FIR (filtfilt, undesigned)" -- rather than
            %   reading its still-empty coefficients as "no filtering", which is
            %   what a Session showed before segment() designed it. "no
            %   filtering" means both bands are off.
            if ~obj.Custom && isempty(obj.HighPass) && isempty(obj.LowPass)
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
        % IsDesigned: design(Fs) has been called and SampleRate is finite.
        % Order: longest coefficient vector, in samples, minus 1.
        % MinLength: shortest signal apply() will filter rather than pass through.
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

        function dB = sectionDB(obj,b,a,f)
            % One section's magnitude AS APPLIED (squared under filtfilt), dB.
            %
            %   b, a  the section's coefficients
            %   f     [n x 1] frequencies, Hz
            %   dB    (returned) [n x 1] 20*log10(|H|) (|H|^2 under filtfilt)
            H = abs(freqz(b,a,f,obj.SampleRate));
            if obj.Method == "filtfilt", H = H.^2; end
            dB = 20*log10(max(H,eps));
        end
    end

    methods (Static, Access = private)
        function fc = crossing(f,dB,k)
            % Where dB crosses -6 between grid points k and k+1, interpolated
            % linearly. f, dB: [n x 1]; k: index. fc: (returned) Hz.
            d = dB(k+1) - dB(k);
            if d == 0
                fc = f(k);
            else
                fc = f(k) + (-6 - dB(k))*(f(k+1) - f(k))/d;
            end
        end

        function s = windowedText(hp6,lp6,order,padMode,pad)
            % The windowed operator in one line (see describeWindowed).
            % hp6/lp6: Hz or NaN; order, padMode, pad: as applyWindowed.
            % s: (returned) 1x1 string.
            if ~isfinite(hp6) && ~isfinite(lp6)
                s = "no filtering, linear detrend";
                return
            end
            if isfinite(hp6), lo = sprintf('%.0f',hp6); else, lo = 'DC'; end
            if isfinite(lp6), hi = sprintf('%.0f',lp6); else, hi = 'Nyq'; end
            s = string(sprintf(['Butterworth order %d, -6 dB at %s-%s Hz (filtfilt), ' ...
                'linear detrend, %s pad %d'],order,lo,hi,padMode,pad));
        end
    end

    methods (Static)
        function obj = fromCoefficients(hpNum,lpNum,opts)
            % Build from numerators (or [b,a] pairs) designed elsewhere.
            %
            %   hpNum            high pass numerator, [] to disable
            %   lpNum            low pass numerator, [] to disable
            %   opts.HighDen     high pass denominator (default 1, i.e. FIR)
            %   opts.LowDen      low pass denominator (default 1, i.e. FIR)
            %   opts.SampleRate  Hz the coefficients were designed at (default NaN)
            %   opts.Method      "filtfilt" (default) or "filter"
            %   obj              (returned) Custom Filter carrying these
            %                    coefficients; call design(Fs) to mark it
            %                    designed (a no-op for a Custom filter beyond
            %                    recording the rate)
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
            %
            %   hp               high pass filter object, [] to disable
            %   lp               low pass filter object, [] to disable
            %   opts.SampleRate  Hz the objects were designed at (default NaN)
            %   opts.Method      "filtfilt" (default) or "filter"
            %   obj              (returned) Custom Filter (see fromCoefficients)
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
            %
            %   hd  [], a numeric vector, or a filter object/struct exposing
            %       Numerator/Denominator or convertible via tf()
            %   b   (returned) numerator, row vector ([] when hd is [])
            %   a   (returned) denominator, row vector (1 for an FIR/numeric hd)
            b = []; a = 1;
            if isempty(hd), return; end
            if isnumeric(hd), b = hd(:).'; return; end
            if (isstruct(hd) && isfield(hd,'Numerator')) || (~isstruct(hd) && isprop(hd,'Numerator'))
                b = hd.Numerator(:).';
                if (isstruct(hd) && isfield(hd,'Denominator')) || (~isstruct(hd) && isprop(hd,'Denominator'))
                    a = hd.Denominator(:).';
                end
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
            %
            %   edges  band-edge frequencies, Hz
            %   nyq    Nyquist frequency, Hz
            %   name   band name used in the thrown error message
            %   (no return value; throws mabr:analysis:Filter:aboveNyquist)
            if any(edges >= nyq)
                error('mabr:analysis:Filter:aboveNyquist', ...
                    '%s edge %g Hz is at or above Nyquist (%g Hz).', ...
                    name, max(edges), nyq);
            end
        end
    end
end
