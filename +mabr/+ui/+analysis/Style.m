classdef Style
% mabr.ui.analysis.Style  The colours, glyphs and number formats every analysis view shares.
%
%   One place for what a colour or a mark MEANS, so the browser, the grid,
%   the series stack and the study plots cannot disagree: green is a final
%   threshold, a dashed red line the fit when it differs, grey what lies below
%   threshold, amber the thing selected. The chrome colours are the ones the
%   acquisition app already uses (mabr.ui.App's panels, the status line),
%   so the two windows read as one program.
%
%       c = mabr.ui.analysis.Style.FinalGreen;
%       s = mabr.ui.analysis.Style.formatThreshold(row)   % "35 (30-40]"
%       mabr.ui.analysis.Style.setButtonIcon(btn,'accept','left')
%
%   GLYPHS (text, so a table cell or a tree node can carry them):
%     session status   ○ not analysed  ● current  ◐ out of date
%                      ✓ fully reviewed  ✕ failed
%     decision         ✓ accepted  ✎ manual  ∅ no response  ≤ all respond
%                      ✕ excluded  ⚑ flagged, not reviewed
%     detection        ● detected  ○ not detected; ■ □ the same, overridden
%     badges           ⧉ interleaved run  ⚠ short run  TEST Test Mode
%
%   Wave colours are mabr.analysis.Peaks.waveColor (Okabe-Ito), so a wave is
%   the same colour in every view and in an exported figure.
%
%   See also mabr.ui.analysis.Compat, mabr.ui.Icon, mabr.analysis.Peaks
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        % ---- chrome (mabr.ui.App's) -----------------------------------------
        Ink          = [0.243 0.271 0.318]
        Muted        = [0.478 0.514 0.565]
        Panel        = [0.969 0.973 0.980]
        DataBlue     = [0.216 0.451 0.678]
        Accent       = [0.898 0.616 0.180]
        AccentText   = [0.702 0.420 0]
        Good         = [0 0.5 0]
        Warn         = [0.8 0.2 0]
        Error        = [0.75 0.15 0.15]
        Busy         = [0.1 0.3 0.7]

        % ---- meaning in the plots ------------------------------------------
        FinalGreen   = [0.10 0.60 0.25]   % the final (curated) threshold
        FitRed       = [0.80 0.20 0.20]   % the fit, where it differs
        SubThreshold = [0.70 0.70 0.70]   % traces below threshold

        % ---- notification bar backgrounds ----------------------------------
        BarRed       = [0.97 0.80 0.80]
        BarYellow    = [1 0.95 0.75]
        BarAmber     = [1 0.88 0.70]
        BarBlue      = [0.86 0.91 0.98]

        % ---- status chip (header) backgrounds, by Model.Status.State --------
        ChipGrey     = [0.90 0.91 0.93]
        ChipGreen    = [0.84 0.93 0.85]
        ChipAmber    = [1 0.90 0.72]
        ChipRed      = [0.97 0.80 0.80]

        % ---- glyphs --------------------------------------------------------
        GlyphNotAnalysed = "○"
        GlyphCurrent     = "●"
        GlyphStale       = "◐"
        GlyphReviewed    = "✓"
        GlyphFailed      = "✕"

        GlyphAccepted    = "✓"
        GlyphManual      = "✎"
        GlyphNoResponse  = "∅"
        GlyphAllRespond  = "≤"
        GlyphExcluded    = "✕"
        GlyphFlagged     = "⚑"

        GlyphDetected    = "●"
        GlyphUndetected  = "○"
        GlyphOverrideOn  = "■"
        GlyphOverrideOff = "□"

        BadgeInterleaved = "⧉"
        BadgeShort       = "⚠"
        BadgeTest        = "TEST"

        % The Okabe-Ito palette (colour-blind safe), in the order series are
        % coloured: orange, sky blue, bluish green, yellow, blue, vermillion,
        % reddish purple, black.
        OkabeIto = [0.902 0.624 0.000
                    0.337 0.706 0.914
                    0.000 0.620 0.451
                    0.941 0.894 0.259
                    0.000 0.447 0.698
                    0.835 0.369 0.000
                    0.800 0.475 0.655
                    0.000 0.000 0.000]
    end

    methods (Static)
        % =================================================================
        %  Numbers as text
        % =================================================================
        function s = formatThreshold(row)
            % The curated threshold of a Thresholds row as display text:
            % "34.9", "35 (30–40]", ">80", "≤0", "n/a".
            %
            % Reads the row's Final, FinalCensored, FinalLo and FinalHi (the
            % curated value, SeriesThreshold.finalValue); a row without them
            % (a v1 results file) falls back to Threshold/Censored/ThrLo/ThrHi.
            %   row  one Thresholds row: table row or struct ([] -> "n/a")
            %   s    (returned) 1x1 string
            s = "n/a";
            if isempty(row), return; end
            try
                if istable(row), row = table2struct(row(1,:)); end
                if isfield(row,'Final')
                    v = double(row.Final);
                    c = mabr.ui.analysis.Style.fieldOr(row,'FinalCensored',"none");
                    lo = double(mabr.ui.analysis.Style.fieldOr(row,'FinalLo',NaN));
                    hi = double(mabr.ui.analysis.Style.fieldOr(row,'FinalHi',NaN));
                else
                    v = double(mabr.ui.analysis.Style.fieldOr(row,'Threshold',NaN));
                    c = mabr.ui.analysis.Style.fieldOr(row,'Censored',"none");
                    lo = double(mabr.ui.analysis.Style.fieldOr(row,'ThrLo',NaN));
                    hi = double(mabr.ui.analysis.Style.fieldOr(row,'ThrHi',NaN));
                end
                c = string(c);
                if ismissing(c), c = ""; end
                s = mabr.analysis.SeriesThreshold.formatValue(v,c,lo,hi);
            catch
                s = "n/a";
            end
        end

        function s = formatUV(v,digits)
            % Volts as microvolts: "3.41 µV". NaN -> "–".
            %   v       value in volts (scalar)
            %   digits  significant digits (default 3)
            if nargin < 2, digits = 3; end
            if isempty(v) || ~isfinite(v)
                s = "–";
                return
            end
            x = 1e6*double(v);
            if abs(x) >= 10^digits
                % whole microvolts rather than "1e+03 µV"
                s = string(sprintf('%.0f µV',x));
            else
                s = string(sprintf('%.*g µV',digits,x));
            end
        end

        function s = formatMs(v,decimals)
            % Milliseconds: "2.58 ms". NaN -> "–".
            %   v         value in ms (scalar)
            %   decimals  digits after the point (default 2)
            if nargin < 2, decimals = 2; end
            if isempty(v) || ~isfinite(v)
                s = "–";
                return
            end
            s = string(sprintf('%.*f ms',decimals,double(v)));
        end

        function s = formatSeconds(sec)
            % A duration estimate for a button: "≈25 s", "≈4 min", "≈1.5 h".
            if isempty(sec) || ~isfinite(sec) || sec < 0
                s = "";
            elseif sec < 1
                s = "<1 s";
            elseif sec < 90
                s = "≈" + round(sec) + " s";
            elseif sec < 5400
                s = "≈" + round(sec/60) + " min";
            else
                s = "≈" + sprintf('%.1f',sec/3600) + " h";
            end
        end

        % =================================================================
        %  Colours
        % =================================================================
        function c = colorFor(index,n)
            % The colour of the index-th of n series: Okabe-Ito while there
            % are colours left in it, then a perceptual ramp
            % (mabr.analysis.Plot.palette "blue" without its first, nearly
            % white entry), so 20 lines are still 20 colours.
            %   index  1-based (scalar or vector)
            %   n      how many series there are (default max(index))
            %   c      (returned) [numel(index) x 3] RGB
            if nargin < 2 || isempty(n), n = max(index); end
            K  = mabr.ui.analysis.Style.OkabeIto;
            nK = size(K,1);
            c  = zeros(numel(index),3);
            extra = max(0,n - nK);
            ramp = [];
            if extra > 0
                ramp = mabr.analysis.Plot.palette(extra + 1,"blue");
                ramp = ramp(2:end,:);
            end
            for i = 1:numel(index)
                k = index(i);
                if k >= 1 && k <= nK
                    c(i,:) = K(k,:);
                elseif k > nK && ~isempty(ramp)
                    c(i,:) = ramp(min(k - nK,size(ramp,1)),:);
                else
                    c(i,:) = mabr.ui.analysis.Style.Muted;
                end
            end
        end

        function c = waveColor(name)
            % mabr.analysis.Peaks.waveColor, here so a view needs one class.
            c = mabr.analysis.Peaks.waveColor(name);
        end

        function [bg,fg] = chipColors(state)
            % Background and text colour of the header status chip for a
            % Model.Status.State: grey (none, not analysed), green (current),
            % amber (stale), red (failed).
            switch string(state)
                case "current"
                    bg = mabr.ui.analysis.Style.ChipGreen;  fg = mabr.ui.analysis.Style.Good;
                case "stale"
                    bg = mabr.ui.analysis.Style.ChipAmber;  fg = mabr.ui.analysis.Style.AccentText;
                case "failed"
                    bg = mabr.ui.analysis.Style.ChipRed;    fg = mabr.ui.analysis.Style.Error;
                otherwise
                    bg = mabr.ui.analysis.Style.ChipGrey;   fg = mabr.ui.analysis.Style.Ink;
            end
        end

        function c = levelColor(level)
            % Status-line text colour of a message level (0 info, 1 warning,
            % 2 error).
            switch level
                case 1,    c = mabr.ui.analysis.Style.Warn;
                case 2,    c = mabr.ui.analysis.Style.Error;
                otherwise, c = mabr.ui.analysis.Style.Ink;
            end
        end

        % =================================================================
        %  Glyphs
        % =================================================================
        function g = statusGlyph(state,reviewed)
            % The session glyph of the browser: ○ ● ◐ ✓ ✕. reviewed (default
            % false) turns a current session's ● into ✓.
            if nargin < 2, reviewed = false; end
            switch string(state)
                case "current"
                    if reviewed, g = mabr.ui.analysis.Style.GlyphReviewed;
                    else,        g = mabr.ui.analysis.Style.GlyphCurrent; end
                case "stale",  g = mabr.ui.analysis.Style.GlyphStale;
                case "failed", g = mabr.ui.analysis.Style.GlyphFailed;
                otherwise,     g = mabr.ui.analysis.Style.GlyphNotAnalysed;
            end
        end

        function g = decisionGlyph(decision,flags)
            % The series glyph of a curation decision: ✓ ✎ ∅ ≤ ✕, ⚑ for an
            % unreviewed series carrying flags, "" for one that is merely
            % unreviewed.
            if nargin < 2, flags = ""; end
            d = string(decision);
            if isempty(d) || ismissing(d), d = ""; end
            switch d
                case "accepted",   g = mabr.ui.analysis.Style.GlyphAccepted;
                case "manual",     g = mabr.ui.analysis.Style.GlyphManual;
                case "noresponse", g = mabr.ui.analysis.Style.GlyphNoResponse;
                case "allrespond", g = mabr.ui.analysis.Style.GlyphAllRespond;
                case "excluded",   g = mabr.ui.analysis.Style.GlyphExcluded;
                otherwise
                    f = string(flags);
                    if any(strlength(f(~ismissing(f))) > 0)
                        g = mabr.ui.analysis.Style.GlyphFlagged;
                    else
                        g = "";
                    end
            end
        end

        function g = detectionGlyph(detected,overridden)
            % ● / ○ for a level's detection, ■ / □ when an override decided it.
            if nargin < 2, overridden = false; end
            if overridden
                if detected, g = mabr.ui.analysis.Style.GlyphOverrideOn;
                else,        g = mabr.ui.analysis.Style.GlyphOverrideOff; end
            else
                if detected, g = mabr.ui.analysis.Style.GlyphDetected;
                else,        g = mabr.ui.analysis.Style.GlyphUndetected; end
            end
        end

        % =================================================================
        %  Series names where room is short
        % =================================================================
        function s = compactSeriesLabels(labels)
            % Series names (Session.seriesLabel) for a narrow place -- a
            % list column, a grid column's title: the acquisition mode as
            % the browser's badge ("Tone 8 kHz ⧉" for the interleaved run,
            % nothing for the conventional one, which is how the Session
            % tab's heat map already names them), and the stimulus word left
            % out when every name starts with the same one ("8 kHz" rather
            % than "Tone 8 kHz" down a list of tones). The mode is the part
            % that tells two series of one stimulus apart, so it is the part
            % that must not be cut off.
            %   labels  string array of series names
            %   s       (returned) the same shape, shortened
            s = string(labels);
            if isempty(s), return; end
            s(ismissing(s)) = "";
            s = replace(s," · conventional","");
            s = replace(s," · interleaved"," " + mabr.ui.analysis.Style.BadgeInterleaved);
            first = extractBefore(s + " "," ");
            if numel(s) > 1 && first(1) ~= "" && all(first == first(1)) && ...
                    all(strlength(s) > strlength(first(1)) + 1)
                s = strtrim(extractAfter(s,strlength(first(1))));
            end
        end

        % =================================================================
        %  Axes in their panels
        % =================================================================
        function pinAxes(panel,ax,margins)
            % Keep AX inside PANEL with fixed margins in PIXELS, however the
            % panel is sized: the tick labels, axis labels and anything drawn
            % outside the plot box (a second ruler) keep their room. The
            % panel's AutoResizeChildren goes off -- left on, a uifigure
            % rescales a normalized axes from whatever size the panel had
            % before the grid laid it out, which put axes half out of their
            % panels -- and its SizeChangedFcn places the axes again.
            %   panel    a uipanel holding AX
            %   ax       the axes
            %   margins  [left bottom right top], pixels
            try
                panel.AutoResizeChildren = 'off';
            catch
            end
            try
                panel.SizeChangedFcn = @(src,~) mabr.ui.analysis.Style.placeAxes(src,ax,margins);
            catch
            end
            setappdata(ax,'MABRAxesMargins',double(margins));
            mabr.ui.analysis.Style.placeAxes(panel,ax,margins);
        end

        function ok = placeAxes(panel,ax,margins)
            % Put AX at MARGINS (pixels, [left bottom right top]) inside
            % PANEL now. Without MARGINS, the ones pinAxes recorded. False
            % (nothing moved) while the panel is too small to be laid out.
            ok = false;
            try
                if isempty(ax) || ~isvalid(ax) || isempty(panel) || ~isvalid(panel), return; end
                if nargin < 3 || isempty(margins)
                    margins = getappdata(ax,'MABRAxesMargins');
                    if isempty(margins), return; end
                end
                pos = getpixelposition(panel);
                W = pos(3);  H = pos(4);
                if ~(W > margins(1) + margins(3) + 20 && H > margins(2) + margins(4) + 20), return; end
                P = [margins(1)/W, margins(2)/H, (W - margins(1) - margins(3))/W, ...
                    (H - margins(2) - margins(4))/H];
                if ~strcmp(ax.Units,'normalized'), ax.Units = 'normalized'; end
                if any(abs(ax.Position - P) > 1e-6), ax.Position = P; end
                ok = true;
            catch
            end
        end

        % =================================================================
        %  Pictures on buttons
        % =================================================================
        function ok = setButtonIcon(btn,glyph,align)
            % Put a mabr.ui.Icon pictogram on a uibutton, keeping its caption.
            %
            % The art is the toolbars' (mabr.ui.Icon.file paints it as a
            % transparent PNG), so a button and the toolbar button for the
            % same action wear the same picture. If the picture cannot be had
            % -- the file cannot be written, or the glyph is not (yet) one
            % mabr.ui.Icon draws -- the button keeps its text and nothing
            % else, which is how it works without a picture. Callers name the
            % glyph as a LITERAL second argument, which is what
            % tests/verify_icons.m reads to check every glyph exists.
            %
            %   btn    a uibutton (or uicontrol-like with Icon/IconAlignment)
            %   glyph  a mabr.ui.Icon name
            %   align  'left' (default), 'top', 'center' or 'right'
            %   ok     (returned) true when the picture was set
            if nargin < 3 || isempty(align), align = 'left'; end
            ok = false;
            try
                f = mabr.ui.Icon.file(char(glyph));
            catch
                f = '';   % an unknown glyph (mabr:ui:Icon:unknown): text only
            end
            if isempty(f), return; end
            try
                btn.Icon = f;
                btn.IconAlignment = char(align);
                ok = true;
            catch
            end
        end
    end

    methods (Static, Access = private)
        function v = fieldOr(s,name,default)
            if isfield(s,name)
                v = s.(name);
                if isempty(v), v = default; end
            else
                v = default;
            end
        end
    end
end
