classdef Config
% mabr.Config  Constants and runtime paths for the MABR toolbox.
%
%   C = mabr.Config returns a plain value object holding the hardware
%   constants (sample rates, frame length, ring-buffer size), release
%   metadata, required-toolbox list, and the runtime/error-log paths used by
%   the acquisition engine.
%
%   C = mabr.Config(fs) builds one at a DAC (device) sample rate other than
%   the 192 kHz default. The rate is IMMUTABLE once constructed -- a Config is
%   a value object, so changing the rate means building a new one and handing
%   it to whatever holds the old (see mabr.ui.App.applyAudioSettings, which
%   does exactly that and rebuilds the acquisition controller around it). The
%   rate the app runs at is a rig SETTING and lives in mabr.AudioSettings; its
%   config() method is the one place that setting becomes a Config.
%
%   ADCSampleRate is DERIVED, not chosen: sweep extraction windows the
%   ring buffer with an integer stride (mabr.metrics.extract_sweeps), so the
%   analysis/storage rate has to be the DAC rate divided by a whole number.
%   decimationFactor is that whole number -- whichever puts the result closest
%   to ADCTargetRate (12 kHz) -- so 192/96/48 kHz all land on exactly 12 kHz,
%   while the 44.1 kHz family lands on 11.025 kHz rather than pretending to a
%   rate no integer stride can reach.
%
%   This is deliberately NOT a handle class and NOT a superclass of anything
%   (unlike the legacy abr.Universal). Nothing inherits from it; the app and
%   engine simply hold a copy.
%
%   Static helpers (do not require constructing the object):
%       mabr.Config.root            - repository root folder
%       mabr.Config.runtimeDir      - .runtime_data folder (created if missing)
%       mabr.Config.errorLogDir     - .error_logs folder (created if missing)
%       mabr.Config.decimationFor   - integer stride for a candidate DAC rate
%       mabr.Config.adcRateFor      - the ADC rate that stride yields
%       mabr.Config.describeRate    - one-line "192 kHz -> 12 kHz (/16)" summary
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        % --- Hardware / streaming constants ---------------------------------
        % The rate a rig runs at unless mabr.AudioSettings says otherwise, and
        % the rate every saved bank, pref, and .mabrcfg predating the setting
        % is read back at.
        DefaultDACSampleRate (1,1) double = 192000;   % Hz
        % What ADCSampleRate aims for. Not a promise: it is reached exactly
        % only when the DAC rate is a whole multiple of it (see decimationFor).
        ADCTargetRate        (1,1) double = 12000;    % Hz
        % Offered by mabr.ui.AudioSettingsDialog's rate picker. Not a
        % restriction -- the picker is editable and any positive rate the
        % device grants is allowed -- just the rates worth listing.
        SupportedSampleRates (1,:) double = [44100 48000 88200 96000 176400 192000 384000];
        frameLength          (1,1) double = 1024;     % samples per play/record frame
        maxInputBufferLength (1,1) double = 2^26;     % ring-buffer length (samples); ~5.8 min @ 192 kHz
        % --- Compute-worker publish buffers (+mabr/+compute) --------------
        % The largest sweep (baseline + response, at the ADC rate), the
        % largest run or roster, and the number of analysis windows a
        % metrics worker serves at once. A window or a run over these is
        % refused with an error, never truncated.
        MaxComputeSamples    (1,1) double = 2048;     % ~85 ms at 12 kHz
        MaxComputeConditions (1,1) double = 256;
        MaxComputeJobs       (1,1) double = 8;

        % --- Release metadata -----------------------------------------------
        SoftwareVersion = '23A';
        DataVersion     = '22A';                      % keep matched to the .abr struct the offline pipeline reads
        Author          = 'Daniel Stolzberg';
        AuthorEmail     = 'dstolz@umd.edu';
        GithubRepository = 'https://github.com/dstolz/MABR';

        % Parallel Computing Toolbox added for the parpool-based engine
        % (absent from the legacy abr.Universal required list).
        % MATLAB >= 9.11 (R2021b): mabr.ui.App puts a uitoolbar on a
        % uifigure, which is only supported from R2021b -- below that the
        % GUI errors while building rather than degrading. (The floor was
        % 9.7/R2019b for 'arguments' blocks, which is still the constraint
        % for everything outside +ui.)
        RequiredToolboxes = {'MATLAB',                     9.11; ...
                             'Signal Processing Toolbox',  8.1; ...
                             'Audio Toolbox',              1.5; ...
                             'DSP System Toolbox',         9.1; ...
                             'Parallel Computing Toolbox', 6.13};
    end

    properties (SetAccess = immutable)
        % Hz: playback + full-duplex record rate, i.e. the rate the ASIO
        % device is opened at and every stimulus must already be rendered at.
        % Immutable because a Config is a value object that half the toolbox
        % holds a copy of: changing a rig's rate means building a new Config
        % and handing it out, which is exactly what mabr.ui.App does, rather
        % than mutating one copy and leaving the rest disagreeing about the
        % clock. Set it through mabr.AudioSettings.SampleRate, not here.
        %
        % The literal here rather than DefaultDACSampleRate: a property
        % default referencing the same class's own Constant is evaluated at
        % class load, which is exactly the moment the class is not yet loaded.
        % The constructor assigns from DefaultDACSampleRate, so that is still
        % the one place the number is decided for every Config anyone builds.
        DACSampleRate (1,1) double = 192000
    end

    properties (Dependent)
        ADCSampleRate               % Hz, decimated storage/analysis rate (DERIVED)
        decimationFactor            % integer stride: DACSampleRate / ADCSampleRate
        runtimePath                 % .runtime_data folder
        errorLogPath                % .error_logs folder
        signalBufferFile            % memmap ring buffer: recorded signal channel
        timingBufferFile            % memmap ring buffer: recorded timing channel
        headerFile                  % memmap ring buffer: write-head header
        computeLiveFile             % memmap: DSP worker -> client live statistics
        computeMetricFile           % memmap: metrics worker -> client values
        computeRequestFile          % memmap: client -> compute workers
    end

    methods
        function obj = Config(dacSampleRate)
            % Touch the runtime directories so they exist before the engine
            % memory-maps files into them.
            mabr.Config.runtimeDir;
            mabr.Config.errorLogDir;
            if nargin < 1 || isempty(dacSampleRate)
                dacSampleRate = mabr.Config.DefaultDACSampleRate;
            end
            obj.DACSampleRate = mabr.Config.validateSampleRate(dacSampleRate);
        end

        function f = get.decimationFactor(obj)
            f = mabr.Config.decimationFor(obj.DACSampleRate);
        end

        function r = get.ADCSampleRate(obj)
            r = obj.DACSampleRate ./ obj.decimationFactor;
        end

        function p = get.runtimePath(~),      p = mabr.Config.runtimeDir;  end
        function p = get.errorLogPath(~),     p = mabr.Config.errorLogDir; end
        function p = get.signalBufferFile(~), p = fullfile(mabr.Config.runtimeDir,'ring_signal.dat'); end
        function p = get.timingBufferFile(~), p = fullfile(mabr.Config.runtimeDir,'ring_timing.dat'); end
        function p = get.headerFile(~),       p = fullfile(mabr.Config.runtimeDir,'ring_header.dat'); end
        function p = get.computeLiveFile(~),    p = fullfile(mabr.Config.runtimeDir,'compute_live.dat');     end
        function p = get.computeMetricFile(~),  p = fullfile(mabr.Config.runtimeDir,'compute_metrics.dat');  end
        function p = get.computeRequestFile(~), p = fullfile(mabr.Config.runtimeDir,'compute_requests.dat'); end

        function tf = verifyToolboxes(obj,doError)
            % Returns true when every required toolbox is installed at a
            % sufficient version. When doError (default true) and something is
            % missing, an informative error is thrown instead.
            if nargin < 2 || isempty(doError), doError = true; end

            v  = ver;
            RT = obj.RequiredToolboxes;
            ok = false(size(RT,1),1);

            for i = 1:numel(v)
                ind = ismember(RT(:,1),v(i).Name);
                if ~any(ind), continue; end
                ok(ind) = mabr.Config.version_ge(v(i).Version,RT{ind,2});
            end

            tf = all(ok);

            if ~tf && doError
                missing = RT(~ok,:);
                s = '';
                for i = 1:size(missing,1)
                    s = sprintf('%s\t> %s (>= v%0.1f)\n',s,missing{i,1},missing{i,2});
                end
                error('mabr:Config:missingToolboxes', ...
                    'The MABR toolbox requires the following toolboxes:\n%s',s);
            end
        end
    end

    methods (Static)
        function r = root()
            % Repository root (the folder containing +mabr and MABR.m).
            r = fileparts(fileparts(which('mabr.Config')));
        end

        function p = runtimeDir()
            p = fullfile(mabr.Config.root,'.runtime_data');
            if ~isfolder(p), mkdir(p); end
        end

        function p = errorLogDir()
            p = fullfile(mabr.Config.root,'.error_logs');
            if ~isfolder(p), mkdir(p); end
        end

        function fs = validateSampleRate(fs)
            % Accept any rate a device might actually grant, and refuse the
            % ones that are a typo rather than a choice. Deliberately NOT
            % restricted to SupportedSampleRates: that list is what the picker
            % offers, and an ASIO box running at some rate nobody listed is
            % still a rate MABR can render, stream, and decimate at.
            assert(isnumeric(fs) && isscalar(fs) && isfinite(fs) && isreal(fs) && fs > 0, ...
                'mabr:Config:badSampleRate', ...
                'The DAC sample rate must be a positive finite scalar (got %s).', ...
                mat2str(fs));
            % Below the target rate there is nothing left to decimate and the
            % analysis band collapses: 12 kHz storage exists because an ABR
            % lives under ~3 kHz, and a device slower than that is not a rig
            % this toolbox can be honest about.
            assert(fs >= mabr.Config.ADCTargetRate,'mabr:Config:sampleRateTooLow', ...
                ['The DAC sample rate must be at least the %g Hz analysis rate ' ...
                 '(got %g Hz).'],mabr.Config.ADCTargetRate,fs);
            fs = double(fs);
        end

        function df = decimationFor(dacSampleRate)
            % The integer stride taking a candidate DAC rate closest to
            % ADCTargetRate. Integer because mabr.metrics.extract_sweeps
            % windows the ring buffer with it as a colon stride and
            % mabr.ui.AcqController.finalize_run resamples 1:df -- neither can
            % take a fraction. So 192/96/48 kHz give 16/8/4 and land on exactly
            % 12 kHz, while 44.1 kHz gives 4 and lands on 11.025 kHz: an
            % honest rate an integer stride can actually reach, rather than a
            % round number it cannot.
            df = max(1,round(dacSampleRate ./ mabr.Config.ADCTargetRate));
        end

        function fs = adcRateFor(dacSampleRate)
            % The analysis/storage rate decimationFor's stride yields.
            fs = dacSampleRate ./ mabr.Config.decimationFor(dacSampleRate);
        end

        function s = describeRate(dacSampleRate)
            % One line for a settings dialog: what is played, what is stored,
            % and the stride between them.
            df = mabr.Config.decimationFor(dacSampleRate);
            s = sprintf('%s kHz out · %s kHz stored (decimate %dx)', ...
                mabr.Config.rateText(dacSampleRate), ...
                mabr.Config.rateText(mabr.Config.adcRateFor(dacSampleRate)),df);
        end

        function s = rateText(fs)
            % kHz with just enough decimals to stay exact for the 44.1 family
            % (44.1, 11.025) without printing 192.000 for the round ones.
            s = strtrim(sprintf('%g',round(fs/1e3,4)));
        end

        function tf = version_ge(haveStr,needNum)
            % Compare a MATLAB version string ("9.13") against a required
            % numeric ("9.1"), treating the decimal as a zero-padded minor
            % component so that 9.12 > 9.5 (matches the legacy comparison).
            have = mabr.Config.version_key(haveStr);
            needStr = num2str(needNum);
            need = mabr.Config.version_key(needStr);
            tf = have >= need;
        end
    end

    methods (Static, Access = private)
        function k = version_key(vstr)
            dp = find(vstr == '.',1,'first');
            if isempty(dp)
                major = str2double(vstr);
                minor = 0;
            else
                major = str2double(vstr(1:dp-1));
                minor = str2double(vstr(dp+1:end));
            end
            k = str2double(sprintf('%d.%04d',major,minor));
        end
    end
end
