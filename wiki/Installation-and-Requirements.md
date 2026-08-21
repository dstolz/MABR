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

## Audio interface

MABR drives one full-duplex **ASIO** device through `audioPlayerRecorder` (or an
output-only `audioDeviceWriter` under **Stimulation only**). What it asks of that device
is short, and follows entirely from the constants above:

- **192 kHz, full duplex.** `Config.DACSampleRate` is fixed and every stimulus must
  already be rendered at it — MABR never resamples to suit a device. A converter capped
  at 96 kHz cannot be used as-is.
- **Two outputs and two inputs, simultaneously.** `PlayerChannels` is
  `[signal timing]` and `RecorderChannels` is `[ADCsignal ADCtiming]`, both `[1 2]` by
  default: the transducer on output 1, the synthesized timing pulse on output 2, the
  electrode on input 1, and output 2 patched back to input 2 as the timing loop-back.
  Sweep extraction reads that loop-back, and `AcqController.verifyTimingLoop` refuses to
  start a schedule without it.
- **A vendor ASIO driver.** Not ASIO4ALL or a WDM/WASAPI wrapper — the loop-back is a
  latency measurement as much as a trigger, and a wrapper's buffering is neither stable
  nor reported honestly.
- Calibration additionally uses `MicChannel` — the input the measurement microphone is
  patched to, deliberately separate from `RecorderChannels(1)`, since acquisition records
  an electrode where calibration records a mic. On a two-input box they are the same
  physical jack repatched, which is why they are two settings.

### Tested

| Device | Notes |
| --- | --- |
| **Focusrite Scarlett 2i2** (USB) | Used with MABR. Two ins / two outs is exactly the minimum: signal + timing out, electrode + timing loop-back in, and the mic swapped onto an input for calibration. |

### Likely compatible, but **not tested**

Nothing below has been run against MABR. They are listed because they meet the
requirements above on paper — a vendor ASIO driver, 192 kHz full duplex, at least 2 in /
2 out — not because anyone has verified one on a rig. Treat the list as a shortlist to
test, not an endorsement.

| Device | Why it is plausible |
| --- | --- |
| Focusrite Scarlett 4i4 / 8i6 / 18i8 / 18i20 | Same vendor and driver as the tested unit, more channels |
| Focusrite Clarett+ 2Pre / 4Pre | Same driver family, better converters |
| MOTU M2 / M4 / UltraLite-mk5 | Vendor ASIO driver, 192 kHz |
| RME Babyface Pro FS / Fireface UC / UCX II | Vendor ASIO driver with a long-standing reputation for stable low-latency buffering |
| PreSonus Studio 24c / 26c / 68c | Vendor ASIO driver, 192 kHz |
| Steinberg UR22C / UR44C | Vendor ASIO driver, 192 kHz |
| Native Instruments Komplete Audio 2 / 6 MK2 | Vendor ASIO driver, 192 kHz |

Two cautions when reading a spec sheet:

- **Check the generation, not just the model name.** Several of these families had earlier
  revisions capped at 96 kHz — including early Scarlett units. The model number alone does
  not settle it.
- **Check that the rate holds in full duplex at the channel count you need.** Some
  interfaces advertise 192 kHz but halve their usable channel count there.

Rather than trusting either, open **Settings ▸ Audio Device (ASIO)…**, select the device,
and press **Test Device**: `mabr.AudioSettings.probeSampleRate` briefly opens the same
device class the worker would and reports the rate it was actually *granted*. That is a
determination, not a setting — MABR has no rate to change. Then run
`verify_timing_loopback` with `'Testing',false` against the real cabling, which
characterises pulse recovery, latency, jitter, clock drift, and amplitude margin, and
sweep its `'PulseRate'` to find where the device starts dropping pulses. See
[[Verification and Testing]].

If you qualify a device on a rig, add it to the tested table above.

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
