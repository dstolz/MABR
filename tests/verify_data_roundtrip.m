function verify_data_roundtrip()
% verify_data_roundtrip  Confirm a written .abr satisfies the offline pipeline.
%
%   Builds a synthetic mabr.data.Session with two conditions, writes each block
%   with mabr.data.io.writeABR, then checks:
%       1. the ABR_Data struct exposes exactly the fields abr_analysis/ reads
%          (ADC.SampleRate/Data/SweepOnsets, StartTime, SIG.informativeParams,
%          numeric SIG params, SIG.Label);
%       1b. the polarity fields offline analysis needs are present, aligned
%          with SweepOnsets, and survive a load back (ADC.SweepPolarity,
%          SIG.alternatePolarity -- which must stay out of informativeParams);
%       2. the filename matches the pipeline's default regex;
%       3. (if parfor_progress is installed) the UNCHANGED pipeline functions
%          parseABRFiles + extractABRResponses load and group the files;
%       4. (same condition) two files of ONE condition are pooled by
%          extractABRResponses (N1+N2 sweeps, not just the last file's), a
%          compact file from an intermixed run is refused with
%          abr_analysis:extractABRResponses:compactFile instead of being cut
%          wrongly, and batchABRAnalysis runs over the written folder.
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

regex = "^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})\.abr";

% One alternating-polarity condition and one fixed, so the polarity fields are
% checked in both states.
conds = struct('Freq',{8,16},'Level',{30,30},'Alt',{true,false});
files = strings(1,numel(conds));

for i = 1:numel(conds)
    block = make_synthetic_block(Fs,df,conds(i).Freq,conds(i).Level,conds(i).Alt);
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

    % --- 1b. polarity fields the offline analysis needs -----------------
    % Always written, whether or not the condition alternated, so analysis
    % code can read them without testing for their existence.
    assert(isfield(D.ADC,'SweepPolarity'),'missing ADC.SweepPolarity');
    assert(isfield(D.SIG,'alternatePolarity'),'missing SIG.alternatePolarity');
    assert(numel(D.ADC.SweepPolarity) == numel(D.ADC.SweepOnsets), ...
        'SweepPolarity (%d) must align with SweepOnsets (%d)', ...
        numel(D.ADC.SweepPolarity),numel(D.ADC.SweepOnsets));
    assert(all(ismember(D.ADC.SweepPolarity,[-1 1])),'SweepPolarity must be +/-1');
    assert(D.SIG.alternatePolarity == conds(i).Alt, ...
        'SIG.alternatePolarity does not reflect how the condition was run');
    % It must stay OUT of informativeParams: those become grouping
    % dimensions in extractABRResponses.
    assert(~ismember('alternatePolarity',cellstr(D.SIG.informativeParams)), ...
        'alternatePolarity must not be an informativeParam');
    if conds(i).Alt
        assert(sum(D.ADC.SweepPolarity == -1) == floor(numel(D.ADC.SweepOnsets)/2), ...
            'An alternating condition should have half its sweeps inverted');
    else
        assert(all(D.ADC.SweepPolarity == 1),'A fixed condition must be all +1');
    end
    % ...and it must survive a load back into the data model.
    b2 = mabr.data.io.importLegacy(ffn);
    assert(isequal(b2.SweepPolarity(:)',double(D.ADC.SweepPolarity(:))'), ...
        'importLegacy lost SweepPolarity');

    % --- 2. filename regex ---------------------------------------------
    [~,fn,ext] = fileparts(ffn);
    assert(~isempty(regexp([fn ext],regex,'once')), ...
        'Filename "%s" does not match the offline regex',[fn ext]);
    fprintf('  wrote %s  (Fs=%g, %d onsets)\n',[fn ext],D.ADC.SampleRate,numel(D.ADC.SweepOnsets));
end
fprintf('  PASS: struct contract + polarity fields + filename regex\n');

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

% --- 4. pooled files, compact refusal, batchABRAnalysis (optional) ------------
% Same prerequisite as leg 3: the legacy chain needs helper_fnc on the path.
if ~exist('parfor_progress','file')
    fprintf('  SKIP: parfor_progress not on path; pooled-file, compact-file and batchABRAnalysis legs not run.\n');
else
    legDir  = fullfile(tempdir,'mabr_roundtrip_legs');
    if isfolder(legDir), rmdir(legDir,'s'); end
    poolDir = fullfile(legDir,'pool');
    compDir = fullfile(legDir,'compact');
    mkdir(poolDir); mkdir(compDir);
    cleanLegs = onCleanup(@() rmdir(legDir,'s'));

    % Two files of the SAME condition (8 kHz, 30 dB) with different sweep
    % counts, plus one file of another condition so pooling cannot leak. Two
    % writes in one second get a "_2" suffix, which the default pattern above
    % does not match (it ends at the timestamp), so this leg allows one.
    regexPool = "^SUBJ-ID-(\d+)_Frequency-([\dp]+kHz)_Level-(m?[\dp]+dB)_(\d{6}T\d{6})(_\d+)?\.abr";
    nReq = [64 40 64];
    ffnP = strings(1,3);
    ffnP(1) = string(mabr.data.io.writeABR(make_synthetic_block(Fs,df,8,30,false,nReq(1)),poolDir,'SUBJ_ID_999'));
    ffnP(2) = string(mabr.data.io.writeABR(make_synthetic_block(Fs,df,8,30,false,nReq(2)),poolDir,'SUBJ_ID_999'));
    ffnP(3) = string(mabr.data.io.writeABR(make_synthetic_block(Fs,df,16,30,false,nReq(3)),poolDir,'SUBJ_ID_999'));
    nOn = zeros(1,3);
    for i = 1:3
        a = load(ffnP(i),'-mat','ABR_Data');
        nOn(i) = numel(a.ABR_Data.ADC.SweepOnsets);
    end
    assert(numel(unique(ffnP)) == 3,'writeABR gave two files the same name');

    T = parseABRFiles(poolDir,'filePattern',regexPool);
    assert(height(T) == 3,'parseABRFiles returned %d rows for 3 files',height(T));
    txt = evalc("[S,U] = extractABRResponses(T,[0 10]);");
    i8  = find(U.Frequency == 8);  i16 = find(U.Frequency == 16);  iL = find(U.Level == 30);
    assert(size(S{i8,iL},2) == nOn(1) + nOn(2), ...
        'two files of one condition must be pooled: %d sweeps expected (%d + %d), got %d', ...
        nOn(1)+nOn(2),nOn(1),nOn(2),size(S{i8,iL},2));
    assert(size(S{i16,iL},2) == nOn(3),'the other condition got %d sweeps, expected %d',size(S{i16,iL},2),nOn(3));
    assert(contains(txt,sprintf('pooled %d sweeps from 2 files',nOn(1)+nOn(2))), ...
        'extractABRResponses did not say that it pooled two files');
    fprintf('  PASS: two files of one condition pooled (%d + %d = %d sweeps), other condition untouched (%d)\n', ...
        nOn(1),nOn(2),size(S{i8,iL},2),size(S{i16,iL},2));

    % A file from an intermixed run holds the sweep windows end to end, not a
    % continuous trace; cutting baselines from it would read the previous
    % sweep's response, so the legacy extractor must refuse it.
    mabr.data.io.writeABR(make_compact_block(Fs,df,8,30,20),compDir,'SUBJ_ID_999');
    Tc = parseABRFiles(compDir,'filePattern',regexPool);
    assert(height(Tc) == 1,'parseABRFiles returned %d rows for the compact file',height(Tc));
    id = '';
    try
        extractABRResponses(Tc,[0 10]);
    catch ME
        id = ME.identifier;
    end
    assert(strcmp(id,'abr_analysis:extractABRResponses:compactFile'), ...
        'a compact file must be refused with abr_analysis:extractABRResponses:compactFile, got "%s"',id);
    fprintf('  PASS: compact (intermixed-layout) file refused with %s\n',id);

    % The repaired all-in-one driver over the same folder: two conditions at
    % one level each cannot give a threshold (Inf), but the whole chain from
    % file names to permutation test has to run and hand back one row of
    % thresholds per session. A machine without the Statistics or Signal
    % Processing Toolbox gets the missing-dependency error: SKIP, not FAIL.
    try
        evalc("[thB,lmB] = batchABRAnalysis(poolDir,'filePattern',regexPool,'plot',false,'Seed',1);");
        assert(iscell(thB) && isscalar(thB) && isequal(size(thB{1}),[1 2]),'batchABRAnalysis returned an unexpected shape');
        assert(isstruct(lmB{1}) && isequal(size(lmB{1}.permResult),[1 2]),'batchABRAnalysis lost the permutation results');
        fprintf('  PASS: batchABRAnalysis ran end to end (1 session, thresholds %s)\n',mat2str(thB{1}));
    catch ME
        if strcmp(ME.identifier,'abr_analysis:missingDependency')
            fprintf('  SKIP: batchABRAnalysis needs more than this machine has (%s)\n',strtok(ME.message,newline));
        else
            rethrow(ME);
        end
    end
end

fprintf('== verify_data_roundtrip PASSED ==\n');
end


% =====================================================================
function block = make_synthetic_block(Fs,df,freqkHz,leveldB,alt,nSweeps)
% A short block with a repeatable evoked wavelet at each sweep onset, so the
% offline pipeline has something to segment and correlate.
if nargin < 6, nSweeps = 64; end
sweepRate = 21.1;
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
    'alternatePolarity',alt, ...
    'informativeParams',{{'Frequency','Level'}}, ...
    'Label',{{sprintf('Frequency = %g kHz',freqkHz),sprintf('Level = %g dB',leveldB)}});
stim = struct('Meta',meta,'SampleRate',Fs);

block = mabr.data.Block(stim,rec);
if alt
    block.SweepPolarity = repmat([1 -1],1,ceil(nSweeps/2));
    block.SweepPolarity = block.SweepPolarity(1:nSweeps);
else
    block.SweepPolarity = ones(1,nSweeps);
end
end

% =====================================================================
function block = make_compact_block(Fs,df,freqkHz,leveldB,nSweeps)
% The layout an INTERMIXED run writes: no continuous trace, just the sweep
% windows laid end to end (onsets 1, L+1, 2L+1, ... and ADC.SweepLength = L).
% L is a multiple of the decimation factor so that the saved onsets still
% step by exactly the saved SweepLength.
L = df*round(0.01*Fs/df);
tw = (0:round(0.002*Fs)-1)'/Fs;
wavelet = single(sin(2*pi*800*tw).*hann(numel(tw)))*1e-6*(1+leveldB/60);

data   = 1e-7*randn(nSweeps*L,1,'single');
onsets = 1 + (0:nSweeps-1)'*L;
for k = 1:nSweeps
    i0 = onsets(k) + round(0.001*Fs);
    data(i0:i0+numel(wavelet)-1) = data(i0:i0+numel(wavelet)-1) + wavelet;
end

rec = mabr.data.Recording(Fs,data,onsets,L,df);

meta = struct('Frequency',freqkHz,'Level',leveldB,'Polarity',1, ...
    'alternatePolarity',false, ...
    'informativeParams',{{'Frequency','Level'}}, ...
    'Label',{{sprintf('Frequency = %g kHz',freqkHz),sprintf('Level = %g dB',leveldB)}});
stim = struct('Meta',meta,'SampleRate',Fs);

block = mabr.data.Block(stim,rec);
block.SweepPolarity = ones(1,nSweeps);
end
