# Viewing Data

MABR has two viewers for the data itself: a live plot for the condition being recorded now, and the Trace Organizer for comparing finished conditions. Both open with the app and are laid out beside the main window; the trace-on-axes and stacked-traces toolbar buttons raise them, and where you leave them is remembered across sessions.

A third window, the **Progress Monitor**, reports on the *schedule* rather than the data: how much of the plan is done and which conditions are still short. It opens on demand from the toolbar (and by itself for a stimulation-only run, where nothing is recorded and it is the only window with anything in it).

## Live Plot

Opens with the app, and is raised by the trace-on-axes toolbar button or by pressing Start. Closing it discards the window; the button builds a fresh one.

**Latest sweep** — across the top, on its own axes: the most recent single sweep. A sanity check on the raw signal — if it is railing, flat, or dominated by 60 Hz, something is wrong with the electrodes or grounding. It turns **red** when that sweep was the one rejected. It keeps its own axes because a single sweep is tens of times the size of an average; sharing an axis would flatten the means below it. The title names the condition the sweep came from and the sweep count so far.

**Running means** — below it, one average per stimulus **the current run is presenting**, over the sweeps that passed the artifact criterion. This is the ABR taking shape: early on mostly noise, then the time-locked response emerges as the background flattens. A blocked run presents one stimulus, so there is one mean; an interleaved or shuffled run presents several at once, and each gets its own average rather than being pooled into one meaningless trace.

**Conditions are named by their parameters.** A bank almost never varies along one dimension — the ordinary run is a Frequency × Level grid — so the averages are labelled `8 kHz, 30 dB` rather than by a raw stimulus ID, ordered by those parameters rather than by the order the schedule happened to present them in, and grouped by one of them. Only the parameters your bank actually varies appear: a bank at a single frequency labels its conditions `30 dB`, `50 dB`, `70 dB`, and a parameter that is the same everywhere never clutters a label. A blocked run's single mean is named the same way, in the axes title.

Grouping is what makes a two-parameter run readable. Each group takes a colour, and its members shade from pale to full along the other parameter, so a level series looks like a series instead of five unrelated colours — and the group is what forms the columns of the Grid and Stacked layouts below.

**Error bands** — right-click the means for **Error band**, and each average gains a shaded region in its own colour:

| | Shows | Read it when |
| --- | --- | --- |
| **± 1 SD** | how much a *single sweep* varies | you want the noise floor. It does **not** shrink as sweeps accumulate — it describes the recording, not the average |
| **± 1 SEM** | how well the *mean* is pinned down | you want to know whether the average has settled. This is the one that visibly tightens as the run goes |
| **90 / 95 / 99% confidence** | the parametric interval for the mean | you want a stated criterion. Student's t, so it stays honest over the first few sweeps rather than over-promising |

A condition with fewer than two surviving sweeps gets no band — not a band of zero width, which would claim a precision nothing has established. The y label names the statistic in force, so a screenshot never leaves it ambiguous.

SEM and confidence bands are part of the amplitude scaling: turning one on frames it. An SD band deliberately is not, and will run off the axes — on an ABR the spread of a single sweep is tens of times the average, and letting it set the scale would flatten every mean in the window to a line. That is the SD band's message rather than a bug.

**Controls** — the strip along the bottom of the window:

- **Means: Overlaid / Separate / Grid / Stacked** — all the averages on one axes (easiest for comparing them directly); one small panel each, titled with its condition and running count (easiest when there are many, or when they differ hugely in size); a **grid** with one group per column and the other parameter up the rows, largest at the top, which is the live version of the figure the offline pipeline draws; or **stacked**, one axes per group with its conditions offset into it and named on the y axis — the shape a threshold is actually read from, filling in as the session runs.
- **Group** — the parameter the conditions are grouped by. *Auto* picks Frequency where your bank varies one, otherwise the coarsest parameter; *None* switches grouping off; or name one yourself. A run that varies only one parameter is deliberately left ungrouped — that one dimension is the series itself. The menu lists the parameters your bank varies, and is greyed out when it has none.
- **Time (ms)** — the displayed window, `-2` to `10` by default. Negative time is the pre-onset baseline, which is what tells you what "no response" looks like on this preparation today. Widening past what was recorded simply stops at the recorded edge.
- **Amplitude** — *Auto (each)* scales every stimulus to its own peak, which is what you want when levels differ by 40 dB; *Auto (shared)* holds them all to one scale, which is the only way an amplitude difference between conditions is visible; *Manual* pins the scale to a ± value you type, so it stops moving between refreshes. Overlaid means share an axis and so share a scale — *each* behaves as *shared* there; in **Stacked** the same choice sets the spacing between traces. The latest-sweep axes always scales itself, Manual included.

**Artifact readout** — when sweeps are being rejected, a red `N rejected (x%)` appears in the top-left corner of the latest-sweep panel, and the count also accumulates in the Run panel's `rejected:` readout beside the sweep count. Nothing appears while every sweep is being kept. A rate climbing through a few percent usually means the preparation needs attention rather than more sweeps. What the live view shows is a *preview* of the criterion applied to the sweeps as they arrive; the recorded verdict is made when the condition finalizes, and only that one reaches the file.

**Correlation bar** — A single bar showing how reproducible the response currently is, on a 0–1 scale, with your threshold marked. It compares the split-half consistency of the response window against that of the pre-stimulus baseline, so it reflects genuine time-locked signal rather than sweeps merely looking alike. When the bar reaches the marked threshold, the correlation advance criterion fires and the condition ends.

The plot refreshes about 20 times per second and resets at the start of each condition.

## Progress Monitor

Opens from the three-bars toolbar button. Small, cheap to leave open, and pinnable — **Always on top** keeps it above every other window, which is the point of it on a second monitor or in the corner of a busy screen. The setting is remembered per rig, along with where you leave the window.

Across the top: how far along the whole schedule is, the state lamp and the run number, and elapsed time with an estimate of what is left. The estimate is measured from the rate the session is actually going at once there is enough of one to measure, and from the plan's own timing before that — either way it is an estimate, since a randomized ISI makes a duration an expectation and an advance criterion can end any run early.

**View** picks what fills the rest of the window:

- **Simple** — two bars: the whole session, and the run streaming right now. What to leave up when the question is "how long until I can go home".
- **Bars** — one bar per stimulus, or, with **Group** set to a stimulus parameter, one bar per value of it. A 4-frequency × 5-level bank is 20 bars by stimulus, 4 by Frequency, 5 by Level — the same progress, asked three ways. A bar being presented right now is amber; a finished one turns green.
- **Heat map** — the classic grid: one parameter across (frequency), one up (level), each cell shaded by how complete that condition is. This is the one view that shows a **hole** — a condition the bank does not contain, drawn empty rather than as a small number — which is how a design mistake becomes visible before the session ends rather than during analysis.

**Show** decides what the numbers read as: **Counts** (`128/512`), **Percent**, or **None** — the shading alone, which is the right setting for a window read from across the rig.

**What is being counted** is presentations, not files: a condition is complete when every sweep the plan asked for has been presented. Two consequences are worth knowing. Sweeps arriving during a run are counted as they arrive, so a bar moves continuously rather than jumping once per condition. And when artifact **Repeat** appends make-up runs, the plan gets *larger* — so overall progress steps back slightly at that moment. That is the truth: the work grew. In a stimulation-only run nothing is recorded, so the counts are presentations *played* (the header says so) and the bars step once per run.

## Trace Organizer

Opens with the app, and is raised by the stacked-traces toolbar button. Closing it only disposes the window — the traces are kept, and the button brings them back. It stacks the mean waveform of every completed condition on one time axis so you can read a series — usually a level series at one frequency — as a whole.

**What you can do:**

- **Drag a trace vertically** to reorder or separate the stack. Click and drag; release to drop.
- **Mark peaks** — **Peaks ▸ Mark peaks** (or the ▼-over-a-peak toolbar button, or `p`) finds and labels response peaks on the selected trace, for identifying waves I–V.
- **Double-click a trace** to open it in the **Trace Inspector** (below) and measure it properly.
- **Save / load** the arrangement, so a figure you have laid out can be recovered later.

Traces are labeled with their stimulus parameters and coloured in sequence. Time is shown in milliseconds relative to sweep onset.

Reading a level series: as level decreases, the response amplitude shrinks and its peaks shift later. The lowest level at which a repeatable waveform is still visible is the visually-determined threshold. For an objective, statistically-defined threshold across a whole study, use the offline pipeline — see [Offline Analysis](Offline-Analysis.md).

## Trace Inspector

**Double-click a trace** in the organizer (or select it and press `i`, or **Peaks ▸ Inspect trace…**) to open it on its own, full size, in microvolts. The stack normalizes every trace to one shared scale — that is what makes a level series readable, and what makes any single waveform too small to measure — so latencies are picked here and sent back when you are done.

**Waves** are the rows of the table on the right: a name, a **search window** in ms after stimulus onset, and whether you expect a **Peak** or a **Trough** there. Waves I–V come pre-filled with starting windows; edit them to suit your preparation and they are remembered for next time.

**Opening the window already picks what it can.** A trace with nothing marked yet is auto-detected the moment the inspector opens, so you see peaks immediately instead of a blank waveform waiting for a button press. Anything already placed — from an earlier pass, or wherever you have since dragged it — is left exactly where it is; only a wave still unplaced gets auto-detected.

**Placing a wave:**

- **Auto-detect** (or `a`) puts every enabled wave on the most prominent feature inside its own window — **including** ones already placed, so it is also how you recompute a wave after widening its window. (The automatic pass on open is narrower: it only fills waves that are still unplaced, so it can never undo a pick you already made.) A window containing no turning point at all still reports its best sample, so you can see that the window, not the response, is what needs fixing.
- **Click the trace** with a wave row selected to place that wave where you clicked — it snaps to the nearest peak within the **Snap** distance, so "near enough" is enough.
- **Drag a marker** to move it, or nudge the selected wave with `Left` / `Right` (`Shift` for ten samples at a time). A marker is free to leave its window; the window only tells Auto-detect where to look.
- `Delete` clears the selected wave, `c` clears all of them.

**Reading it:** the table shows each wave's latency and amplitude, and the summary underneath gives the interpeak intervals — I–II, II–III, and so on, plus the overall I–V. **Copy table** puts the same numbers on the clipboard for a spreadsheet. **Smooth** averages the view (and what Auto-detect searches) when a noisy average makes a peak hard to see; the raw trace stays drawn underneath it, and nothing smoothed is ever saved — markers are stored as positions on the real waveform. Scroll to zoom the time axis, `f` to fit it back.

**Apply & Close** transfers the marked waves onto the trace in the organizer, where they appear as labelled markers and are saved with the view. **Cancel** changes nothing. Re-opening a trace you have already marked brings those waves back into the table, so a second pass edits the first.

---

## Developer notes

### LivePlot

[mabr.ui.LivePlot](../+mabr/+ui/LivePlot.m) owns its figure, split into a **latest-sweep** axes across the top (with the correlation bar beside it) and, below, **one running mean per stimulus the current run is presenting**. It is passive — it draws whatever it is handed and holds no acquisition state:

```matlab
lp = mabr.ui.LivePlot();              % or LivePlot(parentContainer) to embed
lp.update(sweeps,tvec,R,target,bad,info);   % sweeps = [nSweeps x nSamples]
lp.reset();                           % clear between blocks
```

`sweeps` is the baseline and the response as one contiguous segment (`[pre post]` from [extract_sweeps](../+mabr/+metrics/extract_sweeps.m), whose fifth output `tvec` gives the matching time base in seconds) — pre-onset samples are what a negative time base has to draw. `info` carries the per-sweep stimulus identity:

| Field | Meaning |
| --- | --- |
| `.StimIndex` | `[1 x nSweeps]` the stimulus behind each sweep |
| `.Stimuli` | `[1 x nStim]` the stimuli this run presents |
| `.Labels` | `{1 x nStim}` fallback label for each — used where `.Params` cannot name the condition better |
| `.Params` | the stimuli's informative parameters, row-aligned with `.Stimuli`: `.Names {1 x nP}`, `.Values [nStim x nP]`, `.Varying (1 x nP)` (optional — computed from the values when absent), `.Units {1 x nP}` — exactly what [`StimulusSet.paramTable`](../+mabr/+stim/StimulusSet.m) returns |
| `.DetrendPoly`, `.SmoothSpan` | cosmetic post-processing of the means |

Omit `info` and every sweep counts as one condition, which is the old single-mean view. `AcqController.live_info` builds it from `Schedule.renderSpec`'s per-onset stimulus index — the same pairing `finalize_run` de-interleaves by, so a live panel and the block eventually saved for that stimulus contain the same sweeps.

### Multiple parameters

A bank almost never varies along one dimension — the ordinary ABR run is a Frequency × Level grid — and a list of means labelled `Tone_8000_30` in whatever order the schedule presented them is not a view of one. Given `info.Params` the view uses the parameters three ways:

* **Labels** come from the parameters the experiment varies — `8 kHz, 30 dB`, not the raw ID, and never a parameter that is the same everywhere in the bank. The scope is the **bank**, not the run: `AcqController.stimParams` tabulates the whole bank and takes the run's rows out of it, `Varying` and all, because a blocked run holds one condition and therefore varies nothing — deriving the answer from the run would leave a blocked run's single mean with no name but its ID. A blocked run's overlaid axes is titled with it (`8 kHz, 30 dB — mean of 512 sweeps`); with no parameters to name it, the title is the plain sweep count it always was.
* **Order** comes from those parameters too, group parameter first: a level series reads as a series wherever it is drawn, whatever order the sweeps arrived in. The means move with their labels — panel *k* holds stimulus *k*'s sweeps and nothing else, exactly as before.
* **Grouping** by one of them (`GroupBy`) gives each group a hue whose members ramp pale-to-full along the within-group parameter, so a series is visibly a series rather than seven unrelated colours — and it forms the columns of the two parameter-aware layouts.

`GroupBy` defaults to automatic: `Frequency` where the run varies one, otherwise the coarsest varying parameter (fewest distinct values, so a grid comes out wide and short). A run with only **one** varying parameter is deliberately left ungrouped — a single dimension is the series itself, and grouping by it would put every condition in a group of one. `'none'` switches grouping off; naming a parameter the run does not vary falls back to automatic rather than erroring. The **Group** menu in the control strip offers exactly this run's varying parameters and is disabled when there are none.

Without parameters nothing changes: the view is the ID-labelled, presentation-ordered list it always was.

Display settings are public properties, and the control strip along the bottom of the window writes exactly those — so a script can drive the view the same way the user can:

| Property | Default | Effect |
| --- | --- | --- |
| `Layout` | `'overlay'` | Means overlaid on one axes; `'separate'` — one small axes each, titled with its condition and running count; `'grid'` — one tile per condition, groups across columns and the within-group parameter up the rows, largest at the top (the live analogue of `plotABRGrid`), short columns bottom-aligned so a missing high level leaves a hole where it belongs; `'stacked'` — one axes per group, its conditions offset into a stack and named on the y axis, the y ticks doing the job a legend would |
| `GroupBy` | `''` (auto) | The stimulus parameter the conditions are grouped by, or `'none'`. See [Multiple parameters](#multiple-parameters) |
| `TimeBase` | `[-2 10]` ms | Displayed window, clamped to what was actually recorded |
| `AmpMode` | `'common'` | `'each'` (every stimulus to its own peak), `'common'` (one shared scale — the only way an amplitude difference between conditions is visible), `'manual'` |
| `ManualLimit` | `5e-6` V | The ± limit `'manual'` pins the mean axes to. Switching into Manual seeds it from what is on screen |
| `ErrorBand` | `'none'` | `'std'`, `'sem'`, or `'ci'` — a patch behind each mean, in its colour, from [error_band](../+mabr/+metrics/error_band.m). Chosen from the right-click menu. `'sem'`/`'ci'` widen the axes to fit; `'std'` does not (see above) |
| `ConfidenceLevel` | `0.95` | The level `'ci'` uses. The menu offers 90 / 99 as well; any value in (0,1) works from a script |

Overlaid means share an axes and therefore one scale, so `'each'` behaves as `'common'` there; in `'stacked'` the mode sets the offset between traces the same way, from the group's own largest response or the largest anywhere. Under `'each'` every tile keeps its y tick labels rather than only the left column — each is on its own scale, and hiding the numbers would leave a column of traces with no way to tell how big they are. The latest-sweep axes always autoscales, `'manual'` included: it is a single sweep, tens of times the size of a mean, and a limit chosen to frame the averages would clip it away entirely.

`AcqController.live_tick_body` calls `update` from a single ~20 Hz `timer` (`ExecutionMode` `fixedSpacing`, `BusyMode` `drop`), which is the only timer in the program. The tick body is wrapped in a try/catch so a transient draw error cannot kill the timer and freeze the live view. The axes are rebuilt only when the arrangement changes — the run's conditions, their labels, the grouping, or the layout — never on a plain refresh.

[tests/verify_live_plot.m](../tests/verify_live_plot.m) covers all of this without hardware.

Passing a container to the constructor embeds the plot rather than opening a figure, which is the hook for a docked or multi-panel UI.

### ProgressMonitor

[mabr.ui.ProgressMonitor](../+mabr/+ui/ProgressMonitor.m) owns a `uifigure` (or embeds in a container you pass) and follows either a controller or a bare plan:

```matlab
pm = mabr.ui.ProgressMonitor();     % or ProgressMonitor(parentContainer) to embed
pm.listenTo(controller);            % follow an AcqController
pm.attach(schedule,stimulusSet);    % or a plan with no controller behind it
pm.View = 'heatmap';                % 'simple' | 'bars' | 'heatmap'
```

`listenTo` re-points rather than stacking listeners, so re-opening the window (or rebuilding the controller) cannot double-count anything. The controller's `Schedule` is read on every refresh rather than held, because `setStimuli` *replaces* it.

The tally is deliberately computed from the plan rather than accumulated:

| Half | Source |
| --- | --- |
| planned | every presentation in `Schedule.Runs`, summed per stimulus — so make-up and repeat runs enlarge it |
| recorded | `Schedule.RunCounts`, written by the controller at finalization |
| in flight | the current run's sweep count paired against `Schedule.runSequence`, the same pairing `finalize_run` de-interleaves by |

Nothing is accumulated across events, so no missed or duplicated event can put the window out of step with the schedule — the worst a dropped repaint costs is a number that is briefly stale.

**Cost.** The window runs no timer. It rides the controller's existing ~20 Hz `MetricsUpdated` tick, repaints at most every `MinInterval` seconds (0.2 by default), and then only when the tallies actually changed; state changes and finished blocks force a repaint regardless. Nothing is created per refresh — the bars are two patches whose vertices are rewritten, the heat map one image whose `CData` is, the labels a fixed array of text objects. Layout is rebuilt only when the view, the grouping, or the plan itself changes.

The grouping dimensions come from `StimulusSet.meta` — the same `informativeParams` the offline pipeline groups by, so what the progress window calls a condition and what `batchABRAnalysis` calls one are the same thing.

### TraceOrganizer

[mabr.ui.TraceOrganizer](../+mabr/+ui/TraceOrganizer.m) manages an array of [mabr.ui.Trace](../+mabr/+ui/Trace.m) objects, each holding a waveform, time base, stimulus ID, label, colour, per-trace amplitude `Gain`, vertical offset, and its [Marker](../+mabr/+ui/Marker.m) objects.

```matlab
to = mabr.ui.TraceOrganizer();
to.addBlock(block);                    % a finalized mabr.data.Block
to.addTrace(data,time,label,stimID);   % or arbitrary data
to.markPeaks();
to.show();
```

Each trace is labelled on the plot with the stimulus ID `addBlock` reads from `block.Stim.Meta.ID`, falling back to the descriptive label when there is no stimulus metadata. Labels sit in the margin to the left of the axes, right-aligned against the y-axis at each trace's baseline, so they never obscure the waveforms; the margin widens automatically to fit the longest one.

To have the stack fill in during a run rather than only when reopened, point the organizer at a controller:

```matlab
to.listenTo(controller);   % adds a trace on every AcqController BlockReady
to.stopListening();        % detach
```

`listenTo` tracks one controller at a time — calling it again re-points the listener rather than stacking a second one, so re-opening the view cannot duplicate traces. The handler is wrapped in a try/catch: it runs on the acquisition path, so a plotting error must never propagate back into the controller mid-schedule. New blocks are drawn without raising the figure, so an auto-update cannot steal focus from the live view. `App` wires this up when it builds the Trace Organizer — on the first Start or Preview, or earlier if you open it from the toolbar — and re-points it whenever the controller is rebuilt.

Every command is reachable three ways — the menu bar, the right-click context menu, and the keyboard — so nothing is discoverable only by memorization; press `F1` in the figure for the shortcut list. Amplitude commands act on the current selection, or on every trace when nothing is selected. Click a trace or its label to select it, shift- or ctrl-click to extend.

| Key | Action |
| --- | --- |
| `Up` / `Down` | amplitude larger / smaller |
| `Shift+Up` / `Shift+Down` | spacing wider / narrower |
| `Ctrl+Up` / `Ctrl+Down` | move selected trace up / down the stack |
| `0` | reset amplitude to 1× |
| `n` | per-trace vs. common normalization |
| `r` | restack evenly in current visual order |
| `a` / `Esc` | select all / none |
| `l` | toggle stimulus ID labels |
| `p` / `c` | mark peaks / clear markers |
| `i` | inspect the selected trace (same as double-clicking it) |
| `h` / `Delete` | hide / remove selected |
| `Ctrl+S` / `Ctrl+O` | save / load the view |

`saveView` writes a `.torg` file (a MAT-file holding a `View` struct) containing the waveforms plus the complete display state — gains, offsets, stack order, colours, markers, spacing, normalization mode, and axis limits — so `loadView` reproduces the view exactly as it was saved. Older version-1 `.torg` files still load. Markers are stored as **sample indices** rather than plotted coordinates, so they follow their trace through rescaling, restacking, and a save/load round-trip.

```matlab
to.saveView('session1.torg');
to.loadView('session1.torg');          % restored exactly as saved
```

`addBlock` reads `block.ADC.SweepMean` and `block.ADC.TimeVector`, so any `mabr.data.Block` — including one loaded from disk with `mabr.data.io.importLegacy` — can be displayed. `SweepMean` averages only the sweeps that survived artifact rejection (`Recording.CleanSweepData`), so a trace here never carries one the acquisition threw out; a block whose sweeps were *all* rejected has no mean to draw and is skipped with a log message rather than stacked as an empty trace.

```matlab
to = mabr.ui.TraceOrganizer();
to.addBlock(mabr.data.io.importLegacy('SUBJ_ID_001_Frequency_8kHz_Level_60dB_....abr'));
to.show();
```

Interaction uses standard figure `WindowButtonMotionFcn`/`WindowButtonUpFcn`/`WindowKeyPressFcn` callbacks. The legacy version drove dragging through a `user32.dll` mouse hook and had a broken Group/Marker implementation; both are gone. `YSpacing` and `YScaling` set the stack separation and the fraction of it the largest waveform occupies; `NormalizeEach` switches between one common scale (amplitudes stay comparable across traces) and per-trace normalization.

`tests/verify_trace_organizer.m` covers the labelling, scaling, spacing, selection, marker, keyboard, menu, and save/load behaviour with no hardware.

### TraceInspector

[mabr.ui.TraceInspector](../+mabr/+ui/TraceInspector.m) is the measurement window behind the organizer's double-click. It takes a `mabr.ui.Trace` — the same handle the organizer holds — and an optional callback fired after the peaks are transferred:

```matlab
insp = mabr.ui.TraceInspector(to.Traces(2),@() to.refresh());   % auto-detects on open
insp.autoDetect();                     % recompute every enabled wave
insp.setWindow(1,1.0,2.0,'Peak');      % name-free window edit
insp.setWaveTime(1,1.4,true);          % place wave 1 at 1.4 ms, snapping
insp.nudgeWave(1,+2);                  % ...or a couple of samples later
disp(insp.results());                  % Wave / Latency_ms / Amplitude / Type
insp.apply();                          % transfer + close
```

`TraceOrganizer.onTraceClick` branches on the figure's `SelectionType` being `'open'` and **disarms the drag that the first click of the pair armed** — otherwise the trace follows the mouse while the inspector opens. The organizer keeps at most one inspector: re-opening on the same trace raises the existing window rather than discarding the peaks placed in it, opening another trace replaces it, and removing a trace closes the inspector that was editing it.

A wave is `Name` / `Enabled` / `TMin` / `TMax` (ms re onset — a `Recording`'s `TimeVector` starts at the onset, so the trace's own time base is already the right one) / `Type` / `Loc` (a sample index, `NaN` when unplaced). `autoDetect` ranks [find_peaks](../+mabr/+metrics/find_peaks.m) by **prominence** rather than taking the first hit, since inside a hand-drawn window the largest feature is the one meant; a window with no turning point at all falls back to the segment extremum rather than reporting nothing. **The constructor calls it too**, but only over `find([obj.Waves.Enabled] & isnan([obj.Waves.Loc]))` — waves still unplaced once `seedFromTrace` has restored whatever the trace already carries — so opening on a bare trace shows peaks with no button press, while nothing already picked is ever silently recomputed by an open. Calling `autoDetect()` yourself (the button, `a`) carries no such restriction and recomputes every enabled wave regardless of `Loc`, which is the intended way to re-find one after widening its window. `SmoothSpan` smooths the displayed trace and the detection together — picking a peak off one signal while showing another is a disagreement nobody catches until the numbers are wrong — with the raw trace still drawn under it.

Nothing reaches the trace until `apply()`, which calls `Trace.setMarkers` with the placed waves in temporal order plus their names, then fires the callback so the organizer redraws. Because markers are sample indices, they survive the organizer's rescaling and its `.torg` round-trip. Constructing an inspector on a trace that already carries markers **seeds the table from them**, matching by name, so a second pass edits the first. Search windows (never the picks) persist in the `MABR` pref group on apply.

`tests/verify_trace_inspector.m` covers detection, the fallback, click/drag/nudge placement, the smoothing guarantee, transfer-on-apply versus cancel, seeding, and the organizer wiring including the double-click itself — no hardware.
