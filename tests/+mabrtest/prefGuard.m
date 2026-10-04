function g = prefGuard(keys,opts)
% mabrtest.prefGuard  Put MABR preferences back as they were, whatever a test does.
%
%   g = mabrtest.prefGuard(keys)
%   g = mabrtest.prefGuard(keys,Clear=true)
%
%   Snapshots each named preference -- its value, or the fact that it does
%   not exist -- and returns an onCleanup that restores exactly that when it
%   is cleared or goes out of scope: setpref for a preference that existed,
%   rmpref for one that did not. A test holds g for as long as it may write
%   any of them, error or not:
%
%       g = mabrtest.prefGuard(["OfflineAnalysisSettings" "WindowPos_OfflineAnalysis"]);
%       ...                      % anything that can setpref those
%       clear g                  % (or just return) -- the user's values are back
%
%   keys        string array of pref names in the 'MABR' group; a key written
%               "group/name" names a pref in another group
%   opts.Clear  remove every named pref now, after the snapshot, so the test
%               starts from the defaults a fresh install has (default false)
%   g           (returned) onCleanup restoring the snapshot
%
%   A test that can write a pref must hold one of these: a rig's own settings
%   are what MABR opens with next session, and a test run must not change
%   them. Restoring never throws -- a failed setpref is a pref left as the
%   test made it, which is worth less than the rest of the cleanup.
%
%   See also setpref, getpref, rmpref, ispref, onCleanup.
%
% Daniel Stolzberg (c) 2026

arguments
    keys string
    opts.Clear (1,1) logical = false
end

keys = unique(reshape(keys,1,[]),'stable');
keys(ismissing(keys) | strtrim(keys) == "") = [];
n = numel(keys);
group = strings(1,n);
name  = strings(1,n);
for k = 1:n
    parts = split(keys(k),"/");
    if numel(parts) >= 2
        group(k) = parts(1);
        name(k)  = join(parts(2:end),"/");
    else
        group(k) = "MABR";
        name(k)  = keys(k);
    end
end

had = false(1,n);
val = cell(1,n);
for k = 1:n
    had(k) = ispref(char(group(k)),char(name(k)));
    if had(k), val{k} = getpref(char(group(k)),char(name(k))); end
end

if opts.Clear
    for k = 1:n
        if had(k), rmpref(char(group(k)),char(name(k))); end
    end
end

g = onCleanup(@() restore(group,name,had,val));
end

% =========================================================================
function restore(group,name,had,val)
% Each pref back to its snapshot: its old value, or absent.
for k = 1:numel(name)
    try
        if had(k)
            setpref(char(group(k)),char(name(k)),val{k});
        elseif ispref(char(group(k)),char(name(k)))
            rmpref(char(group(k)),char(name(k)));
        end
    catch
        % never throw from a cleanup; the other prefs still come back
    end
end
end
