# Testing

MABR ships a verification suite that runs with **no audio hardware**. It requires the Parallel Computing Toolbox, because it exercises the real acquisition engine on a real parallel worker.

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

### verify_stimulus_alignment

[tests/verify_stimulus_alignment.m](../tests/verify_stimulus_alignment.m) — the correspondence every other number rests on: **the samples recorded at the onset a timing pulse marks are the stimulus the schedule placed there.** Sweep extraction, de-interleaving, the live means, the per-condition metrics and every `.abr` file inherit it, and none of them can detect it going wrong on their own.

The bank is what makes it testable. Each condition is identifiable *from its own samples* — one frequency per column of the design, one amplitude per row — so "is this attributed correctly?" becomes arithmetic: a mean sweep must peak at its own `Frequency`, and the 30 dB step between levels must come back as a 31.62× amplitude ratio. The frequencies are chosen to survive both the decimation to 12 kHz and the display low pass, so nothing the analysis path legitimately does can move the peak the test looks for. A control assertion covers the other direction: at one level the two frequencies must *not* differ in amplitude, which fails if the frequencies have been swapped between conditions.

In loopback the DAC frame *is* the ADC frame, so it asserts the strongest form available — recovered onsets sample-exact against `ExpectedOnsets`, and the samples at each onset bit-identical to that stimulus's waveform times its polarity. Eight parts: the plan, the recording, de-interleaving into `Block`s, the metrics (through `evaluateJobs` *and* a real `MetricPlot`, keyed by condition), the live per-condition statistics, **the live path as it actually runs**, alternating polarity, and the same run again through the compute workers.

That sixth part is the one that earned its keep. Extracting a finished block in one call and extracting it in forty slices are different code — `extract_sweeps` keeps a cursor — and only the second sees a timing pulse straddling a slice boundary. Driven through `mabrtest.GrowingRing` (which replays a completed recording a slice at a time, so the boundaries land where the test wants rather than wherever a 20 Hz timer fell), it found a real defect: a boundary more than the shadow interval into a pulse counted that pulse twice, giving **56 sweeps for 48 presentations**. The live count over-read, every sweep after a duplicate was attributed to the wrong presentation, and the advance criterion fired early. Saved files were never affected — finalization reads the whole block at once. Test the incremental path incrementally; a single-call check cannot see any of it.

**Also a rig diagnostic.** `verify_stimulus_alignment('Testing',false)` streams through the real device with the channel map from your saved audio prefs. There it asserts a *constant* onset offset — reporting the loop-back latency in samples and ms — rather than zero, and skips the bit-exact waveform comparison, since what returns through a converter is not what went out. Everything else is asserted identically, which makes it the check to run after rewiring a rig or changing a sample rate.

### verify_progress_monitor

[tests/verify_progress_monitor.m](../tests/verify_progress_monitor.m) — the progress window, against a real `Schedule` with no engine and no pool. Asserts the tally (planned presentations per stimulus, and what a recorded run credits), each of the three views, counts/percent/none on both the bars and the header, grouping by a stimulus parameter, and a heat map that leaves a **hole** where the bank has no such condition.

Its sharpest assertions are the two that involve a run in flight, driven through `mabrtest.FakeController`: mid-run sweeps must be attributed by the run's own `runSequence` — the same pairing `finalize_run` de-interleaves by — and must be *given up* the moment the run is credited to `RunCounts`, or every sweep is counted twice. It also checks that the refresh rate limit actually suppresses a repaint and that `force` overrides it, since a window that repaints on every one of the controller's 20 ticks a second would cost more than it reports.

### verify_stimgen_import

[tests/verify_stimgen_import.m](../tests/verify_stimgen_import.m) — the stimgen bridge. Asserts a 2×2 variant grid becomes four entries at the DAC rate, that `informativeParams` is the *declared* list rather than every numeric scalar, that a `.spl` bank round-trips with its levels and repetitions intact, and that `Frequency`/`Level` produce a filename matching the offline regex.

Its sharpest assertion is an FFT of every generated waveform against the `Frequency` its own metadata claims. stimgen's `VariantReselectOnUpdate` defaults true, so reading a parameter back *outside* an update cycle silently advances to the next variant — metadata and waveform come apart, and an 8 kHz tone is saved labelled 16 kHz. Nothing about the signal looks wrong; only the pairing is. Test the pairing, not the parts.

**Skips and passes** when the `external/stimgen` submodule was never fetched — an absent optional dependency is not a failure.

## Writing a new verification

Follow the existing pattern: a plain function, no test framework, `fprintf` a banner, `assert` with messages, clean up with `onCleanup`, and add it to the list in [run_all_verifications.m](../tests/run_all_verifications.m).

Two conventions matter for keeping tests hardware-free and deterministic:

- **Construct the engine with `testing = true`.** `mabr.acq.Engine(cfg,true)` or `mabr.ui.AcqController(cfg,true)` runs the entire program with no device, feeding the outgoing frame back as the recorded frame.
- **Use `TestingFrameDelay` to pace loopback.** Without a device, loopback runs as fast as MATLAB can loop, which can starve the 20 Hz live-view timer that evaluates advance criteria. `Schedule.TestingFrameDelay` inserts a per-frame pause so timing-dependent behaviour is observable. It has no effect outside testing mode.

- **Set `Schedule.Seed` for a reproducible order.** Shuffled strategies otherwise reshuffle each time, which makes a failure hard to reproduce. `verify_online_advance` pins it so the intermixed assertions are deterministic.

- **Reuse one `AcqController` across test phases.** A second `Engine` maps the same ring-buffer files and contends for the single-process pool. `verify_online_advance` runs both its end-to-end phases through one controller, recording `Session.NumBlocks` beforehand to tell the new blocks apart.

Prefer building deterministic stimuli inline (as `verify_engine_loopback` does with a 1 kHz tone and fixed onsets) over relying on `demoStimuli`, unless you are specifically testing the demo path.

## What is not covered

The viewer windows are covered (`verify_live_plot`, `verify_progress_monitor`, `verify_trace_organizer`, `verify_trace_inspector`) by driving them the way a user does and reading back what they actually drew — but the main window itself is not, nor is the offline analysis pipeline beyond the file-contract check in `verify_data_roundtrip`. Changes in those areas need manual verification on a rig.

Real ASIO device behaviour is not covered by the suite either, by construction — every script runs hardware-free. Two of them double as **rig diagnostics** and are the way to cover it deliberately, on the machine that has the hardware:

```matlab
>> verify_timing_loopback('Testing',false)      % pulse recovery, jitter, drift, margin
>> verify_stimulus_alignment('Testing',false)   % onset latency, attribution, metrics
```
