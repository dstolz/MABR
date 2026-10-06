function verify_offline_thresholds()
% verify_offline_thresholds  Threshold fixes, SeriesThreshold methods and analysis Settings, offline.
%
%   Covers the threshold layer of the offline analysis without a file or a
%   session: mabr.analysis.PermTest's bounded TFCE (a direct call on
%   near-noiseless sweeps returns in seconds, and nothing below the cap
%   changes), mabr.analysis.Threshold (defect fixes, bit-identical legacy fits,
%   the Firth GLM and its profile interval, the ABRpresto-like fit, rebuilt
%   predictors), mabr.analysis.SeriesThreshold (the named methods, the
%   descending rule on the probe's real permutation p-values, censoring,
%   overrides, conventions, the curated value) and mabr.analysis.Settings
%   (defaults -- each wave's own latency shift among them -- steps,
%   persistence, profiles, problems, and the latency reference: the sound's
%   conduction delay by mode, the offset it makes, and that it is a peaks
%   setting). No hardware, no pool, no window; the one pref it can write is
%   guarded and put back.
%
%   Run:  verify_offline_thresholds
%
%   See also mabr.analysis.Threshold, mabr.analysis.SeriesThreshold,
%   mabr.analysis.Settings

fprintf('== verify_offline_thresholds ==\n');
t0 = tic;
figs0 = findall(groot,'Type','figure');
tmp = tempname;
mkdir(tmp);
cleanTmp = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(tmp));

ST = mabr.analysis.SeriesThreshold;  % static methods through an instance
L  = (0:10:80).';                   % the canonical level series
step = 10;

% Unicode the labels and texts use, spelled by code point so this file stays ASCII.
ARROW = char(8594); PM = char(177); GE = char(8805); ELL = char(8230);
NDASH = char(8211); LE = char(8804); ALPHA = char(945);

%% ====================================================== A. legacy fits unchanged
% Captured from Threshold.fit BEFORE it was edited (Seed 1): Penalty "none"
% must reproduce every number to the last bit.
x  = (0:10:80).';
yb = [0 0 0 1 0 1 1 1 1].';
yg = [0.10 0.12 0.21 0.33 0.58 0.79 0.93 1.00 1.02].';
ys = [120 150 170 400 900 1500 2100 2600 2800].';
w  = [100 120 110 90 128 128 64 128 100].';
F  = @mabr.analysis.Threshold.fit;
base = {
    'glm',           @() F(x,yb,Type="glm",Seed=1),          34.970018935673416, [1.3473139376824315 76.629420913712508]
    'glm weighted',  @() F(x,yb,Type="glm",Weights=w,Seed=1), 37.20746261300539, [35.568245294236633 38.89709816382728]
    'sigmoid',       @() F(x,yg,Type="sigmoid",Seed=1),       39.556201720986174, [38.96769588048258 40.146083687127941]
    'sigmoid w',     @() F(x,ys,Type="sigmoid",Weights=w,Seed=1), 49.063331254622817, [48.082226879011991 50.046729783990635]
    'sigmoid fit',   @() F(x,ys,Type="sigmoid",Asymptotes="fit",Seed=1), 50.346736230727828, [48.881695040641915 51.717005850209183]
    'isotonic',      @() F(x,yg,Type="isotonic",Seed=1),      40, [NaN NaN]
    'isotonic interp', @() F(x,yg,Type="isotonic",Interpolate=true,Seed=1), 39.200000000000003, [NaN NaN]
    'minimum',       @() F(x,yg,Type="minimum",Seed=1),       40, [NaN NaN]
    'glm separated', @() F(x,double(x>=40),Type="glm",Seed=1), 34.915337483545891, [-27.48656605416717 94.209216448977429]
    'glm crit .75',  @() F(x,yb,Type="glm",Criterion=0.75,CINumSamples=500,CIAlpha=0.1,Seed=1), 43.471593626092705, [28.106329112798893 86.569122932725776]
    };
for k = 1:size(base,1)
    o = base{k,2}();
    assert(isequal(o.Threshold,base{k,3}) && isequaln(o.CI,base{k,4}), ...
        'Threshold.fit %s changed: %.17g [%.17g %.17g], was %.17g [%.17g %.17g].', ...
        base{k,1},o.Threshold,o.CI,base{k,3},base{k,4});
    assert(o.Status == "ok" && isequal(o.CIOpen,[false false]), ...
        'Threshold.fit %s: Status "%s".',base{k,1},o.Status);
    if all(isnan(base{k,4}))
        assert(o.CIMethod == "none",'%s: CIMethod "%s", expected "none".',base{k,1},o.CIMethod);
    else
        assert(o.CIMethod == "montecarlo",'%s: CIMethod "%s", expected "montecarlo".',base{k,1},o.CIMethod);
    end
end
% estimate() -- the old Session path -- weights by nSweeps, exactly as before.
det = struct('p',num2cell([.5 .4 .3 .01 .2 .001 .001 .001 .001]), ...
    'isSig',num2cell(logical(yb.')),'strength',num2cell(ys.'),'nSweeps',num2cell(w.'));
e1 = mabr.analysis.Threshold.estimate(x,det,Type="glm",Seed=1);
e2 = mabr.analysis.Threshold.estimate(x,det,Type="sigmoid",FitTarget="p",Seed=1);
assert(isequal(e1.Threshold,37.20746261300539) && isequal(e1.CI,[35.568245294236633 38.89709816382728]), ...
    'Threshold.estimate glm changed: %.17g.',e1.Threshold);
assert(isequal(e2.Threshold,22.278417925695795) && isequal(e2.CI,[15.228344668544613 29.344976637862835]), ...
    'Threshold.estimate sigmoid/p changed: %.17g.',e2.Threshold);
f1 = F(x(1),yb(1));
assert(f1.Status == "insufficient" && isinf(f1.Threshold), 'One level: Status "%s".',f1.Status);
% 10 section 6.8: every fit-shaped struct carries the same fields, whoever made it
fitFields = ["Threshold","CI","CIMethod","Type","Criterion","Predict","Model","X","Y","Scale", ...
             "Converged","Message","Status"];
shaped = {e1, F(x,yb,Type="glm",Penalty="firth"), F(x,yg,Type="isotonic"), f1, ...
          mabr.analysis.Threshold.prestoFit(x,yg,0.3)};
for k = 1:numel(shaped)
    miss = fitFields(~isfield(shaped{k},fitFields));
    assert(isempty(miss),'Fit-shaped struct %d lacks %s.',k,strjoin(miss,', '));
end
fprintf('  PASS Threshold.fit/estimate (Penalty "none") reproduce the pre-change numbers bit for bit\n');

%% ====================================================== B. defects 1 and 2
d = mabr.analysis.Threshold.detect(ones(10,1));
assert(isnan(d.p) && ~d.isSig, 'Defect 1: one sweep gave p %g, isSig %d.',d.p,d.isSig);
o = F(x,yg,Type="isotonic",Extrapolate=false);
assert(all(isnan(o.CI)) && o.CIMethod == "none", ...
    'Defect 2: an isotonic fit with Extrapolate=false has CI [%g %g].',o.CI);
o = F(x,double(x>=40),Type="glm",Extrapolate=false,Seed=1);
assert(isequal(o.CI,[0 80]), 'Extrapolate=false must still clamp finite CI ends: [%g %g].',o.CI);
fprintf('  PASS defect 1 (untestable condition: p NaN, not significant) and defect 2 (NaN CI not clamped)\n');

%% ====================================================== B2. TFCE bounded in PermTest itself
% Threshold.detect raises the TFCE step before a near-noiseless test, but
% PermTest is public: called directly on sweeps whose |t| runs to ~1e7, its
% TFCE once integrated 0.1 at a time up to that -- 1e8 steps, a hang. It now
% takes at most MaxTFCESteps steps per map.
tb = tic;
assert(mabr.analysis.Threshold.MaxTFCESteps*2 <= mabr.analysis.PermTest.MaxTFCESteps, ...
    'PermTest''s TFCE cap (%d) must stand well above Threshold''s (%d), so detect() never meets it.', ...
    mabr.analysis.PermTest.MaxTFCESteps,mabr.analysis.Threshold.MaxTFCESteps);
truthB = mabrtest.SyntheticABR.defaults();
yB = mabrtest.SyntheticABR.template((0:119)/12,80,8,truthB);
rsB = RandStream('threefry','Seed',11);
% 1e-12 V of noise: near-noiseless, yet enough that the variance survives
% double precision (below ~1e-14 it rounds negative and t goes complex).
XB = repmat(yB(:),1,64) + 1e-12*randn(rsB,numel(yB),64);
t1 = tic;
[pB,rB] = mabr.analysis.PermTest.run(XB,Method="tfce",NumPermutations=1000,Seed=1);
secB = toc(t1);
assert(isreal(rB.t) && max(abs(rB.t)) > 1e6, ...
    'The near-noiseless fixture should have a real |t| over 1e6 (max %g).',max(abs(rB.t)));
assert(secB < 10,'A direct PermTest TFCE run on near-noiseless sweeps took %.1f s.',secB);
assert(pB == 1/1001 && isfinite(rB.statistic) && rB.statistic > max(rB.null), ...
    'Near-noiseless direct TFCE: p %g, statistic %g against a null up to %g.',pB,rB.statistic,max(rB.null));
% The cap is exactly "raise dh to |t| over MaxSteps", and only past the cap.
TB = 50*abs(randn(rsB,4,80));                      % one sign, so one |t| decides
mxB = max(TB(:));
A1 = mabr.analysis.PermTest.tfce(TB,struct('E',0.5,'H',2,'dh',0.1,'MaxSteps',40),1);
A2 = mabr.analysis.PermTest.tfce(TB,struct('E',0.5,'H',2,'dh',mxB/40),1);
assert(isequal(A1,A2),'A capped TFCE is not the TFCE at dh = max|t|/MaxSteps.');
A3 = mabr.analysis.PermTest.tfce(TB,struct('E',0.5,'H',2,'dh',0.1),1);
A4 = mabr.analysis.PermTest.tfce(TB,struct('E',0.5,'H',2,'dh',0.1,'MaxSteps',1e9),1);
assert(isequal(A3,A4) && ~isequal(A1,A3), ...
    'Below the cap (max |t| %.0f, %d steps) the TFCE must be unchanged, bit for bit.', ...
    mxB,mabr.analysis.PermTest.MaxTFCESteps);
expectError(@() mabr.analysis.PermTest.tfce(TB,struct('dh',0.1,'MaxSteps',Inf),1), ...
    'mabr:analysis:PermTest:maxSteps','An Inf MaxSteps');
expectError(@() mabr.analysis.PermTest.tfce(TB,struct('dh',0.1,'MaxSteps',0),1), ...
    'mabr:analysis:PermTest:maxSteps','A zero MaxSteps');
fprintf(['  PASS PermTest TFCE bounded: a direct run on near-noiseless sweeps (|t| %.2g) returns in ' ...
    '%.2f s with p 1/1001; capped = dh raised to max|t|/MaxSteps; unchanged below the cap (%.1f s)\n'], ...
    max(abs(rB.t)),secB,toc(tb));

%% ====================================================== B3. one-row maps count every run
% The observed t-map of every PermTest.run is ONE row, and find() on a one-row
% map returns row vectors: sortrows then saw a single row and every run after
% the first was dropped, so the observed cluster mass and TFCE were too low
% (p inflated, thresholds pushed up). A row on its own must give exactly what
% it gives as one row of a larger map, which was always right.
tc = tic;
row = zeros(1,60);
row(5:9)   = [3 4 5 4 3];                     % first run: mass 19
row(30:40) = 6;                                % second run: mass 66, the largest
row(50:52) = -5;                               % a negative run, for the two-sided paths
two = [row; fliplr(row)];
for minSz = [1 3]
    m1 = mabr.analysis.PermTest.maxClusterMass(row,2,minSz);
    m2 = mabr.analysis.PermTest.maxClusterMass(two,2,minSz);
    assert(m1 == 66 && m1 == m2(1), ...
        'One-row cluster mass %g (minClusterSize %d) should be the largest run, 66, as in a two-row map (%g).', ...
        m1,minSz,m2(1));
    par = struct('E',0.5,'H',2,'dh',0.1);
    A1 = mabr.analysis.PermTest.tfce(row,par,minSz);
    A2 = mabr.analysis.PermTest.tfce(two,par,minSz);
    assert(isequal(A1,A2(1,:)) && any(A1(30:40) ~= 0), ...
        'One-row TFCE (minClusterSize %d) differs from the same row in a two-row map by %g.', ...
        minSz,max(abs(A1-A2(1,:))));
end
fprintf('  PASS PermTest one-row maps: cluster mass and TFCE count every run, as one row of a larger map (%.1f s)\n', ...
    toc(tc));

%% ====================================================== C. Firth
sepD = double(x >= 40);
[b,covB,conv,ll] = mabr.analysis.Threshold.logisticFirth(x,sepD);
assert(all(isfinite(b)) && b(2) > 0 && conv && isfinite(ll) && all(isfinite(covB(:))), ...
    'Firth under complete separation: b = [%g %g], converged %d.',b,conv);
o = F(x,sepD,Type="glm",Penalty="firth");
assert(o.Type == "glm" && o.CIMethod == "profile" && o.Model.penalty == "firth", ...
    'Firth fit: Type %s, CIMethod %s.',o.Type,o.CIMethod);
assert(isfinite(o.Threshold) && o.Threshold > min(x)-step && o.Threshold < max(x)+step, ...
    'Defect 4: separated series threshold %g is not inside [L1-step, Ln+step].',o.Threshold);
assert(abs(o.Threshold - 35) < 1, 'Firth threshold of a 30|40 split is %g, expected ~35.',o.Threshold);
w4 = o.CI(2) - o.CI(1);
assert(~(w4 < step), 'Defect 4: the Firth CI [%g %g] is narrower than one level step.',o.CI);
assert(abs(o.Predict(o.Threshold) - 0.5) < 1e-9,'Firth threshold is not where the curve is 0.5.');
% the profile interval covers the generating threshold of a simulated series
rs = RandStream('threefry','Seed',1);
xs = repmat((0:5:100).',3,1);
ysim = double(rand(rs,size(xs)) < 1./(1+exp(-0.15*(xs-50))));
o = F(xs,ysim,Type="glm",Penalty="firth");
assert(o.CI(1) <= 50 && 50 <= o.CI(2), 'Profile CI [%g %g] misses the generating threshold 50.',o.CI);
% an end the data cannot place is open, not a number
o = F(x,double(x>=80),Type="glm",Penalty="firth");
assert(o.CIOpen(2) && isnan(o.CI(2)) && ~o.CIOpen(1) && isfinite(o.CI(1)), ...
    'A top-only detection should leave the upper profile bound open: [%g %g] open [%d %d].',o.CI,o.CIOpen);
[ci,op] = mabr.analysis.Threshold.firthProfileCI(x,double(x>=80));
assert(isequaln(ci,o.CI) && isequal(op,o.CIOpen),'firthProfileCI disagrees with fit.');
% the CIAlpha end points fit() accepts give a Firth fit, not the fallback
o = F(x,sepD,Type="glm",Penalty="firth",CIAlpha=0);
assert(o.Type == "glm" && o.CIMethod == "profile" && isequal(o.CIOpen,[true true]), ...
    'Firth with CIAlpha 0: %s, CI open [%d %d] (%s).',o.Type,o.CIOpen,o.Message);
o = F(x,sepD,Type="glm",Penalty="firth",CIAlpha=1);
assert(o.Type == "glm" && o.CIMethod == "profile",'Firth with CIAlpha 1: %s (%s).',o.Type,o.Message);
fprintf('  PASS Firth GLM: finite under separation, profile CI covers the truth, open bounds reported\n');

%% ====================================================== D. predictor
xx = linspace(-10,95,43).';
fits = {F(x,yb,Type="glm",Seed=1), F(x,yg,Type="sigmoid",Seed=1), ...
        F(x,yg,Type="isotonic"), F(x,yg,Type="minimum"), F(x,sepD,Type="glm",Penalty="firth"), ...
        mabr.analysis.Threshold.prestoFit(x,0.05+0.7./(1+exp(-(x-40)/5)),0.3), ...
        mabr.analysis.Threshold.prestoFit(x,0.02+0.00009*(x+1).^2,0.3)};
for k = 1:numel(fits)
    f0 = fits{k};
    g  = f0;
    g.Predict = [];                              % as a saved fit: no handle
    g  = mabr.analysis.Threshold.predictor(g);
    assert(isequaln(g.Predict(xx),f0.Predict(xx)), ...
        'predictor() rebuilt a different %s curve.',f0.Type);
end
assert(fits{6}.Type == "presto-sigmoid" && fits{7}.Type == "presto-power", ...
    'predictor test fits are not the two presto curves (%s, %s).',fits{6}.Type,fits{7}.Type);
% a v2 SeriesThreshold fit is rebuilt from its sampled curve
Ys = struct('XCorrUp',[0.02 0.05 0.1 0.2 0.45 0.7 0.8 0.85 NaN].');
os = ST.estimate(L,Ys,"xcorr",MinSweeps=0,MinPerPolarity=0);
g = rmfield(os.Fit,'Predict');
g = mabr.analysis.Threshold.predictor(g);
assert(max(abs(g.Predict(os.Fit.CurveX) - os.Fit.CurveY)) < 1e-12, 'v2 CurveX predictor does not reproduce CurveY.');
assert(g.Predict(1e6) == max(os.Fit.CurveY) && g.Predict(-1e6) == min(os.Fit.CurveY), ...
    'v2 CurveX predictor is not clamped to the curve''s range.');
u = mabr.analysis.Threshold.predictor(struct('Type',"mystery",'Model',struct()));
assert(all(isnan(u.Predict([1 2 3]))),'An unknown fit type should predict NaN.');
fprintf('  PASS predictor() rebuilds v1 glm/sigmoid/isotonic/minimum, Firth, presto and v2 CurveX fits\n');

%% ====================================================== E. prestoFit
o = mabr.analysis.Threshold.prestoFit(x,0.05+0.7./(1+exp(-(x-40)/5)),0.3,SD=0.05*ones(9,1));
thrTrue = 40 - 5*log(0.7/0.25 - 1);
assert(o.Type == "presto-sigmoid" && o.Status == "ok" && abs(o.Threshold - thrTrue) < 0.05, ...
    'presto sigmoid branch: %s %s %g (truth %g).',o.Type,o.Status,o.Threshold,thrTrue);
r2 = 0.02 + 0.00009*(x-min(x)+1).^2;
o = mabr.analysis.Threshold.prestoFit(x,r2,0.3);
assert(o.Type == "presto-power" && o.Status == "ok" && isempty(o.Flags), ...
    'presto power branch: %s %s flags "%s".',o.Type,o.Status,strjoin(o.Flags,'|'));
assert(abs(o.Predict(o.Threshold) - 0.3) < 1e-6, ...
    'presto power threshold is not where its curve reaches 0.3 (offset bug?).');
o10 = mabr.analysis.Threshold.prestoFit(x+10,r2,0.3);
assert(abs((o10.Threshold - o.Threshold) - 10) < 1e-9, ...
    'Levels from 0 and from 10 dB give thresholds %.12g and %.12g: not the 10 dB shift.',o.Threshold,o10.Threshold);
jit = 2*[0.06 -0.07 0.05 -0.06 0.08 -0.05 0.07 -0.08 0.04].';
o = mabr.analysis.Threshold.prestoFit(x,r2+jit,0.3);
assert(o.Type == "presto-power" && any(o.Flags == "power law (noisy)") && o.Model.AdjR2 <= 0.7, ...
    'Noisy power law not flagged: %s, adj R2 %g.',o.Type,o.Model.AdjR2);
o = mabr.analysis.Threshold.prestoFit(x,0.5+0.01*(1:9).',0.3);
assert(o.Status == "all-respond" && o.Threshold == 0,'presto all above 1.1 crit: %s.',o.Status);
o = mabr.analysis.Threshold.prestoFit(x,0.1+0.01*(1:9).',0.3);
assert(o.Status == "no-response" && isinf(o.Threshold),'presto all below: %s.',o.Status);
o = mabr.analysis.Threshold.prestoFit(x,[0.35 0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1].',0.3);
assert(o.Status == "no-response" && isinf(o.Threshold),'presto, <= 2 levels above: %s.',o.Status);
o = mabr.analysis.Threshold.prestoFit(x,[0.25 0.6 0.6 0.6 0.6 0.6 0.6 0.6 0.28].',0.3);
assert(o.Status == "all-respond" && o.Threshold == 0,'presto, <= 2 levels below: %s.',o.Status);
o = mabr.analysis.Threshold.prestoFit(x,[0.1 0.5 0.1 0.5 0.1 0.5 0.1 0.5 0.1].',0.3);
assert(o.Status == "failed" && isnan(o.Threshold) && any(o.Flags == "presto: no fit crossed the criterion"), ...
    'presto, no fit crossing: %s.',o.Status);
fprintf('  PASS prestoFit: sigmoid, power (+noisy), all-respond, no-response, <=2 rules, failed, 0/10 dB offset\n');

%% ====================================================== F. real-data fixture
% The probe's permutation p-values of SUBJ-ID-1254_261001T140845 (200
% permutations), rows 80..0 dB, columns 1 2 4 8 16 32 kHz.
P = [ .005 .005 .005 .005 .005 .144
      .005 .005 .005 .005 .005 .687
      .194 .015 .005 .005 .229 .861
      .090 .080 .010 .005 .085 .990
      .055 .184 .005 .005 .010 .990
      .308 1.00 .085 .498 .234 .602
      .995 .995 .085 .637 .965 .154
      .388 .995 .512 .060 .990 .383
      .383 .562 .050 .637 .478 .030];
lev = (80:-10:0).';
nFix = numel(lev);
fixY = @(j) struct('P',P(:,j),'NClean',512*ones(nFix,1),'NPos',256*ones(nFix,1),'NNeg',256*ones(nFix,1));
mid = [65 55 35 35 65]; low = [70 60 40 40 70];
for j = 1:6
    o  = ST.estimate(lev,fixY(j),ST.resolve("perm-descending"));
    ol = ST.estimate(lev,fixY(j),ST.resolve("perm-descending"),Convention="lowest_level");
    if j <= 5
        assert(o.Status == "ok" && o.Censored == "interval" && o.Threshold == mid(j) && ...
            o.ThrLo == low(j)-10 && o.ThrHi == low(j), ...
            'Fixture column %d: perm-descending %g (%s, %s), expected %g.',j,o.Threshold,o.Status,o.Censored,mid(j));
        assert(ol.Threshold == low(j),'Fixture column %d: lowest_level %g, expected %g.',j,ol.Threshold,low(j));
    else
        assert(o.Status == "no-response" && o.Censored == "right" && isinf(o.Threshold) && o.ThrLo == 80, ...
            '32 kHz should be right-censored at 80: %g (%s).',o.Threshold,o.Status);
    end
    assert(any(o.Flags == "isolated detection below threshold") == ismember(j,[5 6]), ...
        'Column %d: isolated-detection flag "%s".',j,strjoin(o.Flags,'|'));
end
gl = zeros(1,6);
for j = 1:6
    o = ST.estimate(lev,fixY(j),ST.resolve("perm-glm"));
    gl(j) = o.Threshold;
    if ismember(j,[1 2 4])                % the monotone series
        assert(isfinite(o.Threshold) && abs(o.Threshold - mid(j)) <= 10, ...
            'perm-glm %d: %g is not within a step of %g.',j,o.Threshold,mid(j));
        assert(o.CIMethod == "profile" && ~(o.CIUpper - o.CILower < 10), ...
            'perm-glm %d: CI [%g %g] narrower than 10 dB.',j,o.CILower,o.CIUpper);
        assert(contains(o.Message,"psychometric (advisory)"),'perm-glm message: "%s".',o.Message);
    end
    % What the default method has to say about this real session (the
    % integration smoke test asserts the same of the files themselves):
    % every tone up to 16 kHz a finite threshold inside the levels tested,
    % 32 kHz -- detected only at 0 dB -- no response up to 80 dB.
    if j <= 5
        assert(o.Status == "ok" && o.Censored == "none" && o.Threshold >= 0 && o.Threshold <= 80, ...
            'perm-glm %d: %g (%s, %s) is not a finite threshold inside [0 80] dB.',j,o.Threshold,o.Status,o.Censored);
    else
        assert(o.Status == "no-response" && o.Censored == "right" && isinf(o.Threshold) && o.ThrLo == 80, ...
            'perm-glm at 32 kHz: %g (%s, %s), expected right-censored at 80 dB.',o.Threshold,o.Status,o.Censored);
    end
end
fprintf('  PASS real-data fixture: perm-descending 65/55/35/35/65/>80, lowest_level 70/60/40/40/70, perm-glm %s\n', ...
    strjoin(compose('%.1f',gl),'/'));

%% ====================================================== G. canonical series
Dcases = {
    'monotone',            [0 0 0 0 1 1 1 1 1], "ok",          "interval", 30,  40,  35,  ""
    'isolated FP at 0',    [1 0 0 0 1 1 1 1 1], "ok",          "interval", 30,  40,  35,  "isolated detection below threshold"
    'failed top level',    [0 0 0 0 1 1 1 1 0], "ok",          "interval", 30,  40,  35,  "miss above threshold"
    'all detected',        [1 1 1 1 1 1 1 1 1], "all-respond", "left",     NaN, 0,   0,   ""
    'none detected',       [0 0 0 0 0 0 0 0 0], "no-response", "right",    80,  NaN, Inf, "no detected level"
    'top-level-only run',  [0 0 0 0 0 0 0 0 1], "ok",          "interval", 70,  80,  75,  "top-level-only run"
    'run below two misses',[0 0 1 1 0 0 1 1 1], "ok",          "interval", 50,  60,  55,  "isolated detection below threshold"
    'run below one miss',  [0 0 1 1 0 1 1 1 1], "ok",          "interval", 10,  20,  15,  "miss above threshold"
    'top two missed',      [0 0 1 1 1 1 1 0 0], "no-response", "right",    80,  NaN, Inf, "isolated detection below threshold"
    };
for k = 1:size(Dcases,1)
    o = ST.estimate(L,detY(Dcases{k,2}),"perm-descending",MinSweeps=0,MinPerPolarity=0);
    assert(o.Status == Dcases{k,3} && o.Censored == Dcases{k,4} && isequaln(o.ThrLo,Dcases{k,5}) && ...
        isequaln(o.ThrHi,Dcases{k,6}) && isequal(o.Threshold,Dcases{k,7}), ...
        '%s: %s/%s [%g %g] %g, expected %s/%s [%g %g] %g.',Dcases{k,1},o.Status,o.Censored, ...
        o.ThrLo,o.ThrHi,o.Threshold,Dcases{k,3},Dcases{k,4},Dcases{k,5},Dcases{k,6},Dcases{k,7});
    if Dcases{k,8} ~= ""
        assert(any(o.Flags == Dcases{k,8}),'%s: flag "%s" missing from "%s".',Dcases{k,1},Dcases{k,8},strjoin(o.Flags,'|'));
    end
    assert(o.NumUsable == 9 && o.NumSig == sum(Dcases{k,2}) && isequal(o.Detected.',logical(Dcases{k,2})), ...
        '%s: counts/detections wrong.',Dcases{k,1});
end
% 10 section 7.2: the output and its Fit carry the contract's fields (Session's
% Thresholds row and the saved Fit cell are built from them by name)
outFields = ["Threshold","ThresholdRaw","Status","Censored","ThrLo","ThrHi","CILower","CIUpper", ...
    "CIMethod","Type","FitTarget","Criterion","CriterionUnit","Convention","NumLevels","NumUsable", ...
    "NumSig","LevelStep","MinLevel","MaxLevel","Converged","Message","Flags","Detected","DetectedAuto", ...
    "Usable","Fit"];
fitStructFields = ["Type","Criterion","CriterionMode","X","Y","D","AllX","AllY","Usable","Model", ...
    "Scale","CurveX","CurveY","Threshold","CI","Message","FitTarget","Converged","Predict"];
for o = {ST.estimate(L,detY([0 0 0 0 1 1 1 1 1]),"perm-glm",MinSweeps=0,MinPerPolarity=0), ...
         ST.estimate(80,struct('P',0.5),"perm-descending")}
    miss = [outFields(~isfield(o{1},outFields)) fitStructFields(~isfield(o{1}.Fit,fitStructFields))];
    assert(isempty(miss),'SeriesThreshold.estimate output lacks %s.',strjoin(miss,', '));
    assert(isstring(o{1}.Flags) && size(o{1}.Flags,1) <= 1 && iscolumn(o{1}.Detected) && ...
        islogical(o{1}.Detected) && islogical(o{1}.Usable),'estimate output shapes are wrong.');
end
% the same five through the Firth GLM: censoring rules decide the ends
o = ST.estimate(L,detY([1 1 1 1 1 1 1 1 1]),"perm-glm",MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "all-respond" && o.Censored == "left" && o.Threshold == 0,'GLM all detected: %s.',o.Status);
o = ST.estimate(L,detY([0 0 0 0 0 0 0 0 0]),"perm-glm",MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "no-response" && o.Censored == "right" && o.ThrLo == 80,'GLM none detected: %s.',o.Status);
% detected at the loudest level only: a threshold inside the range, whose
% upper profile bound the data cannot place -- reported open and flagged
o = ST.estimate(L,detY([0 0 0 0 0 0 0 0 1]),"perm-glm",MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "ok" && o.Censored == "none" && isfinite(o.Threshold) && o.CIMethod == "profile" && ...
    isfinite(o.CILower) && isnan(o.CIUpper) && any(o.Flags == "profile CI open"), ...
    'GLM, top level only: %g [%g %g] (%s) {%s}.',o.Threshold,o.CILower,o.CIUpper,o.Status,strjoin(o.Flags,'|'));
% The descending rule walks DOWN from the loudest level and stops at K
% consecutive misses: a run below them is disconnected from the response
% and does not set the threshold. The next-louder correlation of the real
% 32 kHz series (SUBJ-ID-1254_261001T140845, 70..0 dB, no response by every
% other method) crossed 0.35 at 20-40 dB, and scanning up from the softest
% level gave 18 dB; descending, it is the 60-70 dB crossing, and the low run
% is flagged.
rx = [NaN 0.785 -0.017 -0.147 0.626 0.536 0.520 -0.369 0.211].';    % 80..0 dB
o = ST.estimate((80:-10:0).',struct('XCorrUp',rx),"xcorr",MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "ok" && o.Threshold > 60 && o.Threshold < 70 && ...
    any(o.Flags == "isolated detection below threshold") && any(o.Flags == "top-level-only run"), ...
    'xcorr on the 32 kHz series: %g (%s) {%s}, expected the 60-70 dB crossing.',o.Threshold,o.Status, ...
    strjoin(o.Flags,'|'));
xc = o.Threshold;
fprintf(['  PASS canonical series (monotone, isolated FP, failed top, all, none, top-level-only run, ' ...
    'runs below one and two misses, top two missed; GLM ends); descending from the top: xcorr 32 kHz ' ...
    '%.1f dB, not 18\n'],xc);

%% ====================================================== H. usable levels
Y = struct('P',[0.5 0.5 0.5 0.01].','NClean',[10 10 10 200].');
o = ST.estimate([0 10 20 30].',Y,"perm-descending");
assert(o.Status == "all-respond" && o.Censored == "left" && o.Threshold == 30 && o.ThrHi == 30 && ...
    o.NumUsable == 1 && any(o.Flags == "only one usable level") && any(o.Flags == "level ignored at 0 dB: 10 clean sweeps, fewer than the minimum of 100"), ...
    'One usable, detected level: %s %g {%s}.',o.Status,o.Threshold,strjoin(o.Flags,'|'));
Y.P(4) = 0.5;
o = ST.estimate([0 10 20 30].',Y,"perm-descending");
assert(o.Status == "insufficient" && isnan(o.Threshold) && o.Censored == "", ...
    'One usable, undetected level: %s.',o.Status);
o = ST.estimate(80,struct('P',0.5),"perm-descending");
assert(o.Status == "insufficient" && o.Status ~= "no-response",'Defect 18: one level gave "%s".',o.Status);
o = ST.estimate(L,struct('P',0.01*ones(9,1),'NClean',zeros(9,1)),"perm-glm");
assert(o.Status == "insufficient" && o.NumUsable == 0 && any(o.Flags == "low sweeps"), ...
    'No usable level: %s.',o.Status);
% polarity rule
o = ST.estimate(L,struct('P',[0.5 0.5 0.5 0.5 0.01 0.01 0.01 0.01 0.01].','NPos',[50 50 50 50 50 50 50 50 10].', ...
    'NNeg',50*ones(9,1)),"perm-descending",MinSweeps=0);
assert(~o.Usable(9) && any(o.Flags == "level ignored at 80 dB: 10 clean sweeps of one polarity, fewer than the minimum of 40"), ...
    'A level with 10 sweeps of one polarity should be ignored.');
o2 = ST.estimate(L,struct('P',[0.5 0.5 0.5 0.5 0.01 0.01 0.01 0.01 0.01].','NPos',[50 50 50 50 50 50 50 50 10].', ...
    'NNeg',50*ones(9,1)),"perm-descending",MinSweeps=0,Alternating=false);
assert(o2.Usable(9),'Alternating=false must not apply the per-polarity rule.');
% defect 3: an undefined level is dropped and flagged, never a confident miss
Pd = 0.5 - 0.49*[0 0 0 0 1 1 1 1 1].';
Pd(3) = NaN;
o = ST.estimate(L,struct('P',Pd),"perm-glm",MinSweeps=0,MinPerPolarity=0);
assert(o.NumUsable == 8 && ~o.Usable(3) && ~o.Detected(3) && any(o.Flags == "level ignored at 20 dB: the metric is undefined") && ...
    any(o.Flags == "metric undefined at some level"),'Defect 3: p = NaN level not dropped and flagged.');
% Borderline detections: a permutation p within twice its Monte-Carlo error
% of Alpha (1000 permutations: 0.036-0.064) is flagged with its level and p,
% and changes nothing else; without a permutation count, or with enough
% permutations, nothing is flagged.
Yb = detY([0 0 0 0 1 1 1 1 1]);
Yb.P(4) = 0.06;  Yb.P(5) = 0.043;                       % 30 and 40 dB, either side of 0.05
Yb.IsSig = double(Yb.P < 0.05);
o = ST.estimate(L,Yb,"perm-descending",MinSweeps=0,MinPerPolarity=0,NumPermutations=1000);
bf = "borderline detection at 30, 40 dB (p 0.060, 0.043 within Monte-Carlo error of 0.05)";
assert(any(o.Flags == bf) && o.Threshold == 35 && o.Censored == "interval", ...
    'Borderline flag: {%s}, threshold %g.',strjoin(o.Flags,'|'),o.Threshold);
o0 = ST.estimate(L,Yb,"perm-descending",MinSweeps=0,MinPerPolarity=0);
o1 = ST.estimate(L,Yb,"perm-descending",MinSweeps=0,MinPerPolarity=0,NumPermutations=1e5);
assert(~any(startsWith([o0.Flags o1.Flags],"borderline")) && o0.Threshold == o.Threshold, ...
    'Borderline flagged without a permutation count or with 1e5 permutations: {%s}.', ...
    strjoin([o0.Flags o1.Flags],'|'));
og = ST.estimate(L,Yb,"perm-glm",MinSweeps=0,MinPerPolarity=0,NumPermutations=1000);
assert(any(og.Flags == bf),'perm-glm does not flag the borderline detections: {%s}.',strjoin(og.Flags,'|'));
fprintf(['  PASS usable levels: one level all-respond/insufficient, zero levels, polarity rule, defect 3; ' ...
    'borderline detections flagged (1000 permutations), not without a count or with 1e5\n']);

%% ====================================================== I. overrides, gate, range censoring
Y = detY([0 0 0 0 1 1 1 1 1]);
Y.Override = nan(9,1);
Y.Override(4) = 1;                                  % 30 dB: a person saw a response
o = ST.estimate(L,Y,"perm-descending",MinSweeps=0,MinPerPolarity=0);
assert(o.Threshold == 25 && o.ThrLo == 20 && o.ThrHi == 30 && o.Detected(4) && ~o.DetectedAuto(4) && ...
    any(o.Flags == "detection overridden at 30 dB"),'Override 1 at 30 dB: %g.',o.Threshold);
Y.Override(4) = NaN; Y.Override(5) = 0;             % 40 dB: not a response after all
o = ST.estimate(L,Y,"perm-descending",MinSweeps=0,MinPerPolarity=0);
assert(o.Threshold == 45 && ~o.Detected(5) && o.DetectedAuto(5),'Override 0 at 40 dB: %g.',o.Threshold);
% an override makes an otherwise unusable level count
Y = detY([0 0 0 0 1 1 1 1 1]); Y.NClean = [200 200 200 5 200 200 200 200 200].'; Y.Override = [NaN NaN NaN 1 NaN NaN NaN NaN NaN].';
o = ST.estimate(L,Y,"perm-descending",MinPerPolarity=0);
assert(o.Usable(4) && o.Threshold == 25,'An overridden level with too few sweeps should count: %g.',o.Threshold);
% the legacy gate: no K-run of permutation detections, no fraction fit at all
mIso = ST.resolve("custom",struct('ThresholdMetric',"detection",'ThresholdModel',"isotonic",'CriterionMode',"fraction",'Criterion',0.5));
Yg = struct('P',0.5-0.49*[0 1 0 1 0 1 0 0 0].','IsSig',[0 1 0 1 0 1 0 0 0].','Strength',(1:9).');
o = ST.estimate(L,Yg,mIso,MinSweeps=0,MinPerPolarity=0,MinConsecutive=2);
assert(o.Status == "no-response" && o.Censored == "right" && contains(o.Message,"not attempted") && ...
    ~any(o.Flags == "not converged") && ~any(o.Flags == "fallback model used"), ...
    'Legacy gate: %s (%s) {%s}.',o.Status,o.Message,strjoin(o.Flags,'|'));
o = ST.estimate(L,Yg,mIso,MinSweeps=0,MinPerPolarity=0,MinConsecutive=1,LegacyFitTarget="strength");
assert(o.Type == "isotonic" && o.Status ~= "no-response",'With K = 1 the gate passes: %s.',o.Status);
% range censoring keeps the model's own answer in ThresholdRaw
m99 = ST.resolve("custom",struct('ThresholdMetric',"detection",'ThresholdModel',"glm",'CriterionMode',"probability",'Criterion',0.99));
o = ST.estimate(L,detY([0 0 0 1 0 1 0 1 1]),m99,MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "no-response" && o.Censored == "right" && isinf(o.Threshold) && isfinite(o.ThresholdRaw) && ...
    o.ThresholdRaw > 90 && any(o.Flags == "estimate above range"), ...
    'Above-range estimate: %g (raw %g) %s.',o.Threshold,o.ThresholdRaw,o.Status);
m01 = ST.resolve("custom",struct('ThresholdMetric',"detection",'ThresholdModel',"glm",'CriterionMode',"probability",'Criterion',0.01));
o = ST.estimate(L,detY([0 0 1 0 1 1 1 1 1]),m01,MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "all-respond" && o.Censored == "left" && o.Threshold == 0 && o.ThresholdRaw < -10 && ...
    any(o.Flags == "estimate below range"), ...
    'Below-range estimate: %g (raw %g) %s.',o.Threshold,o.ThresholdRaw,o.Status);
fprintf('  PASS overrides change D (and count), the legacy gate, range censoring keeps ThresholdRaw\n');

%% ====================================================== J. graded metrics, bootstrap CI
Yx = struct('XCorrUp',[0.02 0.05 0.1 0.2 0.45 0.7 0.8 0.85 NaN].');
o = ST.estimate(L,Yx,"xcorr",MinSweeps=0,MinPerPolarity=0);
assert(abs(o.Threshold - 36) < 1e-12 && o.Censored == "none" && o.FitTarget == "graded" && ...
    ~any(startsWith(o.Flags,"level ignored")) && ~any(o.Flags == "metric undefined at some level"), ...
    'xcorr crossing %g {%s}; the top level''s NaN is the method, not a defect.',o.Threshold,strjoin(o.Flags,'|'));
o = ST.estimate(L,Yx,"xcorr",MinSweeps=0,MinPerPolarity=0,Interpolate=false);
assert(o.Censored == "interval" && o.Threshold == 35,'xcorr without interpolation: %g %s.',o.Threshold,o.Censored);
o = ST.estimate(L,Yx,"xcorr",MinSweeps=0,MinPerPolarity=0,Interpolate=false,Convention="crossing");
assert(o.Censored == "interval" && abs(o.Threshold - 36) < 1e-12,'crossing convention: %g.',o.Threshold);
rs = RandStream('threefry','Seed',3);
YB = Yx.XCorrUp + 0.05*randn(rs,9,200);
YB(9,:) = NaN;
o = ST.estimate(L,Yx,"xcorr",MinSweeps=0,MinPerPolarity=0,YBoot=YB);
assert(o.CIMethod == "bootstrap" && o.CILower < o.Threshold && o.Threshold < o.CIUpper, ...
    'Graded bootstrap CI [%g %g] (%s) does not bracket %g.',o.CILower,o.CIUpper,o.CIMethod,o.Threshold);
o2 = ST.estimate(L,Yx,"xcorr",MinSweeps=0,MinPerPolarity=0,YBoot=YB);
assert(isequal([o.CILower o.CIUpper],[o2.CILower o2.CIUpper]),'The bootstrap CI is not deterministic.');
% xcorr-dtw: the same rule on DTWUp, at its own criterion (0.40: noise
% passes it as often as it passes 0.35 under xcorr's rigid lag), and blind to
% XCorrUp -- each method reads its own column.
Yd = struct('DTWUp',Yx.XCorrUp,'XCorrUp',Yx.XCorrUp - 0.3);
o = ST.estimate(L,Yd,"xcorr-dtw",MinSweeps=0,MinPerPolarity=0);
assert(abs(o.Threshold - 38) < 1e-12 && o.Censored == "none" && o.Criterion == 0.40 && ...
    o.CriterionUnit == "r" && o.Fit.Metric == "dtw" && o.Fit.Method == "xcorr-dtw" && ...
    ~any(startsWith(o.Flags,"level ignored")) && ~any(o.Flags == "metric undefined at some level"), ...
    'xcorr-dtw crossing %g (criterion %g) {%s}; expected 38 at 0.40.',o.Threshold,o.Criterion,strjoin(o.Flags,'|'));
o = ST.estimate(L,struct('XCorrUp',Yx.XCorrUp),"xcorr-dtw",MinSweeps=0,MinPerPolarity=0);
assert(o.Status == "insufficient" && o.NumUsable == 0,'xcorr-dtw read XCorrUp: %s, %d usable.',o.Status,o.NumUsable);
YBd = Yd.DTWUp + 0.05*randn(RandStream('threefry','Seed',4),9,200);
YBd(9,:) = NaN;
o = ST.estimate(L,Yd,"xcorr-dtw",MinSweeps=0,MinPerPolarity=0,YBoot=YBd);
assert(o.CIMethod == "bootstrap" && o.CILower < o.Threshold && o.Threshold < o.CIUpper, ...
    'xcorr-dtw bootstrap CI [%g %g] (%s) does not bracket %g.',o.CILower,o.CIUpper,o.CIMethod,o.Threshold);
% presto through estimate, with its flags and censoring
Yp = struct('SplitR',0.05+0.7./(1+exp(-(L-40)/5)),'SplitRSD',0.05*ones(9,1));
o = ST.estimate(L,Yp,"presto",MinSweeps=0,MinPerPolarity=0);
assert(o.Type == "presto-sigmoid" && o.Status == "ok" && abs(o.Threshold - thrTrue) < 0.05, ...
    'presto via estimate: %s %g.',o.Type,o.Threshold);
% An override the metric contradicts leaves no crossing between the bracketing
% levels: the interval stands with its Convention point. (A line extended past
% its ends put the threshold ON the overridden 40 dB -- the open end of
% (40,50] -- or on 30 dB for the second case.)
Yo = Yx; Yo.Override = nan(9,1); Yo.Override(5) = 0;      % 40 dB, r 0.45: "no response"
for interp = [true false]
    o = ST.estimate(L,Yo,"xcorr",MinSweeps=0,MinPerPolarity=0,Interpolate=interp,Convention="crossing");
    assert(o.Censored == "interval" && o.Threshold == 45 && o.ThrLo == 40 && o.ThrHi == 50, ...
        'Override 0 against r >= criterion (Interpolate %d): %g %s [%g %g].',interp,o.Threshold,o.Censored,o.ThrLo,o.ThrHi);
end
Yo.Override(5) = NaN; Yo.Override(4) = 1;                  % 30 dB, r 0.2: "response"
o = ST.estimate(L,Yo,"xcorr",MinSweeps=0,MinPerPolarity=0);
assert(o.Censored == "interval" && o.Threshold == 25 && o.ThrLo == 20 && o.ThrHi == 30, ...
    'Override 1 against r < criterion: %g %s [%g %g].',o.Threshold,o.Censored,o.ThrLo,o.ThrHi);
% presto with fewer than two finite r (the other usable levels are overrides)
Yi = struct('SplitR',[NaN NaN NaN NaN 0.5 NaN NaN NaN NaN].','Override',[NaN NaN NaN 0 NaN 1 NaN NaN NaN].');
o = ST.estimate(L,Yi,"presto",MinSweeps=0,MinPerPolarity=0);
assert(o.NumUsable == 3 && o.Status == "insufficient" && isnan(o.Threshold) && o.Censored == "", ...
    'presto on one finite r: %s %g (%d usable).',o.Status,o.Threshold,o.NumUsable);
fprintf(['  PASS graded metrics: interpolated crossing, conventions, overrides, deterministic bootstrap CI, ' ...
    'presto; xcorr-dtw on DTWUp at 0.40\n']);

%% ====================================================== K. direction
Ym = detY([0 0 0 0 1 1 1 1 1]);
oa = ST.estimate(L,Ym,"perm-descending",MinSweeps=0,MinPerPolarity=0);
od = ST.estimate(80-L,Ym,"perm-descending",MinSweeps=0,MinPerPolarity=0,LevelDirection="descending");
assert(od.Threshold == 80-oa.Threshold && od.ThrLo == 80-oa.ThrHi && od.ThrHi == 80-oa.ThrLo && ...
    od.Censored == "interval" && isequal(od.Detected,oa.Detected), ...
    'An attenuation axis does not mirror: %g [%g %g].',od.Threshold,od.ThrLo,od.ThrHi);
oa = ST.estimate(L,Ym,"perm-glm",MinSweeps=0,MinPerPolarity=0);
od = ST.estimate(80-L,Ym,"perm-glm",MinSweeps=0,MinPerPolarity=0,LevelDirection="descending");
assert(abs(od.Threshold - (80-oa.Threshold)) < 1e-6 && abs(od.CILower - (80-oa.CIUpper)) < 1e-6 && ...
    abs(od.CIUpper - (80-oa.CILower)) < 1e-6,'The GLM does not mirror on an attenuation axis.');
Yall = detY(ones(1,9));
oa = ST.estimate(L,Yall,"perm-descending",MinSweeps=0,MinPerPolarity=0);
od = ST.estimate(80-L,Yall,"perm-descending",MinSweeps=0,MinPerPolarity=0,LevelDirection="descending");
assert(oa.Censored == "left" && od.Censored == "right" && od.Status == "all-respond" && ...
    od.Threshold == 80 && od.ThrLo == 80 && isnan(od.ThrHi), ...
    'All respond on an attenuation axis: %s %g [%g %g].',od.Censored,od.Threshold,od.ThrLo,od.ThrHi);
fprintf('  PASS LevelDirection "descending" mirrors an ascending series (rule, GLM, censoring)\n');

% Random series through every method, both directions, with overrides and
% missing values: whatever the answer, its numbers have the shape its
% censoring claims -- an interval's point inside (ThrLo, ThrHi], a left bound
% at ThrHi, a right bound past ThrLo -- and only usable levels are detected.
rs = RandStream('threefry','Seed',21);
cust = {struct('ThresholdMetric',"detection",'ThresholdModel',"isotonic",'CriterionMode',"fraction",'Criterion',0.5), ...
        struct('ThresholdMetric',"snr",'ThresholdModel',"descending",'CriterionMode',"absolute",'Criterion',NaN), ...
        struct('ThresholdMetric',"xcorr",'ThresholdModel',"presto",'CriterionMode',"absolute",'Criterion',NaN), ...
        struct('ThresholdMetric',"dtw",'ThresholdModel',"presto",'CriterionMode',"absolute",'Criterion',NaN)};
methodsUsed = ST.resolve(ST.Ids(1));
for id = ST.Ids(2:end-1), methodsUsed(end+1) = ST.resolve(id); end %#ok<AGROW>
for k = 1:numel(cust), methodsUsed(end+1) = ST.resolve("custom",cust{k}); end %#ok<AGROW>
nShape = 0;
for it = 1:80
    n  = randi(rs,[2 9]);
    Lr = (0:10:10*(n-1)).';
    pr = 1./(1+exp(-(Lr - 10*randi(rs,[0 n]))/6));
    Yr = struct('P',min(max(1 - pr + 0.15*randn(rs,n,1),0.001),1),'Strength',3000*pr, ...
        'PowerP',min(max(1 - pr + 0.15*randn(rs,n,1),0.001),1),'FspP',min(max(1 - pr + 0.15*randn(rs,n,1),0.001),1), ...
        'SplitR',0.02 + 0.8*pr + 0.05*randn(rs,n,1),'SplitRSD',0.05*ones(n,1), ...
        'XCorrUp',[0.02 + 0.8*pr(1:end-1) + 0.05*randn(rs,n-1,1); NaN],'SNR',-3 + 15*pr + randn(rs,n,1), ...
        'Override',nan(n,1));
    Yr.IsSig = double(Yr.P < 0.05);
    Yr.DTWUp = min(Yr.XCorrUp + 0.05,0.99);     % (no draw: the stream stays as it was)
    if rand(rs) < 0.3, Yr.Override(randi(rs,n)) = double(rand(rs) < 0.5); end
    if rand(rs) < 0.2, Yr.P(randi(rs,n)) = NaN; end
    m    = methodsUsed(randi(rs,numel(methodsUsed)));
    conv = ["midpoint","lowest_level","crossing"];
    ar   = {'MinSweeps',0,'MinPerPolarity',0,'Interpolate',rand(rs) < 0.7,'Convention',conv(randi(rs,3))};
    oa = ST.estimate(Lr,Yr,m,ar{:});
    od = ST.estimate(200-Lr,Yr,m,ar{:},LevelDirection="descending");
    why = [shapeProblem(oa,1) shapeProblem(od,-1)];
    assert(isempty(why),'Random series %d (%s): %s.',it,m.Id + "/" + m.Model,strjoin(why,'; '));
    nShape = nShape + 2;
end
fprintf('  PASS %d random answers of every method keep the shape their censoring claims\n',nShape);

%% ====================================================== L. curated value
o = ST.estimate(L,detY([0 0 0 0 1 1 1 1 1]),"perm-descending",MinSweeps=0,MinPerPolarity=0);
row = struct('Threshold',o.Threshold,'Censored',o.Censored,'ThrLo',o.ThrLo,'ThrHi',o.ThrHi, ...
    'MinLevel',o.MinLevel,'MaxLevel',o.MaxLevel,'LevelStep',o.LevelStep,'Fit',{{o.Fit}}, ...
    'Decision',"",'ManualKind',"",'ManualValue',NaN);
chk = @(F,v,c,lo,hi,what) assert(isequaln([F.Final F.FinalLo F.FinalHi],[v lo hi]) && F.FinalCensored == c, ...
    '%s: %g %s [%g %g], expected %g %s [%g %g].',what,F.Final,F.FinalCensored,F.FinalLo,F.FinalHi,v,c,lo,hi);
chk(ST.finalValue(row),35,"interval",30,40,'unreviewed');
row.Decision = "accepted";   chk(ST.finalValue(row),35,"interval",30,40,'accepted');
row.Decision = "manual"; row.ManualKind = "level"; row.ManualValue = 50;
chk(ST.finalValue(row),45,"interval",40,50,'manual level 50');
chk(ST.finalValue(row,"lowest_level"),50,"interval",40,50,'manual level 50, lowest_level');
chk(ST.finalValue(row,"crossing"),45,"interval",40,50,'manual level 50, crossing');
row.ManualValue = 0;         chk(ST.finalValue(row),0,"left",NaN,0,'manual lowest level');
row.ManualKind = "value"; row.ManualValue = 37.5;
chk(ST.finalValue(row),37.5,"none",37.5,37.5,'manual value');
row.Decision = "noresponse"; chk(ST.finalValue(row),Inf,"right",80,NaN,'no response');
row.Decision = "allrespond"; chk(ST.finalValue(row),0,"left",NaN,0,'all respond');
row.Decision = "excluded";   chk(ST.finalValue(row),NaN,"",NaN,NaN,'excluded');
row2 = rmfield(row,'Fit'); row2.Decision = "manual"; row2.ManualKind = "level"; row2.ManualValue = 60;
chk(ST.finalValue(row2),55,"interval",50,60,'manual level without a Fit');
% Through a table, the shape Session keeps: Fit is a cell column, [] in a row
% with no saved fit. This series lost its 40 dB level (p undefined), so only
% its saved Fit knows that 30 dB is the next usable level under 50: the row
% with the Fit says (30,50], the row without falls back on the MinLevel/
% LevelStep/MaxLevel grid and says (40,50].
Yg = detY([0 0 0 0 1 1 1 1 1]);
Yg.P(5) = NaN;
og = ST.estimate(L,Yg,"perm-descending",MinSweeps=0,MinPerPolarity=0);
assert(og.NumUsable == 8 && isequal(og.Fit.X.',[0 10 20 30 50 60 70 80]) && og.LevelStep == 10, ...
    'Gap series: usable levels [%s], step %g.',num2str(og.Fit.X.'),og.LevelStep);
rg = struct('Threshold',og.Threshold,'Censored',og.Censored,'ThrLo',og.ThrLo,'ThrHi',og.ThrHi, ...
    'MinLevel',og.MinLevel,'MaxLevel',og.MaxLevel,'LevelStep',og.LevelStep,'Fit',{{og.Fit}}, ...
    'Decision',"manual",'ManualKind',"level",'ManualValue',50);
rn = rg;
rn.Fit = {[]};
Tb = struct2table([rg; rn; orderfields(row,rg)]);
assert(iscell(Tb.Fit) && height(Tb) == 3,'The test table should carry Fit as a cell column.');
Fs = ST.finalValue(Tb);
assert(numel(Fs) == 3,'finalValue of a table should give one value per row (%d).',numel(Fs));
chk(Fs(1),40,"interval",30,50,'table row with a Fit (manual level 50 over a gap)');
chk(Fs(2),45,"interval",40,50,'table row without a Fit (manual level 50, grid)');
chk(Fs(3),NaN,"",NaN,NaN,'table row (excluded)');
Fa = ST.finalValue(table2struct(Tb));
assert(isequaln(Fa,Fs),'finalValue of a struct array should equal finalValue of the table.');
% formatValue
assert(ST.formatValue(34.9,"none") == "34.9",'formatValue none.');
assert(ST.formatValue(35,"interval",30,40) == "35 (30" + NDASH + "40]",'formatValue interval.');
assert(ST.formatValue(Inf,"right",80,NaN) == ">80",'formatValue right.');
assert(ST.formatValue(0,"left",NaN,0) == string(LE) + "0",'formatValue left.');
assert(ST.formatValue(NaN,"") == "n/a" && ST.formatValue(40,"") == "n/a",'formatValue excluded.');
assert(ST.formatValue(64.31,"none") == "64.3" && ST.formatValue(40,"none") == "40",'formatValue digits.');
assert(isequal(ST.formatValue([35 Inf],["interval" "right"],[30 80],[40 NaN]), ...
    ["35 (30" + NDASH + "40]" ">80"]),'formatValue on arrays.');
% belowThreshold
assert(isequal(ST.belowThreshold([20 30 40],35,"interval",30),[true true false]),'belowThreshold interval.');
assert(isequal(ST.belowThreshold([20 30 40],34.9,"none",34.9),[true true false]),'belowThreshold none.');
assert(all(ST.belowThreshold([0 80],Inf,"right",80)),'belowThreshold right.');
assert(~any(ST.belowThreshold([0 80],0,"left",NaN)) && ~any(ST.belowThreshold([0 80],NaN,"",NaN)), ...
    'belowThreshold left/excluded.');
assert(isequal(ST.belowThreshold([40 50 60],45,"interval",40,Direction="descending",FinalHi=50),[false true true]), ...
    'belowThreshold on an attenuation axis.');
fprintf('  PASS finalValue for every decision, formatValue texts, belowThreshold\n');

%% ====================================================== M. methods, resolve, definitions
M = ST.methods();
ids = ["perm-glm","perm-descending","power-descending","fsp-descending","presto","xcorr","xcorr-dtw","custom"];
labels = ["Permutation test " + ARROW + " psychometric fit (GLM, p = 0.5)"
          "Permutation test " + ARROW + " lowest of 2 consecutive detected levels"
          "Response power vs " + PM + " reference (sign-flip test) " + ARROW + " lowest of 2 consecutive"
          "Fsp (multi-point F, estimated df) " + ARROW + " lowest of 2 consecutive"
          "Split-half correlation r " + GE + " 0.30 (ABRpresto-like fit)"
          "Correlation with next-louder level " + GE + " 0.35 (Suthakar & Liberman 2019)"
          "Correlation with next-louder level after time warping " + GE + " 0.40 (DTW)"
          "Custom" + ELL].';
assert(numel(M) == 8 && isequal([M.Id],ids) && isequal(ST.Ids,ids),'methods() Ids or order are wrong.');
assert(isequal([M.Label],labels),'methods() labels differ from the contract.');
assert(isequal([M.Metric],["detection","detection","power","fsp","splithalf","xcorr","dtw","detection"]) && ...
    isequal([M.Model],["glm","descending","descending","descending","presto","descending","descending","glm"]) && ...
    isequal([M.CriterionMode],["probability","p","p","p","absolute","absolute","absolute","probability"]) && ...
    isequal([M.Criterion],[0.5 0.05 0.05 0.05 0.30 0.35 0.40 0.5]) && ...
    isequal([M.CriterionUnit],["probability","p","p","p","r","r","r","probability"]) && ...
    isequal([M.NeedsMeasures],[false false true true true true true false]),'methods() table columns are wrong.');
m = ST.resolve("perm-descending",struct('Alpha',0.01,'MinConsecutive',3));
assert(m.Criterion == 0.01 && contains(m.Label,"lowest of 3 consecutive"),'resolve did not apply Alpha/K: %s.',m.Label);
% A named p-method detects at the Alpha estimate is given (10 section 7.2 step
% 4), whatever it was resolved under; a custom "p" method keeps its criterion.
Ya = struct('P',[0.5 0.5 0.5 0.03 0.03 0.005 0.005 0.005 0.005].');
o = ST.estimate(L,Ya,ST.resolve("perm-descending"),Alpha=0.01,MinSweeps=0,MinPerPolarity=0);
assert(o.Threshold == 45 && o.Criterion == 0.01,'perm-descending resolved at 0.05, run at 0.01: %g (criterion %g).', ...
    o.Threshold,o.Criterion);
o = ST.estimate(L,Ya,ST.resolve("perm-descending",struct('Alpha',0.01)),MinSweeps=0,MinPerPolarity=0);
assert(o.Threshold == 25 && o.Criterion == 0.05,'perm-descending resolved at 0.01, run at 0.05: %g.',o.Threshold);
mp = ST.resolve("custom",struct('ThresholdMetric',"detection",'ThresholdModel',"descending", ...
    'CriterionMode',"p",'Criterion',0.04));
o = ST.estimate(L,Ya,mp,Alpha=0.01,MinSweeps=0,MinPerPolarity=0);
assert(o.Threshold == 25 && o.Criterion == 0.04,'custom p-method at 0.04: %g (criterion %g).',o.Threshold,o.Criterion);
bad = { {"nope"}, ...
        {"custom",struct('ThresholdMetric',"splithalf",'ThresholdModel',"glm",'CriterionMode',"probability")}, ...
        {"custom",struct('ThresholdMetric',"detection",'ThresholdModel',"presto",'CriterionMode',"absolute")}, ...
        {"custom",struct('ThresholdMetric',"detection",'ThresholdModel',"descending",'CriterionMode',"absolute")}, ...
        {"custom",struct('ThresholdMetric',"detection",'ThresholdModel',"glm",'CriterionMode',"probability",'Criterion',1.5)}, ...
        {"custom",struct('ThresholdMetric',"strength",'ThresholdModel',"descending",'CriterionMode',"absolute")} };
for k = 1:numel(bad)
    expectError(@() ST.resolve(bad{k}{:}),'mabr:analysis:SeriesThreshold:badMethod', ...
        sprintf('resolve refusal %d',k));
end
mc = ST.resolve("custom",struct('ThresholdMetric',"snr",'ThresholdModel',"descending",'CriterionMode',"absolute"));
assert(mc.Criterion == 3 && mc.CriterionUnit == "dB",'custom SNR default criterion %g %s.',mc.Criterion,mc.CriterionUnit);
mc = ST.resolve("custom",struct('ThresholdMetric',"dtw",'ThresholdModel',"presto",'CriterionMode',"absolute"));
assert(mc.Criterion == 0.40 && mc.CriterionUnit == "r" && mc.NeedsMeasures, ...
    'custom dtw default criterion %g %s.',mc.Criterion,mc.CriterionUnit);
expectError(@() ST.resolve("custom",struct('ThresholdMetric',"dtw",'ThresholdModel',"glm", ...
    'CriterionMode',"probability")),'mabr:analysis:SeriesThreshold:badMethod','resolve refusal: glm on dtw');
d1 = ST.definition("perm-descending");
assert(d1 == "Threshold = the midpoint between the highest level without and the lowest level with " + ...
    "2 consecutive detected responses, descending from the loudest level to the first 2 consecutive " + ...
    "misses (permutation test TFCE, " + ALPHA + " 0.05, 1000 permutations).", ...
    'perm-descending definition: "%s".',d1);
d2 = ST.definition("perm-glm");
assert(d2 == "Threshold = level where the probability of a detected response (TFCE permutation test, " + ...
    ALPHA + " 0.05, 1000 permutations) reaches 0.50 (Firth logistic fit; profile CI; advisory).", ...
    'perm-glm definition: "%s".',d2);
d3 = ST.definition("presto");
assert(d3 == "Threshold = level where the split-half correlation (median sub-averages, 500 resamples, 0.5" + ...
    NDASH + "8 ms) reaches 0.30 (sigmoid or power-law fit).",'presto definition: "%s".',d3);
sx = mabr.analysis.Settings(Alpha=0.01,NumPermutations=2000,MinConsecutive=3,DetectMethod="clusterMass", ...
    SplitHalfResamples=300,SplitHalfWindow=[1 6],ThresholdConvention="lowest_level");
d4 = ST.definition(ST.resolve("perm-descending",sx),sx);
assert(contains(d4,"0.01") && contains(d4,"2000 permutations") && contains(d4,"3 consecutive") && ...
    contains(d4,"cluster-mass") && startsWith(d4,"Threshold = the lowest level"),'Definition ignores the settings: "%s".',d4);
d6 = ST.definition("xcorr-dtw");
assert(d6 == "Threshold = level where the correlation with the next-louder level's average after time " + ...
    "warping (dtw, lag 0" + NDASH + "0.3 ms changing along the response, smoothed over 2 ms) reaches 0.40, " + ...
    "interpolated between the bracketing levels of the lowest run of 2 consecutive levels at or above it, " + ...
    "descending from the loudest level to the first 2 consecutive misses.",'xcorr-dtw definition: "%s".',d6);
s5 = mabr.analysis.Settings(MaxLag=0.5);
d7 = ST.definition(ST.resolve("xcorr-dtw",s5),s5);
assert(contains(d7,"lag 0" + NDASH + "0.5 ms"),'xcorr-dtw definition ignores MaxLag: "%s".',d7);
d5 = ST.definition(ST.resolve("presto",sx),sx);
assert(contains(d5,"300 resamples") && contains(d5,"1" + NDASH + "6 ms"),'presto definition ignores the settings: "%s".',d5);
for id = ids
    assert(strlength(ST.definition(id)) > 20,'No definition for %s.',id);
end
fprintf('  PASS methods() table, resolve refusals (badMethod), definitions carry the numbers in force\n');

%% ====================================================== N. Settings
S = mabr.analysis.Settings();
defaults = {
    'Profile',"MABR default"; 'Window',[-12 12]; 'ResponseWindow',[0.5 8]; 'BaselineWindow',[-10 0];
    'BaselineAmpWindow',[-1 0]; 'HighPass',[150 300]; 'LowPass',[3000 4200]; 'FilterPassRippleDb',0.25;
    'FilterStopAttenDb',30; 'Detrend',NaN; 'Processing',"auto"; 'WindowedOrder',2;
    'WindowedPadMode',"reflect"; 'PoolAcqModes',false; 'MaxSweepsPerCondition',Inf; 'EqualizeMode',"first";
    'HonorAcquisitionArtifacts',true; 'RejectMethod',"median"; 'RejectFeature',"absPeak"; 'RejectFactor',3;
    'RejectUpperOnly',true; 'RejectCeiling',Inf; 'DetectMethod',"tfce"; 'NumPermutations',1000;
    'Alpha',0.05; 'Seed',1; 'SplitHalfMode',"median"; 'SplitHalfResamples',500; 'SplitHalfWindow',[];
    'SplitHalfMinPerPolarity',25; 'MaxLag',0.3; 'ThresholdMethod',"perm-glm"; 'ThresholdMetric',"detection";
    'ThresholdModel',"glm"; 'CriterionMode',"probability"; 'Criterion',NaN; 'LevelParam',"";
    'GroupBy',string.empty(1,0); 'LevelDirection',"auto"; 'MinConsecutive',2; 'ThresholdConvention',"midpoint";
    'Interpolate',true; 'MinSweeps',100; 'MinPerPolarity',40; 'Extrapolate',true; 'NearestLevel',false;
    'CIAlpha',0.05; 'CINumSamples',2000; 'ThresholdBootstrap',0; 'FlagWideCI',0.35; 'FlagNonMonotoneTol',0;
    'PeakOctaveShift',0.15; 'PeakRefFrequency',16; 'PeakSmooth',0; 'PeakMinSeparation',0.3;
    'PeakTrackEarly',0.1; 'PeakTrackLate',0.15; 'PeakCandidateRN',1; 'PeakDetectableRN',4;
    'PeakPolarity',"balanced"; 'PeaksAboveThresholdOnly',true; 'PeakBootstrap',0; 'PeakEdgeMs',1.0;
    'ConductionDelayMode',"none"; 'ConductionDelay',0; 'SpeakerDistance',10; 'SpeedOfSound',343;
    'TimeOffset',0};
for k = 1:size(defaults,1)
    assert(isequaln(S.(defaults{k,1}),defaults{k,2}),'Settings default %s is wrong.',defaults{k,1});
end
% Each wave its own latency shift, larger for the later waves (13 A8).
assert(isequal([S.Waves.Name],["I","II","III","IV","V"]) && isequal([S.Waves.TMin],[1 1.8 2.6 3.4 4.2]) && ...
    isequal([S.Waves.TMax],[2 2.8 3.6 4.6 5.6]) && all([S.Waves.Enabled]) && ...
    isequal([S.Waves.LatencyShift],[0.015 0.018 0.020 0.025 0.030]) && ...
    isequal([S.Waves.Expected],([S.Waves.TMin]+[S.Waves.TMax])/2),'Settings default Waves are wrong.');
assert(isempty(S.problems()),'Default settings report problems: %s',strjoin(S.problems(),' | '));
% Settings' validators spell the vocabularies of the classes that read them;
% held equal here so that neither can grow a value the other refuses.
src = fileread(which('mabr.analysis.Settings'));
vocab = {'ThresholdMethod',ST.Ids; 'ThresholdMetric',ST.Metrics; 'ThresholdModel',ST.Models; ...
         'CriterionMode',ST.CriterionModes; 'RejectFeature',mabr.analysis.Artifacts.Features};
for k = 1:size(vocab,1)
    tok = regexp(src,[vocab{k,1} ' \(1,1\) string \{mustBeMember\(' vocab{k,1} ',\[([^\]]*)\]\)\}'],'tokens','once');
    assert(~isempty(tok),'Settings.%s has no mustBeMember list to compare.',vocab{k,1});
    listed = strip(strip(split(string(tok{1}),",")),'"').';
    assert(isequal(listed,vocab{k,2}),'Settings.%s accepts [%s], its reader [%s].',vocab{k,1}, ...
        strjoin(listed,' '),strjoin(vocab{k,2},' '));
end
fprintf('  PASS Settings defaults table (ThresholdMethod perm-glm) and no problems; vocabularies agree\n');

% Settings keeps its own copies of two things Peaks owns, so that it does not
% depend on Peaks; these two checks are what keep the copies honest.
assert(~isempty(meta.class.fromName('mabr.analysis.Peaks')), ...
    'mabr.analysis.Peaks is missing: Settings'' copies of its waves and name rule cannot be checked.');
assert(isequal(mabr.analysis.Settings().Waves,mabr.analysis.Peaks.defaultWaves()), ...
    'Settings().Waves differ from Peaks.defaultWaves().');
fprintf('  PASS Settings().Waves equals Peaks.defaultWaves()\n');
probes = {"I",strings(0,1); "",strings(0,1); "   ",strings(0,1); "12",strings(0,1); "1a",strings(0,1); ...
          "i",["I" "II"]; " II ",["I" "II"]; "VI",["I" "II"]; 'N1',{'P1','N1'}; "A",string(missing); ...
          "007",strings(0,1); "v",["I" "II" "III" "IV" "V"]; 'Wave I',"I"};
for k = 1:size(probes,1)
    a = mabr.analysis.Settings.waveNameProblem(probes{k,1},probes{k,2});
    b = mabr.analysis.Peaks.nameProblem(probes{k,1},probes{k,2});
    assert(isequal(a,b),'Wave name rules disagree on "%s": "%s" vs "%s".',string(probes{k,1}),a,b);
end
% A wave added without a latency shift gets the same one from both.
bare = struct('Name',"VI",'TMin',5.5,'TMax',6.5);
sb = mabr.analysis.Settings(Waves=bare);
wb = mabr.analysis.Peaks.wavesFor(bare);
assert(sb.Waves.LatencyShift == 0.02 && wb.LatencyShift == 0.02 && ...
    mabr.analysis.Peaks.AddedLatencyShift == 0.02 && isequal(sb.Waves,wb), ...
    'A wave without a LatencyShift: Settings gives %g, Peaks %g (both should give 0.02 ms/dB).', ...
    sb.Waves.LatencyShift,wb.LatencyShift);
fprintf('  PASS Settings.waveNameProblem agrees with Peaks.nameProblem (verdict and wording); an added wave shifts 0.02 ms/dB in both\n');

% the step map covers every property, and nothing else
mcS = ?mabr.analysis.Settings;
props = mcS.PropertyList;
props = props(~[props.Constant] & ~[props.Dependent] & strcmp({props.SetAccess},'public'));
names = sort(string({props.Name}));
st = S.toStruct();
assert(isequal(names,sort(setdiff(string(fieldnames(st)).',"SettingsVersion"))), ...
    'toStruct and the class properties disagree.');
for nm = names
    sp = mabr.analysis.Settings.stepOf(nm);
    assert(ismember(sp,[mabr.analysis.Settings.Steps "report" "none"]),'stepOf(%s) = "%s".',nm,sp);
end
% The latency reference places the wave windows (13 A9), so it is a peaks
% setting -- TimeOffset included -- and no longer a report-only one.
latRef = ["ConductionDelayMode","ConductionDelay","SpeakerDistance","SpeedOfSound","TimeOffset"];
spot = ["Window","segment"; "ResponseWindow","reject"; "BaselineWindow","measure"; "BaselineAmpWindow","peaks";
        "Seed","detect"; "ThresholdMethod","thresholds"; "Waves","peaks"; "Profile","none";
        "SettingsVersion","none"; latRef.' repmat("peaks",numel(latRef),1)];
for k = 1:size(spot,1)
    assert(mabr.analysis.Settings.stepOf(spot(k,1)) == spot(k,2),'stepOf(%s) should be %s.',spot(k,1),spot(k,2));
end
expectError(@() mabr.analysis.Settings.stepOf("NoSuchThing"),'mabr:analysis:Settings:unknownField','stepOf unknown');
rs = S.resultsStruct();
assert(~isfield(rs,'Profile') && all(isfield(rs,cellstr(latRef))) && isfield(rs,'Waves'), ...
    'resultsStruct holds the wrong fields.');
assert(all(isfield(S.stepSettings("peaks"),cellstr(latRef))) && isempty(fieldnames(S.stepSettings("report"))), ...
    'stepSettings("peaks") must hold the latency reference, and nothing is report-only any more.');
ts = S.stepSettings("thresholds");
assert(isfield(ts,'Criterion') && ~isfield(ts,'Alpha') && numel(fieldnames(ts)) == sum(arrayfun(@(n) ...
    mabr.analysis.Settings.stepOf(n) == "thresholds",names)),'stepSettings("thresholds") is wrong.');
fprintf('  PASS stepOf covers every property; resultsStruct/stepSettings\n');

% plain structs, forgivingly
S2 = mabr.analysis.Settings(alpha=0.01,GroupBy="Frequency",SplitHalfWindow=[1 6],HighPass=[], ...
    Profile="mine",Detrend=1,TimeOffset=0.078,ConductionDelayMode="distance",SpeakerDistance=12.5);
S2.Waves(2).TMin = 1.9;
S2.Waves(end+1) = struct('Name',"VI",'Enabled',false,'TMin',5.5,'TMax',7,'Expected',6,'LatencyShift',0.02,'Stimulus',"Tone");
[R2,wn] = mabr.analysis.Settings.fromStruct(S2.toStruct());
assert(isempty(wn) && isequaln(R2,S2),'toStruct/fromStruct does not round-trip.');
[R0,wn] = mabr.analysis.Settings.fromStruct(S.toStruct());
assert(isempty(wn) && isequaln(R0,S),'Defaults do not round-trip.');
junk = S2.toStruct();
junk.SomethingNew = 42;
junk.Alpha = "abc";
junk.Window = 5;
junk.Waves = 5;
junk.ThresholdMethod = "nonsense";
junk.NumPermutations = -3;
junk.ResponseWindow = 'ab';
junk.ConductionDelayMode = "sideways";
junk.SpeakerDistance = "far";
[R3,wn] = mabr.analysis.Settings.fromStruct(junk);
for nm = ["Alpha","Window","Waves","ThresholdMethod","NumPermutations","ResponseWindow", ...
          "ConductionDelayMode","SpeakerDistance"]
    assert(isequaln(R3.(nm),S.(nm)),'fromStruct kept a bad %s.',nm);
    assert(any(startsWith(wn,nm + ":")),'fromStruct did not warn about %s.',nm);
end
assert(numel(wn) == 8 && ~any(contains(wn,"SomethingNew")) && R3.Profile == "mine" && ...
    isequal(R3.GroupBy,"Frequency") && R3.TimeOffset == 0.078, ...
    'fromStruct: %d warnings: %s',numel(wn),strjoin(wn,' | '));
% A settings file from before the latency reference existed: its absence is
% the default (none), without a word -- nothing was refused.
old = rmfield(S2.toStruct(),{'ConductionDelayMode','ConductionDelay','SpeakerDistance','SpeedOfSound'});
[R6,wn] = mabr.analysis.Settings.fromStruct(old);
assert(isempty(wn) && R6.ConductionDelayMode == "none" && R6.conductionDelay() == 0 && ...
    R6.latencyOffset() == 0.078 && R6.SpeakerDistance == 10 && R6.SpeedOfSound == 343, ...
    'An older settings struct without the latency reference: %s',strjoin(wn,' | '));
[R4,wn] = mabr.analysis.Settings.fromStruct(5);
assert(isequaln(R4,S) && ~isempty(wn),'A non-struct should give the defaults with a warning.');
assert(isequal(mabr.analysis.Settings(GroupBy="").GroupBy,string.empty(1,0)) && ...
    isequal(mabr.analysis.Settings(GroupBy=["Frequency" " " string(missing)]).GroupBy,"Frequency") && ...
    mabr.analysis.Settings(GroupBy="").hash() == S.hash(), ...
    'A blank GroupBy should be the empty list ("auto"), not a parameter named "".');
expectError(@() mabr.analysis.Settings(NotASetting=1),'mabr:analysis:Settings:unknownField','constructor unknown name');
expectError(@() mabr.analysis.Settings(Detrend=0.5),'mabr:analysis:Settings:badValue','Detrend 0.5');
fprintf('  PASS toStruct/fromStruct round trip; junk ignored; wrong types -> default + warning\n');

% problems
probs = {
    'NumPermutations', 10,                  "significant"
    'Window',          [12 -12],            "not ascending"
    'ResponseWindow',  [0 20],              "not inside Window"
    'HighPass',        [300 150],           "HighPass"
    'HighPass',        [150 3500],          "high-pass pass band"
    'LowPass',         [3000 4200 5000],    "LowPass"
    'SplitHalfResamples', 5,                "SplitHalfResamples"
    'MinConsecutive',  0,                   "MinConsecutive"
    'BaselineWindow',  [0 -10],             "BaselineWindow"
    };
for k = 1:size(probs,1)
    s = mabr.analysis.Settings(probs{k,1},probs{k,2});
    p = s.problems();
    assert(~isempty(p) && any(contains(p,probs{k,3})),'%s = %s: problems() said "%s".', ...
        probs{k,1},mat2str(probs{k,2}),strjoin(p,' | '));
end
% The latency reference's numbers are judged under the mode that reads them,
% and only there: a dialog greys the fields a mode does not use, and a bad
% value in a greyed field must not block Apply (Criterion's rule, below).
probs = {
    'ConductionDelay', -0.1,                "delay"
    'ConductionDelay', NaN,                 "delay"
    'ConductionDelay', Inf,                 "delay"
    'SpeakerDistance', 0,                   "distance"
    'SpeakerDistance', 600,                 "distance"
    'SpeakerDistance', NaN,                 "distance"
    'SpeedOfSound',    250,                 "distance"
    'SpeedOfSound',    450,                 "distance"
    };
for k = 1:size(probs,1)
    s = mabr.analysis.Settings(probs{k,1},probs{k,2},ConductionDelayMode=probs{k,3});
    p = s.problems();
    assert(~isempty(p) && any(contains(p,probs{k,1})),'%s = %s (mode %s): problems() said "%s".', ...
        probs{k,1},mat2str(probs{k,2}),probs{k,3},strjoin(p,' | '));
    for other = setdiff(["none","delay","distance"],probs{k,3})
        s = mabr.analysis.Settings(probs{k,1},probs{k,2},ConductionDelayMode=other);
        assert(~any(contains(s.problems(),probs{k,1})), ...
            '%s = %s is not read under mode "%s", yet problems() said "%s".', ...
            probs{k,1},mat2str(probs{k,2}),other,strjoin(s.problems(),' | '));
    end
end
s = mabr.analysis.Settings(NumPermutations=19);
assert(~isempty(s.problems()),'19 permutations at alpha 0.05 can never reach p < 0.05.');
s = mabr.analysis.Settings(NumPermutations=20);
assert(isempty(s.problems()),'20 permutations at alpha 0.05 can.');
s = mabr.analysis.Settings(); s.Waves(2).Name = "i";
assert(any(contains(s.problems(),"already a wave")),'Duplicate wave names (any case) not reported.');
s = mabr.analysis.Settings(); s.Waves(3).Name = "12";
assert(any(contains(s.problems(),"plain number")),'All-digit wave name not reported.');
s = mabr.analysis.Settings(); s.Waves(1).Name = "  ";
assert(any(contains(s.problems(),"needs a name")),'Blank wave name not reported.');
s = mabr.analysis.Settings(); s.Waves(4).TMax = 3;
assert(any(contains(s.problems(),"not below TMax")),'TMin >= TMax not reported.');
% Names are unique per stimulus: Peaks.wavesFor uses ONE stimulus's rows, so a
% click-specific I..V beside the generic I..V is the point of the Stimulus
% column, not a duplicate. Inside one stimulus's rows (Stimulus compared
% without case, as wavesFor does) a repeat still is.
s = mabr.analysis.Settings();
Wc = s.Waves;
for k = 1:numel(Wc), Wc(k).Stimulus = "ClickTrain"; Wc(k).TMin = Wc(k).TMin - 0.2; end
s.Waves = [s.Waves Wc];
assert(isempty(s.problems()),'A per-stimulus I..V set is reported: %s',strjoin(s.problems(),' | '));
s2 = s; s2.Waves(10).Name = "iv";
assert(any(contains(s2.problems(),"already a wave")),'A repeat inside the ClickTrain rows is not reported.');
s2 = s; s2.Waves(end+1) = struct('Name',"I",'Enabled',true,'TMin',1,'TMax',2,'Expected',1.5, ...
    'LatencyShift',0.01,'Stimulus',"clicktrain");
assert(any(contains(s2.problems(),"already a wave")),'Stimulus is not compared without case.');
s = mabr.analysis.Settings(ThresholdMethod="custom",ThresholdMetric="splithalf",ThresholdModel="glm");
assert(any(contains(s.problems(),"Custom threshold method")),'A refused custom combination is not a problem.');
s = mabr.analysis.Settings(ThresholdMethod="custom",Criterion=1.5);
assert(any(contains(s.problems(),"criterion")),'A criterion out of range is not a problem.');
s = mabr.analysis.Settings(Criterion=1.5);
assert(isempty(s.problems()),'A named method does not read Criterion, so it is no problem there.');
% the edges of the latency reference's ranges are allowed
s = mabr.analysis.Settings(ConductionDelayMode="distance",SpeakerDistance=500,SpeedOfSound=300);
s2 = mabr.analysis.Settings(ConductionDelayMode="delay",ConductionDelay=0,SpeedOfSound=400,SpeakerDistance=0.5);
assert(isempty(s.problems()) && isempty(s2.problems()), ...
    'A 500 cm distance, 300/400 m/s and a zero delay are possible: %s',strjoin([s.problems(); s2.problems()],' | '));
fprintf(['  PASS problems(): permutations, windows, filter edges, waves (names per stimulus), resamples, K, ' ...
    'custom method, criterion, conduction delay / speaker distance / speed of sound\n']);

% diff, firstChangedStep, hash
D0 = mabr.analysis.Settings.diff(S,mabr.analysis.Settings(Profile="renamed"));
assert(height(D0) == 0 && isequal(D0.Properties.VariableNames,{'Field','Step','Old','New'}),'A Profile rename is no difference.');
D1 = mabr.analysis.Settings.diff(S,mabr.analysis.Settings(Criterion=0.75));
assert(height(D1) == 1 && D1.Field == "Criterion" && D1.Step == "thresholds" && D1.Old == "NaN" && D1.New == "0.75", ...
    'diff of one Criterion change is wrong.');
assert(mabr.analysis.Settings.firstChangedStep(S,mabr.analysis.Settings(Criterion=0.75)) == "thresholds" && ...
    mabr.analysis.Settings.firstChangedStep(S,mabr.analysis.Settings(Window=[-10 10],Criterion=0.75)) == "segment" && ...
    mabr.analysis.Settings.firstChangedStep(S,mabr.analysis.Settings(ResponseWindow=[0 10])) == "reject" && ...
    mabr.analysis.Settings.firstChangedStep(S,mabr.analysis.Settings(TimeOffset=1)) == "peaks" && ...
    mabr.analysis.Settings.firstChangedStep(S,mabr.analysis.Settings(ConductionDelayMode="distance")) == "peaks" && ...
    mabr.analysis.Settings.firstChangedStep(S,S) == "",'firstChangedStep is wrong.');
h = S.hash();
assert(isstring(h) && strlength(h) == 8 && ~isempty(regexp(h,'^[0-9a-f]{8}$','once')),'hash is not 8 hex digits: %s.',h);
assert(mabr.analysis.Settings().hash() == h,'hash is not stable.');
assert(mabr.analysis.Settings(Profile="x").hash() == h,'Profile must not change the hash.');
assert(mabr.analysis.Settings(TimeOffset=0.5).hash() ~= h && ...
    mabr.analysis.Settings(ConductionDelayMode="distance").hash() ~= h && ...
    mabr.analysis.Settings(SpeakerDistance=12).hash() ~= h, ...
    'The latency reference places the wave windows: it must change the hash.');
assert(mabr.analysis.Settings(BaselineAmpWindow=[-1 -0]).hash() == h,'-0 and 0 are equal settings and must hash equal.');
sw = S; sw.Waves(1).TMin = 1.1;
assert(mabr.analysis.Settings(Alpha=0.01).hash() ~= h && sw.hash() ~= h && ...
    mabr.analysis.Settings(HighPass=[]).hash() ~= h && mabr.analysis.Settings(GroupBy="Level").hash() ~= h, ...
    'hash is not sensitive to the settings.');
fprintf('  PASS diff / firstChangedStep; hash stable (%s), sensitive, blind to -0\n',h);

% filter(), profiles
f = S.filter();
assert(isa(f,'mabr.analysis.Filter') && abs(f.PassRipple - 0.014390163418) < 1e-12 && ...
    abs(f.StopRipple - 0.031622776602) < 1e-12 && isequal(f.HighPass,[150 300]) && isequal(f.LowPass,[3000 4200]), ...
    'filter() does not reproduce the Filter defaults.');
fd = mabr.analysis.Filter;
assert(abs(f.PassRipple - fd.PassRipple) < 1e-12 && abs(f.StopRipple - fd.StopRipple) < 1e-12, ...
    'filter() ripple differs from mabr.analysis.Filter''s own defaults.');
f = mabr.analysis.Settings(HighPass=[]).filter();
assert(isempty(f.HighPass),'filter() with the high pass off.');
assert(isequal(mabr.analysis.Settings.profileNames(),["MABR default","Legacy SCRATCH (2025)"]),'profileNames.');
P0 = mabr.analysis.Settings.profile("MABR default");
assert(isequaln(P0.resultsStruct(),S.resultsStruct()) && P0.Profile == "MABR default",'The default profile is not the defaults.');
PL = mabr.analysis.Settings.profile("Legacy SCRATCH (2025)");
assert(PL.Criterion == 0.75 && PL.ThresholdMethod == "custom" && PL.ThresholdModel == "glm" && ...
    PL.CriterionMode == "probability" && isequal(PL.LowPass,[1500 3000]) && PL.FilterPassRippleDb == 0.5 && ...
    PL.Detrend == 1 && isequal(PL.ResponseWindow,[0 10]) && ~PL.RejectUpperOnly && PL.PoolAcqModes && ...
    PL.MinSweeps == 2 && PL.MinPerPolarity == 0 && PL.MinConsecutive == 1 && PL.NumPermutations == 2000 && ...
    isempty(PL.problems()),'The Legacy SCRATCH (2025) profile is wrong.');
assert(S.matchingProfile() == "MABR default" && PL.matchingProfile() == "Legacy SCRATCH (2025)" && ...
    mabr.analysis.Settings(Profile="anything").matchingProfile() == "MABR default" && ...
    mabr.analysis.Settings(Alpha=0.01).matchingProfile() == "",'matchingProfile is wrong.');
expectError(@() mabr.analysis.Settings.profile("Nope"),'mabr:analysis:Settings:unknownProfile','unknown profile');
assert(contains(PL.thresholdDefinition(),"0.75") && contains(PL.thresholdDefinition(),"2000 permutations"), ...
    'Legacy definition: "%s".',PL.thresholdDefinition());
assert(S.thresholdDefinition() == ST.definition(ST.resolve(S.ThresholdMethod,S),S),'thresholdDefinition.');
dsc = S.describe();
assert(isstring(dsc) && isscalar(dsc) && contains(dsc,"Profile: MABR default") && contains(dsc,newline) && ...
    contains(dsc,S.thresholdDefinition()),'describe() is not the multi-line summary.');
s = mabr.analysis.Settings(Waves=[]);
assert(contains(s.describe(),"Peaks: 0 waves (none)") && isempty(s.problems()) && strlength(s.hash()) == 8, ...
    'Settings without waves cannot be described, checked or hashed.');
s = mabr.analysis.Settings(); s.Waves(1).Enabled = false;
assert(contains(s.describe(),"Peaks: 4 waves (II, III, IV, V)"),'describe() lists a disabled wave.');
fprintf('  PASS filter() ripple within 1e-12 of the Filter defaults; profiles and matchingProfile; describe\n');

% The latency reference (13 A9): the delay each mode makes of the numbers,
% the offset peaks are searched and reported with, and what describe() says.
lr = @(varargin) mabr.analysis.Settings(varargin{:});
assert(S.conductionDelay() == 0 && S.latencyOffset() == 0,'The default latency offset is not 0.');
s = lr(ConductionDelayMode="delay",ConductionDelay=0.3,SpeakerDistance=50);
assert(s.conductionDelay() == 0.3 && s.latencyOffset() == 0.3, ...
    'Mode "delay" must take ConductionDelay as it is: %g ms.',s.conductionDelay());
s = lr(ConductionDelayMode="distance");
assert(s.conductionDelay() == 10*10/343 && abs(s.conductionDelay() - 0.2915) < 1e-4 && ...
    s.latencyOffset() == s.conductionDelay(), ...
    'Mode "distance", 10 cm at 343 m/s: %.6g ms, expected 0.2915.',s.conductionDelay());
s = lr(ConductionDelayMode="distance",SpeakerDistance=34.3,SpeedOfSound=343,TimeOffset=0.078);
assert(abs(s.conductionDelay() - 1) < 1e-12 && abs(s.latencyOffset() - 1.078) < 1e-12, ...
    'Mode "distance", 34.3 cm: %.15g ms (offset %.15g).',s.conductionDelay(),s.latencyOffset());
s = lr(ConductionDelay=5,SpeakerDistance=50,TimeOffset=0.078);
assert(s.conductionDelay() == 0 && s.latencyOffset() == 0.078, ...
    'Mode "none" must ignore ConductionDelay and SpeakerDistance (got %g ms).',s.conductionDelay());
d = string(lr(ConductionDelayMode="distance").describe());
assert(contains(d,"Latencies re sound arrival: 0.29 ms conduction delay (10 cm at 343 m/s)."), ...
    'describe() does not state the delay: "%s".',d);
d = string(lr(ConductionDelayMode="delay",ConductionDelay=0.35,TimeOffset=0.05).describe());
assert(contains(d,"Latencies re sound arrival: 0.35 ms conduction delay plus a 0.05 ms system offset, 0.40 ms in all."), ...
    'describe() of a delay and a system offset: "%s".',d);
assert(contains(S.describe(),"Latencies re stimulus onset (no conduction delay).") && ...
    contains(lr(TimeOffset=0.078).describe(),"Latencies re stimulus onset (no conduction delay), less a 0.078 ms system offset."), ...
    'describe() without a conduction delay: "%s".',S.describe());
D2 = mabr.analysis.Settings.diff(S,lr(ConductionDelayMode="distance",SpeakerDistance=12));
assert(isequal(D2.Field.',["ConductionDelayMode","SpeakerDistance"]) && all(D2.Step == "peaks") && ...
    isequal(D2.New.',["distance","12"]),'diff of the latency reference: %s.',strjoin(D2.Field,', '));
assert(lr(ConductionDelayMode="distance").matchingProfile() == "", ...
    'A conduction delay is not the MABR default profile.');
fprintf(['  PASS latency reference: conductionDelay()/latencyOffset() for none/delay/distance (10 cm at ' ...
    '343 m/s = %.4f ms), describe() states it, a peaks setting in diff and profiles\n'], ...
    lr(ConductionDelayMode="distance").conductionDelay());

% .mabraset files
ffn = fullfile(tmp,"lab.mabraset");
S2.save(ffn);
info = whos('-file',ffn);
assert(isscalar(info) && strcmp(info.name,'MABRAnalysisSettings') && strcmp(info.class,'struct'), ...
    'A .mabraset must hold exactly one variable, MABRAnalysisSettings.');
[R5,wn] = mabr.analysis.Settings.load(ffn);
assert(isempty(wn) && isequaln(R5,S2),'save/load .mabraset does not round-trip.');
out = S.save(fullfile(tmp,"noext"));
assert(endsWith(out,".mabraset") && isfile(out),'save() without an extension should add .mabraset.');
other = fullfile(tmp,"other.mat");
X = 1; save(other,'X');
expectError(@() mabr.analysis.Settings.load(other),'mabr:analysis:Settings:badFile','load of a foreign MAT-file');
fprintf('  PASS save/load .mabraset (one variable MABRAnalysisSettings)\n');

% prefs: guarded, and only an explicit savePrefs writes one
key = "OfflineAnalysisSettings";
g = mabrtest.prefGuard(key,Clear=true); %#ok<NASGU> % held until the clear below
assert(~ispref('MABR',char(key)),'prefGuard Clear did not clear the pref.');
assert(isequaln(mabr.analysis.Settings.loadPrefs(),S),'loadPrefs without a pref should give the defaults.');
s = mabr.analysis.Settings(Alpha=0.01);
s.NumPermutations = 2000;
s.Waves(1).TMin = 0.9;
s = mabr.analysis.Settings.fromStruct(s.toStruct()); %#ok<NASGU>
assert(~ispref('MABR',char(key)),'Constructing or setting properties wrote a pref.');
s = mabr.analysis.Settings(Alpha=0.01,NumPermutations=2000);
mabr.analysis.Settings.savePrefs(s);
assert(ispref('MABR',char(key)),'savePrefs wrote nothing.');
assert(isequaln(mabr.analysis.Settings.loadPrefs(),s),'loadPrefs does not give back what savePrefs wrote.');
setpref('MABR',char(key),"junk");
assert(isequaln(mabr.analysis.Settings.loadPrefs(),S),'A junk pref should give the defaults.');
clear g
fprintf('  PASS loadPrefs/savePrefs (guarded); a property set writes no pref\n');

%% ====================================================== O. static scan
files = ["+mabr/+analysis/Threshold.m","+mabr/+analysis/SeriesThreshold.m","+mabr/+analysis/Settings.m"];
root = fileparts(fileparts(mfilename('fullpath')));
forbidden = ["prctile","quantile","iqr","mad","range","zscore","nanmean","nanstd","nanmedian","corr", ...
    "fcdf","finv","tcdf","tinv","normcdf","norminv","normpdf","randsample","datasample","bootstrp", ...
    "fitglm","fitlm","boxplot","ksdensity","grpstats","skewness","kurtosis"];
callRx = "(?<![\w.])(" + strjoin(forbidden,"|") + ")\s*\(";
varRx  = "(?<![\w.])(range|corr|mad)\s*=(?!=)";
for fn = files
    code = splitlines(string(fileread(fullfile(root,fn))));
    for i = 1:numel(code)
        ln = regexprep(code(i),'"[^"]*"','""');              % drop string literals
        ln = regexprep(ln,'(?<![\w\)\]\}''.])''[^'']*''','''''');   % drop char literals
        ln = regexprep(ln,'%.*$','');                         % drop comments
        assert(isempty(regexp(ln,callRx,'once')) && isempty(regexp(ln,varRx,'once')), ...
            '%s line %d uses a Statistics Toolbox identifier: %s',fn,i,strtrim(code(i)));
    end
end
fprintf('  PASS static scan: no Statistics Toolbox identifiers in Threshold/SeriesThreshold/Settings\n');

%% ====================================================== P. nothing left behind
tm = timerfindall;
if ~isempty(tm)
    tags = string(get(tm,'Tag'));
    assert(~any(startsWith(tags,"MABR_Offline")),'A MABR_Offline timer leaked.');
end
assert(isempty(setdiff(findall(groot,'Type','figure'),figs0)),'A figure was left open.');
fprintf('  PASS no timer or figure left behind\n');
fprintf('verify_offline_thresholds: all checks passed (%.1f s)\n',toc(t0));
end

% =========================================================================
function Y = detY(D)
% A series' Y from a detection pattern: p 0.01 where detected, 0.5 where not.
D = double(D(:));
Y = struct('P',0.5 - 0.49*D,'IsSig',D);
end

function why = shapeProblem(o,sgn)
% What is wrong with the numbers of one estimate() answer given its Censored
% (sgn -1: an attenuation axis, where left and right trade places); empty when
% nothing is.
why = strings(1,0);
c = o.Censored;
if sgn < 0
    if c == "left", c = "right"; elseif c == "right", c = "left"; end
    t = -o.Threshold; lo = -o.ThrHi; hi = -o.ThrLo;
else
    t = o.Threshold; lo = o.ThrLo; hi = o.ThrHi;
end
switch c
    case "interval"
        if ~(lo < hi && t > lo && t <= hi), why(end+1) = "interval point outside (ThrLo,ThrHi]"; end
    case "none"
        if ~(isfinite(t) && lo == t && hi == t), why(end+1) = "point estimate with other bounds"; end
    case "left"
        if ~(isnan(lo) && t == hi && o.Status == "all-respond"), why(end+1) = "left-censored shape"; end
    case "right"
        if ~(t == Inf && isnan(hi) && isfinite(lo) && o.Status == "no-response"), why(end+1) = "right-censored shape"; end
    case ""
        if ~(isnan(t) && ismember(o.Status,["insufficient","failed"])), why(end+1) = "no censoring but a value"; end
    otherwise
        why(end+1) = "unknown Censored """ + c + """";
end
if ~ismember(o.Status,mabr.analysis.SeriesThreshold.Statuses), why(end+1) = "unknown Status"; end
if any(o.Detected & ~o.Usable), why(end+1) = "an unusable level detected"; end
if o.NumSig ~= sum(o.Detected) || o.NumUsable ~= sum(o.Usable), why(end+1) = "counts"; end
end

function expectError(fcn,id,what)
% Assert that fcn() throws the error identifier id.
try
    fcn();
catch ME
    assert(strcmp(ME.identifier,id),'%s: threw %s (%s), expected %s.',what,ME.identifier,ME.message,id);
    return
end
error('verify_offline_thresholds:noError','%s: expected error %s, none thrown.',what,id);
end
