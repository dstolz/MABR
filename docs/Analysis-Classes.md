# The `mabr.analysis` classes

`+mabr/+analysis/` is the object-oriented offline pipeline: the same job as the `abr_analysis/` functions ([Offline Analysis](Offline-Analysis.md)) — saved `.abr` files in, thresholds and wave measures out — reorganized so that each piece does one thing and batching is a loop you write rather than one baked into the functions. The analysis app (`MABRAnalysis`, `mabr.ui.AnalysisApp`) is a window over exactly these classes; everything it does can be done from a script.

Nothing here needs the Statistics, Curve Fitting, or Parallel Computing toolboxes, and nothing here needs a File Exchange download. It runs anywhere MABR runs.

## The shape of it

One class holds a **session** — one folder of `.abr` files, one animal, one sitting (or a *pool* of one animal's folders) — and one call takes it from files to thresholds and peaks with a set of settings:

```matlab
s = mabr.analysis.Session("C:\data\abr_data\SUBJ-ID-1107\ABR_001");
s.analyze(mabr.analysis.Settings());        % segment .. reject .. detect .. measure .. thresholds .. peaks
s.Thresholds(:,["Key","Final","FinalCensored","Status"])
s.plotGrid();  s.plotAudiogram();
s.saveResults("results/SUBJ-ID-1107_ABR_001.mat",IncludeSweeps=false);
```

A study is either your own loop or `mabr.analysis.Batch`:

```matlab
T = mabr.analysis.Batch.runFolder("C:\data\study",mabr.analysis.Settings(), ...
        ResultsFolder="C:\results\study");          % one results file per session, a log line each
```

The steps can still be called one at a time, with their own (older) defaults — see *Two tiers of defaults* below:

```matlab
s.segment();  s.reject();  s.detect();  s.estimateThresholds();
```

Everything a step does to **one condition** or **one series** lives in a separate class and can be called on its own, with no Session anywhere:

| class | what it does | unit it works on |
|---|---|---|
| `mabr.analysis.Session` | orchestration, results, edits | a folder (or a pool) |
| `mabr.analysis.Settings` | every analysis setting as one value object | — |
| `mabr.analysis.Batch` | the headless loop over many sessions | a study |
| `mabr.analysis.Catalog` | every recording under a data folder, without opening one | a data folder |
| `mabr.analysis.Project` | labels, pools, study use of the sessions | a results store |
| `mabr.analysis.AbrFile` | the one `.abr` reader | one file |
| `mabr.analysis.Filter` | the zero-phase FIR band, and the windowed operator | one trace / one window |
| `mabr.analysis.Artifacts` | per-sweep artifact detection | one condition |
| `mabr.analysis.PermTest` | sign-flip permutation test | one condition |
| `mabr.analysis.SingleTrial` | balanced means, ± reference, power test, Fsp, split-half, features | one condition |
| `mabr.analysis.Threshold` | detection, and the threshold fits (Firth GLM, presto, legacy models) | one condition / one series |
| `mabr.analysis.SeriesThreshold` | the named threshold methods, censoring, the curated value | one series |
| `mabr.analysis.Peaks` | wave picking, tracking, bootstrap, derived measures | one waveform / one series |
| `mabr.analysis.Export` | tidy tables, CSV/Parquet, the R script | sessions and labels |
| `mabr.analysis.ScriptWriter` | a GUI-free MATLAB script that replicates an analysis | sessions |
| `mabr.analysis.Plot` | every figure | plain data |
| `mabr.analysis.Stats` | toolbox-free statistics, keys, hashes | numbers |
| `mabr.analysis.Progress` | progress through an explicit sink | — |

So `mabr.analysis.PermTest.run(X)` tests one `[nSamples x nSweeps]` matrix from anywhere, and `mabr.analysis.Plot.audiogram(freqs,thresholds)` draws an audiogram from numbers that never came from a Session at all.

## Two tiers of defaults

Calling a `Session` step **directly** keeps the defaults it has always had, so existing scripts — and `tests/verify_analysis.m`, which is held byte-unchanged — give the numbers they always gave: `ResponseWindow [0 10]`, a shared permutation seed, the legacy threshold models, `MinSweeps 2`.

`Session.analyze(settings)` maps **every** option from a `mabr.analysis.Settings`, whose defaults are the **recommended** ones: response window `[0.5 8]` ms, per-condition permutation seeds, the single-trial measures, the `perm-glm` threshold method (`MinSweeps 100`, `MinPerPolarity 40`), and the rodent wave priors. `Settings.profile("Legacy SCRATCH (2025)")` reproduces the 2025 batch pipeline instead.

## Conditions are a table, keyed

`s.Conditions` is one row per stimulus condition, with a column per stimulus parameter (`Key`, `Stimulus`, `AcqMode`, `Frequency`, `Level`, … then the sweeps, their flags and counts, `p`, the measures). The parameter columns come from each file's `SIG.informativeParams` — the union over the files, so a folder whose first file is a click still keeps `Frequency` — and a bank that varies three things produces three columns without anybody saying which two they were.

**Rows move; keys do not.** Every condition, series and file is identified by a stable key: conditions by `Key` (`"Stimulus=Tone|AcqMode=conventional|Frequency=8|Level=30"`, over `KeyParams`; a parameter a stimulus lacks — a click's frequency — is left out), series by the condition key without the level, files by `FileId` (`"<folder>/<file>"`). That is what lets curation, overrides and hand rejections survive a re-analysis. `grid()` reshapes to the `[level x frequency]` cell array the older functions use:

```matlab
[S,U,levels,freqs] = s.grid("Level","Frequency");
```

**Acquisition modes.** A file holding one condition's continuous run is `AcqMode` "conventional"; a file cut out of an intermixed run (compact: windows back to back) is "interleaved". They are separate conditions — and separate series — by default (`Settings.PoolAcqModes = false`): pooling changes the sweep count and the stimulus history. A compact file has no pre-onset sample and a step at every junction, so its sweeps are **windowed**: each sweep's own window is cut raw and filtered alone (`Filter.applyWindowed`), the rows outside what the file holds are `NaN`, and `Conditions.Extent` says which rows those are.

## Rejected sweeps are flagged, never deleted

`reject()` writes a logical per sweep and its reason (`RejectReason`: 1 the rig, 2 a criterion, 3 by hand) and nothing else. `sweeps()` and every average exclude flagged sweeps by default; `s.sweeps(k,IncludeRejected=true)` gets them back. This is the rule the acquisition side already follows (`mabr.data.Recording.IsArtifact`), and it is what lets you change a rejection setting without reloading anything. The rig's own verdict comes in with the data (`ADC.IsArtifact`); `HonorAcquisitionArtifacts=false` starts from a clean slate. A cap on the clean sweeps per condition (`MaxSweepsPerCondition`, kept balanced by polarity) marks the rest `Excess` — unused, not rejected.

```matlab
s.reject(Method="median", Feature="absPeak");            % relative, upper tail: an outlier among its neighbours
s.reject(Method="threshold", Threshold=100e-6);          % absolute: over 100 µV, full stop
```

## Filtering happens before segmentation

`mabr.analysis.Filter` is the offline band — equiripple FIR, 300 Hz to 3000 Hz by default, run with `filtfilt` so no peak moves — and `segment()` applies it to each **whole continuous trace** before cutting sweeps out of it. A sweep is a few hundred samples; a filter's edge transient would land squarely on the response. Traces are kept in memory (`KeepTraces`), so a second band costs no disk reads. A non-finite sample (NaN, Inf) costs the sweeps it reaches and nothing else: it is zeroed for the filter, every sweep whose window — widened by the filter's reach on a continuous trace — holds one is left out (the condition's flags count them, a warning names the file), and every other sweep is bit for bit what it would have been. (It used to stop the filter, and with it the whole session.)

## Detection

`detect()` runs a sign-flip permutation test on each condition (`clusterMass`, `tmax` or `tfce`), family-wise corrected over samples. **Seed it.** `analyze` uses **per-condition seeds** (`Stats.conditionSeed(Seed,Key)`): two conditions with the same sweep count no longer share sign flips, and re-testing one condition after an edit is bit-identical to re-testing all of them.

**No noise, no test.** A condition whose clean sweeps do not vary within their file × polarity groups (`SingleTrial.zeroVariance`: residual noise at most `ZeroVarianceTol`, 1e-6, of the sweeps' own RMS) has nothing to test a response against — an all-zero (dead) channel, a digital loop-back, synthetic data written without noise. It is **not tested**: `p` is `NaN`, `isSig` false, the condition is flagged "zero variance: the clean sweeps do not vary (a dead channel, or noiseless data)", and a warning names it. Such sweeps used to hang the analysis: a sign flip that lines every sweep up has no variance left, its t is unbounded (1e8 on a noiseless 8-sweep condition), and TFCE integrates each t map in steps of 0.1 up to its maximum. A polarity-following CM is not noise (`Threshold.detect` is handed each sweep's polarity), so noiseless alternating sweeps count as identical. **TFCE is bounded** as well, for near-noiseless data that is not quite zero: when the largest |t| a test meets (the observed map and every permuted one, from a t-max run on the same sign flips) would need more than `Threshold.MaxTFCESteps` (1000) steps, the step is raised to that |t| / 1000 for the observed map and the null alike — still a valid test — and the condition is flagged "TFCE step raised to …". A recording with noise in it never gets near a |t| of 100, so nothing else changes, bit for bit. `PermTest` has a backstop of its own for a **direct** call, which skips that step: no map is integrated over more than `PermTest.MaxTFCESteps` (10000) steps per sign — past that, that call's step is raised to its largest |t| / 10000 (`TFCE.MaxSteps` overrides the count) — so `PermTest.run(X,Method="tfce")` on near-noiseless sweeps returns in well under a second instead of hanging. It is applied per call, so the observed map and the null may then be summed on different grids (each within about 1/10000 of the same integral); `detect` raises the step for both first and keeps every map under 1000 steps, so it never meets this cap. At the default step of 0.1 the cap is a |t| of 1000, and below it nothing changes, bit for bit.

## Single-trial measures — `measure()`

Per condition, from its clean sweeps (`mabr.analysis.SingleTrial.summary`, each condition from its own random stream):

- `RN` (residual noise of the polarity-balanced mean) and `RNPM` (RMS of its ± reference); `ResponseRMS`, `BaselineRMS`;
- the **power test** `F = P_m/RN²`, its sign-flip `PowerP` and null 95th percentile `PowerF95`, `SNR = 10·log10(F)`;
- **Fsp** with estimated degrees of freedom (`Fsp`, `FspDF1`, `FspDF2`, `FspP`);
- the **split-half** correlation `SplitR` (`SplitRSD`, percentiles, `SplitN` = K). K is one per **series** — the smallest any of its conditions can give (a condition too small for an r of its own, K under `SplitHalfMinPerPolarity`, does not count) — so every level's r is made from halves of one size;
- `XCorrUp`: each condition's mean against the next *louder* level of its series (`NaN` at the top level) — louder by `measure(LevelDirection=...)`, which `analyze` passes from the settings, since it measures before the threshold step has stored its own;
- `DTWUp`: the same pair after dynamic time warping (`SingleTrial.dtwUp`, Signal Processing's `dtw`). The lag runs from 0 to `MaxLag` and changes along the response, smoothed over 2 ms (`SingleTrial.DTWLagSmoothMs`), so wave I and wave V can each take their own latency shift. `DTWLag` is the warp's mean lag and `DTWLagRange` its spread, in ms (0 for one rigid shift). `NaN` at the top level;
- `Features` per sweep (RMS, P2P, MaxAbs, baseline RMS, template amplitude and r) for the trial view. The template amplitude is the sweep's projection on its leave-one-out average scaled to mean 1, and `NaN` for every sweep of a condition whose average holds no response (mean projection under 3 standard errors above 0): scaling by noise gave values in the hundreds.

A baseline that holds the previous presentation's response (the files' shortest interval under `|BaselineWindow(1)| + ResponseWindow(2)`) is not measured: `BaselineRMS` is `NaN` and the condition is flagged "baseline overlaps the previous response".

A condition with **zero variance** (see *Detection*) has no noise to measure against: `RN` is 0 — which is true — and everything that is a ratio over it (`F`, `SNR`, `SNRCorr`, the power test, `Fsp`, the split-half r) is `NaN`, with the same flag and a warning naming the conditions. A threshold method then ignores the level ("level ignored at L dB: zero variance (the clean sweeps do not vary)"), so a dead channel gives "insufficient" series, never a threshold.

## Thresholds — named methods

`estimateThresholds` fits one threshold per **series** through `mabr.analysis.SeriesThreshold`, by a **named method** (below).

**What a series is.** Every condition sharing everything but the level. `GroupBy` (`Settings.GroupBy`, `estimateThresholds(GroupBy=...)`) names the columns a series is keyed by; empty — the default — is every key column but the level: `Stimulus`, `AcqMode`, the frequency and whatever else the bank varies. A GroupBy that is given is used as given **plus `Stimulus` and `AcqMode`** whenever it leaves them out (`AcqMode` not when `PoolAcqModes` pooled the modes, which leaves one "pooled" mode): a series is one stimulus in one acquisition mode whatever is typed (`Session.seriesGrouping`). Typed exactly as given, `GroupBy="Level"` with the frequency as the level axis fitted clicks, tones, conventional and interleaved runs into one series per level, and said nothing. A note says what was added when an added column varies, and `GroupParams` holds the grouping applied, so `GroupBy="Frequency"` gives the same series keys as the default and the curation stays where it was.

| method | metric | rule |
|---|---|---|
| `perm-glm` (default) | permutation-test detections | Firth-penalised psychometric (GLM) fit, p = 0.5, profile CI — advisory |
| `perm-descending` | permutation-test detections | descending from the loudest level until 2 consecutive misses, the lowest of 2 consecutive detected levels: the interval between it and the level below, reported at its midpoint |
| `power-descending` | the power test's p | the same descending rule |
| `fsp-descending` | Fsp's p | the same descending rule |
| `presto` | split-half r | ABRpresto-like sigmoid / power-law fit, r = 0.30 |
| `suthakar-liberman` | r with the next-louder level | the descending rule at r ≥ 0.35 |
| `xcorr-dtw` | r with the next-louder level after time warping | the descending rule at r ≥ 0.40 |
| `custom` | any metric | any model and criterion (`Settings.ThresholdMetric/Model/CriterionMode/Criterion`) |

**`suthakar-liberman` is named for the paper its statistic comes from**: Suthakar & Liberman 2019, *Hear Res* 381:107782 ([doi:10.1016/j.heares.2019.107782](https://doi.org/10.1016/j.heares.2019.107782)) — each level's average correlated with the next-louder level's (`XCorrUp`, on the quieter level of the pair), and 0.35 as the response criterion. The rule is not the paper's: they fit a sigmoid and a power law to r against level and read the crossing off the better fit (their Fig. 4); here the descending rule decides and the crossing is interpolated between the bracketing levels. The r is not quite theirs either: theirs is at lag 0, `XCorrUp` the best of lags 0..`MaxLag` (`MaxLag = 0` gives theirs; `XCorrUp0` is always stored). It was called `xcorr`, the metric's name. That Id is retired, not refused: `SeriesThreshold.canonicalId` maps it, `Settings` stores it as `suthakar-liberman` (`set.ThresholdMethod`), and `Settings.canonicalStruct` renames it in a saved step's settings before `isStale`, `Batch.isCurrent` and the project's status compare them, so a result made under it is not out of date. A settings hash recorded under it does differ.

**`mabr.analysis.SuthakarLiberman` is the paper's algorithm as published**, to compare with the method. It decides nothing in an analysis; the analysis app's **Suthakar & Liberman…** window draws it. It provides:

- `decide(levels,r)`: the Fig. 4 tree. C1: the sigmoid's limits span 0.35 and 0.005 < d < 0.999. C2: the sigmoid's RMS error is below the power law's (path A). C3: the power law's adjusted R² is over 0.7 (path B). C4: r ever exceeds 0.35 (path C, flagged for visual inspection; otherwise path D, no threshold). It returns the path, each condition's answer, the threshold and its interval, and a sentence saying why.
- `fitSigmoid` and `fitPower`: the paper's `sigm_fit` y = a + (b−a)/(1+10^(d(c−x))) and MATLAB's `power2` y = a·x^b + c, fitted by unweighted least squares. `power2` uses levels above 0 only. Each comes with the band the paper drew: `nlpredci`'s confidence band of the curve, and `predint`'s prediction band. RMS error is sqrt(SSE/(n−p)). No Statistics or Curve Fitting toolbox is used.
- `correlogram`: xcov 'coeff', whose lag-0 value is `SingleTrial.xcorrUp`'s r0.
- `fromSession(S,seriesKey)`: a series' levels, `XCorrUp0` (the paper's r), `XCorrUp` (the method's), and each adjacent pair's correlogram over the window and extents `measure` used. It works on sessions loaded from results files too.

**`xcorr-dtw` extends `suthakar-liberman`**, which advances the quieter level's average by one lag, from 0 to `MaxLag`, to meet the louder one's (Suthakar & Liberman 2019 use lag 0). But a quieter response is not the louder one shifted: its later waves are delayed more than its early ones, wave V about twice wave I per dB. One lag therefore lines up wave I or wave V, not both, and the part left out of line reads as lost morphology. `xcorr-dtw` takes each sample's lag from `dtw`, within 0 to `MaxLag` and never earlier than the louder level. It smooths that lag over 2 ms and then correlates the warped average with the louder one.

The smoothing is what makes the warp usable as a detection statistic. Unsmoothed, `dtw` lines up noise: two independent noise averages (default band and window, 0.3 ms allowance) gave a median r of 0.60, against 0.14 under `suthakar-liberman`. Smoothed, the median is 0.14 again, while a noiseless synthetic series whose waves shift by 0.15–0.30 ms per 10 dB correlates at 0.996 (`suthakar-liberman`: 0.90). The criterion is 0.40, not 0.35, because the smoothed warp still has more freedom than one lag. At 0.40, pairs of noise averages pass about 3% of the time, as they pass 0.35 under `suthakar-liberman`. On the synthetic series near threshold the two methods detect about equally often; the warp's gain is in how well a clear response lines up.

`MaxLag` is the allowance for both methods. A results file analysed before `DTWUp` existed has every step's settings current, so `isStale` adds a "measure" row for `DTWUp` when the method in force is `xcorr-dtw` (`Session.missingMeasure`), and re-running starts from the measures. Re-fitting only the thresholds would refuse with `noMeasures`.

`Settings.thresholdDefinition()` says in one sentence what the threshold *is* under the settings in force. **The descending rule walks down**, as it is done by eye (`SeriesThreshold.descendingRun`): from the loudest usable level down while the response continues, stopping at the first `MinConsecutive` consecutive misses; the threshold run is the lowest run of `MinConsecutive` detections above that stop. A run below the stop is disconnected from the response at the top and only raises "isolated detection below threshold" — scanning up from the softest level instead took the first run met there, which for a series with no response can be a run of noise (18 dB for a real 32 kHz series every other method calls no response). A permutation p is a Monte-Carlo estimate: a level whose p is within twice its standard error, `2·sqrt(α(1−α)/NumPermutations)`, of α is flagged "borderline detection at L dB (p …)" — a detection the next seed may not make, and one that can move a threshold by a level step. A p-value says whether there is a response at a level, not how much, so the p-methods report **intervals**; a graded metric crosses its criterion between two levels and gives a point. **Censoring is an answer**: every usable level detected is "all-respond" (left-censored at the lowest level), none is "no-response" (right-censored, `Threshold Inf`), and fewer than two usable levels is "insufficient" — or "all-respond" when the one level responds — never "no response". A level counts only with `MinSweeps` clean sweeps (`MinPerPolarity` of each polarity) and a finite metric. An attenuation axis (`LevelDirection` "auto" for a parameter named Attenuation) is fitted on −level. Peak tracking (loudest level first), "below" for peak edits and re-tracking, and `XCorrUp`'s next-louder level follow the same direction.

The Thresholds table: `Key`, the series columns, `LevelParam, Method, Metric, Type, FitTarget, Criterion, CriterionUnit, Convention, Threshold, ThresholdRaw, Status, Censored, ThrLo, ThrHi, CILower, CIUpper, CIMethod, NumLevels, NumUsable, NumSig, LevelStep, MinLevel, MaxLevel, Converged, Message, Flags`, the curation columns `Decision, ManualValue, ManualKind, Final, FinalCensored, FinalLo, FinalHi, Note, ReviewedBy, ReviewedAt, ReviewedValue, ReviewedMethod`, then `Curated`, `IsCurated` and `Fit`.

**The direct, legacy call** `estimateThresholds(Type=..., FitTarget=..., Criterion=...)` (no `Method`) is the custom method with metric "detection", model = `Type`, criterion mode "probability" for glm and "fraction" (a fraction of the observed range, fitted only after a run of permutation detections) otherwise — so every script written before named methods keeps its meaning. **`Criterion` means two different things there, and `FitTarget` decides which**: on binary detections it is a probability (the level at which a response becomes detectable half the time); on the graded strength it is a fraction of the response range, so `0.5` is the **half-maximum of the growth function** — a larger number, because the response goes on growing after it first appears. Every GLM, legacy or not, is Firth-penalised with unit weights: one yes/no verdict per level is one observation.

## Curation survives re-analysis

A human decision is part of the result, not a note beside it:

```matlab
s.acceptFit(sk);                                         % "the method is right here"
s.setDecision(sk,"manual",Value=35,Kind="level");        % the lowest level WITH a response: Final (30, 35]
s.setDecision(sk,"manual",Value=37.5,Kind="value");      % a number
s.setDecision(sk,"noresponse");  s.setDecision(sk,"allrespond");  s.setDecision(sk,"excluded");
s.clearDecision(sk);  s.setThresholdNote(sk,"wave V clear at 35");
s.setThreshold(row,45);                                  % the old form: a manual value (Inf: no response, NaN: excluded)
```

`Final*` is what is reported (`SeriesThreshold.finalValue`): the decision when there is one, else the method's answer. Re-analysing carries every decision by series **key**: a curated series whose key disappears (a different grouping) moves to `CurationArchive` and comes back with its key. An *accepted* fit that has since moved by more than half a level step, or changed its censoring, loses the acceptance and is flagged "fit changed since review (was X, now Y)"; a decision made under another method is flagged "reviewed under <method>".

## Peaks — `pickPeaks()`

Waves I–V (or the waves `Settings.Waves` names) are picked on the loudest level and **tracked** down each series (`mabr.analysis.Peaks.track`): each wave is expected where it was one level up plus its own latency shift, and candidates must stand `PeakCandidateRN × RN` proud. A candidate scores `prominence/max(prominence in the window) + λ·prior/max(prior)`; in a wave's own window (the loudest level) λ is 0.5 — **prominence leads**, the window centre breaks near-ties — and on a tracked level 5, the track leads. The waves of a level are **assigned jointly** (the ordered assignment with the largest summed score, a wave allowed to go without), and a tracked wave's window ends `MinSeparation` before where the next wave is expected — so a wave missed for a level cannot take the next wave's peak one level down, as wave I once took a click series' wave II. `Detectable` (`ProminenceRN ≥ PeakDetectableRN`, 4 by default) is a size criterion, **not a detection test**: a pick is the best of several local maxima, so noise picks are routinely 2–3 RN prominent; judge a response by the threshold. Per pick: `PeakLatency/PeakValue`, the trough, `AmpPT` (peak to trough), `AmpBP/AmpBT` (from the baseline), `ProminenceRN`, `Detectable`, `BelowThreshold` (from the series' Final), `EdgeAffected` (a windowed condition's pick near its edge), and with `PeakBootstrap > 0` the bootstrap SE and intervals of latency and amplitude.

The user's corrections are **anchors**: `setPeak` places a pick (snapped to the nearest extremum), `setPeakAbsent` marks a wave absent (at a level, or `Below=true` there and below), `clearPeak` / `clearPeakOverrides` take corrections back. A peak edit re-derives **only the level edited** — nothing anybody did not ask to move moves — and `retrackSeries(sk,wave,fromLevel)` re-tracks the levels below from the picks as they stand. `picksAsWindows(sk)` turns a series' loudest picks into wave windows (at the reference frequency, in the recording's time like every window) for the next analysis.

### Latency reference (sound conduction delay)

Time zero of a recording is the timing pulse — the electrical onset — and the sound reaches the ear later by its travel time (0.29 ms for 10 cm of air at 343 m/s). `Settings.ConductionDelayMode` ("none" / "delay" / "distance"), `ConductionDelay`, `SpeakerDistance`, `SpeedOfSound` and `TimeOffset` describe it; a session's offset is

```
Session.LatencyOffset = (Session.ConductionDelayOverride, else Settings.conductionDelay())
                      + (Session.TimeOffset,              else Settings.TimeOffset)
```

each part taken from the session when it is finite and from the settings the session was analysed with otherwise (0 with none). The two session properties (both `NaN` = none by default) are the per-session overrides `mabr.analysis.Project` sets from its `ConductionDelayOverride` and `TimeOffsetOverride` columns. It is a **reporting correction and nothing else**: the wave windows are in the recording's own time (the TraceInspector windows they come from were drawn up on recordings) and are searched there whatever the delay, latencies are **stored raw**, and `Peaks.reported(PeakLatency, LatencyOffset)` — the one place the offset comes off — is the latency re sound arrival. So setting a delay moves every reported latency by exactly itself and changes **no pick**; windows moved by it searched 0.29 ms later for 10 cm of air, and a peak near the edge of two overlapping windows changed its label when the delay was switched on. `Peaks.LatencyOffset` records the offset each pick is reported with. Interpeak intervals are differences and do not depend on it.

The settings' own rules:

- `settings.conductionDelay()` is 0 under "none", `ConductionDelay` (ms, as measured — tubing included) under "delay", and `10·SpeakerDistance/SpeedOfSound` ms under "distance" (cm over m/s: 10 cm at 343 m/s is 0.29 ms). `settings.latencyOffset()` adds `TimeOffset`, a further fixed offset of the recording system (an onset-rounding bias, say), which applies under every mode.
- `problems()` checks each number only under the mode that reads it: a delay must be finite and 0 or more, a distance in (0, 500] cm, the speed of sound 300–400 m/s.
- `describe()` says which reference is in force: "Latencies re sound arrival: 0.29 ms conduction delay (10 cm at 343 m/s).", or "Latencies re stimulus onset (no conduction delay)."
- All five belong to the **peaks** step (`Settings.stepOf`): they change what latencies read, never a pick, a detection or a threshold; changing one re-runs peaks (the same picks, a new `LatencyOffset` column) and nothing earlier. With the defaults (mode "none", `TimeOffset` 0) the offset is 0 and nothing anywhere changes.
- `picksAsWindows(sk)` gives windows in the recording's time, like the picks, so a delay does not move them either.

## Edits, the cascade, undo

Every edit is by key, appends a row to `EditLog` (`Time, User, Action, Key, Old, New`), is **atomic** (an error or a cancel leaves the session as it was) and returns a report struct `Action, Keys, Before, After, Text` — the line the app echoes:

```matlab
rep = s.setSweepsRejected(ck,cols,true);   % by hand, stored by (FileId, SweepIndex)
rep.Text                                   % "70 sweep(s) rejected in Tone, 8 kHz, 30 dB. Re-tested ...: p 0.00995 -> 0.498."
s.clearManualRejections(ck);               % [] = all
s.setDetectionOverride(ck,1);              % 1 response, 0 none, NaN automatic: the series is re-fitted
s.setExcluded(fileIds,true);               % leave files out: re-segment what they touch, then the cascade
snap = s.editSnapshot();  ...;  s.restoreEdits(snap);    % undo / redo
```

A data edit runs `recompute(keys)`, the **cascade**: reject → detect → measure (their series) → thresholds → peaks for what it touched, each with the options the session was analysed with — never anybody's current settings.

## The canonical pipeline — `analyze()` — and staleness

`analyze(settings)` runs every step (or `Steps=...`, or `From="thresholds"` and later) and records, per step, `StepState.<step> = struct(At, Settings, Fingerprint)`: when, the settings the step read (`settings.stepSettings(step)`), and the data fingerprint (`Session.fingerprintOf`: every `.abr` file's id, size and modification time, and the exclusions). `[tf,D] = s.isStale(settings)` lists what differs, step by step (`Step, Field, Old, New`; Step "data" when the files changed), and `Settings.firstChangedStep` says where re-running must start: changing the threshold method re-fits thresholds in a second, changing the filter re-segments. `Session.estimateSeconds(settings,fromStep,nFiles,nConditions,nSeries)` is the heuristic behind the app's button labels.

**Replication.** `adoptEdits(E)` takes the edits of a results file — or of a plain struct holding only edit tables (`ManualRejections, DetectionOverrides, PeakOverrides, Exclude, Thresholds` with `Key` and curation columns, `CurationArchive, EditLog`; any may be missing) — and the next `analyze(settings)` reproduces the original results **bit for bit** (per-condition seeds; hand rejections re-applied by `(FileId, SweepIndex)`, never by a column index a re-segmentation moves). This is what `Batch` does with an existing results file and what a replication script written by `mabr.analysis.ScriptWriter` does with its literal tables. One caveat: a peak edit re-derives only the level edited, while `analyze` re-tracks a whole series from its anchors — so the levels *below* a hand-placed or absent pick come back as a re-track gives them (as they also do after `retrackSeries`).

## Batch

`mabr.analysis.Batch.run(items,settings)` analyses each session of an items table (`Key, Paths, ResultsFile`, optionally `Exclude, UnitOverride, TestMode, Name, TimeOffset, ConductionDelay`); `runFolder(root,settings)` builds the items from a `Catalog` of a data folder and the study's `Project` (its pools and per-session overrides). Per session: Test Mode sessions are skipped unless asked for; sessions whose results are **current** (`Batch.isCurrent`: every step's settings and the fingerprint match, and the results were made with the same per-session overrides — `UnitOverride`, `TimeOffset`, `ConductionDelay`) are skipped; otherwise the session is read, the edits of its existing results adopted, analysed, the previous results copied to `<results>/.history` (the newest three kept) and the new ones written without sweeps. A failure is caught per session and logged; the log CSV (`<results>/logs/batch_<stamp>.csv`: `Key, Status, Seconds, Message, SettingsHash, ResultsFile`) gains each line the moment its session ends. `CancelFcn` stops after the session in progress; a progress sink that throws `mabr:analysis:cancelled` stops the session in progress, writing nothing for it. `SummaryFigure=true` writes the grid and the audiogram as `<results>/figures/<key>.png`. Batch never writes a preference and never opens a window. `examples/analyze_project.m` is the script form.

Given `Project=p`, `run` takes the per-session overrides of any item that lacks the `UnitOverride`, `TimeOffset` or `ConductionDelay` column from `p.sessionOverrides(key)`, and records each outcome with `p.recordRun(key,err)`; `runFolder` builds its pool items with `p.batchItems` — so a work list made by hand, by `runFolder` or by the app analyses each session the same way.

## The study — Catalog, Project, Export

`mabr.analysis.Catalog(root)` lists every session under a data folder without analysing one; `mabr.analysis.Project.open(catalog.ResultsFolder)` holds what the files cannot say — subject group, timepoint, in-study, free columns, pools, and the per-session overrides (`InputFullScaleOverride`, `AmplifierGainOverride`, `TimeOffsetOverride`, `ConductionDelayOverride`; ms, `NaN` = none). `p.applyOverrides(session,key)` is the one place they reach a `Session`; `p.batchItems(keys,catalog)` is the same rows as a `Batch` work list.

`p.view(catalog,settings)` gives each session a `Status`: `none` (no results), `current`, `stale` (`StatusText` "Out of date (settings changed)", "(files changed)", or "(overrides changed)" — the project's overrides differ from those the results were made with, which is also when `Batch` re-runs a session it would otherwise skip) or `failed`. `p.aggregate(keys,catalog)` builds the study tables from results files alone, and `p.exportItems(keys,catalog)` is the input of `mabr.analysis.Export.tables`, whose `Labels` carry `TimeOffset` and `ConductionDelay` (the project overrides).

**Exported latencies are re sound arrival.** Each `lat_*_ms` is `Peaks.reported(lat_peak_raw_ms, offset)`, with `conduction_delay_ms` and `time_offset_ms` beside it (their sum is the offset). The offset is the project override when one is set — so changing a session's conduction delay moves its exported latencies by exactly that much at once, and changes no threshold — else the `LatencyOffset` the peaks were picked with (the results' `Peaks.LatencyOffset`), else the settings' `latencyOffset()`. Every override counts as set exactly when it is finite. Interpeak intervals do not depend on it.

## Replication scripts — `ScriptWriter`

An analysis made in the app is the sum of things that are easy to lose track of: which files were left out, every setting in force, and the hand edits. `mabr.analysis.ScriptWriter` writes all of it down as one plain MATLAB script that needs nothing but MABR and the data — no window, no preference, no project file — and reproduces the analysis **exactly**:

```matlab
code = mabr.analysis.ScriptWriter.session(S);              % an analysed Session
code = mabr.analysis.ScriptWriter.session("results.mat");  % or its results (v2 struct or file)
code = mabr.analysis.ScriptWriter.study(p.exportItems(keys,c));   % several sessions and their export
file = mabr.analysis.ScriptWriter.write("replicate_analysis.m",code);   % UTF-8, folder created
s    = mabr.analysis.ScriptWriter.literal(x);              % eval(s) is isequaln to x
run(file)
```

Options (both `session` and `study`): `Title`, `DataRoot` (the folder session paths are written relative to; `""` = their common parent), `OutputFolder` (`""` = a `mabr_replication_<stamp>` folder under `tempdir`), `IncludeEdits` (true), `IncludeExport` (true), `ExportOptions` (`Tables, ThresholdsAll, OnlyReviewed, IncludeExcluded, IncludeTestMode, WaveformWindow, Subjects, BlockSize` for `Export.tables`, `Formats, Prefix, Append` for `Export.write`, `RScript`), `IncludePlots` (false) and `IncludeCheck` (true); `session` also takes the export `Labels` and `Notes`. `write` makes the file name a valid MATLAB identifier (a script runs by its name) and returns the name it wrote.

The script has six `%%` sections, in order:

1. **Header** — what it reproduces, what wrote it (the MABR commit from `git rev-parse --short HEAD`, or "unknown"; the MATLAB version; the time), and how to point it at moved data.
2. **Setup** — `MABRROOT`, `DATAROOT` and `OUTFOLDER`, and MABR on the path the way `MABR.m` puts it there (every folder but `.git`). `DATAROOT` and `OUTFOLDER` are assigned only when not already defined, so a caller can set them and `run(file)`.
3. **Settings** — `mabr.analysis.Settings(...)` with **every** property written as a literal (the A9 conduction-delay settings included), followed by `assert(settings.hash() == "<hash>", 'mabr:analysis:ScriptWriter:settingsHash', ...)`: if a later MABR adds a setting or reads one differently, the script stops and says so rather than quietly analysing something else. Sessions analysed with different settings get one variable each (`settings`, `settings2`, …).
4. **Per session** — `S = mabr.analysis.Session(<paths>, Name=, Key=, Exclude=<FileIds>, UnitOverride=<struct>, Verbose=true)`; then `S.TimeOffset` and `S.ConductionDelayOverride`, both always written and `NaN` when the session has none (so the settings' offset and delay apply); then the recorded edits replayed as literal tables (`edits = struct('ManualRejections',…,'DetectionOverrides',…,'PeakOverrides',…,'Thresholds',<Key + curation columns>,'CurationArchive',…)` and `S.adoptEdits(edits)`); `S.analyze(settings)`; and the **check**: the values recorded when the script was written — each series' `Threshold, Status, Censored, Final*, Decision`, each condition's `p, isSig, Detected, nClean, nRejected`, each pick's latencies, values and `LatencyOffset` — compared by key with `isequaln`, printing "replicated exactly" or every value that differs. A floating-point value within 1e-6 of its own size of the recorded one is rounding, not a different analysis, and is counted rather than listed ("replicated (n values compared; m of them within floating-point rounding …)"): a session opened from a results file written before the condition means were stored in double precision re-picks its peaks from single-precision means, ~1e-8 ms from the picks the script makes from the raw files. The check **never throws**: a failed comparison must not cost the analysis above it, and a difference is information (`<missing>` values included).
5. **Export** — `Export.tables`, `write`, `writeRScript`, `writeDictionary` and `writeManifest` into `OUTFOLDER`, every option written out so a later change of a default cannot change what it exports. The raw tables (`trial_waves`, `blocks`, `block_waves`) are built from the sessions just analysed; `sweeps` is written per session by `Export.writeRaw`, as Parquet when the formats are CSV.
6. **Figures** (`IncludePlots`) — the response grid and the audiogram.

It re-runs the analysis rather than carrying results across; a version 1 results file or a session never put through `analyze` records no settings, so `session` refuses it (`mabr:analysis:ScriptWriter:notReplicable` / `notAnalysed`) and `study` leaves it out (`info.Skipped`). One known difference: a peak placed by hand at one level with no re-track below comes back re-tracked (see *Replication* above), and the check lists those lower levels rather than failing. `EditLog` and `Analyst` are history, not inputs, and are not replayed.

## Results files (v2)

```matlab
s.saveResults("results/SUBJ-ID-1107_260903.mat",IncludeSweeps=false);
r = mabr.analysis.Session.fromResults("results/SUBJ-ID-1107_260903.mat");   % results only
r.loadRaw();                                     % read the raw data again; every result is kept
```

A results file is **separate plain variables** — `Version` (2), `Provenance`, `Settings`, `StepState`, `Summary`, `Files`, `Conditions` (without cell columns), `Means` (doubles, as computed, so a session opened from its results re-picks exactly the peaks its raw files give; older files hold singles), `SweepInfo` (every per-sweep flag as flat vectors), `Detection`, `Thresholds` (fits without function handles), `CurationArchive`, `Peaks`, `PeakOverrides`, `ManualRejections`, `DetectionOverrides`, `Messages`, `EditLog`, and `Sweeps` only when asked for — so `load(f,'Version','Summary','StepState','Thresholds')` reads the small parts alone, and nothing needs a particular class version to open. Written atomically (a temporary file moved into place). A results-only session (`HasSweeps` false) has every result, every per-sweep column and the condition means; it cannot segment, reject, detect or measure until `loadRaw()` reads its files again — with the saved options of those steps, the hand decisions applied again, and a warning "raw data changed since analysis" when the counts no longer match. Version 1 files (one struct) still load.

## Plots

Every figure is a static method taking plain data, so it can be drawn from results loaded out of a saved `.mat` long after the object that made them is gone:

```matlab
mabr.analysis.Plot.grid(S,t,levels,freqs,Threshold=thresh);
mabr.analysis.Plot.audiogram(freqs,thresh,CI=ci);
mabr.analysis.Plot.stack(S(:,1),t,levels);         % one frequency as a waterfall
mabr.analysis.Plot.detection(fitOut);              % the evidence behind one threshold
mabr.analysis.Plot.waveform(X,t,Band="ci");        % one condition, mean and band
```

## Messages and progress

Model classes never print except under `Verbose`, and never raise dialogs. Every note and warning is a row of `s.Messages` (`Time, Level, Step, Text`; a step's rows are replaced when it re-runs) and is handed to `s.MessageFcn`. Saving is not a step and leaves no row: `saveResults` prints `Saved <file>.` under `Verbose` and records nothing, because the app saves after every edit and `Messages` is written into the file — a row per save would grow every results file by a line an edit (a "save" row an older MABR wrote is dropped at the next save). Long loops report through an explicit progress sink, `s.ProgressFcn = @(message,count,total) ...`; a sink that throws `MException('mabr:analysis:cancelled',...)` cancels the step, which then leaves the session unchanged.

## Testing

`tests/verify_analysis.m` drives the direct-call pipeline over a synthetic session and checks the recovered waveform, the flagged sweeps, the permutation statistics against a naive implementation, and the thresholds against the level the response was built to appear at. `tests/verify_offline_session.m` covers pools, keys, acquisition modes, windowed processing, atomic steps and results v2; `tests/verify_offline_analyze.m` covers part B — the measures, named methods, curation across re-analysis, peaks and the conduction delay, the edits and undo, replication from edit tables, Batch, (Part L) the whole chain end to end: a synthetic study through `Catalog`, `Project`, `Batch`, `view`, `aggregate` and `Export` to CSV files read back, with a per-session conduction delay moving the exported latencies by exactly its amount, and (Part M) a noiseless session and an all-zero channel analysed in seconds, every condition untested and flagged, every series "insufficient", with TFCE bounded on near-noiseless sweeps and unchanged on noisy ones. A typed `GroupBy` is held to keep stimuli apart (`verify_offline_analyze` Part C) and acquisition modes apart unless pooled (`verify_offline_session` Part D). `verify_offline_catalog` covers `Catalog` and `Project` (including that `aggregate`'s per-file cache gives exactly what a fresh project computes, after label edits and after a results file is rewritten), `verify_offline_export` covers `Export`, and `verify_offline_script` runs the scripts `ScriptWriter` writes and holds their results and exports equal to the originals. `verify_offline_session` Part L also asks MATLAB's own dependency analysis (`requiredFilesAndProducts`) and accepts nothing beyond MATLAB and the Signal Processing Toolbox for any file of the package. None needs hardware, a pool or a preference.

## Relationship to `abr_analysis/`

The function pipeline is unchanged and still works. These classes read the same `.abr` files and reproduce its results; the differences are deliberate:

- conditions are a keyed table rather than an N-D cell array, so nothing hard-codes two parameters;
- files sharing a condition are **concatenated**, where `extractABRResponses` silently overwrote;
- conventional and interleaved runs are separate series, and compact files are filtered window by window;
- artifact verdicts are flags, not deletions;
- the acquisition rig's own artifact flags and per-sweep polarity are read in;
- Test Mode files are called out, loudly — those samples are the stimulus, not a subject;
- thresholds are censored answers, with the human decision kept beside the method's;
- no Statistics, Curve Fitting, or File Exchange dependency;
- permutation statistics are vectorized across permutations.
