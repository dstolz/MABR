function prepare_block_fg(obj,sweep,Fs,nReps,sweepRate,altPolarity)
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


timingSignal = [1; zeros(r-1,1)];
y = [y repmat(timingSignal,nReps,1)];

% make sure output signal length is a multiple of frame length
fl = obj.Universal.frameLength;
r = rem(length(y),fl);
if r > 0, y(end+fl-r,2) = 0; end

% pad onset/offset with some silence
y = [zeros(Fs,2); y; zeros(Fs,2)];

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

