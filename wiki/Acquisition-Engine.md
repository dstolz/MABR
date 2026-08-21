# Acquisition Engine

`+mabr/+acq/` is the load-bearing subsystem. Acquisition runs on a **one-process parallel pool worker**, launched once per session with `parfeval` and kept warm along with its `audioPlayerRecorder`. Control and state flow over **parallel queues**; recorded samples flow through **one** memory-mapped ring buffer.

## Components

**`mabr.acq.Engine`** (client, GUI process) — starts and keeps the pool warm, launches the worker, owns the read-only ring-buffer view, and turns worker messages into **events** via a `DataQueue` `afterEach` callback. No busy-waits anywhere.

Events to listen on:

| Event | Payload |
| --- | --- |
| `StateChanged` | `mabr.acq.StateEventData` with `.State` |
| `BlockCompleted` | the current block finished or was stopped |
| `WorkerError` | `.Identifier` / `.Message` |

**`mabr.acq.worker_loop`** (runs **on** the worker) — owns the `audioPlayerRecorder`, streams the pre-rendered stimulus frame by frame, writes recorded ch1/ch2 into the ring buffer, and polls a `PollableDataQueue` **every frame** for `Prep` / `Run` / `Pause` / `Stop` / `Kill`.

**`mabr.acq.RingBuffer`** — thin wrapper over the memmap surface: `ring_signal.dat` + `ring_timing.dat` (each `maxInputBufferLength` long) plus a small `ring_header.dat` write-head header, all under `.runtime_data/`. Writable on the worker, read-only on the client.

**`mabr.acq.Cmd` / `mabr.acq.State`** — enums travelling as queue messages, not shared memory.

## Lifecycle

```matlab
eng = mabr.acq.Engine(cfg, testing, @(msg) disp(msg));
eng.waitUntilReady();     % one-time worker handshake
eng.prep(spec);           % arm a block (spec from Schedule.renderSpec)
eng.run();                % start streaming
eng.pause(); eng.resume();
eng.stop();               % end the current block
eng.kill();               % tear down the worker
```

The optional third constructor argument is a progress sink called with a char message at each startup milestone — pool spin-up can take tens of seconds, and the GUI pipes this straight into its status line.

Startup also runs `pctRunOnAll addpath(mabr.Config.root)` before the config argument is deserialized, so a **reused** pool that predates the MABR path still resolves the `+mabr` namespace.

## Testing / loopback mode

`mabr.acq.Engine(cfg, true)` runs the entire engine with **no hardware**: the played frames are fed straight back as recorded frames. Every verification script uses this, and it is the GUI's default. `Schedule.TestingFrameDelay` paces loopback frames for tests that need wall-clock realism.

## Sweep extraction

Moved out of the engine into `+mabr/+metrics/` as tested functions:

- `mabr.metrics.find_timing_onsets` — pure function over a timing vector
- `mabr.metrics.extract_sweeps` — explicit cursor state, reads the ring buffer

Both are direct analogues of the legacy `abr.Runtime` methods, minus the hidden state.

Also in `+metrics`: `mean_pairwise_corr`, `partition_corr` (drives the correlation advance criterion and the live `r` readout), `snr`, `rms_metric`, `find_peaks`.

## Why the online advance criterion is possible

Because commands are polled every frame, the engine can honor an advance predicate mid-block and stop as soon as it fires. The legacy two-process design could not: it documented outright that it was *"NOT CURRENTLY POSSIBLE TO UPDATE THE NUMBER OF SWEEPS DURING PLAYBACK"*. See [[Presentation Strategies]].

## What this replaced

The legacy path spawned a second `matlab.exe` via `system(...)`, polled WMIC for the child PID to test liveness, handed off configuration through `info.mat` and the stimulus through `dac.wav`, exchanged commands and state through a `mabr_com.dat` memmap, and busy-waited with `while … pause(0.01)` throughout. All of it is gone; it is recoverable from git history and the `master` branch.
