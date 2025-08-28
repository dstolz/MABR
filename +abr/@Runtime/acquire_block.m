function r = acquire_block(obj)
% ACQUIRE_BLOCK Run background playback/record and fill memmapped buffers.
%
%   r = acquire_block(obj) streams audio frames from obj.AFR (file/stream
%   source), plays & records with obj.APR, and writes the acquired samples
%   into memory-mapped buffers:
%       • obj.mapSignalBuffer.Data  (channel 1 samples)
%       • obj.mapTimingBuffer.Data  (channel 2 samples)
%   The current write window [idx,k] is tracked via
%   obj.mapCom.Data.BufferIndex and wraps to the beginning when the end of
%   the circular buffer is reached.
%
%   Control flow is governed by obj.mapCom.Data.CommandToBg using abr.Cmd:
%       • abr.Cmd.Run    : acquire
%       • abr.Cmd.Pause  : pause in place
%       • otherwise      : stop acquisition loop
%
%   Mode:
%       If obj.Universal.MODE == abr.Cmd.Test, acquisition is simulated by
%       loop-backing the DAC data with tiny added noise; otherwise, actual
%       ADC channels are written.
%
%   States:
%       Sets obj.BackgroundState to abr.stateAcq.ACQUIRE on entry and to
%       abr.stateAcq.COMPLETED on exit.
%
%   Buffering:
%       Frame length is obj.Universal.frameLength. When the next frame
%       would exceed obj.Universal.maxInputBufferLength, indices wrap and a
%       notice is printed via vprintf.
%
%   Output
%       r  – Status code (0 on normal completion).
%
%   Notes
%       • Progress and XRUNs (underruns/overruns) are reported with vprintf.
%       • This function is intended to run as a background process.
% 
% Daniel Stolzberg (c) 2019

% Background process

r = 0;

TESTING = obj.Universal.MODE == abr.Cmd.Test;
vprintf(1,'ACQUISITION MODE: %s',obj.Universal.MODE)

C = obj.mapCom;
M = obj.mapSignalBuffer;
T = obj.mapTimingBuffer;


frameLength = obj.Universal.frameLength;


% reset latest input buffer index
C.Data.BufferIndex = uint32([1; frameLength]);

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
        M.Data(idx:k) = audioDAC(:,1) + randn(frameLength,1)/1e6;
        T.Data(idx:k) = audioDAC(:,2); % loop-back
    else
        M.Data(idx:k) = audioADC(:,1);
        T.Data(idx:k) = audioADC(:,2);
    end

    % update the latest buffer index
    C.Data.BufferIndex = uint32([idx; k]);
end

obj.BackgroundState = abr.stateAcq.COMPLETED;
vprintf(1,'Acquisition complete')