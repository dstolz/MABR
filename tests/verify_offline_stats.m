function verify_offline_stats()
% verify_offline_stats  Single-trial statistics and wave picking (mabr.analysis.SingleTrial, .Peaks).
%
%   Every claim the two pure classes make about one condition, checked on
%   in-memory synthetic sweeps whose truth is known -- no files, no hardware,
%   no parallel pool, no figures, no preferences:
%
%   Part A (the balanced mean): SingleTrial.balancedMean equals a naive
%   per-class computation, its SEM is the within-file-x-polarity pooled
%   variance times (1/n+ + 1/n-)/4, and one-polarity data are flagged.
%   Part B (calibration under H0): 200 null conditions of coloured noise with
%   a polarity-locked cochlear microphonic as large as the noise. The power
%   test rejects at its nominal rate, Fsp averages about 1 and does not
%   over-reject, and RN is sigma/sqrt(N). (A test that pooled the CM into
%   its noise or its null would fail exactly here.) The power test's p and
%   null do not change at all when a CM is added, and a condition too small
%   for a sign-flip null gets no p.
%   Part C (the one statistic): the partition-averaged split-half r with
%   mean halves is (F-1)/(F+1); median halves give a lower r.
%   Part D (+/- reference): balanced signs cancel the CM exactly, where
%   (+)-(-) and polarity-following signs show it.
%   Part E (convergence): RN falls as N^-0.5 on noise.
%   Part F (features, blocks, bootstrap band, xcorrUp -- bounded even on the
%   vanishing tails of a noiseless template -- and dtwUp: a rigid shift
%   recovered exactly, waves shifted by different amounts lined up where one
%   lag cannot, one direction only, the lag-0 r with no room to warp, and on
%   noise no higher than xcorrUp, as it is not without its smoothing).
%   Part G (picking): parabolic refinement is unbiased to well under 20 us;
%   pick() finds waves I-V of the synthetic template; track() follows them
%   down to threshold without swapping labels; manual and absent anchors and
%   troughs behave as documented; a NaN prominence floor (a level with no
%   RN) means no floor, and a NaN level neither tracks nor is tracked from.
%   Part H (peak uncertainty and derived measures): the bootstrap is
%   reproducible and flags unstable picks on noise; singleTrial's shape;
%   derived IPLs and growth slopes; wavesFor; nameProblem; waveColor;
%   reported.
%   Part I (no Statistics toolbox): a static scan of both classes.
%   Part J (the contract's shapes): summary's fields and the relations
%   between them, splitHalf's struct, every table's columns, and no draw
%   from the global random stream.
%   Part K (the default tracking priors and the latency reference): with
%   each default wave's own latency shift and a prior at the latency it is
%   expected at, track() follows the noiseless 16 kHz series to threshold
%   within a sample of the truth, and series whose latencies grow half and
%   one and a half times as fast -- or tracked with half and one and a half
%   times the default shifts -- without a label switch; a wave missed for
%   two levels does not take the next wave's peak (the window ends before
%   where that wave is expected); wavesFor's Offset moves a set of windows,
%   and a series 0.3 ms late tracked in windows moved by it gives the same
%   waves.
%
%   Run:  >> verify_offline_stats
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_stats ==\n');
nFigsBefore = numel(findall(groot,'Type','figure'));

fs    = 12000;
dtms  = 1000/fs;
[bb,aa] = butter(2,[300 3000]/(fs/2));
truth = mabrtest.SyntheticABR.defaults();
tAll  = (-24:120)'/fs*1000;                 % -2 .. 10 ms re onset
resp  = tAll >= 0.5 & tAll <= 8;            % the default response window

% ---- Part A: the balanced mean ---------------------------------------------
rs = RandStream('threefry','Seed',101);
nT = 40;  N = 46;
pol = ones(1,N);  pol(randperm(rs,N,20)) = -1;          % 26 +, 20 -
strata = [ones(1,25) 2*ones(1,21)];
X = 1e-6*randn(rs,nT,N) + 0.4e-6*sin((1:nT)'/3);
X(:,strata == 2) = X(:,strata == 2) + 0.5e-6;            % a level shift between files
X = X + 2e-6*sin((1:nT)'/2).*pol;                       % polarity-locked component
[m,sem,info] = mabr.analysis.SingleTrial.balancedMean(X,pol,strata);
P = pol > 0;  Q = pol < 0;
mNaive = (mean(X(:,P),2) + mean(X(:,Q),2))/2;
ss = zeros(nT,1);  G = 0;
for f = 1:2
    for s = [1 -1]
        k = strata == f & pol == s;
        if ~any(k), continue; end
        G  = G + 1;
        ss = ss + sum((X(:,k) - mean(X(:,k),2)).^2,2);
    end
end
semNaive = sqrt(ss/(N - G)*0.25*(1/sum(P) + 1/sum(Q)));
assert(max(abs(m - mNaive)) <= 1e-12*max(abs(mNaive)), ...
    'balancedMean differs from (mean(+) + mean(-))/2 by %.3g.',max(abs(m - mNaive)));
assert(max(abs(sem - semNaive)) <= 1e-12*max(semNaive), ...
    'the SEM is not the within-group pooled variance x (1/n+ + 1/n-)/4.');
assert(info.N == N && info.NPos == sum(P) && info.NNeg == sum(Q) && info.G == G && info.Balanced, ...
    'balancedMean info fields are wrong (G %d, NPos %d).',info.G,info.NPos);
% The point of stratifying: pooling everything counts the CM and the file
% shift as noise.
semPooled = std(X,0,2)/sqrt(N);
assert(mean(semPooled) > 1.3*mean(sem), ...
    'the stratified SEM should be far below one that pools the CM and file shift as noise.');
[m1,sem1,info1] = mabr.analysis.SingleTrial.balancedMean(X(:,P),pol(P),strata(P));
assert(max(abs(m1 - mean(X(:,P),2))) <= 1e-12*max(abs(m1)) && ~info1.Balanced, ...
    'one-polarity data must give the plain mean and Balanced = false.');
ss1 = zeros(nT,1);
for f = 1:2
    k = strata(P) == f;  XP = X(:,P);
    ss1 = ss1 + sum((XP(:,k) - mean(XP(:,k),2)).^2,2);
end
assert(max(abs(sem1 - sqrt(ss1/(sum(P) - 2)/sum(P)))) <= 1e-12*max(sem1), ...
    'one-polarity SEM must be s^2/N with s^2 pooled within files.');
S1 = mabr.analysis.SingleTrial.summary(X(:,P),[],pol(P),strata(P),Measures="none");
S2 = mabr.analysis.SingleTrial.summary(X,[],pol,strata,Measures="none");
assert(any(S1.Flags == "polarity-locked components not cancelled") && ~S1.Balanced, ...
    'one-polarity data must carry the "polarity-locked components not cancelled" flag.');
assert(isempty(S2.Flags) && S2.Balanced,'balanced data must carry no flag.');
fprintf('  PASS Part A: balanced mean = naive per-class mean; SEM pooled within %d groups; one polarity flagged\n',G);

% ---- Part B: calibration under H0 (coloured noise + CM) --------------------
gen  = RandStream('threefry','Seed',202);
perm = RandStream('threefry','Seed',203);
nR = 60;  N = 64;  nC = 200;  B = 199;
tt  = (0:nR-1)'/fs;
pol = (-1).^(0:N-1);
pilot  = filtfilt(bb,aa,randn(gen,6000,4));
cmAmp  = std(reshape(pilot(1001:end-1000,:),[],1));   % CM as large as the noise
pPow = zeros(nC,1);  pFsp = pPow;  Fsp = pPow;  RN = pPow;  df1 = pPow;
sumsq = 0;  cnt = 0;
for c = 1:nC
    E = filtfilt(bb,aa,randn(gen,nR+200,N));
    E = E(101:100+nR,:);
    sumsq = sumsq + sum(E(:).^2);  cnt = cnt + numel(E);
    X = E + cmAmp*sin(2*pi*1000*tt + 2*pi*rand(gen)).*pol;
    [~,pPow(c)] = mabr.analysis.SingleTrial.powerTest(X,pol,[],[],B,perm);
    f = mabr.analysis.SingleTrial.fsp(X,pol,[],[]);
    pFsp(c) = f.P;  Fsp(c) = f.F;  df1(c) = f.DF1;
    [~,sm] = mabr.analysis.SingleTrial.balancedMean(X,pol,[]);
    RN(c) = sqrt(mean(sm.^2));
end
sigEff  = sqrt(sumsq/cnt);
fpPow   = mean(pPow < 0.05);
fpFsp   = mean(pFsp < 0.05);
rnRatio = mean(RN)/(sigEff/sqrt(N));
assert(fpPow >= 0.02 && fpPow <= 0.09, ...
    'powerTest false-positive rate %.3f at alpha 0.05 is outside [0.02 0.09].',fpPow);
assert(fpFsp <= 0.10,'Fsp false-positive rate %.3f exceeds 0.10.',fpFsp);
assert(mean(Fsp) >= 0.8 && mean(Fsp) <= 1.25,'mean Fsp under H0 is %.3f, not in [0.8 1.25].',mean(Fsp));
assert(abs(rnRatio - 1) < 0.05,'RN is %.3f of sigma/sqrt(N), not within 5%%.',rnRatio);
% Why the power test flips group RESIDUALS and holds its noise term fixed
% (10 s8.3 flipped raw sweeps and recomputed the noise from sum x^2, which
% let the CM deflate the null): a CM, however large, cannot reach it.
cmBig3 = 3*cmAmp*sin(2*pi*1000*tt).*pol;
[F0,p0,n0] = mabr.analysis.SingleTrial.powerTest(E,pol,[],[],B,RandStream('threefry','Seed',5));
[F1,p1,n1] = mabr.analysis.SingleTrial.powerTest(E + cmBig3,pol,[],[],B,RandStream('threefry','Seed',5));
assert(p1 == p0 && abs(F1 - F0) <= 1e-9*F0 && max(abs(n1 - n0)) <= 1e-9*max(n0), ...
    'the power test changed when a CM was added (p %.3f -> %.3f, F %.4g -> %.4g).',p0,p1,F0,F1);
% Too few distinct sign patterns for a sign-flip null: F, but no p. (Eight
% alternating sweeps have 18 patterns; without this rule pure noise was
% "detected" at alpha 0.05 9% of the time at 8 sweeps, 34% at 4.)
[F8,p8,n8] = mabr.analysis.SingleTrial.powerTest(E(:,1:8),pol(1:8),[],[],B,perm);
[~,p16]    = mabr.analysis.SingleTrial.powerTest(E(:,1:16),pol(1:16),[],[],B,perm);
assert(isfinite(F8) && isnan(p8) && isempty(n8) && isfinite(p16), ...
    'eight sweeps must get an F but no p (too few sign patterns), sixteen a p.');
fprintf(['  PASS Part B: %d null conditions with CM: power-test FP %.3f, Fsp FP %.3f, ' ...
    'mean Fsp %.3f (df1 ~%.0f), RN/(sigma/sqrtN) %.3f; power test blind to a CM 3x the noise; ' ...
    'no p from 8 sweeps\n'],nC,fpPow,fpFsp,mean(Fsp),median(df1),rnRatio);

% ---- Part C: split-half r = (F-1)/(F+1) ------------------------------------
N   = 64;  pol = (-1).^(0:N-1);
y60 = mabrtest.SyntheticABR.template(tAll,60,16,truth);
Ps  = mean((y60(resp) - mean(y60(resp))).^2);
cm  = 1e-6*sin(2*pi*tAll).*exp(-max(tAll,0)/1.5).*(tAll >= 0);
diffs = zeros(1,3);  Fs = diffs;  rMean = diffs;  rMed = diffs;
targets = [2 4 8];
for i = 1:3
    g = RandStream('threefry','Seed',300 + i);
    E = filtfilt(bb,aa,randn(g,numel(tAll)+200,N));
    E = E(101:100+numel(tAll),:);
    E = E/std(E(:));
    X = y60 + sqrt(N*Ps/(targets(i) - 1))*E + cm.*pol;
    Sm = mabr.analysis.SingleTrial.summary(X,tAll,pol,[],Rows=resp,Measures="splithalf", ...
        SplitHalfMode="mean",SplitHalfResamples=400,SplitHalfK=N/4,MinPerPolarity=1, ...
        Stream=RandStream('threefry','Seed',9));
    Sd = mabr.analysis.SingleTrial.summary(X,tAll,pol,[],Rows=resp,Measures="splithalf", ...
        SplitHalfMode="median",SplitHalfResamples=400,SplitHalfK=N/4,MinPerPolarity=1, ...
        Stream=RandStream('threefry','Seed',9));
    Fs(i) = Sm.F;  rMean(i) = Sm.SplitR;  rMed(i) = Sd.SplitR;
    diffs(i) = Sm.SplitR - (Sm.F - 1)/(Sm.F + 1);
    assert(Sm.SplitN == N/4,'split-half K should be N/4 = %d, got %d.',N/4,Sm.SplitN);
    assert(Sm.SplitRP025 <= Sm.SplitR && Sm.SplitR <= Sm.SplitRP975, ...
        'the partition percentiles must bracket the partition mean.');
end
assert(all(abs(diffs) < 0.05), ...
    'partition-averaged split-half r differs from (F-1)/(F+1) by %s.',mat2str(diffs,3));
assert(all(rMed < rMean),'median halves must give a lower r than mean halves (%s vs %s).', ...
    mat2str(rMed,3),mat2str(rMean,3));
fprintf(['  PASS Part C: split-half r(mean) - (F-1)/(F+1) = %s at F %s; ' ...
    'median-mode r lower (%s)\n'],mat2str(diffs,2),mat2str(Fs,2),mat2str(rMed,2));

% ---- Part D: the +/- reference cancels the CM ------------------------------
g = RandStream('threefry','Seed',404);
N = 64;  pol = (-1).^(0:N-1);  P = pol > 0;
E = filtfilt(bb,aa,randn(g,numel(tAll)+200,N));
E = 5e-6*E(101:100+numel(tAll),:);
cmBig = 10e-6*sin(2*pi*tAll).*exp(-max(tAll,0)/1.5).*(tAll >= 0);
X  = E + cmBig.*pol;
q1 = mabr.analysis.SingleTrial.plusMinus(X,pol,[],RandStream('threefry','Seed',7));
q0 = mabr.analysis.SingleTrial.plusMinus(E,pol,[],RandStream('threefry','Seed',7));
assert(norm(q1 - q0) <= 1e-9*norm(q0), ...
    'the +/- reference changed when a CM was added (%.3g of its norm).',norm(q1 - q0)/norm(q0));
dPM = mean(X(:,P),2) - mean(X(:,~P),2);                  % (+)-(-)
cc = corrcoef(dPM,2*cmBig);
assert(cc(1,2) > 0.95,'(+)-(-) should show the CM (r = %.3f).',cc(1,2));
qTrap = X*(pol.'/N);                                     % signs that follow polarity
ct = corrcoef(qTrap,cmBig);
assert(norm(qTrap) > 3*norm(q1) && ct(1,2) > 0.9, ...
    'polarity-following signs should carry the CM (|trap| %.3g vs |q| %.3g, r %.2f).', ...
    norm(qTrap),norm(q1),ct(1,2));
[~,sm] = mabr.analysis.SingleTrial.balancedMean(X,pol,[]);
ratio = sqrt(mean(q1.^2))/sqrt(mean(sm.^2));
assert(ratio > 0.7 && ratio < 1.3,'RMS of the +/- reference is %.2f of RN.',ratio);
% Odd groups: the one unpaired sign takes 1/n^2 of a group's variance (11%
% at three sweeps), which the reference gives back -- E[q^2] = sem^2.
po = [ones(1,5) -ones(1,3)];  q2 = 0;  s2 = 0;
for rep = 1:1000
    Z = randn(g,200,8) + 4*po;                           % with a polarity-locked offset
    q2 = q2 + mean(mabr.analysis.SingleTrial.plusMinus(Z,po,[],g).^2);
    [~,sz] = mabr.analysis.SingleTrial.balancedMean(Z,po,[]);
    s2 = s2 + mean(sz.^2);
end
assert(abs(q2/s2 - 1) < 0.02,'E[q^2]/sem^2 with groups of 5 and 3 is %.3f, not 1.',q2/s2);
fprintf(['  PASS Part D: +/- reference identical with and without a CM; (+)-(-) shows it (r %.3f); ' ...
    'RNPM/RN %.2f; E[q^2]/sem^2 %.3f with odd groups\n'],cc(1,2),ratio,q2/s2);

% ---- Part E: convergence ----------------------------------------------------
g = RandStream('threefry','Seed',505);
N = 512;  pol = (-1).^(0:N-1);
X = randn(g,100,N);
C = mabr.analysis.SingleTrial.convergence(X,pol,[],[],[16 32 64 128 256 512], ...
    RandStream('threefry','Seed',5));
assert(isequal(C.Properties.VariableNames,{'N','RN','ResponseRMS','F','SNR','SplitR'}), ...
    'convergence table columns are wrong.');
assert(isequal(C.N.',[16 32 64 128 256 512]),'convergence N column is %s.',mat2str(C.N.'));
b = polyfit(log(C.N),log(C.RN),1);
assert(b(1) >= -0.6 && b(1) <= -0.4,'log-log slope of RN vs N is %.3f, not in [-0.6 -0.4].',b(1));
fprintf('  PASS Part E: RN falls with slope %.3f on log-log axes\n',b(1));

% ---- Part F: features, blocks, bootstrap band, xcorrUp ---------------------
g = RandStream('threefry','Seed',606);
N = 96;  pol = (-1).^(0:N-1);
y80 = mabrtest.SyntheticABR.template(tAll,80,16,truth);
E = filtfilt(bb,aa,randn(g,numel(tAll)+200,N));
E = 3e-6*E(101:100+numel(tAll),:)/std(E(:));
X = y80 + E;
T = mabr.analysis.SingleTrial.features(X,resp,tAll < 0);
assert(isequal(T.Properties.VariableNames, ...
    {'RMS','P2P','MaxAbs','BaselineRMS','TemplateAmp','TemplateR'}) && height(T) == N, ...
    'features table shape is wrong.');
assert(abs(mean(T.TemplateAmp) - 1) < 1e-12,'mean TemplateAmp is %.15g, not 1.',mean(T.TemplateAmp));
% No response, nothing to scale by: the mean projection is noise around 0
% and dividing by it gave values in the hundreds -- NaN instead.
T0 = mabr.analysis.SingleTrial.features(E,resp,tAll < 0);
assert(all(isnan(T0.TemplateAmp)) && all(isfinite(T0.TemplateR)) && all(isfinite(T0.RMS)), ...
    'TemplateAmp of noise alone is %s, not NaN.',mat2str(T0.TemplateAmp(1:3).',3));
k = 5;
assert(abs(T.RMS(k) - sqrt(mean(X(resp,k).^2))) < 1e-18 && ...
    abs(T.P2P(k) - (max(X(resp,k)) - min(X(resp,k)))) < 1e-18 && ...
    abs(T.MaxAbs(k) - max(abs(X(resp,k)))) < 1e-18,'RMS / P2P / MaxAbs of a sweep are wrong.');
assert(all(isfinite(T.BaselineRMS)) && all(abs(T.TemplateR) <= 1),'baseline RMS / template r invalid.');
Tn = mabr.analysis.SingleTrial.features(X,resp,[]);
assert(all(isnan(Tn.BaselineRMS)),'BaselineRMS must be NaN without baseline rows.');

% blocks: polarity-balanced, leftovers counted
Nb = 70;  polb = (-1).^(0:Nb-1);  polb([10 12 14]) = 1;      % a local excess of +
ord = randperm(g,Nb);                                      % acquisition ranks
Xb = y80 + 3e-6*randn(g,numel(tAll),Nb);
P0 = mabr.analysis.Peaks.pick(tAll,y80,mabr.analysis.Peaks.defaultWaves());
[Tb,Tw] = mabr.analysis.SingleTrial.blocks(Xb,polb,ord,resp,tAll,16,P0);
mem = Tb.Properties.UserData.Members;
for i = 1:height(Tb)
    assert(sum(polb(mem{i}) > 0) == 8 && sum(polb(mem{i}) < 0) == 8, ...
        'block %d is not 8 + / 8 - sweeps.',i);
end
allMem = [mem{:}];
assert(numel(unique(allMem)) == numel(allMem),'a sweep is in two blocks.');
assert(Tb.Properties.UserData.Dropped == Nb - sum(Tb.N) && Tb.Properties.UserData.Dropped > 0, ...
    'Dropped (%d) must count the sweeps left over.',Tb.Properties.UserData.Dropped);
assert(all(diff(Tb.FirstOrder) > 0),'blocks must follow acquisition order.');
assert(height(Tw) == height(Tb)*height(P0) && all(abs(Tw.PeakLatency - ...
    repmat(P0.PeakLatency,height(Tb),1)) <= 0.3 + dtms),'block re-picks left their +-0.3 ms windows.');
[Tb1,~] = mabr.analysis.SingleTrial.blocks(Xb,ones(1,Nb),[],resp,tAll,16);
assert(height(Tb1) == 4 && all(Tb1.N == 16) && Tb1.Properties.UserData.Dropped == 6, ...
    'one-polarity blocks should be 4 x 16 with 6 dropped.');
[TbOne,TwOne] = mabr.analysis.SingleTrial.blocks(Xb(:,1:10),polb(1:10),[],resp,tAll,8,P0);
assert(height(TbOne) == 1 && height(TwOne) == height(P0) && iscolumn(TwOne.Block), ...
    'a single block must still give one Tw row per wave.');

% bootstrap band brackets the mean
[lo,hi] = mabr.analysis.SingleTrial.bootstrapBand(X,pol,[],500,0.05,RandStream('threefry','Seed',8));
[mX,semX] = mabr.analysis.SingleTrial.balancedMean(X,pol,[]);
inside = mean(lo <= mX & mX <= hi);
wRatio = median((hi - lo)./(2*1.96*semX));
assert(inside >= 0.99,'the bootstrap band brackets the mean at only %.1f%% of samples.',100*inside);
assert(wRatio > 0.8 && wRatio < 1.2,'bootstrap band width is %.2f of +-1.96 SEM.',wRatio);

% xcorrUp: a later, quieter response is found at its lag
ks = 3;
yLow = [zeros(ks,1); y80(1:end-ks)];
[r,lagMs,r0] = mabr.analysis.SingleTrial.xcorrUp(yLow,y80,resp,6,dtms);
assert(abs(lagMs - ks*dtms) < 1e-12,'xcorrUp lag %.4f ms, expected %.4f.',lagMs,ks*dtms);
assert(r0 < r && r > 0.99,'xcorrUp: r0 %.3f should be below r %.3f.',r0,r);
% Far lags pair the template's vanishing tails (1e-100 V and below) with a
% wave: the sums of squares of such tails underflowed once and gave r = Inf.
[rF,lagF] = mabr.analysis.SingleTrial.xcorrUp(yLow,y80,resp,100,dtms);
assert(isfinite(rF) && rF <= 1 && abs(lagF - ks*dtms) < 1e-12, ...
    'xcorrUp over 100 lags gave r %g at %.4f ms.',rF,lagF);

% dtwUp. A rigid shift equal to the warp's centre (half the allowance) is a
% straight path: r 1, the lag exactly, no spread.
[r,lagMs,rngMs] = mabr.analysis.SingleTrial.dtwUp(yLow,y80,resp,6,dtms);
assert(abs(r - 1) < 1e-12 && abs(lagMs - ks*dtms) < 1e-12 && rngMs == 0, ...
    'dtwUp on a rigid %d-sample shift: r %.15g, lag %.4f ms, range %.4f ms.',ks,r,lagMs,rngMs);
% The case it exists for: 10 dB down, wave I is 0.15 ms later and wave V 0.30
% ms. One lag lines up one of them; the warp lines up both, with a lag that
% spreads by about their difference.
y70 = mabrtest.SyntheticABR.template(tAll,70,16,truth);
rX = mabr.analysis.SingleTrial.xcorrUp(y70,y80,resp,4,dtms);
[rD,lagD,rngD] = mabr.analysis.SingleTrial.dtwUp(y70,y80,resp,4,dtms);
assert(rD > 0.99 && rX < 0.95 && rngD > 0.1 && rngD <= 4*dtms + 1e-12 && lagD > 0 && lagD < 4*dtms, ...
    'dtwUp 70 vs 80 dB: r %.4f (xcorrUp %.4f), lag %.3f ms, spread %.3f ms.',rD,rX,lagD,rngD);
% One direction, as xcorrUp: a quieter response is never earlier.
yE = [y80(ks+1:end); zeros(ks,1)];
rE = mabr.analysis.SingleTrial.dtwUp(yE,y80,resp,6,dtms);
assert(rE < 0.5,'dtwUp lined up an EARLIER response: r %.3f.',rE);
% No room to warp (an allowance under 2 samples): the lag-0 correlation.
[~,~,r00] = mabr.analysis.SingleTrial.xcorrUp(y70,y80,resp,0,dtms);
assert(isequal(mabr.analysis.SingleTrial.dtwUp(y70,y80,resp,1,dtms),r00), ...
    'dtwUp with no room to warp is not the lag-0 r.');
assert(isnan(mabr.analysis.SingleTrial.dtwUp(NaN(size(y80)),y80,resp,4,dtms)) && ...
    isnan(mabr.analysis.SingleTrial.dtwUp(y70,y80,find(resp,2),4,dtms)),'dtwUp on < 3 rows is not NaN.');
% Noise: the smoothed warp is no more willing to line up two independent
% noise averages than one rigid lag is; unsmoothed it lines most of them up.
gN = RandStream('threefry','Seed',616);
nP = 300;
EN = filtfilt(bb,aa,randn(gN,numel(tAll)+200,2*nP));
EN = EN(101:100+numel(tAll),:);
rN = NaN(nP,3);
for i = 1:nP
    a = EN(:,2*i-1);  b = EN(:,2*i);
    rN(i,1) = mabr.analysis.SingleTrial.xcorrUp(a,b,resp,4,dtms);
    rN(i,2) = mabr.analysis.SingleTrial.dtwUp(a,b,resp,4,dtms);
    rN(i,3) = mabr.analysis.SingleTrial.dtwUp(a,b,resp,4,dtms,0);
end
mN = median(rN);
assert(abs(mN(2) - mN(1)) < 0.05 && mN(3) > 0.4, ...
    'dtwUp on noise: median r %.3f (xcorrUp %.3f, unsmoothed %.3f).',mN(2),mN(1),mN(3));
fprintf(['  PASS Part F: mean TemplateAmp = 1 (NaN on noise alone); %d balanced blocks, %d dropped; band brackets %.1f%%, ' ...
    'width %.2f x 1.96 SEM; xcorrUp lag %d samples, r bounded over 100 lags; dtwUp r %.3f where xcorrUp gives %.3f ' ...
    '(lag spread %.2f ms), noise median %.2f (xcorrUp %.2f, unsmoothed %.2f)\n'], ...
    height(Tb),Tb.Properties.UserData.Dropped,100*inside,wRatio,ks,rD,rX,rngD,mN(2),mN(1),mN(3));

% ---- Part G: picking --------------------------------------------------------
% parabolic refinement: unbiased on Gaussian peaks with sub-sample centres
tg = (0:120)'*dtms;  c0 = tg(50);  sgw = 0.12;
g = RandStream('threefry','Seed',707);
biasUs = zeros(2,11);
snrs = [10 20];
for si = 1:2
    sigN = 10^(-snrs(si)/20);
    d = -0.5:0.1:0.5;
    for di = 1:numel(d)
        c = c0 + d(di)*dtms;
        Y = exp(-(tg - c).^2/(2*sgw^2)) + sigN*randn(g,numel(tg),400);
        lat = mabr.analysis.Peaks.repick(tg,Y,c,0.25,"P");
        biasUs(si,di) = 1000*mean(lat - c);
    end
end
assert(all(abs(biasUs(:)) < 20),'parabolic refinement bias reaches %.1f us.',max(abs(biasUs(:))));
[th,yh] = mabr.analysis.Peaks.refine(tg,exp(-(tg - (c0 + 0.3*dtms)).^2/(2*sgw^2)),50);
assert(abs(th - (c0 + 0.3*dtms)) < 0.005 && yh > 0.99, ...
    'refine of a noiseless Gaussian is %.4f ms off.',th - (c0 + 0.3*dtms));
[thn,yhn] = mabr.analysis.Peaks.refine(tg,tg,[1 NaN]);
assert(thn(1) == tg(1) && yhn(1) == tg(1) && isnan(thn(2)),'refine must not step past a missing neighbour.');

% pick on the template at 80 dB, 16 kHz
W0 = mabr.analysis.Peaks.defaultWaves();
y80 = mabrtest.SyntheticABR.template(tAll,80,16,truth);
Wt  = mabrtest.SyntheticABR.waveTruth(80,16,truth);
Pk  = mabr.analysis.Peaks.pick(tAll,y80,W0);
assert(isequal(Pk.Properties.VariableNames,{'Wave','PeakIdx','PeakLatency','PeakValue', ...
    'Prominence','State','TroughLatency','TroughValue','TroughState'}),'pick table columns are wrong.');
assert(all(Pk.State == "auto") && isequal(Pk.Wave,Wt.Wave),'pick did not pick waves I-V.');
errS = abs(Pk.PeakLatency - Wt.PeakLatency)/dtms;
assert(all(errS <= 1),'pick is %s samples off waveTruth.',mat2str(errS.',2));
assert(all(abs(Pk.TroughLatency - Wt.TroughLatency)/dtms <= 2) && all(Pk.TroughState == "auto"), ...
    'pick troughs are off their truth.');
c = mabr.analysis.Peaks.candidates(tAll,y80,"N");
assert(all(c.Prominence > 0) && all(diff(c.T) >= 0.3 - 1e-9),'candidates must be prominent and 0.3 ms apart.');

% track down a level series to threshold (16 kHz: 40 dB)
levels = 80:-10:40;
g = RandStream('threefry','Seed',808);
Y = zeros(numel(tAll),numel(levels));
for j = 1:numel(levels)
    Y(:,j) = mabrtest.SyntheticABR.template(tAll,levels(j),16,truth) + 0.02e-6*randn(g,numel(tAll),1);
end
W = W0;
% A user's own shifts, 0.003 ms/dB under the truth's slopes, are honoured
% (the defaults are the truth's slopes themselves; Part K tracks with them).
shift = [0.012 0.015 0.017 0.022 0.027];
for w = 1:5, W(w).LatencyShift = shift(w); end
trackOpts = {'CandidateProminence',1e-7};
T0 = mabr.analysis.Peaks.track(tAll,Y,levels,W,trackOpts{:});
assert(height(T0) == numel(levels)*5 && isequal(unique(T0.Level,'stable').',levels), ...
    'track must return every level x wave, loudest first.');
worst = 0;
for j = 1:numel(levels)
    Wt = mabrtest.SyntheticABR.waveTruth(levels(j),16,truth);
    r = T0.Level == levels(j);
    assert(all(T0.State(r) == "auto"),'track lost a wave at %d dB.',levels(j));
    e = abs(T0.PeakLatency(r) - Wt.PeakLatency)/dtms;
    worst = max(worst,max(e));
    assert(all(e <= 2),'track at %d dB is %s samples off (label switch?).',levels(j),mat2str(e.',2));
end

% a manual anchor moves the picks below it, and only below it
lat60IV = latencyOf(mabrtest.SyntheticABR.waveTruth(60,16,truth),"IV");
anc = anchorTable(60,"III","P","manual",lat60IV);
Ta  = mabr.analysis.Peaks.track(tAll,Y,levels,W,trackOpts{:},Anchors=anc);
r60 = rowOf(Ta,60,"III");
assert(Ta.State(r60) == "manual" && Ta.PeakLatency(r60) == lat60IV, ...
    'a manual anchor must replace the pick at its level.');
moved = false;
for L = [50 40]
    moved = moved || abs(Ta.PeakLatency(rowOf(Ta,L,"III")) - T0.PeakLatency(rowOf(T0,L,"III"))) > 2*dtms;
end
assert(moved,'a manual anchor must change the automatic picks below it.');
up = Ta.Level > 60;
assert(isequaln(Ta.PeakLatency(up),T0.PeakLatency(up)),'an anchor must not change louder levels.');

% an absent anchor leaves no pick and does not move prev
anc = anchorTable(60,"II","P","absent",NaN);
Tb2 = mabr.analysis.Peaks.track(tAll,Y,levels,W,trackOpts{:},Anchors=anc);
r60 = rowOf(Tb2,60,"II");
assert(Tb2.State(r60) == "absent" && isnan(Tb2.PeakLatency(r60)),'an absent anchor must leave no pick.');
lat50 = latencyOf(mabrtest.SyntheticABR.waveTruth(50,16,truth),"II");
assert(abs(Tb2.PeakLatency(rowOf(Tb2,50,"II")) - lat50) <= 2*dtms, ...
    ['below an absent level, wave II must be tracked from 70 dB with the 20 dB ' ...
     'latency allowance (prev not moved).']);

% troughs follow a moved peak; a manual trough stays
lat80III = latencyOf(mabrtest.SyntheticABR.waveTruth(80,16,truth),"III");
anc = anchorTable(80,"II","P","manual",lat80III);
Tc = mabr.analysis.Peaks.track(tAll,Y,levels,W,trackOpts{:},Anchors=anc);
r = rowOf(Tc,80,"II");  r0i = rowOf(T0,80,"II");
W80 = mabrtest.SyntheticABR.waveTruth(80,16,truth);
tIII = W80.TroughLatency(W80.Wave == "III");
assert(Tc.TroughLatency(r) > lat80III && abs(Tc.TroughLatency(r) - tIII) <= dtms && ...
    abs(Tc.TroughLatency(r) - T0.TroughLatency(r0i)) > 2*dtms, ...
    'the trough of a moved peak must be re-found after it (%.3f ms).',Tc.TroughLatency(r));
anc = anchorTable(80,"I","N","manual",1.9);
Td = mabr.analysis.Peaks.track(tAll,Y,levels,W,trackOpts{:},Anchors=anc);
r = rowOf(Td,80,"I");
assert(Td.TroughState(r) == "manual" && Td.TroughLatency(r) == 1.9,'a manual trough must stay put.');

% Session.pickPeaks scales the floor by each level's RN, which is NaN at a
% level with one clean sweep: that level is picked with no floor, never an error.
cpN = [1e-7 NaN 1e-7 1e-7 1e-7];  cp0 = cpN;  cp0(2) = 0;
assert(isequaln(mabr.analysis.Peaks.track(tAll,Y,levels,W,CandidateProminence=cpN), ...
    mabr.analysis.Peaks.track(tAll,Y,levels,W,CandidateProminence=cp0)), ...
    'track: a NaN prominence floor must mean no floor at that level.');
assert(isequaln(mabr.analysis.Peaks.pick(tAll,y80,W0,CandidateProminence=NaN), ...
    mabr.analysis.Peaks.pick(tAll,y80,W0)),'pick: a NaN prominence floor must mean no floor.');
try
    mabr.analysis.Peaks.pick(tAll,y80,W0,CandidateProminence=-1);
    error('verify:offlineStats:noError','a negative prominence floor was accepted.');
catch me
    assert(strcmp(me.identifier,'mabr:analysis:Peaks:prominence'), ...
        'a negative prominence floor gave "%s".',me.message);
end
% A NaN level has no place in the series: picked last, it neither tracks
% from nor feeds the finite levels.
TNaN = mabr.analysis.Peaks.track(tAll,Y(:,[1 3 5]),[80 NaN 40],W,trackOpts{:});
Tref = mabr.analysis.Peaks.track(tAll,Y(:,[1 5]),[80 40],W,trackOpts{:});
assert(all(isnan(TNaN.Level(end-4:end))) && isequaln(TNaN(isfinite(TNaN.Level),:),Tref), ...
    'a NaN level must come last and leave the tracking of the finite levels alone.');
fprintf(['  PASS Part G: refine bias <= %.1f us (10/20 dB); pick I-V within 1 sample; track 80-40 dB ' ...
    'within %.1f samples; manual/absent anchors and troughs as documented; NaN floors and levels\n'], ...
    max(abs(biasUs(:))),worst);

% ---- Part H: uncertainty, derived measures, the wave helpers ---------------
g = RandStream('threefry','Seed',909);
N = 128;  pol = (-1).^(0:N-1);
E = filtfilt(bb,aa,randn(g,numel(tAll)+200,N));
E = 2e-6*E(101:100+numel(tAll),:)/std(E(:));
X  = y80 + E;
mX = mabr.analysis.SingleTrial.balancedMean(X,pol,[]);
pk = mabr.analysis.Peaks.pick(tAll,mX,W0);
B1 = mabr.analysis.Peaks.bootstrap(tAll,X,pol,[],pk,B=200,Stream=RandStream('threefry','Seed',11));
B2 = mabr.analysis.Peaks.bootstrap(tAll,X,pol,[],pk,B=200,Stream=RandStream('threefry','Seed',11));
assert(isequaln(B1,B2),'the bootstrap is not reproducible for a seed.');
assert(isequal(B1.Properties.VariableNames,{'Wave','LatencySE','LatencyCILo','LatencyCIHi', ...
    'LatencyBias','AmpPTSE','AmpPTCILo','AmpPTCIHi','AmpPTBias','Unstable','B'}), ...
    'bootstrap table columns are wrong.');
assert(sum(B1.Unstable) <= 1 && all(B1.LatencyCILo <= pk.PeakLatency + dtms) && ...
    all(B1.LatencyCIHi >= pk.PeakLatency - dtms),'bootstrap of a clear response is unstable or off.');
m0  = mabr.analysis.SingleTrial.balancedMean(E,pol,[]);
pk0 = mabr.analysis.Peaks.pick(tAll,m0,W0);
B0  = mabr.analysis.Peaks.bootstrap(tAll,E,pol,[],pk0,B=200,Stream=RandStream('threefry','Seed',12));
assert(sum(B0.Unstable) >= 2,'pure noise should leave picks Unstable (got %d of 5).',sum(B0.Unstable));

V = mabr.analysis.Peaks.singleTrial(tAll,X,pk);
assert(isequal(V.Properties.VariableNames,{'Sweep','Wave','PeakLatency','PValue','PNValue','Proj'}) && ...
    height(V) == N*height(pk) && isequal(V.Sweep(1:5),ones(5,1)) && isequal(V.Wave(1:5),pk.Wave), ...
    'singleTrial table shape is wrong.');
assert(all(isfinite(V.PeakLatency)) && all(isfinite(V.Proj)),'singleTrial left NaNs on a clear response.');
V1 = mabr.analysis.Peaks.singleTrial(tAll,X(:,1),pk);           % one sweep: no leave-one-out mean
B1r = mabr.analysis.Peaks.bootstrap(tAll,X,pol,[],pk,B=1);      % one replicate
assert(height(V1) == height(pk) && all(isnan(V1.Proj)) && height(B1r) == height(pk), ...
    'singleTrial/bootstrap must degrade to NaN rows, not throw, at one sweep / one replicate.');

% derived measures from a tracked series
Pt = T0;
Pt.Key = "Frequency=16|Level=" + string(Pt.Level);
Pt.SeriesKey = repmat("Frequency=16",height(Pt),1);
Pt.AmpPT = Pt.PeakValue - Pt.TroughValue;
Pt.Detectable = true(height(Pt),1);
Pt.BelowThreshold = false(height(Pt),1);
[M,Gs] = mabr.analysis.Peaks.derived(Pt);
for L = levels
    k = "Frequency=16|Level=" + L;
    v = M.Value(M.Key == k & M.Measure == "IPL_I_V");
    want = Pt.PeakLatency(Pt.Level == L & Pt.Wave == "V") - Pt.PeakLatency(Pt.Level == L & Pt.Wave == "I");
    assert(isscalar(v) && abs(v - want) < 1e-12,'IPL_I_V at %d dB is not V - I.',L);
end
assert(any(M.Measure == "LOGRATIO_V_I") && all(M.Unit(startsWith(M.Measure,"IPL_")) == "ms"), ...
    'derived must give LOGRATIO_V_I and IPLs in ms.');
amp = Gs(Gs.Quantity == "AmpPT",:);
assert(height(amp) == 5 && all(amp.Slope > 0) && all(amp.NLevels == 5) && all(amp.Unit == "V/dB"), ...
    'growth slopes must be positive on a growing series.');
latG = Gs(Gs.Quantity == "Latency",:);
assert(all(latG.Slope < 0) && all(latG.Unit == "ms/dB"),'latency must fall with level.');
Pt.BelowThreshold = Pt.Level <= 40;
[M2,G2] = mabr.analysis.Peaks.derived(Pt);
assert(~any(M2.Key == "Frequency=16|Level=40") && all(G2.NLevels == 4), ...
    'AboveThresholdOnly must drop below-threshold picks.');
[~,G3] = mabr.analysis.Peaks.derived(Pt,AboveThresholdOnly=false);
assert(all(G3.NLevels == 5),'AboveThresholdOnly=false must keep every pick.');
Pt = removevars(Pt,"BelowThreshold");
Final = table("Frequency=16",45,"interval",40,50,'VariableNames', ...
    {'SeriesKey','Final','FinalCensored','FinalLo','FinalHi'});
[~,G4] = mabr.analysis.Peaks.derived(Pt,Final=Final);
assert(all(G4.NLevels == 4),'an interval-censored Final must exclude levels at or below FinalLo.');
% Row and level order do not matter (the U2 review's question): the rows
% reversed, and the series written as attenuation (a descending axis, where
% 80 dB SPL is 0 dB attenuation and 40 dB SPL is 40), give the same picks.
[~,G5] = mabr.analysis.Peaks.derived(Pt(end:-1:1,:),Final=Final);
assert(all(G5.NLevels == 4),'belowFromFinal must not depend on row order.');
FinalN = table("Frequency=16",45,"none",'VariableNames',{'SeriesKey','Final','FinalCensored'});
[~,G6] = mabr.analysis.Peaks.derived(Pt(end:-1:1,:),Final=FinalN);
assert(all(G6.NLevels == 4),'A "none" Final at 45 dB must drop only the 40 dB picks.');
Pa = Pt;  Pa.Level = 80 - Pa.Level;
FinalA = table("Frequency=16",35,"interval",30,40,"descending",'VariableNames', ...
    {'SeriesKey','Final','FinalCensored','FinalLo','FinalHi','LevelDirection'});
[~,G7] = mabr.analysis.Peaks.derived(Pa,Final=FinalA);
assert(all(G7.NLevels == 4),'A descending (attenuation) interval Final must drop levels at or above FinalHi.');
FinalA.FinalCensored = "none";
[~,G8] = mabr.analysis.Peaks.derived(Pa,Final=FinalA);
assert(all(G8.NLevels == 4),'A descending "none" Final must drop attenuations above it.');
FinalA.FinalCensored = "left";   % on an attenuation axis: never responded
[~,G9] = mabr.analysis.Peaks.derived(Pa,Final=FinalA);
assert(all(G9.NLevels == 0),'A descending left-censored Final is the no-response case.');

% wavesFor, nameProblem, waveColor, reported, defaultWaves
W8  = mabr.analysis.Peaks.wavesFor(W0,"Tone",8);
W32 = mabr.analysis.Peaks.wavesFor(W0,"Tone",32);
Wc  = mabr.analysis.Peaks.wavesFor(W0,"ClickTrain",NaN);
assert(max(abs([W8.TMin] - [W0.TMin] - 0.15)) < 1e-12 && max(abs([W8.TMax] - [W0.TMax] - 0.15)) < 1e-12 && ...
    max(abs([W8.Expected] - [W0.Expected] - 0.15)) < 1e-12,'one octave below 16 kHz must shift +0.15 ms.');
assert(max(abs([W32.TMin] - [W0.TMin] + 0.15)) < 1e-12,'one octave above 16 kHz must shift -0.15 ms.');
assert(isequal([Wc.TMin],[W0.TMin]),'a click (no frequency) must not shift.');
click = W0(1);  click.Stimulus = "ClickTrain";  click.TMin = 0.8;
Wmix = [W0 click];
Wk = mabr.analysis.Peaks.wavesFor(Wmix,"ClickTrain",NaN);
Wt2 = mabr.analysis.Peaks.wavesFor(Wmix,"Tone",16);
assert(isscalar(Wk) && Wk.TMin == 0.8 && numel(Wt2) == 5, ...
    'stimulus-specific rows must win for their stimulus and only for it.');
used = ["I","II","III","IV","V"];
assert(isempty(mabr.analysis.Peaks.nameProblem("VI",used)) && ...
    isempty(mabr.analysis.Peaks.nameProblem("N1",strings(0,1))),'valid names refused.');
bad = {"", "   ", "12", "ii", " V "};
for i = 1:numel(bad)
    assert(~isempty(mabr.analysis.Peaks.nameProblem(bad{i},used)), ...
        'nameProblem accepted "%s".',bad{i});
end
okabe = [213 94 0; 230 159 0; 0 158 115; 86 180 233; 0 114 178]/255;
assert(isequal(mabr.analysis.Peaks.waveColor(["I" "II" "III" "IV" "V"]),okabe), ...
    'waves I-V must be vermillion, orange, bluish green, sky blue, blue.');
assert(isequal(mabr.analysis.Peaks.waveColor('iii'),okabe(3,:)),'waveColor ignores case.');
other = mabr.analysis.Peaks.waveColor(["VI","VII","A","N1"]);
pal = [204 121 167; 0 0 0]/255;
assert(isequal(other(1:2,:),pal) && all(ismember(other(3:4,:),pal,'rows')), ...
    'VI/VII must be reddish purple/black and any other wave one of the two.');
assert(isequal(mabr.analysis.Peaks.reported([1.5 2.0],0.25),[1.25 1.75]), ...
    'reported must subtract the offset.');
% Each wave its own latency shift, larger for the later waves (13 A8); a wave
% added without one shifts AddedLatencyShift.
assert(isequal(size(W0),[1 5]) && isequal(fieldnames(W0).',{'Name','Enabled','TMin','TMax', ...
    'Expected','LatencyShift','Stimulus'}) && max(abs([W0.Expected] - ([W0.TMin] + [W0.TMax])/2)) < 1e-12 && ...
    all([W0.Enabled]) && isequal([W0.LatencyShift],[0.015 0.018 0.020 0.025 0.030]) && all([W0.Stimulus] == ""), ...
    'defaultWaves is not the five TraceInspector windows with their latency shifts.');
wAdd = mabr.analysis.Peaks.wavesFor(struct('Name',"VI",'TMin',5.5,'TMax',6.5));
assert(wAdd.LatencyShift == mabr.analysis.Peaks.AddedLatencyShift && wAdd.LatencyShift == 0.02, ...
    'a wave without a LatencyShift should get 0.02 ms/dB, got %g.',wAdd.LatencyShift);
fprintf(['  PASS Part H: bootstrap reproducible (noise: %d of 5 Unstable, response %d); ' ...
    'singleTrial %d rows; IPL/LOGRATIO and positive growth slopes; wave helpers\n'], ...
    sum(B0.Unstable),sum(B1.Unstable),height(V));

% ---- Part I: no Statistics toolbox -------------------------------------------
forbidden = ['prctile|quantile|iqr|mad|range|zscore|nanmean|nanstd|nanmedian|corr|' ...
    'fcdf|finv|tcdf|tinv|normcdf|norminv|normpdf|randsample|datasample|bootstrp|' ...
    'fitglm|fitlm|boxplot|ksdensity|grpstats|skewness|kurtosis'];
for f = ["SingleTrial","Peaks"]
    src = fileread(which("mabr.analysis." + f));
    hit = regexp(src,['\<(' forbidden ')\s*\('],'match');
    assert(isempty(hit),'%s.m calls %s.',f,strjoin(unique(hit),', '));
    hit = regexp(src,'\<(range|corr|mad)\s*=','match');
    assert(isempty(hit),'%s.m names a variable after a Statistics function: %s.',f,strjoin(unique(hit),', '));
end
fprintf('  PASS Part I: no Statistics-toolbox identifiers in SingleTrial.m or Peaks.m\n');

% ---- Part J: the contract's shapes ---------------------------------------------
% mabr.analysis.Session.measure, the views and the exports read these names.
g = RandStream('threefry','Seed',1010);
N = 96;  pol = (-1).^(0:N-1);  strata = [ones(1,40) 2*ones(1,56)];
E = filtfilt(bb,aa,randn(g,numel(tAll)+200,N));
X = 0.3*y80 + 2e-6*E(101:100+numel(tAll),:)/std(E(:));
base = tAll < 0;
rng0 = rng;                                             % nothing below may move it
S = mabr.analysis.SingleTrial.summary(X,tAll,pol,strata,Rows=resp,BaselineRows=base, ...
    NumPermutations=200,SplitHalfResamples=60,MinPerPolarity=10, ...
    Stream=RandStream('threefry','Seed',21));
want = {'N','NPos','NNeg','Balanced','Mean','MeanPos','MeanNeg','SEM','PlusMinus','RN','RNPM', ...
    'ResponseRMS','BaselineRMS','F','PowerP','PowerF95','SNR','SNRCorr','Fsp','FspDF1','FspDF2', ...
    'FspP','SplitR','SplitRSD','SplitRP025','SplitRP975','SplitN','Flags'};
assert(isempty(setxor(fieldnames(S),want)),'summary fields differ from 10 s8.11: %s.', ...
    strjoin(setxor(fieldnames(S),want),', '));
[m,sem] = mabr.analysis.SingleTrial.balancedMean(X,pol,strata);
mr = m(resp);  mb = m(base);
assert(abs(S.RN - sqrt(mean(sem(resp).^2))) <= 1e-12*S.RN && ...
    abs(S.ResponseRMS - sqrt(mean((mr - mean(mr)).^2))) <= 1e-12*S.ResponseRMS && ...
    abs(S.F - S.ResponseRMS^2/S.RN^2) <= 1e-12*S.F && abs(S.SNR - 10*log10(S.F)) < 1e-12 && ...
    S.F > 1 && abs(S.SNRCorr - 10*log10(S.F - 1)) < 1e-12 && ...
    abs(S.BaselineRMS - sqrt(mean((mb - mean(mb)).^2))) <= 1e-12*S.BaselineRMS && ...
    abs(S.RNPM - sqrt(mean(S.PlusMinus(resp).^2))) <= 1e-12*S.RNPM && S.N == N && ...
    S.NPos == 48 && S.NNeg == 48 && isequal(size(S.Mean),[numel(tAll) 1]), ...
    'summary RN / ResponseRMS / F / SNR / SNRCorr / BaselineRMS / RNPM break their definitions.');
% One stream, drawn by the +/- reference, then the power test, then the split half.
s  = RandStream('threefry','Seed',21);
q  = mabr.analysis.SingleTrial.plusMinus(X,pol,strata,s);
[~,pp,Fn] = mabr.analysis.SingleTrial.powerTest(X,pol,strata,resp,200,s);
f  = mabr.analysis.SingleTrial.fsp(X,pol,strata,resp);
sh = mabr.analysis.SingleTrial.splitHalf(X,pol,resp,Resamples=60,MinPerPolarity=10,Stream=s);
assert(isequal(q,S.PlusMinus) && pp == S.PowerP && ...
    S.PowerF95 == mabr.analysis.Stats.percentile(Fn,0.95) && ...
    isequal([f.F f.DF1 f.DF2 f.P],[S.Fsp S.FspDF1 S.FspDF2 S.FspP]) && ...
    sh.Mean == S.SplitR && sh.SD == S.SplitRSD && sh.K == S.SplitN && ...
    sh.P025 == S.SplitRP025 && sh.P975 == S.SplitRP975, ...
    'summary does not agree with the functions it is made of, drawn in their documented order.');
assert(isempty(setxor(fieldnames(sh),{'R','Mean','SD','P025','P975','K','N','Mode'})) && ...
    numel(sh.R) == 60 && sh.K == 24 && sh.N == N && sh.Mode == "median", ...
    'splitHalf struct is wrong.');
shSmall = mabr.analysis.SingleTrial.splitHalf(X,pol,resp,K=8,MinPerPolarity=10);
assert(isempty(shSmall.R) && isnan(shSmall.Mean) && isnan(shSmall.SD) && isnan(shSmall.P975) && ...
    shSmall.K == 8,'a K below MinPerPolarity must give no resamples and NaN statistics.');
c = mabr.analysis.Peaks.candidates(tAll,y80,"P");
assert(isequal(c.Properties.VariableNames,{'Idx','T','Y','Prominence'}),'candidates columns are wrong.');
assert(isequal(T0.Properties.VariableNames,{'Level','Wave','PeakIdx','PeakLatency','PeakValue', ...
    'Prominence','State','TroughLatency','TroughValue','TroughState'}),'track columns are wrong.');
assert(isequal(Tb.Properties.VariableNames,{'Block','N','FirstOrder','LastOrder','RN','ResponseRMS'}) && ...
    isequal(Tw.Properties.VariableNames,{'Block','Wave','PeakLatency','AmpPT'}) && ...
    all(isfield(Tb.Properties.UserData,{'Dropped','Members'})),'blocks tables are wrong.');
assert(isequal(M.Properties.VariableNames,{'Key','Measure','Value','Unit'}) && ...
    isequal(Gs.Properties.VariableNames,{'SeriesKey','Wave','Quantity','Slope','Intercept', ...
    'Unit','NLevels','LevelMin','LevelMax'}),'derived tables are wrong.');
% Never the global stream: a subset recompute must be bit-identical.
mabr.analysis.SingleTrial.summary(X,tAll,pol,strata,Rows=resp,NumPermutations=50, ...
    SplitHalfResamples=20,MinPerPolarity=10);
mabr.analysis.SingleTrial.plusMinus(X,pol);
mabr.analysis.SingleTrial.bootstrapBand(X,pol,strata,20);
mabr.analysis.SingleTrial.convergence(X,pol);
mabr.analysis.Peaks.bootstrap(tAll,X,pol,strata,mabr.analysis.Peaks.pick(tAll,m,W0),B=20);
assert(isequal(rng,rng0),'a statistic drew from the global random stream.');
fprintf(['  PASS Part J: summary fields and definitions, its stream order, splitHalf struct, ' ...
    'every table''s columns; the global stream untouched\n']);

% ---- Part K: tracking with the defaults; the next wave's bound; Offset --------
% 13 A8: every wave its own latency shift, and a prior located where the wave
% is EXPECTED one level down (prev + LatencyShift*dL) rather than where it
% was. On the NOISELESS 16 kHz series -- the truth's slopes are 0.015-0.030
% ms/dB, so wave V moves 0.3 ms per 10 dB -- every wave is tracked from 80 dB
% down to threshold within a sample of its truth. Series whose latencies grow
% half and one and a half times as fast keep every label; at 1.5x the hard
% window allows wave V exactly the step it makes, so it may be lost at a
% level -- lost, never relabelled.
thr16  = truth.Threshold(truth.Freqs == 16);
levK   = 80:-10:thr16;
W16    = mabr.analysis.Peaks.wavesFor(W0,"Tone",16);
scales = [1 0.5 1.5];
lostK  = zeros(1,numel(scales));  worstK = 0;
for si = 1:numel(scales)
    tr = truth;
    tr.Waves.LatencySlope = scales(si)*truth.Waves.LatencySlope;
    Yk = zeros(numel(tAll),numel(levK));
    for j = 1:numel(levK), Yk(:,j) = mabrtest.SyntheticABR.template(tAll,levK(j),16,tr); end
    Tk = mabr.analysis.Peaks.track(tAll,Yk,levK,W16);
    [nSwitch,lostK(si),errK] = trackAgainstTruth(Tk,levK,16,tr,dtms);
    assert(nSwitch == 0,'tracking a series with %gx the truth''s latency slopes switched %d labels.', ...
        scales(si),nSwitch);
    assert(all(errK <= 1),'tracking at %gx the truth''s slopes is %.2f samples off the truth.', ...
        scales(si),max(errK));
    assert(scales(si) > 1 || lostK(si) == 0,'tracking at %gx the truth''s slopes lost %d picks.', ...
        scales(si),lostK(si));
    if scales(si) == 1, T1 = Tk;  Y1 = Yk;  worstK = max(errK); end
end
% The other way round -- the truth's slopes, the tracker's shifts half and one
% and a half times the defaults (a user's guess off by as much): no label
% switch either; at half the shifts wave V may be lost, at 1.5x nothing is.
lostS = zeros(1,numel(scales));
for si = 2:numel(scales)
    Ws = W16;
    for w = 1:numel(Ws), Ws(w).LatencyShift = scales(si)*W16(w).LatencyShift; end
    Ts = mabr.analysis.Peaks.track(tAll,Y1,levK,Ws);
    [nSwitch,lostS(si),errS] = trackAgainstTruth(Ts,levK,16,truth,dtms);
    assert(nSwitch == 0 && all(errS <= 1),['tracking with %gx the default latency shifts switched %d ' ...
        'labels (%.2f samples off).'],scales(si),nSwitch,max(errS));
    assert(scales(si) < 1 || lostS(si) == 0,'tracking with %gx the default shifts lost %d picks.', ...
        scales(si),lostS(si));
end

% A wave missed for two levels must not take the next wave's peak. Wave I
% (0.015 ms/dB) stops at 70 dB while wave II carries on unchanged in latency,
% 0.42 ms after wave I's last pick -- the click series in which wave I,
% searched one level down in a window widened by two level steps, took wave
% II's peak and left wave II with nothing. Wave I's window now ends
% MinSeparation before where wave II, picked at 60 dB, is expected.
tL = (0:dtms:10).';
levL = 80:-10:50;
latL = [1.40 + 0.015*(80 - levL); repmat(1.97,1,numel(levL)); 3.0 + 0.02*(80 - levL); ...
    3.9 + 0.025*(80 - levL); 4.8 + 0.03*(80 - levL)];
ampL = repmat([1;1.2;1;1.4;1.1]*1e-6,1,numel(levL));
ampL(1,levL <= 60) = 0;                                  % wave I gone at 60 and 50 dB
YL = zeros(numel(tL),numel(levL));
for j = 1:numel(levL)
    for w = 1:5
        YL(:,j) = YL(:,j) + ampL(w,j)*exp(-(tL - latL(w,j)).^2/(2*0.08^2));
    end
end
TL = mabr.analysis.Peaks.track(tL,YL,levL,W0);
for j = 1:numel(levL)
    for w = 1:5
        r = TL.Level == levL(j) & TL.Wave == W0(w).Name;
        if ampL(w,j) == 0
            assert(TL.State(r) == "none",'wave %s, gone at %d dB, was picked at %.3f ms.', ...
                W0(w).Name,levL(j),TL.PeakLatency(r));
        else
            assert(TL.State(r) == "auto" && abs(TL.PeakLatency(r) - latL(w,j)) <= dtms, ...
                'wave %s at %d dB: %s at %.3f ms, not %.3f (the next wave''s peak taken?).', ...
                W0(w).Name,levL(j),TL.State(r),TL.PeakLatency(r),latL(w,j));
        end
    end
end

% wavesFor's Offset moves a set of windows, for every stimulus; Offset 0
% leaves them bit for bit. (Session gives none: its windows are in the
% recording's time and a conduction delay is only reported -- Part I of
% verify_offline_analyze.)
o  = 0.3;
W8 = mabr.analysis.Peaks.wavesFor(W0,"Tone",8);
Wo = mabr.analysis.Peaks.wavesFor(W0,"Tone",8,Offset=o);
assert(max(abs([Wo.TMin] - [W8.TMin] - o)) < 1e-12 && max(abs([Wo.TMax] - [W8.TMax] - o)) < 1e-12 && ...
    max(abs([Wo.Expected] - [W8.Expected] - o)) < 1e-12 && isequal([Wo.LatencyShift],[W8.LatencyShift]) && ...
    isequal([Wo.Name],[W8.Name]),'wavesFor''s Offset must move TMin, TMax and Expected by the offset, and nothing else.');
Wco = mabr.analysis.Peaks.wavesFor(W0,"ClickTrain",NaN,Offset=o);
assert(max(abs([Wco.TMin] - [W0.TMin] - o)) < 1e-12 && max(abs([Wco.Expected] - [W0.Expected] - o)) < 1e-12, ...
    'a click''s windows must move by the offset too.');
assert(isequal(mabr.analysis.Peaks.wavesFor(W0,"Tone",8,Offset=0),W8) && ...
    isequal(mabr.analysis.Peaks.wavesFor(W0,"ClickTrain",NaN,Offset=0), ...
    mabr.analysis.Peaks.wavesFor(W0,"ClickTrain",NaN)),'Offset 0 must leave every window where it was.');
try
    mabr.analysis.Peaks.wavesFor(W0,"Tone",8,Offset=NaN);
    error('verify:offlineStats:noError','a NaN offset was accepted.');
catch me
    assert(strcmp(me.identifier,'mabr:analysis:Peaks:offset'), ...
        'a NaN offset (an invalid delay setting) gave "%s", not mabr:analysis:Peaks:offset.',me.message);
end
% A series recorded 0.3 ms late tracked in windows moved by that offset gives
% the same waves, 0.3 ms later in the recording's time; reported() puts them
% back on the ear's latencies.
Yd = zeros(numel(tAll),numel(levK));
for j = 1:numel(levK), Yd(:,j) = mabrtest.SyntheticABR.template(tAll - o,levK(j),16,truth); end
Td = mabr.analysis.Peaks.track(tAll,Yd,levK,mabr.analysis.Peaks.wavesFor(W0,"Tone",16,Offset=o));
Te = Td;
Te.PeakLatency = mabr.analysis.Peaks.reported(Td.PeakLatency,o);
[nSwitch,lostD,errD] = trackAgainstTruth(Te,levK,16,truth,dtms);
assert(isequal(Td.Level,T1.Level) && isequal(Td.Wave,T1.Wave) && isequal(Td.State,T1.State) && ...
    nSwitch == 0 && lostD == 0 && all(errD <= 1), ...
    'a series 0.3 ms late, tracked in windows moved by that offset, must give the same waves (%.2f samples off).',max(errD));
assert(all(abs(Td.PeakLatency - T1.PeakLatency - o) <= dtms), ...
    'track must return raw latencies: the late series'' picks should be 0.3 ms after the others.');
fprintf(['  PASS Part K: default tracking of the noiseless 16 kHz series 80-%d dB within %.2f samples of ' ...
    'the truth; no label switch with 0.5x/1.5x the latency slopes or the shifts (of %d picks, %d lost at ' ...
    '1.5x the slopes, %d at 0.5x the shifts); wave I missed for two levels leaves wave II its peak; ' ...
    'wavesFor Offset; a series %.1f ms late tracked in moved ' ...
    'windows gives the same waves (%.2f samples)\n'], ...
    thr16,worstK,numel(levK)*numel(W16),lostK(3),lostS(2),o,max(errD));

% ---- leaks -------------------------------------------------------------------
tm = timerfindall;
tags = strings(0,1);
if ~isempty(tm), tags = string(get(tm,'Tag')); end
assert(~any(startsWith(tags,"MABR_Offline")),'a MABR_Offline timer leaked.');
assert(numel(findall(groot,'Type','figure')) == nFigsBefore,'a figure was left open.');

fprintf('== verify_offline_stats PASSED ==\n');
end

% =============================================================================
function A = anchorTable(level,wave,kind,state,latency)
% One anchor row in the shape mabr.analysis.Peaks.track takes.
A = table(level,string(wave),string(kind),string(state),latency, ...
    'VariableNames',{'Level','Wave','Kind','State','Latency'});
end

function r = rowOf(T,level,wave)
% The row of a track() table for one level and wave.
r = find(T.Level == level & T.Wave == wave,1);
assert(~isempty(r),'no row for %d dB wave %s.',level,wave);
end

function v = latencyOf(W,wave)
% A wave's truth latency from mabrtest.SyntheticABR.waveTruth.
v = W.PeakLatency(W.Wave == wave);
end

function [nSwitch,nLost,err] = trackAgainstTruth(T,levels,freq,truth,dtms)
% A track() table against mabrtest.SyntheticABR.waveTruth: how many picks sit
% nearer another wave's truth than their own (a label switch), how many waves
% found nothing, and each pick's distance from its own truth, in samples.
nSwitch = 0;  nLost = 0;  err = zeros(0,1);
for L = reshape(levels,1,[])
    Wt = mabrtest.SyntheticABR.waveTruth(L,freq,truth);
    for i = reshape(find(T.Level == L),1,[])
        if T.State(i) ~= "auto", nLost = nLost + 1; continue; end
        [~,k] = min(abs(Wt.PeakLatency - T.PeakLatency(i)));
        nSwitch = nSwitch + double(Wt.Wave(k) ~= T.Wave(i));
        err(end+1,1) = abs(T.PeakLatency(i) - Wt.PeakLatency(Wt.Wave == T.Wave(i)))/dtms; %#ok<AGROW>
    end
end
end
