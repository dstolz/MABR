function verify_icons()
% verify_icons  Confirm the toolbar pictograms (mabr.ui.Icon) render, and
%               that every toolbar names a glyph that exists.
%
%   Part A: every glyph renders to 16x16 colour in [0,1] and coverage in
%   [0,1], with something drawn and something left clear, and no two glyphs
%   are the same picture.
%   Part B: toolbar() CData is what a uipushtool takes -- 16x16x3, finite
%   in [0,1] where drawn, NaN in all three planes together where not, and
%   transparent exactly where coverage is below MinAlpha; a fully covered
%   pixel is the glyph's own colour whatever the background, and only the
%   blended edge depends on it; a repeat call returns the cached array.
%   Part C: an unknown name is refused, and background() reads a toolbar's
%   colour where it has one and falls back where it does not.
%   Part D: every glyph name the toolbars ask for (mabr.ui.App,
%   mabr.ui.TraceOrganizer, mabr.ui.Notes) is one render() knows, and every
%   glyph is asked for by some toolbar -- a misspelt name would otherwise
%   surface only when that window was opened.
%   Part E: a trace organizer's toolbar is built from them: every tool
%   carries 16x16x3 CData and a tooltip.
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
fprintf('  PASS Part A: %d glyphs render, each its own picture\n',numel(names));

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

% ---- Part D: the names the toolbars ask for ------------------------------
root = fileparts(fileparts(mfilename('fullpath')));
files = {fullfile(root,'+mabr','+ui','App.m'), ...
         fullfile(root,'+mabr','+ui','TraceOrganizer.m'), ...
         fullfile(root,'+mabr','+ui','Notes.m')};
used = {};
for i = 1:numel(files)
    src = fileread(files{i});
    t = regexp(src,'(?:toolButton|Icon\.toolbar)\(\s*''([A-Za-z]+)''','tokens');
    used = [used, cellfun(@(x) x{1},t,'UniformOutput',false)]; %#ok<AGROW>
end
used = unique(used);
missing = setdiff(used,names);
assert(isempty(missing),'toolbars ask for glyphs Icon does not draw: %s', ...
    strjoin(missing,', '));
orphan = setdiff(names,used);
assert(isempty(orphan),'Icon draws glyphs no toolbar uses: %s',strjoin(orphan,', '));
fprintf('  PASS Part D: the %d glyphs the toolbars name are the %d Icon draws\n', ...
    numel(used),numel(names));

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

fprintf('== verify_icons: PASS ==\n');
end
