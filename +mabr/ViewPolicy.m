classdef ViewPolicy
% mabr.ViewPolicy  Which MABR windows open by themselves when a schedule starts.
%
%   The fifth of MABR's plain value objects, alongside mabr.ArtifactPolicy,
%   mabr.FilterPolicy and mabr.AudioSettings, and owned by mabr.ui.App the
%   same way: one field per viewer window, loadPrefs/savePrefs for the "last
%   used" persistence in the MABR pref group, toStruct/fromStruct for the
%   save/load configuration file.
%
%   What it decides is only what opens BY ITSELF at Start -- every one of
%   these windows is still one toolbar press away at any moment, and one
%   already open is never closed by it. Which windows a rig wants up while it
%   acquires is genuinely a per-rig habit: one operator watches the traces and
%   the growing stack, another wants the analysis window and the progress
%   monitor and nothing else, and until now that habit cost two closes and two
%   presses at every single Start.
%
%   The defaults reproduce what MABR did before this was a setting: the live
%   view and the trace organizer, and nothing else.
%
%       v = mabr.ViewPolicy.loadPrefs();
%       v = v.setOpen('ProgressMonitor',true);
%       mabr.ViewPolicy.savePrefs(v);
%
%   Two interactions are deliberately NOT expressed here, because they are
%   rules about the run rather than preferences about the layout:
%
%     * the trace organizer additionally needs "Send blocks to trace
%       organizer" (mabr.ui.App.traceTransferEnabled) -- with the transfer
%       off nothing would ever arrive in it, and a window that stays empty
%       for a whole session is worse than one the user opened deliberately;
%     * a STIMULATION-ONLY schedule records nothing, so it opens the progress
%       monitor alone whatever is set here (see mabr.ui.App.onStart). There is
%       no trace to plot and no metric to compute from; the plan walking
%       itself run by run is the only thing there is to watch.
%
% Daniel Stolzberg (c) 2019-2026

    properties
        % The live acquisition view (mabr.ui.LivePlot): the latest sweep and
        % the running mean per condition. On by default -- it is what the
        % operator watches while a block runs.
        LivePlot        (1,1) logical = true
        % The stacked-waveform viewer (mabr.ui.TraceOrganizer), which gains a
        % trace as each block finalizes. On by default, subject to the
        % transfer preference above.
        TraceOrganizer  (1,1) logical = true
        % The schedule's progress (mabr.ui.ProgressMonitor). Off by default:
        % it answers a question asked occasionally rather than one watched
        % continuously -- but a rig running long interleaved plans often wants
        % it up throughout, which is the whole reason this is a setting.
        ProgressMonitor (1,1) logical = false
        % One online-analysis window (mabr.ui.MetricPlot), opened only when
        % none is already up: the window is deliberately not a singleton, but
        % opening a NEW one at every Start would stack them up a session at a
        % time.
        Analysis        (1,1) logical = false
        % The stimulus bank inspector (mabr.ui.StimulusViewer). Off by
        % default: it shows what is about to be played, which is a question
        % asked before Start rather than during.
        StimulusViewer  (1,1) logical = false
        % The rig notebook (mabr.ui.Notes). Off by default, since the toolbar
        % button is one press -- on for an operator who takes notes through
        % every run and would rather have the field already open.
        Notes           (1,1) logical = false
    end

    methods
        function tf = opens(obj,name)
            % Does the window called `name` open at Start? Unknown names
            % answer false rather than erroring -- callers ask by string and a
            % configuration file may name a window this MABR no longer has.
            name = char(name);
            tf = isprop(obj,name) && any(strcmp(name,mabr.ViewPolicy.names())) ...
                 && obj.(name);
        end

        function obj = setOpen(obj,name,tf)
            % Value-object setter: returns the modified copy. Silently ignores
            % a name this class does not carry, for the same reason opens does.
            name = char(name);
            if any(strcmp(name,mabr.ViewPolicy.names()))
                obj.(name) = logical(tf);
            end
        end

        function n = count(obj)
            n = sum(cellfun(@(f) obj.(f),mabr.ViewPolicy.names()));
        end

        function txt = summary(obj)
            % One line naming what will open, for the status bar.
            fields = mabr.ViewPolicy.names();
            lbl    = mabr.ViewPolicy.labels();
            on     = cellfun(@(f) obj.(f),fields);
            if ~any(on)
                txt = 'No windows open automatically at Start.';
                return
            end
            txt = ['Opens at Start: ' strjoin(lower(lbl(on)),', ') '.'];
        end

        function s = toStruct(obj)
            % Plain-struct snapshot for the save/load configuration file --
            % distinct from loadPrefs/savePrefs's "last used" persistence,
            % though both travel through the same validated fields.
            s = struct();
            for f = mabr.ViewPolicy.names()
                s.(f{1}) = obj.(f{1});
            end
        end
    end

    methods (Static)
        function n = names()
            % The property names, in the order the Settings submenu offers
            % them (which is the toolbar's order, so the menu reads like the
            % row of buttons it is talking about).
            n = {'LivePlot','Analysis','TraceOrganizer','StimulusViewer', ...
                 'ProgressMonitor','Notes'};
        end

        function l = labels()
            % Human names for the same list, in the same order.
            l = {'Live plot','Online analysis','Trace organizer', ...
                 'Stimulus viewer','Progress monitor','Session notes'};
        end

        function obj = loadPrefs()
            % Restore the last session's choice, falling back to the property
            % default for anything never saved or saved invalid -- a pref
            % edited by hand must not stop the app from opening.
            obj = mabr.ViewPolicy;
            for f = mabr.ViewPolicy.names()
                obj.(f{1}) = mabr.ViewPolicy.getLogical(f{1},obj.(f{1}));
            end
        end

        function savePrefs(obj)
            for f = mabr.ViewPolicy.names()
                setpref('MABR',['ViewOpen' f{1}],obj.(f{1}));
            end
        end

        function obj = fromStruct(s)
            % Inverse of toStruct, forgiving field by field.
            obj = mabr.ViewPolicy;
            if ~isstruct(s) || ~isscalar(s), return; end
            for f = mabr.ViewPolicy.names()
                if isfield(s,f{1})
                    obj.(f{1}) = mabr.ViewPolicy.coerceLogical(s.(f{1}),obj.(f{1}));
                end
            end
        end
    end

    methods (Static, Access = private)
        function v = getLogical(name,default)
            v = mabr.ViewPolicy.coerceLogical( ...
                    getpref('MABR',['ViewOpen' name],default),default);
        end

        function v = coerceLogical(v,default)
            if ~islogical(v) && ~(isnumeric(v) && isscalar(v)), v = default; end
            v = logical(v);
        end
    end
end
