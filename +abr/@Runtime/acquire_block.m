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
    audioOut = obj.AFR();
    
    % play/record current frame
    [audioIn,nu,no] = obj.APR(audioOut);
    if nu
        fprintf('# Underruns = %d\n',nu)
    end
    
    if no
        fprintf('# Overruns = %d\n',no)
    end
    
    idx = C.Data.BufferIndex(2)+1;

    % place recorded data into memmapped input buffer
    k = idx+frameLength-1;

%     % wrap to beginning of buffer
%     if k > obj.maxInputBufferLength-frameLength
%         idx = 1;
%         k = frameLength;
%     end

    % TESTING WITH FAKE LOOP-BACK AND SIGNAL **********************
    audioIn(:,1) = audioOut(:,1);
    audioIn(:,2) = [1; zeros(frameLength-1,1,'single')];

    M.Data(idx:k) = audioIn(:,1);
    T.Data(idx:k) = audioIn(:,2);

    % update the latest buffer index
    C.Data.BufferIndex = uint32([idx k]);
end

obj.BackgroundState = abr.stateAcq.COMPLETED;
