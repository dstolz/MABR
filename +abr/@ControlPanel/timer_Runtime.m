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

lastCheckedIdx = bufferHead;


% split signal into downsampled windows
swin = round(app.ABR.DAC.SampleRate.*app.ABR.adcWindow);
swin = swin(1):app.ABR.adcDecimationFactor:swin(2);
samps = app.ABR.ADC.SweepOnsets + swin; % matrix expansion

samps(any(samps>app.Runtime.maxInputBufferLength,2),:) = [];


% organize incoming signal
y = app.Runtime.mapInputBuffer.Data(samps);
if size(y,2) == 1, y = y'; end

% update plots
tvec = 1000 .* swin ./ app.ABR.ADC.SampleRate;
app.abr_live_plot(y,tvec);


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

