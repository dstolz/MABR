function abrSessions = getABRSessions(rootPth)
% GETABRSESSIONS Retrieves unique ABR session folders.
%
% Input:
%   rootPth - Root path containing ABR data folders.
%
% Output:
%   abrSessions - Cell array of unique session folder paths.

a = dir(fullfile(rootPth, '**', '*.abr'));
abrSessions = unique({a.folder}');

ind = false(size(abrSessions));
for i = 1:length(abrSessions)
    [~,d] = fileparts(abrSessions{i});
    ind(i) = isempty(d);
end
abrSessions(ind) = [];

