# Troubleshooting

First step for almost anything: turn up the logger.

```matlab
global GVerbosity
GVerbosity = 3;      % -1 … 3
```

Output also goes to `.error_logs/` under the repository root (`mabr.Config.errorLogDir`).

## Startup

**`MABR:windowsOnly`** — MABR is Windows-only; `MABR.m` warns and returns.

**`mabr:Config:missingToolboxes`** — the error lists each missing toolbox and the minimum version. All five are required, including Parallel Computing Toolbox. See [[Installation and Requirements]].

**Start seems to hang for tens of seconds.** Expected on the first Start of a session: the parallel pool spins up and the worker handshakes. The status line reports each milestone. Subsequent Starts reuse the warm worker — unless you toggled the Testing checkbox, which rebuilds it.

**Undefined function or variable `mabr…` on the worker.** The pool predates the MABR path. The Engine runs `pctRunOnAll addpath(mabr.Config.root)` to defend against this; if it still fails, `delete(gcp('nocreate'))` and start again.

## Audio device

**The device dropdown is empty, or the interface is missing from it.** The list comes from
`getAudioDevices(audioPlayerRecorder)`, which enumerates **ASIO** devices only. Install the
manufacturer's ASIO driver (not ASIO4ALL, not the class-compliant WDM device) and confirm
it appears in the vendor's own control panel first. `mabr.AudioSettings.availableDevices`
never throws — an empty list is a missing driver, not an error.

**Test Device reports a rate other than 192000.** The device would not grant
`Config.DACSampleRate`, and MABR has no rate to change: every stimulus is rendered at
192 kHz. Check the vendor control panel for a rate lock or a channel-count trade-off at
the top rate, and see the hardware list in [[Installation and Requirements]].

**`mabr:ui:AcqController:timingNotDetected`** — the loop-back self-test streamed unit
pulses and heard nothing back. This is the most common rig problem, and it fails
immediately rather than after a whole silent block. Check the cable from
`PlayerChannels(2)` to `RecorderChannels(2)`, the channel numbers themselves (the fields
are 1-based device channels, not indices into some subset), and the input gain — detection
uses a fixed 0.1 threshold, so an input trimmed too far down reads as no pulse at all.
Characterise the margin with `verify_timing_loopback` at `'Testing',false`; see
[[Verification and Testing]].

## Stimulus loading

| Error | Fix |
| --- | --- |
| `mabr:stim:StimulusSet:noSignal` / `:noID` | Every entry needs a nonempty `signal` and `ID` |
| `mabr:stim:StimulusSet:mixedRates` | All entries must share one `SampleRate` — one run, one clock |
| `mabr:stim:StimulusSet:sampleRate` | Rate must equal `Config.DACSampleRate` (192000 Hz) |
| `mabr:stim:StimulusSet:timingLength` | An explicit `Timing` must match its `signal` in length |
| `mabr:stim:StimulusSet:noStimuli` | The `.mat` holds no struct array with `signal` + `ID` fields |

See [[Stimulus Package Contract]].

## Scheduling

**`mabr:stim:Schedule:tooLong`** — the run exceeds the ring buffer (`maxInputBufferLength`, ~5.8 min at 192 kHz). The check runs *before* allocation deliberately, so you get this instead of a `MATLAB:nomem`. Reduce repetitions, shorten the ISI, or switch to a blocked strategy so each run covers a single stimulus. Intermixed strategies render the whole design as one run and hit this first.

**`mabr:stim:Schedule:isi`** — the ISI is shorter than one sample at the stimulus rate. Under `ISIMode = 'random'` it is the *bottom* of `ISIRange` that is too short.

**`mabr:stim:Schedule:isiRange`** — `ISIRange` was given descending, as `[max min]`. It is never sorted for you: which bound is which is exactly what the mistake is about. The GUI's two fields cannot be crossed — pushing one past the other carries it along.

**Red overlap warning in the GUI / red log line.** The longest stimulus does not fit inside the ISI — or, with **Random** checked, inside the *shortest* interval that can be drawn, since one short draw is enough to collide. Overlapping presentations are **summed**, not clipped. Either lengthen the ISI (or raise the range minimum) or accept the summation knowingly.

**Repetition or strategy change had no effect.** `Schedule.build()` must be called after changing `Repetitions` or `Strategy`; `reset()` alone rewinds without rebuilding. The GUI does this for you via `buildSchedule`.

## Advance criterion

**The Advance dropdown is greyed out.** By design — you have selected an intermixed strategy (`interleaved`, `shuffled-cycles`, `shuffled`). Early-stopping a run that pools conditions would truncate whichever stimuli fell last. Pick `blocked` or `shuffled-blocks` to re-enable correlation threshold. See [[Presentation Strategies]].

**Correlation threshold never fires.** It cannot fire before `ctx.minSweeps` (default 32). Check the live `r =` readout against your threshold.

## Data / analysis

**Sweep onsets look wrong or empty.** Sweep extraction reads the **timing channel**, which MABR synthesizes as one pulse per onset (or merges from an entry's explicit `Timing`). Confirm the recorder channel mapping — `Schedule.RecorderChannels` is `[ADCsignal ADCtiming]`.

**Filtering appears not to be applied.** `mabr.data.Recording` filtering is explicit and opt-in: set `Filters` (a `mabr.FilterPolicy`) and call `designFilters()`. Before that, raw `Data` is used throughout. During acquisition the app does this for you from the **Filters…** dialog in the Acquisition panel. See [[Data Format]].

**`mabr:data:io:noABRData`** — the file contains no `ABR_Data` struct. `.abr` files are MAT-files; load with `load(file,'-mat')`.

**`batchABRAnalysis` errors on argument counts.** Known and deliberately unfixed — it calls `parseABRFiles`/`extractABRResponses` with stale positional arguments. Call those functions directly with name-value syntax. See [[Offline Analysis]].

## Clean slate

Delete `.runtime_data/` (the memory-mapped ring buffer files are recreated on the next Engine construction), close the app, `delete(gcp('nocreate'))`, and relaunch with `MABR`.
