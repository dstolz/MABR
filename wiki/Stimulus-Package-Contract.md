# Stimulus Package Contract

MABR **does not generate or calibrate stimuli**. An external package supplies precomputed, calibrated waveforms; `mabr.stim.StimulusSet` wraps and validates them and is otherwise inert — a bank of waveforms and nothing more.

## The shape

A plain **struct array**, where **each element is ONE presentation** of one stimulus — not a repeated train, no ISI padding, no timing channel.

```matlab
stim(i).signal        % [N x 1] required — calibrated waveform for a SINGLE presentation
stim(i).ID            % string  required — names the stimulus condition
```

Three optional fields are given meaning:

| Field | Type | Meaning |
| --- | --- | --- |
| `SampleRate` | scalar | Defaults to `Config.DACSampleRate` (192000). Must equal it. |
| `Repetitions` | scalar | Per-entry starting repetition count the GUI picks up |
| `Timing` | `[N x 1]` | Explicit timing channel; must match `signal` in length. Otherwise MABR synthesizes one unit pulse at each onset. |

**Every other field passes through untouched** into the block metadata and on into the saved `.abr` file, so the external package can add parameters without MABR changing. Numeric scalar extras are additionally advertised in `informativeParams`, which is how the offline pipeline discovers them.

Name a passthrough field `Frequency` (kHz) and `Level` (dB) to get filenames that match the offline pipeline's default regex — see [[Data Format]].

## Validation

`mabr.stim.StimulusSet.validate` normalizes each entry: `signal` is cast to `single` and forced to a column, `ID` to `char`. Errors you may see:

| Identifier | Cause |
| --- | --- |
| `mabr:stim:StimulusSet:notStruct` | Not a struct array |
| `mabr:stim:StimulusSet:noSignal` / `:noID` | Missing or empty required field |
| `mabr:stim:StimulusSet:timingLength` | `Timing` length ≠ `signal` length |
| `mabr:stim:StimulusSet:mixedRates` | Entries disagree on `SampleRate` — one run is rendered against one clock |
| `mabr:stim:StimulusSet:sampleRate` | Rate ≠ `Config.DACSampleRate`; the ring buffer and sweep windowing assume it |

## Loading

From the GUI: **Load .mat…**. Programmatically:

```matlab
set = mabr.stim.StimulusSet(stimStructArray);       % from a struct array
set = mabr.stim.StimulusSet.fromFile('bank.mat');   % from a .mat file
```

`fromFile` accepts either a saved `StimulusSet` object or any variable in the file that is a struct array with `signal` and `ID` fields. It throws `mabr:stim:StimulusSet:noStimuli` if it finds neither.

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
