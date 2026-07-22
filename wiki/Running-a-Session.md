# Running a Session

Launch with `MABR` from the MATLAB command window. The window is `mabr.ui.App`.

## The control panel, top to bottom

**Subject ID** — editable dropdown. Free text is allowed; the ten most recently used IDs are remembered across sessions in MATLAB prefs. Drives the `SUBJ_ID_…` part of the output filename (see [[Data Format]]).

**Output** — editable dropdown plus **Browse…**. Where `.abr` files are written. Also remembered.

**Stimulus** — **Design…** opens the stimgen bank editor and then becomes **Adopt bank** (`mabr.stim.fromStimgen`); **Load bank…** reads a bank from file, `.spl` or `.mat` (`mabr.stim.StimulusSet.fromFile`); **Demo** loads the built-in tone-pip bank. Until one is loaded the label reads `(none loaded)` in red; afterwards it shows the count and source (`12 stimuli · stimgen`), amber when the bank is uncalibrated. See [[Using stimgen]] and [[Stimulus Package Contract]].

**Strategy** — how entries in the bank are combined into runs. See [[Presentation Strategies]].

**Repetitions** — one value applied to the whole bank, or **Per stimulus…** to open `mabr.ui.RepetitionsDialog` for a per-entry vector (with a live total and duration estimate; cancel returns `[]` and changes nothing). Loading a bank resets these to whatever the bank suggests — its own `Repetitions` field, else 512.

**ISI / Rate** — two linked fields; editing either updates the other. ISI is onset-to-onset in ms, rate in Hz. Default 21.1 Hz. If the longest stimulus does not fit inside the ISI, a red warning appears — overlapping presentations are **summed**, not clipped, and the fact is logged.

**Advance** — the criterion that ends a run:
- *All Repetitions* — play the full train (`mabr.stim.advance.num_sweeps`).
- *Correlation Threshold* — stop early once the running onset-contrast correlation reaches the value in the adjacent field (default 0.5), after a minimum sweep count (`mabr.stim.advance.corr_threshold`).

This control is **greyed out and forced to *All Repetitions* for intermixed strategies** — stopping a run that pools different conditions would truncate whichever stimuli fell last, unbalancing the design.

**Plan summary** — a live preview of runs, total presentations, and estimated wall-clock duration. It and Start both go through the same `buildSchedule`, so what you preview is what you run.

**Show Live Plot** — opens `mabr.ui.LivePlot`, refreshed by a single ~20 Hz timer: the most recent sweep on its own axes at the top with the correlation bar beside it, and below it one running mean per stimulus the current run is presenting — overlaid on one axes or one panel each. The control strip along the bottom sets the layout, the time base (default −2 to 10 ms, the negative half being the pre-onset baseline), and how the means are scaled (each to its own peak, all to one shared scale, or a manual ± limit).

**Trace Organizer** — opens `mabr.ui.TraceOrganizer`, the interactive stacked-waveform viewer. Each acquired block appears as one trace labelled with its stimulus ID, and the view keeps up on its own — leave it open during a run and a new trace appears as each block completes, without stealing focus from the live view. Resize individual traces, the selection, or all of them, adjust the stack spacing, reorder and mark peaks — from the menu bar, the right-click menu, or the keyboard (`F1` lists the shortcuts) — then save the arranged view to a `.torg` file and reload it exactly as it was.

**Settings ▸ Audio Device (ASIO)…** — opens `mabr.ui.AudioSettingsDialog`, edited over `mabr.AudioSettings`: **Testing (loopback, no hardware)** (checked by default — runs the whole engine with no audio device; unchecking it enables the rest of the dialog), the ASIO **Device**, the **Player/Recorder** `[signal timing]` channel mapping, and the **Microphone** input channel used by calibration only. Toggling Testing or changing the device rebuilds the worker. Locked for the duration of a schedule.

**Settings ▸ Calibration…** — opens stimgen's calibration GUI over `mabr.stim.CalibrationAdapter`, so the measurement runs on this rig's device, output channel, and mic channel at the DAC rate. Locked during a schedule and unavailable in Testing mode; borrows the audio device from the idle worker (`Engine.releaseDevice`), which retakes it on the next Start. See [[Using stimgen]].

## Transport

| Button | Effect |
| --- | --- |
| **Start** | Builds the schedule and begins the first run. First start is slow — the parallel pool and worker handshake take tens of seconds; progress appears in the status line. |
| **Pause** | Suspends streaming; the worker stays warm. |
| **Advance** | Ends the current run early and saves it, then advances to the next. |
| **Abort** | Ends the whole schedule. |

The lamp, state label, sweep count, and `r =` correlation readout track the controller's `mabr.ui.ProgState` (Idle → PrepBlock → Acquire → BlockComplete → AdvanceBlock → SchedComplete, or Error). The whole path is event-driven — no busy-waits.

Starting again while a worker is already running in the same mode **reuses** it rather than paying pool-startup cost twice.

## What gets saved

At the end of each run, `AcqController.finalize_run` **de-interleaves** it: recorded onsets are paired against `Schedule.runSequence`, and one `mabr.data.Block` plus one `.abr` file is emitted **per stimulus present in that run**. The on-disk unit is therefore always one file per condition, regardless of how the run was ordered.

- A homogeneous (blocked) run saves the continuous recorded trace.
- An intermixed run saves each stimulus's sweep windows concatenated (`compact_sweeps`) rather than N copies of one shared trace.

## Logging

Code logs through `mabr.log.vprintf(level, [red], fmt, ...)`, gated on the global `GVerbosity` (-1 … 3). `mabr.log.vprintf(0,1,...)` prints a critical message in red. Log output also goes to `.error_logs/`.

```matlab
global GVerbosity
GVerbosity = 3;   % maximum detail
```
