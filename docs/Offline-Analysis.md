# Offline Analysis

> **The recommended route is now [the Analysis App](Analysis-App.md).** Start it with `>> MABRAnalysis`, or with **File ▸ Offline Analysis…** in MABR. It takes a study folder through labelling, analysis, threshold and peak review, cross-session comparison and export to R, in one window that never writes into the data folder. It is built on **[the `mabr.analysis` classes](Analysis-Classes.md)**. They do the same job from a script, with one class per step and batching left to a loop you write or to `mabr.analysis.Batch`. Its *Legacy SCRATCH (2025)* settings profile reproduces this pipeline's choices.
>
> This page documents the original function pipeline, which is unchanged and still works as described below.

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
[S,U,Fs,winIdx] = extractABRResponses(T, [-10 10]);    % load, filter and cut into sweeps, ms window
S = S';                                                % [freq x level] → [level x freq], as the later steps expect
S = rejectArtifacts(S);                                % drop bad sweeps (loud outliers only, by default)
S = filterABRData(S,Fs);                               % optional second filtering pass (see below)
plotABRGrid(S,U,Fs,winIdx);                            % the response grid
[thresh,permResult,mdls] = abrPermutationThreshold(S,U.Level, ...   % U.Level: dB SPL, one per row of S
    window=[0 10],Fs=Fs,winIdx=winIdx,Seed=1);         % test the 0–10 ms response window only; Seed makes the run repeatable
plotABRThresholds(thresh,U.Frequency);                 % audiogram
```

Each function has full help text — `>> help extractABRResponses`.

`extractABRResponses` gives `S` one dimension per stimulus parameter, in the order the parameters appear in the table. With frequency before level, as in the usual files (and as [SCRATCH_BatchABRanalysis.m](../abr_analysis/SCRATCH_BatchABRanalysis.m) assumes), `S` is `[freq x level]`, hence the transpose; if your files order them otherwise, check `size(S)` against `[numel(U.Level) numel(U.Frequency)]` before the later steps. In files from the current software `U.Level` is in dB SPL and `U.Frequency` is in kHz; older files call them `soundLevel` (dB SPL) and `frequency` (Hz), and `plotABRGrid` accepts either.

**All sessions at once.** `batchABRAnalysis(rootPth)` runs this recipe for every session folder below `rootPth`: `getABRSessions`, `parseABRFiles`, `extractABRResponses` (which already filters, so `filterABRData` is not called again), `rejectArtifacts` and `plotABRGrid` (one figure per session; `plot=false` skips them), then `abrPermutationThreshold` on the response window. It returns `thresh_hat`, a cell with one `[1 x nFrequencies]` row of thresholds per session, and `logMdls`, a cell of structs (`U`, `permResult`, `mdls`). Options: `window` (default `[-10 10]` ms, what is cut and drawn), `responseWindow` (default `[0 10]` ms, what is tested; it must lie inside `window`), `thresholdType`, `minClusterSize` (default 5), `Seed` and `filePattern`. A session is skipped with a message when no file matches, when its files vary anything but level and frequency, or when it holds compact files. The default `filePattern` ends at the timestamp, so a same-second `_2` file is not matched; pass a pattern with `(_\d+)?` before `\.abr` to include those.

**Several files per condition.** When one condition was recorded in more than one file (Loop/Repeat runs, or same-second `_2`/`_3` file names), `extractABRResponses` pools their sweeps into one cell, taking the files in ascending `StartTime` order, and warns once per condition.

**Compact files are not supported.** Files written from intermixed runs hold only the sweep windows, laid end to end (onsets 1, L+1, 2L+1, …), not a continuous trace, so the pre-stimulus part of each window would be the previous sweep's response. `extractABRResponses` recognises this layout and stops with the error `abr_analysis:extractABRResponses:compactFile`. Analyse such folders with [the Analysis App](Analysis-App.md) (`>> MABRAnalysis`) or `mabr.analysis.Session` ([Analysis Classes](Analysis-Classes.md)).

**Filtering.** `extractABRResponses` already filters, by default: a 150/300 Hz high-pass and a 3000/4200 Hz low-pass, applied to the whole trace before it is cut into sweeps (`lowpass`/`highpass` switch them off). `filterABRData` applies the same two filters again, so after a default extraction it is a second pass over filtered sweeps. It also skips any window shorter than its filters need (367 samples at 12 kHz) and warns (`filterABRData:segmentTooShort`), leaving those sweeps unfiltered.

**Requirements.** The pipeline is not self-contained. Each entry point checks at its first line and stops with one error, `abr_analysis:missingDependency`, naming what is missing and where to get it, rather than failing later with *Undefined function 'parfor_progress'*:

- `parseABRFiles`, `extractABRResponses`, `filterABRData` and `rejectArtifacts` call `parfor_progress`; `plotABRGrid` and `plotABRThresholds` need `colorcet` (unless you pass `cm`) and `structToCallerVars` (`plotABRGrid` also `errEmpty`); `rejectArtifacts` with `'plot',true` needs `use_fig_tiledlayout` and `titlef`; `batchABRAnalysis` needs all of these. They come from the author's separate [helper_fnc](https://github.com/dstolz/helper_fnc) repository, which has to be on the MATLAB path (clone it, then `addpath(genpath(...))` its folder). MABR does not ship copies of them: a copy in `abr_analysis/` would shadow your own, or be shadowed by it, depending on path order.
- The Statistics and Machine Learning Toolbox (`tinv` in `permtest`, `fitglm` for the default GLM threshold), the Curve Fitting Toolbox (only for the `"sigmoid"` threshold) and the Signal Processing Toolbox (`filtfilt`, `firpm`; `extractABRResponses` needs it only while one of its filters is on).
- [The Analysis App and the `mabr.analysis` classes](Analysis-App.md) need none of this.

[SCRATCH_BatchABRanalysis.m](../abr_analysis/SCRATCH_BatchABRanalysis.m) is the author's own working script, with hard-coded paths, to adapt for a study of your own.

## Reading the output

**The response grid** — averaged waveforms, one column per frequency, one row per level, loudest at the top. A healthy series shows clear peaks at high levels that shrink and shift later as level drops, until they vanish into noise. That vanishing point is the threshold.

**The audiogram** — estimated threshold against frequency. Higher means worse hearing. This is the summary figure for most experiments.

**Curation** — `abrPermutationThresholdCuration` opens an interactive review of the automatic thresholds, flagging suspicious columns and letting you inspect and override them. Automatic threshold estimation is good but not infallible, particularly with few sweeps or a noisy recording; curating before pooling across subjects is worth the time.

## How the threshold is estimated

`abrPermutationThreshold` gives every level one yes/no verdict (is the permutation-test p-value below `alpha`?) and fits a psychometric curve through those verdicts; the threshold is where the fitted probability of detection reaches 0.5 (`criterion`). A clean series, nothing detected below some level and everything detected above it, is *perfectly separated*: an ordinary logistic fit has no finite slope, so its slope is arbitrary and its threshold is just the midpoint of the gap. The default `"glm"` fit is therefore Firth-penalised (`fitglm(...,'LikelihoodPenalty','jeffreys-prior')`) with unit weights, one observation per level however many sweeps stand behind the verdict. That is the same fit as the class-based `mabr.analysis.Threshold` with `Penalty="firth"`, and it gives the same threshold to the digit. Its interval (`mdls{k}.threshCI`) is a Monte Carlo draw from the fit's covariance: wider than the class's profile-likelihood interval, and it can run past the levels you tested, which is honest about how little a handful of yes/no verdicts say. If your MATLAB's `fitglm` has no `LikelihoodPenalty` option, the unpenalised fit is used and a warning (`abrPermutationThreshold:noPenalisedFit`) says so.

**Thresholds and intervals from runs made before this change differ.** Earlier versions fitted the same logistic curve without the penalty and weighted each level by its number of sweeps, which made a verdict from 200 sweeps count as 200 identical observations: the interval came out about √200 times too narrow, so the curation flag for wide intervals could hardly fire. A column in which nothing is detected at any level is now `Inf`, and one in which everything is detected is the lowest level, instead of an extrapolated number.

Pass `Seed` for a reproducible run: it fixes every permutation test (condition *i* is tested with `Seed+i-1`) and the Monte Carlo intervals, and leaves the global random stream alone. Without it the global stream is used, so two runs on identical data give slightly different p-values near `alpha`.

## Time windows

The window (in milliseconds, relative to sweep onset) matters. Something like `[-10 10]` includes a pre-stimulus stretch, which helps in the response grid (its default plot window starts at -1 ms) for judging the noise floor by eye. The statistics do not use it: `permtest` is a one-sample sign-flip test against zero at every sample it is given, and it never compares the response with a baseline. So the permutation test needs its own, narrower window: pass `window=[0 10]` (milliseconds re onset) together with `Fs` and `winIdx` from `extractABRResponses`, as in the recipe above, and `abrPermutationThreshold` cuts every condition to those samples before testing. Without `window` every sample passed in is tested, a significant cluster in pre-stimulus samples counts as a detection, and the function warns once per session (`abrPermutationThreshold:noWindow`) to say so; if you cut `S` to the response window yourself, switch that warning off. A window that starts at 0 works, but the grid then shows nothing before the stimulus.

---

## Developer notes

### Status and boundaries

This pipeline was authored separately (`dstolz@umd.edu`, 2025) and was **untouched by the acquisition rewrite**. It is function-based, not object-oriented, and shares no code with `+mabr`. The only coupling is the `.abr` file format and filename convention.

`parfor_progress` is an external dependency (it lives in the author's [helper_fnc](https://github.com/dstolz/helper_fnc) repository) used for progress reporting. Only `abrPermutationThreshold` carries on without it; the other functions call `checkABRDependencies` first and stop at once with `abr_analysis:missingDependency`. `verify_data_roundtrip` skips its pipeline-integration legs when it is absent.

### The contract it depends on

The pipeline reads exactly:

```
ABR_Data.ADC.SampleRate / .Data / .SweepOnsets
ABR_Data.ADC.SweepLength (optional; used to recognise compact files)
ABR_Data.StartTime
ABR_Data.SIG.informativeParams, numeric SIG.(param), SIG.Label
```

and filenames matching:

```
^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr
```

(the default `filePattern` of `batchABRAnalysis`). Underscores separate tokens and hyphens join the parts of one; a decimal point is `p` and a minus sign `m` (see [Data Files](Data-Files.md#filenames)). Files named before this scheme (`SUBJ_ID_001_Frequency_8kHz_…`) do not match it — pass a pattern of your own to reach them.

[mabr.data.io.writeABR](../+mabr/+data/io.m) emits precisely this, and [verify_data_roundtrip.m](../tests/verify_data_roundtrip.m) asserts it — including running the real `parseABRFiles`/`extractABRResponses` over freshly written files when `parfor_progress` is on the path: two files of one condition must be pooled, a compact file must be refused, and `batchABRAnalysis` must run over the folder. Changing the writer without running that test risks silently breaking every downstream analysis.

### Filtering differs from acquisition

The offline pipeline designs its own FIR filters (`filterABRData`, and optional filtering inside `extractABRResponses`: a 3000 Hz passband / 4200 Hz stopband low-pass and a 150 Hz stopband / 300 Hz passband high-pass, `filtfilt` by default) rather than reusing `Recording.designFilters`. This is intentional — `.abr` files store the **unfiltered** continuous trace plus onsets, so offline filtering choices are free and reversible. Note that `extractABRResponses` filters the whole trace **before** segmentation, which avoids edge artifacts at sweep boundaries.

### permtest

[permtest.m](../abr_analysis/permtest.m) is the statistical core: a 1-D permutation test across trials with selectable correction — `clusterMass` (default), `tmax`, or `tfce` (Mensen & Khatami, 2013). It takes `[nTrials x nSamples]`, so `abrPermutationThreshold` transposes the `[nSamples x nTrials]` matrices in `S` on the way in. The statistic is a one-sample t against zero at every sample, with significance from sign-flip permutations; it never uses a baseline, so any baseline correction has to be done on the data beforehand. The optional `Seed` name-value makes the sign flips reproducible without touching the global random stream. A level with fewer than two trials cannot be tested; `abrPermutationThreshold` gives it a `NaN` p-value and leaves it out of the threshold fit. Threshold estimation from the per-level detection results defaults to a Firth-penalised GLM fit rather than fitting a sigmoid to raw 0/1 significance, which is more stable with few levels (see *How the threshold is estimated*).
