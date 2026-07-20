# Viewing Data

MABR has two viewers: a live plot for the condition being recorded now, and the Trace Organizer for comparing finished conditions.

## Live Plot

Opens automatically when you press Start, or via **Show Live Plot**.

Two panels:

**Trace panel** — Two waveforms over the response window:

- **Black** — the running average of every sweep collected so far in this condition. This is the ABR taking shape. Early on it is mostly noise; as sweeps accumulate the time-locked response emerges and the background flattens.
- **Blue** — the most recent single sweep, shown faintly. Useful as a sanity check on the raw signal: if it is railing, flat, or dominated by 60 Hz, something is wrong with the electrodes or grounding.

The title shows the sweep count and, when using the correlation criterion, the current correlation. The vertical scale adapts automatically and the units are labeled.

**Correlation bar** — A single bar showing how reproducible the response currently is, on a 0–1 scale, with your threshold marked. It compares the split-half consistency of the response window against that of the pre-stimulus baseline, so it reflects genuine time-locked signal rather than sweeps merely looking alike. When the bar reaches the marked threshold, the correlation advance criterion fires and the condition ends.

The plot refreshes about 20 times per second and resets at the start of each condition.

## Trace Organizer

Opens via **Trace Organizer**. It stacks the mean waveform of every completed condition on one time axis so you can read a series — usually a level series at one frequency — as a whole.

**What you can do:**

- **Drag a trace vertically** to reorder or separate the stack. Click and drag; release to drop.
- **Mark peaks** — the toolbar's peak-marking action finds and labels response peaks on the selected trace, for identifying waves I–V.
- **Save / load** the arrangement, so a figure you have laid out can be recovered later.

Traces are labeled with their stimulus parameters and coloured in sequence. Time is shown in milliseconds relative to sweep onset.

Reading a level series: as level decreases, the response amplitude shrinks and its peaks shift later. The lowest level at which a repeatable waveform is still visible is the visually-determined threshold. For an objective, statistically-defined threshold across a whole study, use the offline pipeline — see [Offline Analysis](Offline-Analysis.md).

---

## Developer notes

### LivePlot

[mabr.ui.LivePlot](../+mabr/+ui/LivePlot.m) owns its figure and two axes. It is passive — it draws whatever it is handed and holds no acquisition state:

```matlab
lp = mabr.ui.LivePlot();              % or LivePlot(parentContainer) to embed
lp.update(postSweep,tvec,R,target);   % postSweep = [nSweeps x nSamples]
lp.reset();                           % clear between blocks
```

`AcqController.live_tick_body` calls `update` from a single ~20 Hz `timer` (`ExecutionMode` `fixedSpacing`, `BusyMode` `drop`), which is the only timer in the program. The tick body is wrapped in a try/catch so a transient draw error cannot kill the timer and freeze the live view.

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

Each trace is labelled on the plot with the stimulus ID `addBlock` reads from `block.Stim.Meta.ID`, falling back to the descriptive label when there is no stimulus metadata.

To have the stack fill in during a run rather than only when reopened, point the organizer at a controller:

```matlab
to.listenTo(controller);   % adds a trace on every AcqController BlockReady
to.stopListening();        % detach
```

`listenTo` tracks one controller at a time — calling it again re-points the listener rather than stacking a second one, so re-opening the view cannot duplicate traces. The handler is wrapped in a try/catch: it runs on the acquisition path, so a plotting error must never propagate back into the controller mid-schedule. New blocks are drawn without raising the figure, so an auto-update cannot steal focus from the live view. `App` wires this up when you open the Trace Organizer.

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

`addBlock` reads `block.ADC.SweepMean` and `block.ADC.TimeVector`, so any `mabr.data.Block` — including one loaded from disk with `mabr.data.io.importLegacy` — can be displayed:

```matlab
to = mabr.ui.TraceOrganizer();
to.addBlock(mabr.data.io.importLegacy('SUBJ_ID_001_Frequency_8kHz_Level_60dB_....abr'));
to.show();
```

Interaction uses standard figure `WindowButtonMotionFcn`/`WindowButtonUpFcn`/`WindowKeyPressFcn` callbacks. The legacy version drove dragging through a `user32.dll` mouse hook and had a broken Group/Marker implementation; both are gone. `YSpacing` and `YScaling` set the stack separation and the fraction of it the largest waveform occupies; `NormalizeEach` switches between one common scale (amplitudes stay comparable across traces) and per-trace normalization.

`tests/verify_trace_organizer.m` covers the labelling, scaling, spacing, selection, marker, keyboard, menu, and save/load behaviour with no hardware.
