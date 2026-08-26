classdef PlayPlan < handle
% mabr.stim.PlayPlan  A run's play matrix, described rather than materialized.
%
%   A run is a handful of waveforms placed at a list of onsets with a sign at
%   each, and a frame of it is the sum of the (at most a few) presentations
%   that overlap the frame. So the whole [N x 2] matrix -- which for a run
%   filling the ring buffer is 512 MB, allocated in the GUI process and then
%   serialized through the Prep message to the worker -- never needs to exist.
%   mabr.stim.Schedule.renderSpec builds one of these instead, mabr.acq.Engine
%   sends it (its size is the run's bank, not its duration), and
%   mabr.acq.worker_loop asks it for each frame as the device is ready for it.
%
%   Construction:
%       plan = mabr.stim.PlayPlan(signals,timings,onsets,stimIndex,polarity,N)
%           signals    {1 x nStim}  waveform per stimulus PRESENT in the run
%           timings    {1 x nStim}  explicit timing channel per stimulus, or
%                                   [] where MABR synthesizes a unit pulse over
%                                   the presentation (mabr.stim.StimulusSet)
%           onsets     [nPres x 1]  absolute sample of each presentation, in
%                                   ascending order (already padded)
%           stimIndex  [nPres x 1]  index into signals/timings per onset
%           polarity   [nPres x 1]  +1/-1 applied at each onset
%           N          total length of the run in samples (frame-padded)
%       plan = mabr.stim.PlayPlan.fromMatrix(X)   wraps an explicit [N x 2]
%       plan = mabr.stim.PlayPlan.fromSpec(spec)  spec.Plan, else fromMatrix(spec.PlayMatrix)
%
%   Reading:
%       y = plan.range(i0,i1)   [i1-i0+1 x 2] single: column 1 signal, column
%                               2 timing, for samples i0..i1 (1-based, absolute)
%       X = plan.matrix()       the whole [N x 2] -- tests and small blocks
%
%   range() performs the SAME summation, in the SAME presentation order, as a
%   whole-matrix render: each presentation adds pol*w to its span of column 1,
%   and either sets column 2 to 1 over its span (no explicit Timing) or takes
%   the max with its Timing. Overlapping presentations are therefore summed
%   exactly as before, and concatenating range() over any frame boundaries is
%   bit-identical to matrix(). A private cursor makes a sequential walk O(1)
%   per frame; it rewinds by itself if asked for an earlier range.
%
%   fromMatrix exists so callers that hand-build a small block -- the timing
%   loop-back self-test (mabr.ui.AcqController.verifyTimingLoop), the
%   verification scripts -- keep working unchanged; its range() is a slice.
%
%   See also mabr.stim.Schedule, mabr.acq.worker_loop.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        Signals   (1,:) cell   = {}
        Timings   (1,:) cell   = {}
        Onsets    (:,1) double = zeros(0,1)
        StimIndex (:,1) double = zeros(0,1)
        Polarity  (:,1) double = zeros(0,1)
        N         (1,1) double = 0
        MaxLen    (1,1) double = 0     % longest waveform -- the look-back a frame needs
        Matrix                 = []    % [N x 2] single when built fromMatrix, else []
    end

    properties (Access = private)
        KStart (1,1) double = 1        % first presentation that can reach the next range
        LastI0 (1,1) double = 0        % where the last range started (rewind detection)
    end

    methods
        function obj = PlayPlan(signals,timings,onsets,stimIndex,polarity,N)
            if nargin == 0, return; end
            assert(iscell(signals) && iscell(timings) && numel(signals) == numel(timings), ...
                'mabr:stim:PlayPlan:bank', ...
                'signals and timings must be cell arrays of the same length.');
            onsets    = double(onsets(:));
            stimIndex = double(stimIndex(:));
            polarity  = double(polarity(:));
            nPres     = numel(onsets);
            assert(numel(stimIndex) == nPres && numel(polarity) == nPres, ...
                'mabr:stim:PlayPlan:presentations', ...
                'onsets, stimIndex and polarity must have one element per presentation.');
            assert(all(diff(onsets) >= 0),'mabr:stim:PlayPlan:order', ...
                'Onsets must be in ascending order.');
            assert(all(stimIndex >= 1 & stimIndex <= numel(signals) & mod(stimIndex,1) == 0), ...
                'mabr:stim:PlayPlan:index', ...
                'stimIndex must index into signals (1..%d).',numel(signals));

            lens = zeros(1,numel(signals));
            for u = 1:numel(signals)
                w = signals{u}; t = timings{u};
                assert(isnumeric(w) && isvector(w) && ~isempty(w), ...
                    'mabr:stim:PlayPlan:signal','Stimulus %d has no waveform.',u);
                signals{u} = w(:);
                lens(u)    = numel(w);
                if ~isempty(t)
                    assert(isnumeric(t) && numel(t) == numel(w), ...
                        'mabr:stim:PlayPlan:timing', ...
                        'Stimulus %d: Timing must be the same length as its signal.',u);
                    timings{u} = t(:);
                else
                    timings{u} = [];
                end
            end

            obj.Signals   = signals;
            obj.Timings   = timings;
            obj.Onsets    = onsets;
            obj.StimIndex = stimIndex;
            obj.Polarity  = polarity;
            obj.MaxLen    = max([0 lens]);
            obj.N         = double(N);

            if nPres > 0
                % lens(stimIndex) takes the INDEX's shape when lens is a
                % scalar (a one-stimulus run) and lens's when it is not, so
                % force a column before it meets the column of onsets.
                L    = lens(stimIndex);
                last = max(onsets + L(:) - 1);
                assert(obj.N >= last,'mabr:stim:PlayPlan:length', ...
                    'N (%d) is shorter than the last presentation (ends at %d).',obj.N,last);
                assert(onsets(1) >= 1,'mabr:stim:PlayPlan:onset', ...
                    'Onsets are 1-based sample indices (first is %d).',onsets(1));
            end
        end

        function y = range(obj,i0,i1)
            % Samples i0..i1 of the run as [n x 2] single.
            assert(i0 >= 1 && i1 <= obj.N && i1 >= i0 - 1, ...
                'mabr:stim:PlayPlan:range', ...
                'Range [%d %d] is outside the run (1..%d).',i0,i1,obj.N);

            if ~isempty(obj.Matrix)
                y = obj.Matrix(i0:i1,:);
                return
            end

            n = i1 - i0 + 1;
            y = zeros(n,2,'single');
            if n < 1, return; end

            % The cursor only ever moves forward under a sequential walk; a
            % request for an earlier range (a test, a re-read) rewinds it.
            if i0 <= obj.LastI0, obj.KStart = 1; end
            obj.LastI0 = i0;

            nPres = numel(obj.Onsets);
            k     = obj.KStart;
            lo    = i0 - obj.MaxLen + 1;      % earliest onset that can still reach i0
            while k <= nPres && obj.Onsets(k) < lo, k = k + 1; end
            obj.KStart = k;

            while k <= nPres && obj.Onsets(k) <= i1
                o = obj.Onsets(k);
                u = obj.StimIndex(k);
                w = obj.Signals{u};
                e = o + numel(w) - 1;
                if e >= i0
                    a  = max(o,i0);  b  = min(e,i1);     % overlap, absolute
                    wa = a - o + 1;  wb = b - o + 1;     % ... within the waveform
                    ya = a - i0 + 1; yb = b - i0 + 1;    % ... within the frame
                    % Same arithmetic as the whole-matrix render: overlapping
                    % presentations are summed, in presentation order.
                    y(ya:yb,1) = y(ya:yb,1) + obj.Polarity(k).*w(wa:wb);
                    t = obj.Timings{u};
                    if isempty(t)
                        y(ya:yb,2) = 1;
                    else
                        y(ya:yb,2) = max(y(ya:yb,2),t(wa:wb));
                    end
                end
                k = k + 1;
            end
        end

        function X = matrix(obj)
            % The whole [N x 2] play matrix. For tests and small blocks: a
            % run that fills the ring buffer is 512 MB here.
            if ~isempty(obj.Matrix)
                X = obj.Matrix;
            elseif obj.N < 1
                X = zeros(0,2,'single');
            else
                X = obj.range(1,obj.N);
            end
        end
    end

    methods (Static)
        function obj = fromMatrix(X)
            % Wrap an explicit play matrix ([N x 2], column 1 signal, column 2
            % timing). range() is then a plain slice.
            assert(isnumeric(X) && ismatrix(X) && size(X,2) == 2, ...
                'mabr:stim:PlayPlan:matrix','A play matrix is [N x 2].');
            obj = mabr.stim.PlayPlan();
            obj.Matrix = single(X);
            obj.N      = size(X,1);
        end

        function obj = fromSpec(spec)
            % The frame source for a render spec: its Plan, or the explicit
            % PlayMatrix a hand-built spec carries. The one place the worker
            % decides between the two.
            if isfield(spec,'Plan') && ~isempty(spec.Plan)
                obj = spec.Plan;
                assert(isa(obj,'mabr.stim.PlayPlan'),'mabr:stim:PlayPlan:spec', ...
                    'spec.Plan must be a mabr.stim.PlayPlan (got %s).',class(obj));
            elseif isfield(spec,'PlayMatrix')
                obj = mabr.stim.PlayPlan.fromMatrix(spec.PlayMatrix);
            else
                error('mabr:stim:PlayPlan:spec', ...
                    'A render spec needs a Plan or a PlayMatrix.');
            end
        end
    end
end
