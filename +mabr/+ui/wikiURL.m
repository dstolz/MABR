function url = wikiURL(page)
% mabr.ui.wikiURL  The address of a MABR wiki page.
%
%   url = wikiURL()      the wiki's front page
%   url = wikiURL(page)  a named page, e.g. wikiURL('Test-Mode')
%
%   One place the address lives, so a menu item, a toolbar button and a
%   hyperlink inside a dialog cannot end up pointing at three different
%   spellings of it. The wiki is a SEPARATE repository (see CLAUDE.md) --
%   there is no copy of it in this tree to link to instead, which is exactly
%   why the URL is worth centralizing.
%
%   `page` is the wiki's own page name, hyphens and all (the title 'Test
%   Mode' is published as the page 'Test-Mode'); it is passed through
%   unaltered, since only the wiki knows how its pages are named.
%
% Daniel Stolzberg (c) 2026

base = 'https://github.com/dstolz/MABR/wiki';
if nargin < 1 || isempty(page)
    url = base;
else
    url = [base '/' char(page)];
end
end
