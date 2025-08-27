function [S, U, Fs, winIdx] = extractABRResponses(T, win, opts)
%EXTRACTABRRESPONSES Extract per-sweep ABR segments grouped by stimulus.
%   [S,U,Fs,winIdx] = EXTRACTABRRESPONSES(T, win) loads each file listed in T
%   (as produced by PARSEABRFILES) and extracts segments of ADC.Data around
%   each sweep onset. Responses are grouped by unique combinations of the
%   stimulus parameters that appear in T before the variable 'timestamp'.
%
%   Filtering (optional): If enabled, the filter(s) are applied to the entire
%   original a.ADC.Data trace BEFORE segmentation into sweeps.
%
%   Optional filtering (Name-Value in opts):
%     opts.lowpass        logical, apply default low-pass (default: true)
%     opts.highpass       logical, apply default high-pass (default: true)
%     opts.LowpassHd      dfilt/dsp.* filter object for low-pass (overrides default design)
%     opts.HighpassHd     dfilt/dsp.* filter object for high-pass (overrides default design)
%     opts.FilterMethod   "filtfilt" (default) or "filter"
%
%   Default filters (designed per file using Fs):
%     Low-pass:  Fpass=3000 Hz, Fstop=4200 Hz, Dpass=0.014390163418, Dstop=0.031622776602
%     High-pass: Fstop=3000 Hz, Fpass=4200 Hz, same ripples as above.
%
%   INPUT
%     T       Table from PARSEABRFILES with columns 'folder', 'fileName',
%             'timestamp', and stimulus-parameter variables listed before 'timestamp'.
%     win     Two-element vector [t0 t1] in milliseconds, segment window relative
%             to sweep onset.
%     opts    (Name-Value struct, optional) filtering controls as above.
%
%   OUTPUT
%     S       Cell array sized by the number of unique values of each stimulus
%             parameter (in the order they appear before 'timestamp'). Each
%             nonempty cell contains a matrix [numSamples x numSweeps].
%     U       Struct of unique values for each stimulus parameter.
%     Fs      ADC sampling rate (Hz). Assumed identical across files; the value
%             returned is from the last processed file.
%     winIdx  Sample offsets used for extraction (relative to onset), in samples.
%
%   EXAMPLE
%     [S,U,Fs,winIdx] = extractABRResponses(T, [0 12], struct('highpass',true,'lowpass',true));
%
% dstolz@umd.edu 2025

arguments
    T table
    win (1,2) double
    opts.lowpass (1,1) logical = true
    opts.highpass (1,1) logical = true
    opts.LowpassHd = []
    opts.HighpassHd = []
    opts.FilterMethod (1,1) string {mustBeMember(opts.FilterMethod,["filtfilt","filter"])} = "filtfilt"
end

minNumSweeps = 1;

% stimulus properties of interest are listed before "timestamp"
p = string(T.Properties.VariableNames);
it = find(p == "timestamp");
poi = p(1:it-1);

for a = poi, V.(a) = [T.(a)]; end
U = structfun(@unique, V,'uni',0);
sdim = structfun(@numel,U);

S = cell(sdim(:)');
sp = cell(1,length(poi));

warning('off', 'audio:audioPlayerRecorder:invalidDevice')

parfor_progress(size(T,1),sprintf('Extracting %d waveforms',size(T,1)));
for k = 1:size(T,1)

    for j = 1:length(poi)
        sp{j} = find(ismember(U.(poi(j)),T.(poi(j))(k)));
    end
    sidx = sub2ind(sdim,sp{:});

    a = load(fullfile(T.folder(k),T.fileName(k)),'-mat');
    a = a.ABR_Data;

    Fs = a.ADC.SampleRate;
    swin = round(Fs * win / 1000);
    winIdx = swin(1):swin(2);

    nSweeps  = numel(a.ADC.SweepOnsets);
    nSamples = numel(a.ADC.Data);
    if nSweeps < minNumSweeps, parfor_progress; continue; end

    % ---- Apply optional filtering to FULL trace before segmentation ----
    x = a.ADC.Data(:); % column vector
    if opts.highpass
        HdHP = opts.HighpassHd;
        if isempty(HdHP), HdHP = defaultHighpassHd(Fs); end
        [bHP,aHP] = getBA(HdHP);
        x = applyFilter(x, bHP, aHP, opts.FilterMethod);
    end
    if opts.lowpass
        HdLP = opts.LowpassHd;
        if isempty(HdLP), HdLP = defaultLowpassHd(Fs); end
        [bLP,aLP] = getBA(HdLP);
        x = applyFilter(x, bLP, aLP, opts.FilterMethod);
    end

    % ---- Segment filtered trace into sweeps ----
    S{sidx} = nan(length(winIdx), nSweeps);
    for ii = 1:nSweeps
        idx = a.ADC.SweepOnsets(ii) + winIdx;
        if any(idx > nSamples | idx < 1), continue; end
        S{sidx}(:, ii) = x(idx);
    end
    S{sidx} = S{sidx}(:, ~any(isnan(S{sidx}), 1));

    parfor_progress;
end
parfor_progress(0);

warning('on', 'audio:audioPlayerRecorder:invalidDevice')

% ====== Subfunctions ======
function Hd = defaultLowpassHd(FsLoc)
    Fpass = 3000;            % Hz
    Fstop = 4200;            % Hz
    Dpass = 0.014390163418;  % Passband ripple
    Dstop = 0.031622776602;  % Stopband attenuation
    dens  = 20;              % Density factor
    [N,Fo,Ao,W] = firpmord([Fpass Fstop]/(FsLoc/2), [1 0], [Dpass Dstop]);
    b = firpm(N, Fo, Ao, W, {dens});
    Hd = dfilt.dffir(b);
end

function Hd = defaultHighpassHd(FsLoc)
    Fstop = 150;            % Hz
    Fpass = 300;            % Hz
    Dpass = 0.014390163418;
    Dstop = 0.031622776602;
    dens  = 20;
    [N,Fo,Ao,W] = firpmord([Fstop Fpass]/(FsLoc/2), [0 1], [Dstop Dpass]);
    b = firpm(N, Fo, Ao, W, {dens});
    Hd = dfilt.dffir(b);
end

function [b,a] = getBA(HdObj)
    if isa(HdObj,'dfilt.dffir')
        b = HdObj.Numerator; a = 1;
    elseif isa(HdObj,'dsp.FIRFilter')
        b = HdObj.Numerator; a = 1;
    elseif any(strcmp(class(HdObj), {'dfilt.df1','dfilt.df1t','dfilt.df2','dfilt.df2t'}))
        [b,a] = tf(HdObj);
    else
        try
            [b,a] = tf(HdObj);
        catch
            error('Unsupported filter object type for Hd.');
        end
    end
end

function y = applyFilter(x, b, a, method)
    switch lower(method)
        case 'filtfilt'
            y = filtfilt(b, a, x);
        case 'filter'
            y = filter(b, a, x);
        otherwise
            error('Unknown FilterMethod: %s', method);
    end
end

end
