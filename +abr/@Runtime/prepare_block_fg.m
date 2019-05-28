function prepare_block_fg(obj,ABR)
% Daniel Stolzberg (c) 2019

ABR.init_timing_signal;

% append dac timing signal
y = [ABR.DAC.Data [1; zeros(ABR.DAC.N-1,1)]];

% repeate for numSweeps
y = repmat(y,ABR.numSweeps,1);

% write wav file to disk
audiowrite( ...
    obj.Universal.dacFile, ...
    y, ...
    ABR.DAC.SampleRate, ...
    'BitsPerSample',32, ...
    'Title','ABR Stimulus');

obj.mapCom.Data.CommandToBg = int8(abr.Cmd.Prep);