# Test Mode

**Test Mode copies the stimulus straight into the acquisition buffer.** No audio device is opened. Every frame MABR would have played is written into the acquisition ring buffer instead — the signal channel and the timing channel both — so the samples "recorded" at each onset *are* the samples the schedule put there.

That is what makes it a check rather than just a way to run MABR without hardware. It answers the one question every other number in a session depends on:

> Is the stimulus a file is labelled with the stimulus that actually produced its sweeps?

Turn it on in **Settings ▸ Audio Device (ASIO)…**, at the top of the dialog. The link beside the checkbox brings you back to this page.

---

## Why this question needs answering at all

A sweep is not stored with its stimulus attached. What MABR stores is a continuous trace plus a list of onsets, and the stimulus metadata is matched to sweeps by *position*: the k-th recovered onset is paired with the k-th planned presentation. That pairing runs through a lot of moving parts —

- the **plan** (`mabr.stim.Schedule`) decides which stimulus is presented when,
- the **render** turns that into waveforms and a timing pulse per presentation,
- the **worker** streams it frame by frame,
- the **ring buffer** stores what comes back,
- **onset recovery** finds the timing pulses again,
- **finalization** splits the trace by stimulus and writes one `.abr` per condition.

If any one of those slips by a single presentation, nothing crashes and nothing looks wrong. You get a full set of files, with plausible-looking averages, in which every sweep is attributed to the wrong condition. A threshold series computed from that is wrong in a way no amount of staring at the traces will reveal.

Test Mode removes the rig from the picture so the rest of the chain can be checked against a known answer.

---

## What a Test Mode run tells you

Run a schedule with Test Mode on and MABR reports, after **every run**:

```
Test Mode — 48/48 presentations aligned (offset 0 samples); every presentation
matches its own waveform (max error 4.1e-06)
```

Two separate claims are behind that line.

### 1. The onsets are where the plan put them

Every timing pulse recovered from the recording is held against the onset list the plan rendered ([`mabr.metrics.alignment_report`](../+mabr/+metrics/alignment_report.m)). The report carries:

| Field | Meaning |
|-------|---------|
| `NumExpected` / `NumRecovered` | presentations planned, and timing pulses found |
| `Offset` | the constant lag between plan and recording, in samples. **0** in Test Mode — there is no device in the path |
| `Jitter` | the largest departure from that constant offset. **This is the number that matters.** A constant offset is a cable; a varying one means the k-th sweep is not the k-th presentation |
| `Extra` | pulses recovered beyond the plan. Spurious pulses shift the pairing for everything after them |
| `Truncated` | fewer came back than were planned. Not a fault on its own — a run stopped early by Abort or an advance criterion plays fewer presentations than it renders |
| `Aligned` | zero jitter, no spurious pulses, at least one presentation recovered |

### 2. The samples at each onset are the right stimulus

This half is only answerable in Test Mode, and it is the reason the mode exists. MABR reads the recorded samples at each recovered onset and compares them, sample for sample, with the waveform the schedule assigned to that presentation — **times the polarity it assigned**. `MaxError` is the worst disagreement across the whole run.

It catches faults the onset arithmetic cannot see: a plan whose waveforms are rendered in one order and labelled in another, or a polarity applied to the wrong presentation. Both of those leave every onset exactly where it belongs.

On a real rig this comparison is skipped rather than failed — what comes back through a converter is not the waveform that went out — but the onset half above still runs after every recorded run, and a misalignment is reported in red whatever mode produced it.

The tolerance differs by mode, and only there. Test Mode allows **zero** samples of jitter: nothing is being measured, so one sample of drift is a defect. On a rig it allows **50 µs**, deliberately the same line `verify_timing_loopback` draws, so MABR and its own rig diagnostic cannot disagree about whether a rig is healthy — and because a red warning that fires on every ordinary run is one you learn to ignore, along with the run that genuinely is misaligned.

### What "aligned" is worth

A clean Test Mode run means the schedule, the render, the timing channel, the ring buffer, onset recovery and sweep attribution all agree with each other. It says nothing about your electrodes, your amplifier, your speaker or your subject — no signal ever left the computer. What it establishes is that when real signal *does* arrive, MABR will file it against the right condition.

---

## Reading the numbers

**`max error ~1e-06`** is the expected result. MABR adds about one part in a million of dither to the copied signal — far below any converter's noise floor — so that a loopback run is not perfectly degenerate. With a bit-exact copy every sweep of a condition would be identical, its standard deviation exactly zero and its correlation exactly one, which would make the live view's error bands and the correlation-based advance criterion impossible to exercise in the one mode built for exercising them.

**`offset 0`** is expected and required. Any non-zero offset in Test Mode is a defect, not latency: nothing is in the path to be late.

**`MISALIGNED`** in the status line, or in red in the log, means the run's sweeps cannot be trusted to belong to the conditions they are labelled with. Do not proceed to a real session until it is resolved — see [Troubleshooting](Troubleshooting.md).

---

## The files it writes are not data

A Test Mode run is a **full** acquisition run in every other respect. It finalizes blocks, computes metrics, feeds the live view and the trace organizer, and writes ordinary `.abr` files into the output folder. Those files hold the stimulus, not a recording of a subject.

MABR makes that as hard to miss as it can:

- the Run panel is titled **`Run — TEST MODE (recording the stimulus, not a subject)`** for as long as one is in flight;
- **Settings ▸ Audio Device** summarizes as `TEST MODE (stimulus copied to acquisition)`;
- every block carries `TestMode = true`, and every `.abr` written carries **`ABR_Data.TestMode`** at the top level (always present, `false` for an ordinary run — a field that appeared only sometimes would leave offline code guessing, and the guess that a missing field means "real data" is exactly the wrong way round).

To check a file you already have:

```matlab
>> D = load('SUBJ_ID_001_Frequency_8kHz_Level_30dB_260828T101500.abr','-mat');
>> D.ABR_Data.TestMode
ans =
  logical
   1
```

If you want the check without the files, use **Preview** instead of Start: it runs everything and writes nothing.

---

## What Test Mode is not

- **Not a substitute for the timing loop-back self-test.** That check ([`verifyTimingLoop`](../+mabr/+ui/AcqController.m)) runs at the start of every real session and catches a broken or mis-mapped loop-back cable — a rig problem Test Mode cannot see, because there is no cable in the path.
- **Not a rig diagnostic.** For that, see `verify_timing_loopback('Testing',false)` and `verify_stimulus_alignment('Testing',false)`, which stream through the real device and report latency, jitter and clock drift. See [Testing](Testing.md).
- **Not usable for calibration.** Calibration refuses to run in Test Mode: the "measurement" would be the excitation signal copied back into the acquisition buffer.
- **Not compatible with Stimulation Only.** The two are mutually exclusive and Test Mode wins — it opens no device at all, which leaves nothing for stimulation only to be a mode of.

---

## Doing the same thing from the command line

Everything above is one verification script, which the GUI also offers under **Help ▸ Verification Tests…**:

```matlab
>> verify_test_mode
```

It checks the copy itself (the ring buffer against the rendered play matrix — timing channel bit-for-bit), the report MABR draws from it, the mark on the blocks and files, and — importantly — that the check can actually **fail**, by re-running it over deliberately corrupted onsets. A check that cannot fail is not a check.

For the same correspondence taken apart stage by stage, including through the compute workers, see `verify_stimulus_alignment`.

---

## Where this lives in the code

| Piece | Where |
|-------|-------|
| The copy itself | [`mabr.acq.worker_loop`](../+mabr/+acq/worker_loop.m), the `testing` branch of `stream_block` |
| The setting | [`mabr.AudioSettings.Testing`](../+mabr/AudioSettings.m) |
| The dialog | [`mabr.ui.AudioSettingsDialog`](../+mabr/+ui/AudioSettingsDialog.m) |
| The onset arithmetic | [`mabr.metrics.alignment_report`](../+mabr/+metrics/alignment_report.m) |
| The verdict | [`mabr.ui.AcqController.alignmentCheck`](../+mabr/+ui/AcqController.m), raised as the `AlignmentChecked` event |
| The mark on a file | [`mabr.data.io.writeABR`](../+mabr/+data/io.m) → `ABR_Data.TestMode` |
| The test | [tests/verify_test_mode.m](../tests/verify_test_mode.m) |

The property is still called `Testing` internally. It is what MATLAB prefs and every `.mabrcfg` ever saved call it, and renaming a stored field to improve a label would cost every one of those files its setting.
