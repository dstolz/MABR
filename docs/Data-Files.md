# Data Files

## Where recordings go

One file per condition, written to the **Output** folder the moment that condition finishes. Nothing is buffered until the end of a session — if MATLAB crashes on the last condition, every earlier one is already safe on disk.

## Filenames

```
SUBJ_ID_001_Frequency_8kHz_Level_30dB_260720T141530.abr
└───┬────┘ └──────┬──────┘ └────┬────┘ └─────┬──────┘
 subject     frequency        level      timestamp
                                      (yyMMdd'T'HHmmss)
```

**The filename is data, not decoration.** The offline analysis pipeline reads the stimulus parameters back out of it by pattern-matching. Renaming files, or flattening folders in a way that creates name collisions, will break batch analysis.

Notes on the format:

- Decimal points become underscores: 11.3 kHz → `Frequency_11_3kHz`.
- Conditions that are not frequency/level pairs get a label-based name instead, built from the stimulus metadata.
- The timestamp is when the condition started, so files sort chronologically within a subject.

## Organizing folders

The offline tools treat **each folder containing `.abr` files as one session**. A layout that works well:

```
abr_data/
├── SUBJ_ID_001/
│   ├── SUBJ_ID_001_Frequency_8kHz_Level_30dB_260720T141530.abr
│   └── ...
└── SUBJ_ID_002/
    └── ...
```

Point the batch analysis at `abr_data/` and it discovers every session below it.

## What is inside a file

Despite the extension, a `.abr` file is an ordinary MATLAB MAT-file holding one variable, `ABR_Data`. Open one directly:

```matlab
>> load('SUBJ_ID_001_Frequency_8kHz_Level_30dB_260720T141530.abr','-mat')
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
| `ABR_Data.SoftwareVersion` | The MABR version that wrote the file |

The file stores the **whole continuous recording plus the onset indices**, not pre-cut sweeps. This means you can re-window, re-filter, or re-reject artifacts later without re-recording — the offline pipeline does exactly that.

To get an averaged waveform out of a file in two lines:

```matlab
b = mabr.data.io.importLegacy('yourfile.abr');   % also reads current files
plot(b.ADC.TimeVector, b.ADC.SweepMean)
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
^SUBJ_ID_(\d+)_Frequency_([\d_]+kHz)_Level_(\d+dB)_(\d{6}T\d{6})\.abr
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
