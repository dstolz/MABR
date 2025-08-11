function T = parseABRFiles(sessionPath, filePattern)
% PARSEABRFILES Parses ABR filenames to extract metadata.
%
% Inputs:
%   sessionPath - Path to the session folder.
%   filePattern - Regular expression pattern for filenames.
%
% Output:
%   T - Table containing parsed metadata and filenames.

d = dir(fullfile(sessionPath, '*.abr'));
fn = string({d.name})';

tokens = regexp(fn, filePattern, 'tokens');
ind = cellfun(@isempty, tokens);
if all(ind)
    T = [];
    return
end
tokens(ind) = [];
fn(ind) = [];


tokens = [tokens{:}]';
tokens = vertcat(tokens{:});
T = array2table(tokens, 'VariableNames', {'subject_id', 'frequency', 'level', 'timestamp'});
T.filename = fn;

T.timestamp = datetime(T.timestamp, 'InputFormat', "yyMMdd'T'HHmmss");
T.subject_id = "SUBJ-ID-" + T.subject_id;
T.level = cellfun(@(a) sscanf(a, '%d'), T.level);
T.frequency = cellfun(@(a) sscanf(strrep(a, '_', '.'), '%g') * 1000, T.frequency);

T = sortrows(T);
