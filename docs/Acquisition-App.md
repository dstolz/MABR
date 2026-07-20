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

**Load .mat…** — Loads a `.mat` file of pre-computed, calibrated blocks supplied by your external stimulus package. The file should contain a struct array of block specifications; MABR finds it in the loaded variables. Required fields per block are listed in [Extending MABR](Extending.md#supplying-stimuli).

**Test Stimulus** — Loads the built-in tone-pip grid (8 and 16 kHz × 30 and 60 dB, 256 sweeps each). **Uncalibrated** — for testing the software and signal chain only.

The label between the two buttons shows `(none loaded)` in red until a source is loaded, then the block count.

## Acquisition settings

**Testing (loopback, no hardware)** — On by default. Runs the entire program with no audio device: the outgoing stimulus is fed back as the incoming recording, plus a trace of noise. Everything else behaves normally, including saving files. Untick for real recordings. Toggling this rebuilds the background worker.

**Advance** — When to move to the next condition:

| Setting | Behavior |
|---------|----------|
| Number of Sweeps | Run each condition until the target sweep count is reached |
| Correlation Threshold | Stop as soon as the online response correlation reaches the threshold, subject to a minimum sweep count |

**Target / Thr** — Two number fields. The first is the target sweep count (used by both criteria — under the correlation criterion it still bounds how long a condition may run). The second is the correlation threshold, 0 to 1, and is only enabled when the correlation criterion is selected. 0.5 is a reasonable starting point.

## Viewers

**Show Live Plot** — Opens (or brings forward) the live view. Opened automatically when you press Start.

**Trace Organizer** — Opens the stacked comparison viewer with the conditions completed so far. Both are described in [Viewing Data](Viewing-Data.md).

## Status row

**Lamp and state label** — The current program state: Idle, PrepBlock, Acquire, BlockComplete, AdvanceBlock, SchedComplete, or Error.

**Sweeps** — Sweeps detected in the current condition so far.

**r** — The current online correlation, the same value the live plot's bar shows. Under the correlation criterion, the condition ends when this reaches your threshold.

**Status line** (bottom) — The most recent event: worker startup, files saved, errors.

## Transport

| Button | Effect |
|--------|--------|
| **Start** | Begin the schedule from the first condition |
| **Pause** / **Resume** | Suspend playback in place, keeping the audio device open |
| **Stop Block** | End the current condition now, save it, continue to the next |
| **Abort** | End the current condition now, save it, halt the schedule |

Stop Block and Abort both save what was recorded. Neither discards data.

## Closing

Closing the window shuts down the background acquisition worker and releases the audio device. If you close mid-recording, the condition in progress is not saved — use Abort first.

---

## Developer notes

[mabr.ui.App](../+mabr/+ui/App.m) is a programmatic `uifigure` and is deliberately dumb: it constructs an [AcqController](../+mabr/+ui/AcqController.m), forwards button presses to controller methods, and updates labels from controller events. It holds no acquisition state of its own and never touches the [Engine](../+mabr/+acq/Engine.m) or the ring buffer directly.

Layout lives in `createComponents` and is treated as generated code — a rewrite of the layout should not need to touch the callbacks. Logic lives in the `on*` callbacks and event handlers below it.

The four events the app listens for:

| Event | Payload | App response |
|-------|---------|--------------|
| `StateChanged` | `ProgStateEventData.State` | Lamp colour, state label, button enable states |
| `MetricsUpdated` | `.Info` = `numSweeps`, `corr` | Sweep and correlation labels |
| `BlockSaved` | `.Info.file` | Status line; adds the block to the Trace Organizer |
| `ScheduleComplete` | — | Status line; resets transport buttons |

`ensureController` rebuilds the controller when the Testing checkbox changes, since testing mode is fixed at Engine construction. It is also where the one-time `waitUntilReady(120)` handshake happens — the only bounded wait in the program, and the reason the first Start is slower than the rest.

To build a different front end, subclass or ignore `App` entirely and drive `AcqController` directly; see [Extending MABR](Extending.md#building-a-different-front-end).
