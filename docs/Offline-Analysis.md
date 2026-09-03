# Offline Analysis

> There is now a second, object-oriented route to the same results: **[the `mabr.analysis` classes](Analysis-Classes.md)**, which do the same job with one class per step and batching left to a loop you write. This page documents the original function pipeline, which is unchanged.

The `abr_analysis/` folder holds a batch pipeline that turns folders of saved `.abr` files into hearing thresholds. It is **separate from the acquisition app** — a plain set of MATLAB functions you call from the command window or a script. You can run it on a different machine, with no hardware, at any time after recording.

## What it does

For each session folder it finds, the pipeline:

1. Reads every `.abr` file and recovers the stimulus parameters from the filenames.
2. Cuts each recording into sweeps around the stimulus onsets and groups them by condition.
3. Throws out sweeps contaminated by movement or other artifacts.
4. Filters the waveforms.
5. Draws a grid of averaged responses — frequency across, level down.
6. Determines, statistically, the lowest level at which a response is still detectable: the threshold.

Step 6 is the point of the exercise. Rather than judging by eye where a response disappears, it uses a permutation test to ask whether the recorded sweeps at each level contain a genuine time-locked response, then estimates the threshold from that pattern of detections.

## Running it

Organize your data with one folder per session (see [Data Files](Data-Files.md)), then:

```matlab
>> abrSessions = getABRSessions("C:\data\abr_data")
```

This lists every folder below that root containing `.abr` files. For one session:

```matlab
T = parseABRFiles(sessionPath);                        % filenames → table of conditions
[S,U,Fs,winIdx] = extractABRResponses(T, [-10 10]);    % load and cut into sweeps, ms window
S = rejectArtifacts(S);                                % drop bad sweeps
S = filterABRData(S,Fs);                               % bandpass
plotABRGrid(S,U,Fs,winIdx);                            % the response grid
[thresh,permResult,mdls] = abrPermutationThreshold(S,levels);
plotABRThresholds(thresh,freqs);                       % audiogram
```

Each function has full help text — `>> help extractABRResponses`.

> **Known issue:** `batchABRAnalysis` calls `parseABRFiles` and `extractABRResponses` with positional arguments that no longer match their signatures, so the all-in-one entry point is currently broken. **This is known and intentionally not fixed.** Call the functions individually as above, using name-value syntax. [SCRATCH_BatchABRanalysis.m](../abr_analysis/SCRATCH_BatchABRanalysis.m) is a working script to adapt.

## Reading the output

**The response grid** — averaged waveforms, one column per frequency, one row per level, loudest at the top. A healthy series shows clear peaks at high levels that shrink and shift later as level drops, until they vanish into noise. That vanishing point is the threshold.

**The audiogram** — estimated threshold against frequency. Higher means worse hearing. This is the summary figure for most experiments.

**Curation** — `abrPermutationThresholdCuration` opens an interactive review of the automatic thresholds, flagging suspicious columns and letting you inspect and override them. Automatic threshold estimation is good but not infallible, particularly with few sweeps or a noisy recording; curating before pooling across subjects is worth the time.

## Time windows

The window (in milliseconds, relative to sweep onset) matters. Something like `[-10 10]` includes pre-stimulus baseline — needed, because the statistics compare the response period against it. Do not use a window starting at 0.

---

## Developer notes

### Status and boundaries

This pipeline was authored separately (`dstolz@umd.edu`, 2025) and was **untouched by the acquisition rewrite**. It is function-based, not object-oriented, and shares no code with `+mabr`. The only coupling is the `.abr` file format and filename convention.

`parfor_progress` is an external File Exchange dependency used for progress reporting; the pipeline degrades gracefully without it, but `verify_data_roundtrip` skips its pipeline-integration check when it is absent.

### The contract it depends on

The pipeline reads exactly:

```
ABR_Data.ADC.SampleRate / .Data / .SweepOnsets
ABR_Data.StartTime
ABR_Data.SIG.informativeParams, numeric SIG.(param), SIG.Label
```

and filenames matching:

```
^SUBJ_ID_(\d+)_Frequency_([\d_]+kHz)_Level_(\d+dB)_(\d{6}T\d{6})\.abr
```

[mabr.data.io.writeABR](../+mabr/+data/io.m) emits precisely this, and [verify_data_roundtrip.m](../tests/verify_data_roundtrip.m) asserts it — including running the real `parseABRFiles`/`extractABRResponses` over freshly written files when `parfor_progress` is on the path. Changing the writer without running that test risks silently breaking every downstream analysis.

### Filtering differs from acquisition

The offline pipeline designs its own FIR filters (`filterABRData`, and optional filtering inside `extractABRResponses`: 3000 Hz passband / 4200 Hz stopband, `filtfilt` by default) rather than reusing `Recording.designFilters`. This is intentional — `.abr` files store the **unfiltered** continuous trace plus onsets, so offline filtering choices are free and reversible. Note that `extractABRResponses` filters the whole trace **before** segmentation, which avoids edge artifacts at sweep boundaries.

### permtest

[permtest.m](../abr_analysis/permtest.m) is the statistical core: a 1-D permutation test across trials with selectable correction — `clusterMass` (default), `tmax`, or `tfce` (Mensen & Khatami, 2013). It takes `[nTrials x nSamples]`, so `abrPermutationThreshold` transposes the `[nSamples x nTrials]` matrices in `S` on the way in. Threshold estimation from the per-level detection results defaults to a GLM fit rather than fitting a sigmoid to raw 0/1 significance, which is more stable with few levels.
