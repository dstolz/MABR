classdef ThresholdDrag < handle
% mabr.ui.analysis.ThresholdDrag  Dragging a series' threshold divider: the gesture, where it snaps, the decision it makes.
%
%   The Series stack, the Series evidence plot and every Grid column draw a
%   series' final threshold as a green divider, and each lets that divider
%   be dragged to a new place. This class is the part they share: the rule
%   that turns a position into a decision (pure statics, tested without a
%   window), and one drag -- from the press to the release -- with the
%   figure callbacks it needs while the button is down.
%
%   THE RULE (outcome). A position runs along the series' rows, LOUDER
%   LARGER: a stack's row height, or a level axis' value times the level
%   direction (+1, or -1 on an attenuation axis, where a larger number is
%   quieter). Dropped
%     above the loudest row      No response        Model.setNoResponse
%     below the quietest row     All respond        Model.setAllRespond
%     between two rows           the louder row is the lowest level with a
%                                response            Model.setThresholdAtLevel
%                                -- exactly what "t" on that level decides:
%                                the interval between the two levels, its
%                                point by the project's convention (the
%                                midpoint by default; the threshold rules'
%                                own convention for a level-only decision)
%     ... with Alt held          the value at the pointer, to 0.1 dB,
%                                uncensored         Model.setThresholdValue
%   so the divider SNAPS half way between the two tested levels, and with
%   Alt sits where it is let go. Every one is the Model's curation call the
%   buttons make: one undo step (Ctrl+Z), autosaved, recorded in the
%   session's EditLog ("setDecision", with the decision and the value),
%   reviewed by the analyst, blind-review safe. Nothing is asked: the status
%   line says what was set, and Ctrl+Z takes it back. A drop that changes
%   nothing (the decision already there) is not an edit. The preview is
%   what the Session will compute (predict, through
%   SeriesThreshold.finalValue), so on an attenuation axis no response and
%   all respond are censored on the NUMBERS' side as there ("≤ 0", "> 80")
%   and drawn where the release will leave them.
%
%   THE GESTURE. A view makes one ThresholdDrag on a press over the divider
%   (within HitPixels across it) or its grip, and calls begin(pos). Until the
%   pointer has moved StartPixels nothing happens, and a release there is
%   the view's ordinary click (Click): a press near the divider still
%   selects a level or places a peak. Once moving, the view's Preview draws
%   the divider where a release would put it with a readout ("Threshold
%   37.5 dB SPL"), and the status line gives the whole of it. Release
%   commits; Esc -- the window's key while dragging, or the app's "nav.
%   escape" (cancel()) -- puts everything back; any other key ends the drag
%   and then does what it does. Alt is read from the key presses during the
%   drag and from the window's CurrentModifier at the press and the release
%   (whichever saw it), so it may be pressed before or during the drag. The
%   pointer is the vertical (or, along a level axis, horizontal) resize
%   arrow while dragging (Compat.setPointer; nothing where a release cannot
%   show one).
%
%   For tests and scripts: begin(pos), moveTo(pos), releaseAt(pos), cancel()
%   and setAlt(tf) are the gesture without a mouse; onMotion/onUp/onKey are
%   what the figure's callbacks call (they read the axes' CurrentPoint,
%   which follows the figure's settable CurrentPoint).
%
%   See also mabr.ui.analysis.SeriesView, mabr.ui.analysis.GridView,
%   mabr.ui.analysis.Model.setThresholdAtLevel, mabr.analysis.SeriesThreshold.finalValue
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        HitPixels   = 5      % a press this close to the divider (px, across it) takes it
        GripPixels  = 9      % ... or this close to its grip (px)
        StartPixels = 3      % px the pointer moves before a press is a drag
        Hint = "drag the green line to set the threshold; Alt for an exact value"
    end

    properties (SetAccess = private)
        Active (1,1) logical = false     % between the press and the release
        Moved (1,1) logical = false      % the pointer has moved: it is a drag
        Alt (1,1) logical = false        % Alt is held: the exact value
        Outcome = []                     % what a release now would decide (outcome + F, Short, Long)
        SeriesKey (1,1) string = ""
        SessionKey (1,1) string = ""
    end

    properties (Access = private)
        Fig = []
        Ax = []
        Model = []
        Row = []                         % the series' Thresholds row (struct, Fit unwrapped)
        Unit (1,1) string = ""
        Pos = zeros(0,1)                 % the rows' positions, louder larger
        Levels = zeros(0,1)              % ... and their levels
        Axis (1,1) string = "y"          % which coordinate of CurrentPoint is the position
        Scale (1,1) double = 1           % position = Scale * that coordinate
        PxPerUnit (1,1) double = NaN     % pixels per unit of position (StartPixels)
        Pos0 (1,1) double = NaN
        LastPos (1,1) double = NaN
        AltSeenUp (1,1) logical = false  % an Alt release was seen during the drag
        Saved = []                       % the figure's callbacks and pointer before the drag
        PointerName (1,1) string = "top"
        PreviewFcn = []                  % @(o): draw the divider where a release puts it
        EndFcn = []                      % @(committed): tidy up (committed false: put it back)
        ClickFcn = []                    % @(): a press released without moving
        StatusFcn = []                   % @(text,level): the status line
        WrapFcn = []                     % @(fcn): a component callback wrapper (errors -> status)
        LastLong (1,1) string = ""
    end

    % =====================================================================
    methods
        function obj = ThresholdDrag(ax,model,seriesKey,pos,levels,opts)
            % ThresholdDrag(ax,model,seriesKey,pos,levels,Name=Value)
            %   ax         the axes the drag happens in (its CurrentPoint)
            %   model      mabr.ui.analysis.Model
            %   seriesKey  the series whose threshold is set
            %   pos        the rows' positions (louder larger) ...
            %   levels     ... and their levels (NaN rows are left out)
            %   Row        the series' Thresholds row (default: read from the
            %              open session), for the readout's numbers
            %   Unit       the level unit ("dB SPL"; "" none)
            %   Axis       "y" (a stack) or "x" (a level axis)
            %   Scale      position = Scale * the coordinate (-1: attenuation)
            %   PxPerUnit  pixels per unit of position
            %   Pointer    the pointer while dragging ("top" | "left")
            %   Preview, End, Click, Status, Wrap   the view's functions
            arguments
                ax
                model
                seriesKey (1,1) string
                pos double
                levels double
                opts.Row = []
                opts.Unit (1,1) string = ""
                opts.Axis (1,1) string {mustBeMember(opts.Axis,["x","y"])} = "y"
                opts.Scale (1,1) double = 1
                opts.PxPerUnit (1,1) double = NaN
                opts.Pointer (1,1) string = "top"
                opts.Preview = []
                opts.End = []
                opts.Click = []
                opts.Status = []
                opts.Wrap = []
            end
            obj.Ax = ax;
            obj.Fig = ancestor(ax,'figure');
            obj.Model = model;
            obj.SeriesKey = seriesKey;
            try
                obj.SessionKey = string(model.SessionKey);
            catch
            end
            ok = isfinite(pos(:)) & isfinite(levels(:));
            obj.Pos = reshape(double(pos(ok)),[],1);
            obj.Levels = reshape(double(levels(ok)),[],1);
            obj.Row = opts.Row;
            if isempty(obj.Row)
                try
                    obj.Row = mabr.ui.analysis.ThresholdDrag.seriesRow(model.Session,seriesKey);
                catch
                end
            end
            obj.Unit = opts.Unit;
            obj.Axis = opts.Axis;
            obj.Scale = opts.Scale;
            obj.PxPerUnit = opts.PxPerUnit;
            obj.PointerName = opts.Pointer;
            obj.PreviewFcn = opts.Preview;
            obj.EndFcn = opts.End;
            obj.ClickFcn = opts.Click;
            obj.StatusFcn = opts.Status;
            obj.WrapFcn = opts.Wrap;
        end

        function delete(obj)
            % A drag still installed when its view goes: the window's
            % callbacks back as they were.
            try
                if obj.Active, obj.restore(); end
            catch
            end
        end

        function begin(obj,pos,opts)
            % The press, at position POS: install the drag's callbacks.
            % opts.Moved  true: a drag at once (a click on a level axis
            %             sets the threshold where it lands)
            arguments
                obj
                pos (1,1) double
                opts.Moved (1,1) logical = false
            end
            if obj.Active, return; end
            obj.Pos0 = pos;
            obj.LastPos = pos;
            obj.Moved = false;
            obj.AltSeenUp = false;
            obj.Alt = mabr.ui.analysis.ThresholdDrag.altIn(obj.Fig);
            obj.install();
            obj.Active = true;
            if opts.Moved
                obj.Moved = true;
                obj.pointer(true);
                obj.moveTo(pos);
            end
        end

        function moveTo(obj,pos)
            % The pointer at POS: once it has moved StartPixels, the preview.
            if ~obj.Active || ~isfinite(pos), return; end
            obj.LastPos = pos;
            if ~obj.Moved
                px = abs(pos - obj.Pos0)*obj.PxPerUnit;
                if ~isfinite(px), px = Inf; end
                if px < obj.StartPixels, return; end
                obj.Moved = true;
                obj.pointer(true);
            end
            obj.preview(pos);
        end

        function releaseAt(obj,pos)
            % The release at POS: commit a drag; a press that never moved is
            % the view's ordinary click.
            if ~obj.Active, return; end
            if ~obj.Moved
                obj.finish(false);
                obj.callFcn(obj.ClickFcn);
                return
            end
            if isfinite(pos), obj.preview(pos); end
            obj.commit();
        end

        function cancel(obj)
            % Esc: nothing is changed, the divider goes back.
            if ~obj.Active, return; end
            moved = obj.Moved;
            obj.finish(false);
            if moved
                obj.say("Threshold not changed (drag cancelled).",0);
            end
        end

        function setAlt(obj,tf)
            % Alt held (true) or let go: the preview follows.
            arguments
                obj
                tf (1,1) logical
            end
            obj.Alt = tf;
            if ~tf, obj.AltSeenUp = true; end
            if obj.Active && obj.Moved, obj.preview(obj.LastPos); end
        end

        % ---- what the figure's callbacks call ----------------------------
        function onMotion(obj)
            try
                if obj.Active, obj.moveTo(obj.pointerPos()); end
            catch me
                mabr.log.vprintf(2,'Threshold drag: %s',me.message);
            end
        end

        function onUp(obj)
            if ~obj.Active, return; end
            % Alt held at the release counts unless the drag saw it let go
            if ~obj.Alt && ~obj.AltSeenUp && mabr.ui.analysis.ThresholdDrag.altIn(obj.Fig)
                obj.Alt = true;
            end
            obj.releaseAt(obj.pointerPos());
        end

        function onKey(obj,src,evt,down)
            % A key while the button is down: Alt switches to the exact
            % value, Esc cancels, a modifier does nothing, any other key ends
            % the drag and then does what it does.
            if ~obj.Active, return; end
            key = "";
            try
                key = lower(string(evt.Key));
            catch
            end
            if key == "alt"
                obj.setAlt(down);
                return
            end
            if ~down, return; end
            if key == "escape"
                obj.cancel();
                return
            end
            if any(key == ["shift","control","command","windows",""]), return; end
            prev = [];
            try
                prev = obj.Saved.KeyPress;
            catch
            end
            obj.cancel();
            if ~isempty(prev)
                try
                    prev(src,evt);
                catch me
                    mabr.log.vprintf(2,'Threshold drag: key after the drag (%s).',me.message);
                end
            end
        end
    end

    % =====================================================================
    methods (Static)
        function o = outcome(pos,rowPos,levels,alt)
            % The decision a divider dropped at POS makes (the class help).
            %   pos      the position, louder larger
            %   rowPos   the rows' positions (any order; NaN rows ignored)
            %   levels   the rows' levels
            %   alt      true: the exact value between the rows
            %   o        (returned) struct Kind ("noresponse" | "allrespond"
            %            | "level" | "value" | "" when there is nothing to
            %            decide: fewer than two rows), Level (the lowest
            %            level with a response, "level"), Value ("value",
            %            to 0.1), Lo and Hi (the rows' levels it falls
            %            between, or the bound beyond the loudest/quietest),
            %            Pos, Dir (+1: the numbers grow with loudness, -1:
            %            they shrink -- an attenuation axis)
            if nargin < 4, alt = false; end
            o = struct('Kind',"",'Level',NaN,'Value',NaN,'Lo',NaN,'Hi',NaN,'Pos',pos,'Dir',1);
            rowPos = double(rowPos(:));  levels = double(levels(:));
            ok = isfinite(rowPos) & isfinite(levels);
            p = rowPos(ok);  L = levels(ok);
            [p,ix] = sort(p);  L = L(ix);
            n = numel(p);
            if n < 2 || ~isfinite(pos), return; end
            if L(n) < L(1), o.Dir = -1; end
            if pos > p(n)
                o.Kind = "noresponse";
                o.Lo = L(n);
            elseif pos < p(1)
                o.Kind = "allrespond";
                o.Hi = L(1);
            else
                k = find(p <= pos,1,'last');
                k = min(k,n-1);
                o.Lo = L(k);  o.Hi = L(k+1);
                if alt
                    f = (pos - p(k))/(p(k+1) - p(k));
                    v = L(k) + f*(L(k+1) - L(k));
                    v = round(v*10)/10;
                    v = min(max(v,min(L(k),L(k+1))),max(L(k),L(k+1)));
                    o.Kind = "value";
                    o.Value = v;
                else
                    o.Kind = "level";
                    o.Level = L(k+1);
                end
            end
        end

        function F = predict(row,o)
            % The Final the decision O would give the series of ROW -- what
            % the Session will compute (SeriesThreshold.finalValue over the
            % row with the decision put in, at the row's convention), so a
            % preview is drawn exactly where the release will leave it.
            %   F  (returned) struct Final, FinalCensored, FinalLo, FinalHi
            F = struct('Final',NaN,'FinalCensored',"",'FinalLo',NaN,'FinalHi',NaN);
            if ~isstruct(o) || o.Kind == "", return; end
            r = row;
            if ~isstruct(r) || ~isscalar(r), r = struct(); end
            switch o.Kind
                case "level"
                    r.Decision = "manual";  r.ManualKind = "level";  r.ManualValue = o.Level;
                case "value"
                    r.Decision = "manual";  r.ManualKind = "value";  r.ManualValue = o.Value;
                otherwise
                    r.Decision = o.Kind;  r.ManualKind = "";  r.ManualValue = NaN;
            end
            conv = "midpoint";
            try
                c = string(r.Convention);
                if isscalar(c) && any(c == ["midpoint","lowest_level","crossing"]), conv = c; end
            catch
            end
            try
                F = mabr.analysis.SeriesThreshold.finalValue(r,conv);
            catch
            end
            % (a row without the bounds a censored decision stands on: the
            % rows the divider was dropped beyond -- censored on the side of
            % the NUMBERS, as SeriesThreshold.finalValue censors: on an
            % attenuation axis no response is "left" of the smallest, all
            % respond "right" of the largest. Only when the row gave no
            % bound at all: one of the two is NaN by design on either axis.)
            dir = 1;
            if isfield(o,'Dir') && isfinite(o.Dir) && o.Dir < 0, dir = -1; end
            if any(o.Kind == ["noresponse","allrespond"]) && ~isfinite(F.FinalLo) && ~isfinite(F.FinalHi)
                if o.Kind == "noresponse"
                    if dir > 0
                        F = struct('Final',Inf,'FinalCensored',"right",'FinalLo',o.Lo,'FinalHi',NaN);
                    else
                        F = struct('Final',-Inf,'FinalCensored',"left",'FinalLo',NaN,'FinalHi',o.Lo);
                    end
                elseif dir > 0
                    F = struct('Final',o.Hi,'FinalCensored',"left",'FinalLo',NaN,'FinalHi',o.Hi);
                else
                    F = struct('Final',o.Hi,'FinalCensored',"right",'FinalLo',o.Hi,'FinalHi',NaN);
                end
            end
        end

        function [short,long] = describe(o,F,unit)
            % The readout of a drop: SHORT for beside the divider ("Threshold
            % 37.5 dB SPL", "No response (> 80 dB SPL)"), LONG for the status
            % line (with the interval and what releasing does).
            short = "";  long = "";
            if ~isstruct(o) || o.Kind == "", return; end
            unit = string(unit);
            u = "";
            if unit ~= "", u = " " + unit; end
            num = @(v) mabr.analysis.SeriesThreshold.formatValue(double(v),"none");
            fc = string(F.FinalCensored);
            if isempty(fc) || ismissing(fc(1)), fc = ""; else, fc = fc(1); end
            % a censored bound in the numbers' own terms, as the series list
            % and the status line write it (SeriesThreshold.formatValue:
            % "right" is > its lower bound, "left" ≤ its upper one) -- on an
            % attenuation axis no response is "≤ 0", all respond "> 80"
            bound = "";
            if fc == "right" && isfinite(F.FinalLo)
                bound = "> " + num(F.FinalLo);
            elseif fc == "left" && isfinite(F.FinalHi)
                bound = "≤ " + num(F.FinalHi);
            end
            switch o.Kind
                case "noresponse"
                    if bound == "", bound = "> " + num(o.Lo); end
                    short = "No response (" + bound + u + ")";
                    long = "No response: the threshold is above the loudest level (" + bound + u + ")";
                case "allrespond"
                    if bound == "", bound = "≤ " + num(o.Hi); end
                    short = "All respond (" + bound + u + ")";
                    long = "All respond: the threshold is at or below the quietest level (" + bound + u + ")";
                case "value"
                    v = F.Final;  if ~isfinite(v), v = o.Value; end
                    short = "Threshold " + num(v) + u;
                    long = "Threshold " + num(v) + u + ", exactly (Alt)";
                otherwise
                    if bound ~= ""
                        % (the louder level is the extreme usable one: the
                        % threshold is censored there)
                        short = "Threshold " + bound + u;
                        long = short + ": " + num(o.Level) + u + " is the lowest level with a response";
                    else
                        v = F.Final;  if ~isfinite(v), v = (o.Lo + o.Hi)/2; end
                        short = "Threshold " + num(v) + u;
                        txt = mabr.analysis.SeriesThreshold.formatValue(F.Final,fc,F.FinalLo,F.FinalHi);
                        long = "Threshold " + txt + u + ": " + num(o.Level) + u + ...
                            " is the lowest level with a response";
                    end
            end
            long = long + "  ·  release to set";
            if o.Kind == "level", long = long + ", Alt for an exact value"; end
            long = long + ", Esc to cancel";
        end

        function rep = apply(model,o,seriesKey)
            % The decision O on SERIESKEY through the Model's curation call
            % (the one the buttons make: undo, autosave, EditLog).
            arguments
                model
                o (1,1) struct
                seriesKey (1,1) string
            end
            switch o.Kind
                case "level",      rep = model.setThresholdAtLevel(o.Level,seriesKey);
                case "value",      rep = model.setThresholdValue(o.Value,seriesKey);
                case "noresponse", rep = model.setNoResponse(seriesKey);
                case "allrespond", rep = model.setAllRespond(seriesKey);
                otherwise,         rep = [];
            end
        end

        function tf = sameDecision(row,o)
            % True when ROW already holds the decision O would make.
            tf = false;
            if ~isstruct(row) || ~isscalar(row) || ~isstruct(o), return; end
            f = @(nm,d) mabr.ui.analysis.ThresholdDrag.field(row,nm,d);
            d = lower(string(f('Decision',"")));
            switch o.Kind
                case {"noresponse","allrespond"}
                    tf = d == o.Kind;
                case {"level","value"}
                    v = o.Level;  if o.Kind == "value", v = o.Value; end
                    tf = d == "manual" && lower(string(f('ManualKind',""))) == o.Kind && ...
                        abs(double(f('ManualValue',NaN)) - v) < 1e-9;
            end
        end

        function row = seriesRow(S,seriesKey)
            % The series' Thresholds row as a struct (Fit unwrapped, text
            % fields as scalar strings), [] when there is none.
            row = [];
            try
                r = S.seriesRow(seriesKey);
                if isempty(r), return; end
                row = table2struct(S.Thresholds(r,:));
                if isfield(row,'Fit') && iscell(row.Fit)
                    if isempty(row.Fit), row.Fit = []; else, row.Fit = row.Fit{1}; end
                end
                for f = ["Decision","ManualKind","FinalCensored","Censored","Convention"]
                    if isfield(row,f)
                        s = string(row.(f));
                        if isempty(s) || ismissing(s(1)), s = ""; end
                        row.(f) = s(1);
                    end
                end
            catch
                row = [];
            end
        end

        function tf = altIn(fig)
            % Alt among the window's current modifiers (at the last key press
            % or click); false where the window cannot say.
            tf = false;
            try
                tf = any(strcmpi(string(fig.CurrentModifier),"alt"));
            catch
            end
        end
    end

    methods (Static, Access = private)
        function v = field(s,name,default)
            v = default;
            if isstruct(s) && isfield(s,name)
                v = s.(name);
                if isempty(v), v = default; end
                if iscell(v), v = v{1}; end
                if (isstring(v) || ischar(v)) && any(ismissing(string(v))), v = default; end
            end
        end
    end

    % =====================================================================
    methods (Access = private)
        function preview(obj,pos)
            % The outcome at POS, drawn by the view, said on the status line.
            o = mabr.ui.analysis.ThresholdDrag.outcome(pos,obj.Pos,obj.Levels,obj.Alt);
            if o.Kind == "", return; end
            F = mabr.ui.analysis.ThresholdDrag.predict(obj.Row,o);
            [s,l] = mabr.ui.analysis.ThresholdDrag.describe(o,F,obj.Unit);
            o.F = F;
            o.Short = s;
            o.Long = l;
            obj.Outcome = o;
            obj.callFcn(obj.PreviewFcn,o);
            if l ~= obj.LastLong
                obj.LastLong = l;
                obj.say(l,0);
            end
        end

        function commit(obj)
            % The release of a drag: the decision through the Model (or
            % nothing, when it is the one the series already has).
            o = obj.Outcome;
            m = obj.Model;
            stale = isempty(o) || ~isstruct(o) || o.Kind == "";
            try
                stale = stale || string(m.SessionKey) ~= obj.SessionKey || isempty(m.Session);
            catch
                stale = true;
            end
            if stale
                obj.finish(false);
                obj.say("Threshold not changed.",0);
                return
            end
            row = [];
            try
                row = mabr.ui.analysis.ThresholdDrag.seriesRow(m.Session,obj.SeriesKey);
            catch
            end
            if mabr.ui.analysis.ThresholdDrag.sameDecision(row,o)
                obj.finish(false);
                obj.say("Threshold unchanged — " + o.Short + " is already the decision.",0);
                return
            end
            obj.finish(true);
            try
                mabr.ui.analysis.ThresholdDrag.apply(m,o,obj.SeriesKey);
            catch me
                % (the divider back where the Model has it, then the reason
                % on the status line through the view's wrapper)
                obj.callFcn(obj.EndFcn,false);
                rethrow(me);
            end
        end

        function finish(obj,committed)
            obj.restore();
            obj.callFcn(obj.EndFcn,committed);
        end

        function install(obj)
            f = obj.Fig;
            obj.Saved = struct('Motion',{f.WindowButtonMotionFcn},'Up',{f.WindowButtonUpFcn}, ...
                'KeyPress',{f.WindowKeyPressFcn},'KeyRelease',{f.WindowKeyReleaseFcn}, ...
                'Pointer',"");
            try
                obj.Saved.Pointer = string(f.Pointer);
            catch
            end
            up = @(~,~) obj.onUp();
            if ~isempty(obj.WrapFcn)
                try
                    up = obj.WrapFcn(up);
                catch
                end
            end
            f.WindowButtonMotionFcn = @(~,~) obj.onMotion();
            f.WindowButtonUpFcn = up;
            f.WindowKeyPressFcn = @(s,e) obj.keySafe(s,e,true);
            f.WindowKeyReleaseFcn = @(s,e) obj.keySafe(s,e,false);
        end

        function keySafe(obj,src,evt,down)
            try
                obj.onKey(src,evt,down);
            catch me
                mabr.log.vprintf(2,'Threshold drag: key (%s).',me.message);
            end
        end

        function restore(obj)
            % The window's callbacks and pointer as they were before the press.
            obj.Active = false;
            s = obj.Saved;
            obj.Saved = [];
            if isempty(s), return; end
            try
                f = obj.Fig;
                if ~isempty(f) && isvalid(f)
                    f.WindowButtonMotionFcn = s.Motion;
                    f.WindowButtonUpFcn = s.Up;
                    f.WindowKeyPressFcn = s.KeyPress;
                    f.WindowKeyReleaseFcn = s.KeyRelease;
                    if s.Pointer ~= ""
                        mabr.ui.analysis.Compat.setPointer(f,s.Pointer);
                    end
                end
            catch me
                mabr.log.vprintf(2,'Threshold drag: window callbacks not restored (%s).',me.message);
            end
        end

        function pointer(obj,on)
            if on
                mabr.ui.analysis.Compat.setPointer(obj.Fig,obj.PointerName);
            end
        end

        function pos = pointerPos(obj)
            pos = NaN;
            try
                cp = obj.Ax.CurrentPoint;
                if obj.Axis == "x", v = cp(1,1); else, v = cp(1,2); end
                pos = obj.Scale*double(v);
            catch
            end
        end

        function say(obj,text,level)
            if isempty(obj.StatusFcn), return; end
            try
                obj.StatusFcn(text,level);
            catch
            end
        end

        function callFcn(obj,fcn,varargin)
            if isempty(fcn) || ~isvalid(obj), return; end
            fcn(varargin{:});
        end
    end
end
