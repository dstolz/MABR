# Extending MABR

The three extension points, in order of how often they are used: supplying stimuli, defining when a run ends, and building a different front end.

## Supplying stimuli

This is the main integration point, and the contract is deliberately small: **you supply single waveforms, MABR decides how they are presented.**

Hand MABR a plain struct array. Each element is **one** stimulus — one presentation, not a repeated train:

```matlab
stim(1).signal = [ ... ];        % one presentation, calibrated
stim(1).ID     = "8kHz_60dB";
...
stim(N).signal = [ ... ];
stim(N).ID     = "click_rare";
```

### The stimulus entry

**Required:**

| Field | Type | Meaning |
|-------|------|---------|
| `signal` | `[N x 1]` numeric | One calibrated presentation. No repetition, no inter-stimulus padding, no timing channel. |
| `ID` | string or char | Names the condition. Drives the `.abr` filename and the de-interleaving of intermixed runs. |

**Optional, interpreted by MABR:**

| Field | Meaning |
|-------|---------|
| `SampleRate` | DAC rate; defaults to `Config.DACSampleRate` and **must equal** it |
| `Repetitions` | Starting repetition count the GUI picks up (the operator can still change it) |
| `Timing` | `[N x 1]` your own timing channel for this stimulus; otherwise MABR synthesizes a unit pulse at the onset |
| `alternatePolarity` | Logical. Present successive repetitions as `+1, -1, +1, …`, splitting the repetition count between the two polarities rather than doubling it |
| `informativeParams` | Cellstr. The passthrough fields that *identify* this condition. Supply it when your generator emits more numeric fields than it varies (see below) |

**Every other field passes straight through** into the block metadata and on to the saved `.abr`. Numeric scalars are additionally advertised as `informativeParams`, so the offline pipeline picks them up without any extra declaration:

```matlab
stim(k).Frequency = 8;      % -> SIG.Frequency, and an informativeParam
stim(k).Level     = 60;     % -> SIG.Level,     and an informativeParam
stim(k).Notes     = 'left'; % -> carried along, not an informativeParam
```

That inference is right for a hand-built bank whose only extras *are* its parameters. It goes wrong for a generator, which emits every knob it has — window duration, onset phase, ramp time — and each name in `informativeParams` becomes a **grouping dimension** in the offline pipeline, splitting what should be one condition into many. If you know which of your parameters actually vary across the bank, say so:

```matlab
stim(k).informativeParams = {'Frequency','Level'};   % these identify the condition
stim(k).WindowDuration    = 0.002;                   % carried, but not a dimension
```

Supplying `Frequency` and `Level` specifically makes the written filename match the offline pipeline's default regex; without them MABR falls back to `ID`. See [Data Files](Data-Files.md).

### Loading it

Save the struct array to a `.mat` file and the GUI's **Load bank…** button picks it up — [mabr.stim.StimulusSet.fromFile](../+mabr/+stim/StimulusSet.m) finds any variable that is a struct array with `signal` and `ID`. Headlessly:

```matlab
set = mabr.stim.StimulusSet(stim);       % validates and normalizes
```

[mabr.stim.demoStimuli](../+mabr/+stim/demoStimuli.m) is a complete worked example — read it before writing your own.

### Or use stimgen

[stimgen](https://github.com/dstolz/stimgen) ships with MABR as a submodule and already satisfies all of the above; [mabr.stim.fromStimgen](../+mabr/+stim/fromStimgen.m) does the conversion. Reach for the raw contract when you have a stimulus stimgen cannot make, or waveforms from somewhere else entirely — not merely to avoid a dependency.

```matlab
t = stimgen.Tone;
t.Frequency  = [8000 16000];   % a vector expands into variants...
t.SoundLevel = [30 60];        % ...Cartesian, so this is 4 stimuli
set = mabr.stim.fromStimgen(t);          % one variant -> one entry
set = mabr.stim.fromStimgen('bank.spl'); % or a saved bank
```

Two things it does that a naive conversion would not, both worth understanding if you write your own bridge to some other generator:

- **Regenerate, don't resample.** It sets `Fs = Config.DACSampleRate` on a `copy()` of each stimulus and calls `update_signal()`, so every waveform is synthesized natively at 192 kHz. stimgen's own default is 97656.25 Hz. This is why it imports *parameters*, never a bank's cached `Signal`.
- **Pin the variant before reading it back.** stimgen's `VariantReselectOnUpdate` defaults true, which makes every parameter read outside an update cycle silently advance to the *next* variant — so metadata read after selecting variant 3 can describe variant 4 while the waveform is still variant 3's. `fromStimgen` forces it false first. [tests/verify_stimgen_import.m](../tests/verify_stimgen_import.m) FFTs every generated waveform against its own label to prove the pairing holds.

### What MABR decides

Everything about *presentation* is MABR's, not yours. [mabr.stim.Schedule](../+mabr/+stim/Schedule.m) owns three settings, all driven from the GUI:

| Setting | Meaning |
|---------|---------|
| `ISI` | Spacing between successive onsets (s, onset-to-onset), when `ISIMode` is `'fixed'`. GUI shows it as linked ISI/rate fields, default 21.1 Hz. |
| `ISIMode` / `ISIRange` | `'random'` draws each interval independently and uniformly from `ISIRange` = `[min max]` s instead, so the presentation rate carries no periodicity of its own. `MinISI`/`MeanISI` report the two numbers worth reasoning with: the shortest interval that can occur (what overlap is judged against) and the one a duration estimate is built on. |
| `Repetitions` | How many times each entry is presented. One value for all, or one per entry. |
| `Strategy` | How entries are combined across the array. |

The strategies:

| Strategy | Runs | Shape |
|----------|------|-------|
| `blocked` | one per stimulus | `A A A … / B B B … / C C C …`, in array order |
| `shuffled-blocks` | one per stimulus | same, but the order of the runs is shuffled |
| `interleaved` | one | `A B C A B C …` |
| `shuffled-cycles` | one | as interleaved, each cycle shuffled independently |
| `shuffled` | one | the whole multiset shuffled uniformly |

All five are permutations of a **fixed multiset**, never probabilistic sampling — every entry is presented exactly its repetition count under any strategy. The names say "shuffled" rather than "random" for precisely that reason.

The last three **intermix** different stimuli inside one continuous acquisition run. MABR records which stimulus fired at each onset (`spec.StimulusIndex`) and de-interleaves the recorded sweeps at save time, so **each stimulus ID still gets its own `.abr` file** regardless of presentation order. An entry that has met its repetition count drops out of later cycles, so unequal counts stay spread out instead of clumping at the end.

Set `Seed` for a reproducible order — and, under `ISIMode = 'random'`, reproducible timing with it; leave it empty for a fresh shuffle each time. A private `RandStream` is used either way, so neither building a plan nor rendering one perturbs global `rng`.

`Schedule` also renders the play matrix: it pairs your signal with a **synthesized timing channel**, brackets the result with silence for device settling, pads to a whole number of frames, and attaches channel mappings (`SilencePad`, `PlayerChannels`, `RecorderChannels`, `Device`). MABR owns the timing contract because sweep extraction depends on it — see [Architecture](Architecture.md#what-mabr-does-not-do).

Two constraints worth knowing:

- If a stimulus is longer than `MinISI` — the ISI, or the bottom of `ISIRange` — presentations are **summed** where they overlap and the condition is logged; the GUI warns before acquisition starts.
- One run is recorded in one ring-buffer pass, so a run may not exceed `Config.maxInputBufferLength` (~5.8 min at 192 kHz). `renderSpec` refuses with `mabr:stim:Schedule:tooLong` rather than silently discarding the earliest sweeps. Intermixed strategies put every presentation in one run, so this is the ceiling that bites first — the GUI's plan summary shows the estimated duration before you start.

## Defining when a run ends

An advance criterion is a **pure predicate over a context struct**:

```matlab
function done = my_criterion(ctx)
```

`AcqController` calls it on every live tick with a context built from `AdvanceParams` plus the current `numSweeps` and `corr`. Return `true` to end the run; the controller sends `Stop` and the worker halts within one frame.

**Criteria only run for blocked strategies.** An intermixed run pools sweeps from different conditions, so a correlation over it is meaningless, and stopping it early would truncate whichever stimuli happened to fall last in the sequence. `AcqController` therefore skips the criterion entirely when `Schedule.isIntermixed()` is true, and the GUI disables the control. Those runs always play to completion.

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

Two rules. **Always include a hard cap** — a criterion that never fires runs until the scheduled repetitions are exhausted. And **keep it cheap and side-effect-free**: it runs 20 times a second on the GUI thread. If you need a metric the controller does not compute, add it to `live_tick_body` from a [+metrics](../+mabr/+metrics/) function rather than recomputing it inside the predicate.

To expose a new criterion in the GUI, add it to the `AdvanceDrop` items and the mapping in `App.onStart`.

## Building a different front end

[AcqController](../+mabr/+ui/AcqController.m) is the whole program; [App](../+mabr/+ui/App.m) is one view of it. Drive the controller and listen to its events:

| Event | Payload | Meaning |
|-------|---------|---------|
| `StateChanged` | `ProgStateEventData.State` | Program flow changed |
| `MetricsUpdated` | `.Info` = `numSweeps`, `corr` | Live metrics |
| `BlockReady` | `.Info.block` | A finalized `mabr.data.Block` is available — fires **once per stimulus** recovered from the run, whether or not it was written to disk |
| `BlockSaved` | `.Info.file` | A block was written — fires once per stimulus, and only when the `Session` has an `OutputPath` |
| `ScheduleComplete` | — | Schedule finished |

A viewer should listen to `BlockReady`, not `BlockSaved`: it carries the block itself, and a session configured with no output path never raises `BlockSaved` at all.

Public surface: `setStimuli`, `setLivePlot`, `waitUntilReady`, `start`, `pauseAcq`, `resumeAcq`, `stopBlock`, `abort`, and the settable properties `Window`, `AdvanceFcn`, `AdvanceParams`, `Filters`, `Artifacts`. `setStimuli` accepts either a `StimulusSet` or the raw struct array, and builds a default `Schedule` you then configure:

```matlab
c.setStimuli(stim);                      % struct array or StimulusSet
c.Schedule.Strategy    = 'shuffled-cycles';
c.Schedule.Repetitions = 512;            % scalar, or one value per stimulus
c.Schedule.ISI         = 1/21.1;
c.Schedule.build();                      % required after changing either
c.start();
```

For an embedded live view, pass a container to `LivePlot` and hand it over with `setLivePlot`:

```matlab
lp = mabr.ui.LivePlot(myPanel);
lp.Layout   = 'separate';    % one axes per stimulus instead of overlaid
lp.TimeBase = [-2 10];       % ms, the negative half being the baseline
lp.AmpMode  = 'each';        % or 'common' / 'manual' + lp.ManualLimit
c.setLivePlot(lp);
```

The container gets the whole view — the latest-sweep axes, the per-stimulus means, and the control strip — laid out around a fixed-height strip at the bottom. Setting those properties is exactly what the strip does, so a host UI can drive the view from its own controls instead.

Anything more custom can skip `LivePlot` entirely and draw from `MetricsUpdated` plus its own `extract_sweeps` cursor over `c.Engine.RingBuffer` (read-only).

## Using the engine directly

For a specialized rig, skip the controller and drive [Engine](../+mabr/+acq/Engine.m) yourself:

```matlab
eng = mabr.acq.Engine(mabr.Config,false);
eng.waitUntilReady();
addlistener(eng,'BlockCompleted',@(~,~) onDone());
addlistener(eng,'WorkerError',   @(~,e) warning(e.Identifier,'%s',e.Message));

sch = mabr.stim.Schedule(mabr.stim.StimulusSet(stim));
sch.Repetitions = 512; sch.ISI = 1/21.1; sch.build();

spec = sch.renderSpec(1);
eng.prep(spec); eng.run();
```

You then own finalization: read the ring buffer, find onsets, pair them with `spec.StimulusIndex`, decimate, build a `Recording` per stimulus, and save. `AcqController.finalize_run` is the reference implementation — copy its ordering, particularly the `max(1,...)` floor on decimated onsets and the truncation to `min(numel(onsets),numel(seq))` that tolerates an early stop. See [Acquisition Engine](Acquisition-Engine.md) for the full protocol.

## Adding a metric

Put it in [+metrics](../+mabr/+metrics/) as a pure function taking a `[nSamples x nSweeps]` matrix (or a `[nSweeps x nSamples]` one, for the extraction-side functions — follow the neighbours). Then call it from `Block.computeMetrics`, the live tick, or both. Metrics stay pure so that the live and offline paths cannot disagree; do not compute a metric inline in the controller.

Note the naming convention: [rms_metric](../+mabr/+metrics/rms_metric.m) and [find_peaks](../+mabr/+metrics/find_peaks.m) are named to avoid shadowing the Signal Processing Toolbox functions they call.

## Before you commit

Run [the verification suite](Testing.md):

```matlab
>> run_all_verifications
```

If you touched [io](../+mabr/+data/io.m), `verify_data_roundtrip` is the test that protects the offline pipeline's file contract — treat a failure there as a breaking change, not a test to update.
