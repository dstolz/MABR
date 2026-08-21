Add a "Stimulation Only" mode (playback + timing, no recording, no loop-back)
Context
MABR currently always runs full-duplex: the parpool worker opens an audioPlayerRecorder, plays the 2-channel matrix (col 1 = signal, col 2 = timing pulse), and records both input channels into the ring buffer. Two things are hard requirements today: a loop-back cable (the pre-run verifyTimingLoop refuses to start until it sees the timing pulse come back on the input) and an input side on the device.

The user wants MABR to also run as stimulation only — keep signal playback and the timing pulse on the outputs, but perform no acquisition and require no loop-back, so MABR can drive stimuli for setups where another system records (or nothing does). Decisions already made:

Device: use an output-only audioDeviceWriter in this mode, so MABR also runs on hardware with no input channels (not just "ignore the recorded input").
UI during a run: progress only — do not open the live trace / organizer viewers (there is no data to plot) and write no .abr files.
The mode is analogous in shape to the existing Testing (loop-back, no hardware) switch and lives beside it in mabr.AudioSettings / AudioSettingsDialog. Unlike Testing (which is baked into the worker at parfeval time), the new flag rides per-block in the render spec — worker_loop.prepare_device rebuilds the device on every Prep (worker_loop.m:71-73, :228), so no worker rebuild / ensureController plumbing is needed.

Testing and StimulationOnly are mutually exclusive (Testing = no device at all; StimulationOnly = a real output device). The dialog enforces this and Testing wins everywhere it matters.

Changes
1. mabr.AudioSettings — the persisted flag
+mabr/AudioSettings.m

Add property StimulationOnly (1,1) logical = false beside Testing (:47), with a doc block matching the existing style.
describe() (:59-73): when StimulationOnly (and not Testing) append/return "…, stimulation only (no recording)".
toStruct (:110) / fromStruct (:151, reuse coerceLogical at :198) — add the field.
loadPrefs (:139) / savePrefs (:147) — add 'AudioStimulationOnly'.
2. mabr.ui.AudioSettingsDialog — the checkbox + enable logic
+mabr/+ui/AudioSettingsDialog.m

Add a stimCheck checkbox ("Stimulation only (no recording / no loop-back)") following the testCheck pattern (:44-48); grow the [10 3] grid + RowHeight (:38) by one row.
readControls (:174-181): p.StimulationOnly = stimCheck.Value; and force it false when testCheck.Value is true (Testing wins).
Extend syncTestingEnable (:183-203, called from :153 and the change callbacks):
Testing on → grey everything below, including stimCheck (as today).
StimulationOnly on (Testing off) → grey the recorder channel fields (rcSig/rcTim) and the Mic field; leave device dropdown, Refresh, player channels, and Test Device enabled (a real output device is still opened).
Add onStimOnlyChanged mirroring onTestingChanged (:205-209) to re-sync.
3. mabr.stim.Schedule — carry the flag into the spec
+mabr/+stim/Schedule.m

Add property StimulationOnly (1,1) logical = false beside the audio props (:127-130).
In renderSpec emit spec.StimulationOnly = obj.StimulationOnly; beside the existing spec.PlayerChannels/RecorderChannels (:518-520). The play matrix is unchanged — both columns (signal + timing) are still emitted.
4. mabr.acq.worker_loop — output-only device + no recording
+mabr/+acq/worker_loop.m

prepare_device(apr,spec,testing) (:220-243): read stimOnly = getdef(spec,'StimulationOnly',false). Order of precedence: testing → apr = [] (unchanged, :223-226); elseif stimOnly → build an audioDeviceWriter('SampleRate',…, 'ChannelMappingSource','Property', 'ChannelMapping',player, 'BitDepth','32-bit float', ['Device',…]); else → audioPlayerRecorder as today. release(apr)/isvalid (:228) work for both classes, so switching between runs is clean.
stream_block (:132-196): read the same stimOnly via getdef. Add a branch beside the testing/real branches (:179-186): when stimOnly, call apr(frame) (the audioDeviceWriter plays both columns, incl. the timing pulse, and provides the sample clock that paces the loop) and skip rb.writeFrame (:188) — nothing is recorded. rb.reset() (:145) stays (harmless).
5. mabr.ui.AcqController — skip the loop-back check, finalize, and live timer
+mabr/+ui/AcqController.m (read via obj.Schedule.StimulationOnly)

start (:239-263): wrap the verifyTimingLoop/timingNotDetected block (:247-259) in if ~obj.Schedule.StimulationOnly … end — no loop-back to verify.
on_engine_state (:422-430): only start_timer() on Acquire when ~obj.Schedule.StimulationOnly (nothing to plot without recording).
on_block_completed (:432-474): guard the finalize_run + BlockReady/BlockSaved notify loops (:445-459) with if ~obj.Schedule.StimulationOnly; still run the schedule-advance tail (:461-473) so the plan drives to SchedComplete. (No blocks, no .abr files are produced in this mode.)
6. mabr.ui.App — wire the flag, suppress viewers, show progress
+mabr/+ui/App.m

buildSchedule (:1584-1595) and onStart (:1651-1654): set sch.StimulationOnly = app.Audio.StimulationOnly; / c.Schedule.StimulationOnly = … alongside the existing Device/PlayerChannels/RecorderChannels assignments.
onStart (:1668-1669): only openViewers() + c.setLivePlot(app.LivePlot) when ~app.Audio.StimulationOnly; in stim-only leave LivePlot unset (guard setLivePlot/ or pass []).
setRunTitle (:1996-2005): show Run — STIMULATION ONLY (no recording) while a stim-only schedule is in flight (same mechanism as the PREVIEW title), taking precedence over the normal title.
Progress with no live timer: onState (:1857-1870) already updates the state lamp/ label on every ProgState transition, giving run-level progress. In stim-only, set the SweepLabel/CorrLabel to a run indicator (e.g. Run k/N, from the schedule's current-run cursor / NumRuns) instead of Sweeps:/r =, and reset them at onStart. (onMetrics won't fire, since the live timer is off.)
No change needed to configControls — AudioMenuItem is already locked during a run (:1924-1943), so the setting can't be toggled mid-schedule.
Verification
Hardware-free (add to the suite): new tests/verify_stimulation_only.m, added to tests/run_all_verifications.m (so mabr.ui.TestRunner discovers it). Run the engine in Testing mode (Engine(cfg,true), so no real device is needed) but with Schedule.StimulationOnly = true. This exercises the entire client-side stim-only path — because testing wins in the worker (prepare_device returns [], stream_block uses the loop-back branch), while Schedule.StimulationOnly drives AcqController. Assert:

AcqController.start() does not throw timingNotDetected and needs no loop-back;
the schedule advances through every run to SchedComplete;
zero Blocks are added to the Session and zero .abr files are written (given an OutputPath), i.e. finalize_run is skipped;
no LivePlot is required (the live timer never starts). Follow the no-hardware, no-uiwait conventions of the existing verify_* scripts; pass by returning without throwing.
On the rig (manual, like verify_timing_loopback 'Testing',false): the audioDeviceWriter device swap itself can't run without hardware. Confirm on the rig: in AudioSettingsDialog enable Stimulation only, pick the ASIO device, Start a short schedule, and verify (a) it starts with no loop-back cable connected, (b) signal + timing pulses are present on the outputs (scope/DAW), (c) no viewers open and no .abr files are written, (d) the Run title reads STIMULATION ONLY and run progress advances to completion.

Also run the full suite: tests/run_all_verifications.m (and open Help ▸ Verification Tests… to confirm the new test is discovered and listed).