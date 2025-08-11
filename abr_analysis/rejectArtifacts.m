function S = rejectArtifacts(S, option)
% REJECTARTIFACTS Performs simple artifact rejection on ABR data.
%
% Inputs:
%   S      - Cell array of ABR responses.
%   respInd - Samples corresponding to the response window.
%
% Output:
%   S - Cleaned ABR responses.

arguments
    S (:,:) cell
    option.respInd (1,:) logical = []
    option.nstd (1,1) double = 3
end


for i = 1:numel(S)
    y = S{i};

    if isempty(y), continue; end
    
    
    if isempty(option.respInd)
        respInd = true(size(y,1),1);
    else
        respInd = option.respInd;
    end

    y = y(respInd,:);
    
    r = rms(y);
    z = zscore(r);
    aind = abs(z) > option.nstd;

    S{i}(:, aind) = [];
    part = sum(aind) / size(y, 2);
    if part > 0.5
        fprintf(2, '# artifacts = %d (%0.1f%%)\n', sum(aind), 100 * part)
    else
        fprintf('# artifacts = %d (%0.1f%%)\n', sum(aind), 100 * part)
    end
end
