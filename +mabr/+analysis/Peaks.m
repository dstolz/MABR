classdef Peaks
% mabr.analysis.Peaks  Wave peaks and troughs of averaged ABR waveforms.
%
%   Picks ABR waves I-V (or any waves you name) on averaged waveforms, tracks
%   them down a level series, and turns the picks into the measures a study
%   reports. Pure and static like the rest of this package: every function
%   reads its arguments and returns a value, and none of them loops over
%   conditions or sessions -- mabr.analysis.Session.pickPeaks does that.
%
%       o = settings.latencyOffset();                            % ms (0 = none)
%       W = mabr.analysis.Peaks.wavesFor(mabr.analysis.Peaks.defaultWaves(),"Tone",8);
%       P = mabr.analysis.Peaks.pick(tMs,y,W);                  % one waveform
%       T = mabr.analysis.Peaks.track(tMs,Y,levels,W);          % a level series
%       [M,G] = mabr.analysis.Peaks.derived(T);                  % IPLs, I/O slopes
%       lat = mabr.analysis.Peaks.reported(T.PeakLatency,o);     % re sound arrival
%
%   A WAVE is one element of a struct array: Name (string), Enabled
%   (logical), TMin and TMax (the search window, ms re the timing pulse --
%   see below), Expected (ms, where the peak is expected), LatencyShift (ms per
%   dB the peak moves later as level falls) and Stimulus ("" = every
%   stimulus, or the stimulus class the row is for, so clicks and tone pips
%   can carry different windows). defaultWaves() is the rodent starting point:
%   the mabr.ui.TraceInspector windows, each with its own latency shift.
%   mabr.analysis.Settings carries its own literal copy of it.
%
%   PICKING follows the EPL / Buran `abr` scheme (BSD-3; Buran et al., the
%   Eaton-Peabody Laboratories' analysis program): candidates are the local
%   maxima of the waveform, and each wave scores every candidate in its
%   window by its prominence and by a latency prior,
%
%       score = prominence/max(prominence in the window) + lambda*prior/max(prior)
%
%   both terms in [0 1]. The waves are then ASSIGNED JOINTLY: of every way of
%   giving the waves distinct candidates in time order, each at least
%   MinSeparation after the one before (a wave may be left without one), the
%   one with the largest summed score wins (dynamic programming over the
%   candidates, exact). A candidate therefore goes to the wave whose window
%   and track explain it best, not to whichever wave asks first: taken in
%   turn, an early wave whose own peak was missing took the next wave's
%   peak, and that wave, now required to come later still, was lost.
%     - Where a wave is searched in its own window -- the loudest level, or
%       any level with no louder pick of it -- the prior is a Gaussian
%       N(Expected, (TMax-TMin)/4) and lambda is TopPriorWeight (0.5):
%       PROMINENCE LEADS and the window centre breaks near-ties. With the
%       window centre weighted five times over, a small peak a fifth of a
%       millisecond nearer the centre beat a wave I a fifth more prominent,
%       and one animal's wave I came out 0.35 ms apart in two sessions.
%     - Down the series each wave is TRACKED from the latency prev it had at
%       the closest louder level Lprev. It is EXPECTED at prev +
%       LatencyShift*(Lprev - L), and the prior is a skew-normal (shape 3,
%       scale 0.1 ms) located there, with lambda PriorWeight (5): there the
%       track leads, since at low levels noise peaks are as prominent as the
%       wave. The hard window is [prev - TrackEarly, prev + TrackLate +
%       LatencyShift*(Lprev - L)], and it ends MinSeparation before the
%       expected latency of the next wave being tracked (from a pick at
%       least as recent as this wave's): a wave comes before the next one,
%       so it is never searched where that one is expected. (When the
%       earlier wave's track is the more recent, the later wave's window
%       starts MinSeparation after it instead.)
%       Latency grows as level falls, and faster for the later waves --
%       0.015 ms/dB for wave I to 0.03 for wave V in the defaults, steeper
%       still near threshold (Scimemi et al. 2014) -- so a prior left at prev
%       favours whatever peak sits where the wave USED to be, and a window
%       allowing 0.01 ms/dB for every wave loses waves IV and V or hands them
%       the wrong label.
%     - A MANUAL anchor replaces the pick at its level and is what the levels
%       below it track from; an ABSENT anchor leaves that level without a
%       pick and changes nothing below it. Automatic troughs are always
%       recomputed between the (possibly moved) peaks; a manual trough stays.
%   Every latency and value is refined below one sample by parabolic
%   interpolation (refine), because at 12 kHz one sample is 83 us -- the size
%   of the latency effects a noise-exposure study is looking for.
%
%   WINDOWS AND LATENCIES ARE IN THE RECORDING'S TIME. Time zero of a
%   recording is the timing pulse -- the ELECTRICAL onset of the stimulus --
%   and the sound reaches the eardrum later by its travel time (10 cm of air
%   is 0.29 ms), plus whatever else the rig adds. Picking and tracking run in
%   the recording's time, with wave windows in that time too (the
%   TraceInspector windows were drawn up on recordings), and every latency
%   they return is raw, re the onset. The latency offset comes off in
%   exactly one place, reported(latRaw,o), at display and export time, so
%   setting a conduction delay moves every reported latency by exactly
%   itself and changes no pick. (wavesFor(...,Offset=o) can still move a set
%   of windows, for windows written in some other time; Session does not.)
%
%   No Statistics toolbox: the Gaussian and skew-normal densities are written
%   out (the normal CDF through erfc) and percentiles come from
%   mabr.analysis.Stats.
%
%   See also mabr.analysis.SingleTrial, mabr.analysis.Session,
%   mabr.ui.TraceInspector

    properties (Constant)
        % Okabe & Ito (2008) colour-blind-safe palette, in the order the
        % waves take it.
        Vermillion    = [213  94   0]/255
        Orange        = [230 159   0]/255
        BluishGreen   = [  0 158 115]/255
        SkyBlue       = [ 86 180 233]/255
        Blue          = [  0 114 178]/255
        ReddishPurple = [204 121 167]/255
        Black         = [  0   0   0]

        % The tracking prior (EPL): skew-normal with this shape and scale (ms).
        PriorShape = 3
        PriorScale = 0.1

        % Weight of the latency prior against prominence in a pick's score
        % (both scaled to [0 1]): on a TRACKED level, where the track leads...
        PriorWeight = 5

        % ...and where a wave is searched in its own window (the loudest
        % level, or no louder pick of it), where prominence leads and the
        % window centre breaks near-ties.
        TopPriorWeight = 0.5

        % ms after the last picked peak that its trough is looked for.
        TroughSpan = 1.0

        % ms either side of a full-data trough a bootstrap replicate re-picks it.
        TroughWindow = 0.5

        % LatencyShift (ms/dB) of a wave that does not state its own -- one a
        % user adds to the table. mabr.analysis.Settings holds the same literal.
        AddedLatencyShift = 0.02
    end

    methods (Static)
        % =================================================================
        %  Waves
        % =================================================================
        function W = defaultWaves()
            % The five rodent ABR waves: I-V with the TraceInspector windows.
            %
            %   W  (returned) 1x5 struct array: Name, Enabled, TMin, TMax,
            %      Expected (the window centre), LatencyShift, Stimulus ("" =
            %      every stimulus)
            %
            % LatencyShift grows from wave to wave -- 0.015, 0.018, 0.020,
            % 0.025 and 0.030 ms/dB for I-V -- because the later waves'
            % latencies grow faster as level falls (Scimemi et al. 2014, and
            % the 8 kHz series of the noise-exposure data this was written
            % for): one 0.01 ms/dB for every wave allowed wave V a quarter of
            % the 0.3 ms it moves in a 10 dB step and lost it. A wave the user
            % adds without one gets AddedLatencyShift (0.02 ms/dB).
            %
            % Literal numbers on purpose: mabr.analysis.Settings holds the same
            % literal, and a test holds the two equal with isequal.
            W = struct( ...
                'Name',         {"I","II","III","IV","V"}, ...
                'Enabled',      {true,true,true,true,true}, ...
                'TMin',         {1.0,1.8,2.6,3.4,4.2}, ...
                'TMax',         {2.0,2.8,3.6,4.6,5.6}, ...
                'Expected',     {1.5,2.3,3.1,4.0,4.9}, ...
                'LatencyShift', {0.015,0.018,0.020,0.025,0.030}, ...
                'Stimulus',     {"","","","",""});
        end

        function why = nameProblem(name,used)
            % Why a wave cannot be called name, or '' if it can.
            %
            % The rule mabr.ui.TraceInspector applies: a name is required, it
            % may not be all digits (that is how unnamed peak markers are
            % numbered, so "1" would be read back as a marker nobody named),
            % and no two waves may share one in any case -- picks, anchors and
            % exported columns are matched by it.
            %
            %   name  the proposed name (text)
            %   used  the OTHER waves' names (text array; default none)
            %   why   (returned) char: '' or the reason
            arguments
                name
                used = strings(0,1)
            end
            name = string(name);
            if isempty(name) || all(ismissing(name)), name = ""; end
            name = strtrim(char(name(1)));
            used = string(used);
            used = strtrim(used(~ismissing(used)));
            why = '';
            if isempty(name)
                why = 'A wave needs a name.';
            elseif ~isempty(regexp(name,'^\d+$','once'))
                why = sprintf(['"%s" is a plain number, which is how unnamed peak ' ...
                    'markers are numbered. Use a letter or a name (VI, A, N1 ...).'],name);
            elseif any(strcmpi(name,cellstr(used)))
                why = sprintf('There is already a wave named "%s".',name);
            end
        end

        function W = wavesFor(waves,stimulus,freqKHz,opts)
            % The waves that apply to one stimulus, shifted for its frequency.
            %
            % The rows whose Stimulus is this stimulus when there are any, else
            % the rows for every stimulus (""). For a finite positive
            % frequency, TMin, TMax and Expected move LATER by OctaveShift ms
            % for every octave below RefFrequency (earlier above it): a low
            % tone pip excites a more apical, slower part of the cochlea, and
            % a fixed window would put the same peak under two names across
            % frequency.
            %
            % Then every window moves later by Offset, whatever the stimulus
            % -- for windows written in a time other than the recording's.
            % Session.pickPeaks gives none: its windows are in the recording's
            % time, and the latency offset (conduction delay plus system
            % offset) is applied by reported() alone, so that a delay changes
            % no pick. Offset 0 changes nothing.
            %
            %   waves     wave struct array (or table)
            %   stimulus  stimulus class ("" = generic rows only)
            %   freqKHz   frequency, kHz (NaN = no shift, e.g. a click)
            %   opts.OctaveShift   ms per octave (default 0.15)
            %   opts.RefFrequency  kHz at which the windows apply as written
            %                      (default 16)
            %   opts.Offset        ms added to TMin, TMax and Expected
            %                      (default 0). Not a number errors
            %                      mabr:analysis:Peaks:offset -- windows at NaN
            %                      would find no peak and say nothing.
            %   W  (returned) the selected, shifted wave struct array
            arguments
                waves
                stimulus = ""
                freqKHz double = NaN
                opts.OctaveShift (1,1) double = 0.15
                opts.RefFrequency (1,1) double {mustBePositive} = 16
                opts.Offset (1,1) double = 0
            end
            if ~isfinite(opts.Offset)
                error('mabr:analysis:Peaks:offset', ['The latency offset is %g ms: it must be a ' ...
                    'number. Check the conduction delay settings (Settings.problems()).'],opts.Offset);
            end
            W = mabr.analysis.Peaks.asWaves(waves);
            stim = string(stimulus);
            if isempty(stim) || ismissing(stim(1)), stim = ""; else, stim = stim(1); end
            s = mabr.analysis.Peaks.stimuliOf(W);
            if stim ~= "" && any(strcmpi(s,stim))
                W = W(strcmpi(s,stim));
            else
                W = W(s == "");
            end
            f = NaN;
            if ~isempty(freqKHz), f = freqKHz(1); end
            d = 0;
            if isfinite(f) && f > 0
                d = opts.OctaveShift*log2(opts.RefFrequency/f);
            end
            % One sum, so that Offset 0 leaves every window bit for bit what
            % it was before there was an Offset (x + 0 is x).
            d = d + opts.Offset;
            if d ~= 0
                for k = 1:numel(W)
                    W(k).TMin     = W(k).TMin + d;
                    W(k).TMax     = W(k).TMax + d;
                    W(k).Expected = W(k).Expected + d;
                end
            end
        end

        % =================================================================
        %  Candidates and refinement
        % =================================================================
        function c = candidates(tMs,y,kind,opts)
            % Local maxima ("P") or minima ("N") of one waveform.
            %
            % islocalmax/islocalmin over the finite samples (each finite run
            % on its own), at least MinSeparation ms apart -- the more
            % prominent of two closer ones survives -- and at least
            % MinProminence prominent (V).
            %
            %   tMs, y  nT x 1 time (ms) and waveform
            %   kind    "P" (default) | "N"
            %   opts.MinSeparation  ms (default 0.3)
            %   opts.MinProminence  V (default 0; NaN = no floor)
            %   c  (returned) table Idx, T (ms), Y, Prominence (positive for
            %      both kinds), in time order
            arguments
                tMs (:,1) double
                y (:,1) double
                kind (1,1) string {mustBeMember(kind,["P","N"])} = "P"
                opts.MinSeparation (1,1) double {mustBeNonnegative} = 0.3
                opts.MinProminence (1,1) double {mustBeNumeric} = 0
            end
            mabr.analysis.Peaks.checkTime(tMs,y);
            minProm = mabr.analysis.Peaks.promFloor(opts.MinProminence);
            sep = round(opts.MinSeparation/mabr.analysis.Peaks.dt(tMs));
            fin = isfinite(y) & isfinite(tMs);
            d = diff([false; fin; false]);
            s = find(d == 1);  e = find(d == -1) - 1;
            Idx = zeros(0,1);  Prominence = zeros(0,1);
            for r = 1:numel(s)
                if e(r) - s(r) + 1 < 3, continue; end
                seg = y(s(r):e(r));
                if kind == "P"
                    [tf,pr] = islocalmax(seg,'MinSeparation',sep,'MinProminence',minProm);
                else
                    [tf,pr] = islocalmin(seg,'MinSeparation',sep,'MinProminence',minProm);
                end
                ii = find(tf);
                Idx = [Idx; s(r) - 1 + ii]; %#ok<AGROW>
                Prominence = [Prominence; pr(ii)]; %#ok<AGROW>
            end
            T = tMs(Idx);
            Y = y(Idx);
            c = table(Idx,T,Y,Prominence);
        end

        function [tHat,yHat] = refine(tMs,y,idx)
            % Parabolic sub-sample refinement of extrema.
            %
            % Through y-, y0, y+ around each index: delta = (y- - y+)/(2(y- -
            % 2y0 + y+)), clamped to [-1/2 1/2] (0 when the curvature is zero
            % or a neighbour is missing); tHat = t0 + delta*dt, yHat = y0 -
            % (y- - y+)*delta/4. The same formula serves maxima and minima.
            %
            %   tMs, y  nT x 1 time (ms) and waveform
            %   idx     sample indices (any shape; NaN allowed)
            %   tHat, yHat  (returned) same shape as idx (NaN where idx is)
            arguments
                tMs (:,1) double
                y (:,1) double
                idx double
            end
            mabr.analysis.Peaks.checkTime(tMs,y);
            sz = size(idx);
            idx = idx(:);
            n = numel(y);
            tHat = nan(numel(idx),1);  yHat = tHat;
            ok = isfinite(idx) & idx >= 1 & idx <= n & idx == round(idx);
            i  = idx(ok);
            y0 = y(i);
            ym = nan(size(i));  yp = ym;
            hm = i > 1;  ym(hm) = y(i(hm) - 1);
            hp = i < n;  yp(hp) = y(i(hp) + 1);
            [d,dy] = mabr.analysis.Peaks.parabola(ym,y0,yp);
            tHat(ok) = tMs(i) + d*mabr.analysis.Peaks.dt(tMs);
            yHat(ok) = y0 - dy;
            tHat = reshape(tHat,sz);
            yHat = reshape(yHat,sz);
        end

        function [lat,val,edge,idx] = repick(tMs,Y,center,halfWidth,kind)
            % Re-pick one extremum per column inside center +- halfWidth.
            %
            % The constrained re-pick the bootstrap, the leave-one-out
            % single-trial measures and the block sub-averages all use: the
            % largest ("P") or smallest ("N") sample of each column inside the
            % window, refined parabolically. Constraining the window to the
            % full-data pick is what keeps a resample from switching labels.
            %
            %   tMs        nT x 1 time (ms)
            %   Y          [nT x K] waveforms, one per column
            %   center     ms (NaN: nothing is picked)
            %   halfWidth  ms
            %   kind       "P" | "N"
            %   lat, val   (returned) 1 x K refined latency (ms) and value
            %   edge       (returned) 1 x K, true when the extremum is the first
            %              or last sample of the window (an unstable pick)
            %   idx        (returned) 1 x K sample index
            arguments
                tMs (:,1) double
                Y double
                center (1,1) double
                halfWidth (1,1) double {mustBeNonnegative}
                kind (1,1) string {mustBeMember(kind,["P","N"])}
            end
            [nT,K] = size(Y);
            if numel(tMs) ~= nT
                error('mabr:analysis:Peaks:time','tMs has %d samples and Y %d rows.',numel(tMs),nT);
            end
            lat = nan(1,K);  val = lat;  idx = lat;  edge = false(1,K);
            if ~isfinite(center) || K == 0, return; end
            tol = 1e-9;
            w = find(tMs >= center - halfWidth - tol & tMs <= center + halfWidth + tol);
            if isempty(w), return; end
            Yw = Y(w,:);
            if kind == "P", [~,k] = max(Yw,[],1); else, [~,k] = min(Yw,[],1); end
            ok = any(isfinite(Yw),1);
            ii = reshape(w(k),1,[]);
            col = 1:K;
            y0 = Y(sub2ind([nT K],ii,col));
            ym = nan(1,K);  yp = ym;
            hm = ii > 1;   ym(hm) = Y(sub2ind([nT K],ii(hm) - 1,col(hm)));
            hp = ii < nT;  yp(hp) = Y(sub2ind([nT K],ii(hp) + 1,col(hp)));
            [d,dy] = mabr.analysis.Peaks.parabola(ym,y0,yp);
            lat(ok)  = tMs(ii(ok)).' + d(ok)*mabr.analysis.Peaks.dt(tMs);
            val(ok)  = y0(ok) - dy(ok);
            idx(ok)  = ii(ok);
            edge(ok) = (k(ok) == 1) | (k(ok) == numel(w));
        end

        % =================================================================
        %  Picking
        % =================================================================
        function P = pick(tMs,y,W,opts)
            % Pick every enabled wave's peak and trough on one waveform.
            %
            % Every enabled wave's P-candidates inside [TMin TMax] + Offset are
            % scored prom/max(prom) + TopPriorWeight*g, g the Gaussian prior
            % N(Expected + Offset, (TMax - TMin)/4) scaled to peak 1, and the
            % waves are assigned jointly (see the class help): distinct
            % candidates in wave order, each at least MinSeparation after the
            % one before, the largest summed score; a wave left without one
            % has State "none". Then each picked wave's trough: the most
            % prominent N-candidate between its peak and the next picked peak
            % (the last one: up to TroughSpan ms after it).
            %
            %   tMs, y  nT x 1 time (ms) and averaged waveform (V)
            %   W       wave struct array (disabled rows are skipped)
            %   opts.Offset               ms, a series-wide latency offset (default
            %                             0). It moves the windows as wavesFor's
            %                             Offset does: give the latency offset to
            %                             one of the two, not both
            %   opts.MinSeparation        ms between candidates and between
            %                             successive waves (default 0.3)
            %   opts.CandidateProminence  V, the smallest prominence a
            %                             candidate may have (default 0). NaN
            %                             means no floor: a caller scaling it
            %                             by RN may have no RN (one sweep)
            %   opts.Smooth               moving-mean length (samples) of the
            %                             copy candidates are found on (0 = none);
            %                             values are always read from y itself
            %   P  (returned) table Wave, PeakIdx, PeakLatency, PeakValue,
            %      Prominence, State ("auto"|"none"), TroughLatency,
            %      TroughValue, TroughState ("auto"|"none"), one row per
            %      enabled wave
            arguments
                tMs (:,1) double
                y (:,1) double
                W
                opts.Offset (1,1) double = 0
                opts.MinSeparation (1,1) double {mustBeNonnegative} = 0.3
                opts.CandidateProminence (1,1) double {mustBeNumeric} = 0
                opts.Smooth (1,1) double {mustBeNonnegative} = 0
            end
            mabr.analysis.Peaks.checkTime(tMs,y);
            cprom = mabr.analysis.Peaks.promFloor(opts.CandidateProminence);
            W = mabr.analysis.Peaks.asWaves(W);
            W = W([W.Enabled]);
            nW = numel(W);
            [lo,hi,prior] = mabr.analysis.Peaks.absoluteWindows(W,opts.Offset);
            none = mabr.analysis.Peaks.noAnchors(nW);
            lam = repmat(mabr.analysis.Peaks.TopPriorWeight,1,nW);
            R = mabr.analysis.Peaks.pickLevel(tMs,y,W,lo,hi,prior,lam,none,none, ...
                opts.MinSeparation,cprom,opts.Smooth);
            P = mabr.analysis.Peaks.levelTable(W,R);
        end

        function T = track(tMs,Y,levels,W,opts)
            % Pick and track every enabled wave down a level series.
            %
            % Levels are processed loudest first. The loudest level is picked
            % as pick() does. At each lower level L, a wave with a latency
            % prev at the closest louder level Lp is expected at prev +
            % LatencyShift*(Lp - L) and searched for in [prev - TrackEarly,
            % prev + TrackLate + LatencyShift*(Lp - L)] with a skew-normal
            % prior (shape 3, scale 0.1 ms) located at that expected latency,
            % weighted PriorWeight against prominence; a wave with no louder
            % pick falls back to its absolute window and Gaussian prior,
            % weighted TopPriorWeight. (The prior moves with the wave because
            % the wave moves: located at prev, it put the most weight where
            % the wave had been one level up, so a wave growing 0.3 ms later
            % per 10 dB, as wave V does, lost to any peak left there.)
            %
            % A wave's window ends MinSeparation before the expected latency
            % of the next later wave whose last louder pick is at least as
            % recent (as quiet) as this wave's own. Without that a
            % wave missed at one level was searched, one level down, in a
            % window widened by two level steps -- far enough to reach the
            % next wave's peak, which it then took (a click series' wave I
            % "tripling" in amplitude as level fell was wave II). The other
            % way round, when the earlier wave's track is the more recent --
            % picked, or anchored by hand, a level below the later wave's
            % last pick -- the later wave's window starts MinSeparation after
            % where the earlier one is expected. The waves of a level are
            % then assigned jointly, as in pick.
            %
            % Anchors (the user's corrections) win: a "manual" peak replaces
            % the pick at its level and is what the levels below track from;
            % an "absent" peak leaves the level without one (State "absent")
            % and does not move prev. A manual trough fixes the trough;
            % automatic troughs are always recomputed between the bounding
            % peaks, so a moved peak drags its trough with it.
            %
            %   tMs     nT x 1 time (ms)
            %   Y       [nT x nL] averaged waveforms, one column per level
            %   levels  nL level values (dB), one per column (unique). A NaN
            %           level is picked last, on the absolute windows, and
            %           neither tracks from nor feeds the others: it has no
            %           place in the series.
            %   W       wave struct array
            %   opts    as pick, plus
            %     opts.CandidateProminence  scalar or one per level (V; NaN
            %                               = no floor at that level)
            %     opts.TrackEarly           ms before prev (default 0.1)
            %     opts.TrackLate            ms after prev, before the level
            %                               term (default 0.15)
            %     opts.Anchors              [] or table Level, Wave, Kind
            %                               ("P"|"N"), State ("manual"|
            %                               "absent"), Latency (ms, NaN for absent)
            %   T  (returned) long table, loudest level first: Level, Wave,
            %      PeakIdx, PeakLatency, PeakValue, Prominence, State
            %      ("auto"|"manual"|"absent"|"none"), TroughLatency,
            %      TroughValue, TroughState ("auto"|"manual"|"none")
            arguments
                tMs (:,1) double
                Y double
                levels double
                W
                opts.Offset (1,1) double = 0
                opts.MinSeparation (1,1) double {mustBeNonnegative} = 0.3
                opts.CandidateProminence double {mustBeNumeric} = 0
                opts.Smooth (1,1) double {mustBeNonnegative} = 0
                opts.TrackEarly (1,1) double {mustBeNonnegative} = 0.1
                opts.TrackLate (1,1) double {mustBeNonnegative} = 0.15
                opts.Anchors = []
            end
            levels = reshape(double(levels),[],1);
            nL = numel(levels);
            if size(Y,1) ~= numel(tMs) || size(Y,2) ~= nL
                error('mabr:analysis:Peaks:trackSize', ...
                    'Y must be %d samples x %d levels; it is %d x %d.', ...
                    numel(tMs),nL,size(Y,1),size(Y,2));
            end
            % A floor scaled by each level's RN (Session.pickPeaks) is NaN at
            % a level whose RN is undefined -- one clean sweep -- and that
            % level is still picked, with no floor, rather than failing the
            % whole series.
            cp = mabr.analysis.Peaks.promFloor(opts.CandidateProminence(:));
            if isscalar(cp), cp = repmat(cp,nL,1); end
            if numel(cp) ~= nL
                error('mabr:analysis:Peaks:prominence', ...
                    'CandidateProminence has %d values for %d levels.',numel(cp),nL);
            end
            W = mabr.analysis.Peaks.asWaves(W);
            W = W([W.Enabled]);
            nW = numel(W);
            anc = mabr.analysis.Peaks.anchorTable(opts.Anchors);

            % Loudest first; NaN levels (sort puts them first) after every
            % finite one.
            fin = find(isfinite(levels));
            [~,o] = sort(levels(fin),'descend');
            ord = [fin(o); find(~isfinite(levels))];
            [loA,hiA,priorA] = mabr.analysis.Peaks.absoluteWindows(W,opts.Offset);
            lastLat = nan(1,nW);  lastLev = nan(1,nW);
            parts = cell(nL,1);
            for ii = 1:nL
                li = ord(ii);
                L  = levels(li);
                lo = loA;  hi = hiA;  prior = priorA;
                lam = repmat(mabr.analysis.Peaks.TopPriorWeight,1,nW);
                expd = nan(1,nW);                        % expected latency, tracked waves
                for w = 1:nW
                    if isnan(lastLat(w)) || ~isfinite(L), continue; end
                    prev  = lastLat(w);
                    shift = W(w).LatencyShift*(lastLev(w) - L);   % ms later than prev
                    lo(w) = prev - opts.TrackEarly;
                    hi(w) = prev + opts.TrackLate + shift;
                    prior{w} = mabr.analysis.Peaks.trackPrior(prev + shift);
                    lam(w) = mabr.analysis.Peaks.PriorWeight;
                    expd(w) = prev + shift;
                end
                % A wave comes before the next one: never searched where the
                % next wave being tracked is expected -- when that wave's track
                % is at least as recent as this one's. A wave picked (or put by
                % hand) at a quieter level than the next wave was knows better
                % where it is than that wave's older track does, and then it
                % is the later wave that is kept clear of it instead.
                for w = 1:nW-1
                    for v = w+1:nW
                        if ~isfinite(expd(v)), continue; end
                        if isnan(lastLev(w)) || lastLev(v) <= lastLev(w)
                            hi(w) = min(hi(w),expd(v) - opts.MinSeparation);
                            break
                        end
                    end
                end
                for v = 2:nW
                    for w = v-1:-1:1
                        if ~isfinite(expd(w)), continue; end
                        if isnan(lastLev(v)) || lastLev(w) < lastLev(v)
                            lo(v) = max(lo(v),expd(w) + opts.MinSeparation);
                            break
                        end
                    end
                end
                [aP,aN] = mabr.analysis.Peaks.anchorsAt(anc,L,W);
                R = mabr.analysis.Peaks.pickLevel(tMs,Y(:,li),W,lo,hi,prior,lam,aP,aN, ...
                    opts.MinSeparation,cp(li),opts.Smooth);
                got = (R.State == "auto" | R.State == "manual") & isfinite(L);
                lastLat(got) = R.Lat(got);
                lastLev(got) = L;
                t = mabr.analysis.Peaks.levelTable(W,R);
                t = addvars(t,repmat(L,height(t),1),'Before',1,'NewVariableNames','Level');
                parts{ii} = t;
            end
            if nL == 0
                T = addvars(mabr.analysis.Peaks.levelTable(W([]), ...
                    mabr.analysis.Peaks.emptyLevel(0)),zeros(0,1),'Before',1, ...
                    'NewVariableNames','Level');
            else
                T = vertcat(parts{:});
            end
        end

        % =================================================================
        %  Uncertainty from the sweeps
        % =================================================================
        function T = bootstrap(tMs,X,pol,strata,picks,opts)
            % Bootstrap standard errors and intervals of each wave's latency and amplitude.
            %
            % Sweeps are resampled with replacement within each file x
            % polarity group (mabr.analysis.SingleTrial.bootstrapMeans), the
            % balanced mean formed per replicate, and each wave re-picked
            % within +-WindowI (the first wave) or +-WindowOther (the others)
            % of its full-data pick, its trough within +-TroughWindow of the
            % full-data trough, both refined parabolically. Peak-picked
            % amplitudes are biased upward at low SNR, which is what
            % AmpPTBias shows. A wave whose replicate picks land on a window
            % edge more than 10% of the time is Unstable: the window, not the
            % data, decided those picks.
            %
            %   tMs     nT x 1 time (ms)
            %   X       [nT x N] sweeps
            %   pol     1 x N +1/-1
            %   strata  1 x N file index ([] = one file)
            %   picks   table/struct with Wave, PeakLatency, TroughLatency
            %           (pick/track rows; the first row is "the first wave")
            %   opts.B            replicates (default 500)
            %   opts.Alpha        two-sided level of the percentile CI (0.05)
            %   opts.Stream       RandStream ([] = threefry seeded 1)
            %   opts.WindowI      ms (default 0.3)
            %   opts.WindowOther  ms (default 0.5)
            %   T  (returned) table Wave, LatencySE, LatencyCILo, LatencyCIHi,
            %      LatencyBias (ms); AmpPTSE, AmpPTCILo, AmpPTCIHi, AmpPTBias
            %      (V); Unstable; B
            arguments
                tMs (:,1) double
                X double
                pol double
                strata double = []
                picks = []
                opts.B (1,1) double {mustBeInteger,mustBePositive} = 500
                opts.Alpha (1,1) double {mustBeInRange(opts.Alpha,0,1,"exclusive")} = 0.05
                opts.Stream = []
                opts.WindowI (1,1) double {mustBePositive} = 0.3
                opts.WindowOther (1,1) double {mustBePositive} = 0.5
            end
            if numel(tMs) ~= size(X,1)
                error('mabr:analysis:Peaks:time','tMs has %d samples and X %d rows.',numel(tMs),size(X,1));
            end
            pk = mabr.analysis.Peaks.pickList(picks);
            nW = numel(pk.Wave);
            Wave = pk.Wave;
            LatencySE = nan(nW,1); LatencyCILo = LatencySE; LatencyCIHi = LatencySE;
            LatencyBias = LatencySE; AmpPTSE = LatencySE; AmpPTCILo = LatencySE;
            AmpPTCIHi = LatencySE; AmpPTBias = LatencySE;
            Unstable = false(nW,1);
            B = repmat(opts.B,nW,1);
            if nW > 0 && size(X,2) >= 2
                stream = opts.Stream;
                if isempty(stream), stream = RandStream('threefry','Seed',1); end
                m = mabr.analysis.SingleTrial.balancedMean(X,pol,strata);
                M = mabr.analysis.SingleTrial.bootstrapMeans(X,pol,strata,opts.B,stream);
                ci = [opts.Alpha/2 1-opts.Alpha/2];
                tw = mabr.analysis.Peaks.TroughWindow;
                for w = 1:nW
                    if w == 1, win = opts.WindowI; else, win = opts.WindowOther; end
                    [lat0,pv0] = mabr.analysis.Peaks.repick(tMs,m,pk.PeakLatency(w),win,"P");
                    if ~isfinite(lat0), continue; end
                    [~,tv0]    = mabr.analysis.Peaks.repick(tMs,m,pk.TroughLatency(w),tw,"N");
                    [latB,pvB,eP] = mabr.analysis.Peaks.repick(tMs,M,pk.PeakLatency(w),win,"P");
                    [~,tvB,eT]    = mabr.analysis.Peaks.repick(tMs,M,pk.TroughLatency(w),tw,"N");
                    lb = latB(isfinite(latB));
                    LatencySE(w)   = std(lb);
                    q = mabr.analysis.Stats.percentile(lb,ci);
                    LatencyCILo(w) = q(1);  LatencyCIHi(w) = q(2);
                    LatencyBias(w) = mean(lb) - lat0;
                    a0 = pv0 - tv0;
                    aB = pvB - tvB;
                    aB = aB(isfinite(aB));
                    if isfinite(a0) && ~isempty(aB)
                        AmpPTSE(w)   = std(aB);
                        q = mabr.analysis.Stats.percentile(aB,ci);
                        AmpPTCILo(w) = q(1);  AmpPTCIHi(w) = q(2);
                        AmpPTBias(w) = mean(aB) - a0;
                    end
                    hasT = isfinite(pk.TroughLatency(w));
                    Unstable(w) = mean(eP | (hasT & eT)) > 0.1;
                end
            end
            T = table(Wave,LatencySE,LatencyCILo,LatencyCIHi,LatencyBias, ...
                AmpPTSE,AmpPTCILo,AmpPTCIHi,AmpPTBias,Unstable,B);
        end

        function V = singleTrial(tMs,X,picks,opts)
            % Each sweep's wave measures against its leave-one-out average.
            %
            % For sweep k the template is m~_k = (sum x - x_k)/(N-1) -- the
            % average WITHOUT it, so a sweep is never measured against itself.
            % Each wave is re-picked on m~_k within +-Window of the full pick
            % (peak) and the full trough; PValue is x_k at that peak latency
            % (linear interpolation), PNValue = x_k(peak) - x_k(trough), and
            % Proj = <x_k,m~_k>/<m~_k,m~_k> over [peak - 0.3, trough + 0.3] ms
            % of the full pick, the sweep's amplitude in units of the response.
            %
            %   tMs    nT x 1 time (ms)
            %   X      [nT x N] sweeps (clean ones)
            %   picks  table/struct with Wave, PeakLatency, TroughLatency
            %   opts.Window  ms (default 0.3)
            %   V  (returned) table Sweep, Wave, PeakLatency (the LOO pick, ms),
            %      PValue, PNValue (V), Proj -- N x nWaves rows, sweep-major
            arguments
                tMs (:,1) double
                X double
                picks = []
                opts.Window (1,1) double {mustBePositive} = 0.3
            end
            [nT,N] = size(X);
            if numel(tMs) ~= nT
                error('mabr:analysis:Peaks:time','tMs has %d samples and X %d rows.',numel(tMs),nT);
            end
            pk = mabr.analysis.Peaks.pickList(picks);
            nW = numel(pk.Wave);
            Lat = nan(nW,N);  PV = Lat;  PN = Lat;  Pr = Lat;
            if N >= 2 && nW > 0
                M = (sum(X,2) - X)/(N - 1);               % leave-one-out means
                fin = all(isfinite(X),2);
                for w = 1:nW
                    [lp] = mabr.analysis.Peaks.repick(tMs,M,pk.PeakLatency(w),opts.Window,"P");
                    [lt] = mabr.analysis.Peaks.repick(tMs,M,pk.TroughLatency(w),opts.Window,"N");
                    Lat(w,:) = lp;
                    PV(w,:)  = mabr.analysis.Peaks.interpCols(tMs,X,lp);
                    PN(w,:)  = PV(w,:) - mabr.analysis.Peaks.interpCols(tMs,X,lt);
                    t1 = pk.TroughLatency(w);
                    if ~isfinite(t1), t1 = pk.PeakLatency(w); end
                    r = fin & tMs >= pk.PeakLatency(w) - 0.3 & tMs <= t1 + 0.3;
                    if any(r)
                        Pr(w,:) = sum(X(r,:).*M(r,:),1)./sum(M(r,:).^2,1);
                    end
                end
            end
            Sweep       = reshape(repelem((1:N).',nW),[],1);   % repelem of a scalar is a row
            Wave        = repmat(pk.Wave,N,1);
            PeakLatency = Lat(:);
            PValue      = PV(:);
            PNValue     = PN(:);
            Proj        = Pr(:);
            V = table(Sweep,Wave,PeakLatency,PValue,PNValue,Proj);
        end

        % =================================================================
        %  Measures derived from the picks
        % =================================================================
        function [M,G] = derived(P,opts)
            % Interpeak latencies, amplitude ratios and I/O slopes from picks.
            %
            %   P  a peaks table: Key, Level, Wave, State, PeakLatency and,
            %      when present, SeriesKey, AmpPT (else PeakValue -
            %      TroughValue), Detectable, BelowThreshold
            %   opts.Final  [] or table SeriesKey, Final, FinalCensored,
            %               FinalLo: decides BelowThreshold when P has no such
            %               column (interval: level <= FinalLo; none: level <
            %               Final; right-censored: every level; left/excluded:
            %               none). Optional columns LevelDirection
            %               ("descending" = an attenuation axis, judged on
            %               -level as SeriesThreshold.belowThreshold does) and
            %               FinalHi (the interval's other end, which that axis
            %               needs). Row and level order do not matter.
            %   opts.AboveThresholdOnly  use only picks at or above the series'
            %               threshold (default true)
            %   M  (returned) long table Key, Measure, Value, Unit per condition:
            %      IPL_<a>_<b> for each consecutive pair of picked waves (ms),
            %      IPL_<first>_<last> (three or more picked), and
            %      LOGRATIO_<last>_<first> = log(AmpPT last) - log(AmpPT
            %      first) when both are positive -- a ratio is modelled on the
            %      log scale, where a halving and a doubling are symmetric
            %   G  (returned) table SeriesKey, Wave, Quantity ("AmpPT"|
            %      "Latency"), Slope, Intercept, Unit ("V/dB"|"ms/dB"),
            %      NLevels, LevelMin, LevelMax: least squares against level
            %      over the picked (auto/manual), Detectable points, NaN when
            %      fewer than three
            arguments
                P table
                opts.Final = []
                opts.AboveThresholdOnly (1,1) logical = true
            end
            M = table(strings(0,1),strings(0,1),zeros(0,1),strings(0,1), ...
                'VariableNames',{'Key','Measure','Value','Unit'});
            G = table(strings(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
                strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames', ...
                {'SeriesKey','Wave','Quantity','Slope','Intercept','Unit', ...
                 'NLevels','LevelMin','LevelMax'});
            if height(P) == 0, return; end
            v = string(P.Properties.VariableNames);
            need = ["Key","Level","Wave","State","PeakLatency"];
            if ~all(ismember(need,v))
                error('mabr:analysis:Peaks:derivedColumns', ...
                    'The peaks table needs the columns %s.',strjoin(need,', '));
            end
            n    = height(P);
            key  = string(P.Key);
            wave = string(P.Wave);
            lat  = double(P.PeakLatency);
            lev  = double(P.Level);
            if ismember("SeriesKey",v), sk = string(P.SeriesKey); else, sk = repmat("(all)",n,1); end
            if ismember("AmpPT",v)
                amp = double(P.AmpPT);
            elseif all(ismember(["PeakValue","TroughValue"],v))
                amp = double(P.PeakValue) - double(P.TroughValue);
            else
                amp = nan(n,1);
            end
            if ismember("Detectable",v), det = logical(P.Detectable); else, det = true(n,1); end
            if ismember("BelowThreshold",v)
                below = logical(P.BelowThreshold);
            else
                below = mabr.analysis.Peaks.belowFromFinal(sk,lev,opts.Final);
            end

            picked = ismember(string(P.State),["auto","manual"]) & isfinite(lat);
            use = picked & (~below | ~opts.AboveThresholdOnly);
            waveOrder = unique(wave,'stable');

            % ---- per condition
            mk = strings(0,1); mm = strings(0,1); mv = zeros(0,1); mu = strings(0,1);
            for k = reshape(unique(key(use),'stable'),1,[])
                r = find(use & key == k);
                [~,pos] = ismember(wave(r),waveOrder);
                [~,o] = sort(pos);
                r = r(o);
                nm = wave(r);  L = lat(r);  A = amp(r);
                for i = 1:numel(r) - 1
                    mk(end+1,1) = k; mm(end+1,1) = "IPL_" + nm(i) + "_" + nm(i+1); %#ok<AGROW>
                    mv(end+1,1) = L(i+1) - L(i); mu(end+1,1) = "ms"; %#ok<AGROW>
                end
                if numel(r) >= 3
                    mk(end+1,1) = k; mm(end+1,1) = "IPL_" + nm(1) + "_" + nm(end); %#ok<AGROW>
                    mv(end+1,1) = L(end) - L(1); mu(end+1,1) = "ms"; %#ok<AGROW>
                end
                if numel(r) >= 2 && A(1) > 0 && A(end) > 0
                    mk(end+1,1) = k; mm(end+1,1) = "LOGRATIO_" + nm(end) + "_" + nm(1); %#ok<AGROW>
                    mv(end+1,1) = log(A(end)) - log(A(1)); mu(end+1,1) = "ln ratio"; %#ok<AGROW>
                end
            end
            M = table(mk,mm,mv,mu,'VariableNames',{'Key','Measure','Value','Unit'});

            % ---- per series x wave
            [~,first] = unique(sk + "|" + wave,'stable');
            gs = strings(0,1); gw = gs; gq = gs; gu = gs;
            gb = zeros(0,1); ga = gb; gn = gb; gl0 = gb; gl1 = gb;
            qty  = ["AmpPT","Latency"];
            unit = ["V/dB","ms/dB"];
            for f = reshape(first,1,[])
                for qi = 1:2
                    if qi == 1, yv = amp; else, yv = lat; end
                    r = use & det & sk == sk(f) & wave == wave(f) & isfinite(yv) & isfinite(lev);
                    x = lev(r);  y = yv(r);
                    np = numel(x);
                    b = [NaN; NaN];
                    if np >= 3 && numel(unique(x)) >= 2
                        b = [ones(np,1) x]\y;
                    end
                    gs(end+1,1) = sk(f); gw(end+1,1) = wave(f); gq(end+1,1) = qty(qi); %#ok<AGROW>
                    gb(end+1,1) = b(2); ga(end+1,1) = b(1); gu(end+1,1) = unit(qi); %#ok<AGROW>
                    gn(end+1,1) = np; %#ok<AGROW>
                    if np > 0
                        gl0(end+1,1) = min(x); gl1(end+1,1) = max(x); %#ok<AGROW>
                    else
                        gl0(end+1,1) = NaN; gl1(end+1,1) = NaN; %#ok<AGROW>
                    end
                end
            end
            G = table(gs,gw,gq,gb,ga,gu,gn,gl0,gl1,'VariableNames', ...
                {'SeriesKey','Wave','Quantity','Slope','Intercept','Unit', ...
                 'NLevels','LevelMin','LevelMax'});
        end

        function lat = reported(latRaw,offsetMs)
            % The latency a user is shown or an export writes: raw minus offset.
            %
            % THE one place the latency offset -- the sound's conduction delay
            % plus any fixed system offset, mabr.analysis.Settings.
            % latencyOffset() -- comes off a latency, turning one re the
            % electrical onset into one re sound arrival. Every latency stored
            % stays raw, re the onset, and was picked in windows in that same
            % time, so the offset changes what is reported and never what is
            % picked. Interpeak intervals are differences and do not depend
            % on it.
            %
            %   latRaw    latencies re the onset, ms (any shape)
            %   offsetMs  ms to subtract (default 0); scalar or latRaw's size
            %   lat       (returned) latRaw - offsetMs
            arguments
                latRaw double
                offsetMs double = 0
            end
            lat = latRaw - offsetMs;
        end

        function c = waveColor(name)
            % The colour a wave is drawn in (Okabe-Ito).
            %
            % I vermillion, II orange, III bluish green, IV sky blue, V blue,
            % VI reddish purple, VII black; any other name is reddish purple
            % or black, fixed by the name itself, so a wave keeps its colour
            % whatever else is drawn beside it.
            %
            %   name  wave name(s): text, string array or cellstr
            %   c     (returned) [n x 3] RGB in [0 1], one row per name
            arguments
                name
            end
            names = reshape(string(name),[],1);
            c = zeros(numel(names),3);
            for i = 1:numel(names)
                k = names(i);
                if ismissing(k), k = ""; end
                switch upper(strtrim(k))
                    case "I",   c(i,:) = mabr.analysis.Peaks.Vermillion;
                    case "II",  c(i,:) = mabr.analysis.Peaks.Orange;
                    case "III", c(i,:) = mabr.analysis.Peaks.BluishGreen;
                    case "IV",  c(i,:) = mabr.analysis.Peaks.SkyBlue;
                    case "V",   c(i,:) = mabr.analysis.Peaks.Blue;
                    case "VI",  c(i,:) = mabr.analysis.Peaks.ReddishPurple;
                    case "VII", c(i,:) = mabr.analysis.Peaks.Black;
                    otherwise
                        if mod(sum(double(char(upper(strtrim(k))))),2) == 0
                            c(i,:) = mabr.analysis.Peaks.ReddishPurple;
                        else
                            c(i,:) = mabr.analysis.Peaks.Black;
                        end
                end
            end
        end
    end

    methods (Static, Access = private)
        % =================================================================
        %  The picking engine (one level)
        % =================================================================
        function R = pickLevel(t,y,W,lo,hi,prior,lam,aP,aN,minSep,cprom,smooth)
            % Pick every wave's peak, then its trough, on one waveform.
            %
            %   t, y        nT x 1 time (ms) and waveform
            %   W           1 x nW (enabled) waves
            %   lo, hi      1 x nW search windows (ms)
            %   prior       1 x nW cell of @(t) latency priors, peak 1
            %   lam         1 x nW weight of each wave's prior against its
            %               prominence (PriorWeight / TopPriorWeight)
            %   aP, aN      1 x nW anchor structs (State "", "manual",
            %               "absent"; Latency) for peaks and troughs
            %   minSep      ms; cprom V; smooth samples
            %   R  (returned) struct of 1 x nW fields Idx, Lat, Val, Prom,
            %      State, TLat, TVal, TState
            nW  = numel(W);
            R   = mabr.analysis.Peaks.emptyLevel(nW);
            tol = 1e-9;
            ys  = mabr.analysis.Peaks.smoothCopy(y,smooth);
            half = floor(smooth/2);
            cP  = mabr.analysis.Peaks.candidates(t,ys,"P",MinSeparation=minSep,MinProminence=cprom);
            cN  = mabr.analysis.Peaks.candidates(t,ys,"N",MinSeparation=minSep,MinProminence=cprom);
            allP = [];                                   % every local maximum, on demand

            % A later wave anchored by hand bounds the earlier ones from above,
            % as the previous pick bounds the later ones from below.
            ub = inf(1,nW);
            for w = nW-1:-1:1
                ub(w) = ub(w+1);
                if aP(w+1).State == "manual" && isfinite(aP(w+1).Latency)
                    ub(w) = min(ub(w),aP(w+1).Latency - minSep);
                end
            end

            % What each wave would score with each candidate (-Inf: outside
            % its window). Both terms are scaled to [0 1] -- prominence by the
            % most prominent candidate in the wave's window, the prior by its
            % own peak -- so the scores of two waves can be added and compared,
            % which shares of each wave's own candidates could not: a lone
            % candidate was every wave's certain pick, however far from where
            % that wave was expected.
            Tc = cP.T;
            S = -Inf(nW,numel(Tc));
            for w = 1:nW
                if aP(w).State == "absent" || aP(w).State == "manual", continue; end
                sel = Tc >= lo(w) - tol & Tc <= hi(w) + tol & Tc <= ub(w) + tol;
                if ~any(sel), continue; end
                pr = cP.Prominence(sel);
                top = max(pr);
                if top > 0 && isfinite(top), pr = pr/top; else, pr = ones(size(pr)); end
                g = prior{w}(Tc(sel));
                g(~isfinite(g)) = 0;
                S(w,sel) = reshape(pr,1,[]) + lam(w)*reshape(g,1,[]);
            end
            choice = mabr.analysis.Peaks.assign(S,Tc,aP,minSep,tol);

            for w = 1:nW
                switch aP(w).State
                    case "absent"
                        R.State(w) = "absent";
                    case "manual"
                        lat = aP(w).Latency;
                        [~,i] = min(abs(t - lat));
                        if isempty(allP)
                            allP = mabr.analysis.Peaks.candidates(t,ys,"P",MinSeparation=0,MinProminence=0);
                        end
                        near = abs(allP.Idx - i) <= 1;
                        R.Idx(w)  = i;
                        R.Lat(w)  = lat;
                        R.Val(w)  = mabr.analysis.Peaks.valueAt(t,y,lat);
                        R.Prom(w) = max([allP.Prominence(near); 0]);
                        R.State(w) = "manual";
                    otherwise
                        c = choice(w);
                        if c <= 0
                            R.State(w) = "none";
                            continue
                        end
                        i = mabr.analysis.Peaks.snap(y,cP.Idx(c),half,"P");
                        [R.Lat(w),R.Val(w)] = mabr.analysis.Peaks.refine(t,y,i);
                        R.Idx(w)  = i;
                        R.Prom(w) = cP.Prominence(c);
                        R.State(w) = "auto";
                end
            end

            picked = R.State == "auto" | R.State == "manual";
            for w = 1:nW
                switch aN(w).State
                    case "manual"
                        R.TLat(w) = aN(w).Latency;
                        R.TVal(w) = mabr.analysis.Peaks.valueAt(t,y,aN(w).Latency);
                        R.TState(w) = "manual";
                        continue
                    case "absent"
                        continue                          % TState stays "none"
                end
                if ~picked(w), continue; end
                nxt = find(picked(w+1:end),1);
                if isempty(nxt)
                    hiT = R.Lat(w) + mabr.analysis.Peaks.TroughSpan;
                else
                    hiT = R.Lat(w + nxt);
                end
                sel = cN.T > R.Lat(w) & cN.T < hiT;
                if ~any(sel), continue; end
                Pc = cN.Prominence(sel);  Ic = cN.Idx(sel);
                [~,b] = max(Pc);
                i = mabr.analysis.Peaks.snap(y,Ic(b),half,"N");
                [R.TLat(w),R.TVal(w)] = mabr.analysis.Peaks.refine(t,y,i);
                R.TState(w) = "auto";
            end
        end

        function choice = assign(S,Tc,aP,minSep,tol)
            % The joint assignment of candidates to waves with the largest
            % summed score.
            %
            % The waves are taken in order; a wave either takes a candidate
            % at least minSep after the latency the waves before it ended on,
            % or is left without one. A manual anchor is a fixed latency the
            % waves after it must keep minSep clear of; an absent one is
            % skipped. Dynamic programming over the latency the waves so far
            % ended on: each state is that latency, the score so far and the
            % choices that made it, and a state later than another and
            % scoring no more is dropped, since it can only constrain the
            % waves still to come further. Exact, and about nW x nC^2
            % comparisons for nC candidates.
            %
            %   S       [nW x nC] score of each wave for each candidate
            %           (-Inf: the wave may not take it)
            %   Tc      nC x 1 candidate latencies, ms, ascending
            %   aP      1 x nW peak anchors (State "", "manual", "absent")
            %   minSep  ms; tol ms
            %   choice  (returned) 1 x nW: the candidate each wave takes, 0
            %           none, -1 its manual anchor
            nW = size(S,1);
            stT = -Inf;  stV = 0;  stC = zeros(1,nW);
            for w = 1:nW
                switch aP(w).State
                    case "absent"
                        continue
                    case "manual"
                        % Every state ends before it: the windows of the
                        % waves before it end there (ub in pickLevel).
                        [~,b] = max(stV);
                        stT = aP(w).Latency;  stV = stV(b);  stC = stC(b,:);
                        stC(w) = -1;
                        continue
                end
                nT = stT;  nV = stV;  nC = stC;          % the wave left without a pick
                for c = find(isfinite(S(w,:)))
                    ok = stT <= Tc(c) - minSep + tol;
                    if ~any(ok), continue; end
                    v = stV;  v(~ok) = -Inf;
                    [best,b] = max(v);
                    ch = stC(b,:);  ch(w) = c;
                    nT(end+1,1) = Tc(c);  nV(end+1,1) = best + S(w,c);  nC(end+1,:) = ch; %#ok<AGROW>
                end
                % Earliest first, the best of equal latencies first; keep a
                % state only when it beats every earlier one.
                [~,o] = sortrows([nT -nV]);
                nT = nT(o);  nV = nV(o);  nC = nC(o,:);
                keep = false(numel(nT),1);  run = -Inf;
                for k = 1:numel(nT)
                    if nV(k) > run, keep(k) = true;  run = nV(k); end
                end
                stT = nT(keep);  stV = nV(keep);  stC = nC(keep,:);
            end
            [~,b] = max(stV);
            choice = stC(b,:);
        end

        function R = emptyLevel(nW)
            R = struct('Idx',nan(1,nW),'Lat',nan(1,nW),'Val',nan(1,nW), ...
                'Prom',nan(1,nW),'State',repmat("none",1,nW), ...
                'TLat',nan(1,nW),'TVal',nan(1,nW),'TState',repmat("none",1,nW));
        end

        function T = levelTable(W,R)
            % One level's picks as pick()'s table.
            Wave          = reshape(string({W.Name}),[],1);
            PeakIdx       = R.Idx(:);
            PeakLatency   = R.Lat(:);
            PeakValue     = R.Val(:);
            Prominence    = R.Prom(:);
            State         = R.State(:);
            TroughLatency = R.TLat(:);
            TroughValue   = R.TVal(:);
            TroughState   = R.TState(:);
            if isempty(W)
                Wave = strings(0,1);  State = strings(0,1);  TroughState = strings(0,1);
            end
            T = table(Wave,PeakIdx,PeakLatency,PeakValue,Prominence,State, ...
                TroughLatency,TroughValue,TroughState);
        end

        function [lo,hi,prior] = absoluteWindows(W,offset)
            % The top-level search: [TMin TMax] + offset with a Gaussian prior
            % N(Expected + offset, (TMax - TMin)/4), scaled to peak 1.
            nW = numel(W);
            lo = zeros(1,nW);  hi = lo;  prior = cell(1,nW);
            for w = 1:nW
                lo(w) = W(w).TMin + offset;
                hi(w) = W(w).TMax + offset;
                mu = W(w).Expected + offset;
                sg = max((W(w).TMax - W(w).TMin)/4,1e-6);
                prior{w} = @(x) exp(-0.5*((x - mu)/sg).^2);
            end
        end

        function p = skewNormalPdf(x,loc,scale,shape)
            % Skew-normal density 2/w phi((x-xi)/w) Phi(a(x-xi)/w), Phi via erfc.
            z = (x - loc)/scale;
            p = (2/scale)*exp(-0.5*z.^2)/sqrt(2*pi).*(0.5*erfc(-shape*z/sqrt(2)));
        end

        function f = trackPrior(expected)
            % The latency prior of a tracked wave: the EPL skew-normal (shape
            % PriorShape, scale PriorScale ms) located at its expected
            % latency, prev + LatencyShift*(Lprev - L), scaled to peak 1. Its
            % shape puts most of the weight just after that latency and
            % little before it.
            sc = mabr.analysis.Peaks.PriorScale;
            sh = mabr.analysis.Peaks.PriorShape;
            pk = mabr.analysis.Peaks.skewNormalPeak();
            f = @(x) mabr.analysis.Peaks.skewNormalPdf(x,expected,sc,sh)/pk;
        end

        function pk = skewNormalPeak()
            % The largest value of the tracking prior's density (its mode's),
            % found once on a 0.1%-of-a-scale grid: the prior is scaled by it
            % so that a tracked wave's prior term is in [0 1], like the rest.
            persistent v
            if isempty(v)
                sc = mabr.analysis.Peaks.PriorScale;
                z = linspace(-1,3,40001);
                v = max(mabr.analysis.Peaks.skewNormalPdf(z*sc,0,sc,mabr.analysis.Peaks.PriorShape));
            end
            pk = v;
        end

        % =================================================================
        %  Anchors
        % =================================================================
        function A = anchorTable(a)
            % [] or a table Level, Wave, Kind, State, Latency -> the same with
            % string columns (empty when none).
            A = table(zeros(0,1),strings(0,1),strings(0,1),strings(0,1),zeros(0,1), ...
                'VariableNames',{'Level','Wave','Kind','State','Latency'});
            if isempty(a), return; end
            if isstruct(a), a = struct2table(a,'AsArray',true); end
            if ~istable(a)
                error('mabr:analysis:Peaks:anchors', ...
                    'Anchors must be a table with Level, Wave, Kind, State, Latency.');
            end
            need = ["Level","Wave","Kind","State"];
            if ~all(ismember(need,string(a.Properties.VariableNames)))
                error('mabr:analysis:Peaks:anchors', ...
                    'Anchors must have the columns Level, Wave, Kind, State, Latency.');
            end
            n = height(a);
            lat = nan(n,1);
            if ismember("Latency",string(a.Properties.VariableNames))
                lat = double(a.Latency);
            end
            A = table(double(a.Level),string(a.Wave),upper(string(a.Kind)), ...
                lower(string(a.State)),lat, ...
                'VariableNames',{'Level','Wave','Kind','State','Latency'});
        end

        function [aP,aN] = anchorsAt(A,L,W)
            % The anchors of one level, one struct per wave (last row wins).
            nW = numel(W);
            aP = mabr.analysis.Peaks.noAnchors(nW);
            aN = aP;
            if height(A) == 0, return; end
            here = abs(A.Level - L) < 1e-9;
            for w = 1:nW
                r = find(here & strcmpi(A.Wave,W(w).Name));
                for j = reshape(r,1,[])
                    s = struct('State',A.State(j),'Latency',A.Latency(j));
                    if A.State(j) == "manual" && ~isfinite(A.Latency(j)), continue; end
                    if A.Kind(j) == "N", aN(w) = s; else, aP(w) = s; end
                end
            end
        end

        function a = noAnchors(nW)
            a = repmat(struct('State',"",'Latency',NaN),1,nW);
        end

        % =================================================================
        %  Small helpers
        % =================================================================
        function W = asWaves(W)
            % A wave struct array (or table, or TraceInspector-style rows) ->
            % 1 x n struct with every field, Name/Stimulus as strings. A
            % missing Expected is the window centre, a missing LatencyShift
            % AddedLatencyShift, a missing Stimulus "" and a missing Enabled
            % true -- the rule mabr.analysis.Settings.Waves fills by too.
            if istable(W), W = table2struct(W); end
            out = struct('Name',{},'Enabled',{},'TMin',{},'TMax',{}, ...
                'Expected',{},'LatencyShift',{},'Stimulus',{});
            if isempty(W), W = out; return; end
            if ~isstruct(W) || ~all(isfield(W,{'Name','TMin','TMax'}))
                error('mabr:analysis:Peaks:waves', ...
                    'Waves must be a struct array with at least Name, TMin and TMax.');
            end
            W = reshape(W,1,[]);
            for k = numel(W):-1:1
                w = W(k);
                o.Name = string(w.Name);
                o.Enabled = true;
                if isfield(w,'Enabled') && ~isempty(w.Enabled), o.Enabled = logical(w.Enabled(1)); end
                o.TMin = double(w.TMin);
                o.TMax = double(w.TMax);
                o.Expected = (o.TMin + o.TMax)/2;
                if isfield(w,'Expected') && ~isempty(w.Expected) && isfinite(w.Expected(1))
                    o.Expected = double(w.Expected(1));
                end
                o.LatencyShift = mabr.analysis.Peaks.AddedLatencyShift;
                if isfield(w,'LatencyShift') && ~isempty(w.LatencyShift) && isfinite(w.LatencyShift(1))
                    o.LatencyShift = double(w.LatencyShift(1));
                end
                o.Stimulus = "";
                if isfield(w,'Stimulus') && ~isempty(w.Stimulus) && ~any(ismissing(string(w.Stimulus)))
                    o.Stimulus = string(w.Stimulus);
                end
                out(k) = o;
            end
            W = out;
        end

        function s = stimuliOf(W)
            s = strings(1,numel(W));
            for k = 1:numel(W), s(k) = string(W(k).Stimulus); end
        end

        function pk = pickList(picks)
            % picks: [] / struct array / table with Wave, PeakLatency,
            % TroughLatency. pk (returned): struct of columns (Wave string).
            pk = struct('Wave',strings(0,1),'PeakLatency',zeros(0,1),'TroughLatency',zeros(0,1));
            if isempty(picks), return; end
            if istable(picks), picks = table2struct(picks); end
            pk.Wave = reshape(string({picks.Wave}),[],1);
            pk.PeakLatency = reshape(double([picks.PeakLatency]),[],1);
            if isfield(picks,'TroughLatency')
                pk.TroughLatency = reshape(double([picks.TroughLatency]),[],1);
            else
                pk.TroughLatency = nan(numel(pk.Wave),1);
            end
        end

        function below = belowFromFinal(sk,lev,F)
            % BelowThreshold per row from a table of curated thresholds
            % (SeriesThreshold.belowThreshold's rule, kept here so Peaks has
            % no dependency on it): interval -> level <= FinalLo; none ->
            % level < Final; right -> true; left / excluded / "" -> false.
            %
            % Per row and per series, so the order of the rows and of the
            % levels does not matter. What does is the level axis: a series
            % whose LevelDirection (or Direction) column says "descending" --
            % an attenuation axis, where a larger number is a quieter sound
            % -- is judged on -level, as SeriesThreshold.belowThreshold does:
            % none -> level > Final; interval -> level >= FinalHi; right /
            % left swap, since a series that never responded is censored at
            % the other end of the axis. Without the column the axis is
            % ascending (dB SPL).
            below = false(numel(lev),1);
            if isempty(F) || ~istable(F) || height(F) == 0, return; end
            v = string(F.Properties.VariableNames);
            if ismember("SeriesKey",v), fk = string(F.SeriesKey);
            elseif ismember("Key",v),   fk = string(F.Key);
            else, return
            end
            dirn = repmat("ascending",height(F),1);
            if ismember("LevelDirection",v), dirn = string(F.LevelDirection);
            elseif ismember("Direction",v),  dirn = string(F.Direction);
            end
            dirn(ismissing(dirn)) = "ascending";
            for i = 1:numel(lev)
                j = find(fk == sk(i),1);
                if isempty(j), continue; end
                cens = "none";
                if ismember("FinalCensored",v), cens = string(F.FinalCensored(j)); end
                if ismissing(cens), cens = ""; end
                fin = NaN;  lo = NaN;  hi = NaN;
                if ismember("Final",v),   fin = double(F.Final(j));   end
                if ismember("FinalLo",v), lo  = double(F.FinalLo(j)); end
                if ismember("FinalHi",v), hi  = double(F.FinalHi(j)); end
                x = lev(i);
                if strcmpi(dirn(j),"descending")
                    % The same rule on -level: the bracket's lower end on
                    % that axis is -FinalHi, and the two censorings swap.
                    x = -x;  fin = -fin;  lo = -hi;
                    if cens == "left", cens = "right"; elseif cens == "right", cens = "left"; end
                end
                switch cens
                    case "interval"
                        below(i) = x <= lo;
                    case "none"
                        below(i) = x < fin;
                    case "right"
                        below(i) = true;
                end
            end
        end

        function [d,dy] = parabola(ym,y0,yp)
            % The parabolic step and the value correction through three samples.
            den = ym - 2*y0 + yp;
            d   = 0.5*(ym - yp)./den;
            bad = ~isfinite(d) | den == 0;
            d(bad) = 0;
            d   = min(max(d,-0.5),0.5);
            dy  = 0.25*(ym - yp).*d;
            dy(bad) = 0;
        end

        function i = snap(y,i,half,kind)
            % Move a pick found on a smoothed copy onto the extremum of y
            % itself within +-half samples (no-op when half is 0).
            if half < 1, return; end
            r = max(1,i-half):min(numel(y),i+half);
            v = y(r);
            if ~any(isfinite(v)), return; end
            if kind == "P", [~,k] = max(v); else, [~,k] = min(v); end
            i = r(k);
        end

        function ys = smoothCopy(y,k)
            % Moving mean over k samples, NaN kept where y has them.
            if k <= 1, ys = y; return; end
            ys = movmean(y,round(k),'omitnan');
            ys(~isfinite(y)) = NaN;
        end

        function v = valueAt(t,y,lat)
            % y at a latency by linear interpolation (NaN outside the data).
            ok = isfinite(t) & isfinite(y);
            if nnz(ok) < 2 || ~isfinite(lat), v = NaN; return; end
            v = interp1(t(ok),y(ok),lat,'linear',NaN);
        end

        function v = interpCols(t,X,lat)
            % X(:,k) at lat(k) by linear interpolation, for every column.
            [nT,K] = size(X);
            v = nan(1,K);
            dt = mabr.analysis.Peaks.dt(t);
            pos = (lat - t(1))/dt + 1;
            i0 = floor(pos);
            ok = isfinite(pos) & i0 >= 1 & i0 <= nT;
            f = pos - i0;
            i1 = min(i0 + 1,nT);
            col = 1:K;
            a = X(sub2ind([nT K],i0(ok),col(ok)));
            b = X(sub2ind([nT K],i1(ok),col(ok)));
            v(ok) = a.*(1 - f(ok)) + b.*f(ok);
        end

        function v = promFloor(v)
            % A candidate-prominence floor (V), NaN read as none (0).
            %
            % Session.pickPeaks scales the floor by each level's RN, which is
            % NaN where a level has one clean sweep; a negative floor is a
            % caller's error and says so.
            if any(v(:) < 0)
                error('mabr:analysis:Peaks:prominence', ...
                    'A candidate prominence floor must be non-negative (NaN = no floor).');
            end
            v(isnan(v)) = 0;
        end

        function d = dt(t)
            % Sample interval of a time vector (ms).
            if numel(t) < 2, d = 1; return; end
            d = median(diff(t));
        end

        function checkTime(t,y)
            if numel(t) ~= numel(y)
                error('mabr:analysis:Peaks:time', ...
                    'tMs has %d samples and the waveform %d.',numel(t),numel(y));
            end
        end
    end
end
