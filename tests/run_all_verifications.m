function run_all_verifications()
% run_all_verifications  Run the MABR no-hardware verification suite.
%
%   Runs, in order:
%       verify_engine_loopback   - acquisition engine (ring buffer, Pause/Stop/Kill)
%       verify_data_roundtrip    - .abr writer satisfies the offline pipeline
%       verify_legacy_import     - legacy .abr import shim
%       verify_online_advance    - online correlation-threshold early stop
%       verify_artifact_rejection- artifact criteria, prefs, and make-up runs
%       verify_filters           - display filter chain, and that it never
%                                  reaches the saved trace
%       verify_live_plot         - live view: per-stimulus means, time base,
%                                  amplitude scaling, control strip
%       verify_trace_organizer   - TraceOrganizer scaling/spacing/save/load
%       verify_audio_settings    - ASIO device/channel settings: prefs,
%                                  graceful device query, schedule wiring
%       verify_stimgen_import    - stimgen bank -> StimulusSet: one variant per
%                                  entry, regenerated at the DAC rate, and the
%                                  waveform matching its own label. SKIPS when
%                                  the external/stimgen submodule is absent.
%       verify_timing_selftest   - pre-run timing loop-back self-test does
%                                  not regress a normal Start
%       verify_timing_loopback   - timing pulse recovery: count, jitter, clock
%                                  drift, and detection margin. Also the rig
%                                  diagnostic -- see its help for the
%                                  hardware ('Testing',false) invocation.
%       verify_test_runner       - the window that runs this list
%                                  (mabr.ui.TestRunner): discovery, ordering,
%                                  output capture, verdicts
%
%   This file is also the ORDER mabr.ui.TestRunner lists the suite in -- it
%   parses the calls below rather than keeping a second copy of them.
%
%   Requires the Parallel Computing Toolbox (all but verify_filters,
%   verify_live_plot, verify_trace_organizer, and verify_audio_settings). None
%   require audio hardware.
%
% Daniel Stolzberg (c) 2026

tests = {@verify_engine_loopback, @verify_data_roundtrip, ...
         @verify_legacy_import,  @verify_online_advance, ...
         @verify_artifact_rejection, @verify_filters, ...
         @verify_live_plot, @verify_trace_organizer, @verify_audio_settings, ...
         @verify_stimgen_import, ...
         @verify_timing_selftest, @verify_timing_loopback, @verify_test_runner};

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
