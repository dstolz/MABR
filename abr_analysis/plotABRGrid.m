function axesArray = plotABRGrid(S, U, Fs, winIdx ,options)
% plotABRGrid Visualizes ABR data across frequencies and levels in a tiled layout.
%
%   plotABRGrid(S, T, winIdx, Fs, normalizePerFrequency) plots the
%   auditory brainstem response (ABR) data contained in cell array S.
%
%   Inputs:
%       S - Cell array where each cell contains a matrix of ABR data.
%       U - Struct of unique stimulus values from EXTRACTABRRESPONSES. Needs a
%           level field and a frequency field, in either of the two spellings:
%             files from the current software: U.Level (dB SPL), U.Frequency (kHz)
%             older files:                     U.soundLevel (dB SPL), U.frequency (Hz)
%           The frequency axis label states whichever unit applies.
%       winIdx - Vector of indices specifying the window of interest.
%       Fs - Sampling frequency in Hz.
% 
%   Options:
%       plotWindow - plot window in milliseconds, default = [-1 9];
%       normalizePerFrequency - Logical flag to normalize responses per frequency.
%       cm - colormap
%
%   Example:
%       plotABRGrid(S, U, T, winIdx, Fs, true);
%
%   Needs STRUCTTOCALLERVARS and ERREMPTY (and COLORCET unless cm is given) from the
%   author's helper_fnc repository, https://github.com/dstolz/helper_fnc; without them it
%   stops at once with error abr_analysis:missingDependency.

arguments
    S cell
    U struct
    Fs double {mustBePositive}
    winIdx double
    options.plotWindow (1,2) double = [-1 9]; % ms
    options.normalizePerFrequency logical = true
    options.cm = [];
end


helpers = ["structToCallerVars", "errEmpty"];
if isempty(options.cm), helpers(end+1) = "colorcet"; end
checkABRDependencies("plotABRGrid", helpers);

structToCallerVars(options);

% Files written by the current software name the parameters Level and Frequency
% (kHz); older files use soundLevel and frequency (Hz). Accept either set, and
% remember the frequency unit so the labels do not call kHz values "Hz".
if isfield(U, 'Level')
    lvlVals = U.Level;
elseif isfield(U, 'soundLevel')
    lvlVals = U.soundLevel;
else
    error('plotABRGrid:noLevel', 'U has neither a Level nor a soundLevel field.');
end
if isfield(U, 'Frequency')
    freqVals = U.Frequency;
    freqUnit = 'kHz';
elseif isfield(U, 'frequency')
    freqVals = U.frequency;
    freqUnit = 'Hz';
else
    error('plotABRGrid:noFrequency', 'U has neither a Frequency nor a frequency field.');
end

% Convert window indices to time vector in seconds
tvec = winIdx ./ Fs;

% Determine indices within the specified plot window
pind = tvec >= plotWindow(1)/1000 & tvec <= plotWindow(2)/1000;

% Extract and process data within the plotting window
data = cellfun(@(a) a(pind, :), S, 'UniformOutput', false, 'ErrorHandler', @errEmpty);
SM = cellfun(@(a) mean(a, 2), data, 'UniformOutput', false);

% Flip the data and levels for plotting
SM = flipud(SM);
lvl = flipud(lvlVals(:));

% Determine the number of frequencies
numFreq = numel(freqVals);


% Create a tiled layout
tl = tiledlayout(numel(lvl), numFreq, 'TileIndexing', 'columnmajor', ...
    'Padding', 'tight', 'TileSpacing', 'none');

if isempty(cm)
    cm = colorcet('L8', 'N', numFreq);
end

% Update time vector to match the plotting window
tvec = tvec(pind);

% Plot each averaged response in the appropriate tile
for i = 1:numel(SM)
    ax = nexttile(tl);

    % Add vertical line at time zero
    if tvec(1) < 0
        line(ax, [0, 0], [-1e6, 1e6], ...
            'LineWidth', 0.5, ...
            'LineStyle', '--', ...
            'Color', [0.6, 0.6, 0.6], ...
            'HandleVisibility', 'off');
    end

    % Add horizontal line at zero amplitude
    line(ax, tvec([1, end]) * 1000, [0, 0], ...
        'LineWidth', 0.5, ...
        'Color', [0.6, 0.6, 0.6], ...
        'HandleVisibility', 'off');

    % Determine the row and column for the current tile
    [r, c] = tilerowcol(tl, i);

    % Customize axis appearance
    ax.XAxis.Color = 'none';
    ax.YAxis.Color = 'none';

    if c == 1 && r == 1
        ax.YAxis.Color = [0, 0, 0];
    end

    if c == 1
        ylabel(ax, sprintf('%g', lvl(r)), 'Color', [0, 0, 0]);
    end

    if r == numel(lvl)
        % %g, not %d: kHz values such as 1.5 are not integers.
        xlabel(ax, sprintf('%g', freqVals(c)), 'Color', [0, 0, 0]);
    end

    % Skip if data is empty
    if isempty(SM{i})
        continue;
    end

    % Normalize data if specified
    if normalizePerFrequency
        m = [SM{:,c}];
        m = max(abs(m(:)));
        y = SM{i}/ m;
    else
        y = SM{i};
    end

    % Plot the response
    line(ax, tvec * 1000, y, 'Color', cm(c, :), 'LineWidth', 2);
end

% Adjust y-axis limits
axesArray = tl.Children;
axesArray = reshape(axesArray,tl.GridSize);
axesArray = fliplr(axesArray);
% axesArray = rot90(axesArray,2);
if normalizePerFrequency
    set(axesArray, 'YLim', [-1, 1]);
else
    allData = cell2mat(SM');
    m = max(abs(allData(:)));
    set(axesArray, 'YLim', [-m, m]);
end

% Set x-axis ticks
xticks(axesArray, 1000 * (tvec(1):0.002:tvec(end)));

% Add overall labels and title
ylabel(tl, 'Level (dB SPL)');
xlabel(tl, sprintf('Frequency (%s)', freqUnit));

end
