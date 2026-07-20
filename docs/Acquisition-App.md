# The Acquisition App

Reference for every control in the main MABR window. For the intended path through them, read [Getting Started](Getting-Started.md) first.

Open it with `>> MABR`, or `>> mabr.ui.App` if the path is already set.

## Layout

The window is a single column of controls, top to bottom: session identity, stimulus, acquisition settings, viewers, status, and transport buttons.

```
 Subject ID  [ SUBJ_ID_001                          ]
 Output      [ C:\data\subj001          ] [ Browse… ]
 Stimulus     8 blocks     [ Load .mat… ] [ Test Stimulus ]
 [x] Testing (loopback, no hardware)
 Advance     [ Number of Sweeps                   v ]
 Target/Thr  [ 256    ] [ 0.50 ]
 [ Show Live Plot        ] [ Trace Organizer       ]
 (o) Acquire      Sweeps: 128      r = 0.42
 [ Start ] [ Pause ] [ Stop Block ] [ Abort ]
 Saved SUBJ_ID_001_Frequency_8kHz_Level_30dB_....abr
```

## Session identity

**Subject ID** — Labels the session and forms the first part of every filename. If it contains digits they are used (`Rat42` → `SUBJ_ID_42`); if it is purely alphabetic the whole name is used. IDs already starting with `SUBJ` are left alone.

**Output** — Folder for `.abr` files, one per condition. **Browse…** opens a folder picker. The folder is created if it does not exist. Leave it empty to record without saving (blocks stay in memory for the Trace Organizer only).

## Stimulus

**Load .mat…** — Loads a `.mat` file of pre-computed, calibrated stimuli supplied by your external stimulus package. The file should contain a struct array in which each entry is **one** stimulus — a `signal` and an `ID`. MABR finds it among the loaded variables. Fields are listed in [Extending MABR](Extending.md#the-stimulus-entry).

Note what the file does *not* contain: repetition counts, spacing, or ordering. Those are yours to choose here, per session, and are described below.

**Test Stimulus** — Loads the built-in tone-pip grid (8 and 16 kHz × 30 and 60 dB). **Uncalibrated** — for testing the software and signal chain only.

The label between the two buttons shows `(none loaded)` in red until stimuli are loaded, then the stimulus count.

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

## Viewers

**Show Live Plot** — Opens (or brings forward) the live view. Opened automatically when you press Start.

**Trace Organizer** — Opens the stacked comparison viewer with the conditions completed so far. Both are described in [Viewing Data](Viewing-Data.md).

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

Layout lives in `createComponents` and is treated as generated code — a rewrite of the layout should not need to touch the callbacks. Logic lives in the `on*` callbacks and event handlers below it. `syncAdvanceEnables` is deliberately separate from `onStrategyChanged`: `transport()` calls it too, and it must not write to the status line there.

The four events the app listens for:

| Event | Payload | App response |
|-------|---------|--------------|
| `StateChanged` | `ProgStateEventData.State` | Lamp colour, state label, button enable states |
| `MetricsUpdated` | `.Info` = `numSweeps`, `corr` | Sweep and correlation labels |
| `BlockSaved` | `.Info.file` | Status line; adds the block to the Trace Organizer. Fires once per stimulus recovered from the run, so an intermixed run raises it several times |
| `ScheduleComplete` | — | Status line; resets transport buttons |

`ensureController` rebuilds the controller when the Testing checkbox changes, since testing mode is fixed at Engine construction. It is also where the one-time `waitUntilReady(120)` handshake happens — the only bounded wait in the program, and the reason the first Start is slower than the rest.

To build a different front end, subclass or ignore `App` entirely and drive `AcqController` directly; see [Extending MABR](Extending.md#building-a-different-front-end).
