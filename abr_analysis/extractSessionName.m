function sessionName = extractSessionName(sessionPath)
    % EXTRACTSESSIONNAME Extracts the session name from the full path.
    %
    % Input:
    %   sessionPath - Full path to the session folder.
    %
    % Output:
    %   sessionName - Name of the session folder.

    [~, sessionName] = fileparts(sessionPath);
end
