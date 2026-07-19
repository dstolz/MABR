# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MABR (Matlab Auditory Brainstem Response) is a **proprietary, Windows-only** MATLAB toolbox for presenting acoustic stimuli and acquiring/analyzing ABR electrophysiology data. Copyright Daniel Stolzberg, PhD — see `Copyright.txt`. There is no build system, package manager, or automated test harness; it runs inside MATLAB.

## Running & developing

- **Launch the app:** run `MABR` from the MATLAB command window. `MABR.m` genpath-adds every subfolder (except `.git`) to the MATLAB path and opens `abr.ControlPanel`.
- **Requires** (see `abr.Universal.RequiredToolboxes`): MATLAB ≥ 9.5 (R2018b), Signal Processing ≥ 8.1, Audio Toolbox ≥ 1.5, DSP System Toolbox ≥ 9.1. Audio I/O expects an **ASIO** device via `audioPlayerRecorder`.
- **No unit tests.** `permtest.m` is a statistical permutation test, not a test harness. Files named `SCRATCH_*`, `temp.m`, and `Cmd.m`-style scratch are exploratory.
- **Verbosity/logging:** nearly all code logs through `vprintf(level, [red], fmt, ...)` gated on global `GVerbosity` (-1…3). `vprintf(0,1,...)` prints a critical message in red. Logs also go to `.error_logs/`.

## MATLAB conventions used here

- `+abr/` is the **package namespace** — everything is `abr.ClassName` / `abr.subpkg.Thing`. `@ClassName/` folders are multi-file class definitions. `+sigdef`, `+analysis`, `+traces` are subpackages.
- Real-time paths and runtime files are centralized in `abr.Universal` (constants like `DACSampleRate=192000`, `ADCSampleRate=12000`, `frameLength`, plus paths to `.runtime_data/`).

## Architecture: two-process real-time acquisition

This is the load-bearing design and spans several files. Acquisition runs across **two MATLAB processes** that never call each other directly — they communicate only through memory-mapped files in `.runtime_data/`:

- **Foreground** = the GUI. `abr.ControlPanel` (App Designer app, extends `matlab.apps.AppBase` + `abr.Universal`) owns an `abr.ABR` data object, an `abr.Schedule`, an `abr.SoundCalibration`, and an `abr.Runtime('Foreground')`. It drives everything with `timer` objects (`timer_Start/Runtime/Stop/Error`).
- **Background** = a headless MATLAB instance spawned by `abr.Runtime.launch_bg_process` via `system("matlab.exe ... -nodesktop -minimize -noFigureWindows -r ""H = abr.Runtime('Background')""")`. It owns the `audioPlayerRecorder` (playback+record) and `dsp.AudioFileReader`, streaming the DAC WAV out and recording ADC in a tight loop (`prepare_block_bg` → `acquire_block`).
- **IPC via memmapfile** (created in `abr.Runtime`, paths from `abr.Universal`): `mabr_com.dat` (commands + buffer indices + state), `input_buffer.dat` (recorded signal channel), `input_timing.dat` (recorded timing channel), `dac.wav` (stimulus waveform to play), `info.mat`.
- **Shared enums** coordinate the two processes and the GUI state machine:
  - `abr.Cmd` — commands passed foreground↔background (`Prep`, `Run`, `Pause`, `Stop`, `Kill`, …).
  - `abr.stateAcq` — background acquisition state (`IDLE`, `ACQUIRE`, `COMPLETED`, …).
  - `abr.stateProgram` — foreground program flow (`PREP_BLOCK`, `ACQUIRE`, `BLOCK_COMPLETE`, `SCHED_COMPLETE`, …).
- **Sweep extraction:** the timing channel carries onset markers; `abr.Runtime/find_timing_onsets` locates them and `extract_sweeps` slices the continuous ADC buffer into per-sweep epochs.

When touching acquisition, remember state changes propagate through the memmap files and are polled by timers — you cannot step through it as one linear call stack, and the background process has no console you can see (its output goes to `.runtime_data/Background_process_log.txt`).

## Core data model

- `abr.ABR` (handle + Copyable) — the session object: `DAC`/`ADC` (both `abr.Buffer`), `SIG` (a signal), channel maps (`ADCsignalCh`/`ADCtimingCh`/…), sweep params (`sweepRate`, `numSweeps`), and the ADC filter chain (bandpass HP 10 Hz / LP 3000 Hz + 60 Hz notch, designed lazily in `createADCfilt`). `to_struct` serializes it (Buffers/signals flattened) for saving.
- `abr.Buffer` (value class) — a channel's acquired data plus `SweepOnsets`, `SweepLength`, `SweepValue`, artifact flags (`IsArtifact`), and FFT/plot/detrend/smoothing helpers.
- `abr.ABR/analysis(type,...)` dispatches live metrics over sweep data: `'corr'` (Fisher-z mean pairwise correlation), `'rms'`, `'peaks'` (findpeaks), else `feval(type,...)`.

## Stimulus definition & scheduling

- `abr.sigdef.sigs.{Tone,Click,Noise,File}` are concrete signals extending abstract `abr.sigdef.Signal`. Every tunable parameter (level, duration, frequency, ramp, …) is wrapped in an `abr.sigdef.sigProp` (value + Alias + units + display format), which is how the GUI auto-builds parameter tables.
- `abr.SoundCalibration` (+ `abr.CalibrationUtility`) converts requested dB SPL to output amplitude per frequency; signals apply it when `UseCalibration` is true.
- `abr.Schedule` / `abr.ScheduleDesign` (App Designer table GUIs) define the ordered list of stimulus blocks (e.g. a level × frequency grid). The ControlPanel walks the schedule block-by-block.
- **Advance criteria** live in `advanceFcns/` (e.g. `abr_adv_corr_thr`, `abr_adv_num_sweeps`) — each takes the running app and returns whether the current block is done, selected from the ControlPanel's advance-criteria dropdown.

## GUI-side helpers

- `abr.traces.Organizer` (+ `Trace`/`Group`/`Marker`) — interactive waveform stacking and peak-marking in the plots.
- `+analysis/` (`@Analysis`, `CorrCoef`, `Peaks`, `RMS`) — live metrics shown during acquisition.
- `abr.ControlPanel/createComponents.m` is generated App Designer layout code — edit UI logic elsewhere and treat that file as machine-managed.

## Offline analysis pipeline (`abr_analysis/`)

This is a **separate, newer, function-based** batch pipeline (authored `dstolz@umd.edu`, 2025) — not part of the `+abr` app. It reprocesses saved `.abr` files for threshold estimation and is where most current uncommitted work lives. Flow (`batchABRAnalysis`):

`getABRSessions` → `parseABRFiles` (regex over filenames, e.g. `SUBJ_ID_<n>_Frequency_<f>kHz_Level_<L>dB_<yyMMdd'T'HHmmss>.abr`) → `extractABRResponses` (loads `-mat`, filters full trace, segments into sweeps grouped by stimulus) → `rejectArtifacts` → `filterABRData` → `plotABRGrid` → `abrPermutationThreshold` (permutation-test threshold via `permtest`, with `abrPermutationThresholdCuration` for manual review).

## Data file format

`.abr` files are **MATLAB v5 MAT-files** (despite the extension) containing a single `ABR_Data` struct (the output of `abr.ABR.to_struct`). Load with `load(file,'-mat')`. Note `*.abr`, `.runtime_data/`, and `*.asv` are gitignored — sample `.abr` files checked in at the repo/`+abr` root predate that rule.
