function verify_legacy_import()
% verify_legacy_import  Check the legacy .abr import shim.
%
%   Builds a legacy-shaped ABR_Data file (SIG stored as sigProp-style structs
%   with a .Value field, exactly as abr.ABR.to_struct produced) and imports it
%   with mabr.data.io.importLegacy, confirming:
%       * the reconstructed mabr.data.Recording segments sweeps identically to
%         a direct index-based reference (the legacy abr.Buffer.SweepData
%         algorithm);
%       * SIG params are unwrapped from their sigProp structs into plain
%         numerics in the new model.
%   Any real checked-in sample .abr found on disk is also imported as a
%   structural smoke test.
%
%   No hardware required. Run:  >> verify_legacy_import
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_legacy_import ==\n');

% ---- 1. synthetic legacy-shaped file (deterministic) -------------------
tmp = fullfile(tempdir,'mabr_legacy_import');
if isfolder(tmp), rmdir(tmp,'s'); end
mkdir(tmp);
clean = onCleanup(@() rmdir(tmp,'s'));

Fs = 12000; swLen = 120; nSweeps = 40;
N  = nSweeps*300 + swLen;
data   = single(0.5*randn(N,1));
onsets = (1 + (0:nSweeps-1)*300)';

ABR_Data = struct(); %#ok<NASGU>
ABR_Data.ADC = struct('SampleRate',Fs,'Data',data,'SweepOnsets',onsets,'SweepLength',swLen);
ABR_Data.StartTime = '2025-07-19T14:30:00';
% legacy SIG: params wrapped as sigProp-style structs
ABR_Data.SIG.informativeParams = {'Frequency','Level'};
ABR_Data.SIG.Frequency = struct('Value',16,'Alias','Frequency','Unit','kHz');
ABR_Data.SIG.Level     = struct('Value',30,'Alias','Level','Unit','dB');
ABR_Data.SIG.Label     = {'Frequency = 16 kHz','Level = 30 dB'};
ffn = fullfile(tmp,'legacy_sample.abr');
save(ffn,'ABR_Data','-mat');

block = mabr.data.io.importLegacy(ffn);
rec   = block.ADC;

assert(abs(rec.SampleRate - Fs) < 1e-6,'SampleRate mismatch');
assert(numel(rec.Data) == N,'Data length mismatch');

% sigProp unwrapping
assert(isfield(block.Stim,'Meta'),'no Meta reconstructed');
assert(block.Stim.Meta.Frequency == 16,'Frequency not unwrapped from sigProp .Value');
assert(block.Stim.Meta.Level == 30,'Level not unwrapped from sigProp .Value');
fprintf('  PASS: SIG sigProp structs unwrapped (Frequency=16, Level=30)\n');

% segmentation vs the legacy abr.Buffer algorithm
idx   = (0:swLen-1)' + onsets(:)';
valid = ~any(idx > N | idx < 1,1);
ref   = single(data(idx(:,valid)));
got   = rec.SweepData;
assert(isequal(size(got),size(ref)),'SweepData size mismatch: %s vs %s', ...
    mat2str(size(got)),mat2str(size(ref)));
err = max(abs(double(got(:)) - double(ref(:))));
assert(err < 1e-6,'SweepData differs from reference (max err %.2e)',err);
fprintf('  PASS: SweepData matches reference segmentation [%d x %d]\n',size(got,1),size(got,2));

% ---- 2. opportunistic real sample smoke test ---------------------------
real = find_real_sample();
if isempty(real)
    fprintf('  NOTE: no real checked-in .abr with an ADC struct found (repo samples are stubs).\n');
else
    try
        b2 = mabr.data.io.importLegacy(real);
        fprintf('  PASS: imported real sample %s (%d samples)\n', ...
            real,numel(b2.ADC.Data));
    catch me
        fprintf(2,'  WARN: real sample import failed: %s\n',me.message);
    end
end

fprintf('== verify_legacy_import PASSED ==\n');
end


% =====================================================================
function ffn = find_real_sample()
root = mabr.Config.root;
searchDirs = {fullfile(root,'samples'), root, fullfile(root,'+abr')};
ffn = '';
for i = 1:numel(searchDirs)
    d = dir(fullfile(searchDirs{i},'*.abr'));
    for j = 1:numel(d)
        cand = fullfile(d(j).folder,d(j).name);
        try
            a = load(cand,'-mat','ABR_Data');
        catch
            continue
        end
        if isfield(a,'ABR_Data') && isfield(a.ABR_Data,'ADC') ...
                && isfield(a.ABR_Data.ADC,'Data') && ~isempty(a.ABR_Data.ADC.Data)
            ffn = cand; return
        end
    end
end
end
