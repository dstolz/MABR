function timer_Runtime(T,event,app)

persistent bufferHead lastBufferIdx

if isempty(bufferHead), bufferHead = 1; end




% look for updated buffer index
if app.Runtime.mapCom.Data.BufferIndex(2) == bufferHead, return; end

bufferHead = app.Runtime.mapCom.Data.BufferIndex(2);


if isempty(lastBufferIdx) || lastBufferIdx > bufferHead, lastBufferIdx = 1; end


LB = double(lastBufferIdx);
BH = double(bufferHead);


mTB = app.Runtime.mapTimingBuffer;

% find stimulus onsets in timing signal
ind = mTB.Data(LB:BH-1) > mTB.Data(LB+1:BH); % rising edge
ind = ind & mTB.Data(LB:BH-1) >= 0.5; % threshold

if ~any(ind), return; end % no new post

idx = LB + find(ind);

% append newly found detected sweep timing impulses
app.ABR.ADC.SweepOnsets = [app.ABR.ADC.SweepOnsets; idx];



% split signal into resampled windows
swin  = round(app.ABR.DAC.SampleRate.*app.ABR.adcWindow);
swin  = swin(1):app.ABR.adcDecimationFactor:swin(2);
samps = app.ABR.ADC.SweepOnsets + swin; % matrix expansion

% make sure we do not exceed buffer head position
samps(any(samps<1,2) | any(samps>bufferHead,2),:) = []; 

if isempty(samps), return; end


% organize incoming signal
data = app.Runtime.mapInputBuffer.Data(samps);
if app.ABR.sweepCount == 1, data = data'; end


% Compute Pearson's correlation in a similar fashion to Arnold et al, 1985
% Arnold, S.A., et al (1985). Objective versus visual detection of the
% auditory brain stem response. Ear and Hearing, 6(3), 144–150.
if app.ABR.sweepCount > 1
    % extract signal preceding sweep onsets
    bsamps = -1:-1:-size(samps,2);
    bsamps = app.ABR.ADC.SweepOnsets + bsamps;
    bsamps(any(bsamps < 1,2) | any(bsamps>bufferHead,2),:) = [];

    
    pre = app.Runtime.mapInputBuffer.Data(bsamps);
    
    
    % TESTING ***********
    post = abs(data);
    % TESTING ***********
    
    
    % partition the sweeps into two random subsamples
    n = min([size(pre,1) size(post,1)]);
    m = round(n/2);
    i = randperm(n);
    
    preMean1  = mean(pre(i(1:m),:))';
    preMean2  = mean(pre((i(m+1:end)),:))';
    postMean1 = mean(post(i(1:m),:))';
    postMean2 = mean(post(i(m+1:end),:))';
        
    % compute auto and cross correlation between pre and post stimulus means
    R = corrcoef([preMean1 preMean2 postMean1 postMean2]);
        
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


% update this last
lastBufferIdx = bufferHead;


% make sure the background process is still running
if ~app.Runtime.BgIsRunning
    app.stateProgram = abr.stateProgram.ACQ_ERROR;
    app.StateMachine;
    stop(T);
end


% check status of recording
switch app.Runtime.BackgroundState
    case abr.stateAcq.COMPLETED
        app.stateProgram = abr.stateProgram.BLOCK_COMPLETE;
        app.StateMachine;
        
    case abr.stateAcq.ERROR
        app.stateProgram = abr.stateProgram.ACQ_ERROR;
        app.StateMachine;
        stop(T);
end

