function verify_icons()
% verify_icons  Confirm the toolbar pictograms (mabr.ui.Icon) render, and
%               that every toolbar and button names a glyph that exists.
%
%   Part A: every glyph renders to 16x16 colour in [0,1] and coverage in
%   [0,1], with something drawn and something left clear, and no two glyphs
%   are the same picture; redo is undo in a mirror, and the offline
%   analysis glyphs wear the colours their meaning calls for (an orange
%   arrow on export, figure and retrack, green on accept, batch, threshold
%   and restore, red on reject, exclude and noresponse).
%   Part B: toolbar() CData is what a uipushtool takes -- 16x16x3, finite
%   in [0,1] where drawn, NaN in all three planes together where not, and
%   transparent exactly where coverage is below MinAlpha; a fully covered
%   pixel is the glyph's own colour whatever the background, and only the
%   blended edge depends on it; a repeat call returns the cached array.
%   Part C: an unknown name is refused, and background() reads a toolbar's
%   colour where it has one and falls back where it does not.
%   Part D: every glyph name the toolbars and buttons ask for is one
%   render() knows -- mabr.ui.App, mabr.ui.TraceOrganizer, mabr.ui.Notes,
%   mabr.ui.PresentationOrder, and the offline analysis window:
%   mabr.ui.AnalysisApp and every file in +mabr/+ui/+analysis, found with
%   dir so a view added later is scanned without editing this list (a file
%   not written yet is skipped) -- and every glyph is asked for by one of
%   them. A glyph is asked for by a literal: toolButton('glyph',...),
%   Icon.toolbar/Icon.file('glyph'), setButtonIcon(button,'glyph',...),
%   viewIcon(button,'glyph'), or an action's Glyph field -- the button any
%   name, field or indexed element, the call free to run over lines with
%   "...", and a call's literal read whatever it holds, so 'no-response' is
%   reported rather than skipped. Comments, whole-line and block, are not
%   read, so a help example asks for nothing. The scanner is itself checked
%   first, on source written to exercise every one of those forms and the
%   look-alikes it must pass over (glyphRequests, checkScanner). A misspelt
%   name would otherwise surface only when that window was opened -- and
%   not even then on an analysis button, which quietly keeps its text --
%   while a glyph nothing asks for is a misspelt caller or dead art. That
%   second half is judged last, after Parts E and F, so a glyph still
%   waiting for its caller cannot hide a broken toolbar or PNG.
%   Part E: a trace organizer's toolbar is built from them: every tool
%   carries 16x16x3 CData and a tooltip.
%   Part F: every glyph is also a PNG (Icon.file), as a button uses it:
%   16x16, the glyph's own coverage as alpha rather than a baked-in
%   background (a uibutton's colour changes), cached by content -- and
%   every run-control glyph is one a button in App.m asks for, and the
%   presentation-order window's (skip next, disable above / below, enable
%   all, stay on top) are the same, asked for in PresentationOrder.m.
%
%   Opens one window (Part E), no hardware, no engine, no parallel pool, no
%   prefs touched. Look at the glyphs themselves with mabr.ui.Icon.preview.
%
%   Run:  >> verify_icons
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_icons ==\n');
names = mabr.ui.Icon.names();
N = mabr.ui.Icon.Size;
assert(numel(unique(names)) == numel(names),'Icon.names() lists a glyph twice');

% ---- Part A: every glyph renders ------------------------------------------
A = zeros(N,N,numel(names));
for k = 1:numel(names)
    [rgb,alpha] = mabr.ui.Icon.render(names{k});
    assert(isequal(size(rgb),[N N 3]) && isequal(size(alpha),[N N]), ...
        '%s: render must return 16x16x3 colour and 16x16 coverage',names{k});
    assert(all(isfinite(rgb(:))) && all(rgb(:) >= 0 & rgb(:) <= 1), ...
        '%s: colour must be finite and within [0,1]',names{k});
    assert(all(alpha(:) >= 0 & alpha(:) <= 1),'%s: coverage outside [0,1]',names{k});
    cov = mean(alpha(:));
    assert(cov > 0.1 && cov < 0.95, ...
        '%s: covers %.0f%% of the button -- nothing drawn, or nothing left clear', ...
        names{k},100*cov);
    A(:,:,k) = alpha;
end
for i = 1:numel(names)
    for j = i+1:numel(names)
        d = mean(mean(abs(A(:,:,i) - A(:,:,j))));
        assert(d > 0.05,'%s and %s are (nearly) the same shape',names{i},names{j});
    end
end
% Undo and redo are one arrow and its mirror image, so the pair cannot drift
% apart.
[ru,au] = mabr.ui.Icon.render('undo');
[rr,ar] = mabr.ui.Icon.render('redo');
assert(isequal(ar,fliplr(au)) && isequal(rr,flip(ru,2)), ...
    'redo must be undo in a mirror, pixel for pixel');
% The offline analysis glyphs wear the colour their meaning calls for (blue
% the data, orange the action, green done or brought back, red thrown out):
% each named colour is a visible part of the picture, at least SeenArea
% pixels' worth of it, not a stray edge. A pixel keeps its shape's own
% colour however little of it is covered, so the colour is matched exactly
% and weighted by coverage.
K = mabr.ui.Icon.Palette;
wears = {'export','Orange'; 'figure','Orange'; 'retrack','Orange'; ...
         'accept','Green'; 'batch','Green'; 'threshold','Green'; 'restore','Green'; ...
         'reject','Red'; 'exclude','Red'; 'noresponse','Red'};
SeenArea = 6;
for k = 1:size(wears,1)
    [rgb,alpha] = mabr.ui.Icon.render(wears{k,1});
    hit = all(abs(rgb - reshape(K.(wears{k,2}),1,1,3)) < 1e-6,3);
    area = sum(alpha(hit));
    assert(area >= SeenArea, ...
        '%s must wear %s for its meaning, but has %.1f pixels of it (fewer than %d)', ...
        wears{k,1},wears{k,2},area,SeenArea);
end
fprintf(['  PASS Part A: %d glyphs render, each its own picture; redo mirrors undo, ' ...
         'and %d analysis glyphs wear their colour\n'],numel(names),size(wears,1));

% ---- Part B: toolbar CData ------------------------------------------------
bgs = {mabr.ui.Icon.Background,[1 1 1],[0.2 0.2 0.22]};
for k = 1:numel(names)
    [rgb,alpha] = mabr.ui.Icon.render(names{k});
    clear_ = alpha < mabr.ui.Icon.MinAlpha;
    solid  = alpha == 1;
    for b = 1:numel(bgs)
        c = mabr.ui.Icon.toolbar(names{k},bgs{b});
        assert(isequal(size(c),[N N 3]),'%s: CData must be 16x16x3',names{k});
        nanMask = isnan(c);
        assert(isequal(nanMask(:,:,1),nanMask(:,:,2),nanMask(:,:,3)), ...
            '%s: a transparent pixel must be NaN in all three planes',names{k});
        assert(isequal(nanMask(:,:,1),clear_), ...
            '%s: transparent exactly where coverage is below MinAlpha',names{k});
        v = c(~nanMask);
        assert(all(v >= 0 & v <= 1),'%s: CData outside [0,1]',names{k});
        assert(isequaln(c,mabr.ui.Icon.toolbar(names{k},bgs{b})), ...
            '%s: a repeat call must return the same CData',names{k});
        s3 = repmat(solid,[1 1 3]);
        assert(max(abs(c(s3) - rgb(s3))) < 1e-12, ...
            '%s: a fully covered pixel must be the glyph''s own colour',names{k});
    end
end
c1 = mabr.ui.Icon.toolbar('help',[1 1 1]);
c2 = mabr.ui.Icon.toolbar('help',[0.2 0.2 0.22]);
[~,alpha] = mabr.ui.Icon.render('help');
edge = alpha >= mabr.ui.Icon.MinAlpha & alpha < 1;
assert(any(edge(:)),'the help disc must have anti-aliased edge pixels');
e3 = repmat(edge,[1 1 3]);
assert(any(abs(c1(e3) - c2(e3)) > 0.05), ...
    'an edge pixel must be blended against the background it sits on');
fprintf('  PASS Part B: CData is 16x16x3, NaN-transparent, blended only at the edges\n');

% ---- Part C: refusals and the toolbar colour -----------------------------
try
    mabr.ui.Icon.render('no-such-glyph');
    error('verify:icons','an unknown glyph must be refused');
catch me
    assert(strcmp(me.identifier,'mabr:ui:Icon:unknown'), ...
        'unknown glyph refused with "%s", expected mabr:ui:Icon:unknown',me.identifier);
end
assert(isequal(mabr.ui.Icon.background([]),mabr.ui.Icon.Background), ...
    'background of nothing must be the default toolbar grey');
assert(isequal(mabr.ui.Icon.background(struct('BackgroundColor',[2 0 0])), ...
    mabr.ui.Icon.Background),'a struct is not a toolbar: default expected');
f = figure('Visible','off');
cleanF = onCleanup(@() delete(f));
tb = uitoolbar(f);
bg = mabr.ui.Icon.background(tb);
assert(isequal(size(bg),[1 3]) && all(bg >= 0 & bg <= 1), ...
    'background of a classic toolbar must be an RGB triple');
c = mabr.ui.Icon.toolbar('live',tb);
assert(isequal(size(c),[N N 3]),'toolbar() must accept the toolbar itself');
clear cleanF
fprintf('  PASS Part C: unknown glyph refused, toolbar colour read or defaulted\n');

% ---- Part D: the names the toolbars and buttons ask for -------------------
% The scanner is checked first: a pattern that stopped matching a form the
% callers use would make every glyph look unrequested or, worse, let a
% misspelling through, and nothing else here would say which.
nScan = checkScanner();
root = fileparts(fileparts(mfilename('fullpath')));
uiDir = fullfile(root,'+mabr','+ui');
files = fullfile(uiDir,{'App.m','TraceOrganizer.m','Notes.m','PresentationOrder.m'});
% The offline analysis window and every view and dialog of it, found with
% dir so that one added later is scanned without touching this list. One
% not written yet is skipped rather than failed: only the four above must
% exist.
d = dir(fullfile(uiDir,'+analysis','*.m'));
analysisFiles = [{fullfile(uiDir,'AnalysisApp.m')}, fullfile({d.folder},{d.name})];
analysisFiles = analysisFiles(cellfun(@isfile,analysisFiles));
files = [files analysisFiles];
used = {};
from = {};
for i = 1:numel(files)
    g = glyphRequests(fileread(files{i}));
    [~,fn,ext] = fileparts(files{i});
    used = [used, g]; %#ok<AGROW>
    from = [from, repmat({[fn ext]},1,numel(g))]; %#ok<AGROW>
end
missing = setdiff(used,names);
where = cellfun(@(g) sprintf('%s (in %s)',g,strjoin(unique(from(strcmp(used,g))),', ')), ...
    missing,'UniformOutput',false);
assert(isempty(missing),'toolbars and buttons ask for glyphs Icon does not draw: %s', ...
    strjoin(where,'; '));
used = unique(used);
orphan = setdiff(names,used);
fprintf(['  PASS Part D: the %d glyphs the toolbars and buttons name are all drawn ' ...
         '(%d files scanned, %d of them the offline analysis window''s; the scanner ' ...
         'read %d forms right first)\n'], ...
    numel(used),numel(files),numel(analysisFiles),nScan);
if ~isempty(orphan)
    fprintf('  .... Part D: %d glyph(s) nothing asks for yet, judged after Part F: %s\n', ...
        numel(orphan),strjoin(orphan,', '));
end

% ---- Part E: a toolbar built from them -----------------------------------
to = mabr.ui.TraceOrganizer();
cleanTo = onCleanup(@() delete(to));
to.show();
tbar = findall(to.Figure,'Type','uitoolbar');
assert(isscalar(tbar),'the trace organizer must have one toolbar');
tools = allchild(tbar);
assert(numel(tools) >= 11,'expected at least 11 organizer tools, found %d',numel(tools));
for i = 1:numel(tools)
    assert(isequal(size(tools(i).CData),[N N 3]), ...
        'organizer tool "%s" has no 16x16x3 icon',tools(i).Tooltip);
    assert(~isempty(tools(i).Tooltip),'every organizer tool needs a tooltip');
end
clear cleanTo
fprintf('  PASS Part E: the trace organizer''s %d tools all carry an icon\n',numel(tools));

% ---- Part F: the same art as a button's PNG ------------------------------
% A uibutton takes a file, and sits on a background that changes (disabled,
% pressed, Loop on), so file() must keep real transparency rather than blend.
% Every glyph is checked: any of them can go on a button, and the offline
% analysis window puts most of its own there (Style.setButtonIcon).
runGlyphs   = {'play','preview','repeat','loop','pause','advance','abort'};
% The presentation-order window's buttons (Stay on top wears the toolbar's pin).
orderGlyphs = {'skipnext','offabove','offbelow','enableall','pin'};
for k = 1:numel(names)
    g = names{k};
    f = mabr.ui.Icon.file(g);
    assert(ischar(f) && isfile(f),'%s: file() must name a PNG that exists',g);
    assert(strcmp(f,mabr.ui.Icon.file(g)), ...
        '%s: a repeat call must return the same file',g);
    [img,~,a] = imread(f);
    [rgb,alpha] = mabr.ui.Icon.render(g);
    assert(isequal(size(img),[N N 3]) && isequal(size(a),[N N]), ...
        '%s: the PNG must be 16x16 colour with a 16x16 alpha channel',g);
    assert(max(abs(double(a(:))/255 - alpha(:))) <= 1/255 + eps, ...
        '%s: the PNG must carry the glyph''s own coverage as alpha',g);
    solid = alpha == 1;
    s3 = repmat(solid,[1 1 3]);
    assert(max(abs(double(img(s3))/255 - rgb(s3))) <= 1/255 + eps, ...
        '%s: a fully covered pixel must be the glyph''s own colour',g);
    assert(any(a(:) == 0) && any(a(:) == 255), ...
        '%s: the PNG must be both transparent and opaque somewhere',g);
end
try
    mabr.ui.Icon.file('no-such-glyph');
    error('verify:icons','an unknown glyph must be refused by file() too');
catch me
    assert(strcmp(me.identifier,'mabr:ui:Icon:unknown'), ...
        'file() refused an unknown glyph with "%s", expected mabr:ui:Icon:unknown', ...
        me.identifier);
end
% Names of the Run panel's buttons are all ones the buttons use.
appSrc = fileread(fullfile(root,'+mabr','+ui','App.m'));
for k = 1:numel(runGlyphs)
    assert(~isempty(regexp(appSrc,['setButtonIcon\(\s*[A-Za-z_.]+\s*,\s*''' runGlyphs{k} ''''],'once')), ...
        'no Run panel button asks for "%s"',runGlyphs{k});
end
% ...and the presentation-order window's. Stay on top's pin is shared with the
% main toolbar, so it is the window's own source that must ask for it.
orderSrc = fileread(fullfile(root,'+mabr','+ui','PresentationOrder.m'));
for k = 1:numel(orderGlyphs)
    assert(~isempty(regexp(orderSrc,['setButtonIcon\(\s*[A-Za-z_.]+\s*,\s*''' orderGlyphs{k} ''''],'once')), ...
        'no presentation-order button asks for "%s"',orderGlyphs{k});
end
fprintf(['  PASS Part F: all %d glyphs are PNGs with their own alpha, and the %d ' ...
         'run-control and %d presentation-order glyphs are each on a button\n'], ...
    numel(names),numel(runGlyphs),numel(orderGlyphs));

% ---- Part D, second half: nothing drawn that nobody asks for ---------------
rel = strrep(files,[root filesep],'');
assert(isempty(orphan), ['Icon draws %d glyph(s) that no toolbar or button asks for: ' ...
    '%s. Each must be requested -- toolButton/Icon.toolbar/Icon.file(''glyph''), ' ...
    'setButtonIcon/viewIcon(button,''glyph'') or an action''s Glyph field -- in one ' ...
    'of the %d files scanned (%s); a glyph nothing asks for is a misspelt caller or ' ...
    'dead art.'], ...
    numel(orphan),strjoin(orphan,', '),numel(rel),strjoin(rel,', '));
fprintf('  PASS Part D: every one of the %d glyphs is asked for by a toolbar or button\n', ...
    numel(names));

fprintf('== verify_icons: PASS ==\n');
end

% ===========================================================================
function g = glyphRequests(src)
% The glyph names the MATLAB source SRC asks mabr.ui.Icon for, one per
% request, in the forms Part D accepts:
%   toolButton('glyph',...), Icon.toolbar('glyph',...), Icon.file('glyph')
%   setButtonIcon(button,'glyph',...), viewIcon(button,'glyph')
%   an action's Glyph field: 'Glyph','glyph' / a.Glyph = 'glyph' / Glyph="glyph"
% in either kind of quote. The button may be any name, field or indexed
% element (b2, obj.Ctrl.onTop, obj.Buttons(k)), and a call may run over
% lines with "...", as a long one usually does here -- either missed would
% leave a request unread, and its glyph would look unasked for or, if it is
% misspelt, slip through. For the same reason a call's literal is read
% whatever it holds ('no-response' comes back, to be reported as no glyph):
% those calls take nothing but a glyph. Only a Glyph field is held to
% letters, since a field of that name may carry a status mark (a filled
% circle, char(9679)) rather than an Icon name. Comments are dropped first, block and whole-line: an
% example in a help block, or a request commented out, is not a button.
src = regexprep(src,'^[ \t]*%\{[ \t]*\r?$.*?^[ \t]*%\}[ \t]*\r?$','','lineanchors');
src = regexprep(src,'^[ \t]*%[^\n]*','','lineanchors');
ws   = '(?:\s|\.\.\.[^\n]*\n)*';                     % blanks, or a continuation
any_ = '["'']([^"''\r\n]+)["'']';                     % any quoted text
word = '["'']([A-Za-z]+)["'']';                       % letters only
arg  = '[A-Za-z_][\w.]*(?:\([^()]*\)|\{[^{}]*\})?';   % the button
pats = {['(?:toolButton|Icon\.toolbar|Icon\.file)\(' ws any_], ...
        ['(?:setButtonIcon|viewIcon)\(' ws arg ws ',' ws any_], ...
        ['(?<!\w)Glyph["'']?' ws '[,=]' ws word]};
g = {};
for p = 1:numel(pats)
    t = regexp(src,pats{p},'tokens');
    g = [g, cellfun(@(x) x{1},t,'UniformOutput',false)]; %#ok<AGROW>
end
end

function n = checkScanner()
% glyphRequests on source written to exercise it: every form a caller may
% use is read, and nothing that only looks like one. Returns how many
% snippets it judged.
nl = newline;
crlf = [char(13) newline];
pos = { ...
    'app.toolButton(''load'',''Open data folder... (Ctrl+O)'',@(s,e) app.openRoot(""));', {'load'}
    'uipushtool(tb,''CData'',mabr.ui.Icon.toolbar(''gear'',tb))',                          {'gear'}
    'b.Icon = mabr.ui.Icon.file("copy");',                                                 {'copy'}
    'mabr.ui.analysis.Style.setButtonIcon(obj.AcceptButton,''accept'',''left'');',         {'accept'}
    'mabr.ui.analysis.Style.setButtonIcon(h.btn2,"retrack","left")',                       {'retrack'}
    'obj.setButtonIcon(obj.Ctrl.onTop,''pin'');',                                          {'pin'}
    'mabr.ui.analysis.View.viewIcon(obj.Buttons(k), ''restore'')',                         {'restore'}
    ['mabr.ui.analysis.Style.setButtonIcon(obj.PoolButton, ... the long form' nl ...
     '        ''pool'',''left'');'],                                                       {'pool'}
    ['mabr.ui.analysis.Style.setButtonIcon( ...' crlf '    obj.NoResponseButton, ...' ...
     crlf '    ''noresponse'');'],                                                         {'noresponse'}
    'actions = struct(''Text'',"Load raw data",''Fcn'',@() obj.load(),''Glyph'',''load'');', {'load'}
    'a.Glyph = "raster";',                                                                 {'raster'}
    'obj.addAction(Text="Analyse",Glyph="batch")',                                         {'batch'}
    'mabr.ui.analysis.Style.setButtonIcon(b,''no-response'',''left'');',                   {'no-response'}
    ['% help: setButtonIcon(b,''accept'')' crlf 'x = 1;' crlf '  % toolButton(''undo'')' ...
     crlf 'obj.viewIcon(b,''redo''); app.toolButton(''save'',''Save'',@() 1);' crlf],      {'redo','save'}
    };
neg = { ...
    '%       mabr.ui.analysis.Style.setButtonIcon(btn,''accept'',''left'')'
    ['x = 1;' nl '%{' nl 'obj.toolButton(''undo'',''Undo'',@() 1);' nl '%}' nl 'y = 2;']
    ['x = 1;' crlf '  %{' crlf 'Style.setButtonIcon(b,''redo'');' crlf '  %}' crlf]
    'function ok = setButtonIcon(btn,glyph,align)'
    'ok = mabr.ui.analysis.Style.setButtonIcon(btn,glyph,''left'');'
    'f = mabr.ui.Icon.file(char(glyph));'
    'mabr.ui.analysis.View.viewIcon(b,string(a.Glyph));'
    'if isfield(a,''Glyph'') && strlength(string(a.Glyph)) > 0, end'
    ['GlyphNoResponse  = "' char(8709) '"']
    ['s.Glyph = "' char(9679) '";']
    'a.Glyph = "";'
    'if a.Glyph == "load", end'
    'uialert(fig,msg,''Title'',''Icon'',''warning'')'
    };
for i = 1:size(pos,1)
    g = glyphRequests(pos{i,1});
    assert(isequal(sort(g),sort(pos{i,2})), ...
        'Part D scanner: expected {%s} from "%s", read {%s}', ...
        strjoin(pos{i,2},','),pos{i,1},strjoin(g,','));
end
for i = 1:numel(neg)
    g = glyphRequests(neg{i});
    assert(isempty(g),'Part D scanner: "%s" asks for no glyph, yet {%s} was read', ...
        neg{i},strjoin(g,','));
end
n = size(pos,1) + numel(neg);
end
