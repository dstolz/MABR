# Viewing Data

MABR has two viewers: a live plot for the condition being recorded now, and the Trace Organizer for comparing finished conditions. Both open with the app and are laid out beside the main window; the trace-on-axes and stacked-traces toolbar buttons raise them, and where you leave them is remembered across sessions.

## Live Plot

Opens with the app, and is raised by the trace-on-axes toolbar button or by pressing Start. Closing it discards the window; the button builds a fresh one.

**Latest sweep** — across the top, on its own axes: the most recent single sweep. A sanity check on the raw signal — if it is railing, flat, or dominated by 60 Hz, something is wrong with the electrodes or grounding. It turns **red** when that sweep was the one rejected. It keeps its own axes because a single sweep is tens of times the size of an average; sharing an axis would flatten the means below it. The title names the condition the sweep came from and the sweep count so far.

**Running means** — below it, one average per stimulus **the current run is presenting**, over the sweeps that passed the artifact criterion. This is the ABR taking shape: early on mostly noise, then the time-locked response emerges as the background flattens. A blocked run presents one stimulus, so there is one mean; an interleaved or shuffled run presents several at once, and each gets its own average rather than being pooled into one meaningless trace.

**Controls** — the strip along the bottom of the window:

- **Means: Overlaid / Separate** — all the averages on one axes (easiest for comparing them directly), or one small panel each, titled with its stimulus ID and running count (easiest when there are many, or when they differ hugely in size).
- **Time (ms)** — the displayed window, `-2` to `10` by default. Negative time is the pre-onset baseline, which is what tells you what "no response" looks like on this preparation today. Widening past what was recorded simply stops at the recorded edge.
- **Amplitude** — *Auto (each)* scales every stimulus to its own peak, which is what you want when levels differ by 40 dB; *Auto (shared)* holds them all to one scale, which is the only way an amplitude difference between conditions is visible; *Manual* pins the scale to a ± value you type, so it stops moving between refreshes. Overlaid means share an axis and so share a scale — *each* behaves as *shared* there. The latest-sweep axes always scales itself, Manual included.

**Artifact readout** — when sweeps are being rejected, a red `N rejected (x%)` appears in the top-left corner of the latest-sweep panel, and the count also accumulates in the Run panel's `rejected:` readout beside the sweep count. Nothing appears while every sweep is being kept. A rate climbing through a few percent usually means the preparation needs attention rather than more sweeps. What the live view shows is a *preview* of the criterion applied to the sweeps as they arrive; the recorded verdict is made when the condition finalizes, and only that one reaches the file.

**Correlation bar** — A single bar showing how reproducible the response currently is, on a 0–1 scale, with your threshold marked. It compares the split-half consistency of the response window against that of the pre-stimulus baseline, so it reflects genuine time-locked signal rather than sweeps merely looking alike. When the bar reaches the marked threshold, the correlation advance criterion fires and the condition ends.

The plot refreshes about 20 times per second and resets at the start of each condition.

## Trace Organizer

Opens with the app, and is raised by the stacked-traces toolbar button. Closing it only disposes the window — the traces are kept, and the button brings them back. It stacks the mean waveform of every completed condition on one time axis so you can read a series — usually a level series at one frequency — as a whole.

**What you can do:**

- **Drag a trace vertically** to reorder or separate the stack. Click and drag; release to drop.
- **Mark peaks** — **Peaks ▸ Mark peaks** (or the ▼-over-a-peak toolbar button, or `p`) finds and labels response peaks on the selected trace, for identifying waves I–V.
- **Save / load** the arrangement, so a figure you have laid out can be recovered later.

Traces are labeled with their stimulus parameters and coloured in sequence. Time is shown in milliseconds relative to sweep onset.

Reading a level series: as level decreases, the response amplitude shrinks and its peaks shift later. The lowest level at which a repeatable waveform is still visible is the visually-determined threshold. For an objective, statistically-defined threshold across a whole study, use the offline pipeline — see [Offline Analysis](Offline-Analysis.md).

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
| `.Stimuli` | `[1 x nStim]` the stimuli this run presents, in layout order |
| `.Labels` | `{1 x nStim}` display label for each |
| `.DetrendPoly`, `.SmoothSpan` | cosmetic post-processing of the means |

Omit `info` and every sweep counts as one condition, which is the old single-mean view. `AcqController.live_info` builds it from `Schedule.renderSpec`'s per-onset stimulus index — the same pairing `finalize_run` de-interleaves by, so a live panel and the block eventually saved for that stimulus contain the same sweeps.

Display settings are public properties, and the control strip along the bottom of the window writes exactly those — so a script can drive the view the same way the user can:

| Property | Default | Effect |
| --- | --- | --- |
| `Layout` | `'overlay'` | Means overlaid on one axes, or `'separate'` — one small axes each, titled with its stimulus ID and running count |
| `TimeBase` | `[-2 10]` ms | Displayed window, clamped to what was actually recorded |
| `AmpMode` | `'common'` | `'each'` (every stimulus to its own peak), `'common'` (one shared scale — the only way an amplitude difference between conditions is visible), `'manual'` |
| `ManualLimit` | `5e-6` V | The ± limit `'manual'` pins the mean axes to. Switching into Manual seeds it from what is on screen |

Overlaid means share an axes and therefore one scale, so `'each'` behaves as `'common'` there. The latest-sweep axes always autoscales, `'manual'` included: it is a single sweep, tens of times the size of a mean, and a limit chosen to frame the averages would clip it away entirely.

`AcqController.live_tick_body` calls `update` from a single ~20 Hz `timer` (`ExecutionMode` `fixedSpacing`, `BusyMode` `drop`), which is the only timer in the program. The tick body is wrapped in a try/catch so a transient draw error cannot kill the timer and freeze the live view. The axes are rebuilt only when the run's stimulus list or the layout changes, never on a plain refresh.

[tests/verify_live_plot.m](../tests/verify_live_plot.m) covers all of this without hardware.

Passing a container to the constructor embeds the plot rather than opening a figure, which is the hook for a docked or multi-panel UI.

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
