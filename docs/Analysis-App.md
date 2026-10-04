# The Analysis App

The analysis app is the window for everything that happens to saved `.abr` files after they are recorded. You open a data folder, label the sessions in it, analyse them, review each threshold and its peaks, compare a whole study, and export the tables R needs. It needs no audio device and no parallel pool.

It is a window over the [`mabr.analysis` classes](Analysis-Classes.md). Anything it does can also be done from a script, and **File ▸ Export Analysis Script…** writes that script for you.

```text
1 Open a data folder · 2 Label timepoints · 3 Analyse · 4 Review · 5 Compare in Study · 6 Export
```

That line is the hint on the Start panel, and it is the order this page follows.

## Starting it

```matlab
>> MABRAnalysis                                        % reopen where you left off
>> MABRAnalysis("C:\data\OFC_NoiseExposure")           % open this data folder
```

`MABRAnalysis` sets up the path the way `MABR` does, points the logger at this installation, and opens the window. Only one analysis window exists at a time. A second call brings the open window forward, and opens the folder in it if you name one.

From MABR itself, use **File ▸ Offline Analysis…**. It opens the same window, or brings it forward. The two windows are neighbours, not parent and child:

- Closing MABR leaves the analysis window open.
- **Arrange windows** in MABR brings the analysis window forward but does not tile it.
- No MABR control locks it during a run.

**On an acquisition rig, run it in a second MATLAB.** MATLAB has one thread. Whatever the analysis window computes in the MATLAB that is acquiring holds up MABR's live view until it finishes. So while a schedule runs, the analysis window asks before it analyses, exports or rescans:

> MABR is acquiring in this MATLAB. Analysis here will freeze its live view until it finishes.

A batch is refused outright while MABR is acquiring. Browsing and reviewing stay available. A second MATLAB has none of these limits.

## Opening a study

**File ▸ Open Folder… (Ctrl+O)** opens a data folder. You can also use the Start panel's big button, or pick a recent folder. Each folder of `.abr` files below it becomes one **session**, the way MABR writes them: by default a folder for each **Start**, `<Subject>\<Subject>_<yyMMdd>T<HHmmss>`.

**Open the study folder, not one animal's.** Results, timepoint labels and study plots are kept for the whole folder you open. If you open `SUBJ-ID-1254` inside a study that has no results yet, the app asks:

> "SUBJ-ID-1254" looks like one animal's folder. Open the study folder "OFC_NoiseExposure" instead? Results and labels for all animals are then kept together.

Once a study has a results folder, opening any folder inside it files into that study's results anyway.

### What is written where

**Opening a folder writes nothing into it.** A data folder is often a synced or shared drive, and listing it must not change it. All three of these stay out of the data tree:

- The scan of the folder is cached in `%LOCALAPPDATA%\MABR\AnalysisCache`, never next to the recordings. A rescan reopens only the files that changed.
- The first edit or results save creates the **results folder**, `<study>\MABR_Analysis`. Everything the app writes goes there (see [Files written](#files-written)).
- **Settings ▸ Results Folder…** puts the results somewhere else for this study. Use it for a read-only data drive. The choice is remembered for this folder on this computer.

The browser's **Results:** line shows where results go. Click it to open that folder; before the first save, clicking it tells you the folder is created then.

**Read-only data.** If the results folder cannot be written, the app goes **read-only**. Your edits stay in memory, and a yellow bar offers **Choose results folder…**. Edits are not lost: choosing a writable folder saves them there.

The same happens when the study's `project.mat` cannot be read, or was written by a newer MABR. The app never writes such a file back. It opens the store read-only, without its labels, pools and exclusions, and the header and the bar give the reason ("project.mat could not be used (…)"). A save is refused once, with that reason, and is not retried.

**Results already inside an animal's folder.** Someone may once have opened one animal's folder on its own, which left a `SUBJ-ID-1254\MABR_Analysis`. The browser then shows a blue banner: "Results found in SUBJ-ID-1254/MABR_Analysis (6 sessions)."

- **Import into this project** copies those results and labels into the study's store. It never modifies or deletes the nested store.
- **Ignore** dismisses the banner for good.

## The window

- **Browser** (left; Ctrl+B hides it): every session of the folder.
- **Header**: what is open, whether it is up to date, the settings profile, how many series are reviewed, and the save state. Its **Analyse** button names its cost: "Analyse (≈25 s)", "Re-fit thresholds", "Re-run from detect (≈20 s)", or a greyed "Up to date".
- **Notification bar**: one message at a time, the most important first:
  - TEST MODE (the samples are the stimulus, not a subject);
  - read-only;
  - save conflict;
  - out of date, listing what changed;
  - a session holding both acquisition modes;
  - nested results or study duplicates.
- **Five tabs**: Session, Grid, Series, Trials, Study.
- **Status line** along the bottom. Every curation echoes there with its undo hint: "Accepted fit 34.9 dB for Tone 8 kHz (was manual 40) — Ctrl+Z to undo".

**Toolbar**, left to right, in its groups. Each button's tooltip names its shortcut.

| Pictogram | Does |
|---|---|
| open folder · circling arrow · floppy disk | Open data folder… (Ctrl+O) · Rescan the folder (F5) · Save now (Ctrl+S) |
| green ▶ · stack of sessions | Analyse the open session (Ctrl+Enter) · Analyse several sessions in a batch… |
| table with an arrow · page of code `</>` · chart with an arrow | Export tables… (Ctrl+E) · Export an analysis script… · Export the plot on this tab as a figure… |
| arrow curling back · its mirror | Undo (Ctrl+Z) · Redo (Ctrl+Y) |
| stacked traces · marked peaks · sweep raster · audiogram | the Grid, Series, Trials and Study tabs (Ctrl+2 to Ctrl+5) |
| notepad and pencil · cog | Note… (Ctrl+N) · Analysis Settings… |
| keyboard with F1 lit · ? in a blue disc | Keyboard shortcuts (F1) · this guide |

**Every change is undoable and saved.** Edits go through one model object. **Ctrl+Z** undoes and **Ctrl+Y** redoes, with 100 steps per session for as long as the window is open. Each session keeps its own history when you switch to another.

About 2 s after an edit the session's results file is rewritten. The header shows Saved / Saving… / Save pending. Results are also saved when you switch session, close, start a batch or export.

**Save conflicts.** If a results file was changed somewhere else, for example by a batch in another MATLAB, the app does not overwrite it. A red bar offers **Keep mine** or **Load theirs**.

Re-analysing a session clears its undo history, and the status line says so.

## Browser

```text
SUBJ-ID-1254 (6)
  2026-10-01 · Baseline (6)
    ● 14:08  Tone 6×9 · 54 files  ✓5/7
    ◐ 14:00  Tone 6×9 ×2 · ClickTrain ×9 ×2 · 126 files ⧉
    ⊕ Pool: 14:00 + 14:08  ○
```

Subjects come first, in natural order (SUBJ-ID-959 before SUBJ-ID-1254). Under each subject is one **visit** per day, then the sessions recorded that day. The status glyph comes first:

| Glyph | Meaning |
|---|---|
| ○ | not analysed |
| ● | up to date |
| ◐ | out of date (settings, files or overrides changed since it was analysed) |
| ✓ | up to date and every series reviewed |
| ✕ | the last analysis failed |

Badges appear only when they apply:

- ⧉ an interleaved (intermixed) run;
- ⚠ a run stopped early;
- TEST Test Mode files;
- ✓k/n series reviewed.

**Search** (Ctrl+F) matches subject, folder, stimuli, summary, timepoint and group. **Show** narrows the list to *Needs review*, *Not analysed*, *Out of date*, *Failed*, *Not in study* or *Test Mode*.

**Opening a session.** Double-click it, press **Enter** after clicking the tree, or press **Open**. A session with a results file opens from its results in a moment, without reading any `.abr`. The Trials tab and a re-analysis load the raw files when they need them.

**Open from raw files** (context menu) reads the `.abr` files instead of the results: the edits stored in the results file are kept, and the session can be analysed afresh. It is also what happens by itself when a results file cannot be read, for example after a partial sync or a damaged disk. The status line says so, and the unreadable file is first copied to `.history\<session>_unreadable_<yyMMddTHHmmss>.mat`, so the next save cannot destroy it. Its edits cannot be carried over; press **Analyse**.

**Details.** Below the tree, the selected session's details come first with what its badges warn about (TEST MODE, ⚠ a run stopped early). Then its files, conditions and sweeps, units, status and labels, and the **rig notes** written while it was recorded: how many, and the first two. The Session tab lists them all.

**Labels** go in the details below the tree:

- **Timepoint**: set on a visit, it labels every session of that day. A new session takes the timepoint its animal already has that day, so a visit's sessions share one and the earliest names it. Failing that, the timepoint comes from the folder name (`_Baseline`, `_2weeks`), and failing that, from the date (`2026-10-01`).
- **Group** belongs to the animal.
- **In study** says whether the session counts in the Study tab.
- **Comment…** adds a note to the session.

The context menu does the same for several nodes at once. Labels are stored in the study's `project.mat` and are undoable.

**Pool sweeps of selected sessions…** reads several folders of one animal as one session. Its confirmation lists what is pooled per condition. The pool appears as ⊕ under its visit, its members leave the study, and **Unpool** puts them back. Pooling animals is refused.

**Analyse n sessions…** opens the batch dialog on the selection.

## Session tab

The first thing to look at when a session opens, and where its inputs are decided.

**Condition matrix** (top left): one row per level, loudest at the top, and one column per series. Each cell is coloured by a measure you pick: clean sweeps, % rejected, −log10 p, split-half r or SNR. The cell shows its value, with ● (detected) or ○ (not) in the corner, or ■ □ when you overrode the detection. The final threshold is a green step line between the rows. Click a cell to select that condition in every tab. Double-click to open it on the Series tab.

**Files** (bottom left): every `.abr`, grouped by run, showing:

- whether it is used;
- its start time, stimulus and parameters;
- its sweeps and the rig's own rejections;
- its layout and ISI;
- its units, and Test Mode;
- why it is left out, if it is.

Unticking **Use** is *staged*. Nothing changes until **Apply** ("3 changes — Apply re-segments the affected conditions (≈5 s)"), and **Discard** forgets the changes. The buttons stage whole selections: *Use all*, *Only conventional*, *Only interleaved*, and *Skip short* (files with under half the median sweep count). The two *Only* buttons are live only when the session holds both kinds of run, and a refusal names the cause. The context menu does the same for one run group.

Some files are left out by themselves, each with its reason:

- a file at another sample rate than the session's majority;
- a Test Mode file beside real data;
- a copy of a file that is already in another folder of a pool.

**Acquisition modes.** A file holding one condition's continuous run is *conventional*. A file cut out of an intermixed run is *interleaved*: its 10 ms windows are stored back to back, with no pre-stimulus samples (see [Data Files](Data-Files.md#compact-files-from-intermixed-runs)). A session holding both is analysed as **two series per frequency** by default, and the blue bar says so.

Pooling the modes changes the sweep count and the stimulus history. On real data it lowered thresholds by up to 31 dB, so pooling is a deliberate choice: **Settings ▸ Analysis Settings ▸ Signal ▸ Pool acquisition modes**.

Interleaved conditions are **windowed**. Each sweep's own window is filtered on its own, and their time axis covers only what the files hold, 0 to 9.917 ms at 12 kHz.

**Notes** (top right): the rig notes taken while the session was recorded, each shown once. Switch to *All notes* to see the whole notebook.

**Messages and summary** (bottom right): the warnings the analysis left, warnings first. The summary describes how the session was processed: the filters and their −6 dB corners, the acquisition modes, units, the settings profile and hash, the data fingerprint, and where the results file is. Two warnings name what the analysis had to leave out:

- **Non-finite samples.** A file holding NaN or Inf samples costs only the sweeps those samples reach. On a continuous trace that is every sweep whose window, widened by the filter's reach, holds one; in an interleaved file it is the one window that holds it. The condition's flags count the dropped sweeps, the warning names the files, and every other sweep is exactly what it would have been.
- **Zero variance.** A condition whose clean sweeps do not vary at all (a dead, all-zero channel, a digital loop-back, data written without noise) has nothing to test a response against. It is not tested: its p is empty, its measures that are ratios over the noise (F, SNR, Fsp, split-half r) are empty, and it is flagged "zero variance: the clean sweeps do not vary (a dead channel, or noiseless data)". The warning names the conditions, and the threshold methods ignore those levels, so a dead channel gives *insufficient* series, never a threshold.

**Overrides** (bottom right) apply to this session only. Leave a field empty for none:

- **Full scale** (V) and **Gain** correct files whose units were recorded wrongly or not at all. Applying either makes the session out of date from segmentation.
- **Time offset** (ms) and **Conduction delay** (ms) change only the latencies *reported*. The peaks are re-picked at once to record the new offset, and no pick moves: "Overrides saved — latencies now reported less a 0.3 ms latency offset (peaks re-picked, no pick moved; undo history cleared)." See [Sound conduction delay](#sound-conduction-delay).

## Grid

Every series of the session side by side, with levels stacked loudest at the top. It is the whole session at a glance, and the place most thresholds are judged.

- The **final threshold** is a green divider between the rows:
  - an interval sits halfway between its two levels;
  - **NR** above the top row means no response;
  - a divider under the bottom row means every level responded.
- The method's own threshold is a dashed red divider wherever your decision differs from it.
- Traces below the threshold are dashed grey. The selected condition is thick and amber.
- A level a series lacks says **not recorded**. It is never drawn as a flat trace.
- The right margin carries a note per trace: ● ○ detection, p, split-half r, SNR or n. It turns amber when a condition has fewer clean sweeps than **MinSweeps**.
- Each column says its vertical scale in words: "rows 3.2 µV apart" (a trace one row tall is that big), or "↕ 3.2 µV" in a narrow column.
- **Peaks** draws the wave picks: ▲ peaks and ▼ troughs, in the wave colours, never below threshold.
- **Significance** shades the samples the permutation test found significant.
- **Compare with** overlays another analysed session of the same animal in grey dash-dots.

The strip sets the time window, the scale (*per column*, *global*, *fixed µV*), the polarity (balanced, +, −, difference), an SEM band and the annotation. Click a trace to select it, and double-click to open the Series tab on it. The threshold keys work here too (`a t i x c d`, Alt+↓), and each column's green divider can be **dragged** to set that series' threshold, exactly as on the Series stack (see [Setting the threshold with the mouse](#setting-the-threshold-with-the-mouse)).

## Series

One level series at a time, such as "Tone 8 kHz" (see [What a series is](#what-a-series-is)). This is where a threshold is decided and the waves are picked.

**Left:** every series, with:

- its decision glyph: ✓ accepted, ✎ manual, ∅ no response, ≤ all respond, ✕ excluded, ⚑ flagged and not reviewed;
- its name, shortened for the column: ⧉ marks an interleaved series, and a stimulus word every series shares is left out ("8 kHz ⧉");
- the final threshold and the method's fit (the fit's interval is in the decision line on the Threshold side);
- short flags: NM non-monotone, W wide CI, X extrapolated, LS low sweeps, IS isolated detection, MA miss above, FC fit changed since review.

A series opens at the level you last used in it, else at the level next to its threshold.

**Centre:** the level stack. The selected level is black. Detected levels are dark grey, undetected ones light grey and dashed. The final and fit dividers are the Grid's, and the wave picks are drawn on the traces. The green divider has a small grip (◁) at its right end and can be dragged to set the threshold (see [Setting the threshold with the mouse](#setting-the-threshold-with-the-mouse)); the strip under the stack starts with that reminder. The wave search windows are shaded on the selected level: where the tracker looks for each wave at that level. A **scale bar** in the top-left corner gives the amplitude: a 1-2-5 number of µV, at most 0.8 of the row spacing. With **Normalise** on, the traces share no scale, and the corner says "each trace to its own peak".

**A series with one level** is shown like any other, with its list row, trace, peaks and cursor. It cannot have a threshold, so a banner above the stack and the evidence plot both say "Only one level was recorded — no threshold can be estimated", and only **Exclude** and **Note…** stay among the threshold buttons. Its peaks are curated as usual.

**Right:** two sub-tabs, Threshold and Peaks.

### What a series is

A **series** is the set of conditions that share everything but the level: one stimulus, one acquisition mode, and one value of each other parameter the bank varies. Each series gets one threshold, read along its levels.

- A Frequency × Level tone bank gives one series per frequency, such as `Stimulus=Tone|AcqMode=conventional|Frequency=8` (the condition key without the level).
- A click has no frequency, so a session that also holds clicks adds **one series per click stimulus**: `Stimulus=ClickTrain|AcqMode=conventional`.
- A session holding both acquisition modes has a conventional and an interleaved series per frequency. **Pool acquisition modes** (Settings ▸ Analysis Settings ▸ Signal) merges each pair into one *pooled* series.

**The level parameter** is the one a series runs along. Left *(automatic)*, it is found by name: Level (stimgen's SoundLevel is read as Level), then Intensity, dB or Attenuation. Failing those, it is the only numeric parameter that varies. A session where none can be told has no series, and its messages say so. A parameter named like Attenuation runs the other way, quieter as it grows, and is fitted descending.

**Thresholds along another parameter.** Three settings on **Settings ▸ Analysis Settings ▸ Thresholds** decide the series:

| Setting | What it does |
|---|---|
| Level parameter | the parameter a threshold is read along. The list offers the session's parameters; *(automatic)* is the rule above. |
| Group series by | the parameters that make one series, comma separated. Empty (the default) means Stimulus, AcqMode and every parameter but the level parameter. Stimulus and AcqMode are always added to a list you type (see below). |
| Level direction | *Automatic* (descending for an Attenuation axis), *Ascending (louder up)* or *Descending (attenuation)*. |

For example, to read a threshold along frequency at each level, set **Level parameter** to `Frequency` and **Group series by** to `Level`. Each level then becomes a series, such as `Stimulus=Tone|AcqMode=conventional|Level=60`, fitted across the frequencies.

- **A series never mixes stimuli or acquisition modes.** Stimulus and AcqMode are always part of a series, whatever you type: a list that leaves them out has them added, in key order. AcqMode is not added when **Pool acquisition modes** is on, since the pooled runs are then one mode. When an added column actually varies, the session's messages say so: "Series grouped by Stimulus, AcqMode, Level: Stimulus and AcqMode added to the GroupBy given, since a series never mixes stimuli or acquisition modes." The settings summary reads "series by Level (and Stimulus and AcqMode, always)". So `Group series by = Frequency` gives exactly the default series, and their decisions stay where they were.
- A stimulus without the level parameter cannot be fitted along it. A click, read along Frequency, gives series of one condition each, reported *insufficient*.
- **A dead or flat channel.** A condition whose clean sweeps do not vary (an all-zero input, a digital loop-back, data written without noise) is not tested, and is flagged "zero variance" (see [Zero variance](#session-tab)). Its level is left out of the series with the reason ("level ignored at 60 dB: zero variance (the clean sweeps do not vary)"), in the fit and in **Compare methods** alike, so a series recorded on a dead channel is *insufficient*, never a threshold.
- A Level parameter that is not a sound level is labelled in its own unit wherever a level is shown: kHz for Frequency, no unit for any other parameter (never "Frequency (dB)").

These are *thresholds* settings, like the method: the open session is re-fitted at once, and other sessions become out of date. Changing them changes the series keys, so the decisions on the old series are **archived**, not lost. They come back, by key, when the old grouping is set again.

### Threshold methods

A threshold is a statement about a whole series, made from one statistic per level. The **method** says which statistic, which rule turns it into a threshold, and at what criterion. It is a setting of the *project*, so every session of the study is judged the same way.

The **Threshold** sub-tab's method dropdown changes it. The open session is re-fitted at once. Other sessions become out of date and are never re-run behind your back. The sentence under the dropdown says exactly what "threshold" means under the settings in force.

| Method | What it decides from | The rule |
|---|---|---|
| `perm-glm` (default) | Permutation test detections | Threshold = level where the probability of a detected response (TFCE permutation test, α 0.05, 1000 permutations) reaches 0.50 (Firth logistic fit; profile CI; advisory). |
| `perm-descending` | Permutation test detections | Threshold = the midpoint between the highest level without and the lowest level with 2 consecutive detected responses, descending from the loudest level to the first 2 consecutive misses (permutation test TFCE, α 0.05, 1000 permutations). |
| `power-descending` | Response power against the ± reference (sign-flip test) | Threshold = the midpoint between the highest level without and the lowest level with 2 consecutive detected responses, descending from the loudest level to the first 2 consecutive misses (response power vs ± reference, sign-flip test, α 0.05, 1000 permutations). |
| `fsp-descending` | Fsp with estimated degrees of freedom | Threshold = the midpoint between the highest level without and the lowest level with 2 consecutive detected responses, descending from the loudest level to the first 2 consecutive misses (Fsp with estimated degrees of freedom, α 0.05). |
| `presto` | Split-half correlation | Threshold = level where the split-half correlation (median sub-averages, 500 resamples, 0.5–8 ms) reaches 0.30 (sigmoid or power-law fit). |
| `xcorr` | Correlation with the next-louder level (Suthakar & Liberman 2019) | Threshold = level where the correlation with the next-louder level's average (lag ≤ 0.3 ms) reaches 0.35, interpolated between the bracketing levels of the lowest run of 2 consecutive levels at or above it, descending from the loudest level to the first 2 consecutive misses. |
| `custom` | Any metric, model and criterion | Read from the settings (Settings ▸ Thresholds). |

The numbers in those sentences are the defaults. The app always shows the ones in force.

**P-based detection decides; graded metrics interpolate.** A p-value says *whether* there is a response at a level, not how much. The p-methods (`perm-*`, `power-*`, `fsp-*`) therefore reduce each level to yes or no (p < α). The *descending* rule then reports the **interval** between the highest level without and the lowest level with 2 consecutive detections. That is interval-censored data. The point reported inside it is set by **Convention**: the midpoint by default, or the louder level (*lowest_level*).

A graded metric (r, SNR) crosses its criterion somewhere between two levels, and the straight-line crossing is a point estimate. `perm-glm` fits a Firth-penalised logistic curve to the detections. That gives a finite threshold and an honest profile CI even when every level above a point detects and every level below does not. Its value is marked *advisory* because a curve through yes/no data is a model, not an observation. `perm-descending` is the robust alternative, one dropdown away.

**The descending rule walks down, as it is done by eye.** It starts at the loudest level and goes down while the response continues, and it stops at the first 2 consecutive misses (**Consecutive detected levels**, *MinConsecutive*). The threshold run is the lowest run of 2 detections above that stop. A detection below the stop is cut off from the response at the top: it only raises the flag *isolated detection below threshold* (IS), and never becomes the threshold. Scanning up from the quietest level instead would take the first run met there, which for a series with no response can be a run of noise.

**Borderline detections.** The p of a permutation or sign-flip test (`perm-*`, `power-*`; not Fsp) is a Monte-Carlo estimate, so a level whose p lies within twice its standard error of α, 2·√(α(1−α)/B) for B permutations, is a detection the next seed may not make. Such levels are flagged ("borderline detection at 30, 40 dB (p 0.060, 0.043 within Monte-Carlo error of 0.05)"). Nothing changes; the flag tells you which detections to look at.

**One quantity, three names.** For random equal halves, the split-half correlation, the power test's F and the SNR measure the same signal-to-noise ratio:

> r ≈ (F − 1) / (F + 1), and SNR = 10·log10 F

So r 0.30 is F ≈ 1.9, and r 0.35 is F ≈ 2.1. This holds for *mean* halves; the default *median* halves give a somewhat lower r. It is why the power and Fsp methods decide by p rather than by a criterion on any of these numbers.

**Usable levels.** A level counts only when it has at least **MinSweeps** clean sweeps (100 by default) and at least **MinPerPolarity** of each polarity (40) for alternating data, and a defined value of the metric. Any other level is dropped with a flag that says why, not entered as a confident miss: "level ignored at 60 dB: 37 clean sweeps, fewer than the minimum of 100", "… clean sweeps of one polarity, fewer than the minimum of 40", "… zero variance (the clean sweeps do not vary)", or "… the metric is undefined".

**Censoring is an answer.**

| Status | Meaning | Reported as |
|---|---|---|
| ok | a threshold inside the levels | `34.9` or `35 (30–40]` |
| no-response | no usable level detected: the threshold is above the loudest level | `>80`, right-censored |
| all-respond | every usable level detected: the threshold is at or below the quietest | `≤0`, left-censored |
| insufficient | fewer than two usable levels: one level cannot say where a response starts | `n/a` |
| failed | the fit could not be made | `n/a` |

**Insufficient is never "no response".** A series with only one usable level is *insufficient* when that level does not respond. When it does respond, the series is *all-respond*, left-censored at that level. Both carry the flag "insufficient levels". A model estimate more than one level step outside the levels tested is censored the same way, and the raw estimate is kept.

On an **attenuation** axis, where a bigger number is quieter, set **Level direction** to *descending*, or let *auto* recognise a parameter named like Attenuation. The series is then fitted the other way up.

### Curation and review

The fit is a proposal. Each button records a **decision**, which is undoable. Your name (Settings ▸ Analyst Name…) and the time are stamped on it:

| Button | Key | Decision |
|---|---|---|
| Accept fit | `a` | the method's threshold, as fitted |
| At selected level | `t` | manual: the selected level is the lowest with a response (an interval below it) |
| Value field + Set | | manual: exactly this value |
| No response | `i` | right-censored at the loudest level |
| All respond | Alt+↓ | left-censored at the quietest level |
| Exclude | `x` | out of every analysis; the note editor opens for the reason |
| Clear | `c` | back to no decision |
| Note… | Ctrl+N | a note on this series |

**d** cycles the selected level's detection between *auto*, *response* and *no response*. An override counts as a reviewed level, and the threshold is re-fitted at once.

#### Setting the threshold with the mouse

The green divider is a handle as well as a mark. Drag it on the **Series** stack, or in any **Grid** column, to put the threshold where you see it:

| Drop the divider | Decision | The same as |
|---|---|---|
| between two levels | manual: the louder of the two is the lowest level with a response. The threshold is the interval between them, its point set by the **Interval convention** (the midpoint by default), so the divider **snaps** half way between the two traces | **t** on the louder level |
| between two levels, **Alt** held | manual: exactly the value at the pointer, to 0.1 dB | the value field + **Set** |
| above the loudest level | no response (right-censored) | **i** |
| below the quietest level | all respond (left-censored) | **Alt+↓** |

- **Finding it.** The divider has a small green grip (◁) at its right end, and the pointer turns into the up-down resize arrows within a few pixels of it. A series with no final threshold yet (excluded, or a method that could not fit) shows a **hollow** grip, on the fit's dashed red line or half way up the stack, to drag from. A series of one level, or one not analysed, has none.
- **While dragging,** the divider follows the pointer and shows where a release would put it, with a readout beside it ("Threshold 37.5 dB SPL", "No response (> 80 dB SPL)"). On an attenuation axis, where a larger number is quieter, the readout writes the bound in the axis' own numbers, as the series list does: "No response (≤ 0 dB)", "All respond (> 80 dB)". The method's own threshold stays in view as the dashed red line, the reference you are moving from. The status line gives the whole decision, and on the Series tab the readout also appears above the stack. Alt can be pressed or let go during the drag.
- **Esc** during the drag cancels it, and nothing changes. **Ctrl+Z** undoes a release like any other decision.
- **Nothing is asked.** A release makes the same Model call as the matching button. It is one undo step, saved at once, stamped with your name and the time, and written to the session's edit log as a `setDecision` with the decision and its value. Blind review hides nothing it needs. A release that changes nothing, because the series already has that decision, records nothing.
- **Clicks still work.** A press on the divider that is let go without moving is an ordinary click: it selects the level (or, on the Grid, the condition) under it. A press anywhere else behaves as before. On the Series stack a selected wave point within 8 px of the press keeps its own drag. On the Grid a double-click on the divider still opens the Series tab. Right-click still opens the context menu.
- **On the evidence plot** of the Threshold sub-tab, the same rules run along the level axis: drag its green line sideways, or click (or drag) in the band of sweep counts along its bottom to put the threshold where the click lands. Beyond the loudest level is no response, below the quietest all respond.
- On the Grid, the divider can be dragged only while the **Threshold** layer is shown.

**Decisions survive re-analysis.** They are stored by series key, not by row, so a re-analysis with other settings keeps them. There is one exception. An **accepted** fit that moves by more than half a level step loses its acceptance: the decision goes back to undecided and the series is flagged **FC** (*fit changed since review*), so you look again. Changing how series are grouped archives the decisions, and returns them when the grouping comes back.

**Review state.** "Reviewed 5/7" in the header counts series with a decision. **f** goes to the next series that needs review, in this session or the next. A series needs review when it has no decision yet or carries a flag. **Shift+F** goes back.

**Compare methods** lists every built-in method's answer for the series, under short method names (the full ones in its tooltip) with the status in words. **Evidence** plots what the method decided from:

- for a p-method: detections, and −log10 p against its α line;
- for a graded method: the metric against its criterion, with the fitted curve.

The final value is green and the fit red. Arrows mark censoring. Each level's clean sweep count sits in a band of its own along the bottom, clear of the markers.

**Audiogram.** At the foot of the Threshold sub-tab, this session's final thresholds are plotted against frequency on a log axis, so a threshold decided in one series is seen beside its neighbours:

- one line per stimulus and acquisition mode, when the session has more than one, each named at its last point;
- ▲ for no response, drawn at the loudest level, and ▼ for all respond, at the quietest;
- the selected series ringed in black.

A series has a place on it only when its level axis is a sound level and all its conditions are at one frequency. Any other series is listed beneath the plot with its threshold:

- a series with no frequency, such as a click: "ClickTrain · conventional: 96.2 dB SPL";
- a series whose conditions span several frequencies (a **Group series by** that leaves Frequency out): "Tone (4 frequencies): 35 dB SPL".

When the **Level parameter** is not a sound level (set to Frequency, say), there is no audiogram at all. The note begins "No audiogram: these thresholds are along Frequency, not a sound level." and lists every series. A session in which no series has a frequency (clicks or noise only) shows no empty axes, only the note, in larger type. The Study tab's **Thresholds** sub-tab draws the same plot across subjects and timepoints.

### Peaks

Waves I–V are picked on the loudest level and tracked down the series. Each wave has a search window, written in ms **re the timing pulse** (the recording's own time, which a conduction delay never moves) for 16 kHz, and moved 0.15 ms later per octave below it. The defaults are rodent windows: I 1.0–2.0 ms, II 1.8–2.8, III 2.6–3.6, IV 3.4–4.6, V 4.2–5.6.

On the loudest level each wave is searched in its own window, where the most **prominent** peak leads and the window's centre only breaks near-ties. Going down in level, the tracker expects each wave a little later than at the level above, by the wave's own latency shift: 0.015, 0.018, 0.020, 0.025 and 0.030 ms/dB for I–V. It searches from 0.1 ms before the louder pick to 0.15 ms after the expected point, and here the track leads. A wave's window ends 0.3 ms (the minimum separation) before where the next wave is expected. The waves of a level are then **assigned together**: the candidates go to the waves in the order that scores best overall, and a wave may go without. So a wave missing at one level cannot take the next wave's peak.

A pick is *detectable* when its prominence is at least 4 × the residual noise RN (Settings ▸ Peaks ▸ **Detectable prominence (× RN)**). This is a size criterion, **not a detection test**: a pick is the best of several local maxima, so a pick on noise alone is routinely 2–3 RN prominent. Judge whether there is a response by the threshold. Picks below the final threshold are kept and marked *below threshold*. They are left out of the I/O and latency measures.

| Key | What it does |
|---|---|
| 1–5 / Shift+1–5 | select wave I–V's peak / trough |
| click in the selected level | move the selected point to the nearest extremum (snap) |
| press on a marker and drag | place it exactly where you let go |
| Alt+← / Alt+→ (or Shift) | nudge one sample |
| ← / → | next candidate extremum while a point is selected (else the series) |
| Delete / Shift+Delete | the wave is absent here / here and at every quieter level |
| Backspace | back to the automatic pick |
| p | auto-pick the series again |
| u / Shift+U | re-track from the selected level down, keeping / overwriting manual picks |

A manual pick at one level moves the picks below it only when you re-track (**u**). An absent mark survives re-analysis, like every peak edit.

The **Peaks** sub-tab shows a matrix of latency, P–N amplitude or baseline–peak amplitude per level and wave. Manual picks are bold, absent ones show "—", and picks below threshold are grey italic. Under the matrix is an I/O or latency–intensity plot. Its buttons:

- **Bootstrap CIs** loads the raw data and adds standard-error columns.
- **Use current picks as wave windows** writes this series' picks back as the project's wave windows, in the recording's time like every window (a conduction delay does not shift them).
- **Waves…** edits the windows, adds a wave, or switches one off.

## Trials

One condition's single sweeps, looked at one by one. Single sweeps exist only in raw data. A session opened from its results offers **Load raw data** first.

- **(a) Image**: time across, one row per sweep, in acquisition order or sorted by a feature. An artifact shows as a stripe. Red ticks mark rejected sweeps, grey lines mark file boundaries, and a mark shows where a rig note was written.
- **(b) Mean**: the balanced mean with an SEM or 95% bootstrap band, and the **± reference** in grey. The ± reference is the same sweeps with balanced signs, so the response cancels and what is left is the noise the mean still holds.
- **(c) Feature**: one quality number per sweep against sweep order, time or block. The feature is RMS, peak-to-peak, max |x|, or template amplitude/r. Rejected sweeps are red, with a running median, the *Reject above* line and the selection. The template amplitude (each sweep's projection on the average of the others, scaled to a mean of 1) is empty for every sweep of a condition whose average holds no clear response, since scaling by noise gives meaningless numbers; use the template r there.
- **(d)** One of three panels:
  - convergence: RN against N, log-log, against the 1/√N an average that works follows, with the SNR (dB) against N on the right axis;
  - the split-half r over random partitions, with its *partition 2.5–97.5%* range (a statement about this dataset's halves, never a confidence interval);
  - the permutation test's t map and null distribution, while the null is in memory.

Click a sweep to select it. Shift+click extends the selection in the order shown, Ctrl+click toggles one sweep, and a drag on the feature plot selects a range. **r** rejects the selection and **Shift+R** restores it. The condition is re-tested, and the status line says what changed (p, threshold, peaks). **Reject above** rejects every sweep over a value, in this condition or in every level of the series. **Clear manual rejections** drops your decisions.

Rejections are *flags*: no sweep is ever deleted, and every one is undoable.

## Study

The other tabs look at one session; the Study tab compares them. It is built from the results files alone, so a study of forty sessions opens in a moment. It is off during blind review.

**Sessions** sub-tab: every session, with *In study*, *Timepoint*, *Group* and your own columns editable in place. Values are coerced to an existing level: "baseline " becomes "Baseline", and the status line says so. The table also shows each session's status, review count, processing, noise, rejection, fewest clean sweeps, units and settings hash. A hash that differs from the rest is highlighted.

Below it is the subjects table. Edit a subject's comment from its right-click **Edit comment…**: no note is typed into a table cell. The buttons above the table do the rest:

- **Add column…** / **Remove column…**;
- **Timepoint order…** sets the order timepoints are plotted and exported in;
- **Analyse n selected…**, **Analyse n out-of-date…**, **Review queue…**, **Export…**.

**Thresholds** sub-tab: one point per subject × timepoint × series. The x axis is frequency (log), or the timepoints for a stimulus with no frequency. Summaries are across **subjects**, with n in every legend entry.

- **Duplicates.** Sometimes two in-study sessions measured the same series of one animal at one visit. **Duplicates** then decides which the study uses: *most sweeps* (the default), *latest*, or *mean of sessions*. A banner names the duplicates and what is used, and **Choose…** changes the policy. The choice is stored in the project and is undoable.
- **No response.** A series with no response is drawn as ▲ on a dashed ceiling, and all-respond as ▼, above the summary so the summary never hides them. The **No response** rule says what value a summary uses for it: *max level + step*, *max level + 5 dB*, or *exclude*. The rule is written in the plot's subtitle, so a mean that contains invented numbers says so. A summary point made of censored values alone is drawn with their symbol, hollow (▲, ▼, or a hollow circle for a mix): it is a substituted number, not a measured one.
- **Reference.** Choose a timepoint, or *First session*, to plot each subject's **shift** from it instead. *First session* means the first in timepoint order, then by start time. A point involving a censored value is hollow.
- **Layout.** *One panel per subject* draws one panel per animal, with one legend for all of them. Sessions with no timepoint are plotted as "(no timepoint)".

Click a point to read it ("SUBJ-ID-1254 · Baseline · 8 kHz · 35 dB, manual, reviewed"). Double-click to open that session on that series.

**Growth & latency** sub-tab: a wave's amplitude, latency or interpeak interval against level, or against level re the animal's threshold. Amplitudes are in µV or as % of the animal's reference timepoint. Latencies are the reported ones, re sound arrival when a conduction delay is set.

**Waveforms** sub-tab: the grand average of one condition, the mean of per-subject means ± SEM across subjects.

**Banners** (one at a time). Each names what it counts and what it leaves out:

- *level units differ* (dB SPL against dB re max: those sessions are left out of the threshold plot);
- *analysed with different settings* (**Re-analyse them**). This compares against the project's own settings when any session uses them;
- *processing or amplitude units differ* (left out of the growth plot);
- *median clean sweeps differ by more than 20%* between the plotted groups;
- duplicated series.

## Batch

**Batch ▸ Analyse Sessions…** analyses many sessions with one set of settings. It is the overnight run. Its options:

- **Scope**: selected, out of date, or all.
- **Profile**: the project's settings, a built-in profile, or a `.mabraset` file.
- **Skip up-to-date sessions**: on by default.
- **Include Test Mode** sessions: off by default.
- **Summary figures**: a PNG per session.
- **Stop on error**.

The dialog estimates the time ("40 sessions · ≈ 51 min").

Per session the batch reads the files and takes over any curation, overrides and manual rejections from an existing results file. It then analyses the session and writes new results. A failure is recorded and the batch goes on.

An existing results file that cannot be read does not fail the session at every batch from then on. The session is analysed afresh, its log line says the edits could not be carried over, and the unreadable file is kept in `.history` like any replaced file.

- **Log.** One line per session is appended to `MABR_Analysis\logs\batch_<yyMMddTHHmmss>.csv` the moment the session finishes, so a run stopped by a power cut says exactly how far it got.
- **History.** The results file a re-analysis replaces is first copied to `MABR_Analysis\.history\`. The newest three per session are kept.
- **Report.** **Batch ▸ Last Batch Report** lists what happened. **Retry failed** re-runs the failures with the settings the batch used. Cancel stops after the session in progress.

From a script the same thing is one line:

```matlab
T = mabr.analysis.Batch.runFolder("D:\data\OFC_NoiseExposure", mabr.analysis.Settings());
```

## Review queue and blind review

**Session ▸ Review Queue…** steps you through sessions that need review. The scope is selected, in study, or all analysed. You can limit it to sessions not yet reviewed, and order it as in the browser or at random (seeded, so the order can be repeated).

**Blind review** hides who and when, so thresholds are judged on the traces alone:

- the title becomes "Review item 14 / 236";
- the browser tree is covered;
- subject, folder, date, timepoint and group disappear from every title, readout and status line;
- *Compare with* is hidden and the Study tab is off.

**f** / **Shift+F** and **Ctrl+PgDn** / **Ctrl+PgUp** move through the queue. **Session ▸ End Review** stops it.

## Export and R

**File ▸ Export… (Ctrl+E)** writes tidy tables: one row per observation, one column per variable, snake_case names. The scope is the current session, the selected sessions, the study, or every session with results.

| Table | One row per |
|---|---|
| `sessions`, `subjects` | session / animal, with labels and your own columns |
| `conditions` | condition: counts, p, detection, every single-trial measure |
| `thresholds` | series (with *All methods*, also one row per built-in method; `is_primary` marks the one in force) |
| `peaks` | condition × wave: latencies, amplitudes, prominence, state |
| `peak_measures`, `io_slopes` | derived measures and I/O slopes per series and wave |
| `waveforms` | condition × polarity × time sample of the stored means |
| `trials` | sweep: its features, rejection and reason |
| `notes` | rig note |
| `trial_waves`, `blocks`, `block_waves`, `sweeps` | raw tables; these reopen each session's `.abr` files |

**Formats:**

- **CSV** is UTF-8, with TRUE/FALSE logicals, ISO times, and an empty field for a missing value.
- **XLSX** takes only the small tables (≤ 1,048,575 rows).
- **Parquet** suits the large tables, written one file per session under a folder that `arrow::open_dataset` reads as one.
- **MAT** holds one struct, `MABRExport`.

The dialog estimates each table's rows and size. It warns about sessions out of date, series not reviewed, and Test Mode sessions left out. **Export Again** (Ctrl+Shift+E) repeats the last export into a new folder. An export goes to a stamped folder under `MABR_Analysis\exports\` unless you name one. From a read-only store it asks for a folder instead, and exports nothing, naming the store, if you choose none.

**Thresholds are censored, and Inf is never written.** A series with no response is not missing: its threshold lies above the loudest level tested. Dropping it, or writing Inf (which R reads as a number), biases exactly the group × timepoint comparison a noise-exposure study makes. Every threshold row says how it is censored, in the coding `brms` and `survival` read directly:

| `cens` | `threshold_db` | `thr_lo_db` | `thr_hi_db` | `thr_upper_db` |
|---|---|---|---|---|
| `none` | the estimate | = threshold | = threshold | = threshold |
| `left` (all respond) | quietest level | NA | quietest level | = threshold |
| `right` (no response) | loudest level | loudest level | NA | = threshold |
| `interval` | convention point | level below | level above | = `thr_hi_db` |
| empty (excluded / insufficient) | NA | NA | NA | NA |

The curated value is `threshold_db`. The method's own estimate is `threshold_fit_db`. `threshold_imputed_db` (right: loudest + step; left: quietest − step) exists for plots and sensitivity analyses only, and `imputation_rule` says so on every row.

Amplitudes are in **µV** (`_uv` columns). Latencies are in ms re sound arrival when a conduction delay is set. `lat_peak_raw_ms` keeps the value re the electrical onset.

**What R gets.** With **R script** ticked (the default), the folder also holds:

- `mabr_columns.csv`: every column written, with its type, unit and meaning;
- `mabr_export.json` and `mabr_settings.json`: the manifest, the MABR commit, and the settings by hash;
- `mabr_import.R`, which reads the tables with the right types, makes `timepoint` a factor in your timepoint order, and contains these models:
  - the censored threshold model `brm(y | cens(cens, thr_upper_db) ~ group*timepoint*freq_f + (1 + timepoint | subject))`;
  - the `survival::survreg(Surv(thr_lo_db, thr_hi_db, type = "interval2") ~ …)` alternative;
  - an `lmer` on `threshold_imputed_db`, commented out, as a sensitivity analysis only;
  - `lmer(log(amp_pt_uv) ~ group*timepoint*level_c + …)`, restricted to detectable waves at least 10 dB above threshold, with a latency model and a `glmmTMB` Gamma alternative;
  - `emmeans` pairwise comparisons with Holm adjustment;
  - a block-level drift model when blocks were exported.

## The replication script

**File ▸ Export Analysis Script…** writes a plain MATLAB script that reproduces the analysis of the open session, or of the selected or in-study sessions as a study script. It needs no GUI, no prefs and no project file. It goes to `MABR_Analysis\scripts\<name>_replicate.m` by default, and the status line names what was written. The **Export** dialog's *Also write a MATLAB script that reproduces this export* (on by default) puts `replicate_analysis.m` beside the exported files, built with the same options.

Which sessions it covers:

- with no session open, the sessions selected in the browser, else the in-study sessions, as a study script;
- with a session open, that session;
- with a session open *and* several sessions selected in the browser, it asks: **This session**, **The n selected sessions**, or **The study**.

The Export dialog's **Write script…** button writes only the script, for the sessions of the scope chosen in the dialog (*In study*, *Selected sessions* or *All with results*), without exporting anything. It asks where to save it.

The script, in order:

1. A header: what it reproduces, the MABR commit and the MATLAB version.
2. The path, set up as `MABR.m` does.
3. Every setting written out as a literal, followed by an `assert` on the settings hash, so a changed class default cannot silently change the analysis.
4. Per session:
   - the files and exclusions, with the data folders relative to a `DATAROOT` variable you can edit;
   - the unit, time-offset and conduction-delay overrides;
   - every hand edit as a table: decisions, manual rejections, detection overrides, peak picks and absences;
   - the analysis;
   - a **check** against the results recorded when the script was written. It prints "replicated exactly (n recorded values compared)", or lists each difference. A number within 10⁻⁶ of its own size of the recorded one is floating-point rounding, not a different analysis: it is counted rather than listed, "replicated (n recorded values compared; m of them within floating-point rounding of the recorded value, …)". The check never throws.
5. The export, into an `OUTFOLDER` you can edit.

A study script ends with one line, "N of M sessions replicated."

**Run it** with `run(file)` or F5 in the editor. Results files store the condition means in double precision, so a session opened from its results re-picks exactly the peaks its raw files give. (A results file written before that held single-precision means; its peaks can differ from the script's by about 10⁻⁸ ms, which the check counts as rounding.) One caveat: a peak placed by hand at one level, with no re-track below it, comes back re-tracked below in a fresh analysis. The check then lists those levels.

## Sound conduction delay

Time zero in every `.abr` is the timing pulse: the *electrical* onset of the stimulus. The sound reaches the eardrum later, by its travel time: 0.29 ms for 10 cm of air at 343 m/s, plus any tubing. Set a delay and every latency is reported **re sound arrival**.

**Settings ▸ Analysis Settings ▸ Signal ▸ Sound conduction delay** says how the delay is known:

| Mode | Delay |
|---|---|
| None (default) | 0: latencies re the electrical onset |
| Delay (ms) | as measured |
| Speaker distance (cm) | distance ÷ speed of sound (343 m/s by default) |

A live readout shows the result ("= 0.29 ms"). **Time offset** adds a further fixed offset of the recording system on top. The *[Use it]* helper fills it with the onset rounding bias of the open session's files.

A session can override the delay and the offset (Session tab, **Overrides**). Use that when one sitting used another speaker position.

**It changes reported latencies and nothing else.** The wave windows are written, and searched, in the recording's own time, re the timing pulse, whatever the delay. So a delay never changes **what** is picked: every pick stays where it was, and every reported latency moves by exactly the delay. (Windows moved by the delay searched 0.29 ms later for 10 cm of air, and a peak near the edge of two overlapping windows could change its wave label when the delay was switched on.) The delay is a *peaks* setting: changing it re-runs the peaks step, which is instant, only to record the new offset with each pick. The following follow the delay:

- the Grid, Series and Trials time axes, which read "Time re sound arrival (ms)" and name the delay. Traces, picks **and** the wave search windows are all drawn at recording time minus the offset, so each window still covers the samples actually searched and every pick sits inside its own window;
- every reported latency, in the app and in the export (`lat_*_ms`);
- the Study's latencies, after the session is re-analysed.

**What it does not affect.** Which peak is picked, detection, thresholds and every single-trial measure are unchanged. Interpeak intervals are unchanged, being differences. The wave windows you write, and those **Use current picks as wave windows** writes, stay in recording time. The stored latencies stay raw (re the onset), so the correction is applied in exactly one place and is never applied twice.

A delay set while a session was closed makes it open out of date from *peaks*. A batch re-runs any session whose overrides changed.

## Settings, profiles and staleness

**Settings ▸ Analysis Settings…** edits every setting of the project, on six tabs:

| Tab | What it covers |
|---|---|
| Signal | window, response window, filters, processing, acquisition modes, sweep cap, latency reference |
| Artifacts | rejection rule, feature, factor, ceiling, rig flags |
| Detection & measures | permutation test, α, seed, split-half |
| Thresholds | method, level parameter, grouping and direction (see [What a series is](#what-a-series-is)), convention, minimum sweeps, flags |
| Peaks | the wave table and the tracking priors |
| Profiles | built-in profiles, and loading and saving `.mabraset` files |

A line at the bottom lists anything that cannot work, such as too few permutations for α or a response window outside the window. **OK** and **Apply** stay disabled until it is empty.

**The project's settings govern the project.** They are stored in its `project.mat`, and every session is judged against them. The settings you last applied in any project are only the default for a *new* project.

**Staleness is per step.** Each setting belongs to the first analysis step that reads it:

segment → reject → detect → measure → thresholds → peaks

A results file records the settings each step used. A change therefore makes a session out of date from the first step it touches, and the header and Analyse button say how much has to be re-run. "Re-fit thresholds" and a peaks re-pick are instant. "Re-run from detect" is not. Nothing re-runs by itself.

**Profiles** (Settings ▸ Profile):

- **MABR default** is the recommended defaults:
  - 300–3000 Hz FIR;
  - response window 0.5–8 ms;
  - TFCE permutation test, 1000 permutations, α 0.05;
  - `perm-glm`;
  - at least 100 clean sweeps (40 per polarity) per level;
  - acquisition modes kept separate.
- **Legacy SCRATCH (2025)** reproduces the 2025 `abr_analysis/` batch pipeline:
  - Firth GLM at p = 0.75 on TFCE detections, 2000 permutations;
  - a 300–1500 Hz pass band and detrend order 1;
  - response window 0–10 ms;
  - acquisition modes pooled;
  - no sweep-count minimum.
- **Load from File… / Save Current as File…**: a `.mabraset` file you name.

The header shows "Profile: MABR default", or "(modified)" once the settings no longer match it.

## Keyboard shortcuts

Letters run commands only while a **plot** has the keyboard. After a click in a text field, a table or a dropdown, letters are text again; click a plot to give the keyboard back. While the note editor is open, every key except **Esc** (cancel) and **Ctrl+Enter** (save) is text. After a click in the browser, the arrow keys move the tree and **Enter** opens the session. **F1** shows the keys of the tab you are on.

This list is generated from the app's one keymap, `mabr.ui.analysis.Commands.sheet`. What the mouse does that no key does is listed after the keys of the Grid and Series tabs, as F1 lists it (`mabr.ui.analysis.Commands.gestures`).

### Everywhere

| Keys | Command |
|---|---|
| Ctrl+O | Open data folder… |
| F5 | Rescan folder |
| Ctrl+S | Save now |
| Ctrl+E | Export… |
| Ctrl+Shift+E | Export again |
| Ctrl+Z | Undo |
| Ctrl+Y or Ctrl+Shift+Z | Redo |
| Ctrl+N | Note… |
| Ctrl+Enter | Analyse |
| Ctrl+PgUp | Previous session |
| Ctrl+PgDn | Next session |
| f | Next needing review |
| Shift+F | Previous needing review |
| Ctrl+1 | Session tab |
| Ctrl+2 | Grid tab |
| Ctrl+3 | Series tab |
| Ctrl+4 | Trials tab |
| Ctrl+5 | Study tab |
| Ctrl+B | Show/hide browser |
| Ctrl+F | Find session |
| F1 | Keyboard shortcuts |
| Esc | Clear point / cancel drag / close editor |

### In the browser

| Keys | Command |
|---|---|
| Enter | Open the selected session |

### Session tab

| Keys | Command |
|---|---|
| ↑ | Louder level |
| ↓ | Quieter level |
| ← | Previous series |
| → | Next series |
| Enter | Open series |

### Grid tab

| Keys | Command |
|---|---|
| ↑ | Louder level |
| ↓ | Quieter level |
| ← | Previous series |
| → | Next series |
| PgUp | Previous series |
| PgDn | Next series |
| Enter | Open series |
| Shift+Enter | Open condition in Trials |
| a | Accept fit |
| t | Threshold at selected level |
| i | No response |
| Alt+↓ | All levels respond |
| x | Exclude (then note) |
| c | Clear decision |
| d | Cycle detection override (auto → response → none) |
| n | Normalise traces |
| = or Shift+= or Num + or + | Scale up |
| − or Num − or - | Scale down |
| Shift+↑ | More stack spacing |
| Shift+↓ | Less stack spacing |
| Ctrl+0 | Reset zoom |

Mouse on the Grid tab:

| Mouse | Command |
|---|---|
| Drag the green line | Set the threshold: snaps half way between the two levels (the decision t makes on the louder); Alt held, the exact value (0.1 dB); above the loudest level, no response; below the quietest, all respond; Esc cancels, Ctrl+Z undoes |
| Click a trace | Select that condition |
| Double-click a trace | Open the Series tab on it |

### Series tab

| Keys | Command |
|---|---|
| ↑ | Louder level |
| ↓ | Quieter level |
| PgUp | Previous series |
| PgDn | Next series |
| ← | Previous candidate when a wave point is selected, else previous series |
| → | Next candidate when a wave point is selected, else next series |
| Shift+Enter | Open condition in Trials |
| a | Accept fit |
| t | Threshold at selected level |
| i | No response |
| Alt+↓ | All levels respond |
| x | Exclude (then note) |
| c | Clear decision |
| d | Cycle detection override (auto → response → none) |
| p | Auto-pick series |
| u | Re-track down |
| Shift+U | Re-track down, overwriting manual picks |
| 1 | Select wave I peak |
| 2 | Select wave II peak |
| 3 | Select wave III peak |
| 4 | Select wave IV peak |
| 5 | Select wave V peak |
| Shift+1 | Select wave I trough |
| Shift+2 | Select wave II trough |
| Shift+3 | Select wave III trough |
| Shift+4 | Select wave IV trough |
| Shift+5 | Select wave V trough |
| Alt+← or Shift+← | Nudge one sample earlier |
| Alt+→ or Shift+→ | Nudge one sample later |
| Delete | Wave absent here |
| Shift+Delete | Wave absent here and below |
| Backspace | Back to automatic pick |
| n | Normalise traces |
| = or Shift+= or Num + or + | Scale up |
| − or Num − or - | Scale down |
| Shift+↑ | More stack spacing |
| Shift+↓ | Less stack spacing |
| Ctrl+0 | Reset zoom |

Mouse on the Series tab:

| Mouse | Command |
|---|---|
| Drag the green line | Set the threshold: snaps half way between the two levels (the decision t makes on the louder); Alt held, the exact value (0.1 dB); above the loudest level, no response; below the quietest, all respond; Esc cancels, Ctrl+Z undoes |
| Click or drag on the evidence plot's level axis | Set the threshold there, by the same rules (drag its green line, or click the band of sweep counts along the bottom) |
| Click a trace | Select that level; on the selected level, with a wave point selected, move the point to the nearest extremum |
| Drag the selected wave point | Place it exactly where it is let go |

### Trials tab

| Keys | Command |
|---|---|
| ↑ | Louder level |
| ↓ | Quieter level |
| ← | Previous series |
| → | Next series |
| PgUp | Previous series |
| PgDn | Next series |
| = or Shift+= or Num + or + | Scale up |
| − or Num − or - | Scale down |
| Ctrl+0 | Reset zoom |
| r | Reject selected sweeps |
| Shift+R | Restore selected sweeps |

The **i** key means *no response* on every tab, and **n** means *normalise*. No unmodified letter does one thing on one tab and another thing elsewhere.

## Files written

Everything the app writes goes into the results folder, `<study>\MABR_Analysis\`, or the folder you chose in Settings ▸ Results Folder…. Nothing is ever written next to the recordings.

| Path | What it is |
|---|---|
| `project.mat` | the study: labels (timepoints, groups, your own columns), pools, in-study flags, per-session overrides, the duplicate policy, the review queue, and the project's settings. One variable, `MABRAnalysisProject`. Saved atomically. When two windows save at once it reloads and merges row by row, the later edit of a row winning. |
| `<subject>\<session>.mat` | one session's **results v2**, named by the session's path under the study. Holds the settings and per-step state, the files, the conditions and measures, the condition means (in double precision, so a session opened from its results re-picks exactly the peaks its raw files give), per-sweep info, the detections, the thresholds with their curation, the peaks, every edit table and the messages. No raw sweeps, so a 54-condition session is well under 2 MB. Separate variables, so the small parts load alone. |
| `<subject>\pooled\<first>+<n>_<hash>.mat` | the results of a pool |
| `.history\<session>_<yyMMddTHHmmss>.mat` | the previous results file, kept before a re-analysis replaced it (newest 3) |
| `.history\<session>_unreadable_<yyMMddTHHmmss>.mat` | a results file the app could not read, copied aside before the session was opened from its raw files; never pruned |
| `logs\batch_<yyMMddTHHmmss>.csv` | one line per session per batch: key, status, seconds, message, settings hash, results file |
| `figures\<session>.png` | batch summary figures, when asked for |
| `exports\<yyMMddTHHmmss>\` | an export: `mabr_<table>.csv` / `.parquet` / `mabr_tables.xlsx` / `mabr_export.mat`, `mabr_columns.csv`, `mabr_import.R`, `mabr_export.json`, `mabr_settings.json`, `replicate_analysis.m` |
| `scripts\<name>_replicate.m` | File ▸ Export Analysis Script… |

Elsewhere:

- The **catalog cache** goes in `%LOCALAPPDATA%\MABR\AnalysisCache\catalog_<hash>.mat`. It is only a cache: delete it and the next scan rebuilds it.
- **Settings files** (`.mabraset`) go wherever you save them.
- **Messages** go to MABR's daily log in `.error_logs\` (Help ▸ Open Log Folder).
- **Window positions and looks** are kept in MATLAB prefs (group `MABR`):
  - `OfflineAnalysisSettings` (the default for new projects);
  - the five tabs' looks;
  - the export and figure-export choices;
  - recent folders and results-folder choices;
  - the last state, the analyst name, and `WindowPos_OfflineAnalysis*`.
- A MABR **configuration** (`.mabrcfg`) carries the analysis defaults: the new-project settings, the tabs' looks and the export choices. Loading one in MABR applies them to an open analysis window's tabs. It never changes an open project's settings. Recent folders and other history are in no configuration.

Results files are what Study, Export and Batch read. A results file written by a newer MABR is read for what this version knows, with a warning in the session's messages. A results file that cannot be read at all is never overwritten unseen: the app opens the session from its raw files and keeps the file as `_unreadable_` in `.history`, and a batch analyses the session afresh and keeps the old file in `.history` as usual. A `project.mat` that cannot be read, or was written by a newer MABR, opens the store read-only (see [What is written where](#what-is-written-where)).

---

## Developer notes

### Layering

| Layer | Where | Graphics? |
|---|---|---|
| Model classes | `+mabr/+analysis/` (`Session`, `Settings`, `SeriesThreshold`, `SingleTrial`, `Peaks`, `Catalog`, `Project`, `Batch`, `Export`, `ScriptWriter`, `AbrFile`, `Stats`) | none |
| App state | `mabr.ui.analysis.Model` | none (it drives the whole app from a script or a test) |
| Window | `mabr.ui.AnalysisApp` | the shell: menus, toolbar, header, bar, tabs, keys |
| Views | `mabr.ui.analysis.{Browser, SessionView, GridView, SeriesView, TrialView, StudyView}` | one per tab, built the first time it is shown |
| Dialogs | `SettingsDialog, ExportDialog, BatchDialog, BatchReport, ReviewDialog, LevelsDialog, PromptDialog, FigureExport` | non-blocking windows |

**Views never change a Session.** They call Model methods, and every Model method is undoable, autosaved, and announced by an event. Views read `model.Session` at refresh time and never cache it.

**Keys, not rows.** A condition is identified by its key, such as `Stimulus=Tone|AcqMode=conventional|Frequency=8|Level=80`, and a series by the same key without the level. Curation, overrides and manual rejections are stored by key, or by `FileId` + sweep index. That is how they survive a re-segmentation that moves every row. A parameter a stimulus lacks is left out of its key, so a click and a tone never share a condition. A series key always holds Stimulus and, unless the modes are pooled, AcqMode, whatever *Group series by* says (`mabr.analysis.Session.seriesGrouping`).

**Time.** Every time axis goes through `View.timeAxis`/`earTime`/`rawTime`. With a latency offset the axes are in ear time, and everything drawn on them (traces, picks, wave windows) is at raw time minus the offset; a click is converted back to raw time before it reaches `Model.setPeak`. The model searches and stores in raw time, and `mabr.analysis.Peaks.reported` is the one place the offset comes off.

**Atomic steps.** Every Session step computes into locals and commits in one block. A cancel is a progress sink throwing `mabr:analysis:cancelled`, so a cancelled step changes nothing, and the status line says "Cancelled during … — nothing changed". `Model.runJob` is the one place that turns a long call into a progress window with Cancel.

### Events

Events carry a `mabr.ui.analysis.ChangeData` (`What`, `Keys`, `Text`, `Level`, `Source`), in a fixed order per Model method:

| Model method | Events, in this order |
|---|---|
| openRoot, rescan | BusyChanged(busy) → RootChanged → ProjectChanged(all) → SettingsChanged → StatusChanged → BusyChanged(idle) |
| openSession, openAdjacent, nextInQueue | [BusyChanged(busy)] → SessionChanged → SelectionChanged → StatusChanged → [BusyChanged(idle)] |
| analyze, refit, ensureRaw, applyFileUse, setSessionOverrides | BusyChanged(busy) → ResultsChanged(all) → StatusChanged → BusyChanged(idle) |
| setSettings, applyProfile | SettingsChanged → [ResultsChanged(thresholds) when re-fitted] → StatusChanged |
| threshold curation | ResultsChanged(curation, Keys = series) → StatusChanged(save) |
| peak edits | ResultsChanged(peaks, Keys = the series' conditions) → StatusChanged(save) |
| rejections | BusyChanged(busy) → ResultsChanged(rejection) → StatusChanged(save) → BusyChanged(idle) |
| labels, columns, pools | ProjectChanged(labels / columns / pools, Keys) → StatusChanged(save) |
| undo, redo | the events of the action undone |

`SessionChanged` means "rebuild everything". A hidden tab only marks itself dirty and redraws when it is shown.

### Key routing and the R2021b floor

`AnalysisApp.dispatchKey` follows one rule. Letters reach a command only while `Model.KeyTarget == "plot"` and the current object is not a text component; Ctrl and F-key chords always do. Every component callback goes through `app.cb(fcn,area)`, which records whether the user is in the workspace or the browser.

Anything newer than R2021b is reached only through `mabr.ui.analysis.Compat`, such as double-click callbacks, `focus`, placeholders, row selection and themes. Each call there checks `isprop`/`try` before using the newer feature. `verify_offline_app` scans every other GUI file for those identifiers and plants one to prove the scan can fail.

**The mouse.** The window's `WindowButtonMotionFcn` asks the active view for the pointer it wants there (`View.hoverPointer`: the resize arrows over a threshold divider), and sets it only when it changes (`Compat.setPointer`, which never errors). A threshold drag is one `mabr.ui.analysis.ThresholdDrag`: the view makes it on a press over its divider and the drag owns the window's motion, button-up and key callbacks until the release, then puts them back. Its rule is a pure static (`ThresholdDrag.outcome`), and its decision goes through the same Model call as the matching button (`ThresholdDrag.apply`). The verification scripts drive it as MATLAB would: they set the figure's `CurrentPoint`, which the axes' `CurrentPoint` follows, and call those callbacks.

**`tests/manual/spike_uifigure_input.m`** is the one check a script cannot make. It reports which callbacks fire, in which order, when a person types into an edit field, edits a table cell, arrows through a tree, and clicks an axes then presses keys. Run it once on R2021b and once on the release in use. It is not part of the suite.

### Prefs and windows

Prefs are written **only** from a control a user operated, never from a setter, a constructor, or a Model method a script calls. `mabr.ui.AnalysisApp.prefKeys()` lists every key the app may write. Every window restores and remembers its position through `mabr.ui.WindowPos`.

### Testing

The verification scripts are `verify_offline_*`: files, stats, thresholds, session, analyze, catalog, export, script, app, browser, grid, series, trials, study and dialogs. See [Testing](Testing.md#offline-analysis). They run on synthetic data with known truth (`mabrtest.SyntheticABR`). The view tests share a small analysed study (`mabrtest.OfflineFixture`) and guard every pref (`mabrtest.prefGuard`). Every window is invisible, every dialog is stubbed, and timers are off (`AutoRefresh=false`, `flush()`).

`tests/smoke_offline_analysis.m` runs the same classes and window over the real study folder. It asserts that the folder is unchanged afterwards.
