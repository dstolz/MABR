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
%       plan = mabr.stim.PlayPlan(...,N,bg)   the same run on an ONGOING
%           BACKGROUND (docs/Background.md). bg is what backgroundSpec
%           returns: a tiled loop or a closed-form tone, the run-edge ramp,
%           and per stimulus a gain envelope and/or phase deviation that
%           presentation applies to the background. Column 1 is then
%
%               env(i) * G(i) * B(i, theta(i))  +  sum of pol*w
%
%           The timing column is never touched by it.
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
%   The background term is a pure function of the ABSOLUTE sample index (and
%   of the presentations that overlap it, taken in the same order), so it too
%   is the same whatever the frame boundaries: exactly for a loop -- indexing
%   and multiplication -- and to the rounding of sin() for a tone, which MATLAB
%   may evaluate a last bit differently for arrays of different lengths.
%   backgroundLead and backgroundTail render that term alone, for the indices
%   just before or from a point, faded in or out: what the worker plays, and
%   never records, when a block resumes from a pause or stops early.
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
        Background             = []    % [] or the struct backgroundSpec returns
    end

    properties (Access = private)
        KStart (1,1) double = 1        % first presentation that can reach the next range
        LastI0 (1,1) double = 0        % where the last range started (rewind detection)

        % A tone background keeps the phase a frequency modulation left it
        % at. PhaseEnds are the last samples of the presentations that carry
        % a phase deviation, ascending; PhaseSums the running total of their
        % final values (wrapped to 2*pi), so the offset in force at sample i
        % is PhaseSums(nnz(PhaseEnds < i)) -- for any i, in any order.
        PhaseEnds (:,1) double = zeros(0,1)
        PhaseSums (:,1) double = zeros(0,1)
        RampUp    (:,1) double = zeros(0,1)   % sin^2 rise over Background.Ramp samples
    end

    methods
        function obj = PlayPlan(signals,timings,onsets,stimIndex,polarity,N,bg)
            if nargin == 0, return; end
            if nargin < 7, bg = []; end
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

            if ~isempty(bg)
                obj.Background = mabr.stim.PlayPlan.checkBackground(bg,lens);
                obj.indexBackground();
            end
        end

        function tf = hasBackground(obj)
            % True when the run plays on an ongoing background.
            tf = ~isempty(obj.Background);
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

            % The ongoing background, if the run has one, is what the
            % presentations are then added to.
            if ~isempty(obj.Background)
                y(:,1) = single(obj.backgroundTerm(i0,i1,k));
            end

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

        function y = backgroundTail(obj,i0,n)
            % n samples of the background alone, continuing from sample i0
            % and faded to silence over the ramp: [n x 2] single, timing
            % column zero. What the worker plays -- and does not record --
            % when a block stops before its end, so the background does not
            % cut off mid-sample. i0 is the first sample NOT yet played.
            y = zeros(max(0,n),2,'single');
            if isempty(obj.Background) || n < 1, return; end
            i0 = max(1,i0);
            b  = obj.backgroundTerm(i0,i0+n-1,obj.firstReaching(i0));
            R  = min(max(obj.Background.Ramp,1),n);
            fade      = zeros(n,1);
            fade(1:R) = cos(pi/2.*(0:R-1)'./R).^2;
            y(:,1)    = single(fade.*b);
        end

        function y = backgroundLead(obj,i0,n,a,b)
            % The n samples of the background alone that PRECEDE sample i0
            % (i0-n .. i0-1), faded in from silence: [n x 2] single, timing
            % column zero, zeros where the run has not begun or is over.
            % Played, and not recorded, before a block resumes from a pause:
            % it runs straight into sample i0, so the presentations after a
            % pause follow a steady background as those before it did.
            %
            % backgroundLead(i0,n,a,b) returns only samples a..b of those n
            % ([b-a+1 x 2]). That is how the worker plays it: a frame at a
            % time, each rendered as the device is ready for it, as the run
            % itself is. Rendered whole, a lead-in of seconds is that much
            % audio built between two device calls, with the device unfed
            % meanwhile.
            if nargin < 4, a = 1; b = n; end
            y = zeros(max(0,b - a + 1),2,'single');
            if isempty(obj.Background) || n < 1 || b < a, return; end
            hi = min(i0 - 1,obj.N);         % the run's samples the lead holds:
            lo = max(i0 - n,1);             % lo..hi, of i0-n..i0-1
            if hi < lo, return; end
            s  = i0 - n + a - 1;            % the run sample that lead sample a is
            sa = max(s,lo);
            se = min(i0 - n + b - 1,hi);
            if se < sa, return; end
            t = obj.backgroundTerm(sa,se,obj.firstReaching(sa));
            % The fade is over the first samples the lead HOLDS, wherever
            % this window falls among them.
            R  = min(max(obj.Background.Ramp,1),hi - lo + 1);
            q  = (sa - lo:se - lo)';
            fade     = ones(numel(q),1);
            in       = q < R;
            fade(in) = sin(pi/2.*q(in)./R).^2;
            y(sa - s + 1:se - s + 1,1) = single(fade.*t);
        end
    end

    methods (Access = private)
        function indexBackground(obj)
            % Precompute what makes the background term random-access: the
            % run-edge ramp as a table (so every frame reads the same values
            % rather than recomputing them), and for a tone the phase each
            % frequency-modulating presentation leaves behind.
            bg = obj.Background;
            R  = bg.Ramp;
            obj.RampUp = sin(pi/2.*(0:R-1)'./max(R,1)).^2;

            obj.PhaseEnds = zeros(0,1);
            obj.PhaseSums = zeros(0,1);
            if ~strcmp(bg.Kind,'tone'), return; end
            ends = zeros(0,1); vals = zeros(0,1);
            for k = 1:numel(obj.Onsets)
                p = bg.Phases{obj.StimIndex(k)};
                if isempty(p), continue; end
                ends(end+1,1) = obj.Onsets(k) + numel(p) - 1; %#ok<AGROW>
                vals(end+1,1) = p(end);                        %#ok<AGROW>
            end
            if isempty(ends), return; end
            [ends,order]  = sort(ends);
            obj.PhaseEnds = ends;
            obj.PhaseSums = mod(cumsum(vals(order)),2*pi);
        end

        function k = firstReaching(obj,i0)
            % First presentation whose waveform can reach sample i0, found
            % without moving the cursor range() walks with.
            k = find(obj.Onsets >= i0 - obj.MaxLen + 1,1);
            if isempty(k), k = numel(obj.Onsets) + 1; end
        end

        function b = backgroundTerm(obj,i0,i1,kFirst)
            % env .* G .* B(theta) for samples i0..i1 as [n x 1] double.
            % kFirst is the first presentation that can reach i0. Samples
            % past the end of the run are silence.
            bg  = obj.Background;
            idx = (i0:i1)';
            n   = numel(idx);
            N   = obj.N;

            % What the presentations overlapping this range do to the
            % background, taken in presentation order -- the order a
            % whole-run render takes them in.
            isTone = strcmp(bg.Kind,'tone');
            G  = ones(n,1);
            TH = zeros(n,1);
            nPres = numel(obj.Onsets);
            k = kFirst;
            while k <= nPres && obj.Onsets(k) <= i1
                u = obj.StimIndex(k);
                g = bg.Gains{u};
                p = bg.Phases{u};
                if ~isempty(g) || ~isempty(p)
                    o = obj.Onsets(k);
                    e = o + numel(obj.Signals{u}) - 1;
                    if e >= i0
                        a  = max(o,i0);  c  = min(e,i1);
                        wa = a - o + 1;  wb = c - o + 1;
                        ya = a - i0 + 1; yb = c - i0 + 1;
                        if ~isempty(g), G(ya:yb)  = G(ya:yb).*g(wa:wb); end
                        if ~isempty(p), TH(ya:yb) = TH(ya:yb) + p(wa:wb); end
                    end
                end
                k = k + 1;
            end

            pos = idx - 1 + bg.Offset;
            if isTone
                % The phase earlier frequency modulations left the tone at.
                if ~isempty(obj.PhaseEnds)
                    c0  = nnz(obj.PhaseEnds < i0);
                    off = zeros(n,1);
                    if c0 > 0, off(:) = obj.PhaseSums(c0); end
                    c = c0 + 1;
                    while c <= numel(obj.PhaseEnds) && obj.PhaseEnds(c) < i1
                        off(obj.PhaseEnds(c) - i0 + 2:end) = obj.PhaseSums(c);
                        c = c + 1;
                    end
                    TH = TH + off;
                end
                % Whole cycles are removed before the 2*pi, so the phase
                % keeps its precision however far into the run the sample is.
                b = bg.Amplitude.*sin(2*pi.*mod(bg.Frequency.*pos./bg.SampleRate,1) + TH);
            else
                b = double(bg.Loop(mod(pos,numel(bg.Loop)) + 1));
            end
            b = G.*b;

            % Run edges: up over the first Ramp samples, down over the last.
            R = bg.Ramp;
            if R > 0
                in = idx <= R;
                if any(in), b(in) = b(in).*obj.RampUp(idx(in)); end
                out = idx > N - R & idx <= N;
                if any(out), b(out) = b(out).*obj.RampUp(N - idx(out) + 1); end
            end
            b(idx > N) = 0;
        end
    end

    methods (Static)
        function bg = backgroundSpec(B,Fs,gains,phases,offset,ramp)
            % The background argument of the constructor, from one element of
            % mabr.stim.StimulusSet.Backgrounds:
            %   B       the background ([] returns [], i.e. none)
            %   Fs      sample rate of the run
            %   gains   {1 x nStim} gain envelope per stimulus in the run, or []
            %   phases  {1 x nStim} phase deviation per stimulus, or []
            %   offset  sample of the background the run's first sample plays
            %           (0-based: where in the loop, or how far into the tone)
            %   ramp    samples of fade at each end of the run (0 = none)
            bg = [];
            if isempty(B), return; end
            if nargin < 5 || isempty(offset), offset = 0; end
            if nargin < 6 || isempty(ramp),   ramp   = 0; end
            bg = struct('Kind',B.Kind,'Loop',B.signal, ...
                'Frequency',B.Frequency,'Amplitude',B.Amplitude, ...
                'SampleRate',Fs,'Offset',offset,'Ramp',ramp, ...
                'Gains',{gains},'Phases',{phases});
        end

        function bg = checkBackground(bg,lens)
            % Validate a background spec against the run's waveforms (lens =
            % their lengths) and put it in the form backgroundTerm reads.
            nStim = numel(lens);
            assert(isstruct(bg) && isscalar(bg) && isfield(bg,'Kind') ...
                   && any(strcmp(bg.Kind,{'loop','tone'})), ...
                'mabr:stim:PlayPlan:background', ...
                'A background is a struct whose Kind is ''loop'' or ''tone''.');
            if strcmp(bg.Kind,'loop')
                assert(isnumeric(bg.Loop) && numel(bg.Loop) >= 2, ...
                    'mabr:stim:PlayPlan:background','A loop background needs its Loop.');
                bg.Loop = single(bg.Loop(:));
            else
                assert(isscalar(bg.Frequency) && isscalar(bg.Amplitude) ...
                       && isscalar(bg.SampleRate) && bg.SampleRate > 0, ...
                    'mabr:stim:PlayPlan:background', ...
                    'A tone background needs Frequency, Amplitude and SampleRate.');
            end
            bg.Offset = double(bg.Offset);
            bg.Ramp   = double(bg.Ramp);
            assert(isscalar(bg.Offset) && bg.Offset >= 0 && mod(bg.Offset,1) == 0 ...
                   && isscalar(bg.Ramp) && bg.Ramp >= 0 && mod(bg.Ramp,1) == 0, ...
                'mabr:stim:PlayPlan:background', ...
                'A background''s Offset and Ramp are whole numbers of samples.');

            names = {'Gains','Phases'};
            for f = 1:2
                c = bg.(names{f});
                if isempty(c), c = cell(1,nStim); end
                assert(iscell(c) && numel(c) == nStim,'mabr:stim:PlayPlan:background', ...
                    '%s must hold one entry per stimulus in the run.',names{f});
                for u = 1:nStim
                    if isempty(c{u}), c{u} = []; continue; end
                    assert(numel(c{u}) == lens(u),'mabr:stim:PlayPlan:background', ...
                        '%s{%d} must be the length of its signal (%d).',names{f},u,lens(u));
                    c{u} = double(c{u}(:));
                end
                bg.(names{f}) = c;
            end
            assert(strcmp(bg.Kind,'tone') || all(cellfun(@isempty,bg.Phases)), ...
                'mabr:stim:PlayPlan:background', ...
                'A phase deviation needs a tone background.');
        end

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
