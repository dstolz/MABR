%% Calibration pipeline

%% 1. Collect impulse response and export data

% impulseResponseMeasurer;

Fs = 44100;
T = 10;
f1 = 20;
f2 = 20000;
[sweep, invsweepfft, sweepRate] = synthSweep(T,Fs,f1,f2); 

A = abr.ABR;
A.dacFs = Fs;
A.adcFs = Fs;
A.audioDevice = 'ASIO4ALL v2';
A.dacBuffer = sweep;
A.numSweeps = 1;
A.adcUseBPFilter = 0;
A.adcUseNotchFilter = 0;
A.playrec;

sweep_response = A.adcSweepData;
[irLin, irNonLin] = extractIR(sweep_response, invsweepfft);


%% 2. Create arb. mag. filter

load('TEST_FILES\measured_ir_data.mat','measurementData');

MR = measurementData.MagnitudeResponse;
Fs = measurementData.SampleRate;


f = findobj('type','figure','-and','name','IR');
if isempty(f), f = figure('name','IR','color','w'); end
figure(f);
clf(f);


maxFreq = Fs/2;
idx = 1:find(MR.Frequency<=maxFreq,1,'last');
F = MR.Frequency(idx);
mv = mean(MR.PowerDb(idx));

% Invert and make positive the transfer function, A
A = MR.PowerDb(idx);


% normalize Amplitudes
medA = median(A);
mA = max(A);
rA = max(A) - min(A);
nA = A./rA*mA;
nA = nA - median(nA);
nA = nA + abs(min(nA));
nA = nA./max(nA);


% arbmagfir Frequencies must contain [0 Fs/2]
arbF = linspace(0,Fs/2,length(A));
 
filtOrder = 250;

calFilt = designfilt('arbmagfir', ...
    'FilterOrder',filtOrder, ...
    'Frequencies',arbF, ...
    'Amplitudes', nA, ...
    'SampleRate', Fs);

[h,w] = freqz(calFilt,F,Fs);
[b,a] = invfreqz(h,w,'complex',filtOrder,0);

ax = subplot(4,4,[1 8],'parent',f);
plot(ax,F./1000,A,'linewidth',2)
hold(ax,'on');
plot(ax,F./1000,20*log10(abs(h)),'linewidth',2);
set(ax,'xscale','log');
axis(ax,'tight');
plot(ax,xlim(ax),[1 1]*mv,'--','linewidth',2);
grid(ax,'on');
hold(ax,'off');
ylabel(ax,'Magnitude (dB)');
xlabel(ax,'Frequency (kHz)');
legend(ax,'Impulse Response','Filter','location','best');

if ~calFilt.isstable
    title(ax,'WARNING: Filter not stable!');
end

ax = subplot(4,4,[11 16],'parent',f);
zplane(b,a,ax);


%% 3. Filter signal to flatten response

ry = measurementData.RawAudioData.RecordedSignal;
ry = mean(ry,3);
y = measurementData.RawAudioData.ExcitationSignal;

ind = y==0;
y(ind) = [];
ry(ind) = [];


n = length(y);
t = 0:1/Fs:n/Fs-1/Fs;

% acausal filter
% replicate signal to minimize onset/offset transient distortions
fy = filtfilt(calFilt,[ry ry ry]);



fy = fy(n+1:end-n);



f = findobj('type','figure','-and','name','Filter Test');
if isempty(f), f = figure('name','Filter Test'); end
clf(f);
figure(f);

subplot(321,'parent',f);
plot(t,y,'-b');
grid on
ylabel('excitation signal');

subplot(322,'parent',f);
spectrogram(y,128,64,2^11,Fs,'yaxis');
% colorbar off

subplot(323,'parent',f);
plot(t,ry,'-b');
grid on
ylabel('recorded signal');

subplot(324,'parent',f);
spectrogram(ry,128,64,2^11,Fs,'yaxis');
% colorbar off

subplot(325,'parent',f);
plot(t,fy,'-r');
grid on
ylabel('flattened signal');
xlabel('Time (secs)');

subplot(326,'parent',f);
spectrogram(fy,128,64,2^11,Fs,'yaxis');
% colorbar off

ax = findobj(f,'type','axes');
set(ax,'xlim',t([1 end]));

linkaxes(ax,'x');

%% 4. Play filtered tones to test sound level


f1 = 500; % Hz
f2 = 20000; % Hz
octSpacing = 1/4; % ocataves between tones

toneDuration = 0.01; % sec
riseFallTime = 0.0025; % sec

f2o = log2(f2)-log2(f1);
freqs = f1.*2.^(0:octSpacing:f2o);
freqs = freqs';

% generate tones
s = max(measurementData.RawAudioData.ExcitationSignal);
t  = 0:1/Fs:toneDuration-1/Fs;
rt = 0:1/Fs:10*toneDuration-1/Fs;
nf = length(freqs);
nt = round(Fs*toneDuration);
tones = s.*sin(2*pi*freqs*rt)';
% tones = repmat(tones,10,1); % length of signal must be > 3000 pts
tones = filtfilt(calFilt,tones);
tones = tones(nt*4+1:nt*5,:);
% filtfilt =>  filter transfer function is equal to the squared magnitude of the original filter transfer function.
nind = tones < 0;
tones = sqrt(abs(tones)); 
tones(nind) = -tones(nind);

% gate
ng = round(riseFallTime*Fs);
if rem(ng,2)~=0,ng = ng + 1; end
g = window(@blackmanharris,ng)';
ridx = 1:ng/2; fidx = ng/2+1:ng;
g = [g(ridx) ones(1,nt-ng) g(fidx)]';
g = repmat(g,1,length(freqs));
tones = tones.*g;
ngidx = ng/2+1:nt-nt/2-1;

f = findobj('type','figure','-and','name','Tone Test');
if isempty(f), f = figure('name','Tone Test','color','w'); end
clf(f);
figure(f);

if ~exist('A','var') || ~isa(A,'abr.ABR')
    A = abr.ABR;
end
A.audioDevice = 'ASIO4ALL v2';
A.dacFs = Fs;
A.adcFs = Fs;
A.sweepRate = 2;
A.numSweeps = 1;
A.adcUseBPFilter = false;
A.adcUseNotchFilter = false;
for i = 1:length(freqs)
    
    % play/record y
    A.dacBuffer = tones(:,i);

    A.playrec([],ax,'showstimulusplot',false);
        
    ax = subplot(311);
    plot(ax,t,tones(:,i),'-','linewidth',2);
    grid(ax,'on');
    xlim(ax,[0 toneDuration]);
    ylim(ax,[-.5 .5]);
    ylabel(ax,'Amplitude');
    title(ax,'Stimulus');
    
    ax = subplot(312);
    plot(ax,0:1/Fs:size(A.adcSweepData,1)/Fs-1/Fs,A.adcSweepData,'-', ...
        'linewidth',2,'color',[0.85 0.325 0.098]);
    grid(ax,'on');
    xlim(ax,[0 toneDuration]);
    ylim(ax,[-.5 .5]);
    xlabel('time (sec)');
    ylabel('Amplitude');
    title(ax,'Response');
    
    ax = subplot(313);
    
    L = length(ngidx);
    w = window(@hanning,length(ngidx));
    Y = fft(tones(ngidx,i).*w);
    P2 = abs(Y/L);
    P1stim = P2(1:floor(L/2)+1);
    P1stim(2:end-1) = 2*P1stim(2:end-1);
    
    
    L = length(ngidx);
    f = Fs*(0:(L/2))/L;
    w = window(@hanning,length(ngidx));
    Y = fft(A.adcSweepData(ngidx).*w);
    P2 = abs(Y/L);
    P1resp = P2(1:floor(L/2)+1);
    P1resp(2:end-1) = 2*P1resp(2:end-1);
    plot(ax,1000*f,db(P1stim),'-', ...
        1000*f,db(P1resp),'-','linewidth',2);
    xlim(ax,1000*f([1 end]));
    xlabel(ax,'Frequency (kHz)')
    ylabel(ax,'Magnitude (dB)')
    title(ax,'FFT(Response)');
    grid(ax,'on');
    
    drawnow
end

%% 5. Save filter

save('TEST_FILES\TESTCAL.cal','calFilt','measurementData');


