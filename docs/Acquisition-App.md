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
 │  Bank [ ABR_tones.spl          v ][+][−][ Open…  ] │
 │   8 stimuli · stimgen (calibrated) [Demo][Design…] │
 └───────────────────────────────────────────────────┘
 ┌ Presentation ────────────────────────────────────┐
 │    Strategy  [ Conventional — one stimulus v ]    │
 │    Order by  [ Frequency     v ] [ As listed  v ] │
 │     then by  [ Level         v ] [ Descending v ] │
 │ Repetitions  [   512 ] [ Per stimulus…          ] │
 │  ISI / Rate  [ 47.39 ms ] [        21.10 Hz     ] │
 │              overlap! 60.0 ms stim                │
 │        8 runs (blocked) · 4096 presentations · ~4 min │
 └───────────────────────────────────────────────────┘
 ┌ Acquisition ─────────────────────────────────────┐
 │     Advance  [ Correlation Thr. v ] [ r ≥ 0.50 ]  │
 │   Artifacts  [ Voltage threshold v ] [ ± 100 mV ] │
 │              [x] Repeat sweeps lost to artifact   │
 │     Filters  10–3000 Hz + 60 Hz notch [ Filters… ]│
 └───────────────────────────────────────────────────┘
 ┌ Run ─────────────────────────────────────────────┐
 │  (o) Acquire   Sweeps: 128   r = 0.42  rejected: 3 │
 │  [ Start ] [ Preview ] [ Repeat ] [Loop] [ Pause ] [ Advance ] [ Abort ] │
 └───────────────────────────────────────────────────┘
 Saved SUBJ_ID_001_Frequency_8kHz_Level_30dB_....abr
```

Every panel shares one label-column width, so the fields line up along a single edge down the whole window. The gap above **Run** is a spacer that absorbs extra height, keeping the transport controls pinned to the bottom at any window size. The overlap warning and plan summary rows in **Presentation** are blank until they have something to say, but their space is reserved so nothing jumps when they appear.

## Session identity

**Subject ID** — Labels the session and forms the first part of every filename. If it contains digits they are used (`Rat42` → `SUBJ_ID_42`); if it is purely alphabetic the whole name is used. IDs already starting with `SUBJ` are left alone.

**Output** — Folder for `.abr` files, one per condition. **Browse…** opens a folder picker. The folder is created if it does not exist. Leave it empty to record without saving (blocks stay in memory for the Trace Organizer only).

## Stimulus

**Design…** — Opens the [stimgen](https://github.com/dstolz/stimgen) bank editor, the suggested way to build stimuli. Set a parameter to a vector (`Frequency = [8000 16000]`) and stimgen expands it into variants; each variant becomes one MABR stimulus. The window stays open and the button becomes **Adopt bank** — press it to bring the current bank into MABR, tweak, and adopt again as often as you like. Everything is regenerated at MABR's 192 kHz rate, so nothing is resampled.

The editor's **Play** and **Play All** go out through the rig — the device, output channel and sample rate in **Settings ▸ Audio Device**, as selected by the Hardware choice in **Settings ▸ stimgen Tools…** — so a calibrated stimulus is heard at its calibrated level. Its **Output** dropdown switches to the computer's speakers and back. In Test Mode, or with Hardware set to Offline, there is no device to play through: the editor stays on the speakers and the status line says why.

Greyed out with an explanatory tooltip if the stimgen submodule was never fetched — run `git submodule update --init` and restart.

**Open…** — Loads a bank from file: a stimgen `.spl`, or a `.mat` holding a struct array in which each entry is **one** stimulus (a `signal` and an `ID`; MABR finds it among the loaded variables). Fields are listed in [Extending MABR](Extending.md#the-stimulus-entry). The file dialog opens in the folder you last picked a bank from.

**Bank dropdown** — The banks you have loaded from files before, newest first, with the loaded one showing. **Picking a bank loads it.** **+** adds bank files to the list without loading them (several at once — lay out a protocol's banks ahead of time); **−** chooses entries to take off the list. Neither touches the files, and a bank that has gone missing drops off the list by itself when you pick it.

Note what neither contains: repetition counts, spacing, or ordering. Those are yours to choose here, per session, and are described below. A `.spl` does carry stimgen's own reps and ISI — MABR takes the reps as a starting value and ignores the rest.

**Demo** — Loads the built-in tone-pip grid (8 and 16 kHz × 30 and 60 dB). **Uncalibrated** — for testing the software and signal chain only.

The **Bank** field shows `(none loaded)` in red until stimuli are loaded, then the count, where they came from, and whether a calibration is behind them — `12 stimuli · stimgen (calibrated)`, green, or `12 stimuli · stimgen (uncalibrated)`, **amber**. Hover over it for when that calibration was measured, which is how to tell that the bank carries the one you meant. It sits in the field column rather than beside the buttons, so it reads as the panel's current value.

> **Without a calibration, levels are relative — not dB SPL.** dB SPL becomes a voltage *through* the calibration. With none loaded, stimgen would generate every stimulus at the same amplitude, so a bank asking for 30, 60, and 90 dB would be three identical sounds. MABR instead scales an uncalibrated bank **relative to its own loudest entry**: the top level plays at the bank's normalized amplitude and each lower one is attenuated by the right ratio, so level *differences* are correct while the absolute level is arbitrary. MABR warns when you adopt such a bank rather than blocking it — it is still useful for testing, and for anything that only needs relative levels — but do not report absolute thresholds from one. Calibrate under **Settings ▸ Calibration…**, then rebuild the bank.

## Presentation

**Strategy** — How the stimuli in the bank are combined:

| Setting | Behavior |
|---------|----------|
| Conventional — one stimulus per run | All repetitions of one stimulus, then all of the next, and so on — in the order the bank lists them, or the order **Order by** asks for (below) |
| Conventional — shuffled run order | The same, but which stimulus goes first is shuffled |
| Interleaved — cycles in the order below | One continuous run of repeated cycles through the bank, every cycle in the same order — the order the bank lists them in, or the order **Order by** asks for (below) |
| Interleaved random — each cycle shuffled | Repeated cycles through the bank, each cycle in its own random order |
| Fully shuffled — no cycles | One continuous run, every presentation shuffled with no cycle structure |
| Custom function… | The order your own function returns — see below |

The interleaved and fully shuffled strategies **intermix** stimuli within a single continuous run, which removes drift and order effects from the comparison between conditions. You still get one `.abr` file per stimulus: MABR knows which stimulus it played at every onset and separates the sweeps when it saves.

Shuffling only reorders — it never resamples. Every stimulus is presented exactly the number of times you asked for under any of the five built-in strategies, so the counts are identical whichever you pick; only the order changes.

**Custom strategies.** Picking **Custom function…** opens a file browser; choose a function that takes one context struct describing the design — the bank, the repetition counts, and the stimulus parameters as a table — and returns the stimulus indices to present, a vector for one run or a cell of vectors for several. MABR puts its folder on the path and checks it against the contract before accepting it, running it on a representative design with unequal repetition counts, so a malformed one is refused at selection rather than at Start. Once chosen it appears as `Custom: <name>` and is remembered by file in a saved configuration. Polarity is assigned for you, balanced across the whole plan exactly as the built-ins balance it. Copy [`+mabr/+stim/+strategy/custom_template.m`](../+mabr/+stim/+strategy/custom_template.m) — which is itself a useful strategy, one run per condition ordered loudest-first within each frequency — and see [Extending](Extending.md#ordering-presentations-yourself) for the full contract and more worked examples.

**Order by / then by** — The order the **Conventional** runs play in, or the order every **Interleaved** cycle walks the bank in. Pick a stimulus parameter — the dropdown offers the ones your bank actually varies, `Level` and `Frequency` for an ordinary tone grid — and a direction:

| Direction | The runs are played |
|-----------|---------------------|
| Ascending | from the lowest value of the parameter to the highest |
| Descending | from the highest to the lowest |
| As listed | grouped by value, the groups in the order the bank first lists them — nothing is sorted, so a frequency order you chose on purpose (most important first, say) is kept |

**then by** orders the runs *inside* each value of the first parameter, and is what most designs need on a bank that varies two things:

| Order by | then by | Runs, on an 8 / 16 kHz × 30 / 60 / 90 dB bank |
|----------|---------|-----------------------------------------------|
| Level, descending | *(Bank order)* | `8k·90  16k·90  8k·60  16k·60  8k·30  16k·30` — every frequency at the loudest level, then the next |
| Frequency, ascending | Level, descending | `8k·90  8k·60  8k·30  16k·90  16k·60  16k·30` — the threshold series: one frequency at a time, loudest first |
| Frequency, as listed | Level, descending | the same, with the frequencies in whatever order the bank lists them |

Starting loud is usually what a threshold series wants: the loud conditions respond visibly, so a dead electrode or a slipped ear plug shows up in the first minute rather than after twenty spent collecting noise near threshold.

Under **Interleaved** the same rows order each cycle rather than the runs. The two classic interleaved designs are two settings of them:

| Design | Order by | then by | One cycle, on the same bank |
|--------|----------|---------|-----------------------------|
| Ramp — levels within each frequency | Frequency, as listed | Level, ascending | `8k·30  8k·60  8k·90  16k·30  16k·60  16k·90` |
| Plateau — frequencies within each level | Level, ascending | *(Bank order)* | `8k·30  16k·30  8k·60  16k·60  8k·90  16k·90` |

These used to be two strategies of their own, *Interleaved ramp* and *Interleaved plateau*. A configuration saved with either one still loads: it selects **Interleaved** and sets the rows to that design's order.

Stimuli that tie on everything you chose keep the bank's order, whichever direction you sort in — reversing a direction reverses that parameter and nothing else. **Bank order** in the first row leaves the stimuli exactly as the bank lists them. Hover over the plan summary at the bottom of the panel to read the resulting run order (or, under Interleaved, one cycle) back before you press Start.

Both rows are greyed under every other strategy: the shuffled strategies decide their own order, and a custom function returns its own. Ordering never changes *what* is presented — every stimulus still gets its full repetition count. The choice is saved in a configuration and recalled next session; loaded against a bank that does not vary the parameter it names, that row simply falls back to **Bank order**.

**Repetitions** — How many times each stimulus is presented. The number field applies one value to every stimulus. **Per stimulus…** opens a small editor where you can either keep one value for the whole bank or give each stimulus its own count; it shows the running total and estimated acquisition time as you type. Stimuli with unequal counts drop out of the cycle once they are done, so the extra repetitions of the others stay spread out rather than clumping at the end.

**ISI / Rate** — The inter-stimulus interval, onset to onset. The two fields are two views of one number — edit either and the other follows. If the longest stimulus does not fit inside the interval, a red `overlap!` warning appears and the status line tells you the highest rate that would fit; MABR will still run, summing the overlap, but this is almost always a mistake.

**Plan summary** — The grey line below shows what the current settings actually buy: how many runs, how many presentations in total, and roughly how long it will take. Check it before pressing Start. Under the Conventional strategy its tooltip lists the runs in the order they will play.

## Acquisition settings

**Advance** — When to end a run early:

| Setting | Behavior |
|---------|----------|
| All Repetitions | Play every scheduled repetition |
| Correlation Threshold | Stop as soon as the online response correlation reaches the threshold, subject to a minimum sweep count |
| Custom… | Prompts for your own criterion `.m` file (see below) |

The threshold field (0 to 1, 0.5 is a reasonable starting point) is enabled for the correlation criterion and for a custom one, which reads it as `ctx.corrThreshold`.

**Custom criteria.** Picking **Custom…** opens a file browser; choose a function that takes one context struct and returns a single logical (`true` = stop the run). MABR puts its folder on the path and checks it against the contract before accepting it — a malformed function is refused at selection, not mid-run. Once chosen it appears in the dropdown as `Custom: <name>` and is remembered by file in a saved configuration. Copy [`+mabr/+stim/+advance/custom_template.m`](../+mabr/+stim/+advance/custom_template.m) to get the signature and available `ctx` fields right; see [Extending](Extending.md#defining-when-a-run-ends) for the full field list.

**Correlation early-stop is available for blocked strategies only.** When you pick an intermixed strategy the Advance control greys out: a correlation computed across mixed conditions is not meaningful, and stopping such a run would truncate whichever stimuli happened to fall last in the sequence, unbalancing the design. Those runs always play to completion.

**Artifacts** — How a sweep is judged contaminated, and what to do about one:

| Setting | Behavior |
|---------|----------|
| None — keep every sweep | No sweep is ever flagged |
| Voltage threshold | Flag a sweep if any sample leaves ±threshold (default ±100 mV) |
| RMS threshold | Flag a sweep if its RMS exceeds the threshold (default 30 mV) — catches sustained muscle noise a peak limit misses |

One threshold field serves both criteria, since they are alternatives; the caption beside the number says which one it belongs to, and each criterion remembers its own value as you switch. **Repeat sweeps lost to artifact** re-presents what was rejected in a make-up run appended to the end of the schedule, so every condition still reaches its requested count; leave it off to simply count the losses. Your choices are remembered across sessions.

A flagged sweep is **marked, never discarded** — the `.abr` file carries the whole recording plus an `IsArtifact` flag per sweep, so offline analysis can overrule the call. What flagging changes is everything *descriptive*: the sweep is left out of the displayed average, the metrics, and the SNR. The **rejected:** count beside the sweep counter in **Run** tallies the flags for the schedule so far.

**These three controls stay live while a schedule is running**, unlike everything above them. The criterion is only decided when a run is finalized, so changing it mid-session is a decision about the next block rather than an edit to the one in flight — which is what you want when an electrode starts drifting an hour in. The live plot previews the new rule immediately, so you can see whether the threshold you just typed is the one you meant; blocks already finalized keep the verdict they were judged under. Clearing **Repeat** mid-schedule also withdraws any make-up runs that were queued but not yet reached.

**Filters** — Digital filtering of the signal *as you view it*. The row shows the chain in force; **Filters…** opens a small window to change it:

| Control | Purpose |
|---------|---------|
| High pass | Removes DC offset, electrode drift, and slow movement artifact (default 10 Hz) |
| Low pass | Removes hiss and everything above the response band (default 3000 Hz) |
| Notch | Removes mains hum — 60 Hz here, set it to 50 Hz on a 50 Hz supply. The width is the −3 dB span; keep it narrow so it does not eat the response |
| Roll-off | Butterworth order shared by the high and low pass. Steeper is not better on a 10 ms sweep, and a steep IIR with a 10 Hz corner at 12 kHz is numerically fragile |

Each of the three is an independent switch — a rig rarely wants all three answered the same way. The plot shows the chain **as applied**: filtering is zero-phase (`filtfilt` runs it forwards and backwards), so the realized response is the squared magnitude and the corners read −6 dB rather than −3 dB. **Defaults** restores 10–3000 Hz with a 60 Hz notch. OK greys out on a chain that passes nothing, such as a high pass above the low pass.

**Saved `.abr` files always hold the raw, unfiltered trace.** The chain applies to the live plot, the trace organizer, and the sweep metrics (including the SNR and the artifact verdict) — never to the recorded samples. So there is no wrong moment to change it and nothing to undo: the filters are how you *look* at the data, and the offline pipeline is free to make entirely different choices from the same file. Your chain is remembered across sessions.

Like the artifact controls, **Filters… stays live while a schedule runs**. The live plot redraws through the new corners on its next refresh, and its caption names the chain, so a filtered view is never mistaken for the raw signal.

> **Testing with loopback?** The default 10–3000 Hz band is the ABR band. In loopback the "recording" is the stimulus itself — a tone pip far above that band — so the live traces will look empty until you widen or switch off the filters.

## Settings menu

**Audio Device (ASIO)…** opens a small dialog over the audio configuration:

**Testing (loopback, no hardware)** — Ticked by default. Runs the entire program with no audio device: the outgoing stimulus is fed back as the incoming recording, plus a trace of noise. Everything else behaves normally, including saving files. Checking it greys out the device dropdown, the channel fields, and **Test Device** below, since none of them matter when nothing is going to be opened. Untick for real recordings. Toggling this rebuilds the background worker.

**Device** — The ASIO device to open, or **(system default)**. **Refresh** re-queries the system for connected devices.

**Player ch. / Recorder ch.** — The `[signal timing]` output and input channel mapping.

**Microphone** — The input channel your calibration microphone is patched to. Deliberately separate from **Recorder ch.**: during acquisition that input carries an electrode, during calibration it carries a mic. Same device, different patchings, so two settings. Only calibration reads it — it can never affect a recording.

**Test Device** — Briefly opens the selected device and reports the sample rate it actually grants, so a mismatched ASIO driver is caught here rather than partway into a session. Disabled in Testing mode.

Like the acquisition viewers, this dialog's position and every value here are remembered across sessions. Unlike the artifact and filter controls, this menu item **locks for the duration of a schedule** — the worker's audio device is already open on whatever it was handed at Start.

**Calibration…** opens [stimgen](https://github.com/dstolz/stimgen)'s calibration window, pointed at *your* rig: it plays through the ASIO device and output channel set above, records from the **Microphone** channel, and measures at MABR's 192 kHz rate — the rate your stimuli are generated at. Calibrating through some other device would describe a signal chain your experiment never uses.

Measure a reference (a known level from a calibrator), then a tone sweep, then save a `.esgc` file. Load that calibration onto your stimuli in the stimgen designer and rebuild the bank; from then on dB SPL means dB SPL.

Also locked during a schedule, and for a harder reason than the audio settings: an ASIO device has exactly one owner, and while a schedule runs the acquisition worker is it. Note that the worker keeps the device open *between* runs too, to keep block-to-block latency down — so opening calibration quietly asks it to hand the device back. It takes the device again automatically on the next Start.

Calibration is greyed out in Testing mode (loopback would just measure the stimulus fed back to itself) and when the stimgen submodule is missing.

## Toolbar

Both viewers open automatically with the app and sit beside the main window, so the toolbar buttons normally just raise them; they rebuild a window only if you closed it.

Each button is drawn as what its window shows; hover for the tooltip if the pictogram is ambiguous.

| Button | Effect |
| --- | --- |
| a trace on axes | Raises the Live Plot. |
| three rising points on axes | Opens **another** Online Analysis window — one metric across the conditions, refreshed while the schedule runs. Not a raise: every press gives you a new one, so a second question does not cost you the first answer. |
| a stack of traces | Raises the Trace Organizer, refreshed with the conditions completed so far. |
| a loudspeaker | Opens the Stimulus Viewer on the loaded bank. |
| three part-filled bars | Opens the [Progress Monitor](Viewing-Data.md#progressmonitor) — how much of the schedule is done, and which conditions are still short. |
| **?** | Opens the [MABR wiki](https://github.com/dstolz/MABR/wiki) in a browser (same as **Help ▸ MABR Wiki**). |

All three viewers are described in [Viewing Data](Viewing-Data.md). Under **Stimulation only** the live-plot and analysis buttons are disabled along with the whole Acquisition panel: nothing is recorded, so there is nothing for either to show.

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
| **Repeat** | Queue one more full block of the stimulus that just finished |
| **Loop** | Present the run in progress again when it ends, and again after that, until Loop is switched off |
| **Pause** / **Resume** | Suspend playback in place, keeping the audio device open |
| **Advance** | End the current run now, save it, continue to the next |
| **Abort** | End the current run now, save it, halt the schedule |

Advance and Abort both save what was recorded. Neither discards data. Stopping an intermixed run early is allowed but leaves the conditions unbalanced — the stimuli late in the sequence will have fewer sweeps than the rest.

**Repeat** appends one more run of whichever stimulus the most recently completed block presented, at its originally scheduled repetition count, to the end of the plan — the same "append to the end" mechanism artifact make-up uses, just triggered by you instead of a rejected sweep. It is **available only for blocked strategies** (Blocked, or Blocked with shuffled run order): an intermixed run has no single stimulus to point at, so the button stays disabled for the whole run in that case. It lights up as soon as the first eligible block lands and stays available for the rest of the schedule — including after everything has finished, to add one more block before you move on — and it works whether or not the schedule is still running, exactly like the artifact and filter controls beside it.

**Loop** is a toggle, tinted amber while it is on. While it is on, the run in progress is presented again when it ends — and again after that, pass after pass — instead of the schedule moving on; switch it off and the pass that is playing finishes, then the schedule continues from the run that was next, exactly where it would have been. It can be switched on and off at any time: before Start (the first run is held), or mid-run (the run playing is held). It works under every strategy — for a blocked run that is one condition, for an intermixed run the whole intermixed run in the same order — and in stimulation-only mode, Test Mode and Preview.

- **Each pass is a run of its own**: finalized, saved as its own `.abr` file(s) (or `.stimlog`), credited to the schedule, and sent to the viewers, exactly like any other run. Repeats of a condition accumulate in the online analysis window rather than replacing each other.
- **The advance criterion still ends each pass** (a pass that reaches its sweep count or correlation threshold stops there) — and the pass is then presented again. It decides when a pass has enough, not when to leave the condition.
- **Advance still means advance**: it ends the pass and moves on to the next run — which, with Loop still on, is then held in its turn. **Abort** still halts the schedule.
- A pass of an artifact make-up run is a full run of that stimulus at its scheduled count, not another make-up-sized one.
- The progress window says `looping` and names each inserted pass `(loop)`; while Loop is on it quotes no time left or finish time, because a looping schedule has no end of its own.
- Loop is not saved in a configuration or between sessions: MABR always opens with it off.

Short passes of one condition can start within the same second — the resolution of the timestamp in a file name. No file is ever overwritten: a second file of an existing name is written as `…_2.abr` (then `_3`, …), and the log says so. See [Data Files](Data-Files.md#filenames).

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

`ensureController` rebuilds the controller when the Testing checkbox changes, since testing mode is fixed at Engine construction. It is also where the one-time `waitUntilReady(120)` handshake happens — the only bounded wait in the program, and the reason the first Start is slower than the rest. While a controller is being built, `mabr.ui.StartupDialog` covers the main window with a progress dialog naming the workers being started, a checklist of the startup steps, and the latest milestone; every message still reaches the status line too.

To build a different front end, subclass or ignore `App` entirely and drive `AcqController` directly; see [Extending MABR](Extending.md#building-a-different-front-end).
