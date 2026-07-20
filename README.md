# MABR

MATLAB Auditory Brainstem Response software for stimulus presentation, real-time acquisition, and offline analysis of ABR data.

The acquisition app has been rewritten ground-up into a single `+mabr` namespace with a modern acquisition engine built on the Parallel Computing Toolbox (a warm parpool worker + a memory-mapped ring buffer), a decoupled data model and GUI, and a clean boundary where an external package supplies precomputed, calibrated stimulus waveforms. Saved `.abr` files remain compatible with the offline `abr_analysis/` pipeline. See `MABR Complete Refactor — Ground-Up Rewrite.md` for the design and `CLAUDE.md` for an architecture map.

> **Note:** the `wiki/` pages below document the pre-rewrite Control Panel UI and stimulus/calibration/schedule features (now supplied by an external package); they have not yet been updated for the `+mabr` rewrite.

## Documentation

Comprehensive documentation is available in the [`wiki/`](wiki/) directory:

| Page | Description |
|------|-------------|
| [Home](wiki/Home.md) | Overview and navigation |
| [Installation](wiki/Installation.md) | System requirements and setup |
| [Getting Started](wiki/Getting-Started.md) | Step-by-step guide to your first recording |
| [Control Panel](wiki/Control-Panel.md) | Main acquisition GUI reference |
| [Calibration](wiki/Calibration.md) | Sound calibration guide |
| [Schedule Design](wiki/Schedule-Design.md) | Stimulus schedule design |
| [Trace Organizer](wiki/Trace-Organizer.md) | ABR waveform visualization |
| [Data Analysis](wiki/Data-Analysis.md) | Batch processing and threshold estimation |
| [API Reference](wiki/API-Reference.md) | Function and class reference |

## Quick Start

```matlab
MABR   % launch the acquisition app (mabr.ui.App)
```

Please contact me directly if you are interested in using this toolbox.

Copyright (C) Daniel Stolzberg, PhD - All Rights Reserved
Unauthorized copying of this file, via any medium is strictly prohibited
Proprietary and confidential
Written by Daniel Stolzberg, PhD <daniel.stolzberg@gmail.com>, May 2019
