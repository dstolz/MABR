# Installation

This page describes the system requirements and the steps needed to install and configure MABR.

---

## System Requirements

| Requirement | Details |
|-------------|---------|
| **Operating System** | Windows 10 or Windows 11 (64-bit). macOS and Linux are not yet supported. |
| **MATLAB** | R2019b or later recommended |
| **Required Toolboxes** | Signal Processing Toolbox, DSP System Toolbox |
| **Optional Toolboxes** | Statistics and Machine Learning Toolbox, Image Processing Toolbox, Curve Fitting Toolbox, Parallel Computing Toolbox |
| **Audio Hardware** | An ASIO-compatible sound card or audio interface with simultaneous input and output capability |
| **Bioamplifier** | A differential bioamplifier with appropriate gain for recording auditory brainstem responses (e.g. 10,000×) |

> **Note:** Some offline analysis features (threshold estimation via permutation testing) require the Statistics and Machine Learning Toolbox and Image Processing Toolbox. Parallel processing with `parfor` requires the Parallel Computing Toolbox.

---

## ASIO Driver

MABR uses ASIO (Audio Stream Input/Output) drivers for low-latency audio playback and recording.

1. Download and install an ASIO driver for your audio interface (e.g., the manufacturer's ASIO driver or [ASIO4ALL](https://asio4all.org/) for consumer sound cards).
2. Verify that the ASIO driver appears in MATLAB by running:
   ```matlab
   audiodevinfo
   ```
   Your ASIO device should appear in the list of available devices.

---

## Installing MABR

### Option 1 – Clone from GitHub

```bash
git clone https://github.com/dstolz/MABR.git
```

### Option 2 – Download ZIP

1. Go to the [MABR GitHub repository](https://github.com/dstolz/MABR).
2. Click **Code → Download ZIP**.
3. Extract the archive to a folder of your choice (e.g., `C:\MATLAB\MABR`).

---

## Adding MABR to Your MATLAB Path

MABR manages its own paths internally when launched. Simply call the main entry point and all required subdirectories are added automatically:

```matlab
MABR
```

If you prefer a permanent path setup, you can add the MABR root directory to the MATLAB path via **Home → Set Path**, but this is not required.

---

## Verifying the Installation

After launching `MABR` in MATLAB, the **Control Panel** window should appear. If you see error messages in the MATLAB Command Window, check:

1. That all required toolboxes are installed (`ver` in the Command Window lists installed toolboxes).
2. That an ASIO audio device is available (`audiodevinfo`).
3. That the MABR folder and its subfolders are accessible.

---

## External Dependencies

The `external/` folder contains the following third-party code:

| File | Purpose |
|------|---------|
| `getjframe.m` | Java-based helper for platform-specific window features (Windows only) |
| `mingw.mlpkginstall` | MinGW compiler support package installer |

These are bundled with MABR and do not require separate installation.
