function timer_Runtime(T,event,app)

persistent bufferHead lastCheckedIdx

if isempty(bufferHead), bufferHead = 1; end

% look for updated buffer index
if isequal(app.Runtime.mapCom.Data.BufferIndex(2),bufferHead), return; end

bufferHead = app.Runtime.mapCom.Data.BufferIndex(2);


if isempty(lastCheckedIdx) || lastCheckedIdx > bufferHead, lastCheckedIdx = 1; end



LC = double(lastCheckedIdx);
BH = double(bufferHead);


% find stimulus onsets in timing signal
ind = app.Runtime.mapTimingBuffer.Data(LC:BH-1) > app.Runtime.mapTimingBuffer.Data(LC+1:BH);
ind = ind & app.Runtime.mapTimingBuffer.Data(LC:BH-1) >= 0.5; % threshold


if ~any(ind), return; end

idx = LC + find(ind)-1;




% append new foundly detected sweep timing impulses
app.ABR.ADC.SweepOnsets(app.ABR.ADC.SweepOnsets<1) = []; % move to init
app.ABR.ADC.SweepOnsets = [app.ABR.ADC.SweepOnsets; idx];

nSweeps = length(app.ABR.ADC.SweepOnsets);

lastCheckedIdx = bufferHead;


% split signal into downsampled windows
swin = round(app.ABR.DAC.SampleRate.*app.ABR.adcWindow);
swin = swin(1):app.ABR.adcDecimationFactor:swin(2);
samps = app.ABR.ADC.SweepOnsets + swin; % matrix expansion



% organize incoming signal
data = app.Runtime.mapInputBuffer.Data(samps);
if nSweeps == 1, data = data'; end


if nSweeps > 1
    % compute inter-sweep correlation coefficient
    bsamps = -1:-1:-size(samps,2);
    bsamps = app.ABR.ADC.SweepOnsets + bsamps;
    bsamps(any(bsamps < 1,2),:) = [];
    
    pre = app.Runtime.mapInputBuffer.Data(bsamps);
    
    
    % TESTING ***********
    post = abs(data);
    % TESTING ***********
    
    n = size(pre,1);
    m = round(n/2);
    i = randperm(n);
    preMean1  = mean(pre(i(1:m),:))';
    preMean2  = mean(pre((i(m+1:end)),:))';
    postMean1 = mean(post(i(1:m),:))';
    postMean2 = mean(post(i(m+1:end),:))';
    
    X = [preMean1 preMean2 postMean1 postMean2];
    
    
    % compute auto and cross correlation between pre and post stimulus
    R = corrcoef(X);
    
    
    R(1:length(R)+1:end) = nan;
    
    Rpre   = R(2,1); 
    Rcross = mean(R(sub2ind([4 4],[3 3 4 4],[1 2 1 2])));
    Rpost  = R(4,3);
        
    R = abs([Rpre Rcross Rpost]);
else
    R = [0 0 0];
end

% update plots
tvec = 1000 .* swin ./ app.ABR.ADC.SampleRate;
app.abr_live_plot(data,tvec,R);

% update GUI
app.ControlSweepCountGauge.Value = length(app.ABR.ADC.SweepOnsets);

drawnow limitrate


% make sure the background process is still running
if ~app.Runtime.BgIsRunning
    app.stateProgram = abr.stateProgram.ACQ_ERROR;
    app.StateMachine;
    stop(app.Runtime.mapTimingBuffer);
end


% check status of recording
switch app.Runtime.BackgroundState
    case abr.stateAcq.COMPLETED
        app.stateProgram = abr.stateProgram.BLOCK_COMPLETE;
        app.StateMachine;
%         stop(app.Timer);
        
    case abr.stateAcq.ERROR
        app.stateProgram = abr.stateProgram.ACQ_ERROR;
        app.StateMachine;
        stop(app.Timer);
end

