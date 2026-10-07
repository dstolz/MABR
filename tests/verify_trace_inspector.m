function verify_trace_inspector()
% verify_trace_inspector  Exercise the TraceInspector peak picker.
%
%   Builds a trace whose peaks and troughs sit at known latencies, then
%   checks, with no audio hardware:
%       1. auto-detect puts each wave on the right feature of its own
%          search window, and a trough row finds a trough;
%       2. a window that holds no local extremum still reports the best
%          answer it has rather than nothing;
%       3. click-to-place snaps to the nearby peak; nudging moves by
%          samples; clearing unplaces;
%       4. smoothing changes the view and the detection but never the
%          sample indices that get transferred;
%       5. Apply transfers the placed waves to the mabr.ui.Trace in
%          temporal order with their names, and Cancel transfers nothing;
%       6. reopening on a marked trace seeds the table from those markers;
%       7. the organizer opens one inspector per trace, raises rather than
%          rebuilds it, redraws when it applies, and closes it when the
%          trace it was editing is removed;
%       8. double-clicking a trace (or its label) is what opens it, and
%          leaves nothing dragging behind it;
%       9. opening on an unmarked trace auto-detects every enabled wave with
%          no button press, but a pick already there -- from an earlier
%          Apply -- is never silently recomputed by a later open;
%      10. selecting a table cell never rewrites the table (which is what
%          closed the Type dropdown as it opened), and a Type edit lands;
%      11. Add wave names new rows with the next unused capital letter,
%          Remove wave deletes the selected row only, and a name must be
%          unique, non-blank and not a plain number;
%      12. the wave table -- custom waves included -- persists across
%          inspectors, while the organizer's 1, 2, 3 ... peak numbering never
%          becomes a wave (nor does an older saved table keep such rows);
%      13. the peak comparison matrices are column-minus-row, antisymmetric
%          and zero-diagonal, and their window opens once, follows the picks,
%          and closes with the inspector.
%
%   The user's saved search windows are preserved. Creates figures but needs
%   no hardware. Run:
%       >> verify_trace_inspector
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_trace_inspector ==\n');

% The inspector persists its search windows on Apply; leave the user's alone.
hadPref = ispref('MABR','TraceInspectorWaves');
if hadPref
    savedWaves = getpref('MABR','TraceInspectorWaves');
    restore = onCleanup(@() setpref('MABR','TraceInspectorWaves',savedWaves));
else
    restore = onCleanup(@() rmIfPresent('TraceInspectorWaves'));
end

Fs = 12000;
[y,t,truth] = make_wave(Fs);      % peaks at 1.5, 2.5, 3.5 ms; trough at 4.2
tr = mabr.ui.Trace(y,t,'8kHz 60dB','8kHz_60dB');
tr.Color = [0 0.4 0.8];

insp = mabr.ui.TraceInspector(tr);
cleanInsp = onCleanup(@() delete(insp));

% --- 1. auto-detect inside the search windows ----------------------------
assert(insp.isopen(),'the inspector did not open a window');
assert(numel(insp.Waves) >= 3,'expected the default I-V wave rows');
assert(insp.setWindow(1,1.0,2.0),'setWindow rejected a valid window');
assert(insp.setWindow(2,2.0,3.0),'setWindow rejected a valid window');
assert(insp.setWindow(3,3.0,4.0),'setWindow rejected a valid window');
assert(insp.setWindow(4,4.0,4.6,'Trough'),'setWindow rejected a valid trough window');
for i = 5:numel(insp.Waves)
    insp.setWindow(i,9.0,9.9);     % out of the way of the features above
end
insp.autoDetect();

lat = @(i) t(insp.Waves(i).Loc)*1000;
for i = 1:3
    assert(~isnan(insp.Waves(i).Loc),'wave %d was not placed by auto-detect',i);
    assert(abs(lat(i)-truth.peaks(i)) < 0.1, ...
        'wave %d landed at %.2f ms, expected %.2f',i,lat(i),truth.peaks(i));
end
assert(abs(lat(4)-truth.trough) < 0.1, ...
    'the trough row landed at %.2f ms, expected %.2f',lat(4),truth.trough);
assert(y(insp.Waves(4).Loc) < 0,'a Trough row placed its marker on a positive sample');
fprintf('  PASS: auto-detect finds each peak (and a trough) in its own window\n');

% --- 2. a window with no local extremum still answers --------------------
% The rising flank into the first peak contains no turning point at all.
insp.setWindow(5,1.0,1.3);
insp.autoDetect(5);
assert(~isnan(insp.Waves(5).Loc), ...
    'a window with no local peak should still report its best sample');
assert(lat(5) >= 1.0-1e-9 && lat(5) <= 1.3+1e-9, ...
    'the fallback answer left the window (%.2f ms)',lat(5));
insp.enableWave(5,false);
insp.clearWave(5);
fprintf('  PASS: a window with no turning point reports its extremum\n');

% --- 3. click to place, nudge, clear --------------------------------------
insp.clearWave(1);
assert(isnan(insp.Waves(1).Loc),'clearWave did not unplace the wave');
insp.setWaveTime(1,truth.peaks(1)+0.15,true);      % "click" near the peak
assert(abs(lat(1)-truth.peaks(1)) < 0.05, ...
    'a click near the peak did not snap to it (%.2f ms)',lat(1));

k0 = insp.Waves(1).Loc;
insp.nudgeWave(1,+3);
assert(insp.Waves(1).Loc == k0+3,'nudge did not move 3 samples');
insp.nudgeWave(1,-3);
assert(insp.Waves(1).Loc == k0,'nudge back did not restore the position');

insp.SnapWindow = 0;                                % place exactly where told
insp.setWaveTime(1,truth.peaks(1)+0.15,true);
assert(abs(lat(1)-(truth.peaks(1)+0.15)) < 0.1, ...
    'with snapping off the marker should stay where it was put');
insp.SnapWindow = 0.25;
insp.setWaveTime(1,truth.peaks(1),true);
fprintf('  PASS: click-to-place snaps, nudge steps by samples, clear unplaces\n');

% --- 4. smoothing is a view, not a change ---------------------------------
noisy = mabr.ui.Trace(y + 2e-8*sin(2*pi*3000*t),t,'noisy','noisy');
insp2 = mabr.ui.TraceInspector(noisy);
cleanInsp2 = onCleanup(@() delete(insp2)); %#ok<NASGU>
insp2.setWindow(1,1.0,2.0);
insp2.SmoothSpan = 9;
insp2.autoDetect(1);
assert(abs(t(insp2.Waves(1).Loc)*1000 - truth.peaks(1)) < 0.2, ...
    'detection on the smoothed view lost the peak');
insp2.apply();
assert(isequal(noisy.Data,double(y + 2e-8*sin(2*pi*3000*t))), ...
    'smoothing must never be written back into the trace');
assert(noisy.MarkerLocs(1) >= 1 && noisy.MarkerLocs(1) <= numel(noisy.Data), ...
    'the transferred marker is not a sample index into the raw trace');
fprintf('  PASS: smoothing changes the view and detection, never the data\n');

% --- 5. Apply transfers, Cancel does not ---------------------------------
tr.clearMarkers();
insp3 = mabr.ui.TraceInspector(tr);
insp3.setWindow(1,1.0,2.0); insp3.setWindow(2,2.0,3.0);
insp3.autoDetect([1 2]);
insp3.cancel();
assert(isempty(tr.MarkerLocs),'Cancel wrote markers onto the trace');
assert(~insp3.Applied,'Cancel should not report Applied');
delete(insp3);

% The apply callback is what tells the organizer to redraw; route it through
% appdata so this can be observed without a second window. Only waves 1-3
% are wanted in this transfer -- opening now auto-detects every enabled wave
% (see section 9), so 4 and 5 are switched off rather than left to compete.
setappdata(0,'MABR_TI_TEST',false);
insp4 = mabr.ui.TraceInspector(tr,@() setappdata(0,'MABR_TI_TEST',true));
insp4.enableWave(4,false); insp4.enableWave(5,false);
insp4.setWindow(1,1.0,2.0); insp4.setWindow(2,2.0,3.0); insp4.setWindow(3,3.0,4.0);
insp4.autoDetect([1 2 3]);
names0 = {insp4.Waves(1:3).Name};
insp4.apply();
applied = getappdata(0,'MABR_TI_TEST');
rmappdata(0,'MABR_TI_TEST');

assert(numel(tr.MarkerLocs) == 3,'Apply transferred %d of 3 waves',numel(tr.MarkerLocs));
assert(issorted(tr.MarkerLocs),'transferred markers are not in temporal order');
assert(isequal(tr.MarkerText,names0),'transferred markers lost their wave names: %s', ...
    strjoin(tr.MarkerText,','));
assert(applied,'the apply callback did not fire');
assert(insp4.Applied,'Apply should report Applied');
assert(~insp4.isopen(),'Apply should close the window');
fprintf('  PASS: Apply transfers named waves in order and notifies; Cancel does not\n');

% --- 6. reopening seeds from the markers already on the trace ------------
insp5 = mabr.ui.TraceInspector(tr);
cleanInsp5 = onCleanup(@() delete(insp5)); %#ok<NASGU>
for i = 1:3
    j = find(strcmp({insp5.Waves.Name},names0{i}),1);
    assert(~isempty(j),'wave %s was not seeded from the trace markers',names0{i});
    assert(insp5.Waves(j).Loc == tr.MarkerLocs(i), ...
        'wave %s was seeded at the wrong sample',names0{i});
end
r = insp5.results();
assert(height(r) >= 3,'results() reported %d of 3 placed waves',height(r));
assert(all(diff(r.Latency_ms) > 0),'results() is not in temporal order');

% Closing keeps the wave table: show() rebuilds the window around it, and the
% rebuilt axes has to be fitted to the trace again rather than left at the
% default limits.
insp5.close();
assert(~insp5.isopen(),'close left the window up');
insp5.show();
assert(insp5.isopen(),'show did not rebuild the closed window');
assert(abs(insp5.Axes.XLim(2) - t(end)*1000) < 0.5, ...
    'the rebuilt view was not fitted to the trace (XLim %s)',mat2str(insp5.Axes.XLim));
assert(insp5.Waves(1).Loc == tr.MarkerLocs(1),'reopening lost the wave table');
delete(insp5);
fprintf('  PASS: reopening seeds the table from the trace''s own markers\n');

% --- 7. organizer integration ---------------------------------------------
to = mabr.ui.TraceOrganizer();
cleanTo = onCleanup(@() delete(to)); %#ok<NASGU>
to.addTrace(y,t,'first','8kHz_60dB');
to.addTrace(y,t,'second','16kHz_60dB');
to.show();

to.select(2);
i1 = to.inspectTrace();                  % via the selection, as the menu does
assert(~isempty(i1) && isvalid(i1) && i1.isopen(),'inspectTrace opened nothing');
assert(i1.Trace == to.Traces(2),'the inspector opened on the wrong trace');

i2 = to.inspectTrace(2);                 % same trace: raise, do not rebuild
assert(i2 == i1,'re-inspecting the same trace built a second inspector');

i3 = to.inspectTrace(1);                 % a different trace: replace
assert(i3 ~= i1,'inspecting another trace reused the first inspector');
assert(~i1.isopen(),'the previous inspector was left open');

% Applying must reach the organizer's own drawing, not just the Trace.
i3.setWindow(1,1.0,2.0);
i3.autoDetect(1);
i3.apply();
assert(~isempty(to.Traces(1).MarkerLocs),'apply did not reach the organizer''s trace');
assert(~isempty(to.Traces(1).Markers) && isgraphics(to.Traces(1).Markers(1).MarkerHandle), ...
    'the organizer did not redraw the marker the inspector applied');

% A trace that goes away takes its inspector with it.
i4 = to.inspectTrace(1);
assert(i4.isopen(),'inspector did not reopen');
to.select(1);
to.removeTraces(1);
assert(~i4.isopen(),'removing the trace left its inspector editing a dead handle');

% "i" is the keyboard route to the same thing.
nWin = @() numel(findall(0,'Type','figure','-regexp','Name','Trace Inspector'));
to.select(1);
n0 = nWin();
to.Figure.WindowKeyPressFcn([],struct('Key','i','Modifier',{{}}));
assert(nWin() == n0+1,'"i" did not open an inspector window');
fprintf('  PASS: organizer opens, raises, redraws from, and prunes the inspector\n');

% --- 8. double-click is the advertised route -----------------------------
% The figure reports a double click as SelectionType 'open', which is what
% onTraceClick branches on -- and which is settable, so the real path can be
% driven here rather than only the method it ends in.
to2 = mabr.ui.TraceOrganizer();
cleanTo2 = onCleanup(@() delete(to2)); %#ok<NASGU>
to2.addTrace(y,t,'first','8kHz_60dB');
to2.addTrace(y,t,'second','16kHz_60dB');
to2.show();

n0 = nWin();
set(to2.Figure,'SelectionType','normal');
to2.Traces(2).LineHandle.ButtonDownFcn([],[]);     % first click of the pair
assert(nWin() == n0,'a single click opened an inspector');
set(to2.Figure,'SelectionType','open');
to2.Traces(2).LineHandle.ButtonDownFcn([],[]);     % ...completes the double click
assert(nWin() == n0+1,'double-clicking a trace did not open the inspector');
assert(isequal(to2.selectedIndices(),2),'double-click did not select the trace it opened');

% A double click must not leave the trace stuck to the mouse: the first click
% of the pair arms a drag, and the second has to disarm it.
off0 = to2.Traces(2).YOffset;
to2.Figure.WindowButtonMotionFcn([],[]);
assert(to2.Traces(2).YOffset == off0,'a double click left the trace dragging');

% The label is the other half of the hit area, and takes the same route.
set(to2.Figure,'SelectionType','open');
to2.Traces(1).LabelHandle.ButtonDownFcn([],[]);
assert(nWin() == n0+1,'double-clicking the label did not re-point the one inspector');
fprintf('  PASS: double-clicking a trace (or its label) opens the inspector\n');

% --- 9. auto-detect runs on open, but never over a pick already there ----
% A clean set of default windows, isolated from whatever earlier sections
% left in prefs, so this section's result depends only on its own trace.
setpref('MABR','TraceInspectorWaves',mabr.ui.TraceInspector.defaultWaves());

freshTr = mabr.ui.Trace(y,t,'fresh','fresh');
insp6 = mabr.ui.TraceInspector(freshTr);
cleanInsp6 = onCleanup(@() delete(insp6)); %#ok<NASGU>
assert(~any(isnan([insp6.Waves.Loc])), ...
    'opening on an unmarked trace should auto-detect every enabled wave');
for i = 1:3
    assert(abs(t(insp6.Waves(i).Loc)*1000 - truth.peaks(i)) < 0.2, ...
        'wave %d was not auto-detected to the right peak on open',i);
end
fprintf('  PASS: opening on an unmarked trace auto-detects with no button press\n');

% Hand-move wave I somewhere the window would never have found on its own,
% apply, and reopen: a fresh inspector on the SAME now-marked trace must
% leave that pick exactly where it was left, not recompute it.
insp6.nudgeWave(1,+50);
movedLoc = insp6.Waves(1).Loc;
insp6.apply();

insp7 = mabr.ui.TraceInspector(freshTr);
cleanInsp7 = onCleanup(@() delete(insp7)); %#ok<NASGU>
j = find(strcmp({insp7.Waves.Name},'I'),1);
assert(~isempty(j),'wave I was not seeded from the trace''s own marker');
assert(insp7.Waves(j).Loc == movedLoc, ...
    'reopening re-ran detection over a pick that was already there');
fprintf('  PASS: a pick already on the trace survives reopening untouched\n');

% --- 10. selecting a row must not rewrite the table -----------------------
% The Type dropdown collapsed the moment it opened because the selection
% callback went through redraw(), which assigns the table's Data -- tearing
% down the cell editor the same click was opening. A value planted straight in
% the table's Data survives a selection only if nothing rewrote the table.
setpref('MABR','TraceInspectorWaves',mabr.ui.TraceInspector.defaultWaves());
insp8 = mabr.ui.TraceInspector(mabr.ui.Trace(y,t,'select','select'));
cleanInsp8 = onCleanup(@() delete(insp8)); %#ok<NASGU>
tbl = findobj(insp8.Figure,'Type','uitable');
assert(isscalar(tbl),'could not find the wave table');
d = tbl.Data;  d{1,1} = 'PLANTED';  tbl.Data = d;
tbl.CellSelectionCallback(tbl,struct('Indices',[2 5]));
assert(strcmp(tbl.Data{1,1},'PLANTED'), ...
    'selecting a cell rewrote the table, which closes the Type dropdown being opened');

% Editing Type through the table's own callback sets the wave's type.
tbl.CellEditCallback(tbl,struct('Indices',[2 5],'NewData','Trough'));
assert(strcmp(insp8.Waves(2).Type,'Trough'),'a Type edit did not reach the wave');
tbl.CellEditCallback(tbl,struct('Indices',[2 5],'NewData','Peak'));
assert(strcmp(insp8.Waves(2).Type,'Peak'),'a Type edit back to Peak did not reach the wave');
fprintf('  PASS: selecting a cell leaves the table alone; a Type edit lands\n');

% --- 11. wave names, adding and removing ---------------------------------
assert(strcmp(mabr.ui.TraceInspector.nextWaveName({'I','V'}),'A'), ...
    'the first added wave should be A');
assert(strcmp(mabr.ui.TraceInspector.nextWaveName({'A','B','C'}),'D'),'letters do not run on');
assert(strcmp(mabr.ui.TraceInspector.nextWaveName({'a'}),'B'),'a lower-case name should count as taken');
assert(strcmp(mabr.ui.TraceInspector.nextWaveName(cellstr(char('A'+(0:25))')),'AA'), ...
    'after Z the next name should be AA');

nBefore = numel(insp8.Waves);
added = {};
for k = 1:9
    ii = insp8.addWave();
    added{end+1} = insp8.Waves(ii).Name; %#ok<AGROW>
end
assert(isequal(added,{'A','B','C','D','E','F','G','H','J'}), ...
    'added waves should take the unused capitals in order, skipping I: %s',strjoin(added,','));
assert(numel(insp8.Waves) == nBefore+9,'addWave did not append a row each time');
assert(all([insp8.Waves(end-8:end).Enabled]),'an added wave should be on');
assert(all(isnan([insp8.Waves(end-8:end).Loc])),'an added wave should start unplaced');
w = insp8.Waves(end);
assert(w.TMax > w.TMin && w.TMin >= t(1)*1000 && w.TMax <= t(end)*1000+1e-9, ...
    'an added wave got a window outside the trace (%g..%g ms)',w.TMin,w.TMax);

% Remove: only the selected row, and nothing when none is selected.
n0 = numel(insp8.Waves);
tbl = findobj(insp8.Figure,'Type','uitable');
tbl.CellSelectionCallback(tbl,struct('Indices',[nBefore+1 1]));   % wave A
insp8.removeWave();
assert(numel(insp8.Waves) == n0-1 && ~any(strcmp({insp8.Waves.Name},'A')), ...
    'Remove wave did not delete the selected row');
assert(any(strcmp({insp8.Waves.Name},'B')),'Remove wave deleted more than the selected row');
insp8.removeWave();                      % selection was cleared by the removal
assert(numel(insp8.Waves) == n0-1,'Remove wave with nothing selected changed the table');
assert(strcmp(insp8.Waves(nBefore+1).Name,'B'),'rows after a removed one moved the wrong way');

% Renaming through the table: a custom name is accepted, a clash or a plain
% number is put back.
k = nBefore+1;
tbl = findobj(insp8.Figure,'Type','uitable');
tbl.CellEditCallback(tbl,struct('Indices',[k 1],'NewData','N1'));
assert(strcmp(insp8.Waves(k).Name,'N1'),'a custom name was not accepted');
tbl.CellEditCallback(tbl,struct('Indices',[k 1],'NewData','ii'));
assert(strcmp(insp8.Waves(k).Name,'N1'),'a name already in use (any case) was accepted');
tbl.CellEditCallback(tbl,struct('Indices',[k 1],'NewData','7'));
assert(strcmp(insp8.Waves(k).Name,'N1'),'a plain-number name was accepted');
tbl.CellEditCallback(tbl,struct('Indices',[k 1],'NewData','   '));
assert(strcmp(insp8.Waves(k).Name,'N1'),'a blank name was accepted');
assert(strcmp(strtrim(tbl.Data{k,1}),'N1'),'the table kept a rejected name on screen');
assertError(@() insp8.addWave('N1'),'mabr:ui:TraceInspector:badName');
assertError(@() insp8.addWave('42'),'mabr:ui:TraceInspector:badName');
fprintf('  PASS: Add/Remove wave, capital-letter names, and name checks\n');

% --- 12. the table (custom waves included) persists; numbering does not ---
% Keep one custom wave, drop everything lettered, apply, and reopen on a
% different trace: the custom wave is back, the removed ones are not.
for nm = {'B','C','D','E','F','G','H','J'}
    insp8.removeWave(find(strcmp({insp8.Waves.Name},nm{1}),1));
end
insp8.setWindow(find(strcmp({insp8.Waves.Name},'N1')),2.0,3.0,'Trough');
insp8.apply();
insp9 = mabr.ui.TraceInspector(mabr.ui.Trace(y,t,'again','again'));
cleanInsp9 = onCleanup(@() delete(insp9)); %#ok<NASGU>
assert(isequal({insp9.Waves.Name},{'I','II','III','IV','V','N1'}), ...
    'the saved table did not come back: %s',strjoin({insp9.Waves.Name},','));
assert(strcmp(insp9.Waves(6).Type,'Trough') && insp9.Waves(6).TMin == 2.0, ...
    'a custom wave lost its window or type across sessions');
delete(insp9);

% The organizer's Mark peaks labels markers 1, 2, 3 ...; those are numbering,
% not waves, and must not become rows -- in the table or in the pref.
numbered = mabr.ui.Trace(y,t,'numbered','numbered');
numbered.setMarkers([20 40 60 80 100]);                  % default text: '1'..'5'
assert(isequal(numbered.MarkerText,{'1','2','3','4','5'}), ...
    'expected Trace.setMarkers to number the markers (premise of this check)');
insp10 = mabr.ui.TraceInspector(numbered);
cleanInsp10 = onCleanup(@() delete(insp10)); %#ok<NASGU>
assert(~any(cellfun(@mabr.ui.TraceInspector.isAutoNumber,{insp10.Waves.Name})), ...
    'the organizer''s peak numbering was seeded into the wave table: %s', ...
    strjoin({insp10.Waves.Name},','));
delete(insp10);

% A table an older version saved with those rows heals itself on load.
legacy = mabr.ui.TraceInspector.defaultWaves();
for k = 1:3
    legacy(end+1) = legacy(1); %#ok<AGROW>
    legacy(end).Name = sprintf('%d',k);
end
setpref('MABR','TraceInspectorWaves',legacy);
insp11 = mabr.ui.TraceInspector(mabr.ui.Trace(y,t,'legacy','legacy'));
cleanInsp11 = onCleanup(@() delete(insp11)); %#ok<NASGU>
assert(isequal({insp11.Waves.Name},{'I','II','III','IV','V'}), ...
    'numbered rows saved by an older version were not dropped: %s', ...
    strjoin({insp11.Waves.Name},','));
fprintf('  PASS: custom waves persist; the organizer''s numbering is never a wave\n');

% --- 13. the peak comparison matrices --------------------------------------
% A trace and an inspector of its own, with exactly the three picks this
% section reasons about, rather than whatever the sections above left placed.
mtxTr = mabr.ui.Trace(y,t,'matrix','matrix');
insp12 = mabr.ui.TraceInspector(mtxTr);
cleanInsp12 = onCleanup(@() delete(insp12)); %#ok<NASGU>
for i = 1:numel(insp12.Waves), insp12.enableWave(i,i <= 3); end
assert(insp12.setWindow(1,1.0,2.0,'Peak') && insp12.setWindow(2,2.0,3.0,'Peak') && ...
       insp12.setWindow(3,3.0,4.0,'Peak'),'setWindow rejected a valid window');
insp12.clearAll();
insp12.autoDetect();

dm = insp12.peakDifferences();
nw = numel(dm.Names);
assert(nw == 3,'expected the three enabled waves, got %d',nw);
assert(all(diff(dm.Latency) > 0),'peakDifferences did not order the waves in time');
assert(isequal(size(dm.dLatency),[nw nw]) && isequal(size(dm.dAmplitude),[nw nw]), ...
    'the difference matrices are not square over the placed waves');
% Column minus row, antisymmetric, zero diagonal -- the whole contract the
% heat maps are drawn from.
assert(abs(dm.dLatency(1,2) - (dm.Latency(2)-dm.Latency(1))) < 1e-9, ...
    'dLatency(i,j) is not Latency(j) - Latency(i)');
assert(abs(dm.dAmplitude(2,1) - (dm.Amplitude(1)-dm.Amplitude(2))) < 1e-9, ...
    'dAmplitude(i,j) is not Amplitude(j) - Amplitude(i)');
assert(max(abs(dm.dLatency + dm.dLatency.'),[],'all') < 1e-9 && ...
       max(abs(dm.dAmplitude + dm.dAmplitude.'),[],'all') < 1e-9, ...
    'the difference matrices are not antisymmetric');
assert(all(diag(dm.dLatency) == 0) && all(diag(dm.dAmplitude) == 0), ...
    'a wave differs from itself');

nFig = @() numel(findobj(0,'Type','figure','-regexp','Name','Peak Comparison'));
before = nFig();
insp12.showMatrices();
assert(nFig() == before+1,'showMatrices did not open the comparison window');
insp12.showMatrices();
assert(nFig() == before+1,'a second press opened a second comparison window');
% It has to follow the picks: a stale matrix is worse than none.
insp12.nudgeWave(1,-3);
assert(nFig() == before+1,'redrawing the inspector rebuilt the comparison window');
dm2 = insp12.peakDifferences();
assert(abs(dm2.dLatency(1,2) - dm.dLatency(1,2)) > 1e-9, ...
    'nudging a wave left the difference matrix unchanged');
insp12.cancel();
assert(nFig() == before, ...
    'closing the inspector left its comparison window behind');

cmap = mabr.ui.TraceInspector.divergingMap([0 0 1],[1 0 0],64);
assert(isequal(size(cmap),[64 3]) && all(cmap(:) >= 0 & cmap(:) <= 1), ...
    'divergingMap did not return a 64x3 colormap in range');
assert(all(abs(cmap(1,:) - [0 0 1]) < 1e-9) && all(abs(cmap(end,:) - [1 0 0]) < 1e-9), ...
    'divergingMap did not put the two hues at the two ends');
assert(min(sum(abs(cmap - 0.98),2)) < 0.1,'divergingMap has no neutral centre');
fprintf('  PASS: the comparison matrices, and the window that draws them\n');

fprintf('== verify_trace_inspector PASSED ==\n');
end

function assertError(fcn,id)
try
    fcn();
catch me
    assert(strcmp(me.identifier,id),'expected %s but got %s: %s',id,me.identifier,me.message);
    return
end
error('expected %s but nothing was thrown',id);
end


% =====================================================================
function [y,t,truth] = make_wave(Fs)
% A 10 ms trace with three positive peaks and one trough at known latencies.
t = (0:round(0.010*Fs)-1)'/Fs;
truth.peaks  = [1.5 2.5 3.5];
truth.trough = 4.2;
amps = [1.0 0.7 0.5]*1e-6;
y = zeros(size(t));
for i = 1:numel(truth.peaks)
    y = y + amps(i)*exp(-((t*1000 - truth.peaks(i))/0.22).^2);
end
y = y - 0.6e-6*exp(-((t*1000 - truth.trough)/0.22).^2);
end

function rmIfPresent(name)
if ispref('MABR',name), rmpref('MABR',name); end
end
