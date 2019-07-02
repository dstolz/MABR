function r = acquire_block(obj)
% Daniel Stolzberg (c) 2019

% Background process

r = 0;

TESTING = isequal(obj.Universal.MODE,'testing');
vprintf(1,'MODE: %s',obj.Universal.MODE)

C = obj.mapCom;
M = obj.mapSignalBuffer;
T = obj.mapTimingBuffer;


frameLength = obj.Universal.frameLength;


% reset latest input buffer index
C.Data.BufferIndex = uint32([1 frameLength]);

obj.BackgroundState = abr.stateAcq.ACQUIRE;

vprintf(1,'Beginning playback/acquisition')
while ~isDone(obj.AFR)

    % pause on command
    if C.Data.CommandToBg == int8(abr.Cmd.Pause)
        vprintf(4,'Received Pause command')
        pause(0.01); % don't lock up matlab
        continue
    end

    % break on Stop command
    if C.Data.CommandToBg ~= int8(abr.Cmd.Run), break; end

    % read current frame
    [audioDAC,eof] = obj.AFR();
    if eof, vprintf(4,'Reached end of file'), break; end
    
    % play/record current frame
    [audioADC,nu,no] = obj.APR(audioDAC);
    if nu, vprintf(0,'# Underruns = %d',nu); end
    if no, vprintf(0,'# Overruns = %d',no);  end
    
    idx = C.Data.BufferIndex(2)+1;

    % place recorded data into memmapped input buffer
    k = idx+frameLength-1;

    % wrap to beginning of buffer
    if k > obj.Universal.maxInputBufferLength-frameLength
        vprintf(1,'Reached end of buffer!  Wrapping to beginning.')
        idx = 1;
        k = frameLength;
    end

    if TESTING
        % TESTING WITH FAKE LOOP-BACK AND SIGNAL **********************
        M.Data(idx:k) = audioDAC(:,1) + randn(frameLength,1)/1000;
        T.Data(idx:k) = audioDAC(:,2); % loop-back
    else
        M.Data(idx:k) = audioADC(:,1);
        T.Data(idx:k) = audioADC(:,2);
    end

    % update the latest buffer index
    C.Data.BufferIndex = uint32([idx k]);
end

obj.BackgroundState = abr.stateAcq.COMPLETED;
vprintf(1,'Acqusition complete')