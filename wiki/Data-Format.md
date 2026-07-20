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

Two more fields are always written for offline analysis. The stock pipeline does not read them, but they are what lets analysis code tell stimulus polarities apart:

| Field | Contents |
| --- | --- |
| `ADC.SweepPolarity` | `+1`/`-1` per sweep, aligned element-for-element with `ADC.SweepOnsets` |
| `SIG.alternatePolarity` | `0`/`1` — whether this condition was presented with alternating polarity |

Both are unconditional, so analysis code can read them without testing for their existence: a fixed-polarity condition writes all `+1` and `0`. `SIG.alternatePolarity` is deliberately **not** listed in `informativeParams` — those become grouping dimensions in `extractABRResponses`, and this describes how a condition was run rather than defining a separate condition. Files written before this field existed import as all `+1` (see `mabr.data.io.importLegacy`).

Working with the two polarities offline:

```matlab
a = load(f,'-mat','ABR_Data'); D = a.ABR_Data;
p = D.ADC.SweepPolarity;          % aligned with D.ADC.SweepOnsets
% ... segment into sweeps S [nSamples x nSweeps] as extractABRResponses does
cond = mean(S(:,p ==  1),2);      % condensation
rare = mean(S(:,p == -1),2);      % rarefaction
abrs = mean(S,2);                 % standard alternating average
```

Note that `extractABRResponses` **drops** sweeps whose window falls outside the trace, so its returned columns do not always correspond one-to-one with `SweepPolarity`. Segment from `ADC.Data`/`ADC.SweepOnsets` directly when you need the pairing to hold.

Harmless extras the offline pipeline ignores: `SoftwareVersion`, `DataVersion`, `DecimationFactor`, `DAC.SampleRate`.

### Decimation at save time

Preserved exactly as the legacy `save_abr_data` did: `resample(Data,1,df)`, `round(SweepOnsets/df)` (floored at 1, since onsets below `df/2` would otherwise round to an invalid index 0), and `ADC.SampleRate = SampleRate/df`. Decimation moves onsets but never changes how many there are, so `SweepPolarity` passes through untouched and stays aligned.

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
