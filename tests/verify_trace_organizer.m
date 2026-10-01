function verify_trace_organizer()
% verify_trace_organizer  Exercise the TraceOrganizer usability features.
%
%   Builds synthetic blocks, then checks, with no audio hardware:
%       1. each trace is labelled with its stimulus ID;
%       2. amplitude commands scale the selection, or everything when the
%          selection is empty, and reset to 1x;
%       3. spacing changes restack the traces at the new pitch;
%       4. selection, reordering, hiding and removal behave;
%       5. markers are stored as sample indices and survive rescaling;
%       6. saveView -> loadView reproduces every trace and view setting
%          exactly, and a version-1 file still loads;
%       7. keyboard and menu wiring;
%       8. listenTo auto-adds a trace for each block an AcqController
%          finalizes, without duplicating listeners;
%       9. a trace added that way is drawn on its own, and the view is
%          exactly what a full redraw would leave;
%      10. organizing by stimulus parameter: each trace carries its block's
%          parameters exactly; SplitBy gives one panel per value, sharing
%          one time axis and one stack height, none overlapping; OrderBy
%          sorts every stack, top to bottom, either way; LabelBy 'params'
%          names traces by what varies; lifting the split restacks one
%          even stack; a hand-made move makes the order manual and never
%          crosses a panel; a name no trace carries does nothing and says
%          so; a bad direction is refused; the Organize menu and 'g' work;
%      11. organized, a trace added mid-run is drawn incrementally (moving
%          only what it pushed down its panel) and the view is exactly what
%          a full redraw leaves -- new panels and relabelled traces included;
%      12. save/load restores the organization and each trace's Params; a
%          version-4 file loads as one stack, its parameters read back off
%          the labels for organizing but never saved back as Params.
%      13. overlap: selected traces share one slot (the rest close up around
%          it), survive restacking and a save/load, step with stepOverlap,
%          and separateTraces gives each its own line again.
%
%   Creates (invisible-capable) figures but needs no hardware. Run:
%       >> verify_trace_organizer
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_trace_organizer ==\n');

outDir = fullfile(tempdir,'mabr_traceorg');
if ~isfolder(outDir), mkdir(outDir); end
viewFile = fullfile(outDir,'view.torg');
oldFile  = fullfile(outDir,'legacy.torg');

to = mabr.ui.TraceOrganizer();
cleanTo = onCleanup(@() delete(to));

% --- 1. stimulus ID labelling -------------------------------------------
ids = {'8kHz_60dB','16kHz_60dB','32kHz_60dB'};
for i = 1:numel(ids)
    to.addBlock(make_block(ids{i},i));
end
to.show();
assert(numel(to.Traces) == 3,'expected 3 traces, got %d',numel(to.Traces));
for i = 1:numel(ids)
    assert(strcmp(to.Traces(i).StimID,ids{i}), ...
        'trace %d StimID is "%s", expected "%s"',i,to.Traces(i).StimID,ids{i});
    assert(strcmp(to.Traces(i).LabelHandle.String,ids{i}), ...
        'trace %d on-plot label does not show the stimulus ID',i);
end
fprintf('  PASS: %d traces labelled with their stimulus IDs\n',numel(ids));

% --- 2. amplitude --------------------------------------------------------
to.select(2);
assert(isequal(to.selectedIndices(),2),'select(2) did not select trace 2');
to.scaleTraces(2);
assert(to.Traces(2).Gain == 2 && to.Traces(1).Gain == 1, ...
    'scaling the selection leaked onto unselected traces');

% the gain must actually reach the plotted data
sel = to.Traces(2);
assert(max(abs(sel.LineHandle.YData - sel.YOffset)) > 0, 'trace 2 not drawn');
before = max(abs(sel.LineHandle.YData - sel.YOffset));
to.scaleTraces(2,2);
after = max(abs(to.Traces(2).LineHandle.YData - to.Traces(2).YOffset));
assert(abs(after/before - 2) < 1e-9,'plotted amplitude did not follow Gain (%g)',after/before);

% label advertises the non-unit gain
assert(contains(to.Traces(2).LabelHandle.String,'x4'), ...
    'label does not report the gain: "%s"',to.Traces(2).LabelHandle.String);

to.select([]);                      % empty selection => act on all
assert(isempty(to.selectedIndices()),'select([]) did not clear the selection');
g0 = [to.Traces.Gain];
to.scaleTraces(2);
assert(isequal([to.Traces.Gain],g0*2),'unselected scaling did not act on all traces');
to.resetGain();
assert(all([to.Traces.Gain] == 1),'resetGain did not restore 1x');
fprintf('  PASS: amplitude scales selection / all, reaches the plot, resets\n');

% --- 3. spacing ----------------------------------------------------------
to.setSpacing(2.5);
assert(to.YSpacing == 2.5,'YSpacing not set');
offs = [to.Traces.YOffset];
assert(max(abs(diff(offs) + 2.5)) < 1e-9, ...
    'traces not restacked at the new spacing: %s',mat2str(offs));
to.Traces(1).YOffset = -99;         % drag trace 1 to the bottom
to.restack();
assert(strcmp(to.Traces(end).StimID,ids{1}), ...
    'restack did not reorder by visual position');
assert(max(abs(diff([to.Traces.YOffset]) + 2.5)) < 1e-9,'restack pitch wrong');
fprintf('  PASS: spacing control + restack in visual order\n');

% --- 4. selection, order, visibility, removal ----------------------------
to.select(1); to.select(3,true);
assert(isequal(to.selectedIndices(),[1 3]),'shift-extend selection failed');
order0 = {to.Traces.StimID};
to.select(3);
to.moveTrace(3,-1);
assert(strcmp(to.Traces(2).StimID,order0{3}),'moveTrace did not swap upward');
to.select(1);
to.toggleVisible(1);
assert(~to.Traces(1).Visible && strcmp(to.Traces(1).LineHandle.Visible,'off'), ...
    'hiding a trace did not hide its line');
to.toggleVisible(1);
assert(to.Traces(1).Visible,'unhiding failed');
to.removeTraces(2);
assert(numel(to.Traces) == 2,'removeTraces did not remove one trace');
fprintf('  PASS: multi-select, reorder, hide/show, remove\n');

% --- 5. markers follow rescaling ----------------------------------------
to.select(1);
to.markPeaks(1);
tr = to.Traces(1);
assert(~isempty(tr.MarkerLocs),'markPeaks produced no markers');
assert(all(tr.MarkerLocs == round(tr.MarkerLocs)) && ...
       all(tr.MarkerLocs >= 1 & tr.MarkerLocs <= numel(tr.Data)), ...
       'markers are not valid sample indices');
locs0 = tr.MarkerLocs;
yBefore = tr.Markers(1).Y;
to.scaleTraces(3,1);
assert(isequal(to.Traces(1).MarkerLocs,locs0),'rescaling disturbed marker indices');
yAfter = to.Traces(1).Markers(1).Y;
assert(abs(yAfter - to.Traces(1).YOffset) > abs(yBefore - to.Traces(1).YOffset)*2.5, ...
    'marker did not follow the rescaled trace');
to.resetGain(1);
fprintf('  PASS: markers are index-based and track rescaling\n');

% --- 6. save / load exactness -------------------------------------------
to.select(2);
to.Traces(2).Gain = 1.7;
to.Traces(1).Color = [0.9 0.2 0.4];
to.NormalizeEach = true;
to.ShowLabels = false;
to.refresh();
to.saveView(viewFile);
assert(isfile(viewFile),'saveView wrote no file');

want = cell(1,numel(to.Traces));
for k = 1:numel(to.Traces), want{k} = to.Traces(k).toStruct(); end
wantX = [to.Axes.XLim to.Axes.YLim];

to2 = mabr.ui.TraceOrganizer();
cleanTo2 = onCleanup(@() delete(to2));
to2.loadView(viewFile);

assert(numel(to2.Traces) == numel(want),'loadView restored %d of %d traces', ...
    numel(to2.Traces),numel(want));
assert(to2.YSpacing == to.YSpacing && to2.YScaling == to.YScaling && ...
       to2.NormalizeEach == to.NormalizeEach && to2.ShowLabels == to.ShowLabels, ...
       'loadView did not restore the view settings');
for k = 1:numel(want)
    got = to2.Traces(k).toStruct();
    f = fieldnames(want{k});
    for i = 1:numel(f)
        assert(isequal(got.(f{i}),want{k}.(f{i})), ...
            'trace %d field %s differs after save/load',k,f{i});
    end
end
assert(isequal([to2.Axes.XLim to2.Axes.YLim],wantX), ...
    'loadView did not restore the axis limits');
fprintf('  PASS: save/load restores %d traces and the view exactly\n',numel(want));

% version-1 file (waveform + label + colour + offset only) still loads
w = sin(2*pi*(0:99)'/25);      % a waveform with peaks, so section 7 can mark them
S = struct('Data',{w,w},'Time',{(1:100)'/1000,(1:100)'/1000}, ...
           'Label',{'a','b'},'Color',{[1 0 0],[0 1 0]},'YOffset',{0,-1});
save(oldFile,'S','-mat');
to2.loadView(oldFile);
assert(numel(to2.Traces) == 2 && strcmp(to2.Traces(2).Label,'b'), ...
    'version-1 .torg file did not load');
fprintf('  PASS: version-1 .torg files still load\n');

% --- 7. keyboard + menu wiring ------------------------------------------
key = @(k,varargin) to2.Figure.WindowKeyPressFcn([], ...
    struct('Key',k,'Modifier',{varargin}));

to2.select([]);
g = [to2.Traces.Gain];
key('uparrow');
assert(all([to2.Traces.Gain] > g),'Up arrow did not enlarge the traces');
key('downarrow');
assert(max(abs([to2.Traces.Gain] - g)) < 1e-9,'Down arrow did not undo Up');

sp = to2.YSpacing;
key('uparrow','shift');
assert(to2.YSpacing > sp,'Shift+Up did not widen the spacing');
key('downarrow','shift');
assert(abs(to2.YSpacing - sp) < 1e-9,'Shift+Down did not undo Shift+Up');

key('a');
assert(numel(to2.selectedIndices()) == numel(to2.Traces),'"a" did not select all');
key('escape');
assert(isempty(to2.selectedIndices()),'Escape did not clear the selection');

lbl = to2.ShowLabels; key('l');
assert(to2.ShowLabels ~= lbl,'"l" did not toggle the labels');
nrm = to2.NormalizeEach; key('n');
assert(to2.NormalizeEach ~= nrm,'"n" did not toggle normalization');

key('p');
assert(~isempty(to2.Traces(1).MarkerLocs),'"p" did not mark peaks');
key('c');
assert(isempty(to2.Traces(1).MarkerLocs),'"c" did not clear the markers');

key('0'); key('r');   % must not error

tops = findobj(to2.Figure,'Type','uimenu','Parent',to2.Figure);
names = {'Amplitude','Spacing','Traces','Organize','Band','Peaks','File'};
assert(all(ismember(names,{tops.Label})), ...
    'menu bar is missing entries: %s',strjoin(setdiff(names,{tops.Label}),', '));
for k = 1:numel(tops)
    assert(~isempty(findobj(tops(k),'Type','uimenu','-not','Parent',to2.Figure)), ...
        'menu "%s" has no items',tops(k).Label);
end
assert(~isempty(to2.Traces(1).LineHandle.ContextMenu), ...
    'traces have no right-click menu');
fprintf('  PASS: keyboard shortcuts and menu/context-menu wiring\n');

% --- 8. live block updates ----------------------------------------------
% The organizer subscribes to an AcqController's BlockReady event, so a view
% left open during a run gains a trace as each block is finalized.
src = mabrtest.BlockNotifier();
to3 = mabr.ui.TraceOrganizer();
cleanTo3 = onCleanup(@() delete(to3)); %#ok<NASGU>
to3.show();
to3.listenTo(src);

src.emit(make_block('4kHz_70dB',1));
assert(numel(to3.Traces) == 1,'BlockReady did not add a trace');
assert(strcmp(to3.Traces(1).StimID,'4kHz_70dB'), ...
    'auto-added trace lost its stimulus ID');
assert(~isempty(to3.Traces(1).LineHandle) && isgraphics(to3.Traces(1).LineHandle), ...
    'auto-added trace was not drawn into the open view');

src.emit(make_block('4kHz_60dB',2));
assert(numel(to3.Traces) == 2,'second BlockReady did not add a trace');
assert(abs(diff([to3.Traces.YOffset]) + to3.YSpacing) < 1e-9, ...
    'auto-added traces are not stacked at the current spacing');

% Re-pointing must not stack a second listener (re-opening the organizer).
to3.listenTo(src);
src.emit(make_block('8kHz_60dB',3));
assert(numel(to3.Traces) == 3,'re-listening duplicated the trace (%d added)', ...
    numel(to3.Traces)-2);

% ...and detaching stops the updates.
to3.stopListening();
src.emit(make_block('16kHz_60dB',4));
assert(numel(to3.Traces) == 3,'stopListening did not detach the organizer');
fprintf('  PASS: blocks auto-added on BlockReady, no duplicate listeners\n');

% --- 9. an added trace is drawn on its own, exactly as a redraw would ------
% A trace added mid-session (one per finalized block) is drawn without
% redrawing the rest -- unless it moves the shared amplitude scale, which
% moves every trace. Either way the screen must be what a full redraw from
% scratch (show) leaves, pixel data and margins included.
to4 = mabr.ui.TraceOrganizer();
cleanTo4 = onCleanup(@() delete(to4)); %#ok<NASGU>
to4.show();
t = (0:119)'/12000;
w = sin(2*pi*1000*t)*1e-6;
to4.addTrace(w,t,'A');
to4.addTrace(0.5*w,t,'B, whose label is the longest by far');   % smaller: incremental
to4.addTrace(0.7*w,t,'C');                                      % incremental
drawn = view_state(to4);
to4.show();
assert(isequaln(drawn,view_state(to4)), ...
    'traces added one at a time differ from a full redraw of the same traces');
to4.addTrace(3*w,t,'D');                  % bigger: rescales all, so all redrawn
drawn = view_state(to4);
to4.show();
assert(isequaln(drawn,view_state(to4)), ...
    'a trace that moved the shared scale left the others drawn at the old one');
fprintf('  PASS: an added trace is drawn alone, identically to a full redraw\n');

% --- 10. organizing by stimulus parameter ---------------------------------
% A Frequency x Level grid arriving in a scrambled order, as an intermixed
% run's blocks do.
F = [16  8 32  8 16 32  8 16];
L = [60 90 60 30 90 30 60 30];
to5 = mabr.ui.TraceOrganizer();
cleanTo5 = onCleanup(@() delete(to5)); %#ok<NASGU>
to5.show();
for i = 1:numel(F)
    to5.addBlock(make_grid_block(F(i),L(i)));
end
assert(numel(to5.Traces) == numel(F),'grid traces were not all added');
for k = 1:numel(to5.Traces)
    p = to5.Traces(k).Params;
    assert(isequal(sort(fieldnames(p)),{'Frequency';'Level'}) && ...
        p.Frequency == F(k) && p.Level == L(k), ...
        'trace %d does not carry exactly the parameters its block declares',k);
end
assert(~to5.isOrganized() && numel(to5.PanelAxes) == 1, ...
    'a new organizer is not one unorganized stack');
fprintf('  PASS: each trace carries its block''s stimulus parameters\n');

% Split by frequency: one panel per value, ascending, in arrival order.
s = to5.YSpacing;
to5.SplitBy = 'Frequency';
pax = to5.PanelAxes;
assert(numel(pax) == 3,'SplitBy Frequency gave %d panels, expected 3',numel(pax));
ttl = arrayfun(@(a) a.Title.String,pax,'UniformOutput',false);
assert(isequal(ttl,{'8 kHz','16 kHz','32 kHz'}),'panel titles: %s',strjoin(ttl,' | '));
assert(pax(1) == to5.Axes,'Axes is not the first panel');
for k = 1:numel(to5.Traces)
    tr = to5.Traces(k);
    assert(tr.LineHandle.Parent == pax([8 16 32] == tr.Params.Frequency), ...
        '"%s" is drawn in the wrong panel',tr.DisplayName);
end
assert(isequal(pax(1).XLim,pax(2).XLim,pax(3).XLim) && ...
       isequal(pax(1).YLim,pax(2).YLim,pax(3).YLim), ...
    'the panels do not share one time axis and one stack height');
assert(no_overlap(pax),'the split panels overlap');
for f = [8 16 32]
    y = sort([to5.Traces(param_of(to5,'Frequency') == f).YOffset],'descend');
    assert(isequal(y,-(0:numel(y)-1)*s),'the %g kHz panel is not stacked evenly',f);
end
assert(isequal(levels_top_down(to5,8),[90 30 60]), ...
    'with no order, a panel did not keep the arrival order');
assert(contains(to5.statusText(),'split by Frequency (3)'), ...
    'the status line does not report the split: "%s"',to5.statusText());

% Order each stack by level, both ways; the traces are held panel by panel.
to5.setOrder('Level','descending');
for f = [8 16 32]
    assert(isequal(levels_top_down(to5,f),sort(L(F == f),'descend')), ...
        'the %g kHz panel is not ordered by level, descending',f);
end
assert(issorted(param_of(to5,'Frequency')),'traces are not held panel by panel');
assert(contains(to5.statusText(),'ordered by Level descending'), ...
    'the status line does not report the order: "%s"',to5.statusText());
to5.OrderDirection = 'ascending';
for f = [8 16 32]
    assert(isequal(levels_top_down(to5,f),sort(L(F == f),'ascend')), ...
        'the %g kHz panel is not ordered by level, ascending',f);
end

% Panels follow the split parameter's own direction when it is an order key.
to5.setOrder({'Frequency','Level'},{'descending','descending'});
ttl = arrayfun(@(a) a.Title.String,to5.PanelAxes,'UniformOutput',false);
assert(isequal(ttl,{'32 kHz','16 kHz','8 kHz'}), ...
    'panels did not follow a descending split parameter: %s',strjoin(ttl,' | '));
fprintf('  PASS: SplitBy gives a panel per value; OrderBy sorts every stack\n');

% Labels by parameter: the split parameter is the panel's title, not the label's.
to5.setOrder('Level','descending');
to5.LabelBy = 'params';
for k = 1:numel(to5.Traces)
    tr = to5.Traces(k);
    assert(strcmp(tr.LabelHandle.String,sprintf('%g dB',tr.Params.Level)), ...
        'split label reads "%s"',tr.LabelHandle.String);
end
% Lifting the split restacks one even stack, still in the order in force.
to5.SplitBy = '';
assert(numel(to5.PanelAxes) == 1 && isempty(to5.PanelAxes(1).Title.String), ...
    'lifting the split did not return to one untitled stack');
assert(isequal([to5.Traces.YOffset],-(0:numel(F)-1)*s), ...
    'lifting the split did not restack evenly');
assert(issorted(-param_of(to5,'Level')),'the order was lost with the split');
for k = 1:numel(to5.Traces)
    tr = to5.Traces(k);
    want = sprintf('%g kHz, %g dB',tr.Params.Frequency,tr.Params.Level);
    assert(strcmp(tr.LabelHandle.String,want), ...
        'label reads "%s", expected "%s"',tr.LabelHandle.String,want);
end
to5.LabelBy = 'id';
assert(strcmp(to5.Traces(1).LabelHandle.String,to5.Traces(1).StimID), ...
    'LabelBy id did not restore the stimulus ID');
fprintf('  PASS: LabelBy names traces by what varies; lifting a split restacks\n');

% A move by hand makes the order manual, and never crosses a panel.
to5.SplitBy = 'Frequency';
to5.select(1);                       % the 90 dB trace, top of the 8 kHz panel
to5.moveTrace(1,+1);
assert(isempty(to5.OrderBy),'a move by hand left the parameter order in force');
assert(contains(to5.statusText(),'manual'), ...
    'the status line did not say the order is now manual: "%s"',to5.statusText());
assert(isequal(levels_top_down(to5,8),[60 90 30]),'the move did not land');
last8 = find(param_of(to5,'Frequency') == 8,1,'last');
ids0  = {to5.Traces.StimID};
to5.moveTrace(last8,+1);
assert(isequal({to5.Traces.StimID},ids0),'a trace moved across a panel boundary');
% ...and a trace arriving now goes to the bottom of its panel.
to5.addBlock(make_grid_block(8,10));
assert(isequal(levels_top_down(to5,8),[60 90 30 10]), ...
    'a trace added to a manual order did not go to the bottom of its panel');
fprintf('  PASS: a hand-made move makes the order manual, within its panel\n');

% A name no trace carries does nothing, and says so; a bad direction is refused.
to5.SplitBy = 'Duration';
assert(numel(to5.PanelAxes) == 1 && strcmp(to5.SplitBy,'Duration'), ...
    'a split no trace can take was not kept as a no-op');
assert(contains(to5.statusText(),'no trace carries it'), ...
    'the status line does not say no trace carries the split: "%s"',to5.statusText());
try
    to5.OrderDirection = 'sideways';
    error('verify:accepted','an unknown order direction was accepted');
catch me
    assert(strcmp(me.identifier,'mabr:ui:TraceOrganizer:orderDirection'), ...
        'unexpected error for a bad direction: %s',me.identifier);
end

% The Organize menu (bar and right-click) and the 'g' key.
it = findobj(to5.Figure,'Tag','org_split_level');
assert(numel(it) == 2,'Split by > Level is not on both the menu bar and the context menu');
cb = it(1).Callback;
cb(it(1),[]);
assert(strcmp(to5.SplitBy,'Level') && numel(to5.PanelAxes) == 4, ...
    'the Split by menu did not split by level');
assert(all(arrayfun(@(h) strcmp(char(h.Checked),'on'),findobj(to5.Figure,'Tag','org_split_level'))), ...
    'the split in force is not ticked');
it = findobj(to5.Figure,'Tag','org_order_frequency_descending');
cb = it(1).Callback;
cb(it(1),[]);
assert(isequal(to5.OrderBy,{'Frequency'}) && isequal(to5.OrderDirection,{'descending'}), ...
    'the Order by menu did not set the order');
to5.SplitBy = '';
to5.Figure.WindowKeyPressFcn([],struct('Key','g','Modifier',{{}}));
assert(~isempty(to5.SplitBy),'"g" did not split the view');
fprintf('  PASS: unknown names, bad directions, the Organize menu and "g"\n');

% --- 11. organized incremental adds == full redraw --------------------------
% Quieter traces land at the top of their panel (level ascending) and push
% the rest down; a new frequency adds a panel; with LabelBy 'params' a new
% level relabels everything. Each add, drawn incrementally, must leave
% exactly what a full redraw leaves.
seq = [8 90; 16 90; 8 60; 16 60; 8 30; 32 90; 16 30];
for labelMode = {'id','params'}
    to6 = mabr.ui.TraceOrganizer();
    to6.show();
    to6.SplitBy = 'Frequency';
    to6.setOrder('Level','ascending');
    to6.LabelBy = labelMode{1};
    for i = 1:size(seq,1)
        to6.addBlock(make_grid_block(seq(i,1),seq(i,2)));
        drawn = panel_state(to6,true);
        to6.show();
        assert(isequaln(drawn,panel_state(to6,true)), ...
            'LabelBy %s, add %d: drawn incrementally differs from a full redraw',labelMode{1},i);
    end
    if strcmp(labelMode{1},'id'), delete(to6); end
end
cleanTo6 = onCleanup(@() delete(to6)); %#ok<NASGU>
fprintf('  PASS: organized adds are drawn incrementally, identical to a full redraw\n');

% --- 12. save / load the organization ---------------------------------------
orgFile = fullfile(outDir,'organized.torg');
v4File  = fullfile(outDir,'version4.torg');
to6.saveView(orgFile);
to7 = mabr.ui.TraceOrganizer();
cleanTo7 = onCleanup(@() delete(to7)); %#ok<NASGU>
to7.SplitBy = 'Level';              % its own setting, which the file replaces
to7.loadView(orgFile);
assert(strcmp(to7.SplitBy,'Frequency') && isequal(to7.OrderBy,to6.OrderBy) && ...
       isequal(to7.OrderDirection,to6.OrderDirection) && strcmp(to7.LabelBy,'params'), ...
    'loadView did not restore the organization settings');
assert(numel(to7.Traces) == numel(to6.Traces),'loadView lost traces');
for k = 1:numel(to6.Traces)
    a = to6.Traces(k).toStruct(); b = to7.Traces(k).toStruct();
    f = fieldnames(a);
    for i = 1:numel(f)
        assert(isequal(a.(f{i}),b.(f{i})),'trace %d field %s differs after save/load',k,f{i});
    end
end
assert(isequaln(panel_state(to6,false),panel_state(to7,false)), ...
    'the loaded view is not drawn as the saved one was');

% A version-4 file -- one stack, no settings, no Params -- loads as saved,
% with the parameters read back off the labels for organizing.
to6.SplitBy = '';
to6.setOrder({});
to6.LabelBy = 'id';
to6.saveView(v4File);
S4 = load(v4File,'-mat');
View = S4.View;
View = rmfield(View,{'SplitBy','OrderBy','OrderDirection','LabelBy'});
View.Traces  = rmfield(View.Traces,'Params');
View.Version = 4;
save(v4File,'View','-mat');
to7.loadView(v4File);
assert(isempty(to7.SplitBy) && isempty(to7.OrderBy) && strcmp(to7.LabelBy,'id') && ...
       numel(to7.PanelAxes) == 1,'a version-4 file did not load as one stack');
assert(isequal([to7.Traces.YOffset],[View.Traces.YOffset]), ...
    'a version-4 file''s offsets were not kept as saved');
for k = 1:numel(to7.Traces)
    tr = to7.Traces(k);
    p  = tr.parameters();
    assert(isempty(fieldnames(tr.Params)) && p.Frequency == to6.Traces(k).Params.Frequency ...
        && p.Level == to6.Traces(k).Params.Level, ...
        'trace %d: parameters were not read back off its label',k);
end
to7.SplitBy = 'Frequency';
assert(numel(to7.PanelAxes) == 3,'a version-4 view could not be split by its labels');
to7.saveView(v4File);
S5 = load(v4File,'-mat');
assert(all(arrayfun(@(t) isempty(fieldnames(t.Params)),S5.View.Traces)), ...
    'parameters read off a label were saved back as Params');

% The arrangement itself, with no figure: a trace lacking the split
% parameter gets a panel of its own, last; ties keep their place.
P = struct('Names',{{'Frequency','Level'}},'Values',[8 30; 16 30; 8 60; NaN 70]);
A = mabr.ui.TraceOrganizer.arrangement(P,'Frequency','Level','descending',1:4);
assert(isequaln(A.panelValues,[8 16 NaN]) && ...
       isequal(A.panelLabels,{'8 kHz','16 kHz','No Frequency'}) && ...
       isequal(A.order,[3 1 2 4]) && isequal(A.panel,[1 1 2 3]), ...
    'arrangement: unexpected panels or order');
pos = mabr.ui.TraceOrganizer.panelRects(9,640,700,40,true);
assert(no_overlap_rects(pos),'panelRects: nine panels overlap');
fprintf('  PASS: save/load restores the organization; a version-4 view still organizes\n');

% --- 13. overlap and separate ----------------------------------------------
to8 = mabr.ui.TraceOrganizer();
cleanTo8 = onCleanup(@() delete(to8)); %#ok<NASGU>
for i = 1:4, to8.addBlock(make_block(sprintf('ov%d',i),i)); end
to8.show();
to8.overlapTraces([1 3]);
y = [to8.Traces.YOffset];
assert(isequal(sort(y,'descend'),[0 0 -1 -2]*to8.YSpacing), ...
    'overlap: two traces must share one slot, the others close up');
g = [to8.Traces.Group];
assert(nnz(g > 0) == 2 && numel(unique(g(g>0))) == 1,'overlap: group not recorded');
k = find(g > 0);
assert(to8.Traces(k(1)).YOffset == to8.Traces(k(2)).YOffset,'overlap: members differ in offset');
assert(to8.Traces(k(1)).LabelHandle.Position(2) ~= to8.Traces(k(2)).LabelHandle.Position(2), ...
    'overlap: members'' labels were left on top of each other');
to8.restack();                                  % restacking keeps the slot
assert(numel(unique([to8.Traces.YOffset])) == 3,'restack broke an overlap');
% stepping reaches every member, one at a time, and wraps
to8.select(k(1));
to8.stepOverlap(+1);
assert(isequal(to8.selectedIndices(),k(2)),'stepOverlap did not reach the other member');
to8.stepOverlap(+1);
assert(isequal(to8.selectedIndices(),k(1)),'stepOverlap did not wrap');
% a save/load keeps the group
ovFile = fullfile(outDir,'overlap.torg');
to8.saveView(ovFile);
to9 = mabr.ui.TraceOrganizer();
cleanTo9 = onCleanup(@() delete(to9)); %#ok<NASGU>
to9.loadView(ovFile);
assert(isequal([to9.Traces.Group],[to8.Traces.Group]) && ...
       isequal([to9.Traces.YOffset],[to8.Traces.YOffset]),'overlap lost in save/load');
delete(ovFile);
% removing one member dissolves the group
to8.removeTraces(k(2));
assert(all([to8.Traces.Group] == 0),'a lone trace was left in an overlap group');
% separate
to8.addBlock(make_block('ov5',5));
to8.overlapTraces([1 2 3]);
assert(numel(unique([to8.Traces.YOffset])) == numel(to8.Traces) - 2,'overlap of three');
to8.select(1);
to8.separateTraces();
assert(all([to8.Traces.Group] == 0) && numel(unique([to8.Traces.YOffset])) == numel(to8.Traces), ...
    'separate: every trace must have its own line again');
% the pure gather: members brought beside the first of their group
g = mabr.ui.TraceOrganizer.gatherOrder([1 1 1 1 2 2],[7 0 7 0 3 3]);
assert(isequal(g,[1 3 2 4 5 6]),'gatherOrder: unexpected permutation');
fprintf('  PASS: overlap shares a slot, survives restack/save, steps, and separates\n');

delete(viewFile); delete(oldFile); delete(orgFile); delete(v4File);
fprintf('== verify_trace_organizer PASSED ==\n');
end


% =====================================================================
function s = view_state(to)
% Everything a redraw decides: each trace's drawn data and label, and the
% axes' limits and placement (the label margin).
tr = to.Traces;
s = struct('XLim',to.Axes.XLim,'YLim',to.Axes.YLim,'Position',to.Axes.Position, ...
    'X',{arrayfun(@(t) t.LineHandle.XData,tr,'UniformOutput',false)}, ...
    'Y',{arrayfun(@(t) t.LineHandle.YData,tr,'UniformOutput',false)}, ...
    'LabelPos',{arrayfun(@(t) t.LabelHandle.Position,tr,'UniformOutput',false)}, ...
    'LabelStr',{arrayfun(@(t) t.LabelHandle.String,tr,'UniformOutput',false)});
end

function s = panel_state(to,withPosition)
% Everything a redraw decides across the panels: each panel's limits,
% title, and (optionally) placement, and each trace's panel, drawn data and
% label.
pax = to.PanelAxes;
tr  = to.Traces;
s = struct( ...
    'XLim',    {arrayfun(@(a) a.XLim,pax,'UniformOutput',false)}, ...
    'YLim',    {arrayfun(@(a) a.YLim,pax,'UniformOutput',false)}, ...
    'Title',   {arrayfun(@(a) a.Title.String,pax,'UniformOutput',false)}, ...
    'Panel',   {arrayfun(@(t) find(pax == t.LineHandle.Parent),tr,'UniformOutput',false)}, ...
    'X',       {arrayfun(@(t) t.LineHandle.XData,tr,'UniformOutput',false)}, ...
    'Y',       {arrayfun(@(t) t.LineHandle.YData,tr,'UniformOutput',false)}, ...
    'LabelPos',{arrayfun(@(t) t.LabelHandle.Position,tr,'UniformOutput',false)}, ...
    'LabelStr',{arrayfun(@(t) t.LabelHandle.String,tr,'UniformOutput',false)});
if withPosition
    s.Position = arrayfun(@(a) a.Position,pax,'UniformOutput',false);
end
end

function v = param_of(to,name)
% One stimulus parameter of every trace, in the order the traces are held.
v = arrayfun(@(t) t.Params.(name),to.Traces);
end

function lv = levels_top_down(to,f)
% The levels in the frequency-f panel, read top to bottom.
in = param_of(to,'Frequency') == f;
tr = to.Traces(in);
[~,o] = sort([tr.YOffset],'descend');
lv = arrayfun(@(t) t.Params.Level,tr(o));
end

function tf = no_overlap(ax)
tf = no_overlap_rects(cell2mat(arrayfun(@(a) a.Position,ax(:),'UniformOutput',false)));
end

function tf = no_overlap_rects(pos)
tf = true;
for i = 1:size(pos,1)
    for j = i+1:size(pos,1)
        a = pos(i,:); b = pos(j,:);
        if a(1) < b(1)+b(3)-1e-9 && b(1) < a(1)+a(3)-1e-9 && ...
           a(2) < b(2)+b(4)-1e-9 && b(2) < a(2)+a(4)-1e-9
            tf = false;
            return
        end
    end
end
end

function block = make_grid_block(f,lvl)
% A synthetic block from a Frequency x Level grid, its metadata shaped as
% mabr.stim.StimulusSet.meta writes it. The wavelet is scaled to a peak set
% by level alone, so every frequency at one level has the same amplitude --
% which keeps the shared scale still while quieter traces arrive.
Fs = 12000;
nSweeps = 8; period = round(Fs/21.1);
N = nSweeps*period + period;

tw = (0:round(0.002*Fs)-1)'/Fs;
wavelet = sin(2*pi*(400+20*f)*tw).*hann(numel(tw));
wavelet = wavelet/max(abs(wavelet))*1e-6*10^((lvl-90)/20);

data   = zeros(N,1);
onsets = (round(0.05*Fs) + (0:nSweeps-1)*period)';
for i = 1:nSweeps
    i0 = onsets(i);
    data(i0:i0+numel(wavelet)-1) = data(i0:i0+numel(wavelet)-1) + wavelet;
end

id   = sprintf('Tone_%g_%g',f,lvl);
rec  = mabr.data.Recording(Fs,data,onsets,round(0.01*Fs),1);
meta = struct('ID',id,'Frequency',f,'Level',lvl,'alternatePolarity',false, ...
              'informativeParams',{{'Frequency','Level'}}, ...
              'Label',{{sprintf('ID = %s',id),sprintf('Frequency = %g',f), ...
                        sprintf('Level = %g',lvl)}});
block = mabr.data.Block(struct('Meta',meta,'SampleRate',Fs),rec);
end

function block = make_block(id,k)
% A short synthetic block with a distinct wavelet, tagged with a stimulus ID.
Fs = 12000; df = 1;
nSweeps = 8; period = round(Fs/21.1);
N = nSweeps*period + period;

tw = (0:round(0.002*Fs)-1)'/Fs;
wavelet = sin(2*pi*(600+100*k)*tw).*hann(numel(tw))*1e-6*k;

data   = 1e-9*randn(N,1);
onsets = (round(0.05*Fs) + (0:nSweeps-1)*period)';
for i = 1:nSweeps
    i0 = onsets(i);
    data(i0:i0+numel(wavelet)-1) = data(i0:i0+numel(wavelet)-1) + wavelet;
end

rec  = mabr.data.Recording(Fs,data,onsets,round(0.01*Fs),df);
meta = struct('ID',id,'Level',60,'informativeParams',{{'Level'}}, ...
              'Label',{{sprintf('ID = %s',id),'Level = 60'}});
block = mabr.data.Block(struct('Meta',meta,'SampleRate',Fs),rec);
end
