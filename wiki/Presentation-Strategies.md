# Presentation Strategies

`mabr.stim.Schedule` turns a [[Stimulus Package Contract|StimulusSet]] plus three GUI-chosen settings — **ISI** (fixed, or drawn per presentation from a range), **Repetitions**, **Strategy** — into an ordered list of *runs*, and renders each run into the two-channel play matrix the engine streams.

MABR, not the stimulus package, owns these decisions.

## The five strategies

| Strategy | Runs | Ordering |
| --- | --- | --- |
| `blocked` | one per stimulus | Entries in array order; each run is that entry's full repetition train |
| `shuffled-blocks` | one per stimulus | As blocked, but the order of the runs is shuffled |
| `interleaved` | **one** | Cycles A B C A B C …; an entry drops out of later cycles once it hits its repetition count |
| `shuffled-cycles` | **one** | As interleaved, but each cycle's order is shuffled independently |
| `shuffled` | **one** | The whole multiset of presentations shuffled uniformly |

## "Shuffled", not "random"

Every strategy is a **permutation of a fixed multiset** — never probabilistic sampling. Each entry is presented exactly its repetition count in all five. That is precisely why the names say *shuffled*.

Shuffling uses a private `RandStream`, so building a plan never perturbs the global `rng`. Set `Schedule.Seed` to make a plan exactly reproducible; leave it `[]` for a nondeterministic shuffle.

## Fixed and randomized ISI

`ISIMode` picks which of two settings decides the spacing between successive onsets:

| `ISIMode` | Setting used | Spacing |
| --- | --- | --- |
| `'fixed'` (default) | `ISI` (s) | Every interval identical; onsets land on a strict grid |
| `'random'` | `ISIRange` = `[min max]` (s) | Each interval drawn independently and uniformly from the range |

Randomizing decorrelates the presentation rate from line noise and from any periodicity in the response itself, which a strict grid can otherwise average up alongside the signal. In the GUI it is the **Random** checkbox beside the ISI/Rate fields, with the two bounds in **milliseconds**; checking it greys out ISI/Rate, since with an interval drawn per presentation no single number describes the spacing.

The draw happens in `renderSpec`, once per run, from the same private `RandStream` the shuffles use — so it never perturbs the global `rng`, and `Schedule.Seed` fixes a plan's *timing* as well as its order.

Two derived properties say which number to reason with:

- **`MinISI`** — the shortest interval that can occur (`ISIRange(1)` under `'random'`, else `ISI`). This is what `overlaps()` judges against and what the GUI's overlap warning uses: one short draw is enough to collide, so the bottom of the range is what has to clear the stimulus duration — and the sweep window.
- **`MeanISI`** — `mean(ISIRange)` under `'random'`, else `ISI`. `summary().duration` is built on it, which makes a randomized plan's duration an *expectation* rather than a promise.

Nothing downstream needs to know. The timing channel still carries one pulse per onset, so sweep extraction, the sweep window, and every metric are indifferent to how evenly the onsets were spaced; the actual onsets are recorded in `ADC.SweepOnsets` of each `.abr`, so the realized intervals are recoverable from the saved file.

## Intermixed runs

The last three strategies mix different stimuli inside one continuous acquisition run (`Schedule.isIntermixed` is true). Two consequences:

1. **No online early stop.** A run pooling multiple conditions cannot be stopped early for one stimulus without disturbing the balance of the others, so correlation-threshold advance is unavailable and the run always plays to completion. The GUI greys the control out and forces *All Repetitions*.
2. **De-interleaving at save time.** `renderSpec` emits `StimulusIndex` — which stimulus fired at each onset — and the controller pairs recorded onsets against `Schedule.runSequence(r)` so each ID still lands in its own `.abr` file.

`interleaved` and `shuffled-cycles` walk cycles of the still-*owed* stimuli: an entry leaves the cycle once fully scheduled, so unequal repetition counts stay spread out instead of clumping at the end.

## Rendering a run

`renderSpec(r)` builds the play matrix:

- Onsets are placed by accumulating one interval per presentation: `round(Fs*ISI)` every time under `ISIMode = 'fixed'`, or a fresh uniform draw from `ISIRange` under `'random'` (see [[#Fixed and randomized ISI]]).
- Each waveform is **summed** into the signal channel at its onset. Overlapping presentations are summed, not clipped; if the longest stimulus exceeds `MinISI`, a red log line records it and the GUI warns up front.
- The **timing channel is synthesized by MABR** — one unit pulse per onset, unless the entry supplied an explicit `Timing`, in which case it is `max`-merged in. Sweep extraction depends on this channel.
- The run is bracketed by `SilencePad` (default 0.25 s) of silence for device settling and response tail, then zero-padded to a whole number of frames.

The returned spec carries `PlayMatrix`, `SampleRate`, `ExpectedOnsets`, `StimulusIndex`, `Polarity`, `PlayerChannels`, `RecorderChannels`, and `Meta`.

## Alternating polarity

An entry flagged `alternatePolarity` (see [[Stimulus Package Contract]]) has its successive presentations multiplied by `+1, -1, +1, …`, so half of them are inverted. This **splits** the entry's repetition count between the two polarities — it does not add presentations, and a run's total length is unchanged.

Polarity is assigned per presentation and travels with it through shuffling: under `shuffled-cycles` or `shuffled`, the inverted presentations land in shuffled positions rather than in a fixed alternation. `Schedule.runPolarity(r)` returns the sign at each onset of run `r`, and `renderSpec` reports the same vector as the spec's `Polarity`. Entries without the flag are always `+1`, so a bank can mix flagged and unflagged stimuli in one run.

### Length check

Before allocating anything, `renderSpec` asserts the padded run fits `Config.maxInputBufferLength`:

```
mabr:stim:Schedule:tooLong
  Run 1 needs 78643200 samples (409.6 s) but the ring buffer holds 67108864 (349.5 s).
  Reduce repetitions, shorten the ISI, or use a blocked strategy so each run covers one stimulus.
```

The check comes first deliberately — an over-ambitious plan is many gigabytes, and running out of memory would mask the real problem behind a `MATLAB:nomem`.

This is the main practical constraint on intermixed strategies: they render the *entire* design as one run, so total presentations × ISI must stay under ~5.8 minutes at 192 kHz. Blocked strategies only need one condition to fit.

## Programmatic use

```matlab
sch = mabr.stim.Schedule(stimulusSet, mabr.Config);
sch.ISI         = 0.0474;
sch.Strategy    = 'shuffled-cycles';
sch.Repetitions(:) = 512;
sch.build();                    % rebuild after changing Repetitions or Strategy

% ...or draw each interval uniformly from 40-55 ms instead:
sch.ISIRange = [0.040 0.055];
sch.ISIMode  = 'random';        % ISI is left alone and resumes if set back to 'fixed'

s = sch.summary()               % numRuns, presentations, estimated duration, intermixed
sch.overlaps()                  % true if the longest stimulus exceeds MinISI

r    = sch.current();
spec = sch.renderSpec(r);       % -> engine.prep(spec)
% ...acquire...
sch.recordRun(r, counts);
r = sch.advance();              % [] when the plan is complete
```

`build()` rebuilds the run list and resets progress; `reset()` alone rewinds without rebuilding.

## Advance criteria

Implemented in `+mabr/+stim/+advance/` as pure predicates over a context struct:

**`num_sweeps(ctx)`** — `ctx.numSweeps >= ctx.targetSweeps`.

**`corr_threshold(ctx)`** — true once the running onset-contrast correlation (`mabr.metrics.partition_corr`) reaches `ctx.corrThreshold` (default 0.5) after `ctx.minSweeps` (default 32), or when an optional `ctx.maxSweeps` cap is hit.

Because the worker polls commands every frame, honoring `corr_threshold` lets a block stop the moment a response is detected — the capability the legacy design explicitly documented it could not provide. (The legacy `abr_adv_corr_thr.m` was an empty stub.)
