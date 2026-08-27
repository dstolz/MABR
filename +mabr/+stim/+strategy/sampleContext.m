function ctx = sampleContext()
% mabr.stim.strategy.sampleContext  A representative context struct, for
% testing a strategy against the contract without building a stimulus bank.
%
%   ctx = mabr.stim.strategy.sampleContext() returns the same shape of struct
%   mabr.stim.strategy.context builds from a real mabr.stim.Schedule, filled
%   with a small but non-degenerate design: a 2 x 3 Frequency x Level bank
%   (8 and 16 kHz at 30, 60 and 90 dB) with UNEQUAL repetition counts and one
%   entry flagged alternatePolarity.
%
%   Every choice here is deliberately awkward, because a sample design that
%   is too tidy validates strategies that would fail on a real one:
%
%     unequal repetitions  the commonest bug in a hand-written cycle is
%                          assuming every entry is owed the same count and
%                          silently dropping the remainder of the others.
%     two parameters       so a strategy that groups by one and orders by the
%                          other is exercised on both.
%     one alternating      so polarity assignment is exercised on an entry
%                          that alternates AND one that does not.
%
%   It is what mabr.stim.strategy.validate calls, and what a test or a
%   strategy under development can call to try itself out at the command line:
%
%       ctx  = mabr.stim.strategy.sampleContext();
%       runs = my_strategy(ctx)
%
%   See also mabr.stim.strategy.context, mabr.stim.strategy.validate.
%
% Daniel Stolzberg (c) 2019-2026

freq  = [8 8 8 16 16 16];       % kHz
level = [30 60 90 30 60 90];    % dB
n     = numel(freq);

ids = arrayfun(@(f,l) sprintf('%gkHz_%gdB',f,l),freq,level,'UniformOutput',false);

ctx = struct();

% Design.
ctx.numStimuli        = n;
ctx.repetitions       = [512 512 256 512 512 256];   % deliberately unequal
ctx.alternatePolarity = [true false false false false false];
ctx.IDs               = ids;
ctx.durations         = repmat(5e-3,1,n);
ctx.params = struct( ...
    'Names',   {{'Frequency','Level'}}, ...
    'Values',  [freq(:) level(:)], ...
    'Varying', [true true], ...
    'Units',   {{'kHz','dB'}}, ...
    'IDs',     {ids});

% Timing.
ctx.sampleRate    = 192000;
ctx.isi           = 1/21.1;
ctx.isiMode       = 'fixed';
ctx.isiRange      = [1 1]/21.1;
ctx.minISI        = 1/21.1;
ctx.meanISI       = 1/21.1;
ctx.silencePad    = 0.25;
ctx.maxRunSamples = 2^26;

% A fixed seed, so validating the same strategy twice gives the same answer
% even when it shuffles.
ctx.randStream = RandStream('twister','Seed',0);
end
