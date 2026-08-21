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
%          finalizes, without duplicating listeners.
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
names = {'Amplitude','Spacing','Traces','Peaks','File'};
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

delete(viewFile); delete(oldFile);
fprintf('== verify_trace_organizer PASSED ==\n');
end


% =====================================================================
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
