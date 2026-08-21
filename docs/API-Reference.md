# API Reference

Every public class and function, grouped by role and ordered roughly by the path data takes through the system: launch → stimulus → acquisition → metrics → data model → UI → offline analysis.

Small private helpers (`getdef`, `plainValue`, `version_key`, and similar) are omitted. Every file's own header comment is the authoritative reference — `>> help mabr.acq.Engine`.

## Entry point and configuration

| Item | Description |
|------|-------------|
| [`MABR`](../MABR.m) | Launcher. Adds all subfolders to the path (except `.git`) and opens `mabr.ui.App`. Windows-only. |
| [`mabr.Config`](../+mabr/Config.m) | Value object holding hardware constants, release metadata, required-toolbox list, and runtime paths. Not a superclass — nothing inherits from it. |

**`mabr.Config` surface**

| Member | Description |
|--------|-------------|
| `DACSampleRate` | 192000 Hz — playback and full-duplex record rate |
| `ADCSampleRate` | 12000 Hz — decimated storage/analysis rate |
| `frameLength` | 1024 samples per play/record frame |
| `maxInputBufferLength` | 2^26 samples — ring buffer length (~5.8 min at 192 kHz) |
| `RequiredToolboxes` | Name/minimum-version table checked at app startup |
| `decimationFactor` | Dependent: `DACSampleRate / ADCSampleRate` |
| `signalBufferFile`, `timingBufferFile`, `headerFile` | Dependent: ring-buffer backing file paths |
| `verifyToolboxes(doError)` | True when all requirements are met; errors informatively otherwise |
| `root()`, `runtimeDir()`, `errorLogDir()` | Static paths; the latter two create their folder on demand |

## Stimulus — `+mabr/+stim/`

| Item | Description |
|------|-------------|
| [`mabr.stim.StimulusSet`](../+mabr/+stim/StimulusSet.m) | **The contract.** A bank of single stimuli, wrapping the struct array the external package supplies (`signal` + `ID` per entry, everything else passed through). Inert — it holds waveforms and nothing about presentation. |
| [`mabr.stim.Schedule`](../+mabr/+stim/Schedule.m) | **Owns presentation.** Turns a `StimulusSet` plus ISI, repetitions, and a combination strategy into ordered runs, and renders each into the 2-channel play matrix the worker streams. |
| [`mabr.stim.demoStimuli`](../+mabr/+stim/demoStimuli.m) | Built-in tone-pip bank over a Frequency × Level grid. **Testing and demos only — uncalibrated.** Also the clearest worked example of the contract. |
| [`mabr.stim.fromStimgen`](../+mabr/+stim/fromStimgen.m) | **The stimgen bridge.** Converts a `.spl` bank, a live `StimPlayer`, a `StimPlay`, or a bare `StimType` into a `StimulusSet` — one stimgen *variant* per entry, regenerated at the DAC rate. |
| [`mabr.stim.stimgenAvailable`](../+mabr/+stim/stimgenAvailable.m) | `[tf,msg]` — is the `external/stimgen` submodule on the path? `msg` is actionable text for a disabled control's tooltip. |
| [`mabr.stim.CalibrationAdapter`](../+mabr/+stim/CalibrationAdapter.m) | Implements stimgen's `calibration.HwAdapter` against MABR's ASIO device, output channel, and `MicChannel`, so a calibration describes *this* rig. |

**`StimulusSet` surface**

| Member | Description |
|--------|-------------|
| `numStimuli()`, `IDs()`, `get(i)`, `signal(i)`, `id(i)`, `timing(i)` | The bank and its entries |
| `duration([i])`, `maxDuration()` | Single-presentation duration (s); `maxDuration` is the worst case for ISI overlap |
| `defaultRepetitions()` | Per-entry `Repetitions` where supplied, else `0` |
| `meta(i)` | Metadata struct for entry `i`: `ID`, every passthrough field, plus `informativeParams` (declared by the entry if it supplies one, else inferred from numeric scalars) and `Label` |
| `SampleRate` | Common DAC rate; construction errors unless it equals `Config.DACSampleRate` |
| `Source`, `describeSource()` | Provenance: `Kind` (`stimgen`/`file`/`demo`), `File`, `Calibration`, `Generated`. Read by the GUI's bank label and written into the `.abr`; nothing in acquisition uses it |
| `isCalibrated()` | True only when **every** entry was built against a measurement — half-calibrated is not a reportable state, since levels across the bank are then not comparable |
| `validate(s,idx,cfg)` | Static. Validates and normalizes one entry; specific error identifiers on a bad one |
| `fromFile(ffn,[cfg])` | Static. Loads a bank — `.spl` via `fromStimgen`, anything else as a `.mat`. What the GUI's **Load bank…** uses |

**`Schedule` surface**

| Member | Description |
|--------|-------------|
| `Strategies` | Constant. `blocked`, `shuffled-blocks`, `interleaved`, `shuffled-cycles`, `shuffled`. All are permutations of a fixed multiset — never probabilistic sampling |
| `ISI` | Inter-stimulus interval (s, onset-to-onset). Default `1/21.1` |
| `Repetitions` | Per-entry repetition counts; a scalar is broadcast to every entry |
| `Strategy`, `Seed` | How entries combine, and the shuffle seed (`[]` = fresh shuffle, via a private `RandStream`) |
| `build()` | (Re)build `Runs` from `Repetitions` + `Strategy`. **Required after changing either** |
| `NumRuns`, `current()`, `advance()`, `reset()`, `isComplete()` | Run walk; `advance` returns `[]` when finished |
| `runSequence(r)` | The stimulus index presented at each onset of run `r` |
| `runPolarity(r)` | The polarity (`+1`/`-1`) applied at each onset of run `r` |
| `renderSpec(r)` | Build the acquisition spec for run `r` — the argument to `Engine.prep` |
| `isIntermixed()` | True when one run mixes stimuli (the last three strategies) |
| `summary()` | Plan overview: `numRuns`, `presentations`, `repetitions`, `duration` (s), `intermixed` |
| `overlaps()` | True when the longest stimulus does not fit inside the ISI |
| `recordRun(r,counts)` | Record presentations actually acquired, per stimulus |
| `SilencePad`, `PlayerChannels`, `RecorderChannels`, `Device` | Padding and device/channel mapping |
| `TestingFrameDelay` | Per-frame pause used to pace loopback in tests only |
| `strategyIntermixes(s)` | Static. Whether strategy `s` intermixes — used by the GUI to gate early stop |
| `startingRepetitions(set)` | Static. Per-entry `Repetitions` where supplied, else `512` |

`renderSpec` adds `StimulusIndex` to the spec — the stimulus behind each onset, which `AcqController` uses to de-interleave an intermixed run at save time. It errors with `mabr:stim:Schedule:tooLong` if the run would exceed `Config.maxInputBufferLength`, checked **before** allocating.

### Advance criteria — `+mabr/+stim/+advance/`

Pure predicates over a context struct; return `true` to end the run. Evaluated **only for blocked strategies** — see [Extending MABR](Extending.md#defining-when-a-run-ends).

| Item | Description |
|------|-------------|
| [`num_sweeps(ctx)`](../+mabr/+stim/+advance/num_sweeps.m) | True once `ctx.numSweeps >= ctx.targetSweeps`. |
| [`corr_threshold(ctx)`](../+mabr/+stim/+advance/corr_threshold.m) | True once `ctx.corr >= ctx.corrThreshold` after `ctx.minSweeps`, or at `ctx.maxSweeps`. Enables mid-run early stopping. |

## Acquisition — `+mabr/+acq/`

| Item | Description |
|------|-------------|
| [`mabr.acq.Engine`](../+mabr/+acq/Engine.m) | **Client-side controller.** Keeps a warm 1-process pool, launches the worker, owns a read-only ring buffer view, and turns worker messages into events. Runs in the GUI process. |
| [`mabr.acq.worker_loop`](../+mabr/+acq/worker_loop.m) | **Runs on the worker.** Owns the `audioPlayerRecorder`, streams the play matrix frame-by-frame, writes into the ring buffer, polls for commands every frame. |
| [`mabr.acq.RingBuffer`](../+mabr/+acq/RingBuffer.m) | True circular buffer over three memory-mapped files. Worker writable, client read-only. |
| [`mabr.acq.Cmd`](../+mabr/+acq/Cmd.m) | Enumeration, client → worker: `Prep`, `Run`, `Pause`, `Resume`, `Stop`, `Kill`. |
| [`mabr.acq.State`](../+mabr/+acq/State.m) | Enumeration, worker → client: `Idle`, `Ready`, `Acquire`, `Paused`, `Completed`, `Error`. |
| [`mabr.acq.StateEventData`](../+mabr/+acq/StateEventData.m) | Event payload carrying `State`, and `Identifier`/`Message` for errors. |

**`Engine` surface**

| Member | Description |
|--------|-------------|
| `Engine(cfg,testing)` | Construct; `testing = true` runs hardware-free loopback |
| `waitUntilReady(timeout)` | One-time worker handshake. **The only bounded wait in the system** |
| `isReady()` | Whether the handshake has arrived |
| `prep(blockSpec)` | Arm a pre-rendered block |
| `run()`, `pause()`, `resume()`, `stop()`, `kill()` | Transport |
| `head()` | Current ring-buffer write head |
| `RingBuffer`, `State`, `WorkerPID`, `Testing` | Read-only properties |
| events `StateChanged`, `BlockCompleted`, `WorkerError` | Drive a UI from these; never poll |
| `ensure_pool()`, `set_priority(pid,level)` | Static utilities |

**`RingBuffer` surface** — `WriteHead` is a **monotonic sample count since `reset()`**, not a physical index; see [Acquisition Engine](Acquisition-Engine.md#ringbuffer).

| Member | Description |
|--------|-------------|
| `RingBuffer(cfg,writable)` | Open writable (worker) or read-only (client) |
| `reset()` | Start a new block: zero the head, increment `BlockSeq` |
| `writeFrame(sig,tim)` | Append one frame to both channels, wrapping as needed |
| `readSignal(lo,hi)`, `readTiming(lo,hi)` | Slice a monotonic absolute range |
| `readBlock()` | Whole retained block, chronological — used at finalization |
| `readSignalAt(idx)`, `readTimingAt(idx)` | Arbitrary indices, shape preserved |
| `WriteHead`, `BlockSeq`, `NumValid`, `MaxLength`, `Writable` | State |

## Metrics — `+mabr/+metrics/`

Pure, tested functions shared by the live and offline paths. Sweep matrices are `[nSamples x nSweeps]` unless noted.

| Item | Description |
|------|-------------|
| [`find_timing_onsets(timing,shadowSamples,threshold)`](../+mabr/+metrics/find_timing_onsets.m) | Sample indices of sweep onsets — the first sample reaching threshold on a rising edge. Positive signal only; onsets closer than `shadowSamples` are merged. |
| [`extract_sweeps(rb,params,state)`](../+mabr/+metrics/extract_sweeps.m) | Incrementally slice pre-/post-onset windows from the ring buffer. Returns `[pre,post,onsets,state,tvec]`; **the cursor is explicit state owned by the caller**. Matrices here are `[nSweeps x nSamples]`. `tvec.pre`/`tvec.post` are the columns' times in seconds relative to onset — contiguous, so `[pre post]` is one segment on the time base `[tvec.pre tvec.post]`. |
| [`partition_corr(preSweep,postSweep)`](../+mabr/+metrics/partition_corr.m) | Onset-contrast correlation driving the online advance criterion: split-half consistency of the response minus that of the baseline, floored at zero. After Arnold et al. (1985). |
| [`mean_pairwise_corr(D)`](../+mabr/+metrics/mean_pairwise_corr.m) | Fisher-z mean of all pairwise sweep correlations. |
| [`snr(D)`](../+mabr/+metrics/snr.m) | SNR in dB via plus/minus averaging: RMS of the mean sweep over RMS of the odd-minus-even difference. |
| [`rms_metric(D)`](../+mabr/+metrics/rms_metric.m) | Mean per-sweep RMS amplitude. Named to avoid shadowing SPT's `rms`. |
| [`find_peaks(meanTrace,npeaks,findNegative)`](../+mabr/+metrics/find_peaks.m) | Peak/trough finder for ABR wave marking. Returns `pks`/`locs`/`w`/`p`. Named to avoid shadowing SPT's `findpeaks`. |

## Data model — `+mabr/+data/`

| Item | Description |
|------|-------------|
| [`mabr.data.Recording`](../+mabr/+data/Recording.m) | **Value type.** One channel's samples plus sweep bookkeeping, segmentation, filtering, and metrics. Cycle-free — no back-reference to a parent. |
| [`mabr.data.Block`](../+mabr/+data/Block.m) | **Value type.** One condition: stimulus metadata + `Recording` + metrics + start time. |
| [`mabr.data.Session`](../+mabr/+data/Session.m) | **Handle type.** Subject/device config, block queue, and completed `Block` array. |
| [`mabr.data.io`](../+mabr/+data/io.m) | Static save/load. Writes offline-compatible `.abr` files; imports legacy ones. |

**`Recording` surface**

| Member | Description |
|--------|-------------|
| `Recording(Fs,Data,SweepOnsets,SweepLength,DecimationFactor)` | Construct |
| `designFilters()` | Design the enabled filter chain at the current rate. **Filtering is opt-in**; before this call the raw data is used |
| `applyFilter(x)` | Apply the designed chain zero-phase (`filtfilt`) |
| `ProcessedData` | Dependent: `Data` with the chain applied |
| `SweepData`, `NumSweeps` | Dependent: segmentation — **every** sweep, whatever its artifact verdict |
| `CleanSweeps`, `CleanSweepData`, `NumCleanSweeps` | Dependent: the same sweeps with the `IsArtifact` ones dropped (mapped through `ValidSweeps`) |
| `SweepMean` | Dependent: the averaged waveform, over `CleanSweepData`. All-NaN when every sweep was rejected |
| `noisePower`, `signalPower`, `SNR`, `RMS` | Dependent: metrics, also over `CleanSweepData` |
| `N`, `SweepDuration`, `TimeVector`, `NumArtifacts` | Dependent: sizes |
| `fft()` | FFT of the mean sweep; returns `[M,f]` |
| `to_struct()` | Plain-struct serialization |
| `Filters` | A `mabr.FilterPolicy` — independent high pass / low pass / notch (defaults: 10 Hz, 3000 Hz, 60 Hz). The same object the GUI edits and the live view applies |
| `DetrendPoly`, `SmoothSpan` | Post-processing applied to `SweepMean` |
| `IsArtifact`, `SweepValue`, `DecimationFactor` | Bookkeeping |

**`Block` surface** — `Stim`, `ADC`, `Timing`, `Metrics`, `StartTime`, `SweepPolarity` (`+1`/`-1` per sweep, aligned with `ADC.SweepOnsets`); dependent `NumSweeps`, `Label`; `computeMetrics()` populates `Metrics.corr`/`.rms`/`.snr` from the `+metrics` functions.

**`Session` surface** — `Subject`, `Device`, `DACSampleRate`, `ADCSampleRate`, `OutputPath`, `Queue`, `Blocks`, `StartTime`; dependent `DecimationFactor`, `NumBlocks`; `addBlock(block)`, `saveBlock(block,baseName)`.

**`io` surface**

| Member | Description |
|--------|-------------|
| `writeABR(block,outputPath,baseName)` | Write one block to an offline-compatible `.abr`; returns the full path |
| `buildStruct(block)` | Build the `ABR_Data` struct (decimating if `DecimationFactor > 1`) |
| `buildSIG(block)` | Flatten stimulus metadata into the offline-readable `SIG` substruct |
| `buildFilename(block,baseName)` | Name matching the pipeline's regex; label-based fallback |
| `importLegacy(ffn)` | Load a legacy **or** current `.abr` into a `mabr.data.Block`, unwrapping sigProp-style `SIG` values |

## User interface — `+mabr/+ui/`

| Item | Description |
|------|-------------|
| [`mabr.ui.App`](../+mabr/+ui/App.m) | The acquisition GUI (the view). Programmatic `uifigure`; layout in `createComponents` is five titled panels built from one `panelGrid` helper. Holds no acquisition state. |
| [`mabr.ui.AcqController`](../+mabr/+ui/AcqController.m) | **The program.** Owns the Engine, Session, BlockQueue, and live view; translates actions → commands and events → UI updates. Usable headlessly. |
| [`mabr.ui.ProgState`](../+mabr/+ui/ProgState.m) | Enumeration: `Idle`, `PrepBlock`, `Acquire`, `BlockComplete`, `AdvanceBlock`, `SchedComplete`, `Error`. |
| [`mabr.ui.ProgStateEventData`](../+mabr/+ui/ProgStateEventData.m) | Event payload carrying `State` and an `Info` struct. |
| [`mabr.ui.LivePlot`](../+mabr/+ui/LivePlot.m) | Live view: the most-recent sweep on its own top axes, one running mean per stimulus in the run below it, correlation bar. Passive — draws what it is handed. |
| [`mabr.ui.TraceOrganizer`](../+mabr/+ui/TraceOrganizer.m) | Interactive stacked-waveform viewer with drag-to-reposition and peak marking. |
| [`mabr.ui.Trace`](../+mabr/+ui/Trace.m) | One waveform in the stack: data, time base, label, colour, offset, markers. |
| [`mabr.ui.Marker`](../+mabr/+ui/Marker.m) | A peak marker (point + label) on a trace axes. |
| [`mabr.ui.TestRunner`](../+mabr/+ui/TestRunner.m) | The verification suite as a window (Help ▸ Verification Tests…). Discovers every `verify_*.m` in `tests/`, runs the ticked ones, and reports verdict, elapsed time, and captured output per test. |

**`AcqController` surface**

| Member | Description |
|--------|-------------|
| `AcqController(cfg,testing)` | Construct; builds the Engine and the ~20 Hz live timer |
| `waitUntilReady(timeout)` | Forwards to the Engine handshake |
| `setStimuli(stimuli)` | Adopt a `StimulusSet` (or the raw struct array) and build a default `Schedule` to configure |
| `setLivePlot(lp)` | Attach a `LivePlot` (or an embedded one) |
| `start()`, `pauseAcq()`, `resumeAcq()`, `stopBlock()`, `abort()` | User actions. `stopBlock` continues the schedule; `abort` halts it — both save |
| `Window` | ADC window in seconds relative to onset (default `[0 0.01]`) |
| `AdvanceFcn`, `AdvanceParams` | The criterion and its context. `targetSweeps` is overwritten per run with that run's presentation count |
| `Filters` | A `mabr.FilterPolicy` applied to the live view *and* handed to each finalized `Recording`. Settable mid-acquisition; never reaches `Recording.Data`, so saved files stay raw |
| `Engine`, `Session`, `Stimuli`, `Schedule`, `LivePlot`, `State`, `Testing` | Read-only properties |
| events `StateChanged`, `MetricsUpdated`, `BlockReady`, `BlockSaved`, `ScheduleComplete` | The front-end contract. `BlockReady` carries the finalized `Block` (`.Info.block`) and always fires; `BlockSaved` carries a path (`.Info.file`) and fires only when the `Session` has an `OutputPath` |

At finalization the run's sweeps are split by `Schedule.runSequence`, yielding **one `Block` and one `.abr` per stimulus** that appeared in it. A homogeneous run saves the continuous trace; an intermixed one saves each stimulus's sweep windows concatenated, so files do not each carry a full copy of the shared recording.

**`LivePlot`** — `LivePlot(parent)` (omit `parent` for its own figure), `update(sweeps,tvec,R,target,bad,info)`, `reset()`, `setFilterText(txt)`. `sweeps` is `[pre post]` as one contiguous segment and `tvec` its time base in seconds; `info.StimIndex`/`.Stimuli`/`.Labels` say which stimulus evoked each sweep (omit it for a single pooled mean). Display settings are the public properties `Layout` (`'overlay'`/`'separate'`), `TimeBase` (ms, default `[-2 10]`), `AmpMode` (`'each'`/`'common'`/`'manual'`) and `ManualLimit` (volts) — the window's control strip writes exactly these. See [Viewing Data](Viewing-Data.md#liveplot).

**`TraceOrganizer`** — `addBlock(block)`, `addTrace(data,time,label,stimID)`, `markPeaks(idx)`, `clearMarkers(idx)`, `show()`, `refresh()`, `clear()`, `isvalidView()`; live updates `listenTo(controller)`, `stopListening()`; selection `select(idx,extend)`, `selectedIndices()`, `targetIndices()`; display `scaleTraces(factor,idx)`, `resetGain(idx)`, `setSpacing(s)`, `restack()`, `moveTrace(idx,delta)`, `toggleVisible(idx)`, `removeTraces(idx)`; persistence `saveView(file)`, `loadView(file)`; properties `YSpacing`, `YScaling`, `NormalizeEach`, `ShowLabels`, `Colors`, `Traces`, and read-only `Figure`/`Axes`.

## Logging — `+mabr/+log/`

| Item | Description |
|------|-------------|
| [`mabr.log.vprintf(level,[red],fmt,...)`](../+mabr/+log/vprintf.m) | Verbosity-gated logger. Prints a timestamped message and mirrors it to a daily file in `.error_logs/`. Gated on global `GVerbosity` (-1…3). `vprintf(0,1,...)` prints critical text in red. Accepts an `MException` in place of a format string to log the full stack. |

## Verification — `tests/`

| Item | Description |
|------|-------------|
| [`run_all_verifications`](../tests/run_all_verifications.m) | Runs the whole suite and reports a pass count. |
| [`verify_engine_loopback`](../tests/verify_engine_loopback.m) | Engine in loopback: ring buffer writes, head advance, Pause/Stop/Kill latency. |
| [`verify_data_roundtrip`](../tests/verify_data_roundtrip.m) | Written `.abr` files satisfy the offline pipeline's field and filename contract. |
| [`verify_legacy_import`](../tests/verify_legacy_import.m) | Legacy `.abr` import shim, including sigProp-style `SIG` unwrapping. |
| [`verify_online_advance`](../tests/verify_online_advance.m) | Advance-criterion logic, plus an end-to-end early stop through the real controller. |

None require audio hardware; all require the Parallel Computing Toolbox. See [Testing](Testing.md).

## Offline analysis — `abr_analysis/`

A **separate, function-based** pipeline, untouched by the acquisition rewrite. Listed in pipeline order. See [Offline Analysis](Offline-Analysis.md).

| Item | Description |
|------|-------------|
| [`getABRSessions(rootPth)`](../abr_analysis/getABRSessions.m) | Find unique session folders containing `.abr` files below a root. |
| [`extractSessionName(sessionPath)`](../abr_analysis/extractSessionName.m) | Session folder name from a full path. |
| [`parseABRFiles(sessionPath,filePattern=...)`](../abr_analysis/parseABRFiles.m) | Parse filenames and `SIG` metadata into a table: one column per informative param, plus `timestamp`, `fileName`, `folder`. |
| [`extractABRResponses(T,win,opts)`](../abr_analysis/extractABRResponses.m) | Load each file, optionally filter the whole trace, segment into sweeps around onsets, and group by stimulus. Returns `[S,U,Fs,winIdx]`. |
| [`rejectArtifacts(S,opts)`](../abr_analysis/rejectArtifacts.m) | Drop outlier trials by a per-trial feature (`absPeak`, `rms`, …) via `isoutlier`. |
| [`filterABRData(S,Fs)`](../abr_analysis/filterABRData.m) | FIR bandpass over grouped responses. |
| [`plotABRGrid(S,U,Fs,winIdx,opts)`](../abr_analysis/plotABRGrid.m) | Tiled grid of averaged responses, frequency × level. |
| [`permtest(A,options)`](../abr_analysis/permtest.m) | 1-D permutation test across trials. Methods: `clusterMass` (default), `tmax`, `tfce`. Input is `[nTrials x nSamples]`. |
| [`abrPermutationThreshold(S,rowVals,options,ptoptions)`](../abr_analysis/abrPermutationThreshold.m) | Per-condition detection via `permtest`, then a per-column threshold estimate (GLM by default). Returns `[thresh_hat,permResult,mdls]`. |
| [`abrPermutationThresholdCuration(...)`](../abr_analysis/abrPermutationThresholdCuration.m) | Interactive review and manual override of estimated thresholds. |
| [`plotABRThresholds(thresh_hat,freqs,opts)`](../abr_analysis/plotABRThresholds.m) | Audiogram of threshold against frequency. |
| [`batchABRAnalysis(rootPth,options)`](../abr_analysis/batchABRAnalysis.m) | All-in-one driver. **Currently broken** by stale positional-argument calls and intentionally not fixed — call the functions above directly. |
| [`SCRATCH_BatchABRanalysis.m`](../abr_analysis/SCRATCH_BatchABRanalysis.m) | Working example script to adapt. |

`parfor_progress` (File Exchange) is an optional external dependency used for progress reporting.

## Other folders

| Folder | Contents |
|--------|----------|
| [`helpers/`](../helpers/) | Small standalone utilities predating the rewrite (`Fsp`, `octaves`, `log10space`, `figxy2axisxy`, `timeout`, `seppuku`, and a legacy copy of `vprintf` superseded by `mabr.log.vprintf`). Not part of the acquisition path. |
| [`external/`](../external/) | Third-party code and platform files (`getjframe`, MinGW installer, `user32.h`). |
