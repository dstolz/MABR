# Offline Analysis

`abr_analysis/` is a **separate, function-based batch pipeline** (authored `dstolz@umd.edu`, 2025). It is *not* part of the acquisition app and was untouched by the ground-up rewrite. It reprocesses saved `.abr` files.

## Flow

Driven by `batchABRAnalysis`:

```
getABRSessions
  → parseABRFiles            regex over filenames
  → extractABRResponses      load -mat, filter full trace, segment into sweeps by stimulus
  → rejectArtifacts
  → filterABRData
  → plotABRGrid
  → abrPermutationThreshold  permutation-test threshold via permtest
      → abrPermutationThresholdCuration
```

`parseABRFiles` matches the default filename pattern:

```
SUBJ_ID_<n>_Frequency_<f>kHz_Level_<L>dB_<yyMMdd'T'HHmmss>.abr
```

## What it reads

Exactly these fields, and nothing else:

- `ABR_Data.ADC.SampleRate` / `.Data` / `.SweepOnsets`
- `ABR_Data.StartTime`
- `ABR_Data.SIG.informativeParams`, the numeric named params, and `.Label`

`mabr.data.io.writeABR` emits precisely these; `tests/verify_data_roundtrip.m` confirms it. See [[Data Format]].

## ⚠️ Known stale-signature bug — do not fix

`batchABRAnalysis` calls `parseABRFiles` and `extractABRResponses` with **positional arguments that no longer match** their signatures.

This is a known issue and is deliberately left alone. **Call those functions directly with name-value syntax instead** of going through `batchABRAnalysis`.

## External dependency

`parfor_progress` is a MATLAB File Exchange dependency of this pipeline (not of the acquisition app).
