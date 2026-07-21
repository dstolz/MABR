# Installation

## What you need

**Windows.** MABR is Windows-only. It checks this at launch and refuses to start elsewhere.

**MATLAB R2021b (9.11) or newer**, plus these toolboxes:

| Toolbox | Minimum version | Why |
|---------|-----------------|-----|
| Signal Processing Toolbox | 8.1 | Filter design, resampling, peak finding |
| Audio Toolbox | 1.5 | The ASIO full-duplex audio interface |
| DSP System Toolbox | 9.1 | Streaming support |
| Parallel Computing Toolbox | 6.13 | Acquisition runs on a parallel worker |

The R2021b floor comes from the GUI: `mabr.ui.App` puts a `uitoolbar` on a `uifigure`, which is only supported from R2021b. Everything outside `+mabr/+ui` still runs on R2019b.

The Parallel Computing Toolbox is not optional — the acquisition engine runs on a parallel pool worker, and MABR will not acquire without it.

**An ASIO sound device.** MABR talks to your hardware through MATLAB's `audioPlayerRecorder`, which requires an ASIO driver. Consumer sound cards using WDM/DirectSound will not work. You need two output channels (stimulus + timing pulse) and two input channels (electrode signal + timing pulse recorded back).

**An external stimulus package.** MABR does not generate or calibrate sounds — see [Architecture](Architecture.md#what-mabr-does-not-do). You supply pre-computed, calibrated waveforms. For testing and for a first look at the software, a built-in demo stimulus is included, so you can skip this to start with.

## Setup

1. Put the MABR folder somewhere convenient, e.g. `C:\src\MABR`.
2. Start MATLAB and change to that folder.
3. Run the launcher:

   ```matlab
   >> MABR
   ```

[MABR.m](../MABR.m) adds every subfolder to the MATLAB path (skipping `.git`) and opens the acquisition window. You do not need to add paths yourself, and there is nothing to compile or install — MABR is plain MATLAB code.

If you want the path set up permanently, run `MABR` once and then `savepath`.

## Checking that it works

Without any hardware attached, run the verification suite:

```matlab
>> run_all_verifications
```

This exercises the acquisition engine in loopback mode (no audio device), writes and re-reads a data file, imports a legacy file, and confirms the early-stop logic. You should see:

```
==== 4 / 4 verifications passed ====
```

The first run is slow — MATLAB has to start the parallel pool. Subsequent runs reuse it.

If a toolbox is missing, MABR tells you which one when the app opens. See [Troubleshooting](Troubleshooting.md) if something else goes wrong.

## Folders MABR creates

Two hidden folders appear inside the MABR directory on first run. Both are excluded from version control and neither contains data you need to keep:

- `.runtime_data/` — the memory-mapped buffers the acquisition engine streams through. Large (a few hundred MB) and reused every session.
- `.error_logs/` — one text log per day, mirroring the messages printed to the command window.

---

## Developer notes

Requirements are declared in [+mabr/Config.m](../+mabr/Config.m) as `RequiredToolboxes`, and checked by `Config.verifyToolboxes`, which [mabr.ui.App](../+mabr/+ui/App.m) calls in its constructor. Add a dependency by adding a row to that table — the check compares against `ver` output, treating the version's decimal as a zero-padded minor component so 9.12 correctly outranks 9.5.

`mabr.Config` is a plain value object, not a superclass; nothing inherits from it. Runtime paths (`runtimeDir`, `errorLogDir`) are static methods that create their folder on demand, so the engine can memory-map into them without a separate setup step.

There is no build system, package manager, or install script. The only path manipulation is the `genpath` call in [MABR.m](../MABR.m).
