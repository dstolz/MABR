classdef TestRunner < handle
% mabr.ui.TestRunner  Run the verification suite from the GUI.
%
%   mabr.ui.TestRunner opens a window listing every verify_*.m in tests/,
%   runs whichever ones are ticked, and reports for each a verdict, how long
%   it took, and everything it printed. It is the same suite
%   run_all_verifications runs, from the same files, called the same way --
%   this only decides which of them run and where the output lands.
%
%   Opened from the acquisition GUI's Help menu ("Verification Tests…"), or
%   standalone:  >> mabr.ui.TestRunner
%
%   The list is DISCOVERED, not hard-coded: whatever verify_*.m files sit in
%   tests/ are what appears, ordered the way run_all_verifications runs them
%   (parsed from that file), with anything it does not list falling in after.
%   So a newly written verification shows up here whether or not it has been
%   wired into the suite yet, and the two can never disagree about what a
%   test is called.
%
%   A test PASSES if it returns without throwing -- the contract
%   run_all_verifications already relies on, since every check inside these
%   files is an assert. Console output is captured per test with evalc and
%   kept even when the test throws, because the lines printed before the
%   failure are the ones that say how far it got.
%
%   Everything here runs with no audio hardware, EXCEPT the one deliberate
%   exception: "Use the rig…" re-runs verify_timing_loopback against the real
%   device with the channel mapping currently saved in prefs
%   (mabr.AudioSettings.loadPrefs), which is the rig diagnostic that file's
%   help describes. Tests that build an acquisition engine start a parallel
%   pool, so the first run of a session can take a minute before anything
%   appears.
%
%   See also run_all_verifications, mabr.ui.App.
%
% Daniel Stolzberg (c) 2026

    properties (SetAccess = private)
        % One entry per discovered test: Name/File/Summary describe it,
        % Selected/Status/Time/Message are what the last run made of it.
        Tests   struct = struct('Name',{},'File',{},'Summary',{}, ...
                               'Selected',{},'Status',{},'Time',{},'Message',{})
        % Public so a caller (verify_test_runner) can reach THIS window's
        % controls rather than whichever one findall happens to return -- a
        % run launched from the App's menu has two of these open at once.
        UIFigure
    end

    properties (Access = private)
        Table
        LogArea
        SummaryLabel
        HardwareCheck
        RunSelButton
        RunAllButton
        StopButton
        OpenButton
        Buttons        % everything disabled for the duration of a run
        Log       (1,:) cell = {}
        Running   (1,1) logical = false
        Cancelled (1,1) logical = false
        % Set when the window is closed mid-run: the run cannot be abandoned
        % where it stands (MATLAB is inside the test), so it is cancelled and
        % the figure torn down once the current test returns.
        CloseRequested (1,1) logical = false
        SelectedRow    (1,1) double  = 0
    end

    properties (Constant, Access = private)
        MaxLogLines = 4000;   % keep the textarea from growing without bound
        PassColor = [0 0.5 0];
        FailColor = [0.8 0.2 0];
        BusyColor = [0.1 0.3 0.7];
    end

    methods
        function obj = TestRunner()
            obj.Tests = mabr.ui.TestRunner.discover();
            obj.createComponents();
            obj.refreshTable();
            if isempty(obj.Tests)
                obj.setSummary('No verify_*.m files found — is the tests folder on the path?',obj.FailColor);
            else
                obj.setSummary(sprintf('%d tests found. Nothing has run yet.',numel(obj.Tests)));
            end
            if nargout == 0, clear obj; end
        end

        function delete(obj)
            mabr.ui.WindowPos.remember(obj.UIFigure,'TestRunner');
            try, delete(obj.UIFigure); end %#ok<TRYNC>
        end

        function raise(obj)
            % Bring the window forward -- what the App's menu item does when a
            % runner is already open, rather than building a second one.
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                figure(obj.UIFigure);
            end
        end
    end

    % ===================================================================
    methods (Access = private)
        function createComponents(obj)
            obj.UIFigure = uifigure('Name','MABR Verification Tests', ...
                'Position',[100 100 780 660], ...
                'CloseRequestFcn',@(~,~) obj.onClose());
            mabr.ui.WindowPos.restore(obj.UIFigure,'TestRunner',obj.UIFigure.Position,[620 480]);

            g = uigridlayout(obj.UIFigure,[5 1]);
            g.RowHeight   = {30,'1.4x',32,22,'1x'};
            g.ColumnWidth = {'1x'};
            g.RowSpacing  = 6;
            g.Padding     = [10 10 10 8];

            % --- Row 1: what a run costs, and the one hardware opt-in -------
            head = uigridlayout(g,[1 2]);
            head.Layout.Row = 1; head.Layout.Column = 1;
            head.ColumnWidth = {'1x',340};
            head.Padding = [0 0 0 0];
            note = uilabel(head,'WordWrap','on','FontColor',[0.3 0.3 0.3], ...
                'Text','No audio hardware required. Engine tests start a parallel pool — the first run can take a minute.');
            note.Layout.Row = 1; note.Layout.Column = 1;
            obj.HardwareCheck = uicheckbox(head, ...
                'Text','Use the rig for the timing loop-back', ...
                'Tooltip',['Run verify_timing_loopback against the real ASIO device with the ' ...
                           'channel mapping saved in prefs, instead of the hardware-free loopback. ' ...
                           'This is the rig diagnostic — nothing else in the list is affected.']);
            obj.HardwareCheck.Layout.Row = 1; obj.HardwareCheck.Layout.Column = 2;

            % --- Row 2: the tests ------------------------------------------
            obj.Table = uitable(g, ...
                'ColumnName',{'Run','Test','Status','Time (s)','Notes'}, ...
                'ColumnWidth',{40,190,72,66,'auto'}, ...
                'ColumnFormat',{'logical','char','char','char','char'}, ...
                'ColumnEditable',[true false false false false], ...
                'RowName',{}, ...
                'CellEditCallback',@(~,e) obj.onCellEdit(e), ...
                'CellSelectionCallback',@(~,e) obj.onCellSelect(e));
            obj.Table.Layout.Row = 2; obj.Table.Layout.Column = 1;

            % --- Row 3: transport ------------------------------------------
            b = uigridlayout(g,[1 8]);
            b.Layout.Row = 3; b.Layout.Column = 1;
            b.ColumnWidth = {104,84,70,'1x',60,60,104,84};
            b.Padding = [0 0 0 0];
            b.ColumnSpacing = 6;
            obj.RunSelButton = obj.button(b,1,'Run Selected','Run the ticked tests, in list order.', ...
                @() obj.runTests(find([obj.Tests.Selected])), [0.6 0.9 0.6]);
            obj.RunAllButton = obj.button(b,2,'Run All','Run every test in the list, ticked or not.', ...
                @() obj.runTests(1:numel(obj.Tests)));
            obj.StopButton = obj.button(b,3,'Stop', ...
                'Stop after the test now running finishes — a test in flight cannot be interrupted.', ...
                @() obj.onStop());
            obj.StopButton.Enable = 'off';
            obj.button(b,5,'All','Tick every test.',   @() obj.selectAll(true));
            obj.button(b,6,'None','Untick every test.',@() obj.selectAll(false));
            obj.OpenButton = obj.button(b,7,'Open Test File','Open the selected test in the MATLAB editor.', ...
                @() obj.onOpenFile());
            obj.button(b,8,'Clear Log','Empty the output pane below.',@() obj.clearLog());

            % Everything but Stop is dead while a run is in flight; Stop is the
            % complement, so it is not in this list. The table stays enabled --
            % it is what the user is watching — and setBusy takes its ticks
            % away instead.
            obj.Buttons = {obj.RunSelButton, obj.RunAllButton, obj.OpenButton, ...
                           obj.HardwareCheck};

            % --- Row 4: verdict --------------------------------------------
            obj.SummaryLabel = uilabel(g,'Text','','FontWeight','bold');
            obj.SummaryLabel.Layout.Row = 4; obj.SummaryLabel.Layout.Column = 1;

            % --- Row 5: what the tests printed ------------------------------
            obj.LogArea = uitextarea(g,'Editable','off','FontName','Consolas', ...
                'Value',{''}, ...
                'Tooltip','Console output of each test, captured as it ran.');
            obj.LogArea.Layout.Row = 5; obj.LogArea.Layout.Column = 1;
        end

        function h = button(~,parent,col,text,tip,fcn,rgb)
            h = uibutton(parent,'Text',text,'Tooltip',tip, ...
                'ButtonPushedFcn',@(~,~) fcn());
            if nargin > 6, h.BackgroundColor = rgb; h.FontWeight = 'bold'; end
            h.Layout.Row = 1; h.Layout.Column = col;
        end

        % --- Running --------------------------------------------------------
        function runTests(obj,idx)
            if obj.Running, return; end
            idx = reshape(idx,1,[]);
            if isempty(idx)
                obj.setSummary('Nothing ticked — tick a test or press Run All.',obj.FailColor);
                return
            end
            obj.Running = true; obj.Cancelled = false;
            obj.setBusy(true);

            % Clear the verdicts about to be replaced and leave the rest of the
            % board alone, so re-running one test does not blank the others.
            [obj.Tests(idx).Status]  = deal('queued');
            [obj.Tests(idx).Time]    = deal(NaN);
            [obj.Tests(idx).Message] = deal('');
            obj.refreshTable();

            nPass = 0; nFail = 0; nSkip = 0;
            tAll = tic;
            for i = 1:numel(idx)
                if ~isvalid(obj), return; end
                k = idx(i);
                if obj.Cancelled
                    obj.Tests(k).Status = 'skipped';
                    nSkip = nSkip + 1;
                    continue
                end
                name = obj.Tests(k).Name;
                args = obj.argsFor(name);

                obj.Tests(k).Status = 'running…';
                obj.refreshTable();
                obj.setSummary(sprintf('Running %s — %d of %d…',name,i,numel(idx)),obj.BusyColor);
                obj.appendLog(sprintf('---- %s  [%s] ----', ...
                    name,char(datetime('now','Format','HH:mm:ss'))));
                drawnow

                t0 = tic;
                [ok,msg,out] = mabr.ui.TestRunner.runOne(str2func(name),args);
                elapsed = toc(t0);

                % The window can be closed while a test is running (tests
                % pause(), so callbacks fire); everything below touches it.
                if ~isvalid(obj) || isempty(obj.UIFigure) || ~isvalid(obj.UIFigure)
                    return
                end

                obj.appendLog(out);
                obj.Tests(k).Time = elapsed;
                if ok
                    obj.Tests(k).Status  = 'PASS';
                    obj.Tests(k).Message = '';
                    nPass = nPass + 1;
                    obj.appendLog(sprintf('   PASS  %s (%.1f s)',name,elapsed));
                else
                    obj.Tests(k).Status  = 'FAIL';
                    obj.Tests(k).Message = firstLine(msg);
                    nFail = nFail + 1;
                    obj.appendLog(sprintf('   FAIL  %s (%.1f s): %s',name,elapsed,firstLine(msg)));
                end
                obj.appendLog('');
                obj.refreshTable();
                drawnow
            end

            if ~isvalid(obj), return; end
            obj.Running = false;
            if obj.CloseRequested
                delete(obj);
                return
            end
            obj.setBusy(false);
            obj.refreshTable();

            txt = sprintf('%d passed, %d failed',nPass,nFail);
            if nSkip > 0, txt = sprintf('%s, %d skipped',txt,nSkip); end
            txt = sprintf('%s — %.1f s total.',txt,toc(tAll));
            if nFail > 0
                obj.setSummary(txt,obj.FailColor);
            else
                obj.setSummary(txt,obj.PassColor);
            end
            obj.appendLog(sprintf('==== %s ====',txt));
            obj.appendLog('');
            % A test that draws (live plot, trace organizer, timing loop-back)
            % leaves its figure on top; put the results back in front once,
            % rather than snatching focus after every test.
            obj.raise();
        end

        function args = argsFor(obj,name)
            % The suite takes no arguments -- with one exception. Its help
            % calls verify_timing_loopback with Testing=false the rig
            % diagnostic, and a diagnostic run against defaults would be
            % measuring the wrong wiring, so hand it whatever device, sample
            % rate, and channel mapping the rig actually has saved -- the rate
            % included, since a loop-back characterised at a rate the rig never
            % runs at is a measurement of nothing.
            args = {};
            if ~obj.HardwareCheck.Value, return; end
            switch name
                case 'verify_timing_loopback'
                    a = mabr.AudioSettings.loadPrefs();
                    args = {'Testing',false,'Device',a.Device, ...
                            'SampleRate',a.SampleRate, ...
                            'PlayerChannels',a.PlayerChannels, ...
                            'RecorderChannels',a.RecorderChannels};
            end
        end

        function onStop(obj)
            if ~obj.Running, return; end
            obj.Cancelled = true;
            obj.StopButton.Enable = 'off';
            obj.setSummary('Stopping after the current test…',obj.BusyColor);
            drawnow limitrate
        end

        % --- Table ----------------------------------------------------------
        function refreshTable(obj)
            if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure), return; end
            n = numel(obj.Tests);
            d = cell(n,5);
            for i = 1:n
                t = obj.Tests(i);
                d{i,1} = t.Selected;
                d{i,2} = t.Name;
                d{i,3} = t.Status;
                if isnan(t.Time), d{i,4} = ''; else, d{i,4} = sprintf('%.1f',t.Time); end
                % The description earns its place until there is something more
                % specific to say; a failure message is exactly that.
                if isempty(t.Message), d{i,5} = t.Summary; else, d{i,5} = t.Message; end
            end
            obj.Table.Data = d;

            % Styles are re-applied wholesale so the board can only ever show
            % the verdicts currently in Tests.
            removeStyle(obj.Table);
            obj.styleRows(strcmp({obj.Tests.Status},'PASS'),obj.PassColor);
            obj.styleRows(strcmp({obj.Tests.Status},'FAIL'),obj.FailColor);
            obj.styleRows(strcmp({obj.Tests.Status},'running…'),obj.BusyColor);
        end

        function styleRows(obj,mask,rgb)
            rows = find(mask);
            if isempty(rows), return; end
            addStyle(obj.Table,uistyle('FontColor',rgb,'FontWeight','bold'), ...
                'cell',[rows(:) 3*ones(numel(rows),1)]);
        end

        function onCellEdit(obj,e)
            if isempty(e.Indices) || e.Indices(2) ~= 1, return; end
            obj.Tests(e.Indices(1)).Selected = logical(e.NewData);
        end

        function onCellSelect(obj,e)
            if isempty(e.Indices), return; end
            obj.SelectedRow = e.Indices(1);
        end

        function selectAll(obj,tf)
            if isempty(obj.Tests), return; end
            [obj.Tests.Selected] = deal(tf);
            obj.refreshTable();
        end

        function onOpenFile(obj)
            if obj.SelectedRow < 1 || obj.SelectedRow > numel(obj.Tests)
                obj.setSummary('Select a row first.',obj.FailColor);
                return
            end
            edit(obj.Tests(obj.SelectedRow).File);
        end

        % --- Output pane ----------------------------------------------------
        function appendLog(obj,txt)
            if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure), return; end
            if isempty(txt), lines = {''};
            elseif ischar(txt) || isstring(txt)
                lines = regexp(char(txt),'\r\n|\n|\r','split');
            else
                lines = cellstr(txt(:)');
            end
            % A trailing newline in captured output would otherwise add a blank
            % line to every block.
            if numel(lines) > 1 && isempty(lines{end}), lines(end) = []; end
            obj.Log = [obj.Log lines];
            if numel(obj.Log) > obj.MaxLogLines
                obj.Log = [{'… earlier output trimmed …'}, ...
                           obj.Log(end-obj.MaxLogLines+1:end)];
            end
            obj.LogArea.Value = obj.Log;
            try, scroll(obj.LogArea,'bottom'); end %#ok<TRYNC>
        end

        function clearLog(obj)
            obj.Log = {};
            obj.LogArea.Value = {''};
        end

        % --- Small helpers --------------------------------------------------
        function setBusy(obj,busy)
            for i = 1:numel(obj.Buttons)
                obj.Buttons{i}.Enable = onOff(~busy);
            end
            obj.StopButton.Enable = onOff(busy);
            if busy, obj.UIFigure.Pointer = 'watch'; else, obj.UIFigure.Pointer = 'arrow'; end
        end

        function setSummary(obj,txt,rgb)
            if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure), return; end
            if nargin < 3, rgb = [0.15 0.15 0.15]; end
            obj.SummaryLabel.Text = txt;
            obj.SummaryLabel.FontColor = rgb;
            drawnow limitrate
        end

        function onClose(obj)
            if obj.Running
                % MATLAB is inside a test; it will return, see this, and tear
                % the window down then. Saying so beats a window that ignores
                % the close box.
                obj.CloseRequested = true;
                obj.Cancelled = true;
                obj.setSummary('Closing once the current test finishes…',obj.BusyColor);
                return
            end
            delete(obj);
        end
    end

    % ===================================================================
    % Hidden rather than private: runOne evaluates guarded through evalc, and
    % that call is resolved by name.
    methods (Static, Hidden)
        function [ok,msg,out] = runOne(fcn,args) %#ok<INUSD>
            % (fcn and args look unused because the evalc'd statement is what
            % reads them.)
            % Run one verification with its console output captured. The
            % try/catch lives INSIDE the captured region (guarded) so a
            % failure keeps everything the test printed before it threw --
            % which is the part that says how far it got. evalc itself is
            % wrapped only so a capture failure cannot take the window with it.
            ok = false; msg = 'the test could not be run'; out = '';
            try
                out = evalc('[ok,msg] = mabr.ui.TestRunner.guarded(fcn,args);');
            catch me
                msg = me.message;
            end
        end

        function [ok,msg] = guarded(fcn,args)
            % Pass = returns without throwing, the same contract
            % run_all_verifications uses (every check inside these files is an
            % assert). The report is printed, not just returned, so the stack
            % lands in the log next to the output that preceded it.
            ok = true; msg = '';
            try
                fcn(args{:});
            catch me
                ok = false;
                msg = me.message;
                fprintf('%s\n',getReport(me,'extended','hyperlinks','off'));
            end
        end
    end

    % ===================================================================
    methods (Static, Access = private)
        function tests = discover()
            % Every verify_*.m in tests/ becomes a row. Nothing is hard-coded
            % here: a test that exists is a test that can be run, whether or
            % not run_all_verifications has been taught about it yet.
            tests = struct('Name',{},'File',{},'Summary',{}, ...
                           'Selected',{},'Status',{},'Time',{},'Message',{});
            folder = mabr.ui.TestRunner.testsFolder();
            if isempty(folder), return; end
            d = dir(fullfile(folder,'verify_*.m'));
            if isempty(d), return; end

            names = cellfun(@(f) f(1:end-2),{d.name},'UniformOutput',false);
            names = mabr.ui.TestRunner.suiteOrder(folder,names);

            % The tests folder is normally on the path (MABR.m genpath-adds
            % it), but the window can be opened from a bare MATLAB where it is
            % not, and feval would then fail on files sitting right there.
            if isempty(which(names{1})), addpath(folder); end

            for i = 1:numel(names)
                file = fullfile(folder,[names{i} '.m']);
                tests(i).Name     = names{i};
                tests(i).File     = file;
                tests(i).Summary  = mabr.ui.TestRunner.summaryOf(file,names{i});
                tests(i).Selected = true;
                tests(i).Status   = '';
                tests(i).Time     = NaN;
                tests(i).Message  = '';
            end
        end

        function folder = testsFolder()
            % Prefer wherever the suite actually is on the path; fall back to
            % the layout in the repo, so the window still works before MABR.m
            % has ever run.
            folder = '';
            p = which('run_all_verifications');
            if ~isempty(p)
                folder = fileparts(p);
                return
            end
            here = fileparts(mfilename('fullpath'));            % +mabr/+ui
            root = fileparts(fileparts(here));                  % repo root
            guess = fullfile(root,'tests');
            if isfolder(guess), folder = guess; end
        end

        function names = suiteOrder(folder,names)
            % Order the list the way run_all_verifications runs it, by reading
            % the order out of that file rather than repeating it here. Files
            % it does not mention keep their alphabetical place at the end --
            % visible, but after the ones the suite vouches for.
            suite = fullfile(folder,'run_all_verifications.m');
            if ~isfile(suite), return; end
            try
                txt = fileread(suite);
            catch
                return
            end
            listed = regexp(txt,'@(verify_\w+)','tokens');
            if isempty(listed), return; end
            listed = unique([listed{:}],'stable');
            known  = listed(ismember(listed,names));
            names  = [known, sort(setdiff(names,known))];
        end

        function s = summaryOf(file,name)
            % The H1 line, minus the function name it repeats.
            s = '';
            try
                fid = fopen(file,'r');
                if fid < 0, return; end
                c = onCleanup(@() fclose(fid));
                fgetl(fid);                       % the function signature
                ln = fgetl(fid);
                if ~ischar(ln), return; end
                s = strtrim(regexprep(ln,'^%+\s*',''));
                s = strtrim(regexprep(s,['^' name '\s*'],''));
            catch
                s = '';
            end
        end
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function s = firstLine(msg)
% Table cells are one line high; the rest of the message is in the log.
if isempty(msg), s = ''; return; end
lines = regexp(char(msg),'\r\n|\n|\r','split');
s = strtrim(lines{1});
if numel(s) > 140, s = [s(1:137) '…']; end
end
