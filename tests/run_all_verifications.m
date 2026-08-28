function run_all_verifications()
% run_all_verifications  Run the MABR no-hardware verification suite.
%
%   Runs, in order:
%       verify_isi_jitter        - presentation timing: fixed grid vs uniformly
%                                  randomized ISI, and what still reads it back
%       verify_play_plan         - mabr.stim.PlayPlan: frames synthesized on
%                                  demand are bit-identical to a whole-matrix
%                                  render, and the worker streams from one
%       verify_engine_loopback   - acquisition engine (ring buffer, Pause/Stop/Kill)
%       verify_data_roundtrip    - .abr writer satisfies the offline pipeline
%       verify_legacy_import     - legacy .abr import shim
%       verify_online_advance    - online correlation-threshold early stop
%       verify_custom_advance    - the custom advance-function contract:
%                                  context, validator, template, and a
%                                  file-resolved user criterion stopping early
%       verify_custom_strategy   - the custom presentation-strategy contract:
%                                  context, the accepted return shapes, the
%                                  validator, the template, polarity parity
%                                  with the built-ins, and a file-resolved
%                                  user strategy driving the run order
%       verify_artifact_rejection- artifact criteria, prefs, and make-up runs
%       verify_filters           - display filter chain, and that it never
%                                  reaches the saved trace
%       verify_live_plot         - live view: per-stimulus means, time base,
%                                  amplitude scaling, control strip, and the
%                                  parameter-aware labelling, ordering,
%                                  grouping, Grid/Stacked layouts, and the
%                                  SD/SEM/CI error bands and their statistics
%       verify_live_refresh      - the live view keeps its frame rate with the
%                                  progress and analysis windows open: the
%                                  two timers, AuxPeriod, and the realized
%                                  refresh rate during a real loopback run
%       verify_compute_worker    - the compute workers: publish buffers, a
%                                  run served by the DSP worker with no
%                                  in-process DSP, bit-identical parity with
%                                  the in-process pipeline, priorities, and
%                                  the metrics worker (SKIPS the worker parts
%                                  where the pool cannot hold three workers)
%       verify_stimulus_alignment- the correspondence everything else rests
%                                  on: the samples recorded at the onset the
%                                  timing pulse marks ARE the stimulus the
%                                  schedule placed there. Onset recovery,
%                                  de-interleaving, per-condition metrics,
%                                  the live statistics, polarity, and the
%                                  same through the compute workers. Also a
%                                  rig check -- see its help for the
%                                  'Testing',false invocation
%       verify_test_mode         - TEST MODE: the stimulus buffer copied into
%                                  the acquisition ring buffer, the alignment
%                                  report MABR draws from it after every run
%                                  (including that it can FAIL), and the mark
%                                  a Test Mode block and its .abr carry
%       verify_progress_monitor  - acquisition progress window: the tally,
%                                  simple/bar/heat-map views, counts vs
%                                  percent, and the mid-run attribution
%       verify_metric_plot       - online analysis: the metric library and its
%                                  contract, per-condition values, the plot
%                                  adapting to 0/1/2 parameters (lines, bars,
%                                  heat map, contour, surface), live
%                                  conditions, the right-click aesthetics, and
%                                  two independent windows
%       verify_trace_organizer   - TraceOrganizer scaling/spacing/save/load
%       verify_trace_inspector   - TraceInspector peak picking, and the
%                                  transfer of peaks back to the organizer
%       verify_notes             - session notes: run/sweep stamping, the
%                                  editable log, the plain-text crash journal,
%                                  and the notebook reaching the .abr, the
%                                  .stimlog, and a .torg
%       verify_audio_settings    - ASIO device/channel settings: prefs,
%                                  graceful device query, schedule wiring
%       verify_view_prefs        - what MABR recalls between sessions beyond
%                                  those settings: which windows open at
%                                  Start (mabr.ViewPolicy), the whole window
%                                  layout as one snapshot, and the live and
%                                  analysis views' look
%       verify_stimgen_import    - stimgen bank -> StimulusSet: one variant per
%                                  entry, regenerated at the DAC rate, and the
%                                  waveform matching its own label. SKIPS when
%                                  the external/stimgen submodule is absent.
%       verify_stimulation_only  - playback + timing pulse with no recording:
%                                  the setting, the flag on the render spec,
%                                  and a schedule that runs to completion with
%                                  no loop-back, no blocks, and no files
%       verify_timing_selftest   - pre-run timing loop-back self-test does
%                                  not regress a normal Start
%       verify_timing_loopback   - timing pulse recovery: count, jitter, clock
%                                  drift, and detection margin. Also the rig
%                                  diagnostic -- see its help for the
%                                  hardware ('Testing',false) invocation.
%       verify_test_runner       - the window that runs this list
%                                  (mabr.ui.TestRunner): discovery, ordering,
%                                  output capture, verdicts
%       verify_shutdown_pool     - MABR gives the parallel pool back when the
%                                  GUI closes, and declines to touch a BUSY
%                                  one. LAST because it ends with no pool
%                                  open -- anything after it would pay the
%                                  relaunch.
%
%   This file is also the ORDER mabr.ui.TestRunner lists the suite in -- it
%   parses the calls below rather than keeping a second copy of them.
%
%   Requires the Parallel Computing Toolbox (all but verify_isi_jitter,
%   verify_filters, verify_live_plot, verify_progress_monitor,
%   verify_metric_plot, verify_trace_organizer, verify_trace_inspector,
%   verify_audio_settings, and verify_view_prefs). None require audio
%   hardware.
%
% Daniel Stolzberg (c) 2026

tests = {@verify_isi_jitter, @verify_play_plan, ...
         @verify_engine_loopback, @verify_data_roundtrip, ...
         @verify_legacy_import,  @verify_online_advance, ...
         @verify_custom_advance, @verify_custom_strategy, ...
         @verify_artifact_rejection, @verify_filters, ...
         @verify_live_plot, @verify_live_refresh, ...
         @verify_compute_worker, @verify_stimulus_alignment, ...
         @verify_test_mode, ...
         @verify_progress_monitor, @verify_metric_plot, ...
         @verify_trace_organizer, @verify_trace_inspector, ...
         @verify_notes, @verify_audio_settings, @verify_view_prefs, ...
         @verify_stimgen_import, @verify_stimulation_only, ...
         @verify_timing_selftest, @verify_timing_loopback, @verify_test_runner, ...
         @verify_shutdown_pool};

nPass = 0;
for i = 1:numel(tests)
    name = func2str(tests{i});
    try
        tests{i}();
        nPass = nPass + 1;
    catch me
        fprintf(2,'\n*** %s FAILED: %s\n%s\n\n',name,me.message,getReport(me,'basic'));
    end
end

fprintf('\n==== %d / %d verifications passed ====\n',nPass,numel(tests));
end
