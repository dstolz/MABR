function obj = prepareSweep(obj)
% initialize and preallocate variables
% 
% Daniel Stolzberg, PhD (c) 2019



if ~ismethod(obj.APR,'isvalid') || ~obj.APR.isvalid
    obj.APR = audioPlayerRecorder;
    obj.APR.Device = obj.audioDevice;
    
    % release(obj.APR);
    
    obj.APR.PlayerChannelMapping = 1;
    % obj.APR.RecorderChannelMapping = 1;
    obj.APR.RecorderChannelMapping = 3; % LOOPBACK TEST ON FIREFACE UCX
    
    obj.APR.SampleRate  = obj.DAC.SampleRate;
    
    
    
    switch class(obj.DAC.Data)
        case {'double','single'}
            obj.APR.BitDepth = '32-bit float';
        case 'int16'
            obj.APR.BitDepth = '16-bit integer';
        case 'int8'
            obj.APR.BitDepth = '8-bit integer';
    end
end
obj.sweepCount = 1;
