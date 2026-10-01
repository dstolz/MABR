# Data Files

## Where recordings go

One file per condition, written the moment that condition finishes. Nothing is buffered until the end of a session — if MATLAB crashes on the last condition, every earlier one is already safe on disk.

By default each **Start** gets a folder of its own under the **Output** folder, named for the subject and the moment Start was pressed:

```
<Output>\SUBJ-ID-1254\SUBJ-ID-1254_261001T143012\SUBJ-ID-1254_Frequency-8kHz_Level-30dB_261001T143015.abr
```

Every file that schedule writes — make-up, Loop and Repeat runs included — goes in that one folder, along with the `.notes` journal. The next Start makes a new one. A Preview writes nothing and makes no folder.

### Changing the folder pattern

**Settings ▸ Session Folders…** sets the pattern. It is a relative path, folders separated by `/` or `\`, with `{tokens}` filled in at Start:

| Token | Becomes | Example |
|---|---|---|
| `{Subject}` | Subject ID as typed | `SUBJ-ID-1254` |
| `{Date}` / `{Time}` | When Start was pressed, `yyMMdd` / `HHmmss` | `261001` / `143012` |
| `{Start:fmt}` | The same moment in any datetime format | `{Start:yyyy-MM-dd}` → `2026-10-01` |
| `{Bank}` | Stimulus bank name (its file name; `demo` / `designer` without one) | `tones_8-32k` |
| `{Strategy}` | Presentation strategy | `conventional` |
| `{Mode}` | `TestMode` or `StimOnly`; nothing for an ordinary recording | `TestMode` |
| `{User}` | Windows login | `dstolz` |
| `{ID}` | Stimulus ID | `Tone_8000_30` |
| `{<parameter>}` | Any stimulus parameter by name; a number may carry a printf format | `{Frequency}kHz`, `{Level:%03g}dB` |

The default is `{Subject}/{Subject}_{Date}T{Time}`. The dialog offers presets, inserts tokens, and previews the folder from the current subject, bank and Output folder.

- A token that comes out empty takes the separator next to it along (`{Subject}_{Mode}` is `SUBJ-ID-1254` for an ordinary run), and a folder level that comes out empty is dropped.
- Characters a Windows folder name cannot hold become `-`. A value can never add a folder level.
- `{ID}` and stimulus parameters make a folder level **per condition**. The notes journal, and the stimulation log (`_STIM_` `.mat`) of a run presenting several stimuli, go in the level above. Offline analysis reads each folder of `.abr` files as one session, so a per-condition level splits a session's data across folders.
- Switch the scheme off to write every file straight into the Output folder, as MABR did before. The pattern is kept while it is off.
- File **names** never change — they still match the offline pipeline's pattern below.

The setting is remembered between sessions and saved in a `.mabrcfg` configuration.

## Filenames

```
SUBJ-ID-001_Frequency-8kHz_Level-30dB_260720T141530.abr
└───┬────┘ └──────┬──────┘ └────┬────┘ └─────┬──────┘
 subject     frequency        level      timestamp
                                      (yyMMdd'T'HHmmss)
```

**The filename is data, not decoration.** The offline analysis pipeline reads the stimulus parameters back out of it by pattern-matching. Renaming files, or flattening folders in a way that creates name collisions, will break batch analysis.

Notes on the format:

- **Underscores separate tokens, and only tokens**: subject, each parameter, timestamp. Inside a token the parts are joined by hyphens (`SUBJ-ID-001`, `Frequency-8kHz`), so a name splits unambiguously on `_`.
- A decimal point in a value is written `p` and a minus sign `m`: 11.3 kHz → `Frequency-11p3kHz`, −10 dB → `Level-m10dB`.
- A subject ID typed with underscores is written with hyphens: `SUBJ_ID_42` → `SUBJ-ID-42`.
- Conditions that are not frequency/level pairs are named by their stimulus ID instead, as one hyphenated token (`Click_80dB` → `Click-80dB`).
- Files written before this naming (`SUBJ_ID_001_Frequency_8kHz_Level_30dB_….abr`) do not match the strict pattern under *Developer notes*. `parseABRFiles`' default (`^SUBJ*`) and `mabr.analysis.Session` still read them.
- The timestamp is when the condition started, so files sort chronologically within a subject.
- **No file is ever overwritten.** The timestamp resolves whole seconds, so two runs of the same condition started within one second — short passes of a looped run, or a Repeat pressed straight after a run — would share a name. The later file is written as `…_260720T141530_2.abr` (then `_3`, …) and the log says so; the timestamp still says when the run started, and `ABR_Data.StartTime` inside the file is unchanged. The suffixed name does **not** match the strict pattern under *Developer notes* below, which ends at the timestamp — a script filtering on that pattern must allow `(_\d+)?` before `\.abr` to see such a file. `parseABRFiles`' default (`^SUBJ*`) and `mabr.analysis.Session`'s (`\.abr$`) see it as they are.

## Organizing folders

The offline tools treat **each folder containing `.abr` files as one session**. A layout that works well:

```
abr_data/
├── SUBJ-ID-001/
│   ├── SUBJ-ID-001_Frequency-8kHz_Level-30dB_260720T141530.abr
│   └── ...
└── SUBJ-ID-002/
    └── ...
```

Point the batch analysis at `abr_data/` and it discovers every session below it.

## What is inside a file

Despite the extension, a `.abr` file is an ordinary MATLAB MAT-file holding one variable, `ABR_Data`. Open one directly:

```matlab
>> load('SUBJ-ID-001_Frequency-8kHz_Level-30dB_260720T141530.abr','-mat')
>> ABR_Data.ADC
```

The parts you are likely to want:

| Field | Contents |
|-------|----------|
| `ABR_Data.ADC.Data` | The full recorded trace for this condition, one continuous vector |
| `ABR_Data.ADC.SampleRate` | Sample rate of that trace, in Hz (12000 by default) |
| `ABR_Data.ADC.SweepOnsets` | Sample index of each sweep's start, for cutting the trace into sweeps |
| `ABR_Data.ADC.SweepLength` | Sweep length in samples |
| `ABR_Data.StartTime` | When the condition started |
| `ABR_Data.SIG` | Stimulus parameters — frequency, level, and a `Label` for display |
| `ABR_Data.TestMode` | `true` if the file came out of [Test Mode](Test-Mode.md) — the samples are the stimulus, not a recording of a subject. Always present; `false` for an ordinary run |
| `ABR_Data.SoftwareVersion` | The MABR version that wrote the file |

The file stores the **whole continuous recording plus the onset indices**, not pre-cut sweeps. This means you can re-window, re-filter, or re-reject artifacts later without re-recording — the offline pipeline does exactly that.

To get an averaged waveform out of a file in two lines:

```matlab
b = mabr.data.io.importLegacy('yourfile.abr');   % also reads current files
plot(b.ADC.TimeVector, b.ADC.SweepMean)
```

## Stimulation-only files

Under **stimulation only** nothing is recorded, so no `.abr` is written. Each run saves what it played instead: a MAT-file named like its `.abr`, with `STIM` after the subject.

```
SUBJ-ID-001_STIM_Frequency-8kHz_Level-30dB_260720T141530.mat     one stimulus in the run
SUBJ-ID-001_STIM_Run-1_260720T141530.mat                          several stimuli intermixed
```

The `.mat` extension keeps these files out of anything that reads a folder of `.abr` files as recordings. Each holds one variable, `MABR_StimLog`:

| Field | Contents |
|-------|----------|
| `MABR_StimLog.Sequence` | One entry per trial, in play order: `Order`, `StimulusIndex`, `ID`, `Polarity`, `OnsetSample`, `OnsetTime` (s from the start of the run, which is when that trial's timing pulse went out), `Presented` (false for trials an early stop never reached), then one column per stimulus parameter (`Frequency`, `Level`, …) |
| `MABR_StimLog.Parameters` | The names of those stimulus-parameter columns |
| `MABR_StimLog.Stimuli` | Each stimulus the run played, with its full parameters (`SIG`, as in a `.abr`) and how many times it went out |
| `MABR_StimLog.Notes` | The session's notes, all of them, as written up to that run |
| `MABR_StimLog.Presentation` | Strategy, ISI setting, and the silence before the first trial |

`Sequence` is a set of parallel arrays, so it reads as a table in one line:

```matlab
>> load('SUBJ-ID-001_STIM_Frequency-8kHz_Level-30dB_260720T141530.mat')
>> T = struct2table(structfun(@(c) c(:), MABR_StimLog.Sequence, 'UniformOutput', false))
```

## Sample rates

Sound is played and recorded at 192 kHz, but stored at 12 kHz. ABRs contain nothing above a few kHz, so the recording is downsampled before saving — a 40-fold reduction in file size with no loss of relevant signal. The stored `SampleRate` always reflects what is actually in `Data`.

## Runtime files (safe to ignore)

`.runtime_data/` holds the memory-mapped streaming buffers, reused every session and not tied to any recording. `.error_logs/` holds daily text logs. Neither needs backing up; both are excluded from version control. If disk space is tight, they can be deleted while MABR is closed and will be recreated.

---

## Developer notes

### The compatibility contract

[mabr.data.io](../+mabr/+data/io.m) writes files for a pipeline it does not control. The offline `abr_analysis/` code reads **exactly** these fields:

```
ABR_Data.ADC.SampleRate        ABR_Data.SIG.informativeParams
ABR_Data.ADC.Data              ABR_Data.SIG.(param)   one per informativeParam
ABR_Data.ADC.SweepOnsets       ABR_Data.SIG.Label
ABR_Data.StartTime
```

plus a filename matching:

```
^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr
```

Anything else in the struct is provenance and is ignored downstream. [verify_data_roundtrip.m](../tests/verify_data_roundtrip.m) asserts both halves of this contract and, when `parfor_progress` is available, runs the real pipeline functions over freshly written files. **Run it after any change to `io`.**

### Decimation

Decimation happens once, at block finalization in `AcqController.finalize_block`: the raw ring-buffer trace is resampled from the DAC rate to `Config.ADCSampleRate` and onsets are divided by `Config.decimationFactor`, floored at 1 (an onset below `df/2` would round to 0, an invalid index downstream). The resulting `Recording` carries `DecimationFactor = 1`, so `io.writeABR` saves it as-is.

`io.buildStruct` can also decimate at save time when handed a `Recording` still at the DAC rate — the path `verify_data_roundtrip` exercises, and the behavior the legacy `save_abr_data` had. Both routes produce the same 12 kHz file; do not apply both.

### Reading files back

`io.importLegacy` handles both current files and legacy ones, including `SIG` fields stored as sigProp-style structs with a `.Value` field (unwrapped by `plainValue`). It returns a fully-formed [mabr.data.Block](../+mabr/+data/Block.m), so imported data flows into the same viewers and metrics as freshly acquired data. See [verify_legacy_import.m](../tests/verify_legacy_import.m).

### Filtering on load

An imported `Recording` starts **unfiltered** — `designFilters()` has not been called, so `ProcessedData` returns the raw `Data`. To apply the standard chain:

```matlab
b = mabr.data.io.importLegacy(f);
r = b.ADC;
r.Filters = mabr.FilterPolicy;      % 10–3000 Hz + 60 Hz notch
r = r.designFilters();              % value class: reassign
b.ADC = r;
```

`Recording` is a value type; every mutating call returns a new object.

The three sections are independent, so a file can be re-examined under any chain without reloading it — and `Data` is never touched, so you can go back:

```matlab
r.Filters = mabr.FilterPolicy(100,1500,false);   % HP 100, LP 1500, no notch
r.Filters = mabr.FilterPolicy(false,false,60);   % notch only
r = r.designFilters();
```
