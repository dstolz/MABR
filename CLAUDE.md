# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MABR (Matlab Auditory Brainstem Response) is a **proprietary, Windows-only** MATLAB toolbox for presenting acoustic stimuli and acquiring/analyzing ABR electrophysiology data. Copyright Daniel Stolzberg, PhD — see `Copyright.txt`. There is no build system or package manager; it runs inside MATLAB.

The acquisition app was **rewritten ground-up** into a single `+mabr` namespace (see `MABR Complete Refactor — Ground-Up Rewrite.md`). The legacy `+abr` package was retired at cutover and is recoverable from git history / the `master` branch.

## Running & developing

- **Launch the app:** run `MABR` from the MATLAB command window. `MABR.m` genpath-adds every subfolder (except `.git`) and opens `mabr.ui.App`.
- **Requires** (see `mabr.Config.RequiredToolboxes`): MATLAB ≥ 9.5 (R2018b), Signal Processing ≥ 8.1, Audio Toolbox ≥ 1.5, DSP System Toolbox ≥ 9.1, **Parallel Computing Toolbox** (new — the acquisition engine runs on a parpool worker). Audio I/O expects an **ASIO** device via `audioPlayerRecorder`.
- **Verification (no hardware):** `tests/run_all_verifications.m` runs the suite — engine loopback, `.abr` round-trip through the offline pipeline, legacy import, and the online-advance early-stop. Individual scripts: `verify_engine_loopback`, `verify_data_roundtrip`, `verify_legacy_import`, `verify_online_advance`. All run in TESTING loopback mode with no audio device.
- **Verbosity/logging:** code logs through `mabr.log.vprintf(level, [red], fmt, ...)` gated on global `GVerbosity` (-1…3). `mabr.log.vprintf(0,1,...)` prints a critical message in red. Logs also go to `.error_logs/`.

## MATLAB conventions used here

- `+mabr/` is the **package namespace** — everything is `mabr.Thing` / `mabr.subpkg.Thing`. Subpackages: `+acq` (acquisition engine), `+data` (data model + IO), `+stim` (stimulus adapter + advance criteria), `+metrics` (small tested functions), `+ui` (GUI), `+log` (logger).
- `mabr.Config` is a plain **value** object (NOT a superclass) holding constants (`DACSampleRate=192000`, `ADCSampleRate=12000`, `frameLength=1024`, `maxInputBufferLength=2^26`) and the runtime/error-log paths. Nothing inherits from it.

## Architecture: parpool-worker acquisition engine (`+mabr/+acq/`)

The load-bearing subsystem. Acquisition runs on a **1-process parallel pool worker** launched once per session with `parfeval`, keeping the pool and `audioPlayerRecorder` warm. Control/state flow over **parallel queues**; recorded samples flow through **one** memory-mapped ring buffer. This replaces the legacy two-`matlab.exe` design (spawned via `system(...)`, Wmic PID checks, `info.mat`, `dac.wav` handoff, `mabr_com.dat` command/state memmap).

- `mabr.acq.Engine` (client, GUI process) — starts/keeps the pool warm, launches the worker, owns the read-only ring buffer, and turns worker messages into **events** (`StateChanged`/`BlockCompleted`/`WorkerError`) via a `DataQueue` `afterEach` callback. **No busy-waits.**
- `mabr.acq.worker_loop` (runs ON the worker) — owns the `audioPlayerRecorder`, streams the pre-rendered stimulus frame-by-frame (analogue of the legacy `acquire_block`), writes recorded ch1/ch2 into the ring buffer, and polls a `PollableDataQueue` every frame for `Prep`/`Run`/`Pause`/`Stop`/`Kill`. A **TESTING loopback** mode (`Engine(cfg,true)`) runs the whole engine with no hardware.
- `mabr.acq.RingBuffer` — thin wrapper over the retained memmap surface: `ring_signal.dat` + `ring_timing.dat` (single, `maxInputBufferLength`) plus a small `ring_header.dat` write-head header. Worker writable, client read-only.
- Enums `mabr.acq.Cmd` (client→worker commands) and `mabr.acq.State` (worker→client state) travel as messages, not shared memory.
- Because commands are polled every frame, the engine can honor an **online advance criterion** — stopping a block early when a correlation threshold is met (the capability the legacy code documented it could not provide).

Sweep extraction moved to `+metrics`: `mabr.metrics.find_timing_onsets` (pure function on a timing vector) and `mabr.metrics.extract_sweeps` (explicit cursor state, reads the ring buffer) — direct analogues of the legacy `abr.Runtime` methods.

## Core data model (`+mabr/+data/`)

- `mabr.data.Recording` (value type) — one channel's `SampleRate` + `Data` + `SweepOnsets`/`SweepLength`, with `SweepData`/`SweepMean`/`noisePower`/`SNR` ported from the old `abr.Buffer` but **cycle-free** (no `ABRobj` back-reference; decimation passed explicitly). Filtering is **explicit**: `designFilters()` builds the bandpass (HP 10 / LP 3000) + 60 Hz notch, applied consistently in segmentation (the legacy designed but never applied it).
- `mabr.data.Block` (value) — one condition's result: stimulus metadata + the recorded `Recording` + computed metrics + start time.
- `mabr.data.Session` (handle) — subject/device/rate config + block queue + array of `Block` results.
- `mabr.data.io` — save/load. `writeABR` emits an offline-compatible `ABR_Data` struct and matching filename; `importLegacy` reads old `ABR_Data` structs (incl. sigProp-style SIG) into the new model.

## Stimulus adapter (`+mabr/+stim/`)

MABR **does not** generate signals or calibrate — an external package supplies precomputed, calibrated waveforms through the `mabr.stim.StimulusSource` contract (`numBlocks`/`getBlock`, each block: `samples`, `SampleRate`, sweep timing, `Meta`). `mabr.stim.PrecomputedSource` is the reference adapter; `mabr.stim.demoSource` is a built-in tone-pip source for testing only.

`mabr.stim.BlockQueue` holds the pre-rendered blocks and walks the schedule. It builds the **2-channel play matrix** by pairing the external signal channel with a **timing-pulse channel it synthesizes** (one pulse per sweep onset) — MABR owns the timing contract because sweep extraction depends on it (in-memory analogue of the legacy `prepare_block_fg` `dac.wav` handoff). Advance criteria are proper implementations in `+stim/+advance/`: `num_sweeps` and a real `corr_threshold` (the legacy `abr_adv_corr_thr.m` was an empty stub).

## GUI (`+mabr/+ui/`)

- `mabr.ui.App` — the programmatic uifigure view (replaces `abr.ControlPanel`); `createComponents` is treated as generated layout.
- `mabr.ui.AcqController` — owns the `Engine`/`Session`/`BlockQueue`, translates UI actions → engine commands and engine events → UI updates, and runs **one ~20 Hz timer** for the live view only. A single explicit `mabr.ui.ProgState` (Idle/PrepBlock/Acquire/BlockComplete/AdvanceBlock/SchedComplete/Error) drives program flow — event-driven, no global, no busy-wait.
- `mabr.ui.LivePlot` — mean / most-recent / correlation-bar live view.
- `mabr.ui.TraceOrganizer` (+ `Trace`/`Marker`) — interactive stacked-waveform viewer with the broken legacy Group/Marker fixed and the user32.dll mouse hook replaced by standard figure callbacks.

## Offline analysis pipeline (`abr_analysis/`) — UNCHANGED

A **separate, function-based** batch pipeline (authored `dstolz@umd.edu`, 2025) — not part of the app and untouched by the rewrite. It reprocesses saved `.abr` files. Flow (`batchABRAnalysis`):

`getABRSessions` → `parseABRFiles` (regex over filenames, e.g. `SUBJ_ID_<n>_Frequency_<f>kHz_Level_<L>dB_<yyMMdd'T'HHmmss>.abr`) → `extractABRResponses` (loads `-mat`, filters full trace, segments into sweeps grouped by stimulus) → `rejectArtifacts` → `filterABRData` → `plotABRGrid` → `abrPermutationThreshold` (permutation-test threshold via `permtest`, with `abrPermutationThresholdCuration`).

It reads exactly: `ABR_Data.ADC.SampleRate`/`Data`/`SweepOnsets`, `ABR_Data.StartTime`, `ABR_Data.SIG.informativeParams` + numeric named params + `Label`. `mabr.data.io.writeABR` emits precisely these; `verify_data_roundtrip` confirms it. Note `batchABRAnalysis` has a **known stale-signature bug** (it calls `parseABRFiles`/`extractABRResponses` with positional args that no longer match) — **do not fix** it; call those functions with name-value syntax directly instead. `parfor_progress` is an external File Exchange dependency of this pipeline.

## Data file format

`.abr` files are **MATLAB v5 MAT-files** (despite the extension) containing a single `ABR_Data` struct. Load with `load(file,'-mat')`. Note `*.abr`, `.runtime_data/`, and `*.asv` are gitignored.
