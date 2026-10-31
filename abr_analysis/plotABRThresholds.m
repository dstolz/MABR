function plotABRThresholds(thresh_hat, freqs, options)
% plotABRThresholds Visualize ABR threshold estimates and audiogram.
%
%   plotABRThresholds(thresh_hat, freqs, cm) creates audiogram showing
%   threshold estimates across frequencies.
%
%   Inputs:
%     thresh_hat - Estimated thresholds for each frequency.
%     freqs - frequencies corresponding to `thresh_hat`
% 
%   Optional Name-Value Inputs:
%     cm         - Colormap or color vector for plotting.
%
%   Needs STRUCTTOCALLERVARS (and COLORCET unless cm is given) from the author's
%   helper_fnc repository, https://github.com/dstolz/helper_fnc; without them it stops
%   at once with error abr_analysis:missingDependency.
%


arguments
    thresh_hat (1,:) double
    freqs (1,:) double
    options.cm = [] % Optional; default assigned in function body
end

helpers = "structToCallerVars";
if isempty(options.cm), helpers(end+1) = "colorcet"; end
checkABRDependencies("plotABRThresholds", helpers);

structToCallerVars(options);

if isempty(cm)
    cm = colorcet('L8', 'N', length(freqs));
end


scatter(freqs, thresh_hat, 60, cm, 'filled');
line(freqs, thresh_hat, 'Color', 'k', 'LineStyle', '--');
text(freqs, thresh_hat + 1, ...
    compose('%.1f', thresh_hat), ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'bottom', ...
    'FontSize', 10, 'Color', 'k');
set(gca, 'XScale', 'log', ...
    'XTick', freqs, ...
    'XLim', freqs([1 end]) .* 2.^[-0.25 0.25]);
grid on;
box on;
ylabel('Threshold Estimate (dB SPL)');
xlabel('Frequency (Hz)');
title('ABR Audiogram');

