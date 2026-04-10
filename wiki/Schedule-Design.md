# Schedule Design

The **Schedule Design** utility (`abr.ScheduleDesign`) is used to define the set of acoustic stimuli that will be presented during an ABR recording. Each unique combination of stimulus parameters becomes one row in the compiled **Schedule**.

---

## Opening Schedule Design

From the Control Panel's **Utilities** tab, click **Schedule Design**, or launch directly:

```matlab
sd = abr.ScheduleDesign;
```

---

## Workflow Overview

```
1. Set Sampling Rate  →  2. Select Stimulus Type  →  3. Enter Parameters
        ↓
4. Click Compile  →  5. Review Schedule  →  6. Save
```

---

## Step 1 – Set the Sampling Rate

Open **Options → Stimulus Sampling Rate** and enter the sampling rate (Hz) that matches your audio hardware configuration. Higher rates allow higher-frequency stimuli but require more processing resources.

> **Tip:** Set this to the same value you configured in the Calibration Utility and the Control Panel's ASIO settings.

---

## Step 2 – Select the Stimulus Type

Use the **Signal Type** dropdown to choose one of the following:

| Type | Description |
|------|-------------|
| **Tone** | Pure sinusoidal tone bursts parameterized by frequency and level |
| **Noise** | Bandpass-filtered noise bursts parameterized by bandwidth and level |
| **Click** | Brief rectangular pulses parameterized by duration and level |
| **File** | Stimulus waveforms loaded from audio files |

Selecting a type populates the parameter table with the relevant signal properties.

---

## Step 3 – Enter Parameter Values

The **parameter table** shows each configurable property of the selected stimulus type. For each row:

- **Property** – Description of the parameter (includes units).
- **Alternate** – If checked, this parameter will alternate polarity/value on successive sweeps (useful for polarity-alternating stimuli to cancel the cochlear microphonic).
- **Value** – Enter a scalar, a vector, or a valid MATLAB expression.

### Entering Values

Values can be specified as:

| Format | Example | Result |
|--------|---------|--------|
| Scalar | `8` | Single value: 8 |
| Array literal | `[4 8 16 32]` | Four values: 4, 8, 16, 32 |
| Colon operator | `20:10:80` | Values: 20, 30, 40, 50, 60, 70, 80 |
| `linspace` | `linspace(0,80,9)` | 9 evenly spaced values from 0 to 80 |
| `octaves` | `octaves(4,64,6)` | 6 octave-spaced values from 4 to 64 kHz |

> See [`octaves`](API-Reference#octaves) for details on the frequency-spacing helper.

### Common Tone Parameters

| Parameter | Unit | Notes |
|-----------|------|-------|
| **Frequency** | kHz | Must be below Nyquist (Fs/2). Use `octaves(low, high, n)` for audiometric spacing. |
| **Sound Level** | dB SPL | Requires a valid calibration file to convert to actual voltages. |
| **Start Phase** | deg | Starting phase of the sinusoid (typically 0°). |
| **Duration** | ms | Stimulus duration. |
| **Rise/Fall Time** | ms | Duration of the onset/offset gate window. |
| **Window Function** | — | Gating function applied to the onset/offset (e.g., Hann, Blackman). |

### Click Parameters

| Parameter | Unit | Notes |
|-----------|------|-------|
| **Duration** | ms | Duration of the rectangular pulse (e.g., 0.1 ms). |
| **Sound Level** | dB SPL | Calibrated amplitude. |

### Noise Parameters

| Parameter | Unit | Notes |
|-----------|------|-------|
| **High-Pass Corner** | Hz | Lower edge of the noise bandwidth. |
| **Low-Pass Corner** | Hz | Upper edge of the noise bandwidth. |
| **Sound Level** | dB SPL | Calibrated amplitude. |

---

## Step 4 – Preview the Stimulus

Click **Plot** to display a waveform preview of the stimulus with the current parameter settings. Use this to confirm the stimulus looks correct before compiling.

---

## Step 5 – Compile the Schedule

Click **Compile** to generate a **Schedule** from all parameter combinations. MABR enumerates every combination of the specified parameter values and creates one schedule row per combination.

**Example:** A Tone schedule with:
- Frequency: `octaves(4, 64, 6)` → 6 values
- Sound Level: `20:10:80` → 7 values

…produces 6 × 7 = **42 schedule rows**.

After compiling, the [Schedule](Schedule) window opens automatically.

---

## Step 6 – Save the Schedule Design

Use **File → Save Schedule Design** to save the parameter configuration to a file. This lets you reload and re-compile the schedule in future sessions without re-entering all parameters.

Use **File → Load Schedule Design** to restore a previously saved design.

---

## The Compiled Schedule

See [Schedule](Schedule) for documentation on how to view, reorder, and selectively enable schedule rows before and during recording.

---

## Tips and Best Practices

- **Frequency range for tones:** Cover from your lowest frequency of interest up to just below the Nyquist rate to ensure reliable calibration interpolation.
- **Polarity alternation:** Enable **Alternate** on the Sound Level or Start Phase parameters to present alternating-polarity stimuli. Averaging alternating-polarity responses cancels the stimulus artifact and the cochlear microphonic, isolating the neural ABR.
- **Level ordering:** Present stimuli from high to low levels (descending order) to minimize the effect of residual auditory adaptation on threshold estimates.
- **Saving designs:** Always save both the schedule design file and the compiled schedule file so you can reproduce the experiment exactly.
