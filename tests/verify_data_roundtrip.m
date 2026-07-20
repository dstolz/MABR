function verify_data_roundtrip()
% verify_data_roundtrip  Confirm a written .abr satisfies the offline pipeline.
%
%   Builds a synthetic mabr.data.Session with two conditions, writes each block
%   with mabr.data.io.writeABR, then checks:
%       1. the ABR_Data struct exposes exactly the fields abr_analysis/ reads
%          (ADC.SampleRate/Data/SweepOnsets, StartTime, SIG.informativeParams,
%          numeric SIG params, SIG.Label);
%       2. the filename matches the pipeline's default regex;
%       3. (if parfor_progress is installed) the UNCHANGED pipeline functions
%          parseABRFiles + extractABRResponses load and group the files.
%
%   No hardware required. Run:  >> verify_data_roundtrip
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_data_roundtrip ==\n');

cfg  = mabr.Config;
Fs   = cfg.DACSampleRate;      % build the Recording at DAC rate...
df   = cfg.decimationFactor;   % ...and let io decimate at save time
outDir = fullfile(tempdir,'mabr_roundtrip');
if isfolder(outDir), rmdir(outDir,'s'); end
mkdir(outDir);
clean = onCleanup(@() rmdir(outDir,'s'));

regex = "^SUBJ_ID_(\d+)_Frequency_([\d_]+kHz)_Level_(\d+dB)_(\d{6}T\d{6})\.abr";

conds = struct('Freq',{8,16},'Level',{30,30});
files = strings(1,numel(conds));

for i = 1:numel(conds)
    block = make_synthetic_block(Fs,df,conds(i).Freq,conds(i).Level);
    ffn   = mabr.data.io.writeABR(block,outDir,'SUBJ_ID_999');
    files(i) = string(ffn);

    % --- 1. struct field contract --------------------------------------
    a = load(ffn,'-mat','ABR_Data'); D = a.ABR_Data;
    assert(isfield(D,'ADC') && isfield(D.ADC,'SampleRate') && isfield(D.ADC,'Data') ...
        && isfield(D.ADC,'SweepOnsets'),'missing ADC fields');
    assert(isfield(D,'StartTime'),'missing StartTime');
    assert(isfield(D,'SIG') && isfield(D.SIG,'informativeParams') && isfield(D.SIG,'Label'), ...
        'missing SIG fields');
    assert(abs(D.ADC.SampleRate - Fs/df) < 1e-6,'ADC.SampleRate not decimated to %g',Fs/df);
    for p = string(D.SIG.informativeParams)
        assert(isfield(D.SIG,p) && isnumeric(D.SIG.(p)), ...
            'SIG.%s must be numeric for the offline pipeline',p);
    end
    assert(~isempty(datetime(D.StartTime)),'StartTime not datetime-parseable');

    % --- 2. filename regex ---------------------------------------------
    [~,fn,ext] = fileparts(ffn);
    assert(~isempty(regexp([fn ext],regex,'once')), ...
        'Filename "%s" does not match the offline regex',[fn ext]);
    fprintf('  wrote %s  (Fs=%g, %d onsets)\n',[fn ext],D.ADC.SampleRate,numel(D.ADC.SweepOnsets));
end
fprintf('  PASS: struct contract + filename regex\n');

% --- 3. full offline pipeline (optional) --------------------------------
if isempty(which('parfor_progress'))
    fprintf('  SKIP: parfor_progress not on path; install it to run the full pipeline leg.\n');
else
    T = parseABRFiles(outDir,'filePattern',regex);
    assert(~isempty(T) && height(T) == numel(conds),'parseABRFiles returned %d rows',height(T));
    assert(all(ismember({'Frequency','Level','timestamp'},T.Properties.VariableNames)), ...
        'parseABRFiles missing expected columns');
    [S,U,fsOut] = extractABRResponses(T,[0 10]);
    assert(abs(fsOut - Fs/df) < 1e-6,'extractABRResponses Fs mismatch');
    assert(numel(U.Frequency) == 2,'expected 2 unique frequencies');
    assert(any(~cellfun(@isempty,S(:))),'extractABRResponses produced no segments');
    fprintf('  PASS: parseABRFiles + extractABRResponses (%d files, %d freqs)\n', ...
        height(T),numel(U.Frequency));
end

fprintf('== verify_data_roundtrip PASSED ==\n');
end


% =====================================================================
function block = make_synthetic_block(Fs,df,freqkHz,leveldB)
% A short block with a repeatable evoked wavelet at each sweep onset, so the
% offline pipeline has something to segment and correlate.
sweepRate = 21.1;
nSweeps   = 64;
period    = round(Fs/sweepRate);
N         = nSweeps*period + period;

% evoked wavelet (~2 ms), same every sweep
tw = (0:round(0.002*Fs)-1)'/Fs;
wavelet = single(sin(2*pi*800*tw).*hann(numel(tw)))*1e-6*(1+leveldB/60);

data   = 1e-7*randn(N,1,'single');            % baseline noise
onsets = (round(0.05*Fs) + (0:nSweeps-1)*period)';   % after some lead-in
for k = 1:nSweeps
    i0 = onsets(k);
    data(i0:i0+numel(wavelet)-1) = data(i0:i0+numel(wavelet)-1) + wavelet;
end

rec = mabr.data.Recording(Fs,data,onsets,round(0.01*Fs),df);

meta = struct('Frequency',freqkHz,'Level',leveldB,'Polarity',1, ...
    'informativeParams',{{'Frequency','Level'}}, ...
    'Label',{{sprintf('Frequency = %g kHz',freqkHz),sprintf('Level = %g dB',leveldB)}});
stim = struct('Meta',meta,'SampleRate',Fs);

block = mabr.data.Block(stim,rec);
end
