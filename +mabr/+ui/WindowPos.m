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
        function restore(fig,name,defaultPos)
            % Place fig at its remembered position, or at defaultPos if there
            % is none (or the remembered one is off-screen / malformed).
            if isempty(fig) || ~isgraphics(fig), return; end
            pos = getpref('MABR',['WindowPos_' name],[]);
            if ~isnumeric(pos) || numel(pos) ~= 4 || ~all(isfinite(pos)) || any(pos(3:4) <= 0)
                pos = defaultPos;
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
            % Nudge a window fully onto the primary display, shrinking it only
            % if it is genuinely larger than the screen.
            scr = get(0,'ScreenSize');          % [1 1 W H]
            pos(3) = min(pos(3),scr(3));
            pos(4) = min(pos(4),scr(4) - 40);   % leave room for the title bar
            pos(1) = min(max(pos(1),scr(1)),scr(1) + scr(3) - pos(3));
            pos(2) = min(max(pos(2),scr(2)),scr(2) + scr(4) - pos(4) - 40);
        end
    end
end
