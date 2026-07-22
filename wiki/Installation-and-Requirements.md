# Installation and Requirements

## Platform

**Windows only.** `MABR.m` warns and returns immediately on any other platform. Audio I/O expects an **ASIO** device driven through `audioPlayerRecorder`.

## Required toolboxes

Checked at startup by `mabr.Config.verifyToolboxes`, which throws a listing of anything missing or too old.

| Requirement | Minimum version |
| --- | --- |
| MATLAB | 9.7 (R2019b) |
| Signal Processing Toolbox | 8.1 |
| Audio Toolbox | 1.5 |
| DSP System Toolbox | 9.1 |
| **Parallel Computing Toolbox** | 6.13 |

The Parallel Computing Toolbox is not optional — the acquisition engine runs on a parallel-pool worker. See [[Acquisition Engine]].

## Install

There is no build system and no package manager. Clone or copy the repository anywhere, then from the MATLAB command window:

```matlab
cd C:\path\to\MABR
MABR
```

`MABR.m` adds every subfolder except `.git` to the MATLAB path and opens `mabr.ui.App`. Call `MABR(rootDir)` to point it at a different root.

`h = MABR` returns the app handle; called without an output it clears it.

## Hardware constants

Fixed in `mabr.Config` (`+mabr/Config.m`). These are compiled-in assumptions, not user settings — the ring buffer and sweep windowing depend on them:

| Constant | Value | Meaning |
| --- | --- | --- |
| `DACSampleRate` | 192000 Hz | Playback and full-duplex record rate |
| `ADCSampleRate` | 12000 Hz | Decimated storage/analysis rate (÷16) |
| `frameLength` | 1024 | Samples per play/record frame |
| `maxInputBufferLength` | 2^26 | Ring-buffer length (~5.8 min @ 192 kHz) |

A stimulus bank whose `SampleRate` differs from `DACSampleRate` is rejected with `mabr:stim:StimulusSet:sampleRate`.

## Runtime directories

Created on demand at the repository root, both gitignored:

- `.runtime_data/` — the memory-mapped ring buffer files (`ring_signal.dat`, `ring_timing.dat`, `ring_header.dat`)
- `.error_logs/` — logger output

Reach them with `mabr.Config.runtimeDir` / `mabr.Config.errorLogDir`.

## First run without hardware

Leave **Testing (loopback, no hardware)** checked in **Settings ▸ Audio Device (ASIO)…**, or run the verification suite:

```matlab
cd tests
run_all_verifications
```

See [[Verification and Testing]].
