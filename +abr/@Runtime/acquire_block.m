function acquire_block(obj)
% Daniel Stolzberg (c) 2019

% Background process

Mcom = obj.mapCom;
Mbuf = obj.mapInputBuffer;

% reset latest input buffer index
Mcom.LatestIdx = 1;

frameLength = obj.Universal.frameLength;

while ~isDone(obj.AFR) && Mcom.ForegroundState >= 0

    fgstate = Mcom.Data.ForegroundState;

    while fgstate == abr.ACQSTATE.PAUSED
        pause(0.001);
    end

    if fgstate ~= abr.ACQSTATE.ACQUIRE, break; end

    % read current frame
    audioOut = obj.AFR();
    
    % play/record current frame
    audioIn = obj.APR(audioOut);
    
    idx = Mcom.LatestIdx;

    % wrap index to beginning of buffer
    if idx+frameLength > obj.maxinputBufferLength
        idx = 1;
    end


    % place recorded data into memmapped input buffer
    k = idx+frameLength-1;
    Mbuf.Data.InputBuffer(idx:k,:) = audioIn;

        
    % update the latest buffer index
    Mcom.LatestIdx = k;

end


% release objects
release(obj.AFR);
release(obj.APR);

