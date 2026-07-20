# MABR

**M**ATLAB **A**uditory **B**rainstem **R**esponse — a Windows-only MATLAB toolbox for presenting acoustic stimuli and acquiring, viewing, and analyzing ABR electrophysiology data.

```matlab
>> MABR        % launch the acquisition app
```

## What it does

MABR plays a calibrated stimulus, records the evoked response in lock-step with it, and saves each stimulus condition to its own file as soon as it finishes. A live view shows the response averaging together as it accumulates, and conditions can stop automatically the moment a reproducible response is detected rather than always running a fixed number of sweeps. A separate batch pipeline turns folders of saved recordings into hearing thresholds.

MABR does **not** generate or calibrate sounds. An external package supplies pre-computed, calibrated waveforms through a small documented contract — a struct array in which each entry is one stimulus (`signal` + `ID`) — which keeps rig-specific acoustic calibration out of the acquisition path. A built-in uncalibrated tone-pip bank is included so the software can be run and tested without one.

MABR **does** own presentation: the inter-stimulus interval, how many times each stimulus repeats, and how stimuli are combined (blocked, interleaved, or shuffled) are all chosen in the app, per session. Shuffled and interleaved schedules intermix conditions within a single continuous run to remove drift and order effects; MABR separates the recorded sweeps afterwards, so you still get one file per stimulus condition. Shuffling reorders a fixed set of presentations — it never changes how many times a stimulus is played.

## Requirements

Windows, MATLAB R2019b or newer, and the Signal Processing, Audio, DSP System, and **Parallel Computing** toolboxes. Recording needs an ASIO audio device with two output and two input channels. See [Installation](docs/Installation.md).

Verify a working setup with no hardware attached:

```matlab
>> run_all_verifications
```

## Documentation

Full documentation is in [`docs/`](docs/), written at two levels — a plain-language track for running experiments, and developer notes on each page for extending the code.

### Running experiments

| Page | Covers |
| ---- | ------ |
| [Installation](docs/Installation.md) | Requirements, setup, verifying it works |
| [Getting Started](docs/Getting-Started.md) | Your first recording, start to finish |
| [The Acquisition App](docs/Acquisition-App.md) | Every control in the main window |
| [Viewing Data](docs/Viewing-Data.md) | Live plot and Trace Organizer |
| [Data Files](docs/Data-Files.md) | Where files go, naming, and what's inside |
| [Offline Analysis](docs/Offline-Analysis.md) | Batch processing to thresholds |
| [Troubleshooting](docs/Troubleshooting.md) | Common problems and what they mean |

### Development

| Page | Covers |
| ---- | ------ |
| [Architecture](docs/Architecture.md) | How the pieces fit and why |
| [Acquisition Engine](docs/Acquisition-Engine.md) | Worker, ring buffer, command/state protocol |
| [Extending MABR](docs/Extending.md) | Supplying stimuli, presentation strategies, advance criteria, custom front ends |
| [API Reference](docs/API-Reference.md) | Every class and function, with links |
| [Testing](docs/Testing.md) | The no-hardware verification suite |

## Layout

```text
MABR.m              launcher
+mabr/              the toolbox
  +acq/               acquisition engine (parpool worker + ring buffer)
  +data/              data model and .abr file IO
  +stim/              stimulus contract, presentation schedule, advance criteria
  +metrics/           pure, tested signal metrics
  +ui/                acquisition app, live plot, trace organizer
  +log/               verbosity-gated logging
  Config.m            hardware constants and runtime paths
abr_analysis/       offline batch pipeline (separate, function-based)
tests/              no-hardware verification suite
docs/               documentation
helpers/, external/ utilities and third-party code
```

The acquisition app was rewritten ground-up into the single `+mabr` namespace; the legacy `+abr` package was retired at cutover and is recoverable from git history or the `master` branch. Saved `.abr` files remain compatible with the unchanged offline pipeline, and a test enforces that. [MABR Complete Refactor — Ground-Up Rewrite.md](MABR%20Complete%20Refactor%20—%20Ground-Up%20Rewrite.md) records the design rationale; [CLAUDE.md](CLAUDE.md) is a condensed architecture map.

## License

Proprietary. Copyright © Daniel Stolzberg, PhD — All Rights Reserved. Unauthorized copying via any medium is strictly prohibited. See [Copyright.txt](Copyright.txt).

Please contact me directly if you are interested in using this toolbox — <dstolz@umd.edu>.
