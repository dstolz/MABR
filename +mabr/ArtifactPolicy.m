classdef ArtifactPolicy
% mabr.ArtifactPolicy  What counts as an artifact, and what to do about one.
%
%   P = mabr.ArtifactPolicy returns a plain value object holding the three
%   decisions the GUI offers, and the defaults for each:
%
%       Mode    'none' | 'voltage' | 'rms'   how a sweep is judged
%       ...Threshold                          where the line sits
%       Repeat  true/false                    re-present what was lost, or
%                                             merely count it
%
%   Like mabr.Config this is a value object and a superclass of nothing.
%   mabr.ui.App edits one, mabr.ui.AcqController applies it at finalization,
%   and loadPrefs/savePrefs carry the user's choices across sessions in MATLAB
%   prefs (group 'MABR').
%
%   Thresholds are in VOLTS, the units of the recorded trace. The GUI shows
%   them in millivolts because that is the scale the numbers actually live at.
%
%   Counting vs repeating
%   ---------------------
%   Rejected sweeps are ALWAYS marked, in mabr.data.Recording.IsArtifact, and
%   always written to the .abr file — no sample is ever silently discarded, so
%   an offline reanalysis can make its own call. Repeat only decides whether
%   MABR also tries to win the lost sweeps back:
%
%     Repeat = false  count them. The block keeps however many clean sweeps it
%                     got and the schedule moves on.
%     Repeat = true   make them up. The controller asks the schedule to append
%                     a make-up run at the END of the plan re-presenting each
%                     rejected sweep, so the session still converges on the
%                     requested number of clean sweeps per condition. It is
%                     appended rather than spliced in because a run's play
%                     matrix is rendered in full before it starts and cannot
%                     grow mid-flight. mabr.stim.Schedule.MakeupLimit bounds
%                     the total, so a permanently noisy electrode cannot make
%                     a session run forever.
%
%   See also mabr.metrics.detect_artifacts, mabr.stim.Schedule.appendMakeup.
%
% Daniel Stolzberg (c) 2019-2026

    properties (Constant)
        Modes      = {'none','voltage','rms'};

        % Display names for Modes, in the same order (the GUI dropdown carries
        % the canonical names above as ItemsData).
        ModeItems  = { ...
            'None — keep every sweep', ...
            'Voltage threshold', ...
            'RMS threshold'};
    end

    properties
        Mode (1,:) char {mustBeMember(Mode,{'none','voltage','rms'})} = 'none'

        % Reject a sweep when any sample leaves +/- this. 100 mV is the
        % default the electrode chain's usable range implies: anything beyond
        % it is out of the amplifier's linear region, not biology.
        VoltageThreshold (1,1) double {mustBePositive,mustBeFinite} = 0.100   % V

        % Reject a sweep when its RMS exceeds this. 30 mV sits well below the
        % RMS a sweep riding near the +/-100 mV peak limit would show (~50 mV),
        % so it catches sustained muscle contamination that never trips the
        % peak threshold, while leaving a quiet ABR sweep (hundreds of
        % microvolts at most) an enormous margin.
        RMSThreshold (1,1) double {mustBePositive,mustBeFinite} = 0.030       % V

        % Re-present sweeps lost to artifact rather than only counting them.
        Repeat (1,1) logical = false
    end

    properties (Dependent)
        Threshold          % the threshold the current Mode actually uses (V)
        Enabled            % false when Mode is 'none'
    end

    methods
        function obj = ArtifactPolicy(mode,threshold,repeat)
            if nargin >= 1 && ~isempty(mode),   obj.Mode = lower(char(mode)); end
            if nargin >= 2 && ~isempty(threshold), obj = obj.setThreshold(threshold); end
            if nargin >= 3 && ~isempty(repeat), obj.Repeat = logical(repeat); end
        end

        function tf = get.Enabled(obj), tf = ~strcmpi(obj.Mode,'none'); end

        function t = get.Threshold(obj)
            switch lower(obj.Mode)
                case 'voltage', t = obj.VoltageThreshold;
                case 'rms',     t = obj.RMSThreshold;
                otherwise,      t = Inf;      % nothing can exceed it
            end
        end

        function obj = setThreshold(obj,t)
            % Set whichever threshold the current Mode reads, so the two keep
            % independent values as the user switches back and forth.
            switch lower(obj.Mode)
                case 'voltage', obj.VoltageThreshold = t;
                case 'rms',     obj.RMSThreshold     = t;
            end
        end

        function [tf,feature] = detect(obj,D)
            % Flag the artifact sweeps in a [nSamples x nSweeps] matrix.
            [tf,feature] = mabr.metrics.detect_artifacts(D,obj.Mode,obj.Threshold);
        end

        function s = describe(obj)
            % One-line summary for the status line / logs.
            switch lower(obj.Mode)
                case 'voltage'
                    s = sprintf('reject |x| > %g mV',1e3*obj.VoltageThreshold);
                case 'rms'
                    s = sprintf('reject RMS > %g mV',1e3*obj.RMSThreshold);
                otherwise
                    s = 'no artifact rejection';
                    return
            end
            if obj.Repeat, s = [s ', repeating lost sweeps'];
            else,          s = [s ', counting only'];
            end
        end
    end

    methods (Static)
        function obj = loadPrefs()
            % Restore the last session's choices, falling back to the property
            % defaults above for anything never saved (or saved invalid — a
            % pref file edited by hand should not stop the app from opening).
            obj = mabr.ArtifactPolicy;
            try
                obj.Mode = getpref('MABR','ArtifactMode',obj.Mode);
            catch
                obj.Mode = 'none';
            end
            obj.VoltageThreshold = mabr.ArtifactPolicy.getPositive( ...
                'ArtifactVoltage',obj.VoltageThreshold);
            obj.RMSThreshold = mabr.ArtifactPolicy.getPositive( ...
                'ArtifactRMS',obj.RMSThreshold);
            obj.Repeat = logical(getpref('MABR','ArtifactRepeat',obj.Repeat));
        end

        function savePrefs(obj)
            setpref('MABR','ArtifactMode',    obj.Mode);
            setpref('MABR','ArtifactVoltage', obj.VoltageThreshold);
            setpref('MABR','ArtifactRMS',     obj.RMSThreshold);
            setpref('MABR','ArtifactRepeat',  obj.Repeat);
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
