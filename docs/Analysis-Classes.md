# The `mabr.analysis` classes

`+mabr/+analysis/` is the object-oriented offline pipeline: the same job as the `abr_analysis/` functions ([Offline Analysis](Offline-Analysis.md)) — saved `.abr` files in, thresholds out — reorganized so that each piece does one thing and batching is a loop you write rather than one baked into the functions.

Nothing here needs the Statistics, Curve Fitting, or Parallel Computing toolboxes, and nothing here needs a File Exchange download. It runs anywhere MABR runs.

## The shape of it

One class holds a **session** — one folder of `.abr` files, one animal, one sitting — and five methods take it from filenames to thresholds:

```matlab
s = mabr.analysis.Session("C:\data\abr_data\SUBJ-ID-1107\ABR_001");
s.segment();                 % filter each trace, window it into sweeps
s.reject();                  % flag artifact sweeps
s.detect();                  % permutation-test each condition
s.estimateThresholds();      % fit a threshold per frequency
s.plotGrid();
s.plotAudiogram();
```

A study is your own loop:

```matlab
paths = mabr.analysis.Session.find("C:\data\abr_data");
for k = 1:numel(paths)
    s = mabr.analysis.Session(paths(k));
    s.segment(); s.reject(); s.detect(); s.estimateThresholds();
    s.saveResults(fullfile(resultPath, s.Name + ".mat"));
end
```

Everything a step does to **one condition** lives in a separate class and can be called on its own, with no Session anywhere:

| class | what it does | unit it works on |
|---|---|---|
| `mabr.analysis.Session` | orchestration for one session | a folder |
| `mabr.analysis.Filter` | the zero-phase FIR band | one trace |
| `mabr.analysis.Artifacts` | per-sweep artifact detection | one condition |
| `mabr.analysis.PermTest` | sign-flip permutation test | one condition |
| `mabr.analysis.Threshold` | detection, and threshold fitting | one condition / one series |
| `mabr.analysis.Plot` | every figure | plain data |
| `mabr.analysis.Progress` | console progress | — |

So `mabr.analysis.PermTest.run(X)` tests one `[nSamples x nSweeps]` matrix from anywhere, and `mabr.analysis.Plot.audiogram(freqs,thresholds)` draws an audiogram from numbers that never came from a Session at all.

## Conditions are a table

`s.Conditions` is one row per stimulus condition, with a column per stimulus parameter:

```
    Frequency    Level    nSweeps    nRejected    Sweeps           p       isSig
    _________    _____    _______    _________    ___________    ______    _____
        8         30        512         14        {481x512}      0.0010    true
        8         60        512          9        {481x512}      0.0010    true
       16         30        512         21        {481x512}      0.4230    false
```

The parameter columns come from each file's `SIG.informativeParams`, so a bank that varies three things produces three columns and nothing has to be told which two they were. `grid()` reshapes to the `[level x frequency]` cell array and `U` struct the older functions use:

```matlab
[S,U,levels,freqs] = s.grid("Level","Frequency");
```

## Rejected sweeps are flagged, never deleted

`reject()` writes a logical per sweep and nothing else. `sweeps()` and every average exclude flagged sweeps by default; `s.sweeps(k,IncludeRejected=true)` gets them back. This is the rule the acquisition side already follows (`mabr.data.Recording.IsArtifact`), and it is what lets you change a rejection setting without reloading anything.

The rig's own verdict comes in with the data: `.abr` files carry `ADC.IsArtifact`, and `segment()` seeds the flags from it. Pass `HonorAcquisitionArtifacts=false` to start from a clean slate.

Two families of criterion, and they answer different questions:

```matlab
s.reject(Method="median", Feature="absPeak");            % relative: outlier among its neighbours
s.reject(Method="threshold", Threshold=100e-6);          % absolute: over 100 µV, full stop
```

A relative criterion adapts to each electrode and animal but always finds something, and can never condemn a uniformly bad condition. An absolute one is comparable across a session and can.

## Filtering happens before segmentation

`mabr.analysis.Filter` is the offline band — equiripple FIR, 300 Hz to 3000 Hz by default, run with `filtfilt` so no peak moves — and `segment()` applies it to each **whole continuous trace** before cutting sweeps out of it. A sweep is a few hundred samples; a filter's edge transient would land squarely on the response.

```matlab
s.Filter = mabr.analysis.Filter(HighPass=[100 200], LowPass=[2000 3000]);
s.segment();                              % re-cut with the new band
```

Re-segmenting is cheap: traces are kept in memory (`KeepTraces`, on by default), so trying a second band costs no disk reads. A design made elsewhere is accepted whole:

```matlab
s.Filter = mabr.analysis.Filter.fromObject(HdHP,HdLP);   % fdesign/dsp objects
```

## Detection

`detect()` runs a sign-flip permutation test on each condition, asking whether the sweeps contain anything time-locked. Three max-statistics, all two-sided and all family-wise corrected over samples, so the p-value needs no further correction:

- `clusterMass` — largest summed-t run above the t threshold. Sensitive to sustained deflections.
- `tmax` — largest |t| anywhere. Strictest, and the only one with no free parameter.
- `tfce` — threshold-free cluster enhancement. No cluster threshold at all; usually the most sensitive on ABR data.

```matlab
s.detect(Method="tfce", NumPermutations=2000, Seed=1);
```

**Seed it.** A threshold is fitted to these p-values, so an unseeded test makes the threshold itself jitter between re-analyses of the same data.

The permutations are vectorized — the sum of squares is invariant under a sign flip, so a whole block of permuted t-maps is one matrix product, and the cluster and TFCE statistics are computed for the block by run-length arithmetic rather than sample by sample.

## Thresholds, and what `Criterion` means

```matlab
s.estimateThresholds(Type="glm", FitTarget="binary", Criterion=0.5);
```

Four models, differing in what they assume:

- `glm` — binomial logistic regression on the binary detections. The psychometric reading.
- `sigmoid` — logistic growth curve on the graded detection strength.
- `isotonic` — monotone fit. Assumes only that detection does not get worse with level.
- `minimum` — the lowest level detected. No model; entirely determined by the level spacing.

**`Criterion` means two different things, and `FitTarget` decides which.** On binary detections it is a probability: the level at which a response becomes detectable half the time. On graded strength it is a fraction of the response range, so `Criterion = 0.5` is the **half-maximum of the growth function** — a larger number, because the response goes on growing after it first appears. Both are useful; reading one as the other is the easiest way to misreport a threshold. Ask for `FitTarget="binary"` explicitly when you want a detection threshold out of a sigmoid or isotonic fit.

A threshold that was never reached is `Inf`, not a made-up number. What to plot for it (usually `max(level)+step`) is your decision, not the fit's.

**Curation** keeps both answers:

```matlab
row = s.thresholdRow("Frequency",16);
s.setThreshold(row,45);        % your value goes in Curated; the fit stays in Threshold
```

## Plots

Every figure is a static method taking plain data, so it can be drawn from results loaded out of a saved `.mat` long after the object that made them is gone:

```matlab
mabr.analysis.Plot.grid(S,t,levels,freqs,Threshold=thresh);
mabr.analysis.Plot.audiogram(freqs,thresh,CI=ci);
mabr.analysis.Plot.stack(S(:,1),t,levels);         % one frequency as a waterfall
mabr.analysis.Plot.detection(fitOut);              % the evidence behind one threshold
mabr.analysis.Plot.waveform(X,t,Band="ci");        % one condition, mean and band
```

`mabr.analysis.Plot.palette(n)` carries perceptually uniform colormaps of its own, so nothing depends on `colorcet` being installed.

## Saving

```matlab
s.saveResults("results/SUBJ-ID-1107_260903.mat");
s2 = mabr.analysis.Session.fromResults("results/SUBJ-ID-1107_260903.mat");
```

The file is a **plain struct** of tables and arrays — deliberately not the object. A results file that needs a particular class version to load is one that stops opening the day the class changes. `saveResults(...,IncludeSweeps=false)` writes a much smaller file that still carries every answer.

## Testing

`tests/verify_analysis.m` builds a synthetic session on disk — real `.abr` files with a response that appears above a known level — and drives the whole pipeline over it, checking the recovered waveform against the one written, the flagged sweeps against the ones corrupted, the vectorized permutation statistics against a naive implementation, and the recovered thresholds against the level the response was built to appear at. No hardware, no pool, no preferences touched. It runs in the suite and in **Help ▸ Verification Tests…**.

## Relationship to `abr_analysis/`

The function pipeline is unchanged and still works. These classes read the same `.abr` files and reproduce its results; the differences are deliberate:

- conditions are a table rather than an N-D cell array, so nothing hard-codes two parameters;
- files sharing a condition are **concatenated**, where `extractABRResponses` silently overwrote;
- artifact verdicts are flags, not deletions;
- the acquisition rig's own artifact flags and per-sweep polarity are read in;
- Test Mode files are called out, loudly — those samples are the stimulus, not a subject;
- no Statistics, Curve Fitting, or File Exchange dependency;
- permutation statistics are vectorized across permutations.
