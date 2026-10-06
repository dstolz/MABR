classdef Commands
% mabr.ui.analysis.Commands  THE keymap of the analysis app: every key, what it does, and where.
%
%   One table says which key runs which command in which part of the window,
%   and the menus, the F1 sheet, the hint strips under each view and the key
%   dispatcher are all read off it -- so a key shown in a menu is the key that
%   works, and no unmodified letter means one thing on one tab and another
%   thing on the next (the table forbids two rows with the same scope, key,
%   modifiers and character, and verify_offline_app holds it to that).
%
%       T  = mabr.ui.analysis.Commands.spec();          % the whole table
%       id = mabr.ui.analysis.Commands.lookup("a","","a",["series","global"]);
%       S  = mabr.ui.analysis.Commands.sheet("series");  % what F1 lists
%       s  = mabr.ui.analysis.Commands.hint("series");   % the strip under the stack
%       M  = mabr.ui.analysis.Commands.gestures("grid"); % the mouse, for F1
%
%   The mouse is not a key, but one gesture would otherwise go unseen:
%   dragging a threshold divider (mabr.ui.analysis.ThresholdDrag). So
%   gestures() lists what the mouse does on each tab, F1 shows it after the
%   keys, and hint() starts the Grid's and the Series' strips with it.
%
%   COLUMNS of spec():
%     Id         the command ("thr.accept"); several rows may share one (two
%                keys, or one key in several scopes)
%     Key        lower-case MATLAB key name as a KeyPressFcn reports it
%                ("a", "uparrow", "return", "f5", "equal"); "" for a row that
%                matches on Char alone, or a command with no default key
%     Modifiers  the modifiers held, sorted and joined by "+": "",
%                "control", "shift", "alt", "control+shift" ("command" on a
%                Mac counts as control)
%     Char       the character typed, for symbol keys whose Key differs by
%                keyboard layout ("+", "-"); "" otherwise
%     Scope      "global", "browser", "session", "grid", "series", "trials"
%                or "study": where the row applies (a tab, or the browser)
%     Target     "app" (the window), "model" (mabr.ui.analysis.Model) or
%                "view" (the active tab's own onCommand)
%     Mutating   true for a command that changes results; every one is
%                undoable (Ctrl+Z), which verify_offline_app checks
%     Label      what the command does, as a menu or the F1 sheet says it
%     Short      a few words for the hint strip ("" = not on the strip)
%     MenuTag    the Tag of the menu item that runs the same command ("")
%
%   "i" is "no response" everywhere (the user's own idiom), "n" normalises
%   the traces (the trace organizer's key), and notes are Ctrl+N.
%
%   See also mabr.ui.AnalysisApp.dispatchKey, mabr.ui.analysis.Model
%
% Daniel Stolzberg (c) 2026

    methods (Static)
        function T = spec()
            % The keymap table (see the class help for its columns).
            persistent cache
            if isempty(cache)
                cache = mabr.ui.analysis.Commands.build();
            end
            T = cache;
        end

        function id = lookup(key,mods,char,scope)
            % The command a key press runs, or "" when none.
            %
            %   key    the KeyPressFcn's Key (any case)
            %   mods   its Modifier: cell/string array of names, or a joined
            %          string ("control+shift"); order and "command" ignored
            %   char   its Character ("" when unknown)
            %   scope  string array of scopes, highest priority first, e.g.
            %          ["series","global"]; the first scope with a match wins
            %   id     (returned) 1x1 string
            if nargin < 3 || isempty(char), char = ""; end
            if nargin < 4 || isempty(scope), scope = "global"; end
            key   = lower(string(key));
            if isempty(key) || ismissing(key), key = ""; end
            mods  = mabr.ui.analysis.Commands.normalizeMods(mods);
            char  = string(char);
            if isempty(char) || ismissing(char), char = ""; end
            scope = lower(string(scope));
            T  = mabr.ui.analysis.Commands.spec();
            id = "";
            for s = reshape(scope,1,[])
                inScope = T.Scope == s;
                % By key name and the exact modifiers.
                k = find(inScope & T.Key == key & T.Key ~= "" & T.Modifiers == mods,1);
                if ~isempty(k), id = T.Id(k); return; end
                % By the character typed, for the symbol keys: shift is part of
                % how the symbol is typed on one layout and not on another, so
                % it is not compared.
                if char ~= ""
                    m2 = erase(erase(mods,"+shift"),"shift");
                    m2 = regexprep(m2,'^\+|\+$','');
                    k = find(inScope & T.Key == "" & T.Char == char & T.Modifiers == m2,1);
                    if ~isempty(k), id = T.Id(k); return; end
                end
            end
        end

        function S = sheet(scope)
            % The rows F1 and a hint strip show for one or more scopes: one row
            % per (Scope, Id), its keys joined ("Alt+← or Shift+←").
            %
            %   scope  string array of scopes (default every scope)
            %   S      (returned) table Keys, Command, Scope, Id
            T = mabr.ui.analysis.Commands.spec();
            if nargin < 1 || isempty(scope)
                scope = unique(T.Scope,'stable');
            end
            scope = lower(string(scope));
            Keys = strings(0,1); Command = Keys; Scope = Keys; Id = Keys;
            for s = reshape(scope,1,[])
                R = T(T.Scope == s & T.Key + T.Char ~= "",:);
                [ids,first] = unique(R.Id,'stable');
                for i = 1:numel(ids)
                    rows = R(R.Id == ids(i),:);
                    txt  = strings(height(rows),1);
                    for r = 1:height(rows)
                        txt(r) = mabr.ui.analysis.Commands.rowKeyText(rows(r,:));
                    end
                    Keys(end+1,1)    = strjoin(unique(txt,'stable')," or "); %#ok<AGROW>
                    Command(end+1,1) = R.Label(first(i)); %#ok<AGROW>
                    Scope(end+1,1)   = s; %#ok<AGROW>
                    Id(end+1,1)      = ids(i); %#ok<AGROW>
                end
            end
            S = table(Keys,Command,Scope,Id);
        end

        function S = gestures(scope)
            % What the mouse does on a tab that no key does -- dragging a
            % threshold divider, above all, which nothing else would tell a
            % user exists -- in sheet()'s columns (Keys, Command, Scope, Id),
            % for the F1 window to list after the keys. Ids "mouse.*" are not
            % commands: lookup never returns them, and no key runs them.
            %   scope  string array of scopes (default every scope)
            %   S      (returned) table Keys, Command, Scope, Id
            G = mabr.ui.analysis.Commands.gestureRows();
            if nargin >= 1 && ~isempty(scope)
                G = G(ismember(G.Scope,lower(string(scope))),:);
            end
            S = G(:,{'Keys','Command','Scope','Id'});
        end

        function s = hint(scope,opts)
            % One line for the strip under a view: the scope's own mouse
            % gesture first where it has one (the threshold drag), then its
            % keys (not the global ones), short labels, "F1 all keys" at the
            % end.
            %   scope          one scope ("series")
            %   opts.MaxChars  at most this many characters (default Inf):
            %                  the parts that fit, in order, then "F1 all
            %                  keys" -- a strip cut off mid-word says nothing
            %                  about the keys it lost
            %   s              (returned) 1x1 string
            arguments
                scope
                opts.MaxChars (1,1) double = Inf
            end
            T = mabr.ui.analysis.Commands.spec();
            scope = lower(string(scope));
            R = T(T.Scope == scope & T.Short ~= "" & T.Key + T.Char ~= "",:);
            G = mabr.ui.analysis.Commands.gestureRows();
            parts = reshape(G.Short(G.Scope == scope & G.Short ~= ""),[],1);
            [ids,first] = unique(R.Id,'stable');
            for i = 1:numel(ids)
                rows = R(R.Id == ids(i),:);
                k = mabr.ui.analysis.Commands.rowKeyText(rows(1,:));
                parts(end+1,1) = k + " " + R.Short(first(i)); %#ok<AGROW>
            end
            tail = "F1 all keys";
            if isfinite(opts.MaxChars)
                sep = strlength(" · ");
                room = opts.MaxChars - strlength(tail);
                used = 0;  keep = 0;
                for i = 1:numel(parts)
                    add = strlength(parts(i)) + sep;
                    if used + add > room, break; end
                    used = used + add;  keep = i;
                end
                parts = parts(1:keep);
            end
            parts(end+1,1) = tail;
            s = strjoin(parts," · ");
        end

        function s = keyText(id)
            % The keys of a command for a menu caption: "Ctrl+O",
            % "Ctrl+Y or Ctrl+Shift+Z", "" when it has none.
            T = mabr.ui.analysis.Commands.spec();
            R = T(T.Id == string(id) & T.Key + T.Char ~= "",:);
            txt = strings(height(R),1);
            for r = 1:height(R)
                txt(r) = mabr.ui.analysis.Commands.rowKeyText(R(r,:));
            end
            txt = unique(txt,'stable');
            s = strjoin(txt," or ");
            if isempty(txt), s = ""; end
        end

        function r = row(id)
            % The first spec row of a command (a 1-row table; empty if none).
            T = mabr.ui.analysis.Commands.spec();
            r = T(find(T.Id == string(id),1),:);
        end

        function ids = ids()
            % Every command Id, once each, in table order.
            ids = unique(mabr.ui.analysis.Commands.spec().Id,'stable');
        end

        function m = normalizeMods(mods)
            % Modifier names as a canonical joined string ("control+shift").
            if isempty(mods)
                m = "";
                return
            end
            if ischar(mods) || (isstring(mods) && isscalar(mods))
                mods = split(string(mods),"+");
            end
            mods = lower(string(mods));
            mods(mods == "command") = "control";
            mods = intersect(mods,["alt","control","shift"]);   % sorted, unique
            m = strjoin(mods,"+");
            if isempty(mods), m = ""; end
        end

        function s = displayKey(key)
            % A key name as people write it: "↑", "Enter", "Ctrl", "PgUp".
            key = lower(string(key));
            names = ["uparrow","downarrow","leftarrow","rightarrow","return","escape", ...
                "delete","backspace","pageup","pagedown","equal","hyphen","add","subtract","space"];
            shown = ["↑","↓","←","→","Enter","Esc","Delete","Backspace","PgUp","PgDn", ...
                "=","−","Num +","Num −","Space"];
            k = find(names == key,1);
            if ~isempty(k)
                s = shown(k);
            elseif startsWith(key,"f") && strlength(key) > 1 && all(isstrprop(extractAfter(key,1),'digit'))
                s = upper(key);
            else
                s = key;
            end
        end
    end

    methods (Static, Access = private)
        function s = rowKeyText(r)
            % "Ctrl+Shift+E", "Alt+↓", "a", "Shift+1", "+".
            mods = r.Modifiers;
            if r.Key == ""
                k = r.Char;
            else
                k = mabr.ui.analysis.Commands.displayKey(r.Key);
            end
            parts = strings(1,0);
            if contains(mods,"control"), parts(end+1) = "Ctrl"; end
            if contains(mods,"alt"),     parts(end+1) = "Alt"; end
            if contains(mods,"shift"),   parts(end+1) = "Shift"; end
            if ~isempty(parts) && strlength(k) == 1 && isletter(char(k))
                k = upper(k);
            end
            s = strjoin([parts k],"+");
        end

        function T = build()
            % The rows. Scopes are written as a list and expanded, one row
            % per scope.
            C = {};
            function add(id,key,mods,ch,scopes,target,mut,label,short,menu)
                for sc = reshape(string(scopes),1,[])
                    C(end+1,:) = {string(id),string(key),string(mods),string(ch),sc, ...
                        string(target),logical(mut),string(label),string(short),string(menu)}; %#ok<AGROW>
                end
            end
            nav  = ["grid","series","trials","session"];
            gs   = ["grid","series"];
            gst  = ["grid","series","trials"];

            % ---- global -------------------------------------------------------
            add("file.open","o","control","","global","app",false,"Open data folder…","","AnalysisMenuOpen");
            add("file.rescan","f5","","","global","model",false,"Rescan folder","","AnalysisMenuRescan");
            add("file.save","s","control","","global","model",false,"Save now","","AnalysisMenuSave");
            add("file.export","e","control","","global","app",false,"Export…","","AnalysisMenuExport");
            add("file.exportAgain","e","control+shift","","global","model",false,"Export again","","AnalysisMenuExportAgain");
            add("file.exportScript","","","","global","model",false,"Export analysis script…","","AnalysisMenuExportScript");
            add("edit.undo","z","control","","global","model",false,"Undo","","AnalysisMenuUndo");
            add("edit.redo","y","control","","global","model",false,"Redo","","AnalysisMenuRedo");
            add("edit.redo","z","control+shift","","global","model",false,"Redo","","AnalysisMenuRedo");
            add("edit.note","n","control","","global","app",false,"Note…","","AnalysisMenuNote");
            add("session.analyse","return","control","","global","model",false,"Analyse","","AnalysisMenuAnalyse");
            add("session.prev","pageup","control","","global","model",false,"Previous session","","AnalysisMenuPrevSession");
            add("session.next","pagedown","control","","global","model",false,"Next session","","AnalysisMenuNextSession");
            add("review.next","f","","","global","model",false,"Next needing review","","AnalysisMenuNextReview");
            add("review.prev","f","shift","","global","model",false,"Previous needing review","","AnalysisMenuPrevReview");
            tabs = ["Session","Grid","Series","Trials","Study"];
            for k = 1:numel(tabs)
                add("view.tab" + k,string(k),"control","","global","app",false,tabs(k) + " tab","", ...
                    "AnalysisMenuTab" + tabs(k));
            end
            add("view.browser","b","control","","global","app",false,"Show/hide browser","","AnalysisMenuBrowser");
            add("view.find","f","control","","global","app",false,"Find session","","AnalysisMenuFind");
            add("help.keys","f1","","","global","app",false,"Keyboard shortcuts","","AnalysisMenuKeys");
            add("nav.escape","escape","","","global","app",false,"Clear point / cancel drag / close editor","","");

            % ---- browser ------------------------------------------------------
            add("browser.open","return","","","browser","app",false,"Open the selected session","open","AnalysisMenuOpenSession");
            % (a project label, not a results edit -- so not Mutating -- and
            % undone with Ctrl+Z all the same)
            add("browser.hide","delete","","","browser","app",false, ...
                "Exclude and hide the selected sessions (Show ▸ Hidden lists them)","hide","AnalysisMenuHide");

            % ---- navigation ---------------------------------------------------
            add("nav.levelUp","uparrow","","",nav,"model",false,"Louder level","louder","");
            add("nav.levelDown","downarrow","","",nav,"model",false,"Quieter level","quieter","");
            add("nav.seriesPrev","leftarrow","","",["grid","trials","session"],"model",false,"Previous series","previous series","");
            add("nav.seriesNext","rightarrow","","",["grid","trials","session"],"model",false,"Next series","next series","");
            add("nav.seriesPrevPg","pageup","","",gst,"model",false,"Previous series","","");
            add("nav.seriesNextPg","pagedown","","",gst,"model",false,"Next series","","");
            add("series.left","leftarrow","","","series","view",false, ...
                "Previous candidate when a wave point is selected, else previous series","previous","");
            add("series.right","rightarrow","","","series","view",false, ...
                "Next candidate when a wave point is selected, else next series","next","");
            add("nav.openSeries","return","","",["grid","session"],"app",false,"Open series","open series","");
            add("nav.openTrials","return","shift","",gs,"app",false,"Open condition in Trials","trials","");

            % ---- thresholds ---------------------------------------------------
            add("thr.accept","a","","",gs,"model",true,"Accept fit","accept","");
            add("thr.atLevel","t","","",gs,"model",true,"Threshold at selected level","at level","");
            add("thr.noResponse","i","","",gs,"model",true,"No response","no response","");
            add("thr.allRespond","downarrow","alt","",gs,"model",true,"All levels respond","all respond","");
            add("thr.exclude","x","","",gs,"model",true,"Exclude (then note)","exclude","");
            add("thr.clear","c","","",gs,"model",true,"Clear decision","clear","");
            add("thr.override","d","","",gs,"model",true, ...
                "Cycle detection override (auto → response → none)","override","");

            % ---- peaks --------------------------------------------------------
            add("peak.autoPick","p","","","series","model",true,"Auto-pick series","auto-pick","");
            add("peak.retrack","u","","","series","model",true,"Re-track down","re-track","");
            add("peak.retrackOverwrite","u","shift","","series","model",true, ...
                "Re-track down, overwriting manual picks","","");
            roman = ["I","II","III","IV","V"];
            for k = 1:5
                sh = ""; if k == 1, sh = "wave peak (1–5)"; end
                add("peak.wave" + k,string(k),"","","series","view",false, ...
                    "Select wave " + roman(k) + " peak",sh,"");
            end
            for k = 1:5
                sh = ""; if k == 1, sh = "trough (Shift+1–5)"; end
                add("peak.trough" + k,string(k),"shift","","series","view",false, ...
                    "Select wave " + roman(k) + " trough",sh,"");
            end
            add("peak.nudgeLeft","leftarrow","alt","","series","model",true,"Nudge one sample earlier","nudge","");
            add("peak.nudgeLeft","leftarrow","shift","","series","model",true,"Nudge one sample earlier","","");
            add("peak.nudgeRight","rightarrow","alt","","series","model",true,"Nudge one sample later","","");
            add("peak.nudgeRight","rightarrow","shift","","series","model",true,"Nudge one sample later","","");
            add("peak.absent","delete","","","series","model",true,"Wave absent here","absent","");
            add("peak.absentBelow","delete","shift","","series","model",true,"Wave absent here and below","","");
            add("peak.revert","backspace","","","series","model",true,"Back to automatic pick","revert","");

            % ---- display ------------------------------------------------------
            add("view.normalize","n","","",gs,"view",false,"Normalise traces","normalise","");
            add("view.scaleUp","equal","","",gst,"view",false,"Scale up","scale","");
            add("view.scaleUp","equal","shift","",gst,"view",false,"Scale up","","");
            add("view.scaleUp","add","","",gst,"view",false,"Scale up","","");
            add("view.scaleUp","","","+",gst,"view",false,"Scale up","","");
            add("view.scaleDown","hyphen","","",gst,"view",false,"Scale down","","");
            add("view.scaleDown","subtract","","",gst,"view",false,"Scale down","","");
            add("view.scaleDown","","","-",gst,"view",false,"Scale down","","");
            add("view.spacingUp","uparrow","shift","",gs,"view",false,"More stack spacing","spacing","");
            add("view.spacingDown","downarrow","shift","",gs,"view",false,"Less stack spacing","","");
            add("view.resetZoom","0","control","",gst,"view",false,"Reset zoom","reset zoom","");

            % ---- trials -------------------------------------------------------
            add("trials.reject","r","","","trials","model",true,"Reject selected sweeps","reject","");
            add("trials.restore","r","shift","","trials","model",true,"Restore selected sweeps","restore","");

            T = cell2table(C,'VariableNames', ...
                {'Id','Key','Modifiers','Char','Scope','Target','Mutating','Label','Short','MenuTag'});
        end

        function G = gestureRows()
            % The mouse's rows (gestures(), and the hint strip's first part).
            drag = "Set the threshold: snaps half way between the two levels (the decision " + ...
                "t makes on the louder); Alt held, the exact value (0.1 dB); above the loudest " + ...
                "level, no response; below the quietest, all respond; Esc cancels, Ctrl+Z undoes";
            short = "drag green line: threshold (Alt exact)";
            R = {
                "Drag the green line",             drag,  "series", "mouse.thresholdDrag", short
                "Click or drag on the evidence plot's level axis", ...
                    "Set the threshold there, by the same rules (drag its green line, or click the " + ...
                    "band of sweep counts along the bottom)", "series", "mouse.thresholdAxis", ""
                "Click a trace",                   "Select that level; on the selected level, with a " + ...
                    "wave point selected, move the point to the nearest extremum", "series", "mouse.select", ""
                "Drag the selected wave point",    "Place it exactly where it is let go", "series", "mouse.peakDrag", ""
                "Drag the green line",             drag,  "grid",   "mouse.thresholdDrag", short
                "Click a trace",                   "Select that condition", "grid", "mouse.select", ""
                "Double-click a trace",            "Open the Series tab on it", "grid", "mouse.openSeries", ""};
            G = cell2table(R,'VariableNames',{'Keys','Command','Scope','Id','Short'});
            for v = string(G.Properties.VariableNames)
                G.(v) = string(G.(v));
            end
        end
    end
end
