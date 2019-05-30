function r = acquire_block(obj)
% Daniel Stolzberg (c) 2019

% Background process

r = 0;

C = obj.mapCom;
M = obj.mapInputBuffer;
T = obj.mapTimingBuffer;


frameLength = obj.Universal.frameLength;

% reset latest input buffer index
C.Data.BufferIndex = uint32([1 frameLength]);

obj.BackgroundState = abr.stateAcq.ACQUIRE;

while ~isDone(obj.AFR)

    % pause on command
    while C.Data.CommandToBg == int8(abr.Cmd.Pause)
        pause(0.01); % don't lock up matlab
    end

    % break on Stop command
    if C.Data.CommandToBg ~= int8(abr.Cmd.Run), break; end

    % read current frame
    [audioDAC,eof] = obj.AFR();
    if eof, break; end
    
    % play/record current frame
    [audioADC,nu,no] = obj.APR(audioDAC);
    if nu, vprintf(0,'# Underruns = %d\n',nu); end
    if no, vprintf(0,'# Overruns = %d\n',no);  end
    
    idx = C.Data.BufferIndex(2)+1;

    % place recorded data into memmapped input buffer
    k = idx+frameLength-1;

%     % wrap to beginning of buffer
%     if k > obj.maxInputBufferLength-frameLength
%         idx = 1;
%         k = frameLength;
%     end

    % TESTING WITH FAKE LOOP-BACK AND SIGNAL **********************
    audioADC(:,1) = audioDAC(:,1) + randn(frameLength,1)/10;

    M.Data(idx:k) = audioADC(:,1);
    T.Data(idx:k) = audioADC(:,2);

    % update the latest buffer index
    C.Data.BufferIndex = uint32([idx k]);
end

obj.BackgroundState = abr.stateAcq.COMPLETED;
vprintf(1,'Acqusition complete')