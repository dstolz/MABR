classdef FilterPolicy
% mabr.FilterPolicy  The digital filter chain applied to VIEWED data.
%
%   F = mabr.FilterPolicy returns a plain value object holding the three
%   filters the GUI offers, each independently switchable:
%
%       HighPass / HighPassHz    drift, DC offset, and slow electrode noise
%       LowPass  / LowPassHz     hiss and everything above the response band
%       Notch    / NotchHz       mains hum (60 Hz here, 50 Hz elsewhere)
%
%   Like mabr.Config and mabr.ArtifactPolicy this is a value object and a
%   superclass of nothing. mabr.ui.FilterDialog edits one, mabr.ui.App owns
%   it, mabr.ui.AcqController applies it to the live view, and
%   mabr.data.Recording applies it to everything derived from a saved trace.
%   loadPrefs/savePrefs carry the user's choices across sessions in MATLAB
%   prefs (group 'MABR').
%
%   Display only — the raw trace is what gets saved
%   ----------------------------------------------
%   Nothing here ever touches mabr.data.Recording.Data, and so nothing here
%   ever reaches the .abr file: mabr.data.io writes the trace exactly as it
%   came off the ADC. Filtering happens on the way to a plot or a metric
%   (Recording.ProcessedData -> SweepData -> SweepMean, and the live view's
%   sweep matrices), so the offline pipeline is free to make entirely
%   different choices from the same samples. Changing a setting mid-session
%   therefore costs nothing and loses nothing.
%
%   Designing and applying
%   ----------------------
%   designfilt is far too slow to call inside a 20 Hz live-view tick, so the
%   design is cached in the object and the caller keeps a designed copy:
%
%       f = mabr.FilterPolicy;
%       f = f.design(12000);        % build the chain at this sample rate
%       y = f.apply(x);             % zero-phase (filtfilt), column-wise
%
%   apply() on an undesigned policy returns x untouched — the same opt-in
%   rule mabr.data.Recording follows. Because filtfilt runs the chain
%   forwards and backwards, the realized magnitude response is |H|^2; that
%   is what response() reports and what mabr.ui.FilterDialog draws.
%
%   See also mabr.ui.FilterDialog, mabr.data.Recording.designFilters.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        % Butterworth order allowed for the high- and low-pass sections. A
        % high-order IIR with a 10 Hz corner at 12 kHz is numerically
        % fragile, and there is nothing to gain from a steeper skirt on a
        % 10 ms sweep, so the range is deliberately narrow and even-only.
        Orders = [2 4 6 8];
    end

    properties
        HighPass   (1,1) logical = true
        HighPassHz (1,1) double {mustBePositive,mustBeFinite} = 10      % Hz

        LowPass    (1,1) logical = true
        LowPassHz  (1,1) double {mustBePositive,mustBeFinite} = 3000    % Hz

        Notch        (1,1) logical = true
        NotchHz      (1,1) double {mustBePositive,mustBeFinite} = 60    % Hz
        NotchWidthHz (1,1) double {mustBePositive,mustBeFinite} = 4     % Hz, -3 dB width

        % Shared by the high- and low-pass sections; the notch is always
        % order 2, since a wider skirt there would eat the response band.
        Order (1,1) double {mustBePositive,mustBeInteger} = 4
    end

    properties (SetAccess = private)
        % Filled in by design(); a cell of digitalFilter, applied in order.
        Designs    = {}
        DesignRate (1,1) double = 0     % Hz the chain was designed at; 0 = undesigned
    end

    properties (Dependent)
        Enabled     % false when no section is switched on
        Designed    % true once design() has built the chain
    end

    methods
        function obj = FilterPolicy(hp,lp,notch)
            % Optional shorthand: pass a corner frequency to enable a
            % section, or [] / false to switch it off.
            if nargin >= 1, obj = obj.setSection('HighPass',hp); end
            if nargin >= 2, obj = obj.setSection('LowPass',lp);  end
            if nargin >= 3, obj = obj.setSection('Notch',notch); end
        end

        function tf = get.Enabled(obj)
            tf = obj.HighPass || obj.LowPass || obj.Notch;
        end

        function tf = get.Designed(obj)
            tf = ~isempty(obj.Designs);
        end

        function tf = isDesignedFor(obj,Fs)
            % Is the cached chain the one this policy asks for at Fs? The
            % caller uses this to skip a redesign on every live-view tick.
            tf = obj.DesignRate == Fs && (obj.Designed || ~obj.Enabled);
        end

        function obj = design(obj,Fs)
            % Build the enabled sections at sample rate Fs. Reassign the
            % result — this is a value class.
            nyq = Fs/2;
            d   = {};

            if obj.HighPass
                d{end+1} = designfilt('highpassiir', ...
                    'FilterOrder',         obj.clampOrder(), ...
                    'HalfPowerFrequency',  min(obj.HighPassHz,0.99*nyq), ...
                    'SampleRate',          Fs);
            end
            if obj.LowPass
                d{end+1} = designfilt('lowpassiir', ...
                    'FilterOrder',         obj.clampOrder(), ...
                    'HalfPowerFrequency',  min(obj.LowPassHz,0.99*nyq), ...
                    'SampleRate',          Fs);
            end
            if obj.Notch
                w  = obj.NotchWidthHz/2;
                f1 = max(eps,      obj.NotchHz - w);
                f2 = min(0.99*nyq, obj.NotchHz + w);
                d{end+1} = designfilt('bandstopiir', ...
                    'FilterOrder',          2, ...
                    'HalfPowerFrequency1',  f1, ...
                    'HalfPowerFrequency2',  f2, ...
                    'SampleRate',           Fs);
            end

            obj.Designs    = d;
            obj.DesignRate = Fs;
        end

        function y = apply(obj,x)
            % Apply the designed chain zero-phase, column-wise. Returns x
            % unchanged when the policy has not been designed (opt-in, like
            % mabr.data.Recording) or when a column is too short to
            % filtfilt — a truncated sweep should not take the live view
            % down with it.
            y = x;
            if isempty(obj.Designs), return; end
            wasRow = isrow(x);
            if wasRow, y = y(:); end

            y = double(y);
            for i = 1:numel(obj.Designs)
                if size(y,1) <= 3*filtord(obj.Designs{i}), continue; end
                y = filtfilt(obj.Designs{i},y);
            end

            if wasRow, y = y.'; end
            if isa(x,'single'), y = single(y); end
        end

        function [magDB,f] = response(obj,Fs,n)
            % Magnitude of the chain AS APPLIED, i.e. |H|^2 in dB because
            % filtfilt runs it in both directions. Frequencies are
            % log-spaced from 1 Hz to Nyquist, which is the only way a
            % 10 Hz corner and a 3 kHz corner are legible on one axis.
            if nargin < 3 || isempty(n), n = 1024; end
            f = logspace(0,log10(Fs/2),n).';
            if ~obj.isDesignedFor(Fs), obj = obj.design(Fs); end

            magDB = zeros(size(f));
            for i = 1:numel(obj.Designs)
                H = freqz(obj.Designs{i},f,Fs);
                magDB = magDB + 2*20*log10(max(abs(H),1e-12));   % twice: filtfilt
            end
        end

        function s = describe(obj)
            % One-line summary for the GUI caption / status line / logs. Kept
            % short enough to sit in a panel row without eliding: a passband
            % reads as one range rather than two independent corners, which is
            % also how anyone describes it out loud.
            if obj.HighPass && obj.LowPass
                s = sprintf('%g–%g Hz',obj.HighPassHz,obj.LowPassHz);
            elseif obj.HighPass
                s = sprintf('above %g Hz',obj.HighPassHz);
            elseif obj.LowPass
                s = sprintf('below %g Hz',obj.LowPassHz);
            else
                s = '';
            end
            if obj.Notch
                n = sprintf('%g Hz notch',obj.NotchHz);
                if isempty(s), s = n; else, s = [s ' + ' n]; end
            end
            if isempty(s), s = 'no filtering'; end
        end

        function tf = sameSettings(obj,other)
            % Do two policies ask for the same chain? (The cached Designs
            % are deliberately ignored — they are a consequence, not a
            % setting.) Used to skip needless redesigns.
            tf = isa(other,'mabr.FilterPolicy') && ...
                 isequal(obj.settings(),other.settings());
        end

        function [tf,msg] = validate(obj,Fs)
            % Is this chain realizable at Fs, and does it leave a passband?
            % Returns a message the dialog can show rather than throwing:
            % the user is mid-edit, not mid-acquisition.
            tf = true; msg = '';
            nyq = Fs/2;
            if obj.HighPass && obj.HighPassHz >= nyq
                tf = false; msg = sprintf('High pass must be below Nyquist (%g Hz).',nyq); return
            end
            if obj.LowPass && obj.LowPassHz >= nyq
                tf = false; msg = sprintf('Low pass must be below Nyquist (%g Hz).',nyq); return
            end
            if obj.HighPass && obj.LowPass && obj.HighPassHz >= obj.LowPassHz
                tf = false; msg = 'High pass must be below low pass — this chain passes nothing.'; return
            end
            if obj.Notch && obj.NotchHz + obj.NotchWidthHz/2 >= nyq
                tf = false; msg = sprintf('The notch band must lie below Nyquist (%g Hz).',nyq); return
            end
            if obj.Notch && obj.NotchHz - obj.NotchWidthHz/2 <= 0
                tf = false; msg = 'The notch is wider than its own centre frequency.'; return
            end
        end
    end

    methods (Access = private)
        function n = clampOrder(obj)
            % Even, and inside Orders — designfilt demands an even order for
            % these IIR designs and a 10 Hz corner at 12 kHz will not
            % survive a steep one.
            n = 2*round(obj.Order/2);
            n = min(max(n,mabr.FilterPolicy.Orders(1)),mabr.FilterPolicy.Orders(end));
        end

        function obj = setSection(obj,name,v)
            % Constructor shorthand: [] or false switches a section off, a
            % frequency switches it on and sets the corner.
            if isempty(v) || (islogical(v) && ~v)
                obj.(name) = false;
            elseif islogical(v)
                obj.(name) = true;
            else
                obj.(name) = true;
                switch name
                    case 'HighPass', obj.HighPassHz = v;
                    case 'LowPass',  obj.LowPassHz  = v;
                    case 'Notch',    obj.NotchHz    = v;
                end
            end
        end

        function s = settings(obj)
            s = struct('HighPass',obj.HighPass,'HighPassHz',obj.HighPassHz, ...
                       'LowPass', obj.LowPass, 'LowPassHz', obj.LowPassHz, ...
                       'Notch',   obj.Notch,   'NotchHz',   obj.NotchHz, ...
                       'NotchWidthHz',obj.NotchWidthHz,'Order',obj.Order);
        end
    end

    methods (Static)
        function obj = loadPrefs()
            % Restore the last session's chain, falling back to the property
            % defaults for anything never saved (or saved invalid — a pref
            % edited by hand should not stop the app from opening).
            obj = mabr.FilterPolicy;
            obj.HighPass     = logical(getpref('MABR','FilterHighPass',obj.HighPass));
            obj.LowPass      = logical(getpref('MABR','FilterLowPass', obj.LowPass));
            obj.Notch        = logical(getpref('MABR','FilterNotch',   obj.Notch));
            obj.HighPassHz   = mabr.FilterPolicy.getPositive('FilterHighPassHz',obj.HighPassHz);
            obj.LowPassHz    = mabr.FilterPolicy.getPositive('FilterLowPassHz', obj.LowPassHz);
            obj.NotchHz      = mabr.FilterPolicy.getPositive('FilterNotchHz',   obj.NotchHz);
            obj.NotchWidthHz = mabr.FilterPolicy.getPositive('FilterNotchWidthHz',obj.NotchWidthHz);
            obj.Order        = mabr.FilterPolicy.getPositive('FilterOrder',     obj.Order);
        end

        function savePrefs(obj)
            setpref('MABR','FilterHighPass',     obj.HighPass);
            setpref('MABR','FilterLowPass',      obj.LowPass);
            setpref('MABR','FilterNotch',        obj.Notch);
            setpref('MABR','FilterHighPassHz',   obj.HighPassHz);
            setpref('MABR','FilterLowPassHz',    obj.LowPassHz);
            setpref('MABR','FilterNotchHz',      obj.NotchHz);
            setpref('MABR','FilterNotchWidthHz', obj.NotchWidthHz);
            setpref('MABR','FilterOrder',        obj.Order);
        end
    end

    methods (Static, Access = private)
        function v = getPositive(name,default)
            v = getpref('MABR',name,default);
            if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v <= 0
                v = default;
            end
        end
    end
end
