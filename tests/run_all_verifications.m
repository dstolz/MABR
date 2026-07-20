function run_all_verifications()
% run_all_verifications  Run the MABR no-hardware verification suite.
%
%   Runs, in order:
%       verify_engine_loopback   - acquisition engine (ring buffer, Pause/Stop/Kill)
%       verify_data_roundtrip    - .abr writer satisfies the offline pipeline
%       verify_legacy_import     - legacy .abr import shim
%       verify_online_advance    - online correlation-threshold early stop
%       verify_trace_organizer   - TraceOrganizer scaling/spacing/save/load
%
%   Requires the Parallel Computing Toolbox (all but verify_trace_organizer).
%   None require audio hardware.
%
% Daniel Stolzberg (c) 2026

tests = {@verify_engine_loopback, @verify_data_roundtrip, ...
         @verify_legacy_import,  @verify_online_advance, ...
         @verify_trace_organizer};

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
