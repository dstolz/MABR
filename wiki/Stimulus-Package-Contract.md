# Stimulus Package Contract

MABR **does not generate or calibrate stimuli**. An external package supplies precomputed, calibrated waveforms; `mabr.stim.StimulusSet` wraps and validates them and is otherwise inert — a bank of waveforms and nothing more.

[**stimgen**](https://github.com/dstolz/stimgen) is the suggested package and ships as a submodule at `external/stimgen` — see [[Using stimgen]]. It satisfies this contract through `mabr.stim.fromStimgen`; the contract below is what MABR actually requires, and any other source that meets it is equally welcome.

## The shape

A plain **struct array**, where **each element is ONE presentation** of one stimulus — not a repeated train, no ISI padding, no timing channel.

```matlab
stim(i).signal        % [N x 1] required — calibrated waveform for a SINGLE presentation
stim(i).ID            % string  required — names the stimulus condition
```

Five optional fields are given meaning:

| Field | Type | Meaning |
| --- | --- | --- |
| `SampleRate` | scalar | Defaults to `Config.DACSampleRate` (192000). Must equal it. |
| `Repetitions` | scalar | Per-entry starting repetition count the GUI picks up |
| `Timing` | `[N x 1]` | Explicit timing channel; must match `signal` in length. Otherwise MABR synthesizes one unit pulse at each onset. |
| `alternatePolarity` | logical | Present this entry with alternating polarity: successive presentations are multiplied by `+1, -1, +1, …`. This **splits** the repetition count between the two polarities — it does not double it. See [[Presentation Strategies]]. |
| `informativeParams` | cellstr | The passthrough fields that *identify* this condition. Overrides the inference described below. |

**Every other field passes through untouched** into the block metadata and on into the saved `.abr` file, so the external package can add parameters without MABR changing. Numeric scalar extras are otherwise advertised in `informativeParams`, which is how the offline pipeline discovers them.

That inference suits a hand-built bank, whose only extras *are* its parameters. It misfires for a generator, which emits every knob it has: each name in `informativeParams` becomes a **grouping dimension** offline, so a stray `WindowDuration` splits one condition into several. A source that knows which parameters vary should declare the list instead — which is exactly what `fromStimgen` does, from stimgen's own record of which properties were vectorized.

Name a passthrough field `Frequency` (kHz) and `Level` (dB) to get filenames that match the offline pipeline's default regex — see [[Data Format]].

## Provenance

`StimulusSet` also carries a `Source` struct (`Kind` — `stimgen`/`file`/`demo` — plus `File`, `Calibration`, `Generated`) and `isCalibrated()`. Neither is part of the contract: no entry supplies them and nothing in acquisition reads them. They exist because a calibrated bank and the demo bank are indistinguishable once both are struct arrays, and that is a confusion worth making impossible. The GUI's bank label reads `12 stimuli · stimgen` and turns amber when uncalibrated; `mabr.data.io` writes `StimClass`, `VariantIndex`, `Calibrated`, and `CalibrationTime` into each `.abr` — deliberately **not** as `informativeParams`, for the reason above.

## Validation

`mabr.stim.StimulusSet.validate` normalizes each entry: `signal` is cast to `single` and forced to a column, `ID` to `char`. Errors you may see:

| Identifier | Cause |
| --- | --- |
| `mabr:stim:StimulusSet:notStruct` | Not a struct array |
| `mabr:stim:StimulusSet:noSignal` / `:noID` | Missing or empty required field |
| `mabr:stim:StimulusSet:timingLength` | `Timing` length ≠ `signal` length |
| `mabr:stim:StimulusSet:badAltPolarity` | `alternatePolarity` is not a logical scalar |
| `mabr:stim:StimulusSet:mixedRates` | Entries disagree on `SampleRate` — one run is rendered against one clock |
| `mabr:stim:StimulusSet:sampleRate` | Rate ≠ `Config.DACSampleRate`; the ring buffer and sweep windowing assume it |

## Loading

From the GUI: **Load bank…** (or **Design…** for stimgen). Programmatically:

```matlab
set = mabr.stim.StimulusSet(stimStructArray);       % from a struct array
set = mabr.stim.StimulusSet.fromFile('bank.mat');   % from a .mat file
set = mabr.stim.StimulusSet.fromFile('bank.spl');   % a stimgen bank -> fromStimgen
set = mabr.stim.fromStimgen(stimgen.Tone);          % stimgen objects directly
```

`fromFile` dispatches on the extension: `.spl` goes to `mabr.stim.fromStimgen`, anything else is read as a `.mat`. From a `.mat` it accepts either a saved `StimulusSet` object or any variable that is a struct array with `signal` and `ID` fields, and throws `mabr:stim:StimulusSet:noStimuli` if it finds neither.

## Inspecting a bank

```matlab
set.numStimuli        % entry count
set.IDs               % cellstr of IDs
set.signal(i)         % waveform for entry i
set.timing(i)         % explicit timing channel, or []
set.duration(i)       % seconds, full signal length
set.maxDuration       % longest single presentation — the worst case for ISI overlap
set.meta(i)           % metadata struct handed to Block and the .abr writer
set.defaultRepetitions
```

`duration` is the full signal length, not a trailing-zero-trimmed estimate, because the whole waveform is written into the play matrix at each onset and is therefore what can collide with the next one.

## Demo bank

`mabr.stim.demoStimuli` builds a small Frequency × Level grid of gated tone pips — **testing and demos only**. It exists so the engine, GUI, and verification scripts run end to end with no hardware and no external dependency.

```matlab
set = mabr.stim.demoStimuli(mabr.Config, ...
        'Frequencies',[8 16], ...   % kHz
        'Levels',[30 60], ...       % dB
        'PipDuration',0.005, ...    % s
        'Repetitions',256);
```
