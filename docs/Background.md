# Ongoing Backgrounds

Presenting stimuli **embedded in a sound that keeps playing**: a tone in noise, a silent gap in noise, 10 Hz amplitude modulation of a steady band-passed noise, frequency modulation of a steady tone.

Related: [The Acquisition App](Acquisition-App.md) · [Data Files](Data-Files.md) · [Test Mode](Test-Mode.md) · [Extending MABR](Extending.md)

## What it is

A run can play on a background that is continuous from before its first presentation to after its last. Each presentation then does one of two things:

| | Example | What is presented |
|---|---|---|
| **adds** to the background | tone in noise, clicks in noise | the stimulus, summed onto the background |
| **modulates** the background | AM, a gap, FM of a tone | nothing new: the background's own gain or phase changes for the stimulus's duration |

The sweep is time-locked to the start of the stimulus either way: the onset of the tone, or the onset of the modulation.

The background is **designed and calibrated in stimgen**, together with the stimuli (the `Background` settings of a stimulus, and the *Background AM*, *Background Gap* and *Background FM* stimulus types). MABR plays it. See `documentation/stimgen_Background.md` in the stimgen submodule.

## What a run plays

```
y = env × G × B(θ)  +  the stimuli
```

- `B` — the background. Noise is one calibrated, seeded segment (10 s by default) repeated seamlessly; a tone is computed directly.
- `env` — a fade in at the run's first sample and a fade out at its last (20 ms each).
- `G`, `θ` — what a modulating presentation does to the background: a gain envelope (AM, a gap), or a phase deviation of a tone (FM). 1 and 0 outside a presentation.
- the stimuli — the presentations that are added, as in any run.

The timing pulse is unchanged, so sweep extraction, the alignment check and every metric work as they always have.

### One background per run

A background runs unbroken through a run, so **every stimulus of a run must share it**.

- A series made by varying the **stimulus** — the tone's level, for a signal-to-noise series; AM depth; gap duration — shares one background, and can be interleaved or shuffled.
- A series made by varying the **background** — its level, or the frequency of an FM carrier — is several backgrounds, and needs a **Conventional** strategy (one stimulus per run). So does a bank that mixes stimuli in a background with stimuli in quiet.

A plan that would mix backgrounds within a run is refused, and the plan line in the Presentation panel says why.

### When the background is on

- It fades in at the start of each run and plays for the **lead-in** before the first presentation — time for the ear to settle on it. Set it in the Presentation panel's **Background** row (default 1000 ms).
- It is continuous through the run.
- It fades out at the end of the run. **Between runs there is silence.** Under an interleaved or shuffled strategy the whole session is one run, so the background is continuous throughout.
- A run that ends early — Advance, Abort, or a correlation early-stop — fades the background out rather than cutting it.
- **Pause** fades it out. **Resume** plays the lead-in again before continuing, so the presentations after a pause follow a steady background as those before it did. Nothing is recorded during either.

The lead-in in force is never shorter than the fade plus the baseline before the first sweep.

### The same noise recurs

The noise is a loop, so it repeats with its period (10 s by default). Each run enters the loop at a different, recorded place. On a **fixed ISI** the presentations fall on a limited number of places in the loop — few of them when the ISI divides the loop evenly, and the log says so. A randomized ISI removes that.

## Setting one up

1. **Design…** in the Stimulus panel (the stimgen designer).
2. For a stimulus *in* a background: pick the stimulus type (Tone, Click Train, …), then in its **Background** group choose *Noise* or *Tone* and set its level and band or frequency. The stimulus's own Sound Level is separate.
3. For a modulation *of* the background: pick **Background AM**, **Background Gap** or **Background FM**. Their Sound Level is the level of the steady background.
4. **Play** in the designer auditions the stimulus in a short stretch of its background.
5. **Adopt bank**. The Presentation panel's **Background** row now names the background; set the lead-in there.

The main window reports the rest:

- the **Background** row says what the bank's stimuli are embedded in (or that they are presented in quiet), with the full list in its tooltip;
- the **Stimulus Viewer** draws an embedded stimulus in its background;
- the live view's *Show stimulus* draws a modulation as its envelope (or frequency deviation), since a modulating stimulus has no waveform of its own.

## Levels and clipping

With a calibration, the background and the stimuli are each at their own dB SPL, as stimgen calibrated them.

Without one, MABR sets an **entirely uncalibrated** bank on one relative scale — equal levels mean equal rms, so a signal-to-noise ratio is the difference of the two levels — and attenuates the whole mix by one common factor if it would otherwise pass the converter's full scale. The bank is still marked uncalibrated: the spacing is right, the absolute level is not.

The background at its largest gain plus the largest added stimulus is the most a run can reach. If that exceeds full scale, the log says in red that the output **will clip**. It is a warning, not a refusal: lower the levels.

## What is recorded

- **`ABR_Data.Background`** in every `.abr`, always: the background's type, level, band or frequency, loop length and seed, the lead-in and fade the run played, where in the loop the run began, and whether the level is calibrated. `Type` is `'none'` for a run in quiet.
- **The file name** of a recording made on a background gains a token: `SUBJ-ID-1_Frequency-8kHz_Level-30dB_Background-50dB_<stamp>.abr`. It no longer matches the strict frequency/level pattern, so code that reads names skips these files rather than pooling them with the same stimulus recorded in quiet.
- **The stimulus parameters** (`ABR_Data.SIG`) of a stimulus in a background carry the background's level and band or frequency as parameters of their own, so the `mabr.analysis` classes key a tone in noise and the same tone in quiet as different conditions. `SIG.Embedding` says `add` or `modulate`.
- The **stimulation log** of a stimulation-only run carries the same record (`Presentation.Background`).

The noise itself is not stored. It is regenerated from the settings and seed in the record.

## Checking it

[Test Mode](Test-Mode.md) checks a run on a background as it checks any other: the onsets are where the plan put them, and the recorded samples are what the plan rendered — here the stimulus *and* the background under it, with the modulation applied.

On a rig, the fade-out at a stop and the lead-in after a pause are played but never recorded, so no check sees them. Listen to them, or put a scope on the output, once.

---

## Developer notes

The bank contract is three reserved fields on an entry — `Background` (the key of one of the set's `Backgrounds`), `BackgroundGain`, `BackgroundPhase` — and a struct array of backgrounds as `mabr.stim.StimulusSet`'s fourth argument (`Kind` `'loop'` with a `signal`, or `'tone'` with `Frequency` and `Amplitude`). An entry that only modulates carries a `signal` of zeros of the event's length, so the timing pulse, `duration` and overlap arithmetic are untouched. See [Extending MABR](Extending.md#an-ongoing-background).

`mabr.stim.PlayPlan` renders the background term as a pure function of the absolute sample index, so a plan stays random-access and the same however it is sliced into frames — exactly on a loop, to the rounding of `sin()` on a tone. `backgroundTail` and `backgroundLead` render that term alone for the worker's fade-out and pre-roll. `mabr.stim.Schedule` owns the lead-in and fade (`BackgroundLeadIn`, `BackgroundRamp`, `leadPad`, `trailPad`), refuses a run with more than one background (`runBackground`), and records what was played (`spec.Background`, from `mabr.stim.backgroundRecord`).

Files: [+mabr/+stim/PlayPlan.m](../+mabr/+stim/PlayPlan.m) · [Schedule.m](../+mabr/+stim/Schedule.m) · [StimulusSet.m](../+mabr/+stim/StimulusSet.m) · [fromStimgen.m](../+mabr/+stim/fromStimgen.m) · [backgroundRecord.m](../+mabr/+stim/backgroundRecord.m) · [+mabr/+acq/worker_loop.m](../+mabr/+acq/worker_loop.m) · [tests/verify_background.m](../tests/verify_background.m)
