# Using stimgen

[stimgen](https://github.com/dstolz/stimgen) builds parameterized acoustic stimuli and calibrates the rig that plays them. It ships with MABR as a git submodule at `external/stimgen` and is the **suggested** source of stimuli — but an optional one: MABR launches, acquires, and passes its verification suite without it, and the [[Stimulus Package Contract]] remains a plain struct array that any source can satisfy.

```bash
git clone --recurse-submodules https://github.com/dstolz/MABR
# already cloned?
git submodule update --init
```

`MABR.m` picks it up with no extra step — `genpath` skips `+package` folders, so `external/stimgen` is added as the root and `+stimgen` resolves as a package, which is exactly what stimgen's own install instructions ask for. Check with `mabr.stim.stimgenAvailable`; the **Design…** button and **Settings ▸ Calibration…** grey out with an explanatory tooltip when it returns false.

stimgen requires MATLAB R2021a, below MABR's own R2021b floor, so there is **no version gate** — presence is the only thing checked, and nothing was added to `mabr.Config.RequiredToolboxes`.

> 📖 stimgen has its own [documentation wiki](https://github.com/dstolz/stimgen/wiki), split into a [User Guide](https://github.com/dstolz/stimgen/wiki/Getting-Started) and a [Developer Guide](https://github.com/dstolz/stimgen/wiki/Developer-Guide). This page covers only the **seam** — what MABR does with stimgen and what it deliberately does not.

## Building a bank

**Design…** in the Stimulus panel opens `stimgen.StimPlayer`. Assign a vector to any parameter and stimgen expands it into *variants*:

```matlab
t = stimgen.Tone;
t.Frequency  = [8000 16000];    % Hz
t.SoundLevel = [30 60];         % dB SPL
% -> 4 variants (Cartesian), i.e. 4 MABR stimuli
```

The designer stays **open** after you press **Adopt bank** — the button toggles between the two — so you can adjust a parameter and re-adopt without reopening anything. `stimgen.StimPlayer` keeps its figure handle private, so there is nothing MABR could `uiwait` on even if a modal dialog were wanted; the non-modal shape matches how the [[acquisition viewers|Running a Session]] already behave.

### MABR hides the designer's session controls

On open, `App.hideDesignerSessionControls` calls stimgen's own `set_control_visibility(All=false)`, which collapses the designer's **Reps**, **ISI**, sample-rate, **Shuffle/Serial**, preview-output and **Run/Pause** widgets out of its layout.

Every one of those duplicates a setting MABR owns — and the duplicates are not merely redundant, they are **inert**:

- `fromStimgen` drops ISI and `SelectionType` outright;
- the rate is `mabr.Config.DACSampleRate` regardless of what the designer shows;
- the designer's **Run** would stream through stimgen's own speaker preview, not the rig the acquisition worker holds open.

The per-stimulus **Play** / **Play All** preview buttons are *not* hidden and stay, which is right: auditioning a stimulus is the designer's job. The whole thing is guarded on `ismethod` rather than assumed, since a rig may have the submodule checked out at an older commit — an unhidden control is a worse designer, not a broken one.

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

**What is dropped.** `StimPlay.ISI`, `StimPlayer.ISI`, `SelectionType`, and `StimOrder` are ignored: MABR owns presentation and `mabr.stim.Schedule` decides it (see [[Presentation Strategies]]). MABR does now have somewhere to put a `[min max]` jitter range — `ISIMode = 'random'` with `ISIRange` — but the timing is the operator's setting for the session in front of them, and loading a bank must not silently retime a schedule already configured around it.

**`Reps` survives — unless the host hid the field.** `fromStimgen`'s `repsHidden` reads a live player's `ControlVisibility.Reps`. A hidden control means the number is `StimPlay`'s class default of 20 rather than anyone's choice, and **20 sweeps is not an ABR** — so it imports as *no opinion* and `mabr.stim.Schedule.startingRepetitions` supplies 512 instead. A `.spl` read from disk carries no such tell and is taken at its word.

Since MABR hides that very control (above), a bank adopted straight from the designer normally arrives with no repetition opinion at all, which is the intended outcome.

## Calibration

**Settings ▸ Calibration…** opens stimgen's own calibration GUI over [[mabr.stim.CalibrationAdapter|mabr.stim.CalibrationAdapter-Class-Reference]], which implements stimgen's two-method `HwAdapter` contract against MABR's audio path: your ASIO **Device**, output on **Player ch.** signal, input on **Microphone**, at 192 kHz.

Using stimgen's built-in `WindowsSoundCardAdapter` instead would measure through whatever Windows offers by default — a different device, rate, and output than the experiment uses, which is the one thing a calibration must not be.

Set the **Microphone** channel in **Settings ▸ Audio Device (ASIO)…**. It is deliberately separate from **Recorder ch.**: acquisition records an electrode, calibration records a microphone. Same device, different patchings.

Save a `.esgc`, load it onto your stimuli in the designer, and rebuild the bank. stimgen's [Calibrating Your Rig](https://github.com/dstolz/stimgen/wiki/Calibrating-Your-Rig) is the step-by-step.

> ### Without a calibration, levels are relative — not dB SPL
>
> dB SPL becomes a voltage *through* the calibration. With none loaded, `apply_calibration` is a no-op, so `SoundLevel` never reaches the amplitude and a bank asking for 30, 60 and 90 dB would leave stimgen as three **identical** sounds.
>
> `fromStimgen` rescales an entirely uncalibrated bank **relative to its own loudest entry** instead: the top level keeps the amplitude stimgen normalized it to, and every lower level is attenuated by `10^(ΔdB/20)`. The gain applied is recorded per entry as `LevelScale`. So the *spacing* is right — a growth function still grows, a threshold still falls somewhere — while the absolute axis is arbitrary. Since the reference is the top of the bank, this only ever attenuates; no bank gains a clipping risk it did not already have.
>
> MABR says so on adopt and shows the bank label in amber, but does not block it. **Do not report absolute thresholds from one.**
>
> A **partly** calibrated bank is left alone — there is no common reference to be relative to — and the warning says that instead.

### The device is not free just because nothing is running

The acquisition worker opens its `audioPlayerRecorder` on the first block and holds it until the worker is killed — that is what keeps block-to-block latency down. An ASIO device has exactly one owner, so opening calibration asks the worker to hand it back ([[mabr.acq.Cmd|mabr.acq.Cmd-Class-Reference]]`.Release` / `Engine.releaseDevice`). It reopens automatically on the next Start. Without this, the first calibration after any acquisition would fail and the only remedy would be restarting MABR.

Calibration refuses in **Testing (loopback)** mode — there is no device, and the "measurement" would be the excitation signal fed back to itself — and while a schedule is running.

### A filter calibration measured at another rate is refused

The current submodule pin adds an assertion to stimgen's `apply_calibration`: a **filter-type** calibration must be applied at the sample rate its FIR was designed at. `fromStimgen` forces `mabr.Config.DACSampleRate`, so a bank whose filter calibration was measured at some other rate cannot import.

MABR translates that refusal into `mabr:stim:fromStimgen:calibrationRate`, with the two things a MABR user can actually do about it:

- recalibrate through **Settings ▸ Calibration…**, which measures at the DAC rate; or
- redesign the filter with `design_filter(..., SampleRate=192000)`.

The tone and click LUTs are in Hz and volts and need no re-measuring — only the FIR equalization is rate-specific.

### Spot-checking a stimulus

stimgen now ships `stimgen.SpotCheck`: play one stimulus through the rig, record it, and compare what came back with what was asked for. It answers a question a calibration cannot — a calibration maps table points, a spot check measures a whole waveform.

It is not wired into a MABR menu, but it takes the same adapter, so it works against this rig directly:

```matlab
adapter = mabr.stim.CalibrationAdapter(app.Audio, app.Config, app.Controller);
sc = stimgen.SpotCheck(adapter, Stimulus = myTone);
```

The same device rules apply as for calibration: not in Testing mode, and not while a schedule is running. See [Spot-Checking a Stimulus](https://github.com/dstolz/stimgen/wiki/Spot-Checking-a-Stimulus).

## Logging: one session, one log

stimgen ships its own logger — console plus a daily file under `tempdir` — which left a MABR session writing **two log files describing one experiment**.

stimgen's `LogSink` seam exists for exactly this. `mabr.ui.App` installs a [[mabr.log.StimgenLogSink|mabr.log.StimgenLogSink-Class-Reference]] at startup (via `stimgen.util.logSink`) whenever the submodule is present, after which every `stimgen.util.vprintf` call lands in `mabr.log.vprintf` — same console, same `.error_logs/` file — and stimgen writes nothing of its own.

Verbosity stays one setting with no work at all: both packages gate on the same global `GVerbosity`, so a message suppressed for one logger is suppressed for the other.

## Known upstream rough edges

Both are worked around in `mabr.stim.fromStimgen` rather than fixed here, since stimgen is a submodule:

- **`stimgen.StimCalibration.loadobj` used to throw** — it assigned the read-only `Engine.MicSensitivity` — and `StimType.fromStruct` calls it unconditionally, so a `.spl` carrying a calibration was unloadable. **This is fixed at the current pin** (it restores through `Engine.restore` now). `readBank` still restores the stimulus *without* its calibration and reattaches separately in a `try`, and the split is deliberately kept: the isolation, not that one bug, is the point. On any `loadobj` failure — an older submodule checkout included — a bank whose calibration cannot be revived still imports, and honestly reports itself uncalibrated.
- **`StimType.fromStruct` does not restore `SoundLevel`, `Duration`, `WindowDuration`, or `WindowFcn`** (stimgen's own `load_bank` assigns them itself). `readBank` does the same, or banks would silently return at class defaults — 60 dB, 100 ms.

## Verifying

`tests/verify_stimgen_import.m`, part of the [[suite|Verification and Testing]] and needing no hardware. It **skips and passes** when the submodule is absent — a suite must not fail over an optional dependency nobody fetched.

Two checks are worth knowing about:

- **Each generated waveform's dominant frequency must match the `Frequency` its own metadata claims.** stimgen's `VariantReselectOnUpdate` defaults true, which makes every parameter read *outside* an update cycle silently advance to the next variant — so metadata read back after selecting a variant can describe a different one than the waveform just generated, and an 8 kHz tone would be saved labelled 16 kHz. The signal is always right; it is the *description* that drifts. `fromStimgen` forces the flag false, and the FFT check is what proves it stayed forced.
- **A 30 dB and a 60 dB entry from an uncalibrated bank must come back exactly 30 dB apart**, which is what pins the `relativeLevels` rescaling described above.

## See also

- [[Stimulus Package Contract]] — what MABR actually requires, stimgen or not
- [[Presentation Strategies]] — what MABR decides instead of the stimulus package
- [[Running a Session]] — the Stimulus panel and Settings menu in context
- [[mabr.stim.StimulusSet|mabr.stim.StimulusSet-Class-Reference]] — what a converted bank becomes
- [[mabr.stim.CalibrationAdapter|mabr.stim.CalibrationAdapter-Class-Reference]] — the calibration seam
- [stimgen wiki](https://github.com/dstolz/stimgen/wiki) — the package's own documentation
