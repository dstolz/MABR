function prepare_block_bg(obj)
% Daniel Stolzberg (c) 2019

% Background process

if ~isempty(obj.AFR) && isvalid(obj.AFR), release(obj.AFR); end
if ~isempty(obj.APR) && isvalid(obj.APR), release(obj.APR); end
    

% setup wav file reader object
obj.AFR = dsp.AudioFileReader( ...
    'Filename',obj.Universal.dacFile, ...
    'SamplesPerFrame',abr.Universal.frameLength, ...
    'OutputDataType','single', ...
    'PlayCount',1);


% setup audioplayerrecorder object
obj.APR = audioPlayerRecorder( ...
    'SampleRate',obj.AFR.SampleRate, ...
    'PlayerChannelMapping',  [obj.infoData.DACsignalCh obj.infoData.DACtimingCh], ...
    'RecorderChannelMapping',[obj.infoData.ADCsignalCh obj.infoData.ADCtimingCh]);


obj.mapCom.Data.BufferIndex = uint32([1 2]);