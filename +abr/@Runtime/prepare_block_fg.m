function prepare_block_fg(obj,ABR)
% Daniel Stolzberg (c) 2019

% append dac timing signal
y = ABR.DAC.Data;
y = [y [1; zeros(length(y)-1,1,'like',y)]];

% repeate for numSweeps
y = repmat(y,ABR.numSweeps,1);

% write wav file to disk
audiowrite( ...
    obj.Universal.dacFile, ...
    y, ...
    ABR.DAC.SampleRate, ...
    'BitsPerSample',32, ...
    'Title','ABR Stimulus');

obj.mapCom.Data.CommandToBg = int8(abr.CMD.Prep);