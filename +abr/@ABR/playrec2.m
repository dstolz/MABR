function playrec2(ABR,app,livePlotAx,liveAnalysisAx,varargin)

global ACQSTATE


Fs = ABR.DAC.SampleRate;

% write wav file to disk
audiowrite( ...
    ABR.DACfilename, ...
    ABR.DAC.Data,Fs, ...
    'BitsPerSample',32, ...
    'Title','ABR Stimulus')


% setup wav file reader object
AFR = dsp.AudioFileReader( ...
    'Filename',ABR.DACfilename, ...
    'SamplesPerFrame',abr.Universal.frameLength, ...
    'PlayCount',1);


% setup wav file reader object
AFRadc = dsp.AudioFileReader( ...
    'Filename',ABR.ADCfilename, ...
    'SamplesPerFrame',abr.Universal.frameLength);


% setup data writer object
AFW = dsp.AudioFileWriter( ...
    'Filename',ABR.ADCfilename, ...
    'SampleRate',Fs);


% setup audioplayerrecorder object
APR = audioPlayerRecorder( ...
    'SampleRate',Fs, ...
    'PlayerChannelMapping',  [ABR.DACsignalCh ABR.DACtimingCh], ...
    'RecorderChannelMapping',[ABR.ADCsignalCh ABR.ADCtimingCh]);





H = setup_plot;


lastRead = 1;

updateTime = hat;
while ~isDone(AFR)
    
    % look for change in acquisition state
    while ACQSTATE == abr.ACQSTATE.PAUSED && ~isempty(app)
        app.AcquisitionStateLamp.Color = [1 1 .3];
        pause(0.25);
        app.AcquisitionStateLamp.Color = [.7 .7 0];
        pause(0.25);
    end
    
    if ACQSTATE ~= abr.ACQSTATE.ACQUIRE, break; end
    
    
    % read current frame
    audioToPlay = AFR();
    
    % play/record current frame
    audioRecorded = APR(audioToPlay);
    
    % write current frame
    AFW(audioRecorded);
    
    
    % update plot only every 100 ms or so
    if hat >= updateTime + 0.1 % seconds
        
        % read recent data
        AFRadc.ReadRange = [lastRead inf];
        ADC = AFRadc();
        
        % find loop-back signal
        ADCloopback = ADC(:,1);
        ind = ADCloopback(1:end-1) > ADCloopback(2:end);
        ind = ind & ADCloopback(1:end-1) >= 0.5; % threshold
        TimingIdx = lastRead + find(ind)-1;

        % parse signal by loop-back timing index
        
        
        lastRead = lastRead + size(ADC,1) + 1;
        
        ADCsignal   = ADC(:,2);
        
        update_plot;
        updateTime = hat;
        app.ControlSweepCountGauge.Value = ABR.sweepCount;
        drawnow limitrate
    end
end


% release objects
release(AFR);
release(AFW);
release(APR);

end

function H = setup_plot
ax = livePlotAx;
cla(ax);
grid(ax,'on');
box(ax,'on');

y = nan(size(tvec));

H.mean   = line(ax,tvec,y,'linestyle','-','linewidth',2,'color',[0 0 0]);
H.recent = line(ax,tvec,y,'linestyle','-','linewidth',1,'color',[0.4 0.4 0.4]);

drawnow
end

function update_plot



end

