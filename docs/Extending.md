# Extending MABR

The four extension points, in order of how often they are used: supplying stimuli, ordering how they are presented, defining when a run ends, and building a different front end.

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
| `custom` | as many as you return | whatever your own function decides — see [Ordering presentations yourself](#ordering-presentations-yourself) |

The five built-ins are permutations of a **fixed multiset**, never probabilistic sampling — every entry is presented exactly its repetition count under any of them. The names say "shuffled" rather than "random" for precisely that reason. A `custom` strategy is expected to hold to the same invariant and is warned when it does not, but is not refused.

The last three **intermix** different stimuli inside one continuous acquisition run. MABR records which stimulus fired at each onset (`spec.StimulusIndex`) and de-interleaves the recorded sweeps at save time, so **each stimulus ID still gets its own `.abr` file** regardless of presentation order. An entry that has met its repetition count drops out of later cycles, so unequal counts stay spread out instead of clumping at the end.

Set `Seed` for a reproducible order — and, under `ISIMode = 'random'`, reproducible timing with it; leave it empty for a fresh shuffle each time. A private `RandStream` is used either way, so neither building a plan nor rendering one perturbs global `rng`.

`Schedule` also renders the play matrix: it pairs your signal with a **synthesized timing channel**, brackets the result with silence for device settling, pads to a whole number of frames, and attaches channel mappings (`SilencePad`, `PlayerChannels`, `RecorderChannels`, `Device`). MABR owns the timing contract because sweep extraction depends on it — see [Architecture](Architecture.md#what-mabr-does-not-do).

Two constraints worth knowing:

- If a stimulus is longer than `MinISI` — the ISI, or the bottom of `ISIRange` — presentations are **summed** where they overlap and the condition is logged; the GUI warns before acquisition starts.
- One run is recorded in one ring-buffer pass, so a run may not exceed `Config.maxInputBufferLength` (~5.8 min at 192 kHz). `renderSpec` refuses with `mabr:stim:Schedule:tooLong` rather than silently discarding the earliest sweeps. Intermixed strategies put every presentation in one run, so this is the ceiling that bites first — the GUI's plan summary shows the estimated duration before you start.

## Ordering presentations yourself

When none of the five built-in strategies describes the design you want, `Strategy = 'custom'` hands the ordering to a function of yours. It is a **pure function from a design to an order** — one stereotyped input, one stereotyped output:

```matlab
function runs = my_strategy(ctx)   % ctx in, the presentation order out
```

The contract is defined in one place, [mabr.stim.strategy.context](../+mabr/+stim/+strategy/context.m), which builds the `ctx` every strategy is called under. Your function is called **once, when the plan is built**, and never again during acquisition — so unlike an advance criterion it may be as expensive as it likes, and for the same reason it cannot react to incoming data. (Reacting to data is what an [advance criterion](#defining-when-a-run-ends) is for; the two compose.)

### What you are given

| `ctx` field | Kind | Meaning |
|-------------|------|---------|
| `numStimuli` | design | entries in the bank |
| `repetitions` | design | `[1 x n]` presentations owed per entry, already normalized (a scalar arrives expanded over the bank) |
| `alternatePolarity` | design | `[1 x n]` logical, which entries alternate polarity |
| `IDs` | design | `{1 x n}` each entry's ID |
| `durations` | design | `[1 x n]` seconds, one presentation of each |
| `params` | design | the bank as a table — `.Names`, `.Values [n x nP]`, `.Varying`, `.Units` — from [`StimulusSet.paramTable`](../+mabr/+stim/StimulusSet.m) |
| `sampleRate` | timing | Hz, the DAC rate the plan renders at |
| `isi` / `isiMode` / `isiRange` / `minISI` / `meanISI` | timing | the spacing settings, as `Schedule` holds them |
| `silencePad` | timing | s of silence bracketing each run |
| `maxRunSamples` | timing | `Config.maxInputBufferLength` — one run is one ring-buffer pass |
| `randStream` | — | the schedule's own `RandStream`; **shuffle with this** |

`ctx.params` is the field that makes a strategy readable. A bank almost never varies along one dimension — the ordinary ABR run is a Frequency × Level grid — and it lets you sort, group, and select by those dimensions **by name** instead of parsing IDs:

```matlab
jLevel = find(strcmp(ctx.params.Names,'Level'),1);
level  = ctx.params.Values(:,jLevel);        % one row per bank entry
```

Anything you put in `Schedule.StrategyParams` arrives in `ctx` under its own field name, so a strategy can carry its own knobs — exactly as `AdvanceParams` feeds an advance criterion.

### What you return

Return whichever shape is least effort for your design; [mabr.stim.strategy.normalize](../+mabr/+stim/+strategy/normalize.m) reads all three:

| Return | Means |
|--------|-------|
| `seq` — a numeric vector | **one** run presenting those stimulus indices, in that order |
| `{seq1,seq2,…}` — a cell of vectors | that many runs, in that order |
| `struct('Runs',…,'Polarities',…)` | the same, with polarity placed by you |

Indices are 1-based into the bank `ctx` describes. Empty runs are dropped rather than streamed as a block of silence, and returning nothing at all is a plan with nothing in it — not an error.

**Polarity is assigned for you** unless you ask otherwise. The k-th presentation of an entry flagged `alternatePolarity` gets `+1` for odd k and `-1` for even k, counted *across the whole plan* rather than restarted per run — so an entry spread over several runs still comes out balanced between the two polarities, which is the entire reason for alternating them. This reproduces the built-in strategies' polarity **exactly**: a custom reordering of a blocked or cycled plan gets the same signs the built-in would have given it. Supply `.Polarities` only when you need otherwise.

### Three rules

1. **Shuffle from `ctx.randStream`** — `randperm(ctx.randStream,n)`, not `randperm(n)`. Building a plan must not perturb global `rng`, and it is what makes `Schedule.Seed` reproduce a whole session: order and, under `ISIMode = 'random'`, timing with it.
2. **Watch the run length.** One run is recorded in one pass of the ring buffer, so roughly `numel(run)*ctx.meanISI*ctx.sampleRate` must stay under `ctx.maxRunSamples` (~5.8 min at 192 kHz). Putting every presentation in one run is what makes this bite; split into several and the ceiling is per-run.
3. **Present each entry its `ctx.repetitions` count**, unless you mean not to. Departing is allowed and *logged*, not refused — but the usual cause is a cycle that assumed equal counts, not a design.

Structural mistakes are errors rather than warnings, because no design intends them and none can be presented at all: an index off the end of the bank, a non-integer, a polarity that is not ±1.

### A worked example

[custom_template.m](../+mabr/+stim/+strategy/custom_template.m) is a copy-me stereotype and a real strategy: **one run per condition, grouped by frequency, loudest first within each group.**

No built-in can express it — `blocked` presents in array order and the shuffled ones scramble it — and it is what an ABR threshold series usually wants. The loud conditions respond visibly, so a dead electrode or a slipped ear plug shows up in the first minute rather than after twenty spent collecting noise near threshold.

```matlab
function runs = descending_levels(ctx)
    level = paramColumn(ctx,'Level');
    freq  = paramColumn(ctx,'Frequency');
    if isempty(level) && isempty(freq)
        order = 1:ctx.numStimuli;                 % nothing to sort by
    else
        if isempty(freq),  freq  = zeros(ctx.numStimuli,1); end
        if isempty(level), level = zeros(ctx.numStimuli,1); end
        [~,order] = sortrows([freq(:) -level(:)]);   % freq up, level down
        order = order(:)';
    end

    runs = {};
    for i = order
        if ctx.repetitions(i) <= 0, continue, end
        runs{end+1} = repmat(i,1,ctx.repetitions(i));   %#ok<AGROW>
    end
end

function v = paramColumn(ctx,name)
    v = [];
    if isempty(ctx.params.Names), return, end
    j = find(strcmpi(ctx.params.Names,name),1);
    if isempty(j), return, end
    v = ctx.params.Values(:,j);
end
```

On an 8/16 kHz × 30/60/90 dB bank that plans six runs in the order `8 kHz 90 dB`, `8 kHz 60`, `8 kHz 30`, `16 kHz 90`, `16 kHz 60`, `16 kHz 30`. Note the `paramColumn` helper returns `[]` rather than throwing when the bank has no such parameter, and the strategy falls back to bank order: **a strategy that errors on a bank missing the field it hoped for is worse than one that degrades to the obvious thing.**

Drive it directly:

```matlab
sch             = mabr.stim.Schedule(stimulusSet,cfg);
sch.Strategy    = 'custom';
sch.StrategyFcn = @descending_levels;
sch.Repetitions(:) = 512;
sch.build();
```

Try one at the command line without building a bank at all — [`sampleContext`](../+mabr/+stim/+strategy/sampleContext.m) returns a representative design (a Frequency × Level grid with unequal repetition counts and one entry alternating polarity):

```matlab
ctx  = mabr.stim.strategy.sampleContext();
runs = descending_levels(ctx)
```

### Two more shapes

**Several runs from one design** — a paired ABBA ordering, one cycle per run, so the operator can stop cleanly between them:

```matlab
function runs = abba_cycles(ctx)
    fwd  = 1:ctx.numStimuli;
    back = fliplr(fwd);
    runs = {};
    for c = 1:max(ctx.repetitions)
        if mod(c,2), cycle = fwd; else, cycle = back; end
        runs{end+1} = cycle(ctx.repetitions(cycle) >= c);  %#ok<AGROW>
    end
end
```

**A reproducible shuffle with a constraint** — no stimulus twice in a row, drawn from the schedule's own stream so a `Seed` reproduces it. Note it *constructs* the order rather than reshuffling until one happens to satisfy the constraint: on a real bank a uniform shuffle of a few thousand presentations essentially never comes out repeat-free, so a retry loop would always exhaust its attempts and hand back an order that quietly breaks the rule it was written to enforce.

```matlab
function seq = no_repeats(ctx)
    % Greedy: at each step take whichever entry has the most presentations
    % still owed, excluding the one just placed. This is what makes the
    % constraint reachable -- taking the most-owed first is what stops one
    % entry piling up at the end with nothing to separate it from itself.
    left = ctx.repetitions;
    seq  = zeros(1,sum(left));
    prev = 0;
    for k = 1:numel(seq)
        avail = find(left > 0);
        avail(avail == prev) = [];
        if isempty(avail)
            % Only the just-placed entry is left: an unavoidable repeat, not
            % a bug -- a bank of one entry can never satisfy the constraint.
            avail = find(left > 0);
        end
        best   = avail(left(avail) == max(left(avail)));
        pick   = best(randi(ctx.randStream,numel(best)));   % tie-break, seeded
        seq(k) = pick;
        left(pick) = left(pick) - 1;
        prev       = pick;
    end
end
```

### Selecting one from the GUI

The Presentation panel's **Strategy** dropdown has a **Custom function…** item: pick it, choose your function's `.m` file, and MABR puts its folder on the path and checks it against the contract with [mabr.stim.strategy.validate](../+mabr/+stim/+strategy/validate.m) before accepting it. The validator runs your function on the same representative design `sampleContext` supplies — unequal repetition counts included — so a strategy that assumes every entry is owed the same number is refused at selection time rather than at Start with the rig warmed up.

Once accepted the dropdown reads `Custom: <name>`, and the choice is remembered **by file** in a saved [configuration](Acquisition-App.md) so it re-resolves next session; a file that has moved or no longer conforms leaves the built-in strategy in place and says so, rather than selecting a `custom` with nothing behind it.

Two consequences worth knowing:

- **Early stop follows the plan, not the name.** Whether a custom strategy intermixes is a property of the runs it produced, so `Schedule.isIntermixed` asks the built plan whether any run holds more than one stimulus. A custom strategy emitting one stimulus per run keeps the correlation early-stop, the Repeat button, and the live view's correlation bar; one that mixes loses all three, exactly as the built-in intermixed strategies do.
- **The record names your function.** A `.stimlog`'s `Presentation.Strategy` reads `custom: descending_levels`, not just `custom` — a record of what was presented that cannot name the function that ordered it cannot be reproduced from.

Setting `Strategy = 'custom'` with no `StrategyFcn` is refused (`mabr:stim:Schedule:noStrategyFcn`) rather than quietly falling back to a built-in: a session presented in an order nobody chose is worse than one that will not start.

## Defining when a run ends

An advance criterion is a **pure predicate over a context struct** — one stereotyped input, one stereotyped output:

```matlab
function done = my_criterion(ctx)   % ctx in, a single logical out
```

The contract is defined in one place, [mabr.stim.advance.context](../+mabr/+stim/+advance/context.m), which builds the `ctx` every criterion is called under by merging your tuning **parameters** (from `AdvanceParams`) with the **live metrics** the controller recomputes each ~20 Hz tick. Return `true` to end the run; the controller sends `Stop` and the worker halts within one frame.

| `ctx` field | Kind | Meaning |
|-------------|------|---------|
| `numSweeps` | metric | **clean** sweeps averaged so far (artifact-rejected ones excluded) — the count to reason about, since it is what the average is built from |
| `numTotal` | metric | all sweeps acquired so far, including rejected ones |
| `numArtifacts` | metric | sweeps rejected as artifact so far |
| `corr` | metric | running onset-contrast correlation, 0..1 ([partition_corr](../+mabr/+metrics/partition_corr.m)) |
| `elapsedSeconds` | metric | wall-clock seconds since the run began streaming |
| `targetSweeps` | param | the scheduled repetition count — the hard ceiling |
| `corrThreshold` | param | the GUI's threshold field |
| `minSweeps` | param | sweeps required before the criterion may fire |
| `maxSweeps` | param | optional hard cap below `targetSweeps` |

Any extra field you add to `AdvanceParams` arrives in `ctx` too, so a criterion can carry its own knobs. Read only the fields you use.

**Criteria only run for blocked strategies.** An intermixed run pools sweeps from different conditions, so a correlation over it is meaningless, and stopping it early would truncate whichever stimuli happened to fall last in the sequence. `AcqController` therefore skips the criterion entirely when `Schedule.isIntermixed()` is true, and the GUI disables the control. Those runs always play to completion.

Three are supplied — the first two wired to the GUI dropdown, the third a copy-me stereotype:

- [num_sweeps](../+mabr/+stim/+advance/num_sweeps.m) — `ctx.numSweeps >= ctx.targetSweeps`.
- [corr_threshold](../+mabr/+stim/+advance/corr_threshold.m) — `ctx.corr >= ctx.corrThreshold` after `ctx.minSweeps`, or `ctx.numSweeps >= ctx.maxSweeps`.
- [custom_template](../+mabr/+stim/+advance/custom_template.m) — the full contract as comments, plus a worked body; start here.

A custom one, adding a wall-clock budget to the correlation criterion:

```matlab
function done = corr_or_timeout(ctx)
    hitCorr    = ctx.numSweeps >= ctx.minSweeps && ctx.corr >= ctx.corrThreshold;
    ranTooLong = ctx.elapsedSeconds >= ctx.maxSeconds;   % your own knob
    done = hitCorr || ranTooLong || ctx.numSweeps >= ctx.maxSweeps;
end
```

```matlab
c.AdvanceFcn    = @corr_or_timeout;
c.AdvanceParams = struct('maxSeconds',120,'maxSweeps',2048, ...
                         'targetSweeps',2048,'corrThreshold',0.5,'minSweeps',64);
```

Two rules. **Always include a hard cap** — a criterion that never fires runs until the scheduled repetitions are exhausted. And **keep it cheap and side-effect-free**: it runs 20 times a second on the GUI thread. If you need a metric the controller does not compute, add it to `live_tick_body` from a [+metrics](../+mabr/+metrics/) function rather than recomputing it inside the predicate.

**Selecting one from the GUI.** The Acquisition panel's **Advance** dropdown has a **Custom…** item: pick it, choose your function's `.m` file, and MABR puts its folder on the path and checks it against the contract with [mabr.stim.advance.validate](../+mabr/+stim/+advance/validate.m) before accepting it (a malformed one is refused there and then, not 20 times a second mid-run). The choice is remembered by file in a saved [configuration](Acquisition-App.md), so it re-resolves next session. Driving `AcqController.AdvanceFcn` directly (as above) skips the GUI entirely.

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

### A metric for the online analysis window

The [online analysis window](Viewing-Data.md#online-analysis) plots **one number per stimulus condition**. Its metrics are a separate, narrower contract, in [+metrics/+online](../+mabr/+metrics/+online/): one struct in, one number out.

```matlab
function v = my_metric(ctx)
v = max(abs(ctx.Mean))/rms(ctx.Baseline(:));   % peak, in units of baseline noise
end
```

`ctx` is built by [`mabr.metrics.online.context`](../+mabr/+metrics/+online/context.m), which is the authoritative field list. The ones you will use: `Sweeps` `[nSamples x nSweeps]` and their `Mean`, both windowed to the analysis window and in volts; `Time` in **milliseconds** re onset; `Baseline` (the pre-onset samples, empty once a run is finalized); `NumSweeps`/`NumTotal`/`NumArtifacts`/`ArtifactRate`; `Params` (the condition's informative parameters, e.g. `ctx.Params.Level`); and `Live`, true while the run producing it is still streaming.

Return **one** number, in whatever unit you want the axis to read. `NaN` means "not enough data yet" and is drawn as a gap.

Develop it at the command line, with no acquisition:

```matlab
ctx = mabr.metrics.online.sampleContext;
v   = my_metric(ctx)
```

Then pick it from the window's **Metric ▸ Custom function…**. It is run through [`mabr.metrics.online.validate`](../+mabr/+metrics/+online/validate.m) at selection time, so a malformed one is refused with a reason instead of throwing on every refresh. Copy [custom_template.m](../+mabr/+metrics/+online/custom_template.m) to start.

To add a metric to the shipped list instead, add an `entry(...)` line and a local function to [catalog.m](../+mabr/+metrics/+online/catalog.m) — and delegate the arithmetic to the pure functions in `+metrics` rather than reimplementing it, so the window and a saved `Block` cannot disagree.

## Before you commit

Run [the verification suite](Testing.md):

```matlab
>> run_all_verifications
```

If you touched [io](../+mabr/+data/io.m), `verify_data_roundtrip` is the test that protects the offline pipeline's file contract — treat a failure there as a breaking change, not a test to update.
