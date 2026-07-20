# Extending MABR

The three extension points, in order of how often they are used: supplying stimuli, defining when a block ends, and building a different front end.

## Supplying stimuli

This is the main integration point. MABR consumes calibrated waveforms through [mabr.stim.StimulusSource](../+mabr/+stim/StimulusSource.m), an abstract two-method contract:

```matlab
n   = numBlocks(obj)      % how many blocks in this session
blk = getBlock(obj,idx)   % the spec struct for block idx
```

### The block spec

Each `getBlock` returns a struct. **Required:**

| Field | Type | Meaning |
|-------|------|---------|
| `samples` | `[N x 1] single` | The calibrated signal channel |
| `SampleRate` | scalar double | DAC rate; **must equal `Config.DACSampleRate`** |

**Sweep timing — one of:**

| Field | Meaning |
|-------|---------|
| `SweepOnsets` | `[k x 1]` onset sample indices into `samples` |
| `SweepRate` | Sweeps per second, optionally with `NumSweeps` |

**Should provide** — `Meta`, a struct that drives display and the saved file:

| Field | Purpose |
|-------|---------|
| `Frequency`, `Level` | Numeric; drive the filename the offline pipeline parses |
| `Polarity` | Stimulus polarity |
| `Label` | Cellstr, for display and for `SIG.Label` |
| `informativeParams` | Cellstr naming the numeric fields to persist |
| `NumSweeps` | Per-block override of the queue's target |

**May provide** — `Timing` (`[N x 1] single`, your own timing channel; otherwise MABR synthesizes one pulse per onset) and `Device` (ASIO device name override).

`StimulusSource.validateBlock` is a static helper that checks and normalizes a spec; call it in your own source if you want the same errors MABR would raise.

### The quickest route

If your package can produce a struct array of specs, you do not need to write a class at all — [mabr.stim.PrecomputedSource](../+mabr/+stim/PrecomputedSource.m) wraps one:

```matlab
blocks = struct('samples',{},'SampleRate',{},'SweepOnsets',{},'Meta',{});
for k = 1:numel(conditions)
    blocks(end+1) = struct( ...
        'samples',     myCalibratedWaveform(conditions(k)), ...
        'SampleRate',  192000, ...
        'SweepOnsets', myOnsets(conditions(k)), ...
        'Meta',        struct('Frequency',conditions(k).f, ...
                              'Level',    conditions(k).L, ...
                              'Polarity', 1, ...
                              'NumSweeps',512, ...
                              'informativeParams',{{'Frequency','Level'}}, ...
                              'Label',{{sprintf('%g kHz',conditions(k).f), ...
                                        sprintf('%g dB', conditions(k).L)}}));
end
source = mabr.stim.PrecomputedSource(blocks);
```

Save that struct array to a `.mat` file and the GUI's **Load .mat…** button will pick it up. [mabr.stim.demoSource](../+mabr/+stim/demoSource.m) is a complete worked example — read it before writing your own.

### A custom source class

Subclass when blocks should be generated lazily, streamed from disk, or reordered adaptively:

```matlab
classdef MySource < mabr.stim.StimulusSource
    properties (SetAccess = private)
        Conditions
    end
    methods
        function obj = MySource(conditions)
            obj.Conditions = conditions;
        end
        function n = numBlocks(obj)
            n = numel(obj.Conditions);
        end
        function blk = getBlock(obj,idx)
            c = obj.Conditions(idx);
            blk = mabr.stim.StimulusSource.validateBlock(struct( ...
                'samples',    renderWaveform(c), ...
                'SampleRate', 192000, ...
                'SweepOnsets',renderOnsets(c), ...
                'Meta',       c.meta));
        end
    end
end
```

`getBlock` is called at least twice per block (once by `targetSweeps`, once by `renderSpec`), so cache anything expensive.

### What MABR adds

[BlockQueue](../+mabr/+stim/BlockQueue.m) turns your spec into what the worker streams: it pairs your signal with a **synthesized timing channel** (a unit pulse at each onset), brackets the result with silence for device settling, pads to a whole number of frames, and attaches channel mappings. MABR owns the timing contract because sweep extraction depends on it — see [Architecture](Architecture.md#what-mabr-does-not-do).

MABR also owns the **presentation rate**. Whatever rate you tiled your block at, `BlockQueue` extracts the single-sweep waveform back out (first onset to the next, trailing silence trimmed) and re-tiles it at `SweepInterval` — the inter-stimulus interval in seconds, set from the GUI's linked ISI/rate fields and defaulting to 21.1 Hz. Your `SweepOnsets` are the fallback used only when `SweepInterval` is `0`. If your stimulus is longer than the interval the operator picks, the sweeps are summed where they overlap and the condition is logged; the GUI warns before acquisition starts.

`BlockQueue` also controls schedule order (`Order`), which blocks are enabled (`Selected`), padding (`SilencePad`), and channel mapping (`PlayerChannels`, `RecorderChannels`). Reordering `Order` is how you would implement a randomized or interleaved schedule.

## Defining when a block ends

An advance criterion is a **pure predicate over a context struct**:

```matlab
function done = my_criterion(ctx)
```

`AcqController` calls it on every live tick with a context built from `AdvanceParams` plus the current `numSweeps` and `corr`. Return `true` to end the block; the controller sends `Stop` and the worker halts within one frame.

Two are supplied:

- [num_sweeps](../+mabr/+stim/+advance/num_sweeps.m) — `ctx.numSweeps >= ctx.targetSweeps`.
- [corr_threshold](../+mabr/+stim/+advance/corr_threshold.m) — `ctx.corr >= ctx.corrThreshold` after `ctx.minSweeps`, or `ctx.numSweeps >= ctx.maxSweeps`.

A custom one, stopping on SNR with a hard cap:

```matlab
function done = snr_threshold(ctx)
    minN = 64;
    done = (ctx.numSweeps >= minN && ctx.snr >= ctx.snrTarget) || ...
            ctx.numSweeps >= ctx.maxSweeps;
end
```

```matlab
c.AdvanceFcn    = @snr_threshold;
c.AdvanceParams = struct('snrTarget',10,'maxSweeps',2048, ...
                         'targetSweeps',2048,'corrThreshold',0.5,'minSweeps',64);
```

Two rules. **Always include a hard cap** — a criterion that never fires runs until the stimulus is exhausted. And **keep it cheap and side-effect-free**: it runs 20 times a second on the GUI thread. If you need a metric the controller does not compute, add it to `live_tick_body` from a [+metrics](../+mabr/+metrics/) function rather than recomputing it inside the predicate.

To expose a new criterion in the GUI, add it to the `AdvanceDrop` items and the mapping in `App.onStart`.

## Building a different front end

[AcqController](../+mabr/+ui/AcqController.m) is the whole program; [App](../+mabr/+ui/App.m) is one view of it. Drive the controller and listen to four events:

| Event | Payload | Meaning |
|-------|---------|---------|
| `StateChanged` | `ProgStateEventData.State` | Program flow changed |
| `MetricsUpdated` | `.Info` = `numSweeps`, `corr` | Live metrics |
| `BlockSaved` | `.Info.file` | A block was written |
| `ScheduleComplete` | — | Schedule finished |

Public surface: `setSource`, `setLivePlot`, `waitUntilReady`, `start`, `pauseAcq`, `resumeAcq`, `stopBlock`, `abort`, and the settable properties `Window`, `AdvanceFcn`, `AdvanceParams`, `UseBandpass`, `UseNotch`.

For an embedded live view, pass a container to `LivePlot` and hand it over with `setLivePlot`:

```matlab
lp = mabr.ui.LivePlot(myPanel);
c.setLivePlot(lp);
```

Anything more custom can skip `LivePlot` entirely and draw from `MetricsUpdated` plus its own `extract_sweeps` cursor over `c.Engine.RingBuffer` (read-only).

## Using the engine directly

For a specialized rig, skip the controller and drive [Engine](../+mabr/+acq/Engine.m) yourself:

```matlab
eng = mabr.acq.Engine(mabr.Config,false);
eng.waitUntilReady();
addlistener(eng,'BlockCompleted',@(~,~) onDone());
addlistener(eng,'WorkerError',   @(~,e) warning(e.Identifier,'%s',e.Message));

spec = mabr.stim.BlockQueue.buildSpec(myBlock,mabr.Config,0.25);
eng.prep(spec); eng.run();
```

You then own finalization: read the ring buffer, find onsets, decimate, build a `Recording`, and save. `AcqController.finalize_block` is the reference implementation — copy its ordering, particularly the `max(1,...)` floor on decimated onsets. See [Acquisition Engine](Acquisition-Engine.md) for the full protocol.

## Adding a metric

Put it in [+metrics](../+mabr/+metrics/) as a pure function taking a `[nSamples x nSweeps]` matrix (or a `[nSweeps x nSamples]` one, for the extraction-side functions — follow the neighbours). Then call it from `Block.computeMetrics`, the live tick, or both. Metrics stay pure so that the live and offline paths cannot disagree; do not compute a metric inline in the controller.

Note the naming convention: [rms_metric](../+mabr/+metrics/rms_metric.m) and [find_peaks](../+mabr/+metrics/find_peaks.m) are named to avoid shadowing the Signal Processing Toolbox functions they call.

## Before you commit

Run [the verification suite](Testing.md):

```matlab
>> run_all_verifications
```

If you touched [io](../+mabr/+data/io.m), `verify_data_roundtrip` is the test that protects the offline pipeline's file contract — treat a failure there as a breaking change, not a test to update.
