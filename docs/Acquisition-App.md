# The Acquisition App

Reference for every control in the main MABR window. For the intended path through them, read [Getting Started](Getting-Started.md) first.

Open it with `>> MABR`, or `>> mabr.ui.App` if the path is already set.

## Layout

Under the toolbar, the window is five titled panels stacked top to bottom in the order you work through them: **Session** (who and where), **Stimulus** (what to play), **Presentation** (how to order it), **Acquisition** (when to stop), and **Run**. A status line sits at the very bottom.

```
 [L] [T] | [?]
 ┌ Session ─────────────────────────────────────────┐
 │  Subject ID  [ SUBJ_ID_001                    v ] │
 │      Output  [ C:\data\subj001    v ] [ Browse… ] │
 └───────────────────────────────────────────────────┘
 ┌ Stimulus ────────────────────────────────────────┐
 │        Bank   8 stimuli  [ Load .mat… ] [ Test ]  │
 └───────────────────────────────────────────────────┘
 ┌ Presentation ────────────────────────────────────┐
 │    Strategy  [ Blocked — one stimulus per run  v ] │
 │ Repetitions  [   512 ] [ Per stimulus…          ] │
 │  ISI / Rate  [ 47.39 ms ] [        21.10 Hz     ] │
 │              overlap! 60.0 ms stim                │
 │        8 runs (blocked) · 4096 presentations · ~4 min │
 └───────────────────────────────────────────────────┘
 ┌ Acquisition ─────────────────────────────────────┐
 │  [x] Testing (loopback, no hardware)              │
 │     Advance  [ Correlation Thr. v ] [ r ≥ 0.50 ]  │
 └───────────────────────────────────────────────────┘
 ┌ Run ─────────────────────────────────────────────┐
 │  (o) Acquire       Sweeps: 128           r = 0.42 │
 │  [ Start ] [ Pause ] [ Stop Run ] [ Abort ]       │
 └───────────────────────────────────────────────────┘
 Saved SUBJ_ID_001_Frequency_8kHz_Level_30dB_....abr
```

Every panel shares one label-column width, so the fields line up along a single edge down the whole window. The gap above **Run** is a spacer that absorbs extra height, keeping the transport controls pinned to the bottom at any window size. The overlap warning and plan summary rows in **Presentation** are blank until they have something to say, but their space is reserved so nothing jumps when they appear.

## Session identity

**Subject ID** — Labels the session and forms the first part of every filename. If it contains digits they are used (`Rat42` → `SUBJ_ID_42`); if it is purely alphabetic the whole name is used. IDs already starting with `SUBJ` are left alone.

**Output** — Folder for `.abr` files, one per condition. **Browse…** opens a folder picker. The folder is created if it does not exist. Leave it empty to record without saving (blocks stay in memory for the Trace Organizer only).

## Stimulus

**Load .mat…** — Loads a `.mat` file of pre-computed, calibrated stimuli supplied by your external stimulus package. The file should contain a struct array in which each entry is **one** stimulus — a `signal` and an `ID`. MABR finds it among the loaded variables. Fields are listed in [Extending MABR](Extending.md#the-stimulus-entry).

Note what the file does *not* contain: repetition counts, spacing, or ordering. Those are yours to choose here, per session, and are described below.

**Test Stimulus** — Loads the built-in tone-pip grid (8 and 16 kHz × 30 and 60 dB). **Uncalibrated** — for testing the software and signal chain only.

The **Bank** field shows `(none loaded)` in red until stimuli are loaded, then the stimulus count in green. It sits in the field column rather than beside the buttons, so it reads as the panel's current value.

## Presentation

**Strategy** — How the stimuli in the bank are combined:

| Setting | Behavior |
|---------|----------|
| Blocked — one stimulus per run | All repetitions of the first stimulus, then all of the second, and so on |
| Blocked, shuffled run order | The same, but which stimulus goes first is shuffled |
| Interleaved — A B C A B C … | One continuous run cycling through every stimulus |
| Interleaved, shuffled each cycle | The same, with each cycle's order shuffled independently |
| Fully shuffled | One continuous run, every presentation shuffled |

The last three **intermix** stimuli within a single continuous run, which removes drift and order effects from the comparison between conditions. You still get one `.abr` file per stimulus: MABR knows which stimulus it played at every onset and separates the sweeps when it saves.

Shuffling only reorders — it never resamples. Every stimulus is presented exactly the number of times you asked for under any of the five strategies, so the counts are identical whichever you pick; only the order changes.

**Repetitions** — How many times each stimulus is presented. The number field applies one value to every stimulus. **Per stimulus…** opens a small editor where you can either keep one value for the whole bank or give each stimulus its own count; it shows the running total and estimated acquisition time as you type. Stimuli with unequal counts drop out of the cycle once they are done, so the extra repetitions of the others stay spread out rather than clumping at the end.

**ISI / Rate** — The inter-stimulus interval, onset to onset. The two fields are two views of one number — edit either and the other follows. If the longest stimulus does not fit inside the interval, a red `overlap!` warning appears and the status line tells you the highest rate that would fit; MABR will still run, summing the overlap, but this is almost always a mistake.

**Plan summary** — The grey line below shows what the current settings actually buy: how many runs, how many presentations in total, and roughly how long it will take. Check it before pressing Start.

## Acquisition settings

**Testing (loopback, no hardware)** — On by default. Runs the entire program with no audio device: the outgoing stimulus is fed back as the incoming recording, plus a trace of noise. Everything else behaves normally, including saving files. Untick for real recordings. Toggling this rebuilds the background worker.

**Advance** — When to end a run early:

| Setting | Behavior |
|---------|----------|
| All Repetitions | Play every scheduled repetition |
| Correlation Threshold | Stop as soon as the online response correlation reaches the threshold, subject to a minimum sweep count |

The threshold field (0 to 1, 0.5 is a reasonable starting point) is enabled only when the correlation criterion is selected.

**Correlation early-stop is available for blocked strategies only.** When you pick an intermixed strategy the Advance control greys out: a correlation computed across mixed conditions is not meaningful, and stopping such a run would truncate whichever stimuli happened to fall last in the sequence, unbalancing the design. Those runs always play to completion.

## Toolbar

Both viewers open automatically with the app and sit beside the main window, so the toolbar buttons normally just raise them; they rebuild a window only if you closed it.

| Button | Effect |
| --- | --- |
| **L** | Raises the Live Plot. |
| **T** | Raises the Trace Organizer, refreshed with the conditions completed so far. |
| **?** | Opens the [MABR wiki](https://github.com/dstolz/MABR/wiki) in a browser (same as **Help ▸ MABR Wiki**). |

Both viewers are described in [Viewing Data](Viewing-Data.md).

Where you drag the two viewer windows is remembered across sessions ([mabr.ui.WindowPos](../+mabr/+ui/WindowPos.m) stores each position in MATLAB prefs under group `MABR`). A remembered position is clamped back onto the current display before it is applied, so unplugging a monitor cannot strand a window off-screen. The first time you run MABR they are laid out to the right of the main window: the Trace Organizer beside it, the Live Plot beyond that.

The toolbar is never disabled — raising a viewer is safe at any time, including while the engine is starting up.

## Status row

**Lamp and state label** — The current program state: Idle, PrepBlock, Acquire, BlockComplete, AdvanceBlock, SchedComplete, or Error.

**Sweeps** — Sweeps detected in the current run so far. In an intermixed run this counts every presentation, not one condition's share.

**r** — The current online correlation, the same value the live plot's bar shows. Under the correlation criterion, the run ends when this reaches your threshold. In an intermixed run it is shown for information only and never stops the run.

**Status line** (bottom) — The most recent event: worker startup, files saved, errors.

## Transport

| Button | Effect |
|--------|--------|
| **Start** | Begin the schedule from the first run |
| **Pause** / **Resume** | Suspend playback in place, keeping the audio device open |
| **Stop Run** | End the current run now, save it, continue to the next |
| **Abort** | End the current run now, save it, halt the schedule |

Stop Run and Abort both save what was recorded. Neither discards data. Stopping an intermixed run early is allowed but leaves the conditions unbalanced — the stimuli late in the sequence will have fewer sweeps than the rest.

## Closing

Closing the window shuts down the background acquisition worker and releases the audio device. If you close mid-recording, the run in progress is not saved — use Abort first.

---

## Developer notes

[mabr.ui.App](../+mabr/+ui/App.m) is a programmatic `uifigure` and is deliberately dumb: it constructs an [AcqController](../+mabr/+ui/AcqController.m), forwards button presses to controller methods, and updates labels from controller events. It holds no acquisition state of its own and never touches the [Engine](../+mabr/+acq/Engine.m) or the ring buffer directly.

It does own the **presentation settings** — the stimulus bank, per-stimulus repetition counts, strategy, and ISI — because those are experiment design, not acquisition state. `buildSchedule` is the single place that turns them into a [Schedule](../+mabr/+stim/Schedule.m); both the live plan-summary preview and `onStart` go through it, so the preview cannot drift from what actually runs.

[mabr.ui.RepetitionsDialog](../+mabr/+ui/RepetitionsDialog.m) is a self-contained modal returning a repetition vector (or `[]` on cancel). It is a plain function, not a class — it holds no state beyond the window's lifetime.

Layout lives in `createComponents` and the `build*Panel` methods below it, kept strictly separate from behaviour — a rewrite of the layout should not need to touch the callbacks. Each panel is built by the shared `panelGrid(title,row,rowHeights,colWidths)` helper, and all of them use the `LabelWidth` constant for their first column, which is what keeps the fields aligned across panel borders. Panels need explicit pixel heights: `uigridlayout`'s `'fit'` does not measure through a `uipanel` into its nested grid. Logic lives in the `on*` callbacks and event handlers below it. `syncAdvanceEnables` is deliberately separate from `onStrategyChanged`: `transport()` calls it too, and it must not write to the status line there.

The events the app listens for:

| Event | Payload | App response |
|-------|---------|--------------|
| `StateChanged` | `ProgStateEventData.State` | Lamp colour, state label, button enable states |
| `MetricsUpdated` | `.Info` = `numSweeps`, `corr` | Sweep and correlation labels |
| `BlockReady` | `.Info.block` | Not handled by `App` — the Trace Organizer subscribes to it directly (see below) |
| `BlockSaved` | `.Info.file` | Status line. Fires once per stimulus recovered from the run, so an intermixed run raises it several times |
| `ScheduleComplete` | — | Status line; resets transport buttons |

`BlockReady` and `BlockSaved` both fire once per stimulus recovered from the run, but they are not interchangeable: `BlockReady` carries the finalized `mabr.data.Block` and fires whether or not the session is writing files, while `BlockSaved` carries only a path and is skipped entirely when the `Session` has no `OutputPath`. Anything that needs the *data* listens to `BlockReady`.

Rather than the app pushing traces into the viewer, `onTraceOrg` hands the controller to `TraceOrganizer.listenTo`, and the organizer adds each block itself as it lands — so a view left open during a run fills in live. Opening the organizer re-points the listener instead of adding a second one, and `ensureController` re-points it again when the controller is rebuilt, so neither action can duplicate traces or leave the view attached to a deleted controller.

`ensureController` rebuilds the controller when the Testing checkbox changes, since testing mode is fixed at Engine construction. It is also where the one-time `waitUntilReady(120)` handshake happens — the only bounded wait in the program, and the reason the first Start is slower than the rest.

To build a different front end, subclass or ignore `App` entirely and drive `AcqController` directly; see [Extending MABR](Extending.md#building-a-different-front-end).
