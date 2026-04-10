# Getting Started

This guide walks you through your first ABR recording session with MABR, from hardware connection to data acquisition.

---

## Prerequisites

- MABR is installed and the ASIO driver for your audio interface is configured (see [Installation](Installation)).
- Your bioamplifier output is connected to the audio interface input channel.
- Your speaker is connected to the audio interface output channel.
- The subject is prepared and electrodes are in place.

---

## First Launch

Launch MABR from the MATLAB Command Window:

```matlab
MABR
```

The **Control Panel** window opens. MABR automatically adds all required subdirectories to the MATLAB path.

Optionally, specify an alternative root directory:

```matlab
MABR('C:\path\to\MABR')
```

---

## Step 1 – Select Your Audio Device

1. In the Control Panel, open the menu: **Audio → Select Audio Device**.
2. Select your ASIO sound card from the list.
3. MABR remembers your selection between sessions.

> **Tip:** If your device is not listed, verify that the ASIO driver is installed and that MATLAB can see the device (`audiodevinfo`).

---

## Step 2 – Configure Audio Channels

Open **Audio → Define Audio Channels** to map the physical hardware channels:

| Channel | Description |
|---------|-------------|
| **DAC Signal** | Output channel connected to the speaker |
| **DAC Timing** | Output channel used for timing loopback |
| **ADC Signal** | Input channel receiving the bioamplifier output |
| **ADC Timing** | Input channel receiving the timing loopback signal |

The timing loopback (a copy of the stimulus trigger sent back through the hardware) ensures precise alignment between stimulus presentation and the recorded response.

---

## Step 3 – Calibrate Your Speaker

Before recording, calibrate your speaker to ensure stimuli are presented at accurate, repeatable sound levels. See [Calibration](Calibration) for full details.

In brief:
1. Open **Utilities → Calibration** from the Control Panel.
2. Connect a calibrated microphone to the ADC input.
3. Measure microphone sensitivity using a pistonphone or known sound source.
4. Run the calibration sweep and save the resulting calibration file.

---

## Step 4 – Design a Stimulus Schedule

1. Open the **Schedule Design** utility from the Control Panel (Utilities tab).
2. Select a stimulus type (Tone, Noise, Click, or File).
3. Enter the parameter values (frequency range, level range, duration, etc.).
4. Click **Compile** to generate the schedule.
5. Save the schedule design file (`.sch` or `.mat`).

See [Schedule Design](Schedule-Design) for a detailed tutorial.

---

## Step 5 – Configure the Recording Session

In the Control Panel's **Configuration** tab:

| Field | Description |
|-------|-------------|
| **Config File** | Load a previously saved session configuration |
| **Schedule File** | Select the stimulus schedule to use |
| **Calibration File** | Select the calibration file for the chosen schedule |
| **Data Output File** | Set the filename for the recorded `.abr` data |
| **Data Output Directory** | Set the folder where data will be saved |

---

## Step 6 – Set Acquisition Parameters

In the Control Panel's **Control** tab:

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Number of Sweeps** | 1024 | Sweeps to average per schedule row before advancing |
| **Sweep Rate** | 21.1 Hz | Rate at which stimuli are presented |
| **Number of Repetitions** | 1 | How many times to cycle through each schedule row |
| **Sweep Duration** | 10 ms | Duration of the recorded response window |
| **Advance Criterion** | — | Condition for advancing to the next schedule row |

---

## Step 7 – Set Acquisition Filters (Optional)

In the **Acquisition Filter** tab:

- **Bandpass Filter** – Enable and set the high-pass (default: 10 Hz) and low-pass (default: 3000 Hz) corner frequencies.
- **Notch Filter** – Enable to reject line-frequency noise (default: 60 Hz).

---

## Step 8 – Start Recording

1. Toggle the **Start/Stop Acquisition** switch to **Start**.
2. The system begins presenting stimuli and averaging responses.
3. The live ABR waveform updates in real time.
4. Use **Pause** to temporarily halt acquisition without losing data.
5. Use **Advance** to skip to the next schedule row manually.
6. Use **Repeat** to repeat the current stimulus row.
7. Toggle the acquisition switch back to **Stop** when finished.

Data is automatically saved to the configured output file after each schedule row completes.

---

## Step 9 – Analyze Your Data

After recording, use the offline analysis tools in `abr_analysis/`:

```matlab
% Single session analysis
T = parseABRFiles('C:\data\session1');
[S, U, Fs, winIdx] = extractABRResponses(T, [-1 10]);
S = rejectArtifacts(S);
S = filterABRData(S, Fs);
plotABRGrid(S, U, Fs, winIdx);

% Batch analysis across sessions
batchABRAnalysis('C:\data\');
```

See [Data Analysis](Data-Analysis) for the full workflow.

---

## Saving and Loading Configurations

Save the current session configuration from the **Configuration** tab using **Save Config**. Load it again in a future session using **Load Config** (or select from the Config File dropdown). All file paths and parameter values are restored.
