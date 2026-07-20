# Data Format

## The `.abr` file

Despite the extension, `.abr` files are **MATLAB v5 MAT-files** containing a single `ABR_Data` struct. Load them with:

```matlab
load(file,'-mat')
```

`*.abr` is gitignored, as are `.runtime_data/` and `*.asv`.

## `ABR_Data` fields

Written by `mabr.data.io.writeABR`. The offline pipeline reads exactly these:

| Field | Contents |
| --- | --- |
| `ADC.SampleRate` | Hz, **post-decimation** (12000 by default) |
| `ADC.Data` | `single` column vector |
| `ADC.SweepOnsets` | indices into `ADC.Data` |
| `ADC.SweepLength` | sweep window length in samples |
| `StartTime` | `datetime`-parseable char, `yyyy-MM-dd'T'HH:mm:ss` |
| `SIG.informativeParams` | cellstr of parameter names |
| `SIG.(param)` | one numeric value per informative param |
| `SIG.Label` | cellstr; also drives the filename |

Harmless extras the offline pipeline ignores: `SoftwareVersion`, `DataVersion`, `DecimationFactor`, `DAC.SampleRate`.

### Decimation at save time

Preserved exactly as the legacy `save_abr_data` did: `resample(Data,1,df)`, `round(SweepOnsets/df)` (floored at 1, since onsets below `df/2` would otherwise round to an invalid index 0), and `ADC.SampleRate = SampleRate/df`.

## Filenames

Built by `mabr.data.io.buildFilename` to match the offline pipeline's default regex when the stimulus metadata carries `Frequency` and `Level`:

```
SUBJ_ID_<id>_Frequency_<f>kHz_Level_<L>dB_<yyMMdd'T'HHmmss>.abr
```

Frequency is formatted in kHz with `.` replaced by `_`. Without `Frequency`/`Level`, the filename falls back to the stimulus `ID` — which every entry supplies and which is far more legible than a joined `Label`.

Subject IDs not already starting with `SUBJ` get prefixed. The numeric part is preferred; a purely alphabetic ID falls back to a sanitized name (stripping non-digits from an alphabetic ID once collapsed every such subject onto one filename).

## The in-memory model (`+mabr/+data/`)

**`mabr.data.Recording`** (value) — one channel: `SampleRate`, `Data`, `SweepOnsets`, `SweepLength`, plus `SweepData` / `SweepMean` / `noisePower` / `SNR`. Ported from the legacy `abr.Buffer` but **cycle-free** — no back-reference to a parent object; the decimation factor is passed explicitly.

Filtering is **explicit and opt-in**. Call `designFilters()` once to build the chain; afterwards the filtered trace is used consistently through `ProcessedData → SweepData → SweepMean`. Before that call, raw `Data` is used. This resolves the legacy ambiguity where a bandpass/notch was designed in the live path but never applied.

Defaults: Butterworth bandpass HP 10 Hz / LP 3000 Hz, order 4 (clamped to [2 8] — a high-order IIR with a 10 Hz corner at 12 kHz is numerically fragile), plus a 60 Hz notch with 4 Hz −3 dB width. Optional `DetrendPoly` and `SmoothSpan` post-process `SweepMean`.

**`mabr.data.Block`** (value) — one condition's result: stimulus metadata + the recorded `Recording` + computed metrics + start time.

**`mabr.data.Session`** (handle) — subject/device/rate config, the block queue, and the array of `Block` results.

## Reading files back

```matlab
block = mabr.data.io.importLegacy('file.abr');
```

Reads both new files and **legacy** `ABR_Data` structs, including sigProp-style `SIG` where each parameter is a struct with a `.Value` field, unwrapping them to plain numerics. Throws `mabr:data:io:noABRData` if the file has no `ABR_Data`.

Round-tripping is covered by `tests/verify_data_roundtrip.m` and legacy reading by `tests/verify_legacy_import.m` — see [[Verification and Testing]].
