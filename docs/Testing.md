# Testing

MABR ships a verification suite that runs with **no audio hardware**. It requires the Parallel Computing Toolbox, because it exercises the real acquisition engine on a real parallel worker.

```matlab
>> run_all_verifications
```

```
== verify_engine_loopback ==
== verify_data_roundtrip ==
== verify_legacy_import ==
== verify_online_advance ==

==== 4 / 4 verifications passed ====
```

Each script is independently runnable. The first run is slow — the parallel pool has to start.

## What each one covers

### verify_engine_loopback

[tests/verify_engine_loopback.m](../tests/verify_engine_loopback.m) — the acquisition engine end to end in TESTING mode. Asserts that recorded frames land in the ring buffer, the write head advances during acquisition, and `Pause`/`Stop`/`Kill` sent over the queue take effect within about one frame.

This is the test that protects the core promise of the design: commands are honoured *during* playback, not between blocks.

### verify_data_roundtrip

[tests/verify_data_roundtrip.m](../tests/verify_data_roundtrip.m) — the `.abr` writer against the offline pipeline's contract. Builds a synthetic two-condition session, writes it with `io.writeABR`, then checks:

1. The `ABR_Data` struct exposes exactly the fields `abr_analysis/` reads.
2. The filename matches the pipeline's default regex.
3. If `parfor_progress` is installed, the **unmodified** pipeline functions `parseABRFiles` and `extractABRResponses` successfully load and group the files.

**Run this after any change to [io.m](../+mabr/+data/io.m).** A failure here means saved data is unreadable downstream — a breaking change, not a test to update.

### verify_legacy_import

[tests/verify_legacy_import.m](../tests/verify_legacy_import.m) — the import shim. Builds a legacy-shaped file with `SIG` stored as sigProp-style structs (a `.Value` field, as the old `abr.ABR.to_struct` produced) and confirms `io.importLegacy` unwraps them to plain numerics and that the reconstructed `Recording` segments sweeps identically to a direct index-based reference. Any real `.abr` found on disk is also imported as a structural smoke test.

### verify_online_advance

[tests/verify_online_advance.m](../tests/verify_online_advance.m) — early stopping and intermixing, in three parts. Part A checks the advance predicates in isolation. Part B drives the real `AcqController` in loopback with a **blocked** schedule and the correlation criterion, and asserts the run completes with far fewer sweeps than were scheduled. Part C schedules two stimuli with `shuffled-cycles` and asserts that one continuous intermixed run is de-interleaved back into one `Block` per stimulus ID, each with its full repetition count — and that the armed criterion does *not* fire, since intermixed runs play to completion.

Parts B and C are the only tests that exercise the full stack — controller, engine, worker, ring buffer, extraction, criterion, de-interleaving, finalization, save — in one pass.

### verify_stimgen_import

[tests/verify_stimgen_import.m](../tests/verify_stimgen_import.m) — the stimgen bridge. Asserts a 2×2 variant grid becomes four entries at the DAC rate, that `informativeParams` is the *declared* list rather than every numeric scalar, that a `.spl` bank round-trips with its levels and repetitions intact, and that `Frequency`/`Level` produce a filename matching the offline regex.

Its sharpest assertion is an FFT of every generated waveform against the `Frequency` its own metadata claims. stimgen's `VariantReselectOnUpdate` defaults true, so reading a parameter back *outside* an update cycle silently advances to the next variant — metadata and waveform come apart, and an 8 kHz tone is saved labelled 16 kHz. Nothing about the signal looks wrong; only the pairing is. Test the pairing, not the parts.

**Skips and passes** when the `external/stimgen` submodule was never fetched — an absent optional dependency is not a failure.

## Writing a new verification

Follow the existing pattern: a plain function, no test framework, `fprintf` a banner, `assert` with messages, clean up with `onCleanup`, and add it to the list in [run_all_verifications.m](../tests/run_all_verifications.m).

Two conventions matter for keeping tests hardware-free and deterministic:

- **Construct the engine with `testing = true`.** `mabr.acq.Engine(cfg,true)` or `mabr.ui.AcqController(cfg,true)` runs the entire program with no device, feeding the outgoing frame back as the recorded frame.
- **Use `TestingFrameDelay` to pace loopback.** Without a device, loopback runs as fast as MATLAB can loop, which can starve the 20 Hz live-view timer that evaluates advance criteria. `Schedule.TestingFrameDelay` inserts a per-frame pause so timing-dependent behaviour is observable. It has no effect outside testing mode.

- **Set `Schedule.Seed` for a reproducible order.** Shuffled strategies otherwise reshuffle each time, which makes a failure hard to reproduce. `verify_online_advance` pins it so the intermixed assertions are deterministic.

- **Reuse one `AcqController` across test phases.** A second `Engine` maps the same ring-buffer files and contends for the single-process pool. `verify_online_advance` runs both its end-to-end phases through one controller, recording `Session.NumBlocks` beforehand to tell the new blocks apart.

Prefer building deterministic stimuli inline (as `verify_engine_loopback` does with a 1 kHz tone and fixed onsets) over relying on `demoStimuli`, unless you are specifically testing the demo path.

## What is not covered

There is no automated test of the GUI, of real ASIO device behaviour, or of the offline analysis pipeline beyond the file-contract check in `verify_data_roundtrip`. Changes in those areas need manual verification on a rig.
