# Calibration

The **Calibration Utility** (`abr.CalibrationUtility`) measures and corrects for the acoustic transfer function of your speaker system so that stimuli are presented at known, repeatable sound pressure levels (dB SPL).

---

## Overview

Sound calibration in MABR is a two-step process:

1. **Measure microphone sensitivity** – Determine how much voltage your microphone-amplifier system produces per Pascal of acoustic pressure.
2. **Run the calibration sweep** – Present stimuli at a known voltage, measure the resulting SPL, and compute the correction factors needed to reach a target level.

The resulting calibration data is saved to a `.cal` file and loaded before each ABR recording session.

---

## Opening the Calibration Utility

From the Control Panel's **Utilities** tab, click **Calibration**, or launch it directly:

```matlab
cal = abr.CalibrationUtility;
```

---

## Hardware Setup Panel

Before calibrating, configure the audio hardware:

| Control | Description |
|---------|-------------|
| **Audio Device** (dropdown) | Select the same ASIO device that will be used for ABR recording. |
| **Sampling Rate** (dropdown) | Choose the sampling rate. Use the highest value supported by your system unless instability occurs. This setting will be used during ABR acquisition as well. |

> **Tip:** The sampling rate determines the Nyquist limit. For broadband calibration up to 64 kHz, you need at least a 128 kHz sampling rate. Most sound cards support 192 kHz or higher.

---

## Microphone Sensitivity Panel

Accurate SPL estimates depend on knowing how many millivolts your microphone and preamplifier produce per Pascal of sound pressure.

### Method 1 – Pistonphone or Reference Speaker (Recommended)

1. Place your calibrated microphone in the pistonphone cavity (or in front of a reference speaker producing a known level).
2. Enter the **Frequency (Hz)** of the calibration tone.
3. Enter the known **Sound Level (dB SPL)**.
4. Click **Sample** to measure the voltage.
5. Inspect the time- and frequency-domain plots to confirm a clean sinusoid at the expected frequency.
6. MABR computes and stores the sensitivity (mV/Pa).

### Method 2 – Microphone Specification Sheet

1. Obtain the microphone sensitivity from the data sheet (e.g., −40 dBV/Pa = 10 mV/Pa at 94 dB SPL).
2. Set **Sound Level** to `94` (1 Pascal = 94 dB SPL).
3. Enter the **Measured Voltage (mV)** from the spec sheet, adjusted for any additional amplification in your preamplifier (e.g., ×10 for 20 dB gain).
4. Skip clicking **Sample** (the frequency field is ignored in this method).

---

## Stimulus Selection Panel

Choose the type of stimulus to calibrate:

| Type | Notes |
|------|-------|
| **Tone** | Calibrated by sweeping across a range of frequencies. Interpolation (makima) is used to estimate the calibrated voltage at any intermediate frequency. Set a range from the lowest frequency of interest to just below the Nyquist rate (Fs/2). |
| **Noise** | Calibrated using a look-up table. Enter the exact parameter values (e.g., bandwidth) that you plan to use during the ABR experiment. |
| **Click** | Calibrated using a look-up table. Enter the click duration(s) you intend to use. |
| **File** | Calibrate stimuli loaded from audio files. |

Click **Modify** to open the stimulus parameter editor for the selected type.

---

## Running a Calibration

### Setup

1. Connect the calibrated microphone to the ADC input channel.
2. Position the microphone at the same location (and distance) as the subject's ear.
3. Ensure the speaker is connected to the DAC output channel.
4. Specify the **Norm Level (dB)** – the target SPL for the normalized calibrated stimulus. This is typically the maximum level you intend to present. If the required voltage exceeds the sound card's 1 V output limit, additional amplification is needed.

### Procedure

1. Click **Run** to begin.
2. MABR presents the calibration stimuli at full voltage and measures the acoustic output.
3. Results are plotted: you should see a relatively flat SPL curve across frequencies.
4. MABR automatically plays the stimuli a second time at the computed calibrated voltages. The resulting levels should align with the target Norm Level.
5. A save dialog prompts you to save the calibration file (`.cal`).

### Interpreting the Results

- A **flat calibration curve** (±3 dB across the frequency range) indicates a well-behaved speaker system.
- Large deviations at specific frequencies may indicate resonances or anti-resonances in the acoustic coupling and are normal.
- If the required voltage exceeds 1 V at any frequency, MABR warns you. Add a power amplifier or reduce the target Norm Level.

---

## Loading a Calibration File

In the **Configuration** tab of the Control Panel:

1. Select the schedule that the calibration applies to.
2. Use the **Calibration File** dropdown to select the corresponding `.cal` file.

MABR applies the calibration voltage corrections automatically during stimulus generation.

---

## Saving and Loading Calibration Data

Use the **File** menu in the Calibration Utility:

- **Save Calibration Data** – Save the current calibration to a `.cal` file.
- **Load Calibration Data** – Reload a previously saved calibration.

Calibration files can be reused across sessions as long as the hardware setup (speaker position, microphone, preamplifier gain) remains unchanged.

---

## Tips

- Re-calibrate whenever you change the speaker, microphone, preamplifier, or physical placement.
- Include calibration sweeps that cover your full stimulus frequency and level range.
- For tone stimuli, span at least from the lowest frequency you plan to test to 0.45 × Fs (just below Nyquist) to allow reliable interpolation.
