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


% write wav file to disk
audiowrite( ...
    obj.Universal.dacFile, ...
    y,Fs, ...
    'BitsPerSample',32, ...
    'Title','ABR Stimulus');

