classdef Icon
% mabr.ui.Icon  Render a 16x16 toolbar icon from ASCII art.
%
%   Toolbar buttons take CData, not text, so every glyph in the app is drawn
%   as one 16-char string per row: 'X' is inked in the given colour and '.'
%   is transparent (NaN), leaving the system button background showing
%   through. Kept as art rather than index math because the shapes have to
%   be legible at 16 px and that is only checkable by looking at them.
%
%       cdata = mabr.ui.Icon.fromArt(rows,[0.16 0.26 0.42]);
%
%   Used by mabr.ui.App (toolbar) and mabr.ui.TraceOrganizer (toolbar).
%
% Daniel Stolzberg (c) 2019-2026

    methods (Static)
        function c = fromArt(rows,rgb)
            mask = char(rows) == 'X';                 % 16x16 logical
            c = nan(16,16,3);
            for ch = 1:3
                plane = nan(16,16);
                plane(mask) = rgb(ch);
                c(:,:,ch) = plane;
            end
        end
    end
end
