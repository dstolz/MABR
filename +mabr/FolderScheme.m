classdef FolderScheme
% mabr.FolderScheme  Where under the Output folder a session's files go.
%
%   S = mabr.FolderScheme returns the default scheme: every Start writes into
%   a folder of its own, named for the subject and the moment it started,
%
%       <Output>\SUBJ-ID-1254\SUBJ-ID-1254_261001T143012\<the .abr files>
%
%   from the pattern '{Subject}/{Subject}_{Date}T{Time}'. The pattern is a
%   relative path, '/' (or '\') between folders, whose {tokens} are filled in
%   when the session starts. Text outside the braces is kept as written.
%
%   Session tokens -- the same for every file one Start writes, which is what
%   puts them all in one folder:
%
%       {Subject}         the Subject ID as typed
%       {Date}            the date Start was pressed, yyMMdd
%       {Time}            the time Start was pressed, HHmmss
%       {Start:fmt}       that moment in any datetime format, e.g.
%                         {Start:yyyy-MM-dd} -> 2026-10-01
%       {Bank}            the stimulus bank's name (its file name, or demo /
%                         designer for a bank with none)
%       {Strategy}        the presentation strategy (conventional, ...)
%       {Mode}            TestMode or StimOnly, and nothing for an ordinary
%                         recording, so a Test Mode session cannot be filed
%                         as though it were a subject
%       {User}            the Windows login of whoever pressed Start
%
%   Stimulus tokens -- any other name is read off the stimulus each FILE was
%   recorded with, so a folder level built from one splits a session by
%   condition:
%
%       {ID}              the stimulus ID
%       {Frequency} ...   any of the bank's own parameters, by name, in the
%                         units the bank states them in (Frequency in kHz)
%       {Level:%03g}      a number may carry a printf format
%
%   A folder level holding a stimulus token, and every level below it, exists
%   only per file. Anything written once per session rather than per
%   condition -- the notes journal, and the _STIM_ .mat of a run that presents
%   more than one stimulus -- goes in the deepest folder the session tokens
%   alone can name (sessionFolder).
%
%   Values are made safe for a Windows path: characters a folder name cannot
%   hold become '-', and a token that comes out empty takes the separator
%   next to it along, so '{Subject}_{Mode}' is 'SUBJ-ID-1254' for an ordinary
%   recording rather than 'SUBJ-ID-1254_'. A level that comes out empty is
%   dropped. File NAMES are untouched by any of this -- they still match the
%   offline pipeline's regex (see mabr.data.io.buildFilename).
%
%   Enabled = false is the old behaviour: every file straight into the Output
%   folder. The pattern is kept while it is off, so switching back costs
%   nothing.
%
%   Like mabr.ArtifactPolicy this is a value object. mabr.ui.App edits one
%   through mabr.ui.FolderSchemeDialog (Settings > Session Folders...),
%   remembers it in MATLAB prefs (loadPrefs/savePrefs, group 'MABR') and in a
%   configuration file (toStruct/fromStruct), and hands it to the Session at
%   Start with the context it is resolved against (mabr.data.Session.folderFor).
%
%   See also mabr.ui.FolderSchemeDialog, mabr.data.Session, mabr.data.io.
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        DefaultPattern = '{Subject}/{Subject}_{Date}T{Time}'

        % The tokens a session fills in, in the order the dialog lists them.
        SessionTokens = {'Subject','Date','Time','Start','Bank','Strategy','Mode','User'}

        % Patterns offered ready-made by the dialog, with what each reads as.
        Presets = { ...
            '{Subject}/{Subject}_{Date}T{Time}',            'Subject \ Subject_DateTTime  (default)'; ...
            '{Subject}/{Subject}_{Date}T{Time}_{Bank}',     'Subject \ Subject_DateTTime_Bank'; ...
            '{Subject}/{Start:yyyy-MM-dd}/{Subject}_{Time}','Subject \ yyyy-MM-dd \ Subject_Time'; ...
            '{Start:yyyy-MM-dd}/{Subject}_{Date}T{Time}',   'yyyy-MM-dd \ Subject_DateTTime'; ...
            '{Subject}/{Subject}_{Date}T{Time}/{ID}',       'Subject \ Subject_DateTTime \ one folder per stimulus'}

        PrefEnabled = 'FolderSchemeEnabled'
        PrefPattern = 'FolderSchemePattern'
    end

    properties
        Enabled (1,1) logical = true
        Pattern (1,:) char    = mabr.FolderScheme.DefaultPattern
    end

    methods
        function obj = FolderScheme(pattern,enabled)
            if nargin >= 1 && ~isempty(pattern), obj.Pattern = strtrim(char(pattern)); end
            if nargin >= 2 && ~isempty(enabled), obj.Enabled = logical(enabled); end
        end

        function d = resolve(obj,root,ctx,meta)
            % The folder a file goes in: root, then the pattern filled in
            % from the session context ctx (see context) and, when given, the
            % stimulus metadata meta (mabr.stim.StimulusSet.meta). Without
            % meta it stops before the first level that needs a stimulus --
            % the session folder. '' when root is ''; root itself when the
            % scheme is off or comes out empty.
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            if nargin < 4, meta = []; end
            d = char(root);
            if isempty(d) || ~obj.Enabled, return; end
            rel = obj.relative(ctx,meta);
            if ~isempty(rel), d = fullfile(d,rel); end
        end

        function rel = relative(obj,ctx,meta)
            % The pattern filled in, as a relative path ('' when it comes out
            % empty or the scheme is off). See resolve.
            if nargin < 2 || isempty(ctx), ctx = struct(); end
            if nargin < 3, meta = []; end
            rel = '';
            if ~obj.Enabled, return; end
            segs = mabr.FolderScheme.segments(obj.Pattern);
            out  = {};
            for k = 1:numel(segs)
                names = mabr.FolderScheme.tokensIn(segs{k});
                perStim = ~all(ismember(lower(names),lower(mabr.FolderScheme.SessionTokens)));
                if perStim && ~isstruct(meta), break; end
                s = mabr.FolderScheme.fillSegment(segs{k},ctx,meta);
                if ~isempty(s), out{end+1} = s; end %#ok<AGROW>
            end
            if ~isempty(out), rel = strjoin(out,filesep); end
        end

        function [ok,err,warn] = validate(obj,params)
            % Whether the pattern can be used (ok/err), and anything about it
            % worth saying that does not stop it (warn). params, optional, is
            % the loaded bank's parameter names: a stimulus token naming none
            % of them is a warning, not an error, since the bank can change
            % before the next Start and a missing value only drops the token.
            if nargin < 2, params = {}; end
            ok = true; err = ''; warn = '';
            p = obj.Pattern;
            if ~obj.Enabled, return; end
            if isempty(strtrim(p))
                warn = 'The pattern is empty, so files go straight into the Output folder.';
                return
            end
            % Braces must pair, and not nest.
            depth = cumsum((p == '{') - (p == '}'));
            if any(depth < 0) || depth(end) ~= 0 || any(depth > 1)
                ok = false; err = 'Every { needs a matching } (and they do not nest).';
                return
            end
            lit = regexprep(p,'\{[^{}]*\}','');
            bad = unique(lit(ismember(lit,'<>:"|?*')));
            if ~isempty(bad)
                ok = false;
                err = sprintf('A folder name cannot contain %s.',strjoin(cellstr(bad(:)),' '));
                return
            end
            segs = mabr.FolderScheme.segments(p);
            if any(strcmp(segs,'..'))
                ok = false; err = '".." is not allowed: the folders go under Output, never above it.';
                return
            end
            names = mabr.FolderScheme.tokensIn(p);
            if any(cellfun(@isempty,names))
                ok = false; err = 'An empty {} names nothing.';
                return
            end
            stim = names(~ismember(lower(names),lower(mabr.FolderScheme.SessionTokens)));
            stim = unique(stim,'stable');
            known = [{'ID'} cellstr(params(:))'];
            unknown = stim(~ismember(lower(stim),lower(known)));
            notes = {};
            if ~isempty(params) && ~isempty(unknown)
                notes{end+1} = sprintf(['{%s} is not a parameter of the loaded bank -- ' ...
                    'it is left out wherever a stimulus lacks it.'],strjoin(unknown,'}, {'));
            end
            if ~isempty(stim)
                notes{end+1} = ['Folder levels from a {stimulus} token on are per condition ' ...
                    '(the notes journal goes in the level above), and offline analysis ' ...
                    'reads each folder of .abr files as one session.'];
            end
            if ~any(ismember(lower(names),{'date','time','start'}))
                notes{end+1} = ['No {Date}, {Time} or {Start}: every Start for a subject ' ...
                    'writes into the same folder.'];
            end
            warn = strjoin(notes,' ');
        end

        function s = describe(obj)
            % One line for the status line / a tooltip.
            if ~obj.Enabled || isempty(strtrim(obj.Pattern))
                s = 'files straight into the Output folder';
            else
                s = ['session folders ' strrep(obj.Pattern,'/','\')];
            end
        end

        function s = toStruct(obj)
            % Plain-struct snapshot for a configuration file.
            s = struct('Enabled',obj.Enabled,'Pattern',obj.Pattern);
        end
    end

    methods (Static)
        function obj = none()
            % Every file straight into the Output folder -- what a Session
            % does until somebody hands it a scheme, so a script setting
            % OutputPath finds its files where it put them.
            obj = mabr.FolderScheme([],false);
        end

        function ctx = context(varargin)
            % The session half of what a pattern is filled in from, as name/
            % value pairs: Subject, Start (datetime or text; default now),
            % Bank, Strategy, Mode, User (default the Windows login).
            ctx = struct('Subject','','Start',datetime('now'),'Bank','', ...
                         'Strategy','','Mode','','User',char(getenv('USERNAME')));
            for k = 1:2:numel(varargin)-1
                f = char(varargin{k});
                v = varargin{k+1};
                if strcmpi(f,'Start')
                    if isempty(v), v = datetime('now'); end
                    if ~isdatetime(v), v = datetime(v); end
                    ctx.Start = v;
                else
                    ctx.(f) = char(string(v));
                end
            end
        end

        function T = tokenHelp()
            % Name, what it is, and an example, one row per token the dialog
            % offers to insert -- the session tokens, then the stimulus ones.
            T = { ...
                '{Subject}',          'Subject ID',                          'SUBJ-ID-1254'; ...
                '{Date}',             'Date of Start (yyMMdd)',              '261001'; ...
                '{Time}',             'Time of Start (HHmmss)',              '143012'; ...
                '{Start:yyyy-MM-dd}', 'Start in any datetime format',        '2026-10-01'; ...
                '{Bank}',             'Stimulus bank name',                  'tones_8-32k'; ...
                '{Strategy}',         'Presentation strategy',               'conventional'; ...
                '{Mode}',             'TestMode / StimOnly (else nothing)',  'TestMode'; ...
                '{User}',             'Windows login',                       'dstolz'; ...
                '{ID}',               'Stimulus ID (one folder per stimulus)','Tone_8000_30'};
        end

        function obj = loadPrefs()
            % The last scheme used, falling back to the default for anything
            % never saved or saved as something that is not one.
            obj = mabr.FolderScheme;
            try
                obj = mabr.FolderScheme.fromStruct(struct( ...
                    'Enabled',getpref('MABR',mabr.FolderScheme.PrefEnabled,obj.Enabled), ...
                    'Pattern',getpref('MABR',mabr.FolderScheme.PrefPattern,obj.Pattern)));
            catch
                obj = mabr.FolderScheme;
            end
        end

        function savePrefs(obj)
            setpref('MABR',mabr.FolderScheme.PrefEnabled,obj.Enabled);
            setpref('MABR',mabr.FolderScheme.PrefPattern,obj.Pattern);
        end

        function obj = fromStruct(s)
            % Inverse of toStruct, forgiving field by field: a pattern that is
            % not text, or that does not validate, leaves the default.
            obj = mabr.FolderScheme;
            if ~isstruct(s), return; end
            if isfield(s,'Enabled') && (islogical(s.Enabled) || isnumeric(s.Enabled)) ...
                    && isscalar(s.Enabled)
                obj.Enabled = logical(s.Enabled);
            end
            if isfield(s,'Pattern') && (ischar(s.Pattern) || (isstring(s.Pattern) && isscalar(s.Pattern)))
                cand = mabr.FolderScheme(strtrim(char(s.Pattern)),true);
                if cand.validate() || isempty(cand.Pattern)
                    obj.Pattern = cand.Pattern;
                end
            end
        end

        function s = safeName(s)
            % s made usable as one Windows folder name: no character a name
            % cannot hold (path separators included, so a value can never
            % add a level), no trailing dots or spaces, and no device name.
            s = char(s);
            s(ismember(s,'<>:"/\|?*') | s < 32) = '-';
            s = regexprep(strtrim(s),'[\s.]+$','');
            if any(strcmpi(s,{'CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4', ...
                    'COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3'}))
                s = ['_' s];
            end
        end
    end

    methods (Static, Access = private)
        function segs = segments(p)
            % The pattern's folder levels, empty and '.' levels dropped.
            % Split outside braces only, so a {Start:yyyy/MM} format cannot
            % be cut in half (its '/' is cleaned out of the value instead).
            p = char(p);
            segs = {};
            if isempty(p), return; end
            inTok = cumsum((p == '{') - [0 (p(1:end-1) == '}')]) > 0;
            cut = find(ismember(p,'/\') & ~inTok);
            edges = [0 cut numel(p)+1];
            for k = 1:numel(edges)-1
                s = strtrim(p(edges(k)+1:edges(k+1)-1));
                if ~isempty(s) && ~strcmp(s,'.'), segs{end+1} = s; end %#ok<AGROW>
            end
        end

        function names = tokensIn(s)
            % The token names in s, format suffixes removed.
            t = regexp(char(s),'\{([^{}]*)\}','tokens');
            names = cellfun(@(c) strtrim(regexprep(c{1},':.*$','')),t,'UniformOutput',false);
        end

        function out = fillSegment(seg,ctx,meta)
            % One folder level with its tokens filled in and tidied. A token
            % that comes out empty takes one separator next to it along.
            [tok,lit] = regexp(seg,'\{([^{}]*)\}','tokens','split');
            vals = cell(1,numel(tok));
            for k = 1:numel(tok)
                vals{k} = mabr.FolderScheme.safeName( ...
                    mabr.FolderScheme.tokenValue(tok{k}{1},ctx,meta));
            end
            for k = 1:numel(tok)
                if ~isempty(vals{k}), continue; end
                % Drop the separator after the token, or else the one before.
                if ~isempty(lit{k+1}) && any(lit{k+1}(1) == '_-. ')
                    lit{k+1} = lit{k+1}(2:end);
                elseif ~isempty(lit{k}) && any(lit{k}(end) == '_-. ')
                    lit{k} = lit{k}(1:end-1);
                end
            end
            out = lit{1};
            for k = 1:numel(tok)
                out = [out vals{k} lit{k+1}]; %#ok<AGROW>
            end
            out = regexprep(out,'^[\s_\-.]+','');
            out = mabr.FolderScheme.safeName(regexprep(out,'[\s_\-]+$',''));
        end

        function v = tokenValue(spec,ctx,meta)
            % The text one {spec} stands for: 'Name' or 'Name:format'.
            spec = char(spec);
            c = find(spec == ':',1);
            if isempty(c), name = strtrim(spec); fmt = '';
            else, name = strtrim(spec(1:c-1)); fmt = spec(c+1:end);
            end
            start = mabr.FolderScheme.field(ctx,'Start');
            if isempty(start), start = datetime('now'); end
            if ~isdatetime(start)
                try, start = datetime(start); catch, start = datetime('now'); end
            end
            switch lower(name)
                case 'date',  v = mabr.FolderScheme.stamp(start,'yyMMdd'); return
                case 'time',  v = mabr.FolderScheme.stamp(start,'HHmmss'); return
                case 'start'
                    if isempty(fmt), fmt = 'yyMMdd''T''HHmmss'; end
                    v = mabr.FolderScheme.stamp(start,fmt); return
                case lower(mabr.FolderScheme.SessionTokens)
                    v = mabr.FolderScheme.field(ctx,name);
                otherwise
                    v = mabr.FolderScheme.field(meta,name);
            end
            if isstruct(v) && isfield(v,'Value'), v = v.Value; end   % legacy sigProp
            if isnumeric(v) || islogical(v)
                if isempty(v), v = ''; return; end
                v = double(v(1));
                if isempty(fmt), v = sprintf('%g',v);
                else
                    try, v = sprintf(fmt,v); catch, v = sprintf('%g',v); end
                end
            elseif isstring(v) || ischar(v)
                v = char(strjoin(string(v),'_'));
            else
                v = '';
            end
        end

        function v = field(s,name)
            % s.(name), matched without regard to case; '' when absent.
            v = '';
            if ~isstruct(s) || isempty(s), return; end
            f = fieldnames(s);
            k = find(strcmpi(f,name),1);
            if ~isempty(k), v = s(1).(f{k}); end
        end

        function t = stamp(dt,fmt)
            try
                dt.Format = fmt;
                t = char(dt);
            catch
                dt.Format = 'yyMMdd''T''HHmmss';
                t = char(dt);
            end
        end
    end
end
