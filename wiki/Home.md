# MABR

**M**atlab **A**uditory **B**rainstem **R**esponse — a Windows-only MATLAB toolbox for presenting calibrated acoustic stimuli and acquiring/analyzing ABR electrophysiology data.


Copyright © Daniel Stolzberg, PhD (`dstolz@umd.edu`). Proprietary — see `Copyright.txt` in the repository.

## Start here

| If you want to… | Read |
| --- | --- |
| Get it running on a new machine | [[Installation and Requirements]] |
| Run an experiment | [[Running a Session]] |
| Feed MABR your own stimuli | [[Stimulus Package Contract]] |
| Understand blocked vs. interleaved | [[Presentation Strategies]] |
| Understand how acquisition works | [[Acquisition Engine]] |
| Read a saved `.abr` file | [[Data Format]] |
| Batch-process saved files | [[Offline Analysis]] |
| Check the install without hardware | [[Verification and Testing]] |
| Fix something | [[Troubleshooting]] |

## What MABR is and is not

MABR **owns presentation and acquisition**. It decides spacing, repetition, ordering, and early-stopping; it streams the stimulus, records two channels, extracts sweeps, and writes one file per condition.

MABR **does not generate or calibrate stimuli**. An external package supplies precomputed, calibrated waveforms as a plain struct array — one entry per single presentation. See [[Stimulus Package Contract]]. A built-in tone-pip bank, `mabr.stim.demoStimuli`, exists for testing and demos only.

## Layout

Everything lives in the `+mabr` package namespace:

| Subpackage | Role |
| --- | --- |
| `+mabr/+acq` | Acquisition engine (parpool worker, ring buffer, state machine) |
| `+mabr/+data` | Data model (`Recording`, `Block`, `Session`) and `.abr` I/O |
| `+mabr/+stim` | `StimulusSet` adapter, `Schedule`, advance criteria |
| `+mabr/+metrics` | Small tested functions: sweep extraction, SNR, correlation, peaks |
| `+mabr/+ui` | GUI: `App`, `AcqController`, `LivePlot`, `TraceOrganizer` |
| `+mabr/+log` | Verbosity-gated logger |
| `abr_analysis/` | Separate, function-based **offline** batch pipeline (not part of the app) |
| `tests/` | Hardware-free verification scripts |

`mabr.Config` is a plain **value** object holding the fixed constants and runtime paths. Nothing inherits from it.

## History

The acquisition app was rewritten ground-up into the single `+mabr` namespace. The legacy `+abr` package was retired at cutover and remains recoverable from git history and the `master` branch. The rewrite replaced a two-`matlab.exe` design (spawned via `system(...)`, WMIC PID checks, `info.mat` and `dac.wav` handoff, a `mabr_com.dat` command memmap, and busy-wait loops throughout) with a warm parallel-pool worker and event-driven control.
