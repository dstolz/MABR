function h = wikiLink(parent,page,text,tip)
% mabr.ui.wikiLink  A hyperlink to a MABR wiki page, for any uifigure layout.
%
%   h = wikiLink(parent,page)              'Documentation' -> that wiki page
%   h = wikiLink(parent,page,text)         with your own link text
%   h = wikiLink(parent,page,text,tip)     and your own tooltip
%
%   A mode the operator can switch on needs somewhere to read about what it
%   does before they trust the data that comes out of it, and the honest place
%   for that is beside the control rather than three menus away -- so this is
%   a component, not a menu item, and it goes in whatever grid row the caller
%   gives it.
%
%   uihyperlink arrived in R2021b, which is also mabr.Config's floor, so it is
%   available by definition. The fallback below is not defensiveness about the
%   release: it is there because a link that silently fails to build would
%   take the explanation of the mode with it, and a plain button that opens
%   the same page is a better answer than a blank row.
%
% Daniel Stolzberg (c) 2026

if nargin < 3 || isempty(text), text = 'Documentation'; end
if nargin < 4 || isempty(tip),  tip  = 'Opens the MABR wiki in your browser.'; end

url = mabr.ui.wikiURL(page);
try
    h = uihyperlink(parent,'Text',text,'URL',url,'Tooltip',tip);
catch
    h = uibutton(parent,'Text',text,'Tooltip',tip, ...
        'ButtonPushedFcn',@(~,~) web(url,'-browser'));
end
end
