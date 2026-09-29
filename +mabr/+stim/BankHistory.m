classdef BankHistory
% mabr.stim.BankHistory  The stimulus bank files MABR has been pointed at, most recent first.
%
%   What the Bank dropdown of mabr.ui.App's Stimulus panel lists. A plain value
%   object in the shape of the policies in +mabr (loadPrefs/savePrefs in the
%   MABR pref group), but HISTORY rather than a setting: it is not in a
%   .mabrcfg and not in the last-session snapshot, for the same reason
%   mabr.ui.App's recent configurations and stimgen launcher's recent files
%   are not -- which files an operator has opened on this machine says
%   nothing about what a named protocol should restore.
%
%       h = mabr.stim.BankHistory.loadPrefs();
%       h = h.add('C:\banks\ABR_tones.spl');            % a bank was used
%       h = h.add({'C:\banks\a.spl','C:\banks\b.mat'}); % or several at once
%       h = h.remove('C:\banks\a.spl');
%       mabr.stim.BankHistory.savePrefs(h);
%
%   It holds paths and nothing else. It never opens a file, so a bank that
%   has since moved is still listed until something tries to use it and finds
%   out (mabr.ui.App drops it then, with a status line); checking every entry
%   whenever the list is drawn would put a disk -- or an unmounted network
%   drive -- between the operator and the window.
%
%   Paths compare case-insensitively (MABR is Windows-only), and the list is
%   capped at Max: adding to a full list pushes the oldest off the end.
%
%   Folder is the other half of the same history: the folder a bank file was
%   last picked from in a file dialog, so the next dialog opens there rather
%   than wherever MATLAB's current folder happens to be. startFolder() is what
%   a dialog should be handed -- Folder while it still exists, else the folder
%   of the newest listed bank, else '' (the dialog's own default).
%
%       h = h.pickedFrom('C:\banks\protocolA');
%       [fn,pn] = uigetfile('*.spl','Load',h.startFolder());
%
% Daniel Stolzberg (c) 2026

    properties
        % Most recently used first. Always a 1xN cell of non-empty char rows,
        % no two the same path.
        Files (1,:) cell = cell(1,0)
        % The folder a bank was last picked from in a file dialog ('' until
        % one has been). Kept separately from Files because a dialog can be
        % pointed at a folder and cancelled, or at a file that then fails to
        % load, and either way that is where the operator was looking.
        Folder (1,:) char = ''
    end

    properties (Constant)
        % The same length the stimgen launcher's recent files keep.
        Max = 10
        PrefName = 'RecentBankFiles'
        FolderPrefName = 'LastBankFolder'
    end

    methods
        function obj = BankHistory(files)
            if nargin > 0
                obj.Files = mabr.stim.BankHistory.clean(files);
                obj.Files = obj.Files(1:min(numel(obj.Files),obj.Max));
            end
        end

        function n = count(obj)
            n = numel(obj.Files);
        end

        function [obj,dropped] = add(obj,files)
            % Put files at the front, in the order given (so the first of
            % several is the most recent), moving any that were already listed
            % rather than duplicating them. dropped is how many of the OLD
            % entries fell off the end to make room.
            new = mabr.stim.BankHistory.clean(files);
            old = obj.Files(~ismember(lower(obj.Files),lower(new)));
            list = [new, old];
            dropped = max(0,numel(list) - obj.Max);
            obj.Files = list(1:min(numel(list),obj.Max));
        end

        function obj = remove(obj,file)
            % Take one path off the list. The file itself is never touched.
            obj.Files = obj.Files(~strcmpi(obj.Files,char(file)));
        end

        function obj = pickedFrom(obj,folder)
            % Remember where a file dialog was last used. Anything that is
            % not a single line of text leaves the remembered folder alone.
            if isstring(folder) && isscalar(folder) && ~ismissing(folder)
                folder = char(folder);
            end
            if ~ischar(folder) || ~isrow(folder), return; end
            folder = strtrim(folder);
            % uigetfile hands back the path with a trailing separator; store
            % it without, so the same folder is always the same string.
            while numel(folder) > 3 && any(folder(end) == '\/')
                folder(end) = [];
            end
            if ~isempty(folder), obj.Folder = folder; end
        end

        function f = startFolder(obj)
            % Where the next bank dialog should open: the remembered folder
            % while it still exists, else the folder of the newest listed bank
            % that does, else '' -- the dialog's own default. Only the first
            % few entries are tried, since each isfolder on an unmounted
            % network drive can stall before it says no.
            f = '';
            cand = {obj.Folder};
            for k = 1:min(3,numel(obj.Files))
                cand{end+1} = fileparts(obj.Files{k}); %#ok<AGROW>
            end
            for k = 1:numel(cand)
                if ~isempty(cand{k}) && isfolder(cand{k})
                    f = cand{k};
                    return
                end
            end
        end

        function tf = has(obj,file)
            tf = any(strcmpi(obj.Files,char(file)));
        end

        function l = labels(obj)
            % What to show for each entry, and each one DISTINCT, so they can
            % stand as the items of a dropdown: the file name alone; the
            % folder as well where the same name appears twice -- two banks
            % called ABR_tones.spl in different folders are otherwise
            % indistinguishable, while a folder on every entry would just be
            % noise; and the whole path for any that are still the same after
            % that (the same name in two folders of the same name). The full
            % path is the caller's tooltip.
            n = numel(obj.Files);
            base = cell(1,n); parent = cell(1,n);
            for k = 1:n
                [p,nm,ext] = fileparts(obj.Files{k});
                base{k} = [nm ext];
                [~,parent{k}] = fileparts(p);
            end
            l = base;
            for k = 1:n
                if sum(strcmpi(base,base{k})) > 1 && ~isempty(parent{k})
                    l{k} = sprintf('%s  (%s)',base{k},parent{k});
                end
            end
            named = l;
            for k = 1:n
                if sum(strcmpi(named,named{k})) > 1, l{k} = obj.Files{k}; end
            end
        end
    end

    methods (Static)
        function obj = loadPrefs()
            % Whatever was saved, forgiving of whatever a pref might hold --
            % written by another version, edited by hand, or corrupted -- so
            % that none of it can stop the app from opening.
            try
                obj = mabr.stim.BankHistory(getpref('MABR',mabr.stim.BankHistory.PrefName,{}));
            catch
                obj = mabr.stim.BankHistory;
            end
            try
                obj = obj.pickedFrom(getpref('MABR',mabr.stim.BankHistory.FolderPrefName,''));
            catch
                % A folder pref that will not read costs the dialog its
                % starting place, never the list.
            end
        end

        function savePrefs(obj)
            setpref('MABR',mabr.stim.BankHistory.PrefName,obj.Files);
            setpref('MABR',mabr.stim.BankHistory.FolderPrefName,obj.Folder);
        end

        function c = clean(files)
            % Any of a char row, a string array, or a cell of them, reduced to
            % a 1xN cell of trimmed non-empty char rows with repeats removed
            % (first occurrence wins). Anything else contributes nothing.
            if ischar(files) || isstring(files)
                files = cellstr(files(:).');
            end
            c = cell(1,0);
            if ~iscell(files), return; end
            for k = 1:numel(files)
                f = files{k};
                if isstring(f) && isscalar(f) && ~ismissing(f), f = char(f); end
                if ~ischar(f) || ~isrow(f), continue; end
                f = strtrim(f);
                if isempty(f) || any(strcmpi(c,f)), continue; end
                c{end+1} = f; %#ok<AGROW>
            end
        end
    end
end
