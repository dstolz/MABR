%%
fs = 44100;
freq = 1000;
t = 0:1/fs:2/freq-1/fs;
y = sin(2*pi*freq*t);

audiowrite('TEST.wav',y,fs);

%%
A = ABR('TEST.wav','ASIO4ALL v2');

%%

f = findobj('type','figure','-and','name','TEST');
if isempty(f), f = figure('name','TEST'); end
clf(f);
ax = axes(f);
grid(ax,'on');

A.frameLength = 256;
A.numSweeps = 128;
A.sweepRate = 21.1; % 

hl = line(ax,'xdata',A.adcBufferTimeVector,'ydata',nan(A.adcBufferLength,1));

% important to set manual limits on axes
ax.YLim = [-5 5]*10^-2;
ax.XLim = A.dacBufferTimeVector([1 end]);

drawnow

A.prepareSweep;
tic
for i = 1:A.numSweeps
    A.triggerSweep;
    if mod(i,4) == 0
        hl.YData = mean(A.adcDataFiltered(:,1:i),2);
        ax.Title.String = sprintf('Sweep %d/%d',i,A.numSweeps);
        drawnow limitrate
    end
end
toc

%
d = diff(A.sweepOnsets);
fprintf('1/sweepRate\t%0.9f\nmedian\t\t%0.9f\nmean\t\t%0.9f\nstd\t\t\t%0.9f\n', ...
    1/A.sweepRate,median(d),mean(d),std(d))


