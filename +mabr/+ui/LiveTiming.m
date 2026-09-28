classdef LiveTiming < handle
% mabr.ui.LiveTiming  Where one run's live-view ticks spent their time.
%
%   mabr.ui.AcqController's LiveTimer runs 'fixedSpacing' at a 50 ms period,
%   so the rate the live view actually redraws at is 1/(period + whatever the
%   tick cost) -- and "whatever the tick cost" includes every other callback
%   MATLAB chose to run inside it, since the render ends in a drawnow and a
%   drawnow services the queue. A view that redraws at 1 Hz is therefore
%   either doing ~1 s of its own work per tick or sharing the one GUI thread
%   with something that is, and which of those it is decides the fix. This
%   records enough of every tick to tell them apart, and says so once per run.
%
%   Per tick it keeps:
%       start / end     s since reset() -- so interval = diff(start) and the
%                       GAP between ticks = start(k) - end(k-1). Under
%                       fixedSpacing the gap is the period plus whatever ran on
%                       the thread between ticks (other windows' timers, the
%                       aux tick, queue callbacks).
%       stats           fetching the statistics: Pipeline.step in-process, or
%                       reading the DSP worker's publish
%       render          inside LivePlot.updateStats, broken down from
%                       LivePlot.RenderTiming into prep (resolving the layout,
%                       the means, writing the graphics objects), drawnow
%                       (the graphics update AND any callbacks MATLAB runs
%                       inside it), and gutters (the label-room fit after it)
%       drew            whether anything was drawn at all -- a worker-served
%                       tick with nothing new published returns without one
%   and per aux tick its duration and whether it ran NESTED inside a live
%   tick (i.e. from within the live render's drawnow).
%
%   Recording is a handful of tic/toc calls per tick and costs nothing
%   measurable; it is always on.
%
%       T = mabr.ui.LiveTiming();
%       T.reset(runId,0.05);
%       T.beginTick(); ... T.stats(dt,'local'); ... T.render(dt,lp.RenderTiming);
%       T.endTick(nSweeps);
%       S = T.summary();     % struct, with S.Text the human-readable report
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        RunId  (1,1) double = 0
        Period (1,1) double = 0.05     % s, the live timer's configured period
        Source (1,:) char   = ''       % 'worker' / 'local', as of the last tick
        Start      = zeros(0,1)        % s since reset(), per tick
        End        = zeros(0,1)
        Stats      = zeros(0,1)        % s
        Render     = zeros(0,1)        % s, 0 on a tick that drew nothing
        Prep       = zeros(0,1)
        Drawnow    = zeros(0,1)
        Gutters    = zeros(0,1)
        Drew       = false(0,1)
        NumSweeps  = zeros(0,1)
        Rebuilds   (1,1) double = 0    % mean axes rebuilt (a new arrangement)
        Measures   (1,1) double = 0    % label gutters re-measured
        NumAxes    (1,1) double = 0    % as of the last render
        AuxDur     = zeros(0,1)        % s, per aux tick
        AuxNested  = false(0,1)
        % True between beginTick and endTick, so a callback that runs from
        % inside the live tick (the aux tick, via the render's drawnow) can
        % say that it did.
        InTick     (1,1) logical = false
    end

    properties (Access = private)
        T0  = uint64(0)
        Cur = struct()
    end

    methods
        function obj = LiveTiming()
            obj.reset(0,0.05);
        end

        function reset(obj,runId,period)
            if nargin >= 2 && ~isempty(runId),  obj.RunId  = runId;  end
            if nargin >= 3 && ~isempty(period), obj.Period = period; end
            obj.Source    = '';
            obj.Start     = zeros(0,1);
            obj.End       = zeros(0,1);
            obj.Stats     = zeros(0,1);
            obj.Render    = zeros(0,1);
            obj.Prep      = zeros(0,1);
            obj.Drawnow   = zeros(0,1);
            obj.Gutters   = zeros(0,1);
            obj.Drew      = false(0,1);
            obj.NumSweeps = zeros(0,1);
            obj.Rebuilds  = 0;
            obj.Measures  = 0;
            obj.NumAxes   = 0;
            obj.AuxDur    = zeros(0,1);
            obj.AuxNested = false(0,1);
            obj.InTick    = false;
            obj.T0        = tic;
            obj.Cur       = obj.blankTick();
        end

        % --- Recording ------------------------------------------------------
        function beginTick(obj)
            obj.Cur       = obj.blankTick();
            obj.Cur.start = toc(obj.T0);
            obj.InTick    = true;
        end

        function stats(obj,dt,source)
            % source: 'worker' (read the DSP worker's publish) or 'local'
            % (stepped this process's own pipeline).
            obj.Cur.stats = dt;
            if nargin >= 3 && ~isempty(source), obj.Source = source; end
        end

        function render(obj,dt,rt)
            % dt: seconds in LivePlot.updateStats; rt: its RenderTiming.
            obj.Cur.render = dt;
            obj.Cur.drew   = true;
            if nargin < 3 || ~isstruct(rt), return; end
            obj.Cur.prep    = rt.Prep;
            obj.Cur.drawnow = rt.Drawnow;
            obj.Cur.gutters = rt.Gutters;
            obj.Rebuilds    = obj.Rebuilds + rt.Rebuilds;
            obj.Measures    = obj.Measures + rt.Measures;
            obj.NumAxes     = rt.NumAxes;
        end

        function endTick(obj,nSweeps)
            % Called whether or not the tick drew (or threw), so every tick
            % is counted and the gaps between them are real.
            if ~obj.InTick, return; end
            obj.InTick = false;
            c = obj.Cur;
            if nargin < 2 || isempty(nSweeps), nSweeps = NaN; end
            obj.Start(end+1,1)     = c.start;
            obj.End(end+1,1)       = toc(obj.T0);
            obj.Stats(end+1,1)     = c.stats;
            obj.Render(end+1,1)    = c.render;
            obj.Prep(end+1,1)      = c.prep;
            obj.Drawnow(end+1,1)   = c.drawnow;
            obj.Gutters(end+1,1)   = c.gutters;
            obj.Drew(end+1,1)      = c.drew;
            obj.NumSweeps(end+1,1) = nSweeps;
        end

        function aux(obj,dt)
            obj.AuxDur(end+1,1)    = dt;
            obj.AuxNested(end+1,1) = obj.InTick;
        end

        % --- Reporting ------------------------------------------------------
        function S = summary(obj)
            % Percentiles are [median p95 max], in MILLISECONDS. Empty-safe:
            % a run that never ticked reports zero ticks and NaNs.
            n  = numel(obj.Start);
            d  = obj.Drew;
            S  = struct();
            S.RunId      = obj.RunId;
            S.Source     = obj.Source;
            S.Ticks      = n;
            S.Drawn      = nnz(d);
            S.Duration   = 0;
            if n > 0, S.Duration = obj.End(end) - obj.Start(1); end
            S.TargetHz   = 1/obj.Period;
            S.PeriodMs   = 1000*obj.Period;
            S.TickHz     = NaN;
            if n > 1, S.TickHz = (n-1)/(obj.Start(end) - obj.Start(1)); end
            S.RealizedHz = NaN;
            sd = obj.Start(d);
            if numel(sd) > 1, S.RealizedHz = (numel(sd)-1)/(sd(end) - sd(1)); end

            ms = @(x) 1000*mabr.ui.LiveTiming.pct(x);
            S.Interval   = ms(diff(obj.Start));
            S.FrameGap   = ms(diff(sd));                   % between DRAWN ticks
            S.Busy       = ms(obj.End - obj.Start);
            S.Gap        = ms(obj.Start(2:end) - obj.End(1:end-1));
            S.Stats      = ms(obj.Stats);
            S.Render     = ms(obj.Render(d));
            S.Prep       = ms(obj.Prep(d));
            S.Drawnow    = ms(obj.Drawnow(d));
            S.Gutters    = ms(obj.Gutters(d));
            S.Rebuilds   = obj.Rebuilds;
            S.Measures   = obj.Measures;
            S.NumAxes    = obj.NumAxes;
            S.AuxTicks   = numel(obj.AuxDur);
            S.Aux        = ms(obj.AuxDur);
            S.AuxNested  = nnz(obj.AuxNested);
            S.Sweeps     = NaN;
            if n > 0, S.Sweeps = obj.NumSweeps(end); end
            S.Verdict    = mabr.ui.LiveTiming.verdict(S);
            S.Text       = mabr.ui.LiveTiming.format(S);
        end
    end

    methods (Static)
        function p = pct(x)
            % [median p95 max] without the Statistics toolbox (see
            % mabr.Config.RequiredToolboxes). NaNs for an empty sample.
            x = sort(x(isfinite(x)));
            if isempty(x), p = [NaN NaN NaN]; return; end
            m = numel(x);
            p = [median(x) x(max(1,ceil(0.95*m))) x(end)];
        end

        function v = verdict(S)
            % One line naming where the time went, from the medians. Only a
            % pointer to the numbers beside it -- they are the evidence.
            if S.Ticks < 3
                v = 'too few ticks to judge'; return
            end
            if S.RealizedHz >= 0.75*S.TargetHz
                v = 'keeping up'; return
            end
            busy   = S.Busy(1);
            extra  = S.Gap(1) - S.PeriodMs;     % thread time between ticks
            if strcmp(S.Source,'worker') && S.Drawn < 0.5*S.Ticks && busy < S.PeriodMs
                v = ['ticks are cheap but most found nothing new: the DSP worker ' ...
                     'is publishing slower than the live timer asks'];
                return
            end
            if extra > busy
                v = ['most time is spent BETWEEN ticks: other callbacks on the GUI ' ...
                     'thread (analysis windows, progress monitor, aux tick)'];
                return
            end
            parts = [S.Stats(1) S.Prep(1) S.Drawnow(1) S.Gutters(1)];
            parts(~isfinite(parts)) = 0;
            [~,k] = max(parts);
            switch k
                case 1, v = 'most time is fetching statistics (the pipeline step)';
                case 2, v = 'most time is building the frame in LivePlot (before drawnow)';
                case 3
                    v = ['most time is in drawnow: the graphics update itself, plus ' ...
                         'any callbacks MATLAB ran inside it'];
                    if S.AuxNested > 0
                        v = sprintf('%s (%d aux ticks ran nested there)',v,S.AuxNested);
                    end
                otherwise
                    v = 'most time is re-fitting the axis label gutters after drawnow';
            end
        end

        function txt = format(S)
            f = @(p) sprintf('%.0f / %.0f / %.0f',p(1),p(2),p(3));
            L = {};
            L{end+1} = sprintf(['Live view timing, run %d (%s): drew %.1f Hz ' ...
                '(target %.0f Hz); %d ticks, %d drew, %.1f s, %g sweeps'], ...
                S.RunId,S.Source,S.RealizedHz,S.TargetHz,S.Ticks,S.Drawn, ...
                S.Duration,S.Sweeps);
            L{end+1} = sprintf('  ms, median / p95 / max -- period %.0f ms, fixedSpacing',S.PeriodMs);
            L{end+1} = sprintf('    between drawn frames  %s',f(S.FrameGap));
            L{end+1} = sprintf('    tick interval         %s',f(S.Interval));
            L{end+1} = sprintf('      busy in tick        %s',f(S.Busy));
            L{end+1} = sprintf('      gap after tick      %s   (period + other work on the thread)',f(S.Gap));
            L{end+1} = sprintf('    stats fetch           %s',f(S.Stats));
            L{end+1} = sprintf('    render (drawn ticks)  %s',f(S.Render));
            L{end+1} = sprintf('      prep                %s',f(S.Prep));
            L{end+1} = sprintf('      drawnow             %s   (includes callbacks run inside it)',f(S.Drawnow));
            L{end+1} = sprintf('      label gutters       %s',f(S.Gutters));
            L{end+1} = sprintf('    aux ticks %d, %s ms; %d nested inside a live tick', ...
                S.AuxTicks,f(S.Aux),S.AuxNested);
            L{end+1} = sprintf('    axes %d; mean axes rebuilt %dx; gutters re-measured %dx', ...
                S.NumAxes,S.Rebuilds,S.Measures);
            L{end+1} = sprintf('  -> %s',S.Verdict);
            txt = strjoin(L,newline);
        end
    end

    methods (Static, Access = private)
        function c = blankTick()
            c = struct('start',NaN,'stats',NaN,'render',0,'prep',NaN, ...
                       'drawnow',NaN,'gutters',NaN,'drew',false);
        end
    end
end
