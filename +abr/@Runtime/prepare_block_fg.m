function prepare_block_fg(obj,sweep,Fs,nReps,sweepRate,altPolarity)
% PREPARE_BLOCK_FG Build and save a 2-channel stimulus block with timing pulses.
%
%   prepare_block_fg(obj, sweep, Fs, nReps, sweepRate, altPolarity)
%   zero-pads a single sweep to the sweep period (round(Fs/sweepRate)),
%   repeats it nReps times (optionally alternating polarity), and writes a
%   2-channel WAV file to obj.Universal.dacFile. Channel 1 contains the
%   stimulus; Channel 2 contains a per-sweep timing pulse (one sample at 1
%   followed by r−1 zeros). The signal is padded with leading and trailing
%   silence (Fs samples each) and extended to a multiple of
%   obj.Universal.frameLength.
%
% Inputs
%   obj           Object with fields:
%                   • Universal.dacFile (char/string): output WAV path
%                   • Universal.frameLength (positive integer): frame size
%   sweep         Column vector stimulus samples.
%   Fs            Positive scalar, sample rate in Hz.
%   nReps         Positive integer, number of sweep repetitions.
%   sweepRate     Positive scalar, sweeps per second (Hz).
%   altPolarity   Logical; if true, alternate sweep polarity (+/−).
%
% Output
%   (none)        Writes single-precision, uncompressed WAV to disk at
%                 obj.Universal.dacFile.
%
% Details
%   • r = round(Fs/sweepRate) defines the sweep period in samples.
%   • Channel layout: [stimulus, timingPulse].
%   • File written via dsp.AudioFileWriter (DSP System Toolbox).
%
% Example
%   % Build a chirp sweep and write 200 alternating-polarity repetitions at 20 Hz
%   Fs = 97656; t = (0:round(Fs*0.04)-1)'/Fs;                % ~40 ms sweep
%   sweep = chirp(t,2e3,t(end),16e3);
%   prepare_block_fg(abr, sweep, Fs, 200, 20, true)
% 
% Daniel Stolzberg (c) 2019


r = round(Fs/sweepRate);

y = [sweep(:); zeros(r-length(sweep),1,'like',sweep)];

% repeat for numSweeps
if altPolarity
    oy = y;
    y = [y; -y];
    n = floor(nReps/2);
    y = repmat(y,n,1);
    if rem(nReps,2), y = [y; oy]; end
else
    y = repmat(y,nReps,1);
end

% add timing signal to secound output channel
timingSignal = [1; zeros(r-1,1)];
y = [y repmat(timingSignal,nReps,1)];

% make sure output signal length is a multiple of frame length
fl = obj.Universal.frameLength;
r = rem(length(y),fl);
if r > 0, y(end+fl-r,2) = 0; end

% pad onset/offset with some silence
y = [zeros(Fs,2); y; zeros(Fs,2)];

% should be ok due to background process wrapping buffer
% if size(y,1) > obj.Universal.maxInputBufferLength
%     error('abr:Runtime:prepare_block_fg','Stimulus too long, increase abr.Universal.maxInputBufferLength');
% end

% write wav file to disk
afw = dsp.AudioFileWriter( ...
    obj.Universal.dacFile, ...
    'FileFormat','WAV', ...
    'SampleRate',Fs, ...
    'Compressor','None (uncompressed)', ...
    'DataType','Single');
afw(y);
release(afw);
delete(afw);

