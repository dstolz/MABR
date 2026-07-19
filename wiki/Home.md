# MABR – MATLAB Auditory Brainstem Response Toolbox

Welcome to the **MABR** wiki. MABR is a MATLAB toolbox for recording, calibrating, and analyzing Auditory Brainstem Responses (ABRs) in a research setting. It provides a fully integrated graphical environment for stimulus generation, data acquisition, real-time visualization, and offline analysis.

---

## Table of Contents

| Page | Description |
|------|-------------|
| [Installation](Installation) | System requirements, dependencies, and setup |
| [Getting Started](Getting-Started) | Step-by-step guide to your first ABR recording |
| [Control Panel](Control-Panel) | Reference for the main acquisition GUI |
| [Calibration](Calibration) | How to calibrate sound stimuli |
| [Schedule Design](Schedule-Design) | How to create and manage stimulus schedules |
| [Trace Organizer](Trace-Organizer) | Visualizing and managing ABR waveforms |
| [Data Analysis](Data-Analysis) | Batch processing and threshold estimation |
| [API Reference](API-Reference) | Function and class reference |

---

## What is MABR?

MABR (MATLAB Auditory Brainstem Response) is a comprehensive toolbox that guides you through every stage of an ABR experiment:

1. **Hardware Setup** – Select your ASIO-compatible sound card and configure input/output channels.
2. **Sound Calibration** – Measure the acoustic output of your speaker system so that stimuli are presented at known, reproducible sound pressure levels.
3. **Stimulus Scheduling** – Design a set of tone-burst, noise-burst, click, or custom-file stimuli parameterized by frequency, level, duration, etc.
4. **Data Acquisition** – Present stimuli and record the bioelectric response while viewing real-time averaged waveforms.
5. **Offline Analysis** – Load saved `.abr` data files, reject artifacts, filter, and estimate hearing thresholds automatically.

---

## Software Architecture Overview

```
MABR/
├── MABR.m                 Entry point – launches the Control Panel
├── +abr/                  Core package
│   ├── @ControlPanel/     Main acquisition GUI
│   ├── @CalibrationUtility/  Sound calibration GUI
│   ├── @ScheduleDesign/   Stimulus schedule designer GUI
│   ├── @Schedule/         Stimulus schedule viewer/editor GUI
│   ├── @ABR/              ABR data object (DAC/ADC buffers, filters)
│   ├── @Runtime/          Real-time acquisition engine
│   ├── @Subject/          Subject metadata
│   ├── +traces/           Trace Organizer system
│   └── +sigdef/           Signal definitions (Tone, Noise, Click, File)
├── abr_analysis/          Offline batch analysis functions
├── advanceFcns/           Custom schedule-advance criterion functions
├── helpers/               Utility functions
└── external/              Third-party code
```

---

## Quick Links

- [System Requirements](Installation#system-requirements)
- [Running MABR for the First Time](Getting-Started#first-launch)
- [Creating a Tone Schedule](Schedule-Design#tone-stimulus)
- [Calibrating Your Speaker](Calibration#running-a-calibration)
- [Automated Threshold Estimation](Data-Analysis#threshold-estimation)

---

## License & Contact

MABR is proprietary software.  
Copyright © Daniel Stolzberg, PhD – All Rights Reserved.  
Contact: <daniel.stolzberg@gmail.com>
