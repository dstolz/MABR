classdef WindowPos
% mabr.ui.WindowPos  Remember where a window was left, across sessions.
%
%   The acquisition GUI opens its viewers automatically, so where they land
%   matters: a layout the user arranges once should survive quitting MATLAB.
%   Positions are stored per-name in MATLAB prefs alongside the App's other
%   history (group 'MABR', key 'WindowPos_<name>').
%
%       mabr.ui.WindowPos.restore(fig,'LivePlot',defaultPos);  % on open
%       mabr.ui.WindowPos.remember(fig,'LivePlot');            % on close
%
%   A remembered position is only honoured if it still lands on the current
%   display -- monitors get unplugged, and a window restored onto a screen
%   that no longer exists is unreachable. Everything is clamped into the
%   visible screen area before being applied.
%
% Daniel Stolzberg (c) 2019-2026

    methods (Static)
        function restore(fig,name,defaultPos,minSize)
            % Place fig at its remembered position, or at defaultPos if there
            % is none (or the remembered one is off-screen / malformed).
            % minSize (optional) [w h] in pixels: a window remembered from a
            % version that needed less room reopens too small to use, so grow
            % it to fit rather than discarding the spot the user chose.
            if isempty(fig) || ~isgraphics(fig), return; end
            if nargin < 4, minSize = []; end
            pos = getpref('MABR',['WindowPos_' name],[]);
            if ~isnumeric(pos) || numel(pos) ~= 4 || ~all(isfinite(pos)) || any(pos(3:4) <= 0)
                pos = defaultPos;
            end
            if ~isempty(minSize)
                pos(3:4) = max(pos(3:4),minSize(:).');
            end
            fig.Position = mabr.ui.WindowPos.clampToScreen(pos);
        end

        function remember(fig,name)
            % Store the window's current position. Silent no-op for a window
            % that has already been destroyed -- callers invoke this from
            % close paths where the figure may or may not still be there.
            if isempty(fig) || ~isgraphics(fig), return; end
            setpref('MABR',['WindowPos_' name],fig.Position);
        end

        function pos = clampToScreen(pos)
            % Nudge a window fully onto whichever display it actually belongs
            % to, shrinking it only if it is genuinely larger than that
            % display. get(0,'ScreenSize') always reports the PRIMARY monitor
            % only, no matter how many are attached, so clamping against it
            % unconditionally would drag every window on a second monitor back
            % onto the first one on every restore -- the opposite of what a
            % multi-monitor rig needs. Instead, find the monitor whose bounds
            % actually contain this window's centre, and clamp within that
            % one; only fall back to the primary display when no monitor
            % claims it (the genuine "that screen is unplugged" case).
            mp = get(0,'MonitorPositions');     % one [x y w h] row per display
            cx = pos(1) + pos(3)/2;
            cy = pos(2) + pos(4)/2;
            inMon = cx >= mp(:,1) & cx < mp(:,1)+mp(:,3) & cy >= mp(:,2) & cy < mp(:,2)+mp(:,4);
            row = find(inMon,1);
            if isempty(row)
                row = find(mp(:,1) == 1 & mp(:,2) == 1,1);   % primary display's origin
                if isempty(row), row = 1; end
            end
            scr = mp(row,:);
            pos(3) = min(pos(3),scr(3));
            pos(4) = min(pos(4),scr(4) - 40);   % leave room for the title bar
            pos(1) = min(max(pos(1),scr(1)),scr(1) + scr(3) - pos(3));
            pos(2) = min(max(pos(2),scr(2)),scr(2) + scr(4) - pos(4) - 40);
        end
    end
end
