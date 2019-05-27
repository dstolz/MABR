function r = acquire_block(obj)
% Daniel Stolzberg (c) 2019

% Background process

r = 0;

C = obj.mapCom;
B = obj.mapInputBuffer;


frameLength = obj.Universal.frameLength;

% reset latest input buffer index
C.Data.BufferIndex = uint32([1 frameLength]);

C.Data.BackgroundState = int8(abr.ACQSTATE.ACQUIRE);

while ~isDone(obj.AFR)

    % pause on command
    while C.Data.CommandToBg == int8(abr.CMD.Pause)
        pause(0.01); % don't lock up matlab
    end

    % break on Stop command
    if C.Data.CommandToBg == int8(abr.CMD.Stop), break; end

    % read current frame
    audioOut = obj.AFR();
    
    % play/record current frame
    audioIn = obj.APR(audioOut);
    
    idx = C.Data.BufferIndex(2)+1;

    % place recorded data into memmapped input buffer
    k = idx+frameLength-1;

    % wrap to beginning of buffer
    if k > obj.maxInputBufferLength-frameLength
        idx = 1;
        k = frameLength;
    end
    
    B.Data.InputBuffer(idx:k,:) = audioIn;
   

    % update the latest buffer index
    C.Data.BufferIndex = uint32([idx k]);
end

obj.mapCom.Data.BackgroundState = int8(abr.ACQSTATE.COMPLETED);
