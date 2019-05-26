function acquire_block(obj)
% background process

Mcom = obj.mapCom;
Mbuf = obj.mapInputBuffer;

frameLength = obj.Universal.frameLength;

while ~isDone(obj.AFR) && Mcom.ForegroundState > -1


    % read current frame
    audioToPlay = obj.AFR();
    
    % play/record current frame
    audioRecorded = obj.APR(audioToPlay);
    
    % place recorded data into memmapped input buffer
    i = Mcom.LatestIdx;
    Mbuf.Data.InputBuffer(i:i+frameLength-1,:) = audioRecorded;

end
