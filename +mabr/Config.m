classdef Config
% mabr.Config  Constants and runtime paths for the MABR toolbox.
%
%   C = mabr.Config returns a plain value object holding the fixed hardware
%   constants (sample rates, frame length, ring-buffer size), release
%   metadata, required-toolbox list, and the runtime/error-log paths used by
%   the acquisition engine.
%
%   This is deliberately NOT a handle class and NOT a superclass of anything
%   (unlike the legacy abr.Universal). Nothing inherits from it; the app and
%   engine simply hold a copy.
%
%   Static helpers (do not require constructing the object):
%       mabr.Config.root         - repository root folder
%       mabr.Config.runtimeDir   - .runtime_data folder (created if missing)
%       mabr.Config.errorLogDir  - .error_logs folder (created if missing)
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        % --- Hardware / streaming constants ---------------------------------
        DACSampleRate        (1,1) double = 192000;   % Hz, playback + full-duplex record rate
        ADCSampleRate        (1,1) double = 12000;    % Hz, decimated storage/analysis rate
        frameLength          (1,1) double = 1024;     % samples per play/record frame
        maxInputBufferLength (1,1) double = 2^26;     % ring-buffer length (samples); ~5.8 min @ 192 kHz

        % --- Release metadata -----------------------------------------------
        SoftwareVersion = '23A';
        DataVersion     = '22A';                      % keep matched to the .abr struct the offline pipeline reads
        Author          = 'Daniel Stolzberg';
        AuthorEmail     = 'dstolz@umd.edu';
        GithubRepository = 'https://github.com/dstolz/MABR';

        % Parallel Computing Toolbox added for the parpool-based engine
        % (absent from the legacy abr.Universal required list).
        RequiredToolboxes = {'MATLAB',                     9.5; ...
                             'Signal Processing Toolbox',  8.1; ...
                             'Audio Toolbox',              1.5; ...
                             'DSP System Toolbox',         9.1; ...
                             'Parallel Computing Toolbox', 6.13};
    end

    properties (Dependent)
        decimationFactor            % DACSampleRate / ADCSampleRate
        runtimePath                 % .runtime_data folder
        errorLogPath                % .error_logs folder
        signalBufferFile            % memmap ring buffer: recorded signal channel
        timingBufferFile            % memmap ring buffer: recorded timing channel
        headerFile                  % memmap ring buffer: write-head header
    end

    methods
        function obj = Config()
            % Touch the runtime directories so they exist before the engine
            % memory-maps files into them.
            mabr.Config.runtimeDir;
            mabr.Config.errorLogDir;
        end

        function f = get.decimationFactor(obj)
            f = obj.DACSampleRate ./ obj.ADCSampleRate;
        end

        function p = get.runtimePath(~),      p = mabr.Config.runtimeDir;  end
        function p = get.errorLogPath(~),     p = mabr.Config.errorLogDir; end
        function p = get.signalBufferFile(~), p = fullfile(mabr.Config.runtimeDir,'ring_signal.dat'); end
        function p = get.timingBufferFile(~), p = fullfile(mabr.Config.runtimeDir,'ring_timing.dat'); end
        function p = get.headerFile(~),       p = fullfile(mabr.Config.runtimeDir,'ring_header.dat'); end

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
