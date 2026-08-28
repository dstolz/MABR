# MABR Documentation

Documentation for MABR (MATLAB Auditory Brainstem Response), organized by audience.

## For users running experiments

Start here if your job is to record ABRs, not to modify the code.

| Page | What it covers |
|------|----------------|
| [Installation](Installation.md) | What you need, how to set it up, how to check it works |
| [Getting Started](Getting-Started.md) | Your first recording, start to finish |
| [The Acquisition App](Acquisition-App.md) | Every control in the main window, and what it does |
| [Viewing Data](Viewing-Data.md) | Live plot, Online Analysis, and Trace Organizer |
| [Data Files](Data-Files.md) | Where files go, how they're named, what's inside |
| [Test Mode](Test-Mode.md) | Checking that stimulus and acquisition are aligned, with no hardware |
| [Offline Analysis](Offline-Analysis.md) | Batch-processing saved recordings into thresholds |
| [Troubleshooting](Troubleshooting.md) | Common problems and what they mean |

## For developers

Start here if you are extending, embedding, or debugging MABR.

| Page | What it covers |
|------|----------------|
| [Architecture](Architecture.md) | How the pieces fit: engine, data model, GUI, boundaries |
| [Acquisition Engine](Acquisition-Engine.md) | The parpool worker, ring buffer, command/state protocol |
| [Compute Workers](Compute-Workers.md) | The pipeline, the DSP and metrics workers, the publish buffers, and how each degrades |
| [Extending MABR](Extending.md) | Stimulus sources, presentation strategies, advance criteria, embedding the engine, custom UIs |
| [API Reference](API-Reference.md) | Every class and function, grouped, with links |
| [Testing](Testing.md) | The no-hardware verification suite |

## Conventions used in these pages

- `mabr.thing.Name` refers to a class or function in the `+mabr` package namespace. `mabr.acq.Engine` lives at [+mabr/+acq/Engine.m](../+mabr/+acq/Engine.m).
- "Block" means one stimulus condition (one frequency/level combination, for example) and the recording made while it played.
- "Sweep" means one stimulus repetition within a block. Blocks contain hundreds of sweeps, which are averaged together.
- Code samples prefixed with `>>` are typed at the MATLAB command window.

---

MABR is proprietary software. Copyright © Daniel Stolzberg, PhD — All Rights Reserved.
See [Copyright.txt](../Copyright.txt).
