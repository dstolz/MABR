function prepare_block_fg(obj,ABR)
% Daniel Stolzberg (c) 2019

ABR.init_timing_signal;


y = ABR.DAC.Data;
% append dac timing signal

% repeat for numSweeps
if ABR.altPolarity
    oy = y;
    y = [y; -y];
    n = floor(ABR.numSweeps/2);
    y = repmat(y,n,1);
    if rem(ABR.numSweeps,2), y = [y; oy]; end
else
    y = repmat(y,ABR.numSweeps,1);
end

timingSignal = [1; zeros(ABR.DAC.N-1,1)];
y = [y repmat(timingSignal,ABR.numSweeps,1)];


% write wav file to disk
audiowrite( ...
    obj.Universal.dacFile, ...
    y, ...
    ABR.DAC.SampleRate, ...
    'BitsPerSample',32, ...
    'Title','ABR Stimulus');

