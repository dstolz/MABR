# Using stimgen

[stimgen](https://github.com/dstolz/stimgen) builds parameterized acoustic stimuli and calibrates the rig that plays them. It ships with MABR as a git submodule at `external/stimgen` and is the **suggested** source of stimuli — but an optional one: MABR launches, acquires, and passes its verification suite without it, and the [[Stimulus Package Contract]] remains a plain struct array that any source can satisfy.

```bash
git clone --recurse-submodules https://github.com/dstolz/MABR
# already cloned?
git submodule update --init
```

`MABR.m` picks it up with no extra step — `genpath` skips `+package` folders, so `external/stimgen` is added as the root and `+stimgen` resolves as a package, which is exactly what stimgen's own install instructions ask for. Check with `mabr.stim.stimgenAvailable`; the **Design…** button and **Settings ▸ Calibration…** grey out with an explanatory tooltip when it returns false.

stimgen requires MATLAB R2021a, below MABR's own R2021b floor, so there is **no version gate** — presence is the only thing checked, and nothing was added to `mabr.Config.RequiredToolboxes`.

## Building a bank

**Design…** in the Stimulus panel opens `stimgen.StimPlayer`. Assign a vector to any parameter and stimgen expands it into *variants*:

```matlab
t = stimgen.Tone;
t.Frequency  = [8000 16000];    % Hz
t.SoundLevel = [30 60];         % dB SPL
% -> 4 variants (Cartesian), i.e. 4 MABR stimuli
```

The designer stays **open** after you press **Adopt bank** — the button toggles between the two — so you can adjust a parameter and re-adopt without reopening anything. `stimgen.StimPlayer` keeps its figure handle private, so there is nothing MABR could `uiwait` on even if a modal dialog were wanted; the non-modal shape matches how the [[Viewing Data|acquisition viewers]] already behave.

Saved banks are `.spl` files. **Load bank…** reads them through the same path (`mabr.stim.StimulusSet.fromFile` → `mabr.stim.fromStimgen`).

## How the conversion works

`mabr.stim.fromStimgen` accepts a `.spl` path, a live `StimPlayer`, a `StimPlay`, or a bare `StimType`, and flattens three levels — `StimPlayer.StimPlayObjs` → `StimPlay.StimObj` → variants — into one entry per variant.

**One variant is one presentation.** That is already MABR's unit, so nothing is reinterpreted.

**Regenerated, not resampled.** `StimType.Fs` defaults to 97656.25 Hz (a TDT rate) and a saved bank carries whatever it was authored at, while MABR requires 192 kHz. Since stimgen synthesizes from parameters, the importer sets `Fs = Config.DACSampleRate` on a `copy()` and calls `update_signal()` — every waveform is built natively at the DAC rate. This is why it imports *parameters* and never a bank's cached `Signal`.

**Two renamings**, both because the offline pipeline reads by name and unit ([[Data Format]]):

| stimgen | MABR |
| --- | --- |
| `SoundLevel` (dB) | `Level` (dB) |
| `Frequency` (Hz) | `Frequency` (kHz) |

Every other varying property passes through under its own name, and the set of them is declared as `informativeParams` rather than inferred — see [[Stimulus Package Contract]].

**What is dropped.** `StimPlay.ISI`, `StimPlayer.ISI`, `SelectionType`, and `StimOrder` are ignored: MABR owns presentation and `mabr.stim.Schedule` decides it (see [[Presentation Strategies]]). stimgen's ISI is a `[min max]` jitter range that MABR's scalar has no equivalent for, and collapsing it would misreport the bank. Only `Reps` survives, as the starting repetition count.

## Calibration

**Settings ▸ Calibration…** opens stimgen's own calibration GUI over `mabr.stim.CalibrationAdapter`, which implements stimgen's two-method `HwAdapter` contract against MABR's audio path: your ASIO **Device**, output on **Player ch.** signal, input on **Microphone**, at 192 kHz.

Using stimgen's built-in `WindowsSoundCardAdapter` instead would measure through whatever Windows offers by default — a different device, rate, and output than the experiment uses, which is the one thing a calibration must not be.

Set the **Microphone** channel in **Settings ▸ Audio Device (ASIO)…**. It is deliberately separate from **Recorder ch.**: acquisition records an electrode, calibration records a microphone. Same device, different patchings.

Save a `.esgc`, load it onto your stimuli in the designer, and rebuild the bank.

> ### Levels do nothing without a calibration
>
> dB SPL becomes a voltage *through* the calibration. With none loaded, `apply_calibration` is a no-op and every stimulus is generated at the same amplitude — a bank asking for 30, 60 and 90 dB is three **identical** sounds. MABR warns on adopt and shows the bank label in amber, but does not block it (the bank is still useful for testing the signal chain). Never collect data with one.

### The device is not free just because nothing is running

The acquisition worker opens its `audioPlayerRecorder` on the first block and holds it until the worker is killed — that is what keeps block-to-block latency down. An ASIO device has exactly one owner, so opening calibration asks the worker to hand it back (`mabr.acq.Cmd.Release` / `Engine.releaseDevice`). It reopens automatically on the next Start. Without this, the first calibration after any acquisition would fail and the only remedy would be restarting MABR.

Calibration refuses in **Testing (loopback)** mode — there is no device, and the "measurement" would be the excitation signal fed back to itself — and while a schedule is running.

## Known upstream rough edges

Both are worked around in `mabr.stim.fromStimgen`, not fixed here, since stimgen is a submodule:

- **`stimgen.StimCalibration.loadobj` throws** (it assigns the read-only `Engine.MicSensitivity`), and `StimType.fromStruct` calls it unconditionally — so a `.spl` carrying a calibration would be unloadable. `readBank` restores the stimulus without its calibration and reattaches separately in a `try`: a bank whose calibration cannot be revived still imports, and honestly reports itself uncalibrated.
- **`StimType.fromStruct` does not restore `SoundLevel`, `Duration`, `WindowDuration`, or `WindowFcn`** (stimgen's own `load_bank` assigns them itself). `readBank` does the same, or banks would silently return at class defaults — 60 dB, 100 ms.

## Verifying

`tests/verify_stimgen_import.m`, part of the [[Verification and Testing|suite]] and needing no hardware. It **skips and passes** when the submodule is absent.

Its sharpest check is that each generated waveform's dominant frequency matches the `Frequency` its own metadata claims. stimgen's `VariantReselectOnUpdate` defaults true, which makes every parameter read *outside* an update cycle silently advance to the next variant — so metadata read back after selecting a variant can describe a different one than the waveform just generated, and an 8 kHz tone would be saved labelled 16 kHz. `fromStimgen` forces the flag false; the FFT check is what proves it stayed forced.

## See also

- [[Stimulus Package Contract]] — what MABR actually requires, stimgen or not
- [[Presentation Strategies]] — what MABR decides instead of the stimulus package
- [[Running a Session]] — the Stimulus panel and Settings menu in context
