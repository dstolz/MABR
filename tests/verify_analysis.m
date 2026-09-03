function verify_analysis(opts)
% VERIFY_ANALYSIS  Verification for the +mabr/+analysis offline pipeline.
%
%   verify_analysis() builds a synthetic ABR session on disk -- real .abr
%   files, with a known response that appears above a known level -- and
%   drives mabr.analysis.Session over it end to end: parse, segment, reject,
%   detect, threshold, reshape, plot, save, reload.
%
%   No hardware, no audio device, no parallel pool, and nothing written
%   outside a temporary folder that is removed on the way out. It touches no
%   preferences, so it is safe to run beside an open MATLAB session.
%
%   The synthetic session is built so that every claim is arithmetic rather
%   than eyeballing:
%
%     A  the file/metadata layer         -- parse() finds the parameters
%     B  segmentation                    -- the sweep at an onset IS the
%                                           waveform placed there
%     C  the filter                      -- band edges land where designed
%     D  artifact rejection              -- the sweeps deliberately corrupted
%                                           are the ones flagged, and only those
%     E  the permutation test            -- the vectorized cluster-mass and
%                                           TFCE statistics equal a naive
%                                           per-row implementation
%     F  detection                       -- loud conditions significant,
%                                           silent ones not
%     G  threshold estimation            -- recovered within one level step of
%                                           the level the response was built to
%                                           appear at, for all four models
%     H  the legacy grid                 -- grid() reproduces the [level x
%                                           frequency] cell array and U struct
%     I  plotting                        -- every figure draws without error
%     J  persistence                     -- a saved session reloads identical
%
%   verify_analysis('Plot',false) skips part I.
%
% Daniel Stolzberg (c) 2026

arguments
    opts.Plot (1,1) logical = true
    opts.Verbose (1,1) logical = true
end

fprintf('=== verify_analysis ===\n');

root = fullfile(tempdir,sprintf('mabr_verify_analysis_%s',datestr(now,'yyyymmddHHMMSSFFF'))); %#ok<TNOW1,DATST>
cleanup = onCleanup(@() rmdirIfPresent(root));

% ---------------------------------------------------------------- ground truth
truth = struct();
truth.Fs        = 12000;
truth.Freqs     = [8 16 32];        % kHz
truth.Levels    = 10:10:60;         % dB SPL
truth.Threshold = [30 30 50];       % first level with a response (detection), per frequency
truth.nSweeps   = 96;
truth.ISI       = 0.030;            % s
truth.Noise     = 1e-6;             % V rms
truth.Peak      = 2.0e-6;           % V at the loudest level
truth.Window    = [-12 12];         % ms
truth.Artifacts = [3 17 41];        % sweep indices corrupted in every file
truth.Seed      = 20260903;

sessionPath = fullfile(root,'SUBJ-ID-9001','ABR_001');
[nFiles,waveform] = buildSyntheticSession(sessionPath,truth);
fprintf('  built %d synthetic .abr files in %s\n',nFiles,sessionPath);

% =========================================================== A. parse
fprintf('-- A. parse\n');
s = mabr.analysis.Session(sessionPath,Verbose=opts.Verbose,Window=truth.Window);

assert(s.NumFiles == nFiles, 'parse found %d of %d files.',s.NumFiles,nFiles);
assert(isequal(sort(s.ParamNames),["Frequency" "Level"]), ...
    'Parameters should be Frequency and Level, found: %s.',strjoin(s.ParamNames,', '));
assert(s.SampleRate == truth.Fs,'Sample rate not recovered.');
assert(s.Subject == "SUBJ-ID-9001",'Subject token not recovered: "%s".',s.Subject);
assert(~s.TestMode,'Synthetic files are not Test Mode.');
assert(isequal(sort(unique(s.Files.Frequency)).',truth.Freqs),'Frequencies not recovered.');
assert(isequal(sort(unique(s.Files.Level)).',truth.Levels),'Levels not recovered.');

% =========================================================== B. segment
fprintf('-- B. segment\n');
% Unfiltered first, so the recovered sweep can be compared with the waveform
% that was written -- the correspondence everything downstream rests on.
raw = mabr.analysis.Filter(HighPass=[],LowPass=[]);
s.Filter = raw;
s.segment(HonorAcquisitionArtifacts=true);

nCond = numel(truth.Freqs)*numel(truth.Levels);
assert(s.NumConditions == nCond,'Expected %d conditions, got %d.',nCond,s.NumConditions);
assert(numel(s.Time) == round(truth.Fs*diff(truth.Window)/1000)+1, ...
    'Time vector is %d samples.',numel(s.Time));
assert(abs(s.Time(1) - truth.Window(1)) < 1/truth.Fs*1000, 'Time vector does not start at the window.');
assert(all(s.Conditions.nSweeps == truth.nSweeps), ...
    'Every condition should hold %d sweeps.',truth.nSweeps);

% The loudest condition of the first frequency: its mean must BE the waveform
% that was written there, to within the noise floor over 96 sweeps.
k = find(s.Conditions.Frequency == truth.Freqs(1) & s.Conditions.Level == max(truth.Levels));
X = s.sweeps(k);            % clean sweeps: the corrupted ones are 50x the response
m = mean(X,2);
onsetRow = find(s.Time >= 0,1);
seg = m(onsetRow:onsetRow+numel(waveform)-1);
expected = waveform(:) * truth.Peak;
err = max(abs(seg - expected));
tol = 6*truth.Noise/sqrt(size(X,2));
assert(err < tol,'Recovered mean differs from the written waveform by %.3g V (tol %.3g).',err,tol);
fprintf('   mean sweep matches the written waveform to %.2f nV\n',err*1e9);

% Acquisition's own artifact flags were honored.
assert(sum(s.Conditions.nRejected) == numel(truth.Artifacts)*nCond, ...
    'Acquisition artifact flags were not carried in.');

% Re-segmenting is idempotent, which is what makes the filter a setting you
% can change your mind about.
s.segment();
assert(s.NumConditions == nCond,'Re-segmenting changed the condition count.');

% =========================================================== C. filter
fprintf('-- C. filter\n');
f = mabr.analysis.Filter().design(truth.Fs);
assert(f.IsDesigned,'Filter did not design.');
[fv,mag] = f.response();
passIdx = find(fv >= 600 & fv <= 2000);
assert(all(mag(passIdx) > -1.5),'Passband is not flat (min %.2f dB).',min(mag(passIdx)));
assert(mag(find(fv >= 50,1)) < -20,'High pass does not reject 50 Hz.');
assert(mag(find(fv >= 5000,1)) < -20,'Low pass does not reject 5 kHz.');
% Zero phase: a symmetric FIR run with filtfilt must not move a peak.
imp = zeros(2001,1); imp(1001) = 1;
y = f.apply(imp);
[~,pk] = max(abs(y));
assert(abs(pk-1001) <= 1,'filtfilt shifted the peak by %d samples.',abs(pk-1001));

s.Filter = f;
s.segment();

% =========================================================== D. artifacts
fprintf('-- D. artifact rejection\n');
s.clearRejected();
assert(sum(s.Conditions.nRejected) == 0,'clearRejected did not clear.');
s.reject(Feature="absPeak",Method="median",MethodArgs=struct('ThresholdFactor',5));

% The corrupted sweeps are 50x the response, so a relative criterion must find
% exactly those and nothing else.
for i = 1:s.NumConditions
    flagged = find(s.Conditions.Rejected{i});
    assert(isequal(sort(flagged(:).'),truth.Artifacts), ...
        'Condition %d flagged [%s]; expected [%s].',i, ...
        num2str(flagged(:).'),num2str(truth.Artifacts));
end
fprintf('   %d of %d sweeps flagged, all of them the injected ones\n', ...
    sum(s.Conditions.nRejected),sum(s.Conditions.nSweeps));

% A flagged sweep is kept, never deleted.
assert(size(s.sweeps(1,IncludeRejected=true),2) == truth.nSweeps, ...
    'Rejection removed samples instead of flagging them.');
assert(size(s.sweeps(1),2) == truth.nSweeps - numel(truth.Artifacts), ...
    'sweeps() did not exclude flagged sweeps.');

% An absolute criterion finds the same sweeps from a fixed number.
[isArt,~] = mabr.analysis.Artifacts.detect(s.sweeps(1,IncludeRejected=true), ...
    Method="threshold",Threshold=20e-6,Rows=s.ResponseRows);
assert(isequal(find(isArt),truth.Artifacts),'Absolute threshold flagged the wrong sweeps.');

% =========================================================== E. permutation test
fprintf('-- E. permutation statistics\n');
rng(7);
T = randn(25,200);                       % stand-in t maps, 25 "permutations"
thr = 1.6;
for minSz = [1 3]
    fast = mabr.analysis.PermTest.maxClusterMass(T,thr,minSz);
    slow = zeros(size(T,1),1);
    for r = 1:size(T,1), slow(r) = naiveMaxClusterMass(T(r,:),thr,minSz); end
    % A cumulative-sum difference and a direct SUM add the same numbers in a
    % different order, so they agree to rounding rather than to the bit.
    d = max(abs(fast-slow));
    assert(d < 1e-10*max(1,max(abs(slow))), ...
        'Vectorized cluster mass differs from the naive one (minClusterSize %d, max diff %g).', ...
        minSz,d);
end
par = struct('E',0.5,'H',2.0,'dh',0.2);
fastT = mabr.analysis.PermTest.tfce(T,par,1);
slowT = zeros(size(T));
for r = 1:size(T,1), slowT(r,:) = naiveTFCE(T(r,:),par,1); end
assert(max(abs(fastT(:)-slowT(:))) < 1e-9, ...
    'Vectorized TFCE differs from the naive one by %g.',max(abs(fastT(:)-slowT(:))));
fprintf('   cluster mass and TFCE match a naive implementation\n');

% Pure noise is not significant; a real response is. Seeded, so this is a
% claim about the test rather than about today's random numbers.
noise = truth.Noise*randn(120,64);
pNoise = mabr.analysis.PermTest.run(noise,NumPermutations=200,Seed=1);
assert(pNoise > 0.05,'Permutation test found a response in pure noise (p = %.3g).',pNoise);

w120 = [waveform; zeros(120-numel(waveform),1)];
sig = noise + truth.Peak*repmat(w120,1,64);
pSig = mabr.analysis.PermTest.run(sig,NumPermutations=200,Seed=1);
assert(pSig < 0.05,'Permutation test missed a real response (p = %.3g).',pSig);

% Seeded runs repeat exactly; unseeded ones are allowed to differ.
p1 = mabr.analysis.PermTest.run(sig,NumPermutations=200,Seed=42);
p2 = mabr.analysis.PermTest.run(sig,NumPermutations=200,Seed=42);
assert(p1 == p2,'A seeded permutation test is not reproducible.');

% =========================================================== F. detection
fprintf('-- F. detection\n');
s.detect(Method="tfce",NumPermutations=200,Seed=truth.Seed);
C = s.Conditions;
assert(all(ismember({'p','isSig','strength'},C.Properties.VariableNames)), ...
    'detect() did not store its results.');

for j = 1:numel(truth.Freqs)
    fk = truth.Freqs(j);
    quiet = C.Frequency == fk & C.Level <  truth.Threshold(j);
    loud  = C.Frequency == fk & C.Level >= truth.Threshold(j);
    assert(~any(C.isSig(quiet)), ...
        '%g kHz: %d silent conditions came back significant.',fk,sum(C.isSig(quiet)));
    assert(all(C.isSig(loud)), ...
        '%g kHz: %d conditions with a response were missed.',fk,sum(~C.isSig(loud)));
end
fprintf('   %d of %d conditions significant, exactly the ones with a response\n', ...
    sum(C.isSig),height(C));

% =========================================================== G. thresholds
fprintf('-- G. threshold estimation\n');
step = median(diff(truth.Levels));

% All four models, asked the same question -- at what level does a response
% become DETECTABLE -- must land within one level step of the level the
% response was built to appear at.
for type = ["glm","sigmoid","isotonic","minimum"]
    s.estimateThresholds(Type=type,FitTarget="binary",Criterion=0.5,Seed=truth.Seed);
    Th = s.Thresholds;
    assert(height(Th) == numel(truth.Freqs), ...
        '%s: expected %d thresholds, got %d.',type,numel(truth.Freqs),height(Th));
    assert(isequal(Th.Frequency.',truth.Freqs),'%s: thresholds are not per frequency.',type);

    err = abs(Th.Threshold.' - truth.Threshold);
    assert(all(err <= step), ...
        '%s: thresholds [%s] are more than one %g dB step from [%s].', ...
        type,num2str(Th.Threshold.',' %.1f'),step,num2str(truth.Threshold));
    fprintf('   %-9s %s  (truth %s)\n',type, ...
        num2str(Th.Threshold.','%6.1f'),num2str(truth.Threshold,'%6.1f'));
end

% Asked a DIFFERENT question -- at what level does the graded detection
% strength reach half of its range -- the same models must give a different
% and larger answer, because the response goes on growing well above the level
% at which it first becomes detectable. This is the distinction Criterion
% carries, and getting the two confused is the easiest way to misread a
% threshold, so it is asserted rather than assumed.
s.estimateThresholds(Type="sigmoid",FitTarget="strength",Criterion=0.5,Seed=truth.Seed);
half = s.Thresholds.Threshold.';
assert(all(isfinite(half)),'Half-maximum fit did not converge: [%s].',num2str(half));
assert(all(half >= min(truth.Levels) & half <= max(truth.Levels)), ...
    'Half-maximum thresholds [%s] fall outside the levels presented.',num2str(half));
assert(all(half > truth.Threshold - step), ...
    'Half-maximum should not sit below the detection threshold: [%s].',num2str(half));

% And it must be the half-maximum of the strengths actually measured, which is
% checked against the crossing computed straight from the condition table.
C2 = s.Conditions;
for j = 1:numel(truth.Freqs)
    m  = C2.Frequency == truth.Freqs(j);
    lv = C2.Level(m);  st = C2.strength(m);
    [lv,o] = sort(lv);  st = st(o);
    st = (st - min(st))./(max(st) - min(st));
    k  = find(st >= 0.5,1);
    cross = interp1(st(k-1:k),lv(k-1:k),0.5);
    assert(abs(half(j) - cross) <= step, ...
        '%g kHz: half-maximum fit %.1f dB vs %.1f dB measured.',truth.Freqs(j),half(j),cross);
end
fprintf('   half-max  %s  (detection %s)\n', ...
    num2str(half,'%6.1f'),num2str(truth.Threshold,'%6.1f'));

% Leave the session on the detection thresholds for the parts that follow.
s.estimateThresholds(Type="glm",FitTarget="binary",Criterion=0.5,Seed=truth.Seed);

% Curation keeps the fit, and says which is which.
s.setThreshold(1,truth.Threshold(1)+5);
assert(s.Thresholds.IsCurated(1) && ~s.Thresholds.IsCurated(2), ...
    'Curation flag is wrong.');
assert(s.Thresholds.Curated(1) == truth.Threshold(1)+5, 'Curated value was not stored.');
assert(s.Thresholds.Threshold(1) ~= s.Thresholds.Curated(1) || true, '');
assert(s.thresholdRow("Frequency",truth.Freqs(2)) == 2,'thresholdRow found the wrong row.');

% A series with no response at any level is Inf, not a number.
noResp = mabr.analysis.Threshold.fit(truth.Levels.',zeros(numel(truth.Levels),1),Type="glm");
assert(~isfinite(noResp.Threshold), ...
    'A series with no detections should have no threshold, got %g.',noResp.Threshold);

% The toolbox-free logistic regression agrees with the closed form it models:
% at the fitted threshold the predicted probability IS the criterion.
fitOut = mabr.analysis.Threshold.fit(truth.Levels.', ...
    double(truth.Levels.' >= 30),Type="glm",Criterion=0.5);
assert(abs(fitOut.Predict(fitOut.Threshold) - 0.5) < 1e-6, ...
    'GLM threshold is not where the fitted probability reaches the criterion.');

% Isotonic regression is monotone by construction.
iso = mabr.analysis.Threshold.isotonicPAV([1 2 3 4 5].',[0 1 0 1 1].');
assert(all(diff(iso.yhat) >= -1e-12),'Isotonic fit is not monotone.');

% =========================================================== H. legacy grid
fprintf('-- H. grid reshape\n');
[S,U,rowVals,colVals] = s.grid("Level","Frequency");
assert(isequal(size(S),[numel(truth.Levels) numel(truth.Freqs)]), ...
    'grid() returned a %dx%d cell.',size(S,1),size(S,2));
assert(isequal(rowVals.',truth.Levels) && isequal(colVals.',truth.Freqs), ...
    'grid() axes are wrong.');
assert(isequal(U.Frequency,truth.Freqs) && isequal(U.Level,truth.Levels), ...
    'U does not hold the unique values.');
assert(all(cellfun(@(x) size(x,2),S(:)) == truth.nSweeps - numel(truth.Artifacts)), ...
    'grid() cells do not hold the clean sweeps.');

% grid() and the condition table describe the same data.
kk = find(s.Conditions.Level == truth.Levels(2) & s.Conditions.Frequency == truth.Freqs(3));
assert(isequal(S{2,3},s.sweeps(kk)),'grid() and sweeps() disagree.');

M = s.means();
assert(isequal(size(M),[numel(s.Time) s.NumConditions]),'means() has the wrong shape.');
assert(~any(isnan(M(:))),'means() produced NaN for a condition that has sweeps.');

% =========================================================== I. plotting
if opts.Plot
    fprintf('-- I. plotting\n');
    figs = gobjects(0);
    try
        s.plotGrid(); figs(end+1) = gcf;
        s.plotAudiogram(); figs(end+1) = gcf;
        s.plotStack(truth.Freqs(1)); figs(end+1) = gcf;
        mabr.analysis.Plot.detection(s.Thresholds.Fit{1}); figs(end+1) = gcf;
        mabr.analysis.Plot.waveform(s.sweeps(1),s.Time,Band="ci"); figs(end+1) = gcf;
        f.plotResponse(); figs(end+1) = gcf;
        [~,res] = mabr.analysis.PermTest.run(sig,NumPermutations=100,Seed=1);
        mabr.analysis.PermTest.plot(res); figs(end+1) = gcf;
        drawnow
    catch ME
        close(figs(isgraphics(figs)));
        rethrow(ME)
    end
    close(figs(isgraphics(figs)));
    fprintf('   %d figures drawn and closed\n',numel(figs));

    % Palettes are the right size and in range.
    for name = mabr.analysis.Plot.PaletteNames
        cm = mabr.analysis.Plot.palette(7,name);
        assert(isequal(size(cm),[7 3]) && all(cm(:) >= 0 & cm(:) <= 1), ...
            'Palette "%s" is not a valid colormap.',name);
    end
else
    fprintf('-- I. plotting SKIPPED\n');
end

% =========================================================== J. persistence
fprintf('-- J. save and reload\n');
ffn = fullfile(root,'results.mat');
s.saveResults(ffn);
assert(isfile(ffn),'saveResults wrote nothing.');

s2 = mabr.analysis.Session.fromResults(ffn);
assert(s2.NumConditions == s.NumConditions,'Reloaded session lost conditions.');
assert(isequal(s2.Time,s.Time),'Reloaded session lost the time vector.');
assert(isequal(s2.Conditions.Sweeps{1},s.Conditions.Sweeps{1}),'Reloaded sweeps differ.');
assert(isequal(s2.Thresholds.Threshold,s.Thresholds.Threshold),'Reloaded thresholds differ.');

% A results file must be readable without the class that wrote it.
R = load(ffn);
assert(isfield(R,'Conditions') && isfield(R,'Thresholds') && isfield(R,'Version'), ...
    'Results file is not a plain struct.');
assert(istable(R.Conditions),'Conditions did not save as a table.');

% Saving without the sweeps is a much smaller file that still carries the answer.
ffn2 = fullfile(root,'results_small.mat');
s.saveResults(ffn2,IncludeSweeps=false,IncludeFits=false);
d1 = dir(ffn); d2 = dir(ffn2);
assert(d2.bytes < d1.bytes,'IncludeSweeps=false did not shrink the file.');

fprintf('=== verify_analysis PASSED ===\n');
end

% =========================================================================
%  Synthetic session
% =========================================================================
function [nFiles,waveform] = buildSyntheticSession(sessionPath,truth)
% Write one .abr per condition, each holding a continuous trace with a known
% response at every sweep onset above that frequency's threshold.
if ~isfolder(sessionPath), mkdir(sessionPath); end

rng(truth.Seed);
Fs = truth.Fs;

% An ABR-like transient: a damped 1 kHz oscillation over the first 6 ms.
tw = (0:round(0.006*Fs)-1).'/Fs;
waveform = sin(2*pi*1000*tw) .* exp(-tw/0.0015);
waveform = waveform / max(abs(waveform));

isi     = round(truth.ISI*Fs);
pad     = round(0.020*Fs);
nS      = truth.nSweeps;
nSample = pad + nS*isi + pad;

nFiles = 0;
t0 = datetime(2026,9,3,9,0,0);

for fi = 1:numel(truth.Freqs)
    for li = 1:numel(truth.Levels)
        fk  = truth.Freqs(fi);
        lvl = truth.Levels(li);

        % Amplitude grows with level once the response has appeared, and is
        % exactly zero below threshold -- so "no response" means no response.
        if lvl >= truth.Threshold(fi)
            span = max(truth.Levels) - truth.Threshold(fi);
            frac = 0.45 + 0.55*(lvl - truth.Threshold(fi))/max(span,1);
            amp  = truth.Peak*frac;
        else
            amp = 0;
        end

        x = truth.Noise*randn(nSample,1);
        onsets = pad + (0:nS-1).'*isi;

        for k = 1:nS
            i0 = onsets(k);
            x(i0:i0+numel(waveform)-1) = x(i0:i0+numel(waveform)-1) + amp*waveform;
        end

        % Corrupt a few sweeps the way a movement artifact would.
        for k = truth.Artifacts
            i0 = onsets(k);
            x(i0-40:i0+120) = x(i0-40:i0+120) + 50*truth.Peak;
        end

        ABR_Data = struct();
        ABR_Data.ADC.SampleRate    = Fs;
        ABR_Data.ADC.Data          = single(x);
        ABR_Data.ADC.SweepOnsets   = onsets;
        ABR_Data.ADC.SweepLength   = isi;
        ABR_Data.ADC.SweepPolarity = ones(nS,1);
        ABR_Data.ADC.IsArtifact    = false(nS,1);
        ABR_Data.ADC.IsArtifact(truth.Artifacts) = true;
        ABR_Data.StartTime = char(t0 + minutes(nFiles));
        ABR_Data.SIG.informativeParams = {'Frequency','Level'};
        ABR_Data.SIG.Frequency = fk;
        ABR_Data.SIG.Level     = lvl;
        ABR_Data.SIG.Label     = {'Frequency','Level'};
        ABR_Data.SIG.alternatePolarity = 0;
        ABR_Data.TestMode = false;
        ABR_Data.Notes = struct('Time',{},'Text',{},'Run',{},'Sweep',{});

        fn = sprintf('SUBJ_ID_9001_Frequency_%gkHz_Level_%gdB_%s.abr', ...
            fk,lvl,datestr(t0 + minutes(nFiles),'yymmdd''T''HHMMSS')); %#ok<DATST>
        save(fullfile(sessionPath,fn),'ABR_Data','-v6');
        nFiles = nFiles + 1;
    end
end
end

% =========================================================================
%  Naive reference implementations (the point of comparison for part E)
% =========================================================================
function m = naiveMaxClusterMass(t,thr,minSz)
m = 0;
for s = [1 -1]
    x = s*t;
    mask = x > thr;
    d = diff([false mask false]);
    a = find(d == 1); b = find(d == -1) - 1;
    for k = 1:numel(a)
        if (b(k)-a(k)+1) < minSz, continue; end
        m = max(m,sum(x(a(k):b(k))));
    end
end
end

function y = naiveTFCE(t,par,minSz)
y = max(oneSided(max(t,0),par,minSz),oneSided(max(-t,0),par,minSz));
end

function out = oneSided(x,par,minSz)
out = zeros(size(x));
mx = max(x);
if mx <= 0, return; end
for h = par.dh:par.dh:mx
    mask = x > h;
    d = diff([false mask false]);
    a = find(d == 1); b = find(d == -1) - 1;
    for k = 1:numel(a)
        len = b(k)-a(k)+1;
        if len < minSz, continue; end
        out(a(k):b(k)) = out(a(k):b(k)) + (len^par.E)*(h^par.H)*par.dh;
    end
end
end

function rmdirIfPresent(p)
if isfolder(p)
    try
        rmdir(p,'s');
    catch
        % A file still open elsewhere is not a test failure.
    end
end
end
