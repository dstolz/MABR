# API Reference

This page documents the key classes, functions, and helpers provided by MABR. For detailed usage examples see [Data Analysis](Data-Analysis), [Getting Started](Getting-Started), and the individual GUI pages.

---

## Entry Point

### `MABR`

```matlab
MABR
MABR(rootDir)
h = MABR(...)
```

Adds all MABR subdirectories to the MATLAB path and opens the [Control Panel](Control-Panel).

| Argument | Description |
|----------|-------------|
| `rootDir` | (Optional) Root directory of the MABR installation. Defaults to the directory containing `MABR.m`. |
| `h` | (Optional output) Handle to the `abr.ControlPanel` object. |

---

## Core Classes (`+abr/`)

### `abr.ABR`

The data object encapsulating one ABR acquisition state.

**Key Properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `DAC` | `abr.Buffer` | — | Digital-to-analog (output) buffer |
| `ADC` | `abr.Buffer` | — | Analog-to-digital (input) buffer |
| `SIG` | signal object | — | Stimulus signal definition |
| `audioDevice` | `char` | — | Selected ASIO audio device string |
| `sweepRate` | `double` | 21.1 Hz | Stimulus presentation rate |
| `numSweeps` | `double` | 1024 | Sweeps to average per schedule row |
| `adcWindow` | `[1×2] double` | `[0 0.01]` s | ADC recording window `[start stop]` |
| `adcFilterHP` | `double` | 10 Hz | High-pass filter corner frequency |
| `adcFilterLP` | `double` | 3000 Hz | Low-pass filter corner frequency |
| `adcFilterOrder` | `double` | 10 | FIR filter order |
| `adcNotchFilterFreq` | `double` | 60 Hz | Notch filter center frequency |
| `adcUseBPFilter` | `logical` | `true` | Enable bandpass filter |
| `adcUseNotchFilter` | `logical` | `true` | Enable notch filter |
| `ADCsignalCh` | `uint8` | 1 | ADC channel index for biosignal |
| `ADCtimingCh` | `uint8` | 2 | ADC channel index for timing loopback |
| `DACsignalCh` | `uint8` | 1 | DAC channel index for stimulus |
| `DACtimingCh` | `uint8` | 2 | DAC channel index for timing output |

**Dependent Properties:**

| Property | Description |
|----------|-------------|
| `adcDecimationFactor` | Ratio of DAC to ADC sample rates |
| `sweepCount` | Number of sweeps collected so far |
| `adcWindowTVec` | Time vector for the ADC window (seconds) |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `selectAudioDevice(obj, deviceString)` | Select the ASIO audio device |
| `setupAudioChannels(obj)` | Open the audio channel configuration GUI |
| `createADCfilt(obj)` | (Re)design the ADC bandpass and notch filters |
| `analysis(obj, type, varargin)` | Run a named analysis (e.g., `'rms'`, `'corr'`) |
| `to_struct(obj)` | Serialize the ABR object to a plain struct for saving |

---

### `abr.Buffer`

Represents a circular data buffer for either DAC or ADC streams.

**Key Properties:**

| Property | Description |
|----------|-------------|
| `Data` | Raw sample data vector |
| `SampleRate` | Sampling rate (Hz) |
| `SweepOnsets` | Sample indices of each sweep onset |
| `SweepDuration` | Duration of a single sweep (seconds) |

---

### `abr.Subject`

Stores subject metadata.

```matlab
subj = abr.Subject(id, alias, dob, scientist, note)
```

| Property | Description |
|----------|-------------|
| `ID` | Subject identifier string |
| `Alias` | Subject alias or nickname |
| `DOB` | Date of birth string |
| `Scientist` | Name of the experimenter |
| `Note` | Free-text notes |
| `dataFile` | Path to the subject's data file |
| `lastUpdated` | Timestamp of the last property change (read-only) |

---

### `abr.SoundCalibration`

Stores and applies sound calibration data.

**Key Methods:**

| Method | Description |
|--------|-------------|
| `calibration_is_valid` | Returns `true` if a valid calibration has been loaded |
| `estimate_calibrated_voltage(freq, levelDB)` | Returns the DAC voltage required to produce `levelDB` dB SPL at `freq` Hz |
| `plot(obj)` | Plot the raw calibration data |
| `plot_calibration(obj)` | Plot the calibration correction curve |

---

## Signal Definitions (`+abr/+sigdef/`)

### `abr.sigdef.Signal` (abstract base class)

All stimulus types inherit from this class.

**Common Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `soundLevel` | `sigProp` | Stimulus amplitude in dB SPL |
| `duration` | `sigProp` | Stimulus duration |
| `windowFcn` | `sigProp` | Onset/offset gating window function |
| `windowRFTime` | `sigProp` | Rise/fall time for gating |
| `Calibration` | `SoundCalibration` | Associated calibration object |
| `informativeParams` | `cell` | Names of parameters included in file names and analysis |

### `abr.sigdef.sigs.Tone`

Pure-tone stimulus.

**Additional Properties:** `frequency`, `startPhase`

**Constructor:**
```matlab
sig = abr.sigdef.sigs.Tone(frequency, soundLevel, startPhase)
```

### `abr.sigdef.sigs.Click`

Brief rectangular-pulse stimulus.

**Constructor:**
```matlab
sig = abr.sigdef.sigs.Click(duration)
```

### `abr.sigdef.sigs.Noise`

Bandpass-filtered noise stimulus.

**Additional Properties:** `highPassFreq`, `lowPassFreq`

### `abr.sigdef.sigs.File`

Stimulus waveform loaded from an audio file.

---

### `abr.sigdef.sigProp`

A container for a single signal parameter that tracks its value, units, description, and whether it is active.

**Key Properties:**

| Property | Description |
|----------|-------------|
| `Value` | Parameter value (scalar, vector, or MATLAB expression string) |
| `realValue` | Evaluated numeric value(s) |
| `Unit` | Unit string (e.g., `'kHz'`, `'dB SPL'`) |
| `DescriptionWithUnit` | Human-readable description including units |
| `Alternate` | Whether this parameter alternates on successive sweeps |
| `Active` | Whether this parameter is used |

---

## Schedule Classes (`+abr/`)

### `abr.Schedule`

Manages the stimulus schedule table during acquisition.

**Key Properties:**

| Property | Description |
|----------|-------------|
| `filename` | Path to the loaded schedule file |
| `selectedData` | Logical vector of enabled (checked) rows |
| `sigArray` | Array of signal objects, one per schedule row |

**Key Menu / Button Actions:**

| Action | Description |
|--------|-------------|
| Load / Save | Load or save a schedule file |
| Sort on Column | Sort rows by the selected column (ascending/descending toggle) |
| Reset | Restore the original schedule order |
| Deselect All | Uncheck all rows |
| Every Other | Check every other row |
| Custom | Open a dialog to define a custom selection |
| Toggle | Invert the current row selection |
| Remove Rows | Delete the selected rows from the schedule |

### `abr.ScheduleDesign`

GUI for designing stimulus schedules. See [Schedule Design](Schedule-Design).

---

## Trace Classes (`+abr/+traces/`)

### `abr.traces.Organizer`

Interactive waveform display. See [Trace Organizer](Trace-Organizer).

**Key Properties:**

| Property | Default | Description |
|----------|---------|-------------|
| `Traces` | `[]` | Array of `abr.traces.Trace` objects |
| `YScaling` | 0.7 | Vertical amplitude scale factor |
| `YSpacing` | 1.0 | Vertical spacing between traces |
| `SortBy` | `{}` | Cell array of property names for sorting |
| `SortOrder` | `{}` | `'ascend'` or `'descend'` for each sort key |
| `groupColors` | `lines` | Color matrix for groups (`N×3`) |

### `abr.traces.Trace`

A single ABR waveform with metadata.

### `abr.traces.Group`

A named group of `Trace` objects.

---

## Analysis Functions (`+abr/+analysis/`)

### `abr.analysis.RMS`

Computes root-mean-square amplitude of ABR data.

### `abr.analysis.CorrCoef`

Computes the correlation coefficient between split-halves of the averaged ABR, used as a quality metric for automatic schedule advancement.

### `abr.analysis.Peaks`

Detects and labels peaks in ABR waveforms.

---

## Offline Analysis Functions (`abr_analysis/`)

| Function | Signature | Description |
|----------|-----------|-------------|
| `parseABRFiles` | `T = parseABRFiles(path, filePattern=re)` | Parse `.abr` files into a table |
| `extractABRResponses` | `[S,U,Fs,winIdx] = extractABRResponses(T, win, ...)` | Extract and optionally filter sweep epochs |
| `rejectArtifacts` | `[S,artInd] = rejectArtifacts(S, ...)` | Remove artifact sweeps |
| `filterABRData` | `S = filterABRData(S, Fs)` | Bandpass filter all responses |
| `plotABRGrid` | `ax = plotABRGrid(S, U, Fs, winIdx, ...)` | Grid plot of mean waveforms |
| `plotABRThresholds` | `plotABRThresholds(thresh, freqs, ...)` | Audiogram plot |
| `abrPermutationThreshold` | `[th,PR,M] = abrPermutationThreshold(S, rowVals, ...)` | Permutation-based threshold estimation |
| `batchABRAnalysis` | `[th,mdls] = batchABRAnalysis(rootPth, ...)` | Full batch pipeline across sessions |
| `getABRSessions` | `sessions = getABRSessions(rootPth)` | List session folders under `rootPth` |
| `extractSessionName` | `name = extractSessionName(sessionPath)` | Extract a human-readable session name |
| `permtest` | `[p, result] = permtest(data, ...)` | Two-sided cluster-based permutation test |

See [Data Analysis](Data-Analysis) for detailed documentation of each function.

---

## Helper Functions (`helpers/`)

### `octaves`

```matlab
v = octaves(a, b)
v = octaves(a, b, n)
```

Returns `n` values (default: 10) equally spaced on a log₂ (octave) scale between `a` and `b`.

**Example:**
```matlab
octaves(1, 32, 6)
% ans = 1  2  4  8  16  32
```

### `log10space`

```matlab
v = log10space(a, b, n)
```

Returns `n` values equally spaced on a log₁₀ scale between `a` and `b`.

### `Fsp`

Computes the Fsp statistic used as a signal-quality metric for ABR recordings. Fsp is the ratio of the variance in the single-point frequency bin to the variance of adjacent frequency bins in the response spectrum.

### `vprintf`

```matlab
vprintf(verbosity, level, fmt, varargin)
```

Verbosity-gated `fprintf` wrapper. Messages are printed only when `verbosity >= level`.

### `timeout`

Utility for implementing non-blocking time-based conditions in acquisition loops.

### `figxy2axisxy`

Converts figure coordinates to axis data coordinates.

### `seppuku`

Graceful self-termination of an object/application; closes handles and cleans up timers.

---

## Advance Criterion Functions (`advanceFcns/`)

| Function | Description |
|----------|-------------|
| `abr_adv_num_sweeps(app, nReps)` | Advance after `nReps` repetitions of the current row are complete |
| `abr_adv_corr_thr(app)` | Advance when a correlation-based quality threshold is met (experimental) |

Custom advance functions must follow the signature:
```matlab
function nextIdx = my_advance_function(app)
```
where `app` is the `ControlPanel` handle and `nextIdx` is the target schedule row index (or `inf` to end the session).
