# Troubleshooting

## Starting up

**"MABR is Windows-only"** — MABR uses ASIO audio and Windows process APIs. There is no macOS or Linux path.

**A missing-toolbox error when the app opens** — The message names what is missing and the minimum version. All five listed in [Installation](Installation.md) are required; the Parallel Computing Toolbox in particular is not optional, because acquisition runs on a parallel worker.

**"Timed out waiting for the acquisition worker handshake"** — The background worker did not start. Usually one of:

- The parallel pool could not start. Test with `>> parpool('Processes',1)` and fix whatever that reports.
- A pool was already running that was started before MABR was on the path. Run `>> delete(gcp('nocreate'))` and try again.
- Another MATLAB session is holding the pool or the audio device. Close it.

**The first Start takes 30+ seconds** — Expected. The parallel pool is starting. It stays warm for the rest of the session, so subsequent blocks begin immediately.

## Audio and recording

**No audio device / device errors** — MABR needs an **ASIO** driver. Check MATLAB can see it:

```matlab
>> aPR = audioPlayerRecorder; aPR.Device
>> getAudioDevices(audioPlayerRecorder)
```

If your device is absent, the ASIO driver is not installed or not selected. Manufacturer ASIO drivers are usually required; consumer WDM/DirectSound devices will not appear.

**Underruns or overruns reported in the command window** — The worker could not keep up with the audio stream. Close other applications, especially anything doing heavy disk or network work. Occasional underruns at the very start of a block are usually harmless; continuous ones mean the data is not trustworthy. MABR already raises the worker's process priority automatically.

**No sweeps counted — "Sweeps: 0" throughout a block** — The timing pulse is not being recorded. This is the most common rig problem. Check that:

- The timing output channel is physically routed back into the second input channel.
- Player and recorder channel mappings match your wiring (default `[1 2]` for both).
- The timing signal amplitude reaches the detection threshold — a heavily attenuated loop-back pulse can fall below it.

Confirm the software side is fine by ticking **Testing** and running: if sweeps count in loopback but not with hardware, the problem is in the wiring, not MABR.

**The live plot is flat, or noise only** — If the most recent sweep (blue) is flat, no signal is arriving: check electrode connections and the amplifier. If it is noisy but the running average never converges, the response may genuinely be absent (below threshold), or the timing pulses may be firing at the wrong times, so sweeps are being averaged out of alignment.

**Heavy 60 Hz in the recording** — MABR's notch filter is applied at finalization, not to the live view, so the live plot legitimately shows more line noise than the saved data. Persistent 60 Hz in saved data points at grounding in the rig.

## Data and files

**No files appear in the output folder** — The **Output** field is empty, or points somewhere unwritable. With no output path, blocks are recorded and held in memory but never saved.

**All files have the same name / files overwrite each other** — Filenames are built from subject ID, frequency, level, and timestamp. If your stimulus metadata lacks `Frequency` and `Level`, MABR falls back to a label-based name; if labels are also missing, names can collide. Supply `Meta.Frequency`, `Meta.Level`, and `Meta.informativeParams` — see [Extending MABR](Extending.md#supplying-stimuli).

**Offline analysis finds no files or wrong parameters** — Filenames are parsed to recover stimulus parameters. Renaming files breaks this. See [Data Files](Data-Files.md#filenames).

**`batchABRAnalysis` errors on its arguments** — Known and intentionally unfixed. Call the pipeline functions individually with name-value syntax; see [Offline Analysis](Offline-Analysis.md).

## During a session

**A condition never ends** — Under the correlation criterion, the threshold may be unreachable for that condition. The repetition count still bounds the run; if it is very large, the run takes a long time. Press **Advance** to move on. For custom criteria, always include a hard cap.

**Everything froze mid-block** — The live view runs on a timer that is protected against transient errors, so a frozen display usually means MATLAB itself is blocked. Check the command window for errors and `.error_logs/` for the day's log.

**I closed the window mid-recording** — Closing shuts down the worker and releases the device. The condition in progress is lost; every condition completed before it is already saved. Use **Abort** instead, which saves the current condition first.

## Getting more detail

Raise the log verbosity before reproducing a problem:

```matlab
>> global GVerbosity; GVerbosity = 2;    % 0 quiet … 3 very detailed
```

Level 3 prints a lot and can perturb acquisition timing — use it for diagnosis, not for real recordings. Everything printed is also written to a daily log in `.error_logs/`, which is the right thing to attach to a bug report.

**Suspect a stale runtime buffer** — Close MABR and delete `.runtime_data/`. It is recreated on the next run and holds no recorded data. MABR already recreates buffer files whose size on disk does not match expectations, so this is rarely needed.

## Ruling MABR out

The fastest way to separate a software problem from a rig problem: tick **Testing (loopback, no hardware)**, click **Test Stimulus**, and run. That path touches every part of the program except the audio device. If it works, the software is healthy and the problem is in hardware, wiring, or the stimulus file. If it fails, run `>> run_all_verifications` — see [Testing](Testing.md).
