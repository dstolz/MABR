# Data Analysis

MABR provides a suite of MATLAB functions in the `abr_analysis/` directory for loading, filtering, artifact rejection, visualization, and automated threshold estimation from saved ABR data files.

---

## Data File Format

Each ABR recording is saved as a `.abr` file (a MATLAB `.mat` file). Each file contains a variable `ABR_Data` with the following structure:

| Field | Description |
|-------|-------------|
| `ABR_Data.ADC` | ADC buffer object containing the raw recorded data (`ADC.Data`), sweep onset sample indices (`ADC.SweepOnsets`), and sampling rate (`ADC.SampleRate`) |
| `ABR_Data.SIG` | Stimulus signal parameters including `informativeParams` (list of parameter names), individual parameter values, and calibration data |
| `ABR_Data.StartTime` | Timestamp string recording when acquisition began |

---

## Analysis Workflow

The recommended offline analysis pipeline is:

```
parseABRFiles  →  extractABRResponses  →  rejectArtifacts
      ↓
filterABRData  →  plotABRGrid  →  abrPermutationThreshold  →  plotABRThresholds
```

---

## Functions

### `parseABRFiles`

Scans a folder for `.abr` files and assembles a MATLAB table with one row per file.

```matlab
T = parseABRFiles(sessionPath)
T = parseABRFiles(sessionPath, filePattern=expr)
```

**Inputs:**

| Argument | Description |
|----------|-------------|
| `sessionPath` | Path to the folder containing `.abr` files. Defaults to `cd`. |
| `filePattern` | Regular expression to filter file names. Default: `"^SUBJ*"`. |

**Output:** A `table` with columns for each stimulus parameter (e.g., `frequency`, `soundLevel`), plus `timestamp`, `fileName`, and `folder`.

**Example:**
```matlab
T = parseABRFiles("C:\data\session1", filePattern="^SUBJ_(\d+)_Frequency");
```

---

### `extractABRResponses`

Loads each file listed in the table `T`, segments the continuous ADC recording into per-sweep epochs, and groups them by unique stimulus parameter combinations.

```matlab
[S, U, Fs, winIdx] = extractABRResponses(T, win)
[S, U, Fs, winIdx] = extractABRResponses(T, win, Name=Value, ...)
```

**Inputs:**

| Argument | Default | Description |
|----------|---------|-------------|
| `T` | — | Table from `parseABRFiles` |
| `win` | — | Two-element `[t0 t1]` window in **milliseconds** relative to stimulus onset |
| `lowpass` | `true` | Apply default low-pass filter (Fpass=3000 Hz, Fstop=4200 Hz) |
| `highpass` | `true` | Apply default high-pass filter (Fstop=150 Hz, Fpass=300 Hz) |
| `LowpassHd` | `[]` | Custom low-pass filter object (overrides default) |
| `HighpassHd` | `[]` | Custom high-pass filter object (overrides default) |
| `FilterMethod` | `"filtfilt"` | `"filtfilt"` (zero-phase) or `"filter"` (causal) |

**Outputs:**

| Variable | Description |
|----------|-------------|
| `S` | Cell array sized by unique values of each stimulus parameter. Each non-empty cell is `[nSamples × nSweeps]`. |
| `U` | Struct of unique values for each stimulus parameter (e.g., `U.frequency`, `U.soundLevel`). |
| `Fs` | ADC sampling rate (Hz) |
| `winIdx` | Sample offsets used for extraction (relative to onset) |

**Example:**
```matlab
[S, U, Fs, winIdx] = extractABRResponses(T, [-1 10]);
```

---

### `rejectArtifacts`

Identifies and removes artifact trials (individual sweeps) from each cell of `S` using outlier detection on a per-trial feature.

```matlab
S = rejectArtifacts(S)
[S, artInd] = rejectArtifacts(S, Name=Value, ...)
```

**Options:**

| Name | Default | Description |
|------|---------|-------------|
| `respInd` | `[]` | Logical vector selecting the response window samples. Default: use all samples. |
| `feature` | `"absPeak"` | Trial-level feature for outlier detection: `"rms"`, `"std"`, `"meanabs"`, `"peak2peak"`, `"posPeak"`, `"negPeak"`, `"absPeak"` |
| `rmMethod` | `"median"` | Outlier detection method passed to `isoutlier`: `"median"`, `"mean"`, `"quartiles"`, `"gesd"`, `"grubbs"` |
| `rmArgs` | `struct()` | Additional arguments forwarded to `isoutlier` (e.g., `ThresholdFactor`, `MaxNumOutliers`) |
| `useParallel` | `false` | Use `parfor` across cells |
| `plot` | `false` | Show diagnostic histogram and waveform overlay |
| `verbose` | `false` | Print per-cell artifact count in serial mode |

**Example:**
```matlab
% Custom rejection using GESD with strict settings
rmArgs = struct('MaxNumOutliers', 8, 'Alpha', 0.005);
[S, artInd] = rejectArtifacts(S, feature="rms", rmMethod="gesd", rmArgs=rmArgs, plot=true);
```

---

### `filterABRData`

Applies a standard ABR bandpass filter to all cells in `S`. This function is a convenience wrapper — `extractABRResponses` can also apply filtering during data loading.

```matlab
S = filterABRData(S, Fs)
```

**Filter specifications:**
- Low-pass: Fpass = 3000 Hz, Fstop = 4200 Hz (FIR, Parks-McClellan design)
- High-pass: Fstop = 150 Hz, Fpass = 300 Hz (FIR, Parks-McClellan design)

---

### `plotABRGrid`

Visualizes the mean ABR waveform for every frequency–level combination in a tiled grid layout. Rows correspond to sound levels (descending); columns correspond to frequencies.

```matlab
axesArray = plotABRGrid(S, U, Fs, winIdx)
axesArray = plotABRGrid(S, U, Fs, winIdx, Name=Value, ...)
```

**Options:**

| Name | Default | Description |
|------|---------|-------------|
| `plotWindow` | `[-1 9]` ms | Time window for the plot |
| `normalizePerFrequency` | `true` | Scale each column of traces independently |
| `cm` | auto | Colormap (`nFrequencies × 3` matrix or colormap name) |

**Example:**
```matlab
h = plotABRGrid(S, U, Fs, winIdx, plotWindow=[-1 10]);
title(h.Children, 'Subject 001 – Session 1')
```

---

### `abrPermutationThreshold`

Estimates the ABR hearing threshold at each frequency using a cluster-based permutation test followed by curve fitting.

```matlab
[thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals)
[thresh_hat, permResult, mdls] = abrPermutationThreshold(S, rowVals, options, ptoptions)
```

**Key Options:**

| Name | Default | Description |
|------|---------|-------------|
| `thresholdType` | `"logistic"` | Threshold model: `"logistic"`, `"logistic4"`, or `"minimum"` |
| `useParallel` | `false` | Use `parfor` for permutation tests |
| `nearestLevel` | `false` | Snap threshold to nearest tested level |
| `debug` | `false` | Show diagnostic plots for fits |

**Permutation Test Options (`ptoptions`):**

| Name | Default | Description |
|------|---------|-------------|
| `alpha` | `0.05` | Family-wise alpha for cluster detection |
| `nPerm` | `1000` | Number of sign-flip permutations |
| `minClusterSize` | `1` | Minimum contiguous sample count for a cluster |

**Outputs:**

| Variable | Description |
|----------|-------------|
| `thresh_hat` | `1 × nFrequencies` threshold estimates (dB SPL) |
| `permResult` | `nLevels × nFrequencies` struct with permutation test details |
| `mdls` | `1 × nFrequencies` cell of curve-fitting model objects |

**Required toolboxes:** Statistics and Machine Learning Toolbox, Image Processing Toolbox, Curve Fitting Toolbox.

**Example:**
```matlab
freqs = U.frequency;
opts  = struct('thresholdType', "logistic", 'useParallel', true, 'nearestLevel', true);
ptopts = struct('alpha', 0.05, 'nPerm', 2000, 'minClusterSize', 3);
[th, PR, M] = abrPermutationThreshold(S, freqs, opts, ptopts);
```

---

### `plotABRThresholds`

Plots an audiogram of the estimated thresholds versus frequency.

```matlab
plotABRThresholds(thresh_hat, freqs)
plotABRThresholds(thresh_hat, freqs, cm=myColormap)
```

---

### `batchABRAnalysis`

High-level convenience function that processes all ABR sessions within a root directory. Calls `getABRSessions`, `parseABRFiles`, `extractABRResponses`, `rejectArtifacts`, `filterABRData`, `plotABRGrid`, and `abrPermutationThreshold` for each session.

```matlab
[thresh_hat, logMdls] = batchABRAnalysis(rootPth)
[thresh_hat, logMdls] = batchABRAnalysis(rootPth, filePattern=expr, window=win)
```

**Options:**

| Name | Default | Description |
|------|---------|-------------|
| `filePattern` | `"^SUBJ_ID_(\d+)_..."` | Regex for matching `.abr` file names |
| `window` | `[-10 10]` ms | Extraction window |

**Example:**
```matlab
[thresh_hat, logMdls] = batchABRAnalysis('C:\data\', window=[-1 10]);
```

---

## Complete Example: Single Session

```matlab
%% 1. Parse files
sessionPath = 'C:\data\subject01\';
T = parseABRFiles(sessionPath, filePattern="^SUBJ_001");

%% 2. Extract sweep epochs
win = [-1 10]; % ms
[S, U, Fs, winIdx] = extractABRResponses(T, win);

%% 3. Reject artifacts
S = rejectArtifacts(S, feature="absPeak", rmMethod="quartiles");

%% 4. Filter (optional if not already filtered in step 2)
% S = filterABRData(S, Fs);

%% 5. Visualize
figure;
h = plotABRGrid(S, U, Fs, winIdx);
title(h.Children, 'Subject 001')

%% 6. Estimate thresholds
freqs = U.frequency;
[th, ~, ~] = abrPermutationThreshold(S, freqs, ...
    struct('thresholdType', "logistic", 'nearestLevel', true), ...
    struct('nPerm', 2000, 'minClusterSize', 3));

%% 7. Plot audiogram
figure;
plotABRThresholds(th, freqs);
```

---

## Tips

- **Parallel processing:** Many functions support `useParallel=true` for `parfor` loops. Ensure the Parallel Computing Toolbox is installed and a parallel pool is open (`parpool`).
- **File naming convention:** `parseABRFiles` uses a regular expression to identify valid `.abr` files. Define a consistent file naming scheme (including subject ID, frequency, level, and timestamp) for easy filtering.
- **Permutation test runtime:** With `nPerm=1000` and many conditions, `abrPermutationThreshold` can take several minutes per session. Use `useParallel=true` and increase `minClusterSize` to speed up execution.
- **Threshold models:** The `"logistic"` model is appropriate when detection probability transitions sharply from 0 to 1 across levels. Use `"logistic4"` if the transition is asymmetric. Use `"minimum"` for a simple first-significant-level approach.
