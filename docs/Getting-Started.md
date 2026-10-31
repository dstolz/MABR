# Getting Started

This walks through a complete recording session. If you have not installed MABR yet, see [Installation](Installation.md).

## The short version

1. `>> MABR` in MATLAB.
2. Type a subject ID and pick an output folder.
3. Build or load a stimulus bank (or click **Demo** to try the software without one).
4. Choose when each condition should stop: a fixed number of sweeps, or automatically when a response is detected.
5. Untick **Testing** once real hardware is connected.
6. Click **Start** and watch the live plot.

Every run is saved as soon as it finishes: a conventional run is one condition and one `.abr` file; an intermixed run holds every condition at once, so its files (still one per condition) are written when the whole run ends. If something goes wrong halfway through a session, every run that had finished is already on disk — the run in flight is not, unless you **Abort** it, which saves it, and **Resume** then carries the schedule on from the next run.

## Step by step

### 1. Launch

```matlab
>> MABR
```

A small window titled **MABR** opens. Every control is described in [The Acquisition App](Acquisition-App.md); this page covers just the path through them.

### 2. Identify the subject and choose where data goes

**Subject ID** labels the recording and becomes part of every filename. **Output** is the folder the `.abr` files are written to — use the folder button beside it to pick one. The **−** next to each of these two boxes forgets the entry on show, if a list has filled up with old subjects or folders. A per-subject or per-session folder is a good habit, because the offline analysis tools treat each folder as one session.

If you choose **(not saved)** in Output, blocks are still recorded and held in memory, but nothing is written to disk.

### 3. Load a stimulus

MABR does not create sounds. It plays waveforms a calibrated stimulus package produced for you, so that the levels in your data mean what they say.

- **Design…** opens the stimgen bank editor — the suggested route. Pick a stimulus type, give a parameter a vector (`Frequency = [8000 16000]`, `SoundLevel = [30 60]`) and it expands into every combination; each one becomes a MABR stimulus. The editor stays open and the button becomes **Adopt bank**, so you can adjust and re-adopt freely.
- **Open…** opens a saved bank: a stimgen `.spl`, or a `.mat` of pre-computed stimuli. Each entry carries its own waveform, sample rate, and metadata (frequency, level, and so on). Banks you have opened before are in the **Bank** dropdown — pick one to load it again.
- **Demo** loads a built-in grid of tone pips (8 and 16 kHz at 30 and 60 dB). These are **not calibrated** — the levels are nominal. Use this to learn the software or to check the signal chain, never to collect real data.

Once loaded, the label under **Bank** turns from red to a count and its source — `4 stimuli · stimgen (calibrated)`. If it is **amber** and reads `(uncalibrated)`, the bank has no calibration behind it: the sounds will play, but their levels are nominal, and a bank asking for several different levels will produce sounds that are all equally loud. Calibrate first (**Settings ▸ Calibration…**) and rebuild the bank before collecting data.

### 4. Decide when each condition stops

The **Advance** dropdown controls when MABR moves from one condition to the next:

- **All Repetitions** — play every repetition you asked for, however many that is. The count comes from **Repetitions** in the Presentation panel (e.g. 256 or 512). Simple and predictable; every condition takes the same time.
- **Correlation Threshold** — stop as soon as the response becomes reproducible. MABR continuously compares the response window against the pre-stimulus baseline; when that contrast reaches the threshold in the **stop at r ≥** field beside the dropdown (0–1), the condition ends early and the next one starts.

**Correlation Threshold is available for blocked strategies only.** Pick an intermixed strategy and the dropdown greys out and reverts to **All Repetitions** — stopping a run that pools several conditions would truncate whichever stimuli happened to fall last, unbalancing the design.

The correlation option can meaningfully shorten a session, because strong conditions (loud levels, near-threshold frequencies) finish in a fraction of the sweeps that weak ones need. It cannot fire before a minimum number of sweeps have been collected, so it will not stop on a lucky-looking handful of traces.

### 5. Testing vs. real hardware

Open **Settings ▸ Audio Device (ASIO)…**. **Testing (loopback, no hardware)** is ticked by default. In this mode nothing is sent to an audio device — the stimulus is fed straight back as if it were the recorded response, so you can see the whole program run without a rig. Untick it when your ASIO device is connected and you want to record for real; the same dialog is where you pick the device and channel mapping.

Changing this checkbox rebuilds the acquisition worker, which takes a few seconds the first time.

Test Mode is the factory default, so the window never lets you forget which one you are in: the line directly above the **Run** panel always says. It is an amber `TEST MODE — no device, the stimulus is copied into the recording` in Test Mode, and otherwise the device, rate and amplifier gain — `ASIO Fireface UC · 192 kHz · gain ×10000` — with `· bank UNCALIBRATED` added when the loaded bank has no calibration. Read it before the first Start of the day.

### 6. Record

Click **Start**. (If the longest stimulus is longer than the ISI, MABR asks first — *Stimuli last 12.0 ms but the ISI is 10.0 ms: presentations will overlap and be summed. Start anyway?* — and the default answer is **Don't start**.) In order, MABR will:

1. Start the background acquisition process (once per session; the status line says so).
2. Prepare the first condition and begin playing it.
3. Show sweeps accumulating in the live plot as the running average builds.
4. Stop the condition when your advance criterion is met, save it to a `.abr` file, and move to the next.
5. Repeat until every condition is done, then report the schedule is complete.

While it runs:

- **Pause** suspends playback in place and keeps the audio device open; the lamp reads **Paused** and the button becomes **Resume**.
- **Advance** ends the current run early, saves it, and continues with the next one. Useful when a condition is clearly done or clearly bad.
- **Abort** ends the current run early, saves it, and halts the schedule. It is not the end of the session: the **Resume** button beside **Start** lights up, and pressing it carries on from the next run in the same session folder with the counts already recorded (an accidental Abort at run 40 of 60 costs nothing). **Start** would begin a new session instead.

Nothing is discarded by any of these — whatever was recorded before you pressed the button is saved.

Two things to watch while it runs. A red **MISALIGNED** badge (`Run 7 MISALIGNED`) appears above the Run panel if a finished run's sweeps do not sit where the plan put them; that run's data cannot be trusted as the conditions it is labelled with, and the badge stays until the next Start. And closing the window mid-run asks first (**Keep recording** is the default), because the run in flight is lost if you close.

### 7. Look at the results

Both viewers open when you press **Start** (not when the app launches) and sit to the right of the main window. Their toolbar buttons — the monitor and the stacked traces — open them earlier, or raise them if they get buried. Traces from a run that failed the alignment check carry a red ⚠ in the Trace Organizer.

The **Live Plot** (**L**) shows the most recent sweep on its own axes at the top (blue), a bar with the current correlation against your threshold, and below them the running average of every condition the run is presenting. It updates about 20 times a second. Conditions are named by the parameters your bank varies — `8 kHz, 30 dB` — and the **Means** control lays them out overlaid, one panel each, as a Frequency × Level **grid**, or **stacked** into the offset level series a threshold is read from. See [Viewing Data](Viewing-Data.md#live-plot).

The **Trace Organizer** (**T**) stacks the finished conditions on one axis so you can compare them, drag traces to reorder them vertically, and mark response peaks. See [Viewing Data](Viewing-Data.md).

For threshold estimation across a whole subject or study, use the offline pipeline — see [Offline Analysis](Offline-Analysis.md).

## What to expect on disk

One file per condition, in a folder of its own for each Start, under your output folder:

```
SUBJ-ID-001\SUBJ-ID-001_260720T141522\
    SUBJ-ID-001_Frequency-8kHz_Level-30dB_260720T141530.abr
    SUBJ-ID-001_Frequency-8kHz_Level-60dB_260720T141812.abr
```

**Settings ▸ Session Folders…** changes how that folder is named (add the bank, the date as a level of its own, a folder per stimulus, …) or switches it off. See [Data Files](Data-Files.md#changing-the-folder-pattern).

These names are not cosmetic — the offline analysis tools read the stimulus parameters back out of them. See [Data Files](Data-Files.md).

---

## Developer notes

### Driving a session from a script

The GUI is a thin view over [mabr.ui.AcqController](../+mabr/+ui/AcqController.m), which is usable headlessly. This is the whole flow, no figure required:

```matlab
cfg = mabr.Config;
c   = mabr.ui.AcqController(cfg,true);      % true = loopback/testing
c.waitUntilReady(120);                       % one-time worker handshake

% a bank of single stimuli — struct array or mabr.stim.StimulusSet
c.setStimuli(mabr.stim.demoStimuli(cfg));

% presentation is MABR's to choose, not the stimulus package's
c.Schedule.Strategy    = 'interleaved-random'; % intermix the conditions
c.Schedule.Repetitions = 512;               % scalar, or one value per stimulus
c.Schedule.ISI         = 1/21.1;            % seconds, onset-to-onset
c.Schedule.build();                          % required after either change

c.Session.Subject.ID = 'SUBJ-ID-001';
c.Session.OutputPath = 'C:\data\subj001';

addlistener(c,'BlockReady',      @(~,e) disp(e.Info.block.Label));
addlistener(c,'BlockSaved',      @(~,e) fprintf('saved %s\n',e.Info.file));
addlistener(c,'ScheduleComplete',@(~,~) disp('done'));

c.start();
```

That produces one `.abr` per stimulus even though every condition was played in a single intermixed run — `AcqController` de-interleaves the sweeps on the way out.

For a blocked schedule you can additionally arm an early-stop criterion, which ends each run as soon as the response is good enough:

```matlab
c.Schedule.Strategy = 'conventional';  c.Schedule.build();
c.AdvanceFcn    = @mabr.stim.advance.corr_threshold;
c.AdvanceParams = struct('targetSweeps',512,'corrThreshold',0.5, ...
                         'minSweeps',32,'maxSweeps',Inf);
```

The criterion is ignored under intermixed strategies — see [Extending MABR](Extending.md#defining-when-a-run-ends).

The controller is event-driven throughout — `start()` returns immediately and the schedule proceeds on engine events and a live-view timer. Do not busy-wait on its state; listen to `StateChanged`, `MetricsUpdated`, `BlockReady`, `BlockSaved`, and `ScheduleComplete`.

See [verify_online_advance.m](../tests/verify_online_advance.m) for the same pattern used as an end-to-end test, including how to block until completion in a script.

### Where the pieces live

`AcqController` mediates between an [Engine](../+mabr/+acq/Engine.m) (hardware), a [StimulusSet](../+mabr/+stim/StimulusSet.m) (what the sounds are), a [Schedule](../+mabr/+stim/Schedule.m) (when and in what order they play), and a [Session](../+mabr/+data/Session.m) (what came back). [Architecture](Architecture.md) explains the boundaries; [Extending MABR](Extending.md) covers replacing any of them.
