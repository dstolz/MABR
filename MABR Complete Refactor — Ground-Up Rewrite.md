MABR Complete Refactor — Ground-Up Rewrite
Context
MABR is a Windows-only MATLAB toolbox for presenting acoustic stimuli and acquiring/analyzing ABR electrophysiology. The current design works but has accumulated serious structural debt that makes it hard to extend and maintain:

Acquisition runs as two separate matlab.exe processes that coordinate only through memory-mapped files in .runtime_data/ (mabr_com.dat, input_buffer.dat, input_timing.dat, dac.wav, info.mat). Process spawning uses system("matlab.exe …"), liveness is checked by shelling out to Wmic, and the stimulus is handed off by writing a WAV to disk. This is fragile, hard to debug (the background process has no visible console), and couples the GUI directly to raw acquisition memory (app.Runtime.mapSignalBuffer.Data(...) appears inline in the state machine).
The data model is tangled: abr.ABR (handle + Copyable) holds abr.Buffer value objects that carry an ABRobj back-reference (a handle cycle that to_struct has to strip). Filters are designed in the live path but never actually applied.
The GUI is a 1720-line ControlPanel with a giant StateMachine driven by a hidden global stateAcq, UI-blocking while … pause(0.01) busy-waits, and two timer objects.
Stimulus generation and calibration are baked in (+sigdef, SoundCalibration, CalibrationUtility, Schedule/ScheduleDesign) — the user is replacing these with a separate package.
Dead/broken code: traces.Group/traces.Marker (invalid types, mismatched constructors), abr_adv_corr_thr.m (empty stub), the +analysis OO classes (superseded by inline functions), a set.BufferIndex typo (mapCOm), and scratch files (temp.m, Cmd.m, BlockAnalysis.m).
Intended outcome: a clean, single-namespace rewrite (+mabr) with a modern acquisition engine built on the Parallel Computing Toolbox, a decoupled data model and GUI, and a well-defined boundary where an external package supplies precomputed, calibrated stimulus waveforms. The .abr file format stays readable (import shim) and the app keeps writing files the unchanged offline abr_analysis/ pipeline can consume.

Decisions (confirmed with user)
Ground-up rewrite in a new +mabr package; legacy +abr stays runnable side-by-side until cutover. .abr supported via import shim.
Acquisition IPC = PCT parpool worker + memmap ring buffer (hybrid). Control/state/lifecycle over DataQueue; large recorded-sample stream stays in a memmap ring buffer for zero-copy live view.
Stimulus/calibration are external. The other package hands MABR precomputed, calibrated waveform samples + block metadata. MABR owns no signal generation or calibration.
Offline analysis stays separate. abr_analysis/ is untouched; the app must keep emitting .abr files whose struct satisfies that pipeline's field expectations.
Out of scope
Stimulus design and calibration (external package).
Any change to abr_analysis/ (permutation test, threshold estimation, curation GUI). Note but do not fix its known stale-signature bug in batchABRAnalysis.m.
Target architecture
New package layout under a +mabr/ namespace (legacy +abr/ untouched during migration):

+mabr/
  Config.m              constants + runtime paths (NOT a superclass; a plain value/struct config)
  +acq/                 acquisition engine (the load-bearing subsystem)
    Engine.m            client-side controller: owns the parpool future + queues + ring buffer
    worker_loop.m       function that runs ON the parpool worker (owns audioPlayerRecorder)
    RingBuffer.m        thin wrapper over the memmap sample/timing buffers + write-head header
    Cmd.m               command enum (Prep/Run/Pause/Stop/Kill) — sent over DataQueue
    State.m             acquisition state enum (Idle/Ready/Acquire/Paused/Completed/Error)
  +data/
    Session.m           top-level session: subject/device/rates + array of Block results
    Block.m             one condition's result: stimulus meta + raw trace + onsets + metrics
    Recording.m         value type: one channel's samples + segmentation helpers (SweepData/Mean/SNR)
    io.m                save/load; writes .abr (offline-compatible struct) + reads legacy import shim
  +stim/
    StimulusSource.m    adapter contract MABR consumes (precomputed waveforms from external pkg)
    BlockQueue.m        ordered list of pre-rendered blocks + schedule walk
    advance/            advance criteria (num_sweeps, corr_threshold) — proper implementations
  +metrics/             small tested functions: partition_corr, rms, snr, findpeaks wrapper
  +ui/
    App.m               new App Designer app (view) — createComponents treated as generated
    AcqController.m     wires UI <-> acq.Engine via event callbacks (no global, no busy-wait)
    LivePlot.m          live 3-axis view (mean / recent / correlation)
    TraceOrganizer.m    interactive stacked-waveform viewer (rebuilt, markers fixed)
  +log/  vprintf.m      keep the existing verbosity-gated logger (moved, not rewritten)
MABR.m                  launcher: addpath + open mabr.ui.App
Subsystem 1 — Acquisition engine (+mabr/+acq/) — highest risk, build first
Replaces abr.Runtime, launch_bg_process, system() spawn, Wmic PID checks, info.mat, dac.wav handoff, and the mabr_com.dat command/state memmap. Keeps a memmap ring buffer for recorded samples (the hybrid the user chose).

Worker (worker_loop.m), runs on a 1-worker process parpool:

Owns audioPlayerRecorder (ASIO) and iterates the stimulus frames — this is the direct analog of today's acquire_block.m tight loop (+abr/@Runtime/acquire_block.m), but the stimulus arrives in memory as a parfeval argument instead of being read from dac.wav.
Each frame: [audioADC,nu,no] = APR(frame) → write ch1/ch2 into the memmap ring buffer (writable on worker), advance a write-head stored in a tiny memmap header, and poll a parallel.pool.PollableDataQueue (0-timeout) for Pause/Stop/Kill — mirrors the current per-frame C.Data.CommandToBg poll (acquire_block.m:65,72).
Sends state transitions (Ready/Acquire/Completed/Error) and its own PID back over a DataQueue; the client sets high thread priority on that PID (reusing the logic in abr.Tools.set_priority).
Keep a loopback TESTING mode (as today's Universal.MODE == Cmd.Test) so the whole engine runs and is testable with no hardware.
Client (Engine.m), runs in the GUI process:

Starts and keeps warm a 1-process parpool at app launch (amortize worker startup once).
Queue handshake: client creates a DataQueue (worker→client), passes it into parfeval(pool, @mabr.acq.worker_loop, 0, resultQueue, …); the worker creates a PollableDataQueue (client→worker) and sends its handle back on the result queue. afterEach on the result queue drives state/PID/error handling — replacing every while … pause(0.01) busy-wait in the old StateMachine.
Opens the memmap ring buffer read-only and exposes readNewSamples() for the live view to slice zero-copy from the last consumed head to the current write-head (direct analog of extract_sweeps.m + find_timing_onsets.m, which move into +data/+metrics).
Ring buffer (RingBuffer.m): two single memmap files (signal + timing) sized like today's maxInputBufferLength = 2^26, plus a small memmap header for the write-head index. Worker writable, client read-only. This is the one memmap surface retained.

Design win: because commands are polled every frame, the engine can honor an online advance criterion (stop the block early when a correlation threshold is met) — fixing the limitation the old code documents in +abr/@ControlPanel/timer_Runtime.m ("NOT CURRENTLY POSSIBLE TO UPDATE THE NUMBER OF SWEEPS DURING PLAYBACK").

Validation risk to confirm early (Phase 1): ASIO audioPlayerRecorder device access and sample-accurate full-duplex timing from a parpool process worker. It is a headless MATLAB process like today's background instance, so this is expected to work — but it is the single biggest unknown, which is why the engine is built and hardware-smoke-tested before any GUI work.

Add 'Parallel Computing Toolbox' to the required-toolbox list (was absent in +abr/@Universal/Universal.m).

Subsystem 2 — Data model (+mabr/+data/)
Replaces abr.ABR + abr.Buffer with a cleaner, cycle-free model:

Recording (value type): one channel's SampleRate + Data + SweepOnsets/SweepLength, with the genuinely useful dependent helpers ported from abr.Buffer — SweepData (index-matrix segmentation), SweepMean (detrend + smooth), noisePower/SNR (± odd/even averaging). Drop the ABRobj back-reference; pass decimation factor explicitly.
Block: one condition's result — stimulus metadata (from the external package), the recorded Recording(s), artifact flags, and computed metrics.
Session (handle): subject/device/sample-rate config + an array of Blocks + the block queue.
Filtering decision: the old live path designed a bandpass (HP 10 / LP 3000) + 60 Hz notch but never applied it. Make filter application explicit and consistent in Recording (design once, apply in segmentation), so live and saved data are defined.
Serialization (io.m): the app must keep the offline pipeline working unchanged, so the writer emits an ABR_Data-compatible struct — specifically the fields abr_analysis/ reads: ADC.SampleRate, ADC.Data, ADC.SweepOnsets, StartTime, and a SIG-shaped substruct with informativeParams + the named stimulus params + Label (mapped from the external package's block metadata — see Subsystem 3). Preserve the current save-time ADC decimation by adcDecimationFactor (+abr/@ControlPanel/ControlPanel.m save_abr_data, lines ~318–348). Provide a legacy import shim that loads old ABR_Data structs into the new Session/Block model.

Subsystem 3 — Stimulus adapter (+mabr/+stim/)
MABR no longer generates signals or calibrates. Delete (at cutover) +abr/+sigdef, +abr/@SoundCalibration, +abr/@CalibrationUtility, +abr/@Schedule, +abr/@ScheduleDesign.

StimulusSource contract — the external package supplies, per session, an ordered set of blocks; each block provides:

samples — precomputed, calibrated stimulus samples (the signal channel), single.
SampleRate — DAC rate (Hz).
sweep timing — either a sweepRate (Hz) or explicit onset sample indices.
metadata — struct with frequency, level, polarity, label, and an informativeParams list, used for display and for the .abr SIG-compatible write.
MABR responsibilities: MABR builds the 2-channel play matrix by pairing the external signal channel with a timing-pulse channel it synthesizes from the sweep-timing info (one pulse per sweep onset). MABR owns the timing-pulse contract because sweep extraction (find_timing_onsets/extract_sweeps) depends on it. BlockQueue.m holds the pre-rendered blocks and walks them; advance/ implements num_sweeps (port of advanceFcns/abr_adv_num_sweeps.m) and a real corr_threshold (the old abr_adv_corr_thr.m was an empty stub).

Confirm at implementation: whether the external package emits the timing channel itself or only sweep-onset info for MABR to synthesize. Plan assumes MABR synthesizes it (safer for extraction).

Subsystem 4 — GUI (+mabr/+ui/)
New App Designer app replacing abr.ControlPanel. Key changes:

AcqController owns acq.Engine and translates UI actions → commands and engine events → UI updates via the DataQueue afterEach callbacks. No global stateAcq; no busy-wait loops.
A single explicit state object (states: Idle/PrepBlock/AdvanceBlock/Acquire/BlockComplete/ SchedComplete/Error) — a clean rework of the old StateMachine, event-driven rather than polled.
One UI timer for live-view refresh only (~20 Hz), pulling readNewSamples() from the engine and updating LivePlot. The GUI never touches raw acquisition memory directly (unlike today's inline mapSignalBuffer.Data reads).
Keep LivePlot (mean / most-recent / correlation-bar) and a rebuilt TraceOrganizer (fix the broken Group/Marker). Fold live metrics into +mabr/+metrics functions (retire the unused +abr/+analysis OO classes).
Config is a plain config object, not a superclass of the app (the old ControlPanel < abr.Universal inheritance is dropped).
Cross-cutting cleanup
Retire at cutover: traces.Group, traces.Marker, +abr/+analysis/*, abr_adv_corr_thr.m, +abr/temp.m, +abr/Cmd.m (scratch), +abr/BlockAnalysis.m, the Wmic PID discovery, and the user32.dll mouse hook (replace with standard figure callbacks if still needed). Keep and reuse: helpers/vprintf.m + GVerbosity logging, helpers/Fsp.m/log10space.m/octaves.m as needed.

Phased delivery (rewrite delivered incrementally for continuous hardware validation)
Phase 0 — Scaffolding. Create +mabr skeleton, Config (constants + paths, add PCT to required toolboxes), move vprintf under +mabr/+log. Legacy +abr still launches.
Phase 1 — Acquisition engine (de-risk first). Build +mabr/+acq (worker loop, Engine, ring buffer, queues) with TESTING loopback. Then a hardware smoke test: acquire a block headlessly and confirm ASIO on a parpool worker + timing integrity. Representative files: +mabr/+acq/worker_loop.m, +mabr/+acq/Engine.m, +mabr/+acq/RingBuffer.m.
Phase 2 — Data model + IO. Recording/Block/Session, segmentation/metrics ported from abr.Buffer, io.m with offline-compatible .abr writer + legacy import shim. Verify a written .abr round-trips through abr_analysis/parseABRFiles.m + extractABRResponses.m untouched.
Phase 3 — Stimulus adapter. StimulusSource contract, BlockQueue, advance/ criteria; wire the external package; map its metadata into the .abr SIG-compatible struct.
Phase 4 — GUI. New App Designer App + AcqController + LivePlot + TraceOrganizer; event-driven, no busy-waits. Full run of a schedule against hardware.
Phase 5 — Cutover + cleanup. Point MABR.m at mabr.ui.App; delete legacy +abr, stimulus, calibration, and dead code; update CLAUDE.md, README.md, and docs.
Verification
No-hardware: run acq.Engine in TESTING loopback; assert recorded frames land in the ring buffer, write-head advances, and Pause/Stop/Kill over the queue take effect within one frame.
Data round-trip: write a .abr from a synthetic Session and confirm the unchanged abr_analysis/ pipeline (getABRSessions → parseABRFiles → extractABRResponses → rejectArtifacts → abrPermutationThreshold) loads and processes it without edits.
Legacy import: load a checked-in sample .abr (e.g. SUBJ-ID-955.abr) through the import shim into the new model and compare sweep segmentation against the old abr.Buffer.SweepData.
Hardware parity: with the external package driving the same stimulus, run one full schedule on the ASIO device and compare acquired waveforms/sweep counts against a legacy +abr run.
Regression on the win: confirm an online correlation-threshold advance stops a block early (the capability the old design could not provide).