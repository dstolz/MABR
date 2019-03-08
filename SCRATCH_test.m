%%
asiosettings
%%
fs = 44100;
freq = 2000;
t = 0:1/fs:2/freq-1/fs;
y = sin(2*pi*freq*t);

audiowrite('TEST2.wav',y,fs);

%%
A = ABR('TEST.wav','ASIO4ALL v2');

%%

addpath('C:\Users\Daniel\Google Drive\CONSULTING\CLIENTS\Schneider_David\ABR\src\ABRControlPanel_fcns')

f = findobj('type','figure','-and','name','TEST');
if isempty(f), f = figure('name','TEST','color','w'); end
clf(f);
ax = axes(f);
grid(ax,'on');
box(ax,'on');
ax.XAxis.Label.String = 'time (ms)';
ax.YAxis.Label.String = 'amplitude (mV)';

A.frameLength = 512;
A.numSweeps = 128;
A.sweepRate = 21.1;

abrAcquireBatch(A,ax,'showTimingStats',true);
