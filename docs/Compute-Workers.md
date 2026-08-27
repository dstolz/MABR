# Compute Workers

Reference for `+mabr/+compute/` — the signal processing, and the two optional worker processes that run it so the GUI process does not have to. This page is for developers; users need only the one setting, **Settings ▸ Background compute workers**, which is on by default.

## Why

Every number MABR shows while a schedule runs is computed from recorded samples: sweeps are extracted from the ring buffer, filtered, judged for artifact, correlated, and averaged per condition twenty times a second, and every open analysis window re-evaluates its metric over every condition on its own clock. Done in the GUI process, all of that competes with drawing on one thread — with a progress window and an analysis window open the live trace had fallen from ~13 Hz to ~1 Hz — and at the end of every run the same process resampled and filtered the whole block before the next one could start.

The workers move all of it out. The GUI process **polls and draws**; the arithmetic runs elsewhere, and the two processes agree because they run the same code.

## Processes and channels

```
   GUI process                     DSP worker                   metrics worker
 ┌─────────────────────┐        ┌──────────────────────┐     ┌──────────────────────┐
 │ ComputeEngine       │  cmd   │ compute_loop('dsp')  │     │ compute_loop(        │
 │  send ──────────────┼───────►│  poll(cmdQueue)      │     │        'metrics')    │
 │  ◄── afterEach ─────┼────────┤  state / finalized   │     │  state / roster      │
 │                     │        │                      │     │                      │
 │ LiveBuffer   (RO) ◄─┼────────┤ LiveBuffer   (RW)    │     │                      │
 │ MetricBuffer (RO) ◄─┼────────┼──────────────────────┼─────┤ MetricBuffer (RW)    │
 │ RequestBuffer(RW) ──┼───────►│ RequestBuffer (RO)   │ ───►│ RequestBuffer (RO)   │
 │                     │        │  Pipeline @ 20 Hz    │     │  Pipeline @ 1 Hz     │
 └─────────────────────┘        └──────────┬───────────┘     └──────────┬───────────┘
                                           │ read-only                  │ read-only
                          ring_signal.dat / ring_timing.dat  (written by the acquisition worker)
```

Each worker is one `parfeval` on the same parallel pool as the acquisition worker, running [mabr.compute.compute_loop](../+mabr/+compute/compute_loop.m) with a `role`. The protocol is the acquisition engine's: a handshake that hands back a `PollableDataQueue` for commands, state and error reports on a `DataQueue`, and bulk data through memory-mapped files. **Neither worker talks to the other.** Both read the ring buffer and the request file; both are configured by the same `Configure`, so what they extract and how they judge it agree by construction.

Three files back the publish buffers, beside the ring files in `.runtime_data/`: `compute_live.dat` (DSP worker → GUI), `compute_metrics.dat` (metrics worker → GUI), `compute_requests.dat` (GUI → both).

## The pipeline

[mabr.compute.Pipeline](../+mabr/+compute/Pipeline.m) is the one implementation of everything computed from samples:

```matlab
p = mabr.compute.Pipeline(cfg);
p.configure(window,filters,artifacts);   % designs the chain at the ADC rate
p.beginRun(runInfo);                     % what the onsets belong to
stats = p.step(ringBuffer);              % one cycle: [] until a sweep is complete
S     = p.sweeps();                      % the filtered sweeps behind it
F     = p.finalize(ringBuffer,seq);      % the DSP half of finalizing a run
p.endRun();
```

`step` extracts newly completed sweeps (`mabr.metrics.extract_sweeps`), filters them, judges them (`mabr.metrics.detect_artifacts`), correlates the clean ones (`mabr.metrics.partition_corr`), and returns **sufficient statistics**: the latest sweep, `R`, the counts, and per condition the mean, the SD and the counts. It never returns the sweep matrix, because nothing the live view draws needs it — every error band it offers is a function of `(mean, SD, n)` ([mabr.metrics.band_from_stats](../+mabr/+metrics/band_from_stats.m)). At sixteen conditions and a 20 ms window that is ~60 KB a cycle.

It is **incremental and exact**. `extract_sweeps` caches the raw windowed sweeps in its cursor; `Pipeline` keeps a parallel filtered cache and passes only the new sweeps through `filtfilt`. That is bit-identical to filtering the whole matrix every time — `FilterPolicy.apply` is column-wise and both artifact criteria judge a sweep on its own samples — and turns a cycle's cost from *all sweeps so far* to *sweeps since the last cycle*. A `configure` that changes the chain throws the cache away; one that changes only the artifact policy re-judges it.

`finalize` is what `AcqController.finalize_run` used to do inline: read the whole block, recover the onsets, `resample` to the analysis rate, split by stimulus, filter, judge — returning plain `parts` (raw and filtered decimated traces, onsets, flags). The controller's `assemble_blocks` turns them into `Recording`s and `Block`s, and adopts each filtered trace through `Recording.withProcessed` so no consumer of the block filters it again.

Three callers, one object: the DSP worker, the metrics worker, and the controller itself when no worker is available. A controller built without workers — which is what every verification script builds — is the in-process path *by construction*.

## Lifecycle

```matlab
ce = mabr.compute.ComputeEngine(cfg,progressFcn);   % maps the buffers, launches the DSP worker
ce.waitUntilReady();                                % bounded; never throws
ce.configure(fs,window,filters,artifacts);          % broadcast; re-sent on every policy change
ce.runStart(info);                                  % RunId, StimIndex, Stimuli, Labels, Meta
[stats,changed] = ce.live();                        % the 20 Hz tick's poll
ce.runEnd(id);
ce.finalize(id,seq);                                % reply arrives as the Finalized event
slot = ce.acquireSlot(); ce.setJob(slot,metricIdx,window); V = ce.values(slot);
```

[mabr.compute.ComputeEngine](../+mabr/+compute/ComputeEngine.m) is the client facade for both roles. The DSP worker launches with it; the metrics worker launches **lazily**, when the first analysis window takes a slot, and a session that never opens one never pays for it. Whatever a late-launched or relaunched worker missed is replayed at its handshake: the last `Configure`, the run in progress, the finalized conditions, the custom metrics.

`mabr.ui.AcqController` owns the engine (its fifth constructor argument asks for it) and is the only thing that sends it run state. `mabr.ui.MetricPlot` takes a slot in `attach` and pushes its metric, window and refresh interval with every setting change.

## Commands and messages

[mabr.compute.Cmd](../+mabr/+compute/Cmd.m) — client to worker, one set for both roles:

| Command | Payload | Handled by |
|---------|---------|------------|
| `Configure` | `DACSampleRate`, `Window`, `Filters`, `Artifacts` (the policies' `toStruct` forms) | both |
| `RunStart` | `RunId`, `StimIndex`, `Stimuli`, `Labels`, `Meta` | both |
| `RunEnd` | `RunId` | both |
| `Finalize` | `RunId`, `StimIndex` | dsp |
| `AddCondition` / `ClearConditions` | a `ConditionStore` condition | metrics |
| `SetCustomMetric` | `Slot`, the function handle | metrics |
| `Kill` | — | both |

**The sample rate is not optional.** A compute worker needs it for the decimation stride and the filter design, so it builds `mabr.Config(fs)` from `Configure` and steps nothing before one arrives. Function handles travel over the queue because they cannot live in a memory map; everything else about a job rides in the request buffer.

Worker to client: `handshake`, `state` ([mabr.compute.State](../+mabr/+compute/State.m): `Idle`, `Ready`, `Working`, `Finalizing`, `Error`), `error`, `roster` (metrics: the condition keys and parameters a published column index refers to), `finalized` (dsp: the `parts`, or an error).

## The publish buffers

[mabr.compute.PublishBuffer](../+mabr/+compute/PublishBuffer.m) holds the discipline once; `LiveBuffer`, `MetricBuffer` and `RequestBuffer` supply the layouts.

Every payload field exists in **two halves**, encoded in the field's shape — a per-half `[m x n]` is stored `[2m x n]`, a per-half column `[m x 2]` — plus a two-word header, `Seq` and `Half`. The writer fills the idle half, flips `Half`, bumps `Seq`, in that order. A reader reads `Seq`, the half `Half` names, and `Seq` again; if `Seq` moved, the payload may be torn and the reader keeps its previous one. The `Seq` re-check is the *correctness* guarantee; the halves are the *fast path*, so a read succeeds first time in steady state. Readers slice rows (`memmapfile` subscripting is lazy) and never read the file — the live file is ~17 MB, a live poll touches ~60 KB.

A worker publishes on **every** cycle of a run, sweeps or none (`Pipeline.emptyStats` is the heartbeat), so a `Seq` that has not moved for far longer than the cadence is the one thing a wedged worker and a live one do not share. `LiveBuffer.read()` returns exactly `Pipeline.step()`'s struct, which is what lets the controller's tick be the same code whichever produced it.

Sizes come from `mabr.Config`: `MaxComputeSamples` (2048 — a sweep's baseline plus response, ~85 ms at 12 kHz), `MaxComputeConditions` (256), `MaxComputeJobs` (8 analysis windows). A window or a run over them is refused with an error, never truncated.

## Degradation, per role

`hasDSP()` and `hasMetrics()` say whether each worker is up, and every consumer checks before it asks. Absent means never launched, not yet handshaken, or declared dead — **never merely slow**. A consumer that finds no new publish keeps its last values and says so; only a worker that is gone sends the work back in-process. Computing in-process the moment a worker is slow would reproduce the overload the workers exist to remove, at exactly the moment the machine is struggling.

The watchdog rides the consumers' own polls; there is no timer. Silence is judged only *after* reading the sequence word — a run's preparation can take seconds between `runStart` and the first tick, while the worker heartbeats throughout. A worker silent for far longer than its cadence is cancelled and relaunched **once**; if the fresh handshake never arrives (a hang inside a builtin may not answer `cancel`) the role is written off for the session and the status line says so. The pool is never deleted or recreated mid-acquisition — that would kill the acquisition worker.

The three states this produces:

| DSP worker | metrics worker | What happens |
|------------|----------------|--------------|
| up | up | Live view from published statistics; analysis windows read their slots. No DSP in the GUI process. |
| up | absent | Live view as above; analysis windows evaluate in-process (there is no sweep matrix in the foreground, so only finalized conditions are plotted). |
| absent | — | The controller steps its own pipeline; everything is as it was before the workers existed. |

A DSP worker that dies mid-run is covered on the next tick: the controller's own pipeline has been following the run too, and re-extracts from the ring, which still holds it.

**Finalization** is asynchronous with a DSP worker: `on_block_completed` sends `Finalize` and returns with `ProgState` in `BlockComplete`; the reply, or a single-shot timeout (`AcqController.FinalizeTimeout` plus a per-sample allowance), runs the schedule-advance tail. On timeout the run is finalized in the GUI process from the ring buffer — nothing overwrites it until the next `Run` — and the worker is reported as stalled.

## The metrics worker and untrusted code

The metrics worker exists as a *separate* process for one reason: user-supplied metric functions are the only untrusted code in the system, and a MATLAB worker is single-threaded, so a hung one cannot be interleaved around. In its own process a hang costs the analysis windows and nothing else — the live trace, the advance criterion and finalization are unreachable from it.

When the metrics worker stalls, every custom metric is suspect (there is no telling which one hung): all are dropped from the relaunched worker, their slots are flagged, and a window whose slot is flagged shows a note and evaluates **nothing** in-process — a hang in the GUI is the outcome the third worker exists to prevent. Picking another metric clears the flag. `mabr.metrics.online.validate` still runs at selection time, so a metric that throws or returns the wrong shape never reaches the worker; only a genuine hang does.

## Priorities

The acquisition worker runs `high priority`, the DSP worker `below normal`, the metrics worker `idle` — this is a real-time audio rig, and these are the processes that must lose when the CPU is short. `mabr.acq.Engine.set_priority` applies them through .NET (`System.Diagnostics.Process.PriorityClass`); the legacy `wmic` call it replaced is a deprecated Feature-on-Demand that Windows 11 24H2 and later no longer install by default.

## The preference

The workers need a pool of three; a pool cannot be resized once the acquisition worker is on it, and the acquisition loop never returns. So the setting is a **preference** (`MABR`/`ComputeWorker`, default on) that `App.ensureController` reads before building a controller, sizing the pool with [mabr.pool](../+mabr/pool.m) — which recreates a too-small pool only while nothing runs on it, and never shrinks one. Toggling it takes effect at the next Start and restarts the pool. A pool that cannot be sized (busy, or the cluster profile too small) costs the workers for the session and never the acquisition.

## Testing

[verify_compute_worker](../tests/verify_compute_worker.m) covers, with no hardware: the publish buffers (round-trip, the other half winning, the heartbeat, no torn reads under rapid publishing); a controller served by the DSP worker whose own pipeline is never stepped; the worker's statistics and finalization **bit-identical** to the in-process pipeline over the same ring bytes; priorities read back as set; the metrics worker matching the same window's in-process values, slots running out gracefully, and a hung custom metric contained and the worker relaunched without it; the advance criterion firing through the worker; and a DSP worker killed mid-run, with the run finalized anyway and the schedule completing. The worker parts skip and pass where the machine's cluster profile cannot provide three workers.

Every other verification script builds its controller without workers and so exercises the in-process path unchanged.
