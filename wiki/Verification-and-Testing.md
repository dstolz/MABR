# Verification and Testing

Everything in `tests/` runs in **TESTING loopback mode with no audio device**, so the suite works on any machine that satisfies the toolbox requirements.

## Run everything

```matlab
cd tests
run_all_verifications
```

## Run them from the GUI

**Help ▸ Verification Tests…** opens `mabr.ui.TestRunner`: every `verify_*.m` in `tests/` in one list, with a tick box each, a verdict, how long it took, and the full console output of each run in a pane below. Tick what you want and press **Run Selected**, or **Run All**. Nothing is listed by hand — the window finds the scripts on disk and orders them the way `run_all_verifications` runs them, so a newly written verification appears whether or not it has been added to the suite yet.

A test **passes by returning without throwing** — every check inside these files is an `assert`. A failure puts its message in the row and its full report, along with everything the test printed before it failed, in the log.

Two things worth knowing:

- **Stop is cooperative.** MATLAB is inside the test while it runs, so Stop takes effect between tests, not during one. Closing the window mid-run does the same and tears it down afterwards.
- **Use the rig for the timing loop-back** is the one opt-in that touches hardware. It re-runs `verify_timing_loopback` against the real device with the channel mapping saved in **Settings ▸ Audio Device (ASIO)…**, i.e. the rig diagnostic that script's own help describes. Nothing else in the list is affected.

The menu item is locked while a schedule is running: the suite builds its own engine, worker, and parallel pool, and cannot share the rig with an acquisition in flight.

## The individual scripts

| Script | What it verifies |
| --- | --- |
| `verify_isi_jitter` | Presentation timing: a fixed ISI still lands on its grid, a randomized one draws inside its range, and the timing channel still marks every onset |
| `verify_engine_loopback` | The parpool worker starts, streams a rendered run, and the recorded frames come back through the ring buffer |
| `verify_data_roundtrip` | A `Block` written by `mabr.data.io.writeABR` reads back correctly **through the offline pipeline's field set** |
| `verify_legacy_import` | Legacy `ABR_Data` structs — including sigProp-style `SIG` — import into the new model |
| `verify_online_advance` | The correlation advance criterion stops a block early, mid-stream |
| `verify_artifact_rejection` | The voltage/RMS criteria, their prefs, and the make-up runs a rejected sweep triggers |
| `verify_filters` | The display filter chain has the corners it claims — and never reaches the saved trace |
| `verify_live_plot` | The live view: per-stimulus running means, time base, amplitude scaling, control strip |
| `verify_trace_organizer` | Scaling, spacing, selection, marking, and `.torg` save/load round-trip |
| `verify_trace_inspector` | Peak detection in search windows, manual placement, and the transfer of measured waves back to the organizer |
| `verify_audio_settings` | Device and channel settings: prefs, a device query that cannot throw, schedule wiring |
| `verify_stimgen_import` | stimgen bank → `StimulusSet`: one variant per entry, regenerated at the DAC rate, declared `informativeParams`, `.spl` round-trip — and an FFT of every waveform against its own label. **Skips and passes** without the submodule |
| `verify_timing_selftest` | The pre-run timing loop-back self-test catches a dead cable without regressing a normal Start |
| `verify_timing_loopback` | Timing pulse recovery: count, jitter, clock drift, detection margin. Also the rig **diagnostic** — run it with `'Testing',false` |
| `verify_test_runner` | The window that runs this list: discovery, ordering, output capture, verdicts |

Each can be run on its own.

## Testing mode elsewhere

Loopback is not test-only plumbing — it is the GUI's default. **Testing (loopback, no hardware)**, in **Settings ▸ Audio Device (ASIO)…** (`mabr.ui.AudioSettingsDialog`, backed by `mabr.AudioSettings.Testing`), is checked by default, and `mabr.acq.Engine(cfg,true)` gives the same behaviour programmatically. Played frames are fed straight back as recorded frames, exercising the full engine, schedule, extraction, and save path.

`mabr.stim.Schedule.TestingFrameDelay` (seconds per frame) paces loopback for tests that need wall-clock realism; it is 0 by default and has no effect with real hardware.

## Demo stimuli

`mabr.stim.demoStimuli` supplies a tone-pip Frequency × Level bank so the suite has no external stimulus-package dependency. It is for testing and demos only — MABR does not generate or calibrate stimuli in production. See [[Stimulus Package Contract]].

## Turning up detail

```matlab
global GVerbosity
GVerbosity = 3;
```

Levels run −1 … 3. Output also lands in `.error_logs/`.
