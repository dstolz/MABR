function r = acquire_block(obj)
% Daniel Stolzberg (c) 2019

% Background process

r = 0;

Mcom = obj.mapCom;
Mbuf = obj.mapInputBuffer;


frameLength = obj.Universal.frameLength;

% reset latest input buffer index
Mcom.Data.Index = [1 frameLength];

obj.mapCom.Data.BackgroundState = abr.ACQSTATE.ACQUIRE;

while ~isDone(obj.AFR)

    % pause on command
    while Mcom.Data.CommandToBg == abr.CMD.Pause
        pause(0.01); % don't lock up matlab
    end

    % break on Stop command
    if Mcom.Data.CommandToBg == abr.CMD.Stop, break; end

    % read current frame
    audioOut = obj.AFR();
    
    % play/record current frame
    audioIn = obj.APR(audioOut);
    
    idx = Mcom.Data.Index(2)+1;

    % place recorded data into memmapped input buffer
    k = idx+frameLength-1;

    % wrap to beginning of buffer
    if k > obj.maxinputBufferLength-frameLength
        idx = 1;
        k = frameLength;
    end
    
    Mbuf.Data.InputBuffer(idx:k,:) = audioIn;
   

    % update the latest buffer index
    Mcom.Data.Index = [idx k];
end

obj.mapCom.Data.BackgroundState = abr.ACQSTATE.COMPLETED;
