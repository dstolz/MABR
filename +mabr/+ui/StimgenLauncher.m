classdef StimgenLauncher < handle
% mabr.ui.StimgenLauncher  One window to open every stimgen tool, on one rig.
%
%   mabr.ui.StimgenLauncher            open (or raise) the launcher
%   L = mabr.ui.StimgenLauncher(Name,Value,...)
%
%   stimgen ships four windows -- the stimulus designer (StimPlayer), the
%   calibration tool (CalibrationGui), the spot check (SpotCheck) and the
%   stimulus inspector (StimInspector) -- and each of them wants to be told the
%   same things when it opens: which device, at what rate, through which
%   microphone channel, against which calibration. Opened one at a time from
%   the command line each is told none of it, so the operator re-enters the rig
%   four times and the four windows can disagree about what the rig is.
%
%   This is the one place that is said. The RIG panel holds three answers and
%   hands them to every tool it opens:
%
%     Hardware      where measurements are made -- the MABR rig (the ASIO
%                   device, output channel, microphone input and sample rate
%                   in mabr.AudioSettings, measured through
%                   mabr.stim.CalibrationAdapter so the timing loop-back takes
%                   the device round trip out of every record), a plain
%                   Windows sound card (stimgen's own adapter, on the same
%                   device/rate/mic settings), or nothing (windows open
%                   offline: file inspection and speaker preview only).
%     Audio         the mabr.AudioSettings behind it, edited in the same
%                   dialog the main window uses -- launched from mabr.ui.App
%                   it IS the app's setting and a Commit there reaches the
%                   whole toolbox; standalone it is the saved preference.
%     Calibration   one stimgen.calibration.Engine shared by the calibration
%                   window and every spot check, so a calibration loaded (or
%                   measured) in one is the calibration the other reads. Its
%                   file is remembered, and handed to each designer so a bank
%                   opens already calibrated.
%
%   What each tool receives beyond that: the designer opens at the rig's sample
%   rate, in the last folder used, optionally on a bank, with capture routed
%   through the rig (its Capture button records through the same microphone
%   the calibration measured with); the spot check and the calibration window
%   are handed the shared engine with the rig's adapter attached.
%
%   A tool that cannot reach the rig still opens. Test Mode on, a device that
%   will not open, or Hardware set to Offline each leave the window usable for
%   what does not need hardware, and the status line says why the rest is off --
%   a launcher that refused would hide the very windows you would use to fix
%   the setup.
%
%   The launcher writes nothing a tool does not ask it to. Its own settings --
%   the hardware choice, the calibration file, the folder, the recent files --
%   persist in the MABR pref group ('StimgenTools') and, for the first two,
%   travel in a .mabrcfg (configStruct/applyStruct), so a named protocol
%   reopens on the rig it was made for.
%
%   Optional stimgen: a clone without the submodule cannot build one of these
%   (mabr.stim.stimgenAvailable says so, with the fix in the message).
%
%   See also mabr.stim.CalibrationAdapter, mabr.AudioSettings,
%            mabr.stim.stimgenAvailable, stimgen.StimPlayer.
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        Tag        = 'MABR_StimgenLauncher'
        PrefName   = 'StimgenTools'
        WindowName = 'StimgenLauncher'   % mabr.ui.WindowPos key
        MaxRecent  = 10
        MaxInspectors = 6                % windows one file may open at once
        Sources      = {'mabr','soundcard','offline'}
        SourceLabels = {'MABR rig (ASIO, loop-back timed)', ...
                        'Sound card (Windows audio)', ...
                        'Offline (no hardware)'}
        WikiURL  = 'https://github.com/dstolz/stimgen/wiki'
        GuideURL = 'https://github.com/dstolz/stimgen/wiki/Calibrating-Your-Rig'
    end

    properties (SetAccess = private)
        Figure
        Settings struct      % see defaults()
        Engine               % shared stimgen.calibration.Engine, or [] until first needed
    end

    properties
        % Where the audio settings come from, when something else owns them.
        % mabr.ui.App passes its own so the launcher reads the setting the
        % rest of the window is running on rather than a second copy that
        % could drift; empty means "the saved preference".
        AudioFcn = []
        % Called with the settings the audio dialog commits. Empty: the
        % launcher keeps them itself (and saves them to the preference).
        AudioApplyFcn = []
        % Returns the acquisition controller, so a measurement can refuse
        % while a schedule holds the ASIO device (see mabr.stim.CalibrationAdapter).
        ControllerFcn = []
    end

    properties (Access = private)
        OwnAudio                 % mabr.AudioSettings, used when AudioFcn is empty
        H struct = struct()      % UI handles
        Adapter = []             % adapter last handed to the shared engine
        CalGui = []              % the open CalibrationGui, if any
        CalGuiEngine = []        % the engine it was opened on
    end

    % ===================================================================
    methods
        function obj = StimgenLauncher(opts)
            arguments
                opts.AudioFcn = []
                opts.AudioApplyFcn = []
                opts.ControllerFcn = []
                opts.Settings = []
                opts.Show (1,1) logical = true
            end
            [ok,why] = mabr.stim.stimgenAvailable();
            if ~ok
                error('mabr:ui:StimgenLauncher:noStimgen','%s',why);
            end

            obj.AudioFcn      = opts.AudioFcn;
            obj.AudioApplyFcn = opts.AudioApplyFcn;
            obj.ControllerFcn = opts.ControllerFcn;
            if isempty(opts.Settings)
                obj.Settings = mabr.ui.StimgenLauncher.loadPrefs();
            else
                obj.Settings = mabr.ui.StimgenLauncher.sanitize(opts.Settings);
            end
            if isempty(obj.AudioFcn)
                obj.OwnAudio = mabr.AudioSettings.loadPrefs();
            end

            obj.build(opts.Show);
            obj.restoreCalibration();
            obj.syncRig();
            obj.setStatus('Ready. Pick a tool — the rig below is passed along to each.');
        end

        function delete(obj)
            try, mabr.ui.WindowPos.remember(obj.Figure,obj.WindowName); end %#ok<TRYNC>
            try, delete(obj.Figure); end %#ok<TRYNC>
            % An adapter holding an open device must let go of it: the
            % launcher may be the last thing that knew it was there, and an
            % ASIO device has exactly one owner.
            try, delete(obj.Adapter); end %#ok<TRYNC>
        end

        function show(obj)
            % Raise the window, restoring it first if it was minimized.
            f = obj.Figure;
            if isempty(f) || ~isvalid(f), return; end
            if isprop(f,'WindowState') && strcmp(f.WindowState,'minimized')
                f.WindowState = 'normal';
            end
            figure(f);
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function close(obj)
            delete(obj);
        end

        % --- the rig -------------------------------------------------------
        function a = audio(obj)
            % The audio settings in force: the owner's if it gave us a way to
            % ask, else the saved preference.
            a = [];
            if ~isempty(obj.AudioFcn)
                try, a = obj.AudioFcn(); end %#ok<TRYNC>
            end
            if isempty(a)
                if isempty(obj.OwnAudio), obj.OwnAudio = mabr.AudioSettings.loadPrefs(); end
                a = obj.OwnAudio;
            end
        end

        function [txt,warn] = describeRig(obj)
            % One paragraph on where measurements will be made, and whether
            % that is actually possible right now. WARN is true when the
            % chosen hardware cannot be used as it stands, so the tools will
            % open offline.
            a = obj.audio();
            warn = false;
            switch obj.Settings.Source
                case 'mabr'
                    if a.Testing
                        warn = true;
                        txt = ['MABR Test Mode is on, so there is no device to measure ' ...
                               'through and the tools open offline. Turn it off in Audio ' ...
                               'settings to calibrate on the rig.'];
                    else
                        txt = sprintf('MABR rig — %s · output %d · microphone in %d', ...
                            a.describe(),a.PlayerChannels(1),a.MicChannel);
                    end
                case 'soundcard'
                    dev = a.Device;
                    if isempty(dev), dev = 'default Windows device'; end
                    txt = sprintf('Sound card — %s · %s kHz · output 1 · microphone in %d', ...
                        dev,mabr.Config.rateText(a.SampleRate),a.MicChannel);
                otherwise
                    txt = ['Offline — the tools open without hardware: stimulus design, ' ...
                           'speaker preview, and inspecting files.'];
            end
        end

        function txt = describeCalibration(obj)
            eng = obj.Engine;
            if isempty(eng) || ~isvalid(eng) || ~eng.IsCalibrated
                txt = 'none loaded';
                return
            end
            f = obj.Settings.CalibrationFile;
            if isempty(f)
                txt = 'measured this session (not saved to a file)';
            else
                [~,n,e] = fileparts(f);
                txt = [n e];
            end
            try
                ts = eng.CalibrationTimestamp;
                if ~isnat(ts), txt = [txt ' · ' char(ts,'yyyy-MM-dd')]; end
            catch
            end
        end

        function [ad,why] = resolveAdapter(obj)
            % The adapter the rig setting calls for -- the shared one (see
            % sharedAdapter), so the calibration window, the spot checks and
            % every designer play through one adapter. WHY says why there is
            % none.
            [ad,why] = mabr.ui.StimgenLauncher.sharedAdapter( ...
                obj.Settings.Source,obj.audio(),obj.controller());
            obj.Adapter = ad;
        end

        function [eng,why] = prepareEngine(obj)
            % The shared engine with the rig's adapter attached (or detached,
            % with WHY, when the rig cannot be reached).
            if isempty(obj.Engine) || ~isvalid(obj.Engine)
                obj.Engine = stimgen.calibration.Engine();
            end
            eng = obj.Engine;
            [ad,why] = obj.resolveAdapter();
            try
                eng.set_adapter(ad);
            catch me
                why = me.message;
            end
        end

        % --- the tools -----------------------------------------------------
        function sp = openDesigner(obj,bankFile)
            % The stimulus designer, opened on the rig: at its sample rate, in
            % the last folder used, with the remembered calibration applied
            % and capture routed through the rig's microphone.
            if nargin < 2, bankFile = ''; end
            sp = [];
            try
                a = obj.audio();
                sp = stimgen.StimPlayer();
                if isfolder(obj.Settings.LastFolder)
                    sp.DataPath = obj.Settings.LastFolder;
                end
                if ~isempty(bankFile)
                    sp.load_bank(bankFile);
                    obj.noteFile(bankFile);
                end
                % After the bank: assigning Fs regenerates every item, so
                % doing it last puts a loaded bank on the rig's clock too.
                [~,notes] = mabr.ui.StimgenLauncher.routeDesigner( ...
                    sp,obj.Settings.Source,a,obj.ControllerFcn);
                cal = obj.Settings.CalibrationFile;
                if ~isempty(cal) && isfile(cal)
                    sp.load_calibration_(cal);
                    [~,n,e] = fileparts(cal);
                    notes{end+1} = ['calibration ' n e];
                end
                msg = 'Designer opened';
                if ~isempty(notes), msg = [msg ' — ' strjoin(notes,' · ')]; end
                obj.setStatus([msg '.']);
            catch me
                obj.fail('Designer',me);
            end
        end

        function gui = openCalibration(obj)
            % The calibration window on the shared engine. One at a time: a
            % second window on the same engine would be a second place to
            % start a measurement the first is already running.
            gui = [];
            try
                [eng,why] = obj.prepareEngine();
                if ~isempty(obj.CalGui) && isvalid(obj.CalGui) && isequal(obj.CalGuiEngine,eng)
                    obj.CalGui.show();
                    gui = obj.CalGui;
                    obj.setStatus('Calibration window raised.');
                    return
                end
                obj.CalGui = stimgen.calibration.CalibrationGui(eng);
                obj.CalGuiEngine = eng;
                gui = obj.CalGui;
                obj.setStatus(obj.openedMessage('Calibration',why));
            catch me
                obj.fail('Calibration',me);
            end
        end

        function openSpotCheck(obj)
            % Play one stimulus through the rig and characterize what came
            % back, on the shared engine -- so it reads the calibration the
            % calibration window measured or loaded.
            try
                [eng,why] = obj.prepareEngine();
                stimgen.SpotCheck(eng);
                obj.setStatus(obj.openedMessage('Spot check',why));
            catch me
                obj.fail('Spot check',me);
            end
        end

        function n = openInspector(obj,file)
            % Inspect stimuli from a .spl bank or a .mat holding stimgen
            % stimuli, one window per pick. Nothing here needs hardware.
            n = 0;
            if nargin < 2 || isempty(file)
                file = obj.pickFile({'*.spl;*.mat','Stimulus Files (*.spl, *.mat)'; ...
                                     '*.spl','Stimulus Banks (*.spl)'; ...
                                     '*.mat','MAT Files (*.mat)'}, ...
                                    'Inspect Stimulus');
                if isempty(file), return; end
            end
            try
                items = mabr.ui.StimgenLauncher.loadStimuli(file);
                if isempty(items)
                    obj.setStatus(['No stimgen stimulus was found in ' file '.'],true);
                    return
                end
                pick = 1:numel(items);
                if numel(items) > 1
                    [~,base,ext] = fileparts(file);
                    [sel,ok] = listdlg('PromptString',sprintf('Inspect which of the %d stimuli in %s?', ...
                            numel(items),[base ext]), ...
                        'ListString',{items.Label},'SelectionMode','multiple', ...
                        'Name','Choose Stimuli','ListSize',[340 260]);
                    figure(obj.Figure);
                    if ~ok, return; end
                    pick = sel;
                end
                if numel(pick) > obj.MaxInspectors
                    obj.setStatus(sprintf(['Opening the first %d of the %d you picked — ' ...
                        'each is a window of its own.'],obj.MaxInspectors,numel(pick)));
                    pick = pick(1:obj.MaxInspectors);
                end
                for k = pick
                    st = items(k).Stim;
                    try
                        if isempty(st.Signal), st.update_signal; end
                    catch
                    end
                    stimgen.StimInspector(st,items(k).Label);
                    n = n + 1;
                end
                obj.noteFile(file);
                obj.setStatus(sprintf('Inspecting %d stimulus window(s) from %s.',n,file));
            catch me
                obj.fail('Inspector',me);
            end
        end

        % --- calibration ---------------------------------------------------
        function ok = loadCalibration(obj,file)
            % Make FILE the rig's calibration: it becomes the shared engine's,
            % is remembered, and is applied to every designer opened next.
            ok = false;
            if nargin < 2 || isempty(file)
                file = obj.pickFile({'*.esgc','Stim Calibration (*.esgc)'}, ...
                                    'Load Calibration');
                if isempty(file), return; end
            end
            try
                if ~isfile(file)
                    obj.forgetFile(file);
                    obj.setStatus(['Calibration file not found: ' file],true);
                    return
                end
                eng = stimgen.calibration.Engine.load(file);
                if isempty(eng), return; end
                obj.Engine = eng;
                obj.CalGui = []; obj.CalGuiEngine = [];
                obj.Settings.CalibrationFile = file;
                obj.noteFile(file);
                [~,n,e] = fileparts(file);
                obj.setStatus(['Calibration loaded: ' n e '. Calibration and Spot Check ' ...
                    'windows already open keep the one they were opened with.']);
                ok = true;
            catch me
                obj.fail('Load calibration',me);
            end
            obj.syncRig();
        end

        function clearCalibration(obj)
            obj.Engine = [];
            obj.CalGui = []; obj.CalGuiEngine = [];
            obj.Settings.CalibrationFile = '';
            mabr.ui.StimgenLauncher.savePrefs(obj.Settings);
            obj.syncRig();
            obj.setStatus('Calibration cleared — tools open uncalibrated.');
        end

        % --- settings ------------------------------------------------------
        function setSource(obj,src)
            src = char(src);
            if ~any(strcmp(src,obj.Sources))
                error('mabr:ui:StimgenLauncher:badSource', ...
                    'Hardware must be one of: %s.',strjoin(obj.Sources,', '));
            end
            obj.Settings.Source = src;
            mabr.ui.StimgenLauncher.savePrefs(obj.Settings);
            obj.syncRig();
        end

        function applyStruct(obj,s)
            % The configuration-file half of the settings (see configStruct):
            % the hardware choice and the calibration file. Recent files and
            % the folder are per-machine history and are left alone.
            merged = mabr.ui.StimgenLauncher.mergeConfig(obj.Settings,s);
            obj.Settings = merged;
            mabr.ui.StimgenLauncher.savePrefs(obj.Settings);
            obj.restoreCalibration();
            obj.syncRig();
        end

        function recent = recentFiles(obj)
            recent = obj.Settings.Recent;
        end
    end

    % ===================================================================
    methods (Static)
        % --- persistence ---------------------------------------------------
        function s = defaults()
            s = struct('Source','mabr','CalibrationFile','','LastFolder','', ...
                       'Recent',{{}});
        end

        function s = sanitize(s0)
            % Forgiving field by field, like every other loadPrefs here: a
            % pref from another version, or one edited by hand, must not stop
            % the window from opening.
            s = mabr.ui.StimgenLauncher.defaults();
            if ~isstruct(s0) || ~isscalar(s0), return; end
            if isfield(s0,'Source') && isText(s0.Source) && any(strcmp(char(s0.Source),mabr.ui.StimgenLauncher.Sources))
                s.Source = char(s0.Source);
            end
            if isfield(s0,'CalibrationFile') && isText(s0.CalibrationFile)
                s.CalibrationFile = char(s0.CalibrationFile);
            end
            if isfield(s0,'LastFolder') && isText(s0.LastFolder)
                s.LastFolder = char(s0.LastFolder);
            end
            if isfield(s0,'Recent') && (iscellstr(s0.Recent) || isstring(s0.Recent)) %#ok<ISCLSTR>
                r = cellstr(s0.Recent(:).');
                r = r(~cellfun(@isempty,r));
                [~,keep] = unique(lower(r),'stable');
                r = r(keep);
                s.Recent = r(1:min(numel(r),mabr.ui.StimgenLauncher.MaxRecent));
            end

            function tf = isText(v)
                tf = ischar(v) || (isstring(v) && isscalar(v));
            end
        end

        function s = loadPrefs()
            s = mabr.ui.StimgenLauncher.sanitize( ...
                getpref('MABR',mabr.ui.StimgenLauncher.PrefName,struct()));
        end

        function savePrefs(s)
            setpref('MABR',mabr.ui.StimgenLauncher.PrefName, ...
                mabr.ui.StimgenLauncher.sanitize(s));
        end

        function s = configStruct()
            % What a .mabrcfg carries of the launcher: the hardware choice and
            % the calibration file -- a protocol's rig -- and not the folder
            % or recent files, which are history of this machine.
            p = mabr.ui.StimgenLauncher.loadPrefs();
            s = struct('Source',p.Source,'CalibrationFile',p.CalibrationFile);
        end

        function saveConfigStruct(s)
            % Write a configuration's launcher block to the pref, over what
            % is there, without the launcher window having to exist.
            p = mabr.ui.StimgenLauncher.loadPrefs();
            mabr.ui.StimgenLauncher.savePrefs( ...
                mabr.ui.StimgenLauncher.mergeConfig(p,s));
        end

        function merged = mergeConfig(current,s)
            merged = mabr.ui.StimgenLauncher.sanitize(current);
            if ~isstruct(s) || ~isscalar(s), return; end
            keep = struct('Source',merged.Source,'CalibrationFile',merged.CalibrationFile);
            in = mabr.ui.StimgenLauncher.sanitize(mergeFields(keep,s));
            merged.Source = in.Source;
            merged.CalibrationFile = in.CalibrationFile;

            function k = mergeFields(k,src)
                for f = {'Source','CalibrationFile'}
                    if isfield(src,f{1}), k.(f{1}) = src.(f{1}); end
                end
            end
        end

        % --- hardware ------------------------------------------------------
        function [ad,why] = buildAdapter(source,a,controller)
            % The adapter for SOURCE on the audio settings A, or [] and why.
            % A static function of plain values, so a capture started from a
            % designer long after the launcher closed still builds one.
            ad = []; why = '';
            switch source
                case 'mabr'
                    if a.Testing
                        why = ['MABR Test Mode is on, so there is no device to measure ' ...
                               'through (Settings > Audio Device).'];
                        return
                    end
                    try
                        ad = mabr.stim.CalibrationAdapter(a,a.config(),controller);
                    catch me
                        why = me.message;
                    end
                case 'soundcard'
                    try
                        ad = stimgen.calibration.WindowsSoundCardAdapter( ...
                            SampleRate=a.SampleRate,Device=string(a.Device), ...
                            InputChannel=a.MicChannel);
                    catch me
                        why = me.message;
                    end
                otherwise
                    why = 'Hardware is set to Offline.';
            end
        end

        function [routed,notes] = routeDesigner(sp,source,a,controllerFcn)
            % Put the designer SP on the rig SOURCE names, on the audio
            % settings A: generated at the rig's sample rate, with capture
            % and hardware Play through the rig's adapter. The one place
            % that is done, so a designer the launcher opens and the one
            % behind mabr.ui.App's Design… button reach the same rig the
            % same way. ROUTED says whether Play reaches the rig; NOTES is
            % what there is to tell the operator. Offline leaves SP alone.
            routed = false; notes = {};
            if strcmp(source,'offline'), return; end
            sp.Fs = a.SampleRate;
            notes{end+1} = sprintf('%s kHz',mabr.Config.rateText(a.SampleRate));
            sp.CaptureAdapter = @() mabr.ui.StimgenLauncher.captureAdapter(source,a,controllerFcn);
            % The same adapter is the designer's hardware preview route (no
            % HardwareHost is attached), so Play reaches the rig at its
            % calibrated level rather than the computer speakers. Speakers
            % stay one dropdown away.
            try
                sp.PlaybackOutput = "Hardware";
                routed = true;
                notes{end+1} = 'play and capture through the rig';
            catch me
                mabr.log.vprintf(1,1,'stimgen designer: hardware preview unavailable: %s',me.message);
                notes{end+1} = 'capture through the rig (play on the speakers)';
            end
        end

        function ad = captureAdapter(source,a,controllerFcn)
            % Called by a designer at each capture and at each hardware
            % Play (StimPlayer.CaptureAdapter is also its preview route):
            % errors with the reason rather than returning [], since the
            % designer reports a thrown message where it would only say
            % "unavailable" for an empty one.
            ctl = [];
            if ~isempty(controllerFcn)
                try, ctl = controllerFcn(); catch, ctl = []; end
            end
            [ad,why] = mabr.ui.StimgenLauncher.sharedAdapter(source,a,ctl);
            if isempty(ad)
                error('mabr:ui:StimgenLauncher:noAdapter','%s',why);
            end
        end

        function [ad,why] = sharedAdapter(source,a,controller)
            % The one adapter this MATLAB session plays through, rebuilt
            % only when something it was built from changes. One, because a
            % sound-card adapter holds its device open and an ASIO device
            % has exactly one owner: the launcher's engine and a designer
            % each holding their own would leave the second unable to open
            % it. Reused, because a designer's Play All asks once per
            % combination and a fresh adapter would reopen the device (and
            % repeat its warnings) every time. Static and persistent rather
            % than the launcher's, so a designer outliving the launcher
            % still shares with whatever opens next.
            persistent lastKey lastAd lastCtl
            why = '';
            key = mabr.ui.StimgenLauncher.adapterKey(source,a);
            if ~isempty(lastAd) && isvalid(lastAd) && strcmp(key,lastKey) ...
                    && isequal(controller,lastCtl)
                ad = lastAd;
                return
            end
            % Let go of the old one before opening a new one on the same device.
            try, delete(lastAd); end %#ok<TRYNC>
            lastAd = []; lastKey = ''; lastCtl = [];
            [ad,why] = mabr.ui.StimgenLauncher.buildAdapter(source,a,controller);
            if ~isempty(ad)
                lastAd = ad; lastKey = key; lastCtl = controller;
            end
        end

        function key = adapterKey(source,a)
            % What an adapter is built from, as one comparable string.
            key = sprintf('%s|%s|%.10g|%d %d|%d %d|%d|%d',source,a.Device, ...
                a.SampleRate,a.PlayerChannels,a.RecorderChannels,a.MicChannel,a.Testing);
        end

        % --- files ---------------------------------------------------------
        function items = loadStimuli(file)
            % Every stimgen stimulus in FILE: the items of a StimPlayer .spl
            % bank, or the stimuli in a .mat (a live object, or a struct from
            % StimType.toStruct). Built through StimType.fromStruct, so each
            % arrives with its calibration and variant setup as it was saved.
            items = struct('Stim',{},'Label',{});
            S = load(file,'-mat');
            if isfield(S,'Items') && isfield(S,'NItems')
                for k = 1:double(S.NItems)
                    it = S.Items{k};
                    if ~isstruct(it) || ~isfield(it,'StimObj'), continue; end
                    try
                        st = stimgen.StimType.fromStruct(it.StimObj);
                    catch me
                        mabr.log.vprintf(1,'StimgenLauncher: bank item %d not readable: %s',k,me.message);
                        continue
                    end
                    label = sprintf('Item %d',k);
                    if isfield(it,'Name') && strlength(string(it.Name)) > 0
                        label = char(string(it.Name));
                    end
                    items(end+1) = struct('Stim',st,'Label',label); %#ok<AGROW>
                end
                return
            end
            names = fieldnames(S);
            for k = 1:numel(names)
                v = S.(names{k});
                st = [];
                if isa(v,'stimgen.StimType') && isscalar(v) && isvalid(v)
                    st = v;
                elseif isstruct(v) && isscalar(v) && isfield(v,'Class') && isfield(v,'UserProperties')
                    try
                        st = stimgen.StimType.fromStruct(v);
                    catch me
                        mabr.log.vprintf(1,'StimgenLauncher: "%s" not readable as a stimulus: %s', ...
                            names{k},me.message);
                    end
                end
                if ~isempty(st)
                    items(end+1) = struct('Stim',st,'Label',names{k}); %#ok<AGROW>
                end
            end
        end
    end

    % ===================================================================
    methods (Access = private)
        function ctl = controller(obj)
            ctl = [];
            if ~isempty(obj.ControllerFcn)
                try, ctl = obj.ControllerFcn(); catch, ctl = []; end
            end
        end

        function restoreCalibration(obj)
            % Load the remembered calibration file, if there is one and it
            % still exists. Never fatal: a calibration that has moved is a
            % status line, not a launcher that will not open.
            f = obj.Settings.CalibrationFile;
            if isempty(f), return; end
            if ~isfile(f)
                obj.Settings.CalibrationFile = '';
                obj.Engine = [];
                if isfield(obj.H,'Status')
                    obj.setStatus(['Remembered calibration not found, so tools open ' ...
                        'uncalibrated: ' f],true);
                end
                return
            end
            try
                obj.Engine = stimgen.calibration.Engine.load(f);
            catch me
                obj.Settings.CalibrationFile = '';
                obj.Engine = [];
                if isfield(obj.H,'Status')
                    obj.setStatus(['Could not load the remembered calibration: ' me.message],true);
                end
            end
        end

        function msg = openedMessage(obj,name,why)
            if isempty(why)
                msg = [name ' opened on the ' obj.describeRig() '.'];
            else
                msg = [name ' opened offline — ' why];
            end
        end

        function file = pickFile(obj,filter,title)
            start = obj.Settings.LastFolder;
            if ~isfolder(start), start = pwd; end
            [fn,pn] = uigetfile(filter,title,start);
            if ~isempty(obj.Figure) && isvalid(obj.Figure), figure(obj.Figure); end
            if isequal(fn,0), file = ''; else, file = fullfile(pn,fn); end
        end

        function noteFile(obj,file)
            % Remember a file the user chose: at the top of the recent list,
            % and its folder as where the next chooser starts.
            r = [{file} obj.Settings.Recent(:).'];
            [~,keep] = unique(lower(r),'stable');
            r = r(keep);
            obj.Settings.Recent = r(1:min(numel(r),obj.MaxRecent));
            p = fileparts(file);
            if isfolder(p), obj.Settings.LastFolder = p; end
            mabr.ui.StimgenLauncher.savePrefs(obj.Settings);
            obj.syncRecent();
        end

        function forgetFile(obj,file)
            r = obj.Settings.Recent;
            obj.Settings.Recent = r(~strcmpi(r,file));
            mabr.ui.StimgenLauncher.savePrefs(obj.Settings);
            obj.syncRecent();
        end

        function fail(obj,tool,me)
            mabr.log.vprintf(1,'StimgenLauncher: %s failed to open: %s',tool,me.message);
            obj.setStatus(sprintf('%s failed to open: %s',tool,me.message),true);
        end

        function setStatus(obj,msg,isError)
            if nargin < 3, isError = false; end
            if ~isfield(obj.H,'Status') || ~isvalid(obj.H.Status), return; end
            obj.H.Status.Text = msg;
            if isError
                obj.H.Status.FontColor = [0.75 0.15 0.15];
            else
                obj.H.Status.FontColor = [0.35 0.35 0.35];
            end
        end

        % --- window ----------------------------------------------------------
        function build(obj,show)
            vis = 'on'; if ~show, vis = 'off'; end
            f = uifigure('Name','MABR — stimgen Tools','Tag',obj.Tag, ...
                'Position',[140 120 580 650],'Resize','off','Visible',vis, ...
                'CloseRequestFcn',@(~,~) obj.close());
            mabr.ui.WindowPos.restore(f,obj.WindowName,f.Position);
            obj.Figure = f;

            obj.buildMenus(f);

            root = uigridlayout(f,[4 1]);
            root.RowHeight = {52,'1x',158,40};
            root.Padding = [16 12 16 12];
            root.RowSpacing = 10;

            % --- header
            hg = uigridlayout(root,[2 1]);
            hg.Padding = [0 0 0 0]; hg.RowSpacing = 0; hg.RowHeight = {30,'1x'};
            uilabel(hg,'Text','stimgen tools','FontSize',22,'FontWeight','bold');
            uilabel(hg,'Text','Design, calibrate and inspect stimuli — every window opened on the same rig.', ...
                'FontColor',[0.45 0.45 0.45]);

            % --- tools
            tg = uigridlayout(root,[2 2]);
            tg.Padding = [0 0 0 0]; tg.ColumnSpacing = 14; tg.RowSpacing = 10;
            tg.RowHeight = {'1x','1x'};
            obj.card(tg,1,1,'designer','Stimulus Designer', ...
                'Build and audition calibrated stimulus banks: tones, noise, clicks, sweeps, sound files.', ...
                @(~,~) obj.openDesigner());
            obj.card(tg,1,2,'calibration','Calibration', ...
                'Measure the speaker and microphone and build the level tables banks are calibrated with.', ...
                @(~,~) obj.openCalibration());
            obj.card(tg,2,1,'spotcheck','Spot Check', ...
                'Play one stimulus through the rig, record it, and compare it with what was asked for.', ...
                @(~,~) obj.openSpotCheck());
            obj.card(tg,2,2,'inspector','Stimulus Inspector', ...
                'Waveform, spectrum, spectrogram and distortion of any stimulus in a bank file. No hardware needed.', ...
                @(~,~) obj.openInspector());

            % --- rig
            rp = uipanel(root,'Title','Rig — passed to every tool');
            rg = uigridlayout(rp,[3 4]);
            rg.RowHeight = {24,'1x',24};
            rg.ColumnWidth = {78,'1x',100,70};
            rg.Padding = [10 6 10 8]; rg.RowSpacing = 6; rg.ColumnSpacing = 8;

            l = uilabel(rg,'Text','Hardware'); l.Layout.Row = 1; l.Layout.Column = 1;
            obj.H.Source = uidropdown(rg,'Items',obj.SourceLabels,'ItemsData',obj.Sources, ...
                'Tooltip',['MABR rig: the ASIO device and channels in Audio settings, with the ' ...
                           'timing loop-back removing the device round trip from every record.' newline ...
                           'Sound card: stimgen''s own Windows adapter on the same device, rate and mic input.' newline ...
                           'Offline: tools open with no hardware.'], ...
                'ValueChangedFcn',@(s,~) obj.onSource(s.Value));
            obj.H.Source.Layout.Row = 1; obj.H.Source.Layout.Column = 2;
            obj.H.AudioButton = uibutton(rg,'Text','Audio settings…', ...
                'Tooltip','Device, sample rate, channels and microphone input — the same dialog as Settings ▸ Audio Device.', ...
                'ButtonPushedFcn',@(~,~) obj.onAudio());
            obj.H.AudioButton.Layout.Row = 1; obj.H.AudioButton.Layout.Column = [3 4];

            obj.H.Rig = uilabel(rg,'Text','','WordWrap','on','VerticalAlignment','top');
            obj.H.Rig.Layout.Row = 2; obj.H.Rig.Layout.Column = [1 4];

            l = uilabel(rg,'Text','Calibration'); l.Layout.Row = 3; l.Layout.Column = 1;
            obj.H.Cal = uilabel(rg,'Text','');
            obj.H.Cal.Layout.Row = 3; obj.H.Cal.Layout.Column = 2;
            b = uibutton(rg,'Text','Load…','Tooltip','Load a .esgc calibration: shared by the calibration window and spot checks, and applied to each designer''s bank.', ...
                'ButtonPushedFcn',@(~,~) obj.loadCalibration());
            b.Layout.Row = 3; b.Layout.Column = 3;
            obj.H.ClearCal = uibutton(rg,'Text','Clear','Tooltip','Forget the calibration.', ...
                'ButtonPushedFcn',@(~,~) obj.clearCalibration());
            obj.H.ClearCal.Layout.Row = 3; obj.H.ClearCal.Layout.Column = 4;

            % --- status + help
            bg = uigridlayout(root,[1 2]);
            bg.Padding = [0 0 0 0]; bg.ColumnSpacing = 10; bg.ColumnWidth = {'1x',90};
            obj.H.Status = uilabel(bg,'Text','','WordWrap','on','VerticalAlignment','top', ...
                'FontColor',[0.35 0.35 0.35]);
            obj.H.Help = uibutton(bg,'Text','?  Help','FontWeight','bold', ...
                'Tooltip',['Open the stimgen wiki in your browser — how each of these tools works. ' ...
                           'The MABR wiki and the rig-calibration guide are under the Help menu.'], ...
                'ButtonPushedFcn',@(~,~) obj.openHelp());
            obj.H.Help.Layout.Column = 2;
        end

        function openHelp(obj,page)
            % The stimgen wiki (or a named page on it). Held here rather than
            % in mabr.ui.wikiURL, which is the address of MABR's own wiki.
            url = obj.WikiURL;
            if nargin > 1 && ~isempty(page), url = [url '/' page]; end
            web(url,'-browser');
        end

        function buildMenus(obj,f)
            fm = uimenu(f,'Text','&File');
            uimenu(fm,'Text','Open Bank in Designer…', ...
                'MenuSelectedFcn',@(~,~) obj.onOpenBank());
            uimenu(fm,'Text','Inspect Stimulus File…', ...
                'MenuSelectedFcn',@(~,~) obj.openInspector());
            uimenu(fm,'Text','Load Calibration…','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.loadCalibration());
            obj.H.RecentMenu = uimenu(fm,'Text','Recent Files');
            uimenu(fm,'Text','Close','Separator','on','MenuSelectedFcn',@(~,~) obj.close());

            hm = uimenu(f,'Text','&Help');
            uimenu(hm,'Text','stimgen Wiki', ...
                'MenuSelectedFcn',@(~,~) obj.openHelp());
            uimenu(hm,'Text','Calibrating Your Rig', ...
                'MenuSelectedFcn',@(~,~) web(obj.GuideURL,'-browser'));
            uimenu(hm,'Text','MABR Wiki','Separator','on', ...
                'MenuSelectedFcn',@(~,~) web(mabr.ui.wikiURL(''),'-browser'));
        end

        function card(obj,parent,row,col,key,title,desc,cb)
            g = uigridlayout(parent,[2 1]);
            g.Layout.Row = row; g.Layout.Column = col;
            g.Padding = [0 0 0 0]; g.RowSpacing = 8; g.RowHeight = {'1x',46};
            b = uibutton(g,'Text',title,'FontSize',14,'FontWeight','bold', ...
                'IconAlignment','top','Tooltip',desc,'ButtonPushedFcn',cb);
            icon = mabr.ui.StimgenLauncher.iconFile(key);
            if ~isempty(icon), b.Icon = icon; end
            d = uilabel(g,'Text',desc,'WordWrap','on','HorizontalAlignment','center', ...
                'VerticalAlignment','top','FontColor',[0.45 0.45 0.45]);
            obj.H.(['Card_' key]) = b;
            d.Tooltip = desc;
        end

        function syncRig(obj)
            if ~obj.isOpen(), return; end
            obj.H.Source.Value = obj.Settings.Source;
            [txt,warn] = obj.describeRig();
            obj.H.Rig.Text = txt;
            if warn
                obj.H.Rig.FontColor = [0.75 0.45 0.05];
            else
                obj.H.Rig.FontColor = [0.15 0.15 0.15];
            end
            obj.H.Cal.Text = obj.describeCalibration();
            obj.H.ClearCal.Enable = matlab.lang.OnOffSwitchState( ...
                ~isempty(obj.Engine) || ~isempty(obj.Settings.CalibrationFile));
            obj.syncRecent();
        end

        function syncRecent(obj)
            if ~isfield(obj.H,'RecentMenu') || ~isvalid(obj.H.RecentMenu), return; end
            delete(obj.H.RecentMenu.Children);
            r = obj.Settings.Recent;
            if isempty(r)
                uimenu(obj.H.RecentMenu,'Text','(none)','Enable','off');
                return
            end
            for k = 1:numel(r)
                [~,n,e] = fileparts(r{k});
                uimenu(obj.H.RecentMenu,'Text',sprintf('%d  %s',k,[n e]), ...
                    'Tooltip',r{k},'MenuSelectedFcn',@(~,~) obj.openRecent(r{k}));
            end
        end

        % --- callbacks -------------------------------------------------------
        function onSource(obj,src)
            obj.setSource(src);
            [~,warn] = obj.describeRig();
            if warn
                obj.setStatus('Hardware changed — but the rig cannot be reached as it stands (see above).');
            else
                obj.setStatus('Hardware changed. Windows already open keep the rig they were opened with.');
            end
        end

        function onAudio(obj)
            a = obj.audio();
            try
                mabr.ui.AudioSettingsDialog(a,a.config(),@(s) obj.applyAudio(s));
            catch me
                obj.fail('Audio settings',me);
            end
            if obj.isOpen(), figure(obj.Figure); end
            obj.syncRig();
        end

        function applyAudio(obj,s)
            if ~isempty(obj.AudioApplyFcn)
                obj.AudioApplyFcn(s);
            else
                obj.OwnAudio = s;
                mabr.AudioSettings.savePrefs(s);
            end
            obj.syncRig();
            obj.setStatus('Audio settings applied. Windows already open keep the rig they were opened with.');
        end

        function onOpenBank(obj)
            file = obj.pickFile({'*.spl','Stimulus Banks (*.spl)'},'Open Bank in Designer');
            if ~isempty(file), obj.openDesigner(file); end
        end

        function openRecent(obj,file)
            if ~isfile(file)
                obj.forgetFile(file);
                obj.setStatus(['That file is gone, so it was dropped from the list: ' file],true);
                return
            end
            switch lower(fileparts_ext(file))
                case '.esgc', obj.loadCalibration(file);
                case '.spl',  obj.openDesigner(file);
                otherwise,    obj.openInspector(file);
            end

            function e = fileparts_ext(p)
                [~,~,e] = fileparts(p);
            end
        end
    end

    % ===================================================================
    methods (Static, Access = private)
        function file = iconFile(key)
            % A PNG (with real transparency) for a tool button, drawn once
            % and kept in the temp folder: uibutton takes an image file, and
            % the toolbox ships no binary assets, so they are painted here.
            % Empty on any failure -- a button without a picture still works.
            file = '';
            try
                dirName = fullfile(tempdir,'mabr_stimgen_icons');
                if ~isfolder(dirName), mkdir(dirName); end
                file = fullfile(dirName,[key '_v1.png']);
                if isfile(file), return; end
                [rgb,alpha] = mabr.ui.StimgenLauncher.drawIcon(key);
                imwrite(rgb,file,'Alpha',alpha);
            catch
                file = '';
            end
        end

        function [rgb,alpha] = drawIcon(key)
            % 48 px glyphs, painted at 4x and box-filtered down so the edges
            % are anti-aliased. Blue ink for the object, orange for the thing
            % it measures or does.
            N = 48; S = 4; M = N*S;
            [X,Y] = meshgrid(((1:M)-0.5)/M);
            ink = [0.16 0.34 0.58];
            acc = [0.90 0.48 0.10];
            c = struct('R',zeros(M),'G',zeros(M),'B',zeros(M),'A',false(M));
            P = @mabr.ui.StimgenLauncher.paint;
            D = @mabr.ui.StimgenLauncher.segDist;
            C = @mabr.ui.StimgenLauncher.curveDist;

            switch key
                case 'designer'      % a tone burst over its baseline
                    c = P(c,D(X,Y,[0.08 0.80],[0.92 0.80]) <= 0.022,ink);
                    px = linspace(0.08,0.92,300);
                    env = sin(pi*(px-0.08)/0.84).^2;
                    py = 0.44 - 0.30*env.*sin(2*pi*5*(px-0.08)/0.84);
                    c = P(c,C(X,Y,px,py) <= 0.032,acc);

                case 'calibration'   % gauge: arc, ticks, needle, hub
                    ctr = [0.50 0.68];
                    d = hypot(X-ctr(1),Y-ctr(2));
                    c = P(c,d >= 0.31 & d <= 0.40 & Y <= ctr(2)+0.01,ink);
                    for th = linspace(pi,0,7)
                        a0 = ctr + 0.22*[cos(th) -sin(th)];
                        a1 = ctr + 0.27*[cos(th) -sin(th)];
                        c = P(c,D(X,Y,a0,a1) <= 0.014,ink);
                    end
                    tip = ctr + 0.30*[cos(pi*0.30) -sin(pi*0.30)];
                    c = P(c,D(X,Y,ctr,tip) <= 0.024,acc);
                    c = P(c,d <= 0.055,ink);

                case 'spotcheck'     % microphone, and a tick for "checked"
                    cx = 0.34;
                    capsule = D(X,Y,[cx 0.20],[cx 0.38]) <= 0.10;
                    dCup = hypot(X-cx,max(0,Y-0.38));
                    cradle = dCup >= 0.155 & dCup <= 0.20 & Y >= 0.34;
                    stem = X >= cx-0.02 & X <= cx+0.02 & Y >= 0.56 & Y <= 0.78;
                    base = X >= cx-0.13 & X <= cx+0.13 & Y >= 0.78 & Y <= 0.83;
                    c = P(c,capsule | cradle | stem | base,ink);
                    tick = [0.60 0.64; 0.71 0.77; 0.92 0.46];
                    for k = 1:2
                        c = P(c,D(X,Y,tick(k,:),tick(k+1,:)) <= 0.042,acc);
                    end

                case 'inspector'     % magnifier with a waveform in the glass
                    ctr = [0.42 0.42];
                    d = hypot(X-ctr(1),Y-ctr(2));
                    c = P(c,d >= 0.28 & d <= 0.365,ink);
                    c = P(c,D(X,Y,[0.64 0.64],[0.88 0.88]) <= 0.055,ink);
                    px = linspace(0.22,0.62,120);
                    py = 0.42 - 0.11*sin(2*pi*2*(px-0.22)/0.40) .* sin(pi*(px-0.22)/0.40).^0.5;
                    c = P(c,C(X,Y,px,py) <= 0.026,acc);

                otherwise
                    error('mabr:ui:StimgenLauncher:noIcon','No icon named "%s".',key);
            end

            blk = @(Z) squeeze(mean(mean(reshape(Z,S,N,S,N),1),3));
            a = double(c.A);
            alpha = blk(a);
            w = max(alpha,eps);
            rgb = cat(3,blk(c.R.*a)./w,blk(c.G.*a)./w,blk(c.B.*a)./w);
            rgb = min(max(rgb,0),1);
        end

        function c = paint(c,mask,rgb)
            c.R(mask) = rgb(1); c.G(mask) = rgb(2); c.B(mask) = rgb(3);
            c.A(mask) = true;
        end

        function d = segDist(X,Y,a,b)
            % Distance from every point to the segment a-b.
            ab = b - a;
            t = ((X-a(1))*ab(1) + (Y-a(2))*ab(2)) / (ab*ab.');
            t = min(max(t,0),1);
            d = hypot(X-(a(1)+t*ab(1)),Y-(a(2)+t*ab(2)));
        end

        function d = curveDist(X,Y,px,py)
            % Distance from every point to the polyline through (px,py).
            d = inf(size(X));
            for k = 1:numel(px)-1
                d = min(d,mabr.ui.StimgenLauncher.segDist(X,Y,[px(k) py(k)],[px(k+1) py(k+1)]));
            end
        end
    end
end
