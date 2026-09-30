# MATLAB Coder: where compiled code would speed MABR up

Status: proposal only; no Coder work has started. First drafted 2026-09-29 against `2a73634`. Revised 2026-09-30 against `0bca7b4` plus that day's live-path changes (on-demand snapshot, column hand-off, no live `corr`), which were not yet committed when this was written.

The first draft's base lacked the whole `perf/acquisition-hotspots` branch (merged in `9c27aa9`), and that branch settled several of the questions the draft asked; see [What changed since the first draft](#what-changed-since-the-first-draft). Numbers marked *measured* name their source. Everything else comes from reading the code and is marked as an estimate. Phase 0 exists to replace the estimates.

## Summary

MATLAB Coder turns MATLAB code into C and builds it as a MEX function that MATLAB calls like any other function. It pays off where the time goes into MATLAB running its own loops, allocating temporaries, or paying call overhead on small data. It does nothing for time spent in:

- functions that are already compiled (`filter`, `resample`, matrix multiply, FFT);
- things Coder cannot compile (`memmapfile`, parallel queues, graphics);
- copies made when arrays cross into a MEX.

Three places were proposed. In the order to do them now:

| | Where | What it buys | Confidence | Effort | Risk |
|---|---|---|---|---|---|
| 1 | Offline permutation statistics: `mabr.analysis.PermTest` (TFCE by default) | The step that dominates `Session.detect`: est. 10–20× on the statistic, 5–10× on a whole `detect` pass | High | Small, plus a one-time build setup | Low |
| 3 | The acquisition worker's ring write, inside `stream_block` | Headroom inside each 5.33 ms frame. *Measured* in Test Mode: the ring write is ~80% of a frame's MATLAB-side work (p99 1.5 of 1.85 ms); a native write would take microseconds (est.) | Medium: Test Mode only; rig numbers under load decide | Medium, and it is hand-written C, not Coder output | Medium |
| 2 | Onset recovery over a whole block: `find_timing_onsets` | **Deferred.** Its double copy is gone (`4dfd0a7`): a full ring now takes 0.11 s (*measured*, was 0.26 s). A kernel could save at most that per ring-length run | High | Small | Low |

Three findings matter as much as the list:

- **The live DSP step's scaling problem was real, and it was fixed without compiling.** The first draft found the step's cost growing with the run: caches grew one column at a time, the whole cache was transposed on every call, and the statistics were recomputed over every sweep on every tick. `f7518a2` replaced all three with a preallocated cache and running statistics. Late in a 9,000-sweep run a step took 39–49 ms and allocated 88–124 MB; it now takes 0.57–0.73 ms, flat (*measured*, see [the appendix](#measured)). What still grew with the run was fixed on 2026-09-30 by the same kind of change, not by compiling (see [Where Coder would not help](#where-coder-would-not-help-and-what-did)). Nothing on the live path is worth compiling now.
- **Most of the run-to-run cost was avoidable work, not slow arithmetic.** The perf branch took out a device reopened on every run (0.25–0.5 s a run), a `designfilt` repeated twice per block (~280 ms each), the next run waiting on block assembly, an n×n correlation matrix (435 MB at 7,374 sweeps), and a live view that redrew everything every frame (290 → 43 ms at 54 conditions). Compiling any of those would have bought little. That is the case for keeping Phase 0: measure, then compile only what measurement leaves.
- **Putting the audio device inside a MEX fixes it to one rig configuration.** `audioPlayerRecorder` supports code generation. But Coder requires a System object's nontunable properties to be compile-time constants, and those include `Device`, `SampleRate` and the channel mappings. MABR lets the operator change all of them at any time. So the portable version of candidate 3 leaves the device call in MATLAB.

## What changed since the first draft

| Change | Commit | What it settled for this plan |
|---|---|---|
| Live DSP made incremental | `f7518a2` | The live-step finding: fixed without compiling |
| Live snapshot built on demand; sweeps handed over as columns; `corr` not evaluated on a condition still acquiring | uncommitted, 2026-09-30 | The rest of what grew with a run: ~20 ms/s of GUI time, 22–29 ms per metrics cycle, 3.9 s per metrics cycle |
| `find_timing_onsets` compares the single samples | `4dfd0a7` | Candidate 2's double copy: gone. A full ring's onsets 0.26 → 0.11 s |
| Re-arm rule and look-back in `find_timing_onsets` | `db04bde` | A candidate 2 kernel must now reproduce two more rules exactly |
| Frame loop timed; ring prefaulted | `7afd209` | Phase 0 item 1's instrumentation exists |
| First-call costs paid before a fresh worker streams | `3f7d8fd` | The fresh-worker spikes (ring writes up to 13.3 ms) were setup, not steady-state cost |
| Device kept open and clocked between runs; fresh devices warmed up | `f3ae602`, `469a15e` | 0.25–0.5 s of driver start-up per run: gone, and never compute |
| Next run begins before block assembly | `dae07e9` | Only `Pipeline.finalize` now stands between runs |
| `FilterPolicy.design` memoized per process | `98d18bf` | ~280 ms twice per block: 0.14 ms |
| `mean_pairwise_corr` tiled; online metrics memoized | `f91368d`, `4f2f242` | The `corr` row's memory, and re-evaluating finished conditions |
| Live view writes only what changed; paced from frame start | `b685060`, `e7bed6c` | The GUI's frame cost |

## Where MABR spends time at run time

| Process | What it must keep up with | Code |
|---|---|---|
| Acquisition worker (`high priority`) | A hard deadline: one 1024-sample frame every 5.33 ms at 192 kHz (10.7 ms at 96 kHz). A late frame is an underrun, and every presentation after it plays late. Between runs it keeps the device clocked with frames of silence | [worker_loop.m:370-445](../+mabr/+acq/worker_loop.m#L370-L445) |
| DSP worker (`below normal`) | The 50 ms live cycle (~0.6 ms of work, *measured*). Also the DSP half of finalization, which the next run waits for | [Pipeline.m:214](../+mabr/+compute/Pipeline.m#L214) (`step`), [Pipeline.m:327](../+mabr/+compute/Pipeline.m#L327) (`finalize`) |
| GUI | The live view, polled every 10 ms and drawn once 50 ms have passed since the last frame began, and the 2 Hz aux tick. With no DSP worker, the GUI runs `Pipeline.step` itself | [AcqController.m:1142-1247](../+mabr/+ui/AcqController.m#L1142-L1247) |
| Metrics worker (`idle`) | Time-boxed metric passes, plus its own copy of the pipeline ([compute_loop.m:240](../+mabr/+compute/compute_loop.m#L240)). The run in progress becomes live conditions only while a window has a job there | [evaluateJobs.m](../+mabr/+compute/evaluateJobs.m) |
| Offline analysis | Throughput per session and per study | [Session.m](../+mabr/+analysis/Session.m) |

Each pool worker gets one computational thread, which is the default for the `Processes` profile. So any kernel that runs on a worker should stay single-threaded (see [Build, distribution and operation](#build-distribution-and-operation)).

## 1. Offline permutation statistics — `mabr.analysis.PermTest`

Unchanged by the perf work, and still the strongest candidate.

**Where.** `Session.detect` defaults to `Method="tfce"` with 1000 permutations ([Session.m:467-468](../+mabr/+analysis/Session.m#L467-L468)) and runs one test per condition. `PermTest.run` builds the null distribution 512 permutations at a time ([PermTest.m:117-139](../+mabr/+analysis/PermTest.m#L117-L139)). Each block does two things:

- a matrix multiply for the permuted sums, which runs in BLAS and stays as it is;
- the statistic of every row: `tfceOneSided` ([PermTest.m:319-357](../+mabr/+analysis/PermTest.m#L319-L357)) or `maxPositiveMass` ([PermTest.m:285-317](../+mabr/+analysis/PermTest.m#L285-L317)).

**Why it is slow.** TFCE steps through thresholds `h = dh:dh:max`. With ~1000 sweeps, a null t-map peaks around 4–5. At the default `dh = 0.1` that is ~45 steps per sign, or 90 per block. Each step makes several passes over the whole `[512 x ~121]` block (the `[0 10]` ms response window at 12 kHz):

- a mask, then a padded copy of it;
- a `diff`, which promotes the logical mask to double;
- two `find` calls;
- two `sortrows` calls over every run in the block;
- `sub2ind` and a fresh `zeros`;
- a `cumsum`, and an add into the result.

Sorting and allocating inside a loop is where interpreted MATLAB loses most to C. Cluster mass follows the same pattern but only once per sign per block, so it is already cheap.

Estimate: TFCE's statistic costs ~0.2–0.4 s per condition at 1000 permutations, several times the multiply that feeds it. That comes to tens of seconds per 80-condition session, and minutes at 10,000 permutations.

**The kernel.** One `%#codegen` function that returns what the null uses, which is the per-row maximum: `nullMax = perm_null_max(T,method,thr,E,H,dh,minSz)`, where `T` is the `[nRows x nSamples]` block. Behind an output flag, the same loop returns the full per-sample map for the one observed row.

Per row, the kernel makes one pass per threshold over a row that fits in cache. It finds runs by scanning, so there is no sorting and no allocation. Each row stops at its own maximum. This is the naive reference that `verify_analysis` already checks the vectorized code against ([verify_analysis.m:461-493](../tests/verify_analysis.m#L461-L493)), made compilable.

These parts stay in MATLAB:

- The `RandStream` draws of the sign flips, so that `Seed` reproduces today's permutations. `RandStream` is not supported by code generation, and a compiled `rand` would be a different generator anyway.
- `X*flips`, `tFromSums`, `fwerP` and `clusterTable`.

**Threads.** Rows are independent, so the row loop can run on OpenMP threads inside the MEX. That parallelizes offline analysis without the Parallel Computing Toolbox, which `detect(UseParallel=true)` needs today. Three cautions:

- MathWorks' Coder `parfor` page says "to use `parfor` in your MATLAB code, you require a Parallel Computing Toolbox license", and the analysis classes promise not to need it. Use a plain `for` and request threads with `coder.loop.parallelize` under `EnableAutoParallelization`. That avoids the licensing question.
- Cap the thread count at the caller's. Inside a pool worker the cap is 1, so `UseParallel=true` does not oversubscribe the machine.
- A compiler without OpenMP builds a single-threaded loop and does not say so. The build script has to check.

**Expected gain (estimate).** 10–20× on the statistic, single-threaded. After that, the flip generation and the multiply dominate, so a whole `detect` pass gets ~5–10× faster, and more with threads. That makes 10,000 permutations practical where 1000 is the default today. At 1000 permutations, the smallest p-value that can be reported is 1/1001.

**Exactness.** The vectorized code already agrees with the naive reference to rounding, not to the bit: Part E asserts 1e-9 for TFCE. The compiled loop will be the same, because its `pow` and colon come from generated code rather than from MATLAB. p-values are counts of null values ≥ the observed one, so two implementations can only disagree on a tie that falls within one ulp. A fixed `Seed` still reproduces each implementation exactly.

Record which implementation ran (`result.engine = "mex"` or `"matlab"`). Then a threshold that moves in the 15th digit between machines can be explained.

**Risk.** Low. The kernel is offline, pure arithmetic, calls no toolbox functions and has no cross-process parity to keep. Today's code stays as the fallback. `abr_analysis/permtest` is left alone, like the rest of that pipeline.

## 2. Onset recovery over a whole block — `find_timing_onsets` (deferred)

**What changed.** The first draft's case was the double copy: the vectorized code converted a whole block's single-precision timing channel to double before comparing, ~537 MB plus ~270 MB of logical temporaries for a run that fills the ring. `4dfd0a7` removed it. With a positive threshold the function now compares the single samples against the smallest single at or above the threshold, which is the double comparison value for value ([find_timing_onsets.m:44-56](../+mabr/+metrics/find_timing_onsets.m#L44-L56)). A full ring takes 0.11 s instead of 0.26 s (*measured*, `4dfd0a7`). What remains is a handful of one-byte logical temporaries over the block: the `above` mask, its two shifted copies, and the re-arm rule's falls. That is ~0.3 GB for a full ring (estimate).

**Where it sits.** `Pipeline.finalize` runs it over the whole retained block ([Pipeline.m:388](../+mabr/+compute/Pipeline.m#L388)), on the DSP worker or, if there is none, in the GUI. The next run still waits for that DSP half of finalization, but no longer for block assembly: `conclude_run` credits the run and begins the next one before building this one's Blocks ([AcqController.m:963](../+mabr/+ui/AcqController.m#L963), `dae07e9`). The same function also runs on each tick's slice in `extract_sweeps`, in `verifyTimingLoop`, and in `CalibrationAdapter`.

**Why it is deferred.** A one-pass kernel would take most of the remaining 0.11 s and the ~0.3 GB of temporaries off a ring-length run (estimate), and less off the shorter runs a session is mostly made of. That is not worth a build dependency on its own. Revisit it if Phase 0 item 3 shows the onsets are a real share of `Pipeline.finalize`, or build it as a cheap second kernel once Phase 1's infrastructure exists.

**If it is built, it must reproduce all of these exactly**, because the outputs are integers and every caller must get the same onsets:

- **The threshold rule on singles.** Compare against `single(threshold)`, stepped up by one `eps` when it rounded down (0.7 does); see [find_timing_onsets.m:54-56](../+mabr/+metrics/find_timing_onsets.m#L54-L56).
- **The double path's negatives and NaN.** For a threshold of 0 or below, or double input, `d(d<0) = 0` leaves NaN as NaN, and `NaN >= thr` is false. A C `fmax(t,0)` turns NaN into 0 and would disagree. Write `v = (t < 0) ? 0 : t`.
- **The re-arm rule** (`db04bde`). A rising crossing is a new onset only if the channel was below threshold for `rearmSamples` before it, measured from the last fall preceding it; a crossing with no fall before it passes ([find_timing_onsets.m:83-94](../+mabr/+metrics/find_timing_onsets.m#L83-L94)).
- **The look-back `context`.** The first `context` samples settle the re-arm rule and whether the vector starts inside a pulse, and no onset inside them is returned.
- **The shadow merge**, keeping the earliest of each cluster.

Put the dispatch inside `find_timing_onsets` itself, so the worker-versus-in-process parity `verify_compute_worker` checks cannot break. Assert `isequal` against the MATLAB function over every existing fixture (`verify_live_pipeline` Part F exercises the re-arm rule and look-back), plus a randomized property test: negative values and NaN, a threshold of 0 or below, a vector that starts above threshold, runs shorter than the shadow, dropouts shorter and longer than the re-arm, and slices cut inside a pulse.

**Deliberately left alone.** `resample(double(rawSignal),1,df)` ([Pipeline.m:412](../+mabr/+compute/Pipeline.m#L412)) makes an 8-byte copy of the block. But the work inside `resample` is already a compiled built-in, and changing its arithmetic would change the samples written into every `.abr`.

## 3. The acquisition frame loop — `stream_block`

**Where.** Each frame ([worker_loop.m:370-445](../+mabr/+acq/worker_loop.m#L370-L445)) runs:

- `poll(cmdQueue,0)`;
- `src.range(i,hi)`, a handle method whose `while` loop reads object properties ([PlayPlan.m:121-168](../+mabr/+stim/PlayPlan.m#L121-L168));
- `apr(frame)`, the device call, where the loop waits;
- `note_xruns`, which only accumulates (the report is logged after the block);
- `rb.writeFrame` ([RingBuffer.m:104-129](../+mabr/+acq/RingBuffer.m#L104-L129)), which makes three indexed `memmapfile` assignments per frame (five on a wrap). Each first runs `memmapfile`'s own MATLAB-code `subsasgn`, which parses the arguments and bounds-checks against the `Data` array (`hParseNumericDataSubsasgn` in R2025a's `memmapfile.m`). The header update goes through the struct-format path.

**What the loop already does** (none of it existed at the first draft's base):

- **Times itself** (`7afd209`). Each frame's poll, render, device call, ring write and whole iteration are recorded; `summarize_frames` ([worker_loop.m:480](../+mabr/+acq/worker_loop.m#L480)) reports p50/p99/max per stage and the eight frames with the most work, with their ring positions. The summary rides the `'streamed'` message (`Engine.LastStream.timing`), and `log_block_report` ([worker_loop.m:512](../+mabr/+acq/worker_loop.m#L512)) logs it once per block — at level 1 when a frame's work came within half a frame of the budget or the device reported an xrun.
- **Prefaults the ring** at worker start (~0.13 s) and over each run's range at Prep ([worker_loop.m:120](../+mabr/+acq/worker_loop.m#L120), [:187](../+mabr/+acq/worker_loop.m#L187)). Long rig runs had shown one-frame underruns at whole-MiB spacings of ring written, which points at file-backed pages being faulted in by the frame loop itself. Whether prefaulting ended them is not yet confirmed on the rig.
- **Pays first-call costs before streaming** (`3f7d8fd`). `prime_ring` and `prime_render` ([worker_loop.m:652-676](../+mabr/+acq/worker_loop.m#L652-L676)) take MATLAB's first-call setup off the stream. On the Focusrite rig a fresh worker's first block used to underrun: ring writes of 11–13 ms and 7–9 ms against a 5.3 ms frame, and a first render of ~3 ms. They now peak at 1.3 ms and 0.7–0.9 ms, with no underrun (*measured*, `3f7d8fd`).
- **Keeps the device clocked between runs** (`f3ae602`), and warms a fresh one on 0.25 s of unrecorded silence (`469a15e`), so no run pays the driver's start-up.

**Where the time goes now** (*measured*, Test Mode on the development machine, one worker, two runs of 3,785 frames):

| Stage | p50 (ms) | p99 (ms) | max (ms) |
|---|---|---|---|
| poll | 0.06 | 0.24–0.25 | 0.46–0.50 |
| render (`range`) | 0.02 | 0.09–0.10 | 0.38–2.58 |
| ring write | 0.62–0.64 | 1.50–1.51 | 2.23–2.69 |
| work (all but the device call) | 0.76–0.79 | 1.84–1.89 | 2.68–3.21 |

The budget is 5.33 ms. Two conclusions follow:

- **The gate below is already met in Test Mode**: the work's p99 is ~35% of the budget. Test Mode has no device call and no GUI or compute-worker load, so rig numbers under ordinary load are still what decides.
- **The cost is the ring write, not the synthesis.** Rendering a frame takes 0.02 ms at p50, so compiling `range` buys nothing. The ring write is ~80% of the work. Writing 8 KB is a microsecond of memory traffic, so nearly all of it is `memmapfile`'s MATLAB-side `subsasgn`, three times a frame (estimate).

**What can move, and what cannot.**

- **Cannot move:** the `PollableDataQueue` poll (parallel queues are not supported by code generation), `memmapfile` (also unsupported), and logging. These stay in MATLAB regardless, so Pause, Stop and Kill are handled exactly as they are today.
- **Can move, as hand-written C:** the ring write. It would map the same `ring_*.dat` files with `CreateFileMapping`/`MapViewOfFile` and write samples, then the header. On Windows, views of one local file are coherent across processes, so the `memmapfile` readers in the GUI and the DSP worker do not change. Because `memmapfile` is not supported by code generation, this is C whether it sits behind `coder.ceval` or in a plain `mex` file. Candidate 3 therefore does not need Coder unless candidate 1 has already brought a Coder build.
- **Not worth moving:** the synthesis, at 0.02 ms a frame.
- **Can move, with a catch:** the device. `audioPlayerRecorder` supports C/C++ code generation. But its `Device`, `SampleRate`, `PlayerChannelMapping`, `RecorderChannelMapping` and `BitDepth` properties are nontunable, and Coder requires nontunable values to be constants. A device inside the MEX is therefore a MEX built for one rig configuration.

That gives three stages, each only if the one before it leaves the gate unmet:

- **3-pre — fewer `memmapfile` calls, in MATLAB.** Time each of `writeFrame`'s three assignments. Then try writing the header every few frames instead of every frame, since readers poll it at 50 ms and finalization reads it only after the block. That is est. up to a third off the ring write. No native code, no build.
- **3a — a native ring writer.** One call per frame writes the recorded frame into the ring. The poll, the render and the device call stay in MATLAB. Keep `writeFrame` as the fallback.
- **3b — per rig, optional.** The device moves inside a Coder MEX, built for the committed audio settings.
  - Build it when the operator presses Commit in Audio Settings.
  - Cache it under a key made of the release, device, rate, channel mappings and bit depth.
  - Whenever the key does not match, run the 3a path.

  3b needs MATLAB Coder and a compiler on the rig. Do it only if the rig's lower device-call percentiles show MATLAB-side dispatch dominating what is left.

**Constraints a native ring writer has to respect.**

- **One frame per call.** Pause, Stop and Kill are required to take effect within one frame ([worker_loop.m:18-19](../+mabr/+acq/worker_loop.m#L18-L19)). So the loop stays in MATLAB. A call costs microseconds; a frame lasts 5333 µs.
- **Test Mode stays a test of the rig's path.** Test Mode writes the rendered frame into the ring, so it exercises the same writer. The dither's `randn` stays in MATLAB, so the random generator does not change.
- **Samples unchanged.** The writer copies singles and computes nothing, so what it writes is what it was given. `verify_stimulus_alignment` already checks, in Test Mode, that the samples at each onset are the stimulus assigned there, to within the ~1e-6 dither.
- **Ring header written last.** Write the samples before `WriteHead`. Make the header store `volatile` and put it after a compiler barrier. x86 keeps stores in order, so the readers need nothing new.
- **Explicit lifetime.** The mapped views persist across calls. Init and release entry points tie them to worker start, `Cmd.Release` and Kill. `clear mex` in the client cannot reach a pool worker.
- **Page faults do not go away in C.** A native writer touches the same file-backed pages, so it keeps `prefault`, which already runs in MATLAB.
- **Timing stays visible.** `summarize_frames` must still see the ring write as its own stage, so time the call around the MEX.
- **No safety net.** Hand-written C has no MEX integrity checks. Keep it tiny and bounds-check every index against the mapped length.

**Expected gain (estimate).** The ring write falls from p50 0.6 ms and p99 1.5 ms to microseconds, taking a frame's MATLAB-side work from p99 ~1.9 ms to ~0.4 ms. That is headroom, not throughput:

- fewer underruns under the load of an analysis window, the progress monitor and two compute workers;
- room for a smaller ASIO buffer;
- room for a higher rate (at 384 kHz the frame budget halves to 2.67 ms, and today's Test Mode p99 would be ~70% of it).

**Gate.** Go ahead if the per-frame work outside the device call has a p99 above ~10–15% of the frame budget on the rig under ordinary load, or if frames over half the budget occur there. The per-block "Frame timing" log line now carries exactly these numbers. Test Mode already passes the gate, but only the rig decides.

**Risk.** 3-pre is low. 3a is medium: it adds a native write path to the one real-time loop, although the bit-exact tests guard it. 3b is high: it adds a per-rig build step and a second device lifecycle.

**Considered and rejected:** a standalone acquisition executable built by Coder. It would bring back the two-process design MABR retired, and outside MATLAB there would be no parallel queues to talk to it through.

## Where Coder would not help, and what did

| Area | Where the time went | Why Coder would not fix it | What did, or would |
|---|---|---|---|
| Live DSP step (`Pipeline.step`, on the DSP worker, in the GUI with no worker, and the metrics worker's own copy) | Work that grew with the run: caches appended a column at a time, the whole cache transposed every call, mean, SD and the correlation recomputed over every sweep. *Measured* at 9,000 sweeps: 39–49 ms and 88–124 MB per step | The cost was copying, and a MEX called through the same interface marshals the same arrays | **Done** (`f7518a2`): a cache preallocated for the planned run and running statistics. Now 0.57–0.73 ms per step, flat. What is left is `filtfilt` on the new sweeps (a built-in) and the ring reads |
| What else grew with the run: the GUI's analysis snapshot, the metrics worker's live hop, live `corr` | The aux tick copied and transposed the run twice a second whether or not a window read it (~20 ms/s at 9,000 sweeps). The metrics worker transposed rows back to columns every cycle (22–29 ms). Live `corr` compared every pair of a live condition's sweeps every cycle (3.9 s at 9,000) | Copies and an O(n²) algorithm | **Done** (2026-09-30): the snapshot is built only when a window pulls it, at most once per `AuxPeriod`; the sweeps go over as columns (hop 5–15 ms, and none with no job); `corr` waits for a condition to finish |
| `Block.computeMetrics` and finished conditions' metrics | `mean_pairwise_corr` built the full n×n `corrcoef` (435 MB at 7,374 sweeps); every pass re-evaluated every finished condition | The n²m arithmetic already runs in BLAS; the memory and repetition came from the algorithm | **Done**: tiled, ~32 MB at a time (7,374 sweeps in 0.6 s, `f91368d`); finished conditions memoized (`4f2f242`) |
| Between runs | A device reopened every run (0.25–0.5 s); `designfilt` twice per block (~280 ms each; ~20 s at the end of a 54-condition run); the next run waiting on block assembly | None of it was arithmetic | **Done**: device kept clocked (`f3ae602`), design memoized (`98d18bf`), next run begun first (`dae07e9`) |
| Compiled built-ins | `resample` at finalization; `filtfilt` over long traces (`Recording.designFilters`, and the ~200-tap FIR in `mabr.analysis.Filter` used by `Session.segment`); the multiply in PermTest | MathWorks: "Avoid generating MEX functions if computationally intensive, built-in MATLAB functions dominate the run time" | For the long offline FIR, FFT-based zero-phase filtering, if Phase 0 shows it matters |
| `memmapfile` readers, parallel queues, `parfeval`, the publish buffers | MATLAB-side access paths | Not supported by code generation | Nothing needed on the readers' side. The writer is candidate 3 |
| GUI (`LivePlot`, `ProgressMonitor`, `MetricPlot`, `TraceOrganizer`) | Graphics | Graphics cannot be compiled | **Done**: the live view writes only what changed (54 conditions 290 → 43 ms a frame, a frame with nothing new 280 → 0.1 ms, `b685060`), is paced from frame start (`e7bed6c`), and the end-of-run viewers work incrementally (`6414f84`) |
| User-supplied functions (custom metrics, strategies, advance criteria) | Whatever the user wrote | Function handles resolved at run time cannot be compiled ahead of time, and the metrics worker exists to contain them | — |
| `Schedule` build/render, threshold fitting, stimgen synthesis | Once per run, series or bank, on small data; stimgen is a submodule | Too little time to be worth compiling | — |

## Plan

### Phase 0: measure first (no Coder needed)

1. **Frame timing on the acquisition worker.** The instrumentation exists (`7afd209`), and Test Mode numbers are above. Still to do: collect the per-block "Frame timing" and xrun lines from ordinary rig sessions:
   - the rig at 192 kHz;
   - compute workers off, then on;
   - with an analysis window and the progress monitor open;
   - long runs, to check whether prefaulting ended the whole-MiB underruns.

   For 3-pre, also time `writeFrame`'s three assignments separately.
2. **Live step against run length.** Done; see [the appendix](#measured). No timing test guards it, since timing assertions flake on a loaded machine. The property is guarded instead by `verify_live_pipeline` (bit-exact however the run is sliced; stepping makes no copies) and `verify_stimulus_alignment` Part H (no snapshot copy while nothing pulls).
3. **Finalization, part by part,** on a Test Mode run that fills the ring. Time `readBlock`, the onsets, `resample`, and the per-part filtering and judging: that is `Pipeline.finalize`, the part the next run waits for. Time `assemble_blocks` (`computeMetrics`, `writeABR`) separately, since it now overlaps the next run. The onsets are known: 0.11 s.
4. **Offline.** Profile `Session.detect` on a real session with TFCE, at 1000 and 10,000 permutations. Separate the multiply from the statistic.
5. Fill in [the table of what is still to measure](#still-to-measure) and decide each gate from it.

### Phase 1: build infrastructure, then the PermTest kernel

1. **Build script** (e.g. `tools/build_mex.m`). It compiles every kernel for the running release (`codegen`, or `mex` for hand-written C), and:
   - puts build folders outside the repo, because `MABR.m` adds every subfolder except `.git` to the path ([MABR.m:31-33](../MABR.m#L31-L33)), so an in-tree `codegen/` would end up on it;
   - reports the release and whether OpenMP was used;
   - writes a stamp for the dispatcher to check.
2. **Dispatcher.** It uses a kernel only when the kernel's MEX exists and was built for the running release; otherwise it runs today's code.
   - Add a developer-only switch for A/B comparisons.
   - The switch reaches pool workers through `Cmd.Configure` or the Prep spec. It is never a pref read on a worker; that is CLAUDE.md's rule, and it avoids the prefs race CLAUDE.md describes.
   - If the switch is ever promoted to a Settings item, it persists in both places, per the settings convention.
3. **The PermTest kernel** as described above, including `result.engine`.
4. **Tests.**
   - Extend `verify_analysis` Part E to compare kernel, vectorized and naive results. Cover both statistics, `minSz` 1 and 3, several `dh`, and rows entirely below threshold. Require identical significance decisions on the seeded detection data.
   - Add `verify_codegen_kernels.m`, which skips and passes when no MEX is built (the convention for an optional piece). `mabr.ui.TestRunner` will discover it.
   - List it in `run_all_verifications` before `verify_shutdown_pool`, which must stay last.
5. **Docs.** Update [docs/Analysis-Classes.md](../docs/Analysis-Classes.md), [docs/Installation.md](../docs/Installation.md) (building the kernels) and the offline section of CLAUDE.md.

**Exit:** at least 10× on the statistic in the Phase 0 session, and identical significance decisions on the verification data and on that session.

### Phase 2: the onset kernel — deferred

Only if Phase 0 item 3 shows the onsets matter, or as a cheap second kernel once Phase 1 exists.

1. Write the kernel to the rules in [candidate 2](#2-onset-recovery-over-a-whole-block--find_timing_onsets-deferred), with the dispatch inside `find_timing_onsets`.
2. Run the `isequal` property test, then the unchanged suite: `verify_live_pipeline` (Part F: the re-arm rule and look-back), `verify_compute_worker` (parity), `verify_stimulus_alignment`, `verify_timing_loopback`, `verify_play_plan`, `verify_isi_jitter` and `verify_timing_selftest`.

**Exit:** identical onsets everywhere, and finalization shorter by the onsets' measured share.

### Phase 3: the ring write, only if the rig says so

1. Apply the gate to the rig numbers from Phase 0 item 1.
2. **3-pre.** Fewer `memmapfile` calls per frame, in MATLAB. Re-measure; stop if the gate is no longer met.
3. **3a.** The native ring writer, with init and release entry points and `writeFrame` kept as the fallback.
4. **Tests.**
   - `verify_engine_loopback`, `verify_device_reuse`, `verify_stimulus_alignment` (bit-exact in Test Mode), `verify_test_mode`, `verify_stimulation_only`, `verify_timing_selftest` and `verify_compute_worker`.
   - On the rig: `verify_timing_loopback('Testing',false)` and `verify_stimulus_alignment('Testing',false)`.
5. **Exit:** a lower frame-time p99, no change in any bit-exact test, and no new underruns.
6. **3b** only if the rig's device-call percentiles show MATLAB-side dispatch dominating what is left.

## Build, distribution and operation

- **Licences.** MATLAB Coder and a C compiler are needed only where the kernels are built, not where they run. A hand-written C MEX needs only the compiler.
- **Releases.** Build per release; R2024b and R2025a are both installed here. MathWorks: "For best results, your version of MATLAB must be the same version that was used to create the MEX file." The dispatcher's stamp check means a mismatch falls back to today's code instead of misbehaving.
- **Binaries.** Keep them off master. Every rebuild would add another binary to the history, and a clone without them works anyway, on the fallback. Ship the binaries with tagged releases or build them on the rig. Add `*.mexw64` and the build folder to `.gitignore`.
- **Pool workers.** A worker sees the client's path as it was when the pool started. `worker_loop` also adds the repo root, which covers anything under `+mabr`. Windows locks a loaded `.mexw64`, so rebuild with no pool up (`mabr.shutdownPool`). MABR's worker loops never return, so a `parfevalOnAll(@clear,...)` would just queue behind them.
- **Threads.** Kernels that run on workers are built single-threaded. Only the offline kernel gets OpenMP.
- **Crash isolation.** Keep MEX integrity checks on in shipped Coder kernels (they are the default) unless a measured gain argues otherwise. They turn an out-of-range index into a MATLAB error instead of a dead worker. Hand-written C has no such safety net, so limit it to the ring writer.
- **One source per kernel.** Each Coder kernel is a single `%#codegen` MATLAB function, and the equivalence tests also run it interpreted. Today's code stays as the reference fallback. The two can differ only in rounding, never in logic, and the tests bound the rounding.

## Open questions for the spikes

- Does `codegen` in R2024b/R2025a accept entry points inside `+mabr`, either in the package or in a `private` folder? If not, kernel sources go in an un-namespaced folder with `mabr_`-prefixed names, called from the package code. A kernel outside `+mabr` then depends on the pool inheriting the client's path.
- Does the chosen compiler (MSVC or MinGW-w64) give OpenMP to Coder MEX builds on this machine? How is the thread count capped at run time?
- How much of `apr(frame)` is MATLAB-side dispatch rather than waiting on the device? The lower percentiles of the rig's device-call stage give a bound, and 3b depends on the answer.
- Did prefaulting the ring end the whole-MiB underruns on long rig runs? If it did, the rig may already sit under the gate, and 3a may not be needed.
- Which of `writeFrame`'s three assignments costs what? The header's struct-format path may be the expensive one, and 3-pre depends on it.

## Appendix: baseline

### Measured

| Measurement | Before | Now | Source |
|---|---|---|---|
| Live `Pipeline.step`, DSP worker (1 thread), at 1k / 5k / 9k sweeps (ms, median) | 4.2 / 26.4 / 46.7 blocked; 4.6 / 26.0 / 49.3 at 54 conditions | 1.0 / 0.59 / 0.57; 1.2 / 0.67 / 0.61 | Replay, 2026-09-30 [^replay] |
| Live `Pipeline.step`, GUI with no worker (6 threads), same points | 3.9 / 21.6 / 39.1; 4.3 / 26.1 / 49.0 | 0.78 / 0.68 / 0.63; 1.1 / 0.76 / 0.73 | Replay, 2026-09-30 |
| Allocated per step, late in a 9,000-sweep run | 88–124 MB | below the profiler's resolution | Replay, profiler `-memory` |
| GUI analysis snapshot at 9,000 sweeps | ~10 ms, twice a second, always | 5.3–5.5 ms, only when a window pulls it (at most once per `AuxPeriod`) | Replay, 2026-09-30 |
| Metrics worker, run → live conditions per cycle at 9,000 sweeps (1 / 54 conditions) | 21.9 / 29.1 ms | 5.2 / 15.1 ms; none with no job | Replay, 2026-09-30 |
| Live `corr` per metrics cycle, one condition at 1k / 5k / 9k sweeps | 58 ms / 1.2 s / 3.9 s | not evaluated | Replay, 2026-09-30 |
| Frame, non-device work, Test Mode: p50 / p99 / max (ms) | — | 0.76–0.79 / 1.84–1.89 / 2.68–3.21, of which ring write 0.62–0.64 / 1.50–1.51 / 2.23–2.69 | `Engine.LastStream.timing`, 2026-09-30 [^frames] |
| Frame, fresh worker's first block on the rig: ring write max; first render | 13.3 ms (2 underruns); ~3 ms | 1.3 ms (no underrun); 0.7–0.9 ms | `3f7d8fd` |
| Onsets over a full ring (`find_timing_onsets`) | 0.26 s | 0.11 s | `4dfd0a7` |
| `mean_pairwise_corr`, 7,374 sweeps | 435 MB matrix | 0.6 s, ~32 MB tiles | `f91368d` |
| `FilterPolicy.design`, repeat of a chain | ~280 ms | 0.14 ms | `98d18bf` |
| Live view frame, 54 conditions (grid / stacked); blocked run | ~290 / ~325 ms; ~22 ms | ~43 / ~29 ms; ~7 ms | `b685060` |

[^replay]: A 9,600-presentation run at a 37 ms ISI, replayed from memory through each version of `Pipeline.step` in 50 ms slices (the live cycle); medians over the ~149 steps within 100 sweeps of each point. Blocked (1 condition) and intermixed (54 conditions). "Before" is `2a73634`'s code. Development machine (Core Ultra 7 155H), R2025a. The scripts are not in the repo.
[^frames]: Test Mode, one acquisition worker, no compute workers, no GUI: two interleaved runs of 1,000 presentations (3,785 frames each), 20 ms ISI. Development machine, R2025a.

### Still to measure

| Measurement | Test Mode | Rig (192 kHz) | Notes |
|---|---|---|---|
| Frame, non-device work under ordinary load: p50 / p99 / max (ms) | see above | | budget 5.33 ms; workers on, analysis window and progress monitor open |
| Frame, device call: p50 / p99 / max (ms) | — | | the lower percentiles bound MATLAB-side dispatch |
| `writeFrame`'s three assignments, each (ms) | | | decides 3-pre |
| Underruns / overruns per 10 min, and their offsets into the MiB | — | | workers off / on; tests the prefault |
| `Pipeline.finalize` on a ring-length run: read / onsets / resample / parts (s) | | | onsets known: 0.11 s |
| `assemble_blocks` on the same run (s), and peak memory during finalization (GB) | | | overlaps the next run since `dae07e9` |
| `detect` per condition, TFCE, 1k / 10k permutations: multiply / statistic (s) | | | offline |

## Sources

- [audioPlayerRecorder — Extended Capabilities](https://www.mathworks.com/help/audio/ref/audioplayerrecorder-system-object.html)
- [Audio I/O: Buffering, Latency, and Throughput](https://www.mathworks.com/help/audio/gs/audio-io-buffering-latency-and-throughput.html)
- [System Objects in MATLAB Code Generation](https://www.mathworks.com/help/coder/ug/use-system-objects-in-matlab-code-generation.html)
- [Best Practices for Using MEX Functions to Accelerate MATLAB Algorithms](https://www.mathworks.com/help/coder/ug/best-practices-for-using-mex-functions-to-accelerate-matlab-algorithms.html)
- [parfor (MATLAB Coder)](https://www.mathworks.com/help/coder/ref/parfor.html)
- [Automatic Parallelization of for-Loops in the Generated Code](https://www.mathworks.com/help/coder/ug/automatically-parallelize-for-loops.html)
- [MEX Version Compatibility](https://www.mathworks.com/help/matlab/matlab_external/version-compatibility.html)
