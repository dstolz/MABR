# Architecture

How MABR is organized, and why. For a control-by-control tour of the software, see [The Acquisition App](Acquisition-App.md).

## The shape of the system

MABR does one job: play a pre-computed stimulus, record the response in lock-step, and save the result in a form the analysis pipeline can read. Everything is arranged around that.

```
   external stimulus package          (not part of MABR)
              │  calibrated waveforms
              ▼
   ┌──────────────────────┐
   │  +stim               │  what to play, in what order
   └──────────┬───────────┘
              │  play matrix (signal + timing)
              ▼
   ┌──────────────────────┐    commands ──►  ┌────────────────────┐
   │  +ui/AcqController   │                  │  parpool worker    │
   │  (GUI process)       │  ◄── state       │  +acq/worker_loop  │
   └──────────┬───────────┘                  └─────────┬──────────┘
              │                                        │ recorded samples
              │  ◄──────── memory-mapped ring buffer ──┘
              ▼
   ┌──────────────────────┐
   │  +data               │  Recording → Block → Session → .abr
   └──────────┬───────────┘
              ▼
      abr_analysis/  (separate, function-based, unchanged)
```

Two processes, two channels between them: **control and state travel as messages** over parallel queues; **bulk sample data travels through one memory-mapped ring buffer**. Nothing else is shared.

## The packages

Everything lives under the `+mabr` namespace. There is no other package.

| Package | Responsibility |
|---------|----------------|
| [+acq](../+mabr/+acq/) | The acquisition engine: worker, ring buffer, command/state protocol |
| [+data](../+mabr/+data/) | Data model and file IO: `Recording`, `Block`, `Session`, `io` |
| [+stim](../+mabr/+stim/) | The stimulus boundary: source contract, block queue, advance criteria |
| [+metrics](../+mabr/+metrics/) | Small, pure, tested functions: onset detection, sweep extraction, correlations, SNR |
| [+ui](../+mabr/+ui/) | The GUI: app, controller, live plot, trace organizer |
| [+log](../+mabr/+log/) | Verbosity-gated logging |

Plus [mabr.Config](../+mabr/Config.m) at the root: a plain **value** object holding hardware constants and runtime paths. It is not a superclass and nothing inherits from it — the app and engine each hold a copy.

## What MABR does not do

**MABR does not generate or calibrate stimuli.** An external package supplies pre-computed, calibrated waveforms through the [StimulusSet](../+mabr/+stim/StimulusSet.m) contract — a struct array in which each entry is **one** presentation (`signal` + `ID`). This is the single most important boundary in the system: it keeps acoustic calibration — which is rig-specific, changes over time, and needs its own validation — out of the acquisition path entirely.

[**stimgen**](https://github.com/dstolz/stimgen) fills that role and ships as a submodule at `external/stimgen`, but it does not move the boundary — it sits on the far side of it. [mabr.stim.fromStimgen](../+mabr/+stim/fromStimgen.m) converts a stimgen bank into the same struct array any other source would supply, and nothing downstream of `StimulusSet` knows which it got. The dependency is optional in both directions: MABR launches, acquires, and passes its test suite without stimgen ([mabr.stim.stimgenAvailable](../+mabr/+stim/stimgenAvailable.m) gates the features that need it), and stimgen has no idea MABR exists.

Calibration crosses the boundary in the one direction that has to work: stimgen measures the speaker, MABR provides the speaker. [mabr.stim.CalibrationAdapter](../+mabr/+stim/CalibrationAdapter.m) implements stimgen's two-method `HwAdapter` contract (`sample_rate`, `play_and_record`) against MABR's ASIO device and channel map, so a calibration describes the signal chain the experiment actually uses. MABR does *not* implement stimgen's `HardwareHost` — that is a TDT/RPvds playback protocol, and playback is MABR's own worker's job.

The boundary is drawn at *what the sound is*, not *when it is played*. **MABR owns presentation entirely**: the inter-stimulus interval, how many times each entry repeats, and how entries are combined across the bank (blocked, interleaved, shuffled) are all decided by [Schedule](../+mabr/+stim/Schedule.m) from settings the operator picks in the GUI. A stimulus package that also chose the timing would make experimental design a property of a calibration artifact, which is exactly backwards.

MABR also owns the **timing pulse channel**. `Schedule` synthesizes a unit pulse at each onset and pairs it with the external signal channel to form the 2-channel play matrix. That pulse is recorded back on a second input channel and is what sweep extraction keys off, so MABR must own the contract to guarantee sweeps are cut where they were actually played, not where they were nominally scheduled.

Because a run may intermix stimuli, `Schedule` also records which stimulus fired at each onset. [AcqController](../+mabr/+ui/AcqController.m) uses that to de-interleave the recording at save time, so the on-disk unit stays **one file per stimulus condition** no matter how the presentation was ordered — the offline pipeline never learns that interleaving happened.

**MABR does not do offline analysis.** The `abr_analysis/` pipeline is separate and function-based — see [Offline Analysis](Offline-Analysis.md). The coupling between them is the `.abr` file format and filename convention, documented in [Data Files](Data-Files.md) and enforced by a test.

## Acquisition: one warm worker

Acquisition runs on a **1-process parallel pool worker**, launched once per session with `parfeval` and kept alive across blocks so the pool and the `audioPlayerRecorder` stay warm. Details are in [Acquisition Engine](Acquisition-Engine.md); the shape is:

- [mabr.acq.Engine](../+mabr/+acq/Engine.m) runs in the GUI process, owns a read-only view of the ring buffer, and turns worker messages into MATLAB **events** via a `DataQueue` `afterEach` callback. **There are no busy-waits** — the sole bounded wait is the one-time startup handshake.
- [mabr.acq.worker_loop](../+mabr/+acq/worker_loop.m) runs on the worker, owns the audio device, streams frames, writes into the ring buffer, and polls a `PollableDataQueue` **every frame** for commands.

That per-frame poll is what makes online early-stopping possible: a criterion evaluated in the GUI process can stop a block the moment a response is detected, mid-playback.

## Program flow

A single explicit state object, [mabr.ui.ProgState](../+mabr/+ui/ProgState.m), drives the schedule:

```
Idle → PrepBlock → Acquire → BlockComplete → AdvanceBlock → (next block)
                                                    └──────► SchedComplete
                          any → Error
```

Transitions are driven by engine events and user actions. There is no global state and no polling of shared memory. [AcqController](../+mabr/+ui/AcqController.m) runs exactly one timer, at ~20 Hz, and it exists only to refresh the live view and evaluate the advance criterion.

## The data model

Three value/handle types, layered, with **no reference cycles**:

- [mabr.data.Recording](../+mabr/+data/Recording.m) (value) — one channel's samples plus sweep bookkeeping, and the dependent helpers that segment and measure them (`SweepData`, `SweepMean`, `SNR`, `noisePower`). It holds **no back-reference to a parent**; decimation is passed in explicitly.
- [mabr.data.Block](../+mabr/+data/Block.m) (value) — one condition: stimulus metadata + its `Recording` + computed metrics + start time.
- [mabr.data.Session](../+mabr/+data/Session.m) (handle) — subject/device config, the block queue, and the array of completed `Block`s.

Filtering is **explicit and opt-in**, and lives in a [`mabr.FilterPolicy`](../+mabr/FilterPolicy.m) held in `Recording.Filters` — three independent sections (high pass, low pass, notch), defaulting to 10 Hz / 3000 Hz / 60 Hz, applied zero-phase with `filtfilt`. `Recording` designs them only when you call `designFilters()`; afterwards the filtered trace is used consistently everywhere downstream (`ProcessedData` → `SweepData` → `SweepMean`). Before that call, the raw data is used.

The *same* policy object drives the live view (`AcqController.Filters`, redesigned at the live sweep rate whenever it is assigned) and the GUI's filter dialog, so what the operator watches and what a `Block` reports come off one set of corners. Nothing in that chain touches `Recording.Data`, which is what `io` writes — a `.abr` file is always the raw trace.

The filters are IIR by deliberate choice: an FIR of any practical order cannot realize a 10 Hz corner at a 12 kHz sample rate, and `filtfilt` removes the phase distortion that would otherwise argue for FIR.

## Metrics as pure functions

Anything computed from sweeps lives in [+metrics](../+mabr/+metrics/) as a small pure function with no acquisition dependencies — [find_timing_onsets](../+mabr/+metrics/find_timing_onsets.m), [partition_corr](../+mabr/+metrics/partition_corr.m), [snr](../+mabr/+metrics/snr.m), and so on. They are the single source of truth: `Block.computeMetrics` and the live view call the same functions, so a metric shown during acquisition and the same metric computed afterwards cannot disagree.

The one exception is [extract_sweeps](../+mabr/+metrics/extract_sweeps.m), which reads the ring buffer — but its cursor is **explicit state passed in and out by the caller**, not a persistent variable, so it is still deterministic and testable.

## Design principles

These are worth preserving in any change:

1. **No busy-waits.** Anything waiting on the worker listens to an event. The one bounded wait is the startup handshake.
2. **Messages for control, shared memory for bulk data.** Commands and state are never smuggled through the ring buffer.
3. **No reference cycles in the data model.** `Recording` knows nothing about who owns it.
4. **Metrics are pure functions**, shared between live and offline paths.
5. **The stimulus boundary stays closed.** No signal generation or calibration inside MABR.
6. **The `.abr` contract is tested, not assumed.** Change `io`, run [verify_data_roundtrip](../tests/verify_data_roundtrip.m).

## Historical note

This design replaced a two-`matlab.exe` architecture in which a headless background process was spawned via `system(...)`, liveness was checked with `wmic` PID queries, the stimulus was handed over as a `dac.wav` file, and commands and state were multiplexed through a `mabr_com.dat` memory map polled in `while ... pause(0.01)` loops. The legacy `+abr` package was retired at cutover and is recoverable from git history or the `master` branch. [MABR Complete Refactor — Ground-Up Rewrite.md](../MABR%20Complete%20Refactor%20—%20Ground-Up%20Rewrite.md) records the full rationale.
