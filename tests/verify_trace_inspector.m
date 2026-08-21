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
%          Apply -- is never silently recomputed by a later open.
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

fprintf('== verify_trace_inspector PASSED ==\n');
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
