# Testing

MABR ships a verification suite that runs with **no audio hardware**. It requires the Parallel Computing Toolbox, because it exercises the real acquisition engine on a real parallel worker. The offline-analysis scripts are the exception: they need no pool (see [Offline analysis](#offline-analysis)).

```matlab
>> run_all_verifications
```

```text
== verify_isi_jitter ==
  PASS Part A: 'fixed' spacing unchanged (3840 samples, 20.00 ms)
  ...
== verify_engine_loopback ==
  PASS test 1: full block (head 512000, 125 onsets, loopback err 4.9e-06)
  ...

==== 24 / 24 verifications passed ====
```

A script passes by returning without throwing, which is the whole contract — `run_all_verifications` needs nothing else from it, and neither does the GUI's **Help ▸ Verification Tests…** window, which discovers the scripts rather than listing them.

Each script is independently runnable. The first run is slow — the parallel pool has to start. Two scripts size that pool to three workers for the compute-worker parts and **skip those parts** where the machine's cluster profile cannot provide them.

## What each one covers

### verify_logging

[tests/verify_logging.m](../tests/verify_logging.m) — MABR's printing and logging, which run through [granary](https://github.com/dstolz/granary) (`external/granary`). It is first in the suite because everything after it logs.

Seven parts: the host wiring (`LogRoot`, `PrefGroup`, and the `FacadeFiles` that keep a log line credited to the code that raised it rather than to `mabr.log.vprintf`); every calling shape the toolbox's call sites use — literal, formatted, red, and log-only; caller attribution read back out of the file; the format policy that makes a message given **no** values literal text, so a Windows path or a stray `%` survives; the two independent verbosity gates, where a message too quiet for the command window is still on the record; an exception logged as one attributed record rather than a timestamped line per stack frame; and MABR still printing, without throwing, when the submodule is off the path.

The probes go to a temporary log and the user's log directory and verbosity globals are put back on the way out, including on an error exit — so running it does not fill a rig's own daily file.

Unlike `verify_stimgen_import` it does **not** skip when its submodule is absent: stimgen is optional at runtime and granary is not, so a clone that never fetched it has a real fault to hear about.

### verify_test_mode

[tests/verify_test_mode.m](../tests/verify_test_mode.m) — Test Mode, which copies the stimulus straight into the acquisition ring buffer. Asserts the copy itself (the ring against the rendered play matrix, timing channel bit-for-bit), the alignment report MABR draws from it after every run, the mark a Test Mode block and its `.abr` carry — and that the check can actually **fail**, by re-running it over deliberately corrupted onsets.

See [Test Mode](Test-Mode.md) for what a clean result does and does not establish.

### verify_engine_loopback

[tests/verify_engine_loopback.m](../tests/verify_engine_loopback.m) — the acquisition engine end to end in TESTING mode. Asserts that recorded frames land in the ring buffer, the write head advances during acquisition, and `Pause`/`Stop`/`Kill` sent over the queue take effect within about one frame.

This is the test that protects the core promise of the design: commands are honoured *during* playback, not between blocks.

### verify_data_roundtrip

[tests/verify_data_roundtrip.m](../tests/verify_data_roundtrip.m) — the `.abr` writer against the offline pipeline's contract. Builds a synthetic two-condition session, writes it with `io.writeABR`, then checks:

1. The `ABR_Data` struct exposes exactly the fields `abr_analysis/` reads.
2. The filename matches the pipeline's default regex.
3. If `parfor_progress` is installed, the **unmodified** pipeline functions `parseABRFiles` and `extractABRResponses` successfully load and group the files.

**Run this after any change to [io.m](../+mabr/+data/io.m).** A failure here means saved data is unreadable downstream — a breaking change, not a test to update.

### verify_legacy_import

[tests/verify_legacy_import.m](../tests/verify_legacy_import.m) — the import shim. Builds a legacy-shaped file with `SIG` stored as sigProp-style structs (a `.Value` field, as the old `abr.ABR.to_struct` produced) and confirms `io.importLegacy` unwraps them to plain numerics and that the reconstructed `Recording` segments sweeps identically to a direct index-based reference. Any real `.abr` found on disk is also imported as a structural smoke test.

### verify_online_advance

[tests/verify_online_advance.m](../tests/verify_online_advance.m) — early stopping and intermixing, in three parts. Part A checks the advance predicates in isolation. Part B drives the real `AcqController` in loopback with a **blocked** schedule and the correlation criterion, and asserts the run completes with far fewer sweeps than were scheduled. Part C schedules two stimuli with `shuffled-cycles` and asserts that one continuous intermixed run is de-interleaved back into one `Block` per stimulus ID, each with its full repetition count — and that the armed criterion does *not* fire, since intermixed runs play to completion.

Parts B and C are the only tests that exercise the full stack — controller, engine, worker, ring buffer, extraction, criterion, de-interleaving, finalization, save — in one pass.

### verify_loop_mode

[tests/verify_loop_mode.m](../tests/verify_loop_mode.m) — **Loop**, the Run panel toggle that holds the schedule on the run in progress. Part A checks `Schedule.loopRun` with no pool: a pass goes directly after its run and is that run again, presentation for presentation and sign for sign, and an intermixed plan is refused while a shuffled run order still loops; the rest of the plan waits behind it unchanged; a make-up run's pass is a full run of its stimulus and is not charged to the make-up budget; `dropPendingMakeup` leaves passes alone and `reset()` drops them. Part B writes two `.abr` files of the same name and asserts the second lands beside the first as `…_2.abr` with the first untouched — short loop passes make same-second names likely. Parts C–E drive a real `AcqController` in loopback: a run held for several passes, each its own block and file, all credited, then the plan going on once Loop is cleared; **Advance** moving on to the next run, which is then held in its turn; **Abort** halting; an intermixed plan played once with `Loop` set; and stimulation only looping the same way, one stimulation log per pass.

### verify_stimulus_alignment

[tests/verify_stimulus_alignment.m](../tests/verify_stimulus_alignment.m) — the correspondence every other number rests on: **the samples recorded at the onset a timing pulse marks are the stimulus the schedule placed there.** Sweep extraction, de-interleaving, the live means, the per-condition metrics and every `.abr` file inherit it, and none of them can detect it going wrong on their own.

The bank is what makes it testable. Each condition is identifiable *from its own samples* — one frequency per column of the design, one amplitude per row — so "is this attributed correctly?" becomes arithmetic: a mean sweep must peak at its own `Frequency`, and the 30 dB step between levels must come back as a 31.62× amplitude ratio. The frequencies are chosen to survive both the decimation to 12 kHz and the display low pass, so nothing the analysis path legitimately does can move the peak the test looks for. A control assertion covers the other direction: at one level the two frequencies must *not* differ in amplitude, which fails if the frequencies have been swapped between conditions.

In loopback the DAC frame *is* the ADC frame, so it asserts the strongest form available — recovered onsets sample-exact against `ExpectedOnsets`, and the samples at each onset bit-identical to that stimulus's waveform times its polarity. Eight parts: the plan, the recording, de-interleaving into `Block`s, the metrics (through `evaluateJobs` *and* a real `MetricPlot`, keyed by condition), the live per-condition statistics, **the live path as it actually runs**, alternating polarity, and the same run again through the compute workers.

That sixth part is the one that earned its keep. Extracting a finished block in one call and extracting it in forty slices are different code — `extract_sweeps` keeps a cursor — and only the second sees a timing pulse straddling a slice boundary. Driven through `mabrtest.GrowingRing` (which replays a completed recording a slice at a time, so the boundaries land where the test wants rather than wherever a 20 Hz timer fell), it found a real defect: a boundary more than the shadow interval into a pulse counted that pulse twice, giving **56 sweeps for 48 presentations**. The live count over-read, every sweep after a duplicate was attributed to the wrong presentation, and the advance criterion fired early. Saved files were never affected — finalization reads the whole block at once. Test the incremental path incrementally; a single-call check cannot see any of it.

**Also a rig diagnostic.** `verify_stimulus_alignment('Testing',false)` streams through the real device with the channel map from your saved audio prefs. There it asserts a *constant* onset offset — reporting the loop-back latency in samples and ms — rather than zero, and skips the bit-exact waveform comparison, since what returns through a converter is not what went out. Everything else is asserted identically, which makes it the check to run after rewiring a rig or changing a sample rate.

### verify_progress_monitor

[tests/verify_progress_monitor.m](../tests/verify_progress_monitor.m) — the progress window, against a real `Schedule` with no engine and no pool. Asserts the tally (planned presentations per stimulus, and what a recorded run credits), each of the three views, counts/percent/none on both the bars and the header, grouping by a stimulus parameter, and a heat map that leaves a **hole** (hatched) where the bank has no such condition and outlines the conditions being presented. Following a `mabrtest.FakeController`, it checks the header's run and plan lines and the percentage in the window title; that a run's sweeps stay in the tally between the end of the run and its credit; a pause read off the engine (`mabrtest.FakeEngine`) rather than the program state; the stimulation-only clock estimate, frozen by a pause and replaced by the recorded count; that a window opened mid-session shows no elapsed time; and that while the controller's `Loop` is set the header says `looping`, names an inserted pass `(loop)`, and quotes no time left. The stimulation-only part sleeps about a second in all, since what it tests is a clock.

Its sharpest assertions are the two that involve a run in flight, driven through `mabrtest.FakeController`: mid-run sweeps must be attributed by the run's own `runSequence` — the same pairing `finalize_run` de-interleaves by — and must be *given up* the moment the run is credited to `RunCounts`, or every sweep is counted twice. It also checks that the refresh rate limit actually suppresses a repaint and that `force` overrides it, since a window that repaints on every one of the controller's 20 ticks a second would cost more than it reports.

### verify_stimgen_import

[tests/verify_stimgen_import.m](../tests/verify_stimgen_import.m) — the stimgen bridge. Asserts a 2×2 variant grid becomes four entries at the DAC rate, that `informativeParams` is the *declared* list rather than every numeric scalar, that a `.spl` bank round-trips with its levels and repetitions intact, and that `Frequency`/`Level` produce a filename matching the offline regex.

Its sharpest assertion is an FFT of every generated waveform against the `Frequency` its own metadata claims. stimgen's `VariantReselectOnUpdate` defaults true, so reading a parameter back *outside* an update cycle silently advances to the next variant — metadata and waveform come apart, and an 8 kHz tone is saved labelled 16 kHz. Nothing about the signal looks wrong; only the pairing is. Test the pairing, not the parts.

**Skips and passes** when the `external/stimgen` submodule was never fetched — an absent optional dependency is not a failure.

## Offline analysis

Fifteen scripts cover the offline analysis: the `mabr.analysis` model classes and the analysis app (`mabr.ui.AnalysisApp`, [The Analysis App](Analysis-App.md)). They come right after `verify_analysis` in the suite.

None of them needs the Parallel Computing Toolbox, a device, or a pool. All of them follow the same rules:

- **Synthetic data with known truth.** `mabrtest.SyntheticABR` writes the files, so "is this right?" is a comparison with what was written, not a judgement. The window tests share a small analysed study, `mabrtest.OfflineFixture`: two subjects at Baseline and 2 weeks, plus a mixed tone/click session with both acquisition modes, batch-analysed into tempdir in under 20 s.
- **Everything in tempdir.** Each script writes under one `tempname` folder and removes it with an `onCleanup`.
- **Prefs put back.** `mabrtest.prefGuard` snapshots every pref the code under test may write and restores it, error exit included. Most scripts also assert that a script-driven run wrote **no** pref at all.
- **No person needed.** Every window is built invisible and every dialog a test would see is a stub. Timers are off (`AutoRefresh=false`), so a test calls `flush()` where a person would wait.
- **Nothing left behind.** Each script ends asserting that no `MABR_Offline*` timer and no figure it opened is left behind.

Several take longer than the ~60 s the other scripts aim for. The view scripts run roughly 35–135 s each, `verify_offline_app` the longest at about 115–135 s (down from 141), and `verify_offline_series` and `verify_offline_analyze` about 80 s each. Most of a view script's time is fixed cost: building the fixture (~15 s), opening the window, and its first draw.

### verify_offline_files

[tests/verify_offline_files.m](../tests/verify_offline_files.m) — `mabr.analysis.AbrFile`, the one reader every offline consumer goes through, so a wrong answer here is a wrong answer everywhere. It checks every field of every file against what was written:

- the current, "old" and stimgen naming styles;
- continuous and compact layouts;
- the E0 legacy era, a Test Mode file, an 11025 Hz file, a truncated compact window;
- then edited copies: reserved and duplicate parameter names, the three units eras, level units, dropped onsets with their numbers kept, files that are not recordings, a corrupt file.

Warnings are captured rather than printed, and the caller's warning state is untouched. It also covers:

- a **drift check**: SyntheticABR's field set must equal `mabr.data.io.buildStruct`'s, so the synthetic files cannot fall behind the real writer;
- `mabr.analysis.Stats`: percentiles bit for bit, F and t tails, FNV hashing, seeds, keys, natural sort, `balancedMean`;
- `mabrtest.prefGuard`;
- a static scan for Statistics Toolbox functions that a planted call must trip.

### verify_offline_stats

[tests/verify_offline_stats.m](../tests/verify_offline_stats.m) — the single-trial statistics (`mabr.analysis.SingleTrial`) and wave picking (`mabr.analysis.Peaks`), on in-memory sweeps with no files.

**Calibration under H0** uses 200 null conditions of coloured noise with a polarity-locked cochlear microphonic as large as the noise. On them, the power test rejects at its nominal rate, Fsp averages about 1, and RN is σ/√N. A test that pooled the CM into its noise would fail exactly there. It also checks:

- the split-half r with mean halves equals (F−1)/(F+1);
- the ± reference cancels the CM;
- RN falls as N^−0.5.

The template amplitude averages 1 over a condition with a response and is NaN for every sweep of one holding noise alone.

**The next-louder correlations** (Part F): `xcorrUp` finds a later, quieter response at its lag and stays bounded over 100 lags. `dtwUp` recovers a rigid shift exactly (r 1, the lag, no spread). On the synthetic template 10 dB down, where wave I is 0.15 ms later and wave V 0.30 ms, it lines up both (r above 0.99, against `xcorrUp`'s 0.90). It never lines up an *earlier* response, gives the lag-0 r when there is no room to warp, and on pairs of independent noise averages its median r is within 0.05 of `xcorrUp`'s. Without its smoothing the median is above 0.4, so removing the smoothing fails the test.

**Peak picking:**

- parabolic refinement is unbiased to well under 20 µs;
- waves I–V are found on the synthetic template;
- tracking follows them down to threshold without swapping labels, including series whose latencies grow half and one and a half times as fast as the defaults;
- a wave I missing for two levels leaves wave II its own peak (Part K): the waves of a level are assigned together, so a missing wave cannot take its neighbour's;
- manual and absent anchors behave as documented;
- `wavesFor`'s `Offset` moves a set of windows, and a series 0.3 ms late tracked in windows moved by that much gives the same waves, with the latencies returned raw.

### verify_offline_thresholds

[tests/verify_offline_thresholds.m](../tests/verify_offline_thresholds.m) — the threshold layer with no file or session:

- `SeriesThreshold`'s named methods on the **real permutation p-values** of the reference session (perm-descending's intervals, the lowest_level convention, and perm-glm within one step of them);
- the canonical series and the one-level cases, with exact Status / Censored / bounds. The descending rule walks down from the loudest level: a run of detections below two misses is only flagged, and the real 32 kHz `suthakar-liberman` (next-louder correlation) series no longer reads 18 dB; the retired Id `xcorr` resolves, estimates and stores as `suthakar-liberman`;
- `xcorr-dtw`: the methods table (eight methods, labels, metrics, criteria), the descending rule on `DTWUp` at 0.40 and blind to `XCorrUp`, its bootstrap interval, a custom method on the `dtw` metric, and its definition sentence following `MaxLag`;
- Suthakar & Liberman 2019's own tree (`SuthakarLiberman`): paths A–D and "insufficient", each reached by data built for it; the sigmoid and power2 thresholds against their closed forms; the interval bracketing the threshold; power2 leaving out levels at or below 0; no warning; the correlogram as xcov 'coeff', with lag 0 equal to `xcorrUp`'s r0 and a 3-sample delay peaking at +3;
- usable levels, each ignored level flagged with its reason ("level ignored at 0 dB: 10 clean sweeps, fewer than the minimum of 100"), and borderline detections flagged at 1000 permutations but not without a permutation count or at 10⁵;
- overrides, conventions and the curated value for every decision;
- an attenuation axis;
- the Firth GLM, finite under complete separation, with a profile CI that contains the generating threshold;
- the ABRpresto-like fit's branches;
- `Threshold.fit`'s defaults, reproduced **bit for bit** from literals recorded before it was changed.

`mabr.analysis.Settings` is covered too: defaults (the wave windows equal `Peaks.defaultWaves`), steps and staleness, the forgiving struct round trip, profiles, `.mabraset` files, `problems()`, and the conduction delay by mode.

### verify_offline_session

[tests/verify_offline_session.m](../tests/verify_offline_session.m) — `mabr.analysis.Session` from files to conditions, on synthetic files:

- **Pools**: two sibling folders read as one, a file copied into both read once, two subjects refused.
- **Mixed tone + click folders** in the current and the old naming, which used to crash with `badsubscript` or silently pool clicks with tones.
- **Acquisition modes**: conventional and interleaved runs separate unless pooled, and kept separate by a typed GroupBy that leaves AcqMode out (Part D: AcqMode is added, but not when the modes are pooled).
- **Windowed processing**: every compact sweep is its own window of its file and nothing else.
- **The acceptance test for the windowed operator**: waves II–V within one sample of the whole-trace FIR average.
- **Per-condition seeds**: a subset re-test is bit-identical to the full one.
- **Atomic steps**: a cancel inside any step leaves the session exactly as it was.
- **Results v2**: a 54-condition session under 2 MB, reloaded results-only with every per-sweep column rebuilt. Saving adds no row to `Messages`.
- **Non-finite samples** (Part N): NaN and Inf samples in a continuous and a compact file cost only the sweeps they reach. The kept sweeps are bit for bit the clean session's (the compact file's to 10⁻¹²), every other condition is untouched, a warning names both files, and the session still analyses.

The regression checks for defects 7, 9, 10, 12, 13, 14, 15 and 17 are here, along with a scan that no `+mabr/+analysis` file needs the Parallel Computing Toolbox.

### verify_offline_analyze

[tests/verify_offline_analyze.m](../tests/verify_offline_analyze.m) — everything after detection, and `mabr.analysis.Batch`:

- **Measures**: the RN and its ± reference agree where there is no response. `XCorrUp` and `DTWUp` are NaN at each series' loudest level, and `DTWUp`'s lag stays within the allowance.
- **Named thresholds**: within one level step of the truth, `suthakar-liberman` and `xcorr-dtw` included; results saved under the retired `xcorr` are current for `suthakar-liberman`. `SuthakarLiberman.fromSession` reads `XCorrUp0` and each pair's correlogram, at lag 0 that pair's `XCorrUp0`, identically from the sweeps and from a results file.
- **Staleness**: a Criterion change makes thresholds alone stale; a touched file makes the data stale. Results saved without `DTWUp` are stale from the measures for `xcorr-dtw` and current for every other method, and re-fitting only their thresholds refuses with `noMeasures`.
- **Curation survives re-analysis**: accepted, manual level, no response and excluded decisions are kept. A moved fit loses its acceptance with "fit changed since review", and a GroupBy change archives decisions and restores them. A typed GroupBy keeps the stimuli apart (Part C): "Frequency" gives the default series keys, and "Level" on a Frequency axis mixes no stimuli.
- **A single-level session**: "insufficient" or "all-respond", never "no-response".
- **Peaks** against the truth.
- **Every edit and its cascade**, and undo.
- **The sweep cap and unit overrides.**
- **Replication** (a new Session given only the edit tables reproduces the original bit for bit).
- **The conduction delay** (Part I): a 0.3 ms delay, as a session override and through the settings, changes no pick, no threshold and no `picksAsWindows` window, and moves every reported latency by exactly the delay.

The **Batch** checks cover statuses, a broken session failing while the rest finish, the log written as it goes, skips and re-runs, curation carried over, cancel, `.history` pruned to three, an unreadable results file analysed afresh (the message says so, the file kept in `.history`), and no pref written.

**Part L** is the end-to-end check. A synthetic study goes through Catalog, Project labels, `Batch.run`, `Project.view` (all current) and `aggregate`. Then every results-only table is exported as CSV and read back with no NaN/Inf text. Last, a per-session conduction delay is shown to move the exported latencies by exactly that amount.

**Part M** is the "no noise" check. A noiseless session and an all-zero channel analyse in seconds with the recommended settings (a noiseless session once ran past 13 minutes without finishing). Every condition is untested (p NaN) and flagged zero variance, F, SNR, the power test, Fsp and the split-half r are NaN, both series are "insufficient" for zero variance, and the warnings name the conditions. Noiseless sweeps tested without their polarities get a raised TFCE step instead of hanging, and a noisy condition's TFCE test is exactly `PermTest`'s own.

### verify_offline_catalog

[tests/verify_offline_catalog.m](../tests/verify_offline_catalog.m) — study discovery (`mabr.analysis.Catalog`) and the project store (`mabr.analysis.Project`), over a study tree that has every awkward case in it:

- two spellings of one subject, a short run, Test Mode;
- a corrupt file and one that is not a recording;
- hidden and recycle-bin folders;
- a nested results store and an ancestor store.

**Catalog:** keys, natural subject order, days, the summary text, short runs, notes scoped to the session, where results go, `suggestStudyRoot`, and the cache. A rescan opens only what changed, and a stale or foreign cache is rebuilt silently. **Every scan is bracketed by a snapshot of the study: nothing is written under it.** Part G holds each session's counts, modes and short runs against a real `Session` over the same folder.

**Project:**

- `open`/`ensureSessions`/`view` write nothing;
- timepoints follow the same-day rule;
- labels are routed and coerced;
- pools;
- the atomic reload-merge-write save, where two writers keep each other's rows;
- view statuses;
- `aggregate` under each duplicate policy, and its per-file cache;
- `exportItems`/`batchItems`;
- `importStore`.

### verify_offline_export

[tests/verify_offline_export.m](../tests/verify_offline_export.m) — `mabr.analysis.Export` against **hand-built** results, so every expected number is written down rather than computed by the code under test. It covers:

- the schema and naming rules;
- every table's columns in schema order;
- the **censoring columns** for interval, right, left, none and excluded series, with no Inf anywhere, and −Inf on an attenuation axis encoded like Inf;
- all-methods rows;
- peaks with latencies re sound arrival;
- CSV round trips (UTF-8, TRUE/FALSE, ISO times);
- XLSX limits;
- Parquet (skipped without `parquetwrite`), and MAT;
- the R script's models, the dictionary and the manifest;
- `estimate()`;
- appends that reconcile columns;
- the raw tables from a real Session.

### verify_offline_script

[tests/verify_offline_script.m](../tests/verify_offline_script.m) — `mabr.analysis.ScriptWriter`, and the claim is **exact** replication, so every check is an equality.

`literal(v)` must round-trip through `eval` for every supported type, including:

- NaN, ±Inf and −0;
- 64-bit integers past 2^53;
- strings with quotes and non-ASCII text;
- datetimes with time zones;
- tables, structs and Settings.

A session is analysed and then edited every way: a manual rejection, a detection override, a peak placed and one marked absent, and each kind of decision. Its generated script is run in a workspace of its own on a moved copy of the data, with a 0.3 ms conduction-delay override. It must reproduce Thresholds, Conditions, Peaks and every Rejected flag `isequaln`, and print "replicated exactly". So must the script of a session re-analysed from its results file, whose peaks come from the stored means. The same script's export must equal a direct export.

A study script over two sessions with different settings reproduces both. `checkcode` reports nothing on any generated file.

### verify_offline_app

[tests/verify_offline_app.m](../tests/verify_offline_app.m) — the window's shell and the parts every view shares (Model, Commands, Compat, Style, View, FigureExport, PromptDialog, NoteEditor). It checks:

- **Commands**: one keymap, no clashes, and every toolbar glyph drawn by `mabr.ui.Icon`.
- **The window**: lazy tabs, each its own view class. Opening a subject folder offers the study folder, and browsing writes nothing in the data.
- **Events** of every Model method in the specified order.
- **Undo**: every mutating command is undoable.
- **Keys**: the note editor swallows typing, and letters are ignored while a text control has the keyboard.
- **Saving**: autosave writes the results file. A file changed elsewhere is a conflict, not an overwrite. An unwritable folder makes the Model read-only, and choosing another moves the edits there (H2).
- **Unreadable files** (H3): an unreadable results file opens its session from the raw files, kept in `.history`; an unreadable `project.mat` makes the store read-only with its reason, and an edit is not retried; an export from a read-only store refuses, naming it.
- **Busy and cancel**: a cancel leaves the session unchanged, and closing while busy closes once the job unwinds, printing nothing.
- **Blind review** names no session or subject anywhere.
- **The acquisition guard.**
- **A conduction-delay override** reaches project and session, re-picks the peaks without moving one, and a delay set while a session was closed opens it out of date (N).
- **Prefs**: a script-driven run writes none.
- **Export**: figure export, the replication script (L2, which asks which sessions when several are selected and names the scope on the status line), tables, Export Again.

Part M holds the **R2021b floor**: no post-R2021b UI identifier outside `Compat.m` (a planted file proves the scan can fail), no Statistics Toolbox function, and `requiredFilesAndProducts` listing only MATLAB and the Signal Processing Toolbox.

### verify_offline_browser

[tests/verify_offline_browser.m](../tests/verify_offline_browser.m) — the browser and the Session tab:

- **The tree**: natural order, visit texts, status glyphs and badges, and in-place updates that keep what is expanded.
- **Search and Show**, and the typing debounce.
- **Selection**, Open, Analyse n sessions…, and pooling with its confirmation.
- **Labels**: a visit's timepoint labels the whole day, Group is per animal, In study, Comment.
- **The results link.**
- **The condition matrix**: −log10 p never negative and blank without a p, the final threshold's step line, click and double-click.
- **Notes and messages.**
- **The Files table's staged edits**, Apply and undo, the bulk buttons and the run-group actions.
- **The overrides row**: a conduction delay re-picks the peaks (to record the offset; no pick moves) and stays up to date, while a full-scale override goes out of date.
- **A nested store's banner.**
- **Blind review.**
- **Prefs** written only by the Session tab's own controls.

### verify_offline_grid

[tests/verify_offline_grid.m](../tests/verify_offline_grid.m) — the Grid tab:

- one axes per series under the Stimulus/AcqMode filters;
- significance from TFCE (`sigMask`) and from a cluster-mass re-analysis (clusters, never `sigMask`: defect 11);
- peak markers, one line per wave × kind;
- Compare with, hidden in blind review;
- every threshold key placing the Final and fit dividers at the right rows, with only that column redrawn;
- gestures and the context menu;
- a ragged grid's "not recorded";
- the conduction delay drawing traces and markers in ear time (raw time less the offset);
- an attenuation axis turning the stack over;
- the look controls redrawing in place and alone writing `OfflineAnalysisGrid`.

### verify_offline_series

[tests/verify_offline_series.m](../tests/verify_offline_series.m) — the Series tab:

- **Empty states**: no session, no level parameter. A single-level session is shown, with its list, trace and peaks, while the banner and the evidence plot say no threshold can be estimated.
- **Entering a series** at the level next to its threshold, and LevelMemory.
- **The stack**: glyphs and dividers. Every threshold button and its key give the same decision and one undo step.
- **The method dropdown** re-fits the project, makes other sessions out of date and runs nothing. The evidence plot per method family, Compare methods.
- **The audiogram** with series that have no frequency listed in words, and its rules (Part A): where a series is placed, and the level axis' unit.
- **Peaks**: 1–5 selection, snap, drag, nudges, candidates, absent, revert, p/u/Shift+U, the wave matrix, Bootstrap, picks as wave windows.
- **The conduction delay** (Part H): traces, picks and wave windows drawn 0.25 ms earlier on the ear-time axis, each window holding its pick; a drag stores raw time; "Use current picks as wave windows" stores recording-time windows, drawn centred on their picks.
- **An attenuation-axis session** (Part J), with NR and the evidence arrows on the right side.
- **Level parameter = Frequency** (Part K): no series on the audiogram, each listed beneath after the reason, the level axis in kHz; set back to Level, the audiogram returns.
- **The Suthakar & Liberman window** (Part N): its button is off on a single-level series. It opens one window on the series, where each correlogram at lag 0 is its level's `XCorrUp0`, lag 0 and the lag allowance are marked, both fits are drawn on `XCorrUp0` with the 0.35 line, and the path is stated and its threshold marked. The window follows the selection, the button raises it rather than opening a second, it changes no threshold, and Close closes it.

### verify_offline_trials

[tests/verify_offline_trials.m](../tests/verify_offline_trials.m) — the Trials tab, on a condition holding a rig note:

- **Load raw data** from a results-only session.
- **The header** equal to the Session's numbers.
- **The image**: sweeps in µV, rejected ticks, 99th-percentile colour limits, the note at its sweep.
- **Every control.**
- **Selection**: click, Shift+click in the order shown, Ctrl+click, a range.
- **Rejection**: r / Shift+R with the re-test reported and Ctrl+Z restoring every flag; Reject above in the condition and the series.
- **Panel (d)**:
  - the ± reference whose RMS is the stored RNPM;
  - convergence;
  - the permutation test with and without its null;
  - the split-half histogram whose mean is the stored r, bounded "partition 2.5–97.5%" and never "CI". Part H3 checks that a re-analysis with other measure options replaces the cached panels.
- **The 150 ms debounce** timer.
- **The conduction delay** (Part J): traces, wave windows and picks drawn 0.25 ms earlier, each window holding its pick, wave I at its reported latency.
- **The controls** at the window's minimum width, nothing cut off.
- **Reject above before `measure()`** (Part M), on a session read from raw and never measured, compares the tab's own feature, a ratio feature read as a plain number. It uses the template amplitude where the average holds a response to scale by, else the template r.

### verify_offline_study

[tests/verify_offline_study.m](../tests/verify_offline_study.m) — the Study tab:

- **The pure rules**: no-response and all-respond values, the shift and its hollow points, "First session", whom the settings banner names.
- **The Sessions and Subjects tables**: edits through `Model.label` with coercion, the comment through Edit comment…, columns.
- **Duplicates**: each policy and the banner.
- **The threshold plot**:
  - one point per subject × timepoint × series;
  - n in every legend;
  - the no-response ceiling and the rule in the subtitle;
  - shifts;
  - one panel per subject with one legend;
  - "(no timepoint)";
  - click and double-click.
- **Growth & latency** in µV, % of reference, and dB re threshold.
- **The grand average** as the mean of per-subject means.
- **The waveform grid** (All levels / All series):
  - every level stacked, loudest at the top, in a column per series, and a click family as one column;
  - each row's mean equal to the mean of its subjects' curves, offset by its row at its column's spacing;
  - the row spacing per column, global, or a fixed number of µV;
  - one legend outside the last column, which does not narrow that column;
  - Copy data in µV, not stacked positions;
  - colour by subject, and a column per subject and series;
  - All series at one level as a panel per series.
- **Banners**: the different-settings banner and Re-analyse them, and the clean-sweeps banner.
- **Blind review** switching the tab off.
- **The empty state.**

### verify_offline_dialogs

[tests/verify_offline_dialogs.m](../tests/verify_offline_dialogs.m) — every dialog driven by its Tags:

- **SettingsDialog**:
  - edits and how much they make out of date;
  - problems disabling OK;
  - Apply;
  - the waves table;
  - `.mabraset` save/load, profiles and Defaults;
  - the conduction delay row with its live "= 0.29 ms";
  - the onset-bias [Use it].
- **ExportDialog**:
  - estimates and per-table formats;
  - warnings and "Export anyway";
  - an export with `replicate_analysis.m` built with the export's own options;
  - options remembered by the Export button.
- **BatchDialog → Model.batch → BatchReport**, with Retry failed.
- **ReviewDialog** starting a queue as large as it said.
- **LevelsDialog** reordering, undoably.

Every dialog's OK/Start is disabled while the Model is busy, and every window remembers its position on every close path.

### smoke_offline_analysis (not in the suite)

[tests/smoke_offline_analysis.m](../tests/smoke_offline_analysis.m) — the same classes and window over the **real** study folder, `C:\Users\dstolz\My Drive\PROJECTS\OFC_NoiseExposure` by default:

1. Snapshot the study and guard the prefs.
2. `suggestStudyRoot` offers the study folder for `SUBJ-ID-1254`.
3. The catalog finds 6 sessions, 202 files, Tone/ClickTrain/Noise, the 54 compact files of 140000, and the 15-sweep click file a short run.
4. 140000 segments into 12 tone series and 1 click series, its interleaved conditions windowed over [0 9.917] ms.
5. A batch analyses all six. 140820's single-level series are flagged "insufficient levels", and 140845's thresholds are printed by perm-glm and perm-descending.
6. Every results-only table is exported as CSV and Parquet and read back.
7. The window opens 140845, shows every tab, and accepts and saves the 8 kHz fit.
8. The study is compared with its snapshot: **byte-for-byte unchanged**, with no `MABR_Analysis` anywhere under it.

Every result goes to tempdir. It is not a `verify_*` file, because it needs a folder only some machines have. Without that folder it prints SKIP and returns. It takes about 1½ minutes:

```matlab
>> smoke_offline_analysis
>> smoke_offline_analysis("D:\copy\of\OFC_NoiseExposure")
```

### tests/manual/spike_uifigure_input (by hand)

[tests/manual/spike_uifigure_input.m](../tests/manual/spike_uifigure_input.m) is the one check the analysis app's key routing rests on that a script cannot make. It opens an edit field, an editable table, a tree and an axes. It prints which callbacks fire, and in which order, while a person types, edits a cell, arrows through the tree, clicks the axes and presses keys (Alt+← included). Run it once on R2021b and once on the release in use.

## Writing a new verification

Follow the existing pattern: a plain function, no test framework, `fprintf` a banner, `assert` with messages, clean up with `onCleanup`, and add it to the list in [run_all_verifications.m](../tests/run_all_verifications.m).

Two conventions matter for keeping tests hardware-free and deterministic:

- **Construct the engine with `testing = true`.** `mabr.acq.Engine(cfg,true)` or `mabr.ui.AcqController(cfg,true)` runs the entire program with no device, feeding the outgoing frame back as the recorded frame.
- **Use `TestingFrameDelay` to pace loopback.** Without a device, loopback runs as fast as MATLAB can loop, which can starve the 20 Hz live-view timer that evaluates advance criteria. `Schedule.TestingFrameDelay` inserts a per-frame pause so timing-dependent behaviour is observable. It has no effect outside testing mode.

- **Set `Schedule.Seed` for a reproducible order.** Shuffled strategies otherwise reshuffle each time, which makes a failure hard to reproduce. `verify_online_advance` pins it so the intermixed assertions are deterministic.

- **Reuse one `AcqController` across test phases.** A second `Engine` maps the same ring-buffer files and contends for the single-process pool. `verify_online_advance` runs both its end-to-end phases through one controller, recording `Session.NumBlocks` beforehand to tell the new blocks apart.

Prefer building deterministic stimuli inline (as `verify_engine_loopback` does with a 1 kHz tone and fixed onsets) over relying on `demoStimuli`, unless you are specifically testing the demo path.

## What is not covered

The viewer windows are covered (`verify_live_plot`, `verify_progress_monitor`, `verify_trace_organizer`, `verify_trace_inspector`) by driving them the way a user does and reading back what they actually drew. So is the offline analysis — the `mabr.analysis` classes and the analysis app, window, tabs and dialogs (the [`verify_offline_*` scripts](#offline-analysis)).

Three things are not covered:

- **The acquisition main window itself**, `mabr.ui.App`. Changes there need manual verification on a rig.
- **The function pipeline in `abr_analysis/`**, beyond the file-contract check in `verify_data_roundtrip`.
- **Key routing in the analysis app on a real desktop.** The app's keys are tested through its dispatcher. Which callbacks MATLAB actually fires for a person's typing is the manual spike's job.

Real ASIO device behaviour is not covered by the suite either, by construction — every script runs hardware-free. Two of them double as **rig diagnostics** and are the way to cover it deliberately, on the machine that has the hardware:

```matlab
>> verify_timing_loopback('Testing',false)      % pulse recovery, jitter, drift, margin
>> verify_stimulus_alignment('Testing',false)   % onset latency, attribution, metrics
```
