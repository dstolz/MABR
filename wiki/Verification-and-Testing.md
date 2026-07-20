# Verification and Testing

Everything in `tests/` runs in **TESTING loopback mode with no audio device**, so the suite works on any machine that satisfies the toolbox requirements.

## Run everything

```matlab
cd tests
run_all_verifications
```

## The individual scripts

| Script | What it verifies |
| --- | --- |
| `verify_engine_loopback` | The parpool worker starts, streams a rendered run, and the recorded frames come back through the ring buffer |
| `verify_data_roundtrip` | A `Block` written by `mabr.data.io.writeABR` reads back correctly **through the offline pipeline's field set** |
| `verify_legacy_import` | Legacy `ABR_Data` structs — including sigProp-style `SIG` — import into the new model |
| `verify_online_advance` | The correlation advance criterion stops a block early, mid-stream |

Each can be run on its own.

## Testing mode elsewhere

Loopback is not test-only plumbing — it is the GUI's default. **Testing (loopback, no hardware)** is checked when `mabr.ui.App` opens, and `mabr.acq.Engine(cfg,true)` gives the same behaviour programmatically. Played frames are fed straight back as recorded frames, exercising the full engine, schedule, extraction, and save path.

`mabr.stim.Schedule.TestingFrameDelay` (seconds per frame) paces loopback for tests that need wall-clock realism; it is 0 by default and has no effect with real hardware.

## Demo stimuli

`mabr.stim.demoStimuli` supplies a tone-pip Frequency × Level bank so the suite has no external stimulus-package dependency. It is for testing and demos only — MABR does not generate or calibrate stimuli in production. See [[Stimulus Package Contract]].

## Turning up detail

```matlab
global GVerbosity
GVerbosity = 3;
```

Levels run −1 … 3. Output also lands in `.error_logs/`.
