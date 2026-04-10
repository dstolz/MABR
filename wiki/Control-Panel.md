# Control Panel

The **Control Panel** (`abr.ControlPanel`) is the central hub of MABR. It manages hardware selection, stimulus presentation, real-time signal acquisition, and provides access to all other utilities.

---

## Opening the Control Panel

```matlab
MABR          % uses the default MABR root directory
% or
h = MABR;     % returns the ControlPanel handle
```

---

## Menu Bar

### Audio Menu

| Menu Item | Description |
|-----------|-------------|
| **Keep Control Panel on Top** | Keeps the Control Panel window above all other windows. (Feature may be limited in some MATLAB versions.) |
| **Adjust ASIO Settings** | Launches your audio interface's external ASIO configuration utility. The sampling rate and frame length are set automatically by MABR; additional manual adjustments should rarely be needed. |
| **Select Audio Device** | Choose which ASIO-compatible audio device to use for stimulus output and bioelectric signal input. MABR requires a single device for both output and input simultaneously. The selection is remembered across sessions. |
| **Define Audio Channels** | Map logical signal roles (DAC signal, DAC timing, ADC signal, ADC timing) to physical hardware channels on the selected audio device. |

---

## Tabs

The Control Panel is organized into the following tabs:

### Configuration Tab

Use this tab to set up the files for an experiment. Save or load a configuration file to quickly restore a session's full setup.

> ✓ All file paths and parameter values are restored when loading a configuration file.

| Control | Description |
|---------|-------------|
| **Config File** (dropdown) | Select a previously saved configuration file. Selecting a file immediately updates all other fields. |
| **Schedule File** (dropdown) | Choose the stimulus schedule (`.sch`) controlling the order and parameters of stimuli. |
| **Calibration File** (dropdown) | Select the calibration file that matches the stimuli in the chosen schedule. |
| **Data Output File** (dropdown) | Set the filename for the output `.abr` data file. Use the dropdown to choose a different file in the same directory. |
| **Data Output Directory** (dropdown) | Set the folder in which data files are saved. The dropdown shows recently used directories. |

---

### Control Tab

The main panel for starting, stopping, and parameterizing an ABR recording.

| Control | Type | Default | Description |
|---------|------|---------|-------------|
| **Number of Sweeps** | Numeric spinner | 1024 | Number of stimulus presentations (sweeps) to average before moving to the next schedule row. |
| **Sweep Rate** | Numeric spinner | 21.1 Hz | Frequency at which individual stimuli are presented. Lower rates reduce the risk of auditory fatigue; higher rates speed up acquisition. |
| **Number of Repetitions** | Numeric spinner | 1 | How many times each schedule row is repeated before advancing. |
| **Sweep Duration** | Numeric spinner | 10 ms | Length of the recorded response window following each stimulus onset. |
| **Advance Schedule Criterion** | Dropdown | — | The condition that triggers automatic advancement to the next schedule row. Built-in options include advancing after a fixed number of sweeps or after a correlation-based signal quality threshold is met. Select **Define** to specify a custom advance function. |
| **Advance** | Button | — | Manually advance to the next schedule row (or the next repetition if Repetitions > 1). |
| **Repeat** | Toggle button | Off | When active, the current stimulus row is presented repeatedly without advancing. Click again to deactivate. |
| **Pause** | Toggle button | Off | Temporarily suspend stimulus presentation and acquisition. Click again to resume. No data is lost during a pause. |
| **Start / Stop Acquisition** | Toggle switch | Stop | Master control. Flip to **Start** to begin the experiment; flip back to **Stop** when finished. |

---

### Acquisition Filter Tab

Optional digital filters applied to the incoming biosignal before averaging.

| Control | Description |
|---------|-------------|
| **High-Pass Frequency Corner** | Lower cutoff of the bandpass filter (default: 10 Hz). Removes slow baseline drifts. |
| **Low-Pass Frequency Corner** | Upper cutoff of the bandpass filter (default: 3000 Hz). Removes high-frequency noise above the ABR signal band. |
| **Filter Enable Switch** | Enable or disable the bandpass filter. |
| **Notch Filter** | Enables a digital bandstop filter centered on the line-noise frequency (default: 60 Hz, ±1 Hz). Set to **Disabled** to turn off. |

> **Filter Design Note:** Filters are implemented as FIR bandpass filters using MATLAB's `designfilt`. The filter order is set via the **adcFilterOrder** property (default: 10). Changing the filter parameters causes the filter to be redesigned automatically.

---

### Utilities Tab

Provides buttons to launch the other MABR utilities:

- **Calibration** – Opens the [Calibration Utility](Calibration).
- **Schedule Design** – Opens the [Schedule Design](Schedule-Design) GUI.
- **Trace Organizer** – Opens the [Trace Organizer](Trace-Organizer) for viewing saved ABR waveforms.

---

## Real-Time Display

While acquisition is running, MABR displays a live averaged ABR waveform. The display updates after each sweep block, allowing you to monitor response quality in real time.

---

## Advanced Acquisition Control

### Schedule Advance Criteria

MABR supports pluggable advance criteria. Two built-in functions are provided in `advanceFcns/`:

| Function | Description |
|----------|-------------|
| `abr_adv_num_sweeps` | Advance after a specified number of sweep repetitions are completed for the current row. |
| `abr_adv_corr_thr` | Advance based on a cross-correlation quality threshold (experimental). |

**Creating a custom advance function:**

1. Create a new `.m` file in `advanceFcns/` that follows the function signature:
   ```matlab
   function nextIdx = my_advance_criterion(app)
   ```
2. `app` is the `ControlPanel` handle, giving access to schedule and sweep counts.
3. Return `nextIdx` as the index of the next schedule row, or `inf` to signal the end of the session.
4. Select **Define** in the Advance Criterion dropdown to point to your function.

---

## Programmatic Access

The `ControlPanel` object is returned when capturing the output of `MABR`:

```matlab
h = MABR;
```

The `h` handle gives programmatic access to all ABR acquisition parameters. For example:

```matlab
h.ABR.numSweeps  = 2048;   % change sweep count
h.ABR.sweepRate  = 40;     % change presentation rate (Hz)
```

> See [API Reference](API-Reference) for a full list of accessible properties and methods.
